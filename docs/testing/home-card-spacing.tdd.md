# Home card spacing TDD evidence

## Source and journey

The behavior was derived from the approved in-task plan.

As a user, I want the home cards to use compact, consistent spacing so that
images are larger and the grid has equal horizontal and vertical gaps.

## RED and GREEN

| Stage | Command | Result | Evidence |
|---|---|---|---|
| RED | `flutter test test/widget_test.dart` | Expected failure | The old layout returned aspect ratios based on `width + 47`; the new tests expected the compact layout and failed in all three viewport cases. |
| GREEN | `flutter test test/widget_test.dart` | PASS (3/3) | Portrait, landscape, and desktop cases all passed with production theme and Traditional Chinese names. |
| Follow-up RED | `flutter test test/widget_test.dart` | Expected failure | The name still used the font's intrinsic 23 px line box; tests required a compact 16 px line box and failed in all three viewport cases. |
| Follow-up GREEN | `flutter test test/widget_test.dart` | PASS (3/3) | The name now uses `TextStyle.height: 1.0`; its rendered height is 16 px in every tested viewport. |
| Text-scaling RED | `flutter test test/widget_test.dart` | Expected failure | At 125% system text scaling, the fixed 16 px grid estimate caused a 4 px `RenderFlex` overflow. |
| Text-scaling GREEN | `flutter test test/widget_test.dart` | PASS (4/4) | Card height now uses the active `TextScaler`; default and 125% text scaling preserve all spacing without overflow. |
| Regression | `flutter test` | PASS (17/17) | The complete repository test suite passed. |
| Static analysis | `flutter analyze` | PASS | No issues found. |

The focused widget tests guarantee:

- 5 px between the image and the card border.
- 5 px above and below the name.
- A compact 16 px name line box without the font's extra line-height whitespace.
- Correct card height under system text scaling, including the tested 125% case.
- 10 px between adjacent card borders horizontally and vertically.
- No layout overflow or Flutter framework exception.
- The geometry holds at 390×844, 844×390, and 1280×720.

## Coverage and known gaps

`flutter test --coverage --coverage-path=.dart_tool/card_layout_lcov.info test/widget_test.dart`
passed. Focused line coverage was 86.3% for `actress_card.dart` and 52.1% for
the whole `home_view.dart`; the latter also contains unrelated navigation,
search, and filter flows outside this change. All task-owned production lines
were exercised by the focused tests.

No Git checkpoint commits were created because Git mutation was not authorized.
