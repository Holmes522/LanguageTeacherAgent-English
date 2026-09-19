import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

/**
 * tauri.conf.json 的安全与范围边界断言。
 *
 * 对应 SPEC-M00 §5.4（WebView 无外网三层防护的第 2 层）与 §2（非目标）。
 * 放在测试里，是为了让"改配置就悄悄放开外网"或"提前开启打包"这类改动直接失败，
 * 而不是等评审时靠人眼发现。
 *
 * CSP 采用**白名单精确断言**：connect-src 的 token 集合必须与允许集合完全相等。
 * 仅仅"没有 http/https 外部地址"是不够的——ws://、wss://、data:、blob: 以及任意自定义
 * 协议都能成为外泄或注入通道，所以任何多余 token 都必须让测试失败。
 */

interface TauriConf {
  identifier: string
  app: { security: { csp: string } }
  bundle: { active: boolean }
}

/**
 * connect-src 允许的 token，且**仅限**这三个。
 *
 * `ipc:` 与 `http://ipc.localhost` 来自 Tauri v2 官方 CSP 文档的示例（用于保持 IPC 可用）：
 * https://v2.tauri.app/security/csp/ —— 官方原文给出 `"connect-src": "ipc: http://ipc.localhost"`。
 * `'self'` 是本仓库额外需要的：前端由 Vite 构建后从自身源加载。
 */
const ALLOWED_CONNECT_SRC = ["'self'", 'ipc:', 'http://ipc.localhost'] as const

const here = dirname(fileURLToPath(import.meta.url))
const confPath = resolve(here, '..', 'src-tauri', 'tauri.conf.json')
const conf = JSON.parse(readFileSync(confPath, 'utf8')) as TauriConf

function cspDirective(csp: string, name: string): string | undefined {
  return csp
    .split(';')
    .map((part) => part.trim())
    .find((part) => part === name || part.startsWith(`${name} `))
}

/** connect-src 的 token 列表（不含指令名本身）。 */
function connectSrcTokens(csp: string): string[] {
  const directive = cspDirective(csp, 'connect-src')
  if (directive === undefined) {
    throw new Error('CSP 缺少 connect-src 指令')
  }
  return directive.split(/\s+/).slice(1)
}

/**
 * 断言 connect-src 恰好是白名单，多一个 token 就抛错。
 *
 * 这个函数本身也被测试：正例必须通过，每一类额外来源的合成 CSP 必须让它抛错——
 * 否则"白名单"只是一句空话。
 */
function assertConnectSrcExact(csp: string): void {
  const tokens = connectSrcTokens(csp)
  const allowed = new Set<string>(ALLOWED_CONNECT_SRC)

  const unexpected = tokens.filter((token) => !allowed.has(token))
  if (unexpected.length > 0) {
    throw new Error(`connect-src 出现未授权的 token: ${unexpected.join(', ')}`)
  }

  const missing = ALLOWED_CONNECT_SRC.filter((token) => !tokens.includes(token))
  if (missing.length > 0) {
    throw new Error(`connect-src 缺少必需的 token: ${missing.join(', ')}`)
  }

  if (tokens.length !== ALLOWED_CONNECT_SRC.length) {
    throw new Error(`connect-src token 数量为 ${tokens.length}，期望 ${ALLOWED_CONNECT_SRC.length}`)
  }
}

describe('tauri.conf.json: connect-src 白名单', () => {
  it('真实配置恰好等于允许集合', () => {
    expect(() => assertConnectSrcExact(conf.app.security.csp)).not.toThrow()
    expect(new Set(connectSrcTokens(conf.app.security.csp))).toEqual(
      new Set(ALLOWED_CONNECT_SRC),
    )
  })

  it('缺少 connect-src 指令即失败', () => {
    expect(() => assertConnectSrcExact("default-src 'self'")).toThrow(/connect-src/)
  })

  it.each([
    ['外部 https 地址', 'https://api.deepseek.com'],
    ['外部 http 地址', 'http://example.invalid'],
    ['明文 WebSocket', 'ws://localhost:5173'],
    ['加密 WebSocket', 'wss://example.invalid'],
    ['data: 协议', 'data:'],
    ['blob: 协议', 'blob:'],
    ['filesystem: 协议', 'filesystem:'],
    ['自定义协议', 'engm:'],
    ['通配符', '*'],
    ['unsafe-inline', "'unsafe-inline'"],
  ])('%s 必须让白名单断言失败', (_label, extraToken) => {
    const broken = `default-src 'self'; connect-src ${ALLOWED_CONNECT_SRC.join(' ')} ${extraToken}`
    expect(() => assertConnectSrcExact(broken)).toThrow(/未授权的 token/)
  })

  it.each([
    ['移除 ipc:', "'self' http://ipc.localhost"],
    ['移除 self', 'ipc: http://ipc.localhost'],
  ])('%s 也必须失败（不接受被削弱的白名单）', (_label, connectSrc) => {
    expect(() => assertConnectSrcExact(`connect-src ${connectSrc}`)).toThrow(/缺少必需的 token/)
  })
})

describe('tauri.conf.json: 其他边界', () => {
  it('不使用 unsafe-eval', () => {
    expect(conf.app.security.csp).not.toContain('unsafe-eval')
  })

  it('script-src 不允许内联脚本', () => {
    const scriptSrc = cspDirective(conf.app.security.csp, 'script-src')
    expect(scriptSrc).toBe("script-src 'self'")
  })

  it('骨架阶段不启用打包：安装包与签名属于 T050', () => {
    expect(conf.bundle.active).toBe(false)
  })

  it('identifier 与 Rust 侧断言保持一致', () => {
    expect(conf.identifier).toBe('com.engmentor.desktop')
  })
})
