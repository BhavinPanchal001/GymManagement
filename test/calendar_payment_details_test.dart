import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/calendar_payment_indicator.dart';
import 'package:gym/utils/date_utils.dart';

PaymentRecord period({
  double amount = 600,
  double fee = 600,
  double credit = 0,
  int start = 10,
  int end = 20,
}) => PaymentRecord(
  id: 'p$start-$amount',
  customerId: 'c',
  monthYear: '2026-10',
  amount: amount,
  totalDue: fee,
  creditApplied: credit,
  status: amount > 0 || credit > 0 || fee == 0
      ? PaymentStatus.paid
      : PaymentStatus.pending,
  startDate: DateTime(2026, 10, start, 18),
  endDate: DateTime(2026, 10, end, 8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  CalendarPaymentStatus status(int day, List<PaymentRecord> periods) =>
      calendarPaymentStatus(
        date: DateTime(2026, 10, day),
        joinDate: DateTime(2026, 10, 1),
        periods: periods,
      );

  test('paid dates include both boundaries regardless of time of day', () {
    for (final day in [10, 15, 20]) {
      expect(status(day, [period()]), CalendarPaymentStatus.paid);
    }
    for (final day in [9, 21]) {
      expect(status(day, [period()]), CalendarPaymentStatus.none);
    }
  });
  test('partial fee marks the whole period part paid', () {
    for (final day in [10, 15, 20]) {
      expect(status(day, [period(amount: 200)]), CalendarPaymentStatus.partial);
    }
  });
  test('unpaid agreement marks due even without attendance', () {
    expect(status(12, [period(amount: 0)]), CalendarPaymentStatus.due);
  });
  test('no period does not invent a debt', () {
    expect(status(12, []), CalendarPaymentStatus.none);
  });
  test('credit settles fee without another cash payment', () {
    expect(
      status(12, [period(amount: 0, credit: 600)]),
      CalendarPaymentStatus.paid,
    );
    expect(
      status(12, [period(amount: 0, credit: 200)]),
      CalendarPaymentStatus.partial,
    );
  });
  test('waived fee is settled', () {
    expect(status(12, [period(amount: 0, fee: 0)]), CalendarPaymentStatus.paid);
  });
  test('fully paid coverage wins over an overlapping legacy due', () {
    for (final periods in [
      [period(amount: 0), period()],
      [period(), period(amount: 0)],
    ]) {
      expect(status(12, periods), CalendarPaymentStatus.paid);
    }
  });
  test('partial coverage wins over overlapping unpaid legacy record', () {
    for (final periods in [
      [period(amount: 0), period(amount: 200)],
      [period(amount: 200), period(amount: 0)],
    ]) {
      expect(status(12, periods), CalendarPaymentStatus.partial);
    }
  });
  test('dates before joining do not show paid or due', () {
    expect(
      calendarPaymentStatus(
        date: DateTime(2026, 10, 12),
        joinDate: DateTime(2026, 10, 15),
        periods: [period()],
      ),
      CalendarPaymentStatus.none,
    );
  });
  test('cross month and year periods use actual dates', () {
    final p = period().copyWith(
      startDate: DateTime(2025, 12, 15),
      endDate: DateTime(2026, 1, 14),
    );
    for (final day in [DateTime(2025, 12, 31), DateTime(2026, 1, 14)]) {
      expect(
        calendarPaymentStatus(
          date: day,
          joinDate: DateTime(2025),
          periods: [p],
        ),
        CalendarPaymentStatus.paid,
      );
    }
    expect(
      calendarPaymentStatus(
        date: DateTime(2026, 1, 15),
        joinDate: DateTime(2025),
        periods: [p],
      ),
      CalendarPaymentStatus.none,
    );
  });

  final gym = GymService();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await gym.detachUser();
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());
  for (final scenario in [
    (DateTime(2026, 10, 1), DateTime(2026, 12, 31)),
    (DateTime(2026, 10, 15), DateTime(2027, 1, 14)),
    (DateTime(2023, 12, 1), DateTime(2024, 2, 29)),
  ]) {
    test('real three-month member covers every day: ${scenario.$1}', () async {
      final c = await gym.addCustomer(
        name: 'QA Three Months',
        phone: '2025550198',
        joinDate: scenario.$1,
        planDurationMonths: 3,
        membershipStartDate: scenario.$1,
        membershipEndDate: scenario.$2,
        membershipFee: 1500,
        markAsPaidNow: true,
        paidAmount: 1500,
      );
      final periods = gym.feePeriods(c.id);
      expect(periods, hasLength(1));
      expect(periods.single.durationMonths, 3);
      for (
        var date = scenario.$1;
        !date.isAfter(scenario.$2);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        expect(
          calendarPaymentStatus(
            date: date,
            joinDate: c.joinDate,
            periods: periods,
          ),
          CalendarPaymentStatus.paid,
          reason: '$date',
        );
      }
      for (final date in [
        scenario.$1.subtract(const Duration(days: 1)),
        scenario.$2.add(const Duration(days: 1)),
      ]) {
        expect(
          calendarPaymentStatus(
            date: date,
            joinDate: c.joinDate,
            periods: periods,
          ),
          CalendarPaymentStatus.none,
        );
      }
      expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
      expect(gym.getAllPendingDues(), isEmpty);
    });
  }

  for (final payment in [
    (0.0, CalendarPaymentStatus.due),
    (500.0, CalendarPaymentStatus.partial),
  ]) {
    test(
      'three-month plan with ${payment.$1} collected shows ${payment.$2.name} across all months',
      () async {
        final c = await gym.addCustomer(
          name: 'Three Month Balance QA',
          phone: '2025550193',
          joinDate: DateTime(2025, 10),
          membershipStartDate: DateTime(2025, 10),
          membershipEndDate: DateTime(2025, 12, 31),
          planDurationMonths: 3,
          membershipFee: 1500,
          markAsPaidNow: payment.$1 > 0,
          paidAmount: payment.$1,
        );
        for (var month = 10; month <= 12; month++) {
          expect(
            calendarPaymentStatus(
              date: DateTime(2025, month, 15),
              joinDate: c.joinDate,
              periods: gym.feePeriods(c.id),
            ),
            payment.$2,
          );
        }
      },
    );
  }

  test('three-month paid coverage survives owner data reload', () async {
    await gym.attachUser('qa-calendar-owner');
    final c = await gym.addCustomer(
      name: 'Three Month Reload QA',
      phone: '2025550192',
      joinDate: DateTime(2025, 10),
      membershipStartDate: DateTime(2025, 10),
      membershipEndDate: DateTime(2025, 12, 31),
      planDurationMonths: 3,
      membershipFee: 1500,
      markAsPaidNow: true,
      paidAmount: 1500,
    );
    await gym.detachUser();
    await gym.attachUser('qa-calendar-owner');
    final restored = gym.getCustomerById(c.id)!;
    for (var month = 10; month <= 12; month++) {
      expect(
        calendarPaymentStatus(
          date: DateTime(2025, month, 15),
          joinDate: restored.joinDate,
          periods: gym.feePeriods(c.id),
        ),
        CalendarPaymentStatus.paid,
      );
    }
    expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
  });

  test('payment cancellation returns covered dates to due', () async {
    final c = await gym.addCustomer(
      name: 'Cancel QA',
      phone: '2025550197',
      joinDate: DateTime(2026, 1),
      membershipStartDate: DateTime(2026, 1),
      membershipEndDate: DateTime(2026, 3, 31),
      planDurationMonths: 3,
      membershipFee: 1500,
      markAsPaidNow: true,
      paidAmount: 1500,
    );
    final p = gym.feePeriods(c.id).single;
    await gym.revertPayment(p.id);
    expect(
      calendarPaymentStatus(
        date: DateTime(2026, 2, 15),
        joinDate: c.joinDate,
        periods: gym.feePeriods(c.id),
      ),
      CalendarPaymentStatus.due,
    );
  });

  test(
    'uncovered visit creates due period without changing older paid dates',
    () async {
      final c = await gym.addCustomer(
        name: 'Gap QA',
        phone: '2025550196',
        joinDate: DateTime(2025, 10),
        membershipStartDate: DateTime(2025, 10),
        membershipEndDate: DateTime(2025, 10, 14),
        membershipFee: 600,
        markAsPaidNow: true,
        paidAmount: 600,
      );
      await gym.toggleAttendance(
        c.id,
        '2025-10-20',
        AttendanceStatus.present,
        toggle: false,
      );
      final periods = gym.feePeriods(c.id);
      expect(
        calendarPaymentStatus(
          date: DateTime(2025, 10, 14),
          joinDate: c.joinDate,
          periods: periods,
        ),
        CalendarPaymentStatus.paid,
      );
      expect(
        calendarPaymentStatus(
          date: DateTime(2025, 10, 15),
          joinDate: c.joinDate,
          periods: periods,
        ),
        CalendarPaymentStatus.none,
      );
      expect(
        calendarPaymentStatus(
          date: DateTime(2025, 10, 20),
          joinDate: c.joinDate,
          periods: periods,
        ),
        CalendarPaymentStatus.due,
      );
    },
  );

  test(
    'paid membership covers present absent rest and unmarked days alike',
    () async {
      final c = await gym.addCustomer(
        name: 'Attendance QA',
        phone: '2025550195',
        joinDate: DateTime(2025, 10),
        membershipStartDate: DateTime(2025, 10),
        membershipEndDate: DateTime(2025, 12, 31),
        planDurationMonths: 3,
        membershipFee: 1500,
        markAsPaidNow: true,
        paidAmount: 1500,
      );
      for (var i = 0; i < AttendanceStatus.values.length; i++) {
        await gym.toggleAttendance(
          c.id,
          '2025-10-0${i + 1}',
          AttendanceStatus.values[i],
          toggle: false,
        );
      }
      for (var day = 1; day <= 4; day++) {
        expect(
          calendarPaymentStatus(
            date: DateTime(2025, 10, day),
            joinDate: c.joinDate,
            periods: gym.feePeriods(c.id),
          ),
          CalendarPaymentStatus.paid,
        );
      }
    },
  );

  testWidgets(
    'three paid months visible after navigation and expiry has no paid icon',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 3, 0);
      final c = await gym.addCustomer(
        name: 'Three Month UI',
        phone: '2025550194',
        joinDate: start,
        membershipStartDate: start,
        membershipEndDate: end,
        planDurationMonths: 3,
        membershipFee: 1500,
        markAsPaidNow: true,
        paidAmount: 1500,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerDetailScreen(customerId: c.id, initialTabIndex: 1),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('show-calendar-payments'));
      await tester.scrollUntilVisible(
        toggle,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      for (var offset = 0; offset < 4; offset++) {
        final month = DateTime(start.year, start.month + offset);
        final dayCount = DateTime(month.year, month.month + 1, 0).day;
        for (var day = 1; day <= dayCount; day++) {
          final date = DateTime(month.year, month.month, day);
          final cell = find.byKey(
            ValueKey('attendance-day-${GymDateUtils.toDateKey(date)}'),
          );
          final indicator = tester.widget<CalendarPaymentIndicator>(
            find.descendant(
              of: cell,
              matching: find.byType(CalendarPaymentIndicator),
            ),
          );
          expect(
            indicator.status,
            offset < 3
                ? CalendarPaymentStatus.paid
                : CalendarPaymentStatus.none,
            reason: '$date',
          );
          if (date.isAfter(DateTime(now.year, now.month, now.day))) {
            final button = tester.widget<InkWell>(
              find.ancestor(of: cell, matching: find.byType(InkWell)).first,
            );
            expect(button.onTap, isNull);
          }
        }
        if (offset < 3) {
          final next = find.byTooltip('Next Month');
          await tester.ensureVisible(next);
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
      }
      expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
      expect(gym.getAllPendingDues(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 320.0]) {
    testWidgets(
      'calendar toggle, legend and live payment update at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        final c = await gym.addCustomer(
          name: 'Calendar QA',
          phone: '2025550163',
          joinDate: start,
          membershipStartDate: start,
          membershipEndDate: end,
          membershipFee: 600,
          markAsPaidNow: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CustomerDetailScreen(customerId: c.id, initialTabIndex: 1),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('show-calendar-payments'));
        await tester.scrollUntilVisible(
          toggle,
          180,
          scrollable: find.byType(Scrollable).last,
        );
        final dayKey = ValueKey(
          'attendance-day-${GymDateUtils.toDateKey(start)}',
        );
        final compactHeight = tester.getSize(find.byKey(dayKey)).height;
        final compactWidth = tester.getSize(find.byKey(dayKey)).width;
        expect(find.byType(CalendarPaymentIndicator), findsNothing);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(dayKey)).height,
          greaterThan(compactHeight),
        );
        expect(
          tester.getSize(find.byKey(dayKey)).width,
          greaterThan(compactWidth),
        );
        for (final label in ['Paid', 'Part paid', 'Due', 'No payment period']) {
          expect(find.text(label), findsOneWidget);
        }
        CalendarPaymentStatus dayStatus() => tester
            .widget<CalendarPaymentIndicator>(
              find.descendant(
                of: find.byKey(dayKey),
                matching: find.byType(CalendarPaymentIndicator),
              ),
            )
            .status;
        expect(dayStatus(), CalendarPaymentStatus.due);
        final p = gym.getCustomerPaymentHistory(c.id).single;
        await gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: p.monthYear,
          amount: 200,
          totalDue: 600,
          method: PaymentMethod.cash,
          startDate: start,
          endDate: end,
          agreementId: p.id,
        );
        await tester.pumpAndSettle();
        expect(dayStatus(), CalendarPaymentStatus.partial);
        // Display changes must not create attendance or extra financial records.
        expect(gym.getAttendance(c.id, GymDateUtils.toDateKey(start)), isNull);
        expect(gym.getAllBillsForCustomer(c.id), hasLength(1));
        await tester.ensureVisible(find.byKey(dayKey));
        await tester.tap(find.byKey(dayKey));
        await tester.pumpAndSettle();
        expect(
          gym.getAttendance(c.id, GymDateUtils.toDateKey(start))?.status,
          AttendanceStatus.present,
        );
        expect(dayStatus(), CalendarPaymentStatus.partial);
        await gym.collectBalance(
          paymentId: p.id,
          amount: 400,
          method: PaymentMethod.cash,
        );
        await tester.pumpAndSettle();
        expect(dayStatus(), CalendarPaymentStatus.paid);
        expect(gym.getAllBillsForCustomer(c.id), hasLength(2));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.byType(CalendarPaymentIndicator), findsNothing);
        expect(tester.getSize(find.byKey(dayKey)).height, compactHeight);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await gym.detachUser();
      },
    );
  }
}
