// ESLint 扁平配置（仓库根）。
//
// 这里承担 SPEC-M00 §5.4 的**第 1 层防护**：WebView 代码不得直接发起外部网络请求。
// 第 2 层是 tauri.conf.json 的 CSP，第 3 层是 Tauri capability 不授予 HTTP 权限。
// 三层各自独立可测；本层失效不等于外网被放开，反之亦然。
//
// 重要：ESLint 是**编译期**防线，不是安全边界。本配置能拦住的是：
//   - 裸全局标识符：`fetch(...)`、`new XMLHttpRequest()`
//   - 具名全局对象上的点属性与字面量方括号属性：`window.fetch`、`self['WebSocket']`
//     （`no-restricted-properties` 自身即覆盖 `obj["key"]`；`no-restricted-syntax` 是
//     同一条要求的第二道显式表述，任一规则被改动时另一条仍在拦截）
//   - 从这些全局对象解构：`const { fetch } = window`
//
// 拦不住的是（由第 2、3 层在运行时兜住，不要指望再加规则来堵）：
//   - 动态属性名：`window['fe' + 'tch'](...)`
//   - 先取别名再调用：`const w = window; w.fetch(...)`
//   - 任何不以 window/globalThis/self 字面量出现的中转对象
//
// 回归测试：apps/desktop/tests/lintNetworkBoundary.test.ts 会真的加载本文件并运行
// ESLint 引擎，逐类断言下面这些写法确实报错（而不是断言配置里出现了某个字符串）。

import js from '@eslint/js'
import tseslint from 'typescript-eslint'

/** WebView 不得直接触碰的网络 API。 */
const NETWORK_APIS = ['fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource']

/** 可以间接拿到上述 API 的全局对象。 */
const GLOBAL_OBJECTS = ['window', 'globalThis', 'self']

const REFER_TO_RUST =
  'WebView 不得直接访问外网（SPEC-M00 §5.4 第 1 层）。请改为经 Tauri command 走 Rust 主进程；' +
  'CSP 与 Tauri capability 是不放宽的运行时防线。'

/** 裸全局标识符：`fetch(...)`、`new XMLHttpRequest()`。 */
const restrictedGlobals = [
  'error',
  ...NETWORK_APIS.map((name) => ({
    name,
    message: `${name} 不能直接使用。${REFER_TO_RUST}`,
  })),
]

/** 点属性与字面量方括号属性：`window.fetch`、`globalThis["WebSocket"]`。 */
const restrictedProperties = [
  'error',
  ...GLOBAL_OBJECTS.flatMap((object) =>
    NETWORK_APIS.map((property) => ({
      object,
      property,
      message: `${object}.${property} 不允许使用。${REFER_TO_RUST}`,
    })),
  ),
]

/**
 * 方括号访问的显式第二道表述。
 *
 * 只匹配字面量属性名（Literal）。`no-restricted-properties` 已经覆盖同样的写法，
 * 这里保留是因为两者由不同机制实现：任何一条被改写（例如给对象加 allowProperties）
 * 时，另一条仍然拦截，且本规则的选择器在回归测试里单独可见。
 */
const restrictedComputedAccess = [
  'error',
  {
    selector:
      'MemberExpression[computed=true]' +
      '[object.name=/^(window|globalThis|self)$/]' +
      '[property.value=/^(fetch|XMLHttpRequest|WebSocket|EventSource)$/]',
    message: `通过方括号访问全局网络 API 不允许使用。${REFER_TO_RUST}`,
  },
]

const webviewNetworkRules = {
  'no-restricted-globals': restrictedGlobals,
  'no-restricted-properties': restrictedProperties,
  'no-restricted-syntax': restrictedComputedAccess,
}

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
    // 测试文件也在约束内：它们同样不该在测试里发起真实网络请求。
    files: ['apps/desktop/src/**/*.{ts,tsx}', 'apps/desktop/tests/**/*.ts'],
    rules: webviewNetworkRules,
  },
  {
    files: ['packages/contracts/src/**/*.ts'],
    rules: webviewNetworkRules,
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
