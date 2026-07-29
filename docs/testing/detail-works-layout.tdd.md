# Detail profile layout and Works page — TDD evidence

## Source and journeys

The journeys were derived from the user-approved task list in the current
Codex task; no separate plan file was supplied.

- A user can see the profile image on the left and the Works button above the
  attributes on the right, without overflow at phone or desktop widths.
- A user editing a profile sees the same layout, a compact 18 px name field,
  and compact attribute chips whose label text is not reduced.
- A user can open the actress's Works page from view or edit mode. The page
  title uses the persisted actress name, and returning preserves an unsaved
  edit on the detail page.

## RED → GREEN

The Flutter CLI wrapper could not write its state under the sandboxed AppData
directory, so validation invoked the existing Flutter tool snapshot directly
with the same test runner and `--no-pub`. No dependencies were installed.

| Stage | Command | Result |
|---|---|---|
| RED | `dart .../flutter_tools.snapshot test test/views/detail_works_view_test.dart --no-pub` | **Expected failure**: test compilation could not read `lib/views/works_view.dart` and `WorksView` was undefined. |
| GREEN | `dart .../flutter_tools.snapshot test test/views/detail_works_view_test.dart --no-pub` | **PASS**, 4/4 tests. |
| Regression | `dart .../flutter_tools.snapshot test --no-pub` | **PASS**, 21/21 tests. |
| Analysis | `dart .../flutter_tools.snapshot analyze --no-pub` | **PASS**, no issues found. |
| Coverage | `dart .../flutter_tools.snapshot test test/views/detail_works_view_test.dart --coverage --coverage-path=<task-visualization-dir>/detail_works_lcov.info --no-pub` | **PASS**, 4/4 tests. |

An intermediate post-implementation run exposed two test-harness setup issues:
widget state was reused between two sizes in one test, and the app-level route
test inherited the host locale. Resetting the widget between sizes and fixing
the test locale resolved these without changing production behavior.

## Test specification

| # | What is guaranteed | Test type | Result |
|---|---|---|---|
| 1 | At 390 px, image/button spacing is symmetric and Works appears above right-side attributes. | Widget | PASS |
| 2 | Edit mode preserves that placement, keeps the name at 18 px in a field no taller than 40 px, and uses chips no taller than 32 px with 14 px labels. | Widget | PASS |
| 3 | View and edit modes render without overflow at 320 px and 1280 px. | Widget | PASS |
| 4 | `/works/7` renders `已儲存名稱演出的作品`, does not leak the unsaved name, and back navigation restores the unsaved field value. | Integration widget | PASS |

## Coverage and known gaps

Targeted line coverage from the generated LCOV report:

- `lib/controllers/works_controller.dart`: 9/9 (100%)
- `lib/views/works_view.dart`: 32/32 (100%)
- `lib/views/detail_view.dart`: 208/247 (84.2%)
- `lib/main.dart`: 54/84 (64.3%); the new Works route is exercised, while
  unrelated startup/theme branches remain outside this focused test.

The report's aggregate application coverage is 602/2131 (28.2%), so the
repository-wide 80% target is not met by the current project test inventory.
The changed page/controller scope exceeds 80%, apart from `main.dart`, where
the changed route is covered but unrelated application bootstrap code lowers
the file total.

No Git checkpoint commits were created because this task explicitly withheld
Git mutation authorization.

## Code Review correction round 1

Focused tests were changed first for the review findings, then executed before
production changes.

| Stage | Result |
|---|---|
| RED | **3 intended failures**: at 1280 px the left gap was 16 px while the right gap to the screen was 853.33 px; the pending Works page had no AppBar; database failure was not rendered as a load error. Existing tests continued to pass. |
| GREEN | Focused suite **7/7 PASS** after making the profile section full-width at desktop sizes and keeping the Works Scaffold/AppBar outside loading-state replacement. |
| Regression | Full suite **24/24 PASS**. |
| Analysis | `flutter analyze --no-pub`: **No issues found**. |

The correction tests additionally guarantee:

- At 1280 px, the image-to-button and button-to-screen gaps differ by no more
  than 1 px.
- During a pending database read, Scaffold, AppBar, the `作品` title, progress
  indicator, and a localized accessible back tooltip remain visible.
- A database exception renders a localized generic failure, while a missing
  actress independently renders `找不到資料`.

## Code Review correction round 2

The existing error-state test was first tightened to reject the raw exception
text `database unavailable`.

| Stage | Result |
|---|---|
| RED | **1 intended failure**: the rendered text was `載入失敗：Bad state: database unavailable`, so the raw exception assertion found one prohibited match. |
| GREEN | Focused suite **7/7 PASS** after rendering the new localized generic `載入失敗` message without interpolating the controller error. |
| Coverage | Focused coverage suite **7/7 PASS**; controller 100%, Works view 100%, detail view 84.2%, and aggregate application coverage 28.2%. |
| Regression | Full suite **24/24 PASS**. |
| Analysis | `flutter analyze --no-pub`: **No issues found**. |

The controller retains the internal error object for diagnostics, but no error
text or path is exposed by the Works UI.

## Domain Verification correction round 3

This round added verification only; the new tests passed against the existing
production implementation, so no production files were changed.

| Validation | Result |
|---|---|
| Narrow text scaling | At 320 px with `TextScaler.linear(1.25)`, view and edit layouts render the image, Works button, compact name field, and FilterChips without overflow or framework exceptions. |
| View-mode navigation | Before edit mode is entered, Works opens with the persisted `已儲存名稱演出的作品` title; back returns to the unchanged non-editing DetailView. |
| Focused suite | **9/9 PASS**. |
| Focused coverage | **9/9 PASS**; controller 9/9 (100%), Works view 32/32 (100%), detail view 208/247 (84.2%), main 54/84 (64.3%), aggregate application 602/2131 (28.2%). |
| Regression | Full suite **26/26 PASS**. |

Static analysis was not rerun in this tests-and-evidence-only round because no
production code changed; the immediately preceding production round completed
with `flutter analyze --no-pub` reporting no issues.
