# DB Browser for SQLite 当前构建方式分析

> 文档性质：升级前只读分析  
> 分析日期：2026-08-23  
> 分析基线：`1debae535a418b66267db56739a9bc0c9b4ac37b`  
> 目标约束：仅面向 Windows，计划使用 Visual Studio 2022 与 Windows SDK `10.0.22621.0`  
> 本文不代表已经完成构建迁移，也不包含对源码或构建配置的修改。

## 1. 结论摘要

当前项目采用 **CMake + Qt + MSVC/Ninja** 的构建体系：

- 根目录 `CMakeLists.txt` 是应用程序、测试、安装规则和 CPack 配置的总入口。
- Windows x86/x64 的正式构建基线位于 `.github/workflows/cppcmake-windows.yml`。
- 该 Windows 流程虽然运行在 GitHub 的 `windows-2022` runner 上，但会额外安装并显式激活 **Visual Studio 2019**，同时安装 Windows 10 SDK `10.0.19041`；因此它目前不是 VS2022 构建。
- x86/x64 默认使用 Qt `5.15.2` 的 MSVC 2019 预编译包、OpenSSL `1.1.1`、动态下载的最新 SQLite、SQLCipher `4.6.1`，并同时构建 SQLite 与 SQLCipher 两套应用。
- CMake 使用 `Ninja Multi-Config` 生成器，构建和测试均使用 `Release` 配置。
- Windows MSI 不是由 CPack 生成，而是由 `installer/windows` 下的 **WiX Toolset v3** 脚本生成；ZIP 又通过解包 MSI 得到。
- Windows ARM64 已有一条 VS2022 + Qt6 的独立流程，可以作为工具链迁移的参考，但它有独立安装器和依赖处理方式，不能直接等同于 x64 方案。
- 迁移到 VS2022 + SDK `10.0.22621.0` 时，至少需要同步处理 CI 工具链选择、SDK 锁定、Qt/CRT 二进制兼容性、WiX 中的 VC 运行库来源，以及版本号的多个硬编码位置。

本次没有执行 CMake configure、编译或测试，因为这些操作会生成构建目录和缓存，不符合“除分析文档外不做改动”的限制。

## 2. 仓库与分支现状

### 2.1 Git 状态

- 当前工作分支：`upgrade/v4.0.0`
- `master`、`origin/master` 与当前分支均指向同一提交 `1debae53`。
- `origin` 指向 fork：`https://github.com/wpp2014/SQLiteBrowser.git`
- `upstream` 指向上游：`https://github.com/sqlitebrowser/sqlitebrowser.git`
- 当前仓库不是 shallow clone，但本地没有 tag。
- 分析开始前工作区干净。

“只 fork 了 master”本身不妨碍升级开发，但当前缺少 tag 会带来两个问题：

1. 无法仅依赖本地 tag 还原历史发布边界或比较 `v3.13.1...HEAD`。
2. 新版本发布前需要明确 fork 自己的 tag/release 策略，不能假设上游发布 tag 已经存在于本地。

另一个重要事实是：本地 `HEAD` 的提交日期为 **2026-08-09**，并不是两年前。仓库中 `README.md` 记录的最近稳定版是 2024-10-16 发布的 `3.13.1`，但 master 分支仍有之后的开发提交。后续升级应以实际提交基线为准，而不是仅以最近稳定版日期判断代码年龄。

### 2.2 CI 对分支的影响

总 CI `.github/workflows/cppcmake.yml` 的 `push` 触发器只监听 `master`。因此：

- 将 `upgrade/v4.0.0` 直接推送到 fork 时，不会因普通 push 自动运行总 CI。
- 针对该分支创建 Pull Request，或手动执行 `workflow_dispatch`，可以触发 CI。
- 总 CI 当前会同时调用 macOS、Ubuntu、Windows x86/x64 和 Windows ARM64；这与“以后只针对 Windows”的目标不一致。
- 总 CI 的发布任务依赖所有平台构建成功。如果未来只保留 Windows 发布，需要调整 CI 编排，而不只是 Windows 子工作流。

## 3. CMake 构建模型

### 3.1 顶层入口

根目录 `CMakeLists.txt`：

