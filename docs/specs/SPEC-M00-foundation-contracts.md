# SPEC-M00-foundation-contracts：Monorepo、契约、CI 与工程规则

| 字段 | 值 |
|---|---|
| 模块 ID | `M00-foundation-contracts` |
| Spec 版本 | v1.1（按用户 2026-09-19 审阅结论修订） |
| 状态 | 已修订，**待复核**；复核通过后才进入工具链预检与安装 |
| 日期 | 2026-09-19 |
| 负责人 | ZCode（用户 Holmes 审阅） |
| 依赖模块 | 无（M00 是所有模块的前置） |
| 对应任务 | [`tasks/todo.md`](../../tasks/todo.md) T010、T011、T012 |
| 上游依据 | [统一产品与技术开发方案](../英语老师AI-Agent-统一产品与技术开发方案.md) §9/§10/§15/§19/§22、[T000 决策](../decisions/T000-产品边界与技术决策建议.md)、用户审阅结论 D-1～D-6 |

---

## 1. 目标

M00 只做一件事：**让后续每个模块都能在可复现、可验证、默认安全的工程地基上开发**。

1. 建立 Monorepo 目录结构与三个安装边界（Node/pnpm、Python/uv、Rust/Cargo）。
2. 把 WebView、Tauri/Rust 主进程、Python AI Core 之间的**边界**写成可检查的约束，而不是文档里的约定。
3. 以 JSON Schema 作为唯一契约源，向 TypeScript 与 Python 生成类型、向 Rust 提供运行时校验，并让漂移可被 CI 检出。
4. 提供本机与 CI 完全一致的目标命令（lint / typecheck / test / build / contracts:check）。
5. 建立 GitHub Actions 最小门禁（Windows 优先），不依赖任何真实密钥。
6. 固定密钥、`.env`、本地数据目录与模型权重的安全边界。

## 2. 非目标（M00 明确不做）

- 不实现任何业务功能（查词、语法、评分、检索、文档导入、题库）。
- 不调用 DeepSeek 真实 API，不接入 Oxford，不写入任何真实密钥。
- 不定义业务数据库表与迁移（属于 `M02-local-storage-settings`）。
- 不下载 Embedding 模型权重，不初始化 Qdrant（属于 M04/M06）。
- 不做窗口业务 UI、代码签名、自动更新（属于 M01 / T050）。
- 不建 macOS CI 矩阵（Q2：macOS 属 P1）。
- 不做依赖审计、许可证清单与 SBOM（属于 `M12-quality-release`）。
- 不创建 PR、不开分支保护、不安装 `gh` CLI（用户另行授权）。

## 3. 环境事实与工具链预检

### 3.1 本机现状（2026-09-19 只读核对）

| 组件 | 现状 | 结论 |
|---|---|---|
| Git | 2.51.0.windows.1；`core.autocrlf` 生效（工作区 CRLF、仓库 LF） | T010 必须增加 `.gitattributes` 后，才能开启契约漂移检查 |
| Node.js | v22.20.0（已安装） | 作为基线固定 |
| npm | 10.9.3（已安装） | 仅用于引导 pnpm，不作为项目包管理器 |
| pnpm | **未安装** | 预检项 |
| Python | 3.13.7（系统解释器） | **不使用**；项目固定 3.12，由 uv 管理 |
| uv | **未安装** | 预检项 |
| Rust / Cargo | **未安装** | 预检项 |
| MSVC C++ Build Tools | **未核对** | 预检项（D-5：Windows MSVC 工具链） |
| WebView2 Runtime | **未核对** | 预检项 |
| VBSCRIPT 按需功能 | **未核对** | MSI 打包前置项，见 §3.3 |
| 远程仓库 | `origin/main` = `ddd16be`；当前分支 `feat/M00-foundation-contracts` | 就绪 |

T010 的第一个动作是**通过预检并固化版本**，而不是生成代码。

### 3.2 工具链预检清单（安装与编码前必须全部通过）

每一项都必须有命令与期望输出，未通过项先记入 `PROJECT_STATUS.md` 再处理；不得跳过缺失项直接安装。

