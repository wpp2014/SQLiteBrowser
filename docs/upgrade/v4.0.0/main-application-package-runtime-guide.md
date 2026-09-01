# 主程序 Package Runtime 说明

> 适用分支：`upgrade/v4.0.0`
>
> 平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
>
> 状态：统一输出重构阶段 8 已完成

## 1. 阶段 8 结果

主程序现在明确区分两类输出。

Development output：

```text
output/x64-shared-debug/bin
output/x64-shared-release/bin
```

该目录供开发和链接使用，包含应用 EXE/PDB、依赖 DLL、import LIB、linker PDB、zlib、zstd、Qt runtime 和插件，可以直接运行应用。

Package runtime：

```text
output/x64-shared-debug/package/runtime
output/x64-shared-release/package/runtime
```

该目录只包含应用实际运行闭包，不含 `.lib`、PDB、zlib、zstd、单元测试、runtime-smoke tool、`openssl.exe`、`sqlcipher.exe` 或 `vc143.pdb`。它是后续 ZIP、WiX/NSIS 安装器的唯一允许输入，不得再整目录复制 development `bin`。

Package manifest 位于：

```text
output/x64-shared-<config>/package/metadata/runtime-manifest.txt
```

manifest 记录配置、架构、严格 allowlist 策略以及每个 package runtime 文件的 SHA-256。

## 2. 正式命令

仅配置并组装严格 package runtime：

```cmd
cmake --workflow --preset package-debug
cmake --workflow --preset package-release
```

如果已经执行过对应的 configure preset，也可以只调用 build preset：

```cmd
cmake --build --preset package-runtime-debug
cmake --build --preset package-runtime-release
```

组装并执行受限 `PATH` runtime smoke：

```cmd
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
```

这些 target 都是非默认 target。普通命令仍只构建 development output：

```cmd
cmake --build --preset debug
cmake --build --preset release
```

## 3. 组装和校验顺序

`sqlitebrowser_package_runtime` target 固定执行：

1. 构建 `sqlitebrowser`，由 `POST_BUILD` 更新 development `bin`；
2. 按 DEVELOPMENT 文件契约校验 development `bin`，缺失或多出文件都会失败；
3. 从 development `bin` 逐项复制 PACKAGE allowlist，不能使用目录整体复制；
4. 在 `build/package-runtime/next` 校验临时 package runtime；
5. 只替换当前配置的 `package/runtime`；
6. 写入 SHA-256 manifest；
7. 再次严格校验正式 package runtime。

脚本会检查 package runtime 和 manifest 必须分别位于当前配置根的固定路径，避免清理或发布到错误目录。

## 4. Package allowlist

两套配置都包含：

- `DB Browser for SQLCipher.exe`；
- SQLCipher、OpenSSL Crypto/SSL 和三个 Brotli DLL；
- Qt Core、Core5Compat、Gui、Network、Pdf、PrintSupport、Svg、Widgets、Xml DLL；
- `D3Dcompiler_47.dll`、`dxcompiler.dll`、`dxil.dll`、`opengl32sw.dll`；
- windeployqt 选择的 generic、iconengines、imageformats、networkinformation、platforms、styles 和 TLS plugins；
- Qt 翻译文件。

Release 额外包含 `vc_redist.x64.exe`。Debug 不复制 compiler runtime；Debug package runtime 只用于安装了匹配开发工具链的测试机器，不能作为正式发布包。

严格校验同时要求：

- Debug 和 Release Qt 文件不能混用；
- 所有 allowlist 文件存在且非空；
- 目录中不能出现任何 allowlist 之外的文件；
- `.lib`、PDB、zlib、zstd、CLI 和测试程序不能进入 package runtime。

## 5. Runtime smoke

`sqlitebrowser_runtime_smoke` 不再针对 development `bin`，而是依赖 `sqlitebrowser_package_runtime` 并针对严格目录运行。测试工具位于：

```text
output/x64-shared-<config>/build/tests/runtime-smoke
```

测试工具不会进入 development `bin` 或 package runtime。workflow 在仅保留 package runtime 的 `PATH` 和 `QT_PLUGIN_PATH` 下执行：

- 主程序 `--quit` 启动；
- SQLCipher 数据库创建、加密和读取；
- OpenSSL Brotli 压缩接口；
- Qt OpenSSL HTTPS，请求时验证运行版本为 OpenSSL 3.5.7。

TLS 项属于网络 smoke，离线环境失败时应单独报告，不能描述为普通产品编译失败。

## 6. 2026-08-31 验证结果

已在现有 Debug/Release 配置上完成：

- CMake 脚本模式解析和全部 Preset 解析；
- Debug development 严格校验：89 个文件；
- Release development 严格校验：90 个文件；
- Debug package runtime：70 个文件；
- Release package runtime：71 个文件；
- 两套 package runtime 均无 `.lib`、PDB、zlib、zstd 或依赖 CLI；
- Debug、Release 的应用启动、SQLCipher、Brotli 和 Qt OpenSSL HTTPS smoke 全部通过。

重新生成主程序时发现 MSVC 并行写入 `vc143.pdb` 会触发 `C1041`。主目标已增加仅限 MSVC 的 `/FS`，它只协调 compiler PDB 写入，不会把 `vc143.pdb` 部署到公共或 package 输出。

## 7. 当前边界

阶段 8 没有修改旧 WiX 安装器，也没有生成 ZIP/MSI/NSIS。`package/runtime` 是经过严格验证的运行时输入，不等于完整发布物。后续打包阶段还需要决定许可证布局、版本号、签名、归档格式和安装/卸载验证，但不得重新从 development `bin` 选取文件。
