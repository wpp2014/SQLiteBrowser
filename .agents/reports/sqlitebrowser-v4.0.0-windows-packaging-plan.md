# SQLiteBrowser v4.0.0 Windows 打包实施方案

> 整合日期：2026-09-05
>
> 当前分支：`upgrade/v4.0.0`
>
> 目标平台：Windows x64
>
> 状态：ZIP、NSIS portable SFX 与 WiX MSI 已完成本机构建和解包验证；签名及干净机发布门禁尚未实施

本文合并并取代原来的 MSI/ZIP 总方案、NSIS 迁移方案和 WiX MSI 修订方案。
冲突内容以已经落地的工程和验证结果为准。

## 1. 最终结论

Windows v4 打包采用一份严格 Release runtime、多个独立封装器：

```text
validated Release package/runtime
                |
                +--> CMake ZIP archive ----------> .zip
                |
                +--> SDK-style WiX 7 project ----> .msi
                |
                `--> NSIS extraction-only SFX ---> -portable.exe
```

职责边界：

- CMake 构建应用、组装 Release runtime、运行测试并验证 manifest；
- ZIP 只归档已经验证的 runtime，不经过 MSI 或旧 `install()` 规则；
- WiX 独立拥有 MSI 产品身份、安装目录、UI、升级和卸载行为；
- NSIS 只生成选择目录后解压的 portable SFX，不生成 MSI，也不包装 MSI；
- 正常 `release` 构建不隐式运行测试或制作安装包；
- ZIP、MSI 和 SFX 都不得重新从 Qt、依赖 stage、Visual Studio 或 `PATH`
  搜集 DLL。

不再采用：

- CPack WIX 作为 Windows v4 MSI 主实现；
- WiX 3 的 `candle.exe`、`light.exe` 和 `%WIX%\bin`；
- 从 MSI administrative image 反向生成 ZIP；
- NSIS setup wrapper 包装 MSI；
- MSI custom action 自动运行旧 NSIS uninstaller。

## 2. 固定环境与工具

| 项目 | 当前契约 |
| --- | --- |
| Visual Studio | 2022，默认安装目录，MSVC v143 |
| Windows SDK | 10.0.26100.0 |
| CMake | 3.30.3 |
| Qt | 6.11.1 `msvc2022_64`，路径只写入本地 `CMakePresets.json` |
| WiX | `WixToolset.Sdk` 7.0.0 |
| WiX UI extension | `WixToolset.UI.wixext` 7.0.0 |
| NSIS | 3.12，默认路径 `C:\Program Files (x86)\NSIS\makensis.exe` |
| 架构/配置 | x64、Release 正式包 |

WiX 使用 SDK-style `.wixproj`，由 Visual Studio 2022 MSBuild 从 NuGet 恢复固定
版本，不要求全局安装 `wix.exe` 或 Visual Studio HeatWave 扩展。仓库提交
`packages.lock.json`，CI 应使用 locked restore 和受信任的 NuGet 源。

WiX 7 OSMF EULA 必须由有权代表个人或组织的开发者明确审阅和接受。仓库不会
自动设置 `AcceptEula`。本机已在用户确认后执行过接受命令，但该用户级状态不写
入项目文件。新开发机需要按
[Windows v4 构建指南](../../docs/windows-v4-build-guide.md)重新完成该步骤。

## 3. 产品与版本契约

| 字段 | 当前值或规则 |
| --- | --- |
| 产品名称 | `DB Browser for SQLCipher` |
| 文件名前缀 | `DB.Browser.for.SQLCipher` |
| 版本源 | 根 `project(... VERSION 4.0.0)` |
| MSI 版本 | `4.0.0`，严格三段数字 |
| Manufacturer | `DB Browser for SQLite Team`，发布前仍需 fork 维护者确认 |
| Architecture | x64 only |
| MSI scope | per-machine |
| MSI 安装目录 | 64 位 Program Files 下的 `DB Browser for SQLCipher` |
| ZIP 顶层目录 | `DB Browser for SQLCipher` |
| Downgrade | 拒绝 |
| ProductCode | 每个正式 MSI 自动生成 |
| UpgradeCode | `124623D9-35D6-4D2E-9474-2ADACC8BABBB`，必须用真实旧 MSI 复核 |

仓库历史上还出现过 `78c885a7-e9c8-4ded-9b62-9abe47466950`。它不作为当前
默认值。发布前必须决定本 fork 是替换上游产品还是与其并存；如果产品身份独立，
应改用新的 Manufacturer、产品标识和 UpgradeCode，避免误升级或卸载其他发行版。

文件名：

```text
DB.Browser.for.SQLCipher-4.0.0-win-x64.zip
DB.Browser.for.SQLCipher-4.0.0-win-x64.msi
DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe
```

## 4. 唯一载荷与输出结构

当前唯一应用文件输入是：

```text
output/x64-shared-release/package/runtime/
```

它由显式 allowlist 组装，当前包含 70 个文件。每个相对路径及 SHA-256 写入：

```text
output/x64-shared-release/package/metadata/runtime-manifest.txt
```

禁止从下列位置补文件：

- development `bin/`；
- Debug 输出；
- Qt 安装目录；
- OpenSSL、SQLCipher、Brotli、zlib 或 zstd stage；
- Visual Studio redist 目录；
- 系统目录或 `PATH`。

当前实际输出结构：

```text
output/x64-shared-release/package/
├─ runtime/                              ZIP/SFX/MSI 唯一应用文件输入
├─ metadata/
│  ├─ runtime-manifest.txt
│  ├─ zip-manifest.txt
│  ├─ portable-sfx-manifest.txt
│  └─ msi-manifest.txt
├─ artifacts/
│  ├─ DB.Browser.for.SQLCipher-4.0.0-win-x64.zip
│  ├─ DB.Browser.for.SQLCipher-4.0.0-win-x64.zip.sha256
│  ├─ DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe
│  ├─ DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe.sha256
│  ├─ DB.Browser.for.SQLCipher-4.0.0-win-x64.msi
│  └─ DB.Browser.for.SQLCipher-4.0.0-win-x64.wixpdb
├─ build/
│  ├─ zip/
│  ├─ nsis-portable/
│  └─ wix/
└─ verify/
   ├─ zip/
   ├─ portable-sfx/
   └─ msi-admin-image/
