import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(standardMonthlyFee: 600));
  });
  tearDown(() => gym.detachUser());

  Future<Customer> register({bool paid = false, double? amount,
      int duration = 1, DateTime? join, DateTime? start}) => gym.addCustomer(
    name: 'Joining date regression', phone: '9876543210',
    joinDate: join ?? DateTime(2026, 10, 26),
    membershipStartDate: start ?? DateTime(2026, 10, 26),
    membershipFee: 600, planDurationMonths: duration,
    markAsPaidNow: paid, paidAmount: amount,
  );
  PaymentRecord registration(Customer c) =>
      gym.paymentMap['membership_${c.id}']!;

  test('backdating join moves unpaid registration to September, including month key', () async {
    final member = await register();
    final id = registration(member).id;
    await gym.updateCustomer(member.copyWith(joinDate: DateTime(2026, 9, 1)));
    final payment = registration(member);
    expect(payment.id, id);
    expect(payment.monthYear, '2026-09');
    expect(payment.effectiveStartDate, DateTime(2026, 9, 1));
    expect(payment.effectiveEndDate, DateTime(2026, 9, 30));
    expect(payment.balanceDue, 600);
    expect(payment.amount, 0);
    expect(gym.getCustomerPaymentHistory(member.id), hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    final snapshot = jsonDecode(prefs.getString('gym_financial_v1')!) as Map;
    final saved = PaymentRecord.fromMap(Map<String, dynamic>.from(
        (snapshot['payments'] as List).single));
    expect(saved.effectiveStartDate, DateTime(2026, 9, 1));
    expect(saved.monthYear, '2026-09');
  });

  test('forward join edit recalculates multi-month period', () async {
    final member = await register(duration: 3);
    await gym.updateCustomer(member.copyWith(joinDate: DateTime(2026, 11, 1)));
    expect(registration(member).effectiveEndDate, DateTime(2027, 1, 31));
    expect(registration(member).durationMonths, 3);
    expect(registration(member).monthYear, '2026-11');
  });

  for (final amount in [300.0, 600.0]) {
    test('join edit preserves receipt and dates when collected $amount', () async {
      final member = await register(paid: true, amount: amount);
      final original = registration(member).toMap();
      final bills = gym.getAllBillsForCustomer(member.id).map((b) => b.toMap()).toList();
      await gym.updateCustomer(member.copyWith(joinDate: DateTime(2026, 9, 1)),
          realignUnpaidRegistration: true);
      expect(registration(member).toMap(), original);
      expect(gym.getAllBillsForCustomer(member.id).map((b) => b.toMap()).toList(), bills);
    });
  }

  test('ordinary profile edit preserves deliberately different registration start', () async {
    final member = await register(join: DateTime(2026, 9, 1));
    await gym.updateCustomer(member.copyWith(name: 'Changed name'));
    expect(registration(member).effectiveStartDate, DateTime(2026, 10, 26));
  });

  test('selecting existing join date repairs old stale unpaid registration with attendance', () async {
    final member = await register(join: DateTime(2026, 9, 1));
    await gym.toggleAttendance(member.id, '2026-09-01', AttendanceStatus.present, toggle: false);
    await gym.toggleAttendance(member.id, '2026-09-26', AttendanceStatus.present, toggle: false);
    await gym.updateCustomer(member, realignUnpaidRegistration: true);
    expect(registration(member).effectiveStartDate, DateTime(2026, 9, 1));
    expect(registration(member).effectiveEndDate, DateTime(2026, 9, 30));
    expect(gym.getCustomerPaymentHistory(member.id), hasLength(1));
    expect(gym.getUnpaidAttendedDaysInMonth(member.id, '2026-09'), 2);
    // Repeated save must not create a second charge.
    await gym.updateCustomer(member, realignUnpaidRegistration: true);
    expect(gym.getCustomerPaymentHistory(member.id), hasLength(1));
  });
  test('join correction leaves an audited fee adjustment unchanged', () async {
    final member = await register();
    await gym.adjustMembershipFee(expected: registration(member), revisedFee: 300,
        reason: 'Agreed discount', operationId: 'join-discount');
    final original = registration(member).toMap();
    await gym.updateCustomer(member.copyWith(joinDate: DateTime(2026, 9, 1)),
        realignUnpaidRegistration: true);
    expect(registration(member).toMap(), original);
  });

  test('joining and duration can change together without retaining old dates', () async {
    final member = await register();
    await gym.updateCustomer(member.copyWith(joinDate: DateTime(2026, 9, 1),
        planDurationMonths: 3));
    expect(registration(member).monthYear, '2026-09');
    expect(registration(member).effectiveStartDate, DateTime(2026, 9, 1));
    expect(registration(member).effectiveEndDate, DateTime(2026, 11, 30));
    expect(registration(member).durationMonths, 3);
  });

}
