import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duplicate three-month agreements are charged once', () async {
    final customer = Customer(
      id: 'cust_duplicate_due',
      name: 'Aarvu',
      phone: '9984400003',
      joinDate: DateTime(2026, 8, 15),
      planDurationMonths: 3,
    );
    final registrationAgreement = PaymentRecord(
      id: 'membership_${customer.id}',
      customerId: customer.id,
      monthYear: '2026-08',
      amount: 0,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 11, 14),
      isMembershipAgreement: true,
      planType: customer.planType,
    );
    final duplicateInferredAgreement = PaymentRecord(
      id: 'pending_${customer.id}_2026-08-15',
      customerId: customer.id,
      monthYear: '2026-08',
      amount: 0,
      totalDue: 1500,
      durationMonths: 3,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 11, 14),
      isMembershipAgreement: true,
      isInferredAgreement: true,
      planType: customer.planType,
    );
    final attendance = [
      AttendanceRecord(
        id: '${customer.id}_2026-08-15',
        customerId: customer.id,
        dateKey: '2026-08-15',
        status: AttendanceStatus.present,
        recordedAt: DateTime(2026, 8, 15),
      ),
      AttendanceRecord(
        id: '${customer.id}_2026-09-15',
        customerId: customer.id,
        dateKey: '2026-09-15',
        status: AttendanceStatus.present,
        recordedAt: DateTime(2026, 9, 15),
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'gym_customers_v1': json.encode([customer.toMap()]),
      'gym_attendance_v1': json.encode(attendance.map((record) => record.toMap()).toList()),
      'gym_payments_v1': json.encode([registrationAgreement.toMap(), duplicateInferredAgreement.toMap()]),
      'payments_schema_v2': true,
    });

    final gym = GymService();
    await gym.init();

    final pending = gym.getPendingDuesByMember(DateTime(2026, 8, 1), DateTime(2026, 10, 31));
    final aarvu = pending.singleWhere((summary) => summary.customer.id == customer.id);

    expect(aarvu.pendingRecords, hasLength(1));
    expect(aarvu.pendingRecords.single.id, registrationAgreement.id);
    expect(aarvu.totalPendingAmount, 1500);
    expect(gym.paymentRecordCount, 1);
    expect(gym.getPendingDuesByMonth(DateTime(2026, 8, 1), DateTime(2026, 10, 31)).single.items, hasLength(1));
  });
}
