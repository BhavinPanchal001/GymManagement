# Gym Management UI redesign plan

Reviewed 27 October 2026 on the connected Samsung SM-S721B.

## Direction

Adopt My Vhicals' warm cream canvas, forest-green primary color, white bordered cards, restrained icons, and spacious layout. Keep Gym Management's readable text and familiar workflows. This is a design plan; no application code or business records were changed.

## Evidence and limits

- Live reference: My Vhicals home, Fleet list/loading state, and Add an asset form.
- Live Gym Manager: sign-in, Members, Daily Attendance, and Payments collections.
- Earlier workspace screenshots supplement registration, member payment history, pending dues, and printed member reports; these may differ from the installed version.
- Reference fleet has no populated records in the inspected state, so its populated list/detail designs were not verified.
- Screenshots are saved beside this plan. Exact reference font family and source tokens are unknown. Colors and dimensions below are proposed implementation values, not claims about its source code.

## Comparison

| Element | My Vhicals observed | Gym Manager observed | Planned change |
|---|---|---|---|
| Canvas | Warm off-white | Near-black | Warm off-white as the primary visual direction |
| Cards | White, thin pale borders; dark green overview | Multiple dark surface tones, outlined states, occasional gradients | One neutral card treatment and one green summary treatment |
| Accent | Restrained forest green | Neon lime, cyan, orange, green and red | Forest green for actions; semantic colors only for status |
| Type | Strong bold headings, small muted supporting text | Larger text, but some crowded/truncated content | Preserve readable sizing; reflow layouts instead of shrinking text |
| Avatars | Quiet icon treatments | Repeated orange glowing gym icons | Photo or initials on pale sage, without glow |
| Filters | Rounded pills | Large filled rectangular chips | Consistent pills, generous touch area, readable labels |
| Navigation | Icons with selection pill, no visible labels | Icons and clear text labels | Keep text labels; use sage selection pill and green icon |
| Forms | Clear groups, light inputs, persistent bottom actions | Dark nested panels and bright selected states | Light grouped fields, calm selection, clear persistent primary action |

## Proposed design tokens

### Colors

| Role | Value |
|---|---|
| Background | `#F6F5EF` |
| Card/input | `#FFFFFF` |
| Primary green | `#234D3C` |
| Overview background | `#183B2D` |
| Selected/soft surface | `#E8EFE7` |
| Main text | `#18251F` |
| Secondary text | `#59685F` |
| Neutral border | `#DDE4DD` |
| Due/warning | `#8A4B08` on `#FFF0D6` |
| Expired/error | `#B42318` on `#FEECE9` |
| Paid/present | `#236442` on `#E8F3EB` |

Use white text on primary buttons. Check contrast in the implementation, especially disabled controls and metadata. Status must always include a word or icon, not color alone.

### Typography and geometry

- Use one sans-serif family; retain the existing family if it renders well. Consider Inter only after confirming font support and Gujarati/other required script fallbacks.
- Page titles: 28–30 sp, weight 700. Section headings: 20–22 sp, 600–700.
- Member names/card titles: 18–20 sp, 600. Important amounts: 24–28 sp, 700.
- Body, phone numbers, field contents and buttons: 16–18 sp. Labels and supporting metadata: 14–16 sp. No essential information below 14 sp.
- Bottom-navigation labels: 14 sp. Use sentence case for ordinary labels; reserve uppercase for occasional short section markers.
- Body line height approximately 1.4–1.5. Respect system text scaling.
- Page horizontal padding: 20 dp; card padding: 16–20 dp; gaps: 8/12/16/24 dp.
- Card radius: 18–20 dp; hero radius: 24 dp; input/button radius: 12–14 dp; chips fully rounded.
- Neutral card border: 1 dp; avoid glow and decorative gradients. Use shadows sparingly for elevated sheets.
- Inputs/buttons: at least 52–56 dp tall; icon touch targets at least 48 dp. These are minimums, not fixed heights that clip enlarged text.

