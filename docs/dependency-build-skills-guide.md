# 依赖构建 Skill 使用指南

> 适用分支：`upgrade/v4.0.0`
>
> 适用平台：Windows x64
>
> Skill 目录：`.agents/skills`
>
> 构建工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`

## 1. Skill 的作用

仓库提供五个依赖构建 Skill，帮助 Codex 或 Claude Code 根据开发者意图选择正确的仓库脚本、监控构建和测试，并解释 stage 与 manifest 验证结果。

Skill 不是第二套构建系统。每个依赖的 `third_party\<dependency>\build.cmd` 才是命令和构建行为的唯一事实来源。Skill 不应临时重写 CMake、NMake 或验证流程。

完整的人工构建顺序见 [Windows v4 build guide](windows-v4-build-guide.md)，构建架构和历史验收见 [Windows v4 build upgrade report](../.agents/reports/sqlitebrowser-v4.0.0-upgrade-summary.md)。

## 2. 可用 Skill

| Skill | 固定版本 | 上游前置依赖 | 产品 stage | 独立测试 |
| --- | --- | --- | --- | --- |
| `sqlitebrowser-build-brotli` | Brotli 1.2.0 | 无 | `output/x64-shared-<config>/build/brotli/stage` | 共享 DLL smoke |
| `sqlitebrowser-build-zlib` | zlib 1.3.2 | 无 | `output/x64-shared-<config>/build/zlib/stage` | CTest |
| `sqlitebrowser-build-zstd` | zstd 1.5.7 | 无 | `output/x64-shared-<config>/build/zstd/stage` | 共享 DLL smoke |
| `sqlitebrowser-build-openssl` | OpenSSL 3.5.7 | 同配置 Brotli stage | `output/x64-shared-<config>/build/openssl/stage` | OpenSSL safe/full 与 Brotli 聚焦测试 |
| `sqlitebrowser-build-sqlcipher` | SQLCipher 4.18.0 | 同配置 OpenSSL/Brotli stage | `output/x64-shared-<config>/build/sqlcipher/stage` | provider smoke 与 staged-product probe |

## 3. 调用方式

### 3.1 Codex

显式调用时，在 Skill 名称前使用 `$`：

~~~text
$sqlitebrowser-build-brotli 检查 Debug 和 Release 构建环境
$sqlitebrowser-build-zlib 构建并测试 Release
$sqlitebrowser-build-zstd 构建并测试 Debug 和 Release
$sqlitebrowser-build-openssl 对 Release 运行 safe 测试
$sqlitebrowser-build-sqlcipher 最小构建并测试全部配置
~~~

也可以直接描述任务；当请求明确匹配某个依赖构建 Skill 时，Codex 会自动选择对应 Skill。显式名称更适合需要固定流程或验证边界的任务。

### 3.2 Claude Code

`.claude/skills` 提供兼容入口，并转发到 `.agents/skills` 中的同名规范 Skill：

~~~text
/sqlitebrowser-build-brotli 检查构建环境
/sqlitebrowser-build-zlib 构建并测试 Release
/sqlitebrowser-build-zstd 构建全部配置
/sqlitebrowser-build-openssl 测试 Release safe
/sqlitebrowser-build-sqlcipher 测试全部配置
~~~

如果新克隆仓库或更新 Skill 后当前会话尚未发现它们，重新打开项目会话。不要把 `.claude/skills` 复制成另一套独立构建规则。

## 4. 所有 Skill 的共同规则

- 从当前 SQLiteBrowser 仓库工作，并先确认对应 `third_party/<dependency>/src` 子模块存在；
- 上游 `src` 是父仓库固定的只读源码，不应直接修改；
- 只支持 Windows x64、VS2022、MSVC v143 和 SDK `10.0.26100.0`；
- Debug 与 Release 的 work、stage、CRT 和 manifest 必须完全隔离；
- 不允许用系统安装或 `PATH` 中的同名库替代仓库 stage；
- `build` 只构建产品并将测试记录为 `not run`；
- `test` 必须绑定当前有效的 `build-manifest.txt`，成功后写 `test-manifest.txt`；
- 仅要求分析、日志解释或产物检查时，不运行构建、不清理、不修改文件；
- 只有开发者明确要求或批准时才执行 `clean`；
- Skill 不会自动安装缺失工具或永久修改系统 `PATH`；
- Skill 不会自动提交或推送 Git 修改；
- 私有 stage 不是系统安装、公共依赖输出或最终应用安装包。

## 5. 推荐使用顺序

新环境应按依赖关系调用：

~~~text
1. Brotli、zlib、zstd：check
2. Brotli、zlib、zstd：build
3. Brotli、zlib、zstd：test
4. OpenSSL：check、build、safe test
5. SQLCipher：check、build、test
6. 人工调用 third_party\aggregate.cmd
7. 使用 CMake Preset 构建和测试主程序
~~~

可以按以下方式依次交给 AI：

~~~text
$sqlitebrowser-build-brotli 检查、最小构建并测试 Debug 和 Release
$sqlitebrowser-build-zlib 检查、最小构建并测试 Debug 和 Release
$sqlitebrowser-build-zstd 检查、最小构建并测试 Debug 和 Release
$sqlitebrowser-build-openssl 检查、最小构建 Debug 和 Release，然后分别运行 safe 测试
$sqlitebrowser-build-sqlcipher 检查、最小构建并测试 Debug 和 Release
~~~

五个 Skill 完成后，公共汇总仍需使用：

~~~cmd
third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
~~~

公共汇总没有独立 Skill。它不会编译依赖，只验证私有 stage 并发布公共 allowlist。

## 6. Skill 与脚本命令映射

### 6.1 Brotli、zlib 和 zstd

三个 CMake 依赖使用一致的动作：

~~~cmd
third_party\<dependency>\build.cmd check
third_party\<dependency>\build.cmd build [all|debug|release]
third_party\<dependency>\build.cmd test [all|debug|release]
third_party\<dependency>\build.cmd clean [all|debug|release]
~~~

未指定参数时等价于 `build all`，不会运行测试。

### 6.2 OpenSSL

~~~cmd
third_party\openssl\build.cmd check [all|debug|release]
third_party\openssl\build.cmd build [all|debug|release]
third_party\openssl\build.cmd test [all|debug|release] [safe|full]
third_party\openssl\build.cmd clean [all|debug|release]
~~~

测试默认使用 `safe`：运行通用套件但排除 `test_bio_dgram`，然后运行三个 Brotli 聚焦测试。它必须报告为 safe partial pass，不能报告为 full pass。

`full` 会先检查 IPv6 UDP 回环环境，再运行未过滤套件；预检失败时停止，不会静默降级。

### 6.3 SQLCipher

~~~cmd
third_party\sqlcipher\build.cmd check [all|debug|release]
third_party\sqlcipher\build.cmd build [all|debug|release]
third_party\sqlcipher\build.cmd test [all|debug|release]
third_party\sqlcipher\build.cmd clean [all|debug|release]
~~~

SQLCipher 的 NMake 步骤只生成 amalgamation 和公开源码，产品 DLL 与测试 CLI 由 CMake/MSBuild 分别管理。测试不运行 SQLCipher/SQLite Tcl suite。

## 7. 各 Skill 的边界

### 7.1 Brotli

只构建 `brotlicommon.dll`、`brotlidec.dll` 和 `brotlienc.dll`。静态 package targets、Brotli CLI 和上游 CLI tests 保持关闭。

Skill 通过只代表 Brotli 共享 DLL 可用，不代表 OpenSSL Brotli BIO 或 TLS certificate compression 已验证。

### 7.2 zlib

只构建 `zlib1.dll`。stage 中的 `zlib1.lib` 是 DLL import library，不表示启用了静态 zlib。minizip 和所有 contrib 组件保持关闭。

Skill 通过不代表 OpenSSL 已启用 zlib；当前 OpenSSL 构建没有集成 zlib。

### 7.3 zstd

只构建 `libzstd.dll`。静态库、CLI、contrib、legacy、deprecated 及 zlib/LZMA/LZ4 compatibility 保持关闭。

Skill 通过不代表 OpenSSL 已启用 zstd certificate compression；当前 OpenSSL 构建没有集成 zstd。

### 7.4 OpenSSL

只构建 Crypto/SSL 最小开发 stage，并动态使用同配置 Brotli。普通 build 不构建或 stage `openssl.exe`、独立 provider、engine、test 或 fuzz 程序。

测试专用 CLI、provider 和测试程序可以出现在私有 work，但不得进入 stage。当前构建不启用 FIPS，也不能宣称 FIPS 认证。

### 7.5 SQLCipher

只构建 `sqlcipher.dll` 产品 stage。测试专用 CLI 和 probe 留在私有 work，OpenSSL/Brotli DLL 不复制到 SQLCipher stage。

测试通过只能报告 provider smoke 与 staged-product probe 通过，不能报告“SQLCipher 官方完整测试套件通过”。

## 8. 如何判断执行成功

Skill 的最终报告至少应包含：

- 实际 VS2022 edition、MSVC、CMake 和 SDK；
- 依赖 tag 与完整提交；
- 实际处理的 Debug/Release 配置；
- 精确的 work 和 stage 路径；
- 产品 DLL、import LIB、linker PDB、公开头文件和许可证检查；
- x64、CRT、导出、DLL 依赖和版本验证；
- `build-manifest.txt` 是否与本次构建一致；
- 测试是否执行、模式与结果；
- `test-manifest.txt` 是否绑定当前 build manifest；
- 所有明确排除、跳过步骤和未解决阻塞项。

只有脚本返回 0、stage allowlist 验证通过且 manifest 有效时，才能把该配置交给上层依赖。不能只依据“DLL 已生成”判断成功。

## 9. 不属于这些 Skill 的任务

以下任务需要使用仓库正式命令或另行设计，不能由五个依赖 Skill 自动扩展处理：

- `third_party\aggregate.cmd` 公共依赖汇总；
- 主程序 CMake configure/build 和单元测试；
- development `bin` 部署；
- package runtime 组装与受限 `PATH` smoke；
- CMake install、ZIP、NSIS/WiX、签名、版本号和发布；
- 修改上游子模块、升级依赖 tag 或维护补丁；
- Git commit、push、merge、rebase 或分支操作。

主程序和 package workflow 请按 [Windows v4 build guide](windows-v4-build-guide.md) 执行。

## 10. 常见请求示例

只检查环境，不产生输出：

~~~text
$sqlitebrowser-build-openssl 只检查 Debug 和 Release 环境，不构建、不测试
~~~

只构建产品，不运行测试：

~~~text
$sqlitebrowser-build-sqlcipher 最小构建 Release，不运行测试
~~~

测试已有产物：

~~~text
$sqlitebrowser-build-openssl 对已有 Debug 和 Release stage 运行 safe 测试
~~~

分析失败日志：

~~~text
$sqlitebrowser-build-zstd 分析这段构建错误，只分析，不修改、不重新构建
~~~

明确清理单个配置后重建：

~~~text
$sqlitebrowser-build-zlib 清理并重新构建、测试 Release；不要影响 Debug 或其他依赖
~~~

在请求中明确配置、是否测试、是否允许清理和期望边界，可以避免 AI 扩大操作范围。
