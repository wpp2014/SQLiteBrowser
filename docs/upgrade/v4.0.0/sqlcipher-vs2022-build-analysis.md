# SQLCipher 4.18.0 使用 Visual Studio 2022 构建分析

> 2026-08-30 更新：阶段 4 已完成统一输出与最小构建迁移。当前 SDK、命令、stage、CLI/provider 测试和 build/test manifest 契约以 [SQLCipher 构建脚本与项目 Skill 使用说明](sqlcipher-build-automation-guide.md) 为准；本文中的 SDK 22621、旧 `build/` 路径及“构建时自动测试”内容保留为历史分析记录。

> 文档性质：构建分析与 CMake/MSBuild 包装器实施说明
>
> 最后更新：2026-08-26
>
> 源码位置：`third_party/sqlcipher/src`
>
> SQLCipher：`v4.18.0` / `63697beb0fafcb61faa7a3e6fd267036548ab11b`
>
> SQLite baseline：`3.53.4`
>
> 目标平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`
>
> 加密 provider：项目源码构建的 OpenSSL `openssl-3.5.7`

本文以 [`third_party/sqlcipher/src/README.md`](../../../third_party/sqlcipher/src/README.md) 为入口，并核对了 `Makefile.msc`、`doc/compile-for-windows.md`、OpenSSL provider 源码、当前 Windows CI 和 `FindSQLCipher.cmake`。日常构建脚本与 Codex/Claude Skill 的操作说明见 [sqlcipher-build-automation-guide.md](sqlcipher-build-automation-guide.md)。

初次分析阶段没有执行 SQLCipher 的生成、编译、链接、测试或部署。后续已经完成两轮实现：第一轮由 CMake 间接驱动完整 NMake 产品构建；本轮改为 NMake 只生成上游源码、CMake/MSBuild 直接编译产品。SQLCipher 子模块、仓库根 CMake、CI 和安装器仍未修改；最终验证范围见第 18.4 节。

## 1. 结论摘要

SQLCipher 4.18.0 不能像普通、已带 CMake 的依赖那样直接 `add_subdirectory(src)`，但产品编译可以由项目 CMake target 接管。最终职责划分为：

```text
OpenSSL 3.5.7 Debug/Release stage
              |
              v
VS2022 x64 + SDK 10.0.22621.0
              |
              v
Makefile.msc + NMake（只生成 amalgamation/header/shell）
              |
              v
CMake/MSBuild（编译、链接、CTest、install）
              |
              v
sqlcipher.dll + sqlcipher.lib + headers
              |
              v
configuration-specific SQLCipher stage
              |
              v
