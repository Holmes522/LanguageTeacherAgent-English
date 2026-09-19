# 英语老师 AI Agent 桌面客户端：产品、架构与开发方案

> **历史文档：已由 [`英语老师AI-Agent-统一产品与技术开发方案.md`](英语老师AI-Agent-统一产品与技术开发方案.md) 替代。请勿作为当前实现规范；仅用于追溯。**

> 文档状态：Draft v0.1（待确认后再进入实现）  
> 更新日期：2026-09-19  
> 目标平台：Windows 优先，架构兼容 macOS  
> 开发工具：Claude Code 或 Zcode  
> 主生成模型：DeepSeek-V4.1-Flash（API 调用名使用 `deepseek-flash`）

## 1. 结论摘要

建议把产品做成“本地优先、云模型增强”的桌面客户端：

- 桌面壳使用 **Tauri 2 + React + TypeScript + Vite**。
- AI/RAG 核心使用 **Python 3.12 sidecar**，由 Tauri 启动并管理。
- 业务元数据使用 **SQLite**；向量检索首版使用 **Qdrant Local/Edge**；关键词检索使用 SQLite FTS5。
- Embedding 默认本地运行 `BAAI/bge-small-en-v1.5`，上传资料不必发送给云端做向量化。
- DeepSeek 使用 OpenAI 兼容接口，运行时配置 `model=deepseek-flash`；评分等关键输出使用 JSON Output，并经过 Pydantic 二次校验。
- “查单词”优先走结构化词典 API，不走通用 RAG；“语法讲解”和“题库问答”走带引用的 RAG。
- 牛津词典只有在取得对应 API/离线内容授权后才能设为真正默认源。普通 API 条款通常不允许把内容长期缓存在本地或制作为向量库。
- 第一版先完成知识库、查词、语法讲解、写作评分、PDF/DOC/DOCX 导入与引用闭环；口语、OCR、学习计划放到后续版本。

## 2. 假设、边界与待确认事项

### 2.1 当前假设

1. 产品是中文界面的个人英语学习桌面客户端，不是首版即面向学校的大型多租户平台。
2. Windows 11 x64 为第一发布目标；macOS 在 P1 后适配。
3. 用户自行配置 DeepSeek API Key，密钥存入系统安全存储，不写入数据库、日志或 Git。
4. 上传的作文、题库与学习记录默认只保存在本机；只有完成一次请求所需的最小内容会发送给 DeepSeek。
5. 用户有权使用其上传资料；应用不替用户自动抓取受版权保护的教材或词典。
6. “评分”是学习反馈与水平估计，不宣称等同于 IELTS、TOEFL 或学校正式考试成绩。

### 2.2 必须由产品负责人确认

- [ ] 是否已经取得 Oxford Dictionaries API 或离线数据授权；授权是否允许缓存、索引和商业使用。
- [ ] 首发只支持 Windows，还是同时要求 Windows + macOS。
- [ ] 第一版是否必须在没有安装 Microsoft Word/LibreOffice 的机器上原生导入旧 `.doc`。
- [ ] 产品是纯本地单用户，还是首版就需要账号、跨设备同步和教师/学生角色。
- [ ] 评分体系优先使用自定义百分制、CEFR，还是 IELTS 风格量表。
- [ ] 是否允许将用户原文发送给 DeepSeek；是否需要“完全离线模式”。

## 3. 产品目标与非目标

### 3.1 目标用户

- 需要查词、语法解释和写作反馈的英语学习者。
- 需要导入自己的练习题、教材或讲义并进行针对性练习的用户。
- 希望回答能够注明来源，而不是只得到模型自由生成结论的用户。

### 3.2 产品目标

- 用户能选择一个或多个知识源，并明确看到当前答案实际使用了哪些来源。
- 用户能获得可解释、可复查的句子与作文评分，而不只有一个总分。
- 用户能导入 PDF、DOC、DOCX，并跟踪解析、索引和失败原因。
- 单词、语法和题库答案包含可定位的引用信息。
- 本地知识库检索尽量少占用 LLM Token，且不把整本资料发送到云端。

### 3.3 第一版非目标

- 不做学校教务、班级管理、收费订阅和多人协作。
- 不承诺替代正式语言考试评分员。
- 不自动抓取、破解或批量保存受版权保护的在线词典内容。
- 不在 P0 实现实时语音对话、视频课、直播或移动端。

## 4. 功能优先级

优先级定义：P0 为 MVP 发布阻塞项；P1 为首个增强版本；P2 为差异化能力；P3 为规模化能力。

