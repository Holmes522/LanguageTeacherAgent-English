# 英语老师 AI Agent 桌面客户端任务清单

> 当前状态：T000 已完成（含 2026-09-19 GitHub 安全同步，`main` @ `ddd16be`）；M00 Spec v1.1 **已复核通过**（见 [`docs/specs/SPEC-M00-foundation-contracts.md`](../docs/specs/SPEC-M00-foundation-contracts.md)）；T010 进行中——工具链预检已交付并运行，**安装未开始，T010 未完成**。先完整阅读 [`PROJECT_STATUS.md`](../PROJECT_STATUS.md)。每完成一个模块或垂直切片，必须同步更新 `PROJECT_STATUS.md`。
>
> **执行顺序（2026-09-19 用户裁定）**：工具链预检与安装 → `M00（T010–T012）` → `T001–T005` 风险 Spike → `Checkpoint A` → Phase 2 及之后的业务模块。
> 说明：M00 是 Spike 的载体（Spike 证据需要 Monorepo、CI、契约信封与锁文件才能复现），因此 **M00 先于 Spike**；本清单把原 Phase 0（Spike）与原 Phase 1（工程地基）合并为 **Phase 0**，Phase 2 起的编号与统一方案一致。`Checkpoint A` 只门控 Phase 2 及之后的业务模块，不再门控 T010–T012。
>
> 门控：**安装软件前必须获得用户对安装方案的确认**；在此之前不安装依赖、不生成 Tauri 脚手架、不开始编码。

## Phase 0：工程地基与风险验证

### 0.1 工程地基（M00）

#### T010：创建 Monorepo 与 CI

> 状态：**进行中，未完成**。第一小步（工具链预检）已交付；安装、骨架、锁文件与 CI 均未开始。

- [x] 交付并运行工具链预检：`scripts/preflight.ps1` + `scripts/tests/preflight.Tests.ps1`（Pester 29 项通过，自检 28 项通过）。逐项结果见 `PROJECT_STATUS.md` §8。
- [ ] **安装并固化版本**（等待用户确认安装方案）：pnpm、uv、Python 3.12、Rust（`rust-toolchain.toml` 提交精确版本号，不得只写 `stable`）、MSVC C++ Build Tools；安装后重跑预检至 Blocking 全绿。
- [ ] 建立 Tauri/React、Python AI Core、contracts 和测试目录。
- [ ] 落地 `.gitattributes`（统一 LF）、`.node-version`、`.npmrc`、`.env.example`、`.gitleaks.toml`。
- [ ] 配置 pnpm、uv、Rust 锁文件与 GitHub Actions 最小 CI（5 个 job，Windows runner）。
- 预检现状（2026-09-19）：已就绪 Git 2.51.0 / Node v22.20.0 / npm 10.9.3 / Corepack 0.34.0 / WebView2 153.0.4234.32；缺失 pnpm、uv、Python 3.12、rustc、cargo；无法判定 msvc（无 `vswhere.exe`）与 vbscript（需提权，且仅为 MSI 前置项）。
- 验收：Spec AC-1、AC-2、AC-6、AC-10、AC-12 通过；空骨架在 Windows CI 完整构建。
- 验证：`pnpm install --frozen-lockfile`、`uv sync --locked --project services/ai-core`、`uv lock --check --project services/ai-core`、`cargo build --locked`；`pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build` 全绿。
- 依赖：M00 Spec v1.1（已复核通过）+ 工具链预检（已运行；安装待确认）。

#### T011：实现版本化本地契约

- [ ] 定义统一响应、错误、Citation、Job 和进度事件 schema（JSON Schema 2020-12）。
- [ ] 自动生成 TypeScript 与 Python 类型（json-schema-to-typescript + datamodel-code-generator）并检测漂移。
- [ ] Python 生成物落在可安装包 `engm-contracts`（`packages/contracts/python/`），由 uv path 依赖消费，禁止 `PYTHONPATH` 技巧。
- [ ] 落地 Rust 运行时 Schema 校验：覆盖 WebView↔Rust 与 Rust↔Python 四条边的双向校验，失败返回 `ENGM.CONTRACT.SCHEMA_INVALID`；`schema-manifest.json` 嵌入一致性测试。
- [ ] TS / Python / Rust 三方使用同一组正反例 fixtures，结论必须一致。
- 验收：Spec AC-3、AC-4、AC-5、AC-7、AC-8 通过。
- 验证：`pnpm contracts:check`、`pnpm test:contracts`、`cargo test --locked`。
- 依赖：T010。

#### T012：实现设置和密钥存储

- [ ] 模型、数据目录、隐私模式和知识库设置。
- [ ] DeepSeek/Oxford 凭据存入安全存储。
- 验收：UI 不能读取完整密钥；日志和数据库中没有密钥。
- 验证：E2E + `pnpm check:secrets`。
- 依赖：T011。

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
