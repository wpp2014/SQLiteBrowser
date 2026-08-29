# 当前分支主程序构建升级风险分析

> 文档性质：当前分支构建迁移风险与控制措施
> 最后更新：2026-08-28
> 当前分支：`upgrade/v4.0.0`
> 当前基线：`1a6e345c37403f7fa20d2e029be5abd5fdfa9b8b`
> 目标：Windows x64、VS2022/v143、SDK `10.0.26100.0`、Qt 6.11.1、配置专用共享依赖
> 本阶段直接以当前分支为唯一代码基线，不比较、合并或回退到上游稳定标签。
> 本轮只更新文档，没有修改工程。

## 1. 结论

依赖构建阶段已经形成稳定的 Debug/Release stage，主程序可以开始迁移。但整体风险仍为中高，主要集中在主工程 CMake 和运行时部署，而不是依赖源码本身。

优先级最高的风险是：

1. 现有依赖由 SDK 22621 构建，而主程序目标改为 SDK 26100。
2. 当前 SQLCipher finder 不能正确表达 Windows DLL/import library。
3. 现有 install 规则不能保证普通 build 输出直接运行。
4. Qt 路径、系统 OpenSSL 和同名 DLL 仍可能被开发机环境偶然找到。
5. `windeployqt` 只处理 Qt 运行时，不能替代 SQLCipher/OpenSSL/Brotli 的显式部署。
6. 历史 Windows subsystem/entry flags 可能与 VS2022/Qt6 行为冲突。

建议先完成 Preset、严格 finder 和 build-time deploy，再进入 CI、安装器和版本号工作。

## 2. 基线边界

本阶段只接受：

```text
branch: upgrade/v4.0.0
baseline: 1a6e345c37403f7fa20d2e029be5abd5fdfa9b8b
```

后续实现期间不应无计划同步其他分支。若必须同步，应单独提交并在同步后重新验证：

- 两个 configure preset；
- 两个 build preset；
- 两个 test preset；
- Debug/Release 依赖 manifest；
- 应用可运行目录；
- 干净机 Release 启动。

## 3. 工具链风险

### 3.1 SDK 混用

**等级：高**

现有所有依赖 manifest 都记录 SDK `10.0.22621.0`，目标主程序为 `10.0.26100.0`。

可能影响：

- 构建结果不再来自同一套 headers/import libraries；
- 发生 Windows API 或宏差异时难以归因；
- CI 与本地产物的供应链声明不一致；
- 严格 manifest gate 无法通过。

控制措施：

- bring-up 可临时允许 26100 应用消费 22621 依赖；
- 配置日志必须显示该差异；
- 发布前用 26100 重建全部依赖；
- 最终 configure 对 SDK manifest 不一致直接失败。

### 3.2 Visual Studio 多配置误用

**等级：中高**

Visual Studio generator 默认一个 build tree 包含多个配置。若 Debug/Release 共用 cache，就可能把 Debug 应用链接到 Release SQLCipher/OpenSSL。

控制措施：

- 使用 `build/x64-shared-debug` 和 `build/x64-shared-release` 两个独立 tree；
- 每个 configure preset 限制 `CMAKE_CONFIGURATION_TYPES`；
- finder 只接受当前配置 stage；
- build/test preset 显式填写 `configuration`；
- manifest 校验 CRT。

### 3.3 历史 linker flags

**等级：中高**

当前 Release 强制 `/SUBSYSTEM:WINDOWS,5.02 /ENTRY:mainCRTStartup`。它绕开现代 CMake/Qt 对 Windows GUI target 的默认处理，也不能代表 Qt6 的真实最低系统要求。

控制措施：

- 删除历史 subsystem version 和手写 entry point；
- 保留 `WIN32_EXECUTABLE`；
- 分别验证 Debug 控制台与 Release GUI；
- 用产品策略单独确定最低 Windows 版本。

## 4. Qt 风险

### 4.1 路径硬编码

**等级：高**

把开发机 Qt 绝对路径提交到版本化 Preset 会让其他开发者和 CI 立即失效。

控制措施：

- 只提交带占位符的 `CMakePresets.template.json`；
- 开发者复制出被忽略的本地 `CMakePresets.json` 并填写 Qt 根目录；
- 复制模板，不移动被 Git 跟踪的模板；
- configure 验证 Qt 版本、架构、Core5Compat 和 windeployqt；
- 不从全局 PATH 猜测 Qt。

