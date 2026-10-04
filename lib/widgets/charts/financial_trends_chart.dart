import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../animations/animated_pressable.dart';

enum FinancialChartMode { comparison, profit }

class FinancialTrendsChart extends StatefulWidget {
  final GymService gym;
  final String currency;

  const FinancialTrendsChart({
    super.key,
    required this.gym,
    required this.currency,
  });

  @override
  State<FinancialTrendsChart> createState() => _FinancialTrendsChartState();
}

class _FinancialTrendsChartState extends State<FinancialTrendsChart> {
  int _monthsCount = 6;
  FinancialChartMode _mode = FinancialChartMode.comparison;
  int? _touchedGroupIndex;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthsData = <_MonthlyFinancialPoint>[];

    // Gather last N months in chronological order
    for (int i = _monthsCount - 1; i >= 0; i--) {
      final monthDt = DateTime(now.year, now.month - i, 1);
      final monthKey = GymDateUtils.toMonthKey(monthDt);
      final summary = widget.gym.getBalanceSheetSummary(monthKey);
      final double income = (summary['totalIncome'] as num?)?.toDouble() ?? 0.0;
      final double expense = (summary['totalExpense'] as num?)?.toDouble() ?? 0.0;
      final double profit = income - expense;

      monthsData.add(
        _MonthlyFinancialPoint(
          monthKey: monthKey,
          label: DateFormat('MMM').format(monthDt),
          income: income,
          expense: expense,
          profit: profit,
        ),
      );
    }

    // Totals for the selected range
    final totalRevenue = monthsData.fold<double>(0.0, (sum, m) => sum + m.income);
    final totalExpense = monthsData.fold<double>(0.0, (sum, m) => sum + m.expense);
    final totalProfit = totalRevenue - totalExpense;

