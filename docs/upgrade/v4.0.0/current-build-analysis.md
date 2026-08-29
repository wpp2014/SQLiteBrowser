# DB Browser for SQLite 当前构建方式与目标 Preset 分析

> 文档性质：当前分支只读分析与下一阶段设计
> 最后更新：2026-08-28
> 当前分支：`upgrade/v4.0.0`
> 分析基线：`1a6e345c37403f7fa20d2e029be5abd5fdfa9b8b`
> 目标平台：Windows x64
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
> 目标 Qt：Qt 6.11.1，由使用者提供安装根目录
> 当前已新增可版本化的 Preset 模板；主工程 CMake、源码、CI 和安装器仍未修改。

## 1. 结论

当前应用仍由根目录 `CMakeLists.txt` 直接配置。仓库提供 `CMakePresets.template.json`，开发者需要复制为本地 `CMakePresets.json` 并填写 Qt 根目录。依赖库的源码、构建脚本和 Debug/Release stage 已经完成，但主工程尚未完成严格 finder 和运行时部署改造。

下一阶段建议建立两个同名 configure/build/test preset：

| Preset | Binary directory | Configuration | Dependency stage |
| --- | --- | --- | --- |
| `debug` | `build/x64-shared-debug` | Debug | `x64-debug` |
| `release` | `build/x64-shared-release` | Release | `x64-release` |

命令语义必须明确：

```cmd
cmake --preset debug
cmake --build --preset debug
ctest --preset debug

cmake --preset release
cmake --build --preset release
ctest --preset release
```

`cmake --preset <name>` 只负责 configure，不会自动编译。若以后希望一条命令完成 configure/build/test，可另加 workflow preset，并使用 `cmake --workflow --preset <name>`。

构建完成后，应用目录必须是自包含的运行目录，不依赖开发者临时设置 Qt、OpenSSL 或 SQLCipher PATH。

## 2. 当前主工程 CMake 模型

### 2.1 顶层目标

根 `CMakeLists.txt` 当前：

- 最低要求 CMake 3.16；
- 项目版本为 `3.13.99`；
- 生成目标 `sqlitebrowser`；
- Qt5 使用 C++14，Qt6 使用 C++17；
- Qt6 依赖 Concurrent、Gui、LinguistTools、Network、PrintSupport、Test、Widgets、Xml 和 Core5Compat；
- `sqlcipher=ON` 时查找 `SQLCipher::SQLCipher`，否则查找 `SQLite::SQLite3`；
- `ENABLE_TESTING=ON` 时构建四个 CTest；
- 没有统一的配置专用 runtime 输出目录；
- 没有 build-time deploy target。

在 Windows 且 `sqlcipher=ON` 时，当前输出名为 `DB Browser for SQLCipher.exe`。如果后续希望 SQLCipher-enabled 构建仍显示“DB Browser for SQLite”，应作为产品命名决策单独处理，不能在 Preset 迁移中隐式改变。

### 2.2 内置 Qt 库

QScintilla、QCustomPlot 和 QHexEdit 的 CMake 使用未指定类型的 `add_library()`，因此会受全局 `BUILD_SHARED_LIBS` 影响，但当前 wrapper 没有为全部库完整配置 Windows DLL 导出/导入宏。

因此目标目录名中的 `shared` 应解释为“应用使用共享 Qt、SQLCipher、OpenSSL/Brotli 运行时”，不应在第一阶段把全局 `BUILD_SHARED_LIBS` 打开。建议 Preset 显式保持：

```text
BUILD_SHARED_LIBS=OFF
FORCE_INTERNAL_QSCINTILLA=ON
FORCE_INTERNAL_QCUSTOMPLOT=ON
FORCE_INTERNAL_QHEXEDIT=ON
```

这样三个内置库保持静态链接到应用，同时避免开发机上偶然找到不同版本的系统库。

### 2.3 Windows 平台逻辑

`config/platform_win.cmake` 仍包含旧的显式 linker flags：