- 要求 CMake `3.16` 或更高版本。
- 项目名为 `sqlitebrowser`。
- CMake 项目版本为 `3.13.99`。
- 启用 Qt 的 `AUTOMOC`、`AUTORCC` 和 `AUTOUIC`。
- 生成 GUI 可执行文件；Windows 下设置 `WIN32_EXECUTABLE`。
- 根据 Qt 主版本选择 C++ 标准：Qt5 使用 C++14，Qt6 使用 C++17。
- 查找 Qt 的 Concurrent、Gui、LinguistTools、Network、PrintSupport、Test、Widgets、Xml 等组件；Qt6 额外依赖 Core5Compat。
- 查找 SQLite3；启用 `sqlcipher` 选项时改为查找 SQLCipher。
- 通过 `config/*.cmake` 组织平台、第三方库、翻译和安装逻辑。
- `ENABLE_TESTING=ON` 时加入 `src/tests`。

项目没有 `CMakePresets.json`，所以当前没有一个仓库内、可复用且能明确表达 VS 版本、体系结构、SDK 版本和依赖路径的本地构建预设。实际构建参数主要存在于 GitHub Actions 命令中。

### 3.2 主要 CMake 选项

`config/options.cmake` 定义了以下关键选项：

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `QT_MAJOR` | `Qt5` | 选择 Qt5 或 Qt6 |
| `BUILD_STABLE_VERSION` | `OFF` | 控制稳定版与日期型开发版版本信息 |
| `ENABLE_TESTING` | `OFF` | 是否构建测试 |
| `FORCE_INTERNAL_QSCINTILLA` | `OFF` | 强制使用仓库内 QScintilla |
| `FORCE_INTERNAL_QCUSTOMPLOT` | `ON` | 默认使用仓库内 QCustomPlot |
| `FORCE_INTERNAL_QHEXEDIT` | `ON` | 默认使用仓库内 QHexEdit |
| `ALL_WARNINGS` | `OFF` | 启用额外警告 |
| `sqlcipher` | `OFF` | 构建 SQLCipher 版本 |

QScintilla 会先尝试查找系统安装版本，找不到时使用仓库内版本；QCustomPlot 与 QHexEdit 默认直接使用仓库内源码。

### 3.3 Windows 平台逻辑

`config/platform_win.cmake` 当前包含以下 MSVC 特有行为：

- Qt5 要求 OpenSSL `1.1.1`，Qt6 要求 OpenSSL `3.0.0`。
- Release x64 链接参数写入 `/SUBSYSTEM:WINDOWS,5.02 /ENTRY:mainCRTStartup`。
- Debug 和 RelWithDebInfo 使用控制台子系统。
- 将 `src/winapp.rc` 加入目标，用于图标和 Windows 版本资源。

`config/install.cmake` 的 Windows 安装步骤会：

- 安装应用 EXE。
- 查找并安装 `sqlite3.dll` 或 `sqlcipher.dll`。
- 查找并安装 OpenSSL 的 crypto/ssl DLL。
- 安装许可证文件。
- 查找并调用 `windeployqt.exe` 部署 Qt 运行时。

这套 CMake install/CPack 规则存在，但当前 GitHub Actions 的正式 MSI 流程主要直接消费构建输出和依赖目录，并不以 CPack 作为最终 Windows 发布链路。

## 4. 当前 Windows x86/x64 CI 构建链路

`.github/workflows/cppcmake-windows.yml` 的矩阵为：

- runner：`windows-2022`
- 架构：`x86`、`x64`

完整链路如下：

1. 安装 Ninja。
2. 安装 OpenSSL `1.1.1.2100`；x86 与 x64 使用不同 Chocolatey 安装路径。
3. 安装 Qt `5.15.2`：
   - x86：`win32_msvc2019`
   - x64：`win64_msvc2019_64`
4. 额外安装 Visual Studio 2019 Community，并包含：
   - `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`
   - `Microsoft.VisualStudio.Component.Windows10SDK.19041`
   - `Microsoft.VisualStudio.Component.VC.Redist.MSM`
5. 通过 `ilammy/msvc-dev-cmd` 显式选择 VS2019 工具链。
6. 从 SQLite 官网动态解析并下载“最新” amalgamation 源码，使用 `cl` 构建 `sqlite3.dll`。
7. 下载 SQLean：x86 固定为 `0.27.4`，x64 下载当时最新 release。
8. 构建项目自带的 `formats.dll` SQLite 扩展。
9. 下载并使用 `nmake` 构建 SQLCipher `4.6.1`。
10. 分别配置两个构建目录：
    - `release-sqlite`
    - `release-sqlcipher`