SQLiteBrowser CMake imported target
```

推荐方案是：

- 只支持 Windows x64；
- 使用 VS2022 默认安装目录中的 Enterprise、Professional 或 Community；
- 通过 `VsDevCmd.bat` 固定 x64 host、x64 target 和 SDK `10.0.22621.0`；
- 使用 `Makefile.msc` 和 NMake 生成 `sqlite3.c`、公开头文件与 `shell.c`；
- 使用 CMake/MSBuild 编译和链接 `sqlcipher.dll`、`sqlcipher.lib` 与 `sqlcipher.exe`；
- 使用 amalgamation 构建；
- 生成 `sqlcipher.dll` 和 `sqlcipher.lib`，保持与当前项目 finder、CI 和安装器命名一致；
- 显式设置 SQLCipher 必需宏；
- 只链接相同配置的 OpenSSL 3.5.7 `libcrypto.lib`；
- 设置 `USE_CRT_DLL=1`，使 Release 使用 `/MD`、Debug 使用 `/MDd`；
- Debug 和 Release 使用独立 work/stage；
- Debug 和 Release 均使用配置专用 CMake work，并已完成闭环；
- 产品构建与带 `SQLCIPHER_TEST` 的测试构建分离；
- 不在 SQLCipher 源码目录生成任何文件。

## 2. README 给出的硬性要求

SQLCipher README 说明，构建过程与 SQLite 类似，但至少必须满足：

1. 定义 `SQLITE_HAS_CODEC`；
2. 定义 `SQLITE_TEMP_STORE=2` 或 `3`；
3. 定义 `SQLITE_EXTRA_INIT=sqlcipher_extra_init`；
4. 定义 `SQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown`；
5. 定义 `SQLITE_THREADSAFE=1` 或 `2`；
6. 编译并链接受支持的加密 provider。

当前 `Makefile.msc` 已固定：

```text
SQLITE_THREADSAFE=1
```

其余四个 SQLCipher 必需宏应在构建命令中显式传入。v4.18.0 的 `src/sqlcipher.c` 会对 extra-init、extra-shutdown、threadsafe 和 temp-store 进行编译期检查，遗漏时应直接编译失败。

虽然没有显式选择 provider 时源码会默认定义 `SQLCIPHER_CRYPTO_OPENSSL`，项目构建仍应明确传入：

```text
SQLCIPHER_CRYPTO_OPENSSL=1
```

这样可以让构建清单和编译命令明确记录 provider，避免将来新增 provider 后发生静默变化。

## 3. Windows 构建入口

README 中的 `./configure` 和 `make` 示例面向 Unix-like 环境，不能直接用于本项目 Windows 构建。

SQLCipher 合并的 SQLite Windows 文档给出的 MSVC 入口是：

```cmd
nmake /f Makefile.msc <target>
```

常用目标包括：

- `sqlite3.c`：生成 amalgamation；
- `sqlite3.h`、`sqlite3ext.h`、`sqlite3session.h`：生成或复制公开头文件；
- `sqlite3.dll`：生成 DLL 和 import library；
- `sqlite3.exe`：生成命令行程序；
- `testfixture.exe`：生成 Tcl 测试程序。

本项目应通过 Makefile 变量把产物重命名为：

```text
SQLITE3DLL=sqlcipher.dll
SQLITE3LIB=sqlcipher.lib
SQLITE3EXE=sqlcipher.exe
```

这与现有 `.github/workflows/cppcmake-windows.yml`、`cmake/FindSQLCipher.cmake` 和 Windows 安装器期望的命名一致。

## 4. Visual Studio、SDK 与 CRT

SQLCipher 的 Windows 文档要求在 x64 Native Tools 环境中运行，普通 CMD 或 PowerShell 中默认没有完整的 `cl`/`link`/`nmake` 环境。

项目后续脚本应沿用 OpenSSL 脚本的约束，只检查默认目录：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

并调用：

```cmd
call "<VS_ROOT>\Common7\Tools\VsDevCmd.bat" ^
  -no_logo ^
  -arch=x64 ^
  -host_arch=x64 ^
  -winsdk=10.0.22621.0
