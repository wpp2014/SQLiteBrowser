# Windows 本地开发环境升级方案

> 文档性质：基于现有本地工具链的升级方案  
> 分析日期：2026-08-23  
> 分支基线：`upgrade/v4.0.0` / `1debae535a418b66267db56739a9bc0c9b4ac37b`  
> 目标平台：Windows x64  
> 目标工具链：Visual Studio 2022、Windows SDK `10.0.22621.0`  
> 本文仅记录分析和建议，尚未修改项目构建配置。

## 1. 结论

可以直接基于当前 `upgrade/v4.0.0` 开展开发，不必先搭建上游 `v3.13.1` 的旧开发环境。

建议把第一个里程碑收敛为：

```text
Windows x64
Visual Studio 2022 / v143
Windows SDK 10.0.22621.0
Qt 6.11.1
OpenSSL 3.5.7（Qt 6.11.1 官方构建基线为 3.5.4）
SQLCipher 4.18.0 / SQLite core 3.53.4
Release 构建
```

当前还不能直接成功配置项目，存在四个明确阻塞项：

1. Qt 6.11.1 安装中缺少项目强制要求的 `Qt6::Core5Compat`。
2. 当前 Git for Windows 的 submodule 命令异常，不能可靠初始化 OpenSSL/SQLCipher 子模块。
3. OpenSSL 源码构建所需的 Perl、NASM 尚未纳入已验证环境。
4. 项目的 `FindSQLCipher.cmake` 和安装规则还不能消费 superbuild 生成的统一 stage。

本地开发、CTest、CI 和正式构建全部统一使用由源码构建的 OpenSSL 3.5.7。Qt 6.11.1 官方 Windows x64 构建环境使用 OpenSSL 3.5.4，但 3.5.7 与其同属 OpenSSL 3 ABI，并包含后续安全修复。SQLCipher 链接 3.5.7 Crypto，Qt OpenSSL TLS backend 运行时加载同一套 3.5.7 Crypto/SSL DLL。本机 OpenSSL 4.0.1 及使用它构建的 SQLCipher 二进制全部排除在目标开发环境之外，不能用于“先跑通再替换”的过渡构建。

## 2. 已核验的本地环境

### 2.1 编译工具

| 组件 | 实际状态 | 结论 |
| --- | --- | --- |
| Visual Studio | Enterprise 2022 `17.14.37` | 可用 |
| MSVC | v143，工具版本 `14.44` | 可用 |
| Windows SDK | 已安装 `10.0.22621.0` | 可用，但需要显式选择 |
| CMake | `3.30.3`，在 PATH 中 | 高于项目最低要求 `3.16` |
| NSIS | `3.12`，`makensis.exe` 在 PATH 中 | 可用于后续安装器阶段 |

本机还安装了其他 Windows SDK，因此不能依赖 Visual Studio 自动选择，后续 CMake 配置必须显式指定 `10.0.22621.0`。

### 2.2 Qt

Qt 安装路径：

```text
E:\QT\6.11.1\msvc2022_64
```

已确认：

- Qt 版本为 `6.11.1`。
- 架构为 x64。
- mkspec 为 `win32-msvc`。
- `Qt6LinguistTools` 存在。
- `windeployqt.exe` 存在。
- Qt TLS plugins 中包含 OpenSSL、Schannel 和 certificate-only backend。
- `Qt6Core5CompatConfig.cmake` 不存在。

### 2.3 当前 OpenSSL 4 安装（不符合目标环境）

OpenSSL 安装路径：

```text
C:\Program Files\OpenSSL-Win64
```

已确认：

- 版本为 OpenSSL `4.0.1`。
- 平台为 `VC-WIN64A`。
- Release 使用 `/MD`。
- Debug 使用 `/MDd`。
- DLL 为 `libcrypto-4-x64.dll` 和 `libssl-4-x64.dll`。
- CMake 3.30 的 `FindOpenSSL.cmake` 能识别 `lib/VC/x64/MD` 与 `MDd` 目录结构。

上述信息只用于识别和排除旧依赖。目标开发环境不读取该目录，不把它加入 `OPENSSL_ROOT_DIR`、`CMAKE_PREFIX_PATH` 或应用运行 PATH。目标 OpenSSL 3.5.7 必须由仓库 superbuild 从固定源码提交构建，并安装到构建树中的配置专用 stage。

### 2.4 数据库库的真实身份

当前目录：

