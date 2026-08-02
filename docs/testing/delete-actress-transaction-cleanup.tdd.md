# Delete actress transaction cleanup — TDD evidence

## Source and user journeys

Derived from the approved `FIX_BROKEN` plan for deleting an actress without
leaving orphaned JavBus work metadata or managed image files.

- As a user, I can delete an actress and the actress, unshared works, links,
  and managed images disappear together.
- As a user, I can delete one owner of a shared work or shared image without
  losing the remaining owner's data or file.
- As a user, an interrupted or temporarily failed file cleanup finishes on the
  next app startup without reviving database rows or deleting external files.

## RED

The new regression test first referenced the deliberately absent
`deleteActressWithReport`, failure-injection, and post-commit interruption APIs.
The Flutter runner could not initially create its user-level Dart settings in
the sandbox, so the direct Dart analyzer supplied the valid compile-time RED:

```text
9 issues found.
undefined_method: deleteActressWithReport
undefined_named_parameter: deleteFile
undefined_named_parameter: afterDeleteTransactionCommitted
```

## GREEN

Commands run after the implementation:

```text
dart analyze test/core/work_database_test.dart lib/core/database.dart lib/controllers/detail_controller.dart
flutter test test/core/work_database_test.dart --reporter expanded
flutter analyze
flutter test --reporter expanded
flutter test test/core/work_database_test.dart --coverage --reporter compact
```

Results:

- Focused deletion/database suite: 22 passed.
- Static analysis: no issues found.
- Full project suite: 125 passed.
- `lib/core/database.dart` focused line coverage: 474/557 (85.1%).

## Guarantees

| # | Guarantee | Test | Result |
|---|---|---|---|
| 1 | An actress, all of its links, and an unshared work are deleted; avatar/card/detail files are deleted and `images/works` is pruned. | `deleting an actress removes its image and unshared work data` | PASS |
| 2 | A shared work and its images remain when another actress still links to it. | `deleting an actress preserves shared work data and images` | PASS |
| 3 | A physical image path shared by a different surviving work is retained. | `deleting an orphan work preserves an image path still referenced by another work` | PASS |
| 4 | Missing image files are a successful cleanup and leave no queue record. | `missing managed images are successful cleanup and leave no queue garbage` | PASS |
| 5 | A failed delete leaves a pending row; one startup retry deletes the file and clears the row. | `a failed file delete is deferred and startup retry clears its queue entry` | PASS |
| 6 | After the database transaction commits but before file processing, an interruption leaves pending paths; reopening completes cleanup without reviving the actress. | `a committed delete recovers queued image cleanup after a simulated interruption` | PASS |
| 7 | External paths are reported as rejected, retained, and removed from the pending queue. | `an image outside the managed root is rejected, retained, and removed from the queue` | PASS |
| 8 | Canonically duplicate pending records are reduced during the single startup retry. | `startup retry removes duplicate canonical queue records` | PASS |
| 9 | `wal_checkpoint(TRUNCATE)` occurs outside the transaction and `VACUUM` runs only when enough free pages exist. | `deleting an actress preserves untracked files and conditionally compacts the database` | PASS |
| 10 | A failed database transaction starts no file cleanup and leaves all rows, files, and pending records unchanged. | `a transaction failure leaves database rows, managed files, and queue unchanged` | PASS |

## Acceptance metrics from test output

The unshared-work case recorded before/after:

| Metric | Before | After |
|---|---:|---:|
| `actresses` | 1 | 0 |
| `works` | 1 | 0 |
| `actress_works` | 1 | 0 |
| `pending_file_deletions` | 0 | 0 |
| Managed files | 3 | 0 |
| Managed bytes | 17 | 0 |

The shared-work case recorded `actresses` 2→1, `works` 1→1,
`actress_works` 2→1, and managed files 3→2 (17→10 bytes). The shared physical
path case recorded the protected image in `rejected` and retained it on disk.

Device Settings storage displays are deliberately excluded: the verification
uses SQLite counts, managed-root file count/bytes, pending rows, physical-path
checks, and close/reopen behavior.
