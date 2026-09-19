# PROJECT STATUS — Agent 必读交接文件

> **这是所有 Claude Code、Zcode 及其他 AI Agent 接手项目时必须读取的第一份文件。**  
> 文件用途：记录当前真实状态、已完成模块、验证证据、阻塞项、未提交改动和下一步。  
> 更新时间：2026-09-19（Asia/Shanghai）  
> 当前阶段：规划与架构评审  
> 当前维护者：Holmes（Claude Code 协助）

## 1. 新 Agent 启动协议

开始任何分析或修改前，严格按顺序执行：

1. 完整阅读本文件。
2. 阅读根目录 `AGENTS.md`；Claude Code 还必须阅读 `CLAUDE.md`。
3. 阅读 [`docs/英语老师AI-Agent-统一产品与技术开发方案.md`](docs/英语老师AI-Agent-统一产品与技术开发方案.md) 中与当前模块相关的章节。
4. 阅读当前模块的 `docs/specs/SPEC-<module-id>.md`、相关 ADR、测试和源码；不存在时不得直接编码，应先补 Spec。
5. 阅读 `tasks/todo.md`，只领取一个依赖已经满足的任务。
6. 检查 `git status`、当前分支和最近提交，确认没有覆盖其他人的未完成工作。
7. 在开始工作前，把本文件的“当前工作”更新为自己的任务、分支和计划。

如果本文件与代码、测试或 Git 状态冲突，**不要猜**。在“发现的冲突”中记录证据并请求确认。

## 2. 文档优先级

发生冲突时按以下顺序处理：

1. 用户最新明确指令。
2. 已接受的 ADR。
3. 当前模块已批准的 Spec。
4. 本文件记录的当前事实与验证证据。
5. 统一产品与技术开发方案。
6. `tasks/todo.md` 与 `tasks/plan.md`。
7. 已被替代的两份历史方案，仅用于追溯。

## 3. 当前工作

| 字段 | 当前值 |
|---|---|
| Agent/负责人 | ZCode（用户 Holmes 授权） |
| 当前任务 | M00 Spec 审阅修订：`docs/specs/SPEC-M00-foundation-contracts.md` v1.1（待复核） |
| 当前模块 | `M00-foundation-contracts`（Spec 修订阶段，未开始编码） |
| 分支 | `feat/M00-foundation-contracts`（基于 `origin/main` @ `ddd16be`） |
| 状态 | `IN_PROGRESS`（Spec v1.1 待复核；复核通过前不安装、不编码） |
| 开始时间 | 2026-09-19 |
| 计划修改文件 | `docs/specs/SPEC-M00-foundation-contracts.md`、`PROJECT_STATUS.md`、`tasks/todo.md`、`tasks/plan.md`、`docs/英语老师AI-Agent-统一产品与技术开发方案.md` |
| 下一检查点 | Spec v1.1 复核通过 → 运行 `scripts/preflight.ps1` 工具链预检 → 安装并固化 pnpm/uv/Rust → 执行 T010 |

**执行顺序（2026-09-19 用户裁定，替代此前冲突描述）**：工具链预检与安装（T010 的第一步）→ `M00（T010–T012）` → `T001–T005` 风险 Spike → `Checkpoint A` → Phase 1 及之后的业务模块。M00 不再排在 Spike 之后。

## 4. 模块状态总表

允许状态：`NOT_STARTED`、`IN_PROGRESS`、`BLOCKED`、`READY_FOR_REVIEW`、`DONE`、`SUPERSEDED`。

