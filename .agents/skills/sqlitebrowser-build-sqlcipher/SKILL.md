---
name: sqlitebrowser-build-sqlcipher
description: Build, verify, and stage the repository-pinned SQLCipher 4.18.0 against the matching OpenSSL 3.5.7 stages on Windows x64 with Visual Studio 2022 and SDK 10.0.22621.0. Use for SQLCipher environment checks, Debug or Release builds, artifact verification, or staging in this SQLiteBrowser repository; do not use for Tcl test claims, system installation, or non-Windows targets.
---

# SQLiteBrowser SQLCipher Build

Use the repository script as the single source of truth for SQLCipher build commands. Do not reproduce its CMake, MSBuild, or NMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/sqlcipher/src`.
- Treat `third_party/sqlcipher/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.22621.0`.
- Link Debug SQLCipher only to the Debug OpenSSL stage and Release only to the Release OpenSSL stage.
- Treat output in `build/sqlcipher/x64-<config>/stage` as staging, not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, inspect source, scripts, build trees, manifests, or logs without running a build or changing files.

## Select a build invocation

Invoke `third_party\sqlcipher\build.cmd` from any working directory in the repository.

- No explicit configuration: use `all`.
- Debug only: use `debug`.
- Release only: use `release`.
- Environment and dependency validation only: add `check`.
- Reproducible rebuild explicitly requested: add `clean`.

Do not add `clean` unless the user selected it or approved deleting the selected ignored build and stage directories.

## Respect the OpenSSL dependency

The selected configuration requires the matching repository stage:

- Debug: `build/openssl/x64-debug/stage`
- Release: `build/openssl/x64-release/stage`

If a stage or required artifact is missing, stop and report the exact prerequisite command printed by the script. Do not silently link a system OpenSSL, mix Debug and Release, or substitute another OpenSSL version.

Use `third_party\openssl\build.cmd` or the repository's `sqlitebrowser-build-openssl` skill only when the user has requested that dependency build. A missing OpenSSL manifest is permitted for a development build but must be reported; require a manifest produced by the OpenSSL script before calling a build formally reproducible or release-ready.

## Execute and monitor

1. Read `docs/upgrade/v4.0.0/sqlcipher-build-automation-guide.md` when usage, output layout, dependency, deployment, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: SQLCipher revision or dirty state, CMake, Visual Studio edition, SDK, MSVC tools, Windows PowerShell, or OpenSSL artifacts.
4. Do not initialise missing tools or change PATH permanently. The script may initialise the pinned SQLCipher submodule during an actual build.
5. If CMake reports a generator-instance mismatch, rerun with `clean` only after the user has selected or approved it.

## Validate the result

The script must finish successfully and each selected stage must contain:

- `bin/sqlcipher.dll`
- `bin/sqlcipher.exe`
- `include/sqlcipher/sqlite3.h`
- `include/sqlcipher/sqlite3ext.h`
- `include/sqlcipher/sqlite3session.h`
- `lib/sqlcipher.lib`
- `build-manifest.txt`

Confirm the manifest records SQLCipher `v4.18.0`, commit `63697beb0fafcb61faa7a3e6fd267036548ab11b`, the selected CRT, and the OpenSSL `3.5.7` provider result. Release must not depend on Debug CRT DLLs; Debug development artifacts must not enter a Release package.

## State the test boundary

The product wrapper builds with `NO_TCL=1`. It performs artifact, dependency, CRT, exported-symbol, and CLI provider smoke checks, but it does not run `test/sqlcipher.test` or the SQLite Tcl suite.

Never report the result as “SQLCipher tests passed.” Report it as a successful build and stage verification, and explicitly state that the Tcl SQLCipher test suite was not run.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific SQLCipher stage. Do not copy SQLCipher or OpenSSL DLLs into the SQLiteBrowser application directory, edit `FindSQLCipher.cmake`, or modify installers unless the user explicitly expands the task.

Running staged `sqlcipher.exe` requires the matching OpenSSL `bin` directory on the process DLL search path. Do not use a system-wide OpenSSL as fallback.

## Report

Return:

- selected VS edition, MSVC tools version, CMake version, and SDK;
- SQLCipher tag and commit;
- configurations built and exact stage paths;
- OpenSSL stage and manifest status for each configuration;
- artifact, provider, CRT, and manifest verification results;
- the fact that Tcl SQLCipher tests were not run;
- every unresolved dependency or deployment blocker.
