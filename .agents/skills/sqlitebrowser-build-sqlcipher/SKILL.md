---
name: sqlitebrowser-build-sqlcipher
description: Check, minimally build, provider-test, verify, stage, or clean the repository-pinned SQLCipher 4.18.0 against the matching OpenSSL 3.5.7 dynamic-Brotli stage on Windows x64 with Visual Studio 2022 and SDK 10.0.26100.0. Use for this SQLiteBrowser repository's SQLCipher dependency workflow; not for Tcl-suite claims, system installation, application packaging, or non-Windows targets.
---

# SQLiteBrowser SQLCipher Build

Use `third_party\sqlcipher\build.cmd` as the command source of truth. Makefile.msc/NMake only generates upstream amalgamation and public sources; CMake/MSBuild owns product and test targets.

## Preserve the build contract

- Work from the SQLiteBrowser repository containing `third_party/sqlcipher/src`.
- Treat the pinned upstream submodule as read-only.
- Target Windows x64, Visual Studio 2022, MSVC v143, and SDK `10.0.26100.0`.
- Match Debug SQLCipher only with the Debug OpenSSL stage, and Release only with Release.
- Never substitute a system OpenSSL or mix configuration stages.
- Preserve unrelated worktree changes. Do not commit or push unless separately requested.

If the user asks only for analysis, inspect without building, cleaning, or editing.

## Choose one action

Run the wrapper from any repository working directory:

```cmd
third_party\sqlcipher\build.cmd check <all|debug|release>
third_party\sqlcipher\build.cmd build <all|debug|release>
third_party\sqlcipher\build.cmd test <all|debug|release>
third_party\sqlcipher\build.cmd clean <all|debug|release>
```

Defaults are `build all`. Configuration-only invocations remain compatible with build.

- `check` validates source, toolchain, SDK, OpenSSL/Brotli stage, CRT, and manifests without creating build output.
- `build` builds only the `sqlcipher` product target, reinstalls its private stage, and records tests as not run.
- `test` requires a valid existing product stage, builds the excluded `sqlcipher_cli` target, runs CTest and staged-product probes, and writes a test manifest bound to the current build manifest.
- `clean` removes only the selected SQLCipher private build directory. Use it only when the user selected it or approved deletion.

Read `docs/upgrade/v4.0.0/sqlcipher-build-automation-guide.md` when command, output, manifest, dependency, deployment, or troubleshooting details are needed.

## Require the matching OpenSSL stage

The wrapper consumes:

```text
output/x64-shared-debug/build/openssl/stage
output/x64-shared-release/build/openssl/stage
```

Its manifest must prove OpenSSL `3.5.7`, commit `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`, the selected configuration and SDK, Brotli `1.2.0` at commit `028fb5a23661f123017c060daa546b55cf4bde29`, and `enable-brotli-dynamic`. The minimal OpenSSL stage intentionally has no `openssl.exe`.

If missing, report the exact prerequisite command printed by the wrapper. Build OpenSSL only when the user requested or authorized that prerequisite work.

## Validate a product build

Each selected stage is:

```text
output/x64-shared-<config>/build/sqlcipher/stage
```

It must contain:

- `bin/sqlcipher.dll` and `bin/sqlcipher.pdb`;
- `lib/sqlcipher.lib`;
- `include/sqlcipher/sqlite3.h`, `sqlite3ext.h`, and `sqlite3session.h`;
- both SQLCipher/SQLite license files;
- `build-manifest.txt`.

It must not contain the test-only CLI or its PDB, provider/compile probes, OpenSSL/Brotli DLLs, generator PDBs, or compiler PDBs. The build manifest records SQLCipher `v4.18.0`, commit `63697beb0fafcb61faa7a3e6fd267036548ab11b`, SQLite `3.53.4`, configuration, SDK, CRT, OpenSSL manifest hash, product hashes, and test status `not run`.

## Validate a test run

The private `work/test-results` directory must contain the smoke CLI copy, provider output, and compile-option output. The stage must contain `test-manifest.txt` whose build-manifest SHA-256 matches the current product stage and whose CTest and staged-product probes passed.

The wrapper uses `NO_TCL=1`. It does not run `test/sqlcipher.test` or the SQLite Tcl suite. Report successful provider smoke and stage verification, never “SQLCipher official tests passed.”

## Deployment boundary

Ordinary work ends at the SQLCipher private stage. Do not copy artifacts into the application directory, update application finders/Presets, aggregate public output, or modify installers unless the user expands the task. SQLCipher stage deliberately excludes OpenSSL/Brotli runtime DLLs; a later configuration-level aggregation step composes the runnable closure.

## Report

State the selected VS edition, MSVC/CMake/SDK, SQLCipher tag/commit, configurations, exact stage paths, matching OpenSSL manifest status, product or provider-test results, and the Tcl-suite boundary. Report every unresolved prerequisite or deployment blocker.
