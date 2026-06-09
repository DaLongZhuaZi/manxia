# 更新日志

## v0.1.2 (104802308)

### 核心重构
- 全面升级 Legado 书源引擎，新增完整的 JS 运行时（`LegadoJsEngine`）与多层规则分析器。
- 首创引入 Legado 漫画源桥接模块（`LegadoMangaSourceBridge`），实现通过小说“阅读”规则体系直接解析并阅读漫画。

### 功能与优化
- 详情页面（`SourceDetailPage`）新增高自由度的交互式 WebView 悬浮球调试入口，改善图源及书源开发者调试体验。
- 详情与阅读页面（`UnifiedDetailPage`, `MangaReaderPage`）全面接入桥接源，实现图文跨载体逻辑的合一展示与兼容。

### 底层与修复
- 本地数据库（`DatabaseSchema`）扩容更新，用于支持复合类型的源结构与状态。
- 下载中心及 `UnifiedDownloadManager` 同步升级，实现对桥接类图源的下载支持与 Headers 参数精准提取。
