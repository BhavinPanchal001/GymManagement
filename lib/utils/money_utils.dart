import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class MoneyUtils {
  static double round(double amount) {
    if (!amount.isFinite) return 0;
    return (amount * 100).round() / 100;
  }

  static String formatForInput(double amount) {
    final rounded = round(amount);
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(2);
  }

  static String formatDisplay(double amount, {String symbol = '₹'}) {
    final rounded = round(amount);
    final formatter = NumberFormat(
      rounded == rounded.truncateToDouble() ? '#,##,###' : '#,##,###.00',
    );
    return '$symbol${formatter.format(rounded)}';
  }

  static double? tryParseAmount(String? text) {
    if (text == null) return null;
    final normalized = text.trim().replaceAll(',', '.');
    if (!RegExp(r'^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$').hasMatch(normalized)) {
      return null;
    }
    final amount = double.tryParse(normalized);
    if (amount == null || !amount.isFinite) return null;
    return round(amount);
  }

  static double parseAmount(String? text, {double defaultValue = 0.0}) {
    return tryParseAmount(text) ?? defaultValue;
  }
}

class MoneyInputFormatter extends TextInputFormatter {
  static final RegExp _validInput = RegExp(
    r'^(?:\d*(?:\.\d{0,2})?|\.\d{0,2})$',
  );

  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final normalized = newValue.text.replaceAll(',', '.');
    if (!_validInput.hasMatch(normalized)) return oldValue;
    return newValue.copyWith(text: normalized);
  }
}
