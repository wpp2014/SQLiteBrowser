# Brotli v1.2.0 Windows x64 / VS2022 构建分析

> 分析版本：Brotli `v1.2.0`
>
> 上游提交：`028fb5a23661f123017c060daa546b55cf4bde29`
>
> 上游提交时间：`2025-10-27T06:07:48-07:00`
>
> 源码位置：`third_party/brotli/src`
>
> 主要入口：`third_party/brotli/src/CMakeLists.txt`
>
> 目标平台：Windows x64、Visual Studio 2022、Windows SDK `10.0.22621.0`

## 1. 本轮范围

本文基于以下文件分析 Brotli 原始构建方式，并整理后续项目级构建方案：

- `third_party/brotli/src/CMakeLists.txt`
- `third_party/brotli/src/README.md`
- `third_party/brotli/src/c/common/version.h`
- `third_party/brotli/src/c/include/brotli/*.h`
- `third_party/brotli/src/tests/*.cmake`
- `third_party/openssl/src/Configure`
- `third_party/openssl/src/Configurations/00-base-templates.conf`
- `third_party/openssl/src/crypto/comp/c_brotli.c`
- `third_party/openssl/src/INSTALL.md`

本轮只新增本文档，没有：

- 新增 `third_party/brotli/CMakeLists.txt`；
- 新增 smoke test；
- 新增 `build.cmd` 或 skill；
- 修改 `third_party/brotli/src`；
- 修改 OpenSSL 构建选项；
- 执行 CMake configure、编译、CTest 或 install。

## 2. 结论摘要

Brotli `v1.2.0` 已提供可复用的根目录 CMake 构建，项目不需要复制源码列表或重新实现 Brotli。

推荐后续采用：

```text
third_party/brotli/CMakeLists.txt
        |
        |- 检查 Windows / MSVC / VS2022 / x64 / SDK
        |- 固定 Debug、Release 和动态 CRT
        |- 固定 shared-only、关闭 CLI 和上游 CLI 测试
        |- 强制 BROTLI_BUNDLED_MODE=OFF
        |- add_subdirectory(src)
        |- 保持上游三个 DLL 名称
        |- 增加项目共享 DLL smoke test
        `- 提供配置隔离的 stage 契约
```

第一版正式依赖建议只构建三个共享库：

```text
brotlicommon.dll
brotlidec.dll
brotlienc.dll
```

不要把 Brotli 当成单一 DLL。依赖关系是：

```text
brotlienc.dll -----> brotlicommon.dll

