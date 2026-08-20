// 文件路径: src/main/ets/Framework/Components/BookSourceTabContent.ets
// 职责: 书源标签页内容组件，从MainMenuPage提取的独立组件

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { common } from '@kit.AbilityKit';
import { promptAction, curves } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { TabContentCacheManager, BookSourceCacheData } from '../Cache/TabContentCacheManager';
import { ContentFilterManager } from '../Managers/ContentFilterManager';
import { getNovelSourceManager, NovelSourceManager } from '../Novel/NovelSourceManager';
import { LegadoBookSourceType } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import {
  LegadoCompatibilityEngineMode,
  LegadoCompatibilityStatus,
  LegadoExecutionTraceSummary,
  LegadoWorkflowKind
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import { getNovelInitializer } from '../Novel/NovelInitializer';
import { NovelBook, NovelReadStatus, NovelSearchResult, NovelSourceInfo } from '../../Models/NovelModels';
import { NovelSearchPageParams } from '../../pages/NovelBookshelfPage';
import {
  LegadoExploreDetailOpenResult,
  LegadoExploreDetailOpenStatus,
  openLegadoExploreDetail
} from '../Novel/LegadoExploreDetailNavigator';
import { SettingsPageSurfaceManager } from '../../pages/settings/SettingsPageSurfaceManager';
import { AvifImage } from '../../components/AvifImage';
import { DataManager } from '../Data/DataManager';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';

const TAG = 'BookSourceTabContent';

export interface ExploreKind {
  title: string;
  url: string;
}

export interface BookSourceLoadOptions {
  loadBooks?: boolean;
  silent?: boolean;
}

export enum LibraryViewMode {
  LIST = 'list',
  GRID = 'grid',
  CATEGORY = 'category'
}

enum BookSourceTypeFilter {
  ALL = 'all',
  TEXT = 'text',
  IMAGE = 'image',
  AUDIO = 'audio'
}

@Component
export struct BookSourceTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 125;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @Prop @Watch('onSfwFilterChanged') sfwFilterSignal: number = 0;
  @Prop @Watch('onPickerCloseSignalChanged') pickerCloseSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  // 主题状态
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = `BookSourceTabContent_${Date.now()}`;
  // 书源Tab相关状态
  @State bookSourceList: NovelSourceInfo[] = [];
  @State filteredBookSourceList: NovelSourceInfo[] = [];
  @State bookSourceSearchKeyword: string = '';
  @State selectedBookSourceId: string = '';
  @State selectedBookSourceName: string = '';
  @State bookSourceExploreKinds: ExploreKind[] = [];
  @State bookSourceExploreError: string = '';
  @State bookSourceExploreTraceSummary: string = '';
  @State selectedBookSourceKindIndex: number = 0;
  @State bookSourceBooks: NovelSearchResult[] = [];
  @State isLoadingBookSource: boolean = false;
  @State isRefreshingBookSource: boolean = false;
  @State bookSourceCurrentPage: number = 1;
  @State bookSourceHasMore: boolean = true;
  @State @Watch('onBookSourcePickerVisibilityChanged') showBookSourcePicker: boolean = false;
  @State bookSourceViewMode: LibraryViewMode = LibraryViewMode.LIST;
  @State bookSourceSearchInput: string = '';
  @State isBookSourceSearchMode: boolean = false;
  @State bookSourceKindsExpanded: boolean = false;
  @State bookSourceRefreshHintVisible: boolean = false;
  @State selectedBookSourceTypeFilter: BookSourceTypeFilter = BookSourceTypeFilter.ALL;
  @State selectedBookSourceGroupFilter: string = '';
  // 私有字段
  private bookSourceRefreshHintTimer: number = -1;
  private bookSourceListScroller: Scroller = new Scroller();
  private bookSourceModuleInitialized: boolean = false;
  private bookSourceCacheRestored: boolean = false;
  private bookSourceCacheRestorePromise: Promise<void> | null = null;
  private contentFilterManager: ContentFilterManager = ContentFilterManager.getInstance();
  private tabContentCacheManager: TabContentCacheManager = TabContentCacheManager.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  // Every source selection starts a new generation. Async kind/book requests
  // must prove they still belong to that generation before touching UI state.
  private bookSourceSelectionGeneration: number = 0;

  private beginBookSourceSelection(sourceId: string): number {
    this.bookSourceSelectionGeneration++;
    logger.debug(TAG, `书源选择代次更新: generation=${this.bookSourceSelectionGeneration};source=${sourceId}`);
    return this.bookSourceSelectionGeneration;
  }

  private isBookSourceSelectionCurrent(sourceId: string, generation: number): boolean {
    return generation === this.bookSourceSelectionGeneration && sourceId === this.selectedBookSourceId;
  }

  // ============ 生命周期 ============

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState);
    void this.ensureBookSourceCacheReady();
    void this.loadBookSourceViewMode();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    if (this.bookSourceRefreshHintTimer !== -1) {
      clearTimeout(this.bookSourceRefreshHintTimer);
    }
  }

  onRefreshSignalChanged(): void {
    void this.initializeAndLoadBookSources();
  }

  onSfwFilterChanged(): void {
    this.filterBookSourceList(this.bookSourceSearchKeyword);
  }

  onPickerCloseSignalChanged(): void {
    if (this.showBookSourcePicker) {
      this.showBookSourcePicker = false;
    }
  }

  onBookSourcePickerVisibilityChanged(): void {
    if (!this.showBookSourcePicker) {
      this.bookSourceSearchKeyword = '';
      this.filterBookSourceList(this.bookSourceSearchKeyword);
    }
  }

  // ============ SettingsPageSurfaceManager 辅助方法 ============

  private getCardBackground(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundColor;
  }

  private getCardBlurStyle(): BlurStyle | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurStyle;
  }

  private getCardBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurOptions;
  }

  private getCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundEffect;
  }

  private getCardBorderColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderColor;
  }

  private getCardBorderWidth(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderWidth;
  }

  private getCardShadowColor(): string {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.shadowColor;
  }

  private getCardRadius(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius;
  }

  // ============ 颜色辅助方法 ============

  private getBookSourceReadableMutedColor(): ResourceColor {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
  }

  private getBookSourceReadableTertiaryColor(): ResourceColor {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme);
    }
    return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
  }

  // ============ 核心方法 ============

  private async initializeAndLoadBookSources(): Promise<void> {
    try {
      await this.ensureBookSourceCacheReady();
      if (!this.bookSourceModuleInitialized) {
        this.isLoadingBookSource = this.bookSourceBooks.length === 0;
        const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
        const initializer = getNovelInitializer();
        if (!initializer.isReady()) {
          logger.info(TAG, '初始化小说模块...');
          await initializer.initialize(context);
          logger.info(TAG, '小说模块初始化完成');
        }
        this.bookSourceModuleInitialized = true;
        this.isLoadingBookSource = false;
        await this.loadBookSourceList();
        return;
      }
      if (this.bookSourceList.length > 0 && this.bookSourceBooks.length > 0) {
        logger.debug(TAG,
          `使用缓存的书源数据: ${this.bookSourceList.length} 个书源, ${this.bookSourceBooks.length} 本书`);
        return;
      }
      if (this.bookSourceList.length > 0 && this.bookSourceBooks.length === 0 && this.selectedBookSourceId) {
        logger.debug(TAG, '书源列表缓存命中，补全当前分类书籍');
        await this.loadBookSourceExploreKinds();
        return;
      }
      await this.loadBookSourceList();
    } catch (error) {
      logger.error(TAG, `初始化书源模块失败: ${String(error)}`);
      this.isLoadingBookSource = false;
    }
  }

  private async ensureBookSourceCacheReady(): Promise<void> {
    if (this.bookSourceCacheRestored) {
      return;
    }
    if (!this.bookSourceCacheRestorePromise) {
      this.bookSourceCacheRestorePromise = this.restoreBookSourceFromCacheAsync();
    }
    await this.bookSourceCacheRestorePromise;
  }

  private async restoreBookSourceFromCacheAsync(): Promise<void> {
    try {
      await this.tabContentCacheManager.initialize();
      this.restoreBookSourceFromCache();
    } finally {
      this.bookSourceCacheRestored = true;
    }
  }

  private restoreBookSourceFromCache(): void {
    if (this.tabContentCacheManager.hasBookSourceCache()) {
      const cache = this.tabContentCacheManager.getBookSourceCache();
      if (cache) {
        this.bookSourceList = cache.bookSourceList;
        this.filterBookSourceList(this.bookSourceSearchKeyword);
        this.selectedBookSourceId = cache.selectedBookSourceId;
        this.selectedBookSourceName = cache.selectedBookSourceName;
        this.bookSourceExploreKinds = cache.bookSourceExploreKinds;
        this.selectedBookSourceKindIndex = cache.selectedBookSourceKindIndex;
        // A cache record may have been written by an older request before a
        // source switch settled. Never display a book whose source identity
        // differs from the cached selected source.
        this.bookSourceBooks = cache.bookSourceBooks.filter(
          (book: NovelSearchResult): boolean => book.sourceId === cache.selectedBookSourceId
        );
        logger.info(TAG,
          `从缓存恢复书源数据: ${this.bookSourceBooks.length} 本书, 书源: ${cache.selectedBookSourceName}`);
      }
    }
  }

  private saveBookSourceToCache(): void {
    if (!this.selectedBookSourceId && this.bookSourceList.length === 0 && this.bookSourceBooks.length === 0) {
      return;
    }
    if (this.selectedBookSourceId.length > 0 && this.bookSourceExploreKinds.length === 0 &&
      this.bookSourceBooks.length === 0) {
      logger.warn(TAG, `跳过空书源缓存保存: ${this.selectedBookSourceName || this.selectedBookSourceId}`);
      return;
    }
    const cacheData: BookSourceCacheData = {
      bookSourceList: this.bookSourceList,
      selectedBookSourceId: this.selectedBookSourceId,
      selectedBookSourceName: this.selectedBookSourceName,
      bookSourceExploreKinds: this.bookSourceExploreKinds,
      selectedBookSourceKindIndex: this.selectedBookSourceKindIndex,
      bookSourceBooks: this.bookSourceBooks,
      timestamp: Date.now()
    };
    this.tabContentCacheManager.saveBookSourceCache(cacheData).catch((error: Error) => {
      logger.error(TAG, `保存书源缓存失败: ${error.message}`);
    });
  }

  private incrementalUpdateBookSourceList(newList: NovelSourceInfo[]): boolean {
    const currentIds = new Set(this.bookSourceList.map((s: NovelSourceInfo) => s.id));
    const newIds = new Set(newList.map((s: NovelSourceInfo) => s.id));
    const newMap = new Map<string, NovelSourceInfo>();
    for (const source of newList) {
      newMap.set(source.id, source);
    }
    let hasChanges = false;
    const removeIndices: number[] = [];
    for (let i = 0; i < this.bookSourceList.length; i++) {
      if (!newIds.has(this.bookSourceList[i].id)) {
        removeIndices.push(i);
      }
    }
    if (removeIndices.length > 0) {
      hasChanges = true;
      for (let i = removeIndices.length - 1; i >= 0; i--) {
        this.bookSourceList.splice(removeIndices[i], 1);
      }
    }
    for (const existing of this.bookSourceList) {
      const next = newMap.get(existing.id);
      if (!next) continue;
      if (existing.name !== next.name) {
        existing.name = next.name;
        hasChanges = true;
      }
      if (existing.url !== next.url) {
        existing.url = next.url;
        hasChanges = true;
      }
      if (existing.group !== next.group) {
        existing.group = next.group;
        hasChanges = true;
      }
      if (existing.bookSourceType !== next.bookSourceType) {
        existing.bookSourceType = next.bookSourceType;
        hasChanges = true;
      }
      if (existing.enabled !== next.enabled) {
        existing.enabled = next.enabled;
        hasChanges = true;
      }
      if (existing.weight !== next.weight) {
        existing.weight = next.weight;
        hasChanges = true;
      }
      if (existing.customOrder !== next.customOrder) {
        existing.customOrder = next.customOrder;
        hasChanges = true;
      }
      if (existing.lastUpdateTime !== next.lastUpdateTime) {
        existing.lastUpdateTime = next.lastUpdateTime;
        hasChanges = true;
      }
      if (existing.respondTime !== next.respondTime) {
        existing.respondTime = next.respondTime;
        hasChanges = true;
      }
      if (existing.searchable !== next.searchable) {
        existing.searchable = next.searchable;
        hasChanges = true;
      }
      if (existing.hasExplore !== next.hasExplore) {
        existing.hasExplore = next.hasExplore;
        hasChanges = true;
      }
      if (existing.isTop !== next.isTop) {
        existing.isTop = next.isTop;
        hasChanges = true;
      }
      if (existing.isNSFW !== next.isNSFW) {
        existing.isNSFW = next.isNSFW;
        hasChanges = true;
      }
      if (existing.compatibilityStatus !== next.compatibilityStatus) {
        existing.compatibilityStatus = next.compatibilityStatus;
        hasChanges = true;
      }
      if (existing.engineMode !== next.engineMode) {
        existing.engineMode = next.engineMode;
        hasChanges = true;
      }
    }
    for (const source of newList) {
      if (!currentIds.has(source.id)) {
        this.bookSourceList.push(source);
        hasChanges = true;
      }
    }
    const currentMap = new Map<string, NovelSourceInfo>();
    for (const source of this.bookSourceList) {
      currentMap.set(source.id, source);
    }
    const reordered: NovelSourceInfo[] = [];
    for (const source of newList) {
      const existing = currentMap.get(source.id);
      if (existing) reordered.push(existing);
    }
    if (reordered.length === this.bookSourceList.length) {
      let orderChanged = false;
      for (let i = 0; i < reordered.length; i++) {
        if (this.bookSourceList[i].id !== reordered[i].id) {
          hasChanges = true;
          orderChanged = true;
          break;
        }
      }
      if (orderChanged) {
        this.bookSourceList.splice(0, this.bookSourceList.length, ...reordered);
      }
    }
    return hasChanges;
  }

  private incrementalUpdateBookSourceBooks(newList: NovelSearchResult[]): boolean {
    const getKey = (item: NovelSearchResult): string => `${item.sourceId}::${item.bookUrl}`;
    const existingMap = new Map<string, NovelSearchResult>();
    for (const item of this.bookSourceBooks) {
      existingMap.set(getKey(item), item);
    }
    let hasChanges = this.bookSourceBooks.length !== newList.length;
    const merged: NovelSearchResult[] = [];
    for (const next of newList) {
      const key = getKey(next);
      const existing = existingMap.get(key);
      if (existing) {
        if (existing.sourceName !== next.sourceName) {
          existing.sourceName = next.sourceName;
          hasChanges = true;
        }
        if (existing.name !== next.name) {
          existing.name = next.name;
          hasChanges = true;
        }
        if (existing.author !== next.author) {
          existing.author = next.author;
          hasChanges = true;
        }
        if (existing.kind !== next.kind) {
          existing.kind = next.kind;
          hasChanges = true;
        }
        if (existing.intro !== next.intro) {
          existing.intro = next.intro;
          hasChanges = true;
        }
        if (existing.coverUrl !== next.coverUrl) {
          existing.coverUrl = next.coverUrl;
          hasChanges = true;
        }
        if (existing.latestChapterTitle !== next.latestChapterTitle) {
          existing.latestChapterTitle = next.latestChapterTitle;
          hasChanges = true;
        }
        if (existing.wordCount !== next.wordCount) {
          existing.wordCount = next.wordCount;
          hasChanges = true;
        }
        if (existing.isNSFW !== next.isNSFW) {
          existing.isNSFW = next.isNSFW;
          hasChanges = true;
        }
        merged.push(existing);
        existingMap.delete(key);
      } else {
        merged.push(next);
        hasChanges = true;
      }
    }
    if (!hasChanges && merged.length === this.bookSourceBooks.length) {
      for (let i = 0; i < merged.length; i++) {
        if (getKey(this.bookSourceBooks[i]) !== getKey(merged[i])) {
          hasChanges = true;
          break;
        }
      }
    }
    if (hasChanges) {
      this.bookSourceBooks.splice(0, this.bookSourceBooks.length, ...merged);
    }
    return hasChanges;
  }

  private async refreshBookSourceContent(): Promise<void> {
    try {
      if (!this.bookSourceModuleInitialized) {
        await this.initializeAndLoadBookSources();
      } else {
        const refreshOptions: BookSourceLoadOptions = { loadBooks: false, silent: true };
        await this.loadBookSourceList(refreshOptions);
      }
      if (this.selectedBookSourceId && this.bookSourceExploreKinds.length > 0) {
        await this.loadBookSourceBooks(true);
      }
    } catch (error) {
      logger.error(TAG, `刷新书源内容失败: ${String(error)}`);
    }
    this.isRefreshingBookSource = false;
  }

  private async loadBookSourceList(options?: BookSourceLoadOptions): Promise<void> {
    const loadBooks = options?.loadBooks ?? true;
    const silent = options?.silent ?? false;
    try {
      const sourceManager = getNovelSourceManager();
      const allSources = sourceManager.getExploreSources();
      const newList = this.contentFilterManager.filterContentList(allSources);
      let sourceListChanged = false;
      if (this.bookSourceList.length === 0) {
        this.bookSourceList = newList;
        sourceListChanged = newList.length > 0;
      } else {
        sourceListChanged = this.incrementalUpdateBookSourceList(newList);
      }
      this.filterBookSourceList(this.bookSourceSearchKeyword);
      if (silent) {
        logger.debug(TAG,
          `书源列表静默刷新完成：${sourceListChanged ? '有变化' : '无变化'}，共 ${this.bookSourceList.length} 个`);
      } else {
        logger.info(TAG, `加载书源列表完成，共 ${this.bookSourceList.length} 个支持发现功能的书源`);
      }
      if (this.bookSourceList.length === 0) {
        this.selectedBookSourceId = '';
        this.selectedBookSourceName = '';
        this.beginBookSourceSelection('');
        this.bookSourceExploreKinds = [];
        this.selectedBookSourceKindIndex = 0;
        this.bookSourceBooks = [];
        this.bookSourceHasMore = false;
        return;
      }
      if (!this.selectedBookSourceId) {
        this.selectedBookSourceId = this.bookSourceList[0].id;
        this.selectedBookSourceName = this.bookSourceList[0].name;
        this.beginBookSourceSelection(this.selectedBookSourceId);
        this.bookSourceExploreKinds = [];
        this.selectedBookSourceKindIndex = 0;
        this.bookSourceBooks = [];
        this.saveBookSourceToCache();
        await this.loadBookSourceExploreKinds(loadBooks);
        return;
      }
      const selectedSource = this.bookSourceList.find((s: NovelSourceInfo) => s.id === this.selectedBookSourceId);
      if (selectedSource) {
        this.selectedBookSourceName = selectedSource.name;
        await this.loadBookSourceExploreKinds(loadBooks);
      } else {
        this.selectedBookSourceId = this.bookSourceList[0].id;
        this.selectedBookSourceName = this.bookSourceList[0].name;
        this.beginBookSourceSelection(this.selectedBookSourceId);
        this.bookSourceExploreKinds = [];
        this.selectedBookSourceKindIndex = 0;
        this.bookSourceBooks = [];
        this.saveBookSourceToCache();
        await this.loadBookSourceExploreKinds(loadBooks);
      }
    } catch (error) {
      logger.error(TAG, `加载书源列表失败: ${String(error)}`);
    }
  }

  private filterBookSourceList(keyword: string): void {
    const lowerKeyword = keyword.trim().toLowerCase();
    const filtered = this.bookSourceList.filter((source: NovelSourceInfo): boolean => {
      if (lowerKeyword.length > 0 && !source.name.toLowerCase().includes(lowerKeyword)) {
        return false;
      }
      if (!this.matchesBookSourceTypeFilter(source)) {
        return false;
      }
      if (this.selectedBookSourceGroupFilter.length > 0 &&
        !this.getBookSourceGroups(source).includes(this.selectedBookSourceGroupFilter)) {
        return false;
      }
      return true;
    });
    this.filteredBookSourceList = this.contentFilterManager.filterContentList(filtered);
  }

  private matchesBookSourceTypeFilter(source: NovelSourceInfo): boolean {
    if (this.selectedBookSourceTypeFilter === BookSourceTypeFilter.ALL) {
      return true;
    }
    const sourceType = source.bookSourceType ?? LegadoBookSourceType.TEXT;
    if (this.selectedBookSourceTypeFilter === BookSourceTypeFilter.IMAGE) {
      return sourceType === LegadoBookSourceType.IMAGE;
    }
    if (this.selectedBookSourceTypeFilter === BookSourceTypeFilter.AUDIO) {
      return sourceType === LegadoBookSourceType.AUDIO;
    }
    return sourceType === LegadoBookSourceType.TEXT;
  }

  private getBookSourceTypeLabel(source: NovelSourceInfo): string {
    const sourceType = source.bookSourceType ?? LegadoBookSourceType.TEXT;
    if (sourceType === LegadoBookSourceType.IMAGE) {
      return '漫画/图片书源';
    }
    if (sourceType === LegadoBookSourceType.AUDIO) {
      return '听书书源';
    }
    if (sourceType === LegadoBookSourceType.FILE) {
      return '文件书源';
    }
    if (sourceType < LegadoBookSourceType.TEXT || sourceType > LegadoBookSourceType.FILE) {
      return '外部/插件书源';
    }
    return '纯书源';
  }

  private getCompatibilityLabel(source: NovelSourceInfo): string {
    const status = source.compatibilityStatus || LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE;
    const mode = source.engineMode || LegadoCompatibilityEngineMode.LEGACY;
    const fullCutoverBlockReason = source.v2FullCutoverBlockReason || '';
    if (fullCutoverBlockReason.length > 0) {
      return `V2 受阻：${fullCutoverBlockReason}`;
    }
    if (status === LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE) {
      return '旧记录/未无损验证';
    }
    if (status === LegadoCompatibilityStatus.NEEDS_INTERACTION) {
      return '需登录或交互';
    }
    if (status === LegadoCompatibilityStatus.UNSUPPORTED) {
      return '不支持';
    }
    if (status === LegadoCompatibilityStatus.BLOCKED) {
      return '兼容受阻';
    }
    if (status === LegadoCompatibilityStatus.VERIFIED && mode === LegadoCompatibilityEngineMode.V2_ENABLED) {
      return 'V2 已验证';
    }
    if (status === LegadoCompatibilityStatus.VERIFIED && mode === LegadoCompatibilityEngineMode.V2_SHADOW) {
      return 'V2 对照中';
    }
    if (status === LegadoCompatibilityStatus.VERIFIED) {
      return '已验证工作流';
    }
    if (status === LegadoCompatibilityStatus.READY) {
      return mode === LegadoCompatibilityEngineMode.V2_ENABLED ? 'V2 正在执行' : '可编译/待切换';
    }
    return '已解析';
  }

  private getBookSourceGroups(source: NovelSourceInfo): string[] {
    if (!source.group || source.group.trim().length <= 0) {
      return [];
    }
    const normalizedGroup = source.group.replace(/，/g, ',');
    const rawGroups = normalizedGroup.split(',');
    const groups: string[] = [];
    for (let i = 0; i < rawGroups.length; i++) {
      const group = rawGroups[i].trim();
      if (group.length > 0 && !groups.includes(group)) {
        groups.push(group);
      }
    }
    return groups;
  }

  private getBookSourceGroupFilters(): string[] {
    const groups: string[] = [];
    for (let i = 0; i < this.bookSourceList.length; i++) {
      const sourceGroups = this.getBookSourceGroups(this.bookSourceList[i]);
      for (let j = 0; j < sourceGroups.length; j++) {
        const group = sourceGroups[j];
        if (!groups.includes(group)) {
          groups.push(group);
        }
      }
    }
    groups.sort((left: string, right: string): number => left.localeCompare(right));
    return groups;
  }

  private getBookSourceGroupSummary(source: NovelSourceInfo): string {
    const groups = this.getBookSourceGroups(source);
    return groups.length > 0 ? groups.join(' · ') : '未分组';
  }

  private selectBookSourceTypeFilter(filter: BookSourceTypeFilter): void {
    this.selectedBookSourceTypeFilter = filter;
    this.filterBookSourceList(this.bookSourceSearchKeyword);
  }

  private selectBookSourceGroupFilter(group: string): void {
    this.selectedBookSourceGroupFilter = group;
    this.filterBookSourceList(this.bookSourceSearchKeyword);
  }

  private showBookSourceRefreshHint(): void {
    if (this.bookSourceRefreshHintTimer !== -1) {
      clearTimeout(this.bookSourceRefreshHintTimer);
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.bookSourceRefreshHintVisible = true;
    });
    this.bookSourceRefreshHintTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
        this.bookSourceRefreshHintVisible = false;
      });
      this.bookSourceRefreshHintTimer = -1;
    }, 2000) as number;
  }

  private async loadBookSourceExploreKinds(
    loadBooks: boolean = true,
    requestSourceId: string = this.selectedBookSourceId,
    requestGeneration: number = this.bookSourceSelectionGeneration
  ): Promise<void> {
    if (!requestSourceId || !this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
      return;
    }
    this.bookSourceExploreError = '';
    this.bookSourceExploreTraceSummary = '';
    try {
      const sourceManager = getNovelSourceManager();
      const newKinds = await sourceManager.getExploreKindsAsync(requestSourceId);
      if (!this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG, `丢弃过期书源分类结果: generation=${requestGeneration};source=${requestSourceId}`);
        return;
      }
      if (newKinds.length <= 0) {
        logger.warn(TAG, `书源发现分类为空: ${this.selectedBookSourceName || this.selectedBookSourceId}`);
        this.bookSourceExploreKinds = [];
        this.bookSourceExploreError = '该书源没有可执行的发现分类';
        this.bookSourceExploreTraceSummary = '';
        this.selectedBookSourceKindIndex = 0;
        if (loadBooks) {
          this.bookSourceBooks = [];
          this.bookSourceHasMore = false;
        }
        return;
      }
      const cachedIndex = this.selectedBookSourceKindIndex;
      const defaultKindIndex = this.findFirstExecutableExploreKindIndex(newKinds);
      this.bookSourceExploreKinds = newKinds;
      if (cachedIndex >= 0 && cachedIndex < newKinds.length && newKinds[cachedIndex].url.trim().length > 0) {
        this.selectedBookSourceKindIndex = cachedIndex;
      } else if (defaultKindIndex >= 0) {
        this.selectedBookSourceKindIndex = defaultKindIndex;
      } else {
        this.selectedBookSourceKindIndex = 0;
      }
      this.bookSourceExploreError = defaultKindIndex >= 0 ? '' : '该书源没有可执行的发现分类';
      this.saveBookSourceToCache();
      if (loadBooks && defaultKindIndex >= 0) {
        await this.loadBookSourceBooks(true, requestSourceId, requestGeneration);
      } else if (loadBooks) {
        this.bookSourceBooks = [];
        this.bookSourceHasMore = false;
      }
    } catch (error) {
      if (!this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG, `忽略过期书源分类异常: generation=${requestGeneration};source=${requestSourceId}`);
        return;
      }
      logger.error(TAG, `加载书源发现分类失败: ${String(error)}`);
      this.bookSourceExploreKinds = [];
      this.bookSourceBooks = [];
      this.bookSourceHasMore = false;
      this.bookSourceExploreError = this.resolveExploreKindsErrorMessage(String(error));
      // Dynamic kind scripts persist a redacted workflow trace before they
      // reject. Refresh it here as well as on successful book-list loading so
      // a transport failure remains visible and machine-readable in the
      // no-result state.
      await this.refreshBookSourceExploreTrace(getNovelSourceManager());
    }
  }

  private resolveExploreKindsErrorMessage(error: string): string {
    if (error.includes('WEBVIEW_NOT_READY')) {
      return '动态分类运行环境尚未就绪，请稍后重试';
    }
    if (error.includes('JS_CONTRACT_BLOCKED')) {
      return '该书源的动态分类需要尚未支持的脚本能力';
    }
    if (error.includes('SCRIPT_NETWORK')) {
      return '动态分类请求失败，请检查网络后重试';
    }
    if (error.includes('EXPLORE_KINDS_JSON_PARSE_FAILED') || error.includes('EXPLORE_KINDS_JSON_NOT_ARRAY')) {
      return '该书源的发现分类格式无效，已记录诊断';
    }
    return '动态分类执行失败，请刷新重试';
  }

  private findFirstExecutableExploreKindIndex(kinds: ExploreKind[]): number {
    for (let index = 0; index < kinds.length; index++) {
      if (kinds[index].url.trim().length > 0) {
        return index;
      }
    }
    return -1;
  }

  private async loadBookSourceBooks(
    reset: boolean = false,
    requestSourceId: string = this.selectedBookSourceId,
    requestGeneration: number = this.bookSourceSelectionGeneration,
    requestKindIndex: number = this.selectedBookSourceKindIndex,
    requestPage: number = this.bookSourceCurrentPage
  ): Promise<void> {
    if (!requestSourceId || !this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration) ||
      this.bookSourceExploreKinds.length === 0) {
      return;
    }
    const hasCachedData = reset && this.bookSourceBooks.length > 0;
    if (reset) {
      this.bookSourceCurrentPage = 1;
      if (!hasCachedData) {
        this.bookSourceBooks = [];
      }
    }
    if (!hasCachedData) {
      this.isLoadingBookSource = true;
    }
    try {
      const sourceManager = getNovelSourceManager();
      const kind = this.bookSourceExploreKinds[requestKindIndex];
      if (!kind) {
        this.isLoadingBookSource = false;
        return;
      }
      if (kind.url.trim().length === 0) {
        this.isLoadingBookSource = false;
        this.bookSourceHasMore = false;
        this.bookSourceExploreError = '该分类仅用于分组展示，未定义可执行地址';
        return;
      }
      const results = await sourceManager.explore(requestSourceId, kind.url, requestPage);
      if (!this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG, `丢弃过期书源书籍结果: generation=${requestGeneration};source=${requestSourceId}`);
        return;
      }
      for (const result of results) {
        if (result.sourceId !== requestSourceId) {
          logger.error(TAG,
            `书源结果身份不一致，拒绝写入列表: expected=${requestSourceId};actual=${result.sourceId}`);
          return;
        }
      }
      if (reset) {
        if (hasCachedData) {
          const changed = this.incrementalUpdateBookSourceBooks(results);
          if (changed) {
            this.showBookSourceRefreshHint();
          }
        } else {
          this.bookSourceBooks = results;
        }
      } else {
        this.bookSourceBooks = [...this.bookSourceBooks, ...results];
      }
      this.bookSourceHasMore = results.length >= 20;
      this.saveBookSourceToCache();
      await this.refreshBookSourceExploreTrace(sourceManager);
    } catch (error) {
      if (!this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG, `忽略过期书源书籍异常: generation=${requestGeneration};source=${requestSourceId}`);
        return;
      }
      logger.error(TAG, `加载书源书籍失败: ${String(error)}`);
      await this.refreshBookSourceExploreTrace(getNovelSourceManager());
    }
    if (this.isBookSourceSelectionCurrent(requestSourceId, requestGeneration)) {
      this.isLoadingBookSource = false;
    }
  }

  private async refreshBookSourceExploreTrace(sourceManager: NovelSourceManager): Promise<void> {
    if (this.selectedBookSourceId.length === 0) {
      this.bookSourceExploreTraceSummary = '';
      return;
    }
    try {
      const summaries: LegadoExecutionTraceSummary[] =
        await sourceManager.getPersistedExecutionTraceWorkflowSummaries(this.selectedBookSourceId);
      let latestExplore: LegadoExecutionTraceSummary | null = null;
      for (let index = 0; index < summaries.length; index++) {
        const summary = summaries[index];
        if (summary.workflow === LegadoWorkflowKind.EXPLORE &&
          (latestExplore === null || summary.updatedAt > latestExplore.updatedAt)) {
          latestExplore = summary;
        }
      }
      if (latestExplore === null) {
        this.bookSourceExploreTraceSummary = '';
        return;
      }
      this.bookSourceExploreTraceSummary =
        `workflow=${latestExplore.workflow};transport=${latestExplore.transport};` +
        `http=${latestExplore.statusCode};error=${latestExplore.errorCode};` +
        `options=${latestExplore.optionCount};variables=${latestExplore.variableCount};` +
        `output=${latestExplore.outputSummary}`;
    } catch (error) {
      logger.warn(TAG, `刷新发现页脱敏 trace 失败: ${String(error)}`);
      this.bookSourceExploreTraceSummary = '';
    }
  }

  private performBookSourceSearch(): void {
    if (!this.bookSourceSearchInput.trim()) return;
    const params: NovelSearchPageParams = { keyword: this.bookSourceSearchInput.trim() };
    if (this.selectedBookSourceId) {
      params.sourceId = this.selectedBookSourceId;
      params.sourceName = this.selectedBookSourceName;
    }
    this.pathStack.pushPathByName('NovelSearchPage', params);
  }

  private clearBookSourceSearch(): void {
    this.bookSourceSearchInput = '';
    this.isBookSourceSearchMode = false;
    this.loadBookSourceBooks(true);
  }

  private async selectBookSource(source: NovelSourceInfo): Promise<void> {
    if (this.selectedBookSourceId !== source.id) {
      this.selectedBookSourceId = source.id;
      this.selectedBookSourceName = source.name;
      const selectionGeneration = this.beginBookSourceSelection(source.id);
      this.bookSourceCurrentPage = 1;
      this.bookSourceExploreKinds = [];
      this.bookSourceExploreError = '';
      this.bookSourceExploreTraceSummary = '';
      this.selectedBookSourceKindIndex = 0;
      this.bookSourceBooks = [];
      this.isBookSourceSearchMode = false;
      this.bookSourceSearchInput = '';
      this.showBookSourcePicker = false;
      this.bookSourceSearchKeyword = '';
      this.filterBookSourceList(this.bookSourceSearchKeyword);
      this.saveBookSourceToCache();
      await this.loadBookSourceExploreKinds(true, source.id, selectionGeneration);
    } else {
      this.beginBookSourceSelection(source.id);
      this.showBookSourcePicker = false;
      this.bookSourceSearchKeyword = '';
      this.filterBookSourceList(this.bookSourceSearchKeyword);
    }
  }

  private selectBookSourceKind(index: number): void {
    if (this.selectedBookSourceKindIndex !== index) {
      const requestSourceId = this.selectedBookSourceId;
      const requestGeneration = this.bookSourceSelectionGeneration;
      this.bookSourceCurrentPage = 1;
      this.bookSourceBooks = [];
      this.isBookSourceSearchMode = false;
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        this.selectedBookSourceKindIndex = index;
      });
      void this.loadBookSourceBooks(true, requestSourceId, requestGeneration, index, 1);
    }
  }

  private async openBookDetail(book: NovelSearchResult): Promise<void> {
    if (book.sourceId.length === 0 || book.sourceId !== this.selectedBookSourceId) {
      logger.error(
        TAG,
        `拒绝打开跨书源结果: selected=${this.selectedBookSourceId};result=${book.sourceId}`
      );
      promptAction.showToast({ message: '书源结果已过期，请刷新后重试' });
      return;
    }
    const result: LegadoExploreDetailOpenResult =
      await openLegadoExploreDetail(this.pathStack, this.selectedBookSourceId, book);
    if (result.status === LegadoExploreDetailOpenStatus.REJECTED) {
      promptAction.showToast({ message: result.userMessage });
    }
  }

  private toggleBookSourceViewMode(): void {
    const newMode: LibraryViewMode = this.bookSourceViewMode === LibraryViewMode.LIST
      ? LibraryViewMode.GRID
      : LibraryViewMode.LIST;
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.bookSourceViewMode = newMode;
    });
    this.saveBookSourceViewMode(newMode).catch((error: Error) => {
      logger.error(TAG, `切换书源视图模式失败: ${error.message}`);
    });
  }

  private async saveBookSourceViewMode(mode: LibraryViewMode): Promise<void> {
    try {
      const dataManager = DataManager.getInstance();
      await dataManager.saveUserSetting('default_user', 'book_source_view_mode', mode);
    } catch (error) {
      logger.error(TAG, `保存书源视图模式失败: ${String(error)}`);
    }
  }

  private async loadBookSourceViewMode(): Promise<void> {
    try {
      const dataManager = DataManager.getInstance();
      const viewMode = await dataManager.getUserSetting('default_user', 'book_source_view_mode');
      if (viewMode === LibraryViewMode.GRID || viewMode === LibraryViewMode.LIST) {
        this.bookSourceViewMode = viewMode as LibraryViewMode;
        logger.info(TAG, `恢复书源视图模式: ${viewMode}`);
      }
    } catch (error) {
      logger.error(TAG, `加载书源视图模式失败: ${String(error)}`);
    }
  }

  private scrollToSelectedBookSource(): void {
    const autoScrollEnabled: boolean = this.settingsManager.getBoolean(
      SettingKeys.MAIN_MENU_BOOK_SOURCE_PICKER_AUTO_SCROLL_ENABLED,
      true
    );
    if (!autoScrollEnabled) return;
    if (!this.selectedBookSourceId || this.filteredBookSourceList.length === 0) return;
    const selectedIndex =
      this.filteredBookSourceList.findIndex((s: NovelSourceInfo) => s.id === this.selectedBookSourceId);
    if (selectedIndex > 0) {
      setTimeout(() => {
        this.bookSourceListScroller.scrollToIndex(selectedIndex, true, ScrollAlign.CENTER);
      }, 100);
    }
  }

  // ============ Builder 方法 ============

  @Builder
  buildBookSourceExploreTraceSummary() {
    Text(this.bookSourceExploreTraceSummary)
      .id('novel_book_source_explore_v2_trace')
      .fontSize(10)
      .fontFamily(this.appFontFamily)
      .fontColor(this.getBookSourceReadableTertiaryColor())
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  buildBookSourceViewModeToggleButton() {
    Row({ space: 6 }) {
      SymbolGlyph(this.bookSourceViewMode === LibraryViewMode.LIST
        ? $r('sys.symbol.list_bullet')
        : $r('sys.symbol.square_grid_2x2'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
      Text(this.bookSourceViewMode === LibraryViewMode.LIST ? '列表' : '封面')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getBookSourceReadableTertiaryColor())
    }
    .padding({
      left: 12,
      right: 12,
      top: 6,
      bottom: 6
    })
    .backgroundColor(this.getCardBackground())
    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
    .backgroundEffect(this.getCardBackgroundEffect())
    .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
    .borderRadius(16)
    .shadow({
      radius: this.getCardRadius(),
      color: this.getCardShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.toggleBookSourceViewMode();
    })
  }

  @Builder
  buildBookSourceGridCard(book: NovelSearchResult, index: number) {
    Column({ space: 8 }) {
      Stack() {
        if (book.coverUrl && book.coverUrl.length > 0) {
          if (book.coverUrl.startsWith('http://') || book.coverUrl.startsWith('https://')) {
            AvifImage({
              src: book.coverUrl,
              imageWidth: '100%',
              imageHeight: '100%',
              objectFit: ImageFit.Cover
            })
          } else {
            Image(book.coverUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
        } else {
          Column() {
            Text(book.name.substring(0, 1))
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      .aspectRatio(0.7)
      .borderRadius(8)
      .clip(true)
      .onClick(() => {
        void this.openBookDetail(book);
      })

      Column({ space: 4 }) {
        Text(book.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(book.author || '未知作者')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getBookSourceReadableTertiaryColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (book.latestChapterTitle) {
          Text(book.latestChapterTitle)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getBookSourceReadableTertiaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 2, right: 2 })
      .onClick(() => {
        void this.openBookDetail(book);
      })
    }
    .width('100%')
    .id(`novel_book_source_explore_result_${index}`)
    .padding({
      left: 2,
      right: 2,
      top: 4,
      bottom: 6
    })
  }

  @Builder
  buildBookItem(book: NovelSearchResult, index: number) {
    Row() {
      if (book.coverUrl) {
        Image(book.coverUrl)
          .width(70)
          .height(95)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(20)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
        }
        .width(70)
        .height(95)
        .borderRadius(4)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      Column() {
        Text(book.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.author || '未知作者')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getBookSourceReadableTertiaryColor())
          .margin({ top: 4 })
        if (book.intro) {
          Text(book.intro)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getBookSourceReadableTertiaryColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .id(`novel_book_source_explore_result_${index}`)
    .padding(12)
    .backgroundColor(this.getCardBackground())
    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
    .backgroundEffect(this.getCardBackgroundEffect())
    .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
    .borderRadius(16)
    .shadow({
      radius: this.getCardRadius(),
      color: this.getCardShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      void this.openBookDetail(book);
    })
  }

  @Builder
  buildBookSourceTypeFilterChip(label: string, filter: BookSourceTypeFilter) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.selectedBookSourceTypeFilter === filter ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .backgroundColor(this.selectedBookSourceTypeFilter === filter ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
        this.getCardBackground())
      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
      .backgroundEffect(this.getCardBackgroundEffect())
      .border({
        width: this.getCardBorderWidth(),
        color: this.selectedBookSourceTypeFilter === filter ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          this.getCardBorderColor()
      })
      .borderRadius(14)
      .clip(true)
      .onClick(() => {
        this.selectBookSourceTypeFilter(filter);
      })
  }

  @Builder
  buildBookSourceGroupFilterChip(label: string, group: string) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.selectedBookSourceGroupFilter === group ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({
        left: 12,
        right: 12,
        top: 6,
        bottom: 6
      })
      .backgroundColor(this.selectedBookSourceGroupFilter === group ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
        this.getCardBackground())
      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
      .backgroundEffect(this.getCardBackgroundEffect())
      .border({
        width: this.getCardBorderWidth(),
        color: this.selectedBookSourceGroupFilter === group ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          this.getCardBorderColor()
      })
      .borderRadius(14)
      .clip(true)
      .onClick(() => {
        this.selectBookSourceGroupFilter(group);
      })
  }

  @Builder
  buildBookSourcePickerContent() {
    Column() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.list_book'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('书源筛选')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Text(`共 ${this.filteredBookSourceList.length} 个`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getBookSourceReadableTertiaryColor())
        }
        .width('100%')

        TextInput({ placeholder: '输入书源名称进行筛选', text: this.bookSourceSearchKeyword })
          .id('novel_book_source_picker_filter')
          .width('100%')
          .height(42)
          .fontFamily(this.appFontFamily)
          .backgroundColor(
            ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.bookSourceSearchKeyword = value;
            this.filterBookSourceList(value);
          })

        Scroll() {
          Row({ space: 8 }) {
            this.buildBookSourceTypeFilterChip('全部', BookSourceTypeFilter.ALL)
            this.buildBookSourceTypeFilterChip('纯书源', BookSourceTypeFilter.TEXT)
            this.buildBookSourceTypeFilterChip('漫画/图片', BookSourceTypeFilter.IMAGE)
            this.buildBookSourceTypeFilterChip('听书', BookSourceTypeFilter.AUDIO)
          }
          .padding({ right: 4 })
        }
        .width('100%')
        .height(34)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        if (this.getBookSourceGroupFilters().length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              this.buildBookSourceGroupFilterChip('全部分组', '')
              ForEach(this.getBookSourceGroupFilters(), (group: string) => {
                this.buildBookSourceGroupFilterChip(group, group)
              }, (group: string) => group)
            }
            .padding({ right: 4 })
          }
          .width('100%')
          .height(34)
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
        }

        if (this.filteredBookSourceList.length > 0) {
          List({ scroller: this.bookSourceListScroller }) {
            ForEach(this.filteredBookSourceList, (source: NovelSourceInfo) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column({ space: 4 }) {
                    Text(source.name)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.selectedBookSourceId === source.id ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .fontWeight(this.selectedBookSourceId === source.id ? FontWeight.Medium : FontWeight.Normal)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${this.getBookSourceTypeLabel(source)} · ${this.getBookSourceGroupSummary(source)} · ${this.getCompatibilityLabel(source)}`)
                      .fontSize(11)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.getBookSourceReadableTertiaryColor())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  if (this.selectedBookSourceId === source.id) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(20)
                      .fontColor(
                        [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                  }
                }
                .width('100%')
                .height(56)
                .id(`novel_book_source_picker_item_${source.id}`)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.selectedBookSourceId === source.id ?
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                  Color.Transparent)
                .onClick(() => {
                  void this.selectBookSource(source);
                })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .divider({
            strokeWidth: 0.5,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
          })
          .onAppear(() => {
            this.scrollToSelectedBookSource();
          })
        } else {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(40)
              .fontColor([this.getBookSourceReadableMutedColor()])
              .opacity(0.45)
            Text('未匹配到书源')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getBookSourceReadableTertiaryColor())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  // ============ 主内容构建 ============

  build() {
    Stack() {
      Column({ space: 0 }) {
        Blank().height(this.topSpacerHeight)

        // 顶部操作栏
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.list_book'))
              .fontSize(16)
              .fontColor(
                [ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(this.selectedBookSourceName || '选择书源')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor(
                [ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .rotate({ angle: this.showBookSourcePicker ? 180 : 0 })
              .animation({ duration: 200 })
          }
          .layoutWeight(1)
          .padding({
            left: 12,
            right: 12,
            top: 8,
            bottom: 8
          })
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(20)
          .shadow({
            radius: this.getCardRadius(),
            color: this.getCardShadowColor(),
            offsetX: 0,
            offsetY: 2
          })
          .clip(true)
          .id('novel_book_source_picker_open')
          .onClick(() => {
            this.bookSourceSearchKeyword = '';
            this.filterBookSourceList(this.bookSourceSearchKeyword);
            this.showBookSourcePicker = true;
          })

          // 搜索按钮
          Button() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(12)
          .shadow({
            radius: this.getCardRadius(),
            color: this.getCardShadowColor(),
            offsetX: 0,
            offsetY: 2
          })
          .clip(true)
          .onClick(() => {
            const params: NovelSearchPageParams = {};
            if (this.selectedBookSourceId) {
              params.sourceId = this.selectedBookSourceId;
              params.sourceName = this.selectedBookSourceName;
            }
            this.pathStack.pushPathByName('NovelSearchPage', params);
          })

          // 小说设置按钮
          Button() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(12)
          .shadow({
            radius: this.getCardRadius(),
            color: this.getCardShadowColor(),
            offsetX: 0,
            offsetY: 2
          })
          .clip(true)
          .onClick(() => {
            this.pathStack.pushPathByName('NovelSettingsPage', null);
          })

          // 书源管理按钮
          Button() {
            SymbolGlyph($r('sys.symbol.list_book'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(40)
          .height(40)
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(12)
          .shadow({
            radius: this.getCardRadius(),
            color: this.getCardShadowColor(),
            offsetX: 0,
            offsetY: 2
          })
          .clip(true)
          .id('book_source_open_management')
          .onClick(() => {
            this.pathStack.pushPathByName('NovelSourceManagementPage', null);
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.Transparent)

        if (this.isBookSourceSearchMode) {
          Row() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(14)
                .fontColor(
                  [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('清除搜索')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .padding({
              left: 12,
              right: 12,
              top: 8,
              bottom: 8
            })
            .backgroundColor(this.getCardBackground())
            .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
            .backgroundEffect(this.getCardBackgroundEffect())
            .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
            .borderRadius(20)
            .shadow({
              radius: this.getCardRadius(),
              color: this.getCardShadowColor(),
              offsetX: 0,
              offsetY: 2
            })
            .clip(true)
            .onClick(() => this.clearBookSourceSearch())
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 12 })
        }

        // 分类选择器
        if (!this.isBookSourceSearchMode && this.bookSourceExploreKinds.length > 0) {
          Column() {
            Row() {
              Text('发现分类')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(`(${this.bookSourceExploreKinds.length})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.getBookSourceReadableTertiaryColor())
                .margin({ left: 4 })
              Blank()
              Row({ space: 8 }) {
                Row({ space: 4 }) {
                  Text(this.bookSourceKindsExpanded ? '收起' : '展开')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  SymbolGlyph(this.bookSourceKindsExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                    .fontSize(14)
                    .fontColor(
                      [ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
                }
                .padding({
                  left: 8,
                  right: 8,
                  top: 4,
                  bottom: 4
                })
                .backgroundColor(this.getCardBackground())
                .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                .backgroundEffect(this.getCardBackgroundEffect())
                .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
                .borderRadius(12)
                .shadow({
                  radius: this.getCardRadius(),
                  color: this.getCardShadowColor(),
                  offsetX: 0,
                  offsetY: 2
                })
                .clip(true)
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                    this.bookSourceKindsExpanded = !this.bookSourceKindsExpanded;
                  });
                })

                this.buildBookSourceViewModeToggleButton()
              }
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })

            if (this.bookSourceKindsExpanded) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.bookSourceExploreKinds, (kind: ExploreKind, index: number) => {
                  Text(kind.title)
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .padding({
                      left: 16,
                      right: 16,
                      top: 6,
                      bottom: 6
                    })
                    .backgroundColor(this.selectedBookSourceKindIndex === index ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed',
                        this.themeState.currentTheme) :
                      this.getCardBackground())
                    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                    .backgroundEffect(this.getCardBackgroundEffect())
                    .fontColor(this.selectedBookSourceKindIndex === index ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .border({
                      width: this.getCardBorderWidth(),
                      color: this.selectedBookSourceKindIndex === index ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                        this.getCardBorderColor()
                    })
                    .borderRadius(16)
                    .shadow({
                      radius: this.getCardRadius(),
                      color: this.getCardShadowColor(),
                      offsetX: 0,
                      offsetY: 2
                    })
                    .clip(true)
                    .id(`novel_book_source_explore_kind_${index}`)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => this.selectBookSourceKind(index))
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 8 })
            } else {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.bookSourceExploreKinds, (kind: ExploreKind, index: number) => {
                    Text(kind.title)
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .padding({
                        left: 16,
                        right: 16,
                        top: 6,
                        bottom: 6
                      })
                      .backgroundColor(this.selectedBookSourceKindIndex === index ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed',
                          this.themeState.currentTheme) :
                        this.getCardBackground())
                      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                      .backgroundEffect(this.getCardBackgroundEffect())
                      .fontColor(this.selectedBookSourceKindIndex === index ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .border({
                        width: this.getCardBorderWidth(),
                        color: this.selectedBookSourceKindIndex === index ?
                          ThemeAwareHelper.getTestManagementThemedColor('accent_primary',
                            this.themeState.currentTheme) :
                          this.getCardBorderColor()
                      })
                      .borderRadius(16)
                      .shadow({
                        radius: this.getCardRadius(),
                        color: this.getCardShadowColor(),
                        offsetX: 0,
                        offsetY: 2
                      })
                      .clip(true)
                      .id(`novel_book_source_explore_kind_${index}`)
                      .onClick(() => this.selectBookSourceKind(index))
                  })
                }
                .padding({ left: 16, right: 16 })
              }
              .width('100%')
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
            }
          }
          .width('100%')
          .margin({ bottom: 12 })
        }

        // Keep the redacted V2 Explore witness adjacent to the selected
        // categories.  Result cards live in a virtualized Scroll and may
        // push the old disclosure below the initial viewport, making a real
        // completed request look unobservable to both users and Hypium.
        if (this.bookSourceExploreTraceSummary.length > 0) {
          this.buildBookSourceExploreTraceSummary()
        }

        // 刷新提示浮层
        if (this.bookSourceRefreshHintVisible) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text('内容已刷新')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          }
          .padding({
            left: 16,
            right: 16,
            top: 8,
            bottom: 8
          })
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(20)
          .shadow({
            radius: this.getCardRadius(),
            color: this.getCardShadowColor(),
            offsetX: 0,
            offsetY: 2
          })
          .margin({ left: 16, right: 16, bottom: 8 })
        }

        // 书籍列表
        if (this.isLoadingBookSource && this.bookSourceBooks.length === 0) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('加载中...')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.bookSourceBooks.length === 0) {
          Column({ space: 12 }) {
            SymbolGlyph(this.bookSourceExploreError.length > 0
              ? $r('sys.symbol.exclamationmark_triangle')
              : $r('sys.symbol.book'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              .opacity(0.45)
            Text(this.bookSourceExploreError.length > 0
              ? this.bookSourceExploreError
              : (this.selectedBookSourceId ? '该书源暂无发现内容' : '请先选择一个书源'))
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getBookSourceReadableTertiaryColor())
              .id(this.bookSourceExploreError.length > 0
                ? 'novel_book_source_explore_error'
                : 'novel_book_source_explore_empty')
            // A valid Explore request can complete with an empty result set.
            // Keep the persisted transport trace visible in that state so the
            // harness can distinguish an externally empty response from a UI
            // or engine failure.
            if (this.bookSourceExploreTraceSummary.length > 0) {
              this.buildBookSourceExploreTraceSummary()
            }
            if (this.bookSourceExploreError.length > 0) {
              Button('重新加载')
                .height(36)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor(
                  'accent_primary',
                  this.themeState.currentTheme
                ))
                .backgroundColor(this.getCardBackground())
                .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
                .borderRadius(18)
                .onClick(() => {
                  void this.loadBookSourceExploreKinds(true);
                })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column({ space: 0 }) {
              if (this.bookSourceViewMode === LibraryViewMode.LIST) {
                Column({ space: 8 }) {
                  ForEach(this.bookSourceBooks, (book: NovelSearchResult, index: number) => {
                    this.buildBookItem(book, index)
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16 })
              } else {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.bookSourceBooks, (book: NovelSearchResult, index: number) => {
                    Column() {
                      this.buildBookSourceGridCard(book, index)
                    }
                    .width('33.33%')
                    .padding(4)
                  })
                }
                .width('100%')
                .padding({ left: 12, right: 12 })
              }

              // 加载更多
              if (this.bookSourceHasMore) {
                Button('加载更多')
                  .width(120)
                  .height(36)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .backgroundColor(this.getCardBackground())
                  .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                  .backgroundEffect(this.getCardBackgroundEffect())
                  .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
                  .borderRadius(18)
                  .shadow({
                    radius: this.getCardRadius(),
                    color: this.getCardShadowColor(),
                    offsetX: 0,
                    offsetY: 2
                  })
                  .margin({ top: 12, bottom: 12 })
                  .onClick(() => {
                    this.bookSourceCurrentPage++;
                    this.loadBookSourceBooks(false);
                  })
              }

              Blank().height(this.bottomSpacerHeight)
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .onScrollFrameBegin((offset: number, _state: ScrollState) => {
            AppStorage.setOrCreate<number>('extracted_tab_scroll_delta', offset);
            return { offsetRemain: offset };
          })
          .onScrollStop(() => {
            AppStorage.setOrCreate<number>('extracted_tab_scroll_stop', Date.now());
          })
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.showBookSourcePicker, this.buildBookSourcePickerContent(), {
        height: SheetSize.MEDIUM,
        showClose: false,
        dragBar: true
      })
    }
  }
}
