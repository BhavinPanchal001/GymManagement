import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/attendance.dart';
import '../models/payment.dart';
import '../models/bill.dart';
import '../models/expense.dart';
import '../models/gym_settings.dart';
import 'cloud_sync_queue.dart';

/// Callback typedef for when Firestore snapshot data arrives.
typedef FirestoreDataCallback =
    void Function({
      List<Customer>? customers,
      Map<String, AttendanceRecord>? attendanceMap,
      Map<String, PaymentRecord>? paymentMap,
      Map<String, BillRecord>? billsMap,
      List<ExpenseRecord>? expenses,
      GymSettings? settings,
    });

class FirestoreService {
  FirestoreService._internal();
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;

  FirebaseFirestore? _firestore;
  String? _userId;
  bool _isAttached = false;
  bool _persistenceConfigured = false;
  void Function(Object)? onSyncError;

  final List<StreamSubscription> _subscriptions = [];

  /// Callback to push snapshot updates back to GymService
  FirestoreDataCallback? onDataChanged;

  bool get isAttached => _isAttached;
  String? get userId => _userId;

  DocumentReference? get _settingsDoc {
    if (_firestore == null || _userId == null) return null;
    return _firestore!
        .collection('gyms')
        .doc(_userId)
        .collection('settings')
        .doc('config');
  }

  CollectionReference? get _customersCol {
    if (_firestore == null || _userId == null) return null;
    return _firestore!.collection('gyms').doc(_userId).collection('customers');
  }

  CollectionReference? get _attendanceCol {
    if (_firestore == null || _userId == null) return null;
    return _firestore!.collection('gyms').doc(_userId).collection('attendance');
  }

  CollectionReference? get _paymentsCol {
    if (_firestore == null || _userId == null) return null;
    return _firestore!.collection('gyms').doc(_userId).collection('payments');
  }

  CollectionReference? get _billsCol {
    if (_firestore == null || _userId == null) return null;
    return _firestore!.collection('gyms').doc(_userId).collection('bills');
  }

  CollectionReference? get _expensesCol {
    if (_firestore == null || _userId == null) return null;
    return _firestore!.collection('gyms').doc(_userId).collection('expenses');
  }

  // ==================== LIFECYCLE ====================

  /// Attach to a gym owner's Firestore data and start listening.
  Future<void> attachUser(
    String userId, {
    FirestoreDataCallback? callback,
    void Function(Object)? onError,
  }) async {
    if (_isAttached && _userId == userId) return;

    // Detach previous user if any
    await detachUser();

    try {
      _firestore = FirebaseFirestore.instance;
      // Enable offline persistence (default on mobile, explicit for web)
      if (!_persistenceConfigured) {
        _firestore!.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }
      _persistenceConfigured = true;
    } catch (e) {
      debugPrint('FirestoreService: Error getting Firestore instance: $e');
      rethrow;
    }

    _userId = userId;
    _isAttached = true;
    onDataChanged = callback;
    onSyncError = onError;

    _listenToCustomers();
    _listenToAttendance();
    _listenToPayments();
    _listenToBills();
    _listenToExpenses();
    _listenToSettings();

    debugPrint('FirestoreService: Attached to user $userId');
  }

