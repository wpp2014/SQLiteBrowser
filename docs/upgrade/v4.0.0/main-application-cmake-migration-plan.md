# DB Browser for SQLite 主程序 CMake 改造实施方案

> 文档性质：迁移实施方案与阶段执行记录
> 最后更新：2026-08-31
> 当前分支：upgrade/v4.0.0
> 分析基线：1a6e345c37403f7fa20d2e029be5abd5fdfa9b8b
> 目标平台：Windows x64
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK 10.0.26100.0
> 目标 Qt：Qt 6.11.1 MSVC2022 x64，本地路径由开发者在 CMakePresets.json 中填写
> 当前状态：原主程序阶段 0 至阶段 4、统一输出阶段 6、独立单元测试阶段 7、严格 package runtime 阶段 8、空目录全链路验证阶段 9 和 README 正式入口阶段 10 均已完成；install、干净机器 Release gate、ZIP/NSIS、签名和版本号仍待后续阶段。

## 0.1 统一输出阶段 6 检查点（2026-08-30）

本文后续 `build/x64-shared-<config>` 路径记录的是原阶段 1 至阶段 4 的历史实施结果。统一输出重构阶段 6 已将当前正式路径改为：

~~~text
output/x64-shared-debug/build/sqlitebrowser
output/x64-shared-debug/bin
output/x64-shared-release/build/sqlitebrowser
output/x64-shared-release/bin
~~~

`CMakePresets.template.json` 和本地 Preset 现在绑定同配置的 `output/.../build/openssl/stage`、`output/.../build/sqlcipher/stage` 和 `SQLITEBROWSER_CONFIGURATION_ROOT`。build preset 显式只构建 `sqlitebrowser`；EXE/PDB、Qt runtime 及 SQLCipher/OpenSSL/Brotli runtime 进入公共 development `bin`。SDK policy 已切换为 `STRICT`。

Debug、Release 的 configure、build 和 POST_BUILD development 校验均已通过。阶段 5 依赖聚合在主程序部署后重复执行，也不会删除或改写应用与 Qt 文件。公共 `bin` 仍是开发输出；阶段 8 已在独立目录完成 package runtime 的严格整理。

## 0.2 统一输出阶段 7 检查点（2026-08-30）

四个单元测试已改为 `EXCLUDE_FROM_ALL`，由 `sqlitebrowser_unit_tests` 聚合 target 显式构建，并输出到：

~~~text
output/x64-shared-debug/build/tests/unit
output/x64-shared-release/build/tests/unit
~~~

正式测试入口为：

~~~cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
~~~

两个 workflow 都执行 configure、对应 `unit-tests-*` build preset 和 CTest，实际结果均为 4/4 通过。普通 `debug`/`release` 产品 build preset 仍只构建 `sqlitebrowser`；复跑产品构建没有重新生成测试 EXE，公共 `bin` 也没有测试程序。

## 0.3 Package runtime 阶段 8 检查点（2026-08-31）

新增非默认 `sqlitebrowser_package_runtime` target，从严格验证过的 development `bin` 按文件 allowlist 生成：

~~~text
output/x64-shared-debug/package/runtime
output/x64-shared-release/package/runtime
~~~

正式入口为 `package-debug`、`package-release`、`smoke-debug` 和 `smoke-release` workflow。Debug/Release package runtime 分别为 70/71 个文件，不包含 `.lib`、PDB、zlib、zstd、测试或依赖 CLI；两套受限 `PATH` smoke 的应用启动、SQLCipher、OpenSSL Brotli 和 Qt HTTPS 均通过。详细契约见 [main-application-package-runtime-guide.md](main-application-package-runtime-guide.md)。

## 0.4 空目录全链路阶段 9 检查点（2026-08-31）

删除原 `output/` 后，已按依赖层级重新构建并测试 Brotli、zlib、zstd、OpenSSL、SQLCipher、统一依赖输出和主程序的 Debug/Release。主程序单元测试两个配置均为 4/4 通过，development `bin` 分别严格校验为 89/90 个文件，package runtime 分别严格校验为 70/71 个文件。