```

`package/build` 和 `package/verify` 是可重建的验证产物；`artifacts` 和
`metadata` 保存当前未签名候选包及可追踪信息。

## 5. Release runtime 的发布缺口

### 5.1 Visual C++ Runtime

当前 70 文件 package runtime 明确排除 `vc_redist.x64.exe`。该文件仍可由
`windeployqt` 保留在 Release development `bin`，但 ZIP、SFX 和 MSI 均不会分发
或执行它。

移除 redistributable 安装器不等于已经部署 VC Runtime。当前 package 也没有加入
app-local VC143 DLL，因此干净机器仍需预先安装兼容的 Visual C++ Runtime。若目标是
真正解压即运行，正式发布前推荐增加 app-local VC143 Runtime：

1. 只从当前 VS2022 redist 确定 Release 所需 DLL；
2. 禁止复制 Debug CRT；
3. Windows 10/11 继续使用系统 UCRT；
4. 保持 `vc_redist.x64.exe` 在发布 denylist 中，只加入实际 app-local DLL；
5. manifest 记录路径、文件版本和 SHA-256；
6. 在不含 VS/Qt/依赖开发环境的干净机复验。

如果以后改用中央 VC Runtime，应由可选的 WiX Burn bootstrapper 在 MSI 事务
外安装官方 redistributable，同时重新定义 ZIP/SFX 的依赖策略。

### 5.2 许可证、SBOM 与签名

正式 distribution payload 还需要加入许可证目录和第三方声明，至少覆盖项目、
Qt、OpenSSL、SQLCipher、Brotli 及实际随包组件。发布流程还应生成 CycloneDX
或 SPDX SBOM，并记录工具版本、Git commit、每个载荷文件和最终产物哈希。

推荐签名顺序：

```text
build and test
  -> assemble runtime
  -> sign application PE files
  -> regenerate runtime manifest
  -> build and verify ZIP/MSI/SFX
  -> sign MSI and SFX outer files
  -> generate final checksums and release manifest
