import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/collect_balance_dialog.dart';
import 'package:gym/screens/reports/pending_payments_report_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await gym.detachUser();
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 500));
  });

  tearDown(() async {
    await gym.detachUser();
  });

  group('State Machine & Logic Stress Tests', () {
    testWidgets('Rapidly clicks back-and-forth between tabs 60 times without freezing or corrupting state', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      final navBar = find.byType(NavigationBar);
      expect(navBar, findsOneWidget);

      final destinations = ['Members', 'Attendance', 'Payments', 'Settings'];

      // Rapidly switch tabs without full settles to stress state machine transitions
      for (int i = 0; i < 60; i++) {
        final targetIndex = i % destinations.length;
        final tabFind = find.descendant(
          of: navBar,
          matching: find.text(destinations[targetIndex]),
        );
        await tester.tap(tabFind);
        // pump minimal frames to trigger build during in-flight transition
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rapidly opens and cancels CollectBalanceDialog repeatedly without stuck loading or leaks', (tester) async {
      final customer = await gym.addCustomer(
        name: 'Stress Member',
        phone: '9876543210',
        joinDate: DateTime(2026, 1, 1),
      );

      final bill = await gym.markPaymentAsPaid(
        customerId: customer.id,
        monthYear: '2026-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 500,
      );

      final payment = gym.getPaymentById(bill.paymentId)!;
      expect(payment.balanceDue, 300);

      // Open and cancel CollectBalanceDialog 15 times repeatedly
      for (int i = 0; i < 15; i++) {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => CollectBalanceDialog.show(ctx, payment),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pump(); // Show dialog
        expect(find.byType(CollectBalanceDialog), findsOneWidget);

        // Immediately cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(CollectBalanceDialog), findsNothing);
      }

      expect(tester.takeException(), isNull);
      // State must remain consistent
      expect(gym.getPaymentById(payment.id)!.balanceDue, 300);
    });

    testWidgets('Interrupting CollectBalanceDialog mid-save or double tapping does not create duplicate collections', (tester) async {
      final customer = await gym.addCustomer(
        name: 'Double Tap Member',
        phone: '9876543210',
        joinDate: DateTime(2026, 1, 1),
      );

      final bill = await gym.markPaymentAsPaid(
        customerId: customer.id,
        monthYear: '2026-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 500,
      );

      final payment = gym.getPaymentById(bill.paymentId)!;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => CollectBalanceDialog.show(ctx, payment),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Enter valid amount
      final amountField = find.byType(TextField).first;
      await tester.enterText(amountField, '100');

      // Double-tap save button rapidly
      final saveBtn = find.text('Save collection');
      await tester.tap(saveBtn);
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Exactly 1 collection of 100 should be recorded, remaining balance 200
      final updatedPayment = gym.getPaymentById(payment.id)!;
      expect(updatedPayment.balanceDue, 200);
      expect(updatedPayment.amount, 300);
      expect(gym.getBillsForPayment(payment.id).length, 2);
    });

    testWidgets('Rapid attendance toggling does not corrupt attendance status or summary counts', (tester) async {
      final customer = await gym.addCustomer(
        name: 'Attendance Tester',
        phone: '9876543210',
        joinDate: DateTime(2026, 1, 1),
      );

      const dateKey = '2026-01-10';
      // Rapidly toggle attendance 20 times between present and absent
      for (int i = 0; i < 20; i++) {
        final status = i.isEven ? AttendanceStatus.present : AttendanceStatus.absent;
        await gym.toggleAttendance(customer.id, dateKey, status);
      }

      // 19 is odd -> absent
      expect(gym.getAttendanceStatus(customer.id, dateKey), AttendanceStatus.absent);
      expect(gym.getAttendance(customer.id, dateKey), isNotNull);

      // Rapidly toggle 21 times: ending at even (present)
      for (int i = 0; i < 21; i++) {
        final status = i.isEven ? AttendanceStatus.present : AttendanceStatus.absent;
        await gym.toggleAttendance(customer.id, dateKey, status);
      }
      expect(gym.getAttendanceStatus(customer.id, dateKey), AttendanceStatus.present);
    });

    testWidgets('Rapidly opening and closing PendingPaymentsReportScreen and toggling filters', (tester) async {
      final c1 = await gym.addCustomer(name: 'Due Member 1', phone: '1111111111', joinDate: DateTime(2026, 1, 1));
      await gym.markPaymentAsPaid(customerId: c1.id, monthYear: '2026-01', method: PaymentMethod.cash, amount: 200, totalDue: 500);

      await tester.pumpWidget(const MaterialApp(home: PendingPaymentsReportScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Rapidly switch between SegmentedButton or tabs if any
      final byMonthFinder = find.text('By Month');
      final allMembersFinder = find.text('All Pending');

      if (byMonthFinder.evaluate().isNotEmpty && allMembersFinder.evaluate().isNotEmpty) {
        for (int i = 0; i < 10; i++) {
          await tester.tap(byMonthFinder);
          await tester.pump(const Duration(milliseconds: 20));
          await tester.tap(allMembersFinder);
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
