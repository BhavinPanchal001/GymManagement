import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migration removes a corrected pre-membership inferred agreement', () async {
    final customer = Customer(
      id: 'cust_corrected_attendance',
      name: 'Corrected Attendance Member',
      phone: '9984400005',
      joinDate: DateTime(2024, 8, 15),
      planDurationMonths: 3,
    );
    final explicitAgreement = PaymentRecord(
      id: 'membership_${customer.id}',
      customerId: customer.id,
      monthYear: '2024-08',
      amount: 0,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2024, 8, 15),
      endDate: DateTime(2024, 11, 14),
      isMembershipAgreement: true,
      planType: customer.planType,
    );
    final staleJuneAgreement = PaymentRecord(
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
    final attendance = [
      AttendanceRecord(
        id: '${customer.id}_2024-06-15',
        customerId: customer.id,
        dateKey: '2024-06-15',
        status: AttendanceStatus.absent,
        recordedAt: DateTime(2024, 6, 15),
      ),
      AttendanceRecord(
        id: '${customer.id}_2024-08-15',
        customerId: customer.id,
        dateKey: '2024-08-15',
        status: AttendanceStatus.present,
        recordedAt: DateTime(2024, 8, 15),
      ),
      AttendanceRecord(
        id: '${customer.id}_2024-09-15',
        customerId: customer.id,
        dateKey: '2024-09-15',
        status: AttendanceStatus.present,
        recordedAt: DateTime(2024, 9, 15),
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'gym_customers_v1': json.encode([customer.toMap()]),
      'gym_attendance_v1': json.encode(attendance.map((record) => record.toMap()).toList()),
      'gym_payments_v1': json.encode([explicitAgreement.toMap(), staleJuneAgreement.toMap()]),
      'payments_schema_v2': true,
    });

    final gym = GymService();
    await gym.init();

    final pending = gym.getAllPendingDues().single;
    expect(pending.totalPendingAmount, 1500);
    expect(pending.pendingRecords, hasLength(1));
    expect(pending.pendingRecords.single.id, explicitAgreement.id);
    expect(gym.getPaymentById(staleJuneAgreement.id), isNull);
  });
}
