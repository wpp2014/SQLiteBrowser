# Windows x64 portable self-extracting EXE

Run from the repository root:

```cmd
cmake --workflow --preset portable-sfx-release
```

or run `installer\windows\nsis\build.cmd`.

The build requires NSIS 3.12 at
`C:\Program Files (x86)\NSIS\makensis.exe`. It consumes only the validated
Release `package\runtime`, creates an extraction-only EXE, silently extracts it
to a path containing spaces and non-ASCII characters, validates every file
against `runtime-manifest.txt`, and runs the restricted-`PATH` smoke suite from
the extracted copy. A separate negative test confirms that a non-empty target
directory is rejected without changing its sentinel file.

The SFX runs with user privileges and does not create an uninstaller, registry
entry, shortcut, file association, or `PATH` change. It is install-free, but it
does not enable a special portable settings mode in the application.
