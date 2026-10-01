import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/attendance.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/gym_settings.dart';
import '../models/payment.dart';
import 'gym_service.dart';

class GymBackupPreview {
  final DateTime createdAt;
  final String gymName;
  final int customerCount;
  final int attendanceCount;
  final int paymentCount;
  final int billCount;
  final int expenseCount;
  final int mediaCount;

  const GymBackupPreview({
    required this.createdAt,
    required this.gymName,
    required this.customerCount,
    required this.attendanceCount,
    required this.paymentCount,
    required this.billCount,
    required this.expenseCount,
    required this.mediaCount,
  });
}

class ParsedGymBackup {
  final Map<String, dynamic> document;
  final GymBackupPreview preview;

  const ParsedGymBackup({required this.document, required this.preview});
}

class GymBackupData {
  final List<Customer> customers;
  final List<AttendanceRecord> attendance;
  final List<PaymentRecord> payments;
  final List<BillRecord> bills;
  final List<ExpenseRecord> expenses;
  final GymSettings settings;

  const GymBackupData({
    required this.customers,
    required this.attendance,
    required this.payments,
    required this.bills,
    required this.expenses,
    required this.settings,
  });
}

class GymBackupService {
  static const format = 'gym_management_backup';
  static const version = 1;
  static const assetPrefix = 'backup-asset://';

  Future<File> createBackupFile(GymService gym) async {
    final document = await createBackupDocument(gym);
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/gym_backups');
    await directory.create(recursive: true);
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final gymName = _safeFileName(gym.settings.gymName);
    final file = File('${directory.path}/${gymName}_backup_$timestamp.json');
    await file.writeAsString(jsonEncode(document), flush: true);
    return file;
  }

