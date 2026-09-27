import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/customer.dart';
import '../utils/date_utils.dart';
import 'gym_service.dart';

class MemberCardPdfService {
  static final MemberCardPdfService _instance = MemberCardPdfService._internal();
  factory MemberCardPdfService() => _instance;
  MemberCardPdfService._internal();

  /// Primary red color matching the physical entry form
  static const PdfColor cardRed = PdfColor.fromInt(0xFFB71C1C);
  static const PdfColor paidGreen = PdfColor.fromInt(0xFF1B5E20);

  /// Generates the Member Entry Form / Ledger Card as a high-resolution vector PDF
  Future<Uint8List> generateCardPdf({
    required Customer customer,
    required int year,
  }) async {
    final pdf = pw.Document();
    final gym = GymService();
    final gymSettings = gym.settings;
    final yearlyData = gym.getYearlyCardData(customer.id, year);

    // Load Gym Logo Image
    pw.MemoryImage? gymLogoImage;
    final logoPath = gymSettings.gymLogoPath ?? gym.gymLogoPath;
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
        debugPrint('Error loading gym logo image for PDF: $e');
      }
    }

    // Load Customer Photo Image
    pw.MemoryImage? customerPhotoImage;
    if (customer.imagePath != null &&
        customer.imagePath!.isNotEmpty &&
        !customer.imagePath!.startsWith('avatar:')) {
      try {
        String cleanPath = customer.imagePath!;
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
            customerPhotoImage = pw.MemoryImage(bytes);
          }
        }
      } catch (e) {
        debugPrint('Error loading customer photo image for PDF: $e');
      }
    }

    // Try to load Gujarati font for authentic footer notes
    pw.Font? gujaratiFont;
    pw.Font? regularFont;
    pw.Font? boldFont;

    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
      gujaratiFont = await PdfGoogleFonts.notoSansGujaratiRegular();
    } catch (_) {
      // Fallback to standard fonts if network/font fetch fails
    }

    final effectiveRegular = regularFont ?? pw.Font.helvetica();
    final effectiveBold = boldFont ?? pw.Font.helveticaBold();
    final effectiveGujarati = gujaratiFont ?? effectiveRegular;

    final gymName = gymSettings.gymName.trim().isNotEmpty
        ? gymSettings.gymName.trim().toUpperCase()
        : 'TITAN GYM';

    final cardNumber = customer.cardNumber.trim().isNotEmpty
        ? customer.cardNumber.trim()
        : customer.id.replaceAll(RegExp(r'\D'), '').padLeft(3, '0');

    final joinDateFormatted =
        '${customer.joinDate.day}, ${customer.joinDate.month}, ${customer.joinDate.year}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: cardRed, width: 2.5),
            ),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: cardRed, width: 1.0),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // ================= HEADER =================
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      // Photo Box (Top Left)
                      pw.Container(
                        width: 72,
                        height: 84,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: cardRed, width: 1.2),
                        ),
                        child: customerPhotoImage != null
                            ? pw.Image(customerPhotoImage, fit: pw.BoxFit.cover)
                            : pw.Center(
                                child: pw.Text(
                                  'PHOTO',
                                  style: pw.TextStyle(
                                    color: cardRed,
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    font: effectiveBold,
                                  ),
                                ),
                              ),
                      ),

                      // Center: ENTRY FORM badge & Gym Name
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            // ENTRY FORM badge
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 3,
                              ),
                              decoration: pw.BoxDecoration(
                                color: cardRed,
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: pw.Text(
                                'ENTRY FORM',
                                style: pw.TextStyle(
                                  color: PdfColors.white,
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  font: effectiveBold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            pw.SizedBox(height: 6),

                            // Circular logo representation
                            gymLogoImage != null
                                ? pw.Container(
                                    width: 42,
                                    height: 42,
                                    decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle,
                                      border: pw.Border.all(color: cardRed, width: 1.5),
                                    ),
                                    child: pw.ClipOval(
                                      child: pw.Image(
                                        gymLogoImage,
                                        fit: pw.BoxFit.cover,
                                      ),
                                    ),
                                  )
                                : pw.Container(
                                    width: 38,
                                    height: 38,
                                    decoration: pw.BoxDecoration(
                                      shape: pw.BoxShape.circle,
                                      border: pw.Border.all(color: cardRed, width: 1.5),
                                    ),
                                    child: pw.Center(
                                      child: pw.Text(
                                        'GYM',
                                        style: pw.TextStyle(
                                          color: cardRed,
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          font: effectiveBold,
                                        ),
                                      ),
                                    ),
                                  ),
                            pw.SizedBox(height: 4),

                            // Large Bold Gym Name
                            pw.Text(
                              gymName,
                              style: pw.TextStyle(
                                color: cardRed,
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                font: effectiveBold,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Card Number Box (Top Right)
                      pw.Container(
                        width: 80,
                        height: 38,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: cardRed, width: 1.5),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            cardNumber,
                            style: pw.TextStyle(
                              color: cardRed,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              font: effectiveBold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 14),

                  // ================= MEMBER INFO FIELDS =================
                  _buildRuledField('Name :', customer.name, effectiveBold, effectiveRegular),
                  pw.SizedBox(height: 8),
                  _buildRuledField(
                    'Add :',
                    customer.address.isNotEmpty ? customer.address : customer.notes,
                    effectiveBold,
                    effectiveRegular,
                  ),
                  pw.SizedBox(height: 8),

                  pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: _buildRuledField(
                          'Enter Date :',
                          joinDateFormatted,
                          effectiveBold,
                          effectiveRegular,
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      pw.Expanded(
                        flex: 6,
                        child: _buildRuledField(
                          'Mobile No.:',
                          customer.phone,
                          effectiveBold,
                          effectiveRegular,
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 14),

                  // ================= MEASUREMENTS TABLE =================
                  pw.Table(
                    border: pw.TableBorder.all(color: cardRed, width: 1.2),
                    children: [
                      // Header Row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.white),
                        children: [
                          _buildMeasurementHeader('Wt.', effectiveBold),
                          _buildMeasurementHeader('Chest', effectiveBold),
                          _buildMeasurementHeader('Bishep', effectiveBold),
                          _buildMeasurementHeader('Waist', effectiveBold),
                          _buildMeasurementHeader('Leg', effectiveBold),
                        ],
                      ),
                      // Value Row
                      pw.TableRow(
                        children: [
                          _buildMeasurementCell(customer.weight, effectiveRegular),
                          _buildMeasurementCell(customer.chest, effectiveRegular),
                          _buildMeasurementCell(customer.bicep, effectiveRegular),
                          _buildMeasurementCell(customer.waist, effectiveRegular),
                          _buildMeasurementCell(customer.leg, effectiveRegular),
                        ],
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 12),

                  // ================= YEAR HEADER =================
                  pw.Container(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'Year: $year',
                      style: pw.TextStyle(
                        color: cardRed,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        font: effectiveBold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 4),

                  // ================= 12 MONTH ATTENDANCE / FEE TABLE =================
                  // 2 Columns of 6 Months each
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // Left Column (Months 1 - 6)
                        pw.Expanded(
                          child: _buildMonthSubTable(
                            yearlyData.sublist(0, 6),
                            effectiveBold,
                            effectiveRegular,
                            currency: gymSettings.currencySymbol,
                          ),
                        ),
                        // Right Column (Months 7 - 12)
                        pw.Expanded(
                          child: _buildMonthSubTable(
                            yearlyData.sublist(6, 12),
                            effectiveBold,
                            effectiveRegular,
                            currency: gymSettings.currencySymbol,
                          ),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // ================= FOOTER / SPECIAL NOTE (Khaas Nondh) =================
                  pw.Container(
                    padding: const pw.EdgeInsets.only(top: 6),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: cardRed, width: 1.0)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ખાસ નોંધ :-  (Special Note)',
                          style: pw.TextStyle(
                            color: cardRed,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            font: effectiveGujarati,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          '• ભરેલી ફી કોઈપણ સંજોગોમાં પરત મળશે નહીં. (Fee once paid is non-refundable)',
                          style: pw.TextStyle(
                            color: cardRed,
                            fontSize: 8.5,
                            font: effectiveGujarati,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '• જીમના દરેક સભ્યો સાથે સભ્યતાથી વર્તન કરવું. તકરાર કરવી નહીં. (Maintain gym etiquette & discipline)',
                          style: pw.TextStyle(
                            color: cardRed,
                            fontSize: 8.5,
                            font: effectiveGujarati,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Builds a ruled single-line field (e.g. Name : _________)
  static pw.Widget _buildRuledField(
    String label,
    String value,
    pw.Font boldFont,
    pw.Font regularFont,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            color: cardRed,
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            font: boldFont,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: cardRed, width: 1.0),
              ),
            ),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: PdfColors.black,
                fontSize: 11,
                font: regularFont,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds a header cell for the measurements table
  static pw.Widget _buildMeasurementHeader(String title, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: cardRed,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          font: font,
        ),
      ),
    );
  }

  /// Builds a value cell for the measurements table
  static pw.Widget _buildMeasurementCell(String value, pw.Font font) {
    return pw.Container(
      height: 26,
      alignment: pw.Alignment.center,
      child: pw.Text(
        value.isNotEmpty ? value : '-',
        style: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 10,
          font: font,
        ),
      ),
    );
  }

  /// Builds 6 rows of month ledger (index, month name, status & attendance)
  static pw.Widget _buildMonthSubTable(
    List<MonthCardData> months,
    pw.Font boldFont,
    pw.Font regularFont, {
    required String currency,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: cardRed, width: 1.0),
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(),
      },
      children: months.map((m) {
        String feeText = '';
        PdfColor feeColor = PdfColors.grey700;

        if (m.isPaid) {
          feeText = m.isCoveredInPackage
              ? 'PAID (Pkg)'
              : 'PAID (${GymDateUtils.formatCurrency(m.amount, symbol: currency)})';
          feeColor = paidGreen;
        } else {
          feeText = '-';
        }

        String attendanceText = '';
        if (m.presentDays > 0) {
          attendanceText = '${m.presentDays} Pres';
        }

        return pw.TableRow(
          children: [
            // Month Index
            pw.Container(
              height: 32,
              alignment: pw.Alignment.center,
              child: pw.Text(
                '${m.month}',
                style: pw.TextStyle(
                  color: cardRed,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
            ),
            // Month Name
            pw.Container(
              height: 32,
              alignment: pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.only(left: 6),
              child: pw.Text(
                m.monthName,
                style: pw.TextStyle(
                  color: cardRed,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                ),
              ),
            ),
            // Fees & Attendance & Validity Date Range Box
            pw.Container(
              height: 32,
              alignment: pw.Alignment.centerLeft,
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: m.isPaid
                  ? pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              feeText,
                              style: pw.TextStyle(
                                color: feeColor,
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                font: boldFont,
                              ),
                            ),
                            if (attendanceText.isNotEmpty)
                              pw.Text(
                                attendanceText,
                                style: pw.TextStyle(
                                  color: cardRed,
                                  fontSize: 8,
                                  font: regularFont,
                                ),
                              ),
                          ],
                        ),
                        if (m.formattedDateRange != null) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            m.formattedDateRange!,
                            style: pw.TextStyle(
                              color: PdfColors.grey800,
                              fontSize: 7.5,
                              font: regularFont,
                            ),
                          ),
                        ],
                      ],
                    )
                  : pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          feeText,
                          style: pw.TextStyle(
                            color: feeColor,
                            fontSize: 8.5,
                            font: regularFont,
                          ),
                        ),
                        if (attendanceText.isNotEmpty)
                          pw.Text(
                            attendanceText,
                            style: pw.TextStyle(
                              color: cardRed,
                              fontSize: 8,
                              font: regularFont,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// One-tap print card using system printing framework
  Future<void> printCard({
    required Customer customer,
    required int year,
  }) async {
    final pdfBytes = await generateCardPdf(customer: customer, year: year);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Gym_Card_${customer.name}_$year',
    );
  }

  /// One-tap PDF share/save
  Future<void> shareCardPdf({
    required Customer customer,
    required int year,
  }) async {
    final pdfBytes = await generateCardPdf(customer: customer, year: year);
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'Gym_Card_${customer.name.replaceAll(' ', '_')}_$year.pdf',
    );
  }
}
