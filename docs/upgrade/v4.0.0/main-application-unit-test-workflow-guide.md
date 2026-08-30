# 主程序单元测试 Workflow 说明

> 适用分支：`upgrade/v4.0.0`
>
> 平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
>
> 状态：统一输出重构阶段 7 已完成

## 1. 目标

普通产品命令只构建主程序：

```cmd
cmake --preset debug
cmake --build --preset debug
```

单元测试使用独立命令，避免产品构建隐式编译或运行测试。四个测试 target 均设置 `EXCLUDE_FROM_ALL`：

- `test-sqlobjects`；
- `test-import`；
- `test-regex`；
- `test-cache`。

非默认 target `sqlitebrowser_unit_tests` 只聚合这四个测试。

## 2. 正式命令

Debug：

```cmd
cmake --workflow --preset test-debug
```

Release：

```cmd
cmake --workflow --preset test-release
```

每个 workflow 固定执行三个步骤：

```text
configure preset
  -> build unit-tests-<config> preset
     -> sqlitebrowser_unit_tests target
        -> ctest <config> preset
```

因此开发者不需要先手工执行 `cmake --preset`，也不会因为测试 EXE 尚未构建而得到 CTest 的“找不到可执行文件”错误。

## 3. 输出目录

测试产品与主程序、公共运行时分离：

```text
output/x64-shared-debug/build/tests/unit
|- test-cache.exe
|- test-import.exe
|- test-regex.exe
`- test-sqlobjects.exe

output/x64-shared-release/build/tests/unit
`- 同样的四个测试程序
```

测试 linker PDB 在产生时也留在相同私有测试目录。测试 OBJ、AUTOMOC 和生成工程仍位于主程序 CMake binary tree 内。任何测试 EXE 都不得复制到 `output/x64-shared-<config>/bin`。

## 4. Preset 职责

新增 build preset：

| Preset | 配置 | 唯一目标 |
| --- | --- | --- |
| `unit-tests-debug` | Debug | `sqlitebrowser_unit_tests` |
| `unit-tests-release` | Release | `sqlitebrowser_unit_tests` |

新增 workflow preset：

| Preset | 步骤 |
| --- | --- |
| `test-debug` | `debug` configure → `unit-tests-debug` build → `debug` CTest |
| `test-release` | `release` configure → `unit-tests-release` build → `release` CTest |

已有 `debug`、`release` build preset 继续只指定 `sqlitebrowser`，所以普通产品构建不会通过 ALL_BUILD 间接构建测试。

## 5. 运行环境

每项 CTest 的进程环境通过 `ENVIRONMENT_MODIFICATION` 把 `Qt6::Core` 所在目录前置到该测试进程的 `PATH`。这不会永久修改开发者环境变量，也不需要把 Qt DLL 复制到测试目录。

每项测试 timeout 为 60 秒，CTest 使用 `outputOnFailure` 输出失败详情。测试不依赖公共应用 `bin` 中的 SQLCipher、OpenSSL 或 Qt plugin 部署。

## 6. 本次验证

2026-08-30 实际执行：

```cmd
cmake --workflow --preset test-debug
cmake --workflow --preset test-release
```

结果：

- Debug：4/4 通过，总耗时约 0.79 秒；
- Release：4/4 通过，总耗时约 0.88 秒；
- 两个配置均只在私有 `build/tests/unit` 生成四个测试 EXE；
- 随后执行普通 Debug/Release 产品 build，测试 EXE 时间戳保持不变；
- 公共 `bin` 没有测试 EXE，阶段 5 dependency ownership 检查仍通过。

编译 `test-sqlobjects` 时仍报告既有的 `escapeIdentifier` 并非所有控制路径返回值警告；该警告未导致测试失败，应作为独立源码质量问题处理。
