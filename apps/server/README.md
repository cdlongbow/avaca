# AVACA Server

Windows-only management and media-service runtime. It owns the authoritative
Library, scraper/catalog adapters, physical media paths, playback grants and
the QUIC listener. It does not depend on `avaca_player_native` or any video
rendering infrastructure.

The management shell is rendered first and the SQLite catalog is opened
asynchronously after the first frame. If `AVACA_SERVER_DB` is omitted, the
Server uses `%LOCALAPPDATA%\AVACA\server.sqlite`; the path is never exposed to
the Player. This keeps the Windows window responsive while a new or large
catalog is being opened.

The authenticated Windows listener is prepared automatically after the first
frame. The Server selects an available private-key certificate, a usable LAN
IPv4 address, and a free application port. If the current user's
`CurrentUser\My` store has no usable certificate, the Windows runner creates a
self-signed RSA certificate named `AVACA Server QUIC` and keeps its
non-exportable private key in that store. The user does not upload or choose a
certificate file. The phone receives only the certificate's SHA-256 pin inside
the one-time QR; the certificate and private key stay on Windows.

The Server also generates the process bootstrap secret in memory; it is never
shown or written to catalog data. Environment values remain available for
controlled deployments and override the automatic values:

```powershell
$env:AVACA_SERVER_DB = 'D:\AVACA\server.sqlite'
$env:AVACA_SERVER_ID = 'server-local'
$env:AVACA_SERVER_PORT = '4545'
$env:AVACA_SERVER_CERT_SHA1_HEX = '<40 hex characters>'
$env:AVACA_PAIRING_SECRET_HEX = '<at least 64 hex characters>'
$env:AVACA_EXPECTED_CLIENT_ID = 'client-local' # optional
```

The certificate value is the 20-byte SHA-1 thumbprint used by the Windows
transport; it is only needed for controlled deployments. The pairing secret is
never displayed or written to catalog data.
If the values are incomplete, malformed, or the adjacent MsQuic/AVACA native
transport DLLs are unavailable, the shell and local catalog remain usable and
the pairing card reports a readable listener error instead of blocking startup.
The listener still requires a real Server-owned catalog repository and playback
resolver.

When the listener is ready, the pairing panel exposes one `開始配對` action. It
automatically creates a one-time ten-minute `AVACA-PAIR-V2.` QR/code for a new
Player identity. The invitation secret is held only by the in-memory pairing
authority until the first successful HMAC authentication; it is not written to
the catalog or diagnostics.

The management shell includes a Server-owned HTTPS scraper composition for
AV-Wiki, AVBase, and JavBus. The import panel scans a Windows folder
asynchronously, reports scan/resolve/index timings, enforces a file bound, and
supports cancellation at item boundaries. The v2 catalog migration is
additive: existing Server rows survive, while `server_library_roots`, physical
inventory, review state, performers, metadata state, and opaque artwork assets
are added alongside them.

Physical inventory is authoritative and independent from metadata. A missing
filename code, ambiguous variant, scraper timeout, or blocked provider keeps
the file in the Server catalog and places it in the local review panel instead
of dropping it. The Server UI supports folder picking, manual code correction,
and a rescan/retry workflow. No client-facing response contains an imported
physical path, source URL, or SQL key; artwork is served only through the
bounded v2 `openAsset` range contract.

```powershell
flutter pub get --suppress-analytics
flutter analyze --suppress-analytics
flutter test --suppress-analytics
flutter build windows --debug --suppress-analytics
```
