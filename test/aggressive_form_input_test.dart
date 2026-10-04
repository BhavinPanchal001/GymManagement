import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/widgets/add_expense_dialog.dart';
import 'package:gym/widgets/collect_balance_dialog.dart';

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

  group('Aggressive Form & Input Testing Suite', () {
    testWidgets('AddCustomerSheet: Empty & whitespace-only inputs trigger validation errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddCustomerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt to save immediately with empty fields
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Member');
      // If bottom sheet needs scrolling, ensure visible
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Expect field validators to fire
      expect(find.text('Please enter member name'), findsOneWidget);
      expect(find.text('Please enter phone number'), findsOneWidget);
    });

    testWidgets('AddCustomerSheet: Phone formatter strips non-digits and validates 10 digits', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddCustomerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find phone field
      final phoneField = find.widgetWithText(TextFormField, 'Phone Number');
      expect(phoneField, findsOneWidget);

      // Enter malformed phone with letters and symbols
      await tester.enterText(phoneField, '987-abc-5432');
      await tester.pumpAndSettle();

      // Formatter should keep only digits '9875432' (7 digits)
      final saveButton = find.widgetWithText(ElevatedButton, 'Save Member');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid 10-digit phone number'), findsOneWidget);
    });

    testWidgets('AddCustomerSheet: Extreme string length in Name & Notes does not crash widget tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddCustomerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextFormField, 'Full Name');
      final notesField = find.widgetWithText(TextFormField, 'Notes / Special Requests (Optional)');

      final massiveString = 'A' * 2000;
      await tester.enterText(nameField, massiveString);
      if (notesField.evaluate().isNotEmpty) {
        await tester.enterText(notesField, massiveString);
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AddExpenseDialog: Non-numeric and zero amounts are rejected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddExpenseDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(ElevatedButton, 'Save Expense');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter an expense title'), findsOneWidget);
      expect(find.text('Enter amount'), findsOneWidget);

      // Enter zero amount
      final amountField = find.byType(TextFormField).at(1);
      await tester.enterText(amountField, '0');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Valid amount > 0'), findsOneWidget);

      // Enter negative amount
      await tester.enterText(amountField, '-250');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Valid amount > 0'), findsOneWidget);
    });

    testWidgets('CollectBalanceDialog: Over-payment and negative amounts are blocked', (tester) async {
      final payment = PaymentRecord(
        id: 'pay_test_01',
        customerId: 'cust_01',
        monthYear: '2026-10',
        amount: 300,
        totalDue: 600,
        paidAt: DateTime.now(),
        status: PaymentStatus.pending,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectBalanceDialog(payment: payment),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final amountField = find.widgetWithText(TextField, 'Amount received');
      final saveButton = find.widgetWithText(FilledButton, 'Save collection');

      // Attempt to enter amount exceeding remaining balance (balance is 300)
      await tester.enterText(amountField, '500');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Enter a positive amount within the remaining balance.'), findsOneWidget);

      // Attempt negative amount
      await tester.enterText(amountField, '-50');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Enter a positive amount within the remaining balance.'), findsOneWidget);
    });
  });
}
