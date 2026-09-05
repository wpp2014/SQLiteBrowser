# SQLiteBrowser v4.0.0 Windows 构建升级综合报告

> 整理日期：2026-09-05
>
> 当前分支：`upgrade/v4.0.0`
>
> 整理基线：`d394aea27aa2c64010217e7f80e299092ca736a0`
>
> 适用范围：Windows x64、Visual Studio 2022、Qt 6.11.1
>
> 文档来源：原 `docs/upgrade/v4.0.0` 下 19 份分析、实施与验证文档；原文已在完成归并后删除

## 1. 最终结论

当前分支已经完成 Windows x64 构建体系的主体升级：

- 五个外部依赖已固定为 Git submodule，并由仓库内 wrapper 和 `build.cmd` 构建；
- Debug 与 Release 使用独立配置根、依赖 stage、CRT 和 manifest；
- 主程序已使用 CMake Preset 构建，Qt 路径只写入开发者本地 Preset；
- 普通产品构建、单元测试、package runtime 和 runtime smoke 已拆成独立入口；
- 主程序构建完成后，development `bin` 可以直接运行；
- package runtime 使用严格 allowlist 和 SHA-256 manifest，已作为 ZIP、NSIS SFX 和 MSI 的唯一输入；
- Release x64 ZIP、NSIS 3.12 自解压 EXE 与 WiX 7 MSI 已生成，并通过解包、文件集合和 SHA-256 验证；
- 已从空 `output/` 完成 Debug/Release 全链路重建和验证。

阶段 1 至阶段 10 已完成，ZIP、portable SFX 与 MSI 的本机构建闭环也已打通。当前尚未完成的是 CMake install、许可证布局、签名、SBOM、CI 和干净 Windows 机器 Release gate。

本分支直接以当前代码为升级基线，不再以 `v3.13.1` 的本地开发环境为前置条件，也不在构建迁移期间自动同步、合并或回退上游标签。

## 2. 固定环境

| 项目 | 当前契约 |
| --- | --- |
| 平台 | Windows x64 only |
| Visual Studio | 2022 Enterprise、Professional 或 Community，默认安装目录 |
| 工具集 | MSVC v143，x64 host/target |
| Windows SDK | `10.0.26100.0`，依赖和主程序必须一致 |
| CMake/CTest | 已验证 `3.30.3` |
| Qt | `6.11.1`、`msvc2022_64`，包含 Core5Compat、LinguistTools、SVG、PDF |
| Git | 在 `PATH` 中；已验证 Git for Windows 2.45.1 |
| OpenSSL 工具 | Windows 原生 Perl、NASM、NMake |
| 打包工具 | NSIS 3.12（默认安装路径）用于 portable SFX；WiX SDK 7.0.0 由项目锁定并恢复 |

依赖脚本只探测以下 Visual Studio 默认目录，不支持自定义安装位置：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

Debug 固定使用 `/MDd`，Release 固定使用 `/MD`。Debug 运行时只用于安装了匹配开发工具链的机器，不是正式可分发版本。

## 3. 固定依赖与关系

| 依赖 | Tag | 固定提交 | 当前用途 |
| --- | --- | --- | --- |
| Brotli | `v1.2.0` | `028fb5a23661f123017c060daa546b55cf4bde29` | OpenSSL 动态压缩运行时 |
| zlib | `v1.3.2` | `da607da739fa6047df13e66a2af6b8bec7c2a498` | 已构建和汇总，当前不在应用运行闭包 |
| zstd | `v1.5.7` | `f8745da6ff1ad1e7bab384bd1f9d742439278e99` | 已构建和汇总，当前不在应用运行闭包 |
| OpenSSL | `openssl-3.5.7` | `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e` | SQLCipher Crypto 与 Qt TLS 共用 |
| SQLCipher | `v4.18.0` | `63697beb0fafcb61faa7a3e6fd267036548ab11b` | 主程序数据库 provider；SQLite baseline 3.53.4 |

构建依赖图：

```text
Brotli ──> OpenSSL ──> SQLCipher ──> SQLiteBrowser
zlib  ─┐
zstd  ─┴─> 公共开发依赖输出（当前不进入应用 package runtime）
Qt 6.11.1 ────────────────────────> SQLiteBrowser
```

关键约束：

