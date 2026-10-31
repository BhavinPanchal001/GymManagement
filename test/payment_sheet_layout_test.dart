import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/theme_service.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:gym/widgets/mark_payment_dialog.dart';

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
    await ThemeService().setThemeMode(ThemeMode.light);
  });
  tearDown(() => gym.detachUser());

  for (final size in [const Size(320, 568), const Size(360, 800)]) {
    for (final scale in [1.0, 1.3, 1.5]) {
      for (final update in [false, true]) {
        testWidgets(
          '${update ? 'Update' : 'Add'} payment footer stays fixed at $size and $scale text',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetViewInsets);
            final start = DateTime.now().subtract(const Duration(days: 3));
            final member = await gym.addCustomer(
              name: 'Test Member',
              phone: '9876543210',
              joinDate: start,
              membershipStartDate: start,
              membershipFee: 600,
              markAsPaidNow: update,
              paidAmount: update ? 300 : 0,
            );
            final payment = gym.getCustomerPaymentHistory(member.id).single;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => MarkPaymentDialog.show(
                        context,
                        customer: member,
                        monthYear: payment.monthYear,
                        currentRecord: payment,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            final form = find.byKey(const ValueKey('payment-form-scroll'));
            final footer = find.byKey(const ValueKey('payment-sheet-footer'));
            final submit = find.byKey(const ValueKey('payment-submit-button'));
            final reminder = find.byKey(
              const ValueKey('payment-reminder-button'),
            );
            expect(submit.hitTestable(), findsOneWidget);
            expect(reminder, update ? findsNothing : findsOneWidget);
            if (!update) {
              expect(reminder.hitTestable(), findsOneWidget);
            }
            if (scale == 1) {
              expect(tester.getSize(submit).height, lessThanOrEqualTo(44));
              if (!update) {
                expect(tester.getSize(reminder).height, lessThanOrEqualTo(40));
              }
            }
            final fixedTop = tester.getRect(footer).top;
            await tester.drag(form, const Offset(0, -450));
            await tester.pumpAndSettle();
            expect(tester.getRect(footer).top, closeTo(fixedTop, 0.1));
            final reference = find.byKey(
              const ValueKey('payment-reference-field'),
            );
            final remarks = find.byKey(const ValueKey('payment-remarks-field'));
            await tester.ensureVisible(reference);
            expect(tester.getSize(reference).height, greaterThanOrEqualTo(48));
            await tester.ensureVisible(remarks);
            expect(tester.getSize(remarks).height, greaterThanOrEqualTo(64));
            await tester.enterText(remarks, 'Keep this payment note');
            tester.view.viewInsets = const FakeViewPadding(bottom: 240);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(footer).bottom,
              lessThanOrEqualTo(size.height - 240 + 0.1),
            );
            expect(
              tester.getRect(form).bottom,
              lessThanOrEqualTo(tester.getRect(footer).top),
            );
            expect(submit.hitTestable(), findsOneWidget);
            if (!update) {
              expect(reminder.hitTestable(), findsOneWidget);
            }
            final keyboardTop = tester.getRect(footer).top;
            await tester.drag(form, const Offset(0, 180));
            await tester.pumpAndSettle();
            expect(tester.getRect(footer).top, closeTo(keyboardTop, 0.1));
            expect(
              tester.widget<TextField>(remarks).controller!.text,
              'Keep this payment note',
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
