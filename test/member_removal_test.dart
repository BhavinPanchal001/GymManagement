import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
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
    if (key.endsWith('gym_financial_v1')) return false;
    return super.setValue(valueType, key, value);
  }
}

class _BlockingStore extends InMemorySharedPreferencesStore {
  _BlockingStore(super.data) : super.withData();

  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('gym_financial_v1') && !started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/material_fonts').existsSync() &&
        directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = await File(
        '${directory.path}/material_fonts/Roboto-$weight.ttf',
      ).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

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
    test('permanent deletion cascades and removes attendance: ${status.name}', () async {
      final customer = await member();
      await gym.toggleAttendance(customer.id, '2024-01-20', status);
      expect(gym.attendanceMap, isNotEmpty);
      await gym.permanentlyDeleteCustomer(customer.id);
      expect(gym.getCustomerById(customer.id), isNull);
      expect(gym.attendanceMap, isEmpty);
    });
  }

  test(
    'permanent deletion cascades and removes unpaid agreements and paid receipts',
    () async {
      final unpaid = await gym.addCustomer(
        name: 'Unpaid Member',
        phone: '9000000002',
        membershipStartDate: DateTime(2024, 1, 1),
        membershipFee: 600,
      );
      expect(gym.paymentMap.values.any((p) => p.customerId == unpaid.id), isTrue);
      await gym.permanentlyDeleteCustomer(unpaid.id);
      expect(gym.getCustomerById(unpaid.id), isNull);
      expect(gym.paymentMap.values.any((p) => p.customerId == unpaid.id), isFalse);

      final paid = await member();
      await gym.markPaymentAsPaid(
        customerId: paid.id,
        monthYear: '2024-01',
        amount: 600,
        totalDue: 600,
        method: PaymentMethod.cash,
        startDate: DateTime(2024, 1, 1),
      );
      expect(gym.paymentMap.values.any((p) => p.customerId == paid.id), isTrue);
      expect(gym.billsMap.values.any((b) => b.customerId == paid.id), isTrue);
      await gym.permanentlyDeleteCustomer(paid.id);
      expect(gym.getCustomerById(paid.id), isNull);
      expect(gym.paymentMap.values.any((p) => p.customerId == paid.id), isFalse);
      expect(gym.billsMap.values.any((b) => b.customerId == paid.id), isFalse);
    },
  );

  test('permanent deletion cascades and removes cancelled standalone receipts', () async {
    final customer = await member();
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2024-01',
      amount: 600,
      totalDue: 600,
      method: PaymentMethod.cash,
      startDate: DateTime(2024, 1, 1),
    );
    final payment = gym.paymentMap.values.firstWhere((p) => p.customerId == customer.id);
    await gym.revertPayment(payment.id);
    expect(gym.billsMap.values.any((b) => b.customerId == customer.id && b.status == 'CANCELLED'), isTrue);
    await gym.permanentlyDeleteCustomer(customer.id);
    expect(gym.getCustomerById(customer.id), isNull);
    expect(gym.billsMap.values.any((b) => b.customerId == customer.id), isFalse);
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
    'concurrent single and bulk attendance cannot outlive removal',
    () async {
      final customer = await member();
      final deletion = gym.permanentlyDeleteCustomer(customer.id);
      final attendance = [
        gym.toggleAttendance(
          customer.id,
          '2024-01-20',
          AttendanceStatus.present,
        ),
        gym.markAllPresentForDate('2024-01-21'),
        gym.setMonthAttendance(
          customerId: customer.id,
          year: 2024,
          month: 1,
          status: AttendanceStatus.absent,
        ),
        gym.setMonthAttendanceForMultiple(
          customerIds: [customer.id],
          year: 2024,
          month: 1,
          status: AttendanceStatus.rest,
        ),
      ];
      await deletion;
      await Future.wait(attendance);
      expect(gym.getCustomerById(customer.id), isNull);
      expect(
        gym.attendanceMap.values.where((a) => a.customerId == customer.id),
        isEmpty,
      );
    },
  );

  test(
    'attendance arriving during the durable deletion write waits for removal',
    () async {
      final customer = await member();
      final blocking = _BlockingStore(
        await SharedPreferencesStorePlatform.instance.getAll(),
      );
      SharedPreferencesStorePlatform.instance = blocking;
      final deletion = gym.permanentlyDeleteCustomer(customer.id);
      await blocking.started.future;
      final attendance = gym.toggleAttendance(
        customer.id,
        '2024-01-20',
        AttendanceStatus.present,
      );
      expect(gym.getAttendance(customer.id, '2024-01-20'), isNull);
      blocking.release.complete();
      await Future.wait([deletion, attendance]);
      expect(gym.getCustomerById(customer.id), isNull);
      expect(gym.getAttendance(customer.id, '2024-01-20'), isNull);
    },
  );

  test('attendance queued first is cleaned up by removal', () async {
    final customer = await member();
    final attendance = gym.toggleAttendance(
      customer.id,
      '2024-01-20',
      AttendanceStatus.absent,
    );
    await attendance;
    expect(gym.getAttendance(customer.id, '2024-01-20'), isNotNull);
    await gym.permanentlyDeleteCustomer(customer.id);
    expect(gym.getCustomerById(customer.id), isNull);
    expect(gym.getAttendance(customer.id, '2024-01-20'), isNull);
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
    expect(deleteTile.enabled, isTrue);
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
    'history added during confirmation is cascade-deleted on permanent deletion',
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
      expect(gym.getCustomerById(customer.id), isNull);
      expect(gym.attendanceMap, isEmpty);
      expect(find.text('Member permanently deleted.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open menu follows the latest archive state', (tester) async {
    final customer = await member();
    await openProfile(tester, customer);
    await openRemovalMenu(tester);
    await gym.archiveCustomer(customer.id);
    await tester.pumpAndSettle();
    expect(find.text('Archive member'), findsNothing);
    expect(find.text('Restore member'), findsOneWidget);
    await tester.tap(find.text('Restore member'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();
    expect(gym.getCustomerById(customer.id)?.isActive, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions are disabled if member disappears with the menu open', (
    tester,
  ) async {
    final customer = await member();
    await openProfile(tester, customer);
    await openRemovalMenu(tester);
    await gym.permanentlyDeleteCustomer(customer.id);
    await tester.pumpAndSettle();
    for (final title in ['Restore member', 'Delete permanently']) {
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, title)).enabled,
        isFalse,
      );
    }
    expect(find.text('Member not found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archive confirmation detects a changed member', (tester) async {
    final customer = await member();
    await openProfile(tester, customer);
    await openRemovalMenu(tester);
    await tester.tap(find.text('Archive member'));
    await tester.pumpAndSettle();
    await gym.archiveCustomer(customer.id);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(
      find.text('Member changed. Please reopen Remove Member.'),
      findsOneWidget,
    );
    expect(find.text('Member archived. History preserved.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
