import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('payment snapshot waits for attendance before pruning inferred dues', () async {
    const ownerId = 'inferred-snapshot-order-owner';
    final customer = Customer(
      id: 'cust_snapshot_order',
      name: 'Snapshot Order Member',
      phone: '9984400006',
      joinDate: DateTime(2024, 6, 15),
      planDurationMonths: 3,
    );
    final inferredAgreement = PaymentRecord(
      id: 'pending_${customer.id}_2024-06-15',
      customerId: customer.id,
      monthYear: '2024-06',
      amount: 0,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2024, 6, 15),
      endDate: DateTime(2024, 9, 14),
      isMembershipAgreement: true,
      isInferredAgreement: true,
      planType: customer.planType,
    );
    final attendance = AttendanceRecord(
      id: '${customer.id}_2024-06-15',
      customerId: customer.id,
      dateKey: '2024-06-15',
      status: AttendanceStatus.present,
      recordedAt: DateTime(2024, 6, 15),
    );

    SharedPreferences.setMockInitialValues({
      'gym_${ownerId}_customers_v1': json.encode([customer.toMap()]),
      'gym_${ownerId}_payments_v1': json.encode([inferredAgreement.toMap()]),
      'payments_schema_v2': true,
    });

    final gym = GymService();
    await gym.attachUser(ownerId);

    await gym.applyCloudSnapshotForTesting(paymentMap: {inferredAgreement.id: inferredAgreement});
    expect(gym.getPaymentById(inferredAgreement.id), isNotNull);

    await gym.applyCloudSnapshotForTesting(
      attendanceMap: {'${attendance.customerId}_${attendance.dateKey}': attendance},
    );
    expect(gym.getPaymentById(inferredAgreement.id), isNotNull);
    expect(gym.getAllPendingDues().single.totalPendingAmount, 1500);

    await gym.detachUser();
  });

  test('local attendance correction prunes inferred dues before cloud loads', () async {
    const ownerId = 'offline-attendance-correction-owner';
    final customer = Customer(
      id: 'cust_offline_correction',
      name: 'Offline Correction Member',
      phone: '9984400007',
      joinDate: DateTime(2024, 6, 15),
      planDurationMonths: 3,
    );
    final inferredAgreement = PaymentRecord(
      id: 'pending_${customer.id}_2024-06-15',
      customerId: customer.id,
      monthYear: '2024-06',
      amount: 0,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2024, 6, 15),
      endDate: DateTime(2024, 9, 14),
      isMembershipAgreement: true,
      isInferredAgreement: true,
      planType: customer.planType,
    );
    final attendance = AttendanceRecord(
      id: '${customer.id}_2024-06-15',
      customerId: customer.id,
      dateKey: '2024-06-15',
      status: AttendanceStatus.present,
      recordedAt: DateTime(2024, 6, 15),
    );

    SharedPreferences.setMockInitialValues({
      'gym_${ownerId}_customers_v1': json.encode([customer.toMap()]),
      'gym_${ownerId}_attendance_v1': json.encode([attendance.toMap()]),
      'gym_${ownerId}_payments_v1': json.encode([inferredAgreement.toMap()]),
      'payments_schema_v2': true,
    });

    final gym = GymService();
    await gym.attachUser(ownerId);
    await gym.toggleAttendance(customer.id, attendance.dateKey, AttendanceStatus.absent);

    expect(gym.getPaymentById(inferredAgreement.id), isNull);
    expect(gym.getAllPendingDues(), isEmpty);

    await gym.detachUser();
  });
}