- submodule 只固定源码；实际构建参数、输出和验证由父仓库 wrapper 管理；
- 初始化使用 `git submodule update --init --recursive`，不要使用 `--remote`；
- 不在 `third_party/<dependency>/src` 内生成产品或提交二进制；
- 不允许回退到系统 OpenSSL、SQLCipher、zlib 或 zstd；
- OpenSSL 使用 `enable-brotli-dynamic`，必须同时部署三个 Brotli DLL；
- 当前 OpenSSL 不启用 zlib/zstd 压缩集成；
- 使用 OpenSSL 3.5.7 不代表启用或获得 FIPS 认证，FIPS 不属于当前范围；
- Qt 6.11.1 Windows 包运行时使用 OpenSSL 3 接口；Qt TLS 与 SQLCipher 必须加载同一套项目 OpenSSL DLL。

## 4. 构建与输出架构

每个配置使用一个独立根目录：

```text
output/
|- x64-shared-debug/
`- x64-shared-release/
```

单个配置的目录契约：

```text
output/x64-shared-<config>/
|- build/
|  |- brotli/{work,stage}/
|  |- zlib/{work,stage}/
|  |- zstd/{work,stage}/
|  |- openssl/{work,stage}/
|  |- sqlcipher/{work,stage}/
|  |- sqlitebrowser/
|  `- tests/
|     |- unit/
|     `- runtime-smoke/
|- include/                         # 五个依赖的公共开发头文件
|- bin/                             # development output
|- metadata/                        # 依赖 manifest、许可证、ownership
`- package/
   |- runtime/                      # 严格运行闭包，未来发布唯一输入
   `- metadata/runtime-manifest.txt
```

### 4.1 私有 stage

每个依赖脚本只维护自己的 `build/<dependency>/stage`。stage 包含产品 DLL、import LIB、linker PDB、公开头文件、许可证和 manifest；测试程序、CLI、compiler PDB、示例和不需要的静态库不得进入产品 stage。

### 4.2 公共开发输出

`third_party\aggregate.cmd` 验证五个私有 stage 后，将 allowlist 发布到配置级 `include`、`bin`、`metadata`。ownership manifest 记录汇总器拥有文件的路径与 SHA-256，使重复发布和配置级清理不会覆盖未知文件。

主程序构建随后向同一个 `bin` 增加 EXE/PDB、Qt runtime/plugins 和实际应用依赖。该目录用于开发、链接和直接运行，允许包含 `.lib`、linker PDB、zlib 和 zstd，因此不能直接制作安装包。

### 4.3 Package runtime

`package/runtime` 只从验证过的 development `bin` 按固定 allowlist 逐项复制。它不包含：

- `.lib` 或 PDB；
- zlib、zstd；
- 单元测试、runtime-smoke tool；
- `openssl.exe`、`sqlcipher.exe`、provider/engine 或 `vc143.pdb`。

Release 额外包含 `vc_redist.x64.exe`。每次组装会拒绝缺失文件、额外文件、Debug/Release 混用和非法路径，并生成逐文件 SHA-256 manifest。

## 5. 从新克隆到完整验证

以下命令是当前正式顺序，均从仓库根目录的普通 `cmd.exe` 执行。

### 5.1 初始化

```cmd
git clone --branch upgrade/v4.0.0 --recurse-submodules https://github.com/wpp2014/SQLiteBrowser.git
cd SQLiteBrowser
git submodule update --init --recursive
```

### 5.2 检查、构建和测试依赖

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
```

`build` 只生成产品和 `build-manifest.txt`，不隐式运行测试。`test` 只构建测试专用目标，并在成功后生成绑定当前 build manifest 的 `test-manifest.txt`。

### 5.3 创建本地 Preset

```cmd
copy /Y CMakePresets.template.json CMakePresets.json
```

只在本地 `CMakePresets.json` 中将：

```text
REPLACE_WITH_QT_6_11_1_MSVC2022_X64_ROOT
```

替换为 Qt 6.11.1 `msvc2022_64` 根目录，例如：

```json
"CMAKE_PREFIX_PATH": "D:/Qt/6.11.1/msvc2022_64"
```

不要修改配置根或 OpenSSL/SQLCipher stage 路径，不需要设置 `SQLITEBROWSER_QT_ROOT`。本地 `CMakePresets.json` 被 Git 忽略，模板保持可提交。

确认入口：

```cmd
cmake --list-presets=all
```

### 5.4 构建主程序

```cmd
cmake --preset debug
cmake --build --preset debug

cmake --preset release
cmake --build --preset release
```

普通 build preset 只构建 `sqlitebrowser`。`POST_BUILD` 自动复制匹配配置的 SQLCipher、OpenSSL 和 Brotli DLL，运行 `windeployqt`，并验证 development `bin`。

可直接运行：

