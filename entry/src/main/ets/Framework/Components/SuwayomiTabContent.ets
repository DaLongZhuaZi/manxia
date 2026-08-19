// 文件路径: src/main/ets/Framework/Components/SuwayomiTabContent.ets
// 职责: Suwayomi标签页内容组件，从MainMenuPage提取的独立组件

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { TabContentCacheManager } from '../Cache/TabContentCacheManager';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor, SuwayomiExtensionSource } from '../Source/SuwayomiSourceExecutor';
import { SuwayomiCategory, PaginatedResult, MangaSortOption, MANGA_SORT_OPTIONS } from '../Source/SuwayomiSource';
import SuwayomiCacheManager from '../Source/SuwayomiCacheManager';
import DownloadDirManager from '../Storage/DownloadDirManager';
import { ComicInfo as SuwayomiComicInfo } from '../Source/SourceExecutor';
import { SettingsPageSurfaceManager } from '../../pages/settings/SettingsPageSurfaceManager';
import { SuwayomiImage } from '../../components/SuwayomiImage';
import { SuwayomiSourceBrowseParams } from '../../pages/SuwayomiSourceBrowsePage';
import { eventBus, GameEvent, IEventPayload, RemoteLibraryConfigChangedPayload } from '../EventBus';
import { BasicDataSource } from 'manxia_core/src/main/ets/Utils/BasicDataSource';

const TAG = 'SuwayomiTabContent';

interface SuwayomiMangaDetailParams {
  mangaId: string;
  title: string;
}

