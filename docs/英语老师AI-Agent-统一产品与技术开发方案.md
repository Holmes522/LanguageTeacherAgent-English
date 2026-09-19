# EngMentor 英语老师 AI Agent 桌面客户端：统一产品与技术开发方案

> 产品代号：EngMentor（英师）  
> 文档类型：统一 PRD + 技术架构 + 模块计划 + Agent 协作规范  
> 版本：v2.0-draft  
> 日期：2026-09-19  
> 状态：待产品/技术/版权评审  
> 目标：Windows 优先的本地桌面客户端，架构兼容 macOS  
> 主模型：DeepSeek-V4.1-Flash，API model id 使用 `deepseek-flash`

## 0. 文档地位与阅读方式

本文件综合并替代以下两份历史方案：

- `英语老师AI-Agent-桌面客户端产品与开发方案.md`
- `英语老师AI-Agent-产品需求与技术方案.md`

合并原则：

- 保留长版 PRD 的用户问题、场景、功能细节、分层 Token 路由、Eval 与产品内部 Skill 设计。
- 保留桌面方案的 Tauri/Python Sidecar、本地存储、版权模式、文件安全、接口契约和可安装交付。
- 用户后来明确要求桌面客户端，因此 Web/SaaS 技术栈不进入 MVP；账号、云同步、教师后台和 K8s 后移。
- 对未经验证的商业数据、吞吐、成本和 RICE 分数不当作事实；先建立基线再决定。

Agent 的固定阅读顺序：

1. 根目录 `PROJECT_STATUS.md`：当前事实、已完成模块和交接。
2. 根目录 `AGENTS.md`；Claude Code 同时读取 `CLAUDE.md`。
3. 当前模块 Spec、相关 ADR、测试与源码。
4. 本文件的相关章节。
5. `tasks/todo.md` 与 `tasks/plan.md`。

## 1. 一页纸结论

| 维度 | 统一结论 |
|---|---|
| 定位 | 能选择知识源、查词有出处、解释语法、批改写作、导入个人题库的英语学习桌面 Agent |
| 核心用户 | 第一优先：个人自学者/备考学生；第二优先：需要导入教辅资料的教师 |
| 核心差异 | 可插拔知识库、强制引用、可解释评分、本地优先、低 Token 分层路由 |
| MVP | 桌面框架、知识源选择、查词、语法、句子/作文评分、PDF/DOC/DOCX 导入、RAG 引用、GitHub 工程化 |
| P1 | 自动切题与复核、错题本、SRS、学习档案、OCR、导出和评测面板 |
| 暂不做 | 实时口语、教师/学生多租户、社区、云同步、移动端、全自动出卷 |
| 桌面技术 | Tauri 2 + React/TypeScript/Vite + Python 3.12 Sidecar |
| 本地数据 | SQLite + FTS5 + Qdrant Local/Edge + 本地 Embedding |
| AI | DeepSeek `deepseek-flash`；结构化输出由 Pydantic 校验 |
| 成本原则 | 能查表就不生成；能本地规则处理就不调用 LLM；只给模型最小证据 |
| 最大风险 | Oxford 内容授权、旧 DOC 解析打包、评分可信度、用户资料发送云模型的隐私 |
| 协作原则 | 模块化 Spec、垂直切片、测试与 Eval 门禁、每个模块完成后更新 `PROJECT_STATUS.md` |

## 2. 背景与问题

### 2.1 用户问题

1. 查词、改作文、学语法和做题分散在多个工具，数据无法形成学习闭环。
2. 通用模型会编造释义、例句或语法依据，用户无法核验。
3. 作文批改常只给总分和泛化评语，不能解释失分证据和下一步行动。
4. 用户和教师已有的教材、讲义、词表与题库难以安全接入 AI。
5. 云端大模型若每次接收整份资料，会造成 Token 成本、延迟和隐私风险。

### 2.2 待验证的产品假设

- H1：来源可核验比“回答更长”更能提高用户信任。
- H2：分项评分、证据句和修改任务比单一总分更能推动持续使用。
- H3：教师愿意导入题库，但前提是解析结果可复核、可修改、可追溯。
- H4：个人桌面本地优先足以验证核心价值，首版无需账号与云后台。

Phase 0 建议完成 5–8 场任务式访谈：至少 3 名备考学生、2 名职场学习者、2 名教师。结果应更新需求优先级，不能只作为展示材料。

## 3. 用户与核心场景

| 用户 | 核心任务 | MVP 场景 |
|---|---|---|
| 备考学习者 | 快速知道失分点并补弱项 | 粘贴作文 → 分项评分 → 逐句证据 → 语法讲解 |
| 职场学习者 | 确认英文表达准确、自然、适合语境 | 输入句子/邮件 → 纠错与语域建议 → 查词来源 |
| 教师/重度用户 | 利用自己的讲义和题库 | 导入 PDF/DOC/DOCX → 校验索引 → 基于资料问答 |

核心旅程：

```text
首次启动
  → 配置 DeepSeek 与隐私模式
  → 选择默认知识源
  → 查词 / 语法 / 写作 / 资料问答
  → 查看来源与证据
  → 保存错误（P1）
  → 进入复习队列并查看进步（P1）
```

