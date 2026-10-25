# Fee adjustments

Open **Members → select member → Payments → Payment History → Adjust fee**.
The same option is available from a payment form.

Enter the revised fee and a reason, then review and confirm. The screen keeps
the original fee, current fee, money received, amount still owed, and a dated
history showing who approved each change. Attendance never changes the fee
automatically. Membership dates and future package prices are not changed.

Example: last month ₹600 unpaid plus this month ₹600 unpaid gives ₹1,200 due.
Reducing last month's fee to ₹300 leaves ₹900 due. No income or receipt is
created by the reduction.

If ₹400 was received before a fee was reduced to ₹300, the extra ₹100 remains
available as member credit. In Adjust fee, the owner can:

- Leave the credit for later.
- Apply some or all of it to another unpaid period for the same member, or to
  the suggested next membership period. A ₹600 period with ₹100 credit leaves
  ₹500 to collect. Using credit does not create another cash collection.
- Record money already returned to the member, including the payment method
  and reason. This creates a clearly labelled negative refund record and
  reduces net collections on the return date. It does not transfer money.

The existing receipts are retained. Fee adjustments, credit transfers, and
returns are saved with the payment data and use the existing cloud upload queue.
Repeated saves cannot reuse the same credit. A stale form asks the owner to
reopen the period. Changes that would undo spent or returned credit are blocked.
Generic payment correction/cancellation is blocked for periods with adjustment
history so that it cannot erase the history or disconnect a credit transfer.

Expanded verification on 25 October 2026: 69 fee-adjustment checks passed. The
full app run had 333 passing tests and 49 pre-existing failures. Static analysis
passed. A local sample member was adjusted from ₹600 to ₹300 in the simulator
and its history persisted after reopening. Real cloud delivery and conflicts
between two real devices remain unverified. See
[the test report](fee-adjustment-test-report-2026-10-25.md) for coverage and limits.
