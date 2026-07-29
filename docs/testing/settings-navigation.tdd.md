# Settings navigation TDD evidence

## Source and journeys

The journeys were derived from the approved Gate 1 plan for the settings
navigation change:

- A user sees settings grouped into categories before seeing individual
  controls.
- A user opens a category as a separate page and can return to the settings
  root.
- A user expands a detail row to reveal all choices and can collapse it to
  remove those choices.
- A user sees the pure-black AMOLED control only when the effective theme is
  dark, including system-dark, without losing the stored preference.
- A user can continue editing custom theme colors, including opaque black
  (`#000000`, stored as `0xFF000000`).
- A user sees the two top-level categories as simple icon cards with the
  project's 12 px rounded outline and no redundant right arrow.
- A user sees each expandable setting inside the same rounded outline; the
  outline grows with the content through a short 180 ms transition without the
  default expanded top and bottom borders.
- A user expands Dark inside the Theme Mode outline to reveal AMOLED, while
  system-dark remains set to follow the system.
- A user expands Custom Theme inside the same outline to reveal all color
  controls without standalone sections or dividers.
- A user sees the color-picker dialog outline update immediately to the color
  currently being selected.
- A user choosing a custom theme keeps every custom color unchanged even when
  the stored pure-black preference is enabled; custom colors and dark OLED are
  independent settings.
- A user in custom mode on a dark platform sees Custom as the expandable color
  submenu, while Dark remains a normal radio choice and AMOLED stays absent.
- A user expanding Dark sees copy that states AMOLED works only with the dark
  theme, without implying that it applies to a custom theme.
- A user pressing a category or nested settings row sees no full-row Material
  wash; instead a small circular response appears at the touch coordinate and
  fades after release.

## RED and GREEN report

The four newly approved behaviors above were first verified as RED, then made
GREEN by the minimal production changes recorded below.

| Stage | Command | Result | Evidence |
|---|---|---|---|
| RED | `flutter test test/views/settings_view_test.dart --reporter expanded` | FAIL | Six tests compiled and ran; the first failure reported no widget with text `Theme & Colors`, proving the category behavior was absent. |
| Visual RED | `flutter test test/views/settings_view_test.dart --reporter expanded` | FAIL | The focused suite compiled and ran; failures reported the missing `palette_outlined` icon and null `ExpansionTile.clipBehavior`, proving the approved card and expansion styling was absent. |
| Nested-settings RED | `flutter test test/views/settings_view_test.dart --reporter expanded` | FAIL | Nine tests compiled and ran; five failed because AMOLED and custom colors were still standalone, Dark/Custom had no secondary expansion keys, and the color dialog had no dynamic outline. |
| Custom/OLED and touch-feedback RED | `flutter test test/core/app_theme_font_test.dart test/views/settings_view_test.dart --reporter expanded` | FAIL (valid RED) | 21 tests executed: 16 passed and 5 failed for the intended missing behavior—OLED replaced the custom surface, custom platform-dark still exposed a Dark submenu, dark-only copy was absent, and both pressed rows had no transparent overlay/local feedback dot. |
| GREEN | `flutter test test/views/settings_view_test.dart --reporter expanded` | PASS | All ten settings widget tests passed. |
| Custom/OLED and touch-feedback GREEN | `flutter test test/core/app_theme_font_test.dart test/views/settings_view_test.dart --reporter expanded` | PASS | All 22 focused core/settings tests passed, including exact custom colors, custom Dark-row shape, dark-only copy, touch-coordinate feedback, and a 320×480 viewport at 125% text scaling. |
| Regression | `flutter test --coverage --reporter expanded` | PASS | All 35 project tests passed. |
| Analysis | `flutter analyze` | PASS | `No issues found!`. |

No RED/GREEN checkpoint commits were created because this project defaults to
propose-only Git authorization. A commit remains subject to Gate 2 approval.

## Test specification

