# SQLCipher 与 OpenSSL 子模块化及统一构建方案

## 1. 文档目的

本文分析在 SQLiteBrowser 的 `upgrade/v4.0.0` 分支中，将 SQLCipher 4.18.0 与 OpenSSL 3.5.7 作为 Git submodule 引入，并在 Windows、Visual Studio 2022、Windows SDK 10.0.22621.0 下统一构建的可行方案。

本文最初用于设计子模块与统一构建。当前截至 2026-08-26，OpenSSL、SQLCipher、Brotli 等源码子模块和各自 wrapper 已落地，OpenSSL 与 SQLCipher 的 Debug/Release 独立构建已经验证；仓库根 CMake、SQLiteBrowser 主程序部署、CI 和安装器尚未接入这些 stage。本文同时记录当前实现和后续主工程级 superbuild 方向。

## 2. 结论摘要

该方案可行，并且比继续依赖本机预编译 SQLCipher/OpenSSL 更有利于固定版本、复现构建和建立 CI。但需要区分两个概念：

- Git submodule 只负责把依赖源码固定到确定的提交。
- CMake superbuild 负责按顺序调用各依赖自己的构建系统，并把输出交给 SQLiteBrowser。

当前已实现的依赖关系为：

```text
Brotli 1.2.0 stage
          |
          v
OpenSSL 3.5.7 stage（enable-brotli-dynamic）
          |
          v
SQLCipher 4.18.0
  Makefile.msc/NMake：只生成 amalgamation、headers、shell.c
  CMake/MSBuild：直接编译 sqlcipher.dll 与 sqlcipher.exe
          |
          v
SQLCipher-only stage
          |
          v
未来：SQLiteBrowser 主工程编排与最终应用 stage/安装包
```

不建议把 OpenSSL 直接通过 `add_subdirectory()` 加入主工程；它仍使用 Perl `Configure` 和 `nmake`。SQLCipher 当前已有父目录 CMake wrapper，但它不是把上游源码目录直接嵌入：NMake 只负责生成上游源码，产品 DLL、CLI、安装和 CTest 由 CMake/MSBuild 管理。

开发环境、CI 和正式构建的 OpenSSL 目标版本统一为 **3.5.7**：SQLCipher 链接该版本的 Crypto 库，Qt 6.11.1 的 OpenSSL TLS backend 运行时也使用同一构建生成的 SSL/Crypto DLL。Qt 6.11.1 官方 Windows 构建使用的是 3.5.4，但 OpenSSL 3.5.7 是同一 LTS 系列当前已发布的最新 patch，且 OpenSSL 官方保证同一主版本 API/ABI 兼容。用户现有 OpenSSL 4.0.1 及其 SQLCipher 二进制不得进入任何开发、测试、CI 或发布构建。

## 3. 当前仓库和环境观察

### 3.1 当前第三方依赖组织方式

当前 `libs/` 中的 json、qcustomplot、qhexedit、qscintilla 等依赖是直接纳入仓库的源码，不是 Git submodule。仓库的 `.gitmodules` 现已登记 OpenSSL、SQLCipher、zlib、zstd 和 Brotli 五个源码子模块；本文重点只讨论 OpenSSL/SQLCipher 以及 OpenSSL 动态依赖的 Brotli。

OpenSSL 和 SQLCipher 与这些依赖不同：二者都有独立构建过程、独立产物和独立版本生命周期。因此建议放到新的 `third_party/` 目录，而不是继续混入 `libs/`：

```text
third_party/
  openssl/                   # 父工程 wrapper 目录
    src/                     # Git submodule：OpenSSL 上游源码
  sqlcipher/                 # 父工程 wrapper 目录
    src/                     # Git submodule：SQLCipher 上游源码
```

这样能够清楚地区分：

- `libs/`：由主工程直接编译或包含的 vendored 源码；
- `third_party/`：由 superbuild 独立编译并安装到 staging prefix 的外部项目。

### 3.2 当前 CMake 对依赖的假设

当前工程在启用 `sqlcipher=ON` 时调用 `find_package(SQLCipher REQUIRED)`。现有 `cmake/FindSQLCipher.cmake` 假定已经存在一个预编译安装目录，主要查找：

- `include/sqlcipher/sqlite3.h`；
- `lib/sqlcipher.lib`。

当前 Windows 安装逻辑还会查找并复制 SQLCipher、OpenSSL 的运行时 DLL。这种设计适合消费已安装的二进制依赖，但不能自行从源码生成依赖。因此引入源码子模块后，仍然需要一层 superbuild 先生成符合现有查找约定的目录结构。

### 3.3 Git 子模块状态

此前记录的 Git 2.33/MSYS 脚本故障来自另一套工具环境，已经不再是当前阻塞项。开发者在 CMD 中实际使用的是 `git version 2.45.1.windows.1`，标准命令可以初始化仓库中的递归子模块：

```cmd
git submodule update --init --recursive
```