## 4. 产品目标、指标与非目标

### 4.1 产品目标

| ID | 目标 | MVP 衡量方式 |
|---|---|---|
| G1 | 回答可验证 | 查词来源覆盖率 100%；RAG 引用覆盖率 ≥ 95% |
| G2 | 反馈可行动 | 每份评分报告包含分项、证据、优先修改项和修订示例 |
| G3 | 知识库可插拔 | 至少支持词典、语法库、用户资料/题库三类源 |
| G4 | 成本可控制 | 默认 RAG 证据上下文 ≤ 1,800 tokens；L0 查词 0 LLM Token |
| G5 | 系统可接手 | 每个模块都有 Spec、测试、状态、证据和交接记录 |

留存、付费转化、NPS 等商业指标在有真实用户基线后设定，不在开发前虚构目标。

### 4.2 MVP 非目标

- 不做账号注册、OAuth、多人权限和云同步。
- 不做教师班级后台、家长周报、收费订阅。
- 不做实时语音、视频课、社区和移动端。
- 不承诺替代正式考试评分员或真人教师。
- 不自动抓取、破解、批量保存或分发受版权保护的词典与教材。
- 不在没有证据时自动生成“官方例句”“官方评分”或“官方语法规则”。

## 5. 优先级与范围纪律

### 5.1 定义

- P0：没有它就不能验证核心产品价值或不能安全发布 MVP。
- P1：补齐学习闭环与使用效率的首个增强版本。
- P2：差异化能力。
- P3：云平台、机构化和规模化能力。

P0 冻结后，新增 P0 必须说明被移出的项目。实现顺序同时受依赖约束，不能只按业务价值跳过地基。

### 5.2 功能矩阵

| ID | 功能 | 优先级 | MVP 完成条件 |
|---|---|:---:|---|
| F0 | 桌面运行与设置 | P0 | 可安装启动、安全保存 Key、管理 Sidecar 和数据目录 |
| F1 | 知识源管理与选择 | P0 | 默认/会话选择、多库组合、状态、授权与健康信息 |
| F2 | 查词与来源 | P0 | 词形、词性、音标、义项、例句、搭配和逐项来源 |
| F3 | 语法教学 | P0 | 诊断、归因、规则、正反例、修改和引用 |
| F4 | 句子/作文评分 | P0 | 分项分、证据、置信度、优先修订和非官方声明 |
| F5 | 文档/题库导入 | P0 | PDF/DOC/DOCX 安全导入、索引、进度、错误、删除 |
| F6 | 检索与引用 | P0 | 分层路由、混合检索、预算、引用定位和拒答 |
| F7 | 对话入口 | P0 | 自动/显式路由、流式响应、会话知识库状态 |
| F8 | Eval、观测与发布 | P0 | 质量/Token 门禁、脱敏日志、CI 和安装包 |
| F9 | 题库结构化与复核 | P1 | 自动切题、去重、标签、人工审批后使用 |
| F10 | 错题本与 SRS | P1 | 错误沉淀、复习排程、掌握度更新 |
| F11 | 学习档案 | P1 | 版本比较、进步曲线、薄弱点报告 |
| F12 | OCR 与导出 | P1 | 扫描 PDF 校正；报告导出 Markdown/PDF |
| F13 | 口语/发音 | P2 | 录音、识别、音素或可解释反馈 |
| F14 | 完全离线模式 | P2 | 本地 LLM/Embedding/STT/TTS 可切换 |
| F15 | 账号、同步、教师工作台 | P3 | 独立云架构项目，不污染桌面 MVP |

## 6. 功能规格与验收

### 6.1 F1 知识源管理

知识源类型：

- `DICTIONARY`：结构化精确查询优先。
- `GRAMMAR`：结构化语法点 + 语义检索。
- `CORPUS`：范文、语料和模板。
- `QUESTION_BANK`：题目与解析。
- `RUBRIC`：评分量表，条目少且版本化。
- `USER_DOCUMENT`：用户自有资料。

要求：

- 用户可以选择默认知识源和当前会话知识源。
- 多库结果分别标注知识源，不把不同来源混成一条“官方解释”。
- 展示索引状态、数据版本、许可证、条目数、失败信息和更新时间。
- 索引重建期间优先使用上一个完整版本；无完整版本时清楚提示不可用。
- 未获得授权的 Oxford 源显示为“未连接”，不能伪装成已启用默认源。

验收：切换知识源后，答案证据与来源同步变化；删除源后不可检索其内容。

### 6.2 F2 查词

输出：规范化输入、lemma、词形说明、英/美音标、词性、分义项释义、真实例句、搭配、语域、来源与查询时间。

规则：

- 精确查词走结构化连接器，模板渲染，默认不调用 LLM。
- 释义和例句分别标注来源；AI 生成的记忆例句必须标记“AI 生成”。
- 未收录词返回拼写候选或“未收录”，不得编造。
- 上下文词义、近义词辨析等语义任务才升级到生成层。

