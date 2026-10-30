import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/gym_service.dart';
import '../../services/member_card_pdf_service.dart';
import '../../services/whatsapp_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class MemberCardScreen extends StatefulWidget {
  final Customer customer;

  const MemberCardScreen({super.key, required this.customer});

  static Future<void> push(BuildContext context, {required Customer customer}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberCardScreen(customer: customer)),
    );
  }

  @override
  State<MemberCardScreen> createState() => _MemberCardScreenState();
}

class _MemberCardScreenState extends State<MemberCardScreen> {
  late int _selectedYear;
  bool _isGeneratingPdf = false;

  String? _pdfKey;
  Future<Uint8List>? _pdfBytes;

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
  }

  Future<Uint8List> _cardPdf(Customer customer) {
    final gym = GymService();
    final key = jsonEncode({
      'year': _selectedYear,
      'customer': customer.toMap(),
      'settings': gym.settings.toMap(),
      'logo': gym.gymLogoPath,
      'payments': gym.paymentMap.values
          .where((p) => p.customerId == customer.id)
          .map((p) => p.toMap())
          .toList(),
      'attendance': gym.attendanceMap.values
          .where((a) => a.customerId == customer.id)
          .map((a) => a.toMap())
          .toList(),
      'today': GymDateUtils.toDateKey(DateTime.now()),
    });
    if (_pdfKey != key || _pdfBytes == null) {
      _pdfKey = key;
      _pdfBytes = MemberCardPdfService().generateCardPdf(
        customer: customer,
        year: _selectedYear,
      );
    }
    return _pdfBytes!;
  }

  Future<void> _handlePrint() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final gym = GymService();
      final customer =
          gym.getCustomerById(widget.customer.id) ?? widget.customer;
      final bytes = await _cardPdf(customer);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Gym_Card_${customer.name}_$_selectedYear',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to print card: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _handleSharePdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final gym = GymService();
      final customer =
          gym.getCustomerById(widget.customer.id) ?? widget.customer;
      final bytes = await _cardPdf(customer);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'Gym_Card_${customer.name.replaceAll(' ', '_')}_$_selectedYear.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _handleShareWhatsApp() async {
    final gym = GymService();
    final customer = gym.getCustomerById(widget.customer.id) ?? widget.customer;
    final yearly = gym.getYearlyCardData(customer.id, _selectedYear);
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

    final message =
        '🏋️ *${gym.settings.gymName} - Member Ledger Card ($_selectedYear)*\n\n'
        '👤 *Member:* ${customer.name}\n'
        '💳 *Card No:* ${customer.cardNumber.isNotEmpty ? customer.cardNumber : customer.id}\n'
        '📅 *Joined:* ${GymDateUtils.formatDisplayDate(customer.joinDate)}\n'
        '📞 *Phone:* ${customer.phone}\n\n'
        '📊 *Summary for $_selectedYear:*\n'
        '• Fees Paid: *$paidCount / 12 Months*\n'
        '• Total Gym Attendance: *$totalPres Days*\n'
        '${totalDue > 0 ? '• 💰 Total Due: *${GymDateUtils.formatCurrency(totalDue, symbol: currency)}*\n' : ''}\n'
        'For complete ledger details or full card PDF, visit the gym desk!\n'
        '— *Management, ${gym.settings.gymName}*';

    await WhatsAppService().openWhatsApp(
      phone: customer.phone,
      message: message,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    return ListenableBuilder(
      listenable: gym,
      builder: (context, _) {
        final customer =
            gym.getCustomerById(widget.customer.id) ?? widget.customer;
        final pdfBytes = _cardPdf(customer);

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
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.textPrimary,
                    ),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    items:
                        [
                              DateTime.now().year - 2,
                              DateTime.now().year - 1,
                              DateTime.now().year,
                              DateTime.now().year + 1,
                            ]
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text(
                                  '$y',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
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
                icon: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: AppColors.textPrimary,
                ),
                tooltip: 'Download / Share PDF',
                onPressed: _isGeneratingPdf ? null : _handleSharePdf,
              ),
              IconButton(
                icon: const Icon(
                  Icons.chat_bubble_rounded,
                  color: AppColors.whatsapp,
                ),
                tooltip: 'Share via WhatsApp',
                onPressed: _handleShareWhatsApp,
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            top: false,
            child: PdfPreview.builder(
              key: ValueKey(_pdfKey),
              build: (_) => pdfBytes,
              initialPageFormat: PdfPageFormat.a4,
              dpi: 180,
              pagesBuilder: (context, pages) {
                if (pages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(24),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AspectRatio(
                        aspectRatio: pages.first.aspectRatio,
                        child: ColoredBox(
                          color: Colors.white,
                          child: Image(
                            image: pages.first.image,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            semanticLabel:
                                'Member card. Pinch to zoom and drag to move.',
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              useActions: false,
              maxPageWidth: 720,
              previewPageMargin: const EdgeInsets.all(12),
              scrollViewDecoration: BoxDecoration(color: AppColors.background),
              loadingWidget: const Center(child: CircularProgressIndicator()),
              onError: (context, error) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load the member card.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => setState(() => _pdfBytes = null),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
