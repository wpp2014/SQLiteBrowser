# Windows v4 build guide

> Applies to the `upgrade/v4.0.0` branch. This branch supports Windows x64 only.

The following procedure starts with a fresh clone and produces independently
configured Debug and Release development outputs, test outputs, and strict
package runtimes. Run all commands from the repository root in a regular
`cmd.exe` window. The dependency scripts locate and initialise Visual Studio
themselves, so a Developer Command Prompt is not required.

## 1. Install the build tools

| Component | Required configuration |
| --- | --- |
| Visual Studio | Visual Studio 2022 Enterprise, Professional, or Community, installed in its default `C:\Program Files\Microsoft Visual Studio\2022\<Edition>` directory |
| Visual Studio workload | **Desktop development with C++**, including MSVC v143 x64/x86 build tools and MSBuild |
| Windows SDK | **10.0.26100.0** for Brotli, zlib, zstd, OpenSSL, SQLCipher, and the application |
| Git | Available as `git.exe` in `PATH` |
| CMake | Version **3.30.3**, with `cmake.exe` and `ctest.exe` in `PATH` |
| Qt | Qt **6.11.1**, MSVC 2022 64-bit package (`msvc2022_64`), including Core5Compat, LinguistTools, SVG, and PDF support |
| Perl | A native Windows Perl distribution, preferably Strawberry Perl, with `perl.exe` in `PATH` |
| NASM | Available as `nasm.exe` in `PATH` |
| NSIS | Version **3.12**, installed at the default `C:\Program Files (x86)\NSIS` path, for the optional portable self-extracting EXE |

All migrated dependency scripts and the application use Windows SDK
10.0.26100.0.

NSIS is not required to compile or run the application. It is required only
when building the portable self-extracting EXE.

You can check the command-line tools before cloning:

~~~cmd
git --version
cmake --version
ctest --version
perl --version
nasm -v
~~~

## 2. Clone the repository and initialise submodules

~~~cmd
git clone --branch upgrade/v4.0.0 --recurse-submodules https://github.com/wpp2014/SQLiteBrowser.git
cd SQLiteBrowser
git submodule update --init --recursive
~~~

The final `git submodule update` is intentionally safe to repeat and ensures
all nested submodules are present at the commits recorded by this repository.

The main application currently consumes these pinned dependencies:

| Dependency | Version | Required by the main application |
| --- | --- | --- |
| Brotli | v1.2.0 | Yes, dynamically loaded by OpenSSL |
| OpenSSL | openssl-3.5.7 | Yes |
| SQLCipher | v4.18.0 | Yes |
| zlib | v1.3.2 | No |
| zstd | v1.5.7 | No |

## 3. Build and publish the dependency stages

Build the dependencies in this order:

~~~cmd
third_party\brotli\build.cmd check all
third_party\zlib\build.cmd check all
third_party\zstd\build.cmd check all

third_party\brotli\build.cmd build all
third_party\zlib\build.cmd build all
third_party\zstd\build.cmd build all

third_party\brotli\build.cmd test all
third_party\zlib\build.cmd test all
third_party\zstd\build.cmd test all

third_party\openssl\build.cmd check all
third_party\openssl\build.cmd build all
third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release safe

third_party\sqlcipher\build.cmd check all
third_party\sqlcipher\build.cmd build all
third_party\sqlcipher\build.cmd test all

third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
~~~

The dependency `build` actions create only product stages and record tests as
`not run`. The three compression-library `test` actions build only their test
targets; Brotli and zstd run their shared-library smoke tests, while zlib runs
its CTest suite. SQLCipher's separate `test` action builds its private CLI,
runs the provider smoke and staged-product probes, then writes a test manifest
bound to the current build manifest. The OpenSSL `safe` commands run its test
suite while excluding `test_bio_dgram`, which can conflict with local IPv6 UDP
filters, then run the focused Brotli integration tests. A safe result is not a
full OpenSSL test pass. Use `full` only on a machine where the script's IPv6
UDP preflight succeeds.

