import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import '../../models/member_import.dart';
import '../../services/gym_service.dart';
import '../../services/member_import_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class ImportMembersScreen extends StatefulWidget {
  const ImportMembersScreen({super.key});

  static Future<bool?> navigate(BuildContext context) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ImportMembersScreen()),
    );
  }

  @override
  State<ImportMembersScreen> createState() => _ImportMembersScreenState();
}

class _ImportMembersScreenState extends State<ImportMembersScreen> {
  MemberImportPreview? _preview;
  String? _fileName;
  String? _error;
  bool _isReading = false;
  bool _isImporting = false;

  Future<void> _chooseCsv() async {
    if (_isReading || _isImporting) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null || !mounted) return;

    setState(() {
      _isReading = true;
      _error = null;
    });
    try {
      final picked = result.files.single;
      final bytes =
          picked.bytes ??
          (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) {
        throw const FileSystemException('The selected CSV could not be read.');
      }
      final gym = GymService();
      final preview = MemberImportService().parseCsv(
        csvText: utf8.decode(bytes),
        existingCustomers: gym.customers,
        settings: gym.settings,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _fileName = picked.name;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _fileName = null;
        _error = _message(error);
      });
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  Future<void> _copyTemplate() async {
    await Clipboard.setData(
      const ClipboardData(text: MemberImportService.csvTemplate),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV template copied. Paste it into Excel or Sheets.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _importMembers() async {
    final rows = _preview?.importableRows ?? const <MemberImportData>[];
    if (rows.isEmpty || _isImporting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Import ${rows.length} members?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Valid rows will create member profiles, membership periods, opening '
          'balances, and receipts for any amount already paid.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Import',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);
    try {
      final imported = await GymService().importMembers(rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${imported.length} members imported successfully.'),
          backgroundColor: AppColors.paid,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Import Existing Members')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: _buildInstructions(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _buildMessage(
                icon: Icons.error_outline_rounded,
                color: AppColors.absent,
                text: _error!,
              ),
            ),
          if (preview != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: _buildSummary(preview),
            ),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: preview.rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _buildRow(preview.rows[index]),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.surfaceBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isImporting ? null : _chooseCsv,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Choose Another'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            preview.importableRows.isEmpty || _isImporting
                            ? null
                            : _importMembers,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.group_add_rounded),
                        label: Text(
                          _isImporting
                              ? 'Importing...'
                              : 'Import ${preview.importableRows.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_view_rounded,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Choose a CSV exported from Excel or Google Sheets.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You will see every row and any duplicate or invalid '
                        'details before anything is saved.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _isReading ? null : _chooseCsv,
                        icon: _isReading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                          _isReading ? 'Reading CSV...' : 'Choose CSV File',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fileName ?? 'CSV columns',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _copyTemplate,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy Template'),
              ),
            ],
          ),
          Text(
            'Required: Name, Phone. Optional: Card Number, Join Date, Plan, '
            'Duration Months, Membership Start/End, Agreed Fee, Amount Paid, '
            'Payment Method, Paid Date, Address, Notes.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(MemberImportPreview preview) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryValue(
              'Ready',
              preview.importableRows.length,
              AppColors.paid,
            ),
          ),
          Expanded(
            child: _summaryValue(
              'Need Fixing',
              preview.errorCount,
              AppColors.absent,
            ),
          ),
          Expanded(
            child: _summaryValue(
              'Warnings',
              preview.warningCount,
              AppColors.pending,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(MemberImportRow row) {
    final data = row.data;
    final color = row.canImport ? AppColors.paid : AppColors.absent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                row.canImport
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.displayName.isEmpty
                          ? 'Unnamed member'
                          : row.displayName,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        'Row ${row.rowNumber}',
                        row.displayPhone.isEmpty
                            ? 'No phone'
                            : row.displayPhone,
                        if (row.displayCardNumber.isNotEmpty)
                          'Card ${row.displayCardNumber}',
                      ].join(' • '),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data != null) ...[
            const SizedBox(height: 9),
            Text(
              '${CustomerPlan.getShortLabel(data.planType)} • '
              '${data.durationMonths} month${data.durationMonths == 1 ? '' : 's'} • '
              '${GymDateUtils.formatDate(data.membershipStartDate)} to '
              '${GymDateUtils.formatDate(data.membershipEndDate)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              'Fee ${GymDateUtils.formatCurrency(data.membershipFee, symbol: GymService().settings.currencySymbol)}'
              ' • Paid ${GymDateUtils.formatCurrency(data.amountPaid, symbol: GymService().settings.currencySymbol)}',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final error in row.errors) ...[
            const SizedBox(height: 7),
            _buildMessage(
              icon: Icons.error_outline_rounded,
              color: AppColors.absent,
              text: error,
              compact: true,
            ),
          ],
          for (final warning in row.warnings) ...[
            const SizedBox(height: 7),
            _buildMessage(
              icon: Icons.warning_amber_rounded,
              color: AppColors.pending,
              text: warning,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required Color color,
    required String text,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 6 : 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: compact ? 15 : 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('FileSystemException: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
