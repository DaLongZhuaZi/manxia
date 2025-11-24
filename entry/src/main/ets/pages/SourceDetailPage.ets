/**
 * 图源详情页面
 * 显示图源的热门、最新、搜索等内容
 * 参考Mihon和Komikku的设计
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { logger } from '../Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import { DataManager } from '../Framework/Data/DataManager';
import { MangaSourceEngine, SearchResult, EngineResult, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { MangaSourceConfig, MangaInfo, AntiCrawlerConfig } from '../Framework/WebView/MangaSourceTypes';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { TabConfig, TabType, SourceTabsConfig, getDefaultTabsConfig, filterTabsByLoginStatus, sortTabs } from '../Framework/WebView/TabConfig';
import { MangaDetailPageParams } from './MangaDetailPage';
import { SourceSettingsPageParams } from './SourceSettingsPage';
import CookieManager from '../Framework/Managers/CookieManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { image } from '@kit.ImageKit';
import { ImageCacheManager, LoadOptions, RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { AppNotificationManager } from '../Framework/Managers/NotificationManager';

const TAG = 'SourceDetailPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 导航参数接口
 */
interface SourceDetailParams {
  sourceId: number;
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

@Component
export struct SourceDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  @State themeState: ThemeAwareState = new ThemeAwareState();
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
  @State showLoginDialog: boolean = false; // 显示登录对话框
  @State isLoggedIn: boolean = false; // 登录状态
  @State userAvatarUrl: string = ''; // 用户头像URL
  @State filterOrdering: string = '-datetime_updated'; // 筛选排序
  @State filterRegion: string = 'all'; // 筛选地区
  @State filterTheme: string = 'all'; // 筛选题材