两份 package runtime manifest 的 SHA-256 逐项复算失败数均为 0；package 禁止项与公共 `bin` 中测试/CLI 可执行文件数量均为 0。Debug/Release 的应用启动、SQLCipher 加密数据库、OpenSSL Brotli 与 Qt OpenSSL HTTPS smoke 全部通过。OpenSSL 仅声明 safe 测试通过，`test_bio_dgram` 明确排除；SQLCipher Tcl suite 未运行。完整记录见 [phase-9-clean-build-validation.md](phase-9-clean-build-validation.md)。

## 0.5 README 正式入口阶段 10 检查点（2026-09-01）

README 的 Windows v4 构建章节已切换为阶段 9 验证过的正式命令，覆盖工具链、clone/submodule、五个依赖的 check/build/test、Preset 模板、产品构建、独立单元测试、package runtime 和受限 `PATH` smoke。开发者只需在被忽略的本地 `CMakePresets.json` 中填写 Qt 路径。

README 已明确区分 development `bin` 与严格 `package/runtime`，未来 ZIP/NSIS 只能消费后者；`smoke-debug`、`smoke-release` 成为公开 smoke 入口。完整记录见 [phase-10-readme-build-guide-validation.md](phase-10-readme-build-guide-validation.md)。

## 1. 结论

CMakePresets.template.json 的目录、工具链和依赖 stage 设计已经用于阶段 1 至阶段 10。Debug、Release 两套 Preset 均可完成 configure、产品 build、单元测试、package runtime 组装和显式 runtime smoke，各自只引用匹配配置的 OpenSSL 与 SQLCipher stage；README 已将这些入口作为正式开发流程。

阶段 1 至阶段 10 已解决 Qt/toolchain 配置门禁、依赖配置绑定、统一开发输出、最小产品构建、独立单元测试、严格 package runtime、受限 PATH smoke、空目录可重复构建验证和开发者 README 入口。后续优先事项：

1. install、ZIP 和安装器尚未改为只消费已验证的 package runtime。
2. 许可证布局、归档格式、签名和版本号尚未形成发布契约。
3. Release 尚未在没有 Qt/OpenSSL/SQLCipher 开发环境的干净 Windows 上验证。

建议依次打通“可配置、可编译、可测试、可部署、可验证”，暂不同时修改安装器、版本号或功能代码。

## 2. 当前 Preset 状态

仓库保留可提交的 CMakePresets.template.json。本地已经从模板生成被 Git 忽略的 CMakePresets.json，并填写开发者自己的 Qt 路径。其他开发者首次使用时执行：

~~~cmd
copy CMakePresets.template.json CMakePresets.json
~~~

然后只替换 CMAKE_PREFIX_PATH 的 Qt 占位符。不需要设置 SQLITEBROWSER_QT_ROOT，也不能提交带本机绝对路径的文件。

模板已经通过 `cmake --list-presets=all` 解析，可识别产品、单元测试、package runtime 和 smoke 的 Debug/Release Preset；本地文件保持 ignored。

目标命令：

~~~cmd
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
cmake --build --preset debug --target sqlitebrowser_runtime_smoke

cmake --preset release
cmake --build --preset release
ctest --preset release
cmake --build --preset release --target sqlitebrowser_runtime_smoke
~~~

最终运行目录：

~~~text
build/x64-shared-debug/bin/
build/x64-shared-release/bin/
~~~

## 3. 阶段 1 前的构建图与源码问题

阶段 1 实施前的顶层顺序：

~~~text
project
  -> options
  -> add_executable
  -> platform/OpenSSL/历史 linker flags
  -> Qt
  -> 内置 QScintilla/QCustomPlot/QHexEdit
  -> SQLCipher
  -> sources/UI/translations/resources
  -> link/install/tests
~~~

### 3.1 Visual Studio 多配置

