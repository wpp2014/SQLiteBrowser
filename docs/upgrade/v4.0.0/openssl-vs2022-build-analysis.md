# OpenSSL 3.5.7 使用 Visual Studio 2022 构建分析

> 源码：third_party/openssl/src
>
> 版本：openssl-3.5.7 / 8cf17aaeb4599f8af87fefd810b5b5fee90fe69e
>
> 平台：Windows x64
>
> 工具链：Visual Studio 2022、MSVC v143、Windows SDK 10.0.26100.0
>
> 集成：动态加载 Brotli v1.2.0
>
> 最后更新与验证：2026-08-30

## 1. 结论

OpenSSL 的 Windows/MSVC 官方构建不是 CMake 或 Visual Studio solution，而是：

~~~text
Configure VC-WIN64A
  -> 生成 NMake makefile
  -> nmake target
  -> nmake install target
~~~

本项目阶段 3 已采用：

~~~text
nmake build_libs
  -> nmake install_dev
  -> 私有最小 stage
~~~

普通产品构建只部署 Crypto/SSL DLL、linker PDB、公开头文件、import LIB、OpenSSL CMake package 和匹配 Brotli DLL。openssl.exe、独立 provider、engine、测试和 fuzz 程序只允许在独立 test 动作的 work 目录中生成。

## 2. 上游文件依据

### 2.1 build.info

OpenSSL 的 build.info 描述源文件、生成文件、库、程序、module、测试和它们的依赖图。Configure 会把这些规则转换为 Windows NMake makefile。

关键影响：

- libcrypto 和 libssl 是项目实际运行依赖；
- apps/openssl、providers、engines、tests 和 fuzz 是不同类别 target；
- 不能通过手工复制一份源文件列表替代 build.info；
- 使用 build_libs 可以让上游继续控制生成源码、汇编、导出表和内部辅助库，同时不把可选程序作为产品 target。

### 2.2 NOTES-WINDOWS.md

上游 Windows 说明要求：

- 使用匹配目标架构的 Visual C++ 环境；
- 通过 Perl 运行 Configure；
- 64 位汇编优化需要 NASM；
- 使用 NMake 构建；
- 安装 prefix 与 openssldir 应明确指定；
- Debug 和 Release 应使用独立 build directory。

本项目脚本从 VS2022 默认安装目录加载 x64 环境，并显式选择 SDK 10.0.26100.0。Debug 与 Release 分别使用：

~~~text
output/x64-shared-debug/build/openssl/work
output/x64-shared-release/build/openssl/work
~~~

### 2.3 README.md

README 是项目概览，不替代 INSTALL.md、NOTES-WINDOWS.md 和生成的 makefile。版本、支持范围和通用入口来自 README；Windows 命令细节以 NOTES-WINDOWS、Configure help 和生成目标为准。

## 3. VS2022 edition 支持

| Edition | 支持 | 条件 |
| --- | --- | --- |
| Enterprise | 是 | 默认目录、Desktop development with C++、MSVC v143、SDK 10.0.26100.0 |
| Professional | 是 | 同上 |
| Community | 是 | 同上；许可证适用性由使用者自行确认 |

三种 edition 使用相同的 cl、link、nmake、vcvarsall 和 SDK 接口，不影响 OpenSSL 二进制 ABI。

脚本只检查：

~~~text
C:/Program Files/Microsoft Visual Studio/2022/Enterprise
C:/Program Files/Microsoft Visual Studio/2022/Professional
C:/Program Files/Microsoft Visual Studio/2022/Community
~~~

自定义安装目录不在当前项目支持范围内。

## 4. Configure 设计

Debug 与 Release 的共同目标：

- VC-WIN64A；
- shared；
- prefix 指向当前配置私有 stage；
- openssldir 位于 stage/ssl；
- libdir=lib；
- no-demos；
- enable-brotli-dynamic；
- Brotli include 与 bin 指向匹配配置 stage。

配置差异：

| 配置 | OpenSSL 选项 | CRT |
| --- | --- | --- |
| Debug | --debug | /MDd |
| Release | --release | /MD |

动态 Brotli 模式的含义：

- libcrypto 导出 Brotli 压缩 API；
- libcrypto 不产生对 Brotli DLL 的静态 import；
- 运行时通过三个匹配 Brotli DLL 提供功能；
- 应用部署必须同时携带 libcrypto、libssl 和三个 Brotli DLL。

## 5. 为什么选择 build_libs

OpenSSL 生成的 Windows makefile 中：

- build_libs 构建库目标和它们必要的生成/内部依赖；
- 默认 build_sw 范围更大，会带入程序和 module；
- test 会根据需要构建 apps/openssl、测试、fuzz 和 provider；
- install_dev 安装运行库与开发文件；
- install_sw 会安装更广泛的软件和运行组件。

阶段 3 的目标是最小产品构建，因此选择：

~~~cmd
nmake build_libs
nmake install_dev
~~~

OpenSSL 上游可能仍在 work 内生成 libcrypto_static 或 test utility 等内部库。这些属于生成图和中间产物，不等于公共产品；最小化的关键边界是：

1. 普通 build 不生成产品无关 EXE/module；
2. stage 使用严格 allowlist；
3. 后续公共 bin 只从已验证 stage 汇总。

