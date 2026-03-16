# 小说模块与 Legado 原版功能差异清单

## 分析范围
- 对比对象：
  - 我们 APP（`entry/src/main/ets` 下小说相关实现）
  - 本地克隆 Legado（`legado/app/src/main`）
- 对比方式：按功能模块梳理“Legado 已有、我们尚未完整具备”的能力。
- 说明：本清单聚焦“缺失/明显差异”，不是完整功能列表。

## 1. 书签系统（核心缺失）
### Legado 原版
- 阅读页直接加书签：`legado/app/src/main/res/menu/book_read.xml:48`
- 书签数据层：`legado/app/src/main/java/io/legado/app/data/entities/Bookmark.kt`
- 书签 DAO：`legado/app/src/main/java/io/legado/app/data/dao/BookmarkDao.kt`
- 书签编辑弹窗：`legado/app/src/main/java/io/legado/app/ui/book/bookmark/BookmarkDialog.kt`
- 全局书签页（含导出 JSON/MD）：`legado/app/src/main/java/io/legado/app/ui/book/bookmark/AllBookmarkActivity.kt`
- 目录页书签 Tab：`legado/app/src/main/java/io/legado/app/ui/book/toc/BookmarkFragment.kt`

### 我们当前
- 小说库表中无 `bookmark` 表，仅有 `novel_source/novel_book/novel_chapter/...`：`entry/src/main/ets/Framework/Novel/NovelDatabaseSchema.ets:176`
- 阅读器文本菜单为“复制/百科搜索/添加净化规则/分享”，无书签入口：`entry/src/main/ets/components/TextReaderComponent.ets:4712`
- 阅读器底部工具栏为“目录/字体/背景/阅读设置/听书”，无书签按钮：`entry/src/main/ets/pages/NovelReaderPage.ets:1946`

### 差异结论
- 缺少完整书签闭环：新增、编辑、删除、检索、导出、目录联动、全局管理页。

---

## 2. 阅读内全文检索与正文编辑
### Legado 原版
- 书内全文检索（跨章节结果页）：`legado/app/src/main/java/io/legado/app/ui/book/searchContent/SearchContentActivity.kt`
- 阅读菜单内联检索控制：`legado/app/src/main/java/io/legado/app/ui/book/read/SearchMenu.kt`
- 正文编辑：`legado/app/src/main/java/io/legado/app/ui/book/read/ContentEditDialog.kt`

### 我们当前
- 未检索到小说阅读“书内全文检索”模块（仅有全局搜索页和阅读内选中文本菜单）。
- 当前文本长按菜单不含“全文检索/正文编辑”能力：`entry/src/main/ets/components/TextReaderComponent.ets:4712`

### 差异结论
- 缺少阅读场景下的“跨章节检索”和“正文临时修订”能力。

---

## 3. 阅读器菜单能力差异（快捷操作不足）
### Legado 原版
- 阅读菜单含多个关键动作：换源、刷新、离线缓存、反转正文、模拟阅读、重分段、生效替换规则查看等：`legado/app/src/main/res/menu/book_read.xml:7`

### 我们当前
- 阅读器底部主要是样式与目录操作，功能型快捷动作较少：`entry/src/main/ets/pages/NovelReaderPage.ets:1900`

### 差异结论
- 缺少 Legado 在“阅读当下”可直接触发的一批高频工具入口。

---

## 4. 目录系统差异（目录增强能力缺失）
### Legado 原版
- 目录页支持章节/书签双视图、搜索和导出：`legado/app/src/main/java/io/legado/app/ui/book/toc/TocActivity.kt`

### 我们当前
- 目录面板为纯章节列表，无书签 Tab、无目录检索：`entry/src/main/ets/pages/NovelReaderPage.ets:2066`

### 差异结论
- 缺少目录侧的“检索 + 书签联动 + 导出”能力。

---

## 5. 换源能力差异（已支持基础换源，但缺少阅读态高级换源）
### Legado 原版
- 整书换源：`legado/app/src/main/java/io/legado/app/ui/book/changesource/ChangeBookSourceDialog.kt`
- 单章换源：`legado/app/src/main/java/io/legado/app/ui/book/changesource/ChangeChapterSourceDialog.kt`
- 阅读中自动换源：`legado/app/src/main/java/io/legado/app/ui/book/read/ReadBookViewModel.kt`

### 我们当前
- 已有详情页“整书换源搜索+切换”：`entry/src/main/ets/pages/NovelDetailPage.ets:1003`
- 阅读页未见单章换源/自动换源逻辑：`entry/src/main/ets/pages/NovelReaderPage.ets`

### 差异结论
- 缺少“阅读中容错换源”与“单章精细换源”。

---

