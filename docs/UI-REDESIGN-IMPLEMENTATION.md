# Reference-scale cream and green UI implementation

Branch: `codex/cream-green-ui`
Base: `4e946b5`
Initial implementation: 28 October 2026.
Reference-scale revision following phone review: 30 October 2026.

## Implemented

- Warm cream background, white neutral cards, forest-green actions, muted status colors and sage accents in dark mode.
- Compact shared typography: 13 sp body text, 11–12 sp secondary text, 13–14 sp list names, 18 sp app titles and 11 sp navigation labels. Larger system text remains supported; text scaling is not capped. Existing PDF-generation services retain their print typography.
- Members: a single compact row with name/phone/metadata beside a narrow payment/action column, 28 dp avatars, 8 dp card insets and 6 dp gaps. Normal fixture cards must measure no more than 84 dp high. Add Member is a labelled toolbar icon; the full-width bottom action area is removed. Partial balances retain their collection action below the card summary.
- Attendance: single-row member identity with compact check/cross actions, accessible Present/Absent semantics and tooltips, smaller summary padding and neutral cards. Status actions are verified to save the selected attendance state.
- Payments: monthly fee beside the month heading, single-line section tabs that scroll at enlarged text sizes, tighter summary/tracker cards and a scrollable viewport for short screens with the keyboard open.
- Member details/calendar: wrapping metadata, separate month navigation, responsive payment status and reminder rows.
- Registration: readable form labels, wrapping plan/date headings, existing multi-step and payment workflows retained.
- Settings: 8 dp card insets, smaller headings/account avatar, horizontal icon-and-label appearance choices and shorter section gaps. Authentication retains wrapping sign-in options. Shared navigation is 56 dp, app bars are 48 dp and primary controls have a 36 dp minimum. Inline actions use compact visual bounds, and redundant Material tap padding is removed from those controls. Search fields use 36 dp icon constraints.
- Light mode is the default only when no appearance preference is stored. Existing dark/system preferences remain respected.

## Validation

- `flutter analyze --no-pub`: no issues.
- Reference-scale revision focused suite: 117 tests passed across phone layout, theme, registration, workflow compatibility, calendar payment details, critical workflows, Members scaling and rendered screen checks. Members coverage includes unpaid, fully paid and partially paid records at three widths and three text scales. Three navigation/removal smoke checks also passed, bringing the focused total to 120. The 21 rendered-preview/attendance-control checks passed with system-bar insets.
- Sizes checked include 320 x 568 with keyboard and 130% text, 360/384/412 dp Members layouts at 100/130/150%, and five screens at 384 x 832 dp with 100% and 150% text in both light and dark themes. Preview captures include navigation and system-bar insets. Normal-size Members and Attendance tests verify at least six visible member identities. The Members test also measures the card height, and toolbar tests verify the Add Member action remains accessible above the list.
- Rendered previews are in `build/ui-review/dense-<screen>-<light|dark>-<100|150>.png` (Members, Attendance, Payments, Settings, Sign-in). The preview fixtures contain synthetic records; they do not modify phone records.
- Full-suite baseline comparison: original main produced 407 passing / 51 failing tests in this environment. These include navigation timeouts, stale form finders, and existing business-logic assertions. The earlier redesign full run was 413 passing / 54 failing; redesign-specific layout regressions identified there were corrected and the focused suite rerun successfully. The full repository suite is not claimed to be green.

## Build and delivery

- Android version: `1.0.0+2` (version code 2 distinguishes this build from the earlier APKs).
- Replacement APK: `build/app/outputs/flutter-apk/gym-manager-dense-v2.apk` (also emitted as `app-release.apk`).
- The local Flutter SDK migrates Android minSdk to its supported default (24 / Android 7). NDK is aligned to installed 28.2.13676358 required by speech_to_text.
- Existing release signing configuration uses the debug signing key; production signing was not changed.
- No cloud deployment, merge or push is performed by this change. No real member/payment/attendance records were edited.
- No Android device was connected during the reference-scale revision, so the replacement APK is supplied for installation. Both saved dark and light preferences remain supported.
