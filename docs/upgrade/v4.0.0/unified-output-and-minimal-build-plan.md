# Windows 统一输出目录与最小构建方案

> 文档性质：目录重构与构建命令设计
>
> 最后更新：2026-08-30
>
> 当前分支：`upgrade/v4.0.0`
>
> 目标平台：Windows x64
>
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
>
> 状态：阶段 7 已完成；产品构建和单元测试 workflow 已分离，development/package runtime 区分仍待阶段 8 完成

阶段 5 的正式命令、目录 allowlist、验证与清理规则见 [dependency-public-aggregation-guide.md](dependency-public-aggregation-guide.md)。

## 1. 文档目的

本文定义下一阶段的统一输出目录、最小产品构建、独立测试命令和产物边界。目标是让 Debug、Release 各自形成一个可识别、可清理、可归档的配置目录，同时避免普通编译命令构建单元测试、smoke test、示例程序和非必要工具。

当前主程序使用以下路径：

```text
output/x64-shared-<config>/build/sqlitebrowser
output/x64-shared-<config>/bin
```

`output/` 当前已经用于 Brotli、zlib、zstd、OpenSSL、SQLCipher、配置级公共汇总和主程序。主程序 CMake/OBJ 留在 `build/sqlitebrowser`，EXE、应用 linker PDB 和部署后的 Qt/SQLCipher/OpenSSL/Brotli 运行时进入同配置公共 `bin`。

### 1.1 2026-08-30 实施检查点

已完成并从空目录验证：

- `.gitignore` 忽略 `/output/`；
- Brotli、zlib、zstd 使用 `output/x64-shared-<config>/build/<dependency>/{work,stage}`；
- 三个脚本支持 `check`、`build`、`test`、`clean`，并保留省略 `build` 的兼容写法；
- 普通 `build` 使用显式产品 target，不编译 smoke/example；
- `test` 单独构建测试 target，不重新安装产品 stage；
- `build-manifest.txt` 固定记录 `not run`，`test-manifest.txt` 通过 SHA-256 绑定对应 build manifest；
- zlib 和 zstd 的 Debug、Release 均部署 linker PDB，且不部署 `vc143.pdb`；
- 三项依赖均切换到 Windows SDK `10.0.26100.0`；
- Brotli Debug/Release smoke、zstd Debug/Release smoke，以及 zlib Debug/Release 各 13 项 CTest 全部通过。
- OpenSSL 使用 `nmake build_libs` 和 `nmake install_dev`，普通 build 不构建或部署 CLI、provider、engine、test、fuzz；
- OpenSSL Debug/Release 私有 stage 已迁移到 `output/x64-shared-<config>/build/openssl/stage`，并只包含 Crypto/SSL、Brotli 运行 DLL、linker PDB、头文件、import LIB 和 CMake package；
- OpenSSL build 与 test 已拆分，build manifest 固定记录 `Tests: not run`，test manifest 通过 SHA-256 绑定对应 build manifest；
- OpenSSL Debug/Release safe 通用套件各 `343 files / 4279 tests` 通过，Brotli 聚焦测试各 `3 files / 11 tests` 通过；safe 模式明确排除 `test_bio_dgram`；
- OpenSSL Debug/Release stage 均没有 EXE、`legacy.dll`、engine DLL 或 `vc143.pdb`，并使用 Windows SDK `10.0.26100.0`。
- SQLCipher Debug/Release 私有 stage 已迁移到 `output/x64-shared-<config>/build/sqlcipher/stage`，并消费同配置的新 OpenSSL 最小 stage；
- SQLCipher 普通 build 只构建 `sqlcipher` 产品 target，CLI 使用 `EXCLUDE_FROM_ALL`，不会进入产品 stage；
- SQLCipher provider smoke、CTest 和 staged-product 探针已移到独立 test 动作；build manifest 固定记录测试未运行，test manifest 通过 SHA-256 绑定当前 build manifest；
- SQLCipher Debug/Release 均使用 Windows SDK `10.0.26100.0`，最小 stage 只包含 DLL、import LIB、linker PDB、公开头文件、许可证与 manifest。
- SQLCipher Debug/Release 的 CTest provider smoke 各 `1/1` 通过，staged-product provider/compile-options 探针通过；两个 test manifest 均已核对为绑定当前 build manifest。
- 新增 `third_party/aggregate.cmd`，按 allowlist 将五个经过验证的私有 stage 汇总到对应配置的公共 `include/bin/metadata`；
- Debug 和 Release 公共输出各有 196 个 ownership 条目，其中 155 个头文件、24 个二进制/链接产物和 17 个 metadata 文件；
- 公共 `bin` 仅包含 DLL、import LIB 和 linker PDB，不包含 EXE、测试程序、可选 CLI 或 `vc143.pdb`；
- ownership manifest 为每个受管文件记录 SHA-256；重复汇总、只读检查以及 `clean debug` 后保持 Release 和 Debug 私有 stage 不变的隔离测试均已通过。
- Debug/Release Preset binary directory 已迁移到 `output/x64-shared-<config>/build/sqlitebrowser`，并只允许对应配置根和私有 OpenSSL/SQLCipher stage；
- build preset 显式设置 `targets: ["sqlitebrowser"]`，普通主程序构建不会编译四个单元测试或 runtime smoke tool；
- 依赖 SDK policy 已由 `WARN` 改为 `STRICT`，主程序和五个依赖统一要求 Windows SDK `10.0.26100.0`；
- 主程序 EXE/PDB 与 Qt runtime 已部署到公共 `bin`；开发输出校验允许阶段 5 的 zlib、zstd、import LIB 和 linker PDB，但仍禁止依赖 CLI 与 compiler PDB；
- Debug/Release configure、产品 build、POST_BUILD 运行时校验和受限 `PATH` 启动均通过；重新执行依赖聚合后应用与 Qt 文件保持不变。
- 四个单元测试均已设置 `EXCLUDE_FROM_ALL`，并由非默认 `sqlitebrowser_unit_tests` target 聚合；
- 新增 `unit-tests-debug`、`unit-tests-release` build preset 和 `test-debug`、`test-release` workflow preset；
- workflow 按“configure → build unit tests → CTest”执行，测试 EXE/PDB 留在 `output/x64-shared-<config>/build/tests/unit`；
- Debug、Release workflow 均为 4/4 通过；随后执行普通产品 build 未重建测试程序，公共 `bin` 未出现测试 EXE。

