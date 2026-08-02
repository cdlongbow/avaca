# Actress deletion observability and stored-path cleanup — TDD evidence

## Scope

Derived from the approved defect-repair plan. This change adds only deletion
diagnostics and safe resolution for image paths already stored by the app; it
does not change scraping, backup, or list behaviour.

## RED evidence

1. `deletion report snapshots the actual Android managed root before rows are
   removed` initially failed to compile because `ActressDeletionReport` did not
   expose snapshot, transaction, queue, or per-file diagnostic fields.
2. `deletes supported JavBus managed-image path formats under Android
   documents` then ran against a real temporary SQLite DB rooted at
   `<documents>/avaca_data/images`. It committed the DB transaction with
   `snapshot_work_count=3`, but rejected all five non-absolute card/detail
   paths. The test root retained 5 files / 75 bytes from 6 files / 81 bytes.
   The rejection reason was `path is outside image root` for `file://`,
   documents-relative, managed-root-relative, `works/...`, and `/works/...`.

## GREEN evidence

Commands successfully run:

```text
flutter test test/core/work_database_test.dart --plain-name "deletion report snapshots the actual Android managed root before rows are removed"
flutter test test/core/work_database_test.dart --plain-name "deletes supported JavBus managed-image path formats under Android documents"
flutter test test/core/work_database_test.dart
flutter analyze
```

Results:

- Report/snapshot integration test: PASS.
- Supported-path integration test: PASS. It ended with `actresses=0`,
  `works=0`, `actress_works=0`, queue empty, managed files `6→0`, and bytes
  `81→0` after close/reopen.
- Focused database suite: 24 passed.
- Static analysis: `No issues found`.

## Guarantees

| # | Guarantee | Test | Result |
|---|---|---|---|
| 1 | The deletion report records the pre-delete actress/work snapshot, DB transaction row counts, canonical root, per-file details, and queue before/after. | `deletion report snapshots the actual Android managed root before rows are removed` | PASS |
| 2 | Absolute, `file://`, documents-relative, managed-root-relative, `works/...`, and legacy `/works/...` paths resolve only under canonical `<documents>/avaca_data/images`. | `deletes supported JavBus managed-image path formats under Android documents` | PASS |
| 3 | One actress with three unshared works deletes all rows and six real avatar/card/detail files; reopening does not restore rows. | same integration test | PASS |
| 4 | Shared works and shared physical image paths remain protected by the existing focused database tests. | `deleting an actress preserves shared work data and images`; `deleting an orphan work preserves an image path still referenced by another work` | PASS |
| 5 | Missing files, deferred delete retry, post-commit interruption recovery, external-path rejection, and conditional maintenance remain covered. | focused database suite | PASS |

## Verification limitation

The post-change widget-only regression test could be statically analyzed but
not executed in this workstation run: Flutter repeatedly crashed before test
startup while copying its generated `build/native_assets/windows/sqlite3.dll`
(`PathExistsException`, Windows error 183). The generated DLL could not be
removed because Windows returned access denied. No source or user data was
deleted to work around that tooling failure. Focused SQLite tests and static
analysis are direct execution evidence; a physical Android delete remains the
final runtime confirmation.
