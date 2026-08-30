# OpenSSL 构建脚本与项目 Skill 使用说明

> 适用分支：upgrade/v4.0.0
>
> 平台：Windows x64
>
> OpenSSL：openssl-3.5.7 / 8cf17aaeb4599f8af87fefd810b5b5fee90fe69e
>
> Brotli：v1.2.0 / 028fb5a23661f123017c060daa546b55cf4bde29
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK 10.0.26100.0
>
> 最后验证：2026-08-30，Debug 与 Release 最小构建和 safe 测试均通过

本文说明阶段 3 完成后的 OpenSSL 构建、测试、验证和 Skill 用法。构建逻辑只维护在 third_party\openssl\build.cmd；Codex 与 Claude Skill 只负责选择命令、监控和解释结果。

## 1. 目录结构

~~~text
SQLiteBrowser/
|- third_party/
|  |- openssl/
|     |- build.cmd
|     |- src/
|- .agents/
|  |- skills/
|     |- sqlitebrowser-build-openssl/
|        |- SKILL.md
|- .claude/
|  |- skills/
|     |- sqlitebrowser-build-openssl/
|        |- SKILL.md
|- output/
   |- x64-shared-debug/
   |  |- build/
   |     |- brotli/
   |     |  |- stage/
   |     |- openssl/
   |        |- work/
   |        |- stage/
   |- x64-shared-release/
      |- build/
         |- brotli/
         |  |- stage/
         |- openssl/
            |- work/
            |- stage/
~~~

work 是 OpenSSL Configure、NMake、中间对象和测试专用程序的私有目录。stage 是给上层构建消费的最小开发 stage。阶段 5 已通过 `third_party\aggregate.cmd` 把经过验证的文件汇总到配置级公共 `include/bin/metadata`；OpenSSL 脚本本身仍不会执行公共汇总或最终应用部署。

## 2. 前置条件

- Windows x64；
- Git 在 PATH；
- Visual Studio 2022 Enterprise、Professional 或 Community，安装在默认目录；
- Desktop development with C++、MSVC v143 x64/x86 tools；
- Windows SDK 10.0.26100.0；
- Windows 原生 Perl，推荐 Strawberry Perl；
- NASM 在 PATH；
- certutil.exe；
- full 测试还需要 Windows PowerShell；
- 对应配置的 Brotli stage 已完成并通过脚本验证。

脚本按以下顺序检查默认 VS 安装目录：

~~~text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
~~~

三个 VS 版本使用相同的 MSVC、SDK、NMake 和链接器接口，均受支持。脚本不扫描自定义 VS 安装目录，也不自动安装缺失工具。

为避免中文 Windows 下 Strawberry Perl 报不支持的 locale，脚本只在自身 setlocal 范围内设置：

~~~cmd
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
~~~

这些值不会永久改变调用者环境。

## 3. 初始化和环境检查

首次拉取：

~~~cmd
git submodule update --init --recursive
~~~

先构建匹配配置的 Brotli：

~~~cmd
third_party\brotli\build.cmd build all
third_party\openssl\build.cmd check all
~~~

也可以只检查单一配置：

~~~cmd
third_party\openssl\build.cmd check debug
third_party\openssl\build.cmd check release
~~~

check 只验证工具链、源码 revision、源码是否干净，以及匹配 Brotli stage，不运行 Configure、编译、安装或测试。

## 4. 命令模型

查看帮助：

~~~cmd
third_party\openssl\build.cmd --help
~~~

正式接口：

~~~cmd
third_party\openssl\build.cmd check [all|debug|release]
third_party\openssl\build.cmd build [all|debug|release]
third_party\openssl\build.cmd test <all|debug|release> [safe|full]
third_party\openssl\build.cmd clean [all|debug|release]
~~~

不带参数等价于：

~~~cmd
third_party\openssl\build.cmd build all
~~~

它只构建 Debug 和 Release 产品，不再隐式运行测试。

为兼容旧的配置优先调用，以下命令仍表示 build：

~~~cmd
third_party\openssl\build.cmd debug
third_party\openssl\build.cmd release
~~~

