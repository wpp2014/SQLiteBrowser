# zstd 1.5.7 VS2022 x64 CMake 构建分析

> 2026-08-30 更新：统一输出、最小产品构建、独立 smoke test、Debug/Release linker PDB 已经实施。当前契约以 [Windows 统一输出目录与最小构建方案](unified-output-and-minimal-build-plan.md) 和 `third_party/zstd/build.cmd --help` 为准；本文后面的旧路径和旧命令保留为历史分析记录。

> 分析对象：`third_party/zstd/src` 中固定的 zstd `v1.5.7`
>
> 上游提交：`f8745da6ff1ad1e7bab384bd1f9d742439278e99`
>
> 主要入口：`third_party/zstd/src/build/cmake/CMakeLists.txt`
>
> 目标平台：Windows x64
>
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`
>
> 项目 CMake：`3.30.3`
>
> 分析日期：2026-08-24

## 1. 本轮范围

本文记录 zstd `v1.5.7` tag 下的 CMake 构建实现，并分析它如何适配 SQLiteBrowser v4.0.0 的 Windows 构建约束。

本轮只新增本文档，没有：

- 新增 `third_party/zstd/CMakeLists.txt`；
- 新增 zstd 编译脚本或 skill；
- 修改 `third_party/zstd/src`；
- 执行 CMake configure、编译、CTest 或 install；
- 修改 OpenSSL 构建选项；
- 生成或部署任何 zstd 二进制产物。

当前源码已经作为 submodule 固定在：

```text
third_party/zstd/src
```

固定版本为：

```text
tag:    v1.5.7
commit: f8745da6ff1ad1e7bab384bd1f9d742439278e99
```

## 2. 总体结论

zstd `v1.5.7` 可以使用 Visual Studio 2022 和 CMake `3.30.3` 构建 Windows x64 动态库，但不能完全照搬当前 zlib 的构建和测试策略。

推荐的总体结构是：

```text
third_party/zstd/CMakeLists.txt        # 后续新增的项目策略包装层
        |
        |- 检查 Windows / MSVC / VS2022 / x64 / SDK
        |- 固定 shared、CRT、模块和安装策略
        |- add_subdirectory(src/build/cmake)
        |- 统一 Windows DLL 名称
        |- 增加项目自己的共享库 smoke test
        `- 提供稳定的 stage 契约
```

不建议复制 zstd 的源文件列表，也不建议修改 submodule 内的上游 CMake 文件。项目包装层应复用上游：

- compression、decompression、dictionary builder 源码集合；
- Windows DLL 导出定义；
- Windows 版本资源；
- CMake target 和 install/export 规则；
- 版本解析逻辑；
- 后续 tag 对源文件集合的调整。

与 zlib 相比，最重要的差异是：

1. zstd `v1.5.7` 的 CMake 入口位于 `build/cmake`，源码根目录没有 `CMakeLists.txt`；
2. 上游 CMake 测试强制依赖静态库，并不会验证正式交付的共享 DLL；
3. 上游 CMake 生成 `zstd.dll`，但上游 Windows 资源和 OpenSSL 3.5.7 默认使用 `libzstd.dll`；
4. Visual Studio 多配置生成器不会触发上游基于 `CMAKE_BUILD_TYPE` 的 Debug 宏逻辑；
5. 上游提供的 `clean-all` 目标使用 Unix `rm -rf`，不能作为本项目 Windows 清理入口。

## 3. 上游构建系统定位

### 3.1 上游对 CMake 的定位

zstd `v1.5.7` 的 `README.md` 说明 Makefile 是上游正式维护的主要构建系统，CMake、Meson、Visual Studio solution 等属于兼容构建方式，可能在高级选项上存在差异。

本项目仍应选择 CMake，原因是：

- 目标环境已经固定 CMake `3.30.3`；
- CMake 可以稳定选择 Visual Studio 2022、x64、MSVC v143 和指定 SDK；
- 能生成标准的 install、CMake package 和 Visual Studio project；
- 容易与 zlib 的 `work + stage` 目录和后续统一编排对齐；
- 不需要额外引入 GNU Make、MSYS2 或修改上游 VS2010 solution。

不能因为 Makefile 是上游主要构建系统，就在当前 Windows 项目中额外引入另一套 shell 和工具链。对本项目而言，CMake 是变更面最小的选择。

### 3.2 不采用旧 Visual Studio solution

