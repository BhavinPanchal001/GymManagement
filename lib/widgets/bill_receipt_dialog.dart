import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../services/payment_receipt_pdf_service.dart';
import '../services/whatsapp_service.dart';
import '../services/phone_service.dart';
import '../screens/billing/bill_pdf_preview_screen.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class BillReceiptDialog extends StatefulWidget {
  final BillRecord bill;

  const BillReceiptDialog({
    super.key,
    required this.bill,
  });

  static Future<void> show(BuildContext context, {required BillRecord bill}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BillReceiptDialog(bill: bill),
    );
  }

  @override
  State<BillReceiptDialog> createState() => _BillReceiptDialogState();
}

class _BillReceiptDialogState extends State<BillReceiptDialog> {
  bool _isGeneratingPdf = false;

  BillRecord get bill {
    if (widget.bill.amount > 0) return widget.bill;
    final gym = GymService();
    if (widget.bill.paymentId.isNotEmpty) {
      final primary = gym.getBillForPayment(widget.bill.paymentId);
      if (primary != null && primary.amount > 0) return primary;
      final pay = gym.getPaymentById(widget.bill.paymentId);
      final cust = gym.getCustomerById(widget.bill.customerId);
      if (pay != null && pay.amount > 0 && cust != null) {
        return gym.getOrCreateBillForPayment(cust, pay);
      }
    }
    // Legacy bill without paymentId: resolve via the covering payment.
    final covering = gym.getPaymentCoveringMonth(widget.bill.customerId, widget.bill.monthYear);
    final cust = gym.getCustomerById(widget.bill.customerId);
    if (covering != null && cust != null) {
      final resolved = gym.getOrCreateBillForPayment(cust, covering);
      if (resolved.amount > 0) return resolved;
    }
    return widget.bill;
  }

  Future<void> _handlePrintPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      await PaymentReceiptPdfService().printReceipt(
        bill: bill,
        customer: GymService().getCustomerById(bill.customerId),
        settings: GymService().settings,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to print PDF bill: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _handleSharePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      await PaymentReceiptPdfService().shareReceiptPdf(
        bill: bill,
        customer: GymService().getCustomerById(bill.customerId),
        settings: GymService().settings,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share PDF bill: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _handlePreviewPdf() {
    BillPdfPreviewScreen.show(
      context,
      bill: bill,
      customer: GymService().getCustomerById(bill.customerId),
    );
  }

  IconData _getMethodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.gpay:
        return Icons.account_balance_wallet_rounded;
      case PaymentMethod.cash:
        return Icons.payments_rounded;
      case PaymentMethod.phonepe:
        return Icons.smartphone_rounded;
      case PaymentMethod.paytm:
        return Icons.qr_code_2_rounded;
      case PaymentMethod.upi:
        return Icons.flash_on_rounded;
      case PaymentMethod.card:
        return Icons.credit_card_rounded;
      case PaymentMethod.netBanking:
        return Icons.account_balance_rounded;
    }
  }

