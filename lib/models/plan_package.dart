import 'dart:convert';
import 'customer.dart';

class PlanDurationPackage {
  final String id;
  /// Plan tier key: CustomerPlan.normal, CustomerPlan.personalTraining, or CustomerPlan.personalTrainingDiet
  final String planType;
  /// Number of months covered (1, 3, 6, 12, or custom like 2, 4)
  final int months;
  /// Total package price in gym currency (e.g. 1500.0)
  final double price;
  /// Optional display title
  final String? customTitle;

  const PlanDurationPackage({
    required this.id,
    required this.planType,
    required this.months,
    required this.price,
    this.customTitle,
  });

  String get title {
    if (customTitle != null && customTitle!.trim().isNotEmpty) {
      return customTitle!.trim();
    }
    switch (months) {
      case 1:
        return '1 Month (Monthly)';
      case 3:
        return '3 Months (Quarterly)';
      case 6:
        return '6 Months (Half-Yearly)';
      case 12:
        return '1 Year (Annual)';
      default:
        return '$months Months';
    }
  }

  String get shortTitle {
    switch (months) {
      case 1:
        return '1M';
      case 3:
        return '3M';
      case 6:
        return '6M';
      case 12:
        return '1Y';
      default:
        return '${months}M';
    }
  }

  double get monthlyRate => months > 0 ? (price / months) : price;

  PlanDurationPackage copyWith({
    String? id,
    String? planType,
    int? months,
    double? price,
    String? customTitle,
  }) {
    return PlanDurationPackage(
      id: id ?? this.id,
      planType: planType ?? this.planType,
      months: months ?? this.months,
      price: price ?? this.price,
      customTitle: customTitle ?? this.customTitle,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'planType': planType,
      'months': months,
      'price': price,
      'customTitle': customTitle,
    };
  }

  factory PlanDurationPackage.fromMap(Map<String, dynamic> map) {
    return PlanDurationPackage(
      id: map['id'] as String? ?? 'pkg_${DateTime.now().millisecondsSinceEpoch}',
      planType: map['planType'] as String? ?? CustomerPlan.normal,
      months: (map['months'] as num?)?.toInt() ?? 1,
      price: (map['price'] as num?)?.toDouble() ?? 600.0,
      customTitle: map['customTitle'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory PlanDurationPackage.fromJson(String source) =>
      PlanDurationPackage.fromMap(json.decode(source) as Map<String, dynamic>);
}
