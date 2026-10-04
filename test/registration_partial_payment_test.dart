import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';

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

  group('GymService Registration Payment Logic', () {
    test('addCustomer with pay later (markAsPaidNow: false) creates pending agreement', () async {
      final customer = await gym.addCustomer(
        name: 'Later User',
        phone: '9876543210',
        planType: CustomerPlan.normal,
        planDurationMonths: 1,
        membershipFee: 600.0,
        membershipStartDate: DateTime(2026, 10, 1),
        membershipEndDate: DateTime(2026, 10, 31),
        markAsPaidNow: false,
      );

      final payments = gym.getCustomerPaymentHistory(customer.id);
      expect(payments.length, 1);
      final payment = payments.first;
      expect(payment.isPaid, isFalse);
      expect(payment.status, PaymentStatus.pending);
      expect(payment.amount, 0.0);
      expect(payment.totalDue, 600.0);
      expect(payment.balanceDue, 600.0);
      expect(gym.getAllBillsForCustomer(customer.id).isEmpty, isTrue);
    });

    test('addCustomer with full payment (markAsPaidNow: true, paidAmount: null) settles fee', () async {
      final customer = await gym.addCustomer(
        name: 'Full User',
        phone: '9876543211',
        planType: CustomerPlan.normal,
        planDurationMonths: 1,
        markAsPaidNow: true,
        initialPaymentMethod: PaymentMethod.gpay,
      );

      final payments = gym.getCustomerPaymentHistory(customer.id);
      expect(payments.length, 1);
      final payment = payments.first;
      expect(payment.isPaid, isTrue);
      expect(payment.amount, 600.0);
      expect(payment.totalDue, 600.0);
      expect(payment.balanceDue, 0.0);
      expect(payment.isPartiallyPaid, isFalse);
      expect(payment.method, PaymentMethod.gpay);

      final bills = gym.getAllBillsForCustomer(customer.id);
      expect(bills.length, 1);
      expect(bills.first.amount, 600.0);
      expect(bills.first.billType, 'FULL');
      expect(bills.first.method, PaymentMethod.gpay);
    });

    test('addCustomer with partial payment records advance and tracks remaining balance due', () async {
      final customer = await gym.addCustomer(
        name: 'Partial User',
        phone: '9876543212',
        planType: CustomerPlan.normal,
        planDurationMonths: 1,
        markAsPaidNow: true,
        paidAmount: 250.0,
        initialPaymentMethod: PaymentMethod.cash,
      );

      final payments = gym.getCustomerPaymentHistory(customer.id);
      expect(payments.length, 1);
      final payment = payments.first;
      expect(payment.isPaid, isTrue);
      expect(payment.amount, 250.0);
      expect(payment.totalDue, 600.0);
      expect(payment.balanceDue, 350.0);
      expect(payment.isPartiallyPaid, isTrue);
      expect(payment.method, PaymentMethod.cash);

      final bills = gym.getAllBillsForCustomer(customer.id);
      expect(bills.length, 1);
      expect(bills.first.amount, 250.0);
      expect(bills.first.billType, 'PARTIAL');
      expect(bills.first.method, PaymentMethod.cash);

      // Verify that the remaining balance can be collected via collectBalance
      final balanceBill = await gym.collectBalance(
        paymentId: payment.id,
        amount: 350.0,
        method: PaymentMethod.upi,
      );
      expect(balanceBill.amount, 350.0);
      expect(balanceBill.billType, 'BALANCE');

      final updatedPayment = gym.getPaymentById(payment.id)!;
      expect(updatedPayment.amount, 600.0);
      expect(updatedPayment.balanceDue, 0.0);
      expect(updatedPayment.isPartiallyPaid, isFalse);
    });
  });

  group('AddCustomerSheet Widget & UI Layout', () {
    testWidgets('Essential details are shown first and optional details are collapsed by default', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => AddCustomerSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Essential details must be present and visible
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(find.text('Card No.'), findsOneWidget);
      expect(find.text('Joining Date'), findsOneWidget);
      expect(find.text('Membership Plan'), findsOneWidget);
      expect(find.text('Normal Plan'), findsOneWidget);
      expect(find.text('Package Duration (Combo Pricing)'), findsOneWidget);
      expect(find.text('Registration Payment'), findsOneWidget);

      // Optional details header is visible, but inner fields are collapsed
      expect(find.text('Optional Details'), findsOneWidget);
      expect(find.text('Address, Body Measurements, Workout Notes'), findsOneWidget);

      // Tap optional details to expand
      await tester.ensureVisible(find.text('Optional Details'));
      await tester.tap(find.text('Optional Details'));
      await tester.pumpAndSettle();

      // Now optional fields are revealed
      expect(find.text('Address (Optional)'), findsOneWidget);
      expect(find.text('Workout Notes / Goals (Optional)'), findsOneWidget);
      expect(find.text('Body Measurements (Entry Card)'), findsOneWidget);
      expect(find.text('Weight (Wt)'), findsOneWidget);
    });

    testWidgets('Payment mode selector toggles between Pay Later, Partial, and Full Paid', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => AddCustomerSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Mode tabs
      expect(find.text('Pay Later'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
      expect(find.text('Full Paid'), findsOneWidget);

      // Tap Partial
      await tester.ensureVisible(find.text('Partial'));
      await tester.tap(find.text('Partial'));
      await tester.pumpAndSettle();

      // Amount received input and shortcut chips appear
      expect(find.text('Amount Received Today'), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.text('Paid Today'), findsOneWidget);
      expect(find.text('Remaining Balance Due'), findsOneWidget);

      // Tap 50% shortcut chip
      await tester.tap(find.textContaining('50%'));
      await tester.pumpAndSettle();

      // Check that 300 is entered (50% of 600)
      expect(find.text('₹300'), findsAtLeast(1));

      // Tap Full Paid
      await tester.tap(find.text('Full Paid'));
      await tester.pumpAndSettle();
      expect(find.text('Full Fee Settled Upfront'), findsOneWidget);

      // Tap Pay Later
      await tester.tap(find.text('Pay Later'));
      await tester.pumpAndSettle();
      expect(find.textContaining('will be marked pending'), findsOneWidget);
    });

    testWidgets('Registering a member with partial payment saves correctly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => AddCustomerSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter name & phone
      await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'), 'Partial Flow Member');
      await tester.enterText(find.byType(TextFormField).at(1), '9876543219');

      // Select Partial Payment
      await tester.ensureVisible(find.text('Partial'));
      await tester.tap(find.text('Partial'));
      await tester.pumpAndSettle();

      // Tap 50% chip (300)
      await tester.tap(find.textContaining('50%'));
      await tester.pumpAndSettle();

      // Submit registration
      final submitButton = find.text('Register Member');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Verify member saved in gym roster
      final member = gym.customers.firstWhere((c) => c.name == 'Partial Flow Member');
      expect(member.phone, '9876543219');

      final payment = gym.getCustomerPaymentHistory(member.id).first;
      expect(payment.isPaid, isTrue);
      expect(payment.amount, 300.0);
      expect(payment.totalDue, 600.0);
      expect(payment.balanceDue, 300.0);
      expect(payment.isPartiallyPaid, isTrue);

      final bill = gym.getAllBillsForCustomer(member.id).first;
      expect(bill.amount, 300.0);
      expect(bill.billType, 'PARTIAL');
    });

    testWidgets('Editing a member with existing optional data initializes expanded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final existing = await gym.addCustomer(
        name: 'Existing Member',
        phone: '9888877777',
        address: '123 Main Street',
        weight: '75',
        notes: 'Morning workout slot',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => AddCustomerSheet.show(ctx, customerToEdit: existing),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Optional details should start expanded because address and notes are populated
      expect(find.text('Address (Optional)'), findsOneWidget);
      expect(find.text('123 Main Street'), findsOneWidget);
      expect(find.text('Morning workout slot'), findsOneWidget);
      expect(find.text('Filled'), findsOneWidget);
    });
  });
}
