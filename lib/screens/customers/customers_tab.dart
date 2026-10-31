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

enum _MemberAction {
  details,
  edit,
  payment,
  editPayment,
  receipts,
  call,
  message,
  archive,
}

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
        final owingIds = gymService
            .getAllPendingDues()
            .map((s) => s.customer.id)
            .toSet();
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
            title: const Text(
              'Gym Members',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: 'Add Member',
                onPressed: () => AddCustomerSheet.show(context),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryOn,
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(6),
                ),
                icon: const Icon(Icons.person_add_outlined, size: 18),
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
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
              const SizedBox(height: 6),

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
                            : 'Tap Add Member in the top bar to register your first gym member',
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        itemCount: list.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  void _openMember(Customer customer) {
    Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => CustomerDetailScreen(customerId: customer.id),
      ),
    );
  }

  Widget _memberAvatar(Customer customer) {
    if ((customer.imageBase64?.isNotEmpty ?? false) ||
        ((customer.imagePath?.isNotEmpty ?? false) &&
            !customer.imagePath!.startsWith('avatar:'))) {
      return CustomerAvatar(
        imagePath: customer.imagePath,
        imageBase64: customer.imageBase64,
        name: customer.name,
        radius: 24,
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.fitness_center_outlined, color: AppColors.primary),
    );
  }

  Widget _metadata(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color ?? AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerCard(
    Customer customer,
    PaymentRecord payment,
    String currentMonth,
    int presentDays,
  ) {
    final gym = GymService();
    final stage = gym.getMemberLifecycleStage(customer, currentMonth);
    final days = gym.getDaysUntilExpiry(customer);
    final amount = GymDateUtils.formatCurrency(
      payment.displayAmount,
      symbol: gym.settings.currencySymbol,
    );
    final balance = GymDateUtils.formatCurrency(
      payment.balanceDue,
      symbol: gym.settings.currencySymbol,
    );
    final status = stage.isPaid
        ? (payment.isPartiallyPaid
              ? 'Partial · Balance $balance'
              : 'Paid $amount')
        : (stage.isNew ? 'New · $amount' : 'Due $amount');
    final statusColor = stage.isPaid && !payment.isPartiallyPaid
        ? AppColors.dynamicPaid
        : (stage.isNew ? AppColors.secondary : AppColors.dynamicPending);
    final expiry = days < 0
        ? 'Expired'
        : days == 0
        ? 'Expires today'
        : 'Expires in $days ${days == 1 ? 'day' : 'days'}';

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMember(customer),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _memberAvatar(customer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          customer.phone,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Options for ${customer.name}',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () =>
                        _showMemberActions(customer, payment, currentMonth),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: AppColors.surfaceBorder),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _metadata(
                    Icons.fitness_center_outlined,
                    '${CustomerPlan.getShortLabel(customer.planType)} · ${customer.durationLabel}',
                  ),
                  _metadata(
                    Icons.event_available_outlined,
                    '$presentDays ${presentDays == 1 ? 'day' : 'days'} attended',
                  ),
                  _metadata(
                    Icons.schedule_outlined,
                    expiry,
                    color: days < 0
                        ? AppColors.dynamicAbsent
                        : days <= 4
                        ? AppColors.dynamicPending
                        : null,
                  ),
                  if (customer.cardNumber.isNotEmpty)
                    _metadata(
                      Icons.badge_outlined,
                      'Card #${customer.cardNumber}',
                    ),
                  if (!customer.isActive)
                    _metadata(Icons.archive_outlined, 'Archived'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (stage.isPaid && payment.balanceDue > 0)
                    TextButton(
                      onPressed: () => _handleMemberAction(
                        _MemberAction.payment,
                        customer,
                        payment,
                        currentMonth,
                      ),
                      child: const Text(
                        'Collect balance',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMemberActions(
    Customer customer,
    PaymentRecord payment,
    String currentMonth,
  ) async {
    final stage = GymService().getMemberLifecycleStage(customer, currentMonth);
    final action = await showModalBottomSheet<_MemberAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget row(
          _MemberAction action,
          IconData icon,
          String title,
          String subtitle, {
          bool destructive = false,
        }) {
          final color = destructive
              ? AppColors.dynamicAbsent
              : AppColors.primary;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: destructive ? color : AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => Navigator.pop(sheetContext, action),
          );
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _memberAvatar(customer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            customer.phone,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close member options',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: AppColors.surfaceBorder),
                const SizedBox(height: 12),
                Text(
                  'MEMBER ACTIONS',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                row(
                  _MemberAction.details,
                  Icons.person_outline,
                  'View details',
                  'See membership, payments and attendance',
                ),
                row(
                  _MemberAction.edit,
                  Icons.edit_outlined,
                  'Edit member',
                  'Update profile and membership details',
                ),
                Divider(height: 1, color: AppColors.surfaceBorder),
                row(
                  _MemberAction.payment,
                  Icons.payments_outlined,
                  stage.isPaid
                      ? (payment.balanceDue > 0
                            ? 'Collect balance'
                            : 'View / edit payment')
                      : 'Record payment',
                  'Manage this month’s membership payment',
                ),
                if (stage.isPaid && payment.balanceDue > 0)
                  row(
                    _MemberAction.editPayment,
                    Icons.edit_note_outlined,
                    'Edit payment',
                    'Review or update the original payment',
                  ),
                if (stage.isPaid)
                  row(
                    _MemberAction.receipts,
                    Icons.receipt_long_outlined,
                    'View receipts',
                    'See bills and payment history',
                  ),
                row(
                  _MemberAction.call,
                  Icons.call_outlined,
                  'Call member',
                  customer.phone,
                ),
                if (!stage.isPaid)
                  row(
                    _MemberAction.message,
                    Icons.chat_bubble_outline,
                    stage.isNew
                        ? 'Send welcome message'
                        : 'Send WhatsApp reminder',
                    stage.isNew
                        ? 'Welcome this member to your gym'
                        : 'Share a payment reminder',
                  ),
                Divider(height: 1, color: AppColors.surfaceBorder),
                row(
                  _MemberAction.archive,
                  customer.isActive
                      ? Icons.archive_outlined
                      : Icons.unarchive_outlined,
                  customer.isActive ? 'Archive member' : 'Restore member',
                  customer.isActive
                      ? 'Keep all receipts and attendance history'
                      : 'Make this member active again',
                  destructive: customer.isActive,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.surfaceElevated,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    await _handleMemberAction(action, customer, payment, currentMonth);
  }

  Future<void> _handleMemberAction(
    _MemberAction action,
    Customer customer,
    PaymentRecord payment,
    String month,
  ) async {
    switch (action) {
      case _MemberAction.details:
        _openMember(customer);
      case _MemberAction.edit:
        await AddCustomerSheet.show(context, customerToEdit: customer);
      case _MemberAction.payment:
        final current = GymService().getPaymentById(payment.id) ?? payment;
        if (current.isPaid && current.balanceDue > 0) {
          final bill = await CollectBalanceDialog.show(context, current);
          if (bill != null && mounted) {
            await BillReceiptDialog.show(context, bill: bill);
          }
        } else {
          await MarkPaymentDialog.show(
            context,
            customer: customer,
            monthYear: month,
            currentRecord: current,
          );
        }
      case _MemberAction.editPayment:
        await MarkPaymentDialog.show(
          context,
          customer: customer,
          monthYear: month,
          currentRecord: payment,
        );
      case _MemberAction.receipts:
        await BillHistorySheet.showForPayment(
          context,
          customer: customer,
          payment: payment,
        );
      case _MemberAction.call:
        await PhoneService().makeCall(
          customer.phone,
          context: context,
          memberName: customer.name,
        );
      case _MemberAction.message:
        if (GymService().getMemberLifecycleStage(customer, month).isNew) {
          await WhatsAppService().showWelcomeSheet(
            context: context,
            customer: customer,
          );
        } else {
          await WhatsAppService().showReminderSheet(
            context: context,
            customer: customer,
            monthYear: month,
            amount: GymService().pendingAmountOf(payment),
          );
        }
      case _MemberAction.archive:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              customer.isActive ? 'Archive member?' : 'Restore member?',
            ),
            content: Text(
              customer.isActive
                  ? 'Archive ${customer.name}? All receipts and attendance history will be kept.'
                  : 'Make ${customer.name} active again?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(customer.isActive ? 'Archive' : 'Restore'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        try {
          if (customer.isActive) {
            await GymService().archiveCustomer(customer.id);
          } else {
            await GymService().restoreCustomer(customer.id);
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not update member. Please try again.'),
              ),
            );
          }
        }
    }
  }
}
