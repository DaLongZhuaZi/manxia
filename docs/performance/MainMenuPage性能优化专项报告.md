# MainMenuPage 性能优化专项报告

> 分析环境：HarmonyOS ArkTS API23（SDK 6.1.0(23)）
> 分析时间：2026-05-08
> 最后更新：2026-05-08
> 目标文件：`entry/src/main/ets/pages/MainMenuPage.ets`

---

## 一、现状总览

| 指标 | 当前值 | 推荐值 | 评级 |
|------|--------|--------|------|
| 文件行数 | 28,960 | <3,000 | 🔴 极度超标 |
| 文件大小 | ~1.04MB | <100KB | 🔴 极度超标 |
| @State 变量 | 241个 | <20个 | 🔴 极度超标 |
| @Builder 方法 | 148个 | — | 🔴 职责过多 |
| ForEach 使用 | 48处 | — | 🟡 需要优化 |
| LazyForEach 使用 | **0处** | 大列表必须使用 | 🔴 缺失 |
| 独立子组件 | **0个** | 多个 | 🔴 全部内联 |

**核心矛盾：** 一个 `@Entry @Component struct MainMenuPage` 承载了 8 个 Tab 的全部 UI 逻辑、70+ 页面路由、148 个 @Builder 方法、241 个响应式状态变量，构成了一个"上帝组件"。

---

## 二、组件结构剖析

### 2.1 Tab 体系

`build()` 方法（第28514行）构建如下层级：

```
Stack (根)
  ├── GlobalBackgroundLayer
  └── Navigation(pathStack)
       └── Stack
            ├── Column
            │    └── Swiper(tabsController)    ← 用 Swiper 而非 Tabs
            │         └── ForEach(cachedVisibleTabConfigs)
            │              └── buildTabContentForIndex(cfg.index)
            ├── 浮层：搜索按钮、隐私退出、书架预览滑块等
            └── 导航栏：顶栏/底栏/侧栏（自适应）
  .navDestination(buildNavDestination)  ← 70+ 页面路由的 if-else 链
```

8 个 Tab 的内容全部由 `buildTabContentForIndex`（第27096行）分发：

| TabIndex | 名称 | 内容来源 | @Builder 方法数 | 行数范围 |
|----------|------|----------|-----------------|----------|
| 0 | HOME | 内联 @Builder | ~8 | 10841-11260 |
| 1 | LIBRARY | 内联 @Builder | **~65** | 12132-19630 |
| 2 | DISCOVER | 内联 @Builder | ~10 | 23940-24387 |
| 3 | SOURCE | 内联 @Builder | ~15 | 24745-25960 |
| 4 | BOOK_SOURCE | 外部组件 `BookSourceTabContent` | 1 | — |
| 5 | SUWAYOMI | 外部组件 `SuwayomiTabContent` | 1 | — |
| 6 | SETTINGS | 内联 @Builder | ~5 | 26286-26855 |
| 7 | KOMGA | 外部组件 `MainMenuKomgaTabContent` | 1 | — |

**Library Tab 是最大问题**：独占 ~65 个 @Builder 方法、约 7,500 行代码，涵盖默认视图、分类/书架视图、动态筛选、多选工具栏、右键菜单、封面渲染等全部逻辑。

### 2.2 导航路由

`buildNavDestination`（第26857行）是一个约 214 行的 if-else 链，路由 **70+ 页面**，包括：

- 漫画/电子书/小说的阅读器和详情页
- 15+ 设置子页面
- Suwayomi/Komga 浏览、详情、阅读页面
- 小说相关页面（搜索、详情、朗读、源管理等）
- 系统页面（数据管理、备份、日志、关于等）

### 2.3 最大的 @Builder 方法

| 方法 | 行号 | 行数 | 说明 |
|------|------|------|------|
| `buildShelfDetailDisplayFloatingBar` | 1018 | ~2,080 | 书架详情浮动栏（手势、动画、显示模式） |
| `buildSourceUsageGuide` | 3103 | ~1,737 | 图源使用指引面板 |
| `buildEBookCard` | 21166 | ~1,272 | 电子书列表卡片（含手势、动画） |
| `buildMangaCard` | 12718 | ~685 | 漫画列表卡片 |
| `buildCustomShelfMixedList` | 17715 | ~585 | 自定义书架混合列表 |
| `buildSettingsContent` | 26380 | ~425 | 设置页内容 |
| `buildDiscoverContent` | 23940 | ~446 | 发现/历史页内容 |
| `build()` | 28514 | ~434 | 主构建方法 |

---

