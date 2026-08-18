import { SafeUtils } from '../Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
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
import { KomgaImage } from './KomgaImage';
import { eventBus, GameEvent, IEventPayload, RemoteLibraryConfigChangedPayload } from '../Framework/EventBus';

const TAG = 'MainMenuKomgaTabContent';

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
type KomgaColorKey =
  'accent_blue' | 'background_dark' | 'comp_background_tertiary' |
  'panel_background' | 'panel_border' | 'text_muted' | 'text_primary';

interface KomgaChipBuilderParams {
  label: string;
  selected: boolean;
  action: () => void;
}

@Component
export struct MainMenuKomgaTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 80;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('appFontFamily') private appFontFamily: string = 'HarmonyOS Sans';
  @State private instances: KomgaInstanceConfig[] = [];
  @State private currentInstanceId: string = '';
  @State private browseMode: KomgaBrowseMode = 'library';
  @State private contentType: KomgaContentType = 'SERIES';
  @State private feedType: KomgaFeedType = 'POPULAR';
  @State private displayMode: KomgaDisplayMode = 'grid';
  @State private searchQuery: string = '';
  @State private items: ComicInfo[] = [];
  @State private filters: KomgaBrowseFilters = createDefaultKomgaBrowseFilters();
  @State private filterOptions: KomgaFilterOptions = createEmptyKomgaFilterOptions();
  @State private coverCachePaths: Map<string, string> = new Map();
  @State private showFilters: boolean = false;
  @State private isLoading: boolean = true;
  @State private isLoadingMore: boolean = false;
  @State private isRefreshing: boolean = false;
  @State private hasMore: boolean = false;
  @State private currentPage: number = 1;
  @State private errorMessage: string = '';
  @State private refreshHintVisible: boolean = false;

  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private cacheManager: TabContentCacheManager = TabContentCacheManager.getInstance();
  private readonly prefsName: string = 'komga_browse_prefs';
  private readonly componentId: string = 'MainMenuKomgaTabContent';
  private refreshHintTimer: number = -1;
  private initialized: boolean = false;
  private remoteConfigChangedListener: (payload: IEventPayload) => void = (payload: IEventPayload) => {
    this.handleRemoteConfigChanged(payload);
  };

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_theme: ThemeType) => {});
    eventBus.subscribe(GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED, this.remoteConfigChangedListener);
    void this.prepare();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    eventBus.unsubscribe(GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED, this.remoteConfigChangedListener);
    if (this.refreshHintTimer >= 0) {
      clearTimeout(this.refreshHintTimer);
      this.refreshHintTimer = -1;
    }
  }

  private onRefreshSignalChanged(): void {
    if (!this.initialized || this.refreshSignal <= 0) {
      return;
    }
    void this.initializePage();
  }

  private handleRemoteConfigChanged(payload: IEventPayload): void {
    const changedPayload = payload as RemoteLibraryConfigChangedPayload;
    if (changedPayload.provider !== 'komga') {
      return;
    }
    logger.info(TAG, `收到 Komga 配置变更事件，准备静默刷新: reason=${changedPayload.reason}`);
    void this.refreshAfterConfigChanged();
  }

  private async refreshAfterConfigChanged(): Promise<void> {
    this.errorMessage = '';
    this.items = [];
    this.instances = [];
    this.currentInstanceId = '';
    this.hasMore = false;
    this.currentPage = 1;
    this.coverCachePaths = new Map<string, string>();
    this.isLoading = true;
    this.isLoadingMore = false;
    this.isRefreshing = false;
    await this.cacheManager.clearKomgaCache();
    await this.initializePage();
  }

  private color(name: KomgaColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  private getHostContext(): common.UIAbilityContext {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('Komga 主标签页无法获取 UIAbilityContext');
    }
    return context;
  }

  private buildFilterSummary(filters: KomgaBrowseFilters): string {
    return `libraries=${filters.selectedLibraryIds.length}, collection=${filters.collectionId || '-'}, readStatus=${filters.readStatusMode}, genres=${filters.selectedGenres.length}, tags=${filters.selectedTags.length}, publishers=${filters.selectedPublishers.length}, authorRole=${filters.selectedAuthorRole || '-'}, authorName=${filters.selectedAuthorName || '-'}, sort=${filters.sortKey}`;
  }

  private async prepare(): Promise<void> {
    try {
      logger.info(TAG, `准备 Komga 主标签: initialized=${this.initialized}, cachedItems=${this.items.length}, refreshSignal=${this.refreshSignal}`);
      await this.cacheManager.initialize();
      if (!this.initialized) {
        await this.loadPreferences();
        this.restoreFromCache();
        this.initialized = true;
        await this.initializePage();
        return;
      }
      if (this.items.length > 0) {
        logger.debug(TAG, `Komga 主标签准备阶段触发封面缓存检查: itemCount=${this.items.length}`);
        void this.cacheCovers();
      }
      if (!this.executor.isConfigured() || this.currentInstanceId.length <= 0) {
        await this.initializePage();
      }
    } catch (error) {
      logger.error(TAG, `准备 Komga 主标签失败: ${String(error)}`);
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
    logger.info(TAG, `初始化 Komga 主标签: configured=${this.executor.isConfigured()}, instances=${this.instances.length}, currentInstance=${this.currentInstanceId || '-'}`);

    if (!this.executor.isConfigured()) {
      this.items = [];
      this.hasMore = false;
      this.currentPage = 1;
      this.errorMessage = '尚未配置 Komga 实例';
      this.isLoading = false;
      this.saveToCache();
      return;
    }

    await this.loadFilterOptions(false);
    this.sanitizeFiltersForCurrentOptions();
    await this.loadItems(true, this.items.length > 0);
  }

  private async refreshContent(): Promise<void> {
    try {
      logger.info(TAG, `刷新 Komga 主标签: currentInstance=${this.currentInstanceId || '-'}, itemCount=${this.items.length}`);
      await this.executor.initialize(true);
      this.instances = this.executor.getInstances();
      const currentInstance = this.executor.getCurrentInstance();
      this.currentInstanceId = currentInstance?.id || this.currentInstanceId;
      if (!this.executor.isConfigured()) {
        this.items = [];
        this.hasMore = false;
        this.currentPage = 1;
        this.errorMessage = '尚未配置 Komga 实例';
        this.saveToCache();
        return;
      }
      await this.loadFilterOptions(true);
      this.sanitizeFiltersForCurrentOptions();
      await this.loadItems(true, this.items.length > 0);
    } catch (error) {
      logger.error(TAG, `刷新 Komga 主标签失败: ${String(error)}`);
      this.errorMessage = `刷新失败：${String(error)}`;
    } finally {
      this.isRefreshing = false;
    }
  }

  private beginPullRefresh(): void {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    void this.refreshContent();
  }

  private async loadPreferences(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: this.prefsName });
      const savedDisplayMode = store.getSync('displayMode', 'grid') as string;
      const savedBrowseMode = store.getSync('browseMode', 'library') as string;
      const savedContentType = store.getSync('contentType', 'SERIES') as string;
      const savedFeedType = store.getSync('feedType', 'POPULAR') as string;
      this.displayMode = savedDisplayMode === 'list' ? 'list' : 'grid';
      this.browseMode = savedBrowseMode === 'discover' ? 'discover' : 'library';
      this.contentType = savedContentType === 'BOOKS' ? 'BOOKS' : (savedContentType === 'READLISTS' ? 'READLISTS' : 'SERIES');
      this.feedType = savedFeedType === 'LATEST' ? 'LATEST' : (savedFeedType === 'SEARCH' ? 'SEARCH' : 'POPULAR');
      this.searchQuery = store.getSync('searchQuery', '') as string;
      this.showFilters = store.getSync('showFilters', false) as boolean;
      const filtersText = store.getSync('filters', '') as string;
      this.filters = filtersText.length > 0
        ? normalizeKomgaBrowseFilters(SafeUtils.parseObj(filtersText) as ESObject)
        : createDefaultKomgaBrowseFilters();
      logger.info(TAG, `已读取 Komga 主标签偏好: browseMode=${this.browseMode}, contentType=${this.contentType}, feedType=${this.feedType}, displayMode=${this.displayMode}, queryLength=${this.searchQuery.length}, filters=${this.buildFilterSummary(this.filters)}`);
    } catch (error) {
      logger.warn(TAG, `读取 Komga 主标签偏好失败: ${String(error)}`);
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
      logger.debug(TAG, `已保存 Komga 主标签偏好: browseMode=${this.browseMode}, contentType=${this.contentType}, feedType=${this.feedType}, displayMode=${this.displayMode}`);
    } catch (error) {
      logger.warn(TAG, `保存 Komga 主标签偏好失败: ${String(error)}`);
    }
  }

  private restoreFromCache(): void {
    if (!this.cacheManager.hasKomgaCache()) {
      return;
    }
    const cache = this.cacheManager.getKomgaCache();
    if (!cache) {
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
    logger.info(TAG, `已恢复 Komga 标签缓存: ${this.items.length} 项内容, ${this.instances.length} 个实例`);
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
      logger.info(TAG, `Komga 主标签筛选项已更新: forceRefresh=${forceRefresh}, libraries=${this.filterOptions.libraries.length}, collections=${this.filterOptions.collections.length}, genres=${this.filterOptions.genres.length}, tags=${this.filterOptions.tags.length}, publishers=${this.filterOptions.publishers.length}`);
    } catch (_error) {
      this.filterOptions = createEmptyKomgaFilterOptions();
      logger.warn(TAG, `Komga 主标签筛选项加载失败，已回退为空集合: forceRefresh=${forceRefresh}`);
    }
  }

  private sanitizeFiltersForCurrentOptions(): void {
    const availableLibraryIds: string[] = this.filterOptions.libraries.map((item: KomgaLibraryOption): string => item.id);
    const availableCollectionIds: string[] = this.filterOptions.collections.map((item: KomgaCollectionOption): string => item.id);
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedLibraryIds = nextFilters.selectedLibraryIds.filter((libraryId: string): boolean => {
      return availableLibraryIds.includes(libraryId);
    });
    if (nextFilters.collectionId.length > 0 && !availableCollectionIds.includes(nextFilters.collectionId)) {
      nextFilters.collectionId = '';
    }
    this.filters = nextFilters;
  }

  private buildEffectiveFilters(): KomgaBrowseFilters {
    if (this.browseMode === 'discover' &&
      this.filters.selectedLibraryIds.length <= 0 &&
      this.filterOptions.libraries.length > 0) {
      const nextFilters = this.copyFilters(this.filters);
      nextFilters.selectedLibraryIds = this.filterOptions.libraries.map((item: KomgaLibraryOption) => item.id);
      return nextFilters;
    }
    return this.copyFilters(this.filters);
  }

  private async loadItems(reset: boolean, preserveExisting: boolean): Promise<void> {
    if (!this.executor.isConfigured()) {
      this.isLoading = false;
      this.isLoadingMore = false;
      this.isRefreshing = false;
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
      const nextPage = reset ? 1 : this.currentPage + 1;
      const query = this.searchQuery.trim();
      const browseRequest: KomgaBrowseRequest = {
        instanceId: this.currentInstanceId,
        contentType: this.contentType,
        browseMode: this.browseMode,
        feedType: query.length > 0 ? 'SEARCH' : this.feedType,
        page: nextPage,
        query: query,
        filters: this.buildEffectiveFilters()
      };
      logger.info(TAG, `加载 Komga 内容: reset=${reset}, preserveExisting=${preserveExisting}, page=${nextPage}, instance=${browseRequest.instanceId || '-'}, mode=${browseRequest.browseMode}, type=${browseRequest.contentType}, feed=${browseRequest.feedType}, query="${query}", filters=${this.buildFilterSummary(browseRequest.filters)}`);
      const result = await this.executor.browse(browseRequest);
      this.items = reset ? result.items : this.items.concat(result.items);
      logger.info(TAG, `Komga 内容加载完成: page=${nextPage}, received=${result.items.length}, totalItems=${this.items.length}, hasMore=${result.hasMore}`);
      if (reset && preserveExisting && result.items.length > 0) {
        this.showRefreshHint();
      }
      this.currentPage = nextPage;
      this.hasMore = result.hasMore;
      this.errorMessage = '';
      void this.cacheCovers();
      this.saveToCache();
    } catch (error) {
      logger.error(TAG, `加载 Komga 内容失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
      if (!preserveExisting) {
        this.items = [];
      }
      this.saveToCache();
    } finally {
      this.isLoading = false;
      this.isLoadingMore = false;
      this.isRefreshing = false;
      void this.savePreferences();
    }
  }

  private async switchInstance(instanceId: string): Promise<void> {
    if (instanceId === this.currentInstanceId) {
      return;
    }
    logger.info(TAG, `切换 Komga 实例: from=${this.currentInstanceId || '-'} -> to=${instanceId}`);
    if (!await this.executor.setCurrentInstance(instanceId)) {
      this.toast('切换实例失败');
      return;
    }
    this.currentInstanceId = instanceId;
    this.coverCachePaths = new Map();
    await this.loadFilterOptions(true);
    await this.loadItems(true, false);
  }

  private openInstanceDialog(): void {
    if (this.instances.length <= 0) {
      this.toast('暂无可切换的 Komga 实例');
      return;
    }
    const visibleCount: number = this.instances.length > 6 ? 6 : this.instances.length;
    const menuButtons: promptAction.Button[] = [];
    for (let index: number = 0; index < visibleCount; index++) {
      const instance = this.instances[index];
      const selectedPrefix: string = instance.id === this.currentInstanceId ? '当前 · ' : '';
      menuButtons.push({
        text: `${selectedPrefix}${getKomgaInstanceDisplayName(instance)}`,
        color: $r('sys.color.ohos_id_color_text_primary')
      });
    }

    const buttons = menuButtons as [
      promptAction.Button,
      promptAction.Button?,
      promptAction.Button?,
      promptAction.Button?,
      promptAction.Button?,
      promptAction.Button?
    ];

    this.getUIContext().getPromptAction().showActionMenu({
      title: `切换 Komga 实例\n${this.getCurrentInstanceLabel()}`,
      buttons: buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index >= 0 && result.index < visibleCount) {
        const instance = this.instances[result.index];
        if (instance.id !== this.currentInstanceId) {
          void this.switchInstance(instance.id);
        }
      }
    }).catch(() => {
      logger.info(TAG, '用户取消 Komga 实例切换');
    });

    if (this.instances.length > visibleCount) {
      this.toast('系统菜单最多显示 6 个实例，请到设置中调整当前实例');
    }
  }

  private showRefreshHint(): void {
    if (this.refreshHintTimer >= 0) {
      clearTimeout(this.refreshHintTimer);
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.refreshHintVisible = true;
    });
    this.refreshHintTimer = setTimeout(() => {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseIn }, () => {
        this.refreshHintVisible = false;
      });
      this.refreshHintTimer = -1;
    }, 1800) as number;
  }

  private toggleArray(values: string[], target: string): string[] {
    return values.includes(target) ? values.filter((item: string) => item !== target) : values.concat([target]);
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

  private updateFilters(nextFilters: KomgaBrowseFilters): void {
    this.filters = nextFilters;
    logger.info(TAG, `Komga 主标签筛选已更新: ${this.buildFilterSummary(nextFilters)}`);
    void this.loadItems(true, false);
  }

  private setReadStatusMode(mode: 'ANY' | 'UNREAD' | 'IN_PROGRESS' | 'READ'): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.readStatusMode = mode;
    this.updateFilters(nextFilters);
  }

  private setSortKey(sortKey: 'RELEVANCE' | 'ALPHABETICAL' | 'DATE_ADDED' | 'DATE_UPDATED' | 'RANDOM'): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.sortKey = sortKey;
    this.updateFilters(nextFilters);
  }

  private toggleLibraryFilter(libraryId: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedLibraryIds = this.toggleArray(nextFilters.selectedLibraryIds, libraryId);
    this.updateFilters(nextFilters);
  }

  private setCollectionFilter(collectionId: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.collectionId = collectionId;
    this.updateFilters(nextFilters);
  }

  private toggleGenreFilter(genre: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedGenres = this.toggleArray(nextFilters.selectedGenres, genre);
    this.updateFilters(nextFilters);
  }

  private toggleTagFilter(tag: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedTags = this.toggleArray(nextFilters.selectedTags, tag);
    this.updateFilters(nextFilters);
  }

  private togglePublisherFilter(publisher: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedPublishers = this.toggleArray(nextFilters.selectedPublishers, publisher);
    this.updateFilters(nextFilters);
  }

  private clearAuthorRoleFilter(): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorRole = '';
    nextFilters.selectedAuthorName = '';
    this.updateFilters(nextFilters);
  }

  private setAuthorRoleFilter(role: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorRole = role;
    nextFilters.selectedAuthorName = '';
    this.updateFilters(nextFilters);
  }

  private toggleAuthorNameFilter(authorName: string): void {
    const nextFilters = this.copyFilters(this.filters);
    nextFilters.selectedAuthorName = nextFilters.selectedAuthorName === authorName ? '' : authorName;
    this.updateFilters(nextFilters);
  }

  private setBrowseMode(mode: KomgaBrowseMode): void {
    if (this.browseMode === mode) {
      return;
    }
    logger.info(TAG, `Komga 主标签浏览模式切换: ${this.browseMode} -> ${mode}`);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.browseMode = mode;
    });
    void this.loadItems(true, false);
  }

  private setContentType(contentType: KomgaContentType): void {
    if (this.contentType === contentType) {
      return;
    }
    logger.info(TAG, `Komga 主标签内容类型切换: ${this.contentType} -> ${contentType}`);
    this.contentType = contentType;
    if (contentType !== 'SERIES' && this.filters.collectionId.length > 0) {
      const nextFilters = this.copyFilters(this.filters);
      nextFilters.collectionId = '';
      this.filters = nextFilters;
    }
    void this.loadItems(true, false);
  }

  private setFeedType(feedType: KomgaFeedType): void {
    if (this.feedType === feedType) {
      return;
    }
    logger.info(TAG, `Komga 主标签信息流切换: ${this.feedType} -> ${feedType}`);
    this.feedType = feedType;
    void this.loadItems(true, false);
  }

  private setDisplayMode(displayMode: KomgaDisplayMode): void {
    if (this.displayMode === displayMode) {
      return;
    }
    logger.info(TAG, `Komga 主标签显示模式切换: ${this.displayMode} -> ${displayMode}`);
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.displayMode = displayMode;
    });
    void this.savePreferences();
  }

  private toggleFilterPanel(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.showFilters = !this.showFilters;
    });
    void this.savePreferences();
  }

  private getAuthorRoleKeys(): string[] {
    return Object.keys(this.filterOptions.authorsByRole);
  }

  private getAuthorNamesForSelectedRole(): string[] {
    if (this.filters.selectedAuthorRole.length <= 0) {
      return [];
    }
    const options: KomgaAuthorOption[] = this.filterOptions.authorsByRole[this.filters.selectedAuthorRole] || [];
    return options.map((item: KomgaAuthorOption) => item.name);
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
    const rawType = this.getStringField(item, 'contentType');
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

  private getItemTypeLabel(item: ComicInfo): string {
    const contentType = this.getItemContentType(item);
    return contentType === 'READLISTS' ? '阅读列表' : (contentType === 'BOOKS' ? '书籍' : '系列');
  }

  private getCurrentContentTypeLabel(): string {
    return this.contentType === 'READLISTS' ? '阅读列表' : (this.contentType === 'BOOKS' ? '书籍' : '系列');
  }

  private getCurrentInstanceLabel(): string {
    const instance: KomgaInstanceConfig | undefined = this.instances.find((item: KomgaInstanceConfig) => item.id === this.currentInstanceId);
    if (instance !== undefined) {
      return getKomgaInstanceDisplayName(instance);
    }
    if (this.instances.length > 0) {
      return getKomgaInstanceDisplayName(this.instances[0]);
    }
    return '未配置实例';
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

  private getItemMetaLine(item: ComicInfo): string {
    const segments: string[] = [];
    const contentType = this.getItemContentType(item);
    if (contentType === 'READLISTS') {
      const bookCount = this.getNumberField(item, 'bookCount');
      segments.push(bookCount > 0 ? `${bookCount} 本书` : '空列表');
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
      if (item.author && item.author.length > 0) {
        segments.push(item.author);
      }
      const publisher = this.getStringField(item, 'publisher');
      if (publisher.length > 0) {
        segments.push(publisher);
      }
      if (item.status && item.status.length > 0 && item.status !== 'UNKNOWN') {
        segments.push(item.status);
      }
    }
    return segments.length > 0 ? segments.join(' · ') : '暂无元数据';
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
      logger.debug(TAG, `Komga 封面缓存未命中，开始预缓存: cacheKey=${cacheKey}, title=${item.title}`);
      KomgaCacheManager.cacheCover(cacheKey, item.coverUrl, headers).then((path: string | null) => {
        if (path) {
          this.setCoverCachePath(cacheKey, path);
          logger.debug(TAG, `Komga 封面预缓存完成: cacheKey=${cacheKey}, title=${item.title}`);
        }
      }).catch((_error: Object | string | number | boolean) => {
        logger.warn(TAG, `Komga 封面预缓存失败: cacheKey=${cacheKey}, title=${item.title}`);
      });
    }
    logger.info(TAG, `Komga 封面缓存检查完成: items=${this.items.length}, cacheHit=${cacheHitCount}, scheduled=${scheduledCount}, skipped=${skippedCount}`);
  }

  private getCoverUrl(item: ComicInfo): string {
    return item.coverUrl || '';
  }

  private openSettings(): void {
    this.pathStack.pushPathByName('KomgaSettingsPage', null);
  }

  private openDetail(item: ComicInfo): void {
    const params: KomgaDetailParams = {
      itemId: item.id,
      contentType: this.getItemContentType(item),
      instanceId: item.instanceId !== undefined && item.instanceId.length > 0 ? item.instanceId : this.currentInstanceId,
      title: item.title
    };
    logger.info(TAG, `打开 Komga 详情: itemId=${item.id}, title=${item.title}, contentType=${params.contentType}, instanceId=${params.instanceId}`);
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


  private getBrowseModeLabel(): string {
    return this.browseMode === 'library' ? '库模式' : '发现模式';
  }

  private getFeedTypeLabel(): string {
    if (this.feedType === 'LATEST') {
      return '最新';
    }
    if (this.feedType === 'SEARCH') {
      return '搜索';
    }
    return '热门';
  }

  private getCurrentSortLabel(): string {
    const option = KOMGA_SORT_OPTIONS.find((item: KomgaSortOption) => item.key === this.filters.sortKey);
    return option ? option.label : '相关度';
  }

  private getResultSummaryText(): string {
    if (this.items.length > 0) {
      return `共 ${this.items.length} 项`;
    }
    if (this.isLoading) {
      return '正在加载';
    }
    if (this.errorMessage.length > 0) {
      return '加载失败';
    }
    return '等待加载内容';
  }

  private getFilterChipLabel(): string {
    const count: number = this.getActiveFilterCount();
    return count > 0 ? `筛选 ${count}` : '筛选';
  }

  private getItemDescription(item: ComicInfo): string {
    const description = (item.description || '').trim();
    if (description.length > 0) {
      return description;
    }
    const summary = this.getStringField(item, 'summary').trim();
    if (summary.length > 0) {
      return summary;
    }
    const seriesTitle = this.getStringField(item, 'seriesTitle').trim();
    if (seriesTitle.length > 0 && seriesTitle !== item.title) {
      return seriesTitle;
    }
    return '';
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
    .borderRadius(8)
    .onClick(() => action())
  }

  @Builder
  private buildDisplayModeToolbarButton() {
    if (this.displayMode === 'grid') {
      this.buildToolbarButton($r('sys.symbol.list_bullet'), () => {
        this.setDisplayMode('list');
      })
    } else {
      this.buildToolbarButton($r('sys.symbol.square_grid_2x2'), () => {
        this.setDisplayMode('grid');
      })
    }
  }

  // 使用 $$ 让调用处的 @State 表达式按引用参与局部刷新。
  @Builder
  private buildChip($$: KomgaChipBuilderParams) {
    Text($$.label)
      .fontSize(13)
      .fontColor($$.selected ? Color.White : this.color('text_primary'))
      .fontFamily(this.appFontFamily)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor($$.selected ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(16)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => $$.action())
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
        SymbolGlyph($r('sys.symbol.bookshelf'))
          .fontSize(17)
          .fontColor([this.color('accent_blue')])
      }
      .width(32)
      .height(32)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(10)

      Column({ space: 2 }) {
        Text(library.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('进入库详情后再查看具体内容')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('text_muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([this.color('text_muted')])
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(12)
    .onClick(() => {
      this.openLibraryDetail(library);
    })
  }

  @Builder
  private buildOverviewPanel() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('Komga')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text(`${this.getCurrentInstanceLabel()} · ${this.getBrowseModeLabel()} · ${this.getCurrentContentTypeLabel()}`)
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          this.buildToolbarButton($r('sys.symbol.arrow_left_arrow_right'), () => {
            this.openInstanceDialog();
          })
          this.buildToolbarButton($r('sys.symbol.gearshape'), () => {
            this.openSettings();
          })
          this.buildDisplayModeToolbarButton()
        }
        .height(40)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(`${this.instances.length} 个实例`)
          .fontSize(11)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(999)
        Text(this.getResultSummaryText())
          .fontSize(11)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(999)
        if (this.getActiveFilterCount() > 0) {
          Text(`筛选 ${this.getActiveFilterCount()}`)
            .fontSize(11)
            .fontColor(this.color('accent_blue'))
            .fontFamily(this.appFontFamily)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.color('comp_background_tertiary'))
            .borderRadius(999)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildGridItem(item: ComicInfo) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        KomgaImage({
          src: this.getCoverUrl(item),
          imageWidth: '100%',
          imageHeight: 168,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 10,
          requestHeaders: this.executor.getImageHeaders(item.instanceId),
          cacheKey: this.getItemCacheKey(item)
        })
        Text(this.getItemTypeLabel(item))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('accent_blue'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(999)
          .margin({ left: 8, bottom: 8 })
      }
      Text(item.title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.getItemMetaLine(item))
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.color('text_muted'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding(4)
    .onClick(() => this.openDetail(item))
  }

  @Builder
  private buildListItem(item: ComicInfo) {
    Row({ space: 12 }) {
      KomgaImage({
        src: this.getCoverUrl(item),
        imageWidth: 60,
        imageHeight: 84,
        objectFit: ImageFit.Cover,
        imgBorderRadius: 8,
        requestHeaders: this.executor.getImageHeaders(item.instanceId),
        cacheKey: this.getItemCacheKey(item)
      })
      Column({ space: 4 }) {
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
        if (this.getItemDescription(item).length > 0) {
          Text(this.getItemDescription(item))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.color('text_muted'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(this.getItemTypeLabel(item))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.color('accent_blue'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(999)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(12)
    .onClick(() => this.openDetail(item))
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: 12 }) {
            Blank().height(this.topSpacerHeight)
            this.buildOverviewPanel()

            Column({ space: 10 }) {
              Search({ value: this.searchQuery, placeholder: this.browseMode === 'library' ? '搜索 Komga 书库...' : '搜索 Komga 目录...' })
                .width('100%')
                .height(40)
                .searchButton('搜索')
                .onChange((value: string) => {
                  this.searchQuery = value;
                })
                .onSubmit((_value: string) => {
                  void this.loadItems(true, false);
                })

              Scroll() {
                Row({ space: 0 }) {
                  this.buildChip({ label: '库', selected: this.browseMode === 'library', action: () => { this.setBrowseMode('library'); } })
                  this.buildChip({ label: '发现', selected: this.browseMode === 'discover', action: () => { this.setBrowseMode('discover'); } })
                  this.buildChip({ label: '系列', selected: this.contentType === 'SERIES', action: () => { this.setContentType('SERIES'); } })
                  this.buildChip({ label: '阅读列表', selected: this.contentType === 'READLISTS', action: () => { this.setContentType('READLISTS'); } })
                  this.buildChip({ label: '书籍', selected: this.contentType === 'BOOKS', action: () => { this.setContentType('BOOKS'); } })
                  if (this.browseMode === 'discover' && this.searchQuery.trim().length <= 0) {
                    this.buildChip({ label: '热门', selected: this.feedType === 'POPULAR', action: () => { this.setFeedType('POPULAR'); } })
                    this.buildChip({ label: '最新', selected: this.feedType === 'LATEST', action: () => { this.setFeedType('LATEST'); } })
                  }
                  this.buildChip({ label: this.getFilterChipLabel(), selected: this.showFilters, action: () => { this.toggleFilterPanel(); } })
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(36)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 4 })

            if (this.browseMode === 'library' && this.filterOptions.libraries.length > 0) {
              Column({ space: 8 }) {
                Text('库入口')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_primary'))
                Text('打开对应库详情后，可按不同内容类型和排序方式查看库内漫画。')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
                  .lineHeight(16)
                  .width('100%')
                ForEach(this.filterOptions.libraries, (library: KomgaLibraryOption) => {
                  this.buildLibraryEntryCard(library)
                }, (library: KomgaLibraryOption) => library.id)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            }

            if (this.showFilters) {
              Column() {
                Column({ space: 12 }) {
                  if (this.filterOptions.libraries.length > 0) {
                    this.buildPanelTitle('书库范围')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(this.filterOptions.libraries, (library: KomgaLibraryOption) => {
                        this.buildChip({
                          label: library.name,
                          selected: this.filters.selectedLibraryIds.includes(library.id),
                          action: () => { this.toggleLibraryFilter(library.id); }
                        })
                      }, (library: KomgaLibraryOption) => library.id)
                    }
                  }

                  this.buildPanelTitle('阅读进度')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    this.buildChip({ label: '全部进度', selected: this.filters.readStatusMode === 'ANY', action: () => { this.setReadStatusMode('ANY'); } })
                    this.buildChip({ label: '未读', selected: this.filters.readStatusMode === 'UNREAD', action: () => { this.setReadStatusMode('UNREAD'); } })
                    this.buildChip({ label: '阅读中', selected: this.filters.readStatusMode === 'IN_PROGRESS', action: () => { this.setReadStatusMode('IN_PROGRESS'); } })
                    this.buildChip({ label: '已读', selected: this.filters.readStatusMode === 'READ', action: () => { this.setReadStatusMode('READ'); } })
                  }

                  this.buildPanelTitle('排序')
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(KOMGA_SORT_OPTIONS, (option: KomgaSortOption) => {
                      this.buildChip({ label: option.label, selected: this.filters.sortKey === option.key, action: () => { this.setSortKey(option.key); } })
                    }, (option: KomgaSortOption) => option.key)
                  }

                  if (this.contentType === 'SERIES' && this.filterOptions.collections.length > 0) {
                    this.buildPanelTitle('收藏集')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      this.buildChip({ label: '全部收藏集', selected: this.filters.collectionId.length <= 0, action: () => { this.setCollectionFilter(''); } })
                      ForEach(this.filterOptions.collections, (collection: KomgaCollectionOption) => {
                        this.buildChip({
                          label: collection.name,
                          selected: this.filters.collectionId === collection.id,
                          action: () => { this.setCollectionFilter(collection.id); }
                        })
                      }, (collection: KomgaCollectionOption) => collection.id)
                    }
                  }

                  if (this.filterOptions.genres.length > 0) {
                    this.buildPanelTitle('流派')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(this.filterOptions.genres, (genre: string) => {
                        this.buildChip({ label: genre, selected: this.filters.selectedGenres.includes(genre), action: () => { this.toggleGenreFilter(genre); } })
                      }, (genre: string) => genre)
                    }
                  }

                  if (this.filterOptions.tags.length > 0) {
                    this.buildPanelTitle('标签')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(this.filterOptions.tags, (tag: string) => {
                        this.buildChip({ label: tag, selected: this.filters.selectedTags.includes(tag), action: () => { this.toggleTagFilter(tag); } })
                      }, (tag: string) => tag)
                    }
                  }

                  if (this.filterOptions.publishers.length > 0) {
                    this.buildPanelTitle('出版社')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      ForEach(this.filterOptions.publishers, (publisher: string) => {
                        this.buildChip({ label: publisher, selected: this.filters.selectedPublishers.includes(publisher), action: () => { this.togglePublisherFilter(publisher); } })
                      }, (publisher: string) => publisher)
                    }
                  }

                  if (this.getAuthorRoleKeys().length > 0) {
                    this.buildPanelTitle('作者')
                    Flex({ wrap: FlexWrap.Wrap }) {
                      this.buildChip({ label: '全部角色', selected: this.filters.selectedAuthorRole.length <= 0, action: () => { this.clearAuthorRoleFilter(); } })
                      ForEach(this.getAuthorRoleKeys(), (role: string) => {
                        this.buildChip({ label: role, selected: this.filters.selectedAuthorRole === role, action: () => { this.setAuthorRoleFilter(role); } })
                      }, (role: string) => role)
                    }
                    if (this.filters.selectedAuthorRole.length > 0) {
                      Flex({ wrap: FlexWrap.Wrap }) {
                        ForEach(this.getAuthorNamesForSelectedRole(), (authorName: string) => {
                          this.buildChip({ label: authorName, selected: this.filters.selectedAuthorName === authorName, action: () => { this.toggleAuthorNameFilter(authorName); } })
                        }, (authorName: string) => authorName)
                      }
                    }
                  }
                }
                .width('100%')
                .padding(16)
                .backgroundColor(this.color('panel_background'))
                .borderRadius(16)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            }

            Row({ space: 8 }) {
              if (this.browseMode === 'library') {
                Text('排序')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
                Text(this.getCurrentSortLabel())
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('accent_blue'))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.color('comp_background_tertiary'))
                  .borderRadius(12)
              } else {
                Text('动态')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('text_muted'))
                Text(this.getFeedTypeLabel())
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.color('accent_blue'))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(this.color('comp_background_tertiary'))
                  .borderRadius(12)
              }
              Blank()
              Text(this.getResultSummaryText())
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.color('text_muted'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })

            if (this.errorMessage.length > 0 && this.items.length > 0) {
              Column() {
                Row({ space: 12 }) {
                  Text(this.errorMessage)
                    .layoutWeight(1)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor('#FF6B6B')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Button('重试')
                    .height(32)
                    .backgroundColor(this.color('comp_background_tertiary'))
                    .fontColor(this.color('text_primary'))
                    .fontSize(12)
                    .onClick(() => { void this.refreshContent(); })
                }
                .width('100%')
                .padding(12)
                .backgroundColor(this.color('panel_background'))
                .borderRadius(12)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            }

            Column() {
              if (this.errorMessage.length > 0 && this.items.length <= 0) {
                Column({ space: 12 }) {
                  Text(this.errorMessage)
                    .width('100%')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor('#FF6B6B')
                  Row({ space: 12 }) {
                    Button('重新加载')
                      .layoutWeight(1)
                      .backgroundColor(this.color('accent_blue'))
                      .fontColor(Color.White)
                      .onClick(() => { void this.refreshContent(); })
                    Button('打开设置')
                      .layoutWeight(1)
                      .backgroundColor(this.color('comp_background_tertiary'))
                      .fontColor(this.color('text_primary'))
                      .onClick(() => { this.openSettings(); })
                  }
                }
                .width('100%')
                .height(220)
                .padding(20)
                .backgroundColor(this.color('panel_background'))
                .borderRadius(16)
                .justifyContent(FlexAlign.Center)
              } else if (this.isLoading && this.items.length <= 0) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(48)
                    .height(48)
                  Text('正在同步 Komga 内容...')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_muted'))
                }
                .width('100%')
                .height(220)
                .padding(24)
                .justifyContent(FlexAlign.Center)
              } else if (this.items.length <= 0) {
                Column({ space: 12 }) {
                  SymbolGlyph($r('sys.symbol.picture'))
                    .fontSize(40)
                    .fontColor([this.color('text_muted')])
                  Text(this.searchQuery.trim().length > 0 ? '没有找到匹配内容' : '当前没有可浏览内容')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_primary'))
                  Text('可以切换实例、调整筛选条件，或前往 Komga 设置检查连接。')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.color('text_muted'))
                    .textAlign(TextAlign.Center)
                  Button('打开 Komga 设置')
                    .backgroundColor(this.color('accent_blue'))
                    .fontColor(Color.White)
                    .onClick(() => { this.openSettings(); })
                }
                .width('100%')
                .height(240)
                .padding(24)
                .justifyContent(FlexAlign.Center)
              } else {
                Stack() {
                  if (this.displayMode === 'grid') {
                    Grid() {
                      ForEach(this.items, (item: ComicInfo) => {
                        GridItem() {
                          this.buildGridItem(item)
                        }
                      }, (item: ComicInfo) => this.getItemKey(item))
                    }
                    .columnsTemplate('1fr 1fr 1fr')
                    .columnsGap(8)
                    .rowsGap(8)
                    .width('100%')
                    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
                  }

                  if (this.displayMode === 'list') {
                    Column({ space: 8 }) {
                      ForEach(this.items, (item: ComicInfo) => {
                        this.buildListItem(item)
                      }, (item: ComicInfo) => this.getItemKey(item))
                    }
                    .width('100%')
                    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
                  }
                }
                .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 0 })

            if (this.hasMore && this.items.length > 0) {
              Column() {
                Button(this.isLoadingMore ? '加载中...' : '加载更多')
                  .width('100%')
                  .height(44)
                  .backgroundColor(this.color('comp_background_tertiary'))
                  .fontColor(this.color('text_primary'))
                  .enabled(!this.isLoadingMore)
                  .onClick(() => { void this.loadItems(false, false); })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 0 })
            }

            Blank().height(this.bottomSpacerHeight)
          }
          .width('100%')
          .padding(0)
          .backgroundColor(Color.Transparent)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor(Color.Transparent)

        if (this.refreshHintVisible) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([Color.White])
            Text('Komga 内容已刷新')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.color('accent_blue'))
          .borderRadius(20)
          .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.15)', offsetY: 2 })
          .position({ x: '50%', y: this.topSpacerHeight + 8 })
          .translate({ x: '-50%' })
          .opacity(this.refreshHintVisible ? 1 : 0)
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
          .hitTestBehavior(HitTestMode.None)
        }

        Column() {
          Divider()
            .width('100%')
            .height(0.5)
            .color(this.color('comp_background_tertiary'))
          Row({ space: 0 }) {
            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.bookshelf'))
                .fontSize(24)
                .fontColor([this.browseMode === 'library' ? this.color('accent_blue') : this.color('text_muted')])
              Text('库')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.browseMode === 'library' ? this.color('accent_blue') : this.color('text_muted'))
            }
            .layoutWeight(1)
            .height(56)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.setBrowseMode('library'); })

            Column({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.picture'))
                .fontSize(24)
                .fontColor([this.browseMode === 'discover' ? this.color('accent_blue') : this.color('text_muted')])
              Text('发现')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.browseMode === 'discover' ? this.color('accent_blue') : this.color('text_muted'))
            }
            .layoutWeight(1)
            .height(56)
            .justifyContent(FlexAlign.Center)
            .onClick(() => { this.setBrowseMode('discover'); })
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
        .shadow({
          radius: 16,
          color: this.themeState.currentTheme === ThemeType.DARK ? 'rgba(0, 0, 0, 0.4)' : 'rgba(0, 0, 0, 0.15)',
          offsetX: 0,
          offsetY: -4
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .onRefreshing(() => {
      this.beginPullRefresh();
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
