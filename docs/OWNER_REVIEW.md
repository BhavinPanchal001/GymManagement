# Gym workflow fixes

These changes address the first set of important audit findings. The app still
needs the billing and live-account checks listed below before owner handover.

## What changed

- **Renew membership:** Use “Renew Membership” on the member page or “Renew”
  on the expiry list. This creates a new payment and receipt while keeping the
  previous payment intact. The suggested start is the day after an active
  membership expires, or today for an expired membership. Dates are adjustable.
- **Collect a balance:** Select “Collect Balance” in the pending dues report.
  Enter the amount received, its date and payment method. The date starts at
  today. Partial collections are allowed. Each has its own receipt and appears
  in the month it was received.
- **Correct a payment:** Editing a payment adjusts its original receipt. The
  amount is the total received for that membership, including later collections.
  Corrections cannot reduce it below existing balance receipts. Cancelling
  requires confirmation and marks all associated receipts cancelled. It does
  not record a cash refund.
- **Keep history:** Archive members who leave. Their attendance, payments and
  receipts remain available. Find them through the Archived filter and restore
  them from their member page. Outstanding receipt balances remain visible.
- **Register with payment later:** Select the agreed package and membership dates
  and leave immediate collection off. The full agreed fee appears in outstanding
  dues without requiring attendance. A three-month agreement creates one charge
  in its start month. Package price changes leave this stored fee unchanged.
- **Settle an agreement:** Record the first full or partial payment against the
  pending period. Later collections use “Collect Balance.” Cancelling restores
  an explicit agreement to unpaid and keeps its cancelled receipts.
- **Choose future renewal defaults:** When buying a different duration, select
  “Use this package for future renewals” if it should become the member's default.
  Otherwise the purchase changes only the current period.
- **Mark attendance:** “Mark all present” is safe to repeat. Automatic day and
  month marking skip dates before joining and future dates. Deliberate individual
  backdating remains supported for corrections. Rest days are separate from
  absences.
- **See older debts:** The dashboard includes all recorded outstanding balances.
  The report starts with “All Outstanding,” including advance membership balances.
- **Know where changes are saved:** An owner-specific queue saves changes on the
  phone before upload. Failed uploads remain queued and retry. A payment and
  its receipt upload together. Cloud updates cannot replace edits waiting to
  upload. A banner shows connection problems and offers Retry. Signing out
  preserves that owner's waiting uploads on the same device.
- **Protect live accounts:** Demo reload and “Clear all data” are limited to local
  exploration mode. Live accounts use archiving to preserve history.
- **Receipt accuracy:** WhatsApp shows the actual receipt status, including
  cancelled receipts, the full fee, paid earlier, paid now and the balance after
  that receipt. Cancelled receipts state that they are not proof of payment.
  Decimal fees stay intact in money displays and package/payment editors.
  PDFs use the recorded amount instead of substituting today's package price.
- **Phone layouts:** Plan, validity and fee labels wrap, payment fields fit narrow
  screens, and report actions can continue on another line. Automated checks use
  real Roboto fonts at 320 × 568 and 360 × 800 with text at 130%, including
  registration and payment sheets with the keyboard open.

## Check with a test gym account

1. Register a member, collect part of the fee, then collect the balance on another
   date. Check both receipts and the totals for both months.
2. Renew an active member. Check the old receipt and the new membership dates.
3. Archive and restore a member. Check that attendance and receipts remain.
4. Mark everybody present twice. Already-present members should stay present.
5. Turn off the internet, record a payment and close the app. Reopen on the same
   phone. Check the payment and waiting-upload banner. Reconnect and press Retry.
   Check the payment and receipt from a second device.
6. Try a test account whose cloud access is denied. Check the upload error and
   retained changes.
7. Register a pay-later member on a three-month package. Before entering any
   attendance, check that outstanding dues contain one full package fee. Change
   package settings and confirm the agreed fee is unchanged.
8. Record a partial payment, collect its balance, then renew. Check that the first
   agreement remains in history and the renewal has its own dates and receipt.

## Work still needed before handover

- **Old unpaid records:** New registrations retain explicit agreements. Older
  members without an agreement use attendance to infer pending periods. An old
  price that was never recorded cannot be reconstructed; review those inferred
  periods and fees before relying on historical totals.
- **Cloud checks:** Retry, persistence, account isolation and interrupted local
  saves are tested with simulated failures. Real Firebase permissions,
  reconnection and two-device behaviour still need the test-account checks.
  No real owner data was changed during development.
- **Two devices taking money:** Receipt numbers are still allocated locally.
  Simultaneous collections can choose the same number or overwrite a shared
  balance. The queue does not solve these accounting conflicts.
- **Recovery and attachments:** Waiting uploads survive on the same phone.
  Uninstalling the app or losing the phone can lose them. Photos still use local
  file paths and need a separate backup solution.
- **Release setup:** Configure Firebase access rules and a production signing key
  before distribution. The Android build currently uses the repository's debug
  signing configuration.
- **Web:** The pinned printing dependency has a compatibility problem with the
  installed newer Dart SDK. Web needs a separate dependency update and build check.

## Developer validation

Branch: codex/critical-gym-workflows. Nothing is merged into the original repo.
Tested with Flutter 3.47.2 and Dart 3.13.2. The lockfile and Android settings
include changes required by that SDK.
The Android build requires Android 7.0 or newer (API 24).
The earlier branch build produced an Android APK; that build has not been repeated
for these follow-up changes. Current static analysis reports no issues.
The combined branch passes 117 automated tests, including membership agreements,
save retries, history performance and phone layouts. Live cloud, physical-device
and release-signing acceptance remain outstanding.

    flutter pub get
    flutter analyze --no-pub
    flutter test --no-pub
    flutter build apk --release

Regression tests include test/critical_workflows_test.dart,
test/review_fixes_test.dart, test/membership_agreement_test.dart,
test/pending_history_scale_test.dart and test/phone_layout_test.dart.
