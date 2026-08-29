# Windows 主程序构建方式升级方案

> 文档性质：DB Browser for SQLite 主工程下一阶段实施方案
> 最后更新：2026-08-28
> 当前分支：`upgrade/v4.0.0`
> 当前基线：`1a6e345c37403f7fa20d2e029be5abd5fdfa9b8b`
> 目标平台：Windows x64  
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
> 目标 Qt：Qt 6.11.1，安装路径由使用者提供
> 当前已新增可版本化的 Preset 模板；主工程 CMake 和源码仍未修改。

## 1. 目标状态

主工程升级完成后，开发者应能使用：

```cmd
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

生成：

```text
build/x64-shared-debug/
```

并使用：

```cmd
cmake --preset release
cmake --build --preset release
ctest --preset release
```

生成：

```text
build/x64-shared-release/
```

两个 build tree 完全隔离。每个 tree 内有一个可直接运行的 `bin` 目录，包含应用、Qt runtime/plugins、SQLCipher、OpenSSL、Brotli 和所需 MSVC runtime。

## 2. 当前前置条件状态

| 项目 | 当前状态 | 下一阶段处理 |
| --- | --- | --- |
| Visual Studio 2022 / v143 | 已安装并用于依赖构建 | Preset 固定 generator、x64、v143 |
| SDK 10.0.26100.0 | 已安装 | Preset 显式选择并在 configure 校验 |
| CMake 3.30.3 | 已安装 | 用于 Preset 和 workflow |
| Qt 6.11.1 x64 | Qt6Config、Core5Compat、windeployqt 均存在 | 路径由用户填写到本地 Preset |
| Git submodule | 已可递归初始化 | 不再是阻塞项 |
| Brotli 1.2.0 | Debug/Release stage 已完成 | OpenSSL 动态运行时依赖 |
| OpenSSL 3.5.7 | Debug/Release stage 已完成 | 主程序与 Qt TLS 共同使用 |
| SQLCipher 4.18.0 | Debug/Release stage 已完成 | 主程序唯一数据库 provider |
| zlib 1.3.2 | Debug/Release stage 已完成 | 当前不在应用运行时闭包 |
| zstd 1.5.7 | Debug/Release stage 已完成 | 当前不在应用运行时闭包 |

旧文档中“Core5Compat 缺失”“Git submodule 失效”“Perl/NASM 未验证”“SQLCipher 只完成 Release”等结论均已过时。

## 3. Qt 路径输入

仓库保存 `CMakePresets.template.json`，模板中的 Qt 根目录是显式占位符。克隆后复制模板：

```cmd
copy CMakePresets.template.json CMakePresets.json
```

不要使用 `move` 或直接重命名，因为模板是 Git 跟踪文件，移动后会让工作树显示模板被删除。打开本地 `CMakePresets.json`，将：

```text
REPLACE_WITH_QT_6_11_1_MSVC2022_X64_ROOT
```

替换为本机 Qt 6.11.1 MSVC2022 x64 根目录。建议使用正斜杠，例如：

```json
"CMAKE_PREFIX_PATH": "D:/Qt/6.11.1/msvc2022_64"
```

不需要设置 `SQLITEBROWSER_QT_ROOT` 或修改系统环境变量。根 `.gitignore` 忽略本地 `CMakePresets.json` 和 `CMakeUserPresets.json`，但不会忽略模板。

配置阶段必须验证：

- 占位符已替换；
- `lib/cmake/Qt6/Qt6Config.cmake` 存在；
- Qt 版本精确为 6.11.1；
- `Qt6::Core5Compat` 存在；
- `Qt6::windeployqt` 存在；
- Qt 架构为 x64。

CMake 的标准文件名是 `CMakePresets.json`（复数），不是 `CMakePreset.json`。

## 4. Preset 设计

### 4.1 共同设置

隐藏的 Windows base preset 应固定：

```text
generator = Visual Studio 17 2022
architecture = x64
toolset = v143
CMAKE_SYSTEM_VERSION = 10.0.26100.0
QT_MAJOR = Qt6
sqlcipher = ON
ENABLE_TESTING = ON
BUILD_SHARED_LIBS = OFF
FORCE_INTERNAL_QSCINTILLA = ON
FORCE_INTERNAL_QCUSTOMPLOT = ON
FORCE_INTERNAL_QHEXEDIT = ON
```

`BUILD_SHARED_LIBS=OFF` 是有意选择。目录名称中的 `shared` 表示 Qt、SQLCipher、OpenSSL/Brotli 为共享运行时，不表示把仓库内 QScintilla/QCustomPlot/QHexEdit 强制改成 DLL。

### 4.2 Debug preset

```text
name = debug
binaryDir = build/x64-shared-debug
CMAKE_CONFIGURATION_TYPES = Debug
OpenSSL_DIR = build/openssl/x64-debug/stage/lib/cmake/OpenSSL
SQLCIPHER_ROOT_DIR = build/sqlcipher/x64-debug/stage
application CRT = /MDd
```

### 4.3 Release preset

```text
name = release
binaryDir = build/x64-shared-release
CMAKE_CONFIGURATION_TYPES = Release
OpenSSL_DIR = build/openssl/x64-release/stage/lib/cmake/OpenSSL
SQLCIPHER_ROOT_DIR = build/sqlcipher/x64-release/stage
application CRT = /MD
```

Visual Studio 是多配置生成器，但仍使用两个 binary directory，原因是：

- 防止 Debug 与 Release CMake cache 混用；
- 与配置专用依赖 stage 一一对应；
- 便于独立清理、归档和部署；
- 避免一个 solution 意外链接另一配置的 import library。

### 4.4 Configure、build、test 的区别

```cmd
cmake --preset debug
```

只执行 configure。真正编译使用：

```cmd
cmake --build --preset debug
```

测试使用：

```cmd
ctest --preset debug
```

Release 同理。以后可增加 workflow preset 作为一条命令入口，但不能把 `cmake --preset` 描述成同时执行构建。

## 5. 主工程需要调整的文件

### 5.1 Preset 模板与本地 Preset

职责：

- 提交 `CMakePresets.template.json`；
- 由开发者复制出被忽略的本地 `CMakePresets.json`；
- 定义 base/debug/release configure preset；
- 定义同名 build/test preset；
- 固定 generator、architecture、toolset 和 SDK；
- 仅在本地副本填写 Qt 绝对路径；
- 为每个配置选择对应 OpenSSL/SQLCipher stage；
- 确保模板和提交历史不包含本机绝对路径。

### 5.2 根 CMakeLists.txt

建议增加：

- Windows-only 工具链检查；
- Qt 版本、架构和工具 target 检查；
- 配置专用 runtime 输出目录；
- 配置专用依赖 stage 校验；
- build-time deploy target；
- 对 VS 多配置生成器避免无意义设置 `CMAKE_BUILD_TYPE`。

第一阶段不修改项目版本号，也不调整应用功能源码。

### 5.3 cmake/FindSQLCipher.cmake

必须改成正确的 shared imported target：

```text
SQLCipher::SQLCipher
|- IMPORTED_IMPLIB: <stage>/lib/sqlcipher.lib
|- IMPORTED_LOCATION: <stage>/bin/sqlcipher.dll
|- INTERFACE_INCLUDE_DIRECTORIES: <stage>/include/sqlcipher
`- INTERFACE_COMPILE_DEFINITIONS: SQLITE_HAS_CODEC
```

