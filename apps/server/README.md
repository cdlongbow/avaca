# AVACA Server

Windows-only management and media-service runtime. It owns the authoritative
Library, scraper/catalog adapters, physical media paths, playback grants and
the QUIC listener. It does not depend on `avaca_player_native` or any video
rendering infrastructure.

When `AVACA_SERVER_DB` is set, the management shell is rendered first and the
SQLite catalog is opened asynchronously after the first frame. This keeps the
Windows window responsive while a new or large catalog is being opened.

The real Windows listener is opt-in and is also started after the first frame.
Set all required values below in the process environment to enable the
authenticated protocol-v2 listener:

```powershell
$env:AVACA_SERVER_DB = 'D:\AVACA\server.sqlite'
$env:AVACA_SERVER_ID = 'server-local'
$env:AVACA_SERVER_PORT = '4545'
$env:AVACA_SERVER_CERT_SHA1_HEX = '<40 hex characters>'
$env:AVACA_PAIRING_SECRET_HEX = '<at least 64 hex characters>'
$env:AVACA_EXPECTED_CLIENT_ID = 'client-local' # optional
```

The certificate value is the 20-byte SHA-1 thumbprint used by the Windows
transport; the pairing secret is never displayed or written to catalog data.
If the values are incomplete, malformed, or the adjacent MsQuic/AVACA native
transport DLLs are unavailable, the shell stays usable and reports a listener
error instead of blocking startup. The listener still requires a real
Server-owned catalog repository and playback resolver.

When the listener is ready, the pairing panel can enumerate the Windows
CurrentUser\My certificate store, display the selected leaf SHA-256 pin, and
render a one-time ten-minute `AVACA-PAIR-V2.` QR/code. The invitation secret is
held only by the in-memory pairing authority until the first successful HMAC
authentication; it is not written to the catalog or diagnostics.

The management shell accepts an injected `AvacaScraper` composition. Once a
real Server-owned source is supplied, the import panel scans a Windows folder
asynchronously, reports scan/resolve/index timings, enforces a file bound, and
supports cancellation at item boundaries. No client-facing response contains
the imported physical paths. With no scraper source injected, import remains
explicitly disabled instead of using placeholder metadata.

```powershell
flutter pub get --suppress-analytics
flutter analyze --suppress-analytics
flutter test --suppress-analytics
flutter build windows --debug --suppress-analytics
```
