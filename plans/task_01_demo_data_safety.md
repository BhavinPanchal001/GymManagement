# TASK-01: Guard Live Account Against Demo Data Overwrite

## Priority: Critical
## Category: Data Safety & Prevention of Accidental Loss

---

## 1. Problem Statement
In the Settings screen, there is a prominent option labeled **"Reload Sample / Demo Data"**.
Currently, when tapped:
- It shows a mild dialog stating: *"This will restore default demo members, attendance history, and monthly payments."*
- When confirmed, it immediately calls [GymService.resetToDemoData()](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L2429), which executes:
  - `_customers.clear()`
  - `_expenses.clear()`
  - `_attendanceMap.clear()`
  - `_paymentMap.clear()`
  - `_billsMap.clear()`
  - And if Firestore is connected, calls `FirestoreService().clearAllData()`!
- **Consequence**: An owner exploring the settings tab can tap this button by mistake and wipe out their entire real gym database and cloud backup in seconds with no way to recover.

---

## 2. Goals & Objectives
1. **Prevent Accidental Data Erasure**: Ensure a live gym owner with real members cannot accidentally trigger demo data seeding.
2. **Strict Protection when Real Members Exist**:
   - If `GymService.customers.isNotEmpty`, the demo data option should either be hidden or strictly locked behind a multi-step safeguard.
   - Require typing an explicit confirmation phrase (e.g., typing `"RESET"` or the gym's name) before the button activates.
   - Display a loud, unmistakable warning: *"⚠️ DANGER: You have X members and Y payment records. Continuing will permanently erase all real gym records locally and from the cloud."*
3. **Dedicated Demo Mode Separation**:
   - Provide an optional sandbox/demo toggle rather than destructive in-place replacement of live data.

---

## 3. Impacted Files
- [lib/screens/settings/settings_tab.dart — `_confirmResetData()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L101-L137)
- [lib/screens/settings/settings_tab.dart — `_confirmClearAllData()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L139-L176)
- [lib/services/gym_service.dart — `resetToDemoData()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L2429-L2454)
- [lib/services/gym_service.dart — `clearAllGymData()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L2341-L2362)

---

## 4. Detailed Implementation Steps

### Step 1: Update Both Confirmation Dialogs in `settings_tab.dart`
There are **two** destructive dialogs that both need the same safeguards:
- `_confirmResetData()` at line 101 — "Reload Sample / Demo Data"
- `_confirmClearAllData()` at line 139 — "Clear All Gym Data"

For **both** dialogs, when `gym.customers.isNotEmpty`:
  - Present a `DangerConfirmationDialog`:
    - Display current count of affected records: `members`, `payments`, `bills`, `expenses`.
    - Present a text input field requiring the user to type `"DELETE ALL DATA"`.
    - Keep the "Proceed" button disabled until the exact confirmation string is entered.
    - Provide a secondary "Create Backup First" button to prompt an immediate backup before any wipe.
  - If the database is already empty (`customers.isEmpty`), allow the action with a standard informative confirmation.

### Step 2: Add Safety Checks in `GymService`
- In `resetToDemoData()` (line 2429):
  - Add an explicit parameter: `Future<bool> resetToDemoData({bool force = false})`.
  - If `customers.isNotEmpty` and `force == false`, reject the call and log an error or return `false`.
- In `clearAllGymData()` (line 2341):
  - Add the same guard: `Future<bool> clearAllGymData({bool force = false})`.
  - If `customers.isNotEmpty` and `force == false`, reject the call.
- Ensure that automatic background sync does not delete cloud collections unless explicitly confirmed.

### Step 3: UI Placement and Styling
- Move "Reload Sample / Demo Data" to an advanced "Developer / Sandbox Tools" section at the very bottom of the Settings tab.
- Color code the button with warning/caution tones to clearly indicate destructive capability.

---

## 5. Edge Cases & Considerations
- **Offline Mode**: If the user resets while offline and then reconnects to Firestore, ensure inconsistent partial wipes do not leave orphaned cloud records.
- **Initial Setup**: First-time users who have just installed the app and have 0 members can safely load demo data to explore the features.

---

## 6. Validation & Testing Checklist
- [x] Tap "Reload Sample / Demo Data" when 1+ members exist: verify the strict confirmation modal appears.
- [x] Tap "Clear All Gym Data" when 1+ members exist: verify the strict confirmation modal appears.
- [x] Confirm both reset/clear buttons are disabled until the exact phrase is typed.
- [x] Verify cancellation of either dialog leaves all local and cloud records intact.
- [x] Confirm resetting on a completely clean/empty app works smoothly without requiring the complex phrase.
- [x] Confirm clearing on a completely clean/empty app works smoothly without requiring the complex phrase.

**Status: ✅ Implemented & Tested**
