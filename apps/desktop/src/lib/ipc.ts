/**
 * WebView → Rust 的 IPC 封装（SPEC-M00 §5.1 / B-6）。
 *
 * 每个命令都收发**统一信封**：调用方构造 `{ok:true, requestId, data, citations}`，
 * 主进程回同一个形状。这样前端只需要一条错误处理路径，不需要区分
 * "Tauri 自己 reject 了" 与 "业务返回了失败" 两种形态。
 *
 * 类型来自 `@engm/contracts`（B-5：契约包是信封与错误码的唯一来源），
 * 这里不手写第二份信封定义。
 */

import { invoke } from '@tauri-apps/api/core'
import type { LocalResponseFailure, LocalResponseOf } from '@engm/contracts'

/** 主进程内部故障。与 Rust 侧 `CODE_INTERNAL_UNEXPECTED` 逐字一致。 */
const CODE_INTERNAL_UNEXPECTED = 'ENGM.INTERNAL.UNEXPECTED'

/**
 * 生成 requestId。用 `getRandomValues` 而不是 `randomUUID`：
 * 后者只在安全上下文可用，而 IPC 不该因为加载来源变化就整个失效。
 */
export function newRequestId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')
}

/**
 * 结构校验主进程的响应。
 *
 * 这是**防御性的第二道检查**，不是不信任主进程：契约要求 Rust 出站前自校验，
 * 而前端如果直接把 `unknown` 当成信封用，一旦哪天出站校验被绕过或改错，
 * 界面会以"字段莫名 undefined"的形式坏掉，而不是给出可理解的错误。
 */
export function isEnvelope(value: unknown): value is LocalResponseOf<unknown> {
  if (typeof value !== 'object' || value === null) return false
  const candidate = value as Record<string, unknown>
  if (typeof candidate.requestId !== 'string' || candidate.requestId.length === 0) return false

  if (candidate.ok === true) {
    return 'data' in candidate && Array.isArray(candidate.citations)
  }
  if (candidate.ok === false) {
    const error = candidate.error
    if (typeof error !== 'object' || error === null) return false
    const failure = error as Record<string, unknown>
    return typeof failure.code === 'string' && typeof failure.message === 'string'
  }
  return false
}

function internalFailure(requestId: string, message: string): LocalResponseFailure {
  return {
    ok: false,
    requestId,
    error: { code: CODE_INTERNAL_UNEXPECTED, message, retryable: false },
  }
}

function describe(cause: unknown): string {
  if (cause instanceof Error) return cause.message
  if (typeof cause === 'string') return cause
  return '未知错误'
}

/**
 * 调用一个 Tauri 命令，永远返回信封 —— 不抛异常。
 *
 * 之所以不抛：抛出去会让每个调用点都要写 try/catch，而失败信息又得重新包装成
 * 信封才能显示，等于把同一件事做两遍。主进程侧同样是"命令永不返回 Err"。
 *
 * `extra` 用于流式命令需要额外传的 `channel` 参数。注意它会被并进同一个参数对象，
 * 因此不要用它传业务数据 —— 业务数据一律走 `data`。
 */
export async function callCommand<T>(
  command: string,
  data: unknown = null,
  extra: Record<string, unknown> = {},
): Promise<LocalResponseOf<T>> {
  const requestId = newRequestId()
  const request = { ok: true, requestId, data, citations: [] }

  let raw: unknown
  try {
    raw = await invoke(command, { request, ...extra })
  } catch (cause) {
    // 走到这里说明命令根本没被执行（未注册、参数序列化失败、主进程 panic）。
    // 这属于工程故障，不属于业务失败，因此用 INTERNAL 码。
    return internalFailure(requestId, `调用 ${command} 失败：${describe(cause)}`)
  }

  if (!isEnvelope(raw)) {
    return internalFailure(requestId, `命令 ${command} 返回了不符合契约的响应`)
  }
  return raw as LocalResponseOf<T>
}