## 2. 最终决策

采用“配置优先”的目录结构：

```text
output/x64-shared-debug/{build,include,bin,metadata}
output/x64-shared-release/{build,include,bin,metadata}
```

不采用 Debug、Release 共享顶层 `build/` 和 `include/` 的方案。即使当前部分头文件内容相同，OpenSSL 配置头、zlib `zconf.h`、SQLCipher 生成头和 CMake package 都属于具体构建产生的接口，未来改变编译选项或升级版本时不应假设它们继续相同。

配置优先结构还可以保证：

- Debug `/MDd` 与 Release `/MD` 完全隔离；
- 同名 DLL、LIB 和 PDB 不会互相覆盖；
- OpenSSL NMake work 和 SQLCipher 生成源码不会跨配置复用；
- 可以安全清理或归档一个完整配置；
- manifest、测试结果和最终产物可以一一对应。

## 3. 推荐目录结构

```text
output/
|- x64-shared-debug/
|  |- build/
|  |  |- brotli/
|  |  |  |- work/
|  |  |  `- stage/
|  |  |- zlib/
|  |  |  |- work/
|  |  |  `- stage/
|  |  |- zstd/
|  |  |  |- work/
|  |  |  `- stage/
|  |  |- openssl/
|  |  |  |- work/
|  |  |  `- stage/
|  |  |- sqlcipher/
|  |  |  |- work/
|  |  |  `- stage/
|  |  |- sqlitebrowser/
|  |  `- tests/                    # 仅执行测试命令后产生
|  |- include/
|  |  |- brotli/
|  |  |- openssl/
|  |  |- sqlcipher/
|  |  |- zconf.h
|  |  |- zlib.h
|  |  |- zdict.h
|  |  |- zstd.h
|  |  `- zstd_errors.h
|  |- bin/
|  |  |- DB Browser for SQLCipher.exe
|  |  |- DB Browser for SQLCipher.pdb
|  |  |- *.dll
|  |  |- *.lib
|  |  |- 项目生成的链接器 *.pdb
|  |  `- Qt runtime 和插件目录
|  `- metadata/
|     |- manifests/
|     `- licenses/
`- x64-shared-release/
   `- 与 Debug 相同的目录契约
```

如果最终决定只保留 `build/include/bin` 三个一级目录，`metadata` 应移动到：

```text
build/manifests/
build/licenses/
```

manifest 和许可证不应放入 `bin`。

### 3.1 build

