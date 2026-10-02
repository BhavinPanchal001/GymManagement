import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/attendance.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/whatsapp_service.dart';
import '../../services/phone_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/customer_avatar.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/mark_month_attendance_dialog.dart';
import '../../widgets/bill_history_sheet.dart';
import 'add_customer_sheet.dart';
import 'member_card_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  final int initialTabIndex;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.initialTabIndex = 0,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _displayedMonth;
  late TabController _tabController;
  bool _isCustomRangeMode = false;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final customer = GymService().getCustomerById(widget.customerId);
    if (customer != null && widget.initialTabIndex == 1) {
      final unpaid = GymService().getUnpaidAttendedMonthKeys(customer.id);
      if (unpaid.isNotEmpty) {
        final parts = unpaid.first.split('-');
        final y = int.tryParse(parts[0]) ?? now.year;
        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? now.month) : now.month;
        _displayedMonth = DateTime(y, m, 1);
      } else {
        _displayedMonth = DateTime(customer.joinDate.year, customer.joinDate.month, 1);
      }
    } else {
      _displayedMonth = DateTime(now.year, now.month, 1);
    }
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _displayedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 5),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      setState(() {
        _displayedMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialStart = _customStartDate ?? DateTime(now.year, now.month, 1);
    final initialEnd = _customEndDate != null && !_customEndDate!.isAfter(today) ? _customEndDate! : today;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: initialStart.isAfter(today) ? today : initialStart,
        end: initialEnd,
      ),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _displayedMonth = DateTime(picked.start.year, picked.start.month, 1);
      });
    }
  }

  void _prevMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  void _editCustomer(Customer customer) async {
    final updated = await AddCustomerSheet.show(context, customerToEdit: customer);
    if (updated == true) {
      setState(() {});
    }
  }

  void _archiveCustomer(Customer customer) async {
    final archive = customer.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archive ? 'Archive member?' : 'Restore member?'),
        content: Text(
          archive
              ? 'The member will leave the active list. Attendance, payments, receipts and outstanding balances will be kept.'
              : 'The member will return to the active list with their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(archive ? 'Archive' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (archive) {
        await GymService().archiveCustomer(customer.id);
      } else {
        await GymService().restoreCustomer(customer.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              archive
                  ? 'Member archived. History preserved.'
                  : 'Member restored.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GymService(),
      builder: (context, _) {
        final customer = GymService().getCustomerById(widget.customerId);
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Member Not Found')),
            body: const Center(child: Text('Customer was deleted or does not exist.')),
          );
        }

        final monthKey = GymDateUtils.toMonthKey(_displayedMonth);
        final paymentRecord = GymService().getPaymentRecord(customer.id, monthKey);
        final attendanceSummary = GymService().getMonthlyAttendanceSummary(customer.id, monthKey);
        final currency = GymService().settings.currencySymbol;
        final unpaidAttendedMonths = GymService().getUnpaidAttendedMonthKeys(customer.id);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(customer.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.badge_rounded, color: Color(0xFFE53935)),
                tooltip: 'View Member Card / Entry Form',
                onPressed: () => MemberCardScreen.push(context, customer: customer),
              ),
              IconButton(
                icon: Icon(Icons.call_rounded, color: AppColors.primary),
                tooltip: 'Call Member',
                onPressed: () => PhoneService().makeCall(
                  customer.phone,
                  context: context,
                  memberName: customer.name,
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined, color: AppColors.textSecondary),
                tooltip: 'Edit Profile',
                onPressed: () => _editCustomer(customer),
              ),
              IconButton(
                icon: Icon(
                  customer.isActive
                      ? Icons.archive_outlined
                      : Icons.unarchive_outlined,
                ),
                tooltip: customer.isActive
                    ? 'Archive Member'
                    : 'Restore Member',
                onPressed: () => _archiveCustomer(customer),
              ),
            ],
          ),
          body: Column(
            children: [
              if (!customer.isActive)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Archived member • History preserved'),
                ),
              if (customer.isActive && GymService().hasPaidMembership(customer))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => MarkPaymentDialog.showRenewal(
                        context,
                        customer: customer,
                      ),
                      icon: const Icon(Icons.autorenew),
                      label: const Text('Renew Membership'),
                    ),
                  ),
                ),
              // Sleek Segmented TabBar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.primary,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: AppColors.primaryOn,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  dividerColor: Colors.transparent,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payment_rounded, size: 15),
                          const SizedBox(width: 4),
                          const Text('Payments'),
                          if (unpaidAttendedMonths.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: const BoxDecoration(
                                color: Color(0xFFD50000),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${unpaidAttendedMonths.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Attendance'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Payments & Billing
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Overview Banner
                          _buildProfileCard(customer),
                          const SizedBox(height: 16),

                          // Unpaid Attended Dues Alert Card (if any)
                          if (unpaidAttendedMonths.isNotEmpty) ...[
                            _buildDuesAlertBanner(customer, unpaidAttendedMonths, currency),
                            const SizedBox(height: 16),
                          ],

                          // Selected Month Payment Card
                          _buildMonthPaymentCard(customer, monthKey, paymentRecord, currency, attendanceSummary),
                          const SizedBox(height: 24),

                          // Full Payment History Section with context-aware attendance badges
                          _buildPaymentHistorySection(customer, currency),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),

                    // Tab 2: Attendance & Tracking
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Attendance Overview & Direct Settle Card
                          _buildAttendanceOverviewCard(customer, monthKey, currency),
                          const SizedBox(height: 16),

                          // Month Navigation & Mark All Menu
                          _buildMonthSelectorHeader(customer),
                          const SizedBox(height: 14),

                          // Interactive Calendar Grid
                          _buildInteractiveCalendar(customer, monthKey),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileCard(Customer customer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomerAvatar(
            imagePath: customer.imagePath,
            imageBase64: customer.imageBase64,
            name: customer.name,
            radius: 34,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: customer.isActive
                            ? AppColors.paid.withValues(alpha: 0.15)
                            : AppColors.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        customer.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          color: customer.isActive ? AppColors.paid : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    InkWell(
                      onTap: () {
                        PhoneService().makeCall(
                          customer.phone,
                          context: context,
                          memberName: customer.name,
                        );
                      },
                          borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_outlined, color: AppColors.secondary, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            customer.phone,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      // Call button pill
                      InkWell(
                        onTap: () {
                          PhoneService().makeCall(
                            customer.phone,
                            context: context,
                            memberName: customer.name,
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.call_rounded, size: 11, color: AppColors.primary),
                              SizedBox(width: 4),
                              Text(
                                'Call',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // WhatsApp pill
                      InkWell(
                        onTap: () {
                          final gymName = GymService().settings.gymName;
                          WhatsAppService().openWhatsApp(
                            phone: customer.phone,
                            message: 'Hello ${customer.name}! Greetings from $gymName.',
                            context: context,
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.whatsapp.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.whatsapp.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_rounded, size: 10, color: AppColors.whatsapp),
                              SizedBox(width: 4),
                              Text(
                                'WhatsApp',
                                style: TextStyle(
                                  color: AppColors.whatsapp,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event_outlined, color: AppColors.textMuted, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'Joined ${GymDateUtils.formatDate(customer.joinDate)}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final settings = GymService().settings;
                    final currency = settings.currencySymbol;
                    final price = settings.getPriceForDuration(customer.planType, customer.planDurationMonths);
                    Color planColor;
                    IconData planIcon;

                    switch (customer.planType) {
                      case CustomerPlan.personalTraining:
                        planColor = AppColors.secondary;
                        planIcon = Icons.sports_martial_arts_rounded;
                        break;
                      case CustomerPlan.personalTrainingDiet:
                        planColor = const Color(0xFFFF9100);
                        planIcon = Icons.restaurant_menu_rounded;
                        break;
                      case CustomerPlan.normal:
                      default:
                        planColor = AppColors.primary;
                        planIcon = Icons.fitness_center_rounded;
                        break;
                    }

                    final durationText = customer.planDurationMonths > 1
                        ? '${customer.planDurationMonths} Mo'
                        : 'Monthly';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: planColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: planColor.withValues(alpha: 0.45)),
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          Icon(planIcon, size: 14, color: planColor),
                          const SizedBox(width: 6),
                          Text(
                            CustomerPlan.getLabel(customer.planType),
                            style: TextStyle(
                              color: planColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(color: planColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${GymDateUtils.formatCurrency(price, symbol: currency)} ($durationText)',
                            style: TextStyle(
                              color: planColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (context) {
                    final gym = GymService();
                    final hasPaid = gym.hasPaidMembership(customer);

                    if (!hasPaid) {
                      final stage = gym.getMemberLifecycleStage(
                        customer,
                        GymDateUtils.toMonthKey(DateTime.now()),
                      );
                      final isNew = stage == MemberLifecycleStage.newMember;
                      final statusColor = isNew ? AppColors.secondary : AppColors.absent;

                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              isNew ? Icons.fiber_new_rounded : Icons.warning_amber_rounded,
                              size: 12,
                              color: statusColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isNew ? 'New Member • Payment Pending' : 'Membership Unpaid • Due',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final expiry = gym.getCustomerExpiryDate(customer);
                    final days = gym.getDaysUntilExpiry(customer);
                    final isExpired = days < 0;
                    final isDueSoon = days >= 0 && days <= 7;
                    final statusColor = isExpired
                        ? AppColors.absent
                        : (isDueSoon ? AppColors.pending : AppColors.paid);

                    return Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(Icons.event_available_rounded, size: 12, color: statusColor),
                          const SizedBox(width: 5),
                          Text(
                            isExpired
                                ? 'Expired on ${GymDateUtils.formatDate(expiry)} (${days.abs()}d ago)'
                                : 'Valid until ${GymDateUtils.formatDate(expiry)} (${days}d left)',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (customer.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    customer.notes,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.surfaceBorder),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => MemberCardScreen.push(context, customer: customer),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFB71C1C).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFB71C1C).withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB71C1C).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.badge_rounded, color: Color(0xFFB71C1C), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Member Entry Card & Ledger',
                                style: TextStyle(
                                  color: Color(0xFFB71C1C),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB71C1C),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${customer.cardNumber.isNotEmpty ? customer.cardNumber : customer.id.replaceAll(RegExp(r'\D'), '').padLeft(3, '0')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'View physical card, 12-month dues, measurements & export PDF',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFB71C1C), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPaymentCard(
    Customer customer,
    String monthKey,
    PaymentRecord record,
    String currency,
    Map<String, int> attendanceSummary,
  ) {
    final stage = GymService().getMemberLifecycleStage(customer, monthKey);
    final isPaid = stage.isPaid;
    final isNew = stage.isNew;
    final presentDays = attendanceSummary['present'] ?? 0;
    final isNotEnrolled = stage.isNotEnrolled && presentDays == 0;
    final now = DateTime.now();
    final currentMonthKey = GymDateUtils.toMonthKey(now);
    final isPastMonth = monthKey.compareTo(currentMonthKey) < 0;

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;
    String subtitleText;

    if (isPaid) {
      badgeColor = AppColors.paid;
      badgeIcon = Icons.check_circle_rounded;
      badgeText = record.isPartiallyPaid
          ? 'PARTIAL · BAL ${GymDateUtils.formatCurrency(record.balanceDue, symbol: currency)}'
          : 'PAID';
      subtitleText = 'Monthly gym fee • Settled & Active';
    } else if (isNotEnrolled) {
      badgeColor = AppColors.textMuted;
      badgeIcon = Icons.person_off_rounded;
      badgeText = 'NOT ENROLLED';
      subtitleText = 'Member joined ${GymDateUtils.formatDate(customer.joinDate)} • Not enrolled this month';
    } else if (isPastMonth && presentDays == 0) {
      badgeColor = AppColors.pending;
      badgeIcon = Icons.event_busy_rounded;
      badgeText = '0 ATTENDANCE';
      subtitleText = '0 days attended in ${GymDateUtils.formatMonthYearKey(monthKey)} • Mark attendance first';
    } else if (isNew) {
      badgeColor = const Color(0xFF00B4D8);
      badgeIcon = Icons.waving_hand_rounded;
      badgeText = 'NEW';
      subtitleText = 'New registration • 3-day grace period (0 days attended)';
    } else {
      badgeColor = AppColors.pending;
      badgeIcon = Icons.pending_rounded;
      badgeText = 'DUE';
      subtitleText = 'Monthly gym fee • $presentDays ${presentDays == 1 ? "day" : "days"} attended';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.isDark
              ? (isPaid
                  ? [const Color(0xFF10281E), const Color(0xFF161B24)]
                  : (isNotEnrolled
                      ? [const Color(0xFF181C24), const Color(0xFF161B24)]
                      : (isPastMonth && presentDays == 0
                          ? [const Color(0xFF261D12), const Color(0xFF161B24)]
                          : (isNew
                              ? [const Color(0xFF0C2433), const Color(0xFF161B24)]
                              : [const Color(0xFF281C10), const Color(0xFF161B24)]))))
              : (isPaid
                  ? [const Color(0xFFE8F8EE), const Color(0xFFFFFFFF)]
                  : (isNotEnrolled
                      ? [const Color(0xFFF1F3F5), const Color(0xFFFFFFFF)]
                      : (isPastMonth && presentDays == 0
                          ? [const Color(0xFFFFF8E1), const Color(0xFFFFFFFF)]
                          : (isNew
                              ? [const Color(0xFFE0F7FA), const Color(0xFFFFFFFF)]
                              : [const Color(0xFFFFF3E0), const Color(0xFFFFFFFF)])))),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPaid
              ? AppColors.paid.withValues(alpha: 0.4)
              : (isNotEnrolled
                  ? AppColors.surfaceBorder
                  : (isPastMonth && presentDays == 0
                      ? AppColors.pending.withValues(alpha: 0.35)
                      : (isNew
                          ? const Color(0xFF00B4D8).withValues(alpha: 0.45)
                          : AppColors.pending.withValues(alpha: 0.4)))),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${GymDateUtils.formatMonthYearKey(monthKey)} Payment',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10,
                  vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, color: badgeColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isPaid) ...[
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  GymDateUtils.formatCurrency(record.displayAmount, symbol: currency),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.paid.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Validity: ${record.formattedDateRange}',
                    style: TextStyle(
                      color: AppColors.paid,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => BillHistorySheet.showForPayment(
                      context,
                      customer: customer,
                      payment: record,
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.paid.withValues(alpha: 0.1),
                      foregroundColor: AppColors.paid,
                      side: BorderSide(color: AppColors.paid.withValues(alpha: 0.5)),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 17, color: AppColors.paid),
                    label: const Text(
                      'View Bill',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.paid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => MarkPaymentDialog.show(
                      context,
                      customer: customer,
                      monthYear: monthKey,
                      currentRecord: record,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceElevated,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.surfaceBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text(
                      'Edit Payment',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                final bill = GymService().getOrCreateBillForPayment(customer, record);
                WhatsAppService().sendBillReceipt(context: context, bill: bill);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.whatsapp.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.whatsapp.withValues(alpha: 0.5), width: 1.2),
                ),
                child: const Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_rounded, color: AppColors.whatsapp, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Send Receipt on WhatsApp',
                      style: TextStyle(color: AppColors.whatsapp, fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (isNotEnrolled) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This member was not enrolled in ${GymDateUtils.formatMonthYearKey(monthKey)}. Enrollment started on ${GymDateUtils.formatDate(customer.joinDate)}.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isPastMonth && presentDays == 0 &&
              !record.isMembershipAgreement) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.pending.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.pending.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_busy_rounded, color: AppColors.pending, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '0 Days Attended in ${GymDateUtils.formatMonthYearKey(monthKey)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please mark attendance first for this past month before recording payment.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _tabController.animateTo(1);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.primaryOn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: const Text(
                      'Mark Attendance First',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Flexible(
                  child: Text(
                    GymDateUtils.formatCurrency(record.displayAmount, symbol: currency),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    if (isPastMonth && presentDays > 0 &&
                        !record.isMembershipAgreement) {
                      final parts = monthKey.split('-');
                      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
                      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;
                      final startOfMonth = DateTime(y, m, 1);
                      final endOfMonth = DateTime(y, m, GymDateUtils.daysInMonth(y, m));
                      MarkPaymentDialog.show(
                        context,
                        customer: customer,
                        monthYear: monthKey,
                        currentRecord: record.copyWith(
                          startDate: startOfMonth,
                          endDate: endOfMonth,
                          notes: 'Settlement for $presentDays attended days in ${GymDateUtils.formatMonthYearKey(monthKey)}',
                        ),
                      );
                    } else {
                      MarkPaymentDialog.show(
                        context,
                        customer: customer,
                        monthYear: monthKey,
                        currentRecord: record,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryOn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(
                    Icons.payment_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Mark as Paid',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  WhatsAppService().showWelcomeSheet(
                    context: context,
                    customer: customer,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.waving_hand_rounded, color: Color(0xFF00B4D8), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Send Welcome Message on WhatsApp',
                        style: TextStyle(
                          color: Color(0xFF00B4D8),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (presentDays > 0 || !isPastMonth) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  WhatsAppService().showReminderSheet(
                    context: context,
                    customer: customer,
                    monthYear: monthKey,
                    amount: GymService().pendingAmountOf(record),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.whatsapp.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.whatsapp.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_rounded, color: AppColors.whatsapp, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Send WhatsApp Fee Reminder',
                        style: TextStyle(
                          color: AppColors.whatsapp,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          if (isPaid && record.method != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded, color: AppColors.paid, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Paid via ${record.method!.label}'
                      '${record.paidAt != null ? ' on ${GymDateUtils.formatShortDate(record.paidAt!)}' : ''}'
                      '${record.transactionRef != null && record.transactionRef!.isNotEmpty ? ' (${record.transactionRef})' : ''}',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDuesAlertBanner(
    Customer customer,
    List<String> unpaidMonths,
    String currency,
  ) {
    final gym = GymService();
    int totalAttendedDays = 0;
    double totalDueAmount = 0;

    for (final mKey in unpaidMonths) {
      totalAttendedDays += gym.getUnpaidAttendedDaysInMonth(customer.id, mKey);
      final pay = gym.getPaymentRecord(customer.id, mKey);
      totalDueAmount += gym.pendingAmountOf(pay);
    }

    final earliestMonth = unpaidMonths.first;
    final earliestPay = gym.getPaymentRecord(customer.id, earliestMonth);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFD50000).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD50000).withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD50000).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unpaid Attended Dues Detected',
                      style: const TextStyle(
                        color: Color(0xFFFF5252),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      "${unpaidMonths.length} Month${unpaidMonths.length > 1 ? 's' : ''} with attendance • $totalAttendedDays total attended days",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Text(
                GymDateUtils.formatCurrency(totalDueAmount, symbol: currency),
                style: const TextStyle(
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final parts = earliestMonth.split('-');
                    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
                    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;
                    final startOfMonth = DateTime(y, m, 1);
                    final endOfMonth = DateTime(y, m, GymDateUtils.daysInMonth(y, m));
                    final attendedInEarliest = gym.getUnpaidAttendedDaysInMonth(customer.id, earliestMonth);
                    final defaultFee = earliestPay.displayAmount > 0
                        ? earliestPay.displayAmount
                        : gym.settings.getPriceForDuration(customer.planType, customer.planDurationMonths);
                    MarkPaymentDialog.show(
                      context,
                      customer: customer,
                      monthYear: earliestMonth,
                      currentRecord: earliestPay.copyWith(
                        amount: defaultFee,
                        startDate: startOfMonth,
                        endDate: endOfMonth,
                        notes: 'Settlement for $attendedInEarliest attended days in ${GymDateUtils.formatMonthYearKey(earliestMonth)}',
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5252),
                    side: const BorderSide(color: Color(0xFFFF5252), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 16),
                  label: Text(
                    'Settle Dues (from ${GymDateUtils.formatMonthYearKey(earliestMonth)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverviewCard(
    Customer customer,
    String monthKey,
    String currency,
  ) {
    final gym = GymService();
    Map<String, int> summary;
    String periodLabel;

    if (_isCustomRangeMode && _customStartDate != null && _customEndDate != null) {
      summary = gym.getDateRangeAttendanceSummary(customer.id, _customStartDate!, _customEndDate!);
      periodLabel = '${GymDateUtils.formatShortDate(_customStartDate!)} – ${GymDateUtils.formatShortDate(_customEndDate!)}';
    } else {
      summary = gym.getMonthlyAttendanceSummary(customer.id, monthKey);
      periodLabel = GymDateUtils.formatMonthYearKey(monthKey);
    }

    final present = summary['present'] ?? 0;
    final absent = summary['absent'] ?? 0;
    final rest = summary['rest'] ?? 0;

    final paymentRecord = gym.getPaymentRecord(customer.id, monthKey);
    final unpaidAttendedDays = gym.getUnpaidAttendedDaysInMonth(customer.id, monthKey);
    final coveringPayment = gym.getPaymentCoveringMonth(customer.id, monthKey);
    final isCovered = coveringPayment != null && coveringPayment.isPaid;
    final isFullyPaid = isCovered && unpaidAttendedDays == 0;
    final currentMonthKey = GymDateUtils.toMonthKey(DateTime.now());
    final isPastMonth = monthKey.compareTo(currentMonthKey) < 0;
    final joinMonthKey = GymDateUtils.toMonthKey(customer.joinDate);
    final isBeforeJoinMonth = monthKey.compareTo(joinMonthKey) < 0 && present == 0 && unpaidAttendedDays == 0;

    final effectivePayment = (paymentRecord.isPaid ? paymentRecord : (coveringPayment ?? paymentRecord));
    final fee = effectivePayment.displayAmount > 0
        ? effectivePayment.displayAmount
        : gym.settings.getPriceForDuration(customer.planType, customer.planDurationMonths);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance Overview',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    periodLabel,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isCustomRangeMode = !_isCustomRangeMode;
                    if (_isCustomRangeMode) {
                      final now = DateTime.now();
                      _customStartDate ??= DateTime(now.year, now.month, 1);
                      _customEndDate ??= now;
                    }
                  });
                },
                style: TextButton.styleFrom(
                  backgroundColor: _isCustomRangeMode
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceElevated,
                  foregroundColor: _isCustomRangeMode ? AppColors.primary : AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: _isCustomRangeMode ? AppColors.primary : AppColors.surfaceBorder,
                    ),
                  ),
                ),
                icon: Icon(
                  _isCustomRangeMode ? Icons.date_range_rounded : Icons.tune_rounded,
                  size: 14,
                ),
                label: Text(
                  _isCustomRangeMode ? 'Range Active' : 'Custom Range',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_isCustomRangeMode) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${GymDateUtils.formatShortDate(_customStartDate!)}  ➔  ${GymDateUtils.formatShortDate(_customEndDate!)}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _pickCustomDateRange,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.edit_calendar_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Change',
                            style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildCounterCard(
                  label: 'Present',
                  count: '$present',
                  color: AppColors.paid,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCounterCard(
                  label: 'Absent',
                  count: '$absent',
                  color: AppColors.absent,
                  icon: Icons.cancel_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCounterCard(
                  label: 'Rest Day',
                  count: '$rest',
                  color: AppColors.rest,
                  icon: Icons.bed_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFullyPaid
                  ? AppColors.paid.withValues(alpha: 0.1)
                  : (isBeforeJoinMonth || (isPastMonth && present == 0)
                      ? AppColors.surfaceElevated
                      : (unpaidAttendedDays > 0 || present > 0
                          ? AppColors.pending.withValues(alpha: 0.12)
                          : AppColors.surfaceElevated)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFullyPaid
                    ? AppColors.paid.withValues(alpha: 0.35)
                    : (isBeforeJoinMonth || (isPastMonth && present == 0)
                        ? AppColors.surfaceBorder
                        : (unpaidAttendedDays > 0 || present > 0
                            ? AppColors.pending.withValues(alpha: 0.45)
                            : AppColors.surfaceBorder)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isFullyPaid
                      ? Icons.verified_rounded
                      : (isBeforeJoinMonth
                          ? Icons.info_outline_rounded
                          : (isPastMonth && present == 0
                              ? Icons.event_busy_rounded
                              : (unpaidAttendedDays > 0 || present > 0
                                  ? Icons.warning_amber_rounded
                                  : Icons.info_outline_rounded))),
                  color: isFullyPaid
                      ? AppColors.paid
                      : (isBeforeJoinMonth || (isPastMonth && present == 0)
                          ? AppColors.textSecondary
                          : (unpaidAttendedDays > 0 || present > 0
                                  ? AppColors.pending
                              : AppColors.textSecondary)),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFullyPaid
                            ? 'FEES PAID • ACTIVE COVERAGE'
                            : (isBeforeJoinMonth
                                ? 'NOT ENROLLED • JOINED ${GymDateUtils.formatMonthYearKey(joinMonthKey).toUpperCase()}'
                                : (isPastMonth && present == 0
                                    ? 'NO ATTENDANCE • 0 DAYS'
                                    : (unpaidAttendedDays > 0
                                        ? '$unpaidAttendedDays ATTENDED DAYS • DUE'
                                        : (present > 0
                                            ? '$present ATTENDED DAYS • DUE'
                                            : 'UNPAID • 0 DAYS ATTENDED')))),
                        style: TextStyle(
                          color: isFullyPaid
                              ? AppColors.paid
                              : (isBeforeJoinMonth || (isPastMonth && present == 0)
                                  ? AppColors.textSecondary
                                  : (unpaidAttendedDays > 0 || present > 0
                                          ? AppColors.pending
                                      : AppColors.textSecondary)),
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        isFullyPaid
                            ? 'Payment of ${GymDateUtils.formatCurrency(effectivePayment.amount, symbol: currency)} settled (${effectivePayment.formattedDateRange})'
                            : (isBeforeJoinMonth
                                ? 'Member enrolled on ${GymDateUtils.formatDate(customer.joinDate)}'
                                : (isPastMonth && present == 0
                                    ? 'Mark attendance to record dues for this month'
                                    : 'Subscription fee: ${GymDateUtils.formatCurrency(fee, symbol: currency)}')),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFullyPaid) ...[
                  IconButton(
                    icon: const Icon(Icons.receipt_long_rounded, color: AppColors.paid, size: 18),
                    tooltip: 'View Receipt',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.paid.withValues(alpha: 0.15),
                      padding: const EdgeInsets.all(8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => BillHistorySheet.showForPayment(
                      context,
                      customer: customer,
                      payment: effectivePayment,
                    ),
                  ),
                ] else if (isBeforeJoinMonth || (isPastMonth && present == 0)) ...[
                  // No payment button for pre-join or past months with 0 attendance
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      if (isPastMonth && present > 0) {
                        final parts = monthKey.split('-');
                        final y = int.tryParse(parts[0]) ?? DateTime.now().year;
                        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;
                        final startOfMonth = DateTime(y, m, 1);
                        final endOfMonth = DateTime(y, m, GymDateUtils.daysInMonth(y, m));
                        MarkPaymentDialog.show(
                          context,
                          customer: customer,
                          monthYear: monthKey,
                          currentRecord: paymentRecord.copyWith(
                            startDate: startOfMonth,
                            endDate: endOfMonth,
                            notes: 'Settlement for $present attended days in ${GymDateUtils.formatMonthYearKey(monthKey)}',
                          ),
                        );
                      } else {
                        MarkPaymentDialog.show(
                          context,
                          customer: customer,
                          monthYear: monthKey,
                          currentRecord: paymentRecord,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (unpaidAttendedDays > 0 || present > 0)
                          ? AppColors.pending
                          : AppColors.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.payment_rounded, size: 15),
                    label: Text(
                      (unpaidAttendedDays > 0 || present > 0) ? 'Settle Dues' : 'Pay Now',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelectorHeader(Customer customer) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickMonth,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(_displayedMonth)),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_left_rounded, color: AppColors.textPrimary),
              onPressed: _prevMonth,
              tooltip: 'Previous Month',
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_right_rounded, color: AppColors.textPrimary),
              onPressed: _nextMonth,
              tooltip: 'Next Month',
            ),
            const SizedBox(width: 4),
            _buildMarkMonthMenu(customer),
          ],
        ),
      ],
    );
  }

  Widget _buildMarkMonthMenu(Customer customer) {
    final now = DateTime.now();
    final isFutureMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1)
        .isAfter(DateTime(now.year, now.month, 1));
    if (isFutureMonth) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      tooltip: 'Mark Month Options',
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.surfaceBorder),
      ),
      onSelected: (action) => _handleMonthAction(action, customer),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'present_sundays_rest',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.paid.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.done_all_rounded, color: AppColors.paid, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mark Present (Sundays Rest)',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'Mon–Sat Present, Sundays Rest',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'present_all',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.paid.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.paid, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mark 100% Present',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'All days including Sundays',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'absent_all',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.absent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cancel_outlined, color: AppColors.absent, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mark Whole Month Absent',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'Set all month days to Absent',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem(
          value: 'custom',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune_rounded, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'More Options...',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'Custom range, rest days & preview',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl_rounded, color: AppColors.primary, size: 14),
            const SizedBox(width: 4),
            Text(
              'Mark Month',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMonthAction(String action, Customer customer) async {
    final monthName = GymDateUtils.formatMonthYearKey(GymDateUtils.toMonthKey(_displayedMonth));
    final now = DateTime.now();
    final isCurrentMonth = now.year == _displayedMonth.year && now.month == _displayedMonth.month;
    final isFutureMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1)
        .isAfter(DateTime(now.year, now.month, 1));

    if (isFutureMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot mark attendance for future months.'),
          backgroundColor: AppColors.pending,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (action == 'custom') {
      final updated = await MarkMonthAttendanceDialog.show(
        context,
        customer: customer,
        month: _displayedMonth,
      );
      if (updated == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated attendance for $monthName.'),
            backgroundColor: AppColors.paid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'present_sundays_rest') {
      await GymService().setMonthAttendance(
        customerId: customer.id,
        year: _displayedMonth.year,
        month: _displayedMonth.month,
        status: AttendanceStatus.present,
        excludeSundays: true,
        sundayStatus: AttendanceStatus.rest,
        upToTodayOnly: isCurrentMonth,
      );
      if (mounted) {
        final label = isCurrentMonth ? 'up to today (Sundays Rest)' : 'as Present (Sundays Rest)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked $monthName $label'),
            backgroundColor: AppColors.paid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'present_all') {
      await GymService().setMonthAttendance(
        customerId: customer.id,
        year: _displayedMonth.year,
        month: _displayedMonth.month,
        status: AttendanceStatus.present,
        excludeSundays: false,
        upToTodayOnly: isCurrentMonth,
      );
      if (mounted) {
        final label = isCurrentMonth ? 'days up to today as Present' : 'all days of $monthName as Present';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked $label!'),
            backgroundColor: AppColors.paid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (action == 'absent_all') {
      await GymService().setMonthAttendance(
        customerId: customer.id,
        year: _displayedMonth.year,
        month: _displayedMonth.month,
        status: AttendanceStatus.absent,
        upToTodayOnly: isCurrentMonth,
      );
      if (mounted) {
        final label = isCurrentMonth ? 'days up to today as Absent' : 'all days of $monthName as Absent';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked $label.'),
            backgroundColor: AppColors.absent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildCounterCard({
    required String label,
    required String count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveCalendar(Customer customer, String monthKey) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final totalDays = GymDateUtils.daysInMonth(year, month);
    final firstDayOfWeek = DateTime(year, month, 1).weekday % 7; // 0 for Sunday

    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isFutureMonth = DateTime(year, month, 1).isAfter(DateTime(now.year, now.month, 1));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFutureMonth
                    ? 'Future Month: Attendance cannot be marked in advance'
                    : 'Tap any past or today’s date to toggle attendance',
                style: TextStyle(
                  color: isFutureMonth ? AppColors.pending : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _buildLegendItem(AppColors.paid, 'Present'),
                  _buildLegendItem(AppColors.absent, 'Absent'),
                  _buildLegendItem(AppColors.rest, 'Rest Day'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Weekday header
          Row(
            children: weekdays.map((w) {
              return Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      color: w == 'Sun' ? AppColors.rest : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalDays + firstDayOfWeek,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index < firstDayOfWeek) {
                return const SizedBox.shrink();
              }
              final day = index - firstDayOfWeek + 1;
              final date = DateTime(year, month, day);
              final dateKey = GymDateUtils.toDateKey(date);
              final targetDay = DateTime(date.year, date.month, date.day);
              final isToday = targetDay == today;
              final isFuture = targetDay.isAfter(today);

              final attendance = GymService().getAttendance(customer.id, dateKey);
              final status = attendance?.status;

              Color bgColor = isFuture ? AppColors.surfaceElevated.withValues(alpha: 0.35) : AppColors.surfaceElevated;
              Color borderColor = Colors.transparent;
              Color textColor = isFuture ? AppColors.textMuted.withValues(alpha: 0.35) : (status != null ? Colors.white : AppColors.textPrimary);
              IconData? statusIcon;

              if (!isFuture) {
                if (status == AttendanceStatus.present) {
                  bgColor = AppColors.paid.withValues(alpha: 0.2);
                  borderColor = AppColors.paid;
                  statusIcon = Icons.check_rounded;
                } else if (status == AttendanceStatus.absent && attendance != null) {
                  bgColor = AppColors.absent.withValues(alpha: 0.15);
                  borderColor = AppColors.absent;
                  statusIcon = Icons.close_rounded;
                } else if (status == AttendanceStatus.rest) {
                  bgColor = AppColors.rest.withValues(alpha: 0.2);
                  borderColor = AppColors.rest;
                  statusIcon = Icons.bed_rounded;
                }
              }

              final isInCustomRange = _isCustomRangeMode &&
                  _customStartDate != null &&
                  _customEndDate != null &&
                  !date.isBefore(DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day)) &&
                  !date.isAfter(DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day));

              if (isInCustomRange && !isFuture) {
                if (status == null) {
                  bgColor = AppColors.primary.withValues(alpha: 0.1);
                }
                if (borderColor == Colors.transparent) {
                  borderColor = AppColors.primary.withValues(alpha: 0.55);
                }
              }

              if (isToday) {
                borderColor = AppColors.primary;
              }

              return InkWell(
                onTap: isFuture
                    ? null
                    : () {
                        // Cycle: present -> absent -> rest -> present
                        AttendanceStatus nextStatus;
                        if (status == null || status == AttendanceStatus.absent) {
                          nextStatus = AttendanceStatus.present;
                        } else if (status == AttendanceStatus.present) {
                          nextStatus = AttendanceStatus.absent;
                        } else {
                          nextStatus = AttendanceStatus.rest;
                        }
                        GymService().toggleAttendance(customer.id, dateKey, nextStatus);
                      },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFuture
                          ? AppColors.surfaceBorder.withValues(alpha: 0.3)
                          : (borderColor != Colors.transparent ? borderColor : AppColors.surfaceBorder),
                      width: isToday ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (statusIcon != null && !isFuture)
                        Positioned(
                          bottom: 2,
                          child: Icon(
                            statusIcon,
                            size: 10,
                            color: borderColor,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentHistorySection(Customer customer, String currency) {
    final gym = GymService();
    final history = gym.getCustomerPaymentHistory(customer.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'Payment History',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Text(
                  "${history.length} Record${history.length != 1 ? 's' : ''}",
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => BillHistorySheet.show(
                    context,
                    customer: customer,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 14),
                  label: Text(
                    'All Bills (${gym.getAllBillsForCustomer(customer.id).length})',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (history.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Center(
              child: Text(
                'No past payment records yet.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = history[i];
              final unpaidAttended = gym.getUnpaidAttendedDaysInMonth(customer.id, item.monthYear);
              final coveredAttended = gym.getAttendedDaysCoveredByPayment(customer.id, item);
              final hasUnpaidDues = !item.isPaid && unpaidAttended > 0;
              final isCustomCycle = item.startDate != null &&
                  (item.startDate!.day != 1 || item.endDate != null);
              final periodTitle = isCustomCycle
                  ? '${GymDateUtils.formatMonthYearKey(item.monthYear)} (${GymDateUtils.formatShortDate(item.effectiveStartDate)} – ${GymDateUtils.formatShortDate(item.effectiveEndDate)})'
                  : GymDateUtils.formatMonthYearKey(item.monthYear);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: item.isPaid
                        ? AppColors.surfaceBorder
                        : (hasUnpaidDues ? AppColors.pending.withValues(alpha: 0.4) : AppColors.surfaceBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: item.isPaid
                            ? AppColors.paid.withValues(alpha: 0.15)
                            : (hasUnpaidDues
                                ? AppColors.pending.withValues(alpha: 0.15)
                                : AppColors.surfaceElevated),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.isPaid
                            ? Icons.check_circle_rounded
                            : (hasUnpaidDues ? Icons.warning_amber_rounded : Icons.pending_rounded),
                        color: item.isPaid
                            ? AppColors.paid
                            : (hasUnpaidDues ? AppColors.pending : AppColors.textMuted),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            periodTitle,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (item.isPaid) ...[
                            if (coveredAttended > 0) ...[
                              Text(
                                '✓ $coveredAttended Days Attended • Paid ${item.paidAt != null ? "on ${GymDateUtils.formatShortDate(item.paidAt!)}" : ""}',
                                style: TextStyle(
                                  color: AppColors.paid,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Active Coverage (${GymDateUtils.formatShortDate(item.effectiveStartDate)} – ${GymDateUtils.formatShortDate(item.effectiveEndDate)}) • Paid ${item.paidAt != null ? "on ${GymDateUtils.formatShortDate(item.paidAt!)}" : ""}',
                                style: const TextStyle(
                                  color: AppColors.paid,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ] else if (unpaidAttended > 0) ...[
                            Text(
                              '⚠️ $unpaidAttended Days Attended • Payment Due',
                              style: TextStyle(
                                color: AppColors.pending,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ] else ...[
                            Text(
                              '0 Days Attended • Pending',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          GymDateUtils.formatCurrency(item.displayAmount, symbol: currency),
                          style: TextStyle(
                            color: item.isPaid ? AppColors.paid : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (hasUnpaidDues)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'DUE',
                              style: TextStyle(
                                color: AppColors.pending,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    if (item.isPaid) ...[
                      IconButton(
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: const Icon(Icons.receipt_long_rounded, color: AppColors.paid, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.paid.withValues(alpha: 0.15),
                          padding: const EdgeInsets.all(6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: AppColors.paid.withValues(alpha: 0.4)),
                          ),
                        ),
                        tooltip: 'View Bill / Receipt',
                        onPressed: () {
                          BillHistorySheet.showForPayment(
                            context,
                            customer: customer,
                            payment: item,
                          );
                        },
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: () => MarkPaymentDialog.show(
                          context,
                          customer: customer,
                          monthYear: item.monthYear,
                          currentRecord: item,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasUnpaidDues ? AppColors.pending : AppColors.surfaceElevated,
                          foregroundColor: hasUnpaidDues ? Colors.black : AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: hasUnpaidDues ? AppColors.pending : AppColors.surfaceBorder,
                            ),
                          ),
                        ),
                        child: Text(
                          hasUnpaidDues ? 'Settle' : 'Pay',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
