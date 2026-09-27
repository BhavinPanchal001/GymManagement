import 'dart:convert';
import 'customer.dart';
import '../utils/date_utils.dart';

enum PaymentStatus {
  paid,
  pending,
  overdue;

  String get label {
    switch (this) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.overdue:
        return 'Overdue';
    }
  }

  static PaymentStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'paid':
        return PaymentStatus.paid;
      case 'overdue':
        return PaymentStatus.overdue;
      case 'pending':
      default:
        return PaymentStatus.pending;
    }
  }
}

enum PaymentMethod {
  cash,
  gpay,
  phonepe,
  paytm,
  upi,
  card,
  netBanking;

  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.gpay:
        return 'Google Pay';
      case PaymentMethod.phonepe:
        return 'PhonePe';
      case PaymentMethod.paytm:
        return 'Paytm';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.netBanking:
        return 'Net Banking';
    }
  }

  static PaymentMethod fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'gpay':
      case 'google pay':
        return PaymentMethod.gpay;
      case 'phonepe':
        return PaymentMethod.phonepe;
      case 'paytm':
        return PaymentMethod.paytm;
      case 'upi':
        return PaymentMethod.upi;
      case 'card':
        return PaymentMethod.card;
      case 'netbanking':
      case 'net banking':
        return PaymentMethod.netBanking;
      case 'cash':
      default:
        return PaymentMethod.cash;
    }
  }
}

class PaymentRecord {
  final String id;
  final String customerId;
  /// Format: "YYYY-MM", e.g. "2026-09"
  final String monthYear;
  final double amount;
  final PaymentStatus status;
  final PaymentMethod? method;
  final DateTime? paidAt;
  final String? notes;
  final String? transactionRef;
  /// Number of months covered by this payment (1 for standard monthly, or 3, 6, 12)
  final int durationMonths;
  /// If this month was covered as part of a multi-month package paid in another month,
  /// this points to that month (e.g. "2026-09")
  final String? coveredByMonthYear;
  /// Exact start date of this membership period (e.g., 2026-09-15)
  final DateTime? startDate;
  /// Exact end date of this membership period (e.g., 2026-10-14)
  final DateTime? endDate;

  const PaymentRecord({
    required this.id,
    required this.customerId,
    required this.monthYear,
    required this.amount,
    this.status = PaymentStatus.pending,
    this.method,
    this.paidAt,
    this.notes,
    this.transactionRef,
    this.durationMonths = 1,
    this.coveredByMonthYear,
    this.startDate,
    this.endDate,
  });

  bool get isPaid => status == PaymentStatus.paid;

  DateTime get effectiveStartDate {
    if (startDate != null) return startDate!;
    if (paidAt != null) return paidAt!;
    final parts = monthYear.split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      return DateTime(y, m, 1);
    }
    return DateTime.now();
  }

  DateTime get effectiveEndDate {
    if (endDate != null) return endDate!;
    return GymDateUtils.computeAnniversaryEndDate(effectiveStartDate, durationMonths);
  }

  String get formattedDateRange =>
      GymDateUtils.formatDateRange(effectiveStartDate, effectiveEndDate);

  static String methodLabel(PaymentMethod? method) {
    if (method == null) return 'Cash';
    return method.label;
  }
  bool get isCoveredInPackage => coveredByMonthYear != null && coveredByMonthYear!.isNotEmpty;

  PaymentRecord copyWith({
    String? id,
    String? customerId,
    String? monthYear,
    double? amount,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? paidAt,
    String? notes,
    String? transactionRef,
    int? durationMonths,
    String? coveredByMonthYear,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return PaymentRecord(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      monthYear: monthYear ?? this.monthYear,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      method: method ?? this.method,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      transactionRef: transactionRef ?? this.transactionRef,
      durationMonths: durationMonths ?? this.durationMonths,
      coveredByMonthYear: coveredByMonthYear ?? this.coveredByMonthYear,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'monthYear': monthYear,
      'amount': amount,
      'status': status.name,
      'method': method?.name,
      'paidAt': paidAt?.toIso8601String(),
      'notes': notes,
      'transactionRef': transactionRef,
      'durationMonths': durationMonths,
      'coveredByMonthYear': coveredByMonthYear,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      monthYear: map['monthYear'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      status: PaymentStatus.fromString(map['status'] as String?),
      method: map['method'] != null
          ? PaymentMethod.fromString(map['method'] as String?)
          : null,
      paidAt: map['paidAt'] != null
          ? DateTime.tryParse(map['paidAt'] as String)
          : null,
      notes: map['notes'] as String?,
      transactionRef: map['transactionRef'] as String?,
      durationMonths: (map['durationMonths'] as num?)?.toInt() ?? 1,
      coveredByMonthYear: map['coveredByMonthYear'] as String?,
      startDate: map['startDate'] != null
          ? DateTime.tryParse(map['startDate'] as String)
          : null,
      endDate: map['endDate'] != null
          ? DateTime.tryParse(map['endDate'] as String)
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory PaymentRecord.fromJson(String source) =>
      PaymentRecord.fromMap(json.decode(source) as Map<String, dynamic>);
}

class MemberPendingSummary {
  final Customer customer;
  final List<PaymentRecord> pendingRecords;
  final double totalPendingAmount;

  const MemberPendingSummary({
    required this.customer,
    required this.pendingRecords,
    required this.totalPendingAmount,
  });

  List<String> get pendingMonths =>
      pendingRecords.map((r) => r.monthYear).toList();
}

class MonthPendingItem {
  final Customer customer;
  final PaymentRecord payment;

  const MonthPendingItem({
    required this.customer,
    required this.payment,
  });
}

class MonthPendingGroup {
  final String monthKey;
  final List<MonthPendingItem> items;
  final double totalAmount;

  const MonthPendingGroup({
    required this.monthKey,
    required this.items,
    required this.totalAmount,
  });
}
