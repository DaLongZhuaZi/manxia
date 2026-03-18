/**
 * 图源详情页面
 * 显示图源的热门、最新、搜索等内容
 * 参考Mihon和Komikku的设计
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import { DataManager } from '../Framework/Data/DataManager';
import { MangaSourceEngine, SearchResult, EngineResult, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { MangaSourceConfig, MangaInfo, AntiCrawlerConfig, SearchTypeOption, SearchConfig } from '../Framework/WebView/MangaSourceTypes';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { TabConfig, TabType, SourceTabsConfig, getDefaultTabsConfig, filterTabsByLoginStatus, sortTabs, parseTabsFromSourceConfig, FilterConfig, FilterGroup, FilterOption } from '../Framework/WebView/TabConfig';
import { MangaDetailPageParams } from './MangaDetailPage';
import { OnlineEBookDetailPageParams } from './OnlineEBookDetailPage';
import { SourceSettingsPageParams } from './SourceSettingsPage';
import { SearchIntentParser } from '../Framework/Search/SearchIntentParser';
import { SearchIntent, SearchIntentType } from '../Framework/Search/SearchIntentTypes';
import CookieManager from '../Framework/Managers/CookieManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { image } from '@kit.ImageKit';
import { ImageCacheManager, LoadOptions, RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { AppNotificationManager } from '../Framework/Managers/NotificationManager';
import { CredentialLoginDialog } from '../Framework/Components/CredentialLoginDialog';
import { SourceCredentials } from '../Framework/Data/DataManager';
import { ProxyManager } from '../Framework/Network/ProxyManager';
import { PageSettingsHelper, DetailPageType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';
import { SourceContentCache } from '../Framework/Cache/SourceContentCache';

const TAG = 'SourceDetailPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 显示模式枚举
 */
export enum DisplayMode {
  GRID = 'grid',           // 网格模式（默认）
  LIST = 'list',           // 列表模式
  LARGE_COVER = 'large'    // 大封面模式（一行两个）
}

/**
 * 导航参数接口
 */
interface SourceDetailParams {
  sourceId: number;
  initialTab?: string;  // 初始标签ID（如 'popular', 'latest', 'search'）
  searchKeyword?: string;  // 搜索关键词（当initialTab为'search'时使用）
}

interface MangaDetailParams {
  sourceId: number;
  comicId: string;
  title: string;
}

interface DownloadTask {
  comic: ComicInfo;
  needDownload: boolean;
}

class ComicListDataSource implements IDataSource {
  private items: ComicInfo[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: ComicInfo[]) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ComicInfo {
    return this.items[index];
  }

  getItems(): ComicInfo[] {
    return this.items;
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  updateItems(items: ComicInfo[]): void {
    this.items = items;
    this.notifyDataReload();
  }

  /**
   * 在列表顶部插入新项目（用于优雅刷新）
   */
  prependItems(newItems: ComicInfo[]): void {
    if (newItems.length === 0) return;
    this.items = [...newItems, ...this.items];
    // 通知数据变化，触发UI更新
    this.listeners.forEach(listener => {
      listener.onDataAdd(0);
    });
  }

  /**
   * 更新已存在的项目信息（不改变位置）
   */
  updateExistingItems(updatedItems: Map<string, ComicInfo>): void {
    let hasChanges = false;
    this.items = this.items.map(item => {
      const updated = updatedItems.get(item.id);
      if (updated) {
        hasChanges = true;
        return updated;
      }
      return item;
    });
    if (hasChanges) {
      this.notifyDataReload();
    }
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => {
      listener.onDataReloaded();
    });
  }
}
/**
 * 题材选项接口
 */
interface ThemeOption {
  label: string;
  value: string;
}

/**
 * 筛选历史记录项
 */
interface FilterHistoryItem {
  id: string;               // 唯一标识
  filterLabel: string;      // 筛选条件的标签名称（如"同人 / 最多点击 / 全部时间"）
  results: ComicInfo[];     // 该筛选条件下的结果
  expanded: boolean;        // 是否展开
  timestamp: number;        // 创建时间
}

interface AdaptiveCoverRowItem {
  comic: ComicInfo;
  span: number;
}

interface AdaptiveCoverRow {
  key: string;
  usedSpan: number;
  items: AdaptiveCoverRowItem[];
}

