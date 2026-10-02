import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/money_utils.dart';

class AddExpenseDialog extends StatefulWidget {
  final ExpenseRecord? expenseToEdit;
  final DateTime? initialDate;

  const AddExpenseDialog({super.key, this.expenseToEdit, this.initialDate});

  static Future<void> show(BuildContext context, {ExpenseRecord? expenseToEdit, DateTime? initialDate}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddExpenseDialog(expenseToEdit: expenseToEdit, initialDate: initialDate),
    );
  }

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _notesController;

  late ExpenseCategory _selectedCategory;
  late PaymentMethod _selectedPaymentMethod;
  late DateTime _selectedDate;
  bool _isSaving = false;

  bool get _isEditing => widget.expenseToEdit != null;

  @override
  void initState() {
    super.initState();
    final edit = widget.expenseToEdit;
    _titleController = TextEditingController(text: edit?.title ?? '');
    _amountController = TextEditingController(text: edit != null ? MoneyUtils.formatForInput(edit.amount) : '');
    _notesController = TextEditingController(text: edit?.notes ?? '');

    _selectedCategory = edit?.category ?? ExpenseCategory.rent;
    _selectedPaymentMethod = edit?.paymentMethod ?? PaymentMethod.cash;
    _selectedDate = edit?.date ?? widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.primaryOn,
              surface: AppColors.surfaceElevated,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = MoneyUtils.tryParseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid expense amount')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final gym = GymService();
      if (_isEditing) {
        final updated = widget.expenseToEdit!.copyWith(
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory,
          date: _selectedDate,
          paymentMethod: _selectedPaymentMethod,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
        await gym.updateExpense(updated);
      } else {
        await gym.addExpense(
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory,
          date: _selectedDate,
          paymentMethod: _selectedPaymentMethod,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Expense updated successfully' : 'Expense recorded successfully'),
            backgroundColor: AppColors.paid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving expense: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(
          'Delete Expense?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.expenseToEdit!.title}"?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await GymService().deleteExpense(widget.expenseToEdit!.id);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense deleted'), backgroundColor: Colors.orange));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = GymService().settings.currencySymbol;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.surfaceBorder),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _selectedCategory.color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_selectedCategory.icon, color: _selectedCategory.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Edit Gym Expense' : 'Add Gym Expense',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                          Text(
                            'Track operating costs & overheads',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(color: AppColors.surfaceBorder, height: 1),
                const SizedBox(height: 18),

                // Category Grid / Selector
                Text(
                  'Expense Category',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExpenseCategory.values.map((cat) {
                    final isSelected = cat == _selectedCategory;
                    return ChoiceChip(
                      selected: isSelected,
                      showCheckmark: false,
                      avatar: Icon(cat.icon, size: 16, color: isSelected ? Colors.black : cat.color),
                      label: Text(
                        cat.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.black : AppColors.textPrimary,
                        ),
                      ),
                      selectedColor: cat.color,
                      backgroundColor: AppColors.surfaceElevated,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isSelected ? cat.color : AppColors.surfaceBorder, width: 1),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = cat;
                            // Suggest a default title if title is empty
                            if (_titleController.text.trim().isEmpty) {
                              _titleController.text = cat.label;
                            }
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // Expense Title
                TextFormField(
                  controller: _titleController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Expense Title / Description',
                    hintText: 'e.g. Gym Rent, Electricity, Treadmill Belt',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    prefixIcon: Icon(Icons.edit_note, color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter an expense title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Amount & Date in a Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: const [MoneyInputFormatter()],
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          labelText: 'Amount ($currency)',
                          hintText: '0',
                          hintStyle: TextStyle(color: AppColors.textMuted),
                          labelStyle: TextStyle(color: AppColors.textSecondary),
                          prefixText: '$currency ',
                          prefixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                          filled: true,
                          fillColor: AppColors.surfaceElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.surfaceBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.surfaceBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Enter amount';
                          }
                          final parsed = MoneyUtils.tryParseAmount(val);
                          if (parsed == null || parsed <= 0) {
                            return 'Valid amount > 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Date
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.surfaceBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Date', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                                    Text(
                                      GymDateUtils.formatDisplayDate(_selectedDate),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Payment Method Dropdown
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _selectedPaymentMethod,
                  dropdownColor: AppColors.surfaceElevated,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Payment Mode',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                  items: PaymentMethod.values.map((method) {
                    return DropdownMenuItem<PaymentMethod>(
                      value: method,
                      child: Text(
                        PaymentRecord.methodLabel(method),
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedPaymentMethod = val);
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Notes / Vendor info
                TextFormField(
                  controller: _notesController,
                  maxLines: 2,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Notes / Vendor / Bill # (Optional)',
                    hintText: 'e.g. Paid to Landlord, Bill No #4829',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    prefixIcon: Icon(Icons.description_outlined, color: AppColors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Actions
                Row(
                  children: [
                    if (_isEditing) ...[
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: 'Delete Expense',
                        onPressed: _isSaving ? null : _delete,
                      ),
                      const Spacer(),
                    ] else ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(color: AppColors.surfaceBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: _isEditing ? 0 : 1,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.primaryOn,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : Text(
                                _isEditing ? 'Update Expense' : 'Save Expense',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