```cmd
"output\x64-shared-debug\bin\DB Browser for SQLCipher.exe"
"output\x64-shared-release\bin\DB Browser for SQLCipher.exe"
```

不需要把 Qt、OpenSSL 或 SQLCipher 加入全局 `PATH`。

### 5.5 单元测试

```cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
```

两个 workflow 分别配置、构建 `sqlitebrowser_unit_tests` 聚合目标并运行 CTest。四个测试 EXE 只保存在 `build/tests/unit`，不会进入公共 `bin`。

### 5.6 Package runtime 与 smoke

只组装 package runtime：

```cmd
cmake --workflow --preset package-debug
cmake --workflow --preset package-release
```

组装并执行受限 `PATH` smoke：

```cmd
cmake --workflow --preset smoke-debug
cmake --workflow --preset smoke-release
```

`smoke-*` 已包含 package 组装，不要求预先执行 `package-*`。smoke 验证：

- 主程序 `--quit` 启动；
- SQLCipher 加密数据库创建和读取；
- OpenSSL Brotli 压缩接口；
- Qt OpenSSL 3.5.7 backend 与 HTTPS；
- 实际加载 DLL 均来自当前 package runtime。

HTTPS 默认访问 `https://download.sqlitebrowser.org/currentrelease`，离线失败应单独报告；可以通过 `SQLITEBROWSER_TLS_SMOKE_URL` 指定批准的 HTTPS 地址。

## 6. 各依赖的最小构建边界

| 依赖 | 产品构建 | 独立测试 | 明确排除 |
| --- | --- | --- | --- |
| Brotli | 三个共享 DLL：common/dec/enc | 项目共享 DLL smoke | CLI、静态 package targets |
| zlib | `zlib1.dll` 和 import LIB | 13 项 CTest | 静态 zlib、minizip、contrib |
| zstd | `libzstd.dll` 和 import LIB | 项目共享 DLL smoke | CLI、静态库、contrib、zlib/LZMA/LZ4 compatibility |
| OpenSSL | `nmake build_libs` + `install_dev`，Crypto/SSL | `safe` 或 `full`，另含 Brotli 聚焦测试 | 产品 stage 中的 CLI、独立 provider、engine、test/fuzz |
| SQLCipher | NMake 只生成 amalgamation；CMake/MSBuild 构建 DLL | provider smoke 与 staged-product probe | 产品 stage 中的 CLI、Tcl suite、OpenSSL/Brotli DLL |

OpenSSL `safe` 会排除可能受本机 IPv6 UDP/VPN/防火墙影响的 `test_bio_dgram`，不能描述为 full pass。`full` 会先执行 IPv6 UDP 回环预检，预检失败则停止。

SQLCipher 当前测试不运行 Tcl 官方测试套件，因此不能声明完整 SQLCipher suite 通过。

## 7. 项目构建 Skill

仓库中的 `.agents/skills` 是 Codex/Claude 共用的规范来源，构建事实源仍是对应 `build.cmd`：

完整调用方式和示例见 [依赖构建 Skill 使用指南](../../docs/dependency-build-skills-guide.md)。

| Skill | 用途 |
| --- | --- |
| `$sqlitebrowser-build-brotli` | Brotli 环境检查、最小构建、共享 DLL smoke、stage 验证 |
| `$sqlitebrowser-build-zlib` | zlib 环境检查、最小构建、CTest、stage 验证 |
| `$sqlitebrowser-build-zstd` | zstd 环境检查、最小构建、共享 DLL smoke、stage 验证 |
| `$sqlitebrowser-build-openssl` | OpenSSL/Brotli 环境检查、最小 Crypto/SSL 构建、safe/full 测试 |
| `$sqlitebrowser-build-sqlcipher` | SQLCipher/OpenSSL 环境检查、最小 DLL 构建、provider 测试 |

Skill 只负责选择命令、监控和解释结果。仅要求分析时不得构建或修改；未明确要求时不得自动清理；不会修改上游子模块、系统 `PATH`、主程序安装器或 Git 历史。

## 8. 已验证结果

2026-08-31 从空 `output/` 完成全链路验证：

| 范围 | Debug | Release |
| --- | --- | --- |
| Brotli smoke | 1/1 通过 | 1/1 通过 |
| zlib CTest | 13/13 通过 | 13/13 通过 |
| zstd smoke | 1/1 通过 | 1/1 通过 |
| OpenSSL safe suite | 343 files / 4279 tests，PASS | 343 files / 4279 tests，PASS |
| OpenSSL Brotli 聚焦测试 | 3 files / 11 tests，PASS | 3 files / 11 tests，PASS |
| SQLCipher provider smoke | 1/1 通过 | 1/1 通过 |
| 主程序单元测试 | 4/4 通过 | 4/4 通过 |
| Development `bin` | 89 个文件 | 90 个文件 |
| Package runtime | 70 个文件 | 71 个文件 |

