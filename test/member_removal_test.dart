import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/cloud_sync_queue.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'gym_financial_v1') return false;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });

  tearDown(() => gym.detachUser());

  Future<Customer> member() => gym.addCustomer(
    name: 'Mistaken Member',
    phone: '9876543210',
    cardNumber: 'REMOVE-1',
    joinDate: DateTime(2024, 1, 1),
  );

  test(
    'permanent deletion updates both caches and frees the card number',
    () async {
      final customer = await member();
      final other = await gym.addCustomer(
        name: 'Keep Member',
        phone: '9000000001',
      );
      expect(gym.customerDeletionBlockReason(customer.id), isNull);

      await gym.permanentlyDeleteCustomer(customer.id);

      expect(gym.getCustomerById(customer.id), isNull);
      expect(gym.searchCustomers('Mistaken'), isEmpty);
      expect(gym.getCustomerByCardNumber('REMOVE-1'), isNull);
      expect(gym.getCustomerById(other.id), isNotNull);
      final prefs = await SharedPreferences.getInstance();
      final customers =
          json.decode(prefs.getString('gym_customers_v1')!) as List;
      final financial =
          json.decode(prefs.getString('gym_financial_v1')!) as Map;
      expect(customers.map((c) => c['id']), [other.id]);
      expect((financial['customers'] as List).map((c) => c['id']), [other.id]);
      // Reload through the same cache loader used after signing in again.
      await prefs.setString(
        'gym_reload-owner_customers_v1',
        json.encode(customers),
      );
      await prefs.setString(
        'gym_reload-owner_financial_v1',
        json.encode(financial),
      );
      await gym.attachUser('reload-owner');
      expect(gym.getCustomerById(customer.id), isNull);
      expect(gym.getCustomerById(other.id), isNotNull);
      final replacement = await gym.addCustomer(
        name: 'Correct Member',
        phone: '9000000002',
        cardNumber: 'REMOVE-1',
      );
      expect(replacement.cardNumber, 'REMOVE-1');
    },
  );

  test('archived history-free entries can also be deleted', () async {
    final customer = await member();
    await gym.archiveCustomer(customer.id);
    await gym.permanentlyDeleteCustomer(customer.id);
    expect(gym.getCustomerById(customer.id), isNull);
  });

  for (final status in AttendanceStatus.values) {
    test('any recorded attendance blocks deletion: ${status.name}', () async {
      final customer = await member();
      await gym.toggleAttendance(customer.id, '2024-01-20', status);
      final attendance = gym.attendanceMap;
        expect(attendance, isNotEmpty);
      await expectLater(
        gym.permanentlyDeleteCustomer(customer.id),
        throwsStateError,
      );
      expect(gym.getCustomerById(customer.id), isNotNull);
      expect(gym.attendanceMap, attendance);
    });
  }

  test(
    'unpaid membership agreements and paid receipts block deletion',
    () async {
      final unpaid = await gym.addCustomer(
        name: 'Unpaid Member',
        phone: '9000000002',
        membershipStartDate: DateTime(2024, 1, 1),
        membershipFee: 600,
      );
      await expectLater(
        gym.permanentlyDeleteCustomer(unpaid.id),
        throwsStateError,
      );
      expect(gym.getCustomerById(unpaid.id), isNotNull);

      final paid = await member();
      await gym.markPaymentAsPaid(
        customerId: paid.id,
        monthYear: '2024-01',
        amount: 600,
        totalDue: 600,
        method: PaymentMethod.cash,
        startDate: DateTime(2024, 1, 1),
      );
      final payments = gym.paymentMap;
      final receipts = gym.billsMap;
      await expectLater(
        gym.permanentlyDeleteCustomer(paid.id),
        throwsStateError,
      );
      expect(gym.paymentMap, payments);
      expect(gym.billsMap, receipts);
      await gym.archiveCustomer(paid.id);
      await expectLater(
        gym.permanentlyDeleteCustomer(paid.id),
        throwsStateError,
      );
    },
  );

  test('cancelled standalone receipts still block deletion', () async {
    final customer = await member();
    final receipt = BillRecord(
      id: 'legacy-receipt',
      billNumber: 'LEGACY-1',
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      monthYear: '2024-01',
      amount: 600,
      paymentId: '',
      method: PaymentMethod.cash,
      paidAt: DateTime(2024, 1, 1),
      gymName: 'Gym',
      issuedAt: DateTime(2024, 1, 1),
      status: 'CANCELLED',
    );
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({
      'gym_receipt-owner_customers_v1': json.encode([customer.toMap()]),
      'gym_receipt-owner_bills_v1': json.encode([receipt.toMap()]),
      'payments_schema_v2': true,
    });
    await gym.attachUser('receipt-owner');
    expect(gym.customerDeletionBlockReason(customer.id), contains('receipts'));
    await expectLater(
      gym.permanentlyDeleteCustomer(customer.id),
      throwsStateError,
    );
    expect(gym.billsMap[receipt.id]?.status, 'CANCELLED');
  });

  test(
    'unavailable cloud cannot authorize deletion from an empty cache',
    () async {
      await gym.attachUser('offline-owner');
      final customer = await member();
      expect(
        gym.customerDeletionBlockReason(customer.id),
        contains('Connect and sync'),
      );
      await expectLater(
        gym.permanentlyDeleteCustomer(customer.id),
        throwsStateError,
      );
      expect(gym.getCustomerById(customer.id), isNotNull);
      await gym.archiveCustomer(customer.id);
      expect(gym.getCustomerById(customer.id)?.isActive, isFalse);
    },
  );

  test('failed durable save does not remove the member', () async {
    final customer = await member();
    SharedPreferencesStorePlatform.instance = _FailingStore(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    await expectLater(
      gym.permanentlyDeleteCustomer(customer.id),
      throwsStateError,
    );
    expect(gym.getCustomerById(customer.id), isNotNull);
    expect(gym.getCustomerByCardNumber('REMOVE-1')?.id, customer.id);
  });

  test(
    'customer tombstones survive outbox reload and overlay stale snapshots',
    () async {
      final prefs = await SharedPreferences.getInstance();
      CloudSyncQueue queue() => CloudSyncQueue(
        preferences: prefs,
        userId: 'delete-owner',
        upload: (_) async => throw StateError('offline'),
      );
      var outbox = queue();
      await outbox.enqueue([
        const CloudChange('customers', 'deleted', null),
      ], autoFlush: false);
      outbox.dispose();
      outbox = queue()..load();
      addTearDown(outbox.dispose);
      expect(
        outbox.overlay('customers', {
          'deleted': {'id': 'deleted'},
          'kept': {'id': 'kept'},
        }),
        {
          'kept': {'id': 'kept'},
        },
      );
      expect(outbox.pendingCount, 1);
    },
  );

  Future<void> openProfile(
    WidgetTester tester,
    Customer customer, {
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CustomerDetailScreen(customerId: customer.id),
                ),
              ),
              child: const Text('Member list'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Member list'));
    await tester.pumpAndSettle();
  }

  Future<void> openRemovalMenu(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove Member'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'labelled menu supports cancellation and permanent deletion on phones',
    (tester) async {
      final customer = await member();
      await openProfile(tester, customer, width: 320);
      await openRemovalMenu(tester);
      expect(find.text('Archive member'), findsOneWidget);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      expect(find.text('Delete member permanently?'), findsOneWidget);
      expect(find.textContaining('Card #REMOVE-1'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gym.getCustomerById(customer.id), isNotNull);

      await openRemovalMenu(tester);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
      await tester.pumpAndSettle();
      expect(gym.getCustomerById(customer.id), isNull);
      expect(find.text('Member list'), findsOneWidget);
      expect(find.text('Member permanently deleted.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('archive and restore require confirmation and retain history', (
    tester,
  ) async {
    final customer = await member();
    await gym.toggleAttendance(
      customer.id,
      '2024-01-20',
      AttendanceStatus.absent,
    );
    await openProfile(tester, customer);
    await openRemovalMenu(tester);
    final deleteTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Delete permanently'),
    );
    expect(deleteTile.enabled, isFalse);
    expect(find.textContaining('Archive instead'), findsOneWidget);
    await tester.tap(find.text('Archive member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gym.getCustomerById(customer.id)?.isActive, isTrue);

    await openRemovalMenu(tester);
    await tester.tap(find.text('Archive member'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(gym.getCustomerById(customer.id)?.isActive, isFalse);
    expect(find.text('Archived member • History preserved'), findsOneWidget);

    await openRemovalMenu(tester);
    await tester.tap(find.text('Restore member'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(gym.getCustomerById(customer.id)?.isActive, isTrue);
    expect(gym.getAttendance(customer.id, '2024-01-20'), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history added during confirmation is rechecked before deletion',
    (tester) async {
      final customer = await member();
      await openProfile(tester, customer);
      await openRemovalMenu(tester);
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      await gym.toggleAttendance(
        customer.id,
        '2024-01-20',
        AttendanceStatus.absent,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
      await tester.pumpAndSettle();
      expect(gym.getCustomerById(customer.id), isNotNull);
      expect(find.textContaining('Archive instead'), findsOneWidget);
      expect(find.byType(CustomerDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
