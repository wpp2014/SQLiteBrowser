---
name: sqlitebrowser-build-zstd
description: Build, test, verify, and stage the repository-pinned zstd 1.5.7 on Windows x64 with Visual Studio 2022 and SDK 10.0.26100.0. Use for zstd environment checks, minimal Debug or Release builds, separate shared-DLL smoke tests, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide installation, static/CLI/contrib builds, optional zlib/LZMA/LZ4 compatibility, OpenSSL integration claims, or non-Windows targets.
---

# SQLiteBrowser zstd Build

Use `third_party\zstd\build.cmd` as the single source of truth. Do not reproduce or replace its CMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/zstd/src`.
- Treat `third_party/zstd/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.26100.0`.
- Build only the shared zstd library. Keep static zstd, CLI programs, contrib components, legacy support, and deprecated modules disabled.
- Keep `ZSTD_ZLIB_SUPPORT`, `ZSTD_LZMA_SUPPORT`, and `ZSTD_LZ4_SUPPORT` disabled.
- Require both Debug and Release DLLs to be named `libzstd.dll`; keep matching `libzstd.lib` import libraries and linker `libzstd.pdb` files in the configuration-specific stage.
- Treat `output/x64-shared-<config>/build/zstd/stage` as staging, not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, log inspection, or an explanation, do not run a build or modify files.

## Select the script invocation

Invoke the script from any working directory in the repository.

- No explicit configuration: use `third_party\zstd\build.cmd build all`.
- Debug only: use `third_party\zstd\build.cmd build debug`.
- Release only: use `third_party\zstd\build.cmd build release`.
- Environment validation only: use `third_party\zstd\build.cmd check`.
- Tests: use `third_party\zstd\build.cmd test <debug|release|all>` after a successful matching build.
- Cleanup explicitly requested: use `third_party\zstd\build.cmd clean <debug|release|all>`.

Do not add `clean` unless the user selected it or approved removing the selected ignored zstd work and stage directories.

The build action compiles only `libzstd_shared`, stages product artifacts, and marks tests `not run`. The test action builds the excluded smoke target, runs it, and writes `test-manifest.txt` bound to the build manifest SHA-256.

## Execute and monitor

1. Read `.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md` when build policy, output layout, manifest fields, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: source revision or dirty state, CMake/CTest, Visual Studio edition, SDK, MSVC tools, PowerShell, or certutil.
4. Do not install missing tools, modify PATH permanently, or substitute a system zstd.
5. If CMake reports a generator-instance mismatch, use `clean` only after the user has selected or approved it.

## Validate the result

The script must finish successfully. Each selected stage must contain:

- `bin/libzstd.dll`
- `bin/libzstd.pdb`
- `include/zstd.h`
- `include/zdict.h`
- `include/zstd_errors.h`
- `lib/libzstd.lib`
- `build-manifest.txt`

Confirm the build manifest records zstd `v1.5.7`, commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99`, the selected configuration, x64, VS/MSVC/SDK/CMake, `/MDd` or `/MD`, linker-PDB policy, and tests as `not run`. After `test`, confirm `test-manifest.txt` records the passed smoke test, runtime version, and matching build manifest SHA-256.

Also confirm:

- the DLL is x64 and exports the version, one-shot, and streaming APIs checked by the script;
- the DLL file version and runtime version are `1.5.7`;
- Debug uses the Debug CRT and Release does not depend on Debug CRT DLLs;
- Debug and Release both use the un-suffixed `libzstd.dll` and `libzstd.lib` names;
- no static library or CLI program exists in stage;
- no zlib, LZMA, or LZ4 compatibility dependency exists;
- the manifest contains SHA-256 values for the DLL and import library.

`libzstd.lib` is the import library for `libzstd.dll`; its presence does not mean static zstd was enabled. Upstream static tests are intentionally not run because the deliverable is the shared DLL; the project smoke test directly loads and exercises that shared artifact.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific zstd stage. Do not copy zstd into OpenSSL or SQLiteBrowser output directories, enable OpenSSL zstd support, edit installers, or claim that OpenSSL certificate-compression integration passed unless the user explicitly expands the task and that integration is separately built and tested.

## Report

Return:

- selected VS edition, MSVC tools version, CMake version, and Windows SDK;
- zstd tag and commit;
- configurations built and exact stage paths;
- shared-library smoke-test results;
- DLL/import-library naming, architecture, CRT, exports, version, hashes, and manifest verification results;
- confirmation that static, CLI, contrib, legacy, deprecated, and optional compatibility components were excluded;
- every skipped step or unresolved blocker.
