import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/whatsapp_service.dart';
import '../../services/phone_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/animation_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/bill_history_sheet.dart';
import '../../widgets/collect_balance_dialog.dart';
import '../../widgets/bill_receipt_dialog.dart';
import '../../widgets/user_profile_menu_button.dart';
import 'add_customer_sheet.dart';
import 'customer_detail_screen.dart';
import '../../widgets/dashboard_metrics_grid.dart';
import '../../widgets/voice_search_suffix.dart';
import '../../widgets/animations/animated_empty_state.dart';
import '../../widgets/animations/animated_fade_slide.dart';
import '../../widgets/animations/animated_pressable.dart';
import '../../widgets/animations/app_page_route.dart';

enum CustomerFilter { all, active, pendingPayment, archived }

class CustomersTab extends StatefulWidget {
  final bool isVisible;
  const CustomersTab({super.key, this.isVisible = true});

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
            ? gymService.getAllPendingDues().map((s) => s.customer.id).toSet()
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${gymService.customers.length}',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const UserProfileMenuButton(),
            ],
          ),
          body: Column(
            children: [
              // Dashboard Metrics (hidden while keyboard is open to maximize space for search results)
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                DashboardMetricsGrid(isActive: widget.isVisible),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, or card #...',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppColors.textSecondary,
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    _buildFilterChip(
                      'All (${gymService.customers.length})',
                      CustomerFilter.all,
                    ),
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
                    ? AnimatedEmptyState(
                        icon: Icons.person_search_rounded,
                        title: _searchController.text.isNotEmpty
                            ? 'No members found matching "${_searchController.text}"'
                            : 'No members registered yet',
                        subtitle: _searchController.text.isNotEmpty
                            ? 'Check spelling or try searching by phone number or card #'
                            : 'Tap "+ Add Member" below to register your first gym member',
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        itemCount: list.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final customer = list[index];
                          final payment = gymService.getPaymentRecord(
                            customer.id,
                            currentMonth,
                          );
                          final attendanceSummary = gymService
                              .getMonthlyAttendanceSummary(
                                customer.id,
                                currentMonth,
                              );
                          final presentDays = attendanceSummary['present'] ?? 0;

                          return AnimatedFadeSlide.staggered(
                            index: index,
                            maxStaggerIndex: 6,
                            child: _buildCustomerCard(
                              customer,
                              payment,
                              currentMonth,
                              presentDays,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: FilledButton.icon(
                onPressed: () => AddCustomerSheet.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryOn,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text(
                  'Add Member',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, CustomerFilter filter) {
    final isSelected = _selectedFilter == filter;
    return AnimatedPressable(
      onTap: () {
        setState(() => _selectedFilter = filter);
      },
      child: AnimatedContainer(
        duration: AppAnimations.microDuration,
        curve: AppAnimations.curveEaseInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
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
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceBorder, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
                              Icon(
                                Icons.phone_outlined,
                                color: AppColors.secondary,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  customer.phone,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    if (isPaid && payment.balanceDue > 0) {
                      final current =
                          GymService().getPaymentById(payment.id) ?? payment;
                      final bill = await CollectBalanceDialog.show(
                        context,
                        current,
                      );
                      if (bill != null && mounted) {
                        await BillReceiptDialog.show(context, bill: bill);
                      }
                    } else {
                      MarkPaymentDialog.show(
                        context,
                        customer: customer,
                        monthYear: currentMonth,
                        currentRecord: payment,
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? AppColors.dynamicPaid.withValues(alpha: 0.15)
                          : (isNew
                                ? AppColors.secondary.withValues(alpha: 0.15)
                                : AppColors.dynamicPending.withValues(
                                    alpha: 0.15,
                                  )),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPaid
                            ? AppColors.dynamicPaid
                            : (isNew
                                  ? AppColors.secondary
                                  : AppColors.dynamicPending),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPaid
                              ? (payment.isPartiallyPaid ? 'PARTIAL' : 'PAID')
                              : (isNew ? 'NEW' : 'DUE'),
                          style: TextStyle(
                            color: isPaid
                                ? AppColors.dynamicPaid
                                : (isNew
                                      ? AppColors.secondary
                                      : AppColors.dynamicPending),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          GymDateUtils.formatCurrency(
                            payment.displayAmount,
                            symbol: currency,
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$presentDays days',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              customer.planType ==
                                  CustomerPlan.personalTrainingDiet
                              ? AppColors.dynamicPending.withValues(alpha: 0.15)
                              : (customer.planType ==
                                        CustomerPlan.personalTraining
                                    ? AppColors.secondary.withValues(
                                        alpha: 0.15,
                                      )
                                    : AppColors.surfaceElevated),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                customer.planType ==
                                    CustomerPlan.personalTrainingDiet
                                ? AppColors.dynamicPending.withValues(
                                    alpha: 0.4,
                                  )
                                : (customer.planType ==
                                          CustomerPlan.personalTraining
                                      ? AppColors.secondary.withValues(
                                          alpha: 0.4,
                                        )
                                      : AppColors.surfaceBorder),
                          ),
                        ),
                        child: Text(
                          customer.planDurationMonths > 1
                              ? '${CustomerPlan.getShortLabel(customer.planType)} • ${customer.planDurationMonths}M'
                              : CustomerPlan.getShortLabel(customer.planType),
                          style: TextStyle(
                            color:
                                customer.planType ==
                                    CustomerPlan.personalTrainingDiet
                                ? AppColors.dynamicPending
                                : (customer.planType ==
                                          CustomerPlan.personalTraining
                                      ? AppColors.secondary
                                      : AppColors.textSecondary),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final days = GymService().getDaysUntilExpiry(
                            customer,
                          );
                          if (days > 15) return const SizedBox.shrink();
                          final isUrgent = days <= 3;
                          final color = days < 0
                              ? AppColors.dynamicAbsent
                              : (isUrgent
                                    ? AppColors.dynamicAbsent
                                    : AppColors.dynamicPending);
                          final text = days < 0
                              ? 'Expired'
                              : (days == 0
                                    ? 'Expires today'
                                    : 'Expires in $days days');
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: color.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Wrap(
                  spacing: 2,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        Icons.call_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        padding: const EdgeInsets.all(6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
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
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.dynamicPaid,
                          size: 16,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.dynamicPaid.withValues(
                            alpha: 0.15,
                          ),
                          padding: const EdgeInsets.all(6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: AppColors.dynamicPaid.withValues(
                                alpha: 0.35,
                              ),
                            ),
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
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          Icons.waving_hand_rounded,
                          color: AppColors.secondary,
                          size: 16,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.secondary.withValues(
                            alpha: 0.15,
                          ),
                          padding: const EdgeInsets.all(6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: AppColors.secondary.withValues(
                                alpha: 0.35,
                              ),
                            ),
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
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: Icon(
                          Icons.chat_bubble_rounded,
                          color: AppColors.whatsapp,
                          size: 16,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.whatsapp.withValues(
                            alpha: 0.15,
                          ),
                          padding: const EdgeInsets.all(6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: AppColors.whatsapp.withValues(alpha: 0.35),
                            ),
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
                  ],
                ),
              ],
            ),
            if (isPaid && payment.balanceDue > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.dynamicPending.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.dynamicPending.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final current =
                              GymService().getPaymentById(payment.id) ??
                              payment;
                          final bill = await CollectBalanceDialog.show(
                            context,
                            current,
                          );
                          if (bill != null && mounted) {
                            await BillReceiptDialog.show(context, bill: bill);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dynamicPending,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.payments_rounded, size: 15),
                        label: Text(
                          'Collect Balance ${GymDateUtils.formatCurrency(payment.balanceDue, symbol: currency)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () {
                        MarkPaymentDialog.show(
                          context,
                          customer: customer,
                          monthYear: currentMonth,
                          currentRecord: payment,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.surfaceElevated,
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.surfaceBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.edit_note_rounded, size: 14),
                      label: const Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