顶层在 CMAKE_BUILD_TYPE 为空时写入 Release。Visual Studio 的实际配置由 build preset 的 configuration 决定，因此只应在单配置生成器下设置默认值。

Debug 和 Release 继续使用两个 binary tree，并把 CMAKE_CONFIGURATION_TYPES 分别限制为单一配置，防止 cache 和依赖 stage 串用。

### 3.2 Windows GUI 入口

阶段 2 实施前同时设置 WIN32_EXECUTABLE 和以下历史参数：

~~~text
/SUBSYSTEM:WINDOWS,5.02
/ENTRY:mainCRTStartup
~~~

阶段 2 已按以下方案完成：

1. 先精确找到 Qt 6.11.1；
2. 使用 qt_add_executable(sqlitebrowser WIN32)；
3. 让 Qt6 EntryPoint target 管理 main()；
4. 删除手写 /ENTRY 和旧 subsystem version；
5. Debug、Release 都使用 GUI subsystem。

若以后需要 Debug 控制台，应使用独立选项实现和验证。

### 3.3 Qt 组件与兼容性

主程序没有使用 Qt Test API。阶段 2 已从主程序组件和链接列表移除 Qt6::Test，仅在 ENABLE_TESTING 开启时查找该组件并供 src/tests 使用。

静态检查结论：

- QTextCodec 需要 Core5Compat，必须保留；
- QLibraryInfo::location() 在 Qt 6.11.1 仍可编译，但已弃用，可改为 path()；
- Q_WS_WIN 已失效，对应 plugin 路径分支不会执行；
- 采用 windeployqt 标准 plugin 布局后不依赖这个旧分支。

QScintilla、QCustomPlot、QHexEdit 继续保持内部静态构建：

~~~text
BUILD_SHARED_LIBS=OFF
FORCE_INTERNAL_QSCINTILLA=ON
FORCE_INTERNAL_QCUSTOMPLOT=ON
FORCE_INTERNAL_QHEXEDIT=ON
~~~

### 3.4 翻译

阶段 2 实施前，config/translations.cmake 把 .qm 写入 src/translations，translations.qrc 又从源码目录引用。

阶段 2 已采用 Qt6-only 方案：

- 使用 qt_add_translations()；
- .qm 输出到 binary tree；
- Qt CMake API 将资源附加到 sqlitebrowser；
- 移除主目标中的手写 translations.qrc；
- 保持 :/translations 资源前缀，不改应用加载逻辑。

## 4. Configure 门禁

配置阶段立即验证：

| 项目 | 要求 |
| --- | --- |
| Target | Windows x64 |
| Generator | Visual Studio 17 2022 |
| Toolset | v143 |
| Windows SDK | 10.0.26100.0 |
| CMake | 3.30.3 或兼容的更高版本 |
| Qt | 6.11.1 EXACT、MSVC2022 x64 |
| Qt tool | Qt6::windeployqt 存在 |

Qt 使用 Config mode：

~~~cmake
find_package(Qt6 6.11.1 EXACT CONFIG REQUIRED
    COMPONENTS Concurrent Core5Compat Gui LinguistTools
               Network PrintSupport Widgets Xml)
~~~

ENABLE_TESTING 开启时再单独查找 Qt6::Test。

错误信息应输出实际 generator、platform、toolset、SDK、Qt version 和 package path。

## 5. SQLCipher finder

阶段 1 实施前的 finder 允许默认搜索，只找到 header 和 sqlcipher.lib，并把 lib 写入 IMPORTED_LOCATION。阶段 1 已为 Windows 增加严格 stage 分支，同时保留非 Windows 的旧查找逻辑。

Windows 目标应为：

~~~text
SQLCipher::SQLCipher (SHARED IMPORTED)
|- IMPORTED_IMPLIB               <stage>/lib/sqlcipher.lib
|- IMPORTED_LOCATION             <stage>/bin/sqlcipher.dll
|- INTERFACE_INCLUDE_DIRECTORIES <stage>/include/sqlcipher
~~~

查找策略：

