import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/services/cloud_sync_queue.dart';
import 'package:gym/services/member_cloud_store.dart';
import 'package:mock_exceptions/mock_exceptions.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MemberCloudStore store;

  setUp(() async {
    db = FakeFirebaseFirestore();
    store = MemberCloudStore(db, 'owner');
    await db.doc('gyms/owner/settings/memberRemoval').set({'version': 1});
    await store.commit([
      const CloudChange('customers', 'member', {'name': 'Member'}),
    ]);
  });

  test(
    'confirmed cloud deletion keeps a durable guard and is idempotent',
    () async {
      await store.deleteEmptyCustomer('member');
      expect(
        (await db.doc('gyms/owner/customers/member').get()).exists,
        isFalse,
      );
      expect((await db.doc('gyms/owner/memberGuards/member').get()).data(), {
        'hasHistory': false,
        'deleted': true,
      });
      await store.deleteEmptyCustomer('member');
      await store.commit([const CloudChange('customers', 'member', null)]);
    },
  );

  for (final collection in ['attendance', 'payments', 'bills']) {
    test(
      '$collection history contends on the guard and blocks deletion',
      () async {
        await store.commit([
          CloudChange(collection, 'history', {'customerId': 'member'}),
        ]);
        await expectLater(
          store.deleteEmptyCustomer('member'),
          throwsStateError,
        );
        expect(
          (await db.doc('gyms/owner/customers/member').get()).exists,
          isTrue,
        );
        expect(
          (await db.doc('gyms/owner/$collection/history').get()).exists,
          isTrue,
        );
      },
    );

    test(
      'legacy $collection history without a marker still blocks deletion',
      () async {
        await db.doc('gyms/owner/$collection/legacy').set({
          'customerId': 'member',
        });
        await expectLater(
          store.deleteEmptyCustomer('member'),
          throwsStateError,
        );
        expect(
          (await db.doc('gyms/owner/customers/member').get()).exists,
          isTrue,
        );
      },
    );

    test(
      'late offline $collection writes cannot outlive a deleted member',
      () async {
        await store.deleteEmptyCustomer('member');
        await expectLater(
          store.commit([
            CloudChange(collection, 'late', {'customerId': 'member'}),
          ]),
          throwsStateError,
        );
        expect(
          (await db.doc('gyms/owner/$collection/late').get()).exists,
          isFalse,
        );
      },
    );
  }

  test(
    'late customer edits cannot resurrect a permanently deleted member',
    () async {
      await store.deleteEmptyCustomer('member');
      await expectLater(
        store.commit([
          const CloudChange('customers', 'member', {'name': 'Stale edit'}),
        ]),
        throwsStateError,
      );
    },
  );

  test('customer edits never clear a history marker', () async {
    await store.commit([
      const CloudChange('payments', 'payment', {'customerId': 'member'}),
    ]);
    await store.commit([
      const CloudChange('customers', 'member', {'name': 'Edited'}),
    ]);
    expect(
      (await db.doc('gyms/owner/memberGuards/member').get())
          .data()?['hasHistory'],
      isTrue,
    );
    await expectLater(store.deleteEmptyCustomer('member'), throwsStateError);
  });

  test(
    'missing protocol activation blocks deletion but permits legacy saves',
    () async {
      await db.doc('gyms/owner/settings/memberRemoval').delete();
      await expectLater(store.deleteEmptyCustomer('member'), throwsStateError);
      await store.commit([
        const CloudChange('customers', 'member', {'isActive': false}),
      ]);
      await expectLater(
        store.commit([const CloudChange('customers', 'member', null)]),
        throwsStateError,
      );
      expect(
        (await db.doc('gyms/owner/customers/member').get()).exists,
        isTrue,
      );
    },
  );

  test('missing migration guard fails closed', () async {
    await db.doc('gyms/owner/memberGuards/member').delete();
    await expectLater(store.deleteEmptyCustomer('member'), throwsStateError);
    expect((await db.doc('gyms/owner/customers/member').get()).exists, isTrue);
  });

  test(
    'older rules without activation-document access still allow ordinary saves',
    () async {
      final legacy = FakeFirebaseFirestore();
      whenCalling(Invocation.method(#get, null))
          .on(legacy.doc('gyms/owner/settings/memberRemoval'))
          .thenThrow(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          );
      final legacyStore = MemberCloudStore(legacy, 'owner');
      await legacyStore.commit([
        const CloudChange('customers', 'member', {
          'name': 'Member',
          'isActive': false,
        }),
      ]);
      await expectLater(
        legacyStore.deleteEmptyCustomer('member'),
        throwsStateError,
      );
      expect(
        (await legacy.doc('gyms/owner/customers/member').get()).exists,
        isTrue,
      );
    },
  );

  test('queued deletion cannot bypass online confirmation', () async {
    await expectLater(
      store.commit([const CloudChange('customers', 'member', null)]),
      throwsStateError,
    );
    expect((await db.doc('gyms/owner/customers/member').get()).exists, isTrue);
  });

  test('new member, agreement and receipt upload together', () async {
    await store.commit([
      const CloudChange('customers', 'new', {'name': 'New member'}),
      const CloudChange('payments', 'new-payment', {'customerId': 'new'}),
      const CloudChange('bills', 'new-bill', {'customerId': 'new'}),
    ]);
    expect(
      (await db.doc('gyms/owner/memberGuards/new').get()).data()?['hasHistory'],
      isTrue,
    );
    expect((await db.doc('gyms/owner/bills/new-bill').get()).exists, isTrue);
  });

  test(
    'partitioning preserves payment/receipt pairs and rules access limits',
    () {
      final changes = [
        for (var i = 0; i < 20; i++)
          CloudChange('payments', 'p$i', {'customerId': 'm$i'}),
        for (var i = 0; i < 20; i++)
          CloudChange('bills', 'b$i', {'customerId': 'm$i'}),
      ];
      final batches = partitionCloudChanges(changes);
      expect(batches, hasLength(5));
      for (final batch in batches) {
        expect(batch.map((c) => c.memberId).toSet(), hasLength(4));
        for (final id in batch.map((c) => c.memberId).toSet()) {
          expect(batch.where((c) => c.memberId == id), hasLength(2));
        }
      }
    },
  );
}
