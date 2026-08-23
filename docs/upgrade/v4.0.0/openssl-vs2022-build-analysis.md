# OpenSSL 3.5.7 使用 Visual Studio 2022 构建分析

> 文档性质：构建方式与环境兼容性分析
>
> 分析日期：2026-08-23
>
> 源码位置：`third_party/openssl/src`
>
> 源码版本：`openssl-3.5.7` / `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`
>
> 目标平台：Windows x64
>
> 目标工具链：Visual Studio 2022、MSVC v143、Windows SDK 10.0.22621.0

本文只记录分析结论和推荐命令。本次分析没有执行 OpenSSL `Configure`、`nmake`、测试或安装，也没有修改 OpenSSL 子模块和项目构建配置。

## 1. 结论摘要

OpenSSL 3.5.7 的 Windows/MSVC 构建不是 Visual Studio 解决方案构建，也不是 CMake 构建。正确流程是：

```text
Visual Studio 2022 开发环境
        |
        v
Perl Configure VC-WIN64A
        |
        v
生成 Windows NMake Makefile 和配置头文件
        |
        v
nmake -> nmake test -> nmake install
```

Visual Studio 在这里提供的是 `cl.exe`、`link.exe`、`lib.exe`、`nmake.exe`、Windows SDK 头文件和库。OpenSSL 自己的 Perl 构建系统负责读取 `build.info` 并生成最终 Makefile。

对当前 SQLiteBrowser 升级分支，建议采用：

- OpenSSL 目标：`VC-WIN64A`；
- 架构：x64 host 构建 x64 target；
- 库类型：`shared`；
- Release：`/MD`；
- Debug：`/MDd`；
- Windows SDK：显式选择 `10.0.22621.0`；
- Release 和 Debug 使用完全独立的源码外构建目录；
- 安装到项目构建树中的配置专用 stage，不安装到系统目录；
- SQLiteBrowser、SQLCipher 和 Qt OpenSSL TLS backend 统一消费该 stage。

## 2. 分析基线

### 2.1 OpenSSL 子模块

当前父仓库记录的 OpenSSL 子模块为：

```text
tag:    openssl-3.5.7
commit: 8cf17aaeb4599f8af87fefd810b5b5fee90fe69e
path:   third_party/openssl/src
```

分析时父仓库和 OpenSSL 子模块工作区均为干净状态。

### 2.2 本机环境

只读检查得到：

| 组件 | 检测结果 | 结论 |
|---|---|---|
| Visual Studio | Enterprise 2022 17.14.37 | 可用 |
| MSVC 编译器 | 19.44.35228 | 可用 |
| MSVC 工具集 | v143 / 14.44.35207 | 可用 |
| Windows SDK | 10.0.22621.0 | 可用，必须显式选择 |
| Strawberry Perl | 5.38.2 x64 | 可用 |
| NASM | 2.16.03 x64 | 可用 |
| CMake | 3.30.3 | 项目 superbuild 可用，OpenSSL 本身不使用它构建 |

普通终端中没有 `cl.exe` 和 `nmake.exe`。运行 VS2022 的 `VsDevCmd.bat` 后可以正确找到二者，并且可以把 host、target 和 SDK 固定为：

```text
VSCMD_ARG_HOST_ARCH=x64
VSCMD_ARG_TGT_ARCH=x64
VSCMD_ARG_winsdk=10.0.22621.0
WindowsSDKVersion=10.0.22621.0\
VCToolsVersion=14.44.35207
```

这说明当前阻塞点不是工具缺失，而是每次构建都必须先初始化正确的 VS 开发环境。

## 3. 重点文件分析

### 3.1 `build.info`

文件：[`third_party/openssl/src/build.info`](../../../third_party/openssl/src/build.info)

顶层 `build.info` 是 OpenSSL 内部的声明式构建依赖图，不是用户直接执行的脚本，也不是 CMakeLists。

它定义的主要内容包括：

