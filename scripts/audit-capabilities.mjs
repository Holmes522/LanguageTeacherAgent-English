#!/usr/bin/env node
/**
 * Tauri capability 授权清单审计（SPEC-M00 §5.4 第 3 层、AC-9 第 3 层）。
 *
 * 第 3 层防线的内容是"不授予 WebView 任何 HTTP/shell/通配 fs 权限"。它由三处共同决定，
 * 因此三处都要检查——只查 capability 文件会漏掉"通过加依赖把能力装进来"这条路径：
 *   1. src-tauri/capabilities/*.json 的 permissions 必须在白名单内；
 *   2. Cargo.toml 不得引入 tauri-plugin-http / tauri-plugin-shell 等特权插件；
 *   3. 前端 package.json 不得引入对应的 @tauri-apps/plugin-* 包。
 *
 * 白名单本身是刻意写死的：新增任何权限都必须先改 SPEC-M00 §5.4 并在这里登记，
 * 而不是在 capability 文件里加一行就悄悄生效。
 *
 * 退出码：0 与白名单一致；1 出现白名单外的权限或特权依赖。
 */

import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const capabilitiesDir = join(repoRoot, 'apps', 'desktop', 'src-tauri', 'capabilities')
const cargoTomlPath = join(repoRoot, 'apps', 'desktop', 'src-tauri', 'Cargo.toml')
const desktopPackageJsonPath = join(repoRoot, 'apps', 'desktop', 'package.json')

/** 允许出现在 capability 文件里的权限，且仅限这些。 */
const ALLOWED_PERMISSIONS = ['core:default']

/** 明确禁止的插件前缀：命中即失败，并在错误里点出对应的插件名。 */
const FORBIDDEN_PERMISSION_PREFIXES = ['http', 'shell', 'fs', 'process', 'dialog', 'upload', 'os']

/** 禁止出现在 Cargo.toml 的 Rust 侧特权插件 crate。 */
const FORBIDDEN_CARGO_CRATES = ['tauri-plugin-http', 'tauri-plugin-shell', 'tauri-plugin-fs']

const problems = []

function permissionNames(raw) {
  // 权限项可以是字符串，也可以是 { identifier, ... } 对象。
  if (typeof raw === 'string') {
    return [raw]
  }
  if (raw !== null && typeof raw === 'object' && typeof raw.identifier === 'string') {
    return [raw.identifier]
  }
  return []
}

// --- 1. capability 文件 --------------------------------------------------------
if (!existsSync(capabilitiesDir)) {
  problems.push('缺少 apps/desktop/src-tauri/capabilities/ 目录')
} else {
  const files = readdirSync(capabilitiesDir).filter((name) => name.endsWith('.json'))
  if (files.length === 0) {
    problems.push('capabilities/ 下没有任何 .json 文件')
  }

  console.log('[check:capabilities] 已授权的权限:')
  for (const file of files) {
    const relative = `apps/desktop/src-tauri/capabilities/${file}`
    let parsed
    try {
      parsed = JSON.parse(readFileSync(join(capabilitiesDir, file), 'utf8'))
    } catch (error) {
      problems.push(`${relative} 不是合法 JSON：${error.message}`)
      continue
    }

    const permissions = Array.isArray(parsed.permissions) ? parsed.permissions : []
    if (permissions.length === 0) {
      problems.push(`${relative} 的 permissions 为空或不是数组`)
    }
    for (const raw of permissions) {
      for (const name of permissionNames(raw)) {
        console.log(`  ${relative}  ->  ${name}`)
        if (!ALLOWED_PERMISSIONS.includes(name)) {
          problems.push(`${relative} 出现白名单外的权限：${name}`)
        }
        const prefix = name.split(':')[0]
        if (FORBIDDEN_PERMISSION_PREFIXES.includes(prefix)) {
          problems.push(`${relative} 授予了被禁止的 ${prefix} 类权限：${name}`)
        }
      }
    }

    const windows = Array.isArray(parsed.windows) ? parsed.windows : []
    if (windows.length === 0) {
      problems.push(`${relative} 未限定 windows，等于对所有窗口生效`)
    }
  }
}

// --- 2. Rust 侧特权插件 --------------------------------------------------------
if (!existsSync(cargoTomlPath)) {
  problems.push('缺少 apps/desktop/src-tauri/Cargo.toml')
} else {
  const cargoToml = readFileSync(cargoTomlPath, 'utf8')
  for (const crate of FORBIDDEN_CARGO_CRATES) {
    if (new RegExp(`^\\s*${crate}\\s*=`, 'm').test(cargoToml)) {
      problems.push(`Cargo.toml 引入了特权插件 ${crate}`)
    }
  }
}

// --- 3. 前端特权插件 ----------------------------------------------------------
if (!existsSync(desktopPackageJsonPath)) {
  problems.push('缺少 apps/desktop/package.json')
} else {
  const desktopPackage = JSON.parse(readFileSync(desktopPackageJsonPath, 'utf8'))
  const declared = Object.keys({
    ...(desktopPackage.dependencies ?? {}),
    ...(desktopPackage.devDependencies ?? {}),
  })
  for (const name of declared) {
    if (/^@tauri-apps\/plugin-(http|shell|fs|process|dialog|upload|os)$/.test(name)) {
      problems.push(`apps/desktop/package.json 引入了特权插件 ${name}`)
    }
  }
}

console.log('')
if (problems.length > 0) {
  console.error('[check:capabilities] FAILED —— 能力清单与 SPEC-M00 §5.4 白名单不符:')
  for (const problem of problems) {
    console.error(`  - ${problem}`)
  }
  console.error('')
  console.error('  新增权限或插件必须先修订 SPEC-M00 §5.4，再同步本脚本的白名单；')
  console.error('  不要把本脚本的白名单当作"改一行就能放行"的开关。')
  process.exit(1)
}

console.log(`[check:capabilities] OK —— 权限恰好是白名单 ${ALLOWED_PERMISSIONS.join(', ')}，`)
console.log('  未引入 HTTP / shell / 通配 fs 能力，且 capability 已限定到具体窗口。')
