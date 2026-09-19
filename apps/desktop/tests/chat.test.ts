import { beforeEach, describe, expect, it, vi } from 'vitest'

/**
 * `lib/chat.ts` 的流式行为。
 *
 * 重点在两处容易出错的地方：
 *   1. **失败只报一次**。流里的失败帧与命令返回值的失败是同一件事（返回值就是最后一帧），
 *      不去重的话界面会弹两条一样的错误。
 *   2. **终局一定会到**。无论走哪条路径，`onDone` 或 `onFailure` 必须恰好触发一次 ——
 *      否则界面会永远停在"生成中"，用户只能猜。
 */

const { invoke, channels } = vi.hoisted(() => ({
  invoke: vi.fn(),
  channels: [] as Array<{ onmessage: ((message: unknown) => void) | null }>,
}))

vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => invoke(...args),
  Channel: class {
    onmessage: ((message: unknown) => void) | null = null
    constructor() {
      channels.push(this)
    }
  },
}))

const { parseChatStreamEvent, parseSidecarHealth, streamChat } = await import('../src/lib/chat')

function successFrame(data: unknown) {
  return { ok: true, requestId: 'req-test', data, citations: [] }
}

function failureFrame(code: string, message: string) {
  return { ok: false, requestId: 'req-test', error: { code, message, retryable: false } }
}

/** 让 invoke 先把给定帧推给刚刚创建的 Channel，再返回给定的终局信封。 */
function respondWith(frames: unknown[], terminal: unknown) {
  invoke.mockImplementation(async () => {
    const channel = channels[channels.length - 1]
    for (const frame of frames) {
      channel?.onmessage?.(frame)
    }
    return terminal
  })
}

function collector() {
  const deltas: string[] = []
  const failures: Array<{ message: string; code: string }> = []
  let doneCount = 0
  return {
    deltas,
    failures,
    get doneCount() {
      return doneCount
    },
    handlers: {
      onDelta: (text: string) => deltas.push(text),
      onDone: () => {
        doneCount += 1
      },
      onFailure: (message: string, code: string) => failures.push({ message, code }),
    },
  }
}

describe('parseChatStreamEvent', () => {
  it('接受 delta 与 done', () => {
    expect(parseChatStreamEvent({ type: 'delta', text: 'hi' })).toEqual({ type: 'delta', text: 'hi' })
    expect(parseChatStreamEvent({ type: 'done' })).toEqual({ type: 'done' })
  })

  it.each([
    ['null', null],
    ['字符串', 'delta'],
    ['缺 type', { text: 'hi' }],
    ['未知 type', { type: 'thinking' }],
    ['delta 缺 text', { type: 'delta' }],
    ['delta 的 text 不是字符串', { type: 'delta', text: 1 }],
  ])('拒绝 %s', (_label, value) => {
    expect(parseChatStreamEvent(value)).toBeNull()
  })
})

describe('parseSidecarHealth', () => {
  const VALID = {
    package: 'engm-ai-core',
    version: '0.0.0',
    stage: 'pre-alpha',
    capabilities: [],
    contractVersion: 'v1',
    modelConfigured: true,
  }

  it('接受合法的健康信息', () => {
    expect(parseSidecarHealth(VALID)).toEqual(VALID)
  })

  it('缺少关键字段时拒绝', () => {
    expect(parseSidecarHealth({ ...VALID, contractVersion: undefined })).toBeNull()
    expect(parseSidecarHealth({ ...VALID, modelConfigured: 'yes' })).toBeNull()
    expect(parseSidecarHealth(null)).toBeNull()
  })
})

describe('streamChat', () => {
  beforeEach(() => {
    invoke.mockReset()
    channels.length = 0
  })

  it('按顺序累积增量，并在 done 时恰好结束一次', async () => {
    respondWith(
      [
        successFrame({ type: 'delta', text: 'Hel' }),
        successFrame({ type: 'delta', text: 'lo' }),
        successFrame({ type: 'done' }),
      ],
      successFrame({ type: 'done' }),
    )
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.deltas.join('')).toBe('Hello')
    expect(sink.doneCount).toBe(1)
    expect(sink.failures).toEqual([])
  })

  it('把用户消息原样放进请求数据里', async () => {
    respondWith([successFrame({ type: 'done' })], successFrame({ type: 'done' }))
    const sink = collector()

    await streamChat(
      [
        { role: 'user', content: '第一句' },
        { role: 'assistant', content: '回答' },
        { role: 'user', content: '第二句' },
      ],
      sink.handlers,
    )

    const [command, args] = invoke.mock.calls[0] as [string, { request: { data: unknown } }]
    expect(command).toBe('chat_stream')
    expect(args.request.data).toEqual({
      messages: [
        { role: 'user', content: '第一句' },
        { role: 'assistant', content: '回答' },
        { role: 'user', content: '第二句' },
      ],
    })
  })

  it('流里的失败帧只报一次，命令返回值的同一个失败不再重复报', async () => {
    respondWith(
      [failureFrame('ENGM.INTERNAL.UNEXPECTED', '上游 401')],
      failureFrame('ENGM.INTERNAL.UNEXPECTED', '上游 401'),
    )
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.failures).toHaveLength(1)
    expect(sink.failures[0]?.message).toBe('上游 401')
    expect(sink.doneCount).toBe(0)
  })

  it('流里没有终局帧时，命令返回也足以让界面离开生成中', async () => {
    respondWith([successFrame({ type: 'delta', text: 'partial' })], successFrame({ type: 'done' }))
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.deltas.join('')).toBe('partial')
    expect(sink.doneCount).toBe(1)
  })

  it('不符合契约的流式帧被当作失败，而不是被静默忽略', async () => {
    respondWith([{ unexpected: true }], successFrame({ type: 'done' }))
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.failures).toHaveLength(1)
    expect(sink.failures[0]?.code).toBe('ENGM.INTERNAL.UNEXPECTED')
  })

  it('无法识别的事件类型也报失败（而不是把界面留在生成中）', async () => {
    respondWith([successFrame({ type: 'thinking' })], successFrame({ type: 'thinking' }))
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.failures).toHaveLength(1)
    expect(sink.doneCount).toBe(0)
  })

  it('命令本身失败（invoke 抛异常）时也走同一条失败路径', async () => {
    invoke.mockRejectedValue(new Error('command not found'))
    const sink = collector()

    await streamChat([{ role: 'user', content: 'hi' }], sink.handlers)

    expect(sink.failures).toHaveLength(1)
    expect(sink.failures[0]?.code).toBe('ENGM.INTERNAL.UNEXPECTED')
  })
})