```text
E:\Library\sqlite
```

虽然目录和输出文件使用 SQLite 名称，但本地实际运行结果为：

```text
SQLCipher: 4.18.0 community
SQLite core: 3.53.4
SQLITE_HAS_CODEC: 1
```

对应文件：

```text
include/sqlite3.h
include/sqlite3ext.h
include/sqlite3session.h

lib/x64-debug/sqlite3.lib
lib/x64-release/sqlite3.lib

bin/x64-debug/sqlite3.dll
bin/x64-release/sqlite3.dll
```

Release `sqlite3.dll` 直接依赖：

```text
libcrypto-4-x64.dll
VCRUNTIME140.dll
Windows Universal CRT
```

Debug `sqlite3.dll` 直接依赖：

```text
libcrypto-4-x64.dll
VCRUNTIME140D.dll
ucrtbased.dll
```

因此这套库应在项目和文档中称为 **SQLCipher 4.18.0**，而不是 SQLite 4.18.0。SQLCipher 官方 `v4.18.0` release 也明确说明其 SQLite baseline 为 3.53.4：

https://github.com/sqlcipher/sqlcipher/releases/tag/v4.18.0

该现有 SQLCipher 链接 OpenSSL 4，因此同样不属于目标开发环境。它可以作为数据库格式和功能对比样本，但不能参与主程序链接、CTest、CI 或安装包。目标 SQLCipher 必须从 `v4.18.0` 子模块源码重新构建并只链接 superbuild 生成的 OpenSSL 3.5.7。

## 3. 推荐的产品构建形态

### 3.1 第一阶段只构建 SQLCipher-enabled 应用

对于当前 fork，第一阶段建议只生成一个启用 SQLCipher 的应用。

SQLCipher 官方说明：当没有设置 key 时，SQLCipher 会像普通 SQLite 一样处理明文数据库。因此一个 SQLCipher-enabled 应用可以同时支持：

- 普通 SQLite 数据库；
- SQLCipher 加密数据库。

官方兼容性说明：

https://github.com/sqlcipher/sqlcipher/tree/v4.18.0#compatibility

这样可以暂时避免同时维护：

- 一套纯 SQLite 依赖；
- 一套 SQLCipher 依赖；
- 两套 EXE；
- 两套构建、测试和打包目录。

如果未来需要完全复刻上游发布形式，再增加一套独立的纯 SQLite 3.53.4 构建。

### 3.2 不应把 SQLCipher 当作普通 SQLite 链接

项目目前有两种模式：

```text
sqlcipher=OFF -> find_package(SQLite3)
sqlcipher=ON  -> find_package(SQLCipher)
```

如果把当前 `sqlite3.lib` 作为普通 SQLite 链接：

- 库本身仍带有加密能力；
- 但项目不会定义 `ENABLE_SQLCIPHER`；
- SQLCipher 密码、加密设置等 UI 和代码路径不会正确启用。

因此当前库必须以 `sqlcipher=ON` 的语义集成。

## 4. Qt 6.11.1 处理方案

### 4.1 当前阻塞原因

项目明确要求：

```cmake
find_package(Qt6 REQUIRED COMPONENTS Core5Compat)
```

源码仍大量使用 `QTextCodec`，涉及：

- 应用默认编码；
- CSV 导入和导出；
- 文本编码探测；
- Table Browser 编码选项；
- 数据显示和转换。

Qt 官方说明，Qt6 中这些已移除的 Qt5 Core API 由 Core5Compat 模块提供：

https://doc.qt.io/qt-6/qtcore5-index.html

### 4.2 第一阶段方案

使用 Qt Maintenance Tool 为 Qt 6.11.1 MSVC2022 x64 添加：

```text
Qt 5 Compatibility Module / Core5Compat
```

第一阶段继续链接 `Qt6::Core5Compat`，不要同时重写编码层。

### 4.3 后续清理

Qt6 构建稳定后，可以单独安排编码迁移：

- `QTextCodec` 迁移到 `QStringConverter`、`QStringDecoder`、`QStringEncoder`；
- 为 CSV、BOM 探测和非 UTF-8 编码补充回归测试；
- 完成后再删除 Core5Compat。

这应作为独立任务，不与 VS2022 工具链迁移混在一起。

## 5. SQLCipher CMake 集成方案

### 5.1 当前查找逻辑不兼容

项目 `cmake/FindSQLCipher.cmake` 当前要求：