其他验收结果：

- 每个配置的公共依赖输出包含 196 个 ownership 管理文件；
- package manifest 的 SHA-256 逐项复算失败数为 0；
- package runtime 中 `.lib`、PDB、zlib、zstd、测试工具和依赖 CLI 数量为 0；
- Debug/Release 应用启动、SQLCipher、Brotli、Qt OpenSSL HTTPS smoke 均通过；
- 主程序增加 MSVC `/FS` 后，未再出现并行写 compiler PDB 的 `C1041`；
- README 已使用上述实测命令作为正式 Windows v4 开发入口。

这些结果只证明 2026-08-31 的记录基线通过，不等于未来提交自动通过；依赖、CMake、Qt 或源码变更后必须重新执行对应门禁。

## 9. 已知边界与风险

### 9.1 尚未完成

- portable ZIP、NSIS SFX 和 WiX MSI 已只消费 `package/runtime`；CMake install 尚未迁移；
- Release 尚未在不含 Qt/OpenSSL/SQLCipher 开发环境的干净 Windows 机器验证；
- CI 尚未固化完整依赖、产品、测试、package 和 smoke 流程；
- CMake/MSI 已使用 v4.0.0 和固定 UpgradeCode；EXE 文件版本、跨产物产品名称及真实旧版升级兼容仍需验证；
- 许可证布局、SBOM、代码签名、归档签名和安装/卸载测试尚未定义。

### 9.2 测试声明限制

- OpenSSL 当前记录是排除 `test_bio_dgram` 的 safe pass，不是 full pass；
- SQLCipher Tcl suite、错误密钥、rekey 和真实旧数据库样本兼容性未形成完整发布证据；
- SQLCipher/OpenSSL 的大数据库、批量写入和多连接性能回归尚未建立基准；
- FIPS 未启用、未验证，也不能宣称认证。

### 9.3 发布前必须重新检查

- OpenSSL 3.5 LTS 的最新安全 patch 和公告；
- Qt 6.11.1 与实际 OpenSSL runtime 的 TLS backend 行为；
- Release 不包含 Debug CRT，且不从系统 `PATH` 偶然加载 DLL；
- package/runtime 的 manifest、许可证、签名和归档内容一致；
- 现有源码告警，特别是 `ObjectIdentifier.cpp` 的 `C4715`，应作为独立代码质量任务处理。

## 10. 常见故障定位

| 现象 | 处理方式 |
| --- | --- |
| 子模块源码缺失 | 在仓库根目录执行 `git submodule update --init --recursive`，不要使用 `--remote` |
| 找不到 Visual Studio | 确认 VS2022 位于受支持的默认目录，并安装 Desktop development with C++、MSVC v143 和 SDK 10.0.26100.0 |
| 找不到 Perl 或 NASM | 使用 `where perl.exe`、`where nasm.exe` 检查 `PATH`；脚本不会自动安装工具 |
| Perl 报中文 locale 不支持 | 正式 OpenSSL 脚本已在局部环境设置 `LC_ALL=C` 和 `LANG=C`；不要永久修改系统区域设置 |
| CMake generator instance 不匹配 | 仅在明确允许后执行对应依赖的 `clean <config>`，不要删除整个 `output` |
| OpenSSL 测试长时间无输出 | 先检查测试进程和网络状态；开发机优先使用 `safe`，它会明确排除 `test_bio_dgram` |
| SQLCipher 拒绝 OpenSSL stage | 按 Brotli → OpenSSL → SQLCipher 顺序重建同一配置，不要手工复制或修改 manifest |
| CMake 找不到 Qt | 重新从模板生成本地 Preset，只填写 Qt 6.11.1 `msvc2022_64` 的 `CMAKE_PREFIX_PATH` |
| Preset 缺失 | 执行 `cmake --list-presets=all`；若本地 Preset 过期，从当前模板重新复制 |
| 主程序缺少 Qt plugin 或 DLL | 重新执行匹配配置的产品 build，让 `POST_BUILD` 完成部署和校验 |
| Package 拒绝额外文件或哈希 | 重新运行产品 build 和 `package-*`；不要手工修改 `package/runtime` |
| HTTPS smoke 无法连接 | 检查网络，或通过 `SQLITEBROWSER_TLS_SMOKE_URL` 使用批准的可访问 HTTPS 地址 |