| 检查项 | 命令 | 通过标准 |
|---|---|---|
| Node 版本 | `node --version` | `v22.x`，且与 `.node-version` 一致 |
| pnpm 可用 | `pnpm --version` | 与根 `package.json` 的 `packageManager` 完全一致 |
| uv 可用 | `uv --version` | 安装后固定到具体版本，写入 `PROJECT_STATUS.md` |
| Python 工具链 | `uv python list` | 存在 3.12.x，且 `services/ai-core/.python-version` 指向它 |
| Rust 工具链 | `rustc --version --verbose` | host 为 `x86_64-pc-windows-msvc`；版本与 `rust-toolchain.toml` 中提交的**精确版本号**一致（D-5：不得只写 stable） |
| Cargo | `cargo --version` | 与 rustc 同版本 |
| MSVC C++ Build Tools | `"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath` | 返回非空安装路径（提供 `link.exe` 与 Windows SDK） |
| WebView2 Runtime | 读取注册表 `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` 的 `pv`，或 `pnpm tauri info` | 版本非空且 ≥ 官方最低要求 |
| VBSCRIPT 按需功能 | `Get-WindowsCapability -Online -Name "*VBSCRIPT*"` | `State` 为 `Installed`；否则按 §3.3 处理 |

> 预检脚本放在 `scripts/preflight.ps1`（T010 落地），输出逐项 `PASS/FAIL/SKIP`，并把完整输出附在 `PROJECT_STATUS.md` 的交接记录中。上述注册表路径与 `vswhere` 参数需在 T010 于本机实测确认，不凭记忆固化。

### 3.3 MSI 打包前置：VBSCRIPT

Tauri 的 MSI（WiX）打包路径依赖系统 VBScript 组件。Windows 11 24H2 起 VBScript 变为按需功能，可能默认 `NotPresent`，会导致 MSI 构建或安装失败。

- 本 Spec **不**要求 M00 产出 MSI；但 `pnpm build` 会调用 Tauri 骨架构建，一旦产出 MSI 就必须记录 VBSCRIPT 状态。
- 门禁要求：在干净 Windows 机器上执行 MSI 安装验收（T001/T050）前，必须先跑 §3.2 的 VBSCRIPT 检查并记录结论。
- 若为 `NotPresent`，在 T001 内比较两条路径并记录到 ADR：启用该按需功能（`Add-WindowsCapability`，需管理员），或改用 NSIS 打包。**不**在安装包内私自捆绑或分发 VBScript 运行时。

## 4. Monorepo 目录结构

```text
LanguageTeacherAgent-English/
├─ PROJECT_STATUS.md              # 所有 Agent 第一读物与交接账本
├─ AGENTS.md / CLAUDE.md          # Agent 规则入口
├─ package.json                   # 根：private，仅编排脚本，不发布
├─ pnpm-workspace.yaml            # workspace 成员：apps/*、packages/*
├─ pnpm-lock.yaml                 # 唯一的 Node 权威 lockfile（提交）
├─ .npmrc                         # 关闭隐式 peer 安装
├─ .node-version                  # Node 22 LTS 固定
├─ .gitattributes                 # 统一 LF；二进制标记
├─ .env.example                   # 仅占位符，无真实值（提交）
├─ .gitleaks.toml                 # 本机与 CI 共用的扫描规则（提交）
├─ apps/
│  └─ desktop/
│     ├─ package.json             # 依赖 @engm/contracts（workspace:*）
│     ├─ tsconfig.json            # project references
│     ├─ vite.config.ts
│     ├─ index.html
│     ├─ src/                     # 仅 UI 与 invoke 包装层
│     └─ src-tauri/
│        ├─ Cargo.toml
│        ├─ Cargo.lock            # 提交（可执行应用边界）
│        ├─ rust-toolchain.toml   # 仅由源码树固化：精确 Rust 版本
│        ├─ tauri.conf.json       # 窗口、CSP、打包配置（不承担版本锁定职责）
│        ├─ capabilities/         # 最小权限清单（受 check:capabilities 检查）
│        └─ src/
├─ packages/
│  └─ contracts/
│     ├─ package.json             # name: @engm/contracts（private）
│     ├─ src/index.ts             # 仅 re-export 生成物
│     ├─ src/generated/v1/*.ts    # TS 生成物（提交，受漂移检查）
│     ├─ schema/v1/*.schema.json  # 唯一契约源（JSON Schema 2020-12）
│     ├─ error-codes.json         # 错误码注册表（唯一来源）
│     ├─ schema-manifest.json     # 生成：schema 清单 + 哈希（供 Rust 嵌入校验）
│     ├─ python/
│     │  ├─ pyproject.toml        # name: engm-contracts（本地可安装，不发布）
│     │  └─ src/engm_contracts/   # Python 生成物的包路径
│     │     ├─ __init__.py
│     │     └─ v1/*.py
│     ├─ tests/fixtures/*.json    # TS / Python / Rust 三方共用正反例
│     ├─ tests/*.test.ts          # 契约测试（TS 侧）
│     └─ scripts/generate.mjs     # 生成入口（TS + Python + manifest）
├─ services/
│  └─ ai-core/
│     ├─ pyproject.toml           # Python 3.12；严格 mypy；依赖 engm-contracts（path）
│     ├─ uv.lock                  # 唯一的 Python 权威 lockfile（提交）
│     ├─ src/english_teacher/     # 包根
│     ├─ tests/
│     └─ scripts/
├─ evals/                         # Eval 数据集与运行产物（产物被忽略）
├─ docs/{specs,decisions}/
├─ tasks/{plan.md,todo.md}
├─ scripts/                       # preflight.ps1、audit-capabilities.mjs 等
└─ .github/workflows/ci.yml
```

