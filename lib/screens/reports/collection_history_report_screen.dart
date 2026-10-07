import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/phone_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/bill_receipt_dialog.dart';
import '../../widgets/voice_search_suffix.dart';

enum CollectionDatePreset {
  thisMonth('This Month'),
  last3Months('Last 3 Months'),
  last6Months('Last 6 Months'),
  thisYear('This Year'),
  allTime('All Time'),
  custom('Custom');

  final String label;
  const CollectionDatePreset(this.label);
}

enum CollectionViewMode { byMember, byMonth }

enum CollectionSortOrder {
  highestCollection('Highest Collection'),
  nameAZ('Name (A-Z)'),
  mostRecent('Most Recent');

  final String label;
  const CollectionSortOrder(this.label);
}

class CollectionHistoryReportScreen extends StatefulWidget {
  const CollectionHistoryReportScreen({super.key});

  @override
  State<CollectionHistoryReportScreen> createState() => _CollectionHistoryReportScreenState();
}

class _CollectionHistoryReportScreenState extends State<CollectionHistoryReportScreen> {
  CollectionDatePreset _selectedPreset = CollectionDatePreset.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;
  CollectionViewMode _viewMode = CollectionViewMode.byMember;
  CollectionSortOrder _sortOrder = CollectionSortOrder.highestCollection;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _applyPreset(CollectionDatePreset.thisMonth);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyPreset(CollectionDatePreset preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case CollectionDatePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        break;
      case CollectionDatePreset.last3Months:
        start = DateTime(now.year, now.month - 2, 1);
        break;
      case CollectionDatePreset.last6Months:
        start = DateTime(now.year, now.month - 5, 1);
        break;
      case CollectionDatePreset.thisYear:
        start = DateTime(now.year, 1, 1);
        break;
      case CollectionDatePreset.allTime:
        start = DateTime(2022, 1, 1);
        break;
      case CollectionDatePreset.custom:
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
      setState(() {
        _selectedPreset = CollectionDatePreset.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  List<MemberCollectionSummary> _filterAndSortMembers(List<MemberCollectionSummary> original) {
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
      case CollectionSortOrder.highestCollection:
        list.sort((a, b) => b.totalCollectedAmount.compareTo(a.totalCollectedAmount));
        break;
      case CollectionSortOrder.nameAZ:
        list.sort((a, b) => a.customer.name.toLowerCase().compareTo(b.customer.name.toLowerCase()));
        break;
      case CollectionSortOrder.mostRecent:
        list.sort((a, b) {
          final latestA = a.paidRecords.isNotEmpty ? a.paidRecords.first.paidAt ?? DateTime(2000) : DateTime(2000);
          final latestB = b.paidRecords.isNotEmpty ? b.paidRecords.first.paidAt ?? DateTime(2000) : DateTime(2000);
          return latestB.compareTo(latestA);
        });
        break;
    }

    return list;
  }

  List<MonthCollectionGroup> _filterMonthGroups(List<MonthCollectionGroup> original) {
    if (_searchQuery.trim().isEmpty) return original;
    final q = _searchQuery.toLowerCase().trim();

    final filteredGroups = <MonthCollectionGroup>[];
    for (final group in original) {
      final matchingItems = group.items.where((it) {
        return it.customer.name.toLowerCase().contains(q) || it.customer.phone.contains(q);
      }).toList();

      if (matchingItems.isNotEmpty) {
        final groupTotal = matchingItems.fold<double>(0.0, (s, it) => s + it.payment.amount);
        filteredGroups.add(MonthCollectionGroup(
          monthKey: group.monthKey,
          items: matchingItems,
          totalAmount: groupTotal,
        ));
      }
    }
    return filteredGroups;
  }

  void _viewReceipt(Customer customer, PaymentRecord payment) {
    // Find the bill for this payment
    final gym = GymService();
    final bills = gym.billsMap.values.where((b) =>
        b.paymentId == payment.id && b.isPaid).toList();

    if (bills.isNotEmpty) {
      BillReceiptDialog.show(context, bill: bills.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No bill receipt found for this payment.'),
          backgroundColor: AppColors.textSecondary,
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

        final rawMemberSummaries = gym.getCollectionsByMember(_startDate, _endDate);
        final rawMonthGroups = gym.getCollectionsByMonth(_startDate, _endDate);

        final totalCollected = rawMemberSummaries.fold<double>(0.0, (s, m) => s + m.totalCollectedAmount);
        final totalPayments = rawMemberSummaries.fold<int>(0, (s, m) => s + m.paidRecords.length);

        final memberSummaries = _filterAndSortMembers(rawMemberSummaries);
        final monthGroups = _filterMonthGroups(rawMonthGroups);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Collection History'),
            actions: const [
              SizedBox(width: 4),
            ],
          ),
          body: Column(
              children: [
                // Presets Filter Chips
                _buildPresetChips(),

                // Date Range Active Indicator
                _buildDateRangeHeader(),

                // Top KPI Summary Cards
                _buildKpiSection(totalCollected, rawMemberSummaries.length, totalPayments, currency),

                // Search, Sort & View Mode Bar
                _buildFilterAndModeBar(rawMemberSummaries.length),

                // Main Content List
                Expanded(
                  child: _viewMode == CollectionViewMode.byMember
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
        children: CollectionDatePreset.values.map((preset) {
          final isSelected = _selectedPreset == preset;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(preset.label),
              selected: isSelected,
              onSelected: (selected) {
                if (preset == CollectionDatePreset.custom) {
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

  Widget _buildKpiSection(double totalCollected, int membersCount, int paymentsCount, String currency) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          // Total collected amount
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
                        color: AppColors.paid,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TOTAL COLLECTED',
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
                  GymDateUtils.formatCurrency(totalCollected, symbol: currency),
                  style: const TextStyle(
                    color: AppColors.paid,
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
                  '$membersCount',
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
                  'PAYMENTS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$paymentsCount',
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
                      suffixIcon: VoiceSearchSuffix(
                        controller: _searchController,
                        voiceHint: 'Say member name or phone number...',
                        iconSize: 18,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        onClear: () => setState(() => _searchQuery = ''),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: AppColors.surface,
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
                        borderSide: BorderSide(color: AppColors.primary, width: 1.2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Sort Menu Button
              PopupMenuButton<CollectionSortOrder>(
                initialValue: _sortOrder,
                tooltip: 'Sort By',
                onSelected: (order) => setState(() => _sortOrder = order),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.surfaceBorder),
                ),
                itemBuilder: (ctx) => CollectionSortOrder.values.map((order) {
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
                  totalCount == 1 ? '1 member paid' : '$totalCount members paid',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 32,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewToggleButton('By Member', CollectionViewMode.byMember, Icons.person_rounded),
                    _buildViewToggleButton('By Month', CollectionViewMode.byMonth, Icons.calendar_view_month_rounded),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton(String title, CollectionViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
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

  Widget _buildByMemberView(List<MemberCollectionSummary> list, String currency) {
    if (list.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item = list[i];
        final customer = item.customer;

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
                    imageBase64: customer.imageBase64,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                              Flexible(
                                child: Text(
                                  customer.phone,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Total Collected Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        GymDateUtils.formatCurrency(item.totalCollectedAmount, symbol: currency),
                        style: const TextStyle(
                          color: AppColors.paid,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${item.paidRecords.length} ${item.paidRecords.length == 1 ? 'payment' : 'payments'}',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Paid period pills
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: item.paidRecords.map((rec) {
                  return GestureDetector(
                    onTap: () => _viewReceipt(customer, rec),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.paid.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.paid.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            GymDateUtils.formatMonthYearKey(rec.monthYear),
                            style: const TextStyle(
                              color: AppColors.paid,
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
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (rec.method != null) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _paymentMethodIcon(rec.method),
                              size: 10,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),
              Divider(color: AppColors.surfaceBorder.withValues(alpha: 0.6), height: 1),
              const SizedBox(height: 10),

              // Action Buttons Row
              Row(
                children: [
                  // Call Quick Button
                  Tooltip(
                    message: 'Call Member',
                    child: InkWell(
                      onTap: () => PhoneService().makeCall(
                        customer.phone,
                        context: context,
                        memberName: customer.name,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                        ),
                        child: Icon(Icons.call_rounded, size: 17, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // View Latest Receipt Button
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: () => _viewReceipt(customer, item.paidRecords.first),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.paid,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, size: 15),
                        label: const Text(
                          'View Receipt',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

  Widget _buildByMonthView(List<MonthCollectionGroup> groups, String currency) {
    if (groups.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.paid.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${GymDateUtils.formatCurrency(group.totalAmount, symbol: currency)} collected (${group.items.length})',
                        style: const TextStyle(
                          color: AppColors.paid,
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
                        imageBase64: customer.imageBase64,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(
                                  customer.phone,
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (payment.method != null) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    _paymentMethodIcon(payment.method),
                                    size: 11,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    PaymentRecord.methodLabel(payment.method),
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        GymDateUtils.formatCurrency(payment.amount, symbol: currency),
                        style: const TextStyle(
                          color: AppColors.paid,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Quick Call Icon
                      IconButton(
                        icon: Icon(Icons.call_rounded, color: AppColors.primary, size: 18),
                        tooltip: 'Call Member',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => PhoneService().makeCall(
                          customer.phone,
                          context: context,
                          memberName: customer.name,
                        ),
                      ),

                      // View Receipt Icon
                      IconButton(
                        icon: Icon(Icons.receipt_long_rounded, color: AppColors.paid, size: 18),
                        tooltip: 'View Receipt',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _viewReceipt(customer, payment),
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

  IconData _paymentMethodIcon(PaymentMethod? method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.payments_rounded;
      case PaymentMethod.gpay:
      case PaymentMethod.phonepe:
      case PaymentMethod.paytm:
      case PaymentMethod.upi:
        return Icons.phone_android_rounded;
      case PaymentMethod.card:
        return Icons.credit_card_rounded;
      case PaymentMethod.netBanking:
        return Icons.account_balance_rounded;
      case null:
        return Icons.payments_rounded;
    }
  }

  Widget _buildEmptyState() {
    final isSearching = _searchQuery.trim().isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 0 ? constraints.maxHeight : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (isSearching ? AppColors.textMuted : AppColors.textSecondary).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSearching ? Icons.search_off_rounded : Icons.receipt_long_rounded,
                        color: isSearching ? AppColors.textSecondary : AppColors.textMuted,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isSearching ? 'No Matching Members' : 'No Collections Found',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSearching
                          ? 'No payments found matching "$_searchQuery".'
                          : 'No payment collections found for this selected date range.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