Each dependency script validates the source revision, Visual Studio
installation, SDK, architecture, CRT, staged files, and build manifest. The
final aggregate commands validate all five matching private stages and publish
only the public allowlist. A non-zero exit code means the dependency output
must not be used.

Successful builds create:

~~~text
output\x64-shared-debug\build\brotli\stage
output\x64-shared-release\build\brotli\stage
output\x64-shared-debug\build\zlib\stage
output\x64-shared-release\build\zlib\stage
output\x64-shared-debug\build\zstd\stage
output\x64-shared-release\build\zstd\stage
output\x64-shared-debug\build\openssl\stage
output\x64-shared-release\build\openssl\stage
output\x64-shared-debug\build\sqlcipher\stage
output\x64-shared-release\build\sqlcipher\stage

output\x64-shared-debug\include
output\x64-shared-debug\bin
output\x64-shared-debug\metadata
output\x64-shared-release\include
output\x64-shared-release\bin
output\x64-shared-release\metadata
~~~

Immediately after dependency aggregation, the public `bin` directories contain
dependency DLLs, import libraries, and linker PDBs only. The application build
later adds the application EXE/PDB and Qt runtime without changing files owned
by the dependency aggregator. These remain development outputs rather than
application package directories. `metadata\dependency-ownership-manifest.txt`
records the SHA-256 and relative path of every dependency file managed by the
aggregator.

To validate without changing files, or to remove only aggregator-owned public
files for one configuration:

~~~cmd
third_party\aggregate.cmd check all
third_party\aggregate.cmd clean debug
third_party\aggregate.cmd build debug
~~~

To inspect the available modes without building:

~~~cmd
third_party\brotli\build.cmd --help
third_party\zlib\build.cmd --help
third_party\zstd\build.cmd --help
third_party\openssl\build.cmd --help
third_party\sqlcipher\build.cmd --help
third_party\aggregate.cmd --help
~~~

## 4. Create the local CMake Preset file

Copy the repository template. Do not edit the template itself:

~~~cmd
copy /Y CMakePresets.template.json CMakePresets.json
~~~

Open `CMakePresets.json` and replace this single placeholder:

~~~text
REPLACE_WITH_QT_6_11_1_MSVC2022_X64_ROOT
~~~

with the root of your local Qt 6.11.1 MSVC 2022 x64 package. Use forward
slashes in JSON, for example:

~~~json
"CMAKE_PREFIX_PATH": "D:/Qt/6.11.1/msvc2022_64"
~~~

Do not change `SQLITEBROWSER_CONFIGURATION_ROOT` or the configuration-specific
OpenSSL and SQLCipher stage paths.
`CMakePresets.json` is intentionally ignored by Git because it contains a
developer-specific Qt path.

Confirm that CMake can read the local file:

~~~cmd
cmake --list-presets=all
~~~

The output must include the `debug` and `release` configure presets, the
matching product and unit-test build presets, and the `test-*`, `package-*`,
and `smoke-*` workflow presets.

## 5. Configure and build the application

Debug:

~~~cmd
cmake --preset debug
cmake --build --preset debug
~~~

Release:

~~~cmd
cmake --preset release
cmake --build --preset release
~~~

Each build preset names only the `sqlitebrowser` product target, so the normal
command does not compile unit tests or runtime-smoke tools. The build runs the
application's `POST_BUILD` deployment automatically. It
copies the matching SQLCipher, OpenSSL, and Brotli DLLs, runs `windeployqt`,
and fails if required runtime files are missing or Debug and Release files are
mixed.

The runnable output directories are:

~~~text
output\x64-shared-debug\bin
output\x64-shared-release\bin
~~~

Run the application directly:

