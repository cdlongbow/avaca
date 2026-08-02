# Delete actress cleanup — TDD evidence

## Scope

Derived from the approved defect fix: deleting an actress must remove stale,
unreferenced regular files below `images/scraped` and compact SQLite only after
the database deletion has committed. Existing referenced and non-scraped files
must remain intact.

## RED

Command run by the parent agent:

```text
flutter test test/core/work_database_test.dart --reporter expanded
```

The new regression test at `test/core/work_database_test.dart:414` executed and
failed with expected `[false, true]` but actual `[true, false]`: the stale file
remained and SQLite page count was not reduced.

## GREEN

```text
flutter test test/core/work_database_test.dart --reporter expanded
```

Result: 15 tests passed, including `deleting an actress cleans stale scraped
files and compacts the database` and the managed-image lifecycle concurrency
regression below.

```text
flutter test test/services/works_scrape_service_test.dart --reporter expanded
```

Result: 3 tests passed.

## Guarantees

| Guarantee | Evidence |
| --- | --- |
| An unreferenced regular file under `images/scraped` is deleted after actress deletion. | `work_database_test.dart` cleanup/compaction test |
| Database-referenced and non-scraped image files remain. | Same test |
| SQLite `page_count` drops after the deleted large work is committed. | Same test |
| Deletion waits for a prepared scraped file to receive its surviving database reference. | `work_database_test.dart` lifecycle concurrency test |
| Existing scrape persistence behavior remains green. | `works_scrape_service_test.dart` |

## Lifecycle serialization RED/GREEN

The new deterministic concurrency test starts a managed lifecycle operation,
writes `images/scraped/surviving.jpg`, pauses before writing another actress'
database reference, and starts deletion concurrently.

RED command:

```text
flutter test test/core/work_database_test.dart --reporter expanded
```

Result: compilation failed because `AppDatabase.runManagedImageLifecycle` was
not defined at `test/core/work_database_test.dart:444`. This was the missing
serialization API exercised by the regression.

After implementing the serialized lifecycle and wrapping deletion plus scrape
image download/reference sections, the same command passed all 12 tests. The
test verifies deletion remains incomplete while the reference write is paused,
then confirms the file and surviving reference remain after both operations
finish.

## Public writer and reentrancy RED/GREEN

The public-writer test pauses an active lifecycle, then invokes
`syncActressDetails`, `updateActress`, and `upsertActressWork` directly with
managed image paths. The nested-lifecycle test calls the lifecycle API from
inside an existing lifecycle operation with a 100ms timeout.

Before the boundary enforcement and Zone-scoped reentrancy change, the focused
database command executed both tests and failed: the three public writers had
already completed (`Expected: 0`, `Actual: 3`), and the nested call threw a
`TimeoutException` after 100ms. `addActress(imgPath:)` was then added to the
same test and produced `Expected: 0`, `Actual: 1` until it was guarded too.
After the change, the same command passed all 15 tests. Public writers wait for
the prior lifecycle, while a lifecycle owner
can safely call another guarded database API.

## Detached descendant RED/GREEN

The detached-descendant test creates an unawaited child from within a lifecycle
Zone, allows the outer lifecycle to finish, then starts and blocks a second
lifecycle. Before the ownership fix, releasing the child completed it before
the second lifecycle released (`Expected: false`, `Actual: true`), proving the
inherited Zone bypassed FIFO ordering.

The lifecycle owner now accepts direct nested calls only while its outer scope
is active and waits for any already-started nested operations before releasing
the queue. A child that resumes after outer completion must enqueue normally.
The focused database command passed all 15 tests with this behavior.

## Gaps

Final validation also passed:

```text
flutter analyze
flutter test --reporter expanded
flutter test test/core/work_database_test.dart test/services/works_scrape_service_test.dart --coverage --reporter compact
```

Static analysis reported no issues, the full suite passed all 118 tests, and
the focused coverage run passed all 18 tests. Line coverage was 80.9% for
`lib/core/database.dart`; the changed lifecycle wrapper lines in
`lib/services/works_scrape_service.dart` were all executed. The service file's
total line coverage was 67.8% because unrelated network/error branches are not
part of this deletion fix.

Symlink behavior is enforced by the managed-file check but is not exercised by
this focused test because Windows symlink creation may require platform
privileges.