```text
include/sqlcipher/sqlite3.h
lib/sqlcipher.lib
```

Windows 安装规则还要求：

```text
sqlcipher.dll
```

而本机提供的是：

```text
include/sqlite3.h
lib/x64-debug/sqlite3.lib
lib/x64-release/sqlite3.lib
bin/x64-debug/sqlite3.dll
bin/x64-release/sqlite3.dll
```

按现状执行 `-Dsqlcipher=ON` 会查找失败。

### 5.2 推荐修改方向

不建议继续兼容本机旧 `sqlite3.*` 二进制布局，也不通过复制、改名把 OpenSSL 4 版本伪装成目标依赖。推荐让 finder/package config 只消费 superbuild stage，并创建按配置区分的 imported target：

```text
SQLCipher::SQLCipher
  INTERFACE_INCLUDE_DIRECTORIES
  IMPORTED_IMPLIB_DEBUG
  IMPORTED_IMPLIB_RELEASE
  IMPORTED_LOCATION_DEBUG
  IMPORTED_LOCATION_RELEASE
  INTERFACE_COMPILE_DEFINITIONS
```

目标布局需要支持：

- 头文件位于 `stage/<config>/include/sqlcipher/sqlite3.h`；
- import library 为 `stage/<config>/lib/sqlcipher.lib`；
- DLL 为 `stage/<config>/bin/sqlcipher.dll`；
- Debug 与 Release 使用不同目录；
- 定义 `SQLITE_HAS_CODEC`；
- 项目以 `sqlcipher=ON` 启用 `ENABLE_SQLCIPHER`。

安装规则应从 imported target 的实际 DLL 路径部署文件，而不是重新执行一次只按文件名查找的 `find_file()`。

### 5.3 第一阶段只要求 Release

Visual Studio 是多配置生成器，但第一阶段建议只验证 Release：

```text
stage/Release/lib/sqlcipher.lib
stage/Release/bin/sqlcipher.dll
stage/Release/bin/libcrypto-3-x64.dll
stage/Release/bin/libssl-3-x64.dll
```

原因是 Debug SQLCipher 依赖 Microsoft Debug CRT，只适合开发机，且不能随正式安装器分发。

Release 稳定后，再补充 per-config Debug imported location。

## 6. SQLCipher 编译特性差异

本机 SQLCipher 当前启用：

- FTS3；
- FTS5；
- RTREE；
- GEOPOLY；
- 数学函数；
- JSON 函数；
- SQLCipher codec。

但与项目现有 Windows CI 相比，缺少或不同的项目包括：

| 特性 | 当前本机库 | 上游 Windows CI |
| --- | --- | --- |
| `SQLITE_MAX_ATTACHED` | 10 | 125 |
| `SQLITE_ENABLE_FTS3_PARENTHESIS` | 未显式启用 | 启用 |
| `SQLITE_ENABLE_STAT4` | 未启用 | 启用 |
| `SQLITE_SOUNDEX` | 未启用，`soundex()` 不存在 | 启用 |

这会造成用户可见功能和查询行为差异。正式发布前建议重新构建 SQLCipher 4.18.0，使其特性参数至少与当前项目 Windows CI 对齐。

## 7. OpenSSL 与 Qt TLS 版本统一

### 7.1 Qt 6.11.1 的实际版本基线

Qt 的版本要求需要分成两层理解：

- Qt 6.11 官方文档说明，Qt Online Installer 的构建在运行时要求 OpenSSL 3；
- Qt 官方 `Qt 6.11 Tools and Versions` 页面列出的 Qt 6.11.1 Windows x86_64 构建环境使用 OpenSSL x64 **3.5.4**。

本机 Qt 安装也提供了直接证据：

```text
qconfig.pri: opensslv30=yes, openssl=yes
qconfig.pri: openssl-linked=no, opensslv11=no
plugins/tls/qopensslbackend.dll: present
plugins/tls/qschannelbackend.dll: present
Qt bin OpenSSL DLL: not bundled
```

这表示 Qt 的 Windows 二进制包运行时动态加载 OpenSSL，而不是让 Qt DLL 在进程启动时硬链接到一个精确补丁版本。不能把“Qt 支持 OpenSSL 3”表述为“Qt 只接受 3.5.4”；3.5.4 只是 Qt 6.11.1 官方 Windows 构建/测试基线。

