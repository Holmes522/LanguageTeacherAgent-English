import { readFileSync } from 'node:fs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import Ajv2020 from 'ajv/dist/2020.js'
import { describe, expect, it } from 'vitest'

/**
 * 三方一致性测试（TS 侧，SPEC-M00 §5.3 第 7 条 / AC-4）。
 *
 * 判据是 **schema 本身**（ajv 的 draft 2020-12 实现），不是生成的 TS 类型：
 * 类型在运行期不存在，能拦住越界字段的是校验器。Python 侧用 jsonschema、Rust 侧用 jsonschema crate，
 * 三者必须对同一份 schema 与同一批实例得出同样的结论。
 *
 * 判定结果同时写入 tmp/contracts-verdicts/ts.json，供 pnpm test:contracts 与另外两方逐条比对。
 */

const here = dirname(fileURLToPath(import.meta.url))
const contractsRoot = resolve(here, '..')
const repoRoot = resolve(contractsRoot, '..', '..')
const schemaDir = join(contractsRoot, 'schema', 'v1')
const fixturesFile = join(here, 'fixtures', 'contract-cases.json')
const verdictFile = join(repoRoot, 'tmp', 'contracts-verdicts', 'ts.json')

interface FixtureCase {
  readonly name: string
  readonly schema: string
  readonly expect: 'valid' | 'invalid'
  readonly why: string
  readonly instance: unknown
}

interface FixtureDocument {
  readonly contractVersion: string
  readonly cases: readonly FixtureCase[]
}

const fixtures = JSON.parse(readFileSync(fixturesFile, 'utf8')) as FixtureDocument

const ajv = new Ajv2020({ allErrors: true, strict: true })

/**
 * 每个 schema 只编译一次。
 *
 * ajv 会按 $id 记住已注册的 schema，重复 compile 同一个 $id 会直接抛错
 * （"schema with key or id ... already exists"）。先前逐个用例编译的写法会让每个 schema 的
 * 第一条用例通过、其余全部抛错——那种失败看起来像契约有问题，实际是测试自己的缺陷。
 */
const validatorCache = new Map<string, ReturnType<typeof ajv.compile>>()

function validatorsFor(schemaFile: string) {
  const cached = validatorCache.get(schemaFile)
  if (cached !== undefined) {
    return cached
  }
  const doc = JSON.parse(readFileSync(join(schemaDir, schemaFile), 'utf8')) as object
  // strict 模式会拒绝未知关键字；契约 schema 里没有自定义关键字，若将来引入必须显式声明，
  // 而不是在这里放宽 strict —— 放宽会让 schema 的错误悄悄失去保护。
  const compiled = ajv.compile(doc)
  validatorCache.set(schemaFile, compiled)
  return compiled
}

const verdicts: Record<string, 'valid' | 'invalid'> = {}

describe('契约正反例（TS / ajv）', () => {
  it('fixtures 不为空，且每条都带 why（防止用例被清空后测试静默通过）', () => {
    expect(fixtures.cases.length).toBeGreaterThan(20)
    for (const c of fixtures.cases) {
      expect(c.why.length).toBeGreaterThan(0)
    }
  })

  for (const testCase of fixtures.cases) {
    it(`${testCase.name} → ${testCase.expect}`, () => {
      const validate = validatorsFor(testCase.schema)
      const ok = validate(testCase.instance)
      const verdict: 'valid' | 'invalid' = ok ? 'valid' : 'invalid'
      verdicts[testCase.name] = verdict

      expect(verdict, `${testCase.why}；诊断=${JSON.stringify(validate.errors ?? [])}`).toBe(
        testCase.expect,
      )
    })
  }

  it('把判定写入 tmp/，供 pnpm test:contracts 做三方比对', () => {
    const missing = fixtures.cases.filter((c) => verdicts[c.name] === undefined)
    expect(missing.map((c) => c.name)).toEqual([])

    mkdirSync(dirname(verdictFile), { recursive: true })
    writeFileSync(
      verdictFile,
      `${JSON.stringify({ language: 'typescript', verdicts }, null, 2)}\n`,
      'utf8',
    )
  })
})
