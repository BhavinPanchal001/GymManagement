import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../models/bill.dart';
import '../services/gym_service.dart';
import '../utils/date_utils.dart';
import '../widgets/whatsapp_reminder_sheet.dart';
import '../widgets/whatsapp_welcome_sheet.dart';
import '../utils/nav_keys.dart';

enum WelcomeTone {
  standard,
  energetic,
  concise;

  String get label {
    switch (this) {
      case WelcomeTone.standard:
        return 'Standard';
      case WelcomeTone.energetic:
        return 'Energetic';
      case WelcomeTone.concise:
        return 'Quick & Direct';
    }
  }
}

enum ReminderTone {
  standard,
  friendly,
  urgent;

  String get label {
    switch (this) {
      case ReminderTone.standard:
        return 'Standard';
      case ReminderTone.friendly:
        return 'Friendly';
      case ReminderTone.urgent:
        return 'Urgent / Due';
    }
  }
}

class WhatsAppService {
  static final WhatsAppService _instance = WhatsAppService._internal();
  factory WhatsAppService() => _instance;
  WhatsAppService._internal();

  /// Normalizes phone number into WhatsApp international format without '+' or special characters.
  /// Defaults to India (+91) if a 10-digit number is supplied.
  String normalizePhoneNumber(String phone, {String defaultCountryCode = '91'}) {
    // Remove all non-digits
    String cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return '';

    // If starts with leading 0 (e.g. 09876543210), strip the leading 0
    if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }

    // If 10 digits without country code, prepend default country code
    if (cleaned.length == 10) {
      cleaned = '$defaultCountryCode$cleaned';
    }

