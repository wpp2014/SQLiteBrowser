# SQLCipher 构建脚本与项目 Skill 使用说明

> 适用项目：SQLiteBrowser `upgrade/v4.0.0`
>
> 适用平台：Windows x64
>
> SQLCipher：`v4.18.0` / `63697beb0fafcb61faa7a3e6fd267036548ab11b`
>
> SQLite baseline：`3.53.4`
>
> OpenSSL：`openssl-3.5.7` / `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`
>
> Brotli：`v1.2.0` / `028fb5a23661f123017c060daa546b55cf4bde29`
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`、CMake 3.22 或更高版本

本文说明项目当前 SQLCipher 构建入口、输出、验证边界，以及 Codex/Claude Code Skill 的用法。设计依据和迁移分析见 [sqlcipher-vs2022-build-analysis.md](sqlcipher-vs2022-build-analysis.md)。

## 1. 当前构建模型

SQLCipher 的固定 tag 不包含可直接编译的 `sqlite3.c`、`sqlite3.h` 和 `shell.c`。项目采用以下职责划分：

```text
third_party\sqlcipher\build.cmd
  -> 配置专用 CMake work
      -> Makefile.msc + NMake：只生成 amalgamation、头文件和 shell.c
      -> CMake/MSBuild：编译并链接 sqlcipher.dll 与 sqlcipher.exe
      -> CTest：运行 shared/provider smoke test
      -> cmake --install：生成配置专用 stage
      -> build.cmd：运行特性、导出、CRT、依赖、manifest 审计
```

这不是逐行重写 SQLCipher/SQLite 的生成系统。上游 `Makefile.msc` 仍负责 Lemon、Jim Tcl、FTS5、header 和 amalgamation 生成；它不再编译或链接项目产品。产品 DLL、CLI、OpenSSL 链接、PDB 和安装规则由版本控制中的 CMake target 负责。

## 2. 文件和目录

```text
SQLiteBrowser/
|- third_party/sqlcipher/
|  |- build.cmd
|  |- CMakeLists.txt
|  `- src/                         # 固定上游 submodule，保持只读
|- .agents/skills/sqlitebrowser-build-sqlcipher/SKILL.md
|- .claude/skills/sqlitebrowser-build-sqlcipher/SKILL.md
`- build/sqlcipher/
   |- x64-debug/{work,stage}/
   `- x64-release/{work,stage}/
```

旧的 `cmake/BuildSQLCipher.cmake` 和共享 `build/sqlcipher-cmake` 已删除。Debug 与 Release 现在从配置、生成源码到 stage 完全隔离。

## 3. 前置条件

- Windows x64；
- Git、CMake 3.22+、CTest 和 `certutil.exe`；
- 默认目录中的 Visual Studio 2022 Enterprise、Professional 或 Community；
- Desktop development with C++、MSVC v143 x64/x86 build tools；
- Windows SDK `10.0.22621.0`；
- 与目标配置匹配、由项目脚本生成的 OpenSSL stage。

Visual Studio 查找顺序为：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

脚本固定 x64 host、x64 target 与 SDK，不使用 `vswhere`，也不搜索自定义 VS 安装目录。上游源码生成仍使用 `Makefile.msc`，因此仓库、work 和依赖路径暂不支持空格。

## 4. OpenSSL 与 Brotli 契约

配置必须一一对应：

```text
SQLCipher Debug   -> build/openssl/x64-debug/stage
SQLCipher Release -> build/openssl/x64-release/stage
```

OpenSSL 必须是项目固定的 3.5.7，并由当前 OpenSSL 脚本以 `enable-brotli-dynamic` 构建。SQLCipher 直接链接 `libcrypto.lib`，运行时依赖 `libcrypto-3-x64.dll`；Brotli 是 OpenSSL 的动态运行时契约，因此 OpenSSL stage 还必须包含：

```text
brotlicommon.dll
brotlidec.dll
brotlienc.dll
```

SQLCipher 构建要求 OpenSSL `build-manifest.txt` 存在，并核对 OpenSSL/Brotli tag、commit、配置、SDK 和动态 Brotli 选项。缺失时不再以“开发构建警告”继续。

如依赖缺失，先执行：

```cmd
third_party\openssl\build.cmd debug safe
third_party\openssl\build.cmd release safe
```

SQLCipher stage 不复制 OpenSSL 或 Brotli DLL。运行 staged CLI 时，将对应 OpenSSL `bin` 加入进程 PATH：

```cmd
set "PATH=%CD%\build\openssl\x64-release\stage\bin;%PATH%"
build\sqlcipher\x64-release\stage\bin\sqlcipher.exe :memory: "PRAGMA key='probe'; PRAGMA cipher_provider_version;"
```

## 5. 使用 build.cmd

查看帮助：

```cmd
third_party\sqlcipher\build.cmd --help
```

默认构建 Debug 和 Release：

```cmd
third_party\sqlcipher\build.cmd
third_party\sqlcipher\build.cmd all
```

单独构建：

```cmd
third_party\sqlcipher\build.cmd debug
third_party\sqlcipher\build.cmd release
```

只检查，不配置或编译：

```cmd
third_party\sqlcipher\build.cmd check
third_party\sqlcipher\build.cmd debug check
third_party\sqlcipher\build.cmd release check
```

显式清理选中配置的忽略构建输出后重建：

