import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/customer.dart';
import '../../theme/app_theme.dart';

class MembershipDonutChart extends StatefulWidget {
  final List<Customer> liveMembers;
  final List<Customer> expiring1to3;
  final List<Customer> expiring4to7;
  final List<Customer> expiring8to15;
  final List<Customer> expiredMembers;
  final int inactiveCount;
  final int totalMembers;
  final void Function(
    String title,
    String subtitle,
    List<Customer> members,
    Color color,
    IconData icon,
  )? onSelectStage;

  const MembershipDonutChart({
    super.key,
    required this.liveMembers,
    required this.expiring1to3,
    required this.expiring4to7,
    required this.expiring8to15,
    required this.expiredMembers,
    required this.inactiveCount,
    required this.totalMembers,
    this.onSelectStage,
  });

  @override
  State<MembershipDonutChart> createState() => _MembershipDonutChartState();
}

class _MembershipDonutChartState extends State<MembershipDonutChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final totalActive = widget.liveMembers.length +
        widget.expiring1to3.length +
        widget.expiring4to7.length +
        widget.expiring8to15.length;

    final totalAll = widget.totalMembers > 0 ? widget.totalMembers : 1;
    final activePct = (totalActive / totalAll * 100).round();

    final segments = [
      _MembershipSegment(
        title: 'Healthy Active',
        subtitle: 'Memberships with >15 days remaining',
        count: widget.liveMembers.length,
        color: AppColors.paid,
        icon: Icons.verified_user_rounded,
        members: widget.liveMembers,
      ),
      _MembershipSegment(
        title: 'Expiring in 1–3 Days',
        subtitle: 'Urgent renewal needed within 72h',
        count: widget.expiring1to3.length,
        color: const Color(0xFFFF5252),
        icon: Icons.alarm_rounded,
        members: widget.expiring1to3,
      ),
      _MembershipSegment(
        title: 'Expiring in 4–7 Days',
        subtitle: 'Expiring this week',
        count: widget.expiring4to7.length,
        color: const Color(0xFFFF9100),
        icon: Icons.upcoming_rounded,
        members: widget.expiring4to7,
      ),
      _MembershipSegment(
        title: 'Expiring in 8–15 Days',
        subtitle: 'Upcoming in next 2 weeks',
        count: widget.expiring8to15.length,
        color: const Color(0xFF448AFF),
        icon: Icons.calendar_month_rounded,
        members: widget.expiring8to15,
      ),
      _MembershipSegment(
        title: 'Expired',
        subtitle: 'Past renewal date',
        count: widget.expiredMembers.length,
        color: const Color(0xFFD50000),
        icon: Icons.cancel_rounded,
        members: widget.expiredMembers,
      ),
      if (widget.inactiveCount > 0)
        _MembershipSegment(
          title: 'Inactive',
          subtitle: 'Deactivated memberships',
          count: widget.inactiveCount,
          color: AppColors.textMuted.withValues(alpha: 0.5),
          icon: Icons.pause_circle_rounded,
          members: const [],
        ),
    ];

    final nonZeroSegments = segments.where((s) => s.count > 0).toList();

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
                child: Icon(Icons.pie_chart_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Membership Distribution',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Health Breakdown & Renewal Urgency',
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
                  color: AppColors.paid.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activePct% Active',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.paid,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Donut Chart with Centered KPI
          if (nonZeroSegments.isEmpty)
            _buildEmptyState()
          else
            SizedBox(
              height: 200,
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
                      centerSpaceRadius: 56,
                      sections: List.generate(nonZeroSegments.length, (i) {
                        final isTouched = i == _touchedIndex;
                        final segment = nonZeroSegments[i];
                        final radius = isTouched ? 30.0 : 22.0;

                        return PieChartSectionData(
                          color: segment.color,
                          value: segment.count.toDouble(),
                          title: '', // Kept clean, numbers displayed in center or legend
                          radius: radius,
                        );
                      }),
                    ),
                  ),

                  // Center Text Info
                  _buildCenterInfo(nonZeroSegments, totalActive, widget.totalMembers),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Segment Tiles / Legend
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: segments.map((seg) {
              final pct = widget.totalMembers > 0
                  ? (seg.count / widget.totalMembers * 100).round()
                  : 0;

              return InkWell(
                onTap: seg.members.isNotEmpty && widget.onSelectStage != null
                    ? () => widget.onSelectStage!(
                          seg.title,
                          seg.subtitle,
                          seg.members,
                          seg.color,
                          seg.icon,
                        )
                    : null,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: seg.count > 0 && seg.color == const Color(0xFFFF5252)
                          ? seg.color.withValues(alpha: 0.5)
                          : AppColors.surfaceBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: seg.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        seg.title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: seg.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${seg.count} ($pct%)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: seg.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterInfo(
    List<_MembershipSegment> nonZeroSegments,
    int totalActive,
    int totalMembers,
  ) {
    if (_touchedIndex >= 0 && _touchedIndex < nonZeroSegments.length) {
      final touched = nonZeroSegments[_touchedIndex];
      final pct = totalMembers > 0 ? (touched.count / totalMembers * 100).round() : 0;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${touched.count}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: touched.color,
            ),
          ),
          Text(
            '$pct% of Total',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
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
          '$totalActive',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          'Active / $totalMembers',
          style: TextStyle(
            fontSize: 11,
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
          Icon(Icons.groups_outlined, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'No Members Registered',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add members to view live membership health and expiry funnel distributions.',
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

class _MembershipSegment {
  final String title;
  final String subtitle;
  final int count;
  final Color color;
  final IconData icon;
  final List<Customer> members;

  _MembershipSegment({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.icon,
    required this.members,
  });
}
