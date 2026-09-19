# Implementation Plan: 英语老师 AI Agent 桌面客户端

## Overview

以 Windows 优先的 Tauri 桌面客户端交付本地知识库、查词、语法讲解、写作评分和题库导入。产品采用 React UI、Tauri/Rust 主进程和 Python AI Core Sidecar；本地保存资料与索引，DeepSeek 只接收完成当前请求所需的最小上下文。

完整产品与架构说明见 [`docs/英语老师AI-Agent-统一产品与技术开发方案.md`](../docs/英语老师AI-Agent-统一产品与技术开发方案.md)。当前真实进度与 Agent 交接统一记录在 [`PROJECT_STATUS.md`](../PROJECT_STATUS.md)。

## Architecture Decisions

- 桌面壳暂定 Tauri 2；先以 Spike 验证 Python Sidecar 打包，失败时通过 ADR 决定是否切换 Electron。
- DeepSeek API 使用配置化 model id `deepseek-flash`，评分与抽取使用 JSON Output + Pydantic 校验。
- SQLite 保存业务数据与 FTS5；Qdrant Local/Edge 保存向量；Embedding 默认在本地运行。
- Oxford 普通 API 只作为在线词典连接器；只有离线企业授权明确允许时才建立持久化 RAG 索引。
- 长任务采用 `jobId` + 进度事件；统一使用版本化 JSON Schema 契约。

## Dependency Order

```text
contracts → desktop shell / local storage → LLM gateway / knowledge registry
→ ingestion → retrieval → dictionary / grammar / assessment
→ question bank → learning loop → release
```

## Delivery Phases

### Phase 0: Risk Spikes

- Tauri + PyInstaller Sidecar 生命周期与安装包。
- DeepSeek streaming/JSON Output。
- PDF/DOCX/DOC 导入可行性。
- 本地 Embedding + Qdrant 持久化。
- Oxford 授权模式确认。

### Checkpoint: Architecture

- [ ] 所有 Spike 有可运行证据和测试记录。
- [ ] ADR-001 至 ADR-006 完成并获确认。
- [ ] 模块边界、默认平台和 DOC 策略获确认。

### Phase 1: Foundation

- Monorepo、契约、桌面骨架、Sidecar、设置、密钥存储、CI。
- 结构化日志、错误码、基础安全门禁。

### Checkpoint: Foundation

- [ ] 干净 Windows 环境可安装与启动。
- [ ] 所有语言的 lint/typecheck/unit test 通过。
- [ ] 密钥不进入 WebView 状态、日志、数据库或 Git。

### Phase 2: Knowledge/RAG Vertical Slice

- 知识源管理。
- PDF/DOCX/DOC 导入与后台任务。
- 本地分块、Embedding、FTS5、向量检索和引用预览。
- 文档删除与索引清理。

### Checkpoint: Knowledge

- [ ] 三种格式从导入到带定位引用回答全流程通过。
- [ ] Token 上下文预算测试通过。
- [ ] 删除后文本、向量与缓存均不可检索。

### Phase 3: Teaching Core

- 结构化词典连接器与来源展示。
- 语法讲解、例句和练习。
- 句子与作文评分、证据、修订建议。

### Checkpoint: MVP

- [ ] 查词来源覆盖率为 100%。
- [ ] RAG 引用覆盖率达到目标。
- [ ] 评分 JSON 可解析率和稳定性达到目标。
- [ ] 完整桌面 E2E 和安全测试通过。

### Phase 4: Learning Loop

- 题库抽取与复核、练习、错题本和间隔复习。
- OCR、导出和检索评测面板。

### Phase 5: Release

- Windows 签名安装包、更新、迁移、备份、回滚、SBOM 和许可证清单。
- P1 后加入 macOS 构建和适配。

## Verification Commands

命令已在 T010-A 落地并实测（Python 工具需先 `cd` 到项目目录，原因见下方说明）：

```powershell
pnpm install --frozen-lockfile
uv sync --locked --project services/ai-core
uv lock --check --project services/ai-core
cargo build --locked --manifest-path apps/desktop/src-tauri/Cargo.toml
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm contracts:check
```

> `uv sync --locked`（而非 `--frozen`）用于断言 `uv.lock` 与 `pyproject.toml` 一致；`--frozen` 只跳过更新，锁文件过期时不会报错。
>
> Python 工具（ruff / mypy / pytest）在 `services/ai-core` 目录下执行：从仓库根用
> `uv run --project services/ai-core <tool>` 时 cwd 仍在仓库根，实测会导致 mypy 找不到配置而直接失败、
> ruff 把整个仓库当作检查范围、pytest 从仓库根递归收集。完整命令、Rust 运行时契约校验与验收标准见
> [`docs/specs/SPEC-M00-foundation-contracts.md`](../docs/specs/SPEC-M00-foundation-contracts.md) 第 7 节。

> `pnpm tauri build` 尚未启用：`bundle.active` 保持 `false`，安装包与签名属于 T050。

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Oxford 授权不允许离线索引 | 高 | 在线连接器与本地 RAG 分离；开放许可 fallback |
| Sidecar 跨平台打包失败 | 高 | 阶段 0 先验证；保持 AI Core 协议独立 |
| `.doc` 解析引入大依赖 | 中 | Spike 比较方案；legacy importer 可选安装 |
| 评分漂移 | 高 | 固定量表/提示词版本，低温度，人工基准集 |
| 文档 prompt injection | 高 | 权限在代码中，资料只作为引用数据 |
| Token 成本失控 | 中 | 意图路由、Top-K、上下文预算、缓存和遥测 |

## Open Questions

- Oxford 授权类型与允许的存储/索引范围是什么？
- 首发平台与 `.doc` 的离线支持要求是什么？
- 默认评分量表是什么？
- 是否需要完全离线模式或账号同步？
