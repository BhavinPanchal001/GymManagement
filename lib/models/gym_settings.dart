import 'dart:convert';
import 'app_subscription.dart';
import 'customer.dart';
import 'plan_package.dart';

class GymSettings {
  final String gymName;
  final String? gymLogoPath;
  final double standardMonthlyFee;
  final double normalPlanFee;
  final double ptPlanFee;
  final double ptDietPlanFee;
  final String currencySymbol;
  final bool isFirestoreConnected;
  final bool isPaymentDueNotificationEnabled;
  final List<PlanDurationPackage> durationPackages;
  /// Razorpay publishable Key ID (rzp_test_... / rzp_live_...) used to open
  /// Razorpay Checkout for online membership fee collection.
  final String razorpayKeyId;

  /// When this owner's free trial started (first app launch after signup).
  /// Set once; null means the trial hasn't been stamped yet (grace window).
  final DateTime? trialStartedAt;
  /// Owner's app subscription is paid through this instant.
  final DateTime? subscriptionPaidUntil;
  /// Razorpay payment id of the most recent subscription purchase.
  final String? subscriptionPaymentId;

  /// A paid plan that reached checkout success but hasn't finished activating
  /// yet. Retried without charging again; cleared on activation.
  final int? pendingSubscriptionMonths;
  final String? pendingSubscriptionPaymentId;

  static const List<PlanDurationPackage> defaultPackages = [
    // Normal Plan Packages
    PlanDurationPackage(id: 'pkg_normal_1', planType: CustomerPlan.normal, months: 1, price: 600.0),
    PlanDurationPackage(id: 'pkg_normal_3', planType: CustomerPlan.normal, months: 3, price: 1500.0),
    PlanDurationPackage(id: 'pkg_normal_6', planType: CustomerPlan.normal, months: 6, price: 2800.0),
    PlanDurationPackage(id: 'pkg_normal_12', planType: CustomerPlan.normal, months: 12, price: 5000.0),

    // Personal Training Plan Packages
    PlanDurationPackage(id: 'pkg_pt_1', planType: CustomerPlan.personalTraining, months: 1, price: 2500.0),
    PlanDurationPackage(id: 'pkg_pt_3', planType: CustomerPlan.personalTraining, months: 3, price: 6500.0),
    PlanDurationPackage(id: 'pkg_pt_6', planType: CustomerPlan.personalTraining, months: 6, price: 12000.0),
    PlanDurationPackage(id: 'pkg_pt_12', planType: CustomerPlan.personalTraining, months: 12, price: 22000.0),

    // Personal Training + Diet Packages
    PlanDurationPackage(id: 'pkg_pt_diet_1', planType: CustomerPlan.personalTrainingDiet, months: 1, price: 3500.0),
    PlanDurationPackage(id: 'pkg_pt_diet_3', planType: CustomerPlan.personalTrainingDiet, months: 3, price: 9000.0),
    PlanDurationPackage(id: 'pkg_pt_diet_6', planType: CustomerPlan.personalTrainingDiet, months: 6, price: 16500.0),
    PlanDurationPackage(id: 'pkg_pt_diet_12', planType: CustomerPlan.personalTrainingDiet, months: 12, price: 30000.0),
  ];

  const GymSettings({
    this.gymName = 'IronPulse Fitness Club',
    this.gymLogoPath,
    this.standardMonthlyFee = 600.0,
    this.normalPlanFee = 600.0,
    this.ptPlanFee = 2500.0,
    this.ptDietPlanFee = 3500.0,
    this.currencySymbol = '₹',
    this.isFirestoreConnected = false,
    this.isPaymentDueNotificationEnabled = true,
    this.durationPackages = defaultPackages,
    this.razorpayKeyId = '',
    this.trialStartedAt,
    this.subscriptionPaidUntil,
    this.subscriptionPaymentId,
    this.pendingSubscriptionMonths,
    this.pendingSubscriptionPaymentId,
  });

  /// Whether a Razorpay Key ID has been configured for online collections.
  bool get hasRazorpayKey => razorpayKeyId.trim().isNotEmpty;

  /// End of the owner's free trial window.
  DateTime get trialEndsAt =>
      (trialStartedAt ?? DateTime.now()).add(const Duration(days: kTrialDays));

  /// Whole days left in the free trial (0 once it ends).
  int get trialDaysRemaining {
    final remaining = trialEndsAt.difference(DateTime.now());
    if (remaining.isNegative) return 0;
    return (remaining.inMinutes / (24 * 60)).ceil();
  }

