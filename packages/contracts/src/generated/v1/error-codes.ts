// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 错误码联合类型，来源 error-codes.json（注册表是错误码的唯一来源）

/** 已注册的契约错误码（ENGM.<DOMAIN>.<REASON>）。 */
export type ErrorCode = 'ENGM.CONTRACT.INVALID_INPUT' | 'ENGM.CONTRACT.SCHEMA_INVALID' | 'ENGM.CONTRACT.VERSION_MISMATCH' | 'ENGM.INTERNAL.UNEXPECTED'

/** 错误码 → 是否可重试。由注册表生成，不要手写第二份。 */
export const ERROR_CODE_RETRYABLE: Readonly<Record<ErrorCode, boolean>> = {
  'ENGM.CONTRACT.INVALID_INPUT': false,
  'ENGM.CONTRACT.SCHEMA_INVALID': false,
  'ENGM.CONTRACT.VERSION_MISMATCH': false,
  'ENGM.INTERNAL.UNEXPECTED': false,
}

/** 该契约版本固化并注册的全部错误码。 */
export const ERROR_CODES: readonly ErrorCode[] = ['ENGM.CONTRACT.INVALID_INPUT', 'ENGM.CONTRACT.SCHEMA_INVALID', 'ENGM.CONTRACT.VERSION_MISMATCH', 'ENGM.INTERNAL.UNEXPECTED']
