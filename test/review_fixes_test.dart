import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/screens/reports/pending_payments_report_screen.dart';
import 'package:gym/screens/reports/export_report_dialog.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';
import 'package:gym/utils/date_utils.dart';

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore(super.data) : super.withData();
  String? rejectedSuffix;
  bool throwOnWrite = false;
  bool rejectRepeatedly = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectedSuffix != null && key.endsWith(rejectedSuffix!)) {
      if (!rejectRepeatedly) rejectedSuffix = null;
      if (throwOnWrite) throw StateError('disk unavailable');
      return false;
    }
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
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 600));
  });
  tearDown(() async => gym.detachUser());

  Future<Customer> member() => gym.addCustomer(
    name: 'Review member',
    phone: '9000000000',
    joinDate: DateTime(2024, 1, 1),
  );

  Future<FailingStore> failingStore() async {
    final store = FailingStore(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  Future<PaymentRecord> legacyPayment(Customer c, {bool dated = true}) async {
    final payment = PaymentRecord(
      id: 'pay_legacy_1720000000000',
      customerId: c.id,
      monthYear: '2024-01',
      amount: 1200,
      totalDue: 600,
      status: PaymentStatus.paid,
      method: PaymentMethod.cash,
      paidAt: dated ? DateTime(2024, 1, 10) : null,
      transactionRef: 'old-reference',
    );
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({
      'gym_legacy-owner_customers_v1': json.encode([c.toMap()]),
      'gym_legacy-owner_payments_v1': json.encode([payment.toMap()]),
    });
    await gym.attachUser('legacy-owner');
    expect(gym.getPaymentById(payment.id)!.amount, 1200);
    return gym.getPaymentById(payment.id)!;
  }

  for (final throws in [false, true]) {
    test(
      'failed balance queue write ($throws) leaves no money or receipt',
      () async {
        await gym.attachUser('review-owner');
        final c = await member();
        final original = await gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: '2024-01',
          amount: 200,
          totalDue: 600,
          method: PaymentMethod.cash,
          startDate: DateTime(2024, 1, 1),
        );
        final store = await failingStore()
          ..rejectedSuffix = 'cloud_outbox_v1'
          ..throwOnWrite = throws;
        Future<BillRecord> collect() => gym.collectBalance(
          paymentId: original.paymentId,
          amount: 100,
          method: PaymentMethod.cash,
          operationId: 'balance-retry',
        );
        await expectLater(collect(), throwsStateError);
        expect(gym.getPaymentById(original.paymentId)!.amount, 200);
        expect(gym.getBillsForPayment(original.paymentId), hasLength(1));
        await collect();
        await collect();
        expect(gym.getPaymentById(original.paymentId)!.amount, 300);
        expect(gym.getBillsForPayment(original.paymentId), hasLength(2));
        final persisted = await store.getAll();
        final batches =
            json.decode(
                  persisted['flutter.gym_review-owner_cloud_outbox_v1']!
                      as String,
                )
                as List;
        final changes = batches.expand((b) => b['changes'] as List).toList();
        final payments = changes.where((c) => c['collection'] == 'payments');
        final receipts = changes.where((c) => c['collection'] == 'bills');
        expect(payments.last['data']['amount'], 300);
        expect(
          receipts.fold<num>(0, (sum, b) => sum + (b['data']['amount'] as num)),
          300,
        );
        await gym.detachUser();
        await gym.attachUser('review-owner');
        await collect();
        expect(gym.getPaymentById(original.paymentId)!.amount, 300);
        expect(gym.getBillsForPayment(original.paymentId), hasLength(2));
      },
    );
  }

  test('initial payment retry makes one payment and one receipt', () async {
    await gym.attachUser('review-owner');
    final c = await member();
    final store = await failingStore();
    store.rejectedSuffix = 'cloud_outbox_v1';
    Future<BillRecord> pay() => gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: '2024-01',
      amount: 200,
      totalDue: 600,
      method: PaymentMethod.cash,
      startDate: DateTime(2024, 1, 1),
      operationId: 'payment-retry',
    );
    await expectLater(pay(), throwsStateError);
    expect(gym.getPaidPaymentsForCustomer(c.id), isEmpty);
    expect(gym.getAllBillsForCustomer(c.id), isEmpty);
    await Future.wait([pay(), pay()]);
    expect(gym.getPaidPaymentsForCustomer(c.id), hasLength(1));
    expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
  });

  for (final suffix in ['financial_v1', 'payments_v1', 'bills_v1']) {
    test('committed collection survives failed $suffix refresh', () async {
      await gym.attachUser('review-owner');
      final c = await member();
      final store = await failingStore();
      store.rejectedSuffix = suffix;
      store.rejectRepeatedly = true;
      final receipt = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-01',
        amount: 200,
        totalDue: 600,
        method: PaymentMethod.cash,
        startDate: DateTime(2024, 1, 1),
        operationId: 'cache-failure',
      );
      expect(gym.getPaymentById(receipt.paymentId)!.amount, 200);
      expect(gym.syncError, isNotNull);
      await gym.detachUser();
      store.rejectedSuffix = null;
      await gym.attachUser('review-owner');
      final retried = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-01',
        amount: 200,
        method: PaymentMethod.cash,
        operationId: 'cache-failure',
      );
      expect(retried.id, receipt.id);
      expect(gym.getPaidPaymentsForCustomer(c.id), hasLength(1));
      expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
    });
  }

  test('local payment commits both records or neither', () async {
    final c = await member();
    final store = await failingStore();
    store.rejectedSuffix = 'financial_v1';
    await expectLater(
      gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-01',
        amount: 600,
        method: PaymentMethod.cash,
      ),
      throwsStateError,
    );
    expect(gym.getPaidPaymentsForCustomer(c.id), isEmpty);
    expect(gym.getAllBillsForCustomer(c.id), isEmpty);
  });

  test(
    'indexed debts retain coverage gaps and refresh after financial edits',
    () async {
      final c = await member();
      for (final date in [
        DateTime(2024, 1, 10),
        DateTime(2024, 1, 15),
        DateTime(2024, 2, 14),
        DateTime(2024, 2, 15),
      ]) {
        await gym.toggleAttendance(
          c.id,
          GymDateUtils.toDateKey(date),
          AttendanceStatus.present,
        );
      }
      final receipt = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-01',
        startDate: DateTime(2024, 1, 15),
        endDate: DateTime(2024, 2, 14),
        amount: 200,
        totalDue: 600,
        method: PaymentMethod.cash,
      );
      expect(gym.getUnpaidAttendedDaysInMonth(c.id, '2024-01'), 1);
      expect(gym.getUnpaidAttendedDaysInMonth(c.id, '2024-02'), 1);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1600);
      final cached = gym.getAllPendingDues().single;
      expect(identical(cached, gym.getAllPendingDues().single), isTrue);
      final start = gym.outstandingStartDate;
      final end = gym.outstandingEndDate;
      expect(
        gym
            .getPendingDuesByMonth(end, start)
            .fold<double>(0, (sum, group) => sum + group.totalAmount),
        1600,
      );
      await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-02',
        startDate: DateTime(2024, 2, 15),
        endDate: DateTime(2024, 3, 14),
        amount: 600,
        method: PaymentMethod.cash,
      );
      expect(gym.getUnpaidAttendedDaysInMonth(c.id, '2024-02'), 0);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1000);
      await gym.collectBalance(
        paymentId: receipt.paymentId,
        amount: 400,
        method: PaymentMethod.cash,
      );
      expect(gym.getAllPendingDues().single.totalPendingAmount, 600);
      await gym.toggleAttendance(c.id, '2024-01-10', AttendanceStatus.absent);
      expect(gym.getAllPendingDues(), isEmpty);
    },
  );

  test(
    'upload-status notifications reuse the same pending calculation',
    () async {
      await gym.attachUser('review-owner');
      final c = await member();
      await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2024-01',
        startDate: DateTime(2024, 1, 1),
        amount: 200,
        totalDue: 600,
        method: PaymentMethod.cash,
      );
      final cached = gym.getAllPendingDues().single;
      await gym.retryCloudSync();
      expect(identical(cached, gym.getAllPendingDues().single), isTrue);
    },
  );

  for (final received in [0.0, 200.0, 600.0]) {
    test('archive and restore preserve debt with $received received', () async {
      final c = await member();
      await gym.toggleAttendance(c.id, '2024-01-15', AttendanceStatus.present);
      if (received > 0) {
        await gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: '2024-01',
          startDate: DateTime(2024, 1, 1),
          amount: received,
          totalDue: 600,
          method: PaymentMethod.cash,
        );
      }
      double total() => gym.getAllPendingDues().fold<double>(
        0,
        (sum, member) => sum + member.totalPendingAmount,
      );
      expect(total(), 600 - received);
      await gym.archiveCustomer(c.id);
      expect(gym.getCustomerById(c.id)!.isActive, isFalse);
      expect(total(), 600 - received);
      expect(
        gym
            .getPendingDuesByMonth(DateTime(2024, 1), DateTime(2024, 1, 31))
            .fold<double>(0, (sum, month) => sum + month.totalAmount),
        600 - received,
      );
      await gym.restoreCustomer(c.id);
      expect(gym.getCustomerById(c.id)!.isActive, isTrue);
      expect(total(), 600 - received);
    });
  }

  testWidgets('All Outstanding includes older data arriving after opening', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PendingPaymentsReportScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review member'), findsNothing);
    final c = await member();
    await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: '2024-01',
      amount: 200,
      totalDue: 600,
      startDate: DateTime(2024, 1, 1),
      method: PaymentMethod.cash,
    );
    await tester.pumpAndSettle();
    expect(find.text('Review member'), findsOneWidget);
    expect(find.textContaining('Jan 2024'), findsWidgets);
    expect(gym.getAllPendingDues().single.totalPendingAmount, 400);
    await tester.tap(find.text('This Month'));
    await tester.pumpAndSettle();
    expect(find.text('Review member'), findsNothing);
    await gym.updatePayment(
      paymentId: gym.getPaidPaymentsForCustomer(c.id).single.id,
      notes: 'Older data changed',
    );
    await tester.pumpAndSettle();
    expect(find.text('Review member'), findsNothing);
    await tester.tap(find.text('All Outstanding'));
    await tester.pumpAndSettle();
    expect(find.text('Review member'), findsOneWidget);
    final future = DateTime(DateTime.now().year + 1, 2, 1);
    await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: GymDateUtils.toMonthKey(future),
      amount: 200,
      totalDue: 600,
      startDate: future,
      method: PaymentMethod.cash,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export & Share Report'));
    await tester.pumpAndSettle();
    final export = tester.widget<ExportReportDialog>(
      find.byType(ExportReportDialog),
    );
    expect(export.startDate, DateTime(2024, 1, 1));
    expect(export.endDate, DateTime(future.year, future.month + 1, 0));
    expect(export.totalPending, 800);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'legacy reference corrections preserve cash and support fee reconciliation',
    () async {
      final c = await member();
      final old = await legacyPayment(c);
      final originalBill = gym.getOrCreateBillForPayment(c, old);
      final corrected = await gym.updatePayment(
        paymentId: old.id,
        notes: 'Corrected note',
        transactionRef: 'correct-reference',
      );
      final updated = gym.getPaymentById(old.id)!;
      expect(updated.amount, 1200);
      expect(updated.totalDue, 600);
      expect(updated.startDate, old.startDate);
      expect(updated.endDate, old.endDate);
      expect(updated.paidAt, old.paidAt);
      expect(corrected.amount, originalBill.amount);
      expect(corrected.billNumber, originalBill.billNumber);
      expect(corrected.transactionRef, 'correct-reference');
      expect(corrected.notes, 'Corrected note');
      await expectLater(
        gym.updatePayment(paymentId: old.id, amount: 1300),
        throwsArgumentError,
      );
      await expectLater(
        gym.updatePayment(paymentId: old.id, totalDue: 500),
        throwsArgumentError,
      );
      await gym.updatePayment(paymentId: old.id, totalDue: 1500);
      expect(gym.getPaymentById(old.id)!.amount, 1200);
      expect(gym.getPaymentById(old.id)!.balanceDue, 300);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 300);
      expect(
        gym.getBillForPayment(old.id)!.billNumber,
        originalBill.billNumber,
      );
    },
  );

  for (final dated in [true, false]) {
    testWidgets(
      'legacy dialog corrects reference without changing money ($dated)',
      (tester) async {
        final c = await member();
        final old = await legacyPayment(c, dated: dated);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkPaymentDialog(
                customer: c,
                monthYear: old.monthYear,
                currentRecord: old,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final reference = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == 'old-reference',
        );
        await tester.ensureVisible(reference);
        await tester.enterText(reference, 'correct-reference');
        await tester.ensureVisible(find.text('Update Payment Record'));
        await tester.tap(find.text('Update Payment Record'));
        await tester.pumpAndSettle();
        final updated = gym.getPaymentById(old.id)!;
        expect(updated.amount, 1200);
        expect(updated.totalDue, 600);
        expect(updated.startDate, old.startDate);
        expect(updated.endDate, old.endDate);
        expect(updated.paidAt, old.paidAt);
        expect(updated.transactionRef, 'correct-reference');
        expect(gym.getBillsForPayment(old.id).single.amount, 1200);
        if (dated) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MarkPaymentDialog(
                  customer: c,
                  monthYear: updated.monthYear,
                  currentRecord: updated,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final fee = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText ==
                    'Correct membership fee (optional)',
          );
          await tester.ensureVisible(fee);
          await tester.enterText(fee, '1500');
          await tester.ensureVisible(find.text('Update Payment Record'));
          await tester.tap(find.text('Update Payment Record'));
          await tester.pumpAndSettle();
          expect(gym.getPaymentById(old.id)!.amount, 1200);
          expect(gym.getPaymentById(old.id)!.balanceDue, 300);
          expect(gym.getBillsForPayment(old.id).single.amount, 1200);
        }
        await gym.detachUser();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
