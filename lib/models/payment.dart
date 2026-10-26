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

/// An immutable owner-approved fee or credit change. Cash receipts stay separate.
class FeeChange {
  final String id, kind, reason, actor, actorId;
  final String? reversesChangeId;
  final double before, after;
  final DateTime at;
  const FeeChange({
    required this.id,
    required this.kind,
    required this.reason,
    required this.actor,
    required this.actorId,
    required this.before,
    required this.after,
    required this.at,
    this.reversesChangeId,
  });
  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind,
    'reason': reason,
    'actor': actor,
    'actorId': actorId,
    'before': before,
    'after': after,
    'at': at.toIso8601String(),
    if (reversesChangeId != null) 'reversesChangeId': reversesChangeId,
  };
  factory FeeChange.fromMap(Map<String, dynamic> m) => FeeChange(
    id: m['id'] as String,
    kind: m['kind'] as String,
    reason: m['reason'] as String,
    actor: m['actor'] as String,
    actorId: m['actorId'] as String,
    before: (m['before'] as num).toDouble(),
    after: (m['after'] as num).toDouble(),
    at: DateTime.parse(m['at'] as String),
    reversesChangeId: m['reversesChangeId'] as String?,
  );
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
  final bool isTaxEnabled;
  final String taxLabel;
  final double taxRatePercent;
  final bool isTaxInclusive;
  final double taxableAmount;
  final double taxAmount;

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
  final double? originalFee;
  final double creditApplied, creditUsed, creditRefunded;
  final List<FeeChange> feeChanges;
  double get availableCredit => double.parse(
    (amount - totalDue - creditUsed - creditRefunded)
        .clamp(0.0, double.infinity)
        .toStringAsFixed(2),
  );
  bool get hasFeeChanges => feeChanges.isNotEmpty;

  bool get canAdjustFee => balanceDue > 0 && !isCoveredInPackage;

  FeeChange? get latestFeeAdjustment {
    final removed = feeChanges.map((c) => c.reversesChangeId).toSet();
    for (final change in feeChanges.reversed) {
      if (change.kind == 'Fee adjusted' && !removed.contains(change.id)) {
        return change;
      }
    }
    return null;
  }

  String? get adjustmentRemovalBlockedReason {
    final change = latestFeeAdjustment;
    if (change == null) return null;
    if (creditApplied > 0 ||
        (creditUsed + creditRefunded > 0 &&
            change.before > amount - creditUsed - creditRefunded + 0.005)) {
      return 'This adjustment cannot be removed because credit has already been applied or money returned.';
    }
    return null;
  }

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
    this.isTaxEnabled = false,
    this.taxLabel = 'GST',
    this.taxRatePercent = 0.0,
    this.isTaxInclusive = true,
    this.taxableAmount = 0.0,
    this.taxAmount = 0.0,
    this.durationMonths = 1,
    this.coveredByMonthYear,
    this.startDate,
    this.endDate,
    this.isMembershipAgreement = false,
    this.isInferredAgreement = false,
    this.planType,
    this.originalFee,
    this.creditApplied = 0,
    this.creditUsed = 0,
    this.creditRefunded = 0,
    this.feeChanges = const [],
  });

  bool get isPaid => status == PaymentStatus.paid;

  /// Remaining fee still owed on a partially paid cycle.
  double get balanceDue => (totalDue - amount - creditApplied) > 0.005
      ? double.parse((totalDue - amount - creditApplied).toStringAsFixed(2))
      : 0.0;

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
    return GymDateUtils.computeAnniversaryEndDate(
      effectiveStartDate,
      durationMonths,
    );
  }

  String get formattedDateRange =>
      GymDateUtils.formatDateRange(effectiveStartDate, effectiveEndDate);

  static String methodLabel(PaymentMethod? method) {
    if (method == null) return 'Cash';
    return method.label;
  }

  bool get isCoveredInPackage =>
      coveredByMonthYear != null && coveredByMonthYear!.isNotEmpty;

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
    bool? isTaxEnabled,
    String? taxLabel,
    double? taxRatePercent,
    bool? isTaxInclusive,
    double? taxableAmount,
    double? taxAmount,
    int? durationMonths,
    String? coveredByMonthYear,
    DateTime? startDate,
    DateTime? endDate,
    bool? isMembershipAgreement,
    bool? isInferredAgreement,
    String? planType,
    double? originalFee,
    double? creditApplied,
    double? creditUsed,
    double? creditRefunded,
    List<FeeChange>? feeChanges,
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
      isTaxEnabled: isTaxEnabled ?? this.isTaxEnabled,
      taxLabel: taxLabel ?? this.taxLabel,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      taxableAmount: taxableAmount ?? this.taxableAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      durationMonths: durationMonths ?? this.durationMonths,
      coveredByMonthYear: coveredByMonthYear ?? this.coveredByMonthYear,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isMembershipAgreement:
          isMembershipAgreement ?? this.isMembershipAgreement,
      isInferredAgreement: isInferredAgreement ?? this.isInferredAgreement,
      planType: planType ?? this.planType,
      originalFee: originalFee ?? this.originalFee,
      creditApplied: creditApplied ?? this.creditApplied,
      creditUsed: creditUsed ?? this.creditUsed,
      creditRefunded: creditRefunded ?? this.creditRefunded,
      feeChanges: feeChanges ?? this.feeChanges,
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
      'isTaxEnabled': isTaxEnabled,
      'taxLabel': taxLabel,
      'taxRatePercent': taxRatePercent,
      'isTaxInclusive': isTaxInclusive,
      'taxableAmount': taxableAmount,
      'taxAmount': taxAmount,
      'durationMonths': durationMonths,
      'coveredByMonthYear': coveredByMonthYear,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isMembershipAgreement': isMembershipAgreement,
      'isInferredAgreement': isInferredAgreement,
      'planType': planType,
      'originalFee': originalFee,
      'creditApplied': creditApplied,
      'creditUsed': creditUsed,
      'creditRefunded': creditRefunded,
      'feeChanges': feeChanges.map((c) => c.toMap()).toList(),
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'] as String? ?? '',
      customerId: map['customerId'] as String? ?? '',
      monthYear: map['monthYear'] as String? ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      totalDue:
          (map['totalDue'] as num?)?.toDouble() ??
          (map['amount'] as num?)?.toDouble() ??
          0.0,
      status: PaymentStatus.fromString(map['status'] as String?),
      method: map['method'] != null
          ? PaymentMethod.fromString(map['method'] as String?)
          : null,
      paidAt: map['paidAt'] != null
          ? DateTime.tryParse(map['paidAt'] as String)
          : null,
      notes: map['notes'] as String?,
      transactionRef: map['transactionRef'] as String?,
      isTaxEnabled: map['isTaxEnabled'] as bool? ?? false,
      taxLabel: map['taxLabel'] as String? ?? 'GST',
      taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusive: map['isTaxInclusive'] as bool? ?? true,
      taxableAmount: (map['taxableAmount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (map['taxAmount'] as num?)?.toDouble() ?? 0.0,
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
      originalFee: (map['originalFee'] as num?)?.toDouble(),
      creditApplied: (map['creditApplied'] as num?)?.toDouble() ?? 0,
      creditUsed: (map['creditUsed'] as num?)?.toDouble() ?? 0,
      creditRefunded: (map['creditRefunded'] as num?)?.toDouble() ?? 0,
      feeChanges: List.unmodifiable(
        (map['feeChanges'] as List? ?? []).map(
          (v) => FeeChange.fromMap(Map<String, dynamic>.from(v as Map)),
        ),
      ),
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

  const MonthPendingItem({required this.customer, required this.payment});
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

// ==================== COLLECTION HISTORY MODELS ====================

class MemberCollectionSummary {
  final Customer customer;
  final List<PaymentRecord> paidRecords;
  final double totalCollectedAmount;

  const MemberCollectionSummary({
    required this.customer,
    required this.paidRecords,
    required this.totalCollectedAmount,
  });

  List<String> get paidMonths => paidRecords.map((r) => r.monthYear).toList();
}

class MonthCollectionItem {
  final Customer customer;
  final PaymentRecord payment;

  const MonthCollectionItem({required this.customer, required this.payment});
}

class MonthCollectionGroup {
  final String monthKey;
  final List<MonthCollectionItem> items;
  final double totalAmount;

  const MonthCollectionGroup({
    required this.monthKey,
    required this.items,
    required this.totalAmount,
  });
}
