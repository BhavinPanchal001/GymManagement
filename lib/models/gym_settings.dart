import 'dart:convert';
import 'customer.dart';
import 'plan_package.dart';

class GymSettings {
  final String gymName;
  final String gymTagline;
  final String gymAddress;
  final String gymPhone;
  final String gymEmail;
  final String gymTimings;
  final String? gymLogoPath;
  final double standardMonthlyFee;
  final double normalPlanFee;
  final double ptPlanFee;
  final double ptDietPlanFee;
  final String currencySymbol;
  final bool isTaxEnabled;
  final String taxLabel;
  final double taxRatePercent;
  final bool isTaxInclusive;
  final String receiptTerms;
  final bool isFirestoreConnected;
  final bool isPaymentDueNotificationEnabled;
  final List<PlanDurationPackage> durationPackages;

  static const String defaultTagline = 'Gym Management & Billing Suite';
  static const String defaultReceiptTerms =
      '1. All gym membership fees once paid are non-refundable, non-adjustable, and strictly non-transferable under any circumstances.\n'
      '2. Membership is valid strictly for the specified period. Post expiration, admission requires timely renewal.\n'
      '3. Members are required to carry this digital receipt or membership card and adhere strictly to gym safety rules and equipment etiquette.\n'
      '4. Management reserves the right of admission and membership suspension in case of violation of gym guidelines.';

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
    this.gymTagline = defaultTagline,
    this.gymAddress = '',
    this.gymPhone = '',
    this.gymEmail = '',
    this.gymTimings = '',
    this.gymLogoPath,
    this.standardMonthlyFee = 600.0,
    this.normalPlanFee = 600.0,
    this.ptPlanFee = 2500.0,
    this.ptDietPlanFee = 3500.0,
    this.currencySymbol = '₹',
    this.isTaxEnabled = false,
    this.taxLabel = 'GST',
    this.taxRatePercent = 18.0,
    this.isTaxInclusive = true,
    this.receiptTerms = defaultReceiptTerms,
    this.isFirestoreConnected = false,
    this.isPaymentDueNotificationEnabled = true,
    this.durationPackages = defaultPackages,
  });

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
    String? gymTagline,
    String? gymAddress,
    String? gymPhone,
    String? gymEmail,
    String? gymTimings,
    String? gymLogoPath,
    bool clearGymLogo = false,
    double? standardMonthlyFee,
    double? normalPlanFee,
    double? ptPlanFee,
    double? ptDietPlanFee,
    String? currencySymbol,
    bool? isTaxEnabled,
    String? taxLabel,
    double? taxRatePercent,
    bool? isTaxInclusive,
    String? receiptTerms,
    bool? isFirestoreConnected,
    bool? isPaymentDueNotificationEnabled,
    List<PlanDurationPackage>? durationPackages,
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
      gymTagline: gymTagline ?? this.gymTagline,
      gymAddress: gymAddress ?? this.gymAddress,
      gymPhone: gymPhone ?? this.gymPhone,
      gymEmail: gymEmail ?? this.gymEmail,
      gymTimings: gymTimings ?? this.gymTimings,
      gymLogoPath: clearGymLogo ? null : (gymLogoPath ?? this.gymLogoPath),
      standardMonthlyFee: standardMonthlyFee ?? effectiveNormalFee,
      normalPlanFee: effectiveNormalFee,
      ptPlanFee: effectivePtFee,
      ptDietPlanFee: effectivePtDietFee,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      isTaxEnabled: isTaxEnabled ?? this.isTaxEnabled,
      taxLabel: taxLabel ?? this.taxLabel,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      receiptTerms: receiptTerms ?? this.receiptTerms,
      isFirestoreConnected: isFirestoreConnected ?? this.isFirestoreConnected,
      isPaymentDueNotificationEnabled: isPaymentDueNotificationEnabled ?? this.isPaymentDueNotificationEnabled,
      durationPackages: updatedPackages,
    );
  }

  Map<String, dynamic> toMap() {
    final effectivePackages = durationPackages.isNotEmpty ? durationPackages : defaultPackages;
    return {
      'gymName': gymName,
      'gymTagline': gymTagline,
      'gymAddress': gymAddress,
      'gymPhone': gymPhone,
      'gymEmail': gymEmail,
      'gymTimings': gymTimings,
      'gymLogoPath': gymLogoPath,
      'standardMonthlyFee': normalPlanFee,
      'normalPlanFee': normalPlanFee,
      'ptPlanFee': ptPlanFee,
      'ptDietPlanFee': ptDietPlanFee,
      'currencySymbol': currencySymbol,
      'isTaxEnabled': isTaxEnabled,
      'taxLabel': taxLabel,
      'taxRatePercent': taxRatePercent,
      'isTaxInclusive': isTaxInclusive,
      'receiptTerms': receiptTerms,
      'isFirestoreConnected': isFirestoreConnected,
      'isPaymentDueNotificationEnabled': isPaymentDueNotificationEnabled,
      'durationPackages': effectivePackages.map((p) => p.toMap()).toList(),
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
      gymTagline: map['gymTagline'] as String? ?? defaultTagline,
      gymAddress: map['gymAddress'] as String? ?? '',
      gymPhone: map['gymPhone'] as String? ?? '',
      gymEmail: map['gymEmail'] as String? ?? '',
      gymTimings: map['gymTimings'] as String? ?? '',
      gymLogoPath: map['gymLogoPath'] as String?,
      standardMonthlyFee: normalFee,
      normalPlanFee: normalFee,
      ptPlanFee: ptFee,
      ptDietPlanFee: ptDietFee,
      currencySymbol: map['currencySymbol'] as String? ?? '₹',
      isTaxEnabled: map['isTaxEnabled'] as bool? ?? false,
      taxLabel: map['taxLabel'] as String? ?? 'GST',
      taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 18.0,
      isTaxInclusive: map['isTaxInclusive'] as bool? ?? true,
      receiptTerms: map['receiptTerms'] as String? ?? defaultReceiptTerms,
      isFirestoreConnected: map['isFirestoreConnected'] as bool? ?? false,
      isPaymentDueNotificationEnabled: map['isPaymentDueNotificationEnabled'] as bool? ?? true,
      durationPackages: packages,
    );
  }

  String toJson() => json.encode(toMap());

  factory GymSettings.fromJson(String source) =>
      GymSettings.fromMap(json.decode(source) as Map<String, dynamic>);
}