| 模块 ID | 模块 | 优先级 | 状态 | 最后验证 | 证据/PR | 下一步 |
|---|---|:---:|---|---|---|---|
| `M00-foundation-contracts` | Monorepo、契约、CI、ADR 与规则 | P0 | IN_PROGRESS | 2026-09-19 Q1–Q8 已确认；Spec v1.1 已修订待复核；`main` @ `ddd16be` 已同步 | [`SPEC-M00`](docs/specs/SPEC-M00-foundation-contracts.md)、[`T000 决策`](docs/decisions/T000-产品边界与技术决策建议.md) | 复核 Spec v1.1 → 工具链预检与安装 → T010–T012（**先于** T001–T005 Spike） |
| `M01-desktop-shell` | Tauri 桌面壳、Sidecar、安装更新 | P0 | NOT_STARTED | — | — | Sidecar Spike |
| `M02-local-storage-settings` | SQLite、迁移、设置、密钥 | P0 | NOT_STARTED | — | — | 等待 M00/M01 |
| `M03-llm-gateway` | DeepSeek、流式、结构化输出、预算 | P0 | NOT_STARTED | — | — | DeepSeek Spike |
| `M04-knowledge-registry` | 知识源、授权、选择和状态 | P0 | NOT_STARTED | — | — | 等待 M02 |
| `M05-document-ingestion` | PDF/DOC/DOCX、安全解析与索引任务 | P0 | NOT_STARTED | — | — | DOC 方案 Spike |
| `M06-retrieval-citations` | 分层路由、混合检索、引用 | P0 | NOT_STARTED | — | — | 检索 Spike |
| `M07-dictionary` | 结构化查词、词形、来源 | P0 | NOT_STARTED | — | — | 确认词典授权/fallback |
| `M08-grammar-tutor` | 语法诊断、讲解、例句、练习 | P0 | NOT_STARTED | — | — | 等待 M06 |
| `M09-writing-assessment` | 句子/作文评分与修订建议 | P0 | NOT_STARTED | — | — | 量表 Spike |
| `M10-question-bank` | 题库导入、检索；后续结构化复核 | P0/P1 | NOT_STARTED | — | — | 等待 M05/M06 |
| `M11-learning-loop` | 错题、SRS、档案与进步 | P1 | NOT_STARTED | — | — | 等待教学模块 |
| `M12-quality-release` | Eval、观测、安全、打包发布 | P0 横向 | NOT_STARTED | — | — | 从 M00 开始接入 |

## 5. 已完成模块记录

当前没有已完成的实现模块。

模块只有同时满足以下条件才能标记 `DONE`：

- Spec 的全部验收标准通过。
- 相关单元、契约、集成/E2E、Eval 均通过。
- 构建和静态检查通过。
- 安全、隐私、Token 预算没有未解释的回归。
- 文档、ADR、任务状态和本文件已经更新。
- 变更已经进入 PR 或有可定位的 commit；遗留问题已明确记录。

## 6. 产品与技术决策（Q1–Q8）

下表已由用户于 2026-09-19 逐项确认，状态均为 `RESOLVED`。完整决策与理由见 [`docs/decisions/T000-产品边界与技术决策建议.md`](docs/decisions/T000-产品边界与技术决策建议.md)。

| ID | 决策（已确认） | 影响/阻塞 | 负责人 | 状态 |
|---|---|---|---|---|
| Q1 | 开放许可 fallback 先行；Oxford 在线连接器；离线索引等书面授权（此前禁止持久化/向量化 Oxford 内容） | 部分阻塞 Oxford 离线 RAG | 产品/法务（Holmes 跟进授权） | RESOLVED |
| Q2 | Windows-only 首发；macOS P1 | 弱阻塞构建矩阵 | 产品 | RESOLVED |
| Q3 | PDF/DOCX 开箱；DOC 可选 legacy importer | 弱阻塞安装策略 | 产品/技术 | RESOLVED |
| Q4 | 通用百分制 + 低置信度 CEFR 估计；无考试专项 | 强阻塞 M09 Spec（已解除） | 产品/教研 | RESOLVED |
| Q5 | 用户明确同意后最小内容上云；可关闭；完全离线 P2 | 强阻塞 M03/M09 隐私策略（已解除） | 产品/法务 | RESOLVED |
| Q6 | 备考学生/自学者第一；教师第二 | 弱阻塞默认 UX | 产品 | RESOLVED |
| Q7 | 接受约 100–200 MB 轻量 Embedding 模型包 | 影响首次体验 | 产品/技术 | RESOLVED（非阻塞） |
| Q8 | P1 先错题/SRS，后题库复核工作台 | 影响 P1 顺序 | 产品 | RESOLVED（非阻塞） |