@Component
export struct SourceDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State sourceInfo: SourceInfo | null = null;
  @State currentTabId: string = ''; // 当前标签ID
  @State tabsConfig: TabConfig[] = []; // 标签配置列表
  @State comicList: ComicInfo[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false; // 下拉刷新状态
  @State searchKeyword: string = '';
  @State currentPage: number = 1;
  @State hasMore: boolean = true;
  @State useWebView: boolean = false; // 是否使用WebView系统
  @State webViewReady: boolean = false; // WebView是否就绪
  @State webViewControllerAttached: boolean = false; // WebView控制器是否已附加
  @State showSearchDialog: boolean = false; // 显示搜索对话框
  @State showLoginDialog: boolean = false; // 显示登录对话框（WebView登录）
  @State showCredentialDialog: boolean = false; // 显示凭据登录对话框
  @State showCfVerifyDialog: boolean = false; // 显示Cloudflare验证对话框
  @State showWebViewDebugDialog: boolean = false; // 显示WebView调试对话框
  @State isLoggedIn: boolean = false; // 登录状态
  @State requiresCredentialLogin: boolean = false; // 是否需要凭据登录
  @State userAvatarUrl: string = ''; // 用户头像URL
  @State filterOrdering: string = '-datetime_updated'; // 筛选排序
  @State filterRegion: string = ''; // 筛选地区（空字符串表示全部）
  @State filterTheme: string = ''; // 筛选题材（空字符串表示全部）
  @State sourceFilterConfig: FilterConfig | null = null; // 图源筛选配置
  @State dynamicFilterValues: Map<string, string> = new Map(); // 动态筛选值（支持不同图源的不同筛选组）
  @State searchResults: ComicInfo[] = []; // 搜索结果（独立存储）
  @State lastSearchKeyword: string = ''; // 上次搜索的关键词
  @State searchTabVisible: boolean = false; // 搜索标签是否可见
  @State showAmbiguousDialog: boolean = false; // 纯数字歧义选择对话框
  @State ambiguousId: string = ''; // 待确认的ID
  @State searchTypes: SearchTypeOption[] = []; // 搜索类型列表
  @State selectedSearchType: string = 'search'; // 当前选中的搜索类型
  @State searchPlaceholder: string = '搜索漫画名称、粘贴URL、或输入 id:作品ID'; // 搜索框占位符
  @State sourceUserAgent: string = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'; // 图源UA配置
  
  // 显示模式相关状态
  @State displayMode: DisplayMode = DisplayMode.GRID; // 当前显示模式
  @State showDisplayModeMenu: boolean = false; // 显示模式选择菜单
  @State tabDisplayModes: Map<string, DisplayMode> = new Map(); // 每个标签的显示模式
  
  // 首次加载标记（用于控制空状态显示）
  @State hasLoadedOnce: boolean = false;
  @State comicContentRenderVersion: number = 0;
  
  // 筛选历史记录（可折叠显示上次筛选结果）
  @State filterHistory: FilterHistoryItem[] = []; // 筛选历史列表
  private readonly MAX_FILTER_HISTORY: number = 5; // 最多保留的历史记录数
  private pendingFilterHistory: ComicInfo[] = []; // 等待保存到历史的旧数据
  private pendingFilterLabel: string = ''; // 等待保存的筛选标签
  private isDeleteButtonClicked: boolean = false; // 防止删除按钮事件冒泡的标志
  
  // 横向滑动切换标签页相关状态
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;
  
  // 优雅刷新相关状态
  @State private refreshHintVisible: boolean = false; // 刷新提示是否可见
  @State private refreshHintMessage: string = ''; // 刷新提示消息
  @State private refreshHintType: 'success' | 'info' | 'error' | 'loading' = 'info'; // 刷新提示类型
  @State private refreshHintOpacity: number = 0; // 刷新提示透明度（用于动画）

  private sourceId: number = 0;
  private sourceName: string = '';
  private sourceManager: SourceManager = SourceManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private contentCache: SourceContentCache = SourceContentCache.getInstance();
  private componentId: string = `SourceDetailPage_${Date.now()}`;
  private scroller: Scroller = new Scroller();
  @State comicDataSource: ComicListDataSource = new ComicListDataSource([]);
  @State private coverPixelMaps: Map<string, image.PixelMap> = new Map();
  @State private coverAspectRatios: Map<string, number> = new Map();
  
  // 设备方向检测
  @State private isLandscape: boolean = false;
  @State private screenHeight: number = 0;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  
  // WebView相关
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private loginWebViewController: webview.WebviewController = new webview.WebviewController();
  private mangaSourceEngine: MangaSourceEngine | null = null;
  private webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  private loginUrl: string = '';

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    
    // 初始化主题状态
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
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 获取路由参数 - 从NavPathStack获取
    const params: ESObject[] = this.pathStack.getParamByName('SourceDetailPage') as ESObject[];
    if (params && params.length > 0) {
      const param: ESObject = params[0] as ESObject;
      if (param && param.sourceId) {
        this.sourceId = param.sourceId as number;
        logger.info(TAG, `加载图源详情，ID: ${this.sourceId}`);
        
        // 保存初始标签和搜索关键词参数
        const initialTab = param.initialTab as string | undefined;
        const searchKeyword = param.searchKeyword as string | undefined;
        const searchType = param.searchType as string | undefined;
        const fromGlobalSearch = param.fromGlobalSearch as boolean | undefined;  // 是否来自全局搜索
        
        // 异步初始化
        this.initializeAsyncWithParams(initialTab, searchKeyword, searchType, fromGlobalSearch);
      }
    }
    
    // 注册设备方向监听器
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      this.isLandscape = deviceInfo.isLandscape;
      this.screenHeight = deviceInfo.screenHeight;
      logger.info(TAG, `设备方向变化: ${this.isLandscape ? '横屏' : '竖屏'}, 屏幕高度: ${this.screenHeight}`);
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);
  }

  /**
   * 异步初始化（无参数版本，向后兼容）
   */
  private async initializeAsync(): Promise<void> {
    await this.initializeAsyncWithParams(undefined, undefined, undefined, undefined);
  }

  /**
   * 异步初始化（带参数版本）
   * @param fromGlobalSearch 是否来自全局搜索，如果是则优先使用缓存结果
   */
  private async initializeAsyncWithParams(initialTab?: string, searchKeyword?: string, searchType?: string, fromGlobalSearch?: boolean): Promise<void> {
    try {
      // 首先加载 sourceName（用于页面跳转参数传递）
      await this.loadSourceName();
      
      // 加载图源信息
      await this.loadSourceInfo();
      
      // 检查图源是否需要代理，如果需要则确保代理已应用
      if (this.sourceInfo?.requireProxy) {
        const proxyManager = ProxyManager.getInstance();
        await proxyManager.initialize();
        if (proxyManager.isEnabled()) {
          logger.info(TAG, `图源 ${this.sourceInfo.name} 需要代理，代理已启用`);
        } else {
          logger.warn(TAG, `图源 ${this.sourceInfo.name} 需要代理，但代理未启用`);
        }
      }
      
      // 检测图源类型并初始化相应系统
      await this.detectAndInitializeSourceType();
      
      // 检查是否需要凭据登录
      await this.checkCredentialLogin();
      
      // 如果需要凭据登录但未登录，显示登录对话框并返回
      if (this.requiresCredentialLogin && !this.isLoggedIn) {
        logger.info(TAG, '需要凭据登录，显示登录对话框');
        this.showCredentialDialog = true;
        return;
      }
      
      // 如果使用WebView，等待控制器附加
      if (this.useWebView) {
        logger.info(TAG, '等待WebView控制器附加...');
        await this.waitForWebViewReady();
        await this.loadBaseUrlAndCookieBootstrap();
      }
      
      // 加载标签显示模式设置
      await this.loadAllTabDisplayModes();
      
      // 加载标签页配置
      await this.loadTabsConfig();
      
      // 处理初始标签参数
      if (initialTab) {
        // 如果是搜索标签且有关键词，先设置关键词再执行搜索
        if (initialTab === 'search' && searchKeyword) {
          this.searchKeyword = searchKeyword;
          // 如果传入了搜索类型，设置选中的搜索类型
          if (searchType) {
            this.selectedSearchType = searchType;
            const typeConfig = this.searchTypes.find((t: SearchTypeOption) => t.id === searchType);
            if (typeConfig) {
              this.searchPlaceholder = typeConfig.placeholder || '输入搜索内容';
            }
            logger.info(TAG, `初始化搜索标签，类型: ${searchType}, 关键词: ${searchKeyword}`);
          } else {
            logger.info(TAG, `初始化搜索标签，关键词: ${searchKeyword}`);
          }
          this.addOrUpdateSearchTab();
          this.currentTabId = 'search';
          this.loadTabDisplayMode('search');
        } else {
          // 切换到指定标签
          const targetTab = this.tabsConfig.find(t => t.id === initialTab);
          if (targetTab) {
            this.currentTabId = initialTab;
            this.loadTabDisplayMode(initialTab);
            logger.info(TAG, `初始化切换到标签: ${initialTab}`);
          }
        }
      }
      
      // 加载筛选设置（使用动态筛选加载，同时加载旧版筛选）
      await this.loadDynamicFilterSettings();
      
      // 加载漫画列表（如果是搜索标签，执行搜索）
      if (this.currentTabId === 'search' && searchKeyword) {
        // 【关键】如果来自全局搜索，尝试使用缓存结果
        if (fromGlobalSearch && this.tryLoadFromGlobalSearchCache(searchKeyword)) {
          logger.info(TAG, '使用全局搜索缓存结果');
        } else {
          await this.performSearch();
        }
      } else {
        await this.loadComics();
      }
    } catch (error) {
      logger.error(TAG, '初始化失败', String(error));
    }
  }

  private lifecycle = new PageLifecycleManager('SourceDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 清理设备方向监听器
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
      logger.debug(TAG, '设备方向监听器已清理');
    }
  }

  /**
   * 加载 sourceName
   */
  private async loadSourceName(): Promise<void> {
    try {
      logger.info(TAG, `开始加载 sourceName, sourceId=${this.sourceId}`);
      const sourceRecord = await this.dataManager.getComicSourceById(this.sourceId);
      logger.info(TAG, `查询到 sourceRecord: ${sourceRecord ? JSON.stringify(sourceRecord) : 'null'}`);
      if (sourceRecord && sourceRecord.name) {
        this.sourceName = sourceRecord.name as string;
        logger.info(TAG, `成功加载 sourceName: ${this.sourceName}`);
      } else {
        logger.warn(TAG, `sourceRecord 不存在或缺少 name 字段`);
      }
    } catch (error) {
      logger.error(TAG, '加载 sourceName 失败', String(error));
    }
  }

  /**
   * 加载图源信息
   */
  private async loadSourceInfo(): Promise<void> {
    try {
      const sources = await this.sourceManager.getAllSources();
      this.sourceInfo = sources.find((s: SourceInfo) => s.id === this.sourceId) || null;
    } catch (error) {
      logger.error(TAG, '加载图源信息失败', String(error));
    }
  }
  
  /**
   * 尝试从全局搜索缓存加载结果
   * @param keyword 搜索关键词
   * @returns 是否成功加载
   */
  private tryLoadFromGlobalSearchCache(keyword: string): boolean {
    try {
      const cacheKey = `global_search_cache_${this.sourceId}`;
      const cacheStr = AppStorage.get<string>(cacheKey);
      
      if (!cacheStr) {
        logger.info(TAG, `未找到全局搜索缓存: ${cacheKey}`);
        return false;
      }
      
      interface CachedComicInfo {
        id: string;
        title: string;
        author: string;
        coverUrl: string;
        description: string;
        url: string;
        status: string;
      }
      interface SearchCacheData {
        keyword: string;
        results: CachedComicInfo[];
        timestamp: number;
      }
      
      const cacheData: SearchCacheData = JSON.parse(cacheStr) as SearchCacheData;
      
      // 检查关键词是否匹配
      if (cacheData.keyword !== keyword) {
        logger.info(TAG, `缓存关键词不匹配: 缓存="${cacheData.keyword}", 当前="${keyword}"`);
        return false;
      }
      
      // 检查缓存是否过期（5分钟）
      const cacheAge = Date.now() - cacheData.timestamp;
      if (cacheAge > 5 * 60 * 1000) {
        logger.info(TAG, `全局搜索缓存已过期: ${cacheAge}ms`);
        AppStorage.delete(cacheKey);
        return false;
      }
      
      // 转换为 ComicInfo 格式
      const comics: ComicInfo[] = cacheData.results.map((item: CachedComicInfo): ComicInfo => ({
        id: item.id,
        title: item.title,
        author: item.author,
        coverUrl: item.coverUrl,
        description: item.description,
        url: item.url,
        status: item.status
      }));
      
      // 更新 UI
      this.searchResults = comics;
      this.comicList = [...comics];
      this.comicDataSource.updateItems([...this.comicList]);
      this.touchComicContentRender();
      this.hasMore = false;  // 全局搜索缓存不支持分页
      this.lastSearchKeyword = keyword;
      
      logger.info(TAG, `成功加载全局搜索缓存: ${comics.length} 条结果`);
      
      // 清除缓存（一次性使用）
      AppStorage.delete(cacheKey);
      
      return true;
    } catch (error) {
      logger.error(TAG, `加载全局搜索缓存失败: ${error}`);
      return false;
    }
  }

  /**
   * 加载漫画列表（带缓存支持）
   */
  private touchComicContentRender(): void {
    this.comicContentRenderVersion = this.comicContentRenderVersion + 1;
  }

  private async loadComics(): Promise<void> {
    if (this.isLoading) return;

    try {
      this.isLoading = true;
      
      // 生成缓存键
      const workflowKey = this.generateWorkflowKey();
      
      // 1. 优先从缓存加载（仅第一页）
      if (this.currentPage === 1) {
        const cached = this.contentCache.get(this.sourceId, workflowKey);
        if (cached) {
          logger.info(TAG, `从缓存加载数据: ${cached.comics.length} 条`);
          this.comicList = [...cached.comics];
          this.hasMore = cached.hasMore;
          this.comicDataSource.updateItems([...this.comicList]);
          this.touchComicContentRender();
          
          // 检查是否需要刷新
          if (!this.contentCache.needsRefresh(this.sourceId, workflowKey)) {
            this.isLoading = false;
            return;
          }
          
          logger.info(TAG, '缓存数据已显示，后台刷新中...');
        }
      }
      
      // 2. 从网络加载
      let comics: ComicInfo[] = [];
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        logger.info(TAG, '使用WebView系统加载漫画列表');
        comics = await this.loadComicsWithWebView();
      } else {
        logger.info(TAG, '使用HTTP系统加载漫画列表');
        comics = await this.loadComicsWithHTTP();
      }

      // 3. 更新缓存（不缓存空结果，避免加载失败后重试无效）
      if (this.currentPage === 1 && comics.length > 0) {
        this.contentCache.set(
          this.sourceId,
          this.currentTabId,
          workflowKey,
          comics,
          this.currentPage,
          comics.length >= 20
        );
      } else if (this.currentPage > 1) {
        this.contentCache.append(
          this.sourceId,
          workflowKey,
          comics,
          this.currentPage,
          comics.length >= 20
        );
      }

      // 4. 处理筛选历史（新数据加载完成后，把旧数据折叠到历史）
      if (this.currentPage === 1 && this.pendingFilterHistory.length > 0 && comics.length > 0) {
        this.saveToFilterHistory(this.pendingFilterHistory, this.pendingFilterLabel);
        this.pendingFilterHistory = [];
        this.pendingFilterLabel = '';
      }

      // 5. 更新UI
      if (this.currentPage === 1) {
        this.comicList = [...comics];
      } else {
        this.comicList = [...this.comicList, ...comics];
      }

      // 后台异步处理封面缓存（不阻塞 UI）
      this.processCoverCacheAsync(comics);
      this.hasMore = comics.length >= 20;
      this.comicDataSource.updateItems([...this.comicList]);
      this.touchComicContentRender();
      logger.info(TAG, `数据源已刷新: ${this.comicList.length} 条数据`);

    } catch (error) {
      logger.error(TAG, '加载漫画列表失败', String(error));
    } finally {
      this.isLoading = false;
      // 标记首次加载已完成
      if (!this.hasLoadedOnce) {
        this.hasLoadedOnce = true;
      }
    }
  }

  /**
   * 生成工作流缓存键
   * 注意：缓存键需要包含所有影响结果的参数，包括动态筛选参数
   */
  private generateWorkflowKey(): string {
    const tab = this.currentTabId;
    
    // 根据不同标签生成不同的缓存键
    if (tab === 'search') {
      return `search:${this.searchKeyword}:${this.selectedSearchType}`;
    } else if (tab === 'filter') {
      // 筛选标签需要包含所有动态筛选参数
      const filterParts: string[] = ['filter'];
      const groups = this.getDynamicFilterGroups();
      for (const group of groups) {
        const value = this.dynamicFilterValues.get(group.id) || group.defaultValue || '';
        filterParts.push(`${group.id}=${value}`);
      }
      return filterParts.join(':');
    } else if (tab === 'leaderboard') {
      // 排行榜标签需要包含 timeType 参数
      const groups = this.getDynamicFilterGroups();
      const timeTypeGroup = groups.find(g => g.id === 'timeType');
      const timeType = this.dynamicFilterValues.get('timeType') || (timeTypeGroup?.defaultValue) || 'a';
      return `leaderboard:timeType=${timeType}`;
    } else {
      return tab; // popular, latest, favorites等
    }
  }

  /**
   * 异步处理封面缓存（不阻塞UI）
   */
  private processCoverCacheAsync(comics: ComicInfo[]): void {
    // 使用Promise立即返回，后台执行
    this.processCoverCacheBackground(comics).catch((error: Error) => {
      logger.error(TAG, '后台封面缓存处理失败', String(error));
    });
  }

  /**
   * 后台处理封面缓存
   */
  private async processCoverCacheBackground(comics: ComicInfo[]): Promise<void> {
    try {
      const coverCache = CoverCacheManager.getInstance();
      const networkHeaders = this.buildCoverHeaders();
      
      // 转换RequestHeaders为Record<string, string>
      const headers: Record<string, string> = {
        'User-Agent': networkHeaders.userAgent || '',
        'Accept': networkHeaders.accept || '',
        'Referer': networkHeaders.referer || '',
        'Accept-Language': networkHeaders.acceptLanguage || '',
        'Sec-Fetch-Dest': networkHeaders.secFetchDest || '',
        'Sec-Fetch-Mode': networkHeaders.secFetchMode || '',
        'Sec-Fetch-Site': networkHeaders.secFetchSite || ''
      };

      // 过滤有封面URL的漫画
      const validComics = comics.filter(c => c.coverUrl);
      
      // 批量保存漫画信息（减少数据库操作）
      const savePromises = validComics.map((comic: ComicInfo) => {
        const coverUrl: string = comic.coverUrl || '';
        return coverCache.saveTempManga(
          this.sourceId,
          comic.id,
          comic.title,
          coverUrl
        ).catch((e: Error) => {
          logger.warn(TAG, `保存漫画 ${comic.title} 信息失败: ${e}`);
        });
      });

      // 等待保存完成
      await Promise.all(savePromises);

      // 批量查询本地缓存路径
      const externalIds = validComics.map(c => c.id);
      const localPathsMap = await coverCache.getBatchLocalCoverPaths(
        this.sourceId,
        externalIds
      );

      // 筛选需要下载的漫画
      const needDownload = validComics.filter(comic => !localPathsMap.get(comic.id));
      const cachedCount = validComics.length - needDownload.length;

      logger.info(TAG, `封面缓存状态: ${cachedCount}/${validComics.length} 已缓存，后台下载 ${needDownload.length} 个`);

      if (needDownload.length === 0) {
        return;
      }

      // 【修复】提高并发数到10，加快封面下载速度
      const MAX_CONCURRENT = 10;
      let downloadedCount = 0;
      
      // 【修复】并行下载，不等待批次完成
      const allPromises: Promise<void>[] = [];
      
      for (let i = 0; i < needDownload.length; i++) {
        const comic = needDownload[i];
        const coverUrl: string = comic.coverUrl || '';
        
        // 控制并发：每10个一批
        if (i > 0 && i % MAX_CONCURRENT === 0) {
          // 等待前一批完成，避免同时发起过多请求
          await Promise.allSettled(allPromises.splice(0, MAX_CONCURRENT));
        }
        
        const downloadPromise = coverCache.downloadAndCacheCover(
          this.sourceId,
          comic.id,
          coverUrl,
          headers
        ).then((savedPath: string | null) => {
          if (savedPath) {
            downloadedCount++;
            logger.debug(TAG, `后台封面下载完成 (${downloadedCount}/${needDownload.length}): ${comic.title}`);
            // 下载完成后，刷新对应的封面显示
            this.refreshCoverDisplay(comic);
          }
        }).catch((error: Error) => {
          logger.debug(TAG, `后台封面下载失败 ${comic.title}: ${String(error)}`);
        });
        
        allPromises.push(downloadPromise);
      }
      
      // 等待所有剩余的下载完成
      await Promise.allSettled(allPromises);

      logger.info(TAG, `封面后台下载完成: 成功 ${downloadedCount}/${needDownload.length} 个`);
    } catch (error) {
      logger.error(TAG, '后台封面缓存处理失败', String(error));
    }
  }

  /**
   * 刷新单个封面显示（下载完成后调用）
   */
  private async refreshCoverDisplay(comic: ComicInfo): Promise<void> {
    try {
      const coverCache = CoverCacheManager.getInstance();
      const localPath = await coverCache.getLocalCoverPath(this.sourceId, comic.id);
      
      if (localPath) {
        const imageSource = image.createImageSource(localPath);
        await this.updateCoverAspectRatioFromImageSource(comic.id, imageSource);
        const pm = await this.createCoverThumbnailPixelMap(imageSource);
        const newMap: Map<string, image.PixelMap> = new Map(this.coverPixelMaps);
        newMap.set(comic.id, pm);
        this.coverPixelMaps = newMap;
      }
    } catch (e) {
      logger.warn(TAG, `刷新封面显示失败: ${e}`);
    }
  }

  /**
   * 等待WebView准备就绪
   */
  private async waitForWebViewReady(): Promise<void> {
    const maxWaitTime = 5000;
    const checkInterval = 100;
    let waited = 0;
    
    while (!this.webViewControllerAttached && waited < maxWaitTime) {
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      waited += checkInterval;
    }
    
    if (this.webViewControllerAttached) {
      logger.info(TAG, `WebView已就绪，等待时间: ${waited}ms`);
    } else {
      logger.warn(TAG, `WebView等待超时(${maxWaitTime}ms)，继续执行`);
    }
  }

  /**
   * 检测图源类型并初始化
   */
  private async detectAndInitializeSourceType(): Promise<void> {
    try {
      const config: ESObject | null = await this.dataManager.getSourceConfig(this.sourceId);
      
      if (!config) {
        logger.warn(TAG, '图源配置为空，使用HTTP系统');
        this.useWebView = false;
        return;
      }

      const hasWorkflows: boolean = !!config.workflows;
      
      if (hasWorkflows) {
        logger.info(TAG, '检测到WebView类型图源（包含workflows字段），初始化WebView系统');
        this.useWebView = true;
        await this.initializeWebViewEngine(config);
      } else {
        logger.info(TAG, '使用HTTP类型图源');
        this.useWebView = false;
      }
    } catch (error) {
      logger.error(TAG, '检测图源类型失败，降级到HTTP系统', String(error));
      this.useWebView = false;
    }
  }

  /**
   * 检查是否需要凭据登录
   */
  private async checkCredentialLogin(): Promise<void> {
    try {
      const config: ESObject | null = await this.dataManager.getSourceConfig(this.sourceId);
      
      if (!config) {
        this.requiresCredentialLogin = false;
        return;
      }

      // 检查capabilities中是否声明了credentialLogin
      const capabilities: ESObject = config.capabilities as ESObject || {};
      this.requiresCredentialLogin = capabilities['credentialLogin'] === true;
      
      if (!this.requiresCredentialLogin) {
        logger.info(TAG, '图源不需要凭据登录');
        this.isLoggedIn = true;
        return;
      }
      
      logger.info(TAG, '图源需要凭据登录，检查已保存的凭据');
      
      // 检查是否已有保存的凭据
      const credentials: SourceCredentials | null = await this.dataManager.getSourceCredentials(this.sourceId);
      
      if (credentials && credentials.username && credentials.password) {
        logger.info(TAG, `找到已保存的凭据: ${credentials.username}`);
        
        // [修复] 对于需要JWT Token的图源，需要检查是否有有效的Token
        // 如果没有Token，需要执行登录工作流获取Token
        if (this.useWebView && this.mangaSourceEngine) {
          const config: ESObject | null = await this.dataManager.getSourceConfig(this.sourceId);
          const authentication: ESObject | undefined = config?.authentication as ESObject | undefined;
          
          if (authentication && authentication['type'] === 'jwt') {
            logger.info(TAG, '图源使用JWT认证，检查是否需要执行登录获取Token');
            
            // 尝试执行登录工作流获取Token
            try {
              const loginResult = await this.mangaSourceEngine.executeLogin(
                credentials.username, 
                credentials.password
              );
              if (loginResult.success && loginResult.data) {
                logger.info(TAG, `自动登录成功，获取到token: ${loginResult.data.substring(0, 20)}...`);
              } else {
                logger.warn(TAG, '自动登录工作流执行成功但未获取到token');
              }
            } catch (loginError) {
              logger.error(TAG, '自动登录工作流执行失败', String(loginError));
              // 登录失败不阻止继续，可能Token仍然有效
            }
          }
        }
        
        this.isLoggedIn = true;
      } else {
        logger.info(TAG, '未找到已保存的凭据');
        this.isLoggedIn = false;
      }
    } catch (error) {
      logger.error(TAG, '检查凭据登录失败', String(error));
      this.requiresCredentialLogin = false;
      this.isLoggedIn = true;
    }
  }

  /**
   * 处理凭据登录
   */
  private async handleCredentialLogin(username: string, password: string): Promise<void> {
    try {
      logger.info(TAG, `处理凭据登录: ${username}`);
      
      // 保存凭据到数据库
      await this.dataManager.saveSourceCredentials(this.sourceId, username, password);
      logger.info(TAG, '凭据已保存');
      
      // 如果图源支持login工作流，执行登录获取token
      if (this.useWebView && this.mangaSourceEngine) {
        logger.info(TAG, '执行login工作流获取token');
        try {
          const loginResult = await this.mangaSourceEngine.executeLogin(username, password);
          if (loginResult.success && loginResult.data) {
            logger.info(TAG, `登录成功，获取到token: ${loginResult.data.substring(0, 20)}...`);
            // Token已经通过saveAs保存到数据库
          } else {
            logger.warn(TAG, '登录工作流执行成功但未获取到token');
          }
        } catch (loginError) {
          logger.error(TAG, 'login工作流执行失败', String(loginError));
          // 不抛出错误，继续流程
        }
      }
      
      // 更新登录状态
      this.isLoggedIn = true;
      
      // 关闭登录对话框
      this.showCredentialDialog = false;
      
      // 提示用户
      this.getUIContext().getPromptAction().showToast({ 
        message: '登录成功，凭据已保存' 
      });
      
      // 继续初始化流程
      await this.continueInitializationAfterLogin();
    } catch (error) {
      logger.error(TAG, '凭据登录失败', String(error));
      this.getUIContext().getPromptAction().showToast({ 
        message: '登录失败，请重试' 
      });
    }
  }

  /**
   * 登录后继续初始化
   */
  private async continueInitializationAfterLogin(): Promise<void> {
    try {
      // 如果使用WebView，等待控制器附加
      if (this.useWebView) {
        logger.info(TAG, '等待WebView控制器附加...');
        await this.waitForWebViewReady();
        await this.loadBaseUrlAndCookieBootstrap();
      }
      
      // 加载标签页配置
      await this.loadTabsConfig();
      
      // 加载筛选设置（使用动态筛选加载）
      await this.loadDynamicFilterSettings();
      
      // 加载漫画列表
      await this.loadComics();
    } catch (error) {
      logger.error(TAG, '登录后初始化失败', String(error));
    }
  }

  /**
   * 初始化WebView引擎
   */
  private async initializeWebViewEngine(config: ESObject): Promise<void> {
    try {
      logger.info(TAG, '开始初始化WebView引擎');
      
      this.webViewSourceManager.setGlobalWebViewController(this.webViewController);
      
      const antiCrawlerConfig: AntiCrawlerConfig = {
        cloudflare: {
          enabled: true,
          bypassMethod: 'wait'
        },
        captcha: {
          enabled: true,
          autoSolve: false
        },
        ipBlock: {
          enabled: true,
          delay: 3000
        }
      };
      
      const engineConfig: EngineConfig = {
        webViewController: this.webViewController,
        antiCrawlerConfig: antiCrawlerConfig,
        debug: true,
        timeout: 30000,
        caseSensitive: false,
        sourceId: this.sourceId
      };
      
      this.mangaSourceEngine = new MangaSourceEngine(engineConfig);
      
      // 设置CF验证回调，当需要用户交互时显示验证对话框
      this.mangaSourceEngine.setOnNeedCfVerify(() => {
        logger.info(TAG, '收到CF验证回调，显示验证对话框');
        this.showCfVerifyDialog = true;
      });
      
      const configJson = JSON.stringify(config);
      await this.mangaSourceEngine.loadConfig(configJson);
      
      // 从配置中读取UserAgent
      this.initUserAgentFromConfig(config);
      
      // 初始化搜索类型配置
      this.initSearchTypes(config);
      
      this.webViewReady = true;
      logger.info(TAG, 'WebView引擎初始化成功');
    } catch (error) {
      logger.error(TAG, 'WebView引擎初始化失败', String(error));
      this.useWebView = false;
      this.webViewReady = false;
    }
  }

  /**
   * 从配置中初始化UserAgent
   */
  private initUserAgentFromConfig(config: ESObject): void {
    // 默认移动端UA
    const defaultMobileUA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
    
    // 尝试从 network.userAgent 读取
    const network = config.network as Record<string, string> | undefined;
    if (network && network.userAgent && network.userAgent.length > 0) {
      this.sourceUserAgent = network.userAgent;
      logger.info(TAG, `使用图源配置的UserAgent: ${this.sourceUserAgent.substring(0, 50)}...`);
      return;
    }
    
    // 尝试从 settings.userAgent 读取（兼容旧格式）
    const settings = config.settings as Record<string, string> | undefined;
    if (settings && settings.userAgent && settings.userAgent.length > 0) {
      this.sourceUserAgent = settings.userAgent;
      logger.info(TAG, `使用图源settings的UserAgent: ${this.sourceUserAgent.substring(0, 50)}...`);
      return;
    }
    
    // 使用默认UA
    this.sourceUserAgent = defaultMobileUA;
    logger.info(TAG, '使用默认移动端UserAgent');
  }

  /**
   * 初始化搜索类型配置
   */
  private initSearchTypes(config: ESObject): void {
    // 默认搜索类型
    const defaultTypes: SearchTypeOption[] = [
      { id: 'search', label: '关键词', placeholder: '输入漫画名称或标签', isDefault: true }
    ];

    // 从配置中读取搜索类型
    const searchConfig: SearchConfig | undefined = config.searchConfig as SearchConfig | undefined;
    if (searchConfig && searchConfig.types && Array.isArray(searchConfig.types)) {
      const configTypes: SearchTypeOption[] = searchConfig.types;
      if (configTypes.length > 0) {
        this.searchTypes = configTypes;
        // 找到默认类型
        const defaultType = configTypes.find((t: SearchTypeOption) => t.isDefault);
        if (defaultType) {
          this.selectedSearchType = defaultType.id;
          this.searchPlaceholder = defaultType.placeholder || '输入搜索内容';
        } else {
          this.selectedSearchType = configTypes[0].id;
          this.searchPlaceholder = configTypes[0].placeholder || '输入搜索内容';
        }
        logger.info(TAG, `加载了 ${configTypes.length} 个搜索类型: ${configTypes.map((t: SearchTypeOption) => t.label).join(', ')}`);
        return;
      }
    }

    // 使用默认配置
    this.searchTypes = defaultTypes;
    this.selectedSearchType = 'search';
    this.searchPlaceholder = defaultTypes[0].placeholder || '输入搜索内容';
    logger.info(TAG, '使用默认搜索类型配置');
  }

  private async loadBaseUrlAndCookieBootstrap(): Promise<void> {
    try {
      const rec: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(this.sourceId);
      let baseUrl: string = '';
      if (rec) { baseUrl = rec.baseUrl; }
      if (!this.webViewControllerAttached) {
        logger.warn(TAG, 'WebView控制器未附加，无法预加载BaseUrl');
        return;
      }
      if (!baseUrl || baseUrl.length === 0) {
        logger.warn(TAG, 'BaseUrl为空，跳过预加载');
        return;
      }
      this.webViewController.loadUrl(baseUrl);
      logger.info(TAG, `WebView已预加载图源站点: ${baseUrl}`);
      setTimeout(async () => {
        try {
          const ok: boolean = await CookieManager.getInstance().refreshCookiesIfNeeded(this.sourceId, this.webViewController, baseUrl);
          logger.debug(TAG, `预加载后Cookie刷新结果: ${ok}`);
        } catch (e) {
          const msg: string = e instanceof Error ? e.message : String(e);
          logger.warn(TAG, `预加载后Cookie刷新失败: ${msg}`);
        }
      }, 800);
    } catch (error) {
      logger.warn(TAG, `预加载BaseUrl失败: ${String(error)}`);
    }
  }

  private buildCoverHeaders(): RequestHeaders {
    const baseUrl: string = (this.sourceInfo && (this.sourceInfo as SourceInfo).baseUrl && String((this.sourceInfo as SourceInfo).baseUrl).length > 0) ? String((this.sourceInfo as SourceInfo).baseUrl) : 'https://komiic.com';
    const base: RequestHeaders = {} as RequestHeaders;
    base.userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    base.accept = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
    base.referer = baseUrl;
    base.acceptLanguage = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
    base.secFetchDest = 'image';
    base.secFetchMode = 'no-cors';
    base.secFetchSite = 'same-origin';
    return base;
  }

  private updateCoverAspectRatio(comicId: string, width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const ratio = width / height;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      return;
    }
    const newMap: Map<string, number> = new Map(this.coverAspectRatios);
    newMap.set(comicId, ratio);
    this.coverAspectRatios = newMap;
  }

  private async updateCoverAspectRatioFromImageSource(comicId: string, imageSource: image.ImageSource): Promise<void> {
    try {
      const imageInfo = await imageSource.getImageInfo();
      this.updateCoverAspectRatio(comicId, imageInfo.size.width, imageInfo.size.height);
    } catch (_e) {}
  }

  private async updateCoverAspectRatioFromPixelMap(comicId: string, pixelMap: image.PixelMap): Promise<void> {
    try {
      const imageInfo = await pixelMap.getImageInfo();
      this.updateCoverAspectRatio(comicId, imageInfo.size.width, imageInfo.size.height);
    } catch (_e) {}
  }

  private async createCoverThumbnailPixelMap(imageSource: image.ImageSource): Promise<image.PixelMap> {
    try {
      const imageInfo = await imageSource.getImageInfo();
      const maxEdge = Math.max(imageInfo.size.width, imageInfo.size.height);
      const targetMaxEdge = 360;
      if (maxEdge > targetMaxEdge) {
        const ratio = Math.ceil(maxEdge / targetMaxEdge);
        let sampleSize = 1;
        while (sampleSize * 2 <= ratio) {
          sampleSize *= 2;
        }
        return await imageSource.createPixelMap({
          sampleSize: sampleSize,
          editable: false
        });
      }
    } catch (_e) {}
    return await imageSource.createPixelMap();
  }

  private getComicCoverAspectRatio(comic: ComicInfo): number {
    const ratio = this.coverAspectRatios.get(comic.id);
    if (ratio && Number.isFinite(ratio) && ratio > 0) {
      return ratio;
    }
    return 0.7;
  }

  private isLandscapeCover(comic: ComicInfo): boolean {
    return this.getComicCoverAspectRatio(comic) > 1.02;
  }

  private getAdaptiveGridColumnCount(): number {
    return this.isLandscape ? 5 : 3;
  }

  private getComicGridSpan(comic: ComicInfo, columnCount: number): number {
    const desiredSpan = this.isLandscapeCover(comic) ? 2 : 1;
    return Math.max(1, Math.min(desiredSpan, columnCount));
  }

  private buildAdaptiveCoverRows(comics: ComicInfo[], keyPrefix: string): AdaptiveCoverRow[] {
    const rows: AdaptiveCoverRow[] = [];
    const columnCount = this.getAdaptiveGridColumnCount();

    let rowItems: AdaptiveCoverRowItem[] = [];
    let usedSpan = 0;
    let rowIndex = 0;

    comics.forEach((comic: ComicInfo) => {
      const span = this.getComicGridSpan(comic, columnCount);
      if (rowItems.length > 0 && usedSpan + span > columnCount) {
        rows.push({
          key: `${keyPrefix}_row_${rowIndex}`,
          usedSpan: usedSpan,
          items: rowItems
        });
        rowItems = [];
        usedSpan = 0;
        rowIndex++;
      }

      rowItems.push({ comic: comic, span: span });
      usedSpan += span;
    });

    if (rowItems.length > 0) {
      rows.push({
        key: `${keyPrefix}_row_${rowIndex}`,
        usedSpan: usedSpan,
        items: rowItems
      });
    }

    return rows;
  }

  private getCoverFrameBorderColor(): string {
    return 'rgba(0,0,0,0)';
  }

  private async loadCoverPixelMap(comic: ComicInfo): Promise<void> {
    try {
      // 如果已经加载过，直接返回
      if (this.coverPixelMaps.has(comic.id)) {
        return;
      }
      
      const url: string = comic.coverUrl || '';
      if (url.length === 0) { return; }
      
      // 优先使用CoverCacheManager的本地缓存
      const coverCache = CoverCacheManager.getInstance();
      const localPath = await coverCache.getLocalCoverPath(this.sourceId, comic.id);
      
      // 如果有本地缓存，直接从本地加载
      if (localPath) {
        try {
          const imageSource = image.createImageSource(localPath);
          await this.updateCoverAspectRatioFromImageSource(comic.id, imageSource);
          const pm = await this.createCoverThumbnailPixelMap(imageSource);
          const newMap: Map<string, image.PixelMap> = new Map(this.coverPixelMaps);
          newMap.set(comic.id, pm);
          this.coverPixelMaps = newMap;
          return;
        } catch (e) {
          logger.warn(TAG, `从本地缓存加载封面失败: ${e}`);
        }
      }
      
      // 没有本地缓存，使用ImageCacheManager加载（会自动缓存）
      const cacheMgr: ImageCacheManager = ImageCacheManager.getInstance();
      const cookieMgr: CookieManager = CookieManager.getInstance();
      const baseHeaders: RequestHeaders = this.buildCoverHeaders();
      const headers: RequestHeaders = await cookieMgr.buildHeadersWithCookie(baseHeaders, this.sourceId);
      const opts: LoadOptions = {
        headers: headers,
        width: 160,
        height: 220,
        sourceId: this.sourceId,
        loadingMethod: 0,
        partitionKey: 'covers'
      } as LoadOptions;
      const pm: image.PixelMap | null = await cacheMgr.loadImage(url, opts);
      if (pm) {
        await this.updateCoverAspectRatioFromPixelMap(comic.id, pm);
        const newMap: Map<string, image.PixelMap> = new Map(this.coverPixelMaps);
        newMap.set(comic.id, pm);
        this.coverPixelMaps = newMap;
      }
    } catch (_e) {}
  }

  /**
   * 使用WebView系统加载漫画
   */
  private async loadComicsWithWebView(): Promise<ComicInfo[]> {
    if (!this.mangaSourceEngine) {
      logger.error(TAG, 'WebView引擎未初始化');
      throw new Error('WebView引擎未初始化');
    }

    const MAX_RETRIES = 2; // 最多重试2次（总共3次尝试）
    const RETRY_DELAY = 1000; // 重试延迟1秒

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      try {
        if (attempt > 0) {
          logger.info(TAG, `🔄 第${attempt}次重试，等待${RETRY_DELAY}ms...`);
          await new Promise<void>((resolve) => {
            setTimeout(() => resolve(), RETRY_DELAY);
          });
        }

        let result: EngineResult<SearchResult> | null = null;

        // 获取当前标签配置
        const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
        if (!currentTab) {
          logger.warn(TAG, `未找到标签配置: ${this.currentTabId}`);
          return [];
        }

        // 根据标签类型调用不同的方法
        switch (currentTab.type) {
          case TabType.POPULAR:
            logger.info(TAG, `开始获取热门漫画: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getPopular(this.currentPage);
            break;
          
          case TabType.LATEST:
            logger.info(TAG, `开始获取最新更新: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getLatest(this.currentPage);
            break;
          
          case TabType.FILTER:
          case TabType.CUSTOM:
            logger.info(TAG, `开始筛选: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            const params = currentTab.filterParams || {};
            // 输出 dynamicFilterValues 的内容用于调试
            const filterEntries: string[] = [];
            this.dynamicFilterValues.forEach((value: string, key: string) => {
              filterEntries.push(`${key}=${value}`);
            });
            logger.info(TAG, `动态筛选参数: [${filterEntries.join(', ')}]`);
            // 传递动态筛选参数，支持不同图源的不同筛选组
            result = await this.mangaSourceEngine.getFiltered(
              this.currentPage,
              params.ordering || this.filterOrdering,
              params.region || this.filterRegion,
              params.theme || this.filterTheme,
              this.dynamicFilterValues  // 传递动态筛选参数
            );
            break;
          
          case TabType.FAVORITES:
            logger.info(TAG, `开始获取收藏: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getFavorites(this.currentPage);
            break;
          
          case TabType.HISTORY:
            logger.info(TAG, `开始获取浏览记录: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getHistory(this.currentPage);
            break;
          
          case TabType.LEADERBOARD:
            logger.info(TAG, `开始获取排行榜: 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getLeaderboard(this.currentPage, this.dynamicFilterValues);
            break;
          
          case TabType.SEARCH:
            // 搜索标签 - 直接返回已缓存的搜索结果
            logger.info(TAG, `搜索标签: 使用缓存的搜索结果，共 ${this.searchResults.length} 条`);
            return this.searchResults;
          
          case TabType.CATEGORY:
            // 分类页面标签（电子书等）
            const categoryUrl = currentTab.categoryUrl || '';
            logger.info(TAG, `开始获取分类内容: url=${categoryUrl}, 页码=${this.currentPage}, 尝试=${attempt + 1}/${MAX_RETRIES + 1}`);
            result = await this.mangaSourceEngine.getCategory(categoryUrl, this.currentPage);
            break;
          
          default:
            logger.warn(TAG, `未知的标签类型: ${currentTab.type}，使用热门漫画`);
            result = await this.mangaSourceEngine.getPopular(this.currentPage);
            break;
        }

        logger.debug(TAG, `WebView请求返回: success=${result?.success}, hasData=${!!result?.data}, error=${result?.error}`);

        if (result && result.success && result.data) {
          const mangaCount = result.data.mangas.length;
          
          // 如果返回数据为空且还有重试次数，则重试
          if (mangaCount === 0 && attempt < MAX_RETRIES) {
            logger.warn(TAG, `⚠️ 获取到0条数据，将进行重试 (${attempt + 1}/${MAX_RETRIES + 1})`);
            continue; // 继续下一次重试
          }
          
          logger.info(TAG, `✅ WebView请求成功，找到 ${mangaCount} 条结果，耗时 ${result.duration}ms`);
          const converted = this.convertMangaInfoToComicInfo(result.data.mangas);
          logger.debug(TAG, `转换后的漫画数量: ${converted.length}`);
          
          try {
            const controller: webview.WebviewController = this.webViewController;
            const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(this.sourceId);
            let baseUrl: string = '';
            if (srcRecord) { baseUrl = srcRecord.baseUrl; }
            const refreshed: boolean = await CookieManager.getInstance().refreshCookiesIfNeeded(this.sourceId, controller, baseUrl);
            logger.debug(TAG, `刷新Cookie完成: ${refreshed}`);
          } catch (cookieErr) {
            logger.warn(TAG, `刷新Cookie失败: ${String(cookieErr)}`);
          }
          
          return converted;
        } else {
          const errorMsg = result?.error || '未知错误';
          
          // 如果还有重试次数，继续重试
          if (attempt < MAX_RETRIES) {
            logger.warn(TAG, `⚠️ WebView请求失败: ${errorMsg}，将进行重试 (${attempt + 1}/${MAX_RETRIES + 1})`);
            continue;
          } else {
            logger.error(TAG, `❌ WebView请求失败（已重试${MAX_RETRIES}次）: ${errorMsg}`);
            return [];
          }
        }
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        const errorStack = error instanceof Error ? error.stack : '';
        
        // 如果还有重试次数，继续重试
        if (attempt < MAX_RETRIES) {
          logger.warn(TAG, `⚠️ WebView加载异常: ${errorMsg}，将进行重试 (${attempt + 1}/${MAX_RETRIES + 1})`);
          logger.debug(TAG, `异常堆栈: ${errorStack}`);
          continue;
        } else {
          logger.error(TAG, `❌ WebView加载异常（已重试${MAX_RETRIES}次）: ${errorMsg}`);
          logger.debug(TAG, `异常堆栈: ${errorStack}`);
          throw error as Error;
        }
      }
    }
    
    // 理论上不会到这里，但为了类型安全
    return [];
  }

  /**
   * 使用HTTP系统加载漫画
   */
  private async loadComicsWithHTTP(): Promise<ComicInfo[]> {
    try {
      let comics: ComicInfo[] = [];

      const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
      if (!currentTab) {
        logger.warn(TAG, `未找到标签配置: ${this.currentTabId}`);
        return [];
      }

      switch (currentTab.type) {
        case TabType.POPULAR:
          comics = await this.sourceManager.getPopular(this.sourceId, this.currentPage, 20);
          break;
        case TabType.LATEST:
          comics = await this.sourceManager.getLatest(this.sourceId, this.currentPage, 20);
          break;
        case TabType.FILTER:
        case TabType.CUSTOM:
        case TabType.FAVORITES:
        case TabType.HISTORY:
          // HTTP系统暂不支持这些功能，返回空数组
          logger.warn(TAG, `HTTP系统暂不支持${currentTab.name}功能`);
          break;
      }

      try {
        const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceById(this.sourceId);
        let baseUrl: string = '';
        if (srcRecord) { baseUrl = srcRecord.baseUrl; }
        await CookieManager.getInstance().refreshCookiesIfNeeded(this.sourceId, null, baseUrl);
      } catch (cookieErr) {
        const msg: string = cookieErr instanceof Error ? cookieErr.message : String(cookieErr);
        logger.warn(TAG, `HTTP流程刷新Cookie失败: ${msg}`);
      }

      return comics;
    } catch (error) {
      logger.error(TAG, 'HTTP加载失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 转换MangaInfo到ComicInfo
   */
  private convertMangaInfoToComicInfo(mangas: MangaInfo[]): ComicInfo[] {
    return mangas.map((manga: MangaInfo) => {
      // 从URL路径中提取ID
      // 只对以 / 开头的路径格式进行转换（如 /comic/466 -> 466）
      // 不对日期格式路径（如 2025/12/02/xxx）进行转换，保持原样
      let comicId = manga.id || '';
      if (comicId.startsWith('/')) {
        const parts = comicId.split('/').filter((p: string) => p.length > 0);
        comicId = parts[parts.length - 1] || manga.id || '';
      }
      
      // 直接使用封面URL（从img src属性提取）
      const coverUrl = manga.cover || '';
      
      logger.debug(TAG, `转换漫画: id="${manga.id}" -> "${comicId}", title="${manga.title}", cover="${coverUrl}"`);
      
      const comic: ComicInfo = {
        id: comicId,
        title: manga.title || '',
        author: manga.author || '',
        coverUrl: coverUrl,
        description: manga.description || '',
        tags: manga.genres || [],
        status: manga.status || '',
        updateTime: 0 // MangaInfo的updated是string，这里简化处理
      };
      return comic;
    });
  }

  /**
   * 切换到下一个标签页（支持循环）
   */
  private switchToNextTab(): void {
    if (this.tabsConfig.length === 0) return;
    const currentIndex = this.tabsConfig.findIndex(t => t.id === this.currentTabId);
    const nextIndex = (currentIndex + 1) % this.tabsConfig.length;
    this.switchToTab(this.tabsConfig[nextIndex].id);
  }
  
  /**
   * 切换到上一个标签页（支持循环）
   */
  private switchToPrevTab(): void {
    if (this.tabsConfig.length === 0) return;
    const currentIndex = this.tabsConfig.findIndex(t => t.id === this.currentTabId);
    const prevIndex = (currentIndex - 1 + this.tabsConfig.length) % this.tabsConfig.length;
    this.switchToTab(this.tabsConfig[prevIndex].id);
  }

  /**
   * 切换标签页
   */
  private async switchToTab(tabId: string): Promise<void> {
    if (this.currentTabId === tabId) return;

    // 检查是否从筛选标签切换到非筛选标签，如果是则清空筛选历史
    const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
    const targetTab = this.tabsConfig.find(t => t.id === tabId);
    const isCurrentFilterTab = currentTab && (currentTab.type === TabType.FILTER || currentTab.type === TabType.LEADERBOARD || currentTab.type === TabType.CUSTOM);
    const isTargetFilterTab = targetTab && (targetTab.type === TabType.FILTER || targetTab.type === TabType.LEADERBOARD || targetTab.type === TabType.CUSTOM);
    
    // 如果从筛选类型标签切换到非筛选类型标签，清空筛选历史
    if (isCurrentFilterTab && !isTargetFilterTab) {
      this.clearFilterHistory();
    }

    this.currentTabId = tabId;
    this.currentPage = 1;
    this.hasMore = true;
    
    // 加载该标签的显示模式
    this.loadTabDisplayMode(tabId);
    
    // 保存上次访问的标签（搜索标签除外）
    if (tabId !== 'search') {
      this.saveLastVisitedTab(tabId);
    }
    
    // 如果切换到搜索标签，使用缓存的搜索结果
    if (tabId === 'search') {
      this.comicList = [...this.searchResults];
      this.comicDataSource.updateItems([...this.comicList]);
      this.touchComicContentRender();
      return;
    }
    
    // 切换到其他标签时，清空列表并重新加载
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();
    await this.loadComics();
  }

  /**
   * 判断是否应该显示筛选选项
   */
  private shouldShowFilterOptions(): boolean {
    const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
    if (!currentTab) return false;
    // 筛选和自定义标签页始终显示筛选选项
    if (currentTab.type === TabType.FILTER || currentTab.type === TabType.CUSTOM) {
      return true;
    }
    // 排行榜标签页如果有filterConfig也显示筛选选项
    if (currentTab.type === TabType.LEADERBOARD && currentTab.filterConfig && currentTab.filterConfig.groups.length > 0) {
      return true;
    }
    return false;
  }

  /**
   * 加载标签页配置
   */
  private async loadTabsConfig(): Promise<void> {
    try {
      // 检查登录状态
      this.isLoggedIn = await this.dataManager.isSourceLoggedIn(this.sourceId);
      logger.info(TAG, `登录状态: ${this.isLoggedIn}`);

      let config: SourceTabsConfig;

      // 首先尝试从图源配置中解析标签
      const sourceConfig: Record<string, Object> | null = await this.dataManager.getSourceConfig(this.sourceId) as Record<string, Object> | null;
      if (sourceConfig) {
        config = parseTabsFromSourceConfig(this.sourceId, sourceConfig);
        logger.info(TAG, `从图源配置解析标签: ${config.tabs.length}个标签`);
        
        // 如果图源配置中有 filters 定义，为筛选标签添加 filterConfig
        if (sourceConfig['filters']) {
          this.enrichFilterTabsWithConfig(config.tabs, sourceConfig['filters'] as Record<string, Object>);
        }
        // 同时从 settings 中加载筛选配置（兼容旧格式）
        if (sourceConfig['settings']) {
          this.loadFilterConfigFromSettings(sourceConfig['settings'] as Record<string, Object>);
        }
      } else {
        // 尝试加载用户自定义的标签配置
        const configJson = await this.dataManager.getSourceTabsConfig(this.sourceId);
        if (configJson) {
          config = JSON.parse(configJson) as SourceTabsConfig;
          logger.info(TAG, `已加载用户标签配置: ${config.tabs.length}个标签`);
        } else {
          // 使用默认配置
          config = getDefaultTabsConfig(this.sourceId);
          logger.info(TAG, '使用默认标签配置');
        }
      }

      // 过滤并排序标签
      this.tabsConfig = sortTabs(
        filterTabsByLoginStatus(
          config.tabs.filter(t => t.enabled),
          this.isLoggedIn
        )
      );

      logger.info(TAG, `最终标签列表: ${this.tabsConfig.map(t => t.name).join(', ')}`);

      // 设置默认标签（优先使用上次访问的标签）
      if (this.tabsConfig.length > 0 && !this.currentTabId) {
        const lastTabId = await this.loadLastVisitedTab();
        if (lastTabId && this.tabsConfig.find(t => t.id === lastTabId)) {
          this.currentTabId = lastTabId;
        } else {
          this.currentTabId = this.tabsConfig[0].id;
        }
        // 加载该标签的显示模式
        this.loadTabDisplayMode(this.currentTabId);
      }
    } catch (error) {
      logger.error(TAG, '加载标签配置失败', String(error));
      // 使用默认配置
      const defaultConfig = getDefaultTabsConfig(this.sourceId);
      this.tabsConfig = sortTabs(defaultConfig.tabs);
      if (this.tabsConfig.length > 0) {
        this.currentTabId = this.tabsConfig[0].id;
        this.loadTabDisplayMode(this.currentTabId);
      }
    }
  }

  /**
   * 为筛选标签添加筛选配置
   * 注意：只有当标签本身没有定义 filterConfig 时，才从顶级 filters 配置中添加
   */
  private enrichFilterTabsWithConfig(tabs: TabConfig[], filtersConfig: Record<string, Object>): void {
    const filterTab = tabs.find(t => t.type === TabType.FILTER);
    if (!filterTab) {
      return;
    }

    // 如果标签已经有 filterConfig，不覆盖
    if (filterTab.filterConfig && filterTab.filterConfig.groups && filterTab.filterConfig.groups.length > 0) {
      logger.info(TAG, `筛选标签已有 filterConfig，保留原有配置（${filterTab.filterConfig.groups.length} 个筛选组）`);
      return;
    }

    // 将 filters 配置转换为 FilterConfig
    const groups: FilterGroup[] = [];
    const filterKeys = Object.keys(filtersConfig);
    let order = 0;

    for (let i = 0; i < filterKeys.length; i++) {
      const key = filterKeys[i];
      const filterDef = filtersConfig[key] as Record<string, Object>;
      if (!filterDef || typeof filterDef !== 'object') {
        continue;
      }

      const options = filterDef['options'] as Record<string, Object>[] | undefined;
      if (!options || !Array.isArray(options)) {
        continue;
      }

      // 转换选项列表
      const filterOptions: FilterOption[] = [];
      for (let j = 0; j < options.length; j++) {
        const opt: Record<string, Object> = options[j];
        const optItem: FilterOption = {
          value: String(opt['value'] || ''),
          label: String(opt['label'] || opt['value'] || '')
        };
        filterOptions.push(optItem);
      }

      groups.push({
        id: key,
        title: String(filterDef['name'] || key),
        placeholder: filterDef['placeholder'] as string | undefined,
        options: filterOptions,
        defaultValue: filterDef['default'] as string | undefined,
        required: filterDef['required'] === true,
        order: order++
      });
    }

    if (groups.length > 0) {
      filterTab.filterConfig = {
        groups: groups,
        title: '筛选',
        description: '选择筛选条件'
      };
      logger.info(TAG, `为筛选标签添加了 ${groups.length} 个筛选组（从顶级 filters 配置）`);
    }
  }

  /**
   * 从settings配置中加载筛选选项
   */
  private loadFilterConfigFromSettings(settings: Record<string, Object>): void {
    const groups: FilterGroup[] = [];
    let order = 0;

    // 检查筛选相关的设置项
    const filterKeys = ['filterOrdering', 'filterRegion', 'filterTheme', 'sort', 'category'];
    
    for (const key of filterKeys) {
      const setting = settings[key] as Record<string, Object> | undefined;
      if (!setting || setting['type'] !== 'select') {
        continue;
      }

      const options = setting['options'] as Record<string, Object>[] | undefined;
      if (!options || !Array.isArray(options)) {
        continue;
      }

      const filterOptions: FilterOption[] = [];
      for (const opt of options) {
        const item: FilterOption = {
          value: String(opt['value'] || ''),
          label: String(opt['label'] || opt['value'] || '')
        };
        filterOptions.push(item);
      }

      groups.push({
        id: key,
        title: String(setting['name'] || key),
        placeholder: setting['description'] as string | undefined,
        options: filterOptions,
        defaultValue: setting['default'] as string | undefined,
        required: false,
        order: order++
      });
    }

    if (groups.length > 0) {
      this.sourceFilterConfig = {
        groups: groups,
        title: '筛选',
        description: '选择筛选条件'
      };
      logger.info(TAG, `从settings加载了 ${groups.length} 个筛选组`);
    }
  }

  /**
   * 显示登录对话框
   */
  private async showLogin(): Promise<void> {
    logger.info(TAG, `showLogin方法被调用, sourceId=${this.sourceId}`);
    try {
      // 获取图源配置中的登录URL
      logger.info(TAG, '开始获取图源配置');
      const config: ESObject | null = await this.dataManager.getSourceConfig(this.sourceId);
      logger.info(TAG, `获取到配置: ${config ? 'yes' : 'no'}`);
      
      if (config && config['login'] && config['login']['url']) {
        this.loginUrl = String(config['login']['url']);
        logger.info(TAG, `设置loginUrl: ${this.loginUrl}`);
        this.showLoginDialog = true;
        logger.info(TAG, `已设置showLoginDialog=true, 打开登录页面: ${this.loginUrl}`);
      } else {
        logger.warn(TAG, '图源未配置登录URL');
        this.getUIContext().getPromptAction().showToast({ message: '该图源不支持独立登录模式' });
      }
    } catch (error) {
      logger.error(TAG, '获取登录URL失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '获取登录信息失败' });
    }
  }

  /**
   * 完成登录
   */
  private async completeLogin(): Promise<void> {
    try {
      // 从WebView获取cookie
      await this.authManager.captureCookiesFromController(
        this.sourceId,
        this.loginWebViewController
      );
      
      // 更新登录状态
      this.isLoggedIn = true;
      
      // 重新加载Engine配置（确保获取最新的工作流配置）
      await this.reloadEngineConfig();
      
      // 获取用户头像
      await this.loadUserAvatar();
      
      // 重新加载标签配置
      await this.loadTabsConfig();
      
      // 关闭对话框
      this.showLoginDialog = false;
      
      // 提示用户
      this.getUIContext().getPromptAction().showToast({ message: '登录成功' });
      
      logger.info(TAG, '登录完成');
    } catch (error) {
      logger.error(TAG, '完成登录失败', String(error));
      this.getUIContext().getPromptAction().showToast({ message: '保存登录信息失败' });
    }
  }
  
  /**
   * 重新加载Engine配置
   */
  private async reloadEngineConfig(): Promise<void> {
    try {
      if (!this.mangaSourceEngine) {
        logger.warn(TAG, 'Engine未初始化，跳过配置重载');
        return;
      }
      
      logger.info(TAG, '开始重新加载Engine配置');
      
      // 从数据库获取最新配置
      const config: ESObject | null = await this.dataManager.getSourceConfig(this.sourceId);
      if (!config) {
        logger.warn(TAG, '无法获取图源配置');
        return;
      }
      
      // 重新加载配置到Engine
      const configJson = JSON.stringify(config);
      await this.mangaSourceEngine.loadConfig(configJson);
      
      logger.info(TAG, 'Engine配置重载成功');
    } catch (error) {
      logger.error(TAG, 'Engine配置重载失败', String(error));
    }
  }

  /**
   * 加载用户头像
   */
  private async loadUserAvatar(): Promise<void> {
    try {
      if (!this.mangaSourceEngine) {
        logger.warn(TAG, 'WebView引擎未初始化，无法获取用户头像');
        return;
      }
      
      // 调用getUserAvatar方法获取用户头像
      const result = await this.mangaSourceEngine.getUserAvatar();
      
      if (result.success && result.data) {
        this.userAvatarUrl = result.data;
        logger.info(TAG, `获取用户头像成功: ${this.userAvatarUrl}`);
      } else {
        logger.warn(TAG, '获取用户头像失败或未配置');
      }
    } catch (error) {
      logger.error(TAG, '加载用户头像失败', String(error));
    }
  }

  /**
   * 执行搜索（增强版）
   * 根据用户选择的搜索类型执行对应的搜索
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword.trim()) {
      logger.warn(TAG, '搜索关键词为空');
      return;
    }

    const rawQuery = this.searchKeyword.trim();
    logger.info(TAG, `执行搜索: 类型="${this.selectedSearchType}", 查询="${rawQuery}"`);

    // 根据搜索类型执行不同的搜索
    if (this.selectedSearchType === 'search') {
      // 关键词搜索：先尝试解析URL和前缀，否则按关键词搜索
      const intent: SearchIntent = SearchIntentParser.parse(rawQuery);
      if (intent.type === SearchIntentType.URL) {
        await this.executeUrlDirectAccess(intent);
      } else {
        await this.executeKeywordSearch(rawQuery);
      }
    } else if (this.selectedSearchType === 'searchByTag') {
      // 标签搜索：使用searchByTag工作流
      await this.executeTagSearch(rawQuery);
    } else {
      // 非关键词搜索：使用directSearch工作流
      await this.executeDirectSearch(this.selectedSearchType, rawQuery);
    }
  }

  /**
   * 执行标签搜索（使用searchByTag工作流）
   */
  private async executeTagSearch(tagId: string): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;
    this.lastSearchKeyword = `标签: ${tagId}`;

    this.addOrUpdateSearchTab();
    this.currentTabId = 'search';
    this.searchResults = [];
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();

    try {
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        // 检查是否支持searchByTag工作流
        if (this.mangaSourceEngine.supportsCapability('searchByTag')) {
          logger.info(TAG, `执行标签搜索: tagId=${tagId}`);
          const result = await this.mangaSourceEngine.searchByTag(tagId, 1);

          if (result.success && result.data) {
            const comics = this.convertMangaInfoToComicInfo(result.data.mangas);
            this.searchResults = comics;
            this.comicList = [...comics];
            this.comicDataSource.updateItems([...this.comicList]);
            this.touchComicContentRender();
            this.hasMore = result.data.hasNext || false;
            logger.info(TAG, `标签搜索完成，找到 ${comics.length} 个结果`);
          } else {
            this.getUIContext().getPromptAction().showToast({
              message: result.error || '标签搜索失败'
            });
          }
        } else {
          // 不支持searchByTag，降级为关键词搜索
          logger.warn(TAG, '图源不支持searchByTag工作流，降级为关键词搜索');
          await this.executeKeywordSearch(tagId);
          return;
        }
      } else {
        // 非WebView图源，降级为关键词搜索
        logger.warn(TAG, '非WebView图源，降级为关键词搜索');
        await this.executeKeywordSearch(tagId);
        return;
      }
    } catch (error) {
      logger.error(TAG, '标签搜索失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `搜索失败: ${error instanceof Error ? error.message : String(error)}`
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 执行直达搜索（使用directSearch工作流）
   */
  private async executeDirectSearch(searchType: string, query: string): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;
    this.lastSearchKeyword = `${this.getSelectedSearchTypeLabel()}: ${query}`;

    this.addOrUpdateSearchTab();
    this.currentTabId = 'search';
    this.searchResults = [];
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();

    try {
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        // 检查是否支持directSearch工作流
        if (this.mangaSourceEngine.supportsDirectSearch()) {
          logger.info(TAG, `执行直达搜索: type=${searchType}, query=${query}`);
          const result = await this.mangaSourceEngine.directSearch(searchType, query);

          if (result.success && result.data) {
            const directResult = result.data;
            logger.info(TAG, `直达搜索结果: type=${directResult.type}`);

            if (directResult.type === 'detail' && directResult.manga) {
              // 单个作品：直接跳转详情页
              logger.info(TAG, `直达单个作品: ${directResult.manga.title}`);
              this.isLoading = false;
              this.navigateToMangaDetail(directResult.manga);
              return;
            } else if (directResult.type === 'list' && directResult.mangas && directResult.mangas.length > 0) {
              // 作品列表：显示在搜索结果中
              this.searchResults = this.convertMangaInfoToComicInfo(directResult.mangas);
              this.comicList = [...this.searchResults];
              this.comicDataSource.updateItems([...this.comicList]);
              this.touchComicContentRender();
              this.hasMore = directResult.hasNext || false;
              logger.info(TAG, `直达搜索完成，找到 ${directResult.mangas.length} 个结果`);
            } else if (directResult.type === 'redirect' && directResult.redirectUrl) {
              // 重定向：构造MangaInfo并跳转
              const manga: MangaInfo = {
                id: query,
                title: `作品 ${query}`,
                url: directResult.redirectUrl,
                cover: ''
              };
              this.isLoading = false;
              this.navigateToMangaDetail(manga);
              return;
            } else {
              this.getUIContext().getPromptAction().showToast({
                message: '未找到相关内容'
              });
            }
          } else {
            this.getUIContext().getPromptAction().showToast({
              message: result.error || '搜索失败'
            });
          }
        } else {
          // 不支持directSearch，降级为关键词搜索
          logger.warn(TAG, '图源不支持directSearch工作流，降级为关键词搜索');
          await this.executeKeywordSearch(query);
          return;
        }
      } else {
        // 非WebView图源，降级为关键词搜索
        logger.warn(TAG, '非WebView图源，降级为关键词搜索');
        await this.executeKeywordSearch(query);
        return;
      }
    } catch (error) {
      logger.error(TAG, '直达搜索失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `搜索失败: ${error instanceof Error ? error.message : String(error)}`
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 获取当前选中搜索类型的标签
   */
  private getSelectedSearchTypeLabel(): string {
    const config = this.searchTypes.find((t: SearchTypeOption) => t.id === this.selectedSearchType);
    return config ? config.label : '搜索';
  }

  /**
   * 执行关键词搜索（原有逻辑）
   */
  private async executeKeywordSearch(keyword: string): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;
    this.lastSearchKeyword = keyword;

    // 添加或更新搜索标签页
    this.addOrUpdateSearchTab();

    // 切换到搜索标签页
    this.currentTabId = 'search';
    this.searchResults = [];
    this.comicList = []; // 清空列表以显示加载动画
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();

    try {
      let comics: ComicInfo[] = [];

      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        logger.info(TAG, `使用WebView系统搜索: 关键词="${keyword}"`);
        const result = await this.mangaSourceEngine.searchManga(keyword, 1);
        if (result && result.success && result.data) {
          comics = this.convertMangaInfoToComicInfo(result.data.mangas);
        }
      } else {
        logger.info(TAG, `使用HTTP系统搜索: 关键词="${keyword}"`);
        comics = await this.sourceManager.search(this.sourceId, keyword, 1, 20);
      }

      this.searchResults = comics;
      this.comicList = [...comics];
      this.comicDataSource.updateItems([...this.comicList]);
      this.touchComicContentRender();
      this.hasMore = comics.length >= 20;
      logger.info(TAG, `搜索完成，找到 ${comics.length} 个结果`);
    } catch (error) {
      logger.error(TAG, '搜索失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `搜索失败: ${error instanceof Error ? error.message : String(error)}`
      });
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  /**
   * 执行ID直达 - 直接跳转到作品详情页
   */
  private async executeIdDirectAccess(id: string, type: 'manga' | 'chapter'): Promise<void> {
    this.showSearchDialog = false;

    try {
      logger.info(TAG, `执行ID直达: id="${id}", type=${type}`);

      // 直接构造MangaInfo并跳转详情页，详情页会调用getMangaDetail获取完整信息
      const manga: MangaInfo = {
        id: id,
        title: `作品 ${id}`,
        url: '',
        cover: ''
      };

      logger.info(TAG, `ID直达，跳转详情页: ID=${id}`);
      this.navigateToMangaDetail(manga);
    } catch (error) {
      logger.error(TAG, 'ID直达失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `ID直达失败: ${error instanceof Error ? error.message : String(error)}`
      });
    }
  }

  /**
   * 执行作者搜索
   */
  private async executeAuthorSearch(authorId: string): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;
    this.lastSearchKeyword = `作者: ${authorId}`;

    this.addOrUpdateSearchTab();
    this.currentTabId = 'search';
    this.searchResults = [];
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();

    try {
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        // 检查是否支持作者搜索
        if (this.mangaSourceEngine.supportsCapability('searchByAuthor')) {
          logger.info(TAG, `执行作者搜索: authorId="${authorId}"`);
          const result = await this.mangaSourceEngine.searchByAuthor(authorId, 1);

          if (result.success && result.data) {
            this.searchResults = this.convertMangaInfoToComicInfo(result.data.mangas);
            this.comicList = [...this.searchResults];
            this.comicDataSource.updateItems([...this.comicList]);
            this.touchComicContentRender();
            this.hasMore = result.data.hasNext;
            logger.info(TAG, `作者搜索完成，找到 ${result.data.mangas.length} 个结果`);
            return;
          }
        }

        // 不支持或失败，提示并降级
        logger.warn(TAG, '图源不支持作者ID搜索，降级为关键词搜索');
        this.getUIContext().getPromptAction().showToast({
          message: '该图源不支持作者ID搜索，已按关键词搜索'
        });
        await this.executeKeywordSearch(authorId);
      } else {
        await this.executeKeywordSearch(authorId);
      }
    } catch (error) {
      logger.error(TAG, '作者搜索失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `作者搜索失败: ${error instanceof Error ? error.message : String(error)}`
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 执行系列搜索
   */
  private async executeSeriesSearch(seriesId: string): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;
    this.lastSearchKeyword = `系列: ${seriesId}`;

    this.addOrUpdateSearchTab();
    this.currentTabId = 'search';
    this.searchResults = [];
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();

    try {
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        // 检查是否支持系列搜索
        if (this.mangaSourceEngine.supportsCapability('searchBySeries')) {
          logger.info(TAG, `执行系列搜索: seriesId="${seriesId}"`);
          const result = await this.mangaSourceEngine.searchBySeries(seriesId, 1);

          if (result.success && result.data) {
            this.searchResults = this.convertMangaInfoToComicInfo(result.data.mangas);
            this.comicList = [...this.searchResults];
            this.comicDataSource.updateItems([...this.comicList]);
            this.touchComicContentRender();
            this.hasMore = result.data.hasNext;
            logger.info(TAG, `系列搜索完成，找到 ${result.data.mangas.length} 个结果`);
            return;
          }
        }

        // 不支持或失败，提示并降级
        logger.warn(TAG, '图源不支持系列ID搜索，降级为关键词搜索');
        this.getUIContext().getPromptAction().showToast({
          message: '该图源不支持系列ID搜索，已按关键词搜索'
        });
        await this.executeKeywordSearch(seriesId);
      } else {
        await this.executeKeywordSearch(seriesId);
      }
    } catch (error) {
      logger.error(TAG, '系列搜索失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: `系列搜索失败: ${error instanceof Error ? error.message : String(error)}`
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 执行URL直达
   */
  private async executeUrlDirectAccess(intent: SearchIntent): Promise<void> {
    this.showSearchDialog = false;
    this.isLoading = true;

    try {
      const urlInfo = intent.urlParsedInfo;

      if (urlInfo && urlInfo.extractedId) {
        // URL已解析出ID，根据类型处理
        switch (urlInfo.pathType) {
          case 'artwork':
            await this.executeIdDirectAccess(urlInfo.extractedId, 'manga');
            return;
          case 'user':
            await this.executeAuthorSearch(urlInfo.extractedId);
            return;
          case 'series':
            await this.executeSeriesSearch(urlInfo.extractedId);
            return;
        }
      }

      // 无法解析，降级为关键词搜索
      logger.warn(TAG, 'URL无法解析，降级为关键词搜索');
      await this.executeKeywordSearch(intent.rawQuery);
    } catch (error) {
      logger.error(TAG, 'URL直达失败', String(error));
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 跳转到漫画详情页
   */
  private navigateToMangaDetail(manga: MangaInfo): void {
    const sourceType = this.sourceInfo?.type || 'manga';

    // 根据页面设置决定使用哪个详情页
    const pageType = sourceType === 'ebook' 
      ? PageSettingsHelper.getEBookDetailPageType()
      : PageSettingsHelper.getMangaDetailPageType();

    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: sourceType === 'ebook' ? UnifiedContentType.EBOOK : UnifiedContentType.MANGA,
        contentId: manga.id || '',
        sourceId: this.sourceId?.toString(),
        cachedTitle: manga.title,
        cachedCover: manga.cover
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    } else if (sourceType === 'ebook') {
      const params: OnlineEBookDetailPageParams = {
        sourceId: this.sourceId,
        bookId: manga.id || '',
        cachedTitle: manga.title || undefined,
        cachedCover: manga.cover || undefined
      };
      this.pathStack.pushPathByName('OnlineEBookDetailPage', params);
    } else {
      const params: MangaDetailPageParams = {
        sourceId: this.sourceId,
        mangaId: manga.id || '',
        cachedTitle: manga.title || undefined,
        cachedCover: manga.cover || undefined
      };
      this.pathStack.pushPathByName('MangaDetailPage', params);
    }
  }

  /**
   * 处理歧义ID选择（作品ID）
   */
  private handleAmbiguousAsMangaId(): void {
    this.showAmbiguousDialog = false;
    this.executeIdDirectAccess(this.ambiguousId, 'manga');
  }

  /**
   * 处理歧义ID选择（作者ID）
   */
  private handleAmbiguousAsAuthorId(): void {
    this.showAmbiguousDialog = false;
    this.executeAuthorSearch(this.ambiguousId);
  }

  /**
   * 处理歧义ID选择（关键词搜索）
   */
  private handleAmbiguousAsKeyword(): void {
    this.showAmbiguousDialog = false;
    this.executeKeywordSearch(this.ambiguousId);
  }

  /**
   * 添加或更新搜索标签页
   */
  private addOrUpdateSearchTab(): void {
    // 检查是否已存在搜索标签
    const existingSearchTabIndex = this.tabsConfig.findIndex(t => t.type === TabType.SEARCH);
    
    const searchTab: TabConfig = {
      id: 'search',
      type: TabType.SEARCH,
      name: `搜索: ${this.searchKeyword.trim()}`,
      enabled: true,
      order: 999, // 放在最后
      requiresLogin: false
    };
    
    if (existingSearchTabIndex >= 0) {
      // 更新现有搜索标签
      this.tabsConfig[existingSearchTabIndex] = searchTab;
    } else {
      // 添加新的搜索标签
      this.tabsConfig.push(searchTab);
    }
    
    this.searchTabVisible = true;
    logger.info(TAG, `搜索标签已${existingSearchTabIndex >= 0 ? '更新' : '添加'}: "${this.searchKeyword.trim()}"`);
  }

  /**
   * 移除搜索标签页
   */
  private removeSearchTab(): void {
    const searchTabIndex = this.tabsConfig.findIndex(t => t.type === TabType.SEARCH);
    if (searchTabIndex >= 0) {
      this.tabsConfig.splice(searchTabIndex, 1);
      this.searchTabVisible = false;
      this.searchResults = [];
      this.lastSearchKeyword = '';
      logger.info(TAG, '搜索标签已移除');
    }
  }

  /**
   * 加载更多
   */
  private loadMore(): void {
    if (!this.hasMore || this.isLoading) return;

    this.currentPage++;
    this.loadComics();
  }

  /**
   * 打开内容详情（根据图源类型导航到不同的详情页）
   */
  private async openComicDetail(comic: ComicInfo): Promise<void> {
    // 获取本地封面路径
    const coverCache = CoverCacheManager.getInstance();
    const localCoverPath = await coverCache.getLocalCoverPath(this.sourceId, comic.id);
    
    // 根据图源类型导航到不同的详情页
    const sourceType = this.sourceInfo?.type || 'manga';
    
    // 根据页面设置决定使用哪个详情页
    const pageType = sourceType === 'ebook' 
      ? PageSettingsHelper.getEBookDetailPageType()
      : PageSettingsHelper.getMangaDetailPageType();

    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: sourceType === 'ebook' ? UnifiedContentType.EBOOK : UnifiedContentType.MANGA,
        contentId: comic.id,
        sourceId: this.sourceId?.toString(),
        cachedTitle: comic.title,
        cachedCoverPath: localCoverPath || undefined,
        cachedCover: localCoverPath || comic.coverUrl || undefined
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    } else if (sourceType === 'ebook') {
      // 电子书源 -> 在线电子书详情页
      const params: OnlineEBookDetailPageParams = {
        sourceId: this.sourceId,
        bookId: comic.id,
        cachedCoverPath: localCoverPath || undefined,
        cachedTitle: comic.title || undefined,
        cachedCover: comic.coverUrl || undefined
      };
      this.pathStack.pushPathByName('OnlineEBookDetailPage', params);
    } else {
      // 漫画源（默认）-> 漫画详情页
      const params: MangaDetailPageParams = {
        sourceId: this.sourceId,
        mangaId: comic.id,
        cachedCoverPath: localCoverPath || undefined,
        cachedTitle: comic.title || undefined,
        cachedCover: comic.coverUrl || undefined
      };
      this.pathStack.pushPathByName('MangaDetailPage', params);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 预留标题栏空间
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 标签栏
          this.buildTabBar()

          // 筛选选项（筛选标签时显示）
          if (this.shouldShowFilterOptions()) {
            this.buildFilterOptions()
          }

          // 内容区域 - 改用 Stack 叠加模式
          // 解决 LazyForEach 在条件渲染切换时可能丢失数据源监听的问题
          Stack() {
            // 1. 底层：漫画列表网格
            // 始终渲染 Grid，确保 IDataSource 监听器一直保持连接
            this.buildComicGrid(this.comicContentRenderVersion)

            // 2. 中层：空状态视图
            // 仅在首次加载完成后、非加载中且数据为空时覆盖显示
            // 初次进入页面时不显示"暂无内容"，等待自动加载
            if (this.hasLoadedOnce && !this.isLoading && this.comicList.length === 0) {
              // 包裹一层背景色，防止透视到底层的 Grid（虽然此时 Grid 应该是空的）
              Column() {
                this.buildEmptyView()
              }
              .width('100%')
              .height('100%')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
              .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
            }

            // 3. 顶层：加载视图
            // 仅在初始加载且列表为空时全屏覆盖
            // 分页加载时的 Loading 由 buildComicGrid 内部的底部条处理
            if (this.isLoading && this.comicList.length === 0) {
              Column() {
                this.buildLoadingView()
              }
              .width('100%')
              .height('100%')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
            }
          }
          .width('100%')
          .layoutWeight(1) // 占据剩余垂直空间
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
              .onActionStart((event: GestureEvent) => {
                this.swipeStartX = event.offsetX;
                this.swipeOffsetX = 0;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.swipeOffsetX = event.offsetX - this.swipeStartX;
              })
              .onActionEnd((event: GestureEvent) => {
                const swipeThreshold = 80;
                if (this.swipeOffsetX < -swipeThreshold) {
                  this.switchToNextTab();
                } else if (this.swipeOffsetX > swipeThreshold) {
                  this.switchToPrevTab();
                }
                this.swipeOffsetX = 0;
              })
          )
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 隐藏的WebView组件（仅在使用WebView系统时渲染，调试模式下显示）
        // 注意：src使用about:blank，所有导航由controller控制，避免状态变化时重新加载
        if (this.useWebView) {
          Web({
            src: 'about:blank',
            controller: this.webViewController
          })
            .width(this.showWebViewDebugDialog ? '100%' : 1)
            .height(this.showWebViewDebugDialog ? '100%' : 1)
            .opacity(this.showWebViewDebugDialog ? 1 : 0)
            .visibility(this.showWebViewDebugDialog ? Visibility.Visible : Visibility.None)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .mixedMode(MixedMode.All)
            .cacheMode(CacheMode.Default)
            .userAgent(this.sourceUserAgent)
            .onControllerAttached(() => {
              logger.info(TAG, 'WebView控制器已附加');
              this.webViewControllerAttached = true;
            })
            .onPageBegin((event) => {
              logger.debug(TAG, `WebView页面开始加载: ${event.url}`);
            })
            .onPageEnd((event) => {
              logger.debug(TAG, `WebView页面加载完成: ${event.url}`);
              try {
                WebViewAuthManager.getInstance().captureCookiesFromController(this.sourceId, this.webViewController);
              } catch (e) {
                const msg: string = e instanceof Error ? e.message : String(e);
                logger.warn(TAG, `页面结束捕获Cookie失败: ${msg}`);
              }
            })
            .onErrorReceive((event) => {
              const errorInfo = event.error.getErrorInfo();
              logger.error(TAG, `WebView错误: ${errorInfo}`);
            })
        }

        // 登录对话框（WebView登录）
        if (this.showLoginDialog) {
          this.buildLoginDialog()
        }
        
        // 凭据登录对话框
        if (this.showCredentialDialog) {
          this.buildCredentialLoginDialog()
        }
        
        // Cloudflare验证对话框
        if (this.showCfVerifyDialog) {
          this.buildCfVerifyDialog()
        }
        
        // WebView调试对话框
        if (this.showWebViewDebugDialog) {
          this.buildWebViewDebugDialog()
        }

        // 搜索歧义选择对话框（纯数字输入时）
        if (this.showAmbiguousDialog) {
          this.buildAmbiguousDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.sourceInfo?.name || '图源详情',
          subTitle: this.sourceInfo?.description
        },
        menu: {
          value: [
            {
              content: {
                label: '搜索',
                icon: $r('sys.symbol.magnifyingglass'),
                isEnabled: true,
                action: () => {
                  this.showSearchDialog = true;
                }
              }
            },
            {
              content: {
                label: this.isLoggedIn ? '重新登录' : '登录',
                icon: this.isLoggedIn && this.userAvatarUrl ? this.userAvatarUrl : $r('sys.symbol.person_crop_circle_fill'),
                isEnabled: true,
                action: async () => {
                  logger.info(TAG, `点击登录按钮, isLoggedIn=${this.isLoggedIn}, hasAvatar=${!!this.userAvatarUrl}`);
                  // 无论当前状态如何，都允许用户登录/重新登录
                  // 因为可能只有基础Cookie而没有真正的登录Cookie
                  logger.info(TAG, '开始调用showLogin方法');
                  await this.showLogin();
                  logger.info(TAG, 'showLogin方法调用完成');
                }
              }
            },
            {
              content: {
                label: '调试',
                icon: $r('sys.symbol.worldclock_fill_1'),
                isEnabled: this.useWebView,
                action: () => {
                  logger.info(TAG, '点击调试按钮，显示WebView调试窗口');
                  this.showWebViewDebugDialog = true;
                }
              }
            },
            {
              content: {
                label: '设置',
                icon: $r('sys.symbol.gearshape_fill'),
                isEnabled: true,
                action: () => {
                  logger.info(TAG, `准备跳转到设置页, sourceName=${this.sourceName}`);
                  const params = { sourceName: this.sourceName } as SourceSettingsPageParams;
                  logger.info(TAG, `跳转参数: ${JSON.stringify(params)}`);
                  this.pathStack.pushPathByName('SourceSettingsPage', params);
                }
              }
            }
          ]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onShown(() => {
      this.touchComicContentRender();
    })
    .backgroundColor(Color.Transparent)
    .bindContentCover(this.showSearchDialog, this.buildSearchDialog(), {
      modalTransition: ModalTransition.DEFAULT,
      backgroundColor: Color.Transparent,
      onDisappear: () => {
        this.showSearchDialog = false;
      }
    })
  }

  /**
   * 构建筛选选项（动态生成，根据图源配置自动适配）
   */
  @Builder
  buildFilterOptions() {
    // 获取当前标签的筛选配置
    if (this.getDynamicFilterGroups().length > 0) {
      // 使用图源配置的动态筛选组
      Row({ space: 8 }) {
        ForEach(this.getDynamicFilterGroups(), (group: FilterGroup) => {
          Button(this.getDynamicFilterLabel(group))
            .fontSize(13)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showDynamicFilterPicker(group);
            })
        }, (group: FilterGroup) => group.id)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    } else {
      // 回退到默认的三个筛选按钮
      Row({ space: 12 }) {
        Button(this.getOrderingLabel())
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showOrderingPicker();
          })

        Button(this.getRegionLabel())
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showRegionPicker();
          })

        Button(this.getThemeLabel())
          .fontSize(14)
          .layoutWeight(1)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showThemePicker();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    }
  }

  /**
   * 获取动态筛选组列表
   */
  private getDynamicFilterGroups(): FilterGroup[] {
    // 优先从当前标签页的filterConfig获取
    const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
    if (currentTab && currentTab.filterConfig && currentTab.filterConfig.groups.length > 0) {
      return currentTab.filterConfig.groups;
    }
    // 其次从图源级别的sourceFilterConfig获取
    if (this.sourceFilterConfig && this.sourceFilterConfig.groups.length > 0) {
      return this.sourceFilterConfig.groups;
    }
    return [];
  }

  /**
   * 获取动态筛选组的当前值标签
   */
  private getDynamicFilterLabel(group: FilterGroup): string {
    const currentValue = this.dynamicFilterValues.get(group.id) || group.defaultValue || '';
    const option = group.options.find(o => o.value === currentValue);
    if (option) {
      return option.label;
    }
    // 如果没找到匹配的选项，返回组标题
    return group.title || group.id;
  }

  /**
   * 显示动态筛选选择器
   */
  private showDynamicFilterPicker(group: FilterGroup): void {
    if (!group.options || group.options.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: `${group.title}暂无可选项` });
      return;
    }

    const labels = group.options.map(o => o.label);
    const values = group.options.map(o => o.value);
    const currentValue = this.dynamicFilterValues.get(group.id) || group.defaultValue || '';
    const currentIndex = values.indexOf(currentValue);
    
    // [修复] 在用户选择新值之前，先保存当前的筛选标签
    this.prepareFilterHistoryBeforeChange();

    this.getUIContext().showTextPickerDialog({
      range: labels,
      selected: currentIndex >= 0 ? currentIndex : 0,
      defaultPickerItemHeight: 36,
      canLoop: false,
      onAccept: (value: TextPickerResult) => {
        const selectedValue = values[value.index as number];
        
        // 更新动态筛选值
        const newMap = new Map(this.dynamicFilterValues);
        newMap.set(group.id, selectedValue);
        this.dynamicFilterValues = newMap;
        
        // 同时更新传统的筛选参数（保持向后兼容）
        this.syncLegacyFilterValues(group.id, selectedValue);
        
        // 保存筛选设置并刷新
        this.saveDynamicFilterSettings();
        this.refreshFilterAfterChange();
      }
    });
  }

  /**
   * 同步旧版筛选参数（保持向后兼容）
   */
  private syncLegacyFilterValues(groupId: string, value: string): void {
    // 根据组ID同步到对应的旧版筛选变量
    if (groupId === 'filterOrdering' || groupId === 'sort') {
      this.filterOrdering = value;
    } else if (groupId === 'filterRegion' || groupId === 'region') {
      this.filterRegion = value;
    } else if (groupId === 'filterTheme' || groupId === 'category' || groupId === 'type' || groupId === 'filter_category') {
      this.filterTheme = value;
    }
  }

  /**
   * 保存动态筛选设置
   */
  private async saveDynamicFilterSettings(): Promise<void> {
    try {
      // 保存动态筛选值
      const filterJson = JSON.stringify(Array.from(this.dynamicFilterValues.entries()));
      await this.dataManager.saveUserSetting(String(this.sourceId), 'dynamicFilterValues', filterJson);
      
      // 同时保存旧版筛选参数
      await this.saveFilterSettings();
      
      logger.info(TAG, `动态筛选设置已保存: ${filterJson}`);
    } catch (error) {
      logger.error(TAG, '保存动态筛选设置失败', String(error));
    }
  }

  /**
   * 加载动态筛选设置
   */
  private async loadDynamicFilterSettings(): Promise<void> {
    try {
      const filterJson = await this.dataManager.getUserSetting(String(this.sourceId), 'dynamicFilterValues');
      if (filterJson) {
        const entries = JSON.parse(filterJson) as [string, string][];
        const loadedMap = new Map<string, string>(entries);
        
        // [修复] 验证并清理无效的缓存值
        const cleanedMap = new Map<string, string>();
        let hasInvalidValues = false;
        
        loadedMap.forEach((value: string, key: string) => {
          // 检查 filterRegion 的无效值
          if (key === 'filterRegion' || key === 'region') {
            const validRegions = ['', 'japan', 'korea', 'west', 'finish'];
            if (validRegions.includes(value)) {
              cleanedMap.set(key, value);
            } else {
              logger.warn(TAG, `动态筛选无效值: ${key}=${value}，重置为空`);
              cleanedMap.set(key, '');
              hasInvalidValues = true;
            }
          }
          // 检查 filterTheme 的无效值
          else if (key === 'filterTheme' || key === 'category' || key === 'type') {
            if (value === 'all') {
              logger.warn(TAG, `动态筛选无效值: ${key}=${value}，重置为空`);
              cleanedMap.set(key, '');
              hasInvalidValues = true;
            } else {
              cleanedMap.set(key, value);
            }
          } else {
            cleanedMap.set(key, value);
          }
        });
        
        this.dynamicFilterValues = cleanedMap;
        logger.info(TAG, `动态筛选设置已加载: ${this.dynamicFilterValues.size}个项`);
        
        // 如果有无效值被清理，保存正确的值
        if (hasInvalidValues) {
          const cleanedJson = JSON.stringify(Array.from(cleanedMap.entries()));
          await this.dataManager.saveUserSetting(String(this.sourceId), 'dynamicFilterValues', cleanedJson);
        }
      }
      
      // 同时加载旧版筛选设置
      await this.loadFilterSettings();
    } catch (error) {
      logger.warn(TAG, '加载动态筛选设置失败，使用默认值', String(error));
    }
  }

  /**
   * 获取排序标签
   */
  private getOrderingLabel(): string {
    // 优先从图源配置获取标签
    const orderingGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterOrdering' || g.id === 'sort');
    if (orderingGroup) {
      const option = orderingGroup.options.find(o => o.value === this.filterOrdering);
      if (option) return option.label;
    }
    // 回退到默认标签
    const labels: Record<string, string> = {
      '-datetime_updated': '时间↓',
      'datetime_updated': '时间↑',
      '-popular': '热度↓',
      'popular': '热度↑'
    };
    return labels[this.filterOrdering] || '排序';
  }

  /**
   * 获取地区标签
   */
  private getRegionLabel(): string {
    // 优先从图源配置获取标签
    const regionGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterRegion');
    if (regionGroup) {
      const option = regionGroup.options.find(o => o.value === this.filterRegion);
      if (option) return option.label;
    }
      // 回退到默认标签
    const labels: Record<string, string> = {
      '': '全部地区',
      'japan': '日漫',
      'korea': '韩漫',
      'west': '美漫',
      'finish': '已完结'
    };
    return labels[this.filterRegion] || '地区';
  }

  /**
   * 获取题材标签
   */
  private getThemeLabel(): string {
    // 优先从图源配置获取标签
    const themeGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterTheme' || g.id === 'category');
    if (themeGroup) {
      const option = themeGroup.options.find(o => o.value === this.filterTheme);
      if (option) return option.label;
    }
    // 回退到默认标签
    const labels: Record<string, string> = {
      '': '全部题材',
      'aiqing': '愛情',
      'huanlexiang': '歡樂向',
      'maoxian': '冒險',
      'qihuan': '奇幻',
      'baihe': '百合',
      'xiaoyuan': '校园',
      'kehuan': '科幻',
      'rexue': '热血',
      'gaoxiao': '搞笑'
    };
    return labels[this.filterTheme] || '题材';
  }

  /**
   * 显示排序选择器（动态从图源配置加载）
   */
  private showOrderingPicker(): void {
    // [修复] 在打开选择器前保存当前标签
    this.prepareFilterHistoryBeforeChange();
    
    // 从图源配置获取排序选项
    const orderingGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterOrdering' || g.id === 'sort');
    
    if (orderingGroup && orderingGroup.options.length > 0) {
      const labels = orderingGroup.options.map(o => o.label);
      const values = orderingGroup.options.map(o => o.value);
      const currentIndex = values.indexOf(this.filterOrdering);
      
      this.getUIContext().showTextPickerDialog({
        range: labels,
        selected: currentIndex >= 0 ? currentIndex : 0,
        defaultPickerItemHeight: 36,
        canLoop: false,
        onAccept: (value: TextPickerResult) => {
          this.filterOrdering = values[value.index as number];
          this.saveFilterSettings();
          this.refreshFilterAfterChange();
        }
      });
    } else {
      // 回退到默认选项
      this.getUIContext().showTextPickerDialog({
        range: ['按时间-从新到旧', '按时间-从旧到新', '按热度-从高到低', '按热度-从低到高'],
        selected: ['-datetime_updated', 'datetime_updated', '-popular', 'popular'].indexOf(this.filterOrdering),
        defaultPickerItemHeight: 36,
        canLoop: false,
        onAccept: (value: TextPickerResult) => {
          const values = ['-datetime_updated', 'datetime_updated', '-popular', 'popular'];
          this.filterOrdering = values[value.index as number];
          this.saveFilterSettings();
          this.refreshFilterAfterChange();
        }
      });
    }
  }

  /**
   * 显示地区选择器（动态从图源配置加载）
   */
  private showRegionPicker(): void {
    // [修复] 在打开选择器前保存当前标签
    this.prepareFilterHistoryBeforeChange();
    
    // 从图源配置获取地区选项
    const regionGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterRegion');
    
    if (regionGroup && regionGroup.options.length > 0) {
      const labels = regionGroup.options.map(o => o.label);
      const values = regionGroup.options.map(o => o.value);
      const currentIndex = values.indexOf(this.filterRegion);
      
      this.getUIContext().showTextPickerDialog({
        range: labels,
        selected: currentIndex >= 0 ? currentIndex : 0,
        defaultPickerItemHeight: 36,
        canLoop: false,
        onAccept: (value: TextPickerResult) => {
          this.filterRegion = values[value.index as number];
          this.saveFilterSettings();
          this.refreshFilterAfterChange();
        }
      });
    } else {
      // 回退到默认选项（使用新的空字符串和字符串值）
      this.getUIContext().showTextPickerDialog({
        range: ['全部', '日漫', '韩漫', '美漫', '已完结'],
        selected: ['', 'japan', 'korea', 'west', 'finish'].indexOf(this.filterRegion),
        defaultPickerItemHeight: 36,
        canLoop: false,
        onAccept: (value: TextPickerResult) => {
          const values = ['', 'japan', 'korea', 'west', 'finish'];
          this.filterRegion = values[value.index as number];
          this.saveFilterSettings();
          this.refreshFilterAfterChange();
        }
      });
    }
  }

  /**
   * 显示题材选择器（动态从图源配置加载）
   */
  private showThemePicker(): void {
    // [修复] 在打开选择器前保存当前标签
    this.prepareFilterHistoryBeforeChange();
    
    // 从图源配置获取题材选项
    const themeGroup = this.sourceFilterConfig?.groups.find(g => g.id === 'filterTheme' || g.id === 'category');
    
    if (themeGroup && themeGroup.options.length > 0) {
      const labels = themeGroup.options.map(o => o.label);
      const values = themeGroup.options.map(o => o.value);
      const currentIndex = values.indexOf(this.filterTheme);
      
      this.getUIContext().showTextPickerDialog({
        range: labels,
        selected: currentIndex >= 0 ? currentIndex : 0,
        defaultPickerItemHeight: 36,
        canLoop: false,
        onAccept: (value: TextPickerResult) => {
          this.filterTheme = values[value.index as number];
          this.saveFilterSettings();
          this.refreshFilterAfterChange();
        }
      });
      return;
    }
    
    // 回退到默认选项（使用新的空字符串表示全部）
    const themes: ThemeOption[] = [
      { label: '全部', value: '' },
      { label: '愛情', value: 'aiqing' },
      { label: '歡樂向', value: 'huanlexiang' },
      { label: '冒險', value: 'maoxian' },
      { label: '奇幻', value: 'qihuan' },
      { label: '百合', value: 'baihe' },
      { label: '校园', value: 'xiaoyuan' },
      { label: '科幻', value: 'kehuan' },
      { label: '東方', value: 'dongfang' },
      { label: '耽美', value: 'danmei' },
      { label: '生活', value: 'shenghuo' },
      { label: '格鬥', value: 'gedou' },
      { label: '轻小说', value: 'qingxiaoshuo' },
      { label: '悬疑', value: 'xuanyi' },
      { label: '萌系', value: 'mengxi' },
      { label: '神鬼', value: 'shengui' },
      { label: '职场', value: 'zhichang' },
      { label: '治愈', value: 'zhiyu' },
      { label: '搞笑', value: 'gaoxiao' },
      { label: '竞技', value: 'jingji' },
      { label: '魔幻', value: 'mohuan' },
      { label: '热血', value: 'rexue' },
      { label: '美食', value: 'meishi' },
      { label: '励志', value: 'lizhi' },
      { label: '侦探', value: 'zhentan' },
      { label: '惊悚', value: 'jingsong' },
      { label: '异世界', value: 'yishijie' },
      { label: '战争', value: 'zhanzheng' },
      { label: '历史', value: 'lishi' },
      { label: '都市', value: 'dushi' },
      { label: '穿越', value: 'chuanyue' },
      { label: '重生', value: 'chongsheng' },
      { label: '恐怖', value: 'kongbu' },
      { label: '武侠', value: 'wuxia' }
    ];
    
    const currentIndex = themes.findIndex(t => t.value === this.filterTheme);
    
    this.getUIContext().showTextPickerDialog({
      range: themes.map(t => t.label),
      selected: currentIndex >= 0 ? currentIndex : 0,
      defaultPickerItemHeight: 36,
      canLoop: false,
      onAccept: (value: TextPickerResult) => {
        this.filterTheme = themes[value.index as number].value;
        this.saveFilterSettings();
        this.refreshFilterAfterChange();
      }
    });
  }

  /**
   * 保存筛选设置
   */
  private async saveFilterSettings(): Promise<void> {
    try {
      await this.dataManager.saveUserSetting(String(this.sourceId), 'filterOrdering', this.filterOrdering);
      await this.dataManager.saveUserSetting(String(this.sourceId), 'filterRegion', this.filterRegion);
      await this.dataManager.saveUserSetting(String(this.sourceId), 'filterTheme', this.filterTheme);
      logger.info(TAG, `筛选设置已保存: ordering=${this.filterOrdering}, region=${this.filterRegion}, theme=${this.filterTheme}`);
    } catch (error) {
      logger.error(TAG, '保存筛选设置失败', String(error));
    }
  }

  /**
   * 加载筛选设置
   */
  private async loadFilterSettings(): Promise<void> {
    try {
      const ordering = await this.dataManager.getUserSetting(String(this.sourceId), 'filterOrdering');
      const region = await this.dataManager.getUserSetting(String(this.sourceId), 'filterRegion');
      const theme = await this.dataManager.getUserSetting(String(this.sourceId), 'filterTheme');
      
      if (ordering) this.filterOrdering = ordering;
      
      // [修复] 验证缓存的筛选值是否有效，无效则重置为空字符串
      if (region !== null && region !== undefined) {
        // 检查是否是旧的无效值（如 'all', '0', '1', '2' 等）
        const validRegions = ['', 'japan', 'korea', 'west', 'finish'];
        if (validRegions.includes(region)) {
          this.filterRegion = region;
        } else {
          // 旧值无效，重置为空字符串（表示"全部"）
          logger.warn(TAG, `无效的地区筛选值: ${region}，重置为空`);
          this.filterRegion = '';
          // 保存正确的值
          await this.dataManager.saveUserSetting(String(this.sourceId), 'filterRegion', '');
        }
      }
      
      if (theme !== null && theme !== undefined) {
        // 检查是否是旧的 'all' 值
        if (theme === 'all') {
          // 'all' 是旧的无效值，重置为空字符串
          logger.warn(TAG, `无效的题材筛选值: ${theme}，重置为空`);
          this.filterTheme = '';
          await this.dataManager.saveUserSetting(String(this.sourceId), 'filterTheme', '');
        } else {
          this.filterTheme = theme;
        }
      }
      
      logger.info(TAG, `筛选设置已加载: ordering=${this.filterOrdering}, region=${this.filterRegion}, theme=${this.filterTheme}`);
    } catch (error) {
      logger.warn(TAG, '加载筛选设置失败，使用默认值', String(error));
    }
  }

  /**
   * [修复] 在筛选条件变更前保存当前状态（在用户选择新值之前调用）
   */
  private prepareFilterHistoryBeforeChange(): void {
    if (this.comicList.length > 0) {
      this.pendingFilterHistory = this.comicList.slice(); // 浅拷贝当前结果
      this.pendingFilterLabel = this.getCurrentFilterLabel(); // 在参数变更前获取标签
    }
  }

  /**
   * [修复] 在筛选条件变更后刷新（在用户选择新值之后调用）
   */
  private refreshFilterAfterChange(): void {
    // pendingFilterHistory 和 pendingFilterLabel 已在 prepareFilterHistoryBeforeChange 中保存
    
    // [修复] 清除缓存，确保使用新的筛选参数发起请求
    // 必须清除缓存，否则切换回之前用过的筛选条件时会返回旧的缓存数据
    const newWorkflowKey = this.generateWorkflowKey();
    this.contentCache.clearWorkflow(this.sourceId, newWorkflowKey);
    logger.info(TAG, `刷新筛选，已清除缓存: ${newWorkflowKey}`);
    
    // 显示加载提示
    this.showRefreshHint('正在获取内容...', 'loading');
    
    this.currentPage = 1;
    // 不清空列表，继续显示旧数据直到新数据加载完成
    this.loadComicsWithFilterHint();
  }

  /**
   * 刷新筛选结果（兼容旧调用）
   */
  private refreshFilter(): void {
    // 保存当前结果到待处理队列
    this.prepareFilterHistoryBeforeChange();
    this.refreshFilterAfterChange();
  }

  /**
   * 加载漫画并显示筛选结果提示
   */
  private async loadComicsWithFilterHint(): Promise<void> {
    try {
      await this.loadComics();
      // 加载完成后显示结果提示
      if (this.comicList.length > 0) {
        this.showRefreshHint(`已加载 ${this.comicList.length} 条结果`, 'success');
      } else {
        this.showRefreshHint('未找到匹配内容', 'info');
      }
    } catch (error) {
      logger.error(TAG, '筛选加载失败', String(error));
      this.showRefreshHint('加载失败，请重试', 'error');
    }
  }

  /**
   * 保存指定数据到筛选历史记录
   */
  private saveToFilterHistory(results: ComicInfo[], filterLabel: string): void {
    if (results.length === 0) return;
    
    const historyItem: FilterHistoryItem = {
      id: `history_${Date.now()}`,
      filterLabel: filterLabel || '筛选结果',
      results: results,
      expanded: false,  // 默认折叠
      timestamp: Date.now()
    };
    
    // 添加到历史列表开头
    const newHistory: FilterHistoryItem[] = [historyItem];
    for (let i = 0; i < this.filterHistory.length && newHistory.length < this.MAX_FILTER_HISTORY; i++) {
      newHistory.push(this.filterHistory[i]);
    }
    
    this.filterHistory = newHistory;
    logger.info(TAG, `已保存筛选历史: ${filterLabel}, 共 ${results.length} 条结果`);
  }

  /**
   * 获取当前筛选条件的标签名称
   */
  private getCurrentFilterLabel(): string {
    const labels: string[] = [];
    const filterGroups = this.getDynamicFilterGroups();
    
    if (filterGroups.length > 0) {
      // 使用动态筛选组
      for (const group of filterGroups) {
        const label = this.getDynamicFilterLabel(group);
        if (label && label !== group.title) {
          labels.push(label);
        }
      }
    } else {
      // 使用默认筛选
      const orderingLabel = this.getOrderingLabel();
      const regionLabel = this.getRegionLabel();
      const themeLabel = this.getThemeLabel();
      
      if (orderingLabel !== '排序') labels.push(orderingLabel);
      if (regionLabel !== '地区' && regionLabel !== '全部地区') labels.push(regionLabel);
      if (themeLabel !== '题材' && themeLabel !== '全部题材') labels.push(themeLabel);
    }
    
    return labels.length > 0 ? labels.join(' / ') : '筛选结果';
  }

  /**
   * 切换筛选历史项的展开/折叠状态
   */
  private toggleFilterHistoryExpanded(historyId: string): void {
    logger.info(TAG, `切换筛选历史展开状态: historyId=${historyId}`);
    const newHistory: FilterHistoryItem[] = [];
    for (let i = 0; i < this.filterHistory.length; i++) {
      const item = this.filterHistory[i];
      if (item.id === historyId) {
        const newExpanded = !item.expanded;
        logger.info(TAG, `历史记录 ${historyId} 展开状态: ${item.expanded} -> ${newExpanded}`);
        const updatedItem: FilterHistoryItem = {
          id: item.id,
          filterLabel: item.filterLabel,
          results: item.results,
          expanded: newExpanded,
          timestamp: item.timestamp
        };
        newHistory.push(updatedItem);
      } else {
        newHistory.push(item);
      }
    }
    this.filterHistory = newHistory;
  }

  /**
   * 移除指定的筛选历史记录（带动画）
   */
  private removeFilterHistory(historyId: string): void {
    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.filterHistory = this.filterHistory.filter(item => item.id !== historyId);
    });
  }

  /**
   * 清空所有筛选历史记录
   */
  private clearFilterHistory(): void {
    this.filterHistory = [];
  }

  /**
   * 重试加载内容
   */
  private retryLoadContent(): void {
    logger.info(TAG, `用户点击重试按钮，当前标签: ${this.currentTabId}`);
    
    // 清除当前工作流的缓存，强制从网络重新加载
    const workflowKey = this.generateWorkflowKey();
    this.contentCache.clearWorkflow(this.sourceId, workflowKey);
    logger.info(TAG, `已清除缓存: ${workflowKey}`);
    
    this.currentPage = 1;
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.touchComicContentRender();
    
    // 根据当前标签类型决定调用哪个方法
    if (this.currentTabId === 'search') {
      this.performSearch();
    } else {
      this.loadComics();
    }
  }

  /**
   * 下拉刷新 - 优雅的增量刷新逻辑
   * 1. 保留当前内容，后台获取新数据
   * 2. 比对新旧数据，找出新增项
   * 3. 在顶部插入新增项，带动画效果
   * 4. 显示轻量级提示
   */
  private async onRefresh(): Promise<void> {
    logger.info(TAG, '开始下拉刷新 (优雅模式)');
    
    // 保存当前内容的ID集合，用于比对
    const existingIds = new Set(this.comicList.map(comic => comic.id));
    const existingCount = this.comicList.length;
    
    try {
      // 清除缓存，强制从网络获取最新数据
      const workflowKey = this.generateWorkflowKey();
      this.contentCache.clearWorkflow(this.sourceId, workflowKey);
      logger.info(TAG, `下拉刷新，已清除缓存: ${workflowKey}`);
      
      // 后台获取第一页数据（不清空当前列表）
      let newComics: ComicInfo[] = [];
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        newComics = await this.loadComicsWithWebView();
      } else {
        newComics = await this.loadComicsWithHTTP();
      }
      
      if (newComics.length === 0) {
        // 获取失败或无数据
        this.showRefreshHint('刷新失败，请稍后重试', 'error');
        return;
      }
      
      // 找出新增的漫画（在新数据中存在但不在旧数据中）
      const newItems: ComicInfo[] = [];
      const updatedItems: Map<string, ComicInfo> = new Map();
      
      for (const comic of newComics) {
        if (!existingIds.has(comic.id)) {
          newItems.push(comic);
        } else {
          // 已存在的项，检查是否有更新
          updatedItems.set(comic.id, comic);
        }
      }
      
      logger.info(TAG, `刷新结果: 新增 ${newItems.length} 项, 更新 ${updatedItems.size} 项`);
      
      // 更新缓存
      this.contentCache.set(
        this.sourceId,
        this.currentTabId,
        workflowKey,
        newComics,
        1,
        newComics.length >= 20
      );
      
      if (newItems.length > 0) {
        // 有新内容：使用动画在顶部插入
        animateTo({
          duration: 300,
          curve: Curve.EaseOut
        }, () => {
          // 在顶部插入新项
          this.comicList = [...newItems, ...this.comicList];
          this.comicDataSource.updateItems([...this.comicList]);
          this.touchComicContentRender();
          
          // 后台异步处理封面缓存
          this.processCoverCacheAsync(newItems);
        });
        
        // 显示新增提示
        this.showRefreshHint(`发现 ${newItems.length} 部新漫画`, 'success');
        
        // 滚动到顶部显示新内容
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 300 } });
      } else if (updatedItems.size > 0) {
        // 无新内容但有更新：更新现有项
        this.comicList = this.comicList.map((item: ComicInfo) => updatedItems.get(item.id) || item);
        this.comicDataSource.updateExistingItems(updatedItems);
        this.touchComicContentRender();
        this.showRefreshHint('内容已是最新', 'info');
      } else {
        // 完全无变化
        this.showRefreshHint('内容已是最新', 'info');
      }
      
      // 重置页码和hasMore状态
      this.currentPage = 1;
      this.hasMore = newComics.length >= 20;
      
      logger.info(TAG, '下拉刷新完成');
    } catch (error) {
      logger.error(TAG, '下拉刷新失败', String(error));
      this.showRefreshHint('刷新失败', 'error');
    } finally {
      // 延迟关闭刷新状态，让用户看到刷新动画
      setTimeout(() => {
        this.isRefreshing = false;
      }, 300);
    }
  }
  
  /**
   * 显示刷新提示（轻量级Toast样式）
   */
  private showRefreshHint(message: string, type: 'success' | 'info' | 'error' | 'loading'): void {
    this.refreshHintMessage = message;
    this.refreshHintType = type;
    this.refreshHintVisible = true;
    
    // 淡入动画
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.refreshHintOpacity = 1;
    });
    
    // loading 类型不自动隐藏，需要手动调用其他类型的提示来替换
    if (type !== 'loading') {
      // 2秒后自动淡出并隐藏
      setTimeout(() => {
        animateTo({
          duration: 300,
          curve: Curve.EaseIn
        }, () => {
          this.refreshHintOpacity = 0;
        });
        
        setTimeout(() => {
          this.refreshHintVisible = false;
        }, 300);
      }, 2000);
    }
  }

  /**
   * 构建搜索对话框
   */
  @Builder
  buildSearchDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('搜索漫画')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        // 搜索类型选择器（仅当有多个搜索类型时显示）
        if (this.searchTypes.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.searchTypes, (type: SearchTypeOption) => {
                Button(type.label)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .height(32)
                  .padding({ left: 14, right: 14 })
                  .backgroundColor(this.selectedSearchType === type.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(this.selectedSearchType === type.id
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .borderRadius(16)
                  .onClick(() => {
                    this.selectedSearchType = type.id;
                    this.searchPlaceholder = type.placeholder || '输入搜索内容';
                  })
              }, (type: SearchTypeOption) => type.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        Search({ placeholder: this.searchPlaceholder })
          .width('100%')
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.performSearch();
          })

        Row({ space: 12 }) {
          Button('取消')
            .fontSize(15)
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showSearchDialog = false;
            })

          Button('搜索')
            .fontSize(15)
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.performSearch();
            })
        }
        .width('100%')
      }
      .width('90%')
      .constraintSize({ maxWidth: 560, maxHeight: '86%' })
      .padding(24)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(14)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
      .shadow({ radius: 16, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetY: 6 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    .onClick(() => {
      this.showSearchDialog = false;
    })
  }

  /**
   * 构建登录对话框
   */
  @Builder
  buildLoginDialog() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('登录')
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Button('完成登录')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.completeLogin();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        
        // WebView
        Web({ src: this.loginUrl, controller: this.loginWebViewController })
          .width('100%')
          .height(500)
          .onPageEnd(() => {
            logger.info(TAG, '登录页面加载完成');
          })
      }
      .width('90%')
      .constraintSize({ maxWidth: 760, maxHeight: '90%' })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(14)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
      .shadow({ radius: 16, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetY: 6 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
      .onClick(() => {
        // 阻止事件冒泡，防止关闭对话框（通过空函数实现）
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    .onClick(() => {
      // 点击背景关闭对话框
      this.showLoginDialog = false;
    })
  }

  /**
   * 构建Cloudflare验证对话框
   */
  @Builder
  buildCfVerifyDialog() {
    Column() {
      Column() {
        // 标题栏
        Row() {
          Text('网站验证')
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Button('完成验证')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(async () => {
              logger.info(TAG, '用户确认完成CF验证');
              
              // 【关键】从WebView强制提取并保存Cookie（包括cf_clearance等CF验证Cookie）
              try {
                const baseUrl: string = this.sourceInfo?.baseUrl || '';
                if (baseUrl && this.webViewControllerAttached) {
                  // 使用forceCaptureWebViewCookies强制刷新，不检查现有Cookie
                  const refreshOk = await CookieManager.getInstance().forceCaptureWebViewCookies(
                    this.sourceId, 
                    this.webViewController, 
                    baseUrl
                  );
                  logger.info(TAG, `CF验证后Cookie保存结果: ${refreshOk}`);
                }
              } catch (cookieError) {
                logger.warn(TAG, `CF验证后保存Cookie失败: ${String(cookieError)}`);
              }
              
              this.showCfVerifyDialog = false;
              // 刷新数据
              this.currentPage = 1;
              this.comicList = [];
              this.loadComics();
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        
        // 提示文字
        Text('请在下方完成网站验证（点击复选框），完成后点击"完成验证"按钮')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .padding({ left: 16, right: 16, bottom: 8 })
        
        // WebView - 使用主WebView控制器
        Web({ src: 'about:blank', controller: this.webViewController })
          .width('100%')
          .height(400)
          .onPageEnd(() => {
            logger.info(TAG, 'CF验证页面加载完成');
          })
      }
      .width('90%')
      .constraintSize({ maxWidth: 760, maxHeight: '90%' })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(14)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
      .shadow({ radius: 16, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetY: 6 })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
      .onClick(() => {
        // 阻止事件冒泡
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  /**
   * 构建WebView调试对话框（仅显示标题栏和关闭按钮，WebView内容由主WebView组件显示）
   */
  @Builder
  buildWebViewDebugDialog() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('WebView调试')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button('关闭')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.showWebViewDebugDialog = false;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      
      // 提示文字
      Text('当前WebView显示的页面内容，可用于调试图源解析问题')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .padding({ left: 16, right: 16, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
  }

  /**
   * 构建凭据登录对话框
   */
  @Builder
  buildCredentialLoginDialog() {
    Column() {
      CredentialLoginDialog({
        controller: new CustomDialogController({
          builder: CredentialLoginDialog({
            themeState: this.themeState,
            sourceName: this.sourceName,
            onLogin: (username: string, password: string) => {
              this.handleCredentialLogin(username, password);
            },
            onCancel: () => {
              logger.info(TAG, '用户取消凭据登录');
              this.showCredentialDialog = false;
            }
          }),
          autoCancel: false,
          customStyle: true
        }),
        themeState: this.themeState,
        sourceName: this.sourceName,
        onLogin: (username: string, password: string) => {
          this.handleCredentialLogin(username, password);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消凭据登录');
          this.showCredentialDialog = false;
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    .onClick(() => {
      // 点击背景不关闭对话框（需要用户主动取消）
    })
  }

  /**
   * 获取标签图标
   */
  private getTabIcon(tabId: string): Resource {
    switch (tabId) {
      case 'popular':
        return $r('sys.symbol.flame');
      case 'latest':
        return $r('sys.symbol.clock');
      case 'search':
        return $r('sys.symbol.magnifyingglass');
      case 'filter':
        return $r('sys.symbol.line_3_horizontal');
      case 'favorites':
        return $r('sys.symbol.heart');
      case 'history':
        return $r('sys.symbol.clock_arrow_2_circlepath');
      default:
        return $r('sys.symbol.list_bullet');
    }
  }

  /**
   * 构建标签栏 - VSCode风格（带模式切换按钮）
   */
  @Builder
  buildTabBar() {
    Row({ space: 0 }) {
      // 左侧固定：模式切换按钮
      this.buildDisplayModeButton()
      
      // 右侧：可滚动的标签列表
      Scroll() {
        Row({ space: 0 }) {
          ForEach(this.tabsConfig, (tab: TabConfig) => {
            this.buildTabItem(tab)
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(1)
    }
    .width('100%')
    .height(38)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }

  /**
   * 构建显示模式切换按钮
   */
  @Builder
  buildDisplayModeButton() {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(this.getDisplayModeIcon())
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
    }
    .width(38)
    .height(38)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(0)
    .border({
      width: { right: 1 },
      color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.showDisplayModeMenu = true;
    })
    .bindMenu(this.showDisplayModeMenu, this.buildDisplayModeMenu())
  }

  /**
   * 获取当前显示模式的图标
   */
  private getDisplayModeIcon(): Resource {
    switch (this.displayMode) {
      case DisplayMode.GRID:
        return $r('sys.symbol.square_grid_2x2');
      case DisplayMode.LIST:
        return $r('sys.symbol.list_bullet');
      case DisplayMode.LARGE_COVER:
        return $r('sys.symbol.heart_square_stack_fill');
      default:
        return $r('sys.symbol.square_grid_2x2');
    }
  }

  /**
   * 构建显示模式选择菜单
   */
  @Builder
  buildDisplayModeMenu() {
    Menu() {
      MenuItem({ content: '网格模式' })
        .selected(this.displayMode === DisplayMode.GRID)
        .onClick(() => {
          this.setTabDisplayMode(DisplayMode.GRID);
          this.showDisplayModeMenu = false;
        })
      
      MenuItem({ content: '列表模式' })
        .selected(this.displayMode === DisplayMode.LIST)
        .onClick(() => {
          this.setTabDisplayMode(DisplayMode.LIST);
          this.showDisplayModeMenu = false;
        })
      
      MenuItem({ content: '大封面模式' })
        .selected(this.displayMode === DisplayMode.LARGE_COVER)
        .onClick(() => {
          this.setTabDisplayMode(DisplayMode.LARGE_COVER);
          this.showDisplayModeMenu = false;
        })
    }
  }

  /**
   * 设置当前标签的显示模式并保存
   */
  private setTabDisplayMode(mode: DisplayMode): void {
    this.displayMode = mode;
    // 保存到Map
    const newMap = new Map(this.tabDisplayModes);
    newMap.set(this.currentTabId, mode);
    this.tabDisplayModes = newMap;
    // 显式触发内容重绘，避免首帧或切换后渲染不同步
    this.touchComicContentRender();
    // 异步保存到持久化存储
    this.saveTabDisplayModes();
  }

  /**
   * 加载指定标签的显示模式
   */
  private loadTabDisplayMode(tabId: string): void {
    const savedMode = this.tabDisplayModes.get(tabId);
    if (savedMode !== undefined) {
      this.displayMode = savedMode;
    } else {
      // 默认使用网格模式
      this.displayMode = DisplayMode.GRID;
    }
    this.touchComicContentRender();
  }

  private parseDisplayModeValue(value: string | number | null | undefined): DisplayMode {
    if (value === DisplayMode.GRID || value === 0 || value === '0') {
      return DisplayMode.GRID;
    }
    if (value === DisplayMode.LIST || value === 1 || value === '1') {
      return DisplayMode.LIST;
    }
    if (value === DisplayMode.LARGE_COVER || value === 2 || value === '2') {
      return DisplayMode.LARGE_COVER;
    }
    return DisplayMode.GRID;
  }

  /**
   * 保存所有标签的显示模式
   */
  private async saveTabDisplayModes(): Promise<void> {
    try {
      const modesObj: Record<string, string> = {};
      this.tabDisplayModes.forEach((mode, tabId) => {
        modesObj[tabId] = mode;
      });
      await this.dataManager.saveUserSetting(
        String(this.sourceId),
        'tabDisplayModes',
        JSON.stringify(modesObj)
      );
      logger.debug(TAG, `已保存标签显示模式: ${JSON.stringify(modesObj)}`);
    } catch (error) {
      logger.warn(TAG, '保存标签显示模式失败', String(error));
    }
  }

  /**
   * 加载所有标签的显示模式
   */
  private async loadAllTabDisplayModes(): Promise<void> {
    try {
      const modesJson = await this.dataManager.getUserSetting(
        String(this.sourceId),
        'tabDisplayModes'
      );
      if (modesJson) {
        const modesObj = JSON.parse(modesJson) as Record<string, string | number | null | undefined>;
        const newMap = new Map<string, DisplayMode>();
        Object.keys(modesObj).forEach(tabId => {
          const modeValue: string | number | null | undefined = modesObj[tabId];
          newMap.set(tabId, this.parseDisplayModeValue(modeValue));
        });
        this.tabDisplayModes = newMap;
        logger.debug(TAG, `已加载标签显示模式: ${this.tabDisplayModes.size}个`);
      }
    } catch (error) {
      logger.warn(TAG, '加载标签显示模式失败', String(error));
    }
  }

  /**
   * 保存上次访问的标签
   */
  private async saveLastVisitedTab(tabId: string): Promise<void> {
    try {
      await this.dataManager.saveUserSetting(
        String(this.sourceId),
        'lastVisitedTab',
        tabId
      );
    } catch (error) {
      logger.warn(TAG, '保存上次访问标签失败', String(error));
    }
  }

  /**
   * 加载上次访问的标签
   */
  private async loadLastVisitedTab(): Promise<string | null> {
    try {
      return await this.dataManager.getUserSetting(
        String(this.sourceId),
        'lastVisitedTab'
      );
    } catch (error) {
      logger.warn(TAG, '加载上次访问标签失败', String(error));
      return null;
    }
  }

  /**
   * 构建标签项 - VSCode风格
   */
  @Builder
  buildTabItem(tab: TabConfig) {
    Row() {
      // 标签图标
      SymbolGlyph(this.getTabIcon(tab.id))
        .fontSize(14)
        .fontColor([this.currentTabId === tab.id
          ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        .margin({ right: 6 })

      // 标签名称
      Text(tab.name)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentTabId === tab.id
          ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 100 })

      // 搜索标签显示关闭按钮
      if (tab.type === TabType.SEARCH) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(18)
        .height(18)
        .backgroundColor(Color.Transparent)
        .borderRadius(4)
        .margin({ left: 6 })
        .onClick(() => {
          this.closeSearchTab();
        })
      }
    }
    .padding({ left: 12, right: 12, top: 0, bottom: 0 })
    .height(38)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.currentTabId === tab.id
      ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
      : Color.Transparent)
    .border({
      width: { top: this.currentTabId === tab.id ? 2 : 0, bottom: 0, left: 0, right: 0 },
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.switchToTab(tab.id);
    })
    .animation({ duration: 150 })
  }

  /**
   * 关闭搜索标签
   */
  private closeSearchTab(): void {
    // 如果当前在搜索标签，先切换到第一个标签
    if (this.currentTabId === 'search' && this.tabsConfig.length > 1) {
      const firstNonSearchTab = this.tabsConfig.find(t => t.type !== TabType.SEARCH);
      if (firstNonSearchTab) {
        this.switchToTab(firstNonSearchTab.id);
      }
    }
    
    // 移除搜索标签
    this.removeSearchTab();
  }

  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Column({ space: 8 }) {
      // 搜索类型选择器（仅当有多个搜索类型时显示）
      if (this.searchTypes.length > 1) {
        Row({ space: 8 }) {
          ForEach(this.searchTypes, (type: SearchTypeOption) => {
            Button(type.label)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .height(28)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.selectedSearchType === type.id
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.selectedSearchType === type.id
                ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .borderRadius(14)
              .onClick(() => {
                this.selectedSearchType = type.id;
                this.searchPlaceholder = type.placeholder || '输入搜索内容';
              })
          }, (type: SearchTypeOption) => type.id)
        }
        .width('100%')
      }

      // 搜索输入框
      Row({ space: 8 }) {
        Search({ placeholder: this.searchPlaceholder })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
          .onSubmit(() => {
            this.performSearch();
          })

        Button('搜索')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onClick(() => {
            this.performSearch();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建空状态视图
   */
  @Builder
  buildEmptyView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.telescope_fill'))
        .fontSize(50)
        .opacity(0.3)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])


      Text('暂无内容')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      // 重试按钮
      Button('重试')
        .fontSize(14)
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.retryLoadContent();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建筛选历史记录项（可折叠）
   */
  @Builder
  buildFilterHistoryItem(historyItem: FilterHistoryItem) {
    Column() {
      // 折叠头部 - 显示筛选条件和结果数量
      Row() {
        // 展开/折叠图标
        SymbolGlyph(historyItem.expanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          .animation({ duration: 200, curve: Curve.EaseInOut })
        
        // 历史图标
        SymbolGlyph($r('sys.symbol.clock_arrow_2_circlepath'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          .margin({ left: 8 })
        
        // 筛选条件标签
        Text(historyItem.filterLabel)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 8 })
        
        // 结果数量标签
        Text(`${historyItem.results.length}条`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ left: 8 })
        
        // 删除按钮
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(24)
        .height(24)
        .backgroundColor(Color.Transparent)
        .borderRadius(12)
        .margin({ left: 8 })
        .onClick(() => {
          // 设置标志防止事件冒泡到Row的onClick
          this.isDeleteButtonClicked = true;
          this.removeFilterHistory(historyItem.id);
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 12 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(historyItem.expanded ? { topLeft: 12, topRight: 12 } : 12)
      .onClick(() => {
        // 检查是否是删除按钮触发的事件冒泡
        if (this.isDeleteButtonClicked) {
          this.isDeleteButtonClicked = false;
          return;
        }
        this.toggleFilterHistoryExpanded(historyItem.id);
      })
      
      // 展开的内容 - 显示历史结果列表
      if (historyItem.expanded) {
        Column() {
          // 根据显示模式选择不同的布局
          if (this.displayMode === DisplayMode.LIST) {
            // 列表模式
            ForEach(historyItem.results, (comic: ComicInfo) => {
              this.buildComicListItem(comic)
            }, (comic: ComicInfo) => `history_${historyItem.id}_${comic.id}`)
          } else {
            // 网格模式
            if (this.displayMode === DisplayMode.GRID) {
              Column() {
                this.buildAdaptiveCoverGrid(historyItem.results, `history_${historyItem.id}`)
              }
              .padding(this.isLandscape ? { left: 8, right: 8, top: 12, bottom: 12 } : { left: 4, right: 4, top: 8, bottom: 8 })
            } else {
              Grid() {
                ForEach(historyItem.results, (comic: ComicInfo) => {
                  GridItem() {
                    this.buildComicLargeCoverCard(comic)
                  }
                }, (comic: ComicInfo) => `history_${historyItem.id}_${comic.id}`)
              }
              .columnsTemplate(this.getGridColumnsTemplate())
              .columnsGap(this.isLandscape ? 16 : 12)
              .rowsGap(this.isLandscape ? 16 : 12)
              .width('100%')
              .layoutDirection(GridDirection.Row)
              .padding(this.isLandscape ? { left: 8, right: 8, top: 12, bottom: 12 } : { left: 4, right: 4, top: 8, bottom: 8 })
            }
          }
        }
        .width('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius({ bottomLeft: 12, bottomRight: 12 })
        .padding({ top: 8, bottom: 8 })
        // [修复] 展开和收起都有动画
        .transition(
          TransitionEffect.asymmetric(
            // 展开动画：淡入 + 从上向下滑入
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ y: -20 }).animation({ duration: 200, curve: Curve.EaseOut })),
            // 收起动画：淡出 + 向上滑出
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 150, curve: Curve.EaseIn }))
          )
        )
      }
    }
    .width('100%')
    .margin({ bottom: 12 })
    // [修复] 整个卡片的动画（用于删除时）
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
  }

  /**
   * 构建筛选历史列表
   */
  @Builder
  buildFilterHistoryList() {
    if (this.filterHistory.length > 0 && this.shouldShowFilterOptions()) {
      Column() {
        // 历史记录列表
        // 注意：key 函数包含 expanded 状态，确保展开/折叠时触发重新渲染
        ForEach(this.filterHistory, (item: FilterHistoryItem) => {
          this.buildFilterHistoryItem(item)
        }, (item: FilterHistoryItem) => `${item.id}_${item.expanded}`)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })
    }
  }

  /**
   * 构建搜索歧义选择对话框
   */
  @Builder
  buildAmbiguousDialog() {
    Column() {
      // 半透明背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showAmbiguousDialog = false;
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)

    // 对话框内容
    Column() {
      Text('请选择搜索类型')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })

      Text(`输入的数字 "${this.ambiguousId}" 可能是：`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .margin({ bottom: 24 })

      // 作品ID按钮
      Button('作品ID')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .margin({ bottom: 12 })
        .onClick(() => {
          this.handleAmbiguousAsMangaId();
        })

      // 作者ID按钮
      Button('作者ID')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })
        .onClick(() => {
          this.handleAmbiguousAsAuthorId();
        })

      // 关键词搜索按钮
      Button('按关键词搜索')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .onClick(() => {
          this.handleAmbiguousAsKeyword();
        })
    }
    .width('80%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(14)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .shadow({ radius: 16, color: ThemeAwareHelper.getTestManagementThemedColor('shadow_black', this.themeState.currentTheme), offsetY: 6 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
      .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
    .position({ x: '10%', y: '30%' })
  }

  /**
   * 构建漫画网格/列表
   */
  @Builder
  buildComicGrid(renderVersion: number) {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll(this.scroller) {
          Column() {
          // 筛选历史记录（可折叠）
          this.buildFilterHistoryList()
          
          // 根据显示模式选择不同的布局
          if (this.displayMode === DisplayMode.LIST) {
            // 列表模式
            List({ space: 0 }) {
              ForEach(this.comicList, (comic: ComicInfo) => {
                ListItem() {
                  this.buildComicListItem(comic)
                }
              }, (comic: ComicInfo) => `${renderVersion}_${comic.id}`)
            }
            .width('100%')
            .padding(this.isLandscape ? { left: 24, right: 24, top: 12, bottom: 12 } : { left: 12, right: 12, top: 8, bottom: 8 })
          } else {
            // 网格模式和大封面模式
            if (this.displayMode === DisplayMode.GRID) {
              Grid() {
                ForEach(this.comicList, (comic: ComicInfo) => {
                  GridItem() {
                    this.buildComicCard(comic)
                  }
                }, (comic: ComicInfo) => `${renderVersion}_${comic.id}`)
              }
              .columnsTemplate(this.getGridColumnsTemplate())
              .columnsGap(this.isLandscape ? 16 : 12)
              .rowsGap(this.isLandscape ? 16 : 12)
              .width('100%')
              .layoutDirection(GridDirection.Row)
              .padding(this.isLandscape ? { left: 24, right: 24, top: 16, bottom: 16 } : 16)
            } else {
              Grid() {
                ForEach(this.comicList, (comic: ComicInfo) => {
                GridItem() {
                    this.buildComicLargeCoverCard(comic)
                }
                }, (comic: ComicInfo) => `${renderVersion}_${comic.id}`)
              }
              .columnsTemplate(this.getGridColumnsTemplate())
              .columnsGap(this.isLandscape ? 16 : 12)
              .rowsGap(this.isLandscape ? 16 : 12)
              .width('100%')
              .layoutDirection(GridDirection.Row)
              .padding(this.isLandscape ? { left: 24, right: 24, top: 16, bottom: 16 } : 16)
            }
          }

          if (this.isLoading && this.currentPage > 1) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

              Text('加载更多...')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ left: 8 })
            }
            .width('100%')
            .height(60)
            .justifyContent(FlexAlign.Center)
          }

          if (!this.hasMore && this.comicList.length > 0) {
            Text('已加载全部内容')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
              .height(60)
              .textAlign(TextAlign.Center)
              .padding({ top: 20, bottom: 20 })
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.loadMore();
      })
    }
    .onRefreshing(() => {
      this.onRefresh();
    })
    .width('100%')
    .height('100%')

      // 刷新提示浮层
      if (this.refreshHintVisible) {
        Row() {
          if (this.refreshHintType === 'loading') {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          } else if (this.refreshHintType === 'success') {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          } else if (this.refreshHintType === 'error') {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor(['#FF4444'])
          } else {
            SymbolGlyph($r('sys.symbol.info_circle_fill'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
          }

          Text(this.refreshHintMessage)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .margin({ left: 8 })
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .shadow({
          radius: 8,
          color: 'rgba(0,0,0,0.15)',
          offsetX: 0,
          offsetY: 2
        })
        .margin({ top: 16 })
        .opacity(this.refreshHintOpacity)
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建下拉刷新内容
   */
  @Builder
  buildRefreshContent() {
    Row() {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      
      Text('正在刷新...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .margin({ left: 8 })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  /**
   * 构建漫画卡片
   */
  /**
   * Adaptive cover grid in normal grid mode.
   */
  @Builder
  private buildAdaptiveCoverGrid(comics: ComicInfo[], keyPrefix: string) {
    Column({ space: this.isLandscape ? 16 : 12 }) {
      ForEach(this.buildAdaptiveCoverRows(comics, keyPrefix), (row: AdaptiveCoverRow) => {
        Row({ space: this.isLandscape ? 16 : 12 }) {
          ForEach(row.items, (item: AdaptiveCoverRowItem) => {
            Column() {
              this.buildComicCard(item.comic)
            }
            .layoutWeight(item.span)
          }, (item: AdaptiveCoverRowItem) => `${row.key}_${item.comic.id}`)

          if (row.usedSpan < this.getAdaptiveGridColumnCount()) {
            Blank()
              .layoutWeight(this.getAdaptiveGridColumnCount() - row.usedSpan)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (row: AdaptiveCoverRow) => row.key)
    }
    .width('100%')
  }

  /**
   * Build a standard comic card.
   */
  @Builder
  buildComicCard(comic: ComicInfo) {
    Column({ space: 8 }) {
      // 封面容器 - 使用Stack实现加载动画效果
      Stack() {
        // 封面 - 横屏时高度为屏幕高度的一半，宽度自适应
        if (this.isLandscape && this.screenHeight > 0) {
          Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
            .width('100%')
            .height('100%')
            .borderRadius(0)
            .objectFit(ImageFit.Contain)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .onAppear(() => {
              this.loadCoverPixelMap(comic);
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        } else {
          // 竖屏时使用原有样式
          Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
            .width('100%')
            .height('100%')
            .borderRadius(0)
            .objectFit(ImageFit.Contain)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .onAppear(() => {
              this.loadCoverPixelMap(comic);
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .aspectRatio(this.getComicCoverAspectRatio(comic))
      .padding(4)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({ width: 1, color: this.getCoverFrameBorderColor() })

      // 标题 - 固定高度确保卡片一致
      Text(comic.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(40)
        .lineHeight(20)

      // 作者 - 固定高度确保卡片一致
      Text(comic.author || ' ')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(16)
    }
    .width('100%')
    .padding(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .shadow({
      radius: 8,
      color: '#10000000',
      offsetX: 0,
      offsetY: 2
    })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }
  
  /**
   * 构建列表模式的漫画项
   */
  @Builder
  buildComicListItem(comic: ComicInfo) {
    Row({ space: 12 }) {
      // 封面 - 精致的封面卡片
      Stack() {
        Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
          .width(72)
          .aspectRatio(0.72)
          .borderRadius(0)
          .objectFit(ImageFit.Contain)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onAppear(() => {
            this.loadCoverPixelMap(comic);
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
      }
      .padding(3)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({ width: 1, color: this.getCoverFrameBorderColor() })
      .shadow({
        radius: 6,
        color: '#15000000',
        offsetX: 0,
        offsetY: 2
      })

      // 信息区域
      Column({ space: 4 }) {
        // 标题
        Text(comic.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .lineHeight(21)

        // 作者
        if (comic.author) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.person_crop_circle_dashed'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            Text(comic.author)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }

        // 状态标签
        if (comic.status) {
          Row() {
            Text(String(comic.status))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
              .borderRadius(4)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)

      // 右侧箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(12)
    .margin({ top: 4, bottom: 4 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: -20 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  /**
   * 构建大封面模式的漫画卡片
   */
  @Builder
  buildComicLargeCoverCard(comic: ComicInfo) {
    Column({ space: 10 }) {
      // 大封面 - 添加加载动画
      Stack() {
        Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
          .width('100%')
          .height('100%')
          .borderRadius(0)
          .objectFit(ImageFit.Contain)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onAppear(() => {
            this.loadCoverPixelMap(comic);
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
      }
      .width('100%')
      .aspectRatio(this.getComicCoverAspectRatio(comic))
      .padding(4)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({ width: 1, color: this.getCoverFrameBorderColor() })

      // 标题
      Text(comic.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .lineHeight(22)

      // 作者
      Text(comic.author || ' ')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
    .shadow({
      radius: 12,
      color: '#15000000',
      offsetX: 0,
      offsetY: 4
    })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
    .onClick(() => {
      this.openComicDetail(comic);
    })
  }

  /**
   * 更新设备方向状态
   */
  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    this.screenHeight = deviceInfo.screenHeight;
    logger.info(TAG, `设备方向初始化: ${this.isLandscape ? '横屏' : '竖屏'}, 屏幕高度: ${this.screenHeight}`);
  }
  
  /**
   * 获取Grid列模板（根据显示模式和横竖屏自适应）
   */
  private getGridColumnsTemplate(): string {
    if (this.displayMode === DisplayMode.LARGE_COVER) {
      // 大封面模式：一行两个
      return '1fr 1fr';
    } else if (this.isLandscape) {
      // 网格模式 - 横屏：5列
      return '1fr 1fr 1fr 1fr 1fr';
    } else {
      // 网格模式 - 竖屏：3列
      return '1fr 1fr 1fr';
    }
  }
}