`build` 保存不可发布的构建过程文件：

- CMake cache、Visual Studio solution 和 vcxproj；
- `.obj`、生成源码、自动生成 Qt 文件和翻译中间文件；
- OpenSSL Configure/NMake work；
- SQLCipher amalgamation 和生成工具；
- 私有 dependency stage；
- 测试可执行文件及测试临时数据库；
- compiler PDB，例如 `vc143.pdb`。

每个依赖继续保留私有 `work/stage`。不能让所有依赖直接安装到同一个公共 prefix，原因是：

- 各依赖都有同名 `build-manifest.txt`；
- 单独执行 `clean` 时无法安全判断哪些公共文件属于当前依赖；
- OpenSSL、zlib、zstd 的上游 CMake package 仍假设标准 `bin/lib/include` 布局；
- 安装失败可能留下半更新的公共目录。

公共 `include/bin` 应由配置级汇总步骤从已验证的私有 stage 按 allowlist 生成。

### 3.2 include

公共头文件保留上游兼容布局：

| 依赖 | 公共路径 |
| --- | --- |
| Brotli | `include/brotli/*.h` |
| OpenSSL | `include/openssl/*.h` |
| SQLCipher | `include/sqlcipher/sqlite3*.h` |
| zlib | `include/zlib.h`、`include/zconf.h` |
| zstd | `include/zstd.h`、`include/zdict.h`、`include/zstd_errors.h` |

Qt 头文件不复制到 `output`。Qt 仍由开发者在本地 `CMakePresets.json` 中指定。

SQLCipher 头文件必须包含在统一输出中。否则主程序无法只依赖当前配置的统一输出完成编译。

### 3.3 bin

按照当前目标，公共 `bin` 可以集中放置项目产生的 EXE、DLL、import LIB 和 linker PDB。该布局属于项目开发输出，不是标准 CMake SDK，也不能直接等同于最终安装包。

默认产品构建预期包含：

| 项目 | 默认公共产物 |
| --- | --- |
| Brotli | 三个 DLL、三个 import LIB、三个 linker PDB |
| zlib | `zlib1.dll`、`zlib1.lib`、对应 linker PDB |
| zstd | `libzstd.dll`、`libzstd.lib`、对应 linker PDB |
| OpenSSL | Crypto/SSL DLL、import LIB、linker PDB |
| SQLCipher | `sqlcipher.dll`、`sqlcipher.lib`、`sqlcipher.pdb` |
| SQLiteBrowser | 应用 EXE、应用 PDB、Qt/SQLCipher/OpenSSL/Brotli 运行时和 Qt plugins |

以下文件默认不进入公共 `bin`：

- 单元测试和 smoke test 可执行文件；
- `zlib_example`、`minigzip` 等示例程序；
- `openssl.exe`、`sqlcipher.exe` 等可选诊断工具；
- OpenSSL engines、legacy provider 和非运行必需脚本；
- compiler PDB，例如 `vc143.pdb`；
- man page、pkg-config 文件和中间生成工具。

如果以后需要 CLI 工具，应增加显式 `tools` 构建命令，不能让它们重新进入默认产品构建。

### 3.4 `.lib` 放入 bin 的约束

Windows import library 放入 `bin` 技术上可行，但上游安装的 CMake package 通常假设 `.lib` 位于 `lib`：

```text
OpenSSLConfig.cmake  -> <prefix>/lib/libcrypto.lib
ZLIBConfig.cmake     -> <prefix>/lib/zlib1.lib
zstdTargets.cmake    -> <prefix>/lib/libzstd.lib
```

因此第一阶段建议：

1. 主程序继续消费 `build/<dependency>/stage` 中的标准 package；
2. 公共 `bin` 作为面向开发者和归档的汇总产物；
3. 不把上游 CMake package 原样复制到公共输出；
4. 如果以后要让公共输出成为可被 `find_package()` 消费的 SDK，再生成项目维护的、知道 `.lib` 位于 `bin` 的 Config package。

## 4. 最小构建边界

普通构建必须使用明确产品 target，不再构建 `ALL_BUILD`。

| 项目 | 普通构建 target | 从默认构建排除 |
| --- | --- | --- |
| Brotli | `brotlicommon`、`brotlidec`、`brotlienc` | `brotli_shared_smoke` |
| zlib | `zlib` | `zlib_example`、`test_example`、`minigzip` |
| zstd | `libzstd_shared` | `zstd_shared_smoke` |
| OpenSSL | `nmake build_libs` | tests、CLI、engines、非必需 modules |
| SQLCipher | `sqlcipher` | `sqlcipher_cli` 和 provider smoke |
| SQLiteBrowser | `sqlitebrowser` 及其内部静态库 | 四个单元测试、runtime smoke tool |