  /// Still inside the free trial (or the trial hasn't been stamped yet).
  bool get isInTrialPeriod => DateTime.now().isBefore(trialEndsAt);

  /// Owner's app subscription is currently paid up.
  bool get hasActiveSubscription =>
      subscriptionPaidUntil != null &&
      subscriptionPaidUntil!.isAfter(DateTime.now());

  /// Trial ended and no paid subscription — the app should show the paywall.
  bool get subscriptionRequired =>
      !isInTrialPeriod && !hasActiveSubscription;

  /// A completed payment is still waiting to be activated.
  bool get hasPendingSubscription =>
      pendingSubscriptionMonths != null && pendingSubscriptionMonths! > 0;

  /// The next moment the trial or paid plan ends — null when already expired.
  DateTime? get subscriptionExpiryBoundary {
    if (hasActiveSubscription) return subscriptionPaidUntil;
    if (isInTrialPeriod) return trialEndsAt;
    return null;
  }

  /// Returns all packages available for a given plan tier sorted by month count
  List<PlanDurationPackage> getPackagesForPlan(String? planType) {
    final effectivePlan = (planType == null || planType.isEmpty) ? CustomerPlan.normal : planType;
    final all = durationPackages.isNotEmpty ? durationPackages : defaultPackages;
    final filtered = all.where((p) => p.planType == effectivePlan).toList();
    filtered.sort((a, b) => a.months.compareTo(b.months));
    return filtered;
  }

  /// Looks up a package by plan type and months
  PlanDurationPackage? getPackage(String? planType, int months) {
    final effectivePlanType = planType ?? CustomerPlan.normal;
    final packages = durationPackages.isNotEmpty ? durationPackages : defaultPackages;
    try {
      return packages.firstWhere(
        (p) => p.planType == effectivePlanType && p.months == months,
      );
    } catch (_) {
      return null;
    }
  }

  /// Calculates package price for given plan and duration
  double getPriceForDuration(String? planType, int months) {
    final pkg = getPackage(planType, months);
    if (pkg != null) return pkg.price;
    // Fallback: 1-month fee multiplied by months
    final singleFee = getFeeForPlan(planType);
    return singleFee * (months > 0 ? months : 1);
  }

  /// Resolves the monthly price for a given plan type key (1-month baseline)
  double getFeeForPlan(String? planType) {
    switch (planType) {
      case CustomerPlan.personalTraining:
      case 'pt':
        return ptPlanFee > 0 ? ptPlanFee : 2500.0;
      case CustomerPlan.personalTrainingDiet:
      case 'pt_diet':
        return ptDietPlanFee > 0 ? ptDietPlanFee : 3500.0;
      case CustomerPlan.normal:
      default:
        return normalPlanFee > 0 ? normalPlanFee : standardMonthlyFee;
    }
  }

  GymSettings copyWith({
    String? gymName,
    String? gymLogoPath,
    bool clearGymLogo = false,
    double? standardMonthlyFee,
    double? normalPlanFee,
    double? ptPlanFee,
    double? ptDietPlanFee,
    String? currencySymbol,
    bool? isFirestoreConnected,
    bool? isPaymentDueNotificationEnabled,
    List<PlanDurationPackage>? durationPackages,
    String? razorpayKeyId,
    DateTime? trialStartedAt,
    DateTime? subscriptionPaidUntil,
    String? subscriptionPaymentId,
    int? pendingSubscriptionMonths,
    String? pendingSubscriptionPaymentId,
    bool clearPendingSubscription = false,
  }) {
    final effectiveNormalFee = normalPlanFee ?? this.normalPlanFee;
    final effectivePtFee = ptPlanFee ?? this.ptPlanFee;
    final effectivePtDietFee = ptDietPlanFee ?? this.ptDietPlanFee;

    List<PlanDurationPackage> updatedPackages = durationPackages ?? List.from(this.durationPackages);
    if (durationPackages == null && (normalPlanFee != null || ptPlanFee != null || ptDietPlanFee != null)) {
      updatedPackages = updatedPackages.map((p) {
        if (p.months == 1) {
          if (p.planType == CustomerPlan.normal && normalPlanFee != null) {
            return p.copyWith(price: normalPlanFee);
          }
          if (p.planType == CustomerPlan.personalTraining && ptPlanFee != null) {
            return p.copyWith(price: ptPlanFee);
          }
          if (p.planType == CustomerPlan.personalTrainingDiet && ptDietPlanFee != null) {
            return p.copyWith(price: ptDietPlanFee);
          }
        }
        return p;
      }).toList();
    }

    return GymSettings(
      gymName: gymName ?? this.gymName,
      gymLogoPath: clearGymLogo ? null : (gymLogoPath ?? this.gymLogoPath),
      standardMonthlyFee: standardMonthlyFee ?? effectiveNormalFee,
      normalPlanFee: effectiveNormalFee,
      ptPlanFee: effectivePtFee,
      ptDietPlanFee: effectivePtDietFee,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isFirestoreConnected: isFirestoreConnected ?? this.isFirestoreConnected,
      isPaymentDueNotificationEnabled: isPaymentDueNotificationEnabled ?? this.isPaymentDueNotificationEnabled,
      durationPackages: updatedPackages,
      razorpayKeyId: razorpayKeyId ?? this.razorpayKeyId,
      trialStartedAt: trialStartedAt ?? this.trialStartedAt,
      subscriptionPaidUntil: subscriptionPaidUntil ?? this.subscriptionPaidUntil,
      subscriptionPaymentId: subscriptionPaymentId ?? this.subscriptionPaymentId,
      pendingSubscriptionMonths: clearPendingSubscription
          ? null
          : (pendingSubscriptionMonths ?? this.pendingSubscriptionMonths),
      pendingSubscriptionPaymentId: clearPendingSubscription
          ? null
          : (pendingSubscriptionPaymentId ?? this.pendingSubscriptionPaymentId),
    );
  }

