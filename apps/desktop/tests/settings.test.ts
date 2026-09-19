import { describe, expect, it } from 'vitest'
import { parseSettingsSnapshot } from '../src/lib/settings'

/**
 * 设置快照的解析边界（T012）。
 *
 * 最重要的一条是"多出未知键就整体拒绝"：它保证即便主进程哪天把密钥塞进快照，
 * 界面也不会把它渲染出来。这里用一个明确的 apiKey 字段来断言这一点 ——
 * 不是假想场景，而是 §9.2 里"密钥不得进入 WebView 状态"的界面侧落点。
 */

const VALID = {
  cloudConsentGranted: false,
  model: 'deepseek-flash',
  baseUrl: 'https://api.deepseek.com',
  credentialConfigured: true,
} as const

describe('parseSettingsSnapshot', () => {
  it('接受合法快照并原样保留四个字段', () => {
    expect(parseSettingsSnapshot(VALID)).toEqual(VALID)
  })

  it('拒绝缺字段或类型不对的快照', () => {
    for (const broken of [
      { ...VALID, cloudConsentGranted: 'yes' },
      { ...VALID, model: 42 },
      { ...VALID, baseUrl: null },
      { ...VALID, credentialConfigured: 1 },
      { model: 'deepseek-flash', baseUrl: 'https://api.deepseek.com' },
      null,
      'settings',
      [],
    ]) {
      expect(parseSettingsSnapshot(broken)).toBeNull()
    }
  })

  it('快照里出现任何额外字段（尤其是密钥）就整体拒绝', () => {
    expect(parseSettingsSnapshot({ ...VALID, apiKey: 'sk-should-never-be-here' })).toBeNull()
    expect(parseSettingsSnapshot({ ...VALID, api_key: 'sk' })).toBeNull()
    expect(parseSettingsSnapshot({ ...VALID, secret: 'x' })).toBeNull()
  })

  it('解析结果里不含任何键名字面上像密钥的字段', () => {
    const parsed = parseSettingsSnapshot(VALID)
    expect(parsed).not.toBeNull()
    const keys = Object.keys(parsed ?? {})
    expect(keys.sort()).toEqual([
      'baseUrl',
      'cloudConsentGranted',
      'credentialConfigured',
      'model',
    ])
  })
})