“最小构建”只限制编译 target 和公共输出，不表示跳过必要的生成步骤。例如：

- SQLCipher 仍需生成 `sqlite3.c` 和公开头文件；
- Qt 仍需运行 moc、uic、rcc 和 lrelease；
- SQLiteBrowser 仍需构建 QScintilla、QCustomPlot、QHexEdit 等实际链接依赖；
- 主程序构建后仍需部署并验证运行所需 DLL。

## 5. PDB 策略

统一输出只部署与最终 EXE/DLL 对应的 linker PDB：

- Debug：保留 linker PDB；
- Release：保留优化，同时使用 `/Zi` 和 `/DEBUG:FULL` 生成 linker PDB；
- Release 继续使用 `/OPT:REF` 和 `/OPT:ICF`；
- compiler PDB 只留在 `build`；
- 不生成不存在的第三方预编译 Qt PDB。

当前实现中，Brotli、zlib、zstd、OpenSSL、SQLCipher 和主程序均为 Debug/Release 部署对应 linker PDB；`vc143.pdb` 等 compiler PDB 只保留在私有 build tree。

## 6. 构建与测试命令设计

### 6.1 当前可使用的命令

五项依赖及配置级汇总使用以下接口：

```cmd
third_party\brotli\build.cmd build all
third_party\zlib\build.cmd build all
third_party\zstd\build.cmd build all
third_party\openssl\build.cmd build all
third_party\sqlcipher\build.cmd build all

third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release safe
third_party\sqlcipher\build.cmd test all

third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
```

主程序使用同一 Preset 接口，并输出到对应配置的 `output/` 根：

```cmd

cmake --preset debug
cmake --build --preset debug

cmake --preset release
cmake --build --preset release
```

Brotli、zlib、zstd、OpenSSL、SQLCipher、依赖公共汇总和主程序均输出到 `output/`。普通构建不运行测试；主程序构建完成后，公共 `bin` 是可直接运行的 development output，但仍不能直接视为 ZIP/NSIS package runtime。

### 6.2 重构后的依赖脚本契约

建议所有依赖脚本统一为以下命令模型：

```cmd
third_party\<dependency>\build.cmd check
third_party\<dependency>\build.cmd build <debug|release|all>
third_party\<dependency>\build.cmd test <debug|release|all>
third_party\<dependency>\build.cmd clean <debug|release|all>
```

OpenSSL 测试继续保留安全和完整模式：

```cmd
third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release full
```

命令语义：

| 命令 | 行为 |
| --- | --- |
| `check` | 只检查源码、工具链和已有依赖，不生成文件 |
| `build` | 只构建产品 target、安装并验证该依赖的私有 stage |
| `test` | 构建测试专用 target、运行测试并写测试报告，不改变产品文件 |
| `clean` | 只清理所选配置中该依赖拥有的私有 build 目录 |

公共文件由单独的配置级命令管理：

```cmd
third_party\aggregate.cmd build <debug|release|all>
third_party\aggregate.cmd check <debug|release|all>
third_party\aggregate.cmd clean <debug|release|all>
```

依赖脚本不直接写公共目录，避免多个组件各自删除或覆盖同名文件。汇总器会验证版本、配置、SDK、CRT、stage 产品、manifest 绑定和跨依赖关系，再发布公共文件。

### 6.3 主程序产品构建

主程序仍使用现有命令：

```cmd
cmake --preset debug
cmake --build --preset debug

cmake --preset release
cmake --build --preset release
```

阶段 6 的 build preset 已设置明确 target：

```json
"targets": ["sqlitebrowser"]
```

Preset 的目标 binary directory：

```text
debug   -> output/x64-shared-debug/build/sqlitebrowser
release -> output/x64-shared-release/build/sqlitebrowser
```

应用和部署后的运行时统一输出到对应配置的公共 `bin`。Preset 同时提供并校验 `SQLITEBROWSER_CONFIGURATION_ROOT`，要求阶段 5 的 aggregate/ownership manifest 存在，并将 OpenSSL、SQLCipher 分别绑定同配置私有 stage。

### 6.4 单元测试