| 优先级 | 功能 | 交付标准 |
|---|---|---|
| P0 | 桌面客户端框架与设置 | 可安装、可启动、可安全保存 DeepSeek Key、可选择模型与知识库 |
| P0 | 知识源注册与选择 | 支持默认源、会话源、多选、启停、授权状态和索引状态 |
| P0 | 查单词并注明来源 | 返回词形、词性、音标、释义、例句、用法标签、来源链接/版本和查询时间 |
| P0 | 句子评分与纠错 | 分项评分、错误定位、修改理由、改写示例；输出结构稳定 |
| P0 | 作文评分 | 总分、分项分、CEFR 估计、证据句、改进建议、修订稿；声明非官方成绩 |
| P0 | 语法教学 | 识别问题、解释规则、提供正确/错误对比例句、练习题，并引用语法知识源 |
| P0 | PDF/DOC/DOCX 导入 | 文件校验、文本提取、分块、索引、进度、错误报告、删除重建 |
| P0 | RAG 与引用 | 混合检索、权限过滤、上下文预算、答案引用、无证据时拒绝编造 |
| P0 | GitHub 工程化 | 分支、PR、CI、测试、构建产物、敏感信息扫描 |
| P1 | 题库结构化与练习 | 自动提取题干/选项/答案/解析，人工复核后生成练习 |
| P1 | 错题本与学习记录 | 自动收集错误、知识点标签、复习状态与趋势 |
| P1 | 间隔复习 | 基于遗忘曲线/SM-2 类调度单词、语法和错题 |
| P1 | OCR | 支持扫描版 PDF，展示 OCR 置信度并允许校正 |
| P1 | 导出 | 导出作文报告、错题本和学习记录为 Markdown/PDF |
| P1 | 检索评测面板 | 显示命中文档、分数、引用片段、Token 使用和延迟 |
| P2 | 口语训练 | 录音、语音识别、发音反馈、情景对话和回放 |
| P2 | 自适应学习计划 | 根据目标、CEFR、薄弱点和可用时间生成计划 |
| P2 | 多模型提供商 | 在相同 LLM Gateway 下切换 DeepSeek、兼容 OpenAI 的本地模型等 |
| P2 | 完全离线模式 | 本地 LLM + 本地 Embedding + 本地 TTS/STT，不发送内容到云端 |
| P3 | 账号与云同步 | 跨设备同步、备份、冲突处理、数据导出与删除 |
| P3 | 教师/学生模式 | 班级、作业、批阅、教学报表、权限与审计 |

## 5. 能力模块划分

模块 ID 一旦确认应保持稳定，后续 Spec、Issue、分支和 PR 都使用相同 ID。

| 模块 ID | 职责 | 依赖 |
|---|---|---|
| `desktop-shell` | 窗口、菜单、更新、Sidecar 生命周期、系统安全存储 | — |
| `local-contracts` | TypeScript/Python 共用的命令、事件、错误与引用协议 | — |
| `local-storage` | SQLite、迁移、学习记录、任务状态、知识源元数据 | `local-contracts` |
| `llm-gateway` | DeepSeek 调用、流式输出、重试、预算、结构化输出 | `local-contracts`, `desktop-shell` |
| `knowledge-registry` | 知识源注册、授权模式、默认源、会话选择、隔离 | `local-storage` |
| `document-ingestion` | PDF/DOC/DOCX 校验、解析、分块、索引、删除 | `knowledge-registry`, `local-storage` |
| `retrieval-engine` | Dense + FTS5 混合检索、去重、重排、引用 | `document-ingestion`, `knowledge-registry` |
| `dictionary-service` | 单词规范化、词典 API、来源与缓存策略 | `knowledge-registry`, `llm-gateway` |
| `grammar-tutor` | 语法诊断、规则检索、讲解、例句和练习 | `retrieval-engine`, `llm-gateway` |
| `writing-assessment` | 句子/作文量表、评分、校验、修订建议 | `retrieval-engine`, `llm-gateway` |
| `question-bank` | 题目抽取、复核、练习、判分与解析 | `document-ingestion`, `retrieval-engine` |
| `learning-loop` | 错题本、学习档案、复习调度、进度 | `question-bank`, `writing-assessment`, `grammar-tutor` |
| `quality-ops` | 日志、评测集、性能、崩溃报告、发布检查 | 所有模块 |

建议构建顺序：

```text
local-contracts
  ├─ desktop-shell ─ llm-gateway
  └─ local-storage ─ knowledge-registry ─ document-ingestion ─ retrieval-engine
                                                        ├─ dictionary-service
                                                        ├─ grammar-tutor
                                                        ├─ writing-assessment
                                                        └─ question-bank ─ learning-loop

quality-ops 从第一阶段开始横向接入
```

## 6. 核心用户流程

### 6.1 首次启动

1. 用户选择数据目录和隐私模式。
2. 用户填写 DeepSeek API Key；应用只显示验证结果，不回显完整密钥。
3. 应用检测牛津授权配置：
   - 有合法凭据：启用“Oxford 在线源”。
   - 有离线企业授权包：允许导入并建立本地索引。
   - 无授权：显示不可用原因，并选择开放许可来源作为默认源。
4. 下载或导入本地 Embedding 模型，显示大小、哈希和许可证。
5. 完成一组最小健康检查后进入首页。

### 6.2 查单词

1. 规范化输入：大小写、词形、拼写候选。
2. 优先调用当前启用的结构化词典连接器，而不是让 LLM 猜定义。
3. 展示多个义项、词性、发音、例句和用法标签。
4. 每个义项展示来源、版本/语言、原始链接、查询时间和授权提示。
5. LLM 只负责“按当前水平解释”或“生成辅助记忆”，并明确标记为 AI 讲解。