验收：20 个词形用例全部正确；未收录词拒答率 100%；命中本地缓存时目标响应 < 200 ms（以基准机器实测为准）。

### 6.3 F3 语法教学

语法点结构：名称、分类、定义、句型结构、正例、反例、常见错误、前置知识、相关考点、来源定位和版本。

回答固定结构：

1. 标出问题片段。
2. 给出诊断与置信度。
3. 引用规则并解释“为什么”。
4. 提供正误对比。
5. 给出最小修改和自然改写。
6. 给出 1–3 道小练习；无题库时明确标记为 AI 生成练习。
7. 展示来源。

验收：能诊断典型错误；来源可定位到语法点/章节；知识库无证据时不假装有引用。

### 6.4 F4 句子与作文评分

采用“确定性预检 + LLM 高阶评价”：

- 本地确定性层：字数、标点、重复、拼写候选和可稳定识别的语法模式。
- LLM 层：任务完成度、组织、连贯、词汇使用、复杂句式与整体可理解性。
- 评分输出强制 JSON，Pydantic 校验；越界、缺项、空输出和截断有限重试。

句子评分（100）：语法 40、词汇 25、自然度 25、拼写标点 10。

作文评分（100）：任务完成 25、组织连贯 20、词汇 20、语法范围与准确性 25、规范性 10。

可选输出 CEFR 估计区间与置信度，但必须显示“AI 学习反馈，不是正式考试成绩”。考试专项量表只有在量表来源和使用权确认后启用。

验收：

- 正确句子不应被强行修改。
- 总分与分项计算一致。
- 每个扣分点包含原文证据和可执行建议。
- 相同作文重复评分的方差满足 Eval 阈值。
- Prompt、模型、量表版本可复现。

### 6.5 F5 文档与题库导入

| 格式 | MVP 路径 | 限制 |
|---|---|---|
| PDF 文本层 | PyMuPDF 按页提取，保留页码/坐标 | 加密或损坏时明确失败 |
| DOCX | python-docx 提取标题、段落、表格 | 禁止宏、外链和嵌入对象 |
| DOC | LibreOffice headless 转换后解析 | 独立可选 legacy importer；先做体积与许可证 Spike |
| 扫描 PDF | P1 OCR | 低置信度内容必须人工校正 |

P0 需要完成“文件能安全进入知识库并可检索”；P1 才要求高精度自动切题、题目去重、标签和原文对照审批。

验收：导入有进度和错误；重复请求幂等；删除会清理文本、FTS、向量、缓存和临时文件。

### 6.6 F7 对话入口

- 支持自动路由和显式命令 `/dict`、`/grammar`、`/score`、`/ask`。
- UI 持续显示当前知识源、任务类型和是否使用 AI 生成。
- 信息不足时澄清；但精确查词等确定性意图不多问。
- 流式输出可取消；模型失败时降级为确定性检索结果，而不是整个页面报错。
- 对话记忆保存结构化学习状态与滚动摘要，不反复发送完整历史。

## 7. 产品内部 Agent Skills

运行时 Skill 是带契约和预算的能力单元，不是只有一段 Prompt。

| Skill | 默认层级 | 依赖 | Token 预算 | 优先级 |
|---|:---:|---|---:|:---:|
| `intent_router` | L0 | 规则/轻量分类 | 0 | P0 |
| `word_lookup` | L0 | DICTIONARY | 0 | P0 |
| `word_suggest` | L0 | DICTIONARY | 0 | P0 |
| `grammar_explain` | L1/L2 | GRAMMAR | 0–1,200 | P0 |
| `grammar_diagnose` | L2 | GRAMMAR | ≤ 1,200 | P0 |
| `sentence_fix` | L2 | GRAMMAR | ≤ 1,500 | P0 |
| `essay_score` | L3 | RUBRIC + 可选 GRAMMAR/CORPUS | ≤ 6,000 | P0 |
| `citation_builder` | L0 | 来源元数据 | 0 | P0 |
| `document_qa` | L2 | USER_DOCUMENT | ≤ 1,800 证据上下文 | P0 |
| `qbank_search` | L0/L1 | QUESTION_BANK | 0–300 | P0 |
| `qbank_parse` | L2 | 文档解析 | 每页硬预算 | P1 |
| `review_scheduler` | 本地算法 | 学习记录 | 0 | P1 |

每个 Skill 必须声明：版本、触发条件、输入/输出 Schema、允许访问的知识源、Token 上限、超时、fallback、Eval 集和引用规则。Skill 之间传结构化对象，不用自然语言串联内部状态。

示例：

```yaml
name: word_lookup
version: 1.0.0
tier: L0
required_kbs: [DICTIONARY]
token_budget: { input: 0, output: 0 }
fallback: NOT_FOUND_WITH_SUGGESTIONS
eval_set: evals/dictionary/dict_core.jsonl
```

## 8. 统一桌面架构

