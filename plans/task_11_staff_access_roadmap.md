# TASK-11: Staff & Receptionist Access Architecture (Phase 2 Roadmap)

## Priority: Medium / Phase 2 Roadmap
## Category: Security, Multi-User Roles & Permissions

---

## 1. Problem Statement & Scope Analysis
In many gyms, the front desk receptionist or floor trainer interacts with the app during the day to check members in and collect payments.
Currently:
- The app operates under a single owner login.
- There is no role-based permission system.
- Anyone holding the phone can access all financial profit summaries, delete members, modify package pricing, or reset data.
- **Why Phase 2 for Full Cloud RBAC?**: A full multi-user cloud system requires email invitations, Firebase Auth custom claims, and comprehensive Firestore security rules. For immediate handover, we recommend a **Phase 1 Lightweight Front Desk PIN Mode**, followed by the **Phase 2 Cloud RBAC System**.

---

## 2. Proposed Two-Tier Architecture

### Tier 1: Immediate Handover Solution — "Front Desk / Receptionist PIN Mode"
A lightweight, device-level role lock that provides instant front-desk safety without requiring separate Firebase accounts:
1. **Owner 4-Digit Security PIN**:
   - The owner sets a 4-digit master PIN in Settings (e.g. `1234`).
2. **One-Tap Mode Switch**:
   - Owner taps *"Switch to Front Desk Mode"* before leaving the phone/tablet with the receptionist.
3. **Permissions in Front Desk Mode**:
   - ✅ **Permitted**:
     - Daily Attendance check-in & search.
     - Taking payments and issuing digital receipts.
     - Member search and viewing contact cards.
   - 🔒 **Locked / Hidden (Requires PIN to Access)**:
     - Gym Settings, Plan Pricing, and Demo Data tools.
     - Financial Analytics, Profit/Loss, and Expense Management.
     - Member Deletion / Archiving.
     - Database Backup & Restore.

### Tier 2: Future Phase 2 Roadmap — "Cloud Multi-User RBAC"
When the owner needs multiple staff members logging in from their own individual phones:
1. **Firebase Authentication Roles**:
   - Roles: `Owner`, `Receptionist`, `Trainer`.
2. **Firestore Security Rules**:
   - Rule restrictions:
     - Only `role == 'owner'` can write to `settings` or `expenses` collections.
     - `role == 'receptionist'` can read/write `attendance` and create `payment` documents, but cannot execute `delete`.
3. **Staff Invitation Flow**:
   - Owner enters staff email -> invitation link sent -> staff creates login linked to the gym's organization ID.

---

## 3. Impacted Files (for Tier 1 Implementation)
- [lib/models/gym_settings.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/models/gym_settings.dart#L10)
- [lib/screens/settings/settings_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L1)
- [lib/screens/home_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/home_screen.dart#L1)
- New Widget: `lib/widgets/pin_lock_dialog.dart`

---

## 4. Implementation Steps for Front Desk PIN Mode
1. **Add PIN Settings**:
   - Store hashed owner PIN in SharedPreferences / GymSettings (`ownerPinHash`, `isReceptionistModeEnabled`).
2. **Build PIN Verification Dialog**:
   - Quick numeric keypad dialog for unlocking owner features.
3. **Enforce Screen Guards**:
   - Wrap Settings Tab, Analytics Tab, and Member Delete action with `requireOwnerPin(context)`.
4. **Persistent Mode Indicator**:
   - When Receptionist Mode is active, show a discrete top banner: *"Front Desk Mode Active • Tap to Unlock Owner View"*.

---

## 5. Validation Checklist
- [ ] Enable Front Desk Mode with PIN `4321`.
- [ ] Verify attendance can be marked and search works normally.
- [ ] Attempt to open Gym Settings or Financial Analytics: verify PIN prompt appears and blocks unauthorized access.
- [ ] Enter correct PIN: verify full owner permissions are immediately restored.
