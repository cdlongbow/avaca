# JavBus duplicate actress, actress limit, and avatar replacement TDD evidence

## Source and approved journeys

The source plan was approved in the current Codex task; no external plan file was used.

- As a user, I can scrape an actress whose exact JavBus name has multiple result pages, so all matching pages contribute works without duplicate codes.
- As a user, I can leave the actress-count limit blank or enter a positive integer, so works above that limit are excluded and unknown counts fail safely.
- As a user, I can replace an actress avatar from a valid duplicate page, so the authenticated JavBus session is reused and the previous image remains when replacement fails.
- Photo and gravure works remain unfiltered.

## RED and GREEN report

| Task | RED evidence | GREEN evidence | Guarantee |
|---|---|---|---|
| Persist `maxActressCount` | Focused suite failed to compile because `WorkScrapeOptions.maxActressCount` did not exist | `flutter test test/models/work_scrape_options_test.dart ...` passed | Blank/invalid persisted values are unlimited; positive integers round-trip |
| Parse work actresses | Focused suite failed to compile because `JavBusWorkDetails.actressUris` did not exist | Focused suite passed | Only unique `/star/` links in the actress section are counted |
| Merge duplicate actress pages | Service tests failed to compile against the old ambiguous-name flow | Focused suite passed | Exact-name pages are merged and normalized work codes are globally deduplicated |
| Enforce actress limit | Service/UI tests failed because the option and filtering behavior did not exist | Focused suite passed | More than N is excluded; an unknown count is recorded as failed |
| Share authenticated avatar session | Client/service tests failed because `getBinary`, `JavBusBinarySession`, and authenticated downloader injection did not exist | Focused suite passed | Avatar bytes use the live JavBus cookie session and retain image safety checks |
| Report avatar replacement outcome | Tests failed because `ActressImageSyncStatus` and the warning UI did not exist | Focused suite passed | Unavailable/download/database failures do not silently look like replacement success |
| Reject decimal limits | Widget test failed because `1.5` was transformed into `15` by digits-only formatting | The same named widget test passed after validator-based rejection | Decimal input remains invalid instead of being silently changed |

## Commands and results

- Baseline before test changes:
  - `flutter test test/models/work_scrape_options_test.dart` — 3 passed.
  - `flutter test test/services/javbus/javbus_html_parser_test.dart test/services/works_scrape_service_test.dart test/views/works_feature_test.dart` — 12 passed.
- RED:
  - `flutter test test/models/work_scrape_options_test.dart test/services/javbus/javbus_html_parser_test.dart test/services/javbus/javbus_client_test.dart test/services/works_scrape_service_test.dart test/views/works_feature_test.dart --reporter expanded` — failed for the intended missing contracts and behavior.
  - `flutter test test/views/works_feature_test.dart --plain-name "actress-count limit rejects decimal input" --reporter expanded` — failed because no validation error was shown.
- GREEN:
  - The five-file focused command with `--coverage --reporter compact` — 35 tests passed.
  - `flutter analyze` — no issues found.
  - `git diff --check` — no whitespace errors; only repository line-ending warnings.

## Coverage

Focused LCOV for the six changed non-generated production files reports 640 hit lines out of 778, or 82.3% combined coverage.

| File | Coverage |
|---|---:|
| `lib/models/work_scrape_options.dart` | 100.0% |
| `lib/services/javbus/javbus_html_parser.dart` | 95.7% |
| `lib/services/javbus/javbus_models.dart` | 100.0% |
| `lib/services/javbus/javbus_client.dart` | 86.7% |
| `lib/services/works_scrape_service.dart` | 79.5% |
| `lib/views/works_view.dart` | 75.2% |

## Known gaps and merge evidence

- A full-suite attempt was not accepted as PASS. After an initial runner timeout, the unrelated `test/core/app_theme_font_test.dart:128` failed because it expects `FontWeight.w300` while the application intentionally uses `w400`. The user confirmed that the weight and font-size changes are intentional and must not be reverted.
- Live JavBus behavior remains dependent on the site HTML and Cloudflare session, but all external calls in automated tests use fakes or `MockClient`.
- No checkpoint commit was created because project Gate 2 requires separate user authorization. RED/GREEN evidence is preserved in this report.

## Follow-up: START cover fallback and avatar Referer

The user approved two bounded defect fixes: keep DMM URL derivation and add `1…v` as the third candidate after the original and leading-`1` candidates; send a same-origin JavBus Referer for authenticated binary image requests.

