import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/member_card_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';

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

  Future<Customer> register({
    DateTime? start,
    DateTime? end,
    int months = 1,
    double fee = 750,
  }) {
    final join = start ?? DateTime(2024, 9, 15);
    return gym.addCustomer(
      name: 'Cycle member',
      phone: '9876543210',
      joinDate: join,
      membershipStartDate: join,
      membershipEndDate: end,
      membershipFee: fee,
      planDurationMonths: months,
    );
  }

  MonthCardData month(Customer member, int year, int month, DateTime asOf) =>
      gym.getYearlyCardData(member.id, year, asOf: asOf)[month - 1];

  test('zero presence never creates card dues, even after expiry', () async {
    final member = await register();
    await gym.toggleAttendance(
      member.id,
      '2024-09-15',
      AttendanceStatus.absent,
    );
    final data = gym.getYearlyCardData(
      member.id,
      2024,
      asOf: DateTime(2024, 12, 1),
    );
    expect(data.where((m) => m.isDue), isEmpty);
    expect(data.fold<double>(0, (sum, m) => sum + m.outstandingAmount), 0);
    expect(data[8].formattedDateRange, '15 Sep – 14 Oct');
  });

  test(
    'active attended cycle shows dates and becomes due after inclusive end',
    () async {
      final member = await register(end: DateTime(2024, 10, 15));
      // Attendance in October belongs to the cycle starting in September.
      await gym.toggleAttendance(
        member.id,
        '2024-10-08',
        AttendanceStatus.present,
      );
      final active = month(member, 2024, 9, DateTime(2024, 10, 8));
      expect(active.formattedDateRange, '15 Sep – 15 Oct');
      expect(active.isDue, isFalse);
      expect(
        month(member, 2024, 9, DateTime(2024, 10, 15, 23, 59)).isDue,
        isFalse,
      );
      final expired = month(member, 2024, 9, DateTime(2024, 10, 16));
      expect(expired.isDue, isTrue);
      expect(expired.dueAmount, 750);
      expect(month(member, 2024, 10, DateTime(2024, 10, 16)).isDue, isFalse);
    },
  );

  test('attendance correction removes card dues', () async {
    final member = await register();
    await gym.toggleAttendance(
      member.id,
      '2024-09-16',
      AttendanceStatus.present,
    );
    expect(month(member, 2024, 9, DateTime(2024, 11, 1)).isDue, isTrue);
    await gym.toggleAttendance(
      member.id,
      '2024-09-16',
      AttendanceStatus.absent,
    );
    expect(month(member, 2024, 9, DateTime(2024, 11, 1)).isDue, isFalse);
  });

  test(
    'default anniversary boundary and future attendance are respected',
    () async {
      final member = await register();
      await gym.toggleAttendance(
        member.id,
        '2024-09-20',
        AttendanceStatus.present,
      );
      expect(month(member, 2024, 9, DateTime(2024, 9, 19)).isDue, isFalse);
      expect(month(member, 2024, 9, DateTime(2024, 10, 14)).isDue, isFalse);
      expect(month(member, 2024, 9, DateTime(2024, 10, 15)).isDue, isTrue);
    },
  );

  test(
    'multi-month dues use the frozen fee once in the cycle start month',
    () async {
      final member = await register(months: 3, fee: 1800.50);
      await gym.toggleAttendance(
        member.id,
        '2024-10-08',
        AttendanceStatus.present,
      );
      await gym.updateSettings(gym.settings.copyWith(standardMonthlyFee: 999));
      final data = gym.getYearlyCardData(
        member.id,
        2024,
        asOf: DateTime(2024, 12, 15),
      );
      expect(data.where((m) => m.isDue).map((m) => m.month), [9]);
      expect(data[8].dueAmount, 1800.50);
      expect(data[8].formattedDateRange, '15 Sep – 14 Dec');
    },
  );

  test('year-crossing cycle remains in its start year', () async {
    final member = await register(start: DateTime(2024, 12, 15));
    await gym.toggleAttendance(
      member.id,
      '2025-01-08',
      AttendanceStatus.present,
    );
    final due = month(member, 2024, 12, DateTime(2025, 1, 15));
    expect(due.isDue, isTrue);
    expect(due.formattedDateRange, '15 Dec 2024 – 14 Jan 2025');
    expect(
      gym
          .getYearlyCardData(member.id, 2025, asOf: DateTime(2025, 1, 15))
          .where((m) => m.isDue),
      isEmpty,
    );
  });

  test('paid coverage and its partial balance are counted once', () async {
    final member = await register();
    final agreement = gym.getCustomerPaymentHistory(member.id).single;
    await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: agreement.monthYear,
      agreementId: agreement.id,
      method: PaymentMethod.cash,
      amount: 250,
      paidAt: DateTime(2024, 9, 15),
    );
    final data = gym.getYearlyCardData(
      member.id,
      2024,
      asOf: DateTime(2024, 10, 8),
    );
    expect(data[8].isPaid, isTrue);
    expect(data[9].isPaid, isTrue);
    expect(data.where((m) => m.isDue), isEmpty);
    expect(data.fold<double>(0, (sum, m) => sum + m.outstandingAmount), 500);
  });

  test(
    'legacy attendance-derived cycle supplies its fee and date range',
    () async {
      final member = await gym.addCustomer(
        name: 'Legacy member',
        phone: '9876543211',
        joinDate: DateTime(2024, 9, 15),
      );
      expect(
        month(member, 2024, 9, DateTime(2024, 10, 8)).formattedDateRange,
        '15 Sep – 14 Oct',
      );
      await gym.toggleAttendance(
        member.id,
        '2024-09-15',
        AttendanceStatus.present,
      );
      final data = month(member, 2024, 9, DateTime(2024, 10, 15));
      expect(data.isDue, isTrue);
      expect(data.dueAmount, greaterThan(0));
      expect(data.formattedDateRange, '15 Sep – 14 Oct');
    },
  );

  testWidgets('card renders attended dues with dates and matching total', (
    tester,
  ) async {
    final year = DateTime.now().year - 1;
    final start = DateTime(year, 9, 15);
    final member = await register(start: start);
    await gym.toggleAttendance(
      member.id,
      GymDateUtils.toDateKey(start),
      AttendanceStatus.present,
    );
    await tester.pumpWidget(
      MaterialApp(home: MemberCardScreen(customer: member)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$year').last);
    await tester.pumpAndSettle();
    expect(
      find.text('DUE (${GymDateUtils.formatCurrency(750)})'),
      findsOneWidget,
    );
    expect(find.text('15 Sep – 14 Oct'), findsOneWidget);
    expect(
      find.textContaining('Total Due: ${GymDateUtils.formatCurrency(750)}'),
      findsOneWidget,
    );
    expect(find.textContaining('(1 unpaid)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current cycle without attendance shows dates without dues', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final member = await register(start: start);
    await tester.pumpWidget(
      MaterialApp(home: MemberCardScreen(customer: member)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('DUE ('), findsNothing);
    expect(find.textContaining('Total Due:'), findsNothing);
    expect(
      find.text(
        GymDateUtils.formatCardDateRange(
          start,
          GymDateUtils.computeAnniversaryEndDate(start, 1),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