## 7. 已接受的关键事实

- 产品必须以桌面客户端形式交付，Windows 优先。
- 主模型通过 DeepSeek API 接入，公开调用名配置为 `deepseek-flash`。
- 查词的确定性数据优先结构化查询，不使用 LLM 重新生成事实。
- 用户资料本地优先；本地 Embedding；只把当前请求所需最小证据发给云模型。
- 普通 Oxford API 连接器和获授权离线词典索引是两种不同模式，不能混用。
- PDF、DOC、DOCX 是必需导入格式；扫描 PDF OCR 可后置。
- 每个答案的事实性知识应带可定位来源；无证据时拒绝编造。

## 8. 仓库与验证基线

- Git：已初始化，默认分支 `main`，`origin` = `https://github.com/Holmes522/LanguageTeacherAgent-English.git`。
- 远程只读核对（2026-09-19，写操作前执行）：公开仓库、`default_branch=main`、`size=0`、无分支/标签/提交（`commits` API 返回 409、`contents` 返回 404），确认为空仓库后才执行首次推送。
- 首次同步（2026-09-19）：`main` 初始提交 `237a337f144a391477734bca8c70dbf0aedc820d`（`docs: initialize project specifications and T000 decisions`），随后同步状态更新提交 `ddd16be24a97bb3b0bbe1992c29ddadd36018d3a`（`docs: record GitHub remote sync status and initial commit SHA`）。
- `main` 当前 SHA：**`ddd16be24a97bb3b0bbe1992c29ddadd36018d3a`**；本地 `main` 与 `origin/main` 一致。两次推送均未使用 force push。
- 功能分支：`feat/M00-foundation-contracts`（基于 `origin/main` @ `ddd16be`），已推送并与 `origin` 同步。
- 同步内容：`.gitignore`、`AGENTS.md`、`CLAUDE.md`、`PROJECT_STATUS.md`、`docs/**`、`tasks/**`，共 10 个文本文件、3,945 行。
- 排除内容：`.claude/settings.local.json`（IDE/Agent 本地文件，已由 `.gitignore` 忽略，未入库）。
- 入库安全扫描：暂存内容无密钥、真实用户数据、未授权词典内容、模型权重或构建产物；工作区无二进制文件与超过 200 KB 的大文件。
- 源码：尚未创建。
- 测试：尚未创建。
- CI：尚未创建。
- 已就绪的 Spec：[`docs/specs/SPEC-M00-foundation-contracts.md`](docs/specs/SPEC-M00-foundation-contracts.md)（**v1.1**，已按用户 2026-09-19 审阅结论修订，待复核）。
- 本机工具链基线（2026-09-19 只读核对）：Git 2.51.0.windows.1（`core.autocrlf` 生效，工作区 CRLF/仓库 LF，待 `.gitattributes` 统一）；Node v22.20.0 ✅；npm 10.9.3（仅引导）；**pnpm 未安装**；系统 Python 3.13.7（项目固定 3.12，由 uv 管理，**不使用系统解释器**）；**uv 未安装**；**Rust/Cargo 未安装**；**MSVC C++ Build Tools 未核对**；**WebView2 Runtime 未核对**；**VBSCRIPT 按需功能未核对**。
- 工具链预检：清单见 Spec §3.2，脚本 `scripts/preflight.ps1` 于 T010 落地；预检必须在安装与编码之前完成并公开逐项结果。
- 已有规划文档：统一方案、实施计划、任务清单和两份历史方案。
- 未授权事项（勿自行执行）：分支保护、PR 创建、`gh` CLI 安装与认证、Actions 首次运行、安装依赖与生成脚手架（须在 M00 Spec 获批后）。

## 9. 发现的冲突

当前已解决的文档冲突：