  Map<String, dynamic> toMap() {
    final effectivePackages = durationPackages.isNotEmpty ? durationPackages : defaultPackages;
    return {
      'gymName': gymName,
      'gymLogoPath': gymLogoPath,
      'standardMonthlyFee': normalPlanFee,
      'normalPlanFee': normalPlanFee,
      'ptPlanFee': ptPlanFee,
      'ptDietPlanFee': ptDietPlanFee,
      'currencySymbol': currencySymbol,
      'isFirestoreConnected': isFirestoreConnected,
      'isPaymentDueNotificationEnabled': isPaymentDueNotificationEnabled,
      'durationPackages': effectivePackages.map((p) => p.toMap()).toList(),
      'razorpayKeyId': razorpayKeyId,
      'trialStartedAt': trialStartedAt?.toIso8601String(),
      'subscriptionPaidUntil': subscriptionPaidUntil?.toIso8601String(),
      'subscriptionPaymentId': subscriptionPaymentId,
      'pendingSubscriptionMonths': pendingSubscriptionMonths,
      'pendingSubscriptionPaymentId': pendingSubscriptionPaymentId,
    };
  }

  factory GymSettings.fromMap(Map<String, dynamic> map) {
    final standardFee = (map['standardMonthlyFee'] as num?)?.toDouble() ?? 600.0;
    final normalFee = (map['normalPlanFee'] as num?)?.toDouble() ?? standardFee;
    final ptFee = (map['ptPlanFee'] as num?)?.toDouble() ?? 2500.0;
    final ptDietFee = (map['ptDietPlanFee'] as num?)?.toDouble() ?? 3500.0;

    List<PlanDurationPackage> packages = [];
    if (map['durationPackages'] is List) {
      packages = (map['durationPackages'] as List)
          .map((item) => PlanDurationPackage.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    if (packages.isEmpty) {
      packages = List.from(defaultPackages);
    }

    return GymSettings(
      gymName: map['gymName'] as String? ?? 'IronPulse Fitness Club',
      gymLogoPath: map['gymLogoPath'] as String?,
      standardMonthlyFee: normalFee,
      normalPlanFee: normalFee,
      ptPlanFee: ptFee,
      ptDietPlanFee: ptDietFee,
      currencySymbol: map['currencySymbol'] as String? ?? '₹',
      isFirestoreConnected: map['isFirestoreConnected'] as bool? ?? false,
      isPaymentDueNotificationEnabled: map['isPaymentDueNotificationEnabled'] as bool? ?? true,
      durationPackages: packages,
      razorpayKeyId: map['razorpayKeyId'] as String? ?? '',
      trialStartedAt: map['trialStartedAt'] != null
          ? DateTime.tryParse(map['trialStartedAt'] as String)
          : null,
      subscriptionPaidUntil: map['subscriptionPaidUntil'] != null
          ? DateTime.tryParse(map['subscriptionPaidUntil'] as String)
          : null,
      subscriptionPaymentId: map['subscriptionPaymentId'] as String?,
      pendingSubscriptionMonths: (map['pendingSubscriptionMonths'] as num?)?.toInt(),
      pendingSubscriptionPaymentId: map['pendingSubscriptionPaymentId'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory GymSettings.fromJson(String source) =>
      GymSettings.fromMap(json.decode(source) as Map<String, dynamic>);
}
