# zlib 1.3.2 VS2022 x64 动态构建分析

> 分析对象：`third_party/zlib/src/CMakeLists.txt`
>
> 目标包装文件：`third_party/zlib/CMakeLists.txt`
>
> 目标平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`
>
> CMake：`3.30.3`
>
> zlib：`v1.3.2` / `da607da739fa6047df13e66a2af6b8bec7c2a498`

## 1. 本轮范围

本文先分析上游 zlib CMake 构建方式，并确定项目级包装、编译脚本和 skill 的实现约束。当前文档更新阶段没有创建或修改 `third_party/zlib/CMakeLists.txt`、`third_party/zlib/build.cmd` 或 skill，没有修改 `third_party/zlib/src`，也没有执行 zlib 配置、编译、测试或安装。

后续实现目标是：

1. 只支持 Windows x64；
2. 使用 Visual Studio 2022、MSVC v143 和 Windows SDK `10.0.22621.0`；
3. 只构建动态 zlib，不构建静态 zlib；
4. 使用 `/MDd` 构建 Debug、使用 `/MD` 构建 Release；
5. 采用与 OpenSSL、SQLCipher 一致的 `work + stage` 目录约定；
6. 为以后集中构建 OpenSSL、zlib、Brotli、Zstd 和 SQLCipher 保留稳定接口；
7. 不修改固定的上游子模块源码。

以下三项已经由项目确认，不再作为待选方案：

1. Debug 和 Release 的动态库统一命名为 `zlib1.dll`；
2. 只构建 zlib 本体，明确排除 minizip、legacy `zlib1-dll` 和其他 contrib library；
3. DLL import library `zlib1.lib` 保留在对应配置的 stage 中。

## 2. 总体结论

可以新增外层 `third_party/zlib/CMakeLists.txt` 来实现项目所需的 zlib 构建策略，但不建议在外层文件中重新复制 zlib 的源文件列表和安装逻辑。

已确认采用以下方式：

```text
项目外层 CMakeLists.txt
        |
        |- 检查 Windows / MSVC / VS2022 / x64 / SDK
        |- 固定动态库、CRT、测试和安装策略
        |- add_subdirectory(src)
        |- 修正 Windows DLL 名称和 Debug 后缀
        `- 提供项目级 stage 契约
```

也就是说，“重新实现 zlib 构建”应理解为重新实现 SQLiteBrowser 的构建入口和策略层，而不是分叉上游的 CMake 源文件清单。

采用该方案可以继续使用上游维护的：

- zlib 源文件集合；
- `zconf.h` 生成逻辑；
- Windows DLL 导出宏；
- CMake target 和 install/export 规则；
- 示例测试和 CMake package 测试；
- 后续版本中的源文件调整。

## 3. 上游 CMake 构建方式

### 3.1 工程和版本

上游 `CMakeLists.txt` 声明：

```cmake
cmake_minimum_required(VERSION 3.12...3.31)

project(
    zlib
    LANGUAGES C
    VERSION 1.3.2
)
```

当前项目使用 CMake `3.30.3`，位于上游声明的兼容范围内。

zlib 是纯 C 工程，不需要 C++ 编译器。上游 CMake 会检测：

- `off64_t`；
- `fseeko`；
- `stdarg.h`；
- `unistd.h`；
- visibility attribute。

在 Windows/MSVC 上，不支持的 Unix 能力会通过生成的 `zconf.h` 和编译宏正确关闭。

### 3.2 上游构建选项

上游提供以下主要选项：

| 选项 | 默认值 | 作用 | 本项目建议 |
|---|---:|---|---:|
| `ZLIB_BUILD_TESTING` | `ON` | 构建示例并注册 CTest | `ON` |
| `ZLIB_BUILD_SHARED` | `ON` | 构建动态库 `zlib` | `ON` |
| `ZLIB_BUILD_STATIC` | `ON` | 构建静态库 `zlibstatic` | `OFF` |
| `ZLIB_INSTALL` | `ON` | 生成安装和 CMake package 规则 | `ON` |
| `ZLIB_PREFIX` | `OFF` | 为 API/类型增加前缀 | `OFF` |

本项目应显式写入这些值，不能依赖上游默认值。这样上游以后改变默认配置时，本项目的 ABI 和产物不会静默变化。

### 3.3 动态和静态目标

开启 `ZLIB_BUILD_SHARED` 时，上游创建：

```text
target: zlib
alias:  ZLIB::ZLIB
type:   SHARED
```

开启 `ZLIB_BUILD_STATIC` 时，上游创建：

```text
target: zlibstatic
alias:  ZLIB::ZLIBSTATIC
type:   STATIC
```

本项目只需要动态构建，因此应设置：

```cmake
set(ZLIB_BUILD_SHARED ON CACHE BOOL "" FORCE)
set(ZLIB_BUILD_STATIC OFF CACHE BOOL "" FORCE)
```

这会停止生成真正的静态库目标 `zlibstatic`。

