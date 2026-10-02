import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/cloud_sync_queue.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';
import 'package:gym/widgets/collect_balance_dialog.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';
import 'package:gym/screens/home_screen.dart';
import 'package:gym/widgets/bill_receipt_dialog.dart';
import 'package:gym/services/whatsapp_service.dart';

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
  Future<dynamic> member() => gym.addCustomer(
    name: 'Test member',
    phone: '9876543210',
    joinDate: DateTime(2020, 1, 15),
  );

  tearDown(() async => gym.detachUser());

  test(
    'owner uploads recover after interrupted local saves and cannot leak to another owner',
    () async {
      await gym.attachUser('offline-owner');
      final c = await member();
      final receipt = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: DateTime(2020, 1, 15),
      );
      final prefs = await SharedPreferences.getInstance();
      final outbox =
          json.decode(prefs.getString('gym_offline-owner_cloud_outbox_v1')!)
              as List;
      expect(
        outbox.any(
          (b) =>
              (b['changes'] as List).length == 2 &&
              (b['changes'] as List).any(
                (c) => c['collection'] == 'payments',
              ) &&
              (b['changes'] as List).any((c) => c['collection'] == 'bills'),
        ),
        isTrue,
      );
      await gym.detachUser();
      // Simulate a restart between outbox persistence and ordinary local saves.
      await prefs.remove('gym_offline-owner_customers_v1');
      await prefs.remove('gym_offline-owner_payments_v1');
      await prefs.remove('gym_offline-owner_bills_v1');
      await gym.attachUser('offline-owner');
      expect(gym.getCustomerById(c.id), isNotNull);
      expect(gym.getPaymentById(receipt.paymentId)!.amount, 200);
      expect(gym.getBillForPayment(receipt.paymentId)!.amount, 200);
      expect(gym.pendingUploadCount, greaterThan(0));
      await gym.attachUser('different-owner');
      expect(gym.customers, isEmpty);
      expect(gym.billsMap, isEmpty);
      // The only pending upload for a new owner is the subscription
      // trial-stamp settings write — no member data may leak across owners.
      final newOwnerOutbox = json.decode(
            prefs.getString('gym_different-owner_cloud_outbox_v1') ?? '[]',
          ) as List;
      expect(
        newOwnerOutbox
            .expand((b) => b['changes'] as List)
            .map((c) => c['collection']),
        everyElement('settings'),
      );
    },
  );

  testWidgets(
    'phone layout shows unavailable cloud status and a retry action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await gym.attachUser('offline-owner');
      await member();
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('phone.'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await gym.detachUser();
      await tester.pump();
    },
  );

  test('renewal preserves the original payment and receipt', () async {
    final c = await member();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final old = await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: GymDateUtils.toMonthKey(today),
      method: PaymentMethod.cash,
      amount: 600,
      startDate: today.subtract(const Duration(days: 29)),
      endDate: today,
    );
    final next = gym.getRenewalPaymentRecord(c);
    expect(next.isPaid, isFalse);
    expect(next.effectiveStartDate, today.add(const Duration(days: 1)));
    final receipt = await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: next.monthYear,
      method: PaymentMethod.upi,
      amount: 600,
      startDate: next.startDate,
    );
    expect(receipt.paymentId, isNot(old.paymentId));
    expect(gym.getBillForPayment(old.paymentId)!.toMap(), old.toMap());
    expect(gym.getPaidPaymentsForCustomer(c.id), hasLength(2));
  });
  test(
    'balance collection uses its collection month and old debts remain visible',
    () async {
      final c = await member();
      final old = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: DateTime(2020, 1, 15),
        paidAt: DateTime(2020, 1, 15),
      );
      await gym.collectBalance(
        paymentId: old.paymentId,
        amount: 150,
        method: PaymentMethod.upi,
        paidAt: DateTime(2020, 3, 2),
      );
      expect(gym.getPaymentById(old.paymentId)!.balanceDue, 250);
      expect(gym.getMonthlyFinancialSummary('2020-01')['totalCollected'], 200);
      expect(gym.getMonthlyFinancialSummary('2020-03')['totalCollected'], 150);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 250);
    },
  );
  test('invalid amounts and future collection dates make no records', () async {
    final c = await member();
    for (final amount in [0.0, -1.0, double.nan, double.infinity, 601.0]) {
      await expectLater(
        gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: '2020-01',
          method: PaymentMethod.cash,
          amount: amount,
          totalDue: 600,
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 600,
        paidAt: DateTime.now().add(const Duration(days: 2)),
      ),
      throwsArgumentError,
    );
    expect(gym.getPaidPaymentsForCustomer(c.id), isEmpty);
    expect(gym.getAllBillsForCustomer(c.id), isEmpty);
  });
  test(
    'overpayment is rejected and corrections protect existing balance receipts',
    () async {
      final c = await member();
      final b = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
      );
      for (final value in [401.0, 0.0, double.nan]) {
        await expectLater(
          gym.collectBalance(
            paymentId: b.paymentId,
            amount: value,
            method: PaymentMethod.cash,
          ),
          throwsArgumentError,
        );
      }
      await gym.collectBalance(
        paymentId: b.paymentId,
        amount: 300,
        method: PaymentMethod.upi,
      );
      await expectLater(
        gym.updatePayment(paymentId: b.paymentId, amount: 100),
        throwsArgumentError,
      );
      expect(gym.getPaymentById(b.paymentId)!.amount, 500);
      expect(
        gym
            .getBillsForPayment(b.paymentId)
            .fold<double>(0, (sum, b) => sum + b.amount),
        500,
      );
    },
  );
  test(
    'archive preserves history and debt; restore returns the active member',
    () async {
      final c = await member();
      final b = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: DateTime(2020, 1, 15),
      );
      await gym.toggleAttendance(c.id, '2020-01-20', AttendanceStatus.present);
      await gym.deleteCustomer(c.id);
      expect(gym.getCustomerById(c.id)!.isActive, isFalse);
      expect(gym.getAttendance(c.id, '2020-01-20'), isNotNull);
      expect(gym.getBillForPayment(b.paymentId), isNotNull);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 400);
      expect(
        gym.getDailyOverview(GymDateUtils.toDateKey(DateTime.now()))['total'],
        0,
      );
      await gym.restoreCustomer(c.id);
      expect(gym.getCustomerById(c.id)!.isActive, isTrue);
    },
  );
  test('bulk marking is repeatable and skips pre-join dates', () async {
    final c = await member();
    await gym.toggleAttendance(c.id, '2020-01-20', AttendanceStatus.present);
    await gym.markAllPresentForDate('2020-01-20');
    await gym.markAllPresentForDate('2020-01-20');
    expect(
      gym.getAttendanceStatus(c.id, '2020-01-20'),
      AttendanceStatus.present,
    );
    await gym.setMonthAttendance(
      customerId: c.id,
      year: 2020,
      month: 1,
      status: AttendanceStatus.present,
    );
    expect(gym.getAttendance(c.id, '2020-01-14'), isNull);
    expect(gym.getMonthlyAttendanceSummary(c.id, '2020-01')['present'], 17);
    await gym.setMonthAttendanceForMultiple(
      customerIds: [c.id],
      year: 2019,
      month: 12,
      status: AttendanceStatus.present,
    );
    expect(gym.getMonthlyAttendanceSummary(c.id, '2019-12')['present'], 0);
  });
  test('rest days and pre-join members are not counted as absent', () async {
    final c = await member();
    await gym.toggleAttendance(c.id, '2020-01-20', AttendanceStatus.rest);
    expect(gym.getDailyOverview('2020-01-20'), {
      'total': 1,
      'present': 0,
      'absent': 0,
      'rest': 1,
    });
    expect(gym.getDailyOverview('2020-01-14')['total'], 0);
  });
  test(
    'future membership is not active today; its outstanding balance is visible',
    () async {
      final c = await member();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month + 1, 1);
      await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: GymDateUtils.toMonthKey(start),
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: start,
      );
      expect(
        gym.getMemberLifecycleStage(c, GymDateUtils.toMonthKey(now)),
        isNot(MemberLifecycleStage.paid),
      );
      expect(gym.getAllPendingDues().single.totalPendingAmount, 400);
    },
  );
  testWidgets(
    'balance form starts with today and accepts a partial collection',
    (tester) async {
      final c = await member();
      final old = await gym.markPaymentAsPaid(
        customerId: c.id,
        monthYear: '2020-01',
        method: PaymentMethod.cash,
        amount: 200,
        totalDue: 600,
        startDate: DateTime(2020, 1, 15),
        paidAt: DateTime(2020, 1, 15),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CollectBalanceDialog(
              payment: gym.getPaymentById(old.paymentId)!,
            ),
          ),
        ),
      );
      expect(
        find.text('Received on: ${GymDateUtils.formatDate(DateTime.now())}'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      final bill = gym.getBillsForPayment(old.paymentId).last;
      expect(bill.billType, 'BALANCE');
      expect(bill.amount, 100);
      expect(
        GymDateUtils.toDateKey(bill.paidAt),
        GymDateUtils.toDateKey(DateTime.now()),
      );
    },
  );
  testWidgets('renewal form opens a new payment rather than correction', (
    tester,
  ) async {
    final c = await member();
    final p = gym.getRenewalPaymentRecord(c);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkPaymentDialog(
            customer: c,
            monthYear: p.monthYear,
            currentRecord: p,
            isRenewal: true,
          ),
        ),
      ),
    );
    expect(find.text('Renew Membership'), findsOneWidget);
    expect(find.text('Update Payment'), findsNothing);
  });

  testWidgets('invalid payment input stays open without creating a payment', (
    tester,
  ) async {
    final c = await member();
    final p = gym.getRenewalPaymentRecord(c);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkPaymentDialog(
            customer: c,
            monthYear: p.monthYear,
            currentRecord: p,
            isRenewal: true,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'bad');
    final submit = find.byType(ElevatedButton).first;
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(gym.getPaidPaymentsForCustomer(c.id), isEmpty);
    expect(find.byType(MarkPaymentDialog), findsOneWidget);
    expect(find.textContaining('positive amount'), findsOneWidget);
  });

  testWidgets('zero cancelled receipt is never replaced with a paid receipt', (
    tester,
  ) async {
    final c = await member();
    final paid = await gym.markPaymentAsPaid(
      customerId: c.id,
      monthYear: '2020-01',
      method: PaymentMethod.cash,
      amount: 600,
    );
    final cancelled = paid.copyWith(amount: 0, status: 'CANCELLED');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BillReceiptDialog(bill: cancelled)),
      ),
    );
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(
      find.text(
        GymDateUtils.formatCurrency(0, symbol: gym.settings.currencySymbol),
      ),
      findsWidgets,
    );
    final message = WhatsAppService().buildBillReceiptMessage(bill: cancelled);
    expect(message, contains('CANCELLED'));
    expect(message, isNot(contains('*Status:* PAID')));
  });

  group('durable cloud uploads', () {
    CloudSyncQueue? queue;
    tearDown(() => queue?.dispose());
    Future<CloudSyncQueue> create(
      Future<void> Function(List<CloudChange>) upload, {
      String owner = 'owner',
      Duration timeout = const Duration(seconds: 1),
    }) async {
      queue = CloudSyncQueue(
        preferences: await SharedPreferences.getInstance(),
        userId: owner,
        upload: upload,
        retryDelay: const Duration(hours: 1),
        uploadTimeout: timeout,
      );
      queue!.load();
      return queue!;
    }

    test(
      'failed payment and receipt survive restart and retry together',
      () async {
        var offline = true;
        final uploads = <List<CloudChange>>[];
        Future<void> send(List<CloudChange> changes) async {
          if (offline) throw StateError('offline');
          uploads.add(changes);
        }

        var q = await create(send);
        await q.enqueue([
          const CloudChange('payments', 'p', {'amount': 200}),
          const CloudChange('bills', 'b', {'amount': 200}),
        ]);
        await q.flush();
        expect(q.pendingCount, 2);
        expect(q.lastError, isNotNull);
        q.dispose();
        q = await create(send);
        expect(q.pendingCount, 2);
        offline = false;
        await q.flush();
        expect(uploads.single.map((c) => c.collection), ['payments', 'bills']);
        expect(q.pendingCount, 0);
        expect(q.lastError, isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(
          json.decode(prefs.getString('gym_owner_cloud_outbox_v1')!),
          isEmpty,
        );
      },
    );
    test('old snapshots cannot erase pending edits or deletions', () async {
      final q = await create((_) async => throw StateError('offline'));
      await q.enqueue([
        const CloudChange('payments', 'p', {'amount': 200}),
      ]);
      await q.enqueue([
        const CloudChange('payments', 'p', {'amount': 300}),
        const CloudChange('payments', 'removed', null),
      ]);
      await q.flush();
      expect(
        q.overlay('payments', {
          'p': {'amount': 1},
          'removed': {'amount': 600},
        }),
        {
          'p': {'amount': 300},
        },
      );
    });
    test('edits arriving during upload are not lost', () async {
      final gate = Completer<void>();
      final amounts = <int>[];
      final q = await create((changes) async {
        amounts.add(changes.single.data!['amount'] as int);
        if (amounts.length == 1) await gate.future;
      });
      await q.enqueue([
        const CloudChange('payments', 'p', {'amount': 200}),
      ]);
      await q.enqueue([
        const CloudChange('payments', 'p', {'amount': 300}),
      ]);
      gate.complete();
      await q.flush();
      expect(amounts, [200, 300]);
      expect(q.pendingCount, 0);
    });
    test('pending uploads stay with their owner', () async {
      var q = await create((_) async => throw StateError('offline'));
      await q.enqueue([
        const CloudChange('bills', 'b', {'amount': 200}),
      ]);
      await q.flush();
      q.dispose();
      q = await create((_) async {}, owner: 'other-owner');
      expect(q.pendingCount, 0);
      q.dispose();
      q = await create((_) async => throw StateError('offline'));
      expect(q.pendingCount, 1);
    });
    test('stalled uploads time out without losing saved changes', () async {
      final q = await create(
        (_) => Completer<void>().future,
        timeout: const Duration(milliseconds: 30),
      );
      await q.enqueue([
        const CloudChange('bills', 'b', {'amount': 200}),
      ]);
      await q.flush();
      expect(q.pendingCount, 1);
      expect(q.lastError, isNotNull);
    });
  });
}
