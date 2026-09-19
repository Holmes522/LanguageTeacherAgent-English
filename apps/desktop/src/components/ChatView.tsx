import { useCallback, useEffect, useRef, useState } from 'react'
import { checkSidecar, parseSidecarHealth, streamChat, type ChatMessage, type SidecarHealth } from '../lib/chat'
import { parseSettingsSnapshot, readSettings, type SettingsSnapshot } from '../lib/settings'

/**
 * 最小对话界面（M03 最小版本）。
 *
 * 界面上写什么、不写什么是有约束的：这段只把消息发给 DeepSeek 并把回答渲染出来，
 * **没有**知识库、没有检索、没有引用、没有评分。因此界面上不会出现任何暗示这些能力的
 * 措辞（AGENTS.md 的 README 维护规则同样适用于界面）。信封里的 `citations` 目前
 * 恒为空数组 —— 有来源的那一天，这里才该出现"来源"区块。
 */

interface Turn {
  readonly role: 'user' | 'assistant'
  readonly text: string
}

interface SelfCheck {
  readonly kind: 'ok' | 'error'
  readonly text: string
}

export function ChatView({ onOpenSettings }: { readonly onOpenSettings: () => void }) {
  const [snapshot, setSnapshot] = useState<SettingsSnapshot | null>(null)
  const [turns, setTurns] = useState<Turn[]>([])
  const [draft, setDraft] = useState('')
  const [streaming, setStreaming] = useState(false)
  const [failure, setFailure] = useState<string | null>(null)
  const [selfCheck, setSelfCheck] = useState<SelfCheck | null>(null)
  const [health, setHealth] = useState<SidecarHealth | null>(null)
  const transcriptEnd = useRef<HTMLDivElement | null>(null)

  const reload = useCallback(async () => {
    const response = await readSettings()
    if (response.ok) {
      setSnapshot(parseSettingsSnapshot(response.data))
    }
  }, [])

  useEffect(() => {
    void reload()
  }, [reload])

  useEffect(() => {
    transcriptEnd.current?.scrollIntoView({ block: 'end' })
  }, [turns])

  const ready = snapshot?.credentialConfigured === true && snapshot.cloudConsentGranted

  const handleSelfCheck = async () => {
    setSelfCheck({ kind: 'ok', text: '正在启动 Sidecar…' })
    setHealth(null)
    const response = await checkSidecar()
    if (!response.ok) {
      setSelfCheck({ kind: 'error', text: response.error.message })
      return
    }
    const parsed = parseSidecarHealth(response.data)
    if (parsed === null) {
      setSelfCheck({ kind: 'error', text: 'Sidecar 返回的健康信息形状不符合预期' })
      return
    }
    setHealth(parsed)
    setSelfCheck({
      kind: 'ok',
      text: parsed.modelConfigured
        ? `Sidecar 已就绪（契约 ${parsed.contractVersion}，凭据已下发）。`
        : `Sidecar 已就绪（契约 ${parsed.contractVersion}），但这次启动没有拿到凭据。`,
    })
  }

  const handleSend = async () => {
    const text = draft.trim()
    if (text === '' || streaming) return

    const history: ChatMessage[] = [
      ...turns.map((turn) => ({ role: turn.role, content: turn.text })),
      { role: 'user', content: text },
    ]

    setTurns([...turns, { role: 'user', text }, { role: 'assistant', text: '' }])
    setDraft('')
    setFailure(null)
    setStreaming(true)

    const appendToAnswer = (delta: string) => {
      setTurns((current) => {
        const next = [...current]
        const last = next[next.length - 1]
        if (last === undefined || last.role !== 'assistant') return current
        next[next.length - 1] = { role: 'assistant', text: last.text + delta }
        return next
      })
    }

    await streamChat(history, {
      onDelta: appendToAnswer,
      onDone: () => setStreaming(false),
      onFailure: (message) => {
        setStreaming(false)
        setFailure(message)
        // 这一轮没答出来，把占位的助手气泡撤掉，不要留一个空框。
        setTurns((current) => {
          const last = current[current.length - 1]
          if (last !== undefined && last.role === 'assistant' && last.text === '') {
            return current.slice(0, -1)
          }
          return current
        })
      },
    })
  }

  return (
    <div className="stack">
      <section className="panel">
        <div className="row row-between">
          <h2>对话（最小版本）</h2>
          <button type="button" className="secondary" onClick={handleSelfCheck} disabled={streaming}>
            检查 Sidecar
          </button>
        </div>
        <p className="muted">
          目前只把消息原样发给 DeepSeek 并把回答显示出来：没有知识库检索、没有来源引用、
          没有语法讲解与评分。回答可能出错，请自行核对。
        </p>

        {selfCheck !== null && (
          <p className={selfCheck.kind === 'ok' ? 'status-ok' : 'alert alert-error'}>
            {selfCheck.text}
          </p>
        )}
        {health !== null && (
          <p className="muted">
            AI Core {health.package} {health.version}（{health.stage}）· 教学能力：
            {health.capabilities.length === 0 ? '无（尚在骨架阶段）' : health.capabilities.join('、')}
          </p>
        )}
      </section>

      {!ready && (
        <p className="alert alert-error">
          {snapshot?.credentialConfigured !== true
            ? '还没有配置 DeepSeek API Key。'
            : '尚未同意把内容发送给云端模型。'}
          <button type="button" className="link" onClick={onOpenSettings}>
            去设置
          </button>
        </p>
      )}

      <section className="panel transcript">
        {turns.length === 0 ? (
          <p className="muted">还没有对话。在下面输入一句话试试。</p>
        ) : (
          turns.map((turn, index) => (
            <div key={index} className={`bubble bubble-${turn.role}`}>
              <span className="bubble-role">{turn.role === 'user' ? '我' : '模型'}</span>
              <p>{turn.text === '' ? '…' : turn.text}</p>
            </div>
          ))
        )}
        <div ref={transcriptEnd} />
      </section>

      {failure !== null && <p className="alert alert-error">{failure}</p>}

      <section className="panel">
        <div className="row">
          <input
            type="text"
            placeholder={ready ? '输入一句话…' : '请先在设置里配置并同意上云'}
            value={draft}
            disabled={!ready || streaming}
            spellCheck={false}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault()
                void handleSend()
              }
            }}
          />
          <button type="button" onClick={() => void handleSend()} disabled={!ready || streaming || draft.trim() === ''}>
            {streaming ? '生成中…' : '发送'}
          </button>
        </div>
        <p className="muted">回车发送。回答会逐字出现，可以中途关掉窗口。</p>
      </section>
    </div>
  )
}