| Guarantee | RED evidence | GREEN evidence |
|---|---|---|
| DMM attempts `original → 1… → 1…v` and returns the third valid image | `DMM retries with a leading one and trailing v as the third candidate` failed after the second candidate with `WorkImageDownloadException` | The same test passed and asserted all three requested URLs in order |
| JavBus avatar downloads carry the verified cookie and `Referer: https://www.javbus.com/` | `binary requests reuse cookies from the verified JavBus session` failed because the Referer was `null` | The same test passed with both cookie and Referer assertions |
| A caller cannot use the Referer option to name a host outside the existing allowlist | Added security regression test verifies rejection before the HTTP client sends a request | `rejects a non-allowlisted referer before sending` passed |

Validation evidence:

- RED focused run: 18 tests executed, with exactly the two intended regression failures.
- GREEN focused run: 20 tests passed.
- Related coverage run: 39 tests passed across HTTP safety, JavBus client/image policy, scrape service, and works UI.
- Post-review focused run including the Referer allowlist test: 25 tests passed.
- `flutter analyze`: no issues found.
- Combined line coverage for the four changed production files: 241/289, or 83.4%.
- Live HTTP diagnosis: the 125×125 actress JPEG returned HTTP 403 without a Referer and HTTP 200 with either the actress-page or JavBus-origin Referer. The four reported START works returned 90×122 placeholders for the first two candidates and valid 1700–2184px images for `1…v`.
- No commit was created; Gate 2 remains pending user authorization.

## Follow-up: DMM h2 fourth fallback

The user approved adding `1<code>h2` as the fourth DMM candidate for work images, after the original, `1<code>`, and `1<code>v` candidates. No actress-avatar change was made because the user confirmed the source has no usable avatar.

| Guarantee | RED evidence | GREEN evidence |
|---|---|---|
| `STARS-685` builds card/detail URLs under `1stars00685h2` | Policy test failed because `dmmTrailingH2` did not exist | Policy test passed with the expected `ps` and `pl` URLs |
| Downloader tries h2 only after the first three candidates fail | Fourth-candidate test failed to compile before the policy option existed | Fourth-candidate test passed and asserted all four requests in order |
| A valid third `v` candidate short-circuits before h2 | Existing third-candidate test would fail if a fourth request were made | Existing third-candidate test passed with its three-request fake transport |
| All-invalid DMM failures include the fourth candidate | Existing invalid-attempt test expected only three requests | Updated test passed with four requests and the h2 failure URI |

Validation evidence:

- RED focused run: compilation failed only because `dmmTrailingH2` was not yet implemented.
- GREEN h2 focused run: 13 tests passed.
- Related coverage run after the fix: 50 tests passed.
- `flutter analyze`: no issues found.
- Combined line coverage for `work_image_policy.dart` and `work_image_downloader.dart`: 77/91, or 84.6%.
- No commit was created; Gate 2 remains pending user authorization.

## Follow-up: STARS edition suffix normalization

The user approved treating trailing `-V`, `-T`, and `-VT` edition markers as the same base work code during JavBus parsing, deduplication, and image URL generation.

| Guarantee | RED evidence | GREEN evidence |
|---|---|---|
| Actress cards and detail pages normalize the three edition suffixes | Parser regression test returned `STARS-859-V`, `STARS-757-T`, and `STARS-715-VT` instead of their base codes | The same parser test passed and also verified that the title does not retain the removed suffix |
| Edition entries deduplicate against base entries | Client regression test returned six entries instead of three | The same client test passed with only `STARS-859`, `STARS-757`, and `STARS-715` |
| DMM image URLs ignore the edition suffix | Image-policy regression test threw `FormatException` for `STARS-859-V` | The same test passed for `-V`, `-T`, and `-VT` |

Validation evidence:

- RED focused run: 25 tests executed with exactly the three intended failures.
- GREEN focused run: 28 tests passed.
- Post-review focused run: 28 tests passed after adding boundary assertions that `STARS-859-VR` and `FC2-PPV_123-999` remain unchanged.
- Related coverage run: 48 tests passed across HTTP safety, parser, client, image policy/downloader, scrape service, and works UI.
- `flutter analyze`: no issues found.
- Combined line coverage for the three production files in this follow-up: 142/148, or 95.9%.
- Live diagnosis found that `STARS-685` is a separate issue: all three current DMM candidates return 90×122 placeholders, while the valid card/detail assets use product code `1stars00685h2` and measure 1537×2184 / 2184×1542. No `h2` fallback was added in this follow-up.
- No commit was created; Gate 2 remains pending user authorization.
