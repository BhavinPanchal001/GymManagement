import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/customers/add_customer_sheet.dart';
import 'package:gym/services/gym_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
  });

  tearDown(() => gym.detachUser());

  test(
    'card and phone lookups normalize input and support exclusions',
    () async {
      final member = await gym.addCustomer(
        name: 'Existing Member',
        phone: '+91 98765-43210',
        cardNumber: 'VIP-01',
      );

      expect(gym.getCustomerByCardNumber(' vip-01 ')?.id, member.id);
      expect(
        gym.getCustomerByCardNumber('VIP-01', excludeCustomerId: member.id),
        isNull,
      );
      expect(gym.getCustomersByPhone('09876543210').single.id, member.id);
      expect(gym.getCustomersByPhone('98765 43210').single.id, member.id);
      expect(
        gym.getCustomersByPhone(member.phone, excludeCustomerId: member.id),
        isEmpty,
      );
    },
  );

  test('add and update reject duplicate card numbers', () async {
    final first = await gym.addCustomer(
      name: 'First Member',
      phone: '9000000001',
      cardNumber: 'CARD-7',
    );
    final second = await gym.addCustomer(
      name: 'Second Member',
      phone: '9000000002',
      cardNumber: 'CARD-8',
    );

    await expectLater(
      gym.addCustomer(
        name: 'Duplicate Member',
        phone: '9000000003',
        cardNumber: ' card-7 ',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Card #card-7 is already assigned to First Member',
        ),
      ),
    );

    await gym.updateCustomer(second.copyWith(cardNumber: ' CARD-8 '));
    expect(gym.getCustomerById(second.id)?.cardNumber, 'CARD-8');

    await expectLater(
      gym.updateCustomer(second.copyWith(cardNumber: first.cardNumber)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Card #CARD-7 is already assigned to First Member',
        ),
      ),
    );
    expect(gym.getCustomerById(second.id)?.cardNumber, 'CARD-8');
  });

  test('next card number follows the highest numeric allocation', () async {
    await gym.addCustomer(
      name: 'Numeric Member',
      phone: '9000000010',
      cardNumber: '105',
    );
    await gym.addCustomer(
      name: 'Tagged Member',
      phone: '9000000011',
      cardNumber: 'VIP-999',
    );

    expect(gym.getNextCardNumber(), '106');

    final automatic = await gym.addCustomer(
      name: 'Automatic Member',
      phone: '9000000012',
    );
    expect(automatic.cardNumber, '106');
    expect(gym.getNextCardNumber(), '107');
  });

  testWidgets('duplicate card blocks registration with an inline error', (
    tester,
  ) async {
    await gym.addCustomer(
      name: 'Existing Member',
      phone: '9000000020',
      cardNumber: 'VIP-01',
    );
    await _openAddCustomerSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'),
      'New Member',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. 9876543210'),
      '9000000021',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. 778'),
      ' vip-01 ',
    );
    await _submitRegistration(tester);

    expect(
      find.text('Card #vip-01 is already assigned to Existing Member'),
      findsOneWidget,
    );
    expect(gym.customers, hasLength(1));
  });

  testWidgets('duplicate phone warning can cancel or continue registration', (
    tester,
  ) async {
    await gym.addCustomer(
      name: 'Existing Member',
      phone: '+91 98765-43210',
      cardNumber: '101',
    );
    await _openAddCustomerSheet(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. Rahul Sharma'),
      'Family Member',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'e.g. 9876543210'),
      '9876543210',
    );
    await _submitRegistration(tester);

    expect(find.text('Duplicate Phone Number'), findsOneWidget);
    expect(
      find.text(
        'A member named Existing Member (Card #101) is already registered '
        'with this phone number. Is this a family member sharing the number?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel & Review'));
    await tester.pumpAndSettle();
    expect(gym.customers, hasLength(1));
    expect(find.text('Register Member'), findsOneWidget);

    await _submitRegistration(tester);
    await tester.tap(find.text('Yes, Add Member'));
    await tester.pumpAndSettle();

    expect(gym.customers, hasLength(2));
    expect(
      gym.customers.where((customer) => customer.name == 'Family Member'),
      hasLength(1),
    );
  });
}

Future<void> _openAddCustomerSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => AddCustomerSheet.show(context),
            child: const Text('Open Sheet'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();
}

Future<void> _submitRegistration(WidgetTester tester) async {
  final submit = find.text('Register Member');
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}
