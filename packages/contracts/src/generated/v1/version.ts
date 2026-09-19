// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 生成自 version.schema.json，根类型 ContractVersion

/**
 * 契约版本协商（SPEC-M00 §5.2）。Sidecar 启动时上报自身支持的契约版本与 schema 清单；主进程比对不一致时返回 ENGM.CONTRACT.VERSION_MISMATCH 并拒绝服务，而不是带着不匹配的假设继续运行（§5.3 第 5 条）。
 */
export interface ContractVersion {
  /**
   * 契约大版本，形如 v1、v1.1。字段一旦冻结只能通过新增大版本演进（§5.2）。
   */
  contractVersion: string
  /**
   * 该实现嵌入的 schema $id 集合。与 schema-manifest.json 的清单比对，防止某一侧落后于契约包（§5.3 第 6 条）。
   *
   * @minItems 1
   */
  schemaIds: [string, ...string[]]
}
