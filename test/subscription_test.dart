import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/app_subscription.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('addMonthsClamped', () {
    test('clamps month-end overflow instead of rolling over', () {
      expect(
        GymDateUtils.addMonthsClamped(DateTime(2026, 1, 31, 10, 30), 1),
        DateTime(2026, 2, 28, 10, 30),
      );
      // Leap year February.
      expect(
        GymDateUtils.addMonthsClamped(DateTime(2024, 1, 31), 1),
        DateTime(2024, 2, 29),
      );
      // Quarterly from Nov 30 lands on Feb 28/29, not March 2.
      expect(
        GymDateUtils.addMonthsClamped(DateTime(2026, 11, 30), 3),
        DateTime(2027, 2, 28),
      );
    });

    test('keeps the day when the target month is long enough', () {
      expect(
        GymDateUtils.addMonthsClamped(DateTime(2026, 3, 15, 8), 1),
        DateTime(2026, 4, 15, 8),
      );
      expect(
        GymDateUtils.addMonthsClamped(DateTime(2026, 12, 31), 1),
        DateTime(2027, 1, 31),
      );
    });
  });

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

    test('pending purchase is recorded and cleared on activation', () async {
      await gym.detachUser();
      SharedPreferences.setMockInitialValues({});
      await gym.init();
      await gym.attachUser('pending-owner', isNewUser: true);

      await gym.recordPendingSubscription(
        months: 3,
        paymentId: 'pay_pending_1',
      );
      expect(gym.settings.hasPendingSubscription, isTrue);
      expect(gym.settings.pendingSubscriptionMonths, 3);
      expect(gym.settings.pendingSubscriptionPaymentId, 'pay_pending_1');

      // A pending record survives a settings round-trip.
      final restored = GymSettings.fromJson(gym.settings.toJson());
      expect(restored.hasPendingSubscription, isTrue);

      // Resuming activates the plan and clears the pending record.
      await gym.resumePendingSubscription();
      expect(gym.settings.hasActiveSubscription, isTrue);
      expect(gym.settings.subscriptionPaidUntil!.month, isNotNull);
      expect(gym.settings.hasPendingSubscription, isFalse);
      expect(gym.settings.pendingSubscriptionPaymentId, isNull);
      expect(gym.settings.subscriptionPaymentId, 'pay_pending_1');
    });

    test('pending fields default safely in old settings json', () {
      final map = const GymSettings().toMap()
        ..remove('pendingSubscriptionMonths')
        ..remove('pendingSubscriptionPaymentId');
      final restored = GymSettings.fromMap(map);
      expect(restored.hasPendingSubscription, isFalse);
      expect(restored.pendingSubscriptionPaymentId, isNull);
    });

    tearDown(() async => gym.detachUser());
  });
}
