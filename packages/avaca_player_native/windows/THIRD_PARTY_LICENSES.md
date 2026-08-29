# AVACA Windows player license gate

This file is an acceptance checklist, not a claim that the current local
spike artifacts are release-cleared.

The Windows player has two external dependency families:

- libmpv and its enabled media stack, including FFmpeg, libass, Fribidi,
  zlib, and any other libraries included by the exact build;
- ANGLE and its runtime dependencies, including the D3D11/EGL/GLES runtime
  and any shader/compiler or Vulkan support DLLs shipped beside it.

The exact 20241021 libmpv binary's transitive license closure and build
configuration have not been independently established in this checkout.  An
older planning recipe mentioned `-Dgpl=false`, but that setting and its older
FFmpeg revision must not be attributed to the 20241021 binary without direct
build evidence.

Before release packaging, replace this checklist with or attach a complete
machine-readable and human-readable inventory containing:

- each shipped DLL and development header/library;
- its upstream project, version, source revision, and build flags;
- the applicable license and the exact NOTICE text required by that license;
- whether the selected libmpv build is LGPL-compatible for AVACA's intended
  distribution; and
- hashes tying the inventory to the files in the release bundle.

Until that inventory and the artifact hashes are present, the Windows player
backend remains implementation-complete but packaging-blocked.
