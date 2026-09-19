# SPEC-M00-foundation-contracts：Monorepo、契约、CI 与工程规则

> 模块 ID：`M00-foundation-contracts`  
> Spec 版本：v1.0-draft  
> 状态：**待审阅（DRAFT）** — 用户批准前不得开始编码  
> 日期：2026-09-19  
> 负责人：ZCode（用户 Holmes 审阅）  
> 依赖模块：无（M00 是所有模块的前置）  
> 对应任务：[`tasks/todo.md`](../../tasks/todo.md) T010、T011、T012  
> 上游依据：[`统一产品与技术开发方案`](../英语老师AI-Agent-统一产品与技术开发方案.md) 第 9/10/15/19/22 节、[`T000 决策`](../decisions/T000-产品边界与技术决策建议.md)

---

## 1. 目标

M00 只做一件事：**让后续每个模块都能在可复现、可验证、默认安全的工程地基上开发**。

具体目标：

1. 建立 Monorepo 目录结构与三个安装边界（Node/pnpm、Python/uv、Rust/Cargo）。
2. 把 WebView、Tauri/Rust 主进程、Python AI Core 之间的**边界**写成可检查的约束，而不是文档里的约定。
3. 以 JSON Schema 作为唯一契约源，向 TypeScript 与 Python 双向生成类型，并让漂移可被 CI 检出。
4. 提供本机与 CI 完全一致的目标命令（lint / typecheck / test / build / contracts:check）。
5. 建立 GitHub Actions 最小门禁（Windows 优先），不依赖任何真实密钥。
6. 固定密钥、`.env`、本地数据目录与模型权重的安全边界。

## 2. 非目标（M00 明确不做）

- 不实现任何业务功能（查词、语法、评分、检索、文档导入、题库）。
- 不调用 DeepSeek 真实 API，不接入 Oxford，不写入任何真实密钥。
- 不定义业务数据库表与迁移（属于 `M02-local-storage-settings`）。
- 不下载 Embedding 模型权重，不初始化 Qdrant（属于 M04/M06）。
- 不做窗口业务 UI、打包安装包、代码签名、自动更新（属于 M01 / T050）。
- 不建 macOS CI 矩阵（Q2：macOS 属 P1）。
- 不做依赖审计、许可证清单与 SBOM（属于 `M12-quality-release`）。
- 不创建 PR、不开分支保护、不安装 `gh` CLI（用户另行授权）。

## 3. 当前环境事实（2026-09-19 只读核对）

| 组件 | 本机现状 | 结论 |
|---|---|---|
| Git | 2.51.0.windows.1；`core.autocrlf` 生效（工作区 CRLF、仓库 LF） | 需在 T010 增加 `.gitattributes` |
| Node.js | v22.20.0（已安装） | 可作为基线 |
| npm | 10.9.3（已安装） | 仅用于引导 pnpm，不作为项目包管理器 |
| pnpm | **未安装** | T010 前置：安装并锁定版本 |
| Python | 3.13.7（系统解释器） | **不使用**；项目固定 3.12，由 uv 管理 |
| uv | **未安装** | T010 前置 |
| Rust / Cargo | **未安装** | T010 前置（Tauri 2 需要） |
| 远程仓库 | `origin/main` = `ddd16be`（`main` 已同步） | 就绪 |

因此 T010 的第一个动作是**安装三个工具链并固化版本**，而不是生成代码。

## 4. Monorepo 目录结构