需要区分两种 `.lib`：

1. 静态库：包含完整 zlib 机器码，本项目不需要；
2. DLL import library：MSVC 为 DLL 自动生成，用于普通链接动态库。

即使关闭静态库，Windows 动态构建仍会产生 import library。这不是多余的静态 zlib，建议在开发 stage 中保留；最终用户安装包通常不需要部署 `.lib`。

### 3.4 公开头文件

上游安装两个公开头文件：

```text
zlib.h
zconf.h
```

其中 `zconf.h` 在 CMake binary directory 中生成，不能只从源码目录复制同名文件。stage 必须使用本次配置生成并由上游 install 规则安装的 `zconf.h`。

### 3.5 Windows DLL 导出

上游动态目标使用：

```cmake
DEFINE_SYMBOL ZLIB_DLL
```

zlib 源文件通过 `ZLIB_INTERNAL`、`ZLIB_DLL`、`ZEXTERN` 和 `ZEXPORT` 控制 Windows 导入导出。上游还把 `win32/zlib1.rc` 加入 DLL，以写入 Windows 文件版本资源。

外层包装不应自行增加 `WINDOWS_EXPORT_ALL_SYMBOLS`，也不应重新定义调用约定。否则可能扩大导出表或产生与官方 CDECL ABI 不一致的 DLL。

### 3.6 上游默认文件名

上游普通动态目标设置：

```cmake
OUTPUT_NAME z
```

并在 Windows 上全局设置：

```cmake
CMAKE_DEBUG_POSTFIX d
```

因此使用 Visual Studio 生成器时，普通目标预期得到类似：

```text
Release: z.dll / z.lib
Debug:   zd.dll / zd.lib
```

但 OpenSSL 3.5.7 的 `zlib-dynamic` 在 Windows 上默认运行时加载：

```text
ZLIB1.dll
```

如果直接使用上游普通目标的默认名称，OpenSSL 将无法按默认名称找到 DLL。

### 3.7 legacy `zlib1-dll` 目标不适合本项目

上游 `contrib/zlib1-dll` 可以生成名为 `zlib1` 的 DLL，但该目标明确是“zlib + minizip”的 legacy DLL，并把 minizip 源码一起编入 DLL。

本项目只需要 OpenSSL 使用的标准 zlib 压缩 API，不应为了得到 `zlib1.dll` 而额外引入 minizip API 和攻击面。

因此已经确定：

- 不启用 `ZLIB_BUILD_ZLIB1_DLL`；
- 使用上游普通 `zlib` target；
- 在外层包装中把普通 target 的 Windows 输出名改为 `zlib1`；
- 构建后验证导出表满足 OpenSSL 的动态加载需求。

## 4. 已确认的外层 CMake 设计

### 4.1 包装层职责

未来的 `third_party/zlib/CMakeLists.txt` 应只负责：

1. 声明项目最低 CMake 版本；
2. 限制 Windows、MSVC、VS2022 和 x64；
3. 检查 Windows SDK `10.0.22621.0`；
4. 检查 `src/CMakeLists.txt` 和关键源码是否存在；
5. 固定 shared/static/testing/install 选项；
6. 固定 MSVC 动态 CRT；
7. 通过 `add_subdirectory(src)` 引入上游构建；
8. 修正 DLL 名称和 Debug 后缀；
9. 暴露稳定的构建、测试、安装入口；
10. 为以后自动化写 manifest 和 stage 验证提供参数。

它不应：

- 修改 `third_party/zlib/src`；
- 复制上游的 16 个核心 `.c` 文件列表；
- 重新生成一套不同的 `zconf.h`；
- 启用 minizip、contrib 或 legacy zlib1 DLL；
- 自动下载系统依赖；
- 把产物复制到 SQLiteBrowser 应用或安装器目录。

### 4.2 构建边界：只构建 zlib 本体

外层包装必须显式固定：

```cmake
ZLIB_BUILD_SHARED=ON
ZLIB_BUILD_STATIC=OFF
ZLIB_BUILD_TESTING=ON
ZLIB_INSTALL=ON
ZLIB_PREFIX=OFF
```

还应在进入上游 `add_subdirectory(src)` 前，把当前上游提供的 contrib 选项显式设为 `OFF`：

```text
ZLIB_BUILD_ADA
ZLIB_BUILD_BLAST
ZLIB_BUILD_IOSTREAM3
ZLIB_BUILD_MINIZIP
ZLIB_BUILD_PUFF
ZLIB_BUILD_TESTZLIB
ZLIB_BUILD_ZLIB1_DLL
ZLIB_WITH_GVMAT64
ZLIB_WITH_INFBACK9
ZLIB_WITH_CRC32VX
```

这样第一版只产生 zlib 动态 target，以及 `ZLIB_BUILD_TESTING=ON` 所需的临时测试可执行文件。测试程序只存在于 work 中，不进入正式 stage。

特别注意：

