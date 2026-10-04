import 'dart:convert';
import 'customer.dart';
import 'payment.dart';
import '../utils/date_utils.dart';

class BillRecord {
  final String id;
  final String billNumber;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String planType;
  /// Format: "YYYY-MM", e.g. "2026-09"
  final String monthYear;
  final double amount;
  /// The payment record this bill was issued for ('' for un-migrated legacy bills).
  final String paymentId;
  /// 'FULL', 'PARTIAL' or 'BALANCE'.
  final String billType;
  final PaymentMethod method;
  final DateTime paidAt;
  final String? notes;
  final String? transactionRef;
  final String gymName;
  final DateTime issuedAt;
  final bool isTaxEnabled;
  final String taxLabel;
  final double taxRatePercent;
  final bool isTaxInclusive;
  final double taxableAmount;
  final double taxAmount;
  final String status; // 'PAID' or 'CANCELLED'
  final int durationMonths;
  final String? coveragePeriod;
  final DateTime? startDate;
  final DateTime? endDate;

  const BillRecord({
    required this.id,
    required this.billNumber,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.planType = CustomerPlan.normal,
    required this.monthYear,
    required this.amount,
    required this.paymentId,
    this.billType = 'FULL',
    required this.method,
    required this.paidAt,
    this.notes,
    this.transactionRef,
    required this.gymName,
    required this.issuedAt,
    this.isTaxEnabled = false,
    this.taxLabel = 'GST',
    this.taxRatePercent = 0.0,
    this.isTaxInclusive = true,
    this.taxableAmount = 0.0,
    this.taxAmount = 0.0,
    this.status = 'PAID',
    this.durationMonths = 1,
    this.coveragePeriod,
    this.startDate,
    this.endDate,
  });

  bool get isPaid => status == 'PAID';

  DateTime get effectiveStartDate {
    if (startDate != null) return startDate!;
    return paidAt;
  }

  DateTime get effectiveEndDate {
    if (endDate != null) return endDate!;
    return GymDateUtils.computeAnniversaryEndDate(effectiveStartDate, durationMonths);
  }

  String get formattedValidityPeriod {
    if (coveragePeriod != null && coveragePeriod!.isNotEmpty) {
      return coveragePeriod!;
    }
    return GymDateUtils.formatDateRange(effectiveStartDate, effectiveEndDate);
  }

  BillRecord copyWith({
    String? id,
    String? billNumber,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? planType,
    String? monthYear,
    double? amount,
    String? paymentId,
    String? billType,
    PaymentMethod? method,
    DateTime? paidAt,
    String? notes,
    String? transactionRef,
    String? gymName,
    DateTime? issuedAt,
    bool? isTaxEnabled,
    String? taxLabel,
    double? taxRatePercent,
    bool? isTaxInclusive,
    double? taxableAmount,
    double? taxAmount,
    String? status,
    int? durationMonths,
    String? coveragePeriod,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return BillRecord(
      id: id ?? this.id,
      billNumber: billNumber ?? this.billNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      planType: planType ?? this.planType,
      monthYear: monthYear ?? this.monthYear,
      amount: amount ?? this.amount,
      paymentId: paymentId ?? this.paymentId,
      billType: billType ?? this.billType,
      method: method ?? this.method,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      transactionRef: transactionRef ?? this.transactionRef,
      gymName: gymName ?? this.gymName,
      issuedAt: issuedAt ?? this.issuedAt,
      isTaxEnabled: isTaxEnabled ?? this.isTaxEnabled,
      taxLabel: taxLabel ?? this.taxLabel,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      taxableAmount: taxableAmount ?? this.taxableAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      status: status ?? this.status,
      durationMonths: durationMonths ?? this.durationMonths,
      coveragePeriod: coveragePeriod ?? this.coveragePeriod,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'billNumber': billNumber,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'planType': planType,
      'monthYear': monthYear,
      'amount': amount,
      'paymentId': paymentId,
      'billType': billType,
      'method': method.name,
      'paidAt': paidAt.toIso8601String(),
      'notes': notes,
      'transactionRef': transactionRef,
      'gymName': gymName,
      'issuedAt': issuedAt.toIso8601String(),
      'isTaxEnabled': isTaxEnabled,
      'taxLabel': taxLabel,
      'taxRatePercent': taxRatePercent,
      'isTaxInclusive': isTaxInclusive,
      'taxableAmount': taxableAmount,
      'taxAmount': taxAmount,
      'status': status,
      'durationMonths': durationMonths,
      'coveragePeriod': coveragePeriod,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }

  factory BillRecord.fromMap(Map<String, dynamic> map) {
    return BillRecord(
      id: map['id'] as String? ?? '',
      billNumber: map['billNumber'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      customerName: map['customerName'] as String? ?? '',
      customerPhone: map['customerPhone'] as String? ?? '',
      planType: map['planType'] as String? ?? CustomerPlan.normal,
      monthYear: map['monthYear'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentId: map['paymentId'] as String? ?? '',
      billType: map['billType'] as String? ?? 'FULL',
      method: PaymentMethod.fromString(map['method'] as String?),
      paidAt: map['paidAt'] != null
          ? (DateTime.tryParse(map['paidAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      notes: map['notes'] as String?,
      transactionRef: map['transactionRef'] as String?,
      gymName: map['gymName'] as String? ?? 'Gym',
      issuedAt: map['issuedAt'] != null
          ? (DateTime.tryParse(map['issuedAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      isTaxEnabled: map['isTaxEnabled'] as bool? ?? false,
      taxLabel: map['taxLabel'] as String? ?? 'GST',
      taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusive: map['isTaxInclusive'] as bool? ?? true,
      taxableAmount: (map['taxableAmount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (map['taxAmount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'PAID',
      durationMonths: (map['durationMonths'] as num?)?.toInt() ?? 1,
      coveragePeriod: map['coveragePeriod'] as String?,
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'] as String)
          : null,
      endDate: map['endDate'] != null
          ? DateTime.tryParse(map['endDate'] as String)
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory BillRecord.fromJson(String source) =>
      BillRecord.fromMap(json.decode(source) as Map<String, dynamic>);
}