1. Windows 要求显式 SQLCIPHER_ROOT_DIR；
2. 使用规范绝对路径和 NO_DEFAULT_PATH；
3. 同时验证 header、LIB、DLL、build-manifest.txt；
4. Debug 只接受 Debug、x64、/MDd；
5. Release 只接受 Release、x64、/MD；
6. 校验 SQLCipher 4.18.0、OpenSSL 3.5.7；
7. 禁止 PATH 或系统 SQLCipher 回退。

src/sqlite.h 已定义 SQLITE_HAS_CODEC 和 SQLITE_TEMP_STORE=2，finder 不应向消费者传播 SQLCipher 本体的内部编译宏。

现有依赖 manifest 的 SDK 是 22621。当前 bring-up 阶段只警告，正式 Release 前改为不匹配即失败。

## 6. OpenSSL

项目 stage 的 OpenSSLConfig.cmake 已正确导出：

- OpenSSL::Crypto 的 DLL 和 import library；
- OpenSSL::SSL 及其 Crypto 依赖；
- OPENSSL_RUNTIME_DIR；
- libcrypto-3-x64.dll 和 libssl-3-x64.dll。

主工程现已强制：

~~~cmake
find_package(OpenSSL 3.5.7 EXACT CONFIG REQUIRED)
~~~

Preset 保留配置专用 OpenSSL_DIR、OPENSSL_ROOT_DIR，并增加：

~~~text
OPENSSL_USE_STATIC_LIBS=OFF
~~~

不使用 find_file、PATH 或系统 OpenSSL 回退。

OpenSSL 动态加载 Brotli，PE 导入表不一定列出 Brotli DLL，因此部署不能只依据 dumpbin。

## 7. 输出目录

应用 target 设置配置专用属性，避免 VS 自动追加 Debug/Release 子目录：

~~~text
RUNTIME_OUTPUT_DIRECTORY_<CONFIG> = <binaryDir>/bin
PDB_OUTPUT_DIRECTORY_<CONFIG>     = <binaryDir>/bin
~~~

预期：

~~~text
build/x64-shared-debug/bin/DB Browser for SQLCipher.exe
build/x64-shared-release/bin/DB Browser for SQLCipher.exe
~~~

内置静态库继续留在 build tree。

## 8. Build-time 部署

阶段 4 已通过 cmake/SQLiteBrowserWindowsRuntime.cmake 实现部署。为保证普通 cmake --build --preset 命令结束后即可运行，部署是 sqlitebrowser 的 POST_BUILD，而不是需要开发者额外执行的非 ALL target。SQLITEBROWSER_DEPLOY_RUNTIME 默认开启，Preset 模板也显式设置为 ON。

执行顺序：

1. 复制 $<TARGET_FILE:SQLCipher::SQLCipher>；
2. 复制 $<TARGET_FILE:OpenSSL::Crypto>；
3. 复制 $<TARGET_FILE:OpenSSL::SSL>；
4. 从 OPENSSL_RUNTIME_DIR 复制三个匹配配置的 Brotli DLL；
5. 调用 $<TARGET_FILE:Qt6::windeployqt>；
6. 校验必需文件；
7. 任一步失败都让 build 失败。

使用 cmake -E copy_if_different，避免 shell quoting 和无效重复复制。

windeployqt 参数：

| 配置 | 参数 |
| --- | --- |
| Debug | --debug --no-compiler-runtime --force-openssl |
| Release | --release --compiler-runtime --force-openssl |

--force-openssl 确保部署 OpenSSL TLS plugin，同时由项目显式控制 OpenSSL DLL 来源。

Qt 6.11.1 的 windeployqt 明确禁止同时使用 --force-openssl 和 --openssl-root。本项目只传 --force-openssl；OpenSSL 3.5.7 和 Brotli DLL 在调用 windeployqt 前从配置专用 stage 显式复制，因此不会让 Qt 工具从系统路径选择另一套 OpenSSL。

