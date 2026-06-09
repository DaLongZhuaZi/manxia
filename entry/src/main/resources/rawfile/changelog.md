# 📢 更新日志

> 感谢您使用漫匣！以下是最新版本的更新内容。

## 🚀 v0.1.2 `(104802308)`

### 🏗 核心重构 (Core Refactoring)

- **Legado (阅读) 引擎深度重构**
  > 全面升级 Legado 书源引擎，支持更复杂的解析规则与 JS 运行时。
  - 新增 `LegadoJsEngine`，提供完整的 JS 脚本执行环境，以应对复杂且高度定制化的书源规则。
  - 增强 `LegadoRuleAnalyzer` 与 `LegadoSourceParser`，大幅提升规则运算及节点内容过滤能力。
  - 优化 `LegadoUrlAnalyzer` 的动态 URL 构建逻辑，全面适配书源中各项网络请求。

- **Legado 漫画源桥接系统**
  > 首创将 Legado 书源标准跨界扩展至漫画领域。
  - 新增 `LegadoMangaImageExtractor` 和 `LegadoMangaSourceBridge`，打通小说规则引擎与漫画加载管线。
  - 允许复用“阅读”架构直接解析并提取漫画图片列表，实现图源书源解析架构统一化。

### ✨ 功能与优化 (Features & Improvements)

- **WebView 悬浮调试与诊断**
  > `SourceDetailPage` 新增交互式 WebView 悬浮球调试入口，极大便利开发过程中的问题排查。
  - 悬浮球支持多方向手势拖拽与阻尼归位动画，同时防止与底层列表滚动产生手势冲突。
  - 加强 `NovelSourceDebugPage` 等调试面板的功能联动。

- **多页面统一桥接适配**
  > 阅读侧页面全面拥抱 Legado 桥接源格式，提供无缝一致的用户体验。
  - `UnifiedDetailPage` 和 `MangaDetailPage` 增加针对 Legado 桥接漫画数据的加载及展示逻辑。
  - `MangaReaderPage` 以及底层的 `HtmlFormatter` 也相应进行了视图兼容机制处理。

### 🛡 数据库与下载同步 (Database & Download)

- **跨载体资源同步架构**
  > 下载管理器与本地数据库模型扩展对桥接数据类型的全面支持。
  - 改进 `UnifiedDownloadManager` 下载抓取策略，实现通过 `LegadoMangaSourceBridge` 获取带有完整 Headers 参数的合法下载页面 (`DownloadPageItem`)。
  - `DatabaseSchema`、`DatabaseTypes` 迎来字段扩容更新，更平滑地兼容复合类型的源结构、本地缓存以及漫画页面记录。