### 4.1 关键路径职责

| 路径 | 职责 | 谁可以改 |
|---|---|---|
| `packages/contracts/schema/v1/` | 唯一契约源 | 人工（须附 Spec/ADR 变更） |
| `packages/contracts/src/generated/`、`packages/contracts/python/src/` | 生成物，提交入库以便漂移检查 | **仅**生成脚本 |
| `packages/contracts/tests/fixtures/` | 三方共用正反例 | 人工 |
| `packages/contracts/python/` | 本地可安装 Python 包 `engm-contracts` | 人工（仅 `pyproject.toml`） |
| `services/ai-core/` | AI 运行时；通过 path 依赖消费契约包 | 人工 |

### 4.2 与统一方案 §22 的一致性修正

用户结论 D-4 已确认 `uv.lock` 放在 `services/ai-core/`，统一方案 §22 中「根目录 `uv.lock`」的旧描述已同步修正。本 Spec 同时补充了统一方案未列出但复现构建必需的项：`Cargo.lock`（提交）、`.gitattributes`、`.node-version`、`.npmrc`、`.gitleaks.toml`。

## 5. 边界定义

### 5.1 三层与信任边界

```text
[WebView] React/TS        ← 不可信渲染层
   │  仅白名单 Tauri commands（无任意 fs / shell / http）
   ▼
[Rust 主进程] Tauri 2      ← 唯一特权层：密钥、路径、进程、更新
   │  HTTP 127.0.0.1:<随机端口> + 内存 Bearer token
   ▼
[Python AI Core] Sidecar   ← 数据与 AI 运行时，仅 Rust 可访问
```

| ID | 规则 | 强制方式 |
|---|---|---|
| B-1 | Python Sidecar 只绑定 `127.0.0.1`，端口随机；生产路径禁止 `0.0.0.0` | 启动断言 + 单测 |
| B-2 | Sidecar 鉴权 token 每次启动随机生成，仅存于 Rust 与 Sidecar 内存；不落盘、不进日志、不进 WebView | 单测断言 token 不出现在日志与配置 |
| B-3 | WebView 不持有 DeepSeek / Oxford Key，也不持有 Sidecar token | 契约中无密钥字段 + 响应体断言 |
| B-4 | WebView 不直接发起外部网络请求 | 三层防护，见 §5.4 |
| B-5 | 契约包是命令名、信封、错误码的唯一来源；两侧不得手写重复类型 | 契约漂移检查 |
| B-6 | 所有请求/响应使用统一信封 `LocalResponse<T>`；错误必须带稳定错误码 | 三向契约测试（§5.3） |
| B-7 | 长任务返回 `jobId`，进度通过事件推送，幂等键可重放 | 契约中包含 Job/Progress schema |
| B-8 | 日志不记录用户正文、完整 Prompt、Authorization header | 日志封装层 + 单测 |

### 5.2 契约范围（M00 只落骨架，不落业务语义）

`packages/contracts/schema/v1/` 在 M00 至少包含：

