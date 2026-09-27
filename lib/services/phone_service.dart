import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../theme/app_theme.dart';
import 'whatsapp_service.dart';

class PhoneService {
  static final PhoneService _instance = PhoneService._internal();
  factory PhoneService() => _instance;
  PhoneService._internal();

  /// Sanitizes phone number for dialing (preserves leading '+' if present, strips non-digits).
  String cleanPhoneNumber(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return '';
    final hasPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return hasPlus ? '+$digits' : digits;
  }

  /// Initiates a phone call via the device dialer.
  Future<bool> makeCall(
    String phone, {
    BuildContext? context,
    String? memberName,
  }) async {
    final clean = cleanPhoneNumber(phone);
    if (clean.isEmpty) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid phone number available to call.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    final uri = Uri(scheme: 'tel', path: clean);

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);
        if (launched) return true;
      }
      // Fallback: try direct launch in case canLaunchUrl is restricted
      final launched = await launchUrl(uri);
      if (launched) return true;
    } catch (e) {
      debugPrint('Error launching phone call: $e');
    }

    // If launching dialer failed (e.g. emulator, tablet or desktop), copy to clipboard
    await Clipboard.setData(ClipboardData(text: clean));
    if (context != null && context.mounted) {
      final displayName = memberName != null && memberName.trim().isNotEmpty
          ? memberName.trim()
          : 'Member';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open phone dialer. $displayName\'s phone ($clean) copied to clipboard!',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    return false;
  }

  /// Opens an interactive contact options bottom sheet for the member.
  void showContactOptionsSheet({
    required BuildContext context,
    required Customer customer,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.surfaceBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Member Info Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Icon(Icons.person_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customer.phone.isNotEmpty ? customer.phone : 'No phone number provided',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: AppColors.surfaceBorder, height: 1),
              const SizedBox(height: 12),

              // Call Option
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.call_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text(
                  'Call Member',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Open dialer to call ${customer.phone}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  makeCall(customer.phone, context: context, memberName: customer.name);
                },
              ),
              const SizedBox(height: 6),

              // WhatsApp Option
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.whatsapp.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, color: AppColors.whatsapp, size: 20),
                ),
                title: Text(
                  'Chat on WhatsApp',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Send message or greeting via WhatsApp',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  WhatsAppService().openWhatsApp(
                    phone: customer.phone,
                    message: 'Hello ${customer.name}!',
                    context: context,
                  );
                },
              ),
              const SizedBox(height: 6),

              // Copy Phone Option
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.copy_rounded, color: AppColors.textSecondary, size: 20),
                ),
                title: Text(
                  'Copy Phone Number',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  'Copy ${customer.phone} to clipboard',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: customer.phone));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Phone number copied to clipboard: ${customer.phone}'),
                        backgroundColor: AppColors.surfaceElevated,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
