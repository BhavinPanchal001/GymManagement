import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/danger_confirmation_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('TASK-01: GymService Data Safety Guards', () {
    test('resetToDemoData blocks wipe when customers exist unless force: true', () async {
      final gym = GymService();

      // Seed a customer
      await gym.resetToDemoData(force: true);
      expect(gym.customers.isNotEmpty, true);
      final initialCount = gym.customers.length;

      // Attempt to reset without force
      final successWithoutForce = await gym.resetToDemoData();
      expect(successWithoutForce, false);
      expect(gym.customers.length, initialCount);

      // Attempt to reset with force: true
      final successWithForce = await gym.resetToDemoData(force: true);
      expect(successWithForce, true);
      expect(gym.customers.isNotEmpty, true);
    });

    test('clearAllGymData blocks wipe when customers exist unless force: true', () async {
      final gym = GymService();

      // Seed demo data first
      await gym.resetToDemoData(force: true);
      expect(gym.customers.isNotEmpty, true);

      // Attempt clear without force
      final successWithoutForce = await gym.clearAllGymData();
      expect(successWithoutForce, false);
      expect(gym.customers.isNotEmpty, true);

      // Attempt clear with force
      final successWithForce = await gym.clearAllGymData(force: true);
      expect(successWithForce, true);
      expect(gym.customers.isEmpty, true);
      expect(gym.expenses.isEmpty, true);
      expect(gym.attendanceRecordCount, 0);
      expect(gym.paymentRecordCount, 0);
    });
  });

  group('TASK-01: DangerConfirmationDialog Widget Tests', () {
    testWidgets('renders danger badge, record counts, and requires exact phrase', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await DangerConfirmationDialog.show(
                    context,
                    title: 'Reset to Demo Data?',
                    description: 'This will erase all records.',
                    actionLabel: 'Reset to Demo',
                    confirmationPhrase: 'DELETE ALL DATA',
                    memberCount: 25,
                    attendanceCount: 150,
                    paymentCount: 30,
                    billCount: 30,
                    expenseCount: 10,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify header and danger elements
      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('Reset to Demo Data?'), findsOneWidget);
      expect(find.text('25 Members'), findsOneWidget);
      expect(find.text('150 Attendance'), findsOneWidget);
      expect(find.text('30 Payments'), findsOneWidget);
      expect(find.text('30 Invoices'), findsOneWidget);
      expect(find.text('10 Expenses'), findsOneWidget);

      // Confirm button should initially be disabled
      final confirmButtonFinder = find.widgetWithText(ElevatedButton, 'Reset to Demo');
      expect(confirmButtonFinder, findsOneWidget);
      final elevatedButton = tester.widget<ElevatedButton>(confirmButtonFinder);
      expect(elevatedButton.onPressed, isNull);

      // Type partial or wrong phrase
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(confirmButtonFinder).onPressed, isNull);

      // Type exact phrase
      await tester.enterText(find.byType(TextField), 'DELETE ALL DATA');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(confirmButtonFinder).onPressed, isNotNull);

      // Tap confirm button
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      // Verify dialog returned true
      expect(result, true);
    });

    testWidgets('cancel button safely closes dialog and returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await DangerConfirmationDialog.show(
                    context,
                    title: 'Clear All Gym Data?',
                    description: 'Clear everything.',
                    actionLabel: 'Clear All Data',
                    confirmationPhrase: 'DELETE ALL DATA',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, false);
    });
  });
}
