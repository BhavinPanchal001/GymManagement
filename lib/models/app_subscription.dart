// App-level subscription for gym owners (the SaaS plan for using Gym Manager
// itself — separate from member fee collection, which uses the owner's own
// Razorpay key configured in Settings).

/// Length of the free trial granted to every new gym owner.
const int kTrialDays = 3;

/// Publisher Razorpay Key ID that receives subscription payments.
///
/// TODO(release): paste the app publisher's `rzp_live_...` Key ID here before
/// shipping. Use `rzp_test_...` while testing. This is the publishable key —
/// never store the Key Secret in the app.
const String kAppRazorpayKeyId = '';

class AppSubscriptionPlan {
  final String id;
  final int months;
  final double price;
  final String title;
  final String? badge;

  const AppSubscriptionPlan({
    required this.id,
    required this.months,
    required this.price,
    required this.title,
    this.badge,
  });

  double get monthlyRate => months > 0 ? price / months : price;
}

/// Subscription plans offered to gym owners after the free trial.
const List<AppSubscriptionPlan> kAppSubscriptionPlans = [
  AppSubscriptionPlan(
    id: 'app_sub_1m',
    months: 1,
    price: 199,
    title: 'Monthly',
  ),
  AppSubscriptionPlan(
    id: 'app_sub_3m',
    months: 3,
    price: 499,
    title: 'Quarterly',
  ),
  AppSubscriptionPlan(
    id: 'app_sub_12m',
    months: 12,
    price: 1499,
    title: 'Yearly',
    badge: 'BEST VALUE',
  ),
];
