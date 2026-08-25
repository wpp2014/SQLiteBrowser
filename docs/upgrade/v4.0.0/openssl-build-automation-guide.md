# OpenSSL 构建脚本与项目 Skill 使用说明

> 适用项目：SQLiteBrowser `upgrade/v4.0.0`
>
> 适用平台：Windows x64
>
> OpenSSL：`openssl-3.5.7` / `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.22621.0`

本文说明如何使用项目自带的 OpenSSL 构建脚本，以及如何在 Codex 和 Claude Code 中调用项目 Skill。OpenSSL 的构建原理、参数依据和产物分析见 [openssl-vs2022-build-analysis.md](openssl-vs2022-build-analysis.md)。

## 1. 文件位置

项目自动化由以下文件组成：

```text
SQLiteBrowser/
|- third_party/
|  |- openssl/
|     |- build.cmd                         # 人和 AI 共用的构建入口
|     |- src/                              # 固定的 OpenSSL 上游子模块
|- .agents/
|  |- skills/
|     |- sqlitebrowser-build-openssl/
|        |- SKILL.md                       # Codex 使用的规范 Skill
|- .claude/
|  |- skills/
|     |- sqlitebrowser-build-openssl/
|        |- SKILL.md                       # Claude Code 兼容入口
|- build/
   |- openssl/
      |- x64-debug/
      |  |- work/
      |  |- stage/
      |- x64-release/
         |- work/
         |- stage/
   |- brotli/
      |- x64-debug/
      |  |- stage/                        # Debug OpenSSL 的前置依赖
      |- x64-release/
         |- stage/                        # Release OpenSSL 的前置依赖
```

构建逻辑只存在于 `third_party\openssl\build.cmd`。Skill 负责选择参数、调用脚本、监控和解释结果，不应重新拼装另一套 Configure/NMake 命令。

## 2. 前置条件

运行脚本前需要：

- Windows x64；
- Git，且 `git.exe` 在 `PATH`；
- Visual Studio 2022 Enterprise、Professional 或 Community，安装在默认目录；
- Visual Studio 工作负载 `Desktop development with C++`；
- MSVC v143 x64/x86 build tools；
- Windows SDK `10.0.22621.0`；
- Windows 原生 Perl 5.10 或更高版本，推荐 Strawberry Perl；
- NASM，且 `nasm.exe` 在 `PATH`；
- Windows 自带的 `certutil.exe`；选择 `full` 时还需要 Windows PowerShell；
- 已由 `third_party\brotli\build.cmd` 成功构建并验证的匹配配置 Brotli stage。

Debug OpenSSL 只允许消费 `build\brotli\x64-debug\stage`，Release 只允许消费 `build\brotli\x64-release\stage`。脚本会验证 Brotli tag、commit、架构、CRT、VS/MSVC/SDK、运行时版本、smoke test 和 manifest；不会退回系统安装的 Brotli，也不会混用配置。

脚本支持 Enterprise（企业版）、Professional（专业版）和 Community（社区版），不依赖某一版独有的编译功能。它只检查以下 Visual Studio 默认目录，并按该顺序选择第一个可用实例：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

脚本不使用 `vswhere`，不搜索自定义安装目录，也不会自动安装缺失工具。找不到工具或精确 SDK 时会打印错误并以非零状态退出。

脚本会在自己的 `setlocal` 范围内设置：

```cmd
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
```

这用于避免 Strawberry Perl 在中文 Windows 环境中报告不支持的 locale，不会改变应用程序语言或调用者的永久环境变量。

## 3. 初始化子模块

推荐克隆或拉取代码后执行：

```cmd
git submodule update --init --recursive
```

如果 `third_party\openssl\src\Configure` 不存在，构建脚本也会尝试初始化 OpenSSL 子模块。脚本随后严格检查 OpenSSL commit；如果不是项目固定的 `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`，或者 OpenSSL 子模块存在本地修改，脚本会拒绝构建，而不会自动 checkout 或覆盖修改。

首次构建 OpenSSL 前，先生成 Brotli stage：

```cmd
third_party\brotli\build.cmd all clean
third_party\openssl\build.cmd check
```

`check` 会同时验证 Debug 和 Release 的匹配 Brotli stage。只构建单一配置时，实际构建仍只消费对应配置。

## 4. 直接使用构建脚本