  Future<Map<String, dynamic>> createBackupDocument(GymService gym) async {
    final customers = gym.customers
        .map((record) => Map<String, dynamic>.from(record.toMap()))
        .toList();
    final expenses = gym.expenses
        .map((record) => Map<String, dynamic>.from(record.toMap()))
        .toList();
    final settings = Map<String, dynamic>.from(gym.settings.toMap());
    final assets = <Map<String, dynamic>>[];

    for (final customer in customers) {
      await _attachAsset(
        record: customer,
        field: 'imagePath',
        assetId: 'customer_${customer['id']}_image',
        assets: assets,
      );
    }
    for (final expense in expenses) {
      await _attachAsset(
        record: expense,
        field: 'receiptPath',
        assetId: 'expense_${expense['id']}_receipt',
        assets: assets,
      );
    }
    await _attachAsset(
      record: settings,
      field: 'gymLogoPath',
      assetId: 'gym_logo',
      assets: assets,
    );

    return {
      'format': format,
      'version': version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'customers': customers,
        'attendance': gym.attendanceRecords
            .map((record) => record.toMap())
            .toList(),
        'payments': gym.paymentRecords.map((record) => record.toMap()).toList(),
        'bills': gym.billsMap.values.map((record) => record.toMap()).toList(),
        'expenses': expenses,
        'settings': settings,
      },
      'assets': assets,
    };
  }

  ParsedGymBackup parseBackupString(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('This is not a valid backup file.');
    }
    if (decoded is! Map) {
      throw const FormatException('This is not a valid backup file.');
    }
    final document = Map<String, dynamic>.from(decoded);
    if (document['format'] != format) {
      throw const FormatException(
        'This file was not created by Gym Management backup.',
      );
    }
    if (document['version'] != version) {
      throw const FormatException(
        'This backup version is not supported by this app.',
      );
    }
    final createdAt = DateTime.tryParse(document['createdAt'] as String? ?? '');
    if (createdAt == null) {
      throw const FormatException('The backup creation date is missing.');
    }
    final data = _dataMap(document);
    final assets = _assetMaps(document);
    for (final asset in assets) {
      if ((asset['id'] as String? ?? '').isEmpty ||
          (asset['fileName'] as String? ?? '').isEmpty ||
          (asset['base64'] as String? ?? '').isEmpty) {
        throw const FormatException(
          'The backup contains a damaged media file.',
        );
      }
      try {
        base64Decode(asset['base64'] as String);
      } on FormatException {
        throw const FormatException(
          'The backup contains a damaged media file.',
        );
      }
    }
    final decodedData = _decodeData(data);
    return ParsedGymBackup(
      document: document,
      preview: GymBackupPreview(
        createdAt: createdAt.toLocal(),
        gymName: decodedData.settings.gymName,
        customerCount: decodedData.customers.length,
        attendanceCount: decodedData.attendance.length,
        paymentCount: decodedData.payments.length,
        billCount: decodedData.bills.length,
        expenseCount: decodedData.expenses.length,
        mediaCount: assets.length,
      ),
    );
  }

  Future<void> restoreBackup(GymService gym, ParsedGymBackup backup) async {
    final data = _deepCopyMap(_dataMap(backup.document));
    final assets = _assetMaps(backup.document);
    final restoredPaths = await _restoreAssets(assets);
    _replaceAssetReferences(data, restoredPaths);
    final decoded = _decodeData(data);
    await gym.replaceAllData(
      customers: decoded.customers,
      attendance: decoded.attendance,
      payments: decoded.payments,
      bills: decoded.bills,
      expenses: decoded.expenses,
      settings: decoded.settings,
    );
  }

  GymBackupData decodeBackupData(Map<String, dynamic> document) {
    return _decodeData(_dataMap(document));
  }

  Future<void> _attachAsset({
    required Map<String, dynamic> record,
    required String field,
    required String assetId,
    required List<Map<String, dynamic>> assets,
  }) async {
    final path = record[field] as String?;
    if (path == null || path.trim().isEmpty || path.startsWith('avatar:')) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      record[field] = null;
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      final fileName = _safeFileName(
        file.uri.pathSegments.isEmpty ? assetId : file.uri.pathSegments.last,
      );
      assets.add({
        'id': assetId,
        'fileName': fileName,
        'base64': base64Encode(bytes),
      });
      record[field] = '$assetPrefix$assetId';
    } on FileSystemException {
      record[field] = null;
    }
  }

  Future<Map<String, String>> _restoreAssets(
    List<Map<String, dynamic>> assets,
  ) async {
    if (assets.isEmpty) return const {};
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}/restored_media/'
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    final paths = <String, String>{};
    for (final asset in assets) {
      final id = asset['id'] as String;
      final fileName = _safeFileName(asset['fileName'] as String);
      final file = File('${directory.path}/${_safeFileName(id)}_$fileName');
      final bytes = base64Decode(asset['base64'] as String);
      await file.writeAsBytes(bytes, flush: true);
      paths[id] = file.path;
    }
    return paths;
  }

  static Map<String, dynamic> _dataMap(Map<String, dynamic> document) {
    final data = document['data'];
    if (data is! Map) {
      throw const FormatException('The backup data section is missing.');
    }
    return Map<String, dynamic>.from(data);
  }

  static List<Map<String, dynamic>> _assetMaps(Map<String, dynamic> document) {
    final assets = document['assets'];
    if (assets == null) return const [];
    if (assets is! List) {
      throw const FormatException('The backup media section is damaged.');
    }
    return assets
        .map((asset) {
          if (asset is! Map) {
            throw const FormatException('The backup media section is damaged.');
          }
          return Map<String, dynamic>.from(asset);
        })
        .toList(growable: false);
  }

  static GymBackupData _decodeData(Map<String, dynamic> data) {
    try {
      final customers = _maps(
        data,
        'customers',
      ).map(Customer.fromMap).toList(growable: false);
      final attendance = _maps(
        data,
        'attendance',
      ).map(AttendanceRecord.fromMap).toList(growable: false);
      final payments = _maps(
        data,
        'payments',
      ).map(PaymentRecord.fromMap).toList(growable: false);
      final bills = _maps(
        data,
        'bills',
      ).map(BillRecord.fromMap).toList(growable: false);
      final expenses = _maps(
        data,
        'expenses',
      ).map(ExpenseRecord.fromMap).toList(growable: false);
      final settingsMap = data['settings'];
      if (settingsMap is! Map) {
        throw const FormatException('Gym settings are missing.');
      }
      final settings = GymSettings.fromMap(
        Map<String, dynamic>.from(settingsMap),
      );
      _validateData(
        customers: customers,
        attendance: attendance,
        payments: payments,
        bills: bills,
        expenses: expenses,
      );
      return GymBackupData(
        customers: customers,
        attendance: attendance,
        payments: payments,
        bills: bills,
        expenses: expenses,
        settings: settings,
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('The backup data is damaged.');
    }
  }

  static Iterable<Map<String, dynamic>> _maps(
    Map<String, dynamic> data,
    String key,
  ) {
    final list = data[key];
    if (list is! List) {
      throw FormatException('The backup $key section is missing.');
    }
    return list.map((item) {
      if (item is! Map) {
        throw FormatException('The backup $key section is damaged.');
      }
      return Map<String, dynamic>.from(item);
    });
  }

  static void _validateData({
    required List<Customer> customers,
    required List<AttendanceRecord> attendance,
    required List<PaymentRecord> payments,
    required List<BillRecord> bills,
    required List<ExpenseRecord> expenses,
  }) {
    final customerIds = _uniqueIds(
      customers.map((record) => record.id),
      'members',
    );
    _uniqueIds(payments.map((record) => record.id), 'payments');
    _uniqueIds(bills.map((record) => record.id), 'receipts');
    _uniqueIds(expenses.map((record) => record.id), 'expenses');
    _uniqueIds(
      attendance.map((record) => '${record.customerId}_${record.dateKey}'),
      'attendance',
    );
    if (customers.any(
      (record) => record.name.trim().isEmpty || record.phone.trim().isEmpty,
    )) {
      throw const FormatException(
        'The backup contains a member without a name or phone number.',
      );
    }
    for (final record in attendance) {
      if (!customerIds.contains(record.customerId) ||
          DateTime.tryParse(record.dateKey) == null) {
        throw const FormatException(
          'The backup contains invalid attendance data.',
        );
      }
    }
    for (final record in payments) {
      if (!customerIds.contains(record.customerId)) {
        throw const FormatException(
          'The backup contains a payment for a missing member.',
        );
      }
    }
    for (final record in bills) {
      if (!customerIds.contains(record.customerId)) {
        throw const FormatException(
          'The backup contains a receipt for a missing member.',
        );
      }
    }
  }

  static Set<String> _uniqueIds(Iterable<String> values, String section) {
    final ids = <String>{};
    for (final value in values) {
      if (value.trim().isEmpty || !ids.add(value)) {
        throw FormatException(
          'The backup contains invalid or duplicate $section records.',
        );
      }
    }
    return ids;
  }

  static void _replaceAssetReferences(
    Map<String, dynamic> data,
    Map<String, String> paths,
  ) {
    Object? replace(Object? value) {
      if (value is String && value.startsWith(assetPrefix)) {
        final id = value.substring(assetPrefix.length);
        final path = paths[id];
        if (path == null) {
          throw const FormatException('A backup media file is missing.');
        }
        return path;
      }
      if (value is Map) {
        return value.map(
          (key, nested) => MapEntry(key.toString(), replace(nested)),
        );
      }
      if (value is List) return value.map(replace).toList();
      return value;
    }

    final replaced = replace(data) as Map<String, dynamic>;
    data
      ..clear()
      ..addAll(replaced);
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source)) as Map<String, dynamic>,
      );

  static String _safeFileName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return sanitized.isEmpty ? 'gym' : sanitized;
  }
}