## 三、@State 变量深度分析

### 3.1 按作用域分类

| 作用域 | 变量数 | 占比 | 说明 |
|--------|--------|------|------|
| **SHARED（全局共享）** | 47 | 19.5% | 主题、隐私、导航、响应式布局、底栏动画、窗口过渡 |
| **Library Tab** | 126 | **52.3%** | 漫画/电子书/小说数据+筛选+多选+书架管理+右键菜单 |
| **Discover Tab** | 24 | 10.0% | 发现页筛选+数据+多选+右键菜单 |
| **Source Tab** | 39 | 16.2% | 图源管理+代理配置+仓库同步+右键菜单 |
| **Home Tab** | 5 | 2.1% | 最近阅读+Banner |

**关键发现：** Library Tab 独占 126 个 @State 变量，超过总量的一半。即使用户当前不在 Library Tab，这些变量仍然占用内存并参与变更检测。

### 3.2 重复模式识别（可合并 ~60 个变量）

#### 模式 A：多选状态 ×4（25 个变量 → 5 个）

```typescript
// 当前：4 套完全相同的结构
isMultiSelectMode: boolean          // Manga
selectedMangaIds: Set<string>
isDeletingManga: boolean
isEBookMultiSelectMode: boolean     // EBook
selectedEBookIds: Set<string>
isDeletingEBook: boolean
isNovelMultiSelectMode: boolean     // Novel
selectedNovelIds: Set<string>
isDeletingNovel: boolean
isDiscoverMultiSelectMode: boolean  // Discover（4个）
selectedDiscoverMangaIds: Set<string>
selectedDiscoverEBookIds: Set<string>
selectedDiscoverNovelIds: Set<string>

// 建议合并为：
@Observed
class MultiSelectState {
  isActive: boolean = false
  selectedIds: Set<string> = new Set()
  isDeleting: boolean = false
}
// 按内容类型 Map 管理，或直接复用单一实例
```

#### 模式 B：滑动手势状态 ×3（9 个变量 → 3 个）

```typescript
// 当前：Manga/EBook/Novel 各一套
activeSwipeId / isSwipeActive / swipeOffset  × 3

// 建议：UI 层面同一时刻只有一个 item 可被滑动，合并为单一 SwipeState
```

#### 模式 C：右键菜单状态 ×6（20 个变量 → 3 个）

```typescript
// 当前：Source/Manga/EBook/Novel/DiscoverManga/DiscoverEBook/DiscoverNovel 各一套
showXxxContextMenu + contextMenuXxx + xxxContextMenuAnchorKey  × 6~7

// 建议：同一时刻只能有一个右键菜单打开
@Observed
class ContextMenuState {
  visible: boolean = false
  item: Manga | EBook | NovelBook | SourceInfo | null = null
  anchorKey: string = ''
}
```

#### 模式 D：加载/刷新状态（9 个变量 → 1 个 Map）

```typescript
// 当前：散落各处
isLoadingMangaList / isLoadingEbookList / isLoadingNovelList / isLoadingSourceList / isLoadingRecentReading
isRefreshing / isRefreshingHome / isRefreshingDiscover / isRefreshingSourceList

// 建议：
loadingStates: Map<string, boolean> = new Map()
// 例如 loadingStates.get('manga'), loadingStates.get('discover')
```

#### 模式 E：移动操作状态（4 个变量 → 1 个对象）

```typescript
// 当前：4 个独立变量
movingMangaId / movingEBookId / movingNovelId / movingContentType

// 建议：
moveOperation: { id: string, contentType: string } | null = null
```

### 3.3 合并效果预估

| 合并项 | 当前变量数 | 合并后 | 节省 |
|--------|-----------|--------|------|
| 多选状态 | 25 | 5 | 20 |
| 滑动手势 | 9 | 3 | 6 |
| 右键菜单 | 20 | 3 | 17 |
| 加载状态 | 9 | 1 | 8 |
| 移动操作 | 4 | 1 | 3 |
| 排序类型 | 2 | 1 | 1 |
| 书架筛选重叠 | 21 | ~14 | 7 |
| **合计** | **90** | **28** | **~62** |

合并后 @State 总数：241 → **~179 个**。进一步拆分组件后，每个子组件只需持有自己作用域的变量。

---

## 四、渲染性能问题

### 4.1 ForEach 全景分析（48处，LazyForEach 0处）

#### 按严重程度分级

**🔴 严重 — 大列表 + 内联 filter（6处）**