```

必须检查：

```text
VSCMD_ARG_HOST_ARCH=x64
VSCMD_ARG_TGT_ARCH=x64
WindowsSDKVersion=10.0.22621.0\
```

### 4.1 必须覆盖 Makefile 的默认 CRT

`Makefile.msc` 默认值是：

```text
USE_CRT_DLL=0
```

因此默认 Release 使用 `/MT`，Debug 使用 `/MTd`。这与 Qt 6、SQLiteBrowser 和当前 OpenSSL shared 构建不一致。

本项目必须设置：

```text
USE_CRT_DLL=1
```

结果为：

| 配置 | SQLCipher | OpenSSL | 允许用途 |
|---|---|---|---|
| Release | `/MD` | `/MD` | 开发、CI、正式发布 |
| Debug | `/MDd` | `/MDd` | 开发和调试，不进入正式安装包 |

不能把 Debug SQLCipher 链接到 Release OpenSSL，也不能把 Release SQLCipher 链接到 Debug OpenSSL。

## 5. OpenSSL 3.5.7 兼容性

SQLCipher v4.18.0 的参考 OpenSSL provider 位于：

```text
third_party/sqlcipher/src/src/crypto_openssl.c
```

该实现使用：

- `EVP_MAC_fetch`、`EVP_MAC_CTX` 和 `OSSL_PARAM`；
- AES-256-CBC；
- PBKDF2；
- HMAC SHA-1、SHA-256 和 SHA-512；
- `RAND_bytes`；
- OpenSSL runtime version API。

这些路径与 OpenSSL 3.5.7 default provider 兼容。SQLCipher 数据库加密只需要：

```text
libcrypto.lib
libcrypto-3-x64.dll
```

它不直接链接 `libssl.lib`，也不需要 `libssl-3-x64.dll`。后者仍是 Qt OpenSSL TLS backend 的运行时依赖，应在最终应用 stage 中与同一次 OpenSSL 构建一起部署。

不要定义源码中出现但本仓库没有对应 community provider 实现的 `SQLCIPHER_CRYPTO_OSSL3`。当前 community 构建应使用：

```text
SQLCIPHER_CRYPTO_OPENSSL=1
```

SQLCipher 使用的 AES、PBKDF2、HMAC 和随机数能力来自 OpenSSL default provider，不要求部署 `legacy.dll`。使用 OpenSSL 3.5.7 也不会自动获得 FIPS 认证；SQLCipher 参考 provider 的 `fips_status` 返回未启用状态。

## 6. OpenSSL 前置条件

推荐的 SQLCipher 构建必须先完成对应配置的 OpenSSL 构建：

```cmd
third_party\openssl\build.cmd release safe
third_party\openssl\build.cmd debug safe
```

预期输入分别为：

```text
build/openssl/x64-release/stage
build/openssl/x64-debug/stage
```

每个配置至少需要：

```text
include/openssl/opensslv.h
lib/libcrypto.lib
bin/libcrypto-3-x64.dll
build-manifest.txt
```

本次只读检查确认 Debug 和 Release stage 中前三项均存在，但两个 stage 当前都没有 `build-manifest.txt`。这说明现有手工产物可用于本机试验，但还不是由项目自动化完成并记录来源的正式输入。

正式构建 SQLCipher 前，应让 OpenSSL 构建脚本完整执行到 stage 验证和 manifest 生成，而不是只根据文件存在判断来源可信。

OpenSSL 构建脚本使用 `setlocal`，运行结束后不会把 VS 环境保留给调用者。因此未来 SQLCipher 脚本不能依赖“先运行 OpenSSL 脚本”来继承 `cl`/`nmake` 环境；它必须自行初始化 VS，或以后抽取项目共用的 VS 环境辅助脚本。

## 7. 推荐目录布局

SQLCipher 源码子模块必须保持只读和干净：

```text
SQLiteBrowser/
|- third_party/
|  |- sqlcipher/
|     |- src/                        # 上游源码，只读
|- build/
   |- sqlcipher/
      |- x64-release/
      |  |- work/                    # nmake 工作目录
      |  |- stage/
      |     |- bin/
      |     |- include/sqlcipher/
      |     |- lib/
      |- x64-debug/
         |- work/
         |- stage/
            |- bin/
            |- include/sqlcipher/
            |- lib/
```

`Makefile.msc` 的 `TOP` 默认是当前目录，但 NMake 命令行可以覆盖它。当前 wrapper 从配置专用 CMake work 的 `generated/` 目录调用源码树中的 Makefile，并把 `TOP` 指向子模块根目录。NMake 只生成源码，不再生成 SQLCipher 产品二进制。

在实现自动化前必须实际验证一次这种源码外构建。上游 Makefile 中存在未统一引用引号的路径表达式，第一版脚本建议检测并拒绝带空格的仓库路径，直到路径带空格场景完成验证。当前路径 `F:\open-source\SQLiteBrowser` 不包含空格。

## 8. 历史 Release x64 NMake 基线

以下命令记录了第一轮完整 NMake 产品构建的参数来源，已经不再作为当前入口执行。保留它用于审查功能宏、CRT 和 OpenSSL 链接语义；当前等价实现见第 18 节。

```cmd
set "PROJECT_ROOT=F:\open-source\SQLiteBrowser"
set "SQLCIPHER_SRC=%PROJECT_ROOT%\third_party\sqlcipher\src"
set "SQLCIPHER_WORK=%PROJECT_ROOT%\build\sqlcipher\x64-release\work"
set "SQLCIPHER_STAGE=%PROJECT_ROOT%\build\sqlcipher\x64-release\stage"
set "OPENSSL_STAGE=%PROJECT_ROOT%\build\openssl\x64-release\stage"

set "SQLCIPHER_REQUIRED=-DSQLITE_HAS_CODEC=1 -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLCIPHER_CRYPTO_OPENSSL=1"
set "SQLCIPHER_FEATURES=-DSQLITE_ENABLE_FTS3=1 -DSQLITE_ENABLE_FTS5=1 -DSQLITE_ENABLE_FTS3_PARENTHESIS=1 -DSQLITE_ENABLE_STAT4=1 -DSQLITE_SOUNDEX=1 -DSQLITE_ENABLE_JSON1=1 -DSQLITE_ENABLE_GEOPOLY=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_ENABLE_MATH_FUNCTIONS=1 -DSQLITE_MAX_ATTACHED=125"