11. 两套配置都使用 `Ninja Multi-Config`、启用测试，并执行 Release 构建。
12. 对两套构建分别执行 `ctest -C Release --output-on-failure`。
13. 调用 `installer/windows/build.cmd` 创建 MSI。
14. 将未签名 MSI 上传到 SignPath，等待签名结果。
15. 通过 `msiexec /a` 解包 MSI，再压缩为 ZIP。
16. 上传 MSI 和 ZIP，并记录实际依赖版本摘要。

### 4.1 当前 SDK 并未锁定在 CMake 参数中

现有流程安装 SDK `10.0.19041`，但 CMake 命令没有传入 `CMAKE_SYSTEM_VERSION`。SDK 的实际选择依赖激活的 VS2019 开发环境及其可用 SDK。

未来若要求严格使用 `10.0.22621.0`，仅把 runner 保持为 `windows-2022` 或把 `vsversion` 改为 `2022` 都不够。迁移实现中需要：

- 确保 VS2022 安装了 `Microsoft.VisualStudio.Component.Windows11SDK.22621`（组件命名应在实施时验证）。
- 在工具链初始化或 CMake 配置阶段明确选择 SDK。
- 在构建日志中输出并校验最终使用的 Windows SDK 版本，避免机器上同时存在多个 SDK 时静默选择更高版本。

使用 Visual Studio 生成器时，典型表达形式会包含 `-G "Visual Studio 17 2022" -A x64 -T v143 -DCMAKE_SYSTEM_VERSION=10.0.22621.0`；如果继续使用 Ninja Multi-Config，则需要先用 VS2022/v143/指定 SDK 初始化开发环境，再运行 CMake。最终选哪一种应在迁移方案阶段确定。

## 5. 测试体系

测试由 CMake/CTest 管理，`src/tests/CMakeLists.txt` 当前定义四个测试可执行文件：

- `test-sqlobjects`
- `test-import`
- `test-regex`
- `test-cache`

Windows CI 会对 SQLite 和 SQLCipher 两种构建分别运行全部 CTest。现有测试主要是单元级测试，尚未看到安装后启动、DLL 完整性、MSI 升级/卸载、文件关联、签名验证等 Windows 发布物级自动化测试。

因此 VS2022 迁移的验证不能只以“编译成功”作为完成标准，至少还应覆盖：

- SQLite 与 SQLCipher 两个 EXE 可启动。
- Qt、OpenSSL、SQLite/SQLCipher DLL 装载正常。
- 四个 CTest 在 Release 下通过。
- MSI 安装、启动、升级和卸载路径正常。
- ZIP 解压后可独立运行。
- x64/x86/ARM64 中实际保留的目标架构分别验证。

## 6. Windows 安装与发布

### 6.1 WiX MSI

标准 x86/x64 安装器位于 `installer/windows`：

- `build.cmd` 调用 WiX `candle.exe` 与 `light.exe`。
- 支持 `x86` 和 `x64` 参数。
- `variables.wxi` 将产品版本硬编码为 `3.13.99`。
- VC 运行库合并模块路径硬编码到 VS2019 Community 的 `14.29.30133` 目录。
- 合并模块名硬编码为 `Microsoft_VC142_CRT_$(sys.BUILDARCH).msm`。
- 构建输出路径固定为 `release-sqlite/Release` 和 `release-sqlcipher/Release`。

因此 VS2022 迁移必须同步更新安装器的 VC142/VS2019 假设，否则即使应用已经由 v143 编译，MSI 仍可能打入错误或不存在的 CRT 合并模块。

ARM64 安装器位于 `installer/windows_on_arm`，已经引用 VS2022 的 VC143 CRT 路径，但路径中包含特定 Enterprise 安装位置和精确工具集版本号，仍然不具备跨 runner/开发机的可移植性。

### 6.2 CPack 与实际发布物

顶层 CMake 在 Windows 下默认设置 CPack ZIP，并保留 NSIS/WiX 相关参数；但当前 CI 的实际发布物来源是：

- WiX 脚本生成 MSI。
- `msiexec /a` 从 MSI 提取文件。
- PowerShell `Compress-Archive` 生成 ZIP。

也就是说，当前仓库同时存在 CPack 打包配置和独立 WiX 发布链路，但 CI 以独立 WiX 链路为准。升级时应明确哪个才是唯一受支持的发布路径，避免两套打包定义继续漂移。