上游保留：

```text
build/VS2010/zstd.sln
build/VS_scripts/
```

这些文件主要覆盖旧版 Visual Studio，文档明确列出的自动脚本最高只到 VS2017。VS2010 solution 可以由较新的 Visual Studio 转换，但它不适合作为本项目的长期入口：

- 不能直接固定 Windows SDK `10.0.22621.0`；
- 输出和安装目录不符合当前 stage 约定；
- Debug、Release、静态库、CLI 和测试工具容易混在同一 solution 中；
- 需要维护 project upgrade 结果；
- 不提供本项目格式的 manifest 和验收过程。

因此 VS2022 只作为 CMake generator 和编译器，不直接打开旧 solution 构建。

### 3.3 不使用 FetchContent

源码已经由 Git submodule 固定到精确提交。再使用 `FetchContent` 会产生第二份来源和版本控制通道，不利于离线构建、审计和复现。

项目包装层应直接引用：

```text
third_party/zstd/src/build/cmake
```

## 4. CMake 入口和工程结构

### 4.1 正确入口

zstd `v1.5.7` 源码根目录没有 `CMakeLists.txt`。直接执行：

```cmd
cmake -S third_party\zstd\src
```

会失败。

上游直接配置入口是：

```cmd
cmake -S third_party\zstd\src\build\cmake
```

未来项目包装层应使用：

```cmake
add_subdirectory(
    "${CMAKE_CURRENT_LIST_DIR}/src/build/cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/upstream"
)
```

### 4.2 CMake 和 policy 版本

上游声明：

```cmake
cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
```

但随后把已验证 policy 上限固定为 CMake `3.13`。在 CMake `3.30.3` 下，上游仍采用 `3.13` policy 行为，而不是启用所有新 policy。

这不等于 CMake `3.30.3` 不受支持，但意味着：

- 配置时可能出现旧 policy 相关提示；
- 不能假设它会自动采用新 CMake 的行为；
- 升级 zstd tag 时要重新审计 CMake policy 和 install/export；
- 正式构建应从干净 work 目录重新 configure。

### 4.3 工程语言

顶层工程声明：

```text
C
ASM
CXX
```

libzstd 本体主要是 C，但 CXX 用于测试和 contrib。即使本项目关闭测试、CLI 和 contrib，顶层 `project()` 仍会探测 C++ 编译器。

VS2022 的 MSVC 安装必须同时具备可用的 C/C++ x64 工具链。无需额外的第三方汇编器。

### 4.4 版本来源

CMake 不把版本号重复硬编码在构建文件中，而是从：

```text
lib/zstd.h
```

解析：

```text
ZSTD_VERSION_MAJOR   = 1
ZSTD_VERSION_MINOR   = 5
ZSTD_VERSION_RELEASE = 7
```

得到：

```text
zstd_VERSION      = 1.5.7
ZSTD_FULL_VERSION = 1.5.7
```

后续 manifest 和运行时 probe 应同时验证 tag、commit 和 `ZSTD_versionNumber()`，不能只相信目录名称。

## 5. 上游主要构建选项

建议所有影响 ABI 和产物范围的选项都由项目包装层显式固定，不能依赖上游默认值。

| 选项 | v1.5.7 默认值 | 作用 | 本项目建议 |
|---|---:|---|---:|
| `ZSTD_BUILD_SHARED` | `ON` | 构建共享 libzstd | `ON` |
| `ZSTD_BUILD_STATIC` | `ON` | 构建静态 libzstd | `OFF` |
| `ZSTD_BUILD_COMPRESSION` | `ON` | 编译压缩模块 | `ON` |
| `ZSTD_BUILD_DECOMPRESSION` | `ON` | 编译解压模块 | `ON` |
| `ZSTD_BUILD_DICTBUILDER` | `ON` | 编译字典训练模块 | `ON` |
| `ZSTD_BUILD_DEPRECATED` | `OFF` | 编译 deprecated API | `OFF` |
| `ZSTD_BUILD_PROGRAMS` | `ON` | 构建 `zstd.exe` | `OFF` |
| `ZSTD_BUILD_CONTRIB` | `OFF` | 构建 pzstd、gen_html | `OFF` |
| `ZSTD_BUILD_TESTS` | 受 `BUILD_TESTING` 影响 | 构建 CMake 测试 | 正式构建 `OFF` |
| `ZSTD_PROGRAMS_LINK_SHARED` | `OFF` | CLI 是否链接共享库 | `OFF`，因为不构建 CLI |
| `ZSTD_MULTITHREAD_SUPPORT` | Windows 为 `ON` | 启用多线程压缩能力 | `ON` |
| `ZSTD_LEGACY_SUPPORT` | `ON` | 解码早期 zstd 格式 | `OFF` |
| `ZSTD_USE_STATIC_RUNTIME` | MSVC 为 `OFF` | 改用 `/MT`、`/MTd` | `OFF` |
| `ACTIVATE_MULTITHREADED_COMPILATION` | MSVC 为 `ON` | VS generator 使用 `/MP` | `ON` |

