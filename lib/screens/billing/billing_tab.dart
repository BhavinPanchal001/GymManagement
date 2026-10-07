import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/theme_service.dart';
import '../../services/whatsapp_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/bill_history_sheet.dart';
import '../../widgets/collect_balance_dialog.dart';
import '../../widgets/bill_receipt_dialog.dart';
import '../customers/customer_detail_screen.dart';
import '../reports/pending_payments_report_screen.dart';
import '../reports/gym_statistics_screen.dart';
import 'expense_tab.dart';
import 'balance_sheet_tab.dart';
import '../../widgets/voice_search_suffix.dart';
import '../../utils/animation_utils.dart';
import '../../widgets/animations/animated_counter.dart';
import '../../widgets/animations/animated_empty_state.dart';
import '../../widgets/animations/animated_fade_slide.dart';
import '../../widgets/animations/animated_pressable.dart';
import '../../widgets/animations/app_page_route.dart';

enum BillingFilter { all, pending, paid }

class BillingTab extends StatefulWidget {
  final int? sectionIndex;
  final ValueChanged<int>? onSectionSelected;

  const BillingTab({super.key, this.sectionIndex, this.onSectionSelected})
    : assert((sectionIndex == null) == (onSectionSelected == null)),
      assert(sectionIndex == null || (sectionIndex >= 0 && sectionIndex <= 2));

