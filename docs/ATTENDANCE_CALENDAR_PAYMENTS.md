# Payment details on the attendance calendar

Location: Members → select a member → Attendance → calendar → Show payment details.

The switch starts off. Turning it on makes each date box taller and wider (with smaller gaps and side padding, keeping all seven columns visible) and adds a payment icon below the attendance mark. The legend above the weekday names explains all four icons:

- Paid: the fee for the period covering this date is fully settled, including credit or a fee waiver.
- Part paid: some cash or credit was applied, but the period still has a balance.
- Due: the date belongs to an unpaid membership period.
- No payment period: no recorded payment or due period covers the date, or the date is before joining. This does not create a new debt.

The display uses the same payment history as the member’s Payments tab, including attendance-derived dues. Both the start and end dates are included. An absent or rest day can still belong to a paid membership period. A partial payment applies to the whole period; the display does not invent a set of fully paid days from the amount collected. Future paid periods remain visible, while future attendance remains disabled.

Changing the display does not save payments or change attendance. Payment changes refresh the visible calendar automatically. The display choice lasts while the member details page stays open.

## Manual checks

1. Open the location above. With the switch off, verify the compact attendance calendar. Turn it on: boxes become taller and the payment legend appears. Turn it off: the compact view returns.
2. For a fully paid period such as 10 September–9 October, inspect October: 1–9 show Paid. Later dates show their own period status, rather than copying the paid status of the earlier period.
3. For an unpaid period, inspect any date inside it: Due appears even if attendance is absent, rest, or unmarked.
4. Record only part of the period fee in Payments. Return to Attendance: the period shows Part paid. Collect the remaining balance: it shows Paid.
5. Inspect a gap with no payment or due period: No payment period appears. Toggling the switch must not add any dues or receipts.
6. With the switch on, mark attendance on an eligible past day. Attendance changes as before and the payment icon remains based on payment records.
7. Inspect dates before joining and after today: attendance remains disabled. Future dates can show an existing advance payment.
8. Try a narrow phone: the legend wraps, dates remain in seven columns, and payment icons remain separate from attendance marks. Hold an icon to read its date and meaning.

## Validation

All 22 calendar-specific tests pass. The full app run has 380 passing tests and the same 49 existing failures as the previous audit, with no newly failing tests. See ATTENDANCE_CALENDAR_PAYMENT_TEST_REPORT.md for the three-month simulator results and detailed coverage.