| 行号 | 数据源 | 内联 filter | 容器 | 问题 |
|------|--------|-------------|------|------|
| 18305 | `filteredMangaList.filter(...)` | ✅ `categoryManager.isItemInCategory()` | Grid | 全量漫画列表每次渲染都 filter |
| 18327 | `filteredEbookList.filter(...)` | ✅ 同上 | Grid | 同上（电子书） |
| 18349 | `filteredNovelList.filter(...)` | ✅ 同上 | Grid | 同上（小说） |
| 18803 | `filteredMangaList.filter(...)` | ✅ 重复实现 | Grid | 与18305完全重复 |
| 18820 | `filteredEbookList.filter(...)` | ✅ 重复实现 | Grid | 与18327完全重复 |
| 18837 | `filteredNovelList.filter(...)` | ✅ 重复实现 | Grid | 与18349完全重复 |

> 这6处是最严重的性能问题。`categoryManager.isItemInCategory()` 对每个 item 调用一次，假设库中有 1000 部漫画，每次渲染执行 1000 次分类判断。两套代码路径（`buildCategoryXxxList` 和 `buildCategoryContentList`）实现完全相同的功能，属于代码重复。

**🔴 严重 — 大列表 + ForEach（无 LazyForEach）（12处）**

| 行号 | 数据源 | 说明 | 建议 |
|------|--------|------|------|
| 12265 | `getLibraryDefaultMixedItems()` | 混合列表，4个 filteredList 合并，可能上千项 | LazyForEach |
| 12280 | `getLibraryDefaultMixedItems()` | 同上，Grid 视图 | LazyForEach |
| 17248 | `getShelfFilteredMangaList()` | 书架内漫画列表 | LazyForEach |
| 17276 | `getShelfFilteredEBookList()` | 书架内电子书列表 | LazyForEach |
| 17283 | `getShelfFilteredPdfEBookList()` | 书架内 PDF 列表 | LazyForEach |
| 17311 | `getShelfFilteredNovelList()` | 书架内小说列表 | LazyForEach |
| 17719 | `getCustomShelfMixedItems()` | 自定义书架混合列表 | LazyForEach |
| 18857 | `filteredMangaList` | 直接遍历全量漫画 | LazyForEach |
| 24279 | `discoveredMangaList` | 发现页漫画（全量副本） | LazyForEach |
| 24308 | `discoveredEBookList` | 发现页电子书 | LazyForEach |
| 24337 | `discoveredNovelList` | 发现页小说 | LazyForEach |
| 25066/25079 | `filteredSourceList` | 图源列表/网格 | LazyForEach |

> **关键问题：** `getLibraryDefaultMixedItems()` 在每次渲染时被调用 **2次**（第12259行检查 `.length`，第12280行 ForEach），每次都重新遍历4个列表并合并。

**🟡 中等 — 中等列表（10处）**

| 行号 | 数据源 | 说明 |
|------|--------|------|
| 16396 | `getFilteredDynamicItems(allItems)` | 标签/作者筛选结果，可能上百 |
| 23847 | `allTags` | 全部标签，可能上百 |
| 23908 | `allAuthors` | 全部作者，可能上百 |
| 25454 | `sourceList` | 全部图源 |
| 13861 | `typeShelves.filter(...)` | 书架类型，2-10个但有内联 filter |
| 24668 | `tabConfigs.filter(...)` | Tab 配置，7个但有内联 filter |

**🟢 无问题 — 小列表（20处）**

最近阅读（3处，~5-20项）、Tab 配置（6处，3-7项）、Banner（1处，3项）、仓库/日志（2处）、弹窗选项（8处）。

### 4.2 核心渲染瓶颈路径

```
用户滑动/翻页
  → @State filteredMangaList 变化
    → 触发所有引用 filteredMangaList 的 @Builder 重渲染
      → buildCategoryMangaList (18305): 对全量列表执行 filter + ForEach
      → buildCategoryContentList (18803): 再次对全量列表执行 filter + ForEach（重复）
      → buildLibraryMangaGridContent (18857): 再次 ForEach
      → buildLibraryDefaultExpandedContent (12265/12280): 调用 getLibraryDefaultMixedItems() × 2
```

**一次 filteredMangaList 变化可能触发 6+ 个 ForEach 遍历全量列表。**

---

## 五、分阶段执行方案

### 阶段零：零风险快速收益（1-2天）

**目标：** 不改变组件结构，仅优化数据计算层，消除最严重的渲染瓶颈。

#### 0.1 预计算分类筛选结果

**问题：** 第18305/18327/18349/18803/18820/18837行在 ForEach 数据源中内联 `.filter(categoryManager.isItemInCategory())`。