本文范围内父仓库固定的关键 gitlink 为：

```text
third_party/openssl/src   8cf17aaeb4599f8af87fefd810b5b5fee90fe69e  openssl-3.5.7
third_party/sqlcipher/src 63697beb0fafcb61faa7a3e6fd267036548ab11b  v4.18.0
```

新开发机仍应执行 `where git`、`git --version` 和上述递归初始化命令，避免不同 Git/MSYS 工具目录混入 PATH；但不再需要历史 Bash PATH workaround。

### 3.4 Qt 6.11.1 的 OpenSSL 版本结论

Qt 对 OpenSSL 的要求需要分成“接口兼容范围”和“本次官方二进制包的实际构建基线”理解：

- Qt 6.11 官方 SSL 文档说明，Qt Online Installer 提供的 Qt 构建在运行时要求 OpenSSL 3；Windows 包默认采用运行时动态加载，不会让应用在启动阶段硬链接到 OpenSSL DLL。
- Qt 官方 `Qt 6.11 Tools and Versions` 页面列出的 **Qt 6.11.1 / Windows x86_64 OpenSSL x64 版本为 3.5.4**。
- 本机 `E:\QT\6.11.1\msvc2022_64\mkspecs\qconfig.pri` 启用了 `opensslv30` 和 `openssl`，禁用了 `openssl-linked`、`opensslv11`。
- 本机同时包含 `qopensslbackend.dll` 与 `qschannelbackend.dll`，Qt `bin` 目录中没有附带 OpenSSL DLL，符合运行时加载模式。

因此不能表述为“Qt 6.11.1 硬性只接受 3.5.4 的每一个补丁版本”；准确结论是：官方 Windows 包要求 OpenSSL 3，而 3.5.4 是 Qt 6.11.1 官方 Windows 构建/测试所使用的具体版本。

截至本文更新日，OpenSSL 官方列出的 3.5 LTS 最新已发布版本为 **3.5.7**，支持至 2030-04-08；官方漏洞资料显示 3.5.4 位于多个后来修复问题的受影响范围。OpenSSL 发布策略保证同一主版本的 API/ABI 兼容，patch release 只包含错误和安全修复。因此不应为了逐补丁复刻 Qt 构建机而固定已过期的 3.5.4。本方案当前固定 3.5.7，并让 Qt 和 SQLCipher 在运行时使用完全相同的 3.5.7 DLL；每次升级也必须同步升级两者共享的整套运行时。

需要注意：OpenSSL 在 2026-08-13 公布了低危 `CVE-2026-14456`，受影响范围包含 3.5.0 至 3.5.7，计划在 3.5.8 修复。问题位于 OpenSSL QUIC server 的连接接收队列；当前 SQLiteBrowser/Qt HTTPS 客户端和 SQLCipher 数据库加密不属于该直接使用场景，因此不阻塞本地开发验证，但它是正式发布检查项。若 3.5.8 或更高的 3.5.x 已在发布候选冻结前正式发布，应在保持 OpenSSL 3 的前提下将开发、CI、SQLCipher 和安装包整体同步升级，并重新执行全部验收。

## 4. 推荐源码版本与固定方式

建议使用官方仓库：

- OpenSSL：`https://github.com/openssl/openssl.git`，固定到 `openssl-3.5.7` 标签所指向的提交；
- SQLCipher：`https://github.com/sqlcipher/sqlcipher.git`，固定到 `v4.18.0` 标签所指向的提交。

父仓库实际记录的是子模块提交 ID，而不是动态版本范围。即使 `.gitmodules` 中配置了分支，普通 checkout 也仍以父仓库记录的 gitlink 提交为准。为避免无意漂移，建议：

- `.gitmodules` 使用官方 HTTPS URL；
- 不设置跟随 `master` 的浮动更新策略；
- CI 使用 `git submodule update --init --recursive`，不使用 `--remote`；
- 更新依赖时，在子模块中显式 checkout 新标签、核对提交，再提交父仓库中的 gitlink 变化；
- 在依赖清单中同时记录标签、完整提交 ID、许可证和构建参数。

标签便于阅读，提交 ID 才是可复现构建的最终依据。

## 5. 当前目录与产物结构

当前依赖 wrapper 和配置隔离布局如下：

```text
SQLiteBrowser/
  CMakeLists.txt
  third_party/
    brotli/
      CMakeLists.txt
      build.cmd
      src/                    # submodule，保持只读/干净
    openssl/
      build.cmd
      src/                    # submodule，保持只读/干净
    sqlcipher/
      CMakeLists.txt          # CMake/MSBuild 产品构建 wrapper
      build.cmd
      src/                    # submodule，保持只读/干净
  build/
    brotli/x64-<config>/stage/
    openssl/x64-<config>/stage/
    sqlcipher/
      x64-<config>/
        work/
          generated/
        stage/
```

