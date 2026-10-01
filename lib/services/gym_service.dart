import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer.dart';
import '../models/attendance.dart';
import '../models/payment.dart';
import '../models/bill.dart';
import '../models/expense.dart';
import '../models/gym_settings.dart';
import '../utils/date_utils.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'cloud_sync_queue.dart';
import 'dart:async';

enum MemberLifecycleStage {
  paid,
  newMember,
  notEnrolled,
  due;

  String get label {
    switch (this) {
      case MemberLifecycleStage.paid:
        return 'Paid';
      case MemberLifecycleStage.newMember:
        return 'New Member';
      case MemberLifecycleStage.notEnrolled:
        return 'Not Enrolled';
      case MemberLifecycleStage.due:
        return 'Payment Due';
    }
  }

  bool get isPaid => this == MemberLifecycleStage.paid;
  bool get isNew => this == MemberLifecycleStage.newMember;
  bool get isNotEnrolled => this == MemberLifecycleStage.notEnrolled;
  bool get isDue => this == MemberLifecycleStage.due;
}

class MonthCardData {
  final int month;
  final String monthName;
  final String monthKey; // e.g. "2026-01"
  final bool isPaid;
  final double amount;
  final PaymentMethod? method;
  final DateTime? paidAt;
  final int presentDays;
  final int absentDays;
  final int totalRecorded;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCoveredInPackage;

  const MonthCardData({
    required this.month,
    required this.monthName,
    required this.monthKey,
    required this.isPaid,
    required this.amount,
    this.method,
    this.paidAt,
    required this.presentDays,
    required this.absentDays,
    required this.totalRecorded,
    this.startDate,
    this.endDate,
    this.isCoveredInPackage = false,
  });

  String? get formattedDateRange {
    if (!isPaid || startDate == null || endDate == null) return null;
    return GymDateUtils.formatCardDateRange(startDate!, endDate!);
  }
}

class _PendingIndex {
  final Map<String, List<PaymentRecord>> payments = {};
  final Map<String, Map<String, List<String>>> unpaid = {};
  final Map<String, List<(String, String)>> _coverage = {};
  DateTime earliest = DateTime.now();
  DateTime latest = DateTime.now();

  _PendingIndex(
    List<Customer> customers,
    Iterable<PaymentRecord> records,
    Iterable<AttendanceRecord> attendance,
  ) {
    for (final customer in customers) {
      if (customer.joinDate.isBefore(earliest)) earliest = customer.joinDate;
    }
    for (final payment in records) {
      final start = payment.effectiveStartDate;
      final end = payment.effectiveEndDate;
      if (start.isBefore(earliest)) earliest = start;
      if (payment.balanceDue > 0 && start.isAfter(latest)) latest = start;
      if (!payment.isPaid) continue;
      (payments[payment.customerId] ??= []).add(payment);
      if (!end.isBefore(start)) {
        (_coverage[payment.customerId] ??= []).add((
          GymDateUtils.toDateKey(start),
          GymDateUtils.toDateKey(end),
        ));
      }
    }
    for (final list in payments.values) {
      list.sort((a, b) => b.effectiveStartDate.compareTo(a.effectiveStartDate));
    }
    for (final entry in _coverage.entries) {
      entry.value.sort((a, b) => a.$1.compareTo(b.$1));
      final merged = <(String, String)>[];
      for (final range in entry.value) {
        if (merged.isNotEmpty && range.$1.compareTo(merged.last.$2) <= 0) {
          final previous = merged.removeLast();
          merged.add((
            previous.$1,
            range.$2.compareTo(previous.$2) > 0 ? range.$2 : previous.$2,
          ));
        } else {
          merged.add(range);
        }
      }
      _coverage[entry.key] = merged;
    }
    var earliestKey = GymDateUtils.toDateKey(earliest);
    for (final record in attendance) {
      if (record.dateKey.compareTo(earliestKey) < 0) {
        final date = DateTime.tryParse(record.dateKey);
        if (date != null && date.isBefore(earliest)) {
          earliest = date;
          earliestKey = GymDateUtils.toDateKey(date);
        }
      }
      if (record.status != AttendanceStatus.present ||
          record.dateKey.length < 7 ||
          covers(record.customerId, record.dateKey)) {
        continue;
      }
      final months = unpaid[record.customerId] ??= {};
      (months[record.dateKey.substring(0, 7)] ??= []).add(record.dateKey);
    }
  }

  bool covers(String customerId, String dateKey) {
    final ranges = _coverage[customerId];
    if (ranges == null) return false;
    var low = 0;
    var high = ranges.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final range = ranges[middle];
      if (dateKey.compareTo(range.$1) < 0) {
        high = middle - 1;
      } else if (dateKey.compareTo(range.$2) > 0) {
        low = middle + 1;
      } else {
        return true;
      }
    }
    return false;
  }
}

class GymService extends ChangeNotifier {
  static final GymService _instance = GymService._internal();
  factory GymService() => _instance;
  GymService._internal();

  List<Customer> _customers = [];
  List<ExpenseRecord> _expenses = [];
  Map<String, AttendanceRecord> _attendanceMap = {}; // key: "${customerId}_${dateKey}"
  Map<String, PaymentRecord> _paymentMap = {}; // key: payment record id
  Map<String, BillRecord> _billsMap = {}; // key: bill record id
  GymSettings _settings = const GymSettings();
  String? _currentUserId;
  bool _isInitialized = false;
  bool _isCloudAttached = false;
  bool _isMigratedToCloud = false;
  bool _suppressCloudUpdates = false; // Prevents re-entrant updates during local writes
  CloudSyncQueue? _syncQueue;
  String? _cloudReadError;
  String? _financialCacheError;
  Future<void>? _financialTail;
  Future<void>? _financialCacheTail;
  int _operationSequence = 0;
  _PendingIndex? _pendingIndex;
  final Map<String, List<MemberPendingSummary>> _pendingByRange = {};
  String? _pendingCacheDay;

  _PendingIndex get _duesIndex {
    final day = GymDateUtils.toDateKey(DateTime.now());
    if (_pendingCacheDay != day) {
      _pendingIndex = null;
      _pendingByRange.clear();
      _pendingCacheDay = day;
    }
    return _pendingIndex ??= _PendingIndex(
      _customers,
      _paymentMap.values,
      _attendanceMap.values,
    );
  }

  @override
  void notifyListeners() {
    _pendingIndex = null;
    _pendingByRange.clear();
    super.notifyListeners();
  }

  void _notifySyncStatus() => super.notifyListeners();

  int get pendingUploadCount => _syncQueue?.pendingCount ?? 0;
  String? get syncError =>
      _financialCacheError ?? _cloudReadError ?? _syncQueue?.lastError;

  Future<void> _prepareSyncQueue(String userId) async {
    _syncQueue?.dispose();
    final queue = CloudSyncQueue(
      preferences: await SharedPreferences.getInstance(),
      userId: userId,
      upload: (changes) async {
        if (_currentUserId != userId) {
          throw StateError('This account is no longer connected.');
        }
        final payments = _overlay('payments', {
          for (final p in _paymentMap.values) p.id: p.toMap(),
        }).map((key, value) => MapEntry(key, PaymentRecord.fromMap(value)));
        final bills = _overlay('bills', {
          for (final b in _billsMap.values) b.id: b.toMap(),
        }).map((key, value) => MapEntry(key, BillRecord.fromMap(value)));
        await _saveFinancialSnapshot(payments, bills);
        await FirestoreService().commitChanges(userId, changes);
      },
    );
    queue.load();
    _syncQueue = queue;
    queue.addListener(_notifySyncStatus);
    // Recover changes saved to the outbox just before an interrupted local save.
    _onFirestoreData(
      customers: _customers,
      attendanceMap: _attendanceMap,
      paymentMap: _paymentMap,
      billsMap: _billsMap,
      expenses: _expenses,
      settings: _settings,
    );
  }

  Future<void> _connectCloud(String userId) async {
    try {
      await FirestoreService().attachUser(
        userId,
        callback: _onFirestoreData,
        onError: (_) {
          _cloudReadError =
              'Could not refresh cloud data. Changes stay on this phone.';
          _notifySyncStatus();
        },
      );
      _isCloudAttached = FirestoreService().isAttached;
      _cloudReadError = null;
    } catch (_) {
      _isCloudAttached = false;
      _cloudReadError =
          'Cloud connection unavailable. Changes stay on this phone.';
    }
    unawaited(_syncQueue?.flush() ?? Future.value());
  }

  Future<void> retryCloudSync() async {
    final owner = _currentUserId;
    if (owner == null) return;
    await _refreshFinancialCache();
    if (!_isCloudAttached || _cloudReadError != null) {
      await FirestoreService().detachUser();
      await _connectCloud(owner);
    }
    await _syncQueue?.flush();
    _notifySyncStatus();
  }

  Future<void> _queueChanges(List<CloudChange> changes, {
    bool autoFlush = true,
  }) async {
    if (_currentUserId == null) return; // Local exploration mode.
    final queue = _syncQueue;
    if (queue == null) {
      throw StateError('Please wait for your account to finish loading.');
    }
    final writes = <Future<void>>[];
    for (var i = 0; i < changes.length; i += 450) {
      writes.add(queue.enqueue(
        changes.sublist(i, (i + 450).clamp(0, changes.length)),
        autoFlush: autoFlush,
      ));
    }
    await Future.wait(writes);
  }