- `envelope.schema.json`：`LocalResponse<T>` 成功/失败两形态，`requestId`、`citations`、`usage`。
- `error.schema.json`：`code`、`message`、`retryable`、`details`。
- `error-codes.json`：命名空间 `ENGM.<DOMAIN>.<REASON>`。M00 固化：`ENGM.CONTRACT.INVALID_INPUT`、`ENGM.CONTRACT.SCHEMA_INVALID`、`ENGM.CONTRACT.VERSION_MISMATCH`、`ENGM.INTERNAL.UNEXPECTED`。
- `job.schema.json`：`jobId`、状态枚举、进度、取消标记。
- `citation.schema.json`：`sourceName`、`sourceVersion`、`sourceLocator`、`licenseLabel`（供应商无关，对应 Q1）。
- `version.schema.json`：契约版本协商，Sidecar 启动时上报版本。

M00 **不定义**业务命令字段（如 `dictionary.lookup` 的义项结构），只保证骨架与生成链路可用；业务字段由各模块 Spec 追加。

### 5.3 Rust 运行时 JSON Schema 校验

TS 与 Python 侧由生成类型 + 校验库保证，Rust 侧不做类型生成，改为**运行时按同一份 Schema 校验**，保证三条链路的口径一致。

**覆盖的边界（全部为双向校验）：**

| 边界 | 方向 | 校验点 |
|---|---|---|
| WebView → Rust | 入站 | Tauri command 的参数在进入业务逻辑前校验 |
| Rust → WebView | 出站 | 返回 `LocalResponse<T>` 前校验，防止把畸形结果透传给 UI |
| Rust → Python | 出站 | 发往 Sidecar 的请求体在序列化后校验 |
| Python → Rust | 入站 | Sidecar 响应在解析后、进入业务逻辑前校验 |

**实现要求：**

1. Schema 以 `include_str!` 在构建期嵌入 Rust 二进制，不复制文件内容，不在运行时读取仓库路径。
2. 使用支持 JSON Schema Draft 2020-12 的校验库（计划 `jsonschema` crate；具体版本在 T011 依官方文档实测后写入 `Cargo.toml` 并由 `Cargo.lock` 固定）。
3. 编译后的校验器在首次使用时构建一次并缓存（`std::sync::OnceLock`），避免每次请求重复编译。
4. 校验失败返回 `ENGM.CONTRACT.SCHEMA_INVALID`，**不 panic、不静默透传**；错误详情只包含 schema `$id`、实例路径与失败关键字，**不得**包含用户正文。
5. 契约版本协商：Sidecar 启动时按 `version.schema.json` 上报契约版本；主进程与 Sidecar 版本不一致时返回 `ENGM.CONTRACT.VERSION_MISMATCH` 并拒绝服务，而不是继续运行。
6. 嵌入完整性：生成脚本产出 `schema-manifest.json`（schema 文件清单 + SHA-256）。Rust 侧在测试中断言嵌入集合与 manifest 完全一致，防止 Rust 落后于契约包。
7. 三向一致性测试：`packages/contracts/tests/fixtures/` 的同一组正/反例必须被 **TS、Python、Rust 三方**得出相同结论（§10 AC-4）。

### 5.4 WebView 无外网的三层防护

B-4 不依赖单一机制，三层各自独立可测、任一失效仍不放开外网：

| 层 | 机制 | 落地位置 | 验证方式 |
|---|---|---|---|
| 第 1 层：静态检查 | ESLint 禁止 WebView 代码直接使用 `fetch`、`XMLHttpRequest`、`WebSocket`、`EventSource`，只允许经 `@tauri-apps/api` 的 invoke 包装层 | `apps/desktop/src` 的 ESLint 配置 | ESLint 规则自身有单测：注入违规样例必须报错 |
| 第 2 层：CSP | `tauri.conf.json` 的 `app.security.csp` 设 `default-src 'self'`；`connect-src` 只含自身与 Tauri IPC 源，**不含任何外部域**；`script-src 'self'`；不使用 `'unsafe-eval'` | `tauri.conf.json` | 构建后断言 HTML 中被注入的 CSP 字符串与预期一致 |
| 第 3 层：能力 | `src-tauri/capabilities/*.json` 不授予任何 HTTP 权限（不引入 `tauri-plugin-http`），不授予 `shell`、通配 `fs` 权限 | `src-tauri/capabilities/` | `pnpm check:capabilities` 比对白名单，多出即失败 |

