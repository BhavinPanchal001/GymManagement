import 'package:flutter/material.dart';
import '../services/gym_service.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import 'customers/customers_tab.dart';
import 'attendance/daily_attendance_tab.dart';
import 'billing/billing_tab.dart';
import 'settings/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().checkAndNotifyPendingPayments();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService().checkAndNotifyPendingPayments();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  final List<Widget> _tabs = const [
    CustomersTab(),
    DailyAttendanceTab(),
    BillingTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([GymService(), ThemeService()]),
      builder: (context, _) {
        final gym = GymService();
        final currentMonth = GymDateUtils.toMonthKey(DateTime.now());
        final summary = gym.getMonthlyFinancialSummary(currentMonth);
        final pendingDuesCount = summary['pendingCount'] as int? ?? 0;

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _tabs,
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1)),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.primary.withValues(alpha: 0.2),
              elevation: 0,
              height: 68,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined, color: AppColors.textSecondary),
                  selectedIcon: Icon(Icons.groups_rounded, color: AppColors.primary),
                  label: 'Members',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary),
                  selectedIcon: Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                  label: 'Attendance',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: pendingDuesCount > 0,
                    label: Text(
                      '$pendingDuesCount',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.pending,
                    child: Icon(Icons.payments_outlined, color: AppColors.textSecondary),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: pendingDuesCount > 0,
                    label: Text(
                      '$pendingDuesCount',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.pending,
                    child: Icon(Icons.payments_rounded, color: AppColors.primary),
                  ),
                  label: 'Payments',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                  selectedIcon: Icon(Icons.settings_rounded, color: AppColors.primary),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
