# 阶段 10：README 正式构建说明更新记录

> 文档性质：统一输出重构的开发者入口验收记录
>
> 执行日期：2026-09-01
>
> 当前分支：`upgrade/v4.0.0`
>
> 结论：通过

## 1. 目标

阶段 10 将阶段 9 已从空 `output/` 实测通过的命令提升为 README 的正式 Windows v4 开发流程，使新开发者在完成工具安装和子模块初始化后，可以按唯一顺序完成依赖构建、主程序构建、单元测试、package runtime 组装和受限 `PATH` smoke。

本阶段只修改说明文档，不修改工程、Preset、构建脚本或依赖源码，也不重复执行阶段 9 的全量编译。

## 2. README 调整

- 明确普通 `cmd.exe` 即可执行，依赖脚本自行初始化默认路径下的 VS2022；
- 保留 VS2022 Community、Professional、Enterprise、SDK `10.0.26100.0`、Qt `6.11.1` 和工具版本要求；
- 将压缩库、OpenSSL、SQLCipher 的 `check`、最小产品 `build` 和独立 `test` 按真实依赖顺序列出；
- 明确 OpenSSL `safe` 排除 `test_bio_dgram`，不得表述为 full test pass；
- 将 Preset 检查命令改为 `cmake --list-presets=all`，同时检查 configure、build、test 和 workflow Preset；
- 保留普通 `debug`/`release` build 只构建产品目标的说明；
- 将单元测试固定为 `test-debug`、`test-release` workflow；
- 增加 `package-debug`、`package-release` 的严格 package runtime 说明；
- 将 runtime smoke 的正式入口改为 `smoke-debug`、`smoke-release` workflow，不再要求开发者直接调用底层 target；
- 明确 development `bin` 不是发布输入，未来 ZIP/NSIS 只能消费 `package/runtime`；
- 补充 SHA-256 manifest、Debug/Release 当前 70/71 个 package 文件、Release `vc_redist.x64.exe` 和 Debug 发布边界；
- 增加 stale Preset、package hash/额外文件和 HTTPS smoke 的故障定位；
- 增加 package runtime guide 与阶段 9 干净构建记录链接。

## 3. 正式开发入口

新开发者的主流程现在是：

1. 安装 README 中固定的 Windows 工具链；
2. clone 并执行 `git submodule update --init --recursive`；
3. 按 README 顺序构建、测试并汇总五个依赖；
4. 从 `CMakePresets.template.json` 创建被 Git 忽略的本地 `CMakePresets.json`，只填写 Qt 路径；
5. 使用 `debug`、`release` Preset 构建可直接运行的 development output；
6. 使用 `test-debug`、`test-release` workflow 运行四个单元测试；
7. 使用 `package-*` 生成严格运行时，使用 `smoke-*` 完成发布前运行闭包验证。

README 不包含开发者本机 Qt 绝对路径，也没有要求设置 `SQLITEBROWSER_QT_ROOT` 或修改全局 Qt/OpenSSL/SQLCipher `PATH`。

## 4. 验证

- `cmake --list-presets=all` 成功解析本地 Preset；
- 可见 Debug/Release configure、产品、单元测试、package runtime、runtime smoke 和六个 workflow Preset；
- README 中列出的构建和测试命令均已在阶段 9 从空 `output/` 实际执行通过；
- README 中引用的仓库内文档均存在；
- `git diff --check` 通过；
- `output/` 和本地 `CMakePresets.json` 继续被 Git 忽略。

## 5. 边界与下一阶段

阶段 10 完成的是开发者构建入口，不代表发布流程已经完成。`package/runtime` 仍只是经过验证的发布输入；旧 install、ZIP/NSIS、许可证布局、签名、版本号和干净 Windows Release gate 仍需在后续阶段实施。

下一阶段应先设计 install 与 ZIP/NSIS 如何只消费 `package/runtime`，并定义发布归档、许可证、签名和干净机器验收契约，再修改安装器工程。
