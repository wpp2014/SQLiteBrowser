# SQLCipher 构建脚本与项目 Skill 使用说明

> 适用项目：SQLiteBrowser `upgrade/v4.0.0`
>
> 适用平台：Windows x64
>
> SQLCipher：`v4.18.0` / `63697beb0fafcb61faa7a3e6fd267036548ab11b`
>
> OpenSSL：`openssl-3.5.7` / `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`、CMake 3.21 或更高版本

本文说明如何使用项目自带的 SQLCipher 构建脚本，以及如何在 Codex 和 Claude Code 中调用项目 Skill。SQLCipher 的构建原理、参数依据、产物和测试边界见 [sqlcipher-vs2022-build-analysis.md](sqlcipher-vs2022-build-analysis.md)。

## 1. 文件位置

```text
SQLiteBrowser/
|- third_party/sqlcipher/
|  |- build.cmd                         # 人和 AI 共用的构建入口
|  |- CMakeLists.txt                    # 独立 CMake 配置入口
|  |- cmake/BuildSQLCipher.cmake        # NMake 构建、校验和 stage helper
|  `- src/                              # 固定的 SQLCipher 上游子模块
|- .agents/skills/sqlitebrowser-build-sqlcipher/SKILL.md
|- .claude/skills/sqlitebrowser-build-sqlcipher/SKILL.md
`- build/
   |- sqlcipher-cmake/                  # Visual Studio CMake 生成目录
   `- sqlcipher/
      |- x64-debug/{work,stage}/
      `- x64-release/{work,stage}/
```

调用关系固定为：

```text
Skill
  -> third_party\sqlcipher\build.cmd
      -> CMake sqlcipher_stage
          -> BuildSQLCipher.cmake
              -> SQLCipher Makefile.msc / NMake
```

Skill 和 `build.cmd` 不维护第二份 NMake 参数。编译定义、CRT、OpenSSL 链接、产物复制和 provider 检查仍以 CMake wrapper 为准。

## 2. 前置条件

- Windows x64；
- Git，且 `git.exe` 在 `PATH`；
- CMake 3.21 或更高版本，且 `cmake.exe` 在 `PATH`；
- Windows PowerShell；
- 默认目录下的 Visual Studio 2022 Enterprise、Professional 或 Community；
- `Desktop development with C++`、MSVC v143 x64/x86 build tools；
- Windows SDK `10.0.22621.0`；
- 对应配置的项目 OpenSSL 3.5.7 stage。

脚本按以下顺序查找 Visual Studio，并固定同一实例用于环境初始化和 CMake generator：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

脚本不使用 `vswhere`，不搜索自定义安装目录，也不会自动安装缺失工具。仓库路径当前不能包含空格，这是底层 NMake wrapper 的明确限制。

## 3. 子模块与 OpenSSL

克隆或拉取代码后推荐先执行：

```cmd
git submodule update --init --recursive
```

实际构建时，如果 SQLCipher 源码未初始化，脚本会尝试初始化该子模块；`check` 模式只检查，不修改。脚本严格检查 SQLCipher commit 和工作区状态，不会自动 checkout、reset 或覆盖源码修改。

SQLCipher Debug 和 Release 必须分别使用：

```text
build\openssl\x64-debug\stage
build\openssl\x64-release\stage
```

缺少对应 stage 时，先运行：

```cmd
third_party\openssl\build.cmd debug safe
third_party\openssl\build.cmd release safe
```

SQLCipher 脚本不会静默构建 OpenSSL，也不会回退到系统 OpenSSL。它检查 OpenSSL 可执行文件、头文件、`libcrypto.lib`、`libcrypto-3-x64.dll`、版本和 CRT。

如果 stage 包含 `build-manifest.txt`，还会检查 OpenSSL tag、commit、配置和 Windows SDK。manifest 缺失时开发构建会警告并继续；正式发布前应使用 OpenSSL 项目脚本重新生成带 manifest 的 stage。

## 4. 直接使用构建脚本

脚本可以从仓库内任意工作目录调用。以下示例从仓库根目录执行。

查看帮助：

```cmd
third_party\sqlcipher\build.cmd --help
```

不带参数时构建 Debug 和 Release：

```cmd
third_party\sqlcipher\build.cmd
```

等价于：

```cmd
third_party\sqlcipher\build.cmd all
```

### 4.1 只检查环境

```cmd
third_party\sqlcipher\build.cmd check
third_party\sqlcipher\build.cmd debug check
third_party\sqlcipher\build.cmd release check
```

`check` 检查源码、CMake、VS、SDK、MSVC 工具和选中配置的 OpenSSL stage，不配置或构建 SQLCipher。

### 4.2 构建配置

```cmd
third_party\sqlcipher\build.cmd debug
third_party\sqlcipher\build.cmd release
third_party\sqlcipher\build.cmd all
```

