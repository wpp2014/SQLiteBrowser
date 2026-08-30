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
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`、CMake 3.22+
>
> 阶段 4 状态：已迁移到统一 `output/`，最小产品构建与 provider 测试已拆分

本文说明当前 SQLCipher 构建、测试、stage、manifest 和 Codex/Claude Skill 契约。历史设计分析见 [sqlcipher-vs2022-build-analysis.md](sqlcipher-vs2022-build-analysis.md)，统一输出决策见 [unified-output-and-minimal-build-plan.md](unified-output-and-minimal-build-plan.md)。

## 1. 当前构建模型

SQLCipher 固定 tag 不包含可直接编译的 amalgamation。项目保留上游生成器，但把产品编译交给 CMake：

```text
third_party\sqlcipher\build.cmd build <config>
  -> Makefile.msc + NMake 只生成 sqlite3.c、公开头文件和 shell.c
  -> CMake/MSBuild 只构建 sqlcipher target
  -> 安装 SQLCipherProduct component
  -> 写 build-manifest.txt（测试固定为 not run）
  -> 验证最小产品 stage

third_party\sqlcipher\build.cmd test <config>
  -> 验证已有产品 stage 和 build manifest
  -> 构建 EXCLUDE_FROM_ALL 的 sqlcipher_cli
  -> 运行 CTest provider smoke
  -> 用私有 CLI 加载已 stage 的 sqlcipher.dll 执行运行时探针
  -> 写绑定 build manifest SHA-256 的 test-manifest.txt
```

普通 `build` 不编译 CLI、CTest/provider smoke 或 Tcl 测试。测试失败不会被描述为产品编译失败；发布门禁可以单独要求有效的 `test-manifest.txt`。

## 2. 文件与输出目录

```text
SQLiteBrowser/
|- third_party/sqlcipher/
|  |- build.cmd
|  |- CMakeLists.txt
|  `- src/                              # 固定上游 submodule，保持只读
|- .agents/skills/sqlitebrowser-build-sqlcipher/SKILL.md
|- .claude/skills/sqlitebrowser-build-sqlcipher/SKILL.md
`- output/
   |- x64-shared-debug/build/sqlcipher/
   |  |- work/
   |  |  `- test-results/               # 只在 test 后产生
   |  `- stage/
   `- x64-shared-release/build/sqlcipher/
      |- work/
      `- stage/
```

Debug 和 Release 的生成源码、OBJ、CMake cache、测试工具、stage 与 manifest 完全隔离。阶段 5 已通过 `third_party\aggregate.cmd` 把已验证的私有 stage 汇总到配置级公共 `include/bin/metadata`。

## 3. 前置条件

- Windows x64；
- Git、CMake 3.22+；执行 `test` 时还需要 CTest；
- `certutil.exe`（build/test manifest SHA-256）；
- Visual Studio 2022 Enterprise、Professional 或 Community 默认安装目录；
- Desktop development with C++、MSVC v143 x64/x86 build tools；
- Windows SDK `10.0.26100.0`；
- 匹配配置、由本仓库脚本生成的 OpenSSL 3.5.7 最小 stage。

Visual Studio 查找顺序：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

脚本固定 x64 host/target 和 SDK，不搜索自定义 VS 安装目录。上游 `Makefile.msc` 生成步骤要求源码、work 和 OpenSSL stage 路径不含空格。

## 4. OpenSSL 与 Brotli 契约

```text
SQLCipher Debug
  -> output/x64-shared-debug/build/openssl/stage

SQLCipher Release
  -> output/x64-shared-release/build/openssl/stage
```

SQLCipher 链接 `libcrypto.lib`，运行时依赖 `libcrypto-3-x64.dll`。OpenSSL 使用 `enable-brotli-dynamic`，因此其同一 stage 还必须包含三个 Brotli DLL。SQLCipher 脚本核对 OpenSSL/Brotli tag、commit、配置、SDK、CRT 和 manifest，不回退到系统 OpenSSL，也不再要求已从最小 stage 排除的 `openssl.exe`。

依赖缺失时先执行：

```cmd
third_party\openssl\build.cmd build debug
third_party\openssl\build.cmd build release
```

SQLCipher 私有 stage 不复制 OpenSSL/Brotli DLL；配置级公共汇总负责组合依赖开发输出，最终应用运行时闭包仍由后续主程序部署阶段决定。

## 5. build.cmd 命令

```cmd
third_party\sqlcipher\build.cmd --help
third_party\sqlcipher\build.cmd check all
third_party\sqlcipher\build.cmd build debug
third_party\sqlcipher\build.cmd build release
third_party\sqlcipher\build.cmd test debug
third_party\sqlcipher\build.cmd test release
third_party\sqlcipher\build.cmd clean debug
third_party\sqlcipher\build.cmd clean release
```

动作语义：

| 动作 | 行为 |
| --- | --- |
| `check` | 只检查源码、工具链和匹配 OpenSSL stage，不生成构建文件 |
| `build` | 只构建 `sqlcipher.dll` 产品 target、重建 stage 并写 build manifest |
| `test` | 构建私有 CLI、运行 CTest 与 staged-product 探针，并写 test manifest |
| `clean` | 只删除所选配置的 `build/sqlcipher` 私有目录 |

默认是 `build all`。为兼容旧用法，省略动作的 `debug`、`release`、`all` 仍等价于对应 `build`。

## 6. 手工 CMake 诊断

日常使用脚本。诊断 Release wrapper 时可执行：

```cmd
cmake -S third_party/sqlcipher -B output/x64-shared-release/build/sqlcipher/work ^
  -G "Visual Studio 17 2022" -A x64 ^
  "-DCMAKE_SYSTEM_VERSION=10.0.26100.0" ^
  "-DCMAKE_INSTALL_PREFIX=%CD%/output/x64-shared-release/build/sqlcipher/stage" ^
  "-DSQLCIPHER_CONFIGURATION=Release" ^
  "-DSQLCIPHER_WINDOWS_SDK_VERSION=10.0.26100.0" ^
  "-DSQLCIPHER_OPENSSL_ROOT=%CD%/output/x64-shared-release/build/openssl/stage"