脚本返回非零退出码时，对应 stage、公共输出或 package runtime 均不得继续用于上层构建或发布。

## 11. 下一阶段建议

下一阶段只处理正式发布闭环，不重新设计已经验证的依赖构建：

1. 定义 Release package 契约：版本、文件名、许可证、VC runtime、manifest、签名和 SBOM；
2. 让尚未迁移的 CMake install 复用 ZIP/SFX/MSI 已采用的 `output/x64-shared-release/package/runtime`；
3. 禁止安装器重新从 development `bin`、私有 stage、系统目录或 `PATH` 选择 DLL；
4. 增加归档内容 allowlist、安装/卸载和升级测试；
5. 在干净 Windows x64 环境验证启动、数据库、TLS、插件和实际 DLL 来源；
6. 将依赖 check/build/test、aggregate、主程序、单元测试、package 和 smoke 接入 CI；
7. 发布候选冻结后再更新项目版本号，并重新执行完整门禁。

## 12. 已删除原文档归并索引

以下 19 份文档已完成归并并从 `docs/upgrade/v4.0.0` 删除。表格保留原文件名和归并去向，便于从 Git 历史追溯。以后执行构建优先看 [Windows v4 build guide](../../docs/windows-v4-build-guide.md)、根 [README](../../README.md)、本报告、当前脚本 `--help` 和对应项目 Skill。

| 原文档 | 在本报告中的归并位置 | 当前定位 |
| --- | --- | --- |
| `current-build-analysis.md` | 第 1、4、5 节 | 迁移前分析，路径和“未实施”状态已过时 |
| `development-environment-upgrade-plan.md` | 第 2、5、9 节 | 环境与早期实施计划，已由阶段 1–10 结果替代 |
| `master-baseline-risk-analysis.md` | 第 1、9 节 | 保留风险分类，早期 SDK/实施状态已过时 |
| `sqlcipher-openssl-submodule-superbuild-plan.md` | 第 3、4、9 节 | 子模块和依赖关系设计历史 |
| `brotli-vs2022-build-analysis.md` | 第 3、6、8 节 | Brotli 原始分析、实现与 OpenSSL 集成细节 |
| `zlib-vs2022-build-analysis.md` | 第 3、6、8 节 | zlib wrapper、测试与 stage 细节 |
| `zstd-vs2022-build-analysis.md` | 第 3、6、8 节 | zstd wrapper 设计；最终验收以阶段 9 为准 |
| `openssl-vs2022-build-analysis.md` | 第 3、6、8、9 节 | OpenSSL 上游构建依据和测试边界 |
| `openssl-build-automation-guide.md` | 第 5–7、10 节 | OpenSSL 当前脚本、Skill 与故障处理 |
| `sqlcipher-vs2022-build-analysis.md` | 第 3、6、9 节 | SQLCipher 构建与兼容性分析 |
| `sqlcipher-build-automation-guide.md` | 第 5–7、10 节 | SQLCipher 当前脚本、Skill 与故障处理 |
| `dependency-public-aggregation-guide.md` | 第 4、5、8 节 | 公共依赖输出与 ownership 契约 |
| `unified-output-and-minimal-build-plan.md` | 第 4–6、11 节 | 输出重构总方案和阶段记录 |
| `main-application-cmake-migration-plan.md` | 第 1、4、5、9、11 节 | 主程序阶段 1–10 的实施总记录 |
| `main-application-unified-output-guide.md` | 第 4、5 节 | 主程序 development output 手册 |
| `main-application-unit-test-workflow-guide.md` | 第 5、8 节 | 单元测试隔离与 workflow 手册 |
| `main-application-package-runtime-guide.md` | 第 4、5、8、11 节 | 严格 package runtime 当前契约 |
| `phase-9-clean-build-validation.md` | 第 8、9 节 | 从空 output 的最新全链路实测证据 |
| `phase-10-readme-build-guide-validation.md` | 第 1、5、8 节 | README 正式入口验收记录 |

## 13. 信息优先级

文档存在冲突时按以下优先级判断：

1. 当前脚本的 `--help`、`CMakePresets.template.json` 和 `docs/windows-v4-build-guide.md`；
2. 本报告第 8 节保留的阶段 9、阶段 10 验证结果；
3. 当前项目构建 Skill；
4. 本报告中标记为历史背景的早期结论。

早期文档中的 `build/x64-*`、SDK `10.0.22621.0`、普通 build 自动运行测试、主程序尚未接入、zlib/zstd/OpenSSL/SQLCipher 尚未实现等描述均视为历史记录，不再作为当前操作契约。