**方案：** 将 filter 结果提升为 `@State` 变量，在数据变化时预计算。

```typescript
// 新增 @State
@State categoryFilteredMangaList: Manga[] = []
@State categoryFilteredEbookList: EBook[] = []
@State categoryFilteredNovelList: NovelBook[] = []

// 在 filteredMangaList / selectedCategoryId 变化时更新
// 用 @Watch 或在赋值 filteredMangaList 的方法中同步更新
private updateCategoryFilteredLists(): void {
  const catId = this.selectedCategoryId
  if (!catId) {
    this.categoryFilteredMangaList = this.filteredMangaList
    this.categoryFilteredEbookList = this.filteredEbookList
    this.categoryFilteredNovelList = this.filteredNovelList
    return
  }
  this.categoryFilteredMangaList = this.filteredMangaList.filter(
    (m: Manga) => categoryManager.isItemInCategory(m.id, catId)
  )
  // ... ebook, novel 同理
}
```

**收益：** 消除每帧 6 次 `isItemInCategory` 调用循环，filter 仅在数据变化时执行一次。

#### 0.2 消除 `getLibraryDefaultMixedItems()` 重复调用

**问题：** 第12259行和第12280行各调用一次，每次遍历4个列表。

**方案：** 将结果缓存为 `@State` 变量，在数据源变化时更新。

```typescript
@State libraryDefaultMixedItems: ShelfMixedItem[] = []

// 在 mangaList/ebookList/pdfEbookList/novelList/filter 变化时更新
```

**收益：** 从每次渲染 2次全量遍历 → 0次（使用预计算结果）。

#### 0.3 消除 buildCategoryXxxList 与 buildCategoryContentList 重复

**问题：** `buildCategoryMangaList`(18305) 和 `buildCategoryContentList`(18803) 实现完全相同的 filter 逻辑。

**方案：** `buildCategoryContentList` 直接复用 `categoryFilteredMangaList` 等预计算结果，删除重复的 filter 代码。

**预期效果：** 渲染时 ForEach 全量遍历次数从 6+ 降至 3（每种内容类型一次）。

---

### 阶段一：引入 LazyForEach（3-5天）

**目标：** 对所有大列表（>50项）替换 ForEach 为 LazyForEach，仅渲染可见区域。

#### 1.1 实现通用 DataSource

```typescript
// 新建 entry/src/main/ets/components/LazyForEachDataSource.ets
@Observed
class GenericDataSource<T> implements IDataSource {
  private items: T[] = []
  private listeners: DataChangeListener[] = []

  setItems(items: T[]): void {
    this.items = items
    this.listeners.forEach(listener => listener.onDataReloaded())
  }

  totalCount(): number { return this.items.length }
  getData(index: number): T { return this.items[index] }
  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener)
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) this.listeners.splice(index, 1)
  }
}
```

#### 1.2 替换优先级

| 优先级 | 位置 | 数据源 | 预期数据量 | 操作 |
|--------|------|--------|-----------|------|
| P0 | 12265/12280 | `libraryDefaultMixedItems` | 上千 | ForEach → LazyForEach |
| P0 | 18305/18803 | `categoryFilteredMangaList` | 上千 | ForEach → LazyForEach |
| P0 | 18327/18820 | `categoryFilteredEbookList` | 上千 | ForEach → LazyForEach |
| P0 | 18349/18837 | `categoryFilteredNovelList` | 上千 | ForEach → LazyForEach |
| P1 | 17248-17311 | 书架内列表 | 上百 | ForEach → LazyForEach |
| P1 | 17719 | 自定义书架混合列表 | 上百 | ForEach → LazyForEach |
| P1 | 24279/24308/24337 | 发现页列表 | 上百 | ForEach → LazyForEach |
| P2 | 25066/25079 | 图源列表 | 50-200 | ForEach → LazyForEach |

#### 1.3 Grid 容器适配

ArkTS API23 中 `Grid` 组件支持 `LazyForEach`，需要确保容器设置了 `.cachedCount()`：

```typescript
Grid() {
  LazyForEach(this.mangaDataSource, (item: Manga, index: number) => {
    this.buildMangaGridCard(item)
  }, (item: Manga) => item.id)
}
.cachedCount(10)  // 预缓存 10 个 item
.columnsTemplate('1fr 1fr 1fr')
.width('100%')
```

**预期效果：** 首屏渲染时间大幅降低，滚动流畅度显著提升。

---

### 阶段二：状态合并与 @Observed 重构（5-7天）

