import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/screens/splash/splash_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/payment_receipt_pdf_service.dart';
import 'package:gym/services/whatsapp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('legacy GymSettings maps receive migration-safe defaults', () {
    final settings = GymSettings.fromMap({'gymName': 'Legacy Fitness'});

    expect(settings.gymTagline, GymSettings.defaultTagline);
    expect(settings.gymAddress, isEmpty);
    expect(settings.gymPhone, isEmpty);
    expect(settings.gymEmail, isEmpty);
    expect(settings.gymTimings, isEmpty);
    expect(settings.isTaxEnabled, isFalse);
    expect(settings.taxLabel, 'GST');
    expect(settings.taxRatePercent, 18);
    expect(settings.isTaxInclusive, isTrue);
    expect(settings.receiptTerms, GymSettings.defaultReceiptTerms);
  });

  test('GymSettings preserves branding and receipt preferences', () {
    const original = GymSettings(
      gymName: 'Titan Fitness',
      gymTagline: 'Strength & Conditioning Gym',
      gymAddress: '12 Main Street',
      gymPhone: '+91 90000 00000',
      gymEmail: 'hello@titan.example',
      gymTimings: 'Mon-Sat: 6 AM-10 PM',
      isTaxEnabled: true,
      taxLabel: 'VAT',
      taxRatePercent: 12.5,
      isTaxInclusive: false,
      receiptTerms: 'Custom policy line one.\nCustom policy line two.',
    );

    final restored = GymSettings.fromJson(jsonEncode(original.toMap()));

    expect(restored.gymName, original.gymName);
    expect(restored.gymTagline, original.gymTagline);
    expect(restored.gymAddress, original.gymAddress);
    expect(restored.gymPhone, original.gymPhone);
    expect(restored.gymEmail, original.gymEmail);
    expect(restored.gymTimings, original.gymTimings);
    expect(restored.isTaxEnabled, isTrue);
    expect(restored.taxLabel, 'VAT');
    expect(restored.taxRatePercent, 12.5);
    expect(restored.isTaxInclusive, isFalse);
    expect(restored.receiptTerms, original.receiptTerms);
  });

  test('receipt tax calculation supports inclusive and exclusive pricing', () {
    expect(
      PaymentReceiptPdfService.calculateTaxAmount(
        amount: 1180,
        ratePercent: 18,
        isInclusive: true,
      ),
      closeTo(180, 0.001),
    );
    expect(
      PaymentReceiptPdfService.calculateTaxAmount(
        amount: 1000,
        ratePercent: 18,
        isInclusive: false,
      ),
      closeTo(180, 0.001),
    );
  });

  test('exclusive tax is added to configured prices and reconciles from total',
      () {
    const settings = GymSettings(
      isTaxEnabled: true,
      taxRatePercent: 18,
      isTaxInclusive: false,
    );

    final total = settings.totalForConfiguredPrice(1000);

    expect(total, closeTo(1180, 0.001));
    expect(settings.taxAmountFromTotal(total), closeTo(180, 0.001));
  });

  test('invalid stored tax rates fall back to a finite default', () {
    final settings = GymSettings.fromMap({'taxRatePercent': double.nan});

    expect(settings.taxRatePercent, 18);
    expect(settings.taxRatePercent.isFinite, isTrue);
  });

  test('payment and bill tax snapshots survive serialization', () {
    final payment = PaymentRecord(
      id: 'payment-1',
      customerId: 'member-1',
      monthYear: '2026-10',
      amount: 590,
      totalDue: 1180,
      status: PaymentStatus.paid,
      isTaxEnabled: true,
      taxLabel: 'GST',
      taxRatePercent: 18,
      isTaxInclusive: false,
      taxableAmount: 1000,
      taxAmount: 180,
    );
    final bill = BillRecord(
      id: 'bill-1',
      billNumber: 'BILL-202610-0001',
      customerId: 'member-1',
      customerName: 'Aarav',
      customerPhone: '9876543210',
      monthYear: '2026-10',
      amount: 590,
      paymentId: payment.id,
      method: PaymentMethod.cash,
      paidAt: DateTime(2026, 10, 2),
      gymName: 'Titan Fitness',
      issuedAt: DateTime(2026, 10, 2),
      isTaxEnabled: true,
      taxLabel: 'GST',
      taxRatePercent: 18,
      isTaxInclusive: false,
      taxableAmount: 500,
      taxAmount: 90,
    );

    final restoredPayment = PaymentRecord.fromMap(payment.toMap());
    final restoredBill = BillRecord.fromMap(bill.toMap());

    expect(restoredPayment.totalDue, 1180);
    expect(restoredPayment.taxableAmount, 1000);
    expect(restoredPayment.taxAmount, 180);
    expect(restoredBill.isTaxEnabled, isTrue);
    expect(restoredBill.taxableAmount, 500);
    expect(restoredBill.taxAmount, 90);
  });

  test('exclusive-tax payments snapshot reconciled receipt values', () async {
    final gym = GymService();
    await gym.updateSettings(
      const GymSettings(
        gymName: 'Titan Fitness',
        isTaxEnabled: true,
        taxLabel: 'GST',
        taxRatePercent: 18,
        isTaxInclusive: false,
      ),
    );
    final customer = await gym.addCustomer(
      name: 'Tax Snapshot Member',
      phone: '9000000001',
      planDurationMonths: 1,
      membershipFee: 1000,
      markAsPaidNow: true,
      initialPaymentMethod: PaymentMethod.cash,
      operationId: 'tax-snapshot-member',
    );

    final payment = gym.getPaidPaymentsForCustomer(customer.id).single;
    final bill = gym.getBillForPayment(payment.id)!;

    expect(payment.totalDue, closeTo(1180, 0.001));
    expect(payment.taxableAmount, closeTo(1000, 0.001));
    expect(payment.taxAmount, closeTo(180, 0.001));
    expect(bill.amount, closeTo(1180, 0.001));
    expect(bill.taxableAmount, closeTo(1000, 0.001));
    expect(bill.taxAmount, closeTo(180, 0.001));

    await gym.updateSettings(
      const GymSettings(gymName: 'Titan Fitness', isTaxEnabled: false),
    );
    expect(bill.isTaxEnabled, isTrue);
    expect(bill.taxRatePercent, 18);
  });

  test(
    'WhatsApp welcome message uses configured gym name and timings',
    () async {
      await GymService().updateSettings(
        const GymSettings(
          gymName: 'Titan Fitness',
          gymTimings: 'Mon-Sat: 5:30 AM-10:30 PM',
        ),
      );
      final customer = Customer(
        id: 'member-1',
        name: 'Aarav',
        phone: '9876543210',
        joinDate: DateTime(2026, 10, 1),
      );

      final message = WhatsAppService().buildWelcomeMessage(customer: customer);

      expect(message, contains('Titan Fitness'));
      expect(message, contains('Mon-Sat: 5:30 AM-10:30 PM'));
      expect(message, isNot(contains('6:00 AM')));
    },
  );

  testWidgets('splash screen displays configured gym branding', (tester) async {
    await GymService().updateSettings(
      const GymSettings(
        gymName: 'Titan Fitness',
        gymTagline: 'Strength & Conditioning Gym',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.text('Titan Fitness'), findsOneWidget);
    expect(find.text('Strength & Conditioning Gym'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pumpAndSettle();
  });
}
