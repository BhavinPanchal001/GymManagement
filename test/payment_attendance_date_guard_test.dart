import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  Future<PaymentRecord> register({
    bool paid = false,
    int firstVisit = 1,
    AttendanceStatus earlyStatus = AttendanceStatus.present,
    DateTime? agreementStart,
    DateTime? agreementEnd,
  }) async {
    final c = await gym.addCustomer(
      name: 'QA Date Guard',
      phone: '2025550142',
      joinDate: DateTime(2025, 10, 1),
      membershipStartDate: agreementStart ?? DateTime(2025, 10, 1),
      membershipEndDate: agreementEnd ?? DateTime(2025, 10, 31),
      membershipFee: 600,
      markAsPaidNow: paid,
      paidAmount: paid ? 600 : null,
    );
    for (var day = firstVisit; day <= 26; day++) {
      await gym.toggleAttendance(
        c.id,
        '2025-10-${day.toString().padLeft(2, '0')}',
        day < 15 ? earlyStatus : AttendanceStatus.present,
        toggle: false,
      );
    }
    return gym.getCustomerPaymentHistory(c.id).single;
  }

  Future<void> pay(
    PaymentRecord p,
    DateTime start,
    DateTime end, {
    bool linked = true,
  }) async {
    await gym.markPaymentAsPaid(
      customerId: p.customerId,
      monthYear: p.monthYear,
      amount: 600,
      totalDue: 600,
      method: PaymentMethod.cash,
      startDate: start,
      endDate: end,
      agreementId: linked ? p.id : null,
      paidAt: DateTime(2025, 10, 26),
    );
  }

  test(
    '26 visits: shifting unpaid Oct 1–31 to Oct 15–Nov 14 is blocked',
    () async {
      final p = await register();
      await expectLater(
        pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'explanation',
            allOf(
              contains('14 recorded visits'),
              contains('payment received date'),
            ),
          ),
        ),
      );
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
      expect(gym.getAllPendingDues().single.totalPendingAmount, 600);
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
      expect(
        gym.getPaymentById(p.id)!.effectiveStartDate,
        DateTime(2025, 10, 1),
      );
    },
  );

  test(
    'same mistake cannot bypass the guard through a separate new payment',
    () async {
      final p = await register();
      await expectLater(
        pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14), linked: false),
        throwsArgumentError,
      );
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
    },
  );

  test(
    'late receipt date settles the original month with no second due',
    () async {
      final p = await register();
      await pay(p, DateTime(2025, 10, 1), DateTime(2025, 10, 31));
      expect(gym.getAllPendingDues(), isEmpty);
      final saved = gym.getPaymentById(p.id)!;
      expect(saved.paidAt, DateTime(2025, 10, 26));
      expect(saved.effectiveStartDate, DateTime(2025, 10, 1));
      expect(gym.getPaidAttendedDaysInMonth(p.customerId, '2025-10'), 26);
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
    },
  );

  test(
    'moving an existing paid period cannot orphan earlier attendance',
    () async {
      final p = await register(paid: true);
      final bill = gym.getAllBillsForCustomer(p.customerId).single.toJson();
      await expectLater(
        gym.updatePayment(
          paymentId: p.id,
          startDate: DateTime(2025, 10, 15),
          endDate: DateTime(2025, 11, 14),
        ),
        throwsArgumentError,
      );
      expect(gym.getAllBillsForCustomer(p.customerId).single.toJson(), bill);
      expect(gym.getAllPendingDues(), isEmpty);
    },
  );

  test('shortening the end date cannot orphan later attendance', () async {
    final p = await register();
    await expectLater(
      pay(p, DateTime(2025, 10, 1), DateTime(2025, 10, 14)),
      throwsArgumentError,
    );
    expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
  });

  test(
    'changed dates remain allowed when every recorded visit is included',
    () async {
      final p = await register(firstVisit: 15);
      await pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14));
      expect(gym.getAllPendingDues(), isEmpty);
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
    },
  );

  for (final status in [AttendanceStatus.absent, AttendanceStatus.rest]) {
    test(
      'earlier ${status.name} days do not block an otherwise valid date correction',
      () async {
        final p = await register(earlyStatus: status);
        await pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14));
        expect(gym.getAllPendingDues(), isEmpty);
      },
    );
  }

  test(
    'separate consecutive renewal may coexist with a genuine older debt',
    () async {
      final p = await register();
      await pay(
        p,
        DateTime(2025, 11, 1),
        DateTime(2025, 11, 30),
        linked: false,
      );
      expect(gym.getAllPendingDues().single.totalPendingAmount, 600);
      expect(gym.getAllBillsForCustomer(p.customerId), hasLength(1));
    },
  );

  test(
    'payment method and received-date corrections keep coverage intact',
    () async {
      final p = await register(paid: true);
      await gym.updatePayment(
        paymentId: p.id,
        method: PaymentMethod.upi,
        paidAt: DateTime(2025, 10, 26),
      );
      expect(gym.getAllPendingDues(), isEmpty);
      expect(
        gym.getPaymentById(p.id)!.effectiveStartDate,
        DateTime(2025, 10, 1),
      );
    },
  );

  test(
    'correcting an older mistaken period removes the artificial second due',
    () async {
      final p = await register(firstVisit: 15);
      await pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14));
      final receipt = gym.getAllBillsForCustomer(p.customerId).single;
      for (var day = 1; day < 15; day++) {
        await gym.toggleAttendance(
          p.customerId,
          '2025-10-${day.toString().padLeft(2, '0')}',
          AttendanceStatus.present,
          toggle: false,
        );
      }
      expect(gym.getAllPendingDues().single.totalPendingAmount, 600);
      await gym.updatePayment(
        paymentId: p.id,
        startDate: DateTime(2025, 10, 1),
        endDate: DateTime(2025, 10, 31),
      );
      expect(gym.getAllPendingDues(), isEmpty);
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
      final correctedReceipt = gym.getAllBillsForCustomer(p.customerId).single;
      expect(correctedReceipt.id, receipt.id);
      expect(correctedReceipt.billNumber, receipt.billNumber);
      expect(correctedReceipt.amount, receipt.amount);
    },
  );

  testWidgets(
    'wrong fresh-start dates show an explanation inside a visible dialog',
    (tester) async {
      final p = await register();
      final c = gym.getCustomerById(p.customerId)!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkPaymentDialog(
              customer: c,
              monthYear: p.monthYear,
              currentRecord: p,
            ),
          ),
        ),
      );
      final freshStart = find.text('Fresh Start');
      await tester.ensureVisible(freshStart);
      await tester.tap(freshStart);
      await tester.pump();
      final save = find.byType(ElevatedButton).last;
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Check payment details'), findsOneWidget);
      expect(find.textContaining('payment received date'), findsWidgets);
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(1));
    },
  );

  test(
    'legacy times of day cannot bypass the separate-payment guard',
    () async {
      final p = await register(
        agreementStart: DateTime(2025, 10, 1, 13),
        agreementEnd: DateTime(2025, 10, 31, 13),
      );
      await expectLater(
        pay(p, DateTime(2025, 10, 1), DateTime(2025, 10, 1), linked: false),
        throwsArgumentError,
      );
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
      expect(gym.getAllPendingDues().single.totalPendingAmount, 600);
    },
  );

  test(
    'another paid period covering omitted visits permits a valid correction',
    () async {
      final p = await register(paid: true);
      final earlier = PaymentRecord(
        id: 'legacy-earlier',
        customerId: p.customerId,
        monthYear: '2025-10',
        amount: 300,
        totalDue: 300,
        status: PaymentStatus.paid,
        paidAt: DateTime(2025, 10, 1),
        startDate: DateTime(2025, 10, 1),
        endDate: DateTime(2025, 10, 14),
      );
      await gym.applyCloudSnapshotForTesting(
        paymentMap: {p.id: p, earlier.id: earlier},
      );
      await gym.updatePayment(
        paymentId: p.id,
        startDate: DateTime(2025, 10, 15),
        endDate: DateTime(2025, 11, 14),
      );
      expect(gym.getAllPendingDues(), isEmpty);
      expect(gym.getUnpaidAttendedDaysInMonth(p.customerId, '2025-10'), 0);
    },
  );

  test('attendance-created agreements get the same date protection', () async {
    final c = await gym.addCustomer(
      name: 'Legacy attendance',
      phone: '2025550143',
      joinDate: DateTime(2025, 10, 1),
    );
    for (var day = 1; day <= 26; day++) {
      await gym.toggleAttendance(
        c.id,
        '2025-10-${day.toString().padLeft(2, '0')}',
        AttendanceStatus.present,
        toggle: false,
      );
    }
    final p = gym.getCustomerPaymentHistory(c.id).single;
    expect(p.isInferredAgreement, true);
    await expectLater(
      pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14)),
      throwsArgumentError,
    );
    await pay(p, DateTime(2025, 10, 1), DateTime(2025, 10, 31));
    expect(gym.getAllPendingDues(), isEmpty);
    expect(gym.getCustomerPaymentHistory(c.id), hasLength(1));
  });

  test(
    'a partial payment and later balance collection retain the original dates',
    () async {
      final p = await register();
      await gym.markPaymentAsPaid(
        customerId: p.customerId,
        monthYear: p.monthYear,
        amount: 200,
        method: PaymentMethod.cash,
        agreementId: p.id,
        paidAt: DateTime(2025, 10, 15),
      );
      expect(gym.getPaymentById(p.id)!.balanceDue, 400);
      await gym.collectBalance(
        paymentId: p.id,
        amount: 400,
        method: PaymentMethod.upi,
        paidAt: DateTime(2025, 10, 26),
      );
      expect(
        gym.getPaymentById(p.id)!.effectiveStartDate,
        DateTime(2025, 10, 1),
      );
      expect(gym.getAllBillsForCustomer(p.customerId), hasLength(2));
      expect(gym.getAllPendingDues(), isEmpty);
    },
  );

  for (final range in [
    (DateTime(2025, 10, 1), DateTime(2025, 10, 26), true),
    (DateTime(2025, 10, 1), DateTime(2025, 10, 25), false),
    (DateTime(2025, 10, 2), DateTime(2025, 10, 31), false),
    (DateTime(2025, 9, 15), DateTime(2025, 10, 14), false),
    (DateTime(2025, 9, 15), DateTime(2025, 10, 31), true),
    (DateTime(2025, 11, 1), DateTime(2025, 11, 30), false),
  ]) {
    test(
      'membership date boundaries ${range.$1} to ${range.$2} preserve all existing visits',
      () async {
        final p = await register();
        if (range.$3) {
          await pay(p, range.$1, range.$2);
          expect(gym.getAllPendingDues(), isEmpty);
        } else {
          await expectLater(pay(p, range.$1, range.$2), throwsArgumentError);
          expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
        }
      },
    );
  }

  test(
    'consecutive paid renewal does not change the first period or its receipt',
    () async {
      final p = await register(paid: true);
      final original = gym.getAllBillsForCustomer(p.customerId).single.toJson();
      await pay(
        p,
        DateTime(2025, 11, 1),
        DateTime(2025, 11, 30),
        linked: false,
      );
      expect(gym.getCustomerPaymentHistory(p.customerId), hasLength(2));
      expect(
        gym
            .getAllBillsForCustomer(p.customerId)
            .any((b) => b.toJson() == original),
        true,
      );
      expect(gym.getAllPendingDues(), isEmpty);
    },
  );

  testWidgets('date warning fits a small phone with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final p = await register();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkPaymentDialog(
            customer: gym.getCustomerById(p.customerId)!,
            monthYear: p.monthYear,
            currentRecord: p,
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Fresh Start'));
    await tester.tap(find.text('Fresh Start'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    final save = find.byType(ElevatedButton).last;
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Check payment details'), findsOneWidget);
    await tester.ensureVisible(find.text('OK'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
    expect(tester.takeException(), isNull);
  });

  test(
    'rejected save can be corrected and retried without duplicating a receipt',
    () async {
      final p = await register();
      Future<dynamic> submit(DateTime start, DateTime end) =>
          gym.markPaymentAsPaid(
            customerId: p.customerId,
            monthYear: p.monthYear,
            amount: 600,
            totalDue: 600,
            method: PaymentMethod.cash,
            agreementId: p.id,
            startDate: start,
            endDate: end,
            operationId: 'same-form-retry',
            paidAt: DateTime(2025, 10, 26),
          );
      await expectLater(
        submit(DateTime(2025, 10, 15), DateTime(2025, 11, 14)),
        throwsArgumentError,
      );
      final saved = await submit(DateTime(2025, 10, 1), DateTime(2025, 10, 31));
      final repeated = await submit(
        DateTime(2025, 10, 1),
        DateTime(2025, 10, 31),
      );
      expect(saved.id, repeated.id);
      expect(gym.getAllBillsForCustomer(p.customerId), hasLength(1));
      expect(gym.getAllPendingDues(), isEmpty);
    },
  );

  test(
    'attendance added after the form preview is rechecked when saving',
    () async {
      final p = await register(firstVisit: 15);
      expect(
        gym.paymentPeriodAttendanceError(
          customerId: p.customerId,
          startDate: DateTime(2025, 10, 15),
          endDate: DateTime(2025, 11, 14),
          existingPeriod: p,
        ),
        isNull,
      );
      await gym.toggleAttendance(
        p.customerId,
        '2025-10-01',
        AttendanceStatus.present,
        toggle: false,
      );
      await expectLater(
        pay(p, DateTime(2025, 10, 15), DateTime(2025, 11, 14)),
        throwsArgumentError,
      );
      expect(gym.getAllBillsForCustomer(p.customerId), isEmpty);
    },
  );

  for (final start in [DateTime(2024, 2, 1), DateTime(2024, 12, 1)]) {
    test(
      'multi-month attendance guard works from $start across calendar boundaries',
      () async {
        final end = DateTime(start.year, start.month + 3, 0);
        final c = await gym.addCustomer(
          name: 'Three month dates',
          phone: '2025550144',
          joinDate: start,
          membershipStartDate: start,
          membershipEndDate: end,
          membershipFee: 1500,
          planDurationMonths: 3,
        );
        await gym.toggleAttendance(
          c.id,
          '${start.year}-${start.month.toString().padLeft(2, '0')}-01',
          AttendanceStatus.present,
        );
        final p = gym.getCustomerPaymentHistory(c.id).single;
        await expectLater(
          gym.markPaymentAsPaid(
            customerId: c.id,
            monthYear: p.monthYear,
            amount: 1500,
            method: PaymentMethod.cash,
            agreementId: p.id,
            startDate: DateTime(start.year, start.month, 15),
            endDate: end,
          ),
          throwsArgumentError,
        );
        await gym.markPaymentAsPaid(
          customerId: c.id,
          monthYear: p.monthYear,
          amount: 1500,
          method: PaymentMethod.cash,
          agreementId: p.id,
          startDate: start,
          endDate: end,
        );
        expect(gym.getAllPendingDues(), isEmpty);
        expect(gym.getPaymentById(p.id)!.durationMonths, 3);
      },
    );
  }
}
