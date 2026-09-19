/**
 * 设置与凭据的前端接口。
 *
 * `SettingsSnapshot` 是 `settings_read` 的 `data` 形状。它目前**手写在两处**
 * （这里与 Rust 的 `commands::settings_snapshot`），原因是 SPEC-M00 §5.2 明确
 * M00 不定义业务命令字段，而 M02/M03 的 Spec 尚未落地。这是已知的临时重复，
 * 已登记在 PROJECT_STATUS.md，到期条件：M02 设置模块的 Spec 落地时，
 * 把快照形状写进 `packages/contracts/schema/v1/` 并由生成链路产出两侧类型。
 *
 * 注意到一件事：这个形状里**没有密钥字段，也不会有**。密钥只以"是否已配置"
 * 的布尔值出现在界面上（SPEC-M00 §9.2）。
 */

import type { LocalResponseOf } from '@engm/contracts'
import { callCommand } from './ipc'

export interface SettingsSnapshot {
  /** Q5：用户明确同意后才允许把最小内容发往云端模型。 */
  readonly cloudConsentGranted: boolean
  readonly model: string
  readonly baseUrl: string
  /** 是否已在 OS 凭据存储里存有 DeepSeek 密钥。**不是密钥本身**。 */
  readonly credentialConfigured: boolean
}

/** 要写入的非敏感设置。缺省字段保持原值。 */
export interface SettingsPatch {
  readonly cloudConsentGranted?: boolean
  readonly model?: string
  readonly baseUrl?: string
}

/** 快照允许出现的键，一个不多。 */
const SNAPSHOT_KEYS = [
  'cloudConsentGranted',
  'model',
  'baseUrl',
  'credentialConfigured',
] as const

/**
 * 运行期校验主进程给出的快照，避免把不合形状的对象当成设置用。
 *
 * **多出来的键会被整体拒绝，而不是忽略。** 这是一条防线而不是洁癖：如果哪天主进程
 * 改动让快照里带上了密钥字段，忽略未知键会让它照常渲染进 DOM、进而进入截图与
 * WebView 状态；拒绝则会让界面明确报错。宁可界面上出一次错，也不要静默泄漏。
 */
export function parseSettingsSnapshot(value: unknown): SettingsSnapshot | null {
  if (typeof value !== 'object' || value === null) return null
  const candidate = value as Record<string, unknown>

  const allowed = new Set<string>(SNAPSHOT_KEYS)
  if (Object.keys(candidate).some((key) => !allowed.has(key))) return null

  if (
    typeof candidate.cloudConsentGranted !== 'boolean' ||
    typeof candidate.model !== 'string' ||
    typeof candidate.baseUrl !== 'string' ||
    typeof candidate.credentialConfigured !== 'boolean'
  ) {
    return null
  }
  return {
    cloudConsentGranted: candidate.cloudConsentGranted,
    model: candidate.model,
    baseUrl: candidate.baseUrl,
    credentialConfigured: candidate.credentialConfigured,
  }
}

export async function readSettings(): Promise<LocalResponseOf<SettingsSnapshot>> {
  return callCommand<SettingsSnapshot>('settings_read', {})
}

export async function writeSettings(patch: SettingsPatch): Promise<LocalResponseOf<SettingsSnapshot>> {
  return callCommand<SettingsSnapshot>('settings_write', patch)
}

/**
 * 保存 DeepSeek 密钥。
 *
 * 密钥**只往主进程方向走**：它进入 OS 凭据存储，之后任何命令都不会把它读回界面。
 * 调用方在拿到成功后必须立刻清空输入框。
 */
export async function setCredential(apiKey: string): Promise<LocalResponseOf<{ credentialConfigured: boolean }>> {
  return callCommand<{ credentialConfigured: boolean }>('credential_set', { apiKey })
}

export async function clearCredential(): Promise<LocalResponseOf<{ credentialConfigured: boolean }>> {
  return callCommand<{ credentialConfigured: boolean }>('credential_clear', {})
}