| # | What is guaranteed | Test target | Type | Result |
|---|---|---|---|---|
| 1 | The settings root shows only `Theme & Colors` and `Interface`, with their details hidden. | `settings root shows categories but hides their details` | Widget | PASS |
| 2 | The theme category opens as a Navigator page with its own AppBar and back action. | `system dark nests AMOLED under Dark without changing the selected mode` | Widget | PASS |
| 3 | Theme choices are absent while the outer Theme Mode section is collapsed and appear after expansion. | `system dark nests AMOLED under Dark without changing the selected mode` | Widget | PASS |
| 4 | Selecting Dark from system-light changes the mode and promotes Dark into a secondary expandable row. | `system light promotes Dark from a radio option after it is selected` | Widget/integration | PASS |
| 5 | The interface category contains the expandable language choices and updates its AppBar after a locale change. | `interface category expands all language choices` | Widget/integration | PASS |
| 6 | AMOLED is absent in effective light mode. | `AMOLED is hidden in effective light mode` | Widget | PASS |
| 7 | System-light changing to system-dark reveals AMOLED and preserves a stored enabled preference. | `AMOLED follows effective system darkness and preserves its preference` | Widget/integration | PASS |
| 8 | Selecting Custom from another mode promotes it into a collapsed secondary row; expanding it exposes the complete color editor. | `selecting Custom promotes it into a collapsed color submenu`; `custom theme nests the complete color editor under Custom` | Widget/integration | PASS |
| 9 | Both top-level categories use simple icons, no right chevron, and the same 12 px/1 px outlined card shape as the project cards. | `settings root shows categories but hides their details` | Widget | PASS |
| 10 | Theme and language sections retain the default expand arrow, use matching collapsed/expanded rounded outlines, and omit the default border treatment. | `system dark nests AMOLED under Dark without changing the selected mode`; `interface category expands all language choices` | Widget | PASS |
| 11 | In system-dark, expanding Dark reveals AMOLED without changing the stored mode from `system`; tapping its Radio changes the stored mode to `dark`; in effective light, no empty Dark submenu is shown. | `system dark nests AMOLED under Dark without changing the selected mode`; `AMOLED is hidden in effective light mode` | Widget/integration | PASS |
| 12 | Dark and Custom use distinct PageStorage keys, start collapsed after their tested mode transitions, use transparent backgrounds and empty shapes, and add no Dividers. | `system dark nests AMOLED under Dark without changing the selected mode`; `system light promotes Dark from a radio option after it is selected`; `selecting Custom promotes it into a collapsed color submenu`; `custom theme nests the complete color editor under Custom` | Widget/integration | PASS |
| 13 | The color dialog uses a 12 px/1 px outline whose color rebuilds immediately after the picker callback changes color. | `color dialog previews the selected color on its outline` | Widget | PASS |
| 14 | `AppThemeMode.custom` returns the exact supplied custom palette even if `oledBlack` is true. | `custom palette ignores OLED and keeps every custom color exact` | Unit | PASS |
| 15 | In platform-dark custom mode, Custom owns the expandable submenu, Dark remains a plain radio, and AMOLED is absent. | `custom mode in platform dark keeps Dark a radio and hides AMOLED` | Widget/integration | PASS |
| 16 | Fixed dark mode describes AMOLED as dark-only and removes the former custom-theme wording. | `fixed dark AMOLED copy excludes custom theme` | Widget | PASS |
| 17 | Category and nested rows suppress the full-tile pressed overlay and show a small circular response at the actual touch point that fades on release. | `category press uses a transparent tile overlay and local feedback dot`; `nested setting press shares the transparent local feedback behavior` | Widget | PASS |
| 18 | The expanded custom color editor remains scrollable without overflow at 320×480 and 125% text scaling. | `custom settings remain scrollable on a narrow scaled viewport` | Widget/responsive | PASS |

## Coverage and known gaps

- `lib/views/settings_view.dart`: 247 of 258 lines hit, **95.74%**.
- `lib/core/config.dart`: 156 of 186 lines hit, **83.87%**.
- Whole repository: 1008 of 2211 lines hit, **45.59%**. This reflects the
  pre-existing project-wide test gap; the changed settings view exceeds the
  required 80% line coverage.
- The existing `ColorPicker` accepts any Flutter `Color`, and
  `SettingsController.saveCustomTheme` persists `Color.toARGB32()` without
  filtering black. The default custom `surface` is already opaque black. No
  production change was needed for `#000000`.
- No manual desktop interaction session or platform E2E harness was available;
  the critical navigation and theme flows are covered by Flutter widget tests.
