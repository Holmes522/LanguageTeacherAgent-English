/**
 * 对话：把一次提问发给主进程，流式收回答（M03 最小版本）。
 *
 * 流式用 Tauri 的 `Channel` 而不是全局事件：Channel 只存在于发起这次调用的那一端，
 * 而 `emit` 出去的事件同一进程里谁都能听。要把用户正文推给界面时，
 * "只有发起方能收到"是更合适的默认。
 *
 * .. warning::
 *
 *   `ChatMessage` 与 `ChatStreamEvent` 是**临时的**：SPEC-M00 §5.2 明确 M00 不定义
 *   业务命令字段，而这些字段的归属是 M03 的 Spec。因此它们目前与
 *   `services/ai-core/src/english_teacher/sidecar/chat.py` 各写了一份等价定义 ——
 *   这是已知的临时重复，已登记在 PROJECT_STATUS.md，到期条件：M03 的 Spec 落地时
 *   写进 `packages/contracts/schema/v1/`，由生成链路产出两侧类型。
 */

import { Channel } from '@tauri-apps/api/core'
import type { LocalResponseOf } from '@engm/contracts'
import { callCommand, isEnvelope } from './ipc'

export type ChatRole = 'system' | 'user' | 'assistant'

export interface ChatMessage {
  readonly role: ChatRole
  readonly content: string
}

/** Sidecar 在流里推的事件。与 `chat.py` 的 `DeltaEvent` / `DoneEvent` 对应。 */
export type ChatStreamEvent =
  | { readonly type: 'delta'; readonly text: string }
  | { readonly type: 'done' }

/** 运行期解析流式帧的 `data` 载荷；不合形状就返回 `null`。 */
export function parseChatStreamEvent(value: unknown): ChatStreamEvent | null {
  if (typeof value !== 'object' || value === null) return null
  const candidate = value as Record<string, unknown>

  if (candidate.type === 'done') {
    return { type: 'done' }
  }
  if (candidate.type === 'delta' && typeof candidate.text === 'string') {
    return { type: 'delta', text: candidate.text }
  }
  return null
}

export interface ChatHandlers {
  onDelta(text: string): void
  onDone(): void
  onFailure(message: string, code: string): void
}

/** Sidecar 的健康状况（`sidecar_status` 的 `data` 形状）。 */
export interface SidecarHealth {
  readonly package: string
  readonly version: string
  readonly stage: string
  readonly capabilities: readonly string[]
  readonly contractVersion: string
  readonly modelConfigured: boolean
}

export function parseSidecarHealth(value: unknown): SidecarHealth | null {
  if (typeof value !== 'object' || value === null) return null
  const candidate = value as Record<string, unknown>
  if (
    typeof candidate.contractVersion !== 'string' ||
    typeof candidate.modelConfigured !== 'boolean' ||
    !Array.isArray(candidate.capabilities)
  ) {
    return null
  }
  return {
    package: String(candidate.package ?? ''),
    version: String(candidate.version ?? ''),
    stage: String(candidate.stage ?? ''),
    capabilities: candidate.capabilities.map(String),
    contractVersion: candidate.contractVersion,
    modelConfigured: candidate.modelConfigured,
  }
}

/** 拉起 Sidecar 并读一次健康检查。这是"配好了到底能不能用"的自检。 */
export async function checkSidecar(): Promise<LocalResponseOf<SidecarHealth>> {
  return callCommand<SidecarHealth>('sidecar_status', {})
}

/**
 * 发一次提问，流式收回答。
 *
 * 失败只通过 `onFailure` 报告一次：流里的失败帧与命令返回值的失败是**同一件事**
 * （命令的返回值就是最后一帧），不去重的话界面会弹两条一样的错误。
 */
export async function streamChat(
  messages: readonly ChatMessage[],
  handlers: ChatHandlers,
): Promise<void> {
  let settled = false
  const settleFailure = (message: string, code: string) => {
    if (settled) return
    settled = true
    handlers.onFailure(message, code)
  }

  const channel = new Channel<unknown>()
  channel.onmessage = (frame: unknown) => {
    if (!isEnvelope(frame)) {
      settleFailure('主进程推送了不符合契约的流式帧', 'ENGM.INTERNAL.UNEXPECTED')
      return
    }
    if (!frame.ok) {
      settleFailure(frame.error.message, frame.error.code)
      return
    }
    const event = parseChatStreamEvent(frame.data)
    if (event === null) {
      settleFailure('主进程推送了无法识别的流式事件', 'ENGM.INTERNAL.UNEXPECTED')
      return
    }
    if (event.type === 'delta') {
      handlers.onDelta(event.text)
      return
    }
    if (!settled) {
      settled = true
      handlers.onDone()
    }
  }

  const response = await callCommand<unknown>('chat_stream', { messages }, { channel })

  if (!response.ok) {
    settleFailure(response.error.message, response.error.code)
    return
  }
  // 命令返回而流里没有终局帧（例如 Sidecar 提前断开）：也要让界面离开"生成中"。
  if (!settled) {
    settled = true
    handlers.onDone()
  }
}
