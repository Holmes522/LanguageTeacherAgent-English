# EngMentor（英师）

> **当前状态：Pre-alpha（开发早期）**
> EngMentor 还**不能安装、不能下载、不能使用**。仓库里目前有一个**可构建、可测试的空骨架**——桌面壳能编译、能启动，但界面只有一张说明"尚未实现"的页面——以及一套已固定版本的开发工具链。
> **没有任何教学功能**，没有安装包，也没有可供试用的界面。本文件是"随产品成长的文档"：功能一旦真正实现并验证，对应章节才会从"计划"改为"可用"。**在章节标注为"待实现"时，请不要把它当作操作说明。**

---

## EngMentor 是什么

EngMentor 是一款 **Windows 优先的本地桌面英语学习助手**。

它要解决的问题是：查词、学语法、改作文、做练习目前分散在多个工具里，而且通用聊天模型经常编造释义、例句或语法依据，用户无法核验。EngMentor 的设计方向是：

- **有出处**：每个事实性回答都带可定位的来源；没有证据时明确拒答，而不是编造。
- **可解释的评分**：写作评分给出分项、扣分证据和可执行的修改建议，而不是一个总评。
- **知识库可插拔**：可以选用开放许可词典，也可以导入你自己的教材、讲义、词表和题库。
- **本地优先**：你的资料、索引和学习记录默认留在本机。只有在你明确同意后，才把完成当前任务所需的**最小内容**发送给云端模型。
- **成本可控**：能在本地确定性完成的（例如精确查词）不调用大模型。

第一优先用户是**备考学生和个人自学者**，第二优先是需要导入教辅资料的教师。

## 当前状态

**Pre-alpha：产品尚不能安装或使用。**

| 项目 | 状态 |
|---|---|
| 产品与技术方案（统一方案） | 已完成并存档 |
| T000 产品边界与技术决策（Q1–Q8） | 已完成，逐项由负责人确认 |
| M00 工程设计 Spec（Monorepo、契约、CI） | v1.3，已复核通过 |
| 工具链预检脚本（只读） | 已交付并运行（53 项测试通过） |
| 开发工具链（Node / pnpm / uv / Python / Rust / MSVC / SDK） | **已安装、已固定版本，预检门禁通过** |
| Monorepo 骨架（T010-A） | **已建立**：workspace、三个 lockfile、质量命令可运行 |
| 源代码（React / Rust / Python） | **只有空骨架**：可构建、可测试，但没有任何教学功能 |
| 本机安全自检（密钥扫描、敏感路径忽略、能力清单） | **已交付并在本机通过**（gitleaks 8.30.1） |
| 版本化契约内容（JSON Schema 与生成类型） | **尚未创建**（T011） |
| CI（GitHub Actions） | **已创建，但从未在 GitHub 上运行过**（T010-B；契约 job 属 T011） |
| Windows 安装包 | **尚未创建** |
| 界面与截图 | **不存在**（骨架界面只显示"还没做什么"） |

**能跑起来的只有开发流程，不是产品。** 现在可以执行安装依赖、静态检查、类型检查、测试与构建；
但查词、语法、评分、导入等能力一个都没有实现。桌面壳启动后只会显示一张尚未实现的说明页。

下一步（建设中）：**在 GitHub 上实跑一次 CI**（工作流已提交，但至今没有任何一次远程运行记录，因此它的可用性尚未被证明）→ 落地版本化契约与契约 job（T011）→ 设置与密钥存储骨架（T012）→ 风险验证（Spike）→ 按模块实现教学功能。

实时、权威的进度以 [`PROJECT_STATUS.md`](PROJECT_STATUS.md) 为准；本文件的状态表只能比它更粗，不能比它更乐观。

## 计划功能与优先级

以下全部是**计划**，目前没有任何一项可以试用。优先级定义：P0 = 没有它就无法验证核心价值或不能安全发布；P1 = 补齐学习闭环的第一批增强；P2 = 差异化能力。

### P0（MVP 目标）

