import { execFileSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ESLint } from 'eslint'
import { beforeAll, describe, expect, it } from 'vitest'

/**
 * WebView 无外网第 1 层防护的回归测试（SPEC-M00 §5.4）。
 *
 * 这些测试**真的运行 ESLint 引擎**并断言真实诊断与真实退出码，而不是去检查配置对象里
 * 有没有某个字符串——后者在规则被写错、被某个 ignores 覆盖、或路径没匹配上时依然会通过。
 *
 * 覆盖三类写法（每类都跑满 API × 全局对象的组合）：
 *   1. 裸全局标识符：fetch / XMLHttpRequest / WebSocket / EventSource
 *   2. 点属性访问：window. / globalThis. / self.
 *   3. 静态方括号属性访问：window[...] / globalThis[...] / self[...]
 *
 * 注意边界：ESLint 是编译期防线，**不是**安全边界。动态拼接属性名、解构取值等写法可以绕过；
 * 那些由 CSP（第 2 层）与 Tauri capability（第 3 层）在运行时兜住。
 */

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..', '..', '..')

/** 一个位于被检查目录内的虚拟路径：ESLint 据此套用 apps/desktop/src 的规则，但不落盘。 */
const PROBE_FILE = 'apps/desktop/src/__lint_network_probe__.ts'

const NETWORK_APIS = ['fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource']
const GLOBAL_OBJECTS = ['window', 'globalThis', 'self']

const NETWORK_RULES = new Set([
  'no-restricted-globals',
  'no-restricted-properties',
  'no-restricted-syntax',
])

/** 安全的负例：如果它也被判为错误，说明测试本身是坏的，而不是规则严格。 */
const SAFE_SAMPLE = 'export const answer = 42\n'

/** 允许的调用方式：经 Tauri command 走 Rust 主进程。 */
const SAFE_TAURI_SAMPLE =
  'export async function ping(): Promise<void> {\n' +
  "  const { invoke } = await import('@tauri-apps/api/core')\n" +
  "  await invoke('health_check')\n" +
  '}\n'

interface Sample {
  readonly label: string
  readonly code: string
}

function bareSamples(): Sample[] {
  const bodies: Record<string, string> = {
    fetch: 'fetch("https://example.invalid")',
    XMLHttpRequest: 'new XMLHttpRequest()',
    WebSocket: 'new WebSocket("wss://example.invalid")',
    EventSource: 'new EventSource("https://example.invalid")',
  }
  return NETWORK_APIS.map((api) => ({
    label: `裸全局 ${api}`,
    code: `export const probe = ${bodies[api]}\n`,
  }))
}

function dotAccessSamples(): Sample[] {
  const bodies: Record<string, string> = {
    fetch: '.fetch("https://example.invalid")',
    XMLHttpRequest: '.XMLHttpRequest()',
    WebSocket: '.WebSocket("wss://example.invalid")',
    EventSource: '.EventSource("https://example.invalid")',
  }
  return GLOBAL_OBJECTS.flatMap((object) =>
    NETWORK_APIS.map((api) => ({
      label: `点属性 ${object}.${api}`,
      code: `export const probe = ${object}${bodies[api]}\n`,
    })),
  )
}

function bracketAccessSamples(): Sample[] {
  const bodies: Record<string, string> = {
    fetch: '("https://example.invalid")',
    XMLHttpRequest: '()',
    WebSocket: '("wss://example.invalid")',
    EventSource: '("https://example.invalid")',
  }
  return GLOBAL_OBJECTS.flatMap((object) =>
    NETWORK_APIS.map((api) => ({
      label: `方括号 ${object}["${api}"]`,
      code: `export const probe = ${object}["${api}"]${bodies[api]}\n`,
    })),
  )
}

/**
 * 解构取值也被 no-restricted-properties 覆盖（`const { fetch } = window`）。
 * 这一条是实测确认的，不是推断——最初的实现里我误以为它是绕过形式。
 */
function destructuringSamples(): Sample[] {
  return GLOBAL_OBJECTS.flatMap((object) =>
    NETWORK_APIS.map((api) => ({
      label: `解构 const { ${api}: local } = ${object}`,
      code: `const { ${api}: local } = ${object}\nexport const probe = local\n`,
    })),
  )
}

let eslint: ESLint

beforeAll(() => {
  eslint = new ESLint({
    cwd: repoRoot,
    overrideConfigFile: join(repoRoot, 'eslint.config.mjs'),
  })
})

