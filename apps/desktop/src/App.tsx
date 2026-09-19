import { useState } from 'react'
import { appInfo } from './lib/appInfo'
import { ChatView } from './components/ChatView'
import { SettingsView } from './components/SettingsView'

type View = 'chat' | 'settings'

/**
 * 应用外壳。
 *
 * 界面只展示真实存在的能力：目前只有「设置」与一条最小对话链路。
 * 状态以仓库根目录的 PROJECT_STATUS.md 为准（AGENTS.md 的 README 维护规则同理）。
 */
export function App() {
  const info = appInfo()
  const [view, setView] = useState<View>('chat')

  return (
    <div className="app">
      <header className="app-header">
        <div>
          <h1>{info.productName}</h1>
          <p className="stage">{info.stage}</p>
        </div>
        <nav className="tabs">
          <button
            type="button"
            className={view === 'chat' ? 'tab tab-active' : 'tab'}
            onClick={() => setView('chat')}
          >
            对话
          </button>
          <button
            type="button"
            className={view === 'settings' ? 'tab tab-active' : 'tab'}
            onClick={() => setView('settings')}
          >
            设置
          </button>
        </nav>
      </header>

      <main className="app-main">
        {view === 'chat' && <ChatView onOpenSettings={() => setView('settings')} />}
        {view === 'settings' && <SettingsView />}
      </main>

      <footer className="app-footer">
        <p>进度以仓库根目录的 PROJECT_STATUS.md 为准。</p>
      </footer>
    </div>
  )
}
