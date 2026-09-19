# schema/v1 — 契约唯一来源（T010-A：空目录占位）

这里将成为 EngMentor 本地契约的**唯一来源**（JSON Schema 2020-12）。目前只有这份说明，
还没有任何 schema —— 创建 schema、生成脚本与生成物属于 **T011**。

计划放入的 schema（SPEC-M00 §5.2）：

| 文件 | 内容 |
|---|---|
| `envelope.schema.json` | `LocalResponse<T>` 的成功/失败两形态，含 `requestId`、`citations`、`usage` |
| `error.schema.json` | `code`、`message`、`retryable`、`details` |
| `error-codes.json` | 错误码注册表，命名空间 `ENGM.<DOMAIN>.<REASON>` |
| `job.schema.json` | 长任务 `jobId`、状态枚举、进度、取消标记 |
| `citation.schema.json` | 与词典供应商无关的来源元数据（`sourceName`/`sourceVersion`/`sourceLocator`/`licenseLabel`） |
| `version.schema.json` | 契约版本协商，Sidecar 启动时上报 |

约束：

- 不做破坏性变更：字段一旦冻结，只能通过新增 `v2` 演进。
- 变更 schema 必须**同时**更新 Spec 或 ADR，并重新生成生成物（否则漂移检查会失败）。
- 具体业务命令的字段（例如查词的义项结构）由各模块的 Spec 追加，不在此处提前定义。