```text
/SUBSYSTEM:WINDOWS,5.02
/ENTRY:mainCRTStartup
```

Debug/RelWithDebInfo 则使用控制台子系统和 `_CONSOLE`。

对于 VS2022 + Qt6，不建议继续用旧子系统版本和手写 entry point 覆盖 `WIN32_EXECUTABLE` 的默认行为。实施阶段应删除或重构这些 flags，并分别验证：

- Release 为 Windows GUI 子系统；
- Debug 是否继续保留控制台；
- Qt6 启动入口正常；
- 最低 Windows 版本由明确的产品策略决定，而不是由历史 `5.02` 偶然决定。

## 3. 当前依赖 stage

已存在以下 x64 Debug/Release stage：

| 依赖 | 版本 | 主要运行时 |
| --- | --- | --- |
| Brotli | 1.2.0 | `brotlicommon.dll`、`brotlidec.dll`、`brotlienc.dll` |
| zlib | 1.3.2 | `zlib1.dll` |
| zstd | 1.5.7 | `libzstd.dll` |
| OpenSSL | 3.5.7 | `libcrypto-3-x64.dll`、`libssl-3-x64.dll`，并动态使用 Brotli |
| SQLCipher | 4.18.0 / SQLite 3.53.4 | `sqlcipher.dll` |

SQLCipher 与 OpenSSL 的配置必须严格对应：

```text
Debug application
  -> SQLCipher x64-debug
  -> OpenSSL x64-debug
  -> Brotli x64-debug
  -> /MDd

Release application
  -> SQLCipher x64-release
  -> OpenSSL x64-release
  -> Brotli x64-release
  -> /MD
```

zlib 和 zstd 当前没有进入 DB Browser 主程序、SQLCipher 或当前 OpenSSL 的实际链接图。不能因为它们已经构建就无条件复制到应用目录；只有后续 target 或插件真实依赖时才部署。

### 3.1 SDK 不一致

本机已安装 SDK `10.0.26100.0`，但现有 Brotli、zlib、zstd、OpenSSL 和 SQLCipher manifest 全部记录为 SDK `10.0.22621.0`。

同一 MSVC v143 和 DLL CRT 模型下，使用 22621 构建的依赖通常可以被 26100 构建的应用链接和加载，因此可用于第一轮主程序接入验证。但这不满足“所有产物来自同一 SDK”的严格可复现要求。

建议采用两级门禁：

1. 主程序 bring-up 阶段允许消费现有 22621 stage，但配置日志必须明确警告 SDK 不一致。
2. CI、正式安装包和 Release 候选阶段，全部依赖必须用 SDK `10.0.26100.0` 重建，manifest 校验不一致时直接失败。

## 4. 当前依赖发现问题

### 4.1 SQLCipher finder

`cmake/FindSQLCipher.cmake` 当前只找到 header 和 `sqlcipher.lib`，并把 import library 写入 `IMPORTED_LOCATION`。它没有：

- 查找 `sqlcipher.dll`；
- 区分 `IMPORTED_IMPLIB` 与 `IMPORTED_LOCATION`；
- 暴露可靠的 runtime DLL 路径；
- 校验配置、CRT、manifest 或固定版本；
- 阻止 Debug/Release stage 混用。

实施时应让 `SQLCipher::SQLCipher` 成为正确的 Windows shared imported target：

```text
IMPORTED_IMPLIB  -> <stage>/lib/sqlcipher.lib
IMPORTED_LOCATION -> <stage>/bin/sqlcipher.dll
INTERFACE_INCLUDE_DIRECTORIES -> <stage>/include/sqlcipher
```

由于 debug/release preset 使用独立 binary directory，每个 configure 只接受一个配置专用 `SQLCIPHER_ROOT_DIR`，可以先采用单配置 stage finder；后续若需要一个 build tree 同时处理多个配置，再扩展 `IMPORTED_*_DEBUG/RELEASE`。

### 4.2 OpenSSL