- 历史长版 PRD 采用 Next.js/PostgreSQL/Redis/K8s Web/SaaS 架构；用户后续明确要求桌面客户端，因此统一方案以 Tauri + 本地 Sidecar/SQLite 为准。
- 历史长版 PRD 将账号鉴权列为 P0；本地单用户桌面 MVP 不需要账号，账号/云同步后移。
- 历史长版 PRD使用 `bge-m3` 和本地 Reranker；统一方案首版采用资源更轻的 `bge-small-en-v1.5`，把 `bge-m3` 作为可选高质量模型包。
- 历史方案对题库优先级不一致；统一方案把“PDF/DOC/DOCX 可导入、可检索”设为 P0，把高精度自动切题和人工复核工作台设为 P1。

2026-09-19 新发现并已解决的冲突：

- **执行顺序冲突**：`tasks/todo.md` 把 T010（M00 实现）的依赖写成“Checkpoint A：T000–T005 完成且 ADR-001~006 批准”，而统一方案 §9 把 `M00` 列为所有模块的前置，`PROJECT_STATUS.md` 又把下一步写成先做 M00 Spec 再执行 T010。
  **裁定（用户 2026-09-19）**：`M00（T010–T012）` **先于** `T001–T005` Spike 执行。理由：Spike 的可复现证据需要 Monorepo、CI、契约信封与锁文件作为载体，否则 Spike 结论无处落地。
  **后果**：`Checkpoint A` 改为只门控 Phase 1 及之后的业务模块（T020+），不再门控 T010–T012；T001–T005 仍然产出 ADR-001~007。已同步修订 `tasks/todo.md` 与本节。
- **锁文件位置冲突**：统一方案 §22 把 `uv.lock` 列在仓库根，但 uv 的 lockfile 必须与定义项目的 `pyproject.toml` 同目录，而根目录没有 Python 项目。
  **裁定（用户 2026-09-19，D-4）**：`uv.lock` 放在 `services/ai-core/uv.lock`；统一方案 §22 的旧描述已同步修正，并在该节加注锁文件位置说明。

## 10. 模块完成后的强制更新模板

完成一个模块或可交付垂直切片后，Agent 必须：

1. 更新“当前工作”和“模块状态总表”。
2. 在本节下方新增一条记录，最新记录放最上面。
3. 更新 `tasks/todo.md` 对应复选框。
4. 如决策发生变化，先更新/新增 ADR，再更新统一方案。
5. 提交时把 `PROJECT_STATUS.md` 与代码放在同一 PR/commit 中。

复制以下模板：

```markdown
### YYYY-MM-DD HH:mm — <module-id> / <task-id>

- Agent/负责人：
- 状态：READY_FOR_REVIEW | DONE | BLOCKED
- 分支：
- Commit/PR：
- 完成内容：
- 未完成内容：
- 关键文件：
- 接口/Schema 变化：
- 数据迁移：无 | 路径与回滚方式
- ADR/决策：无 | 链接
- 验证命令与结果：
  - `<command>` → PASS/FAIL（摘要）
- Eval/性能/Token 结果：
- 已知问题与风险：
- 环境或密钥要求：
- 下一个 Agent 应先做：
```

## 11. 交接记录

### 2026-09-19 — M00 Spec 审阅修订（READY_FOR_REVIEW）