```text
LanguageTeacherAgent-English/
├─ PROJECT_STATUS.md              # 所有 Agent 第一读物与交接账本
├─ AGENTS.md / CLAUDE.md          # Agent 规则入口
├─ package.json                   # 根：private，仅编排脚本，不发布
├─ pnpm-workspace.yaml            # workspace 成员：apps/*、packages/*
├─ pnpm-lock.yaml                 # 唯一的 Node 权威 lockfile（提交）
├─ .npmrc                         # 关闭隐式安装、固定 registry 策略
├─ .node-version                  # Node 22 LTS 固定
├─ .gitattributes                 # 统一 LF；二进制标记
├─ .env.example                   # 仅占位符，无真实值（提交）
├─ apps/
│  └─ desktop/
│     ├─ package.json             # WebView：React + TS + Vite
│     ├─ tsconfig.json            # project references（src / src-tauri 分离）
│     ├─ vite.config.ts
│     ├─ index.html
│     ├─ src/                     # 仅 UI 与调用层，不含密钥与直连网络
│     └─ src-tauri/               # Rust 主进程与 Tauri 配置
│        ├─ Cargo.toml
│        ├─ Cargo.lock            # 提交（可执行应用边界）
│        ├─ tauri.conf.json
│        ├─ capabilities/         # 最小权限清单（受 AC-8 检查）
│        └─ src/
├─ packages/
│  └─ contracts/
│     ├─ package.json
│     ├─ schema/v1/*.schema.json  # 唯一契约源（JSON Schema 2020-12）
│     ├─ error-codes.json         # 错误码注册表（唯一来源）
│     ├─ generated/ts/            # 生成物（提交，受漂移检查）
│     ├─ generated/python/        # 生成物（提交，受漂移检查）
│     ├─ scripts/generate.mjs     # TS/Python 生成入口
│     └─ tests/                   # 契约正反例测试
├─ services/
│  └─ ai-core/
│     ├─ pyproject.toml           # Python 3.12；Pydantic v2；ruff/mypy/pytest 配置
│     ├─ uv.lock                  # 唯一的 Python 权威 lockfile（提交）
│     ├─ src/english_teacher/     # 包根
│     ├─ tests/
│     └─ scripts/
├─ evals/                         # Eval 数据集与运行产物（产物被忽略）
├─ docs/{specs,decisions}/
├─ tasks/{plan.md,todo.md}
├─ scripts/                       # 跨边界编排脚本（如 audit-capabilities）
└─ .github/workflows/ci.yml
```

### 4.1 与统一方案 §22 的差异（显式记录）

| 项 | 统一方案 §22 | 本 Spec | 理由 |
|---|---|---|---|
| `uv.lock` 位置 | 仓库根 | `services/ai-core/uv.lock` | uv 的 lockfile 必须与定义项目的 `pyproject.toml` 同目录；根目录没有 Python 项目。若需要根级 lockfile 就必须引入 uv workspace，为单个包增加复杂度不划算。 |
| `Cargo.lock` | 未列出 | `apps/desktop/src-tauri/Cargo.lock`（提交） | Rust 可执行应用必须提交 lockfile 才能复现构建。 |
| `.gitattributes` / `.node-version` / `.npmrc` | 未列出 | 新增 | 本机 CRLF 与 CRLF/LF 混用已产生告警，需在 T010 固化。 |

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

规则（每条都必须能在代码或检查中体现）：

| ID | 规则 | 强制方式 |
|---|---|---|
| B-1 | Python Sidecar 只绑定 `127.0.0.1`，端口随机；生产路径禁止 `0.0.0.0` | 启动代码断言 + 单测 |
| B-2 | Sidecar 鉴权 token 每次启动随机生成，仅存于 Rust 与 Sidecar 内存；不落盘、不进日志、不进 WebView | 单测断言 token 不出现在日志与配置 |
| B-3 | WebView 不持有 DeepSeek / Oxford Key，也不持有 Sidecar token | Tauri command 返回体契约中不含密钥字段 |
| B-4 | WebView 不直接发起外部网络请求 | ESLint 限制 + capability 最小化 |
| B-5 | 契约包是命令名、信封、错误码的唯一来源；两侧不得手写重复类型 | 契约漂移检查 |
| B-6 | 所有请求/响应使用统一信封 `LocalResponse<T>`；错误必须带稳定错误码 | 契约测试（正反例） |
| B-7 | 长任务返回 `jobId`，进度通过事件推送，幂等键可重放 | 契约中包含 Job/Progress schema |
| B-8 | 日志不记录用户正文、完整 Prompt、Authorization header | 日志封装层 + 单测 |

### 5.2 契约范围（M00 只落骨架，不落业务语义）

`packages/contracts/schema/v1/` 在 M00 至少包含：

- `envelope.schema.json`：`LocalResponse<T>` 成功/失败两种形态，`requestId`、`citations`、`usage`。
- `error.schema.json`：`code`、`message`、`retryable`、`details`。
- `error-codes.json`：命名空间 `ENGM.<DOMAIN>.<REASON>`，M00 只固化通用码（`ENGM.CONTRACT.INVALID_INPUT`、`ENGM.INTERNAL.UNEXPECTED`、`ENGM.CONTRACT.VERSION_MISMATCH`）。
- `job.schema.json`：`jobId`、状态枚举、进度、取消标记。
- `citation.schema.json`：`sourceName`、`sourceVersion`、`sourceLocator`、`licenseLabel`（与词典供应商无关，对应 Q1 约束）。
- `version.schema.json`：契约版本协商，Sidecar 启动时上报版本。

