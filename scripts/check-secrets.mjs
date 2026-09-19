#!/usr/bin/env node
/**
 * 本机密钥扫描（SPEC-M00 §8 的 gitleaks 约束、AC-10 前半）。
 *
 * 本脚本的目标是**本机与 CI 用同一个 gitleaks 版本、同一个配置文件**，并且这件事
 * 是被断言出来的，而不是靠约定：
 *   1. 断言本机 gitleaks 的版本等于 PINNED_GITLEAKS_VERSION；
 *   2. 断言 `.github/workflows/ci.yml` 里的 GITLEAKS_VERSION 字面量与它逐字相同。
 * 任何一条不成立就拒绝扫描（退出码 2），而不是"扫了但口径不同"——口径不同的扫描结果
 * 比没有扫描更危险，因为它会让人以为本机通过就代表 CI 通过。
 *
 * 退出码：0 扫描通过；1 发现疑似密钥；2 无法按约定口径执行（缺工具/版本不符/配置漂移）。
 */

import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const configPath = join(repoRoot, '.gitleaks.toml')
const workflowPath = join(repoRoot, '.github', 'workflows', 'ci.yml')

/**
 * 固定的 gitleaks 版本。升级必须同时改这里与 ci.yml，并重新在本机全量扫描一次——
 * 上游规则变化可能让新版本报出旧版本没有的命中。
 */
const PINNED_GITLEAKS_VERSION = '8.30.1'

/** 无法按约定口径执行：属于"检查本身没跑起来"，与"跑起来且发现密钥"必须区分。 */
function cannotRun(message) {
  console.error(`[check:secrets] CANNOT RUN —— ${message}`)
  process.exit(2)
}

if (!existsSync(configPath)) {
  cannotRun('缺少 .gitleaks.toml；本脚本不会退回到"没有配置的默认扫描"。')
}
if (!existsSync(workflowPath)) {
  cannotRun(`找不到 ${workflowPath}，无法核对 CI 与本机的 gitleaks 版本是否一致。`)
}

// --- 断言 1：CI 与本机固定同一个版本 -----------------------------------------
const workflow = readFileSync(workflowPath, 'utf8')
const versionMatches = [...workflow.matchAll(/^\s*GITLEAKS_VERSION:\s*(\d+\.\d+\.\d+)\s*$/gm)].map(
  (match) => match[1],
)
if (versionMatches.length !== 1) {
  cannotRun(
    `ci.yml 里应当有且仅有一个字面量 GITLEAKS_VERSION（形如 "GITLEAKS_VERSION: 1.2.3"），` +
      `实际找到 ${versionMatches.length} 个。`,
  )
}
if (versionMatches[0] !== PINNED_GITLEAKS_VERSION) {
  cannotRun(
    `版本不一致：本脚本固定 ${PINNED_GITLEAKS_VERSION}，ci.yml 是 ${versionMatches[0]}。` +
      '请同步两者后再扫描。',
  )
}

// --- 断言 2：本机 gitleaks 存在且版本正确 --------------------------------------
const bin = process.env.GITLEAKS_BIN ?? 'gitleaks'
const versionProbe = spawnSync(bin, ['version'], { encoding: 'utf8' })

if (versionProbe.error) {
  cannotRun(
    `找不到 gitleaks 可执行文件（尝试的路径/名称：${bin}）。` +
      '请安装与 CI 一致的版本，或用环境变量 GITLEAKS_BIN 指向它：\n' +
      `  winget install --id Gitleaks.Gitleaks --version ${PINNED_GITLEAKS_VERSION} -e\n` +
      '  安装后需要重开 shell（winget 修改的是用户 PATH）。',
  )
}

const localVersion = versionProbe.stdout.trim().replace(/^v/, '')
if (localVersion !== PINNED_GITLEAKS_VERSION) {
  cannotRun(
    `本机 gitleaks 版本为 ${localVersion}，但固定版本是 ${PINNED_GITLEAKS_VERSION}。` +
      '不同版本的规则集不同，扫描结论不可比。',
  )
}

// --- 扫描 ---------------------------------------------------------------------
console.log(`[check:secrets] gitleaks ${localVersion}，配置 .gitleaks.toml，扫描全量提交历史`)
const scan = spawnSync(
  bin,
  ['git', '--config', configPath, '--no-banner', '--redact', '--exit-code', '1'],
  { cwd: repoRoot, stdio: 'inherit' },
)

if (scan.error) {
  cannotRun(`扫描进程未能启动：${scan.error.message}`)
}
if (scan.status === 0) {
  console.log('[check:secrets] OK —— 未发现疑似密钥。')
  process.exit(0)
}
console.error(`[check:secrets] FAILED —— gitleaks 退出码 ${scan.status}，疑似发现密钥。`)
console.error('  不要直接把命中内容贴到 Issue 或聊天里；先判断是否为真实密钥。')
console.error('  若确认为真实密钥：立刻轮换，再改写历史；不要仅靠 .gitleaks.toml 放行。')
process.exit(1)
