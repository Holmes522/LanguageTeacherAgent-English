import { appInfo } from './lib/appInfo'

/**
 * 骨架界面。
 *
 * 刻意只显示"还没做什么"，不展示任何看起来像功能的东西：产品尚不能安装或使用，
 * 界面不得暗示已经可以查词、评分或导入资料（README 与 AGENTS.md 的文档规则同样适用）。
 */
export function App() {
  const info = appInfo()

  return (
    <main className="shell">
      <header>
        <h1>{info.productName}</h1>
        <p className="stage">{info.stage}</p>
      </header>

      <section>
        <h2>当前状态</h2>
        <p>
          这是桌面壳的最小骨架：可构建、可运行、可测试，但<strong>没有任何教学功能</strong>。
          尚不能安装或使用，也不存在安装包。
        </p>
      </section>

      <section>
        <h2>尚未实现</h2>
        <ul>
          <li>知识库选择与带来源的查词</li>
          <li>语法诊断与讲解</li>
          <li>句子与作文评分</li>
          <li>PDF / DOC / DOCX 导入与检索引用</li>
          <li>题库复核、错题本与复习计划</li>
        </ul>
      </section>

      <footer>
        <p>进度以仓库根目录的 PROJECT_STATUS.md 为准。</p>
      </footer>
    </main>
  )
}
