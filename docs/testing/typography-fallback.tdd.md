# Typography fallback TDD evidence

## User journey

As a Traditional Chinese user, I want Chinese interface text to use a modern
sans-serif fallback while Latin letters and digits keep the platform UI font,
so mixed-language text remains visually consistent.

## RED → GREEN

| Guarantee | Test | Evidence |
|---|---|---|
| Light and dark themes use the bundled Traditional Chinese family | `test/core/app_theme_font_test.dart` | RED: the theme still returned the OS-dependent fallback list. GREEN: both themes return `AvacaNotoSansTC`. |
| Android Latin letters and digits retain Roboto as the primary font | `keeps Android Roboto as the primary font for Latin and digits` | PASS |
| Every Material text style receives the fallback list | `applies the fallback order to every Material text style` | PASS |
| Component-owned styles cannot bypass the bundled font | `applies the bundled font to every custom component text style` | RED: component styles returned a null fallback. GREEN: input, ListTile, dialog, and both navigation-label states use `AvacaNotoSansTC`. |
| Every visible Settings `Text` receives the effective fallback | `all visible settings text inherits the bundled font` | PASS |
| Flutter bundles the registered font and its OFL license | `loads the registered font and license from rootBundle` | RED: `assets/fonts/OFL.txt` could not be loaded. GREEN: FontManifest, all 11,942,912 font bytes, and OFL load through `rootBundle`. |

## Validation

- `flutter test test\core\app_theme_font_test.dart` — PASS, 6/6.
- `flutter test test\core\app_theme_font_test.dart test\views\settings_view_test.dart` — PASS, 13/13.
- `flutter test` — PASS, 16/16.
- `flutter analyze` — PASS, no issues.
- `flutter build apk --debug` — PASS.
- APK inspection confirmed `AvacaNotoSansTC` in `FontManifest.json`, the
  11,942,912-byte TTF, and `OFL.txt`. The font compresses to 7,938,199 bytes in
  the debug APK.
- Targeted LCOV records the changed `AppTheme.fromPalette` and `_appTextStyle`
  paths as executed. `lib/core/config.dart` coverage is 150/192 lines (78.1%);
  all changed typography lines are covered, while the remaining uncovered
  baseline is unrelated palette-resolution logic.

## Known scope

This change is optimized for Traditional Chinese. The application also declares
Simplified Chinese localization, but locale-specific CJK font selection would
require a separate theme/localization design change. No Android device or
emulator was available for a final screenshot comparison.
