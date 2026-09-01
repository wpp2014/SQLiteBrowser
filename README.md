# DB Browser for SQLite

[![Join the chat at https://gitter.im/sqlitebrowser/sqlitebrowser][gitter-img]][gitter]
[![Wiki][wiki-img]][wiki]
[![Patreon][patreon-img]][patreon]<br>
[![C/C++ CI][ghaction-img]][ghaction]
[![Qt][qt-img]][qt]<br>
[![CodeQL](https://github.com/sqlitebrowser/sqlitebrowser/actions/workflows/codeql.yml/badge.svg)](https://github.com/sqlitebrowser/sqlitebrowser/actions/workflows/codeql.yml)
[![Coverity][coverity-img]][coverity]<br>
[![Download][download-img]][download]
[![snapcraft](https://snapcraft.io/sqlitebrowser/badge.svg)](https://snapcraft.io/sqlitebrowser)
[![snapcraft](https://snapcraft.io/sqlitebrowser/trending.svg?name=0)](https://snapcraft.io/sqlitebrowser)

![DB Browser for SQLite Screenshot](https://github.com/sqlitebrowser/sqlitebrowser/raw/master/images/sqlitebrowser.png "DB Browser for SQLite Screenshot")

## Table of Contents
- [DB Browser for SQLite](#db-browser-for-sqlite)
  - [Table of Contents](#table-of-contents)
  - [What it is](#what-it-is)
  - [What it is not](#what-it-is-not)
  - [Wiki](#wiki)
  - [Continuous, Nightly builds](#continuous-nightly-builds)
  - [Windows](#windows)
      - [Continuous, Nightly builds](#continuous-nightly-builds-1)
  - [macOS](#macos)
      - [Stable release](#stable-release)
      - [Continuous, Nightly builds](#continuous-nightly-builds-2)
  - [Linux](#linux)
    - [Arch Linux](#arch-linux)
    - [Debian](#debian)
    - [Fedora](#fedora)
    - [openSUSE](#opensuse)
    - [Ubuntu and Derivatives](#ubuntu-and-derivatives)
      - [Stable release](#stable-release-1)
      - [Nightly builds](#nightly-builds)
    - [Other Linux](#other-linux)
  - [FreeBSD](#freebsd)
  - [Snap packages](#snap-packages)
      - [Snap Nightlies](#snap-nightlies)
      - [Snap Stable](#snap-stable)
  - [Nix Packages](#nix-packages)
    - [Flox](#flox)
  - [Compiling](#compiling)
    - [Windows v4 branch](#windows-v4-branch)
  - [X (Known as Twitter)](#x-known-as-twitter)
  - [Website](#website)
  - [Old project page](#old-project-page)
  - [Releases](#releases)
  - [History](#history)
  - [Contributors](#contributors)
  - [License](#license)

## What it is

_DB Browser for SQLite_ (DB4S) is a high quality, visual, open source tool to
create, design, and edit database files compatible with SQLite.

DB4S is for users and developers who want to create, search, and edit
databases.  DB4S uses a familiar spreadsheet-like interface, so complicated SQL commands do not have to be learned.

Controls and wizards are available for users to:

* Create and compact database files
* Create, define, modify and delete tables
* Create, define, and delete indexes
* Browse, edit, add, and delete records
* Search records
* Import and export records as text
* Import and export tables from/to CSV files
* Import and export databases from/to SQL dump files
* Issue SQL queries and inspect the results
* Examine a log of all SQL commands issued by the application
* Plot simple graphs based on table or query data

## What it is not

Even though DB4S comes with a spreadsheet-like interface, it is not meant to replace your spreadsheet application.
We implement a few convenience functions which go beyond a simple database frontend but do not add them when they
do not make sense in a database context or are so complex to implement that they will only ever be a poor
replacement for your favorite spreadsheet application. We are a small team with limited time after all. Thanks
for your understanding :)

## Wiki

For user and developer documentation, check out our Wiki at:
https://github.com/sqlitebrowser/sqlitebrowser/wiki.

## Continuous, Nightly builds

Download continuous builds for AppImage, macOS and Windows here:

* https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/continuous
> Note: A continuous build is generated when a new commit is added to the `master` branch.<br>

Download nightly builds for Windows and macOS here:

* https://nightlies.sqlitebrowser.org/latest

## Windows

Download Windows releases here:

* https://sqlitebrowser.org/dl/#windows

Or use Chocolatey:

```
choco install sqlitebrowser
```

Or use winget:

```
winget install -e --id DBBrowserForSQLite.DBBrowserForSQLite
```

Or use scoop:
```
scoop install sqlitebrowser
```

#### Continuous, Nightly builds

Continuous builds are available here:

* https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/continuous

Nightly builds are available here:
* https://nightlies.sqlitebrowser.org/latest

## macOS

DB Browser for SQLite works well on macOS.

* macOS 10.15 (Catalina) - 14.0 (Sonoma) are tested and known to work.

#### Stable release

Download macOS releases here:

* https://sqlitebrowser.org/dl/#macos

The latest macOS binary can be installed via [Homebrew Cask](https://caskroom.github.io/ "Homebrew Cask"):

```
brew install --cask db-browser-for-sqlite
```

#### Continuous, Nightly builds

Continuous builds are available here:

* https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/continuous

Nightly builds are available here:
* https://nightlies.sqlitebrowser.org/latest

and also you can be installed via [Homebrew Cask](https://caskroom.github.io/ "Homebrew Cask"):

```
brew tap homebrew/cask-versions

# for the version without SQLCipher support
brew install --cask db-browser-for-sqlite-nightly

# for the version with SQLCipher support
brew install --cask db-browser-for-sqlcipher-nightly
```

It also has its own Homebrew tap the include Cask for older version.<br>
For more information, see the following: https://github.com/sqlitebrowser/homebrew-tap

## Linux

DB Browser for SQLite works well on Linux.

### Arch Linux

Arch Linux provides an [up to date version](https://archlinux.org/packages/extra/x86_64/sqlitebrowser/)

Install with the following command:

    sudo pacman -S sqlitebrowser

### Debian

Debian focuses more on stability rather than newest features.<br>
Therefore packages will typically contain an older (but well tested) version, compared to the latest release.

Update the cache using:

    sudo apt-get update

Install the package using:

    sudo apt-get install sqlitebrowser

### Fedora

Install for Fedora (i386 and x86_64) by issuing the following command:

    sudo dnf install sqlitebrowser
    
### openSUSE

    sudo zypper install sqlitebrowser

### Ubuntu and Derivatives

#### Stable release

For Ubuntu and derivatives, [@deepsidhu1313](https://github.com/deepsidhu1313)
provides a PPA with the latest release here:

* https://launchpad.net/~linuxgndu/+archive/ubuntu/sqlitebrowser

To add this PPA just type in this command in terminal:

    sudo add-apt-repository -y ppa:linuxgndu/sqlitebrowser

Then update the cache using:

    sudo apt-get update

Install the package using:

    sudo apt-get install sqlitebrowser

Packages for Older Ubuntu releases are supported while launchpad keeps building those or if Older Ubuntu release has dependency packages that are required to build the latest version of Sqlitebrowser. We don't remove builds from our ppa repos, so users can still install older version of sqlitebrowser if they like. Alternatively Linux users can also switch to Snap packages if Snap packages are supported by the distro they are using.

#### Nightly builds

Nightly builds are available here:

* https://launchpad.net/~linuxgndu/+archive/ubuntu/sqlitebrowser-testing

To add this PPA, type these commands into the terminal:

    sudo add-apt-repository -y ppa:linuxgndu/sqlitebrowser-testing

Then update the cache using:

    sudo apt-get update

Install the package using:

    sudo apt-get install sqlitebrowser

### Other Linux

On others, compile DB4S using the instructions in [BUILDING.md](BUILDING.md).

## FreeBSD

DB Browser for SQLite works well on FreeBSD, and there is a port for it (thanks
to [lbartoletti](https://github.com/lbartoletti) :smile:).<br>DB4S can be installed
using either this command:

    make -C /usr/ports/databases/sqlitebrowser install

or this command:

    pkg install sqlitebrowser

## Snap packages

[![Get it from the Snap Store](https://snapcraft.io/static/images/badges/en/snap-store-black.svg)](https://snapcraft.io/sqlitebrowser)

#### Snap Nightlies

     snap install sqlitebrowser --edge

#### Snap Stable

     snap install sqlitebrowser

## Nix Packages

`sqlitebrowser` is packaged and available in nixpkgs.
It can be used with the experimental flakes and nix-command features with:

    nix profile install nixpkgs#sqlitebrowser

Or with the `nix-env` or `nix-shell` commands:

    nix-shell -p sqlitebrowser

### Flox

`sqlitebrowser` can be installed into a Flox environment with.

    flox install sqlitebrowser

## Compiling

The `upgrade/v4.0.0` branch currently supports Windows x64 only. It uses
Visual Studio 2022, Qt 6.11.1, the repository-pinned dependency sources, and
CMake Presets. The older cross-platform instructions in [BUILDING](BUILDING.md)
do not describe this branch.

### Windows v4 branch

The following procedure starts with a fresh clone and produces independently
configured Debug and Release development outputs, test outputs, and strict
package runtimes. Run all commands from the repository root in a regular
`cmd.exe` window. The dependency scripts locate and initialise Visual Studio
themselves, so a Developer Command Prompt is not required.

#### 1. Install the build tools

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

All migrated dependency scripts and the application use Windows SDK
10.0.26100.0.

NSIS is not required to compile or run the application. It will be needed
later for installer packaging.

You can check the command-line tools before cloning:

~~~cmd
git --version
cmake --version
ctest --version
perl --version
nasm -v
~~~

#### 2. Clone the repository and initialise submodules

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

#### 3. Build and publish the dependency stages

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

#### 4. Create the local CMake Preset file

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

#### 5. Configure and build the application

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

#### 6. Run the tests

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

#### 7. Assemble and smoke-test the package runtime

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
Debug and Release allowlists contain 70 and 71 files respectively. Release
also contains `vc_redist.x64.exe`; Debug is intended only for testing on a
machine with the matching development toolchain.

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

These directories are validated inputs for the future ZIP/NSIS process, not
finished release archives or installers. Packaging must consume
`package\runtime` and must not select files again from the development `bin`.

#### 8. Common build failures

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

For implementation details and dependency-specific diagnostics, see:

- [Main application CMake migration plan](docs/upgrade/v4.0.0/main-application-cmake-migration-plan.md)
- [Main application unified output guide](docs/upgrade/v4.0.0/main-application-unified-output-guide.md)
- [Main application unit-test workflow guide](docs/upgrade/v4.0.0/main-application-unit-test-workflow-guide.md)
- [Main application package runtime guide](docs/upgrade/v4.0.0/main-application-package-runtime-guide.md)
- [Unified output and minimal-build workflow](docs/upgrade/v4.0.0/unified-output-and-minimal-build-plan.md)
- [Phase 9 clean-build validation](docs/upgrade/v4.0.0/phase-9-clean-build-validation.md)
- [Dependency public aggregation guide](docs/upgrade/v4.0.0/dependency-public-aggregation-guide.md)
- [Brotli VS2022 build analysis](docs/upgrade/v4.0.0/brotli-vs2022-build-analysis.md)
- [OpenSSL build automation guide](docs/upgrade/v4.0.0/openssl-build-automation-guide.md)
- [SQLCipher build automation guide](docs/upgrade/v4.0.0/sqlcipher-build-automation-guide.md)

## X (Known as Twitter)

Follow us on X: https://x.com/sqlitebrowser

## Website

* https://sqlitebrowser.org

## Old project page

* https://sourceforge.net/projects/sqlitebrowser

## Releases

* [Version 3.13.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.13.1) - 2024-10-16
* [Version 3.13.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.13.0) - 2024-07-23
* [Version 3.12.2 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.12.2) - 2021-05-18
* [Version 3.12.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.12.1) - 2020-11-09
* [Version 3.12.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.12.0) - 2020-06-16
* [Version 3.11.2 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.11.2) - 2019-04-03
* [Version 3.11.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.11.1) - 2019-02-18
* [Version 3.11.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.11.0) - 2019-02-07
* [Version 3.10.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.10.1) - 2017-09-20
* [Version 3.10.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.10.0) - 2017-08-20
* [Version 3.9.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.9.1) - 2016-10-03
* [Version 3.9.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.9.0) - 2016-08-24
* [Version 3.8.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.8.0) - 2015-12-25
* [Version 3.7.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.7.0) - 2015-06-14
* [Version 3.6.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.6.0) - 2015-04-27
* [Version 3.5.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.5.1) - 2015-02-08
* [Version 3.5.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.5.0) - 2015-01-31
* [Version 3.4.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.4.0) - 2014-10-29
* [Version 3.3.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.3.1) - 2014-08-31 - Project renamed from "SQLite Database Browser"
* [Version 3.3.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/v3.3.0) - 2014-08-24
* [Version 3.2.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.2.0) - 2014-07-06
* [Version 3.1.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.1.0) - 2014-05-17
* [Version 3.0.3 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.0.3) - 2014-04-28
* [Version 3.0.2 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.0.2) - 2014-02-12
* [Version 3.0.1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.0.1) - 2013-12-02
* [Version 3.0 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/sqlb-3.0) - 2013-09-15
* [Version 3.0rc1 released](https://github.com/sqlitebrowser/sqlitebrowser/releases/tag/rc1) - 2013-09-09 - Project now on GitHub
* Version 2.0b1 released - 2009-12-10 - Based on Qt4.6
* Version 1.2 released - 2005-04-05
* Version 1.1 released - 2004-07-20
* Version 1.01 released - 2003-10-02
* Version 1.0 released to public domain - 2003-08-19

## History

This program was developed originally by Mauricio Piacentini
([@piacentini](https://github.com/piacentini)) from Tabuleiro Producoes as
the Arca Database Browser. The original version was used as a free companion
tool to the Arca Database Xtra, a commercial product that embeds SQLite
databases with some additional extensions to handle compressed and binary data.

The original code was trimmed and adjusted to be compatible with standard
SQLite 2.x databases. The resulting program was renamed SQLite Database
Browser, and released into the Public Domain by Mauricio. Icons were
contributed by [Raquel Ravanini](http://www.raquelravanini.com), also from
Tabuleiro. Jens Miltner ([@jmiltner](https://github.com/jmiltner)) contributed
the code to support SQLite 3.x databases for the 1.2 release.

Pete Morgan ([@daffodil](https://github.com/daffodil)) created an initial
project on GitHub with the code in 2012, where several contributors fixed and
improved pieces over the years. René Peinthor ([@rp-](https://github.com/rp-))
and Martin Kleusberg ([@MKleusberg](https://github.com/MKleusberg)) then
became involved, and have been the main driving force from that point.  Justin
Clift ([@justinclift](https://github.com/justinclift)) helps out with testing
on OSX, and started the new github.com/sqlitebrowser organisation on GitHub.

[John T. Haller](https://johnhaller.com), of
[PortableApps.com](https://portableapps.com) fame, created the new logo.  He
based it on the Tango icon set (public domain).

In August 2014, the project was renamed to "Database Browser for SQLite" at
the request of [Richard Hipp](https://www.hwaci.com/drh) (creator of
[SQLite](https://sqlite.org)), as the previous name was creating unintended
support issues.

In September 2014, the project was renamed to "DB Browser for SQLite", to
avoid confusion with an existing application called "Database Browser".

## Contributors

View the list by going to the [__Contributors__ tab](https://github.com/sqlitebrowser/sqlitebrowser/graphs/contributors).

## License

See the [LICENSE](LICENSE) file for licensing information.

  [gitter-img]: https://badges.gitter.im/sqlitebrowser/sqlitebrowser.svg
  [gitter]: https://gitter.im/sqlitebrowser/sqlitebrowser

  [slack-img]: https://img.shields.io/badge/chat-on%20slack-orange.svg
  [slack]: https://join.slack.com/t/db4s/shared_invite/enQtMzc3MzY5OTU4NDgzLWRlYjk0ZmE5ZDEzYWVmNDQxYTYxNmJjNWVkMjI3ZmVjZTY2NDBjODY3YzNhNTNmZDVlNWI2ZGFjNTk5MjJkYmU

  [download-img]: https://img.shields.io/github/downloads/sqlitebrowser/sqlitebrowser/total.svg
  [download]: https://github.com/sqlitebrowser/sqlitebrowser/releases

  [qt-img]: https://img.shields.io/badge/Qt-cmake-green.svg
  [qt]: https://www.qt.io

  [coverity-img]: https://img.shields.io/coverity/scan/11712.svg
  [coverity]: https://scan.coverity.com/projects/sqlitebrowser-sqlitebrowser

  [patreon-img]: https://img.shields.io/badge/donate-Patreon-coral.svg
  [patreon]: https://www.patreon.com/bePatron?u=11578749

  [wiki-img]: https://img.shields.io/badge/docs-Wiki-blue.svg
  [wiki]: https://github.com/sqlitebrowser/sqlitebrowser/wiki

  [ghaction-img]: https://github.com/sqlitebrowser/sqlitebrowser/actions/workflows/cppcmake.yml/badge.svg
  [ghaction]: https://github.com/sqlitebrowser/sqlitebrowser/actions/workflows/cppcmake.yml