### 6.3 语法讲解

1. 检测用户句子的疑似错误和目标语法点。
2. 从被选择的语法库中检索规则与例句。
3. 回答结构固定为：问题位置 → 规则 → 为什么 → 正误对比 → 修改建议 → 小练习 → 引用。
4. 找不到足够证据时，明确说“当前知识库未覆盖”，不伪造来源。

### 6.4 句子/作文评分

1. 用户选择任务类型、目标水平、评分量表和题目要求。
2. 应用先做确定性检查：字数、拼写、标点、重复、基本语法候选。
3. DeepSeek 按固定量表输出 JSON；应用验证分数范围、分项和总分关系。
4. 结果展示证据句、错误类型、优先修改项和修订示例。
5. 用户可保存版本，后续比较“初稿 → 修改稿”的进步。

### 6.5 上传题库/资料

1. 校验真实 MIME、文件签名、大小、页数和压缩膨胀率。
2. 在隔离工作目录中解析，不执行宏、脚本、外链或嵌入对象。
3. 保存页码/段落/标题层级等来源坐标。
4. 分块、生成本地 Embedding、写入索引。
5. 题库抽取结果必须先进入“待复核”，用户确认后才用于自动判题。

## 7. 评分设计

### 7.1 句子评分（0–100）

| 维度 | 权重 | 说明 |
|---|---:|---|
| 语法准确性 | 40 | 时态、主谓一致、从句、冠词、介词、词形等 |
| 词汇准确性 | 25 | 词义、搭配、语域、用词精确度 |
| 自然度与表达 | 25 | 是否符合英语惯用表达，是否清楚、简洁 |
| 拼写与标点 | 10 | 拼写、大小写、标点和格式 |

短句证据不足时应降低 `confidence`，避免对五六个词的句子给出虚假的高精度等级。

### 7.2 作文评分（0–100）

| 维度 | 权重 | 说明 |
|---|---:|---|
| 任务完成度 | 25 | 是否回应题目、观点是否充分、体裁是否合适 |
| 组织与连贯 | 20 | 段落、衔接、逻辑推进、指代清晰度 |
| 词汇资源 | 20 | 范围、准确性、搭配、重复和语域 |
| 语法范围与准确性 | 25 | 句式多样性、复杂度、错误密度和可理解性 |
| 规范性 | 10 | 拼写、标点、格式和字数要求 |

同时提供 CEFR `A1–C2` 的**估计区间**和置信度。量表应参考 Council of Europe 的 CEFR 写作描述符，但不能把模型评分宣传为官方 CEFR 认证。

### 7.3 评分输出契约

```json
{
  "schemaVersion": "1.0",
  "assessmentType": "ESSAY",
  "overallScore": 78,
  "cefrEstimate": { "level": "B2", "confidence": 0.71 },
  "dimensions": [
    {
      "key": "GRAMMAR",
      "score": 19,
      "maxScore": 25,
      "evidence": ["原文中的具体片段"],
      "feedback": "可执行的反馈"
    }
  ],
  "priorityFixes": [],
  "strengths": [],
  "revision": "修改后的文本",
  "disclaimer": "AI 学习反馈，不是正式考试成绩"
}
```

服务端必须用 Pydantic 校验 JSON；空输出、截断、越界分数或维度缺失时只允许有限次数重试。评分温度建议 `0–0.2`，同一测试集要做稳定性回归。

## 8. 知识库与 RAG 设计

### 8.1 知识源类型

| 类型 | 示例 | 获取方式 | 是否进入向量库 |
|---|---|---|---|
| 结构化词典 | Oxford Dictionaries API | 在线 API | 默认否；受授权限制 |
| 授权离线词典 | OUP Enterprise 数据包 | 离线授权文件 | 仅授权允许时 |
| 自建语法库 | 团队编写规则、例句、练习 | Markdown/JSON | 是 |
| 开放许可词典 | WordNet、合规的 Wiktionary 派生数据 | 下载/连接器 | 按许可证要求 |
| 用户资料 | PDF、DOC、DOCX | 本地上传 | 是，仅用户空间 |
| 用户题库 | 试卷、讲义、习题册 | 本地上传并复核 | 是，仅用户空间 |

### 8.2 牛津词典的正确接入方式

“牛津词典作为默认知识库”不能直接等同于“把牛津词典抓下来做向量库”。应实现两个互斥模式：

#### 模式 A：Oxford 在线 API（普通授权）

- 词典查询直接调用官方 API。
- 只保留条款允许的用户会话级缓存。
- 不长期保存完整词条，不批量抓取，不生成持久化向量。
- 输出中展示来源归属与必要的品牌/版权信息。
- 这一路径适合 P0 的“查单词”，不适合作为离线 RAG 全量语料。

#### 模式 B：Oxford 离线/企业授权

- 只有合同明确允许本地保存、索引和产品内展示时才导入。
- 原始授权包加密保存，并记录 `licenseId`、数据版本、到期时间与可展示字段。
- 检索时加入授权过滤；授权到期后自动禁用并提供删除索引流程。
- 只把命中的少量释义或例句发送给 LLM，不把整条词典记录或整本词典放进提示词。