```text
React/TypeScript WebView
  │ 白名单 Tauri commands
  ▼
Tauri/Rust 主进程
  ├─ 窗口、菜单、文件选择器、更新
  ├─ OS Keychain/Stronghold
  ├─ 参数与路径校验
  └─ Python Sidecar 生命周期与私有鉴权
       ▼
Python AI Core（127.0.0.1 随机端口，仅 Rust 代理访问）
  ├─ LLM Gateway / Skill Router
  ├─ Document Ingestion
  ├─ Retrieval & Citations
  ├─ Dictionary / Grammar / Assessment / QBank
  ├─ SQLite + FTS5
  ├─ Qdrant Local/Edge
  └─ Local Embedding
```

生产环境禁止 Sidecar 绑定 `0.0.0.0`。随机鉴权令牌只存在内存中，WebView 不直接持有 DeepSeek/Oxford Key 或 Sidecar 令牌。

### 8.1 为什么选择 Tauri

- 桌面交付明确，不需要 SSR/SEO，Vite SPA 更简单。
- 系统 WebView 可减少 UI 壳体积；Python Sidecar 已承担 AI 运行时。
- Tauri capability 便于限制文件、Shell 和网络权限。
- 官方支持嵌入 PyInstaller 等外部二进制。

风险：团队 Rust 经验、Sidecar 多平台命名/签名、WebView 差异。Phase 0 做 2 天 Spike；若干净 Windows VM 无法稳定安装和管理 Sidecar，再通过 ADR 评估 Electron。AI Core 和 JSON 契约不得绑定 Tauri，以保留替换空间。

## 9. 模块划分与依赖

| 模块 ID | 职责 | 依赖 | 优先级 |
|---|---|---|:---:|
| `M00-foundation-contracts` | Monorepo、JSON Schema、代码规范、CI、ADR | — | P0 |
| `M01-desktop-shell` | Tauri、Sidecar、窗口、安装、更新 | M00 | P0 |
| `M02-local-storage-settings` | SQLite、迁移、设置、Key、备份 | M00/M01 | P0 |
| `M03-llm-gateway` | DeepSeek、流式、重试、JSON、预算 | M00/M01 | P0 |
| `M04-knowledge-registry` | 知识源、授权、选择、状态与版本 | M02 | P0 |
| `M05-document-ingestion` | 文件验证、解析、分块、任务、删除 | M02/M04 | P0 |
| `M06-retrieval-citations` | 分层路由、FTS+Dense、重排、引用 | M04/M05 | P0 |
| `M07-dictionary` | 词形、结构化查词、来源、缓存 | M03/M04 | P0 |
| `M08-grammar-tutor` | 语法结构、诊断、讲解、练习 | M03/M06 | P0 |
| `M09-writing-assessment` | 预检、量表、评分、批注、版本比较 | M03/M06/M08 | P0 |
| `M10-question-bank` | P0 导入检索；P1 切题、去重、复核 | M05/M06 | P0/P1 |
| `M11-learning-loop` | 错题、SRS、档案、薄弱点 | M08/M09/M10 | P1 |
| `M12-quality-release` | Eval、观测、安全、性能、CI、签名发布 | 横向 | P0 |

依赖主链：

```text
M00 → M01 → M02 → M04 → M05 → M06
          └→ M03 ─────────┬→ M07
                           ├→ M08 → M09
                           └→ M10 → M11

M12 从 M00 开始贯穿所有模块
```

开发不是先做完所有后端再做 UI。每个业务模块采用垂直切片：契约 + 本地服务 + 最小 UI + 测试 + Eval + 文档一起交付。

## 10. 技术选型

| 层 | MVP 选择 | 说明/后续 |
|---|---|---|
| 桌面 | Tauri 2 | Spike 失败才评估 Electron |
| 前端 | React + TypeScript + Vite | Tailwind + shadcn/ui；Zustand + TanStack Query |
| Rust | Tauri commands + Sidecar manager | 权限、密钥代理、进程与更新 |
| AI Core | Python 3.12 + Pydantic | PyInstaller 打包 |
| 工作流 | 显式 typed state machine | 先保持简单；复杂分支达到阈值再评估 LangGraph |
| 元数据 | SQLite + SQLModel/Alembic | 单用户本地，支持迁移/备份 |
| 关键词检索 | SQLite FTS5 | 术语、题号、精确词命中 |
| 向量 | Qdrant Local/Edge | 无独立 Docker/服务 |
| Embedding | `BAAI/bge-small-en-v1.5` | 轻量英文默认包；`bge-m3` 作为 P1 高质量/双语包 |
| Rerank | 先使用轻量打分/MMR | 本地大 Reranker 通过性能测试后再启用 |
| PDF | PyMuPDF | 保留页码与坐标 |
| DOCX | python-docx | 段落、标题、表格 |
| DOC | LibreOffice headless legacy importer | 可选组件，隔离运行 |
| 确定性检查 | 统一 Checker 接口 | 比较自建规则与本地 LanguageTool 的体积/质量后决定实现 |
| 测试 | Vitest + pytest + Tauri WebDriver/Playwright | 契约/Eval 单独门禁 |
| 包管理 | pnpm + uv + Cargo | 每个安装边界只有一个权威 lockfile |

MVP 不使用 PostgreSQL、Redis、MinIO、Celery、K8s、OAuth 或云端 Langfuse。这些是未来多用户云架构候选，不应增加桌面首版的运维和资源成本。

