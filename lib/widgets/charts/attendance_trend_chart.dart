import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class AttendanceTrendChart extends StatefulWidget {
  final GymService gym;

  const AttendanceTrendChart({
    super.key,
    required this.gym,
  });

  @override
  State<AttendanceTrendChart> createState() => _AttendanceTrendChartState();
}

class _AttendanceTrendChartState extends State<AttendanceTrendChart> {
  int _daysCount = 7; // 7 or 14

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final points = <_AttendanceDayPoint>[];

    for (int i = _daysCount - 1; i >= 0; i--) {
      final dt = now.subtract(Duration(days: i));
      final dateKey = GymDateUtils.toDateKey(dt);
      final overview = widget.gym.getDailyOverview(dateKey);
      final present = overview['present'] ?? 0;
      final total = overview['total'] ?? 0;

      points.add(
        _AttendanceDayPoint(
          date: dt,
          dateKey: dateKey,
          dayLabel: _daysCount <= 7 ? DateFormat('E').format(dt) : DateFormat('d/M').format(dt),
          presentCount: present,
          totalActive: total,
        ),
      );
    }

    final totalActive = widget.gym.customers.where((c) => c.isActive).length;
    final totalAttendanceSum = points.fold<int>(0, (sum, p) => sum + p.presentCount);
    final avgAttendance = (totalAttendanceSum / _daysCount).toStringAsFixed(1);

    int maxTurnout = 0;
    String peakDayLabel = 'N/A';
    for (final p in points) {
      if (p.presentCount > maxTurnout) {
        maxTurnout = p.presentCount;
        peakDayLabel = DateFormat('E, d MMM').format(p.date);
      }
    }

    final hasActivity = totalAttendanceSum > 0;

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
                child: Icon(Icons.insights_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Trends',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Daily Footfall & Member Consistency',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 7D vs 14D Toggle
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRangeButton(7, '7D'),
                    _buildRangeButton(14, '14D'),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Stat Badges
          Row(
            children: [
              Expanded(
                child: _buildStatBadge(
                  label: 'Average Daily',
                  value: '$avgAttendance members',
                  icon: Icons.speed_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatBadge(
                  label: 'Peak Turnout',
                  value: maxTurnout > 0 ? '$maxTurnout members' : '0 members',
                  icon: Icons.trending_up_rounded,
                  color: AppColors.paid,
                  subtitle: maxTurnout > 0 ? peakDayLabel : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Chart Area
          if (!hasActivity)
            _buildEmptyState()
          else
            SizedBox(
              height: 200,
              child: _buildAttendanceLineChart(points, totalActive),
            ),

          const SizedBox(height: 12),

          // Footer info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Daily Present',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                'Total active pool: $totalActive members',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRangeButton(int count, String text) {
    final isSelected = _daysCount == count;
    return GestureDetector(
      onTap: () => setState(() => _daysCount = count),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? AppColors.primaryOn : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle ?? label,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 180,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy_rounded, size: 40, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'No Attendance Records',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mark member attendance daily in the Attendance tab to track turnout trends.',
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

  Widget _buildAttendanceLineChart(List<_AttendanceDayPoint> points, int totalActive) {
    int maxVal = 0;
    for (final p in points) {
      maxVal = math.max(maxVal, p.presentCount);
    }
    if (maxVal == 0) maxVal = 10;
    final maxY = math.max((maxVal * 1.3).ceilToDouble(), 5.0);

    final spots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].presentCount.toDouble()));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 10,
            getTooltipColor: (_) => AppColors.surfaceElevated,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final point = points[spot.x.toInt()];
                final rate = point.totalActive > 0
                    ? (point.presentCount / point.totalActive * 100).round()
                    : 0;

                return LineTooltipItem(
                  '${DateFormat('EEEE, d MMM').format(point.date)}\n',
                  TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${point.presentCount} Present ($rate% turnout)',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: math.max(1, (maxY / 4).roundToDouble()),
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceBorder.withValues(alpha: 0.6),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                // If 14 days, show every 2nd title to avoid crowding
                if (_daysCount > 7 && index % 2 != 0 && index != points.length - 1) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    points[index].dayLabel,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value % 1 != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  space: 4,
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 3.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final isToday = index == points.length - 1;
                return FlDotCirclePainter(
                  radius: isToday ? 5.5 : 4,
                  color: isToday ? AppColors.paid : AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: AppColors.surface,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }
}

class _AttendanceDayPoint {
  final DateTime date;
  final String dateKey;
  final String dayLabel;
  final int presentCount;
  final int totalActive;

  _AttendanceDayPoint({
    required this.date,
    required this.dateKey,
    required this.dayLabel,
    required this.presentCount,
    required this.totalActive,
  });
}
