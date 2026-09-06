---
name: sqlitebrowser-build-openssl
description: Build, test, verify, and stage the repository-pinned OpenSSL 3.5.7 on Windows x64 with Visual Studio 2022 and SDK 10.0.26100.0. Use for OpenSSL environment checks, minimal Crypto/SSL product builds, safe or full test runs, artifact verification, or staging in this SQLiteBrowser repository; do not use for system-wide installation, final app packaging, or non-Windows targets.
---

# SQLiteBrowser OpenSSL Build

Use third_party\openssl\build.cmd as the single source of truth. Do not reproduce its Configure or NMake workflow unless the user explicitly asks to change the automation.

## Establish scope

- Work from the SQLiteBrowser repository containing third_party/openssl/src.
- Treat the OpenSSL source submodule as pinned upstream source; do not edit it.
- Target Windows x64, Visual Studio 2022, MSVC v143, and Windows SDK 10.0.26100.0.
- Require a matching Brotli stage at output/x64-shared-<config>/build/brotli/stage.
- Debug OpenSSL consumes only Debug Brotli; Release consumes only Release Brotli.
- Treat output/x64-shared-<config>/build/openssl/stage as a private dependency stage, not a system installation or final application package.
- Preserve unrelated worktree changes. Never commit or push unless separately requested.

If the user asks only for analysis, inspect source, scripts, manifests, or logs without running a build or changing files.

## Select an invocation

Run the script from any directory in the repository.

~~~cmd
third_party\openssl\build.cmd check [all|debug|release]
third_party\openssl\build.cmd build [all|debug|release]
third_party\openssl\build.cmd test <all|debug|release> [safe|full]
third_party\openssl\build.cmd clean [all|debug|release]
~~~

Selection rules:

- No arguments means build all. It does not run tests.
- Ordinary product build: build all, or one explicit configuration.
- Environment validation only: check.
- Test an existing verified build: test <config> safe unless the user explicitly requests full.
- Reproducible rebuild: clean <config>, followed by build <config>.
- Do not delete build directories unless clean was requested or approved.

Test modes:

- safe runs the general suite with test_bio_dgram excluded, then runs test_bio_comp, test_cert_comp, and test_tls13certcomp. Report it as a safe partial pass, never a full pass.
- full performs the IPv6 UDP loopback preflight, runs the unfiltered suite, then the same focused Brotli tests. If preflight fails, stop and report the local network-filter conflict.

The build action never runs tests. Do not add no-tests to Configure because the separate test action must remain available.

## Execute and monitor

1. Read `.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md` when usage, layout, deployment, or troubleshooting detail is needed.
2. Run the selected repository command.
3. Surface prerequisite failures exactly: VS edition, SDK, Perl, NASM, Git, MSVC tools, source revision, or matching Brotli stage.
4. During tests, track the last recipe. A quiet stress test is not automatically a hang; inspect processes and network state before terminating.
5. Keep test-only CLI, provider, fuzz, and recipe executables inside the configuration work directory.

## Validate a product build

The stage must contain:

- bin/libcrypto-3-x64.dll and its linker PDB;
- bin/libssl-3-x64.dll and its linker PDB;
- matching bin/brotlicommon.dll, bin/brotlidec.dll, and bin/brotlienc.dll;
- include/openssl/opensslv.h and the public OpenSSL headers;
- lib/libcrypto.lib and lib/libssl.lib;
- lib/cmake/OpenSSL/OpenSSLConfig.cmake;
- build-manifest.txt with Tests: not run.

The stage must not contain:

- openssl.exe;
- legacy.dll or other provider modules;
- engine DLLs;
- vc143.pdb or another compiler PDB;
- test, fuzz, example, or demo executables.

Confirm:

- DLL architecture is x64;
- Debug uses Debug CRT and Release does not depend on VCRUNTIME140D.dll or ucrtbased.dll;
- configdata.pm records Brotli dynamic loading and the matching Brotli include path;
- libcrypto exports COMP_brotli, COMP_brotli_oneshot, and BIO_f_brotli;
- libcrypto has no direct Brotli DLL import;
- staged Brotli DLLs are byte-identical to the validated Brotli stage.

## Validate a test run

- Require an existing verified build-manifest.txt before testing.
- Require stage/test-manifest.txt after success.
- Verify its Build manifest SHA-256 equals the current build-manifest.txt hash.
- Require the selected general suite and all three focused Brotli tests to pass.
- For safe mode, require the record to state that test_bio_dgram was excluded.
- Confirm no test executable, CLI, provider, or engine DLL entered the stage.
- Do not rewrite build-manifest.txt to claim tests ran; build and test records are intentionally separate.

## Deployment boundary

For ordinary requests, deployment ends at the configuration-specific OpenSSL stage. Do not copy files to the application or installer output until the later public-output and application migration phases request it.

The eventual application runtime set is the matching Release pair of OpenSSL DLLs plus all three Brotli DLLs. Deploy openssl.exe, providers, engines, configuration files, import libraries, or PDBs only for a demonstrated development or packaging requirement.

## Report

Return:

- selected VS edition, MSVC tools, and SDK;
- OpenSSL and Brotli tag/commit provenance;
- configuration and action;
- exact work and stage paths;
- minimal-stage and CRT results;
- Brotli export, dynamic-loading, and byte-identity results;
- test mode, suite totals, focused-test result, build-manifest binding, and every excluded/skipped item;
- any unresolved consumer or packaging migration blocker.
