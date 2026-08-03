# Scrape settings layout TDD evidence

## Source and user journeys

The acceptance criteria were confirmed in the task conversation; no external plan file was used.

- As a user, I can scan compact scrape options with labels on the left and their controls on the right.
- As a user, I can keep excluded prefixes collapsed, expand them for editing, and scroll the dialog on a constrained screen.
- As a user, I see neutral secondary text on every text button while emphasized button styles retain their contrast colors.

## RED and GREEN evidence

| Guarantee | Test target | RED evidence | GREEN evidence |
| --- | --- | --- | --- |
| Three scrape booleans use trailing switches; max count is a left-label/right-input row; rendered row gaps are 8 px | `test/views/works_feature_test.dart` | Test-only run found zero `SwitchListTile` widgets and missing layout keys | Focused run passed |
| Prefixes start collapsed, show count and chevron, expand for editing, and remain scrollable in a 300 x 300 viewport | `test/views/works_feature_test.dart` | Test-only run could not find `scrape-prefix-section` | Focused run passed |
| Prefix normalization and scrape option forwarding remain intact | `test/views/works_feature_test.dart` | Existing forwarding test was adapted to the collapsed section | Focused and full runs passed |
| Global `TextButton` foreground uses `onSurfaceVariant` without changing Filled, Elevated, or Outlined button foregrounds | `test/core/app_theme_font_test.dart` | Theme resolved the `TextButton` foreground to `primary` | Focused run passed |

Commands and results:

- `flutter test test/views/works_feature_test.dart test/core/app_theme_font_test.dart` — 20 tests passed.
- `flutter test` — 179 tests passed.
- `flutter analyze` — no issues found.
- `dart format --output=none --set-exit-if-changed lib/core/config.dart lib/views/works_view.dart test/core/app_theme_font_test.dart test/views/works_feature_test.dart` — no formatting changes required.
- `git diff --check` — passed.

## Coverage and known gaps

The changed behavior is covered by widget and theme tests, including constrained viewport and option-forwarding paths. A numerical line-coverage threshold was not collected; the repository does not currently enforce an 80% coverage gate. No Git checkpoint commits were created because the task did not authorize Git mutation.

## Independent verification

An independent read-only verifier inspected the final diff and reran both focused test files: PASS, 20 tests passed.