@Component
export struct SuwayomiTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 125;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 主题状态
  @State private themeState: ThemeAwareState = new ThemeAwareState();

  // Suwayomi Tab相关状态
  @State suwayomiMangas: SuwayomiComicInfo[] = [];
  @State suwayomiSources: SuwayomiExtensionSource[] = [];
  @State suwayomiCategories: SuwayomiCategory[] = [];
  @State suwayomiSelectedCategoryId: number = -1;
  @State suwayomiBrowseMode: 'library' | 'sources' = 'library';
  @State suwayomiSearchQuery: string = '';
  @State suwayomiDisplayMode: 'grid' | 'list' = 'grid';
  @State isLoadingSuwayomi: boolean = false;
  @State isRefreshingSuwayomi: boolean = false;
  @State suwayomiTotalCount: number = 0;
  @State suwayomiHasMore: boolean = false;
  @State suwayomiCurrentOffset: number = 0;
  @State suwayomiSelectedSortIndex: number = 0;
  @State suwayomiCoverCachePaths: Map<string, string> = new Map();
  @State suwayomiErrorMessage: string = '';
  @State suwayomiSelectedLanguage: string = 'all';
  @State suwayomiAvailableLanguages: string[] = [];
  @State suwayomiPinnedSourceIds: string[] = [];
  @State suwayomiFilteredSourceCount: number = 0;
  @State suwayomiCategoriesExpanded: boolean = false;
  @State suwayomiRefreshHintVisible: boolean = false;

  // 私有字段
  private suwayomiRefreshHintTimer: number = -1;
  private suwayomiInitialized: boolean = false;
  private suwayomiExecutor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private tabContentCacheManager: TabContentCacheManager = TabContentCacheManager.getInstance();
  private readonly SUWAYOMI_PAGE_SIZE: number = 50;
  private readonly componentId: string = 'SuwayomiTabContent';
  private suwayomiSourceListDataSource: BasicDataSource<SuwayomiExtensionSource> =
    new BasicDataSource<SuwayomiExtensionSource>();
  private suwayomiSourceIconCacheEpoch: number = 0;
  private remoteConfigChangedListener: (payload: IEventPayload) => void = (payload: IEventPayload) => {
    this.handleRemoteConfigChanged(payload);
  };

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {});
    eventBus.subscribe(GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED, this.remoteConfigChangedListener);
    void this.tabContentCacheManager.initialize().then(() => {
      this.restoreSuwayomiFromCache();
    });
  }

  aboutToDisappear(): void {
    this.suwayomiSourceIconCacheEpoch += 1;
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    eventBus.unsubscribe(GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED, this.remoteConfigChangedListener);
    if (this.suwayomiRefreshHintTimer !== -1) {
      clearTimeout(this.suwayomiRefreshHintTimer);
      this.suwayomiRefreshHintTimer = -1;
    }
  }

  private onRefreshSignalChanged(): void {
    void this.silentInitializeSuwayomi();
  }

  private handleRemoteConfigChanged(payload: IEventPayload): void {
    const changedPayload = payload as RemoteLibraryConfigChangedPayload;
    if (changedPayload.provider !== 'suwayomi') {
      return;
    }
    logger.info(TAG, `收到 Suwayomi 配置变更事件，准备静默刷新: reason=${changedPayload.reason}`);
    void this.refreshAfterConfigChanged();
  }

  private async refreshAfterConfigChanged(): Promise<void> {
    this.suwayomiSourceIconCacheEpoch += 1;
    this.suwayomiInitialized = false;
    this.suwayomiErrorMessage = '';
    this.suwayomiSelectedCategoryId = -1;
    this.suwayomiCurrentOffset = 0;
    this.suwayomiHasMore = false;
    this.suwayomiTotalCount = 0;
    this.suwayomiMangas = [];
    this.suwayomiSources = [];
    this.suwayomiCategories = [];
    this.suwayomiCoverCachePaths = new Map<string, string>();
    this.suwayomiSourceListDataSource.setData(this.suwayomiSources);
    this.suwayomiFilteredSourceCount = 0;
    this.isLoadingSuwayomi = true;

    try {
      await this.suwayomiExecutor.initialize(true);
      if (!this.suwayomiExecutor.isConfigured()) {
        this.suwayomiErrorMessage = '请先配置 Suwayomi 服务器';
        void this.tabContentCacheManager.clearSuwayomiCache();
        return;
      }
      if (this.suwayomiBrowseMode === 'sources') {
        await this.loadSuwayomiSources();
      } else {
        await this.loadSuwayomiCategories();
        await this.loadSuwayomiLibraryForCategory(-1, true);
      }
      this.suwayomiInitialized = true;
    } catch (error) {
      logger.error(TAG, `Suwayomi 配置变更后刷新失败: ${String(error)}`);
      this.suwayomiErrorMessage = `刷新失败: ${String(error)}`;
    } finally {
      this.isLoadingSuwayomi = false;
    }
  }

  /**
   * 刷新Suwayomi内容（下拉刷新回调）
   */
  private async refreshSuwayomiContent(): Promise<void> {
    try {
      if (this.suwayomiBrowseMode === 'library') {
        await this.loadSuwayomiCategories();
        await this.loadSuwayomiLibrary(true);
      } else {
        await this.loadSuwayomiSources();
      }
    } catch (error) {
      logger.error(TAG, `刷新Suwayomi内容失败: ${String(error)}`);
    }
    this.isRefreshingSuwayomi = false;
  }

  /**
   * 初始Suwayomi
   * 支持内容缓存：冷启动时先显示缓存数据，然后静默刷新增量更新
   */
  private async initializeSuwayomi(): Promise<void> {
    if (this.suwayomiInitialized || this.isLoadingSuwayomi) return;

    // 缓存数据已在 aboutToAppear 中提前恢复，这里只做模块初始化和静默刷新
    this.isLoadingSuwayomi = this.suwayomiMangas.length === 0; // 有缓存则不显示加载状态
    this.suwayomiErrorMessage = '';
    try {
      await this.suwayomiExecutor.initialize();
      if (!this.suwayomiExecutor.isConfigured()) {
        this.suwayomiErrorMessage = '请先配置 Suwayomi 服务器';
        this.isLoadingSuwayomi = false;
        return;
      }
      await this.loadSuwayomiCategories();
      if (this.suwayomiSelectedCategoryId !== -1 &&
        !this.suwayomiCategories.find((category: SuwayomiCategory) => category.id === this.suwayomiSelectedCategoryId)) {
        this.suwayomiSelectedCategoryId = -1;
      }
      await this.loadSuwayomiLibrary(true);
      this.suwayomiInitialized = true;
    } catch (error) {
      logger.error(TAG, `初始Suwayomi失败: ${String(error)}`);
      this.suwayomiErrorMessage = `初始化失败: ${String(error)}`;
    }
    this.isLoadingSuwayomi = false;
  }

  /**
   * 静默初始Suwayomi（切换标签时调用，有缓存则不重新加载）
   */
  private async silentInitializeSuwayomi(): Promise<void> {
    // 如果已初始化且有数据（漫画或图源），不重新加载
    if (this.suwayomiInitialized && (this.suwayomiMangas.length > 0 || this.suwayomiSources.length > 0)) {
      logger.info(TAG, 'Suwayomi已有缓存数据，跳过加载');
      return;
    }
    await this.initializeSuwayomi();
  }

  /**
   * 从持久化缓存恢复Suwayomi Tab数据
   */
  private restoreSuwayomiFromCache(): void {
    if (this.tabContentCacheManager.hasSuwayomiCache()) {
      const cache = this.tabContentCacheManager.getSuwayomiCache();
      if (cache) {
        this.suwayomiMangas = cache.mangas as SuwayomiComicInfo[];
        this.suwayomiCategories = cache.categories;
        this.suwayomiSelectedCategoryId = cache.selectedCategoryId;
        this.suwayomiSelectedSortIndex = cache.selectedSortIndex;
        this.suwayomiBrowseMode = cache.browseMode as 'library' | 'sources';
        this.suwayomiTotalCount = cache.totalCount;
        this.suwayomiHasMore = cache.hasMore;
        this.suwayomiCurrentOffset = cache.currentOffset;
        logger.info(TAG, `从缓存恢复Suwayomi数据: ${cache.mangas.length} 部漫画, ${cache.categories.length} 个分类`);
        // 恢复缓存后重新缓存封面（从本地文件缓存中查找）
        this.cacheSuwayomiCovers();
      }
    }
  }

  /**
   * 保存Suwayomi Tab当前状态到缓存
   */
  private saveSuwayomiToCache(): void {
    this.tabContentCacheManager.saveSuwayomiCache({
      mangas: this.suwayomiMangas,
      categories: this.suwayomiCategories,
      selectedCategoryId: this.suwayomiSelectedCategoryId,
      selectedSortIndex: this.suwayomiSelectedSortIndex,
      browseMode: this.suwayomiBrowseMode,
      totalCount: this.suwayomiTotalCount,
      hasMore: this.suwayomiHasMore,
      currentOffset: this.suwayomiCurrentOffset,
      timestamp: Date.now()
    });
  }

  /**
   * 加载Suwayomi分类
   */
  private async loadSuwayomiCategories(): Promise<void> {
    try {
      this.suwayomiCategories = await this.suwayomiExecutor.getCategories();
      logger.info(TAG, `加载Suwayomi分类: ${this.suwayomiCategories.length} 个`);
    } catch (error) {
      logger.error(TAG, `加载Suwayomi分类失败: ${String(error)}`);
    }
  }

  /**
   * 显示Suwayomi刷新提示浮层
   */
  private showSuwayomiRefreshHint(): void {
    if (this.suwayomiRefreshHintTimer !== -1) {
      clearTimeout(this.suwayomiRefreshHintTimer);
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.suwayomiRefreshHintVisible = true;
    });
    this.suwayomiRefreshHintTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
        this.suwayomiRefreshHintVisible = false;
      });
      this.suwayomiRefreshHintTimer = -1;
    }, 2000) as number;
  }

  /**
   * 加载Suwayomi库漫画
   * 静默刷新：当 reset=true 且已有缓存数据时，保留旧数据显示，加载完成后再替换并显示刷新提示
   */
  private async loadSuwayomiLibrary(reset: boolean = false): Promise<void> {
    await this.loadSuwayomiLibraryForCategory(this.suwayomiSelectedCategoryId, reset);
  }

  private async loadSuwayomiLibraryForCategory(categoryId: number, reset: boolean = false): Promise<void> {
    const hasCachedData = reset && this.suwayomiMangas.length > 0;
    if (reset) {
      this.suwayomiCurrentOffset = 0;
      // 静默刷新：保留旧数据，不清空
      if (!hasCachedData) {
        this.suwayomiMangas = [];
      }
    }
    // 没有缓存数据时才显示全屏加载状态
    if (!hasCachedData) {
      this.isLoadingSuwayomi = reset;
    }
    this.suwayomiBrowseMode = 'library';
    this.suwayomiErrorMessage = '';
    try {
      const sortOption = MANGA_SORT_OPTIONS[this.suwayomiSelectedSortIndex];
      const result: PaginatedResult<SuwayomiComicInfo> = await this.suwayomiExecutor.getLibraryPaginated(
        categoryId,
        this.suwayomiCurrentOffset,
        this.SUWAYOMI_PAGE_SIZE,
        sortOption.type,
        sortOption.direction
      );
      if (reset) {
        this.suwayomiMangas = result.items;
        // 静默刷新完成，显示刷新提示胶囊
        if (hasCachedData && result.items.length > 0) {
          this.showSuwayomiRefreshHint();
        }
      } else {
        this.suwayomiMangas = this.suwayomiMangas.concat(result.items);
      }
      this.suwayomiTotalCount = result.totalCount;
      this.suwayomiHasMore = result.hasMore;
      this.suwayomiCurrentOffset += result.items.length;
      this.cacheSuwayomiCovers();
      // 保存到持久化缓存
      this.saveSuwayomiToCache();
    } catch (error) {
      logger.error(TAG, `加载Suwayomi库失败: ${String(error)}`);
      this.suwayomiErrorMessage = `加载失败: ${String(error)}`;
    }
    this.isLoadingSuwayomi = false;
  }

  private selectSuwayomiCategory(categoryId: number): void {
    if (this.suwayomiSelectedCategoryId === categoryId && this.suwayomiBrowseMode === 'library') {
      return;
    }
    this.suwayomiSelectedCategoryId = categoryId;
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseInOut
    }, () => {
      this.suwayomiSelectedCategoryId = categoryId;
    });
    void this.loadSuwayomiLibraryForCategory(categoryId, true);
  }

  /**
   * 加载Suwayomi图源
   */
  private async loadSuwayomiSources(): Promise<void> {
    this.isLoadingSuwayomi = true;
    this.suwayomiBrowseMode = 'sources';
    this.suwayomiErrorMessage = '';
    try {
      this.suwayomiSources = await this.suwayomiExecutor.getAvailableSources();
      this.extractSuwayomiLanguages();
      this.syncFilteredSuwayomiSources('load');
      this.scheduleSuwayomiSourceIconCaching();
      logger.info(TAG, `加载Suwayomi图源: ${this.suwayomiSources.length} 个`);
    } catch (error) {
      logger.error(TAG, `加载Suwayomi图源失败: ${String(error)}`);
      this.suwayomiErrorMessage = `加载失败: ${String(error)}`;
    }
    this.isLoadingSuwayomi = false;
  }

  /**
   * 将 Suwayomi 资源路径（可能是相对路径）转为完整 URL
   */
  private isSuwayomiHostLikeUrlWithoutScheme(url: string): boolean {
    const slashIndex = url.indexOf('/');
    const hostPart = slashIndex >= 0 ? url.substring(0, slashIndex) : url;
    const pathPart = slashIndex >= 0 ? url.substring(slashIndex) : '';
    if (!hostPart) {
      return false;
    }
    const isIpv4Host = /^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?$/.test(hostPart);
    const isNamedHost = /^(localhost|[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+)(?::\d+)?$/.test(hostPart);
    if (!isIpv4Host && !isNamedHost) {
      return false;
    }
    return hostPart.includes(':') || pathPart.startsWith('/');
  }

  private resolveSuwayomiAssetUrl(rawUrl: string): string {
    const url = (rawUrl || '').trim();
    if (!url) {
      return '';
    }
    if (url.includes('://') || url.startsWith('data:') || url.startsWith('file:')) {
      return url;
    }

    const serverUrlRaw = (this.suwayomiExecutor.getServerUrl() || '').trim();
    if (!serverUrlRaw) {
      return url;
    }
    const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(serverUrlRaw);
    const normalizedServerUrl = hasScheme ? serverUrlRaw : `http://${serverUrlRaw}`;
    const serverUrl = normalizedServerUrl.endsWith('/') ?
      normalizedServerUrl.substring(0, normalizedServerUrl.length - 1) :
      normalizedServerUrl;
    const protocol = serverUrl.startsWith('https://') ? 'https:' : 'http:';

    if (url.startsWith('//')) {
      return `${protocol}${url}`;
    }
    if (this.isSuwayomiHostLikeUrlWithoutScheme(url)) {
      return `${protocol}//${url}`;
    }
    if (url.startsWith('/')) {
      return `${serverUrl}${url}`;
    }
    return `${serverUrl}/${url}`;
  }

  /**
   * 获取图源图标URL（优先使用缓存）
   */
  private getSuwayomiSourceIconUrl(source: SuwayomiExtensionSource): string {
    if (source.iconUrl) {
      const fullIconUrl = this.resolveSuwayomiAssetUrl(source.iconUrl);
      const cachedPath = SuwayomiCacheManager.getCachedSourceIconPath(source.id, fullIconUrl);
      return cachedPath ? `file://${cachedPath}` : fullIconUrl;
    }
    return '';
  }

  private scheduleSuwayomiSourceIconCaching(): void {
    this.suwayomiSourceIconCacheEpoch += 1;
    const cacheEpoch = this.suwayomiSourceIconCacheEpoch;
    void this.cacheSuwayomiSourceIconsSequentially(cacheEpoch);
  }

  private async cacheSuwayomiSourceIconsSequentially(cacheEpoch: number): Promise<void> {
    if (!DownloadDirManager.isReady()) {
      return;
    }
    const headers = this.suwayomiExecutor.getImageHeaders();
    const sources = this.suwayomiSources.concat();
    let cachedCount = 0;
    for (const source of sources) {
      if (cacheEpoch !== this.suwayomiSourceIconCacheEpoch) {
        return;
      }
      if (!source.iconUrl) {
        continue;
      }
      const fullIconUrl = this.resolveSuwayomiAssetUrl(source.iconUrl);
      if (!fullIconUrl || SuwayomiCacheManager.getCachedSourceIconPath(source.id, fullIconUrl)) {
        continue;
      }
      const cachedPath = await SuwayomiCacheManager.cacheSourceIcon(source.id, fullIconUrl, headers);
      if (cacheEpoch !== this.suwayomiSourceIconCacheEpoch) {
        return;
      }
      if (cachedPath) {
        cachedCount += 1;
      }
    }
    logger.debug(TAG, `Suwayomi图源图标串行缓存完成: cached=${cachedCount}, total=${sources.length}`);
  }

  /**
   * 获取筛选后的Suwayomi图源列表
   */
  private getFilteredSuwayomiSources(): SuwayomiExtensionSource[] {
    if (!this.suwayomiSources || this.suwayomiSources.length === 0) {
      return [];
    }
    let filtered: SuwayomiExtensionSource[] = [];
    for (const s of this.suwayomiSources) {
      filtered.push(s);
    }
    // 按语言筛选
    if (this.suwayomiSelectedLanguage !== 'all') {
      filtered = filtered.filter((s: SuwayomiExtensionSource) => s.lang === this.suwayomiSelectedLanguage);
    }
    // 按搜索词筛选
    if (this.suwayomiSearchQuery && this.suwayomiSearchQuery.trim()) {
      const query = this.suwayomiSearchQuery.toLowerCase();
      filtered = filtered.filter((s: SuwayomiExtensionSource) =>
        (s.name && s.name.toLowerCase().includes(query)) ||
        (s.lang && s.lang.toLowerCase().includes(query))
      );
    }
    // 排序：置顶的在前面
    const pinnedIds = this.suwayomiPinnedSourceIds || [];
    return filtered.sort((a: SuwayomiExtensionSource, b: SuwayomiExtensionSource) => {
      const aPinned = pinnedIds.includes(a.id);
      const bPinned = pinnedIds.includes(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return (a.name || '').localeCompare(b.name || '');
    });
  }

  private syncFilteredSuwayomiSources(reason: string): void {
    const filteredSources = this.getFilteredSuwayomiSources();
    this.suwayomiSourceListDataSource.setData(filteredSources);
    this.suwayomiFilteredSourceCount = filteredSources.length;
    logger.debug(TAG, `刷新Suwayomi图源惰性列表: reason=${reason}, count=${filteredSources.length}`);
  }

  /**
   * 切换Suwayomi图源置顶状态
   */
  private toggleSuwayomiSourcePin(sourceId: string): void {
    const index = this.suwayomiPinnedSourceIds.indexOf(sourceId);
    if (index >= 0) {
      this.suwayomiPinnedSourceIds.splice(index, 1);
    } else {
      this.suwayomiPinnedSourceIds.push(sourceId);
    }
    this.suwayomiPinnedSourceIds = [...this.suwayomiPinnedSourceIds]; // 触发更新
    this.syncFilteredSuwayomiSources('pin');
  }

  /**
   * 检查Suwayomi图源是否已置顶
   */
  private isSuwayomiSourcePinned(sourceId: string): boolean {
    return this.suwayomiPinnedSourceIds.includes(sourceId);
  }

  /**
   * 选择Suwayomi图源（跳转到图源浏览页面）
   * 如果有搜索关键词，会带上关键词进行自动搜索
   */
  private selectSuwayomiSource(source: SuwayomiExtensionSource): void {
    const params: SuwayomiSourceBrowseParams = {
      source: source,
      keyword: this.suwayomiSearchQuery.trim() || undefined
    };
    this.pathStack.pushPathByName('SuwayomiSourceBrowsePage', params);
  }

  /**
   * 获取筛选后的Suwayomi漫画列表（库模式下的本地筛选）
   */
  private getFilteredSuwayomiMangas(): SuwayomiComicInfo[] {
    if (!this.suwayomiMangas || this.suwayomiMangas.length === 0) {
      return [];
    }
    // 如果没有搜索词，返回全部
    if (!this.suwayomiSearchQuery || !this.suwayomiSearchQuery.trim()) {
      return this.suwayomiMangas;
    }
    // 按标题筛选
    const query = this.suwayomiSearchQuery.toLowerCase();
    return this.suwayomiMangas.filter((manga: SuwayomiComicInfo) =>
      manga.title && manga.title.toLowerCase().includes(query)
    );
  }

  /**
   * 提取可用语言
   */
  private extractSuwayomiLanguages(): void {
    const langSet = new Set<string>();
    this.suwayomiSources.forEach((source: SuwayomiExtensionSource) => {
      if (source.lang) langSet.add(source.lang);
    });
    const priorityLangs = ['zh', 'en', 'ja', 'jp'];
    const allLangs = Array.from(langSet);
    const prioritized = priorityLangs.filter((lang: string) => allLangs.includes(lang));
    const others = allLangs.filter((lang: string) => !priorityLangs.includes(lang)).sort();
    this.suwayomiAvailableLanguages = [...prioritized, ...others];
  }

  /**
   * 缓存Suwayomi封面
   */
  private async cacheSuwayomiCovers(): Promise<void> {
    if (!DownloadDirManager.isReady()) return;
    const headers = this.suwayomiExecutor.getImageHeaders();
    for (const manga of this.suwayomiMangas) {
      if (manga.coverUrl && !this.suwayomiCoverCachePaths.has(manga.id)) {
        const cachedPath = SuwayomiCacheManager.getCachedCoverPath(manga.id, manga.coverUrl);
        if (cachedPath) {
          this.suwayomiCoverCachePaths.set(manga.id, cachedPath);
        } else {
          SuwayomiCacheManager.cacheCover(manga.id, manga.coverUrl, headers).then((path: string | null) => {
            if (path) {
              this.suwayomiCoverCachePaths.set(manga.id, path);
              this.suwayomiCoverCachePaths = new Map(this.suwayomiCoverCachePaths);
            }
          });
        }
      }
    }
  }

  /**
   * 获取漫画封面URL
   */
  private getSuwayomiCoverUrl(manga: SuwayomiComicInfo): string {
    return manga.coverUrl || '';
  }

  /**
   * 打开Suwayomi漫画详情
   */
  private openSuwayomiMangaDetail(manga: SuwayomiComicInfo): void {
    const params: SuwayomiMangaDetailParams = { mangaId: manga.id, title: manga.title };
    this.pathStack.pushPathByName('SuwayomiMangaDetailPage', params);
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

  private getCardChevronColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.chevronColor;
  }

  private getCardChevronOpacity(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.chevronOpacity;
  }

  // ============ @Builder 方法 ============

  @Builder
  buildSuwayomiMangaGridItem(manga: SuwayomiComicInfo) {
    Column({ space: 6 }) {
      if (manga.coverUrl) {
        SuwayomiImage({
          src: this.getSuwayomiCoverUrl(manga),
          imageWidth: '100%',
          imgAspectRatio: 0.7,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(manga.title.charAt(0))
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .aspectRatio(0.7)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      Text(manga.title)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(4)
    .onClick(() => this.openSuwayomiMangaDetail(manga))
  }

  @Builder
  buildSuwayomiMangaListItem(manga: SuwayomiComicInfo) {
    Row({ space: 12 }) {
      if (manga.coverUrl) {
        SuwayomiImage({
          src: this.getSuwayomiCoverUrl(manga),
          imageWidth: 60,
          imageHeight: 80,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(manga.title.charAt(0))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width(60)
        .height(80)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text(manga.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)
        if (manga.author) {
          Text(manga.author)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(this.appFontFamily)
        }
        if (manga.status) {
          Text(manga.status)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.openSuwayomiMangaDetail(manga))
  }

  @Builder
  buildSuwayomiSourceGridItem(source: SuwayomiExtensionSource) {
    Column({ space: 8 }) {
      Stack() {
        if (source.iconUrl) {
          SuwayomiImage({
            src: this.getSuwayomiSourceIconUrl(source),
            imageWidth: 60,
            imageHeight: 60,
            imgBorderRadius: 12,
            objectFit: ImageFit.Cover
          })
        } else {
          Column() {
            Text(source.name.charAt(0))
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .fontFamily(this.appFontFamily)
          }
          .width(60)
          .height(60)
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
        }

        if (this.isSuwayomiSourcePinned(source.id)) {
          Column() {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(12)
              .fontColor([Color.White])
          }
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
          .position({ x: -4, y: -4 })
        }
      }

      Text(source.name)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Text(source.lang?.toUpperCase() || '')
        .fontSize(10)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.selectSuwayomiSource(source))
    .gesture(LongPressGesture().onAction(() => {
      this.toggleSuwayomiSourcePin(source.id);
    }))
  }

  @Builder
  buildSuwayomiSourceListItem(source: SuwayomiExtensionSource) {
    Row({ space: 12 }) {
      if (source.iconUrl) {
        SuwayomiImage({
          src: this.getSuwayomiSourceIconUrl(source),
          imageWidth: 40,
          imageHeight: 40,
          imgBorderRadius: 8,
          objectFit: ImageFit.Cover
        })
      } else {
        Column() {
          Text(source.name.charAt(0))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
        }
        .width(40)
        .height(40)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 4 }) {
        Row({ space: 4 }) {
          if (this.isSuwayomiSourcePinned(source.id)) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          }
          Text(source.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(source.lang?.toUpperCase() || '')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (source.isNsfw) {
        Text('18+')
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#FF6B6B')
          .borderRadius(4)
          .fontFamily(this.appFontFamily)
      }

      // 置顶按钮
      Button() {
        SymbolGlyph(this.isSuwayomiSourcePinned(source.id) ? $r('sys.symbol.pin_slash') : $r('sys.symbol.pin'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.getCardBackground())
      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
      .backgroundEffect(this.getCardBackgroundEffect())
      .border({
        width: this.getCardBorderWidth(),
        color: this.getCardBorderColor()
      })
      .borderRadius(18)
      .shadow({
        radius: this.getCardRadius(),
        color: this.getCardShadowColor(),
        offsetX: 0,
        offsetY: 2
      })
      .clip(true)
      .onClick(() => {
        this.toggleSuwayomiSourcePin(source.id);
      })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => this.selectSuwayomiSource(source))
  }

  @Builder
  buildSuwayomiBottomNav() {
    Column() {
      Divider()
        .width('100%')
        .height(0.5)
        .color(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      Row({ space: 0 }) {
        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.bookshelf'))
            .fontSize(24)
            .fontColor([this.suwayomiBrowseMode === 'library' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('库')
            .fontSize(12)
            .fontColor(this.suwayomiBrowseMode === 'library' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          // 使用动画过渡切换到库模式
          if (this.suwayomiBrowseMode !== 'library') {
            this.getUIContext().animateTo({
              duration: 250,
              curve: Curve.EaseInOut
            }, () => {
              this.suwayomiBrowseMode = 'library';
            });
          }
          this.loadSuwayomiLibrary(true);
        })

        Column({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(24)
            .fontColor([this.suwayomiBrowseMode === 'sources' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          Text('源')
            .fontSize(12)
            .fontColor(this.suwayomiBrowseMode === 'sources' ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          // 使用动画过渡切换到源模式
          if (this.suwayomiBrowseMode !== 'sources') {
            this.getUIContext().animateTo({
              duration: 250,
              curve: Curve.EaseInOut
            }, () => {
              this.suwayomiBrowseMode = 'sources';
            });
          }
          this.loadSuwayomiSources();
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: 8 })
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THIN, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.5
    })
    .shadow({ radius: 16, color: this.themeState.currentTheme === ThemeType.DARK ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.15)', offsetX: 0, offsetY: -4 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildSuwayomiSortMenu() {
    Menu() {
      ForEach(MANGA_SORT_OPTIONS, (option: MangaSortOption, index: number) => {
        MenuItem({ content: option.label })
          .selected(index === this.suwayomiSelectedSortIndex)
          .onClick(() => {
            if (this.suwayomiSelectedSortIndex !== index) {
              this.suwayomiSelectedSortIndex = index;
              this.loadSuwayomiLibrary(true);
            }
          })
      })
    }
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshingSuwayomi }) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容区域
        Column() {
          // 顶部工具栏
          Blank().height(this.topSpacerHeight)
          Row({ space: 8 }) {
            Search({ value: this.suwayomiSearchQuery, placeholder: this.suwayomiBrowseMode === 'library' ? '搜索漫画...' : '搜索图源...' })
              .layoutWeight(1)
              .height(40)
              .searchButton('搜索')
              .onChange((value: string) => {
                this.suwayomiSearchQuery = value;
                if (this.suwayomiBrowseMode === 'sources') {
                  this.syncFilteredSuwayomiSources('search');
                }
              })

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
            .border({
              width: this.getCardBorderWidth(),
              color: this.getCardBorderColor()
            })
            .borderRadius(12)
            .shadow({
              radius: this.getCardRadius(),
              color: this.getCardShadowColor(),
              offsetX: 0,
              offsetY: 2
            })
            .clip(true)
            .onClick(() => {
              this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
            })

            Button() {
              SymbolGlyph(this.suwayomiDisplayMode === 'grid' ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(40)
            .height(40)
            .backgroundColor(this.getCardBackground())
            .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
            .backgroundEffect(this.getCardBackgroundEffect())
            .border({
              width: this.getCardBorderWidth(),
              color: this.getCardBorderColor()
            })
            .borderRadius(12)
            .shadow({
              radius: this.getCardRadius(),
              color: this.getCardShadowColor(),
              offsetX: 0,
              offsetY: 2
            })
            .clip(true)
            .onClick(() => {
              // 使用动画过渡切换显示模式（与书库LIST/GRID切换动画保持一致）
              this.getUIContext().animateTo({
                duration: 250,
                curve: Curve.EaseInOut
              }, () => {
                this.suwayomiDisplayMode = this.suwayomiDisplayMode === 'grid' ? 'list' : 'grid';
              });
            })

          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })

          // 分类选择器（库模式）
          if (this.suwayomiBrowseMode === 'library') {
            Column() {
              // 标题行（包含展开按钮）
              Row() {
                Text('书架')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                Text(`(${this.suwayomiCategories.length + 1})`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .margin({ left: 4 })

                Blank()

                // 展开/收起按钮
                Row({ space: 4 }) {
                  Text(this.suwayomiCategoriesExpanded ? '收起' : '展开')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  SymbolGlyph(this.suwayomiCategoriesExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
                }
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.getCardBackground())
                .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                .backgroundEffect(this.getCardBackgroundEffect())
                .border({
                  width: this.getCardBorderWidth(),
                  color: this.getCardBorderColor()
                })
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
                    this.suwayomiCategoriesExpanded = !this.suwayomiCategoriesExpanded;
                  });
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })

              // 分类内容
              if (this.suwayomiCategoriesExpanded) {
                // 展开状态：网格布局
                Flex({ wrap: FlexWrap.Wrap }) {
                  Text('全部')
                    .fontSize(13)
                    .fontColor(this.suwayomiSelectedCategoryId === -1 ? Color.White :
                      ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.suwayomiSelectedCategoryId === -1 ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                      this.getCardBackground())
                    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                    .backgroundEffect(this.getCardBackgroundEffect())
                    .borderRadius(16)
                    .border({
                      width: this.getCardBorderWidth(),
                      color: this.suwayomiSelectedCategoryId === -1 ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                        this.getCardBorderColor()
                    })
                    .shadow({
                      radius: this.getCardRadius(),
                      color: this.getCardShadowColor(),
                      offsetX: 0,
                      offsetY: 2
                    })
                    .clip(true)
                    .fontFamily(this.appFontFamily)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.selectSuwayomiCategory(-1);
                    })
                  ForEach(this.suwayomiCategories, (category: SuwayomiCategory) => {
                    Text(`${category.name} (${category.mangaCount})`)
                      .fontSize(13)
                      .fontColor(this.suwayomiSelectedCategoryId === category.id ? Color.White :
                        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(this.suwayomiSelectedCategoryId === category.id ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                        this.getCardBackground())
                      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                      .backgroundEffect(this.getCardBackgroundEffect())
                      .borderRadius(16)
                      .border({
                        width: this.getCardBorderWidth(),
                        color: this.suwayomiSelectedCategoryId === category.id ?
                          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                          this.getCardBorderColor()
                      })
                      .shadow({
                        radius: this.getCardRadius(),
                        color: this.getCardShadowColor(),
                        offsetX: 0,
                        offsetY: 2
                      })
                      .clip(true)
                      .fontFamily(this.appFontFamily)
                      .margin({ right: 8, bottom: 8 })
                      .onClick(() => {
                        this.selectSuwayomiCategory(category.id);
                      })
                  })
                }
                .width('100%')
                .padding({ left: 16, right: 16, bottom: 8 })
              } else {
                // 收起状态：水平滚动
                Scroll() {
                  Row({ space: 8 }) {
                    Text('全部')
                      .fontSize(13)
                      .fontColor(this.suwayomiSelectedCategoryId === -1 ? Color.White :
                        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                      .backgroundColor(this.suwayomiSelectedCategoryId === -1 ?
                        ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                        this.getCardBackground())
                      .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                      .backgroundEffect(this.getCardBackgroundEffect())
                      .borderRadius(16)
                      .border({
                        width: this.getCardBorderWidth(),
                        color: this.suwayomiSelectedCategoryId === -1 ?
                          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                          this.getCardBorderColor()
                      })
                      .shadow({
                        radius: this.getCardRadius(),
                        color: this.getCardShadowColor(),
                        offsetX: 0,
                        offsetY: 2
                      })
                      .clip(true)
                      .fontFamily(this.appFontFamily)
                      .onClick(() => {
                        this.selectSuwayomiCategory(-1);
                      })
                    ForEach(this.suwayomiCategories, (category: SuwayomiCategory) => {
                      Text(`${category.name} (${category.mangaCount})`)
                        .fontSize(13)
                        .fontColor(this.suwayomiSelectedCategoryId === category.id ? Color.White :
                          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                        .backgroundColor(this.suwayomiSelectedCategoryId === category.id ?
                          ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                          this.getCardBackground())
                        .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                        .backgroundEffect(this.getCardBackgroundEffect())
                        .borderRadius(16)
                        .border({
                          width: this.getCardBorderWidth(),
                          color: this.suwayomiSelectedCategoryId === category.id ?
                            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                            this.getCardBorderColor()
                        })
                        .shadow({
                          radius: this.getCardRadius(),
                          color: this.getCardShadowColor(),
                          offsetX: 0,
                          offsetY: 2
                        })
                        .clip(true)
                        .fontFamily(this.appFontFamily)
                        .onClick(() => {
                          this.selectSuwayomiCategory(category.id);
                        })
                    })
                  }
                  .padding({ left: 16, right: 16 })
                }
                .scrollable(ScrollDirection.Horizontal)
                .scrollBar(BarState.Off)
                .width('100%')
                .height(44)
              }
            }
            .width('100%')
          }

          // 语言筛选器（图源模式）
          if (this.suwayomiBrowseMode === 'sources' && this.suwayomiAvailableLanguages.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                Text('全部')
                  .fontSize(13)
                  .fontColor(this.suwayomiSelectedLanguage === 'all' ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.suwayomiSelectedLanguage === 'all' ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                    this.getCardBackground())
                  .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                  .backgroundEffect(this.getCardBackgroundEffect())
                  .border({
                    width: this.getCardBorderWidth(),
                    color: this.suwayomiSelectedLanguage === 'all'
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                      : this.getCardBorderColor()
                  })
                  .borderRadius(16)
                  .shadow({
                    radius: this.getCardRadius(),
                    color: this.getCardShadowColor(),
                    offsetX: 0,
                    offsetY: 2
                  })
                  .clip(true)
                  .fontFamily(this.appFontFamily)
                  .onClick(() => {
                    // 使用动画过渡切换语言
                    this.getUIContext().animateTo({
                      duration: 200,
                      curve: Curve.EaseInOut
                    }, () => {
                      this.suwayomiSelectedLanguage = 'all';
                      this.syncFilteredSuwayomiSources('language');
                    });
                  })
                ForEach(this.suwayomiAvailableLanguages, (lang: string) => {
                  Text(lang.toUpperCase())
                    .fontSize(13)
                    .fontColor(this.suwayomiSelectedLanguage === lang ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(this.suwayomiSelectedLanguage === lang ?
                      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
                      this.getCardBackground())
                    .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                    .backgroundEffect(this.getCardBackgroundEffect())
                    .border({
                      width: this.getCardBorderWidth(),
                      color: this.suwayomiSelectedLanguage === lang
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                        : this.getCardBorderColor()
                    })
                    .borderRadius(16)
                    .shadow({
                      radius: this.getCardRadius(),
                      color: this.getCardShadowColor(),
                      offsetX: 0,
                      offsetY: 2
                    })
                    .clip(true)
                    .fontFamily(this.appFontFamily)
                    .onClick(() => {
                      // 使用动画过渡切换语言
                      this.getUIContext().animateTo({
                        duration: 200,
                        curve: Curve.EaseInOut
                      }, () => {
                        this.suwayomiSelectedLanguage = lang;
                        this.syncFilteredSuwayomiSources('language');
                      });
                    })
                })
              }
              .padding({ left: 16, right: 16 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(44)
          }

          // 排序选择器（库模式）
          if (this.suwayomiBrowseMode === 'library') {
            Row({ space: 8 }) {
              Text('排序:')
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)
              Text(MANGA_SORT_OPTIONS[this.suwayomiSelectedSortIndex].label)
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(this.getCardBackground())
                .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                .backgroundEffect(this.getCardBackgroundEffect())
                .border({
                  width: this.getCardBorderWidth(),
                  color: this.getCardBorderColor()
                })
                .borderRadius(12)
                .shadow({
                  radius: this.getCardRadius(),
                  color: this.getCardShadowColor(),
                  offsetX: 0,
                  offsetY: 2
                })
                .clip(true)
                .fontFamily(this.appFontFamily)
                .bindMenu(this.buildSuwayomiSortMenu())
              Blank()
              if (this.suwayomiTotalCount > 0) {
                Text(`共 ${this.suwayomiTotalCount} 本`)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
          }

          // 图源统计信息（图源模式）
          if (this.suwayomiBrowseMode === 'sources') {
            Text(`共 ${this.suwayomiFilteredSourceCount} 个图源`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .fontFamily(this.appFontFamily)
              .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 内容区域
          if (this.isLoadingSuwayomi && this.suwayomiMangas.length === 0 && this.suwayomiSources.length === 0) {
            Column() {
              LoadingProgress().width(48).height(48)
              Text('加载中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .margin({ top: 16 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.suwayomiErrorMessage) {
            Column({ space: 16 }) {
              Text(this.suwayomiErrorMessage)
                .fontSize(14)
                .fontColor('#FF6B6B')
                .textAlign(TextAlign.Center)
                .fontFamily(this.appFontFamily)
              Button('打开设置')
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .backgroundColor(this.getCardBackground())
                .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                .backgroundEffect(this.getCardBackgroundEffect())
                .border({
                  width: this.getCardBorderWidth(),
                  color: this.getCardBorderColor()
                })
                .borderRadius(16)
                .shadow({
                  radius: this.getCardRadius(),
                  color: this.getCardShadowColor(),
                  offsetX: 0,
                  offsetY: 2
                })
                .clip(true)
                .onClick(() => {
                  this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding(16)
          } else if (this.suwayomiBrowseMode === 'sources') {
            // 图源列表
            if (this.suwayomiFilteredSourceCount === 0) {
              Column() {
                SymbolGlyph($r('sys.symbol.square_grid_2x2'))
                  .fontSize(48)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                Text('暂无图源')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .margin({ top: 12 })
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
            } else {
              // 图源列表容器 - 使用Stack实现平滑切换
              Stack() {
                // 网格视图
                if (this.suwayomiDisplayMode === 'grid') {
                  Grid() {
                    LazyForEach(this.suwayomiSourceListDataSource, (source: SuwayomiExtensionSource) => {
                      GridItem() {
                        this.buildSuwayomiSourceGridItem(source)
                      }
                    }, (source: SuwayomiExtensionSource) => source.id)
                  }
                  .columnsTemplate('1fr 1fr 1fr 1fr')
                  .columnsGap(8)
                  .rowsGap(8)
                  .cachedCount(12)
                  .width('100%')
                  .height('100%')
                  .padding({ left: 16, right: 16, top: 16, bottom: this.bottomSpacerHeight + 16 })
                  .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
                }

                // 列表视图
                if (this.suwayomiDisplayMode === 'list') {
                  List({ space: 8 }) {
                    LazyForEach(this.suwayomiSourceListDataSource, (source: SuwayomiExtensionSource) => {
                      ListItem() {
                        this.buildSuwayomiSourceListItem(source)
                      }
                    }, (source: SuwayomiExtensionSource) => source.id)
                  }
                  .width('100%')
                  .height('100%')
                  .cachedCount(8)
                  .padding({ left: 16, right: 16, top: 16, bottom: this.bottomSpacerHeight + 16 })
                  .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
                }
              }
              .width('100%')
              .layoutWeight(1)
            }
          } else if (this.getFilteredSuwayomiMangas().length === 0) {
            Column() {
              SymbolGlyph($r('sys.symbol.text_book_closed'))
                .fontSize(48)
                .fontColor([this.getCardChevronColor()])
                .opacity(this.getCardChevronOpacity())
              Text(this.suwayomiSearchQuery.trim() ? '未找到匹配的漫画' : '暂无漫画')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .margin({ top: 12 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 漫画列表容器 - 使用Stack实现平滑切换
            Stack() {
              // 网格视图
              if (this.suwayomiDisplayMode === 'grid') {
                Scroll() {
                  Column() {
                    Grid() {
                      ForEach(this.getFilteredSuwayomiMangas(), (manga: SuwayomiComicInfo) => {
                        GridItem() {
                          this.buildSuwayomiMangaGridItem(manga)
                        }
                      })
                    }
                    .columnsTemplate('1fr 1fr 1fr')
                    .columnsGap(8)
                    .rowsGap(8)
                    .width('100%')

                    if (this.suwayomiHasMore) {
                      Button('加载更多')
                        .width('100%')
                        .height(44)
                        .margin({ top: 16 })
                        .backgroundColor(this.getCardBackground())
                        .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                        .backgroundEffect(this.getCardBackgroundEffect())
                        .border({
                          width: this.getCardBorderWidth(),
                          color: this.getCardBorderColor()
                        })
                        .borderRadius(16)
                        .shadow({
                          radius: this.getCardRadius(),
                          color: this.getCardShadowColor(),
                          offsetX: 0,
                          offsetY: 2
                        })
                        .clip(true)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.loadSuwayomiLibrary(false);
                        })
                    }
                    Blank().height(this.bottomSpacerHeight)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
              }

              // 列表视图
              if (this.suwayomiDisplayMode === 'list') {
                Scroll() {
                  Column({ space: 8 }) {
                    ForEach(this.getFilteredSuwayomiMangas(), (manga: SuwayomiComicInfo) => {
                      this.buildSuwayomiMangaListItem(manga)
                    })
                    if (this.suwayomiHasMore) {
                      Button('加载更多')
                        .width('100%')
                        .height(44)
                        .backgroundColor(this.getCardBackground())
                        .backgroundBlurStyle(this.getCardBlurStyle(), this.getCardBlurOptions())
                        .backgroundEffect(this.getCardBackgroundEffect())
                        .border({
                          width: this.getCardBorderWidth(),
                          color: this.getCardBorderColor()
                        })
                        .borderRadius(16)
                        .shadow({
                          radius: this.getCardRadius(),
                          color: this.getCardShadowColor(),
                          offsetX: 0,
                          offsetY: 2
                        })
                        .clip(true)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .onClick(() => {
                          this.loadSuwayomiLibrary(false);
                        })
                    }
                    Blank().height(this.bottomSpacerHeight)
                  }
                  .width('100%')
                  .padding(16)
                }
                .width('100%')
                .height('100%')
                .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
              }
            }
            .width('100%')
            .layoutWeight(1)
          }

        }
        .width('100%')
        .height('100%')

        // Suwayomi刷新提示浮层（静默刷新完成后短暂显示）
        if (this.suwayomiRefreshHintVisible) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([Color.White])
            Text('内容已刷新')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(20)
          .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.15)', offsetY: 2 })
          .position({ x: '50%', y: this.topSpacerHeight + 8 })
          .translate({ x: '-50%' })
          .opacity(this.suwayomiRefreshHintVisible ? 1 : 0)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
          .hitTestBehavior(HitTestMode.None)
        }

        // 底部导航（浮动在内容之上，实现模糊效果）
        this.buildSuwayomiBottomNav()
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .onRefreshing(() => {
      this.refreshSuwayomiContent();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