CMake 没有 `cmake test` 子命令。标准测试程序是 `ctest`，但测试 target 被排除出默认构建后，仅运行 `ctest` 不会自动编译测试程序。

阶段 7 已增加 workflow preset，把“构建测试 target”和“运行 CTest”组成一条独立命令：

```cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
```

workflow 的实际逻辑为：

```text
configure
  -> build sqlitebrowser_unit_tests aggregate target
  -> ctest --preset <config>
```

四个单元测试使用 `EXCLUDE_FROM_ALL`，生成到：

```text
output/x64-shared-<config>/build/tests/unit
```

测试程序不得复制到公共 `bin`。

### 6.5 运行时 smoke test

应用启动、SQLCipher、Brotli 和 TLS smoke 继续与确定性单元测试分离：

```cmd
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
```

也可以保留显式 target 入口：

```cmd
cmake --build --preset debug --target sqlitebrowser_runtime_smoke
cmake --build --preset release --target sqlitebrowser_runtime_smoke
```

smoke tool 和临时数据库输出到：

```text
output/x64-shared-<config>/build/tests/runtime-smoke
```

网络 smoke 仍需单独报告，不能因为离线环境失败而把普通产品编译描述为失败。

## 7. 建议的完整开发流程

以下依赖构建、汇总、主程序和单元测试 workflow 均已可以执行。阶段 8 将继续区分 development output 和 package runtime。

### 7.1 初始化

```cmd
git clone --branch upgrade/v4.0.0 --recurse-submodules https://github.com/wpp2014/SQLiteBrowser.git
cd SQLiteBrowser
git submodule update --init --recursive
copy /Y CMakePresets.template.json CMakePresets.json
```

然后只在本地 `CMakePresets.json` 中填写 Qt 6.11.1 MSVC2022 x64 路径。

### 7.2 最小 Debug 产品构建

```cmd
third_party\brotli\build.cmd build debug
third_party\zlib\build.cmd build debug
third_party\zstd\build.cmd build debug
third_party\openssl\build.cmd build debug
third_party\sqlcipher\build.cmd build debug
third_party\aggregate.cmd build debug

cmake --preset debug
cmake --build --preset debug
```

### 7.3 最小 Release 产品构建

```cmd
third_party\brotli\build.cmd build release
third_party\zlib\build.cmd build release
third_party\zstd\build.cmd build release
third_party\openssl\build.cmd build release
third_party\sqlcipher\build.cmd build release
third_party\aggregate.cmd build release

cmake --preset release
cmake --build --preset release
```

虽然 zlib、zstd 当前不属于 SQLiteBrowser 的实际运行时闭包，但统一依赖产物构建可以显式生成它们。以后可增加 `required` 与 `all-dependencies` 两种顶层 profile：

- `required`：只构建 Brotli、OpenSSL、SQLCipher 和主程序；
- `all-dependencies`：额外构建 zlib、zstd。

### 7.4 测试

依赖测试：

```cmd
third_party\brotli\build.cmd test debug
third_party\zlib\build.cmd test debug
third_party\zstd\build.cmd test debug
third_party\openssl\build.cmd test debug safe
third_party\sqlcipher\build.cmd test debug
```

主程序测试：

```cmd
cmake --workflow --preset test-debug
cmake --workflow --preset smoke-debug
```

Release 使用同样命令并将 `debug` 替换为 `release`。

## 8. Manifest 和测试记录

构建与测试分离后，不应继续把“测试通过”作为生成 build manifest 的前提。

推荐拆分：

```text
metadata/manifests/<dependency>/build-manifest.txt
metadata/manifests/<dependency>/test-manifest.txt
```

`build-manifest.txt` 记录：

- tag、commit、子模块状态；
- VS、MSVC、SDK、CMake、配置和 CRT；
- 构建选项；
- 公共产物及 SHA-256；
- 当前测试状态为 `not run` 或对应 test manifest 的哈希。

`test-manifest.txt` 记录：

- 被测试 build manifest 的 SHA-256；
- 测试模式和过滤条件；
- 开始/结束时间和结果；
- smoke 使用的 DLL 来源；
- 未运行项目及原因。

开发构建可以消费已验证但尚未测试的依赖。CI、Release candidate 和正式发布必须要求匹配的 test manifest。

## 9. 开发输出与发布输出必须区分

统一公共 `bin` 会包含 zlib、zstd、import LIB 和 PDB，而当前应用运行时校验故意禁止这些文件。目录重构后需要两种校验策略：

### Development output