| 功能 | 说明 |
|---|---|
| 知识源管理与选择 | 选择默认知识源与会话知识源、多库组合，并显示授权、索引与健康状态；未获授权的来源显示为"未连接"，不会被伪装成默认源 |
| 带来源的查词 | 词形还原、英/美音标、词性、分义项释义、真实例句、搭配与语域，每一项单独标注来源；未收录词给出拼写候选或明确"未收录"，不编造 |
| 语法讲解 | 标出问题片段 → 诊断与置信度 → 引用规则解释原因 → 正误对比 → 最小修改与自然改写 → 1–3 道小练习 → 展示来源 |
| 句子评分 | 百分制：语法 40、词汇 25、自然度 25、拼写标点 10，附证据与建议 |
| 作文评分 | 百分制：任务完成 25、组织连贯 20、词汇 20、语法范围与准确性 25、规范性 10；含低置信度 CEFR 估计与优先修改项 |
| PDF / DOCX / DOC 导入 | 文件先做真实类型与安全检查再解析；`.doc` 通过可选的 legacy importer 处理（系统装有 LibreOffice 时转换，否则提示转为 `.docx`） |
| 检索与引用（RAG） | 混合检索后给出可点击引用，定位到页码或段落；默认证据上下文不超过约 1,800 tokens |
| 安全删除 | 删除文档后，其文本、检索索引、向量与缓存都不可再被检索到 |

评分一律注明是 **AI 学习反馈，不是正式考试成绩**；不提供考试专项评分量表。

### P1（MVP 之后）

| 功能 | 说明 |
|---|---|
| 题库结构化与人工复核 | 从导入资料中抽取题干、选项、答案、解析与来源坐标；**未经人工批准**的题目不会进入正式练习 |
| 错题本与间隔复习（SRS） | 错误沉淀、复习排程、掌握度更新 |
| 学习档案 | 版本比较、进步曲线、薄弱点报告 |
| OCR 与导出 | 扫描版 PDF 的 OCR（低置信度内容必须人工校正）；报告导出为 Markdown / PDF |

### 明确暂不做

账号注册与云同步、教师班级后台与多租户、实时语音与发音评测、社区、移动端、全自动出卷。完全离线模式（本地大模型）属 P2。

## 用户使用指南

> **产品完成后，这里将成为正式使用流程。**
> 现在下列小节只是**结构占位**：它们说明每一节将来会写什么、依赖哪个模块。产品还不能安装或使用，因此这里**不含任何可执行的操作步骤**。当某个功能真正交付时，对应小节会在同一次改动中改写成可照做的步骤，并附上实际界面截图。

### 1. 安装与升级

**待实现。** 将说明：从何处获取 Windows 安装包；系统要求；安装步骤；升级方式与升级时的数据处理；如何确认安装包来源可信（签名校验）。依赖：M01 桌面壳与发布流程（T050）。

### 2. 首次启动与隐私设置

**待实现。** 将说明：首次启动的画面与需要做的选择；隐私模式的含义与切换方式；哪些内容会留在本机、哪些内容在什么条件下才会离开本机；如何随时撤回同意。依赖：M02 本地存储与设置。

### 3. 配置 DeepSeek

**待实现。** 将说明：如何填写并安全保存 DeepSeek API 凭据；凭据存放在操作系统凭据存储而不是明文文件；如何测试连接；如何关闭云端处理。依赖：M03 模型网关、M02 密钥存储。

### 4. 选择知识库

**待实现。** 将说明：默认知识源与会话知识源的区别与切换方式；如何看懂一个来源的授权状态、索引状态与更新时间；未获授权的来源为什么显示为"未连接"。依赖：M04 知识源管理。

### 5. 查词与来源查看

**待实现。** 将说明：如何查一个词；如何阅读词形、音标、义项与例句；如何区分"来自词典的事实"与"AI 生成的记忆例句"；查不到词时会发生什么。依赖：M07 词典模块。

### 6. 语法学习

**待实现。** 将说明：如何让 EngMentor 检查一段文字；如何阅读诊断、规则引用与正误对比；练习从哪里来、哪些是 AI 生成的。依赖：M08 语法导师。

### 7. 句子与作文评分

**待实现。** 将说明：如何提交句子或作文；如何阅读分项得分、扣分证据与优先修改项；CEFR 估计的置信度该怎么理解；为什么它不是考试成绩。依赖：M09 写作评估。

### 8. 上传 PDF / DOC / DOCX

**待实现。** 将说明：支持的文件类型与限制；导入时的进度与失败提示；重复导入会怎样；如何确认识别结果是否可靠。依赖：M05 文档导入。

### 9. 本地数据、备份、删除与卸载

**待实现。** 将说明：数据保存在本机什么位置；如何备份与恢复；如何删除单份文档并使它的索引与向量一并消失；如何彻底删除全部本地数据；卸载时会保留或删除什么。依赖：M02、M05、M06。

### 10. 常见问题与问题反馈

**待实现。** 将说明：常见故障与排查步骤（模型不可用时会退化为本地确定性结果而不是整页报错）；如何安全地提交问题反馈——**反馈时不要粘贴 API 密钥或完整私人文档内容**。依赖：M12 质量与发布。