所有生成文件必须留在 `build/` 下，不能直接写入 `third_party/openssl/src` 或 `third_party/sqlcipher/src`。wrapper 文件放在各自父目录中，不修改上游源码子模块。这样可以保证：

- `git status` 不被依赖构建产物污染；
- 清理构建只需删除明确的 build 目录；
- Debug、Release 可以拥有完全隔离的输出；
- 子模块切换版本时不会残留旧版本生成文件。

## 6. 当前分层构建与未来主工程 superbuild

### 6.1 当前实现边界

当前每个依赖由自己的 `build.cmd` 驱动，并把经过验证的结果写入配置专用 stage：

1. Brotli wrapper 生成 Brotli stage；
2. OpenSSL wrapper 消费匹配配置的 Brotli stage，生成 OpenSSL stage 和 manifest；
3. SQLCipher wrapper 严格验证匹配配置的 OpenSSL manifest，再生成 SQLCipher-only stage；
4. Debug 与 Release 的 work、CMake build 和 stage 完全隔离。

这已经解决单个依赖的可复现构建，但尚未提供仓库根的一条命令编排，也没有让 SQLiteBrowser 主工程消费这些 stage。

### 6.2 未来 ExternalProject 编排

后续可在 `cmake/superbuild/` 增加外层 CMake 工程，用 `ExternalProject_Add()` 依次调用现有入口，而不是重新实现它们：Brotli、OpenSSL、SQLCipher、SQLiteBrowser。外层只负责编排依赖顺序、配置和最终应用 stage；各依赖的版本、工具链、检查、测试与 manifest 仍以自身 `build.cmd` 为单一事实来源。

`ExternalProject_Add()` 可以表达 `DEPENDS`、源码目录、构建目录、安装目录和 `BUILD_BYPRODUCTS`，但它不会自动把 Visual Studio generator 的所有设置传递给 Perl、`nmake` 或自定义 Makefile。

因此 superbuild 必须显式保证：

- VS2022 x64 编译环境已初始化；
- 使用 MSVC v143；
- Windows SDK 固定为 10.0.22621.0；
- `cl.exe`、`link.exe`、`nmake.exe` 来自同一个 VS2022 环境；
- Brotli、OpenSSL、SQLCipher 和主程序使用一致的 x64 架构与对应配置运行库；
- 每个配置拥有独立的构建和安装目录；
- 所有关键输出通过 `BUILD_BYPRODUCTS` 声明，以便 Ninja/MSBuild 正确判断依赖关系。

建议由一个入口脚本调用 VS 的 `VsDevCmd.bat -arch=x64 -host_arch=x64 -winsdk=10.0.22621.0`，再执行 CMake preset。也可以从“x64 Native Tools Command Prompt for VS 2022”运行，但脚本化入口更适合 CI 和长期复现。

### 6.3 CMake Preset 建议

外层 preset 应至少固定：

```text
generator: Visual Studio 17 2022
architecture: x64
toolset: v143
CMAKE_SYSTEM_VERSION: 10.0.22621.0
QT_ROOT: E:/QT/6.11.1/msvc2022_64
```

OpenSSL 和 SQLCipher 的依赖级 Debug/Release 链路已经打通；根级 preset 应同时提供两种配置，但在主程序与安装包接入前不能宣称完成端到端构建。

## 7. OpenSSL 子项目构建

### 7.1 构建机制

OpenSSL 3.5.7 的 Windows 官方流程基于 Perl `Configure` 和 `nmake`。x64 MSVC 的目标平台为 `VC-WIN64A`。概念流程如下：

```text
perl Configure VC-WIN64A shared --prefix=<openssl-install>
nmake
nmake test
nmake install
```

实际命令应在实现阶段依据 `openssl-3.5.7` 标签中的 `INSTALL.md` 和配置帮助再次核对，尤其是 Debug 选项、安装目标和运行库选项，不能从其他 OpenSSL 大版本直接复制参数。

### 7.2 新增的环境前置条件

用户当前列出的工具中没有 Perl 和 NASM。按 OpenSSL 官方 Windows 构建说明，实施源码构建前需要补充并固定：

- 适用于 Windows 的 Perl；
- NASM；
- VS2022 自带的 `nmake`；
- PATH 中不能混入会覆盖 MSVC 工具或 Perl 行为的同名程序。

superbuild 配置阶段应主动检查 `perl --version`、`nasm -v`、`cl` 和 `nmake /?`，缺少时立即报出可读错误，而不是到编译中途失败。

### 7.3 Release 与 Debug 隔离

OpenSSL 的 `nmake` 构建不是 Visual Studio 多配置工程。不能期望一次配置同时生成 Debug 和 Release。建议建立两个独立 ExternalProject 实例或两个独立 superbuild preset：

- `openssl-release` → `openssl-install/Release`；
- `openssl-debug` → `openssl-install/Debug`。

