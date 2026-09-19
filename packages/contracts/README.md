# packages/contracts — 契约包（T010-A：占位）

> **当前状态：只有目录边界，没有契约内容。**
> 本包尚不包含任何 JSON Schema、生成类型或校验逻辑。引入契约生成是 **T011** 的工作。

## 这个包负责什么（计划）

按 [`SPEC-M00 §5.2–§5.4`](../../docs/specs/SPEC-M00-foundation-contracts.md)，本包将成为**本地契约的唯一来源**：

| 路径 | 职责 | 何时创建 |
|---|---|---|
| `schema/v1/*.schema.json` | 唯一契约源（JSON Schema 2020-12）：信封、错误、错误码、Job、Citation、契约版本 | T011 |
| `src/generated/` | TypeScript 生成物（提交入库，受漂移检查） | T011 |
| `python/src/engm_contracts/` | 可安装的本地 Python 包 `engm-contracts`（由 `services/ai-core` 以 path 依赖消费） | T011 |
| `tests/fixtures/` | TS / Python / Rust 三方共用的正反例 | T011 |
| `schema-manifest.json` | schema 清单 + SHA-256，供 Rust 侧断言嵌入集合一致 | T011 |
| `scripts/generate.mjs` | 生成入口 | T011 |

Rust 侧不做类型生成，而是**运行时按同一份 Schema 校验**，覆盖 WebView↔Rust 与 Rust↔Python 四条边界的双向校验。

## 明确不做的事

- 本包**不是**业务逻辑的家：查词、语法、评分、检索的领域模型属于各自的模块包。
- 契约字段一旦冻结就只能通过新增版本来变更；`v1` 内不做破坏性改动。
- 不手写与生成物重复的类型定义（SPEC-M00 规则 B-5）。

## 当前的结构检查

```powershell
pnpm contracts:check
```

该命令只验证目录结构是否完整、以及"生成尚未启用"这一状态是否被如实报告；它不会创建或生成任何 schema。如果检测到 schema 或生成物已存在而脚本尚未更新，它会**失败**而不是绕过——这一条是刻意的。