还应显式设置：

```text
BUILD_SHARED_LIBS=ON
BUILD_TESTING=OFF
```

虽然只启用 shared 时 `libzstd` interface target 会自动指向 shared，显式设置 `BUILD_SHARED_LIBS=ON` 可以消除歧义，并避免以后同时启用两种库时 target 指向变化。

### 5.1 compression 和 decompression

OpenSSL 证书压缩需要压缩和解压能力，因此二者都必须启用。不能为了缩小 DLL 而只构建 decoder。

### 5.2 dictionary builder

OpenSSL 当前证书压缩不要求字典训练 API，但 SQLiteBrowser 以后可能处理大量结构相似的小数据。保留 `ZSTD_BUILD_DICTBUILDER=ON` 可以提供：

```text
zdict.h
ZDICT_* API
```

它不会引入额外第三方库。第一版建议保留，后续若有明确的最小体积要求再测量是否关闭。

### 5.3 legacy support

上游默认启用早期 zstd v0.1 到 v0.7 格式解码代码。SQLiteBrowser v4.0.0 是新构建基线，OpenSSL 证书压缩也不需要这些早期实验格式。

建议显式设置：

```text
ZSTD_LEGACY_SUPPORT=OFF
```

优点是减少 DLL 体积和旧格式解析代码。只有在产品需求明确要求读取 zstd 0.8 之前生成的数据时才应重新开启。

### 5.4 多线程支持

Windows 下 `ZSTD_MULTITHREAD_SUPPORT` 默认开启。它不需要 pthread；上游只在 Unix 上查找 `Threads`。

建议保持开启，原因是：

- 不引入新的 Windows 第三方依赖；
- 保留大数据压缩扩展能力；
- 不改变公开 zstd 格式；
- 避免以后因重新开启而产生另一套 DLL 构建变体。

调用方是否实际使用多个 worker 仍由运行时参数决定。

## 6. libzstd target 和源码组成

### 6.1 target

上游可能创建：

| target | 类型 | Windows 输出 |
|---|---|---|
| `libzstd_shared` | `SHARED` | 默认 `zstd.dll` + `zstd.lib` |
| `libzstd_static` | `STATIC` | MSVC 下 `zstd_static.lib` |
| `libzstd` | `INTERFACE` | 指向选定的 shared/static target |

本项目正式构建只需要：

```text
libzstd_shared
libzstd -> libzstd_shared
```

`zstd.lib` 或以后统一命名得到的 `libzstd.lib` 是 DLL import library，不是静态 zstd。

### 6.2 源码集合

上游通过 `file(GLOB ...)` 收集：

```text
lib/common/*.c
lib/compress/*.c
lib/decompress/*.c
lib/dictBuilder/*.c
```

如果 legacy 打开，还会显式加入 `lib/legacy` 下的 v0.1 到 v0.7 实现。

项目包装层不应复制这些列表。上游使用的 glob 没有 `CONFIGURE_DEPENDS`，所以切换 zstd tag 或改变源码集合后必须重新 configure；推荐升级 tag 时使用全新的 work 目录。

### 6.3 MSVC 汇编策略

在 MSVC 下，上游主动定义：

```text
ZSTD_DISABLE_ASM
```

因此不会编译 `huf_decompress_amd64.S`。这是 zstd v1.5.7 CMake 对 MSVC 的既有策略，不建议项目层强行开启 GNU 风格汇编。

影响主要是可能失去部分平台优化，不影响格式、ABI 和基本功能。性能是否满足要求应在实现后以 Release x64 benchmark 判断，而不是修改上游宏猜测。

### 6.4 MSVC 专用定义

共享库 target 在 MSVC 下增加：