## 6. 为什么不在普通构建运行测试

旧流程把 nmake test 与构建、安装放在同一命令中，会造成：

- 产品构建受本机 IPv6 UDP、VPN、防火墙等状态影响；
- test 为了运行 recipe 生成 CLI、provider、fuzz 和大量测试 EXE；
- build manifest 难以区分“产物是什么”和“哪次测试验证了它”；
- 开发者不能快速完成仅产品构建。

阶段 3 拆分为：

~~~cmd
third_party\openssl\build.cmd build <config>
third_party\openssl\build.cmd test <config> safe
~~~

test 复用现有 work 和已验证 stage，在 work 内生成测试专用文件，不再调用 install_dev，不替换 stage 产品。

## 7. Safe 与 Full

Safe：

~~~text
通用 suite，排除 test_bio_dgram
  + test_bio_comp
  + test_cert_comp
  + test_tls13certcomp
~~~

test_bio_dgram 是 IPv6 UDP datagram 测试。部分开发机的 VPN、TUN、代理、防火墙或虚拟网络过滤器可能使其长时间无输出。safe 明确排除它并写入 test manifest，不能宣称 full pass。

Full：

~~~text
IPv6 UDP ::1 预检
  -> 未过滤通用 suite
  -> 三个 Brotli 聚焦测试
~~~

预检失败时应修复网络环境或接受 safe 的发布风险，不能隐藏排除项。

## 8. Stage 产物

允许：

~~~text
bin/libcrypto-3-x64.dll
bin/libcrypto-3-x64.pdb
bin/libssl-3-x64.dll
bin/libssl-3-x64.pdb
bin/brotlicommon.dll
bin/brotlidec.dll
bin/brotlienc.dll
include/openssl/*
lib/libcrypto.lib
lib/libssl.lib
lib/cmake/OpenSSL/*
build-manifest.txt
test-manifest.txt       # 仅测试成功后
~~~

禁止：

~~~text
openssl.exe
legacy.dll
lib/engines-3/*.dll
vc143.pdb
test/*.exe
fuzz/*.exe
~~~

provider API 的公开头文件属于开发头文件，不表示必须部署独立 provider DLL。默认 provider 的实现可以并入 libcrypto；legacy provider 只有在应用明确需要旧算法时才应作为单独运行时决策。

## 9. PDB 和 Release 策略

Debug 与 Release 都部署 DLL 对应的 linker PDB。compiler PDB 只留在 work。

Release：

- 使用 OpenSSL --release 和 /MD；
- 开启优化；
- 链接器仍产生完整 PDB；
- stage 验证拒绝 Debug CRT；
- stage 拒绝 vc143.pdb。

PDB 不进入最终用户安装包属于后续 packaging 决策；在开发公共 bin 中保留 linker PDB 有利于崩溃定位。

## 10. Manifest

build-manifest.txt 记录：

- OpenSSL/Brotli tag 与 commit；
- 配置、Configure target/options；
- build_libs 与 install_dev；
- VS edition、MSVC、SDK、Perl、NASM；
- stage 路径；
- 核心 DLL/PDB/LIB 与 Brotli DLL SHA-256；
- Tests: not run；
- CLI/provider/engine staged: no。

test-manifest.txt 记录：

- 被测 build manifest SHA-256；
- safe/full；
- 通用 suite 与过滤条件；
- Brotli 聚焦测试结果。

测试记录与 build manifest 分离，使重新构建自然使旧测试记录失效。

## 11. 实测结果

2026-08-30 从新的 output 路径分别完成：

| 配置 | 最小 build/stage | 通用 safe suite | Brotli 聚焦 |
| --- | --- | --- | --- |
| Debug | 通过 | 343 files / 4279 tests，PASS | 3 files / 11 tests，PASS |
| Release | 通过 | 343 files / 4279 tests，PASS | 3 files / 11 tests，PASS |

两个 safe suite 均排除 test_bio_dgram。stage 中 EXE 数量为 0，没有 legacy.dll、engine DLL 或 vc143.pdb。Debug/Release test manifest 的 build SHA-256 均与对应当前 build-manifest.txt 一致。

## 12. 风险与后续阶段

### 当前风险

- Safe 不是未过滤 full 测试；
- 测试首次生成大量程序，耗时明显长于最小 build；
- OpenSSL test 第二次聚焦调用会再次触发部分 test target relink，这是上游 NMake 依赖行为；
- SQLCipher 与主程序尚未迁移到新的 OpenSSL stage 路径。

### 后续

1. 阶段 4 更新 SQLCipher 消费 output 中的 OpenSSL stage，并保持默认 CLI/provider smoke 分离；
2. 阶段 5 建立公共 include/bin 与 ownership manifest；
3. 阶段 6 修改主程序 Preset 和运行时部署；
4. packaging 只复制实际运行闭包，不直接复制整个开发 stage。

## 13. 推荐命令

~~~cmd
third_party\brotli\build.cmd build all
third_party\openssl\build.cmd check all
third_party\openssl\build.cmd build all
third_party\openssl\build.cmd test debug safe
third_party\openssl\build.cmd test release safe
~~~

发布门禁如要求 full：

~~~cmd
third_party\openssl\build.cmd test release full
~~~

完整操作和 Skill 用法见 openssl-build-automation-guide.md。
