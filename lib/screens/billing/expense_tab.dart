import 'package:flutter/material.dart';
import '../../models/expense.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/add_expense_dialog.dart';
import '../../widgets/voice_search_suffix.dart';

class ExpenseTab extends StatefulWidget {
  final DateTime selectedMonth;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  const ExpenseTab({
    super.key,
    required this.selectedMonth,
    this.onPrevMonth,
    this.onNextMonth,
  });

  @override
  State<ExpenseTab> createState() => _ExpenseTabState();
}

class _ExpenseTabState extends State<ExpenseTab> {
  ExpenseCategory? _selectedCategoryFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GymService(),
      builder: (context, _) {
        final gym = GymService();
        final monthKey = GymDateUtils.toMonthKey(widget.selectedMonth);
        final currency = gym.settings.currencySymbol;
        final allExpenses = gym.getMonthlyExpenses(monthKey);
        final totalExpense = gym.getTotalExpenseAmount(monthKey);
        final categoryBreakdown = gym.getExpenseCategoryBreakdown(monthKey);

        // Filter by category and search
        var filteredExpenses = allExpenses;
        if (_selectedCategoryFilter != null) {
          filteredExpenses = filteredExpenses
              .where((e) => e.category == _selectedCategoryFilter)
              .toList();
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          filteredExpenses = filteredExpenses.where((e) {
            return e.title.toLowerCase().contains(q) ||
                (e.notes != null && e.notes!.toLowerCase().contains(q));
          }).toList();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              // Summary Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.absent.withValues(alpha: 0.18),
                      AppColors.surfaceElevated,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.absent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.absent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.outbox_rounded, color: AppColors.absent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL EXPENSES (${GymDateUtils.formatMonthHeader(monthKey)})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GymDateUtils.formatCurrency(totalExpense, symbol: currency),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.absent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: Text(
                        '${allExpenses.length} Records',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search and Category Filters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search expenses by name or notes...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.surfaceElevated,
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textMuted),
                    suffixIcon: VoiceSearchSuffix(
                      controller: _searchController,
                      voiceHint: 'Say expense title, category, or note...',
                      iconSize: 18,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      onClear: () => setState(() => _searchQuery = ''),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceBorder),
                    ),
                  ),
                ),
              ),

              // Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    FilterChip(
                      selected: _selectedCategoryFilter == null,
                      showCheckmark: false,
                      label: Text('All (${allExpenses.length})'),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: _selectedCategoryFilter == null
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _selectedCategoryFilter == null ? AppColors.primaryOn : AppColors.textSecondary,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceElevated,
                      side: BorderSide(
                        color: _selectedCategoryFilter == null
                            ? AppColors.primary
                            : AppColors.surfaceBorder,
                      ),
                      onSelected: (_) => setState(() => _selectedCategoryFilter = null),
                    ),
                    const SizedBox(width: 8),
                    ...ExpenseCategory.values.map((cat) {
                      final count = categoryBreakdown[cat] != null
                          ? allExpenses.where((e) => e.category == cat).length
                          : 0;
                      if (count == 0 && _selectedCategoryFilter != cat) {
                        return const SizedBox.shrink();
                      }
                      final isSelected = _selectedCategoryFilter == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSelected,
                          showCheckmark: false,
                          avatar: Icon(
                            cat.icon,
                            size: 14,
                            color: isSelected ? Colors.black : cat.color,
                          ),
                          label: Text('${cat.label} ($count)'),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.black : AppColors.textSecondary,
                          ),
                          selectedColor: cat.color,
                          backgroundColor: AppColors.surfaceElevated,
                          side: BorderSide(
                            color: isSelected ? cat.color : AppColors.surfaceBorder,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryFilter = selected ? cat : null;
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),

              // Expense List
              Expanded(
                child: filteredExpenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              _selectedCategoryFilter != null || _searchQuery.isNotEmpty
                                  ? 'No expenses matching filter'
                                  : 'No expenses recorded for this month',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () {
                                AddExpenseDialog.show(
                                  context,
                                  initialDate: widget.selectedMonth,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.primaryOn,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add First Expense'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: filteredExpenses.length,
                        itemBuilder: (context, index) {
                          final expense = filteredExpenses[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            color: AppColors.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: AppColors.surfaceBorder),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                AddExpenseDialog.show(
                                  context,
                                  expenseToEdit: expense,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    // Category Icon Container
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: expense.category.color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        expense.category.icon,
                                        color: expense.category.color,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Title, Category & Date
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            expense.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: expense.category.color.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  expense.category.label,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: expense.category.color,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                GymDateUtils.formatDisplayDate(expense.date),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '• ${PaymentRecord.methodLabel(expense.paymentMethod)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (expense.notes != null &&
                                              expense.notes!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              expense.notes!,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: AppColors.textMuted,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Amount & Edit Icon
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          GymDateUtils.formatCurrency(expense.amount, symbol: currency),
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.absent,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 14,
                                          color: AppColors.textMuted,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              AddExpenseDialog.show(
                context,
                initialDate: widget.selectedMonth,
              );
            },
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.primaryOn,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add Expense',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}