  /// Detach from the current user — cancel all listeners.
  Future<void> detachUser() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _userId = null;
    _isAttached = false;
    onDataChanged = null;
    onSyncError = null;
    debugPrint('FirestoreService: Detached');
  }

  // ==================== SNAPSHOT LISTENERS ====================

  void _listenToCustomers() {
    final col = _customersCol;
    if (col == null) return;

    final sub = col.snapshots().listen(
      (snapshot) {
        final customers = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Customer.fromMap(data);
        }).toList();

        // Sort by name for consistent ordering
        customers.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        onDataChanged?.call(customers: customers);
      },
      onError: (e) {
        debugPrint('FirestoreService: Customers listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  void _listenToAttendance() {
    final col = _attendanceCol;
    if (col == null) return;

    final sub = col.snapshots().listen(
      (snapshot) {
        final map = <String, AttendanceRecord>{};
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final record = AttendanceRecord.fromMap(data);
          map["${record.customerId}_${record.dateKey}"] = record;
        }
        onDataChanged?.call(attendanceMap: map);
      },
      onError: (e) {
        debugPrint('FirestoreService: Attendance listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  void _listenToPayments() {
    final col = _paymentsCol;
    if (col == null) return;

    final sub = col.snapshots().listen(
      (snapshot) {
        final map = <String, PaymentRecord>{};
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final record = PaymentRecord.fromMap(data);
          map[record.id.isNotEmpty ? record.id : doc.id] = record;
        }
        onDataChanged?.call(paymentMap: map);
      },
      onError: (e) {
        debugPrint('FirestoreService: Payments listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  void _listenToBills() {
    final col = _billsCol;
    if (col == null) return;

    final sub = col.snapshots().listen(
      (snapshot) {
        final map = <String, BillRecord>{};
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final record = BillRecord.fromMap(data);
          map[record.id.isNotEmpty ? record.id : doc.id] = record;
        }
        onDataChanged?.call(billsMap: map);
      },
      onError: (e) {
        debugPrint('FirestoreService: Bills listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  void _listenToExpenses() {
    final col = _expensesCol;
    if (col == null) return;

    final sub = col.snapshots().listen(
      (snapshot) {
        final expenses = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return ExpenseRecord.fromMap(data);
        }).toList();

        // Sort by date descending (most recent first)
        expenses.sort((a, b) => b.date.compareTo(a.date));

        onDataChanged?.call(expenses: expenses);
      },
      onError: (e) {
        debugPrint('FirestoreService: Expenses listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  void _listenToSettings() {
    final doc = _settingsDoc;
    if (doc == null) return;

    final sub = doc.snapshots().listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          final settings = GymSettings.fromMap(data);
          onDataChanged?.call(settings: settings);
        }
      },
      onError: (e) {
        debugPrint('FirestoreService: Settings listener error: $e');
        onSyncError?.call(e);
      },
    );

    _subscriptions.add(sub);
  }

  // ==================== WRITE OPERATIONS ====================

  Future<Map<String, Set<String>>> fetchAllDocumentIds(String ownerId) async {
    if (!_isAttached || _firestore == null || _userId != ownerId) {
      throw StateError('Connect to the cloud before restoring this account.');
    }
    const collections = [
      'customers',
      'attendance',
      'payments',
      'bills',
      'expenses',
    ];
    try {
      final snapshots = await Future.wait(
        collections.map(
          (collection) => _firestore!
              .collection('gyms')
              .doc(ownerId)
              .collection(collection)
              .get(const GetOptions(source: Source.server)),
        ),
      );
      return {
        for (var index = 0; index < collections.length; index++)
          collections[index]: snapshots[index].docs
              .map((document) => document.id)
              .toSet(),
      };
    } catch (_) {
      throw StateError(
        'Could not verify all cloud records. Connect to the internet and try restore again.',
      );
    }
  }

  /// Owner checks prevent a delayed retry from writing to another account.
  Future<void> commitChanges(String ownerId, List<CloudChange> changes) async {
    if (!_isAttached || _firestore == null || _userId != ownerId) {
      throw StateError('This account is not connected.');
    }
    const allowed = {
      'customers',
      'attendance',
      'payments',
      'bills',
      'expenses',
      'settings',
    };
    final batch = _firestore!.batch();
    for (final change in changes) {
      if (!allowed.contains(change.collection) ||
          change.documentId.isEmpty ||
          change.documentId.contains('/')) {
        throw ArgumentError('Invalid document change.');
      }
      final ref = _firestore!
          .collection('gyms')
          .doc(ownerId)
          .collection(change.collection)
          .doc(change.documentId);
      if (change.data == null) {
        batch.delete(ref);
      } else {
        batch.set(ref, change.data!);
      }
    }
    await batch.commit();
  }

  /// Upsert a single customer document.
  Future<void> upsertCustomer(Customer customer) async {
    try {
      await _customersCol?.doc(customer.id).set(customer.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertCustomer error: $e');
      rethrow;
    }
  }

  /// Upsert a single attendance record.
  Future<void> upsertAttendance(AttendanceRecord record) async {
    try {
      final docId = "${record.customerId}_${record.dateKey}";
      await _attendanceCol?.doc(docId).set(record.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertAttendance error: $e');
      rethrow;
    }
  }

  /// Batch upsert multiple attendance records (for bulk month marking).
  Future<void> batchUpsertAttendance(List<AttendanceRecord> records) async {
    if (records.isEmpty) return;
    try {
      // Firestore batches are limited to 500 writes
      final chunks = _chunkList(records, 450);
      for (final chunk in chunks) {
        final batch = _firestore!.batch();
        for (final record in chunk) {
          final docId = "${record.customerId}_${record.dateKey}";
          batch.set(_attendanceCol!.doc(docId), record.toMap());
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('FirestoreService: batchUpsertAttendance error: $e');
      rethrow;
    }
  }

  /// Upsert a single payment record.
  Future<void> upsertPayment(PaymentRecord record) async {
    try {
      await _paymentsCol?.doc(record.id).set(record.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertPayment error: $e');
      rethrow;
    }
  }

  /// Batch upsert multiple payment records.
  Future<void> batchUpsertPayments(List<PaymentRecord> records) async {
    if (records.isEmpty) return;
    try {
      final chunks = _chunkList(records, 450);
      for (final chunk in chunks) {
        final batch = _firestore!.batch();
        for (final record in chunk) {
          batch.set(_paymentsCol!.doc(record.id), record.toMap());
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('FirestoreService: batchUpsertPayments error: $e');
      rethrow;
    }
  }

  /// Delete a payment record by document id.
  Future<void> deletePayment(String docId) async {
    try {
      await _paymentsCol?.doc(docId).delete();
    } catch (e) {
      debugPrint('FirestoreService: deletePayment error: $e');
      rethrow;
    }
  }

  /// Upsert a single bill record.
  Future<void> upsertBill(BillRecord record) async {
    try {
      await _billsCol?.doc(record.id).set(record.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertBill error: $e');
      rethrow;
    }
  }

  /// Batch upsert multiple bill records.
  Future<void> batchUpsertBills(List<BillRecord> records) async {
    if (records.isEmpty) return;
    try {
      final chunks = _chunkList(records, 450);
      for (final chunk in chunks) {
        final batch = _firestore!.batch();
        for (final record in chunk) {
          batch.set(_billsCol!.doc(record.id), record.toMap());
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('FirestoreService: batchUpsertBills error: $e');
      rethrow;
    }
  }

  /// Delete a bill record by document id.
  Future<void> deleteBill(String docId) async {
    try {
      await _billsCol?.doc(docId).delete();
    } catch (e) {
      debugPrint('FirestoreService: deleteBill error: $e');
      rethrow;
    }
  }

  /// Upsert a single expense record.
  Future<void> upsertExpense(ExpenseRecord record) async {
    try {
      await _expensesCol?.doc(record.id).set(record.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertExpense error: $e');
      rethrow;
    }
  }

  /// Delete an expense record.
  Future<void> deleteExpense(String expenseId) async {
    try {
      await _expensesCol?.doc(expenseId).delete();
    } catch (e) {
      debugPrint('FirestoreService: deleteExpense error: $e');
      rethrow;
    }
  }

  /// Save gym settings document.
  Future<void> upsertSettings(GymSettings settings) async {
    try {
      await _settingsDoc?.set(settings.toMap());
    } catch (e) {
      debugPrint('FirestoreService: upsertSettings error: $e');
      rethrow;
    }
  }

  // ==================== DATA MIGRATION ====================

  /// One-time migration: push all local data to Firestore.
  /// Returns true if migration was performed, false if skipped.
  Future<bool> migrateLocalData({
    required List<Customer> customers,
    required Map<String, AttendanceRecord> attendanceMap,
    required Map<String, PaymentRecord> paymentMap,
    required Map<String, BillRecord> billsMap,
    required List<ExpenseRecord> expenses,
    required GymSettings settings,
  }) async {
    if (!_isAttached || _firestore == null) return false;

    try {
      // Check if cloud already has data (settings doc exists = already migrated)
      final settingsSnap = await _settingsDoc?.get();
      if (settingsSnap != null && settingsSnap.exists) {
        debugPrint(
          'FirestoreService: Cloud data already exists, skipping migration.',
        );
        return false;
      }

      debugPrint('FirestoreService: Starting local → cloud data migration...');

      // 1. Migrate settings
      await upsertSettings(settings);

      // 2. Migrate customers in batches
      final customerChunks = _chunkList(customers, 450);
      for (final chunk in customerChunks) {
        final batch = _firestore!.batch();
        for (final customer in chunk) {
          batch.set(_customersCol!.doc(customer.id), customer.toMap());
        }
        await batch.commit();
      }

      // 3. Migrate attendance in batches
      final attRecords = attendanceMap.values.toList();
      await batchUpsertAttendance(attRecords);

      // 4. Migrate payments in batches
      final payRecords = paymentMap.values.toList();
      await batchUpsertPayments(payRecords);

      // 5. Migrate bills in batches
      final billRecords = billsMap.values.toList();
      final billChunks = _chunkList(billRecords, 450);
      for (final chunk in billChunks) {
        final batch = _firestore!.batch();
        for (final bill in chunk) {
          batch.set(_billsCol!.doc(bill.id), bill.toMap());
        }
        await batch.commit();
      }

      // 6. Migrate expenses in batches
      final expChunks = _chunkList(expenses, 450);
      for (final chunk in expChunks) {
        final batch = _firestore!.batch();
        for (final expense in chunk) {
          batch.set(_expensesCol!.doc(expense.id), expense.toMap());
        }
        await batch.commit();
      }

      debugPrint(
        'FirestoreService: Migration complete! '
        '${customers.length} customers, '
        '${attRecords.length} attendance, '
        '${payRecords.length} payments, '
        '${billRecords.length} bills, '
        '${expenses.length} expenses.',
      );

      return true;
    } catch (e) {
      debugPrint('FirestoreService: Migration error: $e');
      return false;
    }
  }

  // ==================== BULK OPERATIONS (for resetToDemoData) ====================

  /// Clear all collections for the current user (used when resetting to demo data).
  Future<void> clearAllData() async {
    if (!_isAttached || _firestore == null) return;

    try {
      await _deleteCollection(_customersCol);
      await _deleteCollection(_attendanceCol);
      await _deleteCollection(_paymentsCol);
      await _deleteCollection(_billsCol);
      await _deleteCollection(_expensesCol);
      await _settingsDoc?.delete();
    } catch (e) {
      debugPrint('FirestoreService: clearAllData error: $e');
      rethrow;
    }
  }

  Future<void> _deleteCollection(CollectionReference? col) async {
    if (col == null) return;
    final snapshot = await col.get();
    if (snapshot.docs.isEmpty) return;

    final chunks = _chunkList(snapshot.docs, 450);
    for (final chunk in chunks) {
      final batch = _firestore!.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  // ==================== HELPERS ====================

  /// Splits a list into chunks of [chunkSize].
  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