    final hasData = totalRevenue > 0 || totalExpense > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Financial Trends',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _mode == FinancialChartMode.comparison
                          ? 'Revenue vs Operating Expenses'
                          : 'Monthly Net Profit Trajectory',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 3M vs 6M Toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRangeButton(3, '3M'),
                    _buildRangeButton(6, '6M'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Sub-controls: Mode Switcher & Range Totals
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Chart Mode Switcher
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    _buildModeButton(FinancialChartMode.comparison, Icons.view_column_rounded, 'Compare'),
                    _buildModeButton(FinancialChartMode.profit, Icons.show_chart_rounded, 'Net Profit'),
                  ],
                ),
              ),

              // Summary Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (totalProfit >= 0 ? AppColors.paid : AppColors.absent).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_monthsCount}M Net: ',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${totalProfit >= 0 ? '+' : ''}${GymDateUtils.formatCurrency(totalProfit, symbol: widget.currency)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: totalProfit >= 0 ? AppColors.paid : AppColors.absent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Chart Display Area
          if (!hasData)
            _buildEmptyState()
          else
            SizedBox(
              height: 220,
              child: _mode == FinancialChartMode.comparison
                  ? _buildBarChart(monthsData)
                  : _buildLineChart(monthsData),
            ),

          const SizedBox(height: 14),

          // Legend Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_mode == FinancialChartMode.comparison) ...[
                _buildLegendItem('Revenue', AppColors.paid),
                const SizedBox(width: 18),
                _buildLegendItem('Expenses', AppColors.absent),
              ] else ...[
                _buildLegendItem('Net Surplus', AppColors.paid),
                const SizedBox(width: 18),
                _buildLegendItem('Deficit', AppColors.absent),
                const SizedBox(width: 18),
                _buildLegendItem('Break-Even (0)', AppColors.textMuted),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRangeButton(int count, String text) {
    final isSelected = _monthsCount == count;
    return AnimatedPressable(
      onTap: () => setState(() => _monthsCount = count),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton(FinancialChartMode mode, IconData icon, String label) {
    final isSelected = _mode == mode;
    return AnimatedPressable(
      onTap: () => setState(() => _mode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.query_stats_rounded, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'No Financial Activity Recorded',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Collect member dues or record expenses to populate this graph.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<_MonthlyFinancialPoint> data) {
    double maxVal = 0;
    for (final p in data) {
      maxVal = math.max(maxVal, math.max(p.income, p.expense));
    }
    if (maxVal == 0) maxVal = 1000;
    // Round maxY up to a nice number
    final maxY = (maxVal * 1.25).ceilToDouble();

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 10,
            getTooltipColor: (_) => AppColors.surfaceElevated,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final point = data[group.x.toInt()];
              final isIncome = rodIndex == 0;
              final label = isIncome ? 'Revenue' : 'Expense';
              final val = isIncome ? point.income : point.expense;
              final color = isIncome ? AppColors.paid : AppColors.absent;

              return BarTooltipItem(
                '${point.label}\n',
                TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: '$label: ${GymDateUtils.formatCurrency(val, symbol: widget.currency)}\n',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  TextSpan(
                    text: 'Net: ${point.profit >= 0 ? '+' : ''}${GymDateUtils.formatCurrency(point.profit, symbol: widget.currency)}',
                    style: TextStyle(
                      color: point.profit >= 0 ? AppColors.paid : AppColors.absent,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            },
          ),
          touchCallback: (FlTouchEvent event, barTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  barTouchResponse == null ||
                  barTouchResponse.spot == null) {
                _touchedGroupIndex = -1;
                return;
              }
              _touchedGroupIndex = barTouchResponse.spot!.touchedBarGroupIndex;
            });
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox.shrink();
                final isTouched = index == _touchedGroupIndex;
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    data[index].label,
                    style: TextStyle(
                      color: isTouched ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isTouched ? FontWeight.bold : FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value == 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    _formatCompact(value),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceBorder.withValues(alpha: 0.6),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (index) {
          final p = data[index];
          final isTouched = index == _touchedGroupIndex;
          final rodWidth = _monthsCount == 3 ? 18.0 : 12.0;

          return BarChartGroupData(
            x: index,
            barRods: [
              // Income Rod
              BarChartRodData(
                toY: p.income,
                color: AppColors.paid,
                width: rodWidth,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(5),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: isTouched
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                ),
              ),
              // Expense Rod
              BarChartRodData(
                toY: p.expense,
                color: AppColors.absent,
                width: rodWidth,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(5),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: false,
                ),
              ),
            ],
            barsSpace: 4,
          );
        }),
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildLineChart(List<_MonthlyFinancialPoint> data) {
    double minProfit = 0;
    double maxProfit = 0;
    for (final p in data) {
      minProfit = math.min(minProfit, p.profit);
      maxProfit = math.max(maxProfit, p.profit);
    }
    if (minProfit == 0 && maxProfit == 0) {
      maxProfit = 1000;
    }

    final effectiveMaxY = (maxProfit > 0 ? maxProfit * 1.25 : 100).ceilToDouble();
    final effectiveMinY = (minProfit < 0 ? minProfit * 1.25 : 0).floorToDouble();

    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].profit));
    }

    return LineChart(
      LineChartData(
        minY: effectiveMinY,
        maxY: effectiveMaxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 10,
            getTooltipColor: (_) => AppColors.surfaceElevated,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final point = data[spot.x.toInt()];
                final isPositive = point.profit >= 0;
                return LineTooltipItem(
                  '${point.label}\n',
                  TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${isPositive ? '+' : ''}${GymDateUtils.formatCurrency(point.profit, symbol: widget.currency)}',
                      style: TextStyle(
                        color: isPositive ? AppColors.paid : AppColors.absent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            final isZero = value.abs() < 0.1;
            return FlLine(
              color: isZero
                  ? AppColors.textMuted.withValues(alpha: 0.6)
                  : AppColors.surfaceBorder.withValues(alpha: 0.5),
              strokeWidth: isZero ? 1.5 : 1,
              dashArray: isZero ? null : [4, 4],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    data[index].label,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (double value, TitleMeta meta) {
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    _formatCompact(value),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            preventCurveOverShooting: true,
            color: AppColors.secondary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final point = data[index];
                final color = point.profit >= 0 ? AppColors.paid : AppColors.absent;
                return FlDotCirclePainter(
                  radius: 5,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: AppColors.surface,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.secondary.withValues(alpha: 0.3),
                  AppColors.secondary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  String _formatCompact(double value) {
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.toStringAsFixed(0);
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MonthlyFinancialPoint {
  final String monthKey;
  final String label;
  final double income;
  final double expense;
  final double profit;

  _MonthlyFinancialPoint({
    required this.monthKey,
    required this.label,
    required this.income,
    required this.expense,
    required this.profit,
  });
}