同时验证：

- SQLCipher tag/commit；
- SQLite baseline；
- configuration；
- CRT；
- OpenSSL manifest hash；
- DLL、LIB、headers 和 manifest 全部存在。

不允许回退到系统 SQLCipher 或旧 `sqlite3.*` 布局。

### 5.4 config/platform_win.cmake

建议：

- Qt6 路径只由 Qt package target 提供；
- 使用项目 OpenSSL config package，而不是系统扫描；
- 删除历史 `/SUBSYSTEM:WINDOWS,5.02` 与手写 `/ENTRY:mainCRTStartup`；
- 继续决定 Debug 是否保留控制台；
- 显式验证 VS2022、x64、v143、SDK 26100。

### 5.5 config/install.cmake 与 build-time deploy

现有 install 逻辑依赖 `find_file()` 搜索 DLL，可能找到 PATH 或其他安装目录中的同名文件；而且只有 `cmake --install` 才运行。

建议把“开发构建可直接运行”和“安装包 staging”拆开，但共用同一份 runtime 清单：

- build-time deploy：构建后填充当前 binary tree 的 `bin`；
- install-time deploy：安装到独立 prefix；
- 两者都从 imported target 或明确 stage 复制，禁止再次全局搜索。

如果新增单独的 `config/*.cmake` 文件，需要注意仓库当前 `.gitignore` 全局忽略 `*.cmake`。实施时必须同步增加精确 whitelist，或把逻辑放进已有受跟踪文件。

## 6. 可运行目录设计

建议最终目录：

