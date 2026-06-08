# 📢 更新日志

> 感谢您使用漫匣！以下是最新版本的更新内容。

## 🚀 v0.1.1 `(104802307)`

*此版本目前仅提供 **API23** 软件包。*

### 🏗 核心重构 (Core Refactoring)

- **漫画阅读器管线模块化**
  > 将 `MangaViewer` 中的大量阅读逻辑拆分为独立规划器、解析器、生命周期管理器与监控器，降低单组件复杂度。
  - 新增资源加载管线：`MangaAssetLoadCoordinator`、`MangaAssetLoader`、`MangaAssetRequestFactory`、`MangaAssetMonitor`。
  - 新增阅读会话保护：`MangaReaderSessionGuard`、`MangaChapterResolveGuard`、`MangaReaderLaunchContextResolver`、`MangaReaderPageSyncGuard`。
  - 新增预加载与缓存协调：`MangaPreloadPlanner`、`MangaPreloadTaskCoordinator`、`MangaReaderCacheMonitor`。
  - 新增 PixelMap 生命周期管理：集中释放、淘汰和卷页所需 PixelMap 解析，减少图片资源泄漏风险。

- **Webtoon 与翻页逻辑拆分**
  > 连续滚动、相邻章节、边界判断、手势、视口、预热、清理和章节切换逻辑改为专用模块。
  - 新增 `MangaWebtoonDataPlanner`、`MangaWebtoonViewportPlanner`、`MangaWebtoonBoundaryPlanner`、`MangaWebtoonChapterSwitchPlanner` 等模块。
  - 新增 `MangaPageTurnPlanner`、`MangaCurlTurnPlanner`、`MangaCurlPixelMapResolver`，统一普通翻页、单页卷页和双页卷页的决策。

- **阅读流程监控体系**
  > 新增 `MangaReadFlowMonitor` 及相关事件模型，贯穿本地导入、在线阅读、远程阅读器和阅读页显示提交。
  - 记录章节解析、页面解析、页面切换、进度保存、降级、恢复、错误、清理等事件。
  - Suwayomi 旧阅读页、Komga 阅读页、电子书图片阅读页等补充阅读流程记录。
  - 本地漫画导入完成后会生成阅读流程导入报告，便于回溯从导入到打开阅读的完整链路。

- **独立 Ability 架构接入**
  > 新增多个隔离窗口能力，并在 `module.json5` 与 `main_pages.json` 中完成注册。
  - 新增 `ReadAloudPlayerAbility`：听书播放器可在独立实例中打开。
  - 新增 `FileEditorAbility`：文件编辑器支持多实例隔离会话。
  - 新增 `ExternalFileTaskAbility`：系统打开、系统分享、局域网传书、网络文件夹等外部文件任务统一交给独立导入实例处理。
  - 新增 `RemoteControlAbility`：遥控器可独立打开，避免与主页面导航状态相互干扰。
  - 启动页改为透明隐藏启动窗口资源，减少独立 Ability 打开时的闪屏。

### ✨ 功能与优化 (Features & Improvements)

- **文件编辑器增强**
  > 文件编辑器升级为可恢复的多实例、多标签编辑环境。
  - 新增编辑器会话、实例快照、脏状态恢复和关闭保护。
  - 支持保存全部、另存为、Ctrl/Cmd+S 快捷保存和 Monaco 保存回调。
  - 新增能力审计面板，显示独立会话、核心编辑、文件保存、导入导出、Markdown 预览、多标签和应用联动状态。
  - 支持图源 JSON 与书源 JSON 的联动保存，保存后可自动应用到应用内配置。

- **外部文件导入统一化**
  > 文件管理器打开、系统分享、局域网传书、网络文件夹导入统一转换为 `ExternalFileTaskParams`。
  - 支持漫画、电子书、PDF、备份、JSON、字体、代码、AVIF 和普通图片。
  - `EntryAbility` 与 `ShareExtAbility` 优先启动独立外部文件任务，失败时回退旧流程。
  - `DataManagementPage` 支持接收独立任务参数、批量任务和导入结果追踪。
  - AVIF 测试页扩展为通用图片预览页，普通图片走系统解码，AVIF 继续使用专用解码器。

- **局域网传书与小窗**
  > 局域网传书支持把已上传文件交给独立导入窗口继续处理。
  - 新增 `TransferFloatingWindowPage` 和应用内小窗管理能力，可将传输状态以小窗形式悬浮显示。
  - 传输服务停止时会清理服务通知和活跃上传通知，避免残留通知。
  - 支持 AVIF/普通图片作为传输导入类型。

- **远程书库入口与引导**
  > Suwayomi 与 Komga 从隐藏能力变为更明确的远程书库入口。
  - 默认底栏标签包含书库、图源、书源、Suwayomi、Komga 和设置。
  - Suwayomi/Komga 设置页新增底栏显示开关。
  - 欢迎引导新增“远程书库”步骤，可直接跳转 Suwayomi 或 Komga 配置。
  - Komga 浏览页新增页面内引导，覆盖实例、筛选、内容区和阅读链路。
  - Komga 设置页增加异步请求序号保护，避免切换实例时旧测试/加载结果覆盖新状态。

- **主书库交互增强**
  > 主页面书库补充批量选择、滑动删除和远程内容删除体验。
  - 支持双指对角手势进入或退出书库多选。
  - 漫画、电子书、小说列表增加滑动删除背景和更多操作按钮。
  - 多选删除支持混合内容，并对远程服务端内容做本地书架移除处理。
  - 新增书源选择器自动滚动设置。

