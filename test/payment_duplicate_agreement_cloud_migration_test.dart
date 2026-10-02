import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duplicate cleanup preserves paid history and the agreed balance', () async {
    const ownerId = 'duplicate-migration-owner';
    final customer = Customer(
      id: 'cust_review',
      name: 'Review Member',
      phone: '9984400004',
      joinDate: DateTime(2026, 8, 1),
      planDurationMonths: 3,
    );
    final legacyPaid = PaymentRecord(
      id: '${customer.id}_2026-08',
      customerId: customer.id,
      monthYear: '2026-08',
      amount: 600,
      totalDue: 600,
      status: PaymentStatus.paid,
      method: PaymentMethod.cash,
      paidAt: DateTime(2026, 8, 1),
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
    );
    final explicitAgreement = PaymentRecord(
      id: 'membership_${customer.id}',
      customerId: customer.id,
      monthYear: '2026-08',
      amount: 0,
      totalDue: 1800,
      durationMonths: 3,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 11, 14),
      isMembershipAgreement: true,
      planType: customer.planType,
    );
    final partialInferredAgreement = PaymentRecord(
      id: 'pay_${customer.id}_partial',
      customerId: customer.id,
      monthYear: '2026-08',
      amount: 500,
      totalDue: 1500,
      status: PaymentStatus.paid,
      method: PaymentMethod.gpay,
      paidAt: DateTime(2026, 9, 15),
      durationMonths: 3,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 11, 14),
      isMembershipAgreement: true,
      isInferredAgreement: true,
      planType: customer.planType,
    );
    final receipt = BillRecord(
      id: 'bill_${customer.id}_partial',
      billNumber: 'BILL-202609-0001',
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      planType: customer.planType,
      monthYear: '2026-08',
      amount: 500,
      paymentId: partialInferredAgreement.id,
      billType: 'PARTIAL',
      method: PaymentMethod.gpay,
      paidAt: DateTime(2026, 9, 15),
      gymName: 'Gym',
      issuedAt: DateTime(2026, 9, 15),
      durationMonths: 3,
      startDate: DateTime(2026, 8, 15),
      endDate: DateTime(2026, 11, 14),
    );

    SharedPreferences.setMockInitialValues({
      'gym_${ownerId}_customers_v1': json.encode([customer.toMap()]),
      'gym_${ownerId}_payments_v1': json.encode([
        legacyPaid.toMap(),
        explicitAgreement.toMap(),
        partialInferredAgreement.toMap(),
      ]),
      'gym_${ownerId}_bills_v1': json.encode([receipt.toMap()]),
    });

    final gym = GymService();
    await gym.attachUser(ownerId);
    final preferences = await SharedPreferences.getInstance();
    String? savedOutbox;
    for (var attempt = 0; attempt < 50; attempt++) {
      savedOutbox = preferences.getString('gym_${ownerId}_cloud_outbox_v1');
      if (savedOutbox != null && savedOutbox != '[]') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final reconciled = gym.getPaymentById(partialInferredAgreement.id);
    expect(reconciled, isNotNull);
    expect(reconciled!.totalDue, 1800);
    expect(reconciled.amount, 500);
    expect(reconciled.balanceDue, 1300);
    expect(reconciled.isInferredAgreement, isFalse);
    expect(gym.getPaymentById(legacyPaid.id), isNotNull);
    expect(gym.getPaymentById(explicitAgreement.id), isNull);
    expect(gym.getBillForPayment(partialInferredAgreement.id)?.id, receipt.id);
    expect(gym.getPendingDuesByMember(DateTime(2026, 8, 1), DateTime(2026, 11, 30)).single.totalPendingAmount, 1300);

    expect(savedOutbox, isNotNull);
    final batches = json.decode(savedOutbox!) as List<dynamic>;
    final changes = batches
        .expand((batch) => (batch as Map<String, dynamic>)['changes'] as List)
        .map((change) => Map<String, dynamic>.from(change as Map))
        .toList();
    expect(
      changes.where(
        (change) =>
            change['collection'] == 'payments' && change['documentId'] == legacyPaid.id && change['data'] == null,
      ),
      isEmpty,
    );
    expect(
      changes.any(
        (change) =>
            change['collection'] == 'payments' &&
            change['documentId'] == explicitAgreement.id &&
            change['data'] == null,
      ),
      isTrue,
    );
    final reconciledUpload = changes.singleWhere(
      (change) =>
          change['collection'] == 'payments' &&
          change['documentId'] == partialInferredAgreement.id &&
          change['data'] != null,
    );
    expect((reconciledUpload['data'] as Map<String, dynamic>)['totalDue'], 1800);

    await gym.detachUser();
  });
}