```text
ZSTD_DLL_EXPORT=1
ZSTD_HEAPMODE=0
_CONSOLE
_CRT_SECURE_NO_WARNINGS
```

并在启用多线程时增加：

```text
ZSTD_MULTITHREAD
```

`ZSTD_DLL_EXPORT=1` 负责导出公开 API，不需要开启 `WINDOWS_EXPORT_ALL_SYMBOLS`。

`ZSTD_HEAPMODE=0` 使便捷函数 `ZSTD_decompress()` 在栈上创建 decompression context；显式 context API 不受影响。这是上游 MSVC CMake 的默认选择。第一版应保持上游行为，但共享库 smoke test 应覆盖 `ZSTD_decompress()`，后续应用测试也要注意自定义小线程栈场景。

## 7. Debug、Release 和 CRT

### 7.1 CRT

本项目统一约定：

| 配置 | CRT | 目标用途 |
|---|---|---|
| Debug | `/MDd` | 本地调试，不进入正式安装包 |
| Release | `/MD` | 正式构建和安装包 |

上游的 `ZSTD_USE_STATIC_RUNTIME=OFF` 表示不把 `/MD` 改写为 `/MT`，但项目包装层仍应使用现代 CMake 明确设置：

```cmake
set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
)
```

该变量必须在创建上游 targets 前设置。

### 7.2 Visual Studio 多配置 Debug 限制

上游 `AddZstdCompilationFlags.cmake` 使用：

```cmake
if(CMAKE_BUILD_TYPE MATCHES "Debug")
    ... DEBUGLEVEL=1 ...
endif()
```

Visual Studio generator 是多配置生成器，通常使用 `CMAKE_CONFIGURATION_TYPES`，`CMAKE_BUILD_TYPE` 为空。因此 VS2022 的 Debug 配置不会自动得到上游预期的 `DEBUGLEVEL=1`。

这不影响 `/MDd`、PDB 或编译优化配置，但 zstd 内部 Debug 断言和诊断仍保持默认 `DEBUGLEVEL=0`。

后续包装层有两个选择：

1. 保持上游行为，只把 Debug 定义为 CRT/优化层面的 Debug；
2. 对 `libzstd_shared` 增加配置相关定义：

   ```cmake
   target_compile_definitions(libzstd_shared PRIVATE
       "$<$<CONFIG:Debug>:DEBUGLEVEL=1>"
   )
   ```

推荐采用第二种，但必须在构建后确认没有引入新的断言失败或 ABI 差异。`DEBUGLEVEL` 只控制内部诊断，不应进入公共 ABI。

### 7.3 文件名和 Debug 后缀

上游 CMake没有设置 Debug postfix，所以 Debug 和 Release 默认都叫：

```text
zstd.dll
zstd.lib
```

只要两个配置使用独立 stage，相同名称不会冲突。

## 8. Windows DLL 命名分析

### 8.1 上游存在两种命名

zstd v1.5.7 的不同 Windows 构建入口存在命名差异：

| 构建入口 | DLL | import library |
|---|---|---|
| CMake `libzstd_shared` | `zstd.dll` | `zstd.lib` |
| VS2010 `libzstd-dll` project | `libzstd.dll` | `libzstd.lib` |

更重要的是，CMake 给 DLL 加入的 Windows resource 固定记录：

```text
InternalName:     libzstd.dll
OriginalFilename: libzstd.dll
```

如果保留 CMake 默认的 `zstd.dll`，实际文件名会与其版本资源不一致。

### 8.2 OpenSSL 3.5.7 动态加载名

OpenSSL 3.5.7 在 Windows 的 `enable-zstd-dynamic` 实现中固定加载：

```text
LIBZSTD
```

最终对应 `LIBZSTD.dll`。Windows 文件名不区分大小写，因此它与 `libzstd.dll` 匹配，但与 `zstd.dll` 不匹配。

虽然 OpenSSL 文档提到 `--with-zstd-lib`，当前 `c_zstd.c` 的动态加载代码仍在 Windows 分支中直接定义 `LIBZSTD`。为了避免依赖文档与实现之间的差异，不应把正式方案建立在“用参数把动态加载名改成 zstd”这一假设上。

### 8.3 推荐决策

后续项目包装层建议把共享 target 设置为：

```cmake
set_target_properties(libzstd_shared PROPERTIES
    OUTPUT_NAME "libzstd"
    DEBUG_POSTFIX ""
)
```

最终统一为：

