import { readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

/**
 * tauri.conf.json 的安全与范围边界断言。
 *
 * 这些是 SPEC-M00 §5.4（WebView 无外网三层防护的第 2 层）与 §2（非目标）里的约束，
 * 放在测试里是为了让"改配置就悄悄放开外网"或"提前开启打包"这类改动会直接失败，
 * 而不是等到评审时靠人眼发现。
 */
interface TauriConf {
  identifier: string
  app: { security: { csp: string } }
  bundle: { active: boolean }
}

const here = dirname(fileURLToPath(import.meta.url))
const confPath = resolve(here, '..', 'src-tauri', 'tauri.conf.json')
const conf = JSON.parse(readFileSync(confPath, 'utf8')) as TauriConf

function cspDirective(name: string): string | undefined {
  return conf.app.security.csp
    .split(';')
    .map((part) => part.trim())
    .find((part) => part === name || part.startsWith(`${name} `))
}

describe('tauri.conf.json 边界', () => {
  it('connect-src 只允许自身与 Tauri IPC，不含任何外部来源', () => {
    const connectSrc = cspDirective('connect-src')
    expect(connectSrc).toBeDefined()

    const tokens = (connectSrc ?? '').split(/\s+/).slice(1)
    const external = tokens.filter(
      (token) => /^https?:\/\//.test(token) && !token.startsWith('http://ipc.localhost'),
    )

    expect(external).toEqual([])
  })

  it('不使用 unsafe-eval', () => {
    expect(conf.app.security.csp).not.toContain('unsafe-eval')
  })

  it('骨架阶段不启用打包：安装包与签名属于 T050', () => {
    expect(conf.bundle.active).toBe(false)
  })

  it('identifier 与 Rust 侧断言保持一致', () => {
    expect(conf.identifier).toBe('com.engmentor.desktop')
  })
})
