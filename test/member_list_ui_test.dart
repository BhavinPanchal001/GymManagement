import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  final captureKey = GlobalKey();
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
      '${directory.path}/material_fonts/materialicons-regular.otf',
    ).readAsBytes();
    icons.addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await gym.detachUser();
    await gym.init();
    await gym.clearAllGymData();
  });
  tearDown(() => gym.detachUser());

  Future<void> show(
    WidgetTester tester, {
    double width = 384,
    double scale = 1,
    bool dark = false,
    String name = 'Aarti',
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ThemeService().setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    await gym.addCustomer(name: name, phone: '9876543210', cardNumber: '42');
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const CustomersTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_MEMBER_UI')) return;
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('build/ui-review/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    for (final width in [360.0, 384.0, 412.0]) {
      testWidgets(
        'cards and scrollable options fit $width, 150% text, dark=$dark',
        (tester) async {
          await show(
            tester,
            width: width,
            scale: 1.5,
            dark: dark,
            name: 'Aarti Panchal With A Long Member Name',
          );
          expect(find.text('Card #42'), findsOneWidget);
          expect(find.text('0 days attended'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byTooltip('Options for Aarti Panchal With A Long Member Name'),
          );
          await tester.pumpAndSettle();
          expect(find.text('MEMBER ACTIONS'), findsOneWidget);
          expect(find.text('View details'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).last,
            const Offset(0, -1300),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('MEMBER ACTIONS'), findsNothing);
          expect(gym.customers.single.isActive, isTrue);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'member actions preview, archive confirmation and restore, dark=$dark',
      (tester) async {
        await show(tester, dark: dark);
        await capture(tester, dark ? 'members-dark' : 'members-light');
        await tester.tap(find.byTooltip('Options for Aarti'));
        await tester.pumpAndSettle();
        await capture(tester, dark ? 'options-dark' : 'options-light');
        await tester.ensureVisible(find.text('Archive member'));
        await tester.tap(find.text('Archive member'));
        await tester.pumpAndSettle();
        expect(find.text('Archive member?'), findsOneWidget);
        expect(gym.customers.single.isActive, isTrue);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(gym.customers.single.isActive, isTrue);
        await tester.tap(find.byTooltip('Options for Aarti'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Archive member'));
        await tester.tap(find.text('Archive member'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        expect(gym.customers.single.isActive, isFalse);
        await tester.tap(find.byTooltip('Options for Aarti'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Restore member'));
        await tester.tap(find.text('Restore member'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        expect(gym.customers.single.isActive, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
