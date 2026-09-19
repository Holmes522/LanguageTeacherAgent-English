/**
 * 应用元信息的单一来源（骨架阶段）。
 *
 * 产品名与阶段在这里集中定义，避免散落在组件里；阶段值必须如实反映
 * PROJECT_STATUS.md 的状态，不得为了界面好看而提前宣称可用。
 */
export interface AppInfo {
  readonly productName: string
  readonly stage: string
}

export function appInfo(): AppInfo {
  return {
    productName: 'EngMentor（英师）',
    stage: 'Pre-alpha · 工程骨架',
  }
}
