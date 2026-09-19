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
| 当前任务 | `T010-A`（Monorepo 骨架与可复现安装边界）**已完成并验证**；`T010-B`（GitHub Actions CI）待做 |
| 当前模块 | `M00-foundation-contracts`（T010-A 完成；T010-B 与 T011/T012 未开始） |
| 分支 | `feat/M00-foundation-contracts`（基于 `origin/main` @ `ddd16be`） |
| 状态 | `IN_PROGRESS`；骨架与三个 lockfile 就绪，11 项验证命令全部 exit 0 |
| 开始时间 | 2026-09-19 |
| 计划修改文件 | `package.json`、`pnpm-workspace.yaml`、`.npmrc`、`.gitattributes`、`.env.example`、`eslint.config.mjs`、`apps/desktop/**`、`packages/contracts/**`、`services/ai-core/**`、`scripts/contracts-check.mjs`、`README.md`、`PROJECT_STATUS.md`、`tasks/todo.md` |
| 下一检查点 | 用户审阅 T010-A → 授权 `T010-B`（GitHub Actions 最小 CI：contracts / web / python / rust / secrets 五个 job、Windows runner、零密钥） |

**执行顺序（2026-09-19 用户裁定，替代此前冲突描述）**：工具链预检与安装（T010 的第一步）→ `M00（T010–T012）` → `T001–T005` 风险 Spike → `Checkpoint A` → Phase 1 及之后的业务模块。M00 不再排在 Spike 之后。

## 4. 模块状态总表

允许状态：`NOT_STARTED`、`IN_PROGRESS`、`BLOCKED`、`READY_FOR_REVIEW`、`DONE`、`SUPERSEDED`。

