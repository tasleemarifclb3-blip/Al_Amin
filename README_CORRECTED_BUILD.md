# Al-Amin Baitul Maal — corrected project build

This archive is based on the latest complete AABM project available in the conversation, with the requested receipt-printing, backup/restore, security-gate and Qarz-return changes merged into the actual source files. Unrelated reporting, confidentiality and approval features from the base project were preserved.

## Changes included

### Thermal receipts

All requested receiving receipts now use the compact 80 mm thermal layout:

- Monthly Donation
- General Donation
- Box Collection
- Zakaat Received
- Sadqa-e-Fitr Received
- Other Income
- Historical receipt reprints for the above transaction types

The thermal layout uses a narrow page, compact rows, small branding and reduced spacing so it wastes substantially less thermal paper than the previous A4-style layout.

### Qarz recovery / return receipt

Qarz recovery receipts now use a dedicated compact thermal format containing only the requested transaction summary:

- Name
- Amount
- Amount Borrowed
- Amount Returned (including this receipt)
- Balance After This Receipt

The receipt also has only the small document title; address, phone, Aadhaar, cheque/payment details, verification fields and signatures are intentionally excluded from this repayment receipt.

Historical Qarz recovery reprints calculate the cumulative borrowed amount, cumulative returned amount including the selected receipt, and the balance after that receipt.

### Backup and restore

- A complete JSON backup covers the accounting and workflow tables used by the app.
- The normal **BACK UP DATA** action uses the application's private application-support location on native platforms; Web uses the browser save/download flow.
- **SAVE BACKUP COPY...** lets the user export a backup to another location for transfer or external storage.
- A latest recovery copy is kept locally inside the application database so local data deletion does not remove the last recovery point.
- Restore validates the backup format, schema version and table structure and gives specific errors for invalid JSON, PNG and PDF selections.
- Restore retains the device identity and rebuilds local sync state rather than replaying an old device's sync queue.
- The existing global-restore/global-delete path remains synchronized across Firebase and devices.
- Local-only deletion continues to pause cloud sync on that device so the intact Firebase dataset is not immediately downloaded back; a deliberate reconnect action is available.
- Destructive deletion still requires a complete user-saved backup before deletion and requires two confirmations.

### Password management

- **Admin Password** defaults to `1212` and is changeable.
- **Manage Users & Passwords**, including changing the Superuser/Admin passwords, is protected by the separate Admin Password.
- The **Superuser Password** remains the authorization used for sensitive accounting edits, confidential data and Data Management access.

### Preserved project functionality

The base project's approval workflow, pending/rejected transaction handling, confidential ledger masking, Superuser Reports, formal financial statement, dashboard changes and reconciliation behaviour are preserved rather than replaced by receipt patches.

## Build and verify on Windows

Open a terminal in the project folder and run:

```powershell
flutter pub get
flutter analyze
flutter run -d windows
```

For Android, run:

```powershell
flutter pub get
flutter analyze
flutter run
```

Before testing deletion or restore against production data, create an external backup copy and use a test database where possible.

## Important accounting note

The generated PDF/thermal printouts are presentation formats generated from the accounting data recorded in the app. Reconcile important financial statements against the cashbook, bank statements, vouchers and approvals before official submission.

## Validation status in this editing environment

Source-level checks were run on the final project, including Dart delimiter balancing, relative-import existence, ReceiptActions API consistency, required thermal-receipt wiring, backup-table coverage, the Admin-password gate and preservation checks for the base reporting/confidentiality features.

A full Flutter build and `flutter analyze` could not be run here because the Flutter/Dart SDK is not installed in this editing environment. The archive is therefore source-validated, not runtime-validated.
