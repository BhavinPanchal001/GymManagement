import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, runTransaction, setDoc, writeBatch } from 'firebase/firestore';

let env;
let db;
const ref = (collection, id = 'member') => doc(db, `gyms/owner/${collection}/${id}`);
const seed = async (collection, id, data) => env.withSecurityRulesDisabled(async (ctx) => {
  await setDoc(doc(ctx.firestore(), `gyms/owner/${collection}/${id}`), data);
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-gym-removal',
    firestore: { rules: await readFile(new URL('./member-removal.rules', import.meta.url), 'utf8') },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  db = env.authenticatedContext('owner').firestore();
  await seed('customers', 'member', { name: 'Member' });
  await seed('memberGuards', 'member', { hasHistory: false, deleted: false });
});
after(async () => env?.cleanup());

const remove = async (onRead = async () => {}) => runTransaction(db, async (transaction) => {
  const guard = await transaction.get(ref('memberGuards'));
  await onRead();
  if (guard.data().hasHistory || guard.data().deleted) throw new Error('History prevents removal');
  transaction.update(ref('memberGuards'), { deleted: true });
  transaction.delete(ref('customers'));
});
const history = async (collection, onRead = async () => {}) => runTransaction(db, async (transaction) => {
  const guard = await transaction.get(ref('memberGuards'));
  const customer = await transaction.get(ref('customers'));
  await onRead();
  if (guard.data().deleted || !customer.exists()) throw new Error('Member removed');
  transaction.update(ref('memberGuards'), { hasHistory: true });
  transaction.set(ref(collection, 'history'), { customerId: 'member' });
});

test('unguarded deletion and history writes are refused, including old clients', async () => {
  await assertFails(deleteDoc(ref('customers')));
  for (const collection of ['attendance', 'payments', 'bills']) {
    await assertFails(setDoc(ref(collection, 'history'), { customerId: 'member' }));
  }
  await assertFails(setDoc(ref('settings', 'memberRemoval'), { version: 1 }));
});

test('empty member removal is atomic and leaves an immutable guard', async () => {
  await assertSucceeds(remove());
  assert.equal((await getDoc(ref('customers'))).exists(), false);
  assert.equal((await getDoc(ref('memberGuards'))).data().deleted, true);
  await assertFails(deleteDoc(ref('memberGuards')));
  await assertFails(setDoc(ref('memberGuards'), { hasHistory: false, deleted: false }));
  await assertFails(setDoc(ref('customers'), { name: 'Stale offline edit' }));
});

for (const collection of ['attendance', 'payments', 'bills']) {
  test(`${collection} arriving while deletion waits wins and prevents removal`, async () => {
    let started;
    let release;
    const ready = new Promise((resolve) => { started = resolve; });
    const resume = new Promise((resolve) => { release = resolve; });
    let first = true;
    const deletion = remove(async () => {
      if (!first) return;
      first = false;
      started();
      await resume;
    });
    // Attach the rejection handler before resuming the concurrent transaction.
    const failed = assert.rejects(deletion);
    await ready;
    await assertSucceeds(history(collection));
    release();
    await failed;
    assert.equal((await getDoc(ref('customers'))).exists(), true);
    assert.equal((await getDoc(ref(collection, 'history'))).exists(), true);
  });

  test(`${collection} arriving after deletion cannot create an orphan`, async () => {
    await remove();
    await assert.rejects(history(collection));
    await assertFails(setDoc(ref(collection, 'late'), { customerId: 'member' }));
    assert.equal((await getDoc(ref(collection, 'late'))).exists(), false);
  });

  test(`${collection} already in flight retries and stops when deletion wins`, async () => {
    let started;
    let release;
    const ready = new Promise((resolve) => { started = resolve; });
    const resume = new Promise((resolve) => { release = resolve; });
    let first = true;
    const write = history(collection, async () => {
      if (!first) return;
      first = false;
      started();
      await resume;
    });
    const failed = assert.rejects(write);
    await ready;
    await assertSucceeds(remove());
    release();
    await failed;
    assert.equal((await getDoc(ref('customers'))).exists(), false);
    assert.equal((await getDoc(ref(collection, 'history'))).exists(), false);
  });
}

test('a member with backfilled history cannot be deleted or have its guard reset', async () => {
  await seed('memberGuards', 'member', { hasHistory: true, deleted: false });
  const batch = writeBatch(db);
  batch.set(ref('memberGuards'), { hasHistory: false, deleted: true });
  batch.delete(ref('customers'));
  await assertFails(batch.commit());
  await assertFails(setDoc(ref('memberGuards'), { hasHistory: false, deleted: false }));
  await assertSucceeds(setDoc(ref('customers'), { name: 'Archived', isActive: false }));
});

test('new member, payment and receipt commit together within rule limits', async () => {
  const batch = writeBatch(db);
  for (let i = 0; i < 4; i++) {
    const id = `new-${i}`;
    batch.set(ref('memberGuards', id), { hasHistory: true, deleted: false });
    batch.set(ref('customers', id), { name: id });
    batch.set(ref('payments', id), { customerId: id });
    batch.set(ref('bills', id), { customerId: id });
  }
  await assertSucceeds(batch.commit());
});

test('other owners and unauthenticated clients cannot read or write gym data', async () => {
  for (const context of [env.authenticatedContext('other'), env.unauthenticatedContext()]) {
    const foreign = doc(context.firestore(), 'gyms/owner/memberGuards/member');
    await assertFails(getDoc(foreign));
    await assertFails(setDoc(foreign, { hasHistory: false, deleted: true }));
  }
});