  Color _getMethodColor(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.gpay:
        return const Color(0xFF4285F4);
      case PaymentMethod.cash:
        return const Color(0xFF00E676);
      case PaymentMethod.phonepe:
        return const Color(0xFF673AB7);
      case PaymentMethod.paytm:
        return const Color(0xFF00B0FF);
      case PaymentMethod.upi:
        return const Color(0xFFFF9100);
      case PaymentMethod.card:
        return const Color(0xFFFF4081);
      case PaymentMethod.netBanking:
        return const Color(0xFF26A69A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = GymService().settings.currencySymbol;
    final formattedAmount = GymDateUtils.formatCurrency(bill.amount, symbol: currency);
    final formattedCycle = GymDateUtils.formatMonthYearKey(bill.monthYear);
    final formattedDate = GymDateUtils.formatDateTime(bill.paidAt);
    final planLabel = CustomerPlan.getLabel(bill.planType);
    final methodColor = _getMethodColor(bill.method);
    final isDark = AppColors.isDark;
    final attSummary = GymService().getMonthlyAttendanceSummary(bill.customerId, bill.monthYear);
    final presentDays = attSummary['present'] ?? 0;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.dynamicSurface(),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.dynamicSurfaceBorder(), width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle pill
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.dynamicSurfaceBorder(),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top Header: Title & Action Icons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.paid.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: AppColors.paid,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Payment Bill & Receipt',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          GymService().settings.gymName.trim().isNotEmpty
                              ? GymService().settings.gymName.trim()
                              : (bill.gymName.trim().isNotEmpty ? bill.gymName.trim() : 'Gym Management'),
                          style: TextStyle(
                            color: AppColors.dynamicTextSecondary(),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Full Screen PDF Preview Icon Button
                    IconButton(
                      icon: Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary, size: 20),
                      tooltip: 'View PDF Preview',
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      ),
                      onPressed: _handlePreviewPdf,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.dynamicSurfaceElevated(),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // The Receipt Card
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.paid.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Receipt Header Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.paid.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      border: Border(
                        bottom: BorderSide(color: AppColors.paid.withValues(alpha: 0.2)),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.dynamicSurfaceElevated(),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.dynamicSurfaceBorder()),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tag_rounded, size: 13, color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    bill.billNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Builder(builder: (context) {
                              final cancelled = bill.status == 'CANCELLED';
                              final chipColor = cancelled
                                  ? AppColors.absent
                                  : (bill.billType == 'BALANCE'
                                      ? AppColors.primary
                                      : (bill.billType == 'PARTIAL'
                                          ? AppColors.pending
                                          : AppColors.paid));
                              final chipLabel = cancelled
                                  ? 'CANCELLED'
                                  : (bill.billType == 'BALANCE'
                                      ? 'BALANCE PAID'
                                      : (bill.billType == 'PARTIAL' ? 'PARTIAL' : 'PAID'));
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: chipColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: chipColor, width: 1),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      cancelled ? Icons.cancel_rounded : Icons.check_circle_rounded,
                                      color: chipColor,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      chipLabel,
                                      style: TextStyle(
                                        color: chipColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Big Paid Amount
                        Text(
                          formattedAmount,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (bill.billType == 'PARTIAL' || bill.billType == 'BALANCE')
                          Builder(builder: (context) {
                            final pay = GymService().getPaymentById(bill.paymentId);
                            final label = bill.billType == 'PARTIAL'
                                ? 'Partial payment — balance ${GymDateUtils.formatCurrency(pay?.balanceDue ?? 0, symbol: currency)}'
                                : 'Balance payment for cycle ${bill.formattedValidityPeriod}';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: AppColors.pending,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }),
                        Text(
                          'Payment completed on $formattedDate',
                          style: TextStyle(
                            color: AppColors.dynamicTextSecondary(),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Receipt Body Details
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _buildReceiptRow(
                          icon: Icons.person_rounded,
                          iconColor: AppColors.primary,
                          label: 'Member Name',
                          value: bill.customerName,
                          bold: true,
                        ),
                        if (bill.customerPhone.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildReceiptRow(
                            icon: Icons.phone_rounded,
                            iconColor: const Color(0xFF00E5FF),
                            label: 'Contact Number',
                            valueWidget: InkWell(
                              onTap: () => PhoneService().makeCall(
                                bill.customerPhone,
                                context: context,
                                memberName: bill.customerName,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    bill.customerPhone,
                                    style: TextStyle(
                                      color: AppColors.dynamicTextPrimary(),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.call_rounded, size: 10, color: AppColors.primary),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Call',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildReceiptRow(
                          icon: Icons.fitness_center_rounded,
                          iconColor: const Color(0xFFFF9100),
                          label: 'Membership Plan',
                          value: bill.durationMonths > 1
                              ? '$planLabel (${bill.durationMonths}-Mo Package)'
                              : planLabel,
                        ),
                        const SizedBox(height: 12),
                        _buildReceiptRow(
                          icon: Icons.calendar_month_rounded,
                          iconColor: const Color(0xFFAB47BC),
                          label: 'Validity Period',
                          value: bill.formattedValidityPeriod,
                          bold: true,
                        ),
                        const SizedBox(height: 12),
                        _buildReceiptRow(
                          icon: Icons.event_repeat_rounded,
                          iconColor: const Color(0xFF448AFF),
                          label: 'Billing Cycle',
                          value: formattedCycle,
                        ),
                        if (presentDays > 0) ...[
                          const SizedBox(height: 12),
                          _buildReceiptRow(
                            icon: Icons.how_to_reg_rounded,
                            iconColor: AppColors.paid,
                            label: 'Attendance Linked',
                            valueWidget: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.paid.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.paid.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '✓ $presentDays Days Attended in $formattedCycle',
                                style: const TextStyle(
                                  color: AppColors.paid,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildReceiptRow(
                          icon: _getMethodIcon(bill.method),
                          iconColor: methodColor,
                          label: 'Payment Method',
                          valueWidget: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: methodColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: methodColor.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getMethodIcon(bill.method), size: 13, color: methodColor),
                                const SizedBox(width: 5),
                                Text(
                                  bill.method.label,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (bill.transactionRef != null && bill.transactionRef!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildReceiptRow(
                            icon: Icons.receipt_rounded,
                            iconColor: AppColors.dynamicTextMuted(),
                            label: 'Ref / Txn ID',
                            value: bill.transactionRef!.trim(),
                          ),
                        ],
                        if (bill.notes != null && bill.notes!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _buildReceiptRow(
                            icon: Icons.note_rounded,
                            iconColor: AppColors.dynamicTextMuted(),
                            label: 'Remarks',
                            value: bill.notes!.trim(),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Serrated / Perforated visual divider
                  Row(
                    children: List.generate(
                      24,
                      (index) => Expanded(
                        child: Container(
                          height: 1.5,
                          color: index % 2 == 0
                              ? AppColors.dynamicSurfaceBorder()
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),

                  // Quick PDF preview tap strip
                  InkWell(
                    onTap: _handlePreviewPdf,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, size: 15, color: AppColors.primary),
                          const SizedBox(width: 7),
                          Text(
                            'View Full Tax Invoice / Bill PDF',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // PRIMARY ACTIONS: Print / Download PDF & Share PDF
            Row(
              children: [
                // Print / Download PDF Button
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingPdf ? null : _handlePrintPdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.print_rounded, size: 18),
                      label: Text(
                        _isGeneratingPdf ? 'Preparing...' : 'Print / Save PDF',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Share PDF Bill Button
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isGeneratingPdf ? null : _handleSharePdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.paid,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share PDF Bill',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // SECONDARY ACTIONS: WhatsApp, Call, Copy
            Row(
              children: [
                // Send WhatsApp Button
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        WhatsAppService().sendBillReceipt(
                          context: context,
                          bill: bill,
                          currency: currency,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.whatsapp.withValues(alpha: 0.1),
                        foregroundColor: AppColors.whatsapp,
                        side: BorderSide(color: AppColors.whatsapp.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 16, color: AppColors.whatsapp),
                      label: const Text(
                        'WhatsApp Alert',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Call Member Button
                if (bill.customerPhone.isNotEmpty) ...[
                  SizedBox(
                    height: 44,
                    width: 46,
                    child: OutlinedButton(
                      onPressed: () {
                        PhoneService().makeCall(
                          bill.customerPhone,
                          context: context,
                          memberName: bill.customerName,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Icon(
                        Icons.call_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Copy Text Button
                SizedBox(
                  height: 44,
                  width: 46,
                  child: OutlinedButton(
                    onPressed: () {
                      final receiptText = WhatsAppService().buildBillReceiptMessage(
                        bill: bill,
                        currency: currency,
                      );
                      Clipboard.setData(ClipboardData(text: receiptText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bill receipt text copied to clipboard!'),
                          backgroundColor: AppColors.paid,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: AppColors.dynamicSurfaceBorder()),
                      backgroundColor: AppColors.dynamicSurfaceElevated(),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(Icons.copy_rounded, size: 17),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Close / Done button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: AppColors.dynamicTextSecondary(),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    Widget? valueWidget,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.dynamicTextSecondary(),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Flexible(
          child: valueWidget ??
              Text(
                value ?? '',
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
        ),
      ],
    );
  }
}