## 11. DeepSeek Gateway

```dotenv
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
```

要求：

- model id 和能力由配置表管理，不在业务代码散落字符串。
- 所有网络请求有连接/读取超时、取消、有限重试和稳定错误码。
- 评分、抽取使用 `response_format={"type":"json_object"}`，提示中包含 JSON 示例，返回经 Pydantic 校验。
- 网络/限流/空输出/明确截断可重试；业务校验失败不得无限自修复。
- 每个 Skill 有输入、输出、总 Token 和最大工具轮数。
- 保存模型 id、Prompt 版本、量表版本和去标识化用量；不记录用户正文。
- DeepSeek 故障时，查词、本地检索和基本检查仍可使用。

## 12. 分层路由与低 Token RAG

### 12.1 L0–L3

| 层 | 场景 | 实现 | 默认预算 |
|---|---|---|---:|
| L0 确定性 | 查词、词形、字数、KB 列表、题目精确查找 | 数据库/规则/模板 | 0 LLM Token |
| L1 检索拼装 | 已有语法点、固定搭配、可直接引用的资料 | 检索 + 模板 | 0–300 |
| L2 小上下文 | 语境词义、辨析、语法诊断、资料问答 | Top-N 证据 + DeepSeek | ≤ 1,500–1,800 |
| L3 深度生成 | 作文评分、长文修改、多轮辅导 | 量表 + 最小证据 + DeepSeek | 任务上限 ≤ 6,000 |

优先下沉：能在 L0/L1 解决就不升级。不要为了追求某个预设占比而错误分类；以上线实测质量与成本决定目标。

### 12.2 检索流水线

```text
意图/显式 Skill
  → 知识源、授权、语言和用户空间过滤
  → 必要时查询改写
  → FTS5 Top 8 + Dense Top 8
  → 合并、去重、MMR/轻量重排
  → 引用完整性校验
  → Top 4，证据总预算默认 1,200–1,800 tokens
  → DeepSeek
  → 输出 Schema/引用校验
```

### 12.3 Token 控制

- 语义块约 250–450 tokens，重叠 40–60，保留标题、页码和层级。
- 入库时清理页眉页脚、导航和重复段落。
- 先用元数据过滤，再算相似度。
- 引用用短 ID 进入 Prompt，完整片段由应用展示。
- 对话使用滚动摘要和结构化学习状态。
- 缓存 query Embedding、检索结果和许可允许的响应。
- Oxford 普通 API 内容不进入持久缓存/向量索引。
- CI 运行 Token 回归；平均用量显著上涨必须解释。

## 13. Oxford 与其他知识源

### 13.1 Oxford 在线模式

- 通过官方 API 精确查询。
- 只做许可允许的用户会话缓存。
- 不批量下载、不长期保存完整词条、不生成持久化向量。
- 显示必要的来源、品牌和版权信息。

### 13.2 Oxford 离线企业授权模式

- 合同明确允许本地存储、索引和展示后才能启用。
- 记录 `licenseId`、版本、到期时间、允许字段和删除要求。
- 授权到期自动禁用，并能清除原始包、索引与缓存。

### 13.3 无 Oxford 授权

- 默认使用许可证已确认的开放词典；来源 UI 不得写成 Oxford。
- 开发与 Eval 使用可合法再分发的固定测试夹具。
- 语法库由团队自建或单独授权；词典不能替代系统语法课程。

数据模型必须与词典供应商无关，保留 `sourceName`、`sourceVersion`、`sourceLocator`、`licenseLabel`。

## 14. 文件安全与题库

### 14.1 导入安全

- 检查真实 MIME、magic bytes、大小、页数和容器结构，不信任扩展名。
- 默认单文件 50 MB、PDF 500 页；可配置但保留硬上限。
- DOCX 防 ZIP bomb：限制文件数、展开大小和压缩比。
- 解析/转换在临时低权限、禁网工作目录，设置 CPU、内存和超时。
- 不执行宏、脚本、嵌入对象、外部关系或文档内命令。
- 文档中的“忽略系统指令”只是资料，不能改变 Agent 权限和 Prompt。
- 文件哈希用于幂等与去重，临时文件无论成功失败都清理。

### 14.2 题目状态

```text
PENDING → APPROVED → ACTIVE
   └────→ REJECTED
```

P1 自动抽取的数据包括：题型、题干、选项、答案、解析、标签、难度、来源坐标和置信度。只有 `APPROVED` 才可正式判题和进入统计。

## 15. 数据与本地契约

### 15.1 MVP 数据

- `app_settings`
- `knowledge_sources`
- `documents`
- `document_chunks`
- `ingestion_jobs`
- `conversations` / `messages`
- `assessments` / `assessment_dimensions`
- `citations`
- `prompt_versions`
- `usage_events`
- `questions`（P0 只需可导入检索，P1 扩展复核状态）

P1：`practice_sessions`、`practice_answers`、`error_records`、`review_items`、`learning_profiles`。

### 15.2 契约

