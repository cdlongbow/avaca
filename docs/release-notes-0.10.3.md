# AVACA 0.10.3

AVACA 0.10.3 is the Server ↔ Player remote-connection release.

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

## Validated release checks

- `flutter analyze --no-fatal-infos` passes with four informational lint
  notices only.
- The root Flutter suite passes 386 tests; the package/application matrix,
  architecture check, and focused native checks pass.
- Windows release builds pass for the root target, `apps/server`, and
  `apps/avaca`. The pinned Flutter engine, six player runtimes, required
  executables, and server no-player-runtime boundary pass bundle integrity
  verification.
- Android MsQuic native builds pass for `arm64-v8a` and `x86_64`. The tagged
  GitHub Actions workflow produces the signed `arm64-v8a` release APK and
  verifies its version metadata and checksum.

## Acceptance boundary

The following remain `WAIVABLE_ACCEPTANCE` follow-up evidence, not release
blockers: physical Server ↔ Player playback smoke, manual Windows/Android
action-level UI checks, Windows certificate-store validation, Android
physical-device validation, and Sol final review. Deterministic repository,
build, package, and integrity checks found no release-blocking defect.