- 子目录：`crypto`、`ssl`、`apps`、`util`、`tools`、`fuzz`、`providers`、`doc` 和 `exporters`；
- 测试目录仅在没有禁用 tests 时加入；
- demos 目录仅在没有禁用 demos 时加入；
- `libcrypto` 和 `libssl` 两个顶层库；
- `libssl` 对 `libcrypto` 的依赖；
- 从 `.in` 模板生成大量公开和内部头文件；
- 为 Windows/MSVC 目标生成 `libcrypto.rc`、`libssl.rc`；
- 生成构建树使用的 `OpenSSLConfig.cmake`、`OpenSSLConfigVersion.cmake`；
- 生成 pkg-config 和构建变量文件。

由此得到四个重要结论：

1. 不能只把源码树中的 `include` 目录交给 SQLiteBrowser。

   部分必要头文件要在 `Configure` 阶段生成。项目应消费已经配置的构建树，或更稳妥地消费安装后的 stage。

2. `OpenSSLConfig.cmake` 是给下游项目消费 OpenSSL 的包配置，不代表 OpenSSL 自身使用 CMake 构建。

3. `build.info` 不选择 VS 版本、MSVC 工具集或 Windows SDK。这些信息来自执行 `Configure` 时的进程环境。

4. 当前不需要、也不应修改 OpenSSL 子模块中的 `build.info`。未来的封装文件应放在 `third_party/openssl/` 父目录或项目 superbuild 中。

### 3.2 `NOTES-WINDOWS.md`

文件：[`third_party/openssl/src/NOTES-WINDOWS.md`](../../../third_party/openssl/src/NOTES-WINDOWS.md)

该文件是 Windows 原生构建的主要平台说明。对当前任务最相关的要求是：

- MSVC 原生目标使用 `VC-*` 前缀；
- 推荐 Strawberry Perl；
- NASM 是受支持的汇编器；
- Perl 和 NASM 必须在 PATH；
- 必须从 Visual Studio Developer Command Prompt 或加载 `vcvarsall.bat`/`VsDevCmd.bat` 的命令行构建；
- x64 Windows 使用 `VC-WIN64A`；
- 构建顺序是 `Configure`、`nmake`、`nmake test`、`nmake install`。

`VC-WIN64A-HYBRIDCRT` 不是当前项目的默认选择。当前 Qt、SQLCipher 和 SQLiteBrowser 计划按普通 MSVC CRT 模型统一，使用标准 `VC-WIN64A` 更清晰。

`NOTES-WINDOWS.md` 还讨论了注册表路径 `OSSL_WINCTX`。当前项目采用应用本地 stage 和安装包部署，不应定义 `OSSL_WINCTX`，以免把运行时行为绑定到开发机注册表。

静态链接 OpenSSL 时还需要额外链接多个 Windows 系统库，并处理静态 CRT、库固定和 Applink 等问题。当前项目希望 Qt TLS backend 与 SQLCipher 共用同一套 OpenSSL 运行时，因此优先使用 shared 构建。

### 3.3 `README.md`

文件：[`third_party/openssl/src/README.md`](../../../third_party/openssl/src/README.md)

README 是项目总览和文档导航，不是完整构建手册。它明确要求结合：

- `INSTALL.md`：通用构建、配置、测试和安装说明；
- `NOTES-WINDOWS.md`：Windows 平台补充说明；
- `NOTES-PERL.md`：Perl 要求；
- `README-FIPS.md`：需要 FIPS 时的独立说明。

README 对当前方案的意义是确认构建流程必须以 OpenSSL 自带文档为准，不能把第三方预编译包的目录布局或构建参数当成源码构建标准。

### 3.4 `INSTALL.md` 的补充结论

文件：[`third_party/openssl/src/INSTALL.md`](../../../third_party/openssl/src/INSTALL.md)

虽然它不在最初指定的三个重点文件内，但 `README.md` 和 `NOTES-WINDOWS.md` 都明确引用它。与当前方案直接相关的内容包括：

