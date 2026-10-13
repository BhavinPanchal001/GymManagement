import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/screens/customers/customers_tab.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

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
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 600));
  });
  tearDown(() => gym.detachUser());

  Future<void> openForm(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double keyboard = 0,
    Customer? edit,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AddCustomerSheet.show(context, customerToEdit: edit),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> step(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    for (final mode in ['Partial', 'Full Paid']) {
      testWidgets(
        '$mode registration fits $size with keyboard and larger text',
        (tester) async {
          await openForm(tester, size: size, keyboard: 240);
          expect(tester.takeException(), isNull);
          await step(tester, '2. Duration');
          expect(tester.takeException(), isNull);
          await step(tester, '3. Payment');
          await tester.ensureVisible(find.text(mode));
          await tester.tap(find.text(mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Register Member'));
          expect(find.text('Register Member').hitTestable(), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'switching steps preserves amount, method, duration and member data when saved',
    (tester) async {
      await openForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'),
        'Audit Member',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '9876543210');
      await step(tester, '2. Duration');
      await tester.ensureVisible(find.text('3 Months (Quarterly)'));
      await tester.tap(find.text('3 Months (Quarterly)'));
      await tester.pumpAndSettle();
      await step(tester, '3. Payment');
      await tester.ensureVisible(find.text('Partial'));
      await tester.tap(find.text('Partial'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('50%'));
      await tester.tap(find.textContaining('50%'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Google Pay'));
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();
      await step(tester, '1. Plan');
      await step(tester, '3. Payment');
      final received = find.byType(TextFormField).last;
      final amount = double.parse(
        tester.widget<TextFormField>(received).controller!.text,
      );
      expect(amount, greaterThan(0));
      await step(tester, '1. Plan');
      await tester.tap(find.text('Register Member'));
      await tester.pumpAndSettle();
      final member = gym.customers.single;
      expect(member.name, 'Audit Member');
      expect(member.phone, '9876543210');
      expect(member.planDurationMonths, 3);
      final payment = gym.getCustomerPaymentHistory(member.id).single;
      expect(payment.method, PaymentMethod.gpay);
      expect(payment.amount, amount);
      expect(payment.balanceDue, payment.totalDue - amount);
      expect(gym.getAllBillsForCustomer(member.id).single.amount, amount);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'editing member from a different step retains optional details and paid receipts',
    (tester) async {
      final member = await gym.addCustomer(
        name: 'Existing Member',
        phone: '9876543210',
        joinDate: DateTime(2020, 8, 5),
        markAsPaidNow: true,
        address: 'Original address',
        weight: '75',
        notes: 'Existing notes',
      );
      final paymentBefore = gym
          .getCustomerPaymentHistory(member.id)
          .single
          .toMap();
      final billBefore = gym.getAllBillsForCustomer(member.id).single.toMap();
      await openForm(tester, edit: member);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'),
        'Renamed Member',
      );
      await step(tester, '2. Duration');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      final saved = gym.getCustomerById(member.id)!;
      expect(saved.name, 'Renamed Member');
      expect(saved.address, 'Original address');
      expect(saved.weight, '75');
      expect(saved.notes, 'Existing notes');
      expect(
        gym.getCustomerPaymentHistory(member.id).single.toMap(),
        paymentBefore,
      );
      expect(gym.getAllBillsForCustomer(member.id).single.toMap(), billBefore);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'gap reads and new attendance preserve saved partial payment and receipt',
    () async {
      final member = await gym.addCustomer(
        name: 'Partial member',
        phone: '9876543210',
        joinDate: DateTime(2020, 8, 5),
      );
      final bill = await gym.markPaymentAsPaid(
        customerId: member.id,
        monthYear: '2020-08',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: DateTime(2020, 8, 5),
        endDate: DateTime(2020, 9, 4),
        transactionRef: 'original-ref',
      );
      final paymentBefore = gym.getPaymentById(bill.paymentId)!.toMap();
      final billBefore = gym.getAllBillsForCustomer(member.id).single.toMap();
      await gym.toggleAttendance(
        member.id,
        '2020-09-20',
        AttendanceStatus.present,
        toggle: false,
      );
      gym.getMembershipGaps(member.id);
      gym.getMemberDueBreakdown(member.id);
      expect(gym.getPaymentById(bill.paymentId)!.toMap(), paymentBefore);
      expect(gym.getAllBillsForCustomer(member.id).single.toMap(), billBefore);
      final receipt = await gym.collectBalance(
        paymentId: bill.paymentId,
        amount: 400,
        method: PaymentMethod.gpay,
        paidAt: DateTime.now(),
        transactionRef: 'balance-ref',
      );
      expect(receipt.amount, 400);
      expect(gym.getPaymentById(bill.paymentId)!.balanceDue, 0);
      expect(
        gym.getPaymentById(bill.paymentId)!.effectiveStartDate,
        DateTime(2020, 8, 5),
      );
      expect(
        gym.getPaymentById(bill.paymentId)!.effectiveEndDate,
        DateTime(2020, 9, 4),
      );
      expect(gym.getAllBillsForCustomer(member.id), hasLength(2));
    },
  );

  test(
    'stored inferred agreement keeps its dates and fee after return-date change',
    () async {
      final member = await gym.addCustomer(
        name: 'Existing cycle',
        phone: '9876543210',
        joinDate: DateTime(2020, 8, 5),
      );
      final oldCycle = PaymentRecord(
        id: 'existing-inferred',
        customerId: member.id,
        monthYear: '2020-09',
        amount: 0,
        totalDue: 750,
        durationMonths: 1,
        startDate: DateTime(2020, 9, 5),
        endDate: DateTime(2020, 10, 4),
        isMembershipAgreement: true,
        isInferredAgreement: true,
      );
      final attendance = AttendanceRecord(
        id: 'old-attendance',
        customerId: member.id,
        dateKey: '2020-09-20',
        status: AttendanceStatus.present,
        recordedAt: DateTime(2020, 9, 20),
      );
      await gym.applyCloudSnapshotForTesting(
        paymentMap: {oldCycle.id: oldCycle},
        attendanceMap: {'${member.id}_2020-09-20': attendance},
      );
      await gym.toggleAttendance(
        member.id,
        '2020-09-21',
        AttendanceStatus.present,
        toggle: false,
      );
      expect(gym.getPaymentById(oldCycle.id)!.toMap(), oldCycle.toMap());
      expect(gym.getPaymentRecord(member.id, '2020-09').id, oldCycle.id);
    },
  );
  testWidgets(
    'navigation and member search survive tab changes and service rebuilds',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await gym.addCustomer(
        name: 'Audit navigation member',
        phone: '9876543210',
      );
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      // Empty-state animations elsewhere in the app repeat; do not wait for them
      // to stop before checking that navigation actually works.
      await tester.pump(const Duration(seconds: 1));
      final search = find.descendant(
        of: find.byType(CustomersTab),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Audit');
      await tester.pump(const Duration(milliseconds: 500));
      for (final index in [1, 2, 3]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(
              ['Members', 'Attendance', 'Payments', 'Settings'][index],
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
      }
      await gym.updateSettings(
        gym.settings.copyWith(gymName: 'Updated gym name'),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      for (final index in [2, 1, 0]) {
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
      }
      expect(tester.widget<TextField>(search).controller!.text, 'Audit');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'form retains focused input across keyboard and orientation changes',
    (tester) async {
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final keyboard = ValueNotifier<double>(0);
      addTearDown(keyboard.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => ValueListenableBuilder<double>(
            valueListenable: keyboard,
            builder: (context, inset, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AddCustomerSheet.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextFormField, 'e.g. Rahul Sharma');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Keyboard member');
      final input = tester.widget<EditableText>(
        find.descendant(of: name, matching: find.byType(EditableText)),
      );
      keyboard.value = 240;
      await tester.pumpAndSettle();
      expect(input.focusNode.hasFocus, isTrue);
      expect(input.controller.text, 'Keyboard member');
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(input.focusNode.hasFocus, isTrue);
      expect(input.controller.text, 'Keyboard member');
      expect(find.text('Register Member').hitTestable(), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