- 不启用 `ZLIB_BUILD_MINIZIP`；
- 不启用把 zlib 与 minizip 合并的 legacy `ZLIB_BUILD_ZLIB1_DLL`；
- 不构建静态 `zlibstatic`；
- 不把 `contrib/minizip` 的 headers、DLL 或 import library 安装到 stage；
- 不因为未来可能使用而预先启用其他 contrib feature。

升级 zlib 时仍需审计上游 `contrib/CMakeLists.txt` 是否新增选项，防止产物范围静默扩大。

### 4.3 平台限制

建议沿用 SQLCipher wrapper 的显式失败策略：

```text
WIN32 required
MSVC required
MSVC_VERSION must belong to VS2022
CMAKE_SIZEOF_VOID_P must equal 8
Windows SDK must equal 10.0.22621.0
```

MSVC 版本检查建议接受 VS2022 的整个工具链范围，而不是只匹配某一个 `cl.exe` 小版本，以兼容 VS2022 Enterprise、Professional 和 Community 的更新。

外层 CMake 不需要检查 VS 安装目录。CMake generator 已经选择了具体 VS instance；默认路径和 edition 检查更适合以后统一的 `build.cmd`。

### 4.4 CRT 策略

项目当前约定为：

| 配置 | MSVC Runtime | 预期依赖 |
|---|---|---|
| Debug | `/MDd` | Debug VC Runtime 和 Debug UCRT |
| Release | `/MD` | Release VC Runtime 和 UCRT |

外层包装应在创建 zlib target 前设置 `CMAKE_MSVC_RUNTIME_LIBRARY`，例如采用 CMake generator expression 选择 Debug/Release 动态 CRT。

由于 Debug 和 Release 使用不同 stage，可以让两个配置都使用相同 DLL 文件名 `zlib1.dll`，而不依赖 `zlib1d.dll` 区分配置。

这与当前 OpenSSL 的配置独立 stage 一致，并能让 OpenSSL 的默认 `zlib-dynamic` 名称在两个配置下保持不变。

### 4.5 DLL 和 import library 命名

已确认对上游 `zlib` target 设置：

```text
OUTPUT_NAME:    zlib1
DEBUG_POSTFIX:  空
```

预期产物为：

```text
Debug stage:
  bin/zlib1.dll
  lib/zlib1.lib

Release stage:
  bin/zlib1.dll
  lib/zlib1.lib
```

相同文件名不会冲突，因为两个配置位于不同 stage。

这也避免未来 OpenSSL 为 Debug/Release 传递不同的 `--with-zlib-lib` 动态库名称。

`zlib1.lib` 必须保留在 stage 的 `lib` 目录。它是 `zlib1.dll` 的 import library，不是已经排除的静态 zlib。普通 CMake/MSVC 消费者可以用它链接 DLL；OpenSSL 的 `zlib-dynamic` 虽然不需要链接它，完整开发 stage 仍应保留。

### 4.6 是否使用 `win32/zlib.def`

第一版应优先使用上游普通 `zlib` target 的既有导出机制，不要立即额外注入 `win32/zlib.def`。

实现后必须使用 `dumpbin /exports` 验证公开符号。至少应确认 OpenSSL 动态加载需要的压缩、解压和错误函数均存在，并确认导出名没有 x86 风格修饰。

只有在实际导出验证失败时，再评估把 `win32/zlib.def` 加入 target。避免在没有证据时叠加两套导出机制，产生重复导出警告或 ABI 差异。

### 4.7 测试策略

已确认保持：

```cmake
ZLIB_BUILD_TESTING=ON
```

动态构建会生成并测试 `zlib_example`。测试定义会把 DLL target 目录放入临时 `PATH`，适合 Windows 动态库验证。

上游还提供：

- install fixture；
- `find_package` configure/build/test；
- `add_subdirectory` configure/build/test；
- 错误 component 验证。

关闭静态库后，静态示例不会生成。上游对“不带 component 查找但只安装一种库”的用例标记为预期失败，所以不应误判为真实测试失败。

正式构建至少执行：

```cmd
ctest --test-dir <work> -C Debug --output-on-failure
ctest --test-dir <work> -C Release --output-on-failure
```

zlib 测试不存在 OpenSSL `test_bio_dgram` 的 IPv6 UDP 卡住问题，因此没有必要仿照 OpenSSL 排除网络测试。

### 4.8 CMake package 限制

上游安装的 `ZLIBConfig.cmake` 默认同时包含：

```text
ZLIB-shared.cmake
ZLIB-static.cmake
```

当本项目只构建 shared 时，不带 component 的：

```cmake
find_package(ZLIB CONFIG REQUIRED)
```

可能尝试包含不存在的 static export。

第一版下游应显式使用：

```cmake
find_package(ZLIB CONFIG REQUIRED COMPONENTS shared)
target_link_libraries(target PRIVATE ZLIB::ZLIB)
```

