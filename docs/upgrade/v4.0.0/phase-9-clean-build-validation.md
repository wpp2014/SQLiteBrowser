# 阶段 9：从空 output 完整构建与验证记录

> 文档性质：统一输出重构的干净构建验收记录
>
> 执行日期：2026-08-31
>
> 当前分支：`upgrade/v4.0.0`
>
> 结论：通过

## 1. 验证目的

阶段 9 从删除后的空 `output/` 开始，按依赖顺序重新生成 Debug 和 Release 的全部产品、测试与 package runtime，确认阶段 1 至阶段 8 的目录、最小构建、测试隔离、运行时白名单和 manifest 契约可以重复执行。

本阶段只验证当前构建系统，没有修改工程源码、构建脚本或依赖源码。验证使用本地且被 Git 忽略的 `CMakePresets.json`，其中 Qt 路径为 `E:/QT/6.11.1/msvc2022_64`；仓库中的模板没有写入该机器路径。

## 2. 验证环境

- Visual Studio 2022 Enterprise；
- MSVC `14.44.35207`；
- Windows SDK `10.0.26100.0`；
- CMake/CTest `3.30.3`；
- Qt `6.11.1`，MSVC 2022 x64；
- Perl `5.38.2`；
- NASM `2.16.03`；
- NSIS `3.12`；
- Brotli `v1.2.0`；
- zlib `v1.3.2`；
- zstd `v1.5.7`；
- OpenSSL `openssl-3.5.7`；
- SQLCipher `v4.18.0`，SQLite baseline `3.53.4`。

Visual Studio Community、Professional 和 Enterprise 继续由各脚本的默认安装路径探测逻辑支持；本次实测使用 Enterprise。

## 3. 执行顺序

从空目录恢复时必须先构建底层依赖，再构建上层消费者。阶段 9 使用以下顺序：

```cmd
third_party\brotli\build.cmd check all
third_party\zlib\build.cmd check all
third_party\zstd\build.cmd check all

third_party\brotli\build.cmd build all
third_party\zlib\build.cmd build all
third_party\zstd\build.cmd build all

third_party\brotli\build.cmd test all
third_party\zlib\build.cmd test all
third_party\zstd\build.cmd test all

third_party\openssl\build.cmd check all
third_party\openssl\build.cmd build all
third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release safe

third_party\sqlcipher\build.cmd check all
third_party\sqlcipher\build.cmd build all
third_party\sqlcipher\build.cmd test all

third_party\aggregate.cmd build all
third_party\aggregate.cmd check all

cmake --preset debug
cmake --build --preset debug
cmake --preset release
cmake --build --preset release

cmake --workflow --preset test-debug
cmake --workflow --preset test-release
cmake --workflow --preset package-debug
cmake --workflow --preset package-release
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
```

普通依赖 `build` 与测试命令保持分离。普通主程序 build preset 只构建 `sqlitebrowser`；单元测试、package runtime 和 runtime smoke 均通过单独的显式 workflow 运行。

## 4. 验证结果

### 4.1 底层压缩库

- Brotli Debug/Release 最小共享库构建成功，两个配置的 smoke 均为 `1/1` 通过；
- zlib Debug/Release 最小共享库构建成功，两个配置均为 `13/13` CTest 通过；
- zstd Debug/Release 最小共享库构建成功，两个配置的 smoke 均为 `1/1` 通过；
- 三个库的产品构建没有隐式执行测试，也没有把测试程序部署到 stage。

### 4.2 OpenSSL

- Debug/Release 的最小 Crypto/SSL 产品构建和 stage 校验成功；
- 两个配置均使用同配置 Brotli 动态库；
- Debug safe 基础集：`343 files / 4279 tests`，`1590` 秒，PASS；
- Release safe 基础集：`343 files / 4279 tests`，`1329` 秒，PASS；
- Debug/Release 的 Brotli BIO 与证书压缩聚焦集均为 `3 files / 11 tests`，`20` 秒，PASS。