Release 调用时通过 CMAKE_GENERATOR_INSTANCE 派生默认 Visual Studio 的 VCINSTALLDIR。当前 Qt 6.11.1 的 --compiler-runtime 输出 vc_redist.x64.exe，而不是散装 MSVC runtime DLL；该文件已纳入 Release 构建期校验。如何在 ZIP 中做 app-local CRT，或由 NSIS 安装 redistributable，留到阶段 5 决定。

不要指定 --plugindir plugins。platform plugin 在 QApplication 创建时就必须可见，应保持标准布局：

~~~text
bin/platforms/qwindows[d].dll
bin/tls/qopensslbackend[d].dll
bin/tls/qschannelbackend[d].dll
bin/imageformats/...
bin/iconengines/...
bin/styles/...
~~~

第一阶段不要使用 --no-opengl-sw 或 --no-system-d3d-compiler 等裁剪参数。

非 Qt runtime 必须包含：

~~~text
sqlcipher.dll
libcrypto-3-x64.dll
libssl-3-x64.dll
brotlicommon.dll
brotlidec.dll
brotlienc.dll
~~~

当前不复制 zlib1.dll、libzstd.dll、openssl.exe、sqlcipher.exe、依赖库 PDB 和 OpenSSL modules。

POST_BUILD 最后再次以 cmake -P 执行同一个 helper 的校验入口。校验范围包括：

- 六个固定非 Qt DLL；
- 配置匹配的 Qt Core/GUI/Network/Widgets 等 DLL；
- qwindows、qopensslbackend、qschannelbackend 和主要 image/icon/style plugin；
- D3Dcompiler_47.dll、opengl32sw.dll；
- Release 的 vc_redist.x64.exe；
- 禁止混入另一配置的 Qt DLL、工具 EXE、依赖 PDB、zlib 和 zstd。

任一必需文件缺失、为空或配置混用都会直接让 build 失败。

## 9. Install-time 部署

config/install.cmake 的 find_file 可能从 PATH 复制错误 DLL，而且 install 与 build 使用两套来源。

后续应：

- build/install 共用已验证的 runtime 清单；
- 用 install(IMPORTED_RUNTIME_ARTIFACTS ...) 安装 SQLCipher/OpenSSL；
- Brotli 从 OPENSSL_RUNTIME_DIR 安装；
- Qt install 使用 qt_generate_deploy_app_script()；
- 删除 DLL 名称猜测和全局 find_file。

安装器改造应放在普通 build 可运行之后。

## 10. 测试

### 10.1 单元测试

四个现有测试不依赖 SQLCipher，主要依赖 Qt Test/Core；test-regex 还依赖 Widgets/Core5Compat。

阶段 3 已完成：

- 测试输出到 binaryDir/tests；
- include/link 改为 target-based；
- 使用 ENVIRONMENT_MODIFICATION 把 $<TARGET_FILE_DIR:Qt6::Core> 前置到 PATH；
- 每项测试 timeout 设置为 60 秒；
- Preset 保持 outputOnFailure=true；
- 四个测试入口均为 QCoreApplication 或 app-less，不需要 Qt platform plugin。

### 10.2 应用启动 smoke

阶段 4 通过 sqlitebrowser_runtime_smoke 显式 target 执行：

~~~text
cmake --build --preset debug --target sqlitebrowser_runtime_smoke
cmake --build --preset release --target sqlitebrowser_runtime_smoke
~~~

target 先以 --quit --settings <临时文件> 启动主程序。该路径创建 QApplication 但不显示主窗口，可验证 EXE、Qt GUI 和 qwindows plugin 的基本运行时闭包。

测试把 PATH 限制为应用 bin，并使用临时 settings 文件，防止从开发机 Qt/OpenSSL 目录补齐缺失 DLL。现有 Settings 有效性检查要求 INI 第一行为 [%General]；若直接以 [checkversion] 开头，Windows message handler 会把警告转换为模态框，使 --quit 无人值守测试超时。runner 已按项目规则生成有效文件。

--version 和 --help 当前可能经 Windows message handler 弹框，不适合无人值守 smoke。

