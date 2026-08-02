# Unified Noto Sans CJK typography — TDD evidence

## Source and journeys

The journeys were derived from the approved in-task plan; no external plan file
was supplied.

- As a user, I see every application label rendered with the bundled Noto Sans
  CJK TC Variable family instead of a platform primary font.
- As a user, no application text is rendered below variable weight 300.
- As a multilingual user, I can select `zh_TW`, `zh_CN`, `ja_JP`, or `en`, and
  mixed text such as `三上悠亜・八木奈々 / AVACA 简体中文` remains covered by
  the same bundled font.
- As a maintainer, I do not ship the unused `cupertino_icons` dependency or the
  font license as a runtime asset.

## RED and GREEN evidence

| Task | Test target | RED evidence | GREEN evidence |
|---|---|---|---|
| Make the bundled font primary and enforce `w300` | `test/core/app_theme_font_test.dart` and `test/views/settings_view_test.dart` | Focused run failed because the effective family was `Roboto`/null and component styles did not satisfy the new contract. | `flutter test --coverage test/core/app_theme_font_test.dart test/controllers/settings_controller_locale_test.dart test/views/settings_view_test.dart` passed 24/24. |
| Add `ja_JP` selection and restoration | `test/controllers/settings_controller_locale_test.dart` and `test/views/settings_view_test.dart` | Focused run failed because the locale list omitted `ja_JP`, locale resolution returned null, and the Japanese option was absent. | The same focused run passed locale choice, persistence, app restoration, and settings UI tests. |
| Cover mixed Japanese, Chinese, and Latin glyphs | Widget rendering test plus font cmap audit | The original 11.9 MB subset lacked U+4E9C (`亜`) and U+7B80 (`简`). | The official 36.1 MB `NotoSansCJKtc-VF.ttf` covers all requested samples; its cmap has 44,810 code points and its `wght` axis spans 100–900. |
| Keep generated localization and dependencies consistent | `flutter gen-l10n` and `flutter pub get` | The first localization generation failed because Flutter requires a base `ja` fallback when `ja_JP` exists. | Adding `app_ja.arb` made both commands pass; `cupertino_icons` was removed from the resolved graph. |

## Test specification

| # | Guarantee | Test or command | Type | Result |
|---|---|---|---|---|
| 1 | All 15 Material text roles use `NotoSansCjkTcVariable` and weight at least 300 | `test/core/app_theme_font_test.dart` | unit/widget | PASS |
| 2 | Custom component and button theme styles use the same family and minimum weight | `test/core/app_theme_font_test.dart` | unit | PASS |
| 3 | Visible settings text inherits the required family and minimum weight | `test/views/settings_view_test.dart` | widget | PASS |
| 4 | `ja_JP` is selectable, persisted, restored, and advertised by generated localization | `test/controllers/settings_controller_locale_test.dart` | unit/widget | PASS |
| 5 | Japanese appears in the language selector | `test/views/settings_view_test.dart` | widget | PASS |
| 6 | The bundled font manifest points to the complete CJK TC variable TTF | `test/core/app_theme_font_test.dart` | asset/widget | PASS |
| 7 | `三上悠亜`, `八木奈々`, Traditional Chinese, Simplified Chinese, kana, and Latin samples have cmap coverage | fontTools cmap audit | domain verification | PASS |
| 8 | Dart/Flutter static analysis reports no issues | `flutter analyze` | static | PASS |

## Coverage and known gaps

The focused LCOV report covers the changed runtime files at 502/604 lines
(83.1% aggregate):

- `lib/core/config.dart`: 166/196 (84.7%)
- `lib/main.dart`: 49/87 (56.3%)
- `lib/controllers/settings_controller.dart`: 39/62 (62.9%)
- `lib/views/settings_view.dart`: 248/259 (95.8%)

The full `flutter test` command did not complete: it timed out after 244 seconds.
Isolation showed that
`test/controllers/detail_controller_delete_report_test.dart` also times out
when run alone after 64 seconds, while adjacent controller tests pass. This test
belongs to the pre-existing deletion workflow and is outside this typography
change. Therefore the focused change suite is PASS, but the repository-wide test
suite remains BLOCKED by that existing test hang.

No TDD checkpoint commits were created because Git mutation was not authorized.
