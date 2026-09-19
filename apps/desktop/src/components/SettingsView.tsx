import { useCallback, useEffect, useState } from 'react'
import {
  clearCredential,
  parseSettingsSnapshot,
  readSettings,
  setCredential,
  writeSettings,
  type SettingsSnapshot,
} from '../lib/settings'

/**
 * 设置界面（T012 最小版本）。
 *
 * 两条不能违反的界面规则：
 *   1. **密钥只进不出**。输入框永远从空开始，保存成功后立刻清空；界面显示的是
 *      "已配置 / 未配置"，没有任何路径能把已保存的密钥读回来（主进程也不提供这样的命令）。
 *   2. **上云同意必须是用户主动勾选**。默认关闭，并且说明清楚发送的是什么、
 *      不发的是什么 —— 这是 Q5 的已批准决策，不能用一个含糊的开关糊过去。
 */

interface Feedback {
  readonly kind: 'ok' | 'error'
  readonly text: string
}

export function SettingsView() {
  const [snapshot, setSnapshot] = useState<SettingsSnapshot | null>(null)
  const [loading, setLoading] = useState(true)
  const [apiKey, setApiKey] = useState('')
  const [model, setModel] = useState('')
  const [baseUrl, setBaseUrl] = useState('')
  const [feedback, setFeedback] = useState<Feedback | null>(null)
  const [busy, setBusy] = useState(false)

  const applySnapshot = useCallback((value: SettingsSnapshot) => {
    setSnapshot(value)
    setModel(value.model)
    setBaseUrl(value.baseUrl)
  }, [])

  const reload = useCallback(async () => {
    const response = await readSettings()
    if (!response.ok) {
      setFeedback({ kind: 'error', text: response.error.message })
      setLoading(false)
      return
    }
    const parsed = parseSettingsSnapshot(response.data)
    if (parsed === null) {
      setFeedback({ kind: 'error', text: '主进程返回的设置形状不符合预期' })
      setLoading(false)
      return
    }
    applySnapshot(parsed)
    setLoading(false)
  }, [applySnapshot])

  useEffect(() => {
    void reload()
  }, [reload])

  const handleSaveKey = async () => {
    if (busy) return
    setBusy(true)
    setFeedback(null)
    const response = await setCredential(apiKey)
    if (response.ok) {
      // 无论成功与否都不保留输入内容：成功是因为没必要留，失败是因为
      // 留在界面上会被后续截图/录屏带出去。
      setApiKey('')
      setFeedback({ kind: 'ok', text: '已保存到 Windows 凭据管理器。本界面无法读回，这是有意的。' })
    } else {
      setFeedback({ kind: 'error', text: response.error.message })
    }
    setBusy(false)
    await reload()
  }

  const handleClearKey = async () => {
    if (busy) return
    setBusy(true)
    setFeedback(null)
    const response = await clearCredential()
    setApiKey('')
    setFeedback(
      response.ok
        ? { kind: 'ok', text: '已从凭据管理器删除。' }
        : { kind: 'error', text: response.error.message },
    )
    setBusy(false)
    await reload()
  }

  const handleSaveService = async () => {
    if (busy) return
    setBusy(true)
    setFeedback(null)
    const response = await writeSettings({ model, baseUrl })
    if (response.ok) {
      const parsed = parseSettingsSnapshot(response.data)
      if (parsed !== null) applySnapshot(parsed)
      setFeedback({ kind: 'ok', text: '模型设置已保存。' })
    } else {
      setFeedback({ kind: 'error', text: response.error.message })
    }
    setBusy(false)
  }

  const handleConsentChange = async (granted: boolean) => {
    if (busy) return
    setBusy(true)
    setFeedback(null)
    const response = await writeSettings({ cloudConsentGranted: granted })
    if (response.ok) {
      const parsed = parseSettingsSnapshot(response.data)
      if (parsed !== null) applySnapshot(parsed)
      setFeedback({
        kind: 'ok',
        text: granted ? '已同意，从现在起提问会把内容发给 DeepSeek。' : '已关闭，提问不会再发往云端。',
      })
    } else {
      setFeedback({ kind: 'error', text: response.error.message })
    }
    setBusy(false)
  }

  if (loading) {
    return <p className="muted">正在读取设置…</p>
  }

  if (snapshot === null) {
    return (
      <section className="panel">
        <h2>设置</h2>
        <p className="alert alert-error">
          无法读取设置{feedback?.kind === 'error' ? `：${feedback.text}` : ''}
        </p>
      </section>
    )
  }

  return (
    <div className="stack">
      <section className="panel">
        <h2>模型服务</h2>
        <p className="muted">
          密钥保存在 Windows 凭据管理器里，不写入任何配置文件，也不会回传到本界面。
        </p>

        <div className="field">
          <label htmlFor="api-key">DeepSeek API Key</label>
          <div className="row">
            <input
              id="api-key"
              type="password"
              autoComplete="off"
              spellCheck={false}
              placeholder={snapshot.credentialConfigured ? '已保存（重新填写可覆盖）' : 'sk-…'}
              value={apiKey}
              onChange={(event) => setApiKey(event.target.value)}
            />
            <button type="button" onClick={handleSaveKey} disabled={busy || apiKey.trim() === ''}>
              保存密钥
            </button>
            <button
              type="button"
              className="secondary"
              onClick={handleClearKey}
              disabled={busy || !snapshot.credentialConfigured}
            >
              删除
            </button>
          </div>
          <p className={snapshot.credentialConfigured ? 'status-ok' : 'status-off'}>
            {snapshot.credentialConfigured ? '✓ 已配置' : '✗ 未配置'}
          </p>
        </div>

        <div className="field">
          <label htmlFor="model">模型 id</label>
          <input
            id="model"
            type="text"
            spellCheck={false}
            value={model}
            onChange={(event) => setModel(event.target.value)}
          />
        </div>

        <div className="field">
          <label htmlFor="base-url">服务地址</label>
          <input
            id="base-url"
            type="text"
            spellCheck={false}
            value={baseUrl}
            onChange={(event) => setBaseUrl(event.target.value)}
          />
          <p className="muted">必须是以 https:// 开头的地址。密钥会随请求发往这里。</p>
        </div>

        <button type="button" onClick={handleSaveService} disabled={busy}>
          保存模型设置
        </button>
      </section>

      <section className="panel">
        <h2>内容上云</h2>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={snapshot.cloudConsentGranted}
            disabled={busy}
            onChange={(event) => void handleConsentChange(event.target.checked)}
          />
          <span>我同意在提问时把内容发送给 DeepSeek（切换后立即生效）</span>
        </label>
        <ul className="muted">
          <li>会发送：你当前输入的问题，以及回答所需的少量资料片段。</li>
          <li>不会发送：你的整份文档、知识库全文、本地数据库，以及你的 API Key（密钥只在你的电脑与 DeepSeek 之间使用）。</li>
          <li>随时可以关掉。关掉后仍可使用不依赖云模型的功能。</li>
        </ul>
      </section>

      {feedback !== null && (
        <p className={feedback.kind === 'ok' ? 'alert alert-ok' : 'alert alert-error'}>
          {feedback.text}
        </p>
      )}
    </div>
  )
}
