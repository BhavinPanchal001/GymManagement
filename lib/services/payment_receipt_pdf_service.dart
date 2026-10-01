import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/gym_settings.dart';
import '../utils/date_utils.dart';
import 'gym_service.dart';

class PaymentReceiptPdfService {
  static final PaymentReceiptPdfService _instance = PaymentReceiptPdfService._internal();
  factory PaymentReceiptPdfService() => _instance;
  PaymentReceiptPdfService._internal();

  // Premium corporate bill palette
  static const PdfColor primaryNavy = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor accentBlue = PdfColor.fromInt(0xFF2563EB);
  static const PdfColor paidGreen = PdfColor.fromInt(0xFF16A34A);
  static const PdfColor paidBg = PdfColor.fromInt(0xFFDCFCE7);
  static const PdfColor cancelRed = PdfColor.fromInt(0xFFDC2626);
  static const PdfColor cancelBg = PdfColor.fromInt(0xFFFEE2E2);
  static const PdfColor partialAmber = PdfColor.fromInt(0xFFB45309);
  static const PdfColor partialBg = PdfColor.fromInt(0xFFFEF3C7);
  static const PdfColor slateDark = PdfColor.fromInt(0xFF1E293B);
  static const PdfColor slateMedium = PdfColor.fromInt(0xFF475569);
  static const PdfColor slateLight = PdfColor.fromInt(0xFF64748B);
  static const PdfColor borderLight = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor bgMuted = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor white = PdfColor.fromInt(0xFFFFFFFF);

