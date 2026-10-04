import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  Future<Customer> register(String name, DateTime start, {double fee = 600}) =>
      gym.addCustomer(
        name: name,
        phone: '98765${name.length}3210',
        joinDate: start,
        planDurationMonths: 1,
        membershipStartDate: start,
        membershipFee: fee,
        operationId: 'register-$name',
      );

  Future<void> attend(Customer c, DateTime day) => gym.toggleAttendance(
    c.id,
    GymDateUtils.toDateKey(day),
    AttendanceStatus.present,
    toggle: false,
  );

  test('running plan without attendance can be paid later', () async {
    final c = await register('Later', today.subtract(const Duration(days: 3)));
    final dues = gym.getMemberDueBreakdown(c.id);
    expect(dues.upcoming.count, 1);
    expect(dues.upcoming.amount, 600);
    expect(dues.attendedInPlan.count, 0);
    expect(dues.overdue.count, 0);
  });

  test('plan starting in the future is not yet compulsory', () async {
    final c = await register('Future', today.add(const Duration(days: 5)));
    final dues = gym.getMemberDueBreakdown(c.id);
    expect(dues.upcoming.count, 1);
    expect(dues.attendedInPlan.count, 0);
    expect(dues.overdue.count, 0);
  });

  test('attendance in a running plan makes it payable now', () async {
    final c = await register('Now', today.subtract(const Duration(days: 3)));
    await attend(c, today.subtract(const Duration(days: 1)));
    final dues = gym.getMemberDueBreakdown(c.id);
    expect(dues.upcoming.count, 0);
    expect(dues.attendedInPlan.count, 1);
    expect(dues.attendedInPlan.amount, 600);
    expect(dues.overdue.count, 0);

    await gym.toggleAttendance(
      c.id,
      GymDateUtils.toDateKey(today.subtract(const Duration(days: 1))),
      AttendanceStatus.absent,
      toggle: false,
    );
    expect(gym.getMemberDueBreakdown(c.id).upcoming.count, 1);
    expect(gym.getMemberDueBreakdown(c.id).attendedInPlan.count, 0);
  });

  test('ended plans with attendance are overdue, one per plan', () async {
    final start = DateTime(today.year, today.month - 4, 1);
    final c = await register('Overdue', start);
    await attend(c, start.add(const Duration(days: 2)));
    // Attendance after the first plan ended creates a second unpaid plan.
    final second = DateTime(today.year, today.month - 2, 10);
    await attend(c, second);
    final dues = gym.getMemberDueBreakdown(c.id);
    expect(dues.overdue.count, 2);
    expect(
      dues.overdue.amount,
      600 + gym.settings.getPriceForDuration(c.planType, c.planDurationMonths),
    );
    expect(
      dues.overdue.earliestEndDate,
      gym
          .getCustomerPaymentHistory(c.id)
          .map((p) => p.effectiveEndDate)
          .reduce((a, b) => a.isBefore(b) ? a : b),
    );
    expect(dues.upcoming.count, 0);
    expect(dues.attendedInPlan.count, 0);
  });

  test(
    'partial balance is classified and fully paid plan clears dues',
    () async {
      final c = await register(
        'Partial',
        today.subtract(const Duration(days: 3)),
      );
      await attend(c, today.subtract(const Duration(days: 1)));
      final agreement = gym.getCustomerPaymentHistory(c.id).single;
      await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: agreement.monthYear,
        agreementId: agreement.id,
        amount: 200,
        method: PaymentMethod.cash,
        durationMonths: agreement.durationMonths,
        startDate: agreement.startDate,
        endDate: agreement.endDate,
        operationId: 'partial',
      );
      var dues = gym.getMemberDueBreakdown(c.id);
      expect(dues.totalCount, 1);
      expect(dues.attendedInPlan.amount, 400);

      final paid = gym.getPaidPaymentsForCustomer(c.id).single;
      await gym.collectBalance(
        paymentId: paid.id,
        amount: 400,
        method: PaymentMethod.cash,
        operationId: 'balance',
      );
      dues = gym.getMemberDueBreakdown(c.id);
      expect(dues.totalCount, 0);
      expect(dues.totalAmount, 0);
    },
  );

  testWidgets('member detail page shows the three due counts', (tester) async {
    late Customer c;
    await tester.runAsync(() async {
      c = await register('Widget', today.subtract(const Duration(days: 3)));
      await attend(c, today.subtract(const Duration(days: 1)));
    });
    await tester.pumpWidget(
      MaterialApp(home: CustomerDetailScreen(customerId: c.id)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current Dues'), findsOneWidget);
    // Card is expandable and collapsed by default
    expect(find.byKey(const ValueKey('due-upcoming')), findsNothing);

    // Tap to expand
    await tester.tap(find.text('Current Dues'));
    await tester.pumpAndSettle();

    for (final key in ['due-upcoming', 'due-attendedInPlan', 'due-overdue']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('Can Pay Later'), findsOneWidget);
    expect(find.text('Pay Now'), findsWidgets);
    expect(find.text('Overdue'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('due-attendedInPlan')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    // Tap to collapse
    await tester.tap(find.text('Current Dues'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('due-upcoming')), findsNothing);
  });
}
