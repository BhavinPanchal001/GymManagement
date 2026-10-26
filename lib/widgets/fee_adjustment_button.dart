import 'package:flutter/material.dart';

import '../models/payment.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import 'fee_adjustment_sheet.dart';

/// A direct shortcut for an existing membership period, never a placeholder.
class FeeAdjustmentButton extends StatelessWidget {
  final PaymentRecord payment;
  final VoidCallback? onChanged;
  final bool enabled;
  final bool expand;
  final bool compact;
  final double topSpacing;
  final double bottomSpacing;

  const FeeAdjustmentButton({
    super.key,
    required this.payment,
    this.onChanged,
    this.enabled = true,
    this.expand = false,
    this.compact = false,
    this.topSpacing = 0,
    this.bottomSpacing = 0,
  });

  PaymentRecord? _currentPeriod() {
    final gym = GymService();
    final saved = gym.getPaymentById(payment.id);
    if (saved != null) return saved;
    for (final period in gym.feePeriods(payment.customerId)) {
      if (period.id == payment.id) return period;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final period = _currentPeriod();
    if (period == null || (!period.canAdjustFee && !period.hasFeeChanges)) {
      return const SizedBox.shrink();
    }
    final viewing = period.hasFeeChanges;
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: bottomSpacing),
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: FilledButton.icon(
          onPressed: !enabled
              ? null
              : () async {
                  final changed = await FeeAdjustmentSheet.show(
                    context,
                    period,
                  );
                  if (!context.mounted) return;
                  if (changed == true ||
                      _currentPeriod()?.toJson() != period.toJson()) {
                    onChanged?.call();
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: viewing
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.primary,
            foregroundColor: viewing ? AppColors.primary : AppColors.primaryOn,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
            minimumSize: Size(0, compact ? 36 : 44),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 8 : 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: TextStyle(
              fontSize: compact ? 12 : 14,
              fontWeight: compact ? FontWeight.w700 : FontWeight.w800,
            ),
          ),
          icon: Icon(
            viewing ? Icons.history_rounded : Icons.price_change_outlined,
            size: compact ? 16 : 20,
          ),
          label: Text(viewing ? 'View adjustment' : 'Adjust fee'),
        ),
      ),
    );
  }
}
