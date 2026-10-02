import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/plan_package.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/whatsapp_service.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';

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

  Future<Customer> register({DateTime? start, int months = 3}) =>
      gym.addCustomer(
        name: 'Credit member',
        phone: '9876543210',
        joinDate: DateTime(2024, 1, 1),
        planDurationMonths: months,
        membershipStartDate: start ?? DateTime(2024, 1, 15),
        membershipFee: months == 3 ? 1500.75 : 600.75,
        operationId: 'registration',
      );

  Future<void> settle(Customer c, {double amount = 500.25}) async {
    final agreement = gym.getCustomerPaymentHistory(c.id).single;
    await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: agreement.monthYear,
      agreementId: agreement.id,
      amount: amount,
      method: PaymentMethod.cash,
      durationMonths: agreement.durationMonths,
      startDate: agreement.startDate,
      endDate: agreement.endDate,
      operationId: 'first-collection',
    );
  }

  test(
    'pay later keeps dates and one charge without attendance, including after restart',
    () async {
      final c = await register();
      final agreement = gym.getCustomerPaymentHistory(c.id).single;
      expect(agreement.isPaid, isFalse);
      expect(agreement.startDate, DateTime(2024, 1, 15));
      expect(agreement.endDate, DateTime(2024, 4, 14));
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
      expect(
        gym.getMemberLifecycleStage(c, '2024-01'),
        MemberLifecycleStage.due,
      );
      expect(gym.billsMap, isEmpty);
      await gym.init();
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
      expect(gym.getCustomerPaymentHistory(c.id).single.id, agreement.id);
      expect((await register()).id, c.id);
      expect(gym.customers, hasLength(1));
    },
  );

  test('same-day pay-later registration remains available for welcome onboarding',
      () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final customer = await gym.addCustomer(
      name: 'New member',
      phone: '9876543212',
      joinDate: today,
      membershipStartDate: today,
      membershipFee: 600.75,
      operationId: 'new-member-registration',
    );

    expect(
      gym.getMemberLifecycleStage(
        customer,
        '${today.year}-${today.month.toString().padLeft(2, '0')}',
      ),
      MemberLifecycleStage.newMember,
    );
  });

  test(
    'multi-month credit package is charged once in its start month',
    () async {
      final c = await register();
      for (final date in ['2024-01-15', '2024-02-15', '2024-03-15']) {
        await gym.toggleAttendance(c.id, date, AttendanceStatus.present);
      }
      final groups = gym.getPendingDuesByMonth(
        DateTime(2024, 1),
        DateTime(2024, 4),
      );
      expect(groups, hasLength(1));
      expect(groups.single.monthKey, '2024-01');
      expect(groups.single.totalAmount, 1500.75);
      expect(gym.getCustomerPaymentHistory(c.id), hasLength(1));
    },
  );

  test(
    'explicit and attendance-derived fees remain frozen when package prices change',
    () async {
      final c = await register();
      final legacy = await gym.addCustomer(
        name: 'Existing member',
        phone: '9876543211',
        joinDate: DateTime(2024, 1, 1),
        planDurationMonths: 3,
      );
      await gym.toggleAttendance(
        legacy.id,
        '2024-01-15',
        AttendanceStatus.present,
      );
      await gym.toggleAttendance(
        legacy.id,
        '2024-02-15',
        AttendanceStatus.present,
      );
      await gym.updateSettings(
        gym.settings.copyWith(
          durationPackages: const [
            PlanDurationPackage(
              id: 'normal-three',
              planType: CustomerPlan.normal,
              months: 3,
              price: 2100,
            ),
          ],
        ),
      );
      final dues = gym.getAllPendingDues();
      expect(
        dues.singleWhere((s) => s.customer.id == c.id).totalPendingAmount,
        1500.75,
      );
      expect(
        dues.singleWhere((s) => s.customer.id == legacy.id).totalPendingAmount,
        1500,
      );
      await gym.toggleAttendance(
        legacy.id,
        '2024-03-15',
        AttendanceStatus.present,
      );
      expect(gym.getCustomerPaymentHistory(legacy.id), hasLength(1));
    },
  );

  test(
    'partial payment settles the stored agreement and balance clears it',
    () async {
      final c = await register();
      final id = gym.getCustomerPaymentHistory(c.id).single.id;
      await settle(c);
      expect(gym.getCustomerPaymentHistory(c.id), hasLength(1));
      expect(gym.getPaymentById(id)!.amount, 500.25);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1000.5);
      final bill = await gym.collectBalance(
        paymentId: id,
        amount: 1000.5,
        method: PaymentMethod.cash,
        operationId: 'remaining-balance',
      );
      expect(bill.billType, 'BALANCE');
      expect(gym.getAllPendingDues(), isEmpty);
      expect(gym.getCustomerPaymentHistory(c.id), hasLength(1));
      expect(gym.getBillsForPayment(id), hasLength(2));
    },
  );

  test('full settlement and renewal preserve the first period', () async {
    final c = await register();
    await settle(c, amount: 1500.75);
    final first = gym.getCustomerPaymentHistory(c.id).single;
    await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: '2024-04',
      startDate: DateTime(2024, 4, 15),
      durationMonths: 3,
      amount: 1500,
      method: PaymentMethod.cash,
    );
    expect(gym.getPaidPaymentsForCustomer(c.id), hasLength(2));
    expect(gym.getPaymentById(first.id)!.endDate, DateTime(2024, 4, 14));
    expect(gym.getAllPendingDues(), isEmpty);
  });

  test(
    'archive and cancellation retain an explicit unpaid agreement without attendance',
    () async {
      final c = await register();
      await gym.archiveCustomer(c.id);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
      await gym.restoreCustomer(c.id);
      await settle(c);
      final id = gym.getCustomerPaymentHistory(c.id).single.id;
      await gym.revertPayment(id);
      expect(gym.getPaymentById(id)!.isPaid, isFalse);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
      expect(gym.getAllBillsForPayment(id).single.status, 'CANCELLED');
    },
  );

  test('future credit membership is not active today', () async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day + 1);
    final c = await register(start: start);
    expect(gym.hasPaidMembership(c), isFalse);
    expect(
      gym.getMemberLifecycleStage(
        c,
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
      ),
      isNot(MemberLifecycleStage.paid),
    );
    expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
  });

  for (final changeDefault in [false, true]) {
    test(
      'package purchase updates future default only when selected: $changeDefault',
      () async {
        final c = await gym.addCustomer(
          name: 'Renewing member',
          phone: '9876543210',
        );
        final bill = await gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: '2024-01',
          startDate: DateTime(2024, 1, 1),
          durationMonths: 3,
          amount: 1500,
          method: PaymentMethod.cash,
          updateFutureRenewalDefault: changeDefault,
        );
        final updated = gym.getCustomerById(c.id)!;
        expect(updated.planDurationMonths, changeDefault ? 3 : 1);
        expect(
          gym.getRenewalPaymentRecord(updated).durationMonths,
          changeDefault ? 3 : 1,
        );
        expect(gym.getPaymentById(bill.paymentId)!.durationMonths, 3);
      },
    );
  }

  test(
    'settlement defaults retain the agreed duration, dates and fee',
    () async {
      final c = await register();
      final agreement = gym.getCustomerPaymentHistory(c.id).single;
      final bill = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: agreement.monthYear,
        agreementId: agreement.id,
        amount: 500.25,
        method: PaymentMethod.cash,
      );
      final paid = gym.getPaymentById(bill.paymentId)!;
      expect(paid.durationMonths, agreement.durationMonths);
      expect(paid.startDate, agreement.startDate);
      expect(paid.endDate, agreement.endDate);
      expect(paid.totalDue, agreement.totalDue);
      expect(bill.durationMonths, agreement.durationMonths);
      await expectLater(
        gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: agreement.monthYear,
          agreementId: agreement.id,
          amount: 500.25,
          method: PaymentMethod.cash,
        ),
        throwsArgumentError,
      );
      expect(gym.getAllBillsForPayment(agreement.id), hasLength(1));
    },
  );

  testWidgets(
    'settled attendance agreement opens its saved receipt and updates in place',
    (tester) async {
      final c = await gym.addCustomer(
        name: 'Existing member',
        phone: '9876543210',
        joinDate: DateTime(2024, 1, 1),
      );
      await gym.toggleAttendance(c.id, '2024-01-15', AttendanceStatus.present);
      final agreement = gym.getCustomerPaymentHistory(c.id).single;
      final bill = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: agreement.monthYear,
        agreementId: agreement.id,
        amount: 200,
        totalDue: 600,
        method: PaymentMethod.cash,
      );
      final paid = gym.getPaymentById(bill.paymentId)!;
      expect(gym.getOrCreateBillForPayment(c, paid).id, bill.id);
      expect(gym.getOrCreateBillForPayment(c, paid).billType, 'PARTIAL');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => MarkPaymentDialog.show(
                  context,
                  customer: c,
                  monthYear: paid.monthYear,
                  currentRecord: paid,
                ),
                child: const Text('Open payment'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open payment'));
      await tester.pumpAndSettle();
      expect(find.text('Revert to Pending'), findsOneWidget);
      await tester.ensureVisible(find.text('Update Payment Record'));
      await tester.tap(find.text('Update Payment Record'));
      await tester.pumpAndSettle();
      expect(gym.getCustomerPaymentHistory(c.id), hasLength(1));
      expect(gym.getAllBillsForPayment(paid.id), hasLength(1));
      expect(gym.getAllBillsForPayment(paid.id).single.id, bill.id);
      expect(find.textContaining('Payment updated for'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'registration and agreement share a recoverable cloud queue operation',
    () async {
      await gym.attachUser('credit-owner');
      final c = await register();
      final prefs = await SharedPreferences.getInstance();
      final queued =
          json.decode(prefs.getString('gym_credit-owner_cloud_outbox_v1')!)
              as List;
      expect(
        queued.any((item) {
          final changes = (item as Map)['changes'] as List;
          return changes.any(
                (change) => (change as Map)['collection'] == 'customers',
              ) &&
              changes.any(
                (change) => (change as Map)['collection'] == 'payments',
              );
        }),
        isTrue,
      );
      await gym.detachUser();
      await prefs.remove('gym_credit-owner_customers_v1');
      await prefs.remove('gym_credit-owner_payments_v1');
      await gym.attachUser('credit-owner');
      expect(gym.getCustomerById(c.id), isNotNull);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 1500.75);
    },
  );

  test(
    'WhatsApp receipts retain the partial balance at issue and distinguish balance and cancellation',
    () async {
      final c = await register();
      await settle(c);
      final first = gym.getAllBillsForCustomer(c.id).single;
      final balance = await gym.collectBalance(
        paymentId: first.paymentId,
        amount: 1000.5,
        method: PaymentMethod.cash,
      );
      final service = WhatsAppService();
      final firstMessage = service.buildBillReceiptMessage(bill: first);
      expect(firstMessage, contains('*Status:* PARTIAL'));
      expect(firstMessage, contains('*Total membership fee:* ₹1,500.75'));
      expect(firstMessage, contains('*Paid now:* *₹500.25*'));
      expect(firstMessage, contains('*Balance after this receipt:* ₹1,000.50'));
      final balanceMessage = service.buildBillReceiptMessage(bill: balance);
      expect(balanceMessage, contains('BALANCE RECEIVED'));
      expect(balanceMessage, contains('*Paid earlier:* ₹500.25'));
      expect(balanceMessage, contains('*Balance after this receipt:* ₹0'));
      expect(balanceMessage, contains('*Status:* PAID'));
      await gym.revertPayment(first.paymentId);
      final cancelled = gym.getAllBillsForPayment(first.paymentId).first;
      final cancelledMessage = service.buildBillReceiptMessage(bill: cancelled);
      expect(cancelledMessage, contains('*Status:* CANCELLED'));
      expect(cancelledMessage, isNot(contains('*Paid now:*')));
    },
  );
}