M00 **不定义**业务命令的字段（如 `dictionary.lookup` 的义项结构），只保证骨架与生成链路可用；业务字段由各模块的 Spec 追加。

## 6. 工具链与锁文件策略

原则：**每个安装边界只有一个权威 lockfile，且 CI 用 frozen 模式校验**。

| 边界 | 包管理器 | 版本固定方式 | 权威 lockfile | 安装命令 | CI 校验 |
|---|---|---|---|---|---|
| Node / 前端 | pnpm | 根 `package.json` 的 `packageManager` 字段 + `.node-version` | `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` | frozen 安装后 `git diff --exit-code` |
| Python / AI Core | uv | `.python-version` = 3.12；`requires-python = ">=3.12,<3.13"` | `services/ai-core/uv.lock` | `uv sync --frozen --project services/ai-core` | 同上 |
| Rust / Tauri | Cargo | `rust-toolchain.toml`（stable + rustfmt/clippy） | `apps/desktop/src-tauri/Cargo.lock` | `cargo build --locked` | 同上 |

补充规则：

- npm **只**用于引导 pnpm（`corepack enable` 或 `npm i -g pnpm`），不作为项目包管理器。
- 不使用 `pnpm` 的隐式 peer 安装；`.npmrc` 设 `strict-peer-dependencies=true`、`auto-install-peers=false`。
- 三方 GitHub Action **必须**固定到完整 commit SHA，不使用浮动 tag（供应链要求）。
- 依赖版本升级是独立提交，不得与功能改动混在同一提交。

## 7. 目标命令

所有命令必须在仓库根目录可直接执行，且本机与 CI 使用**完全相同的入口**。

| 目的 | 命令 | 覆盖范围 |
|---|---|---|
| 安装 | `pnpm install --frozen-lockfile` | 根 + workspace |
| 安装 | `uv sync --frozen --project services/ai-core` | Python |
| 契约生成 | `pnpm contracts:generate` | `packages/contracts` |
| 契约漂移检查 | `pnpm contracts:check` | 生成物与 schema 一致；退出码非 0 表示漂移 |
| Lint | `pnpm lint` | = `lint:web` + `lint:py` + `lint:rust` |
| | `pnpm lint:web` | ESLint（`apps/desktop/src`、`packages/*`） |
| | `pnpm lint:py` | `uv run --project services/ai-core ruff check .` |
| | `pnpm lint:rust` | `cargo fmt --check` + `cargo clippy --all-targets -- -D warnings` |
| Typecheck | `pnpm typecheck` | = `typecheck:web` + `typecheck:py` |
| | `pnpm typecheck:web` | `tsc -b --noEmit`（workspace 全部 TS） |
| | `pnpm typecheck:py` | `uv run --project services/ai-core mypy src` |
| Test | `pnpm test` | = `test:web` + `test:py` + `test:rust` |
| | `pnpm test:web` | Vitest（含契约正反例） |
| | `pnpm test:py` | `uv run --project services/ai-core pytest` |
| | `test:rust` | `cargo test --locked` |
| Build | `pnpm build` | Web 静态构建 + Tauri 骨架构建 |
| 安全自检 | `pnpm check:secrets` | 本地 secret 扫描（与 CI 同规则） |
| 边界自检 | `pnpm check:capabilities` | 输出 Tauri capability 授权清单并与白名单比对 |

约定：`typecheck:py` 使用 **mypy**（Pydantic v2 插件）。这是本 Spec 的选择，见 §11 待确认项。

## 8. GitHub Actions 最小 CI

文件：`.github/workflows/ci.yml`

- 触发：`push`（`main`）与 `pull_request`。
- 权限：`permissions: contents: read`（默认最小）。
- 并发：同一 ref 的新运行取消旧运行（`cancel-in-progress`）。
- Runner：`windows-latest`（Q2：Windows 首发）。macOS 不加入（P1）。
- 服务与密钥：**不需要任何 secret**。缺少 `DEEPSEEK_API_KEY` 时，需要真实 API 的测试必须 `skip` 而不是 `fail`。

