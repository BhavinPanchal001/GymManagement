import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/gym_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/charts/attendance_trend_chart.dart';
import '../../widgets/charts/expense_category_chart.dart';
import '../../widgets/charts/financial_trends_chart.dart';
import '../../widgets/charts/membership_donut_chart.dart';
import '../customers/expiring_members_sheet.dart';
import 'pending_payments_report_screen.dart';
import '../../utils/animation_utils.dart';
import '../../widgets/animations/animated_counter.dart';
import '../../widgets/animations/animated_fade_slide.dart';
import '../../widgets/animations/animated_pressable.dart';

enum AnalyticsCategoryFilter { all, financials, attendance, memberships }

class GymStatisticsScreen extends StatefulWidget {
  const GymStatisticsScreen({super.key});

  @override
  State<GymStatisticsScreen> createState() => _GymStatisticsScreenState();
}

class _GymStatisticsScreenState extends State<GymStatisticsScreen> {
  AnalyticsCategoryFilter _selectedFilter = AnalyticsCategoryFilter.all;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final currency = gym.settings.currencySymbol;
        final summary = gym.getMembershipExpirySummary();

        final liveMembers = summary['live'] as List<Customer>;
        final expiring1to3 = summary['expiring1to3'] as List<Customer>;
        final expiring4to7 = summary['expiring4to7'] as List<Customer>;
        final expiring8to15 = summary['expiring8to15'] as List<Customer>;
        final expiredMembers = summary['expired'] as List<Customer>;

        final totalActive = summary['totalActive'] as int;
        final totalCustomers = gym.customers.length;
        final inactiveCount = totalCustomers - totalActive;

        final todayCollection = summary['todayCollection'] as double;
        final todayExpense = summary['todayExpense'] as double;
        final todayNet = todayCollection - todayExpense;

        final totalDues = summary['totalDues'] as double;
        final currentMonthProfit = summary['currentMonthProfit'] as double;
        final currentMonthIncome = summary['currentMonthIncome'] as double;
        final currentMonthExpense = summary['currentMonthExpense'] as double;

        // Current month expense breakdown
        final currentMonthKey = GymDateUtils.toMonthKey(DateTime.now());
        final expenseBreakdown = gym.getExpenseCategoryBreakdown(currentMonthKey);

        // Daily Attendance Overview
        final todayKey = GymDateUtils.toDateKey(DateTime.now());
        final dailyAtt = gym.getDailyOverview(todayKey);
        final presentToday = dailyAtt['present'] ?? 0;
        final attendanceRate = totalActive > 0 ? (presentToday / totalActive * 100).round() : 0;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Gym Analytics'),
            centerTitle: false,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 15, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Live Metrics',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Gym Overview Banner Card
                AnimatedFadeSlide(
                  offset: const Offset(0, -0.05),
                  child: _buildOverviewBanner(
                    gymName: gym.settings.gymName,
                    totalMembers: totalCustomers,
                    activeMembers: totalActive,
                    inactiveMembers: inactiveCount,
                    presentToday: presentToday,
                    attendanceRate: attendanceRate,
                  ),
                ),

                const SizedBox(height: 16),

                // 2. Filter Category Pills
                _buildCategoryFilterPills(),

                const SizedBox(height: 18),

