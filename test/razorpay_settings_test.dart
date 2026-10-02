import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';

void main() {
  group('PaymentMethod.razorpay', () {
    test('has Razorpay label and round-trips through fromString', () {
      expect(PaymentMethod.razorpay.label, 'Razorpay');
      expect(PaymentMethod.fromString('razorpay'), PaymentMethod.razorpay);
      expect(PaymentMethod.fromString('Razorpay'), PaymentMethod.razorpay);
    });
  });

  group('GymSettings razorpayKeyId', () {
    test('defaults to empty and not configured', () {
      const settings = GymSettings();
      expect(settings.razorpayKeyId, '');
      expect(settings.hasRazorpayKey, isFalse);
    });

    test('persists through toMap/fromMap', () {
      final settings = const GymSettings().copyWith(
        razorpayKeyId: 'rzp_test_123456',
      );
      final restored = GymSettings.fromMap(settings.toMap());
      expect(restored.razorpayKeyId, 'rzp_test_123456');
      expect(restored.hasRazorpayKey, isTrue);
    });

    test('missing key in stored map restores as empty', () {
      final restored = GymSettings.fromMap(const GymSettings().toMap()
        ..remove('razorpayKeyId'));
      expect(restored.razorpayKeyId, '');
      expect(restored.hasRazorpayKey, isFalse);
    });
  });
}
