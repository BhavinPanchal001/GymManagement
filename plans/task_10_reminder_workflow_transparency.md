# TASK-10: Transparent Reminder Delivery and Actionable Queues

## Priority: Medium
## Category: Communication & Expectation Alignment

---

## 1. Problem Statement
The app currently creates a misleading expectation regarding fee reminders:
- In Settings and Notification services, wording implies that the app provides unattended automated fee follow-up.
- In reality:
  - Background execution without an active server is constrained by mobile OS battery optimizations.
  - The WhatsApp integration uses `url_launcher` with `whatsapp://send?text=...`, which opens the external WhatsApp application with a pre-filled draft message. The gym owner must manually review and tap the "Send" button in WhatsApp for each message.
  - If the owner believes the app is silently collecting fees and messaging members in the background, overdue debts will go uncollected.
- Furthermore, the notification service looks only at a 3-month window for dues, causing it to announce "0 dues" when older debts exist.

---

## 2. Goals & Objectives
1. **Accurate & Transparent UI Copy**:
   - Clearly communicate how reminders work:
     - Change *"Automatic Daily Reminders"* to *"Daily Due Alerts for Owner"*.
     - Subtitle: *"Alerts you on this device when memberships expire so you can dispatch WhatsApp reminders with one tap."*
2. **Dedicated One-Tap Follow-up Queue**:
   - Provide an actionable reminder queue in the Billing / Pending Dues tab:
     - Lists all members with overdue balances.
     - Single-tap button: *"Dispatch WhatsApp Draft"*.
     - Shows when a reminder was last dispatched to prevent accidental duplicate messaging on the same day.
3. **Harmonize Due Calculations**:
   - Ensure the notification alert counts all overdue members matching the pending payment report, rather than truncating older balances.

---

## 3. Impacted Files
- [lib/services/notification_service.dart — `checkAndNotifyPendingPayments()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/notification_service.dart#L235-L260)
- [lib/screens/settings/settings_tab.dart — notification toggle](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L490-L540) *(note: the plan previously cited L300-L340, which is the user profile section, not the notification toggle)*
- [lib/screens/billing/billing_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/billing/billing_tab.dart#L70-L100)
- [lib/screens/reports/pending_payments_report_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/reports/pending_payments_report_screen.dart#L100-L150)
- [lib/models/customer.dart — field declarations](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/models/customer.dart#L39-L56) *(note: the plan previously cited L60-L75, which is inside `copyWith()`, not where new fields should be declared)*

---

## 4. Detailed Implementation Steps

### Step 1: Update UI Terminology in Settings
- In `SettingsTab`:
  - Update toggle title: **"Payment Due Alerts (For Gym Owner)"**.
  - Update description: *"Shows notification alerts on this phone when members have pending dues or expiring plans. WhatsApp messages are prepared for your review and one-tap dispatch."*

### Step 2: Track "Last Reminded" Timestamp
- Add `DateTime? lastReminderSentAt` field to the `Customer` model:
  - Add to the field declarations (around line 43-56).
  - Add to the constructor with default `null`.
  - Add to `copyWith()` (around line 79-114).
  - Add to `toMap()`: `'lastReminderSentAt': lastReminderSentAt?.toIso8601String(),`
  - Add to `fromMap()`: `lastReminderSentAt: map['lastReminderSentAt'] != null ? DateTime.tryParse(map['lastReminderSentAt'] as String) : null,`
  - **Migration safety**: `fromMap()` must default to `null` for existing records that don't have this field.
  - **Persistence choice**: Stored in the Customer model and synced to Firestore (so reminder timestamps are consistent if the owner checks from another device).
- When tapping the WhatsApp reminder button for a member:
  - Launch WhatsApp with the pre-filled polite reminder.
  - Update `lastReminderSentAt = DateTime.now()` via `GymService().updateCustomer(customer.copyWith(lastReminderSentAt: DateTime.now()))`.
  - Display subtle badge in list: *"Reminded today"* or *"Reminded 3 days ago"*.

### Step 3: Align Due Calculation in Notification Service
- Update `NotificationService.checkAndNotifyPendingPayments()` (line 235):
  - Currently queries `getPendingDuesByMember()` (line 245-248) with a 3-month window: `DateTime(now.year, now.month - 2, 1)` to `now`.
  - Change to query all pending balances from `GymService().getPendingDuesByMember(DateTime(2020, 1, 1), now)` instead of restricting to 90 days.
  - *(Note: The method is `getPendingDuesByMember(DateTime start, DateTime end)` at [gym_service.dart#L1824](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L1824), NOT `getPendingDues()` which does not exist.)*
  - Ensure notification count accurately mirrors the Pending Payments report count.

---

## 5. Edge Cases & Considerations
- **Member Has No Phone Number / Invalid Format**: Disable the WhatsApp reminder button or show a warning prompting the owner to update the member's phone number first.
- **WhatsApp Not Installed**: Handle `canLaunchUrl` failure gracefully with a message: *"WhatsApp is not installed on this device."*

---

## 6. Validation & Testing Checklist
- [ ] Review Settings tab: verify reminder toggle and descriptions are clear, honest, and unambiguous.
- [ ] Send a reminder to a member: verify WhatsApp opens with the pre-filled polite payment reminder.
- [ ] Return to app: verify the member's card indicates that a reminder was sent today.
- [ ] Verify that notification summary count matches the total count in the Pending Payments report.
