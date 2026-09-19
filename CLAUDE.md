# Claude Code Project Instructions

进入本项目后，第一项操作必须是完整读取 `PROJECT_STATUS.md`，然后遵循根目录 `AGENTS.md`。

## 当前权威文档

- 当前状态与交接：`PROJECT_STATUS.md`
- Agent 规则：`AGENTS.md`
- 产品与技术总方案：`docs/英语老师AI-Agent-统一产品与技术开发方案.md`
- 实施计划：`tasks/plan.md`
- 任务清单：`tasks/todo.md`
- 模块规格：`docs/specs/SPEC-<module-id>.md`（创建后生效）
- 架构决策：`docs/decisions/ADR-*.md`（创建后生效）

## 每次会话

开始时：

1. 读取 `PROJECT_STATUS.md`。
2. 检查 Git 分支、状态和最近提交。
3. 读取当前任务相关的 Spec、ADR、测试和源码。
4. 在 `PROJECT_STATUS.md` 登记当前任务与计划。

结束前：

1. 运行当前任务要求的 lint、typecheck、test、Eval 和 build。
2. 检查 staged diff 是否包含密钥、真实用户数据或未授权内容。
3. 更新 `PROJECT_STATUS.md` 和 `tasks/todo.md`。
4. 使用 Conventional Commit；通过功能分支与 PR 同步 GitHub。

未满足验收标准时不得写“已完成”。使用 `IN_PROGRESS`、`BLOCKED` 或 `READY_FOR_REVIEW` 表达真实状态。
