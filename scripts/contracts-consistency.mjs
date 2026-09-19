#!/usr/bin/env node
/**
 * 三方一致性比对（SPEC-M00 §5.3 第 7 条 / AC-4）。
 *
 * 单独看"三方各自断言期望值"还不够：三份测试可能各自对着自己那份（被改过的）期望值通过。
 * 所以这里让三方各自把判定写进 tmp/contracts-verdicts/<lang>.json，再**逐条比对三份结果**——
 * 只有当 TS、Python、Rust 对同一个实例给出完全相同的判定时才算通过。
 *
 * 退出码：0 三方一致；1 三方不一致（会打印具体差异）；2 某一份判定没能产生（先跑着失败，不猜）。
 */

import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, rmSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..')
const verdictDir = join(repoRoot, 'tmp', 'contracts-verdicts')

const LANGUAGES = ['ts', 'py', 'rust']

function run(label, command, args, cwd) {
  process.stdout.write(`\n=== ${label} ===\n`)
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', shell: false })
  const output = `${result.stdout ?? ''}${result.stderr ?? ''}`
  process.stdout.write(output.split('\n').slice(-12).join('\n'))
  if (result.status !== 0) {
    console.error(`\n[test:contracts] FAILED —— ${label} 自身失败（退出码 ${result.status}）。`)
    process.exit(1)
  }
}

// 先清掉旧判定：残留文件会让比对建立在过期结果上。
rmSync(verdictDir, { recursive: true, force: true })

run('TypeScript（vitest + ajv）', 'pnpm', ['--filter', '@engm/contracts', 'run', 'test'], repoRoot)
run(
  'Python（pytest + jsonschema）',
  'uv',
  ['run', 'pytest', '../../packages/contracts/python/tests', '-q'],
  join(repoRoot, 'services', 'ai-core'),
)
run(
  'Rust（cargo test + jsonschema crate）',
  'cargo',
  ['test', '--locked', '--manifest-path', 'apps/desktop/src-tauri/Cargo.toml'],
  repoRoot,
)

const loaded = new Map()
for (const language of LANGUAGES) {
  const file = join(verdictDir, `${language}.json`)
  if (!existsSync(file)) {
    console.error(
      `\n[test:contracts] FAILED —— ${language} 没有产出判定文件（${file}）。\n` +
        '  三方比对的前提是三份判定都存在；不要在这一步"跳过"缺失的一方。',
    )
    process.exit(2)
  }
  const parsed = JSON.parse(readFileSync(file, 'utf8'))
  loaded.set(language, parsed.verdicts)
}

const caseNames = [...new Set([...loaded.values()].flatMap((v) => Object.keys(v)))].sort()

const mismatches = []
for (const name of caseNames) {
  const byLanguage = LANGUAGES.map((language) => [language, loaded.get(language)[name]])
  const distinct = new Set(byLanguage.map(([, verdict]) => verdict))
  if (distinct.size !== 1 || distinct.has(undefined)) {
    mismatches.push({ name, byLanguage })
  }
}

console.log('')
if (mismatches.length > 0) {
  console.error(`[test:contracts] FAILED —— ${mismatches.length}/${caseNames.length} 条用例的三方判定不一致：`)
  for (const { name, byLanguage } of mismatches) {
    console.error(`  ${name}: ${byLanguage.map(([lang, v]) => `${lang}=${v ?? '(缺失)'}`).join('  ')}`)
  }
  console.error('')
  console.error('  这类差异通常意味着某一方的校验器对 schema 的语义理解不同（默认值、格式、$ref 解析等），')
  console.error('  必须查清原因，不要把某一方的判定改成"和别的一致"就收工。')
  process.exit(1)
}

console.log(`[test:contracts] OK —— ${caseNames.length} 条用例在 TS / Python / Rust 三方判定完全一致。`)
for (const language of LANGUAGES) {
  console.log(`  ${language}: ${Object.keys(loaded.get(language)).length} 条`)
}