- 允许项目所有 DLL、LIB 和 linker PDB；
- 应用可以从该目录直接运行；
- 验证实际加载的 SQLCipher、OpenSSL、Brotli 和 Qt DLL 来自当前配置；
- 不得包含另一配置的 DLL 或 compiler PDB。

### Package runtime

- 只包含应用实际运行时闭包；
- 不包含 `.lib`、PDB、zlib、zstd、测试工具或诊断 CLI；
- 继续执行当前严格 allowlist 和受限 `PATH` smoke；
- NSIS、ZIP 不能直接复制整个开发 `bin`。

## 10. 清理策略

安全清理必须以配置和组件为边界。单个依赖脚本只删除自己的私有构建目录：

```text
third_party\brotli\build.cmd clean debug
  -> output/x64-shared-debug/build/brotli
```

公共依赖文件只能通过 ownership manifest 清理：

```cmd
third_party\aggregate.cmd clean debug
```

该命令先验证 ownership manifest 和所有已发布文件的 SHA-256，再只删除 manifest 中逐项声明的文件。它不会删除 `output/x64-shared-debug/build/<dependency>`、Release 公共文件或未被汇总器拥有的文件。若受管文件被外部修改，命令会拒绝清理，避免误删。

禁止让单个依赖脚本递归删除整个 `output/`、另一个配置或共享父目录。公共文件删除必须依赖上一次成功生成的 ownership manifest，不能用宽泛通配符猜测。

## 11. 实施影响范围

后续实现预计涉及：

- `CMakePresets.template.json`；
- 根 `CMakeLists.txt`；
- `src/tests/CMakeLists.txt`；
- `cmake/SQLiteBrowserWindowsRuntime.cmake`；
- 五个依赖的 `build.cmd`；
- Brotli、zlib、zstd、SQLCipher 包装层 CMakeLists；
- OpenSSL 的 NMake target、安装和验证流程；
- 依赖构建 skill；
- `.gitignore`；
- `README.md` 和各依赖说明文档。

不能简单移动现有 `build/`。CMake cache、OpenSSL Config package、生成工程和 manifest 中含有原绝对路径，必须从新的 `output/` 目录进行干净重建。

## 12. 验收标准

### 普通构建

- Debug、Release 使用完全独立的配置根；
- 默认命令不编译任何单元测试、smoke、示例或可选 CLI；
- 公共 `bin` 只包含产品 allowlist 中的 EXE、DLL、LIB、linker PDB 和 Qt runtime；
- `build` 包含全部 obj、生成源码和 compiler PDB；
- 公共 `include` 来自匹配配置的已验证 stage；
- 应用可直接从公共 `bin` 启动。

### 测试命令

- 第一次执行测试命令时才生成测试程序；
- 单元测试与网络/runtime smoke 使用不同入口；
- 测试程序不进入公共 `bin`；
- 测试结果引用同一次产品构建的 manifest；
- 测试失败不伪装为产品编译失败，但 Release gate 必须拒绝缺失或失败的测试记录。

### 配置与产物

- Debug 公共产物不进入 Release；
- Release 不依赖 Debug CRT；
- zlib、zstd、Brotli、OpenSSL、SQLCipher 和应用均具有明确的 linker PDB 策略；
- `vc143.pdb` 等 compiler PDB 不进入公共输出；
- 清理单个依赖不会删除其他依赖产物；
- 从空 `output/` 可重复生成相同目录契约。

## 13. 推荐实施顺序

1. 固定本文目录、命令和 manifest 契约。
2. 先迁移 Brotli、zlib、zstd 的 build root，并拆分 build/test。
3. 迁移 OpenSSL，使用 `build_libs` 和独立 tests 流程。
4. 迁移 SQLCipher，把 CLI/provider smoke 从默认产品 target 分离。（已完成）
5. 增加公共产物汇总和 ownership manifest。（已完成）
6. 修改主程序 Preset、binary directory 和依赖 stage 路径。（已完成）
7. 将四个单元测试改为 `EXCLUDE_FROM_ALL` 并增加 test workflow。（已完成）
8. 调整 runtime 校验，区分 development output 和 package runtime。
9. 从空目录分别构建并测试 Debug、Release。
10. 最后更新 README，将本文中的目标命令升级为正式命令。

不建议一次性把目录迁移、依赖脚本、主程序、安装器和 NSIS 全部改完。每个依赖完成新的产品构建、独立测试和目录验证后，再迁移上层消费者。
