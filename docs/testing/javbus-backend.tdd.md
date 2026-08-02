# JavBus works scraper TDD evidence

## Source and journeys

The journeys were derived from the user-approved second implementation plan.

- A user can store each scraped work once and associate it with an actress.
- A repeat scrape can fill missing data without overwriting stored values.
- A user can exclude any nonempty, potentially complex code prefix without
  case-sensitive mismatches.
- Actress and work HTML can be parsed without live network access in tests.
- Work images are downloaded from DMM or MGStage, with the documented DMM
  placeholder fallback.

## RED and GREEN

| Behavior | RED evidence | GREEN evidence |
|---|---|---|
| New database, parser, prefix, and image contracts | `dart analyze test\core\work_database_test.dart test\services\javbus` reported missing production URIs and APIs | Focused Flutter test run completed with 32 passing tests |
| Actress profile field boundaries | Focused Flutter test run executed the parser test and returned `Actual: '1997-12-03身高: 160cm罩杯: D'` | The same test target passed after parsing each profile paragraph separately |
| Regression and coverage | Not applicable | `flutter test --coverage test\core\work_database_test.dart test\core\database_birth_date_sort_test.dart test\services\javbus` returned `All tests passed!` |

The Flutter commands were executed through
`C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe
C:\src\flutter\packages\flutter_tools\bin\flutter_tools.dart` because the
ordinary batch launcher waited on a shared Flutter tool lock.

## Test specification

| # | Guarantee | Test target | Type | Result |
|---|---|---|---|---|
| 1 | Work codes and actress links are unique without case sensitivity | `test/core/work_database_test.dart` | SQLite integration | PASS |
| 2 | Missing-only updates fill blanks and do not clear or replace stored data | `test/core/work_database_test.dart` | SQLite integration | PASS |
| 3 | Actress sync never changes weight and only changes an image when explicitly allowed | `test/core/work_database_test.dart` | SQLite integration | PASS |
| 4 | Prefixes display uppercase, accept mixed characters, and match case-insensitively | `test/services/javbus/prefix_exclusion_test.dart` | Unit | PASS |
| 5 | Actress, search, pagination, work summary, and selected detail fields parse from local HTML | `test/services/javbus/javbus_html_parser_test.dart` | Unit | PASS |
| 6 | All actress pages are fetched, excluded codes are skipped, and duplicate codes are removed | `test/services/javbus/javbus_client_test.dart` | Service integration with fake transport | PASS |
| 7 | DMM and MGStage URLs follow the approved naming rules | `test/services/javbus/work_image_downloader_test.dart` | Unit | PASS |
| 8 | A DMM 90x122 placeholder triggers the leading-`1` fallback, while MGStage never guesses DMM | `test/services/javbus/work_image_downloader_test.dart` | Service integration with fake transport | PASS |
| 9 | Downloaded image bytes are written to the requested local path | `test/services/javbus/work_image_downloader_test.dart` | File integration | PASS |
| 10 | JavBus HTTP requests retry only a bounded number of transient failures | `test/services/javbus/javbus_client_test.dart` | Service integration with fake HTTP | PASS |
| 11 | The works page uses a three-column mobile grid and opens local work details | `test/views/works_feature_test.dart` | Widget integration | PASS |
| 12 | Scrape settings preserve complex uppercase prefixes and forward every option | `test/views/works_feature_test.dart` | Widget integration | PASS |
| 13 | System Back cannot dismiss the active progress dialog or pop the Works page | `test/views/works_feature_test.dart` | Widget regression | PASS |
| 14 | HTTPS, host allowlists, redirects, response-size caps, and an absolute deadline are enforced | `test/services/http_safety_test.dart` | Security unit/integration | PASS |
| 15 | Unbounded pagination and off-origin JavBus navigation are rejected | `test/services/javbus/javbus_client_test.dart` | Security integration | PASS |
| 16 | Oversized image dimensions are rejected before frame decoding | `test/services/javbus/work_image_downloader_test.dart` | Security unit | PASS |
| 17 | Invalid scraped birthdays do not suppress valid fields and FK cascades remove actress-work links | `test/core/work_database_test.dart` | SQLite integration | PASS |
| 18 | A JavBus 302 driver-verification challenge includes the clicked `<button>` field (`submit=question`), completes manually, and retries the original request in the same cookie session | `test/services/javbus/javbus_client_test.dart` | Service integration with fake HTTP | PASS |
| 19 | JavBus's current `#form1` age confirmation posts its submit field back to the verification URI in the same cookie session | `test/services/javbus/javbus_client_test.dart` | Service integration with fake HTTP | PASS |
| 20 | Current JavBus actress results using `a.avatar-box` are parsed without including the nested category button text | `test/services/javbus/javbus_html_parser_test.dart` | Unit regression | PASS |

## Coverage and checks

- Final complete suite: **112 tests passed**.
- Feature files: 727 of 849 lines hit, **85.63%**.
- Repository-wide coverage is 65.29%; this includes pre-existing application
  code outside this feature.
- Final static analysis: `No issues found!`
- Independent code review: **PASS**.
- Independent security/reliability review: **PARTIAL**. The scraper defect is
  fixed, while broader pre-existing cookie scoping, plaintext persistence, and
  form-hardening recommendations remain documented follow-up work.
- Independent verifier: **PARTIAL** only because the security review remains
  partial; it found no evidence that the verification or live scraping defects
  remain.
- Chrome inspection confirmed that the live actress image is a relative
  `/pics/actress/uly_a.jpg` URL on the allowed `www.javbus.com` origin and
  that live work headings begin with the code, which the parser removes.
- No live scraping result was persisted to the local database. Automated HTTP
  and HTML tests use local strings or fake transports; the read-only live
  checks below exercised the current public pages without saving their data.
- JavBus verification cookies remain inside the app-managed HTTP session. The
  app supports both the dynamic driver-question form and the current `#form1`
  age confirmation, asks the user to confirm in a modal dialog, posts the
  required form fields, persists the resulting cookie header, and retries the
  original request without reading browser cookies.
- A live anonymous-session verification confirmed that including JavBus's
  `<button name="submit" value="question">` field causes correct answers to
  return the real `/star/uly` actress search result. Omitting that field
  reproduced the server replacing the questions instead of allowing access.
- Live verified-page inspection showed that actress search results now use
  `a.avatar-box text-center`, not the fixture's former `a.star-box`. A live
  anonymous run with the corrected parser found `/star/uly`, parsed 30 works
  from the first page, and successfully fetched and parsed the first 10 work
  detail pages.
- Git checkpoint commits were intentionally omitted because the task explicitly
  prohibited commits.