项目当前使用普通 `find_package(OpenSSL ...)`，可能优先进入 CMake 内置 FindOpenSSL module。项目 OpenSSL stage 已提供 `OpenSSLConfig.cmake`，并正确声明：

- `OpenSSL::Crypto` 的 DLL 与 import library；
- `OpenSSL::SSL` 的 DLL 与 import library；
- `OPENSSL_RUNTIME_DIR`。

Windows 目标构建应优先使用配置模式并显式传入配置专用 `OpenSSL_DIR`，禁止扫描系统 OpenSSL。

## 5. Preset 设计

仓库提交 `CMakePresets.template.json`，其中 Qt 路径使用以下占位符：

```text
REPLACE_WITH_QT_6_11_1_MSVC2022_X64_ROOT
```

克隆仓库后应复制模板，不应移动或重命名被 Git 跟踪的模板：

```cmd
copy CMakePresets.template.json CMakePresets.json
```

然后只修改本地 `CMakePresets.json` 中的 `CMAKE_PREFIX_PATH`。Windows 路径建议使用 JSON 友好的正斜杠，例如：

```json
"CMAKE_PREFIX_PATH": "D:/Qt/6.11.1/msvc2022_64"
```

`CMakePresets.json` 和 `CMakeUserPresets.json` 已加入根 `.gitignore`，本机绝对路径不会进入提交；模板保持版本化。CMake 只识别复数形式 `CMakePresets.json`，`CMakePreset.json` 不会生效。

建议结构如下，具体字段在工程实施时验证：

```json
{
  "version": 6,
  "cmakeMinimumRequired": {
    "major": 3,
    "minor": 30,
    "patch": 3
  },
  "configurePresets": [
    {
      "name": "windows-x64-base",
      "hidden": true,
      "generator": "Visual Studio 17 2022",
      "architecture": {
        "value": "x64",
        "strategy": "set"
      },
      "toolset": {
        "value": "v143",
        "strategy": "set"
      },
      "cacheVariables": {
        "CMAKE_SYSTEM_VERSION": "10.0.26100.0",
        "CMAKE_PREFIX_PATH": "REPLACE_WITH_QT_6_11_1_MSVC2022_X64_ROOT",
        "QT_MAJOR": "Qt6",
        "sqlcipher": "ON",
        "ENABLE_TESTING": "ON",
        "BUILD_SHARED_LIBS": "OFF",
        "FORCE_INTERNAL_QSCINTILLA": "ON",
        "FORCE_INTERNAL_QCUSTOMPLOT": "ON",
        "FORCE_INTERNAL_QHEXEDIT": "ON"
      }
    },
    {
      "name": "debug",
      "inherits": "windows-x64-base",
      "binaryDir": "${sourceDir}/build/x64-shared-debug",
      "cacheVariables": {
        "CMAKE_CONFIGURATION_TYPES": "Debug",
        "OpenSSL_DIR": "${sourceDir}/build/openssl/x64-debug/stage/lib/cmake/OpenSSL",
        "SQLCIPHER_ROOT_DIR": "${sourceDir}/build/sqlcipher/x64-debug/stage"
      }
    },
    {
      "name": "release",
      "inherits": "windows-x64-base",
      "binaryDir": "${sourceDir}/build/x64-shared-release",
      "cacheVariables": {
        "CMAKE_CONFIGURATION_TYPES": "Release",
        "OpenSSL_DIR": "${sourceDir}/build/openssl/x64-release/stage/lib/cmake/OpenSSL",
        "SQLCIPHER_ROOT_DIR": "${sourceDir}/build/sqlcipher/x64-release/stage"
      }
    }
  ],
  "buildPresets": [
    {
      "name": "debug",
      "configurePreset": "debug",
      "configuration": "Debug"
    },
    {
      "name": "release",
      "configurePreset": "release",
      "configuration": "Release"
    }
  ],
  "testPresets": [
    {
      "name": "debug",
      "configurePreset": "debug",
      "configuration": "Debug",
      "output": {
        "outputOnFailure": true
      }
    },
    {
      "name": "release",
      "configurePreset": "release",
      "configuration": "Release",
      "output": {
        "outputOnFailure": true
      }
    }
  ]
}
```