二者不能共享 build 目录。Debug 版本还必须和 SQLCipher、SQLiteBrowser 的 `/MDd` 或最终选定运行库设置一致。由于用户目前已有的预编译 OpenSSL Debug/Release 库布局不能证明源码构建参数，建议 Release 成功后再单独设计 Debug 参数并验证依赖 DLL。

### 7.4 OpenSSL 产物边界

SQLCipher 只需要 OpenSSL Crypto 能力，但 Qt OpenSSL TLS backend 还需要 SSL 库。因此统一构建和 staging 需要：

- OpenSSL headers；
- `libcrypto` import library；
- `libssl` import library；
- `libcrypto-3-x64.dll`；
- `libssl-3-x64.dll`；
- OpenSSL 许可证及 NOTICE 文件。

Qt 的 `qopensslbackend.dll` 在运行时动态加载 OpenSSL。发布物应让 Qt OpenSSL backend 与 SQLCipher 共享由本 superbuild 生成的 OpenSSL 3.5.7 DLL，避免同时存在不同 OpenSSL 版本。`qschannelbackend.dll` 可以作为 Windows 原生 fallback 保留；测试必须确认正常环境优先启用 OpenSSL backend，并确认移除 OpenSSL DLL 后能够按预期回退到 Schannel。若产品最终决定只使用 Schannel，也可以删除 `qopensslbackend.dll` 和 `libssl-3-x64.dll`，但 SQLCipher 仍需保留 `libcrypto-3-x64.dll`。

### 7.5 使用 OpenSSL 3.5.7 源码的影响分析

#### Qt 6.11.1 兼容性

影响较低。Qt Online Installer 的 Qt 6.11.1 Windows 包使用 OpenSSL 3 runtime，并以 3.5.4 作为官方构建环境版本；`qopensslbackend.dll` 采用运行时动态加载。OpenSSL 官方保证 3.x 同一主版本 API/ABI 兼容，因此将运行时更新到 3.5.7 不要求重新编译 Qt。

仍需通过实际运行测试确认：

- `QSslSocket::supportsSsl()` 为真；
- `QSslSocket::activeBackend()` 为 `openssl`；
- build/runtime version 分别被记录，runtime version 为 3.5.7；
- HTTPS、证书校验、代理和 TLS 错误处理行为正常；
- `QT_DEBUG_PLUGINS=1` 时没有加载失败或从系统 PATH 加载其他 OpenSSL。

#### SQLCipher 4.18.0 兼容性

影响可控，但必须重编。SQLCipher 4.18.0 的 `src/crypto_openssl.c` 已经使用 OpenSSL 3 风格的 `EVP_MAC_fetch`、`EVP_MAC_CTX`、`EVP_MAC_init/update/final`，并通过 EVP 使用 AES-256-CBC、PBKDF2 和 SHA 系列；这与 OpenSSL 3.5.7 的默认 provider 匹配。用户现有链接 `libcrypto-4-x64.dll` 的 SQLCipher DLL 不能改名复用，也不能只替换 DLL，必须使用 3.5.7 headers/import library 重新编译。

OpenSSL patch 变化不改变 SQLCipher 的 cipher page size、KDF iteration、HMAC/KDF algorithm 或数据库格式参数，因此预期不会改变 SQLCipher 4 的磁盘格式。该结论仍需用已有加密数据库样本做双向验证：旧库读取、修改后重开、rekey、新库创建和错误密码。

#### 性能影响

SQLCipher 4.18.0 的 OpenSSL provider 在每次 HMAC 操作中调用 `EVP_MAC_fetch`/`EVP_MAC_free`，上游已有公开问题指出这会产生每页操作开销和多线程全局 method store 竞争。它不是 3.5.7 引入的正确性回归，也不改变磁盘格式，但升级后应增加基准测试，特别是大数据库、批量写入和多连接并发场景。未经数据证明，不建议在本次依赖升级中自行维护 SQLCipher crypto provider 性能补丁。

#### Provider 与 FIPS 影响

SQLCipher 当前所用算法可由 OpenSSL 3 默认 provider 提供，不应依赖系统 OpenSSL 配置或 legacy provider。stage 和启动测试必须确保默认 provider 能正常加载。SQLCipher 4.18.0 参考 OpenSSL provider 的 `fips_status` 固定返回 0，因此“从 OpenSSL 3.5.7 源码构建”并不等于获得 FIPS 模式或认证；若未来需要 FIPS，必须作为独立需求设计、构建和认证，不能在 v4.0.0 升级中默认宣称。

#### Windows 构建与部署影响

- DLL 名称从现有 OpenSSL 4 的 `libcrypto-4-x64.dll`/`libssl-4-x64.dll` 改为 OpenSSL 3 的 `libcrypto-3-x64.dll`/`libssl-3-x64.dll`；
- OpenSSL、SQLCipher 和 SQLiteBrowser 必须统一 VS2022 x64、SDK 10.0.22621.0 及 `/MD`（Release）或 `/MDd`（Debug）；
- 切换后必须使用全新的 build/stage 目录，删除旧 CMake cache，避免缓存的 OpenSSL 4 include/library 路径；
- 开发运行、CTest、CI、portable ZIP 和 NSIS 必须全部从同一 stage 取 DLL，不允许引用 `C:\Program Files\OpenSSL-Win64` 或开发者 PATH；
- Release 和 Debug 分别构建 OpenSSL，不能混用 import library 或 DLL。

