#!/usr/bin/env node
/**
 * 契约生成入口（SPEC-M00 §5.2 / §5.3 第 6 条 / D-2）。
 *
 * 唯一来源：packages/contracts/schema/v1/ 下的 5 个 *.schema.json 与 error-codes.json。
 * 产出（全部入库，禁止手工编辑；漂移由 pnpm contracts:check 检出）：
 *   - src/generated/v1/*.ts                  TS 类型（json-schema-to-typescript）
 *   - python/src/engm_contracts/v1/*.py      Pydantic v2 模型（datamodel-code-generator）
 *   - schema-manifest.json                   schema 清单 + SHA-256（供 Rust 断言嵌入完整性）
 *
 * 生成前先做「来源一致性」断言：如果注册表与 schema 里的错误码集合不一致，直接失败。
 * 这类不一致无法被任何单一校验器发现，只能在生成阶段拦住。
 *
 * 幂等性：输出内容不含时间戳，同样的输入必然产生同样的字节，否则 contracts:check 会永久误报漂移。
 */

import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { compile } from 'json-schema-to-typescript'

const here = dirname(fileURLToPath(import.meta.url))
const contractsRoot = resolve(here, '..')
const repoRoot = resolve(contractsRoot, '..', '..')

const schemaDir = join(contractsRoot, 'schema', 'v1')
const tsOutDir = join(contractsRoot, 'src', 'generated', 'v1')
const pyPackageRoot = join(contractsRoot, 'python', 'src', 'engm_contracts')
const pyOutDir = join(pyPackageRoot, 'v1')
const manifestPath = join(contractsRoot, 'schema-manifest.json')

const CONTRACT_VERSION = 'v1'
const SCHEMA_ID_PREFIX = `https://engmentor.local/contracts/${CONTRACT_VERSION}/`

/** 5 个 schema + 1 个注册表 = SPEC-M00 §5.2 要求的 6 个契约来源。 */
const SCHEMA_FILES = [
  'citation.schema.json',
  'envelope.schema.json',
  'error.schema.json',
  'job.schema.json',
  'version.schema.json',
]
const REGISTRY_FILE = 'error-codes.json'

/** datamodel-code-generator 与 json-schema-to-typescript 的版本都固定，升级是独立提交。 */
const DATAMODEL_CODEGEN_SPEC = 'datamodel-code-generator==0.82.0'
const PY_TARGET = '3.12'

const problems = []

function fail(message) {
  problems.push(message)
}

function readJson(file) {
  return JSON.parse(readFileSync(file, 'utf8'))
}

function banner(description) {
  return [
    '// 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。',
    `// 来源：packages/contracts/schema/${CONTRACT_VERSION}/`,
    `// ${description}`,
    '',
  ].join('\n')
}

// ---------------------------------------------------------------------------
// 1. 读取来源并做一致性断言
// ---------------------------------------------------------------------------

const actualFiles = readdirSync(schemaDir)
  .filter((name) => name.endsWith('.json'))
  .sort()
const expectedFiles = [...SCHEMA_FILES, REGISTRY_FILE].sort()
if (actualFiles.join('|') !== expectedFiles.join('|')) {
  fail(
    `schema/${CONTRACT_VERSION} 的文件集合与预期不一致。\n  预期：${expectedFiles.join(', ')}\n  实际：${actualFiles.join(', ')}\n  新增或删除契约来源必须同步更新本脚本与 SPEC-M00 §5.2。`,
  )
}

const schemas = new Map()
for (const file of SCHEMA_FILES) {
  const doc = readJson(join(schemaDir, file))
  schemas.set(file, doc)

  if (doc.$schema !== 'https://json-schema.org/draft/2020-12/schema') {
    fail(`${file}: $schema 必须是 JSON Schema 2020-12（当前：${doc.$schema}）`)
  }
  if (doc.$id !== `${SCHEMA_ID_PREFIX}${file}`) {
    fail(`${file}: $id 必须是 ${SCHEMA_ID_PREFIX}${file}（当前：${doc.$id}）`)
  }
  if (typeof doc.title !== 'string' || doc.title.length === 0) {
    fail(`${file}: 缺少 title —— 生成器用它命名根类型，缺了会产生 LocalResponse1 之类的名字`)
  }
}

