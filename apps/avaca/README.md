# AVACA

Windows and Android browsing/playback client. It consumes opaque IDs,
catalog records and short-lived playback descriptors from AVACA Server. It
does not import Server Library/scraper implementations or resolve Server
filesystem paths.

An authenticated client connection can be enabled after the first frame by
pasting an `AVACA-PAIR-V2.` invitation in the Servers page. The page previews
Server ID, endpoint and leaf SHA-256 pin before saving the profile. Windows
uses DPAPI and Android uses the native Keystore/AES-GCM store; revoke removes
the active profile. Discovery records remain candidate-only and never carry a
secret.

Windows also retains this environment-variable composition path for local
diagnostics:

```powershell
$env:AVACA_SERVER_HOST = '127.0.0.1'
$env:AVACA_SERVER_PORT = '4545'
$env:AVACA_SERVER_ID = 'server-local'
$env:AVACA_CLIENT_ID = 'client-local'
$env:AVACA_SERVER_CERT_SHA256_HEX = '<64 hex characters>'
$env:AVACA_PAIRING_SECRET_HEX = '<64 hex characters>'
```

The client rejects incomplete or malformed values and remains an offline
shell. A valid configuration starts the native transport asynchronously;
connection failure is shown as status text and does not block navigation or
the first frame. Windows playback uses the libmpv stream adapter; Android
playback uses the JNI MsQuic range adapter and Media3 `DataSource`. Neither
path accepts HTTP, SMB, a local Server path, or a full-file fallback.

```powershell
flutter pub get --suppress-analytics
flutter analyze --suppress-analytics
flutter test --suppress-analytics
flutter build windows --debug --suppress-analytics
flutter build apk --debug --suppress-analytics
```