#### 安全版本影响

3.5.7 修复了 3.5.4 之后的多项安全问题，因此比逐补丁匹配 Qt 官方构建机更适合作为当前开发基线。但 3.5.7 已知受到低危 `CVE-2026-14456` 影响，修复目标为 3.5.8。该问题针对 QUIC server，当前产品直接暴露较低；仍应把“发布前检查 OpenSSL 3.5 最新 patch 和漏洞页”设为强制 release gate，而不是永久固定 3.5.7。

## 8. SQLCipher 子项目构建

### 8.1 构建顺序

当前 `third_party/sqlcipher/build.cmd` 要求匹配配置的 OpenSSL stage 和 `build-manifest.txt` 已存在。manifest 必须证明 OpenSSL 3.5.7、固定提交、匹配配置、匹配 CRT、Brotli 1.2.0 和 `enable-brotli-dynamic`。SQLCipher 配置和链接参数只允许引用该 stage，不能回退到 `C:\Program Files\OpenSSL-Win64` 或 PATH。未来 `sqlcipher_external` 也必须声明对 `openssl_external` 的顺序依赖。

### 8.2 避免污染 SQLCipher 子模块

当前 wrapper 不复制整个源码树，也不在 submodule 内构建。CMake 在 `build/sqlcipher/x64-<config>/work` 下配置，并从该目录的 `generated/` 子目录调用上游 `Makefile.msc`。NMake 只生成 `sqlite3.c`、`sqlite3.h`、`sqlite3ext.h`、`sqlite3session.h` 和 `shell.c`；随后 CMake/MSBuild 从这些生成文件和只读源码树编译产品。

这种方式避免完整源码复制和 NMake 产品链接，同时保持 submodule 干净。NMake 的 `LDFLAGS` 覆盖仅作用于 Jim Tcl、Lemon 等生成工具：Debug 使用 `/DEBUG`，Release 使用空值，以避免上游 `/NODEFAULTLIB:msvcrt` 破坏 Release 生成工具链接。

### 8.3 输出命名与特性参数

当前 CMake target 已固定以下产品命名：

- `sqlcipher.dll`；
- `sqlcipher.lib`；
- `sqlcipher.exe`。

同时以当前上游 CI 参数为功能基线，并由脚本审计以下核心编译特性：

```text
SQLITE_TEMP_STORE=2
SQLITE_HAS_CODEC
SQLITE_ENABLE_FTS3
SQLITE_ENABLE_FTS5
SQLITE_ENABLE_FTS3_PARENTHESIS
SQLITE_ENABLE_STAT4
SQLITE_SOUNDEX
SQLITE_ENABLE_JSON1
SQLITE_ENABLE_GEOPOLY
SQLITE_ENABLE_RTREE
SQLCIPHER_CRYPTO_OPENSSL
SQLITE_MAX_ATTACHED=125
```

这一步很重要。用户现有 SQLCipher 4.18.0 自编译库虽然可识别为 SQLCipher，但其编译选项与 SQLiteBrowser 当前 CI 基线并不完全一致，例如 `MAX_ATTACHED` 和部分 SQLite 特性。把源码纳入 superbuild 后，应把功能集合写成受版本控制的明确参数，并增加运行时查询验证，而不是只验证 DLL 能否链接。

完整受控定义记录在 stage 的 `build-manifest.txt` 和 `compile-options.txt` 中。产品目标链接匹配 OpenSSL stage 的 `libcrypto.lib`；SQLCipher 不直接链接 `libssl.lib`。

### 8.4 SQLCipher staging 结构

`cmake --install` 当前生成配置专用 SQLCipher-only stage：

```text
build/sqlcipher/x64-<config>/stage/
  build-manifest.txt
  compile-options.txt
  provider-probe.txt
  include/
    sqlcipher/
      sqlite3.h
      sqlite3ext.h
      sqlite3session.h
  lib/
    sqlcipher.lib
  bin/
    sqlcipher.dll
    sqlcipher.exe
    sqlcipher.pdb
    sqlcipher-cli.pdb
  share/licenses/sqlcipher/
    LICENSE.md
    SQLITE_LICENSE.md
```

SQLCipher stage 故意不复制 OpenSSL 或 Brotli DLL，避免多个依赖 stage 出现重复且可能漂移的二进制。当前 CLI/CTest 运行时临时把匹配 OpenSSL `bin` 加入进程 DLL 搜索路径；未来最终应用 stage/安装包应从 SQLCipher、OpenSSL、Brotli 和 Qt 各自的权威 stage 集中收集一次。

