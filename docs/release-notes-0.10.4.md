# AVACA 0.10.4

AVACA 0.10.4 repairs AVACA pairing and publishes the Windows client and
Windows Server as separate portable products.

## Highlights

- Builds the Android AVACA client from `apps/avaca` instead of the root
  migration fixture.
- Resolves LAN discovery candidates only when the invitation's Server ID,
  port, and certificate pin match exactly; the invitation remains the only
  source of the pairing secret and trust material.
- Selects usable private IPv4 addresses on Windows Server and exposes
  multiple network interfaces without overwriting a manually entered host.
- Fixes Windows DNS-SD registration and browsing with complete `.local`
  service names and correct asynchronous pending-status handling.
- Publishes separate Windows AVACA client and AVACA Server ZIPs with pinned
  MsQuic runtime provenance and role-specific bundle checks.

## Assets

- `avaca-0.10.4-arm64-v8a.apk`
- `avaca-0.10.4.zip`
- `avaca-server-0.10.4.zip`
- One `.sha256` sidecar for each asset.

## Validation boundary

Repository tests, app analysis, architecture checks, Windows release builds,
role-specific bundle checks, Windows DNS-SD registration/browse, and the
separate-process native MsQuic path were verified before publication.

Physical Android↔Windows LAN testing and action-level Windows/Android UI
evidence depend on devices and UI surfaces unavailable in the release
environment; they are not represented as passed here.