`safe` 模式明确排除了 Windows 上曾发生 IPv6 地址冲突的 `test_bio_dgram`，因此以上结果不是 OpenSSL full test pass。首次测试会先生成大量 OpenSSL 测试可执行文件，长时间编译或某些测试短时间无输出均不等于卡死。

### 4.3 SQLCipher

- Debug/Release 最小 DLL、import LIB、linker PDB、公开头文件、许可证与 manifest 构建和 stage 校验成功；
- 两个配置的 provider smoke 均为 `1/1` 通过；
- staged-product provider 与 compile-options 探针通过；
- 测试 CLI 只生成在私有 `build` 目录，没有进入产品 stage 或公共 `bin`。

本次没有运行 SQLCipher Tcl suite，不能据此声明 Tcl 全套测试通过。

### 4.4 统一依赖输出

`third_party\aggregate.cmd build all` 和 `check all` 均通过。Debug、Release 各有 `196` 个由 ownership manifest 管理的公共依赖文件，所有 stage、文件存在性和 SHA-256 校验均通过。

### 4.5 主程序与单元测试

- `cmake --preset debug` 与 `cmake --preset release` 均使用 VS2022 x64、v143、SDK `10.0.26100.0` 和 Qt `6.11.1` 成功配置；
- Debug/Release 产品 build 均成功；
- Debug development `bin` 严格校验为 `89` 个文件；
- Release development `bin` 严格校验为 `90` 个文件；
- Debug/Release 单元测试均为 `4/4` 通过；
- 单元测试 EXE 位于 `output/x64-shared-<config>/build/tests/unit`，公共 `bin` 中测试或依赖 CLI 可执行文件数量为 `0`；
- 主程序并行编译没有再发生 compiler PDB 的 `C1041` 争用。

### 4.6 Package runtime 与受限 PATH smoke

- Debug package runtime：`70` 个文件；
- Release package runtime：`71` 个文件，其中 Release 按策略额外包含 `vc_redist.x64.exe`；
- 两份 `runtime-manifest.txt` 分别有 `70` 和 `71` 个 SHA-256 条目，逐项复算失败数均为 `0`；
- 两套 package runtime 的 `.lib`、PDB、zlib、zstd、测试工具和依赖 CLI 禁止项数量均为 `0`；
- Debug/Release 的应用启动、SQLCipher 加密数据库、OpenSSL Brotli 和 Qt OpenSSL HTTPS smoke 全部通过；
- runtime smoke tool 位于 `output/x64-shared-<config>/build/tests/runtime-smoke`，没有进入 package runtime。

## 5. 非阻塞信息与已有警告

- Qt configure 报告未找到 `WrapVulkanHeaders`，但当前目标不需要 Vulkan headers，configure/generate 正常完成；
- OpenSSL 在系统代码页 936 下对个别源码产生 `C4819`，同时有若干上游窄化转换警告；构建与测试均通过；
- 主程序保留既有 `C4834`、`C4715` 和 `C4267` 告警，本阶段没有扩大范围修改业务源码。

这些信息目前不是阶段 9 阻塞项，但 `ObjectIdentifier.cpp` 的 `C4715` 应在后续源码质量阶段单独处理，不能与输出目录迁移混在同一阶段修改。

## 6. 阶段结论与下一步

阶段 9 验收通过：当前仓库可以从空 `output/` 重建两套配置，产品构建与测试入口保持分离，development output 与 package runtime 边界稳定，package manifest 可复算，受限 PATH 运行闭包有效。

README 正式工作流已于阶段 10 完成，记录见 [phase-10-readme-build-guide-validation.md](phase-10-readme-build-guide-validation.md)。后续应设计 install、ZIP/NSIS 只消费 `package/runtime` 的发布流程；干净 Windows 机器 Release gate、签名与版本号仍未完成。