```

证书、私钥、token 和密码不得写入 Preset、脚本、仓库或普通构建日志。

## 6. ZIP 绿色包

### 6.1 已实现方式

ZIP 不使用旧 Windows `install()` 或 CPack install tree，而是通过 CMake 3.30
自带的 `cmake -E tar --format=zip` 直接归档已经验证的 Release runtime。

入口：

```cmd
cmake --workflow --preset zip-release
```

也可以运行：

```cmd
installer\windows\zip\build.cmd
```

目标链：

```text
sqlitebrowser
  -> sqlitebrowser_package_runtime
     -> sqlitebrowser_runtime_smoke
        -> sqlitebrowser_zip
```

`sqlitebrowser_zip` 为 Release-only 显式目标，不加入默认 `ALL`。流程会：

1. 验证 Release runtime 和 `runtime-manifest.txt`；
2. 拒绝绝对路径、`..`、重复、缺失、额外或哈希不一致的文件；
3. 从 manifest 逐项建立受控归档输入；
4. 生成唯一顶层目录 `DB Browser for SQLCipher`；
5. 原子发布 ZIP；
6. 解压到独立 `package/verify/zip`；
7. 再次比较全部 70 个相对路径和 SHA-256；
8. 从解压副本运行受限 `PATH` 的应用启动、SQLCipher、OpenSSL Brotli 和 Qt
   OpenSSL HTTPS smoke；
9. 写入 `.zip.sha256` 和 `zip-manifest.txt`。

2026-09-05 本机结果：ZIP 构建、解包、70 文件哈希以及四项 smoke 全部通过。

### 6.2 “绿色”的准确含义

当前 ZIP 表示：

- 不运行安装器；
- 不注册卸载项、文件关联、服务或驱动；
- 不修改系统 `PATH`；
- 解压后从目录启动，删除目录即可删除程序文件。

它不承诺设置完全无痕。没有指定 `DB4S_SETTINGS_FILE` 或 `-S/--settings` 时，
应用仍可能通过正常 `QSettings` 使用注册表或 AppData。真正 portable settings
应作为独立应用功能实现，例如显式 `--portable` 和包内 `data/settings.ini`，
不能仅靠 ZIP 命名获得。

## 7. WiX 7 MSI

### 7.1 已实现工程

MSI 使用：

```text
installer/windows/wix/
├─ SQLiteBrowser.Installer.wixproj
├─ Package.wxs
├─ packages.lock.json
├─ README.md
└─ build.cmd

cmake/
├─ SQLiteBrowserWix.cmake
└─ BuildSQLiteBrowserMsi.cmake
```

入口：

```cmd
cmake --workflow --preset msi-release
```

首次在新机器构建前，由授权方审阅 EULA 后执行：

```cmd
msbuild installer\windows\wix\SQLiteBrowser.Installer.wixproj ^
  -t:AcceptEula ^
  -p:EulaId=wix7
```

### 7.2 MSI 契约

当前实现包括：

- SDK 与 UI extension 精确固定为 7.0.0；
- x64、Release-only、per-machine；
- 标准 WixUI 安装目录界面及现有 license/banner/background 资源；
- WiX `MajorUpgrade` 和降级阻止；
- ARP 图标、帮助、项目信息和更新链接；
- 只通过 `<Files Include="$(PayloadRoot)\**">` harvest 已验证 runtime；
- 不修改 `PATH`；
- 不执行旧 uninstaller custom action；
- 保留 `.wixpdb` 用于诊断。

开始菜单快捷方式、桌面快捷方式、文件关联和多语言 MSI 当前尚未实施，应在最小
MSI 生命周期稳定后独立增加。

### 7.3 前后置验证

CMake 在调用 WiX 前验证 manifest、路径边界、文件集合和哈希。WiX build 使用
VS2022 MSBuild `-restore`，Windows Installer validation 必须零错误。生成后执行：

```cmd
msiexec /a "<package>.msi" /qn ^
  TARGETDIR="<verify-dir>" ^
  /l*v "<verify-log>"
