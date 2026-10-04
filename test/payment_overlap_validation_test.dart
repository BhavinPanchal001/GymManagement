import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  test('findOverlappingPaidPayment correctly detects overlap with existing paid period', () async {
    final customer = await gym.addCustomer(
      name: 'John Doe',
      phone: '9876543210',
      joinDate: DateTime(2026, 10, 1),
      planDurationMonths: 3,
    );

    // Paid payment: 1 Oct 2026 to 31 Dec 2026 (3-month plan)
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-10',
      method: PaymentMethod.cash,
      amount: 1500,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 12, 31),
    );

    // Case 1: Start 1 Nov 2026 to 31 Jan 2027 (user example: clicked Feb/Nov, overlaps Nov-Dec)
    final overlap1 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2027, 1, 31),
    );
    expect(overlap1, isNotNull);
    expect(overlap1!.effectiveStartDate, DateTime(2026, 10, 1));
    expect(overlap1.effectiveEndDate, DateTime(2026, 12, 31));

    // Case 2: Sub-period inside 1 Oct - 31 Dec (e.g. 15 Oct to 15 Nov)
    final overlap2 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2026, 10, 15),
      endDate: DateTime(2026, 11, 15),
    );
    expect(overlap2, isNotNull);

    // Case 3: Overlaps start date (e.g. 15 Sep to 15 Oct)
    final overlap3 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2026, 9, 15),
      endDate: DateTime(2026, 10, 15),
    );
    expect(overlap3, isNotNull);

    // Case 4: Exactly consecutive after expiry: 1 Jan 2027 to 31 Jan 2027 -> NO overlap
    final overlap4 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 1, 31),
    );
    expect(overlap4, isNull);

    // Case 5: Before plan start: 1 Jul 2026 to 30 Sep 2026 -> NO overlap
    final overlap5 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 9, 30),
    );
    expect(overlap5, isNull);

    // Case 6: Same payment excluded by ID
    final paidRecord = gym.getPaidPaymentsForCustomer(customer.id).first;
    final overlap6 = gym.findOverlappingPaidPayment(
      customerId: customer.id,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 12, 31),
      excludePaymentId: paidRecord.id,
    );
    expect(overlap6, isNull);
  });

  test('markPaymentAsPaid throws ArgumentError when dates overlap with an existing paid payment', () async {
    final customer = await gym.addCustomer(
      name: 'Alice',
      phone: '9876543211',
      joinDate: DateTime(2026, 10, 1),
      planDurationMonths: 3,
    );

    // 1st payment: 1 Oct 2026 to 31 Dec 2026
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-10',
      method: PaymentMethod.gpay,
      amount: 1500,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 12, 31),
    );

    // Attempt to add 2nd payment starting 1 Nov 2026 (overlaps!)
    expect(
      () => gym.markPaymentAsPaid(
        customerId: customer.id,
        monthYear: '2026-11',
        method: PaymentMethod.cash,
        amount: 500,
        totalDue: 500,
        durationMonths: 1,
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 30),
      ),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        contains('overlaps with an already paid membership'),
      )),
    );

    // Non-overlapping payment starting 1 Jan 2027 succeeds
    final secondBill = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2027-01',
      method: PaymentMethod.cash,
      amount: 500,
      totalDue: 500,
      durationMonths: 1,
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 1, 31),
    );
    expect(secondBill.status, 'PAID');
    expect(gym.getPaidPaymentsForCustomer(customer.id), hasLength(2));
  });

  test('updatePayment throws ArgumentError when updated dates overlap with another paid payment', () async {
    final customer = await gym.addCustomer(
      name: 'Bob',
      phone: '9876543212',
      joinDate: DateTime(2026, 10, 1),
      planDurationMonths: 1,
    );

    // Payment 1: Oct (1 Oct to 31 Oct)
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-10',
      method: PaymentMethod.cash,
      amount: 500,
      totalDue: 500,
      durationMonths: 1,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 10, 31),
    );

    // Payment 2: Dec (1 Dec to 31 Dec)
    final bill2 = await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-12',
      method: PaymentMethod.cash,
      amount: 500,
      totalDue: 500,
      durationMonths: 1,
      startDate: DateTime(2026, 12, 1),
      endDate: DateTime(2026, 12, 31),
    );

    // Try to update Payment 2 to start on 15 Oct (overlaps Payment 1)
    expect(
      () => gym.updatePayment(
        paymentId: bill2.paymentId,
        startDate: DateTime(2026, 10, 15),
        endDate: DateTime(2026, 11, 14),
      ),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        contains('overlaps with an already paid membership'),
      )),
    );

    // Updating Payment 2 to November (1 Nov to 30 Nov) does NOT overlap -> succeeds
    final updatedBill = await gym.updatePayment(
      paymentId: bill2.paymentId,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
    );
    expect(updatedBill.startDate, DateTime(2026, 11, 1));
    expect(updatedBill.endDate, DateTime(2026, 11, 30));
  });

  testWidgets('MarkPaymentDialog displays overlap warning and blocks submission when dates overlap', (tester) async {
    final customer = await gym.addCustomer(
      name: 'Charlie',
      phone: '9876543213',
      joinDate: DateTime(2026, 10, 1),
      planDurationMonths: 3,
    );

    // Paid payment: 1 Oct 2026 to 31 Dec 2026
    await gym.markPaymentAsPaid(
      customerId: customer.id,
      monthYear: '2026-10',
      method: PaymentMethod.gpay,
      amount: 1500,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 12, 31),
    );

    // Pending record for February with overlapping start date (1 Nov 2026)
    final pendingRecord = PaymentRecord(
      id: 'pending_charlie_test',
      customerId: customer.id,
      monthYear: '2027-02',
      amount: 0,
      totalDue: 500,
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2027, 1, 31),
      durationMonths: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                MarkPaymentDialog.show(
                  ctx,
                  customer: customer,
                  monthYear: '2027-02',
                  currentRecord: pendingRecord,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify the warning text and UI indicator are shown
    expect(find.textContaining('Overlaps with paid plan'), findsOneWidget);
    expect(find.text('Dates Overlap With Paid Plan'), findsOneWidget);
    expect(find.textContaining('Start after paid plan'), findsOneWidget);

    // Attempt to tap the submit button
    await tester.tap(find.text('Dates Overlap With Paid Plan'));
    await tester.pumpAndSettle();

    // The dialog should NOT have dismissed, and should show the error SnackBar
    expect(find.byType(MarkPaymentDialog), findsOneWidget);
    expect(find.textContaining('overlaps with an already paid membership'), findsOneWidget);

    // Tap "Start after paid plan" quick-fix button
    await tester.tap(find.textContaining('Start after paid plan'));
    await tester.pumpAndSettle();

    // The overlap warning should be gone and confirm button active
    expect(find.textContaining('Overlaps with paid plan'), findsNothing);
    expect(find.text('Confirm & Mark as Paid'), findsOneWidget);
  });
}
