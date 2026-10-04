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
  /// Amount actually paid so far.
  final double amount;
  /// Full fee for this cycle. Legacy records default to [amount] (fully paid).
  final double totalDue;
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
  final bool isMembershipAgreement;
  final bool isInferredAgreement;
  final String? planType;

  const PaymentRecord({
    required this.id,
    required this.customerId,
    required this.monthYear,
    required this.amount,
    this.totalDue = 0.0,
    this.status = PaymentStatus.pending,
    this.method,
    this.paidAt,
    this.notes,
    this.transactionRef,
    this.durationMonths = 1,
    this.coveredByMonthYear,
    this.startDate,
    this.endDate,
    this.isMembershipAgreement = false,
    this.isInferredAgreement = false,
    this.planType,
  });

  bool get isPaid => status == PaymentStatus.paid;

  /// Remaining fee still owed on a partially paid cycle.
  double get balanceDue => (totalDue - amount) > 0.005 ? totalDue - amount : 0.0;

  bool get isPartiallyPaid => isPaid && balanceDue > 0;

  /// Amount to show when a single figure is displayed: paid → collected, pending → fee.
  double get displayAmount => isPaid ? amount : totalDue;

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
    double? totalDue,
    PaymentStatus? status,
    PaymentMethod? method,
    DateTime? paidAt,
    String? notes,
    String? transactionRef,
    int? durationMonths,
    String? coveredByMonthYear,
    DateTime? startDate,
    DateTime? endDate,
    bool? isMembershipAgreement,
    bool? isInferredAgreement,
    String? planType,
  }) {
    return PaymentRecord(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      monthYear: monthYear ?? this.monthYear,
      amount: amount ?? this.amount,
      totalDue: totalDue ?? this.totalDue,
      status: status ?? this.status,
      method: method ?? this.method,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
      transactionRef: transactionRef ?? this.transactionRef,
      durationMonths: durationMonths ?? this.durationMonths,
      coveredByMonthYear: coveredByMonthYear ?? this.coveredByMonthYear,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isMembershipAgreement:
          isMembershipAgreement ?? this.isMembershipAgreement,
      isInferredAgreement: isInferredAgreement ?? this.isInferredAgreement,
      planType: planType ?? this.planType,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'monthYear': monthYear,
      'amount': amount,
      'totalDue': totalDue,
      'status': status.name,
      'method': method?.name,
      'paidAt': paidAt?.toIso8601String(),
      'notes': notes,
      'transactionRef': transactionRef,
      'durationMonths': durationMonths,
      'coveredByMonthYear': coveredByMonthYear,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isMembershipAgreement': isMembershipAgreement,
      'isInferredAgreement': isInferredAgreement,
      'planType': planType,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      monthYear: map['monthYear'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      totalDue: (map['totalDue'] as num?)?.toDouble() ??
          (map['amount'] as num?)?.toDouble() ?? 0.0,
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
      isMembershipAgreement: map['isMembershipAgreement'] as bool? ?? false,
      isInferredAgreement: map['isInferredAgreement'] as bool? ?? false,
      planType: map['planType'] as String?,
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

enum DueUrgency {
  /// Plan still running and not attended yet: can be paid by the plan end.
  upcoming,
  /// Plan still running but already attended: should be paid now.
  attendedInPlan,
  /// Plan period has ended and the fee is still unpaid.
  overdue,
}

class DueBucket {
  final List<PaymentRecord> records;
  final double amount;

  const DueBucket({this.records = const [], this.amount = 0});

  int get count => records.length;
  bool get isEmpty => records.isEmpty;

  DateTime? get earliestEndDate => records.isEmpty
      ? null
      : records
          .map((r) => r.effectiveEndDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
}

class MemberDueBreakdown {
  final DueBucket upcoming;
  final DueBucket attendedInPlan;
  final DueBucket overdue;

  const MemberDueBreakdown({
    this.upcoming = const DueBucket(),
    this.attendedInPlan = const DueBucket(),
    this.overdue = const DueBucket(),
  });

  DueBucket of(DueUrgency urgency) => switch (urgency) {
        DueUrgency.upcoming => upcoming,
        DueUrgency.attendedInPlan => attendedInPlan,
        DueUrgency.overdue => overdue,
      };

  int get totalCount => upcoming.count + attendedInPlan.count + overdue.count;
  double get totalAmount =>
      upcoming.amount + attendedInPlan.amount + overdue.amount;
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
