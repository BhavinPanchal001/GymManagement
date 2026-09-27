import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/date_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Migration fixes paid records whose monthYear does not match start month',
      () async {
    final customer = Customer(
      id: 'cust_m2',
      name: 'Misplaced Member',
      phone: '9800000002',
      joinDate: DateTime(2026, 8, 27),
      isActive: true,
    );

    // Legacy bug: a 27 Aug – 26 Sep cycle was stored under '2026-09' and the
    // record carries no startDate/endDate keys at all (relies on paidAt).
    final misplaced = {
      'id': 'pay_cust_m2_2026-09',
      'customerId': 'cust_m2',
      'monthYear': '2026-09',
      'amount': 600.0,
      'status': 'paid',
      'method': 'cash',
      'paidAt': '2026-08-27T09:00:00.000',
      'durationMonths': 1,
    };

    SharedPreferences.setMockInitialValues({
      'gym_customers_v1': json.encode([customer.toMap()]),
      'gym_payments_v1': json.encode([misplaced]),
    });

    final gym = GymService();
    await gym.init();

    final record = gym.getPaymentById('pay_cust_m2_2026-09');
    expect(record, isNotNull);
    // Dates frozen from effective values (paidAt 27 Aug 09:00, +1 month).
    expect(record!.startDate, equals(DateTime(2026, 8, 27, 9)));
    expect(
        record.endDate,
        equals(GymDateUtils.computeAnniversaryEndDate(
            DateTime(2026, 8, 27, 9), 1)));
    // monthYear label corrected to the start month; id unchanged.
    expect(record.monthYear, equals('2026-08'));
    expect(gym.isMonthCoveredByPaidPayment('cust_m2', '2026-08'), isTrue);
    expect(gym.isMonthCoveredByPaidPayment('cust_m2', '2026-09'), isTrue);
  });
}
