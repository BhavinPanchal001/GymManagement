import 'package:flutter/material.dart';
import '../../models/expense.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/balance_sheet_card.dart';
import '../../widgets/balance_sheet_kpi_card.dart';
import '../../widgets/add_expense_dialog.dart';

class BalanceSheetTab extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback? onSwitchToExpenses;

  const BalanceSheetTab({
    super.key,
    required this.selectedMonth,
    this.onSwitchToExpenses,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final monthKey = GymDateUtils.toMonthKey(selectedMonth);
        final currency = gym.settings.currencySymbol;
        final summary = gym.getBalanceSheetSummary(monthKey);

        final double totalIncome = summary['totalIncome'] as double;
        final double totalExpense = summary['totalExpense'] as double;
        final double netProfit = summary['netProfit'] as double;
        final double profitMargin = summary['profitMargin'] as double;
        final bool isProfit = summary['isProfit'] as bool;
        final Map<ExpenseCategory, double> breakdown =
            summary['categoryBreakdown'] as Map<ExpenseCategory, double>;

        // Income payment method breakdown (PAID bills collected this month)
        final monthBills = gym.billsMap.values
            .where((b) =>
                b.status == 'PAID' &&
                GymDateUtils.toMonthKey(b.paidAt) == monthKey)
            .toList();

        final methodIncome = <PaymentMethod, double>{};
        for (final b in monthBills) {
          methodIncome[b.method] = (methodIncome[b.method] ?? 0.0) + b.amount;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Hero Balance Sheet Card
                BalanceSheetCard(
                  monthYear: monthKey,
                  onManageExpenses: onSwitchToExpenses,
                ),

                const SizedBox(height: 16),

                // Executive Financial KPIs Suite
                BalanceSheetKPICard(monthYear: monthKey),

                const SizedBox(height: 20),

                // Revenue Inflows Section
                _buildSectionHeader(
                  title: 'Revenue Inflow (Collections)',
                  subtitle: '${monthBills.length} payments collected this month',
                  icon: Icons.savings_outlined,
                  color: AppColors.paid,
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    children: [
                      if (methodIncome.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              'No payments collected yet for ${GymDateUtils.formatMonthHeader(monthKey)}',
                              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                          ),
                        ),
                      ] else ...[
                        ...methodIncome.entries.map((entry) {
                          final pct = totalIncome > 0 ? (entry.value / totalIncome * 100) : 0.0;
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.paid.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.arrow_downward, size: 16, color: AppColors.paid),
                            ),
                            title: Text(
                              PaymentRecord.methodLabel(entry.key),
                              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              '${pct.toStringAsFixed(1)}% of total inflow',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                            trailing: Text(
                              GymDateUtils.formatCurrency(entry.value, symbol: currency),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          );
                        }),
                      ],
                      Divider(color: AppColors.surfaceBorder, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Total Collections',
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                GymDateUtils.formatCurrency(totalIncome, symbol: currency),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.paid,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Expense Outflows Section
                _buildSectionHeader(
                  title: 'Operating Expenses Outflow',
                  subtitle: '${breakdown.length} cost categories recorded',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.absent,
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    children: [
                      if (breakdown.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Column(
                              children: [
                                Text(
                                  'No expenses logged for this month',
                                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    AddExpenseDialog.show(context, initialDate: selectedMonth);
                                  },
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add Expense'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        ...breakdown.entries.map((entry) {
                          final pct = totalExpense > 0 ? (entry.value / totalExpense * 100) : 0.0;
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: entry.key.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(entry.key.icon, size: 16, color: entry.key.color),
                            ),
                            title: Text(
                              entry.key.label,
                              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              '${pct.toStringAsFixed(1)}% of expenses',
                              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                            ),
                            trailing: Text(
                              GymDateUtils.formatCurrency(entry.value, symbol: currency),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          );
                        }),
                      ],
                      Divider(color: AppColors.surfaceBorder, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Total Operating Expenses',
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                GymDateUtils.formatCurrency(totalExpense, symbol: currency),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.absent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Net Cash Flow Summary Banner
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isProfit
                        ? AppColors.paid.withValues(alpha: 0.12)
                        : AppColors.absent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isProfit
                          ? AppColors.paid.withValues(alpha: 0.4)
                          : AppColors.absent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isProfit ? 'NET OPERATING PROFIT' : 'NET OPERATING DEFICIT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isProfit ? AppColors.paid : AppColors.absent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Margin: ${profitMargin.toStringAsFixed(1)}% • ${isProfit ? 'Healthy gym surplus' : 'Expenses exceed income'}',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          GymDateUtils.formatCurrency(netProfit.abs(), symbol: currency),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: isProfit ? AppColors.paid : AppColors.absent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
