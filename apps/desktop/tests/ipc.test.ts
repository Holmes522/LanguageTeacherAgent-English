import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * `lib/ipc.ts` 的信封契约行为。
 *
 * 这里断言的是"前端如何处理各种响应形状"，尤其是两类会被忽略的失败：
 * 命令根本没执行（invoke 抛异常）与主进程返回了不合契约的东西。
 * 两者都必须变成**合法信封**，否则界面会以未捕获的 promise 结束，
 * 用户看到的是一次静默无反应。
 */

const invoke = vi.fn()

vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}))

const { callCommand, isEnvelope, newRequestId } = await import('../src/lib/ipc')

const VALID_SUCCESS = {
  ok: true,
  requestId: 'req-1',
  data: { hello: 'world' },
  citations: [],
}

describe('newRequestId', () => {
  it('产出 32 位十六进制，且落在契约的 128 字符上限内', () => {
    const id = newRequestId()
    expect(id).toMatch(/^[0-9a-f]{32}$/)
    expect(id.length).toBeLessThanOrEqual(128)
  })

  it('每次调用都不同（requestId 的用途是与日志配对，重复就失去意义）', () => {
    const ids = new Set(Array.from({ length: 50 }, () => newRequestId()))
    expect(ids.size).toBe(50)
  })
})

describe('isEnvelope', () => {
  it('接受真实的成功与失败信封', () => {
    expect(isEnvelope(VALID_SUCCESS)).toBe(true)
    expect(
      isEnvelope({
        ok: false,
        requestId: 'req-1',
        error: { code: 'ENGM.INTERNAL.UNEXPECTED', message: 'x', retryable: false },
      }),
    ).toBe(true)
  })

  it.each([
    ['null', null],
    ['字符串', 'ok'],
    ['数组', []],
    ['缺 requestId', { ok: true, data: null, citations: [] }],
    ['requestId 为空串', { ok: true, requestId: '', data: null, citations: [] }],
    ['ok 不是布尔', { ok: 'yes', requestId: 'r', data: null, citations: [] }],
    ['成功但缺 citations', { ok: true, requestId: 'r', data: null }],
    ['成功但缺 data', { ok: true, requestId: 'r', citations: [] }],
    ['失败但缺 error', { ok: false, requestId: 'r' }],
    ['失败且 error 缺 code', { ok: false, requestId: 'r', error: { message: 'x' } }],
  ])('拒绝 %s', (_label, value) => {
    expect(isEnvelope(value)).toBe(false)
  })
})

describe('callCommand', () => {
  beforeEach(() => {
    invoke.mockReset()
  })

  it('构造合法请求信封并把成功响应原样返回', async () => {
    invoke.mockResolvedValue(VALID_SUCCESS)

    const response = await callCommand<{ hello: string }>('settings_read', {})

    expect(invoke).toHaveBeenCalledTimes(1)
    const [command, args] = invoke.mock.calls[0] as [string, { request: unknown }]
    expect(command).toBe('settings_read')

    const request = args.request as Record<string, unknown>
    expect(request.ok).toBe(true)
    expect(request.citations).toEqual([])
    expect(typeof request.requestId).toBe('string')
    expect(isEnvelope(request)).toBe(true)

    expect(response.ok).toBe(true)
  })

  it('invoke 抛异常时返回信封而不是抛出（命令未注册/主进程故障）', async () => {
    invoke.mockRejectedValue(new Error('command not found'))

    const response = await callCommand('nope', {})

    expect(response.ok).toBe(false)
    if (response.ok) throw new Error('unreachable')
    expect(response.error.code).toBe('ENGM.INTERNAL.UNEXPECTED')
    expect(response.error.message).toContain('nope')
    expect(response.error.retryable).toBe(false)
    // 失败信封本身必须合法，否则它自己就会在下一层被拒。
    expect(isEnvelope(response)).toBe(true)
  })

  it('主进程返回非信封内容时也返回信封', async () => {
    invoke.mockResolvedValue({ unexpected: true })

    const response = await callCommand('settings_read', {})

    expect(response.ok).toBe(false)
    if (response.ok) throw new Error('unreachable')
    expect(response.error.code).toBe('ENGM.INTERNAL.UNEXPECTED')
    expect(isEnvelope(response)).toBe(true)
  })

  it('失败信封会回传主进程给出的错误码，不做改写', async () => {
    invoke.mockResolvedValue({
      ok: false,
      requestId: 'req-9',
      error: { code: 'ENGM.CONTRACT.INVALID_INPUT', message: 'API Key 不能为空', retryable: false },
    })

    const response = await callCommand('credential_set', { apiKey: '' })

    expect(response.ok).toBe(false)
    if (response.ok) throw new Error('unreachable')
    expect(response.error.code).toBe('ENGM.CONTRACT.INVALID_INPUT')
    expect(response.error.message).toBe('API Key 不能为空')
  })
})
