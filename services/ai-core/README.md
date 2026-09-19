# services/ai-core — AI 运行时（T010-A：骨架）

Python 3.12 侧车进程。**当前只有一个健康检查**，没有任何教学能力。

## 边界（SPEC-M00 §5）

- 只监听 `127.0.0.1` 的随机端口，仅由 Tauri/Rust 主进程代理访问；WebView 不直连（B-1）。
- 鉴权令牌每次启动随机生成，只存在于内存，不落盘、不进日志、不进 WebView（B-2）。
- 所有进出数据使用统一信封 `LocalResponse<T>`，错误必须带稳定错误码（B-6）。
- 日志不记录用户正文、完整提示词或授权请求头（B-8）。

这些规则目前是**设计约束**，实现分别在 M03–M06 与 T012。

## 当前状态

在仓库根安装依赖；其余命令请在**本目录**下执行（`uv run --project` 会把 cwd 留在仓库根，
导致 mypy 找不到配置、ruff 与 pytest 的作用范围扩大）：

```powershell
# 仓库根
uv sync --locked --project services/ai-core

# services/ai-core 目录下
uv run pytest        # 运行健康检查测试
uv run mypy          # 严格类型检查
uv run ruff check .  # 静态检查
```

项目内可直接使用的根级编排入口：`pnpm lint:py`、`pnpm typecheck:py`、`pnpm test:py`
（它们已经替你做了 `cd services/ai-core`）。

## 不做的事

查词、语法诊断、评分、检索、文档解析、真实 API 调用、密钥存储 —— 全部等待各自模块的 Spec。
