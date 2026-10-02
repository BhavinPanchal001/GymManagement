import 'dart:async';

import 'package:flutter/material.dart';
import '../models/app_subscription.dart';
import '../services/gym_service.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'customers/customers_tab.dart';
import 'attendance/daily_attendance_tab.dart';
import 'billing/billing_tab.dart';
import 'settings/settings_tab.dart';
import 'subscription/subscription_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _billingSection = 0;
  Timer? _entitlementTimer;
  final List<({int tabIndex, int billingSection})> _navigationHistory = [];

  void _selectDestination(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _rememberCurrentLocation();
      _currentIndex = index;
    });
  }

  void _selectBillingSection(int section) {
    if (section == _billingSection) return;
    setState(() {
      _rememberCurrentLocation();
      _billingSection = section;
    });
  }

  void _rememberCurrentLocation() {
    // These views share one route, so Navigator cannot remember them for us.
    _navigationHistory.add((
      tabIndex: _currentIndex,
      billingSection: _billingSection,
    ));
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop || _navigationHistory.isEmpty) return;
    setState(() {
      final previous = _navigationHistory.removeLast();
      _currentIndex = previous.tabIndex;
      _billingSection = previous.billingSection;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GymService().addListener(_scheduleEntitlementCheck);
    _scheduleEntitlementCheck();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().checkAndNotifyPendingPayments();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService().checkAndNotifyPendingPayments();
      // Re-evaluate the paywall — the trial/plan may have expired in background.
      setState(() {});
      _scheduleEntitlementCheck();
    }
  }

  @override
  void dispose() {
    _entitlementTimer?.cancel();
    GymService().removeListener(_scheduleEntitlementCheck);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Rebuilds when the current trial or paid plan actually expires so the
  /// paywall engages even while the app stays open. Called on every
  /// GymService notification to keep the timer aligned with new settings.
  void _scheduleEntitlementCheck() {
    _entitlementTimer?.cancel();
    _entitlementTimer = null;
    if (!mounted || kAppRazorpayKeyId.trim().isEmpty) return;
    final boundary = GymService().settings.subscriptionExpiryBoundary;
    if (boundary == null) return;
    final delay = boundary.difference(DateTime.now());
    _entitlementTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleEntitlementCheck();
      },
    );
  }

  List<Widget> get _tabs => [
    const CustomersTab(),
    const DailyAttendanceTab(),
    BillingTab(
      sectionIndex: _billingSection,
      onSectionSelected: _selectBillingSection,
    ),
    const SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _navigationHistory.isEmpty,
      onPopInvokedWithResult: _onPopInvoked,
      child: ListenableBuilder(
        listenable: Listenable.merge([GymService(), ThemeService()]),
        builder: (context, _) {
          final gym = GymService();
          final pendingDuesCount = gym.getAllPendingDues().length;

          // Paywall: trial ended without a paid subscription. Only enforced
          // once publisher billing is configured — an empty key would lock
          // owners out with no way to pay.
          if (kAppRazorpayKeyId.trim().isNotEmpty && gym.subscriptionRequired) {
            return const SubscriptionScreen();
          }

          return Scaffold(
            body: Column(
              children: [
                if (gym.currentUserId != null &&
                    (gym.pendingUploadCount > 0 ||
                        gym.syncError != null ||
                        !gym.isCloudAttached))
                  SafeArea(
                    bottom: false,
                    child: Material(
                      color: AppColors.pending.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_upload_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                gym.syncError ??
                                    'Saved on this phone. Waiting to upload changes.',
                              ),
                            ),
                            TextButton(
                              onPressed: gym.retryCloudSync,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (gym.settings.isInTrialPeriod &&
                    !gym.settings.hasActiveSubscription)
                  SafeArea(
                    bottom: false,
                    child: Material(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      child: InkWell(
                        onTap: () => SubscriptionScreen.navigate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined,
                                  size: 20, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Free trial · ${gym.settings.trialDaysRemaining} day${gym.settings.trialDaysRemaining == 1 ? '' : 's'} left — tap to subscribe',
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  size: 20, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(index: _currentIndex, children: _tabs),
                ),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.surfaceBorder, width: 1),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _selectDestination,
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.primary.withValues(alpha: 0.2),
                elevation: 0,
                height: 68,
                destinations: [
                  NavigationDestination(
                    icon: Icon(
                      Icons.groups_outlined,
                      color: AppColors.textSecondary,
                    ),
                    selectedIcon: Icon(
                      Icons.groups_rounded,
                      color: AppColors.primary,
                    ),
                    label: 'Members',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.calendar_today_outlined,
                      color: AppColors.textSecondary,
                    ),
                    selectedIcon: Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.primary,
                    ),
                    label: 'Attendance',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: pendingDuesCount > 0,
                      label: Text(
                        '$pendingDuesCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: AppColors.pending,
                      child: Icon(
                        Icons.payments_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: pendingDuesCount > 0,
                      label: Text(
                        '$pendingDuesCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: AppColors.pending,
                      child: Icon(
                        Icons.payments_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    label: 'Payments',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.settings_outlined,
                      color: AppColors.textSecondary,
                    ),
                    selectedIcon: Icon(
                      Icons.settings_rounded,
                      color: AppColors.primary,
                    ),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