- **Cloudflare 传输辅助服务**
  > 新增 `cloudflare/manxia-worker`，用于外部访问入口、深链跳转、信令房间和 WebRTC 文件发送实验。
  - 支持 Durable Object 信令房间、房间状态 API、WebSocket 信令与 CORS API。
  - 提供传输落地页、应用深链、局域网访问跳转、WebRTC 文件发送界面。

### 🛡 备份、恢复与文件安全 (Backup & Storage)

- **备份恢复覆盖面扩展**
  > `EnhancedBackupManager` 扩展备份数据模型并增强失败传播。
  - 新增小说章节、正文缓存、阅读器设置、替换规则、TXT 目录规则、词典规则、第三方追踪记录和 Preferences 备份恢复。
  - 区分普通偏好配置与敏感云端配置，默认不再自动恢复云配置。
  - 数据库恢复任务按事务/非事务分组，数据库部分失败时会回滚并停止后续副作用恢复。
  - 恢复时会累计失败项并抛出明确错误，避免静默成功。

- **WebDAV 备份加固**
  > WebDAV 远程备份增加文件名、远程路径、索引和下载安全处理。
  - 远程备份文件名统一净化，避免路径穿越和非法字符。
  - 备份索引读取增加标准化，兼容旧字段并过滤异常条目。
  - ArkTS 回退 WebDAV 客户端限制 32 MiB 大文件并提示使用 Native 客户端。
  - 下载采用临时文件替换，减少失败时覆盖已有备份的风险。

- **严格文件 I/O 与 Tar 包处理**
  > 新增 `SafeFileUtils` 严格读写工具，Tar 打包/解包改为流式精确读写。
  - 支持 `readExactSync`、`writeExactSync`、严格复制、重命名、删除、打开、关闭等封装。
  - Tar 解包校验 `ustar`、校验和、八进制字段和非法路径，防止路径穿越。
  - 备份媒体、字体、电子书、图源图标恢复改用原子复制或严格复制。

### 🎨 视觉、资源与系统图标 (UI & Resources)

- **系统资源目录扩展**
  > 根据本机 HarmonyOS SDK 23 的 `sysResource.js` 扩展资源映射。
  - `ResourceMap.ets` 新增系统颜色与系统媒体资源映射。
  - `SystemSymbolCatalog.ets` 更新为 4027 个系统 Symbol 图标目录。
  - `SystemResourcePreviewPage` 扩展系统颜色、媒体图标和 Symbol 预览能力。
  - 新增测试管理面板深色背景与边框颜色资源。

- **阅读统计页重排**
  > 阅读统计页重构为更统一的玻璃面板布局。
  - 新增阅读波动趋势条、趋势日期标签和阅读洞察区域。
  - 漫画、电子书、小说阅读统计分区统一卡片、间距、阴影和响应式布局。
  - 修复多个文本溢出与紧凑布局场景。

- **弹窗与组件细节**
  > 对话框、隐私认证、来源弹窗、底栏和设置卡片继续向统一玻璃风格收敛。
  - `UniversalDialog` 支持自定义内容构建参数。
  - `PrivacyAuthDialogComponent` 复用统一弹窗圆角，密码显示按钮改为 Symbol 图标。
  - 多个页面与组件继续替换语义化系统 Symbol。

### ⚙️ 性能、缓存与数据修复 (Performance & Fixes)

- **图片与封面缓存**
  > 降低重复失败请求和 PixelMap 泄漏风险。
  - `CoverCacheManager` 记录短期失败下载，避免 30 分钟内反复请求失败封面。
  - `CoverImageManager` 增加 LRU 数量上限并在淘汰时释放 PixelMap。
  - 阅读器退出、章节切换和 Suwayomi AVIF 缓存清理时补充资源释放。

- **下载与数据一致性**
  > 下载管理器和漫画数据查询增强索引与状态同步。
  - `UnifiedDownloadManager` 增加任务状态索引和回调快照，减少遍历和回调期间集合变化风险。
  - `DataManager` 优化本地/在线漫画信息合并，优先保留本地记录。
  - 在线章节支持同步下载状态、下载路径、章节号等字段。
  - 新增按任务或章节删除下载任务记录的方法。

- **图源解析与网络**
  > 图源 JSON 解析器补充 HTML/XML 标记解析路径。
  - 未知解析器类型会记录警告并返回安全结果。
  - WebView 行为、反爬、Workflow、Cookie、Rhino 执行器等模块同步完成小范围 ArkTS 规范修复。

- **工程与诊断**
  > 主仓库补充本次排查与回滚辅助材料。
  - 新增 `build-warning-summary-20260608.txt`，记录当前构建告警分类和重点文件。
  - `AGENTS.md` 补充已验证的构建/设备命令和本机 SDK 路径规则。
  - 本次高风险改动保留了同目录 `*.bak_*` 与 `backup/agent-resource-bak` 资源备份文件，便于必要时人工比对。

### 🚧 已知问题与优化计划 (Known Issues)

部分功能目前仍在积极完善中，为您带来的不便敬请谅解：
- [ ] 🔄 **独立 Ability 与小窗**：多实例、后台、分屏和跨设备场景仍需要真机回归
- [ ] 📡 **Cloudflare 信令与 WebRTC 传输**：新增服务端与网页实验能力，仍需线上部署和网络环境验证
- [ ] 🔄 **备份与恢复**：覆盖面已扩大，但敏感云配置、媒体文件和大备份仍需更多边缘用例验证
- [ ] 📚 **远程书库**：Suwayomi / Komga 的入口、引导和阅读流程已加强，兼容性仍会继续补齐
- [ ] ⚠️ **构建告警**：当前告警摘要记录到 `build-warning-summary-20260608.txt`，后续会继续处理可复用的 ArkTS 告警
