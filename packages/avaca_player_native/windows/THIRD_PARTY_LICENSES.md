# AVACA Windows player license inventory

This inventory is shipped with the Windows portable archive as
`THIRD_PARTY_NOTICES.md`. It identifies the exact binary provenance and the
license mode selected by the upstream build. It is not legal advice; release
owners must retain the upstream license texts and satisfy the obligations of
the licenses listed here.

## libmpv and media stack

The shipped `libmpv-2.dll` is the `2026-08-27-182fa6ca49` LGPL development
asset from `zhongfly/mpv-winbuild`. Its source commit is
`182fa6ca49f455cadb884858f386e2f00540aeb7`, and its extracted DLL SHA-256 is
`63FED593A9E1B3C7E170BB38FCDF73722FA3D73B7C068F303BF2985EEEC75367`.

The upstream LGPL workflow records `-Dgpl=false`, `-Dcplayer=false`,
`-Dprefer_static=true`, `-Degl-angle=enabled`, `-Dvulkan=enabled`, and
`libmpv=YES`. Its FFmpeg configure log identifies FFmpeg as “LGPL version 3
or later”, and the exact FFmpeg revision is recorded in
`WINDOWS_PLAYER_DEPS.lock.json`. The enabled media stack includes FFmpeg,
libass 0.17.5, FriBidi 1.0.16, libplacebo 7.371.0, zlib-ng, shaderc, and
other libraries selected by that exact build; the lock file records the
direct linked components and their upstream license sources. The upstream
archive/source notices remain authoritative for each component's individual
license text and attribution requirements.

## Flutter/ANGLE runtime

`libEGL.dll` and `libGLESv2.dll` are from the pinned Flutter 3.44.8 engine
build used by AVACA. `d3dcompiler_47.dll`, `vk_swiftshader.dll`, and
`vulkan-1.dll` are shipped adjacent runtime files captured with that build.
The source-level license files for Flutter Engine, ANGLE, and SwiftShader are
kept in their upstream source trees; Windows system components are not copied
from AVACA source and remain governed by their Microsoft distribution terms.

The exact shipped-file hashes are recorded in
`THIRD_PARTY_PROVENANCE.md` and checked by `.github/workflows/release.yml`.
The release archive also includes this inventory so users can identify the
runtime closure that was packaged.

## No substitution rule

The diagnostic spike binary and the old 20241021 planning candidate are not
release inputs. A missing or hash-mismatched runtime is a packaging failure;
the build must not silently substitute a system renderer or an ambient DLL.