旧的 all safe、debug none 等混合参数不再是有效接口。构建和测试必须使用不同命令，避免普通产品构建的成功依赖本机网络测试状态。

## 5. 最小产品构建

推荐：

~~~cmd
third_party\openssl\build.cmd build debug
third_party\openssl\build.cmd build release
~~~

脚本执行的核心流程：

~~~text
Configure VC-WIN64A shared <debug-or-release>
  + enable-brotli-dynamic
  + no-demos
  + matching Brotli include/bin
    -> nmake build_libs
    -> 清理当前配置旧 stage
    -> nmake install_dev
    -> 复制匹配 Brotli 运行 DLL
    -> 写 build-manifest.txt
    -> 最小 stage、架构、CRT、导出和 DLL 身份验证
~~~

选择 build_libs 而不是默认 nmake，可避免把 CLI、provider module、engine 和测试当成产品 target。install_dev 安装运行库、公开头文件、import LIB 和 OpenSSL CMake package，不安装 openssl.exe、providers 或 engines。

OpenSSL 上游仍可能在 work 内生成内部静态辅助库和 test utility library；它们是 NMake 图的内部依赖，不会进入 stage 或后续公共 bin。

## 6. Stage 契约

Debug：

~~~text
output\x64-shared-debug\build\openssl\stage
~~~

Release：

~~~text
output\x64-shared-release\build\openssl\stage
~~~

核心内容：

~~~text
stage/
|- build-manifest.txt
|- test-manifest.txt                 # 只有 test 成功后存在
|- bin/
|  |- libcrypto-3-x64.dll
|  |- libcrypto-3-x64.pdb
|  |- libssl-3-x64.dll
|  |- libssl-3-x64.pdb
|  |- brotlicommon.dll
|  |- brotlidec.dll
|  |- brotlienc.dll
|- include/
|  |- openssl/
|- lib/
   |- libcrypto.lib
   |- libssl.lib
   |- cmake/
      |- OpenSSL/
         |- OpenSSLConfig.cmake
         |- OpenSSLConfigVersion.cmake
~~~

禁止进入 stage：

- openssl.exe；
- legacy.dll 或其他独立 provider module；
- engine DLL；
- test、fuzz、demo 和 example EXE；
- vc143.pdb 等 compiler PDB。

Debug 和 Release 都保留与 DLL 对应的 linker PDB。Release 仍使用优化配置，同时 OpenSSL 上游链接规则生成可调试的 PDB。

## 7. 构建验证

脚本验证：

- OpenSSL tag、commit 和干净子模块；
- VS edition、MSVC tools 和精确 SDK；
- x64 DLL；
- Debug/Release CRT 不混用；
- 公开头文件、import LIB、CMake package；
- stage 最小 allowlist 与禁止文件；
- matching Brotli stage 的 tag、commit、配置和 manifest；
- 三个 Brotli DLL 逐字节一致；
- configdata.pm 启用 Brotli dynamic；
- libcrypto 导出 COMP_brotli、COMP_brotli_oneshot、BIO_f_brotli；
- libcrypto 不直接导入 Brotli DLL，保持运行时动态加载；
- libssl 正确依赖 libcrypto。

build-manifest.txt 记录构建 provenance、配置选项、工具链、stage 路径和核心文件 SHA-256，并固定写入：

~~~text
Build target: build_libs
Install target: install_dev
Tests: not run
OpenSSL CLI staged: no
Providers staged: no
Engines staged: no
~~~

普通构建成功不能表述为测试通过。

## 8. 独立测试

### 8.1 Safe

~~~cmd
third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release safe
~~~

safe 流程：

1. 验证现有 build-manifest 和最小 stage；
2. 在 work 内构建测试专用 CLI、provider、fuzz 和测试 EXE；
3. 运行通用测试套件，但排除 test_bio_dgram；
4. 单独运行 test_bio_comp、test_cert_comp、test_tls13certcomp；
5. 不重新安装 stage 产品；
6. 写 stage\test-manifest.txt。

test_bio_dgram 可能受开发机 IPv6 UDP 回环过滤、VPN、TUN、代理或防火墙影响。safe 是项目开发机推荐模式，但必须报告为排除一项的部分通过。

