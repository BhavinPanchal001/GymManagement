import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/expense.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class ExpenseCategoryChart extends StatefulWidget {
  final Map<ExpenseCategory, double> breakdown;
  final double totalExpense;
  final String currency;

  const ExpenseCategoryChart({
    super.key,
    required this.breakdown,
    required this.totalExpense,
    required this.currency,
  });

  @override
  State<ExpenseCategoryChart> createState() => _ExpenseCategoryChartState();
}

class _ExpenseCategoryChartState extends State<ExpenseCategoryChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // Sort categories by spend descending
    final activeEntries = widget.breakdown.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final hasExpenses = widget.totalExpense > 0 && activeEntries.isNotEmpty;

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
                  color: AppColors.absent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.donut_small_rounded, color: AppColors.absent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expense Breakdown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Monthly Cost Allocation by Category',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.absent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  GymDateUtils.formatCurrency(widget.totalExpense, symbol: widget.currency),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.absent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Donut Chart Display Area
          if (!hasExpenses)
            _buildEmptyState()
          else ...[
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2.5,
                      centerSpaceRadius: 52,
                      sections: List.generate(activeEntries.length, (i) {
                        final isTouched = i == _touchedIndex;
                        final entry = activeEntries[i];
                        final radius = isTouched ? 30.0 : 22.0;

                        return PieChartSectionData(
                          color: entry.key.color,
                          value: entry.value,
                          title: '', // Handled in center and legend
                          radius: radius,
                        );
                      }),
                    ),
                  ),

                  // Center info
                  _buildCenterInfo(activeEntries),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Ranked Category Breakdown List
            Column(
              children: activeEntries.map((entry) {
                final category = entry.key;
                final amount = entry.value;
                final pct = widget.totalExpense > 0
                    ? (amount / widget.totalExpense * 100).round()
                    : 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: category.color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(category.icon, size: 16, color: category.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              category.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                GymDateUtils.formatCurrency(amount, symbol: widget.currency),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '$pct% of total',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Mini bar indicator
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: widget.totalExpense > 0 ? (amount / widget.totalExpense).clamp(0.0, 1.0) : 0,
                          backgroundColor: AppColors.surfaceBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(category.color),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCenterInfo(List<MapEntry<ExpenseCategory, double>> activeEntries) {
    if (_touchedIndex >= 0 && _touchedIndex < activeEntries.length) {
      final entry = activeEntries[_touchedIndex];
      final pct = widget.totalExpense > 0
          ? (entry.value / widget.totalExpense * 100).round()
          : 0;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(entry.key.icon, size: 18, color: entry.key.color),
          const SizedBox(height: 2),
          Text(
            GymDateUtils.formatCurrency(entry.value, symbol: widget.currency),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: entry.key.color,
            ),
          ),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          GymDateUtils.formatCurrency(widget.totalExpense, symbol: widget.currency),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          'Total Expenses',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pie_chart_outline_rounded, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'No Expenses Recorded This Month',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add rent, salaries, or utility costs to visualize category breakdown.',
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
}
