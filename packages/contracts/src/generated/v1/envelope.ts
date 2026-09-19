// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 生成自 envelope.schema.json，根类型 LocalResponse

/**
 * 所有边界上的统一响应信封（SPEC-M00 §5.2 / B-6）。成功与失败两种形态由 ok 判别：成功必须带 data、不得带 error；失败必须带 error、不得带 data。刻意不使用跨文件 $ref —— 三个校验器（TS/Python/Rust）都只编译单份文档，避免多文档引用解析差异成为三方不一致的来源；$defs 中 error 与 citation 的形状与 error.schema.json、citation.schema.json 行为等价，由 packages/contracts/tests/fixtures 的共享正反例同时压两份文档来保证。
 */
export type LocalResponse = LocalResponseSuccess | LocalResponseFailure

/**
 * 成功形态。data 的业务结构在 M00 不受约束（§5.2 不定义业务命令字段），因此这里是布尔 schema true：任何 JSON 值都合法，具体形状由各模块的 schema 追加。
 */
export interface LocalResponseSuccess {
  ok: true
  /**
   * 请求标识，用于日志与故障定位配对。空字符串等同于缺失。
   */
  requestId: string
  data: unknown
  /**
   * 该回答依据的来源列表。没有依据时必须是空数组，而不是省略字段——省略会让"无来源"和"忘了带"无法区分。
   */
  citations: LocalResponseCitation[]
  usage?: LocalResponseUsage
}
export interface LocalResponseCitation {
  sourceName: string
  sourceVersion: string
  sourceLocator: string
  licenseLabel: string
}
export interface LocalResponseUsage {
  inputTokens: number
  outputTokens: number
  cached: boolean
}
export interface LocalResponseFailure {
  ok: false
  requestId: string
  error: LocalResponseError
}
export interface LocalResponseError {
  code:
    | 'ENGM.CONTRACT.INVALID_INPUT'
    | 'ENGM.CONTRACT.SCHEMA_INVALID'
    | 'ENGM.CONTRACT.VERSION_MISMATCH'
    | 'ENGM.INTERNAL.UNEXPECTED'
  message: string
  retryable: boolean
  details?: unknown
}
