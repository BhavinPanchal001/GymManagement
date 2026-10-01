import 'package:flutter/material.dart';

import '../../models/app_subscription.dart';
import '../../services/auth_service.dart';
import '../../services/gym_service.dart';
import '../../services/razorpay_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

/// Subscription screen for the app itself: shows trial/subscription status and
/// lets the gym owner buy a plan via Razorpay. Rendered blocking-style in place
/// of HomeScreen once the trial has expired, or pushed as a normal route while
/// the trial is still running.
class SubscriptionScreen extends StatefulWidget {
  /// When true the owner is locked out until they subscribe (trial expired).
  final bool blocking;

  const SubscriptionScreen({super.key, this.blocking = true});

  /// Opens the screen as a regular route (used from the trial banner/Settings).
  static Future<void> navigate(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SubscriptionScreen(blocking: false)),
    );
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  AppSubscriptionPlan _selectedPlan = kAppSubscriptionPlans.first;
  bool _paying = false;
  String? _error;

  /// A payment that already succeeded at checkout but hasn't activated yet —
  /// retried without opening checkout again. In-memory fallback for when the
  /// settings record itself couldn't be saved.
  int _pendingMonths = 0;
  String _pendingPaymentId = '';

  bool get _billingConfigured => kAppRazorpayKeyId.trim().isNotEmpty;

  Future<void> _subscribe() async {
    if (_paying) return;
    if (!_billingConfigured) {
      setState(() => _error =
          'Subscription payments are not configured yet. Please contact the app publisher.');
      return;
    }
    if (!RazorpayService().isSupported) {
      setState(() => _error =
          'Online payment is only available on Android and iOS.');
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    final auth = AuthService();
    RazorpayPaymentResult result;
    try {
      result = await RazorpayService().collectPayment(
        amountInr: _selectedPlan.price,
        description:
            'Gym Manager ${_selectedPlan.title} subscription (${_selectedPlan.months} month${_selectedPlan.months > 1 ? 's' : ''})',
        memberName: auth.displayName,
        contact: auth.phoneNumber,
        email: auth.email,
        keyIdOverride: kAppRazorpayKeyId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _paying = false;
          _error = 'The payment failed. Please try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    if (result.cancelled) {
      setState(() {
        _paying = false;
        _error = 'Payment was cancelled.';
      });
      return;
    }
    if (!result.success) {
      setState(() {
        _paying = false;
        _error =
            result.errorMessage ?? 'The payment failed. Please try again.';
      });
      return;
    }

    // Payment succeeded — remember it before activating so a failure below
    // retries activation instead of charging the owner a second time.
    _pendingMonths = _selectedPlan.months;
    _pendingPaymentId = result.paymentId ?? '';
    setState(() => _paying = false);
    await _activatePendingSubscription();
  }

  /// Activates a purchase that already cleared checkout — never re-opens
  /// Razorpay, so a retry can't double-charge the owner.
  Future<void> _activatePendingSubscription() async {
    if (_paying) return;
    final gym = GymService();
    final months = _pendingMonths > 0
        ? _pendingMonths
        : (gym.settings.pendingSubscriptionMonths ?? 0);
    final paymentId = _pendingPaymentId.isNotEmpty
        ? _pendingPaymentId
        : (gym.settings.pendingSubscriptionPaymentId ?? '');
    if (months <= 0) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      // Persist the purchase first: the synced record lets this device — or
      // another one — finish activation later without a second charge.
      await gym.recordPendingSubscription(
        months: months,
        paymentId: paymentId,
      );
      await gym.activateSubscription(months: months, paymentId: paymentId);
      if (!mounted) return;
      _pendingMonths = 0;
      _pendingPaymentId = '';
      final paidUntil = gym.settings.subscriptionPaidUntil;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paidUntil != null
                ? 'Subscription active until ${GymDateUtils.formatDate(paidUntil)}!'
                : 'Subscription activated!',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.paid,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (!widget.blocking && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Payment received, but activation did not finish. Tap "Complete activation" — you will not be charged again.');
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GymService(),
      builder: (context, _) {
        final settings = GymService().settings;
        final currency = settings.currencySymbol;
        final isExpired = settings.subscriptionRequired;
        final isActive = settings.hasActiveSubscription;
        final hasPending =
            _pendingMonths > 0 || settings.hasPendingSubscription;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: widget.blocking
              ? null
              : AppBar(title: const Text('Subscription')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isActive
                            ? Icons.verified_rounded
                            : Icons.workspace_premium_rounded,
                        color: isActive ? AppColors.paid : AppColors.primary,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isActive
                        ? 'Subscription Active'
                        : isExpired
                            ? 'Subscription Required'
                            : 'Free Trial',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isActive
                        ? 'Your plan is paid until ${GymDateUtils.formatDate(settings.subscriptionPaidUntil!)}.'
                        : isExpired
                            ? 'Your $kTrialDays-day free trial has ended. Pick a plan to keep managing members, attendance and payments.'
                            : 'You have ${settings.trialDaysRemaining} day${settings.trialDaysRemaining == 1 ? '' : 's'} left in your free trial (ends ${GymDateUtils.formatDate(settings.trialEndsAt)}).',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Plan cards
                  ...kAppSubscriptionPlans.map((plan) {
                    final isSelected = plan == _selectedPlan;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => setState(() => _selectedPlan = plan),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.surfaceBorder,
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          plan.title,
                                          style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (plan.badge != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.paid
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              plan.badge!,
                                              style: TextStyle(
                                                color: AppColors.paid,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${plan.months} month${plan.months > 1 ? 's' : ''} • ${GymDateUtils.formatCurrency(plan.monthlyRate, symbol: currency)}/mo',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                GymDateUtils.formatCurrency(plan.price,
                                    symbol: currency),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _paying || (!hasPending && !_billingConfigured)
                          ? null
                          : (hasPending
                              ? _activatePendingSubscription
                              : _subscribe),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF528FF0),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.textMuted.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: _paying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.bolt_rounded, size: 20),
                      label: Text(
                        _paying
                            ? 'Please wait...'
                            : hasPending
                                ? 'Complete Activation'
                                : 'Pay ${GymDateUtils.formatCurrency(_selectedPlan.price, symbol: currency)} via Razorpay',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasPending
                        ? 'Your payment was received — finish activating it. No new charge.'
                        : 'UPI, cards, net banking & more — secure checkout by Razorpay.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  if (!_billingConfigured) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Subscription billing is not configured yet — the app publisher must add the Razorpay Key ID.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.pending, fontSize: 12),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.absent, fontSize: 13),
                    ),
                  ],

                  if (widget.blocking) ...[
                    const SizedBox(height: 18),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => AuthService().signOut(),
                        icon: Icon(Icons.logout_rounded,
                            size: 16, color: AppColors.textMuted),
                        label: Text(
                          'Sign out',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
