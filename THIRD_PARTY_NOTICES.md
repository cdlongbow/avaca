# AVACA third-party notices

The Windows portable release includes a pinned Flutter/ANGLE rendering stack
and a pinned LGPL libmpv runtime. The exact files and SHA-256 values are
recorded in [`packages/avaca_player_native/windows/THIRD_PARTY_PROVENANCE.md`](packages/avaca_player_native/windows/THIRD_PARTY_PROVENANCE.md),
and the Windows package contains this notice together with that provenance
record.

## libmpv

- Project: mpv, built by [`zhongfly/mpv-winbuild`](https://github.com/zhongfly/mpv-winbuild)
- Release: `2026-08-27-182fa6ca49`
- Source commit: `182fa6ca49f455cadb884858f386e2f00540aeb7`
- mpv version string: `0.41.0-1011-g182fa6ca4`
- FFmpeg source commit: `278eeeb16e67f24d46851e3355bef5a51322c3bd`
- Build mode: `-Dgpl=false`, `-Dcplayer=false`, `libmpv=YES`
- Asset: [`mpv-dev-lgpl-x86_64-20260827-git-182fa6ca49.7z`](https://github.com/zhongfly/mpv-winbuild/releases/download/2026-08-27-182fa6ca49/mpv-dev-lgpl-x86_64-20260827-git-182fa6ca49.7z)
- Archive SHA-256: `16CD542F7386BF1E68339B90618FE5446171FA555DAA0C6D07D59BE43BB903EA`
- `libmpv-2.dll` SHA-256: `63FED593A9E1B3C7E170BB38FCDF73722FA3D73B7C068F303BF2985EEEC75367`

The selected upstream build log identifies FFmpeg as LGPL version 3 or later.
The libmpv/media-stack source notices and license texts supplied by the
upstream archive are authoritative for the transitive components enabled by
that build. In particular, retain the corresponding mpv, FFmpeg, libass,
FriBidi, zlib, and other enabled-component notices when redistributing the
binary. The machine-readable dependency lock is shipped in the source tree at
`packages/avaca_player_native/windows/WINDOWS_PLAYER_DEPS.lock.json` and the
release workflow verifies the six runtime hashes before packaging.

## Flutter Engine and ANGLE

AVACA uses a pinned Flutter 3.44.8 Windows engine build with an ANGLE
DirectComposition patch. Flutter Engine, ANGLE, and SwiftShader remain under
their upstream license terms. The shipped runtime hashes and source/build
provenance are recorded in the adjacent provenance document.

## Windows runtime components

`d3dcompiler_47.dll` and `vulkan-1.dll` are Windows runtime components used by
the pinned graphics stack. Their redistribution and notice requirements are
governed by the applicable Microsoft terms. AVACA does not replace or modify
their license terms.

This notice is an inventory and provenance record, not legal advice.