## 9. SQLiteBrowser 主工程接入

### 9.1 依赖发现方式

短期可以让现有 `FindSQLCipher.cmake` 查找 stage，但其当前 imported target 偏向单配置库。长期更推荐由工程维护一个小型 `SQLCipherConfig.cmake`，为 Debug/Release 提供配置感知的 imported target：

```text
SQLCipher::SQLCipher
  INTERFACE_INCLUDE_DIRECTORIES -> stage/<config>/include/sqlcipher
  IMPORTED_IMPLIB_<CONFIG>      -> stage/<config>/lib/sqlcipher.lib
  IMPORTED_LOCATION_<CONFIG>    -> stage/<config>/bin/sqlcipher.dll
```

OpenSSL 的编译期依赖应通过 SQLCipher target 或明确的包配置表达；最终应用部署必须从同一配置的 OpenSSL stage 取得 SSL/Crypto 及其 Brotli 运行时，避免主程序或 Qt plugin 通过全局 PATH 偶然加载系统 OpenSSL。

### 9.2 内层主工程配置

`sqlitebrowser_external` 的配置参数建议包含：

- `QT_MAJOR=Qt6`；
- `sqlcipher=ON`；
- `CMAKE_PREFIX_PATH` 指向 Qt 和当前配置的 stage；
- `CMAKE_SYSTEM_VERSION=10.0.22621.0`；
- 显式 x64、v143 和当前配置；
- 禁止查找用户现有 SQLCipher/OpenSSL 路径的选项或严格查找模式。

此前环境分析已经发现 Qt 6.11.1 安装中缺少 Qt6 Core5Compat，而当前代码仍需要该模块。该问题与子模块方案无直接关系，但会继续阻塞主程序配置；在进入完整 superbuild 验证前仍需安装匹配 Qt 6.11.1 MSVC 2022 x64 的 Core5Compat 组件，或先完成代码迁移。

## 10. 测试与验收

建议按以下层级验收，而不是只以“编译成功”为标准。

### 10.1 OpenSSL

- `nmake test` 通过；
- 产物架构为 x64；
- import library 和 DLL 来自同一构建；
- DLL 不依赖意外的第三方运行库；
- 记录 OpenSSL 完整版本信息。

### 10.2 SQLCipher

- 当前 CTest provider smoke 通过，并明确记录官方 Tcl SQLCipher 测试未运行；
- `PRAGMA cipher_version;` 返回预期版本；
- `PRAGMA compile_options;` 与受控特性清单一致；
- CLI provider probe 能创建加密数据库并完成基本读写；
- 发布门禁仍需补充错误密钥、rekey、官方 `test/sqlcipher.test` 和现有用户数据库样本兼容性；
- `dumpbin /dependents` 只指向本次 staging 的预期运行时依赖。

### 10.3 SQLiteBrowser

- Release x64 配置、编译、测试通过；
- 能新建、打开、修改和保存 SQLCipher 数据库；
- 普通 SQLite 数据库功能不回退；
- 打包目录不依赖开发机 PATH；
- 在无 Qt、OpenSSL、SQLCipher 开发环境的干净 Windows 虚拟机中启动和完成冒烟测试；
- NSIS 安装、卸载和覆盖升级均通过。
- `QSslSocket::activeBackend()` 在完整发布物中返回 `openssl`，运行时 OpenSSL 版本为 3.5.7；
- 在专门的 fallback 测试中移除 OpenSSL TLS 所需文件后，Qt 能按设计使用 `schannel`，SQLCipher 测试则应因缺少 Crypto DLL 而明确失败，不能静默加载系统中的其他版本。

## 11. CI 与可复现性

CI checkout 必须初始化子模块，并验证其提交和依赖清单一致。推荐的流水线阶段为：

1. checkout 父仓库及 recursive submodules；
2. 输出 Git、VS、MSVC、SDK、CMake、Perl、NASM、Qt 版本；
3. 构建并测试匹配配置的 Brotli；
4. 构建并测试匹配配置的 OpenSSL；
5. 构建、运行 CTest 并验证 SQLCipher；
6. 配置、构建并测试 SQLiteBrowser；
7. 从统一 stage 生成安装包；
8. 保存依赖清单、测试结果和最终 artifacts。

为增强供应链可审计性，构建产物应附带：

- 父仓库提交；
- 所有参与构建的子模块完整提交 ID；
- Brotli/OpenSSL/SQLCipher 构建参数与各自 manifest；
- MSVC、Windows SDK、CMake、Perl、NASM 和 Qt 版本；
- `PRAGMA compile_options` 输出；
- 最终 DLL 依赖列表；
- 第三方许可证清单。

## 12. 主要风险和控制措施

