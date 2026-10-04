import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../models/bill.dart';
import '../services/gym_service.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import 'bill_history_sheet.dart';
import 'bill_receipt_dialog.dart';
import 'collect_balance_dialog.dart';
import 'animations/animated_success_dialog.dart';

class MarkPaymentDialog extends StatefulWidget {
  final Customer customer;
  final String monthYear;
  final PaymentRecord currentRecord;
  final bool isRenewal;

  const MarkPaymentDialog({
    super.key,
    required this.customer,
    required this.monthYear,
    required this.currentRecord,
    this.isRenewal = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Customer customer,
    required String monthYear,
    required PaymentRecord currentRecord,
    bool isRenewal = false,
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MarkPaymentDialog(
        customer: customer,
        monthYear: monthYear,
        currentRecord: currentRecord,
        isRenewal: isRenewal,
      ),
    );

    if (result is BillRecord && context.mounted) {
      await BillReceiptDialog.show(context, bill: result);
      return true;
    }
    return result == true;
  }

  static Future<bool?> showRenewal(
    BuildContext context, {
    required Customer customer,
  }) {
    final record = GymService().getRenewalPaymentRecord(customer);
    return show(
      context,
      customer: customer,
      monthYear: record.monthYear,
      currentRecord: record,
      isRenewal: true,
    );
  }

  @override
  State<MarkPaymentDialog> createState() => _MarkPaymentDialogState();
}

class _MarkPaymentDialogState extends State<MarkPaymentDialog> {
  late TextEditingController _amountController;
  TextEditingController? _legacyFeeController;
  late DateTime _initialReceivedDate;
  late TextEditingController _refController;
  late TextEditingController _notesController;
  late PaymentMethod _selectedMethod;
  late DateTime _selectedDate;
  late int _selectedDurationMonths;
  late double _totalDue;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isCurrentlyActive;
  late DateTime _lastExpiryDate;
  int _cycleModeIndex = 0; // 0: Fresh Start, 1: Continuous, 2: Custom
  bool _isLoading = false;
  final _operationId = GymService().newPaymentOperationId();
  bool _updateFutureRenewalDefault = false;

  PaymentRecord? get _overlappingPayment {
    return GymService().findOverlappingPaidPayment(
      customerId: widget.customer.id,
      startDate: _startDate,
      endDate: _endDate,
      excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
    );
  }

  final List<PaymentMethod> _methods = [
    PaymentMethod.gpay,
    PaymentMethod.cash,
    PaymentMethod.phonepe,
    PaymentMethod.paytm,
    PaymentMethod.upi,
    PaymentMethod.card,
    PaymentMethod.netBanking,
  ];

