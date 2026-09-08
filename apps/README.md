# AVACA application split

| application | platforms | authority |
|---|---|---|
| `apps/server` | Windows only | Library, scraper, catalog, playback grants, QUIC listener |
| `apps/avaca` | Windows + Android | browsing, detail, player UI, QUIC client |

Both compositions require `avaca_protocol` v2.  The old root Flutter target is
kept as a migration fixture only; it is not imported by either production app.

## Local verification

```powershell
cd apps/server
flutter pub get --suppress-analytics
flutter analyze --suppress-analytics
flutter test --suppress-analytics
flutter build windows --debug --suppress-analytics

cd ../avaca
flutter pub get --suppress-analytics
flutter analyze --suppress-analytics
flutter test --suppress-analytics
flutter build windows --debug --suppress-analytics
flutter build apk --debug --suppress-analytics
```

The MsQuic bridge is opt-in at CMake configure time.  Configure it only with
the exact source/runtime paths produced by `tooling/msquic/provision_windows.ps1`;
there is no plaintext or PATH-selected fallback.