**目标：** 消除重复模式，将 241 个 @State 降至 ~180 个以下。

#### 2.1 提取 MultiSelectState

```typescript
// 新建 entry/src/main/ets/models/MultiSelectState.ets
@Observed
export class MultiSelectState {
  isActive: boolean = false
  selectedIds: Set<string> = new Set()
  isDeleting: boolean = false

  toggle(id: string): void {
    if (this.selectedIds.has(id)) {
      this.selectedIds.delete(id)
    } else {
      this.selectedIds.add(id)
    }
    this.isActive = this.selectedIds.size > 0
  }

  clear(): void {
    this.selectedIds = new Set()
    this.isActive = false
    this.isDeleting = false
  }
}
```

替换 MainMenuPage 中 4 套多选状态：

```typescript
// 替换前（25 个变量）
@State isMultiSelectMode: boolean = false
@State selectedMangaIds: Set<string> = new Set()
// ... × 4 套

// 替换后（4 个对象，但通过 @Observed 自动触发子组件更新）
@State mangaMultiSelect: MultiSelectState = new MultiSelectState()
@State ebookMultiSelect: MultiSelectState = new MultiSelectState()
@State novelMultiSelect: MultiSelectState = new MultiSelectState()
@State discoverMultiSelect: MultiSelectState = new MultiSelectState()
```

#### 2.2 提取 ContextMenuState

```typescript
@Observed
export class ContextMenuState<T> {
  visible: boolean = false
  item: T | null = null
  anchorKey: string = ''

  show(item: T, anchorKey: string): void {
    this.item = item
    this.anchorKey = anchorKey
    this.visible = true
  }

  hide(): void {
    this.visible = false
    this.item = null
    this.anchorKey = ''
  }
}
```

替换 6 套右键菜单状态（20 个变量 → 6 个对象）。

#### 2.3 合并 SwipeState

```typescript
@Observed
export class SwipeGestureState {
  activeId: string = ''
  isActive: boolean = false
  offset: number = 0
  readonly threshold: number = 80

  reset(): void {
    this.activeId = ''
    this.isActive = false
    this.offset = 0
  }
}
```

替换 3 套滑动状态（9 个变量 → 3 个对象）。

#### 2.4 合并 LoadingState

```typescript
// 替换 9 个散落的 boolean
@State loadingStates: Map<string, boolean> = new Map()

// 使用方式
this.loadingStates.set('manga', true)
// 读取
this.loadingStates.get('manga') ?? false
```

> **注意：** ArkTS 中 `@State` 对 Map 不深度监听。需配合 `new Map(this.loadingStates)` 赋值触发更新，或改用 `@Observed` 包装的 Map 类。建议在阶段二中评估是否需要引入 ObservableMap。

---

### 阶段三：组件拆分（7-10天）

**目标：** 将 MainMenuPage 从 28,960 行拆分为多个独立组件，每个组件管理自己的 @State。

#### 3.1 拆分方案总览

```
MainMenuPage (保留 ~3,000 行)
├── HomeTabContent              (~300 行)  ← 提取自 buildHomeContent
├── LibraryTabContent           (~2,000 行) ← 最大，进一步拆分
│   ├── LibraryDefaultView      (~800 行)
│   ├── LibraryCategoryView     (~400 行)
│   ├── LibraryShelfDetailView  (~400 行)
│   └── LibraryMultiSelectToolbar (~200 行)
├── DiscoverTabContent          (~500 行)  ← 提取自 buildDiscoverContent
├── SourceTabContent            (~800 行)  ← 提取自 buildSourceContent
├── SettingsTabContent          (~500 行)  ← 提取自 buildSettingsContent
├── NavigationBars              (~400 行)  ← 顶栏/底栏/侧栏
├── ContextMenuOverlay          (~300 行)  ← 统一的右键菜单层
└── GuideOverlay                (~200 行)  ← 引导/教程覆盖层
```

#### 3.2 拆分原则

1. **数据下沉：** 每个子组件只接收自己需要的数据，通过 `@Prop` 或 `@ObjectLink` 传入
2. **状态归属：** Tab 级别的 @State 移入对应子组件（如 `showLibraryFilterDialog` 只在 LibraryTabContent 中使用）
3. **事件上报：** 子组件通过回调函数向父组件通知状态变化
4. **共享状态保留：** 主题、导航、响应式布局等全局状态保留在 MainMenuPage

#### 3.3 LibraryTabContent 拆分细节

Library Tab 是最大的拆分目标。拆分后：