## 6. 书架分组模型差异（功能有，但数据模型较轻）
### Legado 原版
- 独立 `book_groups` 实体，含 `order/show/enableRefresh/bookSort` 等字段：
  - `legado/app/src/main/java/io/legado/app/data/entities/BookGroup.kt:14`
  - `legado/app/src/main/java/io/legado/app/data/dao/BookGroupDao.kt:23`

### 我们当前
- 仅在 `novel_book` 上以 `groupName` 字符串表示分组：`entry/src/main/ets/Framework/Novel/NovelDatabaseSchema.ets:222`
- 分组操作以字符串聚合为主：`entry/src/main/ets/Framework/Novel/NovelDataManager.ets:540`

### 差异结论
- 缺少独立分组实体带来的高级能力：分组显示控制、独立排序策略、刷新策略等。

---

## 7. 听书引擎差异（HTTP/远程链路缺失）
### Legado 原版
- System TTS + HttpTTS 数据实体、服务、配置编辑全链路：
  - `legado/app/src/main/java/io/legado/app/data/entities/HttpTTS.kt`
  - `legado/app/src/main/java/io/legado/app/service/HttpReadAloudService.kt`
  - `legado/app/src/main/java/io/legado/app/ui/book/read/config/SpeakEngineDialog.kt`

### 我们当前
- 引擎类型枚举虽包含 `LEGADO_COMPAT/REMOTE`：`entry/src/main/ets/Models/TextReaderModels.ets:154`
- 但可用性默认仅 `SYSTEM=true`：`entry/src/main/ets/Framework/ReadAloud/ReadAloudAvailability.ets:24`
- `LEGADO_COMPAT` 与 `REMOTE` 后端仍是占位/TODO：`entry/src/main/ets/Framework/ReadAloud/ReadAloudBackends.ets:1454`

### 差异结论
- 目前实质上仅系统 TTS 可用，缺少 Legado 的 HTTP TTS 生态能力。

---

## 8. 登录链路差异（URL 登录未完成）
### Legado 原版
- 原版对书源登录场景支持更完整（含 WebView 登录链路）。

### 我们当前
- `executeUrlLogin()` 仍为 TODO，明确提示需 WebView 支持：`entry/src/main/ets/Framework/Novel/NovelLoginManager.ets:488`

### 差异结论
- 复杂登录源（需页面交互/表单提交流程）兼容性仍不足。

---

## 9. 替换规则高级能力差异
### Legado 原版
- ReplaceRule 支持分组、标题/正文独立作用、include/exclude scope、超时等：`legado/app/src/main/java/io/legado/app/data/entities/ReplaceRule.kt:24`
- 支持规则分组管理与阅读态“生效规则”查看：
  - `legado/app/src/main/java/io/legado/app/ui/replace/GroupManageDialog.kt`
  - `legado/app/src/main/java/io/legado/app/ui/book/read/EffectiveReplacesDialog.kt`

### 我们当前
- ReplaceRule 字段较简化（无 group/excludeScope/timeout 等）：`entry/src/main/ets/Framework/Novel/NovelReplaceRuleManager.ets:16`
- 阅读页未见“当前章生效规则可视化”入口。

### 差异结论
- 规则系统“高级筛选与阅读态调试”能力尚未对齐。

---

## 10. 阅读记录与云端进度同步差异
### Legado 原版
- 有 `ReadRecord` 实体与阅读记录页：
  - `legado/app/src/main/java/io/legado/app/data/entities/ReadRecord.kt`
  - `legado/app/src/main/java/io/legado/app/ui/about/ReadRecordActivity.kt`
- 阅读进度可与 WebDAV 联动上传/拉取：`legado/app/src/main/java/io/legado/app/model/ReadBook.kt:238`

### 我们当前
- 以 `novel_read_progress` 保存本地进度：`entry/src/main/ets/Framework/Novel/NovelDatabaseSchema.ets:275`
- 在小说模块未检索到 WebDAV 进度同步调用（上传/拉取进度逻辑）。

### 差异结论
- 缺少“阅读记录中心”与“阅读过程中的云端进度同步闭环”。

---

## 11. 书源编辑体验差异
### Legado 原版
- 有结构化书源编辑器（按规则分区编辑）：`legado/app/src/main/java/io/legado/app/ui/book/source/edit/BookSourceEditActivity.kt`

### 我们当前
- 书源编辑走通用 JSON 文本编辑器：`entry/src/main/ets/pages/NovelSourceManagementPage.ets:2097`

### 差异结论
- 缺少结构化校验、字段级编辑体验和针对书源规则的专用表单能力。

---

## 总结（优先级建议）
- P0（建议先做）：
  - 书签系统
  - 阅读内全文检索
  - 阅读态换源（至少单章换源）
- P1：
  - 听书 HTTP/远程引擎
  - 替换规则高级能力（分组+生效规则可视化）
  - URL 登录完整链路
- P2：
  - 分组模型升级（独立分组实体）
  - 阅读记录中心与云进度同步
  - 结构化书源编辑器
