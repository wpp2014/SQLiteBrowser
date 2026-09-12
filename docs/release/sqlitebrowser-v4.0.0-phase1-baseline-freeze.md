# SQLiteBrowser v4.0.0 阶段一实施记录（固定绿色基线）

> 实施日期：2026-09-12  
> 分支：`upgrade/v4.0.0`  
> 阶段：1（固定绿色基线）  
> 说明：本记录仅冻结已通过的 CI 基线，不包含代码逻辑修改、tag 创建或发布动作。

## 1. 基线标识（唯一追溯）

- **Commit（基线提交）**：`a28466325e2fee974c285625e0b669d5cedc78b9`  
  提交标题：`Install required Qt runtime modules in Windows CI`
- **Workflow Run**：`34039874959`  
  URL：<https://github.com/wpp2014/SQLiteBrowser/actions/runs/34039874959>
- **Workflow**：`Build (Windows v4)`（[cppcmake-windows.yml](../../.github/workflows/cppcmake-windows.yml)）
- **Trigger**：`workflow_dispatch`
- **Run 结论**：`success`
- **Job**：`windows-2022-x64-release`  
  Job URL：<https://github.com/wpp2014/SQLiteBrowser/actions/runs/34039874959/job/101504572065>  
  Job 结论：`success`
- **Run 时间窗口（UTC）**：`2026-09-06T14:39:53Z` ~ `2026-09-06T15:22:58Z`（约 43 分钟）

## 2. 已冻结证据

### 2.1 GitHub 日志证据

- Workflow Run 日志页面：<https://github.com/wpp2014/SQLiteBrowser/actions/runs/34039874959>
- Job 日志页面（`windows-2022-x64-release`）：<https://github.com/wpp2014/SQLiteBrowser/actions/runs/34039874959/job/101504572065>
- Run 全量日志 ZIP（下载链接，带时效性）：<https://results-receiver.actions.githubusercontent.com/rest/runs/94f1dfb9-3f13-48a6-aece-c95f4eac19f6/logs?filename=logs_92227039237.zip&signature=1789178644.ba915da6a213823a932725c1617fa140327d33545fa2e81f317f1125fc746aeb>

关键证据行（来自同一 Job 日志）：

- `L34`：`Complete job name: windows-2022-x64-release`
- `L10404`：`100% tests passed, 0 tests failed out of 13`（zlib）
- `L10439`：`100% tests passed, 0 tests failed out of 1`（zstd）
- `L10481`：`100% tests passed, 0 tests failed out of 1`（brotli）
- `L42542`：`100% tests passed, 0 tests failed out of 1`（OpenSSL focused/safe链路）
- `L42750`：`100% tests passed, 0 tests failed out of 4`（应用单元测试）
- `L43423`：`-- OpenSSL Brotli smoke: passed`
- `L43425`：`-- SQLiteBrowser restricted-PATH runtime smoke suite passed.`

### 2.2 GitHub Artifact 证据

- Artifact 名称：`windows-v4-release-diagnostics-1`
- Artifact ID：`9991983388`
- Digest：`sha256:da16f19391fcee200b4b301668cc09c0949661e35d99df5f9137f2b7c24dd6a6`
- API URL：<https://api.github.com/repos/wpp2014/SQLiteBrowser/actions/artifacts/9991983388>
- 下载 URL：<https://api.github.com/repos/wpp2014/SQLiteBrowser/actions/artifacts/9991983388/zip>
- 过期时间（UTC）：`2026-09-13T15:22:47Z`

## 3. 阶段一范围确认（已执行 / 未执行）

### 已执行

1. 固化成功提交 SHA、workflow run 和 job 的一一映射；
2. 固化 GitHub 日志链接与关键通过证据；
3. 固化 diagnostics artifact 标识（名称、ID、digest、下载位置）。

### 未执行（按阶段计划保持不做）

1. 不创建 `v4.0.0` tag；
2. 不创建或发布 GitHub Release；
3. 不进行代码逻辑修改；
4. 不调整顶层 workflow 编排（该项属于阶段二）。

## 4. 阶段一完成判定（DoD）

- [x] Commit / Run / Job 可唯一对应；  
- [x] 通过证据可复查（GitHub 日志 + GitHub artifact）；  
- [x] 明确保持“仅冻结基线，不发布、不打 tag”。