if not exist "%SQLCIPHER_WORK%" mkdir "%SQLCIPHER_WORK%"
pushd "%SQLCIPHER_WORK%"

set "PATH=%OPENSSL_STAGE%\bin;%PATH%"

nmake /nologo /f "%SQLCIPHER_SRC%\Makefile.msc" ^
  TOP=%SQLCIPHER_SRC% ^
  PLATFORM=x64 ^
  USE_AMALGAMATION=1 ^
  USE_CRT_DLL=1 ^
  NO_TCL=1 ^
  DYNAMIC_SHELL=1 ^
  DEBUG=0 ^
  SQLITE3DLL=sqlcipher.dll ^
  SQLITE3LIB=sqlcipher.lib ^
  SQLITE3EXE=sqlcipher.exe ^
  "TCCOPTS=-I%OPENSSL_STAGE%\include" ^
  "LTLIBPATHS=/LIBPATH:%OPENSSL_STAGE%\lib" ^
  "LTLIBS=libcrypto.lib" ^
  "OPTS=%SQLCIPHER_REQUIRED% %SQLCIPHER_FEATURES%" ^
  sqlcipher.dll sqlcipher.exe sqlite3.h sqlite3ext.h sqlite3session.h

popd
```

说明：

- `NO_TCL=1` 只关闭外部 Tcl 依赖，不影响生成 DLL、CLI 和公开头文件；
- `DYNAMIC_SHELL=1` 让 `sqlcipher.exe` 通过 `sqlcipher.lib` 使用 DLL，便于验证真实部署关系；
- `LTLIBS=libcrypto.lib` 只把 OpenSSL Crypto 加入链接步骤，不应使用 `TLIBS` 把 import library 混入 `libsqlite3.lib` 归档规则；
- 当前不启用 zlib、ICU、RPCRT4 或 UWP；若以后启用，需要重新审查 `LTLIBS` 的组合方式；
- `SQLITE_ENABLE_JSON1` 对当前 SQLite baseline 可能已是兼容性空操作，第一阶段可以保留以对齐现有 CI 命令；
- `SQLITE_ENABLE_MATH_FUNCTIONS` 应补入 SQLCipher 构建，使 SQLCipher-enabled 应用与普通 SQLite 构建功能一致。

当前完整宏列表集中在 `third_party/sqlcipher/CMakeLists.txt`，同一列表同时传给上游源码生成和 CMake 产品 target，并写入 manifest；脚本和文档不再维护第二份可执行参数。

## 9. Debug x64 差异

Debug 必须使用完全独立的 CMake work、generated 目录、stage 和 OpenSSL Debug stage：

```text
SQLCIPHER_WORK=build/sqlcipher/x64-debug/work
SQLCIPHER_STAGE=build/sqlcipher/x64-debug/stage
OPENSSL_STAGE=build/openssl/x64-debug/stage
SQLCIPHER_CONFIGURATION=Debug
CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDebugDLL
`Makefile.msc` source generation: DEBUG=3, USE_CRT_DLL=1
```

`DEBUG=3` 只用于生成上游 Debug 语义的 amalgamation；CMake Debug target 负责 `/MDd`、断言、诊断、编译与 linker PDB。

如果只需要接近 Release 逻辑但带符号的诊断构建，可以在后续脚本设计时评估 `DEBUG=2`；第一版应固定单一 Debug 语义，不能让不同开发人员自行选择导致产物不可比较。

Debug DLL 依赖 `VCRUNTIME140D.dll` 和 Debug UCRT，只能在安装相应开发运行库的机器上使用，不能进入正式 MSI 或 portable ZIP。

## 10. Stage 规范

CMake/MSBuild 编译和 CTest 成功后，项目脚本通过 `cmake --install` 生成配置专用 stage，而不是把 work 目录直接交给主工程：

```text
stage/
|- bin/
|  |- sqlcipher.dll
|  |- sqlcipher.exe                 # 开发和验证工具，可不进入最终产品
|  |- sqlcipher.pdb                 # DLL linker PDB
|  |- sqlcipher-cli.pdb             # CLI linker PDB
|- include/
|  |- sqlcipher/
|     |- sqlite3.h
|     |- sqlite3ext.h
|     |- sqlite3session.h           # 仅在下游需要 session API 时保留
|- lib/
|  |- sqlcipher.lib
|- build-manifest.txt
```

stage 只保留 `bin/sqlcipher.pdb` 与 `bin/sqlcipher-cli.pdb` 两个 linker PDB，并与对应运行时产物放在同一目录。NMake 生成工具和 compiler PDB 留在 work，不得进入 stage；最终用户安装包是否携带符号由后续打包策略决定。

`libcrypto-3-x64.dll` 以及 OpenSSL 动态加载的三个 Brotli DLL，其权威来源仍是匹配配置的 OpenSSL stage。SQLCipher-only stage 明确禁止复制这些 DLL；运行验证通过进程 PATH 引用 OpenSSL stage。

manifest 至少记录：

- SQLCipher tag、commit 和 SQLite baseline；
- OpenSSL tag、commit、stage 和 manifest hash；
- VS edition、MSVC toolset、`cl` 版本和 SDK；
- Debug/Release、CRT、target；
- 完整宏列表；
- 产物 SHA-256；
- 是否执行 SQLCipher 专项测试；
- 测试使用的 Tcl 版本。

## 11. 测试方案

### 11.1 不使用完整 SQLite suite 作为唯一门禁

SQLCipher README 明确说明，完整 SQLite test suite 在 SQLCipher 构建下不会全部成功。加密会影响直接读取数据库文件内容或假定普通 SQLite 行为的底层测试，单个失败还可能导致后续级联失败。

因此不能把：

```cmd
nmake test
```

的结果简单解释为 SQLCipher 产品质量结论。

### 11.2 SQLCipher 专项测试

官方建议编译时增加：

```text
SQLCIPHER_TEST=1
```

然后构建 `testfixture.exe` 并执行：

```cmd
testfixture.exe <SQLCIPHER_SRC>\test\sqlcipher.test
```

Windows 的 `testfixture.exe` 需要 Tcl interpreter、headers 和 import libraries。当前机器没有发现 `tclsh.exe`、`tclsh90.exe`、`tclsh86.exe`，也不存在 `C:\Tcl`。因此：

- 当前可以分析并实现 `NO_TCL=1` 的产品构建；
- 当前不能宣称完成 SQLCipher 官方专项测试；
- 在正式验收前需要增加 x64 Tcl 开发环境，并记录其版本；
- 测试构建应使用独立 work 目录，不能把 `SQLCIPHER_TEST` 编进正式产品 DLL。

### 11.3 无 Tcl 的基础 smoke test

构建 `sqlcipher.exe` 后，可以先执行不替代官方专项测试的基础检查：

```cmd
set "PATH=<SQLCIPHER_STAGE>\bin;<OPENSSL_STAGE>\bin;%PATH%"

