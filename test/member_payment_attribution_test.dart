import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GymService().init();
  });

  test('Member paid for August shows PAID in Aug, and UNPAID with 26 days attendance in Sept', () async {
    final gym = GymService();

    // 1. Add customer with payment for August 1 to August 31, 2026
    final augStart = DateTime(2026, 8, 1);
    final augEnd = DateTime(2026, 8, 31);
    final customer = await gym.addCustomer(
      name: 'Ramesh Patel',
      phone: '9876543210',
      joinDate: augStart,
      markAsPaidNow: true,
      membershipStartDate: augStart,
      membershipEndDate: augEnd,
      initialPaymentMethod: PaymentMethod.cash,
    );

    // 2. Add 26 days of present attendance in September 2026
    for (int day = 1; day <= 26; day++) {
      final dateKey = '2026-09-${day.toString().padLeft(2, '0')}';
      await gym.toggleAttendance(
        customer.id,
        dateKey,
        AttendanceStatus.present,
      );
    }

    // 3. Verify August status
    final augPay = gym.getPaymentRecord(customer.id, '2026-08');
    expect(augPay.isPaid, isTrue);
    expect(gym.getMemberLifecycleStage(customer, '2026-08'), equals(MemberLifecycleStage.paid));

    // 4. Verify September status (Today: Sept 26, 2026)
    final septPay = gym.getPaymentRecord(customer.id, '2026-09');
    expect(septPay.isPaid, isFalse);
    expect(septPay.status, equals(PaymentStatus.pending));

    final septStage = gym.getMemberLifecycleStage(customer, '2026-09');
    expect(septStage, equals(MemberLifecycleStage.due), reason: 'Member membership expired on Aug 31 and has 26 attended days in Sept, so status must be DUE');

    // 5. Verify Yearly Card Data for MemberCardScreen and PDF
    final yearly = gym.getYearlyCardData(customer.id, 2026);
    final augCard = yearly.firstWhere((m) => m.month == 8);
    final septCard = yearly.firstWhere((m) => m.month == 9);

    expect(augCard.isPaid, isTrue, reason: 'August was paid');
    expect(septCard.isPaid, isFalse, reason: 'September is unpaid');
    expect(septCard.presentDays, equals(26), reason: '26 days present in September');
  });

  test('Auto-normalization heals existing misattributed September records', () async {
    final gym = GymService();

    // Setup an initial customer
    final customer = await gym.addCustomer(
      name: 'Suresh Shah',
      phone: '9876543211',
      joinDate: DateTime(2026, 8, 1),
      markAsPaidNow: false,
    );

    // Simulate old buggy state: payment for August was saved under September key
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: 800.0,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
    );

    // Check August: should be paid
    final augPay = gym.getPaymentRecord(customer.id, '2026-08');
    expect(augPay.isPaid, isTrue);
    expect(augPay.monthYear, equals('2026-08'));

    // Check September: must be pending (unpaid)
    final septPay = gym.getPaymentRecord(customer.id, '2026-09');
    expect(septPay.isPaid, isFalse);
    expect(septPay.status, equals(PaymentStatus.pending));
  });

  test('Pay-later member with multi-month attendance accurately tracks unpaid months and links payment to attendance', () async {
    final gym = GymService();

    // 1. Create a pay-later member who joined on August 1st
    final customer = await gym.addCustomer(
      name: 'Priya Sharma',
      phone: '9876543299',
      joinDate: DateTime(2026, 8, 1),
      markAsPaidNow: false,
    );

    // 2. Mark 20 days present in August 2026
    for (int day = 1; day <= 20; day++) {
      await gym.toggleAttendance(
        customer.id,
        '2026-08-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
      );
    }

    // 3. Mark 25 days present in September 2026
    for (int day = 1; day <= 25; day++) {
      await gym.toggleAttendance(
        customer.id,
        '2026-09-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
      );
    }

    // 4. Verify getUnpaidAttendedMonthKeys identifies both overdue months
    final unpaidMonths = gym.getUnpaidAttendedMonthKeys(customer.id);
    expect(unpaidMonths, equals(['2026-08', '2026-09']));

    // 5. Member pays later on September 27 for August dues
    final bill = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-08',
      method: PaymentMethod.upi,
      amount: 800.0,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      paidAt: DateTime(2026, 9, 27),
    );

    // 6. Verify August is settled and bill has correct monthYear
    final augRecord = gym.getPaymentRecord(customer.id, '2026-08');
    expect(augRecord.isPaid, isTrue);
    expect(augRecord.amount, equals(800.0));
    expect(bill.monthYear, equals('2026-08'));

    // Verify August attendance stats (20 days)
    final augAtt = gym.getMonthlyAttendanceSummary(customer.id, '2026-08');
    expect(augAtt['present'], equals(20));

    // 7. Verify September remains UNPAID with 25 attended days
    final remainingUnpaid = gym.getUnpaidAttendedMonthKeys(customer.id);
    expect(remainingUnpaid, equals(['2026-09']));

    final septRecord = gym.getPaymentRecord(customer.id, '2026-09');
    expect(septRecord.isPaid, isFalse);
    expect(septRecord.status, equals(PaymentStatus.pending));

    final septAtt = gym.getMonthlyAttendanceSummary(customer.id, '2026-09');
    expect(septAtt['present'], equals(25));

    final septStage = gym.getMemberLifecycleStage(customer, '2026-09');
    expect(septStage, equals(MemberLifecycleStage.due));
  });

  test('User scenario: 26 days in Aug, 26 days in Sept, then paid 27 Sep to 26 Oct', () async {
    final gym = GymService();

    // 1. Create member Kajal
    final kajal = await gym.addCustomer(
      name: 'Kajal',
      phone: '9494049494',
      joinDate: DateTime(2026, 8, 1),
      markAsPaidNow: false,
    );

    // 2. Mark 26 days present in August 2026
    for (int day = 1; day <= 26; day++) {
      await gym.toggleAttendance(
        kajal.id,
        '2026-08-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
      );
    }

    // 3. Mark 26 days present in September 2026 (Sep 1 to Sep 26)
    for (int day = 1; day <= 26; day++) {
      await gym.toggleAttendance(
        kajal.id,
        '2026-09-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
      );
    }

    // Prior to payment, both months are unpaid dues
    expect(gym.getUnpaidAttendedMonthKeys(kajal.id), equals(['2026-08', '2026-09']));
    expect(gym.getUnpaidAttendedDaysInMonth(kajal.id, '2026-08'), equals(26));
    expect(gym.getUnpaidAttendedDaysInMonth(kajal.id, '2026-09'), equals(26));

    // 4. Member pays for 27 Sep to 26 Oct (Renewal / Next Cycle)
    final sep27 = DateTime(2026, 9, 27);
    final oct26 = DateTime(2026, 10, 26);
    final bill = await gym.markPaymentAsPaid(
      customerId: kajal.id,
      monthYear: '2026-09',
      method: PaymentMethod.gpay,
      amount: 600.0,
      startDate: sep27,
      endDate: oct26,
      paidAt: sep27,
    );

    // 5. Verify payment was placed into October cycle (targetMonthKey: 2026-10)
    expect(bill.monthYear, equals('2026-10'));
    expect(bill.startDate, equals(sep27));
    expect(bill.endDate, equals(oct26));

    // 6. Verify August & September BOTH remain UNPAID with 26 attended days each
    final unpaidMonthsAfter = gym.getUnpaidAttendedMonthKeys(kajal.id);
    expect(unpaidMonthsAfter, equals(['2026-08', '2026-09']),
        reason: 'Payment from Sep 27 to Oct 26 does NOT pay for Sep 1-26 or Aug 1-26!');

    expect(gym.getUnpaidAttendedDaysInMonth(kajal.id, '2026-08'), equals(26));
    expect(gym.getUnpaidAttendedDaysInMonth(kajal.id, '2026-09'), equals(26));
    expect(gym.getUnpaidAttendedDaysInMonth(kajal.id, '2026-10'), equals(0));

    // 7. Verify October is PAID and active
    final octPayment = gym.getPaymentRecord(kajal.id, '2026-10');
    expect(octPayment.isPaid, isTrue);
    expect(octPayment.amount, equals(600.0));
    expect(gym.getAttendedDaysCoveredByPayment(kajal.id, octPayment), equals(0),
        reason: 'No attendance has been marked yet between 27 Sep and 26 Oct');

    // 8. Verify June 2026 is UNPAID with NO coverage
    expect(gym.isMonthCoveredByPaidPayment(kajal.id, '2026-06'), isFalse);
    expect(gym.getMemberLifecycleStage(kajal, '2026-06'), equals(MemberLifecycleStage.due));

    // 9. Verify bill lookup for October resolves to the 27 Sep - 26 Oct bill
    final resolvedBill = gym.getOrCreateBillForPayment(kajal, octPayment);
    expect(resolvedBill.billNumber, equals(bill.billNumber));
    expect(resolvedBill.coveragePeriod, equals('27 Sep – 26 Oct 2026'));
  });

  test('Future attendance marking is strictly prevented at service level', () async {
    final gym = GymService();
    final customer = await gym.addCustomer(
      name: 'Future Test Member',
      phone: '9998887776',
      joinDate: DateTime.now().subtract(const Duration(days: 10)),
      markAsPaidNow: false,
    );

    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowKey = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

    // 1. toggleAttendance on future date should be rejected
    await gym.toggleAttendance(customer.id, tomorrowKey, AttendanceStatus.present);
    expect(gym.getAttendance(customer.id, tomorrowKey), isNull,
        reason: 'Future attendance toggle must do nothing');

    // 2. setMonthAttendance on future month should be rejected
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    await gym.setMonthAttendance(
      customerId: customer.id,
      year: nextMonth.year,
      month: nextMonth.month,
      status: AttendanceStatus.present,
    );
    final futureDayKey = '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-01';
    expect(gym.getAttendance(customer.id, futureDayKey), isNull,
        reason: 'Marking future month attendance must do nothing');

    // 3. setMonthAttendance on current month should cap at today
    await gym.setMonthAttendance(
      customerId: customer.id,
      year: now.year,
      month: now.month,
      status: AttendanceStatus.present,
    );
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(gym.getAttendance(customer.id, todayKey)?.status, equals(AttendanceStatus.present),
        reason: 'Today attendance should be marked present');

    // Any day after today in current month should NOT be marked
    if (now.day < 28) {
      final futureDayInCurrentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day + 1).toString().padLeft(2, '0')}';
      expect(gym.getAttendance(customer.id, futureDayInCurrentMonth), isNull,
          reason: 'Future days in current month must not be marked');
    }
  });

  test('Clean mid-month cycle (0 days attended in start month) is attributed to start month with no ghost pending record', () async {
    final gym = GymService();

    // 1. Create member Nayan who joined on 27 Sep with no prior attendance
    final nayan = await gym.addCustomer(
      name: 'Nayan',
      phone: '9876543200',
      joinDate: DateTime(2026, 9, 27),
      markAsPaidNow: false,
    );

    // 0 days attended in September
    expect(gym.getUnpaidAttendedDaysInMonth(nayan.id, '2026-09'), equals(0));

    // 2. Member pays for 27 Sep to 26 Oct (monthYear: 2026-09)
    final sep27 = DateTime(2026, 9, 27);
    final oct26 = DateTime(2026, 10, 26);
    final bill = await gym.markPaymentAsPaid(
      customerId: nayan.id,
      monthYear: '2026-09',
      method: PaymentMethod.cash,
      amount: 600.0,
      startDate: sep27,
      endDate: oct26,
      paidAt: sep27,
    );

    // 3. Payment must be anchored to September 2026 (targetMonthKey: 2026-09)
    expect(bill.monthYear, equals('2026-09'));
    expect(bill.startDate, equals(sep27));
    expect(bill.endDate, equals(oct26));

    // 4. September must be PAID
    final sepRecord = gym.getPaymentRecord(nayan.id, '2026-09');
    expect(sepRecord.isPaid, isTrue);
    expect(sepRecord.amount, equals(600.0));

    // 5. Member must have NO unpaid attended dues in September or October
    expect(gym.getUnpaidAttendedMonthKeys(nayan.id), isEmpty);
    expect(gym.getMemberLifecycleStage(nayan, '2026-09'), equals(MemberLifecycleStage.paid));

    // 6. Payment History must have exactly 1 record (the paid September cycle)
    final history = gym.getCustomerPaymentHistory(nayan.id);
    expect(history.length, equals(1), reason: 'Should NOT contain a ghost pending September record with 0 days attended');
    expect(history.first.monthYear, equals('2026-09'));
    expect(history.first.isPaid, isTrue);
    expect(history.first.startDate, equals(sep27));
    expect(history.first.endDate, equals(oct26));
  });

  test('Auto-normalization heals payments mistakenly placed in end month when start month had 0 unpaid attendance', () async {
    final gym = GymService();

    // 1. Create customer
    final cust = await gym.addCustomer(
      name: 'Nayan Legacy',
      phone: '9876543201',
      joinDate: DateTime(2026, 9, 27),
      markAsPaidNow: false,
    );

    // 2. Simulate the old buggy state: payment was stored under 2026-10 with a ghost pending in 2026-09
    final sep27 = DateTime(2026, 9, 27);
    final oct26 = DateTime(2026, 10, 26);
    // Put legacy records in gym_service
    await gym.markPaymentAsPaid(
      customerId: cust.id,
      monthYear: '2026-10',
      method: PaymentMethod.cash,
      amount: 600.0,
      startDate: sep27,
      endDate: oct26,
      paidAt: sep27,
    );

    // 3. Trigger normalization
    await gym.init();

    // 4. Verify healed state: September is now PAID and October key was cleared
    final sepPay = gym.getPaymentRecord(cust.id, '2026-09');
    expect(sepPay.isPaid, isTrue);
    expect(sepPay.monthYear, equals('2026-09'));
    expect(sepPay.startDate, equals(sep27));
    expect(sepPay.endDate, equals(oct26));

    final history = gym.getCustomerPaymentHistory(cust.id);
    expect(history.length, equals(1));
    expect(history.first.monthYear, equals('2026-09'));
    expect(history.first.isPaid, isTrue);
  });
}