## Screen-by-screen changes

### Members — first prototype

1. Keep the Members heading and count, using a quiet count label and sage profile avatar.
2. Restyle the existing collapsible Gym Overview in dark green; preserve its collapse behavior. Give summary values more emphasis than their labels.
3. Use a white search field and green selected filter pill. Preserve search, voice entry, and all existing filters.
4. Redesign each member card: name and balance/status first; phone and plan second; attendance and expiry metadata below. Use clear text such as “Expires in 4 days.”
5. Replace glowing orange placeholders with sage initials/photo avatars. Keep phone/receipt/reminder actions accessible, with consistent icon treatment and accessible labels.
6. Move Add Member to a stable header or dedicated action area. If a floating action remains, add enough list padding that it never covers a member or action.

### Attendance

1. Put the date and calendar control in a clean header; use a compact green overview with present/absent/turnout numbers.
2. Keep Mark All clearly labeled and separate from individual row controls; preserve existing confirmation behavior.
3. Use white member cards and soft green/red selected Present/Absent controls. Avoid strongly colored borders around every card.
4. At narrow widths or enlarged text, put attendance controls below the member identity rather than squeezing them beside it.

### Payments and dues

1. Show the full title “Payments”; move the fee and secondary report actions to a second row or action menu so the title never reads “Payments & …”.
2. Retain Collections, Expenses and Balance Sheet, with a subdued segmented selector and readable labels.
3. Present collected, pending and expected totals in one consistent summary card. Stack values when three columns cannot fit.
4. Payment cards: identity and amount first, payment status second, dates/method next, then actions. Keep Record payment as the main action where applicable; render Bill and Edit as quieter actions.
5. For member payment history, align period and amount clearly. Move adjustment details into a readable secondary section so Adjust fee/View adjustment does not dominate every card.
6. Retain financial status distinctions, receipts, date ranges, balances and all current calculations unchanged.

### Registration, details, settings and sign-in

- Registration: retain Plan → Duration → Payment; use sage selected plan cards, clear labels, white inputs and a persistent green Register Member action. Keep the action reachable above the keyboard.
- Member details: compact identity header, clear Payments/Attendance tabs, consistent white history cards.
- Settings: grouped white action rows with outline icons and chevrons, following the reference home action rows.
- Sign-in: cream background, smaller green logo block, white form card, green primary button and consistent secondary links.
- Reports: review screen previews and exported documents separately; preserve print readability instead of mechanically copying screen colors.

## Implementation sequence

1. Locate the actual Gym Manager source checkout and inspect its theme, shared widgets, navigation and text-scale handling. This workspace currently contains supporting files and diary projects, not the complete gym app source.
2. Define semantic colors, text styles, spacing and shared card/button/input/chip/status components in the existing framework.
3. Build Members as the visual prototype, including paid, due, expired, empty and loading states. Review on the Samsung before spreading the pattern.
4. Apply the components to Attendance and Payments, then registration, details, reports, settings and sign-in.
5. Remove remaining hard-coded neon colors and inconsistent styling only after all states map correctly to the shared theme.

## Completion checks

- Inspect at 360, 384 and 412 dp widths, and 100%, 130% and 150% text scaling.
- No clipped titles, names, currency amounts, dates or action labels; long content wraps sensibly.
- No floating button, keyboard or bottom navigation obscures content or form submission.
- Confirm normal-text contrast of at least 4.5:1 and sufficient contrast for controls; verify all statuses without relying on color.
- Check loading, empty, error, paid, partial, due, upcoming, expired, present and absent states.
- Smoke-test registration, search, filtering, attendance, payment collection, adjustment and receipts against the existing behavior. Validate representative UI interactions without altering real member records during design review.
- Compare before/after screenshots on the same device. Acceptance: the calm visual character of My Vhicals, with clearly larger supporting text and no loss of useful gym information.
