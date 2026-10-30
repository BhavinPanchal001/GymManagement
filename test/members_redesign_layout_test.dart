import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/customers/customers_tab.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/theme_service.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  for (final width in [360.0, 384.0, 412.0]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      for (final paidAmount in [0.0, 150.0, 600.0]) {
        testWidgets(
          'Members at $width dp and $scale text scale and $paidAmount collected',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await ThemeService().setThemeMode(ThemeMode.light);
            await gym.addCustomer(
              name: 'Alexander Robertson Patel',
              phone: '9876543210',
              joinDate: DateTime.now().subtract(const Duration(days: 14)),
              membershipStartDate: DateTime.now().subtract(
                const Duration(days: 14),
              ),
              membershipFee: 600,
              markAsPaidNow: paidAmount > 0,
              paidAmount: paidAmount,
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const CustomersTab(),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Alexander Robertson Patel'), findsOneWidget);
            expect(find.byTooltip('Add Member'), findsOneWidget);
            expect(tester.takeException(), isNull);
            final list = tester.getRect(find.byType(ListView));
            final add = tester.getRect(find.byTooltip('Add Member'));
            expect(add.bottom, lessThanOrEqualTo(list.top));
            expect(find.byTooltip('Add Member').hitTestable(), findsOneWidget);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
