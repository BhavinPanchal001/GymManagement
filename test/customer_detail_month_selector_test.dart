import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });

  tearDown(() async => gym.detachUser());

  testWidgets('Payments tab has month selector above payment card, syncs with attendance view, and has expandable dues card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final customer = await gym.addCustomer(
      name: 'Sync Member',
      phone: '9876543210',
      joinDate: DateTime(now.year, now.month, 1),
      planType: CustomerPlan.normal,
      planDurationMonths: 1,
      markAsPaidNow: false,
      membershipFee: 600.0,
      membershipStartDate: DateTime(now.year, now.month, 1),
      membershipEndDate: DateTime(now.year, now.month, GymDateUtils.daysInMonth(now.year, now.month)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerDetailScreen(customerId: customer.id),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Current Dues card is rendered and collapsed by default
    expect(find.text('Current Dues'), findsOneWidget);
    expect(find.byKey(const ValueKey('due-upcoming')), findsNothing);

    // Tap to expand Current Dues card
    await tester.tap(find.text('Current Dues'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('due-upcoming')), findsOneWidget);
    expect(find.byKey(const ValueKey('due-attendedInPlan')), findsOneWidget);
    expect(find.byKey(const ValueKey('due-overdue')), findsOneWidget);

    // Tap to collapse Current Dues card again
    await tester.tap(find.text('Current Dues'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('due-upcoming')), findsNothing);

    // 2. Verify Month Selector Header is rendered on Payments Tab
    final currentMonthLabel = GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(now));
    expect(find.text(currentMonthLabel), findsOneWidget);

    // Verify current month payment card is visible
    expect(find.text('$currentMonthLabel Payment'), findsOneWidget);

    // 3. Tap Previous Month button on Payments Tab
    final prevMonthButton = find.byTooltip('Previous Month');
    expect(prevMonthButton, findsOneWidget);
    await tester.tap(prevMonthButton);
    await tester.pumpAndSettle();

    final prevMonthDate = DateTime(now.year, now.month - 1, 1);
    final prevMonthLabel = GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(prevMonthDate));

    // Payments Tab should now show previous month
    expect(find.text(prevMonthLabel), findsOneWidget);
    expect(find.text('$prevMonthLabel Payment'), findsOneWidget);

    // 4. Switch to Attendance Tab (Tab 2)
    final attendanceTab = find.text('Attendance');
    await tester.tap(attendanceTab);
    await tester.pumpAndSettle();

    // Attendance view must also display the previous month!
    expect(find.text(prevMonthLabel), findsWidgets);
    // Attendance overview card should show the previous month label
    expect(
      find.descendant(
        of: find.byType(CustomerDetailScreen),
        matching: find.text(prevMonthLabel),
      ),
      findsWidgets,
    );
  });
}
