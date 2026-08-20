/**
 * 全局搜索页面
 * 搜索所有内容（本地+在线漫画、电子书、小说）
 */
import { common } from '@kit.AbilityKit';
import { ComicInfo } from '../Framework/Data/DataManager';
import { EBook } from '../Models/EBookModels';
import { NovelBook, NovelSearchResult, NovelSourceInfo } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { NovelDetailPageParams } from './NovelBookshelfPage';
import {
  GlobalSearchService,
  getGlobalSearchService,
  SearchContentType,
  SearchSourceType,
  OnlineSourceType,
  UnifiedSearchItem,
  SearchSourceGroup,
  SearchFilterConfig
} from '../Framework/Services/GlobalSearchService';
import { SourceInfo } from '../Framework/Source/SourceManager';
import { PageSettingsHelper, DetailPageType, SceneType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsPageSurfaceManager } from './settings/SettingsPageSurfaceManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SourceDetailSearchExecutor, getSourceDetailSearchExecutor } from '../Framework/Services/SourceDetailSearchExecutor';
import { openSourceDetailInIsolatedAbility } from '../Framework/Source/SourceDetailAbilityLauncher';
import { MangaDetailPageParams } from './MangaDetailPage';
import type { SourceDetailParams } from './SourceDetailPage';
import { GlobalSearchSessionHandle } from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchSessionTypes';
import { SearchResultDataSource } from 'manxia_source_engine/src/main/ets/Framework/Search/SearchResultDataSource';
import { GlobalSearchFlowMonitor, getGlobalSearchFlowMonitor } from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowMonitor';
import {
  GlobalSearchFlowEvent,
  GlobalSearchFlowEventType,
  GlobalSearchFlowSessionInfo,
  GlobalSearchFlowSeverity
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowTypes';
import {
  buildGlobalSearchCacheKey,
  createGlobalSearchCacheData,
  GlobalSearchCacheData,
  GlobalSearchCachedComicInfo
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchCacheBridge';

const TAG = 'GlobalSearchPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const SEARCH_PREFS_NAME = 'global_search_preferences';
const SEARCH_HISTORY_PREF_KEY: string = 'searchHistory';
const SEARCH_LOADING_GROUP_KEYS: number[] = [0, 1];
const SEARCH_LOADING_ITEM_KEYS: number[] = [0, 1, 2, 3];
const SEARCH_LOADING_LANDSCAPE_ITEM_KEYS: number[] = [0, 1, 2, 3, 4, 5];
const SEARCH_SHIMMER_INTERVAL_MS: number = 1800;
const SEARCH_RESULT_REVEAL_DURATION_MS: number = 360;
const SEARCH_GROUP_EXPAND_DURATION_MS: number = 320;
const SEARCH_COVER_FADE_DURATION_MS: number = 260;
const SEARCH_SHIMMER_BLADE_WIDTH: number = 5;
const SEARCH_PREF_SAVE_DEBOUNCE_MS: number = 350;
const SEARCH_RESULT_ITEM_WIDTH: number = 100;
const SEARCH_RESULT_ITEM_HEIGHT: number = 184;
const SEARCH_RESULT_EXPANDED_GRID_COLUMNS: number = 3;
const SEARCH_RESULT_EXPANDED_GRID_COLUMN_GAP: number = 12;
const SEARCH_RESULT_EXPANDED_GRID_ROW_GAP: number = 12;

// 源选择列表分页常量
const SOURCE_DISPLAY_LIMIT = 20;  // 默认显示数量
const SOURCE_DISPLAY_STEP = 50;   // 每次加载更多的数量

// 搜索偏好持久化接口
interface SearchPreferences {
  contentType: string;
  sourceType: string;
  selectedMangaSources: string[];
  selectedNovelSources: string[];
  enableSuwayomi: boolean;
  showSourceExpanded: boolean;  // 是否展开源选择器
}

// 导航参数接口
interface MangaDetailNavParam {
  mangaId: string;
}

interface EBookDetailNavParam {
  bookId: string;
}

interface SuwayomiDetailNavParam {
  mangaId: string;
}

// 全局搜索页面参数接口
export interface GlobalSearchPageParams {
  initialKeyword?: string;  // 初始搜索关键词
  initialContentType?: string;    // 初始内容类型筛选 ('manga' | 'novel' | 'ebook' | 'all')
  initialSourceType?: string;     // 初始来源类型筛选 ('local' | 'online' | 'all')
  autoSelectAllSources?: boolean; // 是否自动选中该类型的所有已开启源
}


@Component
export struct GlobalSearchPage {
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('source_features_enabled') @Watch('onSourceFeaturesEnabledChanged') sourceFeaturesEnabled: boolean = false;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'GlobalSearchPage';
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  
  // 搜索相关
  @State searchKeyword: string = '';
  @State isSearching: boolean = false;
  @State searchProgress: string = '';
  @State onlineSourceProgressCompleted: number = 0;
  @State onlineSourceProgressTotal: number = 0;
  @State onlineSourceProgressFinished: boolean = false;
  @State hasOnlineSourceProgress: boolean = false;
  
  // 筛选配置
  @State contentTypeFilter: SearchContentType = SearchContentType.ALL;
  @State sourceTypeFilter: SearchSourceType = SearchSourceType.LOCAL;
  @State selectedMangaSources: string[] = [];
  @State selectedNovelSources: string[] = [];
  @State enableSuwayomi: boolean = false;
  @State maxConcurrent: number = 5;
  
  // 可用源列表
  @State availableMangaSources: SourceInfo[] = [];
  @State availableNovelSources: NovelSourceInfo[] = [];
  @State isSuwayomiAvailable: boolean = false;
  
  // 结果相关
  @State sourceGroups: SearchSourceGroup[] = [];
  @State filteredGroups: SearchSourceGroup[] = [];  // 缓存筛选结果
  private filteredGroupDataSource: SearchResultDataSource<SearchSourceGroup> = new SearchResultDataSource<SearchSourceGroup>();
  
  // 历史记录
  @State searchHistory: string[] = [];
  @State isSearchHistoryLoaded: boolean = false;
  
  // UI 状态
  @State showSourceExpanded: boolean = false;  // 源选择区域是否展开
  @State expandedGroups: Set<string> = new Set<string>();  // 已展开显示所有结果的分组ID
  @State mangaSourceDisplayCount: number = SOURCE_DISPLAY_LIMIT;  // 当前显示的漫画图源数量
  @State novelSourceDisplayCount: number = SOURCE_DISPLAY_LIMIT;  // 当前显示的小说书源数量
  @State isResultsScrolling: boolean = false;  // 结果列表是否正在滚动
  @State private searchLoadingMotionPhase: number = 0;
  @State private resultRevealPhase: number = 1;
  @State private loadedSearchCoverIds: Set<string> = new Set<string>();
  @State private allowSearchCoverPlaceholders: boolean = false;
  @State private searchResultRenderVersion: number = 0;
  private searchLoadingMotionTimer: number = -1;
  private resultRevealTimer: number = -1;
  private coverPlaceholderReleaseTimer: number = -1;
  private lastVisibleResultItemCount: number = 0;
  
  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  @State responsive_gridColumns: number = 5;
  
  // 服务
  private searchService: GlobalSearchService = getGlobalSearchService();
  private searchFlowMonitor: GlobalSearchFlowMonitor = getGlobalSearchFlowMonitor();
  private sourceDetailSearchExecutor: SourceDetailSearchExecutor = getSourceDetailSearchExecutor();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private pathStack: NavPathStack = new NavPathStack();
  private sourceDetailWindowSequence: number = 0;
  private lastProgressUpdate: number = 0;  // 上次进度更新时间戳
  private pendingProgressGroups: SearchSourceGroup[] | null = null;
  private pendingProgressCompleted: number = 0;
  private pendingProgressTotal: number = 0;
  private activeSearchToken: number = 0;
  private currentSearchHandle: GlobalSearchSessionHandle<SearchSourceGroup[]> | null = null;
  private currentSearchFlowSessionId: string = '';
  private currentSearchFlowStartTime: number = 0;
  private lastFilteredGroupsSignature: string = '';
  private searchPreferenceSaveTimer: number = -1;
  
  // WebView 相关（用于后台搜索 WebView 格式图源）
  private webViewController: webview.WebviewController = new webview.WebviewController();
  @State webViewReady: boolean = false;
  @State webViewControllerAttached: boolean = false;
  
  // 页面参数
  @State pageParams: GlobalSearchPageParams | null = null;
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();

  private isSourceGuideAnchor(anchorId?: string): boolean {
    return anchorId === 'guide_global_search_source_types' ||
      anchorId === 'guide_global_search_online_sources';
  }

  private applySourceFeatureVisibility(): void {
    if (!this.sourceFeaturesEnabled) {
      this.sourceTypeFilter = SearchSourceType.LOCAL;
      this.showSourceExpanded = false;
      this.resetOnlineSourceProgressStatus();
    }
  }

  private getEffectiveSourceTypeFilter(): SearchSourceType {
    return this.sourceFeaturesEnabled ? this.sourceTypeFilter : SearchSourceType.LOCAL;
  }

  private onSourceFeaturesEnabledChanged(): void {
    this.applySourceFeatureVisibility();
    this.updateFilteredGroups();
    this.syncSearchLoadingMotion();
    void this.refreshPageGuide('source_features_changed');
  }

  aboutToAppear(): void {
    this.previousDisplayMode = WindowManager.getCurrentMode();
    WindowManager.setDisplayMode(DisplayMode.DEFAULT, this.getUIContext());
    this.initThemeAware();
    this.initFontAware();
    void this.loadSearchHistory();
    this.initResponsiveLayout();
    this.loadSearchPreferences();
    this.loadAvailableSources();
    this.initWebView();
    void this.refreshPageGuide('aboutToAppear');
  }

  onPageShow(): void {
    WindowManager.setDisplayMode(DisplayMode.DEFAULT, this.getUIContext());
    if (this.webViewControllerAttached) {
      this.sourceDetailSearchExecutor.attachWebViewController(this.webViewController);
    }
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_global_search_root');
    } catch (error) {
      logger.warn(TAG, `获取全局搜索引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private adjustGuideHighlightRect(anchorId: string | undefined, rect: GuideHighlightRect | null): GuideHighlightRect | null {
    return rect;
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.GLOBAL_SEARCH);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.GLOBAL_SEARCH) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      return;
    }
    if (!this.sourceFeaturesEnabled && this.isSourceGuideAnchor(step.anchorId)) {
      await this.appGuideManager.nextStep();
      void this.refreshPageGuide(`${trigger}_skip_hidden_source_features`);
      return;
    }
    if (this.prepareGuidePresentation(step.anchorId) && !trigger.endsWith('_after_prepare')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_prepare`);
      }, 160);
      return;
    }
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.adjustGuideHighlightRect(
      step.anchorId,
      this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18)
    );
    if (!this.appGuideHighlightRect && !trigger.endsWith('_retry_layout')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_retry_layout`);
      }, 120);
    }
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  private prepareGuidePresentation(anchorId?: string): boolean {
    if (!this.sourceFeaturesEnabled) {
      if (this.showSourceExpanded) {
        this.showSourceExpanded = false;
        return true;
      }
      return false;
    }

    if (anchorId === 'guide_global_search_online_sources') {
      let changed = false;
      if (this.sourceTypeFilter === SearchSourceType.LOCAL) {
        this.sourceTypeFilter = SearchSourceType.ONLINE;
        changed = true;
      }
      if (this.contentTypeFilter === SearchContentType.EBOOK) {
        this.contentTypeFilter = SearchContentType.ALL;
        changed = true;
      }
      if (!this.showSourceExpanded) {
        this.showSourceExpanded = true;
        changed = true;
      }
      return changed;
    }

    if (this.showSourceExpanded) {
      this.showSourceExpanded = false;
      return true;
    }
    return false;
  }
  
  /**
   * 初始化 WebView（用于后台搜索 WebView 格式图源）
   */
  private initWebView(): void {
    // WebView 控制器将在组件附加时设置为全局控制器
    logger.info(TAG, '初始化 WebView 用于全局搜索');
  }
  
  /**
   * 等待 WebView 就绪
   * 【关键】图源搜索需要 WebView 控制器，必须等待其附加完成
   */
  private async waitForWebViewReady(): Promise<void> {
    // 如果已经就绪，直接返回
    if (this.webViewReady && this.webViewControllerAttached) {
      logger.debug(TAG, 'WebView 已就绪');
      return;
    }
    
    // 等待 WebView 附加，最多等待 5 秒
    const maxWaitTime = 5000;
    const checkInterval = 100;
    let waitedTime = 0;
    
    logger.info(TAG, '等待 WebView 就绪...');
    
    while ((!this.webViewReady || !this.webViewControllerAttached) && waitedTime < maxWaitTime) {
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      waitedTime += checkInterval;
    }
    
    if (this.webViewReady && this.webViewControllerAttached) {
      logger.info(TAG, `WebView 已就绪，等待了 ${waitedTime}ms`);
    } else {
      logger.warn(TAG, `WebView 等待超时 (${maxWaitTime}ms)，取消本次 WebView 图源搜索准备`);
      throw new Error('WebView控制器未附加');
    }
  }

  /**
   * 加载搜索偏好设置
   */
  private async loadSearchPreferences(): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext();
      if (!hostContext) {
        logger.warn(TAG, '加载搜索偏好失败: 页面上下文不可用');
        return;
      }
      const context = hostContext as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: SEARCH_PREFS_NAME });
      
      const contentType = await store.get('contentType', SearchContentType.ALL) as string;
      const sourceType = await store.get('sourceType', SearchSourceType.LOCAL) as string;
      const mangaSources = await store.get('selectedMangaSources', '[]') as string;
      const novelSources = await store.get('selectedNovelSources', '[]') as string;
      const suwayomi = await store.get('enableSuwayomi', false) as boolean;
      const expanded = await store.get('showSourceExpanded', false) as boolean;
      
      this.contentTypeFilter = contentType as SearchContentType;
      this.sourceTypeFilter = sourceType as SearchSourceType;
      this.selectedMangaSources = SafeUtils.parseArr<string[]>(mangaSources);
      this.selectedNovelSources = SafeUtils.parseArr<string[]>(novelSources);
      this.enableSuwayomi = suwayomi;
      this.showSourceExpanded = expanded;
      this.applySourceFeatureVisibility();
      
      logger.info(TAG, `加载搜索偏好: 内容=${contentType}, 来源=${sourceType}`);
    } catch (error) {
      logger.warn(TAG, `加载搜索偏好失败: ${error}`);
    }
  }

  /**
   * 保存搜索偏好设置
   */
  private async saveSearchPreferences(): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext();
      if (!hostContext) {
        logger.warn(TAG, '保存搜索偏好失败: 页面上下文不可用');
        return;
      }
      const context = hostContext as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: SEARCH_PREFS_NAME });
      const effectiveSourceType = this.getEffectiveSourceTypeFilter();
      const shouldShowSourceExpanded = this.sourceFeaturesEnabled ? this.showSourceExpanded : false;
      const shouldEnableSuwayomi = this.sourceFeaturesEnabled ? this.enableSuwayomi : false;
      
      await store.put('contentType', this.contentTypeFilter);
      await store.put('sourceType', effectiveSourceType);
      await store.put('selectedMangaSources', JSON.stringify(this.selectedMangaSources));
      await store.put('selectedNovelSources', JSON.stringify(this.selectedNovelSources));
      await store.put('enableSuwayomi', shouldEnableSuwayomi);
      await store.put('showSourceExpanded', shouldShowSourceExpanded);
      
      await store.flush();
      logger.debug(TAG, '搜索偏好已保存');
    } catch (error) {
      logger.warn(TAG, `保存搜索偏好失败: ${error}`);
    }
  }

  private clearSearchPreferencesSaveTimer(): void {
    if (this.searchPreferenceSaveTimer !== -1) {
      this.lifecycle.clearTimeout(this.searchPreferenceSaveTimer);
      this.searchPreferenceSaveTimer = -1;
    }
  }

  private scheduleSearchPreferencesSave(): void {
    this.clearSearchPreferencesSaveTimer();
    this.searchPreferenceSaveTimer = this.lifecycle.setTimeout(() => {
      this.searchPreferenceSaveTimer = -1;
      void this.saveSearchPreferences();
    }, SEARCH_PREF_SAVE_DEBOUNCE_MS);
  }

  private flushSearchPreferencesSave(): void {
    if (this.searchPreferenceSaveTimer === -1) {
      return;
    }
    this.clearSearchPreferencesSaveTimer();
    void this.saveSearchPreferences();
  }

  /**
   * 加载可用的在线源
   */
  private async loadAvailableSources(): Promise<void> {
    try {
      // 加载漫画图源
      this.availableMangaSources = await this.searchService.getAvailableMangaSources();
      logger.info(TAG, `加载了 ${this.availableMangaSources.length} 个漫画图源`);
      
      // 加载小说书源
      this.availableNovelSources = this.searchService.getAvailableNovelSources();
      logger.info(TAG, `加载了 ${this.availableNovelSources.length} 个小说书源`);
      
      // 检查 Suwayomi 是否可用
      this.isSuwayomiAvailable = this.searchService.isSuwayomiConfigured();
      logger.info(TAG, `Suwayomi 可用: ${this.isSuwayomiAvailable}`);
    } catch (error) {
      logger.error(TAG, `加载可用源失败: ${error}`);
    }
  }
  
  /**
   * 处理页面参数，如果有初始关键词则自动搜索
   * 支持预设筛选配置（从详情页快捷搜索跳转时使用）
   */
  private async handlePageParams(): Promise<void> {
    if (this.pageParams?.initialKeyword) {
      this.searchKeyword = this.pageParams.initialKeyword;
      
      // 应用初始筛选配置（如果提供）
      if (this.pageParams.initialContentType) {
        this.contentTypeFilter = this.pageParams.initialContentType as SearchContentType;
      }
      if (this.pageParams.initialSourceType && this.sourceFeaturesEnabled) {
        this.sourceTypeFilter = this.pageParams.initialSourceType as SearchSourceType;
      }
      
      // 自动选中所有已开启的源
      if (this.pageParams.autoSelectAllSources && this.sourceFeaturesEnabled) {
        // 确保源列表已加载
        await this.loadAvailableSources();
        this.autoSelectSourcesForContentType();
      }

      this.applySourceFeatureVisibility();
      
      logger.info(TAG, `收到初始搜索关键词: ${this.searchKeyword}, contentType=${this.contentTypeFilter}, sourceType=${this.sourceTypeFilter}`);
      this.performSearch();
    }
  }
  
  /**
   * 根据当前内容类型自动选中所有已开启的源
   * 用于从详情页快捷搜索跳转时，自动选中对应类型的所有源
   */
  private autoSelectSourcesForContentType(): void {
    if (this.contentTypeFilter === SearchContentType.MANGA || this.contentTypeFilter === SearchContentType.ALL) {
      // 选中所有已开启的漫画图源（已按置顶排序）
      this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
      logger.info(TAG, `自动选中 ${this.selectedMangaSources.length} 个漫画图源`);
    }
    if (this.contentTypeFilter === SearchContentType.NOVEL || this.contentTypeFilter === SearchContentType.ALL) {
      // 选中所有已开启的小说书源
      this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
      logger.info(TAG, `自动选中 ${this.selectedNovelSources.length} 个小说书源`);
    }
  }

  private lifecycle = new PageLifecycleManager('GlobalSearchPage', { enableDebug: true });

  private cancelCurrentSearch(reason: string): void {
    if (this.currentSearchHandle) {
      this.recordSearchFlowSimpleEvent(
        this.currentSearchHandle.sessionId,
        GlobalSearchFlowEventType.TASK_CANCELLED,
        reason,
        true,
        `activeToken=${this.activeSearchToken}`
      );
      this.currentSearchHandle.cancel(reason);
      this.currentSearchHandle = null;
    } else {
      this.sourceDetailSearchExecutor.cancelGlobalSearchWork(reason);
    }
  }

  aboutToDisappear(): void {
    WindowManager.setDisplayMode(this.previousDisplayMode, this.getUIContext());
    this.activeSearchToken++;
    this.cancelCurrentSearch('page_disappear');
    this.flushSearchPreferencesSave();
    this.lifecycle.destroy();
    this.stopSearchLoadingMotion();
    this.clearResultRevealTimer();
    this.clearCoverPlaceholderReleaseTimer();
    // 清理主题监听器
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化主题感知
   */
  private initThemeAware(): void {
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }
  
  /**
   * 初始化字体感知
   */
  private initFontAware(): void {
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  /**
   * 初始化响应式布局
   */
  private initResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 横屏=${deviceInfo.isLandscape}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        this.responsive_gridColumns = 4;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        this.responsive_gridColumns = 5;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        this.responsive_gridColumns = 6;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        this.responsive_gridColumns = 8;
        break;
    }
  }

  /**
   * 更新筛选后的分组缓存
   */
  private updateFilteredGroups(): void {
    if (!this.searchKeyword || this.searchKeyword.trim().length === 0) {
      if (this.lastFilteredGroupsSignature.length > 0) {
        this.filteredGroups = [];
        this.filteredGroupDataSource.replaceData([]);
        this.lastFilteredGroupsSignature = '';
      }
      return;
    }
    
    // 搜索中的分组保留进度；已结束后失败或无结果的源自动隐藏。
    let groups = this.sourceGroups.filter((group: SearchSourceGroup): boolean => {
      return group.isSearching || (!group.hasError && group.items.length > 0);
    });
    const effectiveSourceType = this.getEffectiveSourceTypeFilter();

    if (effectiveSourceType === SearchSourceType.LOCAL) {
      groups = groups.filter((group: SearchSourceGroup) => group.sourceType === SearchSourceType.LOCAL);
    } else if (effectiveSourceType === SearchSourceType.ONLINE) {
      groups = groups.filter((group: SearchSourceGroup) => group.sourceType === SearchSourceType.ONLINE);
    }

    if (!this.isSearchInProgress()) {
      groups = this.sortGroupsBySearchRelevance(groups);
    }

    const nextSignature: string = this.buildFilteredGroupsSignature(groups);
    if (nextSignature === this.lastFilteredGroupsSignature) {
      return;
    }
    this.lastFilteredGroupsSignature = nextSignature;
    this.filteredGroups = groups;
    this.filteredGroupDataSource.replaceData(groups);
  }

  private buildFilteredGroupsSignature(groups: SearchSourceGroup[]): string {
    const parts: string[] = [];
    parts.push(this.searchKeyword.trim());
    parts.push(this.contentTypeFilter);
    parts.push(this.getEffectiveSourceTypeFilter());
    for (const group of groups) {
      const searchingFlag: string = group.isSearching ? '1' : '0';
      const errorFlag: string = group.hasError ? '1' : '0';
      parts.push(`${group.groupId}:${group.items.length}:${searchingFlag}:${errorFlag}:${group.errorMessage || ''}`);
    }
    return parts.join('|');
  }

  private cloneSearchGroup(group: SearchSourceGroup, forceCompleted: boolean): SearchSourceGroup {
    const cloned: SearchSourceGroup = {
      groupId: group.groupId,
      groupName: group.groupName,
      contentType: group.contentType,
      sourceType: group.sourceType,
      onlineSourceType: group.onlineSourceType,
      usesWebViewEngine: group.usesWebViewEngine,
      items: this.cloneSearchItems(group.items),
      isSearching: forceCompleted ? false : group.isSearching,
      hasError: group.hasError,
      errorMessage: group.errorMessage
    };
    return cloned;
  }

  private cloneSearchGroups(groups: SearchSourceGroup[], forceCompleted: boolean): SearchSourceGroup[] {
    const clonedGroups: SearchSourceGroup[] = [];
    for (const group of groups) {
      clonedGroups.push(this.cloneSearchGroup(group, forceCompleted));
    }
    return clonedGroups;
  }

  private cloneSearchItems(items: UnifiedSearchItem[]): UnifiedSearchItem[] {
    const clonedItems: UnifiedSearchItem[] = [];
    for (const item of items) {
      const clonedItem: UnifiedSearchItem = {
        id: item.id,
        title: item.title,
        author: item.author,
        coverUrl: item.coverUrl,
        description: item.description,
        contentType: item.contentType,
        sourceType: item.sourceType,
        onlineSourceType: item.onlineSourceType,
        sourceId: item.sourceId,
        sourceName: item.sourceName,
        sourcePkg: item.sourcePkg,
        rawManga: item.rawManga,
        rawEbook: item.rawEbook,
        rawNovelBook: item.rawNovelBook,
        rawNovelSearch: item.rawNovelSearch,
        rawOnlineComic: item.rawOnlineComic
      };
      clonedItems.push(clonedItem);
    }
    return clonedItems;
  }

  private buildSearchGroupRenderKey(group: SearchSourceGroup): string {
    const searchingFlag: string = group.isSearching ? 'searching' : 'done';
    const errorFlag: string = group.hasError ? 'error' : 'ok';
    return `${group.groupId}_${group.items.length}_${searchingFlag}_${errorFlag}`;
  }

  private buildSearchItemRenderKey(item: UnifiedSearchItem, index: number): string {
    return `${item.sourceId}_${item.id}_${index}`;
  }

  private buildExpandedSearchItemRenderKey(item: UnifiedSearchItem, index: number): string {
    return `expanded_${this.buildSearchItemRenderKey(item, index)}`;
  }

  private getExpandedSearchGridRows(itemCount: number): number {
    if (itemCount <= 0) {
      return 0;
    }
    return Math.ceil(itemCount / SEARCH_RESULT_EXPANDED_GRID_COLUMNS);
  }

  private getExpandedSearchGridHeight(itemCount: number): number {
    const rows: number = this.getExpandedSearchGridRows(itemCount);
    if (rows <= 0) {
      return 0;
    }
    return rows * SEARCH_RESULT_ITEM_HEIGHT + (rows - 1) * SEARCH_RESULT_EXPANDED_GRID_ROW_GAP;
  }

  private runSearchAnimation(duration: number, curve: Curve, callback: () => void): void {
    try {
      this.getUIContext().animateTo({ duration: duration, curve: curve }, callback);
    } catch (_error) {
      callback();
    }
  }

  private countResultItems(groups: SearchSourceGroup[]): number {
    let total = 0;
    for (const group of groups) {
      total += group.items.length;
    }
    return total;
  }

  private buildSearchFlowSessionInfo(
    sessionId: string,
    keyword: string,
    filterConfig: SearchFilterConfig
  ): GlobalSearchFlowSessionInfo {
    const info: GlobalSearchFlowSessionInfo = new GlobalSearchFlowSessionInfo();
    info.sessionId = sessionId;
    info.keyword = keyword;
    info.contentType = filterConfig.contentType;
    info.sourceType = filterConfig.sourceType;
    info.selectedMangaSourceCount = filterConfig.selectedMangaSources.length;
    info.selectedNovelSourceCount = filterConfig.selectedNovelSources.length;
    info.enableSuwayomi = filterConfig.enableSuwayomi;
    info.maxConcurrent = filterConfig.maxConcurrent;
    info.pageInstanceId = this.componentId;
    info.startedAt = Date.now();
    return info;
  }

  private recordSearchFlowSimpleEvent(
    sessionId: string,
    eventType: GlobalSearchFlowEventType,
    reason: string,
    success: boolean,
    detail: string
  ): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.searchFlowMonitor.createEvent(sessionId, eventType, reason);
    event.keyword = this.searchKeyword.trim();
    event.contentType = this.contentTypeFilter;
    event.sourceType = this.getEffectiveSourceTypeFilter();
    event.success = success;
    event.detail = detail;
    if (!success) {
      event.errorMessage = detail;
      event.severity = GlobalSearchFlowSeverity.WARN;
    }
    this.searchFlowMonitor.record(event);
  }

  private recordElapsedSearchFlowEvent(
    sessionId: string,
    eventType: GlobalSearchFlowEventType,
    reason: string,
    elapsedMs: number,
    success: boolean,
    detailOrError: string
  ): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.searchFlowMonitor.createEvent(sessionId, eventType, reason);
    event.keyword = this.searchKeyword.trim();
    event.contentType = this.contentTypeFilter;
    event.sourceType = this.getEffectiveSourceTypeFilter();
    event.elapsedMs = elapsedMs;
    event.success = success;
    if (success) {
      event.detail = detailOrError;
    } else {
      event.errorMessage = detailOrError;
      event.severity = GlobalSearchFlowSeverity.ERROR;
    }
    event.metricName = `global_search_${eventType}`;
    event.metricValue = elapsedMs;
    event.metricUnit = 'ms';
    this.searchFlowMonitor.record(event);
  }

  private recordSearchSnapshotEvent(
    sessionId: string,
    completed: number,
    total: number,
    itemCount: number,
    isFinalSnapshot: boolean,
    elapsedMs: number
  ): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.searchFlowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.SNAPSHOT_APPLIED, isFinalSnapshot ? 'final_snapshot' : 'progress_snapshot');
    event.keyword = this.searchKeyword.trim();
    event.contentType = this.contentTypeFilter;
    event.sourceType = this.getEffectiveSourceTypeFilter();
    event.completedGroups = completed;
    event.totalGroups = total;
    event.itemCount = itemCount;
    event.elapsedMs = elapsedMs;
    event.detail = `filteredGroups=${this.filteredGroups.length}, searching=${this.isSearchInProgress()}`;
    event.metricName = 'global_search_snapshot_apply';
    event.metricValue = elapsedMs;
    event.metricUnit = 'ms';
    this.searchFlowMonitor.record(event);
  }

  private recordSearchFlowError(sessionId: string, reason: string, errorMessage: string): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.searchFlowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.ERROR, reason);
    event.keyword = this.searchKeyword.trim();
    event.contentType = this.contentTypeFilter;
    event.sourceType = this.getEffectiveSourceTypeFilter();
    event.success = false;
    event.errorMessage = errorMessage;
    event.severity = GlobalSearchFlowSeverity.ERROR;
    this.searchFlowMonitor.record(event);
  }

  private sortGroupsBySearchRelevance(groups: SearchSourceGroup[]): SearchSourceGroup[] {
    const sortedGroups: SearchSourceGroup[] = groups.slice();
    sortedGroups.sort((left: SearchSourceGroup, right: SearchSourceGroup): number => {
      const rightScore: number = this.calculateGroupRelevanceScore(right);
      const leftScore: number = this.calculateGroupRelevanceScore(left);
      if (rightScore !== leftScore) {
        return rightScore - leftScore;
      }
      return this.resolveSourceGroupOriginalIndex(left.groupId) - this.resolveSourceGroupOriginalIndex(right.groupId);
    });
    return sortedGroups;
  }

  private calculateGroupRelevanceScore(group: SearchSourceGroup): number {
    const keyword: string = this.searchKeyword.trim().toLowerCase();
    if (keyword.length === 0 || group.items.length === 0) {
      return group.items.length;
    }

    let bestItemScore: number = 0;
    for (let i = 0; i < group.items.length; i++) {
      const score: number = this.calculateItemRelevanceScore(group.items[i], keyword, i);
      if (score > bestItemScore) {
        bestItemScore = score;
      }
    }
    return bestItemScore + Math.min(group.items.length, 100);
  }

  private calculateItemRelevanceScore(item: UnifiedSearchItem, keyword: string, index: number): number {
    const title: string = item.title.toLowerCase();
    const author: string = item.author ? item.author.toLowerCase() : '';
    const description: string = item.description ? item.description.toLowerCase() : '';
    let score: number = Math.max(0, 100 - Math.min(index, 30) * 3);

    if (title === keyword) {
      score += 10000;
    } else if (title.startsWith(keyword)) {
      score += 8000;
    } else if (title.indexOf(keyword) >= 0) {
      score += 6000;
    }

    if (author.length > 0) {
      if (author === keyword) {
        score += 3500;
      } else if (author.indexOf(keyword) >= 0) {
        score += 2500;
      }
    }

    if (description.length > 0 && description.indexOf(keyword) >= 0) {
      score += 500;
    }

    return score;
  }

  private resolveSourceGroupOriginalIndex(groupId: string): number {
    for (let i = 0; i < this.sourceGroups.length; i++) {
      if (this.sourceGroups[i].groupId === groupId) {
        return i;
      }
    }
    return 999999;
  }

  private countPendingSearchCovers(groups: SearchSourceGroup[]): number {
    let total = 0;
    for (const group of groups) {
      const visibleCount = this.responsive_isLandscape || this.expandedGroups.has(group.groupId) ?
        group.items.length :
        Math.min(group.items.length, 10);
      const visibleItems = group.items.slice(0, visibleCount);
      for (const item of visibleItems) {
        if (this.shouldAnimateSearchCover(item) && !this.loadedSearchCoverIds.has(item.id)) {
          total++;
        }
      }
    }
    return total;
  }

  private clearResultRevealTimer(): void {
    if (this.resultRevealTimer !== -1) {
      this.lifecycle.clearTimeout(this.resultRevealTimer);
      this.resultRevealTimer = -1;
    }
  }

  private clearCoverPlaceholderReleaseTimer(): void {
    if (this.coverPlaceholderReleaseTimer !== -1) {
      this.lifecycle.clearTimeout(this.coverPlaceholderReleaseTimer);
      this.coverPlaceholderReleaseTimer = -1;
    }
  }

  private scheduleCoverPlaceholderRelease(): void {
    this.clearCoverPlaceholderReleaseTimer();
    this.coverPlaceholderReleaseTimer = this.lifecycle.setTimeout(() => {
      this.coverPlaceholderReleaseTimer = -1;
      this.runSearchAnimation(SEARCH_COVER_FADE_DURATION_MS, Curve.EaseOut, () => {
        this.allowSearchCoverPlaceholders = false;
        this.syncSearchLoadingMotion();
      });
    }, SEARCH_SHIMMER_INTERVAL_MS + SEARCH_COVER_FADE_DURATION_MS);
  }

  private triggerResultRevealMotion(): void {
    this.clearResultRevealTimer();
    this.resultRevealPhase = 0;
    this.resultRevealTimer = this.lifecycle.setTimeout(() => {
      this.resultRevealTimer = -1;
      this.runSearchAnimation(SEARCH_RESULT_REVEAL_DURATION_MS, Curve.EaseOut, () => {
        this.resultRevealPhase = 1;
      });
    }, 16);
  }

  private startSearchLoadingMotion(): void {
    if (this.searchLoadingMotionTimer !== -1) {
      return;
    }

    this.searchLoadingMotionPhase = 0;
    this.runSearchAnimation(SEARCH_SHIMMER_INTERVAL_MS, Curve.Linear, () => {
      this.searchLoadingMotionPhase = 1;
    });
    this.searchLoadingMotionTimer = this.lifecycle.setInterval(() => {
      const nextPhase = this.searchLoadingMotionPhase === 0 ? 1 : 0;
      this.runSearchAnimation(SEARCH_SHIMMER_INTERVAL_MS, Curve.Linear, () => {
        this.searchLoadingMotionPhase = nextPhase;
      });
    }, SEARCH_SHIMMER_INTERVAL_MS);
  }

  private stopSearchLoadingMotion(): void {
    if (this.searchLoadingMotionTimer !== -1) {
      this.lifecycle.clearInterval(this.searchLoadingMotionTimer);
      this.searchLoadingMotionTimer = -1;
    }
    this.searchLoadingMotionPhase = 0;
  }

  private syncSearchLoadingMotion(): void {
    if (this.isResultsScrolling) {
      this.stopSearchLoadingMotion();
      return;
    }
    if (this.isSearchInProgress() || this.countPendingSearchCovers(this.filteredGroups) > 0) {
      this.startSearchLoadingMotion();
      return;
    }
    this.stopSearchLoadingMotion();
  }

  private resetSearchResultMotionForNewSearch(): void {
    this.clearResultRevealTimer();
    this.clearCoverPlaceholderReleaseTimer();
    this.loadedSearchCoverIds = new Set<string>();
    this.allowSearchCoverPlaceholders = true;
    this.lastVisibleResultItemCount = 0;
    this.resultRevealPhase = 0;
    this.startSearchLoadingMotion();
  }

  private applyProgressSnapshot(
    completed: number,
    total: number,
    groups: SearchSourceGroup[],
    isFinalSnapshot: boolean
  ): void {
    const applyStartedAt: number = Date.now();
    this.lastProgressUpdate = Date.now();
    if (isFinalSnapshot) {
      this.isSearching = false;
      this.searchProgress = '';
    } else {
      this.searchProgress = `搜索中... (${completed}/${total})`;
    }
    const previousItemCount = this.lastVisibleResultItemCount;
    const clonedGroups: SearchSourceGroup[] = this.cloneSearchGroups(groups, isFinalSnapshot);
    const nextItemCount = this.countResultItems(clonedGroups);
    this.updateOnlineSourceProgressStatus(clonedGroups, isFinalSnapshot);
    this.sourceGroups = clonedGroups;
    this.updateFilteredGroups();
    this.lastVisibleResultItemCount = nextItemCount;
    logger.info(TAG, `应用搜索快照: completed=${completed}/${total}, final=${isFinalSnapshot}, groups=${this.sourceGroups.length}, filtered=${this.filteredGroups.length}, items=${nextItemCount}, searching=${this.isSearchInProgress()}`);
    if (isFinalSnapshot) {
      if (nextItemCount > 0) {
        this.scheduleCoverPlaceholderRelease();
      } else {
        this.allowSearchCoverPlaceholders = false;
      }
    }
    if (previousItemCount === 0 && nextItemCount > 0) {
      this.triggerResultRevealMotion();
    } else if (nextItemCount > 0 && this.resultRevealPhase < 1) {
      this.resultRevealPhase = 1;
    }
    this.syncSearchLoadingMotion();
    const sessionId: string = this.currentSearchHandle ? this.currentSearchHandle.sessionId : this.currentSearchFlowSessionId;
    this.recordSearchSnapshotEvent(sessionId, completed, total, nextItemCount, isFinalSnapshot, Date.now() - applyStartedAt);
  }

  private queueProgressSnapshot(completed: number, total: number, groups: SearchSourceGroup[]): void {
    this.pendingProgressGroups = groups;
    this.pendingProgressCompleted = completed;
    this.pendingProgressTotal = total;
    const sessionId: string = this.currentSearchHandle ? this.currentSearchHandle.sessionId : this.currentSearchFlowSessionId;
    this.recordSearchFlowSimpleEvent(sessionId, GlobalSearchFlowEventType.SNAPSHOT_QUEUED, 'results_scrolling', true, `completed=${completed}/${total}, groups=${groups.length}`);
  }

  private flushPendingProgressSnapshot(): void {
    if (!this.pendingProgressGroups) {
      return;
    }
    const completed = this.pendingProgressCompleted;
    const total = this.pendingProgressTotal;
    this.applyProgressSnapshot(
      completed,
      total,
      this.pendingProgressGroups,
      total > 0 && completed >= total
    );
    this.pendingProgressGroups = null;
    this.pendingProgressCompleted = 0;
    this.pendingProgressTotal = 0;
    if (total > 0 && completed >= total) {
      this.isSearching = false;
      this.searchProgress = '';
      this.syncSearchLoadingMotion();
    }
  }

  private onResultsScrollStart(): void {
    this.isResultsScrolling = true;
    this.syncSearchLoadingMotion();
  }

  private onResultsScrollStop(): void {
    this.isResultsScrolling = false;
    this.flushPendingProgressSnapshot();
    this.syncSearchLoadingMotion();
  }

  /**
   * 加载搜索历史
   */
  private normalizeSearchHistoryKeywords(keywords: string[]): string[] {
    const normalized: string[] = [];
    for (const keyword of keywords) {
      const trimmedKeyword: string = keyword.trim();
      if (trimmedKeyword.length === 0) {
        continue;
      }
      if (!normalized.includes(trimmedKeyword)) {
        normalized.push(trimmedKeyword);
      }
      if (normalized.length >= 10) {
        break;
      }
    }
    return normalized;
  }

  private mergeSearchHistory(primary: string[], secondary: string[]): string[] {
    const merged: string[] = [];
    const normalizedPrimary: string[] = this.normalizeSearchHistoryKeywords(primary);
    const normalizedSecondary: string[] = this.normalizeSearchHistoryKeywords(secondary);

    for (const keyword of normalizedPrimary) {
      if (!merged.includes(keyword)) {
        merged.push(keyword);
      }
      if (merged.length >= 10) {
        return merged;
      }
    }

    for (const keyword of normalizedSecondary) {
      if (!merged.includes(keyword)) {
        merged.push(keyword);
      }
      if (merged.length >= 10) {
        break;
      }
    }
    return merged;
  }

  private getRuntimeSearchHistory(): string[] {
    const history: string[] = AppStorage.get<string[]>(SEARCH_HISTORY_PREF_KEY) || [];
    return this.normalizeSearchHistoryKeywords(history);
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      const runtimeHistory: string[] = this.getRuntimeSearchHistory();
      if (runtimeHistory.length > 0) {
        this.searchHistory = runtimeHistory;
      }

      const hostContext = this.getUIContext()?.getHostContext();
      if (!hostContext) {
        logger.warn(TAG, '加载搜索历史失败: 页面上下文不可用');
        return;
      }

      const context = hostContext as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: SEARCH_PREFS_NAME });
      const storedHistoryJson = await store.get(SEARCH_HISTORY_PREF_KEY, '[]') as string;
      const persistedHistory: string[] = SafeUtils.parseArr<string[]>(storedHistoryJson);
      const mergedRuntimeHistory: string[] = this.mergeSearchHistory(this.searchHistory, runtimeHistory);
      const mergedHistory: string[] = this.mergeSearchHistory(mergedRuntimeHistory, persistedHistory);

      this.searchHistory = mergedHistory;
      AppStorage.setOrCreate(SEARCH_HISTORY_PREF_KEY, mergedHistory);
      if (JSON.stringify(persistedHistory) !== JSON.stringify(mergedHistory)) {
        await store.put(SEARCH_HISTORY_PREF_KEY, JSON.stringify(mergedHistory));
        await store.flush();
      }
    } catch (error) {
      logger.error(TAG, `加载搜索历史失败: ${String(error)}`);
    } finally {
      this.isSearchHistoryLoaded = true;
    }
  }

  /**
   * 保存搜索历史
   */
  private saveSearchHistory(keyword: string): void {
    const trimmedKeyword: string = keyword.trim();
    if (trimmedKeyword.length === 0) {
      return;
    }

    const history: string[] = this.mergeSearchHistory([trimmedKeyword], this.searchHistory);
    this.searchHistory = history;
    this.isSearchHistoryLoaded = true;
    AppStorage.setOrCreate(SEARCH_HISTORY_PREF_KEY, history);
    void this.persistSearchHistory(history);
  }

  private async persistSearchHistory(history: string[]): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext();
      if (!hostContext) {
        logger.warn(TAG, '保存搜索历史失败: 页面上下文不可用');
        return;
      }

      const context = hostContext as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: SEARCH_PREFS_NAME });
      const normalizedHistory: string[] = this.normalizeSearchHistoryKeywords(history);
      await store.put(SEARCH_HISTORY_PREF_KEY, JSON.stringify(normalizedHistory));
      await store.flush();
      logger.debug(TAG, `搜索历史已保存: ${normalizedHistory.length}条`);
    } catch (error) {
      logger.warn(TAG, `保存搜索历史失败: ${String(error)}`);
    }
  }

  /**
   * 执行搜索 - 使用 GlobalSearchService
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword || this.searchKeyword.trim() === '') {
      this.resetOnlineSourceProgressStatus();
      return;
    }

    const searchToken: number = this.activeSearchToken + 1;
    this.activeSearchToken = searchToken;
    const keyword: string = this.searchKeyword.trim();
    this.cancelCurrentSearch('new_search');
    this.saveSearchHistory(keyword);

    try {
      const effectiveSourceType = this.getEffectiveSourceTypeFilter();
      const filterConfig: SearchFilterConfig = {
        contentType: this.contentTypeFilter,
        sourceType: effectiveSourceType,
        selectedMangaSources: this.selectedMangaSources,
        selectedNovelSources: this.selectedNovelSources,
        enableSuwayomi: this.sourceFeaturesEnabled ? this.enableSuwayomi : false,
        maxConcurrent: this.maxConcurrent,
        sessionId: `global_search_page_${searchToken}_${Date.now()}`
      };
      const flowSessionId: string = filterConfig.sessionId || '';
      this.currentSearchFlowSessionId = flowSessionId;
      this.currentSearchFlowStartTime = Date.now();
      this.searchFlowMonitor.ensureSession(this.buildSearchFlowSessionInfo(flowSessionId, keyword, filterConfig));
      this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.REQUEST_STARTED, 'perform_search', true, `token=${searchToken}`);
      this.recordSearchFlowSimpleEvent(
        flowSessionId,
        GlobalSearchFlowEventType.FILTER_BOUND,
        'filter_config',
        true,
        `contentType=${filterConfig.contentType}, sourceType=${filterConfig.sourceType}, mangaSources=${filterConfig.selectedMangaSources.length}, novelSources=${filterConfig.selectedNovelSources.length}, suwayomi=${filterConfig.enableSuwayomi}, maxConcurrent=${filterConfig.maxConcurrent}`
      );

      const cachedGroups: SearchSourceGroup[] | null = this.searchService.getCachedFullSearchResult(keyword, filterConfig);
      if (cachedGroups !== null) {
        if (searchToken !== this.activeSearchToken) {
          this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.STALE_RESULT_DROPPED, 'stale_full_cache_result', true, `token=${searchToken}, active=${this.activeSearchToken}`);
          this.searchFlowMonitor.endSession(flowSessionId, 'stale_full_cache_result');
          logger.debug(TAG, `丢弃过期缓存搜索结果: "${keyword}"`);
          return;
        }
        this.showSourceExpanded = false;
        this.clearResultRevealTimer();
        this.clearCoverPlaceholderReleaseTimer();
        this.allowSearchCoverPlaceholders = false;
        this.resultRevealPhase = 1;
        const cachedTotal: number = cachedGroups.length;
        this.applyProgressSnapshot(cachedTotal, cachedTotal, cachedGroups, true);
        this.pendingProgressGroups = null;
        this.pendingProgressCompleted = 0;
        this.pendingProgressTotal = 0;
        this.syncSearchLoadingMotion();
        const cachedItemCount: number = this.countResultItems(cachedGroups);
        logger.info(TAG, `搜索命中完整结果缓存: "${keyword}", groups=${cachedGroups.length}, items=${cachedItemCount}`);
        this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.RESULT_COMPLETED, 'full_cache_hit', true, `groups=${cachedGroups.length}, items=${cachedItemCount}`);
        this.searchFlowMonitor.endSession(flowSessionId, 'full_cache_hit');
        return;
      }

      this.isSearching = true;
      this.searchProgress = '正在搜索...';
      this.prepareOnlineSourceProgressStatus();
      this.sourceGroups = [];
      this.filteredGroups = [];
      this.lastFilteredGroupsSignature = '';
      this.filteredGroupDataSource.replaceData([]);
      this.pendingProgressGroups = null;
      this.pendingProgressCompleted = 0;
      this.pendingProgressTotal = 0;
      this.resetSearchResultMotionForNewSearch();
      
      // 自动收起在线源列表
      this.showSourceExpanded = false;
      if (this.shouldWaitForMangaSourceWebView(effectiveSourceType)) {
        const webViewWaitStartedAt: number = Date.now();
        this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.WEBVIEW_WAIT_STARTED, 'prepare_webview', true, '');
        try {
          await this.waitForWebViewReady();
          this.recordElapsedSearchFlowEvent(flowSessionId, GlobalSearchFlowEventType.WEBVIEW_WAIT_COMPLETED, 'prepare_webview', Date.now() - webViewWaitStartedAt, true, '');
        } catch (webViewError) {
          this.recordElapsedSearchFlowEvent(flowSessionId, GlobalSearchFlowEventType.WEBVIEW_WAIT_FAILED, 'prepare_webview_failed', Date.now() - webViewWaitStartedAt, false, String(webViewError));
          throw new Error(String(webViewError));
        }
        if (searchToken !== this.activeSearchToken) {
          this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.STALE_RESULT_DROPPED, 'stale_after_webview_ready', true, `token=${searchToken}, active=${this.activeSearchToken}`);
          this.searchFlowMonitor.endSession(flowSessionId, 'stale_after_webview_ready');
          logger.debug(TAG, `丢弃过期搜索准备结果: "${keyword}"`);
          return;
        }
        this.sourceDetailSearchExecutor.attachWebViewController(this.webViewController);
      }
      
      logger.info(TAG, `开始搜索: "${keyword}", 内容类型=${this.contentTypeFilter}, 来源=${effectiveSourceType}`);

      // 执行搜索
      const handle: GlobalSearchSessionHandle<SearchSourceGroup[]> = this.searchService.createSearchSession(
        keyword,
        filterConfig,
        (completed: number, total: number, _groupName: string, groups: SearchSourceGroup[]) => {
          if (searchToken !== this.activeSearchToken) {
            return;
          }
          // 触摸/滑动期间冻结结果刷新，仅缓存最新快照，待停止滑动后一次性应用
          if (this.isResultsScrolling && completed < total) {
            this.queueProgressSnapshot(completed, total, groups);
            return;
          }

          // 节流进度更新，最多每500ms更新一次UI
          const now = Date.now();
          if (now - this.lastProgressUpdate >= 500 || completed === total) {
            this.applyProgressSnapshot(completed, total, groups, total > 0 && completed >= total);
          }
        }
      );
      this.currentSearchHandle = handle;
      const results = await handle.completion;

      if (searchToken !== this.activeSearchToken) {
        this.recordSearchFlowSimpleEvent(handle.sessionId, GlobalSearchFlowEventType.STALE_RESULT_DROPPED, 'stale_completion_result', true, `token=${searchToken}, active=${this.activeSearchToken}`);
        logger.debug(TAG, `丢弃过期搜索结果: "${keyword}"`);
        return;
      }
      if (this.currentSearchHandle && this.currentSearchHandle.sessionId === handle.sessionId) {
        this.currentSearchHandle = null;
      }
      const finalTotal = this.pendingProgressTotal > 0 ? this.pendingProgressTotal : results.length;
      this.applyProgressSnapshot(finalTotal, finalTotal, results, true);
      this.searchService.cacheFullSearchResult(keyword, filterConfig, results);
      this.pendingProgressGroups = null;
      this.pendingProgressCompleted = 0;
      this.pendingProgressTotal = 0;
      this.syncSearchLoadingMotion();
      
      const totalResults = results.reduce((sum, g) => sum + g.items.length, 0);
      logger.info(TAG, `搜索完成: ${results.length}个分组, ${totalResults}条结果`);
      this.recordSearchFlowSimpleEvent(handle.sessionId, GlobalSearchFlowEventType.RESULT_COMPLETED, 'page_render_completed', true, `groups=${results.length}, items=${totalResults}`);
    } catch (error) {
      if (searchToken !== this.activeSearchToken) {
        this.recordSearchFlowSimpleEvent(this.currentSearchFlowSessionId, GlobalSearchFlowEventType.STALE_RESULT_DROPPED, 'stale_exception', true, `token=${searchToken}, active=${this.activeSearchToken}, error=${String(error)}`);
        logger.debug(TAG, `忽略过期搜索异常: "${keyword}", ${String(error)}`);
        return;
      }
      if (this.currentSearchHandle && this.currentSearchHandle.sessionId.indexOf(`global_search_page_${searchToken}_`) === 0) {
        this.currentSearchHandle = null;
      }
      logger.error(TAG, `搜索失败: ${error}`);
      this.pendingProgressGroups = null;
      this.pendingProgressCompleted = 0;
      this.pendingProgressTotal = 0;
      this.isSearching = false;
      this.searchProgress = '';
      this.resetOnlineSourceProgressStatus();
      this.allowSearchCoverPlaceholders = false;
      this.stopSearchLoadingMotion();
      this.recordSearchFlowError(this.currentSearchFlowSessionId, 'perform_search_error', String(error));
      this.searchFlowMonitor.endSession(this.currentSearchFlowSessionId, 'page_error');
    }
  }

  /**
   * 获取内容类型的显示名称
   */
  private getContentTypeName(type: SearchContentType): string {
    switch (type) {
      case SearchContentType.MANGA: return '漫画';
      case SearchContentType.NOVEL: return '小说';
      case SearchContentType.EBOOK: return '电子书';
      default: return '全部';
    }
  }

  /**
   * 获取来源类型的显示名称
   */
  private getSourceTypeName(type: SearchSourceType): string {
    switch (type) {
      case SearchSourceType.LOCAL: return '本地';
      case SearchSourceType.ONLINE: return '在线';
      default: return '全部';
    }
  }

  /**
   * 获取项目数量文本
   */
  private getItemCountText(group: SearchSourceGroup): string {
    const count = group.items.length;
    switch (group.contentType) {
      case SearchContentType.MANGA: return `${count}本漫画`;
      case SearchContentType.NOVEL: return `${count}本小说`;
      case SearchContentType.EBOOK: return `${count}本电子书`;
      default: return `${count}项`;
    }
  }

  private getSearchResultSurfaceStyle() {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface;
  }

  private getSearchResultRowStyle() {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row;
  }

  private getSearchResultCoverRadius(): number {
    const surfaceRadius = this.getSearchResultSurfaceStyle().radius;
    return Math.max(8, Math.min(12, surfaceRadius));
  }

  private isSearchInProgress(): boolean {
    if (this.isSearching) {
      return true;
    }
    return this.sourceGroups.some((group: SearchSourceGroup) => group.isSearching);
  }

  private shouldWaitForMangaSourceWebView(effectiveSourceType: SearchSourceType): boolean {
    if (effectiveSourceType === SearchSourceType.LOCAL) {
      return false;
    }
    if (this.contentTypeFilter !== SearchContentType.ALL && this.contentTypeFilter !== SearchContentType.MANGA) {
      return false;
    }
    return this.selectedMangaSources.length > 0;
  }

  private getSearchLoadingText(): string {
    if (this.searchProgress.length > 0) {
      return this.searchProgress;
    }
    return '搜索中...';
  }

  private getSearchItemRevealDelay(index: number): number {
    return Math.min(index, 8) * 22;
  }

  private getSearchItemTransitionDelay(index: number): number {
    return Math.min(index, 10) * 18;
  }

  private getSearchItemRevealTranslateY(index: number): number {
    if (this.resultRevealPhase >= 1) {
      return 0;
    }
    return 14 + Math.min(index, 6) * 2;
  }

  private getSearchItemRevealScale(index: number): number {
    if (this.resultRevealPhase >= 1) {
      return 1;
    }
    return index % 2 === 0 ? 0.972 : 0.982;
  }

  private getSearchShimmerTranslateX(width: number, index: number): number {
    const offset = (index % 3) * 10;
    if (this.searchLoadingMotionPhase === 0) {
      return -width - 56 + offset;
    }
    return width + 56 + offset;
  }

  private shouldAnimateSearchCover(item: UnifiedSearchItem): boolean {
    const coverUrl = item.coverUrl || '';
    return this.allowSearchCoverPlaceholders && coverUrl.length > 0;
  }

  private isSearchCoverLoaded(item: UnifiedSearchItem): boolean {
    if (!this.shouldAnimateSearchCover(item)) {
      return true;
    }
    return this.loadedSearchCoverIds.has(item.id);
  }

  private getSearchCoverMediaOpacity(item: UnifiedSearchItem): number {
    return this.isSearchCoverLoaded(item) ? 1 : 0;
  }

  private getSearchCoverPlaceholderOpacity(item: UnifiedSearchItem): number {
    if (!this.shouldAnimateSearchCover(item)) {
      return 0;
    }
    return this.isSearchCoverLoaded(item) ? 0 : 1;
  }

  private markSearchCoverLoaded(itemId: string): void {
    if (this.loadedSearchCoverIds.has(itemId)) {
      return;
    }
    this.runSearchAnimation(SEARCH_COVER_FADE_DURATION_MS, Curve.EaseOut, () => {
      const newSet = new Set<string>(this.loadedSearchCoverIds);
      newSet.add(itemId);
      this.loadedSearchCoverIds = newSet;
      this.syncSearchLoadingMotion();
    });
  }

  /**
   * 获取已选源的摘要信息
   */
  private getSelectedSourcesSummary(): string {
    const parts: string[] = [];
    if (this.selectedMangaSources.length > 0) {
      parts.push(`${this.selectedMangaSources.length}个图源`);
    }
    if (this.selectedNovelSources.length > 0) {
      parts.push(`${this.selectedNovelSources.length}个书源`);
    }
    if (this.enableSuwayomi) {
      parts.push('Suwayomi');
    }
    return parts.length > 0 ? parts.join(', ') : '未选择';
  }

  /**
   * 切换漫画图源选中状态
   */
  private toggleMangaSource(sourceId: string): void {
    this.cancelCurrentSearch('manga_source_changed');
    this.resetOnlineSourceProgressStatus();
    const index = this.selectedMangaSources.indexOf(sourceId);
    if (index >= 0) {
      this.selectedMangaSources = this.selectedMangaSources.filter(id => id !== sourceId);
    } else {
      this.selectedMangaSources = [...this.selectedMangaSources, sourceId];
    }
    this.scheduleSearchPreferencesSave();
  }

  /**
   * 切换小说书源选中状态
   */
  private toggleNovelSource(sourceId: string): void {
    this.cancelCurrentSearch('novel_source_changed');
    this.resetOnlineSourceProgressStatus();
    const index = this.selectedNovelSources.indexOf(sourceId);
    if (index >= 0) {
      this.selectedNovelSources = this.selectedNovelSources.filter(id => id !== sourceId);
    } else {
      this.selectedNovelSources = [...this.selectedNovelSources, sourceId];
    }
    this.scheduleSearchPreferencesSave();
  }
  
  /**
   * 切换分组展开状态
   */
  private toggleGroupExpanded(groupId: string): void {
    this.runSearchAnimation(SEARCH_GROUP_EXPAND_DURATION_MS, Curve.EaseInOut, () => {
      const newSet = new Set<string>(this.expandedGroups);
      if (newSet.has(groupId)) {
        newSet.delete(groupId);
      } else {
        newSet.add(groupId);
      }
      this.expandedGroups = newSet;
      this.syncSearchLoadingMotion();
    });
  }

  private extractLocalContentId(itemId: string, prefix: string): string {
    if (itemId.startsWith(prefix)) {
      return itemId.substring(prefix.length);
    }
    return itemId;
  }

  private shouldOpenSourceDetailInNewWindow(): boolean {
    return this.settingsManager.getBoolean(SettingKeys.SOURCE_DETAIL_MULTI_WINDOW_ENABLED, false);
  }

  private buildSourceDetailWindowKey(sourceId: number): string {
    this.sourceDetailWindowSequence += 1;
    return `source_detail_page_${sourceId}_${Date.now()}_${this.sourceDetailWindowSequence}`;
  }

  private appendSourceDetailWindowKey(param: SourceDetailParams): SourceDetailParams {
    if (this.shouldOpenSourceDetailInNewWindow()) {
      param.sourceDetailWindowKey = this.buildSourceDetailWindowKey(param.sourceId);
    }
    return param;
  }

  private appendSourceSearchWindowKey(param: SourceDetailParams): SourceDetailParams {
    if (this.shouldOpenSourceDetailInNewWindow()) {
      param.sourceDetailWindowKey = this.buildSourceDetailWindowKey(param.sourceId);
    }
    return param;
  }

  private pushSourceDetailPath(stack: NavPathStack, param: SourceDetailParams): void {
    if (param.sourceDetailWindowKey && param.sourceDetailWindowKey.length > 0) {
      openSourceDetailInIsolatedAbility(this.getUIContext(), stack, param, TAG);
      return;
    }

    stack.removeByName('SourceDetailPage');
    stack.pushPath({ name: 'SourceDetailPage', param: param });
  }

  /**
   * 打开详情页 - 支持统一搜索结果项
   * 根据设置判断跳转到默认详情页还是统一详情页
   */
  private openDetail(item: UnifiedSearchItem): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      const stack = globalStack || this.pathStack;
      
      // 本地漫画
      if (item.contentType === SearchContentType.MANGA && item.sourceType === SearchSourceType.LOCAL) {
        const mangaId: string = item.rawManga ? item.rawManga.id : this.extractLocalContentId(item.id, 'local-manga-');
        if (mangaId.length === 0) {
          logger.warn(TAG, `本地漫画搜索结果缺少ID，无法打开详情: ${item.title}`);
          return;
        }
        const pageType = PageSettingsHelper.getMangaDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          // 统一详情页
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.MANGA,
            contentId: mangaId,
            cachedTitle: item.title,
            cachedCoverPath: this.getUnifiedDetailCachedCoverPath(item),
            cachedCover: this.getUnifiedDetailCachedCover(item),
            cachedAuthor: item.author
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          // 默认详情页
          const navParam: MangaDetailNavParam = { mangaId: mangaId };
          stack.pushPath({ name: 'MangaDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到本地漫画详情页: ${mangaId}, pageType=${pageType}`);
      }
      // 本地电子书
      else if (item.contentType === SearchContentType.EBOOK) {
        const bookId: string = item.rawEbook ? item.rawEbook.id : this.extractLocalContentId(item.id, 'local-ebook-');
        if (bookId.length === 0) {
          logger.warn(TAG, `本地电子书搜索结果缺少ID，无法打开详情: ${item.title}`);
          return;
        }
        const pageType = PageSettingsHelper.getEBookDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.EBOOK,
            contentId: bookId,
            cachedTitle: item.title,
            cachedCoverPath: this.getUnifiedDetailCachedCoverPath(item),
            cachedCover: this.getUnifiedDetailCachedCover(item),
            cachedAuthor: item.author
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: EBookDetailNavParam = { bookId: bookId };
          stack.pushPath({ name: 'EBookDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到电子书详情页: ${bookId}, pageType=${pageType}`);
      }
      // 本地小说
      else if (item.contentType === SearchContentType.NOVEL && item.sourceType === SearchSourceType.LOCAL && item.rawNovelBook) {
        const pageType = PageSettingsHelper.getNovelDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.NOVEL,
            contentId: item.rawNovelBook.bookUrl,
            sourceId: item.rawNovelBook.sourceId,
            sourceName: item.sourceName,
            cachedTitle: item.title,
            cachedCoverPath: this.getUnifiedDetailCachedCoverPath(item),
            cachedCover: this.getUnifiedDetailCachedCover(item),
            cachedAuthor: item.author
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: NovelDetailPageParams = { 
            sourceId: item.rawNovelBook.sourceId,
            bookUrl: item.rawNovelBook.bookUrl,
            bookName: item.rawNovelBook.name,
            author: item.rawNovelBook.author,
            coverUrl: item.rawNovelBook.coverUrl,
            intro: item.rawNovelBook.intro,
            sourceName: item.rawNovelBook.sourceName
          };
          stack.pushPath({ name: 'NovelDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到本地小说详情页: ${item.rawNovelBook.name}, pageType=${pageType}`);
      }
      // 在线漫画（图源）
      else if (item.contentType === SearchContentType.MANGA && item.onlineSourceType === OnlineSourceType.MANGA_SOURCE && item.rawOnlineComic) {
        const pageType = PageSettingsHelper.getMangaDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.MANGA,
            contentId: item.rawOnlineComic.id,
            sourceId: item.sourceId,
            sourceName: item.sourceName,
            sourcePkg: item.sourcePkg,
            cachedTitle: item.title,
            cachedCoverPath: this.getUnifiedDetailCachedCoverPath(item),
            cachedCover: this.getUnifiedDetailCachedCover(item),
            cachedAuthor: item.author
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: SourceDetailParams = {
            sourceId: parseInt(item.sourceId),
            comicId: item.rawOnlineComic.id,
            comicTitle: item.rawOnlineComic.title,
            sourceName: item.sourceName,
            sourcePkg: item.sourcePkg
          };
          if (item.sourcePkg && item.sourcePkg.startsWith('legado.image.')) {
            const mangaDetailParam: MangaDetailPageParams = {
              mangaId: item.rawOnlineComic.id,
              sourceId: parseInt(item.sourceId),
              sourcePkg: item.sourcePkg,
              cachedTitle: item.title,
              cachedCover: this.getUnifiedDetailCachedCover(item)
            };
            stack.pushPath({ name: 'MangaDetailPage', param: mangaDetailParam });
          } else {
            this.pushSourceDetailPath(stack, this.appendSourceDetailWindowKey(navParam));
          }
        }
        logger.debug(TAG, `导航到在线漫画详情页: ${item.rawOnlineComic.title}, pageType=${pageType}`);
      }
      // 在线漫画（Suwayomi）
      else if (item.contentType === SearchContentType.MANGA && item.onlineSourceType === OnlineSourceType.SUWAYOMI && item.rawOnlineComic) {
        const suwayomiParam: SuwayomiDetailNavParam = { mangaId: item.rawOnlineComic.id };
        stack.pushPath({ name: 'SuwayomiDetailPage', param: suwayomiParam });
        logger.debug(TAG, `导航到Suwayomi详情页: ${item.rawOnlineComic.id}`);
      }
      // 在线小说（书源）
      else if (item.contentType === SearchContentType.NOVEL && item.onlineSourceType === OnlineSourceType.NOVEL_SOURCE && item.rawNovelSearch) {
        const rawNovelSearch = item.rawNovelSearch;
        if (rawNovelSearch === undefined) {
          logger.warn(TAG, '在线小说搜索结果缺少原始书籍数据，无法打开详情');
          return;
        }
        const pageType = PageSettingsHelper.getNovelDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.NOVEL,
            contentId: rawNovelSearch.bookUrl,
            sourceId: rawNovelSearch.sourceId,
            sourceName: item.sourceName,
            cachedTitle: item.title,
            cachedCoverPath: this.getUnifiedDetailCachedCoverPath(item),
            cachedCover: this.getUnifiedDetailCachedCover(item),
            cachedAuthor: item.author,
            novelRequestCarrierKey: rawNovelSearch.requestCarrierKey,
            novelBookVariable: rawNovelSearch.variable
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: NovelDetailPageParams = { 
            sourceId: rawNovelSearch.sourceId,
            bookUrl: rawNovelSearch.bookUrl,
            bookName: rawNovelSearch.name,
            author: rawNovelSearch.author,
            coverUrl: rawNovelSearch.coverUrl,
            intro: rawNovelSearch.intro,
            sourceName: rawNovelSearch.sourceName,
            requestCarrierKey: rawNovelSearch.requestCarrierKey,
            bookVariable: rawNovelSearch.variable
          };
          stack.pushPath({ name: 'NovelDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到在线小说详情页: ${rawNovelSearch.name}, pageType=${pageType}`);
      }
    } catch (error) {
      logger.error(TAG, `打开详情页失败: ${error}`);
    }
  }

  private getUnifiedDetailCachedCoverPath(item: UnifiedSearchItem): string | undefined {
    const coverUrl = item.coverUrl || '';
    if (coverUrl.length === 0) {
      return undefined;
    }
    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://') || coverUrl.startsWith('app.media.')) {
      return undefined;
    }
    return coverUrl;
  }

  private getUnifiedDetailCachedCover(item: UnifiedSearchItem): string | undefined {
    const coverUrl = item.coverUrl || '';
    return coverUrl.length > 0 ? coverUrl : undefined;
  }
  
  /**
   * 打开图源搜索页面
   * 跳转到 SourceDetailPage 的搜索标签，传递搜索结果避免重复搜索
   */
  private openSourceSearchPage(group: SearchSourceGroup): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      const stack = globalStack || this.pathStack;
      
      // 从 groupId 提取 sourceId，格式为 "online-manga-{sourceId}"
      const groupIdParts = group.groupId.split('-');
      const sourceIdStr = groupIdParts.length >= 3 ? groupIdParts[2] : '';
      const sourceId = parseInt(sourceIdStr);
      if (isNaN(sourceId)) {
        logger.warn(TAG, `无效的图源ID: ${group.groupId}`);
        return;
      }
      
      // 转换 UnifiedSearchItem 为 SourceDetailPage 可用的 ComicInfo 格式
      const cachedResults: GlobalSearchCachedComicInfo[] = group.items.map((item: UnifiedSearchItem): GlobalSearchCachedComicInfo => {
        const result: GlobalSearchCachedComicInfo = new GlobalSearchCachedComicInfo();
        result.id = item.rawOnlineComic?.id || '';
        result.title = item.title;
        result.author = item.author || '';
        result.coverUrl = item.coverUrl || '';
        result.description = item.description || '';
        result.url = item.rawOnlineComic?.url || '';
        result.status = item.rawOnlineComic?.status || '';
        return result;
      });
      
      // 存储缓存，使用 sourceId 和 keyword 组合作为 key
      const cacheKey: string = buildGlobalSearchCacheKey(sourceId, this.searchKeyword);
      const flowSessionId: string = this.currentSearchHandle ? this.currentSearchHandle.sessionId : this.currentSearchFlowSessionId;
      const cacheData: GlobalSearchCacheData = createGlobalSearchCacheData(this.searchKeyword, cachedResults, flowSessionId);
      AppStorage.setOrCreate(cacheKey, JSON.stringify(cacheData));
      logger.info(TAG, `缓存搜索结果: ${cachedResults.length} 条, key=${cacheKey}`);
      this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.DETAIL_CACHE_WRITTEN, 'open_source_search_page', true, `sourceId=${sourceId}, cacheKey=${cacheKey}, items=${cachedResults.length}`);
      
      // 跳转到 SourceDetailPage，传递 initialTab='search' 和 searchKeyword
      // 并标记来自全局搜索，让 SourceDetailPage 优先使用缓存
      const navParam: SourceDetailParams = {
        sourceId: sourceId,
        initialTab: 'search',
        searchKeyword: this.searchKeyword,
        fromGlobalSearch: true,
        globalSearchSessionId: flowSessionId,
        sourceName: group.groupName
      };
      
      this.pushSourceDetailPath(stack, this.appendSourceSearchWindowKey(navParam));
      logger.info(TAG, `跳转到图源搜索页: sourceId=${sourceId}, keyword="${this.searchKeyword}"`);
      this.recordSearchFlowSimpleEvent(flowSessionId, GlobalSearchFlowEventType.NAVIGATE, 'open_source_search_page', true, `sourceId=${sourceId}, keyword="${this.searchKeyword}"`);
    } catch (error) {
      logger.error(TAG, `打开图源搜索页失败: ${error}`);
      this.recordSearchFlowError(this.currentSearchFlowSessionId, 'open_source_search_page', String(error));
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层（纯色，响应全局主题）
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          // 搜索栏
          Row({ space: 12 }) {
            TextInput({ placeholder: '搜索漫画、电子书、作者...', text: this.searchKeyword })
              .layoutWeight(1)
              .height(44)
              .borderRadius(12)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
              })
              .onChange((value: string) => {
                this.searchKeyword = value;
                if (!this.isSearchInProgress()) {
                  this.resetOnlineSourceProgressStatus();
                }
              })
              .onSubmit(() => {
                this.performSearch();
              })

            Button('搜索')
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.performSearch();
              })
          }
          .width('100%')
          .id('guide_global_search_input')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding(this.responsive_contentPadding)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          })
          .shadow({
            radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 8
          })
          .margin({ bottom: 16 })

          // 紧凑筛选栏 - 内容类型 + 来源类型 在一行（可滑动）
          Scroll() {
            Row({ space: 12 }) {
              // 内容类型筛选
              Row({ space: 4 }) {
                this.buildContentTypeChip('全部', SearchContentType.ALL)
                this.buildContentTypeChip('漫画', SearchContentType.MANGA)
                this.buildContentTypeChip('小说', SearchContentType.NOVEL)
                this.buildContentTypeChip('电子书', SearchContentType.EBOOK)
              }
              .id('guide_global_search_content_types')
              
              // 分隔符
              if (this.sourceFeaturesEnabled) {
                Divider()
                  .vertical(true)
                  .height(20)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

                // 来源类型筛选
                Row({ space: 6 }) {
                  this.buildSourceTypeIconChip($r('sys.symbol.folder'), SearchSourceType.LOCAL)
                  this.buildSourceTypeIconChip($r('sys.symbol.globe_and_keyboard'), SearchSourceType.ONLINE)
                  this.buildSourceTypeIconChip($r('sys.symbol.square_grid_2x2'), SearchSourceType.ALL)
                }
                .id('guide_global_search_source_types')

                // Suwayomi 独立开关（仅当可用时显示）
                if (this.isSuwayomiAvailable && this.sourceTypeFilter !== SearchSourceType.LOCAL) {
                  Divider()
                    .vertical(true)
                    .height(20)
                    .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

                  Row({ space: 4 }) {
                    SymbolGlyph($r('sys.symbol.computer_host_fill'))
                      .fontSize(14)
                      .fontColor([this.enableSuwayomi ?
                        Color.White :
                        ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                    Text('Suwayomi')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.enableSuwayomi ?
                        Color.White :
                        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .backgroundColor(this.enableSuwayomi ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .border({
                    width: 1,
                    color: this.enableSuwayomi ?
                      Color.Transparent :
                      ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                  })
                  .animation({ duration: 200, curve: Curve.EaseInOut })
                  .onClick(() => {
                    this.cancelCurrentSearch('suwayomi_toggle_changed');
                    this.resetOnlineSourceProgressStatus();
                    this.enableSuwayomi = !this.enableSuwayomi;
                    this.scheduleSearchPreferencesSave();
                  })
                }
              }
            }
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .id('guide_global_search_filters')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding({ bottom: 8 })

          // 在线源选择器（仅当选择在线或全部时显示）
          if (this.sourceFeaturesEnabled && this.sourceTypeFilter !== SearchSourceType.LOCAL) {
            this.buildInlineSourceSelector()
          }

          // 搜索结果或历史记录
          if (this.searchKeyword && this.filteredGroups.length > 0) {
            // 按图源分组显示搜索结果
            if (this.responsive_isLandscape) {
              // 横屏模式：使用网格布局
              Column() {
                this.buildLandscapeResults()
              }
              .width('100%')
              .layoutWeight(1)
              .id('guide_global_search_content_area' as string)
            } else {
              // 竖屏模式：使用列表布局
              List({ space: 16 }) {
                LazyForEach(this.filteredGroupDataSource, (group: SearchSourceGroup, index: number) => {
                  ListItem() {
                    this.buildSourceGroupCard(group, index)
                  }
                }, (group: SearchSourceGroup) => this.buildSearchGroupRenderKey(group))
                ListItem() {
                  Column() {
                    Blank().height(40 + this.navigationBarHeight)
                  }
                }
              }
              .width('100%')
              .height('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8 })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
              .id('guide_global_search_content_area' as string)
              .onScrollStart(() => {
                this.onResultsScrollStart();
              })
              .onScrollStop(() => {
                this.onResultsScrollStop();
              })
            }
          } else if (this.searchKeyword && this.sourceGroups.length > 0 && !this.isSearchInProgress()) {
            // 搜索完成但无结果
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(48)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              Text('未找到相关内容')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('换个关键词试试吧')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .id('guide_global_search_content_area' as string)
          } else if (this.searchKeyword && this.isSearchInProgress()) {
            // 正在搜索：只让结果区进入骨架态，保留顶部输入与筛选区域稳定可交互。
            this.buildInitialSearchLoadingState()
          } else {
            // 搜索历史
            Column() {
              if (this.searchHistory.length > 0) {
                Text('搜索历史')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .padding(this.responsive_contentPadding)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.searchHistory, (keyword: string) => {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.clock'))
                        .fontSize(14)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                      Text(keyword)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .padding({ left: 12, right: 14, top: 8, bottom: 8 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .borderRadius(18)
                    .border({
                      width: 1,
                      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                    })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.searchKeyword = keyword;
                      this.performSearch();
                    })
                  })
                }
                .width('100%')
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              } else if (!this.isSearchHistoryLoaded) {
                Column({ space: 8 }) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  Text('正在加载搜索历史...')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                .width('100%')
                .padding({
                  left: this.responsive_contentPadding,
                  right: this.responsive_contentPadding,
                  top: 24,
                  bottom: 24
                })
              } else {
                Column({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.clock'))
                    .fontSize(28)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                  Text('暂无搜索历史')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text('完成一次搜索后，这里会保留最近使用过的关键词，方便你快速重复搜索或切换筛选后重新查询。')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .padding({
                  left: this.responsive_contentPadding,
                  right: this.responsive_contentPadding,
                  top: 24,
                  bottom: 24
                })
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignItems(HorizontalAlign.Start)
            .id('guide_global_search_content_area' as string)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .alignItems(this.responsive_isLandscape ? HorizontalAlign.Center : HorizontalAlign.Start)
        .id('guide_global_search_root')
        
        // 隐藏的 WebView 组件（用于后台搜索 WebView 格式图源）
        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            showSkip: this.appGuideStep.showSkip !== false,
            themeState: this.themeState,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }

        Web({
          src: 'about:blank',
          controller: this.webViewController
        })
          .width(1)
          .height(1)
          .opacity(0)
          .visibility(Visibility.None)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .onControllerAttached(() => {
            logger.info(TAG, 'WebView控制器已附加，设置为全局控制器');
            this.webViewControllerAttached = true;
            this.webViewReady = true;
            this.sourceDetailSearchExecutor.attachWebViewController(this.webViewController);
          })
          .onPageEnd(() => {
            logger.debug(TAG, 'WebView页面加载完成');
          })
          .onErrorReceive((event) => {
            const errorInfo = event.error.getErrorInfo();
            logger.warn(TAG, `WebView错误: ${errorInfo}`);
          })
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '全局搜索',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })
      }
      .width('100%')
      .height('100%')
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
      // 获取页面参数
      const params: GlobalSearchPageParams | undefined = context.pathInfo?.param as GlobalSearchPageParams | undefined;
      if (params) {
        this.pageParams = params;
        this.handlePageParams();
      }
    })
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private buildInitialSearchLoadingState() {
    if (this.responsive_isLandscape) {
      Scroll() {
        Column({ space: 16 }) {
          ForEach(SEARCH_LOADING_GROUP_KEYS, (index: number) => {
            this.buildInitialSearchLoadingGroupCard(index, true)
          }, (index: number) => `initial_search_loading_landscape_${index}`)

          Blank().height(40 + this.navigationBarHeight)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
        .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8 })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .id('guide_global_search_content_area' as string)
      .onScrollStart(() => {
        this.onResultsScrollStart();
      })
      .onScrollStop(() => {
        this.onResultsScrollStop();
      })
    } else {
      Scroll() {
        Column({ space: 16 }) {
          ForEach(SEARCH_LOADING_GROUP_KEYS, (index: number) => {
            this.buildInitialSearchLoadingGroupCard(index, false)
          }, (index: number) => `initial_search_loading_portrait_${index}`)

          Blank().height(40 + this.navigationBarHeight)
        }
        .width('100%')
        .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8 })
      }
      .width('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .id('guide_global_search_content_area' as string)
      .onScrollStart(() => {
        this.onResultsScrollStart();
      })
      .onScrollStop(() => {
        this.onResultsScrollStop();
      })
    }
  }

  @Builder
  private buildInitialSearchLoadingGroupCard(index: number, isLandscape: boolean) {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 7 }) {
          this.buildSearchSkeletonLine(index === 0 ? 116 : 92, 18, 9, false, index)

          this.buildSearchSkeletonLine(index === 0 ? 148 : 124, 12, 6, true, index + 1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Row({ space: 6 }) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

          Text(this.getSearchLoadingText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSearchResultRowStyle().subtitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')

      this.buildSearchRefreshRail(index)

      if (isLandscape) {
        this.buildSearchGroupLoadingGrid()
      } else {
        this.buildSearchGroupLoadingStrip()
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
    .backgroundBlurStyle(
      this.getSearchResultSurfaceStyle().blurStyle,
      this.getSearchResultSurfaceStyle().blurOptions
    )
    .backgroundEffect(this.getSearchResultSurfaceStyle().backgroundEffect)
    .linearGradient(this.getSearchResultSurfaceStyle().surfaceGradient)
    .borderRadius(this.getSearchResultSurfaceStyle().radius)
    .clip(true)
    .border({
      width: this.getSearchResultSurfaceStyle().borderWidth,
      color: this.getSearchResultSurfaceStyle().borderColor
    })
    .shadow({
      radius: this.getSearchResultSurfaceStyle().radius + 4,
      color: this.getSearchResultSurfaceStyle().shadowColor,
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private buildSearchSkeletonLine(lineWidth: number, lineHeight: number, radius: number, secondary: boolean, index: number) {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [secondary ?
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme), 0.52],
            [secondary ?
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 1.0]
          ]
        })
        .opacity(secondary ? 0.72 : 0.86)

      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSearchResultSurfaceStyle().topEdgeColor)
        .opacity(0.38)

      Column()
        .width(SEARCH_SHIMMER_BLADE_WIDTH)
        .height(lineHeight + 12)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.24],
            [Color.White, 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.76],
            [Color.Transparent, 1.0]
          ]
        })
        .opacity(secondary ? 0.72 : 0.9)
        .translate({ x: this.getSearchShimmerTranslateX(lineWidth, index) })
        .animation({ duration: SEARCH_SHIMMER_INTERVAL_MS, curve: Curve.Linear })
    }
    .width(lineWidth)
    .height(lineHeight)
    .borderRadius(radius)
    .clip(true)
  }

  @Builder
  private buildSearchRefreshRail(index: number) {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .opacity(0.30)

      Column()
        .width(SEARCH_SHIMMER_BLADE_WIDTH)
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.24],
            [Color.White, 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.76],
            [Color.Transparent, 1.0]
          ]
        })
        .opacity(0.92)
        .translate({ x: this.getSearchShimmerTranslateX(320, index) })
        .animation({ duration: SEARCH_SHIMMER_INTERVAL_MS, curve: Curve.Linear })
    }
    .width('100%')
    .height(2)
    .borderRadius(2)
    .clip(true)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  private buildAnimatedItemCard(item: UnifiedSearchItem, index: number) {
    Column() {
      this.buildItemCard(item)
    }
    .width(100)
    .height(184)
    .opacity(this.resultRevealPhase)
    .translate({ y: this.getSearchItemRevealTranslateY(index) })
    .scale({
      x: this.getSearchItemRevealScale(index),
      y: this.getSearchItemRevealScale(index)
    })
    .animation({
      duration: SEARCH_RESULT_REVEAL_DURATION_MS,
      curve: Curve.EaseOut,
      delay: this.getSearchItemRevealDelay(index)
    })
    .transition(
      TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.animation({
          duration: 260,
          curve: Curve.EaseOut,
          delay: this.getSearchItemTransitionDelay(index)
        })
          .combine(TransitionEffect.translate({ y: 14 }).animation({
            duration: 260,
            curve: Curve.EaseOut,
            delay: this.getSearchItemTransitionDelay(index)
          }))
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({
            duration: 260,
            curve: Curve.EaseOut,
            delay: this.getSearchItemTransitionDelay(index)
          })),
        TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
          .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }).animation({ duration: 160, curve: Curve.EaseIn }))
      )
    )
  }

  /**
   * 构建横屏模式下的搜索结果
   */
  @Builder
  buildLandscapeResults() {
    Scroll() {
      Column({ space: 24 }) {
        ForEach(this.filteredGroups, (group: SearchSourceGroup, index: number) => {
          Column({ space: 12 }) {
            // 分组标题
            Row() {
              Text(group.groupName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(this.getSearchResultRowStyle().titleColor)
              
              Text(`(${this.getItemCountText(group)})`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.getSearchResultRowStyle().subtitleColor)
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })

            if (group.isSearching) {
              Column() {
                this.buildSearchRefreshRail(index)
              }
              .width('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
            }

            // 网格布局显示结果
            if (group.items.length > 0) {
              Grid() {
                ForEach(group.items, (item: UnifiedSearchItem, index: number) => {
                  GridItem() {
                    this.buildAnimatedItemCard(item, index)
                  }
                }, (item: UnifiedSearchItem, index: number) => this.buildSearchItemRenderKey(item, index))
              }
              .columnsTemplate(`repeat(${this.responsive_gridColumns}, 1fr)`)
              .columnsGap(12)
              .rowsGap(16)
              .width('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              .animation({ duration: SEARCH_GROUP_EXPAND_DURATION_MS, curve: Curve.EaseInOut })
              .transition(
                TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 240, curve: Curve.EaseOut }))
              )
            } else if (group.isSearching) {
              Column() {
                this.buildSearchGroupLoadingGrid()
              }
              .width('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              .transition(
                TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 220, curve: Curve.EaseOut }))
              )
            }
          }
          .width('100%')
        }, (group: SearchSourceGroup) => this.buildSearchGroupRenderKey(group))
        
        Blank().height(40 + this.navigationBarHeight)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.responsive_maxContentWidth })
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onScrollStart(() => {
      this.onResultsScrollStart();
    })
    .onScrollStop(() => {
      this.onResultsScrollStop();
    })
  }


  /**
   * 构建源分组卡片
   */
  @Builder
  buildSourceGroupCard(group: SearchSourceGroup, groupIndex: number) {
    Column({ space: 12 }) {
      // 源标题行
      Row() {
        Column({ space: 4 }) {
          Text(group.groupName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSearchResultRowStyle().titleColor)
          
          if (group.isSearching && group.items.length === 0) {
            Text('搜索中...')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSearchResultRowStyle().subtitleColor)
          } else if (group.isSearching) {
            Text(`${this.getItemCountText(group)} · 继续搜索中`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSearchResultRowStyle().subtitleColor)
          } else if (group.hasError) {
            Text('搜索失败')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          } else {
            Text(this.getItemCountText(group))
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.getSearchResultRowStyle().subtitleColor)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        // 操作按钮区域：统一使用"展开全部"/"收起"逻辑
        if (group.items.length > 10) {
          Row({ space: 4 }) {
            Text(this.expandedGroups.has(group.groupId) ? '收起' : `展开全部 (${group.items.length})`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              .rotate({ angle: this.expandedGroups.has(group.groupId) ? 180 : 0 })
              .animation({ duration: SEARCH_GROUP_EXPAND_DURATION_MS, curve: Curve.EaseInOut })
          }
          .onClick(() => {
            this.toggleGroupExpanded(group.groupId);
          })
        }
      }
      .width('100%')

      if (group.isSearching) {
        this.buildSearchRefreshRail(groupIndex)
      }

      // 搜索结果内容区域
      if (group.items.length > 0) {
        // 判断是否展开显示所有结果
        if (this.expandedGroups.has(group.groupId)) {
          // 展开模式：显示所有结果（网格布局）
          Grid() {
            ForEach(group.items, (item: UnifiedSearchItem, index: number) => {
              GridItem() {
                this.buildAnimatedItemCard(item, index)
              }
              .width(SEARCH_RESULT_ITEM_WIDTH)
              .height(SEARCH_RESULT_ITEM_HEIGHT)
            }, (item: UnifiedSearchItem, index: number) => this.buildExpandedSearchItemRenderKey(item, index))
          }
          .columnsTemplate('1fr 1fr 1fr')
          .rowsTemplate(`repeat(auto-fill, ${SEARCH_RESULT_ITEM_HEIGHT})`)
          .columnsGap(SEARCH_RESULT_EXPANDED_GRID_COLUMN_GAP)
          .rowsGap(SEARCH_RESULT_EXPANDED_GRID_ROW_GAP)
          .width('100%')
          .height(this.getExpandedSearchGridHeight(group.items.length))
          .enableScrollInteraction(false)
          .animation({ duration: SEARCH_GROUP_EXPAND_DURATION_MS, curve: Curve.EaseInOut })
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 240, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 240, curve: Curve.EaseOut }))
          )
        } else {
          // 收起模式：横向滚动显示前10个
          Scroll() {
            Row({ space: 12 }) {
              ForEach(group.items.slice(0, 10), (item: UnifiedSearchItem, index: number) => {
                this.buildAnimatedItemCard(item, index)
              }, (item: UnifiedSearchItem, index: number) => this.buildSearchItemRenderKey(item, index))
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .animation({ duration: SEARCH_GROUP_EXPAND_DURATION_MS, curve: Curve.EaseInOut })
          .transition(
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 220, curve: Curve.EaseOut }))
          )
          .onScrollStart(() => {
            this.onResultsScrollStart();
          })
          .onScrollStop(() => {
            this.onResultsScrollStop();
          })
        }
      } else if (group.isSearching) {
        this.buildSearchGroupLoadingStrip()
      } else if (group.hasError) {
        Text('搜索失败，请重试')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSearchResultRowStyle().subtitleColor)
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
      } else {
        Text('暂无结果')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSearchResultRowStyle().subtitleColor)
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
    .backgroundBlurStyle(
      this.getSearchResultSurfaceStyle().blurStyle,
      this.getSearchResultSurfaceStyle().blurOptions
    )
    .backgroundEffect(this.getSearchResultSurfaceStyle().backgroundEffect)
    .linearGradient(this.getSearchResultSurfaceStyle().surfaceGradient)
    .borderRadius(this.getSearchResultSurfaceStyle().radius)
    .clip(true)
    .border({
      width: this.getSearchResultSurfaceStyle().borderWidth,
      color: this.getSearchResultSurfaceStyle().borderColor
    })
    .shadow({
      radius: this.getSearchResultSurfaceStyle().radius + 4,
      color: this.getSearchResultSurfaceStyle().shadowColor,
      offsetX: 0,
      offsetY: 8
    })
    .animation({ duration: SEARCH_GROUP_EXPAND_DURATION_MS, curve: Curve.EaseInOut })
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 260, curve: Curve.EaseOut }))
    )
  }

  @Builder
  private buildSearchSkeletonCover() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getSearchResultSurfaceStyle().surfaceGradient)
        .opacity(0.26)

      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSearchResultSurfaceStyle().topEdgeColor)

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSearchResultSurfaceStyle().bottomEdgeColor)

      Column()
        .width(SEARCH_SHIMMER_BLADE_WIDTH)
        .height(180)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.24],
            [Color.White, 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.76],
            [Color.Transparent, 1.0]
          ]
        })
        .opacity(0.9)
        .translate({ x: this.getSearchShimmerTranslateX(100, 0) })
        .animation({ duration: SEARCH_SHIMMER_INTERVAL_MS, curve: Curve.Linear })
    }
    .width(100)
    .height(140)
    .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
    .backgroundBlurStyle(
      this.getSearchResultSurfaceStyle().blurStyle,
      this.getSearchResultSurfaceStyle().blurOptions
    )
    .backgroundEffect(this.getSearchResultSurfaceStyle().backgroundEffect)
    .borderRadius(this.getSearchResultCoverRadius())
    .clip(true)
    .border({
      width: this.getSearchResultSurfaceStyle().borderWidth,
      color: this.getSearchResultSurfaceStyle().borderColor
    })
    .shadow({
      radius: this.getSearchResultCoverRadius() + 2,
      color: this.getSearchResultSurfaceStyle().shadowColor,
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  private buildSearchItemSkeleton(index: number) {
    Column({ space: 8 }) {
      this.buildSearchSkeletonCover()

      Column({ space: 6 }) {
        this.buildSearchSkeletonLine(index % 2 === 0 ? 84 : 72, 13, 7, false, index)

        this.buildSearchSkeletonLine(index % 3 === 0 ? 58 : 46, 11, 6, true, index + 1)
      }
      .width(100)
      .height(36)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width(100)
    .height(184)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .opacity(0.9)
  }

  @Builder
  private buildSearchGroupLoadingStrip() {
    Scroll() {
      Row({ space: 12 }) {
        ForEach(SEARCH_LOADING_ITEM_KEYS, (index: number) => {
          this.buildSearchItemSkeleton(index)
        }, (index: number) => `search_loading_item_${index}`)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 220, curve: Curve.EaseOut }))
    )
  }

  @Builder
  private buildSearchGroupLoadingGrid() {
    Grid() {
      ForEach(SEARCH_LOADING_LANDSCAPE_ITEM_KEYS, (index: number) => {
        GridItem() {
          this.buildSearchItemSkeleton(index)
        }
      }, (index: number) => `search_loading_grid_item_${index}`)
    }
    .columnsTemplate(`repeat(${this.responsive_gridColumns}, 1fr)`)
    .columnsGap(12)
    .rowsGap(16)
    .width('100%')
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 220, curve: Curve.EaseOut }))
    )
  }

  /**
   * 获取搜索结果封面
   */
  private getUnifiedCoverSource(item: UnifiedSearchItem): ResourceStr {
    const coverUrl = item.coverUrl || '';

    if (coverUrl.length === 0) {
      switch (item.contentType) {
        case SearchContentType.MANGA:
          return $r('app.media.mangabook');
        case SearchContentType.EBOOK:
          return $r('app.media.ic_ebook');
        case SearchContentType.NOVEL:
          return $r('app.media.ebook');
        default:
          return $r('app.media.mangabook');
      }
    }

    if (coverUrl.startsWith('app.media.')) {
      const resourceName = coverUrl.substring('app.media.'.length);
      if (resourceName === 'mangabook') return $r('app.media.mangabook');
      if (resourceName === 'ebook') return $r('app.media.ebook');
      if (resourceName === 'ic_ebook') return $r('app.media.ic_ebook');
      if (resourceName === 'ic_novel') return $r('app.media.ebook');
      return $r('app.media.mangabook');
    }

    if (coverUrl.startsWith('/')) {
      return `file://${coverUrl}`;
    }

    return coverUrl;
  }


  /**
   * 获取搜索结果默认封面
   */
  private getDefaultCover(contentType: SearchContentType): Resource {
    switch (contentType) {
      case SearchContentType.MANGA:
        return $r('app.media.mangabook');
      case SearchContentType.EBOOK:
        return $r('app.media.ic_ebook');
      case SearchContentType.NOVEL:
        return $r('app.media.ebook');
      default:
        return $r('app.media.mangabook');
    }
  }

  @Builder
  private buildSearchResultCoverMedia(item: UnifiedSearchItem) {
    if (item.coverUrl && item.coverUrl.length > 0) {
      Image(this.getUnifiedCoverSource(item))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
        .alt(this.getDefaultCover(item.contentType))
        .opacity(this.getSearchCoverMediaOpacity(item))
        .scale({
          x: this.isSearchCoverLoaded(item) ? 1 : 1.018,
          y: this.isSearchCoverLoaded(item) ? 1 : 1.018
        })
        .animation({ duration: SEARCH_COVER_FADE_DURATION_MS, curve: Curve.EaseOut })
        .onComplete(() => {
          this.markSearchCoverLoaded(item.id);
        })
        .onError(() => {
          this.markSearchCoverLoaded(item.id);
        })
    } else if (item.contentType === SearchContentType.NOVEL) {
      Image($r('app.media.ebook'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
        .alt($r('app.media.ebook'))
    } else {
      Column() {
        Text(item.title.substring(0, 1))
          .fontSize(32)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private buildSearchCoverLoadingPlaceholder(item: UnifiedSearchItem) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

      Column()
        .width(34)
        .height(26)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .opacity(0.5)

      Column()
        .width(SEARCH_SHIMMER_BLADE_WIDTH)
        .height(180)
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [
            [Color.Transparent, 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.24],
            [Color.White, 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme), 0.76],
            [Color.Transparent, 1.0]
          ]
        })
        .opacity(0.9)
        .translate({ x: this.getSearchShimmerTranslateX(100, item.id.length) })
        .animation({ duration: SEARCH_SHIMMER_INTERVAL_MS, curve: Curve.Linear })
    }
    .width('100%')
    .height('100%')
    .opacity(this.getSearchCoverPlaceholderOpacity(item))
    .animation({ duration: SEARCH_COVER_FADE_DURATION_MS, curve: Curve.EaseOut })
  }

  @Builder
  private buildSearchResultCover(item: UnifiedSearchItem) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.shouldAnimateSearchCover(item)) {
        this.buildSearchCoverLoadingPlaceholder(item)
      }

      this.buildSearchResultCoverMedia(item)

      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getSearchResultSurfaceStyle().surfaceGradient)
        .opacity(0.34)

      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSearchResultSurfaceStyle().topEdgeColor)

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSearchResultSurfaceStyle().bottomEdgeColor)
    }
    .width(100)
    .height(140)
    .backgroundColor(this.getSearchResultSurfaceStyle().backgroundColor)
    .backgroundBlurStyle(
      this.getSearchResultSurfaceStyle().blurStyle,
      this.getSearchResultSurfaceStyle().blurOptions
    )
    .backgroundEffect(this.getSearchResultSurfaceStyle().backgroundEffect)
    .borderRadius(this.getSearchResultCoverRadius())
    .clip(true)
    .border({
      width: this.getSearchResultSurfaceStyle().borderWidth,
      color: this.getSearchResultSurfaceStyle().borderColor
    })
    .shadow({
      radius: this.getSearchResultCoverRadius() + 2,
      color: this.getSearchResultSurfaceStyle().shadowColor,
      offsetX: 0,
      offsetY: 2
    })
  }


  /**
   * 构建项目卡片（统一搜索结果）
   */
  @Builder
  buildItemCard(item: UnifiedSearchItem) {
    Column({ space: 8 }) {
      this.buildSearchResultCover(item)

      Column() {
        Text(item.title)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSearchResultRowStyle().titleColor)
          .maxLines(2)
          .lineHeight(18)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(100)
          .textAlign(TextAlign.Start)
      }
      .width(100)
      .height(36)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width(100)
    .height(184)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .onClick(() => {
      this.openDetail(item);
    })
  }


  /**
   * 构建内容类型筛选Chip
   */
  @Builder
  buildContentTypeChip(label: string, type: SearchContentType) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.contentTypeFilter === type ? 
        Color.White : 
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.contentTypeFilter === type ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({
        width: 1,
        color: this.contentTypeFilter === type ? 
          Color.Transparent : 
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .animation({ duration: 200, curve: Curve.EaseInOut })
      .onClick(() => {
        this.cancelCurrentSearch('content_filter_changed');
        this.contentTypeFilter = type;
        this.resetOnlineSourceProgressStatus();
        this.scheduleSearchPreferencesSave();
        this.updateFilteredGroups();
        this.syncSearchLoadingMotion();
      })
  }

  /**
   * 构建来源类型筛选图标Chip
   */
  @Builder
  buildSourceTypeIconChip(icon: Resource, type: SearchSourceType) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.sourceTypeFilter === type ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.sourceTypeFilter === type ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.sourceTypeFilter === type ? 
        Color.Transparent : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.cancelCurrentSearch('source_filter_changed');
      this.sourceTypeFilter = type;
      this.resetOnlineSourceProgressStatus();
      this.scheduleSearchPreferencesSave();
      this.updateFilteredGroups();
      this.syncSearchLoadingMotion();
    })
  }

  /**
   * 构建内联在线源选择器（可折叠）
   */
  @Builder
  buildInlineSourceSelector() {
    Column() {
      // 展开/收起按钮
      Row({ space: 8 }) {
        SymbolGlyph(this.showSourceExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        
        SymbolGlyph($r('sys.symbol.globe_and_keyboard'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('在线源')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        // 已选源数量/当前搜索进度标记
        Text(this.getOnlineSourceStatusText())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

        if (this.shouldShowOnlineSourceFinishedBadge()) {
          Text('搜索完成')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20')
        }
        
        Blank()
        
        // 全选/清空快捷按钮
        if (this.showSourceExpanded) {
          Row({ space: 12 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('全选')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .onClick(() => {
              this.selectAllSourcesForCurrentType();
            })
            
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text('清空')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .onClick(() => {
              this.clearAllSourcesForCurrentType();
            })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .onClick(() => {
        this.runSearchAnimation(250, Curve.EaseInOut, () => {
          this.showSourceExpanded = !this.showSourceExpanded;
        });
        this.scheduleSearchPreferencesSave();
      })

      // 展开的源选择内容
      if (this.showSourceExpanded) {
        Scroll() {
          Column({ space: 16 }) {
            // 根据内容类型显示对应的源
            if (this.shouldShowMangaSources()) {
              this.buildMangaSourcesSection()
            }
            
            if (this.shouldShowNovelSources()) {
              this.buildNovelSourcesSection()
            }
            
            // 电子书无在线源提示
            if (this.contentTypeFilter === SearchContentType.EBOOK) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                Text('电子书仅支持本地搜索')
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 16, bottom: 16 })
            }

            // 无可用源提示
            if (this.getAvailableSourcesForCurrentType() === 0 && this.contentTypeFilter !== SearchContentType.EBOOK) {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.questionmark_circle'))
                  .fontSize(32)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                Text('暂无可用的在线源')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                Text('请先添加图源或书源')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')
              .padding({ top: 20, bottom: 20 })
            }
          }
          .width('100%')
          .padding(12)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .margin({ top: 8 })
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
    .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 8 })
    .id('guide_global_search_online_sources')
  }

  /**
   * 构建源选择Chip
   */
  @Builder
  buildSourceChip(name: string, id: string, isSelected: boolean, onClick: () => void) {
    Text(name)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({
        width: 1,
        color: isSelected ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .margin({ right: 6, bottom: 6 })
      .onClick(onClick)
  }

  /**
   * 构建带置顶标记的源选择Chip
   */
  @Builder
  buildSourceChipWithPin(name: string, id: string, isSelected: boolean, isPinned: boolean, onClick: () => void) {
    Row({ space: 2 }) {
      if (isPinned) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(10)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      Text(name)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(isSelected ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
    }
    .padding({ left: isPinned ? 4 : 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(12)
    .backgroundColor(isSelected ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' : 
      (isPinned ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '10' :
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)))
    .border({
      width: 1,
      color: isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        (isPinned ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '50' :
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
    })
    .margin({ right: 6, bottom: 6 })
    .onClick(onClick)
  }

  /**
   * 获取已选源数量文本
   * 注：Suwayomi 已独立，不计入此处
   */
  private getSelectedSourcesCount(): string {
    const count = this.selectedMangaSources.length + this.selectedNovelSources.length;
    const total = this.availableMangaSources.length + this.availableNovelSources.length;
    return `${count}/${total}`;
  }

  /**
   * 全选所有源
   * 注：Suwayomi 已独立，不在此处控制
   */
  private selectAllSources(): void {
    this.resetOnlineSourceProgressStatus();
    this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
    this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
    this.scheduleSearchPreferencesSave();
  }

  /**
   * 清空所有源选择
   * 注：Suwayomi 已独立，不在此处控制
   */
  private clearAllSources(): void {
    this.resetOnlineSourceProgressStatus();
    this.selectedMangaSources = [];
    this.selectedNovelSources = [];
    this.scheduleSearchPreferencesSave();
  }

  /**
   * 判断是否应显示漫画图源
   */
  private shouldShowMangaSources(): boolean {
    return (this.contentTypeFilter === SearchContentType.ALL || 
            this.contentTypeFilter === SearchContentType.MANGA) &&
           this.availableMangaSources.length > 0;
  }

  /**
   * 判断是否应显示小说书源
   */
  private shouldShowNovelSources(): boolean {
    return (this.contentTypeFilter === SearchContentType.ALL || 
            this.contentTypeFilter === SearchContentType.NOVEL) &&
           this.availableNovelSources.length > 0;
  }

  /**
   * 获取当前类型已选源数量
   * 注：Suwayomi 已独立，不计入此处
   */
  private getSelectedSourcesCountForCurrentType(): string {
    let selected = 0;
    let total = 0;
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      selected += this.selectedMangaSources.length;
      total += this.availableMangaSources.length;
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      selected += this.selectedNovelSources.length;
      total += this.availableNovelSources.length;
    }
    
    return `${selected}/${total}`;
  }

  private resetOnlineSourceProgressStatus(): void {
    this.onlineSourceProgressCompleted = 0;
    this.onlineSourceProgressTotal = 0;
    this.onlineSourceProgressFinished = false;
    this.hasOnlineSourceProgress = false;
  }

  private prepareOnlineSourceProgressStatus(): void {
    const total: number = this.getSelectedOnlineSearchSourceCountForCurrentType();
    this.onlineSourceProgressCompleted = 0;
    this.onlineSourceProgressTotal = total;
    this.onlineSourceProgressFinished = false;
    this.hasOnlineSourceProgress = total > 0;
  }

  private updateOnlineSourceProgressStatus(groups: SearchSourceGroup[], isFinalSnapshot: boolean): void {
    let groupTotal: number = 0;
    let groupCompleted: number = 0;
    for (const group of groups) {
      if (group.sourceType === SearchSourceType.ONLINE) {
        groupTotal++;
        if (!group.isSearching) {
          groupCompleted++;
        }
      }
    }

    let total: number = Math.max(this.onlineSourceProgressTotal, groupTotal);
    if (total === 0) {
      total = this.getSelectedOnlineSearchSourceCountForCurrentType();
    }
    if (total === 0) {
      this.resetOnlineSourceProgressStatus();
      return;
    }

    const completed: number = isFinalSnapshot ? total : Math.min(groupCompleted, total);
    this.onlineSourceProgressCompleted = completed;
    this.onlineSourceProgressTotal = total;
    this.onlineSourceProgressFinished = isFinalSnapshot;
    this.hasOnlineSourceProgress = true;
  }

  private getOnlineSourceStatusText(): string {
    if (this.hasOnlineSourceProgress && this.onlineSourceProgressTotal > 0) {
      return `搜索 ${this.onlineSourceProgressCompleted}/${this.onlineSourceProgressTotal}`;
    }

    return this.getSelectedSourcesCountForCurrentType();
  }

  private shouldShowOnlineSourceFinishedBadge(): boolean {
    return this.hasOnlineSourceProgress && this.onlineSourceProgressFinished && this.onlineSourceProgressTotal > 0;
  }

  private getSelectedOnlineSearchSourceCountForCurrentType(): number {
    const effectiveSourceType: SearchSourceType = this.getEffectiveSourceTypeFilter();
    if (effectiveSourceType === SearchSourceType.LOCAL) {
      return 0;
    }

    let total: number = 0;
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      total += this.selectedMangaSources.length;
      if (this.sourceFeaturesEnabled && this.enableSuwayomi && this.isSuwayomiAvailable) {
        total += 1;
      }
    }
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      total += this.selectedNovelSources.length;
    }
    return total;
  }

  /**
   * 获取当前类型可用源数量
   * 注：Suwayomi 已独立，不计入此处
   */
  private getAvailableSourcesForCurrentType(): number {
    let total = 0;
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      total += this.availableMangaSources.length;
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      total += this.availableNovelSources.length;
    }
    
    return total;
  }

  /**
   * 根据当前类型全选
   * 注：Suwayomi 已独立，不在此处控制
   */
  private selectAllSourcesForCurrentType(): void {
    this.resetOnlineSourceProgressStatus();
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
    }
    
    this.scheduleSearchPreferencesSave();
  }

  /**
   * 根据当前类型清空
   * 注：Suwayomi 已独立，不在此处控制
   */
  private clearAllSourcesForCurrentType(): void {
    this.resetOnlineSourceProgressStatus();
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      this.selectedMangaSources = [];
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      this.selectedNovelSources = [];
    }
    
    this.scheduleSearchPreferencesSave();
  }

  /**
   * 构建漫画图源区域
   * 注：Suwayomi 已移至筛选栏作为独立开关
   */
  @Builder
  buildMangaSourcesSection() {
    Column({ space: 10 }) {
      // 标题行
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.picture'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
        
        Text('漫画图源')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(`${this.selectedMangaSources.length}/${this.availableMangaSources.length}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        // 置顶源提示
        if (this.availableMangaSources.some(s => s.isPinned)) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(`${this.availableMangaSources.filter(s => s.isPinned).length}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
      }
      .width('100%')
      
      // 图源列表
      if (this.availableMangaSources.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.availableMangaSources.slice(0, this.mangaSourceDisplayCount), (source: SourceInfo) => {
            this.buildMangaSourceChip(source)
          }, (source: SourceInfo) => `manga-${source.id}-${this.selectedMangaSources.includes(source.id.toString())}`)
        }
        .width('100%')
        
        // 显示更多/收起按钮
        if (this.availableMangaSources.length > SOURCE_DISPLAY_LIMIT) {
          Row({ space: 4 }) {
            if (this.mangaSourceDisplayCount < this.availableMangaSources.length) {
              Text(`显示更多 (${this.mangaSourceDisplayCount}/${this.availableMangaSources.length})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onClick(() => {
                  this.mangaSourceDisplayCount = Math.min(
                    this.mangaSourceDisplayCount + SOURCE_DISPLAY_STEP,
                    this.availableMangaSources.length
                  );
                })
            } else {
              Text('收起')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.mangaSourceDisplayCount = SOURCE_DISPLAY_LIMIT;
                })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8 })
        }
      } else {
        Text('暂无可用图源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .padding({ top: 8 })
      }
    }
    .width('100%')
  }

  /**
   * 构建小说书源区域
   */
  @Builder
  buildNovelSourcesSection() {
    Column({ space: 10 }) {
      // 标题行
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
        
        Text('小说书源')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(`${this.selectedNovelSources.length}/${this.availableNovelSources.length}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 书源列表
      if (this.availableNovelSources.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.availableNovelSources.slice(0, this.novelSourceDisplayCount), (source: NovelSourceInfo) => {
            this.buildNovelSourceChip(source)
          }, (source: NovelSourceInfo) => `novel-${source.id}-${this.selectedNovelSources.includes(source.id)}`)
        }
        .width('100%')
        
        // 显示更多/收起按钮
        if (this.availableNovelSources.length > SOURCE_DISPLAY_LIMIT) {
          Row({ space: 4 }) {
            if (this.novelSourceDisplayCount < this.availableNovelSources.length) {
              Text(`显示更多 (${this.novelSourceDisplayCount}/${this.availableNovelSources.length})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onClick(() => {
                  this.novelSourceDisplayCount = Math.min(
                    this.novelSourceDisplayCount + SOURCE_DISPLAY_STEP,
                    this.availableNovelSources.length
                  );
                })
            } else {
              Text('收起')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.novelSourceDisplayCount = SOURCE_DISPLAY_LIMIT;
                })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8 })
        }
      } else {
        Text('暂无可用书源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .padding({ top: 8 })
      }
    }
    .width('100%')
  }

  /**
   * 构建漫画图源Chip
   */
  @Builder
  buildMangaSourceChip(source: SourceInfo) {
    Row({ space: 4 }) {
      // 网络代理标识
      if (source.requireProxy) {
        SymbolGlyph($r('sys.symbol.globe_and_keyboard'))
          .fontSize(11)
          .fontColor([this.selectedMangaSources.includes(source.id.toString()) ? 
            Color.White :
            ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
      }
      // 置顶标识
      if (source.isPinned) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(10)
          .fontColor([this.selectedMangaSources.includes(source.id.toString()) ? 
            Color.White :
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      Text(source.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.selectedMangaSources.includes(source.id.toString()) ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: (source.requireProxy || source.isPinned) ? 6 : 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.selectedMangaSources.includes(source.id.toString()) ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.selectedMangaSources.includes(source.id.toString()) ? 
        Color.Transparent : 
        (source.isPinned ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '50' :
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
    })
    .margin({ right: 8, bottom: 8 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.toggleMangaSource(source.id.toString());
    })
  }

  /**
   * 构建小说书源Chip
   */
  @Builder
  buildNovelSourceChip(source: NovelSourceInfo) {
    Row({ space: 4 }) {
      Text(source.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.selectedNovelSources.includes(source.id) ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.selectedNovelSources.includes(source.id) ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.selectedNovelSources.includes(source.id) ? 
        Color.Transparent : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .margin({ right: 8, bottom: 8 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.toggleNovelSource(source.id);
    })
  }
}
