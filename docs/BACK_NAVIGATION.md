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

In signed-in mode, AuthGate also needs to preserve HomeScreen through rebuilds.
Previously, it requested a new Firebase authentication stream inside build.
Replacing that stream moves StreamBuilder through its loading state, removes
HomeScreen, and then recreates it with Members selected. AuthGate now obtains
one stream in initState and reuses it for both its account listener and UI.
Real sign-out events still replace HomeScreen with the sign-in screen.

## Automated checks

`test/back_navigation_test.dart` exercises the system back callback and checks
that SystemNavigator.pop is not called while there is history to revisit.
It covers every pair of main tabs, repeated selections, navigation after back,
retained tab state, Payments sections, nested reports/member cards/PDF previews,
profile editing, the review tour, registration/editing/payment/renewal/balance/
expense/attendance dialogs, bill history, receipts, expiry lists, WhatsApp
previews, report export, and the forgot-password sheet. PDF navigation uses a
mocked unavailable native rasterizer; it does not test PDF rasterization.

The 45 navigation checks pass, including four signed-in regressions in
`test/authenticated_back_navigation_test.dart`. These exercise parent rebuilds,
returning from the pending report, same-user authentication events, and sign-out.
The first three reproduced a reset to Members before the stream correction.
Analysis of the changed authentication screen and regression tests is clean.

On the current main branch, the full suite has 167 passing tests and five
existing failures in pending_report_test.dart and phone_layout_test.dart. Those
same five failures were reproduced in a separate checkout of unmodified main.
Global analysis also reports two existing deprecation notices and one unused
import in the pending report test. Checks use Flutter 3.47.2 and Dart 3.13.2.

Run:

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

## Physical-device check

On an Android phone with the older installed build, Payments → Pending Dues
Report → system back reproduced the reported jump to Members. Back at the
Attendance root also left the app. The installed build's embedded source did
not contain the tab-history correction.

On a phone running a build containing both fixes, verify the back button and
edge gesture with this sequence: Members → Attendance →
Payments → Expenses → Balance Sheet → Settings. Each back should revisit the
previous view. Open a member card or receipt PDF and verify back closes one
screen at a time. With a keyboard open, the first back should dismiss the
keyboard; subsequent backs should navigate. Leaving the app should be possible
after all prior views have been revisited.

When validating an installed build, ensure its source includes these fixes.
Merging the pull request does not update an APK already installed on a phone.
An update must use the original app's signing key to preserve that installation.