- Agent/负责人：ZCode（用户 Holmes 审阅）
- 状态：READY_FOR_REVIEW（等 Spec v1.1 复核；复核通过后才进入工具链预检与安装）
- 分支：`feat/M00-foundation-contracts`（基于 `origin/main` @ `ddd16be`）
- Commit/PR：本分支提交；未创建 PR（用户未授权），未 push `main`，未 force push
- 完成内容：
  - Spec 升级到 v1.1，逐条落实用户审阅结论 D-1～D-6 与 7 项必改要求（详见 Spec §14 变更记录）。
  - 修订 1：所有 uv 命令由 `--frozen` 改为 `--locked`，并新增 `uv lock --check`；同步修正 `tasks/plan.md` 的 Verification Commands。
  - 修订 2：新增 Spec §5.3「Rust 运行时 JSON Schema 校验」，覆盖 WebView↔Rust、Rust↔Python 四条边的双向校验、`ENGM.CONTRACT.SCHEMA_INVALID`、版本协商与 `schema-manifest.json` 嵌入一致性。
  - 修订 3：Python 生成物改为可安装本地包 `engm-contracts`（`packages/contracts/python/`），由 uv path 依赖安装；明确禁止 `PYTHONPATH`/`sys.path` 技巧并加入 AC-3 检查。
  - 修订 4：WebView 无外网改为 ESLint + CSP `connect-src` + 不授予 HTTP capability 三层防护（Spec §5.4），三层各自可独立验证（AC-9）。
  - 修订 5：工具链预检新增 MSVC C++ Build Tools 与 WebView2（Spec §3.2 含具体命令），MSI 前置新增 VBSCRIPT 检查（Spec §3.3、AC-11）。
  - 修订 6：修正 `PROJECT_STATUS.md` 的 `main` SHA（`237a337` → `ddd16be`，并区分初始提交与状态提交）与 M00/T010 对 Phase 0 Spike 的顺序矛盾（已裁定 M00 在前，见 §9）；同步更新 `tasks/todo.md`。
  - 修订 7：清理新 Spec 的 Markdown 行尾空格。
  - 附带修正：统一方案 §22 的 `uv.lock` 位置（D-4）并加注锁文件位置说明。
- 未完成内容：Spec v1.1 未复核；工具链未预检、未安装；未生成 Tauri 脚手架；未开始 T001–T005。
- 关键文件：`docs/specs/SPEC-M00-foundation-contracts.md`、`PROJECT_STATUS.md`、`tasks/todo.md`、`tasks/plan.md`、`docs/英语老师AI-Agent-统一产品与技术开发方案.md`
- 接口/Schema 变化：Spec 定义契约骨架与 Rust 运行时校验策略，**仍未创建实际文件**
- 数据迁移：无
- ADR/决策：D-1～D-6 已由用户确认并写入 Spec §11；Spike 阶段的 ADR-001～ADR-007 仍未产出
- 验证命令与结果：
  - `git diff --check` → 退出码 0（仅 CRLF 转换提示；无行尾空格、无冲突标记）
  - `git status --short` → 5 个文件被修改：`PROJECT_STATUS.md`、`docs/specs/SPEC-M00-foundation-contracts.md`、`docs/英语老师AI-Agent-统一产品与技术开发方案.md`、`tasks/plan.md`、`tasks/todo.md`
  - 行尾空格检查（新 Spec）→ 0 命中（`PROJECT_STATUS.md` 与统一方案的文件头旧行尾空格为既有内容，本轮未扩大改动范围）
  - `--frozen` 残留检查 → 仅剩 `pnpm install --frozen-lockfile` 与对本次变更的说明文字；无 `uv sync --frozen`
  - 内部链接检查（遍历 10 个 Markdown 文件、18 条相对链接）→ 全部可解析
  - 结构检查 → `tasks/todo.md` 无重复任务块（T001/T010 各出现 1 次）
- Eval/性能/Token 结果：不适用（无代码）
- 已知问题与风险：见 Spec §13；最前置风险是 pnpm/uv/Rust 未安装且 MSVC/WebView2/VBSCRIPT 未核对，T010 必须先过预检
- 环境或密钥要求：无需任何密钥
- 下一个 Agent 应先做：等用户复核 Spec v1.1；通过后落地 `scripts/preflight.ps1` 并运行工具链预检，再执行 T010

### 2026-09-19 — M00 Spec 编写（READY_FOR_REVIEW）