### 6.3 GitHub Release

总 CI 对非 Pull Request 构建会调用 `.github/workflows/release.yml`，发布到可移动的 `nightly` 或 `continuous` tag，并统一标记为 prerelease。单独手动运行 Windows 子工作流时会使用基于提交 SHA 的 Windows tag。

这套工作流没有直接表达“创建稳定版 `v4.0.0`”的流程。因此新稳定版本至少还需要单独设计：

- 稳定版 tag 命名。
- Release 是否为 prerelease。
- MSI/ZIP 文件名中的稳定版本号。
- 签名策略从测试签名切换到正式签名。
- Winget 发布触发条件。
- 更新日志与升级兼容策略。

## 7. 当前依赖基线

| 依赖 | 当前来源/版本 | 可复现性观察 |
| --- | --- | --- |
| Qt（x86/x64） | install-qt-action，Qt `5.15.2`，MSVC2019 包 | 版本固定 |
| Qt（ARM64） | Qt6 | 与标准 x86/x64 流程不同 |
| OpenSSL（x86/x64） | Chocolatey `1.1.1.2100` | 包版本固定，但 OpenSSL 1.1.1 已是旧主线 |
| SQLite | 构建时从官网解析最新 amalgamation | 未固定版本，构建不可完全复现 |
| SQLCipher | `4.6.1` | 固定版本 |
| SQLean x86 | `0.27.4` | 固定版本 |
| SQLean x64 | GitHub 最新 release | 未固定版本 |
| QScintilla | 仓库内 `2.14.1`，系统找不到时回退 | 结果依赖环境；CI 通常回退到内置版本 |
| QCustomPlot | 仓库内 `2.1.1` | 固定版本 |
| QHexEdit | 仓库内 `0.8.6` | 固定版本 |
| nlohmann/json | 仓库内 `3.10.4` 单头文件 | 固定版本 |
| WiX | Windows 安装器使用 WiX v3 工具 | 依赖 runner/环境提供，路径处理不统一 |

当前最大可复现性问题是 SQLite 与 x64 SQLean 使用“最新版本”。这意味着同一个项目提交在不同日期构建，可能得到不同二进制和行为。版本升级期间应优先改为显式版本和校验值。

## 8. 版本号来源与 4.0.0 风险

当前至少存在三套版本来源：

1. `CMakeLists.txt`：项目开发版本 `3.13.99`。
2. `installer/windows/variables.wxi` 与 `installer/windows_on_arm/variables.wxi`：MSI 产品版本 `3.13.99`。
3. `currentrelease`：稳定版本 `3.13.1` 及其发布页面。

此外：

- `src/version.h.in` 从 CMake 项目版本生成应用版本宏。
- 非稳定构建默认附加 `YYYYMMDD` 日期型 `BUILD_VERSION`。
- `src/winapp.rc` 使用这些宏生成 Windows 文件版本和产品版本。
- CI 产物文件名对 nightly 使用日期，对开发构建使用 Git 短 SHA，并不直接使用 CMake 项目版本。

因此新建 `4.0.0` 版本不应只是替换某一个字符串。建议在升级实施前先确定一个“唯一版本源”，再让 CMake、Windows 资源、WiX、产物命名和 Release tag 从该来源派生。否则很容易出现应用 About 页面、EXE 属性、MSI 产品版本和 GitHub Release 名称互不一致。

还需注意 WiX/MSI 的版本和 UpgradeCode/ProductCode 规则。跨到 `4.0.0` 是否能覆盖升级旧的 3.x 安装，需要通过 MSI 升级场景验证，而不能仅凭版本字符串判断。

## 9. 与目标工具链的差距

| 项目 | 当前 x86/x64 状态 | 目标 | 差距 |
| --- | --- | --- | --- |
| 操作系统范围 | CI 同时覆盖 Windows、Linux、macOS | 仅 Windows | 需调整总 CI 与发布依赖关系 |
| 编译器 | VS2019 / v142 | VS2022 / v143 | 需切换开发环境和运行库打包 |
| Windows SDK | 安装 10.0.19041，未在 CMake 显式锁定 | 10.0.22621.0 | 需安装、选择并校验 |
| CMake 生成器 | Ninja Multi-Config | 尚未决定 | 可继续 Ninja，也可改 VS 2022 生成器 |
| Qt | Qt 5.15.2 MSVC2019 预编译包 | 尚未决定 | 需决定保留 Qt5 还是统一到 Qt6，并验证 VS2022 兼容性 |
| 架构 | x86、x64，另有 ARM64 | 尚未决定 | “仅 Windows”不足以确定保留哪些架构 |
| 安装器 CRT | VS2019 VC142 合并模块硬编码 | VS2022 VC143 | 必须更新并去除脆弱的绝对版本路径 |
| 版本源 | 多处硬编码 | 4.0.0 | 需统一版本来源与稳定发布流程 |