- OpenSSL 官方支持源码外构建；
- `--release` 是默认构建类型，但建议显式写出；
- `--debug` 会关闭优化并生成调试构建；
- `--prefix` 控制安装根目录；
- `--openssldir` 控制配置、证书和私钥默认目录；
- `--libdir=lib` 可以避免不同 target 自动形成不同库目录名；
- `no-shared` 表示只构建静态库；
- `no-makedepend` 可以加速总是从空目录开始的构建；
- Windows 使用 `nmake`、`nmake test`、`nmake install`；
- 测试必须使用非特权账户运行。

因此，本项目不需要管理员 Developer Command Prompt。把 `--prefix` 指向用户可写的项目 build 目录后，应使用普通非管理员终端构建和测试。

## 4. Visual Studio 2022 版本支持

### 4.1 名称说明

Microsoft 官方的 Visual Studio 2022 完整 IDE 版本名称是：

- Enterprise；
- Professional；
- Community。

Microsoft 没有名为“Commercial”的独立版本。如果“商业版”指最高级付费版本，本文将其对应为 Enterprise；如果“商业版”泛指付费版本，则同时包括 Enterprise 和 Professional。

### 4.2 技术支持矩阵

| VS2022 版本 | OpenSSL 3.5.7 x64 构建 | 所需组件 | 推荐用途 | 主要差异 |
|---|---|---|---|---|
| Enterprise | 支持 | Desktop development with C++、MSVC v143 x64/x86、SDK 10.0.22621.0 | 企业开发、正式发布、受控 CI | IDE 企业功能和许可；可使用受支持的 LTSC/Current 通道 |
| Professional | 支持 | 同上 | 商业开发、正式发布、受控 CI | IDE 功能和许可少于 Enterprise；编译器构建能力相同 |
| Community | 支持 | 同上 | 个人开发、开源贡献、符合许可条件的团队 | 编译器构建能力相同；许可范围和维护通道不同 |

对 OpenSSL 构建而言，版本名称本身不进入二进制 ABI。真正影响产物的是：

- MSVC toolset 版本；
- 编译器补丁版本；
- Windows SDK 版本；
- host/target 架构；
- OpenSSL Configure target 和选项；
- CRT 选择；
- NASM、Perl 和源码 commit。

因此，同样安装 MSVC v143 和 SDK 10.0.22621.0 时，Enterprise、Professional、Community 都能执行同一套 OpenSSL 构建命令。不同版本或不同编译器补丁通常保持 MSVC ABI 兼容，但不保证生成逐字节相同的二进制。正式发布仍应记录完整工具版本。

### 4.3 Community 版本的维护与许可边界

Community 在技术上能够完成全部 OpenSSL 构建步骤，包括 `cl`、`link`、`lib`、`nmake` 和 Windows SDK 资源编译。

Microsoft 当前生命周期策略指出，Community 只在 Current Channel 的最新维护版本上受支持；Enterprise 和 Professional 还可以使用相应的 LTSC/Current 策略。因此，如果发布流程要求长期冻结一个 VS 小版本，Enterprise、Professional 或受控 Build Tools 环境通常更方便；使用 Community 时应接受更频繁的维护升级，并在每次发布记录实际 `VCToolsVersion`。

Community 的使用还受 Microsoft 许可条款约束。Microsoft 当前许可资料允许个人开发者使用，并对开源项目贡献提供组织场景许可；其他组织和商业使用存在人数及企业规模限制。SQLiteBrowser fork 如果以后加入闭源模块或改变使用场景，应重新检查当时有效的许可条款。本文只记录工程风险，不构成法律意见。

### 4.4 必需的安装组件

无论使用哪个版本，都至少需要：

```text
Desktop development with C++
MSVC v143 - VS 2022 C++ x64/x86 build tools
Windows 11 SDK 10.0.22621.0
```

说明：Visual Studio Installer 中该 SDK 的组件名称包含“Windows 11 SDK”，但其版本号就是项目要求的 `10.0.22621.0`，仍可用于构建目标 Windows 桌面程序。

OpenSSL 本身不要求 MFC、ATL、Visual Studio CMake tools 或完整 IDE。自动化 CI 未来也可以评估 Visual Studio Build Tools，但 Build Tools 的许可、安装和发布环境应作为单独决策；本节的承诺范围是用户指定的三个完整 IDE 版本。