```ts
type LocalResponse<T> =
  | {
      ok: true;
      requestId: string;
      data: T;
      citations: Citation[];
      usage?: { inputTokens: number; outputTokens: number; cached: boolean };
    }
  | {
      ok: false;
      requestId: string;
      error: { code: string; message: string; retryable: boolean; details?: unknown };
    };
```

所有输入/输出由一份 JSON Schema 生成 TypeScript 和 Python 类型。长任务返回 `jobId` 并发布进度事件；状态变更支持幂等键。

P0 命令：

- `settings.validateModel`
- `knowledge.list` / `knowledge.setSessionSelection`
- `documents.import` / `jobs.get` / `documents.delete`
- `dictionary.lookup`
- `grammar.explain` / `grammar.diagnose`
- `assessment.scoreSentence` / `assessment.scoreEssay`
- `questions.search`
- `chat.send`

## 16. 安全、隐私与版权

- 用户文件、外部 API、配置文件中的内容和 LLM 输出都是不可信输入。
- Tauri capabilities 仅开放必要命令、目录和 Sidecar 参数。
- API Key 存 OS Keychain/Stronghold；不进 WebView、SQLite、日志或 Git。
- LLM 输出不得直接进入 shell、SQL、HTML 或文件路径。
- 日志不记录正文、完整 Prompt、Authorization header 和身份信息。
- 用户提交云模型前显示隐私说明；仅发送当前请求所需内容。
- 提供本地数据查看、导出、备份和彻底删除。
- 如果面向未成年人，另行设计监护人同意、数据最小化、内容安全和地区合规。
- 用户上传内容需要权利声明与删除通道，但不能把免责条款当作版权许可。
- 正式发布前确认 DeepSeek 数据使用、保留和训练条款。

## 17. Eval、测试与完成指标

### 17.1 测试层级

- 单元：解析、分块、过滤、评分计算、迁移、错误映射。
- 契约：TS/Python 对相同 Schema 的正反例。
- 集成：DeepSeek mock、词典脱敏 fixture、本地索引。
- RAG Eval：Recall@K、MRR、引用覆盖与定位正确率。
- 教学 Eval：查词、语法诊断、正确句负例、作文人工评分集。
- 安全：伪扩展、损坏文件、ZIP bomb、宏、Prompt Injection、路径穿越。
- 桌面 E2E：安装、首次启动、导入、检索、评分、删除、升级。

### 17.2 MVP 门禁

| 指标 | 阈值 |
|---|---:|
| 查词事实来源覆盖率 | 100% |
| 未收录词正确拒答率 | 100% |
| RAG 引用覆盖率 | ≥ 95% |
| 引用可定位正确率 | ≥ 95%（人工抽检） |
| 结构化评分可解析率 | ≥ 99.5% |
| 同作文重复评分标准差 | ≤ 3/100 |
| 正确句子幻觉纠错率 | ≤ 2% |
| 默认 RAG 证据上下文 | ≤ 1,800 tokens |
| 文本型 50 页 PDF 基准集导入成功率 | ≥ 99% |
| 删除后原内容可检索率 | 0% |

阈值必须附数据集版本和基准机器，不允许只写一个百分比而没有可复现测试。

## 18. 开发阶段

> **执行顺序说明（2026-09-19 用户裁定）**：`M00`（Monorepo、契约、CI）**先于** Phase 0 的风险 Spike 执行——Spike 的可复现证据需要仓库骨架、CI 与契约信封作为载体。实际顺序为：工具链预检与安装 → `M00（T010–T012）` → Phase 0 风险 Spike（T001–T005）→ `Checkpoint A` → Phase 2 及之后的业务模块。`tasks/todo.md` 已按此把原 Phase 0 与 Phase 1 合并为统一的 Phase 0。

### Phase 0：产品与技术风险验证

- 用户访谈和目标用户确认。
- Oxford 授权路径。
- Tauri + PyInstaller Sidecar 安装/生命周期。
- DeepSeek streaming/JSON Output/错误处理。
- PDF/DOCX/DOC 样本。
- 本地 Embedding + Qdrant 持久化。
- 评分量表与最小人工标注集。

出口：ADR-001 至 ADR-006 获批准，Q1–Q6 有结论或明确 owner/deadline。

### Phase 1：工程地基

- M00–M04：Monorepo、契约、桌面壳、存储、设置、密钥、LLM Gateway、知识源。
- GitHub CI、脱敏日志、基础 Eval。

出口：干净 Windows VM 安装启动；密钥不落盘到非安全存储；契约门禁通过。

### Phase 2：知识与检索闭环

- M05/M06：三种格式导入、后台任务、FTS+Dense、引用预览、删除重建。

出口：从上传到带页码答案全流程通过；Token 与安全门禁通过。

### Phase 3：核心教学 MVP

- M07–M10 P0：查词、语法、评分、题库资料检索和统一对话入口。

出口：第 17.2 节门禁通过；Windows RC 安装包可用。

### Phase 4：学习闭环

- 自动切题/复核、错题本、SRS、学习档案、OCR 和导出。

### Phase 5：差异化与规模化

