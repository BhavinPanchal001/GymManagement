import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/customer.dart';
import '../services/gym_service.dart';
import '../services/whatsapp_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import 'customer_avatar.dart';

class WhatsAppWelcomeSheet extends StatefulWidget {
  final Customer customer;

  const WhatsAppWelcomeSheet({
    super.key,
    required this.customer,
  });

  static Future<void> show(
    BuildContext context, {
    required Customer customer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WhatsAppWelcomeSheet(
        customer: customer,
      ),
    );
  }

  @override
  State<WhatsAppWelcomeSheet> createState() => _WhatsAppWelcomeSheetState();
}

class _WhatsAppWelcomeSheetState extends State<WhatsAppWelcomeSheet> {
  late TextEditingController _messageController;
  WelcomeTone _selectedTone = WelcomeTone.standard;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: _generateText(_selectedTone));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _generateText(WelcomeTone tone) {
    return WhatsAppService().buildWelcomeMessage(
      customer: widget.customer,
      tone: tone,
    );
  }

  void _onToneChanged(WelcomeTone tone) {
    setState(() {
      _selectedTone = tone;
      _messageController.text = _generateText(tone);
    });
  }

  Future<void> _handleSend() async {
    setState(() => _isSending = true);
    final text = _messageController.text.trim();

    final success = await WhatsAppService().openWhatsApp(
      phone: widget.customer.phone,
      message: text,
      context: context,
    );

    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: _messageController.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Welcome message copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const welcomeAccent = Color(0xFF00B4D8);
    final planLabel = CustomerPlan.getLabel(widget.customer.planType);
    final durationLabel = widget.customer.planDurationMonths > 1
        ? '${widget.customer.planDurationMonths} Months'
        : '1 Month';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder, width: 1.5),
          left: BorderSide(color: AppColors.surfaceBorder, width: 1.5),
          right: BorderSide(color: AppColors.surfaceBorder, width: 1.5),
        ),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Sheet Title & WhatsApp Branding
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: welcomeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: welcomeAccent.withValues(alpha: 0.35)),
                  ),
                  child: const Center(
                    child: Icon(Icons.waving_hand_rounded, color: welcomeAccent, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Welcome Message',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            widget.customer.name,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('•', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          const SizedBox(width: 6),
                          Text(
                            widget.customer.phone.isNotEmpty ? widget.customer.phone : 'No phone',
                            style: TextStyle(
                              color: widget.customer.phone.isNotEmpty ? AppColors.whatsapp : AppColors.absent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Onboarding Member Details Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                children: [
                  CustomerAvatar(
                    imagePath: widget.customer.imagePath,
                    imageBase64: widget.customer.imageBase64,
                    name: widget.customer.name,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$planLabel ($durationLabel)',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Joined ${GymDateUtils.formatDisplayDate(widget.customer.joinDate)} • New Onboarding',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: welcomeAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: welcomeAccent.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: welcomeAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tone / Template Selector Chips
            Text(
              'Message Tone',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: WelcomeTone.values.map((tone) {
                final isSelected = _selectedTone == tone;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => _onToneChanged(tone),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? welcomeAccent.withValues(alpha: 0.2) : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? welcomeAccent : AppColors.surfaceBorder,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          tone.label,
                          style: TextStyle(
                            color: isSelected ? welcomeAccent : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Message Preview / Editor Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Message Preview & Customization',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton.icon(
                  onPressed: _handleCopy,
                  icon: Icon(Icons.copy_rounded, size: 13, color: AppColors.textSecondary),
                  label: Text(
                    'Copy Text',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.whatsappSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.whatsapp.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.whatsapp,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'WhatsApp Welcome • ${GymService().settings.gymName.isNotEmpty ? GymService().settings.gymName : "Gym"}',
                          style: const TextStyle(
                            color: AppColors.whatsapp,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 8,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'Type welcome message...',
                      hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Button
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _handleSend,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: Text(
                      _isSending ? 'Opening...' : 'Send via WhatsApp',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.whatsapp,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