OpenSSL 的 `zlib-dynamic` 不使用该 CMake package，也不链接 import library，因此不会受此限制。

如果以后将全部依赖统一为 CMake package 消费方式，应再决定：

1. 保留上游 config，并要求所有消费者指定 `COMPONENTS shared`；或
2. 在项目包装层生成只声明 shared 的项目级 config。

不建议为了让无 component 查找成功而重新打开静态库。

## 5. 推荐输出目录

### 5.1 根目录约定

与 OpenSSL、SQLCipher 保持一致：

```text
build/
`- zlib/
   |- x64-debug/
   |  |- work/
   |  `- stage/
   `- x64-release/
      |- work/
      `- stage/
```

虽然 Visual Studio 是多配置生成器，但仍建议 Debug 和 Release 使用独立 work：

- 与 OpenSSL 的独立 NMake work/stage 对齐；
- 避免误把某个配置安装到另一个配置的 stage；
- 便于 `clean` 精确删除单个依赖和配置；
- 便于以后统一 build manifest；
- 便于检查 `/MDd` 与 `/MD`，防止混用。

### 5.2 stage 契约

已确认 stage 结构：

```text
stage/
|- bin/
|  |- zlib1.dll
|  `- zlib1.pdb             # 如果对应配置生成并安装
|- include/
|  |- zlib.h
|  `- zconf.h
|- lib/
|  |- zlib1.lib             # DLL import library，不是静态 zlib
|  |- cmake/
|  |  `- zlib/
|  |     |- ZLIBConfig.cmake
|  |     |- ZLIBConfigVersion.cmake
|  |     `- ZLIB-shared.cmake
|  `- pkgconfig/
|     `- zlib.pc
`- build-manifest.txt       # 后续自动化生成
```

上游 install 规则已经能生成绝大部分布局。项目包装层主要解决配置、命名和验证，不需要手工复制头文件或 import library。

`lib/zlib1.lib` 是 stage 契约中的必需开发产物。最终用户安装包只部署运行时 DLL，不部署 `.lib`；但依赖 stage 不是最终安装包，不能因为 OpenSSL 动态加载时暂时不用 import library 就把它删除。

PDB 的位置在现有依赖中并不完全统一：OpenSSL 把 PDB 放在 `bin`，SQLCipher 使用单独的 `pdb`。zlib 第一版可沿用上游 install 到 `bin` 的行为；以后集中依赖构建时再统一符号归档规范。

### 5.3 建议的配置和构建流程

未来脚本可按以下逻辑驱动外层 CMake。以下命令是设计示例，本轮没有执行：

```cmd
cmake -S third_party\zlib ^
  -B build\zlib\x64-release\work ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_SYSTEM_VERSION=10.0.22621.0 ^
  -DCMAKE_INSTALL_PREFIX=build\zlib\x64-release\stage

cmake --build build\zlib\x64-release\work --config Release

ctest --test-dir build\zlib\x64-release\work ^
  -C Release --output-on-failure

