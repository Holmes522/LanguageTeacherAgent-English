#!/usr/bin/env node
/**
 * 契约漂移检查（SPEC-M00 §7「契约漂移检查」/ AC-5）。
 *
 * 两段式检查，**顺序是关键**：
 *   第 1 段（先）—— 断言生成物路径相对 git 本来就是干净的。这一段必须在重新生成之前跑：
 *     一旦先重新生成，手工编辑过的文件会被覆盖回正确内容，证据就没了，检查会误报"无漂移"。
 *     这个顺序问题是实测发现的：先重新生成再 diff 的写法，对"手工改了一处生成物"完全无感。
 *   第 2 段（后）—— 重新生成，再断言生成物仍然干净。这一段负责抓"改了 schema 但忘了重新生成"。
 *
 * 退出码：0 无漂移；1 检测到漂移（会指出是哪一段发现的）；2 检查本身没能按约定口径执行。
 *
 * 为什么不是"比较哈希"：哈希只能发现变化，不能告诉人变化在哪里；`git diff` 直接给出可读差异。
 */

import { spawnSync } from 'node:child_process'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const contractsRoot = resolve(here, '..')
const repoRoot = resolve(contractsRoot, '..', '..')

/** 生成物路径（相对仓库根）。新增生成物目录时必须同步这里。 */
const GENERATED_PATHS = [
  'packages/contracts/src/generated',
  'packages/contracts/python/src/engm_contracts',
  'packages/contracts/schema-manifest.json',
]

function run(command, args, options = {}) {
  return spawnSync(command, args, { cwd: repoRoot, encoding: 'utf8', shell: false, ...options })
}

function nonEmptyLines(text) {
  return (text ?? '')
    .split('\n')
    .filter((line) => line.trim().length > 0)
}

function indent(text) {
  return nonEmptyLines(text)
    .map((line) => `    ${line}`)
    .join('\n')
}

function indentAsUntracked(text) {
  return nonEmptyLines(text)
    .map((line) => `    (未入库) ${line}`)
    .join('\n')
}

function inspectGeneratedPaths() {
  const diff = run('git', ['diff', '--exit-code', '--stat', '--', ...GENERATED_PATHS])
  const untracked = run('git', [
    'ls-files',
    '--others',
    '--exclude-standard',
    '--',
    ...GENERATED_PATHS,
  ])
  return {
    diff,
    untracked,
    hasDiff: diff.status !== 0,
    hasUntracked: nonEmptyLines(untracked.stdout).length > 0,
  }
}

// 0. 必须在 git 工作树内：否则"漂移"无从判断。
const insideWorkTree = run('git', ['rev-parse', '--is-inside-work-tree'])
if (insideWorkTree.status !== 0 || insideWorkTree.stdout.trim() !== 'true') {
  console.error('[contracts:check] FAILED —— 当前目录不是 git 工作树，无法判断漂移。')
  process.exit(2)
}

// 1. 重新生成之前：生成物路径必须已经干净。
const before = inspectGeneratedPaths()
if (before.hasDiff || before.hasUntracked) {
  console.error(
    '[contracts:check] FAILED —— 生成物路径相对 git 已经不干净（第 1 段：重新生成之前）。',
  )
  console.error('')
  console.error('  可能原因：有人手工编辑了生成物（禁止），或者本次生成的结果还没提交。')
  if (before.hasDiff) {
    console.error(indent(before.diff.stdout))
  }
  if (before.hasUntracked) {
    console.error(indentAsUntracked(before.untracked.stdout))
  }
  console.error('')
  console.error('  生成物只能由 `pnpm contracts:generate` 产生；确认无误后把结果一起提交。')
  process.exit(1)
}

// 2. 重新生成，再断言仍然干净——这一段抓"改了 schema 但忘了重新生成"。
const generate = run('node', ['scripts/generate.mjs'], { cwd: contractsRoot })
if (generate.status !== 0) {
  console.error('[contracts:check] FAILED —— 重新生成失败，无法做漂移判断。')
  console.error(generate.stdout ?? '')
  console.error(generate.stderr ?? '')
  process.exit(2)
}

const after = inspectGeneratedPaths()
if (after.hasDiff || after.hasUntracked) {
  console.error('[contracts:check] FAILED —— 检测到契约漂移（第 2 段：重新生成之后）。')
  console.error('')
  if (after.hasDiff) {
    console.error('  重新生成的结果与仓库内容不一致：')
    console.error(indent(after.diff.stdout))
    console.error('')
    console.error('  可能原因：改了 schema 但没重新生成（这正是本段要抓的情况）。')
  }
  if (after.hasUntracked) {
    console.error('  重新生成产生了尚未入库的文件：')
    console.error(indentAsUntracked(after.untracked.stdout))
    console.error('')
  }
  console.error('  处理方式：运行 `pnpm contracts:generate`，检查差异后与 schema 改动一起提交。')
  process.exit(1)
}

console.log('[contracts:check] OK —— 生成物与 schema 同步，无漂移。')
for (const path of GENERATED_PATHS) {
  console.log(`  clean  ${path}`)
}