                // 3. Financial Performance & Trends Section
                if (_selectedFilter == AnalyticsCategoryFilter.all ||
                    _selectedFilter == AnalyticsCategoryFilter.financials) ...[
                  _buildSectionHeader(
                    title: 'Financial Analytics & Trends',
                    subtitle: 'Revenue vs Expenses, Profit trajectory & Cost allocation',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: 10),

                  // Financial KPI Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildFinancialMetricBox(
                          title: 'Total Revenue',
                          subtitle: 'Month collections',
                          amount: currentMonthIncome,
                          currency: currency,
                          color: AppColors.paid,
                          icon: Icons.trending_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFinancialMetricBox(
                          title: 'Total Expenses',
                          subtitle: 'Month expenses',
                          amount: currentMonthExpense,
                          currency: currency,
                          color: AppColors.absent,
                          icon: Icons.trending_down_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildFinancialMetricBox(
                          title: currentMonthProfit >= 0 ? 'Month Net Profit' : 'Month Net Loss',
                          subtitle: currentMonthProfit >= 0 ? 'Surplus income' : 'Operating deficit',
                          amount: currentMonthProfit.abs(),
                          currency: currency,
                          color: currentMonthProfit >= 0 ? AppColors.paid : AppColors.absent,
                          icon: currentMonthProfit >= 0 ? Icons.savings_rounded : Icons.warning_amber_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedPressable(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PendingPaymentsReportScreen(),
                              ),
                            );
                          },
                          child: _buildFinancialMetricBox(
                            title: 'Pending Dues',
                            subtitle: 'Tap to view report',
                            amount: totalDues,
                            currency: currency,
                            color: AppColors.pending,
                            icon: Icons.history_rounded,
                            showArrow: true,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // VISUAL GRAPH 1: Financial Trends (Bar & Line Chart)
                  FinancialTrendsChart(
                    gym: gym,
                    currency: currency,
                  ),

                  const SizedBox(height: 14),

                  // VISUAL GRAPH 2: Expense Category Breakdown (Donut Chart)
                  ExpenseCategoryChart(
                    breakdown: expenseBreakdown,
                    totalExpense: currentMonthExpense,
                    currency: currency,
                  ),

                  const SizedBox(height: 14),

                  // Daily Operations (Today)
                  _buildSectionHeader(
                    title: 'Daily Operations (Today)',
                    subtitle: 'Real-time daily collection and operational expenses',
                    icon: Icons.today_rounded,
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildFinancialMetricBox(
                          title: "Today's Collection",
                          subtitle: 'Cash & online inflow',
                          amount: todayCollection,
                          currency: currency,
                          color: AppColors.paid,
                          icon: Icons.arrow_downward_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFinancialMetricBox(
                          title: "Today's Expense",
                          subtitle: 'Operating costs out',
                          amount: todayExpense,
                          currency: currency,
                          color: AppColors.absent,
                          icon: Icons.arrow_upward_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  _buildNetFlowTile(
                    title: "Today's Net Cash Flow",
                    subtitle: 'Collection minus Expense today',
                    amount: GymDateUtils.formatCurrency(todayNet.abs(), symbol: currency),
                    isPositive: todayNet >= 0,
                    currency: currency,
                  ),

                  const SizedBox(height: 24),
                ],

                // 4. Attendance Trends Section
                if (_selectedFilter == AnalyticsCategoryFilter.all ||
                    _selectedFilter == AnalyticsCategoryFilter.attendance) ...[
                  _buildSectionHeader(
                    title: 'Attendance Analytics',
                    subtitle: 'Member turnout consistency & footfall patterns',
                    icon: Icons.calendar_today_rounded,
                  ),
                  const SizedBox(height: 10),

                  // Today's Turnout Health Meter
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.people_outline_rounded, color: AppColors.primary, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$presentToday Members Present Today',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'Out of $totalActive active members',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.paid.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$attendanceRate% Turnout',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.paid,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0.0,
                              end: totalActive > 0 ? (presentToday / totalActive).clamp(0.0, 1.0) : 0.0,
                            ),
                            duration: AppAnimations.contentDuration,
                            curve: Curves.easeOutCubic,
                            builder: (context, val, _) => LinearProgressIndicator(
                              value: val,
                              backgroundColor: AppColors.surfaceBorder,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // VISUAL GRAPH 3: Daily Attendance Trend (Line Chart)
                  AttendanceTrendChart(gym: gym),

                  const SizedBox(height: 24),
                ],

                // 5. Membership Expiry Funnel Section
                if (_selectedFilter == AnalyticsCategoryFilter.all ||
                    _selectedFilter == AnalyticsCategoryFilter.memberships) ...[
                  _buildSectionHeader(
                    title: 'Membership Health & Funnel',
                    subtitle: 'Donut distribution & actionable renewal stages',
                    icon: Icons.filter_alt_outlined,
                  ),
                  const SizedBox(height: 10),

                  // VISUAL GRAPH 4: Membership Donut Chart
                  MembershipDonutChart(
                    liveMembers: liveMembers,
                    expiring1to3: expiring1to3,
                    expiring4to7: expiring4to7,
                    expiring8to15: expiring8to15,
                    expiredMembers: expiredMembers,
                    inactiveCount: inactiveCount,
                    totalMembers: totalCustomers,
                    onSelectStage: (title, subtitle, members, color, icon) {
                      ExpiringMembersSheet.show(
                        context,
                        title: title,
                        subtitle: subtitle,
                        members: members,
                        accentColor: color,
                        icon: icon,
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  // Expiry funnel action cards list
                  _buildExpiryTile(
                    context: context,
                    title: 'Live Active Members',
                    subtitle: 'Healthy active memberships (> 15 days remaining)',
                    count: liveMembers.length,
                    badgeText: 'Active',
                    accentColor: AppColors.paid,
                    icon: Icons.verified_user_rounded,
                    members: liveMembers,
                  ),
                  const SizedBox(height: 8),

                  _buildExpiryTile(
                    context: context,
                    title: 'Expiring in 1–3 Days',
                    subtitle: 'Urgent renewal needed within 72 hours',
                    count: expiring1to3.length,
                    badgeText: 'Urgent',
                    accentColor: const Color(0xFFFF5252),
                    icon: Icons.alarm_rounded,
                    members: expiring1to3,
                    isUrgent: expiring1to3.isNotEmpty,
                  ),
                  const SizedBox(height: 8),

                  _buildExpiryTile(
                    context: context,
                    title: 'Expiring in 4–7 Days',
                    subtitle: 'Memberships expiring within this week',
                    count: expiring4to7.length,
                    badgeText: 'This Week',
                    accentColor: const Color(0xFFFF9100),
                    icon: Icons.upcoming_rounded,
                    members: expiring4to7,
                  ),
                  const SizedBox(height: 8),

                  _buildExpiryTile(
                    context: context,
                    title: 'Expiring in 8–15 Days',
                    subtitle: 'Upcoming renewals within the next two weeks',
                    count: expiring8to15.length,
                    badgeText: 'Upcoming',
                    accentColor: const Color(0xFF448AFF),
                    icon: Icons.calendar_month_rounded,
                    members: expiring8to15,
                  ),
                  const SizedBox(height: 8),

                  _buildExpiryTile(
                    context: context,
                    title: 'Expired Memberships',
                    subtitle: 'Past expiry date, eligible for reactivation',
                    count: expiredMembers.length,
                    badgeText: 'Expired',
                    accentColor: const Color(0xFFD50000),
                    icon: Icons.cancel_rounded,
                    members: expiredMembers,
                    isUrgent: expiredMembers.isNotEmpty,
                  ),

                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Category Filter Pills ---

  Widget _buildCategoryFilterPills() {
    final filters = [
      (AnalyticsCategoryFilter.all, 'All Analytics', Icons.dashboard_rounded),
      (AnalyticsCategoryFilter.financials, 'Financials', Icons.bar_chart_rounded),
      (AnalyticsCategoryFilter.attendance, 'Attendance', Icons.insights_rounded),
      (AnalyticsCategoryFilter.memberships, 'Memberships', Icons.pie_chart_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedPressable(
              onTap: () => setState(() => _selectedFilter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      f.$3,
                      size: 14,
                      color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- Sub-widgets & Builders ---

  Widget _buildOverviewBanner({
    required String gymName,
    required int totalMembers,
    required int activeMembers,
    required int inactiveMembers,
    required int presentToday,
    required int attendanceRate,
  }) {
    final activeRate = totalMembers > 0 ? (activeMembers / totalMembers * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fitness_center_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gymName.isNotEmpty ? gymName : 'My Gym',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Membership & Financial Intelligence',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.paid.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.paid.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$activeRate% Active',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.paid,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.surfaceBorder, height: 1),
          const SizedBox(height: 14),

          // 3 key counts
          Row(
            children: [
              Expanded(
                child: _buildBannerStat(
                  label: 'Total Members',
                  count: totalMembers,
                  icon: Icons.groups_rounded,
                  color: AppColors.primary,
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.surfaceBorder),
              Expanded(
                child: _buildBannerStat(
                  label: 'Active',
                  count: activeMembers,
                  icon: Icons.check_circle_rounded,
                  color: AppColors.paid,
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.surfaceBorder),
              Expanded(
                child: _buildBannerStat(
                  label: 'Inactive',
                  count: inactiveMembers,
                  icon: Icons.pause_circle_rounded,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBannerStat({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            AnimatedCounter(
              value: count,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiryTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int count,
    required String badgeText,
    required Color accentColor,
    required IconData icon,
    required List<Customer> members,
    bool isUrgent = false,
  }) {
    return AnimatedPressable(
      onTap: () {
        ExpiringMembersSheet.show(
          context,
          title: title,
          subtitle: subtitle,
          members: members,
          accentColor: accentColor,
          icon: icon,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUrgent ? accentColor.withValues(alpha: 0.6) : AppColors.surfaceBorder,
            width: isUrgent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialMetricBox({
    required String title,
    required String subtitle,
    required double amount,
    required String currency,
    required Color color,
    required IconData icon,
    bool showArrow = false,
  }) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              if (showArrow)
                Icon(Icons.arrow_forward_ios_rounded, color: color, size: 12),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedCounter(
              value: amount,
              prefix: '$currency ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildNetFlowTile({
    required String title,
    required String subtitle,
    required String amount,
    required bool isPositive,
    required String currency,
  }) {
    final color = isPositive ? AppColors.paid : AppColors.absent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPositive ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${isPositive ? '+' : '-'}$amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
