import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../models/payment.dart';
import '../services/gym_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import 'customer_avatar.dart';

class PendingMemberDetailCard extends StatelessWidget {
  final MemberPendingSummary summary;
  final DateTime startDate, endDate;
  final String currency;
  final VoidCallback onCollect, onReminder, onCall, onOpenMember;

  const PendingMemberDetailCard({
    super.key,
    required this.summary,
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.onCollect,
    required this.onReminder,
    required this.onCall,
    required this.onOpenMember,
  });

  String _money(double amount) =>
      GymDateUtils.formatCurrency(amount, symbol: currency);

  @override
  Widget build(BuildContext context) {
    final member = summary.customer;
    final gym = GymService();
    final attendance = gym.getDateRangeAttendanceSummary(
      member.id,
      startDate,
      endDate,
    );
    final received = summary.pendingRecords.fold<double>(
      0,
      (sum, record) => sum + record.amount,
    );
    final fee = summary.pendingRecords.fold<double>(
      0,
      (sum, record) => sum + record.totalDue,
    );
    final credit = summary.pendingRecords.fold<double>(
      0,
      (sum, record) => sum + record.creditApplied,
    );
    final records = List<PaymentRecord>.of(summary.pendingRecords)
      ..sort((a, b) => a.effectiveStartDate.compareTo(b.effectiveStartDate));
    final lastEnd = records
        .map((r) => r.effectiveEndDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final today = DateUtils.dateOnly(DateTime.now());
    final overdue = records.any(
      (r) => DateUtils.dateOnly(r.effectiveEndDate).isBefore(today),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(member),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.pending.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.pending.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        _label('PENDING BALANCE'),
                        Text(
                          overdue ? 'OVERDUE' : 'PAYMENT DUE',
                          style: const TextStyle(
                            color: AppColors.pending,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _money(summary.totalPendingAmount),
                      style: const TextStyle(
                        color: AppColors.pending,
                        fontSize: 27,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 12,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Billed ${_money(fee)}',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          'Received ${_money(received)}',
                          style: TextStyle(
                            color: AppColors.dynamicPaid,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (credit > 0)
                          Text(
                            'Credit ${_money(credit)}',
                            style: TextStyle(
                              color: AppColors.dynamicPaid,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 6,
                children: [
                  _label('ATTENDANCE'),
                  Text(
                    'Selected date range',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Total present',
                      attendance['present']!,
                      AppColors.dynamicPaid,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _stat(
                      'Absent',
                      attendance['absent']!,
                      AppColors.dynamicAbsent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _stat(
                      'Rest days',
                      attendance['rest']!,
                      AppColors.dynamicRest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 6,
                children: [
                  _label(
                    records.length == 1
                        ? 'UNPAID PERIOD'
                        : 'UNPAID BILLING WINDOW',
                  ),
                  Text(
                    '${records.length} ${records.length == 1 ? 'period' : 'periods'}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                GymDateUtils.formatDateRange(
                  records.first.effectiveStartDate,
                  lastEnd,
                ),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Joined ${GymDateUtils.formatDate(member.joinDate)}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
              const SizedBox(height: 10),
              PendingMemberCardActions(
                isPartialPayment: records.first.isPaid,
                onCollect: onCollect,
                onReminder: onReminder,
                onCall: onCall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Customer member) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.surfaceElevated,
          Color.alphaBlend(
            AppColors.primary.withValues(alpha: 0.13),
            AppColors.surface,
          ),
        ],
      ),
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          children: [
            CustomerAvatar(
              imagePath: member.imagePath,
              imageBase64: member.imageBase64,
              name: member.name,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 34),
                    child: Tooltip(
                      message: 'Open member profile',
                      child: InkWell(
                        onTap: onOpenMember,
                        borderRadius: BorderRadius.circular(6),
                        child: Text(
                          member.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (member.cardNumber.isNotEmpty) '#${member.cardNumber}',
                      member.isActive ? 'Active' : 'Archived',
                      CustomerPlan.getShortLabel(member.planType),
                      member.durationLabel,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    member.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: -4,
          right: -4,
          child: IconButton.filledTonal(
            tooltip: 'View member details',
            onPressed: onOpenMember,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.10),
              foregroundColor: AppColors.primary,
              minimumSize: const Size(32, 32),
              maximumSize: const Size(32, 32),
              padding: const EdgeInsets.all(6),
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.north_east_rounded, size: 18),
          ),
        ),
      ],
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: AppColors.textSecondary,
      fontSize: 9,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _stat(String label, int count, Color color) => Container(
    key: ValueKey('attendance-$label'),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
      ],
    ),
  );
}

class PendingMemberCardActions extends StatelessWidget {
  final bool isPartialPayment;
  final VoidCallback onCollect, onReminder, onCall;

  const PendingMemberCardActions({
    super.key,
    required this.isPartialPayment,
    required this.onCollect,
    required this.onReminder,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(11),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onCollect,
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(
            isPartialPayment ? 'Collect balance' : 'Record payment',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.primaryOn,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            shape: shape,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call_outlined, size: 17),
                label: const Text(
                  'Call',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  shape: shape,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onReminder,
                icon: const Icon(Icons.chat_outlined, size: 17),
                label: const Text(
                  'Remind',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dynamicPaid,
                  backgroundColor: AppColors.dynamicPaid.withValues(
                    alpha: 0.05,
                  ),
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  shape: shape,
                  side: BorderSide(
                    color: AppColors.dynamicPaid.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