**LibraryTabContent**（容器组件）
- 持有：`libraryContentType`, `libraryFilterType`, `libraryViewMode`, `libraryDefaultSortType`
- 持有：`mangaList`, `ebookList`, `novelList`, `pdfEbookList` 及其 filtered 版本
- 持有：`bookshelfCategories`, `typeShelves`
- 职责：数据加载、筛选逻辑、子视图分发

**LibraryDefaultView**
- 持有：`showLibraryFilterDialog`, `showLibrarySortPopup`, `showLibraryGridSettingsPopup`
- 接收：filtered 列表数据（通过 `@ObjectLink` 或 `@Prop`）
- 职责：默认网格/列表视图渲染

**LibraryCategoryView**
- 持有：`showCategoryDetail`, `selectedCategoryId`, 分类对话框状态
- 持有：书架管理相关状态（`showAddShelfDialog`, `addShelfDialogStep` 等）
- 职责：分类/书架卡片网格、书架详情

**LibraryShelfDetailView**
- 持有：`customShelfSortType`, `customShelfTags`, `customShelfAuthors`, 筛选弹窗状态
- 接收：当前书架数据
- 职责：书架详情页、自定义书架筛选

**LibraryMultiSelectToolbar**
- 持有：`MultiSelectState` 对象
- 接收：选中项数据
- 职责：多选工具栏（删除、移动、导出等）

#### 3.4 预期效果

| 指标 | 拆分前 | 拆分后 |
|------|--------|--------|
| MainMenuPage 行数 | 28,960 | ~3,000 |
| MainMenuPage @State | 241 | ~50（仅全局共享） |
| 最大子组件行数 | — | ~2,000（LibraryTabContent） |
| 非活跃 Tab 的重渲染 | 全部参与 | 仅容器组件 |

---

### 阶段四：深层优化（持续改进）

#### 4.1 buildNavDestination 路由优化

当前 214 行 if-else 链可改为 Map 查表：

```typescript
private readonly routeMap: Map<string, (param: ESObject) => void> = new Map([
  ['MangaReaderPage', (p) => MangaReaderPage({ manga: p.manga })],
  ['EBookReaderPage', (p) => EBookReaderPage({ ebook: p.eBook })],
  // ...
])

@Builder
buildNavDestination(name: string, param: ESObject) {
  const builder = this.routeMap.get(name)
  if (builder) {
    builder(param)
  } else {
    Text(`Unknown route: ${name}`)
  }
}
```

#### 4.2 getLibraryDefaultMixedItems 结果缓存

当前每次调用都重新遍历 4 个列表并合并。改为在数据源变化时预计算：

```typescript
@State libraryDefaultMixedItems: ShelfMixedItem[] = []

// 在 mangaList/ebookList/novelList/pdfEbookList 或 filter 变化时
@Watch('onLibraryDataChange')
onLibraryDataChange(): void {
  this.libraryDefaultMixedItems = this.computeMixedItems()
}
```

#### 4.3 发现页数据去副本化

当前 `discoveredMangaList` 是 `mangaList` 的完整副本（第5689-5691行）。如果仅用于展示，可改为引用 filteredMangaList 配合不同的筛选条件，避免内存双倍占用。

#### 4.4 响应式布局状态精简

13 个 `responsive_*` 变量中，部分可合并为对象：

```typescript
@Observed
class ResponsiveState {
  gridColumns: number = 3
  gridGap: number = 8
  contentPadding: number = 12
  isLandscape: boolean = false
  tabBarPosition: BarPosition = BarPosition.End
  tabBarVertical: boolean = false
  viewportWidth: number = 0
  viewportHeight: number = 0
}
```

---

## 六、执行路线图