```text
Debug:   libzstd.dll + libzstd.lib
Release: libzstd.dll + libzstd.lib
```

这项重命名：

- 与 zstd 自带 Windows resource 一致；
- 与上游 Visual Studio DLL project 一致；
- 与 OpenSSL 3.5.7 默认动态加载名一致；
- 避免给 OpenSSL 打补丁；
- 不改变 DLL 导出 ABI。

## 9. CLI 和额外压缩格式

### 9.1 zstd.exe

`ZSTD_BUILD_PROGRAMS=ON` 会构建并安装 `zstd.exe`。默认情况下 CLI 链接静态库；如果设置 `ZSTD_PROGRAMS_LINK_SHARED=ON`，才链接共享库。

SQLiteBrowser 和 OpenSSL 运行时不需要 zstd CLI，因此正式依赖构建应关闭：

```text
ZSTD_BUILD_PROGRAMS=OFF
```

这也排除 CLI 专用的 benchmark、文件操作代码和安装内容。

### 9.2 zlib、lzma 和 lz4 支持

以下选项只扩展 `zstd.exe` 对其他文件格式的处理：

```text
ZSTD_ZLIB_SUPPORT
ZSTD_LZMA_SUPPORT
ZSTD_LZ4_SUPPORT
```

它们不用于 libzstd 的核心压缩 API。本项目不构建 CLI，因此不应启用这些选项，也不应因此给 zstd 新增 zlib、lzma 或 lz4 依赖。

### 9.3 contrib

`ZSTD_BUILD_CONTRIB=ON` 会进入：

```text
pzstd
gen_html
```

它们不是 SQLiteBrowser 或 OpenSSL 的运行时依赖，正式构建应保持关闭。

## 10. 测试体系分析

### 10.1 上游 CMake 测试强制依赖静态库

顶层 CMake 明确检查：

```text
ZSTD_BUILD_TESTS=ON
    -> ZSTD_BUILD_STATIC 必须为 ON
```

`build/cmake/tests/CMakeLists.txt` 中的 native test executables 全部链接：

```text
libzstd_static
```

因此即使同时构建 shared 和 static，上游 CMake 测试通过也只能直接证明静态 target 通过，不能证明 `libzstd.dll` 被加载和运行。

### 10.2 上游注册的测试

上游 CMake 注册：

| 测试 | 内容 | 备注 |
|---|---|---|
| `fullbench` | 性能及内部功能覆盖 | 链接静态库 |
| `fuzzer` | 随机压缩/解压完整性 | 可能运行较久 |
| `zstreamtest` | streaming API 测试 | 链接静态库 |
| `playTests` | shell 集成测试 | 需要 `sh`、`uname`、CLI 和 datagen |

在普通 VS2022 Developer Command Prompt 中，如果不存在 `sh` 或 `uname`，`playTests` 会被标记为 disabled。`paramgrill` 会被构建，但没有注册为 CTest。

### 10.3 推荐测试分层

正式共享库构建建议：

```text
ZSTD_BUILD_SHARED=ON
ZSTD_BUILD_STATIC=OFF
ZSTD_BUILD_TESTS=OFF
```

然后由项目包装层增加一个链接 `libzstd_shared` 的 Windows smoke test，至少覆盖：

1. `ZSTD_versionNumber()` 返回 `10507`；
2. `ZSTD_versionString()` 返回 `1.5.7`；
3. `ZSTD_compress()` 和 `ZSTD_decompress()` 往返；
4. `ZSTD_isError()` 和 `ZSTD_getErrorName()`；
5. streaming compression/decompression；
6. 测试进程实际从匹配配置加载 `libzstd.dll`。

这个 smoke test 才是正式 DLL 的直接验收依据。

如果以后要求运行上游 CMake 测试，应增加独立验证模式：

```text
build/zstd/x64-<config>/validation
```

验证模式可以开启 static 和上游测试，但：

- 不把 `zstd_static.lib` 安装到正式 stage；
- 不把它当成共享 DLL 的替代测试；
- 对 disabled 的 `playTests` 如实记录；
- 对长时间运行的 fuzzer 设置明确的 CI 时间预算；
- 报告中区分“上游静态测试”和“项目共享库 smoke test”。

## 11. install 和 CMake package

### 11.1 上游安装内容

shared-only 时，上游 install 规则可以安装：

