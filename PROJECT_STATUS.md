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
| Agent/负责人 | Claude Code（用户 Holmes 确认） |
| 当前任务 | T000：确认产品边界与授权（已 DONE；下一步 T001 Sidecar Spike） |
| 当前模块 | `M00-foundation-contracts`（规划阶段） |
| 分支 | 尚未初始化 Git 仓库 |
| 状态 | `DONE` |
| 开始时间 | 2026-09-19 |
| 计划修改文件 | `PROJECT_STATUS.md`、`tasks/todo.md`、`docs/decisions/T000-产品边界与技术决策建议.md` |
| 下一检查点 | 用户确认远程同步方案 → 初始化本地 Git 并连接远程 → 启动 T001–T005 |

## 4. 模块状态总表

允许状态：`NOT_STARTED`、`IN_PROGRESS`、`BLOCKED`、`READY_FOR_REVIEW`、`DONE`、`SUPERSEDED`。

| 模块 ID | 模块 | 优先级 | 状态 | 最后验证 | 证据/PR | 下一步 |
|---|---|:---:|---|---|---|---|
| `M00-foundation-contracts` | Monorepo、契约、CI、ADR 与规则 | P0 | IN_PROGRESS | 2026-09-19 Q1–Q8 已确认 | [`T000 决策`](docs/decisions/T000-产品边界与技术决策建议.md) | 完成 T001–T005 Spike 并批准 ADR-001~006 |
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

- Git：当前目录尚未初始化为 Git 仓库。
- 目标 GitHub：`https://github.com/Holmes522/LanguageTeacherAgent-English`；本地尚未添加/核对 `origin`。
- 源码：尚未创建。
- 测试：尚未创建。
- CI：尚未创建。
- 已有规划文档：统一方案、实施计划、任务清单和两份历史方案。

## 9. 发现的冲突

当前已解决的文档冲突：

- 历史长版 PRD 采用 Next.js/PostgreSQL/Redis/K8s Web/SaaS 架构；用户后续明确要求桌面客户端，因此统一方案以 Tauri + 本地 Sidecar/SQLite 为准。
- 历史长版 PRD 将账号鉴权列为 P0；本地单用户桌面 MVP 不需要账号，账号/云同步后移。
- 历史长版 PRD使用 `bge-m3` 和本地 Reranker；统一方案首版采用资源更轻的 `bge-small-en-v1.5`，把 `bge-m3` 作为可选高质量模型包。
- 历史方案对题库优先级不一致；统一方案把“PDF/DOC/DOCX 可导入、可检索”设为 P0，把高精度自动切题和人工复核工作台设为 P1。

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
