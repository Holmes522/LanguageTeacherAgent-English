#!/usr/bin/env node
/**
 * 敏感路径的忽略规则检查（SPEC-M00 §9.3、AC-10 后半）。
 *
 * 只做一件事：断言密钥与本地运行数据的路径确实被 `.gitignore` 忽略，并把**命中规则的
 * 出处**打印出来。为什么单独成脚本而不并进 check-secrets：CI 里密钥扫描由
 * gitleaks-action 完成（它自带二进制），而这条检查只需要 Node，两者依赖不同，
 * 混在一起会让 CI 为了跑一个 JSON 检查而多装一整套工具链。
 *
 * 它还做一条反向断言：`.env.example` **必须不被忽略**。`.gitignore` 里
 * `.env.*` 与 `!.env.example` 相邻，正是这类"顺手加一条通配就把模板文件一起忽略掉"
 * 的改动，值得用测试钉住——模板文件消失后 README 的配置说明会变成死链。
 *
 * 退出码：0 全部符合预期；1 有路径未被忽略（或模板被误忽略）。
 */

import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/** 必须被忽略的路径。每项都对应一条真实存在的敏感数据，不是凑数的例子。 */
const mustBeIgnored = [
  '.env', // 开发机临时密钥
  'engmentor.key', // 证书/私钥类
  'models/bge-small-en-v1.5/model.onnx', // Embedding 权重
  'data/engmentor.db', // 本地 SQLite
  'data/index/vectors.bin', // 向量索引
  'uploads/essay.docx', // 用户上传的原始资料
  'apps/desktop/src-tauri/target/debug/engmentor.pdb', // Rust 构建产物
  'tmp/preflight/report.json', // 预检报告等临时产物
]

/** 必须**不被**忽略的路径：模板与说明文件要随仓库分发。 */
const mustNotBeIgnored = ['.env.example']

/** `git check-ignore -v` 成功时返回命中规则，未命中时退出码 1。 */
function ignoreRuleFor(relativePath) {
  const result = spawnSync('git', ['check-ignore', '-v', '--', relativePath], {
    cwd: repoRoot,
    encoding: 'utf8',
  })
  if (result.error) {
    console.error(`[check:ignored] 无法执行 git：${result.error.message}`)
    process.exit(2)
  }
  if (result.status === 0) {
    // 输出形如 `.gitignore:11:.env\t.env`，取规则来源与模式两段即可。
    const [source, pattern] = result.stdout.trim().split('\t')
    return { source, pattern }
  }
  return null
}

let failed = false

console.log('[check:ignored] 必须被忽略的路径:')
for (const relativePath of mustBeIgnored) {
  const hit = ignoreRuleFor(relativePath)
  if (hit === null) {
    console.error(`  FAIL  ${relativePath} —— 未被任何规则忽略，存在误入库风险`)
    failed = true
  } else {
    console.log(`  ok    ${relativePath}  ←  ${hit.source}  [${hit.pattern}]`)
  }
}

console.log('')
console.log('[check:ignored] 必须不被忽略的路径:')
for (const relativePath of mustNotBeIgnored) {
  const hit = ignoreRuleFor(relativePath)
  if (hit !== null) {
    console.error(
      `  FAIL  ${relativePath} —— 被 ${hit.source} [${hit.pattern}] 忽略了，但它必须随仓库提交`,
    )
    failed = true
  } else {
    console.log(`  ok    ${relativePath}  （未被忽略）`)
  }
}

console.log('')
if (failed) {
  console.error('[check:ignored] FAILED —— 忽略规则与 SPEC-M00 §9.3 不符。')
  process.exit(1)
}
console.log('[check:ignored] OK —— 敏感路径全部被忽略，模板文件未被误忽略。')