sqlcipher.exe :memory: "PRAGMA cipher_version;"
sqlcipher.exe :memory: "PRAGMA cipher_provider;"
sqlcipher.exe :memory: "PRAGMA cipher_provider_version;"
sqlcipher.exe :memory: "PRAGMA compile_options;"
```

还应验证：

- 新建 SQLCipher 4 加密数据库；
- 正确密码读取、修改并重开；
- 错误密码明确失败；
- `PRAGMA cipher_integrity_check`；
- `PRAGMA integrity_check`；
- rekey 后新密码有效、旧密码失效；
- 不设置 key 时打开普通 SQLite 数据库；
- 打开当前 v3.13.1/SQLCipher 4.6.1 生成的实际用户样本；
- FTS3/FTS5、RTREE、GEOPOLY、JSON、数学函数、SOUNDEX、STAT4 和最大 ATTACH 数。

SQLCipher README 承诺同一 major version 内保持数据库格式兼容，但 SQLCipher 3 与 4 默认参数不同。SQLiteBrowser 已提供 SQLCipher 3/4 compatibility 选项，升级验证必须覆盖旧格式，而不能只测试新建数据库。

## 12. 二进制验证

至少检查：

```cmd
dumpbin /headers sqlcipher.dll
dumpbin /dependents sqlcipher.dll
dumpbin /dependents sqlcipher.exe
dumpbin /exports sqlcipher.dll
```

Release 验收：

- machine 是 x64；
- 直接依赖 `libcrypto-3-x64.dll`；
- 不依赖 OpenSSL 4 DLL；
- 不依赖 `VCRUNTIME140D.dll` 或 `ucrtbased.dll`；
- 导出 `sqlite3_open`、`sqlite3_key`、`sqlite3_rekey` 等所需 API；
- 运行时从项目 OpenSSL stage 加载 `libcrypto-3-x64.dll`；
- 移除该 DLL 后应明确启动失败，不能回退到系统 OpenSSL；
- SQLCipher 源码子模块仍为干净状态。

Debug 验收：

- 直接依赖 Debug OpenSSL `libcrypto-3-x64.dll`；
- 依赖 Debug CRT；
- 不加载 Release OpenSSL DLL；
- PDB 与对应二进制一起归档。

## 13. 当前项目集成差距

当前 `CMakeLists.txt` 在 `sqlcipher` 为真时会：

```text
定义 ENABLE_SQLCIPHER
find_package(SQLCipher REQUIRED)
链接 SQLCipher::SQLCipher
```

当前 `cmake/FindSQLCipher.cmake` 仍有以下问题：

1. 只查找单一 `lib/sqlcipher.lib`，没有 Debug/Release imported locations；
2. imported target 类型和 Windows DLL/import library 关系没有完整表达；
3. 不记录 `sqlcipher.dll` 位置，安装器需要再次按文件名查找；
4. interface definition 写成了 `SQLITE_TEMPSTORE=2`，正确名称应为 `SQLITE_TEMP_STORE=2`；
5. OpenSSL 静态/动态传递依赖和最终运行时部署边界没有区分；
6. 当前 Windows CI 仍下载 SQLCipher 4.6.1，而不是使用 v4.18.0 子模块；
7. 当前 CI 构建命令没有显式传入 v4.18.0 现在会检查的 extra-init/extra-shutdown 宏；
8. 当前 CI 使用 VS2019 和外部 OpenSSL 布局，与目标 VS2022/SDK/OpenSSL stage 不一致。

这些内容属于后续集成阶段。本次只记录，不修改。

推荐未来 imported target 表达：

```text
SQLCipher::SQLCipher
  INTERFACE_INCLUDE_DIRECTORIES
  IMPORTED_IMPLIB_DEBUG
  IMPORTED_IMPLIB_RELEASE
  IMPORTED_LOCATION_DEBUG
  IMPORTED_LOCATION_RELEASE
  INTERFACE_COMPILE_DEFINITIONS=SQLITE_HAS_CODEC
