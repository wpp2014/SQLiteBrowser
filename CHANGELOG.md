# CHANGELOG for DB4S

## 4.0.0 - pending release

- Restrict the supported build and release target to Windows x64 with Visual
  Studio 2022, MSVC v143, and Windows SDK 10.0.26100.0.
- Upgrade the application build to Qt 6.11.1 and CMake Presets.
- Pin and build Brotli 1.2.0, OpenSSL 3.5.7, SQLCipher 4.18.0, zlib 1.3.2, and
  zstd 1.5.7 from repository submodules.
- Add reproducible dependency stages, manifests, unit tests, restricted-path
  runtime smoke tests, and GitHub-hosted Windows builds.
- Add a portable NSIS self-extracting package and a per-machine WiX MSI with
  optional Start Menu and desktop shortcuts.
- Publish only the portable SFX and WiX MSI user packages, each with an
  independent SHA-256 file.
- Disable the upstream release update check for the SQLCipher-only v4 build.

Known limitations:

- The packages require a compatible Microsoft Visual C++ x64 Runtime to be
  installed separately.
- The v4.0.0 packages are not Authenticode-signed and may trigger Windows
  unknown-publisher or SmartScreen warnings.
- Automatic WinGet publication is disabled for this fork release.

For changes in the current codebase, see the following wiki page:  
> https://github.com/sqlitebrowser/sqlitebrowser/wiki/CHANGELOG
