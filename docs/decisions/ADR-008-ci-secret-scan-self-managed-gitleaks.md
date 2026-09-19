# ADR-008：CI 密钥扫描改为自管下载固定版本 gitleaks

- 状态：Accepted（2026-09-19）
- 决策者：ZCode（用户 Holmes 授权执行并修复 CI）
- 影响模块：`M00-foundation-contracts`（CI 的 `secrets` job）
- 关联：SPEC-M00 §8「gitleaks 约束（D-3）」、§8.1；T010-B 交接记录

## 背景

T010-B 按 D-3 把 CI 的密钥扫描实现为 `gitleaks/gitleaks-action`，固定到完整 commit SHA
`e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e`（v3.0.0），并通过环境变量
`GITLEAKS_VERSION=8.30.1` 要求它安装与**本机完全相同**的版本
（SPEC-M00 §8 的硬要求：本机与 CI 同版本、同规则，`scripts/check-secrets.mjs` 逐字断言两处常量）。

该工作流从未在 GitHub 上运行过。2026-09-19 首次真实运行（draft PR #1，run #1）时，
`secrets` job 在"gitleaks 扫描（全量历史）"步骤失败：

```
gitleaks version: 8.30.1
Version to install: 8.30.1 (target directory: C:\Users\RUNNER~1\AppData\Local\Temp\gitleaks-8.30.1)
Downloading gitleaks from https://github.com/zricethezav/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_windows_x64.tar.gz
##[error]could not install gitleaks from ... error: Error: Unexpected HTTP response: 404
```

## 根因（已核实，非推断）

1. gitleaks 8.30.1 的发布产物中，Windows 是 **`.zip`**，darwin/linux 才是 `.tar.gz`。
   查询 GitHub Releases API 得到 8.30.1 的资产清单：
   `gitleaks_8.30.1_windows_arm64.zip`、`gitleaks_8.30.1_windows_x32.zip`、
   `gitleaks_8.30.1_windows_x64.zip`，**不存在** `gitleaks_8.30.1_windows_x64.tar.gz`。
2. `gitleaks-action` v3.0.0（当前最新，2026-05-30 发布）的安装逻辑按 `.tar.gz` 拼接
   Windows 下载地址，因此必然 404。
3. 该 Action 的 `action.yml` **没有任何 `inputs`**（全部行为由环境变量控制），因此无法
   指定"已安装的二进制"或修正资源名——不存在可用的配置绕过路径。

结论：`gitleaks-action` v3.0.0 在 Windows runner 上**无法**安装 8.30.1。要么放弃"CI 与本机
同版本"这一硬约束，要么不再使用该 Action。

## 决策

**移除 `gitleaks-action`，改为在 `secrets` job 中自管安装固定版本的 gitleaks CLI 并直接运行扫描**：

1. 从 `https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/` 下载
   `gitleaks_<version>_windows_x64.zip` **与**官方 `gitleaks_<version>_checksums.txt`；
2. 用 `checksums.txt` 中的 SHA-256 校验下载物，不匹配即失败；
3. 解压后加入 `PATH`，执行与本机**逐字相同**的命令：
   `gitleaks git --config .gitleaks.toml --no-banner --redact --exit-code 1`
   （与 `scripts/check-secrets.mjs` 的调用一致）。

`GITLEAKS_VERSION` 仍是 `ci.yml` 顶部的单一常量 `8.30.1`，`scripts/check-secrets.mjs` 继续逐字
断言它与 `PINNED_GITLEAKS_VERSION` 相同——**版本固定机制不变，只换安装方式**。

## 为什么这是对 D-3 的偏离，以及为什么可以接受

D-3 的原文包含两点：(a) "Action 引用必须是完整 commit SHA"；(b) 关闭 PR 评论、SARIF 上传、
摘要等非必要能力，只保留退出码语义。本 ADR 偏离的是 (a) 的**实现形式**。

- (b) 的**意图被更强地满足**：自管调用 CLI 时，这些能力根本不存在，而不是"关闭"。扫描结果
  只通过退出码表达。
- (a) 的**意图是供应链可信**。自管方案用两个更强的控制替代"固定 Action SHA"：固定**版本号**，
  并用发布方签名发布的 `checksums.txt` 校验下载物。Action SHA 保证的是"我拿到的是那一段代码"，
  但它自己会去下载一个**未校验**的二进制；自管方案对真正执行扫描的二进制做哈希校验。
- **许可证更干净**：`gitleaks-action` 采用 GITLEAKS-ACTION END-USER LICENSE AGREEMENT
  （个人账号免费，组织账号需 `GITLEAKS_LICENSE`）。**gitleaks CLI 是 MIT。** T010-B 已记录
  "若仓库转为组织账号，`secrets` job 会失败"这一风险——本决策把它消除，M12 的许可证清单也因此少一项。

代价：`ci.yml` 里多了一段 PowerShell 安装逻辑（约 15 行），且该逻辑是 Windows 专用。后者与本项目
"Windows 首发"（Q2）一致；P1 引入 macOS 时需要为 darwin 资源名补一条分支，届时按同一模式扩展。

## 备选方案与否决理由

| 方案 | 否决理由 |
|---|---|
| 保持 Action，不设 `GITLEAKS_VERSION` | 会让 CI 使用 Action 内置版本，违反"CI 与本机同版本"；且 `check-secrets.mjs` 的逐字断言失去意义 |
| 保持 Action，改用有 `.tar.gz` 的旧版本 | 需要放弃 8.30.1（本机已固定），或让本机降级；为迁就一个上游 bug 而退版本不合理 |
| 用其它第三方 Action | 换汤不换药：仍依赖一个会自行下载未校验二进制的第三方组件，且引入新的供应链主体 |
| 在 `secrets` job 里跳过 gitleaks，只跑忽略规则检查 | 直接放弃密钥门禁，违反 AC-10 |

## 验证要求

- 本机：`pnpm check:secrets` 必须仍为 0（版本断言逻辑未变）。
- CI：`secrets` job 在真实 runner 上通过，且日志中出现校验和匹配与 gitleaks 版本行。
- 失败关闭：篡改 `GITLEAKS_VERSION` 后，`check-secrets.mjs` 应拒绝扫描（退出码 2）——该行为在
  T010-B 已实测，本次不改动它。

## 影响

- `ci.yml` 的 `secrets` job 步骤：由 1 个 Action 步骤变为「安装 + 扫描」两个步骤。
- SPEC-M00 §8 的 gitleaks 约束与 §8.1 的 Action 清单需同步更新（Action 由 6 条减为 5 条）。
- `README.md` 中"CI 从未在 GitHub 上运行过"的说明在首次运行通过后需要更新。
