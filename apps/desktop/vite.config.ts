import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// 桌面壳的前端构建配置（M00 骨架）。
//
// 这里刻意不做的事：不配置任何外部 origin 到 dev server 之外、不注入代理。
// WebView 不得直接访问外网 —— 由三层防护共同约束（SPEC-M00 §5.4）：
//   1. ESLint 禁止 fetch / XMLHttpRequest / WebSocket / EventSource（eslint.config.mjs）
//   2. tauri.conf.json 的 CSP 不含外部来源
//   3. Tauri capability 不授予 HTTP 权限
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 5173,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'es2022',
    sourcemap: true,
  },
})