  String newPaymentOperationId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_operationSequence++}';

  Future<BillRecord> _serializeFinancialSave(
    Future<BillRecord> Function() save,
  ) {
    final result = (_financialTail ?? Future.value()).then((_) => save());
    late final Future<void> tail;
    void clear() {
      if (identical(_financialTail, tail)) _financialTail = null;
    }

    tail = result.then<void>(
      (_) => clear(),
      onError: (Object error, StackTrace stack) => clear(),
    );
    _financialTail = tail;
    return result;
  }

  String _financialKey(String? owner) =>
      owner == null ? 'gym_financial_v1' : 'gym_${owner}_financial_v1';

  void _loadFinancialSnapshot(SharedPreferences preferences) {
    final saved = preferences.getString(_financialKey(_currentUserId));
    if (saved == null) return;
    final data = json.decode(saved) as Map<String, dynamic>;
    _paymentMap = {
      for (final item in data['payments'] as List)
        (item['id'] as String): PaymentRecord.fromMap(
          Map<String, dynamic>.from(item as Map),
        ),
    };
    _billsMap = {
      for (final item in data['bills'] as List)
        (item['id'] as String): BillRecord.fromMap(
          Map<String, dynamic>.from(item as Map),
        ),
    };
  }

  Future<void> _saveFinancialSnapshot(
    Map<String, PaymentRecord> payments,
    Map<String, BillRecord> bills,
  ) {
    final key = _financialKey(_currentUserId);
    final saved = json.encode({
      'payments': payments.values.map((p) => p.toMap()).toList(),
      'bills': bills.values.map((b) => b.toMap()).toList(),
    });
    final write = (_financialCacheTail ?? Future.value())
        .catchError((Object _) {})
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          bool stored;
          try {
            stored = await preferences.setString(key, saved);
          } catch (_) {
            await preferences.reload();
            rethrow;
          }
          if (!stored) {
            await preferences.reload();
            throw StateError('Could not save payment history on this phone.');
          }
        });
    late final Future<void> result;
    result = write.whenComplete(() {
      if (identical(_financialCacheTail, result)) _financialCacheTail = null;
    });
    _financialCacheTail = result;
    return result;
  }

  Future<void> _refreshFinancialCache() async {
    try {
      await _savePayments();
      await _saveBills();
      _financialCacheError = null;
    } catch (_) {
      _financialCacheError =
          'Payment saved. Local history refresh needs a retry.';
    }
  }

  Future<void> _commitFinancialChange(
    PaymentRecord payment,
    BillRecord bill,
  ) async {
    if (_currentUserId == null) {
      await _saveFinancialSnapshot(
        {..._paymentMap, payment.id: payment},
        {..._billsMap, bill.id: bill},
      );
    } else {
      await _queueChanges([
        CloudChange('payments', payment.id, payment.toMap()),
        CloudChange('bills', bill.id, bill.toMap()),
      ], autoFlush: false);
    }
    _paymentMap[payment.id] = payment;
    _billsMap[bill.id] = bill;
    await _refreshFinancialCache();
    notifyListeners();
    unawaited(_syncQueue?.flush() ?? Future.value());
  }

  Map<String, Map<String, dynamic>> _overlay(
    String collection,
    Map<String, Map<String, dynamic>> records,
  ) => _syncQueue?.overlay(collection, records) ?? records;

  List<Customer> get customers => List.unmodifiable(_customers);
  List<ExpenseRecord> get expenses => List.unmodifiable(_expenses);
  Map<String, BillRecord> get billsMap => Map.unmodifiable(_billsMap);
  GymSettings get settings => _settings;
  String? get currentUserId => _currentUserId;

  /// Effective gym logo path with fallback to cached owner profile photo
  String? get gymLogoPath {
    final path = _settings.gymLogoPath;
    if (path != null && path.trim().isNotEmpty) {
      return path.trim();
    }
    final authPhoto = AuthService().profilePhotoPath;
    if (authPhoto != null && authPhoto.trim().isNotEmpty) {
      return authPhoto.trim();
    }
    return null;
  }
  bool get isCloudAttached => _isCloudAttached;
  bool get isMigratedToCloud => _isMigratedToCloud;
  bool get isInitialized => _isInitialized;

  // Keys for SharedPreferences
  static const String _keyCustomers = 'gym_customers_v1';
  static const String _keyExpenses = 'gym_expenses_v1';
  static const String _keyAttendance = 'gym_attendance_v1';
  static const String _keyPayments = 'gym_payments_v1';
  static const String _keyBills = 'gym_bills_v1';
  static const String _keySettings = 'gym_settings_v1';
  static const String _keyPaymentsSchemaV2 = 'payments_schema_v2';

  String _customerKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_customers_v1' : _keyCustomers;
  String _expensesKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_expenses_v1' : _keyExpenses;
  String _attendanceKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_attendance_v1' : _keyAttendance;
  String _paymentsKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_payments_v1' : _keyPayments;
  String _billsKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_bills_v1' : _keyBills;
  String _settingsKey(String? uid) => (uid != null && uid.isNotEmpty) ? 'gym_${uid}_settings_v1' : _keySettings;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final currentUser = AuthService().currentUser;
      if (currentUser != null) {
        _currentUserId = currentUser.uid;
        await _loadUserLocalData(currentUser.uid);
      } else if (Firebase.apps.isEmpty) {
        // Fallback for offline exploration mode when Firebase is not configured
        final settingsJson = prefs.getString(_keySettings);
        if (settingsJson != null) {
          _settings = GymSettings.fromJson(settingsJson);
        }

        final customersJson = prefs.getString(_keyCustomers);
        if (customersJson != null) {
          final list = json.decode(customersJson) as List<dynamic>;
          _customers = list.map((item) => Customer.fromMap(item as Map<String, dynamic>)).toList();
        }

        final attendanceJson = prefs.getString(_keyAttendance);
        if (attendanceJson != null) {
          final list = json.decode(attendanceJson) as List<dynamic>;
          _attendanceMap = {
            for (var item in list)
              "${item['customerId']}_${item['dateKey']}": AttendanceRecord.fromMap(item as Map<String, dynamic>)
          };
        }

        final paymentsJson = prefs.getString(_keyPayments);
        if (paymentsJson != null) {
          final list = json.decode(paymentsJson) as List<dynamic>;
          _paymentMap = {
            for (var item in list)
              (item['id'] as String? ?? ''): PaymentRecord.fromMap(item as Map<String, dynamic>)
          };
        }

        final billsJson = prefs.getString(_keyBills);
        if (billsJson != null) {
          final list = json.decode(billsJson) as List<dynamic>;
          _billsMap = {
            for (var item in list)
              (item['id'] as String? ?? ''): BillRecord.fromMap(item as Map<String, dynamic>)
          };
        }
        _loadFinancialSnapshot(prefs);

        final expensesJson = prefs.getString(_keyExpenses);
        if (expensesJson != null) {
          final list = json.decode(expensesJson) as List<dynamic>;
          _expenses = list
              .map((item) => ExpenseRecord.fromMap(item as Map<String, dynamic>))
              .toList();
        }
      } else {
        // Firebase is active but no user is currently authenticated:
        // Keep in-memory data completely clean so old user's data is never displayed or leaked!
        _customers = [];
        _expenses = [];
        _attendanceMap = {};
        _paymentMap = {};
        _billsMap = {};
        _settings = const GymSettings();
      }

      if (prefs.getBool(_keyPaymentsSchemaV2) != true) {
        await _migrateLegacyPayments();
        await prefs.setBool(_keyPaymentsSchemaV2, true);
      }
    } catch (e) {
      debugPrint('Error initializing GymService: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadUserLocalData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final settingsJson = prefs.getString(_settingsKey(userId));
      if (settingsJson != null) {
        _settings = GymSettings.fromJson(settingsJson);
      } else {
        _settings = const GymSettings();
      }

      final customersJson = prefs.getString(_customerKey(userId));
      if (customersJson != null) {
        final list = json.decode(customersJson) as List<dynamic>;
        _customers = list.map((item) => Customer.fromMap(item as Map<String, dynamic>)).toList();
      } else {
        _customers = [];
      }

      final attendanceJson = prefs.getString(_attendanceKey(userId));
      if (attendanceJson != null) {
        final list = json.decode(attendanceJson) as List<dynamic>;
        _attendanceMap = {
          for (var item in list)
            "${item['customerId']}_${item['dateKey']}": AttendanceRecord.fromMap(item as Map<String, dynamic>)
        };
      } else {
        _attendanceMap = {};
      }

      final paymentsJson = prefs.getString(_paymentsKey(userId));
      if (paymentsJson != null) {
        final list = json.decode(paymentsJson) as List<dynamic>;
        _paymentMap = {
          for (var item in list)
            (item['id'] as String? ?? ''): PaymentRecord.fromMap(item as Map<String, dynamic>)
        };
      } else {
        _paymentMap = {};
      }

      final billsJson = prefs.getString(_billsKey(userId));
      if (billsJson != null) {
        final list = json.decode(billsJson) as List<dynamic>;
        _billsMap = {
          for (var item in list)
            (item['id'] as String? ?? ''): BillRecord.fromMap(item as Map<String, dynamic>)
        };
      } else {
        _billsMap = {};
      }
      _loadFinancialSnapshot(prefs);

      final expensesJson = prefs.getString(_expensesKey(userId));
      if (expensesJson != null) {
        final list = json.decode(expensesJson) as List<dynamic>;
        _expenses = list
            .map((item) => ExpenseRecord.fromMap(item as Map<String, dynamic>))
            .toList();
      } else {
        _expenses = [];
      }
    } catch (e) {
      debugPrint('GymService._loadUserLocalData error: $e');
    }
  }

  // ==================== CLOUD LIFECYCLE ====================

  /// Attach Firestore sync for the authenticated user.
  /// Call this after successful login or signup.
  Future<void> attachUser(
    String userId, {
    bool isNewUser = false,
    GymSettings? initialSettings,
  }) async {
    // If already attached to this exact user and not initializing a new user, skip
    if (_isCloudAttached && _currentUserId == userId && !isNewUser) return;

    // If switching from another user, clear old memory first
    if (_currentUserId != null && _currentUserId != userId) {
      await detachUser(clearMemory: true);
    }

    _currentUserId = userId;

    if (isNewUser) {
      // New user signup: guarantee completely empty, clean state
      _customers = [];
      _expenses = [];
      _attendanceMap = {};
      _paymentMap = {};
      _billsMap = {};
      _settings = initialSettings ?? GymSettings(gymName: AuthService().displayName);

      // Save initial settings and empty collections to user-scoped local storage
      await _saveSettingsLocallyOnly();
      await _saveCustomers();
      await _saveAttendance();
      await _savePayments();
      await _saveBills();
      await _saveExpenses();

      // Attach Firestore listener
      await _prepareSyncQueue(userId);

      // Upsert fresh settings in Firestore for this new user
      await _queueChanges([
        CloudChange('settings', 'config', _settings.toMap()),
      ]);
      await _connectCloud(userId);

      notifyListeners();
      return;
    }

    // Existing user:
    // 1. Load user's local cached data
    await _loadUserLocalData(userId);

    // 2. Attach Firestore sync (Firestore is source of truth)
    await _prepareSyncQueue(userId);
    await _connectCloud(userId);

    notifyListeners();
  }

  /// Detach Firestore sync. Call this on logout.
  Future<void> detachUser({bool clearMemory = true}) async {
    await _financialTail;
    _syncQueue?.dispose();
    _syncQueue = null;
    _cloudReadError = null;
    _financialCacheError = null;
    await FirestoreService().detachUser();
    _isCloudAttached = false;
    _isMigratedToCloud = false;
    _currentUserId = null;

    if (clearMemory) {
      _customers = [];
      _expenses = [];
      _attendanceMap = {};
      _paymentMap = {};
      _billsMap = {};
      _settings = const GymSettings();

      try {
        final prefs = await SharedPreferences.getInstance();
        // Remove legacy un-scoped keys to ensure no stale data persists
        await prefs.remove(_keyCustomers);
        await prefs.remove(_keyExpenses);
        await prefs.remove(_keyAttendance);
        await prefs.remove(_keyPayments);
        await prefs.remove(_keyBills);
        await prefs.remove(_financialKey(null));
        await prefs.remove(_keySettings);
      } catch (e) {
        debugPrint('GymService.detachUser prefs cleanup warning: $e');
      }
    }

    notifyListeners();
  }

  /// Callback invoked by FirestoreService when cloud data changes.
  void _onFirestoreData({
    List<Customer>? customers,
    Map<String, AttendanceRecord>? attendanceMap,
    Map<String, PaymentRecord>? paymentMap,
    Map<String, BillRecord>? billsMap,
    List<ExpenseRecord>? expenses,
    GymSettings? settings,
  }) {
    if (_suppressCloudUpdates) return;

    bool changed = false;

    if (customers != null) {
      _customers = _overlay('customers', {
        for (final c in customers) c.id: c.toMap(),
      }).values.map(Customer.fromMap).toList();
      _saveCustomers();
      changed = true;
    }
    if (attendanceMap != null) {
      _attendanceMap = _overlay('attendance', {
        for (final e in attendanceMap.entries) e.key: e.value.toMap(),
      }).map((k, v) => MapEntry(k, AttendanceRecord.fromMap(v)));
      _saveAttendance();
      changed = true;
    }
    if (paymentMap != null) {
      _paymentMap = _overlay('payments', {
        for (final e in paymentMap.entries) e.key: e.value.toMap(),
      }).map((k, v) => MapEntry(k, PaymentRecord.fromMap(v)));
      changed = true;
    }
    if (billsMap != null) {
      _billsMap = _overlay('bills', {
        for (final e in billsMap.entries) e.key: e.value.toMap(),
      }).map((k, v) => MapEntry(k, BillRecord.fromMap(v)));
      changed = true;
    }
    if (expenses != null) {
      _expenses = _overlay('expenses', {
        for (final e in expenses) e.id: e.toMap(),
      }).values.map(ExpenseRecord.fromMap).toList();
      _saveExpenses();
      changed = true;
    }
    if (settings != null) {
      _settings = GymSettings.fromMap(
        _overlay('settings', {'config': settings.toMap()})['config']!,
      );
      _saveSettingsLocallyOnly();
      changed = true;
    }
    if (paymentMap != null || billsMap != null) {
      unawaited(_refreshFinancialCache());
    }

    if ((paymentMap != null || billsMap != null) && _hasLegacyPaymentShapes()) {
      _migrateLegacyPayments();
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// One-time migration of local SharedPreferences data to Firestore.
  Future<bool> migrateLocalDataToCloud() async {
    if (!_isCloudAttached) return false;
    if (_customers.isEmpty && _expenses.isEmpty) return false;

    final result = await FirestoreService().migrateLocalData(
      customers: _customers,
      attendanceMap: _attendanceMap,
      paymentMap: _paymentMap,
      billsMap: _billsMap,
      expenses: _expenses,
      settings: _settings,
    );

    if (result) {
      _isMigratedToCloud = true;
      notifyListeners();
    }
    return result;
  }

  // ==================== CUSTOMER OPERATIONS ====================

  String getNextCardNumber() {
    int maxNum = 100;
    for (final c in _customers) {
      final n = int.tryParse(c.cardNumber.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n > maxNum) {
        maxNum = n;
      }
    }
    if (maxNum == 100 && _customers.isNotEmpty) {
      return '${100 + _customers.length}';
    }
    return '${maxNum + 1}';
  }

  List<MonthCardData> getYearlyCardData(String customerId, int year) {
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    final result = <MonthCardData>[];
    for (int m = 1; m <= 12; m++) {
      final monthKey = '$year-${m.toString().padLeft(2, '0')}';
      final payment = getPaymentRecord(customerId, monthKey);
      final attSummary = getMonthlyAttendanceSummary(customerId, monthKey);
      final present = attSummary['present'] ?? 0;
      final absent = attSummary['absent'] ?? 0;
      final total = attSummary['total'] ?? 0;

      // Determine true isPaid for this specific calendar month:
      bool isPaidForMonth = payment.isPaid;
      if (isPaidForMonth && payment.endDate != null) {
        final monthStart = DateTime(year, m, 1);
        if (payment.endDate!.isBefore(monthStart)) {
          isPaidForMonth = false;
        }
      }

      DateTime? effStart;
      DateTime? effEnd;
      // A month covered by a multi-month package whose cycle started earlier.
      final bool isCovered = isPaidForMonth &&
          payment.durationMonths > 1 &&
          payment.monthYear != monthKey;
      if (isPaidForMonth) {
        effStart = payment.effectiveStartDate;
        effEnd = payment.effectiveEndDate;
      }

      result.add(MonthCardData(
        month: m,
        monthName: monthNames[m - 1],
        monthKey: monthKey,
        isPaid: isPaidForMonth,
        amount: isPaidForMonth ? payment.amount : 0.0,
        method: isPaidForMonth ? payment.method : null,
        paidAt: isPaidForMonth ? payment.paidAt : null,
        presentDays: present,
        absentDays: absent,
        totalRecorded: total,
        startDate: effStart,
        endDate: effEnd,
        isCoveredInPackage: isCovered,
      ));
    }
    return result;
  }

  Future<Customer> addCustomer({
    required String name,
    required String phone,
    String? imagePath,
    DateTime? joinDate,
    String notes = '',
    String planType = CustomerPlan.normal,
    int planDurationMonths = 1,
    String cardNumber = '',
    String address = '',
    String weight = '',
    String chest = '',
    String bicep = '',
    String waist = '',
    String leg = '',
    bool markAsPaidNow = false,
    PaymentMethod? initialPaymentMethod,
    DateTime? membershipStartDate,
    DateTime? membershipEndDate,
  }) async {
    final assignedCardNumber = cardNumber.trim().isNotEmpty
        ? cardNumber.trim()
        : getNextCardNumber();
    var newId = 'cust_${DateTime.now().millisecondsSinceEpoch}';
    while (_customers.any((c) => c.id == newId)) {
      newId += 'x';
    }
    // Pending dues are derived from attendance — no stored pending record needed.
    final customer = Customer(
      id: newId,
      name: name.trim(),
      phone: phone.trim(),
      imagePath: imagePath,
      joinDate: joinDate ?? DateTime.now(),
      isActive: true,
      notes: notes.trim(),
      planType: planType,
      planDurationMonths: planDurationMonths,
      cardNumber: assignedCardNumber,
      address: address.trim(),
      weight: weight.trim(),
      chest: chest.trim(),
      bicep: bicep.trim(),
      waist: waist.trim(),
      leg: leg.trim(),
    );
    _customers.insert(0, customer);
    await _cloudSaveCustomer(customer);

    if (markAsPaidNow) {
      final fee = _settings.getPriceForDuration(planType, planDurationMonths);
      final actualStart = membershipStartDate ?? customer.joinDate;
      final actualEnd = membershipEndDate ??
          GymDateUtils.computeAnniversaryEndDate(actualStart, planDurationMonths);
      final paymentMonthKey = GymDateUtils.toMonthKey(actualStart);
      await markPaymentAsPaid(
        customerId: customer.id,
        monthYear: paymentMonthKey,
        method: initialPaymentMethod ?? PaymentMethod.cash,
        amount: fee,
        totalDue: fee,
        durationMonths: planDurationMonths,
        startDate: actualStart,
        endDate: actualEnd,
        notes: 'Initial registration payment',
      );
    }

    notifyListeners();
    await _saveCustomers();
    await _savePayments();

    return customer;
  }

  /// Checks whether a specific attendance dateKey (yyyy-MM-dd) is covered by any valid paid payment.
  bool isDateCoveredByPayment(String customerId, String dateKey) {
    final date = DateTime.tryParse(dateKey);
    if (date == null) return false;
    return _duesIndex.covers(customerId, GymDateUtils.toDateKey(date));
  }

  /// Returns the count of attended (present) days in a month that have NOT been covered by any paid payment.
  int getUnpaidAttendedDaysInMonth(String customerId, String monthKey) {
    return _duesIndex.unpaid[customerId]?[monthKey]?.length ?? 0;
  }

  /// Returns the count of attended (present) days in a month that ARE covered by a paid payment.
  int getPaidAttendedDaysInMonth(String customerId, String monthKey) {
    int count = 0;
    for (final record in _attendanceMap.values) {
      if (record.customerId == customerId &&
          record.status == AttendanceStatus.present &&
          record.dateKey.startsWith(monthKey)) {
        if (isDateCoveredByPayment(customerId, record.dateKey)) {
          count++;
        }
      }
    }
    return count;
  }

  /// Returns the count of attended days covered by a specific payment's validity range.
  int getAttendedDaysCoveredByPayment(String customerId, PaymentRecord payment) {
    if (!payment.isPaid) return 0;
    final start = DateTime(payment.effectiveStartDate.year, payment.effectiveStartDate.month, payment.effectiveStartDate.day);
    final end = DateTime(payment.effectiveEndDate.year, payment.effectiveEndDate.month, payment.effectiveEndDate.day);

    int count = 0;
    for (final record in _attendanceMap.values) {
      if (record.customerId == customerId && record.status == AttendanceStatus.present) {
        final d = DateTime.tryParse(record.dateKey);
        if (d != null) {
          final day = DateTime(d.year, d.month, d.day);
          if (!day.isBefore(start) && !day.isAfter(end)) {
            count++;
          }
        }
      }
    }
    return count;
  }

  /// Checks whether a calendar month is covered by a valid paid payment.
  bool isMonthCoveredByPaidPayment(String customerId, String monthKey) {
    return getPaymentCoveringMonth(customerId, monthKey) != null;
  }

  /// Returns the PaymentRecord covering a specific month, if any.
  /// Among paid records whose [effectiveStartDate, effectiveEndDate] overlaps the
  /// calendar month, prefers one whose cycle starts in that month (latest start
  /// first), else the one with the latest start.
  PaymentRecord? getPaymentCoveringMonth(String customerId, String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final monthStart = DateTime(y, m, 1);
    final monthEnd = DateTime(y, m, GymDateUtils.daysInMonth(y, m));

    final covering = <PaymentRecord>[];
    for (final p in _duesIndex.payments[customerId] ?? <PaymentRecord>[]) {
        final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
        final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);
        if (!start.isAfter(monthEnd) && !end.isBefore(monthStart)) {
          covering.add(p);
      }
    }
    if (covering.isEmpty) return null;

    covering.sort((a, b) => b.effectiveStartDate.compareTo(a.effectiveStartDate));
    for (final p in covering) {
      if (p.monthYear == monthKey) return p;
    }
    return covering.first;
  }

  /// Evaluates member lifecycle stage for a given month:
  /// - PAID: Covered by a valid paid plan with no unpaid attended days in that month
  /// - NEW: Unpaid + 0 attendance days + Joined within last 3 days
  /// - DUE: Unpaid attended days or expired / lacking plan
  MemberLifecycleStage getMemberLifecycleStage(Customer customer, String monthYear) {
    // 1. Check if a paid payment covers this month — but only count it as
    // paid when no attended days in the month are left uncovered.
    final unpaidAttendedDays = getUnpaidAttendedDaysInMonth(customer.id, monthYear);
    final parts = monthYear.split('-');
    if (parts.length == 2 && unpaidAttendedDays == 0) {
      final y = int.tryParse(parts[0]) ?? 2026;
      final m = int.tryParse(parts[1]) ?? 1;
      final monthStart = DateTime(y, m, 1);
      final monthEnd = DateTime(y, m, GymDateUtils.daysInMonth(y, m));

      for (final p in _paymentMap.values) {
        if (p.customerId == customer.id && p.isPaid) {
          final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
          final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);

          if (!start.isAfter(monthEnd) && !end.isBefore(monthStart)) {
            final now = DateTime.now();
            final currentMonthKey = GymDateUtils.toMonthKey(now);
            if (monthYear == currentMonthKey) {
              final today = DateTime(now.year, now.month, now.day);
              if (!start.isAfter(today) && !end.isBefore(today)) {
                return MemberLifecycleStage.paid;
              }
            } else {
              return MemberLifecycleStage.paid;
            }
          }
        }
      }
    }

    // 2. If this month has any attended days that are NOT covered by payment -> DUE!
    if (unpaidAttendedDays > 0) {
      return MemberLifecycleStage.due;
    }

    // 3. If month is before the customer joined, not paid, and has 0 attendance -> not enrolled
    final joinMonthKey = GymDateUtils.toMonthKey(customer.joinDate);
    if (monthYear.compareTo(joinMonthKey) < 0) {
      return MemberLifecycleStage.notEnrolled;
    }

    // 4. New member check (only applies to current month of joining with 0 attendance within 3 days)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final joinDay = DateTime(customer.joinDate.year, customer.joinDate.month, customer.joinDate.day);
    final daysSinceJoined = today.difference(joinDay).inDays;
    final currentMonthKey = GymDateUtils.toMonthKey(now);

    final hasAttended = _attendanceMap.values.any(
      (a) => a.customerId == customer.id && a.status == AttendanceStatus.present,
    );

    if (!hasAttended && daysSinceJoined <= 3 && monthYear == currentMonthKey) {
      return MemberLifecycleStage.newMember;
    }

    return MemberLifecycleStage.due;
  }

  Future<void> updateCustomer(Customer updated) async {
    final index = _customers.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _customers[index] = updated;

      await _cloudSaveCustomer(updated);
      notifyListeners();
      await _saveCustomers();
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    await archiveCustomer(customerId);
  }

  /// Keep receipts and attendance when a member leaves the gym.
  Future<void> archiveCustomer(String customerId) async {
    final customer = getCustomerById(customerId);
    if (customer != null) {
      await updateCustomer(customer.copyWith(isActive: false));
    }
  }

  Future<void> restoreCustomer(String customerId) async {
    final customer = getCustomerById(customerId);
    if (customer != null) {
      await updateCustomer(customer.copyWith(isActive: true));
    }
  }

  Customer? getCustomerById(String id) {
    try {
      return _customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Customer> searchCustomers(String query) {
    if (query.trim().isEmpty) return customers;
    final q = query.toLowerCase().trim();
    return _customers.where((c) {
      return c.name.toLowerCase().contains(q) || c.phone.contains(q);
    }).toList();
  }

  // ==================== ATTENDANCE OPERATIONS ====================

  String _attKey(String customerId, String dateKey) => "${customerId}_$dateKey";

  AttendanceRecord? getAttendance(String customerId, String dateKey) {
    return _attendanceMap[_attKey(customerId, dateKey)];
  }

  AttendanceStatus getAttendanceStatus(String customerId, String dateKey) {
    return _attendanceMap[_attKey(customerId, dateKey)]?.status ?? AttendanceStatus.absent;
  }

  bool isCustomerPresentOnDate(String customerId, String dateKey) {
    return _attendanceMap[_attKey(customerId, dateKey)]?.status == AttendanceStatus.present;
  }

  bool _canRecordAttendance(
    String customerId,
    DateTime date, {
    bool allowBeforeJoin = false,
  }) {
    final customer = getCustomerById(customerId);
    if (customer == null || !customer.isActive) return false;
    final join = customer.joinDate;
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    return (allowBeforeJoin ||
            !day.isBefore(DateTime(join.year, join.month, join.day))) &&
        !day.isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<void> toggleAttendance(String customerId, String dateKey, AttendanceStatus status, {
    bool toggle = true,
  }) async {
    final date = DateTime.tryParse(dateKey);
    if (date == null ||
        !_canRecordAttendance(customerId, date, allowBeforeJoin: true)) {
      return;
    }
    {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final targetDay = DateTime(date.year, date.month, date.day);
      if (targetDay.isAfter(today)) {
        // Disallow marking attendance for future dates!
        return;
      }
    }

    final key = _attKey(customerId, dateKey);
    final existing = _attendanceMap[key];

    if (toggle && existing != null && existing.status == status) {
      // Toggle off to absent if tapped again
      _attendanceMap[key] = existing.copyWith(
        status: AttendanceStatus.absent,
        recordedAt: DateTime.now(),
      );
    } else {
      _attendanceMap[key] = AttendanceRecord(
        id: 'att_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode}',
        customerId: customerId,
        dateKey: dateKey,
        status: status,
        recordedAt: DateTime.now(),
      );
    }

    await _cloudSaveAttendance(_attendanceMap[key]!);
    notifyListeners();
    await _saveAttendance();
  }

  Future<void> markAllPresentForDate(String dateKey) async {
    final date = DateTime.tryParse(dateKey);
    if (date == null) throw ArgumentError('Choose a valid attendance date.');
    final records = <AttendanceRecord>[];
    for (final customer in _customers) {
      if (!_canRecordAttendance(customer.id, date)) continue;
      final key = _attKey(customer.id, dateKey);
      final record = AttendanceRecord(
        id: _attendanceMap[key]?.id ?? 'att_$key',
        customerId: customer.id,
        dateKey: dateKey,
        status: AttendanceStatus.present,
        recordedAt: DateTime.now(),
      );
      _attendanceMap[key] = record;
      records.add(record);
    }
    await _cloudBatchSaveAttendance(records);
    notifyListeners();
    await _saveAttendance();
  }

  Future<void> markTodayQuickAttendance(String customerId, bool present) async {
    final todayKey = GymDateUtils.toDateKey(DateTime.now());
    await toggleAttendance(
      customerId,
      todayKey,
      present ? AttendanceStatus.present : AttendanceStatus.absent,
      toggle: false,
    );
  }

  Future<void> setMonthAttendance({
    required String customerId,
    required int year,
    required int month,
    required AttendanceStatus status,
    bool excludeSundays = false,
    AttendanceStatus sundayStatus = AttendanceStatus.rest,
    bool upToTodayOnly = false,
  }) async {
    final now = DateTime.now();
    final monthStart = DateTime(year, month, 1);
    final currentMonthStart = DateTime(now.year, now.month, 1);
    if (monthStart.isAfter(currentMonthStart)) {
      // Cannot mark attendance for future months!
      return;
    }

    final isCurrentMonth = now.year == year && now.month == month;
    final totalDays = GymDateUtils.daysInMonth(year, month);
    // For current month, always cap at today (future dates cannot be marked)!
    final maxDay = isCurrentMonth ? now.day : totalDays;

    for (int day = 1; day <= maxDay; day++) {
      final date = DateTime(year, month, day);
      if (!_canRecordAttendance(customerId, date)) continue;
      final dateKey = GymDateUtils.toDateKey(date);
      final key = _attKey(customerId, dateKey);

      AttendanceStatus targetStatus = status;
      if (excludeSundays && date.weekday == DateTime.sunday) {
        targetStatus = sundayStatus;
      }

      final existing = _attendanceMap[key];
      if (existing != null) {
        _attendanceMap[key] = existing.copyWith(
          status: targetStatus,
          recordedAt: DateTime.now(),
        );
      } else {
        _attendanceMap[key] = AttendanceRecord(
          id: 'att_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode}_$day',
          customerId: customerId,
          dateKey: dateKey,
          status: targetStatus,
          recordedAt: DateTime.now(),
        );
      }
    }

    // Collect all modified records for batch cloud sync
    final modifiedRecords = <AttendanceRecord>[];
    for (int day = 1; day <= maxDay; day++) {
      final date = DateTime(year, month, day);
      if (!_canRecordAttendance(customerId, date)) continue;
      final dateKey = GymDateUtils.toDateKey(date);
      final key = _attKey(customerId, dateKey);
      final record = _attendanceMap[key];
      if (record != null) modifiedRecords.add(record);
    }

    await _cloudBatchSaveAttendance(modifiedRecords);
    notifyListeners();
    await _saveAttendance();
  }

  Future<void> setMonthAttendanceForMultiple({
    required List<String> customerIds,
    required int year,
    required int month,
    required AttendanceStatus status,
    bool excludeSundays = false,
    AttendanceStatus sundayStatus = AttendanceStatus.rest,
    bool upToTodayOnly = false,
  }) async {
    final now = DateTime.now();
    final monthStart = DateTime(year, month, 1);
    final currentMonthStart = DateTime(now.year, now.month, 1);
    if (monthStart.isAfter(currentMonthStart)) {
      // Cannot mark attendance for future months!
      return;
    }

    final isCurrentMonth = now.year == year && now.month == month;
    final totalDays = GymDateUtils.daysInMonth(year, month);
    final maxDay = isCurrentMonth ? now.day : totalDays;

    for (final customerId in customerIds) {
      for (int day = 1; day <= maxDay; day++) {
        final date = DateTime(year, month, day);
        if (!_canRecordAttendance(customerId, date)) continue;
        final dateKey = GymDateUtils.toDateKey(date);
        final key = _attKey(customerId, dateKey);

        AttendanceStatus targetStatus = status;
        if (excludeSundays && date.weekday == DateTime.sunday) {
          targetStatus = sundayStatus;
        }

        final existing = _attendanceMap[key];
        if (existing != null) {
          _attendanceMap[key] = existing.copyWith(
            status: targetStatus,
            recordedAt: DateTime.now(),
          );
        } else {
          _attendanceMap[key] = AttendanceRecord(
            id: 'att_${DateTime.now().millisecondsSinceEpoch}_${customerId.hashCode}_$day',
            customerId: customerId,
            dateKey: dateKey,
            status: targetStatus,
            recordedAt: DateTime.now(),
          );
        }
      }
    }

    // Collect all modified records for batch cloud sync
    final modifiedRecords = <AttendanceRecord>[];
    for (final cId in customerIds) {
      for (int day = 1; day <= maxDay; day++) {
        final date = DateTime(year, month, day);
        if (!_canRecordAttendance(cId, date)) continue;
        final dateKey = GymDateUtils.toDateKey(date);
        final key = _attKey(cId, dateKey);
        final record = _attendanceMap[key];
        if (record != null) modifiedRecords.add(record);
      }
    }

    await _cloudBatchSaveAttendance(modifiedRecords);
    notifyListeners();
    await _saveAttendance();
  }

  Map<String, int> getMonthlyAttendanceSummary(String customerId, String monthYear) {
    int presentCount = 0;
    int absentCount = 0;
    int restCount = 0;

    for (var record in _attendanceMap.values) {
      if (record.customerId == customerId && record.dateKey.startsWith(monthYear)) {
        switch (record.status) {
          case AttendanceStatus.present:
            presentCount++;
            break;
          case AttendanceStatus.absent:
            absentCount++;
            break;
          case AttendanceStatus.rest:
            restCount++;
            break;
        }
      }
    }

    return {
      'present': presentCount,
      'absent': absentCount,
      'rest': restCount,
    };
  }

  Map<String, int> getDateRangeAttendanceSummary(String customerId, DateTime start, DateTime end) {
    int presentCount = 0;
    int absentCount = 0;
    int restCount = 0;

    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);

    for (var record in _attendanceMap.values) {
      if (record.customerId == customerId) {
        final d = DateTime.tryParse(record.dateKey);
        if (d != null) {
          final recordDay = DateTime(d.year, d.month, d.day);
          if (!recordDay.isBefore(startDay) && !recordDay.isAfter(endDay)) {
            switch (record.status) {
              case AttendanceStatus.present:
                presentCount++;
                break;
              case AttendanceStatus.absent:
                absentCount++;
                break;
              case AttendanceStatus.rest:
                restCount++;
                break;
            }
          }
        }
      }
    }

    return {
      'present': presentCount,
      'absent': absentCount,
      'rest': restCount,
    };
  }

  List<String> getUnpaidAttendedMonthKeys(String customerId) {
    return (_duesIndex.unpaid[customerId]?.keys.toList() ?? <String>[])..sort();
  }


  Map<String, int> getDailyOverview(String dateKey) {
    int present = 0;
    int rest = 0;
    final date = DateTime.tryParse(dateKey);
    final eligible = _customers
        .where(
          (c) =>
              c.isActive &&
              date != null &&
              !DateTime(date.year, date.month, date.day).isBefore(
                DateTime(c.joinDate.year, c.joinDate.month, c.joinDate.day),
              ),
        )
        .toList();
    int totalActive = eligible.length;

    for (var c in eligible) {
      if (isCustomerPresentOnDate(c.id, dateKey)) {
        present++;
      } else if (getAttendanceStatus(c.id, dateKey) == AttendanceStatus.rest) {
        rest++;
      }
    }

    return {
      'total': totalActive,
      'present': present,
      'absent': totalActive - present - rest,
      'rest': rest,
    };
  }

  // ==================== PAYMENT OPERATIONS ====================

  /// The plan fee used for derived pending records and as default total due.
  double _feeForCustomer(Customer? customer, {int? durationMonths}) {
    if (customer == null) return _settings.standardMonthlyFee;
    return _settings.getPriceForDuration(
        customer.planType, durationMonths ?? customer.planDurationMonths);
  }

  /// All paid payment records for a customer, latest cycle start first.
  List<PaymentRecord> getPaidPaymentsForCustomer(String customerId) {
    return List.of(_duesIndex.payments[customerId] ?? <PaymentRecord>[]);
  }

  PaymentRecord? getPaymentById(String id) => _paymentMap[id];

  PaymentRecord getRenewalPaymentRecord(Customer customer) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = getCustomerExpiryDate(customer);
    final start = hasPaidMembership(customer) && !expiry.isBefore(today)
        ? expiry.add(const Duration(days: 1))
        : today;
    return PaymentRecord(
      id: 'pending_renewal_${customer.id}',
      customerId: customer.id,
      monthYear: GymDateUtils.toMonthKey(start),
      amount: 0,
      totalDue: _feeForCustomer(customer),
      status: PaymentStatus.pending,
      durationMonths: customer.planDurationMonths,
      startDate: start,
    );
  }

  void _validatePayment(
    double amount,
    double due,
    int duration,
    DateTime start,
    DateTime end,
    DateTime received,
  ) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Enter an amount greater than zero.');
    }
    if (!due.isFinite || due <= 0 || amount > due + 0.005) {
      throw ArgumentError(
        'The amount received cannot exceed the membership fee.',
      );
    }
    if (duration <= 0 || end.isBefore(start)) {
      throw ArgumentError('Choose a valid membership period.');
    }
    final now = DateTime.now();
    if (DateTime(
      received.year,
      received.month,
      received.day,
    ).isAfter(DateTime(now.year, now.month, now.day))) {
      throw ArgumentError('The payment received date cannot be in the future.');
    }
  }

  /// Amount still owed for a record: the remaining balance for partially paid
  /// records, the full fee for pending ones.
  double pendingAmountOf(PaymentRecord r) => r.isPaid ? r.balanceDue : r.totalDue;

  /// Pure read: the paid payment covering [monthYear] with all attended days
  /// covered, or a transient pending record when attended days remain unpaid.
  /// Transient records are never stored.
  PaymentRecord getPaymentRecord(String customerId, String monthYear) {
    final covering = getPaymentCoveringMonth(customerId, monthYear);
    final unpaidDays = getUnpaidAttendedDaysInMonth(customerId, monthYear);
    if (covering != null && unpaidDays == 0) return covering;

    // A paid cycle overlaps this month but still-uncovered attended days
    // remain: suggest the new cycle start at the first uncovered attendance
    // (or right after the latest paid cycle that ends before it).
    DateTime? suggestedStart;
    if (covering != null) {
      final parts = monthYear.split('-');
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final monthStart = DateTime(y, m, 1);

      DateTime? firstUnpaid;
      for (final dateKey
          in _duesIndex.unpaid[customerId]?[monthYear] ?? <String>[]) {
        final d = DateTime.tryParse(dateKey);
        if (d != null) {
          final day = DateTime(d.year, d.month, d.day);
          if (firstUnpaid == null || day.isBefore(firstUnpaid)) {
            firstUnpaid = day;
          }
        }
      }

      if (firstUnpaid != null) {
        DateTime? prevEndPlusOne;
        for (final p in _duesIndex.payments[customerId] ?? <PaymentRecord>[]) {
          final e = p.effectiveEndDate;
          final endPlusOne = DateTime(e.year, e.month, e.day + 1);
          if (!endPlusOne.isAfter(firstUnpaid) &&
              !endPlusOne.isBefore(monthStart)) {
            if (prevEndPlusOne == null || endPlusOne.isAfter(prevEndPlusOne)) {
              prevEndPlusOne = endPlusOne;
            }
          }
        }
        suggestedStart = prevEndPlusOne ?? firstUnpaid;
      }
    }

    final customer = getCustomerById(customerId);
    return PaymentRecord(
      id: 'pending_${customerId}_$monthYear',
      customerId: customerId,
      monthYear: monthYear,
      amount: 0.0,
      totalDue: _feeForCustomer(customer),
      status: PaymentStatus.pending,
      durationMonths: customer?.planDurationMonths ?? 1,
      startDate: suggestedStart,
    );
  }

  // ---------- Bills ----------

  /// The primary (non-BALANCE) PAID bill issued for a payment.
  BillRecord? getBillForPayment(String paymentId) {
    for (final b in _billsMap.values) {
      if (b.paymentId == paymentId &&
          b.status == 'PAID' &&
          b.billType != 'BALANCE') {
        return b;
      }
    }
    return null;
  }

  /// All PAID bills for a payment, oldest first.
  List<BillRecord> getBillsForPayment(String paymentId) {
    final list = _billsMap.values
        .where((b) => b.paymentId == paymentId && b.status == 'PAID')
        .toList();
    list.sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
    return list;
  }

  /// Every bill ever issued to a customer (PAID and CANCELLED), newest first.
  List<BillRecord> getAllBillsForCustomer(String customerId) {
    final list =
        _billsMap.values.where((b) => b.customerId == customerId).toList();
    list.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  /// Every bill for a payment (PAID and CANCELLED), newest first.
  List<BillRecord> getAllBillsForPayment(String paymentId) {
    final list =
        _billsMap.values.where((b) => b.paymentId == paymentId).toList();
    list.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  /// Primary bill covering a customer+month (UI compatibility shim).
  BillRecord? getBill(String customerId, String monthYear) {
    final p = getPaymentCoveringMonth(customerId, monthYear);
    if (p == null) return null;
    return getBillForPayment(p.id);
  }

  BillRecord getOrCreateBillForPayment(Customer customer, PaymentRecord payment) {
    if (payment.isPaid && !payment.id.startsWith('pending_')) {
      final existing = getBillForPayment(payment.id);
      if (existing != null) return existing;

      // Legacy gap: a paid payment with no persisted bill — create + persist once.
      final bill = _buildPaidBill(customer, payment);
      _billsMap[bill.id] = bill;
      unawaited(_refreshFinancialCache());
      _cloudSaveBill(bill);
      return bill;
    }

    // Transient/pending payment: return a non-persisted preview bill.
    final effectiveAmount = payment.amount > 0.0
        ? payment.amount
        : _feeForCustomer(customer, durationMonths: payment.durationMonths);
    return _buildPaidBill(customer, payment).copyWith(
      id: 'bill_${customer.id}_${payment.monthYear}',
      amount: effectiveAmount,
      billType: 'FULL',
      status: payment.isPaid ? 'PAID' : 'PENDING',
    );
  }

  BillRecord _buildPaidBill(Customer customer, PaymentRecord payment) =>
      BillRecord(
        id: 'bill_${customer.id}_${DateTime.now().millisecondsSinceEpoch}',
        billNumber: generateBillNumber(payment.monthYear),
        customerId: customer.id,
        customerName: customer.name,
        customerPhone: customer.phone,
        planType: customer.planType,
        monthYear: payment.monthYear,
        amount: payment.amount,
        paymentId: payment.id,
        billType: payment.balanceDue > 0 ? 'PARTIAL' : 'FULL',
        method: payment.method ?? PaymentMethod.cash,
        paidAt: payment.paidAt ?? DateTime.now(),
        notes: payment.notes,
        transactionRef: payment.transactionRef,
        gymName: _settings.gymName,
        issuedAt: payment.paidAt ?? DateTime.now(),
        status: 'PAID',
        durationMonths: payment.durationMonths,
        startDate: payment.startDate ?? payment.effectiveStartDate,
        endDate: payment.endDate ?? payment.effectiveEndDate,
        coveragePeriod: payment.formattedDateRange,
      );

  /// Sequential bill number BILL-YYYYMM-NNNN where NNNN = max sequence parsed
  /// from existing bill numbers with the same prefix (any status) + 1.
  /// Cancelled bills keep their numbers forever, so numbers are never reused.
  String generateBillNumber(String monthYear) {
    final cleanMonth = monthYear.replaceAll('-', '');
    final prefix = 'BILL-$cleanMonth-';
    final seqRe = RegExp('^${RegExp.escape(prefix)}(\\d+)\$');
    int maxSeq = 0;
    for (final b in _billsMap.values) {
      final match = seqRe.firstMatch(b.billNumber);
      if (match != null) {
        final seq = int.tryParse(match.group(1)!) ?? 0;
        if (seq > maxSeq) maxSeq = seq;
      }
    }
    return '$prefix${(maxSeq + 1).toString().padLeft(4, '0')}';
  }

  String _newPaymentId(String customerId) {
    var id = 'pay_${customerId}_${DateTime.now().millisecondsSinceEpoch}';
    while (_paymentMap.containsKey(id)) {
      id = '${id}x';
    }
    return id;
  }

  String _newBillId(String customerId) {
    var id = 'bill_${customerId}_${DateTime.now().millisecondsSinceEpoch}';
    while (_billsMap.containsKey(id)) {
      id = '${id}x';
    }
    return id;
  }

  /// Records a payment. Always creates a NEW PaymentRecord with a fresh id —
  /// never overwrites an existing one. [monthYear] is only a hint kept for
  /// callers; the record's monthYear is the month the cycle starts in.
  Future<BillRecord> markPaymentAsPaid({
    required String customerId,
    required String monthYear,
    required PaymentMethod method,
    required double amount,
    double? totalDue,
    int durationMonths = 1,
    DateTime? startDate,
    DateTime? endDate,
    String? notes,
    String? transactionRef,
    DateTime? paidAt,
    String? operationId,
  }) => _serializeFinancialSave(() async {
    final receiptId = operationId == null
        ? _newBillId(customerId)
        : 'bill_operation_$operationId';
    final saved = _billsMap[receiptId];
    if (saved != null) return saved;
    final effectivePaidAt = paidAt ?? DateTime.now();
    final customer = getCustomerById(customerId);
    if (customer == null || !customer.isActive) {
      throw ArgumentError('Restore the member before recording a new payment.');
    }

    // Smart default for startDate if not provided:
    DateTime computedStartDate;
    if (startDate != null) {
      computedStartDate = startDate;
    } else {
      final currentExpiry = getCustomerExpiryDate(customer);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (hasPaidMembership(customer) && !currentExpiry.isBefore(today)) {
        // Member is currently active -> advance payment starts day after expiry
        computedStartDate = currentExpiry.add(const Duration(days: 1));
      } else {
        computedStartDate = DateTime(
            effectivePaidAt.year, effectivePaidAt.month, effectivePaidAt.day);
      }
    }

    final computedEndDate = endDate ??
        GymDateUtils.computeAnniversaryEndDate(computedStartDate, durationMonths);
    final coveragePeriod =
        GymDateUtils.formatDateRange(computedStartDate, computedEndDate);
    final startMonthKey = GymDateUtils.toMonthKey(computedStartDate);
    final effectiveTotalDue =
        totalDue ?? _feeForCustomer(customer, durationMonths: durationMonths);
    _validatePayment(
      amount,
      effectiveTotalDue,
      durationMonths,
      computedStartDate,
      computedEndDate,
      effectivePaidAt,
    );

    final record = PaymentRecord(
      id: _newPaymentId(customerId),
      customerId: customerId,
      monthYear: startMonthKey,
      amount: amount,
      totalDue: effectiveTotalDue,
      status: PaymentStatus.paid,
      method: method,
      paidAt: effectivePaidAt,
      startDate: computedStartDate,
      endDate: computedEndDate,
      notes: notes,
      transactionRef: transactionRef,
      durationMonths: durationMonths,
    );
    final bill = BillRecord(
      id: receiptId,
      billNumber: generateBillNumber(startMonthKey),
      customerId: customerId,
      customerName: customer.name,
      customerPhone: customer.phone,
      planType: customer.planType,
      monthYear: startMonthKey,
      amount: amount,
      paymentId: record.id,
      billType: amount + 0.005 >= effectiveTotalDue ? 'FULL' : 'PARTIAL',
      method: method,
      paidAt: effectivePaidAt,
      startDate: computedStartDate,
      endDate: computedEndDate,
      notes: notes,
      transactionRef: transactionRef,
      gymName: _settings.gymName,
      issuedAt: DateTime.now(),
      status: 'PAID',
      durationMonths: durationMonths,
      coveragePeriod: coveragePeriod,
    );
    await _commitFinancialChange(record, bill);

    return bill;
  });

  /// Collects (part of) the remaining balance on a paid payment. Issues its own
  /// BALANCE bill with its own bill number.
  Future<BillRecord> collectBalance({
    required String paymentId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
    String? transactionRef,
    String? operationId,
  }) => _serializeFinancialSave(() async {
    final saved = operationId == null
        ? null
        : _billsMap['bill_operation_$operationId'];
    if (saved != null) return saved;
    final record = _paymentMap[paymentId];
    if (record == null || !record.isPaid) {
      throw ArgumentError('No paid payment found for id $paymentId');
    }
    if (!amount.isFinite ||
        amount <= 0 ||
        record.balanceDue <= 0 ||
        amount > record.balanceDue + 0.005) {
      throw ArgumentError(
        'Enter a positive amount within the remaining balance.',
      );
    }
    final collected =
        amount > record.balanceDue ? record.balanceDue : amount;
    final effectivePaidAt = paidAt ?? DateTime.now();
    _validatePayment(
      collected,
      record.balanceDue,
      record.durationMonths,
      record.effectiveStartDate,
      record.effectiveEndDate,
      effectivePaidAt,
    );
    final customer = getCustomerById(record.customerId);

    final updated = record.copyWith(amount: record.amount + collected);
    final bill = BillRecord(
      id: operationId == null
          ? _newBillId(record.customerId)
          : 'bill_operation_$operationId',
      billNumber: generateBillNumber(record.monthYear),
      customerId: record.customerId,
      customerName: customer?.name ?? 'Member',
      customerPhone: customer?.phone ?? '',
      planType: customer?.planType ?? CustomerPlan.normal,
      monthYear: record.monthYear,
      amount: collected,
      paymentId: record.id,
      billType: 'BALANCE',
      method: method,
      paidAt: effectivePaidAt,
      startDate: record.startDate,
      endDate: record.endDate,
      notes: notes,
      transactionRef: transactionRef,
      gymName: _settings.gymName,
      issuedAt: DateTime.now(),
      status: 'PAID',
      durationMonths: record.durationMonths,
      coveragePeriod: record.formattedDateRange,
    );
    await _commitFinancialChange(updated, bill);

    return bill;
  });

  /// Updates an existing paid payment in place (same record id) and syncs its
  /// primary (non-BALANCE) bill in place, keeping the bill's id and billNumber.
  /// PAID BALANCE bills are untouched: the primary bill's amount becomes the
  /// record's paid amount minus what BALANCE bills already collected.
  Future<BillRecord> updatePayment({
    required String paymentId,
    double? amount,
    double? totalDue,
    PaymentMethod? method,
    DateTime? paidAt,
    DateTime? startDate,
    DateTime? endDate,
    int? durationMonths,
    String? notes,
    String? transactionRef,
  }) => _serializeFinancialSave(() async {
    final record = _paymentMap[paymentId];
    if (record == null || !record.isPaid) {
      throw ArgumentError('No paid payment found for id $paymentId');
    }

    final newStart = startDate ?? record.startDate;
    final newDuration = durationMonths ?? record.durationMonths;
    final DateTime? newEnd;
    if (endDate != null) {
      newEnd = endDate;
    } else if (startDate != null || durationMonths != null) {
      newEnd = newStart != null
          ? GymDateUtils.computeAnniversaryEndDate(newStart, newDuration)
          : null;
    } else {
      newEnd = record.endDate;
    }
    final newMonthYear = newStart != null && newStart != record.effectiveStartDate
        ? GymDateUtils.toMonthKey(newStart)
        : record.monthYear;

    var updated = record.copyWith(
      amount: amount,
      totalDue: totalDue,
      method: method,
      paidAt: paidAt,
      startDate: newStart,
      endDate: newEnd,
      durationMonths: durationMonths,
      notes: notes,
      transactionRef: transactionRef,
      monthYear: newMonthYear,
    );
    final financialEdit =
        updated.amount != record.amount ||
        updated.totalDue != record.totalDue ||
        updated.durationMonths != record.durationMonths ||
        updated.effectiveStartDate != record.effectiveStartDate ||
        updated.effectiveEndDate != record.effectiveEndDate ||
        updated.paidAt != record.paidAt;
    if (financialEdit) {
      _validatePayment(
        updated.amount,
        updated.totalDue,
        updated.durationMonths,
        updated.effectiveStartDate,
        updated.effectiveEndDate,
        updated.paidAt ?? DateTime.now(),
      );
    } else {
      updated = record.copyWith(
        method: method,
        notes: notes,
        transactionRef: transactionRef,
      );
    }
    final balanceReceipts = getBillsForPayment(paymentId)
        .where((b) => b.billType == 'BALANCE')
        .fold<double>(0, (sum, b) => sum + b.amount);
    if (financialEdit && updated.amount <= balanceReceipts) {
      throw ArgumentError(
        'The total received must include the original payment and all balance receipts.',
      );
    }
    final customer = getCustomerById(record.customerId);
    BillRecord bill;
    final existing = getBillForPayment(paymentId);
    if (existing != null && !financialEdit) {
      bill = existing.copyWith(
        method: updated.method,
        notes: updated.notes,
        transactionRef: updated.transactionRef,
      );
    } else if (existing != null) {
      var balanceCollected = 0.0;
      for (final b in _billsMap.values) {
        if (b.paymentId == paymentId &&
            b.status == 'PAID' &&
            b.billType == 'BALANCE') {
          balanceCollected += b.amount;
        }
      }
      final primaryAmount = updated.amount - balanceCollected;
      bill = existing.copyWith(
        amount: primaryAmount > 0 ? primaryAmount : 0.0,
        monthYear: updated.monthYear,
        billType: updated.balanceDue > 0 ? 'PARTIAL' : 'FULL',
        method: updated.method ?? existing.method,
        paidAt: updated.paidAt ?? existing.paidAt,
        startDate: updated.startDate,
        endDate: updated.endDate,
        durationMonths: updated.durationMonths,
        coveragePeriod: updated.formattedDateRange,
        notes: updated.notes,
        transactionRef: updated.transactionRef,
      );
    } else {
      bill = _buildPaidBill(
          customer ??
              Customer(
                id: record.customerId,
                name: 'Member',
                phone: '',
                joinDate: DateTime.now(),
              ),
          updated);
    }

    await _commitFinancialChange(updated, bill);

    return bill;
  });

  /// Removes a payment record entirely (pending state is derived, so nothing
  /// needs to be kept) and marks all of its bills CANCELLED. Bills are never
  /// deleted so bill numbers are never reissued.
  Future<void> revertPayment(String paymentId) async {
    final record = _paymentMap[paymentId];
    if (record == null) return;
    _paymentMap.remove(paymentId);

    final cancelled = <BillRecord>[];
    for (final entry in _billsMap.entries.toList()) {
      if (entry.value.paymentId == paymentId && entry.value.status != 'CANCELLED') {
        final c = entry.value.copyWith(status: 'CANCELLED');
        _billsMap[entry.key] = c;
        cancelled.add(c);
      }
    }

    await _queueChanges([
      CloudChange('payments', record.id, null),
      ...cancelled.map((b) => CloudChange('bills', b.id, b.toMap())),
    ]);
    notifyListeners();
    await _savePayments();
    await _saveBills();
  }

  /// Thin compatibility wrapper: resolves the payment covering [monthYear]
  /// and reverts it by id.
  Future<void> revertPaymentToPending(String customerId, String monthYear) async {
    final covering = getPaymentCoveringMonth(customerId, monthYear);
    if (covering != null) {
      await revertPayment(covering.id);
    }
  }

  /// Paid records (latest cycle start first) plus transient pending records for
  /// each month with unpaid attended days where no paid cycle starts.
  List<PaymentRecord> getCustomerPaymentHistory(String customerId) {
    final list = getPaidPaymentsForCustomer(customerId);
    for (final monthKey in getUnpaidAttendedMonthKeys(customerId)) {
      final hasCycleStartingHere = list.any((p) => p.monthYear == monthKey);
      if (!hasCycleStartingHere) {
        final rec = getPaymentRecord(customerId, monthKey);
        if (!rec.isPaid && !list.any((p) => p.id == rec.id)) {
          list.add(rec);
        }
      }
    }
    list.sort((a, b) => b.effectiveStartDate.compareTo(a.effectiveStartDate));
    return list;
  }

  Map<String, dynamic> getMonthlyFinancialSummary(String monthYear) {
    // Collected = all PAID bills paid within this calendar month
    // (includes BALANCE collections).
    double totalCollected = 0;
    for (final b in _billsMap.values) {
      if (b.status == 'PAID' && GymDateUtils.toMonthKey(b.paidAt) == monthYear) {
        totalCollected += b.amount;
      }
    }

    double totalPending = 0;
    int pendingCount = 0;
    final parts = monthYear.split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final groups = getPendingDuesByMonth(
          DateTime(y, m, 1), DateTime(y, m, GymDateUtils.daysInMonth(y, m)));
      for (final g in groups) {
        if (g.monthKey == monthYear) {
          totalPending += g.totalAmount;
          pendingCount += g.items.length;
        }
      }
    }

    int paidCount = 0;
    for (final customer in _customers) {
      if (customer.isActive &&
          isMonthCoveredByPaidPayment(customer.id, monthYear)) {
        paidCount++;
      }
    }

    return {
      'totalMembers': _customers.where((c) => c.isActive).length,
      'totalExpected': totalCollected + totalPending,
      'totalCollected': totalCollected,
      'totalPending': totalPending,
      'paidCount': paidCount,
      'pendingCount': pendingCount,
    };
  }

  // ==================== LEGACY MIGRATION ====================

  bool _migrating = false;

  @visibleForTesting
  bool get hasLegacyPaymentShapes => _hasLegacyPaymentShapes();

  /// Cheap detection of legacy payment/bill shapes needing migration.
  bool _hasLegacyPaymentShapes() {
    for (final p in _paymentMap.values) {
      if (p.isCoveredInPackage) return true;
      if (p.status != PaymentStatus.paid) return true;
      if (p.startDate == null ||
          p.monthYear != GymDateUtils.toMonthKey(p.effectiveStartDate)) {
        return true;
      }
    }
    for (final b in _billsMap.values) {
      if (b.paymentId.isEmpty) return true;
    }
    return false;
  }

  /// Idempotent migration to schema v2:
  /// 1. Drop ₹0 coveredByMonthYear placeholder records.
  /// 2. Drop stored pending/overdue records (pending is now derived).
  /// 3. Freeze start/end dates and fix the monthYear label on paid records.
  /// 4. Link legacy bills (empty paymentId) to their payment.
  /// 5. Re-key Firestore docs to record.id / bill.id; delete legacy doc ids.
  Future<void> _migrateLegacyPayments() async {
    if (_migrating) return;
    if (!_hasLegacyPaymentShapes()) return;
    _migrating = true;
    try {
      bool modified = false;
      final paymentsToUpsert = <PaymentRecord>[];
      final billsToUpsert = <BillRecord>[];
      final paymentDocsToDelete = <String>{};
      final billDocsToDelete = <String>{};

      // Steps 1 & 2: remove placeholders and stored pending/overdue records.
      for (final p in _paymentMap.values.toList()) {
        if (p.isCoveredInPackage || p.status != PaymentStatus.paid) {
          _paymentMap.remove(p.id);
          paymentDocsToDelete.add('${p.customerId}_${p.monthYear}');
          if (p.id != '${p.customerId}_${p.monthYear}') {
            paymentDocsToDelete.add(p.id);
          }
          modified = true;
        }
      }

      // Step 3: freeze dates + fix monthYear labels on remaining paid records.
      for (final p in _paymentMap.values.toList()) {
        final frozenStart = p.startDate ?? p.effectiveStartDate;
        final frozenEnd = p.endDate ?? p.effectiveEndDate;
        final correctMonth = GymDateUtils.toMonthKey(frozenStart);
        var migrated = p;
        if (p.startDate == null ||
            p.endDate == null ||
            p.monthYear != correctMonth) {
          migrated = p.copyWith(
            startDate: frozenStart,
            endDate: frozenEnd,
            monthYear: correctMonth,
          );
          _paymentMap[p.id] = migrated;
          modified = true;
        }
        paymentsToUpsert.add(migrated);
        final legacyDocId = '${p.customerId}_${p.monthYear}';
        if (legacyDocId != p.id) paymentDocsToDelete.add(legacyDocId);
      }

      // Step 4: link bills with empty paymentId to their payment.
      for (final b in _billsMap.values.toList()) {
        var migrated = b;
        if (b.paymentId.isEmpty) {
          PaymentRecord? linked;
          for (final p in _paymentMap.values) {
            if (p.customerId == b.customerId &&
                p.isPaid &&
                p.monthYear == b.monthYear) {
              linked = p;
              break;
            }
          }
          if (linked == null) {
            final monthStart = DateTime.tryParse('${b.monthYear}-01');
            if (monthStart != null) {
              for (final p in _paymentMap.values) {
                if (p.customerId == b.customerId && p.isPaid) {
                  if (!monthStart.isBefore(p.effectiveStartDate) &&
                      !monthStart.isAfter(p.effectiveEndDate)) {
                    linked = p;
                    break;
                  }
                }
              }
            }
          }
          migrated = b.copyWith(
            paymentId: linked?.id ?? 'legacy-unlinked',
            billType: 'FULL',
          );
          _billsMap[b.id] = migrated;
          modified = true;
        }
        billsToUpsert.add(migrated);
        final legacyDocId = '${b.customerId}_${b.monthYear}';
        if (legacyDocId != b.id) billDocsToDelete.add(legacyDocId);
      }

      if (modified) {
        await _savePayments();
        await _saveBills();
      }

      // Legacy re-keying uses the same durable upload queue.
      if (_syncQueue != null) {
        await _queueChanges([
          ...paymentsToUpsert.map(
            (p) => CloudChange('payments', p.id, p.toMap()),
          ),
          ...billsToUpsert.map((b) => CloudChange('bills', b.id, b.toMap())),
          ...paymentDocsToDelete.map((id) => CloudChange('payments', id, null)),
          ...billDocsToDelete.map((id) => CloudChange('bills', id, null)),
        ]);
      }
    } finally {
      _migrating = false;
    }
  }

  // ==================== PENDING RANGE OPERATIONS ====================

  DateTime get outstandingStartDate {
    final earliest = _duesIndex.earliest;
    return DateTime(earliest.year, earliest.month, 1);
  }

  List<MemberPendingSummary> getAllPendingDues() =>
      getPendingDuesByMember(outstandingStartDate, outstandingEndDate);

  DateTime get outstandingEndDate {
    final latest = _duesIndex.latest;
    return DateTime(latest.year, latest.month + 1, 0);
  }

  List<String> getMonthKeysInRange(DateTime start, DateTime end) {
    final effectiveStart = start.isBefore(end) ? start : end;
    final effectiveEnd = start.isBefore(end) ? end : start;

    final list = <String>[];
    var cur = DateTime(effectiveStart.year, effectiveStart.month, 1);
    final last = DateTime(effectiveEnd.year, effectiveEnd.month, 1);

    while (!cur.isAfter(last)) {
      list.add(GymDateUtils.toMonthKey(cur));
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
    return list;
  }

  /// Returns outstanding debt, including archived members, in the date range.
  List<MemberPendingSummary> getPendingDuesByMember(DateTime start, DateTime end) {
    final index = _duesIndex;
    final monthKeys = getMonthKeysInRange(start, end);
    final rangeKey = '${monthKeys.first}:${monthKeys.last}';
    final cached = _pendingByRange[rangeKey];
    if (cached != null) return List.of(cached);
    final results = <MemberPendingSummary>[];

    for (final customer in _customers) {
      final pendingRecords = <PaymentRecord>[];
      for (final monthKey in monthKeys) {
        if (index.unpaid[customer.id]?[monthKey]?.isNotEmpty ?? false) {
          final record = getPaymentRecord(customer.id, monthKey);
          pendingRecords.add(record);
        }
      }

      // Partial balances: paid cycles with an outstanding balance whose
      // start month falls inside the range still owe money.
      for (final p in index.payments[customer.id] ?? <PaymentRecord>[]) {
        if (p.balanceDue > 0 &&
            monthKeys.contains(p.monthYear)) {
          pendingRecords.add(p);
        }
      }

      if (pendingRecords.isNotEmpty) {
        final total = pendingRecords.fold<double>(0.0, (sum, r) => sum + pendingAmountOf(r));
        results.add(MemberPendingSummary(
          customer: customer,
          pendingRecords: List.unmodifiable(pendingRecords),
          totalPendingAmount: total,
        ));
      }
    }

    _pendingByRange[rangeKey] = List.unmodifiable(results);
    return List.of(results);
  }

  /// Returns pending dues grouped by each month in the date range.
  List<MonthPendingGroup> getPendingDuesByMonth(DateTime start, DateTime end) {
    final byMonth = <String, List<MonthPendingItem>>{};
    for (final member in getPendingDuesByMember(start, end)) {
      for (final payment in member.pendingRecords) {
        (byMonth[payment.monthYear] ??= []).add(
          MonthPendingItem(customer: member.customer, payment: payment),
        );
      }
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final month in months)
        MonthPendingGroup(
          monthKey: month,
          items: List.unmodifiable(byMonth[month]!),
          totalAmount: byMonth[month]!.fold<double>(
            0,
            (sum, item) => sum + pendingAmountOf(item.payment),
          ),
        ),
    ];
  }

  // ==================== SETTINGS OPERATIONS ====================

  Future<void> updateSettings(GymSettings newSettings) async {
    _settings = newSettings;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> updateGymLogo(String? logoPath) async {
    _settings = _settings.copyWith(
      gymLogoPath: logoPath,
      clearGymLogo: logoPath == null || logoPath.isEmpty,
    );
    notifyListeners();
    await _saveSettings();
  }

  Future<void> updateStandardMonthlyFee(double fee) async {
    _settings = _settings.copyWith(standardMonthlyFee: fee);
    notifyListeners();
    await _saveSettings();
  }

  // ==================== EXPENSE OPERATIONS ====================

  Future<void> addExpense({
    required String title,
    required double amount,
    required ExpenseCategory category,
    required DateTime date,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? receiptImagePath,
    String? notes,
  }) async {
    final newId = 'exp_${DateTime.now().millisecondsSinceEpoch}';
    final expense = ExpenseRecord(
      id: newId,
      title: title.trim(),
      amount: amount,
      category: category,
      date: date,
      monthYear: GymDateUtils.toMonthKey(date),
      paymentMethod: paymentMethod,
      receiptPath: receiptImagePath,
      notes: notes?.trim(),
    );
    _expenses.insert(0, expense);
    await _cloudSaveExpense(expense);
    notifyListeners();
    await _saveExpenses();
  }

  Future<void> updateExpense(ExpenseRecord updated) async {
    final index = _expenses.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      _expenses[index] = updated;
      await _cloudSaveExpense(updated);
      notifyListeners();
      await _saveExpenses();
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    _expenses.removeWhere((e) => e.id == expenseId);
    await _cloudDeleteExpense(expenseId);
    notifyListeners();
    await _saveExpenses();
  }

  List<ExpenseRecord> getMonthlyExpenses(String monthYear) {
    final list = _expenses.where((e) {
      final mKey = GymDateUtils.toMonthKey(e.date);
      return mKey == monthYear;
    }).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double getTotalExpenseAmount(String monthYear) {
    return getMonthlyExpenses(monthYear)
        .fold<double>(0.0, (sum, e) => sum + e.amount);
  }

  Map<ExpenseCategory, double> getExpenseCategoryBreakdown(String monthYear) {
    final monthly = getMonthlyExpenses(monthYear);
    final breakdown = <ExpenseCategory, double>{};
    for (final exp in monthly) {
      breakdown[exp.category] = (breakdown[exp.category] ?? 0.0) + exp.amount;
    }
    return breakdown;
  }

  Map<String, dynamic> getBalanceSheetSummary(String monthYear) {
    final finSummary = getMonthlyFinancialSummary(monthYear);
    final totalCollected = (finSummary['totalCollected'] as num?)?.toDouble() ?? 0.0;
    final totalExpense = getTotalExpenseAmount(monthYear);
    final netProfit = totalCollected - totalExpense;
    final profitMargin = totalCollected > 0 ? (netProfit / totalCollected) * 100 : 0.0;

    return {
      'monthYear': monthYear,
      'totalIncome': totalCollected,
      'totalExpense': totalExpense,
      'netProfit': netProfit,
      'profitMargin': profitMargin,
      'isProfit': netProfit >= 0,
      'categoryBreakdown': getExpenseCategoryBreakdown(monthYear),
      'expensesCount': getMonthlyExpenses(monthYear).length,
    };
  }

  Map<String, dynamic> getBalanceSheetKPIs(String monthYear) {
    final curSummary = getBalanceSheetSummary(monthYear);
    final finSummary = getMonthlyFinancialSummary(monthYear);

    final double totalIncome = curSummary['totalIncome'] as double;
    final double totalExpense = curSummary['totalExpense'] as double;
    final double netProfit = curSummary['netProfit'] as double;
    final double profitMargin = curSummary['profitMargin'] as double;
    final int paidCount = finSummary['paidCount'] as int;
    final int pendingCount = finSummary['pendingCount'] as int;
    final int totalActiveMembers = _customers.where((c) => c.isActive).length;

    // 1. ARPM (Average Revenue Per Paying Member)
    final double arpm = paidCount > 0 ? (totalIncome / paidCount) : 0.0;

    // 2. Average Operating Cost Per Active Member
    final double costPerMember = totalActiveMembers > 0 ? (totalExpense / totalActiveMembers) : 0.0;

    // 3. Operating Expense Ratio (OER): (Expenses / Income) * 100
    final double oer = totalIncome > 0 ? (totalExpense / totalIncome) * 100 : 0.0;

    // 4. Break-Even Analysis
    double avgMemberPlanFee = _settings.standardMonthlyFee;
    if (_customers.isNotEmpty) {
      double sumFees = 0;
      int count = 0;
      for (final c in _customers) {
        if (c.isActive) {
          sumFees += _settings.getPriceForDuration(c.planType, 1);
          count++;
        }
      }
      if (count > 0) {
        avgMemberPlanFee = sumFees / count;
      }
    }
    final int breakEvenMembers = avgMemberPlanFee > 0 ? (totalExpense / avgMemberPlanFee).ceil() : 0;
    final int memberBuffer = totalActiveMembers - breakEvenMembers;
    final double breakEvenLoadPct = totalActiveMembers > 0 ? (breakEvenMembers / totalActiveMembers) * 100 : 0.0;

    // 5. Fixed vs Variable Cost Breakdown
    // Fixed: Rent, Trainer Salaries, Electricity
    // Variable: Equipment maintenance, Cleaning, Marketing, Supplements, Misc
    final breakdown = curSummary['categoryBreakdown'] as Map<ExpenseCategory, double>;
    double fixedCosts = 0.0;
    double variableCosts = 0.0;

    for (final entry in breakdown.entries) {
      if (entry.key == ExpenseCategory.rent ||
          entry.key == ExpenseCategory.trainerSalaries ||
          entry.key == ExpenseCategory.electricity) {
        fixedCosts += entry.value;
      } else {
        variableCosts += entry.value;
      }
    }
    final double fixedCostPct = totalExpense > 0 ? (fixedCosts / totalExpense) * 100 : 0.0;
    final double variableCostPct = totalExpense > 0 ? (variableCosts / totalExpense) * 100 : 0.0;

    // 6. Month-Over-Month (MoM) Growth Comparison
    final parts = monthYear.split('-');
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final prevMonthDt = DateTime(year, month - 1, 1);
    final prevMonthKey = GymDateUtils.toMonthKey(prevMonthDt);

    final prevSummary = getBalanceSheetSummary(prevMonthKey);
    final double prevIncome = prevSummary['totalIncome'] as double;
    final double prevExpense = prevSummary['totalExpense'] as double;
    final double prevProfit = prevSummary['netProfit'] as double;

    double revenueGrowthMoM = 0.0;
    if (prevIncome > 0) {
      revenueGrowthMoM = ((totalIncome - prevIncome) / prevIncome) * 100;
    }

    double expenseGrowthMoM = 0.0;
    if (prevExpense > 0) {
      expenseGrowthMoM = ((totalExpense - prevExpense) / prevExpense) * 100;
    }

    double profitGrowthMoM = 0.0;
    if (prevProfit.abs() > 0) {
      profitGrowthMoM = ((netProfit - prevProfit) / prevProfit.abs()) * 100;
    }

    // 7. Health Rating & Insights
    String healthTier; // 'exceptional', 'healthy', 'moderate', 'tight', 'deficit', 'none'
    String healthTitle;
    String healthAdvice;

    if (totalIncome == 0 && totalExpense == 0) {
      healthTier = 'none';
      healthTitle = 'No Financial Activity';
      healthAdvice = 'Record member payments and gym expenses to unlock financial intelligence.';
    } else if (netProfit < 0) {
      healthTier = 'deficit';
      healthTitle = 'Operating Deficit';
      healthAdvice = 'Expenses exceed income by ${GymDateUtils.formatCurrency(netProfit.abs(), symbol: _settings.currencySymbol)}. Focus on renewing $pendingCount pending members or reducing variable overheads.';
    } else if (profitMargin < 15) {
      healthTier = 'tight';
      healthTitle = 'Tight Operating Margins';
      healthAdvice = 'Net margin is ${profitMargin.toStringAsFixed(1)}%. Target adding at least ${breakEvenMembers > totalActiveMembers ? breakEvenMembers - totalActiveMembers : 2} more members to create a secure buffer.';
    } else if (profitMargin < 35) {
      healthTier = 'healthy';
      healthTitle = 'Healthy & Sustainable';
      healthAdvice = 'Strong financial health with ${profitMargin.toStringAsFixed(1)}% profit margin. ARPM is ${GymDateUtils.formatCurrency(arpm, symbol: _settings.currencySymbol)} across $paidCount paying members.';
    } else {
      healthTier = 'exceptional';
      healthTitle = 'High Profitability';
      healthAdvice = 'Superb profitability (${profitMargin.toStringAsFixed(1)}% margin). Surplus can be strategically reinvested in equipment upgrades or marketing.';
    }

    return {
      'monthYear': monthYear,
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'netProfit': netProfit,
      'profitMargin': profitMargin,
      'isProfit': netProfit >= 0,
      'paidCount': paidCount,
      'pendingCount': pendingCount,
      'totalActiveMembers': totalActiveMembers,
      'arpm': arpm,
      'costPerMember': costPerMember,
      'oer': oer,
      'avgMemberPlanFee': avgMemberPlanFee,
      'breakEvenMembers': breakEvenMembers,
      'memberBuffer': memberBuffer,
      'breakEvenLoadPct': breakEvenLoadPct,
      'fixedCosts': fixedCosts,
      'variableCosts': variableCosts,
      'fixedCostPct': fixedCostPct,
      'variableCostPct': variableCostPct,
      'prevIncome': prevIncome,
      'prevExpense': prevExpense,
      'prevProfit': prevProfit,
      'revenueGrowthMoM': revenueGrowthMoM,
      'expenseGrowthMoM': expenseGrowthMoM,
      'profitGrowthMoM': profitGrowthMoM,
      'healthTier': healthTier,
      'healthTitle': healthTitle,
      'healthAdvice': healthAdvice,
    };
  }

  // ==================== EXPIRY FUNNEL & DASHBOARD METRICS ====================

  /// Checks if a customer has ever had a paid membership
  bool hasPaidMembership(Customer customer) {
    return _paymentMap.values.any((p) => p.customerId == customer.id && p.isPaid);
  }

  DateTime getCustomerExpiryDate(Customer customer) {
    final paidPayments = _paymentMap.values
        .where((p) => p.customerId == customer.id && p.isPaid)
        .toList();

    if (paidPayments.isEmpty) {
      // Customer has never paid: membership validity has not started
      return customer.joinDate.subtract(const Duration(days: 1));
    }

    DateTime latestExpiry = paidPayments.first.effectiveEndDate;
    for (final p in paidPayments) {
      final coverageEnd = p.effectiveEndDate;
      if (coverageEnd.isAfter(latestExpiry)) {
        latestExpiry = coverageEnd;
      }
    }

    return latestExpiry;
  }

  int getDaysUntilExpiry(Customer customer) {
    final expiry = getCustomerExpiryDate(customer);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    return expiryDay.difference(today).inDays;
  }

  Map<String, dynamic> getMembershipExpirySummary() {
    final now = DateTime.now();
    final currentMonthKey = GymDateUtils.toMonthKey(now);
    final todayKey = GymDateUtils.toDateKey(now);

    final liveMembers = <Customer>[];
    final expiring1to3 = <Customer>[];
    final expiring4to7 = <Customer>[];
    final expiring8to15 = <Customer>[];
    final expiredMembers = <Customer>[];

    for (final c in _customers) {
      if (!c.isActive) continue;
      final stage = getMemberLifecycleStage(c, currentMonthKey);
      if (stage == MemberLifecycleStage.newMember) {
        continue; // Unpaid new member in onboarding grace period
      }

      final days = getDaysUntilExpiry(c);
      if (days < 0) {
        expiredMembers.add(c);
      } else if (days <= 3) {
        expiring1to3.add(c);
      } else if (days <= 7) {
        expiring4to7.add(c);
      } else if (days <= 15) {
        expiring8to15.add(c);
      } else {
        liveMembers.add(c);
      }
    }

    // Today's collections (PAID bills — includes BALANCE collections)
    double todayCollection = 0;
    for (final b in _billsMap.values) {
      if (b.status == 'PAID' &&
          GymDateUtils.toDateKey(b.paidAt) == todayKey) {
        todayCollection += b.amount;
      }
    }

    // Today's expenses
    double todayExpense = 0;
    for (final exp in _expenses) {
      if (GymDateUtils.toDateKey(exp.date) == todayKey) {
        todayExpense += exp.amount;
      }
    }

    // Include older debts and archived members' unpaid receipt balances.
    final pendingSummaries = getAllPendingDues();
    double totalDues = 0;
    for (final s in pendingSummaries) {
      totalDues += s.totalPendingAmount;
    }

    final balanceSheet = getBalanceSheetSummary(currentMonthKey);

    return {
      'live': liveMembers,
      'expiring1to3': expiring1to3,
      'expiring4to7': expiring4to7,
      'expiring8to15': expiring8to15,
      'expired': expiredMembers,
      'totalActive': _customers.where((c) => c.isActive).length,
      'todayCollection': todayCollection,
      'todayExpense': todayExpense,
      'totalDues': totalDues,
      'currentMonthProfit': balanceSheet['netProfit'],
      'currentMonthIncome': balanceSheet['totalIncome'],
      'currentMonthExpense': balanceSheet['totalExpense'],
    };
  }

  // ==================== PERSISTENCE ====================
  //
  // Each _save method writes to local SharedPreferences (offline cache)
  // AND dispatches the write to Firestore (cloud sync).

  Future<void> _saveCustomers() async {
    final key = _customerKey(_currentUserId);
    final data = json.encode(_customers.map((c) => c.toMap()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _saveExpenses() async {
    final key = _expensesKey(_currentUserId);
    final data = json.encode(_expenses.map((e) => e.toMap()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _saveAttendance() async {
    final key = _attendanceKey(_currentUserId);
    final data = json.encode(
      _attendanceMap.values.map((a) => a.toMap()).toList(),
    );
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _savePayments() async {
    await _saveFinancialSnapshot(_paymentMap, _billsMap);
    final key = _paymentsKey(_currentUserId);
    final data = json.encode(_paymentMap.values.map((p) => p.toMap()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _saveBills() async {
    final key = _billsKey(_currentUserId);
    final data = json.encode(_billsMap.values.map((b) => b.toMap()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _saveSettingsLocallyOnly() async {
    final key = _settingsKey(_currentUserId);
    final data = _settings.toJson();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data)) {
      throw StateError('Could not save on this phone.');
    }
  }

  Future<void> _saveSettings() async {
    await _queueChanges([CloudChange('settings', 'config', _settings.toMap())]);
    await _saveSettingsLocallyOnly();
  }

  Future<void> _saveAll() async {
    await _saveCustomers();
    await _saveExpenses();
    await _saveAttendance();
    await _savePayments();
    await _saveBills();
    await _saveSettings();
  }

  /// Completely clears all gym members, attendance, payments, bills, and expenses.
  /// Gives the gym owner a clean, fresh start.
  Future<void> clearAllGymData() async {
    if (_currentUserId != null) {
      // Collection deletion spans several server batches and cannot be safely
      // undone. Keep the local reset action out of live owner accounts.
      throw StateError(
        'Clearing a live gym account is unavailable. Archive members to preserve their history.',
      );
    }
    _customers.clear();
    _expenses.clear();
    _attendanceMap.clear();
    _paymentMap.clear();
    _billsMap.clear();
    notifyListeners();

    if (_isCloudAttached) {
      _suppressCloudUpdates = true;
      await FirestoreService().clearAllData();
      // Keep gym settings in cloud so gym name and configuration remain intact
      await FirestoreService().upsertSettings(_settings);
      _suppressCloudUpdates = false;
    }

    await _saveCustomers();
    await _saveAttendance();
    await _savePayments();
    await _saveBills();
    await _saveExpenses();
  }

  Future<void> _cloudSaveCustomer(Customer c) =>
      _queueChanges([CloudChange('customers', c.id, c.toMap())]);
  Future<void> _cloudSaveAttendance(AttendanceRecord r) => _queueChanges([
    CloudChange('attendance', _attKey(r.customerId, r.dateKey), r.toMap()),
  ]);
  Future<void> _cloudBatchSaveAttendance(List<AttendanceRecord> records) =>
      _queueChanges(
        records
            .map(
              (r) => CloudChange(
                'attendance',
                _attKey(r.customerId, r.dateKey),
                r.toMap(),
              ),
            )
            .toList(),
      );
  Future<void> _cloudSaveBill(BillRecord b) =>
      _queueChanges([CloudChange('bills', b.id, b.toMap())]);
  Future<void> _cloudSaveExpense(ExpenseRecord e) =>
      _queueChanges([CloudChange('expenses', e.id, e.toMap())]);
  Future<void> _cloudDeleteExpense(String id) =>
      _queueChanges([CloudChange('expenses', id, null)]);
  Future<void> resetToDemoData() async {
    if (_currentUserId != null) {
      throw StateError(
        'Demo data is only available in local exploration mode.',
      );
    }
    _customers.clear();
    _expenses.clear();
    _attendanceMap.clear();
    _paymentMap.clear();
    _billsMap.clear();
    _settings = const GymSettings();
    _seedDemoData();
    _seedDemoExpenses();
    notifyListeners();
    // Clear cloud data and re-upload demo
    if (_isCloudAttached) {
      _suppressCloudUpdates = true;
      await FirestoreService().clearAllData();
      await FirestoreService().migrateLocalData(
        customers: _customers,
        attendanceMap: _attendanceMap,
        paymentMap: _paymentMap,
        billsMap: _billsMap,
        expenses: _expenses,
        settings: _settings,
      );
      _suppressCloudUpdates = false;
    }
    await _saveAll();
  }

  // ==================== DEMO DATA SEEDING ====================

  void _seedDemoData() {
    final now = DateTime.now();

    _customers = [
      Customer(
        id: 'cust_1',
        name: 'Rahul Sharma',
        phone: '+91 98765 43210',
        imagePath: 'avatar:1',
        joinDate: DateTime(now.year, now.month - 3, 10),
        isActive: true,
        notes: 'Personal training client. Prefers morning workout.',
        planType: CustomerPlan.personalTraining,
        planDurationMonths: 3,
      ),
      Customer(
        id: 'cust_2',
        name: 'Pooja Patel',
        phone: '+91 98123 45678',
        imagePath: 'avatar:2',
        joinDate: DateTime(now.year, now.month - 2, 5),
        isActive: true,
        notes: 'Cardio & Strength training.',
        planType: CustomerPlan.normal,
        planDurationMonths: 1,
      ),
      Customer(
        id: 'cust_3',
        name: 'Vikram Singh',
        phone: '+91 97654 32109',
        imagePath: 'avatar:3',
        joinDate: DateTime(now.year, now.month - 4, 18),
        isActive: true,
        notes: 'Powerlifting focus.',
        planType: CustomerPlan.personalTrainingDiet,
        planDurationMonths: 6,
      ),
      Customer(
        id: 'cust_4',
        name: 'Ananya Verma',
        phone: '+91 99887 76655',
        imagePath: 'avatar:4',
        joinDate: DateTime(now.year, now.month - 1, 2),
        isActive: true,
        notes: 'Evening slot.',
        planType: CustomerPlan.normal,
        planDurationMonths: 12,
      ),
      Customer(
        id: 'cust_5',
        name: 'Karan Malhotra',
        phone: '+91 98234 56789',
        imagePath: 'avatar:5',
        joinDate: DateTime(now.year, now.month - 5, 25),
        isActive: true,
        notes: 'CrossFit enthusiast.',
        planType: CustomerPlan.personalTraining,
        planDurationMonths: 1,
      ),
      Customer(
        id: 'cust_6',
        name: 'Sneha Reddy',
        phone: '+91 91234 56780',
        imagePath: 'avatar:6',
        joinDate: DateTime(now.year, now.month - 2, 14),
        isActive: true,
        notes: 'HIIT and functional training.',
        planType: CustomerPlan.personalTrainingDiet,
        planDurationMonths: 3,
      ),
    ];

    // Seed realistic attendance for the current month up to today
    final currentDay = now.day;
    for (int day = 1; day <= currentDay; day++) {
      final date = DateTime(now.year, now.month, day);
      final dateKey = GymDateUtils.toDateKey(date);

      // Skip Sundays as rest days
      final isSunday = date.weekday == DateTime.sunday;

      for (var c in _customers) {
        if (isSunday) {
          _attendanceMap[_attKey(c.id, dateKey)] = AttendanceRecord(
            id: 'att_${c.id}_$dateKey',
            customerId: c.id,
            dateKey: dateKey,
            status: AttendanceStatus.rest,
            recordedAt: date,
          );
        } else {
          // Semi-random deterministic attendance
          final isPresent = (c.id.hashCode + day) % 3 != 0;
          _attendanceMap[_attKey(c.id, dateKey)] = AttendanceRecord(
            id: 'att_${c.id}_$dateKey',
            customerId: c.id,
            dateKey: dateKey,
            status: isPresent ? AttendanceStatus.present : AttendanceStatus.absent,
            recordedAt: date,
          );
        }
      }
    }

    // Seed payments for previous month (all paid, unique ids, explicit ranges)
    void demoPaid({
      required String customerId,
      required double amount,
      required PaymentMethod method,
      required DateTime paidAt,
      int durationMonths = 1,
      String? transactionRef,
      String? notes,
    }) {
      final start = DateTime(paidAt.year, paidAt.month, paidAt.day);
      final end = GymDateUtils.computeAnniversaryEndDate(start, durationMonths);
      final record = PaymentRecord(
        id: 'pay_${customerId}_${paidAt.millisecondsSinceEpoch}',
        customerId: customerId,
        monthYear: GymDateUtils.toMonthKey(start),
        amount: amount,
        totalDue: amount,
        status: PaymentStatus.paid,
        method: method,
        paidAt: paidAt,
        startDate: start,
        endDate: end,
        durationMonths: durationMonths,
        transactionRef: transactionRef,
        notes: notes,
      );
      _paymentMap[record.id] = record;
    }

    demoPaid(
      customerId: 'cust_1',
      amount: 1200,
      method: PaymentMethod.gpay,
      paidAt: DateTime(now.year, now.month - 1, 5),
      transactionRef: 'UPI-789234812',
    );
    demoPaid(
      customerId: 'cust_2',
      amount: 1200,
      method: PaymentMethod.cash,
      paidAt: DateTime(now.year, now.month - 1, 3),
    );
    demoPaid(
      customerId: 'cust_3',
      amount: 2500,
      method: PaymentMethod.upi,
      paidAt: DateTime(now.year, now.month - 1, 5),
    );
    demoPaid(
      customerId: 'cust_4',
      amount: 1200,
      method: PaymentMethod.phonepe,
      paidAt: DateTime(now.year, now.month - 1, 7),
    );

    // Seed payments for current month
    // Rahul: Paid with GPay
    demoPaid(
      customerId: 'cust_1',
      amount: 1200,
      method: PaymentMethod.gpay,
      paidAt: DateTime(now.year, now.month, 4),
      transactionRef: 'UPI-98210344',
      notes: 'Paid via GPay QR at front desk',
    );

    // Pooja: Paid with Cash
    demoPaid(
      customerId: 'cust_2',
      amount: 1200,
      method: PaymentMethod.cash,
      paidAt: DateTime(now.year, now.month, 6),
      notes: 'Received by coach',
    );

    // Ananya: Paid with PhonePe
    demoPaid(
      customerId: 'cust_4',
      amount: 1200,
      method: PaymentMethod.phonepe,
      paidAt: DateTime(now.year, now.month, 8),
      transactionRef: 'PP-459201948',
    );

    // Vikram, Karan, Sneha have no payment for the current month —
    // pending dues are derived from attendance, nothing is stored.
  }

  void _seedDemoExpenses() {
    final now = DateTime.now();
    final curMonth = GymDateUtils.toMonthKey(now);
    final prevMonthDt = DateTime(now.year, now.month - 1, 1);
    final prevMonth = GymDateUtils.toMonthKey(prevMonthDt);

    _expenses = [
      // Previous Month Baseline Expenses (for MoM tracking)
      ExpenseRecord(
        id: 'exp_demo_prev_1',
        title: 'Gym Rent - Previous Month',
        amount: 25000.0,
        category: ExpenseCategory.rent,
        date: DateTime(prevMonthDt.year, prevMonthDt.month, 1),
        monthYear: prevMonth,
        paymentMethod: PaymentMethod.netBanking,
        notes: 'Monthly property lease payment',
      ),
      ExpenseRecord(
        id: 'exp_demo_prev_2',
        title: 'Electricity & AC Bill - Previous Month',
        amount: 5900.0,
        category: ExpenseCategory.electricity,
        date: DateTime(prevMonthDt.year, prevMonthDt.month, 5),
        monthYear: prevMonth,
        paymentMethod: PaymentMethod.gpay,
        notes: 'Commercial meter power bill',
      ),
      ExpenseRecord(
        id: 'exp_demo_prev_3',
        title: 'Trainer Salaries - Previous Month',
        amount: 18000.0,
        category: ExpenseCategory.trainerSalaries,
        date: DateTime(prevMonthDt.year, prevMonthDt.month, 7),
        monthYear: prevMonth,
        paymentMethod: PaymentMethod.netBanking,
        notes: 'Floor coach monthly payout',
      ),

      // Current Month Expenses
      ExpenseRecord(
        id: 'exp_demo_1',
        title: 'Gym Rent - Current Month',
        amount: 25000.0,
        category: ExpenseCategory.rent,
        date: DateTime(now.year, now.month, 1),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.netBanking,
        notes: 'Monthly property lease payment',
      ),
      ExpenseRecord(
        id: 'exp_demo_2',
        title: 'Electricity & AC Bill',
        amount: 6500.0,
        category: ExpenseCategory.electricity,
        date: DateTime(now.year, now.month, 5),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.gpay,
        notes: 'Commercial meter power bill',
      ),
      ExpenseRecord(
        id: 'exp_demo_3',
        title: 'Trainer Salaries (Senior Coach)',
        amount: 18000.0,
        category: ExpenseCategory.trainerSalaries,
        date: DateTime(now.year, now.month, 7),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.netBanking,
        notes: 'Floor coach monthly payout',
      ),
      ExpenseRecord(
        id: 'exp_demo_4',
        title: 'Treadmill Belt & Cable Maintenance',
        amount: 2200.0,
        category: ExpenseCategory.equipmentMaintenance,
        date: DateTime(now.year, now.month, 10),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.cash,
        notes: 'Lubrication and cable replacement',
      ),
      ExpenseRecord(
        id: 'exp_demo_5',
        title: 'Cleaning Supplies & Sanitizers',
        amount: 1450.0,
        category: ExpenseCategory.cleaningSupplies,
        date: DateTime(now.year, now.month, 12),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.phonepe,
        notes: 'Floor cleaner, spray bottles, wipes',
      ),
      ExpenseRecord(
        id: 'exp_demo_6',
        title: 'Whey Protein & Shaker Stock',
        amount: 8500.0,
        category: ExpenseCategory.supplements,
        date: DateTime(now.year, now.month, 14),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.paytm,
        notes: 'Wholesale supplement inventory',
      ),
      ExpenseRecord(
        id: 'exp_demo_7',
        title: 'Instagram Local Ads & Pamphlets',
        amount: 2000.0,
        category: ExpenseCategory.marketing,
        date: DateTime(now.year, now.month, 15),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.card,
        notes: 'Meta targeted promo campaign',
      ),
      ExpenseRecord(
        id: 'exp_demo_8',
        title: 'Drinking Water Dispensers & First Aid',
        amount: 750.0,
        category: ExpenseCategory.misc,
        date: DateTime(now.year, now.month, 18),
        monthYear: curMonth,
        paymentMethod: PaymentMethod.cash,
        notes: 'Bisleri 20L jars + bandages',
      ),
    ];
  }
}