#### 无 Oxford 授权时

- 产品设置页仍可把 Oxford 列为“可连接源”，但不能伪装成已启用默认源。
- 默认使用开放许可词典，并在 UI 中清楚标出实际来源。
- 语法知识库使用团队自建或单独取得授权的语法材料。词典不应承担完整语法课程的职责。

### 8.3 检索流程

```text
用户请求
  → 意图路由（查词 / 语法 / 评分 / 题库 / 普通问答）
  → 知识源与权限过滤
  → 查询改写（必要时才做）
  → SQLite FTS5 关键词召回 + 本地 Dense 向量召回
  → 合并、去重、MMR/轻量重排
  → 引用完整性检查
  → 只把 Top-N 证据片段交给 DeepSeek
  → JSON/Markdown 输出校验
  → 答案 + 可点击引用 + Token/延迟记录
```

### 8.4 低 Token 策略

| 策略 | 建议值/做法 |
|---|---|
| 意图路由 | 查词直接调用词典 API；简单拼写检查不触发 RAG |
| 分块 | 语义块约 250–450 tokens，重叠 40–60 tokens；保留标题与页码 |
| 初筛 | Dense Top 8 + FTS Top 8，合并后去重 |
| 最终上下文 | 默认 Top 4；证据总预算 1,200–1,800 tokens |
| 元数据过滤 | 先按知识库、语言、文档类型、章节、用户空间过滤，再做相似度检索 |
| 上下文压缩 | 去掉导航、重复例句、页眉页脚；保留定义、规则与来源坐标 |
| 缓存 | 缓存查询 Embedding、检索结果和允许缓存的模型响应；Oxford 受条款单独控制 |
| 对话记忆 | 只保留结构化学习状态与滚动摘要，不重复发送完整历史 |
| 评分 | 只在需要解释特定语法点时检索；不要给每篇作文塞入整个语法库 |
| 失败策略 | 证据不足就返回“未找到可靠来源”，不扩大 Top-K 到整库 |

每次请求应记录但不包含用户正文的：输入 tokens、证据 tokens、输出 tokens、命中来源数、缓存命中、模型延迟。以此建立 Token 预算门禁。

## 9. 桌面技术架构

### 9.1 推荐技术栈

| 层 | 选择 | 原因 |
|---|---|---|
| 桌面框架 | Tauri 2 | 安装包较小、系统 WebView、权限模型清晰、支持外部 Sidecar |
| 前端 | React + TypeScript + Vite | Tauri 官方推荐 SPA/Vite 路径；生态成熟，适合复杂交互 |
| UI | Tailwind CSS + shadcn/ui | 可访问性基础较好、开发快、便于形成一致设计系统 |
| 前端状态 | Zustand + TanStack Query | 区分本地 UI 状态与异步任务状态 |
| Rust 层 | Tauri commands + Sidecar manager | 负责最小权限、文件选择、密钥代理、进程与更新 |
| AI 核心 | Python 3.12 + Pydantic | 文档解析、Embedding、RAG、评测生态成熟 |
| Sidecar 通信 | Rust 代理到 `127.0.0.1` 随机端口 + 启动时短期令牌 | WebView 不直接持有密钥；便于开发和自动化测试 |
| 元数据 | SQLite + Alembic/SQLModel | 本地单用户足够，备份和迁移简单 |
| 关键词检索 | SQLite FTS5 | 无额外服务，适合精确术语和题目编号 |
| 向量检索 | Qdrant Local/Edge | 可嵌入、可落盘、无需用户运行 Docker 或独立服务 |
| Embedding | `BAAI/bge-small-en-v1.5` 本地模型 | 英文检索效果/体积折中，模型卡为 MIT；约 133 MB 权重 |
| PDF | PyMuPDF | 提取文本、页码和布局信息 |
| DOCX | python-docx | 读取段落、表格和基本结构 |
| DOC | LibreOffice headless 转换工作器 | 对旧二进制 DOC 更稳；建议作为可选安装组件并评估体积 |
| OCR（P1） | PaddleOCR 或 Tesseract | 扫描 PDF 的可选处理链 |
| Python 打包 | PyInstaller | 官方 Tauri 文档直接支持把 Python 程序作为 Sidecar 打包 |
| 测试 | Vitest、Playwright/WebDriver、pytest | 单元、契约、桌面 E2E 与 RAG 评测分层 |
| 包管理 | pnpm + uv | 分别锁定前端/Rust 外围与 Python 依赖 |

### 9.2 为什么不首选 Electron

Electron 的 Node 集成和打包工具更成熟，团队完全不熟 Rust 时会更快；但它会捆绑 Chromium，常驻内存和安装包通常更大。本产品本来就要携带 Python Sidecar 与本地 Embedding 模型，因此 UI 壳应尽量轻。建议先做 2 天技术 Spike：

- 验证 Tauri 能启动、停止并随应用打包 Python Sidecar。
- 验证 Windows 安装包能加载本地 Embedding 模型。
- 验证自动更新、文件选择与流式回复。