> CSP 中的具体源令牌（Windows 上 Tauri 使用 `http://tauri.localhost` 与 `http://ipc.localhost`）在 T010 依 Tauri v2 官方文档实测确认后写入，不凭记忆固化。

## 6. 工具链与锁文件策略

原则：**每个安装边界只有一个权威 lockfile，CI 用 locked 模式校验**。

| 边界 | 包管理器 | 版本固定方式 | 权威 lockfile | 安装命令 | CI 校验 |
|---|---|---|---|---|---|
| Node / 前端 | pnpm | 根 `package.json` 的 `packageManager` + `.node-version` | `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | 安装后 `git diff --exit-code` |
| Python / AI Core | uv | `.python-version` = 3.12；`requires-python = ">=3.12,<3.13"`；契约包以 path 依赖消费 | `services/ai-core/uv.lock` | `uv sync --locked --project services/ai-core` | 额外运行 `uv lock --check --project services/ai-core` |
| Rust / Tauri | Cargo | `rust-toolchain.toml` 提交**精确版本号**（D-5） | `apps/desktop/src-tauri/Cargo.lock` | `cargo build --locked` | 构建后 `git diff --exit-code` |

补充规则：

- npm **只**用于引导 pnpm（`corepack enable` 或 `npm i -g pnpm`），不作为项目包管理器。
- `.npmrc` 设 `strict-peer-dependencies=true`、`auto-install-peers=false`。
- Tauri v2（D-6）的实际版本由 `pnpm-lock.yaml` 与 `Cargo.lock` 固定；`tauri.conf.json` **不承担版本锁定职责**，本 Spec 不声称其锁定版本。
- 依赖升级必须是独立提交，不得与功能改动混在同一提交。
- 三方 GitHub Action 必须固定到完整 commit SHA，不使用浮动 tag。

### 6.1 Python 契约包的导入方式（禁止 PYTHONPATH 技巧）

- `packages/contracts/python/` 是一个正常的可安装 Python 包，包名 `engm-contracts`，顶层导入名 `engm_contracts`，不发布到任何索引。
- `services/ai-core/pyproject.toml` 以 path 依赖消费它：

  ```toml
  [project]
  dependencies = ["engm-contracts"]

  [tool.uv.sources]
  engm-contracts = { path = "../../packages/contracts/python", editable = true }
  ```

- 由 `uv sync --locked --project services/ai-core` 安装进虚拟环境，业务代码直接 `from engm_contracts.v1 import ...`。
- **禁止** `PYTHONPATH`、`sys.path.append`、`conftest.py` 路径注入、把生成物复制进 `services/ai-core/src` 等临时技巧。AC-3 含一条专门检查：在未设置 `PYTHONPATH` 的干净虚拟环境中必须能正常导入。
- mypy 视野同时覆盖 `services/ai-core/src` 与 `engm_contracts`。业务代码 `strict = true`；若生成物需要放宽，必须用 `[[tool.mypy.overrides]]` 显式列出模块并写明理由，**禁止**全局放宽严格度。

## 7. 目标命令

所有命令在仓库根目录可直接执行，本机与 CI 使用**完全相同的入口**。

| 目的 | 命令 | 覆盖范围 |
|---|---|---|
| 安装（Node） | `pnpm install --frozen-lockfile` | 根 + workspace |
| 安装（Python） | `uv sync --locked --project services/ai-core` | Python 环境 + 契约包 |
| 锁文件一致性 | `uv lock --check --project services/ai-core` | 断言 `uv.lock` 与 `pyproject.toml` 一致 |
| 契约生成 | `pnpm contracts:generate` | TS + Python 生成物 + `schema-manifest.json` |
| 契约漂移检查 | `pnpm contracts:check` | 生成物与 schema 一致；非 0 表示漂移 |
| Lint | `pnpm lint` | = `lint:web` + `lint:py` + `lint:rust` |
| | `pnpm lint:web` | ESLint（`apps/desktop/src`、`packages/contracts/src`） |
| | `pnpm lint:py` | `uv run --project services/ai-core ruff check .` |
| | `pnpm lint:rust` | `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` |
| Typecheck | `pnpm typecheck` | = `typecheck:web` + `typecheck:py` |
| | `pnpm typecheck:web` | `tsc -b --noEmit` |
| | `pnpm typecheck:py` | `uv run --project services/ai-core mypy`（严格基线，见 §6.1） |
| Test | `pnpm test` | = `test:web` + `test:py` + `test:rust` |
| | `pnpm test:web` | Vitest（含契约 TS 侧正反例） |
| | `pnpm test:py` | `uv run --project services/ai-core pytest`（含契约 Python 侧正反例） |
| | `test:rust` | `cargo test --locked`（含 Rust 运行时 Schema 校验与 manifest 一致性） |
| | `pnpm test:contracts` | 三方一致性：同一 fixtures 集合的 TS / Python / Rust 结论比对 |
| Build | `pnpm build` | Web 静态构建 + Tauri 骨架构建 |
| 安全自检 | `pnpm check:secrets` | 与 CI 同版本的 gitleaks + 同一 `.gitleaks.toml` |
| 边界自检 | `pnpm check:capabilities` | 输出 Tauri capability 授权清单并与白名单比对 |

## 8. GitHub Actions 最小 CI

文件：`.github/workflows/ci.yml`

- 触发：`push`（`main`）与 `pull_request`。
- 权限：`permissions: contents: read`（最小）。
- 并发：同一 ref 的新运行取消旧运行。
- Runner：`windows-latest`（Q2：Windows 首发）。macOS 不加入（P1）。
- 密钥：**不需要任何 secret**。缺少 `DEEPSEEK_API_KEY` 时，需要真实 API 的测试必须 `skip` 而非 `fail`。

| Job | 内容 | 阻塞 |
|---|---|---|
| `contracts` | 校验 JSON Schema → `pnpm contracts:generate` → `git diff --exit-code`（漂移即失败）→ 三方一致性测试 | 是 |
| `web` | `pnpm install --frozen-lockfile` → `lint:web` → `typecheck:web` → `test:web` → `build`（Web 部分） | 是 |
| `python` | `uv sync --locked` → `uv lock --check` → `ruff` → `mypy` → `pytest` | 是 |
| `rust` | `cargo fmt --check` → `clippy -D warnings` → `cargo test --locked` → Tauri 骨架构建 | 是 |
| `secrets` | gitleaks 固定完整 commit SHA；推送与 PR 均运行 | 是 |

gitleaks 约束（D-3）：

- Action 引用**必须**是完整 commit SHA，不使用 `@v2` 之类浮动 tag。
- 关闭 PR 评论、SARIF 上传、摘要等非必要能力，只保留退出码语义（具体参数名按固定版本的官方文档在 T010 实测确认）。
- 本机 `pnpm check:secrets` 使用与 CI **相同版本**的 gitleaks 和同一个 `.gitleaks.toml`；脚本先断言本机版本与固定版本一致，不一致直接失败。
- T010 记录所选 gitleaks 版本及其许可证，并登记到 M12 的许可证清单。
- `.gitleaks.toml` 中的例外条目必须写明理由，禁止把真实密钥形态的字符串写进配置。

缓存：`actions/setup-node`（pnpm）、`astral-sh/setup-uv`（uv cache）、Rust 构建缓存；三方 Action 全部固定 SHA。

失败信息要求：CI 失败必须能直接区分 lint、类型、测试、契约漂移与密钥问题，不得只输出一个聚合退出码。

## 9. 安全边界

### 9.1 `.env.example`

提交该文件，且**只包含无敏感值的占位符**：

```dotenv
# 本文件仅用于本地开发说明；真实值写入 OS Keychain，绝不写入 .env
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
# 真实密钥不在此填写。开发机如确需临时使用，请在 .env 中填写；
# .env 已被 .gitignore 忽略，禁止提交、禁止粘贴到 Issue 或日志。
DEEPSEEK_API_KEY=
# 本地检索模型名（权重不进入仓库）
ENGM_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
```

### 9.2 密钥

- 运行时密钥唯一合法位置：OS Keychain / Tauri Stronghold（由 T012 实现）。
- 禁止出现位置：WebView 状态、SQLite、日志、CI 日志、Git、Issue、`.env.example`。
- `.env` 仅供本地开发临时使用，已被 `.gitignore` 忽略；任何 Agent 不得提交它。

### 9.3 本地数据

- 用户数据目录在仓库之外，Windows 为 `%APPDATA%\EngMentor\`，含 `db/`、`index/`、`models/`、`logs/`、`tmp/`。
- 仓库内不得存在运行时数据；测试产生的临时数据必须落在被忽略路径并在测试结束清理。
- 模型权重、向量索引、本地数据库、用户上传文件一律不进入 Git（`.gitignore` 已覆盖；T010 用 `git check-ignore` 加回归测试）。

## 10. 验收标准

| ID | 验收标准 | 验证命令 | 期望 |
|---|---|---|---|
| AC-1 | 目录结构与两条 workspace 生效 | `pnpm -r list --depth -1`；`uv run --project services/ai-core python -c "import english_teacher"` | 列出 `apps/desktop`、`packages/contracts`；Python 包可导入 |
| AC-2 | 三个边界 locked 安装可复现且不改写 lockfile | `pnpm install --frozen-lockfile`、`uv sync --locked --project services/ai-core`、`uv lock --check --project services/ai-core`、`cargo build --locked`，随后 `git status --porcelain` | 命令全部成功；`git status --porcelain` 为空 |
| AC-3 | 契约包可正常导入，且不依赖任何路径技巧 | 删除 `PYTHONPATH` 后在干净虚拟环境执行 `python -c "from engm_contracts.v1 import Envelope"`；`rg -n "PYTHONPATH\|sys\.path" services/ packages/` | 导入成功；仓库内无 `PYTHONPATH`/`sys.path` 注入 |
| AC-4 | TS / Python / Rust 三方对同一组正反例结论一致 | `pnpm test:contracts` | 同一 fixtures 集合三方结论完全一致；未知错误码、缺 `requestId`、`ok` 与负载不匹配、越界字段均被拒 |
| AC-5 | 契约无漂移，且漂移能被检出 | `pnpm contracts:check`（未改 schema）；手工改一处生成物后再运行 | 第一次退出码 0；第二次非 0 |
| AC-6 | 四类目标命令全绿 | `pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build` | 全部退出码 0 |
| AC-7 | Rust 运行时 Schema 校验生效 | `cargo test --locked` 中的校验用例 | 四条边界的畸形输入均返回 `ENGM.CONTRACT.SCHEMA_INVALID`；无 panic；错误详情不含用户正文；版本不匹配返回 `ENGM.CONTRACT.VERSION_MISMATCH` |
| AC-8 | Rust 嵌入的 schema 集合与 manifest 一致 | manifest 一致性测试 | 集合与哈希完全一致，缺少任一 schema 即失败 |
| AC-9 | WebView 无外网三层防护均可独立验证 | ESLint 违规样例单测；构建产物 CSP 断言；`pnpm check:capabilities` | 三层各自失败可复现；能力清单与白名单一致 |
| AC-10 | 密钥与本地数据不被跟踪 | `pnpm check:secrets`；`git check-ignore -v .env`、`*.key`、`models/`、`*.db`、`target/` | 扫描 0 命中；路径全部被忽略且规则来源可打印 |
| AC-11 | MSI 打包前置（VBSCRIPT）已记录 | §3.2 的 VBSCRIPT 检查；若产出 MSI 则附实测安装结果 | 状态已记录；`NotPresent` 时给出 ADR 决策路径 |
| AC-12 | 预检清单全项通过且有证据 | `scripts/preflight.ps1` | 逐项 `PASS`；`FAIL`/`SKIP` 项已记入 `PROJECT_STATUS.md` 并说明处理方式 |
| AC-13 | 文档与状态同步 | 检查 `PROJECT_STATUS.md`、`tasks/todo.md`、本 Spec | 与实际结果一致，含验证命令与输出摘要 |
| AC-14 | 仓库无二进制与大文件 | `git ls-files -s` 过滤 + 体积检查 | 无模型权重、无构建产物、无 >1 MB 的误入库文件 |

## 11. 已确认决策（D-1～D-6）

用户于 2026-09-19 审阅确认，本 Spec 按此执行：

| ID | 决策 | 在本 Spec 中的落地 |
|---|---|---|
| D-1 | Python 类型检查用 **mypy + `pydantic.mypy`**，采用严格基线 | §6.1、§7（`typecheck:py`）、AC-6 |
| D-2 | JSON Schema 2020-12 → **json-schema-to-typescript** + **datamodel-code-generator**；T011 必须有 TS/Python 同一正反例一致性测试 | §5.2、§7（`test:contracts`）、AC-4 |
| D-3 | **Gitleaks 固定完整 SHA**；禁用 PR 评论、SARIF 上传等非必要能力；本机与 CI 同版本同规则 | §8 gitleaks 约束、AC-10 |
| D-4 | `uv.lock` 放 `services/ai-core/uv.lock`；同步修正统一方案根目录 `uv.lock` 的旧描述 | §4、§4.2、§6（统一方案 §22 已修正） |
| D-5 | **Windows MSVC 工具链**；安装时可用 stable-msvc，但 `rust-toolchain.toml` 必须提交精确版本号，不得只写 `stable` | §3.2、§6 |
| D-6 | 采用 **Tauri v2**；由 `pnpm-lock.yaml` 与 `Cargo.lock` 固定实际版本，依赖升级只能独立提交；不声称 `tauri.conf.json` 锁定版本 | §6 补充规则 |

## 12. 实施顺序

**门控：本 Spec 复核通过 → 工具链预检（§3.2）→ 安装与固化版本 → T010 → T011 → T012。**

1. **预检**：运行 §3.2 清单，公开逐项结果；未通过项先解决再安装。
2. **T010**：安装并固化 pnpm / uv / Rust（MSVC）；建目录与 workspace；写 `.gitattributes`、`.node-version`、`.npmrc`、`.env.example`、`.gitleaks.toml`、`scripts/preflight.ps1`；建根脚本骨架与 `ci.yml`。
3. **T011**：落地 `packages/contracts`（schema、error-codes、生成脚本、`schema-manifest.json`、TS 生成物、`engm-contracts` Python 包、三方 fixtures 与一致性测试、Rust 运行时校验 + 嵌入 manifest 测试）。
4. **T012**：落地设置与密钥存储骨架（M00 范围内只建接口与安全断言，业务配置留给 M02）。

每一步都遵守：先写测试 → 最小实现 → 运行 §7 命令 → 更新 `PROJECT_STATUS.md` 与 `tasks/todo.md`。

## 13. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 本机缺 pnpm/uv/Rust，且 MSVC/WebView2 未核对；安装可能受代理影响 | 阻塞 T010 | §3.2 逐项预检；代理已存在（`http.proxy=127.0.0.1:7890`）；失败则记证据并标 `BLOCKED` |
| Windows 11 24H2 起 VBScript 默认缺失影响 MSI | 阻塞打包验收 | §3.3 前置检查 + ADR 决策路径（启用按需功能或改 NSIS） |
| CRLF/LF 混用导致漂移检查假失败 | 契约漂移检查误报 | T010 先落 `.gitattributes` 统一 LF，再开启漂移检查 |
| Rust 侧 schema 嵌入落后于契约包 | 三条链路口径不一致 | `schema-manifest.json` + AC-8 一致性测试 |
| 运行时 Schema 校验拖慢热路径 | 性能退化 | 校验器编译一次并缓存；T011 记录单次校验耗时基线 |
| 三方 Action 固定 SHA 但上游被弃用 | CI 失效 | 记录 SHA 与来源；升级走独立提交 |
| 契约生成器对 JSON Schema 2020-12 支持不一致 | 生成体不可用 | T011 先用 §5.2 的 6 个 schema 做最小验证再扩展 |
| Python 3.12 由 uv 下载（系统为 3.13） | 首次安装较慢 | §3.2 显式固定，避免误用系统解释器 |
| M00 范围被业务需求侵入 | 地基延期 | 严格执行 §2 非目标；新增需求走模块 Spec |

## 14. 变更记录

| 日期 | 版本 | 变更 | 作者 |
|---|---|---|---|
| 2026-09-19 | v1.1 | 按用户审阅结论修订：uv 命令 `--frozen` → `--locked`/`uv lock --check`；新增 §5.3 Rust 运行时 Schema 校验；Python 生成物改为可安装包 `engm-contracts`（禁止 PYTHONPATH）；新增 §5.4 WebView 无外网三层防护；§3.2 预检加入 MSVC/WebView2 与 §3.3 VBSCRIPT；落定 D-1～D-6；补 AC-7～AC-12；清理行尾空格 | ZCode |
| 2026-09-19 | v1.0-draft | 初稿 | ZCode |