截至本文更新日，OpenSSL 3.5 LTS 最新版本为 3.5.7，官方漏洞列表显示 3.5.4 处于多个后来修复问题的受影响范围。OpenSSL 官方保证同一主版本 API/ABI 兼容，patch release 仅包含错误和安全修复。因此正式目标选择 3.5.7，而不是逐补丁复刻 Qt 构建机的 3.5.4。

### 7.2 OpenSSL 4.0.1 及其 SQLCipher 必须退出开发链路

本机 SQLCipher DLL 已经针对 OpenSSL 4.0.1 编译，并直接依赖 `libcrypto-4-x64.dll`；SQLCipher 数据库加密本身不需要 `libssl-4-x64.dll`。这些信息只解释现有文件来源。OpenSSL 4 import library、DLL、headers 和该 SQLCipher DLL 均不得进入本地开发、CTest、CI 或正式发布链路。

本地开发和正式 v4.0.0 构建都从官方源码固定 OpenSSL `openssl-3.5.7` 标签，SQLCipher 4.18.0 也必须使用这次构建生成的 headers 和 `libcrypto` 重新编译。本机 `C:\Program Files\OpenSSL-Win64` 不作为任何目标构建的搜索回退路径。

### 7.3 推荐部署方式

Windows 发布物统一包含：

- SQLCipher 4.18.0，链接 OpenSSL 3.5.7 `libcrypto`；
- `libcrypto-3-x64.dll`，由 SQLCipher 和 Qt OpenSSL backend 共享；
- `libssl-3-x64.dll`，供 Qt OpenSSL backend 使用；
- `qopensslbackend.dll`，作为首选 Qt TLS backend；
- `qschannelbackend.dll`，作为 Windows 原生 fallback。

运行时测试应确认：

- 完整发布物中 `QSslSocket::activeBackend()` 返回 `openssl`；
- Qt 报告的运行时 OpenSSL 版本为 3.5.7；
- SQLCipher 和 Qt plugin 没有通过系统 PATH 加载其他 OpenSSL；
- 专门移除 OpenSSL TLS 文件时，Qt 可以按设计回退到 Schannel；
- 缺少 `libcrypto-3-x64.dll` 时 SQLCipher 明确失败，不能静默加载系统中的其他版本。

项目当前无条件查找和复制 OpenSSL crypto/ssl DLL，后续应重构为统一 stage：

```text
SQLCipher             -> OpenSSL 3.5.7 Crypto
Qt OpenSSL TLS backend -> OpenSSL 3.5.7 SSL + Crypto
Qt TLS fallback       -> Windows Schannel
```

官方依据：

- https://wiki.qt.io/Qt_6.11_Tools_and_Versions
- https://doc.qt.io/QT-6/ssl.html
- https://www.openssl-library.org/source/
- https://www.openssl-library.org/news/vulnerabilities-3.5/
- https://www.openssl-library.org/policies/releasestrat/
- https://github.com/openssl/openssl/releases/tag/openssl-3.5.7

## 8. OpenSSL 3.5.7 源码构建影响与供应链要求

### 8.1 兼容性影响

- Qt：官方 Qt 6.11.1 Windows 包使用 OpenSSL 3 runtime，官方构建基线为 3.5.4。OpenSSL 官方保证同一主版本 API/ABI 兼容，因此 3.5.7 可以由 `qopensslbackend.dll` 在运行时加载，不需要重新编译 Qt；仍必须用 HTTPS/证书测试验证。
- SQLCipher：v4.18.0 的 OpenSSL provider 已使用 OpenSSL 3 `EVP_MAC`/EVP API，并使用 AES-256-CBC、PBKDF2、HMAC SHA1/256/512；与 3.5.7 默认 provider 匹配。现有 OpenSSL 4 版 SQLCipher 不能通过替换 DLL 复用，必须重编。
- 数据库格式：OpenSSL patch 版本不会主动修改 SQLCipher cipher/KDF/HMAC 配置，预期不改变 SQLCipher 4 文件格式；必须以旧库读取、修改重开、rekey、新库和错误密码测试确认。
- CMake/部署：DLL 名称变为 `libcrypto-3-x64.dll`、`libssl-3-x64.dll`，必须清理旧 CMake cache，并确保所有运行入口只读取统一 stage。

### 8.2 性能和 Provider 影响

SQLCipher v4.18.0 源码会在每次 HMAC 操作中执行 `EVP_MAC_fetch`/`EVP_MAC_free`。这不是 3.5.7 引入的正确性回归，但可能增加大数据库和多连接并发下的 CPU 与锁竞争，应建立升级前后基准。此次升级不直接维护 SQLCipher provider 私有性能补丁。