| 风险 | 影响 | 控制措施 |
| --- | --- | --- |
| 新开发机 Git/MSYS 路径混用 | 无法可靠初始化 submodule | 记录 `where git`/`git --version` 并验证标准 recursive update；当前 Git 2.45.1 已解决历史故障 |
| 误认为 submodule 等于统一构建 | 依赖仍由不同编译器或本机路径生成 | 使用现有 wrapper/manifest 固定 VS、SDK、架构、配置和路径；根级编排只调用这些入口 |
| Perl/NASM 未安装或版本漂移 | OpenSSL 配置或汇编失败 | 纳入前置工具清单、配置期检查和 CI 版本记录 |
| 在子模块目录内编译 | 污染源码、清理危险、切换版本残留 | OpenSSL 使用配置专用 work；SQLCipher 只把生成文件写入配置专用 `work/generated` |
| Debug/Release 运行库不一致 | 链接失败或运行时内存/CRT 问题 | 分离构建目录和安装前缀；Release 先行；逐项核对 `/MD`、`/MDd` |
| SQLCipher 特性参数回退 | 编译成功但功能或数据库行为变化 | 固定 CI 基线参数并校验 `PRAGMA compile_options` |
| 系统 OpenSSL 被意外找到 | 开发机成功、干净机失败，版本不可审计 | 只允许使用匹配配置且 manifest 验证通过的仓库 stage；禁止 PATH 回退 |
| Qt 和 SQLCipher 加载不同 OpenSSL | 同进程出现多套密码库、行为不一致且难以审计 | 两者统一使用 superbuild 生成的 OpenSSL 3.5.7，部署时禁止 PATH 回退 |
| 将 Qt 官方构建使用的 3.5.4 永久当作发布版本 | 带入该补丁版之后已修复的安全问题 | 保持 OpenSSL 3.5 LTS 系列，当前开发固定 3.5.7，并在发布前重新核对安全公告 |
| 3.5.7 已知 QUIC server 低危问题 | 若未来应用暴露 QUIC server，可被消耗内存导致拒绝服务 | 当前不启用 QUIC server；发布前优先同步升级到已正式发布的 3.5.8 或更高 3.5.x |
| SQLCipher OpenSSL provider 每页获取 EVP_MAC | 大库和多连接场景可能出现额外 CPU/锁竞争 | 建立升级前后基准；不在依赖升级中引入未经验证的 provider 私有补丁 |
| 将 Qt 的 OpenSSL 3 要求误解为任意 OpenSSL 主版本 | `qopensslbackend` 无法加载或 TLS 功能回退 | 使用 OpenSSL 3.x；通过官方 API/ABI 策略支持的安全 patch 更新，并在运行时断言 backend 与版本 |
| ExternalProject 并行依赖描述不足 | 偶发配置/链接找不到产物 | 声明 `DEPENDS`、`BUILD_BYPRODUCTS` 和明确 install step |
| 上游 Makefile 变量变化 | 升级 SQLCipher/OpenSSL 后构建脚本失效 | 每次依赖升级单独审阅对应标签的官方构建文件和 release notes |
| 把依赖 DLL 复制进多个组件 stage | 重复二进制漂移，来源不唯一 | 保持组件 stage 单一职责，最终应用 stage 按 manifest 从各权威 stage 集中收集 |

## 13. 分阶段实施建议

### 阶段 A：工具和仓库基础（已完成）

1. Git for Windows 2.45.1 可执行标准递归子模块命令；
2. OpenSSL 构建所需 Perl、NASM 已纳入脚本预检；
3. VS2022 x64 + SDK 10.0.22621.0 已由各依赖脚本初始化并验证；
4. OpenSSL、SQLCipher、Brotli 等子模块已固定到准确提交。

Qt6 Core5Compat 属于主程序接入阶段，尚未由本轮依赖构建处理。

### 阶段 B：Brotli/OpenSSL Debug 与 Release（已完成）

1. 完成 Brotli 1.2.0 的配置专用 stage；
2. 完成 OpenSSL 3.5.7 Debug/Release x64 的独立 build/install；
3. OpenSSL 以 `enable-brotli-dynamic` 消费匹配配置的 Brotli；
4. 产物、测试和 manifest 已由各自脚本验证。

### 阶段 C：SQLCipher Debug 与 Release（依赖级闭环已完成）

1. NMake 只生成上游源码，CMake/MSBuild 直接编译 DLL 和 CLI；
2. 只链接阶段 B 的匹配 OpenSSL stage；
3. 固定并审计 SQLiteBrowser 所需功能参数；
4. 输出 SQLCipher-only stage、linker PDB 和 manifest；
5. Debug/Release 的 CTest provider smoke、导出、CRT、依赖和运行时 probe 已通过。

官方 Tcl 测试、错误密钥、rekey 和真实数据库兼容性仍是发布门禁，不包含在“依赖级闭环已完成”中。

### 阶段 D：主程序与安装包

1. 让内层 SQLiteBrowser 只消费 stage；
2. 改进 SQLCipher imported target 的配置感知能力；
3. 从同一配置的权威 stage 集中部署 SQLCipher、OpenSSL 3.5.7 Crypto/SSL、Brotli DLL 与 Qt OpenSSL backend；
4. 完成 Qt 部署和 NSIS 打包；
5. 在干净 Windows 环境验证 OpenSSL backend、Schannel fallback、安装和运行。