```

对于 shared SQLCipher，主程序链接 import library 时通常不需要再次链接 `OpenSSL::Crypto`；运行时必须部署同一 OpenSSL `libcrypto` DLL。若以后支持 SQLCipher static library，则 `OpenSSL::Crypto` 必须作为传递链接依赖。

## 14. 风险清单

| 风险 | 后果 | 建议 |
|---|---|---|
| 直接照搬 README 的 Unix configure 命令 | Windows 构建入口错误 | 使用 `Makefile.msc` 和 `nmake` |
| 遗漏 extra-init/shutdown 宏 | v4.18.0 编译失败 | 显式固定全部必需宏 |
| 使用默认 `USE_CRT_DLL=0` | `/MT` 与 Qt/OpenSSL `/MD` 混用 | 强制 `USE_CRT_DLL=1` |
| Debug/Release 共用 work | 对象、PDB、CRT 和 OpenSSL 混用 | 每个配置独立 work/stage |
| 使用系统 OpenSSL 或 OpenSSL 4 | ABI、来源和部署失控 | 只消费项目 OpenSSL 3.5.7 stage |
| 把 `libssl` 当成 SQLCipher 依赖 | 多余链接和错误部署判断 | SQLCipher 只链接 Crypto |
| 定义 `SQLCIPHER_CRYPTO_OSSL3` | community 源码没有对应实现 | 使用 `SQLCIPHER_CRYPTO_OPENSSL` |
| 产品 DLL 启用 `SQLCIPHER_TEST` | 测试接口进入发布物 | 使用独立测试构建 |
| 没有 Tcl 却宣称测试通过 | 缺失 SQLCipher 官方专项验证 | 安装 Tcl 后运行 `sqlcipher.test` |
| 依赖完整 SQLite suite 全绿 | 已知不兼容测试造成误判 | 以 SQLCipher 专项测试和功能测试为门禁 |
| 在子模块目录构建 | 污染 submodule，难以清理 | 使用源码外 work |
| 仓库路径含空格 | 上游 Makefile 未统一引用路径 | 第一版脚本检测并拒绝，验证后再放开 |
| Finder 继续使用单配置路径 | Debug/Release 链错库 | 改成 per-config imported target |
| 只验证 DLL 存在 | 可能加载错误 OpenSSL/CRT | 使用 dumpbin、版本 PRAGMA 和干净环境测试 |

## 15. 实施状态与后续顺序

### 阶段 A：独立依赖自动化闭环（已完成）

1. OpenSSL Debug/Release stage 和 manifest 作为强制输入；
2. 脚本初始化 VS2022 x64 + SDK `10.0.22621.0`；
3. 验证 SQLCipher tag、commit、SQLite baseline 和源码干净；
4. NMake 在配置专用 `work/generated` 只生成源码；
5. CMake/MSBuild 生成 DLL、import library、CLI、headers 和 linker PDB；
6. `cmake --install` 生成 SQLCipher-only stage 与 manifest；
7. Debug/Release 均已通过 CTest provider smoke、PRAGMA、依赖、导出、CRT、编译选项和运行时检查。

### 阶段 B：正式专项测试

1. 准备并记录 x64 Tcl 开发环境；
2. 创建独立 test work；
3. 增加 `SQLCIPHER_TEST=1`；
4. 构建 `testfixture.exe`；
5. 执行 `test/sqlcipher.test`；
6. 记录跳过项和结果，不要求完整 SQLite suite 全绿。

### 阶段 C：项目集成

1. 修改 `FindSQLCipher.cmake` 为配置感知 imported target；
2. 让 CMake 只消费 stage，不扫描本机旧 SQLCipher/OpenSSL；
3. 使用 `-Dsqlcipher=ON` 构建 SQLiteBrowser；
4. 运行项目 CTest 和数据库功能测试；
5. 更新部署和安装器路径。

### 阶段 D：Debug 与自动化（依赖级已完成，CI 待接入）

1. 已使用 OpenSSL Debug stage 构建 SQLCipher Debug；
2. 已验证 `/MDd`、Debug CRT、PDB 和依赖；
3. 固定入口为 `third_party/sqlcipher/build.cmd`；
4. Codex/Claude 兼容项目 Skill 已同步；
5. 待将同一入口接入 CI。

## 16. 最终建议

当前独立依赖闭环已经完成，不再建议回退到完整 NMake 产品构建。后续应以本轮验证通过的“上游生成 + CMake/MSBuild 产品构建”作为唯一自动化基线。

当前闭环已经证明：

- 使用 VS2022、v143、SDK `10.0.22621.0`；
- Release 使用 `/MD`，Debug 使用 `/MDd`；
- 只链接匹配配置、manifest 验证通过的项目 OpenSSL 3.5.7；
- 生成项目所需名称和 stage 布局；
- 保持 SQLCipher 子模块干净；
- CTest shared/provider smoke 与加密 provider probe 通过。

仍需由后续发布门禁证明：明文 SQLite、错误密钥、rekey、现有用户数据库兼容性，以及补齐 Tcl 后的 SQLCipher 专项测试。

构建脚本、Skill 和 CMake target 已实现；下一阶段应让主工程和安装器消费受验证 stage，并补齐真实数据库兼容性及 Tcl 专项测试，避免在同一变更中再次重写依赖构建。

## 17. 本地分析依据

- [`SQLCipher README.md`](../../../third_party/sqlcipher/src/README.md)
- [`SQLCipher Makefile.msc`](../../../third_party/sqlcipher/src/Makefile.msc)
- [`compile-for-windows.md`](../../../third_party/sqlcipher/src/doc/compile-for-windows.md)
- [`sqlcipher.c`](../../../third_party/sqlcipher/src/src/sqlcipher.c)
- [`crypto_openssl.c`](../../../third_party/sqlcipher/src/src/crypto_openssl.c)
- [`test/sqlcipher.test`](../../../third_party/sqlcipher/src/test/sqlcipher.test)
- [`FindSQLCipher.cmake`](../../../cmake/FindSQLCipher.cmake)
- [`cppcmake-windows.yml`](../../../.github/workflows/cppcmake-windows.yml)
- [`development-environment-upgrade-plan.md`](development-environment-upgrade-plan.md)
- [`openssl-build-automation-guide.md`](openssl-build-automation-guide.md)

## 18. 已实现的 CMake/MSBuild 产品构建入口

当前仓库实现由两个文件构成：

- [`third_party/sqlcipher/CMakeLists.txt`](../../../third_party/sqlcipher/CMakeLists.txt)：上游源码生成规则、原生 CMake shared library/CLI target、CTest、install 和 PDB 策略；
- [`third_party/sqlcipher/build.cmd`](../../../third_party/sqlcipher/build.cmd)：版本与工具链预检、配置编排、OpenSSL/Brotli 契约、运行时审计和 manifest。

旧的 `third_party/sqlcipher/cmake/BuildSQLCipher.cmake` 已删除。当前不再生成临时批处理，也不再由 CMake helper 启动完整 NMake 产品构建。

### 18.1 构建职责

```text
Makefile.msc / NMake
  -> Jim Tcl、Lemon、FTS5、sqlite3.c、headers、shell.c