~~~cmd
"output\x64-shared-debug\bin\DB Browser for SQLCipher.exe"
"output\x64-shared-release\bin\DB Browser for SQLCipher.exe"
~~~

No Qt, OpenSSL, or SQLCipher directory needs to be added to the global `PATH`.

## 6. Run the tests

The normal product preset intentionally does not build the four unit-test
executables. Use the dedicated workflows to configure, build only the unit-test
aggregate target, and run CTest:

~~~cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
~~~

The four test executables remain under
`output\x64-shared-<config>\build\tests\unit`; they are never copied to the
public `bin` directory.

## 7. Assemble and smoke-test the package runtime

The public `bin` directories are development outputs. They also contain import
libraries, linker PDBs, zlib, and zstd, so they must not be copied directly into
a ZIP or installer. Assemble the strict runtime-only directories with:

~~~cmd
cmake --workflow --preset package-debug
cmake --workflow --preset package-release
~~~

The validated package inputs are:

~~~text
output\x64-shared-debug\package\runtime
output\x64-shared-release\package\runtime
~~~

Each workflow first validates the matching development output, copies an
explicit runtime allowlist through a temporary directory, rejects extra files,
and writes a SHA-256 manifest to
`output\x64-shared-<config>\package\metadata\runtime-manifest.txt`. The current
Debug and Release package allowlists both contain 70 files. Although
`windeployqt` can place `vc_redist.x64.exe` in the Release development `bin`,
the publication allowlist explicitly excludes it from `package\runtime`.
Debug is intended only for testing on a machine with the matching development
toolchain.

Run the complete restricted-`PATH` package smoke suites with:

~~~cmd
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
~~~

Each smoke workflow also assembles and validates its package runtime, so the
matching `package-*` workflow does not need to be run first. The smoke tool is
built under `output\x64-shared-<config>\build\tests\runtime-smoke` and is not
copied into the package runtime. It verifies application startup, encrypted
SQLCipher, OpenSSL dynamic Brotli support, Qt's OpenSSL 3.5.7 backend, HTTPS,
and the actual loaded DLL locations. The HTTPS check requires network access
to `https://download.sqlitebrowser.org/currentrelease`; its endpoint can be
overridden with the `SQLITEBROWSER_TLS_SMOKE_URL` CMake cache variable.

These directories are validated packaging inputs, not finished release
archives or installers. Packaging must consume `package\runtime` and must not
select files again from the development `bin`.

## 8. Build the Release x64 ZIP archive

The ZIP archive consumes the same validated Release runtime used by the MSI.
It does not use the legacy Windows `install()` rules and does not collect files
again from the development `bin` directory.

Build, smoke-test, archive, extract, and verify the ZIP from the repository
root:

~~~cmd
cmake --workflow --preset zip-release
~~~

The equivalent convenience entry point is:

~~~cmd
installer\windows\zip\build.cmd
~~~

The workflow creates one fixed `DB Browser for SQLCipher` top-level directory,
checks every source file against `runtime-manifest.txt`, extracts the finished
archive into a separate verification directory, compares all 70 files and
hashes, and runs the restricted-`PATH` startup, SQLCipher, Brotli, TLS, and
HTTPS smoke checks from the extracted copy.

Outputs are written to:

~~~text
output\x64-shared-release\package\artifacts\
  DB.Browser.for.SQLCipher-4.0.0-win-x64.zip
  DB.Browser.for.SQLCipher-4.0.0-win-x64.zip.sha256

output\x64-shared-release\package\metadata\zip-manifest.txt
output\x64-shared-release\package\verify\zip\
~~~

This is an install-free archive: users can extract it and start the executable
without registering an installed product. It does not yet implement a special
portable settings mode, so application settings may still use the normal
registry or AppData locations.

## 9. Build the Release x64 portable self-extracting EXE

The NSIS package is an extraction-only portable wrapper around the same strict
70-file Release runtime used by the ZIP and MSI. It does not install a product,
write the registry, create shortcuts or an uninstaller, change `PATH`, request
administrator rights, or inspect/remove an installed version.

