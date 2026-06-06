# 📢 更新日志

> 感谢您使用我们的 App！以下是最新版本的更新内容。

## 🚀 v0.1.1 `(104802306)`

*此版本目前仅提供 **API23** 软件包。*

### 🛠 核心重构 (Core Refactoring)

- **ESObject 全面消除**
  > 大规模迁移，将全项目约 30+ 文件中的 `ESObject` 替换为类型安全的 `Record<string, Object>` / `Record<string, Object | undefined>` 及显式接口定义，显著提升编译期类型安全。
  - `DataManager`：新增 `ComicSourceDatabaseInput`、`OnlineComicSourceSaveInput`、`OnlineComicInfoDatabaseRecord` 接口，替代 `ESObject` 参数与返回值。
  - `JSONSourceParser` / `JSONPathParser` / `VariableReplacer`：所有 `ESObject` 替换为 `Record<string, Object>` 系列类型。
  - WebView 引擎（`MangaSourceEngine`、`MangaSourceTypes`、`TaskExecutor`、`MangaSourceAPIEngine`、`MangaSourceActionEngine`、`MangaSourceConfigParser`、`WebViewSourceManager`）：全面迁移至类型安全的 Record 与显式接口。
  - `ImageDescramblerInitializer`：`ESObject` → `Record<string, Object | undefined>`。
  - 多个页面（`OnlineEBookDetailPage`、`SourceDetailPage`、`SourceSettingsPage`）完成同步迁移。

- **DistributedDataSyncManager 回调重构**
  > 从单回调模式 (`setOnDataChangedCallback`/`setOnStatusChangedCallback`) 迁移为多回调模式 (`addOnDataChangedCallback`/`removeOnDataChangedCallback`)，使用 `Set<Callback>` 支持多个监听者同时注册与独立注销。
  - `DistributedReadingService` 改为保存回调实例引用，确保 `detach()` 时正确移除自身回调。
  - `MangaReaderPage`、`EBookReaderPage`、`NovelReaderPage`、`RemoteControlPage` 重构为具名方法 + `add/remove` 模式，确保 `aboutToDisappear()` 中正确清理。

- **definite assignment assertion 消除**
  > 移除所有 `@Prop X!: Type` 写法，改为 `@Prop X: Type = default`，符合 ArkTS 严格类型规范。
  - 涉及 6+ 对话框/组件：`ThemeAwareState`、`GuideHighlightRect`、`CacheConfirmConfig`、`OriginalBookInfo` 等。

- **GlobalTaskCoordinator 类型安全**
  > 新增 `IPageManager` 接口（含 `getStats()` 和 `destroy()` 方法），替代页面管理器注册中的 `ESObject`，使任务协调器的类型链完全闭合。

### ✨ 功能与优化 (Features & Improvements)

- **showToast 废弃 API 修复**
  > 将 9 处已废弃的 `promptAction.showToast()` 全部迁移为 `this.getUIContext().getPromptAction().showToast()`，符合 API 23 规范。
  - `MangaReaderPage`、`EBookReaderPage`：移除 `promptAction` 导入。
  - `NovelReaderPage`：保留 `promptAction` 导入（`ActionMenuSuccessResponse` 类型仍需使用）。

- **GlobalSearchService 并发优化**
  > 搜索任务调度从批处理模式 (`executeTasksInBatches`) 升级为滑动窗口模式 (`executeTasksWithSlidingWindow`)，实现更平滑的并发控制。
  - 合并漫画 HTTP 与小说网络任务至共享 `networkTasks` 队列，避免双倍并发导致应用卡顿。

- **SuwayomiSource 扩展章节信息**
  > 新增 `SuwayomiExtendedChapterInfo` 接口（含 `isRead`、`isDownloaded`、`lastPageRead`），替代对 `ChapterInfo` 的不安全 `ESObject` 属性附加。

- **KomgaConfigStore 保存规范化**
  > 新增 `normalizeKomgaConfigForSave` 和 `normalizeKomgaInstanceConfig` 函数，确保 Komga 配置持久化时类型安全，替代 `normalizeKomgaConfig(config as ESObject)` 写法。

- **NGF 生命周期编排器完成承诺**
  > `ILifecycleOrchestrator` 接口新增 `getCompletionPromise(): Promise<boolean>` 方法。
  - `EntryAbility` 中延迟 `distributedDataSyncManager.joinSession()` 调用，等待 NGF 初始化完成后才加入分布式会话。

### 🔧 其他修复 (Other Fixes)

- **BOM 清理**：多个源文件移除 UTF-8 BOM 标记，确保编译器零警告。
- **TaskExecutor 变量替换正则修复**：将 `\$\{(\w+)\}` 修正为 `\{\{([a-zA-Z0-9_.]+)\}\}`，与模板语法 `{{variable}}` 对齐。
- **MangaSourceEngine 非法属性附加消除**：移除对数组对象的 `(pages as ESObject)['totalPages']` 写法。

### 🚧 已知问题与优化计划 (Known Issues)

部分功能目前仍在积极完善中，为您带来的不便敬请谅解：
- [ ] 🔄 **跨设备接续与遥控器**：基础链路已接入，但多设备权限、网络状态和真机一致性仍需继续打磨
- [ ] 🎧 **听书功能**：基础功能可用，但高阶体验仍需打磨
- [ ] 📚 **Suwayomi 兼容**：功能支持尚未完全对齐
- [ ] 📖 **Komga 兼容**：部分特性解析存在异常
- [ ] 🔄 **备份与恢复**：存在若干边缘测试未通过的问题，将在后续版本重点修复
