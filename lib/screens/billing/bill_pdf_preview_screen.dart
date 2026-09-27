import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/bill.dart';
import '../../models/customer.dart';
import '../../services/gym_service.dart';
import '../../services/payment_receipt_pdf_service.dart';
import '../../theme/app_theme.dart';

class BillPdfPreviewScreen extends StatelessWidget {
  final BillRecord bill;
  final Customer? customer;

  const BillPdfPreviewScreen({super.key, required this.bill, this.customer});

  static Future<void> show(BuildContext context, {required BillRecord bill, Customer? customer}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => BillPdfPreviewScreen(bill: bill, customer: customer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sanitizedCustomer = bill.customerName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    final filename = 'Receipt_${bill.billNumber}_$sanitizedCustomer.pdf';

    return Scaffold(
      backgroundColor: AppColors.dynamicBackground(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Official Payment Bill', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              '#${bill.billNumber} • ${bill.customerName}',
              style: TextStyle(fontSize: 12, color: AppColors.dynamicTextSecondary(), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        backgroundColor: AppColors.dynamicSurface(),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share PDF Bill',
            onPressed: () => PaymentReceiptPdfService().shareReceiptPdf(
              bill: bill,
              customer: customer,
              settings: GymService().settings,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Print / Download PDF',
            onPressed: () => PaymentReceiptPdfService().printReceipt(
              bill: bill,
              customer: customer,
              settings: GymService().settings,
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) => PaymentReceiptPdfService().generateReceiptPdf(
          bill: bill,
          customer: customer,
          settings: GymService().settings,
        ),
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: filename,
        maxPageWidth: 720,
      ),
    );
  }
}