async function lint(code: string) {
  const results = await eslint.lintText(code, { filePath: PROBE_FILE })
  const result = results[0]
  if (result === undefined) {
    throw new Error('ESLint 未返回任何结果，测试无法判定')
  }
  return result
}

/** 用真实的 ESLint CLI 跑一次，返回退出码。 */
function cliExitCode(code: string): number {
  const bin = join(repoRoot, 'node_modules', 'eslint', 'bin', 'eslint.js')
  try {
    execFileSync(process.execPath, [bin, '--stdin', '--stdin-filename', PROBE_FILE], {
      cwd: repoRoot,
      input: code,
      stdio: ['pipe', 'pipe', 'pipe'],
    })
    return 0
  } catch (error) {
    const status = (error as { status?: number | null }).status
    return typeof status === 'number' ? status : -1
  }
}

describe('负例控制：安全的写法必须保持干净', () => {
  it('普通常量没有诊断', async () => {
    const result = await lint(SAFE_SAMPLE)
    expect(result.messages).toEqual([])
    expect(result.errorCount).toBe(0)
  })

  it('经 Tauri command 调用是被允许的方式', async () => {
    const result = await lint(SAFE_TAURI_SAMPLE)
    expect(result.messages).toEqual([])
  })

  it('CLI 对安全样例返回退出码 0', () => {
    expect(cliExitCode(SAFE_SAMPLE)).toBe(0)
  })
})

describe.each([
  ['裸全局标识符', bareSamples()],
  ['点属性访问', dotAccessSamples()],
  ['静态方括号属性访问', bracketAccessSamples()],
  ['解构取值', destructuringSamples()],
])('%s 必须被 ESLint 拒绝', (_group, samples: Sample[]) => {
  it('样例矩阵不为空（防止上面的生成器写错导致空跑）', () => {
    expect(samples.length).toBeGreaterThan(0)
  })

  for (const sample of samples) {
    it(`${sample.label} 产生网络规则诊断`, async () => {
      const result = await lint(sample.code)

      expect(result.errorCount).toBeGreaterThan(0)
      const ruleIds = result.messages.map((m) => m.ruleId ?? '')
      expect(ruleIds.some((id) => NETWORK_RULES.has(id))).toBe(true)
    })
  }
})

describe('CLI 退出码：规则确实让构建门禁失败', () => {
  for (const sample of [
    { label: '裸 fetch', code: 'export const probe = fetch("https://example.invalid")\n' },
    {
      label: 'window.fetch',
      code: 'export const probe = window.fetch("https://example.invalid")\n',
    },
    {
      label: 'globalThis.fetch',
      code: 'export const probe = globalThis.fetch("https://example.invalid")\n',
    },
    {
      label: 'self["fetch"]',
      code: 'export const probe = self["fetch"]("https://example.invalid")\n',
    },
    {
      label: 'window["WebSocket"]',
      code: 'export const probe = new window["WebSocket"]("wss://example.invalid")\n',
    },
  ]) {
    it(`${sample.label} 返回非 0 退出码`, () => {
      expect(cliExitCode(sample.code)).not.toBe(0)
    })
  }
})

/**
 * 实测确认的绕过形式。
 *
 * 这些断言的存在不是为了"接受"这些漏洞，而是把边界写成可执行的记录：
 *   1. 如果将来规则被加强到能覆盖它们，这些测试会失败，从而强制更新本文档与 Spec，
 *      而不是让"覆盖率"停留在过时的描述上；
 *   2. 明确提醒读者：ESLint 只是编译期第 1 层，越权网络访问最终必须由 CSP（第 2 层）
 *      与 Tauri capability（第 3 层）在运行时拦住。
 */
describe('已知未覆盖的绕过形式（由 CSP 与 capability 在运行时兜住）', () => {
  it('动态拼接的属性名不会被 lint 拦住', async () => {
    const result = await lint(
      'const key = "fe" + "tch"\nexport const probe = window[key]("https://example.invalid")\n',
    )
    expect(result.errorCount).toBe(0)
  })

  it('先取别名再访问不会被 lint 拦住', async () => {
    const result = await lint(
      'const w = window\nexport const probe = w.fetch("https://example.invalid")\n',
    )
    expect(result.errorCount).toBe(0)
  })

  it('在别名上使用方括号同样不会被拦住', async () => {
    const result = await lint(
      'const g = globalThis\nexport const probe = g["fetch"]("https://example.invalid")\n',
    )
    expect(result.errorCount).toBe(0)
  })
})
