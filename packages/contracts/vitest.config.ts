import { defineConfig } from 'vitest/config'

// 契约包的测试是纯数据校验（读 schema 与 fixtures 文件），不需要 DOM 环境。
export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    passWithNoTests: false,
  },
})
