# Actress aliases and global work deletion — TDD evidence

## Scope

- Store multiple aliases per actress and manage them from the actress detail page.
- Scrape works using the canonical name and every alias, while deduplicating sources and work codes.
- Long-press works to enter multi-select mode and globally delete selected works, their actress links, and only unreferenced managed image files.

## RED evidence

The first focused test run failed because the alias database APIs, scraper `aliases` input, global work-deletion report/API, and alias/selection UI keys did not exist yet.

Two additional regression tests were then added and observed failing before their fixes:

- renaming an actress to an existing alias left the canonical name duplicated in `actress_aliases`;
- deleting an empty or unknown work-id set incorrectly reported a committed deletion.

## GREEN evidence

Commands were run with `--no-pub` after the initial environment check so verification could not change dependency resolution.

- `flutter test --no-pub test\core\work_database_test.dart test\services\works_scrape_service_test.dart` — PASS, 36 tests.
- `flutter test --no-pub test\views\works_feature_test.dart test\views\detail_alias_test.dart` — PASS, 12 tests.
- `flutter analyze --no-pub` — PASS, no issues.
- Focused coverage run for the changed feature tests — PASS and produced `coverage/lcov.info`.
- Changed executable lines — 390/473 covered (82.5%).
- Case-variant alias exact matching — observed RED, then PASS after switching to case-insensitive exact comparison.
- Shared-URI retry after a transient canonical page failure — PASS.
- Global deletion of 501 works/links across multiple SQLite bind batches — PASS.
- Final alias/work widget group — PASS, 13 tests.

Core changed-line coverage included:

- `lib/core/database.dart` — 154/160 (96.2%).
- `lib/services/works_scrape_service.dart` — 28/32 (87.5%).
- `lib/views/detail_view.dart` — 67/74 (90.5%).
- `lib/views/works_view.dart` — 116/124 (93.5%).

## Full-suite result

`flutter test --no-pub --concurrency=1` completed with 159 tests: 158 passed and 1 failed.

The sole failure is the pre-existing typography assertion in `test/core/app_theme_font_test.dart` (`FontWeight.w300` expected, `FontWeight.w400` rendered). It reproduces when that file is run alone, and this feature does not modify theme, font, or typography configuration. All alias, scraping, database deletion, recovery, and multi-select tests passed in the full run.

## Safety assertions covered

- Alias input is trimmed, blank values are removed, comparison is case-insensitive, and the canonical name cannot remain as an alias.
- Opening an older database creates the alias table without destructive migration.
- Scraping tries canonical and alias names, tolerates an individual source failure, and deduplicates by source URI and normalized work code.
- A source URI is marked complete only after its work traversal succeeds, so a later alias can retry a transient failure.
- Work deletion removes selected work rows and all actress links atomically.
- Large selections use 500-ID SQL batches inside the same transaction.
- Stored image paths are validated against the managed image root before deletion.
- Files still referenced by another actress or work are retained.
- Failed post-commit file cleanup remains in `pending_file_deletions` for startup retry.
- Empty and unknown selections are non-committing no-ops.