```

传给 `msiexec` 的路径必须转换为 Windows 原生反斜杠形式，否则可能返回 1619。
administrative image 中的应用目录再次执行 runtime allowlist 和逐文件 SHA-256
比较，然后生成 `msi-manifest.txt`。

2026-09-05 本机结果：WiX authoring、Windows Installer validation、管理解包和
70 文件哈希校验全部通过，WiX 构建为零警告、零错误。

## 8. 旧版本检测、升级和卸载

### 8.1 同产品 MSI

由稳定 UpgradeCode 和 WiX `MajorUpgrade` 处理：

- 较旧版本升级；
- 较新版本存在时拒绝降级；
- repair 和 uninstall 使用 Windows Installer 标准行为；
- 不用 custom action 复制或删除应用文件；
- 不删除用户数据库和用户配置。

当前 UpgradeCode 仍需要用真实历史 MSI 验证产品身份，并测试 upgrade、repair、
rollback、downgrade 和 uninstall。

### 8.2 历史 NSIS 安装

当前 MSI 检查历史产品键：

```text
Software\DB Browser for SQLite Team\DB Browser for SQLite
```

覆盖 HKLM/HKCU 和 32/64-bit registry view。检测到旧 NSIS 安装时，MSI 通过
LaunchCondition 提示用户从 Windows“应用和功能”手工卸载，然后阻止新安装。

不把旧 `CA_NSIS_UNINSTALL` 迁入新 MSI。直接从提权 MSI transaction 拼接并
执行 `[InstallLocation]\Uninstall.exe /S` 存在身份验证不足、非事务卸载和失败
回滚困难等风险。

如果以后确实需要自动迁移，应单独评估 WiX Burn bootstrapper，在 MSI 事务前
验证旧产品 registry 来源、路径、Publisher、数字签名和退出码，再经用户确认
卸载。第一版 MSI 不实现自动删除。

### 8.3 旧绿色包

ZIP/SFX 不写可靠安装状态，系统无法知道用户解压到了哪里。禁止扫描磁盘或用户
目录，也不自动删除旧绿色包；用户应解压到新版本目录，验证后自行删除旧目录。

## 9. NSIS portable SFX

### 9.1 定位

NSIS 只生成 extraction-only `-portable.exe`，让普通用户双击、选择目录、解压
并可选启动。它不包装 MSI，也不负责旧 NSIS 自动迁移。

构建脚本只检查默认路径和精确版本 3.12：

```text
C:\Program Files (x86)\NSIS\makensis.exe
```

不存在或版本不匹配时明确报错退出；不读取自定义环境变量，不自动下载安装工具
或第三方 plugin。

### 9.2 行为边界

portable SFX 必须：

- `Unicode true`；
- `RequestExecutionLevel user`，不请求 UAC；
- `CRCCheck force`；
- 只嵌入经过 manifest 验证的 Release runtime；
- 不写 HKLM/HKCU；
- 不生成 uninstaller、快捷方式、文件关联或卸载项；
- 不修改 `PATH`；
- 不检测或卸载系统中的安装版；
- 默认不在完成后自动运行应用；
- 支持标准 `/S /D=<path>` 静默解压。

以上约束已经由 `installer/windows/nsis/portable-sfx.nsi` 和
`cmake/BuildSQLiteBrowserPortableSfx.cmake` 实现。构建入口是 Release-only
`sqlitebrowser_portable_sfx` target；普通 `release` 构建不会隐式制作 SFX。

建议页面：Welcome、Directory、解压进度和 Finish。所有界面应使用“解压”而不是
“安装”。默认目录建议为 SFX 旁边的版本目录。

### 9.3 目标目录安全

第一版采用严格策略：

1. 目标目录必须不存在或为空；
2. 拒绝驱动器根、Windows 和已知系统目录；
3. 不提供强制覆盖非空目录；
4. 先解压到同盘同级保留目录 `<目标>.__sqlitebrowser_extracting`；
5. staging 已存在时立即失败，不接管也不删除该目录；
6. 载荷与临时 completion marker 均成功写入后，删除 marker，再将 staging 原子
   rename 为最终目录；
7. 失败时只清理本进程成功创建的 staging；
8. 不递归删除用户原目录、数据库或设置。

静默形式：

```cmd
DB.Browser.for.SQLCipher-4.0.0-win-x64-portable.exe /S /D=F:\Apps\SQLiteBrowser
```

NSIS 的 `/D=` 必须作为最后一个参数。静默模式不弹 MessageBox、不自动启动；
目标目录非空时返回稳定非零退出码。`/D=` 不能加引号，即使路径包含空格；自动
验证通过 UTF-8 `.cmd` runner 保留 NSIS 所要求的原始命令行形式。

目录校验退出码为 21–25，分别表示无效路径、根目录、受保护系统树、已有文件和
非空目录；解压阶段错误使用 31–40，便于 CI 定位失败阶段。

2026-09-05 本机结果：生成的约 54.2 MB SFX 已成功静默解压到同时包含空格
和中文字符的目录；70 个路径与 SHA-256 全部匹配；应用启动、SQLCipher、OpenSSL
Brotli、Qt OpenSSL HTTPS smoke 均通过；非空目录被拒绝且 sentinel 哈希未改变。

## 10. 构建入口

```cmd
rem 只编译应用
cmake --preset release
cmake --build --preset release