### 阶段 E：主程序 Debug 与 CI

1. 消费已完成的 OpenSSL/SQLCipher Debug stage，为主程序增加完全隔离的 Debug 链路；
2. 核对最终应用 stage 的 Debug CRT 和 DLL；
3. 将工具版本、子模块提交、测试和依赖清单纳入 CI；
4. 在 Release 构建稳定后再将其作为 v4.0.0 的正式发布基础。
5. 发布候选冻结前检查 OpenSSL 3.5 漏洞页；如 3.5.8 或更高 3.5.x 已发布，开发、CI 和发布整体升级后重新验收。

## 14. 不推荐的方案

### 14.1 只添加 submodule，继续手工编译

源码版本虽然固定，但编译器、SDK、参数、输出位置和依赖关系仍依赖人工操作，无法达到“同一套构建环境”的目标。

### 14.2 直接修改上游子模块构建文件

这会让子模块长期保持本地补丁，升级标签时冲突较多。优先在父仓库维护 wrapper CMake 和命令参数；只有上游构建机制无法满足必要功能时，才维护最小补丁并记录原因。

### 14.3 在源码目录中生成并提交二进制文件

这会混淆源码固定与产物分发，增加仓库体积，并使 Debug/Release、不同 MSVC 版本的文件难以区分。发布二进制应作为 CI artifact 或安装包管理。

### 14.4 同时保留系统路径自动回退

如果找不到 stage 就自动搜索 `C:\Program Files` 或 PATH，会掩盖 superbuild 问题并破坏复现性。统一构建模式应采用严格依赖发现，缺失时直接失败。

## 15. 最终建议

继续采用“固定源码 submodule + 配置专用组件 stage + manifest 契约 + 未来根级编排”的方向。开发环境、CI 和正式构建都必须使用仓库 wrapper 生成的 OpenSSL 3，不允许回退到系统 OpenSSL 4 或旧 SQLCipher 二进制。Brotli、OpenSSL、SQLCipher 的依赖级 Debug/Release 链路已经完成；下一步是主工程、CI、最终应用 stage 和安装器接入。

首个里程碑应限定为：

> 在 VS2022、MSVC v143、Windows SDK 10.0.22621.0 下，从固定提交的 Brotli 1.2.0、OpenSSL 3.5.7 和 SQLCipher 4.18.0 源码开始，一条命令生成 Release x64 SQLiteBrowser 及可在干净 Windows 环境运行的安装包；SQLCipher 和 Qt OpenSSL TLS backend 使用同一套 OpenSSL 3.5.7/Brotli 运行时。

依赖级 Debug 已经具备，主程序接入时应同步保留配置隔离。完成上述里程碑后，再补齐 Tcl 专项测试、数据库迁移样本、干净机验证和依赖升级自动化。

## 16. 官方资料

- [Git submodule 文档](https://git-scm.com/docs/git-submodule)
- [CMake 3.30 ExternalProject 文档](https://cmake.org/cmake/help/v3.30/module/ExternalProject.html)
- [Qt 6.11 Tools and Versions](https://wiki.qt.io/Qt_6.11_Tools_and_Versions)
- [OpenSSL 当前版本下载与支持周期](https://www.openssl-library.org/source/)
- [OpenSSL 3.5 漏洞列表](https://www.openssl-library.org/news/vulnerabilities-3.5/)
- [OpenSSL 发布与 API/ABI 兼容策略](https://www.openssl-library.org/policies/releasestrat/)
- [OpenSSL 3.5.7 release](https://github.com/openssl/openssl/releases/tag/openssl-3.5.7)
- [OpenSSL 3.5.7 INSTALL.md](https://github.com/openssl/openssl/blob/openssl-3.5.7/INSTALL.md)
- [OpenSSL 3.5.7 Windows 构建说明](https://github.com/openssl/openssl/blob/openssl-3.5.7/NOTES-WINDOWS.md)
- [SQLCipher v4.18.0 源码](https://github.com/sqlcipher/sqlcipher/tree/v4.18.0)
- [SQLCipher v4.18.0 Makefile.msc](https://github.com/sqlcipher/sqlcipher/blob/v4.18.0/Makefile.msc)
- [SQLCipher v4.18.0 OpenSSL provider 源码](https://github.com/sqlcipher/sqlcipher/blob/v4.18.0/src/crypto_openssl.c)
- [SQLCipher OpenSSL 3 provider 性能问题 #597](https://github.com/sqlcipher/sqlcipher/issues/597)
- [SQLCipher v4.18.0 release](https://github.com/sqlcipher/sqlcipher/releases/tag/v4.18.0)
- [Qt 6 SSL/TLS 文档](https://doc.qt.io/qt-6/ssl.html)