### 10.3 功能 smoke

新增 src/tests/runtime_smoke.cpp，生成不进入默认 ALL/CTest 的 sqlitebrowser-runtime-smoke-tool。显式 runtime target 依次执行：

1. 创建普通 SQLite 数据库并完成写入、读取；
2. 创建 SQLCipher 数据库，确认文件头不是明文 SQLite；
3. 确认无 key 不可读取、正确 key 可重开，并执行基本读写和 integrity_check；
4. 查询并要求 PRAGMA cipher_version 为 4.18.x；
5. 通过 OpenSSL COMP_brotli_oneshot() 做压缩/解压，实际触发动态 Brotli；
6. 强制 Qt 使用 openssl backend，要求运行时为 OpenSSL 3.5.7，并完成真实 HTTPS 请求；
7. 在进程内检查 SQLCipher、OpenSSL、三个 Brotli、Qt Core/Network 和 qopensslbackend 的已加载模块路径都来自应用 bin。

调度逻辑位于 cmake/RunSQLiteBrowserWindowsSmoke.cmake。网络 smoke 与普通四项单元测试分离，避免 ctest --preset 在离线环境下变成网络相关测试。

## 11. 建议修改文件

| 文件 | 主要职责 |
| --- | --- |
| CMakePresets.template.json | 部署开关、SDK policy、OPENSSL_USE_STATIC_LIBS |
| 本地 CMakePresets.json | 只填写 Qt 路径，不提交 |
| CMakeLists.txt | Qt/target 顺序、Qt6 exact、输出目录、target-based 配置 |
| config/options.cmake | runtime deploy 和 manifest policy |
| config/platform_win.cmake | 工具链/OpenSSL、删除旧 entry/subsystem |
| cmake/FindSQLCipher.cmake | SHARED imported target 和 stage 校验 |
| config/translations.cmake | build-tree translations |
| cmake/SQLiteBrowserWindowsRuntime.cmake | POST_BUILD、windeployqt、文件校验、runtime smoke target |
| cmake/RunSQLiteBrowserWindowsSmoke.cmake | 受限 PATH 的 smoke 调度、临时 settings |
| src/tests/runtime_smoke.cpp | SQLCipher、OpenSSL Brotli、Qt OpenSSL TLS 与模块来源检查 |
| config/install.cmake | 共用明确 runtime 来源 |
| src/tests/CMakeLists.txt | 测试输出、Qt PATH、timeout |
| .gitignore | 新 .cmake helper 的精确 whitelist |

建议 helper 名称：

~~~text
cmake/SQLiteBrowserWindowsRuntime.cmake
~~~

根 .gitignore 忽略全部 .cmake，新增 helper 时必须添加精确例外。

## 12. 推荐实施顺序

### 阶段 0：本地入口（已完成）

已复制模板、填写 Qt，并确认两个 preset 可见；本地文件保持 ignored。

### 阶段 1：Configure（已完成）

1. 调整 Qt 查找和 qt_add_executable 顺序；
2. 修复多配置 CMAKE_BUILD_TYPE；
3. 验证 VS2022/x64/v143/SDK/Qt；
4. 强制 OpenSSL Config；
5. 重写 SQLCipher target；
6. 对依赖 SDK 22621 发 warning。

只执行：

~~~cmd
cmake --preset debug
cmake --preset release
~~~

执行结果：

- cmake --preset debug：configure/generate 成功；
- cmake --preset release：configure/generate 成功；
- Debug cache 只引用 OpenSSL、SQLCipher 的 Debug stage；
- Release cache 只引用 OpenSSL、SQLCipher 的 Release stage；
- VS2022、x64、v143、Windows SDK 10.0.26100.0 与 Qt 6.11.1 门禁通过；
- OpenSSL 3.5.7、SQLCipher 4.18.0 的版本、配置、架构、CRT 和 manifest 关联校验通过；
- 依赖库由 SDK 10.0.22621.0 构建，与主程序 SDK 10.0.26100.0 不同，按当前 WARN policy 输出预期警告；
- Qt 输出的 WrapVulkanHeaders 缺失信息不影响 configure/generate。

