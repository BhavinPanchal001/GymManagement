# Attendance calendar payment display — test report

Tested on 26 October 2026.

## Three-month member created in the simulator

Location: Members → QA Calendar 3 Months → Attendance → Show payment details.

- Test member: QA Calendar 3 Months, card 104, test phone 2025550198.
- Normal plan, three months, ₹1,500 recorded paid in full.
- Joining and membership start: 1 October 2026.
- Membership expiry: 31 December 2026.
- October: all 31 dates show Paid.
- November: all 30 dates show Paid.
- December: all 31 dates show Paid.
- January 2027: all 31 dates show No payment period; none show Paid.
- Future paid dates are visible while future attendance remains disabled.
- The QA member is left in the simulator for review. Existing members were not edited during this test.

## Automated calendar checks

All 22 calendar-specific tests passed. They cover:

- Paid, unpaid, partially paid, and missing periods.
- Inclusive start/end boundaries, ignoring clock times.
- No payment status before joining.
- Full and partial credit, and waived fees.
- Existing overlapping records: settled coverage takes precedence.
- Three-month coverage for every date in October–December.
- Mid-month three-month periods crossing New Year.
- A three-month period including 29 February in a leap year.
- Dates just before the start and just after expiry.
- Three-month unpaid and partially paid plans across each month.
- Coverage preserved after loading saved owner data again (local storage).
- Cancelled payment returning an agreement to Due.
- An uncovered visit creating a due period, while earlier paid dates stay Paid.
- Paid status independent of present, absent, rest, and unmarked attendance.
- Actual calendar navigation through three paid months and the following month.
- Future attendance buttons remain disabled.
- Switch off/on/off, legend, increased height and width, 320- and 390-point phone layouts.
- Live Due → Part paid → Paid updates when money is recorded.
- Attendance marking still works; toggling the display creates no financial records.

## Wider checks

The complete app test run passed 380 tests and failed 49. The failure names exactly match the previous audit: no newly failing tests and no previously failing tests changed result. This run included the first 19 calendar tests; the final three additional cases were then included in the separate successful 22-test calendar run.

Code analysis of the changed feature files passed. The current app build had already passed and was installed in the iPhone 17 simulator. This testing turn added tests and documentation only.

Evidence:

- outputs/calendar-payment-feature-tests.log
- outputs/calendar-payment-full-suite.jsonl
- outputs/calendar-payment-suite-comparison.json
- outputs/calendar-payment-analysis.log

## Limits and existing behaviour

This verifies local storage, automated widgets, and the offline iPhone simulator. Live Firebase sync and physical-device testing were not performed.

The older summary card above the calendar still says “UNPAID • 0 DAYS ATTENDED” in a future month with no recorded membership period. The new day icons correctly show “No payment period” in that case. That summary-card wording is existing behaviour and was not changed as part of this display feature. The calendar itself does not create a debt for those dates.