- Agent/负责人：ZCode（用户 Holmes 审阅）
- 状态：READY_FOR_REVIEW
- 分支：`feat/M00-foundation-contracts`（基于 `origin/main` @ `ddd16be`）
- Commit/PR：本分支提交；未创建 PR（用户未授权）
- 完成内容：
  - 新建 `docs/specs/SPEC-M00-foundation-contracts.md`（v1.0-draft），覆盖用户要求的全部范围：Monorepo 目录结构、三层边界与 8 条强制规则、pnpm/uv/Cargo 版本与锁文件策略、lint/typecheck/test/build/contracts 目标命令、GitHub Actions 最小 CI（5 个 job、Windows runner、零密钥）、`.env.example` 与密钥/本地数据安全边界、10 条可执行验收标准、非目标清单。
  - 显式记录与统一方案 §22 的 3 处差异（`uv.lock` 位置、`Cargo.lock`、`.gitattributes`/`.node-version`/`.npmrc`），未静默选择。
  - 列出 6 项待确认决策（D-1～D-6：mypy、契约生成器、secret 扫描 Action、`uv.lock` 位置、Rust 工具链、Tauri 版本锁定）。
- 未完成内容：Spec 未获批准，未安装任何依赖，未生成 Tauri 脚手架，未开始 T001。
- 关键文件：`docs/specs/SPEC-M00-foundation-contracts.md`（新建）、`PROJECT_STATUS.md`、`tasks/todo.md`
- 接口/Schema 变化：Spec 中定义契约骨架（`envelope`、`error`、`error-codes`、`job`、`citation`、`version`），**尚未创建实际文件**
- 数据迁移：无
- ADR/决策：D-2 若偏离本 Spec 的契约生成器方案，需先写 ADR-008
- 验证命令与结果：
  - 只读核对本机工具链 → Node v22.20.0 / npm 10.9.3 / Python 3.13.7 存在；pnpm / uv / cargo 缺失（已记入 Spec §3 与状态文件 §8）
  - `git log --oneline -1` → `ddd16be`
  - 本模块无代码，故无 lint/test/build 结果可报告
- Eval/性能/Token 结果：不适用
- 已知问题与风险：见 Spec §13；最前置的风险是本机缺 pnpm/uv/Rust，T010 第一动作是安装并固化版本；`.gitattributes` 必须在契约漂移检查之前落地，否则 CRLF 会导致假失败。
- 环境或密钥要求：无需任何密钥；Spec 明确 CI 不依赖 secret，缺 key 时相关测试必须 skip。
- 下一个 Agent 应先做：等待用户审阅 M00 Spec 与 D-1～D-6；批准后执行 T010，第一步安装并锁定 pnpm/uv/Rust。

### 2026-09-19 — T000 收尾：GitHub 安全初始化与首次同步（DONE）

- Agent/负责人：ZCode（用户 Holmes 授权）
- 状态：DONE
- 分支：`main`（首次推送时为 `origin/main` @ `237a337`；随后同步状态提交为 `ddd16be`，当前值见 §8）
- Commit/PR：`237a337f144a391477734bca8c70dbf0aedc820d`（无 PR，用户未授权创建）
- 完成内容：
  - 按启动顺序完整阅读 `PROJECT_STATUS.md`、`AGENTS.md`、`CLAUDE.md`、统一方案、T000 决策、`tasks/plan.md`、`tasks/todo.md`。
  - 写操作前只读核对远程：`git ls-remote` 无任何 ref；API `size=0`、`branches=[]`、`tags=[]`、`commits` 409、`contents` 404，确认远程为空仓库。
  - 创建 `.gitignore`（密钥、依赖、构建产物、本地数据库、向量索引、模型权重、用户上传、日志、IDE 临时文件）。
  - `git init -b main`，添加 `origin`，仅暂存规则、文档、任务清单与 `.gitignore`。
  - 审查 staged diff：10 个文本文件、3,945 行、无二进制、无密钥命中；`.claude/` 已被忽略。
  - 创建初始提交（Conventional Commit）并 `git push -u origin main`，未使用 force push。
  - 回读远程 `refs/heads/main` 确认与本地 `HEAD` 一致。
- 未完成内容：M00 Spec 编写；T001–T005 Spike 未开始；分支保护与 Actions 由用户在网页端处理。
- 关键文件：`.gitignore`、`PROJECT_STATUS.md`、`tasks/todo.md`、`docs/decisions/T000-产品边界与技术决策建议.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增；T000 的 Q1–Q8 保持已确认状态
- 验证命令与结果：
  - `git ls-remote <origin>` → 无 ref（空仓库确认）
  - `curl https://api.github.com/repos/Holmes522/LanguageTeacherAgent-English` → `size=0`, `default_branch=main`, `private=false`
  - `git diff --cached --numstat` → 10 个文本文件，无二进制
  - `git push -u origin main` → `PUSH_EXIT=0`，`[new branch] main -> main`
  - `git ls-remote origin` → `237a337…` `refs/heads/main`，与 `git rev-parse HEAD` 一致
