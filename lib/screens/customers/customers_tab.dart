import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/whatsapp_service.dart';
import '../../services/phone_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/bill_history_sheet.dart';
import '../../widgets/user_profile_menu_button.dart';
import '../../widgets/dashboard_metrics_grid.dart';
import 'add_customer_sheet.dart';
import 'customer_detail_screen.dart';

enum CustomerFilter { all, active, pendingPayment, archived }

class CustomersTab extends StatefulWidget {
  const CustomersTab({super.key});

  @override
  State<CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<CustomersTab> {
  final TextEditingController _searchController = TextEditingController();
  CustomerFilter _selectedFilter = CustomerFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gymService = GymService();
        final currentMonth = GymDateUtils.toMonthKey(DateTime.now());
        final owingIds = _selectedFilter == CustomerFilter.pendingPayment
            ? gymService
                .getAllPendingDues()
                .map((s) => s.customer.id)
                .toSet()
            : <String>{};
        var list = gymService.searchCustomers(_searchController.text);

        if (_selectedFilter == CustomerFilter.active) {
          list = list.where((c) => c.isActive).toList();
        } else if (_selectedFilter == CustomerFilter.pendingPayment) {
          list = list.where((c) {
            return owingIds.contains(c.id);
          }).toList();
        } else if (_selectedFilter == CustomerFilter.archived) {
          list = list.where((c) => !c.isActive).toList();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Gym Members'),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${gymService.customers.length} Members',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const UserProfileMenuButton(),
            ],
          ),
          body: Column(
            children: [
              const DashboardMetricsGrid(),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by member name or phone...',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip('All (${gymService.customers.length})', CustomerFilter.all),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Active (${gymService.customers.where((c) => c.isActive).length})',
                      CustomerFilter.active,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Pending Dues (${owingIds.length})',
                      CustomerFilter.pendingPayment,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip('Archived', CustomerFilter.archived),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Customer List
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search_rounded, size: 54, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No members found matching "${_searchController.text}"'
                                  : 'No members registered yet',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final customer = list[index];
                          final payment = gymService.getPaymentRecord(customer.id, currentMonth);
                          final attendanceSummary = gymService.getMonthlyAttendanceSummary(customer.id, currentMonth);
                          final presentDays = attendanceSummary['present'] ?? 0;

                          return _buildCustomerCard(customer, payment, currentMonth, presentDays);
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => AddCustomerSheet.show(context),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.primaryOn,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text(
              'Add Member',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, CustomerFilter filter) {
    final isSelected = _selectedFilter == filter;
    return InkWell(
      onTap: () {
        setState(() => _selectedFilter = filter);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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

  Widget _buildCustomerCard(
    Customer customer,
    PaymentRecord payment,
    String currentMonth,
    int presentDays,
  ) {
    final stage = GymService().getMemberLifecycleStage(customer, currentMonth);
    final isPaid = stage.isPaid;
    final isNew = stage.isNew;
    final currency = GymService().settings.currencySymbol;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(customerId: customer.id),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPaid
                ? AppColors.surfaceBorder
                : (isNew ? const Color(0xFF00B4D8).withValues(alpha: 0.35) : AppColors.pending.withValues(alpha: 0.3)),
            width: isPaid ? 1 : 1.2,
          ),
        ),
        child: Row(
          children: [
            CustomerAvatar(
              imagePath: customer.imagePath,
              name: customer.name,
              radius: 24,
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
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  InkWell(
                    onTap: () {
                      PhoneService().makeCall(
                        customer.phone,
                        context: context,
                        memberName: customer.name,
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_outlined, color: AppColors.secondary, size: 13),
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
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6,
                          vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$presentDays days',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6,
                          vertical: 2),
                        decoration: BoxDecoration(
                          color: customer.planType == CustomerPlan.personalTrainingDiet
                              ? const Color(0xFFFF9100).withValues(alpha: 0.15)
                              : (customer.planType == CustomerPlan.personalTraining
                                  ? AppColors.secondary.withValues(alpha: 0.15)
                                  : AppColors.surfaceElevated),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: customer.planType == CustomerPlan.personalTrainingDiet
                                ? const Color(0xFFFF9100).withValues(alpha: 0.4)
                                : (customer.planType == CustomerPlan.personalTraining
                                    ? AppColors.secondary.withValues(alpha: 0.4)
                                    : AppColors.surfaceBorder),
                          ),
                        ),
                        child: Text(
                          customer.planDurationMonths > 1
                              ? '${CustomerPlan.getShortLabel(customer.planType)} • ${customer.planDurationMonths}M'
                              : CustomerPlan.getShortLabel(customer.planType),
                          style: TextStyle(
                            color: customer.planType == CustomerPlan.personalTrainingDiet
                                ? const Color(0xFFFF9100)
                                : (customer.planType == CustomerPlan.personalTraining
                                    ? AppColors.secondary
                                    : AppColors.textSecondary),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final days = GymService().getDaysUntilExpiry(customer);
                          if (days > 15) return const SizedBox.shrink();
                          final isUrgent = days <= 3;
                          final color = days < 0
                              ? const Color(0xFFD50000)
                              : (isUrgent ? const Color(0xFFFF5252) : const Color(0xFFFF9100));
                          final text = days < 0
                              ? 'Expired'
                              : (days == 0 ? 'Exp Today' : '${days}d left');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6,
                              vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.call_rounded, color: AppColors.primary, size: 16),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
                ),
              ),
              tooltip: 'Call Member',
              onPressed: () {
                PhoneService().makeCall(
                  customer.phone,
                  context: context,
                  memberName: customer.name,
                );
              },
            ),
            const SizedBox(width: 4),
            if (isPaid) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.receipt_long_rounded, color: AppColors.paid, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.paid.withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppColors.paid.withValues(alpha: 0.35)),
                  ),
                ),
                tooltip: 'View Bill / Receipt',
                onPressed: () {
                  BillHistorySheet.showForPayment(
                    context,
                    customer: customer,
                    payment: payment,
                  );
                },
              ),
              const SizedBox(width: 4),
            ] else if (isNew) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.waving_hand_rounded, color: Color(0xFF00B4D8), size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: const Color(0xFF00B4D8).withValues(alpha: 0.35)),
                  ),
                ),
                tooltip: 'Send Welcome Message',
                onPressed: () {
                  WhatsAppService().showWelcomeSheet(
                    context: context,
                    customer: customer,
                  );
                },
              ),
              const SizedBox(width: 4),
            ] else ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.whatsapp, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.whatsapp.withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: AppColors.whatsapp.withValues(alpha: 0.35)),
                  ),
                ),
                tooltip: 'Send WhatsApp Reminder',
                onPressed: () {
                  WhatsAppService().showReminderSheet(
                    context: context,
                    customer: customer,
                    monthYear: currentMonth,
                    amount: GymService().pendingAmountOf(payment),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],

            // Payment status pill with action
            InkWell(
              onTap: () {
                MarkPaymentDialog.show(
                  context,
                  customer: customer,
                  monthYear: currentMonth,
                  currentRecord: payment,
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isPaid
                      ? AppColors.paid.withValues(alpha: 0.15)
                      : (isNew ? const Color(0xFF00B4D8).withValues(alpha: 0.15) : AppColors.pending.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPaid
                        ? AppColors.paid
                        : (isNew ? const Color(0xFF00B4D8) : AppColors.pending),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isPaid
                          ? (payment.isPartiallyPaid
                              ? 'PARTIAL · BAL ${GymDateUtils.formatCurrency(payment.balanceDue, symbol: currency)}'
                              : 'PAID')
                          : (isNew ? 'NEW' : 'DUE'),
                      style: TextStyle(
                        color: isPaid
                            ? AppColors.paid
                            : (isNew ? const Color(0xFF00B4D8) : AppColors.pending),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      GymDateUtils.formatCurrency(payment.displayAmount, symbol: currency),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
