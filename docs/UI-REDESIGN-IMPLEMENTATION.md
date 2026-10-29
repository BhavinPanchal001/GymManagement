# Cream and green UI implementation

Branch: `codex/cream-green-ui`
Base: `4e946b5`
Initial implementation: 28 October 2026.
Compact layout correction following phone review: 29 October 2026.

## Implemented

- Warm cream background, white neutral cards, forest-green actions, muted status colors and sage accents in dark mode.
- Compact shared typography: 14 sp body text, 13 sp secondary text, 15–16 sp list names/headings, 20 sp app titles and 12 sp navigation labels. Larger system text remains supported; text scaling is not capped. Existing PDF-generation services retain their print typography.
- Members: payment status beside the name/phone, metadata and quick actions sharing a compact footer, smaller avatars and card padding, a single-row overview header and a 44 dp Add Member button clear of list content. Partial balances retain their collection action below the card summary.
- Attendance: single-row member identity with compact check/cross actions, accessible Present/Absent semantics and tooltips, smaller summary padding and neutral cards. Status actions are verified to save the selected attendance state.
- Payments: monthly fee beside the month heading, single-line section tabs that scroll at enlarged text sizes, tighter summary/tracker cards and a scrollable viewport for short screens with the keyboard open.
- Member details/calendar: wrapping metadata, separate month navigation, responsive payment status and reminder rows.
- Registration: readable form labels, wrapping plan/date headings, existing multi-step and payment workflows retained.
- Settings: smaller card insets, headings, account avatar, appearance options and section gaps. Authentication retains wrapping sign-in options and no decorative logo glow. Shared navigation is 64 dp rather than 72 dp; shared primary buttons use a 44 dp minimum rather than 52 dp.
- Light mode is the default only when no appearance preference is stored. Existing dark/system preferences remain respected.

## Validation

- `flutter analyze --no-pub`: no issues.
- Compact revision focused suite: 117 tests passed across phone layout, theme, registration, workflow compatibility, calendar payment details, critical workflows, Members scaling and rendered screen checks. Members coverage includes unpaid, fully paid and partially paid records at three widths and three text scales. Three navigation/removal smoke checks also passed, bringing the focused total to 120. The 21 rendered-preview/attendance-control checks were rerun successfully with system-bar insets.
- Sizes checked include 320 x 568 with keyboard and 130% text, 360/384/412 dp Members layouts at 100/130/150%, and five screens at 384 x 832 dp with 100% and 150% text in both light and dark themes. Preview captures include navigation and system-bar insets. Normal-size Members and Attendance tests verify at least four visible member identities.
- Rendered previews are in `build/ui-review/compact-<screen>-<light|dark>-<100|150>.png` (Members, Attendance, Payments, Settings, Sign-in). The preview fixtures contain synthetic records; they do not modify phone records.
- Full-suite baseline comparison: original main produced 407 passing / 51 failing tests in this environment. These include navigation timeouts, stale form finders, and existing business-logic assertions. The earlier redesign full run was 413 passing / 54 failing; redesign-specific layout regressions identified there were corrected and the focused suite rerun successfully. The full repository suite is not claimed to be green.

## Build and delivery

- Replacement APK: `build/app/outputs/flutter-apk/gym-manager-compact-ui.apk` (also emitted as `app-release.apk`).
- The local Flutter SDK migrates Android minSdk to its supported default (24 / Android 7). NDK is aligned to installed 28.2.13676358 required by speech_to_text.
- Existing release signing configuration uses the debug signing key; production signing was not changed.
- No cloud deployment, merge or push is performed by this change. No real member/payment/attendance records were edited.
- No Android device was connected during the compact revision, so the replacement APK is supplied for installation. Both saved dark and light preferences remain supported.