- Eval/性能/Token 结果：不适用（本轮无代码）
- 已知问题与风险：
  - 推送认证依赖本机 Git Credential Manager；后续 Agent 首次 push 时若凭据过期会交互式提示。
  - 工作区行尾为 CRLF、仓库内为 LF（`core.autocrlf`）；建议后续在 M00 增加 `.gitattributes` 统一策略（本轮未授权，未添加）。
  - 远程为空仓库时首次推送的默认分支由本地 `main` 决定；仓库设置中的默认分支已复核为 `main`。
  - 未启用分支保护，`main` 目前允许直接 push（用户网页端处理）。
- 环境或密钥要求：无新增；本轮未创建任何密钥或 `.env`。
- 下一个 Agent 应先做：编写 `docs/specs/SPEC-M00-foundation-contracts.md` 并等待审阅；未获批准前不安装依赖、不生成 Tauri 脚手架、不开始 T001。

### 2026-09-19 — T000 决策确认（DONE）

- Agent/负责人：Claude Code（用户 Holmes 确认）
- 状态：DONE
- 分支：无；本地尚未初始化 Git
- 完成内容：Q1–Q8 由用户逐项确认并写入决策文件；`PROJECT_STATUS.md` 与 `tasks/todo.md` 同步更新；T000 决策部分完成。
- 未完成内容：远程 GitHub 安全同步方案待确认后执行（本地 Git 初始化与连接）。
- 关键文件：`docs/decisions/T000-产品边界与技术决策建议.md`、`PROJECT_STATUS.md`、`tasks/todo.md`
- 验证结果：Q1–Q8 均有结论；Oxford 约束（授权前禁止持久化/向量化）已写入。
- 已知问题：远程仓库经只读检查为“存在、公开、空仓库”（无分支/提交）；`gh` CLI 未安装。
- 下一个 Agent 应先做：确认远程同步方案 → 初始化本地 Git 并连接远程 → 启动 T001。

### 2026-09-19 — T000 Claude Code 接手报告

- Agent/负责人：Claude Code（报告由用户提供并合并）
- 状态：IN_PROGRESS
- 分支：无；本地尚未初始化 Git
- 完成内容：核对项目目标、技术方向和真实状态；为 Q1–Q8 给出推荐默认值；提出 T001–T005 Spike 顺序。
- 未完成内容：用户尚未批准 Q1–Q8；Oxford 法务 owner/deadline 未定；GitHub 尚未连接。
- 关键文件：`docs/decisions/T000-产品边界与技术决策建议.md`
- 验证结果：现有文档与接手报告的阶段、技术栈、模块状态一致。
- 已知问题：Q4/Q5 是 M09/M03 的强阻塞；Q3 的 DOC 降级方案是否满足原始需求仍需用户确认。
- 下一个 Agent 应先做：等待用户逐项批准/修改 Q1–Q8；批准后更新本文件并安全核对远程 GitHub。

### 2026-09-19 — 规划文档统一

- Agent/负责人：Codex
- 状态：DONE（仅文档工作）
- 分支：无；仓库尚未初始化
- 完成内容：合并两份产品/技术方案；建立统一方案、Agent 必读状态文件和规则入口。
- 关键文件：`PROJECT_STATUS.md`、`AGENTS.md`、`CLAUDE.md`、`docs/英语老师AI-Agent-统一产品与技术开发方案.md`
- 验证：文件存在、Markdown 结构与内部引用检查。
- 已知问题：Q1–Q6 尚未确认，不能开始规模化实现。
- 下一个 Agent 应先做：T000，确认产品边界与授权，然后执行风险 Spike。