```text
bin/zstd.dll
lib/zstd.lib
include/zstd.h
include/zdict.h
include/zstd_errors.h
lib/pkgconfig/libzstd.pc
lib/cmake/zstd/zstdConfig.cmake
lib/cmake/zstd/zstdConfigVersion.cmake
lib/cmake/zstd/zstdTargets*.cmake
```

应用项目级重命名后，前两项应变为：

```text
bin/libzstd.dll
lib/libzstd.lib
```

### 11.2 CMake targets

安装后的 package namespace 为：

```text
zstd::
```

shared-only stage 预期导出：

```text
zstd::libzstd_shared
zstd::libzstd
```

下游可以使用：

```cmake
find_package(zstd CONFIG REQUIRED)
target_link_libraries(target PRIVATE zstd::libzstd_shared)
```

同一个 CMake configure 过程中不要先 `add_subdirectory(zstd)`，再从其 install stage `find_package(zstd)`；重复定义相同 target 会冲突。统一编排层必须二选一：直接 target 消费，或已安装 package 消费。

### 11.3 PDB 和许可证

上游 install 规则没有显式安装 PDB。后续脚本如果需要符号归档，应单独验证并复制匹配配置的 PDB，不能假设 `cmake --install` 会自动包含。

上游 CMake也不会安装 `LICENSE` 或 `COPYING`。最终二进制发行物应至少保留所选择 BSD 许可要求的版权和许可文本。stage 是否包含 `share/licenses/zstd` 可以在实现阶段统一决定，但最终安装器不能遗漏第三方许可材料。

## 12. 推荐项目包装策略

未来 `third_party/zstd/CMakeLists.txt` 建议承担以下职责：

1. 限制 Windows；
2. 限制 MSVC 和 VS2022 工具链范围；
3. 限制 x64；
4. 检查 Windows SDK `10.0.22621.0`；
5. 检查 submodule 的 CMake 入口和 `lib/zstd.h`；
6. 只保留 Debug 和 Release；
7. 固定 `/MDd` 和 `/MD`；
8. 固定所有上游构建选项；
9. `add_subdirectory(src/build/cmake)`；
10. 把共享库命名为 `libzstd.dll`；
11. 增加共享 DLL smoke test；
12. 提供 install/stage 和后续 manifest 所需的稳定参数。

它不应：

- 修改 `third_party/zstd/src`；
- 复制上游源码列表；
- 构建 `zstd.exe`；
- 构建 pzstd、gen_html 或其他 contrib；
- 把静态库安装进正式 stage；
- 使用 FetchContent 再下载一份 zstd；
- 自动修改 OpenSSL；
- 把 stage 直接复制到最终 SQLiteBrowser 安装目录。

建议在进入上游目录前固定：

```cmake
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)

set(ZSTD_BUILD_SHARED ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_STATIC OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_COMPRESSION ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_DECOMPRESSION ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_DICTBUILDER ON CACHE BOOL "" FORCE)
set(ZSTD_BUILD_DEPRECATED OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_PROGRAMS_LINK_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT ON CACHE BOOL "" FORCE)
set(ZSTD_LEGACY_SUPPORT OFF CACHE BOOL "" FORCE)
set(ZSTD_USE_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)
```

## 13. 推荐 work 和 stage 目录

与 OpenSSL、SQLCipher、zlib 保持一致：

```text
build/
`- zstd/
   |- x64-debug/
   |  |- work/
   |  `- stage/
   `- x64-release/
      |- work/
      `- stage/
```

即使 Visual Studio 是多配置生成器，也建议 Debug 和 Release 使用独立 work 和 stage：

- 防止错误配置安装到另一配置；
- 方便验证 `/MDd` 和 `/MD`；
- 与 OpenSSL、SQLCipher、zlib 目录一致；
- 便于安全地清理单个依赖和配置；
- 方便生成配置独立 manifest；
- 两个配置可以使用相同 DLL 文件名。

推荐 stage 契约：

```text
stage/
|- bin/
|  `- libzstd.dll
|- include/
|  |- zstd.h
|  |- zdict.h
|  `- zstd_errors.h
|- lib/
|  |- libzstd.lib
|  |- cmake/
|  |  `- zstd/
|  |     |- zstdConfig.cmake
|  |     |- zstdConfigVersion.cmake
|  |     `- zstdTargets*.cmake
|  `- pkgconfig/
|     `- libzstd.pc
`- build-manifest.txt
```

PDB 和 license 的最终位置应在实现脚本前与其他依赖统一；不能在尚未决定时把它们声明成已经存在的必需文件。

## 14. 建议的构建流程

未来包装层存在后，命令形态建议为：

```cmd
cmake -S third_party\zstd ^
  -B build\zstd\x64-release\work ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -T v143 ^
  -DCMAKE_SYSTEM_VERSION=10.0.22621.0 ^
  -DCMAKE_INSTALL_PREFIX=build\zstd\x64-release\stage

