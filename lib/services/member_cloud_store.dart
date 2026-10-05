import 'package:cloud_firestore/cloud_firestore.dart';

import 'cloud_sync_queue.dart';

/// History writes and removal contend on the same durable per-member guard.
class MemberCloudStore {
  final FirebaseFirestore firestore;
  final String ownerId;

  MemberCloudStore(this.firestore, this.ownerId);

  DocumentReference<Map<String, dynamic>> _ref(String collection, String id) =>
      firestore.collection('gyms').doc(ownerId).collection(collection).doc(id);

  Future<bool> _enabled() async {
    try {
      final configuration = await _ref(
        'settings',
        'memberRemoval',
      ).get(const GetOptions(source: Source.server));
      return configuration.data()?['version'] == 1;
    } on FirebaseException catch (error) {
      // Older rules may allow settings/config but not this activation document.
      if (error.code == 'permission-denied') return false;
      rethrow;
    }
  }

  Future<void> deleteEmptyCustomer(String customerId) async {
    if (!await _enabled()) {
      throw StateError(
        'Safe cloud deletion needs activation by your gym administrator. '
        'You can archive this member instead.',
      );
    }
    await firestore.runTransaction((transaction) async {
      final guardRef = _ref('memberGuards', customerId);
      final customerRef = _ref('customers', customerId);
      final guard = (await transaction.get(guardRef)).data();
      final customer = await transaction.get(customerRef);
      if (guard == null) {
        throw StateError('Sync this member before deleting permanently.');
      }
      if (guard['hasHistory'] == true) throw _historyError();
      if (guard['deleted'] == true && !customer.exists) return;
      if (!customer.exists) throw StateError('Member not found.');
      // Legacy history is checked too. Concurrent writes must update the guard,
      // so the transaction retries if history arrives during these server reads.
      final history = await Future.wait([
        for (final collection in ['attendance', 'payments', 'bills'])
          firestore
              .collection('gyms')
              .doc(ownerId)
              .collection(collection)
              .where('customerId', isEqualTo: customerId)
              .limit(1)
              .get(const GetOptions(source: Source.server)),
      ]);
      if (history.any((snapshot) => snapshot.docs.isNotEmpty)) {
        throw _historyError();
      }
      transaction.set(guardRef, {'hasHistory': false, 'deleted': true});
      transaction.delete(customerRef);
    });
  }

  StateError _historyError() => StateError(
    'This member has attendance, payments, membership dues or receipts. '
    'Archive instead to preserve their history.',
  );

  Future<void> commit(List<CloudChange> changes) async {
    final guarded = await _enabled();
    if (!guarded) {
      if (changes.any((c) => c.collection == 'customers' && c.data == null)) {
        throw StateError('Safe cloud deletion has not been activated.');
      }
      final batch = firestore.batch();
      for (final change in changes) {
        final ref = _ref(change.collection, change.documentId);
        if (change.data == null) {
          batch.delete(ref);
        } else {
          batch.set(ref, change.data!);
        }
      }
      await batch.commit();
      return;
    }
    for (final chunk in partitionCloudChanges(changes)) {
      await _commitGuarded(chunk);
    }
  }

  Future<void> _commitGuarded(List<CloudChange> changes) async {
    final ids = changes.map((c) => c.memberId).whereType<String>().toSet();
    final historyIds = changes
        .where(
          (c) =>
              c.collection != 'customers' &&
              c.memberId != null &&
              c.data != null,
        )
        .map((c) => c.memberId!)
        .toSet();
    final upserts = changes
        .where((c) => c.collection == 'customers' && c.data != null)
        .map((c) => c.documentId)
        .toSet();
    await firestore.runTransaction((transaction) async {
      final guards = <String, Map<String, dynamic>?>{};
      for (final id in ids) {
        guards[id] = (await transaction.get(_ref('memberGuards', id))).data();
      }
      for (final id in historyIds.difference(upserts)) {
        if (!(await transaction.get(_ref('customers', id))).exists) {
          throw StateError(
            'This member was removed. History cannot be uploaded.',
          );
        }
      }
      for (final id in ids) {
        final guard = guards[id];
        final onlyDeletion = changes
            .where((c) => c.memberId == id)
            .every((c) => c.collection == 'customers' && c.data == null);
        if (onlyDeletion) {
          if (guard?['deleted'] != true || guard?['hasHistory'] != false) {
            throw StateError('Member deletion must be confirmed online first.');
          }
        } else {
          if (guard?['deleted'] == true) {
            throw StateError(
              'This member was removed. Changes cannot be uploaded.',
            );
          }
          transaction.set(_ref('memberGuards', id), {
            'hasHistory':
                guard?['hasHistory'] == true || historyIds.contains(id),
            'deleted': false,
          });
        }
      }
      for (final change in changes) {
        final ref = _ref(change.collection, change.documentId);
        if (change.data == null) {
          transaction.delete(ref);
        } else {
          transaction.set(ref, change.data!);
        }
      }
    });
  }
}
