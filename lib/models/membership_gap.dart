class MembershipGap {
  final String nextPaymentId;
  final DateTime start;
  final DateTime end;
  final int attendedDays;

  const MembershipGap({
    required this.nextPaymentId,
    required this.start,
    required this.end,
    required this.attendedDays,
  });

  int get days =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;
}