SQLCipher 参考 OpenSSL provider 的 `fips_status` 返回 0，因此使用 OpenSSL 3.5.7 源码不代表产品自动具备 FIPS 模式或认证。默认构建只使用 OpenSSL default provider，不依赖开发机的 OpenSSL 配置或 legacy provider。

### 8.3 当前安全公告影响

截至 2026-08-23，3.5.7 是 OpenSSL 3.5 LTS 最新已发布版本，但 `CVE-2026-14456` 将 3.5.0 至 3.5.7 列为受影响版本，计划在 3.5.8 修复。该低危问题位于 QUIC server 的待接收连接队列；当前 SQLiteBrowser 的 Qt HTTPS 客户端和 SQLCipher 数据库加密不属于其直接场景，因此可以使用 3.5.7 开展开发。

正式发布必须设置版本门禁：发布候选冻结前重新检查 OpenSSL 3.5 下载和漏洞页；如 3.5.8 或更高 3.5.x 已发布，则开发、CI、SQLCipher 和发布包整体同步升级并重跑验收。不能因文档曾固定 3.5.7 就忽略后续安全 patch。

### 8.4 供应链要求

本地开发与正式发布均必须从 OpenSSL 官方 `openssl-3.5.7` 标签和父仓库记录的精确 commit 使用 VS2022 自行构建，不再接受网上预编译包作为过渡输入。

需要记录：

- 源码 tag 和 commit；
- 下载文件 SHA-256；
- 构建命令；
- `/MD`、`/MDd` 配置；
- provider 配置；
- 许可证和 notices。

随后使用同一套可信 OpenSSL 重新构建 SQLCipher，并执行 SQLCipher 自身测试。

影响分析依据：

- https://github.com/sqlcipher/sqlcipher/blob/v4.18.0/src/crypto_openssl.c
- https://github.com/sqlcipher/sqlcipher/issues/597
- https://www.openssl-library.org/news/vulnerabilities-3.5/
- https://www.openssl-library.org/policies/releasestrat/

## 9. CMake 生成器与 Preset

### 9.1 推荐使用 Visual Studio 生成器

建议使用：

```text
Visual Studio 17 2022
x64
v143
Windows SDK 10.0.22621.0
```

相对继续使用 Ninja Multi-Config，其优势是：

- 不额外依赖 Ninja；
- 能直接表达 VS2022、x64、v143 和 SDK；
- 原生支持 Debug/Release 多配置；
- 与当前本地工具和 Visual Studio 调试体验一致。

### 9.2 目标配置参数

完成 Core5Compat 安装和 SQLCipher finder 修改后，配置参数应等价于：

```powershell
cmake -S . -B build/vs2022-x64 `
  -G "Visual Studio 17 2022" `
  -A x64 `
  -T v143 `
  -DCMAKE_SYSTEM_VERSION=10.0.22621.0 `
  -DQT_MAJOR=Qt6 `
  -DQt6_DIR="E:/QT/6.11.1/msvc2022_64/lib/cmake/Qt6" `
  -Dsqlcipher=ON `
  -DENABLE_TESTING=ON
```

建议最终将这些配置写入 `CMakePresets.json`，避免依赖开发者临时设置 PATH 或手工输入长命令。

## 10. NSIS 与发布物方案

项目当前正式 Windows 安装器使用 WiX 生成 MSI。NSIS 3.12 不能直接替代这一链路。

建议按以下顺序处理发布物：

1. 生成 Release EXE。
2. 执行 `windeployqt`。
3. 形成可运行目录。
4. 创建 portable ZIP。
5. 验证运行时依赖和功能。
6. 再建立 NSIS 安装器。

若选择 NSIS，需要重新实现并验证：

- 桌面与开始菜单快捷方式；
- 文件关联；
- 安装范围；
- VC143 Runtime；
- Qt plugins 和 translations；
- SQLCipher 与 libcrypto；
- 许可证；
- 升级与卸载；
- 安装器版本信息。

不要把 NSIS 迁移与第一次 VS2022 编译放在同一个阶段。

## 11. 分阶段实施方案

### 阶段 1：最小 Release 构建