## 10. 建议的升级顺序（仅建议，尚未实施）

建议把升级拆成可验证的小阶段：

1. **冻结基线**：补齐上游 tag 信息，记录当前依赖实际版本，并确定首要目标架构。若没有兼容需求，建议先以 Windows x64 为最小闭环。
2. **建立可重复的本地构建入口**：增加 CMake Preset 或等效脚本，明确 VS2022/v143、SDK `10.0.22621.0`、架构、Qt 路径和依赖路径。
3. **只迁移编译器与 SDK**：暂不同时升级 Qt/SQLite/SQLCipher，先让现有代码在 VS2022 + 指定 SDK 下编译并通过 CTest，以缩小问题来源。
4. **迁移 Windows CI**：把 VS2019/19041 替换为 VS2022/22621，并在日志中验证实际工具链；将 fork 的 CI 改为 Windows 范围。
5. **修正发布物链路**：升级或整理 WiX 配置、VC143 运行库部署、签名、MSI/ZIP 冒烟测试。
6. **逐项升级第三方依赖**：每次只升级一类依赖，固定版本与校验值，并保留可回退提交。
7. **统一版本管理**：将版本号集中到单一来源，再切换为 `4.0.0` 候选版本。
8. **发布候选版**：先发布 `4.0.0-rc` 或等效预发布版本，验证旧版本升级、全新安装、便携 ZIP 和签名。
9. **稳定发布**：创建稳定 tag/release，更新 `currentrelease`、变更日志和 Winget 流程。

不建议在同一个提交中同时完成 VS2022、SDK、Qt 主版本、SQLite/SQLCipher、WiX 和应用版本号升级；这些变化的故障表现高度重叠，会显著增加定位难度。

## 11. 尚需确认的决策

进入修改阶段前，建议由维护者明确以下事项：

1. Windows 架构范围：仅 x64，还是保留 x86 与 ARM64？
2. Qt 路线：保留 Qt 5.15.2，还是迁移 Qt6？
3. 是否继续同时发布 SQLite 与 SQLCipher 两个应用？
4. 是否继续使用 WiX v3，还是迁移到较新的安装器方案？
5. 是否保留 CPack Windows 配置，还是明确 WiX 为唯一发布链路？
6. `4.0.0` 是否表示存在不兼容变更；如果只是工具链和依赖升级，是否更适合沿用 3.x 语义？
7. fork 的 GitHub Actions 是否具备 SignPath secrets；没有时是否允许生成未签名测试包？
8. 稳定发布是否需要自动发布到 Winget？

## 12. 本机环境观察

本次只读检查显示当前开发机已经具备：

- CMake `3.30.3`
- Ninja `1.12.1`
- Visual Studio Enterprise 2022 `17.14.37`
- Windows SDK `10.0.22621.0`（同时还安装了 `10.0.10240.0` 与 `10.0.26100.0`）

这说明目标 SDK 在本机存在，但多个 SDK 并存进一步说明后续必须显式选择并验证 `10.0.22621.0`。本次未检查 Qt、OpenSSL、SQLite/SQLCipher 的本机可用性，也未尝试配置项目。

## 13. 文档路径评估

仓库此前没有 `docs/` 目录，已有的用户/贡献者文档（例如 `README.md`、`BUILDING.md`）位于根目录。尽管如此，本分析属于 fork 的升级过程记录，不宜在尚未验证前直接改写正式的 `BUILDING.md`。

本文件采用：

`docs/upgrade/v4.0.0/current-build-analysis.md`

该路径符合用户要求的 `./docs` 范围，并为后续的迁移方案、实施记录、依赖清单和测试报告预留了同一版本目录。因此目前判断 **不需要调整路径**，也没有移动现有文档。

如果未来目标变为向上游提交正式构建说明，则应在升级完成并验证后，再把最终、稳定的用户操作部分整理回根目录 `BUILDING.md`；这属于后续改动，需要维护者另行确认。
