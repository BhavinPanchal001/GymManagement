import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/models/expense.dart';
import 'package:gym/models/payment.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/utils/money_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MoneyUtils', () {
    test('formats input values without dropping paise', () {
      expect(MoneyUtils.formatForInput(600), '600');
      expect(MoneyUtils.formatForInput(600.5), '600.50');
      expect(MoneyUtils.formatForInput(600.75), '600.75');
      expect(MoneyUtils.formatDisplay(1234.5), '₹1,234.50');
    });

    test('strictly parses dot and comma decimals', () {
      expect(MoneyUtils.tryParseAmount('750.25'), 750.25);
      expect(MoneyUtils.tryParseAmount('750,25'), 750.25);
      expect(MoneyUtils.tryParseAmount('.50'), 0.5);
      expect(MoneyUtils.tryParseAmount('12.34.56'), isNull);
      expect(MoneyUtils.tryParseAmount('amount 750.25'), isNull);
      expect(MoneyUtils.tryParseAmount('-50'), isNull);
      expect(MoneyUtils.tryParseAmount('12.345'), isNull);
      expect(MoneyUtils.parseAmount('invalid', defaultValue: 42), 42);
    });

    test('input formatter normalizes comma and clears invalid input', () {
      const formatter = MoneyInputFormatter();
      const oldValue = TextEditingValue(
        text: '12.34',
        selection: TextSelection.collapsed(offset: 5),
      );

      final commaValue = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '12,34',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(commaValue.text, '12.34');

      expect(
        formatter
            .formatEditUpdate(
              oldValue,
              const TextEditingValue(text: '12.345'),
            )
            .text,
        isEmpty,
      );
      expect(
        formatter
            .formatEditUpdate(
              oldValue,
              const TextEditingValue(text: '12.34.56'),
            )
            .text,
        isEmpty,
      );
      expect(
        formatter
            .formatEditUpdate(
              oldValue,
              const TextEditingValue(text: '-50'),
            )
            .text,
        '-50',
      );
    });
  });

  group('financial summaries', () {
    final gym = GymService();

    setUp(() async {
      await gym.detachUser();
      SharedPreferences.setMockInitialValues({});
      await gym.init();
      await gym.clearAllGymData();
    });

    tearDown(() async => gym.detachUser());

    test('rounds payment and expense aggregates to two decimals', () async {
      for (final entry in [
        (name: 'One', amount: 0.1),
        (name: 'Two', amount: 0.2),
      ]) {
        final customer = await gym.addCustomer(
          name: entry.name,
          phone: entry.name == 'One' ? '9000000001' : '9000000002',
          joinDate: DateTime(2026, 10, 1),
          markAsPaidNow: false,
        );
        await gym.markPaymentAsPaid(
          customerId: customer.id,
          monthYear: '2026-10',
          method: PaymentMethod.cash,
          amount: entry.amount,
          totalDue: 1,
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 31),
          paidAt: DateTime(2026, 10, 1),
        );
        await gym.addExpense(
          title: entry.name,
          amount: entry.amount,
          category: ExpenseCategory.misc,
          date: DateTime(2026, 10, 1),
        );
      }

      final financial = gym.getMonthlyFinancialSummary('2026-10');
      final balance = gym.getBalanceSheetSummary('2026-10');

      expect(financial['totalCollected'], 0.3);
      expect(gym.getTotalExpenseAmount('2026-10'), 0.3);
      expect(balance['netProfit'], 0);
    });
  });
}
