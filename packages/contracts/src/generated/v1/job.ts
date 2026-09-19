// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。
// 来源：packages/contracts/schema/v1/
// 生成自 job.schema.json，根类型 Job

/**
 * 长任务状态与进度（SPEC-M00 §5.2 / B-7）。长任务先返回 jobId，进度通过事件推送；cancelRequested 表示调用方已请求取消，不代表任务已停止——真正的终态是 status 变为 cancelled。
 */
export interface Job {
  /**
   * 任务标识。同一 jobId 的重复请求必须幂等（B-7）。
   */
  jobId: string
  /**
   * 任务状态。pending/running 为进行中，succeeded/failed/cancelled 为终态。
   */
  status: 'pending' | 'running' | 'succeeded' | 'failed' | 'cancelled'
  progress: {
    /**
     * 已完成的工作单元数。
     */
    completed: number
    /**
     * 总工作单元数。0 表示总数仍未知，而不是"没有工作"。
     */
    total: number
    /**
     * 给用户看的阶段说明。不得包含用户正文。
     */
    message?: string
  }
  /**
   * 调用方是否已请求取消。
   */
  cancelRequested: boolean
}