```cmd
third_party\sqlcipher\build.cmd debug clean
third_party\sqlcipher\build.cmd release clean
third_party\sqlcipher\build.cmd all clean
```

`clean` 只允许删除 `build/sqlcipher/x64-debug` 和/或 `x64-release`；不能与 `check` 同时使用，不影响源码与 OpenSSL stage。

## 6. 手工 CMake 调用

日常开发应使用 `build.cmd`。诊断 wrapper 时，每个配置必须使用独立 work：

```cmd
cmake -S third_party/sqlcipher -B build/sqlcipher/x64-release/work ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  "-DCMAKE_SYSTEM_VERSION=10.0.22621.0" ^
  "-DCMAKE_INSTALL_PREFIX=%CD%/build/sqlcipher/x64-release/stage" ^
  "-DSQLCIPHER_CONFIGURATION=Release" ^
  "-DSQLCIPHER_OPENSSL_ROOT=%CD%/build/openssl/x64-release/stage"

cmake --build build/sqlcipher/x64-release/work --config Release --parallel
ctest --test-dir build/sqlcipher/x64-release/work -C Release --output-on-failure
cmake --install build/sqlcipher/x64-release/work --config Release
```

不得在同一个 work 中切换 Debug/Release。CMake 将 `CMAKE_CONFIGURATION_TYPES` 固定为选中配置以防误用。

## 7. Stage 和 manifest

每个配置输出：

```text
stage/
|- bin/{sqlcipher.dll,sqlcipher.exe,sqlcipher.pdb,sqlcipher-cli.pdb}
|- include/sqlcipher/{sqlite3.h,sqlite3ext.h,sqlite3session.h}
|- lib/sqlcipher.lib
|- share/licenses/sqlcipher/{LICENSE.md,SQLITE_LICENSE.md}
|- provider-probe.txt
|- compile-options.txt
`- build-manifest.txt
```

两个 linker PDB 与对应的 DLL/CLI 一起部署到 `bin`。NMake 生成工具的 `lemon.pdb`、`mkkeywordhash.pdb`、`mksourceid.pdb`、`src-verify.pdb` 以及 compiler PDB 不进入 stage。

manifest 记录 SQLCipher/SQLite/OpenSSL/Brotli 版本、VS/MSVC/SDK/CMake、CRT、完整宏集合、OpenSSL manifest hash、三个产品文件 hash、CTest 和 Tcl 测试状态。

## 8. 自动验证

每次构建固定执行：

- CTest shared/provider smoke test；
- SQLCipher `4.18.0 community`、`openssl`、OpenSSL `3.5.7` provider 探测；
- 受控 `PRAGMA compile_options` 特性清单；
- x64、`libcrypto-3-x64.dll` 和动态 CLI→DLL 依赖；
- Debug `/MDd`、Release `/MD` CRT 审计；
- `sqlite3_open`、`sqlite3_key`、`sqlite3_rekey`、`sqlcipher_version` 导出；
- 必需文件、许可证、PDB、SHA-256 和 manifest；
- SQLCipher-only stage 中不得混入 OpenSSL/Brotli DLL。

产品 wrapper 使用 `NO_TCL=1`，不会构建 `testfixture.exe`，也不会运行 `test/sqlcipher.test` 或 SQLite Tcl suite。因此应表述为“CMake 构建、CTest provider smoke 和 stage 验证通过”，不能表述为“SQLCipher 官方测试套件通过”。

## 9. 使用 Codex 与 Claude Code Skill

Codex 示例：

```text
$sqlitebrowser-build-sqlcipher 检查 Release 构建环境
$sqlitebrowser-build-sqlcipher 构建 Debug 和 Release
$sqlitebrowser-build-sqlcipher 对 Release 执行 clean 构建
```

Claude Code 示例：

```text
/sqlitebrowser-build-sqlcipher 检查 Release 构建环境
/sqlitebrowser-build-sqlcipher 构建全部配置
```

两个入口最终都遵循 `.agents/skills/sqlitebrowser-build-sqlcipher/SKILL.md`，并以 `third_party/sqlcipher/build.cmd` 为命令真相源。只要求分析时，不运行构建或修改文件。

## 10. 部署边界

当前部署终点是配置专用 SQLCipher stage。该入口不修改仓库根 CMake、`FindSQLCipher.cmake`、SQLiteBrowser 运行目录、CI 或 NSIS。

最终应用部署必须从匹配配置的 OpenSSL stage 收集 Crypto/SSL/Brotli runtime，不能从系统 PATH 或 `C:\Program Files\OpenSSL-Win64` 回退。Debug 产物不得进入 Release 安装包。

## 11. 常见错误

### OpenSSL manifest 或 Brotli DLL 缺失

使用项目 OpenSSL 脚本重新生成对应配置；手工遗留 stage 不再接受。

### CMake generator/配置不匹配

确认选中配置的忽略构建输出可以删除后，使用：

```cmd
third_party\sqlcipher\build.cmd <debug|release> clean
```

### SQLCipher 子模块不正确或不干净

```cmd
git -C third_party\sqlcipher\src rev-parse HEAD
git -C third_party\sqlcipher\src describe --tags --exact-match
git -C third_party\sqlcipher\src status --short
```

脚本不会 checkout、reset 或覆盖子模块修改。

### 路径包含空格

当前限制来自上游 `Makefile.msc` 源码生成步骤，不来自 CMake 产品编译。请将仓库放在不含空格的路径。
