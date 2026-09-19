# 英语老师 AI Agent 桌面客户端任务清单

> 当前状态：**开发侧重点已转为「产品可用优先」**（2026-09-19 用户指令，优先于下方执行顺序）：目标是让用户能在自己电脑上真正用起来；CI / 发布工程 / 质量门禁投入暂停，已建成的不拆除。下一步：`T012`（设置与密钥存储，含本机凭据配置）→ 桌面壳可跑通的最小闭环（M01 + M03）。详见 `PROJECT_STATUS.md` §3 与最新交接记录。
>
> 历史状态：T000 已完成（含 2026-09-19 GitHub 安全同步，`main` @ `ddd16be`）；M00 Spec v1.3 **已复核通过**（见 [`docs/specs/SPEC-M00-foundation-contracts.md`](../docs/specs/SPEC-M00-foundation-contracts.md)）；`T010-A`（Monorepo 骨架与可复现安装边界）与 `T010-B`（GitHub Actions 最小 CI）**已完成并在本机验证**；`T011`（版本化本地契约）**已完成并在 GitHub 上 5/5 通过验证**。先完整阅读 [`PROJECT_STATUS.md`](../PROJECT_STATUS.md)。每完成一个模块或垂直切片，必须同步更新 `PROJECT_STATUS.md`。
>
> **执行顺序（2026-09-19 用户裁定）**：工具链预检与安装 → `M00（T010–T012）` → `T001–T005` 风险 Spike → `Checkpoint A` → Phase 2 及之后的业务模块。
> 说明：M00 是 Spike 的载体（Spike 证据需要 Monorepo、CI、契约信封与锁文件才能复现），因此 **M00 先于 Spike**；本清单把原 Phase 0（Spike）与原 Phase 1（工程地基）合并为 **Phase 0**，Phase 2 起的编号与统一方案一致。`Checkpoint A` 只门控 Phase 2 及之后的业务模块，不再门控 T010–T012。
>
> 门控：新增依赖或修改数据 Schema 前需先获批准（**Spike 与 Checkpoint A 已按用户 2026-09-19 指令不再作为产品功能的硬门禁**）；**CI 已在 GitHub 上 5/5 通过**（[run #2](https://github.com/Holmes522/LanguageTeacherAgent-English/actions/runs/35431617828)，触发器为 PR），可用同样的方式复验。

## Phase 0：工程地基与风险验证

### 0.1 工程地基（M00）

#### T010：创建 Monorepo 与 CI

> **拆分**：`T010-A`（Monorepo 骨架与可复现安装边界）与 `T010-B`（GitHub Actions 最小 CI）**均已完成并在本机验证**。

> 状态：**T010-A 已完成**（骨架、三个 lockfile、根级质量命令全部实测通过）；**T010-B 已完成**（工作流与两个自检脚本落地并在本机验证；**尚未在 GitHub 上运行过**，见下方验收说明）。

- [x] 交付并运行工具链预检：入口 `scripts/preflight.ps1` + 检查模块 `scripts/lib/PreflightChecks.psm1` + Pester `scripts/tests/preflight.Tests.ps1`（53 项通过，为唯一自动化测试来源）。逐项结果见 `PROJECT_STATUS.md` §8。
  - 已加固：JSON 输出限定在 `tmp/preflight/` 内（越界路径退出码 2）；MSVC 要求 VC Tools + `link.exe` + Windows SDK 三项齐备；新增 winget 渠道检查（Info，不阻塞）；退出码 0/1/2/3 语义互不混淆。
  - 已修复缺陷（v2.0.1）：`Vswhere` 探针在 `GetNewClosure()` 闭包内误读模块作用域变量，导致 vswhere 恒判为「未找到」（返回 UNKNOWN 而非误报 MISSING）；改为参数注入并补回归测试。
- [x] 安装工具链：pnpm `12.4.2`（winget `pnpm.pnpm`，用户作用域）、uv `0.12.17`（winget `astral-sh.uv`）、Python `3.12.14`（`uv python install`）、Rust/cargo `1.98.1` + rustup `1.29.1`（官方 rustup-init，host `x86_64-pc-windows-msvc`，含 rustfmt/clippy）。包 ID 先用 `winget search` 只读核实。
- [x] 固化版本：`rust-toolchain.toml`（精确 `1.98.1`，非 `stable`）、`.node-version`（`22.20.0`）；仓库内实测 `rustup show active-toolchain` 显示被 `rust-toolchain.toml` 覆盖。
- [x] 安装 Windows SDK 并让 `msvc` 变为 OK：用户通过 Visual Studio Installer 完成。SDK `10.0.26100.0` 位于 `C:\Program Files (x86)\Windows Kits\10\`（`Include\`、`Lib\` 均存在，实测有 `windows.h` 与 `x64\kernel32.Lib`），VC 工具与 `link.exe` 来自已完成的 Build Tools 2022 实例（`17.14.37710.0`，VC 工具 `14.44.35207`）。**预检 `-RequireReady` 退出码 0**。
- [x] 建立 Tauri/React、Python AI Core、contracts 和测试目录（`apps/desktop`、`services/ai-core`、`packages/contracts`）。
- [x] 落地 `.gitattributes`（统一 LF）、`.npmrc`、`.env.example`、`eslint.config.mjs`、根 `package.json`、`pnpm-workspace.yaml`（`.node-version` 与 `rust-toolchain.toml` 前一步已完成）。
- [x] 落地 `.gitleaks.toml`、`scripts/check-secrets.mjs`、`scripts/check-ignored.mjs` 与 `pnpm check:secrets`（T010-B）。配置文件**不含任何例外**；本机 gitleaks 固定 `8.30.1`，与 CI 的 `GITLEAKS_VERSION` 由脚本逐字断言，版本不符时拒绝扫描（退出码 2）。
- [x] 落地 `scripts/audit-capabilities.mjs` 与 `pnpm check:capabilities`（SPEC-M00 §5.4 第 3 层、AC-9）：审计 capability 文件的权限白名单、`Cargo.toml` 的特权插件与前端 `@tauri-apps/plugin-*` 依赖，并打印完整授权清单。
- [x] 配置三个权威 lockfile：`pnpm-lock.yaml`、`services/ai-core/uv.lock`、`apps/desktop/src-tauri/Cargo.lock`，并用 frozen/locked 模式复验。
- [x] **T010-B**：落地 `.github/workflows/ci.yml`（`web` / `python` / `rust` / `secrets` 四个 job，`windows-latest`，零密钥依赖，六条三方 Action 全部固定完整 SHA，触发器含 `push(main)` / `pull_request` / `workflow_dispatch`）。**`contracts` job 推迟到 T011**，因为它的两步命令（`pnpm contracts:generate`、`pnpm test:contracts`）都是 T011 的交付物。
  - **验收说明（已在 T011 之后补齐）**：本条写下时工作流尚未在 GitHub 上运行过（当时不允许创建 PR、不允许推 `main`，只有前两个触发器时不会有运行记录）。该缺口已由 2026-09-19 的真实运行补上：[run #2](https://github.com/Holmes522/LanguageTeacherAgent-English/actions/runs/35431617828) 显示 **5/5 job 通过**，其中 `secrets` 与 `contracts` 两个 job 在首次运行（run #1）中先失败、修复后才通过（见 ADR-008 与 PROJECT_STATUS 的对应交接记录）。
- 预检现状（2026-09-19 SDK 就绪后，14 项 **ok=13 missing=0 unknown=1**，`VERDICT Ready`）：Git 2.51.0 / Node v22.20.0 / pnpm 12.4.2 / uv 0.12.17 / Python 3.12 / rustc 1.98.1 / cargo 1.98.1 / **msvc（VC 工具 14.44.35207 + link.exe + SDK 10.0.26100.0）** / Corepack 0.34.0 / rustup 1.29.1 / winget v1.29.290 / WebView2 153.0.4234.32；唯一 unknown 为 Advisory 级 vbscript（需提权查询，仅 MSI 前置项）。
- 验收：Spec AC-1、AC-2、AC-6、AC-9、AC-10、AC-12、AC-15、AC-16、AC-17、AC-18 通过；两个自检脚本本机通过；README 与产品实际状态一致。**CI 在 GitHub 上的首次真实运行仍待完成**（需手动触发或开 PR）。
- 验证：`pnpm install --frozen-lockfile`、`uv sync --locked --project services/ai-core`、`uv lock --check --project services/ai-core`、`cargo build --locked`；`pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build`、`pnpm contracts:check`、`pnpm check:secrets`、`pnpm check:capabilities` 全绿。
- 依赖：M00 Spec v1.3（已复核通过）+ 工具链预检**已全部就绪**（`-RequireReady` 退出码 0）。

#### T011：实现版本化本地契约

> 状态：**本机已完成并验证**；唯一未完成项是"CI 的 `contracts` job 在 GitHub 上真实跑通"——工作流已写入
> `ci.yml`，但仓库无 PR、未推 `main`，Actions 从未被触发。

- [x] 定义 6 个契约来源（JSON Schema 2020-12）：`envelope`（成功/失败两形态）、`error`、`error-codes`（注册表，4 个码）、`job`、`citation`、`version`。不定义业务命令字段。
- [x] 自动生成 TypeScript 与 Python 类型（`json-schema-to-typescript` 16.0.0 + `datamodel-code-generator` 0.82.0）并检测漂移：`pnpm contracts:generate` / `pnpm contracts:check`（两段式，先断言再生成）。
- [x] Python 生成物落在可安装包 `engm-contracts`（`packages/contracts/python/`），由 `services/ai-core` 以 path 依赖消费；无 `PYTHONPATH` / `sys.path` / `conftest` 注入；mypy `--strict` 覆盖生成物且**无需任何 overrides 放宽**。
- [x] Rust 运行时 Schema 校验：`jsonschema` crate 0.56.0（`default-features = false`）、`include_str!` 嵌入、`OnceLock` 缓存；四条边界的畸形输入一律返回 `ENGM.CONTRACT.SCHEMA_INVALID`（不 panic、详情不含用户正文）；版本不一致返回 `ENGM.CONTRACT.VERSION_MISMATCH`；`schema-manifest.json` 的 SHA-256 嵌入一致性断言（AC-8）。
- [x] TS / Python / Rust 三方共用 `packages/contracts/tests/fixtures/contract-cases.json`，32 条正反例三方判定逐条一致（`pnpm test:contracts`）。
- [x] **补齐 CI 的 `contracts` job**：安装 → `uv sync --locked` → `pnpm contracts:generate` → `git diff --exit-code --stat` → `pnpm test:contracts`；五个 job 的 Action SHA 沿用 §8.1 已记录值。
- [x] **在 GitHub 上真实跑通一次 CI**（含 `contracts` job）：[run #2](https://github.com/Holmes522/LanguageTeacherAgent-English/actions/runs/35431617828)，5/5 job 成功（`web` 80s / `python` 33s / `rust` 160s / `contracts` 286s / `secrets` 19s）。首次运行（run #1）暴露的 2 个问题见下方记录与 ADR-008。注意触发器是 `pull_request`——`workflow_dispatch` 在本仓库不可用（工作流不在默认分支上）。
- 验收：Spec AC-3、AC-4、AC-5、AC-7、AC-8 本机通过；AC-4 的三方一致性以 32 条用例实测一致。
- 验证（全部真实退出码 0）：`pnpm contracts:check`（无漂移；手工改生成物则为 1）、`pnpm test:contracts`、`cargo test --locked`（13 项）、`uv sync --locked`、`uv lock --check`、`pnpm lint/typecheck/test/build`、`pnpm check:secrets`、`pnpm check:capabilities`。
- 依赖：T010（已完成）。

#### T012：实现设置和密钥存储

> 状态：**最小版本已完成**（2026-09-19，用户直令的「本机可用」切片）。验收项、验证方式与
> 缺口登记见 `PROJECT_STATUS.md` 最新交接记录；真实用户验收待做。

- [x] 模型与隐私模式设置：模型 id、服务地址、上云同意开关（Q5 的 opt-in，默认关闭，可随时关闭）。
  - 落在 `%APPDATA%\EngMentor\settings.json`，原子写；有测试断言序列化结果里**只有 3 个键**、不含任何密钥字段。
  - 「知识库设置」与「数据目录」仍待做（属 M02 的 SQLite 部分）。
- [x] DeepSeek 凭据存入安全存储：Windows 凭据管理器（`keyring` 4.2.0），服务名 `com.engmentor.desktop`。
  - Oxford 凭据未做（尚未接入 Oxford）。
- [x] 验收：**UI 不能读取完整密钥** —— 没有任何命令返回密钥，`settings_read` 只回 `credentialConfigured: bool`；
      前端解析快照时多出任何未知字段即整体拒绝。
- [x] 验收：**日志和数据库中没有密钥** —— 尚无数据库；日志侧有单测（错误文案不含密钥载荷）
      与 Python 子进程端到端用例（token/API Key 不出现在 stdout/stderr）双重断言。
- [x] 验证：`pnpm check:secrets` → 0；Rust 单测 46 项 + 真实凭据管理器往返用例通过。
  - 「E2E」一项由 `apps/desktop/src-tauri/tests/sidecar_integration.rs` 的 6 项 Rust↔Python 集成测试承担
    （需显式运行 `-- --ignored`，原因见 PROJECT_STATUS 的 G-6）。
- 依赖：T011（已完成）。

#### T002（部分完成）：DeepSeek Gateway 的最小可用版本

> 说明：用户 2026-09-19 直令「先跑通一次真实回答」，因此本任务先做了一个**最小版本**，
> 完整 Spike（结构化输出、预算、失败重试矩阵）仍未做。

- [x] 使用配置里的 model id 完成**流式请求**：`POST {base_url}/chat/completions`（`stream: true`），
      只用标准库 `urllib`，逐帧 SSE 解析。
- [x] 流式回答经 Tauri `Channel` 推到界面并逐字渲染。
- [ ] 结构化输出（JSON Output + Pydantic 校验）。
- [ ] 超时、限流、截断、取消与预算上限的完整处理（目前只有 60s 超时与可读的失败信封）。
- [ ] `ENGM.LLM.*` 错误码域（当前借用 `INVALID_INPUT` / `INTERNAL_UNEXPECTED`，缺口 G-1）。
- 验收：结构化输出通过 Pydantic；失败不会无限重试 —— **未做**。
- 验证：mock 测试 + 一次脱敏的真实 API smoke test —— **待用户用真实密钥验收**。
- 依赖：T011（已完成）。

### 0.2 风险验证（Spike）

#### T001：验证 Tauri Python Sidecar

- [ ] Tauri 启动、健康检查、停止 PyInstaller Sidecar。
- [ ] 验证 Windows 安装包和崩溃恢复；若产出 MSI，先执行 VBSCRIPT 检查（Spec §3.3）并记录结论。
- [ ] 输出 ADR-001、ADR-002。
- 验收：干净 Windows VM 能完成安装、启动、退出，不留僵尸进程。
- 验证：自动化 smoke test + 手工安装录像。
- 依赖：T010–T012（需要 Monorepo、CI 与契约作为证据载体）。

#### T002：验证 DeepSeek Gateway

- [ ] 使用 `deepseek-flash` 完成流式请求和 JSON Output。
- [ ] 验证空输出、超时、限流、截断、取消和预算上限。
- 验收：结构化输出通过 Pydantic；失败不会无限重试。
- 验证：mock 测试 + 一次脱敏的真实 API smoke test。
- 依赖：T011。

#### T003：验证文件导入

- [ ] PDF、DOCX、DOC 各准备正常、损坏和恶意样本。
- [ ] 比较并确定旧 DOC 解析方案。
- [ ] 输出 ADR-005。
- 验收：三种格式均有明确的成功路径与可理解的失败信息。
- 验证：fixture 集成测试和资源限制测试。
- 依赖：T010。

#### T004：验证本地检索

- [ ] 本地 Embedding、FTS5、Qdrant Local/Edge 持久化。
- [ ] 建立 30–50 个问题的最小检索集。
- [ ] 输出 ADR-003。
- 验收：重启后索引可用，引用能定位页码/段落。
- 验证：Recall@K、MRR 和删除测试。
- 依赖：T010。

#### T005：定义评分量表

- [ ] 确认句子/作文维度、权重、CEFR 映射和免责声明。
- [ ] 建立最小人工标注集。
- [ ] 输出 ADR-006。
- 验收：量表可由人类独立使用，模型输出 schema 完整。
- 验证：双人抽样评分一致性评审。
- 依赖：T011。

## Checkpoint A：架构确认

> 只门控 Phase 2 及之后的业务模块；T010–T012 不再受此门控（2026-09-19 裁定）。

- [ ] T001–T005 完成。
- [ ] ADR-001 至 ADR-007 通过评审。
- [ ] 负责人明确批准进入实现阶段。

## 已完成任务记录

### T000：确认产品边界与授权 ✅ DONE（2026-09-19）

- [x] 核对项目真实状态并形成接手报告。
- [x] 为 Q1–Q8 给出推荐、影响和阻塞分析。
- [x] 用户确认 Windows/macOS 范围、评分量表、隐私模式和 `.doc` 支持标准。
- [x] 用户确认 Q7/Q8（Embedding 体积、P1 顺序）。
- [x] 为 Oxford 授权指定负责人（Holmes 跟进）；在线连接器 + 开放词典 fallback；离线索引待书面授权，此前禁止持久化/向量化 Oxford 内容。
- [x] 安全核对并连接 GitHub 仓库（2026-09-19 ZCode 完成：只读确认为空仓库 → `git init -b main` → 初始提交 `237a337` → 推送 `origin/main`，未强推）。
- 验收：Q1–Q8 有负责人、结论；远程连接作为独立门控步骤待确认。
- 验证：用户 2026-09-19 确认 Q1–Q8；决策记录见 [`T000 产品边界与技术决策`](../docs/decisions/T000-产品边界与技术决策建议.md)。
- 依赖：无。

## Checkpoint B：基础设施

> 与 Checkpoint A 一同门控 Phase 2；其中「Sidecar 异常能自动恢复」依赖 T001 的结论。

- [ ] 干净 Windows VM 安装启动通过。
- [ ] CI 全绿且无密钥泄露。
- [ ] Sidecar 异常能自动恢复或给出明确操作。

## Phase 2：知识库垂直切片

### T020：知识源管理

- [ ] 创建、启停、选择默认/会话知识源。
- [ ] 展示来源类型、授权、索引和健康状态。
- 验收：选择状态在重启后保持，未授权源不可被误用。
- 验证：单元 + E2E。
- 依赖：Checkpoint B。

### T021：文件导入后台任务

- [ ] PDF/DOCX/DOC 校验、隔离解析、进度和错误。
- [ ] 幂等导入与取消。
- 验收：重复导入不会产生重复文档和向量。
- 验证：fixture 集成测试、安全测试。
- 依赖：T020。

### T022：分块与本地索引

- [ ] 保存块文本、层级、页码、哈希和许可元数据。
- [ ] 写入 FTS5 与向量索引。
- 验收：重启后可检索，更新只重建变化部分。
- 验证：索引一致性测试。
- 依赖：T021。

### T023：混合检索与引用

- [ ] Dense + FTS 召回、过滤、去重、重排和 Token 预算。
- [ ] 返回可点击引用和证据预览。
- 验收：默认上下文不超过 1,800 tokens；越权文档不参与检索。
- 验证：RAG 评测集 + 权限测试。
- 依赖：T022。

### T024：删除和重建索引

- [ ] 删除 SQLite、FTS、向量、缓存和临时文件。
- [ ] 支持单文档与单知识库重建。
- 验收：删除后任何路径均无法检索原文。
- 验证：端到端删除测试。
- 依赖：T023。

## Checkpoint C：知识库闭环

- [ ] PDF/DOCX/DOC 到带定位引用回答全流程通过。
- [ ] 检索、Token、安全和删除指标达到目标。

## Phase 3：教学核心

### T030：结构化查词

- [ ] 词形规范化、连接器、来源/许可展示和受控缓存。
- [ ] Oxford 无授权时使用明确 fallback。
- 验收：每个词典事实都有来源；LLM 生成内容被单独标记。
- 验证：连接器契约测试 + E2E。
- 依赖：Checkpoint C。

### T031：语法导师

- [ ] 错误定位、规则检索、解释、正误例句、练习和引用。
- 验收：无证据时不伪造规则来源。
- 验证：语法黄金集和引用抽检。
- 依赖：Checkpoint C。

### T032：句子评分

- [ ] 分项评分、置信度、证据、纠错与改写。
- 验收：输出契约稳定，短文本置信度合理降低。
- 验证：人工样本回归和重复运行稳定性。
- 依赖：T002、T005、Checkpoint C。

### T033：作文评分

- [ ] 任务要求、分项分、CEFR 估计、证据、优先修改项和修订稿。
- 验收：明确非正式考试成绩；总分与分项一致。
- 验证：至少 100 篇人工标注集评测。
- 依赖：T032。

## Checkpoint D：MVP

- [ ] 查词来源覆盖率 100%。
- [ ] 引用覆盖率、评分解析率和稳定性达到主方案指标。
- [ ] Windows 完整 E2E、依赖审计和安全测试通过。

## Phase 4：P1 学习闭环

### T040：题库抽取与人工复核

- [ ] 抽取题干、选项、答案、解析、标签和来源坐标。
- [ ] 未审批题目不能进入正式练习。
- 验收：用户能修订并批准题目。
- 验证：多类题型 fixture + E2E。
- 依赖：Checkpoint D。

### T041：练习、错题本与复习

- [ ] 练习会话、判分、错误档案、复习队列和掌握度。
- 验收：一次错误能进入复习并更新后续状态。
- 验证：端到端学习循环。
- 依赖：T040。

### T042：OCR 与导出

- [ ] 扫描 PDF OCR、置信度校正、Markdown/PDF 导出。
- 验收：低置信度内容不会静默进入正式索引。
- 验证：扫描样本与导出视觉检查。
- 依赖：T021。

## Phase 5：发布

### T050：Windows 发布门禁

- [ ] 代码签名、自动更新、备份、迁移、回滚、SBOM、许可证清单。
- 验收：干净 VM 安装/升级/卸载通过，用户数据按预期保留或删除。
- 验证：Release Candidate 清单和签名校验。
- 依赖：Checkpoint D。
