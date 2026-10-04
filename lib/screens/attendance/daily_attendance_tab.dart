import 'package:flutter/material.dart';
import '../../models/attendance.dart';
import '../../services/gym_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_month_attendance_dialog.dart';
import '../customers/customer_detail_screen.dart';

class DailyAttendanceTab extends StatefulWidget {
  const DailyAttendanceTab({super.key});

  @override
  State<DailyAttendanceTab> createState() => _DailyAttendanceTabState();
}

class _DailyAttendanceTabState extends State<DailyAttendanceTab> {
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
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
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.primaryOn,
              surface: AppColors.surface,
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

  void _markAllPresent() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (targetDay.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot mark attendance for future dates.'),
          backgroundColor: AppColors.pending,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final gym = GymService();
    final dateKey = GymDateUtils.toDateKey(_selectedDate);
    try {
      await gym.markAllPresentForDate(dateKey);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not save attendance. Please try again.')));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All eligible members marked Present for ${GymDateUtils.formatDate(_selectedDate)}!'),
          backgroundColor: AppColors.paid,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dateKey = GymDateUtils.toDateKey(_selectedDate);
        final targetDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final isToday = targetDay == today;
        final isFutureDate = targetDay.isAfter(today);
        final overview = gym.getDailyOverview(dateKey);
        final activeCustomers = gym.customers
            .where(
              (c) => c.isActive && !targetDay.isBefore(DateTime(c.joinDate.year, c.joinDate.month, c.joinDate.day)),
            )
            .toList();
        final searchQuery = _searchController.text.trim().toLowerCase();
        final filteredCustomers = searchQuery.isEmpty
            ? activeCustomers
            : activeCustomers.where((c) {
                return c.name.toLowerCase().contains(searchQuery) ||
                    c.phone.contains(searchQuery) ||
                    c.cardNumber.toLowerCase().contains(searchQuery);
              }).toList();
        final total = overview['total'] ?? 0;
        final present = overview['present'] ?? 0;
        final absent = overview['absent'] ?? 0;
        final rate = total > 0 ? ((present / total) * 100).round() : 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Daily Attendance'),
            actions: [
              IconButton(
                icon: Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                tooltip: 'Change Date',
                onPressed: _pickDate,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
                tooltip: 'More Attendance Options',
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.surfaceBorder),
                ),
                onSelected: (val) async {
                  if (val == 'mark_month') {
                    final isFutureMonth = DateTime(
                      _selectedDate.year,
                      _selectedDate.month,
                      1,
                    ).isAfter(DateTime(now.year, now.month, 1));
                    if (isFutureMonth) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot mark attendance for future months.'),
                          backgroundColor: AppColors.pending,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }
                    final updated = await MarkMonthAttendanceDialog.show(context, customer: null, month: _selectedDate);
                    if (updated == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Updated attendance for ${GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(_selectedDate))} for all active members.',
                          ),
                          backgroundColor: AppColors.paid,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'mark_month',
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Mark Month (All Members)...',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // Date Banner & Switcher (hidden while the keyboard is open so the
              // search field and results fit on small screens)
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      GymDateUtils.formatDate(_selectedDate),
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isToday) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'TODAY',
                                        style: TextStyle(
                                          color: AppColors.primaryOn,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                GymDateUtils.formatDayOfWeek(_selectedDate),
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: isFutureDate ? null : _markAllPresent,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.paid,
                            side: BorderSide(color: isFutureDate ? AppColors.surfaceBorder : AppColors.paid),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.done_all_rounded, size: 16),
                          label: const Text('Mark All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (isFutureDate) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.pending.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.pending, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Future date: Attendance cannot be marked in advance.',
                                style: TextStyle(color: AppColors.pending, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Metrics Strip
                    Row(
                      children: [
                        Expanded(child: _buildMetricCol('Present', '$present', AppColors.paid)),
                        Container(width: 1, height: 28, color: AppColors.surfaceBorder),
                        Expanded(child: _buildMetricCol('Absent', '$absent', AppColors.absent)),
                        Container(width: 1, height: 28, color: AppColors.surfaceBorder),
                        Expanded(child: _buildMetricCol('Turnout', '$rate%', AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, or card #...',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: AppColors.textSecondary),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Attendance List
              Expanded(
                child: filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (searchQuery.isNotEmpty) ...[
                              Icon(Icons.person_search_rounded, size: 54, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              searchQuery.isNotEmpty
                                  ? 'No members found matching "${_searchController.text.trim()}"'
                                  : 'No active members to record attendance.',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredCustomers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final customer = filteredCustomers[i];
                          final status = gym.getAttendanceStatus(customer.id, dateKey);
                          final isPresent = status == AttendanceStatus.present;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isPresent ? AppColors.paid.withValues(alpha: 0.35) : AppColors.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                CustomerAvatar(
                                  imagePath: customer.imagePath,
                                  imageBase64: customer.imageBase64,
                                  name: customer.name,
                                  radius: 22,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: customer.id)),
                                    );
                                  },
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CustomerDetailScreen(customerId: customer.id),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          customer.name,
                                          style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          customer.phone,
                                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Quick Status Toggle Buttons
                                Row(
                                  children: [
                                    _buildStatusButton(
                                      label: 'Present',
                                      icon: Icons.check_circle_rounded,
                                      color: AppColors.paid,
                                      isActive: isPresent,
                                      isDisabled: isFutureDate,
                                      onTap: isFutureDate
                                          ? null
                                          : () {
                                              gym.toggleAttendance(customer.id, dateKey, AttendanceStatus.present);
                                            },
                                    ),
                                    const SizedBox(width: 6),
                                    _buildStatusButton(
                                      label: 'Absent',
                                      icon: Icons.cancel_rounded,
                                      color: AppColors.absent,
                                      isActive: status == AttendanceStatus.absent,
                                      isDisabled: isFutureDate,
                                      onTap: isFutureDate
                                          ? null
                                          : () {
                                              gym.toggleAttendance(customer.id, dateKey, AttendanceStatus.absent);
                                            },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCol(String label, String val, Color color) {
    return Column(
      children: [
        Text(
          val,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildStatusButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    bool isDisabled = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isDisabled
              ? AppColors.surfaceElevated.withValues(alpha: 0.4)
              : (isActive ? color.withValues(alpha: 0.2) : AppColors.surfaceElevated),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDisabled
                ? AppColors.surfaceBorder.withValues(alpha: 0.4)
                : (isActive ? color : AppColors.surfaceBorder),
            width: isActive && !isDisabled ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isDisabled
                  ? AppColors.textMuted.withValues(alpha: 0.35)
                  : (isActive ? color : AppColors.textMuted),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isDisabled
                    ? AppColors.textMuted.withValues(alpha: 0.35)
                    : (isActive ? color : AppColors.textSecondary),
                fontSize: 11,
                fontWeight: isActive && !isDisabled ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
