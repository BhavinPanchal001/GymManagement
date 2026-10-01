import 'package:csv/csv.dart';
import 'package:csv/csv_settings_autodetection.dart';
import 'package:intl/intl.dart';

import '../models/customer.dart';
import '../models/gym_settings.dart';
import '../models/member_import.dart';
import '../models/payment.dart';
import '../utils/date_utils.dart';

class MemberImportService {
  static const String csvTemplate =
      'Name,Phone,Card Number,Join Date,Plan,Duration Months,Membership Start,'
      'Membership End,Agreed Fee,Amount Paid,Payment Method,Paid Date,Address,Notes\n'
      'Ravi Patel,9876543210,101,01/10/2026,Normal,3,01/10/2026,31/12/2026,'
      '1500,500,Cash,01/10/2026,Main Road,Opening balance imported\n';

  MemberImportPreview parseCsv({
    required String csvText,
    required List<Customer> existingCustomers,
    required GymSettings settings,
    DateTime? today,
  }) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      csvSettingsDetector: FirstOccurrenceSettingsDetector(
        eols: ['\r\n', '\n'],
      ),
    ).convert(csvText.replaceFirst('\ufeff', ''));
    if (rows.isEmpty) {
      throw const FormatException('The CSV file is empty.');
    }

    final headers = <String, int>{};
    for (var i = 0; i < rows.first.length; i++) {
      final normalized = _normalizeHeader(rows.first[i].toString());
      if (normalized.isNotEmpty) headers[normalized] = i;
    }
    if (_column(headers, _nameHeaders) == null ||
        _column(headers, _phoneHeaders) == null) {
      throw const FormatException('The CSV must have Name and Phone columns.');
    }

    final effectiveToday = today ?? DateTime.now();
    final existingCards = {
      for (final customer in existingCustomers)
        if (customer.cardNumber.trim().isNotEmpty)
          customer.cardNumber.trim().toLowerCase(),
    };
    final existingPhones = {
      for (final customer in existingCustomers) _digits(customer.phone),
    };
    final importedCardCounts = <String, int>{};
    final importedPhoneCounts = <String, int>{};
    final sourceRows = <({int rowNumber, Map<String, String> values})>[];

    for (var index = 1; index < rows.length; index++) {
      final values = <String, String>{};
      for (final entry in headers.entries) {
        values[entry.key] = entry.value < rows[index].length
            ? rows[index][entry.value].toString().trim()
            : '';
      }
      if (values.values.every((value) => value.isEmpty)) continue;
      final card = _value(values, _cardHeaders).toLowerCase();
      final phone = _digits(_value(values, _phoneHeaders));
      if (card.isNotEmpty) {
        importedCardCounts[card] = (importedCardCounts[card] ?? 0) + 1;
      }
      if (phone.isNotEmpty) {
        importedPhoneCounts[phone] = (importedPhoneCounts[phone] ?? 0) + 1;
      }
      sourceRows.add((rowNumber: index + 1, values: values));
    }

    final previewRows = sourceRows
        .map((source) {
          final values = source.values;
          final errors = <String>[];
          final warnings = <String>[];
          final name = _value(values, _nameHeaders).trim();
          final phone = _digits(_value(values, _phoneHeaders));
          final card = _value(values, _cardHeaders).trim();

          if (name.isEmpty) errors.add('Name is required.');
          if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
            errors.add('Phone must contain exactly 10 digits.');
          }
          final cardKey = card.toLowerCase();
          if (cardKey.isNotEmpty && existingCards.contains(cardKey)) {
            errors.add('Card number is already used by an existing member.');
          }
          if (cardKey.isNotEmpty && (importedCardCounts[cardKey] ?? 0) > 1) {
            errors.add('Card number is repeated in this CSV.');
          }
          if (phone.isNotEmpty && existingPhones.contains(phone)) {
            warnings.add('Phone number is also used by an existing member.');
          }
          if (phone.isNotEmpty && (importedPhoneCounts[phone] ?? 0) > 1) {
            warnings.add('Phone number is repeated in this CSV.');
          }

          final joinDate =
              _parseDate(
                _value(values, _joinDateHeaders),
                'Join Date',
                errors,
              ) ??
              DateTime(
                effectiveToday.year,
                effectiveToday.month,
                effectiveToday.day,
              );
          final rawPlan = _value(values, _planHeaders);
          final planType = normalizePlanType(rawPlan);
          if (planType.isEmpty) {
            errors.add('Plan must be Normal, Personal Training, or PT + Diet.');
          }
          final duration = _parseInt(
            _value(values, _durationHeaders),
            defaultValue: 1,
          );
          if (duration <= 0) errors.add('Duration must be at least 1 month.');
          final startDate =
              _parseDate(
                _value(values, _startDateHeaders),
                'Membership Start',
                errors,
              ) ??
              joinDate;
          final endDate =
              _parseDate(
                _value(values, _endDateHeaders),
                'Membership End',
                errors,
              ) ??
              GymDateUtils.computeAnniversaryEndDate(startDate, duration);
          if (endDate.isBefore(startDate)) {
            errors.add('Membership End cannot be before Membership Start.');
          }

          final defaultFee = planType.isEmpty
              ? 0.0
              : settings.getPriceForDuration(planType, duration);
          final fee = _parseMoney(
            _value(values, _feeHeaders),
            defaultValue: defaultFee,
            fieldName: 'Agreed Fee',
            errors: errors,
          );
          final amountPaid = _parseMoney(
            _value(values, _amountPaidHeaders),
            defaultValue: 0,
            fieldName: 'Amount Paid',
            errors: errors,
          );
          if (fee <= 0) errors.add('Agreed Fee must be greater than zero.');
          if (amountPaid < 0) errors.add('Amount Paid cannot be negative.');
          if (amountPaid > fee + 0.005) {
            errors.add('Amount Paid cannot be more than Agreed Fee.');
          }
          final paymentMethod = _parsePaymentMethod(
            _value(values, _paymentMethodHeaders),
            errors,
          );
          var paidAt = _parseDate(
            _value(values, _paidDateHeaders),
            'Paid Date',
            errors,
          );
          if (amountPaid > 0 && paidAt == null) {
            paidAt = startDate;
            warnings.add('Paid Date was empty; Membership Start will be used.');
          }
          final todayDate = DateTime(
            effectiveToday.year,
            effectiveToday.month,
            effectiveToday.day,
          );
          if (amountPaid > 0 && paidAt != null && paidAt.isAfter(todayDate)) {
            errors.add('Paid Date cannot be in the future.');
          }

          MemberImportData? data;
          if (errors.isEmpty) {
            data = MemberImportData(
              rowNumber: source.rowNumber,
              name: name,
              phone: phone,
              cardNumber: card,
              joinDate: joinDate,
              planType: planType,
              durationMonths: duration,
              membershipStartDate: startDate,
              membershipEndDate: endDate,
              membershipFee: fee,
              amountPaid: amountPaid,
              paymentMethod: paymentMethod,
              paidAt: paidAt,
              address: _value(values, _addressHeaders),
              notes: _value(values, _notesHeaders),
            );
          }
          return MemberImportRow(
            rowNumber: source.rowNumber,
            data: data,
            displayName: name,
            displayPhone: phone,
            displayCardNumber: card,
            errors: errors,
            warnings: warnings,
          );
        })
        .toList(growable: false);

    if (previewRows.isEmpty) {
      throw const FormatException('The CSV does not contain any member rows.');
    }
    return MemberImportPreview(previewRows);
  }

  static String _normalizeHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static int? _column(Map<String, int> headers, List<String> aliases) {
    for (final alias in aliases) {
      final column = headers[alias];
      if (column != null) return column;
    }
    return null;
  }

  static String _value(Map<String, String> values, List<String> aliases) {
    for (final alias in aliases) {
      final value = values[alias];
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  static int _parseInt(String value, {required int defaultValue}) {
    if (value.trim().isEmpty) return defaultValue;
    return int.tryParse(value.trim()) ?? -1;
  }

  static double _parseMoney(
    String value, {
    required double defaultValue,
    required String fieldName,
    required List<String> errors,
  }) {
    if (value.trim().isEmpty) return defaultValue;
    final cleaned = value.replaceAll(RegExp(r'[^0-9.\-]'), '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite) {
      errors.add('$fieldName is not a valid amount.');
      return 0;
    }
    return parsed;
  }

  static DateTime? _parseDate(
    String value,
    String fieldName,
    List<String> errors,
  ) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final direct = DateTime.tryParse(trimmed);
    if (direct != null) {
      return DateTime(direct.year, direct.month, direct.day);
    }
    for (final format in const ['dd/MM/yyyy', 'dd-MM-yyyy', 'MM/dd/yyyy']) {
      try {
        final parsed = DateFormat(format).parseStrict(trimmed);
        return DateTime(parsed.year, parsed.month, parsed.day);
      } catch (_) {}
    }
    errors.add('$fieldName must use DD/MM/YYYY or YYYY-MM-DD.');
    return null;
  }

  static PaymentMethod _parsePaymentMethod(String value, List<String> errors) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return PaymentMethod.cash;
    const supported = {
      'cash',
      'gpay',
      'google pay',
      'phonepe',
      'paytm',
      'upi',
      'card',
      'netbanking',
      'net banking',
    };
    if (!supported.contains(normalized)) {
      errors.add(
        'Payment Method must be Cash, GPay, PhonePe, Paytm, UPI, Card, or Net Banking.',
      );
      return PaymentMethod.cash;
    }
    return PaymentMethod.fromString(normalized);
  }

  static const _nameHeaders = [
    'name',
    'membername',
    'customername',
    'fullname',
  ];
  static const _phoneHeaders = [
    'phone',
    'phonenumber',
    'mobile',
    'mobilenumber',
    'contact',
  ];
  static const _cardHeaders = [
    'card',
    'cardnumber',
    'memberid',
    'membershipnumber',
  ];
  static const _joinDateHeaders = ['joindate', 'joiningdate', 'joinedon'];
  static const _planHeaders = ['plan', 'plantype', 'membershipplan'];
  static const _durationHeaders = [
    'duration',
    'durationmonths',
    'months',
    'membershipmonths',
  ];
  static const _startDateHeaders = [
    'membershipstart',
    'startdate',
    'validfrom',
  ];
  static const _endDateHeaders = [
    'membershipend',
    'enddate',
    'validto',
    'expirydate',
  ];
  static const _feeHeaders = ['agreedfee', 'membershipfee', 'totalfee', 'fee'];
  static const _amountPaidHeaders = ['amountpaid', 'paidamount', 'paid'];
  static const _paymentMethodHeaders = ['paymentmethod', 'method'];
  static const _paidDateHeaders = ['paiddate', 'paymentdate', 'paidat'];
  static const _addressHeaders = ['address'];
  static const _notesHeaders = ['notes', 'note'];
}
