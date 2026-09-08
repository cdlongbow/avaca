# AVACA 0.10.3

AVACA 0.10.3 is the Server ↔ Player remote-connection implementation
candidate.

## Highlights

- Adds the separated Windows-only AVACA Server and Windows/Android AVACA
  client entry points.
- Adds protocol v2 HMAC authentication with TLS-exporter channel binding,
  opaque resource descriptors, playback grants, client ownership checks,
  expiry, revoke, and cancellable range reads.
- Keeps control traffic in a Dart session while native libmpv/Media3 playback
  uses a second session with the same client identity and a retained native
  lease.
- Adds Windows libmpv and Android Media3 native range adapters over the shared
  MsQuic remote core.
- Adds QR/paste invitations, certificate pin display, secure profile storage
  boundaries, revoke/re-pair, and `_avaca-remote._udp` DNS-SD discovery.

## Validation status

- Dart analysis and focused package/application tests pass.
- Windows Server and AVACA debug builds pass.
- Android arm64-v8a and x86_64 native MsQuic builds pass.
- Physical Windows/Android end-to-end playback, action-level UI evidence,
  Windows certificate-store validation, and Android-device validation remain
  blocked by the current environment. This candidate must not be represented
  as a completed public release until those gates close.
