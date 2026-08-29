# AVACA Windows player dependency provenance

The Windows player is an AVACA-owned plugin.  It loads `libmpv-2.dll`,
`libEGL.dll`, and `libGLESv2.dll` only from the executable directory with
deterministic full-path loading.  No system OpenGL loader, ambient `PATH`
entry, WGL interop path, or CPU pixel-buffer fallback is accepted.

## Candidate libmpv recipe

The external planning record identified the following first-party media_kit
Windows recipe as a candidate input, not as an accepted dependency:

- development archive: `mpv-dev-x86_64-20241021-git-0f78584.7z`
- recipe tag: `20241021`
- recipe archive MD5: `6ecf18e85b093c3f7edb16f3ee6603f3`
- recipe/source commit recorded by the planning evidence:
  `8ddbe5472465950b87853789f7173f2eedc5586a`
- expected runtime name: `libmpv-2.dll`

The locally available spike binary is not that candidate artifact.  Its
hashes are recorded here to prevent accidental substitution:

- local spike MD5: `27A55D941C7370943DFC7DD4F40E0381`
- local spike SHA-256:
  `82BE8EDD8E61BD7A02458EFAF648D6414E262D59E9873D516A2E107579618FE2`

The local spike binary is diagnostic-only until its exact build inputs,
transitive license closure, and matching ANGLE runtime are independently
verified.  It must not be described as the 20241021 candidate or copied into
a release bundle by default.

## ANGLE candidate

The planning evidence recorded ANGLE v1.0.1 archive MD5
`e866f13e8d552348058afaafe869b1ed`.  The exact archive URL, SHA-256, build
configuration, and runtime DLL hashes still need to be captured through an
allowed artifact channel before a release bundle is accepted.

## Acceptance record required before packaging

Before enabling `AVACA_PLAYER_NATIVE_STRICT_DEPS` or shipping a Windows
bundle, record for every runtime and development artifact:

1. source URL or repository/ref and the exact build inputs;
2. SHA-256 and the planning MD5 where one is specified;
3. x64 PE machine/import/export inspection and the complete adjacent DLL
   inventory;
4. the full transitive NOTICE/license inventory; and
5. a runtime log proving ANGLE D3D11 shared-handle rendering and
   `dartFrameCopy=none`.

An absent or unverified artifact is a backend initialization failure.  It is
never silently replaced by a software renderer.