const registry = readJson(join(schemaDir, REGISTRY_FILE))
const registryCodes = Object.keys(registry.codes ?? {}).sort()

/** 注册表 ↔ error.schema.json ↔ envelope.$defs.error 三处的错误码集合必须一致。 */
function codeSetOf(list, where) {
  if (!Array.isArray(list)) {
    fail(`${where}: 未找到错误码 enum 数组`)
    return []
  }
  return [...list].sort()
}

const errorEnum = codeSetOf(schemas.get('error.schema.json')?.properties?.code?.enum, 'error.schema.json#/properties/code/enum')
const envelopeErrorEnum = codeSetOf(
  schemas.get('envelope.schema.json')?.$defs?.error?.properties?.code?.enum,
  'envelope.schema.json#/$defs/error/properties/code/enum',
)

for (const [label, codes] of [
  ['error.schema.json', errorEnum],
  ['envelope.schema.json', envelopeErrorEnum],
]) {
  if (codes.join('|') !== registryCodes.join('|')) {
    fail(
      `${label} 的错误码集合与 ${REGISTRY_FILE} 不一致。\n  注册表：${registryCodes.join(', ')}\n  ${label}：${codes.join(', ')}\n  两处必须完全一致，否则会出现"注册了却校验不过"或反之。`,
    )
  }
}

/** 错误码形状必须符合 ENGM.<DOMAIN>.<REASON>。 */
for (const code of registryCodes) {
  if (!/^ENGM\.[A-Z][A-Z0-9_]*\.[A-Z][A-Z0-9_]*$/.test(code)) {
    fail(`${REGISTRY_FILE}: 错误码 ${code} 不符合 ENGM.<DOMAIN>.<REASON> 形状`)
  }
  const entry = registry.codes[code]
  if (entry.domain !== code.split('.')[1] || entry.reason !== code.split('.')[2]) {
    fail(`${REGISTRY_FILE}: ${code} 的 domain/reason 与代码本身不一致`)
  }
  if (typeof entry.retryable !== 'boolean' || typeof entry.description !== 'string') {
    fail(`${REGISTRY_FILE}: ${code} 必须带 retryable(boolean) 与 description(string)`)
  }
}

if (problems.length > 0) {
  console.error('[contracts:generate] FAILED —— 契约来源自身不一致：\n')
  for (const p of problems) console.error(`  - ${p}\n`)
  process.exit(1)
}

// ---------------------------------------------------------------------------
// 2. TypeScript 生成
// ---------------------------------------------------------------------------

rmSync(tsOutDir, { recursive: true, force: true })
mkdirSync(tsOutDir, { recursive: true })

const tsFiles = []
for (const file of SCHEMA_FILES) {
  const doc = schemas.get(file)
  const name = file.replace('.schema.json', '')
  const ts = await compile(doc, doc.title, {
    bannerComment: banner(`生成自 ${file}，根类型 ${doc.title}`),
    additionalProperties: false,
    declareExternallyReferenced: true,
    enableConstEnums: true,
    style: { semi: false, singleQuote: true },
  })
  const outFile = join(tsOutDir, `${name}.ts`)
  writeFileSync(outFile, ts.endsWith('\n') ? ts : `${ts}\n`, 'utf8')
  tsFiles.push(`${name}`)
}

