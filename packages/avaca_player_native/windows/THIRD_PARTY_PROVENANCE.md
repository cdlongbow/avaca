# AVACA Windows player dependency provenance

The Windows player is an AVACA-owned plugin. It loads the pinned runtime
closure from the executable directory with deterministic full-path loading.
No ambient `PATH` entry, WGL interop path, or CPU pixel-buffer fallback is
accepted.

## Pinned libmpv artifact

The shipped `libmpv-2.dll` comes from the official LGPL development archive
published by the `zhongfly/mpv-winbuild` project:

- release: `2026-08-27-182fa6ca49`
- source commit: `182fa6ca49f455cadb884858f386e2f00540aeb7`
- asset: [`mpv-dev-lgpl-x86_64-20260827-git-182fa6ca49.7z`](https://github.com/zhongfly/mpv-winbuild/releases/download/2026-08-27-182fa6ca49/mpv-dev-lgpl-x86_64-20260827-git-182fa6ca49.7z)
- archive SHA-256: `16CD542F7386BF1E68339B90618FE5446171FA555DAA0C6D07D59BE43BB903EA`
- extracted `libmpv-2.dll` SHA-256: `63FED593A9E1B3C7E170BB38FCDF73722FA3D73B7C068F303BF2985EEEC75367`
- embedded mpv version string: `0.41.0-1011-g182fa6ca4`
- FFmpeg source commit: `278eeeb16e67f24d46851e3355bef5a51322c3bd`
- build workflow commit: `014d5c77bf68afc924ff6f4f4a69776a8dbafeab`
- GitHub Actions provenance run: `33069943766`, LGPL log artifact
  `64-lgpl_logs` (artifact SHA-256
  `aa43e0662dfead6f0d8d7660fd6078407def297384aaaecdb765be92302f3d0d`)

The machine-readable lock is
[`WINDOWS_PLAYER_DEPS.lock.json`](WINDOWS_PLAYER_DEPS.lock.json). The
captured configure logs record the exact mpv/FFmpeg options and dependency
versions; the release candidate also runs `llvm-readobj --coff-imports` over
the produced `libmpv-2.dll`. Its only non-system import is `vulkan-1.dll`;
the media libraries are statically linked into libmpv.

The upstream build log records `libmpv=YES`, `gpl=false`, `cplayer=false`,
`prefer_static=true`, `egl-angle=enabled`, and `vulkan=YES`. AVACA's fetch
script verifies both the archive and extracted DLL hashes before copying the
DLL into `windows/engine`.

## Pinned adjacent graphics/runtime files

These files are shipped beside `avaca.exe` and are installed from the pinned
engine directory. The Windows release workflow verifies each hash:

| file | SHA-256 |
| --- | --- |
| `libEGL.dll` | `3562C97F80C4EE79E9CD19881981A6C4BD69E26D04A9B0D88B54DDBFA334F58B` |
| `libGLESv2.dll` | `2B43130299CAD2156D20BBE5C2DBA3E6FF079A4F38E96D834FCDFDD3D68F4332` |
| `d3dcompiler_47.dll` | `E407B9FFADEF47E87994DC488214F75405CF04EE99589F2315FC7AB99FD1DFE2` |
| `vk_swiftshader.dll` | `329912B23F6DD001981E3C18CF0F99B7E41F99F8B36EEAF629B1E3D298DFBF10` |
| `vulkan-1.dll` | `14323F145642B0C16DD2354A1158D823DE9EF5CB14FBB75AA3971A6E5FD42A0F` |

The two ANGLE binaries were built from the pinned Flutter 3.44.8 engine
checkout and its recorded ANGLE DEPS revision. `d3dcompiler_47.dll` and
`vulkan-1.dll` are the corresponding Windows runtime files captured with that
engine build; their hashes are part of the release verification contract.

## Scope and remaining runtime gate

Strict CMake configuration now fails when any of the six lock-listed adjacent
files is missing, and the top-level Windows install step places all six files
beside `avaca.exe` in a clean portable bundle. The native diagnostics report
the absolute executable-directory paths actually loaded for `libmpv-2.dll`,
`libEGL.dll`, and `libGLESv2.dll`, together with `renderer=D3D11`,
`dartFrameCopy=none`, `cpuReadback=false`, and `softwareFallback=false`.
This does not by itself claim that a real media file has rendered
successfully: the release gate still requires a fresh-extraction player action
log.