脚本先固定 VS generator instance 和 SDK 配置 `build\sqlcipher-cmake`，再调用：

```cmd
cmake --build build\sqlcipher-cmake --config <Debug|Release> --target sqlcipher_stage
```

底层 helper 每次执行 NMake `clean` 后重新生成目标，Debug 和 Release 使用独立的 work 与 stage。

### 4.3 清理重建

```cmd
third_party\sqlcipher\build.cmd release clean
third_party\sqlcipher\build.cmd all clean
```

`clean` 只允许删除：

```text
build\sqlcipher-cmake
build\sqlcipher\x64-debug
build\sqlcipher\x64-release
```

它不会删除源码、OpenSSL stage 或其他项目构建目录。`check` 和 `clean` 不能同时使用。如果现有 CMake 目录由另一个 VS 实例生成，确认可丢弃忽略构建输出后再显式使用 `clean`。

## 5. 输出与验证

```text
build\sqlcipher\x64-debug\stage
build\sqlcipher\x64-release\stage
```

每个选中 stage 应包含：

```text
stage/
|- bin/{sqlcipher.dll,sqlcipher.exe}
|- include/sqlcipher/{sqlite3.h,sqlite3ext.h,sqlite3session.h}
|- lib/sqlcipher.lib
|- pdb/
`- build-manifest.txt
```

自动化检查 SQLCipher tag/commit、OpenSSL 3.5.7、`libcrypto-3-x64.dll` 依赖、Debug/Release CRT、`sqlcipher_version` 导出、CLI provider 输出、必需产物和 SHA-256。

运行 staged CLI 时需要匹配的 OpenSSL `bin`：

```cmd
set "PATH=%CD%\build\openssl\x64-release\stage\bin;%PATH%"
build\sqlcipher\x64-release\stage\bin\sqlcipher.exe :memory: "PRAGMA key='probe'; PRAGMA cipher_provider_version;"
```

## 6. 使用 Codex Skill

Codex 从仓库根目录 `.agents\skills` 发现项目 Skill。可以显式调用：

```text
$sqlitebrowser-build-sqlcipher 检查当前机器是否满足 SQLCipher Release 构建条件
```

```text
$sqlitebrowser-build-sqlcipher 构建 Debug 和 Release
```

```text
$sqlitebrowser-build-sqlcipher 对 Release 执行 clean 构建
```

也可以直接用自然语言请求。Skill 支持显式调用和基于 description 的自动匹配，相关机制见 [OpenAI 官方 Build skills 文档](https://learn.chatgpt.com/docs/build-skills)。只要求分析时，Skill 不得运行构建或修改文件。

如果新增 Skill 没有立即显示，重新打开任务或重启 Codex。

## 7. 使用 Claude Code Skill

Claude Code 兼容入口位于 `.claude\skills`：

```text
/sqlitebrowser-build-sqlcipher 检查 Release 构建环境
/sqlitebrowser-build-sqlcipher 构建全部配置
```

Claude 入口会读取 `.agents\skills\sqlitebrowser-build-sqlcipher\SKILL.md` 的规范内容，因此构建规则只维护一份。如果当前会话没有发现新 Skill，重启 Claude Code。

## 8. 测试与部署边界

当前产品 wrapper 固定使用 `NO_TCL=1`。它执行产物、依赖、CRT、导出符号和 CLI provider smoke check，但不会构建 `testfixture.exe`，也不会运行 `test/sqlcipher.test` 或 SQLite Tcl suite。

因此成功结果应表述为“SQLCipher 构建和 stage 验证通过”，不能表述为“SQLCipher 测试套件通过”。正式专项测试需要独立 Tcl test work 和 `SQLCIPHER_TEST=1` 构建。

当前“部署”只表示输出到 SQLCipher stage。脚本和 Skill 不会修改仓库根 CMake、`FindSQLCipher.cmake`、SQLiteBrowser 可执行目录、CI 或安装器。

## 9. 常见错误

### 找不到 CMake

```cmd
where cmake.exe
cmake --version
```

要求 CMake 3.21 或更高版本。

### OpenSSL stage 缺失或配置错误

不要混用 Debug 和 Release。使用对应的 OpenSSL 项目脚本重新生成。

### OpenSSL manifest 缺失

开发构建可以继续，但不具备完整的 OpenSSL tag/commit 构建记录；正式发布前应重新生成受验证的 stage。

### CMake generator instance 不匹配

确认旧的忽略构建输出可以删除后执行：

```cmd
third_party\sqlcipher\build.cmd <debug|release|all> clean
```

### SQLCipher 子模块版本不符或不干净

```cmd
git -C third_party\sqlcipher\src rev-parse HEAD
git -C third_party\sqlcipher\src status --short
```

脚本不会覆盖这些源码修改。

### 仓库路径包含空格

当前 NMake wrapper 明确拒绝源码、OpenSSL 和构建路径中的空格。请把仓库放在不含空格的路径下。
