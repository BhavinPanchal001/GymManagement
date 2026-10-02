# TASK-07: Complete Database Backup & Restore Workflow

## Priority: High
## Category: Disaster Recovery & Data Ownership

---

## 1. Problem Statement
The app currently lacks any complete owner-facing backup and recovery mechanism:
- In [export_report_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/reports/export_report_dialog.dart#L104), the only "export" function copies a text/CSV summary of pending dues to the device clipboard. It does not export members, past payments, attendance, expenses, or settings.
- Cloud synchronization is not a substitute for backup: because deletions and updates sync immediately to the cloud, accidental deletions or corrupted records are propagated to Firestore right away.
- If a gym owner switches to a new phone, encounters local storage corruption, or wants to keep offline weekly backups for compliance, there is no way to export or restore their data.

---

## 2. Goals & Objectives
1. **Full One-Click JSON Backup**:
   - Package all gym entities into a single structured, versioned JSON file:
     - Customers
     - Attendance Records
     - Payment Records
     - Bill & Receipt Records
     - Expense Records
     - Gym Settings
   - Metadata header with backup timestamp, schema version, gym name, and item counts.
   - Allow sharing the backup file (via WhatsApp, Google Drive, email) or saving to local storage.
2. **Validated Restore Flow with Live Preview**:
   - Allow the owner to select a backup JSON file or paste backup content.
   - Validate structure, schema version, and data integrity before applying.
   - Present a comprehensive **Restore Preview Dialog**:
     - Shows export date, source gym name, and record breakdown (*"54 Members, 132 Payments, 890 Attendance days, 15 Expenses"*).
   - Require explicit confirmation to prevent accidental overwrites.
3. **Safety Rollback Snapshot**:
   - Automatically take an internal temporary snapshot of current records right before executing a restore, enabling instant undo if the wrong file was selected.
4. **CSV Data Export**:
   - Provide standard CSV downloads for:
     - Members Directory (`name`, `phone`, `card`, `plan`, `joinDate`, `status`)
     - Financial Transactions (`receiptNo`, `customer`, `date`, `amount`, `method`, `status`)
     - Expenses Log (`title`, `category`, `date`, `amount`)

---

## 3. Required New Dependencies (not currently in `pubspec.yaml`)
- **`path_provider`**: For `getApplicationDocumentsDirectory()` to write backup files to persistent storage.
- **`share_plus`**: For triggering the platform share sheet (WhatsApp, Google Drive, Email, etc.).
- **`file_picker`**: For selecting `.json` backup files during restore.

> These dependencies are also needed by Task 08 (CSV Import) and Task 09 (Image Persistence). Install them as a preparatory step before executing any of these plans.

---

## 4. Impacted Files
- New Service: `lib/services/backup_service.dart`
- New Dialog / Screen: `lib/widgets/backup_restore_dialog.dart`
- [lib/services/gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L2400-L2450)
- [lib/screens/settings/settings_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L700-L750)
- [lib/screens/reports/export_report_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/reports/export_report_dialog.dart#L100-L150)

---

## 5. Detailed Implementation Steps

### Step 1: Design Versioned Backup Schema
Create JSON format:
```json
{
  "version": 1,
  "exportedAt": "2026-10-01T23:30:00.000Z",
  "appVersion": "1.0.0",
  "gymName": "Titan Fitness Club",
  "summary": {
    "customersCount": 45,
    "paymentsCount": 120,
    "billsCount": 120,
    "attendanceCount": 780,
    "expensesCount": 14
  },
  "data": {
    "settings": { ... },
    "customers": [ ... ],
    "attendance": [ ... ],
    "payments": [ ... ],
    "bills": [ ... ],
    "expenses": [ ... ]
  }
}
```

### Step 2: Implement `BackupService`
- `Future<String> generateBackupJson()`:
  - Collects all in-memory lists/maps from `GymService`.
  - Serializes to pretty JSON string.
- `Future<bool> shareOrSaveBackup(BuildContext context)`:
  - Generates backup file: `GymBackup_YYYYMMDD_HHmm.json`.
  - Saves to temporary file and triggers platform share sheet or download.
- `Future<BackupValidationResult> validateBackupJson(String rawJson)`:
  - Checks JSON structure, version compatibility, and parses summary counts.
- `Future<void> restoreFromBackup(BackupData data, {bool replaceAll = true})`:
  - Captures pre-restore rollback copy.
  - Clears or merges records into `GymService`.
  - Persists locally and synchronizes to Firestore if attached.

### Step 3: Implement Backup & Restore UI in Settings
- In `SettingsTab`:
  - Add a dedicated **"Backup & Data Management"** section:
    - **"Create Full Backup"**: Generates and shares/downloads the backup file.
    - **"Restore from Backup"**: Opens file picker or text paste dialog.
    - **"Export to CSV"**: Offers CSV download of members, payments, and expenses.

---

## 6. Edge Cases & Considerations
- **Schema Migrations**: Include a `version` field so future app updates can transform older backup files without breaking.
- **Large Backups**: In gyms with 200+ members and 2 years of attendance (200 members × 365 days × 2 years ≈ 146,000 attendance records), the JSON backup could reach 15-30 MB. Consider optional gzip compression (`dart:io` GZipCodec) for sharing. Uncompressed backups up to ~5 MB are fine for most gyms.
- **Corrupt File Handling**: If a user uploads an invalid or truncated file, fail gracefully with a descriptive error message without touching existing database state.

---

## 7. Validation & Testing Checklist
- [ ] Export a full backup: verify the JSON file contains valid schema, customer records, payments, and settings.
- [ ] Share the file via WhatsApp / Google Drive: verify recipient receives a valid `.json` file.
- [ ] Delete a member, then restore the backup file: verify the deleted member and their full payment history are restored.
- [ ] Attempt to restore an invalid or corrupt JSON string: verify error is caught and existing data remains untouched.
- [ ] Export CSV for members and payments: open in Excel / Google Sheets and verify clean column alignment.
