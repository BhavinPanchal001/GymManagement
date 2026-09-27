import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/phone_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/whatsapp_reminder_sheet.dart';
import 'export_report_dialog.dart';

enum DateRangePreset {
  thisMonth('This Month'),
  last3Months('Last 3 Months'),
  last6Months('Last 6 Months'),
  thisYear('This Year'),
  custom('Custom');

  final String label;
  const DateRangePreset(this.label);
}

enum ReportViewMode { byMember, byMonth }

enum ReportSortOrder {
  highestDue('Highest Dues'),
  nameAZ('Name (A-Z)'),
  oldestDue('Oldest Dues');

  final String label;
  const ReportSortOrder(this.label);
}

class PendingPaymentsReportScreen extends StatefulWidget {
  const PendingPaymentsReportScreen({super.key});

  @override
  State<PendingPaymentsReportScreen> createState() => _PendingPaymentsReportScreenState();
}

class _PendingPaymentsReportScreenState extends State<PendingPaymentsReportScreen> {
  DateRangePreset _selectedPreset = DateRangePreset.last3Months;
  late DateTime _startDate;
  late DateTime _endDate;
  ReportViewMode _viewMode = ReportViewMode.byMember;
  ReportSortOrder _sortOrder = ReportSortOrder.highestDue;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _applyPreset(DateRangePreset.last3Months);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyPreset(DateRangePreset preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month + 1, 0); // end of current month

    switch (preset) {
      case DateRangePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        break;
      case DateRangePreset.last3Months:
        start = DateTime(now.year, now.month - 2, 1);
        break;
      case DateRangePreset.last6Months:
        start = DateTime(now.year, now.month - 5, 1);
        break;
      case DateRangePreset.thisYear:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case DateRangePreset.custom:
        return;
    }

