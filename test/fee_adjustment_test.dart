import "dart:convert";
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/fee_adjustment_sheet.dart';

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

  Future<PaymentRecord> member({double paid = 0}) async {
    final c = await gym.addCustomer(
      name: 'QA adjustment',
      phone: '9876543210',
      joinDate: DateTime(2025, 9, 1),
      planType: CustomerPlan.normal,
      membershipFee: 600,
      membershipStartDate: DateTime(2025, 9, 1),
      membershipEndDate: DateTime(2025, 9, 30),
      markAsPaidNow: paid > 0,
      paidAmount: paid > 0 ? paid : null,
    );
    return gym.getCustomerPaymentHistory(c.id).single;
  }

  Future<void> adjust(PaymentRecord p, double fee, {String id = 'adjust'}) =>
      gym.adjustMembershipFee(
        expected: p,
        revisedFee: fee,
        reason: 'Approved half-month discount',
        operationId: id,
      );

  test(
    'unpaid fee reduction preserves dates, cash, actor and original fee',
    () async {
      final p = await member();
      await adjust(p, 300);
      final updated = gym.getPaymentById(p.id)!;
      expect(updated.totalDue, 300);
      expect(updated.balanceDue, 300);
      expect(updated.amount, 0);
      expect(updated.originalFee, 600);
      expect(updated.effectiveStartDate, p.effectiveStartDate);
      expect(updated.effectiveEndDate, p.effectiveEndDate);
      expect(updated.feeChanges.single.actorId, 'local-owner');
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
      expect(gym.pendingAmountOf(updated), 300);
    },
  );

  test(
    'repeat confirmation is idempotent and stale changes are rejected',
    () async {
      final p = await member();
      await adjust(p, 300);
      await adjust(p, 300);
      expect(gym.getPaymentById(p.id)!.feeChanges, hasLength(1));
      await expectLater(adjust(p, 200, id: 'stale'), throwsStateError);
    },
  );

  test(
    'a 15-day break leaves two fees and adjustment reduces only the selected one',
    () async {
      final p = await member();
      for (var day = 1; day <= 15; day++) {
        await gym.toggleAttendance(
          p.customerId,
          '2025-09-${day.toString().padLeft(2, '0')}',
          AttendanceStatus.present,
          toggle: false,
        );
      }
      await gym.toggleAttendance(
        p.customerId,
        '2025-10-01',
        AttendanceStatus.present,
        toggle: false,
      );
      final before = gym
          .getPendingDuesByMember(DateTime(2025, 9), DateTime(2025, 10, 31))
          .single;
      expect(before.totalPendingAmount, 1200);
      expect(before.pendingRecords, hasLength(2));
      await adjust(gym.getPaymentById(p.id)!, 300);
      final after = gym
          .getPendingDuesByMember(DateTime(2025, 9), DateTime(2025, 10, 31))
          .single;
      expect(after.totalPendingAmount, 900);
      expect(
        after.pendingRecords
            .singleWhere((r) => r.monthYear == '2025-10')
            .totalDue,
        600,
      );
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
    },
  );

  test('invalid fee or missing reason cannot change records', () async {
    final p = await member();
    for (final value in [-1.0, double.nan, double.infinity, 300.001]) {
      await expectLater(adjust(p, value), throwsArgumentError);
    }
    await expectLater(
      gym.adjustMembershipFee(
        expected: p,
        revisedFee: 300,
        reason: ' ',
        operationId: 'blank',
      ),
      throwsArgumentError,
    );
    expect(gym.getPaymentById(p.id)!.totalDue, 600);
  });

  test(
    'paid excess becomes credit without modifying original receipt',
    () async {
      final p = await member(paid: 400);
      final receipts = gym
          .getAllBillsForCustomer(p.customerId)
          .map((b) => b.toJson())
          .toList();
      await adjust(p, 300);
      final changed = gym.getPaymentById(p.id)!;
      expect(changed.amount, 400);
      expect(changed.availableCredit, 100);
      expect(changed.balanceDue, 0);
      expect(
        gym
            .getAllBillsForCustomer(p.customerId)
            .map((b) => b.toJson())
            .toList(),
        receipts,
      );
      final bill = gym.getAllBillsForCustomer(p.customerId).single;
      expect(gym.feeAtReceipt(changed, bill), 600);
      expect(gym.balanceAtReceipt(changed, bill), 200);
      expect(PaymentRecord.fromJson(changed.toJson()).toMap(), changed.toMap());
    },
  );

  test('credit carries forward once and does not create income', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    final source = gym.getPaymentById(p.id)!;
    final target = gym.creditRenewalPeriod(p.customerId);
    await gym.applyMemberCredit(
      expectedSource: source,
      expectedTarget: target,
      amount: 100,
      operationId: 'transfer',
    );
    await gym.applyMemberCredit(
      expectedSource: source,
      expectedTarget: target,
      amount: 100,
      operationId: 'transfer',
    );
    expect(gym.getPaymentById(p.id)!.availableCredit, 0);
    final next = gym.getPaymentById(target.id)!;
    expect(next.balanceDue, 500);
    expect(next.amount, 0);
    expect(next.creditApplied, 100);
    expect(gym.getAllBillsForCustomer(p.customerId), hasLength(1));
    final bill = await gym.collectBalance(
      paymentId: target.id,
      amount: 500,
      method: PaymentMethod.cash,
    );
    expect(bill.amount, 500);
    expect(gym.getPaymentById(target.id)!.balanceDue, 0);
    expect(gym.getPaymentById(target.id)!.paidAt, isNotNull);
    expect(
      gym
          .getAllBillsForCustomer(p.customerId)
          .fold<double>(0, (v, b) => v + b.amount),
      900,
    );
  });

  test(
    'credit cannot cross members, overspend or be undone by fee editing',
    () async {
      final p = await member(paid: 400);
      await adjust(p, 300);
      final source = gym.getPaymentById(p.id)!;
      final other = await member();
      await expectLater(
        gym.applyMemberCredit(
          expectedSource: source,
          expectedTarget: other,
          amount: 100,
          operationId: 'wrong-member',
        ),
        throwsArgumentError,
      );
      final target = gym.creditRenewalPeriod(p.customerId);
      await expectLater(
        gym.applyMemberCredit(
          expectedSource: source,
          expectedTarget: target,
          amount: 101,
          operationId: 'too-much',
        ),
        throwsArgumentError,
      );
      await gym.applyMemberCredit(
        expectedSource: source,
        expectedTarget: target,
        amount: 100,
        operationId: 'use',
      );
      await expectLater(
        adjust(gym.getPaymentById(p.id)!, 600, id: 'undo-credit'),
        throwsArgumentError,
      );
      await expectLater(gym.revertPayment(p.id), throwsArgumentError);
    },
  );

  test('recording money returned reduces net collections once', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    final source = gym.getPaymentById(p.id)!;
    await gym.refundMemberCredit(
      expected: source,
      amount: 100,
      method: PaymentMethod.cash,
      reason: 'Returned in cash',
      operationId: 'refund',
    );
    await gym.refundMemberCredit(
      expected: source,
      amount: 100,
      method: PaymentMethod.cash,
      reason: 'Returned in cash',
      operationId: 'refund',
    );
    expect(gym.getPaymentById(p.id)!.availableCredit, 0);
    final bills = gym.getAllBillsForCustomer(p.customerId);
    expect(bills, hasLength(2));
    expect(bills.singleWhere((b) => b.billType == 'REFUND').amount, -100);
    expect(bills.fold<double>(0, (v, b) => v + b.amount), 300);
    final reports = gym.getCollectionsByMember(DateTime(2020), DateTime(2100));
    expect(reports.single.totalCollectedAmount, 300);
    final refundRow = reports.single.paidRecords.singleWhere(
      (r) => r.amount < 0,
    );
    expect(
      gym
          .getOrCreateBillForPayment(
            gym.getCustomerById(p.customerId)!,
            refundRow,
          )
          .billType,
      'REFUND',
    );
  });

  test('full waiver and audit are persisted without a cash receipt', () async {
    final p = await member();
    await adjust(p, 0);
    final before = gym.getPaymentById(p.id)!;
    expect(before.balanceDue, 0);
    expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final snapshot =
        jsonDecode(prefs.getString('gym_financial_v1')!)
            as Map<String, dynamic>;
    final after = PaymentRecord.fromMap(
      Map<String, dynamic>.from((snapshot['payments'] as List).single),
    );
    expect(after.totalDue, 0);
    expect(after.originalFee, 600);
    expect(after.feeChanges, hasLength(1));
    expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
  });

  test(
    'collect adjusted unpaid fee retains audit and does not change old price',
    () async {
      final p = await member();
      await adjust(p, 300);
      await gym.markPaymentAsPaid(
        customerId: p.customerId,
        monthYear: p.monthYear,
        amount: 300,
        method: PaymentMethod.cash,
        agreementId: p.id,
        startDate: p.effectiveStartDate,
        endDate: p.effectiveEndDate,
      );
      final saved = gym.getPaymentById(p.id)!;
      expect(saved.originalFee, 600);
      expect(saved.totalDue, 300);
      expect(saved.balanceDue, 0);
      expect(saved.feeChanges, hasLength(1));
    },
  );

  testWidgets('adjustment requires reason and confirmation before saving', (
    tester,
  ) async {
    final p = await member();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeeAdjustmentSheet(payment: p)),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Revised fee'),
      '300',
    );
    await tester.tap(find.text('Review fee adjustment'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid revised fee and a reason.'),
      findsOneWidget,
    );
    expect(gym.getPaymentById(p.id)!.totalDue, 600);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for adjustment'),
      'Approved break',
    );
    await tester.tap(find.text('Review fee adjustment'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Review change'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(gym.getPaymentById(p.id)!.totalDue, 300);
    expect(find.text('Change saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
