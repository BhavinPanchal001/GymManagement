import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  late Customer member;

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    member = await gym.addCustomer(
      name: 'Mid month member',
      phone: '9876543210',
      joinDate: DateTime(2020, 8, 5),
    );
  });
  tearDown(() => gym.detachUser());

  Future<void> pay(DateTime start, DateTime end) async {
    await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '${start.year}-${start.month.toString().padLeft(2, '0')}',
      method: PaymentMethod.cash,
      amount: 600,
      totalDue: 600,
      startDate: start,
      endDate: end,
    );
  }

  test(
    'individual and bulk attendance reject every status before joining',
    () async {
      for (final status in AttendanceStatus.values) {
        await gym.toggleAttendance(
          member.id,
          '2020-08-04',
          status,
          toggle: false,
        );
        expect(gym.getAttendance(member.id, '2020-08-04'), isNull);
      }
      await gym.setMonthAttendance(
        customerId: member.id,
        year: 2020,
        month: 8,
        status: AttendanceStatus.present,
      );
      expect(gym.getAttendance(member.id, '2020-08-04'), isNull);
      expect(
        gym.getAttendance(member.id, '2020-08-05')?.status,
        AttendanceStatus.present,
      );
    },
  );

  testWidgets(
    'September attendance already paid by August cycle has no settlement button',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pay(DateTime(2020, 8, 5), DateTime(2020, 9, 4));
      for (final date in ['2020-09-01', '2020-09-02']) {
        await gym.toggleAttendance(
          member.id,
          date,
          AttendanceStatus.present,
          toggle: false,
        );
      }
      expect(gym.getUnpaidAttendedDaysInMonth(member.id, '2020-09'), 0);
      expect(gym.getPaymentRecord(member.id, '2020-09').isPaid, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerDetailScreen(customerId: member.id, initialTabIndex: 1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next Month'));
      await tester.pumpAndSettle();
      expect(find.text('Settle Dues'), findsNothing);
      expect(find.text('Pay Now'), findsNothing);
      expect(find.textContaining('ACTIVE COVERAGE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'paid cycle gap is September 5–19 and adjacent cycles have no gap',
    () async {
      await pay(DateTime(2020, 8, 5), DateTime(2020, 9, 4));
      await pay(DateTime(2020, 9, 20), DateTime(2020, 10, 19));
      final gap = gym.getMembershipGaps(member.id).single;
      expect(gap.start, DateTime(2020, 9, 5));
      expect(gap.end, DateTime(2020, 9, 19));
      expect(gap.days, 15);
      expect(gap.attendedDays, 0);
      await pay(DateTime(2020, 10, 20), DateTime(2020, 11, 19));
      expect(gym.getMembershipGaps(member.id), hasLength(1));
    },
  );

  test(
    'attendance within a coverage gap is counted instead of labelled a break',
    () async {
      await pay(DateTime(2020, 8, 5), DateTime(2020, 9, 4));
      await pay(DateTime(2020, 9, 20), DateTime(2020, 10, 19));
      await gym.toggleAttendance(
        member.id,
        '2020-09-10',
        AttendanceStatus.present,
        toggle: false,
      );
      expect(gym.getMembershipGaps(member.id).single.attendedDays, 1);
    },
  );
  test(
    'return after a break starts new dues on September 20, with no overlap',
    () async {
      await pay(DateTime(2020, 8, 5), DateTime(2020, 9, 4));
      for (final date in ['2020-09-01', '2020-09-02', '2020-09-20']) {
        await gym.toggleAttendance(
          member.id,
          date,
          AttendanceStatus.present,
          toggle: false,
        );
      }
      final due = gym.getPaymentRecord(member.id, '2020-09');
      expect(due.effectiveStartDate, DateTime(2020, 9, 20));
      expect(due.effectiveEndDate, DateTime(2020, 10, 19));
      expect(
        gym.findOverlappingPaidPayment(
          customerId: member.id,
          startDate: due.effectiveStartDate,
          endDate: due.effectiveEndDate,
        ),
        isNull,
      );
      await gym.markPaymentAsPaid(
        customerId: member.id,
        monthYear: due.monthYear,
        method: PaymentMethod.cash,
        amount: due.totalDue,
        totalDue: due.totalDue,
        startDate: due.effectiveStartDate,
        endDate: due.effectiveEndDate,
        agreementId: due.id,
      );
      expect(gym.getUnpaidAttendedDaysInMonth(member.id, '2020-09'), 0);
      expect(gym.getMembershipGaps(member.id).single.days, 15);
    },
  );
}
