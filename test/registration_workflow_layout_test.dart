import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/name_input_formatter.dart';
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

  test('names capitalise initials and preserve existing spelling', () {
    expect(capitalizeName('bhavin panchal'), 'Bhavin Panchal');
    expect(capitalizeName('my Gym'), 'My Gym');
    expect(capitalizeName('  McDonald FITNESS'), '  McDonald FITNESS');
    final value = NameInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'my gym',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(value.text, 'My Gym');
    expect(value.selection.baseOffset, 6);
  });

  testWidgets(
    'registration footer stays visible and opening date picker clears focus',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AddCustomerSheet.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final register = find.text('Register Member');
      final initialY = tester.getCenter(register).dy;
      expect(register.hitTestable(), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -450),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(register).dy, initialY);
      await tester.ensureVisible(find.text('Duration'));
      await tester.tap(find.text('Duration'));
      await tester.pumpAndSettle();
      expect(find.text('Package Duration (Combo Pricing)'), findsOneWidget);
      await tester.tap(find.text('Payment'));
      await tester.pumpAndSettle();
      expect(find.text('Registration Payment'), findsOneWidget);
      expect(register.hitTestable(), findsOneWidget);
      final phone = find.byType(TextFormField).at(1);
      await tester.ensureVisible(phone);
      await tester.tap(phone);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(phone).enabled, isTrue);
      await tester.ensureVisible(find.text('Joining Date'));
      await tester.tap(find.byIcon(Icons.calendar_today_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final editable = tester.widget<EditableText>(
        find.descendant(of: phone, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