/** 错误码联合类型：来源是注册表而不是 schema，因此单独生成。 */
const errorCodeUnion = [
  banner('错误码联合类型，来源 error-codes.json（注册表是错误码的唯一来源）'),
  '/** 已注册的契约错误码（ENGM.<DOMAIN>.<REASON>）。 */',
  `export type ErrorCode = ${registryCodes.map((c) => `'${c}'`).join(' | ')}`,
  '',
  '/** 错误码 → 是否可重试。由注册表生成，不要手写第二份。 */',
  'export const ERROR_CODE_RETRYABLE: Readonly<Record<ErrorCode, boolean>> = {',
  ...registryCodes.map((c) => `  '${c}': ${registry.codes[c].retryable},`),
  '}',
  '',
  '/** 该契约版本固化并注册的全部错误码。 */',
  `export const ERROR_CODES: readonly ErrorCode[] = [${registryCodes.map((c) => `'${c}'`).join(', ')}]`,
  '',
].join('\n')
writeFileSync(join(tsOutDir, 'error-codes.ts'), errorCodeUnion, 'utf8')
tsFiles.push('error-codes')

const tsIndex = [
  banner('按需再导出生成物；业务代码从 @engm/contracts 导入，不要直接引用本目录路径'),
  ...tsFiles.map((n) => `export * from './${n}'`),
  '',
].join('\n')
writeFileSync(join(tsOutDir, 'index.ts'), tsIndex, 'utf8')

// ---------------------------------------------------------------------------
// 3. Python 生成
// ---------------------------------------------------------------------------

rmSync(pyOutDir, { recursive: true, force: true })
mkdirSync(pyOutDir, { recursive: true })

for (const file of SCHEMA_FILES) {
  const name = file.replace('.schema.json', '')
  const args = [
    'tool',
    'run',
    '--from',
    DATAMODEL_CODEGEN_SPEC,
    'datamodel-codegen',
    '--input',
    join(schemaDir, file),
    '--input-file-type',
    'jsonschema',
    '--output',
    join(pyOutDir, `${name}.py`),
    '--output-model-type',
    'pydantic_v2.BaseModel',
    '--target-python-version',
    PY_TARGET,
    '--enum-field-as-literal',
    'all',
    '--use-standard-collections',
    '--use-union-operator',
    // --field-constraints + --use-annotated：产出 Annotated[..., StringConstraints(...)] 这类
    // pydantic v2 惯用注解，而不是 conint/constr 调用。
    // 原因是 mypy --strict 会拒绝把函数调用当作类型注解（"Cannot use a function call in a type
    // annotation"）；改用现代注解后生成物能通过严格检查，也就不必为生成物开豁免。
    '--field-constraints',
    '--use-annotated',
    '--use-field-description',
    '--disable-timestamp',
  ]
  const result = spawnSync('uv', args, { cwd: repoRoot, encoding: 'utf8', shell: false })
  if (result.status !== 0) {
    console.error(`[contracts:generate] FAILED —— ${file} 的 Python 生成失败：`)
    console.error(result.stdout ?? '')
    console.error(result.stderr ?? '')
    process.exit(1)
  }
  // 生成器在文件头写了它自己的来源注释；把我们的横幅补在最前面，便于一眼看出是生成物。
  const outFile = join(pyOutDir, `${name}.py`)
  const body = readFileSync(outFile, 'utf8')
  writeFileSync(
    outFile,
    [
      '# 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。',
      `# 来源：packages/contracts/schema/${CONTRACT_VERSION}/${file}`,
      '',
      body,
    ].join('\n'),
    'utf8',
  )
}

/** 错误码在 Python 侧同样来自注册表。 */
const pyErrorCodes = [
  '# 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。',
  `# 来源：packages/contracts/schema/${CONTRACT_VERSION}/${REGISTRY_FILE}`,
  '',
  '"""已注册的契约错误码（ENGM.<DOMAIN>.<REASON>）。"""',
  '',
  'from typing import Final, Literal',
  '',
  'ErrorCode = Literal[',
  ...registryCodes.map((c) => `    "${c}",`),
  ']',
  '',
  '# 错误码 → 是否可重试；由注册表生成，不要手写第二份。',
  'ERROR_CODE_RETRYABLE: Final[dict[ErrorCode, bool]] = {',
  ...registryCodes.map((c) => `    "${c}": ${registry.codes[c].retryable ? 'True' : 'False'},`),
  '}',
  '',
  'ERROR_CODES: Final[tuple[ErrorCode, ...]] = (',
  ...registryCodes.map((c) => `    "${c}",`),
  ')',
  '',
].join('\n')
writeFileSync(join(pyOutDir, 'error_codes.py'), pyErrorCodes, 'utf8')