  @override
  void initState() {
    super.initState();
    final initialDuration = widget.currentRecord.durationMonths > 0
        ? widget.currentRecord.durationMonths
        : widget.customer.planDurationMonths;
    _selectedDurationMonths = initialDuration;

    _totalDue = widget.currentRecord.isPaid || widget.currentRecord.totalDue > 0
        ? widget.currentRecord.totalDue
        : GymService().settings.getPriceForDuration(widget.customer.planType, _selectedDurationMonths);
    if (widget.currentRecord.isPaid &&
        widget.currentRecord.amount > _totalDue + 0.005) {
      _legacyFeeController = TextEditingController(
        text: _totalDue.toStringAsFixed(2),
      );
    }
    final initialAmount = widget.currentRecord.isPaid
        ? widget.currentRecord.amount
        : _totalDue;

    _amountController = TextEditingController(
      text: initialAmount.toStringAsFixed(2),
    );
    _amountController.addListener(() => setState(() {}));
    _refController = TextEditingController(text: widget.currentRecord.transactionRef ?? '');
    _notesController = TextEditingController(text: widget.currentRecord.notes ?? '');
    _selectedMethod = widget.currentRecord.method ?? PaymentMethod.gpay;
    _selectedDate = widget.currentRecord.paidAt ?? DateTime.now();
    _initialReceivedDate = _selectedDate;

    final gymService = GymService();
    final hasPaid = gymService.hasPaidMembership(widget.customer);
    final latestExpiry = gymService.getCustomerExpiryDate(widget.customer);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _lastExpiryDate = latestExpiry;
    _isCurrentlyActive = hasPaid && !latestExpiry.isBefore(today);

    if (widget.currentRecord.isPaid || widget.currentRecord.startDate != null) {
      _startDate = widget.currentRecord.effectiveStartDate;
      _endDate = widget.currentRecord.effectiveEndDate;
      _cycleModeIndex = 2; // custom
    } else if (_isCurrentlyActive) {
      _startDate = latestExpiry.add(const Duration(days: 1));
      _endDate = GymDateUtils.computeAnniversaryEndDate(_startDate, _selectedDurationMonths);
      _cycleModeIndex = 1; // advance from expiry
    } else {
      final monthParts = widget.monthYear.split('-');
      if (monthParts.length == 2) {
        final y = int.tryParse(monthParts[0]) ?? today.year;
        final m = int.tryParse(monthParts[1]) ?? today.month;
        final monthStart = DateTime(y, m, 1);
        final isPastOrFuture = y != today.year || m != today.month;

        final attSummary = GymService().getMonthlyAttendanceSummary(widget.customer.id, widget.monthYear);
        final presentDays = attSummary['present'] ?? 0;
        final joinDay = DateTime(widget.customer.joinDate.year, widget.customer.joinDate.month, widget.customer.joinDate.day);
        final joinedBeforeToday = joinDay.isBefore(today);

        if (isPastOrFuture) {
          // If paying for a past or future specific month, anchor from that month's start
          _startDate = monthStart;
          _endDate = GymDateUtils.computeAnniversaryEndDate(_startDate, _selectedDurationMonths);
          _cycleModeIndex = 2;
        } else if (presentDays > 0 || joinedBeforeToday) {
          // Pay-later member settling current month with existing attendance or earlier start
          if (joinDay.year == y && joinDay.month == m && joinDay.isAfter(monthStart)) {
            _startDate = joinDay;
          } else {
            _startDate = monthStart;
          }
          _endDate = GymDateUtils.computeAnniversaryEndDate(_startDate, _selectedDurationMonths);
          _cycleModeIndex = 2;
        } else {
          _startDate = today;
          _endDate = GymDateUtils.computeAnniversaryEndDate(_startDate, _selectedDurationMonths);
          _cycleModeIndex = 0; // fresh start from today
        }
      } else {
        _startDate = today;
        _endDate = GymDateUtils.computeAnniversaryEndDate(_startDate, _selectedDurationMonths);
        _cycleModeIndex = 0; // fresh start from today
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _legacyFeeController?.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(DateTime.now()) ? DateTime.now() : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      final newEnd = GymDateUtils.computeAnniversaryEndDate(picked, _selectedDurationMonths);
      final overlapping = GymService().findOverlappingPaidPayment(
        customerId: widget.customer.id,
        startDate: picked,
        endDate: newEnd,
        excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
      );
      setState(() {
        _startDate = picked;
        _endDate = newEnd;
        _cycleModeIndex = 2;
      });
      if (overlapping != null && mounted) {
        _showError(
          'Warning: Selected range overlaps with paid membership (${overlapping.formattedDateRange}).',
        );
      }
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isAfter(_startDate) ? _endDate : _startDate.add(const Duration(days: 1)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      final overlapping = GymService().findOverlappingPaidPayment(
        customerId: widget.customer.id,
        startDate: _startDate,
        endDate: picked,
        excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
      );
      setState(() {
        _endDate = picked;
        _cycleModeIndex = 2;
      });
      if (overlapping != null && mounted) {
        _showError(
          'Warning: Selected range overlaps with paid membership (${overlapping.formattedDateRange}).',
        );
      }
    }
  }

  Future<void> _submitPayment() async {
    if (_isLoading) return;
    final overlapping = _overlappingPayment;
    if (overlapping != null) {
      _showError(
        'Cannot save payment: the selected period (${GymDateUtils.formatDateRange(_startDate, _endDate)}) '
        'overlaps with an already paid membership (${overlapping.formattedDateRange}).',
      );
      return;
    }
    final amount = double.tryParse(_amountController.text.trim());
    final isUpdate = widget.currentRecord.isPaid;
    final unchangedMoney =
        isUpdate &&
        amount == widget.currentRecord.amount &&
        _totalDue == widget.currentRecord.totalDue;
    if (amount == null ||
        !amount.isFinite ||
        (!unchangedMoney && (amount <= 0 || amount > _totalDue + 0.005))) {
      _showError('Enter a positive amount no greater than the membership fee.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bill = isUpdate
        ? await GymService().updatePayment(
            paymentId: widget.currentRecord.id,
            amount: amount,
            totalDue: _totalDue,
            method: _selectedMethod,
            paidAt: _selectedDate == _initialReceivedDate
                ? widget.currentRecord.paidAt : _selectedDate,
            startDate: _startDate,
            endDate: _endDate,
            durationMonths: _selectedDurationMonths,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
            transactionRef: _refController.text.trim().isNotEmpty
                  ? _refController.text.trim() : null,
          )
        : await GymService().markPaymentAsPaid(
            customerId: widget.customer.id,
            monthYear: widget.monthYear,
            method: _selectedMethod,
            amount: amount,
            totalDue: _totalDue,
            durationMonths: _selectedDurationMonths,
            startDate: _startDate,
            endDate: _endDate,
            notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
            transactionRef: _refController.text.trim().isNotEmpty ? _refController.text.trim() : null,
            paidAt: _selectedDate,
            operationId: _operationId,
            agreementId: widget.currentRecord.isMembershipAgreement
                ? widget.currentRecord.id : null,
            updateFutureRenewalDefault: _updateFutureRenewalDefault,
          );

      if (mounted) {
        await AnimatedSuccessDialog.show(
          context,
          title: isUpdate ? 'Payment Updated!' : 'Payment Recorded!',
          message: '${widget.customer.name} • ${widget.monthYear}',
          autoDismiss: const Duration(milliseconds: 900),
        );
        if (mounted) {
          Navigator.pop(context, bill);
        }
      }
    } catch (error) {
      if (mounted) {
        _showError(
          error is ArgumentError
              ? error.message.toString()
              : 'Could not save the payment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _collectBalance() async {
    if (_isLoading) return;
    final current = GymService().getPaymentById(widget.currentRecord.id);
    if (current == null || current.balanceDue <= 0) return;
    final receipt = await CollectBalanceDialog.show(context, current);
    if (receipt != null && mounted) Navigator.pop(context, receipt);
  }

  Future<void> _revertPayment() async {
    if (_isLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this payment?'),
        content: const Text(
          'All receipts for this payment will be marked cancelled and removed from collected totals. Membership coverage will be removed. This does not record a cash refund.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep payment'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await GymService().revertPayment(widget.currentRecord.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        _showError('Could not cancel the payment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final isAlreadyPaid = widget.currentRecord.isPaid;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle pill
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAlreadyPaid ? 'Update Payment' : widget.isRenewal
                            ? 'Renew Membership'
                            : 'Record Payment',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Builder(builder: (context) {
                        final summary = GymService().getMonthlyAttendanceSummary(widget.customer.id, widget.monthYear);
                        final attendedDays = summary['present'] ?? 0;
                        return Text(
                          '${widget.customer.name} • ${GymDateUtils.formatMonthYearKey(widget.monthYear)} ($attendedDays days attended)',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10,
                    vertical: 5),
                  decoration: BoxDecoration(
                    color: isAlreadyPaid
                        ? AppColors.paid.withValues(alpha: 0.15)
                        : AppColors.pending.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAlreadyPaid ? AppColors.paid : AppColors.pending,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isAlreadyPaid ? 'PAID' : 'PENDING',
                    style: TextStyle(
                      color: isAlreadyPaid ? AppColors.paid : AppColors.pending,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            // Date Validity Period Card & Cycle Mode Toggles
            _buildValidityDateSection(),
            const SizedBox(height: 14),

            // Package & Duration Combo Selector
            _buildDurationPackageSelector(currency),
            const SizedBox(height: 18),
            if (!isAlreadyPaid &&
                _selectedDurationMonths != widget.customer.planDurationMonths) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _updateFutureRenewalDefault,
                onChanged: (value) => setState(
                  () => _updateFutureRenewalDefault = value ?? false,
                ),
                title: const Text('Use this package for future renewals'),
                subtitle: Text(
                  'The current default remains ${widget.customer.durationLabel} unless selected.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
            ],

            // Total due (plan fee / package price, read-only)
            Row(
              children: [
                Text(
                  'Total Due',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  GymDateUtils.formatCurrency(_totalDue, symbol: currency),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_legacyFeeController != null) ...[
              TextField(
                controller: _legacyFeeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Correct membership fee (optional)',
                  helperText:
                      'Reference edits keep the existing fee and received amount.',
                ),
                onChanged: (value) => setState(() {
                  _totalDue = double.tryParse(value.trim()) ?? double.nan;
                }),
              ),
              const SizedBox(height: 10),
            ],

            // Amount field
            Text(
              isAlreadyPaid ? 'Total received for this membership' : 'Amount received now',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8, top: 12),
                  child: Text(
                    currency,
                    style: TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                hintText: 'Enter amount',
              ),
            ),
            Builder(builder: (context) {
              final amountNow = double.tryParse(_amountController.text.trim()) ?? 0;
              final balance = _totalDue - amountNow;
              if (balance <= 0.005) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Text(
                      'Balance: ${GymDateUtils.formatCurrency(balance, symbol: currency)}',
                      style: TextStyle(color: AppColors.pending, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.pending.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.pending.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Will be recorded as PARTIAL payment',
                        style: TextStyle(color: AppColors.pending, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),

            // Payment Mode selector
            Text(
              'Payment Method',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _methods.map((method) {
                final isSelected = _selectedMethod == method;
                final color = _getMethodColor(method);
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMethod = method;
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.2) : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? color : AppColors.surfaceBorder,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getMethodIcon(method),
                          color: isSelected ? color : AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          method.label,
                          style: TextStyle(
                            color: isSelected ? (AppColors.isDark ? Colors.white : color) : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Date Paid
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAlreadyPaid ? 'Original payment date' : 'Payment received date',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.surfaceBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Flexible(child: Text(
                                GymDateUtils.formatDate(_selectedDate),
                                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ref / Txn ID (Optional)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _refController,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'e.g. UPI-9821...',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes
            Text(
              'Remarks / Notes',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'e.g. Paid in full at front counter',
              ),
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        final overlapping = _overlappingPayment;
                        if (overlapping != null) {
                          _showError(
                            'Cannot record payment: the selected period (${GymDateUtils.formatDateRange(_startDate, _endDate)}) overlaps with an already paid membership (${overlapping.formattedDateRange}).',
                          );
                          return;
                        }
                        _submitPayment();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _overlappingPayment != null ? AppColors.absent : AppColors.primary,
                  foregroundColor: AppColors.primaryOn,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryOn),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_overlappingPayment != null ? Icons.block_rounded : Icons.check_circle_rounded, size: 20),
                          const SizedBox(width: 8),
                          Flexible(child: Text(
                            _overlappingPayment != null
                                ? 'Dates Overlap With Paid Plan'
                                : (isAlreadyPaid
                                    ? 'Update Payment Record'
                                    : ((double.tryParse(_amountController.text.trim()) ?? 0) + 0.005 < _totalDue
                                        ? 'Record Partial Payment'
                                        : 'Confirm & Mark as Paid')),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          )),
                        ],
                      ),
              ),
            ),

            if (!isAlreadyPaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final currentAmount = double.tryParse(_amountController.text.trim()) ?? widget.currentRecord.amount;
                    WhatsAppService().showReminderSheet(
                      context: context,
                      customer: widget.customer,
                      monthYear: widget.monthYear,
                      amount: currentAmount,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.whatsapp.withValues(alpha: 0.1),
                    foregroundColor: AppColors.whatsapp,
                    side: BorderSide(color: AppColors.whatsapp.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: AppColors.whatsapp),
                  label: const Text(
                    'Send WhatsApp Fee Reminder',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.whatsapp,
                    ),
                  ),
                ),
              ),
            ],

            if (isAlreadyPaid) ...[
              if (widget.currentRecord.balanceDue > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _collectBalance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pending,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 20),
                    label: Text(
                      'Collect Balance ${GymDateUtils.formatCurrency(widget.currentRecord.balanceDue, symbol: currency)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    BillHistorySheet.showForPayment(
                      context,
                      customer: widget.customer,
                      payment: widget.currentRecord,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.paid.withValues(alpha: 0.1),
                    foregroundColor: AppColors.paid,
                    side: BorderSide(color: AppColors.paid.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.paid),
                  label: const Text(
                    'View Payment Bill / Receipt',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.paid,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _revertPayment,
                  icon: const Icon(Icons.undo_rounded, color: AppColors.absent, size: 18),
                  label: const Text(
                    'Revert to Pending',
                    style: TextStyle(color: AppColors.absent, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildValidityDateSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active vs Expired Status Banner
          if (_isCurrentlyActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.paid.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.paid.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, color: AppColors.paid, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Active until ${GymDateUtils.formatDate(_lastExpiryDate)} • Advance Renewal',
                      style: TextStyle(
                        color: AppColors.paid,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            // Expired / Break member -> Quick Toggles
            Text(
              'Renewal Start Date (Break or Late Payment):',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Toggle 1: Fresh Start
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final newEnd = GymDateUtils.computeAnniversaryEndDate(today, _selectedDurationMonths);
                      final overlapping = GymService().findOverlappingPaidPayment(
                        customerId: widget.customer.id,
                        startDate: today,
                        endDate: newEnd,
                        excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
                      );
                      setState(() {
                        _cycleModeIndex = 0;
                        _startDate = today;
                        _endDate = newEnd;
                      });
                      if (overlapping != null && mounted) {
                        _showError(
                          'Warning: Fresh start date overlaps with paid membership (${overlapping.formattedDateRange}).',
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _cycleModeIndex == 0
                            ? AppColors.paid.withValues(alpha: 0.18)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _cycleModeIndex == 0 ? AppColors.paid : AppColors.surfaceBorder,
                          width: _cycleModeIndex == 0 ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.fiber_new_rounded,
                                size: 15,
                                color: _cycleModeIndex == 0 ? AppColors.paid : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Fresh Start',
                                style: TextStyle(
                                  color: _cycleModeIndex == 0 ? AppColors.paid : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'From Today (${GymDateUtils.formatShortDate(today)})',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Toggle 2: Continue from Last Expiry
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final nextStart = DateTime(
                        _lastExpiryDate.year,
                        _lastExpiryDate.month,
                        _lastExpiryDate.day + 1,
                      );
                      final newEnd = GymDateUtils.computeAnniversaryEndDate(nextStart, _selectedDurationMonths);
                      final overlapping = GymService().findOverlappingPaidPayment(
                        customerId: widget.customer.id,
                        startDate: nextStart,
                        endDate: newEnd,
                        excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
                      );
                      setState(() {
                        _cycleModeIndex = 1;
                        _startDate = nextStart;
                        _endDate = newEnd;
                      });
                      if (overlapping != null && mounted) {
                        _showError(
                          'Warning: This range overlaps with paid membership (${overlapping.formattedDateRange}).',
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _cycleModeIndex == 1
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _cycleModeIndex == 1 ? AppColors.primary : AppColors.surfaceBorder,
                          width: _cycleModeIndex == 1 ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.replay_rounded,
                                size: 14,
                                color: _cycleModeIndex == 1 ? AppColors.primary : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Continuous',
                                style: TextStyle(
                                  color: _cycleModeIndex == 1 ? AppColors.primary : AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'From ${GymDateUtils.formatShortDate(_lastExpiryDate.add(const Duration(days: 1)))}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Exact Start & End Date Pickers Row
          Builder(builder: (context) {
            final overlapping = _overlappingPayment;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickStartDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: overlapping != null ? AppColors.absent : AppColors.surfaceBorder,
                              width: overlapping != null ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(
                                    'START DATE',
                                    style: TextStyle(
                                      color: overlapping != null ? AppColors.absent : AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  )),
                                  Icon(Icons.edit_calendar_rounded, size: 13, color: overlapping != null ? AppColors.absent : AppColors.primary),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                GymDateUtils.formatDate(_startDate),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.textSecondary),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickEndDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: overlapping != null ? AppColors.absent : AppColors.surfaceBorder,
                              width: overlapping != null ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(
                                    'EXPIRY DATE',
                                    style: TextStyle(
                                      color: overlapping != null ? AppColors.absent : AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  )),
                                  Icon(Icons.edit_calendar_rounded, size: 13, color: overlapping != null ? AppColors.absent : AppColors.primary),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                GymDateUtils.formatDate(_endDate),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (overlapping != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.absent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.absent.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.absent, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Overlaps with paid plan (${overlapping.formattedDateRange})',
                                style: const TextStyle(
                                  color: AppColors.absent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This member has already paid for dates within this period. Please select a non-overlapping start date.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            final nextStart = DateTime(
                              overlapping.effectiveEndDate.year,
                              overlapping.effectiveEndDate.month,
                              overlapping.effectiveEndDate.day + 1,
                            );
                            setState(() {
                              _startDate = nextStart;
                              _endDate = GymDateUtils.computeAnniversaryEndDate(nextStart, _selectedDurationMonths);
                              _cycleModeIndex = 2;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_fix_high_rounded, size: 14, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Start after paid plan (${GymDateUtils.formatShortDate(DateTime(overlapping.effectiveEndDate.year, overlapping.effectiveEndDate.month, overlapping.effectiveEndDate.day + 1))})',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Plan Validity: ${GymDateUtils.formatDateRange(_startDate, _endDate)} ($_selectedDurationMonths ${_selectedDurationMonths == 1 ? "Month" : "Months"})',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDurationPackageSelector(String currency) {
    final settings = GymService().settings;
    final packages = settings.getPackagesForPlan(widget.customer.planType);

    Color accentColor;
    switch (widget.customer.planType) {
      case CustomerPlan.personalTraining:
        accentColor = AppColors.secondary;
        break;
      case CustomerPlan.personalTrainingDiet:
        accentColor = const Color(0xFFFF9100);
        break;
      case CustomerPlan.normal:
      default:
        accentColor = AppColors.primary;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Package Duration',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13,
                fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                CustomerPlan.getShortLabel(widget.customer.planType),
                style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            Text(
              '$_selectedDurationMonths ${_selectedDurationMonths == 1 ? "Month" : "Months"}',
              style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: packages.map((pkg) {
              final isSelected = _selectedDurationMonths == pkg.months;
              final payablePrice = settings.totalForConfiguredPrice(pkg.price);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    final newEnd = GymDateUtils.computeAnniversaryEndDate(_startDate, pkg.months);
                    final overlapping = GymService().findOverlappingPaidPayment(
                      customerId: widget.customer.id,
                      startDate: _startDate,
                      endDate: newEnd,
                      excludePaymentId: widget.currentRecord.isPaid ? widget.currentRecord.id : null,
                    );
                    setState(() {
                      _selectedDurationMonths = pkg.months;
                      _totalDue = payablePrice;
                      _amountController.text = payablePrice.toStringAsFixed(2);
                      _endDate = newEnd;
                    });
                    if (overlapping != null && mounted) {
                      _showError(
                        'Warning: This package duration overlaps with paid membership (${overlapping.formattedDateRange}).',
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? accentColor.withValues(alpha: 0.18) : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? accentColor : AppColors.surfaceBorder,
                        width: isSelected ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkg.title,
                          style: TextStyle(
                            color: isSelected ? (AppColors.isDark ? Colors.white : accentColor) : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$currency${payablePrice.toStringAsFixed(payablePrice.truncateToDouble() == payablePrice ? 0 : 2)}',
                          style: TextStyle(
                            color: isSelected ? accentColor : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedDurationMonths > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.paid.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.paid.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.date_range_rounded, color: AppColors.paid, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Covers ${_getCoveragePeriodPreview()} • Next bill in ${_getNextBillMonthPreview()}',
                    style: TextStyle(color: AppColors.paid, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _getCoveragePeriodPreview() {
    final parts = widget.monthYear.split('-');
    final startYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    final startMonth = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;
    final startDate = DateTime(startYear, startMonth, 1);
    final endDate = DateTime(startYear, startMonth + _selectedDurationMonths - 1, 1);
    return "${GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(startDate))} to ${GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(endDate))}";
  }

  String _getNextBillMonthPreview() {
    final parts = widget.monthYear.split('-');
    final startYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    final startMonth = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;
    final nextDate = DateTime(startYear, startMonth + _selectedDurationMonths, 1);
    return GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(nextDate));
  }
}
