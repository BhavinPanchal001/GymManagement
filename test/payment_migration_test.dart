import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/services/gym_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Legacy v1 data migrates: placeholders & pending dropped, bills linked', () async {
    final customer = Customer(
      id: 'cust_m1',
      name: 'Legacy Member',
      phone: '9800000001',
      joinDate: DateTime(2026, 6, 1),
      isActive: true,
    );

    // Legacy 3-month package: parent + two ₹0 coveredByMonthYear placeholders.
    final parent = {
      'id': 'pay_cust_m1_2026-06',
      'customerId': 'cust_m1',
      'monthYear': '2026-06',
      'amount': 1500.0,
      'status': 'paid',
      'method': 'gpay',
      'paidAt': '2026-06-10T10:00:00.000',
      'durationMonths': 3,
      'startDate': '2026-06-10T00:00:00.000',
      'endDate': '2026-09-09T00:00:00.000',
    };
    final placeholder1 = {
      'id': 'pay_cust_m1_2026-07',
      'customerId': 'cust_m1',
      'monthYear': '2026-07',
      'amount': 0.0,
      'status': 'paid',
      'method': 'gpay',
      'paidAt': '2026-06-10T10:00:00.000',
      'durationMonths': 1,
      'coveredByMonthYear': '2026-06',
      'startDate': '2026-06-10T00:00:00.000',
      'endDate': '2026-09-09T00:00:00.000',
    };
    final placeholder2 = {
      'id': 'pay_cust_m1_2026-08',
      'customerId': 'cust_m1',
      'monthYear': '2026-08',
      'amount': 0.0,
      'status': 'paid',
      'method': 'gpay',
      'paidAt': '2026-06-10T10:00:00.000',
      'durationMonths': 1,
      'coveredByMonthYear': '2026-06',
      'startDate': '2026-06-10T00:00:00.000',
      'endDate': '2026-09-09T00:00:00.000',
    };
    final storedPending = {
      'id': 'pay_cust_m1_2026-09',
      'customerId': 'cust_m1',
      'monthYear': '2026-09',
      'amount': 600.0,
      'status': 'pending',
      'durationMonths': 1,
    };
    final legacyBill = {
      'id': 'bill_cust_m1_2026-06',
      'billNumber': 'BILL-202606-0001',
      'customerId': 'cust_m1',
      'customerName': 'Legacy Member',
      'customerPhone': '9800000001',
      'planType': 'normal',
      'monthYear': '2026-06',
      'amount': 1500.0,
      'method': 'gpay',
      'paidAt': '2026-06-10T10:00:00.000',
      'gymName': 'Gym',
      'issuedAt': '2026-06-10T10:00:00.000',
      'status': 'PAID',
      'durationMonths': 3,
      'startDate': '2026-06-10T00:00:00.000',
      'endDate': '2026-09-09T00:00:00.000',
    };

    SharedPreferences.setMockInitialValues({
      'gym_customers_v1': json.encode([customer.toMap()]),
      'gym_payments_v1':
          json.encode([parent, placeholder1, placeholder2, storedPending]),
      'gym_bills_v1': json.encode([legacyBill]),
    });

    final gym = GymService();
    await gym.init();

    // Placeholders and stored pending are gone; only the parent remains.
    final paid = gym.getPaidPaymentsForCustomer('cust_m1');
    expect(paid.length, equals(1));
    expect(paid.first.id, equals('pay_cust_m1_2026-06'));
    expect(paid.first.coveredByMonthYear, isNull);
    expect(paid.first.monthYear, equals('2026-06'));

    // Coverage for the full 3-month range still resolves via the parent.
    for (final mk in ['2026-06', '2026-07', '2026-08', '2026-09']) {
      expect(
        gym.isMonthCoveredByPaidPayment('cust_m1', mk),
        isTrue,
        reason: 'Expected $mk to be covered',
      );
    }

    // Bill is linked to the parent payment and typed FULL.
    final bill = gym.billsMap['bill_cust_m1_2026-06'];
    expect(bill, isNotNull);
    expect(bill!.paymentId, equals('pay_cust_m1_2026-06'));
    expect(bill.billType, equals('FULL'));

    // September has no stored pending record but coverage from the package
    // still applies through Sep 9; October onwards is a transient pending.
    final octRecord = gym.getPaymentRecord('cust_m1', '2026-10');
    expect(octRecord.isPaid, isFalse);
    expect(octRecord.id, startsWith('pending_'));
  });
}