const pyPackageInit = [
  '# 本文件由 packages/contracts/scripts/generate.mjs 生成 —— 请勿手工编辑。',
  '',
  '"""EngMentor 本地契约（Python 侧）。',
  '',
  '生成物只按 schema 结构描述数据；校验请使用 jsonschema 或 Pydantic 的校验能力，',
  '不要在这里手写第二份契约定义。',
  '"""',
  '',
].join('\n')
writeFileSync(join(pyPackageRoot, '__init__.py'), pyPackageInit, 'utf8')
writeFileSync(join(pyOutDir, '__init__.py'), `${pyPackageInit}`, 'utf8')

// ---------------------------------------------------------------------------
// 4. schema-manifest.json（供 Rust 断言嵌入完整性）
// ---------------------------------------------------------------------------

const manifestEntries = [...SCHEMA_FILES, REGISTRY_FILE].sort().map((file) => {
  const bytes = readFileSync(join(schemaDir, file))
  const doc = readJson(join(schemaDir, file))
  return {
    file,
    path: `packages/contracts/schema/${CONTRACT_VERSION}/${file}`,
    id: typeof doc.$id === 'string' ? doc.$id : null,
    sha256: createHash('sha256').update(bytes).digest('hex'),
    bytes: bytes.length,
  }
})

const manifest = {
  $comment:
    '由 packages/contracts/scripts/generate.mjs 生成。Rust 侧在测试中用它断言 include_str! 嵌入的集合与契约包完全一致（SPEC-M00 §5.3 第 6 条 / AC-8）。改动 schema 后必须重新生成本文件。',
  contractVersion: CONTRACT_VERSION,
  schemaCount: manifestEntries.length,
  entries: manifestEntries,
}
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')

/**
 * 同一份 manifest 也放进 Python 包。
 *
 * 原因：Python 侧的 Sidecar 启动时要按 version.schema.json 上报自己支持的 schema $id 集合
 * （SPEC-M00 §5.3 第 5、6 条）。如果那份清单在 Python 里另写一遍，它就成了第二份契约来源，
 * 而"某侧落后于契约包"正是这条检查要发现的问题 —— 手抄的清单永远发现不了自己落后。
 * 放进包里的这一份仍在 check-drift.mjs 的生成物路径内，因此同样受漂移检查约束。
 */
const pyManifestPath = join(pyPackageRoot, 'schema-manifest.json')
writeFileSync(pyManifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')

// ---------------------------------------------------------------------------

const rel = (p) => relative(repoRoot, p).replace(/\\/g, '/')
console.log('[contracts:generate] OK')
console.log(`  契约来源（${manifestEntries.length}）: ${manifestEntries.map((e) => e.file).join(', ')}`)
console.log(`  错误码（${registryCodes.length}）: ${registryCodes.join(', ')}`)
console.log(`  TS 生成物: ${rel(tsOutDir)}/  (${tsFiles.length + 1} 个文件)`)
console.log(`  Python 生成物: ${rel(pyOutDir)}/`)
console.log(`  manifest: ${rel(manifestPath)}`)
console.log(`  manifest（Python 包内副本，供 Sidecar 版本上报）: ${rel(pyManifestPath)}`)
if (!existsSync(join(contractsRoot, 'python', 'pyproject.toml'))) {
  console.warn('  [warn] packages/contracts/python/pyproject.toml 不存在 —— Python 契约包无法安装')
}
