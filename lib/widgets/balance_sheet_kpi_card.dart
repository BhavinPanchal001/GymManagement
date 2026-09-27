import 'package:flutter/material.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

class BalanceSheetKPICard extends StatelessWidget {
  final String monthYear;

  const BalanceSheetKPICard({
    super.key,
    required this.monthYear,
  });

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final currency = gym.settings.currencySymbol;
    final kpi = gym.getBalanceSheetKPIs(monthYear);

    final double profitMargin = kpi['profitMargin'] as double;
    final bool isProfit = kpi['isProfit'] as bool;
    final double arpm = kpi['arpm'] as double;
    final double costPerMember = kpi['costPerMember'] as double;
    final double oer = kpi['oer'] as double;
    final int breakEvenMembers = kpi['breakEvenMembers'] as int;
    final int memberBuffer = kpi['memberBuffer'] as int;
    final double breakEvenLoadPct = (kpi['breakEvenLoadPct'] as double).clamp(0.0, 100.0);

    final double fixedCosts = kpi['fixedCosts'] as double;
    final double variableCosts = kpi['variableCosts'] as double;
    final double fixedCostPct = kpi['fixedCostPct'] as double;
    final double variableCostPct = kpi['variableCostPct'] as double;

    final double revGrowthMoM = kpi['revenueGrowthMoM'] as double;
    final double expGrowthMoM = kpi['expenseGrowthMoM'] as double;
    final double profitGrowthMoM = kpi['profitGrowthMoM'] as double;

    final String healthTier = kpi['healthTier'] as String;
    final String healthTitle = kpi['healthTitle'] as String;
    final String healthAdvice = kpi['healthAdvice'] as String;

    Color tierColor;
    IconData tierIcon;
    switch (healthTier) {
      case 'exceptional':
        tierColor = const Color(0xFF00E5FF); // Electric Cyan
        tierIcon = Icons.diamond_outlined;
        break;
      case 'healthy':
        tierColor = AppColors.paid; // Emerald Green
        tierIcon = Icons.check_circle_outline;
        break;
      case 'tight':
        tierColor = AppColors.pending; // Amber
        tierIcon = Icons.warning_amber_rounded;
        break;
      case 'deficit':
        tierColor = const Color(0xFFD50000); // Red
        tierIcon = Icons.error_outline;
        break;
      default:
        tierColor = AppColors.textMuted;
        tierIcon = Icons.info_outline;
    }

    return Container(
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & Health Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(tierIcon, color: tierColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Executive Financial KPIs',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Unit Economics & Operational Sustainability',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tierColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: tierColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      healthTitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: tierColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Smart Financial Advice Callout Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: tierColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    healthAdvice,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Month-Over-Month (MoM) Growth Comparison Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMoMItem(
                    label: 'Collections MoM',
                    pct: revGrowthMoM,
                    isGoodIfPositive: true,
                  ),
                ),
                Container(width: 1, height: 26, color: AppColors.surfaceBorder),
                Expanded(
                  child: _buildMoMItem(
                    label: 'Expenses MoM',
                    pct: expGrowthMoM,
                    isGoodIfPositive: false, // lower expense growth is better
                  ),
                ),
                Container(width: 1, height: 26, color: AppColors.surfaceBorder),
                Expanded(
                  child: _buildMoMItem(
                    label: 'Net Profit MoM',
                    pct: profitGrowthMoM,
                    isGoodIfPositive: true,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 4-Card Grid: Unit Economics & Targets
          Row(
            children: [
              // 1. Break-Even Members Target
              Expanded(
                child: _buildKPICell(
                  title: 'Break-Even Target',
                  value: '$breakEvenMembers Members',
                  subtitle: memberBuffer >= 0 ? '+$memberBuffer Buffer' : '${memberBuffer.abs()} Deficit',
                  subColor: memberBuffer >= 0 ? AppColors.paid : AppColors.absent,
                  icon: Icons.flag_outlined,
                  color: AppColors.primary,
                  extra: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (breakEvenLoadPct / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        breakEvenLoadPct <= 85 ? AppColors.paid : AppColors.pending,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. Net Profit Margin & OER
              Expanded(
                child: _buildKPICell(
                  title: 'Profit Margin',
                  value: '${profitMargin.toStringAsFixed(1)}%',
                  subtitle: 'OER: ${oer.toStringAsFixed(1)}%',
                  subColor: AppColors.textMuted,
                  icon: Icons.pie_chart_outline,
                  color: isProfit ? AppColors.paid : AppColors.absent,
                  extra: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (profitMargin / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isProfit ? AppColors.paid : AppColors.absent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              // 3. ARPM (Average Revenue Per Paying Member)
              Expanded(
                child: _buildKPICell(
                  title: 'ARPM (Rev/Member)',
                  value: GymDateUtils.formatCurrency(arpm, symbol: currency),
                  subtitle: 'Monthly billing / member',
                  subColor: AppColors.textMuted,
                  icon: Icons.person_pin_circle_outlined,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 10),

              // 4. Operating Cost Per Active Member
              Expanded(
                child: _buildKPICell(
                  title: 'Cost Per Member',
                  value: GymDateUtils.formatCurrency(costPerMember, symbol: currency),
                  subtitle: 'Overhead / active member',
                  subColor: AppColors.textMuted,
                  icon: Icons.price_check_outlined,
                  color: const Color(0xFFFF9100),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Cost Structure Split (Fixed vs Variable)
          if (fixedCosts > 0 || variableCosts > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cost Structure Analysis',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Fixed: ${fixedCostPct.toStringAsFixed(0)}% • Variable: ${variableCostPct.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Segmented Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    Flexible(
                      flex: fixedCostPct.toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFF6366F1)), // Indigo for Fixed
                    ),
                    Flexible(
                      flex: variableCostPct.toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFFF59E0B)), // Amber for Variable
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Fixed (Rent, Salaries, Power): ${GymDateUtils.formatCurrency(fixedCosts, symbol: currency)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Variable: ${GymDateUtils.formatCurrency(variableCosts, symbol: currency)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKPICell({
    required String title,
    required String value,
    required String subtitle,
    required Color subColor,
    required IconData icon,
    required Color color,
    Widget? extra,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: subColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (extra != null) ...[
            const SizedBox(height: 6),
            extra,
          ],
        ],
      ),
    );
  }

  Widget _buildMoMItem({
    required String label,
    required double pct,
    required bool isGoodIfPositive,
  }) {
    final bool isPositive = pct >= 0;
    final bool isGood = isGoodIfPositive ? isPositive : !isPositive;
    final color = isGood ? AppColors.paid : AppColors.absent;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPositive ? Icons.arrow_upward : Icons.arrow_downward,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '${pct.abs().toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
