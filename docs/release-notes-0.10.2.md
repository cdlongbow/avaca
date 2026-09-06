# AVACA 0.10.2

AVACA 0.10.2 restores the Library around real imported media.

## Highlights

- Restores the Library workflow from folder import and scan through item
  selection, review, primary-performer confirmation, and commit.
- Keeps normal Collection entries tied to real, locatable imported media
  instead of metadata-only Work records.
- Adds portable media identity and media-location resolution for imported
  Library items.
- Improves Collection, detail, import, and Works integration around the
  recovered Library flow.
- Adds the Android storage/media access integration required by the import
  journey.
- Adds focused automated coverage for the Library recovery paths.
- Windows bundles the pinned Flutter 3.44.8 engine with the validated ANGLE
  DirectComposition surface path so the supported Windows setup renders the
  application instead of a white client area.

## Upgrade notes

- The database remains on schema version 2.
- Existing local data is expected to remain compatible; release validation must
  pass the existing database migration and Library compatibility tests before
  publication.

## Packages

The GitHub Release publishes:

- `avaca-0.10.2-arm64-v8a.apk`
- `avaca-0.10.2-arm64-v8a.apk.sha256`
- `avaca-0.10.2.zip`
- `avaca-0.10.2.zip.sha256`

The Android package is ARM64. The Windows ZIP must contain the application,
updater, Flutter runtime/data bundle, README, and `version.txt`.
