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
  due;

  String get label {
    switch (this) {
      case MemberLifecycleStage.paid:
        return 'Paid';
      case MemberLifecycleStage.newMember:
        return 'New Member';
      case MemberLifecycleStage.due:
        return 'Payment Due';
    }
  }

  bool get isPaid => this == MemberLifecycleStage.paid;
  bool get isNew => this == MemberLifecycleStage.newMember;
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
  Map<String, PaymentRecord> _paymentMap = {}; // key: "${customerId}_${monthYear}"
  Map<String, BillRecord> _billsMap = {}; // key: "${customerId}_${monthYear}"
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
            "${item['customerId']}_${item['monthYear']}": PaymentRecord.fromMap(item as Map<String, dynamic>)
        };
      }

      final billsJson = prefs.getString(_keyBills);
      if (billsJson != null) {
        final list = json.decode(billsJson) as List<dynamic>;
        _billsMap = {
          for (var item in list)
            "${item['customerId']}_${item['monthYear']}": BillRecord.fromMap(item as Map<String, dynamic>)
        };
      }

      await _normalizePaymentRecords();

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

    if (paymentMap != null || billsMap != null) {
      _normalizePaymentRecords();
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
      if (isPaidForMonth && payment.endDate != null && !payment.isCoveredInPackage) {
        final monthStart = DateTime(year, m, 1);
        if (payment.endDate!.isBefore(monthStart)) {
          isPaidForMonth = false;
        }
      }

      DateTime? effStart;
      DateTime? effEnd;
      final bool isCovered = payment.isCoveredInPackage;
      if (isPaidForMonth) {
        if (isCovered && payment.coveredByMonthYear != null) {
          final parentPay = getPaymentRecord(customerId, payment.coveredByMonthYear!);
          effStart = parentPay.effectiveStartDate;
          effEnd = parentPay.effectiveEndDate;
        } else {
          effStart = payment.effectiveStartDate;
          effEnd = payment.effectiveEndDate;
        }
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

    final currentMonth = GymDateUtils.toMonthKey(DateTime.now());

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
        durationMonths: planDurationMonths,
        startDate: actualStart,
        endDate: actualEnd,
        notes: 'Initial registration payment',
      );
      if (actualEnd.isBefore(DateTime(DateTime.now().year, DateTime.now().month, 1))) {
        _ensurePaymentRecordExists(customer.id, currentMonth);
      }
    } else {
      // Also ensure current month pending payment record exists
      _ensurePaymentRecordExists(customer.id, currentMonth);
      final payKey = _payKey(customer.id, currentMonth);
      final pendingPay = _paymentMap[payKey];
      if (pendingPay != null) await _cloudSavePayment(pendingPay);
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
    final parts = monthKey.split('-');
    if (parts.length != 2) return false;
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final monthStart = DateTime(y, m, 1);
    final monthEnd = DateTime(y, m, GymDateUtils.daysInMonth(y, m));

    for (final p in _paymentMap.values) {
      if (p.customerId == customerId && p.isPaid) {
        final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
        final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);
        if (!start.isAfter(monthEnd) && !end.isBefore(monthStart)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns the PaymentRecord covering a specific month, if any.
  PaymentRecord? getPaymentCoveringMonth(String customerId, String monthKey) {
    // 1. Direct payment for this monthKey
    final key = _payKey(customerId, monthKey);
    final direct = _paymentMap[key];
    if (direct != null && direct.isPaid) {
      return direct;
    }
    // 2. Direct payment covered under a parent package
    if (direct?.coveredByMonthYear != null && direct!.coveredByMonthYear!.isNotEmpty) {
      final parent = _paymentMap[_payKey(customerId, direct.coveredByMonthYear!)];
      if (parent != null && parent.isPaid) return parent;
    }
    // 3. Any paid payment whose effective validity overlaps with this month
    final parts = monthKey.split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final monthStart = DateTime(y, m, 1);
      final monthEnd = DateTime(y, m, GymDateUtils.daysInMonth(y, m));
      for (final p in _paymentMap.values) {
        if (p.customerId == customerId && p.isPaid) {
          final start = DateTime(p.effectiveStartDate.year, p.effectiveStartDate.month, p.effectiveStartDate.day);
          final end = DateTime(p.effectiveEndDate.year, p.effectiveEndDate.month, p.effectiveEndDate.day);
          if (!start.isAfter(monthEnd) && !end.isBefore(monthStart)) {
            return p;
          }
        }
      }
    }
    return null;
  }

  /// Evaluates member lifecycle stage for a given month:
  /// - PAID: Covered by a valid paid plan with no unpaid attended days in that month
  /// - NEW: Unpaid + 0 attendance days + Joined within last 3 days
  /// - DUE: Unpaid attended days or expired / lacking plan
  MemberLifecycleStage getMemberLifecycleStage(Customer customer, String monthYear) {
    // 1. If this month has any attended days that are NOT covered by payment -> DUE!
    final unpaidAttendedDays = getUnpaidAttendedDaysInMonth(customer.id, monthYear);
    if (unpaidAttendedDays > 0) {
      return MemberLifecycleStage.due;
    }

    // 2. Check if a paid payment covers this month
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

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final joinDay = DateTime(customer.joinDate.year, customer.joinDate.month, customer.joinDate.day);
    final daysSinceJoined = today.difference(joinDay).inDays;

    final hasAttended = _attendanceMap.values.any(
      (a) => a.customerId == customer.id && a.status == AttendanceStatus.present,
    );

    if (!hasAttended && daysSinceJoined <= 3) {
      return MemberLifecycleStage.newMember;
    }

    return MemberLifecycleStage.due;
  }

  Future<void> updateCustomer(Customer updated) async {
    final index = _customers.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      final old = _customers[index];
      _customers[index] = updated;

      // If plan or duration changed, update any unpaid pending payment for current month
      if (old.planType != updated.planType || old.planDurationMonths != updated.planDurationMonths) {
        final currentMonth = GymDateUtils.toMonthKey(DateTime.now());
        final key = _payKey(updated.id, currentMonth);
        final existing = _paymentMap[key];
        if (existing != null && !existing.isPaid) {
          _paymentMap[key] = existing.copyWith(
            amount: _settings.getPriceForDuration(updated.planType, updated.planDurationMonths),
            durationMonths: updated.planDurationMonths,
          );
          await _savePayments();
          await _cloudSavePayment(_paymentMap[key]!);
        }
      }

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

    if (status == AttendanceStatus.present && dateKey.length >= 7) {
      _ensurePaymentRecordExists(customerId, dateKey.substring(0, 7));
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

    final monthKey = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    if (status == AttendanceStatus.present) {
      _ensurePaymentRecordExists(customerId, monthKey);
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

  String _payKey(String customerId, String monthYear) => "${customerId}_$monthYear";

  PaymentRecord getPaymentRecord(String customerId, String monthYear) {
    final key = _payKey(customerId, monthYear);
    if (_paymentMap.containsKey(key)) {
      final p = _paymentMap[key]!;
      // Auto-relocation guard: If this payment has an exact startDate belonging to another month
      if (p.isPaid && p.startDate != null && !p.isCoveredInPackage) {
        final startMonth = GymDateUtils.toMonthKey(p.effectiveStartDate);
        final endMonth = GymDateUtils.toMonthKey(p.effectiveEndDate);
        final startUnpaid = getUnpaidAttendedDaysInMonth(customerId, startMonth);

        // Case A: Misplaced in endMonth by old logic, but startMonth had 0 unpaid attendance days
        if (monthYear == endMonth && startMonth != endMonth && startUnpaid == 0) {
          final trueMonth = startMonth;
          final trueKey = _payKey(customerId, trueMonth);
          _paymentMap.remove(key);
          _paymentMap[trueKey] = p.copyWith(monthYear: trueMonth);
          if (_billsMap.containsKey(key)) {
            final b = _billsMap.remove(key)!;
            _billsMap[trueKey] = b.copyWith(monthYear: trueMonth);
          }
          _savePayments();
          _saveBills();
          return _paymentMap[trueKey]!;
        }

        // Case B: Payment stored under completely unrelated month (neither startMonth nor endMonth)
        if (monthYear != startMonth && monthYear != endMonth) {
          final trueMonth = (startMonth != endMonth && startUnpaid > 0) ? endMonth : startMonth;
          final trueKey = _payKey(customerId, trueMonth);
          _paymentMap.remove(key);
          _paymentMap[trueKey] = p.copyWith(monthYear: trueMonth);
          if (_billsMap.containsKey(key)) {
            final b = _billsMap.remove(key)!;
            _billsMap[trueKey] = b.copyWith(monthYear: trueMonth);
          }
          _savePayments();
          _saveBills();

          final customer = getCustomerById(customerId);
          final fee = customer != null
              ? _settings.getPriceForDuration(customer.planType, customer.planDurationMonths)
              : _settings.standardMonthlyFee;
          final pendingRecord = PaymentRecord(
            id: 'pay_${customerId}_$monthYear',
            customerId: customerId,
            monthYear: monthYear,
            amount: fee,
            status: PaymentStatus.pending,
            durationMonths: customer?.planDurationMonths ?? 1,
          );
          _paymentMap[key] = pendingRecord;
          return pendingRecord;
        }
      }
      return p;
    }

    // Check if there is a misplaced payment in endMonth that actually belongs to monthYear:
    for (final other in _paymentMap.values.toList()) {
      if (other.customerId == customerId &&
          other.isPaid &&
          other.startDate != null &&
          !other.isCoveredInPackage &&
          other.durationMonths <= 1) {
        final sMonth = GymDateUtils.toMonthKey(other.effectiveStartDate);
        final eMonth = GymDateUtils.toMonthKey(other.effectiveEndDate);
        if (sMonth == monthYear && other.monthYear == eMonth) {
          final startUnpaid = getUnpaidAttendedDaysInMonth(customerId, sMonth);
          if (startUnpaid == 0) {
            final oldKey = _payKey(customerId, eMonth);
            final targetKey = _payKey(customerId, sMonth);
            _paymentMap.remove(oldKey);
            final updatedPay = other.copyWith(monthYear: sMonth);
            _paymentMap[targetKey] = updatedPay;
            if (_billsMap.containsKey(oldKey)) {
              final b = _billsMap.remove(oldKey)!;
              _billsMap[targetKey] = b.copyWith(monthYear: sMonth);
            }
            _savePayments();
            _saveBills();
            return updatedPay;
          }
        }
      }
    }

    final customer = getCustomerById(customerId);
    final fee = customer != null
        ? _settings.getPriceForDuration(customer.planType, customer.planDurationMonths)
        : _settings.standardMonthlyFee;
    return PaymentRecord(
      id: 'pay_${customerId}_$monthYear',
      customerId: customerId,
      monthYear: monthYear,
      amount: fee,
      status: PaymentStatus.pending,
      durationMonths: customer?.planDurationMonths ?? 1,
    );
  }

  void _ensurePaymentRecordExists(String customerId, String monthYear) {
    final key = _payKey(customerId, monthYear);
    if (!_paymentMap.containsKey(key)) {
      final customer = getCustomerById(customerId);
      final fee = customer != null
          ? _settings.getPriceForDuration(customer.planType, customer.planDurationMonths)
          : _settings.standardMonthlyFee;
      _paymentMap[key] = PaymentRecord(
        id: 'pay_${customerId}_$monthYear',
        customerId: customerId,
        monthYear: monthYear,
        amount: fee,
        status: PaymentStatus.pending,
        durationMonths: customer?.planDurationMonths ?? 1,
      );
    }
  }

  /// Automatically relocates any payment record whose effective start date belongs to a
  /// different month (e.g. August payment erroneously stored under September key).
  Future<void> _normalizePaymentRecords() async {
    bool modified = false;
    final entries = Map<String, PaymentRecord>.from(_paymentMap);
    for (final entry in entries.entries) {
      final p = entry.value;
      if (p.isPaid && p.startDate != null && !p.isCoveredInPackage && p.durationMonths <= 1) {
        final startMonth = GymDateUtils.toMonthKey(p.effectiveStartDate);
        final endMonth = GymDateUtils.toMonthKey(p.effectiveEndDate);

        // Case 1: Mid-month renewal (e.g. 27 Sep - 26 Oct) was placed in startMonth,
        // but startMonth has unpaid attendance days prior to start date!
        final startUnpaidAttended = getUnpaidAttendedDaysInMonth(p.customerId, startMonth);
        if (p.monthYear == startMonth && startMonth != endMonth && startUnpaidAttended > 0) {
          final targetKey = _payKey(p.customerId, endMonth);
          _paymentMap.remove(entry.key);
          final updatedPay = p.copyWith(monthYear: endMonth);
          _paymentMap[targetKey] = updatedPay;
          _ensurePaymentRecordExists(p.customerId, startMonth);

          BillRecord? updatedBill;
          if (_billsMap.containsKey(entry.key)) {
            final bill = _billsMap.remove(entry.key)!;
            updatedBill = bill.copyWith(monthYear: endMonth);
            _billsMap[targetKey] = updatedBill;
          }

          if (_isCloudAttached) {
            await _cloudSavePayment(updatedPay);
            final vacatedPay = _paymentMap[entry.key];
            if (vacatedPay != null) await _cloudSavePayment(vacatedPay);

            if (updatedBill != null) {
              await _cloudSaveBill(updatedBill);
              await _cloudDeleteBill(p.customerId, startMonth);
            }
          }

          modified = true;
          continue;
        }

        // Case 2: Mid-month payment (e.g. 27 Sep - 26 Oct) was placed in endMonth ('2026-10')
        // by the old daysInEnd > daysInStart logic, BUT startMonth has 0 unpaid attended days!
        // It properly belongs to startMonth ('2026-09').
        if (p.monthYear == endMonth && startMonth != endMonth && startUnpaidAttended == 0) {
          final targetKey = _payKey(p.customerId, startMonth);
          _paymentMap.remove(entry.key);
          final updatedPay = p.copyWith(monthYear: startMonth);
          _paymentMap[targetKey] = updatedPay;

          BillRecord? updatedBill;
          if (_billsMap.containsKey(entry.key)) {
            final bill = _billsMap.remove(entry.key)!;
            updatedBill = bill.copyWith(monthYear: startMonth);
            _billsMap[targetKey] = updatedBill;
          }

          if (_isCloudAttached) {
            await _cloudSavePayment(updatedPay);
            await _cloudDeletePayment(p.customerId, endMonth);

            if (updatedBill != null) {
              await _cloudSaveBill(updatedBill);
              await _cloudDeleteBill(p.customerId, endMonth);
            }
          }

          modified = true;
          continue;
        }

        // Case 3: Payment stored under completely unrelated month (neither startMonth nor endMonth)
        if (p.monthYear != startMonth && p.monthYear != endMonth) {
          final trueMonth = (startMonth != endMonth && startUnpaidAttended > 0) ? endMonth : startMonth;
          final trueKey = _payKey(p.customerId, trueMonth);
          _paymentMap.remove(entry.key);
          final updatedPay = p.copyWith(monthYear: trueMonth);
          _paymentMap[trueKey] = updatedPay;
          _ensurePaymentRecordExists(p.customerId, p.monthYear);

          BillRecord? updatedBill;
          if (_billsMap.containsKey(entry.key)) {
            final bill = _billsMap.remove(entry.key)!;
            updatedBill = bill.copyWith(monthYear: trueMonth);
            _billsMap[trueKey] = updatedBill;
          }

          if (_isCloudAttached) {
            await _cloudSavePayment(updatedPay);
            final vacatedPay = _paymentMap[entry.key];
            if (vacatedPay != null) await _cloudSavePayment(vacatedPay);

            if (updatedBill != null) {
              await _cloudSaveBill(updatedBill);
              await _cloudDeleteBill(p.customerId, p.monthYear);
            }
          }

          modified = true;
        }
      }
    }

    // Clean up any stale/ghost pending records with 0 attended days that are covered by an active paid cycle
    final pendingEntries = Map<String, PaymentRecord>.from(_paymentMap);
    for (final entry in pendingEntries.entries) {
      final p = entry.value;
      if (!p.isPaid) {
        final unpaid = getUnpaidAttendedDaysInMonth(p.customerId, p.monthYear);
        if (unpaid == 0 && isMonthCoveredByPaidPayment(p.customerId, p.monthYear)) {
          _paymentMap.remove(entry.key);
          modified = true;
        }
      }
    }
    if (modified) {
      await _savePayments();
      await _saveBills();
    }
  }

  String generateBillNumber(String monthYear) {
    final cleanMonth = monthYear.replaceAll('-', '');
    final count = _billsMap.values.where((b) => b.monthYear == monthYear).length + 1;
    final seq = count.toString().padLeft(4, '0');
    return 'BILL-$cleanMonth-$seq';
  }

  Future<BillRecord> markPaymentAsPaid({
    required String customerId,
    required String monthYear,
    required PaymentMethod method,
    required double amount,
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
    } else {
      if (customer != null) {
        final currentExpiry = getCustomerExpiryDate(customer);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (hasPaidMembership(customer) && currentExpiry.isAfter(today)) {
          // Member is currently active -> advance payment starts day after expiry
          computedStartDate = currentExpiry.add(const Duration(days: 1));
        } else {
          computedStartDate = DateTime(effectivePaidAt.year, effectivePaidAt.month, effectivePaidAt.day);
        }
      } else {
        computedStartDate = DateTime(effectivePaidAt.year, effectivePaidAt.month, effectivePaidAt.day);
      }
    }

    final computedEndDate = endDate ??
        GymDateUtils.computeAnniversaryEndDate(computedStartDate, durationMonths);
    final coveragePeriod = GymDateUtils.formatDateRange(computedStartDate, computedEndDate);

    final startMonthKey = GymDateUtils.toMonthKey(computedStartDate);
    final endMonthKey = GymDateUtils.toMonthKey(computedEndDate);

    String targetMonthKey;
    if (startMonthKey == endMonthKey || durationMonths > 1) {
      targetMonthKey = startMonthKey;
    } else {
      // Cross-month payment for single month (e.g. 27 Sep - 26 Oct):
      final startUnpaidAttended = getUnpaidAttendedDaysInMonth(customerId, startMonthKey);
      if (monthYear == endMonthKey) {
        targetMonthKey = endMonthKey;
      } else if (startUnpaidAttended > 0) {
        // Start month has unpaid attended days prior to this payment!
        // Storing this payment under startMonthKey would overwrite the pending dues of start month!
        targetMonthKey = endMonthKey;
      } else {
        // Member has 0 unpaid attended days in startMonthKey.
        // This payment covers the cycle beginning in startMonthKey.
        // It belongs to startMonthKey.
        targetMonthKey = startMonthKey;
      }
    }

    final targetKey = _payKey(customerId, targetMonthKey);
    final existing = _paymentMap[targetKey];

    _paymentMap[targetKey] = PaymentRecord(
      id: existing?.id ?? 'pay_${customerId}_$targetMonthKey',
      customerId: customerId,
      monthYear: targetMonthKey,
      amount: amount,
      status: PaymentStatus.paid,
      method: method,
      paidAt: effectivePaidAt,
      startDate: computedStartDate,
      endDate: computedEndDate,
      notes: notes,
      transactionRef: transactionRef,
      durationMonths: durationMonths,
    );

    // Ensure startMonthKey retains its pending record if this payment was placed in endMonthKey
    // and startMonthKey actually has unpaid attendance dues
    if (targetMonthKey != startMonthKey) {
      final startUnpaid = getUnpaidAttendedDaysInMonth(customerId, startMonthKey);
      if (startUnpaid > 0) {
        _ensurePaymentRecordExists(customerId, startMonthKey);
      } else {
        final startKey = _payKey(customerId, startMonthKey);
        if (_paymentMap.containsKey(startKey) && !_paymentMap[startKey]!.isPaid) {
          _paymentMap.remove(startKey);
        }
      }
    }

    // If caller passed a different monthYear, ensure caller month is not falsely marked paid
    if (monthYear != targetMonthKey) {
      final callerKey = _payKey(customerId, monthYear);
      final callerUnpaid = getUnpaidAttendedDaysInMonth(customerId, monthYear);
      if (callerUnpaid > 0) {
        _ensurePaymentRecordExists(customerId, monthYear);
      }
      if (_paymentMap.containsKey(callerKey) &&
          _paymentMap[callerKey]!.isPaid &&
          _paymentMap[callerKey]!.coveredByMonthYear != targetMonthKey) {
        _paymentMap[callerKey] = PaymentRecord(
          id: 'pay_${customerId}_$monthYear',
          customerId: customerId,
          monthYear: monthYear,
          amount: _settings.getPriceForDuration(
            customer?.planType ?? CustomerPlan.normal,
            customer?.planDurationMonths ?? 1,
          ),
          status: PaymentStatus.pending,
          durationMonths: customer?.planDurationMonths ?? 1,
        );
        _billsMap.remove(callerKey);
      }
    }

    // Compute coverage period string and mark forward covered months if duration > 1
    final parts = targetMonthKey.split('-');
    final startYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    final startMonth = parts.length > 1 ? (int.tryParse(parts[1]) ?? DateTime.now().month) : DateTime.now().month;

    if (durationMonths > 1) {
      // Mark forward months as prepaid/covered under this multi-month package
      for (int i = 1; i < durationMonths; i++) {
        final forwardDate = DateTime(startYear, startMonth + i, 1);
        final forwardMonthKey = GymDateUtils.toMonthKey(forwardDate);
        final forwardKey = _payKey(customerId, forwardMonthKey);

        _paymentMap[forwardKey] = PaymentRecord(
          id: 'pay_${customerId}_$forwardMonthKey',
          customerId: customerId,
          monthYear: forwardMonthKey,
          amount: 0.0,
          status: PaymentStatus.paid,
          method: method,
          paidAt: effectivePaidAt,
          startDate: computedStartDate,
          endDate: computedEndDate,
          notes: 'Covered under $durationMonths-Month Package ($coveragePeriod)',
          transactionRef: transactionRef,
          durationMonths: 1,
          coveredByMonthYear: targetMonthKey,
        );
      }
    }

    final existingBill = _billsMap[targetKey];
    final billNumber = existingBill?.billNumber ?? generateBillNumber(targetMonthKey);

    final bill = BillRecord(
      id: existingBill?.id ?? 'bill_${customerId}_$targetMonthKey',
      billNumber: billNumber,
      customerId: customerId,
      customerName: customer?.name ?? 'Member',
      customerPhone: customer?.phone ?? '',
      planType: customer?.planType ?? CustomerPlan.normal,
      monthYear: targetMonthKey,
      amount: amount,
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
    _billsMap[targetKey] = bill;

    notifyListeners();
    await _savePayments();
    await _saveBills();
    // Sync payment + bill to cloud
    await _cloudSavePayment(_paymentMap[targetKey]!);
    await _cloudSaveBill(bill);
    if (monthYear != targetMonthKey) {
      final callerKey = _payKey(customerId, monthYear);
      if (_paymentMap.containsKey(callerKey)) {
        await _cloudSavePayment(_paymentMap[callerKey]!);
        await _cloudDeleteBill(customerId, monthYear);
      }
    }
    // Also sync forward covered months to cloud
    if (durationMonths > 1) {
      for (int i = 1; i < durationMonths; i++) {
        final forwardDate = DateTime(startYear, startMonth + i, 1);
        final forwardMonthKey = GymDateUtils.toMonthKey(forwardDate);
        final forwardKey = _payKey(customerId, forwardMonthKey);
        final forwardPay = _paymentMap[forwardKey];
        if (forwardPay != null) await _cloudSavePayment(forwardPay);
      }
    }

    return bill;
  }

  Future<void> revertPaymentToPending(String customerId, String monthYear) async {
    final key = _payKey(customerId, monthYear);
    if (_paymentMap.containsKey(key)) {
      final old = _paymentMap[key]!;
      _paymentMap[key] = PaymentRecord(
        id: old.id,
        customerId: old.customerId,
        monthYear: old.monthYear,
        amount: old.amount,
        status: PaymentStatus.pending,
        durationMonths: old.durationMonths,
      );
      _billsMap.remove(key);

      // Also clean up any forward months covered under this month's multi-month package
      final coveredKeys = _paymentMap.entries
          .where((e) => e.value.customerId == customerId && e.value.coveredByMonthYear == monthYear)
          .map((e) => e.key)
          .toList();

      for (final covKey in coveredKeys) {
        // Extract customerId and monthYear from covKey for cloud delete
        final covParts = covKey.split('_');
        if (covParts.length >= 2) {
          final covMonth = covParts.sublist(1).join('_');
          await _cloudDeletePayment(customerId, covMonth);
          await _cloudDeleteBill(customerId, covMonth);
        }
        _paymentMap.remove(covKey);
        _billsMap.remove(covKey);
      }

      notifyListeners();
      await _savePayments();
      await _saveBills();
      // Sync reverted payment + removed bill to cloud
      await _cloudSavePayment(_paymentMap[key]!);
      await _cloudDeleteBill(customerId, monthYear);
    }
  }

  BillRecord? getBill(String customerId, String monthYear) {
    final key = _payKey(customerId, monthYear);
    return _billsMap[key];
  }

  BillRecord getOrCreateBillForPayment(Customer customer, PaymentRecord payment) {
    // 1. If this month is covered under another month's multi-month package (e.g. Oct/Nov covered by Sept):
    if (payment.coveredByMonthYear != null && payment.coveredByMonthYear!.isNotEmpty) {
      final parentKey = _payKey(customer.id, payment.coveredByMonthYear!);
      final parentBill = _billsMap[parentKey];
      if (parentBill != null && parentBill.amount > 0) {
        return parentBill;
      }
      final parentPayment = _paymentMap[parentKey];
      if (parentPayment != null && parentPayment.amount > 0) {
        return getOrCreateBillForPayment(customer, parentPayment);
      }
    }

    // 2. If this payment is not paid or has amount <= 0, check if covered by any paid payment
    if (!payment.isPaid || payment.amount <= 0.0) {
      final covering = getPaymentCoveringMonth(customer.id, payment.monthYear);
      if (covering != null && covering.isPaid && covering.monthYear != payment.monthYear) {
        return getOrCreateBillForPayment(customer, covering);
      }
      for (final p in _paymentMap.values) {
        if (p.customerId == customer.id && p.isPaid && p.amount > 0) {
          if (p.startDate != null && p.endDate != null) {
            final monthDate = DateTime.tryParse('${payment.monthYear}-01');
            if (monthDate != null &&
                !monthDate.isBefore(DateTime(p.startDate!.year, p.startDate!.month, 1)) &&
                !monthDate.isAfter(p.endDate!)) {
              return getOrCreateBillForPayment(customer, p);
            }
          }
        }
      }
    }

    final key = _payKey(customer.id, payment.monthYear);
    if (_billsMap.containsKey(key)) {
      final existing = _billsMap[key]!;
      if (existing.amount > 0) {
        return existing;
      }
      if (payment.coveredByMonthYear != null && payment.coveredByMonthYear!.isNotEmpty) {
        final parentKey = _payKey(customer.id, payment.coveredByMonthYear!);
        if (_billsMap.containsKey(parentKey) && _billsMap[parentKey]!.amount > 0) {
          return _billsMap[parentKey]!;
        }
      }
    }

    double effectiveAmount = payment.amount;
    if (effectiveAmount <= 0.0) {
      effectiveAmount = _settings.getPriceForDuration(customer.planType, payment.durationMonths);
    }

    final bill = BillRecord(
      id: 'bill_${customer.id}_${payment.monthYear}',
      billNumber: generateBillNumber(payment.monthYear),
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      planType: customer.planType,
      monthYear: payment.monthYear,
      amount: effectiveAmount,
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

    if (payment.isPaid) {
      _billsMap[key] = bill;
      _saveBills();
      _cloudSaveBill(bill);
    }
    return bill;
  }

  List<PaymentRecord> getCustomerPaymentHistory(String customerId) {
    // Auto-relocation guard for any misplaced endMonth payment for this customer
    for (final p in _paymentMap.values.toList()) {
      if (p.customerId == customerId &&
          p.isPaid &&
          p.startDate != null &&
          !p.isCoveredInPackage &&
          p.durationMonths <= 1) {
        final startMonth = GymDateUtils.toMonthKey(p.effectiveStartDate);
        final endMonth = GymDateUtils.toMonthKey(p.effectiveEndDate);
        if (p.monthYear == endMonth && startMonth != endMonth) {
          final startUnpaid = getUnpaidAttendedDaysInMonth(customerId, startMonth);
          if (startUnpaid == 0) {
            final oldKey = _payKey(customerId, endMonth);
            final targetKey = _payKey(customerId, startMonth);
            _paymentMap.remove(oldKey);
            final updatedPay = p.copyWith(monthYear: startMonth);
            _paymentMap[targetKey] = updatedPay;
            if (_billsMap.containsKey(oldKey)) {
              final b = _billsMap.remove(oldKey)!;
              _billsMap[targetKey] = b.copyWith(monthYear: startMonth);
            }
            _savePayments();
            _saveBills();
          }
        }
      }
    }

    final list = _paymentMap.values
        .where((p) => p.customerId == customerId)
        .where((p) {
          if (p.isPaid) return true;
          // For unpaid records, only show in payment history if member actually attended (has real dues)
          final unpaid = getUnpaidAttendedDaysInMonth(customerId, p.monthYear);
          return unpaid > 0;
        })
        .toList();
    list.sort((a, b) => b.monthYear.compareTo(a.monthYear));
    return list;
  }

  Map<String, dynamic> getMonthlyFinancialSummary(String monthYear) {
    double totalExpected = 0;
    double totalCollected = 0;
    int paidCount = 0;
    int pendingCount = 0;

    for (var customer in _customers) {
      if (!customer.isActive) continue;
      final record = getPaymentRecord(customer.id, monthYear);
      totalExpected += record.amount;
      if (record.isPaid) {
        totalCollected += record.amount;
        paidCount++;
      } else {
        pendingCount++;
      }
    }

    return {
      'totalMembers': _customers.where((c) => c.isActive).length,
      'totalExpected': totalExpected,
      'totalCollected': totalCollected,
      'totalPending': totalExpected - totalCollected,
      'paidCount': paidCount,
      'pendingCount': pendingCount,
    };
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

      if (pendingRecords.isNotEmpty) {
        final total = pendingRecords.fold<double>(0.0, (sum, r) => sum + r.amount);
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
          monthTotal += record.amount;
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

    // Today's collections
    double todayCollection = 0;
    for (final p in _paymentMap.values) {
      if (p.isPaid && p.paidAt != null) {
        if (GymDateUtils.toDateKey(p.paidAt!) == todayKey) {
          todayCollection += p.amount;
        }
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

  Future<void> _cloudDeletePayment(String customerId, String monthYear) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().deletePayment(customerId, monthYear);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudSaveBill(BillRecord record) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().upsertBill(record);
    _suppressCloudUpdates = false;
  }

  Future<void> _cloudDeleteBill(String customerId, String monthYear) async {
    if (!_isCloudAttached) return;
    _suppressCloudUpdates = true;
    await FirestoreService().deleteBill(customerId, monthYear);
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
    final currentMonth = GymDateUtils.toMonthKey(now);
    final prevMonth = GymDateUtils.toMonthKey(DateTime(now.year, now.month - 1, 1));

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

    // Seed payments for previous month (all paid)
    _paymentMap[_payKey('cust_1', prevMonth)] = PaymentRecord(
      id: 'pay_cust_1_$prevMonth',
      customerId: 'cust_1',
      monthYear: prevMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.gpay,
      paidAt: DateTime(now.year, now.month - 1, 5),
      transactionRef: 'UPI-789234812',
    );
    _paymentMap[_payKey('cust_2', prevMonth)] = PaymentRecord(
      id: 'pay_cust_2_$prevMonth',
      customerId: 'cust_2',
      monthYear: prevMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.cash,
      paidAt: DateTime(now.year, now.month - 1, 3),
    );
    _paymentMap[_payKey('cust_3', prevMonth)] = PaymentRecord(
      id: 'pay_cust_3_$prevMonth',
      customerId: 'cust_3',
      monthYear: prevMonth,
      amount: 2500,
      status: PaymentStatus.paid,
      method: PaymentMethod.upi,
      paidAt: DateTime(now.year, now.month - 1, 5),
    );
    _paymentMap[_payKey('cust_4', prevMonth)] = PaymentRecord(
      id: 'pay_cust_4_$prevMonth',
      customerId: 'cust_4',
      monthYear: prevMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.phonepe,
      paidAt: DateTime(now.year, now.month - 1, 7),
    );

    // Seed payments for current month
    // Rahul: Paid with GPay
    _paymentMap[_payKey('cust_1', currentMonth)] = PaymentRecord(
      id: 'pay_cust_1_$currentMonth',
      customerId: 'cust_1',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.gpay,
      paidAt: DateTime(now.year, now.month, 4),
      transactionRef: 'UPI-98210344',
      notes: 'Paid via GPay QR at front desk',
    );

    // Pooja: Paid with Cash
    _paymentMap[_payKey('cust_2', currentMonth)] = PaymentRecord(
      id: 'pay_cust_2_$currentMonth',
      customerId: 'cust_2',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.cash,
      paidAt: DateTime(now.year, now.month, 6),
      notes: 'Received by coach',
    );

    // Ananya: Paid with PhonePe
    _paymentMap[_payKey('cust_4', currentMonth)] = PaymentRecord(
      id: 'pay_cust_4_$currentMonth',
      customerId: 'cust_4',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.paid,
      method: PaymentMethod.phonepe,
      paidAt: DateTime(now.year, now.month, 8),
      transactionRef: 'PP-459201948',
    );

    // Vikram, Karan, Sneha are Pending for current month
    _paymentMap[_payKey('cust_3', currentMonth)] = PaymentRecord(
      id: 'pay_cust_3_$currentMonth',
      customerId: 'cust_3',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.pending,
    );
    _paymentMap[_payKey('cust_5', currentMonth)] = PaymentRecord(
      id: 'pay_cust_5_$currentMonth',
      customerId: 'cust_5',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.pending,
    );
    _paymentMap[_payKey('cust_6', currentMonth)] = PaymentRecord(
      id: 'pay_cust_6_$currentMonth',
      customerId: 'cust_6',
      monthYear: currentMonth,
      amount: 1200,
      status: PaymentStatus.pending,
    );
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