Job 划分（最小集合，5 个）：

| Job | 内容 | 阻塞 |
|---|---|---|
| `contracts` | 校验 JSON Schema → `pnpm contracts:generate` → `git diff --exit-code`（漂移即失败）→ 契约正反例测试 | 是 |
| `web` | `pnpm install --frozen-lockfile` → `lint:web` → `typecheck:web` → `test:web` → `build`（Web 部分） | 是 |
| `python` | `uv sync --frozen` → `ruff` → `mypy` → `pytest` | 是 |
| `rust` | `cargo fmt --check` → `clippy -D warnings` → `cargo test --locked` → Tauri 骨架构建 | 是 |
| `secrets` | secret 扫描（推送与 PR 均运行） | 是 |

缓存：`actions/setup-node`（pnpm）、`astral-sh/setup-uv`（uv cache）、Rust 构建缓存。三方 Action 全部固定 SHA。

失败信息要求：CI 失败必须能直接看出是 lint、类型、测试、契约漂移还是密钥问题；不得只输出一个聚合退出码。

## 9. 安全边界

### 9.1 `.env.example`

提交该文件，且**只包含无敏感值的占位符**：

```dotenv
# 本文件仅用于本地开发说明；真实值写入 OS Keychain，绝不写入 .env
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-flash
# 真实密钥不在此填写。开发机如确需临时使用，请在 .env 中填写，
# 但 .env 已被 .gitignore 忽略，且禁止提交、禁止粘贴到 Issue/日志。
DEEPSEEK_API_KEY=
# 本地检索模型名（权重不进入仓库）
ENGM_EMBEDDING_MODEL=BAAI/bge-small-en-v1.5
```

### 9.2 密钥

- 运行时密钥唯一合法位置：OS Keychain / Tauri Stronghold（M02/T012 实现）。
- 禁止出现位置：WebView 状态、SQLite、日志、CI 日志、Git、Issue、`.env.example`。
- `.env` 仅供本地开发临时使用，已被 `.gitignore` 忽略；任何 Agent 不得提交它。

### 9.3 本地数据

