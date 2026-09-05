# Windows x64 MSI

This directory contains the SDK-style WiX project used to build the Windows
x64 MSI. WiX is restored by Visual Studio 2022 MSBuild through NuGet; a global
WiX installation, `candle.exe`, and `light.exe` are not used.

The project deliberately does not accept the WiX 7 OSMF EULA on behalf of the
developer or organization. Review the EULA before accepting it. After that
one-time decision, run the MSI workflow from the repository root:

```cmd
cmake --workflow --preset msi-release
```

Alternatively run `build.cmd` from this directory. The workflow builds and
smoke-tests the Release runtime, validates `runtime-manifest.txt`, builds the
MSI, retains its `.wixpdb`, performs an administrative extraction, and compares
the extracted application files with the validated runtime.

Outputs are written below:

```text
output/x64-shared-release/package/
|- artifacts/
|- build/wix/
|- metadata/msi-manifest.txt
`- verify/msi-admin-image/
```

The MSI is x64, Release-only, and per-machine. If a historical NSIS installation
is detected, the MSI asks the user to uninstall it first; it never executes an
external uninstaller as a Windows Installer custom action.
