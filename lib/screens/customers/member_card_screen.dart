import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/gym_service.dart';
import '../../services/member_card_pdf_service.dart';
import '../../services/whatsapp_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/image_storage_utils.dart';
import '../../widgets/gym_logo_widget.dart';

class MemberCardScreen extends StatefulWidget {
  final Customer customer;

  const MemberCardScreen({
    super.key,
    required this.customer,
  });

  static Future<void> push(BuildContext context, {required Customer customer}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberCardScreen(customer: customer),
      ),
    );
  }

  @override
  State<MemberCardScreen> createState() => _MemberCardScreenState();
}

class _MemberCardScreenState extends State<MemberCardScreen> {
  late int _selectedYear;
  bool _isGeneratingPdf = false;

  static const Color cardRed = Color(0xFFB71C1C);
  static const Color paidGreen = Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  Widget _buildCustomerPhoto() {
    final imagePath = widget.customer.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(ImageStorageUtils.normalizeFilePath(imagePath));
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    final bytes =
        ImageStorageUtils.decodeBase64Image(widget.customer.imageBase64);
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, color: cardRed, size: 28),
          SizedBox(height: 2),
          Text(
            'PHOTO',
            style: TextStyle(
              color: cardRed,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint() async {
    setState(() => _isGeneratingPdf = true);
    try {
      await MemberCardPdfService().printCard(
        customer: widget.customer,
        year: _selectedYear,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print card: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _handleSharePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      await MemberCardPdfService().shareCardPdf(
        customer: widget.customer,
        year: _selectedYear,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _handleShareWhatsApp() async {
    final gym = GymService();
    final yearly = gym.getYearlyCardData(widget.customer.id, _selectedYear);
    final paidCount = yearly.where((m) => m.isPaid).length;
    final totalPres = yearly.fold<int>(0, (sum, m) => sum + m.presentDays);

    // Calculate total due for WhatsApp message
    final currency = gym.settings.currencySymbol;
    double totalDue = 0;
    for (final m in yearly) {
      if (m.isDue) {
        totalDue += m.dueAmount;
      } else if (m.balanceDue > 0) {
        totalDue += m.balanceDue;
      }
    }

    final message = '🏋️ *${gym.settings.gymName} - Member Ledger Card ($_selectedYear)*\n\n'
        '👤 *Member:* ${widget.customer.name}\n'
        '💳 *Card No:* ${widget.customer.cardNumber.isNotEmpty ? widget.customer.cardNumber : widget.customer.id}\n'
        '📅 *Joined:* ${GymDateUtils.formatDisplayDate(widget.customer.joinDate)}\n'
        '📞 *Phone:* ${widget.customer.phone}\n\n'
        '📊 *Summary for $_selectedYear:*\n'
        '• Fees Paid: *$paidCount / 12 Months*\n'
        '• Total Gym Attendance: *$totalPres Days*\n'
        '${totalDue > 0 ? '• 💰 Total Due: *${GymDateUtils.formatCurrency(totalDue, symbol: currency)}*\n' : ''}\n'
        'For complete ledger details or full card PDF, visit the gym desk!\n'
        '— *Management, ${gym.settings.gymName}*';

    await WhatsAppService().openWhatsApp(
      phone: widget.customer.phone,
      message: message,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final gymSettings = gym.settings;
    final gymLogoPath = gymSettings.gymLogoPath ?? gym.gymLogoPath;
    final yearlyData = gym.getYearlyCardData(widget.customer.id, _selectedYear);

    final gymName = gymSettings.gymName.trim().isNotEmpty
        ? gymSettings.gymName.trim().toUpperCase()
        : 'TITAN GYM';

    final cardNumber = widget.customer.cardNumber.trim().isNotEmpty
        ? widget.customer.cardNumber.trim()
        : widget.customer.id.replaceAll(RegExp(r'\D'), '').padLeft(3, '0');

    final joinDateFormatted =
        '${widget.customer.joinDate.day}, ${widget.customer.joinDate.month}, ${widget.customer.joinDate.year}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Member Entry Card'),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          // Year Selector
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                dropdownColor: AppColors.surfaceElevated,
                icon: Icon(Icons.arrow_drop_down, color: AppColors.textPrimary),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                items: [
                  DateTime.now().year - 2,
                  DateTime.now().year - 1,
                  DateTime.now().year,
                  DateTime.now().year + 1,
                ].map((y) => DropdownMenuItem(value: y, child: Text('$y', style: TextStyle(color: AppColors.textPrimary)))).toList(),
                onChanged: (y) {
                  if (y != null) setState(() => _selectedYear = y);
                },
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.print_rounded, color: AppColors.textPrimary),
            tooltip: 'Print Card',
            onPressed: _isGeneratingPdf ? null : _handlePrint,
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf_rounded, color: AppColors.textPrimary),
            tooltip: 'Download / Share PDF',
            onPressed: _isGeneratingPdf ? null : _handleSharePdf,
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.whatsapp),
            tooltip: 'Share via WhatsApp',
            onPressed: _handleShareWhatsApp,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isGeneratingPdf
            ? const Center(child: CircularProgressIndicator())
            : InteractiveViewer(
                minScale: 0.8,
                maxScale: 2.5,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  child: Center(
                    child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    // Outer Red Border
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: cardRed, width: 2.5),
                      ),
                      padding: const EdgeInsets.all(4),
                      // Inner Red Border
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cardRed, width: 1.0),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ================= HEADER =================
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Photo Box
                                Container(
                                  width: 68,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: cardRed, width: 1.2),
                                    color: Colors.grey.shade50,
                                  ),
                                  child: _buildCustomerPhoto(),
                                ),
                                const SizedBox(width: 10),

                                // Title & Logo Center
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // ENTRY FORM Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cardRed,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'ENTRY FORM',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),

                                      // Circular Gym Logo
                                      GymLogoWidget(
                                        logoPath: gymLogoPath,
                                        logoBase64:
                                            gymSettings.gymLogoBase64,
                                        gymName: gymName,
                                        size: 40,
                                        shape: BoxShape.circle,
                                        borderColor: cardRed,
                                        borderWidth: 1.5,
                                        backgroundColor: Colors.white,
                                        iconColor: cardRed,
                                      ),
                                      const SizedBox(height: 3),

                                      // Bold Gym Name
                                      Text(
                                        gymName,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: cardRed,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                          fontFamily: 'serif',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Card Number Box
                                Container(
                                  width: 72,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: cardRed, width: 1.5),
                                  ),
                                  child: Center(
                                    child: Text(
                                      cardNumber,
                                      style: const TextStyle(
                                        color: cardRed,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'monospace',
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            // ================= RULED FIELDS =================
                            _buildScreenRuledField('Name :', widget.customer.name),
                            const SizedBox(height: 8),
                            _buildScreenRuledField(
                              'Add :',
                              widget.customer.address.isNotEmpty
                                  ? widget.customer.address
                                  : widget.customer.notes,
                            ),
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _buildScreenRuledField(
                                    'Enter Date :',
                                    joinDateFormatted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 6,
                                  child: _buildScreenRuledField(
                                    'Mobile No.:',
                                    widget.customer.phone,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            // ================= MEASUREMENTS TABLE =================
                            Table(
                              border: TableBorder.all(color: cardRed, width: 1.2),
                              children: [
                                TableRow(
                                  children: [
                                    _buildMeasurementHeader('Wt.'),
                                    _buildMeasurementHeader('Chest'),
                                    _buildMeasurementHeader('Bishep'),
                                    _buildMeasurementHeader('Waist'),
                                    _buildMeasurementHeader('Leg'),
                                  ],
                                ),
                                TableRow(
                                  children: [
                                    _buildMeasurementCell(widget.customer.weight),
                                    _buildMeasurementCell(widget.customer.chest),
                                    _buildMeasurementCell(widget.customer.bicep),
                                    _buildMeasurementCell(widget.customer.waist),
                                    _buildMeasurementCell(widget.customer.leg),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ================= DUE PAYMENT SUMMARY =================
                            Builder(
                              builder: (context) {
                                double totalDue = 0;
                                int dueMonthCount = 0;
                                int partialCount = 0;
                                for (final m in yearlyData) {
                                  if (m.isDue) {
                                    totalDue += m.dueAmount;
                                    dueMonthCount++;
                                  } else if (m.balanceDue > 0) {
                                    totalDue += m.balanceDue;
                                    partialCount++;
                                  }
                                }
                                if (totalDue <= 0) return const SizedBox.shrink();
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    border: Border.all(color: const Color(0xFFE65100), width: 1.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100), size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text.rich(
                                          TextSpan(
                                            children: [
                                              const TextSpan(
                                                text: 'Total Due: ',
                                                style: TextStyle(
                                                  color: Color(0xFFE65100),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              TextSpan(
                                                text: GymDateUtils.formatCurrency(totalDue, symbol: gymSettings.currencySymbol),
                                                style: const TextStyle(
                                                  color: Color(0xFFBF360C),
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              TextSpan(
                                                text: '  ($dueMonthCount unpaid${partialCount > 0 ? ', $partialCount partial' : ''})',
                                                style: const TextStyle(
                                                  color: Color(0xFFE65100),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // Year indicator
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'MONTHLY LEDGER & ATTENDANCE',
                                  style: TextStyle(
                                    color: cardRed,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Text(
                                  'YEAR: $_selectedYear',
                                  style: const TextStyle(
                                    color: cardRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // ================= 12-MONTH TABLE =================
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Months 1 - 6
                                Expanded(
                                  child: _buildScreenMonthSubTable(
                                    yearlyData.sublist(0, 6),
                                    currency: gymSettings.currencySymbol,
                                  ),
                                ),
                                // Months 7 - 12
                                Expanded(
                                  child: _buildScreenMonthSubTable(
                                    yearlyData.sublist(6, 12),
                                    currency: gymSettings.currencySymbol,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ================= FOOTER / GUJARATI NOTES =================
                            Container(
                              padding: const EdgeInsets.only(top: 8),
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: cardRed, width: 1.0),
                                ),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ખાસ નોંધ :-',
                                    style: TextStyle(
                                      color: cardRed,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '• ભરેલી ફી કોઈપણ સંજોગોમાં પરત મળશે નહીં.',
                                    style: TextStyle(
                                      color: cardRed,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '• જીમના દરેક સભ્યો સાથે સભ્યતાથી વર્તન કરવું. તકરાર કરવી નહીં.',
                                    style: TextStyle(
                                      color: cardRed,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildScreenRuledField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: cardRed,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(bottom: 2, left: 4),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cardRed, width: 1.0),
              ),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      color: Colors.grey.shade50,
      child: Text(
        title,
        style: const TextStyle(
          color: cardRed,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMeasurementCell(String value) {
    return Container(
      height: 28,
      alignment: Alignment.center,
      child: Text(
        value.isNotEmpty ? value : '-',
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScreenMonthSubTable(
    List<MonthCardData> months, {
    required String currency,
  }) {
    return Table(
      border: TableBorder.all(color: cardRed, width: 1.0),
      columnWidths: const {
        0: FixedColumnWidth(22),
        1: FixedColumnWidth(64),
        2: FlexColumnWidth(),
      },
      children: months.map((m) {
        final isDue = m.isDue;
        final hasBalance = m.isPaid && m.balanceDue > 0;
        String feeText = '-';
        Color feeColor = Colors.black26;
        if (m.isPaid) {
          feeText = m.isCoveredInPackage
              ? 'PAID (Pkg)'
              : 'PAID (${GymDateUtils.formatCurrency(m.amount, symbol: currency)})';
          feeColor = paidGreen;
          if (hasBalance) {
            feeText += ' BAL (${GymDateUtils.formatCurrency(m.balanceDue, symbol: currency)})';
            feeColor = const Color(0xFFE65100);
          }
        } else if (isDue) {
          feeText = 'DUE (${GymDateUtils.formatCurrency(m.dueAmount, symbol: currency)})';
          feeColor = const Color(0xFFD32F2F);
        }

        return TableRow(
          children: [
            // Month Index
            Container(
              height: 36,
              alignment: Alignment.center,
              child: Text(
                '${m.month}',
                style: const TextStyle(
                  color: cardRed,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Month Name
            Container(
              height: 36,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                m.monthName,
                style: const TextStyle(
                  color: cardRed,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Paid / Due status, Date Range & Attendance
            Container(
              height: 36,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          feeText,
                          style: TextStyle(
                            color: feeColor,
                            fontSize: hasBalance ? 7.5 : 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (m.presentDays > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '✓ ${m.presentDays} Pres',
                          style: const TextStyle(
                            color: cardRed,
                            fontSize: 7.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (m.formattedDateRange != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      m.formattedDateRange!,
                      style: const TextStyle(
                        color: Color(0xFF424242),
                        fontSize: 7.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
