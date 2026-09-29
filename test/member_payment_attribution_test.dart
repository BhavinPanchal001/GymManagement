import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/payment_receipt_pdf_service.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GymService().init();
  });

  test('Two payments in the same calendar month coexist with separate bills', () async {
    final gym = GymService();

    final customer = await gym.addCustomer(
      name: 'Double Payer',
      phone: '9876500001',
      joinDate: DateTime(2026, 8, 1),
      markAsPaidNow: false,
    );

    // First cycle: Aug 1 - Aug 31
    final bill1 = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-08',
      method: PaymentMethod.cash,
      amount: 600.0,
      totalDue: 600.0,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      paidAt: DateTime(2026, 8, 1),
    );

    // Second payment lands in the same calendar month (advance renewal paid Aug 20)
    final bill2 = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-08',
      method: PaymentMethod.gpay,
      amount: 600.0,
      totalDue: 600.0,
      startDate: DateTime(2026, 8, 20),
      endDate: DateTime(2026, 9, 19),
      paidAt: DateTime(2026, 8, 20),
    );

    expect(bill1.paymentId, isNot(equals(bill2.paymentId)));
    expect(bill1.billNumber, isNot(equals(bill2.billNumber)));

    final paid = gym.getPaidPaymentsForCustomer(customer.id);
    expect(paid.length, equals(2));

    expect(gym.getBillForPayment(bill1.paymentId)?.billNumber, equals(bill1.billNumber));
    expect(gym.getBillForPayment(bill2.paymentId)?.billNumber, equals(bill2.billNumber));

    final history = gym.getCustomerPaymentHistory(customer.id);
    expect(history.where((p) => p.isPaid).length, equals(2));

    final summary = gym.getMonthlyFinancialSummary('2026-08');
    expect(summary['totalCollected'], equals(1200.0));
  });

  test('27 Sep join + 1-month payment covers Sep and Oct; Nov is a transient pending', () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Mid Month Joiner',
      phone: '9876500002',
      joinDate: DateTime(2026, 9, 27),
      markAsPaidNow: false,
    );

    final sep27 = DateTime(2026, 9, 27);
    final oct26 = DateTime(2026, 10, 26);
    final fee = gym.settings.getPriceForDuration(member.planType, member.planDurationMonths);

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: fee,
      startDate: sep27,
      endDate: oct26,
      paidAt: sep27,
    );

    // Record's monthYear is the month the cycle starts in.
    expect(bill.monthYear, equals('2026-09'));
    expect(gym.isMonthCoveredByPaidPayment(member.id, '2026-09'), isTrue);
    expect(gym.isMonthCoveredByPaidPayment(member.id, '2026-10'), isTrue);

    // A member whose cycle already expired shows DUE once they attend again:
    // joined 27 Aug, paid 27 Aug – 26 Sep, attends today (past the end date).
    final expired = await gym.addCustomer(
      name: 'Expired Member',
      phone: '9876500008',
      joinDate: DateTime(2026, 8, 27),
      markAsPaidNow: false,
    );
    await gym.markPaymentAsPaid(
      customerId: expired.id,
      monthYear: '2026-08',
      method: PaymentMethod.cash,
      amount: fee,
      startDate: DateTime(2026, 8, 27),
      endDate: DateTime(2026, 9, 26),
      paidAt: DateTime(2026, 8, 27),
    );
    final today = DateTime.now();
    final todayKey = GymDateUtils.toDateKey(today);
    final thisMonth = GymDateUtils.toMonthKey(today);
    // Only meaningful if today is past this member's expiry.
    if (!today.isBefore(DateTime(2026, 9, 27))) {
      await gym.toggleAttendance(expired.id, todayKey, AttendanceStatus.present);
      expect(
        gym.getMemberLifecycleStage(expired, thisMonth),
        equals(MemberLifecycleStage.due),
      );
    }

    // November has no coverage: transient pending record with full fee as totalDue.
    final novRecord = gym.getPaymentRecord(member.id, '2026-11');
    expect(novRecord.isPaid, isFalse);
    expect(novRecord.id, startsWith('pending_'));
    expect(novRecord.amount, equals(0.0));
    expect(novRecord.totalDue, equals(fee));
  });

  test('3-month package is a single record covering all months (no placeholders)', () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Package Member',
      phone: '9876500003',
      joinDate: DateTime(2026, 9, 15),
      planDurationMonths: 3,
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.gpay,
      amount: 1500.0,
      totalDue: 1500.0,
      durationMonths: 3,
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 12, 14),
      paidAt: DateTime(2026, 9, 15),
    );

    final paid = gym.getPaidPaymentsForCustomer(member.id);
    expect(paid.length, equals(1));
    final record = paid.first;
    expect(record.durationMonths, equals(3));
    expect(record.coveredByMonthYear, isNull);
    expect(record.endDate, equals(DateTime(2026, 12, 14)));
    expect(bill.billType, equals('FULL'));

    for (final mk in ['2026-09', '2026-10', '2026-11', '2026-12']) {
      expect(
        gym.getPaymentCoveringMonth(member.id, mk)?.id,
        equals(record.id),
        reason: 'Package should cover $mk',
      );
    }
    expect(gym.getPaymentCoveringMonth(member.id, '2027-01'), isNull);

    // No placeholder records exist anywhere for this customer.
    expect(gym.getCustomerPaymentHistory(member.id).length, equals(1));
  });

  test('Partial payment tracks balance; collectBalance settles it with a BALANCE bill', () async {
    final gym = GymService();

    // July is used so the shared GymService singleton's other-test bills
    // (Sep/Aug) don't interfere with the financial-summary assertion.
    final member = await gym.addCustomer(
      name: 'Partial Payer',
      phone: '9876500004',
      joinDate: DateTime(2026, 7, 1),
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-07',
      method: PaymentMethod.cash,
      amount: 500.0,
      totalDue: 1500.0,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 7, 31),
      paidAt: DateTime(2026, 7, 1),
    );

    expect(bill.billType, equals('PARTIAL'));
    final record = gym.getPaymentById(bill.paymentId)!;
    expect(record.isPaid, isTrue);
    expect(record.isPartiallyPaid, isTrue);
    expect(record.balanceDue, equals(1000.0));

    // Pending reports include the balance.
    final pending = gym.getPendingDuesByMember(DateTime(2026, 7, 1), DateTime(2026, 7, 31));
    final mine = pending.where((s) => s.customer.id == member.id);
    expect(mine.isNotEmpty, isTrue);
    expect(mine.first.totalPendingAmount, equals(1000.0));

    // Overpaying the balance is clamped.
    final balBill = await gym.collectBalance(
      paymentId: record.id,
      amount: 2000.0,
      method: PaymentMethod.upi,
      paidAt: DateTime(2026, 7, 10),
    );
    expect(balBill.billType, equals('BALANCE'));
    expect(balBill.amount, equals(1000.0));
    expect(balBill.billNumber, isNot(equals(bill.billNumber)));

    final settled = gym.getPaymentById(record.id)!;
    expect(settled.balanceDue, equals(0.0));
    expect(settled.amount, equals(1500.0));

    final summary = gym.getMonthlyFinancialSummary('2026-07');
    expect(summary['totalCollected'], equals(1500.0));

    expect(
      gym.getBillsForPayment(record.id).length,
      equals(2),
    );
  });

  test('collectBalance rejects invalid input', () async {
    final gym = GymService();
    final member = await gym.addCustomer(
      name: 'Balance Guard',
      phone: '9876500005',
      joinDate: DateTime(2026, 9, 1),
      markAsPaidNow: false,
    );
    expect(
      () => gym.collectBalance(
        paymentId: 'nonexistent',
        amount: 100,
        method: PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: 600.0,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
    );
    expect(
      () => gym.collectBalance(
        paymentId: bill.paymentId,
        amount: 0,
        method: PaymentMethod.cash,
      ),
      throwsArgumentError,
    );
  });

  test('Revert cancels bills (never deletes) and bill numbers are not reused', () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Revert Test',
      phone: '9876500006',
      joinDate: DateTime(2026, 9, 1),
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: 600.0,
      totalDue: 600.0,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
      paidAt: DateTime(2026, 9, 1),
    );

    await gym.revertPayment(bill.paymentId);

    // Payment record is gone; coverage removed.
    expect(gym.getPaymentById(bill.paymentId), isNull);
    expect(gym.isMonthCoveredByPaidPayment(member.id, '2026-09'), isFalse);

    // Bill is still present, CANCELLED.
    final cancelled = gym.getBillsForPayment(bill.paymentId);
    expect(cancelled, isEmpty); // only PAID bills returned
    expect(
      gym.billsMap.values.any((b) => b.id == bill.id && b.status == 'CANCELLED'),
      isTrue,
    );

    // Next payment in the same month gets a HIGHER sequence.
    final bill2 = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.gpay,
      amount: 600.0,
      startDate: DateTime(2026, 9, 5),
      endDate: DateTime(2026, 10, 4),
    );
    expect(bill2.billNumber, isNot(equals(bill.billNumber)));

    int seqOf(String n) => int.parse(n.split('-').last);
    expect(seqOf(bill2.billNumber), greaterThan(seqOf(bill.billNumber)));
  });

  test('Legacy wrapper revertPaymentToPending resolves and reverts by month', () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Wrapper Revert',
      phone: '9876500007',
      joinDate: DateTime(2026, 9, 1),
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: 600.0,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
    );

    await gym.revertPaymentToPending(member.id, '2026-09');
    expect(gym.getPaymentById(bill.paymentId), isNull);
    expect(gym.isMonthCoveredByPaidPayment(member.id, '2026-09'), isFalse);
  });

  test('updatePayment edits the record and primary bill in place, no duplicates',
      () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Edit Payer',
      phone: '9876500008',
      joinDate: DateTime(2026, 5, 1),
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-05',
      method: PaymentMethod.cash,
      amount: 1500.0,
      totalDue: 1500.0,
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 5, 31),
      paidAt: DateTime(2026, 5, 1),
    );

    final updatedBill = await gym.updatePayment(
      paymentId: bill.paymentId,
      amount: 1200.0,
      method: PaymentMethod.gpay,
    );

    // Still exactly one payment record and one PAID bill for it.
    expect(gym.getPaidPaymentsForCustomer(member.id).length, equals(1));
    expect(gym.getBillsForPayment(bill.paymentId).length, equals(1));
    expect(updatedBill.id, equals(bill.id));
    expect(updatedBill.billNumber, equals(bill.billNumber));
    expect(updatedBill.amount, equals(1200.0));
    expect(updatedBill.billType, equals('PARTIAL'));
    expect(updatedBill.method, equals(PaymentMethod.gpay));

    final record = gym.getPaymentById(bill.paymentId)!;
    expect(record.amount, equals(1200.0));
    expect(record.balanceDue, equals(300.0));
  });

  test('Pre-join months return notEnrolled and past months distinguish 0 vs positive attendance', () async {
    final gym = GymService();
    // Member enrolled on September 27, 2026
    final member = await gym.addCustomer(
      name: 'Mayank PreJoin Test',
      phone: '9704949494',
      joinDate: DateTime(2026, 9, 27),
      markAsPaidNow: false,
    );

    // 1. August 2026 is prior to enrollment month (2026-09) -> notEnrolled
    final augStage = gym.getMemberLifecycleStage(member, '2026-08');
    expect(augStage, equals(MemberLifecycleStage.notEnrolled));
    expect(augStage.isNotEnrolled, isTrue);

    // 2. July 2026 is also prior to enrollment -> notEnrolled
    final julStage = gym.getMemberLifecycleStage(member, '2026-07');
    expect(julStage, equals(MemberLifecycleStage.notEnrolled));

    // 3. Current or enrollment month (September 2026) with 0 attendance
    // is within 3-day grace period if within 3 days, or due
    final sepStage = gym.getMemberLifecycleStage(member, '2026-09');
    expect(sepStage.isNotEnrolled, isFalse);

    // 4. Mark attendance in July 2026 (27 days present)
    for (int day = 1; day <= 27; day++) {
      await gym.toggleAttendance(
        member.id,
        '2026-07-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
      );
    }

    // Now July 2026 has attendance marked -> MUST be due!
    final julStageAfterAttendance = gym.getMemberLifecycleStage(member, '2026-07');
    expect(julStageAfterAttendance, equals(MemberLifecycleStage.due));
    expect(julStageAfterAttendance.isDue, isTrue);
    expect(julStageAfterAttendance.isNotEnrolled, isFalse);

    // August 2026 still has 0 attendance -> remains notEnrolled
    final augStageStillZero = gym.getMemberLifecycleStage(member, '2026-08');
    expect(augStageStillZero, equals(MemberLifecycleStage.notEnrolled));
  });

  test('getAllBillsForCustomer includes cancelled and balance bills newest first',
      () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Bill History Member',
      phone: '9876500009',
      joinDate: DateTime(2026, 2, 1),
      markAsPaidNow: false,
    );

    // Partial payment, then a balance collection on the same payment.
    final firstBill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-02',
      method: PaymentMethod.cash,
      amount: 500.0,
      totalDue: 1500.0,
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 2, 28),
      paidAt: DateTime(2026, 2, 1),
    );
    await gym.collectBalance(
      paymentId: firstBill.paymentId,
      amount: 1000.0,
      method: PaymentMethod.gpay,
    );

    // A second cycle that is then reverted: its bill stays as CANCELLED.
    final secondBill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-03',
      method: PaymentMethod.upi,
      amount: 1500.0,
      totalDue: 1500.0,
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 31),
      paidAt: DateTime(2026, 3, 1),
    );
    await gym.revertPayment(secondBill.paymentId);

    final allBills = gym.getAllBillsForCustomer(member.id);
    expect(allBills.length, equals(3));
    expect(allBills.any((b) => b.status == 'CANCELLED'), isTrue);
    expect(allBills.any((b) => b.billType == 'BALANCE'), isTrue);
    expect(allBills.any((b) => b.billType == 'PARTIAL'), isTrue);
    for (var i = 0; i + 1 < allBills.length; i++) {
      expect(
        allBills[i].issuedAt.isBefore(allBills[i + 1].issuedAt),
        isFalse,
        reason: 'Bills must be newest first',
      );
    }

    // PAID-only view still sees 2 bills on the first payment.
    expect(gym.getBillsForPayment(firstBill.paymentId).length, equals(2));
    expect(
        gym.getAllBillsForPayment(firstBill.paymentId).length, equals(2));
  });

  test('PDF receipt for a partial bill generates non-empty bytes', () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Pdf Partial Member',
      phone: '9876500010',
      joinDate: DateTime(2026, 4, 1),
      markAsPaidNow: false,
    );

    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-04',
      method: PaymentMethod.cash,
      amount: 500.0,
      totalDue: 1500.0,
      durationMonths: 3,
      startDate: DateTime(2026, 4, 1),
      endDate: DateTime(2026, 6, 30),
      paidAt: DateTime(2026, 4, 1),
    );
    expect(bill.billType, equals('PARTIAL'));

    final bytes = await PaymentReceiptPdfService().generateReceiptPdf(
      bill: bill,
      customer: member,
      settings: gym.settings,
    );
    expect(bytes, isNotEmpty);
  });

  test('mid-month cycle: month with uncovered attended days yields a pending record, not the covering payment',
      () async {
    final gym = GymService();

    final member = await gym.addCustomer(
      name: 'Mid Month Cycle',
      phone: '9876500011',
      joinDate: DateTime(2026, 8, 15),
      markAsPaidNow: false,
    );

    // Attendance 15-31 Aug and 1-29 Sep 2026.
    for (var d = 15; d <= 31; d++) {
      final key = '2026-08-${d.toString().padLeft(2, '0')}';
      await gym.toggleAttendance(member.id, key, AttendanceStatus.present);
    }
    await gym.setMonthAttendance(
      customerId: member.id,
      year: 2026,
      month: 9,
      status: AttendanceStatus.present,
    );

    // Paid cycle: 15 Aug - 14 Sep.
    await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-08',
      method: PaymentMethod.cash,
      amount: 600.0,
      totalDue: 600.0,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 9, 14),
      paidAt: DateTime(2026, 8, 15),
    );

    // August is fully covered -> paid record.
    final augRecord = gym.getPaymentRecord(member.id, '2026-08');
    expect(augRecord.isPaid, isTrue);
    expect(gym.getMemberLifecycleStage(member, '2026-08'),
        equals(MemberLifecycleStage.paid));

    // September still has uncovered attended days (15-29) -> pending record.
    final sepRecord = gym.getPaymentRecord(member.id, '2026-09');
    expect(sepRecord.isPaid, isFalse);
    expect(sepRecord.id, startsWith('pending_'));
    expect(sepRecord.startDate, equals(DateTime(2026, 9, 15)));
    expect(gym.getMemberLifecycleStage(member, '2026-09'),
        equals(MemberLifecycleStage.due));

    // History: exactly one paid + one pending, no duplicate of the paid record.
    final history = gym.getCustomerPaymentHistory(member.id);
    expect(history.where((p) => p.isPaid).length, equals(1));
    expect(history.where((p) => !p.isPaid).length, equals(1));

    // Continuation: pay the suggested 15 Sep - 14 Oct cycle.
    await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.gpay,
      amount: 600.0,
      totalDue: 600.0,
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 10, 14),
      paidAt: DateTime(2026, 9, 15),
    );

    final paid = gym.getPaidPaymentsForCustomer(member.id);
    expect(paid.length, equals(2));
    final starts = paid.map((p) => p.effectiveStartDate).toList();
    expect(starts, contains(DateTime(2026, 8, 15)));
    expect(starts, contains(DateTime(2026, 9, 15)));
    expect(gym.getUnpaidAttendedMonthKeys(member.id), isEmpty);
    final sepAfter = gym.getPaymentRecord(member.id, '2026-09');
    expect(sepAfter.isPaid, isTrue);
    expect(sepAfter.effectiveStartDate, equals(DateTime(2026, 9, 15)));
  });
}
