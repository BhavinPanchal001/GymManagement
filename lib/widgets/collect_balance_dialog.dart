import 'package:flutter/material.dart';
import '../models/bill.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../utils/date_utils.dart';

/// A new collection is separate from correcting the original receipt.
class CollectBalanceDialog extends StatefulWidget {
  final PaymentRecord payment;
  const CollectBalanceDialog({super.key, required this.payment});
  static Future<BillRecord?> show(
    BuildContext context,
    PaymentRecord payment,
  ) => showDialog<BillRecord>(
    context: context,
    builder: (_) => CollectBalanceDialog(payment: payment),
  );
  @override
  State<CollectBalanceDialog> createState() => _CollectBalanceDialogState();
}

class _CollectBalanceDialogState extends State<CollectBalanceDialog> {
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  DateTime _received = DateTime.now();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;
  final _operationId = GymService().newPaymentOperationId();
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.payment.balanceDue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim());
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        value > widget.payment.balanceDue + 0.005) {
      setState(
        () => _error = 'Enter a positive amount within the remaining balance.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final receipt = await GymService().collectBalance(
        paymentId: widget.payment.id,
        amount: value,
        method: _method,
        paidAt: _received,
        transactionRef: _reference.text.trim(),
        operationId: _operationId,
      );
      if (mounted) Navigator.pop(context, receipt);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ArgumentError
              ? error.message.toString()
              : 'Could not save. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Collect balance'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remaining balance: ${GymService().settings.currencySymbol}${widget.payment.balanceDue.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount received'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Received on: ${GymDateUtils.formatDate(_received)}'),
            onPressed: _saving
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _received,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null && mounted) {
                      setState(() => _received = date);
                    }
                  },
          ),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: PaymentMethod.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: _saving ? null : (m) => setState(() => _method = m!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Transaction reference (optional)',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save collection'),
      ),
    ],
  );
}
