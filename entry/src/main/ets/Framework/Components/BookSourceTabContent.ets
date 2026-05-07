// 文件路径: src/main/ets/Framework/Components/BookSourceTabContent.ets
// 职责: 书源标签页内容组件，从MainMenuPage提取的独立组件

import { logger } from '../../Utils/Logger';
import { common } from '@kit.AbilityKit';
import { promptAction, curves } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { TabContentCacheManager } from '../Cache/TabContentCacheManager';
import { ContentFilterManager } from '../Managers/ContentFilterManager';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelInitializer } from '../Novel/NovelInitializer';
import { NovelBook, NovelReadStatus, NovelSearchResult, NovelSourceInfo } from '../../Models/NovelModels';
import { UnifiedDetailPageParams, UnifiedContentType } from '../../Models/UnifiedContentModels';
import { PageSettingsHelper, DetailPageType } from '../../pages/settings/PageSettingsSubPage';
import { NovelDetailPageParams, NovelSearchPageParams } from '../../pages/NovelBookshelfPage';
import { SettingsPageSurfaceManager } from '../../pages/settings/SettingsPageSurfaceManager';
import { AvifImage } from '../../components/AvifImage';
import { DataManager } from '../Data/DataManager';

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
  @State selectedBookSourceKindIndex: number = 0;
  @State bookSourceBooks: NovelSearchResult[] = [];
  @State isLoadingBookSource: boolean = false;
  @State isRefreshingBookSource: boolean = false;
  @State bookSourceCurrentPage: number = 1;
  @State bookSourceHasMore: boolean = true;
  @State showBookSourcePicker: boolean = false;
  @State bookSourceViewMode: LibraryViewMode = LibraryViewMode.LIST;
  @State bookSourceSearchInput: string = '';
  @State isBookSourceSearchMode: boolean = false;
  @State bookSourceKindsExpanded: boolean = false;
  @State bookSourceRefreshHintVisible: boolean = false;

  // 私有字段
  private bookSourceRefreshHintTimer: number = -1;
  private bookSourceListScroller: Scroller = new Scroller();
  private bookSourceModuleInitialized: boolean = false;
  private contentFilterManager: ContentFilterManager = ContentFilterManager.getInstance();
  private tabContentCacheManager: TabContentCacheManager = TabContentCacheManager.getInstance();

  // ============ 生命周期 ============

  aboutToAppear(): void {
    void ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState);
    this.restoreBookSourceFromCache();
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
      if (!this.bookSourceModuleInitialized) {
        this.isLoadingBookSource = this.bookSourceBooks.length === 0;
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        logger.debug(TAG, `使用缓存的书源数据: ${this.bookSourceList.length} 个书源, ${this.bookSourceBooks.length} 本书`);
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

  private restoreBookSourceFromCache(): void {
    if (this.tabContentCacheManager.hasBookSourceCache()) {
      const cache = this.tabContentCacheManager.getBookSourceCache();
      if (cache) {
        this.bookSourceList = cache.bookSourceList;
        this.filteredBookSourceList = cache.bookSourceList;
        this.selectedBookSourceId = cache.selectedBookSourceId;
        this.selectedBookSourceName = cache.selectedBookSourceName;
        this.bookSourceExploreKinds = cache.bookSourceExploreKinds;
        this.selectedBookSourceKindIndex = cache.selectedBookSourceKindIndex;
        this.bookSourceBooks = cache.bookSourceBooks;
        logger.info(TAG, `从缓存恢复书源数据: ${cache.bookSourceBooks.length} 本书, 书源: ${cache.selectedBookSourceName}`);
      }
    }
  }

  private saveBookSourceToCache(): void {
    if (this.bookSourceBooks.length === 0) return;
    this.tabContentCacheManager.saveBookSourceCache({
      bookSourceList: this.bookSourceList,
      selectedBookSourceId: this.selectedBookSourceId,
      selectedBookSourceName: this.selectedBookSourceName,
      bookSourceExploreKinds: this.bookSourceExploreKinds,
      selectedBookSourceKindIndex: this.selectedBookSourceKindIndex,
      bookSourceBooks: this.bookSourceBooks,
      timestamp: Date.now()
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
      if (existing.name !== next.name) { existing.name = next.name; hasChanges = true; }
      if (existing.url !== next.url) { existing.url = next.url; hasChanges = true; }
      if (existing.group !== next.group) { existing.group = next.group; hasChanges = true; }
      if (existing.enabled !== next.enabled) { existing.enabled = next.enabled; hasChanges = true; }
      if (existing.weight !== next.weight) { existing.weight = next.weight; hasChanges = true; }
      if (existing.customOrder !== next.customOrder) { existing.customOrder = next.customOrder; hasChanges = true; }
      if (existing.lastUpdateTime !== next.lastUpdateTime) { existing.lastUpdateTime = next.lastUpdateTime; hasChanges = true; }
      if (existing.respondTime !== next.respondTime) { existing.respondTime = next.respondTime; hasChanges = true; }
      if (existing.searchable !== next.searchable) { existing.searchable = next.searchable; hasChanges = true; }
      if (existing.hasExplore !== next.hasExplore) { existing.hasExplore = next.hasExplore; hasChanges = true; }
      if (existing.isTop !== next.isTop) { existing.isTop = next.isTop; hasChanges = true; }
      if (existing.isNSFW !== next.isNSFW) { existing.isNSFW = next.isNSFW; hasChanges = true; }
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
        if (existing.sourceName !== next.sourceName) { existing.sourceName = next.sourceName; hasChanges = true; }
        if (existing.name !== next.name) { existing.name = next.name; hasChanges = true; }
        if (existing.author !== next.author) { existing.author = next.author; hasChanges = true; }
        if (existing.kind !== next.kind) { existing.kind = next.kind; hasChanges = true; }
        if (existing.intro !== next.intro) { existing.intro = next.intro; hasChanges = true; }
        if (existing.coverUrl !== next.coverUrl) { existing.coverUrl = next.coverUrl; hasChanges = true; }
        if (existing.latestChapterTitle !== next.latestChapterTitle) { existing.latestChapterTitle = next.latestChapterTitle; hasChanges = true; }
        if (existing.wordCount !== next.wordCount) { existing.wordCount = next.wordCount; hasChanges = true; }
        if (existing.isNSFW !== next.isNSFW) { existing.isNSFW = next.isNSFW; hasChanges = true; }
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
        logger.debug(TAG, `书源列表静默刷新完成：${sourceListChanged ? '有变化' : '无变化'}，共 ${this.bookSourceList.length} 个`);
      } else {
        logger.info(TAG, `加载书源列表完成，共 ${this.bookSourceList.length} 个支持发现功能的书源`);
      }
      if (this.bookSourceList.length === 0) {
        this.selectedBookSourceId = '';
        this.selectedBookSourceName = '';
        this.bookSourceExploreKinds = [];
        this.selectedBookSourceKindIndex = 0;
        this.bookSourceBooks = [];
        this.bookSourceHasMore = false;
        return;
      }
      if (!this.selectedBookSourceId) {
        this.selectedBookSourceId = this.bookSourceList[0].id;
        this.selectedBookSourceName = this.bookSourceList[0].name;
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
        this.selectedBookSourceKindIndex = 0;
        this.bookSourceBooks = [];
        await this.loadBookSourceExploreKinds(loadBooks);
      }
    } catch (error) {
      logger.error(TAG, `加载书源列表失败: ${String(error)}`);
    }
  }

  private filterBookSourceList(keyword: string): void {
    let filtered: NovelSourceInfo[];
    if (!keyword.trim()) {
      filtered = this.bookSourceList;
    } else {
      const lowerKeyword = keyword.toLowerCase();
      filtered = this.bookSourceList.filter((source: NovelSourceInfo) =>
        source.name.toLowerCase().includes(lowerKeyword)
      );
    }
    this.filteredBookSourceList = this.contentFilterManager.filterContentList(filtered);
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

  private async loadBookSourceExploreKinds(loadBooks: boolean = true): Promise<void> {
    if (!this.selectedBookSourceId) return;
    try {
      const sourceManager = getNovelSourceManager();
      const newKinds = sourceManager.getExploreKinds(this.selectedBookSourceId);
      const cachedIndex = this.selectedBookSourceKindIndex;
      this.bookSourceExploreKinds = newKinds;
      if (cachedIndex >= 0 && cachedIndex < newKinds.length) {
        this.selectedBookSourceKindIndex = cachedIndex;
      } else {
        this.selectedBookSourceKindIndex = 0;
      }
      if (loadBooks && this.bookSourceExploreKinds.length > 0) {
        await this.loadBookSourceBooks(true);
      }
    } catch (error) {
      logger.error(TAG, `加载书源发现分类失败: ${String(error)}`);
    }
  }

  private async loadBookSourceBooks(reset: boolean = false): Promise<void> {
    if (!this.selectedBookSourceId || this.bookSourceExploreKinds.length === 0) return;
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
      const kind = this.bookSourceExploreKinds[this.selectedBookSourceKindIndex];
      const results = await sourceManager.explore(this.selectedBookSourceId, kind.url, this.bookSourceCurrentPage);
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
    } catch (error) {
      logger.error(TAG, `加载书源书籍失败: ${String(error)}`);
    }
    this.isLoadingBookSource = false;
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
      this.bookSourceCurrentPage = 1;
      this.bookSourceBooks = [];
      this.isBookSourceSearchMode = false;
      this.bookSourceSearchInput = '';
      this.showBookSourcePicker = false;
      this.bookSourceSearchKeyword = '';
      this.filterBookSourceList(this.bookSourceSearchKeyword);
      await this.loadBookSourceExploreKinds();
    } else {
      this.showBookSourcePicker = false;
      this.bookSourceSearchKeyword = '';
      this.filterBookSourceList(this.bookSourceSearchKeyword);
    }
  }

  private selectBookSourceKind(index: number): void {
    if (this.selectedBookSourceKindIndex !== index) {
      this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        this.selectedBookSourceKindIndex = index;
        this.bookSourceCurrentPage = 1;
        this.bookSourceBooks = [];
        this.isBookSourceSearchMode = false;
      });
      this.loadBookSourceBooks(true);
    }
  }

  private openBookDetail(book: NovelSearchResult): void {
    const pageType = PageSettingsHelper.getNovelDetailPageType();
    if (pageType === DetailPageType.UNIFIED) {
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.NOVEL,
        contentId: book.bookUrl,
        sourceId: book.sourceId,
        cachedTitle: book.name,
        cachedCover: book.coverUrl,
        cachedAuthor: book.author
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    } else {
      const params: NovelDetailPageParams = {
        sourceId: book.sourceId,
        bookUrl: book.bookUrl,
        bookName: book.name,
        author: book.author,
        kind: book.kind,
        intro: book.intro,
        coverUrl: book.coverUrl,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        sourceName: book.sourceName
      };
      this.pathStack.pushPathByName('NovelDetailPage', params);
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

  private scrollToSelectedBookSource(): void {
    if (!this.selectedBookSourceId || this.filteredBookSourceList.length === 0) return;
    const selectedIndex = this.filteredBookSourceList.findIndex((s: NovelSourceInfo) => s.id === this.selectedBookSourceId);
    if (selectedIndex > 0) {
      setTimeout(() => {
        this.bookSourceListScroller.scrollToIndex(selectedIndex, true, ScrollAlign.CENTER);
      }, 100);
    }
  }

  // ============ Builder 方法 ============

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
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.getCardBackground())
    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
    .backgroundEffect(this.getCardBackgroundEffect())
    .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
    .borderRadius(16)
    .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
    .onClick(() => { this.toggleBookSourceViewMode(); })
  }

  @Builder
  buildBookSourceGridCard(book: NovelSearchResult) {
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
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      .aspectRatio(0.7)
      .borderRadius(8)
      .clip(true)
      .onClick(() => this.openBookDetail(book))

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
      .onClick(() => this.openBookDetail(book))
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 4, bottom: 6 })
  }

  @Builder
  buildBookItem(book: NovelSearchResult) {
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
    .padding(12)
    .backgroundColor(this.getCardBackground())
    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
    .backgroundEffect(this.getCardBackgroundEffect())
    .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
    .borderRadius(16)
    .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
    .onClick(() => this.openBookDetail(book))
  }

  @Builder
  buildBookSourcePickerContent() {
    Column() {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.text_book_closed'))
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
          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(30)
          .height(30)
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(15)
          .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
          .clip(true)
          .onClick(() => {
            this.showBookSourcePicker = false;
            this.bookSourceSearchKeyword = '';
            this.filterBookSourceList(this.bookSourceSearchKeyword);
          })
        }
        .width('100%')

        TextInput({ placeholder: '输入书源名称进行筛选', text: this.bookSourceSearchKeyword })
          .width('100%')
          .height(42)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.bookSourceSearchKeyword = value;
            this.filterBookSourceList(value);
          })

        if (this.filteredBookSourceList.length > 0) {
          List({ scroller: this.bookSourceListScroller }) {
            ForEach(this.filteredBookSourceList, (source: NovelSourceInfo) => {
              ListItem() {
                Row() {
                  Text(source.name)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.selectedBookSourceId === source.id ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .fontWeight(this.selectedBookSourceId === source.id ? FontWeight.Medium : FontWeight.Normal)
                    .layoutWeight(1)
                  if (this.selectedBookSourceId === source.id) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(20)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                  }
                }
                .width('100%')
                .height(48)
                .padding({ left: 16, right: 16 })
                .backgroundColor(this.selectedBookSourceId === source.id ?
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                  Color.Transparent)
                .onClick(() => { void this.selectBookSource(source); })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
          .onAppear(() => { this.scrollToSelectedBookSource(); })
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
    Column({ space: 0 }) {
      Blank().height(this.topSpacerHeight)

      // 顶部操作栏
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.text_book_closed'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          Text(this.selectedBookSourceName || '选择书源')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .rotate({ angle: this.showBookSourcePicker ? 180 : 0 })
            .animation({ duration: 200 })
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.getCardBackground())
        .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
        .backgroundEffect(this.getCardBackgroundEffect())
        .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
        .borderRadius(20)
        .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
        .clip(true)
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
        .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
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
        .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
        .clip(true)
        .onClick(() => { this.pathStack.pushPathByName('NovelSettingsPage', null); })

        // 书源管理按钮
        Button() {
          SymbolGlyph($r('sys.symbol.text_book_closed'))
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
        .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
        .clip(true)
        .onClick(() => { this.pathStack.pushPathByName('NovelSourceManagementPage', null); })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.Transparent)

      // 状态行
      Row({ space: 12 }) {
        if (this.isBookSourceSearchMode) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('清除搜索')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.getCardBackground())
          .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
          .backgroundEffect(this.getCardBackgroundEffect())
          .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
          .borderRadius(20)
          .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
          .clip(true)
          .onClick(() => this.clearBookSourceSearch())
        }
        Blank()
        Row({ space: 8 }) {
          Text(`共 ${this.bookSourceList.length} 个书源`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getBookSourceReadableTertiaryColor())
          this.buildBookSourceViewModeToggleButton()
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

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
            Row({ space: 4 }) {
              Text(this.bookSourceKindsExpanded ? '收起' : '展开')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              SymbolGlyph(this.bookSourceKindsExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.getCardBackground())
            .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
            .backgroundEffect(this.getCardBackgroundEffect())
            .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
            .borderRadius(12)
            .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
            .clip(true)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                this.bookSourceKindsExpanded = !this.bookSourceKindsExpanded;
              });
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          if (this.bookSourceKindsExpanded) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.bookSourceExploreKinds, (kind: ExploreKind, index: number) => {
                Text(kind.title)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                  .backgroundColor(this.selectedBookSourceKindIndex === index ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
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
                  .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
                  .clip(true)
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
                    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                    .backgroundColor(this.selectedBookSourceKindIndex === index ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
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
                    .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
                    .clip(true)
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
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.getCardBackground())
        .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
        .backgroundEffect(this.getCardBackgroundEffect())
        .border({ width: this.getCardBorderWidth(), color: this.getCardBorderColor() })
        .borderRadius(20)
        .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
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
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            .opacity(0.45)
          Text(this.selectedBookSourceId ? '该书源暂无发现内容' : '请先选择一个书源')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getBookSourceReadableTertiaryColor())
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
                ForEach(this.bookSourceBooks, (book: NovelSearchResult) => {
                  this.buildBookItem(book)
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.bookSourceBooks, (book: NovelSearchResult) => {
                  Column() {
                    this.buildBookSourceGridCard(book)
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
                .shadow({ radius: this.getCardRadius(), color: this.getCardShadowColor(), offsetX: 0, offsetY: 2 })
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
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showBookSourcePicker, this.buildBookSourcePickerContent(), {
      height: SheetSize.MEDIUM,
      dragBar: true
    })
  }
}
