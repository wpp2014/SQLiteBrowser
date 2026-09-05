---
name: sqlitebrowser-build-zlib
description: Build, test, verify, and stage the repository-pinned zlib 1.3.2 on Windows x64 with Visual Studio 2022 and SDK 10.0.26100.0. Use for zlib environment checks, minimal Debug or Release builds, separate CTest runs, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide installation, minizip/contrib builds, static zlib, or non-Windows targets.
---

# SQLiteBrowser zlib Build

Use `third_party\zlib\build.cmd` as the single source of truth. Do not reproduce or replace its CMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/zlib/src`.
- Treat `third_party/zlib/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.26100.0`.
- Build only the shared zlib library. Keep minizip, every other contrib component, and static zlib disabled.
- Require both Debug and Release DLLs to be named `zlib1.dll`; keep matching `zlib1.lib` import libraries and linker `zlib1.pdb` files in the configuration-specific stage.
- Treat `output/x64-shared-<config>/build/zlib/stage` as staging, not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, log inspection, or an explanation, do not run a build or modify files.

## Select the script invocation

Invoke the script from any working directory in the repository.

- No explicit configuration: use `third_party\zlib\build.cmd build all`.
- Debug only: use `third_party\zlib\build.cmd build debug`.
- Release only: use `third_party\zlib\build.cmd build release`.
- Environment validation only: use `third_party\zlib\build.cmd check`.
- Tests: use `third_party\zlib\build.cmd test <debug|release|all>` after a successful matching build.
- Cleanup explicitly requested: use `third_party\zlib\build.cmd clean <debug|release|all>`.

Do not add `clean` unless the user selected it or approved removing the selected ignored zlib work and stage directories.

The build action compiles only `zlib`, stages product artifacts, and marks tests `not run`. The test action builds the excluded example target, runs CTest, and writes `test-manifest.txt` bound to the build manifest SHA-256.

## Execute and monitor

1. Read `.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md` when build policy, output layout, usage, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: source revision or dirty state, CMake/CTest, Visual Studio edition, SDK, MSVC tools, or PowerShell.
4. Do not install missing tools, modify PATH permanently, or substitute a system zlib.
5. If CMake reports a generator-instance mismatch, use `clean` only after the user has selected or approved it.

## Validate the result

The script must finish successfully. Each selected stage must contain:

- `bin/zlib1.dll`
- `bin/zlib1.pdb`
- `include/zlib.h`
- `include/zconf.h`
- `lib/zlib1.lib`
- `build-manifest.txt`

Confirm the build manifest records zlib `v1.3.2`, commit `da607da739fa6047df13e66a2af6b8bec7c2a498`, the selected configuration, x64, VS/MSVC/SDK/CMake, `/MDd` or `/MD`, linker-PDB policy, and tests as `not run`. After `test`, confirm `test-manifest.txt` records passed CTest and the matching build manifest SHA-256.

Also confirm:

- the DLL is x64 and exports `zlibVersion` and deflate APIs;
- Debug uses the Debug CRT and Release does not depend on Debug CRT DLLs;
- Debug and Release both use the un-suffixed `zlib1.dll` and `zlib1.lib` names;
- no static zlib, minizip, or other contrib artifact exists in stage.

`zlib1.lib` is the import library for `zlib1.dll`; its presence does not mean static zlib was enabled.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific zlib stage. Do not copy zlib into the OpenSSL or SQLiteBrowser output directories, modify OpenSSL configuration, edit installers, or claim that OpenSSL zlib integration passed unless the user explicitly expands the task and that integration is tested.

## Report

Return:

- selected VS edition, MSVC tools version, CMake version, and Windows SDK;
- zlib tag and commit;
- configurations built and exact stage paths;
- CTest results;
- DLL/import-library naming, architecture, CRT, exports, version, and manifest verification results;
- confirmation that static zlib and contrib components were excluded;
- every skipped step or unresolved blocker.
