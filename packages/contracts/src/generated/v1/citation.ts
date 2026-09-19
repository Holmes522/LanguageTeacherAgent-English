// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 生成自 citation.schema.json，根类型 Citation

/**
 * 引用来源元数据（SPEC-M00 §5.2）。刻意与词典/知识源供应商无关（Q1）：不出现任何厂商专有字段名，Oxford 与开放许可词典走同一结构。sourceVersion 为必填：来源确实没有版本时，必须显式写 "unversioned" 一类占位值，而不是省略字段——省略会让"没有版本"和"忘了填"无法区分。
 */
export interface Citation {
  /**
   * 来源的人类可读名称，例如某个开放许可词典或用户自己的文档名。
   */
  sourceName: string
  /**
   * 来源版本；无版本时写显式占位值，不得省略。
   */
  sourceVersion: string
  /**
   * 可定位坐标：页码/段落/条目 id 等。用户必须能据此回到原文核对。
   */
  sourceLocator: string
  /**
   * 许可标识。未获书面离线授权的来源不得声称可离线索引（Q1 红线）。
   */
  licenseLabel: string
}
