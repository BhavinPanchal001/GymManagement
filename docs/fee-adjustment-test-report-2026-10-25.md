# Fee adjustment testing — 25 October 2026

## Result

**69 automated checks for fee adjustments passed.** Two problems found during
the expanded checks were fixed:

1. A fully used small credit could leave a tiny fraction behind. Credit and
   remaining fees now round to currency precision so a settled amount is zero.
2. Invalid text such as `NaN` or `Infinity` in a credit/refund amount could crash
   the review screen. Invalid values are now rejected before review.

## Scenarios checked

| Area | Checks covered | Result |
| --- | --- | --- |
| The member's 15-day break | Two unpaid monthly fees; reducing only the selected month from ₹600 to ₹300 leaves ₹900 due | Passed |
| Paid and unpaid fees | No payment, partial payment and full payment; reductions, increases and full waivers | Passed |
| Repeated changes | Original fee stays visible; reasons remain in order; reinstating a waived fee | Passed |
| Invalid entries | Missing reason, unchanged fee, negative/zero amounts where disallowed, too many decimals, invalid numbers and amounts above available credit | Passed |
| Credit use | Partial use, full use, two uses against one period, and credit that fully covers a new period | Passed |
| Money returned | Full and partial returns, return followed by credit use, required reason and correct net collections | Passed |
| Preventing mistakes | Wrong member, same source/target, old form data, changed target and two simultaneous attempts on one phone | Passed |
| Receipts and income | Old receipts retained, historical balances preserved, credit is not new income, returns reduce net collections | Passed |
| Decimal money | Split use/return of ₹0.30; exact zero when exhausted; remaining fee rounds correctly | Passed after fix |
| Dates and packages | Leap February, year change, month end and multi-month packages; dates and future prices preserved | Passed |
| Tax | Included and added tax settings; adjusted fee recalculates its tax and old receipt data stays unchanged | Passed |
| Archived members | Discounts/returns allowed on retained history; starting a new period requires restoring the member | Passed |
| Saving and recovery | Simulated failed local saves leave cash/credit unchanged; owner-scoped reload preserves history; credit transfer queues both sides together | Passed |
| Screen behaviour | Reason and confirmation required, cancellation saves nothing, successful credit use hides exhausted controls, invalid refund input is safe | Passed |
| Phone layout | Credit controls, dropdown and long adjustment history on 320-pixel and 393-pixel wide phone layouts | Passed |
| Older records | Records without adjustment fields remain readable | Passed |

## Wider app checks

- Full automated app run: **333 passed, 49 failed**.
- All 69 fee-adjustment checks passed within that run.
- 48 failure names match the earlier audit. The remaining registration-layout
  characterization test also fails against the original committed source,
  verified in a separate temporary checkout. No new failure from fee adjustments
  was identified. The wider app suite is still not fully passing.
- Static analysis: **no issues found**.
- The earlier simulator check saved a ₹600 → ₹300 change and verified its
  original fee, reason and history after reopening the app.

## Checks that remain unavailable

These results do not prove every possible device/data combination. In particular:

- Live cloud upload and delivery need valid Firebase setup and test accounts.
- Simultaneous changes on two real devices have not been accepted as safe.
  Same-phone conflict prevention and queued transfer recovery were tested;
  these do not establish two-device conflict handling.
- Real bank/UPI transfers are outside this feature. “Record money returned”
  records a return the owner has already made.
- Physical Android devices, OS interruptions during a disk write and production
  Firebase permission rules were not exercised during this round.

## Evidence

- Tests: `test/fee_adjustment_test.dart` and
  `test/fee_adjustment_edge_cases_test.dart`.
- Full run: `outputs/gym-fee-full-suite.jsonl`.
- Failure list: `outputs/gym-fee-full-failures.json`.
- Focused run: `outputs/gym-fee-expanded-tests.log`.
- Analysis: `outputs/gym-fee-analysis.log`.
- Original-source registration check: `outputs/gym-fee-baseline-registration.log`.
