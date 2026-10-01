import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/app_subscription.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('subscription status on GymSettings', () {
    test('fresh install is inside the trial window', () {
      const s = GymSettings();
      expect(s.isInTrialPeriod, isTrue);
      expect(s.hasActiveSubscription, isFalse);
      expect(s.subscriptionRequired, isFalse);
      expect(s.trialDaysRemaining, kTrialDays);
    });

    test('trial ends after the trial window', () {
      final s = GymSettings(
        trialStartedAt: DateTime.now().subtract(
          const Duration(days: kTrialDays, hours: 1),
        ),
      );
      expect(s.isInTrialPeriod, isFalse);
      expect(s.trialDaysRemaining, 0);
      expect(s.subscriptionRequired, isTrue);
    });

    test('remaining days count down during trial', () {
      final s = GymSettings(
        trialStartedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.isInTrialPeriod, isTrue);
      expect(s.subscriptionRequired, isFalse);
      expect(s.trialDaysRemaining, kTrialDays - 1);
    });

    test('paid subscription keeps access after trial end', () {
      final s = GymSettings(
        trialStartedAt: DateTime.now().subtract(const Duration(days: 30)),
        subscriptionPaidUntil: DateTime.now().add(const Duration(days: 10)),
      );
      expect(s.hasActiveSubscription, isTrue);
      expect(s.subscriptionRequired, isFalse);
    });

    test('lapsed paid subscription locks the app again', () {
      final s = GymSettings(
        trialStartedAt: DateTime.now().subtract(const Duration(days: 30)),
        subscriptionPaidUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(s.hasActiveSubscription, isFalse);
      expect(s.subscriptionRequired, isTrue);
    });

    test('subscription fields round-trip through json', () {
      final start = DateTime(2026, 10, 1, 12);
      final paid = DateTime(2026, 11, 1, 12);
      final s = GymSettings(
        trialStartedAt: start,
        subscriptionPaidUntil: paid,
        subscriptionPaymentId: 'pay_abc',
      );
      final restored = GymSettings.fromJson(s.toJson());
      expect(restored.trialStartedAt, start);
      expect(restored.subscriptionPaidUntil, paid);
      expect(restored.subscriptionPaymentId, 'pay_abc');
    });

    test('old settings json without subscription fields defaults safely', () {
      final map = const GymSettings().toMap()
        ..remove('trialStartedAt')
        ..remove('subscriptionPaidUntil')
        ..remove('subscriptionPaymentId');
      final restored = GymSettings.fromMap(map);
      expect(restored.trialStartedAt, isNull);
      expect(restored.subscriptionPaidUntil, isNull);
      expect(restored.subscriptionPaymentId, isNull);
    });
  });

  group('GymService subscription lifecycle', () {
    final gym = GymService();

    test('trial start is stamped on attach and subscriptions activate', () async {
      await gym.detachUser();
      SharedPreferences.setMockInitialValues({});
      await gym.init();
      await gym.attachUser('sub-owner', isNewUser: true);

      expect(gym.settings.trialStartedAt, isNotNull);
      expect(gym.settings.isInTrialPeriod, isTrue);
      expect(gym.subscriptionRequired, isFalse);

      await gym.activateSubscription(months: 1, paymentId: 'pay_test_1');
      expect(gym.settings.hasActiveSubscription, isTrue);
      expect(gym.settings.subscriptionPaymentId, 'pay_test_1');
      final firstUntil = gym.settings.subscriptionPaidUntil!;
      expect(
        firstUntil.isAfter(DateTime.now().add(const Duration(days: 25))),
        isTrue,
      );

      // Renewals stack on the remaining paid time.
      await gym.activateSubscription(months: 1, paymentId: 'pay_test_2');
      expect(
        gym.settings.subscriptionPaidUntil!.isAfter(firstUntil),
        isTrue,
      );
      expect(gym.settings.subscriptionPaymentId, 'pay_test_2');
    });

    tearDown(() async => gym.detachUser());
  });
}