- 安装 Qt Core5Compat。
- 修复 Git submodule 工具并安装 Perl、NASM。
- 仅支持 Windows x64。
- 仅验证 Release。
- 使用 VS2022/v143。
- 显式选择 SDK `10.0.22621.0`。
- 使用 Qt 6.11.1。
- 从子模块源码构建 OpenSSL 3.5.7 Release。
- 从子模块源码构建 SQLCipher 4.18.0 Release，且只链接上述 OpenSSL 3.5.7。
- 修改 SQLCipher package/finder 和 Windows 安装逻辑，使其只消费统一 stage。
- 启用项目 CTest。
- 暂不修改 `4.0.0` 版本号。
- 暂不构建安装器。

### 阶段 2：运行和功能验证

- 运行四个项目 CTest。
- 打开、编辑和保存普通 SQLite 数据库。
- 创建和打开 SQLCipher 4 数据库。
- 验证正确密码、错误密码和 rekey。
- 验证旧 SQLCipher 4 数据库。
- 验证 CSV 编码导入导出。
- 验证 FTS、JSON、RTREE、SOUNDEX 和 STAT4。
- 验证应用 HTTPS 请求。
- 确认 Qt TLS backend 为 OpenSSL、运行时版本为 3.5.7，并单独验证 Schannel fallback。

### 阶段 3：Debug 构建

- 为 SQLCipher target 增加 Debug/Release imported location。
- 验证 `/MD` 与 `/MDd`。
- 独立构建 OpenSSL 3.5.7 Debug。
- 使用同一 OpenSSL 3.5.7 Debug 构建 SQLCipher Debug。
- 执行 SQLCipher 自身测试。
- 固定依赖版本和校验值。

### 阶段 4：部署和 NSIS

- 整理 CMake install 规则。
- 运行 `windeployqt`。
- 部署 `qopensslbackend.dll`，并保留 `qschannelbackend.dll` 作为 fallback。
- 部署同一构建生成的 `libcrypto-3-x64.dll` 和 `libssl-3-x64.dll`。
- 生成 portable ZIP。
- 创建 NSIS 安装器。
- 验证安装、覆盖升级、卸载和文件关联。

### 阶段 5：版本切换

- 把 CMake、Windows 资源、NSIS 和 Release 的版本集中到单一来源。
- 设置 `4.0.0-rc1`。
- 验证候选版本。
- 确认最低 Windows 版本和兼容性承诺。
- 最后创建 `v4.0.0` 稳定 tag 和 Release。

## 12. 第一阶段准入与完成条件

### 开始修改前

- Qt Core5Compat 已安装。
- Git submodule 命令已修复。
- Perl、NASM、`cl` 和 `nmake` 已验证。
- 明确首个目标只包含 x64 Release。
- OpenSSL 3.5.7 tag、commit 和构建参数已记录。
- SQLCipher 4.18.0 的源码 tag、构建参数和产物路径已记录。
- 接受第一阶段只生成 SQLCipher-enabled 应用。

### 第一阶段完成条件

- CMake 明确报告 VS2022/v143。
- CMake 明确报告 Windows SDK `10.0.22621.0`。
- 找到 Qt 6.11.1 和 Core5Compat。
- OpenSSL 3.5.7 Release 已从子模块源码完成构建和测试。
- SQLCipher 4.18.0 Release 已从子模块源码构建并只依赖 OpenSSL 3.5.7。
- 应用完成 Release 编译。
- 四个 CTest 通过。
- 应用能打开普通 SQLite 和 SQLCipher 数据库。
- 构建目录之外没有依赖开发机 PATH 才能启动的隐式 DLL。

## 13. 推荐的下一步

在开始代码修改前，先通过 Qt Maintenance Tool 补装 Core5Compat，修复 Git submodule 工具并安装 Perl、NASM。随后第一批项目改动应严格限制为：

1. 增加 VS2022 x64 CMake Preset；
2. 引入 OpenSSL 3.5.7 和 SQLCipher 4.18.0 子模块；
3. 建立 OpenSSL → SQLCipher → SQLiteBrowser Release superbuild；
4. 改造 SQLCipher imported target，使其只消费统一 stage；
5. 让 Release 构建和 CTest 跑通。

第一批改动不应包含：

- 4.0.0 版本切换；
- NSIS；
- Qt 编码 API 重写；
- 大规模第三方依赖升级。

这样可以从第一天起保证开发和正式构建使用同一套 OpenSSL 3/SQLCipher 源码链路，避免先适配 OpenSSL 4 二进制后再返工。