- 口语、离线 LLM；另立项目评估账号、云同步、教师工作台和多租户。

## 19. GitHub 与持续同步

小团队采用 `main` + 短生命周期功能分支：

- `main`：始终可发布，禁止直接 push。
- `feat/<module-id>-<name>`
- `fix/<module-id>-<name>`
- `docs/<name>`

每个垂直切片一个 PR，关联任务/Issue，包含验收、截图、测试、Eval、风险和回滚。使用 Conventional Commits。

CI：

- React/TS：format、lint、typecheck、Vitest、build。
- Python：Ruff、类型检查、pytest、依赖锁。
- Rust：fmt、clippy、test。
- 契约：生成物漂移检测。
- Eval：快速集 PR 运行；完整集阶段检查点运行。
- 安全：secret scan、依赖审计、许可证、SBOM。
- 桌面：Windows 安装包；P1 后加 macOS。

GitHub 同步节奏：领取任务 → 更新 `PROJECT_STATUS.md` → 建分支 → 测试驱动实现 → push → Draft PR → CI/Eval → Review → 更新交接 → merge。

## 20. 开发 Agent Skills

| 场景 | Skill |
|---|---|
| 新模块 Spec | `spec-driven-development` |
| 任务拆分 | `planning-and-task-breakdown` |
| 多文件垂直切片 | `incremental-implementation` |
| 行为变更 | `test-driven-development` |
| 契约与边界 | `api-and-interface-design` |
| Tauri/DeepSeek/Qdrant 官方接口 | `source-driven-development` |
| 桌面 UI | `frontend-ui-engineering` |
| 文件/RAG/密钥 | `security-and-hardening` |
| Token/检索性能 | `performance-optimization` |
| 日志/指标/Eval | `observability-and-instrumentation` |
| Git/PR/版本 | `git-workflow-and-versioning` |
| CI | `ci-cd-and-automation` |
| ADR/交接文档 | `documentation-and-adrs` + `context-engineering` |
| 合并前 | `code-review-and-quality` |
| 故障 | `debugging-and-error-recovery` |
| 发布 | `shipping-and-launch` |

原则：每个任务只加载必要 Skill。不要把外部不存在或未安装的 Skill 名称写成硬依赖；工具能力缺失时使用项目内 Spec、测试和官方文档完成同一流程。

## 21. Agent 接手与模块完成协议

### 21.1 接手时

Agent 必须先读 `PROJECT_STATUS.md`，再读规则、相关 Spec/ADR/测试/源码。不得从历史 PRD 猜当前技术栈。

### 21.2 开发中

- 在 `PROJECT_STATUS.md` 登记当前任务、分支、计划和状态。
- 一次只领取一个依赖已满足的任务。
- 决策变化先写 ADR；需求变化先改 Spec。
- 发现冲突立即记录，不静默选择。

### 21.3 完成后

同一 PR/commit 必须更新：

1. `PROJECT_STATUS.md` 模块表。
2. `PROJECT_STATUS.md` 交接记录。
3. `tasks/todo.md`。
4. Spec 的实际行为和验收结果。
5. 相关 ADR、API 或数据迁移文档。

交接记录至少包含：完成/未完成、关键文件、接口变化、迁移/回滚、验证命令、Eval/性能/Token、已知问题、环境要求和下一 Agent 的第一步。

## 22. 推荐目录

```text
LanguageTeacherAgent-English/
├─ PROJECT_STATUS.md             # 所有 Agent 第一读物与交接账本
├─ AGENTS.md                     # 通用 Agent 规则
├─ CLAUDE.md                     # Claude Code 入口
├─ apps/desktop/
│  ├─ src/                       # React UI
│  └─ src-tauri/
│     ├─ Cargo.lock              # Rust 权威 lockfile（提交）
│     └─ rust-toolchain.toml     # 提交精确 Rust 版本号
├─ services/ai-core/
│  ├─ src/english_teacher/
│  ├─ tests/
│  └─ uv.lock                    # Python 权威 lockfile（与 pyproject.toml 同目录）
├─ packages/contracts/           # JSON Schema + 生成类型（TS 与 Python 包）
├─ evals/
├─ docs/
│  ├─ 英语老师AI-Agent-统一产品与技术开发方案.md
│  ├─ specs/
│  └─ decisions/
├─ tasks/plan.md
├─ tasks/todo.md
├─ scripts/
├─ .github/workflows/
├─ .env.example
├─ .gitattributes
├─ .npmrc
├─ .node-version
└─ pnpm-lock.yaml
```

> **锁文件位置说明（D-4，2026-09-19 确认）**：`uv.lock` 必须与定义项目的 `pyproject.toml` 同目录，因此位于 `services/ai-core/uv.lock`，不在仓库根。根目录只保留 Node 边界的 `pnpm-lock.yaml`；Rust 边界使用 `apps/desktop/src-tauri/Cargo.lock`。每个安装边界只有一个权威 lockfile。细节见 [`specs/SPEC-M00-foundation-contracts.md`](specs/SPEC-M00-foundation-contracts.md)。

## 23. ADR 清单

编码前至少完成：

