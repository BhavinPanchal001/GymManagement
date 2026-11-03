import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../services/gym_service.dart';
import '../../services/phone_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/pending_member_cards.dart';
import '../../widgets/pending_member_detail_card.dart';
import '../../widgets/mark_payment_dialog.dart';
import '../../widgets/collect_balance_dialog.dart';
import '../../widgets/bill_receipt_dialog.dart';
import '../../widgets/whatsapp_reminder_sheet.dart';
import '../customers/customer_detail_screen.dart';

/// Focused review of pending members, separate from the reporting tools.
class PendingMembersScreen extends StatefulWidget {
  final DateTimeRange? initialRange;
  const PendingMembersScreen({super.key, this.initialRange});

  @override
  State<PendingMembersScreen> createState() => _PendingMembersScreenState();
}

class _PendingMembersScreenState extends State<PendingMembersScreen> {
  late DateTimeRange _range;
  DateTime get _rangeStart => _range.start;
  DateTime get _rangeEnd => _range.end;

  @override
  void initState() {
    super.initState();
    _range =
        widget.initialRange ??
        DateTimeRange(
          start: GymService().outstandingStartDate,
          end: GymService().outstandingEndDate,
        );
  }

  Future<void> _pickDateRange() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final limit = DateTime(today.year + 1, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      helpText: 'Select billing period start dates',
      firstDate: _range.start.isBefore(DateTime(2022))
          ? _range.start
          : DateTime(2022),
      lastDate: _range.end.isAfter(limit) ? _range.end : limit,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: AppColors.primaryOn,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([GymService(), ThemeService()]),
    builder: (context, _) {
      final gym = GymService();
      final members =
          gym.getPendingDuesByMember(
            _rangeStart,
            _rangeEnd,
            exactDates: true,
          )..sort((a, b) {
            final amount = b.totalPendingAmount.compareTo(a.totalPendingAmount);
            return amount != 0
                ? amount
                : a.customer.name.toLowerCase().compareTo(
                    b.customer.name.toLowerCase(),
                  );
          });
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Pending members')),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Tooltip(
                  message: 'Select date range',
                  child: OutlinedButton(
                    onPressed: _pickDateRange,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      backgroundColor: AppColors.surfaceElevated,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      side: BorderSide(color: AppColors.surfaceBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            GymDateUtils.formatDateRange(
                              _rangeStart,
                              _rangeEnd,
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.done_all_rounded,
                                color: AppColors.dynamicPaid,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No pending bills',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Choose another date range to review members.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : PendingMemberCards(
                        key: ValueKey('${_range.start}:${_range.end}'),
                        memberIds: members.map((m) => m.customer.id).toList(),
                        cardBuilder: (context, index) => _buildDetailedCard(
                          members[index],
                          gym.settings.currencySymbol,
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  void _openWhatsAppReminder(
    Customer customer,
    String monthYear,
    double amount,
  ) {
    WhatsAppReminderSheet.show(
      context,
      customer: customer,
      monthYear: monthYear,
      amount: amount,
    );
  }

  Future<void> _openMarkPaid(Customer customer, PaymentRecord record) async {
    if (record.isPaid) {
      final current = GymService().getPaymentById(record.id);
      if (current == null || current.balanceDue <= 0) return;
      final bill = await CollectBalanceDialog.show(context, current);
      if (bill != null && mounted) {
        await BillReceiptDialog.show(context, bill: bill);
      }
      return;
    }
    final success = await MarkPaymentDialog.show(
      context,
      customer: customer,
      monthYear: record.monthYear,
      currentRecord: record,
    );

    if (success == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment recorded for ${customer.name}!'),
          backgroundColor: AppColors.paid,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildDetailedCard(MemberPendingSummary item, String currency) {
    final records = List<PaymentRecord>.of(item.pendingRecords)
      ..sort((a, b) => a.effectiveStartDate.compareTo(b.effectiveStartDate));
    return PendingMemberDetailCard(
      summary: item,
      startDate: _rangeStart,
      endDate: _rangeEnd,
      currency: currency,
      onOpenMember: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CustomerDetailScreen(customerId: item.customer.id),
          ),
        );
      },
      onCollect: () => _openMarkPaid(item.customer, records.first),
      onReminder: () => _openWhatsAppReminder(
        item.customer,
        records.last.monthYear,
        item.totalPendingAmount,
      ),
      onCall: () => PhoneService().makeCall(
        item.customer.phone,
        context: context,
        memberName: item.customer.name,
      ),
    );
  }
}
