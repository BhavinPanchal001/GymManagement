import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../services/auth_service.dart';
import '../../services/gym_service.dart';
import '../../services/notification_service.dart';
import '../../services/theme_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/gym_logo_widget.dart';
import '../../widgets/danger_confirmation_dialog.dart';
import '../intro/intro_screen.dart';
import 'edit_profile_screen.dart';
import '../../widgets/animations/animated_fade_slide.dart';
import '../../widgets/animations/animated_pressable.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _gymNameController;
  late TextEditingController _normalFeeController;
  late TextEditingController _ptFeeController;
  late TextEditingController _ptDietFeeController;

  @override
  void initState() {
    super.initState();
    final settings = GymService().settings;
    _gymNameController = TextEditingController(text: settings.gymName);
    _normalFeeController = TextEditingController(text: settings.normalPlanFee.toInt().toString());
    _ptFeeController = TextEditingController(text: settings.ptPlanFee.toInt().toString());
    _ptDietFeeController = TextEditingController(text: settings.ptDietPlanFee.toInt().toString());
  }

  void _syncControllersFromSettings() {
    if (!mounted) return;
    final settings = GymService().settings;
    _gymNameController.text = settings.gymName;
    _normalFeeController.text = settings.normalPlanFee.toInt().toString();
    _ptFeeController.text = settings.ptPlanFee.toInt().toString();
    _ptDietFeeController.text = settings.ptDietPlanFee.toInt().toString();
  }

  Future<void> _openEditProfile() async {
    await EditProfileScreen.navigate(context);
    if (!mounted) return;
    setState(() {
      _syncControllersFromSettings();
    });
  }

  @override
  void dispose() {
    _gymNameController.dispose();
    _normalFeeController.dispose();
    _ptFeeController.dispose();
    _ptDietFeeController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final gym = GymService();
    final normalFee = double.tryParse(_normalFeeController.text.trim()) ?? gym.settings.normalPlanFee;
    final ptFee = double.tryParse(_ptFeeController.text.trim()) ?? gym.settings.ptPlanFee;
    final ptDietFee = double.tryParse(_ptDietFeeController.text.trim()) ?? gym.settings.ptDietPlanFee;
    final name = _gymNameController.text.trim().isNotEmpty ? _gymNameController.text.trim() : gym.settings.gymName;

    final existingPackages = List.of(gym.settings.durationPackages);
    final updatedPackages = existingPackages.map((p) {
      if (p.months == 1) {
        if (p.planType == CustomerPlan.normal) {
          return p.copyWith(price: normalFee);
        }
        if (p.planType == CustomerPlan.personalTraining) {
          return p.copyWith(price: ptFee);
        }
        if (p.planType == CustomerPlan.personalTrainingDiet) {
          return p.copyWith(price: ptDietFee);
        }
      }
      return p;
    }).toList();

    final updated = gym.settings.copyWith(
      gymName: name,
      normalPlanFee: normalFee,
      standardMonthlyFee: normalFee,
      ptPlanFee: ptFee,
      ptDietPlanFee: ptDietFee,
      durationPackages: updatedPackages,
    );

    await gym.updateSettings(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gym settings & plan pricing updated successfully!'),
          backgroundColor: AppColors.paid,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmResetData() async {
    final gym = GymService();

    if (gym.customers.isNotEmpty) {
      final confirmed = await DangerConfirmationDialog.show(
        context,
        title: 'Reset to Demo Data?',
        description:
            'This will replace your current gym data with default sample members, attendance history, and monthly payments. All real records will be permanently erased locally and from the cloud.',
        actionLabel: 'Reset to Demo',
        confirmationPhrase: 'DELETE ALL DATA',
        memberCount: gym.customers.length,
        attendanceCount: gym.attendanceRecordCount,
        paymentCount: gym.paymentRecordCount,
        billCount: gym.billRecordCount,
        expenseCount: gym.expenses.length,
      );

      if (confirmed == true) {
        await gym.resetToDemoData(force: true);
        if (!mounted) return;
        setState(() {
          _syncControllersFromSettings();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Demo data reloaded successfully!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppColors.paid,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Load Sample / Demo Data?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will populate default sample members, attendance history, and monthly payments.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.primaryOn),
            onPressed: () async {
              Navigator.pop(ctx);
              await gym.resetToDemoData(force: true);
              if (!mounted) return;
              setState(() {
                _syncControllersFromSettings();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Demo data loaded successfully!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: AppColors.paid,
                ),
              );
            },
            child: const Text('Load Demo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAllData() async {
    final gym = GymService();

    if (gym.customers.isNotEmpty) {
      final confirmed = await DangerConfirmationDialog.show(
        context,
        title: 'Clear All Gym Data?',
        description:
            'This will permanently delete all members, attendance records, payments, bills, and expenses. Your gym will start completely fresh.\n\nThis action CANNOT be undone.',
        actionLabel: 'Clear All Data',
        confirmationPhrase: 'DELETE ALL DATA',
        memberCount: gym.customers.length,
        attendanceCount: gym.attendanceRecordCount,
        paymentCount: gym.paymentRecordCount,
        billCount: gym.billRecordCount,
        expenseCount: gym.expenses.length,
      );

      if (confirmed == true) {
        await gym.clearAllGymData(force: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All gym data cleared. Ready for your members!'),
            backgroundColor: AppColors.paid,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Clear All Gym Data?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will clear any remaining expenses or temporary records.\n\nThis action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.absent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await gym.clearAllGymData(force: true);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All gym data cleared. Ready for your members!'),
                  backgroundColor: AppColors.paid,
                ),
              );
            },
            child: const Text('Clear All Data', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Sign Out?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to sign out of your account?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.absent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService().signOut();
            },
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    return Expanded(
      child: AnimatedPressable(
        onTap: () => ThemeService().setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.14) : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: isSelected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final theme = ThemeService();
        final currency = gym.settings.currencySymbol;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Gym Settings'),
            actions: [
              IconButton(
                tooltip: 'Toggle Theme',
                icon: Icon(
                  theme.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: AppColors.primary,
                ),
                onPressed: () => theme.toggleTheme(),
              ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Account & Security Card
                AnimatedFadeSlide.staggered(
                  index: 0,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_circle_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Account & Security',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'AUTHENTICATED',
                              style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ListenableBuilder(
                        listenable: AuthService().profileNotifier,
                        builder: (context, _) {
                          final auth = AuthService();
                          final user = auth.currentUser;
                          final email = user?.email ?? auth.email;
                          final name = auth.displayName;
                          final phone = auth.phoneNumber;

                          return Column(
                            children: [
                              InkWell(
                                onTap: _openEditProfile,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const UserAvatar(radius: 28, showEditBadge: true),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              email,
                                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (phone != null && phone.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Icon(Icons.phone_outlined, size: 12, color: AppColors.primary),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    phone,
                                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _openEditProfile,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.primaryOn,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.edit_rounded, size: 18),
                                      label: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: _confirmSignOut,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.absent,
                                      side: BorderSide(color: AppColors.absent.withValues(alpha: 0.5)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    ),
                                    icon: const Icon(Icons.logout_rounded, size: 18),
                                    label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // Appearance & Theme Card
                AnimatedFadeSlide.staggered(
                  index: 1,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.palette_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Appearance & Theme',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              theme.themeModeName.toUpperCase(),
                              style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select light mode, dark mode, or follow your device settings.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildThemeOption(
                            mode: ThemeMode.light,
                            label: 'Light Mode',
                            icon: Icons.light_mode_rounded,
                            isSelected: theme.themeMode == ThemeMode.light,
                          ),
                          const SizedBox(width: 10),
                          _buildThemeOption(
                            mode: ThemeMode.dark,
                            label: 'Dark Mode',
                            icon: Icons.dark_mode_rounded,
                            isSelected: theme.themeMode == ThemeMode.dark,
                          ),
                          const SizedBox(width: 10),
                          _buildThemeOption(
                            mode: ThemeMode.system,
                            label: 'System',
                            icon: Icons.brightness_auto_rounded,
                            isSelected: theme.themeMode == ThemeMode.system,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // Notifications & Alerts Card
                AnimatedFadeSlide.staggered(
                  index: 2,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active_rounded, color: AppColors.pending, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Notifications & Alerts',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: gym.settings.isPaymentDueNotificationEnabled
                                  ? AppColors.paid.withValues(alpha: 0.15)
                                  : AppColors.textMuted.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              gym.settings.isPaymentDueNotificationEnabled ? 'ACTIVE' : 'MUTED',
                              style: TextStyle(
                                color: gym.settings.isPaymentDueNotificationEnabled
                                    ? AppColors.paid
                                    : AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          // activeThumbColor: AppColors.primary,
                          title: Text(
                            'Payment Due Reminders',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            'Notify on app launch when members have overdue membership payments.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          value: gym.settings.isPaymentDueNotificationEnabled,
                          onChanged: (bool enabled) async {
                            final updated = gym.settings.copyWith(isPaymentDueNotificationEnabled: enabled);
                            await gym.updateSettings(updated);
                          },
                        ),
                      ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Icon(Icons.cloud_done_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Firebase FCM Push Ready',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await NotificationService().checkAndNotifyPendingPayments(force: true);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Checking pending dues & test notification sent!'),
                                    backgroundColor: AppColors.paid,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            child: const Text(
                              'Test Alert',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // Gym Profile Card
                AnimatedFadeSlide.staggered(
                  index: 3,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.fitness_center_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Gym Profile & Pricing',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Gym Brand Logo Preview & Quick Edit
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.surfaceBorder),
                        ),
                        child: Row(
                          children: [
                            GymLogoWidget(
                              logoPath: gym.gymLogoPath,
                              logoBase64: gym.settings.gymLogoBase64,
                              gymName: gym.settings.gymName,
                              size: 48,
                              borderColor: AppColors.primary,
                              borderWidth: 2,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gym Brand Logo',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    gym.gymLogoPath != null
                                        ? 'Active on member cards & receipts'
                                        : 'No logo set yet. Tap to upload.',
                                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _openEditProfile,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.edit_rounded, size: 16),
                              label: Text(
                                gym.gymLogoPath != null ? 'Change' : 'Upload',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Gym Name
                      Text(
                        'Gym Name',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _gymNameController,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                        decoration: const InputDecoration(hintText: 'Enter gym title'),
                      ),
                      const SizedBox(height: 16),

                      Divider(color: AppColors.surfaceBorder, height: 28),

                      // Membership Plans Monthly Pricing Header
                      Row(
                        children: [
                          Icon(Icons.payments_rounded, color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Membership Plans Pricing',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PER MONTH',
                              style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monthly charges applied to active members according to their plan tier.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 14),

                      // 1. Normal Plan
                      Text(
                        'Normal Plan (₹/mo)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _normalFeeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8, top: 12),
                            child: Text(
                              currency,
                              style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                          hintText: '1200',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 2. Plan with Personal Training
                      Text(
                        'Plan with Personal Training (₹/mo)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ptFeeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8, top: 12),
                            child: Text(
                              currency,
                              style: TextStyle(color: AppColors.secondary, fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                          ),
                          hintText: '2500',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 3. Plan with Personal Training + Diet
                      Text(
                        'Plan with Personal Training + Diet (₹/mo)',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ptDietFeeController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8, top: 12),
                            child: Text(
                              currency,
                              style: const TextStyle(
                                color: Color(0xFFFF9100),
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          hintText: '3500',
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.primaryOn,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Save Settings',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openEditProfile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text(
                            'Manage Duration Packages (1, 3, 6, 12 Mo)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // Cloud Sync / Firebase Card
                AnimatedFadeSlide.staggered(
                  index: 4,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_sync_rounded, color: AppColors.secondary, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cloud & Database',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: gym.isCloudAttached
                                  ? AppColors.paid.withValues(alpha: 0.15)
                                  : AppColors.pending.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              gym.syncError != null
                                  ? 'UPLOAD ISSUE'
                                  : gym.pendingUploadCount > 0
                                  ? 'WAITING TO UPLOAD'
                                  : gym.isCloudAttached
                                  ? 'CLOUD CONNECTED'
                                  : 'ON THIS PHONE',
                              style: TextStyle(
                                color: gym.isCloudAttached ? AppColors.paid : AppColors.pending,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        gym.currentUserId != null
                            ? 'Changes are saved on this phone and uploaded when the cloud is available. Check any waiting uploads before changing devices.'
                            : 'Data is stored locally on this device. Sign in to enable cloud sync across devices.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                      ),
                      if (gym.isCloudAttached) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: AppColors.paid, size: 16),
                            const SizedBox(width: 6),
                            Text('Cloud account connected', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 16),

                // App Tour & Resources Card
                AnimatedFadeSlide.staggered(
                  index: 5,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.help_outline_rounded, color: AppColors.secondary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'App Tour & Resources',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).push(MaterialPageRoute(builder: (_) => const IntroScreen(isReview: true)));
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: AppColors.surfaceBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          icon: Icon(Icons.auto_stories_rounded, size: 18, color: AppColors.secondary),
                          label: const Text(
                            'View App Intro & Feature Tour',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Danger Zone Card
                AnimatedFadeSlide.staggered(
                  index: 5,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.absent.withValues(alpha: 0.35), width: 1.2),
                    ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.absent, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Danger Zone',
                            style: TextStyle(color: AppColors.absent, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.absent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'DESTRUCTIVE',
                              style: TextStyle(
                                color: AppColors.absent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Operations that reset or wipe local and cloud database records. Protected by security confirmation when real data exists.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: gym.currentUserId == null ? _confirmClearAllData : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.absent,
                          side: BorderSide(color: AppColors.absent.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.absent),
                        label: const Text(
                          'Clear All Gym Data (Start Fresh)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: gym.currentUserId == null ? _confirmResetData : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: BorderSide(color: AppColors.surfaceBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.restore_rounded, size: 18, color: AppColors.pending),
                        label: const Text('Reload Sample / Demo Data', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }
}