CMake / MSBuild
  -> sqlcipher.dll + sqlcipher.lib + sqlcipher.exe
  -> OpenSSL::Crypto import target
  -> CTest shared/provider smoke
  -> cmake --install
```

NMake 的 `LDFLAGS` 覆盖只影响生成工具：Debug 使用 `/DEBUG`，Release 使用空值，避免上游默认 `/NODEFAULTLIB:msvcrt` 破坏 Release 生成工具链接。SQLCipher 产品链接选项完全由 CMake target 控制。

### 18.2 配置与固定行为

日常入口：

```cmd
third_party\sqlcipher\build.cmd check
third_party\sqlcipher\build.cmd debug
third_party\sqlcipher\build.cmd release
third_party\sqlcipher\build.cmd all
```

每个配置使用 `build/sqlcipher/x64-<config>/work`，CMake 将生成配置限制为单一 Debug 或 Release。固定行为包括：

- VS2022 x64、MSVC v143、SDK `10.0.22621.0`；
- SQLCipher `v4.18.0`、SQLite `3.53.4`、子模块干净；
- Debug `/MDd`，Release `/MD`；
- 相同配置的 OpenSSL 3.5.7 stage；
- OpenSSL manifest 必须记录 Brotli 1.2.0 与 `enable-brotli-dynamic`；
- 一份 CMake 宏列表同时用于源码生成、产品编译和 manifest；
- `SQLCipher::SQLCipher` 是当前 build tree 中 `sqlcipher` target 的 alias，不是预先存在文件的 imported target；
- 只支持 Debug/Release，不再映射 RelWithDebInfo/MinSizeRel。

### 18.3 输出与验证

```text
build/sqlcipher/
|- x64-debug/
|  |- work/{generated,Debug,...}/
|  `- stage/{bin,include/sqlcipher,lib,share/licenses/sqlcipher}/
`- x64-release/
   |- work/{generated,Release,...}/
   `- stage/{bin,include/sqlcipher,lib,share/licenses/sqlcipher}/
```