  @override
  State<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends State<BillingTab> {
  late DateTime _selectedMonth;
  BillingFilter _filter = BillingFilter.all;
  int _localBillingSection = 0;
  // HomeScreen owns this selection when it is tracking phone back navigation.
  int get _billingSection => widget.sectionIndex ?? _localBillingSection;
  final TextEditingController _searchController = TextEditingController();

  void _selectSection(int section) {
    if (section == _billingSection) return;
    final onSectionSelected = widget.onSectionSelected;
    if (onSectionSelected != null) {
      onSectionSelected(section);
    } else {
      setState(() => _localBillingSection = section);
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final monthKey = GymDateUtils.toMonthKey(_selectedMonth);
        final currency = gym.settings.currencySymbol;
        final summary = gym.getMonthlyFinancialSummary(monthKey);
        final totalMembers = summary['totalMembers'] as int;
        final totalExpected = summary['totalExpected'] as double;
        final totalCollected = summary['totalCollected'] as double;
        final totalPending = summary['totalPending'] as double;
        final paidCount = summary['paidCount'] as int;
        final pendingCount = summary['pendingCount'] as int;
        final progress = totalExpected > 0 ? (totalCollected / totalExpected).clamp(0.0, 1.0) : 0.0;

        final dueIds = <String>{};
        for (final g in gym.getPendingDuesByMonth(
            DateTime(_selectedMonth.year, _selectedMonth.month, 1),
            DateTime(_selectedMonth.year, _selectedMonth.month,
                GymDateUtils.daysInMonth(_selectedMonth.year, _selectedMonth.month)))) {
          if (g.monthKey == monthKey) {
            for (final it in g.items) {
              dueIds.add(it.customer.id);
            }
          }
        }

        // Active members + archived members with billing records (dues or payments) for this month
        var customers = gym.customers.where((c) {
          if (c.isActive) return true;
          return dueIds.contains(c.id) || gym.isMonthCoveredByPaidPayment(c.id, monthKey);
        }).toList();
        if (_filter == BillingFilter.pending) {
          customers = customers.where((c) => dueIds.contains(c.id)).toList();
        } else if (_filter == BillingFilter.paid) {
          customers = customers
              .where((c) => gym.isMonthCoveredByPaidPayment(c.id, monthKey))
              .toList();
        }
        final searchQuery = _searchController.text.trim().toLowerCase();
        if (searchQuery.isNotEmpty) {
          customers = customers.where((c) {
            return c.name.toLowerCase().contains(searchQuery) ||
                c.phone.contains(searchQuery) ||
                c.cardNumber.toLowerCase().contains(searchQuery);
          }).toList();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Payments & Billing'),
            actions: [
              IconButton(
                icon: Icon(Icons.insights_rounded, color: AppColors.primary),
                tooltip: 'Gym Analytics & Statistics',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const GymStatisticsScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                tooltip: 'Pending Dues Report',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingPaymentsReportScreen(),
                    ),
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Text(
                      'Fee: ${GymDateUtils.formatCurrency(gym.settings.standardMonthlyFee, symbol: currency)}/mo',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Month Selector Bar and section tabs are hidden while the keyboard
              // is open so the search field and results fit on small screens.
              if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
              // Month Selector Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_note_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          GymDateUtils.formatMonthYearKey(monthKey),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left_rounded, color: AppColors.textPrimary),
                          onPressed: _prevMonth,
                          tooltip: 'Previous Month',
                        ),
                        IconButton(
                          icon: Icon(Icons.chevron_right_rounded, color: AppColors.textPrimary),
                          onPressed: _nextMonth,
                          tooltip: 'Next Month',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Segmented Sub-Navigation: Collections | Expenses | Balance Sheet
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildSectionTabItem(
                        index: 0,
                        title: 'Collections',
                        icon: Icons.payments_outlined,
                        badge: '$paidCount/$totalMembers',
                      ),
                      _buildSectionTabItem(
                        index: 1,
                        title: 'Expenses',
                        icon: Icons.receipt_long_outlined,
                        badge: '${gym.getMonthlyExpenses(monthKey).length}',
                      ),
                      _buildSectionTabItem(
                        index: 2,
                        title: 'Balance Sheet',
                        icon: Icons.account_balance_outlined,
                        badge: null,
                      ),
                    ],
                  ),
                ),
              ),
              ],

              if (_billingSection == 1)
                Expanded(
                  child: ExpenseTab(
                    selectedMonth: _selectedMonth,
                    onPrevMonth: _prevMonth,
                    onNextMonth: _nextMonth,
                  ),
                )
              else if (_billingSection == 2)
                Expanded(
                  child: BalanceSheetTab(
                    selectedMonth: _selectedMonth,
                    onSwitchToExpenses: () => _selectSection(1),
                  ),
                )
              else ...[
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
                      suffixIcon: VoiceSearchSuffix(
                        controller: _searchController,
                        voiceHint: 'Say member name, phone, or card number...',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildFilterChip('All ($totalMembers)', BillingFilter.all),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending ($pendingCount)', BillingFilter.pending),
                      const SizedBox(width: 8),
                      _buildFilterChip('Paid ($paidCount)', BillingFilter.paid),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Summary Card
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: AppColors.isDark
                                      ? const [Color(0xFF19222E), Color(0xFF131922)]
                                      : const [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.surfaceBorder),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: AppColors.isDark ? 0.25 : 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildStatBox(
                                          'Collected',
                                          totalCollected,
                                          GymDateUtils.formatCurrency(totalCollected, symbol: currency),
                                          AppColors.paid,
                                          '$paidCount paid',
                                          prefix: currency,
                                        ),
                                      ),
                                      Container(width: 1, height: 40, color: AppColors.surfaceBorder),
                                      Expanded(
                                        child: _buildStatBox(
                                          'Pending Dues',
                                          totalPending,
                                          GymDateUtils.formatCurrency(totalPending, symbol: currency),
                                          AppColors.pending,
                                          '$pendingCount pending',
                                          prefix: currency,
                                        ),
                                      ),
                                      Container(width: 1, height: 40, color: AppColors.surfaceBorder),
                                      Expanded(
                                        child: _buildStatBox(
                                          'Total Expected',
                                          totalExpected,
                                          GymDateUtils.formatCurrency(totalExpected, symbol: currency),
                                          AppColors.textPrimary,
                                          '$totalMembers members',
                                          prefix: currency,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  // Progress Bar
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0.0, end: progress),
                                      duration: AppAnimations.normalDuration,
                                      curve: AppAnimations.curveEaseOut,
                                      builder: (context, animatedVal, _) {
                                        return LinearProgressIndicator(
                                          value: animatedVal,
                                          minHeight: 8,
                                          backgroundColor: AppColors.surfaceBorder,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            animatedVal >= 0.8
                                                ? AppColors.paid
                                                : animatedVal >= 0.5
                                                    ? AppColors.pending
                                                    : AppColors.absent,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Collection Rate: ',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          AnimatedCounter(
                                            value: progress * 100,
                                            suffix: '%',
                                            decimalPlaces: 1,
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '$paidCount of $totalMembers Cleared',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Multi-Month Pending Dues Banner
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PendingPaymentsReportScreen(),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: AppColors.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.pending.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.history_rounded, color: AppColors.pending, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Overdue & Pending Tracker',
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              'Track pending dues across months with 1-tap reminders',
                                              style: TextStyle(
                                                color: AppColors.textMuted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                      if (customers.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: AnimatedEmptyState(
                            icon: Icons.payments_outlined,
                            title: searchQuery.isNotEmpty
                                ? 'No members found matching "${_searchController.text.trim()}"'
                                : _filter == BillingFilter.pending
                                    ? 'All member payments are cleared for this month!'
                                    : 'No records found for this month.',
                            subtitle: searchQuery.isNotEmpty
                                ? 'Check spelling or search by phone/card number'
                                : _filter == BillingFilter.pending
                                    ? 'Outstanding! 100% of memberships are settled for this cycle.'
                                    : null,
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          sliver: SliverList.separated(
                            itemCount: customers.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final customer = customers[i];
                              final payment = gym.getPaymentRecord(customer.id, monthKey);
                              final attendanceSummary = gym.getMonthlyAttendanceSummary(customer.id, monthKey);
                              final presentDays = attendanceSummary['present'] ?? 0;

                              return AnimatedFadeSlide.staggered(
                                index: i,
                                maxStaggerIndex: 6,
                                child: _buildBillingRow(
                                  customer,
                                  payment,
                                  monthKey,
                                  presentDays,
                                  currency,
                                  dueIds.contains(customer.id),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTabItem({
    required int index,
    required String title,
    required IconData icon,
    String? badge,
  }) {
    final isSelected = _billingSection == index;
    return Expanded(
      child: AnimatedPressable(
        onTap: () => _selectSection(index),
        child: AnimatedContainer(
          duration: AppAnimations.microDuration,
          curve: AppAnimations.curveEaseInOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryOn.withValues(alpha: 0.2)
                        : AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isSelected ? AppColors.primaryOn : AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String title, num? numericAmount, String amount, Color color, String sub, {String prefix = ''}) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: numericAmount != null
              ? AnimatedCounter(
                  value: numericAmount,
                  prefix: prefix,
                  decimalPlaces: (numericAmount is int || numericAmount % 1 == 0) ? 0 : 2,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
                )
              : Text(
                  amount,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, BillingFilter filter) {
    final isSelected = _filter == filter;
    return AnimatedPressable(
      onTap: () {
        setState(() => _filter = filter);
      },
      child: AnimatedContainer(
        duration: AppAnimations.microDuration,
        curve: AppAnimations.curveEaseInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildBillingRow(
    Customer customer,
    PaymentRecord payment,
    String monthKey,
    int presentDays,
    String currency,
    bool isDue,
  ) {
    final isPaid = payment.isPaid;

    return AnimatedPressable(
      onTap: () {
        Navigator.push(
          context,
          AppPageRoute(
            builder: (_) => CustomerDetailScreen(customerId: customer.id),
          ),
        );
      },
      child: AnimatedContainer(
        duration: AppAnimations.normalDuration,
        curve: AppAnimations.curveEaseInOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPaid ? AppColors.surfaceBorder : AppColors.pending.withValues(alpha: 0.4),
            width: isPaid ? 1 : 1.2,
          ),
        ),
        child: Column(
          children: [
            // Top Section: Avatar, Customer Name & Amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomerAvatar(
                  imagePath: customer.imagePath,
                  imageBase64: customer.imageBase64,
                  name: customer.name,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              customer.name,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!customer.isActive) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.pending.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.pending.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.archive_outlined,
                                    size: 10,
                                    color: AppColors.pending,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'ARCHIVED',
                                    style: TextStyle(
                                      color: AppColors.pending,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: presentDays > 0 ? AppColors.paid : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$presentDays days attended in ${GymDateUtils.formatMonthYearKey(monthKey).split(' ').first}',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      GymDateUtils.formatCurrency(payment.displayAmount, symbol: currency),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: (isPaid && payment.balanceDue > 0)
                          ? () async {
                              final current = GymService().getPaymentById(payment.id) ?? payment;
                              final bill = await CollectBalanceDialog.show(context, current);
                              if (bill != null && mounted) {
                                await BillReceiptDialog.show(context, bill: bill);
                              }
                            }
                          : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? AppColors.paid.withValues(alpha: 0.15)
                              : (isDue
                                  ? AppColors.pending.withValues(alpha: 0.15)
                                  : AppColors.surfaceElevated),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isPaid
                                ? AppColors.paid.withValues(alpha: 0.5)
                                : (isDue
                                    ? AppColors.pending.withValues(alpha: 0.5)
                                    : AppColors.surfaceBorder),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isPaid
                              ? (payment.isPartiallyPaid
                                  ? 'PARTIAL · BAL ${GymDateUtils.formatCurrency(payment.balanceDue, symbol: currency)}'
                                  : 'PAID')
                              : (isDue ? 'PENDING' : 'NOT DUE'),
                          style: TextStyle(
                            color: isPaid
                                ? AppColors.paid
                                : (isDue ? AppColors.pending : AppColors.textMuted),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Container(height: 1, color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
            const SizedBox(height: 10),

            // Bottom Section: Payment Mode / Status info + Action Button
            Row(
              children: [
                Expanded(
                  child: isPaid && payment.method != null
                      ? Row(
                          children: [
                            const Icon(Icons.verified_rounded, size: 14, color: AppColors.paid),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Via ${payment.method!.label}'
                                '${payment.paidAt != null ? ' (${GymDateUtils.formatShortDate(payment.paidAt!)})' : ''}',
                                style: const TextStyle(
                                  color: AppColors.paid,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(Icons.pending_actions_rounded, size: 14, color: isDue ? AppColors.pending : AppColors.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isDue ? 'Due this month' :
                                    payment.isMembershipAgreement && payment.balanceDue > 0
                                        ? 'Fee due in ${GymDateUtils.formatMonthYearKey(payment.monthYear)}'
                                        : 'No unpaid attendance yet',
                                style: TextStyle(
                                  color: isDue ? AppColors.pending : AppColors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                if (!isPaid && isDue) ...[
                  OutlinedButton.icon(
                    onPressed: () {
                      WhatsAppService().showReminderSheet(
                        context: context,
                        customer: customer,
                        monthYear: monthKey,
                        amount: GymService().pendingAmountOf(payment),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.whatsapp.withValues(alpha: 0.12),
                      foregroundColor: AppColors.whatsapp,
                      side: BorderSide(color: AppColors.whatsapp.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 13, color: AppColors.whatsapp),
                    label: const Text(
                      'Remind',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.whatsapp,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isPaid) ...[
                  OutlinedButton.icon(
                    onPressed: () => BillHistorySheet.showForPayment(
                      context,
                      customer: customer,
                      payment: payment,
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.paid.withValues(alpha: 0.1),
                      foregroundColor: AppColors.paid,
                      side: BorderSide(color: AppColors.paid.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 13, color: AppColors.paid),
                    label: const Text(
                      'Bill',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.paid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: () {
                      MarkPaymentDialog.show(
                        context,
                        customer: customer,
                        monthYear: monthKey,
                        currentRecord: payment,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surfaceElevated,
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(
                      Icons.edit_note_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    label: Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      MarkPaymentDialog.show(
                        context,
                        customer: customer,
                        monthYear: monthKey,
                        currentRecord: payment,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.primaryOn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide.none,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.primaryOn,
                    ),
                    label: Text(
                      'Mark Paid',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryOn,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (isPaid && payment.balanceDue > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final current = GymService().getPaymentById(payment.id) ?? payment;
                    final bill = await CollectBalanceDialog.show(context, current);
                    if (bill != null && mounted) {
                      await BillReceiptDialog.show(context, bill: bill);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pending,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  icon: const Icon(Icons.payments_rounded, size: 16),
                  label: Text(
                    'Collect Balance ${GymDateUtils.formatCurrency(payment.balanceDue, symbol: currency)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
