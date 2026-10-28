# Cream and green UI implementation

Branch: `codex/cream-green-ui`
Base: `4e946b5`
Completed UI implementation: 28 October 2026.

## Implemented

- Warm cream background, white neutral cards, forest-green actions, muted status colors and sage accents in dark mode.
- Shared readable typography and minimum 14 sp explicit UI labels across screens, dialogs and charts. Existing PDF-generation services retain their print typography.
- Members: readable identity section, wrapping actions, neutral avatars, green overview, count badge, dedicated Add Member area clear of list content.
- Attendance: identity above status actions; neutral cards and explicit present/absent labels.
- Payments: full title and separate fee row, scrollable section tabs at enlarged text sizes, wrapping summary labels, consistent neutral cards, and a scrollable viewport for small screens with the keyboard open.
- Member details/calendar: wrapping metadata, separate month navigation, responsive payment status and reminder rows.
- Registration: readable form labels, wrapping plan/date headings, existing multi-step and payment workflows retained.
- Settings and authentication: consistent card treatments, wrapping section headings/status labels, readable sign-in options and no decorative logo glow.
- Light mode is the default only when no appearance preference is stored. Existing dark/system preferences remain respected.

## Validation

- `flutter analyze --no-pub`: no issues.
- Final focused suites: 86 tests passed (83 UI/workflow tests plus 3 navigation/removal smoke tests) across phone layout, theme, registration, workflow compatibility, calendar payment details, critical workflows, Members scaling, rendered screen checks, profile back navigation, and removal confirmation.
- Sizes checked include 320 x 568 with keyboard and 130% text, 360/384/412 dp Members layouts at 100/130/150%, and five main screens at 384 dp with 150% text.
- Rendered previews are in `build/ui-review/` (Members, Attendance, Payments, Settings, Sign-in). The preview fixtures contain synthetic records; they do not modify phone records.
- Full-suite baseline comparison: original main produced 407 passing / 51 failing tests in this environment. These include navigation timeouts, stale form finders, and existing business-logic assertions. The earlier redesign full run was 413 passing / 54 failing; redesign-specific layout regressions identified there were corrected and the focused suite rerun successfully. The full repository suite is not claimed to be green.

## Build and delivery

- APK output: `build/app/outputs/flutter-apk/app-release.apk`.
- The local Flutter SDK migrates Android minSdk to its supported default (24 / Android 7). NDK is aligned to installed 28.2.13676358 required by speech_to_text.
- Existing release signing configuration uses the debug signing key; production signing was not changed.
- No cloud deployment, merge or push is performed by this change. No real member/payment/attendance records were edited.
- The phone disconnected before final installation. Existing users can choose Settings → Appearance & Theme → Light Mode to see the cream theme.
