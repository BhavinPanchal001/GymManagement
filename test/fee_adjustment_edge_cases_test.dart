import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/fee_adjustment_sheet.dart';

class _FailFinancialSave extends InMemorySharedPreferencesStore {
  _FailFinancialSave(super.data) : super.withData();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('gym_financial_v1')) return false;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  var sequence = 0;
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 600));
  });
  tearDown(() async => gym.detachUser());

  Future<PaymentRecord> member({
    double fee = 600,
    double paid = 0,
    DateTime? start,
    DateTime? end,
    int months = 1,
  }) async {
    final c = await gym.addCustomer(
      name: 'QA Edge ${sequence++}',
      phone: '9876543210',
      joinDate: start ?? DateTime(2025, 1, 1),
      membershipStartDate: start ?? DateTime(2025, 1, 1),
      membershipEndDate: end ?? DateTime(2025, 1, 31),
      membershipFee: fee,
      planDurationMonths: months,
      markAsPaidNow: paid > 0,
      paidAmount: paid > 0 ? paid : null,
    );
    return gym.getCustomerPaymentHistory(c.id).single;
  }

  Future<void> adjust(
    PaymentRecord p,
    double fee, {
    String? id,
    String reason = 'Approved change',
  }) => gym.adjustMembershipFee(
    expected: p,
    revisedFee: fee,
    reason: reason,
    operationId: id ?? 'edge-${sequence++}',
  );
  PaymentRecord current(PaymentRecord p) => gym.getPaymentById(p.id)!;
  double cash(String id) => gym
      .getAllBillsForCustomer(id)
      .where((b) => b.isPaid)
      .fold<double>(0, (s, b) => s + b.amount);
  Future<void> credit(
    PaymentRecord source,
    PaymentRecord target,
    double amount, {
    String? id,
  }) => gym.applyMemberCredit(
    expectedSource: source,
    expectedTarget: target,
    amount: amount,
    operationId: id ?? 'edge-${sequence++}',
  );
  Future<void> refund(
    PaymentRecord source,
    double amount, {
    String? id,
    String reason = 'Cash returned',
  }) => gym.refundMemberCredit(
    expected: source,
    amount: amount,
    method: PaymentMethod.cash,
    reason: reason,
    operationId: id ?? 'edge-${sequence++}',
  );

  for (final paid in [0.0, 200.0, 600.0]) {
    for (final fee in [0.0, 100.0, 200.0, 300.0, 900.0]) {
      test(
        'received $paid and revised fee $fee reconcile due, credit and cash',
        () async {
          final p = await member(paid: paid);
          await adjust(p, fee);
          final changed = current(p);
          expect(changed.balanceDue, (fee - paid).clamp(0, double.infinity));
          expect(
            changed.availableCredit,
            (paid - fee).clamp(0, double.infinity),
          );
          expect(cash(p.customerId), paid);
          expect(changed.originalFee, 600);
          expect(changed.effectiveStartDate, p.effectiveStartDate);
          expect(changed.effectiveEndDate, p.effectiveEndDate);
        },
      );
    }
  }

  test('repeated changes keep original fee and ordered reasons', () async {
    final p = await member(paid: 400);
    await adjust(p, 300, reason: 'First approval');
    await adjust(current(p), 350, reason: 'Corrected approval');
    await adjust(current(p), 600, reason: 'Discount withdrawn');
    expect(current(p).originalFee, 600);
    expect(current(p).balanceDue, 200);
    expect(current(p).availableCredit, 0);
    expect(current(p).feeChanges.map((c) => c.reason), [
      'First approval',
      'Corrected approval',
      'Discount withdrawn',
    ]);
    expect(cash(p.customerId), 400);
  });

  test('unchanged fee is rejected without writing history', () async {
    final p = await member();
    await expectLater(adjust(p, 600), throwsArgumentError);
    expect(current(p).feeChanges, isEmpty);
  });

  for (final amount in [
    0.0,
    -1.0,
    100.001,
    101.0,
    double.nan,
    double.infinity,
  ]) {
    test(
      'invalid transfer amount $amount leaves both periods untouched',
      () async {
        final p = await member(paid: 400);
        await adjust(p, 300);
        final source = current(p),
            target = gym.creditRenewalPeriod(p.customerId);
        await expectLater(credit(source, target, amount), throwsArgumentError);
        expect(current(p).availableCredit, 100);
        expect(gym.getPaymentById(target.id), isNull);
      },
    );
    test(
      'invalid return amount $amount leaves cash and credit untouched',
      () async {
        final p = await member(paid: 400);
        await adjust(p, 300);
        await expectLater(refund(current(p), amount), throwsArgumentError);
        expect(current(p).availableCredit, 100);
        expect(cash(p.customerId), 400);
      },
    );
  }

  test('refund requires a reason', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    await expectLater(
      refund(current(p), 100, reason: ' '),
      throwsArgumentError,
    );
    expect(current(p).availableCredit, 100);
    expect(cash(p.customerId), 400);
  });

  test('part of credit can be returned and the rest applied', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    await refund(current(p), 40);
    await credit(current(p), gym.creditRenewalPeriod(p.customerId), 60);
    expect(current(p).creditRefunded, 40);
    expect(current(p).creditUsed, 60);
    expect(current(p).availableCredit, 0);
    expect(cash(p.customerId), 360);
  });

  test('credit may be applied in two pieces to the same period', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    final target = gym.creditRenewalPeriod(p.customerId);
    await credit(current(p), target, 40);
    await credit(current(p), current(target), 60);
    expect(current(target).balanceDue, 500);
    expect(current(target).creditApplied, 100);
    expect(current(p).availableCredit, 0);
    expect(cash(p.customerId), 400);
  });

  test('decimal credit can be fully consumed without rounding loss', () async {
    final p = await member(fee: 600, paid: 300.30);
    await adjust(p, 300);
    final target = gym.creditRenewalPeriod(p.customerId);
    await credit(current(p), target, 0.10);
    await credit(current(p), current(target), 0.20);
    expect(current(p).availableCredit, 0);
    expect(current(target).creditApplied, closeTo(0.30, 0.000001));
    expect(current(target).balanceDue, 599.70);
  });

  test('decimal refund can exhaust the exact remaining credit', () async {
    final p = await member(paid: 300.30);
    await adjust(p, 300);
    await refund(current(p), 0.10);
    await refund(current(p), 0.20);
    expect(current(p).availableCredit, 0);
    expect(cash(p.customerId), closeTo(300, 0.000001));
  });

  test(
    'two simultaneous attempts cannot spend the same credit twice locally',
    () async {
      final p = await member(paid: 400);
      await adjust(p, 300);
      final source = current(p), target = gym.creditRenewalPeriod(p.customerId);
      final results = await Future.wait([
        credit(source, target, 100).then((_) => true, onError: (_) => false),
        refund(source, 100).then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((v) => v), hasLength(1));
      expect(current(p).availableCredit, 0);
      expect(current(p).creditUsed + current(p).creditRefunded, 100);
    },
  );

  test(
    'a changed target is rejected without consuming source credit',
    () async {
      final p = await member(paid: 400);
      await adjust(p, 300);
      final proposed = gym.creditRenewalPeriod(p.customerId);
      await credit(current(p), proposed, 1);
      final oldTarget = current(proposed);
      await gym.collectBalance(
        paymentId: oldTarget.id,
        amount: 100,
        method: PaymentMethod.cash,
      );
      await expectLater(credit(current(p), oldTarget, 50), throwsStateError);
      expect(current(p).availableCredit, 99);
    },
  );

  test('cannot apply credit to the source period', () async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    await expectLater(credit(current(p), current(p), 100), throwsArgumentError);
  });

  test(
    'archived member can receive a discount or refund but not a new period',
    () async {
      final p = await member(paid: 400);
      await gym.archiveCustomer(p.customerId);
      await adjust(p, 300);
      await expectLater(
        credit(current(p), gym.creditRenewalPeriod(p.customerId), 100),
        throwsArgumentError,
      );
      await refund(current(p), 100);
      expect(cash(p.customerId), 300);
      expect(gym.getCustomerById(p.customerId)!.isActive, false);
    },
  );

  for (final start in [
    DateTime(2024, 2, 1),
    DateTime(2025, 12, 1),
    DateTime(2025, 1, 31),
  ]) {
    test(
      'fee change preserves dates around ${start.toIso8601String()}',
      () async {
        final p = await member(
          start: start,
          end: DateTime(start.year, start.month + 1, start.day - 1),
        );
        await adjust(p, 300);
        expect(current(p).effectiveStartDate, p.effectiveStartDate);
        expect(current(p).effectiveEndDate, p.effectiveEndDate);
        expect(current(p).monthYear, p.monthYear);
      },
    );
  }

  test(
    'multi-month package adjustment does not change duration or future price',
    () async {
      final p = await member(fee: 1500, months: 3, end: DateTime(2025, 3, 31));
      await adjust(p, 1000);
      expect(current(p).durationMonths, 3);
      expect(current(p).effectiveEndDate, DateTime(2025, 3, 31));
      expect(gym.getCustomerById(p.customerId)!.planDurationMonths, 3);
      expect(gym.settings.standardMonthlyFee, 600);
    },
  );

  test('receipt balances retain their meaning after a later refund', () async {
    final p = await member(paid: 400);
    final bill = gym.getAllBillsForCustomer(p.customerId).single;
    // The change is later than the receipt, including on millisecond clocks.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await adjust(p, 300);
    await refund(current(p), 100);
    expect(gym.feeAtReceipt(current(p), bill), 600);
    expect(gym.balanceAtReceipt(current(p), bill), 200);
  });

  test('history and credits survive owner-scoped reload', () async {
    await gym.attachUser('qa-fee-owner');
    final p = await member(paid: 400);
    await adjust(p, 300);
    final target = gym.creditRenewalPeriod(p.customerId);
    await credit(current(p), target, 40);
    await refund(current(p), 60);
    await gym.detachUser();
    await gym.attachUser('qa-fee-owner');
    expect(current(p).originalFee, 600);
    expect(current(p).feeChanges, hasLength(3));
    expect(current(p).availableCredit, 0);
    expect(current(target).creditApplied, 40);
    expect(cash(p.customerId), 340);
  });

  for (final width in [320.0, 393.0]) {
    testWidgets('credit controls and long history fit a $width pixel phone', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = await member(paid: 400);
      await adjust(p, 300, reason: 'Approved break ' * 20);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeeAdjustmentSheet(payment: current(p))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Record money returned'), findsNothing);
      await tester.ensureVisible(find.text('Apply credit'));
      await tester.tap(find.text('Apply credit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Apply credit to selected period'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelling confirmation saves no fee change', (tester) async {
    final p = await member();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeeAdjustmentSheet(payment: p)),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Revised fee'),
      '300',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for adjustment'),
      'Approved break',
    );
    await tester.ensureVisible(find.text('Review fee adjustment'));
    await tester.tap(find.text('Review fee adjustment'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(current(p).totalDue, 600);
    expect(current(p).feeChanges, isEmpty);
  });

  test('legacy payment without new fields stays readable', () async {
    final p = PaymentRecord.fromMap({
      'id': 'old',
      'customerId': 'member',
      'monthYear': '2025-01',
      'amount': 400,
    });
    expect(p.originalFee, isNull);
    expect(p.creditApplied, 0);
    expect(p.feeChanges, isEmpty);
    expect(PaymentRecord.fromJson(jsonEncode(p.toMap())).amount, 400);
  });

  for (final action in ['adjust', 'credit', 'refund', 'remove']) {
    test(
      'failed $action save leaves both memory and stored money unchanged',
      () async {
        final p = await member(paid: 400);
        if (action != 'adjust') await adjust(p, 300);
        final source = current(p), before = source.toJson();
        final target = gym.creditRenewalPeriod(p.customerId);
        final store = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = _FailFinancialSave(
          await store.getAll(),
        );
        try {
          final attempt = action == 'adjust'
              ? adjust(source, 300)
              : action == 'credit'
              ? credit(source, target, 100)
              : action == 'refund'
              ? refund(source, 100)
              : gym.removeMembershipFeeAdjustment(
                  expected: source,
                  adjustmentId: source.latestFeeAdjustment!.id,
                  operationId: 'failed-remove',
                );
          await expectLater(attempt, throwsStateError);
          expect(current(p).toJson(), before);
          expect(cash(p.customerId), 400);
          expect(gym.getPaymentById(target.id), isNull);
        } finally {
          SharedPreferencesStorePlatform.instance = store;
        }
      },
    );
  }

  test('waived fee can be reinstated without creating a receipt', () async {
    final p = await member();
    await adjust(p, 0);
    await adjust(current(p), 600);
    expect(current(p).balanceDue, 600);
    expect(current(p).isPaid, false);
    expect(current(p).originalFee, 600);
    expect(cash(p.customerId), 0);
  });

  for (final inclusive in [true, false]) {
    test(
      'tax snapshot is preserved while adjusted fee tax is recalculated (inclusive=$inclusive)',
      () async {
        await gym.updateSettings(
          GymSettings(
            standardMonthlyFee: 600,
            isTaxEnabled: true,
            taxRatePercent: 10,
            isTaxInclusive: inclusive,
          ),
        );
        final p = await member(fee: 1100, paid: 600);
        final bill = gym.getAllBillsForCustomer(p.customerId).single.toJson();
        await adjust(p, 550);
        expect(current(p).taxAmount, closeTo(50, 0.000001));
        expect(current(p).taxableAmount, closeTo(500, 0.000001));
        expect(gym.getAllBillsForCustomer(p.customerId).single.toJson(), bill);
        expect(current(p).availableCredit, 50);
      },
    );
  }

  test(
    'credit can fully pay a smaller future fee without creating cash',
    () async {
      final p = await member(paid: 600);
      await adjust(p, 0);
      final target = gym.creditRenewalPeriod(p.customerId);
      await credit(current(p), target, 600);
      expect(current(target).balanceDue, 0);
      expect(current(target).amount, 0);
      expect(current(p).availableCredit, 0);
      expect(gym.getAllPendingDues(), isEmpty);
      expect(cash(p.customerId), 600);
    },
  );

  test(
    'owner-scoped queue keeps both halves of a credit move together',
    () async {
      await gym.attachUser('qa-credit-batch');
      final p = await member(paid: 400);
      await adjust(p, 300);
      final target = gym.creditRenewalPeriod(p.customerId);
      await credit(current(p), target, 100, id: 'credit-batch');
      final prefs = await SharedPreferences.getInstance();
      final batches =
          jsonDecode(prefs.getString('gym_qa-credit-batch_cloud_outbox_v1')!)
              as List;
      expect(
        batches.any((raw) {
          final changes = (raw as Map)['changes'] as List;
          final records = changes
              .where((c) => c['collection'] == 'payments')
              .map((c) => c['data'] as Map)
              .toList();
          return records.any(
                (r) => r['id'] == p.id && r['creditUsed'] == 100,
              ) &&
              records.any(
                (r) => r['id'] == target.id && r['creditApplied'] == 100,
              );
        }),
        true,
      );
    },
  );

  testWidgets(
    'credit application saves successfully and removes exhausted controls',
    (tester) async {
      final p = await member(paid: 400);
      await adjust(p, 300);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeeAdjustmentSheet(payment: current(p))),
        ),
      );
      await tester.ensureVisible(find.text('Apply credit'));
      await tester.tap(find.text('Apply credit'));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.pump();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      final targetLabel = find.textContaining('(₹600 due)').last;
      await tester.tap(targetLabel);
      await tester.pumpAndSettle();
      final apply = find.text('Apply credit to selected period');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(current(p).availableCredit, 0);
      expect(find.text('Apply credit to selected period'), findsNothing);
      expect(find.text('Change saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid refund inputs never crash the review screen', (
    tester,
  ) async {
    final p = await member(paid: 400);
    await adjust(p, 300);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeeAdjustmentSheet(payment: current(p))),
      ),
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.ensureVisible(find.text('Record refund'));
    await tester.tap(find.text('Record refund'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason / return reference'),
      'QA return',
    );
    for (final value in ['NaN', 'Infinity', '-1', '100.001', '101']) {
      final field = find.widgetWithText(TextField, 'Amount');
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      final button = find.text('Record money returned');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Review change'), findsNothing);
      expect(current(p).availableCredit, 100);
    }
  });
}