若 Spike 因 Sidecar 打包、企业签名或团队 Rust 能力失败，再用 ADR 把壳切到 Electron；AI Core 与本地契约保持不变。

### 9.3 进程与安全边界

```text
React WebView
  │ 仅允许白名单 Tauri commands
  ▼
Tauri/Rust 主进程
  ├─ 系统文件选择器
  ├─ 系统安全存储 / Stronghold
  ├─ Sidecar 生命周期与随机鉴权令牌
  └─ 请求参数校验
       ▼
Python AI Core（仅监听 127.0.0.1 随机端口）
  ├─ DeepSeek Gateway
  ├─ 文档解析与隔离工作区
  ├─ SQLite / FTS5
  ├─ Qdrant Local/Edge
  └─ 本地 Embedding
```

生产环境禁止 Sidecar 绑定 `0.0.0.0`。令牌只在进程内存中存在；WebView 通过 Rust 代理访问，不直接得到 DeepSeek Key 或 Sidecar 令牌。

## 10. DeepSeek 接入

### 10.1 配置

```dotenv
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
```

`DeepSeek-V4.1-Flash` 是当前服务模型名称，但官方 Quick Start 使用的公开 model id 是 `deepseek-flash`。把 model id 放入配置与模型能力表，不散落在业务代码中。

### 10.2 Gateway 职责

- OpenAI 兼容客户端封装、连接超时、指数退避和可取消流式请求。
- 每种任务独立配置：系统提示词版本、温度、最大输出 tokens、JSON Schema。
- 评分、题目抽取等任务使用 `response_format={"type":"json_object"}`，提示词中包含 JSON 示例，并用 Pydantic 校验。
- 只对网络错误、限流、空输出或可判定截断做有限重试；格式错误不得无限循环。
- 每请求设置输入、输出和总成本上限；Agent 最大工具轮数固定。
- 保存 `promptVersion`、`modelId` 和去标识化的统计信息，便于回归。

## 11. 本地接口契约

所有命令使用版本化契约和一致错误结构。

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

