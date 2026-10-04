import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/gym_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../utils/animation_utils.dart';
import '../utils/date_utils.dart';
import '../screens/customers/expiring_members_sheet.dart';
import '../screens/reports/gym_statistics_screen.dart';
import '../screens/reports/pending_payments_report_screen.dart';
import 'animations/animated_counter.dart';
import 'animations/animated_fade_slide.dart';
import 'animations/animated_pressable.dart';
import 'animations/app_page_route.dart';

class DashboardMetricsGrid extends StatefulWidget {
  final VoidCallback? onNavigateToBilling;

  const DashboardMetricsGrid({
    super.key,
    this.onNavigateToBilling,
  });

  @override
  State<DashboardMetricsGrid> createState() => _DashboardMetricsGridState();
}

class _DashboardMetricsGridState extends State<DashboardMetricsGrid> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final currency = gym.settings.currencySymbol;
        final summary = gym.getMembershipExpirySummary();

        final expiring1to3 = summary['expiring1to3'] as List<Customer>;
        final expiring4to7 = summary['expiring4to7'] as List<Customer>;
        final totalActive = summary['totalActive'] as int;
        final totalDues = summary['totalDues'] as double;

        final int urgentRenewalCount = expiring1to3.length;
        final int dueSoonCount = expiring1to3.length + expiring4to7.length;

        return AnimatedContainer(
          duration: AppAnimations.normalDuration,
          curve: AppAnimations.curveEaseInOut,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title, All Stats Button & Expand/Collapse
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.dashboard_customize_outlined, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gym Overview',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // "All Stats" Button to open dedicated statistics page
                    AnimatedPressable(
                      onTap: () {
                        Navigator.push(
                          context,
                          AppPageRoute(
                            builder: (_) => const GymStatisticsScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'All Stats',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Collapse / Expand toggle button with smooth rotation
                    IconButton(
                      icon: AnimatedRotation(
                        turns: _isExpanded ? 0.0 : 0.5,
                        duration: AppAnimations.normalDuration,
                        curve: AppAnimations.curveEaseInOut,
                        child: Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                      onPressed: () => setState(() => _isExpanded = !_isExpanded),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              AnimatedSize(
                duration: AppAnimations.normalDuration,
                curve: AppAnimations.curveEaseInOut,
                alignment: Alignment.topCenter,
                child: _isExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(color: AppColors.surfaceBorder, height: 1),
                          const SizedBox(height: 12),

                          // Top 3 Most Important Metrics
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                            child: Row(
                              children: [
                                // 1. Active Members
                                Expanded(
                                  child: AnimatedFadeSlide.staggered(
                                    index: 0,
                                    child: _buildMetricCard(
                                      title: 'Active',
                                      numericValue: totalActive,
                                      value: '$totalActive',
                                      subtitle: 'Live members',
                                      icon: Icons.groups_rounded,
                                      color: AppColors.paid,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          AppPageRoute(
                                            builder: (_) => const GymStatisticsScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 2. Expiring Soon (1-7 Days)
                                Expanded(
                                  child: AnimatedFadeSlide.staggered(
                                    index: 1,
                                    child: _buildMetricCard(
                                      title: 'Due Soon',
                                      numericValue: dueSoonCount,
                                      value: '$dueSoonCount',
                                      subtitle: urgentRenewalCount > 0 ? '$urgentRenewalCount urgent' : 'Next 7 days',
                                      icon: Icons.alarm_rounded,
                                      color: urgentRenewalCount > 0 ? const Color(0xFFFF5252) : const Color(0xFFFF9100),
                                      isUrgent: urgentRenewalCount > 0,
                                      onTap: () {
                                        final dueMembers = [...expiring1to3, ...expiring4to7];
                                        if (dueMembers.isNotEmpty) {
                                          ExpiringMembersSheet.show(
                                            context,
                                            title: 'Members Due for Renewal',
                                            subtitle: 'Memberships expiring within 7 days',
                                            members: dueMembers,
                                            accentColor: urgentRenewalCount > 0 ? const Color(0xFFFF5252) : const Color(0xFFFF9100),
                                            icon: Icons.alarm_rounded,
                                          );
                                        } else {
                                          Navigator.push(
                                            context,
                                            AppPageRoute(
                                              builder: (_) => const GymStatisticsScreen(),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 3. Pending Dues
                                Expanded(
                                  child: AnimatedFadeSlide.staggered(
                                    index: 2,
                                    child: _buildMetricCard(
                                      title: 'Pending Dues',
                                      numericValue: totalDues,
                                      prefix: currency,
                                      value: GymDateUtils.formatCurrency(totalDues, symbol: currency),
                                      subtitle: 'Tap for report',
                                      icon: Icons.history_rounded,
                                      color: AppColors.pending,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          AppPageRoute(
                                            builder: (_) => const PendingPaymentsReportScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    num? numericValue,
    String prefix = '',
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isUrgent = false,
  }) {
    return AnimatedPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUrgent ? color.withValues(alpha: 0.6) : AppColors.surfaceBorder,
            width: isUrgent ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 10,
                  color: AppColors.textMuted.withValues(alpha: 0.6),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: numericValue != null
                  ? AnimatedCounter(
                      value: numericValue,
                      prefix: prefix,
                      decimalPlaces: (numericValue is int || numericValue % 1 == 0) ? 0 : 2,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: -0.3,
                      ),
                    )
                  : Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: -0.3,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isUrgent ? color : AppColors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

