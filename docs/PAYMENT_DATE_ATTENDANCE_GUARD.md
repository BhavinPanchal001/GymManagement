# Preventing an accidental second monthly fee

When a member has a 1–31 October membership and has already attended on
1–26 October, saving payment coverage as 15 October–14 November leaves the
first 14 visits uncovered. The app could then derive another unpaid cycle from
those visits, making one month look like two fees.

Payment entry and correction now reject a date change that would leave recorded
visits from the selected membership outside its dates, unless another paid
period already covers those visits. A separate payment overlapping an explicitly
agreed unpaid membership cannot bypass this check. Separate historical cycles
may still retain other attendance-created debts without editing those cycles.
No payment or receipt is saved on rejection.

The payment form explains that someone who pays late should keep their
membership dates and change **Payment received date**. Errors are shown in a
visible dialog rather than a message that can be hidden under the form.

The check does not block:

- Recording a late receipt against the original membership period.
- A genuine separate renewal after the old period ends.
- A date correction that includes every recorded visit.
- Earlier absent or rest days.
- Correcting an older mistaken paid period to cover the original month, when
  that correction does not leave other visits uncovered. The existing receipt
  number and collected amount are kept; the artificial unpaid cycle disappears.

Expanded verification: **28 date-guard tests passed**. A full before/after audit
found 333 passing tests and 49 failures before the fix, and 361 passing tests
with the exact same 49 failures afterward. No new regression failures remain.
Static analysis and the simulator build passed. See
[the regression audit](PAYMENT_DATE_GUARD_AUDIT.md) for findings and limitations.
