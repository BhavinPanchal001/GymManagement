import 'package:flutter/material.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../utils/date_utils.dart';

/// Owner-approved changes to a single agreed membership period.
class FeeAdjustmentSheet extends StatefulWidget {
  final PaymentRecord payment;
  const FeeAdjustmentSheet({super.key, required this.payment});

  static Future<bool?> show(BuildContext context, PaymentRecord payment) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _expected = widget.payment;
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

  bool _validCreditAmount(double? amount) =>
      amount != null &&
      amount.isFinite &&
      amount > 0 &&
      amount <= _expected.availableCredit &&
      (amount * 100 - (amount * 100).round()).abs() <= 0.00001;

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final targets = gym
        .feePeriods(_expected.customerId)
        .where((p) => p.id != _expected.id && p.balanceDue > 0)
        .toList();
    final next = gym.creditRenewalPeriod(_expected.customerId);
    if (!targets.any((p) => p.effectiveStartDate == next.effectiveStartDate)) {
      targets.add(next);
    }
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Adjust fee',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(_expected.formattedDateRange),
                const SizedBox(height: 12),
                Text(
                  'Original fee: ${money(_expected.originalFee ?? _expected.totalDue)}\n'
                  'Current fee: ${money(_expected.totalDue)}\n'
                  'Money received: ${money(_expected.amount)}\n'
                  'Credit applied here: ${money(_expected.creditApplied)}\n'
                  'Still owed: ${money(_expected.balanceDue)}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fee,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Revised fee',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason for adjustment',
                    hintText: 'Approved half-month discount',
                    border: OutlineInputBorder(),
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _adjust,
                  child: const Text('Review fee adjustment'),
                ),
                if (_expected.availableCredit > 0) ...[
                  const Divider(height: 32),
                  Text(
                    'Available member credit: ${money(_expected.availableCredit)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'This is money already received. Leave it here for later, apply it to a period, or record money you have returned.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _creditAmount,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Credit amount to use or return',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_expected.feeChanges.length),
                    initialValue: _target?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Apply to membership period',
                    ),
                    items: targets
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.formattedDateRange} (${money(p.balanceDue)} due)',
                              maxLines: 2,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (id) => setState(
                            () =>
                                _target = targets.firstWhere((p) => p.id == id),
                          ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final target = _target,
                                amount = double.tryParse(_creditAmount.text);
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
                              (id) => gym.applyMemberCredit(
                                expectedSource: _expected,
                                expectedTarget: target,
                                amount: amount,
                                operationId: id,
                              ),
                            );
                          },
                    child: const Text('Apply credit to selected period'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'How money was returned',
                    ),
                    items: PaymentMethod.values
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text(m.label)),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (m) => setState(() => _method = m!),
                  ),
                  TextField(
                    controller: _refundReason,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Reason / return reference',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final amount = double.tryParse(_creditAmount.text);
                            if (!_validCreditAmount(amount) ||
                                _refundReason.text.trim().isEmpty) {
                              setState(
                                () => _error =
                                    'Enter a valid amount and return reason.',
                              );
                              return;
                            }
                            _run(
                              'Confirm you have already returned ${money(amount!)} by ${_method.label}.\n'
                              'This records money returned and reduces net collections. It does not send a bank payment.',
                              (id) => gym.refundMemberCredit(
                                expected: _expected,
                                amount: amount,
                                method: _method,
                                reason: _refundReason.text,
                                operationId: id,
                              ),
                            );
                          },
                    child: const Text('Record money returned'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_changed)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Change saved.'),
                  ),
                if (_expected.feeChanges.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Adjustment history',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final c in _expected.feeChanges.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${c.kind}: ${money(c.before)} → ${money(c.after)}\n'
                        '${c.reason}\n${c.actor} • ${GymDateUtils.formatDate(c.at.toLocal())} ${c.at.toLocal().hour.toString().padLeft(2, '0')}:${c.at.toLocal().minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
