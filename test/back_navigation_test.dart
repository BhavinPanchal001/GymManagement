import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/screens/auth/forgot_password_sheet.dart';
import 'package:gym/screens/billing/balance_sheet_tab.dart';
import 'package:gym/screens/billing/bill_pdf_preview_screen.dart';
import 'package:gym/screens/billing/expense_tab.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/screens/customers/expiring_members_sheet.dart';
import 'package:gym/screens/customers/member_card_screen.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/screens/intro/intro_screen.dart';
import 'package:gym/screens/reports/export_report_dialog.dart';
import 'package:gym/screens/reports/gym_statistics_screen.dart';
import 'package:gym/screens/reports/pending_payments_report_screen.dart';
import 'package:gym/screens/settings/edit_profile_screen.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';
import 'package:gym/widgets/add_expense_dialog.dart';
import 'package:gym/widgets/bill_history_sheet.dart';
import 'package:gym/widgets/bill_receipt_dialog.dart';
import 'package:gym/widgets/collect_balance_dialog.dart';
import 'package:gym/widgets/mark_month_attendance_dialog.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';
import 'package:gym/widgets/whatsapp_reminder_sheet.dart';
import 'package:gym/widgets/whatsapp_welcome_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _destinations = ['Members', 'Attendance', 'Payments', 'Settings'];

Future<void> _openHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, int index) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(_destinations[index]),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectTab(WidgetTester tester, int index) {
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    index,
  );
}