cmake --install build\zlib\x64-release\work --config Release
```

Debug 使用独立的 `x64-debug/work` 和 `x64-debug/stage`，并把 `--config` 改成 `Debug`。

未来 build script 应传入 `CMAKE_GENERATOR_INSTANCE`，确保使用检查到的 VS2022 Enterprise、Professional 或 Community 实例；不应让已有 build tree 静默切换 VS instance。

## 6. 构建后验证

### 6.1 必需产物

每个配置的 stage 至少应包含：

```text
bin/zlib1.dll
include/zlib.h
include/zconf.h
lib/zlib1.lib
lib/cmake/zlib/ZLIBConfig.cmake
lib/cmake/zlib/ZLIB-shared.cmake
build-manifest.txt
```

这里保留 `zlib1.lib` 是为了提供完整开发 stage。最终 SQLiteBrowser 安装包只需要运行时 DLL，不需要 `.lib`、头文件或 CMake package。

### 6.2 架构验证

必须使用 `dumpbin /headers` 确认：

```text
machine (x64)
```

不能只根据 build 目录名称判断架构。

### 6.3 CRT 验证

使用 `dumpbin /dependents` 检查：

- Release 不得依赖 `VCRUNTIME140D.dll`；
- Release 不得依赖 `ucrtbased.dll`；
- Debug 应体现 Debug CRT 依赖；
- Debug DLL 不得进入 Release stage 或正式安装包。

### 6.4 导出验证

使用 `dumpbin /exports bin\zlib1.dll` 验证公开 API。OpenSSL 3.5.7 的动态 zlib 实现会在运行时绑定一组 zlib 函数，至少应覆盖：

```text
compress
uncompress
inflateInit_
inflate
inflateEnd
deflateInit_
deflate
deflateEnd
zError
```

还应检查 `zlibVersion`，并通过示例或独立 probe 确认运行时返回 `1.3.2`。

### 6.5 测试边界

只有在 CTest 成功执行后才能报告“zlib 上游 CMake 测试通过”。仅编译并运行 `dumpbin` 不等价于测试通过。

后续 OpenSSL 启用 `zlib-dynamic` 后，还需要额外执行 OpenSSL 自己的：

- compression BIO 测试；
- TLS 1.3 certificate compression 测试；
- OpenSSL 运行时加载 `zlib1.dll` 的集成 probe。

zlib 单独测试通过不能证明 OpenSSL 集成已经通过。

## 7. build manifest 建议

zlib 上游 CMake 不生成本项目格式的 `build-manifest.txt`。为了与 OpenSSL、SQLCipher 对齐，后续自动化应在测试、安装和验证全部成功后生成。

建议至少记录：

```text
zlib tag: v1.3.2
zlib commit: da607da739fa6047df13e66a2af6b8bec7c2a498
Configuration: Debug or Release
Architecture: x64
Visual Studio: <edition> 2022
MSVC tools: <version>
Windows SDK: 10.0.22621.0
CMake: 3.30.3
CRT: /MDd or /MD
Shared library: ON
Static library: OFF
Tests: passed / not run
zlib runtime version: 1.3.2
zlib1.dll SHA256: <hash>
zlib1.lib SHA256: <hash>
```

manifest 生成前应验证子模块：

- HEAD 等于固定 commit；
- exact tag 为 `v1.3.2`；
- 子模块工作区干净。

不能为来源不明或测试失败的手工产物补写正式 manifest。

## 8. 与 OpenSSL 的后续集成

如果以后采用 OpenSSL 的动态 zlib 模式，OpenSSL Configure 可以使用：

```text
zlib-dynamic
--with-zlib-include=<matching-zlib-stage>/include
```

当 DLL 名称固定为 `zlib1.dll` 时，不需要为 Debug 和 Release指定不同运行时名称。

OpenSSL 构建和测试时必须把匹配配置的 zlib `bin` 临时加入 `PATH`：

```text
Debug OpenSSL   -> Debug zlib stage
Release OpenSSL -> Release zlib stage
```

不能出现：

- Debug OpenSSL 使用 Release zlib；
- Release OpenSSL 使用 Debug zlib；
- 使用系统 PATH 中来源不明的 `zlib1.dll`；
- 安装器同时包含多份不同来源的 `zlib1.dll`。

OpenSSL manifest 以后也应记录 zlib tag、commit、stage manifest hash 和 DLL SHA-256，形成完整依赖链。

## 9. 为以后集中构建保留的接口

当前不建议立刻把 OpenSSL、zlib 和 SQLCipher 改造成一个巨大的 CMake 工程。OpenSSL 仍使用 Configure/NMake，SQLCipher 当前仍通过 NMake wrapper，强行合并会扩大变更面。

第一阶段应先统一以下契约：

```text
源码：third_party/<name>/src
入口：third_party/<name>/CMakeLists.txt 或 build.cmd
工作：build/<name>/x64-<config>/work
部署：build/<name>/x64-<config>/stage
记录：build/<name>/x64-<config>/stage/build-manifest.txt
配置：Debug / Release
架构：x64
CRT： /MDd / /MD
```

以后可以增加一个编排层，只负责依赖顺序：

```text
zlib / Brotli / Zstd
          |
          v
      OpenSSL
          |
          v
      SQLCipher
          |
          v
    SQLiteBrowser
