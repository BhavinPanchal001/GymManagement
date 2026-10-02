# Phone back navigation

The main tabs and Payments sections share a single Navigator route. Previously,
changing these views only updated an index, so pressing the phone's back button
could leave the app instead of returning to the previous view.

HomeScreen now records each change of tab or Payments section and handles back
with PopScope. Back retraces the actual visit order, including Collections,
Expenses, Balance Sheet, and the Manage Expenses shortcut. Selecting the current
tab or section does not add a history entry. Existing tab state, such as member
search, is retained. Once this history is exhausted, normal platform exit
behavior applies.

Detail pages, reports, profile editing, the review tour, dialogs, and bottom
sheets retain their Navigator routes. Back dismisses the top route first and
leaves the tab history intact. In particular, a PDF preview returns to its
receipt, and a member card returns to its member profile.

## Automated checks

`test/back_navigation_test.dart` exercises the system back callback and checks
that SystemNavigator.pop is not called while there is history to revisit.
It covers every pair of main tabs, repeated selections, navigation after back,
retained tab state, Payments sections, nested reports/member cards/PDF previews,
profile editing, the review tour, registration/editing/payment/renewal/balance/
expense/attendance dialogs, bill history, receipts, expiry lists, WhatsApp
previews, report export, and the forgot-password sheet. PDF navigation uses a
mocked unavailable native rasterizer; it does not test PDF rasterization.

The full suite passes 158 tests, including 41 back-navigation checks. Static
analysis reports no issues with Flutter 3.47.2 and Dart 3.13.2.

Run:

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

## Physical-device check

No Android device was connected during development. On a phone, verify both
the back button and edge gesture with this sequence: Members → Attendance →
Payments → Expenses → Balance Sheet → Settings. Each back should revisit the
previous view. Open a member card or receipt PDF and verify back closes one
screen at a time. With a keyboard open, the first back should dismiss the
keyboard; subsequent backs should navigate. Leaving the app should be possible
after all prior views have been revisited.
