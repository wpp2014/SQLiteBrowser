# 主程序统一输出构建说明

> 适用分支：`upgrade/v4.0.0`
>
> 平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
>
> 状态：统一输出重构阶段 6 已完成

## 1. 阶段 6 结果

主程序的 Debug 和 Release 构建树分别位于：

```text
output/x64-shared-debug/build/sqlitebrowser
output/x64-shared-release/build/sqlitebrowser
```

主程序产品及部署后的运行时位于：

```text
output/x64-shared-debug/bin
output/x64-shared-release/bin
```

普通 `cmake --build --preset` 只构建 `sqlitebrowser` target。内置 QScintilla、QCustomPlot 和 QHexEdit 是主程序实际链接依赖，会正常构建；四个单元测试和 runtime smoke tool 不属于普通产品 target。

四个单元测试通过独立 workflow 构建和运行：

```cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
```

workflow 生成的测试程序位于 `output/x64-shared-<config>/build/tests/unit`，不会复制到公共 `bin`。详细契约见 [main-application-unit-test-workflow-guide.md](main-application-unit-test-workflow-guide.md)。

## 2. 前置条件

首先按配置构建五个依赖并运行配置级汇总。例如全部配置：

```cmd
third_party\brotli\build.cmd build all
third_party\zlib\build.cmd build all
third_party\zstd\build.cmd build all
third_party\openssl\build.cmd build all
third_party\sqlcipher\build.cmd build all
third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
```

然后从模板生成本地 Preset，只修改 Qt 路径：

```cmd
copy /Y CMakePresets.template.json CMakePresets.json
```

不要修改配置根、OpenSSL stage 或 SQLCipher stage。CMake 配置会检查两个 aggregate manifest 是否存在，并拒绝旧 `build/x64-shared-*` binary directory、错误配置 stage 或非 SDK `10.0.26100.0` 的依赖。

## 3. 构建命令

Debug：

```cmd
cmake --preset debug
cmake --build --preset debug
```

Release：

```cmd
cmake --preset release
cmake --build --preset release
```

构建结束后可以直接运行：

```cmd
"output\x64-shared-debug\bin\DB Browser for SQLCipher.exe"
"output\x64-shared-release\bin\DB Browser for SQLCipher.exe"
```

不需要把 Qt、OpenSSL 或 SQLCipher 安装目录加入全局 `PATH`。

## 4. 依赖消费和部署边界

主程序链接继续消费对应配置的私有标准 stage：

```text
output/x64-shared-<config>/build/openssl/stage
output/x64-shared-<config>/build/sqlcipher/stage
```

这样可以复用 OpenSSL Config package 的标准 `bin/lib/include` 布局和 SQLCipher build manifest 校验。公共 `include/bin` 是配置级开发输出，不伪装成通用 CMake SDK。

POST_BUILD 会把 SQLCipher、OpenSSL、Brotli DLL 复制到公共 `bin`，然后运行 `windeployqt`。Debug 与 Release 分别部署匹配的 Qt runtime 和 plugin；Release 还包含 `vc_redist.x64.exe`。

阶段 5 ownership manifest 只拥有依赖汇总文件。应用、Qt runtime 和插件不加入该 manifest，因此重新执行 `third_party\aggregate.cmd build all` 只刷新依赖文件，不删除主程序或 Qt 文件。

## 5. Development bin 校验

公共 `bin` 允许：

- 应用 EXE/PDB；
- 五项依赖的 DLL、import LIB 和 linker PDB；
- Qt runtime、plugins 和翻译；
- Release 的 VC redistributable。

公共 `bin` 仍禁止依赖 CLI、测试工具和 `vc143.pdb`。POST_BUILD 还会检查必需 Qt/SQLCipher/OpenSSL/Brotli 文件，以及 Debug/Release Qt runtime 不得混用。

该目录不是最终 ZIP/NSIS package runtime。阶段 8 已增加独立的严格运行时目录，后续打包不得整目录复制 development `bin`。

## 6. Package runtime

显式 workflow 会从已验证 development `bin` 按 allowlist 生成：

```text
output/x64-shared-debug/package/runtime
output/x64-shared-release/package/runtime
```

使用命令：

```cmd
cmake --workflow --preset package-debug
cmake --workflow --preset package-release
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
```

该目录不含 `.lib`、PDB、zlib、zstd、测试或 CLI，完整契约见 [main-application-package-runtime-guide.md](main-application-package-runtime-guide.md)。

## 7. 本次验证

2026-08-30 已完成：

- Debug/Release Preset 解析和 configure；
- Debug/Release `sqlitebrowser` 产品构建；
- 两套 POST_BUILD runtime 部署与校验；
- 两套应用在 `PATH` 仅含自身公共 `bin` 时执行 `--quit` 成功；
- 部署后重新执行依赖 `build all` 和 `check all`，应用 SHA-256 与 Qt runtime 均保持不变；
- 公共 `bin` 没有单元测试、runtime smoke 或依赖 CLI 可执行文件。

源码编译仍报告若干既有 MSVC 警告，包括忽略 `[[nodiscard]]` 返回值、窄化转换以及 `escapeIdentifier` 并非所有路径返回值；它们没有阻止阶段 6 构建，但应作为独立代码质量任务处理。
