#!/usr/bin/env node
/**
 * packages/contracts 的结构检查（T010-A）。
 *
 * T011 才会创建 Schema、生成脚本与生成物。在那之前本脚本只做两件事：
 *   1. 验证契约目录的骨架结构符合 SPEC-M00 §4；
 *   2. 如实报告"生成尚未启用"，而不是把空目录伪装成"检查通过"。
 *
 * 它**不会**创建、生成或修补任何 schema。如果检测到 schema 或生成物已经存在，
 * 它会失败——那是 T011 开始的信号，此时应当同步更新本脚本与 Spec 的验收项，
 * 而不是放宽这里的判断。这是刻意的：静默通过的检查比没有检查更危险。
 */

import { existsSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const contractsRoot = join(repoRoot, 'packages', 'contracts')

/** T010-A 阶段必须存在的骨架路径（相对 packages/contracts）。 */
const requiredPaths = [
  'README.md',
  'package.json',
  'tsconfig.json',
  'src/index.ts',
  'schema/v1',
  'python/README.md',
]

/** 生成物路径：T011 之前必须不存在。 */
const generatedPaths = [
  'src/generated',
  'python/pyproject.toml',
  'python/src/engm_contracts',
  'schema-manifest.json',
]

let missing = false
for (const rel of requiredPaths) {
  if (!existsSync(join(contractsRoot, rel))) {
    console.error(`[contracts:check] 缺少必需路径: packages/contracts/${rel}`)
    missing = true
  }
}
if (missing) {
  console.error('[contracts:check] FAILED —— 骨架结构不完整。本脚本不会自动补建。')
  process.exit(1)
}

const schemaDir = join(contractsRoot, 'schema', 'v1')
const schemaFiles = readdirSync(schemaDir).filter((name) => name.endsWith('.schema.json'))
const presentGenerated = generatedPaths.filter((rel) => existsSync(join(contractsRoot, rel)))

console.log('[contracts:check] 结构检查通过:')
for (const rel of requiredPaths) {
  console.log(`  ok  packages/contracts/${rel}`)
}
console.log('')
console.log('[contracts:check] 生成物状态: 尚未启用（属于 T011）')
console.log(`  schema/v1 中的 *.schema.json 数量: ${schemaFiles.length}`)
console.log(
  `  已存在的生成物路径: ${presentGenerated.length === 0 ? '(无)' : presentGenerated.join(', ')}`,
)

if (schemaFiles.length > 0 || presentGenerated.length > 0) {
  console.error('')
  console.error('[contracts:check] FAILED —— 检测到 schema 或生成物，但当前脚本尚未覆盖校验。')
  console.error('  请先更新本脚本（加入 schema 校验与生成物漂移检查）并同步 SPEC-M00，再继续。')
  process.exit(1)
}

console.log('')
console.log('[contracts:check] OK —— 契约生成未启用，且该状态已被显式报告。')
