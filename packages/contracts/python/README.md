# Python 侧契约包（T010-A：占位）

计划在这里放置**可安装的本地 Python 包** `engm-contracts`（顶层导入名 `engm_contracts`），
由 `services/ai-core` 通过 `[tool.uv.sources]` 的 path 依赖消费，生成物落在
`python/src/engm_contracts/v1/`。

为什么必须做成可安装的包，而不是把生成物复制到 AI Core 的源码树里：SPEC-M00 §6.1 明确禁止
`PYTHONPATH`、`sys.path.append`、`conftest.py` 路径注入这类临时技巧——它们会让"同一个契约"
在不同机器上解析到不同文件，破坏可复现性。

本目录在 **T011** 之前只有这份说明，请勿在此提前放入 `pyproject.toml` 或生成物。