## 5. 不应硬编码 Visual Studio 版本路径

三个完整 IDE 的默认路径分别为：

```text
C:\Program Files\Microsoft Visual Studio\2022\Enterprise
C:\Program Files\Microsoft Visual Studio\2022\Professional
C:\Program Files\Microsoft Visual Studio\2022\Community
```

本机实际安装的是 Enterprise，所以手工验证可以直接调用：

```cmd
call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat" ^
  -arch=x64 ^
  -host_arch=x64 ^
  -winsdk=10.0.22621.0
```

但项目脚本不能硬编码 `Enterprise`，否则在 Professional 和 Community 环境会失败。应使用 Visual Studio Installer 自带的 `vswhere.exe` 自动发现安装实例。

## 6. 版本无关的 VS2022 环境初始化

### 6.1 推荐的批处理逻辑

以下内容适合未来写入 `.cmd` 或 `.bat`；当前尚未创建脚本：

```cmd
@echo off
setlocal

rem Use the locale that Strawberry Perl always supports on Windows.
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VSINSTALL="

if not exist "%VSWHERE%" (
  echo ERROR: vswhere.exe was not found.
  exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" ^
  -latest -products * -version "[17.0,18.0)" ^
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
            Microsoft.VisualStudio.Component.Windows11SDK.22621 ^
  -property installationPath`) do set "VSINSTALL=%%i"

if not defined VSINSTALL (
  echo ERROR: No compatible Visual Studio 2022 installation was found.
  exit /b 1
)

call "%VSINSTALL%\Common7\Tools\VsDevCmd.bat" ^
  -arch=x64 ^
  -host_arch=x64 ^
  -winsdk=10.0.22621.0

if errorlevel 1 exit /b 1

where cl.exe
if errorlevel 1 exit /b 1

where nmake.exe
if errorlevel 1 exit /b 1

if /i not "%VSCMD_ARG_TGT_ARCH%"=="x64" (
  echo ERROR: Visual Studio target architecture is not x64.
  exit /b 1
)

if /i not "%WindowsSDKVersion%"=="10.0.22621.0\" (
  echo ERROR: Windows SDK 10.0.22621.0 was not selected.
  exit /b 1
)
```

这个查找条件同时实现：

- 只选择 Visual Studio 2022，即版本范围 `[17.0,18.0)`；
- 接受 Enterprise、Professional、Community；
- `-products *` 也允许未来评估 Build Tools；
- 要求安装 x64/x86 MSVC 组件；
- 要求安装准确的 SDK 22621 组件；
- 不依赖默认安装目录和版本名称。

如果同一台机器安装多个满足条件的实例，`-latest` 会选择版本最高的实例。正式发布环境应记录选择结果，并视可重复构建要求决定是否进一步固定实例 ID 或 MSVC toolset 版本。

## 7. OpenSSL 依赖环境验证

加载 VS 开发环境后，应在执行 `Configure` 前验证：

```cmd
where cl.exe
where link.exe
where lib.exe
where nmake.exe
where rc.exe
where perl.exe
where nasm.exe

cl.exe
perl.exe -v
nasm.exe -v