完成条件“两个 cache 只引用各自 stage”已经满足。本阶段未执行 build、CTest、部署或程序启动。

### 阶段 2：Build（已完成）

已完成：

1. 删除 /ENTRY、旧 subsystem version、Debug/RelWithDebInfo 的手写 console flags 和 _CONSOLE；
2. 由 qt_add_executable(WIN32) 和 Qt6 EntryPoint 管理 Windows GUI 入口；
3. 从主程序移除 Qt6::Test，ENABLE_TESTING 开启时仍为测试目标查找 Qt Test；
4. 使用 qt_add_translations() 在各自 binary tree 生成 20 个 .qm，并以 /translations 资源前缀附加到主程序；
5. 移除主目标对源码目录 translations.qrc 的引用；
6. 设置 Debug、Release 的 EXE 与链接 PDB 输出到各自 bin；
7. Release 保持优化构建，同时使用 ProgramDatabase 编译信息和链接 /DEBUG 生成可用 PDB。

首次 Debug 构建发现 SQLCipher::SQLCipher 传播的是 stage/include，而主程序直接包含 sqlite3.h；实际头文件位于 stage/include/sqlcipher。finder 已改为验证并传播真实目录，刷新既有 cache 后 Debug、Release 均构建成功。

执行结果：

- cmake --build --preset debug：成功；
- cmake --build --preset release：成功；
- Debug 生成 build/x64-shared-debug/bin/DB Browser for SQLCipher.exe 和同名 PDB；
- Release 生成 build/x64-shared-release/bin/DB Browser for SQLCipher.exe 和同名 PDB；
- 两套生成工程均为 Windows subsystem，没有自定义 EntryPointSymbol；
- 主程序链接项不包含 Qt6Test；
- 翻译资源路径为 :/translations/sqlb_*.qm，来源均位于对应 binary tree；
- 首次全量构建可能因 Visual Studio ALL_BUILD 与资源依赖各显示一次 lrelease 日志，生成文件一致；后续增量构建不会重复生成；
- 构建保留若干既有源码警告，不影响本阶段完成条件。

本阶段未执行 CTest、运行时 DLL 部署或程序启动。

### 阶段 3：CTest（已完成）

已完成：

1. 移除 src/tests 的目录级 include_directories() 和重复 find_package()；
2. 四个测试改用显式 Qt6 imported targets 与 PRIVATE include/link；
3. Debug、Release 测试可执行文件统一输出到各自 binaryDir/tests；
4. 每个测试通过 ENVIRONMENT_MODIFICATION 将 Qt6::Core 所在目录前置到 PATH；
5. 每项测试设置 60 秒超时，测试 Preset 继续启用 outputOnFailure。

首次执行时，Release 四项通过，但 Debug test-import 在 utf8chars 和 utf16chars 数据行等待 MSVC Debug CRT 断言并超时。根因是 csvparser.cpp 将可能为负值的 char 直接传给 isspace()，违反字符分类函数的参数约束。两处调用已改为先转换为 unsigned char，并显式使用 std::isspace()。

最终结果：

- ctest --preset debug：4/4 通过，总耗时约 0.26 秒；
- ctest --preset release：4/4 通过，总耗时约 0.20 秒；
- 两套 CTest 定义均指向各自 binaryDir/tests；
- Qt PATH 在每个测试进程内修改，不影响其他测试或调用者环境；
- tests 目录不需要复制 Qt、OpenSSL、SQLCipher 或 platform plugin DLL。

本阶段未执行主程序运行时部署、程序启动、数据库 smoke 或 TLS smoke。

### 阶段 4：Deploy and run（已完成）

已完成：