```text
build/x64-shared-<config>/bin/
|- DB Browser for SQLCipher.exe
|- sqlcipher.dll
|- libcrypto-3-x64.dll
|- libssl-3-x64.dll
|- brotlicommon.dll
|- brotlidec.dll
|- brotlienc.dll
|- Qt6*.dll
|- platforms/
|- tls/
|- imageformats/
|- styles/
|- networkinformation/
`- other files selected by windeployqt
```

应用名称来自当前 `sqlcipher=ON` 逻辑。是否更名不属于本轮构建迁移。

### 6.1 Qt runtime

使用 `Qt6::windeployqt`，目标是 `$<TARGET_FILE:sqlitebrowser>`，并传入：

- Debug：`--debug`；
- Release：`--release`；
- 编译器运行库部署；
- 输出目录：`$<TARGET_FILE_DIR:sqlitebrowser>`。

不能手写 Qt DLL/plugin 清单，也不能依赖用户 Qt `bin` 在 PATH 中。

### 6.2 项目依赖 runtime

显式从匹配 stage 复制：

| 文件 | 来源 |
| --- | --- |
| `sqlcipher.dll` | SQLCipher stage |
| `libcrypto-3-x64.dll` | OpenSSL stage |
| `libssl-3-x64.dll` | OpenSSL stage |
| 三个 Brotli DLL | OpenSSL stage 中经过集成验证的副本 |

OpenSSL 对 Brotli 使用动态加载，所以静态导入表检查不能替代文件部署。

zlib1.dll 和 libzstd.dll 当前不复制。以后只有在链接图、Qt plugin 或新功能真实引用时才加入。

### 6.3 Debug 与 Release 可运行含义

- Debug：在安装 VS2022 Debug CRT 的开发机直接运行；不可作为面向用户的 portable 包。
- Release：在未安装 Qt/OpenSSL/SQLCipher 的机器上直接运行；VC143 runtime 必须由 `windeployqt` 或安装器部署。
- 两个配置禁止互相复制 DLL。

## 7. SDK 26100 迁移策略

主程序 Preset 从第一天开始固定 `10.0.26100.0`。配置完成后必须检查：

```text
CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION=10.0.26100.0
```

现有依赖 stage 仍由 SDK 22621 构建。建议：

### Bring-up

- 允许主程序 26100 临时消费依赖 22621；
- 在配置和测试报告中记录混用；
- 不将该结果标记为正式可复现构建。

### Release gate

- 将 Brotli、zlib、zstd、OpenSSL、SQLCipher 构建入口统一升级到 26100；
- 重建 Debug/Release；
- manifest 全部精确匹配 26100；
- 主工程 configure 对 manifest 不一致直接失败；
- 重新执行依赖测试、主程序 CTest、运行时和干净机验证。

## 8. 推荐实施顺序

### 阶段 1：Preset 与严格依赖发现

1. 从 `CMakePresets.template.json` 复制本地 `CMakePresets.json`。
2. 填写并验证本地 Qt 根目录。
3. 升级 `FindSQLCipher.cmake`。
4. 强制使用 OpenSSL config package。
5. 清理历史 Windows linker flags。
6. 只执行 configure，确认 Debug/Release cache 没有串用。

### 阶段 2：主程序编译

1. 构建 Debug。
2. 构建 Release。
3. 验证 x64、v143、SDK 26100。
4. 验证 /MDd 与 /MD。
5. 运行四个 CTest。

### 阶段 3：可运行目录

1. 统一应用 runtime output 到各自 `bin`。
2. 增加 build-time deploy target。
3. 运行对应配置的 `windeployqt`。
4. 复制 SQLCipher/OpenSSL/Brotli DLL。
5. 审计 DLL 依赖和来源。
6. 启动应用并完成数据库/TLS smoke test。

### 阶段 4：统一 SDK

1. 把依赖构建 SDK 升级到 26100。
2. 重建全部依赖。
3. 启用严格 manifest gate。
4. 重新验证两个主程序 preset。

### 阶段 5：CI 和发布

1. CI 使用同一 preset。
2. Release 目录在干净 Windows 环境启动。
3. 再整理 CMake install、portable ZIP 和 NSIS。
4. 版本号与安装器升级另行处理。

## 9. 验收清单

### Debug

- configure/build/test preset 全部成功；
- 应用和所有项目 DLL 为 x64 Debug；
- SQLCipher/OpenSSL/Brotli 使用 Debug stage；
- `bin` 可在开发机直接启动；
- 没有 Release 依赖混入。

### Release

- configure/build/test preset 全部成功；
- 应用和全部 runtime 为 x64 Release；
- Release 不依赖 `VCRUNTIME140D.dll` 或 `ucrtbased.dll`；
- Qt TLS 能使用 OpenSSL 3.5.7；
- 普通 SQLite 和 SQLCipher 数据库可打开；
- 整个 `bin` 复制到干净机器后可启动；
- 不依赖用户 PATH 或系统 OpenSSL。

## 10. 本轮边界

本轮没有执行以上工程修改或主程序构建。文档中的 JSON、CMake target 和目录只是下一阶段实施契约；实际实现时应按阶段修改并逐步验证。
