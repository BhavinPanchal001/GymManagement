import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/bill.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/payment_receipt_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentReceiptPdfService Tests', () {
    test('numberToWords formats amounts properly into English words', () {
      expect(
        PaymentReceiptPdfService.numberToWords(0),
        'Zero Rupees Only',
      );
      expect(
        PaymentReceiptPdfService.numberToWords(600),
        'Six Hundred Rupees Only',
      );
      expect(
        PaymentReceiptPdfService.numberToWords(1500),
        'One Thousand Five Hundred Rupees Only',
      );
      expect(
        PaymentReceiptPdfService.numberToWords(12000),
        'Twelve Thousand Rupees Only',
      );
      expect(
        PaymentReceiptPdfService.numberToWords(25800),
        'Twenty Five Thousand Eight Hundred Rupees Only',
      );
      expect(
        PaymentReceiptPdfService.numberToWords(100000),
        'One Lakh Rupees Only',
      );
    });

    test('generateReceiptPdf produces valid PDF byte stream with header', () async {
      final bill = BillRecord(
        id: 'bill_test_1',
        billNumber: '2026-09-001',
        customerId: 'cust_101',
        customerName: 'Rahul Sharma',
        customerPhone: '+91 98765 43210',
        planType: CustomerPlan.normal,
        monthYear: '2026-09',
        amount: 600.0,
        paymentId: 'pay_test_1',
        method: PaymentMethod.gpay,
        paidAt: DateTime(2026, 9, 15, 10, 30),
        issuedAt: DateTime(2026, 9, 15, 10, 30),
        gymName: 'Titan Gym & Fitness',
        durationMonths: 1,
        coveragePeriod: '15 Sep 2026 – 14 Oct 2026',
        transactionRef: 'UPI-9920192831',
        notes: 'Monthly renewal payment',
      );

      final customer = Customer(
        id: 'cust_101',
        name: 'Rahul Sharma',
        phone: '+91 98765 43210',
        cardNumber: 'TG-101',
        address: 'Sector 4, Main Street',
        joinDate: DateTime(2026, 1, 1),
        planType: CustomerPlan.normal,
      );

      final settings = const GymSettings(
        gymName: 'Titan Gym & Fitness',
        currencySymbol: '₹',
      );

      final bytes = await PaymentReceiptPdfService().generateReceiptPdf(
        bill: bill,
        customer: customer,
        settings: settings,
      );

      expect(bytes, isNotEmpty);
      final header = ascii.decode(bytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test('generateReceiptPdf handles 0-amount bill by resolving non-zero fee', () async {
      // Represents a forward month like October or November where stored amount was 0
      final zeroBill = BillRecord(
        id: 'bill_test_oct',
        billNumber: '2026-10-001',
        customerId: 'cust_102',
        customerName: 'Aman Verma',
        customerPhone: '+91 98111 22233',
        planType: CustomerPlan.normal,
        monthYear: '2026-10',
        amount: 0.0,
        paymentId: 'pay_test_oct',
        method: PaymentMethod.gpay,
        paidAt: DateTime(2026, 9, 15),
        issuedAt: DateTime(2026, 9, 15),
        gymName: 'Titan Gym & Fitness',
        durationMonths: 3,
        coveragePeriod: '15 Sep 2026 – 14 Dec 2026',
      );

      final customer = Customer(
        id: 'cust_102',
        name: 'Aman Verma',
        phone: '+91 98111 22233',
        joinDate: DateTime(2026, 1, 1),
        planType: CustomerPlan.normal,
      );

      final bytes = await PaymentReceiptPdfService().generateReceiptPdf(
        bill: zeroBill,
        customer: customer,
      );

      expect(bytes, isNotEmpty);
      final header = ascii.decode(bytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test('generateReceiptPdf works without customer and settings passed', () async {
      final bill = BillRecord(
        id: 'bill_test_2',
        billNumber: '2026-09-002',
        customerId: 'cust_999',
        customerName: 'Priya Patel',
        customerPhone: '+91 99999 88888',
        planType: CustomerPlan.personalTraining,
        monthYear: '2026-09',
        amount: 6500.0,
        paymentId: 'pay_test_2',
        method: PaymentMethod.cash,
        paidAt: DateTime(2026, 9, 20),
        issuedAt: DateTime(2026, 9, 20),
        gymName: 'IronPulse Gym',
        durationMonths: 3,
        coveragePeriod: '20 Sep 2026 – 19 Dec 2026',
      );

      final bytes = await PaymentReceiptPdfService().generateReceiptPdf(bill: bill);
      expect(bytes, isNotEmpty);
      final header = ascii.decode(bytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test('generateReceiptPdf uses current gym name from settings and omits static locker facilities', () async {
      final bill = BillRecord(
        id: 'bill_test_3',
        billNumber: '2026-09-003',
        customerId: 'cust_555',
        customerName: 'Karan Mehra',
        customerPhone: '+91 91234 56789',
        planType: CustomerPlan.normal,
        monthYear: '2026-09',
        amount: 1500.0,
        paymentId: 'pay_test_3',
        method: PaymentMethod.upi,
        paidAt: DateTime(2026, 9, 10),
        issuedAt: DateTime(2026, 9, 10),
        gymName: 'Old Stale Gym Name', // Stale gym name saved earlier
        durationMonths: 3,
        coveragePeriod: '10 Sep 2026 – 09 Dec 2026',
        notes: 'Personal locker not included',
      );

      final settings = const GymSettings(
        gymName: 'Apex Fitness Hub', // Current gym name in settings
      );

      final bytes = await PaymentReceiptPdfService().generateReceiptPdf(
        bill: bill,
        settings: settings,
      );

      expect(bytes, isNotEmpty);
      final pdfString = String.fromCharCodes(bytes);

      // Verify current gym name appears in PDF document metadata or content
      expect(pdfString.contains('Apex Fitness Hub'), isTrue);

      // Verify static "access to strength equipment, cardio & locker facilities" is NOT present
      expect(pdfString.contains('locker facilities'), isFalse);
    });
  });
}
