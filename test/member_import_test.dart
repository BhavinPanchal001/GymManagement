import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/customer.dart';
import 'package:gym/models/gym_settings.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/member_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gym = GymService();
  final importer = MemberImportService();

  setUp(() async {
    await gym.detachUser();
    SharedPreferences.setMockInitialValues({});
    await gym.init();
    await gym.clearAllGymData();
    await gym.updateSettings(const GymSettings(gymName: 'Import Test Gym'));
  });

  tearDown(() async => gym.detachUser());

  test('customer search matches name, phone, and card number', () async {
    await gym.addCustomer(
      name: 'Ravi Patel',
      phone: '9876543210',
      joinDate: DateTime(2026, 1, 1),
      cardNumber: 'GYM-204',
    );

    expect(gym.searchCustomers('ravi'), hasLength(1));
    expect(gym.searchCustomers('7654'), hasLength(1));
    expect(gym.searchCustomers('gym-204'), hasLength(1));
    expect(gym.searchCustomers('missing'), isEmpty);
    expect(gym.searchCustomers(''), hasLength(1));
  });

  test('CSV preview supports quoted commas and reports duplicates', () {
    final preview = importer.parseCsv(
      csvText:
          'Name,Phone,Card Number,Join Date,Plan,Duration Months,'
          'Membership Start,Agreed Fee,Amount Paid,Address,Notes\r\n'
          '"Patel, Ravi",9876543210,CARD-1,01/01/2026,Normal,3,'
          '01/01/2026,"1,500",500,"Main Road, Surat","Opening, balance"\r\n'
          'Second Member,9876543210,CARD-2,01/01/2026,Normal,1,'
          '01/01/2026,600,0,Other Road,\r\n'
          'Duplicate Card,9999999999,CARD-2,01/01/2026,Normal,1,'
          '01/01/2026,600,0,Other Road,\r\n'
          'Existing Card,8888888888,USED-9,01/01/2026,Normal,1,'
          '01/01/2026,600,0,Other Road,\r\n',
      existingCustomers: [
        Customer(
          id: 'existing',
          name: 'Existing',
          phone: '9876543210',
          joinDate: DateTime(2025, 1, 1),
          cardNumber: 'USED-9',
        ),
      ],
      settings: const GymSettings(),
      today: DateTime(2026, 1, 1),
    );

    expect(preview.rows, hasLength(4));
    expect(preview.rows.first.data!.name, 'Patel, Ravi');
    expect(preview.rows.first.data!.membershipFee, 1500);
    expect(preview.rows.first.data!.address, 'Main Road, Surat');
    expect(preview.rows.first.warnings, isNotEmpty);
    expect(preview.rows[1].canImport, isFalse);
    expect(preview.rows[2].canImport, isFalse);
    expect(
      preview.rows[3].errors,
      contains('Card number is already used by an existing member.'),
    );
  });

  test(
    'valid CSV rows create members, agreements, and paid receipts',
    () async {
      final preview = importer.parseCsv(
        csvText:
            'Name,Phone,Card Number,Join Date,Plan,Duration Months,'
            'Membership Start,Membership End,Agreed Fee,Amount Paid,'
            'Payment Method,Paid Date,Address,Notes\n'
            'Paid Member,9876543210,P-1,01/01/2026,Normal,3,'
            '01/01/2026,31/03/2026,1500,500,UPI,01/01/2026,Main Road,'
            'Opening balance\n'
            'Pending Member,9999999999,,02/01/2026,Personal Training,1,'
            '02/01/2026,01/02/2026,2500,0,Cash,,Second Road,\n',
        existingCustomers: gym.customers,
        settings: gym.settings,
        today: DateTime(2026, 1, 2),
      );

      expect(preview.errorCount, 0);
      final imported = await gym.importMembers(preview.importableRows);

      expect(imported, hasLength(2));
      expect(gym.customers, hasLength(2));
      expect(gym.paymentRecords, hasLength(2));
      expect(
        gym.paymentRecords.where((record) => record.amount == 500),
        hasLength(1),
      );
      expect(
        gym.paymentRecords.where((record) => record.amount == 0),
        hasLength(1),
      );
      expect(gym.billsMap, hasLength(1));
      expect(gym.searchCustomers('P-1').single.name, 'Paid Member');
      expect(
        gym.customers
            .singleWhere((customer) => customer.name == 'Pending Member')
            .cardNumber,
        isNotEmpty,
      );
    },
  );

  test('CSV rejects unsupported payment methods', () {
    final preview = importer.parseCsv(
      csvText:
          'Name,Phone,Plan,Agreed Fee,Amount Paid,Payment Method,Paid Date\n'
          'Unsupported,9876543210,Normal,600,600,Bank Transfer,01/01/2026\n',
      existingCustomers: const [],
      settings: const GymSettings(),
      today: DateTime(2026, 1, 1),
    );

    expect(
      preview.rows.single.errors,
      contains(
        'Payment Method must be Cash, GPay, PhonePe, Paytm, UPI, Card, or Net Banking.',
      ),
    );
  });

  test('CSV rejects explicit and defaulted future paid dates', () {
    final preview = importer.parseCsv(
      csvText:
          'Name,Phone,Plan,Membership Start,Agreed Fee,Amount Paid,'
          'Payment Method,Paid Date\n'
          'Explicit Future,9876543210,Normal,01/01/2026,600,600,Cash,'
          '02/01/2026\n'
          'Default Future,9999999999,Normal,02/01/2026,600,600,Cash,\n',
      existingCustomers: const [],
      settings: const GymSettings(),
      today: DateTime(2026, 1, 1),
    );

    expect(
      preview.rows[0].errors,
      contains('Paid Date cannot be in the future.'),
    );
    expect(
      preview.rows[1].errors,
      contains('Paid Date cannot be in the future.'),
    );
  });

  test('CSV keeps an empty payment method as Cash', () {
    final preview = importer.parseCsv(
      csvText:
          'Name,Phone,Plan,Agreed Fee,Amount Paid,Payment Method,Paid Date\n'
          'Cash Default,9876543210,Normal,600,600,,01/01/2026\n',
      existingCustomers: const [],
      settings: const GymSettings(),
      today: DateTime(2026, 1, 1),
    );

    expect(preview.rows.single.errors, isEmpty);
    expect(preview.rows.single.data!.paymentMethod, PaymentMethod.cash);
  });
}
