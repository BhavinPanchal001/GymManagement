import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  late Customer member;
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 600));
    member = await gym.addCustomer(
      name: 'Corrected attendance',
      phone: '9876543210',
      joinDate: DateTime(2026, 8, 1),
      membershipStartDate: DateTime(2026, 8, 1),
      membershipEndDate: DateTime(2026, 8, 31),
      membershipFee: 600,
      markAsPaidNow: true,
    );
    for (var day = 15; day <= 30; day++) {
      await gym.toggleAttendance(
        member.id,
        '2026-09-$day',
        AttendanceStatus.present,
        toggle: false,
      );
    }
  });
  tearDown(() => gym.detachUser());
  List<PaymentRecord> dues() => gym
      .getCustomerPaymentHistory(member.id)
      .where((p) => p.balanceDue > 0)
      .toList();
  Future<void> mark(String date, AttendanceStatus status) =>
      gym.toggleAttendance(member.id, date, status, toggle: false);

  test(
    'correcting accidental September 4 to absent leaves one September 15 charge',
    () async {
      final paid = gym.paymentMap['membership_${member.id}']!.toMap();
      await mark('2026-09-04', AttendanceStatus.present);
      await mark('2026-09-04', AttendanceStatus.absent);
      expect(dues(), hasLength(1));
      expect(dues().single.effectiveStartDate, DateTime(2026, 9, 15));
      expect(dues().single.effectiveEndDate, DateTime(2026, 10, 14));
      expect(dues().single.totalDue, 600);
      expect(gym.getUnpaidAttendedDaysInMonth(member.id, '2026-09'), 16);
      expect(gym.paymentMap['membership_${member.id}']!.toMap(), paid);
      expect(gym.getAllBillsForCustomer(member.id), hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      final snapshot = jsonDecode(prefs.getString('gym_financial_v1')!) as Map;
      expect((snapshot['payments'] as List).length, 2);
    },
  );

  test(
    'earlier genuine attendance replaces overlapping automatic period',
    () async {
      await mark('2026-09-04', AttendanceStatus.present);
      expect(dues(), hasLength(1));
      expect(dues().single.effectiveStartDate, DateTime(2026, 9, 4));
      expect(dues().single.effectiveEndDate, DateTime(2026, 10, 3));
      await mark('2026-10-04', AttendanceStatus.present);
      expect(dues(), hasLength(2));
      final periods = dues()
        ..sort((a, b) => a.effectiveStartDate.compareTo(b.effectiveStartDate));
      expect(periods[1].effectiveStartDate, DateTime(2026, 10, 4));
    },
  );

  test('rest day and repeat corrections do not leave extra charges', () async {
    await mark('2026-09-04', AttendanceStatus.present);
    await mark('2026-09-04', AttendanceStatus.rest);
    await mark('2026-09-04', AttendanceStatus.rest);
    expect(dues(), hasLength(1));
    expect(dues().single.effectiveStartDate, DateTime(2026, 9, 15));
  });

  test('changing a non-present day creates no new period', () async {
    await mark('2026-09-04', AttendanceStatus.absent);
    expect(dues(), hasLength(1));
    expect(dues().single.effectiveStartDate, DateTime(2026, 9, 15));
  });
  test(
    'loading existing overlapping September cards removes stale September 4',
    () async {
      final valid = dues().single;
      final stale = valid.copyWith(
        id: 'pending_${member.id}_2026-09-04',
        startDate: DateTime(2026, 9, 4),
        endDate: DateTime(2026, 10, 3),
      );
      await mark('2026-09-04', AttendanceStatus.absent);
      await gym.applyCloudSnapshotForTesting(
        paymentMap: {...gym.paymentMap, stale.id: stale},
      );
      expect(dues(), hasLength(1));
      expect(dues().single.id, valid.id);
      expect(gym.getPaymentById(stale.id), isNull);
    },
  );

  test(
    'attendance corrections preserve adjusted period and audit history',
    () async {
      final period = dues().single;
      await gym.adjustMembershipFee(
        expected: period,
        revisedFee: 300,
        reason: 'Half month approved',
        operationId: 'attendance-discount',
      );
      final adjusted = gym.getPaymentById(period.id)!.toMap();
      await mark('2026-09-15', AttendanceStatus.absent);
      expect(gym.getPaymentById(period.id)!.toMap(), adjusted);
      expect(dues(), hasLength(1));
    },
  );

  test(
    'unchanged attendance cycle retains its fee when default fee changes',
    () async {
      final period = dues().single.toMap();
      await gym.updateSettings(const GymSettings(standardMonthlyFee: 800));
      await mark('2026-09-04', AttendanceStatus.absent);
      expect(dues().single.toMap(), period);
    },
  );
}
