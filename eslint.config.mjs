// ESLint 扁平配置（仓库根）。
//
// 这里承担 SPEC-M00 §5.4 的**第 1 层防护**：WebView 代码不得直接发起外部网络请求。
// 第 2 层是 tauri.conf.json 的 CSP，第 3 层是 Tauri capability 不授予 HTTP 权限；
// 三层各自独立，任一层失效也不放开外网。
//
// 规则只加在 WebView 与契约包源码上：脚本与配置属于开发期工具，不在此约束内。

import js from '@eslint/js'
import tseslint from 'typescript-eslint'

const networkApis = [
  {
    name: 'fetch',
    message: 'WebView 不得直接访问外网（SPEC-M00 §5.4）。请改为经 Tauri command 走 Rust 主进程。',
  },
  {
    name: 'XMLHttpRequest',
    message: 'WebView 不得直接访问外网（SPEC-M00 §5.4）。请改为经 Tauri command 走 Rust 主进程。',
  },
  {
    name: 'WebSocket',
    message: 'WebView 不得直接访问外网（SPEC-M00 §5.4）。请改为经 Tauri command 走 Rust 主进程。',
  },
  {
    name: 'EventSource',
    message: 'WebView 不得直接访问外网（SPEC-M00 §5.4）。请改为经 Tauri command 走 Rust 主进程。',
  },
]

export default tseslint.config(
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/target/**',
      '**/.venv/**',
      '**/src-tauri/gen/**',
      '**/__pycache__/**',
      'tmp/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['apps/desktop/src/**/*.{ts,tsx}', 'apps/desktop/tests/**/*.ts'],
    rules: {
      'no-restricted-globals': ['error', ...networkApis],
    },
  },
  {
    files: ['packages/contracts/src/**/*.ts'],
    rules: {
      'no-restricted-globals': ['error', ...networkApis],
    },
  },
  {
    // 开发期脚本与配置文件运行在 Node 上。这里只声明实际用到的 Node 全局量，
    // 而不是引入 globals 包 —— 少一个依赖，也避免把整个 Node 全局面暴露给 lint。
    files: [
      'scripts/**/*.mjs',
      'packages/contracts/**/*.mjs',
      'eslint.config.mjs',
      'apps/desktop/*.config.ts',
    ],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        URL: 'readonly',
        Buffer: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
      },
    },
  },
)