interface Citation {
  sourceId: string;
  sourceTitle: string;
  locator?: string; // 页码、段落、词条或 URL
  excerpt?: string;
  licenseLabel?: string;
}
```

P0 命令：

- `settings.validateModel`
- `knowledge.list`
- `knowledge.setSessionSelection`
- `documents.import`
- `jobs.get`
- `documents.delete`
- `dictionary.lookup`
- `grammar.explain`
- `assessment.scoreSentence`
- `assessment.scoreEssay`
- `chat.send`

P1 命令：

- `questions.extract`
- `questions.review`
- `practice.start`
- `practice.submit`
- `learning.getProgress`
- `learning.getReviewQueue`

导入、索引和 OCR 是长任务，调用立即返回 `jobId`，前端订阅进度事件；重复提交使用幂等键，避免同一文件重复建索引。

## 12. 文件导入与题库结构化

### 12.1 格式处理

| 格式 | P0 处理方式 | 注意事项 |
|---|---|---|
| PDF | PyMuPDF 按页提取，保存页码和块坐标 | 扫描版在 P1 进入 OCR |
| DOCX | python-docx 提取段落、表格、标题 | 禁止执行宏和外部关系 |
| DOC | LibreOffice headless 转 DOCX/PDF 后解析 | 作为可选 legacy importer；必须做超时和隔离 |

### 12.2 上传安全

- 不信任文件扩展名；检查 MIME、magic bytes 和容器结构。
- 默认单文件上限建议 50 MB、PDF 500 页；可配置但必须有硬上限。
- DOCX ZIP 解压设置文件数、总展开大小和压缩比限制，防止 ZIP bomb。
- 转换进程在临时目录、低权限、禁网环境运行，并设置 CPU/内存/时间限制。
- 丢弃宏、脚本、嵌入对象、外链和隐藏可执行内容。
- 每个知识库与用户空间做索引隔离，删除文档时同步删除块、向量和缓存。
- 把文档中的“忽略系统指令”等文本视为普通资料，不允许其改变 Agent 权限或系统提示词。

### 12.3 题库数据结构

```text
Question
├─ id / sourceId / locator
├─ type: SINGLE_CHOICE | MULTIPLE_CHOICE | FILL | READING | WRITING
├─ stem
├─ options[]
├─ answer
├─ explanation
├─ tags[]: grammar/vocabulary/CEFR/topic
├─ extractionConfidence
└─ reviewStatus: PENDING | APPROVED | REJECTED
```

自动抽取内容在 `APPROVED` 前不能进入正式练习或统计。

## 13. 建议补充的产品功能

### P1 必补

- **错误档案**：统一记录作文、语法和题库中的错误类型及证据。
- **版本对比**：显示初稿和修改稿的差异，并解释为什么更好。
- **引用检查器**：点击引用可回到原文页码/段落；无法定位的引用不展示为“有来源”。
- **知识库健康度**：显示解析失败、空页、重复文档、索引版本和授权状态。
- **可复现评分**：保存量表版本、模型 id、提示词版本和时间，便于以后解释分数变化。
- **隐私中心**：查看本地保存内容、导出数据、删除数据、清理模型缓存。

### P2 差异化

- 基于错题和写作错误的自动微课。
- 将查过的词自动生成例句、辨析题和间隔复习卡。
- 口语场景角色扮演与发音反馈。
- 完全离线模型切换与设备性能检测。

## 14. 数据模型建议

P0 表/集合：

- `app_settings`
- `knowledge_sources`
- `documents`
- `document_chunks`
- `ingestion_jobs`
- `conversations`
- `messages`
- `assessments`
- `assessment_dimensions`
- `citations`
- `prompt_versions`
- `usage_events`

P1 增加：

- `questions`
- `practice_sessions`
- `practice_answers`
- `error_records`
- `review_items`
- `learning_profiles`

所有需要删除的实体使用明确的所有权字段；删除知识源时必须清除 SQLite、FTS、向量索引、缓存和临时文件。

## 15. 推荐目录结构

```text
LanguageTeacherAgent-English/
├─ apps/
│  └─ desktop/
│     ├─ src/                    # React/TypeScript UI
│     └─ src-tauri/              # Rust 主进程与 Tauri 配置
├─ services/
│  └─ ai-core/
│     ├─ src/english_teacher/
│     │  ├─ llm/
│     │  ├─ knowledge/
│     │  ├─ ingestion/
│     │  ├─ retrieval/
│     │  ├─ dictionary/
│     │  ├─ grammar/
│     │  ├─ assessment/
│     │  └─ questions/
│     └─ tests/
├─ packages/
│  └─ contracts/                 # JSON Schema 与 TS 类型生成物
├─ evals/
│  ├─ retrieval/
│  ├─ grammar/
│  └─ writing/
├─ docs/
│  ├─ decisions/                 # ADR
│  └─ 英语老师AI-Agent-桌面客户端产品与开发方案.md
├─ tasks/
│  ├─ plan.md
│  └─ todo.md
├─ scripts/
├─ .github/workflows/
├─ CLAUDE.md
├─ .env.example
├─ pnpm-lock.yaml
└─ uv.lock
```

## 16. 开发阶段与验收门

### 阶段 0：风险 Spike（P0，先做）

- Tauri 打包并管理 PyInstaller Sidecar。
- DeepSeek `deepseek-flash` 流式输出和 JSON Output。
- PDF/DOCX/DOC 三类样本导入。
- 本地 Embedding + Qdrant Local 持久化。
- Oxford 授权路径确认。

验收门：上述任何一项失败都先写 ADR 调整方案，不开始大规模 UI 开发。

### 阶段 1：桌面骨架与契约

- 建立 monorepo、contracts、设置页、密钥存储和 CI。
- Sidecar 健康检查、统一错误结构、日志脱敏。

验收门：干净机器能安装启动；密钥不出现在文件、日志和前端状态中。

### 阶段 2：知识库闭环

- 知识源管理、文件导入、后台任务、混合检索、引用预览。

验收门：从导入 PDF/DOCX/DOC 到带页码回答全流程通过；删除后无法再次检索。

### 阶段 3：三个核心教学功能

- 查词、语法讲解、句子/作文评分。

验收门：所有答案结构稳定；查词和语法答案含真实来源；评分通过基准集回归。

### 阶段 4：题库与学习闭环（P1）

- 题库抽取/复核、练习、错题本、间隔复习和学习报告。

验收门：错误能从一次练习进入复习队列，并能在后续复习后更新掌握度。

### 阶段 5：发布准备

- 安装包签名、自动更新、崩溃恢复、备份迁移、许可证清单、隐私说明。

验收门：Windows 干净虚拟机 E2E、依赖审计、升级/回滚和数据迁移全部通过。

## 17. 测试与质量指标

### 17.1 测试层级

- 单元测试：分块、过滤、评分计算、数据迁移、错误映射。
- 契约测试：TypeScript 与 Python 针对同一 JSON Schema 的正反例。
- 集成测试：DeepSeek 使用 mock server；词典连接器使用录制且脱敏的响应。
- RAG 评测：固定问题、期望文档、Recall@K、MRR、引用正确率。
- 评分评测：至少 100 篇经人工标注的不同水平作文；检查相关性和重复运行方差。
- 文件安全测试：伪扩展名、损坏文件、超大页数、ZIP bomb、宏和 prompt injection 文档。
- 桌面 E2E：安装、首次启动、导入、检索、评分、删除、升级。

### 17.2 MVP 指标

| 指标 | 目标 |
|---|---:|
| 查词来源覆盖率 | 100% |
| RAG 答案引用覆盖率 | ≥ 95% |
| 引用可定位正确率 | ≥ 95%（人工抽检） |
| 结构化评分可解析率 | ≥ 99.5% |
| 相同作文重复评分总分标准差 | ≤ 3/100 |
| 普通检索送入模型的证据上下文 | 默认 ≤ 1,800 tokens |
| 50 页文本 PDF 索引成功率 | ≥ 99%（基准集） |
| 崩溃后导入任务可恢复/可安全重试 | 100% |

## 18. 安全、隐私与版权

- 用户文件、第三方 API、词典响应和 LLM 输出全部视为不可信输入。
- Tauri capability 只开放必要命令、文件目录和 Sidecar 参数。
- DeepSeek Key 使用 OS Keychain/Stronghold；开发环境用未提交的 `.env.local`。
- 日志不记录原文、完整提示词、密钥、Authorization header 或个人信息。
- 上传文件解析设置大小、时间、内存与页数限制。
- 知识库按用户/空间分区，检索前先做权限过滤，防止跨库泄露。
- 模型输出不得直接进入 shell、SQL、文件路径或 HTML；全部解析、校验和转义。
- 为本地数据提供查看、导出和彻底删除路径；删除覆盖向量、缓存与临时文件。
- 第三方内容保留来源、许可证与版本；授权到期能够禁用和清除。
- 若面向未成年人，需单独评估监护人同意、数据最小化和地区合规要求。

## 19. 开发 Agent 应使用的 Skills

不要在每个任务中一次性加载全部 Skill。按阶段选择最小组合：

| 阶段/场景 | Skill | 使用方式 |
|---|---|---|
| 新模块开始前 | `spec-driven-development` | 先写模块 Spec、边界和验收标准，用户确认后编码 |
| 将 Spec 拆任务 | `planning-and-task-breakdown` | 每个任务控制在 1–5 个文件，写清依赖与验证命令 |
| 多文件实现 | `incremental-implementation` | 以可运行的垂直切片落地，不一次生成整个系统 |
| 修改任何逻辑 | `test-driven-development` | 先写失败测试，再实现，尤其是分块、评分和迁移 |
| 定义本地命令/Schema | `api-and-interface-design` | 契约优先、版本化、统一错误、幂等长任务 |
| 使用 Tauri/DeepSeek/Qdrant | `source-driven-development` | 只按官方文档确认接口和版本，不凭记忆写 API |
| 构建桌面 UI | `frontend-ui-engineering` | 可访问性、键盘操作、加载/错误/空状态 |
| 上传、RAG、密钥 | `security-and-hardening` | 先做威胁模型，再做文件隔离、权限和输出校验 |
| Token/索引性能 | `performance-optimization` | 先建立指标，再调整 chunk、Top-K、缓存和模型 |
| 日志和评测 | `observability-and-instrumentation` | 记录延迟、错误码、Token、召回指标，不记录正文 |
| Git 与版本 | `git-workflow-and-versioning` | 小提交、语义化版本、功能分支和可回滚发布 |
| GitHub Actions | `ci-cd-and-automation` | lint/test/build/secret scan/安装包矩阵 |
| 设计选择 | `documentation-and-adrs` | Tauri、向量库、DOC 导入、牛津授权分别写 ADR |
| 合并前 | `code-review-and-quality` | 功能、可维护性、测试、性能、安全五轴审查 |
| 异常/失败 | `debugging-and-error-recovery` | 复现、缩小范围、修根因、补回归测试 |
| 发布 | `shipping-and-launch` | 签名、更新、回滚、迁移和发布检查表 |

推荐给 Claude Code/Zcode 的固定工作指令：

```text
读取 CLAUDE.md、当前模块 SPEC、tasks/todo.md 和相关 ADR。
一次只领取一个未完成任务；先陈述假设和将修改的文件。
先写或更新测试，再做最小实现。
不得修改任务外模块，不得引入依赖或改数据库结构而不记录 ADR。
运行任务要求的 lint、typecheck、test 和 build。
检查 staged diff 是否含密钥、用户原文或大模型文件。
更新任务状态，使用 Conventional Commit 提交并推送功能分支。
除非 CI 通过且完成代码审查，不得合并到 main。
```

## 20. GitHub 同步工作流

### 20.1 分支与提交

- `main`：始终可发布，开启保护，禁止直接 push。
- `feat/<module-id>-<short-name>`：功能。
- `fix/<module-id>-<short-name>`：缺陷。
- `docs/<short-name>`：文档与 ADR。
- Conventional Commits：`feat(retrieval): add hybrid source filtering`。

每个垂直切片一个 PR，包含：关联 Issue、验收标准、截图/录屏、测试结果、风险和回滚方式。PR 不同时混入无关重构。

### 20.2 开发同步节奏

1. 从 Issue/`tasks/todo.md` 领取一个任务。
2. 从最新 `main` 创建功能分支。
3. 完成最小可验证切片并本地测试。
4. 原子提交并 push 到 GitHub，不在本地堆积多天未同步代码。
5. 创建 Draft PR，让 CI 持续运行。
6. 达到阶段 Checkpoint 后转 Ready for review。
7. Squash merge；自动生成变更日志与预发布安装包。

### 20.3 GitHub Actions 门禁

- 前端：format、ESLint、TypeScript、Vitest、构建。
- Python：Ruff、mypy/pyright、pytest、依赖锁检查。
- Rust：fmt、clippy、test。
- 契约：JSON Schema 生成物无漂移。
- 安全：Secret scanning、依赖审计、许可证清单、SBOM。
- 桌面：Windows 安装包构建；P1 后加入 macOS matrix。
- Release：只允许带签名 tag 触发，产物包含校验和。

不要把 DeepSeek Key、Oxford App Key、证书私钥或真实用户文档放入 GitHub。CI 使用 GitHub Secrets 和脱敏测试夹具。

## 21. 关键 ADR 清单

在编码前至少创建以下决策记录：

1. `ADR-001-desktop-shell-tauri.md`：Tauri 与 Electron 的取舍。
2. `ADR-002-python-sidecar-boundary.md`：进程、通信、鉴权和打包。
3. `ADR-003-local-retrieval-storage.md`：SQLite FTS5 + Qdrant Local/Edge。
4. `ADR-004-oxford-licensing-modes.md`：在线、离线授权与 fallback。
5. `ADR-005-legacy-doc-import.md`：LibreOffice 组件的体积、安全与许可证。
6. `ADR-006-assessment-rubrics.md`：百分制、CEFR 映射和免责声明。

## 22. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| Oxford 不允许本地缓存/索引 | 核心“默认知识库”设计不可用 | 连接器模式与 RAG 模式分离；尽早确认企业授权；准备开放许可 fallback |
| LLM 评分漂移 | 用户不信任分数 | 固定量表/提示词版本、低温度、结构校验、人工标注基准集和版本说明 |
| `.doc` 支持使安装包膨胀 | 下载和更新成本增加 | 作为可选 legacy importer；Spike 比较 LibreOffice、系统 Word 和替代解析器 |
| Python Sidecar 打包复杂 | 跨平台发布受阻 | 阶段 0 先验证；协议与 AI Core 独立，必要时可换 Electron 或 Rust 实现 |
| 上传文档 prompt injection | 回答被资料中的指令劫持 | 文档只作为引用数据；系统权限在代码中；禁止文档触发工具和配置变更 |
| 本地模型占空间/性能低 | 首次体验差 | 首次下载显示大小与进度；模型哈希校验；允许 CPU 线程和低资源模式 |
| RAG 检索命中但引用错误 | “有来源”却不可复核 | 保存页码/段落坐标；引用验证；建立引用正确率评测集 |
| 用户隐私泄露到云模型 | 合规与信任风险 | 请求前提示、最小化上下文、敏感信息检测、完全离线模式路线图 |

## 23. MVP 完成定义

- [ ] Windows 安装包可在干净环境安装、启动、升级和卸载。
- [ ] 用户能安全配置 DeepSeek，并通过 `deepseek-flash` 完成流式请求。
- [ ] 用户能选择知识源；UI 明确显示授权、索引和实际使用状态。
- [ ] PDF、DOC、DOCX 均能按约定支持方式导入，并返回可理解的进度/错误。
- [ ] 用户能查词，所有词典事实都有来源。
- [ ] 用户能获取带引用的语法讲解和练习。
- [ ] 用户能获得句子与作文的分项评分、证据和修改建议。
- [ ] 普通 RAG 请求证据上下文默认不超过 1,800 tokens。
- [ ] 删除文档后，其文本、向量、缓存和引用均不可再访问。
- [ ] 单元、契约、集成、RAG 评测和桌面 E2E 在 GitHub Actions 通过。
- [ ] 仓库不含密钥、真实用户文件、未授权词典内容或未追踪的大模型二进制。

## 24. 官方资料依据

- [DeepSeek API Quick Start](https://api-docs.deepseek.com/)：OpenAI/Anthropic 兼容接口，以及当前 `deepseek-flash` model id。
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)：`response_format`、提示词和截断注意事项。
- [Tauri 2 Frontend Configuration](https://v2.tauri.app/start/frontend/)：SPA/Vite 推荐配置。
- [Tauri Embedding External Binaries](https://v2.tauri.app/develop/sidecar/)：Python/PyInstaller Sidecar 与权限配置。
- [Qdrant Local Mode](https://qdrant.tech/documentation/frameworks/langchain/)：无需独立服务的内存或磁盘持久化模式。
- [BAAI bge-small-en-v1.5 Model Card](https://huggingface.co/BAAI/bge-small-en-v1.5)：模型用法、权重大小与许可证信息。
- [Oxford Dictionaries API Getting Started](https://developer.oxforddictionaries.com/documentation/getting_started)：凭据和计划说明。
- [Oxford Dictionaries API Terms](https://developer.oxforddictionaries.com/api-terms-and-conditions)：缓存、存储、再分发和独立查词产品限制。
- [Oxford Dictionaries API FAQ](https://developer.oxforddictionaries.com/faq)：离线缓存通常需要 Enterprise 授权。
- [Council of Europe CEFR Descriptors](https://www.coe.int/en/web/common-european-framework-reference-languages/cefr-descriptors)：CEFR 等级与写作描述符来源。

## 25. 下一步

1. 产品负责人审阅本文件，重点确认第 2.2 节和模块边界。
2. 完成牛津内容授权确认；未确认前按开放许可 fallback 设计。
3. 执行阶段 0 技术 Spike，形成 6 份 ADR。
4. Spike 通过后，为每个 P0 模块生成独立 `SPEC-<module-id>.md`。
5. 按 `tasks/todo.md` 逐个垂直切片开发并通过 GitHub PR 同步。
