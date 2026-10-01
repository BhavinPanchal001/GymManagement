import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/attendance/daily_attendance_tab.dart';
import 'package:gym/screens/billing/billing_tab.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/screens/reports/pending_payments_report_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:gym/widgets/collect_balance_dialog.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  late Customer member;
  late PaymentRecord partial;
  late PaymentRecord unpaid;

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
    final now = DateTime.now();
    member = await gym.addCustomer(
      name: 'Alexander Robertson Patel',
      phone: '9876543210',
      joinDate: DateTime(now.year, now.month, 1),
      planType: CustomerPlan.personalTrainingDiet,
      membershipStartDate: DateTime(now.year, now.month, 1),
      membershipFee: 10500.75,
    );
    final bill = await gym.markPaymentAsPaid(
      customerId: member.id,
      monthYear: GymDateUtils.toMonthKey(now),
      method: PaymentMethod.cash,
      amount: 500.25,
      totalDue: 10500.75,
      startDate: DateTime(now.year, now.month, 1),
      agreementId: gym.getCustomerPaymentHistory(member.id).single.id,
    );
    partial = gym.getPaymentById(bill.paymentId)!;
    unpaid = gym.getRenewalPaymentRecord(member);
  });
  tearDown(() => gym.detachUser());

  for (final size in [const Size(320, 568), const Size(360, 800)]) {
    for (final screen in [
      'billing',
      'member',
      'attendance',
      'report',
      'registration',
      'payment',
      'balance',
    ]) {
      testWidgets('$screen fits $size with 130% Roboto text', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final keyboard = [
          'registration',
          'payment',
          'balance',
        ].contains(screen);
        final content = switch (screen) {
          'billing' => const BillingTab(),
          'member' => CustomerDetailScreen(customerId: member.id),
          'attendance' => const DailyAttendanceTab(),
          'report' => const PendingPaymentsReportScreen(),
          _ => Builder(
            builder: (context) => TextButton(
              onPressed: () {
                switch (screen) {
                  case 'registration':
                    AddCustomerSheet.show(context);
                  case 'payment':
                    MarkPaymentDialog.show(
                      context,
                      customer: member,
                      monthYear: unpaid.monthYear,
                      currentRecord: unpaid,
                    );
                  case 'balance':
                    CollectBalanceDialog.show(context, partial);
                }
              },
              child: const Text('Open'),
            ),
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
                viewInsets: keyboard
                    ? const EdgeInsets.only(bottom: 240)
                    : EdgeInsets.zero,
              ),
              child: child!,
            ),
            home: Scaffold(body: content),
          ),
        );
        if (keyboard) await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen == 'report') {
          await tester.tap(find.text('By Month'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (screen == 'registration' || screen == 'payment') {
          await tester.scrollUntilVisible(
            find.text(
              screen == 'registration'
                  ? 'Register Member'
                  : 'Confirm & Mark as Paid',
            ),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