Install NSIS 3.12 in its default directory, then run from the repository root:

~~~cmd
cmake --workflow --preset portable-sfx-release
~~~

The equivalent convenience entry point is:

~~~cmd
installer\windows\nsis\build.cmd
~~~

The workflow validates and smoke-tests the Release runtime, builds a Unicode
NSIS executable with forced CRC checking and solid LZMA compression, silently
extracts it to a path containing spaces and non-ASCII characters, verifies all
70 paths and hashes, and reruns the startup, SQLCipher, Brotli, TLS, and HTTPS
smoke checks from the extracted directory. A negative test also confirms that
a non-empty destination is rejected without modifying its sentinel file.

Outputs are written to:

~~~text
output\x64-shared-release\package\artifacts\
  DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe
  DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe.sha256

output\x64-shared-release\package\metadata\portable-sfx-manifest.txt
output\x64-shared-release\package\verify\portable-sfx\
~~~

Double-click the EXE and choose a new or empty user-writable directory. The
default is a versioned directory next to the self-extractor. The extraction is
staged in a reserved sibling directory and published only after every embedded
file has been written. Existing non-empty destinations, files, drive/share
roots, Windows directories, and Program Files trees are rejected.

For unattended extraction, `/D=` must be the final argument and must not be
quoted, even when its value contains spaces:

~~~cmd
DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe /S /D=F:\Portable Apps\SQLiteBrowser
~~~

The stable validation exit codes are 21 for an invalid path, 22 for a root,
23 for a protected system tree, 24 for an existing file, and 25 for a non-empty
directory. Extraction-stage failures use codes 31 through 40. Silent mode does
not display message boxes or launch the application.

Like the ZIP, this is install-free packaging, not a dedicated portable-settings
mode. Application settings can still use the normal registry or AppData paths.

## 10. Build the Release x64 MSI with WiX

The MSI uses the SDK-style project under `installer\windows\wix`. Visual Studio
2022 MSBuild restores the repository-pinned WiX SDK and UI extension from
NuGet. Do not install WiX globally, and do not use the legacy `candle.exe` or
`light.exe` scripts under `installer\windows`.

WiX 7 requires each developer or organisation to review and explicitly accept
its OSMF EULA. This repository does not accept the EULA automatically. After
reviewing the current terms at <https://wixtoolset.org/osmf/>, a developer who
is authorised to accept them can use a Developer Command Prompt for VS 2022:

~~~cmd
msbuild installer\windows\wix\SQLiteBrowser.Installer.wixproj ^
  -t:AcceptEula ^
  -p:EulaId=wix7
~~~

This is a one-time per-user, per-computer action. Do not add
`<AcceptEula>wix7</AcceptEula>` to the project unless the repository owner has
made and documented that licensing decision.

Build, smoke-test, package, and verify the MSI from the repository root:

~~~cmd
cmake --workflow --preset msi-release
~~~

The equivalent convenience entry point is:

~~~cmd
installer\windows\wix\build.cmd
~~~

The workflow:

1. configures and minimally builds the Release x64 application;
2. assembles the strict 70-file Release package runtime;
3. runs the restricted-`PATH` startup, SQLCipher, Brotli, TLS, and HTTPS smoke
   checks;
4. checks every runtime path and SHA-256 against `runtime-manifest.txt`;
5. restores the exactly pinned `WixToolset.Sdk` 7.0.0 and restores
   `WixToolset.UI.wixext` 7.0.0 using `packages.lock.json`;
6. builds the per-machine x64 MSI with VS2022 MSBuild;
7. performs an MSI administrative extraction and compares all application
   files with the validated runtime;
8. writes an MSI SHA-256 manifest while retaining the `.wixpdb` for diagnostics.

Outputs are written to:

