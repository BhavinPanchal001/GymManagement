# Payment date protection: regression audit

The complete existing automated suite was run against both versions. A separate
temporary copy retained the current project and its other working changes, but
used the payment service and payment form from before the date fix. This kept
unrelated settings and sign-out changes the same in both runs.

| Version | Passing tests | Failing tests |
| --- | ---: | ---: |
| Before the date fix | 333 | 49 |
| Audited date fix | 361 | 49 |

**The failure names are identical. No new failing test remains.** The extra
28 passes are tests added for the date protection and its compatibility. The
existing 49 failures still need separate work; the entire app suite is not green.

## Problems found and corrected

1. The first version blocked an existing historical-payment workflow that keeps
   an older attendance-created debt while recording a separate membership.
   The protection now distinguishes that workflow from changing the dates of an
   explicitly selected or agreed membership. The original regression test passes
   again without changing its expectations.
2. Older membership timestamps could contain hours and minutes. A same-day
   boundary could evade the check because the clock times differed. Comparisons
   now use calendar dates consistently.
3. The Fresh Start, Continuous and Package Duration controls could overflow on
   a narrow phone. They now wrap. The warning dialog is scrollable, and a new
   check verifies that it can be read and dismissed with the keyboard open.

## Compatibility checked

- Normal full payment and late received dates against the original dates.
- Partial payment followed by balance collection and separate receipts.
- Normal consecutive paid renewals and renewals while genuine older debt remains.
- Attendance-created cycles and explicit registration agreements.
- Corrections to payment method or received date without moving membership dates.
- Safe date corrections when all visits remain covered.
- Visits covered by another paid period, including older overlapping history.
- Absent and rest days do not cause false rejection.
- Correction of an already-saved mistaken period removes the artificial due and
  keeps the original receipt number and collected amount.
- Rejection changes neither receipts nor balances; correcting and retrying the
  same form creates only one receipt.
- Attendance added after the form preview is checked again when saving.
- Inclusive start/end dates, shortened periods, multi-month packages, leap
  February and year boundaries.
- Existing fee-adjustment, credit/refund, report, account and navigation tests
  were included in the full suite comparison.

Static analysis: no issues found. iOS simulator build: succeeded.

## Limits

No new automated regression was found; this is not proof of every possible
device or data combination. Live Firebase delivery, production security rules
and simultaneous changes on two physical devices remain unverified because
valid Firebase setup is unavailable. The date fix does not change that setup.

## Evidence

- `outputs/date-guard-audit-baseline.jsonl`
- `outputs/date-guard-audit-final.jsonl`
- `outputs/date-guard-audit-final-comparison.json`
- `outputs/date-guard-audit-boundaries.log`
- `outputs/date-guard-audit-analysis.log`
- `outputs/date-guard-audit-build.log`
- `test/payment_attendance_date_guard_test.dart`
