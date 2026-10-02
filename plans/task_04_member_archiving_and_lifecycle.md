# TASK-04: Member Archiving & Status Lifecycle

## Priority: High
## Category: Accounting Integrity & Member Lifecycle Management

---

## 1. Problem Statement
When a member stops coming or finishes their membership, gym owners currently only have a single action: **"Delete Member"**.
This creates severe accounting and operational problems:
- In [gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L766), `deleteCustomer()` removes the member and their payment records from the local state, but leaves bills behind.
- In [firestore_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/firestore_service.dart#L247), deleting a customer permanently deletes their bills and receipts from the cloud database as well.
- **Financial Audit Trail Destroyed**: If a member paid ₹15,000 over the past year and then left the gym, deleting them erases ₹15,000 from past financial records, throwing off yearly income reports, balance sheets, and tax totals.
- Although `Customer` has an `isActive` boolean field, there is currently no user-facing **"Archive Member"** or **"Deactivate Member"** workflow.

---

## 2. Goals & Objectives
1. **Dedicated "Archive / Deactivate" Flow**:
   - Provide an "Archive Member" action on the member details screen.
   - Sets `customer.isActive = false`.
   - Archived members are removed from Daily Attendance check-ins and active counts, but remain safely stored.
2. **Preserve Complete Historical Integrity**:
   - Archiving preserves 100% of historical payments, receipts, bills, and attendance records.
   - Financial reports for past months remain completely unchanged and accurate.
3. **Reactivation Workflow**:
   - Owners can view archived members via an "Archived" filter chip in the Members tab.
   - A single tap on "Reactivate Member" sets `isActive = true`, seamlessly welcoming returning members back without re-typing their profile.
4. **Safeguarded Permanent Deletion**:
   - Prevent accidental permanent deletion of members with financial records.
   - If a member has recorded payments or receipts, guide the owner: *"This member has payment history. Please Archive them instead to preserve financial records."* Permanent deletion is reserved for mistaken registrations with zero transactions.

---

## 3. Impacted Files
- [lib/services/gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L740-L775)
- [lib/services/firestore_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/firestore_service.dart#L247-L280)
- [lib/screens/customers/customer_detail_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/customer_detail_screen.dart#L130-L165)
- [lib/screens/customers/customers_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/customers_tab.dart#L100-L180)

---

## 4. Detailed Implementation Steps

### Step 1: Add Archive & Reactivate Methods in `GymService`
- Implement `Future<void> archiveCustomer(String customerId)`:
  - Fetches customer, sets `isActive = false`, calls `updateCustomer()`.
  - **CRITICAL**: This must call `_cloudSaveCustomer(updated)` (upsert with `isActive: false`), NOT `_cloudDeleteCustomer()`. Using the delete method would permanently destroy the member’s cloud records, which defeats the purpose of archiving.
- Implement `Future<void> reactivateCustomer(String customerId)`:
  - Fetches customer, sets `isActive = true`, calls `updateCustomer()`.
- Add guard to `deleteCustomer(String customerId)` (line 766):
  - Check if payments or bills exist for `customerId` using `_paymentMap.values.any((p) => p.customerId == customerId)`.
  - If payments exist, throw an exception or return a status indicating archiving is required.
  - Note: `deleteCustomer()` currently also removes attendance records at line 768 (`_attendanceMap.removeWhere`). Archiving must preserve these.

### Step 2: Update UI in `customer_detail_screen.dart`
- In the top action menu (`PopupMenuButton` or header actions):
  - If member is active: Show **"Archive Member"** (with `Icons.archive_outlined`).
  - If member is inactive: Show **"Reactivate Member"** (with `Icons.unarchive_outlined`).
  - Show a banner at the top of the detail screen when viewing an archived member:
    *"📦 This member is Archived. They do not appear in daily attendance."*
- Replace direct "Delete Member" with an informative dialog:
  - Show options: `"Archive (Recommended)"` and `"Cancel"`.
  - Only show `"Permanently Delete"` if no payments exist.

### Step 3: Add Filter Chips in `customers_tab.dart`
The existing `customers_tab.dart` already has three filter chips (lines 106-125):
- `All` — shows all members including inactive ones via `searchCustomers()`
- `Active` — filters `c.isActive` (line 46-47)
- `Pending Dues` — filters by `MemberLifecycleStage.due`

The `Active` filter already hides archived members. Add a new dedicated chip:
- `Archived` — shows only `!c.isActive` members with an archived badge/banner.

Display archived count in the chip label. Ensure the `All` filter continues to show both active and archived members.

---

## 5. Edge Cases & Considerations
- **Card Numbers of Archived Members**: The physical card number of an archived member should remain associated with them unless the owner explicitly clears or reassigns it upon archiving.
- **Reporting Consistency**: Income reports must include receipts from both active and archived members so annual revenue matches actual bank deposits.
- **Cloud Synchronization**: Archiving calls `_cloudSaveCustomer()` (upsert) to update `isActive = false` in Firestore. This is safe. Verify that the Firestore snapshot listener in `gym_service.dart` (line 378) correctly handles incoming `isActive = false` documents without treating them as deletions.
- **Attendance Records**: All historical attendance records must be preserved for archived members. Currently, `deleteCustomer()` removes them via `_attendanceMap.removeWhere` at line 768 — `archiveCustomer()` must NOT do this.
- **Bulk Attendance**: After archiving, the "Mark All Present" button (daily_attendance_tab.dart line 63) already filters by `c.isActive`, so archived members are automatically excluded from bulk marking.

---

## 6. Validation & Testing Checklist
- [ ] Archive an active member who has payment records: verify they disappear from the daily attendance list.
- [ ] Open monthly financial report: verify the archived member's past payments and receipts are still counted in total collections.
- [ ] Switch to the "Archived" filter in Members tab: verify the member appears with an archived badge.
- [ ] Tap "Reactivate Member": verify the member immediately returns to the active member list and daily attendance.
- [ ] Try to permanently delete a member with 3 paid receipts: verify the app blocks deletion and offers Archiving instead.
