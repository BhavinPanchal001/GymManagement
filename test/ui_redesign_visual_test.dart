import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/screens/customers/customers_tab.dart';
import 'package:gym/screens/attendance/daily_attendance_tab.dart';
import 'package:gym/screens/billing/billing_tab.dart';
import 'package:gym/screens/settings/settings_tab.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/models/attendance.dart';
import 'package:gym/utils/date_utils.dart';
import 'package:gym/services/theme_service.dart';
import 'package:gym/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  setUpAll(() async {
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/material_fonts').existsSync() &&
        directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Bold']) {
      final bytes = await File(
        '${directory.path}/material_fonts/Roboto-$weight.ttf',
      ).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    final iconBytes = await File(
      '${directory.path}/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    icons.addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
  });
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  testWidgets('compact attendance controls retain labelled actions', (
    tester,
  ) async {
    final member = await gym.addCustomer(
      name: 'Test Member',
      phone: '9876543210',
    );
    await ThemeService().setThemeMode(ThemeMode.light);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const DailyAttendanceTab()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Present'));
    await tester.pumpAndSettle();
    final dateKey = GymDateUtils.toDateKey(DateTime.now());
    expect(
      gym.getAttendanceStatus(member.id, dateKey),
      AttendanceStatus.present,
    );
    await tester.tap(find.byTooltip('Absent'));
    await tester.pumpAndSettle();
    expect(
      gym.getAttendanceStatus(member.id, dateKey),
      AttendanceStatus.absent,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final scale in [1.0, 1.5]) {
      for (final entry in <String, Widget>{
        'members': const CustomersTab(),
        'attendance': const DailyAttendanceTab(),
        'payments': const BillingTab(),
        'settings': const SettingsTab(),
        'sign-in': const AuthScreen(),
      }.entries) {
        testWidgets('${entry.key} ${mode.name} theme at ${scale * 100}% text', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(384, 832);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await ThemeService().setThemeMode(mode);
          await gym.addCustomer(name: 'Aarav Patel', phone: '9876543210');
          await gym.addCustomer(name: 'Meera Shah', phone: '9876543211');
          for (final name in [
            'Anash',
            'Bv',
            'Ganesh',
            'Jay',
            'Kiran',
            'Ravi',
            'Sejal',
            'Viren',
          ]) {
            await gym.addCustomer(
              name: name,
              phone: '9876543212',
              joinDate: DateTime.now().subtract(const Duration(days: 14)),
              membershipStartDate: DateTime.now().subtract(
                const Duration(days: 14),
              ),
              membershipFee: 600,
              markAsPaidNow: name != 'Kiran',
              paidAmount: name == 'Anash' ? 150 : 600,
            );
          }
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: mode == ThemeMode.dark
                  ? AppTheme.darkTheme
                  : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                  padding: const EdgeInsets.only(top: 24, bottom: 24),
                  viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundaryKey,
                child: Scaffold(
                  body: entry.value,
                  bottomNavigationBar: entry.key == 'sign-in'
                      ? null
                      : NavigationBar(
                          height: 56,
                          backgroundColor: AppColors.surface,
                          indicatorColor: AppColors.primary.withValues(
                            alpha: 0.2,
                          ),
                          selectedIndex: [
                            'members',
                            'attendance',
                            'payments',
                            'settings',
                          ].indexOf(entry.key),
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.groups_outlined),
                              label: 'Members',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.calendar_today_outlined),
                              label: 'Attendance',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.payments_outlined),
                              label: 'Payments',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.settings_outlined),
                              label: 'Settings',
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scale == 1 && ['members', 'attendance'].contains(entry.key)) {
            // A phone must show at least six identities without scrolling.
            final visibleNames =
                [
                      'Aarav Patel',
                      'Meera Shah',
                      'Anash',
                      'Bv',
                      'Ganesh',
                      'Jay',
                      'Kiran',
                      'Ravi',
                      'Sejal',
                      'Viren',
                    ]
                    .where(
                      (name) =>
                          find.text(name).hitTestable().evaluate().isNotEmpty,
                    )
                    .length;
            expect(visibleNames, greaterThanOrEqualTo(6));
            if (entry.key == 'members') {
              final card = find
                  .ancestor(
                    of: find.text('Viren'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first;
              expect(tester.getSize(card).height, lessThanOrEqualTo(84));
            }
          }
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/ui-review/dense-${entry.key}-${mode.name}-${(scale * 100).round()}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