2026-08-26 已使用 VS2022 Enterprise、MSVC `14.44.35207`、CMake `3.30.3` 和 SDK `10.0.22621.0` 完整验证 Debug 与 Release：

- 上游源码生成成功，子模块保持干净；
- CMake/MSBuild 直接生成 `sqlcipher.dll`、`sqlcipher.lib` 和动态链接该 DLL 的 `sqlcipher.exe`；
- 两个配置的 CTest `sqlcipher.provider.smoke` 均通过；
- provider 为 SQLCipher `4.18.0 community`、`openssl`、OpenSSL `3.5.7`；
- 受控 compile-options 清单、x64、导出、Crypto 依赖及 Debug/Release CRT 审计通过；
- stage 的 `bin` 只包含 `sqlcipher.pdb` 与 `sqlcipher-cli.pdb` 两个 linker PDB，不包含生成工具/compiler PDB；
- SQLCipher-only stage 未复制 OpenSSL 或 Brotli DLL；
- manifest 包含版本、工具链、完整宏、OpenSSL manifest hash 和产品 SHA-256。

### 18.4 尚未覆盖的范围

当前未修改仓库根 `CMakeLists.txt`、`FindSQLCipher.cmake`、CI、SQLiteBrowser 应用部署或 NSIS。CTest provider smoke 不等于官方 Tcl 专项测试；`test/sqlcipher.test`、真实用户数据库兼容性、rekey 和干净虚拟机安装验证仍是后续发布门禁。
