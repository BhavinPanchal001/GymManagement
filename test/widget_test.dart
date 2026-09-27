import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/whatsapp_service.dart';
import 'package:gym/services/phone_service.dart';
import 'package:gym/widgets/mark_month_attendance_dialog.dart';
import 'package:gym/services/auth_service.dart';
import 'package:gym/widgets/user_avatar.dart';
import 'package:gym/screens/settings/edit_profile_screen.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/widgets/gym_logo_widget.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/plan_package.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/screens/splash/splash_screen.dart';
import 'package:gym/screens/intro/intro_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GymService().init();
    await AuthService().init();
    final gym = GymService();
    if (gym.customers.isEmpty) {
      await gym.addCustomer(
        name: 'Demo Member',
        phone: '9876543210',
        joinDate: DateTime(2026, 7, 1),
      );
    }
  });

  test('GymService customer, attendance and payment logic test', () async {
    final gym = GymService();
    expect(gym.customers.isNotEmpty, true);

    final initialCount = gym.customers.length;
    // Test adding customer
    await gym.addCustomer(
      name: 'Test Member',
      phone: '+91 99999 88888',
      notes: 'Test notes',
    );
    expect(gym.customers.length, initialCount + 1);

    final testCustomer = gym.customers.firstWhere((c) => c.name == 'Test Member');
    expect(testCustomer.phone, '+91 99999 88888');

    // Test attendance toggle
    const testDateKey = '2026-09-17';
    await gym.toggleAttendance(testCustomer.id, testDateKey, AttendanceStatus.present);
    expect(gym.getAttendanceStatus(testCustomer.id, testDateKey), AttendanceStatus.present);

    // Test payment marking
    const testMonth = '2026-09';
    await gym.markPaymentAsPaid(
      customerId: testCustomer.id,
      monthYear: testMonth,
      method: PaymentMethod.gpay,
      amount: 1200,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
      transactionRef: 'UPI-TEST-123',
    );

    final payment = gym.getPaymentRecord(testCustomer.id, testMonth);
    expect(payment.isPaid, true);
    expect(payment.method, PaymentMethod.gpay);
    expect(payment.transactionRef, 'UPI-TEST-123');
  });

  test('GymService mark whole month present / absent logic test', () async {
    final gym = GymService();
    final customer = gym.customers.first;
    const testYear = 2026;
    const testMonth = 7; // July 2026 has 31 days and is in the past
    const monthKey = '2026-07';

    // 1. Mark month present with Sundays as Rest Day
    await gym.setMonthAttendance(
      customerId: customer.id,
      year: testYear,
      month: testMonth,
      status: AttendanceStatus.present,
      excludeSundays: true,
      sundayStatus: AttendanceStatus.rest,
    );

    var summary = gym.getMonthlyAttendanceSummary(customer.id, monthKey);
    // October 2026: 31 days total. Sundays are 4th, 11th, 18th, 25th (4 Sundays)
    expect(summary['rest'], 4);
    expect(summary['present'], 27);
    expect(summary['absent'], 0);

    // 2. Mark month whole absent
    await gym.setMonthAttendance(
      customerId: customer.id,
      year: testYear,
      month: testMonth,
      status: AttendanceStatus.absent,
    );

    summary = gym.getMonthlyAttendanceSummary(customer.id, monthKey);
    expect(summary['absent'], 31);
    expect(summary['present'], 0);
    expect(summary['rest'], 0);

    // 3. Mark 100% present (excludeSundays: false)
    await gym.setMonthAttendance(
      customerId: customer.id,
      year: testYear,
      month: testMonth,
      status: AttendanceStatus.present,
      excludeSundays: false,
    );

    summary = gym.getMonthlyAttendanceSummary(customer.id, monthKey);
    expect(summary['present'], 31);
    expect(summary['absent'], 0);
    expect(summary['rest'], 0);

    // 4. Test setMonthAttendanceForMultiple
    final activeIds = gym.customers.where((c) => c.isActive).take(2).map((c) => c.id).toList();
    await gym.setMonthAttendanceForMultiple(
      customerIds: activeIds,
      year: testYear,
      month: testMonth,
      status: AttendanceStatus.absent,
    );

    for (final id in activeIds) {
      final s = gym.getMonthlyAttendanceSummary(id, monthKey);
      expect(s['absent'], 31);
      expect(s['present'], 0);
    }
  });

  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify app bar title
    expect(find.text('Gym Members'), findsOneWidget);
    // Verify navigation tabs
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('CustomerDetailScreen has Mark Month button and actions test', (WidgetTester tester) async {
    final gym = GymService();
    final customer = gym.customers.first;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerDetailScreen(
          customerId: customer.id,
          initialTabIndex: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Mark Month button is present
    expect(find.text('Mark Month'), findsOneWidget);

    // Tap Mark Month to open popup menu
    await tester.tap(find.text('Mark Month'));
    await tester.pumpAndSettle();

    // Verify popup menu options appear
    expect(find.text('Mark Present (Sundays Rest)'), findsOneWidget);
    expect(find.text('Mark 100% Present'), findsOneWidget);
    expect(find.text('Mark Whole Month Absent'), findsOneWidget);
    expect(find.text('More Options...'), findsOneWidget);

    // Tap 'Mark Whole Month Absent'
    await tester.tap(find.text('Mark Whole Month Absent'));
    await tester.pumpAndSettle();

    // Verify SnackBar appears
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('MarkMonthAttendanceDialog widget renders and applies test', (WidgetTester tester) async {
    final gym = GymService();
    final customer = gym.customers.first;
    final testMonth = DateTime(2026, 7, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => MarkMonthAttendanceDialog.show(
                ctx,
                customer: customer,
                month: testMonth,
              ),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Mark Month Attendance'), findsOneWidget);
    expect(find.text('SELECT STATUS TO MARK'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);
    expect(find.text('Rest Day'), findsOneWidget);
    expect(find.text('Keep Sundays as Rest Day'), findsOneWidget);
    expect(find.text('Apply to Month'), findsOneWidget);

    // Tap Apply to Month
    await tester.tap(find.text('Apply to Month'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Mark Month Attendance'), findsNothing);

    // Verify customer July attendance is present (with Sundays as rest)
    final summary = gym.getMonthlyAttendanceSummary(customer.id, '2026-07');
    expect(summary['present'], 27);
    expect(summary['rest'], 4);
  });

  test('WhatsAppService phone number normalization and message building test', () {
    final service = WhatsAppService();

    // Normalization tests
    expect(service.normalizePhoneNumber('+91 98765 43210'), '919876543210');
    expect(service.normalizePhoneNumber('9876543210'), '919876543210');
    expect(service.normalizePhoneNumber('09876543210'), '919876543210');
    expect(service.normalizePhoneNumber('+1 (555) 234-5678'), '15552345678');
    expect(service.normalizePhoneNumber(''), '');

    // Reminder message generation tests
    final standardMsg = service.buildReminderMessage(
      customerName: 'Rahul Sharma',
      monthYear: '2026-09',
      amount: 1200,
      currency: '₹',
      gymName: 'IronPulse Fitness Club',
      tone: ReminderTone.standard,
    );
    expect(standardMsg.contains('Rahul Sharma'), true);
    expect(standardMsg.contains('IronPulse Fitness Club'), true);
    expect(standardMsg.contains('🏋️ *Gym:* *IronPulse Fitness Club*'), true);
    expect(standardMsg.contains('— *Team IronPulse Fitness Club*'), true);
    expect(standardMsg.contains('₹1,200'), true);
    expect(standardMsg.contains('September 2026'), true);
    expect(standardMsg.contains('membership fee'), true);

    final friendlyMsg = service.buildReminderMessage(
      customerName: 'Pooja Patel',
      monthYear: '2026-09',
      amount: 1500,
      currency: '₹',
      gymName: 'IronPulse Fitness Club',
      tone: ReminderTone.friendly,
    );
    expect(friendlyMsg.contains('Pooja Patel'), true);
    expect(friendlyMsg.contains('stay strong'), true);
    expect(friendlyMsg.contains('workouts at *IronPulse Fitness Club*'), true);
    expect(friendlyMsg.contains('🏋️ *Gym:* *IronPulse Fitness Club*'), true);
    expect(friendlyMsg.contains('*Team IronPulse Fitness Club*'), true);

    final urgentMsg = service.buildReminderMessage(
      customerName: 'Amit Verma',
      monthYear: '2026-08',
      amount: 1200,
      currency: '₹',
      gymName: 'IronPulse Fitness Club',
      tone: ReminderTone.urgent,
    );
    expect(urgentMsg.contains('Overdue Fee Notice'), true);
    expect(urgentMsg.contains('Amit Verma'), true);
    expect(urgentMsg.contains('reminder from *IronPulse Fitness Club*'), true);
    expect(urgentMsg.contains('🏋️ *Gym:* *IronPulse Fitness Club*'), true);
    expect(urgentMsg.contains('— *Management, IronPulse Fitness Club*'), true);

    // Fallback to GymService settings gymName when gymName is omitted or empty
    final fallbackMsg = service.buildReminderMessage(
      customerName: 'Karan Mehra',
      monthYear: '2026-09',
      amount: 1200,
    );
    expect(fallbackMsg.contains(GymService().settings.gymName), true);
    expect(fallbackMsg.contains('🏋️ *Gym:* *${GymService().settings.gymName}*'), true);
    expect(fallbackMsg.contains('— *Team ${GymService().settings.gymName}*'), true);
  });

  test('AuthService profile caching and updateProfile test', () async {
    final auth = AuthService();
    final initialNotificationCount = auth.profileNotifier.value;

    await auth.updateProfile(
      displayName: 'Alex Mercer',
      photoPath: 'avatar:3',
      phone: '+91 91234 56789',
    );

    expect(auth.displayName, 'Alex Mercer');
    expect(auth.profilePhotoPath, 'avatar:3');
    expect(auth.phoneNumber, '+91 91234 56789');
    expect(auth.profileNotifier.value > initialNotificationCount, true);
  });

  testWidgets('UserAvatar widget renders fallback and custom values test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserAvatar(
              imagePath: '',
              name: 'Bruce Wayne',
              radius: 30,
              showEditBadge: true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('BW'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
  });

  testWidgets('EditProfileScreen renders and updates gym title test', (tester) async {
    final auth = AuthService();
    await auth.updateProfile(
      displayName: 'Sarah Connor',
      photoPath: 'avatar:2',
      phone: '+91 98888 77777',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: EditProfileScreen(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Owner Information'), findsOneWidget);
    expect(find.text('Gym Title'), findsOneWidget);
    expect(find.text('Plan Tiers & Duration Packages'), findsOneWidget);
    expect(find.text('DURATION COMBOS'), findsOneWidget);
    expect(find.text('Normal Plan'), findsWidgets);
    expect(find.text('Security & Password'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);

    // Verify fields pre-populated
    expect(find.text('Sarah Connor'), findsOneWidget);
    expect(find.text('+91 98888 77777'), findsOneWidget);

    // Enter a new gym brand name
    final gymFinder = find.widgetWithText(TextFormField, GymService().settings.gymName);
    expect(gymFinder, findsOneWidget);
    await tester.enterText(gymFinder, 'Titan Peak Fitness');

    // Tap Save button in AppBar
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(GymService().settings.gymName, 'Titan Peak Fitness');
  });

  testWidgets('AuthScreen sign up photo selection widget test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Create Account (Sign Up) tab
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    // Verify photo selector is rendered
    expect(find.byType(GymLogoSelector), findsOneWidget);
    expect(find.text('Upload Gym Logo (Optional)'), findsOneWidget);
  });

  test('GymService membership plan pricing and payment generation test', () async {
    final gym = GymService();

    // Set custom prices for each plan
    await gym.updateSettings(gym.settings.copyWith(
      normalPlanFee: 1400.0,
      ptPlanFee: 2800.0,
      ptDietPlanFee: 3900.0,
    ));

    expect(gym.settings.getFeeForPlan(CustomerPlan.normal), 1400.0);
    expect(gym.settings.getFeeForPlan(CustomerPlan.personalTraining), 2800.0);
    expect(gym.settings.getFeeForPlan(CustomerPlan.personalTrainingDiet), 3900.0);

    // Add customer with Personal Training
    await gym.addCustomer(
      name: 'John PT Client',
      phone: '+91 91111 22222',
      planType: CustomerPlan.personalTraining,
    );

    final ptCustomer = gym.customers.firstWhere((c) => c.name == 'John PT Client');
    expect(ptCustomer.planType, CustomerPlan.personalTraining);

    // Verify payment amount matches PT plan fee
    const testMonth = '2026-11';
    final payment = gym.getPaymentRecord(ptCustomer.id, testMonth);
    expect(payment.amount, 2800.0);

    // Add customer with Personal Training + Diet
    await gym.addCustomer(
      name: 'Emma Diet Client',
      phone: '+91 93333 44444',
      planType: CustomerPlan.personalTrainingDiet,
    );

    final dietCustomer = gym.customers.firstWhere((c) => c.name == 'Emma Diet Client');
    expect(dietCustomer.planType, CustomerPlan.personalTrainingDiet);
    final dietPayment = gym.getPaymentRecord(dietCustomer.id, testMonth);
    expect(dietPayment.amount, 3900.0);
  });

  testWidgets('AddCustomerSheet shows all 3 plan options and saves selected plan', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gym = GymService();
    final initialCount = gym.customers.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AddCustomerSheet.show(context),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Verify all 3 plan options are visible
    expect(find.text('Normal Plan'), findsOneWidget);
    expect(find.text('Plan with Personal Training'), findsOneWidget);
    expect(find.text('Plan with Personal Training + Diet'), findsOneWidget);

    // Select Plan with Personal Training + Diet
    await tester.ensureVisible(find.text('Plan with Personal Training + Diet'));
    await tester.tap(find.text('Plan with Personal Training + Diet'));
    await tester.pumpAndSettle();

    // Enter name & phone
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'), 'Plan Test User');
    await tester.enterText(find.widgetWithText(TextFormField, 'e.g. +91 98765 43210'), '+91 95555 66666');

    // Register Member
    await tester.ensureVisible(find.text('Register Member'));
    await tester.tap(find.text('Register Member'));
    await tester.pumpAndSettle();

    expect(gym.customers.length, initialCount + 1);
    final newMember = gym.customers.firstWhere((c) => c.name == 'Plan Test User');
    expect(newMember.planType, CustomerPlan.personalTrainingDiet);
  });

  test('PlanDurationPackage model calculations and serialization test', () {
    const pkg = PlanDurationPackage(
      id: 'pkg_norm_3m',
      planType: CustomerPlan.normal,
      months: 3,
      price: 1500.0,
    );

    expect(pkg.title, '3 Months (Quarterly)');
    expect(pkg.shortTitle, '3M');
    expect(pkg.monthlyRate, 500.0);

    final map = pkg.toMap();
    final restored = PlanDurationPackage.fromMap(map);
    expect(restored.id, pkg.id);
    expect(restored.months, 3);
    expect(restored.price, 1500.0);
  });

  test('GymSettings duration pricing matrix and custom packages test', () async {
    final gym = GymService();
    await gym.updateSettings(const GymSettings());

    // Default 3-month normal plan should be 1500
    expect(gym.settings.getPriceForDuration(CustomerPlan.normal, 3), 1500.0);
    // Default 1-month normal plan should be 600
    expect(gym.settings.getPriceForDuration(CustomerPlan.normal, 1), 600.0);

    // Add a custom combo: 2 Months Normal Plan for 1100
    final customPackages = [
      ...gym.settings.durationPackages,
      const PlanDurationPackage(
        id: 'pkg_norm_2m',
        planType: CustomerPlan.normal,
        months: 2,
        price: 1100.0,
      ),
    ];

    await gym.updateSettings(gym.settings.copyWith(durationPackages: customPackages));

    expect(gym.settings.getPriceForDuration(CustomerPlan.normal, 2), 1100.0);
    final pkg2 = gym.settings.getPackage(CustomerPlan.normal, 2);
    expect(pkg2 != null, true);
    expect(pkg2!.monthlyRate, 550.0);
  });

  test('GymService multi-month package payment covers future months correctly test', () async {
    final gym = GymService();

    // Add customer enrolled in 3-Month package
    await gym.addCustomer(
      name: 'Package Test Member',
      phone: '+91 97777 88888',
      planType: CustomerPlan.normal,
      planDurationMonths: 3,
    );

    final member = gym.customers.firstWhere((c) => c.name == 'Package Test Member');
    expect(member.planDurationMonths, 3);

    // Initial pending bill for current month should be 3-month package price (1500)
    final pRecord = gym.getPaymentRecord(member.id, '2026-09');
    expect(pRecord.amount, 1500.0);

    // Pay 3-Month package starting September 2026
    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: '2026-09',
      method: PaymentMethod.gpay,
      amount: 1500.0,
      durationMonths: 3,
      transactionRef: 'UPI-PKG-1500',
    );

    // Verify Bill
    expect(bill.amount, 1500.0);
    expect(bill.durationMonths, 3);
    expect(bill.coveragePeriod, isNotNull);
    expect(bill.coveragePeriod!.contains('2026'), true);

    // September payment record should be paid
    final sepPayment = gym.getPaymentRecord(member.id, '2026-09');
    expect(sepPayment.isPaid, true);
    expect(sepPayment.amount, 1500.0);
    expect(sepPayment.durationMonths, 3);

    // October payment record should be automatically covered (Paid, 0.0 amount, coveredBy 2026-09)
    final octPayment = gym.getPaymentRecord(member.id, '2026-10');
    expect(octPayment.isPaid, true);
    expect(octPayment.amount, 0.0);
    expect(octPayment.isCoveredInPackage, true);
    expect(octPayment.coveredByMonthYear, '2026-09');

    // November payment record should be automatically covered
    final novPayment = gym.getPaymentRecord(member.id, '2026-11');
    expect(novPayment.isPaid, true);
    expect(novPayment.amount, 0.0);
    expect(novPayment.isCoveredInPackage, true);
    expect(novPayment.coveredByMonthYear, '2026-09');

    // December payment record is beyond the package and should be a fresh Pending record
    final decPayment = gym.getPaymentRecord(member.id, '2026-12');
    expect(decPayment.isPaid, false);
    expect(decPayment.status, PaymentStatus.pending);
    expect(decPayment.amount, 1500.0); // Next cycle package amount
  });

  test('PhoneService phone number cleaning and validation test', () {
    final phoneService = PhoneService();
    expect(phoneService.cleanPhoneNumber('9876543210'), '9876543210');
    expect(phoneService.cleanPhoneNumber('+91 98765 43210'), '+919876543210');
    expect(phoneService.cleanPhoneNumber('(555) 123-4567'), '5551234567');
    expect(phoneService.cleanPhoneNumber('+1 (800) 555-0199'), '+18005550199');
    expect(phoneService.cleanPhoneNumber('  '), '');
    expect(phoneService.cleanPhoneNumber(''), '');
  });

  testWidgets('Call button is rendered in CustomerDetailScreen and CustomersTab', (WidgetTester tester) async {
    final gym = GymService();
    final customer = gym.customers.first;

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerDetailScreen(customerId: customer.id),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Call button tooltip in appbar actions
    expect(find.byTooltip('Call Member'), findsWidgets);
    // Verify Call pill button in profile card
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('AuthScreen sign up includes Gym Name field test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Create Account (Sign Up) tab
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    // Verify Gym Name input field is rendered
    expect(find.text('Gym / Fitness Center Name'), findsOneWidget);
    expect(find.text('e.g. IronPulse Fitness Club'), findsOneWidget);
  });

  testWidgets('SplashScreen branding elements test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(),
      ),
    );
    // Pump first frame
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('IRONPULSE'), findsOneWidget);
    expect(find.text('GYM MANAGEMENT & BILLING SUITE'), findsOneWidget);
    expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('IntroScreen multi-slide navigation test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IntroScreen(isReview: true),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Slide 1
    expect(find.text('Smart Member &\nAttendance Tracking'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Tap Next -> Slide 2
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('One-Tap Invoicing &\nWhatsApp Reminders'), findsOneWidget);

    // Tap Next -> Slide 3
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Real-Time Expenses &\nBusiness Insights'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('IntroScreen compact screen overflow-free test', (tester) async {
    // Set a very small compact device size (320 x 568 - iPhone SE / compact Android)
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: IntroScreen(isReview: true),
      ),
    );
    await tester.pumpAndSettle();

    // Verify no overflow exception was thrown
    expect(tester.takeException(), isNull);
    expect(find.text('Next'), findsOneWidget);

    // Verify navigating through all slides on compact screen
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Get Started'), findsOneWidget);
  });
}