  private sourceId: number = 0;
  private sourceName: string = '';
  private sourceManager: SourceManager = SourceManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `SourceDetailPage_${Date.now()}`;
  private scroller: Scroller = new Scroller();
  @State comicDataSource: ComicListDataSource = new ComicListDataSource([]);
  @State private coverPixelMaps: Map<string, image.PixelMap> = new Map();
  
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

    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 获取路由参数 - 从NavPathStack获取
    const params: ESObject[] = this.pathStack.getParamByName('SourceDetailPage') as ESObject[];
    if (params && params.length > 0) {
      const param: ESObject = params[0] as ESObject;
      if (param && param.sourceId) {
        this.sourceId = param.sourceId as number;
        logger.info(TAG, `加载图源详情，ID: ${this.sourceId}`);
        
        // 异步初始化
        this.initializeAsync();
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
   * 异步初始化
   */
  private async initializeAsync(): Promise<void> {
    try {
      // 首先加载 sourceName（用于页面跳转参数传递）
      await this.loadSourceName();
      
      // 加载图源信息
      await this.loadSourceInfo();
      
      // 检测图源类型并初始化相应系统
      await this.detectAndInitializeSourceType();
      
      // 如果使用WebView，等待控制器附加
      if (this.useWebView) {
        logger.info(TAG, '等待WebView控制器附加...');
        await this.waitForWebViewReady();
        await this.loadBaseUrlAndCookieBootstrap();
      }
      
      // 加载标签页配置
      await this.loadTabsConfig();
      
      // 加载筛选设置
      await this.loadFilterSettings();
      
      // 加载漫画列表
      await this.loadComics();
    } catch (error) {
      logger.error(TAG, '初始化失败', String(error));
    }
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
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
   * 加载漫画列表
   */
  private async loadComics(): Promise<void> {
    if (this.isLoading) return;

    try {
      this.isLoading = true;
      let comics: ComicInfo[] = [];

      // 根据图源类型选择加载方式
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        logger.info(TAG, '使用WebView系统加载漫画列表');
        comics = await this.loadComicsWithWebView();
      } else {
        logger.info(TAG, '使用HTTP系统加载漫画列表');
        comics = await this.loadComicsWithHTTP();
      }

      // [核心修改] 先更新数据，立即显示列表
      if (this.currentPage === 1) {
        this.comicList = comics;
      } else {
        this.comicList = [...this.comicList, ...comics];
      }

      // 后台异步处理封面缓存（不阻塞UI）
      this.processCoverCacheAsync(comics);
      this.hasMore = comics.length >= 20;
      this.comicDataSource.updateItems(this.comicList);
      logger.info(TAG, `数据源已刷新: ${this.comicList.length} 条数据`);

    } catch (error) {
      logger.error(TAG, '加载漫画列表失败', String(error));
    } finally {
      this.isLoading = false;
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

      // 降低并发数，避免超时
      const MAX_CONCURRENT = 3;
      let downloadedCount = 0;
      
      for (let i = 0; i < needDownload.length; i += MAX_CONCURRENT) {
        const batch = needDownload.slice(i, i + MAX_CONCURRENT);
        
        // 等待当前批次完成，然后刷新UI
        const batchPromises = batch.map((comic: ComicInfo) => {
          const coverUrl: string = comic.coverUrl || '';
          return coverCache.downloadAndCacheCover(
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
            return savedPath;
          }).catch((error: Error) => {
            logger.debug(TAG, `后台封面下载失败 ${comic.title}: ${String(error)}`);
            return null;
          });
        });
        
        await Promise.allSettled(batchPromises);
        
        // 批次间短暂延迟，避免瞬间大量请求
        if (i + MAX_CONCURRENT < needDownload.length) {
          await new Promise<void>((resolve: (value: void) => void) => {
            setTimeout(() => resolve(), 100);
          });
        }
      }

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
        const pm = await imageSource.createPixelMap({ desiredSize: { width: 160, height: 220 } });
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
      
      const configJson = JSON.stringify(config);
      await this.mangaSourceEngine.loadConfig(configJson);
      
      this.webViewReady = true;
      logger.info(TAG, 'WebView引擎初始化成功');
    } catch (error) {
      logger.error(TAG, 'WebView引擎初始化失败', String(error));
      this.useWebView = false;
      this.webViewReady = false;
    }
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

  private async loadCoverPixelMap(comic: ComicInfo): Promise<void> {
    try {
      const url: string = comic.coverUrl || '';
      if (url.length === 0) { return; }
      
      // 优先使用CoverCacheManager的本地缓存
      const coverCache = CoverCacheManager.getInstance();
      const localPath = await coverCache.getLocalCoverPath(this.sourceId, comic.id);
      
      // 如果有本地缓存，直接从本地加载
      if (localPath) {
        try {
          const imageSource = image.createImageSource(localPath);
          const pm = await imageSource.createPixelMap({ desiredSize: { width: 160, height: 220 } });
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
            result = await this.mangaSourceEngine.getFiltered(
              this.currentPage,
              params.ordering || this.filterOrdering,
              params.region || this.filterRegion,
              params.theme || this.filterTheme
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
      // 从URL路径中提取ID（如 /comic/466 -> 466）
      let comicId = manga.id || '';
      if (comicId.includes('/')) {
        const parts = comicId.split('/');
        comicId = parts[parts.length - 1]; // 取最后一部分
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
   * 切换标签页
   */
  private async switchToTab(tabId: string): Promise<void> {
    if (this.currentTabId === tabId) return;

    this.currentTabId = tabId;
    this.currentPage = 1;
    this.comicList = [];
    this.hasMore = true;
    await this.loadComics();
  }

  /**
   * 判断是否应该显示筛选选项
   */
  private shouldShowFilterOptions(): boolean {
    const currentTab = this.tabsConfig.find(t => t.id === this.currentTabId);
    if (!currentTab) return false;
    return currentTab.type === TabType.FILTER || currentTab.type === TabType.CUSTOM;
  }

  /**
   * 加载标签页配置
   */
  private async loadTabsConfig(): Promise<void> {
    try {
      // 检查登录状态
      this.isLoggedIn = await this.dataManager.isSourceLoggedIn(this.sourceId);
      logger.info(TAG, `登录状态: ${this.isLoggedIn}`);

      // 加载标签配置
      const configJson = await this.dataManager.getSourceTabsConfig(this.sourceId);
      let config: SourceTabsConfig;

      if (configJson) {
        config = JSON.parse(configJson) as SourceTabsConfig;
        logger.info(TAG, `已加载标签配置: ${config.tabs.length}个标签`);
      } else {
        // 使用默认配置
        config = getDefaultTabsConfig(this.sourceId);
        logger.info(TAG, '使用默认标签配置');
      }

      // 过滤并排序标签
      this.tabsConfig = sortTabs(
        filterTabsByLoginStatus(
          config.tabs.filter(t => t.enabled),
          this.isLoggedIn
        )
      );

      logger.info(TAG, `最终标签列表: ${this.tabsConfig.map(t => t.name).join(', ')}`);

      // 设置默认标签
      if (this.tabsConfig.length > 0 && !this.currentTabId) {
        this.currentTabId = this.tabsConfig[0].id;
      }
    } catch (error) {
      logger.error(TAG, '加载标签配置失败', String(error));
      // 使用默认配置
      const defaultConfig = getDefaultTabsConfig(this.sourceId);
      this.tabsConfig = sortTabs(defaultConfig.tabs);
      if (this.tabsConfig.length > 0) {
        this.currentTabId = this.tabsConfig[0].id;
      }
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
        this.getUIContext().getPromptAction().showToast({ message: '该图源不支持登录' });
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
   * 执行搜索
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword.trim()) {
      logger.warn(TAG, '搜索关键词为空');
      return;
    }

    this.showSearchDialog = false;
    this.isLoading = true;
    this.comicList = [];
    
    try {
      let comics: ComicInfo[] = [];
      
      if (this.useWebView && this.webViewReady && this.mangaSourceEngine) {
        logger.info(TAG, `使用WebView系统搜索: 关键词="${this.searchKeyword}"`);
        const result = await this.mangaSourceEngine.searchManga(this.searchKeyword, 1);
        if (result && result.success && result.data) {
          comics = this.convertMangaInfoToComicInfo(result.data.mangas);
        }
      } else {
        logger.info(TAG, `使用HTTP系统搜索: 关键词="${this.searchKeyword}"`);
        comics = await this.sourceManager.search(this.sourceId, this.searchKeyword, 1, 20);
      }
      
      this.comicList = comics;
      this.comicDataSource.updateItems(this.comicList);
      logger.info(TAG, `搜索完成，找到 ${comics.length} 个结果`);
    } catch (error) {
      logger.error(TAG, '搜索失败', String(error));
    } finally {
      this.isLoading = false;
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
   * 打开漫画详情
   */
  private openComicDetail(comic: ComicInfo): void {
    const params: MangaDetailPageParams = {
      sourceId: this.sourceId,
      mangaId: comic.id
    };
    this.pathStack.pushPathByName('MangaDetailPage', params);
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
            this.buildComicGrid()

            // 2. 中层：空状态视图
            // 仅在非加载中且数据为空时覆盖显示
            if (!this.isLoading && this.comicList.length === 0) {
              // 包裹一层背景色，防止透视到底层的 Grid（虽然此时 Grid 应该是空的）
              Column() {
                this.buildEmptyView()
              }
              .width('100%')
              .height('100%')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
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
        }
        .width('100%')
        .height('100%')

        // 隐藏的WebView组件（仅在使用WebView系统时渲染）
        if (this.useWebView) {
          Web({
            src: (this.sourceInfo && this.sourceInfo.baseUrl) ? this.sourceInfo.baseUrl : 'about:blank',
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

        // 登录对话框
        if (this.showLoginDialog) {
          this.buildLoginDialog()
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
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
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
                icon: $r('app.media.ic_search_selected'),
                isEnabled: true,
                action: () => {
                  this.showSearchDialog = true;
                }
              }
            },
            {
              content: {
                label: this.isLoggedIn ? '重新登录' : '登录',
                icon: this.isLoggedIn && this.userAvatarUrl ? this.userAvatarUrl : $r('app.media.ic_user_avatar'),
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
                label: '设置',
                icon: $r('app.media.ic_settings'),
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
   * 构建筛选选项
   */
  @Builder
  buildFilterOptions() {
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

  /**
   * 获取排序标签
   */
  private getOrderingLabel(): string {
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
    const labels: Record<string, string> = {
      'all': '全部地区',
      '0': '日漫',
      '1': '韩漫',
      '2': '美漫'
    };
    return labels[this.filterRegion] || '地区';
  }

  /**
   * 获取题材标签
   */
  private getThemeLabel(): string {
    const labels: Record<string, string> = {
      'all': '全部题材',
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
   * 显示排序选择器
   */
  private showOrderingPicker(): void {
    this.getUIContext().showTextPickerDialog({
      range: ['按时间-从新到旧', '按时间-从旧到新', '按热度-从高到低', '按热度-从低到高'],
      selected: ['-datetime_updated', 'datetime_updated', '-popular', 'popular'].indexOf(this.filterOrdering),
      defaultPickerItemHeight: 36,
      canLoop: false,
      onAccept: (value: TextPickerResult) => {
        const values = ['-datetime_updated', 'datetime_updated', '-popular', 'popular'];
        this.filterOrdering = values[value.index as number];
        this.saveFilterSettings();
        this.refreshFilter();
      }
    });
  }

  /**
   * 显示地区选择器
   */
  private showRegionPicker(): void {
    this.getUIContext().showTextPickerDialog({
      range: ['全部', '日漫', '韩漫', '美漫'],
      selected: ['all', '0', '1', '2'].indexOf(this.filterRegion),
      defaultPickerItemHeight: 36,
      canLoop: false,
      onAccept: (value: TextPickerResult) => {
        const values = ['all', '0', '1', '2'];
        this.filterRegion = values[value.index as number];
        this.saveFilterSettings();
        this.refreshFilter();
      }
    });
  }

  /**
   * 显示题材选择器
   */
  private showThemePicker(): void {
    const themes: ThemeOption[] = [
      { label: '全部', value: 'all' },
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
        this.refreshFilter();
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
      if (region) this.filterRegion = region;
      if (theme) this.filterTheme = theme;
      
      logger.info(TAG, `筛选设置已加载: ordering=${this.filterOrdering}, region=${this.filterRegion}, theme=${this.filterTheme}`);
    } catch (error) {
      logger.warn(TAG, '加载筛选设置失败，使用默认值', String(error));
    }
  }

  /**
   * 刷新筛选结果
   */
  private refreshFilter(): void {
    this.currentPage = 1;
    this.comicList = [];
    this.loadComics();
  }

  /**
   * 重试加载内容
   */
  private retryLoadContent(): void {
    logger.info(TAG, '用户点击重试按钮');
    this.currentPage = 1;
    this.comicList = [];
    this.comicDataSource.updateItems([]);
    this.loadComics();
  }

  /**
   * 下拉刷新
   */
  private async onRefresh(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    
    logger.info(TAG, '开始下拉刷新');
    this.isRefreshing = true;
    
    try {
      // 重置到第一页
      this.currentPage = 1;
      this.comicList = [];
      this.comicDataSource.updateItems([]);
      
      // 重新加载内容
      await this.loadComics();
      
      logger.info(TAG, '下拉刷新完成');
    } catch (error) {
      logger.error(TAG, '下拉刷新失败', String(error));
    } finally {
      // 延迟一点时间再关闭刷新状态，让用户看到刷新动画
      setTimeout(() => {
        this.isRefreshing = false;
      }, 500);
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
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Search({ placeholder: '输入漫画名称' })
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
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showSearchDialog = false;
            })

          Button('搜索')
            .fontSize(15)
            .layoutWeight(1)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onClick(() => {
              this.performSearch();
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(24)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Button('完成登录')
            .fontSize(14)
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
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
      .onClick(() => {
        // 阻止事件冒泡，防止关闭对话框（通过空函数实现）
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // 点击背景关闭对话框
      this.showLoginDialog = false;
    })
  }

  /**
   * 构建标签栏
   */
  @Builder
  buildTabBar() {
    Scroll() {
      Row({ space: 16 }) {
        ForEach(this.tabsConfig, (tab: TabConfig) => {
          this.buildTabItem(tab)
        })
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(48)
    .backgroundColor(Color.Transparent)
  }

  /**
   * 构建标签项
   */
  @Builder
  buildTabItem(tab: TabConfig) {
    Column() {
      Text(tab.name)
        .fontSize(15)
        .fontWeight(this.currentTabId === tab.id ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTabId === tab.id ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      // 指示器
      if (this.currentTabId === tab.id) {
        Divider()
          .width(24)
          .height(3)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .margin({ top: 4 })
      }
    }
    .padding({ left: 8, right: 8 })
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchToTab(tab.id);
    })
  }

  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      Search({ placeholder: '搜索漫画' })
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchKeyword = value;
        })
        .onSubmit(() => {
          this.performSearch();
        })

      Button('搜索')
        .fontSize(14)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .onClick(() => {
          this.performSearch();
        })
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
      Image($r('app.media.ic_empty'))
        .width(80)
        .height(80)
        .opacity(0.3)

      Text('暂无内容')
        .fontSize(15)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      // 重试按钮
      Button('重试')
        .fontSize(14)
        .padding({ left: 24, right: 24, top: 8, bottom: 8 })
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
   * 构建漫画网格
   */
  @Builder
  buildComicGrid() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll(this.scroller) {
        Column() {
          Grid() {
            LazyForEach(this.comicDataSource, (comic: ComicInfo, index: number) => {
              GridItem() {
                this.buildComicCard(comic)
              }
            }, (comic: ComicInfo) => comic.id)
          }
          .columnsTemplate(this.getGridColumnsTemplate())
          .columnsGap(this.isLandscape ? 16 : 12)
          .rowsGap(this.isLandscape ? 16 : 12)
          .width('100%')
          .padding(this.isLandscape ? { left: 24, right: 24, top: 16, bottom: 16 } : 16)

          if (this.isLoading && this.currentPage > 1) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

              Text('加载更多...')
                .fontSize(13)
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
  @Builder
  buildComicCard(comic: ComicInfo) {
    Column({ space: 8 }) {
      // 封面 - 横屏时高度为屏幕高度的一半，宽度自适应
      if (this.isLandscape && this.screenHeight > 0) {
        Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
          .height(this.screenHeight * 0.5)
          .aspectRatio(0.7)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onAppear(() => {
            this.loadCoverPixelMap(comic);
          })
      } else {
        // 竖屏时使用原有样式
        Image(this.coverPixelMaps.has(comic.id) ? (this.coverPixelMaps.get(comic.id) as image.PixelMap) : $r('app.media.ic_placeholder'))
          .width('100%')
          .aspectRatio(0.7)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .onAppear(() => {
            this.loadCoverPixelMap(comic);
          })
      }

      // 标题
      Text(comic.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .lineHeight(20)

      // 作者
      if (comic.author) {
        Text(comic.author)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
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
   * 获取Grid列模板（根据横竖屏自适应）
   */
  private getGridColumnsTemplate(): string {
    if (this.isLandscape) {
      // 横屏：5列
      return '1fr 1fr 1fr 1fr 1fr';
    } else {
      // 竖屏：3列
      return '1fr 1fr 1fr';
    }
  }
}
