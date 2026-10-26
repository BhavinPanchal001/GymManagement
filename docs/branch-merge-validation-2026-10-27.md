# Merge validation — 27 October 2026

Branch: `codex/fee-adjustment-management`
Base: `67cb898` (Show payment coverage on member attendance calendars).

## Changes

- Add fee-adjustment shortcuts, history-only views for settled payments, and audited removal with credit/refund safeguards.
- Improve registration steps, payment controls, navigation from pending dues, and success-dialog presentation.
- Align untouched unpaid registration periods when joining dates are corrected.
- Reconcile untouched attendance-derived periods so corrected attendance cannot leave overlapping dues.
- Use the same PDF bytes for member-card preview, printing and sharing, with direct pinch zoom and a white page background.

## Validation

- Analyzer: all 19 changed Dart files passed with no issues.
- Targeted run across 13 test files: 140 passed; one compatibility expectation still required old automatic-cycle dates. Updated that assertion to match the requested attendance-correction behavior, then reran its complete workflow file: all 10 passed.
- Targeted files: fee_adjustment_test, fee_adjustment_edge_cases_test, fee_adjustment_management_test, registration_partial_payment_test, registration_workflow_layout_test, workflow_compatibility_audit_test, join_date_payment_alignment_test, attendance_inferred_period_reconciliation_test, payment_stale_inferred_agreement_migration_test, payment_inferred_agreement_cloud_order_test, member_cycle_workflows_test, customer_integrity_test, pending_report_test.
- Latest debug APK built successfully and was installed and launched on Samsung SM-S721B before merging.
- `git diff --check` passed.

## Existing test limitations

The full repository suite is not claimed to pass. Earlier broader checks reproduced eight member-card dues/layout expectation failures with the previous screen and a receipt success-message assertion failure with the previous reconciliation implementation. The member-card screen now renders a PDF, so Flutter text-finder assertions for its former handwritten table also require replacement with PDF-aware checks.