    setState(() {
      _selectedPreset = preset;
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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
      setState(() {
        _selectedPreset = DateRangePreset.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  List<MemberPendingSummary> _filterAndSortMembers(List<MemberPendingSummary> original) {
    var list = original;

    // Search query filter
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list.where((m) {
        return m.customer.name.toLowerCase().contains(q) || m.customer.phone.contains(q);
      }).toList();
    }

    // Sort
    switch (_sortOrder) {
      case ReportSortOrder.highestDue:
        list.sort((a, b) => b.totalPendingAmount.compareTo(a.totalPendingAmount));
        break;
      case ReportSortOrder.nameAZ:
        list.sort((a, b) => a.customer.name.toLowerCase().compareTo(b.customer.name.toLowerCase()));
        break;
      case ReportSortOrder.oldestDue:
        list.sort((a, b) {
          final firstMonthA = a.pendingMonths.isNotEmpty ? a.pendingMonths.first : '';
          final firstMonthB = b.pendingMonths.isNotEmpty ? b.pendingMonths.first : '';
          return firstMonthA.compareTo(firstMonthB);
        });
        break;
    }

    return list;
  }

  List<MonthPendingGroup> _filterMonthGroups(List<MonthPendingGroup> original) {
    if (_searchQuery.trim().isEmpty) return original;
    final q = _searchQuery.toLowerCase().trim();

    final filteredGroups = <MonthPendingGroup>[];
    for (final group in original) {
      final matchingItems = group.items.where((it) {
        return it.customer.name.toLowerCase().contains(q) || it.customer.phone.contains(q);
      }).toList();

      if (matchingItems.isNotEmpty) {
        final groupTotal = matchingItems.fold<double>(0.0, (s, it) => s + it.payment.amount);
        filteredGroups.add(MonthPendingGroup(
          monthKey: group.monthKey,
          items: matchingItems,
          totalAmount: groupTotal,
        ));
      }
    }
    return filteredGroups;
  }

  void _openWhatsAppReminder(Customer customer, String monthYear, double amount) {
    WhatsAppReminderSheet.show(
      context,
      customer: customer,
      monthYear: monthYear,
      amount: amount,
    );
  }

  Future<void> _openMarkPaid(Customer customer, PaymentRecord record) async {
    final success = await MarkPaymentDialog.show(
      context,
      customer: customer,
      monthYear: record.monthYear,
      currentRecord: record,
    );

    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment recorded for ${customer.name}!'),
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
        final currency = gym.settings.currencySymbol;

        final rawMemberSummaries = gym.getPendingDuesByMember(_startDate, _endDate);
        final rawMonthGroups = gym.getPendingDuesByMonth(_startDate, _endDate);

        final totalPending = rawMemberSummaries.fold<double>(0.0, (s, m) => s + m.totalPendingAmount);
        final totalPendingRecords = rawMemberSummaries.fold<int>(0, (s, m) => s + m.pendingRecords.length);

        final memberSummaries = _filterAndSortMembers(rawMemberSummaries);
        final monthGroups = _filterMonthGroups(rawMonthGroups);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Pending Dues Report'),
            actions: [
              IconButton(
                icon: Icon(Icons.share_outlined, color: AppColors.primary),
                tooltip: 'Export & Share Report',
                onPressed: () {
                  ExportReportDialog.show(
                    context,
                    startDate: _startDate,
                    endDate: _endDate,
                    memberSummaries: rawMemberSummaries,
                    totalPending: totalPending,
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              // Presets Filter Chips
              _buildPresetChips(),

              // Date Range Active Indicator
              _buildDateRangeHeader(),

              // Top KPI Summary Cards
              _buildKpiSection(totalPending, rawMemberSummaries.length, totalPendingRecords, currency),

              // Search, Sort & View Mode Bar
              _buildFilterAndModeBar(rawMemberSummaries.length),

              // Main Content List
              Expanded(
                child: _viewMode == ReportViewMode.byMember
                    ? _buildByMemberView(memberSummaries, currency)
                    : _buildByMonthView(monthGroups, currency),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: DateRangePreset.values.map((preset) {
          final isSelected = _selectedPreset == preset;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(preset.label),
              selected: isSelected,
              onSelected: (selected) {
                if (preset == DateRangePreset.custom) {
                  _pickCustomDateRange();
                } else if (selected) {
                  _applyPreset(preset);
                }
              },
              backgroundColor: AppColors.surfaceElevated,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                ),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateRangeHeader() {
    final startStr = GymDateUtils.formatDate(_startDate);
    final endStr = GymDateUtils.formatDate(_endDate);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$startStr  →  $endStr',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          InkWell(
            onTap: _pickCustomDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_calendar_rounded, color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Text('Change', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(double totalPending, int unpaidMembersCount, int pendingRecordsCount, String currency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          // Total pending amount
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.pending,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TOTAL PENDING',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  GymDateUtils.formatCurrency(totalPending, symbol: currency),
                  style: const TextStyle(
                    color: AppColors.pending,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 44, color: AppColors.surfaceBorder),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MEMBERS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$unpaidMembersCount',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 44, color: AppColors.surfaceBorder),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONTHS DUE',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$pendingRecordsCount',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterAndModeBar(int totalCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // Search Field & Sort Button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search member or phone...',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, color: AppColors.textSecondary, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.surfaceBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.surfaceBorder),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Sort Menu Button
              PopupMenuButton<ReportSortOrder>(
                initialValue: _sortOrder,
                tooltip: 'Sort By',
                onSelected: (order) => setState(() => _sortOrder = order),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.surfaceBorder),
                ),
                itemBuilder: (ctx) => ReportSortOrder.values.map((order) {
                  return PopupMenuItem(
                    value: order,
                    child: Row(
                      children: [
                        Icon(
                          order == _sortOrder ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: order == _sortOrder ? AppColors.primary : AppColors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(order.label, style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sort_rounded, color: AppColors.textSecondary, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // View Mode Switcher
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing $totalCount members with pending dues',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewToggleButton('By Member', ReportViewMode.byMember, Icons.person_rounded),
                    _buildViewToggleButton('By Month', ReportViewMode.byMonth, Icons.calendar_view_month_rounded),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton(String title, ReportViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildByMemberView(List<MemberPendingSummary> list, String currency) {
    if (list.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = list[i];
        final customer = item.customer;
        final latestRecord = item.pendingRecords.last;

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
              // Member row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CustomerAvatar(
                    imagePath: customer.imagePath,
                    name: customer.name,
                    radius: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
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
                        InkWell(
                          onTap: () => PhoneService().makeCall(
                            customer.phone,
                            context: context,
                            memberName: customer.name,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_rounded, color: AppColors.primary, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                customer.phone,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Total Due Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        GymDateUtils.formatCurrency(item.totalPendingAmount, symbol: currency),
                        style: const TextStyle(
                          color: AppColors.pending,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${item.pendingRecords.length} ${item.pendingRecords.length == 1 ? 'month' : 'months'} due',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Pending months pills
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.pendingRecords.map((rec) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.pending.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          GymDateUtils.formatMonthYearKey(rec.monthYear),
                          style: const TextStyle(
                            color: AppColors.pending,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          GymDateUtils.formatCurrency(rec.amount, symbol: currency),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Action Buttons Row
              Row(
                children: [
                  // Call Member Button
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.all(8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                    ),
                    icon: const Icon(Icons.call_rounded, size: 16),
                    tooltip: 'Call Member',
                    onPressed: () => PhoneService().makeCall(
                      customer.phone,
                      context: context,
                      memberName: customer.name,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // WhatsApp Reminder Button
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.whatsapp,
                        side: BorderSide(color: AppColors.whatsapp.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.chat_rounded, size: 15, color: AppColors.whatsapp),
                      label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openWhatsAppReminder(
                        customer,
                        latestRecord.monthYear,
                        item.totalPendingAmount,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Mark as Paid Button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.primaryOn,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 15),
                      label: const Text('Mark Paid', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openMarkPaid(customer, item.pendingRecords.first),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildByMonthView(List<MonthPendingGroup> groups, String currency) {
    if (groups.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: groups.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final group = groups[i];
        final formattedMonth = GymDateUtils.formatMonthYearKey(group.monthKey);

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month Group Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          formattedMonth,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.pending.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${GymDateUtils.formatCurrency(group.totalAmount, symbol: currency)} due (${group.items.length})',
                        style: const TextStyle(
                          color: AppColors.pending,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Items under this month
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: group.items.length,
                separatorBuilder: (context, index) => Divider(color: AppColors.surfaceBorder.withValues(alpha: 0.5), height: 16),
                itemBuilder: (context, j) {
                  final item = group.items[j];
                  final customer = item.customer;
                  final payment = item.payment;

                  return Row(
                    children: [
                      CustomerAvatar(
                        imagePath: customer.imagePath,
                        name: customer.name,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              customer.phone,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        GymDateUtils.formatCurrency(payment.amount, symbol: currency),
                        style: const TextStyle(
                          color: AppColors.pending,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Quick Call Icon
                      IconButton(
                        icon: Icon(Icons.call_rounded, color: AppColors.primary, size: 18),
                        tooltip: 'Call Member',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => PhoneService().makeCall(
                          customer.phone,
                          context: context,
                          memberName: customer.name,
                        ),
                      ),

                      // Quick WhatsApp Icon
                      IconButton(
                        icon: const Icon(Icons.chat_rounded, color: AppColors.whatsapp, size: 18),
                        tooltip: 'WhatsApp Reminder',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openWhatsAppReminder(
                          customer,
                          group.monthKey,
                          payment.amount,
                        ),
                      ),

                      // Quick Pay Icon
                      IconButton(
                        icon: Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                        tooltip: 'Mark Paid',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openMarkPaid(customer, payment),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.paid.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded, color: AppColors.paid, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'All Clear!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No pending payments found for this selected date range or query.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
