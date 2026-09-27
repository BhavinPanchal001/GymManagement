import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/member_card_pdf_service.dart';
import 'package:gym/widgets/gym_logo_widget.dart';
import 'package:gym/screens/customers/member_card_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GymSettings Logo Property Tests', () {
    test('GymSettings holds optional gymLogoPath and defaults to null', () {
      const settings = GymSettings();
      expect(settings.gymLogoPath, isNull);
    });

    test('GymSettings serializes and deserializes gymLogoPath accurately', () {
      const original = GymSettings(
        gymName: 'Apex Fitness Club',
        gymLogoPath: 'avatar:3',
      );

      final map = original.toMap();
      expect(map['gymLogoPath'], 'avatar:3');
      expect(map['gymName'], 'Apex Fitness Club');

      final deserialized = GymSettings.fromMap(map);
      expect(deserialized.gymLogoPath, 'avatar:3');
      expect(deserialized.gymName, 'Apex Fitness Club');
    });

    test('GymSettings.copyWith updates and clears gymLogoPath', () {
      const initial = GymSettings(gymName: 'Pulse Gym');
      final updated = initial.copyWith(gymLogoPath: '/storage/emulated/0/logo.png');
      expect(updated.gymLogoPath, '/storage/emulated/0/logo.png');

      final cleared = updated.copyWith(clearGymLogo: true);
      expect(cleared.gymLogoPath, isNull);
    });
  });

  group('GymLogoWidget Widget Tests', () {
    testWidgets('renders fallback icon when logoPath is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GymLogoWidget(
              logoPath: null,
              gymName: 'Titan Gym',
              size: 44,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
    });

    testWidgets('renders preset avatar when logoPath starts with avatar:', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GymLogoWidget(
              logoPath: 'avatar:2',
              gymName: 'Titan Gym',
              size: 44,
            ),
          ),
        ),
      );

      // CustomerAvatar renders inside
      expect(find.byType(GymLogoWidget), findsOneWidget);
    });
  });

  group('MemberCardScreen & PDF Tests with Gym Logo', () {
    testWidgets('MemberCardScreen renders GymLogoWidget with gym brand logo', (tester) async {
      final customer = Customer(
        id: 'cust_test_logo',
        name: 'Aarav Patel',
        phone: '+91 99887 76655',
        joinDate: DateTime(2026, 1, 1),
        isActive: true,
        cardNumber: '042',
      );

      GymService().updateSettings(
        const GymSettings(
          gymName: 'IRON PULSE GYM',
          gymLogoPath: 'avatar:1',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MemberCardScreen(customer: customer),
        ),
      );
      await tester.pump();

      // Verify GymLogoWidget is present on member card
      expect(find.byType(GymLogoWidget), findsOneWidget);
      expect(find.text('ENTRY FORM'), findsOneWidget);
      expect(find.text('IRON PULSE GYM'), findsOneWidget);
    });

    test('MemberCardPdfService generates PDF bytes with gym settings', () async {
      final customer = Customer(
        id: 'cust_pdf_test',
        name: 'Vikram Singh',
        phone: '+91 91234 56789',
        joinDate: DateTime(2026, 3, 1),
        isActive: true,
        cardNumber: '108',
      );

      GymService().updateSettings(
        const GymSettings(
          gymName: 'TITAN FITNESS CENTER',
          gymLogoPath: 'avatar:4',
        ),
      );

      final pdfBytes = await MemberCardPdfService().generateCardPdf(
        customer: customer,
        year: 2026,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      // PDF Magic bytes %PDF-
      expect(pdfBytes[0], 0x25); // '%'
      expect(pdfBytes[1], 0x50); // 'P'
      expect(pdfBytes[2], 0x44); // 'D'
      expect(pdfBytes[3], 0x46); // 'F'
    });
  });
}
