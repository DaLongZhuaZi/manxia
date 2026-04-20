import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
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
import { getKomgaInstanceDisplayName } from '../Framework/Source/KomgaConfigStore';
import { KomgaImage } from '../components/KomgaImage';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

const TAG = 'KomgaLibraryDetailPage';
const PAGE_BOTTOM_SPACER: number = 30;
const INFO_TICKER_STEP_PX: number = 44;
const INFO_TICKER_INTERVAL_MS: number = 2400;
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
  private infoTickerScroller: Scroller = new Scroller();
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
  private infoTickerTimer: number = -1;
  private infoTickerDirection: number = 1;
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
    this.stopInfoTickerAutoScroll();
  }

  private color(name: KomgaLibraryDetailColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 1800 });
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

  private getFeedLabel(): string {
    if (this.searchQuery.trim().length > 0) {
      return '搜索';
    }
    if (this.feedType === 'LATEST') {
      return '最新';
    }
    return '热门';
  }

  private getContentTypeLabel(): string {
    if (this.contentType === 'READLISTS') {
      return '阅读列表';
    }
    if (this.contentType === 'BOOKS') {
      return '书籍';
    }
    return '系列';
  }

  private getCurrentInstanceLabel(): string {
    const currentId = this.getEffectiveInstanceId();
    if (currentId.length <= 0) {
      return '未连接实例';
    }
    const instances = this.executor.getInstances();
    const matched = instances.find((item) => item.id === currentId);
    if (matched !== undefined) {
      return getKomgaInstanceDisplayName(matched);
    }
    return '未连接实例';
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
      this.items = reset ? result.items : this.items.concat(result.items);
      this.currentPage = page;
      this.hasMore = result.hasMore;
      this.errorMessage = '';
      this.updateRefreshTimestamp();
      if (showSilentHint) {
        this.showRefreshHint();
      }
      void this.cacheCovers();
      logger.info(TAG, `Komga 库详情内容加载完成: libraryId=${this.libraryId}, page=${page}, received=${result.items.length}, totalItems=${this.items.length}, hasMore=${result.hasMore}`);
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

  private setContentType(contentType: KomgaContentType): void {
    if (this.contentType === contentType) {
      return;
    }
    this.contentType = contentType;
    void this.loadLibraryItems(true, true, true);
  }

  private setFeedType(feedType: KomgaFeedType): void {
    if (this.feedType === feedType) {
      return;
    }
    this.feedType = feedType;
    void this.loadLibraryItems(true, true, true);
  }

  private setSortKey(sortKey: KomgaSortKey): void {
    if (this.sortKey === sortKey) {
      return;
    }
    this.sortKey = sortKey;
    void this.loadLibraryItems(true, true, true);
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

  private getItemTypeLabel(item: ComicInfo): string {
    const contentType = this.getItemContentType(item);
    if (contentType === 'READLISTS') {
      return '阅读列表';
    }
    if (contentType === 'BOOKS') {
      return '书籍';
    }
    return '系列';
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

  private getSummaryText(): string {
    return `${this.getCurrentInstanceLabel()} · ${this.getContentTypeLabel()} · ${this.getSortLabel(this.sortKey)} · ${this.getFeedLabel()}`;
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

  private getSearchBadgeText(): string {
    const query = this.searchQuery.trim();
    if (query.length <= 0) {
      return '关键词：无';
    }
    if (query.length > 14) {
      return `关键词：${query.substring(0, 14)}...`;
    }
    return `关键词：${query}`;
  }

  private getRefreshStateLabel(): string {
    if (this.silentRefreshing) {
      return '静默刷新中';
    }
    if (this.isRefreshing || this.isLoading) {
      return '刷新中';
    }
    if (this.errorMessage.trim().length > 0) {
      return '刷新失败';
    }
    if (this.lastRefreshAtLabel === '等待刷新') {
      return '待同步';
    }
    return '已同步';
  }

  private startInfoTickerAutoScroll(): void {
    this.stopInfoTickerAutoScroll();
    this.infoTickerDirection = 1;
    this.infoTickerTimer = setInterval(() => {
      this.stepInfoTicker();
    }, INFO_TICKER_INTERVAL_MS);
  }

  private stopInfoTickerAutoScroll(): void {
    if (this.infoTickerTimer < 0) {
      return;
    }
    clearInterval(this.infoTickerTimer);
    this.infoTickerTimer = -1;
  }

  private stepInfoTicker(): void {
    const currentX = Number(this.infoTickerScroller.currentOffset()?.xOffset ?? 0);
    const targetX = Math.max(0, currentX + this.infoTickerDirection * INFO_TICKER_STEP_PX);
    this.infoTickerScroller.scrollTo({
      xOffset: targetX,
      yOffset: 0,
      animation: { duration: 460, curve: Curve.EaseInOut }
    });
    setTimeout(() => {
      const latestX = Number(this.infoTickerScroller.currentOffset()?.xOffset ?? 0);
      if (Math.abs(latestX - currentX) < 2) {
        this.infoTickerDirection = this.infoTickerDirection > 0 ? -1 : 1;
      }
    }, 520);
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
      const anchorTop = px2vp(Number(bottomAnchorRect.windowOffset.y));
      const viewportTop = px2vp(Number(viewportRect.windowOffset.y));
      const viewportBottom = viewportTop + px2vp(Number(viewportRect.size.height));
      const distanceToBottom = anchorTop - viewportBottom;
      if (distanceToBottom <= AUTO_LOAD_TRIGGER_DISTANCE_VP) {
        void this.loadLibraryItems(false);
      }
    } catch (_error) {
    }
  }

  @Builder
  private buildChip(label: string, selected: boolean, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(selected ? Color.White : this.color('text_primary'))
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(selected ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: selected ? Color.Transparent : this.color('panel_border')
    })
    .margin({ right: 8, bottom: 8 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => action())
  }

  @Builder
  private buildDisplayModeButton(icon: Resource, selected: boolean, action: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([selected ? Color.White : this.color('text_primary')])
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .borderRadius(18)
    .backgroundColor(selected ? this.color('accent_primary') : this.color('panel_background'))
    .border({
      width: 1,
      color: selected ? Color.Transparent : this.color('panel_border')
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => action())
  }

  @Builder
  private buildInfoBadge(text: string) {
    Text(text)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(this.color('text_muted'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.color('comp_background_tertiary'))
      .border({ width: 1, color: this.color('comp_divider') })
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private buildInfoTickerSection() {
    Scroll(this.infoTickerScroller) {
      Row({ space: 0 }) {
        this.buildInfoBadge(`实例：${this.getCurrentInstanceLabel()}`)
        this.buildInfoBadge(`库：${this.getResolvedLibraryName()}`)
        this.buildInfoBadge(`内容类型：${this.getContentTypeLabel()}`)
        this.buildInfoBadge(`动态：${this.getFeedLabel()}`)
        this.buildInfoBadge(`排序：${this.getSortLabel(this.sortKey)}`)
        this.buildInfoBadge(`显示：${this.displayMode === 'grid' ? '网格' : '列表'}`)
        this.buildInfoBadge(this.getSearchBadgeText())
        this.buildInfoBadge(`页码：${this.currentPage}`)
        this.buildInfoBadge(`结果：${this.items.length}`)
        this.buildInfoBadge(`刷新：${this.lastRefreshAtLabel}`)
        this.buildInfoBadge(`状态：${this.getRefreshStateLabel()}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(34)
  }

  @Builder
  private buildStatCard(title: string, value: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHeroSection() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.books_vertical_fill'))
            .fontSize(26)
            .fontColor([this.color('accent_blue')])
        }
        .width(48)
        .height(48)
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(16)

        Column({ space: 4 }) {
          Text(this.getResolvedLibraryName())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`库详情 · ${this.getSummaryText()}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Text('先在此页查看当前库，再进入具体漫画/阅读列表/书籍详情。支持网格或列表查看，并可按多种方式排序。')
        .fontSize(12)
        .lineHeight(18)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
        .width('100%')

      Text('信息滚动区（自动滚动，可手动拖动）')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
        .width('100%')

      this.buildInfoTickerSection()

      Row({ space: 8 }) {
        this.buildStatCard('内容', `${this.items.length}`)
        this.buildStatCard('查看', this.displayMode === 'grid' ? '网格' : '列表')
        this.buildStatCard('排序', this.getSortLabel(this.sortKey))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(20)
    .border({ width: 1, color: this.color('panel_border') })
  }

  @Builder
  private buildControlSection() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Search({ value: this.searchQuery, placeholder: '搜索当前库内容...' })
          .layoutWeight(1)
          .height(40)
          .searchButton('搜索')
          .onChange((value: string) => {
            this.searchQuery = value;
          })
          .onSubmit((_value: string) => {
            void this.loadLibraryItems(true, true, true);
          })

        Row({ space: 6 }) {
          this.buildDisplayModeButton(
            $r('sys.symbol.square_grid_2x2'),
            this.displayMode === 'grid',
            () => {
              this.setDisplayMode('grid');
            }
          )
          this.buildDisplayModeButton(
            $r('sys.symbol.list_bullet'),
            this.displayMode === 'list',
            () => {
              this.setDisplayMode('list');
            }
          )
        }
      }
      .width('100%')

      Text('内容类型')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
      Flex({ wrap: FlexWrap.Wrap }) {
        this.buildChip('系列', this.contentType === 'SERIES', () => this.setContentType('SERIES'))
        this.buildChip('阅读列表', this.contentType === 'READLISTS', () => this.setContentType('READLISTS'))
        this.buildChip('书籍', this.contentType === 'BOOKS', () => this.setContentType('BOOKS'))
      }

      Text('动态视图')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
      Flex({ wrap: FlexWrap.Wrap }) {
        this.buildChip('热门', this.feedType === 'POPULAR', () => this.setFeedType('POPULAR'))
        this.buildChip('最新', this.feedType === 'LATEST', () => this.setFeedType('LATEST'))
      }

      Text('排序方式')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(KOMGA_SORT_OPTIONS, (option: KomgaSortOption) => {
          this.buildChip(this.getSortLabel(option.key), this.sortKey === option.key, () => this.setSortKey(option.key))
        }, (option: KomgaSortOption) => option.key)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(18)
    .border({ width: 1, color: this.color('panel_border') })
  }

  @Builder
  private buildGridItem(item: ComicInfo) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        KomgaImage({
          src: this.getCoverUrl(item),
          imageWidth: '100%',
          imageHeight: 180,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 14,
          requestHeaders: this.executor.getImageHeaders(item.instanceId),
          cacheKey: this.getItemCacheKey(item)
        })
        Text(this.getItemTypeLabel(item))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('button_text_primary'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.color('accent_blue'))
          .borderRadius(999)
          .margin({ top: 10, right: 10 })
      }

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
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.description || '暂无简介')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .maxLines(3)
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
    Column({ space: 14 }) {
      Row() {
        Text(this.items.length > 0 ? `当前显示 ${this.items.length} 项` : '等待加载内容')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
        Blank()
        Text(`${this.getContentTypeLabel()} · ${this.getSortLabel(this.sortKey)}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
      }
      .width('100%')

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
        Column({ space: 12 }) {
          LoadingProgress()
          Text('正在加载当前库内容...')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
        }
        .width('100%')
        .padding(24)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(16)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.items.length <= 0) {
        Column({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.rectangle_stack'))
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
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.color('background_dark'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Refresh({ refreshing: $$this.isRefreshing }) {
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              this.buildHeroSection()
              this.buildControlSection()
              this.buildContentSection()
              Blank().height(PAGE_BOTTOM_SPACER).id(LIBRARY_BOTTOM_ANCHOR_ID)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 0, bottom: 0 })
            .opacity(this.pageContentOpacity)
            .backgroundColor(this.color('background_dark'))
          }
          .width('100%')
          .height('100%')
          .id(LIBRARY_SCROLL_ID)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onScroll((_xOffset: number, _yOffset: number) => {
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
          .position({ x: '50%', y: SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight) + 2 })
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
      this.startInfoTickerAutoScroll();
    })
    .backgroundColor(Color.Transparent)
  }
}
