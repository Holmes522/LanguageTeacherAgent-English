import { defineConfig } from 'vitest/config'

// 骨架阶段的测试运行配置。
//
// 使用 node 环境而不是 jsdom：当前的测试都是纯逻辑与配置文件边界断言，不渲染 DOM。
// 等到真正有组件测试时再引入 DOM 环境与相应依赖（需要先在 Spec 中说明）。
export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    passWithNoTests: false,
  },
})
