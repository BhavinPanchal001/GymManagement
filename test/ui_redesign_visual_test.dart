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

  for (final entry in <String, Widget>{
    'members': const CustomersTab(),
    'attendance': const DailyAttendanceTab(),
    'payments': const BillingTab(),
    'settings': const SettingsTab(),
    'sign-in': const AuthScreen(),
  }.entries) {
    testWidgets('${entry.key} light theme at 150% text', (tester) async {
      tester.view.physicalSize = const Size(384, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await ThemeService().setThemeMode(ThemeMode.light);
      await gym.addCustomer(name: 'Aarav Patel', phone: '9876543210');
      await gym.addCustomer(name: 'Meera Shah', phone: '9876543211');
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.5),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: RepaintBoundary(key: boundaryKey, child: entry.value),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ui-review/${entry.key}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