set VSCMD_ARG_
set WindowsSDK
set VCToolsVersion
```

最低验收条件：

- `cl.exe` 来自 Visual Studio 2022 的 x64 host/x64 target 路径；
- `nmake.exe` 与 `cl.exe` 来自同一 VS 实例；
- `rc.exe` 来自 `10.0.22621.0\x64` SDK 路径；
- `WindowsSDKVersion=10.0.22621.0\`；
- Perl 是 Windows 原生 Strawberry Perl；
- NASM 是可执行的 x64 Windows 版本。

### 7.1 Strawberry Perl locale 修复

当前环境已经复现以下错误：

```text
Locale 'Chinese (Simplified)_China.936' is unsupported, and may crash the interpreter.
```

触发过程是：

1. 自动化终端向 Windows 进程传入 `LC_ALL=C.UTF-8`、`LANG=C.UTF-8`；
2. 当前 Strawberry Perl 5.38.2 不支持名为 `C.UTF-8` 的 Windows locale；
3. Perl 回退到系统 locale `Chinese (Simplified)_China.936`；
4. 当前 Perl locale 层同样不接受该 Windows 区域名称，因此发出可能崩溃的警告。

只清空 `LC_ALL` 和 `LANG` 不能可靠修复，因为这会重新触发第 3 步。正确做法是在当前构建脚本的 `setlocal` 作用域内显式固定为标准 `C` locale：

```cmd
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
```

设置后可以在执行 `Configure` 前验证：

```cmd
perl -MPOSIX=setlocale,LC_ALL -e "print setlocale(LC_ALL), qq(\n)"
if errorlevel 1 exit /b 1
```

预期输出：

```text
C
```

本机只读验证确认：使用上述设置后，Strawberry Perl 返回 locale `C`，且不再输出 locale 警告。

不要通过设置 `PERL_BADLANG=0` 解决。该变量只会隐藏诊断信息，不能把不支持的 locale 变成受支持状态，也不能消除潜在运行风险。

`C` locale 只影响当前构建子进程中 Perl 和相关命令行工具的区域行为，不会改变 SQLiteBrowser 的界面语言和最终应用的 Windows 本地化行为。`setlocal` 会在脚本结束时恢复调用者环境。

不能忽略该警告后直接进入正式构建。验收条件应包括：locale 检查输出 `C`、`perl -v` 无 locale 警告、`perl Configure` 正常完成。

## 8. 推荐目录布局

必须使用源码外构建，保持 Git submodule 干净：

```text
SQLiteBrowser/
|- third_party/
|  |- openssl/
|     |- src/                     # 固定上游源码，只读使用
|- build/
   |- openssl/
      |- x64-release/
      |  |- work/                 # Configure 和 nmake 工作目录
      |  |- stage/                # Release 安装结果
      |- x64-debug/
         |- work/                 # 独立 Debug 工作目录
         |- stage/                # Debug 安装结果
```

项目 `.gitignore` 已通过 `build*/` 忽略上述构建树。不能把 Makefile、生成头文件、对象文件或安装产物写入 `third_party/openssl/src`。

## 9. Release x64 推荐流程

以下命令是待实施方案，本次没有执行：

```cmd
call "%VSINSTALL%\Common7\Tools\VsDevCmd.bat" ^
  -arch=x64 ^
  -host_arch=x64 ^
  -winsdk=10.0.22621.0

set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="

perl -MPOSIX=setlocale,LC_ALL -e "print setlocale(LC_ALL), qq(\n)"
if errorlevel 1 exit /b 1

set "PROJECT_ROOT=F:\open-source\SQLiteBrowser"
set "OPENSSL_SRC=%PROJECT_ROOT%\third_party\openssl\src"
set "OPENSSL_BUILD=%PROJECT_ROOT%\build\openssl\x64-release"
set "OPENSSL_STAGE=%OPENSSL_BUILD%\stage"

if not exist "%OPENSSL_BUILD%\work" mkdir "%OPENSSL_BUILD%\work"
pushd "%OPENSSL_BUILD%\work"

perl "%OPENSSL_SRC%\Configure" VC-WIN64A ^
  shared ^
  --release ^
  --prefix="%OPENSSL_STAGE%" ^
  --openssldir="%OPENSSL_STAGE%\ssl" ^
  --libdir=lib ^
  no-demos

if errorlevel 1 exit /b 1

nmake
if errorlevel 1 exit /b 1

nmake test
if errorlevel 1 exit /b 1

nmake install_sw
if errorlevel 1 exit /b 1

nmake install_ssldirs
if errorlevel 1 exit /b 1

