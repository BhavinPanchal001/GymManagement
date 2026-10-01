import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/expense.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_backup_service.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingBackupStore extends InMemorySharedPreferencesStore {
  FailingBackupStore(super.data) : super.withData();

  String? rejectedSuffix;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectedSuffix != null && key.endsWith(rejectedSuffix!)) {
      rejectedSuffix = null;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  final backupService = GymBackupService();
  final start = DateTime(2026, 1, 10);
  final end = DateTime(2026, 2, 9);
  final customer = Customer(
    id: 'customer-1',
    name: 'Ravi Patel',
    phone: '9876543210',
    joinDate: start,
    cardNumber: 'CARD-101',
  );

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.replaceAllData(
      customers: [
        Customer(
          id: customer.id,
          name: customer.name,
          phone: customer.phone,
          joinDate: start,
          cardNumber: customer.cardNumber,
        ),
      ],
      attendance: [
        AttendanceRecord(
          id: 'attendance-1',
          customerId: customer.id,
          dateKey: '2026-01-10',
          status: AttendanceStatus.present,
          recordedAt: start,
        ),
      ],
      payments: [
        PaymentRecord(
          id: 'payment-1',
          customerId: customer.id,
          monthYear: '2026-01',
          amount: 500,
          totalDue: 600,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          paidAt: start,
          startDate: start,
          endDate: end,
          isMembershipAgreement: true,
          planType: CustomerPlan.normal,
        ),
      ],
      bills: [
        BillRecord(
          id: 'bill-1',
          billNumber: 'BILL-202601-0001',
          customerId: customer.id,
          customerName: customer.name,
          customerPhone: customer.phone,
          monthYear: '2026-01',
          amount: 500,
          paymentId: 'payment-1',
          billType: 'PARTIAL',
          method: PaymentMethod.cash,
          paidAt: start,
          gymName: 'Test Gym',
          issuedAt: start,
          startDate: start,
          endDate: end,
        ),
      ],
      expenses: [
        ExpenseRecord(
          id: 'expense-1',
          title: 'Rent',
          category: ExpenseCategory.rent,
          amount: 10000,
          date: start,
          monthYear: '2026-01',
        ),
      ],
      settings: const GymSettings(gymName: 'Test Gym'),
    );
  });

  tearDown(() async => gym.detachUser());

  test('backup serializes, previews, and restores all gym records', () async {
    final document = await backupService.createBackupDocument(gym);
    final parsed = backupService.parseBackupString(jsonEncode(document));

    expect(parsed.preview.gymName, 'Test Gym');
    expect(parsed.preview.customerCount, 1);
    expect(parsed.preview.attendanceCount, 1);
    expect(parsed.preview.paymentCount, 1);
    expect(parsed.preview.billCount, 1);
    expect(parsed.preview.expenseCount, 1);

    await gym.replaceAllData(
      customers: const [],
      attendance: const [],
      payments: const [],
      bills: const [],
      expenses: const [],
      settings: const GymSettings(gymName: 'Empty Gym'),
    );
    await backupService.restoreBackup(gym, parsed);

    expect(gym.customers.single.name, 'Ravi Patel');
    expect(gym.attendanceRecords.single.status, AttendanceStatus.present);
    expect(gym.paymentRecords.single.balanceDue, 100);
    expect(gym.billsMap.values.single.billType, 'PARTIAL');
    expect(gym.expenses.single.amount, 10000);
    expect(gym.settings.gymName, 'Test Gym');
  });

  test('backup rejects incompatible and damaged content', () async {
    final document = await backupService.createBackupDocument(gym);
    final incompatible = Map<String, dynamic>.from(document)..['version'] = 99;
    expect(
      () => backupService.parseBackupString(jsonEncode(incompatible)),
      throwsFormatException,
    );

    final damaged = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
    (damaged['data'] as Map<String, dynamic>)['payments'] = [
      {
        ...(damaged['data'] as Map<String, dynamic>)['payments'][0]
            as Map<String, dynamic>,
        'customerId': 'missing-member',
      },
    ];
    expect(
      () => backupService.parseBackupString(jsonEncode(damaged)),
      throwsFormatException,
    );
  });

  test('backup rejects media larger than the per-file limit', () async {
    final document = await backupService.createBackupDocument(gym);
    document['assets'] = [
      {
        'id': 'oversized',
        'fileName': 'large.jpg',
        'base64': base64Encode(Uint8List(GymBackupService.maxAssetBytes + 1)),
      },
    ];

    expect(
      () => backupService.parseBackupString(jsonEncode(document)),
      throwsFormatException,
    );
  });

  test('interrupted restore leaves a complete recovery snapshot', () async {
    final store = FailingBackupStore(
      await SharedPreferencesStorePlatform.instance.getAll(),
    )..rejectedSuffix = 'attendance_v1';
    SharedPreferencesStorePlatform.instance = store;

    await expectLater(
      gym.replaceAllData(
        customers: [
          Customer(
            id: 'replacement',
            name: 'Replacement Member',
            phone: '9999999999',
            joinDate: start,
            cardNumber: 'NEW-1',
          ),
        ],
        attendance: const [],
        payments: const [],
        bills: const [],
        expenses: const [],
        settings: const GymSettings(gymName: 'Replacement Gym'),
      ),
      throwsStateError,
    );

    final stored = await store.getAll();
    final transaction =
        jsonDecode(stored['flutter.gym_restore_transaction_v1']! as String)
            as Map<String, dynamic>;
    final data = transaction['data'] as Map<String, dynamic>;
    expect((data['customers'] as List).single['id'], 'replacement');
    expect(
      (data['settings'] as Map<String, dynamic>)['gymName'],
      'Replacement Gym',
    );
  });
}
