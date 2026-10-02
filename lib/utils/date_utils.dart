import 'package:intl/intl.dart';
import 'money_utils.dart';

class GymDateUtils {
  static String toDateKey(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  static String toMonthKey(DateTime dt) {
    return DateFormat('yyyy-MM').format(dt);
  }

  static String formatMonthYearKey(String monthKey) {
    try {
      final parts = monthKey.split('-');
      if (parts.length == 2) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final dt = DateTime(year, month, 1);
        return DateFormat('MMMM yyyy').format(dt);
      }
    } catch (_) {}
    return monthKey;
  }

  static String formatMonthYear(dynamic input) {
    if (input is DateTime) {
      return DateFormat('MMMM yyyy').format(input);
    } else if (input is String) {
      return formatMonthYearKey(input);
    }
    return input.toString();
  }

  static String formatShortMonthYear(DateTime dt) {
    return DateFormat('MMM yyyy').format(dt);
  }

  static String formatMonthHeader(String monthKey) {
    return formatMonthYearKey(monthKey);
  }

  static String formatDate(DateTime dt) {
    return DateFormat('dd MMM yyyy').format(dt);
  }

  static String formatDisplayDate(DateTime dt) {
    return formatDate(dt);
  }

  static String formatShortDate(DateTime dt) {
    return DateFormat('dd MMM').format(dt);
  }

  static String formatDayOfWeek(DateTime dt) {
    return DateFormat('EEE').format(dt);
  }

  static String formatDateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  static String formatCurrency(double amount, {String symbol = '₹'}) {
    return MoneyUtils.formatDisplay(amount, symbol: symbol);
  }

  static int daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  /// Computes the end date for a membership of [durationMonths] starting on [startDate].
  /// By anniversary convention:
  /// - Starting 15 Sep for 1 month -> ends 14 Oct.
  /// - Starting 15 Sep for 3 months -> ends 14 Dec.
  /// - Starting 1 Sep for 1 month -> ends 30 Sep.
  /// - Starting 31 Jan for 1 month -> ends 28 Feb (or 29 Feb on leap years).
  static DateTime computeAnniversaryEndDate(DateTime startDate, int durationMonths) {
    if (durationMonths <= 0) durationMonths = 1;
    final totalMonths = startDate.month + durationMonths;
    final targetYear = startDate.year + (totalMonths - 1) ~/ 12;
    final targetMonth = ((totalMonths - 1) % 12) + 1;
    final maxTargetDays = daysInMonth(targetYear, targetMonth);

    if (startDate.day == 1) {
      return DateTime(targetYear, targetMonth, 0);
    } else {
      final desiredDay = startDate.day - 1;
      final clampedDay = desiredDay > maxTargetDays ? maxTargetDays : desiredDay;
      return DateTime(targetYear, targetMonth, clampedDay);
    }
  }

  static String formatDateRange(DateTime start, DateTime end) {
    if (start.year == end.year) {
      return '${DateFormat('dd MMM').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}';
    }
    return '${DateFormat('dd MMM yyyy').format(start)} – ${DateFormat('dd MMM yyyy').format(end)}';
  }

  static String formatCardDateRange(DateTime start, DateTime end) {
    final startStr = DateFormat('dd MMM').format(start);
    final endStr = DateFormat('dd MMM').format(end);
    if (start.year != end.year) {
      return '$startStr ${start.year} – $endStr ${end.year}';
    }
    return '$startStr – $endStr';
  }

  static List<String> getRecentMonthKeys({int pastMonths = 5, int futureMonths = 1}) {
    final now = DateTime.now();
    final list = <String>[];
    for (int i = -pastMonths; i <= futureMonths; i++) {
      final dt = DateTime(now.year, now.month + i, 1);
      list.add(toMonthKey(dt));
    }
    return list;
  }
}
