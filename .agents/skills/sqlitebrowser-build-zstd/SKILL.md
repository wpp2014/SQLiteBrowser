---
name: sqlitebrowser-build-zstd
description: Build, test, verify, and stage the repository-pinned zstd 1.5.7 on Windows x64 with Visual Studio 2022 and SDK 10.0.22621.0. Use for zstd environment checks, Debug or Release builds, shared-DLL smoke tests, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide installation, static/CLI/contrib builds, optional zlib/LZMA/LZ4 compatibility, OpenSSL integration claims, or non-Windows targets.
---

# SQLiteBrowser zstd Build

Use `third_party\zstd\build.cmd` as the single source of truth. Do not reproduce or replace its CMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/zstd/src`.
- Treat `third_party/zstd/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.22621.0`.
- Build only the shared zstd library. Keep static zstd, CLI programs, contrib components, legacy support, and deprecated modules disabled.
- Keep `ZSTD_ZLIB_SUPPORT`, `ZSTD_LZMA_SUPPORT`, and `ZSTD_LZ4_SUPPORT` disabled.
- Require both Debug and Release DLLs to be named `libzstd.dll`; keep their matching `libzstd.lib` import libraries in the configuration-specific stage.
- Treat `build/zstd/x64-<config>/stage` as staging, not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, log inspection, or an explanation, do not run a build or modify files.

## Select the script invocation

Invoke the script from any working directory in the repository.

- No explicit configuration: use `third_party\zstd\build.cmd all`.
- Debug only: use `third_party\zstd\build.cmd debug`.
- Release only: use `third_party\zstd\build.cmd release`.
- Environment validation only: use `third_party\zstd\build.cmd check`.
- Reproducible rebuild explicitly requested: add `clean` to the selected build configuration.

Do not add `clean` unless the user selected it or approved removing the selected ignored zstd work and stage directories.

Every actual build runs the project-owned shared-library smoke test. This workflow has no skip-test mode. If the smoke test fails, report the failure; do not generate a manifest or treat staged artifacts as a successful verified build.

## Execute and monitor

1. Read `docs/upgrade/v4.0.0/zstd-vs2022-build-analysis.md` when build policy, output layout, manifest fields, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: source revision or dirty state, CMake/CTest, Visual Studio edition, SDK, MSVC tools, PowerShell, or certutil.
4. Do not install missing tools, modify PATH permanently, or substitute a system zstd.
5. If CMake reports a generator-instance mismatch, use `clean` only after the user has selected or approved it.

## Validate the result

The script must finish successfully. Each selected stage must contain:

- `bin/libzstd.dll`
- `include/zstd.h`
- `include/zdict.h`
- `include/zstd_errors.h`
- `lib/libzstd.lib`
- `build-manifest.txt`

Confirm the manifest records zstd `v1.5.7`, commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99`, the selected configuration, x64, VS/MSVC/SDK/CMake, `/MDd` or `/MD`, and a passed project shared-library smoke test.

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
