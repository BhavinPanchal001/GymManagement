import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class ExportReportDialog extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<MemberPendingSummary> memberSummaries;
  final double totalPending;

  const ExportReportDialog({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.memberSummaries,
    required this.totalPending,
  });

  static Future<void> show(
    BuildContext context, {
    required DateTime startDate,
    required DateTime endDate,
    required List<MemberPendingSummary> memberSummaries,
    required double totalPending,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ExportReportDialog(
        startDate: startDate,
        endDate: endDate,
        memberSummaries: memberSummaries,
        totalPending: totalPending,
      ),
    );
  }

  @override
  State<ExportReportDialog> createState() => _ExportReportDialogState();
}

class _ExportReportDialogState extends State<ExportReportDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _csvContent;
  late String _textContent;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateExports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _generateExports() {
    final gym = GymService();
    final gymName = gym.settings.gymName.isEmpty ? 'Gym' : gym.settings.gymName;
    final currency = gym.settings.currencySymbol;
    final dateRangeStr = '${GymDateUtils.formatDate(widget.startDate)} to ${GymDateUtils.formatDate(widget.endDate)}';

    // 1. Generate CSV
    final csvBuf = StringBuffer();
    csvBuf.writeln('Member Name,Phone,Join Date,Month,Amount Due,Status');
    for (final m in widget.memberSummaries) {
      final name = m.customer.name.replaceAll(',', ' ');
      final phone = m.customer.phone.replaceAll(',', ' ');
      final join = GymDateUtils.formatDate(m.customer.joinDate);
      for (final r in m.pendingRecords) {
        final monthStr = GymDateUtils.formatMonthYearKey(r.monthYear);
        csvBuf.writeln('"$name","$phone","$join","$monthStr",${r.amount.toStringAsFixed(2)},"Pending"');
      }
    }
    _csvContent = csvBuf.toString();

    // 2. Generate Formatted Text
    final textBuf = StringBuffer();
    textBuf.writeln('📋 *$gymName - Outstanding Dues Report*');
    textBuf.writeln('📅 Period: $dateRangeStr');
    textBuf.writeln('💰 Total Pending: ${GymDateUtils.formatCurrency(widget.totalPending, symbol: currency)}');
    textBuf.writeln('👥 Unpaid Members: ${widget.memberSummaries.length}');
    textBuf.writeln('----------------------------------------');

    if (widget.memberSummaries.isEmpty) {
      textBuf.writeln('🎉 No outstanding dues found for this period!');
    } else {
      for (int i = 0; i < widget.memberSummaries.length; i++) {
        final m = widget.memberSummaries[i];
        final months = m.pendingMonths.map(GymDateUtils.formatMonthYearKey).join(', ');
        textBuf.writeln('${i + 1}. *${m.customer.name}* (${m.customer.phone})');
        textBuf.writeln('   • Due: ${GymDateUtils.formatCurrency(m.totalPendingAmount, symbol: currency)}');
        textBuf.writeln('   • Pending For: $months\n');
      }
    }
    _textContent = textBuf.toString();
  }

  Future<void> _copyToClipboard(String content, String label) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.primaryOn, size: 18),
              const SizedBox(width: 8),
              Text('$label copied to clipboard!'),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.surfaceBorder, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.file_download_outlined, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Pending Report',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Copy CSV data or share formatted summary',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: AppColors.primaryOn,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerHeight: 0,
                tabs: const [
                  Tab(text: 'CSV Format'),
                  Tab(text: 'Text Summary'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tab Views / Previews
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // CSV Preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _csvContent,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),

                  // Text Summary Preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _textContent,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy CSV', style: TextStyle(fontSize: 13)),
                    onPressed: () => _copyToClipboard(_csvContent, 'CSV Data'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.primaryOn,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.assignment_outlined, size: 16),
                    label: const Text('Copy Text', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: () => _copyToClipboard(_textContent, 'Text Summary'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
