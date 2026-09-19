import { describe, expect, it } from 'vitest'
import { appInfo } from '../src/lib/appInfo'

describe('appInfo', () => {
  it('宣称的阶段必须仍然是 pre-alpha，界面不得提前宣称可用', () => {
    const info = appInfo()

    expect(info.productName).toContain('EngMentor')
    expect(info.stage.toLowerCase()).toContain('pre-alpha')
  })

  it('返回不可变快照语义：每次调用都给出相同内容', () => {
    expect(appInfo()).toEqual(appInfo())
  })
})
