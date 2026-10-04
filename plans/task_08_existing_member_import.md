# TASK-08: Existing-Member CSV Import with Live Preview

## Priority: Medium-High
## Category: Owner Onboarding & Data Migration

---

## 1. Problem Statement
When handing over this app to a gym owner who currently tracks members in Microsoft Excel, Google Sheets, or a physical notebook:
- There is **no spreadsheet import workflow**.
- The owner must manually open the "Add Member" form 100 to 300 times to onboard their gym.
- This manual entry takes dozens of hours, introduces typos, and is the single highest barrier preventing gym owners from adopting the software.

---

## 2. Goals & Objectives
1. **Simple CSV Template & Ingestion**:
   - Provide a sample CSV format and downloadable/copyable template:
     `CardNumber,Name,Phone,Plan,DurationMonths,JoinDate,ExpiryDate,BalanceDue,Notes`
   - Support both `.csv` file selection and direct text pasting (for quick copy-paste from Excel/Google Sheets).
2. **Robust Multi-Column Header Parsing**:
   - Tolerant header matching: recognize `"Card #"`, `"CardNo"`, `"Card Number"`, `"Mobile"`, `"Telephone"`, `"Full Name"`, etc.
3. **Comprehensive Validation & Error Detection**:
   - Detect duplicate card numbers within the file and against existing active members.
   - Detect duplicate or malformed phone numbers.
   - Validate plan types and duration months with safe fallbacks.
4. **Interactive Import Preview Table**:
   - Group records into **Ready to Import**, **Warnings** (e.g. shared phone), and **Errors** (e.g. duplicate card number).
   - Let the owner inspect and uncheck individual rows before committing the batch.
5. **Atomic Batch Registration**:
   - Insert all approved members into local storage and cloud database without duplicate ID generation.

---

## 3. Required New Dependencies (not currently in `pubspec.yaml`)
- **`file_picker`**: For selecting `.csv` files from the device. Not currently in pubspec.yaml.
- **`path_provider`**: If the plan needs to save temporary import files (shared with Task 07/09).

---

## 4. Impacted Files
- New Screen: `lib/screens/customers/import_members_screen.dart`
- New Service: `lib/services/csv_import_service.dart`
- [lib/screens/customers/customers_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/customers_tab.dart#L100-L150)
- [lib/services/gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L510-L580)

---

## 5. Detailed Implementation Steps

### Step 1: Create `CsvImportService`
- Define `MemberImportRow`:
  - Fields: `cardNumber`, `name`, `phone`, `planType`, `durationMonths`, `joinDate`, `balanceDue`, `notes`.
  - Status: `isValid`, `errors` (List<String>), `warnings` (List<String>).
- Implement parser:
  - Splits lines and comma delimiters (handling quoted commas like `"Flat 101, Street 2"`).
  - Normalizes headers to known keys.
  - Cross-references each row against `GymService.customers` to flag card and phone collisions.

### Step 2: Build `ImportMembersScreen`
- UI Components:
  - Header with **"Download / Copy Sample CSV Template"**.
  - File picker button (`Pick .csv file`) and a text area toggle (`Paste CSV Text`).
  - **"Analyze & Preview"** action button.
  - **Preview Table**:
    - Chip summaries: `Total Rows: 50 | Valid: 46 | Warnings: 2 | Errors: 2`.
    - Data table showing status badges (Green check, Yellow warning, Red error).
    - Checkbox to include/exclude specific rows.
  - Sticky bottom action bar:
    - Button: `"Import X Members"` (disabled if 0 valid rows selected).

### Step 3: Implement Batch Ingestion in `GymService`
- Add `Future<int> batchAddCustomers(List<Customer> newCustomers)`:
  - **ID Generation Fix**: The current `addCustomer()` generates IDs using `'cust_${DateTime.now().millisecondsSinceEpoch}'` (line 536). When batch-inserting 200 members synchronously, many will receive identical millisecond timestamps, causing ID collisions. Use a different strategy for batch mode:
    ```dart
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < newCustomers.length; i++) {
      final id = 'cust_${baseTimestamp + i}';
      // ... create customer with unique id
    }
    ```
  - Efficiently inserts members into `_customers`.
  - Saves local preferences and triggers batch write to Firestore if cloud is attached.
  - Notifies listeners and refreshes customer directory.

> **BalanceDue Column Mapping**: The CSV template includes a `BalanceDue` column, but the current data model has no standalone "balance owed" field on `Customer`. Balances are derived from attendance-based payment records (see [gym_service.dart#L1108](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L1108)). If a `BalanceDue` value is provided during import:
> - Create a synthetic unpaid payment record with `status: PaymentStatus.pending` and `totalDue` equal to the CSV value.
> - Alternatively, document this as a "known starting balance" note on the member, and defer to Task 05's membership agreement model for proper tracking.
> - The simplest approach for Phase 1: import the member with `notes` field set to `"Imported balance: ₹[amount]"` and let the owner record the first real payment manually.

---

## 6. Edge Cases & Considerations
- **Empty Lines & Trailing Commas**: Excel frequently exports empty rows or blank commas at the end of files; these must be filtered out cleanly.
- **Date Formats**: Support multiple date formats (`DD/MM/YYYY`, `YYYY-MM-DD`, `DD-MM-YYYY`) commonly found in spreadsheets. When a date is completely unparseable (e.g., `"N/A"`, blank, or `"TBD"`), default to today's date and flag the row with a yellow warning badge.
- **Card Number Collisions**: Clearly show which existing member owns the colliding card number so the owner can adjust it in their sheet. This depends on Task 02's `getCustomerByCardNumber()` method — ensure Task 02 is implemented first.

---

## 7. Validation & Testing Checklist
- [ ] Import a CSV with 20 members: verify all 20 are added with correct names, phones, and card numbers.
- [ ] Import a CSV containing a duplicate card number: verify the preview flags the exact row with a red error badge and explains the collision.
- [ ] Paste CSV text with phone numbers that already exist: verify warning appears and allows the owner to import or skip.
- [ ] Verify members imported via CSV appear instantly in Daily Attendance and Billing.