~~~text
output\x64-shared-release\package\artifacts\
  DB.Browser.for.SQLCipher-4.0.0-win-x64.msi
  DB.Browser.for.SQLCipher-4.0.0-win-x64.wixpdb

output\x64-shared-release\package\metadata\msi-manifest.txt
output\x64-shared-release\package\verify\msi-admin-image\
~~~

The MSI uses WiX `MajorUpgrade`, rejects downgrades, and detects the historical
NSIS registry key in HKLM/HKCU 32-bit and 64-bit views. It asks the user to
uninstall a detected NSIS version first; it never launches an external
uninstaller from an MSI custom action.

The publication runtime explicitly excludes `vc_redist.x64.exe`, so ZIP, SFX,
and MSI do not distribute or execute the redistributable installer. No
app-local VC143 runtime is currently added in its place. A clean machine must
therefore already have a compatible Visual C++ Runtime until the app-local
runtime policy is implemented and verified.

## 11. Common build failures

| Symptom | Check |
| --- | --- |
| A submodule source file is missing | Run `git submodule update --init --recursive` from the repository root |
| Visual Studio is not found | Use a supported 2022 edition installed in its default directory and install the Desktop C++ workload |
| Windows SDK selection fails | Install SDK 10.0.26100.0 and confirm the Desktop C++ workload selected it |
| Perl or NASM is not found | Add the native Windows tools to `PATH`, then open a new `cmd.exe` |
| CMake cannot find Qt | Check that only `CMAKE_PREFIX_PATH` in the local `CMakePresets.json` points to Qt 6.11.1 `msvc2022_64` |
| A documented workflow preset is missing | Run `cmake --list-presets=all` and recreate the ignored local `CMakePresets.json` from the current template if it is stale |
| OpenSSL full tests report an IPv6 UDP conflict | Rebuild with the documented `safe` test mode |
| SQLCipher configure rejects OpenSSL | Rebuild Brotli, then OpenSSL, then SQLCipher in that order and do not mix Debug and Release stages |
| The application reports a missing Qt plugin or DLL | Re-run `cmake --build --preset <debug-or-release>` so the `POST_BUILD` deployment and validation run again |
| Package assembly rejects a file or hash | Re-run the matching product build and `package-*` workflow; do not copy the development `bin` manually |
| The HTTPS smoke test cannot connect | Check network access or set `SQLITEBROWSER_TLS_SMOKE_URL` to an approved reachable HTTPS endpoint |
| ZIP validation rejects the archive | Do not edit the ZIP manually; rebuild it with `zip-release` so it is regenerated from the validated runtime |
| Portable SFX cannot find NSIS | Install NSIS 3.12 at `C:\Program Files (x86)\NSIS`; the build intentionally does not search custom paths or download tools |
| Portable SFX rejects the destination | Select a new or empty user-writable subdirectory; roots, system trees, files, and non-empty directories are intentionally refused |
| Silent portable extraction ignores `/D=` | Keep `/D=<path>` unquoted and as the final argument; use a `.cmd` wrapper when another launcher rewrites quoting |
| MSI build reports WIX7015 | Review the WiX 7 OSMF EULA and have an authorised developer run the documented `AcceptEula` target; the project intentionally cannot bypass it |
| WiX restore cannot reach NuGet | Check access to `https://api.nuget.org/v3/index.json`; do not change the locked WiX version to work around a network failure |
| Package validation reports `vc_redist.x64.exe` | Reassemble `package\runtime`; the redistributable installer is forbidden in every published format even if it remains in development `bin` |

For the consolidated architecture, implementation history, validation results,
dependency boundaries, and troubleshooting guide, see the
[Windows v4 build upgrade report](../.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md).
For the current ZIP, portable NSIS SFX, WiX MSI, and legacy-install migration
decisions, see the
[Windows packaging plan](../.agents/reports/sqlitebrowser-v4.0.0-windows-packaging-plan.md).