```

编排层应调用每个依赖自己的稳定入口，而不是重新实现每个项目的内部构建命令。

## 10. 已识别风险

### 10.1 DLL 名称不匹配

直接使用上游普通 CMake 默认名称会生成 `z.dll`/`zd.dll`，而 OpenSSL `zlib-dynamic` 默认查找 `zlib1.dll`。外层包装必须统一名称，或者 OpenSSL 必须显式配置动态加载名。优先建议前者。

### 10.2 Debug 后缀导致运行时不一致

上游 Windows 默认 Debug postfix 为 `d`。如果保留，OpenSSL Debug 必须查找另一名称。由于本项目已经使用配置独立 stage，建议清空 target 的 Debug postfix。

### 10.3 把 import library 误认为静态库

关闭 `ZLIB_BUILD_STATIC` 后仍会看到 `.lib`。这是 DLL import library，不能据此判断静态 zlib 仍在构建。

### 10.4 CMake package 默认查找失败

只安装 shared 时，上游无 component config 仍可能尝试包含 static export。消费者必须显式指定 `COMPONENTS shared`，或以后提供项目级 package config。

### 10.5 legacy zlib1 DLL 引入 minizip

启用 `ZLIB_BUILD_ZLIB1_DLL` 会引入 minizip，不符合当前最小依赖目标。不能仅因为目标名称正确就使用该构建。

### 10.6 CRT 混用

Debug/Release zlib stage 混用会把 Debug CRT 引入 Release 依赖链。OpenSSL 和最终应用都必须按配置匹配。

### 10.7 只验证文件存在

仅存在 `zlib1.dll` 不能证明它是 x64、v1.3.2、正确 CRT 或正确导出。必须结合 revision、CTest、`dumpbin`、版本 probe 和 SHA-256。

### 10.8 `.cmake` 忽略规则

仓库 `.gitignore` 全局忽略 `*.cmake`。未来如果为 zlib 增加项目自有的 `cmake/*.cmake` helper，需要像 SQLCipher 一样增加精确反忽略规则。目标文件 `third_party/zlib/CMakeLists.txt` 本身不受该规则影响。

## 11. 编译脚本实现

统一入口已经实现为 `third_party/zlib/build.cmd`。脚本是开发人员、Codex 和 Claude 共用的唯一命令入口；skill 只负责选择参数、调用、监控和解释结果。

### 11.1 命令模式

```cmd
third_party\zlib\build.cmd
third_party\zlib\build.cmd all
third_party\zlib\build.cmd debug
third_party\zlib\build.cmd release
third_party\zlib\build.cmd check
third_party\zlib\build.cmd all clean
```

| 参数 | 行为 |
|---|---|
| 无参数 / `all` | 构建、测试、安装并验证 Debug 和 Release |
| `debug` | 只处理 Debug |
| `release` | 只处理 Release |
| `check` | 只检查源码和工具链，不生成构建输出 |
| `clean` | 删除所选配置的 `work` 和 `stage` 后重新构建 |

zlib 没有 OpenSSL 已知的 IPv6 UDP 测试冲突，因此第一版不需要 `safe`、`full` 或 `none`。正常构建必须执行 CTest，不能静默跳过。

### 11.2 前置检查

脚本检查 Windows x64、Git、CMake/CTest、默认目录中的 VS2022、MSVC v143 x64 tools、SDK `10.0.22621.0`、系统默认路径中的 Windows PowerShell、`certutil.exe`、固定 tag/commit 和干净的 zlib 子模块。子模块未初始化时可以运行限定路径的 `git submodule update --init --recursive`，但不能自动覆盖本地修改。

manifest 的 SHA-256 使用 Windows 自带的 `certutil.exe` 计算，不依赖 PowerShell 的 `Get-FileHash` 模块自动加载。DLL 版本资源检查则显式调用 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`，避免 VS 或父进程 `PATH` 中的同名程序改变行为。

### 11.3 构建流程和验收

每个配置依次执行：

```text
CMake configure
    -> cmake --build
    -> ctest --output-on-failure
    -> cmake --install
    -> artifact/version/export/CRT verification
    -> build-manifest.txt
```

脚本必须显式传递 VS2022 generator、`-A x64`、VS instance、SDK 和绝对 install prefix。`clean` 只能删除 `build/zlib/x64-debug` 或 `build/zlib/x64-release` 下对应的 `work` 和 `stage`，并必须先验证绝对路径。

每个配置必须验证：

- `bin/zlib1.dll`、`lib/zlib1.lib`、`include/zlib.h` 和 `include/zconf.h`；
- x64、匹配的 CRT、OpenSSL 所需导出和 runtime version `1.3.2`；
- CTest 和 manifest；
- stage 不含静态 zlib、minizip DLL/lib/headers 或其他 contrib。

## 12. 项目 skill 实现

已经新增：

```text
.agents/skills/sqlitebrowser-build-zlib/SKILL.md
.claude/skills/sqlitebrowser-build-zlib/SKILL.md
```

Codex skill 是规范来源；Claude skill 作为兼容入口引用同一套规则。skill 使用 `third_party\zlib\build.cmd` 作为唯一构建事实来源，覆盖环境检查、Debug/Release 构建、CTest、stage、CRT、导出和 manifest 验证。

skill 不用于系统安装、非 Windows x64、修改上游源码、构建 minizip/contrib、最终应用部署或未经请求的 Git 提交。未经用户选择或批准不得添加 `clean`；只分析时不得运行构建。

成功报告必须包含 VS/MSVC/SDK/CMake、tag/commit、配置和 stage，以及 CTest、x64、CRT、导出、版本、manifest 和 contrib 排除结果。zlib 单独通过不能表述为 OpenSSL 集成已经通过。

### 12.1 使用前提

本节描述当前已经实现的 zlib 编译脚本和项目 skill。完成子模块和工具链准备后，下面的命令可以直接使用。

首次拉取仓库后，先在仓库根目录初始化依赖：

```cmd
git submodule update --init --recursive
```

然后确认：

- 当前目录位于 SQLiteBrowser 仓库内，Codex 或 Claude Code 能向上找到仓库根目录；
- `third_party\zlib\src` 已初始化为仓库固定的 zlib v1.3.2；
- Visual Studio 2022、MSVC v143 x64 工具和 Windows SDK `10.0.22621.0` 已安装；
- `cmake.exe` 和 `ctest.exe` 可从 `PATH` 调用；
- `third_party\zlib\build.cmd`、Codex 规范 skill 和 Claude Code 兼容 skill 均已存在。

不要求开发人员手工打开 VS2022 IDE、选择具体 VS 版本或拼接 CMake 参数。skill 应先检查环境，再调用仓库脚本。

### 12.2 使用 Codex skill

Codex 从仓库的 `.agents\skills` 发现项目 skill。按照 [OpenAI 官方 Build skills 文档](https://learn.chatgpt.com/docs/build-skills)，可以使用 `$` 显式引用 skill，也可以通过与 skill description 匹配的自然语言请求触发。

检查环境，不执行构建：

```text
$sqlitebrowser-build-zlib 检查当前机器是否满足 zlib 构建条件
```

构建、测试并验证 Debug 和 Release：

```text
$sqlitebrowser-build-zlib 构建并验证 zlib 的 Debug 和 Release
```

只处理 Release：

```text
$sqlitebrowser-build-zlib 构建、运行测试并验证 zlib Release
```

明确清理 Release 的 work 和 stage 后重新构建：

```text
$sqlitebrowser-build-zlib 对 zlib Release 执行 clean 构建和完整验证
```

也可以使用自然语言：

```text
帮我构建当前项目固定的 zlib Release，先检查 VS2022、x64 工具链和 SDK 10.0.22621.0，然后运行测试并检查 stage。
```

skill 的 description 应覆盖环境检查、Debug/Release 构建、CTest、产物验证和 stage 等触发词。只要求分析、阅读日志或检查现有产物时，skill 不得擅自执行构建或修改文件；未明确要求 `clean` 时，也不得删除现有 work 或 stage。

Codex 能自动检测 skill 变更。如果新增 skill 后没有出现在当前环境中，可重新打开任务或重启 Codex。

### 12.3 使用 Claude Code skill

Claude Code 通过项目根目录的 `.claude\skills\sqlitebrowser-build-zlib\SKILL.md` 提供兼容入口。根据 [Claude Code Skills 官方文档](https://code.claude.com/docs/en/skills)，项目 skill 可以用 `/skill-name` 显式调用。

检查环境：

```text
/sqlitebrowser-build-zlib 检查 zlib 构建环境
```

构建全部配置：

```text
/sqlitebrowser-build-zlib 构建、测试并验证 Debug 和 Release
```

清理后只构建 Release：

```text
/sqlitebrowser-build-zlib 对 Release 执行 clean 构建和验证
```

Claude Code 兼容入口不复制构建规则，只负责定位仓库根目录、完整读取 `.agents\skills\sqlitebrowser-build-zlib\SKILL.md`，然后遵循规范 skill。构建逻辑仍以 `third_party\zlib\build.cmd` 为唯一事实来源，从而让 Codex、Claude Code 和人工调用使用同一套流程。

如果当前 Claude Code 会话没有发现新加入的项目 skill，重新启动 Claude Code。

### 12.4 请求与脚本模式映射

skill 将用户意图映射为脚本模式，不应临时重新实现 CMake 命令：

| 用户请求 | 脚本调用 | 是否构建 | 是否运行 CTest |
|---|---|---:|---:|
| 未指定配置，要求构建 | `third_party\zlib\build.cmd all` | 是，Debug + Release | 是 |
| 只构建 Debug | `third_party\zlib\build.cmd debug` | 是 | 是 |
| 只构建 Release | `third_party\zlib\build.cmd release` | 是 | 是 |
| 只检查环境 | `third_party\zlib\build.cmd check` | 否 | 否 |
| 明确要求清理后构建 | `third_party\zlib\build.cmd <all|debug|release> clean` | 是 | 是 |

第一版没有跳过测试模式。除 `check` 外，成功构建必须运行 CTest；测试失败时 skill 应报告失败，不能只因 DLL 已生成就宣称构建验证通过。

### 12.5 skill 的预期执行过程

skill 应依次完成：

1. 定位仓库根目录，确认 Windows x64 和 zlib 子模块状态；
2. 检查默认安装目录中的 Visual Studio 2022、MSVC v143 x64 工具和 SDK `10.0.22621.0`；
3. 检查 CMake、CTest 和 `third_party\zlib\build.cmd`；
4. 根据请求选择 `all`、`debug`、`release`、`check` 及显式的 `clean`；
5. 调用脚本并监控 configure、build、CTest、install 和验证阶段；
6. 检查每个已选配置的 stage 和 `build-manifest.txt`；
7. 汇报实际工具链、配置、测试结果、stage 路径和任何未执行项。

skill 不应：

- 修改 `third_party\zlib\src` 上游源码；
- 构建或部署 minizip、其他 contrib 组件或静态 zlib；
- 使用系统级 zlib 替代仓库固定版本；
- 在指定 SDK 缺失时自动换用其他 SDK 并宣称结果等价；
- 把 stage 当作系统安装或最终 SQLiteBrowser 打包；
- 未经单独请求提交或推送 Git 修改。

### 12.6 完成报告和验收标准

成功报告至少包含：

- 实际使用的 VS2022 edition、MSVC tools、Windows SDK 和 CMake 版本；
- zlib tag/commit 以及子模块是否干净；
- 实际处理的 Debug、Release 配置；
- CTest 是否运行及其结果；
- 每个配置的 stage 绝对路径；
- `bin\zlib1.dll`、`lib\zlib1.lib`、`include\zlib.h` 和 `include\zconf.h` 的检查结果；
- DLL 架构、CRT、导出符号和运行时版本检查结果；
- `build-manifest.txt` 是否存在且与本次构建一致；
- stage 中不存在 minizip、其他 contrib 产物和静态 zlib 的验证结果。

其中 `zlib1.lib` 是 `zlib1.dll` 的导入库，保留在 stage 不表示启用了静态库构建。zlib skill 通过仅代表 zlib 本体的构建、测试和 stage 验证通过，不代表 OpenSSL 的 zlib 集成已经验证。

## 13. 实施状态与后续顺序

本轮已完成以下第 1 至 14 项；第 15 项保留给后续 OpenSSL 集成变更：

1. 新增外层 `third_party/zlib/CMakeLists.txt`；
2. 限制 Windows x64、VS2022 和 SDK；
3. 固定 shared ON、static OFF、testing ON、install ON；
4. 固定 `/MDd` 和 `/MD`；
5. 使用 `add_subdirectory(src)`；
6. 将上游普通动态 target 命名为 `zlib1` 并清空 Debug postfix；
7. 分别从空 work 配置 Debug 和 Release；
8. 构建并运行完整 CTest；
9. 安装到配置独立 stage；
10. 验证架构、CRT、导出、版本和必需文件；
11. 生成 `build-manifest.txt`；
12. 新增并验证 `third_party/zlib/build.cmd`；
13. 新增并验证 Codex/Claude 项目 skill；
14. 增加脚本和 skill 使用说明；
15. 后续修改 OpenSSL 自动化以消费匹配的 zlib stage。

不建议在同一次变更中同时加入 zlib wrapper、重写 OpenSSL、修改 SQLCipher 和修改最终安装器。先让 zlib 自身形成可重复的构建与 stage 契约，再接入上层依赖，问题定位会更清晰。

## 14. 最终决策

`third_party/zlib/CMakeLists.txt` 的最佳定位是项目级 policy wrapper：复用上游 target，但强制本项目平台、配置、命名、CRT 和输出契约。

第一版已确定采用：

```text
Windows x64 only
VS2022 / MSVC v143
SDK 10.0.22621.0
shared ON
static OFF
testing ON
install ON
DLL name zlib1.dll
Debug postfix empty
contrib libraries OFF
minizip OFF
legacy zlib1-dll OFF
zlib1.lib retained in stage
Debug /MDd
Release /MD
configuration-specific work and stage
```

这种设计能直接服务未来 OpenSSL `zlib-dynamic`，同时保留以后统一依赖编排和 CMake package 消费的空间。

## 15. 实施与构建验证结果

本轮已经新增并验证：

```text
third_party/zlib/CMakeLists.txt
third_party/zlib/build.cmd
.agents/skills/sqlitebrowser-build-zlib/SKILL.md
.claude/skills/sqlitebrowser-build-zlib/SKILL.md
```

2026-08-24 分别执行了以下命令，而不是只调用聚合的 `all` 模式：

```cmd
third_party\zlib\build.cmd debug
third_party\zlib\build.cmd release
```

实际工具链为：

```text
Visual Studio: Enterprise 2022
MSVC tools: 14.44.35207
C compiler: MSVC 19.44.35228.0
Windows SDK: 10.0.22621.0
CMake: 3.30.3
zlib: v1.3.2 / da607da739fa6047df13e66a2af6b8bec7c2a498
```

Debug 和 Release 均完成：

- CMake configure 和 MSBuild x64 编译；
- 上游完整 CTest：13/13 通过；
- 安装到配置独立 stage；
- `zlib1.dll`、`zlib1.lib`、`zlib.h`、`zconf.h` 和 `build-manifest.txt` 验证；
- x64、导出符号、版本 `1.3.2` 和配置匹配 CRT 验证；
- Debug/Release 无 `d` 后缀；
- stage 不含静态 zlib、minizip 或其他 contrib 产物。

最终 stage 为：

```text
build/zlib/x64-debug/stage
build/zlib/x64-release/stage
```

两份 skill 均通过 `skill-creator/scripts/quick_validate.py` 的 frontmatter 和结构校验。由于本机 Python 未安装 PyYAML，校验时使用了临时的最小 YAML 兼容解析器；该临时文件在校验后已删除，没有进入仓库修改。

当前结论仅覆盖 zlib 本体。OpenSSL 尚未改为消费这些 stage，也尚未验证 `zlib-dynamic` 集成，因此不能把本轮结果表述为 OpenSSL 压缩支持已启用。