rem 组装/测试公共 runtime
cmake --workflow --preset package-release
cmake --workflow --preset smoke-release

rem 已实现的正式格式
cmake --workflow --preset zip-release
cmake --workflow --preset portable-sfx-release
cmake --workflow --preset msi-release
```

Debug configure 不提供正式 ZIP、MSI 或 SFX target。打包命令必须保持显式，且
不得改变正常 `release` 最小产品构建的输出范围。

## 11. 验证矩阵

### 11.1 已自动化

- runtime 只允许 70 个指定文件，并显式排除 `vc_redist.x64.exe`；
- 缺失、空文件、额外文件和 manifest 哈希变化立即失败；
- ZIP 固定唯一顶层目录；
- ZIP 解包后路径和 SHA-256 与 runtime 完全一致；
- MSI 通过 Windows Installer validation；
- MSI administrative image 与 runtime 完全一致；
- SFX 静默解压到含空格和非 ASCII 字符的目录后，路径和 SHA-256 与 runtime
  完全一致；
- SFX 拒绝非空目录且不修改原有 sentinel 文件；
- runtime、ZIP 与 SFX 解包副本通过应用启动、SQLCipher、OpenSSL Brotli、Qt OpenSSL
  backend 和 HTTPS smoke；
- ZIP/SFX/MSI 生成独立 manifest，ZIP 和 SFX 生成 SHA-256 sidecar。

### 11.2 发布前干净机测试

在不含 Visual Studio、Qt、OpenSSL、SQLCipher、NSIS 和开发输出的 Windows 10/11
x64 虚拟机至少验证：

1. ZIP 解压到空目录并在受限 `PATH` 下运行；
2. ZIP 路径包含空格和非 ASCII 字符；
3. MSI 全新交互和 `/qn` 静默安装；
4. 默认和自定义安装目录；
5. Programs and Features 元数据；
6. repair；
7. 真实旧 MSI major upgrade；
8. 拒绝降级；
9. 交互和静默卸载；
10. 旧 NSIS 四个 registry view 的检测提示；
11. 卸载不删除用户数据库和设置；
12. 开始菜单与公共桌面快捷方式的目标、工作目录、repair 恢复和卸载清理；
13. 安装、升级和卸载日志无未解释错误；
14. SFX 的交互选择目录、取消、系统目录拒绝和人为制造的中途写入失败。

### 11.3 负向测试

- 删除、篡改或额外加入一个 runtime 文件时打包必须失败；
- Debug DLL/PDB、`.lib`、测试程序、依赖 CLI、zlib/zstd 不得进入正式载荷；
- WiX SDK 与 extension 版本不一致或 locked restore 变化时失败；
- 错误架构、配置、版本和不安全路径时失败；
- ZIP/SFX/MSI 验证不得从开发机 `PATH` 偶然加载依赖；
- portable SFX 对非空目录和系统路径必须失败且不删除用户文件。

## 12. 后续实施顺序

### 阶段 A：补齐公共发布载荷

- 保持排除 `vc_redist.x64.exe`，评估并加入所需 app-local VC143 Runtime；
- 加入项目和第三方许可证；
- 增加完整 package inputs、签名状态及 SBOM；
- 复验 ZIP 和 MSI 仍来自同一个 manifest。

### 阶段 B：确认 MSI 产品家族

- 从真实旧 MSI 读取 ProductName、Manufacturer、ProductCode 和 UpgradeCode；
- 明确 fork 与上游产品的升级或并存关系；
- 完成安装、repair、upgrade、downgrade、rollback 和 uninstall 测试；
- 开始菜单与公共桌面快捷方式已实现；需要后再增加文件关联和本地化。

### 阶段 C：实现 NSIS portable SFX（已完成）

- 新增目的单一的 `portable-sfx.nsi`；
- 固定 NSIS 默认路径和 3.12；
- 实现目标目录保护、静默解压及解包验证；
- 不加入 setup wrapper 或旧版自动卸载。

2026-09-05 已完成上述工程实现和本机自动验证。仍需在干净 Windows 机器补充
交互 UI、取消及故障注入测试。

### 阶段 D：签名、CI 和发布

- 签内部 PE、MSI 和 SFX；
- 生成最终 checksums、SBOM、日志和 release manifest；
- CI 固化 build -> test -> runtime -> package -> verify -> sign；
- 在干净 Windows x64 环境完成发布门禁；
- 新增 ZIP/MSI/SFX 构建 Skill；
- 新流程稳定后归档或删除旧 WiX 3 构建入口。

只有确有自动迁移需求并完成威胁模型后，才单独评估 WiX Burn；它不应成为 v4.0.0
首次发布的前置条件。

## 13. 主要风险与控制

| 风险 | 控制 |
| --- | --- |
| 错误 UpgradeCode 影响上游或其他 fork | 用真实 MSI 取证，未确认前不宣称升级兼容 |
| 打包器重新收集 DLL | ZIP/MSI/SFX 只接受相同 runtime 和 manifest |
| 发布包缺少 VC Runtime | 保持排除 redistributable installer，正式发布前按需加入 app-local VC143 并做干净机测试 |
| WiX 许可未经授权 | 脚本不自动接受 EULA，由授权方在每台构建机明确处理 |
| NuGet/WiX 版本漂移 | 精确版本、lock file、locked restore、受信源 |
| MSI 执行旧 NSIS uninstaller | 第一版仅检测阻止；自动迁移只能在事务外另行设计 |
| ZIP/SFX 被误称完全无痕 | 文档区分免安装与 portable settings |
| SFX 覆盖用户数据库 | 只接受不存在或空目录，使用受控 staging |
| 签名后 manifest 失效 | 固定签名顺序，签名后重算并最终复验 |
| ZIP/SFX/MSI 内容分叉 | 前后置解包校验都对比同一 runtime manifest |
| 包体较大 | 先保证正确性，再基于实测依赖精简，不手工删 DLL |

## 14. v4.0.0 发布验收标准

1. 普通 `release` 仍是最小产品构建；
2. ZIP、MSI、SFX 和测试均使用显式独立命令；
3. 所有格式来自同一份已签名、已验证载荷；
4. 正式载荷不包含 PDB、LIB、测试工具、私有 stage 或构建目录；
5. ZIP/SFX 在无开发环境的支持系统上解压即运行；
6. MSI 安装、repair、major upgrade、拒绝降级和卸载全部通过；
7. 每种格式的应用文件集合与 runtime manifest 一致；
8. 版本、产品名称、EXE version resource、MSI 和文件名一致；
9. 许可证、SBOM、签名和 SHA-256 可追溯到同一 Git commit；
10. 旧打包入口不会被开发者误用。

## 15. 参考资料

- [Windows v4 构建指南](../../docs/windows-v4-build-guide.md)
- [WiX Toolset：使用 WiX](https://docs.firegiant.com/wix/using-wix/)
- [WiX Toolset：OSMF](https://docs.firegiant.com/wix/osmf/)
- [WiX Toolset：MSBuild SDK](https://docs.firegiant.com/wix/tools/msbuild/)
- [WiX Toolset：MajorUpgrade](https://docs.firegiant.com/wix/schema/wxs/majorupgrade/)
- [WiX Toolset：Launch condition](https://docs.firegiant.com/wix/schema/wxs/launch/)
- [NSIS scripting reference](https://nsis.sourceforge.io/Docs/Chapter4.html)
- [NSIS Modern UI 2](https://nsis.sourceforge.io/Docs/Modern%20UI%202/Readme.html)
- [NSIS SetRegView](https://nsis.sourceforge.io/Reference/SetRegView)
- [Microsoft：Visual C++ 部署](https://learn.microsoft.com/en-us/cpp/windows/deployment-in-visual-cpp?view=msvc-170)
- [Qt 6 Windows 部署](https://doc.qt.io/qt-6/windows-deployment.html)