```
阶段零（1-2天）─── 零风险快速收益
  ├─ 0.1 预计算分类筛选结果（消除6处内联filter）
  ├─ 0.2 缓存 getLibraryDefaultMixedItems（消除2次重复调用）
  └─ 0.3 消除 buildCategoryXxxList 重复代码
  预期：渲染时 ForEach 全量遍历从 6+ 降至 3

阶段一（3-5天）─── LazyForEach 引入
  ├─ 1.1 实现通用 DataSource
  ├─ 1.2 替换 P0 级 ForEach（6处大列表）
  ├─ 1.3 替换 P1 级 ForEach（6处中等列表）
  └─ 1.4 替换 P2 级 ForEach（2处图源列表）
  预期：首屏渲染时间降低 50%+，滚动流畅度显著提升

阶段二（5-7天）─── 状态合并
  ├─ 2.1 提取 MultiSelectState（25→5变量）
  ├─ 2.2 提取 ContextMenuState（20→3变量）
  ├─ 2.3 合并 SwipeState（9→3变量）
  ├─ 2.4 合并 LoadingState（9→1变量）
  └─ 2.5 合并移动/排序等杂项（6→2变量）
  预期：@State 从 241 降至 ~179

阶段三（7-10天）─── 组件拆分
  ├─ 3.1 提取 HomeTabContent
  ├─ 3.2 提取 LibraryTabContent（最大任务）
  ├─ 3.3 提取 DiscoverTabContent
  ├─ 3.4 提取 SourceTabContent
  ├─ 3.5 提取 SettingsTabContent
  ├─ 3.6 提取 NavigationBars
  └─ 3.7 提取 ContextMenuOverlay / GuideOverlay
  预期：MainMenuPage 降至 ~3,000行/~50个@State

阶段四（持续）─── 深层优化
  ├─ 4.1 路由查表化
  ├─ 4.2 发现页去副本化
  └─ 4.3 响应式状态精简
```

---

## 七、风险与注意事项

### 7.1 ArkTS API23 约束

- `@State` 对 `Map`/`Set` 只做浅层引用比较，合并 LoadingState 时需配合 `new Map()` 赋值或 `@Observed` 包装
- `LazyForEach` 要求 `IDataSource` 接口实现，`getData()` 返回值必须稳定（同一 index 返回同一对象引用）
- `@Observed` + `@ObjectLink` 是 API23 推荐的深度观察方案，但 `@ObjectLink` 要求装饰的变量类型必须被 `@Observed` 装饰

### 7.2 拆分兼容性

- `@Provide`/`@Inject` 用于跨层级传递数据，拆分后子组件可通过 `@Inject('NavPathStack')` 获取导航栈
- 已有外部组件（BookSourceTabContent、SuwayomiTabContent、MainMenuKomgaTabContent）的集成方式不受影响
- `Swiper` + `SwiperController` 的 Tab 切换机制在拆分后仍可用，子组件作为 `@Builder` 的返回值传入

### 7.3 测试策略

- 每个阶段完成后进行回归测试，重点关注：
  - Tab 切换是否正常
  - 多选操作是否正确
  - 右键菜单是否正常弹出/关闭
  - 书架管理（创建/编辑/删除/排序）是否正常
  - 响应式布局切换（横竖屏、手机/平板）是否正常
- 阶段一完成后重点测试大列表滚动性能
- 阶段三完成后测试内存占用变化

---

## 八、优化进度追踪

> 最后更新：2026-05-08

### 8.1 当前指标

| 指标 | 优化前 | 当前值 | 变化 |
|------|--------|--------|------|
| 文件行数 | 28,960 | 28,529 | -431 |
| @State 变量 | 241 | 221 | -20 |
| ForEach 使用 | 48 | 33 | -15 |
| LazyForEach 使用 | 0 | 18 | +18 |
| 独立子组件 | 0 | 3 | +3 |

### 8.2 已完成优化

#### 阶段零：零风险快速收益 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 预计算分类筛选结果 | ✅ | categoryMangaDS, categoryEbookDS, categoryNovelDS |
| 缓存 getLibraryDefaultMixedItems | ✅ | libraryDefaultMixedDS |
| 消除 buildCategoryXxxList 重复代码 | ✅ | 复用预计算结果 |

#### 阶段一：LazyForEach 引入 ✅

| 任务 | 状态 | 说明 |
|------|------|------|
| 实现通用 DataSource | ✅ | `entry/src/main/ets/Utils/BasicDataSource.ets` |
| 替换 P0 级 ForEach | ✅ | 书库默认列表、分类列表 |
| 替换 P1 级 ForEach | ✅ | 书架内列表、自定义书架 |
| 发现页 ForEach → LazyForEach | ✅ | discoveredMangaDS, discoveredEBookDS, discoveredNovelDS |
| 图源列表 ForEach → LazyForEach | ✅ | sourceListDS |

#### 阶段二：状态合并 ✅

| 任务 | 状态 | 文件 |
|------|------|------|
| 提取 MultiSelectState | ✅ | `entry/src/main/ets/Utils/MultiSelectState.ets` |
| 提取 ContextMenuState | ✅ | `entry/src/main/ets/Utils/ContextMenuState.ets` |
| 合并 SwipeState | ✅ | `entry/src/main/ets/Utils/SwipeGestureState.ets` |
| 合并 LoadingState | ✅ | `entry/src/main/ets/Utils/LoadingState.ets` |
| 合并 MoveState | ✅ | `entry/src/main/ets/Utils/MoveState.ets` |

