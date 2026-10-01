import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '200 members and 96000 attendance records share indexed totals',
    () async {
      final gym = GymService();
      await gym.detachUser();
      final customers = <Customer>[];
      final payments = <PaymentRecord>[];
      final attendance = <AttendanceRecord>[];
      for (var member = 0; member < 200; member++) {
        final id = 'scale_$member';
        customers.add(
          Customer(
            id: id,
            name: 'Member $member',
            phone: '9000000000',
            joinDate: DateTime(2023, 1, 1),
          ),
        );
        for (var month = 0; month < 24; month++) {
          final start = DateTime(2023, month + 1, 1);
          final monthKey = GymDateUtils.toMonthKey(start);
          payments.add(
            PaymentRecord(
              id: 'pay_${id}_$monthKey',
              customerId: id,
              monthYear: monthKey,
              amount: month == 23 && member < 100 ? 200 : 600,
              totalDue: 600,
              status: PaymentStatus.paid,
              method: PaymentMethod.cash,
              paidAt: start,
              startDate: start,
              endDate: month == 23 && member >= 100
                  ? DateTime(start.year, start.month, 10)
                  : DateTime(start.year, start.month + 1, 0),
            ),
          );
          for (var day = 1; day <= 20; day++) {
            final dateKey = GymDateUtils.toDateKey(
              DateTime(start.year, start.month, day),
            );
            attendance.add(
              AttendanceRecord(
                id: 'att_${id}_$dateKey',
                customerId: id,
                dateKey: dateKey,
                status: AttendanceStatus.present,
                recordedAt: start,
              ),
            );
          }
        }
      }
      SharedPreferences.setMockInitialValues({
        'gym_customers_v1': json.encode(
          customers.map((c) => c.toMap()).toList(),
        ),
        'gym_payments_v1': json.encode(payments.map((p) => p.toMap()).toList()),
        'gym_attendance_v1': json.encode(
          attendance.map((a) => a.toMap()).toList(),
        ),
      });
      await gym.init();
      final first = Stopwatch()..start();
      expect(gym.getAllPendingDues(), hasLength(200));
      expect(
        gym.getAllPendingDues().fold<double>(
          0,
          (sum, member) => sum + member.totalPendingAmount,
        ),
        100000,
      );
      first.stop();
      final repeated = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        expect(gym.getAllPendingDues(), hasLength(200));
        expect(
          gym.getPendingDuesByMonth(
            gym.outstandingStartDate,
            gym.outstandingEndDate,
          ),
          hasLength(1),
        );
      }
      repeated.stop();
      debugPrint(
        'Indexed first calculation: ${first.elapsedMilliseconds} ms; '
        '100 member/month refreshes: ${repeated.elapsedMilliseconds} ms',
      );
      expect(first.elapsedMilliseconds, lessThan(2000));
      expect(repeated.elapsedMilliseconds, lessThan(1000));
      expect(gym.getPaidPaymentsForCustomer('scale_0'), hasLength(24));
      expect(attendance, hasLength(96000));
      expect(payments, hasLength(4800));
      expect(gym.getUnpaidAttendedDaysInMonth('scale_199', '2024-12'), 10);
      expect(gym.getUnpaidAttendedDaysInMonth('scale_0', '2023-01'), 0);
      await gym.detachUser();
    },
  );
}