## 版权与隐私

这一节的约束已经由负责人确认，属于**产品红线**，不是待定项。

### Oxford 词典

- 在取得**书面离线授权之前**，Oxford 普通 API 只能作为**在线连接器**使用。
- **禁止持久化存储或向量化任何 Oxford 词典内容**，只允许许可范围内的会话级缓存，且必须可清除。
- 未获授权时，产品默认使用许可已确认的开放词典作为可工作的替代方案；**界面不得把替代词典显示为 Oxford**。
- 在线连接器与离线索引在代码层面保持分离，授权状态到期会自动禁用离线能力。

### 你的文档与本地数据

- 你导入的教材、讲义、题库属于你自己的内容，默认只保存在本机。
- 本地的检索索引与向量由你的文档生成，同样保存在本机，用于让回答带上出处。
- 删除文档时，原始文本、检索索引、向量与缓存会一并清理。

### API 密钥

- 密钥存放在操作系统的凭据存储（Keychain / Stronghold 一类）中，**不会**写进界面状态、数据库、日志，也不会提交到代码仓库。
- 日志不记录你的正文内容、完整提示词或授权请求头。

### 发送给云端模型的内容

- 采用的是 **opt-in（用户明确同意后才发送）**：首次使用时会有明确说明并需要你主动选择，选择结果本地保存、可随时撤回。
- 只发送**完成当前任务所需的最小内容**，而不是整份资料。
- 云端处理可以关闭；完全离线模式（本地大模型）是 P2 计划。

### 本地模型文件

首次使用本地检索能力时，需要下载约 **100–200 MB** 的轻量英文嵌入模型。下载前会显示模型名称、体积、许可与哈希，并显示进度。该模型文件不会进入代码仓库。

## 开发者快速开始

### 已确认的技术栈

| 层 | 选择 |
|---|---|
| 桌面壳 | Tauri 2（Rust 主进程） |
| 前端 | React + TypeScript + Vite |
| AI 运行时 | Python 3.12 Sidecar（Pydantic 校验结构化输出） |
| 契约 | JSON Schema 2020-12，生成 TypeScript 与 Python 类型；Rust 侧运行时校验 |
| 元数据 | SQLite + FTS5（计划） |
| 向量检索 | Qdrant Local/Edge（计划） |
| 本地嵌入 | `BAAI/bge-small-en-v1.5`（轻量默认，计划） |
| 主模型 | DeepSeek，API model id `deepseek-flash` |
| 包管理 | pnpm（Node）、uv（Python）、Cargo（Rust），每个安装边界一个权威 lockfile |

### 已固定的开发工具链版本

以下是开发机上**已安装并实测**的版本，不是计划值：

| 工具 | 版本 | 固定方式（均已创建） |
|---|---|---|
| Node.js | `v22.20.0` | `.node-version` 与根 `package.json` 的 `engines`（配合 `.npmrc` 的 `engine-strict=true`） |
| pnpm | `12.4.2` | 根 `package.json` 的 `packageManager`；`pnpm-lock.yaml` 锁定全部依赖 |
| uv | `0.12.17` | `services/ai-core/uv.lock`（18 个包） |
| Python | `3.12.14` | 由 uv 托管；`services/ai-core/.python-version` = `3.12` |
| Rust / cargo | `1.98.1`（host `x86_64-pc-windows-msvc`，含 rustfmt、clippy） | `rust-toolchain.toml`（精确版本号）、`apps/desktop/src-tauri/Cargo.lock`（430 个包） |

Windows 编译环境同样已就绪：MSVC 链接器 `link.exe` 与 Windows SDK `10.0.26100.0` 均已安装并实测存在（`windows.h`、`x64\kernel32.lib`）。完整工具链已通过只读预检门禁（`scripts/preflight.ps1 -RequireReady` 退出码 0）。

### 目前可以运行的命令（已实际验证）

只读环境盘点，不安装任何东西、不修改任何配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1
```

加了 `-RequireReady` 会在关键开发依赖缺失时返回非 0，适合作为安装或构建前的门禁：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/preflight.ps1 -RequireReady
```

预检脚本的自动化测试（Pester，本次在 Windows PowerShell 5.1 + Pester 3.4.0 上验证通过）：

```powershell
powershell -NoProfile -Command "Invoke-Pester scripts/tests/preflight.Tests.ps1"
```

### 工程命令（T010-A 已实测通过）

