---
name: sqlitebrowser-build-brotli
description: Build, test, verify, and stage the repository-pinned Brotli 1.2.0 on Windows x64 with Visual Studio 2022 and SDK 10.0.26100.0. Use for Brotli environment checks, minimal Debug or Release builds, separate shared-DLL smoke tests, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide installation, static/CLI builds, OpenSSL integration claims, or non-Windows targets.
---

# SQLiteBrowser Brotli Build

Use `third_party\brotli\build.cmd` as the single source of truth. Do not reproduce or replace its CMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/brotli/src`.
- Treat `third_party/brotli/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.26100.0`.
- Build only the upstream `brotlicommon`, `brotlidec`, and `brotlienc` shared libraries. Keep static package variants, the Brotli CLI, and upstream CLI-based tests disabled.
- Require Debug and Release artifacts to keep the un-suffixed names `brotlicommon.dll`, `brotlidec.dll`, and `brotlienc.dll`; keep the three matching linker PDBs and import libraries in the configuration-specific stage, but never stage compiler intermediates such as `vc143.pdb`.
- Treat `output/x64-shared-<config>/build/brotli/stage` as dependency staging, not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, log inspection, or an explanation, do not run a build or modify files.

## Select the script invocation

Invoke the script from any working directory in the repository.

- No explicit configuration: use `third_party\brotli\build.cmd build all`.
- Debug only: use `third_party\brotli\build.cmd build debug`.
- Release only: use `third_party\brotli\build.cmd build release`.
- Environment validation only: use `third_party\brotli\build.cmd check`.
- Tests: use `third_party\brotli\build.cmd test <debug|release|all>` after a successful matching build.
- Cleanup explicitly requested: use `third_party\brotli\build.cmd clean <debug|release|all>`.

Do not add `clean` unless the user selected it or approved removing the selected ignored Brotli work and stage directories.

The build action compiles only the three product DLL targets and writes `build-manifest.txt` with tests marked `not run`. The test action builds the excluded smoke target, runs it, and writes `test-manifest.txt` bound to the build manifest SHA-256.

## Execute and monitor

1. Read `.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md` when build policy, output layout, manifest fields, OpenSSL boundary, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: source revision or dirty state, CMake/CTest, Visual Studio edition, SDK, MSVC tools, or certutil.
4. Do not install missing tools, modify PATH permanently, or substitute a system Brotli.
5. If CMake reports a generator-instance mismatch, use `clean` only after the user has selected or approved it.

## Validate the result

The script must finish successfully. Each selected stage must contain:

- `bin/brotlicommon.dll`
- `bin/brotlicommon.pdb`
- `bin/brotlidec.dll`
- `bin/brotlidec.pdb`
- `bin/brotlienc.dll`
- `bin/brotlienc.pdb`
- `include/brotli/decode.h`
- `include/brotli/encode.h`
- `include/brotli/port.h`
- `include/brotli/shared_dictionary.h`
- `include/brotli/types.h`
- `lib/brotlicommon.lib`
- `lib/brotlidec.lib`
- `lib/brotlienc.lib`
- `build-manifest.txt`

Confirm the build manifest records Brotli `v1.2.0`, commit `028fb5a23661f123017c060daa546b55cf4bde29`, the selected configuration, x64, VS/MSVC/SDK/CMake, `/MDd` or `/MD`, the linker-PDB-only policy, Release optimized symbol flags, and tests as `not run`. After `test`, confirm `test-manifest.txt` records a passed smoke test and the matching build manifest SHA-256.

Also confirm:

- all three DLLs are x64;
- encoder and decoder runtime versions are `1.2.0`;
- Debug uses the Debug CRT and Release does not depend on Debug CRT DLLs;
- `brotlidec.dll` and `brotlienc.dll` depend on `brotlicommon.dll`;
- the encoder and decoder DLLs export the APIs needed by OpenSSL's dynamic Brotli loader;
- Debug and Release both use un-suffixed DLL/import-library names;
- each stage contains exactly `brotlicommon.pdb`, `brotlidec.pdb`, and `brotlienc.pdb`, and contains no `vc143.pdb`;
- Release remains optimized and generates linker PDBs with `/Zi`, `/DEBUG:FULL`, `/OPT:REF`, and `/OPT:ICF`;
- no static package library or Brotli CLI exists in stage;
- no zlib, zstd, or LZMA dependency exists;
- the manifest contains SHA-256 values for all three DLLs, all three linker PDBs, and all three import libraries.

The three `.lib` files are import libraries for the matching DLLs; their presence does not mean static Brotli was enabled. Upstream CLI tests are intentionally not run because the deliverable excludes the CLI; the project smoke test directly loads and exercises the shared libraries with one-shot and streaming round trips plus decoder error handling.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific Brotli stage. Do not copy Brotli into OpenSSL or SQLiteBrowser output directories, enable OpenSSL Brotli support, edit installers, or claim that OpenSSL Brotli BIO or certificate-compression integration passed unless the user explicitly expands the task and that integration is separately built and tested.

## Report

Return:

- selected VS edition, MSVC tools version, CMake version, and Windows SDK;
- Brotli tag and commit;
- configurations built and exact stage paths;
- shared-library smoke-test results;
- three-DLL/linker-PDB/import-library naming, architecture, CRT, exports, dependencies, runtime versions, hashes, and manifest verification results, including confirmation that no `vc143.pdb` was staged;
- confirmation that static package targets, the CLI, upstream CLI tests, and optional compression dependencies were excluded;
- every skipped step or unresolved blocker.