脚本可以从仓库中的任意工作目录调用。以下示例从仓库根目录执行。

查看帮助：

```cmd
third_party\openssl\build.cmd --help
```

只检查环境、子模块和工具，不执行 Configure、编译、测试或安装：

```cmd
third_party\openssl\build.cmd check
```

不带参数时构建 Debug 和 Release，并执行安全测试模式：

```cmd
third_party\openssl\build.cmd
```

它等价于：

```cmd
third_party\openssl\build.cmd all safe
```

### 4.1 构建配置

```cmd
third_party\openssl\build.cmd debug safe
third_party\openssl\build.cmd release safe
third_party\openssl\build.cmd all safe
```

OpenSSL NMake 构建不是多配置构建。Debug 和 Release 始终使用各自独立的 `work` 与 `stage`。

### 4.2 测试模式

安全模式：

```cmd
third_party\openssl\build.cmd all safe
```

执行通用测试套件，但排除可能因本机 IPv6 UDP 回环故障无限等待的 `test_bio_dgram`；随后显式运行 `test_bio_comp test_cert_comp test_tls13certcomp` 三项 Brotli 集成测试。前者必须记录为“部分测试通过”，三项专项测试应单独记录为通过或失败。

完整模式：

```cmd
third_party\openssl\build.cmd release full
```

脚本先执行 IPv6 UDP `::1` 回环收发检查。只有预检成功才运行完整 `nmake test`；预检失败会明确退出，不会静默降级到安全模式。

跳过测试：

```cmd
third_party\openssl\build.cmd debug none
```

这适合已经验证过同一源码和工具链后的快速增量开发。脚本仍会检查安装产物、版本、provider、CRT、Brotli 动态加载配置、导出和 DLL 身份，但不会运行通用测试或三项 Brotli 专项测试，不能将结果记录为“测试通过”。

项目没有在 Configure 中使用 `no-tests`，因此即使某次选择 `none`，仍可在后续补跑完整测试。

### 4.3 清理重建

```cmd
third_party\openssl\build.cmd release full clean
```

`clean` 只允许删除项目 `build\openssl\x64-debug` 或 `x64-release` 下当前配置的 `work` 和 `stage`，然后从空目录重新 Configure。它不会删除 OpenSSL 源码或其他项目构建目录。

不带 `clean` 时，如果工作目录内已有 `makefile` 和 `configdata.pm`，脚本会复用现有配置并执行增量构建；首次构建或显式指定 `clean` 时，才会按固定参数重新执行 Configure。构建参数或工具链要求发生变化后，应使用 `clean`。

## 5. 输出与验证

Debug stage：

```text
build\openssl\x64-debug\stage
```

Release stage：

```text
build\openssl\x64-release\stage
```

脚本在安装后检查：

- OpenSSL 版本和 Configure 平台；
- 默认 provider；
- `legacy` provider 的显式加载；
- 公开头文件；
- `libcrypto.lib` 和 `libssl.lib`；
- `libcrypto-3-x64.dll` 和 `libssl-3-x64.dll`；
- OpenSSL CMake package；
- Debug/Release CRT 依赖。

此外还验证 Brotli 集成：

- Configure 同时启用 `brotli` 和 `brotli-dynamic`，并记录匹配 stage 的 include 路径；
- `libcrypto-3-x64.dll` 导出 `COMP_brotli`、`COMP_brotli_oneshot` 和 `BIO_f_brotli`；
- `libcrypto-3-x64.dll` 没有对 Brotli DLL 的静态导入依赖，证明采用运行时动态加载；
- OpenSSL stage 的 `brotlicommon.dll`、`brotlidec.dll`、`brotlienc.dll` 与匹配 Brotli stage 逐字节一致；
- 三个 Brotli DLL 都是 x64，并与 OpenSSL 配置使用相同 CRT。

每个 stage 会生成忽略提交的：

```text
build-manifest.txt
```

其中记录 OpenSSL tag/commit、构建配置、测试模式、VS 版本、MSVC tools、Windows SDK、Perl/NASM、`openssl version -a`、Brotli tag/commit/stage/动态加载方式/专项测试状态，以及 OpenSSL 和 Brotli DLL 的 SHA-256。

Debug DLL 依赖 `VCRUNTIME140D.dll`，只能用于开发。Release DLL 必须不依赖 `VCRUNTIME140D.dll` 或 `ucrtbased.dll`。