1. ADR-001：Tauri 与 Electron。
2. ADR-002：Python Sidecar 边界、通信、鉴权、打包。
3. ADR-003：SQLite FTS5 + Qdrant Local/Edge。
4. ADR-004：Oxford 在线、离线授权与 fallback。
5. ADR-005：旧 DOC importer。
6. ADR-006：评分量表与免责声明。
7. ADR-007：确定性 Checker（自建规则/LanguageTool）。

## 24. 主要风险

| 风险 | 缓解 |
|---|---|
| Oxford 不允许离线索引 | 在线连接器与本地索引分离；开放许可 fallback |
| Sidecar 打包不稳定 | Phase 0 先验证；保持协议与桌面壳解耦 |
| DOC 导入导致包过大 | 独立 legacy importer；评估按需安装 |
| 评分漂移 | 版本化量表/Prompt、低温度、人工基准、置信度 |
| 文档 Prompt Injection | 文档仅作为数据；权限在代码中；工具参数白名单 |
| 本地模型资源压力 | 轻量默认模型、模型包可选、硬件检测 |
| 引用命中但定位错误 | 保存坐标、引用校验、人工 Eval |
| 云模型隐私 | 明示、最小上下文、脱敏、离线路线 |
| 状态文档过期 | 模块完成定义要求与代码同 PR 更新；CI 后续检查时间戳/模块状态 |

## 25. MVP 完成定义

- Windows 干净机器可安装、启动、升级、卸载。
- DeepSeek `deepseek-flash` 可安全配置，支持流式与结构化输出。
- 用户能选择知识源并看到真实授权/索引状态。
- PDF/DOC/DOCX 能按约定导入、检索、删除。
- 查词事实来源覆盖率 100%，无词不编造。
- 语法讲解带来源、诊断、正反例和练习。
- 句子/作文评分带分项、证据、置信度和修订建议。
- 普通 RAG 默认证据上下文 ≤ 1,800 tokens。
- 删除后文本、向量、缓存与引用不可访问。
- 单元、契约、集成、Eval、安全和桌面 E2E 全部通过。
- 仓库不含密钥、真实用户资料、未授权词典或未追踪模型权重。
- `PROJECT_STATUS.md` 与真实模块状态一致，下一 Agent 能按记录继续工作。

## 26. 待确认问题

Claude Code 已完成 T000 接手分析并给出以下建议。它们均为 `PROPOSED`，在用户确认前不视为产品决定；完整分析见 [`decisions/T000-产品边界与技术决策建议.md`](decisions/T000-产品边界与技术决策建议.md)。

| ID | 待确认问题 | 推荐默认值 | 阻塞 |
|---|---|---|:---:|
| Q1 | Oxford 授权路径和可缓存/索引范围 | 开放许可 fallback 先行；Oxford 在线连接器；离线索引等书面授权 | 部分 |
| Q2 | 首发平台 | 仅 Windows；macOS P1 | 弱 |
| Q3 | DOC 开箱支持 | 可选 legacy importer；无 LibreOffice 时提示转 DOCX | 弱 |
| Q4 | 首发评分量表 | 通用百分制 + 低置信度 CEFR 估计；不做考试专项 | 强 |
| Q5 | 作文发送 DeepSeek/离线要求 | 用户明示同意后最小内容上云；可关闭；完全离线 P2 | 强 |
| Q6 | 第一目标用户 | 备考学生/自学者第一，教师第二 | 弱 |
| Q7 | 本地 Embedding 下载 | 接受约 100–200 MB 模型包，展示许可/哈希/进度 | 否 |
| Q8 | P1 顺序 | 先错题/SRS，后题库复核工作台 | 否 |

## 27. 官方资料

- [DeepSeek API Quick Start](https://api-docs.deepseek.com/)
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)
- [Tauri 2 Frontend Configuration](https://v2.tauri.app/start/frontend/)
- [Tauri External Binaries / Sidecar](https://v2.tauri.app/develop/sidecar/)
- [Qdrant Local Mode](https://qdrant.tech/documentation/frameworks/langchain/)
- [BAAI bge-small-en-v1.5 Model Card](https://huggingface.co/BAAI/bge-small-en-v1.5)
- [Oxford Dictionaries API Terms](https://developer.oxforddictionaries.com/api-terms-and-conditions)
- [Oxford Dictionaries API FAQ](https://developer.oxforddictionaries.com/faq)
- [Council of Europe CEFR Descriptors](https://www.coe.int/en/web/common-european-framework-reference-languages/cefr-descriptors)

## 28. 立即下一步

1. 用户审阅 T000 决策建议并逐项确认/修改 Q1–Q8；Q1 指定负责人和期限。
2. 安全核对并连接 `https://github.com/Holmes522/LanguageTeacherAgent-English`；远程非空时不得强推或合并无关历史。
3. 完成 T000–T005 风险 Spike。
4. 批准 ADR-001 至 ADR-007。
5. 为 M00 创建 `docs/specs/SPEC-M00-foundation-contracts.md`。
6. 按 `tasks/todo.md` 开始第一个垂直切片，并从第一天维护 `PROJECT_STATUS.md`。
