import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

enum CalendarPaymentStatus {
  paid('Paid', Icons.verified_outlined),
  partial('Part paid', Icons.pending_outlined),
  due('Due', Icons.error_outline_rounded),
  none('No payment period', Icons.remove_circle_outline_rounded);

  const CalendarPaymentStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  Color get color => switch (this) {
    CalendarPaymentStatus.paid => AppColors.paid,
    CalendarPaymentStatus.partial => AppColors.pending,
    CalendarPaymentStatus.due => AppColors.absent,
    CalendarPaymentStatus.none => AppColors.textMuted,
  };
}

/// A date belongs to the whole membership fee period; payments are not divided
/// into paid and unpaid days when only part of a period's fee was collected.
CalendarPaymentStatus calendarPaymentStatus({
  required DateTime date,
  required DateTime joinDate,
  required Iterable<PaymentRecord> periods,
}) {
  final key = GymDateUtils.toDateKey(date);
  if (key.compareTo(GymDateUtils.toDateKey(joinDate)) < 0) {
    return CalendarPaymentStatus.none;
  }
  var result = CalendarPaymentStatus.none;
  for (final period in periods) {
    if (key.compareTo(GymDateUtils.toDateKey(period.effectiveStartDate)) < 0 ||
        key.compareTo(GymDateUtils.toDateKey(period.effectiveEndDate)) > 0) {
      continue;
    }
    if (period.balanceDue == 0) return CalendarPaymentStatus.paid;
    if (period.amount + period.creditApplied > 0) {
      result = CalendarPaymentStatus.partial;
    } else if (result == CalendarPaymentStatus.none) {
      result = CalendarPaymentStatus.due;
    }
  }
  return result;
}

class CalendarPaymentIndicator extends StatelessWidget {
  const CalendarPaymentIndicator({
    super.key,
    required this.status,
    this.dateLabel,
    this.showLabel = false,
  });

  final CalendarPaymentStatus status;
  final String? dateLabel;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final label = dateLabel == null
        ? status.label
        : '$dateLabel: ${status.label}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(status.icon, size: 14, color: status.color),
              if (showLabel) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    status.label,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