brotlidec.dll -----> brotlicommon.dll
```

上游名称已经与 OpenSSL 3.5.7 的 Windows 静态链接和动态加载约定一致，因此不应添加 `lib` 前缀，也不应合并或重命名三个 DLL。

## 3. 源码版本和供应链边界

当前 submodule 必须固定为：

```text
Tag:    v1.2.0
Commit: 028fb5a23661f123017c060daa546b55cf4bde29
```

`v1.2.0` 是直接指向 commit 的 lightweight tag，不是带签名的 annotated tag。自动化不能只比较人类可读 tag，应同时验证：

```cmd
git -C third_party\brotli\src rev-parse HEAD
git -C third_party\brotli\src describe --tags --exact-match
git -C third_party\brotli\src status --porcelain=v1 --untracked-files=all
```

只有 commit、tag 和干净状态全部匹配才能构建。

Brotli `v1.2.0` 没有嵌套 submodule，但项目仍应统一使用：

```cmd
git submodule update --init --recursive
```

源码使用 MIT License，许可证文件位于：

```text
third_party/brotli/src/LICENSE
```

上游 CMake 不会把该文件安装到 stage。正式发行物后续应增加项目级许可安装规则。

## 4. README 描述的原始构建入口

README 同时提到 vcpkg、Bazel、CMake 和 Python 构建方式。当前项目只需要 C/CMake 库构建，不需要 Python 模块、Java、Kotlin、Bazel 或 vcpkg。

README 给出的 CMake 基本流程是：

```text
mkdir out
cd out
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=./installed ..
cmake --build . --config Release --target install
```

这段命令主要面向单配置生成器。Visual Studio 是多配置生成器，应使用 `--config Debug` 或 `--config Release`，不能依赖 `CMAKE_BUILD_TYPE` 区分配置。

与 zstd `v1.5.7` 不同，Brotli 源码根目录本身就是 CMake 入口：

```text
third_party/brotli/src/CMakeLists.txt
```

上游最低 CMake 版本是 `3.15`。本项目后续包装层建议使用 `3.22` 或更高，以便固定 MSVC runtime 并使用 CTest 的 `ENVIRONMENT_MODIFICATION` 为共享 DLL 测试设置运行路径。当前已安装 CMake `3.30.3` 满足要求。

## 5. 上游 CMake 选项

### 5.1 BUILD_SHARED_LIBS

上游定义：

```cmake
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
```

它控制未显式指定类型的三个主 target 是 `SHARED` 还是 `STATIC`：

```text
brotlicommon
brotlidec
brotlienc
```

本项目正式构建应固定：

```text
BUILD_SHARED_LIBS=ON
```

### 5.2 BROTLI_BUILD_FOR_PACKAGE

上游默认：

```text
BROTLI_BUILD_FOR_PACKAGE=OFF
```

当它和 `BUILD_SHARED_LIBS=ON` 同时开启时，上游会额外创建：

```text
brotlicommon-static
brotlidec-static
brotlienc-static
```

正式 stage 只交付共享库，因此必须固定：

```text
BROTLI_BUILD_FOR_PACKAGE=OFF
```

不能仅凭 stage 中存在 `.lib` 判断静态库被启用。Windows shared build 也会生成三个 `.lib`，它们是 DLL import library。

### 5.3 BROTLI_BUILD_TOOLS

上游默认：

```text
BROTLI_BUILD_TOOLS=ON
```

开启后创建 `brotli` CLI，并把它安装到 `bin`。SQLiteBrowser 和 OpenSSL 运行时不需要 Brotli CLI，因此正式依赖构建应固定：

```text
BROTLI_BUILD_TOOLS=OFF
```

### 5.4 BROTLI_DISABLE_TESTS

上游没有通过 `option()` 声明该变量，但会直接判断：

```text
NOT BROTLI_DISABLE_TESTS AND BROTLI_BUILD_TOOLS
```

因此正式包装层应显式固定：

```text
BROTLI_DISABLE_TESTS=ON
```

这可以避免未来缓存或外部父项目意外重新开启 CLI 测试。

### 5.5 BROTLI_BUNDLED_MODE

这是 Brotli 嵌入本项目时最容易遗漏的选项。

上游行为是：

- Brotli 作为顶层项目配置时，默认 `OFF`；
- Brotli 通过 `add_subdirectory()` 作为子目录时，默认 `ON`。

当它为 `ON` 时，上游不会安装核心 library target、头文件和 pkg-config 文件。项目包装层如果直接执行：

```cmake
add_subdirectory(src)
```

但没有提前设置该变量，后续 `cmake --install` 将缺少正式交付产物。

因此包装层必须在 `add_subdirectory()` 前固定：

```text
BROTLI_BUNDLED_MODE=OFF
```

## 6. 上游 target 和源码组织

上游使用 `file(GLOB_RECURSE)` 收集三组源码：

```text
c/common/*.c -> brotlicommon
c/dec/*.c    -> brotlidec
c/enc/*.c    -> brotlienc
```

依赖关系由 CMake 明确声明：

```cmake
target_link_libraries(brotlidec brotlicommon)
target_link_libraries(brotlienc brotlicommon)
```

公共头文件目录是：

```text
third_party/brotli/src/c/include
```

正式安装的头文件位于：

```text
include/brotli/decode.h
include/brotli/encode.h
include/brotli/port.h
include/brotli/shared_dictionary.h
include/brotli/types.h
```

上游使用 GLOB，但没有 `CONFIGURE_DEPENDS`。固定 submodule 构建没有直接问题；升级 tag 后应从空 work 目录重新 configure，避免旧 CMake 文件列表残留。

## 7. Windows DLL 导出方式

上游不依赖 `.def` 文件或 `WINDOWS_EXPORT_ALL_SYMBOLS`，而是通过编译宏控制 `__declspec(dllexport)` 和 `__declspec(dllimport)`。

共享构建时，所有三个 target 都公开：

```text
BROTLI_SHARED_COMPILATION
```

同时，CMake 使用 `DEFINE_SYMBOL` 分别给正在编译的 DLL 添加：

```text
BROTLICOMMON_SHARED_COMPILATION
BROTLIDEC_SHARED_COMPILATION
BROTLIENC_SHARED_COMPILATION
```

`port.h` 根据这些宏选择导出或导入：

```text
BROTLI_COMMON_API
BROTLI_DEC_API
BROTLI_ENC_API
```

因此后续包装层不应开启 `WINDOWS_EXPORT_ALL_SYMBOLS`，也不需要维护额外 `.def` 文件。

上游没有 Windows `.rc` 版本资源。与 zlib、zstd 不同，Brotli DLL 的版本验证不能依赖 Explorer/FileVersion，必须调用：

```text
BrotliEncoderVersion()
BrotliDecoderVersion()
```

`v1.2.0` 的版本编码是：

```text
(1 << 24) | (2 << 12) | 0 = 0x01002000
```

## 8. DLL 和 import library 命名

Visual Studio shared build 预期生成：

```text
bin/brotlicommon.dll
bin/brotlidec.dll
bin/brotlienc.dll

lib/brotlicommon.lib
lib/brotlidec.lib
lib/brotlienc.lib
```

上游没有默认 Debug postfix，因此 Debug 和 Release 名称相同。配置必须通过独立 work/stage 隔离：

```text
build/brotli/x64-debug
build/brotli/x64-release
```

包装层可以显式把三个 target 的 `DEBUG_POSTFIX` 固定为空字符串，防止外部父项目或未来上游缓存改变命名。

不要重命名为：

```text
libbrotlicommon.dll
libbrotlidec.dll
libbrotlienc.dll
```

OpenSSL Windows 契约使用不带 `lib` 前缀的名称，上游默认名称已经正确。

## 9. Debug、Release 和 MSVC CRT

上游 CMake 没有自己固定 MSVC runtime。若不由项目包装层控制，CRT 会受 CMake policy、生成器默认值和外部缓存影响。

本项目应在 `add_subdirectory(src)` 前固定：

```cmake
set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "Use the matching dynamic MSVC runtime" FORCE
)
```

目标组合：

| 配置 | CRT | Stage |
|---|---|---|
| Debug | `/MDd` | `build/brotli/x64-debug/stage` |
| Release | `/MD` | `build/brotli/x64-release/stage` |

必须对三个 DLL 分别检查 CRT，不能只检查 encoder 或 decoder，因为 common 承载共享实现并被另外两个 DLL 动态依赖。

### 9.1 PDB 策略

Debug 的 CMake/MSVC 默认设置会使用 `/Zi` 和 `/DEBUG`，生成三个 DLL 对应的链接器 PDB。Release 默认只有 `/O2`，不会生成链接器 PDB。为了保留线上崩溃分析能力，同时维持 Release 优化，包装层对三个共享库的 Release 配置增加：

```text
/Zi
/DEBUG:FULL
/OPT:REF
/OPT:ICF
```

`/O2` 仍由 CMake 的 Release 默认配置保留；显式指定 `/OPT:REF` 和 `/OPT:ICF`，避免启用调试信息后改变链接优化策略。

每个 stage 只安装与 DLL 对应的链接器 PDB：

```text
brotlicommon.pdb
brotlidec.pdb
brotlienc.pdb
```

`vc143.pdb` 是编译阶段中间 PDB，只能保留在 `work`，不得部署到 stage。最终应用安装包可以不携带 PDB，但发布流程应归档与 DLL 同一次构建生成的 PDB，不能跨构建混用。

## 10. 上游 CLI 和测试

上游 CMake 测试全部围绕 `brotli` CLI：

```text
输入文件
  -> brotli CLI 压缩
  -> brotli CLI 解压
  -> SHA-512 比较
```

测试分为：

1. roundtrip：对固定输入使用 quality `1`、`6`、`9`、`11`；
2. compatibility：解压 `tests/testdata/*.compressed*` 并与参考数据比较。

当前 git submodule 含有 69 个 testdata 文件，正常源码 checkout 不需要额外下载测试数据。

但正式构建关闭 `BROTLI_BUILD_TOOLS` 后，上游不会注册任何 CTest。上游测试即使通过，主要证明 CLI roundtrip 和兼容性，也不能单独证明：

- 正式 stage 中三个 DLL 均可加载；
- Debug/Release CRT 匹配；
- import library 命名正确；
- OpenSSL 动态加载所需导出完整；
- `brotlienc.dll`、`brotlidec.dll` 能在运行时找到 `brotlicommon.dll`。

第一版建议：

```text
BROTLI_BUILD_TOOLS=OFF
BROTLI_DISABLE_TESTS=ON
project-owned shared DLL smoke test=ON
```

如果以后需要运行上游测试，应使用独立 validation work：

```text
BROTLI_BUILD_TOOLS=ON
BROTLI_DISABLE_TESTS=OFF
```

该模式不应改变或污染正式 stage，也不能替代项目共享 DLL smoke test。

## 11. install 行为

当 `BROTLI_BUNDLED_MODE=OFF` 时，上游安装：

- 三个 library target；
- `include/brotli` 公共头文件；
- 三个 pkg-config 文件。

pkg-config 文件是：

```text
lib/pkgconfig/libbrotlicommon.pc
lib/pkgconfig/libbrotlidec.pc
lib/pkgconfig/libbrotlienc.pc
```

上游不会生成：

```text
BrotliConfig.cmake
BrotliConfigVersion.cmake
BrotliTargets.cmake
```

因此安装后的 stage 不能直接假设支持 `find_package(Brotli CONFIG)`。当前 OpenSSL 集成只需要 include、DLL 和 import library，不要求新增 CMake package。

上游还会安装四个 man3 文件。该安装规则不受 `BROTLI_BUNDLED_MODE` 控制。Windows stage 中出现 `share/man/man3` 不表示 CLI 被启用，也不是错误。

上游不安装 `LICENSE`。项目包装层后续应增加：

```text
share/licenses/brotli/LICENSE
```

## 12. OpenSSL 3.5.7 集成契约

### 12.1 配置方式

OpenSSL 3.5.7 提供：

```text
enable-brotli
enable-brotli-dynamic
--with-brotli-include=<dir>
--with-brotli-lib=<dir>
```

`enable-brotli` 是构建期链接模式。在 Windows 上，OpenSSL 期望：

```text
brotlicommon.lib
brotlidec.lib
brotlienc.lib
```

`enable-brotli-dynamic` 不把 Brotli import library 链入 OpenSSL DLL，而是在真正使用 Brotli 时加载 DLL。OpenSSL 源码明确说明，这样可以避免所有 OpenSSL 使用者在进程启动时都必须提供 Brotli DLL。

本项目后续优先采用：

```text
enable-brotli-dynamic
--with-brotli-include=<matching Brotli stage>\include
```

动态模式编译期需要头文件；运行期需要三个 DLL。`--with-brotli-lib` 对 Windows 动态模式不是核心依赖，因为 OpenSSL 不链接 `.lib`，但 Brotli stage 仍应保留 import libraries，供 smoke test、其他消费者和非动态验证使用。

### 12.2 Windows 动态加载名称

OpenSSL Windows 代码固定加载：

```text
BROTLIENC.dll
BROTLIDEC.dll
```

Windows 文件名不区分大小写，因此分别匹配：

```text
brotlienc.dll
brotlidec.dll
```

OpenSSL 不直接 DSO-load `brotlicommon.dll`，但 encoder 和 decoder DLL 都依赖 common，Windows loader 必须能在同一目录或 `PATH` 中找到它。

因此三个 DLL 必须作为不可拆分的运行时集合部署。

### 12.3 OpenSSL 动态绑定的导出

OpenSSL 3.5.7 会绑定以下 encoder API：

```text
BrotliEncoderCreateInstance
BrotliEncoderCompressStream
BrotliEncoderHasMoreOutput
BrotliEncoderDestroyInstance
BrotliEncoderCompress
```

以及 decoder API：

```text
BrotliDecoderCreateInstance
BrotliDecoderDecompressStream
BrotliDecoderHasMoreOutput
BrotliDecoderDestroyInstance
BrotliDecoderGetErrorCode
BrotliDecoderErrorString
BrotliDecoderIsFinished
BrotliDecoderDecompress
```

这些 API 在 Brotli `v1.2.0` 中全部存在。后续 stage 验证应逐项检查，而不是只检查一个版本函数。

### 12.4 TLS 行为影响

OpenSSL 3.5.7 启用 Brotli 后会把它加入 TLS certificate compression，默认偏好顺序中 Brotli位于 zlib 和 zstd 之前。

这意味着 OpenSSL 集成完成后必须运行：

- Brotli BIO compression tests；
- certificate compression tests；
- 动态加载 probe；
- 缺失任一 Brotli DLL 时的可诊断失败测试。

Brotli 自身构建成功不能表述为“OpenSSL Brotli 集成通过”。

## 13. 推荐项目包装策略

未来 `third_party/brotli/CMakeLists.txt` 建议承担：

1. 限制 Windows；
2. 限制 MSVC 和 VS2022 工具链范围；
3. 限制 x64；
4. 验证 Windows SDK `10.0.22621.0`；
5. 验证 submodule 入口和公共头文件；
6. 只保留 Debug、Release；
7. 固定 Debug `/MDd`、Release `/MD`；
8. 固定 install 的 `bin`、`lib`、`include`；
9. 固定 shared-only；
10. 关闭 CLI 和上游 CLI tests；
11. 强制 `BROTLI_BUNDLED_MODE=OFF`；
12. `add_subdirectory(src)`；
13. 验证三个 target 都是 `SHARED_LIBRARY`；
14. 固定三个 target 的 Debug postfix 为空；
15. 增加项目共享 DLL smoke test；
16. 安装 MIT LICENSE；
17. 提供稳定 stage 和 manifest 契约。

它不应：

- 修改 `third_party/brotli/src`；
- 复制或手工维护 Brotli 源码列表；
- 使用 `FetchContent` 下载第二份 Brotli；
- 合并三个 DLL；
- 为 Windows 名称添加 `lib` 前缀；
- 构建 Python、Java、Kotlin 或其他语言绑定；
- 在 Brotli wrapper 中修改 OpenSSL；
- 安装到系统目录。

## 14. 推荐 CMake 策略草案

以下只是后续实现方向，不是本轮代码：

```cmake
cmake_minimum_required(VERSION 3.22)
project(sqlitebrowser_brotli VERSION 1.2.0 LANGUAGES C)

# Windows / MSVC / VS2022 / x64 / SDK checks

set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "Use the matching dynamic MSVC runtime" FORCE)

set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared Brotli libraries" FORCE)
set(BROTLI_BUILD_FOR_PACKAGE OFF CACHE BOOL "Disable static package targets" FORCE)
set(BROTLI_BUILD_TOOLS OFF CACHE BOOL "Disable Brotli CLI" FORCE)
set(BROTLI_DISABLE_TESTS ON CACHE BOOL "Disable upstream CLI tests" FORCE)
set(BROTLI_BUNDLED_MODE OFF CACHE BOOL "Enable upstream install rules" FORCE)

enable_testing()
add_subdirectory(src upstream)

# Verify brotlicommon, brotlidec and brotlienc are shared targets.
# Keep the upstream output names and add a project-owned DLL smoke test.
```

`BUILD_SHARED_LIBS` 是全局 CMake 变量。建议 Brotli wrapper 作为独立 configure 入口使用，不要在一个大型父项目中无条件覆盖其他依赖的 library type。

## 15. 项目共享 DLL smoke test

建议创建：

```text
third_party/brotli/tests/brotli_smoke.c
```

测试 target 同时链接：

```text
brotlienc
brotlidec
```

`brotlicommon` 由上游 target 依赖传递，但运行环境必须包含三个 DLL。

smoke test 至少覆盖：

1. `BrotliEncoderVersion()` 返回 `0x01002000`；
2. `BrotliDecoderVersion()` 返回 `0x01002000`；
3. `BrotliEncoderCompress()` one-shot 压缩；
4. `BrotliDecoderDecompress()` one-shot 解压；
5. roundtrip 字节完全一致；
6. `BrotliEncoderCreateInstance()` 和 streaming encode；
7. `BrotliDecoderCreateInstance()` 和 streaming decode；
8. decoder 错误码及 `BrotliDecoderErrorString()`；
9. 测试进程实际加载当前配置的三个 DLL。

CTest 需要把 Brotli DLL 输出目录临时加入 `PATH`，不能依赖开发机上可能存在的系统 Brotli。

## 16. 推荐目录和 stage

```text
build/brotli/
|- x64-debug/
|  |- work/
|  `- stage/
|     |- bin/
|     |  |- brotlicommon.dll
|     |  |- brotlicommon.pdb
|     |  |- brotlidec.dll
|     |  |- brotlidec.pdb
|     |  |- brotlienc.dll
|     |  `- brotlienc.pdb
|     |- include/
|     |  `- brotli/
|     |     |- decode.h
|     |     |- encode.h
|     |     |- port.h
|     |     |- shared_dictionary.h
|     |     `- types.h
|     |- lib/
|     |  |- brotlicommon.lib
|     |  |- brotlidec.lib
|     |  |- brotlienc.lib
|     |  `- pkgconfig/
|     |- share/
|     |  |- licenses/brotli/LICENSE
|     |  `- man/man3/
|     `- build-manifest.txt
`- x64-release/
   |- work/
   `- stage/
      `- ... same contract ...
```

Debug 和 Release 不得共享 stage。三个 DLL 名称相同，混合复制会造成 CRT 和二进制来源不可追踪。

## 17. 自动化命令与构建 skill

项目提供 `third_party/brotli/build.cmd`，命令接口与 zlib、zstd 保持一致：

```cmd
third_party\brotli\build.cmd all
third_party\brotli\build.cmd debug
third_party\brotli\build.cmd release
third_party\brotli\build.cmd check
third_party\brotli\build.cmd debug clean
third_party\brotli\build.cmd release clean
```

内部构建流程建议：

```text
source/toolchain check
  -> configure configuration-specific work
  -> build shared libraries and smoke executable
  -> run project shared DLL CTest
  -> clear exact configuration stage
  -> cmake --install
  -> write build-manifest.txt
  -> verify stage
```

建议的 CMake 命令形态：

```cmd
cmake -S third_party\brotli ^
  -B build\brotli\x64-release\work ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_SYSTEM_VERSION=10.0.22621.0 ^
  -DCMAKE_INSTALL_PREFIX=build\brotli\x64-release\stage

cmake --build build\brotli\x64-release\work --config Release --parallel

ctest --test-dir build\brotli\x64-release\work ^
  -C Release --output-on-failure

cmake --install build\brotli\x64-release\work --config Release
```

### 17.1 直接使用构建脚本

推荐先执行只读环境检查：

```cmd
third_party\brotli\build.cmd check
```

构建 Debug 和 Release，并分别执行共享 DLL smoke test、安装、manifest 生成和 stage 验证：

```cmd
third_party\brotli\build.cmd all
```

需要保证 work 与 stage 从空目录重建时，显式添加 `clean`：

```cmd
third_party\brotli\build.cmd all clean
```

`clean` 只删除所选配置对应的 `build\brotli\x64-<config>`。脚本不会修改 `third_party\brotli\src`，也不会安装到系统目录。

### 17.2 使用 Codex/Claude 构建 skill

项目同时提供以下入口：

```text
.agents/skills/sqlitebrowser-build-brotli/SKILL.md
.claude/skills/sqlitebrowser-build-brotli/SKILL.md
```

`.agents` 中的文件是唯一规范说明；`.claude` 文件是兼容入口，只负责引导 Claude Code 读取规范 skill。两者最终都调用同一个 `third_party\brotli\build.cmd`，不会维护两套构建逻辑。

在支持项目 skill 的 Codex 或 Claude Code 中，可直接提出：

```text
使用 $sqlitebrowser-build-brotli 检查 Brotli 构建环境。
使用 $sqlitebrowser-build-brotli 构建并验证 Debug 和 Release。
使用 $sqlitebrowser-build-brotli 从空目录重建 Release。
```

skill 根据意图分别选择 `check`、`all` 或 `release clean`。未明确要求清理时，不应自行添加 `clean`；仅请求分析或查看日志时，也不应运行构建或修改文件。

skill 的常规部署边界止于：

```text
build/brotli/x64-debug/stage
build/brotli/x64-release/stage
```

它不会自行修改 OpenSSL、SQLCipher、SQLiteBrowser 安装器或系统 PATH。OpenSSL Brotli 集成必须作为独立步骤构建和验证后，才能宣称 BIO 或 certificate compression 已启用。

## 18. Stage 验证建议

### 18.1 文件集合

必须存在：

```text
bin/brotlicommon.dll
bin/brotlicommon.pdb
bin/brotlidec.dll
bin/brotlidec.pdb
bin/brotlienc.dll
bin/brotlienc.pdb
lib/brotlicommon.lib
lib/brotlidec.lib
lib/brotlienc.lib
include/brotli/decode.h
include/brotli/encode.h
include/brotli/port.h
include/brotli/shared_dictionary.h
include/brotli/types.h
build-manifest.txt
```

不得存在：

```text
bin/brotli.exe
vc143.pdb
lib/brotlicommon-static.lib
lib/brotlidec-static.lib
lib/brotlienc-static.lib
```

### 18.2 架构

对三个 DLL 分别执行：

```cmd
dumpbin /headers <dll>
```

必须包含 x64 machine `8664`。

### 18.3 导出

对 encoder 和 decoder DLL 检查 OpenSSL 动态绑定所需的全部 API，并额外检查两个版本函数。

### 18.4 DLL 依赖

使用：

```cmd
dumpbin /dependents brotlienc.dll
dumpbin /dependents brotlidec.dll
```

两者都应依赖：

```text
brotlicommon.dll
```

三 DLL 不应依赖系统安装的另一份 Brotli，也不应引入 zlib、zstd、LZMA 或其他压缩库。

### 18.5 CRT

Debug 三 DLL 应依赖 Debug CRT；Release 三 DLL 不得依赖：

```text
VCRUNTIME140D.dll
VCRUNTIME140_1D.dll
ucrtbased.dll
```

### 18.6 版本

因为没有 Windows version resource，版本结论必须来自 smoke test 的 runtime API，不能只来自文件名、tag 或 CMake cache。

## 19. build-manifest.txt 建议

Brotli 上游不生成本项目格式的 manifest。自动化应在 smoke test、install 和所有产物验证成功后生成。

建议至少包含：

```text
Brotli tag: v1.2.0
Brotli commit: 028fb5a23661f123017c060daa546b55cf4bde29
Configuration: Debug / Release
Architecture: x64
Visual Studio: Enterprise / Professional / Community 2022
MSVC tools: <version>
Windows SDK: 10.0.22621.0
CMake: <version>
CRT: /MDd / /MD
Library type: shared
Libraries: brotlicommon; brotlidec; brotlienc
Linker PDBs: brotlicommon.pdb; brotlidec.pdb; brotlienc.pdb
PDB policy: linker PDBs staged; compiler PDBs excluded
Release symbol flags: /Zi /DEBUG:FULL /OPT:REF /OPT:ICF
CLI: disabled
Static libraries: disabled
Project shared smoke test: passed
Upstream CLI tests: not run
Runtime encoder version: 1.2.0
Runtime decoder version: 1.2.0
brotlicommon.dll SHA-256: <hash>
brotlicommon.pdb SHA-256: <hash>
brotlidec.dll SHA-256: <hash>
brotlidec.pdb SHA-256: <hash>
brotlienc.dll SHA-256: <hash>
brotlienc.pdb SHA-256: <hash>
brotlicommon.lib SHA-256: <hash>
brotlidec.lib SHA-256: <hash>
brotlienc.lib SHA-256: <hash>
```

## 20. 风险和易错点

### 20.1 误以为只有一个 Brotli DLL

Brotli 是 common、decoder、encoder 三库结构。只部署 encoder 和 decoder 会因缺少 common 导致 Windows loader 失败。

### 20.2 add_subdirectory 后 install 为空

作为子目录时 `BROTLI_BUNDLED_MODE` 默认 `ON`。如果没有显式改为 `OFF`，核心 target 和头文件不会安装。

### 20.3 开启 BROTLI_BUILD_FOR_PACKAGE

该选项会同时构建共享和静态变体，扩大 stage、测试和许可证审计范围。正式构建应保持关闭。

### 20.4 为 Windows DLL 添加 lib 前缀

OpenSSL 3.5.7 Windows 动态加载名称是 `BROTLIENC.dll` 和 `BROTLIDEC.dll`，静态链接名称也是 `brotli*.lib`。添加 `lib` 前缀会破坏默认契约。

### 20.5 只运行上游 CTest

上游测试依赖 CLI。它不能替代正式三 DLL 的运行验证。

### 20.6 使用 FileVersion 验证

上游没有 Windows `.rc` 版本资源。应调用 encoder/decoder version API。

### 20.7 Debug/Release stage 混用

两个配置文件名相同，混合复制无法从名称识别 CRT。必须使用配置隔离目录和 manifest。

### 20.8 把 raw Brotli 当作完整容器

README 明确说明 Brotli 是 stream format，不含 checksum 或未压缩长度。应用不能把 Brotli 本身当作完整性保护。TLS certificate compression 的完整性由 TLS 协议提供，但其他未来使用场景需要单独定义长度和完整性边界。

### 20.9 升级 tag 后复用旧 work

上游使用不带 `CONFIGURE_DEPENDS` 的 GLOB。版本升级后应清理对应 work 并重新 configure。

## 21. 推荐实施顺序

建议后续逐步实施，每一步独立验证：

1. 新增 `third_party/brotli/CMakeLists.txt`；
2. 固定 Windows x64、VS2022、SDK、shared 和 CRT；
3. 关闭 static package targets、CLI 和上游 CLI tests；
4. 设置 `BROTLI_BUNDLED_MODE=OFF`；
5. 保持三个上游 DLL 名称；
6. 新增共享 DLL smoke test；
7. 从空 work 分别构建、测试、install Debug 和 Release；
8. 验证三 DLL 的 tag、架构、CRT、版本、导出、依赖和 stage；
9. 生成 `build-manifest.txt`；
10. 新增统一 `build.cmd`；
11. 新增 Codex/Claude 构建 skill；
12. 最后单独修改 OpenSSL 自动化以消费匹配配置的 Brotli stage；
13. 运行 OpenSSL Brotli BIO、certificate compression 和动态加载验证。

不要在同一次未验证的变更中同时实现 Brotli wrapper、修改 OpenSSL、修改 SQLCipher 和修改最终安装器。先让 Brotli 自身形成稳定的三 DLL stage 契约，再接入 OpenSSL。

## 22. 最终建议

`third_party/brotli/CMakeLists.txt` 的最佳定位是项目级 policy wrapper，而不是重新实现 Brotli。

第一版建议固定：

```text
Windows x64 only
VS2022 / MSVC v143
SDK 10.0.22621.0
CMake entry: src
BUILD_SHARED_LIBS=ON
BROTLI_BUILD_FOR_PACKAGE=OFF
BROTLI_BUILD_TOOLS=OFF
BROTLI_DISABLE_TESTS=ON
BROTLI_BUNDLED_MODE=OFF
DLLs: brotlicommon.dll; brotlidec.dll; brotlienc.dll
Debug postfix: empty
Debug CRT: /MDd
Release CRT: /MD
Debug linker PDBs: enabled
Release linker PDBs: /Zi /DEBUG:FULL with /OPT:REF /OPT:ICF
Compiler PDB deployment: disabled
configuration-specific work and stage
project-owned shared-library smoke test
optional separate upstream CLI-test validation
```

该方案最大限度复用 Brotli `v1.2.0` 上游 CMake，同时解决 VS2022 多配置、三 DLL 运行时依赖、`BROTLI_BUNDLED_MODE` 安装行为、共享库测试、OpenSSL 3.5.7 动态加载和项目 stage 规范之间的差异。

## 23. 实施与验证结果

截至 2026-08-25，本章推荐顺序已完成实施。

### 23.1 Brotli 构建层

已增加以下项目文件：

```text
third_party/brotli/CMakeLists.txt
third_party/brotli/tests/brotli_smoke.c
third_party/brotli/build.cmd
.agents/skills/sqlitebrowser-build-brotli/SKILL.md
.claude/skills/sqlitebrowser-build-brotli/SKILL.md
```

`third_party\brotli\build.cmd all clean` 已从空 work 分别完成 Debug 和 Release 的 configure、build、CTest、install、二进制审计和 manifest 生成。实际环境为 Visual Studio 2022 Enterprise、MSVC tools `14.44.35207`、Windows SDK `10.0.22621.0` 和 CMake `3.30.3`。

两个配置的项目 smoke test 均通过，覆盖：

- encoder/decoder runtime version 为 `1.2.0`；
- one-shot round trip；
- streaming round trip；
- decoder 错误路径。

最终 stage 为：

```text
build/brotli/x64-debug/stage
build/brotli/x64-release/stage
```

二进制审计确认三个 DLL 均为 x64；Debug 使用 `/MDd`，Release 使用 `/MD`；`brotlidec.dll` 和 `brotlienc.dll` 依赖 `brotlicommon.dll`；所需导出存在；未引入 zlib、zstd 或 LZMA；stage 不包含静态 package 库和 Brotli CLI。三个 `.lib` 是对应共享 DLL 的 import library。两个 stage 都生成了 `build-manifest.txt`。

PDB 策略实施后再次执行 `third_party\brotli\build.cmd all`，Debug 和 Release 均重新 configure、build、通过 smoke test、install 并完成 stage 验证。两个 stage 都且仅包含 `brotlicommon.pdb`、`brotlidec.pdb` 和 `brotlienc.pdb`，不包含任何 `vc143.pdb`。三个 stage PDB 与各自 `work/upstream/<Config>` 下的链接器 PDB SHA-256 完全一致，DLL 的 RSDS 记录也指向对应名称。Release 生成的 VS 工程确认同时保留 `MaxSpeed` 优化、`ProgramDatabase`、`DebugFull`、`OptimizeReferences` 和 `EnableCOMDATFolding`。

### 23.2 OpenSSL 动态 Brotli 集成

OpenSSL 自动化已改为只消费匹配配置且通过 manifest 校验的 Brotli stage，并使用：

```text
enable-brotli-dynamic
--with-brotli-include=<matching Brotli stage>/include
```

`third_party\openssl\build.cmd all safe clean` 已完成 OpenSSL 3.5.7 Debug 和 Release 的干净重建。两个配置的安全测试均为：

```text
Files=343, Tests=4279, Result: PASS
```

Debug 用时 1595 秒，Release 用时 1359 秒。安全模式明确排除了本机可能因 IPv6 UDP 环境问题阻塞的 `test_bio_dgram`，因此该结果是“安全测试通过”，不是 OpenSSL 完整测试套件通过。

安全测试后又单独运行并通过：

```text
test_bio_comp
test_cert_comp
test_tls13certcomp
```

最终验证确认：

- `configdata.pm` 同时记录 `brotli` 和 `brotli-dynamic`；
- `libcrypto-3-x64.dll` 导出 `COMP_brotli`、`COMP_brotli_oneshot` 和 `BIO_f_brotli`；
- `libcrypto-3-x64.dll` 不直接导入 Brotli DLL，符合运行时动态加载设计；
- OpenSSL stage 中三枚 Brotli DLL 与对应 Brotli stage 逐字节一致；
- Debug/Release stage 均生成包含 Brotli tag、commit、匹配 stage、动态加载方式、专项测试状态和 DLL SHA-256 的 `build-manifest.txt`。

OpenSSL stage 为：

```text
build/openssl/x64-debug/stage
build/openssl/x64-release/stage
```

因此，当前实现已经形成可重复验证的两层契约：先由 Brotli 脚本产生配置隔离的三 DLL stage，再由 OpenSSL 脚本验证 provenance 和 CRT 后消费、测试并部署该 stage。SQLCipher 和最终安装器仍未在本次实施中修改。

PDB 策略变更后只重新构建了 Brotli，没有重新构建 OpenSSL。上面的 OpenSSL 结果是上一轮集成测试记录，不能视为当前新 Brotli DLL/PDB 组合与既有 OpenSSL stage 的再次身份验证；下一次执行 OpenSSL 构建时，脚本会重新消费当前匹配配置的 Brotli stage。