    return cleaned;
  }

  /// Builds predefined message based on customer and due details
  String buildReminderMessage({
    required String customerName,
    required String monthYear,
    required double amount,
    String? currency,
    String? gymName,
    ReminderTone tone = ReminderTone.standard,
  }) {
    final gymSettings = GymService().settings;
    final curr = (currency != null && currency.trim().isNotEmpty)
        ? currency
        : gymSettings.currencySymbol;
    final formattedMonth = GymDateUtils.formatMonthYearKey(monthYear);
    final formattedAmount = GymDateUtils.formatCurrency(amount, symbol: curr);
    final name = customerName.trim().isEmpty ? 'Valued Member' : customerName.trim();
    
    // Resolve Gym Name: provided parameter -> settings -> default fallback
    final String gym;
    if (gymName != null && gymName.trim().isNotEmpty) {
      gym = gymName.trim();
    } else if (gymSettings.gymName.trim().isNotEmpty) {
      gym = gymSettings.gymName.trim();
    } else {
      gym = 'IronPulse Fitness Club';
    }

    switch (tone) {
      case ReminderTone.friendly:
        return '💪 *Hello from $gym!* 💪\n\n'
            'Hi *$name*,\n\n'
            'Hope you are enjoying your workouts at *$gym*! Just a quick and friendly reminder that your gym membership fee for *$formattedMonth* (*$formattedAmount*) is due.\n\n'
            '💰 *Amount Due:* *$formattedAmount*\n'
            '📅 *Billing Period:* *$formattedMonth*\n'
            '🏋️ *Gym:* *$gym*\n\n'
            'You can easily settle it on your next gym visit or via UPI.\n\n'
            'Keep up the great momentum and stay strong! 🏋️‍♂️✨\n\n'
            'Warm regards,\n'
            '*Team $gym*';

      case ReminderTone.urgent:
        return '⚠️ *$gym - Overdue Fee Notice* ⚠️\n\n'
            'Dear *$name*,\n\n'
            'This is an important reminder from *$gym* that your membership fee for *$formattedMonth* remains pending.\n\n'
            '💰 *Pending Amount:* *$formattedAmount*\n'
            '📅 *Billing Period:* *$formattedMonth*\n'
            '🏋️ *Gym:* *$gym*\n\n'
            'Kindly clear the balance at your earliest convenience to avoid any disruption to your gym sessions.\n\n'
            'If you have already settled this, please disregard this notice. Thank you!\n\n'
            '— *Management, $gym*';

      case ReminderTone.standard:
        return '🏋️ *$gym - Membership Fee Reminder* 🏋️\n\n'
            'Dear *$name*,\n\n'
            'Greetings from *$gym*! This is a friendly reminder that your membership fee for *$formattedMonth* is currently pending.\n\n'
            '💰 *Amount Due:* *$formattedAmount*\n'
            '📅 *Month:* *$formattedMonth*\n'
            '🏋️ *Gym:* *$gym*\n\n'
            'Kindly clear your dues at the gym counter or via UPI at your convenience. If you have already made this payment, please disregard this reminder.\n\n'
            'Thank you, and keep crushing your fitness goals! 💪🔥\n\n'
            '— *Team $gym*';
    }
  }

  /// Builds a WhatsApp reminder message specifically tailored for expiring or expired memberships
  String buildMembershipExpiryMessage({
    required Customer customer,
    required DateTime expiryDate,
    required int daysLeft,
    required double renewalAmount,
    String? currency,
  }) {
    final gymSettings = GymService().settings;
    final curr = currency ?? gymSettings.currencySymbol;
    final formattedDate = GymDateUtils.formatDisplayDate(expiryDate);
    final formattedAmount = GymDateUtils.formatCurrency(renewalAmount, symbol: curr);
    final gym = gymSettings.gymName.isNotEmpty ? gymSettings.gymName : 'IronPulse Fitness Club';
    final name = customer.name;

    if (daysLeft < 0) {
      final daysAgo = daysLeft.abs();
      return '⚠️ *$gym - Membership Expired Notice* ⚠️\n\n'
          'Hi *$name*,\n\n'
          'Your gym membership at *$gym* expired *$daysAgo ${daysAgo == 1 ? "day" : "days"} ago* on *$formattedDate*.\n\n'
          '🏋️ *Plan:* ${CustomerPlan.getLabel(customer.planType)}\n'
          '💰 *Renewal Fee:* *$formattedAmount*\n'
          '📅 *Expiry Date:* *$formattedDate*\n\n'
          'Don\'t break your fitness streak! Please renew your membership to continue uninterrupted access to the gym.\n\n'
          'You can pay at the counter or via UPI.\n\n'
          'Stay consistent, stay strong! 💪🔥\n'
          '— *Team $gym*';
    } else if (daysLeft == 0) {
      return '🔔 *$gym - Membership Expiring Today!* 🔔\n\n'
          'Hi *$name*,\n\n'
          'Your gym membership at *$gym* is expiring *TODAY* (*$formattedDate*).\n\n'
          '🏋️ *Plan:* ${CustomerPlan.getLabel(customer.planType)}\n'
          '💰 *Renewal Amount:* *$formattedAmount*\n\n'
          'Renew today to keep your fitness momentum going! Pay at the desk or via UPI.\n\n'
          '— *Team $gym*';
    } else {
      return '💪 *$gym - Membership Renewal Reminder* 💪\n\n'
          'Hi *$name*,\n\n'
          'Hope you\'re having fantastic workouts! Just a quick reminder that your gym membership at *$gym* will expire in *$daysLeft ${daysLeft == 1 ? "day" : "days"}* on *$formattedDate*.\n\n'
          '🏋️ *Plan:* ${CustomerPlan.getLabel(customer.planType)}\n'
          '💰 *Renewal Fee:* *$formattedAmount*\n'
          '📅 *Valid Till:* *$formattedDate*\n\n'
          'Renew early to ensure seamless entry and workout progress!\n\n'
          'Keep pushing, you\'re doing great! 🏋️‍♂️✨\n'
          '— *Team $gym*';
    }
  }

  /// Attempts to launch WhatsApp via native scheme first, then falls back to wa.me web link.
  Future<bool> openWhatsApp({
    required String phone,
    required String message,
    BuildContext? context,
  }) async {
    final cleanPhone = normalizePhoneNumber(phone);
    if (cleanPhone.isEmpty) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or missing phone number for WhatsApp.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }

    final encodedText = Uri.encodeComponent(message);

    // 1. Try native WhatsApp URL scheme
    final nativeUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedText');

    try {
      if (await canLaunchUrl(nativeUri)) {
        final launched = await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        if (launched) return true;
      }
    } catch (_) {
      // Ignore and fallback to web URL
    }

    // 2. Fallback to universal web link: https://wa.me/
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedText');
    try {
      final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    } catch (e) {
      debugPrint('Error launching WhatsApp web link: $e');
    }

    // 3. If neither worked, copy message to clipboard and alert user
    await Clipboard.setData(ClipboardData(text: message));
    final messenger = (context != null && context.mounted)
        ? ScaffoldMessenger.of(context)
        : rootScaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: const Text(
          'Could not open WhatsApp app. Reminder text has been copied to clipboard!',
        ),
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
    return false;
  }

  /// Displays the interactive WhatsApp Reminder Sheet with preview, template picker & send button.
  Future<void> showReminderSheet({
    BuildContext? context,
    required Customer customer,
    required String monthYear,
    required double amount,
  }) {
    final targetContext = (context != null && context.mounted)
        ? context
        : rootNavigatorKey.currentContext;
    if (targetContext == null) return Future.value();
    return WhatsAppReminderSheet.show(
      targetContext,
      customer: customer,
      monthYear: monthYear,
      amount: amount,
    );
  }

  /// Displays the interactive WhatsApp Welcome Sheet for newly registered members.
  Future<void> showWelcomeSheet({
    BuildContext? context,
    required Customer customer,
  }) {
    final targetContext = (context != null && context.mounted)
        ? context
        : rootNavigatorKey.currentContext;
    if (targetContext == null) return Future.value();
    return WhatsAppWelcomeSheet.show(
      targetContext,
      customer: customer,
    );
  }

  /// Builds a personalized welcome message for new member onboarding
  String buildWelcomeMessage({
    required Customer customer,
    String? gymName,
    String? timings,
    WelcomeTone tone = WelcomeTone.standard,
  }) {
    final gymSettings = GymService().settings;
    final String gym;
    if (gymName != null && gymName.trim().isNotEmpty) {
      gym = gymName.trim();
    } else if (gymSettings.gymName.trim().isNotEmpty) {
      gym = gymSettings.gymName.trim();
    } else {
      gym = 'IronPulse Fitness Club';
    }

    final name = customer.name.trim().isNotEmpty ? customer.name.trim() : 'Fitness Enthusiast';
    final plan = CustomerPlan.getLabel(customer.planType);
    final duration = customer.planDurationMonths > 1 ? '${customer.planDurationMonths} Months' : '1 Month';
    final startDate = GymDateUtils.formatDisplayDate(customer.joinDate);
    final defaultTimings = timings?.trim().isNotEmpty == true
        ? timings!.trim()
        : '🌅 Morning: 6:00 AM – 11:00 AM\n🌆 Evening: 5:00 PM – 10:00 PM\n📅 Mon – Sat (Sunday Rest / Maintenance)';

    switch (tone) {
      case WelcomeTone.energetic:
        return '🔥 *WELCOME TO $gym!* 🔥\n\n'
            'Hey *$name*,\n\n'
            'Super excited to welcome you to the family! Get ready to crush your fitness goals and transform yourself.\n\n'
            '📋 *Plan:* $plan ($duration)\n'
            '📅 *Start Date:* $startDate\n'
            '⏰ *Gym Timings:*\n$defaultTimings\n\n'
            '⚡ *Quick Pro-Tips:*\n'
            '• Carry your gym towel and clean pair of training shoes.\n'
            '• Hydrate well before, during, and after workouts.\n'
            '• Our trainers are always here on the floor if you need guidance!\n\n'
            'Let\'s build strength and level up together! 💪🏋️‍♂️🔥\n\n'
            '— *Team $gym*';

      case WelcomeTone.concise:
        return '👋 *Welcome to $gym, $name!* 👋\n\n'
            'We are delighted to have you train with us. Here are your onboarding details:\n\n'
            '📋 *Plan:* $plan ($duration)\n'
            '📅 *Joining Date:* $startDate\n'
            '⏰ *Timings:*\n$defaultTimings\n\n'
            '👟 Remember clean workout shoes and a water bottle.\n'
            'See you on the floor! Stay strong! 💪\n\n'
            '— *Team $gym*';

      case WelcomeTone.standard:
        return '🎉 *Welcome to $gym!* 🎉\n\n'
            'Dear *$name*,\n\n'
            'A very warm welcome to *$gym*! We are delighted to partner with you on your fitness journey.\n\n'
            '🏋️ *Membership Details:*\n'
            '• *Plan:* $plan\n'
            '• *Duration:* $duration\n'
            '• *Start Date:* $startDate\n\n'
            '⏰ *Gym Hours:*\n$defaultTimings\n\n'
            '💡 *Important Guidelines:*\n'
            '• Please bring separate indoor training shoes & a gym towel.\n'
            '• Wipe down equipment after use & re-rack your weights.\n'
            '• Never hesitate to reach out to our gym staff for any assistance.\n\n'
            'We look forward to seeing your progress and consistency! 💪🔥\n\n'
            'Warm regards,\n'
            '*Management, $gym*';
    }
  }

  /// Direct one-tap reminder sender without opening the preview sheet
  Future<bool> sendQuickReminder({
    required BuildContext context,
    required Customer customer,
    required String monthYear,
    required double amount,
  }) async {
    final gym = GymService();
    final message = buildReminderMessage(
      customerName: customer.name,
      monthYear: monthYear,
      amount: amount,
      currency: gym.settings.currencySymbol,
      gymName: gym.settings.gymName,
      tone: ReminderTone.standard,
    );

    return openWhatsApp(
      phone: customer.phone,
      message: message,
      context: context,
    );
  }

  /// Formats an official digital bill/receipt message suitable for WhatsApp sharing
  String buildBillReceiptMessage({
    required BillRecord bill,
    String? currency,
  }) {
    final cur = currency ?? GymService().settings.currencySymbol;
    final formattedAmount = GymDateUtils.formatCurrency(bill.amount, symbol: cur);
    final formattedPaidDate = GymDateUtils.formatDateTime(bill.paidAt);
    final planLabel = CustomerPlan.getLabel(bill.planType);
    final gym = bill.gymName.isNotEmpty ? bill.gymName : GymService().settings.gymName;

    final buf = StringBuffer();
    buf.writeln('🧾 *FEE RECEIPT / PAYMENT BILL* 🧾');
    buf.writeln('🏢 *$gym*');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('📄 *Invoice No:* ${bill.billNumber}');
    buf.writeln('📅 *Date:* $formattedPaidDate');
    buf.writeln('👤 *Member Name:* ${bill.customerName}');
    if (bill.customerPhone.isNotEmpty) {
      buf.writeln('📞 *Contact:* ${bill.customerPhone}');
    }
    buf.writeln('📋 *Membership Plan:* $planLabel');
    buf.writeln('🗓️ *Validity:* ${bill.formattedValidityPeriod}');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('💵 *Amount Paid:* *$formattedAmount*');
    buf.writeln('💳 *Payment Method:* ${bill.method.label}');
    if (bill.transactionRef != null && bill.transactionRef!.trim().isNotEmpty) {
      buf.writeln('🔖 *Txn Ref / ID:* ${bill.transactionRef!.trim()}');
    }
    if (bill.notes != null && bill.notes!.trim().isNotEmpty) {
      buf.writeln('📝 *Remarks:* ${bill.notes!.trim()}');
    }
    buf.writeln('✅ *Status:* PAID');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('Thank you for training with *$gym*!');
    buf.writeln('Stay consistent, stay fit, and keep crushing your goals! 💪🔥');

    return buf.toString();
  }

  /// Sends the formatted bill receipt directly to the member via WhatsApp
  Future<bool> sendBillReceipt({
    BuildContext? context,
    required BillRecord bill,
    String? currency,
  }) async {
    final message = buildBillReceiptMessage(bill: bill, currency: currency);
    return openWhatsApp(
      phone: bill.customerPhone,
      message: message,
      context: context,
    );
  }
}
