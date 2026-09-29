import 'dart:convert';
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
  bool _isInitialized = false;
  bool _isCloudAttached = false;
  bool _isMigratedToCloud = false;
  bool _suppressCloudUpdates = false; // Prevents re-entrant updates during local writes

  List<Customer> get customers => List.unmodifiable(_customers);
  List<ExpenseRecord> get expenses => List.unmodifiable(_expenses);
  Map<String, BillRecord> get billsMap => Map.unmodifiable(_billsMap);
  GymSettings get settings => _settings;

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

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

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

      if (prefs.getBool(_keyPaymentsSchemaV2) != true) {
        await _migrateLegacyPayments();
        await prefs.setBool(_keyPaymentsSchemaV2, true);
      }

      final expensesJson = prefs.getString(_keyExpenses);
      if (expensesJson != null) {
        final list = json.decode(expensesJson) as List<dynamic>;
        _expenses = list
            .map((item) => ExpenseRecord.fromMap(item as Map<String, dynamic>))
            .toList();
      }

    } catch (e) {
      debugPrint('Error initializing GymService: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  // ==================== CLOUD LIFECYCLE ====================

  /// Attach Firestore sync for the authenticated user.
  /// Call this after successful login.
  Future<void> attachUser(String userId) async {
    if (_isCloudAttached) return;

    await FirestoreService().attachUser(userId, callback: _onFirestoreData);
    _isCloudAttached = true;

    // Auto-migrate local data to cloud if this is the first time
    await migrateLocalDataToCloud();

    notifyListeners();
  }

  /// Detach Firestore sync. Call this on logout.
  Future<void> detachUser() async {
    await FirestoreService().detachUser();
    _isCloudAttached = false;
    _isMigratedToCloud = false;
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
      _customers = customers;
      changed = true;
    }
    if (attendanceMap != null) {
      _attendanceMap = attendanceMap;
      changed = true;
    }
    if (paymentMap != null) {
      _paymentMap = paymentMap;
      changed = true;
    }
    if (billsMap != null) {
      _billsMap = billsMap;
      changed = true;
    }
    if (expenses != null) {
      _expenses = expenses;
      changed = true;
    }
    if (settings != null) {
      _settings = settings;
      changed = true;
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
    final newId = 'cust_${DateTime.now().millisecondsSinceEpoch}';
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
    await _cloudSaveCustomer(customer);

    return customer;
  }

  /// Checks whether a specific attendance dateKey (yyyy-MM-dd) is covered by any valid paid payment.
  bool isDateCoveredByPayment(String customerId, String dateKey) {
    final date = DateTime.tryParse(dateKey);
    if (date == null) return false;
    final targetDay = DateTime(date.year, date.month, date.day);

    for (final p in _paymentMap.values) {
      if (p.customerId == customerId && p.isPaid) {
        final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
        final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);
        if (!targetDay.isBefore(start) && !targetDay.isAfter(end)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns the count of attended (present) days in a month that have NOT been covered by any paid payment.
  int getUnpaidAttendedDaysInMonth(String customerId, String monthKey) {
    int count = 0;
    for (final record in _attendanceMap.values) {
      if (record.customerId == customerId &&
          record.status == AttendanceStatus.present &&
          record.dateKey.startsWith(monthKey)) {
        if (!isDateCoveredByPayment(customerId, record.dateKey)) {
          count++;
        }
      }
    }
    return count;
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
    for (final p in _paymentMap.values) {
      if (p.customerId == customerId && p.isPaid) {
        final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
        final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);
        if (!start.isAfter(monthEnd) && !end.isBefore(monthStart)) {
          covering.add(p);
        }
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
    // 1. Check if a paid payment covers this month
    final parts = monthYear.split('-');
    if (parts.length == 2) {
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
              if (!end.isBefore(today)) {
                return MemberLifecycleStage.paid;
              }
            } else {
              return MemberLifecycleStage.paid;
            }
          }
        }
      }
    }

    // 2. If month is before the customer joined and not paid, they weren't enrolled yet
    final joinMonthKey = GymDateUtils.toMonthKey(customer.joinDate);
    if (monthYear.compareTo(joinMonthKey) < 0) {
      return MemberLifecycleStage.notEnrolled;
    }

    // 3. If this month has any attended days that are NOT covered by payment -> DUE!
    final unpaidAttendedDays = getUnpaidAttendedDaysInMonth(customer.id, monthYear);
    if (unpaidAttendedDays > 0) {
      return MemberLifecycleStage.due;
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

      notifyListeners();
      await _saveCustomers();
      await _cloudSaveCustomer(updated);
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    _customers.removeWhere((c) => c.id == customerId);
    _attendanceMap.removeWhere((k, v) => v.customerId == customerId);
    _paymentMap.removeWhere((k, v) => v.customerId == customerId);
    notifyListeners();
    await _saveAll();
    await _cloudDeleteCustomer(customerId);
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

  Future<void> toggleAttendance(String customerId, String dateKey, AttendanceStatus status) async {
    final date = DateTime.tryParse(dateKey);
    if (date != null) {
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

    if (existing != null && existing.status == status) {
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

    notifyListeners();
    await _saveAttendance();
    await _cloudSaveAttendance(_attendanceMap[key]!);
  }

  Future<void> markTodayQuickAttendance(String customerId, bool present) async {
    final todayKey = GymDateUtils.toDateKey(DateTime.now());
    await toggleAttendance(
      customerId,
      todayKey,
      present ? AttendanceStatus.present : AttendanceStatus.absent,
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
      final dateKey = GymDateUtils.toDateKey(date);
      final key = _attKey(customerId, dateKey);
      final record = _attendanceMap[key];
      if (record != null) modifiedRecords.add(record);
    }

    notifyListeners();
    await _saveAttendance();
    await _cloudBatchSaveAttendance(modifiedRecords);
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
        final dateKey = GymDateUtils.toDateKey(date);
        final key = _attKey(cId, dateKey);
        final record = _attendanceMap[key];
        if (record != null) modifiedRecords.add(record);
      }
    }

    notifyListeners();
    await _saveAttendance();
    await _cloudBatchSaveAttendance(modifiedRecords);
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
    final monthsWithUnpaidAttendance = <String>{};
    for (final record in _attendanceMap.values) {
      if (record.customerId == customerId && record.status == AttendanceStatus.present) {
        if (!isDateCoveredByPayment(customerId, record.dateKey)) {
          if (record.dateKey.length >= 7) {
            monthsWithUnpaidAttendance.add(record.dateKey.substring(0, 7));
          }
        }
      }
    }
    final list = monthsWithUnpaidAttendance.toList()..sort();
    return list;
  }


  Map<String, int> getDailyOverview(String dateKey) {
    int present = 0;
    int totalActive = _customers.where((c) => c.isActive).length;

    for (var c in _customers) {
      if (c.isActive && isCustomerPresentOnDate(c.id, dateKey)) {
        present++;
      }
    }

    return {
      'total': totalActive,
      'present': present,
      'absent': totalActive - present,
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
    final list = _paymentMap.values
        .where((p) => p.customerId == customerId && p.isPaid)
        .toList();
    list.sort((a, b) => b.effectiveStartDate.compareTo(a.effectiveStartDate));
    return list;
  }

  PaymentRecord? getPaymentById(String id) => _paymentMap[id];

  /// Amount still owed for a record: the remaining balance for partially paid
  /// records, the full fee for pending ones.
  double pendingAmountOf(PaymentRecord r) => r.isPaid ? r.balanceDue : r.totalDue;

  /// Pure read: the paid payment covering [monthYear], or a transient pending
  /// record when none exists. Transient records are never stored.
  PaymentRecord getPaymentRecord(String customerId, String monthYear) {
    final covering = getPaymentCoveringMonth(customerId, monthYear);
    if (covering != null) return covering;

    final customer = getCustomerById(customerId);
    return PaymentRecord(
      id: 'pending_${customerId}_$monthYear',
      customerId: customerId,
      monthYear: monthYear,
      amount: 0.0,
      totalDue: _feeForCustomer(customer),
      status: PaymentStatus.pending,
      durationMonths: customer?.planDurationMonths ?? 1,
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
      final bill = BillRecord(
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
      _billsMap[bill.id] = bill;
      _saveBills();
      _cloudSaveBill(bill);
      return bill;
    }

    // Transient/pending payment: return a non-persisted preview bill.
    final effectiveAmount = payment.amount > 0.0
        ? payment.amount
        : _feeForCustomer(customer, durationMonths: payment.durationMonths);
    return BillRecord(
      id: 'bill_${customer.id}_${payment.monthYear}',
      billNumber: generateBillNumber(payment.monthYear),
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      planType: customer.planType,
      monthYear: payment.monthYear,
      amount: effectiveAmount,
      paymentId: payment.id,
      method: payment.method ?? PaymentMethod.cash,
      paidAt: payment.paidAt ?? DateTime.now(),
      notes: payment.notes,
      transactionRef: payment.transactionRef,
      gymName: _settings.gymName,
      issuedAt: payment.paidAt ?? DateTime.now(),
      status: payment.isPaid ? 'PAID' : 'PENDING',
      durationMonths: payment.durationMonths,
      startDate: payment.startDate ?? payment.effectiveStartDate,
      endDate: payment.endDate ?? payment.effectiveEndDate,
      coveragePeriod: payment.formattedDateRange,
    );
  }

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
  }) async {
    final effectivePaidAt = paidAt ?? DateTime.now();
    final customer = getCustomerById(customerId);

    // Smart default for startDate if not provided:
    DateTime computedStartDate;
    if (startDate != null) {
      computedStartDate = startDate;
    } else if (customer != null) {
      final currentExpiry = getCustomerExpiryDate(customer);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (hasPaidMembership(customer) && currentExpiry.isAfter(today)) {
        // Member is currently active -> advance payment starts day after expiry
        computedStartDate = currentExpiry.add(const Duration(days: 1));
      } else {
        computedStartDate = DateTime(
            effectivePaidAt.year, effectivePaidAt.month, effectivePaidAt.day);
      }
    } else {
      computedStartDate = DateTime(
          effectivePaidAt.year, effectivePaidAt.month, effectivePaidAt.day);
    }

    final computedEndDate = endDate ??
        GymDateUtils.computeAnniversaryEndDate(computedStartDate, durationMonths);
    final coveragePeriod =
        GymDateUtils.formatDateRange(computedStartDate, computedEndDate);
    final startMonthKey = GymDateUtils.toMonthKey(computedStartDate);
    final effectiveTotalDue =
        totalDue ?? _feeForCustomer(customer, durationMonths: durationMonths);

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
    _paymentMap[record.id] = record;

    final bill = BillRecord(
      id: _newBillId(customerId),
      billNumber: generateBillNumber(startMonthKey),
      customerId: customerId,
      customerName: customer?.name ?? 'Member',
      customerPhone: customer?.phone ?? '',
      planType: customer?.planType ?? CustomerPlan.normal,
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
    _billsMap[bill.id] = bill;

    notifyListeners();
    await _savePayments();
    await _saveBills();
    await _cloudSavePayment(record);
    await _cloudSaveBill(bill);

    return bill;
  }

  /// Collects (part of) the remaining balance on a paid payment. Issues its own
  /// BALANCE bill with its own bill number.
  Future<BillRecord> collectBalance({
    required String paymentId,
    required double amount,
    required PaymentMethod method,
    DateTime? paidAt,
    String? notes,
    String? transactionRef,
  }) async {
    final record = _paymentMap[paymentId];
    if (record == null || !record.isPaid) {
      throw ArgumentError('No paid payment found for id $paymentId');
    }
    if (amount <= 0) {
      throw ArgumentError('Amount must be positive');
    }
    final collected =
        amount > record.balanceDue ? record.balanceDue : amount;
    final effectivePaidAt = paidAt ?? DateTime.now();
    final customer = getCustomerById(record.customerId);

    final updated = record.copyWith(amount: record.amount + collected);
    _paymentMap[paymentId] = updated;

    final bill = BillRecord(
      id: _newBillId(record.customerId),
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
    _billsMap[bill.id] = bill;

    notifyListeners();
    await _savePayments();
    await _saveBills();
    await _cloudSavePayment(updated);
    await _cloudSaveBill(bill);

    return bill;
  }

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
  }) async {
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
    final newMonthYear = newStart != null
        ? GymDateUtils.toMonthKey(newStart)
        : record.monthYear;

    final updated = record.copyWith(
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
    _paymentMap[paymentId] = updated;

    final customer = getCustomerById(record.customerId);
    BillRecord bill;
    final existing = getBillForPayment(paymentId);
    if (existing != null) {
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
      _billsMap[bill.id] = bill;
    } else {
      bill = getOrCreateBillForPayment(
          customer ??
              Customer(
                id: record.customerId,
                name: 'Member',
                phone: '',
                joinDate: DateTime.now(),
              ),
          updated);
    }

    notifyListeners();
    await _savePayments();
    await _saveBills();
    await _cloudSavePayment(updated);
    await _cloudSaveBill(bill);

    return bill;
  }

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

    notifyListeners();
    await _savePayments();
    await _saveBills();
    await _cloudDeletePayment(record.id);
    for (final b in cancelled) {
      await _cloudSaveBill(b);
    }
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
        list.add(getPaymentRecord(customerId, monthKey));
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

      // Step 5: re-key cloud docs. Legacy doc ids were `${customerId}_${monthYear}`.
      if (_isCloudAttached) {
        _suppressCloudUpdates = true;
        try {
          await FirestoreService().batchUpsertPayments(paymentsToUpsert);
          await FirestoreService().batchUpsertBills(billsToUpsert);
          for (final docId in paymentDocsToDelete) {
            await FirestoreService().deletePayment(docId);
          }
          for (final docId in billDocsToDelete) {
            await FirestoreService().deleteBill(docId);
          }
        } finally {
          _suppressCloudUpdates = false;
        }
      }
    } finally {
      _migrating = false;
    }
  }

  // ==================== PENDING RANGE OPERATIONS ====================

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

  /// Returns all active customers with pending dues across months in the date range.
  List<MemberPendingSummary> getPendingDuesByMember(DateTime start, DateTime end) {
    final monthKeys = getMonthKeysInRange(start, end);
    final results = <MemberPendingSummary>[];

    for (final customer in _customers) {
      if (!customer.isActive) continue;

      final pendingRecords = <PaymentRecord>[];
      for (final monthKey in monthKeys) {
        final parts = monthKey.split('-');
        if (parts.length == 2) {
          final year = int.tryParse(parts[0]) ?? 2026;
          final month = int.tryParse(parts[1]) ?? 1;
          final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);
          if (customer.joinDate.isAfter(monthEnd)) {
            continue; // Member hadn't joined yet
          }
        }

        final stage = getMemberLifecycleStage(customer, monthKey);
        if (stage == MemberLifecycleStage.due) {
          final record = getPaymentRecord(customer.id, monthKey);
          pendingRecords.add(record);
        }
      }

      // Partial balances: paid cycles with an outstanding balance whose
      // start month falls inside the range still owe money.
      for (final p in _paymentMap.values) {
        if (p.customerId == customer.id &&
            p.isPaid &&
            p.balanceDue > 0 &&
            monthKeys.contains(p.monthYear)) {
          pendingRecords.add(p);
        }
      }

      if (pendingRecords.isNotEmpty) {
        final total = pendingRecords.fold<double>(0.0, (sum, r) => sum + pendingAmountOf(r));
        results.add(MemberPendingSummary(
          customer: customer,
          pendingRecords: pendingRecords,
          totalPendingAmount: total,
        ));
      }
    }

    return results;
  }

  /// Returns pending dues grouped by each month in the date range.
  List<MonthPendingGroup> getPendingDuesByMonth(DateTime start, DateTime end) {
    final monthKeys = getMonthKeysInRange(start, end);
    final sortedMonths = List<String>.from(monthKeys)..sort((a, b) => b.compareTo(a));
    final groups = <MonthPendingGroup>[];

    for (final monthKey in sortedMonths) {
      final items = <MonthPendingItem>[];
      double monthTotal = 0.0;

      final parts = monthKey.split('-');
      final year = int.tryParse(parts[0]) ?? 2026;
      final month = int.tryParse(parts[1]) ?? 1;
      final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);

      for (final customer in _customers) {
        if (!customer.isActive) continue;
        if (customer.joinDate.isAfter(monthEnd)) continue;

        final stage = getMemberLifecycleStage(customer, monthKey);
        if (stage == MemberLifecycleStage.due) {
          final record = getPaymentRecord(customer.id, monthKey);
          items.add(MonthPendingItem(customer: customer, payment: record));
          monthTotal += pendingAmountOf(record);
        }

        // Partial balances owed on paid cycles starting in this month.
        for (final p in _paymentMap.values) {
          if (p.customerId == customer.id &&
              p.isPaid &&
              p.balanceDue > 0 &&
              p.monthYear == monthKey) {
            items.add(MonthPendingItem(customer: customer, payment: p));
            monthTotal += p.balanceDue;
          }
        }
      }

      if (items.isNotEmpty) {
        groups.add(MonthPendingGroup(
          monthKey: monthKey,
          items: items,
          totalAmount: monthTotal,
        ));
      }
    }

    return groups;
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
    notifyListeners();
    await _saveExpenses();
    await _cloudSaveExpense(expense);
  }

  Future<void> updateExpense(ExpenseRecord updated) async {
    final index = _expenses.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      _expenses[index] = updated;
      notifyListeners();
      await _saveExpenses();
      await _cloudSaveExpense(updated);
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    _expenses.removeWhere((e) => e.id == expenseId);
    notifyListeners();
    await _saveExpenses();
    await _cloudDeleteExpense(expenseId);
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

    // Total pending dues across all members up to current month (last 3 months)
    final pendingSummaries = getPendingDuesByMember(
      DateTime(now.year, now.month - 2, 1),
      now,
    );
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
    final prefs = await SharedPreferences.getInstance();
    final data = _customers.map((c) => c.toMap()).toList();
    await prefs.setString(_keyCustomers, json.encode(data));
  }

  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _expenses.map((e) => e.toMap()).toList();
    await prefs.setString(_keyExpenses, json.encode(data));
  }

  Future<void> _saveAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _attendanceMap.values.map((a) => a.toMap()).toList();
    await prefs.setString(_keyAttendance, json.encode(data));
  }

  Future<void> _savePayments() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _paymentMap.values.map((p) => p.toMap()).toList();
    await prefs.setString(_keyPayments, json.encode(data));
  }

  Future<void> _saveBills() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _billsMap.values.map((b) => b.toMap()).toList();
    await prefs.setString(_keyBills, json.encode(data));
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, _settings.toJson());
    // Sync settings to cloud
    if (_isCloudAttached) {
      _suppressCloudUpdates = true;
      await FirestoreService().upsertSettings(_settings);
      _suppressCloudUpdates = false;
    }
  }

  Future<void> _saveAll() async {
    await _saveCustomers();
    await _saveExpenses();
    await _saveAttendance();
    await _savePayments();
    await _saveBills();
    await _saveSettings();
    // Full sync to cloud
    if (_isCloudAttached) {
      _suppressCloudUpdates = true;
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
  }

  // ---- Cloud-aware save helpers for individual record operations ----

  Future<void> _cloudSaveCustomer(Customer customer) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertCustomer(customer);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudDeleteCustomer(String customerId) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().deleteCustomer(customerId);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudSaveAttendance(AttendanceRecord record) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertAttendance(record);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudBatchSaveAttendance(List<AttendanceRecord> records) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().batchUpsertAttendance(records);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudSavePayment(PaymentRecord record) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertPayment(record);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudDeletePayment(String docId) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().deletePayment(docId);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudSaveBill(BillRecord record) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertBill(record);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudSaveExpense(ExpenseRecord record) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertExpense(record);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudDeleteExpense(String expenseId) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().deleteExpense(expenseId);
    _suppressCloudUpdates = false;
  }

  Future<void> resetToDemoData() async {
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
