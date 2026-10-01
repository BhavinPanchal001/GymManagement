import 'package:flutter/material.dart';
import '../models/attendance.dart';
import '../models/customer.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class MarkMonthAttendanceDialog extends StatefulWidget {
  final Customer? customer; // null if marking for all active members
  final DateTime month;

  const MarkMonthAttendanceDialog({
    super.key,
    this.customer,
    required this.month,
  });

  static Future<bool?> show(
    BuildContext context, {
    Customer? customer,
    required DateTime month,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MarkMonthAttendanceDialog(
        customer: customer,
        month: month,
      ),
    );
  }

  @override
  State<MarkMonthAttendanceDialog> createState() => _MarkMonthAttendanceDialogState();
}

class _MarkMonthAttendanceDialogState extends State<MarkMonthAttendanceDialog> {
  AttendanceStatus _selectedStatus = AttendanceStatus.present;
  bool _excludeSundays = true;
  final bool _upToTodayOnly = true;
  bool _isLoading = false;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return now.year == widget.month.year && now.month == widget.month.month;
  }

  bool get _isFutureMonth {
    final now = DateTime.now();
    final monthStart = DateTime(widget.month.year, widget.month.month, 1);
    final currentMonthStart = DateTime(now.year, now.month, 1);
    return monthStart.isAfter(currentMonthStart);
  }

  int get _totalDaysInMonth => GymDateUtils.daysInMonth(widget.month.year, widget.month.month);

  int get _targetMaxDay {
    if (_isFutureMonth) return 0;
    if (_isCurrentMonth) {
      return DateTime.now().day;
    }
    return _totalDaysInMonth;
  }

  Map<String, int> _calculatePreview() {
    int present = 0;
    int absent = 0;
    int rest = 0;

    final maxDay = _targetMaxDay;
    for (int day = 1; day <= maxDay; day++) {
      final date = DateTime(widget.month.year, widget.month.month, day);
      if (_selectedStatus == AttendanceStatus.present && _excludeSundays && date.weekday == DateTime.sunday) {
        rest++;
      } else if (_selectedStatus == AttendanceStatus.present) {
        present++;
      } else if (_selectedStatus == AttendanceStatus.absent) {
        absent++;
      } else if (_selectedStatus == AttendanceStatus.rest) {
        rest++;
      }
    }

    return {
      'total': maxDay,
      'present': present,
      'absent': absent,
      'rest': rest,
    };
  }

  Future<void> _apply() async {
    if (_isFutureMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot mark attendance for future months.'),
          backgroundColor: AppColors.pending,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final gym = GymService();
    final year = widget.month.year;
    final month = widget.month.month;

    try {
      if (widget.customer != null) {
        await gym.setMonthAttendance(
          customerId: widget.customer!.id,
          year: year,
          month: month,
          status: _selectedStatus,
          excludeSundays: _selectedStatus == AttendanceStatus.present && _excludeSundays,
          sundayStatus: AttendanceStatus.rest,
          upToTodayOnly: _isCurrentMonth ? true : _upToTodayOnly,
        );
      } else {
        // Bulk for all active members
        final activeCustomerIds = gym.customers.where((c) => c.isActive).map((c) => c.id).toList();
        await gym.setMonthAttendanceForMultiple(
          customerIds: activeCustomerIds,
          year: year,
          month: month,
          status: _selectedStatus,
          excludeSundays: _selectedStatus == AttendanceStatus.present && _excludeSundays,
          sundayStatus: AttendanceStatus.rest,
          upToTodayOnly: _isCurrentMonth ? true : _upToTodayOnly,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating attendance: $e'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthName = GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(widget.month));
    final preview = _calculatePreview();
    final isSingleCustomer = widget.customer != null;
    final totalMembers = isSingleCustomer ? 1 : GymService().customers.where((c) => c.isActive).length;

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
            const SizedBox(height: 18),

            // Header info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mark Month Attendance',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSingleCustomer
                            ? '${widget.customer!.name} • $monthName'
                            : 'All Active Members ($totalMembers) • $monthName',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ],
            ),
            if (_isFutureMonth) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pending.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.pending, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Attendance cannot be marked for future months.',
                        style: TextStyle(color: AppColors.pending, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Target Status Selection
            Text(
              'SELECT STATUS TO MARK',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildStatusCard(
                    status: AttendanceStatus.present,
                    title: 'Present',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.paid,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatusCard(
                    status: AttendanceStatus.absent,
                    title: 'Absent',
                    icon: Icons.cancel_rounded,
                    color: AppColors.absent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatusCard(
                    status: AttendanceStatus.rest,
                    title: 'Rest Day',
                    icon: Icons.bed_rounded,
                    color: AppColors.rest,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Toggles / Configuration Section
            Text(
              'RULES & RANGE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  // Sundays as Rest Day Toggle (Only relevant when marking Present)
                  if (_selectedStatus == AttendanceStatus.present) ...[
                    Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(
                        'Keep Sundays as Rest Day',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Sundays are marked as Rest instead of Present',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.rest.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bed_rounded, color: AppColors.rest, size: 20),
                      ),
                      // ignore: deprecated_member_use
                      activeColor: AppColors.primary,
                      value: _excludeSundays,
                      onChanged: (val) => setState(() => _excludeSundays = val),
                    ),
                    ),
                    if (_isCurrentMonth)
                      Divider(height: 1, color: AppColors.surfaceBorder, indent: 16, endIndent: 16),
                  ],

                  // Current Month Range Banner
                  if (_isCurrentMonth) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.today_rounded, color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Marking up to today (Day 1 to ${DateTime.now().day})',
                                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Future dates in this month cannot be marked in advance.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Live Preview Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${preview['total']} days will be updated${!isSingleCustomer ? ' for $totalMembers members' : ''}:',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 10,
                          children: [
                            if ((preview['present'] ?? 0) > 0)
                              Text(
                                '${preview['present']} Present',
                                style: const TextStyle(
                                  color: AppColors.paid,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if ((preview['absent'] ?? 0) > 0)
                              Text(
                                '${preview['absent']} Absent',
                                style: const TextStyle(
                                  color: AppColors.absent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if ((preview['rest'] ?? 0) > 0)
                              Text(
                                '${preview['rest']} Rest Day',
                                style: const TextStyle(
                                  color: AppColors.rest,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _isFutureMonth) ? null : _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedStatus == AttendanceStatus.present
                          ? AppColors.paid
                          : _selectedStatus == AttendanceStatus.absent
                              ? AppColors.absent
                              : AppColors.rest,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceElevated,
                      disabledForegroundColor: AppColors.textMuted,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            _isFutureMonth ? Icons.block_rounded : Icons.done_all_rounded,
                            size: 20,
                          ),
                    label: Text(
                      _isLoading
                          ? 'Applying...'
                          : (_isFutureMonth ? 'Cannot Mark Future' : 'Apply to Month'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required AttendanceStatus status,
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedStatus == status;

    return InkWell(
      onTap: () => setState(() => _selectedStatus = status),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : AppColors.surfaceBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? (AppColors.isDark ? Colors.white : color) : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