1. 新增 SQLITEBROWSER_DEPLOY_RUNTIME，并在 Preset 模板显式开启；
2. 主程序 POST_BUILD 依次复制 SQLCipher、OpenSSL 和三个 Brotli DLL；
3. Debug 使用 --debug --no-compiler-runtime --force-openssl，Release 使用 --release --compiler-runtime --force-openssl；
4. 使用标准 Qt plugin 布局，并在 build 末尾校验文件、配置和禁止项；
5. 新增显式 sqlitebrowser_runtime_smoke target 和专用 smoke 工具；
6. 使用有效临时 settings 和只含应用 bin 的 PATH；
7. 验证普通 SQLite、SQLCipher、OpenSSL 动态 Brotli、Qt OpenSSL HTTPS 和实际模块来源。

执行结果：

- cmake --build --preset debug：成功，Debug runtime 构建期校验通过；
- cmake --build --preset release：成功，Release runtime 构建期校验通过；
- Debug sqlitebrowser_runtime_smoke：全部通过；
- Release sqlitebrowser_runtime_smoke：全部通过；
- 两套配置的应用 --quit 启动均通过；
- 两套配置均报告 SQLCipher database、OpenSSL Brotli、Qt OpenSSL HTTPS smoke 通过；
- 两套 bin 的六个固定非 Qt DLL 与对应 stage 的 SHA-256 全部一致，禁止文件数量均为 0；
- ctest --preset debug：4/4 通过，总耗时约 0.24 秒；
- ctest --preset release：4/4 通过，总耗时约 0.18 秒。

本阶段没有修改 install/NSIS，没有在干净 Windows 验证 Release，也没有重建 SDK 26100 依赖或调整版本号。

### 阶段 5：Release gate

重构 install，用 SDK 26100 重建依赖，把 manifest policy 改为 fatal，在干净 Windows 验证 Release，再进入 ZIP、NSIS、签名和版本号。

## 13. 常见故障定位

| 阶段 | 错误 | 检查 |
| --- | --- | --- |
| Configure | 找不到 Qt | 本地 CMAKE_PREFIX_PATH 和占位符 |
| Configure | 错误 Qt | Qt6_DIR、版本、架构、cache |
| Configure | OpenSSL target 混合 | 第一次查找必须是 3.5.7 Config |
| Configure | SQLCipher DLL 缺失 | finder 同时要求 LIB/DLL/manifest |
| Link | WinMain/main 错误 | qt_add_executable(WIN32) 与旧 /ENTRY |
| Link | 配置冲突 | binary tree 和 stage manifest |
| Build | rcc 找不到 qm | binary-tree 翻译依赖 |
| CTest | Qt DLL 找不到 | ENVIRONMENT_MODIFICATION |
| Startup | qwindows 错误 | bin/platforms 和 debug 后缀 |
| Startup | libcrypto 缺失 | 依赖配置和复制顺序 |
| TLS | OpenSSL backend 不可用 | tls plugin 和 OpenSSL DLL 来源 |
| Brotli | 动态加载失败 | 三个 Brotli DLL 的配置一致性 |

## 14. 最终验收

Debug：

- configure/build/ctest 全部成功；
- EXE、PDB 和 Debug runtime 位于同一 bin；
- 安装 VS2022 的开发机不设置 Qt/OpenSSL PATH 即可启动。

Release：

- configure/build/ctest 全部成功；
- bin 不包含 Debug CRT 或 Debug Qt；
- SQLCipher、TLS、Brotli smoke 通过；
- 整个 bin 复制到没有 Qt/OpenSSL/SQLCipher 的干净机器后可启动。

## 15. 本轮边界

本轮新增实施范围为阶段 4：

- 主程序 POST_BUILD 运行时部署；
- 配置专用 Qt/SQLCipher/OpenSSL/Brotli 闭包；
- 构建期 runtime 校验；
- 显式受限 PATH startup、database、Brotli 和 TLS smoke；
- Debug、Release 的完整构建与验证；
- 复跑两套配置的阶段 3 CTest。

本轮没有修改 install/NSIS、ZIP、签名或版本号，没有把依赖 SDK policy 改为 STRICT，也没有宣称完成干净 Windows 发布验证。这些工作留到阶段 5。