## 6. 使用 Codex Skill

Codex 从仓库根目录的 `.agents\skills` 自动发现项目 Skill，规则见 [Codex Agent Skills 官方文档](https://developers.openai.com/codex/skills)。可以显式调用：

```text
$sqlitebrowser-build-openssl 检查当前机器是否满足 OpenSSL 构建条件
```

```text
$sqlitebrowser-build-openssl 构建 Debug 和 Release，使用 safe 测试模式
```

```text
$sqlitebrowser-build-openssl 对 Release 执行 clean 和 full 构建验证
```

也可以自然语言请求：

```text
帮我构建当前项目固定的 OpenSSL Release 版本，先检查环境。
```

Skill 可根据描述自动匹配，但它会区分“只分析”和“实际构建”：只要求分析时不得运行构建或修改文件。

如果新拉取的 Skill 没有立即出现在 Codex 中，重新打开任务或重启 Codex。

## 7. 使用 Claude Code Skill

Claude Code 从 `.claude\skills` 自动发现项目 Skill，规则见 [Claude Code Skills 官方文档](https://code.claude.com/docs/en/skills)。调用方式是：

```text
/sqlitebrowser-build-openssl 检查构建环境
```

```text
/sqlitebrowser-build-openssl 构建全部配置，使用 safe 模式
```

Claude 入口会读取 `.agents\skills\sqlitebrowser-build-openssl\SKILL.md` 中的规范内容，因此构建规则只维护一份。

如果首次新增 `.claude\skills` 后当前 Claude Code 会话没有发现它，重启 Claude Code。

## 8. 部署边界

当前自动化中的“部署”指：

```text
nmake install_sw + nmake install_ssldirs
        -> build\openssl\x64-<config>\stage
```

它不表示复制到 SQLiteBrowser 可执行文件目录，也不表示制作 MSI。

当前 x64 WiX 安装器仍引用 OpenSSL 1.1.1 文件名：

```text
libcrypto-1_1-x64.dll
libssl-1_1-x64.dll
```

在安装器和 Qt 6 部署逻辑完成升级前，Skill 不得擅自把 OpenSSL 3 文件复制进最终安装包目录。

未来正式应用部署通常只需要 Release：

```text
bin\libcrypto-3-x64.dll
bin\libssl-3-x64.dll
bin\brotlicommon.dll
bin\brotlidec.dll
bin\brotlienc.dll
```

启用 Brotli 动态加载后，五个 DLL 必须作为同一套 Release 运行时部署；不能只部署 OpenSSL 的两个 DLL。

`legacy.dll`、engines、`openssl.cnf`、`openssl.exe` 和 PDB 应根据明确运行时或调试需求决定，不应无条件进入用户安装包。

## 9. 常见错误

### 找不到 Visual Studio

确认 VS2022 安装在受支持的默认目录，并安装了 Desktop development with C++、MSVC v143 和 SDK `10.0.22621.0`。

### 找不到 Perl 或 NASM

在普通 CMD 中确认：

```cmd
where perl.exe
where nasm.exe
```

脚本不会扫描自定义工具目录。工具必须可以通过 `PATH` 调用。

### Perl locale 警告

必须通过项目脚本运行。脚本在局部环境中固定 `LC_ALL=C` 和 `LANG=C`。不要使用 `PERL_BADLANG=0` 隐藏问题。

### 完整测试拒绝启动

`full` 模式的 IPv6 UDP 预检失败时，检查 VPN、TUN、代理、防火墙、VMware 网络过滤组件及 `ping -6 ::1`。开发机可以改用 `safe`，但必须记录排除项。

### OpenSSL 子模块版本不符或不干净

脚本不会自动丢弃源码改动。先查看：

```cmd
git -C third_party\openssl\src status --short
git -C third_party\openssl\src rev-parse HEAD
```

确认变更如何处理后再构建。

### Brotli stage 缺失或不匹配

先运行对应配置的 Brotli 构建：

```cmd
third_party\brotli\build.cmd debug
third_party\brotli\build.cmd release
```

不要手工修改 manifest 绕过校验，也不要从另一配置或其他机器只复制部分 DLL。Brotli stage 是 OpenSSL 构建输入，其 provenance 和 CRT 必须整体匹配。
