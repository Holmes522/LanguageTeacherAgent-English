/**
 * @engm/contracts —— 契约包的公开入口。
 *
 * 生成物（`src/generated/`）不得手工编辑；它们是 `packages/contracts/scripts/generate.mjs`
 * 的产物，漂移由 `pnpm contracts:check` 检出。
 *
 * 这里只做两件事：再导出生成物，以及补一个纯派生的 TS 泛型别名。
 * **不在这里手写任何契约定义**——那会构成 B-5 禁止的第二份契约来源。
 */

export * from './generated/v1'

import type { LocalResponseFailure, LocalResponseSuccess } from './generated/v1/envelope'

/**
 * `LocalResponse<T>` 的 TypeScript 表达（SPEC-M00 §5.2）。
 *
 * 为什么需要这一行：JSON Schema 无法可移植地表达泛型，所以生成器只能把 `data` 生成为
 * `unknown`。这个别名把 `data` 收窄为调用方指定的 T，其余部分完全来自生成物（`Omit` + 交叉类型，
 * 没有任何独立定义）。失败形态不需要泛型参数：失败时没有业务负载。
 */
export type LocalResponseOf<T> =
  | (Omit<LocalResponseSuccess, 'data'> & { readonly data: T })
  | LocalResponseFailure