cmake --build output/x64-shared-release/build/sqlcipher/work ^
  --config Release --parallel --target sqlcipher
cmake --install output/x64-shared-release/build/sqlcipher/work ^
  --config Release --component SQLCipherProduct
```

测试 target 必须显式构建：

```cmd
cmake --build output/x64-shared-release/build/sqlcipher/work ^
  --config Release --parallel --target sqlcipher_cli
ctest --test-dir output/x64-shared-release/build/sqlcipher/work ^
  -C Release --output-on-failure
```

手工命令不会生成项目 build/test manifest；需要正式 stage 契约时仍应运行 `build.cmd`。

## 7. 产品 stage 与测试产物

普通 build 的最小 stage：

```text
stage/
|- bin/{sqlcipher.dll,sqlcipher.pdb}
|- include/sqlcipher/{sqlite3.h,sqlite3ext.h,sqlite3session.h}
|- lib/sqlcipher.lib
|- share/licenses/sqlcipher/{LICENSE.md,SQLITE_LICENSE.md}
`- build-manifest.txt
```

以下内容不得进入产品 stage：

- `sqlcipher.exe`、`sqlcipher-cli.pdb`；
- `provider-probe.txt`、`compile-options.txt`；
- OpenSSL/Brotli DLL；
- `vc143.pdb` 和 NMake 生成工具 PDB。

执行 test 后：

```text
work/test-results/
|- sqlcipher-provider-smoke.exe
|- provider-probe.txt
`- compile-options.txt

stage/test-manifest.txt
```

测试 CLI 和探针结果是私有测试产物，不进入未来公共 `bin`。

## 8. Manifest 与验证边界

`build-manifest.txt` 记录版本、工具链、配置、CRT、宏集合、OpenSSL manifest hash、产品文件 hash，并固定记录：

```text
CTest provider smoke: not run
Product runtime probes: not run
Tcl SQLCipher test suite: not run
```

`test-manifest.txt` 记录当前 build manifest SHA-256、CTest/provider/compile-options 探针结果和 Tcl suite 未运行边界。重新执行 build 会重建 stage 并删除旧 test manifest；test 开始时也会先移除旧记录，只有全部检查通过后才写新记录。

自动验证包括 x64、配置 CRT、`libcrypto-3-x64.dll` 依赖、SQLCipher 导出、最小 stage allowlist、OpenSSL/Brotli 配置匹配、provider 版本和编译选项。脚本使用 `NO_TCL=1`，不会运行 `test/sqlcipher.test` 或 SQLite Tcl suite，因此不能声称“SQLCipher 官方测试套件通过”。

## 9. 使用 Codex 与 Claude Skill

Codex：

```text
$sqlitebrowser-build-sqlcipher 检查 Debug 和 Release 环境
$sqlitebrowser-build-sqlcipher 最小构建 Release
$sqlitebrowser-build-sqlcipher 测试 Debug 和 Release provider
```

Claude Code：

```text
/sqlitebrowser-build-sqlcipher 最小构建 Release
/sqlitebrowser-build-sqlcipher 测试全部配置
```

两个入口都以 `third_party/sqlcipher/build.cmd` 为命令真相源。只要求分析时，Skill 不运行构建、不清理、不修改文件。`clean` 只有在用户明确选择或批准后执行。

## 10. 常见错误

### OpenSSL stage 缺失或 manifest 不匹配

用 `third_party\openssl\build.cmd build <config>` 重新生成 SDK 26100 的对应 stage。不要复制系统 OpenSSL 文件修补 stage。

### test 提示尚未构建

先执行 `third_party\sqlcipher\build.cmd build <config>`。测试必须绑定当前有效产品 stage。

### CMake generator/VS instance 不匹配

确认允许删除所选 SQLCipher 私有输出后执行 `clean <config>`，再重新 build。不要删除整个 `output/` 或其他依赖目录。

### SQLCipher 子模块不正确或不干净

```cmd
git -C third_party\sqlcipher\src rev-parse HEAD
git -C third_party\sqlcipher\src describe --tags --exact-match
git -C third_party\sqlcipher\src status --short
```

脚本不会 checkout、reset 或覆盖子模块修改。

## 11. 2026-08-30 实际验证

在 Visual Studio 2022 Enterprise、MSVC tools `14.44.35207`、CMake `3.30.3` 和 Windows SDK `10.0.26100.0` 下执行：

```cmd
third_party\sqlcipher\build.cmd check all
third_party\sqlcipher\build.cmd build all
third_party\sqlcipher\build.cmd test all
```

Debug 与 Release 最小产品构建、stage 审计均通过；两个配置的 CTest provider smoke 各 `1/1` 通过，staged-product provider 和 compile-options 探针通过。两个 test manifest 的 build-manifest SHA-256 均与当前 stage 实际哈希一致。产品 stage 未包含 CLI、CLI PDB、探针文本、OpenSSL/Brotli DLL 或 compiler/generator PDB。Tcl SQLCipher test suite 未运行。