| 模块 ID | 模块 | 优先级 | 状态 | 最后验证 | 证据/PR | 下一步 |
|---|---|:---:|---|---|---|---|
| `M00-foundation-contracts` | Monorepo、契约、CI、ADR 与规则 | P0 | IN_PROGRESS | 2026-09-19 T010-A 完成：11 项验证命令全部 exit 0；三个 lockfile 就绪 | [`SPEC-M00`](docs/specs/SPEC-M00-foundation-contracts.md)、`apps/`、`packages/`、`services/` | T010-B（CI）→ T011（契约）→ T012（设置与密钥）（**先于** T001–T005 Spike） |
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
- 已就绪的 Spec：[`docs/specs/SPEC-M00-foundation-contracts.md`](docs/specs/SPEC-M00-foundation-contracts.md)（**v1.2**，v1.1 已复核通过，v1.2 增补 README 文档基线验收项 AC-15～AC-18）。
- 文档基线：[`README.md`](README.md) 已建立（Living README，Pre-alpha 状态如实声明，用户使用指南按 10 个固定小节预留为"待实现"占位，不含未实现命令、虚构截图或下载地址）。维护规则见 [`AGENTS.md`](AGENTS.md)「README 维护规则」：README 与实际产品不一致时模块不得标记 `DONE`。
- 本机工具链（2026-09-19 已安装并固定版本）：
  - Git `2.51.0.windows.1`（`core.autocrlf` 生效，工作区 CRLF/仓库 LF，待 `.gitattributes` 统一）；Node `v22.20.0`（已写入 `.node-version`）；npm `10.9.3`（仅引导）；Corepack `0.34.0`；winget `v1.29.290`；WebView2 Runtime `153.0.4234.32`。
  - **pnpm `12.4.2`**（winget `pnpm.pnpm`，用户作用域）。`npm install -g pnpm` 失败：本机 npm 全局前缀是 `F:\JAVA_Tools\NodeJs`（Node 安装目录），非提权不可写（EPERM），故改用 winget。
  - **uv `0.12.17`**（winget `astral-sh.uv`，用户作用域）。
  - **Python `3.12.14`**（`uv python install 3.12`，由 uv 托管于 `%APPDATA%\uv\python\`）。系统 3.13.7 仍存在，但**不是**项目解释器。
  - **Rust `1.98.1` / cargo `1.98.1` / rustup `1.29.1`**，host `x86_64-pc-windows-msvc`，含 rustfmt 与 clippy。用官方 `rustup-init.exe` 安装（winget 的 `Rustlang.Rustup` 无用户作用域安装程序）。
  - 版本固定文件：`rust-toolchain.toml`（`channel = "1.98.1"` + rustfmt/clippy + `x86_64-pc-windows-msvc`，满足 D-5「必须写精确版本号」）、`.node-version`（`22.20.0`）。已在仓库内实测 `rustup show active-toolchain` → `overridden by rust-toolchain.toml`。
  - 未创建：`package.json` 的 `packageManager`（pnpm 固定）与 `.python-version`（Python 固定）——两者随 T010 的包清单一起落地，避免提前生成脚手架。
- 工具链预检（v2.0.1）：入口 `scripts/preflight.ps1`（短入口，仅 CLI 与退出码）+ 检查模块 `scripts/lib/PreflightChecks.psm1`（检查逻辑与可注入探针）+ 测试 `scripts/tests/preflight.Tests.ps1`（Pester 53 项，唯一自动化测试来源）。清单见 Spec §3.2。
- **预检缺陷（本轮发现并修复）**：v2.0.0 的 `Vswhere` 探针在 `GetNewClosure()` 闭包内读取模块作用域变量 `$script:VswhereCandidates`，而闭包只捕获**局部**变量，导致该变量恒为空、探针始终返回「未找到 vswhere」。后果是不会误报 MISSING（状态为 UNKNOWN，属安全的保守失败），但会给出错误的诊断方向。修复：把候选路径改为 `Get-RealProbes` 的参数（局部变量）并在闭包内捕获，新增 `Get-VswhereCandidatePaths` 与 3 项回归测试。本机正是 `C:\Program Files (x86)\...\Installer\vswhere.exe` 这一被漏检的位置。
- 预检执行结果（2026-09-19 修复后，报告模式，退出码 0；共 **14** 项：ok=12 missing=1 unknown=1）：
  - **已就绪（Blocking）**：Git、Node `v22.20.0`、pnpm `12.4.2`、uv `0.12.17`、Python `3.12`、rustc `1.98.1`、cargo `1.98.1`、WebView2 `153.0.4234.32`。
  - **缺失（Blocking）**：无。
  - **就绪明细 `msvc`（2026-09-19 用户完成 SDK 安装后）**：三部分齐备。VC 工具由 **Visual Studio Build Tools 2022 `17.14.37710.0`** 提供（`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`，VC 工具 `14.44.35207`），`link.exe` = `...\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\link.exe`；Windows SDK `10.0.26100.0` 位于 `C:\Program Files (x86)\Windows Kits\10\`，已实测存在 `Include\10.0.26100.0\um\windows.h` 与 `Lib\10.0.26100.0\um\x64\kernel32.Lib`。该行 status 为 `OK`，`version` = SDK 根路径。仍为**存在性检查**，真正的链接验证在 T010 的 `cargo build --locked`。
  - **无法判定（Advisory）**：`vbscript` —— 需提权才能查询按需功能状态；**仅为 MSI 打包前置项，非当前开发硬阻塞**。
  - JSON 报告写入 `tmp/preflight/`（已被 `.gitignore` 忽略）。`-OutputDirectory` 只允许指向 `tmp/preflight/` 或其子目录，仓库外路径被拒绝（退出码 2）。
- 安装副作用（已由用户处理，需知悉）：此前失败的 VS Build Tools 安装尝试（winget `Microsoft.VisualStudio.2022.BuildTools`，退出码 143）创建了 `C:\Program Files (x86)\Microsoft Visual Studio\Installer\`（含 `vswhere.exe`，这一发现反而让预检得以正确诊断）以及一个当时**不完整**的 `...\2022\BuildTools\` 目录树。用户随后通过 Visual Studio Installer 完成安装，该实例现已是**完整且已注册**的 VS 实例（Build Tools 2022 `17.14.37710.0`，实例目录 `_Instances\b672361a` 已生成 `state.json`）。
- 全部 Blocking 项就绪：**预检 `-RequireReady` 退出码 0**（报告模式 `VERDICT Ready`，14 项 ok=13 missing=0 unknown=1，唯一的 unknown 是 Advisory 级 `vbscript`）。
- Monorepo 骨架（T010-A，2026-09-19 完成）：
  - 根级工程规则：`.gitattributes`（统一 LF + 二进制标注）、`.npmrc`（peer 严格 / 不隐式装 peer / engine-strict）、`.env.example`（仅占位符）、`package.json`（private，`packageManager` 固定 `pnpm@12.4.2`）、`pnpm-workspace.yaml`（仅 `apps/*`、`packages/*`）、`eslint.config.mjs`。
  - 三个安装边界与三个权威 lockfile：
    - Node：`pnpm-lock.yaml`（根）— 3 个 workspace 项目，249 个条目通过 pnpm 供应链策略校验。
    - Python：`services/ai-core/uv.lock` — 18 个包。
    - Rust：`apps/desktop/src-tauri/Cargo.lock` — 430 个包。
  - `apps/desktop`：Tauri 2 + React + Vite 的最小可构建骨架（`src/`、`src-tauri/`、`capabilities/default.json`、`icons/icon.ico`）。刻意不注册任何 Tauri command。
  - `packages/contracts`：只有目录、README 与占位模块；**没有任何 schema 或生成物**（属 T011）。
  - `services/ai-core`：Python 3.12 包 `engm-ai-core`，仅含严格类型化的健康检查与 3 项测试。
  - `scripts/contracts-check.mjs`：契约目录结构检查，并显式报告"生成尚未启用"；检测到 schema/生成物即失败。
- 规模约束（本轮刻意不做）：无查词/语法/评分/RAG/导入/题库、无真实 API 调用、无密钥存储、无 GitHub Actions CI（T010-B）、无安装包、未启用 `bundle.active`。
- 待办提示：`winget list` 未把 Build Tools 2022 列为已安装包（不在其 ARP 记录中），因此后续升级/卸载应走 Visual Studio Installer 而不是 winget。
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
### 2026-09-19 — T010-A Monorepo 骨架与可复现安装边界（DONE；等待审阅）

- Agent/负责人：ZCode（用户授权 T010-A）
- 状态：DONE —— 11 项验证命令全部退出码 0
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR，未 push `main`，未 force push
- 完成内容：见 §8「Monorepo 骨架（T010-A）」。
- 未完成内容（**T010-B 及之后**）：GitHub Actions CI 未创建；`.gitleaks.toml` 与 secret 扫描未接入；契约内容（T011）、设置与密钥存储（T012）未开始。
- 关键文件：见 §3「计划修改文件」；新增 26 个文件、修改 0 个既有源文件。
- 接口/Schema 变化：无（`packages/contracts/schema/v1` 仍为空）
- 数据迁移：无
- ADR/决策：无新增 ADR。两处需要记录的技术决定（均在 `pnpm-workspace.yaml` 注释中说明）：
  1. `allowBuilds: esbuild: false` —— 不允许依赖在安装期执行脚本，正确性由 `pnpm build:web` 实测保证；
  2. `minimumReleaseAgeExclude` —— pnpm 12 的供应链保护要求把固定到精确版本、发布较新的包登记为例外（pnpm 自动写入，已补充说明）。
- 验证命令与结果（全部在仓库根执行，逐条退出码）：
  - `scripts/preflight.ps1 -RequireReady -NoJson -Quiet` → **0**
  - `pnpm install --frozen-lockfile` → **0**
  - `uv sync --locked --project services/ai-core` → **0**
  - `uv lock --check --project services/ai-core` → **0**
  - `cargo build --locked --manifest-path apps/desktop/src-tauri/Cargo.toml` → **0**
  - `pnpm lint`（eslint + ruff + cargo fmt/clippy）→ **0**
  - `pnpm typecheck`（tsc×2 + mypy --strict）→ **0**
  - `pnpm test`（vitest 6 项 + pytest 3 项 + cargo test 2 项）→ **0**
  - `pnpm build`（vite + cargo）→ **0**
  - `pnpm contracts:check` → **0**（显式报告生成未启用）
  - `git diff --check` → **0**
- 实际锁定版本：Node `22.20.0`、pnpm `12.4.2`、uv `0.12.17`、Python `3.12.14`、Rust/cargo `1.98.1`；前端 React/React-DOM `19.3.0`、Vite `7.3.6`、`@vitejs/plugin-react` `5.2.0`、TypeScript `5.9.3`、Vitest `4.1.11`、ESLint `10.11.0`、typescript-eslint `8.70.0`、`@tauri-apps/api` `2.11.1`、`@tauri-apps/cli` `2.11.4`；Rust `tauri` `2.11.5`、`tauri-build` `2.6.3`、`serde` `1.0.229`；Python `pydantic` `2.13.5`、`mypy` `2.3.1`、`pytest` `9.1.1`、`ruff` `0.16.8`。
- **首次建锁例外**：lockfile 首次生成使用非 frozen 模式（`pnpm install`、`uv sync`、`cargo generate-lockfile`），随后立即用 frozen/locked 命令复验通过。CLAUDE.md 要求记录该例外，特此登记。
- 过程中发现并修复的问题：
  1. `tauri-build` 在 Windows 上**总会**生成资源文件，因此要求 `src-tauri/icons/icon.ico` 存在，即使 `bundle.active=false`。首次 `cargo build` 因此失败（exit 101）。已生成合法的 32×32 32bpp 占位 ICO，来源与生成器见 `icons/README.md`。
  2. `cargo fmt --check` 首次未通过（测试断言换行方式）；已用 `cargo fmt` 修正。
  3. mypy 与 ruff 在"frozen 模型不可变"测试上冲突：mypy 禁止对只读属性赋值（B010 又禁止 `setattr` 常量属性）。最终使用普通赋值 + 精确的 `# type: ignore[misc]`，并在测试注释中说明理由。
  4. `uv run --project ... mypy` 从仓库根执行时无法发现项目配置；`test:py` / `typecheck:py` / `lint:py` 改为 `cd services/ai-core && uv run ...`，使每个工具在项目目录下运行（与 Spec §7 的字面写法不同，效果等价且更稳健）。
  5. `pnpm build` / `pnpm test` 中的 Rust 步骤依赖前端产物（`tauri::generate_context!` 在编译期嵌入 `dist`），故 `test:rust` 内置 `build:web`；该顺序约束已写入 README。
- 已知问题与风险：
  - MSVC 链接仍只是"存在性检查 + 一次成功的 `cargo build`"，尚未验证 release 构建与打包；真正的打包验证属于 T050。
  - `packages/contracts` 目前是空壳；在 T011 之前不要把它当成可用的契约来源。
  - `vbscript` 仍为 UNKNOWN（需提权查询），仅影响 MSI 打包，不阻塞当前工作。
  - 两个 VS 实例（Community `17.11.35303.130` 与 Build Tools `17.14.37710.0`）共存，`vswhere -latest` 解析到后者。
- 环境或密钥要求：无需任何密钥；未创建 `.env`；`.env.example` 只含占位符。
- 下一个 Agent 应先做：等待用户审阅 T010-A；获批后执行 **T010-B**：创建 `.github/workflows/ci.yml`（contracts / web / python / rust / secrets 五个 job、`windows-latest`、零密钥依赖、三方 Action 固定完整 SHA），并补 `.gitleaks.toml` 与 `pnpm check:secrets`。


### 2026-09-19 — Windows SDK 就绪验证（DONE；等待 T010 授权）

- Agent/负责人：ZCode（只读验证；SDK 由用户通过 Visual Studio Installer 安装）
- 状态：DONE（**只读验证**：未安装或删除任何软件，未修改注册表/环境变量/VS 安装）
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR，未 push `main`，未 force push
- 完成内容：
  - 只读验证 Windows SDK：`Test-Path "C:\Program Files (x86)\Windows Kits\10\Include"` → `True`；`...\Lib` → `True`；SDK 版本目录 `10.0.26100.0`；实测存在 `Include\10.0.26100.0\um\windows.h` 与 `Lib\10.0.26100.0\um\x64\kernel32.Lib`。
  - 预检 `-RequireReady -NoJson -Quiet` → **退出码 0**（此前为 1）。报告模式 `VERDICT Ready`，14 项 **ok=13 missing=0 unknown=1**，`blockingNotOk` 为空。
  - `msvc` 由 MISSING 变为 **OK**：VC 工具 + `link.exe` + Windows SDK 三部分齐备（证据见 §8）。
  - Pester **53/53** 通过（本轮未改动任何脚本或测试）。
  - 记录实例变化：用户通过 Visual Studio Installer 完成了 Build Tools 2022 实例（`17.14.37710.0`，VC 工具 `14.44.35207`），其 `_Instances\b672361a` 已生成 `state.json`、成为完整实例；原有 Community 2022（`17.11.35303.130`）仍在。`vswhere -latest` 现解析到 BuildTools（版本号更高）。
  - 同步更新 `README.md`：按 `AGENTS.md` 的 README 维护规则，删除「当前开发环境尚缺 Windows SDK」这一已过时提示，并更新工具链表。
- 未完成内容：T010 骨架、锁文件、CI、契约包均未创建——**等待用户授权**。
- 关键文件：`PROJECT_STATUS.md`、`tasks/todo.md`、`README.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增
- 验证命令与结果：
  - `Test-Path 'C:\Program Files (x86)\Windows Kits\10\Include'` → `True`
  - `Test-Path 'C:\Program Files (x86)\Windows Kits\10\Lib'` → `True`
  - `scripts/preflight.ps1 -RequireReady -NoJson -Quiet` → **退出码 0**
  - `scripts/preflight.ps1` → `VERDICT Ready`，`ok=13 missing=0 unknown=1`
  - `Invoke-Pester scripts/tests/preflight.Tests.ps1` → `Passed: 53 Failed: 0`
  - `git status --short` → 仅本次文档改动
- Eval/性能/Token 结果：不适用
- 已知问题与风险：
  - `msvc` 仍是**存在性检查**（VC 工具 + `link.exe` + SDK 目录），不是真实编译；真正的验证是 T010 的 `cargo build --locked`。若该构建失败，应优先怀疑此处。
  - `vbscript` 仍为 UNKNOWN（需提权查询），但它只是 MSI 打包前置项，不阻塞 T010。
  - `winget list` 未列出 Build Tools 2022，后续升级/卸载应走 Visual Studio Installer。
  - 本机现有两个 VS 实例（Community `17.11.35303.130` 与 Build Tools `17.14.37710.0`）；`vswhere -latest` 解析到版本更高的 BuildTools。若后续需要固定实例，应在 Spec 或 ADR 中明确选择依据。
- 环境或密钥要求：无需密钥；未创建 `.env`。
- 下一个 Agent 应先做：**等待用户授权进入 T010**；授权后建 Monorepo 骨架与 workspace、落 `.gitattributes`（先消除 CRLF 对漂移检查的影响）、三个锁文件、`.npmrc`/`.env.example`/`.gitleaks.toml` 与最小 CI，并在同一提交内按 Spec AC-1/AC-2/AC-6/AC-10/AC-12 验证。

### 2026-09-19 — 工具链安装与版本固化（IN_PROGRESS；MSVC/Windows SDK BLOCKED）

- Agent/负责人：ZCode（用户 Holmes 授权执行安装）
- 状态：**IN_PROGRESS / 部分 BLOCKED**。5 项已安装并固定；`msvc` 因缺 Windows SDK 且安装需管理员权限而阻塞。
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR（用户未授权），未 push `main`，未 force push
- 完成内容：
  - 安装并固定：**pnpm 12.4.2**（winget `pnpm.pnpm`，用户作用域）、**uv 0.12.17**（winget `astral-sh.uv`，用户作用域）、**Python 3.12.14**（`uv python install 3.12`）、**Rust/cargo 1.98.1 + rustup 1.29.1**（官方 `rustup-init.exe`，host `x86_64-pc-windows-msvc`，含 rustfmt/clippy）。
  - 新增版本固定文件：`rust-toolchain.toml`（精确版本 `1.98.1` + rustfmt/clippy + MSVC target，满足 D-5）、`.node-version`（`22.20.0`）。实测仓库内 `rustup show active-toolchain` 显示被 `rust-toolchain.toml` 覆盖。
  - 安装渠道核实：winget 包 ID 先用 `winget search` 只读核实（`pnpm.pnpm` / `astral-sh.uv` / `Rustlang.Rustup`）；`Rustlang.Rustup` 无用户作用域安装程序，故改用官方 rustup-init。
  - rustup-init 供应链校验：**未依赖代码签名**（官方产物此版本无 Authenticode 签名，`Get-AuthenticodeSignature` 报 `NotSigned`）。改为比对官方发布的 SHA-256（`6f4bef66…0bdb7e`）并从两个独立官方主机各下载一次，两个副本与发布校验值三者一致、字节完全相同后才执行；安装器临时文件已清理。
  - **修复预检缺陷（v2.0.0 → v2.0.1）**：`Vswhere` 探针在 `GetNewClosure()` 闭包内读取模块作用域变量，而闭包只捕获局部变量，导致 vswhere 恒被判为「未找到」。该缺陷不会误报 MISSING（返回 UNKNOWN，保守失败），但会误导诊断方向。修复为把候选路径作为 `Get-RealProbes` 参数注入，新增 `Get-VswhereCandidatePaths`，并补 3 项回归测试。
  - Pester 测试从 50 增至 **53 项，全部通过**。
- 未完成内容：
  - **Windows SDK 未安装**（唯一 Blocking 项）。`msvc` 检查要求 VC 工具 + `link.exe` + SDK 三者齐备：前两者由本机预装的 Visual Studio Community 2022 `17.11.3` 提供（VC 工具 `14.41.34120`），但注册表 `KitsRoot10` 指向的 `C:\Program Files (x86)\Windows Kits\10\` 下没有 `Include\` 与 `Lib\`，全盘无 `windows.h` / `kernel32.lib`。缺 SDK 无法链接 Windows 二进制。
  - 因此预检 `-RequireReady` 仍为退出码 1，不能进入 T010 的 `cargo build`/CI 验证。
  - Monorepo 骨架、锁文件、CI、契约包均未创建；`package.json` 的 `packageManager` 与 `.python-version` 未创建（随 T010 包清单落地）。
- 关键文件：`rust-toolchain.toml`（新建）、`.node-version`（新建）、`scripts/lib/PreflightChecks.psm1`、`scripts/tests/preflight.Tests.ps1`、`README.md`、`PROJECT_STATUS.md`、`tasks/todo.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增。MSVC 判定标准（VC 工具 + link.exe + SDK 三者齐备）沿用 Spec §3.3 与 D-5。
- 验证命令与结果：
  - `pnpm --version` → `12.4.2`；`uv --version` → `0.12.17`；`uv python list` → 含 `cpython-3.12.14`；`rustc --version --verbose` → `1.98.1`，`host: x86_64-pc-windows-msvc`；`cargo --version` → `1.98.1`
  - `rustup show active-toolchain` → `1.98.1-x86_64-pc-windows-msvc (overridden by 'G:\LanguageTeacherAgent-English\rust-toolchain.toml')`
  - `Invoke-Pester scripts/tests/preflight.Tests.ps1` → `Passed: 53 Failed: 0`
  - `scripts/preflight.ps1`（刷新 PATH 后）→ 14 项 `ok=12 missing=1 unknown=1`，`VERDICT NotReady`，退出码 0
  - `scripts/preflight.ps1 -RequireReady` → 退出码 **1**（因 `msvc`）
  - `sha256sum` 双源比对 rustup-init → 三者一致
- Eval/性能/Token 结果：不适用
- 已知问题与风险：
  - **安装副作用**：失败的 VS Build Tools 尝试（winget，退出码 143，未注册）在 `C:\Program Files (x86)\Microsoft Visual Studio\Installer\` 下留下 `vswhere.exe`（客观上让预检得以正确诊断），并留下不完整的 `...\2022\BuildTools\` 目录树。位于 Program Files 且需提权，可能与既有 VS 安装共享组件，**未自行删除**。
  - winget/rustup 安装过程按其自身行为修改了用户 PATH（新增 winget 包目录与 `%USERPROFILE%\.cargo\bin`）；这是安装器的标准行为，不是脚本所为。
  - `npm install -g pnpm` 在本机不可用（npm 全局前缀为 `F:\JAVA_Tools\NodeJs`，非提权不可写）。后续若需 npm 全局安装，应先与用户确认是否改 npm 前缀。
  - `stable` 与 `1.98.1` 两个 Rust 工具链同时存在（约多占一份磁盘）；`1.98.1` 为默认且被仓库固定，`stable` 可在用户确认后移除。
- 环境或密钥要求：无需密钥；未创建 `.env`。
- 下一个 Agent 应先做：**在提权的 PowerShell 中安装 Windows SDK**（例如 `winget install --id=Microsoft.VisualStudio.2022.BuildTools -e --override "--wait --passive --add Microsoft.VisualStudio.Component.Windows11SDK.26100"`，或对既有 VS Community 2022 用 VS Installer 勾选「Windows 11 SDK」），随后重跑 `scripts/preflight.ps1 -RequireReady` 直到退出码 0，再继续 T010 的 Monorepo 骨架、锁文件与 CI。

### 2026-09-19 — README 文档基线（DONE）

- Agent/负责人：ZCode（用户 Holmes 授权）
- 状态：DONE（**T010 仍未完成**；本小步只改文档，未安装软件、未生成脚手架）
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR（用户未授权），未 push `main`，未 force push
- 完成内容：
  - 新建根目录 `README.md`（中文为主，面向未来产品使用者）：如实声明 Pre-alpha、产品不能安装或使用；含 EngMentor 定位、当前状态表、P0/P1 计划功能与"明确暂不做"、10 个固定小节的用户使用指南占位、版权与隐私红线（含 Oxford 约束与 opt-in 上云）、开发者快速开始（仅列已确认技术栈与已实测命令）、项目结构、核心文档索引、贡献与开发纪律。
  - 已确认此文件中**不存在**：真实 API 密钥、Oxford 受限原文、虚构下载地址、未实现命令（`pnpm dev` 等一律未写）、截图。所有"待实现"小节明确标注且不含可执行步骤。
  - `AGENTS.md` 新增「README 维护规则」：影响安装/配置/数据/隐私/知识库/查词/语法/评分/导入/界面的改动必须在同一模块提交中同步更新 README；**README 与实际产品不一致时模块不得标记 `DONE`**；并把"更新 README"加入完成与交接的强制清单。
  - `SPEC-M00` 升到 v1.2：新增 AC-15（README 内部链接无断链）、AC-16（README 状态与 `PROJECT_STATUS.md` 一致）、AC-17（不含虚构内容）、AC-18（用户使用指南 10 小节结构 + 产品可用时的最终验收门禁）；目录结构与 T010 实施项同步加入 `README.md`。
- 未完成内容：工具链安装与版本固化（下一步）；Monorepo 骨架、锁文件、CI 均未创建。
- 关键文件：`README.md`（新建）、`AGENTS.md`、`docs/specs/SPEC-M00-foundation-contracts.md`、`PROJECT_STATUS.md`、`tasks/todo.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增。README 维护规则属流程约束，写入 `AGENTS.md` 而非 ADR。
- 验证命令与结果：
  - README 内容审查 → 无密钥、无 Oxford 受限原文、无虚构下载地址、无未实现命令、无截图
  - 相对链接检查（遍历仓库全部 Markdown，含新增 README）→ 0 条断链
  - `git diff --check` → 退出码 0
  - `git status --short` → 仅本次文档改动，无临时产物入库
- Eval/性能/Token 结果：不适用
- 已知问题与风险：README 的"开发者快速开始"有意只列已实测的预检与 Pester 命令；其余命令在 T010 完成并验证前保持"待补充"占位，避免出现未经验证的命令。
- 环境或密钥要求：无需任何密钥
- 下一个 Agent 应先做：执行已授权的工具链安装与版本固化，重跑预检至 Blocking 全绿，再继续 T010 骨架与 CI；此后每次用户可见改动都必须按 `AGENTS.md` 规则同步 README。

### 2026-09-19 — T010-preflight-fix：预检重构与加固（IN_PROGRESS，等待安装方案确认）

- Agent/负责人：ZCode（用户 Holmes 授权）
- 状态：IN_PROGRESS（**T010 未完成**；本小步仅重构预检并补齐检查项，未安装任何软件）
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR（用户未授权），未 push `main`，未 force push
- 完成内容：
  - **降低复杂度**：检查逻辑拆到 `scripts/lib/PreflightChecks.psm1`（含可注入探针），`scripts/preflight.ps1` 只保留 CLI 与退出码；删除脚本内与 Pester 重复的 `-SelfTest` 假场景框架，Pester 成为唯一自动化测试来源。保留默认报告、`-RequireReady`、`-NoJson`、JSON 报告与 PS 5.1/7 兼容。
  - **收紧 JSON 边界**：`Resolve-PreflightOutputDirectory` 只允许 `tmp/preflight/` 及其子目录；仓库外路径、仓库根、`tmp/` 下其他兄弟目录与 `..` 穿越一律拒绝并返回退出码 2。默认仍写入被忽略的 `tmp/preflight/`。
  - **补足 Windows 编译环境验证**：MSVC 检查现在要求 vswhere 的 VC Tools 组件、`link.exe`、Windows SDK（注册表 `KitsRoot10` 且 `Include\`/`Lib\` 目录存在）三者同时成立；缺任一即为 Blocking-not-ready（MISSING）。vswhere 无法回答时仍为 UNKNOWN，与"缺失"区分。
  - **安装渠道预检**：新增 `winget` 检查（Info，不阻塞），只读报告其可用性与版本；不执行 winget 查询或安装命令，仅列出下一阶段需核实的包 ID。
  - 退出码契约明确化：0 报告模式/-RequireReady 就绪；1 `-RequireReady` 未就绪；2 用法错误（如越界输出目录）；3 预检自身运行失败——三者与"工具缺失"互不混淆。
- 未完成内容：**安装与固化 pnpm / uv / Python 3.12 / Rust(MSVC) / MSVC Build Tools 均未执行**；Monorepo 骨架、`.gitattributes`、锁文件、CI 均未创建；T010 其余部分未开始。
- 关键文件：`scripts/preflight.ps1`、`scripts/lib/PreflightChecks.psm1`、`scripts/tests/preflight.Tests.ps1`、`PROJECT_STATUS.md`、`tasks/todo.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增。新增 `link.exe` + Windows SDK 验收使 MSVC 判断更严格，安装后必须重跑预检确认三项齐备。
- 验证命令与结果：
  - `Invoke-Pester scripts/tests/preflight.Tests.ps1` → `Passed: 50 Failed: 0`（含 MSVC 三要素、winget 非阻塞、输出目录边界、CLI 退出码 0/2、只读性与无密钥字段断言）
  - `scripts/preflight.ps1` → 14 项，`ok=6 missing=6 unknown=2`，`VERDICT NotReady`，**退出码 0**
  - `scripts/preflight.ps1 -RequireReady -NoJson -Quiet` → **退出码 1**
  - `git diff --check` → 退出码 0
  - `git status --short` → 仅本次改动文件，无临时产物入库
- Eval/性能/Token 结果：不适用（无代码、无 LLM 调用）
- 已知问题与风险：
  - MSVC 的 SDK 判定是基于注册表根 + `Include\`/`Lib\` 目录存在的**存在性检查**，不是真实编译；真正的验证是 T010 的 `cargo build --locked`。
  - 输出目录边界是词法包含检查（`Path.GetFullPath` 规范化 `..`，不解析 symlink/junction）。对本机开发脚本可接受，已在模块注释中说明。
  - Pester 测试仍使用 v3 断言语法（本机仅 Pester 3.4.0）；升级到 ≥ 4 时需转换为 `Should -Be`，文件头已注明。
  - `vbscript` 需在提权 shell 中重跑才能判定；不阻塞 T010。
- 环境或密钥要求：无需任何密钥；未创建 `.env`。
- 下一个 Agent 应先做：等待用户确认安装方案；确认后安装并固化上述工具链，重跑预检至 Blocking 全绿（`-RequireReady` 退出码 0），再继续 T010 骨架与 CI。

### 2026-09-19 — T010 第一小步：工具链预检（IN_PROGRESS，等待安装方案确认）

- Agent/负责人：ZCode（用户 Holmes 授权）
- 状态：IN_PROGRESS（**T010 未完成**；本小步仅交付预检脚本与预检结果，未安装任何软件）
- 分支：`feat/M00-foundation-contracts`
- Commit/PR：本分支提交；未创建 PR（用户未授权），未 push `main`，未 force push
- 完成内容：
  - 新增 `scripts/preflight.ps1`（v1.0.0）：只读、无副作用的环境盘点。不执行 winget/choco/npm install/corepack enable/rustup update；不修改环境变量、注册表、Git 配置或用户 Profile；不读取或输出任何密钥。
  - 三种运行模式：默认报告模式（工具缺失也输出完整盘点，退出码恒为 0）、`-RequireReady`（Blocking 项未就绪时退出码 1）、`-SelfTest`（用假探针跑四个场景）。
  - 输出人类可读摘要 + 机器可读 JSON；JSON 写入 `tmp/preflight/`（已被 `.gitignore` 忽略），`-NoJson` 可完全禁用写入。
  - 新增 `scripts/tests/preflight.Tests.ps1`：29 个 Pester 测试，覆盖「工具存在」「工具缺失」「vswhere 不存在」「注册表项缺失」四类路径，并含只读性静态断言与「报告不含密钥字段」断言。
  - `.gitignore` 忽略 ZCode 客户端生成的 `.zcodeignore`（IDE 本地文件，未入库）。
- 未完成内容：**安装与固化 pnpm / uv / Python 3.12 / Rust(MSVC) / MSVC Build Tools 均未执行**；Monorepo 骨架、`.gitattributes`、锁文件、CI 均未创建；T010 其余部分未开始。
- 关键文件：`scripts/preflight.ps1`、`scripts/tests/preflight.Tests.ps1`、`.gitignore`、`PROJECT_STATUS.md`、`tasks/todo.md`
- 接口/Schema 变化：无
- 数据迁移：无
- ADR/决策：无新增。预检暴露 6 项缺失与 2 项无法判定，安装方案需用户确认后再执行。
- 验证命令与结果：
  - `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1 -SelfTest` → `passed=28 failed=0`，退出码 0
  - `... -File scripts/preflight.ps1` → 报告模式输出 13 项检查，`ok=5 missing=6 unknown=2`，`VERDICT NotReady`，**退出码 0**（缺失项不被误判为脚本故障）
  - `... -File scripts/preflight.ps1 -RequireReady -NoJson -Quiet` → **退出码 1**
  - `Invoke-Pester scripts/tests/preflight.Tests.ps1` → `Passed: 29 Failed: 0`
  - `git check-ignore -v tmp/preflight/*.json` → 命中 `.gitignore:106:tmp/`，JSON 报告不入库
  - `git status --short` → 仅 `scripts/`、`.gitignore`、文档变更，无临时产物入库
- Eval/性能/Token 结果：不适用（无代码、无 LLM 调用）
- 已知问题与风险：
  - 6 项 Blocking 缺失（pnpm、uv、python312、rustc、cargo）与 2 项无法判定（msvc、vbscript）需在安装阶段解决；其中 `msvc` 因未找到 `vswhere.exe` 无法判定，安装 VS Build Tools 后应重跑预检确认。
  - `vbscript` 需在**提权** shell 中重跑才能判定；它只是 MSI 打包前置项，不阻塞 T010。
  - 预检脚本的输出为 ASCII，避免 Windows PowerShell 5.1 在中文代码页下的编码问题。
  - Pester 测试使用 v3 断言语法（`Should Be`），因为本机仅有 Pester 3.4.0；升级到 Pester ≥ 4 时需转换为 `Should -Be`（该转换只涉及测试文件，文件头已注明）。
- 环境或密钥要求：无需任何密钥；未创建 `.env`。
- 下一个 Agent 应先做：等待用户确认安装方案；确认后先安装并固化 `pnpm`、`uv`、Python 3.12、Rust（MSVC，`rust-toolchain.toml` 写精确版本号）与 MSVC Build Tools，再重跑预检至 Blocking 全绿，然后继续 T010 骨架与 CI。

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
