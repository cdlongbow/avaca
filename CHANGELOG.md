# Changelog

## 0.7.7 - 2026-08-10

- Added ZIP data export and import for actresses, works, details, and all
  managed images, with portable archive references and safe staging.
- Added duplicate-actress import resolution with work counts, avatar previews,
  and an in-app choice flow for keeping existing or imported details.
- Added the third Settings category for data transfer with localized,
  responsive controls consistent with the rest of the app.

## 0.7.5 - 2026-08-10

- Rebalanced responsive Detail and Edit layouts across compact and wide screens.
- Unified adaptive spacing and card geometry across Works, Work Detail,
  Settings, and Add while restoring the Home gallery's original card flow.
- Added CJK-aware adaptive UI Golden coverage and fixed the phone-landscape
  filter sheet overflow.
- Configured Android release signing and guarded plugin registration for
  current release builds.

## 0.7.3 - 2026-08-04

- Refined scrape settings into compact switch and count rows with consistent
  spacing, a collapsible excluded-prefix editor, and constrained-screen
  scrolling.
- Updated application text buttons to use the secondary text color while
  preserving emphasized button contrast colors.

## 0.7.2 - 2026-08-03

- Unified detail-page Edit and Delete actions under a localized overflow menu;
  edit mode now keeps only Save in the app bar, and Back cancels unsaved edits
  while restoring the persisted detail and photo state.
- Added theme-aware, content-sized Snackbar styling with configurable light,
  dark, and custom-palette backgrounds, and applied the shared presentation to
  detail and Works feedback.
- Hardened custom-theme preference loading against malformed JSON, unknown
  keys, and invalid color values.
- Aligned bundled-font tests with the current `w400` minimum application font
  weight.

## 0.7.0 - 2026-08-03

- Added actress alias management with multiple aliases per actress and
  case-insensitive alias normalization.
- Scraping now checks the canonical actress name and every saved alias,
  retries shared sources after transient failures, and deduplicates works by
  source and normalized work code.
- Added long-press multi-selection on the Works page and global work deletion
  with transactional actress-link removal and managed-image cleanup that
  preserves shared files.

## 0.6.10 - 2026-08-03

- Added JavBus scraping for actress profiles and works, including localized
  scrape controls, a configurable multi-actress threshold, and exact-name
  merging across duplicate actress pages.
- Added duplicate work-code filtering and normalization for trailing `-V`,
  `-T`, and `-VT` suffixes so variants such as STARS codes resolve correctly.
- Added safe work-image fallback attempts in the approved order: original,
  leading `1`, leading `1` with trailing `v`, and trailing `h2`, while
  rejecting placeholder images and unsafe URLs.
- Added actress avatar session/Referer handling, work detail image display,
  cleanup and database migration improvements, birthday persistence, and
  related UI/localization updates.
- Preserved the existing typography adjustments, including the manually
  selected `w400` minimum font weight.

## 0.5.7 - 2026-07-29

- Added compact, immediately applied filtering with created, modified, and
  actress-age sorting.
- Added birthday persistence, age display, and a three-wheel birthday picker
  to the detailed profile editor.
- Refined detail-page spacing, controls, tags, photo actions, and responsive
  layouts to match the rest of the app.
- Prevented the keyboard from unexpectedly reopening after physical back
  navigation.

## 0.5.2 - 2026-07-29

- Reworked settings into categorized, expandable pages with independent custom
  colors, dark-only AMOLED controls, and localized touch feedback.
- Improved responsive gallery spacing, profile layout, and Works navigation.
- Added bundled Traditional Chinese typography and broader widget coverage.
