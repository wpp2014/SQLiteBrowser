---
name: sqlitebrowser-build-openssl
description: Build, test, verify, and stage the repository-pinned OpenSSL 3.5.7 on Windows x64 with Visual Studio 2022 and SDK 10.0.22621.0. Use for OpenSSL environment checks, builds, test selection, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide OpenSSL installation or non-Windows targets.
---

# SQLiteBrowser OpenSSL Build

Use the repository script as the single source of truth for OpenSSL build commands. Do not reproduce or replace its Configure and NMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing `third_party/openssl/src`.
- Treat `third_party/openssl/src` as pinned upstream source. Do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK `10.0.22621.0`.
- Treat installation into `build/openssl/x64-<config>/stage` as staging. It is not system installation or final application packaging.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, inspect the source, build tree, or logs without running a build or changing files.

## Select a build invocation

Invoke `third_party\openssl\build.cmd` from any working directory in the repository.

- No explicit choices: use `all safe`.
- Debug only: use `debug`.
- Release only: use `release`.
- Reproducible rebuild explicitly requested: add `clean`.
- Environment validation only: use `check`.
- Quick incremental build explicitly requested: use `none`, then disclose that tests were skipped.
- Formal release verification: use `release full clean`.

Test modes are significant:

- `safe` runs the suite except `test_bio_dgram`, avoiding the known IPv6 UDP loopback hang. Report this as a partial test pass.
- `full` performs an IPv6 UDP loopback preflight and then runs the full suite. If the preflight fails, stop and report the network-filter conflict; do not silently downgrade.
- `none` skips `nmake test` but still verifies staged artifacts. Never report it as tested.

Do not add OpenSSL's `no-tests` Configure option. Keeping test programs available allows later full validation.

## Execute and monitor

1. Read `docs/upgrade/v4.0.0/openssl-build-automation-guide.md` when usage, output layout, deployment, or troubleshooting detail is needed.
2. Run the selected repository script command.
3. Surface prerequisite failures exactly: Visual Studio edition, SDK, Perl, NASM, Git, or MSVC tools. Do not install missing tools automatically.
4. During test execution, track the last test name. If a full test produces no progress for an extended period, inspect the active process and network state before considering termination.
5. Do not delete build directories unless the user selected or approved `clean`.

## Validate the result

The script must finish successfully and the selected stage must contain:

- `bin/libcrypto-3-x64.dll`
- `bin/libssl-3-x64.dll`
- `bin/openssl.exe`
- `include/openssl/opensslv.h`
- `lib/libcrypto.lib`
- `lib/libssl.lib`
- `lib/cmake/OpenSSL/OpenSSLConfig.cmake`
- `lib/ossl-modules/legacy.dll`
- `build-manifest.txt`

Confirm Release DLLs do not depend on `VCRUNTIME140D.dll` or `ucrtbased.dll`. Debug DLLs are development artifacts and must not enter a Release package.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific stage. The current x64 WiX installer still references OpenSSL 1.1.1 filenames, so do not copy OpenSSL 3 DLLs into application or installer output and do not modify installer definitions unless the user explicitly expands the task.

For a future application deployment, use only the Release `libcrypto-3-x64.dll` and `libssl-3-x64.dll` by default. Deploy `legacy.dll`, engines, `openssl.cnf`, or `openssl.exe` only when a demonstrated runtime requirement exists, and account for OpenSSL's configured module and configuration search paths.

## Report

Return:

- selected VS edition, MSVC tools version, and SDK;
- OpenSSL tag and commit;
- configurations and test mode used;
- exact stage paths;
- build, test, install, provider, and CRT verification results;
- every skipped test or unresolved deployment blocker.
