# 组件状态爆炸问题详细分析与解决方案

> 目标 API 版本：HarmonyOS 6.1.0(23) / ArkTS 5.0
> 分析日期：2026-05-06

---

## 目录

1. [问题总览](#1-问题总览)
2. [MainMenuPage.ets — 308 个响应式状态装饰器](#2-mainmenupageets--308-个响应式状态装饰器)
3. [UnifiedDetailPage.ets — 164 个 @State 变量](#3-unifieddetailpageets--164-个-state-变量)
4. [EpubWebViewReaderComponent.ets — ~~7663~~ 5,106 行（Phase 1 完成）](#4-epubwebviewreadercomponentets--7663-行未拆分)
5. [通用优化模式](#5-通用优化模式)
6. [推荐实施顺序](#6-推荐实施顺序)

---

## 1. 问题总览

| 文件 | 行数 | @State | @StorageProp | 其他装饰器 | @Builder 数 | 估计可提取行数 |
|------|------|--------|-------------|-----------|------------|--------------|
| MainMenuPage.ets | 32,272 | 282 | 22 | 4 | 161 | ~14,000 |
| UnifiedDetailPage.ets | ~~17,545~~ → **8,910** | ~~164~~ → **75** | 0 | 0 | 73 | ~7,000 |
| EpubWebViewReaderComponent.ets | ~~7,663~~ → **5,106** | 24 | 0 | 4 | 3 | ~3,000 |

**核心问题：** 每个 `@State` 变量在 ArkUI 框架中都会创建一个独立的响应式订阅链。当任何一个 `@State` 变量变化时，框架需要遍历该组件的整个 `build()` 树来决定哪些 UI 节点需要更新。变量越多，遍历开销越大。300+ 个 `@State` 意味着每次状态变更都要对 32,000 行的组件树做 diff，这是渲染卡顿的直接原因。

**ArkTS 特有约束：**
- ArkTS 不支持 `React.memo` / `Vue.computed` 等细粒度响应式原语
- `@State` 变量变更会触发整个组件的 `build()` 重新执行（不是子树）
- `@Builder` 方法不是独立组件，不享受组件级别的 diff 优化
- `@Observed` + `@ObjectLink` 是 ArkTS 提供的唯一对象级响应式方案

---

## 2. MainMenuPage.ets — 308 个响应式状态装饰器

### 2.1 装饰器分布

| 装饰器 | 数量 | 说明 |
|--------|------|------|
| `@State` | 282 | 组件内部状态 |
| `@StorageProp` | 22 | 从 AppStorage 单向读取 |
| `@StorageLink` | 3 | 与 AppStorage 双向绑定 |
| `@Provide` | 1 | 向子组件提供上下文 |
| `@Watch` | 7 | 状态变更监听（与其他装饰器共行） |

### 2.2 功能区域详细分解

#### A. 书架管理（53 变量，lines 634-703）

这是最大的状态集群，由三个紧密耦合的子组构成：

**书架 CRUD（28 变量）：**
```
showAddShelfDialog, showDeleteShelfDialog, showRenameShelfDialog, showMoveToShelfDialog,
newShelfName, newShelfType, newShelfContentTypes, newShelfIcon, newShelfColor,
addShelfDialogStep, isShelfEditMode, shelfCardAnimationScale, deletingShelfId,
renamingShelf, renameShelfName, movingToShelfItemId, movingToShelfContentType,
availableShelvesForMove, customShelfSortType, customShelfTags, customShelfSelectedTags,
showCustomShelfSortPopup, showCustomShelfTagPopup, selectedShelfType, shelfContentFilter,
selectedShelf, shelfDetailTransitionScale, shelfDetailContentDeferred
```

**动态筛选器（11 变量）：**
```
dynamicFilterSelectedAuthors, dynamicFilterSelectedTags, dynamicFilterSelectedKeywords,
dynamicFilterSelectedSources, dynamicFilterCustomKeywords, dynamicFilterCustomInput,
dynamicFilterAllTitleKeywords, dynamicFilterAllImageSourceNames, dynamicFilterAllBookSourceNames,
dynamicFilterTabIndex, dynamicFilterSearchText, dynamicFilterNsfwSelection, dynamicShelfMatchedItems
```

**书架分类（14 变量）：**
```
selectedCategoryId, showCategoryDetail, showCreateCategoryDialog, showEditCategoryDialog,
editingCategory, newCategoryName, showMoveToCategoryDialog, categoryDetailAnimationProgress,
movingMangaId, movingEBookId, movingNovelId, movingContentType, isCategoryEditMode, draggingCategoryId
```

**关联 @Builder 方法（20+ 个）：**
`buildShelfDetailHeader`, `buildCategoryView`, `buildCustomShelfCard`, `buildAddShelfCard`,
`buildShelfManageCard`, `buildTypeShelfCard`, `buildCategoryCard`, `buildAddShelfDialog`,
`buildDeleteShelfDialog`, `buildRenameShelfDialog`, `buildMoveToShelfDialog`,
`buildCategoryDetailOverlay`, `buildMoveToCategoryDialog`, `buildShelfToolbar`,
`buildDynamicFilterChipList` 等。

**提取方案：** 将 53 个变量 + 20+ 个 @Builder + 关联 handler 方法提取为独立 `@Component`：
```typescript
@Component
export struct ShelfManagerPanel {
  // 书架管理状态（28 变量）
  @State showAddShelfDialog: boolean = false;
  @State newShelfName: string = '';
  // ... 其余 26 个

  // 动态筛选状态（11 变量）
  @State dynamicFilterSelectedTags: Set<string> = new Set();
  // ... 其余 10 个

  // 分类状态（14 变量）
  @State selectedCategoryId: string = '';
  // ... 其余 13 个

  // 通过回调与父组件通信
  onShelfSelected?: (shelfId: string) => void;
  onCategorySelected?: (categoryId: string) => void;

  build() {
    // 迁移自 MainMenuPage 的 20+ 个 @Builder
  }
}
```

**预估收益：** 减少 53 个 @State，提取 ~1,500 行代码。

---

#### B. Suwayomi 集成（20 变量，lines 856-876）

所有变量均以 `suwayomi*` 为前缀，几乎完全自包含：

```
suwayomiMangas, suwayomiSources, suwayomiCategories, suwayomiSelectedCategoryId,
suwayomiBrowseMode, suwayomiSearchQuery, suwayomiDisplayMode, isLoadingSuwayomi,
isRefreshingSuwayomi, suwayomiTotalCount, suwayomiHasMore, suwayomiCurrentOffset,
suwayomiSelectedSortIndex, suwayomiCoverCachePaths, suwayomiErrorMessage,
suwayomiSelectedLanguage, suwayomiAvailableLanguages, suwayomiPinnedSourceIds,
suwayomiSourceIconCachePaths, suwayomiCategoriesExpanded, suwayomiRefreshHintVisible
```

**关联 @Builder：** `buildSuwayomiContent`（694 行，全文件最大 @Builder）。

**耦合分析：** 仅 `suwayomiBrowseMode` 在 `buildSuwayomiBottomNav` 中有额外引用，其余 19 个变量完全局限于 Suwayomi 区域。

**提取方案：**
```typescript
@Component
export struct SuwayomiTabContent {
  @State suwayomiMangas: SuwayomiManga[] = [];
  @State suwayomiSources: SuwayomiSource[] = [];
  @State isLoadingSuwayomi: boolean = false;
  // ... 其余 17 个

  // 仅需从父组件接收主题和布局信息
  @Prop themeState!: ThemeAwareState;
  @Prop gridColumns: number = 3;

  build() {
    // 迁移 buildSuwayomiContent 的 694 行
  }
}
```

**预估收益：** 减少 20 个 @State，提取 ~700 行代码。**ROI 最高的单一提取。**

---

#### C. 书源管理（17 变量，lines 831-848）

```
bookSourceList, filteredBookSourceList, bookSourceSearchKeyword, selectedBookSourceId,
selectedBookSourceName, bookSourceExploreKinds, bookSourceExploreKindIndex,
bookSourceBooks, isLoadingBookSourceBooks, bookSourceHasMore, bookSourceCurrentPage,
showBookSourcePicker, bookSourceViewMode, bookSourceSearchInput, bookSourceSearchMode,
bookSourceKindsExpanded, bookSourceRefreshHintVisible
```

**关联 @Builder：** `buildBookSourceContent`（542 行）、`buildBookSourcePickerContent`（146 行）。

**提取方案：**
```typescript
@Component
export struct BookSourceTabContent {
  @State bookSourceList: BookSourceItem[] = [];
  @State selectedBookSourceId: string = '';
  // ... 其余 15 个

  onBookSelected?: (bookId: string) => void;

  build() { /* 迁移 542 + 146 行 */ }
}
```

**预估收益：** 减少 17 个 @State，提取 ~700 行代码。

---

#### D. 库核心状态（23 变量，lines 596-812）

```
mangaList, filteredMangaList, allMangaList, isLoadingMangaList, isRefreshing,
libraryContentType, libraryFilterType, librarySortType, libraryViewMode,
showFilterPopup, showSortPopup, showGridSettingsPopup, bannerIndex,
coverInfoCache, showTagPopup, showAuthorPopup, allTags, selectedTags,
allAuthors, selectedAuthors, isFavoriteOnly, pdfEbookList, filteredPdfEbookList
```

**问题：** 这些变量是书库 Tab 的核心数据流，与多个子区域（漫画列表、电子书列表、小说列表、筛选面板）都有耦合。直接提取难度较高。

**分步方案：**
1. 先将 `mangaList`/`filteredMangaList`/`allMangaList` 等列表数据封装为 `@Observed` 类
2. 再将筛选/排序状态封装为独立类
3. 最后将列表渲染提取为子组件

```typescript
@Observed
class MangaListState {
  mangaList: Manga[] = [];
  filteredMangaList: Manga[] = [];
  allMangaList: Manga[] = [];
  isLoading: boolean = false;
  isRefreshing: boolean = false;
  filterType: LibraryFilterType = LibraryFilterType.ALL;
  sortType: LibrarySortType = LibrarySortType.LAST_READ;
  viewMode: LibraryViewMode = LibraryViewMode.GRID;
}

@Observed
class LibraryFilterState {
  allTags: string[] = [];
  selectedTags: Set<string> = new Set();
  allAuthors: string[] = [];
  selectedAuthors: Set<string> = new Set();
  showTagPopup: boolean = false;
  showAuthorPopup: boolean = false;
}
```

**预估收益：** 减少 23 个 @State → 2 个对象引用。

---

#### E. 三重重复模式（41 变量）

以下三组变量在漫画/电子书/小说三个内容类型间完全重复：

**多选模式（13 变量）：**
```
isMultiSelectMode / isEBookMultiSelectMode / isNovelMultiSelectMode
selectedMangaIds / selectedEBookIds / selectedNovelIds
isDeletingManga / isDeletingEBook / isDeletingNovel
isDiscoverMultiSelectMode / selectedDiscoverMangaIds / selectedDiscoverEBookIds / selectedDiscoverNovelIds
```

**滑动操作（10 变量）：**
```
activeSwipeId / activeEBookSwipeId / activeNovelSwipeId
isSwipeActive / isEBookSwipeActive / isNovelSwipeActive
swipeOffset / ebookSwipeOffset / novelSwipeOffset
swipeThreshold
```

**上下文菜单（18 变量）：**
```
showMangaContextMenu / showEBookContextMenu / showNovelContextMenu
contextMenuManga / contextMenuEBook / contextMenuNovel
mangaContextMenuAnchorKey / ebookContextMenuAnchorKey / novelContextMenuAnchorKey
showDiscoverMangaContextMenu / showDiscoverEBookContextMenu / showDiscoverNovelContextMenu
contextMenuDiscoverManga / contextMenuDiscoverEBook / contextMenuDiscoverNovel
discoverMangaContextMenuAnchorKey / discoverEBookContextMenuAnchorKey / discoverNovelContextMenuAnchorKey
```

**ArkTS 通用化方案：**

由于 ArkTS 不支持泛型组件，可以使用 `@Observed` 类封装：

```typescript
@Observed
class MultiSelectState {
  isActive: boolean = false;
  selectedIds: Set<string> = new Set();
  isDeleting: boolean = false;

  enter(initialId?: string): void { /* ... */ }
  exit(): void { /* ... */ }
  toggle(id: string): void { /* ... */ }
  selectAll(ids: string[]): void { /* ... */ }
  hasSelection(): boolean { return this.selectedIds.size > 0; }
}

@Observed
class SwipeActionState {
  activeId: string = '';
  isActive: boolean = false;
  offset: number = 0;
  readonly threshold: number = 80;
}

@Observed
class ContextMenuState<T> {
  show: boolean = false;
  item: T | null = null;
  anchorKey: string = '';

  showMenu(item: T, anchorKey: string): void { /* ... */ }
  hide(): void { /* ... */ }
}
```

使用时：
```typescript
// 在 MainMenuPage 中
@State mangaMultiSelect = new MultiSelectState();
@State ebookMultiSelect = new MultiSelectState();
@State novelMultiSelect = new MultiSelectState();

@State mangaSwipe = new SwipeActionState();
@State ebookSwipe = new SwipeActionState();
@State novelSwipe = new SwipeActionState();

@State mangaContextMenu = new ContextMenuState<Manga>();
@State ebookContextMenu = new ContextMenuState<EBook>();
@State novelContextMenu = new ContextMenuState<NovelBook>();
```

**预估收益：** 41 个 @State → 9 个对象引用（减少 32 个），同时消除大量重复代码。

---

#### F. 发现页（15 变量，lines 792-799, 4270-4278）

```
discoveredMangaList, discoveredEBookList, discoveredNovelList,
discoverContentType, isDiscoverRefreshing, discoverGridColumns,
showDiscoverMangaContextMenu, contextMenuDiscoverManga, discoverMangaContextMenuAnchorKey,
showDiscoverEBookContextMenu, contextMenuDiscoverEBook, discoverEBookContextMenuAnchorKey,
showDiscoverNovelContextMenu, contextMenuDiscoverNovel, discoverNovelContextMenuAnchorKey
```

**关联 @Builder：** `buildDiscoverContent`（444 行）。

**提取方案：**
```typescript
@Component
export struct DiscoverTabContent {
  @State discoveredMangaList: Manga[] = [];
  @State discoveredEBookList: EBook[] = [];
  @State discoveredNovelList: NovelBook[] = [];
  @State discoverContentType: DiscoverContentType = 'all';
  @State isDiscoverRefreshing: boolean = false;
  // ... 上下文菜单状态（可用 ContextMenuState 类封装）

  @Prop themeState!: ThemeAwareState;
  @Prop gridColumns: number = 3;

  build() { /* 迁移 buildDiscoverContent 的 444 行 */ }
}
```

**预估收益：** 减少 15 个 @State + 6 个发现页多选状态，提取 ~500 行。

---

#### G. 设置/系统（23 变量，lines 656-1359）

图源管理相关变量：
```
sourceList, filteredSourceList, sourceSearchKeyword, showSourceSearchDialog,
sourceSearchInput, searchTargetSource, sourceSearchTypes, selectedSourceSearchType,
sourceSearchPlaceholder, isLoadingSourceList, hasSourceUpdate, sourceViewMode,
sourceTypeFilter
```

**关联 @Builder：** `buildSourceContent`（384 行）、`buildSourceGridCard`（220 行）。

**提取方案：** 提取为 `SourceManagementTab` 组件。

---

#### H. 隐私/认证（9 变量，lines 566-574）

```
isPrivacyMode, showPrivacyAuthDialog, privacyAuthDialogVisible, privacyAuthDialogMode,
privacyAuthPasswordInput, privacyAuthPasswordConfirmInput, privacyAuthShowPassword,
privacyAuthErrorMessage, privacyAuthSubmitting
```

**关联 @Builder：** `buildPrivacyAuthDialog`（~100 行）。

**提取方案：**
```typescript
@Component
export struct PrivacyAuthDialog {
  @State privacyAuthDialogMode: PrivacyAuthMode = 'verify';
  @State privacyAuthPasswordInput: string = '';
  @State privacyAuthPasswordConfirmInput: string = '';
  @State privacyAuthShowPassword: boolean = false;
  @State privacyAuthErrorMessage: string = '';
  @State privacyAuthSubmitting: boolean = false;

  @Link isPrivacyMode: boolean;  // 双向绑定回父组件

  onSuccess?: () => void;

  build() { /* 迁移 buildPrivacyAuthDialog */ }
}
```

**预估收益：** 减少 9 个 @State，提取 ~150 行。

---

#### I. 其他可提取区域

| 区域 | 变量数 | @Builder | 提取难度 |
|------|--------|----------|---------|
| 代理设置 | 6 | buildProxyConfigDialog + 3 子 builder | 低 |
| 源仓库管理 | 11 | buildSourceRepoDialog (234行) | 低 |
| 底部栏动画 | 10 | buildHorizontalTabIndicator* | 中 |
| 最近阅读 | 4 | buildRecentReadingSection | 低 |
| 导航/标签页 | 6 | buildNavDestination | 中 |

---

### 2.3 MainMenuPage 整体提取路线图

```
Phase 1（低风险，高收益）：
  ├─ SuwayomiTabContent         → -20 @State, -700 行
  ├─ BookSourceTabContent       → -17 @State, -700 行
  ├─ PrivacyAuthDialog          → -9 @State, -150 行
  └─ 三重模式通用化             → -32 @State（41→9）

Phase 2（中风险，高收益）：
  ├─ ShelfManagerPanel          → -53 @State, -1500 行
  ├─ DiscoverTabContent         → -21 @State, -500 行
  └─ SourceManagementTab        → -13 @State, -400 行

Phase 3（中风险，中收益）：
  ├─ MangaListState @Observed   → -23 @State → 2 对象
  ├─ LibraryFilterState @Observed
  └─ BottomBarAnimationState    → -10 @State

Phase 4（低风险，低收益）：
  ├─ ProxyConfigDialog          → -6 @State
  ├─ SourceRepoDialog           → -11 @State
  └─ RecentReadingSection       → -4 @State
```

**Phase 1 完成后预期：** 308 → ~200 个装饰器（减少 35%）
**全部完成后预期：** 308 → ~50 个装饰器（减少 84%）

---

## 3. UnifiedDetailPage.ets — 164 个 @State 变量

### 3.1 装饰器分布

| 装饰器 | 数量 |
|--------|------|
| `@State` | 164 |
| 其他 | 0 |

所有状态都是 `@State`，没有任何父组件绑定（`@Prop`/`@Link`）。组件完全自包含。

### 3.2 对话框状态分析

164 个 @State 中，**约 150+ 个用于对话框管理**。每个对话框遵循相同的模式：

```typescript
// 对话框通用模式（每个对话框 4-37 个变量）
@State showXxxDialog: boolean = false;        // 显示控制
@State xxxDialogOpacity: number = 0;          // 动画透明度
@State xxxDialogScale: number = 0.95;         // 动画缩放
@State xxxDialogTranslateY: number = 100;     // 动画位移
// ... 对话框特有的业务状态（0-33 个）
```

### 3.3 十大对话框详细分析

#### 对话框 1：朗读缓存对话框（37 变量，lines 351-387）

**这是全文件最大的状态集群。**

```
showReadAloudCacheDialog, readAloudCacheDialogOpacity, readAloudCacheDialogScale,
readAloudCacheDialogTranslateY, readAloudCacheSummary, isReadAloudCacheLoading,
isReadAloudCacheExpanded, readAloudCacheDialogActiveTab, readAloudCacheSelectionMode,
readAloudCacheRangeStart, readAloudCacheRangeEnd, readAloudCacheSelectedChapters,
readAloudCacheChapterListExpanded, readAloudCacheTaskSettings,
readAloudCacheManageChapterIndex, readAloudCacheManageDetail,
isReadAloudCacheManageLoading, isReadAloudCacheManageMutating,
readAloudCacheManageChapterSectionExpanded, readAloudCacheManageTargetSectionExpanded,
readAloudCacheManageSourceSectionExpanded, readAloudCacheManageSelectedTargetIndex,
readAloudCacheManageBlockedSuggestionKeys, readAloudCacheManageStatusMessage,
readAloudCachePresetDraftName, readAloudCachePresetStatusMessage,
isReadAloudCurrentSettingsSaving, isReadAloudPrecaching,
readAloudPrecachingStatusText, readAloudPrecachingDetailText,
readAloudPrecachingChapterOrder, readAloudPrecachingChapterTotal,
readAloudPrecachingSegmentDone, readAloudPrecachingSegmentTotal,
readAloudPrecachingBytes, appGuideStep, appGuideHighlightRect
```

**关联 @Builder（19 个，~1,800 行）：**
`buildReadAloudCacheDialog`, `buildReadAloudCacheDialogTabButton`,
`buildReadAloudCacheDialogFooter`, `buildReadAloudCacheManagementTab`,
`buildReadAloudCacheCoverageCard`, `buildReadAloudCacheManageChapterRow`,
`buildReadAloudCacheTargetSegmentRow`, `buildReadAloudCacheSourceSegmentRow`,
`buildReadAloudCacheChapterSelectionTab`, `buildReadAloudCacheDialogChapterRow`,
`buildReadAloudCacheChoiceChip`, `buildReadAloudCacheMiMoVoiceSelector`,
`buildReadAloudCacheMiMoStyleSelector`, `buildReadAloudCacheTextInput`,
`buildReadAloudCacheNumberInput`, `buildReadAloudCacheJsonInput`,
`buildReadAloudCacheToggleRow`, `buildReadAloudCacheSettingsTab`,
`buildReadAloudCachePreviewRow`, `buildReadAloudCacheMetric`

**关联 Handler 方法（~700 行）：** lines 4294-5000

**提取方案：**
```typescript
@Component
export struct ReadAloudCacheDialogComponent {
  // 对话框可见性通过父组件控制
  @Link isVisible: boolean;

  // 对话框内部状态（37 变量全部移入）
  @State dialogOpacity: number = 0;
  @State dialogScale: number = 0.95;
  @State dialogTranslateY: number = 100;
  @State activeTab: ReadAloudCacheTab = 'selection';
  @State selectionMode: ReadAloudCacheSelectionMode = 'range';
  // ... 其余 32 个

  // 数据回调
  onCacheTaskCreated?: (task: ReadAloudCacheTask) => void;

  build() {
    // 迁移 19 个 @Builder（~1,800 行）
  }

  // 迁移 handler 方法（~700 行）
}
```

**预估收益：** 减少 37 个 @State，提取 ~2,500 行（全文件 14%）。

---

#### 对话框 2：小说设置对话框（32 变量，lines 421-452）

```
showNovelSettingsDialog, novelSettingsDialogOpacity, novelSettingsDialogScale,
novelSettingsDialogTranslateY, novelEnableReadWhileDownload, novelDefaultLoadChapters,
novelEnableDirectoryParsing, novelEnableReplaceRules, novelSettingsActiveTab,
novelDirectoryParsingSelection, novelReplaceRulesSelection, novelTocRules,
novelReplaceRules, novelSelectedTocRuleIds, novelSelectedReplaceRuleIds,
novelAppliedTocRuleIds, novelAppliedReplaceRuleIds, novelDirectoryRulesDirty,
novelReplaceRulesDirty, isApplyingNovelDirectoryParsing, isApplyingNovelReplaceRules,
ebookInfoTitle, ebookInfoAuthor, ebookInfoPublisher, ebookInfoPublishDate,
ebookInfoIsbn, ebookInfoLanguage, ebookInfoDescription, ebookInfoTagsText,
ebookInfoCoverPath, ebookInfoDirty, isSavingEBookInfo
```

**关联 @Builder（8 个，~500 行）：**
`buildNovelSettingsDialog`, `buildNovelSettingsTabButton`,
`buildNovelPrefetchSettingsTab`, `buildNovelDirectorySettingsTab`,
`buildNovelReplaceRuleSettingsTab`, `buildEBookInfoTextInput`,
`buildEBookInfoTextArea`, `buildEBookInfoEditTab`

**预估收益：** 减少 32 个 @State，提取 ~1,000 行。

---

#### 对话框 3：跟踪设置对话框（24 变量，lines 508-531）

```
trackingRule, trackingExecution, isTrackingLoading, isTrackingBusy,
trackingSupported, trackingUnsupportedReason, showTrackingSettingsDialog,
trackingDialogOpacity, trackingDialogScale, trackingDialogTranslateY,
trackingSettingsActiveTab, trackingCheckIntervalText, trackingCheckIntervalUnit,
trackingMinNewItemsText, trackingAutoDownloadCountText, trackingConditionMatchMode,
trackingRequireFavorite, trackingExcludeNSFW, trackingTitleKeywordText,
trackingTagKeywordText, trackingSourceKeywordText, trackingEnableNotify,
trackingAutoCreateAttempted, trackingAutoCreatedThisSession
```

**关联 @Builder（16 个，~1,200 行）**

**预估收益：** 减少 24 个 @State，提取 ~900 行。

---

#### 对话框 4-10（剩余对话框）

| 对话框 | 变量数 | @Builder 行数 | Handler 行数 | 总提取行数 |
|--------|--------|-------------|-------------|----------|
| 下载对话框 | 13 | ~1,037 | ~200 | ~1,100 |
| 换源对话框 | 13 | ~412 | ~300 | ~750 |
| 缓存确认对话框 | 9 | ~70 | ~50 | ~130 |
| 加入书架对话框 | 7 | ~188 | ~50 | ~250 |
| 生成封面对话框 | 7 | ~127 | ~50 | ~200 |
| 替换书籍对话框 | 5 | ~150 | ~50 | ~150 |
| 小说设置关闭确认 | 4 | ~114 | ~30 | ~130 |

---

### 3.4 UnifiedDetailPage 通用对话框动画抽象

所有 10 个对话框共享相同的动画模式（Opacity + Scale + TranslateY）。可以提取为通用基类：

```typescript
@Observed
class DialogAnimationState {
  opacity: number = 0;
  scale: number = 0.95;
  translateY: number = 100;

  animateIn(uiContext: UIContext): void {
    uiContext.animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.opacity = 1;
      this.scale = 1;
      this.translateY = 0;
    });
  }

  animateOut(uiContext: UIContext, onComplete?: () => void): void {
    uiContext.animateTo({ duration: 200, curve: Curve.EaseIn }, () => {
      this.opacity = 0;
      this.scale = 0.95;
      this.translateY = 100;
    });
    setTimeout(() => onComplete?.(), 200);
  }
}
```

每个对话框只需：
```typescript
@State animation = new DialogAnimationState();
// 替代原来的 4 个变量：showDialog, dialogOpacity, dialogScale, dialogTranslateY
```

**预估收益：** 每个对话框减少 3 个 @State（10 个对话框共减少 30 个），同时消除 ~100 行重复动画代码。

---

### 3.5 UnifiedDetailPage 提取路线图

```
✅ Phase 1（最大收益）：
  ├─ ReadAloudCacheDialogComponent    → -37 @State, -2500 行
  ├─ NovelSettingsDialogComponent     → -32 @State, -1000 行
  └─ TrackingSettingsDialogComponent  → -24 @State, -900 行

✅ Phase 2（中等收益）：
  ├─ DownloadDialogComponent          → -13 @State, -1100 行
  ├─ ChangeSourceDialogComponent      → -13 @State, -750 行
  └─ DialogAnimationState 通用化      → -5 @State（仅对剩余 4 个对话框生效）

✅ Phase 3（低收益，低风险）：
  ├─ CacheConfirmDialogComponent      → -5 @State
  ├─ AddToShelfDialogComponent        → -2 @State
  ├─ GenerateCoverDialogComponent     → -3 @State
  ├─ ReplaceBookDialogComponent       → -1 @State
  └─ NovelCloseConfirmDialogComponent → 跳过（代码中不存在）
```

**实际结果：** 164 → 75 个 @State（减少 54%），17,545 → 8,910 行（减少 49%）
**注：** 实际 @State 减少量低于理论估算，因信号 prop/回调 prop/非对话框业务状态无法压缩

---

## 4. EpubWebViewReaderComponent.ets — ~~7663~~ 5,106 行（Phase 1 完成）

### 4.1 装饰器分布

| 装饰器 | 数量 | 行号 |
|--------|------|------|
| `@State` | 24 | 595-625 |
| `@Prop` | 3 | 479-481 |
| `@Watch` | 1 | 481 |
| 私有实例字段 | 62+ | 483-627 |

**注意：** 此文件的 @State 数量（24）远少于前两个文件，但问题在于 **62 个私有实例字段** 和 **8 个功能子系统** 全部挤在一个组件中。

### 4.2 八大功能子系统

#### 子系统 A：WebView 管理 / Spine 加载（~2,300 行）

**私有字段（13 个）：**
```
webviewController, ready, webControllerAttached, lastLoadedFileUrl,
pendingPageOffset, pendingSpinePath, pendingAnchorFragment,
activeSpineLayoutType, activeSpineMediaType, aboutBlankReloadTimer,
aboutBlankReloadCount, pendingSpineTransition, universalAccessRootSignature
```

**关键方法：** `loadSpineItemImmediate`, `configureUniversalAccessRoot`,
`resolveUniversalAccessRoots`, `scheduleAboutBlankReload`, `handleAboutBlankPageEnd`,
`queryViewportThenInject`, `applyInjectedLayout`, `buildBridgeJs`, `normalizeFileUrl`

**提取难度：** 高 — 这是整个组件的核心，所有其他子系统都依赖 WebView。

**提取方案：** 不提取为独立组件，而是提取为 `WebViewManager` 控制器类：
```typescript
class EpubWebViewManager {
  private controller: webview.WebviewController;
  private ready: boolean = false;
  private lastLoadedFileUrl: string = '';

  async loadSpineItem(path: string, offset?: number): Promise<void> { /* ... */ }
  async injectLayout(css: string, bridgeJs: string): Promise<void> { /* ... */ }
  async runJavaScript(script: string): Promise<string> { /* ... */ }

  // 回调通知组件
  onReady?: () => void;
  onPageEnd?: (url: string) => void;
  onError?: (code: number, desc: string) => void;
}
```

---

#### 子系统 B：卷曲动画 / 翻页效果（~700 行，32 变量）

**@State（14 个）：**
```
viewportOpacity, viewportMatrix, showEpubCurlSnapshotCover, showEpubCurlEffect,
hideWebViewForEpubCurlCapture, epubCurlCanvasReady, epubCurlProgress,
epubCurlRenderToken, epubCurlAnimateTarget, epubCurlAnimateVelocity,
epubCurlIsForward, epubCurlStartPosition, epubCurlTouchX, epubCurlTouchY
```

**私有字段（18 个）：**
```
epubCurlCurrentPixelMap, epubCurlNextPixelMap, epubCurlAnimationTimer,
epubCurlReleaseTimer, epubCurlInteractiveActive, epubCurlInteractiveReady,
epubCurlInteractiveEndPending, epubCurlInteractiveEndComplete,
epubCurlInteractiveOriginalPage, epubCurlInteractiveTargetPage,
epubCurlPendingProgress, epubCurlLastProgress, epubCurlLastProgressAt,
epubCurlReleaseVelocity, epubCurlReleaseAnimating, epubCurlReleaseComplete,
readerSwipeSuppressedUntil, epubCurlEffectConfig
```

**关联 @Builder：** `buildEpubCurlLayer`（62 行）

**耦合点：**
- 读取 `currentPage`（页面导航子系统）
- 调用 `commitPageChangeAsync`（页面导航子系统）
- 操作 `viewportOpacity`/`viewportMatrix`（与页面导航共享）
- 需要 `activePageSettings`（CSS 子系统）

**提取方案：**
```typescript
@Component
export struct EpubCurlEffectLayer {
  // 14 个 @State 全部移入
  @State showEpubCurlEffect: boolean = false;
  @State epubCurlProgress: number = 0;
  // ...

  // 通过 @Link 绑定共享状态
  @Link viewportOpacity: number;
  @Link viewportMatrix: string;
  @Prop currentPage: number = 0;
  @Prop totalPages: number = 0;

  // 回调
  onPageTurn?: (direction: 'forward' | 'backward') => void;
  onSpineTransition?: (targetSpine: string) => void;
  captureSnapshot?: () => Promise<image.PixelMap | null>;

  build() {
    this.buildEpubCurlLayer()  // 迁移自原组件
  }
}
```

**预估收益：** 减少 14 个 @State + 18 个私有字段，提取 ~700 行。

---

#### 子系统 C：高亮/注解系统（~1,300 行，29 变量）

**@State（16 个）：**
```
webSelectedText, showHighlightThoughtPopup, highlightThoughtPopupText,
highlightThoughtPopupIsPlaceholder, highlightThoughtPopupEditing,
highlightThoughtPopupInputText, highlightThoughtPopupQuoteText,
highlightThoughtPopupHighlightId, highlightThoughtPopupColor,
highlightThoughtPopupLineType, highlightThoughtPopupLeftVp,
highlightThoughtPopupTopVp, highlightThoughtPopupMaskOpacity,
highlightThoughtPopupOpacity, highlightThoughtPopupScale, highlightThoughtPopupTranslateY
```

**私有字段（12 个）：**
```
webSelectionSnapshot, webSelectionRefreshTimer, webSelectionActionInProgress,
pendingThoughtPopupStartOffset, pendingThoughtPopupEndOffset,
pendingThoughtPopupQuoteText, pendingThoughtPopupRetryCount,
pendingThoughtPopupTimer, suppressNextTapEvent, suppressNextTapResetTimer,
highlightThoughtPopupTimer, highlightThoughtPopupHideTimer
```

**关联 @Builder：** `buildHighlightThoughtPopupLayer`（201 行）、`buildWebTextSelectionMenuWithSymbol`（51 行）

**耦合点：**
- 需要 WebView 的 `runJavaScript` 能力（通过回调注入 JS）
- 依赖分页状态（`currentPage`、`totalPages`）
- 与阅读交互子系统共享 `suppressNextTapEvent`

**提取方案：**
```typescript
@Component
export struct EpubHighlightOverlay {
  @State showThoughtPopup: boolean = false;
  @State popupText: string = '';
  @State popupColor: string = '#FFEB3B';
  @State popupLineType: HighlightLineType = 'solid';
  // ... 其余 12 个 @State

  @Prop @Watch('onRangesChange') epubHighlightRanges!: EpubHighlightRange[];

  // WebView JS 注入回调
  runJavaScript?: (script: string) => Promise<string>;

  // 高亮操作回调
  onHighlightAdded?: (range: EpubHighlightRange) => void;
  onHighlightDeleted?: (id: string) => void;
  onThoughtSubmitted?: (id: string, thought: string) => void;

  build() {
    Column() {
      this.buildHighlightThoughtPopupLayer()
      this.buildWebTextSelectionMenuWithSymbol()
    }
  }
}
```

**预估收益：** 减少 16 个 @State + 12 个私有字段，提取 ~1,300 行。

---

#### 子系统 D：页面导航/分页（~900 行，11 私有字段）

```
currentPageCount, currentPage, isPageTurnAnimating, boundarySwitchTimer,
currentLayoutKind, lastPaginationOffset, lastPaginationMaxOffset,
lastPaginationPageExtent, lastProgressRatio, lastBoundarySwitchTime,
boundarySuppressionUntil
```

**提取难度：** 高 — 与 WebView 加载和卷曲动画深度耦合。

**方案：** 不独立提取为组件，而是封装为 `EpubPageNavigator` 控制器类，与 `EpubWebViewManager` 协作。

---

#### 子系统 E：CSS/布局引擎（~650 行，0 @State）

**私有字段（16 个）：**
```
activeTextSettings (18 子字段), activePageSettings, hostWidthVp, hostHeightVp,
fallbackVpW, fallbackVpH, lastVpW, lastVpH, lastVisualVpW, lastVisualVpH,
lastVisualVpScale, applySettingsTimer, pendingSettingsReapplyReason,
pageTurnPhaseTimer, paintStabilizeTimer
```

**关键方法：** `buildReflowCss`, `buildFixedCss`, `buildFontCss`, `buildBackgroundCss`

**提取方案：** 纯函数工具类，零耦合：
```typescript
class EpubCssBuilder {
  static buildReflowCss(textSettings: EpubTextSettings, pageSettings: EpubPageSettings): string { /* ... */ }
  static buildFixedCss(pageSettings: EpubPageSettings, viewportW: number, viewportH: number): string { /* ... */ }
  static buildFontCss(textSettings: EpubTextSettings): string { /* ... */ }
  static buildBackgroundCss(pageSettings: EpubPageSettings): string { /* ... */ }
  static resolveFontFamily(family: string): string { /* ... */ }
  static resolveTextAlignment(alignment: string): string { /* ... */ }
}
```

**预估收益：** 提取 ~650 行，减少 16 个私有字段。**零风险。**

---

#### 子系统 F：视口动画引擎（~340 行，0 @State）

**关键方法：** `buildMatrix`, `resetViewportTransform`, `applyViewportState`,
`createAnimationProfile`, `createTextSafeAnimationProfile`

**提取方案：** 纯函数工具类：
```typescript
class EpubAnimationEngine {
  static buildMatrix(type: string, progress: number, width: number, height: number): string { /* ... */ }
  static createAnimationProfile(type: string, direction: string): AnimationProfile { /* ... */ }
}
```

**预估收益：** 提取 ~340 行。**零风险。**

---

#### 子系统 G：TTS/朗读桥接（~200 行，0 @State）

嵌入在 `buildAnnotationBridgeJs` 中的 JS 函数。可以提取为独立的 JS 字符串常量或工具方法。

---

#### 子系统 H：阅读器交互事件（~115 行）

```
handleReaderTap, handleReaderPan, handleReaderPanUpdate, handleReaderPanEnd,
handleReaderPanCancel, handleReaderSwipe
```

与卷曲动画和高亮系统共享 `suppressNextTapEvent` 和 `readerSwipeSuppressedUntil`。

---

### 4.3 EpubWebViewReaderComponent 提取路线图

```
Phase 1（零风险，纯函数提取）：                               ✅ 已完成
  ├─ EpubCssBuilder 工具类        → -16 私有字段, -650 行    ✅
  ├─ EpubAnimationEngine 工具类   → -340 行                  ✅
  └─ BridgeJsBuilder 工具类       → -1,630 行（JS 字符串生成） ✅

Phase 2（中风险，UI 组件提取）：
  ├─ EpubHighlightOverlay 组件    → -16 @State, -1300 行
  └─ EpubCurlEffectLayer 组件     → -14 @State, -700 行

Phase 3（高风险，控制器提取）：
  ├─ EpubWebViewManager 类        → -13 私有字段, -1000 行
  └─ EpubPageNavigator 类         → -11 私有字段, -900 行
```

**Phase 1 实际结果：** 7,663 行 → 5,106 行（减少 33%），零状态变量变更。
**全部完成后预期：** 7,663 行 → ~2,500 行（减少 67%），24 @State → ~8 @State。

> **注：** BridgeJsBuilder 实际提取量（1,630 行）远超初始估计（800 行），因为 `buildAnnotationBridgeJs`（854 行）和 `buildBridgeJs`（782 行）均为大型纯 JS 模板字符串。

---

## 5. 通用优化模式

### 5.1 @Observed 类封装模式

**适用场景：** 多个相关 `@State` 变量形成逻辑分组。

**ArkTS API：** `@Observed` 装饰器 + `@ObjectLink` 属性装饰器。

```typescript
// 定义可观察类
@Observed
class DialogState {
  isVisible: boolean = false;
  animation: DialogAnimationState = new DialogAnimationState();

  open(): void { this.isVisible = true; this.animation.animateIn(); }
  close(): void { this.animation.animateOut(() => { this.isVisible = false; }); }
}

// 在组件中使用
@Component
export struct MyComponent {
  @State dialogA = new DialogState();  // 1 个 @State 替代 4 个
  @State dialogB = new DialogState();  // 1 个 @State 替代 4 个

  build() {
    Column() {
      Button('打开A').onClick(() => this.dialogA.open())
      if (this.dialogA.isVisible) {
        this.buildDialogA()
      }
    }
  }
}
```

**注意：** `@Observed` 类的属性变更不会自动触发外层组件的 `build()`。如果需要在属性变更时更新 UI，需要配合 `@ObjectLink` 在子组件中使用：

```typescript
@Component
struct DialogView {
  @ObjectLink state: DialogState;  // 属性变更会触发此组件的 build()

  build() {
    Column() { /* ... */ }
      .opacity(this.state.animation.opacity)
  }
}
```

### 5.2 子组件提取模式

**适用场景：** `@Builder` 方法 + 其独占的 `@State` 变量形成独立 UI 区域。

**ArkTS API：** `@Component struct` + `@Prop` / `@Link` / 回调函数。

```typescript
// 子组件定义
@Component
export struct ChildPanel {
  // 从父组件单向接收
  @Prop themeState!: ThemeAwareState;
  @Prop gridColumns: number = 3;

  // 子组件内部状态（从父组件迁移）
  @State items: Item[] = [];
  @State isLoading: boolean = false;
  @State selectedId: string = '';

  // 双向绑定（需要时）
  @Link selectedItemId: string;

  // 回调通知父组件
  onItemSelected?: (item: Item) => void;
  onItemDeleted?: (id: string) => void;

  build() {
    // 迁移自父组件的 @Builder
  }
}

// 父组件中使用
@Component
export struct ParentPage {
  @State selectedItemId: string = '';

  build() {
    Column() {
      ChildPanel({
        themeState: this.themeState,
        gridColumns: this.responsive_gridColumns,
        selectedItemId: $selectedItemId,  // 双向绑定
        onItemSelected: (item) => this.handleSelection(item),
        onItemDeleted: (id) => this.handleDelete(id)
      })
    }
  }
}
```

### 5.3 控制器类提取模式

**适用场景：** 大量私有方法和字段构成独立的业务逻辑，但不直接对应 UI。

```typescript
// 控制器类（非组件，无 @State）
class BusinessController {
  private state: InternalState;
  private timer: number = -1;

  // 操作方法
  async fetchData(): Promise<void> { /* ... */ }
  processResult(data: RawData): ProcessedData { /* ... */ }

  // 回调通知组件刷新
  onDataChanged?: (data: ProcessedData) => void;
  onError?: (error: Error) => void;

  // 生命周期
  destroy(): void {
    if (this.timer !== -1) clearTimeout(this.timer);
  }
}

// 组件中使用
@Component
export struct MyComponent {
  private controller: BusinessController = new BusinessController();

  aboutToAppear(): void {
    this.controller.onDataChanged = (data) => {
      // 更新 @State 触发 UI 刷新
      this.displayData = data;
    };
  }

  aboutToDisappear(): void {
    this.controller.destroy();
  }
}
```

---

## 6. 推荐实施顺序

### 优先级矩阵

| 优先级 | 文件 | 任务 | 收益 | 风险 | 工作量 |
|--------|------|------|------|------|--------|
| ~~P0~~ | ~~EpubWebView~~ | ~~EpubCssBuilder 提取~~ | ~~中~~ | ~~零~~ | ~~小~~ ✅ |
| ~~P0~~ | ~~EpubWebView~~ | ~~EpubAnimationEngine 提取~~ | ~~中~~ | ~~零~~ | ~~小~~ ✅ |
| ~~P0~~ | ~~EpubWebView~~ | ~~BridgeJsBuilder 提取~~ | ~~高~~ | ~~零~~ | ~~小~~ ✅ |
| P1 | MainMenuPage | SuwayomiTabContent 提取 | 高 | 低 | 中 |
| P1 | MainMenuPage | BookSourceTabContent 提取 | 高 | 低 | 中 |
| P1 | UnifiedDetailPage | ReadAloudCacheDialog 提取 | 高 | 低 | 中 |
| P2 | MainMenuPage | 三重模式通用化 | 高 | 中 | 中 |
| P2 | UnifiedDetailPage | NovelSettingsDialog 提取 | 中 | 低 | 中 |
| P2 | UnifiedDetailPage | TrackingSettingsDialog 提取 | 中 | 低 | 中 |
| P2 | EpubWebView | EpubHighlightOverlay 提取 | 高 | 中 | 大 |
| P2 | EpubWebView | EpubCurlEffectLayer 提取 | 高 | 中 | 大 |
| P3 | MainMenuPage | ShelfManagerPanel 提取 | 高 | 高 | 大 |
| P3 | MainMenuPage | DiscoverTabContent 提取 | 中 | 中 | 中 |
| P3 | UnifiedDetailPage | 剩余 7 个对话框提取 | 中 | 低 | 中 |
| P3 | UnifiedDetailPage | DialogAnimationState 通用化 | 中 | 低 | 小 |
| P4 | EpubWebView | WebViewManager 控制器 | 高 | 高 | 大 |
| P4 | EpubWebView | PageNavigator 控制器 | 中 | 高 | 大 |

### 每个 Phase 的预期效果

| Phase | MainMenuPage @State | UnifiedDetailPage @State | EpubWebView 行数 |
|-------|-------------------|------------------------|-----------------|
| ~~当前~~ | 308 | ~~164~~ | ~~7,663~~ |
| ~~Phase 1 完成~~ | ~230 | ~~~70~~ → 实际 85 | ~~5,900~~ → 实际 **5,106** |
| ~~Phase 2 完成~~ | ~150 | ~~~25~~ → 实际 80 | ~3,900 |
| ~~Phase 3 完成~~ | ~80 | ~~~25~~ → 实际 **75** | ~2,500 |
| Phase 4 完成 | ~50 | 75 | ~2,500 |

**UnifiedDetailPage 实际进度（2026-05-07）：**
- 行数：17,545 → 8,910（-49%）
- @State：164 → 75（-54%）
- 已提取组件：ReadAloudCacheDialog, NovelSettingsDialog, TrackingSettingsDialog, DownloadDialog, ChangeSourceDialog, CacheConfirmDialog, GenerateCoverDialog, AddToShelfDialog, ReplaceBookDialog
- 通用化：DialogAnimationState 工具类
- 注：实际 @State 高于理论估算，因信号 prop、回调 prop、以及非对话框业务状态（书架/章节/推荐等）无法进一步压缩

**EpubWebViewReaderComponent 实际进度（2026-05-07）：**
- 行数：7,663 → 5,106（-33%）
- @State：24（不变，Phase 1 为纯函数提取）
- 已提取工具类：EpubCssBuilder（797 行）, EpubAnimationEngine（332 行）, BridgeJsBuilder（~1,630 行）
- 所有提取均为 thin delegation wrapper 模式，私有方法签名不变
- Phase 1 完成，Phase 2（UI 组件提取）待启动

### 关键约束

1. **每次只提取一个组件**，确保编译通过后再进行下一个
2. **先提取零耦合的纯函数**（CSS Builder、Animation Engine），建立信心
3. **对话框提取时保留原方法签名**作为 deprecated wrapper，逐步迁移调用点
4. **使用 `@Prop` 而非 `@Link`** 传递只读数据，减少双向绑定的复杂度
5. **每个提取的子组件必须有独立的 aboutToDisappear 清理逻辑**

---

## 7. 组件提取编译修复记录（2026-05-07）

组件提取后产生的编译错误已全部修复，四个文件结构验证通过（brace depth = 0）。

### 7.1 NovelSettingsDialogComponent.ets

- **问题**：提取后遗留孤儿代码（方法体外的代码片段），缺失导入和回调
- **修复**：
  - 删除孤儿代码（原 1245-1263 行）
  - 添加 `TrackingSettingsDialogComponent` 导入
  - 添加缺失回调：`getCurrentNovelSourceId`、`isCurrentLocalImportedContent`
  - 添加追踪状态：`trackingLoadSignal`、`trackingCardState`、`trackingCardCallbacks`
  - 更新 `build()` 方法集成 `TrackingSettingsDialogComponent`

### 7.2 ReadAloudCacheDialogComponent.ets

- **问题**：`buildReadAloudCacheSection()` 和 `buildReadAloudCacheDialog()` 缺少 `@Builder` 装饰器
- **修复**：在两个方法前添加 `@Builder` 装饰器

### 7.3 UnifiedDetailPage.ets

- **问题**：提取后删除了仍被引用的 `@State` 变量；SymbolGlyph `.fontColor()` 类型不匹配
- **修复**：
  - 恢复 `appGuideStep` 和 `appGuideHighlightRect` 的 `@State` 声明
  - 所有 SymbolGlyph `.fontColor()` 调用改为数组格式：`.fontColor([...])`

### 7.4 MainMenuPage.ets

- **问题**：提取过程中产生重复方法实现（24 个方法各出现两次），文件中存在两个 `build()` 方法
- **修复**：
  - 从 git 恢复被误删的 `initializeAndLoadBookSources` 和 `openBookDetail` 方法
  - 删除 548 行重复代码块（含重复的 `build()` 方法和 24 个重复方法实现）
  - 文件从 32,272 行 → 29,272 行（-9.3%）

### 7.5 联合编译修复（2026-05-07 第二轮）

修复 106 个编译错误，涉及 14 个文件，所有文件 brace depth = 0。

**DialogAnimationState.ets**：提取构造参数内联类型为 `DialogAnimationStateParams` 接口，字段类型改为 `Curve | ICurve`

**SuwayomiTabContent.ets**：`.then()` 回调参数类型 `string | undefined` → `string | null`

**TrackingSettingsDialogComponent.ets**：
- 添加缺失导入：`Manga`、`RemoteLibraryMangaBridge`、`NovelAdapter`、`NovelBook`、`NovelReadStatus`、`getNovelDataManager`
- 添加缺失方法：`normalizeTrackingText`、`buildDialogChrome`、`getDialogMaskBlurStyle`、`getSectionBackgroundEffect`
- 添加缺失属性：`novelDataManager`、回调 props（`getLocalCoverPath`、`getIsFavorite`、`isOnlineContent`）
- 移除方法上的 `@Watch` 装饰器
- `DialogResult` → `promptAction.ShowDialogSuccessResponse`

**NovelSettingsDialogComponent.ets**：
- 导入 `curves` 模块
- 添加缺失的 `buildNovelSettingsDialog` @Builder 方法
- 移除方法上的 `@Watch` 装饰器
- 修复 `boolean | undefined` → 添加 `?? false` 空值合并
- 修复 `string | undefined` → 添加 `?? ''` 空值合并

**ReadAloudCacheDialogComponent.ets**：
- `initializeThemeAware` 调用修正为正确签名（componentId + state + stateUpdater）
- `isChapterListExpanded` → `readAloudCacheChapterListExpanded`

**BookSourceTabContent.ets**：
- 添加 `componentId` 属性
- `initializeThemeAware`/`cleanupThemeAware` 调用修正为正确签名
- `@Builder` 返回值不能链式调用 `.width()` → 包裹 `Column` 容器

**DownloadDialogComponent.ets / ChangeSourceDialogComponent.ets**：
- 添加 `getDialogChromeTopEdgeColor`/`getDialogChromeBottomEdgeColor` 方法
- `buildDialogChrome` 使用方法调用替代不存在的色值 token
- 移除方法上的 `@Watch` 装饰器
- `NovelSearchResult` 导入源修正为 `../../Models/NovelModels`

**MainMenuPage.ets**：删除已提取到 BookSourceTabContent 的 `initializeAndLoadBookSources` 方法，调用点改为 `bookSourceTabRefreshSignal++`

### 7.6 对话框显示/交互问题修复（2026-05-07 第三轮）

提取后的对话框组件出现"点击按钮后对话框不显示、页面无法交互"的问题。经过 4 轮迭代修复。

**根因分析：** `SourceDialogScaffold` 使用 `position({ x: 0, y: 0 }).width('100%').height('100%')` 实现全屏覆盖。在 `build()` 中使用 `Column()` 或 `Stack()` 包裹 `SourceDialogScaffold` 时，外层容器约束了内部组件的布局，导致对话框不可见或遮罩层拦截了点击事件。

**失败方案：**
1. `Column() { SourceDialogScaffold({}) {...} }.width('100%').height('100%')` → 对话框不可见
2. `Stack() { SourceDialogScaffold({}) {...} }.position(...)` → 遮罩拦截点击
3. `Stack() { SourceDialogScaffold({}) {...} }.width('100%').height('100%')` → 对话框不可见

**最终方案：** 不使用任何包裹容器，直接在 `build()` 中使用 `if/else if/else` 条件渲染，每个分支返回单一根组件：

```typescript
build() {
  if (this.showDialog && this.content) {
    this.buildMainDialog()
  } else if (this.showSubDialog) {
    this.buildSubDialog()
  } else {
    Column()  // 空 fallback，满足 ArkTS 单一根节点要求
  }
}
```

**关键约束：**
- ArkTS `@Entry` 组件的 `build()` 方法只能有一个根节点
- `SourceDialogScaffold` 必须是直接根节点，不能被任何容器包裹
- 使用 `if/else if/else` 满足单一根节点要求，同时支持多对话框切换
- 空 `Column()` 作为 fallback 保证所有分支都有返回值

**适用组件：** NovelSettingsDialogComponent、DownloadDialogComponent、ChangeSourceDialogComponent、ReadAloudCacheDialogComponent、TrackingSettingsDialogComponent（直接调用 `buildTrackingSettingsDialog()`，无包裹）

### 7.7 PrivacyAuthDialogComponent 提取（2026-05-07）

从 MainMenuPage.ets 提取隐私认证对话框为独立组件。

**提取内容：**
- 8 @State 变量 + 2 private 成员 → 组件内部
- 10 个方法（含 1 个 @Builder）→ 组件内部
- `PrivacyAuthDialogMode` 类型定义 → 导出

**父组件变更：**
- 删除 8 @State，新增 2 @State（信号 prop）→ 净减少 6 @State
- `handlePrivacyModeAuth()` 保留，4 处 `openPrivacyAuthDialog()` → `triggerPrivacyAuthDialog()`
- build() 渲染从 Stack 包裹改为 `PrivacyAuthDialogComponent({...})` 直接调用

**关键设计：**
- `isPrivacyMode` 保留在父组件（30+ 处引用）
- `PrivacyModeManager` 单例在组件内部获取，不从父组件传递
- 组件使用 `promptAction.showToast()` 直接显示提示
- 动画保留原有 Stack + opacity/scale/animation 模式（与 DownloadDialogComponent 不同）

**结果：** MainMenuPage.ets 29,236 → 28,954 行（-282），@State 253 → 247（-6）

---

## 8. 整体进度报告（2026-05-07）

### 8.1 三大文件指标对比

| 文件 | 原始行数 | 当前行数 | 减少 | 原始 @State | 当前 @State | 减少 |
|------|---------|---------|------|------------|------------|------|
| MainMenuPage.ets | 32,272 | 28,954 | **-10.3%** | 308 | 247 | **-19.8%** |
| UnifiedDetailPage.ets | 17,545 | 8,914 | **-49.2%** | 164 | 77 | **-53.0%** |
| EpubWebViewReaderComponent.ets | 7,663 | 5,106 | **-33.4%** | 24 | 24 | 0% (Phase 1 纯函数) |

### 8.2 UnifiedDetailPage 提取组件清单（全部完成 ✅）

| 组件 | 行数 | 功能 |
|------|------|------|
| ReadAloudCacheDialogComponent.ets | 3,675 | 朗读缓存管理对话框 |
| NovelSettingsDialogComponent.ets | 1,957 | 小说/电子书设置对话框 |
| TrackingSettingsDialogComponent.ets | 2,024 | 跟踪规则设置对话框 |
| DownloadDialogComponent.ets | 742 | 章节下载对话框 |
| ChangeSourceDialogComponent.ets | 564 | 换源对话框 |
| CacheConfirmDialogComponent.ets | 151 | 缓存确认对话框 |
| GenerateCoverDialogComponent.ets | 175 | 生成封面对话框 |
| AddToShelfDialogComponent.ets | 214 | 加入书架对话框 |
| ReplaceBookDialogComponent.ets | 330 | 替换书籍对话框 |
| DialogAnimationState.ets | 83 | 通用对话框动画状态工具类 |

**合计提取：** 9,915 行（含工具类），@State 从 164 → 77（-53%）

### 8.3 MainMenuPage 提取组件清单

| 组件 | 行数 | 状态 | Phase |
|------|------|------|-------|
| SuwayomiTabContent.ets | 1,612 | ✅ 完成 | Phase 1 |
| BookSourceTabContent.ets | 1,218 | ✅ 完成 | Phase 1 |
| PrivacyAuthDialogComponent.ets | 345 | ✅ 完成 | Phase 1 |
| ShelfManagerPanel | — | ❌ 未启动 | Phase 2 |
| DiscoverTabContent | — | ❌ 未启动 | Phase 2 |
| SourceManagementTab | — | ❌ 未启动 | Phase 2 |
| 三重模式通用化 | — | ❌ 未启动 | Phase 1 |

**已完成：** 3,175 行，@State 从 308 → 247（-19.8%，Phase 1 部分完成）
**剩余工作：** Phase 1 余项（三重模式通用化、PrivacyAuthDialog）+ Phase 2-4

### 8.4 EpubWebView 提取清单

| 工具类 | 行数 | 状态 | Phase |
|--------|------|------|-------|
| EpubCssBuilder.ets | 797 | ✅ 完成 | Phase 1 |
| EpubAnimationEngine.ets | 332 | ✅ 完成 | Phase 1 |
| BridgeJsBuilder.ets | 1,656 | ✅ 完成 | Phase 1 |
| EpubHighlightOverlay | — | ❌ 未启动 | Phase 2 |
| EpubCurlEffectLayer | — | ❌ 未启动 | Phase 2 |

**已完成：** 2,785 行（-33.4%），@State 不变（Phase 1 为纯函数提取）

### 8.5 当前执行阶段

```
✅ 已完成：
  ├─ EpubWebView Phase 1（纯函数提取）        — 3 个工具类，-33% 行数
  ├─ UnifiedDetailPage 全部对话框提取          — 9 个组件 + 1 工具类，-49% 行数，-53% @State
  ├─ MainMenuPage Phase 1 部分（Suwayomi + BookSource + PrivacyAuthDialog）— 3 个组件，-10% 行数，-20% @State
  ├─ DialogAnimationState 通用化工具类
  └─ 全部编译错误修复（106+ 错误）+ 对话框显示修复

🔄 下一步（按优先级）：
  ├─ MainMenuPage Phase 1 余项：三重模式通用化（-32 @State）
  ├─ MainMenuPage Phase 2：ShelfManagerPanel（-53 @State）、DiscoverTabContent（-21 @State）
  ├─ EpubWebView Phase 2：EpubHighlightOverlay、EpubCurlEffectLayer
  └─ MainMenuPage Phase 3-4：SourceManagementTab、@Observed 封装等
```

### 8.6 经验总结

1. **对话框提取模式**：`@Prop` 信号触发 + `@Watch` 加载 + `if/else if/else` 单根渲染
2. **SourceDialogScaffold 不能被包裹**：任何外层 Column/Stack 都会破坏全屏覆盖定位
3. **@Watch 只能装饰 @State/@Prop/@Link 声明**：不能放在方法上
4. **ThemeAwareHelper 正确签名**：`initializeThemeAware(componentId, state, callback?, stateUpdater?)`
5. **ThemeAwareState 实例化**：`new ThemeAwareState()`，无 `createDefaultState` 方法
6. **ArkTS 单一根节点**：`build()` 中用 `if/else if/else` + 空 `Column()` fallback
