import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
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