### 4.2 Qt runtime 不完整

**等级：高**

只复制 `Qt6Core.dll` 等顶层 DLL 不足以运行 GUI。缺少 `platforms/qwindows.dll`、TLS、imageformats 或其他 plugin 时，应用可能启动失败或部分功能静默不可用。

控制措施：

- 使用当前 Qt package 提供的 `Qt6::windeployqt`；
- Debug/Release 传入正确模式；
- 部署 compiler runtime；
- 对最终目录运行 Qt plugin 和 TLS smoke test；
- 不维护手写 Qt DLL 清单。

### 4.3 Debug 可分发性

**等级：中**

Debug Qt、SQLCipher 和 OpenSSL 使用 Debug CRT。Microsoft Debug CRT 不属于普通 redistributable。

控制措施：

- Debug 只承诺在安装 VS2022 的开发机直接运行；
- portable ZIP、CI 发布物和安装器只消费 Release；
- Release 审计不得出现 Debug CRT。

## 5. SQLCipher 与 OpenSSL 风险

### 5.1 SQLCipher imported target 错误

**等级：高**

当前 finder 把 `sqlcipher.lib` 作为 `IMPORTED_LOCATION`，没有声明 DLL。链接可能成功，但 CMake 无法从 target 可靠取得 runtime 文件。

控制措施：

- `IMPORTED_IMPLIB` 指向 LIB；
- `IMPORTED_LOCATION` 指向 DLL；
- include 指向配置专用 stage；
- finder 同时验证 manifest；
- deploy 通过 target 或明确 stage 获取 DLL。

### 5.2 系统 OpenSSL 被误用

**等级：高**

普通 `find_package(OpenSSL)`、PATH 或 `find_file()` 可能选中系统安装的其他 OpenSSL。

控制措施：

- Windows 使用项目 stage 的 OpenSSL config package；
- preset 显式设置配置专用 `OpenSSL_DIR`；
- 禁止系统回退；
- 运行时从最终 EXE 目录加载 DLL；
- 用 `dumpbin` 和进程模块列表验证来源。

### 5.3 Brotli 是动态隐藏依赖

**等级：高**

OpenSSL 以动态方式加载 Brotli，导入表不一定列出 Brotli DLL。仅根据 `dumpbin /dependents libcrypto` 复制文件会漏部署。

控制措施：

- 从匹配 OpenSSL stage 复制三个 Brotli DLL；
- 把 OpenSSL manifest 的 Brotli tag/commit 作为部署契约；
- 增加运行时 Brotli integration probe；
- 禁止混用独立 Brotli stage 的另一配置。

### 5.4 不相关 DLL 过度部署

**等级：中**

zlib 和 zstd 已经构建，但目前没有进入主程序的实际链接闭包。无条件复制会扩大攻击面、许可证清单和版本维护范围。

控制措施：

- 只部署真实 runtime closure；
- 新增链接后再加入对应 DLL 和许可证；
- 以 imported target、dumpbin 和运行时模块审计为依据。

## 6. Preset 风险

### 6.1 误解 cmake --preset

**等级：中**

`cmake --preset debug` 只 configure。如果文档把它描述成完整构建，开发者会误以为没有生成 EXE 是故障。

控制措施：

