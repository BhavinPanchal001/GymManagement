import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A modal dialog that protects destructive actions (like clearing all data
/// or overwriting with demo data) when real data exists in the database.
///
/// It displays exact record counts that will be lost and requires typing
/// an explicit confirmation phrase (e.g. "DELETE ALL DATA") to activate
/// the destructive action button.
class DangerConfirmationDialog extends StatefulWidget {
  final String title;
  final String description;
  final String actionLabel;
  final String confirmationPhrase;
  final int memberCount;
  final int paymentCount;
  final int billCount;
  final int expenseCount;
  final int attendanceCount;

  const DangerConfirmationDialog({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.confirmationPhrase = 'DELETE ALL DATA',
    this.memberCount = 0,
    this.paymentCount = 0,
    this.billCount = 0,
    this.expenseCount = 0,
    this.attendanceCount = 0,
  });

  /// Displays the danger confirmation dialog and returns `true` if the user
  /// successfully entered the required phrase and confirmed the action.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String description,
    required String actionLabel,
    String confirmationPhrase = 'DELETE ALL DATA',
    int memberCount = 0,
    int paymentCount = 0,
    int billCount = 0,
    int expenseCount = 0,
    int attendanceCount = 0,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DangerConfirmationDialog(
        title: title,
        description: description,
        actionLabel: actionLabel,
        confirmationPhrase: confirmationPhrase,
        memberCount: memberCount,
        paymentCount: paymentCount,
        billCount: billCount,
        expenseCount: expenseCount,
        attendanceCount: attendanceCount,
      ),
    );
  }

  @override
  State<DangerConfirmationDialog> createState() => _DangerConfirmationDialogState();
}

class _DangerConfirmationDialogState extends State<DangerConfirmationDialog> {
  late final TextEditingController _phraseController;
  bool _isConfirmed = false;

  @override
  void initState() {
    super.initState();
    _phraseController = TextEditingController();
    _phraseController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final matches = _phraseController.text.trim() == widget.confirmationPhrase;
    if (matches != _isConfirmed) {
      setState(() {
        _isConfirmed = matches;
      });
    }
  }

  @override
  void dispose() {
    _phraseController.removeListener(_onTextChanged);
    _phraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: AppColors.absent.withValues(alpha: 0.4), width: 1.5),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.absent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.absent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.absent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DANGER ZONE',
                    style: TextStyle(
                      color: AppColors.absent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),

            // Record count breakdown card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF221115) : const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.absent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.absent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Records that will be permanently lost:',
                        style: TextStyle(
                          color: isDark ? const Color(0xFFFF8A80) : const Color(0xFFBE123C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildCountBadge('Members', widget.memberCount, Icons.people_outline_rounded),
                      _buildCountBadge('Attendance', widget.attendanceCount, Icons.event_available_rounded),
                      _buildCountBadge('Payments', widget.paymentCount, Icons.receipt_long_rounded),
                      _buildCountBadge('Invoices', widget.billCount, Icons.description_outlined),
                      _buildCountBadge('Expenses', widget.expenseCount, Icons.account_balance_wallet_outlined),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Confirmation phrase prompt
            RichText(
              text: TextSpan(
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                children: [
                  const TextSpan(text: 'To confirm, type '),
                  TextSpan(
                    text: widget.confirmationPhrase,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.absent,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const TextSpan(text: ' below:'),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Input TextField
            TextField(
              controller: _phraseController,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              decoration: InputDecoration(
                hintText: widget.confirmationPhrase,
                hintStyle: TextStyle(
                  color: AppColors.textMuted.withValues(alpha: 0.5),
                  fontWeight: FontWeight.normal,
                ),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.absent, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isConfirmed ? AppColors.absent : AppColors.surfaceBorder,
            foregroundColor: _isConfirmed ? Colors.white : AppColors.textMuted,
            elevation: _isConfirmed ? 2 : 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          ),
          onPressed: _isConfirmed ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            widget.actionLabel,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge(String label, int count, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
