# GymManagement Improvement & Handover Master Plan

## Overview
This directory contains actionable, step-by-step engineering plans addressing the critical gaps and improvements identified during the gym-owner handover audit.

> **CRITICAL DIRECTIVE**: Execution of these plans has **NOT** been started. These plan files define the exact requirements, affected files, edge cases, implementation steps, and validation checks for review before proceeding with implementation.

---

## Task Roadmap & Priority Matrix

| Task ID | Task Name | Priority | Category | Plan File | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TASK-01** | Guard Live Account Against Demo Data Overwrite | **Critical** | Data Safety | [task_01_demo_data_safety.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_01_demo_data_safety.md) | ✅ **Completed** |
| **TASK-02** | Enforce Unique Card Numbers & Phone Duplicate Warnings | **Critical** | Data Integrity | [task_02_duplicate_prevention_card_uniqueness.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_02_duplicate_prevention_card_uniqueness.md) | Ready |
| **TASK-03** | Fast Member Search (Attendance, Billing & Card Numbers) | **High** | Daily Operations | [task_03_quick_member_search.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_03_quick_member_search.md) | Ready |
| **TASK-04** | Member Archiving & Status Lifecycle | **High** | Accounting Integrity | [task_04_member_archiving_and_lifecycle.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_04_member_archiving_and_lifecycle.md) | Ready |
| **TASK-05** | Configurable Receipts, Gym Timings & Dynamic Branding | **High** | Business Setup & Legal | [task_05_receipt_and_branding_customization.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_05_receipt_and_branding_customization.md) | Ready |
| **TASK-06** | Standardize Money & Pricing Decimal Precision | **High** | Financial Accuracy | [task_06_money_precision.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_06_money_precision.md) | Ready |
| **TASK-07** | Complete Database Backup & Restore Workflow | **High** | Disaster Recovery | [task_07_backup_and_recovery.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_07_backup_and_recovery.md) | Ready |
| **TASK-08** | Existing-Member CSV Import with Live Preview | **Medium-High** | Onboarding | [task_08_existing_member_import.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_08_existing_member_import.md) | Ready |
| **TASK-09** | Permanent Media Storage & Cross-Device Sync | **Medium** | Media Reliability | [task_09_image_persistence_sync.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_09_image_persistence_sync.md) | Ready |
| **TASK-10** | Transparent Reminder Delivery & Actionable Queues | **Medium** | Communication | [task_10_reminder_workflow_transparency.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_10_reminder_workflow_transparency.md) | Ready |
| **TASK-11** | Staff & Receptionist Role Access (Phase 2 Roadmap) | **Phase 2** | Security & Access | [task_11_staff_access_roadmap.md](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/plans/task_11_staff_access_roadmap.md) | Roadmap |

---

## Shared Dependencies Preparation Step

Before executing tasks that touch local file storage, file sharing, or imports, add the following packages to `pubspec.yaml`:
- **`path_provider`**: Required by **TASK-07** (Backup & Restore) and **TASK-09** (Permanent Image Storage).
- **`share_plus`**: Required by **TASK-07** (Sharing JSON backup files via system share sheet).
- **`file_picker`**: Required by **TASK-07** (Selecting backup file to restore) and **TASK-08** (Selecting `.csv` member import file).

---

## Inter-Task Ordering Constraints

When scheduling and executing these tasks, the following sequential dependencies must be respected:
1. **TASK-02 before TASK-08**: Card number uniqueness validation and conflict resolution logic must exist before importing members in bulk via CSV.
2. **TASK-04 before TASK-07**: Member lifecycle status (`isActive` / archived state) must be stabilized before finalizing the full database backup & restore schema.
3. **TASK-06 before TASK-05**: Decimal price precision and `MoneyUtils` must be in place before calculating configurable taxes, receipts, and custom billing templates.
4. **TASK-09 & TASK-10 Model Migration Co-ordination**: Both tasks modify the `Customer` model (`imageBase64` in Task 09, `lastReminderSentAt` in Task 10). When implementing, ensure `toMap()`, `fromMap()`, and `copyWith()` retain defaults for both fields to avoid schema desynchronization.

---

## Recommended Execution Sequence

1. **Phase 1: Critical Safeguards & Data Integrity**
   - **TASK-01**: Demo Data Overwrite Guard *(✅ Completed)*
   - **TASK-02**: Card Number Uniqueness & Duplicate Prevention
   - **TASK-06**: Decimal & Money Precision Standardization
2. **Phase 2: Core Usability & Lifecycle**
   - **TASK-03**: Fast Member Search (Attendance & Billing)
   - **TASK-04**: Member Archiving & Status Lifecycle
3. **Phase 3: Business Setup & Customization**
   - **TASK-05**: Configurable Receipts, Timings & Dynamic Branding
   - **TASK-10**: Reminder Delivery & Status Tracking
4. **Phase 4: Disaster Recovery & Migration**
   - **TASK-07**: Complete Database Backup & Restore Workflow
   - **TASK-08**: Existing-Member CSV Import with Live Preview
5. **Phase 5: Media Reliability & Future Roadmap**
   - **TASK-09**: Permanent Image Storage & Cross-Device Sync
   - **TASK-11**: Staff & Receptionist Role Access Roadmap (Phase 2)