#### 阶段三：组件拆分（部分完成）

| 任务 | 状态 | 文件 | 说明 |
|------|------|------|------|
| 提取 HomeTabContent | ✅ | `entry/src/main/ets/components/HomeTabContent.ets` | 已集成 |
| 提取 SettingsTabContent | ✅ | `entry/src/main/ets/components/SettingsTabContent.ets` | 已集成 |
| 提取 DiscoverTabContent | ✅ | `entry/src/main/ets/components/DiscoverTabContent.ets` | 已集成 |
| 提取 SourceTabContent | ❌ | — | 功能过于复杂，回退使用原有 buildSourceContent |
| 提取 LibraryTabContent | ❌ | — | 最大任务，126 个状态变量，待进行 |
| 提取 NavigationBars | ❌ | — | 待进行 |
| 提取 ContextMenuOverlay | ❌ | — | 待进行 |

### 8.3 新增文件清单

```
entry/src/main/ets/Utils/
├── BasicDataSource.ets          # 通用 LazyForEach 数据源
├── MultiSelectState.ets         # 多选状态管理（@Observed）
├── SwipeGestureState.ets        # 滑动手势状态管理（@Observed）
├── ContextMenuState.ets         # 右键菜单状态管理（@Observed）
├── LoadingState.ets             # 加载/刷新状态管理（@Observed）
└── MoveState.ets                # 移动操作状态管理（@Observed）

entry/src/main/ets/components/
├── HomeTabContent.ets           # 首页Tab组件
├── SettingsTabContent.ets       # 设置Tab组件
└── DiscoverTabContent.ets       # 发现Tab组件
```

### 8.4 未完成任务

#### 高优先级

| 任务 | 预期收益 | 难度 | 说明 |
|------|----------|------|------|
| 提取 LibraryTabContent | 减少 ~7500 行 | 高 | 最大任务，涉及 126 个状态变量和 ~65 个 @Builder 方法 |

#### 中优先级（已完成评估）

| 任务 | 预期收益 | 难度 | 状态 | 说明 |
|------|----------|------|------|------|
| 提取 NavigationBars | 减少 ~400 行 | 中 | ❌ 放弃 | 代码与 MainMenuPage 紧密耦合，提取风险大 |
| 提取 ContextMenuOverlay | 减少 ~300 行 | 中 | ❌ 放弃 | 右键菜单涉及大量业务逻辑，提取风险大 |

#### 低优先级（阶段四 - 已完成评估）

| 任务 | 预期收益 | 难度 | 状态 | 说明 |
|------|----------|------|------|------|
| 路由查表化 | 代码可读性 | 低 | ❌ 不可行 | ArkTS @Builder 不支持动态组件渲染 |
| 发现页去副本化 | 内存占用 | 中 | ⏸️ 待评估 | discoveredMangaList 是 mangaList 的完整副本 |
| 响应式状态精简 | 变量数量 | 低 | ❌ 放弃 | 9 个 responsive_* 变量被广泛使用，提取风险大 |

### 8.5 经验教训

1. **图源标签页不适合简单提取**：SourceTabContent 涉及大量业务逻辑（搜索对话框、代理配置、仓库同步、上下文菜单等），简单提取会导致功能缺失。建议采用渐进式重构，先提取子模块。

2. **LibraryTabContent 是最大挑战**：独占 126 个 @State 变量和 ~65 个 @Builder 方法，需要进一步拆分为子组件（LibraryDefaultView、LibraryCategoryView、LibraryShelfDetailView 等）。

3. **状态合并效果显著**：通过 MultiSelectState、ContextMenuState 等 @Observed 类，成功将 241 个 @State 减少到 221 个，减少了重复模式。

4. **导航栏不适合提取**：顶栏/底栏/侧栏代码与 MainMenuPage 紧密耦合（访问 pathStack、themeState、各种业务方法），提取需要传递大量属性和回调，得不偿失。

5. **路由查表化不可行**：ArkTS 的 @Builder 装饰器不支持动态组件渲染，无法使用 Map 查表的方式替代 if-else 链。

6. **响应式状态不适合合并**：9 个 responsive_* 变量被广泛使用（在 30+ 处引用），合并为对象会增加代码复杂度，收益不大。

7. **小列表不需要 LazyForEach**：剩余的 ForEach（Tab配置 3-7项、Banner 3项、书架封面 3-6项等）都是小列表，使用 LazyForEach 反而会增加复杂度，没有性能收益。

---

*报告生成时间：2026-05-08*
*最后更新：2026-05-08*
