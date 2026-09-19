// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 生成自 error.schema.json，根类型 ContractError

/**
 * 统一错误对象（SPEC-M00 §5.2 / B-6）。code 必须是 error-codes.json 注册过的值：未注册但形式合法的码也会被拒绝，这是刻意设计（避免各模块随手发明错误码）。details 是任意附加信息，但不得包含用户正文。
 */
export interface ContractError {
  /**
   * 已注册的错误码。取值集合与 error-codes.json 的 codes 键完全一致。
   */
  code:
    | 'ENGM.CONTRACT.INVALID_INPUT'
    | 'ENGM.CONTRACT.SCHEMA_INVALID'
    | 'ENGM.CONTRACT.VERSION_MISMATCH'
    | 'ENGM.INTERNAL.UNEXPECTED'
  /**
   * 给人看的说明。不得回显用户正文或密钥。
   */
  message: string
  /**
   * 调用方是否可以原样重试。业务校验失败一律为 false，避免无限自修复。
   */
  retryable: boolean
  /**
   * 附加诊断信息。结构由产生方决定，但不得包含用户正文、完整提示词或凭据。
   */
  details?: {
    [k: string]: unknown
  }
}
