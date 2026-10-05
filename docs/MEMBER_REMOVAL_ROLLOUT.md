# Safe member removal

Local permanent deletion works without Firebase. Synced permanent deletion stays
disabled until the server safeguards below are activated. Archiving remains
available before activation and offline.

## How the protection works

Every member has `gyms/{owner}/memberGuards/{customerId}` with two booleans:
`hasHistory` and `deleted`. Attendance, payments and receipts mark `hasHistory`
in the same transaction as the history write. Permanent deletion reads the same
guard, verifies server history, marks `deleted`, and deletes the member atomically.
Concurrent history forces deletion to retry and then stop. Deletion winning first
rejects late history and stale member edits, including offline outbox uploads.
Neither flag can be reset by clients. The guard is deliberately retained forever.

Firestore rules are essential: a transaction alone cannot protect against an older
app that writes history without updating the guard. Old app versions must be
upgraded before this protocol is activated. Rejected edits stay in their local
outbox; they are not silently discarded.

## Administrator rollout (not run against production by this PR)

1. Back up the gym's Firestore data and schedule a short maintenance window.
   Stop edits on **all devices**, including offline devices that will reconnect.
2. Install the updated app on all devices. Keep edits paused until step 6.
3. Using trusted Admin SDK access or the Firebase console, backfill a guard for
   every existing member. Set `hasHistory: true` if **any** attendance, payment
   or bill references that member, including absent/rest attendance, unpaid dues
   and cancelled receipts. Otherwise use `false`. Set `deleted: false`.
   Do not clear existing true/deleted guards. Audit orphaned legacy records too;
   preserve them and mark their guard `hasHistory: true` rather than deleting them.
4. Review and merge `firebase/member-removal.rules` into the **existing** deployed
   rules. It is a reference for the gym subtree, not a replacement for unrelated
   account/profile rules. Remove overlapping broad gym write permissions:
   Firestore allow rules are additive, so a broad allow would bypass the guards.
   Preserve existing authentication and any stricter validation/compliance rules.
   Test the merged rules before deploying them.
5. After backfill and rules deployment, use trusted administrator access to create
   `gyms/{owner}/settings/memberRemoval` with `{ "version": 1 }` for that owner.
   Client apps cannot activate this flag. Never activate it before steps 3–4.
6. Resume edits. Verify one history-free mistaken member can be deleted, a member
   with history can only be archived, and another device cannot re-create a deleted
   member or upload new history for them. Monitor older app outboxes for rejections.

For a new gym, deploy the rules before activation and create the activation document
administratively. The updated app creates guards when new members are uploaded.
Never delete guards during a demo reset or reuse a deleted customer ID.

## Automated checks

```powershell
flutter analyze
flutter test test/member_removal_test.dart test/member_cloud_store_test.dart
Set-Location firebase
npm ci
npm exec --yes --package=firebase-tools@15.32.1 -- firebase emulators:exec --only firestore --project demo-gym-removal "npm test"
```

The emulator tests need Node.js 20+ and Java 21+. They use a `demo-` project and do
not contact production Firebase. They cover rule enforcement, concurrent attendance,
payment and receipt writes, immutable history/deletion guards and owner isolation.
The Dart tests exercise the actual app persistence/transaction implementation.