以下命令都在仓库根目录执行，并且**已经在本机实际跑过**（结果见
[`PROJECT_STATUS.md`](PROJECT_STATUS.md) 的交接记录），不是设计目标：

```powershell
pnpm install --frozen-lockfile                        # Node 依赖（按 lockfile，不允许漂移）
uv sync --locked --project services/ai-core           # Python 依赖（按 lockfile）
uv lock --check --project services/ai-core            # 断言 uv.lock 与 pyproject.toml 一致
cargo build --locked --manifest-path apps/desktop/src-tauri/Cargo.toml

pnpm lint          # eslint + ruff + cargo fmt/clippy
pnpm typecheck     # tsc + mypy(strict)
pnpm test          # vitest + pytest + cargo test
pnpm build         # 前端构建 + Rust 骨架构建
pnpm contracts:generate   # 从 schema 生成 TS/Python 类型与 schema-manifest.json
pnpm contracts:check      # 漂移检查（无漂移 0；生成物与 schema 不同步则非 0）
pnpm test:contracts       # 三方一致性：TS/Python/Rust 对同一批正反例的判定必须逐条相同
```

关于前端产物与 Rust 的顺序：Tauri 通过 `tauri::generate_context!` 在**编译期嵌入前端产物**。
实测（`cargo clean -p engmentor-desktop` 后移走 `apps/desktop/dist`）clippy 与 `cargo build`
**都不会因此失败**，但那样产出的程序里没有前端资源、启动后不会有界面。
`pnpm build` 与 `pnpm test` 已经替你处理了顺序；单独调用 cargo 时请先跑 `pnpm build:web`。

首次创建 lockfile 时使用的是非 fixed 模式（`pnpm install` / `uv sync` / `cargo generate-lockfile`），
随后立刻用上面的 frozen/locked 命令复验——这是**首次建锁的例外**，之后所有安装都必须走 locked 模式。

### 安全自检（T010-B 已在本机实测通过）

```powershell
pnpm check:secrets        # 敏感路径忽略规则 + gitleaks 全量历史扫描
pnpm check:capabilities   # Tauri capability 白名单审计（SPEC-M00 §5.4 第 3 层）
```

`pnpm check:secrets` 要求本机装有与 CI **完全相同版本**的 gitleaks；版本不一致时它会拒绝扫描
（退出码 2），而不是给出一个与 CI 不可比的结论。安装方式：

```powershell
winget install --id Gitleaks.Gitleaks --version 8.30.1 -e
```

安装后需要重开 shell（winget 修改的是用户 PATH）。若 gitleaks 装在别处，可用环境变量
`GITLEAKS_BIN` 指向它。

退出码语义：`0` 通过；`1` 确实发现了问题（疑似密钥、忽略规则不符）；`2` 检查本身没能按约定口径
执行——三种情况互不混淆，`2` 不代表"安全"。

### 还没有的命令

| 目的 | 状态 |
|---|---|
| 启动桌面应用（开发模式） | 待 M01 完成后补充 |
| 打包 Windows 安装包 / 签名 | 待 T050 完成后补充 |
| CI 流程（GitHub Actions） | **工作流已提交，但从未在 GitHub 上运行过**；要验证需在 Actions 页面手动触发（`workflow_dispatch`）或开 PR |

在对应任务落地并实测之前，README 不会写入这些命令。

## 项目结构