popd
```

配置参数含义：

| 参数 | 作用 | 选择理由 |
|---|---|---|
| `VC-WIN64A` | MSVC Windows x64 | 对应当前目标平台 |
| `shared` | 构建 DLL 和导入库 | 让 Qt 和 SQLCipher 共用一套 OpenSSL 运行时 |
| `--release` | Release 优化构建 | 显式记录配置，避免依赖默认值 |
| `--prefix` | 固定安装 stage | 防止写入系统目录 |
| `--openssldir` | 固定配置/证书目录 | 避免依赖注册表或系统 OpenSSL |
| `--libdir=lib` | 固定库目录名 | 简化下游 CMake 和部署逻辑 |
| `no-demos` | 不构建 demos | demos 不是产品依赖，测试仍保留 |

首个可验证版本不建议使用 `no-makedepend`。它适合每次从空构建目录开始的 CI，可缩短构建时间；用于开发者增量构建时可能降低源码或头文件变化后的依赖可靠性。

## 10. Debug x64 推荐流程

OpenSSL 的 NMake 构建不是多配置工程。Debug 不能复用 Release 的 work 或 stage。

Debug 配置应改为：

```cmd
set "OPENSSL_BUILD=%PROJECT_ROOT%\build\openssl\x64-debug"
set "OPENSSL_STAGE=%OPENSSL_BUILD%\stage"

set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="

perl "%OPENSSL_SRC%\Configure" VC-WIN64A ^
  shared ^
  --debug ^
  --prefix="%OPENSSL_STAGE%" ^
  --openssldir="%OPENSSL_STAGE%\ssl" ^
  --libdir=lib ^
  no-demos