Future<void> _phoneBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  late int appExitCount;

  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/material_fonts').existsSync() &&
        directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = await File(
        '${directory.path}/material_fonts/Roboto-$weight.ttf',
      ).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await gym.detachUser();
    await gym.init();
    await gym.clearAllGymData();
    appExitCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') appExitCount++;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await gym.detachUser();
  });

  testWidgets('phone back unwinds visited tabs before leaving the app', (
    tester,
  ) async {
    await _openHome(tester);
    for (final index in [1, 2, 3]) {
      await _selectTab(tester, index);
    }
    for (final index in [2, 1, 0]) {
      await _phoneBack(tester);
      _expectTab(tester, index);
      expect(appExitCount, 0);
    }
    await _phoneBack(tester);
    expect(appExitCount, 1);
  });

  testWidgets('phone back returns through payment sections before other tabs', (
    tester,
  ) async {
    await _openHome(tester);
    await _selectTab(tester, 1);
    await _selectTab(tester, 2);
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balance Sheet'));
    await tester.pumpAndSettle();

    await _phoneBack(tester);
    _expectTab(tester, 2);
    expect(find.text('Add First Expense'), findsOneWidget);
    await _phoneBack(tester);
    _expectTab(tester, 2);
    expect(find.text('Add First Expense'), findsNothing);
    await _phoneBack(tester);
    _expectTab(tester, 1);
    expect(appExitCount, 0);
  });

  for (var from = 0; from < _destinations.length; from++) {
    for (var to = 0; to < _destinations.length; to++) {
      if (from == to) continue;
      testWidgets(
        'back from ${_destinations[to]} restores ${_destinations[from]}',
        (tester) async {
          await _openHome(tester);
          await _selectTab(tester, from);
          await _selectTab(tester, to);
          await _phoneBack(tester);
          _expectTab(tester, from);
          expect(appExitCount, 0);
        },
      );
    }
  }

  testWidgets('selecting the same tab or section adds no extra back steps', (
    tester,
  ) async {
    await _openHome(tester);
    await _selectTab(tester, 0);
    await _selectTab(tester, 2);
    await _selectTab(tester, 2);
    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    await _phoneBack(tester);
    _expectTab(tester, 0);
    await _phoneBack(tester);
    expect(appExitCount, 1);
  });

  testWidgets('new navigation after back follows the new visit order', (
    tester,
  ) async {
    await _openHome(tester);
    await _selectTab(tester, 1);
    await _selectTab(tester, 2);
    await _phoneBack(tester);
    await _selectTab(tester, 3);
    await _phoneBack(tester);
    _expectTab(tester, 1);
    await _phoneBack(tester);
    _expectTab(tester, 0);
    expect(appExitCount, 0);
  });

  testWidgets('returning to a tab retains its search and payment section', (
    tester,
  ) async {
    await _openHome(tester);
    await tester.enterText(find.byType(TextField), 'Saved search');
    await _selectTab(tester, 2);
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    await _selectTab(tester, 3);
    await _phoneBack(tester);
    expect(find.byType(ExpenseTab), findsOneWidget);
    await _phoneBack(tester);
    await _phoneBack(tester);
    _expectTab(tester, 0);
    expect(find.text('Saved search'), findsOneWidget);
    expect(appExitCount, 0);
  });

  testWidgets('Manage Expenses shortcut returns to the balance sheet on back', (
    tester,
  ) async {
    await _openHome(tester);
    await _selectTab(tester, 2);
    await tester.tap(find.text('Balance Sheet'));
    await tester.pumpAndSettle();
    final manage = find.text('Manage Expenses Ledger');
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseTab), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(BalanceSheetTab), findsOneWidget);
    await _phoneBack(tester);
    _expectTab(tester, 2);
    expect(find.byType(BalanceSheetTab), findsNothing);
    expect(appExitCount, 0);
  });

  for (final page in [
    'member',
    'card',
    'analytics',
    'report',
    'profile',
    'intro',
  ]) {
    testWidgets('phone back from $page restores its originating tab', (
      tester,
    ) async {
      final customer = await gym.addCustomer(
        name: 'Back Test Member',
        phone: '9876543210',
        joinDate: DateTime.now(),
      );
      await _openHome(tester);
      final tab = switch (page) {
        'member' || 'card' => 1,
        'analytics' || 'report' => 2,
        _ => 3,
      };
      await _selectTab(tester, tab);
      final Widget screen = switch (page) {
        'member' => CustomerDetailScreen(customerId: customer.id),
        'card' => MemberCardScreen(customer: customer),
        'analytics' => const GymStatisticsScreen(),
        'report' => const PendingPaymentsReportScreen(),
        'profile' => const EditProfileScreen(),
        _ => const IntroScreen(isReview: true),
      };
      unawaited(
        Navigator.of(
          tester.element(find.byType(HomeScreen)),
        ).push<void>(MaterialPageRoute(builder: (_) => screen)),
      );
      await tester.pumpAndSettle();
      expect(find.byWidget(screen), findsOneWidget);
      await _phoneBack(tester);
      expect(find.byWidget(screen), findsNothing);
      _expectTab(tester, tab);
      expect(appExitCount, 0);
      await _phoneBack(tester);
      _expectTab(tester, 0);
      expect(appExitCount, 0);
    });
  }

  testWidgets('nested analytics report closes before consuming tab history', (
    tester,
  ) async {
    await _openHome(tester);
    await _selectTab(tester, 1);
    await _selectTab(tester, 2);
    await tester.tap(find.byTooltip('Gym Analytics & Statistics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to view report'));
    await tester.pumpAndSettle();
    expect(find.byType(PendingPaymentsReportScreen), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(GymStatisticsScreen), findsOneWidget);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded),
    );
    await tester.pumpAndSettle();
    _expectTab(tester, 2);
    await _phoneBack(tester);
    _expectTab(tester, 1);
    expect(appExitCount, 0);
  });

  testWidgets('member card returns to the profile before the attendance tab', (
    tester,
  ) async {
    final customer = await gym.addCustomer(
      name: 'Back Test Member',
      phone: '9876543210',
      joinDate: DateTime.now(),
    );
    await _openHome(tester);
    await _selectTab(tester, 1);
    unawaited(
      Navigator.of(tester.element(find.byType(HomeScreen))).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              CustomerDetailScreen(customerId: customer.id, initialTabIndex: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View Member Card / Entry Form'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberCardScreen), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(CustomerDetailScreen), findsOneWidget);
    await _phoneBack(tester);
    _expectTab(tester, 1);
    await _phoneBack(tester);
    _expectTab(tester, 0);
    expect(appExitCount, 0);
  });

  testWidgets('PDF preview returns to the receipt before the payment section', (
    tester,
  ) async {
    // Navigation does not need a native PDF rasterizer in this widget test.
    const printingChannel = MethodChannel('net.nfet.printing');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          printingChannel,
          (_) async => <String, bool>{},
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(printingChannel, null),
    );
    final now = DateTime.now();
    final customer = await gym.addCustomer(
      name: 'Back Test Member',
      phone: '9876543210',
      joinDate: now,
    );
    final bill = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: GymDateUtils.toMonthKey(now),
      method: PaymentMethod.cash,
      amount: 100,
      totalDue: 600,
      startDate: now,
    );
    await _openHome(tester);
    await _selectTab(tester, 2);
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    unawaited(
      BillReceiptDialog.show(
        tester.element(find.byType(HomeScreen)),
        bill: bill,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View PDF Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(BillPdfPreviewScreen), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(BillReceiptDialog), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(ExpenseTab), findsOneWidget);
    await _phoneBack(tester);
    _expectTab(tester, 2);
    expect(find.byType(ExpenseTab), findsNothing);
    expect(appExitCount, 0);
  });

  testWidgets('forgot password closes back to sign in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    unawaited(
      ForgotPasswordSheet.show(tester.element(find.byType(AuthScreen))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordSheet), findsOneWidget);
    await _phoneBack(tester);
    expect(find.byType(ForgotPasswordSheet), findsNothing);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(appExitCount, 0);
  });

  for (final overlay in [
    'registration',
    'edit member',
    'payment',
    'renewal',
    'balance',
    'expense',
    'attendance',
    'bill history',
    'receipt',
    'expiry',
    'welcome',
    'reminder',
    'export',
  ]) {
    testWidgets('phone back dismisses $overlay without changing tab history', (
      tester,
    ) async {
      final now = DateTime.now();
      final month = GymDateUtils.toMonthKey(now);
      final customer = await gym.addCustomer(
        name: 'Back Test Member',
        phone: '9876543210',
        joinDate: now,
      );
      final bill = await gym.markPaymentAsPaid(
        customerId: customer.id,
        monthYear: month,
        method: PaymentMethod.cash,
        amount: 100,
        totalDue: 600,
        startDate: now,
      );
      final payment = gym.getPaymentById(bill.paymentId)!;
      await _openHome(tester);
      await _selectTab(tester, 1);
      await _selectTab(tester, 2);
      final context = tester.element(find.byType(HomeScreen));
      final Future<dynamic>? dismissed = switch (overlay) {
        'registration' => AddCustomerSheet.show(context),
        'edit member' => AddCustomerSheet.show(
          context,
          customerToEdit: customer,
        ),
        'payment' => MarkPaymentDialog.show(
          context,
          customer: customer,
          monthYear: month,
          currentRecord: payment,
        ),
        'renewal' => MarkPaymentDialog.showRenewal(context, customer: customer),
        'balance' => CollectBalanceDialog.show(context, payment),
        'expense' => AddExpenseDialog.show(context),
        'attendance' => MarkMonthAttendanceDialog.show(
          context,
          customer: customer,
          month: now,
        ),
        'bill history' => BillHistorySheet.show(context, customer: customer),
        'receipt' => BillReceiptDialog.show(context, bill: bill),
        'welcome' => WhatsAppWelcomeSheet.show(context, customer: customer),
        'reminder' => WhatsAppReminderSheet.show(
          context,
          customer: customer,
          monthYear: month,
          amount: 500,
        ),
        'export' => ExportReportDialog.show(
          context,
          startDate: now,
          endDate: now,
          memberSummaries: gym.getAllPendingDues(),
          totalPending: 500,
        ),
        _ => null,
      };
      if (overlay == 'expiry') {
        ExpiringMembersSheet.show(
          context,
          title: 'Expiring members',
          subtitle: 'Due soon',
          members: [customer],
          accentColor: Colors.orange,
          icon: Icons.alarm,
        );
      }
      await tester.pumpAndSettle();
      expect(ModalRoute.of(context)!.isCurrent, isFalse);
      await _phoneBack(tester);
      await dismissed;
      expect(ModalRoute.of(context)!.isCurrent, isTrue);
      _expectTab(tester, 2);
      await _phoneBack(tester);
      _expectTab(tester, 1);
      expect(appExitCount, 0);
    });
  }
}