```text
LanguageTeacherAgent-English/
├─ README.md                     # 本文件
├─ PROJECT_STATUS.md             # 所有 Agent 的第一读物与交接账本
├─ AGENTS.md / CLAUDE.md         # AI 协作规则入口
├─ package.json                  # 根包：私有，只做编排，packageManager 固定 pnpm
├─ pnpm-workspace.yaml           # workspace 成员 + 依赖安装期脚本/供应链策略
├─ .npmrc                        # peer 严格、不隐式装 peer、engine-strict
├─ .gitattributes                # 统一 LF，二进制类型显式标注
├─ .node-version / .env.example  # Node 版本固定 / 环境变量占位符（无真实值）
├─ .gitleaks.toml                # 密钥扫描规则（本机与 CI 共用；当前不含任何例外）
├─ rust-toolchain.toml           # Rust 精确版本（1.98.1，MSVC host）
├─ eslint.config.mjs             # 含"WebView 不得直接访问外网"的边界规则
├─ .github/workflows/ci.yml      # 最小 CI（web / python / rust / secrets，Action 固定 SHA）
├─ docs/
│  ├─ 英语老师AI-Agent-统一产品与技术开发方案.md   # 唯一当前总方案
│  ├─ specs/                     # 模块规格（当前：SPEC-M00）
│  └─ decisions/                 # 决策与 ADR（当前：T000 决策）
├─ tasks/{plan.md,todo.md}       # 实施计划与任务清单
├─ scripts/
│  ├─ preflight.ps1              # 只读工具链预检入口（可运行）
│  ├─ lib/PreflightChecks.psm1   # 预检的检查逻辑
│  ├─ tests/preflight.Tests.ps1  # 预检测试（Pester，53 项）
│  ├─ contracts-check.mjs        # 契约目录结构检查
│  ├─ check-ignored.mjs          # 敏感路径是否被 .gitignore 覆盖
│  ├─ check-secrets.mjs          # gitleaks 扫描（断言与 CI 同版本同配置）
│  └─ audit-capabilities.mjs     # Tauri capability 白名单审计
├─ apps/desktop/                 # 桌面壳（Tauri 2 + React + Vite，骨架可构建）
│  ├─ src/                       # React UI（只有一张"尚未实现"说明页）
│  ├─ tests/                     # vitest：元信息 + tauri.conf.json 边界断言
│  └─ src-tauri/                 # Rust 主进程、tauri.conf.json、capabilities、icons
├─ packages/contracts/           # 契约包：schema/v1 是唯一来源，生成 TS + Python 类型（已落地）
├─ services/ai-core/             # Python 3.12 AI 运行时（当前只有健康检查）
└─ evals/                        # 计划：评测集（尚未创建）
```

## 状态文件与核心文档

| 文档 | 用途 |
|---|---|
| [`PROJECT_STATUS.md`](PROJECT_STATUS.md) | 当前真实状态、模块表、验证证据、阻塞项、交接记录——**判断进度只看这里** |
| [`docs/英语老师AI-Agent-统一产品与技术开发方案.md`](docs/英语老师AI-Agent-统一产品与技术开发方案.md) | 唯一当前总方案（产品 + 技术架构 + 模块划分 + 门禁） |
| [`docs/specs/SPEC-M00-foundation-contracts.md`](docs/specs/SPEC-M00-foundation-contracts.md) | M00 模块规格：目录结构、边界、契约、命令、CI、验收标准 |
| [`docs/decisions/T000-产品边界与技术决策建议.md`](docs/decisions/T000-产品边界与技术决策建议.md) | 已确认的产品边界与技术决策（Q1–Q8），含 Oxford 与隐私红线 |
| [`tasks/plan.md`](tasks/plan.md) | 实施计划、阶段出口与风险 |
| [`tasks/todo.md`](tasks/todo.md) | 任务清单与验收条件 |
| [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) | AI 协作规则与启动顺序 |

历史文档（**已被替代，仅供追溯**）：`docs/英语老师AI-Agent-桌面客户端产品与开发方案.md`、`docs/英语老师AI-Agent-产品需求与技术方案.md`。

## 贡献与开发纪律

- 一次只处理一个依赖已满足的任务；没有获批准的模块 Spec 不开始编码。
- 先写测试再做最小实现；不得删除或弱化失败测试来让 CI 通过。
- 不擅自更换架构、增加依赖、修改数据 Schema 或扩大 P0；此类变化必须先写 ADR。
- 用户上传的文档、第三方响应与模型输出都视为不可信数据。
- 不把密钥、真实用户内容、未授权词典内容或模型权重提交到仓库。
- 不把模型输出直接交给 shell、SQL、HTML 或文件路径。
- 完成后运行 Spec 指定的测试、静态检查、评测与构建。

### README 维护规则（强制）

**README 是产品文档，不是开发日志，它必须始终反映产品的真实状态。**

1. 任何影响**安装、配置、数据、隐私、知识库、查词、语法、评分、导入或用户界面**的改动，必须在**同一模块的提交**中同步更新 README 对应的用户说明。
2. 功能交付时，把对应小节从"待实现"改写为可照做的步骤，并补齐：**功能状态、操作步骤、限制与边界、实际截图或 GIF（如适用）、故障排查**。
3. **README 与实际产品不一致时，该模块不得标记 `DONE`。**
4. README 中不得出现：虚构的命令、截图、安装包下载地址、未实现的功能描述，或任何真实 API 密钥、未授权词典原文。
5. README 的内部链接必须始终可用；断链等同于文档缺陷。

---

*EngMentor 处于 Pre-alpha 阶段。本文件随每个用户可见模块的交付而更新；进度以 [`PROJECT_STATUS.md`](PROJECT_STATUS.md) 为准。*