```

然后在 Debug work 目录执行相同的：

```cmd
nmake
nmake test
nmake install_sw
nmake install_ssldirs
```

OpenSSL 的 Windows 配置对 shared Release 使用 `/MD`，对 shared Debug 使用 `/MDd`。SQLCipher 和 SQLiteBrowser 必须按相同配置链接，不能把 Release OpenSSL DLL 放入 Debug PATH，也不能把 Debug import library 提供给 Release 链接器。

## 11. 预计 stage 产物

Release stage 预计形成：

```text
stage/
|- bin/
|  |- openssl.exe
|  |- libcrypto-3-x64.dll
|  |- libssl-3-x64.dll
|- include/
|  |- openssl/
|- lib/
|  |- libcrypto.lib
|  |- libssl.lib
|  |- cmake/
|  |- engines-3/
|  |- ossl-modules/
|- ssl/
```

具体模块和配置文件以实际 `Configure` 结果为准。下游关系为：

```text
SQLCipher                -> libcrypto
Qt OpenSSL TLS backend   -> libssl + libcrypto
SQLiteBrowser installer  -> 同一 stage 的 OpenSSL DLL 和所需 provider/module
```

不能把系统 `C:\Program Files\OpenSSL-Win64` 中的 OpenSSL 4 文件加入 include、lib 或运行 PATH 回退。

## 12. 构建后验证要求

仅有 `nmake` 返回成功不够。建议至少执行：

```cmd
perl configdata.pm --dump
nmake test
"%OPENSSL_STAGE%\bin\openssl.exe" version -a
"%OPENSSL_STAGE%\bin\openssl.exe" list -providers
dumpbin /dependents "%OPENSSL_STAGE%\bin\libcrypto-3-x64.dll"
dumpbin /dependents "%OPENSSL_STAGE%\bin\libssl-3-x64.dll"
git -C "%OPENSSL_SRC%" status --short
```

验收内容包括：

- target 是 `VC-WIN64A`；
- 编译器来自预期 VS2022 实例；
- SDK 是 10.0.22621.0；
- OpenSSL 版本是 3.5.7；
- Release/Debug CRT 与下游一致；
- `nmake test` 全部通过；
- stage 中的程序只加载同一 stage 的 OpenSSL DLL；
- provider/module 能从安装后的相对目录加载；
- OpenSSL 子模块保持干净；
- 干净 Windows 测试机不依赖开发机 PATH 和注册表。

建议为每次正式构建记录：

```text
Visual Studio productId
Visual Studio display version
VCToolsVersion
cl.exe version
WindowsSDKVersion
Perl version
Perl locale (`LC_ALL=C`, `LANG=C`)
NASM version
OpenSSL tag and commit
Configure command line
configdata.pm dump
test result
```

## 13. shared 与 static 选择

### 13.1 推荐 shared

shared 的主要优点是：

- Qt TLS backend 和 SQLCipher 可以使用同一 `libcrypto`；
- Release `/MD`、Debug `/MDd` 与主项目容易对齐；
- 安装包可以显式审计 DLL 版本；
- 安全补丁更新可以集中替换并重新验证；
- 避免多个静态 OpenSSL 副本进入同一进程。

### 13.2 当前不推荐 static

`no-shared` 会只构建静态库。Windows 静态链接还需要处理：

- `WS2_32.LIB`、`GDI32.LIB`、`ADVAPI32.LIB`、`CRYPT32.LIB`、`USER32.LIB`；
- `no-pinshared` 等静态库行为；
- CRT 和 `/Zl` 行为；
- Qt plugin 与 SQLCipher 可能各自带入 OpenSSL 副本；
- 更复杂的许可证清单和安全更新定位。

除非后续有明确的单文件部署或静态链接需求，否则不应把 static 作为 v4.0.0 第一阶段目标。

## 14. Applink 和下游 CMake

OpenSSL Windows shared 构建涉及 `OPENSSL_Applink`。OpenSSL 3.5.7 会生成 CMake package 配置，并提供相应的 `OpenSSL::applink` target。

后续集成时应优先消费 OpenSSL 安装后的 CMake package 或项目统一定义的 imported target，而不是在多个目标中手工包含 `ms/applink.c`。同一个最终程序中重复编译 Applink 可能产生符号和运行时边界问题。

OpenSSL 不能通过以下方式直接加入 SQLiteBrowser：

```cmake
add_subdirectory(third_party/openssl/src)
```

未来应使用 CMake `ExternalProject`、自定义构建步骤或独立 bootstrap 脚本封装上述 `Configure`/`nmake` 流程，再让 SQLiteBrowser 和 SQLCipher 消费统一 stage。

## 15. FIPS 边界

普通命令：

```cmd
perl Configure VC-WIN64A shared
```

不会构建或启用 FIPS provider。

即使加入 `enable-fips`，也不能仅凭本地源码构建宣称获得 FIPS 认证。需要 FIPS 时必须选择 OpenSSL 官方列出的有效验证模块版本，严格遵循相应 Security Policy，并审计应用是否只使用获准算法和参数。

当前 v4.0.0 的依赖升级目标不包含 FIPS 合规。FIPS 应作为独立需求和独立验收流程，不能顺便加入普通 OpenSSL 构建。

## 16. 风险清单

| 风险 | 后果 | 建议 |
|---|---|---|
| 普通终端直接运行 Configure | 找不到 `cl`/`nmake` 或选择错误架构 | 统一通过 `VsDevCmd.bat` 入口 |
| 硬编码 Enterprise 路径 | Professional/Community 构建失败 | 使用 `vswhere` |
| 未校验 VS 主版本 | 可能选择 VS2019 或未来主版本 | 限定 `[17.0,18.0)` |
| 未校验 SDK | 多 SDK 环境发生无意漂移 | `-winsdk=10.0.22621.0` 并检查环境变量 |
| Strawberry Perl 使用不支持的 locale | Configure 警告、行为不确定或进程崩溃 | 在 `setlocal` 中固定 `LC_ALL=C`、`LANG=C` 并验证输出 |
| 只记录 VS 版本名称 | 不同 toolset patch 产物不一致 | 记录 `VCToolsVersion` 和 `cl` 版本 |
| 在源码目录构建 | 污染子模块、难以清理 | 强制源码外 work/stage |
| Release/Debug 复用目录 | 目标和 CRT 混合 | 独立 work 和 stage |
| 使用 `no-asm` 进入发布 | 性能下降 | 仅排错时临时使用 |
| 过早使用 `no-makedepend` | 增量构建可能遗漏依赖 | 首次验证阶段不启用 |
| 管理员权限运行测试 | 违反 OpenSSL 测试安全建议 | 使用普通用户和可写 prefix |
| 依赖系统 OpenSSL/注册表 | 开发机可用、干净机器失败 | 应用本地 stage，避免 `OSSL_WINCTX` |
| Community 许可或通道理解错误 | 合规或可复现性风险 | 发布前复核当前 Microsoft 条款和工具版本 |

## 17. 分阶段实施建议

### 阶段 A：手工验证

1. 使用 `vswhere` 找到 VS2022；
2. 加载 x64 + SDK 10.0.22621.0 环境；
3. 固定 `LC_ALL=C`、`LANG=C` 并确认 Perl locale 输出 `C`；
4. 验证 Perl 和 NASM；
5. 在空的 Release work 目录执行 Configure；
6. 完成 `nmake` 和 `nmake test`；
7. 安装到 Release stage；
8. 验证版本、DLL 依赖和 provider；
9. 确认子模块干净。

### 阶段 B：下游验证

1. 使用 Release stage 构建 SQLCipher；
2. 验证 SQLCipher 只链接该 `libcrypto-3-x64.dll`；
3. 让 Qt TLS backend 使用同一 stage；
4. 验证 SQLiteBrowser 启动和加密数据库操作；
5. 在干净 Windows 环境测试运行时部署。

### 阶段 C：自动化

1. 将 VS 发现和环境校验封装成项目脚本；
2. 将 OpenSSL 封装为 ExternalProject 或等价 superbuild 步骤；
3. 增加 Release preset；
4. 完成 Debug 独立构建；
5. 在 CI 中记录工具链和 `configdata.pm`；
6. 再评估是否使用 `no-makedepend` 优化全新构建。

## 18. 最终建议

建议把 OpenSSL 3.5.7 的 Windows 构建定义为“VS2022 工具链驱动的 OpenSSL 原生 Perl/NMake 构建”，而不是“Visual Studio 工程构建”或“CMake 子目录构建”。

Enterprise、Professional 和 Community 都应列为技术上受支持的 VS2022 版本，前提是安装相同的 MSVC v143 x64/x86 工具和 Windows SDK 10.0.22621.0。项目脚本必须通过 `vswhere` 发现环境，不得硬编码版本目录。

正式发布是否可重复，不应以 IDE 版本名称判断，而应以 OpenSSL commit、Configure 参数、MSVC toolset、编译器版本、SDK、Perl、NASM和测试结果判断。

第一项实施工作应是创建一个版本无关的 VS2022 环境初始化脚本，并完成一次 Release x64 手工闭环。在该闭环通过前，不建议修改主工程 CMake、SQLCipher 构建或安装包。

## 19. 参考资料

OpenSSL 3.5.7 仓库内文档：

- [`build.info`](../../../third_party/openssl/src/build.info)
- [`NOTES-WINDOWS.md`](../../../third_party/openssl/src/NOTES-WINDOWS.md)
- [`README.md`](../../../third_party/openssl/src/README.md)
- [`INSTALL.md`](../../../third_party/openssl/src/INSTALL.md)
- [`NOTES-PERL.md`](../../../third_party/openssl/src/NOTES-PERL.md)
- [`README-FIPS.md`](../../../third_party/openssl/src/README-FIPS.md)

Microsoft 官方资料：

- [Visual Studio 2022 lifecycle and supported editions](https://learn.microsoft.com/en-us/lifecycle/products/visual-studio-2022)
- [Visual Studio 2022 release history and servicing channels](https://learn.microsoft.com/en-us/visualstudio/releases/2022/release-history)
- [Install the Microsoft C++ build tools](https://learn.microsoft.com/en-us/cpp/overview/acquire-msvc?view=msvc-170)
- [Visual Studio licensing terms directory](https://visualstudio.microsoft.com/license-terms/)
- [Visual Studio Community 2022 license terms](https://visualstudio.microsoft.com/license-terms/vs2022-ga-community/)
- [Microsoft `vswhere`: Find VC](https://github.com/microsoft/vswhere/wiki/Find-VC)
- [Microsoft `vswhere` examples](https://github.com/microsoft/vswhere/wiki/Examples)