### 8.2 Full

~~~cmd
third_party\openssl\build.cmd test release full
~~~

full 先执行 IPv6 UDP ::1 回环收发预检。预检失败时脚本退出，不会静默降级；预检通过后运行未过滤的完整套件和三个 Brotli 聚焦测试。

### 8.3 测试记录

test-manifest.txt 记录：

- OpenSSL tag 和 commit；
- 配置和 safe/full；
- 当前 build-manifest.txt 的 SHA-256；
- 通用套件结果和过滤条件；
- 三个 Brotli 聚焦测试结果。

重新执行 build 会重建 stage 并移除旧 test-manifest。重新执行 test 后才生成绑定新 build manifest 的记录。

2026-08-30 的实测：

| 配置 | 模式 | 通用套件 | Brotli 聚焦测试 | 结果 |
| --- | --- | --- | --- | --- |
| Debug | safe | 343 files / 4279 tests | 3 files / 11 tests | 全部通过，test_bio_dgram 排除 |
| Release | safe | 343 files / 4279 tests | 3 files / 11 tests | 全部通过，test_bio_dgram 排除 |

上游因 Windows、非 FIPS、locale 或外部测试未配置而标记的 SKIP 仍属于 OpenSSL 正常测试报告；项目额外排除项只有 safe 模式的 test_bio_dgram。

## 9. 清理

~~~cmd
third_party\openssl\build.cmd clean debug
third_party\openssl\build.cmd clean release
third_party\openssl\build.cmd clean all
~~~

清理只允许删除：

~~~text
output\x64-shared-<config>\build\openssl
~~~

以及构建时该目录下精确的 stage 子目录。脚本不会删除 output 根、另一个依赖、源码子模块或另一配置。

## 10. 使用 Codex Skill

显式调用：

~~~text
$sqlitebrowser-build-openssl 检查 Debug 和 Release 构建环境
~~~

~~~text
$sqlitebrowser-build-openssl 只构建 Debug 和 Release 最小产品，不运行测试
~~~

~~~text
$sqlitebrowser-build-openssl 对已有 Release 构建运行 safe 测试
~~~

~~~text
$sqlitebrowser-build-openssl 对 Release 运行 full 测试；IPv6 预检失败就停止
~~~

Skill 会区分只分析、构建和测试。用户只要求分析时，不得运行构建或修改文件。

## 11. 使用 Claude Code Skill

~~~text
/sqlitebrowser-build-openssl 检查构建环境
~~~

~~~text
/sqlitebrowser-build-openssl 构建全部配置，然后分别运行 safe 测试
~~~

.claude 下的入口只转发到 .agents 下的规范 Skill，构建规则只维护一份。

## 12. 当前部署边界

阶段 3 的部署终点是 OpenSSL 私有 stage。它还不是：

- output/x64-shared-<config>/bin 公共开发输出；
- SQLiteBrowser EXE 目录；
- ZIP、NSIS 或其他正式安装包。

后续应用运行时需要匹配配置的：

~~~text
libcrypto-3-x64.dll
libssl-3-x64.dll
brotlicommon.dll
brotlidec.dll
brotlienc.dll
~~~

五个 DLL 必须作为同一套运行时部署。openssl.exe、provider、engine、import LIB 和 PDB 不应无条件进入用户安装包。

## 13. 常见问题

### 找不到 Visual Studio 或 SDK

确认 VS2022 位于默认目录并安装 Desktop development with C++、MSVC v143 与 SDK 10.0.26100.0。

### 找不到 Perl 或 NASM

~~~cmd
where perl.exe
where nasm.exe
~~~

脚本不自动安装工具。

### Brotli stage 缺失

~~~cmd
third_party\brotli\build.cmd build debug
third_party\brotli\build.cmd build release
~~~

不要手工修改 manifest 或混用配置。

### Full 测试预检失败

检查 VPN、TUN、代理、防火墙和虚拟网络过滤器。开发机可使用 safe，但发布门禁需要明确决定是否接受排除项。

### 测试时出现 openssl.exe 或 legacy.dll

只要它们位于 work 内就是测试专用产物。若出现在 stage，脚本应判为失败。