  /// Converts a numeric amount to English words (Indian numbering system)
  static String numberToWords(int number) {
    if (number == 0) return 'Zero Rupees Only';
    if (number < 0) return 'Minus ${numberToWords(-number)}';

    final units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen'
    ];
    final tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    ];

    String convertLessThanOneThousand(int n) {
      if (n == 0) return '';
      if (n < 20) return units[n];
      if (n < 100) {
        final ten = tens[n ~/ 10];
        final unit = units[n % 10];
        return unit.isEmpty ? ten : '$ten $unit';
      }
      final hundred = '${units[n ~/ 100]} Hundred';
      final rest = n % 100;
      if (rest == 0) return hundred;
      return '$hundred and ${convertLessThanOneThousand(rest)}';
    }

    int remaining = number;
    final crores = remaining ~/ 10000000;
    remaining %= 10000000;
    final lakhs = remaining ~/ 100000;
    remaining %= 100000;
    final thousands = remaining ~/ 1000;
    remaining %= 1000;
    final hundreds = remaining;

    final parts = <String>[];
    if (crores > 0) parts.add('${convertLessThanOneThousand(crores)} Crore');
    if (lakhs > 0) parts.add('${convertLessThanOneThousand(lakhs)} Lakh');
    if (thousands > 0) {
      parts.add('${convertLessThanOneThousand(thousands)} Thousand');
    }
    if (hundreds > 0) parts.add(convertLessThanOneThousand(hundreds));

    final result = parts.join(' ').trim();
    return result.isEmpty ? 'Zero Rupees Only' : '$result Rupees Only';
  }

  /// Generates the official Payment Receipt / Invoice as a vector PDF document
  Future<Uint8List> generateReceiptPdf({
    required BillRecord bill,
    Customer? customer,
    GymSettings? settings,
  }) async {
    final gymSettings = settings ?? GymService().settings;
    final effectiveCustomer = customer ?? GymService().getCustomerById(bill.customerId);

    // Render the actual receipt amount; never substitute a current plan price.
    BillRecord effectiveBill = bill;

    // Gym name resolution: Always prioritize the CURRENT name configured in GymSettings
    final currentGymName = gymSettings.gymName.trim().isNotEmpty
        ? gymSettings.gymName.trim()
        : (effectiveBill.gymName.trim().isNotEmpty &&
                effectiveBill.gymName.trim().toLowerCase() != 'gym' &&
                effectiveBill.gymName.trim().toLowerCase() != 'ironpulse fitness club'
            ? effectiveBill.gymName.trim()
            : 'GYM & FITNESS CLUB');
    effectiveBill = effectiveBill.copyWith(gymName: currentGymName);

    // Installment math: plan total vs amount received on THIS receipt.
    final gym = GymService();
    final payment = effectiveBill.paymentId.isNotEmpty
        ? gym.getPaymentById(effectiveBill.paymentId)
        : null;
    final planTotal = (payment != null && payment.totalDue > 0)
        ? payment.totalDue
        : effectiveBill.amount;
    // PAID bills on the same payment issued before this one.
    final paidEarlier = payment == null
        ? 0.0
        : gym.getBillsForPayment(payment.id)
            .where((b) =>
                b.id != effectiveBill.id &&
                b.issuedAt.isBefore(effectiveBill.issuedAt))
            .fold<double>(0.0, (s, b) => s + b.amount);
    final balanceAfter =
        (planTotal - paidEarlier - effectiveBill.amount).clamp(0.0, double.infinity);
    final isCancelled = effectiveBill.status == 'CANCELLED';
    final isPartial = effectiveBill.billType == 'PARTIAL';
    final isBalance = effectiveBill.billType == 'BALANCE';
    final isInstallment = isPartial || isBalance;
    final badgeLabel = isCancelled
        ? 'CANCELLED'
        : (isPartial
            ? 'PARTIAL PAYMENT'
            : (isBalance ? 'BALANCE RECEIVED' : 'PAYMENT RECEIVED'));
    final badgeColor =
        isCancelled ? cancelRed : (isPartial ? partialAmber : paidGreen);
    final badgeBg = isCancelled ? cancelBg : (isPartial ? partialBg : paidBg);

    final pdf = pw.Document(
      title: 'Payment_Receipt_${effectiveBill.billNumber}',
      author: currentGymName,
    );

    // Load Gym Logo Image
    pw.MemoryImage? gymLogoImage;
    final logoPath = gymSettings.gymLogoPath ?? GymService().gymLogoPath;
    if (logoPath != null && logoPath.isNotEmpty && !logoPath.startsWith('avatar:')) {
      try {
        String cleanPath = logoPath;
        if (cleanPath.startsWith('file://')) {
          try {
            cleanPath = Uri.parse(cleanPath).toFilePath();
          } catch (_) {
            cleanPath = cleanPath.replaceFirst('file://', '');
          }
        }
        final file = File(cleanPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            gymLogoImage = pw.MemoryImage(bytes);
          }
        }
      } catch (e) {
        debugPrint('Error loading gym logo for receipt PDF: $e');
      }
    }

    // Font resolution with safe fallbacks
    pw.Font? regularFont;
    pw.Font? boldFont;
    pw.Font? mediumFont;

    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
      mediumFont = await PdfGoogleFonts.robotoMedium();
    } catch (_) {
      // Safe offline fallback
    }

    final effectiveRegular = regularFont ?? pw.Font.helvetica();
    final effectiveBold = boldFont ?? pw.Font.helveticaBold();
    final effectiveMedium = mediumFont ?? effectiveRegular;

    // Unicode currency safe handling (Fallback to "Rs." if Helvetica fallback is active)
    final hasUnicode = effectiveRegular is pw.TtfFont;
    final bullet = hasUnicode ? '•' : '|';
    final checkmark = hasUnicode ? '✓' : '[OK]';

    String sanitize(String text) {
      if (hasUnicode) return text;
      return text
          .replaceAll('₹', 'Rs. ')
          .replaceAll('–', '-')
          .replaceAll('—', '-')
          .replaceAll('✓', '[OK]')
          .replaceAll('★', '*')
          .replaceAll('•', '|');
    }

    final currencySymbol = gymSettings.currencySymbol;
    final displayCurrency = hasUnicode ? currencySymbol : (currencySymbol == '₹' ? 'Rs. ' : currencySymbol);

    String formatMoney(double amount) {
      return '$displayCurrency${amount.toStringAsFixed(2)}';
    }

    final gymName = sanitize(currentGymName.toUpperCase());

    final memberId = effectiveCustomer?.cardNumber.trim().isNotEmpty == true
        ? effectiveCustomer!.cardNumber.trim()
        : (effectiveCustomer?.id.isNotEmpty == true
            ? effectiveCustomer!.id.replaceAll(RegExp(r'\D'), '').padLeft(4, '0')
            : effectiveBill.customerId.replaceAll(RegExp(r'\D'), '').padLeft(4, '0'));

    final planLabel = CustomerPlan.getLabel(effectiveBill.planType);
    final validityPeriod = sanitize(effectiveBill.formattedValidityPeriod);
    final issuedDate = GymDateUtils.formatDate(effectiveBill.issuedAt);
    final paidDateTime = GymDateUtils.formatDateTime(effectiveBill.paidAt);
    final amountWords = numberToWords(effectiveBill.amount.round());
    final attSummary = GymService().getMonthlyAttendanceSummary(effectiveBill.customerId, effectiveBill.monthYear);
    final presentDays = attSummary['present'] ?? 0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ================= TOP ACCENT DECORATION =================
              pw.Container(
                height: 5,
                decoration: const pw.BoxDecoration(
                  color: accentBlue,
                  borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                ),
              ),
              pw.SizedBox(height: 14),

              // ================= HEADER: GYM BRANDING & INVOICE META =================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Gym Identity with Logo and Current Gym Name
                  pw.Expanded(
                    flex: 7,
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (gymLogoImage != null) ...[
                          pw.Container(
                            width: 48,
                            height: 48,
                            margin: const pw.EdgeInsets.only(right: 12),
                            decoration: pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              border: pw.Border.all(color: accentBlue, width: 1.5),
                            ),
                            child: pw.ClipOval(
                              child: pw.Image(gymLogoImage, fit: pw.BoxFit.cover),
                            ),
                          ),
                        ] else ...[
                          pw.Container(
                            width: 48,
                            height: 48,
                            margin: const pw.EdgeInsets.only(right: 12),
                            decoration: const pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              color: accentBlue,
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                gymName.isNotEmpty ? gymName[0] : 'G',
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: 22,
                                  color: white,
                                ),
                              ),
                            ),
                          ),
                        ],
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                gymName,
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: gymName.length > 25 ? 14 : (gymName.length > 18 ? 16 : 19),
                                  color: primaryNavy,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'Official Payment Receipt & Tax Invoice',
                                style: pw.TextStyle(
                                  font: effectiveMedium,
                                  fontSize: 8.5,
                                  color: accentBlue,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right: Invoice Title & Paid Badge
                  pw.Expanded(
                    flex: 4,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: badgeBg,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            border: pw.Border.all(color: badgeColor, width: 1.2),
                          ),
                          child: pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Container(
                                width: 7,
                                height: 7,
                                decoration: pw.BoxDecoration(
                                  color: badgeColor,
                                  shape: pw.BoxShape.circle,
                                ),
                              ),
                              pw.SizedBox(width: 5),
                              pw.Text(
                                badgeLabel,
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: 9.5,
                                  color: badgeColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'RECEIPT / TAX INVOICE',
                          style: pw.TextStyle(
                            font: effectiveBold,
                            fontSize: 14,
                            color: slateDark,
                            letterSpacing: -0.2,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Receipt #: ${effectiveBill.billNumber}',
                          style: pw.TextStyle(
                            font: effectiveBold,
                            fontSize: 10,
                            color: accentBlue,
                          ),
                        ),
                        pw.Text(
                          'Issue Date: $issuedDate',
                          style: pw.TextStyle(
                            font: effectiveRegular,
                            fontSize: 8.5,
                            color: slateMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 14),
              pw.Container(height: 1, color: borderLight),
              pw.SizedBox(height: 14),

              // ================= 2-COLUMN INFO: BILLED TO & PAYMENT DETAILS =================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left Card: Billed To (Member Info)
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: bgMuted,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        border: pw.Border.all(color: borderLight),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'BILLED TO / MEMBER DETAILS',
                            style: pw.TextStyle(
                              font: effectiveBold,
                              fontSize: 8,
                              color: slateLight,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            effectiveBill.customerName,
                            style: pw.TextStyle(
                              font: effectiveBold,
                              fontSize: 12,
                              color: primaryNavy,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          _buildDetailRow('Member ID / Card:', '#$memberId', effectiveRegular, effectiveBold),
                          if (effectiveBill.customerPhone.isNotEmpty)
                            _buildDetailRow('Phone Number:', effectiveBill.customerPhone, effectiveRegular, effectiveMedium),
                          if (effectiveCustomer?.address.isNotEmpty == true)
                            _buildDetailRow('Address:', effectiveCustomer!.address, effectiveRegular, effectiveMedium),
                          _buildDetailRow('Plan Category:', planLabel, effectiveRegular, effectiveMedium),
                          if (effectiveCustomer != null)
                            _buildDetailRow('Member Since:', GymDateUtils.formatDate(effectiveCustomer.joinDate), effectiveRegular, effectiveMedium),
                        ],
                      ),
                    ),
                  ),

                  pw.SizedBox(width: 12),

                  // Right Card: Invoice & Transaction Details
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: bgMuted,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        border: pw.Border.all(color: borderLight),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PAYMENT & BILL METRICS',
                            style: pw.TextStyle(
                              font: effectiveBold,
                              fontSize: 8,
                              color: slateLight,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.SizedBox(height: 6),
                          _buildDetailRow('Bill Number:', effectiveBill.billNumber, effectiveRegular, effectiveBold),
                          _buildDetailRow('Payment Date:', paidDateTime, effectiveRegular, effectiveMedium),
                          _buildDetailRow('Payment Mode:', effectiveBill.method.label, effectiveRegular, effectiveBold),
                          if (effectiveBill.transactionRef != null && effectiveBill.transactionRef!.trim().isNotEmpty)
                            _buildDetailRow('Transaction Ref:', effectiveBill.transactionRef!.trim(), effectiveRegular, effectiveMedium),
                          _buildDetailRow('Billing Cycle:', GymDateUtils.formatMonthYearKey(effectiveBill.monthYear), effectiveRegular, effectiveMedium),
                          if (presentDays > 0)
                            _buildDetailRow('Attendance Linked:', '$presentDays Days Attended', effectiveRegular, effectiveBold),
                          _buildDetailRow('Validity Period:', validityPeriod, effectiveRegular, effectiveBold),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // ================= ITEMIZED BILL TABLE =================
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderLight),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  children: [
                    // Table Header
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: const pw.BoxDecoration(
                        color: slateDark,
                        borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
                      ),
                      child: pw.Row(
                        children: [
                          pw.SizedBox(
                            width: 24,
                            child: pw.Text(
                              '#',
                              style: pw.TextStyle(font: effectiveBold, fontSize: 8.5, color: white),
                            ),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Text(
                              'DESCRIPTION OF MEMBERSHIP / SERVICE',
                              style: pw.TextStyle(font: effectiveBold, fontSize: 8.5, color: white),
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              'VALIDITY PERIOD',
                              style: pw.TextStyle(font: effectiveBold, fontSize: 8.5, color: white),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'DURATION',
                              style: pw.TextStyle(font: effectiveBold, fontSize: 8.5, color: white),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'AMOUNT',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(font: effectiveBold, fontSize: 8.5, color: white),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Table Row
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      color: white,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.SizedBox(
                            width: 24,
                            child: pw.Text('1', style: pw.TextStyle(font: effectiveMedium, fontSize: 9.5)),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'Gym Membership - $planLabel',
                                  style: pw.TextStyle(font: effectiveBold, fontSize: 10, color: slateDark),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  effectiveBill.durationMonths > 1
                                      ? '${effectiveBill.durationMonths}-Month Membership Package'
                                      : 'Monthly Membership Subscription',
                                  style: pw.TextStyle(font: effectiveRegular, fontSize: 8, color: slateLight),
                                ),
                                if (isInstallment) ...[
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    isPartial
                                        ? sanitize('Partial payment — balance ${formatMoney(balanceAfter)} pending')
                                        : 'Balance payment for earlier partial receipt',
                                    style: pw.TextStyle(font: effectiveRegular, fontSize: 8, color: partialAmber),
                                  ),
                                ],
                                if (presentDays > 0) ...[
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    '$checkmark $presentDays Days Attended in ${GymDateUtils.formatMonthYearKey(effectiveBill.monthYear)}',
                                    style: const pw.TextStyle(font: null, fontSize: 8, color: paidGreen),
                                  ),
                                ],
                                if (effectiveBill.coveragePeriod != null &&
                                    effectiveBill.coveragePeriod!.isNotEmpty &&
                                    effectiveBill.coveragePeriod != validityPeriod) ...[
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Coverage: ${sanitize(effectiveBill.coveragePeriod!)}',
                                    style: pw.TextStyle(font: effectiveRegular, fontSize: 7.5, color: slateLight),
                                  ),
                                ],
                                if (effectiveBill.notes != null && effectiveBill.notes!.trim().isNotEmpty) ...[
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Note: ${sanitize(effectiveBill.notes!.trim())}',
                                    style: pw.TextStyle(font: effectiveRegular, fontSize: 8, color: accentBlue),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              validityPeriod,
                              style: pw.TextStyle(font: effectiveMedium, fontSize: 9, color: slateDark),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              '${effectiveBill.durationMonths} Month${effectiveBill.durationMonths > 1 ? 's' : ''}',
                              style: pw.TextStyle(font: effectiveMedium, fontSize: 9, color: slateDark),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              formatMoney(planTotal),
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(font: effectiveBold, fontSize: 10, color: primaryNavy),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ================= TOTALS & AMOUNT IN WORDS =================
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Amount in Words & Payment Settlement Note
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Amount in words box
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: bgMuted,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            border: pw.Border.all(color: borderLight),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'AMOUNT IN WORDS:',
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: 7.5,
                                  color: slateLight,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                amountWords,
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: 9.5,
                                  color: slateDark,
                                  fontStyle: pw.FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 8),

                        // Payment Confirmation Tag
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                          decoration: pw.BoxDecoration(
                            color: isCancelled ? cancelBg : paidBg,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                            border: pw.Border.all(
                                color: isCancelled
                                    ? cancelRed.shade(0.3)
                                    : paidGreen.shade(0.3),
                                width: 0.8),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Text(
                                checkmark,
                                style: pw.TextStyle(
                                  font: effectiveBold,
                                  fontSize: 10,
                                  color: isCancelled ? cancelRed : paidGreen,
                                ),
                              ),
                              pw.SizedBox(width: 6),
                              pw.Expanded(
                                child: pw.Text(
                                  isCancelled
                                      ? 'This receipt was cancelled and is no longer valid.'
                                      : 'Payment of ${formatMoney(effectiveBill.amount)} confirmed received via ${effectiveBill.method.label} on $paidDateTime.${isInstallment && balanceAfter > 0 ? ' Remaining balance: ${formatMoney(balanceAfter)}.' : ''}',
                                  style: pw.TextStyle(
                                    font: effectiveMedium,
                                    fontSize: 8,
                                    color: isCancelled ? cancelRed : paidGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(width: 14),

                  // Right: Financial Summary Box
                  pw.Expanded(
                    flex: 5,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: bgMuted,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        border: pw.Border.all(color: borderLight),
                      ),
                      child: pw.Column(
                        children: [
                          _buildSummaryRow('Subtotal:', formatMoney(planTotal), effectiveRegular, effectiveMedium),
                          pw.SizedBox(height: 4),
                          _buildSummaryRow('Discount / Offer:', formatMoney(0.0), effectiveRegular, effectiveMedium),
                          pw.SizedBox(height: 4),
                          _buildSummaryRow('Taxes / GST:', 'Inclusive', effectiveRegular, effectiveMedium),
                          if (isInstallment) ...[
                            if (paidEarlier > 0) ...[
                              pw.SizedBox(height: 4),
                              _buildSummaryRow('Paid Earlier:', formatMoney(paidEarlier), effectiveRegular, effectiveMedium),
                            ],
                            pw.SizedBox(height: 4),
                            _buildSummaryRow('Balance Due:', formatMoney(balanceAfter), effectiveRegular, effectiveMedium),
                          ],
                          pw.SizedBox(height: 6),
                          pw.Container(height: 1, color: borderLight),
                          pw.SizedBox(height: 6),
                          // Net Total Highlight
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: const pw.BoxDecoration(
                              color: primaryNavy,
                              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  isInstallment ? 'PAID NOW:' : 'TOTAL PAID:',
                                  style: pw.TextStyle(
                                    font: effectiveBold,
                                    fontSize: 10,
                                    color: white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                pw.Text(
                                  formatMoney(effectiveBill.amount),
                                  style: pw.TextStyle(
                                    font: effectiveBold,
                                    fontSize: 13,
                                    color: white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // ================= TERMS & CONDITIONS =================
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: borderLight),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  color: bgMuted,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TERMS & MEMBERSHIP POLICIES:',
                      style: pw.TextStyle(
                        font: effectiveBold,
                        fontSize: 7.5,
                        color: slateLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      '1. All gym membership fees once paid are non-refundable, non-adjustable, and strictly non-transferable under any circumstances.\n'
                      '2. Membership is valid strictly for the specified period ($validityPeriod). Post expiration, admission requires timely renewal.\n'
                      '3. Members are required to carry this digital receipt or membership card and adhere strictly to gym safety rules and equipment etiquette.\n'
                      '4. Management reserves the right of admission and membership suspension in case of violation of gym guidelines.',
                      style: pw.TextStyle(
                        font: effectiveRegular,
                        fontSize: 7.2,
                        color: slateMedium,
                        lineSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),
              pw.Container(height: 0.5, color: borderLight),
              pw.SizedBox(height: 6),

              // ================= FOOTER / TAGLINE =================
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Thank you for training with us! Consistency is the key to transformation.',
                    style: pw.TextStyle(
                      font: effectiveMedium,
                      fontSize: 7.5,
                      color: slateMedium,
                    ),
                  ),
                  pw.Text(
                    'Computer-generated invoice $bullet No physical signature required',
                    style: pw.TextStyle(
                      font: effectiveRegular,
                      fontSize: 7,
                      color: slateLight,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// System print dialog / PDF layout generator
  Future<void> printReceipt({
    required BillRecord bill,
    Customer? customer,
    GymSettings? settings,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      bill: bill,
      customer: customer,
      settings: settings,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Payment_Receipt_${bill.billNumber}',
    );
  }

  /// One-tap share of real PDF receipt via system sharing sheet (WhatsApp, Email, Drive, etc.)
  Future<void> shareReceiptPdf({
    required BillRecord bill,
    Customer? customer,
    GymSettings? settings,
  }) async {
    final pdfBytes = await generateReceiptPdf(
      bill: bill,
      customer: customer,
      settings: settings,
    );

    final sanitizedCustomer = bill.customerName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    final filename = 'Receipt_${bill.billNumber}_$sanitizedCustomer.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  // Helpers
  static pw.Widget _buildDetailRow(
    String label,
    String value,
    pw.Font regularFont,
    pw.Font valueFont,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: slateLight),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            value,
            style: pw.TextStyle(font: valueFont,
              fontSize: 8.5, color: slateDark),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String value,
    pw.Font regularFont,
    pw.Font valueFont,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: slateMedium),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(font: valueFont, fontSize: 8.5, color: slateDark),
        ),
      ],
    );
  }
}
