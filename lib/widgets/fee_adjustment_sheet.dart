import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';

/// Owner-approved changes to a single agreed membership period.
class FeeAdjustmentSheet extends StatefulWidget {
  final PaymentRecord payment;
  const FeeAdjustmentSheet({super.key, required this.payment});

  static Future<bool?> show(BuildContext context, PaymentRecord payment) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        builder: (_) => FeeAdjustmentSheet(payment: payment),
      );

  @override
  State<FeeAdjustmentSheet> createState() => _FeeAdjustmentSheetState();
}

class _FeeAdjustmentSheetState extends State<FeeAdjustmentSheet> {
  final _fee = TextEditingController(), _reason = TextEditingController();
  final _creditAmount = TextEditingController(),
      _refundReason = TextEditingController();
  PaymentRecord? _target;
  PaymentMethod _method = PaymentMethod.cash;
  late PaymentRecord _expected;
  bool _busy = false, _changed = false;
  late bool _editingFee;
  int? _creditAction;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expected =
        GymService().getPaymentById(widget.payment.id) ?? widget.payment;
    _editingFee = !_expected.hasFeeChanges && _expected.canAdjustFee;
    _fee.text = _expected.totalDue.toStringAsFixed(2);
    _creditAmount.text = _expected.availableCredit.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _fee.dispose();
    _reason.dispose();
    _creditAmount.dispose();
    _refundReason.dispose();
    super.dispose();
  }

  String money(double value) => GymDateUtils.formatCurrency(
    value,
    symbol: GymService().settings.currencySymbol,
  );

  Future<void> _run(String preview, Future<void> Function(String) save) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review change'),
        content: Text(preview),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busy = false);
      return;
    }
    try {
      await save(GymService().newPaymentOperationId());
      if (!mounted) return;
      setState(() {
        _expected = GymService().getPaymentById(_expected.id)!;
        _fee.text = _expected.totalDue.toStringAsFixed(2);
        _creditAmount.text = _expected.availableCredit.toStringAsFixed(2);
        _target = null;
        _editingFee = false;
        _creditAction = null;
        _reason.clear();
        _refundReason.clear();
        _changed = true;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e
              .toString()
              .replaceFirst('Invalid argument(s): ', '')
              .replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _adjust() {
    if (!_expected.canAdjustFee) {
      setState(() => _error = 'This period has no outstanding balance.');
      return;
    }
    final amount = double.tryParse(_fee.text.trim());
    if (amount == null ||
        !amount.isFinite ||
        !(amount * 100).isFinite ||
        amount < 0 ||
        (amount * 100 - (amount * 100).round()).abs() > 0.00001 ||
        _reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a valid revised fee and a reason.');
      return;
    }
    final extra =
        (_expected.amount -
                amount -
                _expected.creditUsed -
                _expected.creditRefunded)
            .clamp(0.0, double.infinity)
            .toDouble();
    _run(
      'Change this period from ${money(_expected.totalDue)} to ${money(amount)}?\n'
      'Reason: ${_reason.text.trim()}\n\n'
      'Received money and membership dates will stay unchanged.'
      '${extra > 0 ? '\n${money(extra)} will be kept as member credit. You can apply it or record money returned below.' : ''}',
      (id) => GymService().adjustMembershipFee(
        expected: _expected,
        revisedFee: amount,
        reason: _reason.text,
        operationId: id,
      ),
    );
  }

  void _removeAdjustment() {
    final change = _expected.latestFeeAdjustment;
    if (change == null) return;
    final blocked = _expected.adjustmentRemovalBlockedReason;
    if (blocked != null) {
      setState(() => _error = blocked);
      return;
    }
    final balance = (change.before - _expected.amount - _expected.creditApplied)
        .clamp(0.0, double.infinity)
        .toDouble();
    _run(
      'Remove this adjustment and restore the fee from '
      '${money(_expected.totalDue)} to ${money(change.before)}?\n\n'
      'The remaining balance will be ${money(balance)}. '
      'Money received, membership dates and receipts will stay unchanged. '
      'The removal will remain in adjustment history.',
      (id) => GymService().removeMembershipFeeAdjustment(
        expected: _expected,
        adjustmentId: change.id,
        operationId: id,
      ),
    );
  }

  bool _validCreditAmount(double? amount) =>
      amount != null &&
      amount.isFinite &&
      amount > 0 &&
      amount <= _expected.availableCredit &&
      (amount * 100 - (amount * 100).round()).abs() <= 0.00001;

  Widget _card(Widget child, {Color? accent}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: accent == null
          ? AppColors.surfaceElevated
          : accent.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: accent?.withValues(alpha: 0.3) ?? AppColors.surfaceBorder,
      ),
    ),
    child: child,
  );

  InputDecoration _input(String label, {String? hint, String? prefix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );

  ButtonStyle get _primaryButton => FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.primaryOn,
    minimumSize: const Size(double.infinity, 46),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );

  Widget _metric(String label, double amount, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 5),
      Text(
        money(amount),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    ],
  );

  Widget _summary() {
    final settled = _expected.balanceDue == 0;
    final statusColor = settled
        ? AppColors.dynamicPaid
        : AppColors.dynamicPending;
    final original = _expected.originalFee ?? _expected.totalDue;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current fee',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money(_expected.totalDue),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Original fee: ${money(original)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  settled ? 'Settled' : 'Balance due',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.surfaceBorder),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _metric('Money received', _expected.amount)),
              const SizedBox(width: 12),
              Expanded(
                child: _metric(
                  'Still owed',
                  _expected.balanceDue,
                  color: statusColor,
                ),
              ),
            ],
          ),
          if (_expected.creditApplied > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Credit applied here: ${money(_expected.creditApplied)}',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editFee() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Update this period',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _fee,
          enabled: !_busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _input(
            'Revised fee',
            prefix: '${GymService().settings.currencySymbol} ',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _reason,
          enabled: !_busy,
          maxLength: 500,
          maxLines: 2,
          decoration: _input(
            'Reason for adjustment',
            hint: 'e.g. Approved half-month discount',
          ),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: _busy ? null : _adjust,
          style: _primaryButton,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Review fee adjustment'),
        ),
      ],
    ),
  );

  Widget _creditChoice(int index, String label, IconData icon) {
    final selected = _creditAction == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: Material(
          color: selected ? AppColors.primary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy
                ? null
                : () => setState(() {
                    _creditAction = selected ? null : index;
                    _error = null;
                  }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.surfaceBorder,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? AppColors.primaryOn : AppColors.primary,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primaryOn
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _applyCredit() {
    final target = _target, amount = double.tryParse(_creditAmount.text);
    if (target == null ||
        !_validCreditAmount(amount) ||
        amount! > target.balanceDue) {
      setState(
        () => _error =
            'Choose a period and a positive amount within its balance and available credit, with up to two decimals.',
      );
      return;
    }
    _run(
      'Apply ${money(amount)} of existing credit to ${target.formattedDateRange}?\nNo new money will be recorded.',
      (id) => GymService().applyMemberCredit(
        expectedSource: _expected,
        expectedTarget: target,
        amount: amount,
        operationId: id,
      ),
    );
  }

  void _recordRefund() {
    final amount = double.tryParse(_creditAmount.text);
    if (!_validCreditAmount(amount) || _refundReason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a valid amount and return reason.');
      return;
    }
    _run(
      'Confirm you have already returned ${money(amount!)} by ${_method.label}.\n'
      'This records money returned and reduces net collections. It does not send a bank payment.',
      (id) => GymService().refundMemberCredit(
        expected: _expected,
        amount: amount,
        method: _method,
        reason: _refundReason.text,
        operationId: id,
      ),
    );
  }

  Widget _creditCard() {
    final gym = GymService();
    final targets = gym
        .feePeriods(_expected.customerId)
        .where((p) => p.id != _expected.id && p.balanceDue > 0)
        .toList();
    final next = gym.creditRenewalPeriod(_expected.customerId);
    if (!targets.any((p) => p.effectiveStartDate == next.effectiveStartDate)) {
      targets.add(next);
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available member credit',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      money(_expected.availableCredit),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Keep it for later, or choose an action below.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _creditChoice(0, 'Apply credit', Icons.swap_horiz_rounded),
              const SizedBox(width: 10),
              _creditChoice(1, 'Record refund', Icons.undo_rounded),
            ],
          ),
          if (_creditAction != null) ...[
            const SizedBox(height: 18),
            TextField(
              controller: _creditAmount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _input(
                'Amount',
                prefix: '${gym.settings.currencySymbol} ',
              ),
            ),
            const SizedBox(height: 14),
            if (_creditAction == 0) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(_expected.feeChanges.length),
                initialValue: _target?.id,
                isExpanded: true,
                decoration: _input('Membership period'),
                items: targets
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.formattedDateRange} (${money(p.balanceDue)} due)',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _target = targets.firstWhere((p) => p.id == id),
                      ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _applyCredit,
                style: _primaryButton,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Apply credit to selected period'),
              ),
            ] else ...[
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: _input('Refund method'),
                items: PaymentMethod.values
                    .map(
                      (m) => DropdownMenuItem(value: m, child: Text(m.label)),
                    )
                    .toList(),
                onChanged: _busy ? null : (m) => setState(() => _method = m!),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _refundReason,
                enabled: !_busy,
                maxLines: 2,
                decoration: _input(
                  'Reason / return reference',
                  hint: 'e.g. Cash returned to member',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Only record money you have already returned.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _recordRefund,
                style: _primaryButton,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Record money returned'),
              ),
            ],
          ],
        ],
      ),
      accent: AppColors.primary,
    );
  }

  Widget _historyEntry(FeeChange change) {
    final removed = _expected.feeChanges.any(
      (c) => c.reversesChangeId == change.id,
    );
    final latest = change.id == _expected.latestFeeAdjustment?.id;
    final blocked = _expected.adjustmentRemovalBlockedReason;
    final date = change.at.toLocal();
    final isFee =
        change.kind == 'Fee adjusted' ||
        change.kind == 'Fee adjustment removed';
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  change.kind,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (removed)
                Text(
                  'Removed',
                  style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (isFee) ...[
                Text(
                  money(change.before),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
              Text(
                money(change.after),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            change.reason,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${change.actor} • ${GymDateUtils.formatDate(date)} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          if (latest) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy || blocked != null ? null : _removeAdjustment,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text(
                'Remove adjustment',
                style: TextStyle(fontSize: 14),
              ),
            ),
            if (blocked != null)
              Text(
                blocked,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
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
                    Expanded(
                      child: Text(
                        _editingFee ? 'Adjust fee' : 'Fee adjustment details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _changed),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceElevated,
                        foregroundColor: AppColors.textSecondary,
                      ),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _expected.formattedDateRange,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _summary(),
                if (!_editingFee && _expected.canAdjustFee) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _editingFee = true;
                            _error = null;
                          }),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Change fee'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
                if (_editingFee && _expected.canAdjustFee) ...[
                  const SizedBox(height: 16),
                  _editFee(),
                ],
                if (_expected.availableCredit > 0) ...[
                  const SizedBox(height: 16),
                  _creditCard(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _card(
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    accent: Theme.of(context).colorScheme.error,
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (_changed) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.dynamicPaid,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Change saved.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.dynamicPaid,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_expected.feeChanges.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Adjustment history',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  for (final change in _expected.feeChanges.reversed) ...[
                    const SizedBox(height: 12),
                    _historyEntry(change),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