```cmd
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

Release 同理。需要单命令时使用 workflow preset。

### 6.2 “shared”命名歧义

**等级：中高**

看到 `x64-shared-*` 后直接设置 `BUILD_SHARED_LIBS=ON`，会把内置 QScintilla、QCustomPlot、QHexEdit 变成 DLL；当前 wrapper 没有完整验证这些库的 Windows 导出宏和部署。

控制措施：

- 第一阶段固定 `BUILD_SHARED_LIBS=OFF`；
- “shared”只表示外部 Qt/SQLCipher/OpenSSL/Brotli 运行时；
- 若未来需要内部库 DLL 化，单独实现导出宏、ABI 和部署测试。

### 6.3 Qt 占位符未替换

**等级：中**

开发者若直接复制模板但没有替换 Qt 占位符，配置可能表现为找不到 Qt；若另外存在系统 Qt，也可能意外找到错误版本。

控制措施：

- configure 开始即验证 `CMAKE_PREFIX_PATH` 不是模板占位符；
- 错误信息给出复制模板和填写路径的方法；
- 不允许静默 fallback；
- CI 生成自己的本地 `CMakePresets.json`，不修改已提交模板。

## 7. 输出与部署风险

### 7.1 install 与 build 输出不一致

**等级：高**

当前 DLL 部署只在 install 阶段执行。用户要求 build 后 EXE 目录即可运行，因此只修正 install 规则不足以达成目标。

控制措施：

- 新增 build-time deploy target；
- build preset 构建该 target；
- build/install 共用 runtime 来源；
- 两种输出都进行依赖审计。

### 7.2 find_file 找到错误 DLL

**等级：高**

现有 `find_file()` 使用通用 suffix 搜索，可能从 PATH、旧构建或系统安装中取得同名 DLL。

控制措施：

- 不再全局搜索 runtime；
- 使用 `SQLCipher::SQLCipher`、`OpenSSL::Crypto`、`OpenSSL::SSL` 的 imported location；
- Brotli 从已验证 OpenSSL stage 复制；
- configure 输出每个源文件的绝对路径。

### 7.3 PATH 掩盖缺失文件

**等级：高**

开发机 PATH 中的 Qt/OpenSSL DLL 可能让不完整目录看似可运行。

控制措施：

- 用最小环境或干净虚拟机启动 Release；
- 临时清空开发依赖 PATH；
- 记录实际加载模块路径；
- 将“整个目录复制到另一台机器可启动”设为完成条件。

## 8. 工程范围风险

### 8.1 .gitignore 忽略新 CMake 文件

**等级：中**

仓库当前全局忽略 `*.cmake`。新增部署 helper 时可能不会出现在 `git status`，导致本地能构建但提交缺文件。

控制措施：

- 优先修改已有 tracked CMake 文件；
- 如需新增 helper，同步增加精确 whitelist；
- 提交前使用 `git status --ignored` 检查。

### 8.2 构建、部署、安装器同时修改

**等级：高**

Preset、finder、windeployqt、NSIS、版本号同时变化会导致错误难以归因。

控制措施：

1. Preset 与 finder；
2. 主程序编译和 CTest；
3. build-time deploy；
4. SDK 统一；
5. CI；
6. install/portable ZIP/NSIS；
7. 版本号。

每阶段独立提交和验证。

## 9. 实施门禁

### 开始编码前

- 三份分析文档与当前目标一致；
- Qt 路径输入方式确定；
- Debug/Release stage 路径确定；
- 接受 bring-up 阶段 SDK 混用，或先决定重建依赖；
- 应用输出名是否保持 SQLCipher 品牌已知但不在本阶段修改。

### Preset 完成

- configure 精确报告 VS2022、x64、v143、SDK 26100；
- Qt 精确为用户指定的 6.11.1；
- Debug/Release cache 和依赖不混用；
- 系统 OpenSSL/SQLCipher 不参与。

### Build 完成

- 两个 build preset 成功；
- 四个 CTest 成功；
- 主程序、SQLCipher、OpenSSL 架构和 CRT 正确；
- 历史 linker flags 已处理。

### Deploy 完成

- 两个 `bin` 目录形成；
- Debug 可在开发机运行；
- Release 可在干净 Windows 环境运行；
- Qt TLS、普通数据库、加密数据库 smoke test 通过；
- 没有从 PATH 加载依赖。

### Release 准入

- 全部依赖重新使用 SDK 26100；
- manifest 严格一致；
- Release 不包含 Debug CRT；
- portable/installer、许可证、签名和升级测试另行完成。

## 10. 最终建议

以当前分支为唯一基线，下一次工程修改只处理：

1. `CMakePresets.template.json` 与本地 `CMakePresets.json` 工作流；
2. Qt 用户路径输入与验证；
3. SQLCipher/OpenSSL 严格 finder；
4. Windows linker flags；
5. 配置专用 runtime output；
6. build-time DLL/Qt deployment；
7. Debug/Release build 与 CTest。

不要在同一阶段引入版本号、NSIS、功能重构或内部 Qt 库 DLL 化。这样可以把问题限定在构建图与部署闭包内，并为后续统一 SDK 和正式发布保留清晰边界。
