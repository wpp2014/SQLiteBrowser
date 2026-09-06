# Windows x64 ZIP package

Run from the repository root:

```cmd
cmake --workflow --preset zip-release
```

or run `installer\windows\zip\build.cmd`.

The Release-only workflow consumes the validated `package\runtime`, creates a
ZIP with one `DB Browser for SQLCipher` top-level directory, extracts it into a
separate verification directory, compares every file with
`runtime-manifest.txt`, and runs the complete restricted-`PATH` smoke suite from
the extracted copy.

The finished archive and its SHA-256 sidecar are written to
`output\x64-shared-release\package\artifacts`. This is an install-free archive,
not a guarantee that application settings never use the registry or AppData.
