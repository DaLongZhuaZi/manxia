import { promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import KomgaCacheManager from '../Framework/Source/KomgaCacheManager';
import { getKomgaSourceExecutor, KomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';
import {
  KomgaBrowseFilters,
  KomgaBrowseRequest,
  KomgaContentType,
  KomgaFeedType,
  KomgaLibraryOption,
  KomgaSortKey,
  KomgaSortOption,
  KOMGA_SORT_OPTIONS,
  createDefaultKomgaBrowseFilters
} from '../Framework/Source/KomgaModels';
import { KomgaImage } from '../components/KomgaImage';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'KomgaLibraryDetailPage';
const PAGE_BOTTOM_SPACER: number = 30;
const CONTROL_BLOCK_HEIGHT: number = 116;
const CONTROL_TOP_GAP: number = 12;
const CONTENT_TOP_GAP: number = 12;
const AUTO_LOAD_TRIGGER_DISTANCE_VP: number = 280;
const LIBRARY_SCROLL_ID: string = 'komga_library_detail_scroll';
const LIBRARY_BOTTOM_ANCHOR_ID: string = 'komga_library_detail_bottom_anchor';

export interface KomgaLibraryDetailParams {
  libraryId: string;
  libraryName?: string;
  instanceId?: string;
}

interface KomgaDetailParams {
  itemId: string;
  contentType: KomgaContentType;
  instanceId: string;
  title: string;
}

type KomgaLibraryDisplayMode = 'grid' | 'list';
type KomgaLibraryDetailColorKey =
  'accent_primary' |
  'accent_blue' |
  'background_dark' |
  'comp_background_tertiary' |
  'comp_divider' |
  'border_active' |
  'icon_primary' |
  'panel_background' |
  'panel_border' |
  'text_muted' |
  'text_primary' |
  'button_text_primary' |
  'button_text_secondary';

@Component
export struct KomgaLibraryDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pageContentOpacity: number = 0;

  @State libraryId: string = '';
  @State libraryName: string = '';
  @State instanceId: string = '';
  @State availableLibraries: KomgaLibraryOption[] = [];

  @State contentType: KomgaContentType = 'SERIES';
  @State feedType: KomgaFeedType = 'POPULAR';
  @State sortKey: KomgaSortKey = 'RELEVANCE';
  @State displayMode: KomgaLibraryDisplayMode = 'grid';
  @State searchQuery: string = '';

  @State items: ComicInfo[] = [];
  @State totalCount: number = 0;
  @State coverCachePaths: Map<string, string> = new Map();
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = false;
  @State currentPage: number = 1;
  @State errorMessage: string = '';
  @State refreshHintVisible: boolean = false;
  @State lastRefreshAtLabel: string = '等待刷新';
  @State silentRefreshing: boolean = false;

  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private componentId: string = 'KomgaLibraryDetailPage';
  private refreshHintTimer: number = -1;
  private searchDebounceTimer: number = -1;
  private lastAutoLoadCheckTime: number = 0;
  private requestSerial: number = 0;
  private latestResetRequestSerial: number = 0;
  private silentRefreshPendingCount: number = 0;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.refreshHintTimer >= 0) {
      clearTimeout(this.refreshHintTimer);
      this.refreshHintTimer = -1;
    }
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
      this.searchDebounceTimer = -1;
    }
  }

  private color(name: KomgaLibraryDetailColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  private revealPageContent(): void {
    const uiContext = this.getUIContext();
    if (uiContext === null || uiContext === undefined) {
      this.pageContentOpacity = 1;
      return;
    }
    uiContext.animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.pageContentOpacity = 1;
    });
  }

  private getEffectiveInstanceId(): string {
    if (this.instanceId.length > 0) {
      return this.instanceId;
    }
    const current = this.executor.getCurrentInstance();
    if (current !== null) {
      return current.id;
    }
    return '';
  }

  private getNormalizedStatusBarHeight(): number {
    if (this.statusBarHeight <= 0) {
      return SettingsPageTitleBarManager.DEFAULT_STATUS_BAR_INSET;
    }
    if (this.statusBarHeight <= 80) {
      return this.statusBarHeight;
    }
    const uiContext = this.getUIContext();
    if (uiContext !== null && uiContext !== undefined) {
      const convertedHeight = uiContext.px2vp(this.statusBarHeight);
      if (convertedHeight > 0 && convertedHeight < this.statusBarHeight) {
        return convertedHeight;
      }
    }
    return 64;
  }

  private getControlTopOffset(): number {
    return this.getNormalizedStatusBarHeight() +
      SettingsPageTitleBarManager.TITLE_BAR_TOP_OFFSET +
      SettingsPageTitleBarManager.TITLE_BAR_ROW_HEIGHT +
      CONTROL_TOP_GAP;
  }

  private getScrollContentTopPadding(): number {
    return this.getControlTopOffset() + CONTROL_BLOCK_HEIGHT + CONTENT_TOP_GAP;
  }

  private getSortLabel(sortKey: KomgaSortKey): string {
    switch (sortKey) {
      case 'ALPHABETICAL':
        return '名称';
      case 'DATE_ADDED':
        return '新增时间';
      case 'DATE_UPDATED':
        return '更新时间';
      case 'RANDOM':
        return '随机';
      case 'RELEVANCE':
      default:
        return '相关度';
    }
  }

  private getResolvedLibraryName(): string {
    const fromState = this.libraryName.trim();
    if (fromState.length > 0) {
      return fromState;
    }
    const matched = this.availableLibraries.find((item: KomgaLibraryOption) => item.id === this.libraryId);
    if (matched !== undefined) {
      return matched.name;
    }
    if (this.libraryId.length > 0) {
      return `书库 ${this.libraryId}`;
    }
    return '未选择书库';
  }

  private async syncLibraryContext(forceRefresh: boolean): Promise<void> {
    await this.executor.initialize(forceRefresh);
    if (this.instanceId.length > 0) {
      const currentInstance = this.executor.getCurrentInstance();
      if (currentInstance === null || currentInstance.id !== this.instanceId) {
        const switched = await this.executor.setCurrentInstance(this.instanceId);
        if (!switched) {
          logger.warn(TAG, `切换 Komga 实例失败，继续使用当前实例: expected=${this.instanceId}`);
        }
        await this.executor.initialize(true);
      }
    } else {
      const currentInstance = this.executor.getCurrentInstance();
      this.instanceId = currentInstance !== null ? currentInstance.id : '';
    }

    const filterOptions = await this.executor.getFilterOptions(forceRefresh);
    this.availableLibraries = filterOptions.libraries.concat();

    if (this.libraryName.trim().length <= 0) {
      const matched = this.availableLibraries.find((item: KomgaLibraryOption) => item.id === this.libraryId);
      if (matched !== undefined) {
        this.libraryName = matched.name;
      }
    }
  }

  private buildBrowseFilters(): KomgaBrowseFilters {
    const filters = createDefaultKomgaBrowseFilters();
    filters.selectedLibraryIds = this.libraryId.length > 0 ? [this.libraryId] : [];
    filters.sortKey = this.sortKey;
    return filters;
  }

  private async loadLibraryItems(
    reset: boolean,
    preserveExisting: boolean = false,
    showSilentHint: boolean = false
  ): Promise<void> {
    if (this.libraryId.length <= 0) {
      this.errorMessage = '缺少 Komga 书库 ID';
      this.totalCount = 0;
      this.isLoading = false;
      this.isLoadingMore = false;
      return;
    }

    const requestSerial = this.requestSerial + 1;
    this.requestSerial = requestSerial;
    let resetSerialSnapshot: number = this.latestResetRequestSerial;
    if (reset) {
      this.latestResetRequestSerial = requestSerial;
      resetSerialSnapshot = requestSerial;
    }

    if (reset) {
      this.currentPage = 0;
      if (!preserveExisting) {
        this.items = [];
        this.totalCount = 0;
      }
      this.isLoading = !preserveExisting;
      this.isLoadingMore = false;
      this.markRefreshingLabel(showSilentHint);
    } else {
      if (!this.hasMore || this.isLoadingMore) {
        return;
      }
      this.isLoadingMore = true;
    }

    this.beginSilentRefreshTracking(showSilentHint);

    try {
      const page = reset ? 1 : this.currentPage + 1;
      const query = this.searchQuery.trim();
      const request: KomgaBrowseRequest = {
        instanceId: this.getEffectiveInstanceId(),
        contentType: this.contentType,
        browseMode: 'library',
        feedType: query.length > 0 ? 'SEARCH' : this.feedType,
        page: page,
        query: query,
        filters: this.buildBrowseFilters()
      };
      logger.info(TAG, `加载 Komga 库详情内容: libraryId=${this.libraryId}, page=${page}, type=${request.contentType}, feed=${request.feedType}, sort=${request.filters.sortKey}, query="${request.query}"`);
      const result = await this.executor.browse(request);
      const isStaleResetRequest = reset && requestSerial !== this.latestResetRequestSerial;
      const isStaleLoadMoreRequest = !reset && resetSerialSnapshot !== this.latestResetRequestSerial;
      if (isStaleResetRequest || isStaleLoadMoreRequest) {
        logger.info(TAG, `忽略过期 Komga 库详情请求: requestSerial=${requestSerial}, latestResetSerial=${this.latestResetRequestSerial}`);
        return;
      }
      const mergedItems = reset ? result.items : this.items.concat(result.items);
      this.items = mergedItems;
      this.totalCount = result.totalCount > 0 ? result.totalCount : mergedItems.length;
      this.currentPage = page;
      this.hasMore = result.hasMore;
      this.errorMessage = '';
      this.updateRefreshTimestamp();
      if (showSilentHint) {
        this.showRefreshHint();
      }
      void this.cacheCovers();
      logger.info(TAG, `Komga 库详情内容加载完成: libraryId=${this.libraryId}, page=${page}, received=${result.items.length}, totalItems=${this.items.length}, totalCount=${this.totalCount}, hasMore=${result.hasMore}`);
    } catch (error) {
      const isStaleResetRequest = reset && requestSerial !== this.latestResetRequestSerial;
      const isStaleLoadMoreRequest = !reset && resetSerialSnapshot !== this.latestResetRequestSerial;
      if (isStaleResetRequest || isStaleLoadMoreRequest) {
        logger.info(TAG, `忽略过期 Komga 库详情异常请求: requestSerial=${requestSerial}, latestResetSerial=${this.latestResetRequestSerial}`);
        return;
      }
      logger.error(TAG, `加载 Komga 库详情内容失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
      if (reset) {
        this.markRefreshErrorLabel();
      }
      if (!preserveExisting) {
        this.items = [];
        this.totalCount = 0;
      }
    } finally {
      const shouldApplyLoadingState = reset
        ? requestSerial === this.latestResetRequestSerial
        : resetSerialSnapshot === this.latestResetRequestSerial;
      if (shouldApplyLoadingState) {
        this.isLoading = false;
        this.isLoadingMore = false;
        this.isRefreshing = false;
      }
      this.endSilentRefreshTracking(showSilentHint);
    }
  }

  private async loadPage(forceRefresh: boolean, preserveExisting: boolean = false): Promise<void> {
    if (this.libraryId.length <= 0) {
      this.errorMessage = '缺少 Komga 书库 ID';
      this.totalCount = 0;
      this.isLoading = false;
      return;
    }
    this.errorMessage = '';
    try {
      await this.syncLibraryContext(forceRefresh);
      await this.loadLibraryItems(true, preserveExisting);
    } catch (error) {
      logger.error(TAG, `加载 Komga 库详情页面失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  private async refreshContent(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    await this.loadPage(true, this.items.length > 0);
  }

  private scheduleSearchRefresh(): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
    }
    this.searchDebounceTimer = setTimeout(() => {
      this.searchDebounceTimer = -1;
      void this.loadLibraryItems(true, false, true);
    }, 420);
  }

  private submitSearchRefresh(): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
      this.searchDebounceTimer = -1;
    }
    void this.loadLibraryItems(true, false, true);
  }

  private setContentType(contentType: KomgaContentType): void {
    if (this.contentType === contentType) {
      return;
    }
    this.contentType = contentType;
    void this.loadLibraryItems(true, false, true);
  }

  private setFeedType(feedType: KomgaFeedType): void {
    if (this.feedType === feedType) {
      return;
    }
    this.feedType = feedType;
    void this.loadLibraryItems(true, false, true);
  }

  private setSortKey(sortKey: KomgaSortKey): void {
    if (this.sortKey === sortKey) {
      return;
    }
    this.sortKey = sortKey;
    void this.loadLibraryItems(true, false, true);
  }

  private setDisplayMode(displayMode: KomgaLibraryDisplayMode): void {
    if (this.displayMode === displayMode) {
      return;
    }
    this.displayMode = displayMode;
  }

  private getStringField(item: ComicInfo, key: string): string {
    const data: ESObject = item as ESObject;
    const raw: Object = data[key];
    return typeof raw === 'string' ? String(raw) : '';
  }

  private getNumberField(item: ComicInfo, key: string): number {
    const data: ESObject = item as ESObject;
    const raw: Object = data[key];
    if (typeof raw === 'number') {
      return Number(raw);
    }
    if (typeof raw === 'string') {
      const parsed = Number(raw);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private getItemContentType(item: ComicInfo): KomgaContentType {
    const rawType: string = this.getStringField(item, 'contentType');
    if (rawType === 'BOOKS') {
      return 'BOOKS';
    }
    if (rawType === 'READLISTS') {
      return 'READLISTS';
    }
    return 'SERIES';
  }

  private getItemKey(item: ComicInfo): string {
    return `${this.getItemContentType(item)}_${item.id}`;
  }

  private getItemCacheKey(item: ComicInfo): string {
    const instanceId = item.instanceId !== undefined && item.instanceId.length > 0 ? item.instanceId : this.getEffectiveInstanceId();
    return `${instanceId}_${this.getItemContentType(item)}_${item.id}`;
  }

  private setCoverCachePath(cacheKey: string, coverPath: string): void {
    const nextPaths: Map<string, string> = new Map(this.coverCachePaths);
    nextPaths.set(cacheKey, coverPath);
    this.coverCachePaths = nextPaths;
  }

  private async cacheCovers(): Promise<void> {
    let cacheHitCount: number = 0;
    let scheduledCount: number = 0;
    let skippedCount: number = 0;
    for (const item of this.items) {
      if (!item.coverUrl) {
        skippedCount++;
        continue;
      }
      const cacheKey = this.getItemCacheKey(item);
      if (this.coverCachePaths.has(cacheKey)) {
        skippedCount++;
        continue;
      }
      const cachedPath = KomgaCacheManager.getCachedCoverPath(cacheKey, item.coverUrl);
      if (cachedPath) {
        this.setCoverCachePath(cacheKey, cachedPath);
        cacheHitCount++;
        continue;
      }
      const headers = this.executor.getImageHeaders(item.instanceId);
      scheduledCount++;
      KomgaCacheManager.cacheCover(cacheKey, item.coverUrl, headers).then((path: string | null) => {
        if (path) {
          this.setCoverCachePath(cacheKey, path);
        }
      }).catch((_error: Object | string | number | boolean) => {
        logger.warn(TAG, `Komga 库详情封面预缓存失败: cacheKey=${cacheKey}`);
      });
    }
    logger.info(TAG, `Komga 库详情封面缓存检查完成: items=${this.items.length}, cacheHit=${cacheHitCount}, scheduled=${scheduledCount}, skipped=${skippedCount}`);
  }

  private getCoverUrl(item: ComicInfo): string {
    return item.coverUrl || '';
  }

  private getItemMetaLine(item: ComicInfo): string {
    const segments: string[] = [];
    const contentType = this.getItemContentType(item);
    if (contentType === 'READLISTS') {
      const bookCount = this.getNumberField(item, 'bookCount');
      segments.push(bookCount > 0 ? `${bookCount} 本内容` : '阅读列表');
    } else if (contentType === 'BOOKS') {
      const seriesTitle = this.getStringField(item, 'seriesTitle');
      const pageCount = this.getNumberField(item, 'pageCount');
      if (seriesTitle.length > 0) {
        segments.push(seriesTitle);
      }
      if (pageCount > 0) {
        segments.push(`${pageCount} 页`);
      }
    } else {
      if (item.author !== undefined && item.author.length > 0) {
        segments.push(item.author);
      }
      const publisher = this.getStringField(item, 'publisher');
      if (publisher.length > 0) {
        segments.push(publisher);
      }
      if (item.status !== undefined && item.status.length > 0 && item.status !== 'UNKNOWN') {
        segments.push(item.status);
      }
    }
    return segments.length > 0 ? segments.join(' · ') : '暂无元数据';
  }

  private openDetail(item: ComicInfo): void {
    const params: KomgaDetailParams = {
      itemId: item.id,
      contentType: this.getItemContentType(item),
      instanceId: item.instanceId !== undefined && item.instanceId.length > 0 ? item.instanceId : this.getEffectiveInstanceId(),
      title: item.title
    };
    logger.info(TAG, `打开 Komga 内容详情: libraryId=${this.libraryId}, itemId=${item.id}, type=${params.contentType}, instanceId=${params.instanceId}`);
    this.pathStack.pushPathByName('KomgaMangaDetailPage', params);
  }

  private getTitleBarTitle(): string {
    const libraryName = this.getResolvedLibraryName();
    if (libraryName.length > 0) {
      return libraryName;
    }
    return 'Komga 库详情';
  }

  private showRefreshHint(): void {
    this.refreshHintVisible = true;
    if (this.refreshHintTimer >= 0) {
      clearTimeout(this.refreshHintTimer);
    }
    this.refreshHintTimer = setTimeout(() => {
      this.refreshHintVisible = false;
      this.refreshHintTimer = -1;
    }, 1400);
  }

  private buildTimeLabel(): string {
    const now = new Date();
    const hour = String(now.getHours()).padStart(2, '0');
    const minute = String(now.getMinutes()).padStart(2, '0');
    const second = String(now.getSeconds()).padStart(2, '0');
    return `${hour}:${minute}:${second}`;
  }

  private updateRefreshTimestamp(): void {
    this.lastRefreshAtLabel = this.buildTimeLabel();
  }

  private markRefreshingLabel(showSilentHint: boolean): void {
    this.lastRefreshAtLabel = showSilentHint ? '静默刷新中' : '刷新中';
  }

  private markRefreshErrorLabel(): void {
    this.lastRefreshAtLabel = `刷新失败 ${this.buildTimeLabel()}`;
  }

  private beginSilentRefreshTracking(showSilentHint: boolean): void {
    if (!showSilentHint) {
      return;
    }
    this.silentRefreshPendingCount += 1;
    this.silentRefreshing = true;
  }

  private endSilentRefreshTracking(showSilentHint: boolean): void {
    if (!showSilentHint) {
      return;
    }
    if (this.silentRefreshPendingCount > 0) {
      this.silentRefreshPendingCount -= 1;
    }
    this.silentRefreshing = this.silentRefreshPendingCount > 0;
  }

  private checkAutoLoadMoreNearBottom(): void {
    if (!this.hasMore || this.isLoadingMore || this.isLoading || this.items.length <= 0) {
      return;
    }
    const now = new Date().getTime();
    if (now - this.lastAutoLoadCheckTime < 160) {
      return;
    }
    this.lastAutoLoadCheckTime = now;

    const uiContext = this.getUIContext();
    if (uiContext === null || uiContext === undefined) {
      return;
    }
    try {
      const componentUtils = uiContext.getComponentUtils();
      const bottomAnchorRect = componentUtils.getRectangleById(LIBRARY_BOTTOM_ANCHOR_ID);
      const viewportRect = componentUtils.getRectangleById(LIBRARY_SCROLL_ID);
      if (bottomAnchorRect === null || bottomAnchorRect === undefined ||
        viewportRect === null || viewportRect === undefined) {
        return;
      }
      const anchorTop = uiContext.px2vp(Number(bottomAnchorRect.windowOffset.y));
      const viewportTop = uiContext.px2vp(Number(viewportRect.windowOffset.y));
      const viewportBottom = viewportTop + uiContext.px2vp(Number(viewportRect.size.height));
      const distanceToBottom = anchorTop - viewportBottom;
      if (distanceToBottom <= AUTO_LOAD_TRIGGER_DISTANCE_VP) {
        void this.loadLibraryItems(false);
      }
    } catch (_error) {
    }
  }

  @Builder
  private buildContentTypeChip(label: string, contentType: KomgaContentType) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(this.contentType === contentType ? FontWeight.Medium : FontWeight.Regular)
        .fontFamily(this.appFontFamily)
        .fontColor(this.contentType === contentType ? Color.White : this.color('text_primary'))
    }
    .height(28)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(14)
    .backgroundColor(this.contentType === contentType ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: this.contentType === contentType ? Color.Transparent : this.color('panel_border')
    })
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .onClick(() => {
      this.setContentType(contentType);
    })
  }

  @Builder
  private buildFeedChip(label: string, feedType: KomgaFeedType) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontWeight(this.feedType === feedType ? FontWeight.Medium : FontWeight.Regular)
        .fontFamily(this.appFontFamily)
        .fontColor(this.feedType === feedType ? Color.White : this.color('text_primary'))
    }
    .height(28)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(14)
    .backgroundColor(this.feedType === feedType ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: this.feedType === feedType ? Color.Transparent : this.color('panel_border')
    })
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .onClick(() => {
      this.setFeedType(feedType);
    })
  }

  @Builder
  private buildSortChip(sortKey: KomgaSortKey) {
    Row() {
      Text(this.getSortLabel(sortKey))
        .fontSize(12)
        .fontWeight(this.sortKey === sortKey ? FontWeight.Medium : FontWeight.Regular)
        .fontFamily(this.appFontFamily)
        .fontColor(this.sortKey === sortKey ? Color.White : this.color('text_primary'))
        .maxLines(1)
    }
    .height(28)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(14)
    .backgroundColor(this.sortKey === sortKey ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: this.sortKey === sortKey ? Color.Transparent : this.color('panel_border')
    })
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .onClick(() => {
      this.setSortKey(sortKey);
    })
  }

  @Builder
  private buildDisplayModeButton(icon: Resource, displayMode: KomgaLibraryDisplayMode) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([this.displayMode === displayMode ? Color.White : this.color('text_primary')])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .backgroundColor(this.displayMode === displayMode ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: this.displayMode === displayMode ? Color.Transparent : this.color('panel_border')
    })
    .animation({ duration: 180, curve: Curve.EaseInOut })
    .onClick(() => {
      this.setDisplayMode(displayMode);
    })
  }

  @Builder
  private buildControlSection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Search({ value: this.searchQuery, placeholder: '搜索当前库内容...' })
          .layoutWeight(1)
          .height(36)
          .searchButton('搜索')
          .onChange((value: string) => {
            this.searchQuery = value;
            this.scheduleSearchRefresh();
          })
          .onSubmit((_value: string) => {
            this.submitSearchRefresh();
          })

        Row({ space: 6 }) {
          this.buildDisplayModeButton($r('sys.symbol.square_grid_2x2'), 'grid')
          this.buildDisplayModeButton($r('sys.symbol.list_bullet'), 'list')
        }
      }
      .width('100%')

      Scroll() {
        Row({ space: 6 }) {
          this.buildContentTypeChip('系列', 'SERIES')
          this.buildContentTypeChip('阅读列表', 'READLISTS')
          this.buildContentTypeChip('书籍', 'BOOKS')
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(30)

      Row({ space: 8 }) {
        Row({ space: 6 }) {
          this.buildFeedChip('热门', 'POPULAR')
          this.buildFeedChip('最新', 'LATEST')
        }

        Text('排序')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .margin({ left: 2 })

        Scroll() {
          Row({ space: 6 }) {
            ForEach(KOMGA_SORT_OPTIONS, (option: KomgaSortOption) => {
              this.buildSortChip(option.key)
            }, (option: KomgaSortOption) => `${option.key}_${this.sortKey}`)
          }
        }
        .layoutWeight(1)
        .height(30)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height(30)
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  private buildGridItem(item: ComicInfo) {
    Column({ space: 8 }) {
      KomgaImage({
        src: this.getCoverUrl(item),
        imageWidth: '100%',
        imageHeight: 180,
        objectFit: ImageFit.Cover,
        imgBorderRadius: 14,
        requestHeaders: this.executor.getImageHeaders(item.instanceId),
        cacheKey: this.getItemCacheKey(item)
      })

      Text(item.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getItemMetaLine(item))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .padding(12)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(18)
    .border({ width: 1, color: this.color('panel_border') })
    .onClick(() => this.openDetail(item))
  }

  @Builder
  private buildListItem(item: ComicInfo) {
    Row({ space: 12 }) {
      KomgaImage({
        src: this.getCoverUrl(item),
        imageWidth: 90,
        imageHeight: 128,
        objectFit: ImageFit.Cover,
        imgBorderRadius: 12,
        requestHeaders: this.executor.getImageHeaders(item.instanceId),
        cacheKey: this.getItemCacheKey(item)
      })

      Column({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getItemMetaLine(item))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(18)
    .border({ width: 1, color: this.color('panel_border') })
    .onClick(() => this.openDetail(item))
  }

  @Builder
  private buildContentSection() {
    Column({ space: 12 }) {
      if (this.errorMessage.length > 0 && this.items.length > 0) {
        Row({ space: 12 }) {
          Text(this.errorMessage)
            .layoutWeight(1)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('重试')
            .height(32)
            .backgroundColor(this.color('comp_background_tertiary'))
            .fontColor(this.color('button_text_secondary'))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              void this.refreshContent();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(14)
        .border({ width: 1, color: this.color('panel_border') })
      }

      if (this.errorMessage.length > 0 && this.items.length <= 0) {
        Column({ space: 12 }) {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#FF6B6B')
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
          Button('重新加载')
            .backgroundColor(this.color('accent_blue'))
            .fontColor(this.color('button_text_primary'))
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              void this.refreshContent();
            })
        }
        .width('100%')
        .padding(22)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(16)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.isLoading && this.items.length <= 0) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(this.color('accent_primary'))
          Text('正在加载当前库内容...')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
        }
        .width('100%')
        .padding(18)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(16)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.items.length <= 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(26)
            .fontColor([this.color('text_muted')])
          Text(this.searchQuery.trim().length > 0 ? '当前库没有匹配内容' : '当前库暂无可浏览内容')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
          Text('你可以切换内容类型、排序方式，或修改搜索关键字。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(24)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(16)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.displayMode === 'grid') {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.items, (item: ComicInfo) => {
            this.buildGridItem(item)
          }, (item: ComicInfo) => this.getItemKey(item))
        }
        .width('100%')
      } else {
        Column({ space: 12 }) {
          ForEach(this.items, (item: ComicInfo) => {
            this.buildListItem(item)
          }, (item: ComicInfo) => this.getItemKey(item))
        }
        .width('100%')
      }

      if (this.isLoadingMore) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(18)
            .height(18)
          Text('正在加载更多内容...')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
        }
        .width('100%')
        .padding({ top: 6, bottom: 4 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll(this.scroller) {
            Column({ space: 12 }) {
              Blank().height(this.getScrollContentTopPadding())
              this.buildContentSection()
              Blank().height(PAGE_BOTTOM_SPACER).id(LIBRARY_BOTTOM_ANCHOR_ID)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 0, bottom: 0 })
            .opacity(this.pageContentOpacity)
            .backgroundColor(Color.Transparent)
          }
          .width('100%')
          .height('100%')
          .id(LIBRARY_SCROLL_ID)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onDidScroll((_xOffset: number, _yOffset: number) => {
            this.checkAutoLoadMoreNearBottom();
          })
          .onReachEnd(() => {
            if (this.hasMore && !this.isLoadingMore) {
              void this.loadLibraryItems(false);
            }
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .onRefreshing(() => {
          void this.refreshContent();
        })
        .width('100%')
        .height('100%')

        Column() {
          this.buildControlSection()
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor(Color.Transparent)
        .position({ x: 0, y: this.getControlTopOffset() })
        .zIndex(8)
        .opacity(this.pageContentOpacity)

        if (this.refreshHintVisible) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([this.color('button_text_primary')])
            Text('已静默刷新')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.color('button_text_primary'))
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(this.color('accent_blue'))
          .borderRadius(18)
          .position({ x: '50%', y: this.getControlTopOffset() + 2 })
          .translate({ x: '-50%' })
          .opacity(this.refreshHintVisible ? 1 : 0)
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
          .hitTestBehavior(HitTestMode.None)
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.getTitleBarTitle(),
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 1200,
          pathStack: this.pathStack
        })
      }
      .width('100%')
      .height('100%')
    }
    .title(this.getTitleBarTitle())
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== undefined && param !== null) {
        const params = param as KomgaLibraryDetailParams;
        this.libraryId = String(params.libraryId || '').trim();
        this.libraryName = String(params.libraryName || '').trim();
        this.instanceId = String(params.instanceId || '').trim();
      }
      if (this.libraryId.length <= 0) {
        this.errorMessage = '缺少 Komga 书库 ID';
        this.isLoading = false;
      } else {
        void this.loadPage(false);
      }
    })
    .onShown(() => {
      this.revealPageContent();
    })
    .backgroundColor(Color.Transparent)
  }
}
