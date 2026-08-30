# Windows 依赖公共产物汇总说明

> 适用分支：`upgrade/v4.0.0`
>
> 目标平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK `10.0.26100.0`
>
> 状态：阶段 5 已实施并完成 Debug/Release 验证

## 1. 作用和边界

五个依赖各自的 `build.cmd` 只负责生成私有 stage：

```text
output/x64-shared-<config>/build/<dependency>/stage
```

`third_party\aggregate.cmd` 是唯一负责配置级公共依赖目录的入口。它不会编译依赖，也不会部署主程序或 Qt；它会验证已有私有 stage，并按明确 allowlist 发布到：

```text
output/x64-shared-<config>/include
output/x64-shared-<config>/bin
output/x64-shared-<config>/metadata
```

主程序要到阶段 6 才切换为消费该公共目录。因此阶段 5 的 `bin` 是开发依赖输出，不是可直接打包的应用运行目录。

## 2. 使用命令

从仓库根目录执行：

```cmd
third_party\aggregate.cmd build all
```

也可以只处理一个配置：

```cmd
third_party\aggregate.cmd build debug
third_party\aggregate.cmd build release
```

只读验证不会创建或修改文件：

```cmd
third_party\aggregate.cmd check all
```

清理只删除 ownership manifest 声明的公共依赖文件：

```cmd
third_party\aggregate.cmd clean debug
third_party\aggregate.cmd clean release
```

查看帮助：

```cmd
third_party\aggregate.cmd --help
```

省略参数时默认为 `build all`。执行 `build` 前必须已经成功构建所选配置的 Brotli、zlib、zstd、OpenSSL 和 SQLCipher 私有 stage。

## 3. 推荐顺序

完整依赖集按以下顺序生成：

```cmd
third_party\brotli\build.cmd build all
third_party\zlib\build.cmd build all
third_party\zstd\build.cmd build all
third_party\openssl\build.cmd build all
third_party\sqlcipher\build.cmd build all
third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
```

测试仍然使用各依赖的独立 `test` 命令。汇总器不会把测试程序复制到公共 `bin`；若私有 stage 已存在 `test-manifest.txt`，汇总时会验证它绑定当前 build manifest 并复制到 metadata。测试不是普通产品构建的隐式步骤。

## 4. 公共目录契约

### 4.1 include

```text
include/
|- brotli/*.h
|- openssl/*.h
|- sqlcipher/sqlite3.h
|- sqlcipher/sqlite3ext.h
|- sqlcipher/sqlite3session.h
|- zlib.h
|- zconf.h
|- zstd.h
|- zdict.h
`- zstd_errors.h
```

Qt 头文件不复制到 `output`。OpenSSL 的 `applink.c` 也不属于当前公共头文件 allowlist。

### 4.2 bin

公共 `bin` 只接收产品 DLL、import LIB 和与产品 DLL 对应的 linker PDB：

- Brotli：`brotlicommon`、`brotlidec`、`brotlienc`；
- zlib：`zlib1`；
- zstd：`libzstd`；
- OpenSSL：`libcrypto-3-x64`、`libssl-3-x64`；
- SQLCipher：`sqlcipher`。

不允许 EXE、测试程序、示例、SQLCipher CLI、OpenSSL CLI、provider/engine DLL、compiler PDB（如 `vc143.pdb`）进入公共 `bin`。OpenSSL stage 中附带的 Brotli DLL 必须与 Brotli stage 逐字节一致，公共输出只从 Brotli stage 复制一份。

### 4.3 metadata

`metadata` 包含：

- 五个依赖的 build manifest；
- 存在且与当前构建绑定的 test manifest；
- 五个依赖的许可证；
- `dependency-aggregate-manifest.txt`；
- `dependency-ownership-manifest.txt`。

aggregate manifest 记录配置、架构、Windows SDK、CRT、五个 build manifest 的 SHA-256 和测试记录状态。ownership manifest 使用 `SHA-256<TAB>relative/path` 声明汇总器拥有的每个公共文件。

## 5. 验证规则

汇总前会检查：

- 每个依赖的固定 tag、commit、配置、x64、SDK `10.0.26100.0` 和 CRT；
- 每个私有 stage 的必要产品、公开头文件和 build manifest；
- 已存在 test manifest 与当前 build manifest 的 SHA-256 绑定；
- OpenSSL 附带 Brotli DLL 与 Brotli stage 完全相同；
- SQLCipher build manifest 绑定当前同配置 OpenSSL build manifest；
- Debug 和 Release 不交叉复制。

任何验证失败都会以非零退出码停止，不能把该公共输出视为有效。

## 6. 所有权和安全更新

重复执行 `build` 时，汇总器先验证现有 ownership manifest 和所有受管文件的哈希。对于计划写入但不属于现有 ownership manifest 的文件，汇总器会拒绝覆盖。

发布使用配置内的临时 next tree 和 backup：旧受管文件先移入精确备份，新文件与 ownership manifest 验证完成后才删除备份；发布失败时恢复旧文件。若发现上次遗留的备份目录，脚本会停止并要求先检查，避免覆盖可恢复内容。

`clean` 同样先验证所有受管文件哈希，再逐项移动和删除。它不会递归删除整个 `output`、配置根、私有 dependency stage、另一配置或未知公共文件。

## 7. 本次验证结果

2026-08-30 已在当前仓库执行：

```cmd
third_party\aggregate.cmd build all
third_party\aggregate.cmd build all
third_party\aggregate.cmd check all
third_party\aggregate.cmd clean debug
third_party\aggregate.cmd build debug
third_party\aggregate.cmd check all
```

Debug 和 Release 各发布 196 个受管文件：155 个头文件、24 个 DLL/LIB/linker PDB 和 17 个 metadata 文件；此外各有 1 个不自引用的 ownership control manifest。重复汇总通过；Debug 清理后，其五个私有 stage 与 Release 公共输出保持不变；重新聚合 Debug 后双配置检查通过。

阶段 6 需要修改主程序 Preset、binary directory 和依赖查找路径，使应用在同一配置根中消费这些公共头文件和二进制产物。
