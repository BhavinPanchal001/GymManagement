# Member workflow fixes

Razorpay is excluded at the owner's request. The other eleven requested items are implemented.

| Request | Result |
| --- | --- |
| 1. Forgot password | Resend uses the address from the successful request without accessing a removed form. Failed resends show an error and allow retry. Duplicate requests are blocked. |
| 2. Razorpay merge | Skipped at the owner's request. |
| 3. Signup names | Owner and gym names capitalize word initials, including pasted text, while preserving the remaining spelling. |
| 4. Gym overview | Starts collapsed and collapses again when leaving the Members tab. |
| 5. Add-member form | Plan, Duration and Payment have horizontal step navigation. The existing selections and payment modes are retained. |
| 6. Date picker focus | Date and date-range pickers dismiss the active text field. Closing a picker also leaves text fields unfocused. |
| 7. Register button | The register/save button remains at the bottom while the form scrolls. |
| 8. Attendance profile | Removed the duplicate profile card from the attendance tab. |
| 9. Future payments | An unpaid future month's payment card says Upcoming instead of Due. |
| 10. Attendance before joining | Individual and bulk marking reject dates before joining. Calendar cells before joining are disabled. |
| 11. Paid attendance | Attendance already covered by an earlier paid cycle does not show a settlement button. Settlement forms retain the recorded cycle dates rather than replacing them with calendar-month boundaries. |
| 12. Breaks between cycles | New attendance-based cycles start on the first unpaid day the member returns. Payment history shows the dates and length of gaps between paid cycles. |

For the confirmed example, the first payment covers 5 August–4 September. Attendance on 1–2 September is already paid. Returning on 20 September starts a new monthly period of 20 September–19 October. After that period is paid, payment history shows a 15-day gap from 5–19 September.

Gap cards distinguish days with no recorded attendance from days attended without paid coverage. They do not silently forgive attendance-based dues. Existing recorded payment periods and explicit membership agreements retain their saved dates; no stored-data migration is introduced.

The automated checks include password-reset success, resend and retry using simulated Firebase responses; attendance boundaries; paid attendance across months; return-date billing; gap dates; future-month labels; overview collapse; fixed footer placement; and keyboard focus after closing a date picker. Actual reset-email delivery still needs a check with the configured Firebase account and a real inbox.

## Verification results

- Code analysis: no issues found.
- Web build: passed (`flutter build web --no-pub --no-wasm-dry-run`).
- Focused workflow checks: 51 passed, including 12 new checks and existing registration, payment migration, month selection and critical workflow checks.
- Full suite: 238 passed and 55 failed. An unchanged checkout of main had 226 passed and 55 failed. Comparing failures showed 54 shared failures, one previously failing check now passing, and one timing threshold failure during the parallel web build. The timing check passed when rerun independently (437 ms against a 1000 ms limit).

The remaining shared failures include older form expectations, member-card dues expectations, navigation assertions and existing phone layout overflows. They are recorded here so the full suite is not presented as passing.