cmake --build build\zstd\x64-release\work --config Release

ctest --test-dir build\zstd\x64-release\work ^
  -C Release --output-on-failure

cmake --install build\zstd\x64-release\work --config Release
```

Debug 使用独立的 `x64-debug/work` 和 `x64-debug/stage`，并把配置改为 `Debug`。

以上命令只是后续设计，本轮没有执行。正式脚本还应选择默认安装路径下实际存在的 VS2022 Enterprise、Professional 或 Community instance。三种 edition 使用相同的 VS17 generator、MSVC v143 和 SDK 约束，本项目不依赖商业版专有编译能力。

## 15. 构建后验证要求

### 15.1 来源验证

必须确认：

```text
exact tag: v1.5.7
HEAD:      f8745da6ff1ad1e7bab384bd1f9d742439278e99
submodule: clean
```

### 15.2 文件、架构和版本

每个配置至少验证：

```text
bin/libzstd.dll
lib/libzstd.lib
include/zstd.h
include/zdict.h
include/zstd_errors.h
build-manifest.txt
```

使用 `dumpbin /headers` 确认 x64，使用 Windows 文件版本或运行时 probe 确认 `1.5.7`。

### 15.3 CRT

使用 `dumpbin /dependents` 确认：

- Release 不依赖 Debug CRT；
- Debug 使用匹配的 Debug CRT；
- Debug DLL 不进入 Release stage；
- OpenSSL Debug/Release 以后只消费匹配配置的 zstd stage。

### 15.4 导出

使用 `dumpbin /exports` 检查基本 libzstd API。为了以后支持 OpenSSL 3.5.7 `enable-zstd-dynamic`，至少确认：

```text
ZSTD_createCStream
ZSTD_initCStream
ZSTD_freeCStream
ZSTD_compressStream2
ZSTD_flushStream
ZSTD_endStream
ZSTD_compress
ZSTD_createDStream
ZSTD_initDStream
ZSTD_freeDStream
ZSTD_decompressStream
ZSTD_decompress
ZSTD_isError
ZSTD_getErrorName
ZSTD_DStreamInSize
ZSTD_CStreamInSize
```

### 15.5 测试声明边界

只有项目共享库 smoke test 成功，才能报告“`libzstd.dll` 已通过运行验证”。

如果另行运行上游 CMake tests，应报告为“上游静态库测试通过”，不能把它等同于 DLL 测试。zstd 本体测试通过也不能表述为 OpenSSL zstd certificate compression 集成已经通过；后者需要 OpenSSL 自己的构建、测试和动态加载 probe。

## 16. build manifest 建议

zstd 上游 CMake 不生成本项目格式的 `build-manifest.txt`。后续自动化应在编译、共享库 smoke test、install 和产物验证全部成功后生成。

建议至少记录：

```text
zstd tag: v1.5.7
zstd commit: f8745da6ff1ad1e7bab384bd1f9d742439278e99
Configuration: Debug or Release
Architecture: x64
Visual Studio: <Enterprise|Professional|Community> 2022
MSVC tools: <version>
Windows SDK: 10.0.22621.0
CMake: 3.30.3
CRT: /MDd or /MD
Shared library: ON
Static library: OFF
Compression: ON
Decompression: ON
Dictionary builder: ON
Legacy support: OFF
Multithread support: ON
Project shared smoke test: passed / not run
Upstream static tests: passed / not run
Runtime version: 1.5.7
libzstd.dll SHA256: <hash>
libzstd.lib SHA256: <hash>
```

不能为来源不明、子模块脏、测试失败或手工复制的 DLL 补写正式 manifest。

## 17. 已识别风险

### 17.1 CMake 不是上游主要维护入口

Makefile 是上游主要构建系统，CMake 可能存在功能和测试差异。升级 zstd 时必须重新审计 CMake options、target、install 和测试规则。

### 17.2 错误使用源码根目录

v1.5.7 根目录没有 CMakeLists。必须使用 `src/build/cmake`，不能照搬较新开发分支从根目录配置的说明。

### 17.3 DLL 名称不匹配

上游 CMake 默认 `zstd.dll`，但 Windows resource 和 OpenSSL 默认使用 `libzstd.dll`。不统一名称会导致 OpenSSL 动态加载失败或文件元数据不一致。

### 17.4 把 import library 误认为静态库

关闭 `ZSTD_BUILD_STATIC` 后仍会生成 `libzstd.lib`。这是 DLL import library，不表示静态 zstd 被启用。

### 17.5 上游 CTest 不验证共享 DLL

上游 CMake tests 全部依赖 `libzstd_static`。只运行上游 CTest 无法证明正式 DLL 可用，必须增加项目共享库 smoke test。

### 17.6 Debug 宏在 VS 多配置下不生效

上游使用 `CMAKE_BUILD_TYPE` 判断 Debug，而 VS2022 是多配置生成器。若项目需要 `DEBUGLEVEL=1`，包装层必须用 generator expression 明确增加。

### 17.7 MSVC 汇编被关闭

上游 CMake 在 MSVC 下定义 `ZSTD_DISABLE_ASM`。强行打开汇编会偏离已验证路径；应先接受上游实现并测量性能。

### 17.8 `ZSTD_HEAPMODE=0` 的栈使用

上游 MSVC target 让 `ZSTD_decompress()` 在栈上创建 context。普通 Windows 线程通常可以工作，但自定义小线程栈需要测试。显式 context API 不受影响。

### 17.9 `clean-all` 不适用于 Windows

上游 `clean-all` target 执行 `rm -rf`。本项目脚本不应调用它，应使用经过绝对路径边界检查的配置级清理逻辑。

### 17.10 PDB 和 license 不会自动进入 stage

上游 install 没有完整处理 Windows PDB 和第三方许可材料。后续脚本和安装器必须明确处理，不能假设 `cmake --install` 已覆盖。

### 17.11 package target 重复定义

同一 configure 中混用 `add_subdirectory` 和已安装的 `find_package(zstd)` 可能重复定义 `zstd::` targets。统一编排层应固定一种消费方式。

### 17.12 glob 需要重新 configure

上游源文件通过没有 `CONFIGURE_DEPENDS` 的 glob 收集。切换 tag 后复用旧 work 可能遗漏源文件变化，因此版本升级必须使用干净 work。

## 18. 后续实施顺序

推荐后续按以下顺序进行，每一步独立验证：

1. 新增 `third_party/zstd/CMakeLists.txt` 项目包装层；
2. 固定 Windows x64、VS2022、SDK、shared 和 CRT；
3. 命名为 `libzstd.dll`，关闭 static、CLI、contrib 和 legacy；
4. 增加链接共享 target 的项目 smoke test；
5. 从空 work 分别配置 Debug 和 Release；
6. 编译、运行 smoke test、install；
7. 验证 tag、架构、CRT、版本、导出和 stage；
8. 生成 `build-manifest.txt`；
9. 新增统一 `build.cmd`；
10. 新增 Codex 和 Claude 兼容 skill；
11. 最后再修改 OpenSSL 自动化以消费匹配配置的 zstd stage。

不要在同一次未验证的变更中同时加入 zstd wrapper、重写 OpenSSL、修改 SQLCipher 和修改最终安装器。先让 zstd 自身形成稳定的 shared build 和 stage 契约，再接入 OpenSSL，便于定位 DLL 加载、CRT 或测试问题。

## 19. 最终建议

`third_party/zstd/CMakeLists.txt` 的最佳定位是项目级 policy wrapper，而不是重新实现 libzstd。

第一版建议采用：

```text
Windows x64 only
VS2022 / MSVC v143
SDK 10.0.22621.0
CMake entry: src/build/cmake
shared ON
static OFF
compression ON
decompression ON
dictionary builder ON
deprecated OFF
legacy OFF
multithread ON
CLI OFF
contrib OFF
DLL name libzstd.dll
Debug postfix empty
Debug /MDd
Release /MD
configuration-specific work and stage
project-owned shared-library smoke test
optional separate upstream static-test validation
```

这种方式最大限度复用上游 CMake，同时解决 zstd v1.5.7 在 VS2022 多配置、共享库测试、DLL 命名、OpenSSL 动态加载和项目 stage 规范之间的差异。