完整且应保持同步的定义以仓库根目录 `CMakePresets.template.json` 为准。配置专用 OpenSSL/SQLCipher stage 使用 `${sourceDir}` 相对路径，不需要本机修改。当前工程在 finder、部署和 SDK 校验完成前，使用模板仍不能保证最终应用目录可直接运行。

## 6. 可直接运行的输出目录

现有 `config/install.cmake` 只在 `cmake --install` 时复制部分 DLL 并调用 `windeployqt`，不能保证 `cmake --build --preset ...` 后的 EXE 目录可运行。

建议主工程建立配置专用 runtime 目录：

```text
build/x64-shared-debug/bin/
build/x64-shared-release/bin/
```

应用 target 的 Debug/Release runtime output 都指向对应 preset 的 `bin`。构建后运行部署 target，使用 `Qt6::windeployqt` 对 `$<TARGET_FILE:sqlitebrowser>` 执行正确的 `--debug` 或 `--release` 部署，并明确启用 compiler runtime 部署。

项目自有依赖还需显式复制到同一个目录：

```text
sqlcipher.dll
libcrypto-3-x64.dll
libssl-3-x64.dll
brotlicommon.dll
brotlidec.dll
brotlienc.dll
```

OpenSSL 对 Brotli 使用动态加载，`dumpbin /dependents libcrypto-3-x64.dll` 不会显示这三个 Brotli DLL；不能因此漏掉它们。

Qt DLL 和 plugin 不维护手工文件清单，应交给与用户指定 Qt 安装相同的 `Qt6::windeployqt`。至少需要验证：

- Qt6 Core/Gui/Widgets/Network/Concurrent/PrintSupport/Test/Xml/Core5Compat；
- `platforms/qwindows.dll`；
- TLS plugins，包括 OpenSSL 与 Schannel backend；
- imageformats、styles、networkinformation 等实际扫描到的插件；
- MSVC/UCRT runtime 部署结果。

Debug 构建依赖 Microsoft Debug CRT，只保证在安装 VS2022 的开发机直接运行，不能作为可分发 portable 包。Release 才需要在未安装开发工具的干净机器上满足“复制后直接运行”。

## 7. 验收标准

### Configure

- generator 为 Visual Studio 17 2022；
- architecture 为 x64；
- toolset 为 v143；
- `CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION` 精确为 `10.0.26100.0`；
- Qt 为用户指定的 6.11.1 MSVC2022 x64；
- Core5Compat 和 `Qt6::windeployqt` 可用；
- SQLCipher/OpenSSL stage 与配置匹配；
- 不搜索系统 OpenSSL 或旧 SQLCipher。

### Build and test

- `cmake --build --preset debug` 成功；
- `cmake --build --preset release` 成功；
- 四个 CTest 在两个配置下运行；
- Release 不依赖 Debug CRT；
- SQLCipher DLL 只加载匹配配置的 OpenSSL；
- 主程序和依赖均为 x64。

### Runtime

- EXE 在对应 `bin` 目录直接启动；
- 临时移除 Qt 或 SQLCipher 必需 DLL 时能够明确失败，而不是从 PATH 偶然加载；
- Qt TLS backend 能加载项目 OpenSSL 3.5.7；
- 普通 SQLite 与 SQLCipher 数据库基本操作可用；
- Release 目录复制到干净 Windows 环境后可启动。

## 8. 当前未实施内容

本轮没有创建或修改：

- 本地 `CMakePresets.json` 已可由模板生成，但尚未执行 configure；
- 根 `CMakeLists.txt`；
- `FindSQLCipher.cmake`；
- `platform_win.cmake`；
- build-time deploy 规则；
- CI、NSIS、WiX、版本号或应用源码。

下一阶段工程修改应先完成 Preset、finder、输出目录和 deploy target，再实际执行 Debug/Release 主程序构建。