- 用户数据目录在系统 AppData 之外于仓库，Windows 为 `%APPDATA%\EngMentor\`，含 `db/`、`index/`、`models/`、`logs/`、`tmp/`。
- 仓库内**不得**存在运行时数据；如为测试产生临时数据，必须落在被忽略路径并在测试结束清理。
- 模型权重、向量索引、本地数据库、用户上传文件一律不进入 Git（`.gitignore` 已覆盖；T010 用 `git check-ignore` 加回归测试）。

## 10. 验收标准

每条都给出可执行验证。全部通过才可标记 `DONE`。

| ID | 验收标准 | 验证命令 | 期望 |
|---|---|---|---|
| AC-1 | 目录结构与两条 workspace 生效 | `pnpm -r list --depth -1`；`uv run --project services/ai-core python -c "import english_teacher"` | 列出 `apps/desktop`、`packages/contracts`；Python 包可导入且无报错 |
| AC-2 | 三个边界 frozen 安装可复现且不改写 lockfile | `pnpm install --frozen-lockfile`、`uv sync --frozen --project services/ai-core`、`cargo build --locked`，随后 `git status --porcelain` | 三条命令成功；`git status --porcelain` 为空 |
| AC-3 | 契约无漂移，且漂移能被检出 | `pnpm contracts:check`（未改 schema）；手工改一处生成物后再运行 | 第一次退出码 0；第二次退出码非 0 |
| AC-4 | TS 与 Python 对同一组正反例结论一致 | `pnpm test:web` 与 `pnpm test:py` 中的契约用例 | 同一组 fixture 两侧结论完全一致；未知错误码、缺 `requestId`、`ok` 与负载不匹配的用例均被拒 |
| AC-5 | 四类目标命令全绿 | `pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm build` | 全部退出码 0 |
| AC-6 | CI 在 Windows runner 通过且不需要任何密钥 | GitHub Actions `ci.yml` 运行结果 | 5 个 job 全绿；仓库无任何 required secret；缺 key 时相关测试为 `skipped` |
| AC-7 | 密钥与本地数据不被跟踪 | `pnpm check:secrets`；`git check-ignore -v .env`、`*.key`、`models/`、`*.db`、`target/` | 扫描 0 命中；全部路径被忽略且规则来源可打印 |
| AC-8 | 边界约束可检查而非仅靠约定 | `pnpm check:capabilities`；ESLint 外链规则；B-1/B-2 单测 | capability 清单与白名单一致；WebView 无外部直连；Sidecar token 不出现在日志与配置 |
| AC-9 | 文档与状态同步 | 检查 `PROJECT_STATUS.md`、`tasks/todo.md`、本 Spec 的验收结果 | 与实际结果一致，含验证命令与输出摘要 |
| AC-10 | 仓库无二进制与大文件 | `git ls-files -s` 过滤 + 体积检查 | 无模型权重、无构建产物、无 >1 MB 的误入库文件 |

## 11. 待确认项（审阅本 Spec 时一并决定）

| ID | 待确认 | 本 Spec 的建议 | 影响 |
|---|---|---|---|
| D-1 | Python 类型检查器 | `mypy` + Pydantic 插件 | 影响 `typecheck:py` 与 CI 时长 |
| D-2 | 契约生成器组合 | JSON Schema 2020-12 → `json-schema-to-typescript`（TS）+ `datamodel-code-generator`（Pydantic v2） | 引入两个开发依赖；若改其他方案应先写 ADR-008 |
| D-3 | secret 扫描实现 | CI 使用固定 SHA 的 gitleaks Action；本机用同规则脚本 | 引入一个三方 Action（供应链风险） |
| D-4 | `uv.lock` 位置 | `services/ai-core/uv.lock`（偏离统一方案 §22，理由见 §4.1） | 若不接受则需引入 uv workspace |
| D-5 | Rust 工具链与 MSRV | `rust-toolchain.toml` 固定 stable；MSRV 由 Tauri 2 官方要求决定，T010 实测后写入 | 影响 CI 与后续升级策略 |
| D-6 | Tauri 2 版本锁定 | 锁定到 T010 时的最新 2.x minor，并记录在 `Cargo.toml` + `tauri.conf.json` | 影响后续升级成本 |

> 本 Spec 一经批准，即视为对 T010–T012 所需依赖与工具选择的批准。偏离本 Spec 的技术选择必须先写 ADR。

## 12. 实施顺序（T010 → T011 → T012）

1. **T010**：安装并锁定 pnpm / uv / Rust；创建目录与 workspace；写 `.gitattributes`、`.node-version`、`.npmrc`、`.env.example`、根脚本骨架；创建 `ci.yml`。
2. **T011**：落地 `packages/contracts`（schema + error-codes + 生成脚本 + 两侧契约测试 + 漂移检查）。
3. **T012**：落地设置与密钥存储骨架（M00 范围内只建立接口与安全断言，业务配置留给 M02）。

每一步都遵守：先写测试 → 最小实现 → 运行 §7 命令 → 更新 `PROJECT_STATUS.md` 与 `tasks/todo.md`。

## 13. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 本机缺 pnpm/uv/Rust，安装过程可能受代理或镜像影响 | 阻塞 T010 | 先验证三个工具链可安装并固化版本；代理已存在（`http.proxy=127.0.0.1:7890`），安装失败则记录证据并标记 `BLOCKED` |
| 三方 Action 固定 SHA 但上游被弃用 | CI 失效 | 记录 SHA 与来源；升级走独立提交 |
| 契约生成器对 JSON Schema 2020-12 支持不一致 | 生成体不可用 | T011 先用 §5.2 的 6 个 schema 做最小验证，再扩展 |
| Python 3.12 由 uv 下载（系统为 3.13） | 首次安装较慢 | 在 §3 与 CI 中显式固定，避免误用系统解释器 |
| CRLF/LF 混用导致漂移检查误报 | 契约漂移检查假失败 | T010 先加 `.gitattributes` 统一 LF，再开启漂移检查 |
| M00 范围被业务需求侵入 | 地基延期 | 严格执行 §2 非目标；新增需求走模块 Spec |

## 14. 变更记录

| 日期 | 版本 | 变更 | 作者 |
|---|---|---|---|
| 2026-09-19 | v1.0-draft | 初稿：目录结构、边界、工具链与锁文件、目标命令、最小 CI、安全边界、验收标准、非目标 | ZCode |
