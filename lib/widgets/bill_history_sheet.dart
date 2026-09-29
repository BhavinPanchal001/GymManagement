import 'package:flutter/material.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import 'bill_receipt_dialog.dart';

class BillHistorySheet extends StatelessWidget {
  final Customer customer;
  final String? paymentId;

  const BillHistorySheet({
    super.key,
    required this.customer,
    this.paymentId,
  });

  static Future<void> show(
    BuildContext context, {
    required Customer customer,
    String? paymentId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BillHistorySheet(customer: customer, paymentId: paymentId),
    );
  }

  /// Opens the receipt directly when a payment has a single bill, otherwise
  /// shows the full bill history sheet for that payment.
  static Future<void> showForPayment(
    BuildContext context, {
    required Customer customer,
    required PaymentRecord payment,
  }) async {
    final gym = GymService();
    if (gym.getAllBillsForPayment(payment.id).length > 1) {
      return show(context, customer: customer, paymentId: payment.id);
    }
    final bill = gym.getOrCreateBillForPayment(customer, payment);
    return BillReceiptDialog.show(context, bill: bill);
  }

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final currency = gym.settings.currencySymbol;

    return ListenableBuilder(
      listenable: gym,
      builder: (context, _) {
        final bills = paymentId == null
            ? gym.getAllBillsForCustomer(customer.id)
            : gym.getAllBillsForPayment(paymentId!);
        final title = paymentId == null
            ? 'Bills — ${customer.name}'
            : 'Bills for this payment';

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${bills.length}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (bills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No bills issued yet.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: bills.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _buildBillRow(context, bills[i], currency),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBillRow(BuildContext context, BillRecord bill, String currency) {
    final isCancelled = bill.status == 'CANCELLED';
    final statusColor = isCancelled ? AppColors.textMuted : AppColors.paid;
    final typeColor = switch (bill.billType) {
      'PARTIAL' => AppColors.pending,
      'BALANCE' => AppColors.secondary,
      _ => AppColors.primary,
    };

    return InkWell(
      onTap: () => BillReceiptDialog.show(context, bill: bill),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.billNumber,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${GymDateUtils.formatMonthYearKey(bill.monthYear)} · Issued ${GymDateUtils.formatShortDate(bill.issuedAt)}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  GymDateUtils.formatCurrency(bill.amount, symbol: currency),
                  style: TextStyle(
                    color: isCancelled ? AppColors.textMuted : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    decoration:
                        isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chip(bill.billType, typeColor),
                    const SizedBox(width: 5),
                    _chip(bill.status, statusColor),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
