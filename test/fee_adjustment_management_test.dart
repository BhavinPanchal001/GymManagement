import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/billing/billing_tab.dart';
import 'package:gym/screens/customers/customer_detail_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/fee_adjustment_sheet.dart';
import 'package:gym/widgets/fee_adjustment_button.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';
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

  Future<PaymentRecord> member({double paid = 0, DateTime? starts}) async {
    final start = starts ?? DateTime(2025, 9, 1);
    final customer = await gym.addCustomer(
      name: 'Adjustment management',
      phone: '9876543210',
      joinDate: start,
      membershipFee: 600,
      membershipStartDate: start,
      membershipEndDate: DateTime(start.year, start.month + 1, 0),
      markAsPaidNow: paid > 0,
      paidAmount: paid > 0 ? paid : null,
    );
    return gym.getCustomerPaymentHistory(customer.id).single;
  }

  PaymentRecord current(PaymentRecord payment) =>
      gym.getPaymentById(payment.id)!;

  Future<void> adjust(PaymentRecord payment, double fee, String id) =>
      gym.adjustMembershipFee(
        expected: payment,
        revisedFee: fee,
        reason: 'Approved half-month break',
        operationId: id,
      );

  Future<void> remove(PaymentRecord payment, {String id = 'remove'}) =>
      gym.removeMembershipFeeAdjustment(
        expected: payment,
        adjustmentId: payment.latestFeeAdjustment!.id,
        operationId: id,
      );

  Future<void> showSheet(WidgetTester tester, PaymentRecord payment) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeeAdjustmentSheet(payment: payment)),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final paid in [0.0, 200.0, 300.0, 400.0]) {
    test(
      'removing reduction with $paid received preserves receipts and dates',
      () async {
        final payment = await member(paid: paid);
        final receipts = gym
            .getAllBillsForCustomer(payment.customerId)
            .map((bill) => bill.toMap())
            .toList();
        await adjust(payment, 300, 'adjust');
        await remove(current(payment));
        final restored = current(payment);
        expect(restored.totalDue, 600);
        expect(restored.balanceDue, 600 - paid);
        expect(restored.amount, paid);
        expect(restored.originalFee, 600);
        expect(restored.availableCredit, 0);
        expect(restored.effectiveStartDate, payment.effectiveStartDate);
        expect(restored.effectiveEndDate, payment.effectiveEndDate);
        expect(restored.latestFeeAdjustment, isNull);
        expect(restored.feeChanges.first.reason, 'Approved half-month break');
        expect(restored.feeChanges.last.reversesChangeId, 'adjust');
        expect(restored.feeChanges.last.actorId, 'local-owner');
        expect(
          gym
              .getAllBillsForCustomer(payment.customerId)
              .map((bill) => bill.toMap())
              .toList(),
          receipts,
        );
        expect(
          gym
              .getPendingDuesByMember(DateTime(2025, 9), DateTime(2025, 9, 30))
              .single
              .totalPendingAmount,
          600 - paid,
        );
      },
    );
  }

  test(
    'removing a full waiver restores unpaid status without a receipt',
    () async {
      final payment = await member();
      await adjust(payment, 0, 'waiver');
      await remove(current(payment));
      expect(current(payment).totalDue, 600);
      expect(current(payment).isPaid, isFalse);
      expect(gym.getAllBillsForCustomer(payment.customerId), isEmpty);
    },
  );

  test(
    'only latest active adjustment can be removed, then the previous one',
    () async {
      final payment = await member();
      await adjust(payment, 400, 'first');
      await adjust(current(payment), 300, 'second');
      final before = current(payment);
      await expectLater(
        gym.removeMembershipFeeAdjustment(
          expected: before,
          adjustmentId: 'first',
          operationId: 'out-of-order',
        ),
        throwsArgumentError,
      );
      expect(current(payment).toMap(), before.toMap());
      await remove(current(payment));
      expect(current(payment).totalDue, 400);
      expect(current(payment).latestFeeAdjustment!.id, 'first');
      await remove(current(payment), id: 'remove-first');
      expect(current(payment).totalDue, 600);
      expect(current(payment).latestFeeAdjustment, isNull);
      expect(current(payment).feeChanges, hasLength(4));
    },
  );

  test(
    'repeat removal is idempotent and stale forms cannot remove again',
    () async {
      final payment = await member();
      await adjust(payment, 300, 'adjust');
      final expected = current(payment);
      await remove(expected);
      await remove(expected);
      expect(current(payment).feeChanges, hasLength(2));
      await expectLater(remove(expected, id: 'stale'), throwsStateError);
      await expectLater(
        gym.removeMembershipFeeAdjustment(
          expected: current(payment),
          adjustmentId: 'adjust',
          operationId: 'again',
        ),
        throwsArgumentError,
      );
    },
  );

  for (final action in ['apply', 'refund']) {
    test('removal cannot consume credit already $action', () async {
      final payment = await member(paid: 400);
      await adjust(payment, 300, 'adjust');
      if (action == 'apply') {
        await gym.applyMemberCredit(
          expectedSource: current(payment),
          expectedTarget: gym.creditRenewalPeriod(payment.customerId),
          amount: 100,
          operationId: 'credit',
        );
      } else {
        await gym.refundMemberCredit(
          expected: current(payment),
          amount: 100,
          method: PaymentMethod.cash,
          reason: 'Returned cash',
          operationId: 'refund',
        );
      }
      final before = current(payment);
      final receipts = gym
          .getAllBillsForCustomer(payment.customerId)
          .map((bill) => bill.toMap())
          .toList();
      expect(before.adjustmentRemovalBlockedReason, isNotNull);
      await expectLater(remove(before), throwsArgumentError);
      expect(current(payment).toMap(), before.toMap());
      expect(
        gym
            .getAllBillsForCustomer(payment.customerId)
            .map((bill) => bill.toMap())
            .toList(),
        receipts,
      );
    });
  }

  test('removal persists its audit link and recalculates tax', () async {
    final payment = await member();
    final taxable = payment.copyWith(
      isTaxEnabled: true,
      taxRatePercent: 18,
      taxAmount: 600 - 600 / 1.18,
      taxableAmount: 600 / 1.18,
    );
    await gym.applyCloudSnapshotForTesting(paymentMap: {payment.id: taxable});
    await adjust(current(payment), 300, 'adjust');
    await remove(current(payment));
    expect(current(payment).taxAmount, closeTo(600 - 600 / 1.18, 0.001));
    final prefs = await SharedPreferences.getInstance();
    final snapshot = jsonDecode(prefs.getString('gym_financial_v1')!) as Map;
    final saved = PaymentRecord.fromMap(
      Map<String, dynamic>.from((snapshot['payments'] as List).single),
    );
    expect(saved.totalDue, 600);
    expect(saved.latestFeeAdjustment, isNull);
    expect(saved.feeChanges.last.reversesChangeId, 'adjust');
  });

  test(
    'fully settled periods hide adjustment while partial balances stay eligible',
    () async {
      final full = await member(paid: 600);
      expect(full.canAdjustFee, isFalse);
      expect(full.copyWith(amount: 200).canAdjustFee, isTrue);
      expect(
        full.copyWith(amount: 0, creditApplied: 600).canAdjustFee,
        isFalse,
      );
      expect(full.copyWith(amount: 0, totalDue: 0).canAdjustFee, isFalse);
    },
  );

  testWidgets(
    'existing adjustment opens history without asking for a reason again',
    (tester) async {
      final payment = await member();
      await adjust(payment, 300, 'adjust');
      await showSheet(tester, current(payment));
      expect(find.text('Fee adjustment details'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Reason for adjustment'),
        findsNothing,
      );
      expect(find.textContaining('Approved half-month break'), findsOneWidget);
      expect(find.text('Remove adjustment'), findsOneWidget);
      await tester.tap(find.text('Change fee'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Reason for adjustment'),
        findsOneWidget,
      );
    },
  );

  testWidgets('settled adjusted payment only shows details and removal', (
    tester,
  ) async {
    final payment = await member(paid: 300);
    await adjust(payment, 300, 'adjust');
    await showSheet(tester, current(payment));
    expect(find.text('Change fee'), findsNothing);
    expect(find.text('Review fee adjustment'), findsNothing);
    expect(
      find.widgetWithText(TextField, 'Reason for adjustment'),
      findsNothing,
    );
    expect(find.text('Remove adjustment'), findsOneWidget);
  });

  testWidgets('removal can be cancelled and confirmed without another reason', (
    tester,
  ) async {
    final payment = await member(paid: 300);
    await adjust(payment, 300, 'adjust');
    await showSheet(tester, current(payment));
    final button = find.text('Remove adjustment');
    await tester.ensureVisible(button);
    await tester.tap(button);
    // The sheet's busy indicator keeps animating behind the review dialog.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(current(payment).totalDue, 300);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(current(payment).totalDue, 600);
    expect(current(payment).balanceDue, 300);
    expect(find.text('Remove adjustment'), findsNothing);
    expect(find.text('Removed'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Reason for adjustment'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'receipts after removal use restored fee and old receipts retain their fee',
    () async {
      final payment = await member(paid: 300);
      final originalBill = gym
          .getAllBillsForCustomer(payment.customerId)
          .single;
      await adjust(payment, 300, 'adjust');
      await remove(current(payment));
      final collection = await gym.collectBalance(
        paymentId: payment.id,
        amount: 300,
        method: PaymentMethod.cash,
      );
      expect(gym.feeAtReceipt(current(payment), originalBill), 600);
      expect(gym.feeAtReceipt(current(payment), collection), 600);
      expect(gym.balanceAtReceipt(current(payment), collection), 0);
    },
  );

  for (final screen in ['member', 'payments']) {
    testWidgets('$screen month card opens adjustment directly for its period', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(460, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final payment = await member(starts: DateTime(now.year, now.month, 1));
      await tester.pumpWidget(
        MaterialApp(
          home: screen == 'member'
              ? CustomerDetailScreen(customerId: payment.customerId)
              : const BillingTab(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final shortcut = screen == 'member'
          ? find.byKey(const ValueKey('month-fee-adjustment'))
          : find.byType(FeeAdjustmentButton);
      final button = find.descendant(
        of: shortcut,
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FeeAdjustmentSheet), findsOneWidget);
      expect(find.text(payment.formattedDateRange), findsWidgets);
      expect(find.widgetWithText(TextField, 'Revised fee'), findsOneWidget);
      expect(current(payment).totalDue, 600);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('placeholder month has no adjustment shortcut', (tester) async {
    final payment = await member();
    final next = gym.getPaymentRecord(payment.customerId, '2030-10');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeeAdjustmentButton(payment: next)),
      ),
    );
    expect(find.text('Adjust fee'), findsNothing);
  });

  for (final adjusted in [false, true]) {
    testWidgets(
      'paid payment form and history hide Adjust fee (adjusted: $adjusted)',
      (tester) async {
        tester.view.physicalSize = const Size(460, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final payment = await member(paid: adjusted ? 300 : 600);
        if (adjusted) await adjust(payment, 300, 'adjust');
        final saved = current(payment);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MarkPaymentDialog(
                customer: gym.getCustomerById(payment.customerId)!,
                monthYear: payment.monthYear,
                currentRecord: saved,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Adjust fee'), findsNothing);
        expect(
          find.text('View adjustment'),
          adjusted ? findsOneWidget : findsNothing,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CustomerDetailScreen(customerId: payment.customerId),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Adjust fee'), findsNothing);
        expect(
          find.text('View adjustment'),
          adjusted ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
