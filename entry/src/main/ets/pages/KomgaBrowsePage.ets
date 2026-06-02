import { SafeUtils } from '../Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { TabContentCacheManager, KomgaCacheData } from '../Framework/Cache/TabContentCacheManager';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import KomgaCacheManager from '../Framework/Source/KomgaCacheManager';

import { getKomgaSourceExecutor, KomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';
import {
  KomgaAuthorOption,
  KomgaBrowseFilters,
  KomgaBrowseMode,
  KomgaBrowseRequest,
  KomgaCollectionOption,
  KomgaContentType,
  KomgaFeedType,
  KomgaFilterOptions,
  KomgaInstanceConfig,
  KomgaLibraryOption,
  KomgaSortOption,
  KOMGA_SORT_OPTIONS,
  createDefaultKomgaBrowseFilters,
  createEmptyKomgaFilterOptions,
  normalizeKomgaBrowseFilters
} from '../Framework/Source/KomgaModels';
import { getKomgaInstanceDisplayName } from '../Framework/Source/KomgaConfigStore';
import { KomgaImage } from '../components/KomgaImage';

const TAG = 'KomgaBrowsePage';
const PAGE_BOTTOM_SPACER: number = 32;

interface KomgaDetailParams {
  itemId: string;
  contentType: KomgaContentType;
  instanceId: string;
  title: string;
}

interface KomgaLibraryDetailParams {
  libraryId: string;
  libraryName: string;
  instanceId: string;
}

type KomgaDisplayMode = 'grid' | 'list';
type KomgaBrowseColorKey =
  'accent_blue' |
  'background_dark' |
  'comp_background_tertiary' |
  'icon_primary' |
  'panel_background' |
  'panel_border' |
  'text_muted' |
  'text_primary';

@Component
export struct KomgaBrowsePage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pageContentOpacity: number = 0;
  @State instances: KomgaInstanceConfig[] = [];
  @State currentInstanceId: string = '';
  @State browseMode: KomgaBrowseMode = 'library';
  @State contentType: KomgaContentType = 'SERIES';
  @State feedType: KomgaFeedType = 'POPULAR';
  @State displayMode: KomgaDisplayMode = 'grid';
  @State searchQuery: string = '';
  @State items: ComicInfo[] = [];
  @State filters: KomgaBrowseFilters = createDefaultKomgaBrowseFilters();
  @State filterOptions: KomgaFilterOptions = createEmptyKomgaFilterOptions();
  @State coverCachePaths: Map<string, string> = new Map();
  @State showFilters: boolean = false;
  @State isLoading: boolean = true;
  @State isLoadingMore: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = false;
  @State currentPage: number = 1;
  @State errorMessage: string = '';

  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private cacheManager: TabContentCacheManager = TabContentCacheManager.getInstance();
  private componentId: string = 'KomgaBrowsePage';
  private readonly prefsName: string = 'komga_browse_prefs';
  private initialized: boolean = false;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    void this.prepare();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private color(name: KomgaBrowseColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  private revealPageContent(): void {
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.pageContentOpacity = 1;
    });
  }

  private getHostContext(): common.UIAbilityContext {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('Komga 浏览页无法获取 UIAbilityContext');
    }
    return context;
  }

  private async prepare(): Promise<void> {
    try {
      await this.cacheManager.initialize();
      if (!this.initialized) {
        await this.loadPreferences();
        this.restoreFromCache();
        this.initialized = true;
        await this.initializePage();
        return;
      }
      if (this.items.length > 0) {
        void this.cacheCovers();
      }
      if (!this.executor.isConfigured() || this.currentInstanceId.length <= 0) {
        await this.initializePage();
      }
    } catch (error) {
      logger.error(TAG, `准备 Komga 浏览页失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
      this.isLoading = false;
    }
  }

  private async initializePage(): Promise<void> {
    this.errorMessage = '';
    await this.executor.initialize();
    this.instances = this.executor.getInstances();
    const currentInstance = this.executor.getCurrentInstance();
    this.currentInstanceId = currentInstance?.id || (this.instances.length > 0 ? this.instances[0].id : '');
    if (!this.executor.isConfigured()) {
      this.items = [];
      this.hasMore = false;
      this.currentPage = 1;
      this.errorMessage = '';
      this.isLoading = false;
      this.saveToCache();
      return;
    }
    await this.loadFilterOptions(false);
    await this.loadItems(true, this.items.length > 0);
  }


  private async loadPreferences(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: this.prefsName });
      const savedDisplayMode: string = store.getSync('displayMode', 'grid') as string;
      const savedBrowseMode: string = store.getSync('browseMode', 'library') as string;
      const savedContentType: string = store.getSync('contentType', 'SERIES') as string;
      const savedFeedType: string = store.getSync('feedType', 'POPULAR') as string;
      const filtersText: string = store.getSync('filters', '') as string;

      this.displayMode = savedDisplayMode === 'list' ? 'list' : 'grid';
      this.browseMode = savedBrowseMode === 'discover' ? 'discover' : 'library';
      this.contentType = savedContentType === 'BOOKS'
        ? 'BOOKS'
        : (savedContentType === 'READLISTS' ? 'READLISTS' : 'SERIES');
      this.feedType = savedFeedType === 'LATEST' ? 'LATEST' : 'POPULAR';
      this.searchQuery = store.getSync('searchQuery', '') as string;
      this.showFilters = store.getSync('showFilters', false) as boolean;
      this.filters = filtersText.length > 0
        ? normalizeKomgaBrowseFilters(SafeUtils.parseObj(filtersText) as ESObject)
        : createDefaultKomgaBrowseFilters();
    } catch (error) {
      logger.warn(TAG, `读取 Komga 浏览偏好失败: ${String(error)}`);
      this.displayMode = 'grid';
      this.browseMode = 'library';
      this.contentType = 'SERIES';
      this.feedType = 'POPULAR';
      this.filters = createDefaultKomgaBrowseFilters();
    }
  }

  private async savePreferences(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: this.prefsName });
      store.putSync('displayMode', this.displayMode);
      store.putSync('browseMode', this.browseMode);
      store.putSync('contentType', this.contentType);
      store.putSync('feedType', this.feedType);
      store.putSync('searchQuery', this.searchQuery);
      store.putSync('showFilters', this.showFilters);
      store.putSync('filters', JSON.stringify(this.filters));
      await store.flush();
    } catch (error) {
      logger.warn(TAG, `保存 Komga 浏览偏好失败: ${String(error)}`);
    }
  }

  private restoreFromCache(): void {
    if (!this.cacheManager.hasKomgaCache()) {
      return;
    }
    const cache = this.cacheManager.getKomgaCache();
    if (cache === null) {
      return;
    }
    this.items = cache.items;
    this.instances = cache.instances.concat();
    this.currentInstanceId = cache.currentInstanceId;
    this.browseMode = cache.browseMode;
    this.contentType = cache.contentType;
    this.feedType = cache.feedType;
    this.displayMode = cache.displayMode;
    this.searchQuery = cache.searchQuery;
    this.filters = this.copyFilters(cache.filters);
    this.filterOptions = cache.filterOptions;
    this.showFilters = cache.showFilters;
    this.hasMore = cache.hasMore;
    this.currentPage = cache.currentPage > 0 ? cache.currentPage : 1;
    this.errorMessage = cache.errorMessage;
    logger.info(TAG, `已恢复 Komga 浏览缓存: ${this.items.length} 项内容, ${this.instances.length} 个实例`);
  }

  private saveToCache(): void {
    const cacheData: KomgaCacheData = {
      items: this.items,
      instances: this.instances,
      currentInstanceId: this.currentInstanceId,
      browseMode: this.browseMode,
      contentType: this.contentType,
      feedType: this.feedType,
      displayMode: this.displayMode,
      searchQuery: this.searchQuery,
      filters: this.copyFilters(this.filters),
      filterOptions: this.filterOptions,
      showFilters: this.showFilters,
      hasMore: this.hasMore,
      currentPage: this.currentPage,
      errorMessage: this.errorMessage,
      timestamp: Date.now()
    };
    void this.cacheManager.saveKomgaCache(cacheData);
  }

  private async loadFilterOptions(forceRefresh: boolean): Promise<void> {
    try {
      this.filterOptions = await this.executor.getFilterOptions(forceRefresh);
    } catch (_error) {
      this.filterOptions = createEmptyKomgaFilterOptions();
    }
  }

  private buildEffectiveFilters(): KomgaBrowseFilters {
    if (this.browseMode === 'discover' &&
      this.filters.selectedLibraryIds.length <= 0 &&
      this.filterOptions.libraries.length > 0) {
      const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
      nextFilters.selectedLibraryIds = this.filterOptions.libraries.map((item: KomgaLibraryOption) => item.id);
      return nextFilters;
    }
    return this.copyFilters(this.filters);
  }

  private async loadItems(reset: boolean, preserveExisting: boolean = false): Promise<void> {
    if (!this.executor.isConfigured()) {
      this.isLoading = false;
      this.isLoadingMore = false;
      return;
    }
    if (reset) {
      this.currentPage = 0;
      if (!preserveExisting) {
        this.items = [];
      }
      this.isLoading = !preserveExisting;
      this.isLoadingMore = false;
    } else {
      if (!this.hasMore || this.isLoadingMore) {
        return;
      }
      this.isLoadingMore = true;
    }

    try {
      const page: number = reset ? 1 : this.currentPage + 1;
      const browseRequest: KomgaBrowseRequest = {
        instanceId: this.currentInstanceId,
        contentType: this.contentType,
        browseMode: this.browseMode,
        feedType: this.searchQuery.trim().length > 0 ? 'SEARCH' : this.feedType,
        page: page,
        query: this.searchQuery.trim(),
        filters: this.buildEffectiveFilters()
      };
      logger.info(TAG, `加载 Komga 浏览内容: reset=${reset}, preserveExisting=${preserveExisting}, page=${page}, instance=${browseRequest.instanceId || '-'}, mode=${browseRequest.browseMode}, type=${browseRequest.contentType}, feed=${browseRequest.feedType}, query="${browseRequest.query}"`);
      const result = await this.executor.browse(browseRequest);
      this.items = reset ? result.items : this.items.concat(result.items);
      logger.info(TAG, `Komga 浏览内容加载完成: page=${page}, received=${result.items.length}, totalItems=${this.items.length}, hasMore=${result.hasMore}`);
      this.currentPage = page;
      this.hasMore = result.hasMore;
      this.errorMessage = '';
      void this.cacheCovers();
      this.saveToCache();
    } catch (error) {
      logger.error(TAG, `加载 Komga 列表失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
      if (!preserveExisting) {
        this.items = [];
      }
      this.saveToCache();
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
      void this.savePreferences();
    }
  }

  private async refreshContent(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    try {
      await this.executor.initialize(true);
      this.instances = this.executor.getInstances();
      this.currentInstanceId = this.executor.getCurrentInstance()?.id || this.currentInstanceId;
      if (!this.executor.isConfigured()) {
        this.items = [];
        this.hasMore = false;
        this.currentPage = 1;
        this.errorMessage = '';
        this.saveToCache();
        return;
      }
      await this.loadFilterOptions(true);
      await this.loadItems(true, this.items.length > 0);
    } finally {
      this.isRefreshing = false;
    }
  }

  private async switchInstance(instanceId: string): Promise<void> {
    if (instanceId === this.currentInstanceId) {
      return;
    }
    if (!await this.executor.setCurrentInstance(instanceId)) {
      this.toast('切换实例失败');
      return;
    }
    await this.initializePage();
  }

  private toggleArray(values: string[], target: string): string[] {
    return values.includes(target) ? values.filter((item: string) => item !== target) : values.concat([target]);
  }

  private updateFilters(nextFilters: KomgaBrowseFilters): void {
    this.filters = nextFilters;
    void this.loadItems(true);
  }

  private copyFilters(source: KomgaBrowseFilters): KomgaBrowseFilters {
    const nextFilters: KomgaBrowseFilters = {
      selectedLibraryIds: source.selectedLibraryIds.concat(),
      collectionId: source.collectionId,
      readStatusMode: source.readStatusMode,
      selectedStatuses: source.selectedStatuses.concat(),
      selectedGenres: source.selectedGenres.concat(),
      selectedTags: source.selectedTags.concat(),
      selectedPublishers: source.selectedPublishers.concat(),
      selectedAuthorRole: source.selectedAuthorRole,
      selectedAuthorName: source.selectedAuthorName,
      sortKey: source.sortKey
    };
    return nextFilters;
  }

  private setReadStatusMode(mode: 'ANY' | 'UNREAD' | 'IN_PROGRESS' | 'READ'): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.readStatusMode = mode;
    this.updateFilters(nextFilters);
  }

  private setSortKey(sortKey: 'RELEVANCE' | 'ALPHABETICAL' | 'DATE_ADDED' | 'DATE_UPDATED' | 'RANDOM'): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.sortKey = sortKey;
    this.updateFilters(nextFilters);
  }

  private toggleLibraryFilter(libraryId: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedLibraryIds = this.toggleArray(this.filters.selectedLibraryIds, libraryId);
    this.updateFilters(nextFilters);
  }

  private setCollectionFilter(collectionId: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.collectionId = collectionId;
    this.updateFilters(nextFilters);
  }

  private toggleGenreFilter(genre: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedGenres = this.toggleArray(this.filters.selectedGenres, genre);
    this.updateFilters(nextFilters);
  }

  private toggleTagFilter(tag: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedTags = this.toggleArray(this.filters.selectedTags, tag);
    this.updateFilters(nextFilters);
  }

  private togglePublisherFilter(publisher: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedPublishers = this.toggleArray(this.filters.selectedPublishers, publisher);
    this.updateFilters(nextFilters);
  }

  private clearAuthorRoleFilter(): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorRole = '';
    nextFilters.selectedAuthorName = '';
    this.updateFilters(nextFilters);
  }

  private setAuthorRoleFilter(role: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorRole = role;
    nextFilters.selectedAuthorName = '';
    this.updateFilters(nextFilters);
  }

  private toggleAuthorNameFilter(authorName: string): void {
    const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorName = this.filters.selectedAuthorName === authorName ? '' : authorName;
    this.updateFilters(nextFilters);
  }

  private setBrowseMode(mode: KomgaBrowseMode): void {
    if (this.browseMode === mode) {
      return;
    }
    this.browseMode = mode;
    void this.loadItems(true);
  }

  private setContentType(contentType: KomgaContentType): void {
    if (this.contentType === contentType) {
      return;
    }
    this.contentType = contentType;
    if (contentType !== 'SERIES' && this.filters.collectionId.length > 0) {
      const nextFilters: KomgaBrowseFilters = this.copyFilters(this.filters);
      nextFilters.collectionId = '';
      this.filters = nextFilters;
    }
    void this.loadItems(true);
  }

  private setFeedType(feedType: KomgaFeedType): void {
    if (this.feedType === feedType) {
      return;
    }
    this.feedType = feedType;
    void this.loadItems(true);
  }

  private setDisplayMode(displayMode: KomgaDisplayMode): void {
    this.displayMode = displayMode;
    void this.savePreferences();
  }

  private toggleFilterPanel(): void {
    this.showFilters = !this.showFilters;
    void this.savePreferences();
  }

  private setCoverCachePath(cacheKey: string, coverPath: string): void {
    const nextPaths: Map<string, string> = new Map(this.coverCachePaths);
    nextPaths.set(cacheKey, coverPath);
    this.coverCachePaths = nextPaths;
  }

  private getAuthorRoleKeys(): string[] {
    return Object.keys(this.filterOptions.authorsByRole);
  }

  private getAuthorNamesForSelectedRole(): string[] {
    if (this.filters.selectedAuthorRole.length <= 0) {
      return [];
    }
    return (this.filterOptions.authorsByRole[this.filters.selectedAuthorRole] || []).map((item: KomgaAuthorOption) => item.name);
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
      const parsed: number = Number(raw);
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
    const instanceId = item.instanceId !== undefined && item.instanceId.length > 0 ? item.instanceId : this.currentInstanceId;
    return `${instanceId}_${this.getItemContentType(item)}_${item.id}`;
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
      const cacheKey: string = this.getItemCacheKey(item);
      if (this.coverCachePaths.has(cacheKey)) {
        skippedCount++;
        continue;
      }
      const cachedPath: string | null = KomgaCacheManager.getCachedCoverPath(cacheKey, item.coverUrl);
      if (cachedPath) {
        this.setCoverCachePath(cacheKey, cachedPath);
        cacheHitCount++;
        continue;
      }
      const headers = this.executor.getImageHeaders(item.instanceId);
      scheduledCount++;
      logger.debug(TAG, `Komga 浏览封面缓存未命中，开始预缓存: cacheKey=${cacheKey}, title=${item.title}`);
      KomgaCacheManager.cacheCover(cacheKey, item.coverUrl, headers).then((path: string | null) => {
        if (path) {
          this.setCoverCachePath(cacheKey, path);
          logger.debug(TAG, `Komga 浏览封面预缓存完成: cacheKey=${cacheKey}, title=${item.title}`);
        }
      }).catch((_error: Object | string | number | boolean) => {
        logger.warn(TAG, `Komga 浏览封面预缓存失败: cacheKey=${cacheKey}, title=${item.title}`);
      });
    }
    logger.info(TAG, `Komga 浏览封面缓存检查完成: items=${this.items.length}, cacheHit=${cacheHitCount}, scheduled=${scheduledCount}, skipped=${skippedCount}`);
  }

  private getCoverUrl(item: ComicInfo): string {
    return item.coverUrl || '';
  }

  private openDetail(item: ComicInfo): void {
    const contentType: KomgaContentType = this.getItemContentType(item);
    const params: KomgaDetailParams = {
      itemId: item.id,
      contentType: contentType,
      instanceId: item.instanceId !== undefined && item.instanceId.length > 0 ? item.instanceId : this.currentInstanceId,
      title: item.title
    };
    logger.info(TAG, `打开 Komga 浏览详情: itemId=${item.id}, title=${item.title}, contentType=${params.contentType}, instanceId=${params.instanceId}`);
    this.pathStack.pushPathByName('KomgaMangaDetailPage', params);
  }

  private openLibraryDetail(library: KomgaLibraryOption): void {
    const instanceId = this.currentInstanceId.length > 0 ? this.currentInstanceId : this.executor.getCurrentInstanceId();
    const params: KomgaLibraryDetailParams = {
      libraryId: library.id,
      libraryName: library.name,
      instanceId: instanceId
    };
    logger.info(TAG, `打开 Komga 库详情: libraryId=${library.id}, libraryName=${library.name}, instanceId=${instanceId || '-'}`);
    this.pathStack.pushPathByName('KomgaLibraryDetailPage', params);
  }

  private getCurrentInstanceLabel(): string {
    const instance: KomgaInstanceConfig | undefined = this.instances.find((item: KomgaInstanceConfig) => item.id === this.currentInstanceId);
    if (instance !== undefined) {
      return getKomgaInstanceDisplayName(instance);
    }
    if (this.instances.length > 0) {
      return getKomgaInstanceDisplayName(this.instances[0]);
    }
    return '未连接实例';
  }

  private getItemTypeLabel(item: ComicInfo): string {
    const contentType: KomgaContentType = this.getItemContentType(item);
    return contentType === 'READLISTS' ? '阅读列表' : (contentType === 'BOOKS' ? '书籍' : '系列');
  }

  private getCurrentContentTypeLabel(): string {
    return this.contentType === 'READLISTS' ? '阅读列表' : (this.contentType === 'BOOKS' ? '书籍' : '系列');
  }

  private getItemMetaLine(item: ComicInfo): string {
    const segments: string[] = [];
    const contentType: KomgaContentType = this.getItemContentType(item);
    if (contentType === 'READLISTS') {
      const bookCount: number = this.getNumberField(item, 'bookCount');
      segments.push(bookCount > 0 ? `${bookCount} 本内容` : '阅读列表');
    } else if (contentType === 'BOOKS') {
      const seriesTitle: string = this.getStringField(item, 'seriesTitle');
      const pageCount: number = this.getNumberField(item, 'pageCount');
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
      const publisher: string = this.getStringField(item, 'publisher');
      if (publisher.length > 0) {
        segments.push(publisher);
      }
      if (item.status !== undefined && item.status.length > 0 && item.status !== 'UNKNOWN') {
        segments.push(item.status);
      }
    }
    return segments.length > 0 ? segments.join(' · ') : '暂无元数据';
  }

  private getActiveFilterCount(): number {
    let count: number = 0;
    count += this.filters.selectedLibraryIds.length;
    count += this.filters.collectionId.length > 0 ? 1 : 0;
    count += this.filters.readStatusMode === 'ANY' ? 0 : 1;
    count += this.filters.selectedGenres.length;
    count += this.filters.selectedTags.length;
    count += this.filters.selectedPublishers.length;
    count += this.filters.selectedAuthorRole.length > 0 ? 1 : 0;
    count += this.filters.selectedAuthorName.length > 0 ? 1 : 0;
    count += this.filters.sortKey === 'RELEVANCE' ? 0 : 1;
    return count;
  }

  private getBrowseSummaryText(): string {
    return `${this.browseMode === 'library' ? '库模式' : '发现模式'} · ${this.getCurrentContentTypeLabel()} · ${this.feedType === 'LATEST' ? '最新' : '热门'}`;
  }

  @Builder
  private buildToolbarButton(icon: Resource, action: () => void) {
    Button() {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([this.color('text_primary')])
    }
    .width(40)
    .height(40)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(10)
    .onClick(() => action())
  }

  @Builder
  private buildChip(label: string, selected: boolean, action: () => void) {
    Button(label)
      .fontSize(12)
      .fontColor(selected ? Color.White : this.color('text_primary'))
      .fontFamily(this.appFontFamily)
      .constraintSize({ minHeight: 0 })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(selected ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
      .stateEffect(false)
      .onClick(() => action())
  }

  @Builder
  private buildPanelTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.appFontFamily)
      .fontColor(this.color('text_primary'))
  }

  @Builder
  private buildLibraryEntryCard(library: KomgaLibraryOption) {
    Row({ space: 10 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.books_vertical_fill'))
          .fontSize(18)
          .fontColor([this.color('accent_blue')])
      }
      .width(34)
      .height(34)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(10)

      Column({ space: 3 }) {
        Text(library.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('进入库详情页查看并选择具体内容')
          .fontSize(11)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.color('text_muted')])
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(14)
    .border({ width: 1, color: this.color('panel_border') })
    .onClick(() => {
      this.openLibraryDetail(library);
    })
  }

  @Builder
  private buildStatCard(title: string, value: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(11)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('31.5%')
    .padding(14)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildOverviewPanel() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Column({ space: 6 }) {
          Text('Komga 浏览')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text(`${this.getCurrentInstanceLabel()} · ${this.getBrowseSummaryText()}`)
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.buildToolbarButton($r('sys.symbol.arrow_clockwise'), () => {
          void this.refreshContent();
        })
        this.buildToolbarButton($r('sys.symbol.gearshape'), () => {
          this.pathStack.pushPathByName('KomgaSettingsPage', null);
        })
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildStatCard('实例', `${this.instances.length}`)
        this.buildStatCard('结果', `${this.items.length}`)
        this.buildStatCard('筛选', `${this.getActiveFilterCount()}`)
      }
      .width('100%')

      Text(this.getActiveFilterCount() > 0
        ? `已启用 ${this.getActiveFilterCount()} 个筛选条件，可下拉刷新或切换模式查看更多内容。`
        : '支持多实例切换、发现流浏览、阅读列表和书籍级内容查看。')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(22)
    .border({ width: 1, color: this.color('panel_border') })
  }

  @Builder
  private buildGridItem(item: ComicInfo) {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        KomgaImage({
          src: this.getCoverUrl(item),
          imageWidth: '100%',
          imageHeight: 190,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 14,
          requestHeaders: this.executor.getImageHeaders(item.instanceId),
          cacheKey: this.getItemCacheKey(item)
        })
        Text(this.getItemTypeLabel(item))
          .fontSize(11)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(0, 0, 0, 0.55)')
          .borderRadius(999)
          .margin({ top: 10, right: 10 })
      }

      Text(item.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.getItemMetaLine(item))
        .fontSize(12)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
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
        imageWidth: 92,
        imageHeight: 132,
        objectFit: ImageFit.Cover,
        imgBorderRadius: 14,
        requestHeaders: this.executor.getImageHeaders(item.instanceId),
        cacheKey: this.getItemCacheKey(item)
      })
      Column({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getItemMetaLine(item))
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.description || '暂无简介')
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
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
  private buildConfiguredContent() {
    Column({ space: 16 }) {
      if (this.instances.length > 0) {
        Column({ space: 12 }) {
          this.buildPanelTitle('实例')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.instances, (instance: KomgaInstanceConfig) => {
              this.buildChip(getKomgaInstanceDisplayName(instance), instance.id === this.currentInstanceId, () => {
                void this.switchInstance(instance.id);
              })
            }, (instance: KomgaInstanceConfig) => instance.id)
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
      }

      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Search({ value: this.searchQuery, placeholder: this.browseMode === 'library' ? '搜索 Komga 书库...' : '搜索 Komga 目录...' })
            .layoutWeight(1)
            .height(40)
            .searchButton('搜索')
            .onChange((value: string) => {
              this.searchQuery = value;
            })
            .onSubmit((_value: string) => {
              void this.loadItems(true);
            })

          this.buildToolbarButton(this.displayMode === 'grid' ? $r('sys.symbol.list_bullet') : $r('sys.symbol.square_grid_2x2'), () => {
            this.setDisplayMode(this.displayMode === 'grid' ? 'list' : 'grid');
          })
        }

        Flex({ wrap: FlexWrap.Wrap }) {
          this.buildChip('库', this.browseMode === 'library', () => { this.setBrowseMode('library'); })
          this.buildChip('发现', this.browseMode === 'discover', () => { this.setBrowseMode('discover'); })
          this.buildChip('系列', this.contentType === 'SERIES', () => { this.setContentType('SERIES'); })
          this.buildChip('阅读列表', this.contentType === 'READLISTS', () => { this.setContentType('READLISTS'); })
          this.buildChip('书籍', this.contentType === 'BOOKS', () => { this.setContentType('BOOKS'); })
          this.buildChip('热门', this.feedType === 'POPULAR', () => { this.setFeedType('POPULAR'); })
          this.buildChip('最新', this.feedType === 'LATEST', () => { this.setFeedType('LATEST'); })
          this.buildChip('筛选', this.showFilters, () => { this.toggleFilterPanel(); })
        }

        if (this.showFilters) {
          Column({ space: 10 }) {
            if (this.filterOptions.libraries.length > 0) {
              this.buildPanelTitle('书库范围')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.filterOptions.libraries, (library: KomgaLibraryOption) => {
                  this.buildChip(library.name, this.filters.selectedLibraryIds.includes(library.id), () => {
                    this.toggleLibraryFilter(library.id);
                  })
                }, (library: KomgaLibraryOption) => library.id)
              }
            }

            this.buildPanelTitle('阅读进度')
            Flex({ wrap: FlexWrap.Wrap }) {
              this.buildChip('全部进度', this.filters.readStatusMode === 'ANY', () => this.setReadStatusMode('ANY'))
              this.buildChip('未读', this.filters.readStatusMode === 'UNREAD', () => this.setReadStatusMode('UNREAD'))
              this.buildChip('阅读中', this.filters.readStatusMode === 'IN_PROGRESS', () => this.setReadStatusMode('IN_PROGRESS'))
              this.buildChip('已读', this.filters.readStatusMode === 'READ', () => this.setReadStatusMode('READ'))
            }

            this.buildPanelTitle('排序')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(KOMGA_SORT_OPTIONS, (option: KomgaSortOption) => {
                this.buildChip(option.label, this.filters.sortKey === option.key, () => this.setSortKey(option.key))
              }, (option: KomgaSortOption) => option.key)
            }

            if (this.contentType === 'SERIES' && this.filterOptions.collections.length > 0) {
              this.buildPanelTitle('收藏集')
              Flex({ wrap: FlexWrap.Wrap }) {
                this.buildChip('全部收藏集', this.filters.collectionId.length <= 0, () => this.setCollectionFilter(''))
                ForEach(this.filterOptions.collections, (collection: KomgaCollectionOption) => {
                  this.buildChip(collection.name, this.filters.collectionId === collection.id, () => {
                    this.setCollectionFilter(collection.id);
                  })
                }, (collection: KomgaCollectionOption) => collection.id)
              }
            }

            if (this.filterOptions.genres.length > 0) {
              this.buildPanelTitle('流派')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.filterOptions.genres, (genre: string) => {
                  this.buildChip(genre, this.filters.selectedGenres.includes(genre), () => {
                    this.toggleGenreFilter(genre);
                  })
                }, (genre: string) => genre)
              }
            }

            if (this.filterOptions.tags.length > 0) {
              this.buildPanelTitle('标签')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.filterOptions.tags, (tag: string) => {
                  this.buildChip(tag, this.filters.selectedTags.includes(tag), () => {
                    this.toggleTagFilter(tag);
                  })
                }, (tag: string) => tag)
              }
            }

            if (this.filterOptions.publishers.length > 0) {
              this.buildPanelTitle('出版社')
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.filterOptions.publishers, (publisher: string) => {
                  this.buildChip(publisher, this.filters.selectedPublishers.includes(publisher), () => {
                    this.togglePublisherFilter(publisher);
                  })
                }, (publisher: string) => publisher)
              }
            }

            if (this.getAuthorRoleKeys().length > 0) {
              this.buildPanelTitle('作者')
              Flex({ wrap: FlexWrap.Wrap }) {
                this.buildChip('全部角色', this.filters.selectedAuthorRole.length <= 0, () => {
                  this.clearAuthorRoleFilter();
                })
                ForEach(this.getAuthorRoleKeys(), (role: string) => {
                  this.buildChip(role, this.filters.selectedAuthorRole === role, () => {
                    this.setAuthorRoleFilter(role);
                  })
                }, (role: string) => role)
              }
              if (this.filters.selectedAuthorRole.length > 0) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.getAuthorNamesForSelectedRole(), (authorName: string) => {
                    this.buildChip(authorName, this.filters.selectedAuthorName === authorName, () => {
                      this.toggleAuthorNameFilter(authorName);
                    })
                  }, (authorName: string) => authorName)
                }
              }
            }
          }
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.color('panel_background'))
      .borderRadius(20)
      .border({ width: 1, color: this.color('panel_border') })

      if (this.browseMode === 'library' && this.filterOptions.libraries.length > 0) {
        Column({ space: 10 }) {
          this.buildPanelTitle('库入口')
          Text('先打开对应库详情，再进入具体漫画/阅读列表/书籍内容。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .width('100%')
          ForEach(this.filterOptions.libraries, (library: KomgaLibraryOption) => {
            this.buildLibraryEntryCard(library)
          }, (library: KomgaLibraryOption) => library.id)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
      }

      Row() {
        Text(this.items.length > 0 ? `当前显示 ${this.items.length} 项` : '等待加载内容')
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
        Blank()
        Text(this.getBrowseSummaryText())
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
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
            .fontColor(this.color('text_primary'))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              void this.refreshContent();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(16)
        .border({ width: 1, color: this.color('panel_border') })
      }

      if (this.errorMessage.length > 0 && this.items.length <= 0) {
        Column({ space: 12 }) {
          Text(this.errorMessage)
            .width('100%')
            .fontSize(13)
            .fontColor('#FF6B6B')
            .fontFamily(this.appFontFamily)
          Row({ space: 12 }) {
            Button('重新加载')
              .layoutWeight(1)
              .backgroundColor(this.color('accent_blue'))
              .fontColor(Color.White)
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                void this.refreshContent();
              })
            Button('打开设置')
              .layoutWeight(1)
              .backgroundColor(this.color('comp_background_tertiary'))
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.pathStack.pushPathByName('KomgaSettingsPage', null);
              })
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.isLoading && this.items.length <= 0) {
        Column({ space: 12 }) {
          LoadingProgress()
          Text('正在同步 Komga 内容...')
            .fontSize(13)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .padding(24)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
      } else if (this.items.length <= 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.rectangle_stack'))
            .fontSize(28)
            .fontColor([this.color('text_muted')])
          Text(this.searchQuery.trim().length > 0 ? '没有找到匹配内容' : '当前没有可浏览内容')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text('你可以切换实例、调整筛选条件，或前往 Komga 设置检查连接。')
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
          Button('打开 Komga 设置')
            .backgroundColor(this.color('accent_blue'))
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              this.pathStack.pushPathByName('KomgaSettingsPage', null);
            })
        }
        .width('100%')
        .padding(24)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
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

      if (this.hasMore && this.items.length > 0) {
        Button(this.isLoadingMore ? '加载中...' : '加载更多')
          .width('100%')
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .enabled(!this.isLoadingMore)
          .onClick(() => {
            void this.loadItems(false);
          })
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
          Scroll() {
            Column({ space: 16 }) {
              this.buildOverviewPanel()

              if (!this.executor.isConfigured()) {
                Column({ space: 12 }) {
                  Text('尚未配置 Komga')
                    .fontSize(18)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.color('text_primary'))
                    .fontFamily(this.appFontFamily)
                  Text('请先在设置中添加 Komga 实例，随后即可在这里切换书库、发现流和阅读列表。')
                    .fontSize(12)
                    .lineHeight(18)
                    .fontColor(this.color('text_muted'))
                    .fontFamily(this.appFontFamily)
                    .textAlign(TextAlign.Center)
                  Button('打开设置')
                    .width('100%')
                    .backgroundColor(this.color('accent_blue'))
                    .fontColor(Color.White)
                    .fontFamily(this.appFontFamily)
                    .onClick(() => this.pathStack.pushPathByName('KomgaSettingsPage', null))
                }
                .width('100%')
                .padding(18)
                .backgroundColor(this.color('panel_background'))
                .borderRadius(20)
                .border({ width: 1, color: this.color('panel_border') })
              } else {
                this.buildConfiguredContent()
              }

              Blank().height(PAGE_BOTTOM_SPACER)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 0 })
            .opacity(this.pageContentOpacity)
            .backgroundColor(this.color('background_dark'))
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .onRefreshing(() => {
          void this.refreshContent();
        })
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .title('Komga 浏览')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onShown(() => {
      this.revealPageContent();
    })
  }
}
