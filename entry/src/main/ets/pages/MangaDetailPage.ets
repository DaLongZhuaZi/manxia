import { SafeFileUtils } from '../Utils/SafeFileUtils';
import { SafeUtils } from '../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/pages/MangaDetailPage.ets
// 职责: 漫画详情页面，展示漫画的详细信息、章节列表等内容（含收藏持久化）

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { Popup } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';
import { AnimatedComponent } from '../Framework/Animation/AnimatedComponent';
import { AnimationType } from '../Framework/Animation/GlobalAnimationSystem';
import { logger } from '../Utils/Logger';
import { TimeUtils } from '../Framework/Utils/TimeUtils';
import {
  Manga,
  MangaChapter,
  MangaBookmark,
  ReadingProgress,
  ImageSourceType,
  ReadingMode,
  ReadingDirection,
  MangaPage
} from '../Models/MangaModels';
import { DEFAULT_READING_SETTINGS, ReadingSettings } from '../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus, StatusConverter } from '../Framework/Types/StatusEnums';
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { DataManager, ComicInfo, ComicInfoInput, ChapterInfo as DataChapterInfo, ChapterInfoInput, PageInfo, PageInfoInput, ReadHistory, OnlineChapterInfoInput, OnlinePageInfoInput, OnlineComicInfo, OnlineComicSourceSaveInput } from '../Framework/Data/DataManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { colorMap } from '../Data/ResourceMap';
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { openMangaReaderInIsolatedAbility } from '../Framework/Reader/MangaReaderAbilityLauncher';
import { DataService } from '../Framework/Services/DataService';
import { MangaSettingsPageParams } from './MangaSettingsPage';
import { GlobalSearchPageParams } from './GlobalSearchPage';
import { startBookOpenTransition, startBookOpenTransitionWithComponentId, setReaderReady } from '../components/BookTransitionOverlay';
import { CoverPosition } from '../components/BookOpenTransition';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { MangaSourceEngine, EngineResult, MangaDetailWithChapters } from '../Framework/WebView/MangaSourceEngine';
import { MangaInfo, ChapterInfo as WebViewChapterInfo, PageInfo as SourcePageInfo } from '../Framework/WebView/MangaSourceTypes';
import { WebViewDataCacheManager } from '../Framework/Cache/WebViewDataCacheManager';
import { ChapterPreloadManager, ChapterInfo } from '../Framework/Preload/ChapterPreloadManager';

import { LengthMetrics, curves, UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { LabelUtils } from '../Utils/LabelUtils';
import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import webview from '@ohos.web.webview';
import { DatabaseRecord, ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { DatabaseManager } from '../Framework/Database/DatabaseManager';
import { OnlineImageLoader, RequestHeaderEntry as OnlineRequestHeaderEntry, RequestHeaders as OnlineRequestHeaders } from '../Framework/Cache/OnlineImageLoader';
import { promptAction } from '@kit.ArkUI';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';
import { AvifImage } from '../components/AvifImage';

const TAG: string = 'MangaDetailPage';

// 动画参数接口定义
interface AnimateParam {
  duration: number;
  curve: Curve;
  delay?: number;
  iterations?: number;
  playMode?: PlayMode;
}
// 定义漫画详情页面标题栏最小高度
const TITLE_BAR_HEIGHT_MINI: number = 56;
// 定义漫画详情页面封面图片最大高度
const COVER_IMAGE_HEIGHT: number = 180; // 最大高度边界
const COVER_IMAGE_WIDTH: number = 120;  // 最大宽度边界
const DEFAULT_COVER_ASPECT_RATIO: number = COVER_IMAGE_WIDTH / COVER_IMAGE_HEIGHT; // 默认封面宽高比

// 基础尺寸结构体接口（用于严格类型约束）
interface Size2D {
  width: number;
  height: number;
}

/**
 * 导航参数接口
 */
export interface MangaDetailPageParams {
  sourceId?: number;  // 新增：图源ID
  sourcePkg?: string;
  mangaId: string;
  chapterId?: string;
  fromPage?: string;
  cachedCoverPath?: string;  // 新增：已缓存的封面路径
  cachedTitle?: string;      // 新增：已缓存的漫画标题（从列表页面传递）
  cachedCover?: string;      // 新增：已缓存的封面URL（从列表页面传递）
}


/**
 * 导航路径参数接口
 */
export interface NavigationPathParam {
  mangaId: string;
  chapterId?: string;
  fromPage?: string;
}

/**
 * 导航路径接口
 */
export interface NavigationPath {
  name: string;
  param: NavigationPathParam;
}

interface MangaDetailSourceHeaderMap {
  Referer?: string;
  referer?: string;
  Origin?: string;
  origin?: string;
  Accept?: string;
  accept?: string;
  Cookie?: string;
  cookie?: string;
  Authorization?: string;
  authorization?: string;
  UserAgent?: string;
  userAgent?: string;
  AcceptLanguage?: string;
  acceptLanguage?: string;
  CacheControl?: string;
  cacheControl?: string;
  Pragma?: string;
  pragma?: string;
  SecFetchDest?: string;
  secFetchDest?: string;
  SecFetchMode?: string;
  secFetchMode?: string;
  SecFetchSite?: string;
  secFetchSite?: string;
  CachePartition?: string;
  cachePartition?: string;
}

class MangaDetailNormalizedHeaders {
  userAgent: string = '';
  referer: string = '';
  origin: string = '';
  accept: string = '';
  cookie: string = '';
  authorization: string = '';
  acceptLanguage: string = '';
  cacheControl: string = '';
  pragma: string = '';
  secFetchDest: string = '';
  secFetchMode: string = '';
  secFetchSite: string = '';
  cachePartition: string = '';
}

interface MangaDetailSourceNetworkConfig {
  headers?: MangaDetailSourceHeaderMap;
}

interface MangaDetailSourceHeaderConfig {
  network?: MangaDetailSourceNetworkConfig;
  imageHeaders?: MangaDetailSourceHeaderMap;
  coverHeaders?: MangaDetailSourceHeaderMap;
}

/**
 * 章节排序方式枚举
 */
enum ChapterSortOrder {
  ASCENDING = 'asc',
  DESCENDING = 'desc'
}

enum ChapterSortKey {
  CHAPTER_NUMBER = 'chapter',
  PUBLISH_TIME = 'time'
}

enum KnownSourceNames {
  KOMIIC = 'komiic'
}

/**
 * 章节过滤状态枚举
 */
enum ChapterFilterType {
  ALL = 'all',
  UNREAD = 'unread',
  DOWNLOADED = 'downloaded',
  BOOKMARKED = 'bookmarked'
}

/**
 * 章节显示模式枚举
 */
enum ChapterDisplayMode {
  LIST = 'list',
  GRID = 'grid'
}

/**
 * ChapterInfo到MangaChapter转换接口
 * 用于修复未类型化对象字面量错误
 */
interface ChapterInfoToMangaChapterConverter {
  id: string;
  title: string;
  chapterNumber: number;
  publishedAt: number;
  isDownloaded: boolean;
  downloadPath?: string;
  sourceUrl: string;
  translatedLanguage: string;
  scanlationGroup: string;
  uploader: string;
  version: number;
  readableAt: number;
  publishDate: number | Date;
  language: string;
  downloadStatus: DownloadStatus;
  downloadProgress: number;
  pages: MangaPage[];
  externalId?: string;  // [修复] WebView图源的外部章节ID
}

/**
 * 章节阅读进度信息接口
 */
interface ChapterProgressInfo {
  chapterId: string;
  totalPages: number;
  currentPageIndex: number; // -1 表示未开始
  lastReadTime: number; // 毫秒时间戳
}

/**
 * 阅读恢复目标接口
 * 定义恢复阅读时需要传递到阅读页面的目标章节与页码
 */
interface ResumeTarget {
  chapterId: string;
  pageIndex: number;
}

/**
 * 章节懒加载数据源 - 实现ArkUI的IDataSource接口，供LazyForEach使用
 */
class MangaChapterDataSource implements IDataSource {
  private chapters: MangaChapter[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(chapters: MangaChapter[]) {
    this.chapters = chapters;
  }

  totalCount(): number {
    return this.chapters.length;
  }

  getData(index: number): MangaChapter {
    return this.chapters[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    const exists: boolean = this.listeners.indexOf(listener) >= 0;
    if (!exists) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  setChapters(chapters: MangaChapter[]): void {
    this.chapters = chapters;
    this.notifyDataReload();
  }

  // 数据源变更通知 - ArkUI要求在数据变化时通知列表进行刷新
  private notifyDataReload(): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    for (const listener of listenersSnapshot) {
      listener.onDataReloaded();
    }
  }

  private notifyDataAdd(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    for (const listener of listenersSnapshot) {
      listener.onDataAdd(index);
    }
  }

  private notifyDataChange(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    for (const listener of listenersSnapshot) {
      listener.onDataChange(index);
    }
  }

  private notifyDataDelete(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    for (const listener of listenersSnapshot) {
      listener.onDataDelete(index);
    }
  }
}

/**
 * 漫画详情页组件
 * 参考Mihon和Komikku的设计，提供现代化的漫画详情展示界面
 */
@Component
struct MangaDetailPage {
  // 主题管理导航相关
  @State pathStack: NavPathStack = new NavPathStack();
  private lifecycle = new PageLifecycleManager('MangaDetailPage', { enableDebug: true });
  @State pageParams: MangaDetailPageParams | null = null;

  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `MangaDetailPage_${Date.now()}`;
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  
  // 字体相关状态
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // 数据服务
  private dataService: DataService = DataService.getInstance();
  
  // WebView支持
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private mangaEngine: MangaSourceEngine | null = null;
  private cacheManager: WebViewDataCacheManager = WebViewDataCacheManager.getInstance();
  private webViewController: webview.WebviewController = new webview.WebviewController();
  @State private useWebView: boolean = false;
  @State private sourceId: number = 0;
  @State private sourceName: string = '';
  @State private accessDenied: boolean = false;
  @State private coverHttpHeaders: OnlineRequestHeaders = {} as OnlineRequestHeaders; // 封面图片加载的HTTP headers
  private sourcePkg: string = '';
  private photos18CoverPartition: string = 'photos18_detail_cover';



  // 漫画数据
  @State currentManga: Manga | null = null;
  @State isLoading: boolean = true;
  @State loadError: string = '';
  @State isLocalManga: boolean = false;
  @State mangaIsNSFW: boolean = false;  // NSFW状态

  // 章节管理
  @State filteredChapters: MangaChapter[] = [];
  @State chapterSortOrder: ChapterSortOrder = ChapterSortOrder.DESCENDING;
  @State chapterSortKey: ChapterSortKey = ChapterSortKey.CHAPTER_NUMBER;
  @State chapterFilter: ChapterFilterType = ChapterFilterType.ALL;
  @State selectedChapters: Set<string> = new Set();
  @State showDownloadOptions: boolean = false;
  @State showDeleteOptions: boolean = false;
  @State isSelectionMode: boolean = false;
  @State showSortOptions: boolean = false;
  @State showFilterOptions: boolean = false;
  
  // 章节图片数量查询缓存
  private chapterPageCountCache: Set<string> = new Set();

  // UI状态
  @State showChapterOptions: boolean = false;
  @State scrollOffset: number = 0;
  @State coverImageLoaded: boolean = false;
  @State coverDisplayWidth: number = COVER_IMAGE_WIDTH;
  @State coverDisplayHeight: number = COVER_IMAGE_HEIGHT;
  @State coverPixelMap: image.PixelMap | null = null; // 使用PixelMap加载封面（支持headers）
  @State isChapterLoading: boolean = true;
  @State expandDescription: boolean = false;
  @State retryCount: number = 0;
  @State maxRetries: number = 3;
  @State loadingTimeout: number = 10000; // 10秒超时

  private isLoadInProgress: boolean = false;
  private isDisposed: boolean = false;
  private loadTimeoutTimerId: number = 0;
  private loadDelayTimerId: number = 0;
  private retryTimerId: number = 0;
  private silentRefreshTimerId: number = 0;
  private entranceAnimTimerId: number = 0;
  private downloadProgressListenerId: string = '';  // 下载进度监听器ID
  @State chapterDownloadProgress: Map<string, number> = new Map();  // 章节下载进度

  

  private clearAllTimers(): void {
    if (this.loadTimeoutTimerId) {
      clearTimeout(this.loadTimeoutTimerId);
      this.loadTimeoutTimerId = 0;
    }
    if (this.loadDelayTimerId) {
      clearTimeout(this.loadDelayTimerId);
      this.loadDelayTimerId = 0;
    }
    if (this.retryTimerId) {
      clearTimeout(this.retryTimerId);
      this.retryTimerId = 0;
    }
    if (this.silentRefreshTimerId) {
      clearTimeout(this.silentRefreshTimerId);
      this.silentRefreshTimerId = 0;
    }
    if (this.entranceAnimTimerId) {
      clearTimeout(this.entranceAnimTimerId);
      this.entranceAnimTimerId = 0;
    }
  }

  private canScheduleLoad(): boolean {
    if (this.isDisposed) {
      return false;
    }
    if (this.isLoadInProgress) {
      return false;
    }
    return true;
  }

  private isKomiicSource(): boolean {
    const name: string = this.sourceName ? this.sourceName.toLowerCase() : '';
    return name.indexOf(KnownSourceNames.KOMIIC) >= 0;
  }

  private shouldPrefetchPagesForSource(): boolean {
    // [修复] WebView图源禁用页面预取，因为：
    // 1. WebView阅读器需要JavaScript动态加载，预取无法获取真实图片
    // 2. 预取会导致大量无用的页面导航，严重影响性能
    // 3. 页面列表应该在用户真正阅读时才获取
    if (this.mangaEngine) {
      logger.info(TAG, '🚫 WebView图源禁用页面预取');
      return false;
    }
    return true;
  }
  @State isRefreshing: boolean = false; // 下拉刷新状态
  @State isPullRefreshing: boolean = false; // 下拉刷新UI状态
  // 已废弃：阅读设置面板显隐（改为跳转设置页面）
  // @State showSettingsPanel: boolean = false;

  // 章节阅读进度列表
  @State chapterProgressList: ChapterProgressInfo[] = [];

  // 章节懒加载数据源
  private chapterDataSource: MangaChapterDataSource = new MangaChapterDataSource([]);

  // 动画相关
  @State private uiContext: UIContext | undefined = undefined;
  // 返回后静默刷新标志，避免全屏遮罩阻塞交互
  private isSilentRefresh: boolean = false;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  // 设备方向检测
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  
  // 章节显示模式（横屏模式下使用）
  @State private chapterDisplayMode: ChapterDisplayMode = ChapterDisplayMode.LIST;
  @State private currentBreakpoint: Breakpoint = Breakpoint.SM;

  async aboutToAppear(): Promise<void> {
    logger.lifecycle(TAG, 'aboutToAppear 开始');
    this.isDisposed = false;

    // 获取UI上下文
    this.uiContext = this.getUIContext();

    // 初始化主题状态 - 使用实际显示的主题
    try {
      const actualTheme = await this.themeManager.getActualTheme();
      this.themeState.updateTheme(actualTheme);
      logger.debug(TAG, `主题状态已初始化: ${actualTheme}`);
    } catch (error) {
      logger.error(TAG, `主题初始化失败: ${String(error)}`);
      // 使用同步方法作为备选
      this.themeState.updateTheme(this.themeManager.getCurrentThemeSync());
    }

    // 设置主题变化监听器
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.debug(TAG, `主题变化: ${this.themeState.currentTheme} -> ${newTheme}`);
      this.themeState.updateTheme(newTheme);
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
    
    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    
    // 初始化WebView控制器（用于网络漫画）
    try {
      this.webViewManager.setGlobalWebViewController(this.webViewController);
      logger.info(TAG, 'WebView控制器已初始化');
    } catch (error) {
      logger.warn(TAG, `WebView控制器初始化失败: ${String(error)}`);
    }

    // 在入场动画前刷新封面显示尺寸
    this.refreshCoverSize().catch((err: Error) => {
      logger.warn(TAG, `刷新封面尺寸失败: ${err.message}`);
    });

    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 注册设备方向变化监听器
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      logger.info(TAG, `设备方向变化: ${deviceInfo.isLandscape ? '横屏' : '竖屏'}, 断点: ${deviceInfo.breakpoint}`);
      this.isLandscape = deviceInfo.isLandscape;
      this.currentBreakpoint = deviceInfo.breakpoint;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);

    // 注册下载进度监听器
    this.registerDownloadProgressListener();

    // 启动入场动画序列
    this.entranceAnimTimerId = setTimeout((): void => {
      this.startEntranceAnimations();
    }, 100);
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    this.lifecycle.destroy();
    this.isDisposed = true;
    this.isLoading = false;
    this.clearAllTimers();

    // 停止预加载任务
    ChapterPreloadManager.getInstance().stopPreload();
    logger.info(TAG, '已停止章节预加载');

    // 清理主题变化监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
      this.themeChangeCallback = null;
      logger.debug(TAG, '主题变化监听器已清理');
    }
    
    // 清理字体感知
    FontAwareHelper.cleanupFontAware(this.componentId);

    // 清理设备方向监听器
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
      logger.debug(TAG, '设备方向监听器已清理');
    }

    // 取消下载进度监听器
    this.unregisterDownloadProgressListener();
  }

  onPageShow(): void {
    logger.lifecycle(TAG, 'onPageShow');
    
    // 重新关联WebView控制器（修复：返回后再进入导致WebView失效）
    if (this.useWebView && this.mangaEngine) {
      try {
        this.webViewManager.setGlobalWebViewController(this.webViewController);
        logger.info(TAG, 'WebView控制器已重新关联');
      } catch (error) {
        logger.warn(TAG, `WebView控制器重新关联失败: ${String(error)}`);
      }
    }
    
    const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
    if (stack) {
      this.pathStack = stack;
      const paramList = this.pathStack.getParamByName('MangaDetailPage') as MangaDetailPageParams[];
      if (paramList && paramList.length > 0) {
        const latestParam = paramList[paramList.length - 1] as MangaDetailPageParams;
        if (latestParam && Object.keys(latestParam).includes('mangaId')) {
          this.pageParams = latestParam;
        }
      }
    }

    if (this.pageParams && this.pageParams.mangaId) {
      this.loadError = '';
      this.isSilentRefresh = true;
      this.silentRefreshTimerId = setTimeout((): void => {
        if (!this.canScheduleLoad()) {
          this.isSilentRefresh = false;
          return;
        }
        this.loadMangaData()
          .then(() => {
            logger.debug(TAG, '静默刷新完成');
          })
          .catch((error: Error) => {
            logger.error(TAG, `静默刷新失败: ${error.message}`);
          })
          .finally(() => {
            this.isSilentRefresh = false;
          });
      }, 50);
    }
  }

  /**
   * 启动入场动画序列
   */
  private startEntranceAnimations(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext未初始化，跳过动画');
      return;
    }

    // 封面图片动画
    const coverAnimateOptions: AnimateParam = {
      duration: 600,
      delay: 0,
      curve: Curve.EaseOut
    };

    this.uiContext.animateTo(coverAnimateOptions, () => {
      this.coverImageLoaded = true;
    });

    // 内容区域动画
    const contentAnimateOptions: AnimateParam = {
      duration: 500,
      delay: 200,
      curve: Curve.EaseInOut
    };

    this.uiContext.animateTo(contentAnimateOptions, () => {
      // 只有在没有开始数据加载时才设置为false
      if (!this.pageParams) {
        this.isLoading = false;
      }
    });
  }

  /**
   * 判断图片路径来源类型
   */
  private detectImageSourceType(path: string): ImageSourceType {
    const src: string = path;
    if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
      return ImageSourceType.NETWORK;
    }
    if (src.indexOf('$rawfile(') === 0) {
      return ImageSourceType.RAWFILE;
    }
    return ImageSourceType.LOCAL;
  }

  /**
   * 规范化用于 UI 显示的图片路径：本地文件补充 file:// 前缀，并记录详细诊断日志
   */
  private normalizeDisplayPath(rawPath: string, sourceType: ImageSourceType): string {
    if (!rawPath || rawPath.length === 0) {
      return '';
    }
    let displayPath: string = rawPath;
    if (sourceType === ImageSourceType.LOCAL) {
      const hasScheme: boolean = rawPath.indexOf('file://') === 0;
      if (!hasScheme) {
        displayPath = 'file://' + rawPath;
      }
      // 仅用于日志的轻量存在性检查，避免 UI 失败时无上下文
      try {
        const actualPath: string = hasScheme ? rawPath.substring(7) : rawPath;
        const stat: fs.Stat = SafeFileUtils.statSync(actualPath);
        logger.debug(TAG, `封面路径规范化成功: raw='${rawPath}', display='${displayPath}', size=${stat.size}`);
      } catch (statErr) {
        logger.warn(TAG, `封面路径规范化检查失败: raw='${rawPath}', display='${displayPath}', 原始错误=${String(statErr)}`);
      }
    } else {
      logger.debug(TAG, `封面路径来源类型=${sourceType}, 原样使用路径: '${rawPath}'`);
    }
    return displayPath;
  }

  /**
   * 提供封面图片的 UI 渲染源：返回规范化后的路径、PixelMap或资源占位图
   */
  getCoverImageSourceForUI(): string | ResourceStr | image.PixelMap {
    // 优先使用PixelMap（通过OnlineImageLoader加载的带headers的图片）
    if (this.coverPixelMap) {
      return this.coverPixelMap;
    }
    const mg: Manga | null = this.currentManga;
    if (mg && mg.coverImagePath && mg.coverImagePath.length > 0 && mg.coverSourceType !== undefined) {
      const normalized: string = this.normalizeDisplayPath(mg.coverImagePath as string, mg.coverSourceType as ImageSourceType);
      if (normalized.length > 0) {
        return normalized;
      }
    }
    return $r('app.media.mangabook');
  }

  /**
   * 用于日志的封面显示路径（规范化后的字符串），若使用资源占位返回空字符串
   */
  private getCoverDisplayPathForLog(): string {
    const mg: Manga | null = this.currentManga;
    if (mg && mg.coverImagePath && mg.coverImagePath.length > 0 && mg.coverSourceType !== undefined) {
      return this.normalizeDisplayPath(mg.coverImagePath as string, mg.coverSourceType as ImageSourceType);
    }
    return '';
  }

  /**
   * 在封面缺失时，尝试用第一章第一页作为封面回退
   */
  private async ensureCoverImageFromData(comicInfo: ComicInfo, chapterInfos: DataChapterInfo[]): Promise<void> {
    if (!this.currentManga) {
      return;
    }

    const hasCover: boolean = comicInfo.coverUrl !== undefined && comicInfo.coverUrl !== null && comicInfo.coverUrl.length > 0;
    if (hasCover) {
      this.currentManga.coverImagePath = comicInfo.coverUrl;
      this.currentManga.coverSourceType = this.detectImageSourceType(comicInfo.coverUrl);
      return;
    }

    if (chapterInfos.length === 0) {
      logger.warn(TAG, '无章节数据，无法回退封面');
      return;
    }

    try {
      const firstChapterId: string = chapterInfos[0].id;
      const pages: PageInfo[] = await DataManager.getInstance().getChapterPages(firstChapterId);
      if (pages.length > 0) {
        const firstPage: PageInfo = pages[0];
        const pagePath: string = firstPage.localPath && firstPage.localPath.length > 0 ? firstPage.localPath : firstPage.imageUrl;
        this.currentManga.coverImagePath = pagePath;
        this.currentManga.coverSourceType = this.detectImageSourceType(pagePath);
        logger.info(TAG, '封面缺失，已使用第一页图片作为回退封面');
        await this.refreshCoverSize();
      } else {
        logger.warn(TAG, '第一页图片不存在，保持默认封面资源');
      }
    } catch (pageError) {
      logger.error(TAG, `获取章节页失败，无法设置回退封面: ${String(pageError)}`);
    }
  }

  /**
   * 读取图片分辨率以计算宽高比（仅处理本地文件）；其他来源使用默认比例
   */
  private async getImageAspectRatio(path: string, sourceType: ImageSourceType): Promise<number | null> {
    if (sourceType === ImageSourceType.LOCAL) {
      let file: fs.File | null = null;
      try {
        const hasScheme: boolean = path.indexOf('file://') === 0;
        const actualPath: string = hasScheme ? path.substring(7) : path;
        file = SafeFileUtils.openSync(actualPath, fs.OpenMode.READ_ONLY);
        const src: image.ImageSource = image.createImageSource(file.fd);
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        logger.debug(TAG, `读取本地封面分辨率成功: ${w}x${h}, path='${path}'`);
        if (w > 0 && h > 0) {
          return w / h;
        } else {
          logger.warn(TAG, `读取到无效分辨率: ${w}x${h}, 使用默认比例`);
        }
      } catch (metaErr) {
        const msg: string = metaErr instanceof Error ? metaErr.message : String(metaErr);
        logger.error(TAG, `读取封面分辨率失败（LOCAL），原始错误: ${msg}, path='${path}'`);
      } finally {
        if (file) {
          try {
            SafeFileUtils.closeSync(file);
          } catch (closeErr) {
            const closeMsg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
            logger.warn(TAG, `关闭文件描述符失败: ${closeMsg}`);
          }
        }
      }
      return null;
    }

    if (sourceType === ImageSourceType.RAWFILE || sourceType === ImageSourceType.NETWORK) {
      try {
        const src: image.ImageSource = image.createImageSource(path);
        const info: image.ImageInfo = await src.getImageInfo();
        const w: number = info.size.width;
        const h: number = info.size.height;
        logger.debug(TAG, `读取封面分辨率成功(${sourceType}): ${w}x${h}, path='${path}'`);
        if (w > 0 && h > 0) {
          return w / h;
        }
      } catch (metaErr2) {
        const msg2: string = metaErr2 instanceof Error ? metaErr2.message : String(metaErr2);
        logger.warn(TAG, `读取封面分辨率失败(${sourceType})，原始错误: ${msg2}, path='${path}'`);
      }
    }
    return null;
  }

  /**
   * 根据宽高比在边界内计算显示尺寸（Contain）
   */
  private computeDisplaySize(aspect: number): Size2D {
    const maxW: number = COVER_IMAGE_WIDTH;
    const maxH: number = COVER_IMAGE_HEIGHT;
    const heightByWidth: number = Math.round(maxW / aspect);
    if (heightByWidth <= maxH) {
      return { width: maxW, height: heightByWidth } as Size2D;
    }
    const widthByHeight: number = Math.round(maxH * aspect);
    logger.debug(TAG, `根据宽高比计算显示尺寸: ${widthByHeight}x${maxH}`);
    return { width: widthByHeight, height: maxH } as Size2D;
  }

  /**
   * 刷新封面显示尺寸，优先使用实际分辨率，否则使用默认比例
   * 对于网络图片，直接使用OnlineImageLoader预加载（支持AVIF格式）
   */
  private async refreshCoverSize(): Promise<void> {
    let aspect: number = DEFAULT_COVER_ASPECT_RATIO;
    const mg: Manga | null = this.currentManga;
    if (mg && mg.coverImagePath && mg.coverImagePath.length > 0 && mg.coverSourceType !== undefined) {
      const coverUrl = mg.coverImagePath as string;
      
      // 对于网络图片，直接使用OnlineImageLoader预加载（支持AVIF等特殊格式）
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        try {
          await this.loadCoverWithHeaders(coverUrl);
          // 如果成功加载了PixelMap，尺寸已在loadCoverWithHeaders中设置
          if (this.coverPixelMap) {
            return;
          }
        } catch (e) {
          logger.warn(TAG, `预加载网络封面失败，回退到Image组件: ${e}`);
        }
      }
      
      const computed: number | null = await this.getImageAspectRatio(coverUrl, mg.coverSourceType as ImageSourceType);
      if (computed !== null) {
        aspect = computed;
      }
    }
    const size: Size2D = this.computeDisplaySize(aspect);
    this.coverDisplayWidth = size.width;
    this.coverDisplayHeight = size.height;
  }

  /**
   * 从章节标题中提取数字（支持阿拉伯数字和中文数字）
   */
  private extractChapterNumber(title: string): number {
    if (!title) return 0;
    
    // 尝试提取阿拉伯数字
    const arabicMatch = title.match(/\d+/);
    if (arabicMatch) {
      return parseInt(arabicMatch[0], 10);
    }
    
    // 尝试提取中文数字
    interface ChineseNumberMapping {
      char: string;
      value: number;
    }
    
    const chineseNumbers: ChineseNumberMapping[] = [
      { char: '一', value: 1 } as ChineseNumberMapping,
      { char: '二', value: 2 } as ChineseNumberMapping,
      { char: '三', value: 3 } as ChineseNumberMapping,
      { char: '四', value: 4 } as ChineseNumberMapping,
      { char: '五', value: 5 } as ChineseNumberMapping,
      { char: '六', value: 6 } as ChineseNumberMapping,
      { char: '七', value: 7 } as ChineseNumberMapping,
      { char: '八', value: 8 } as ChineseNumberMapping,
      { char: '九', value: 9 } as ChineseNumberMapping,
      { char: '十', value: 10 } as ChineseNumberMapping
    ];
    
    for (let i = 0; i < chineseNumbers.length; i++) {
      if (title.includes(chineseNumbers[i].char)) {
        return chineseNumbers[i].value;
      }
    }
    
    return 0;
  }

  /**
   * 加载章节阅读进度数据（总页数 + 最近阅读到的页）
   * 优化：批量查询所有章节的页面信息，避免N次数据库查询
   */
  private async loadChapterProgressData(): Promise<void> {
    const mangaRef: Manga | null = this.currentManga;
    if (!mangaRef) {
      return;
    }

    const chapters: MangaChapter[] = mangaRef.chapters;
    const dm: DataManager = DataManager.getInstance();
    
    logger.info(TAG, `开始加载章节进度数据，共${chapters.length}个章节`);
    
    // [修复] 对于在线漫画，使用online_read_history表
    let historyList: ReadHistory[] = [];
    try {
      if (this.pageParams?.sourceId) {
        // 在线漫画：查询online_read_history表
        const onlineHistoryRecords = await dm.getOnlineReadHistoryByComic(mangaRef.id);
        logger.debug(TAG, `获取到当前在线漫画的阅读历史记录数: ${onlineHistoryRecords.length}`);
        // 转换为ReadHistory格式
        historyList = onlineHistoryRecords.map(record => {
          const history: ReadHistory = {
            id: record.id,
            userId: 'default_user',
            comicId: record.comicId,
            chapterId: record.chapterId,
            pageIndex: record.pageIndex,
            readTime: record.readTime,
            readDuration: 0  // 在线漫画阅读历史没有readDuration字段，设为0
          };
          return history;
        });
      } else {
        // 本地漫画：查询read_history表
        historyList = await dm.getReadHistoryByComic(mangaRef.id, 'default_user', 1000);
        logger.debug(TAG, `获取到当前本地漫画的阅读历史记录数: ${historyList.length}`);
      }
    } catch (err) {
      logger.warn(TAG, `获取阅读历史失败: ${String(err)}`);
    }

    // 批量查询所有章节的页面数量，避免逐章节并发查询造成数据库风暴
    const pageCountMap: Map<string, number> = new Map();
    try {
      const queriedPageCounts: Map<string, number> = this.pageParams?.sourceId
        ? await dm.getOnlineChapterPageCounts(mangaRef.id)
        : await dm.getLocalChapterPageCounts(mangaRef.id);
      for (const mapEntry of queriedPageCounts) {
        pageCountMap.set(mapEntry[0], mapEntry[1]);
      }
      logger.info(TAG, `批量查询完成，获取到${pageCountMap.size}个章节的页面信息`);
    } catch (err) {
      logger.error(TAG, `批量查询章节页面失败: ${String(err)}`);
    }

    if (this.useWebView && this.pageParams?.mangaId && this.isKomiicSource()) {
      let webChapters: WebViewChapterInfo[] | null = this.cacheManager.getChapterList(this.sourceId, this.pageParams.mangaId);
      if (!webChapters && this.mangaEngine) {
        const chaptersResult: EngineResult<WebViewChapterInfo[]> = await this.mangaEngine.getChapterList(this.pageParams.mangaId);
        if (chaptersResult.success && chaptersResult.data) {
          webChapters = chaptersResult.data;
          this.cacheManager.setChapterList(this.sourceId, this.pageParams.mangaId, webChapters);
          const nm: string = this.sourceName ? this.sourceName.toLowerCase() : '';
          if ((nm.indexOf('再漫画') >= 0 || nm.indexOf('zai') >= 0) && this.mangaEngine && this.mangaEngine.isLastChapterAccessDenied()) {
            this.accessDenied = true;
            logger.warn(TAG, '检测到再漫画章节接口返回 errno=0, errmsg=""，提示登录或权限不足');
          }
        }
      }
      if (webChapters) {
        for (let k: number = 0; k < webChapters.length; k++) {
          const wc: WebViewChapterInfo = webChapters[k];
          if (wc.id && wc.pageCount && wc.pageCount > 0) {
            pageCountMap.set(wc.id, wc.pageCount as number);
          }
        }
      }
    }

    const progressArray: ChapterProgressInfo[] = [];
    for (let i: number = 0; i < chapters.length; i++) {
      const chapter: MangaChapter = chapters[i];
      let totalPages: number = pageCountMap.get(chapter.id) || 0;
      
      // 注意：不在这里获取页面信息，避免96个章节并发请求导致性能问题
      // 页面信息应该在阅读时按需获取，或者在漫画详情加载时已经保存到数据库

      let lastReadIndex: number = -1;
      let lastReadTime: number = 0;
      for (let j: number = 0; j < historyList.length; j++) {
        const h: ReadHistory = historyList[j];
        if (h.chapterId === chapter.id) {
          if (h.readTime > lastReadTime) {
            lastReadTime = h.readTime;
            lastReadIndex = h.pageIndex;
          }
        }
      }

      const info: ChapterProgressInfo = {
        chapterId: chapter.id,
        totalPages: totalPages,
        currentPageIndex: lastReadIndex,
        lastReadTime: lastReadTime
      } as ChapterProgressInfo;
      progressArray.push(info);
      
      logger.debug(TAG, `章节进度: ${chapter.title} - 当前页: ${lastReadIndex}, 总页数: ${totalPages}`);
    }

    this.chapterProgressList = progressArray;
    logger.info(TAG, `章节进度数据加载完成，共${progressArray.length}个章节`);
  }

  /**
   * 查找章节进度信息
   */
  private findChapterProgress(chapterId: string): ChapterProgressInfo | null {
    for (let i: number = 0; i < this.chapterProgressList.length; i++) {
      const info: ChapterProgressInfo = this.chapterProgressList[i];
      if (info.chapterId === chapterId) {
        return info;
      }
    }
    return null;
  }

  /**
   * 计算阅读恢复目标
   * 从章节进度列表中找到最后阅读的章节（readTime最大），优先恢复该章节
   */
  private determineResumeTarget(): ResumeTarget | null {
    const mg: Manga | null = this.currentManga;
    if (!mg) {
      return null;
    }

    logger.info(TAG, `计算恢复目标: 进度=${this.chapterProgressList.length}, 过滤章节=${this.filteredChapters.length}`);

    const fc: MangaChapter[] = this.filteredChapters;
    
    // [调试] 输出前5个章节的信息
    for (let i = 0; i < Math.min(5, fc.length); i++) {
      logger.debug(TAG, `章节${i}: ${fc[i].title}, chapterNumber=${fc[i].chapterNumber}, id=${fc[i].id}`);
    }

    // 从章节进度列表中找到最后阅读的章节（lastReadTime最大且currentPageIndex >= 0）
    let latestChapterInfo: ChapterProgressInfo | null = null;
    let latestReadTime: number = 0;

    for (let i: number = 0; i < this.chapterProgressList.length; i++) {
      const info: ChapterProgressInfo = this.chapterProgressList[i];
      if (info.currentPageIndex >= 0 && info.lastReadTime > latestReadTime) {
        latestReadTime = info.lastReadTime;
        latestChapterInfo = info;
      }
    }
    
    if (latestChapterInfo) {
      logger.debug(TAG, `找到最后阅读章节: ${latestChapterInfo.chapterId}, 页码=${latestChapterInfo.currentPageIndex}, 总页数=${latestChapterInfo.totalPages}`);
    }

    // 如果找到了最后阅读的章节，恢复到该章节
    if (latestChapterInfo) {
      let resumePageIndex: number = latestChapterInfo.currentPageIndex;
      const totalPages: number = latestChapterInfo.totalPages;

      // 确保页面索引在有效范围内
      if (totalPages > 0) {
        if (resumePageIndex < 0) {
          resumePageIndex = 0;
        } else if (resumePageIndex >= totalPages) {
          resumePageIndex = totalPages - 1;
        }
      } else {
        if (resumePageIndex < 0) {
          resumePageIndex = 0;
        }
      }

      // 检查是否已读完该章节
      const isCompleted: boolean = (totalPages > 0 && resumePageIndex >= totalPages - 1);
      if (!isCompleted) {
        const target: ResumeTarget = { 
          chapterId: latestChapterInfo.chapterId, 
          pageIndex: resumePageIndex 
        } as ResumeTarget;
        logger.info(TAG, `恢复到最后阅读章节: ${latestChapterInfo.chapterId}, 页码: ${resumePageIndex}`);
        return target;
      }

      // 已读完最后阅读的章节，尝试选择下一章节
      if (latestChapterInfo) {
        const safeLatestChapterInfo: ChapterProgressInfo = latestChapterInfo;
        const currentChapter: MangaChapter | undefined = mg.chapters.find((c: MangaChapter) => c.id === safeLatestChapterInfo.chapterId);
        if (currentChapter) {
          // 按章节编号找到下一章（编号更大的章节）
          let nextChapter: MangaChapter | null = null;
          for (let i: number = 0; i < mg.chapters.length; i++) {
            const ch: MangaChapter = mg.chapters[i];
            if (ch.chapterNumber > currentChapter.chapterNumber) {
              if (!nextChapter || ch.chapterNumber < nextChapter.chapterNumber) {
                nextChapter = ch;
              }
            }
          }

          if (nextChapter) {
            const targetNext: ResumeTarget = { chapterId: nextChapter.id, pageIndex: 0 } as ResumeTarget;
            logger.info(TAG, `最后阅读章节已完成，跳转到下一章: ${nextChapter.id}`);
            return targetNext;
          }
        }
      }
    }

    // 无阅读记录时，智能查找第一章
    if (fc && fc.length > 0) {
      // [优化] 优先查找标题中包含"第1话/第01话/第一话"等的章节
      const firstChapterPatterns = [
        /第\s*0*1\s*[话話]/i,  // 第1话、第01话、第 1 话
        /第\s*一\s*[话話]/i,   // 第一话
        /chapter\s*0*1/i,      // Chapter 1, Chapter 01
        /ch\.\s*0*1/i          // Ch.1, Ch. 01
      ];
      
      let foundFirst: MangaChapter | null = null;
      for (let i = 0; i < fc.length; i++) {
        const title = fc[i].title;
        for (const pattern of firstChapterPatterns) {
          if (pattern.test(title)) {
            foundFirst = fc[i];
            logger.info(TAG, `✅ 智能匹配到第一章: ${title}`);
            break;
          }
        }
        if (foundFirst) break;
      }
      
      // 如果没有匹配到，回退到chapterNumber最小的章节
      if (!foundFirst) {
        foundFirst = fc[0];
        for (let i = 1; i < fc.length; i++) {
          if (fc[i].chapterNumber < foundFirst.chapterNumber) {
            foundFirst = fc[i];
          }
        }
        logger.info(TAG, `未匹配到第一章标题，使用chapterNumber最小的: ${foundFirst.title} (编号: ${foundFirst.chapterNumber})`);
      }
      
      const targetFallback: ResumeTarget = { chapterId: foundFirst.id, pageIndex: 0 } as ResumeTarget;
      return targetFallback;
    }

    if (mg.chapters && mg.chapters.length > 0) {
      // [修复] 始终选择chapterNumber最小的章节作为第一章，不依赖排序顺序
      let firstChapter2: MangaChapter = mg.chapters[0];
      for (let i = 1; i < mg.chapters.length; i++) {
        if (mg.chapters[i].chapterNumber < firstChapter2.chapterNumber) {
          firstChapter2 = mg.chapters[i];
        }
      }
      const targetFallback2: ResumeTarget = { chapterId: firstChapter2.id, pageIndex: 0 } as ResumeTarget;
      logger.info(TAG, `无阅读记录，回退到第一章: ${firstChapter2.title} (编号: ${firstChapter2.chapterNumber})`);
      return targetFallback2;
    }

    return null;
  }

  /**
   * 静默刷新阅读进度（从阅读器返回时调用）
   * 不显示加载状态，只更新阅读进度相关的数据
   */
  private async refreshReadingProgressSilently(): Promise<void> {
    if (!this.currentManga || this.isLoading) {
      logger.debug(TAG, '跳过静默刷新：漫画未加载或正在加载中');
      return;
    }

    try {
      logger.info(TAG, '开始静默刷新阅读进度...');
      const dm = DataManager.getInstance();
      const mangaId = this.currentManga.id;

      // 1. 重新加载阅读历史记录
      const history: ReadHistory[] = await dm.getReadHistoryByComic(mangaId, 'default_user', 1);
      if (history && history.length > 0) {
        const lastRead: ReadHistory = history[0];
        this.currentManga.readingProgress = {
          currentChapterId: lastRead.chapterId,
          currentPageIndex: lastRead.pageIndex,
          readingStatus: ReadingStatus.READING,
          totalReadingTime: this.currentManga.readingProgress.totalReadingTime,
          lastReadAt: lastRead.readTime,
          readingPercentage: this.currentManga.readingProgress.readingPercentage
        };
        logger.info(TAG, `阅读进度已更新: chapterId=${lastRead.chapterId}, pageIndex=${lastRead.pageIndex}`);
      }

      // 2. 重新加载章节进度数据
      await this.loadChapterProgressData();

      // 3. 触发UI更新
      const updatedManga = this.currentManga;
      this.currentManga = null;
      this.currentManga = updatedManga;

      logger.info(TAG, '静默刷新阅读进度完成');
    } catch (error) {
      logger.error(TAG, `静默刷新阅读进度失败: ${String(error)}`);
    }
  }

  /**
   * 手动刷新漫画数据（下拉刷新）
   */
  private async refreshMangaData(): Promise<void> {
    if (this.isRefreshing || this.isLoading || this.isPullRefreshing) {
      logger.warn(TAG, '正在刷新或加载中，跳过');
      return;
    }

    // 仅对在线漫画执行下拉刷新
    if (!this.useWebView || this.sourceId <= 0) {
      logger.info(TAG, '非在线漫画，跳过下拉刷新');
      this.isPullRefreshing = false;
      return;
    }

    try {
      this.isPullRefreshing = true;
      this.isRefreshing = true;
      logger.info(TAG, '开始下拉刷新在线漫画数据');

      // 保存当前阅读进度（避免刷新后丢失）
      const progressBackup = new Map<string, ChapterProgressInfo>();
      for (const progressInfo of this.chapterProgressList) {
        if (progressInfo.chapterId) {
          progressBackup.set(progressInfo.chapterId, {
            chapterId: progressInfo.chapterId,
            currentPageIndex: progressInfo.currentPageIndex,
            totalPages: progressInfo.totalPages,
            lastReadTime: progressInfo.lastReadTime
          });
        }
      }
      logger.info(TAG, `已备份 ${progressBackup.size} 个章节的阅读进度`);

      // 强制从网络刷新数据
      await this.loadMangaDataWithWebView();

      // 恢复阅读进度到chapterProgressList
      const newProgressList: ChapterProgressInfo[] = [];
      progressBackup.forEach((backup: ChapterProgressInfo, chapterId: string) => {
        newProgressList.push(backup);
      });
      this.chapterProgressList = newProgressList;
      logger.info(TAG, `已恢复 ${newProgressList.length} 个章节的阅读进度`);

      // 重新应用筛选
      this.applyChapterFilters();

      logger.info(TAG, '下拉刷新完成');
      
      // 显示刷新成功提示
      this.getUIContext().getPromptAction().showToast({
        message: '刷新成功',
        duration: 2000
      });
    } catch (error) {
      logger.error(TAG, `下拉刷新失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: `刷新失败: ${error instanceof Error ? error.message : String(error)}`,
        duration: 3000
      });
    } finally {
      this.isRefreshing = false;
      this.isPullRefreshing = false;
    }
  }

  /**
   * 构造章节进度显示文本
   */
  private getChapterProgressText(chapter: MangaChapter): string {
    const info: ChapterProgressInfo | null = this.findChapterProgress(chapter.id);
    if (!info) {
      return '进度未知';
    }
    const total: number = info.totalPages;
    if (total <= 0) {
      return '页数未知';
    }
    const current: number = info.currentPageIndex >= 0 ? (info.currentPageIndex + 1) : 0;
    if (current > 0) {
      return `共 ${total} 页 • 已读 ${current}/${total}`;
    }
    return `共 ${total} 页 • 未开始`;
  }

  /**
   * 更新漫画NSFW状态
   */
  private async updateMangaNSFW(isNSFW: boolean): Promise<void> {
    try {
      if (!this.pageParams?.mangaId) {
        logger.error(TAG, 'mangaId为空，无法更新NSFW状态');
        return;
      }
      
      // 使用通用方法更新NSFW状态，自动检测内容类型
      const success = await DataManager.getInstance().updateContentNSFW(this.pageParams.mangaId, isNSFW);
      
      if (success) {
        this.mangaIsNSFW = isNSFW;
        this.getUIContext().getPromptAction().showToast({
          message: isNSFW ? '已标记为NSFW内容' : '已标记为SFW内容',
          duration: 2000
        });
      } else {
        logger.error(TAG, `更新NSFW状态失败: 未找到内容`);
        this.getUIContext().getPromptAction().showToast({
          message: '更新失败：未找到内容',
          duration: 2000
        });
      }
    } catch (error) {
      logger.error(TAG, `更新NSFW状态失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '更新失败',
        duration: 2000
      });
    }
  }
  
  /**
   * 加载漫画数据（含收藏状态初始化）
   */
  private async loadMangaData(): Promise<void> {
    logger.info(TAG, '=== loadMangaData 开始执行 ===');
    logger.info(TAG, `当前pageParams: ${JSON.stringify(this.pageParams)}`);
    logger.info(TAG, `重试次数: ${this.retryCount}/${this.maxRetries}`);

    if (!this.canScheduleLoad()) {
      logger.warn(TAG, '加载已在进行或页面已销毁，跳过本次调用');
      return;
    }

    this.isLoadInProgress = true;

    if (!this.pageParams?.mangaId) {
      logger.error(TAG, '无效的漫画ID，pageParams为空或mangaId不存在');
      this.loadError = '无效的漫画ID';
      if (!this.isSilentRefresh) {
        this.isLoading = false;
      }
      this.isLoadInProgress = false;
      return;
    }

    logger.info(TAG, `开始加载漫画数据，ID: ${this.pageParams.mangaId}`);
    if (!this.isSilentRefresh) {
      this.isLoading = true;
    }
    this.loadError = '';
    
    // 检测图源类型
    if (this.pageParams.sourceId) {
      this.sourceId = this.pageParams.sourceId;
      if (this.pageParams.sourcePkg) {
        this.sourcePkg = this.pageParams.sourcePkg;
      }
      this.useWebView = await this.webViewManager.isWebViewSource(this.sourceId);
      logger.info(TAG, `图源ID: ${this.sourceId}, 是否WebView源: ${this.useWebView}`);
    }


    // 设置超时机制
    this.loadTimeoutTimerId = setTimeout((): void => {
      if (this.isLoading && !this.isDisposed) {
        logger.warn(TAG, `数据加载超时 (${this.loadingTimeout}ms)`);
        this.handleLoadTimeout();
      }
    }, this.loadingTimeout);

    try {
      // 如果是WebView源：离线优先，只有手动刷新(isRefreshing=true)时才走网络
      if (this.useWebView && this.sourceId > 0) {
        if (!this.isRefreshing) {
          logger.info(TAG, 'WebView源离线优先：尝试从数据库加载在线漫画数据');
          const loadedFromDB: boolean = await this.loadOnlineMangaFromDatabaseOnly();
          if (loadedFromDB) {
            if (this.loadTimeoutTimerId) {
              clearTimeout(this.loadTimeoutTimerId);
              this.loadTimeoutTimerId = 0;
            }
            if (!this.isSilentRefresh) {
              this.isLoading = false;
            }
            this.isChapterLoading = false;
            this.isLoadInProgress = false;
            logger.info(TAG, '✅ 离线优先命中数据库，章节加载状态已完成');
            return;
          } else {
            logger.info(TAG, '数据库未命中缓存：自动从网络获取在线漫画数据');
            await this.loadMangaDataWithWebView();
            if (this.loadTimeoutTimerId) {
              clearTimeout(this.loadTimeoutTimerId);
              this.loadTimeoutTimerId = 0;
            }
            if (!this.isSilentRefresh) {
              this.isLoading = false;
            }
            this.isLoadInProgress = false;
            return;
          }
        } else {
          logger.info(TAG, 'WebView源强制刷新：从网络获取在线漫画数据');
          await this.loadMangaDataWithWebView();
          if (this.loadTimeoutTimerId) {
            clearTimeout(this.loadTimeoutTimerId);
            this.loadTimeoutTimerId = 0;
          }
          if (!this.isSilentRefresh) {
            this.isLoading = false;
          }
          this.isLoadInProgress = false;
          return;
        }
      }
      
      // 先快速获取漫画基本信息来判断是否为本地漫画
      if (this.pageParams?.mangaId) {
        const comicInfo = await DataManager.getInstance().getComicById(this.pageParams.mangaId);
        this.isLocalManga = comicInfo?.sourceId === 'local_import' || comicInfo?.sourceId === 'local_pdf';
        logger.info(TAG, `漫画来源检测: ${comicInfo?.sourceId}, 是否本地漫画: ${this.isLocalManga}`);
      }

      // 根据漫画来源决定是否需要模拟网络延迟
      const delayTime = this.isLocalManga ? 0 : 800;
      if (delayTime > 0) {
        logger.info(TAG, `开始模拟网络延迟${delayTime}ms`);
      } else {
        logger.info(TAG, '本地漫画，跳过网络延迟'); 
      }

      this.loadDelayTimerId = setTimeout(async (): Promise<void> => {
        if (delayTime > 0) {
          logger.info(TAG, '网络延迟结束，开始获取数据');
        } else {
          logger.info(TAG, '开始获取本地数据');
        }

        try {
          // 清除超时定时器
          if (this.loadTimeoutTimerId) {
            clearTimeout(this.loadTimeoutTimerId);
            this.loadTimeoutTimerId = 0;
          }

          if (!this.isLoading) {
            logger.info(TAG, '加载已被取消或超时');
            this.isLoadInProgress = false;
            if (this.loadDelayTimerId) {
              this.loadDelayTimerId = 0;
            }
            return;
          }

          // 使用DataManager获取真实数据
          if (this.pageParams?.mangaId) {
            logger.info(TAG, `调用DataManager.getComicById: ${this.pageParams.mangaId}`);
            const comicInfo = await DataManager.getInstance().getComicById(this.pageParams.mangaId);

            if (comicInfo) {
              logger.info(TAG, `DataManager返回结果: 找到数据 - ${comicInfo.title}`);
              
              // [修复] 判断是在线漫画还是本地漫画，使用正确的转换方法
              const sourceIdStr = String(comicInfo.sourceId || '');
              // 排除本地导入的漫画（local_import, local_pdf）
              const isLocalSource = sourceIdStr === 'local_import' || sourceIdStr === 'local_pdf' || sourceIdStr === '0' || sourceIdStr === '';
              const isOnlineComic = comicInfo.sourceId && !isLocalSource;
              if (isOnlineComic) {
                // 在线漫画：从 online_comic_info 表重新获取完整信息
                logger.info(TAG, `检测到在线漫画，使用 convertOnlineComicInfoToMangaAsync`);
                const onlineInfo = await DataManager.getInstance().getOnlineComicInfoById(comicInfo.id);
                if (onlineInfo) {
                  this.currentManga = await ComicConverter.convertOnlineComicInfoToMangaAsync(onlineInfo);
                } else {
                  // 降级：如果 online_comic_info 不存在，仍使用 ComicInfo
                  this.currentManga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
                }
              } else {
                // 本地漫画：使用原方法
                logger.info(TAG, `检测到本地漫画，使用 convertComicInfoToMangaAsync`);
                this.currentManga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
              }
              
              logger.info(TAG, `漫画数据加载完成（包含阅读进度）: chapterId=${this.currentManga.readingProgress.currentChapterId}, pageIndex=${this.currentManga.readingProgress.currentPageIndex}`);
              logger.debug(TAG, `📋 章节列表前3个: ${this.currentManga.chapters.slice(0, 3).map(ch => `${ch.title}(id=${ch.id})`).join(', ')}`);
              
              // 加载NSFW状态
              this.mangaIsNSFW = this.currentManga.isNSFW === true;
              logger.debug(TAG, `NSFW状态: ${this.mangaIsNSFW}, currentManga.isNSFW=${this.currentManga.isNSFW}`);

              // 初始化收藏状态（持久化）
              try {
                const favorited: boolean = await this.dataService.isFavorited(comicInfo.id);
                if (this.currentManga) {
                  this.currentManga.isFavorite = favorited;
                }
                logger.info(TAG, `收藏状态初始化完成: ${String(favorited)}`);
              } catch (favErr) {
                logger.warn(TAG, `收藏状态初始化失败: ${String(favErr)}`);
              }

              // 单独加载章节信息
              logger.info(TAG, `开始加载章节信息，漫画ID: ${this.pageParams.mangaId}`);
              try {
                // [修复] 根据漫画来源选择正确的表
                // 本地漫画 (sourceId='local_import', 'local_pdf', 'download_import') 使用 chapter 表
                // 在线漫画使用 online_chapter 表
                const isLocalManga = comicInfo.sourceId === 'local_import' || comicInfo.sourceId === 'local_pdf' || comicInfo.sourceId === 'download_import';
                const chapterInfos = isLocalManga 
                  ? await DataManager.getInstance().getComicChapters(this.pageParams.mangaId)
                  : await DataManager.getInstance().getOnlineComicChapters(this.pageParams.mangaId);
                logger.info(TAG, `成功获取章节信息（${isLocalManga ? 'chapter' : 'online_chapter'}表），数量: ${chapterInfos.length}`);

                // 将DataChapterInfo转换为MangaChapter
                const mangaChapters: MangaChapter[] = chapterInfos.map((chapterInfo: DataChapterInfo) => {
                  const converter: ChapterInfoToMangaChapterConverter = {
                    id: chapterInfo.id,
                    title: chapterInfo.title,
                    chapterNumber: chapterInfo.index,
                    publishedAt: chapterInfo.publishTime,
                    isDownloaded: chapterInfo.isDownloaded,
                    downloadPath: chapterInfo.downloadPath,
                    sourceUrl: '',
                    translatedLanguage: 'zh-CN',
                    scanlationGroup: '',
                    uploader: '',
                    version: 1,
                    readableAt: chapterInfo.publishTime,
                    publishDate: chapterInfo.publishTime,
                    language: 'zh-CN',
                    downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                    downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                    pages: [],
                    externalId: chapterInfo.externalId  // [修复] 传递外部ID，用于WebView图源章节匹配
                  };
                  logger.debug(TAG, `转换章节: ${converter.title}, 编号: ${converter.chapterNumber}, externalId=${chapterInfo.externalId}`);
                  return converter as MangaChapter;
                });

                // 更新漫画对象的章节信息
                if (this.currentManga) {
                  this.currentManga.chapters = mangaChapters;
                }
                logger.info(TAG, `章节信息已更新到漫画对象，章节数量: ${mangaChapters.length}`);

          // 立即更新过滤列表，保证UI尽快渲染章节
          this.updateFilteredChapters();

          // 为封面提供安全回退（缺少封面时使用第一页图片）
          await this.ensureCoverImageFromData(comicInfo, chapterInfos);

          // 加载章节阅读进度（总页数与最近阅读页）
          await this.loadChapterProgressData();
          this.isChapterLoading = false;

                // 输出章节详细信息用于调试
                mangaChapters.forEach((chapter: MangaChapter, idx: number) => {
                  logger.debug(TAG, `章节${idx + 1}: ${chapter.title} (ID: ${chapter.id}, 页数: ${chapter.pages.length})`);
                });

              } catch (chapterError) {
                logger.error(TAG, `加载章节信息失败: ${String(chapterError)}`);
                // 即使章节加载失败，也继续显示漫画基本信息
                if (this.currentManga) {
                  this.currentManga.chapters = [];
                }
              }
            } else {
              logger.warn(TAG, '未找到指定漫画');
              this.currentManga = null;
            }
          }

          // 如果没有找到对应的漫画，显示错误
          if (!this.currentManga) {
            logger.error(TAG, '未找到指定漫画数据');
            this.handleLoadError('未找到指定的漫画');
            return;
          }

          logger.info(TAG, `成功加载漫画: ${this.currentManga.title}`);
          
          // 检查SFW模式
          const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
          if (sfwEnabled && this.mangaIsNSFW) {
            logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
            this.getUIContext().getPromptAction().showToast({
              message: 'SFW模式已启用，无法查看NSFW内容',
              duration: 2000
            });
            // 返回上一页
            if (this.pathStack) {
              this.pathStack.pop();
            }
            this.isLoading = false;
            this.isLoadInProgress = false;
            return;
          }
          
          logger.info(TAG, '确认更新章节过滤');
          this.updateFilteredChapters();
          logger.info(TAG, '数据加载完成，设置isLoading为false');
          this.isLoading = false;
          this.retryCount = 0;
          this.isLoadInProgress = false;
        } catch (error) {
          if (this.loadTimeoutTimerId) {
            clearTimeout(this.loadTimeoutTimerId);
            this.loadTimeoutTimerId = 0;
          }
          logger.error(TAG, `数据加载异常: ${String(error)}`);
          this.handleLoadError(`加载失败: ${String(error)}`);
          this.isLoadInProgress = false;
        }
      }, delayTime);
    } catch (outerError) {
      if (this.loadTimeoutTimerId) {
        clearTimeout(this.loadTimeoutTimerId);
        this.loadTimeoutTimerId = 0;
      }
      logger.error(TAG, `初始化加载失败: ${String(outerError)}`);
      this.handleLoadError(`初始化失败: ${String(outerError)}`);
      this.isLoadInProgress = false;
    }
  }

  /**
   * 处理加载超时
   */
  private handleLoadTimeout(): void {
    if (!this.isSilentRefresh) {
      this.isLoading = false;
    }

    if (this.retryCount < this.maxRetries) {
      this.retryCount++;
      logger.info(TAG, `准备重试加载 (${this.retryCount}/${this.maxRetries})`);

      this.retryTimerId = setTimeout((): void => {
        if (!this.canScheduleLoad()) {
          logger.warn(TAG, '页面不可重试或已有加载在进行，跳过重试调度');
          return;
        }
        this.loadMangaData().catch((error: Error) => {
          logger.error(TAG, `重试加载失败: ${error.message}`);
        });
      }, 1000 * this.retryCount);
    } else {
      logger.error(TAG, '达到最大重试次数，加载失败');
      this.loadError = `加载超时，已重试 ${this.maxRetries} 次`;
    }
  }

  /**
   * 处理加载错误
   */
  private handleLoadError(errorMessage: string): void {
    if (!this.isSilentRefresh) {
      this.isLoading = false;
    }

    if (this.retryCount < this.maxRetries) {
      this.retryCount++;
      logger.info(TAG, `准备重试加载 (${this.retryCount}/${this.maxRetries})`);

      this.retryTimerId = setTimeout((): void => {
        if (!this.canScheduleLoad()) {
          logger.warn(TAG, '页面不可重试或已有加载在进行，跳过重试调度');
          return;
        }
        this.loadMangaData().catch((error: Error) => {
          logger.error(TAG, `重试加载失败: ${error.message}`);
        });
      }, 1000 * this.retryCount);
    } else {
      logger.error(TAG, '达到最大重试次数，加载失败');
      this.loadError = errorMessage;
    }
  }

  /**
   * 手动重试加载
   */
  private retryLoad(): void {
    logger.info(TAG, '用户手动重试加载');
    this.retryCount = 0;
    this.loadMangaData().catch((error: Error) => {
      logger.error(TAG, `手动重试加载失败: ${error.message}`);
    });
  }

  private normalizeConfiguredCoverHeaderValue(value?: string): string {
    if (!value) {
      return '';
    }
    return value.trim();
  }

  private readCoverHeaderAlias(headers: MangaDetailSourceHeaderMap, fieldName: string): string {
    try {
      const value = Reflect.get(headers, fieldName) as string | undefined;
      return this.normalizeConfiguredCoverHeaderValue(value);
    } catch (_error) {
      return '';
    }
  }

  private chooseCoverHeaderValue(first: string, second: string, third: string): string {
    if (first.length > 0) {
      return first;
    }
    if (second.length > 0) {
      return second;
    }
    return third;
  }

  private normalizeCoverHeaderMap(headers: MangaDetailSourceHeaderMap): MangaDetailNormalizedHeaders {
    const normalized = new MangaDetailNormalizedHeaders();
    normalized.userAgent = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'User-Agent'), this.readCoverHeaderAlias(headers, 'UserAgent'), this.readCoverHeaderAlias(headers, 'userAgent'));
    normalized.referer = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Referer'), this.readCoverHeaderAlias(headers, 'referer'), '');
    normalized.origin = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Origin'), this.readCoverHeaderAlias(headers, 'origin'), '');
    normalized.accept = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Accept'), this.readCoverHeaderAlias(headers, 'accept'), '');
    normalized.cookie = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Cookie'), this.readCoverHeaderAlias(headers, 'cookie'), '');
    normalized.authorization = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Authorization'), this.readCoverHeaderAlias(headers, 'authorization'), '');
    normalized.acceptLanguage = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Accept-Language'), this.readCoverHeaderAlias(headers, 'AcceptLanguage'), this.readCoverHeaderAlias(headers, 'acceptLanguage'));
    normalized.cacheControl = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Cache-Control'), this.readCoverHeaderAlias(headers, 'CacheControl'), this.readCoverHeaderAlias(headers, 'cacheControl'));
    normalized.pragma = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Pragma'), this.readCoverHeaderAlias(headers, 'pragma'), '');
    normalized.secFetchDest = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Sec-Fetch-Dest'), this.readCoverHeaderAlias(headers, 'SecFetchDest'), this.readCoverHeaderAlias(headers, 'secFetchDest'));
    normalized.secFetchMode = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Sec-Fetch-Mode'), this.readCoverHeaderAlias(headers, 'SecFetchMode'), this.readCoverHeaderAlias(headers, 'secFetchMode'));
    normalized.secFetchSite = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Sec-Fetch-Site'), this.readCoverHeaderAlias(headers, 'SecFetchSite'), this.readCoverHeaderAlias(headers, 'secFetchSite'));
    normalized.cachePartition = this.chooseCoverHeaderValue(this.readCoverHeaderAlias(headers, 'Cache-Partition'), this.readCoverHeaderAlias(headers, 'CachePartition'), this.readCoverHeaderAlias(headers, 'cachePartition'));
    return normalized;
  }

  private appendCoverExtraHeader(target: OnlineRequestHeaders, headerName: string, headerValue: string): void {
    const normalizedName = headerName.trim();
    const normalizedValue = headerValue.trim();
    if (normalizedName.length === 0 || normalizedValue.length === 0) {
      return;
    }
    if (!target.extraHeaders) {
      target.extraHeaders = [];
    }
    let index = 0;
    while (index < target.extraHeaders.length) {
      const entry = target.extraHeaders[index];
      if (entry.name.toLowerCase() === normalizedName.toLowerCase()) {
        entry.value = normalizedValue;
        return;
      }
      index = index + 1;
    }
    target.extraHeaders.push({
      name: normalizedName,
      value: normalizedValue
    } as OnlineRequestHeaderEntry);
  }

  private applyConfiguredCoverHeader(target: OnlineRequestHeaders, headerName: string, headerValue: string): void {
    const normalizedName = headerName.trim().toLowerCase();
    const normalizedValue = headerValue.trim();
    if (normalizedName.length === 0 || normalizedValue.length === 0) {
      return;
    }
    switch (normalizedName) {
      case 'user-agent':
      case 'useragent':
        target.userAgent = normalizedValue;
        return;
      case 'referer':
        target.referer = normalizedValue;
        return;
      case 'origin':
        target.origin = normalizedValue;
        return;
      case 'accept':
        target.accept = normalizedValue;
        return;
      case 'cookie':
        target.cookie = normalizedValue;
        return;
      case 'authorization':
        target.authorization = normalizedValue;
        return;
      case 'accept-language':
      case 'acceptlanguage':
        target.acceptLanguage = normalizedValue;
        return;
      case 'cache-control':
      case 'cachecontrol':
        target.cacheControl = normalizedValue;
        return;
      case 'pragma':
        target.pragma = normalizedValue;
        return;
      case 'sec-fetch-dest':
      case 'secfetchdest':
        target.secFetchDest = normalizedValue;
        return;
      case 'sec-fetch-mode':
      case 'secfetchmode':
        target.secFetchMode = normalizedValue;
        return;
      case 'sec-fetch-site':
      case 'secfetchsite':
        target.secFetchSite = normalizedValue;
        return;
      case 'cache-partition':
      case 'cachepartition':
        target.cachePartition = normalizedValue;
        return;
      default:
        this.appendCoverExtraHeader(target, headerName, normalizedValue);
        return;
    }
  }

  private applyCoverHeaderCandidate(target: OnlineRequestHeaders, headerName: string, headerValue?: string): void {
    const normalizedValue = this.normalizeConfiguredCoverHeaderValue(headerValue);
    if (normalizedValue.length > 0) {
      this.applyConfiguredCoverHeader(target, headerName, normalizedValue);
    }
  }

  private applyConfiguredCoverHeaderMap(target: OnlineRequestHeaders, headerMap?: MangaDetailSourceHeaderMap): void {
    if (!headerMap) {
      return;
    }
    const normalized = this.normalizeCoverHeaderMap(headerMap);
    this.applyCoverHeaderCandidate(target, 'User-Agent', normalized.userAgent);
    this.applyCoverHeaderCandidate(target, 'Referer', normalized.referer);
    this.applyCoverHeaderCandidate(target, 'Origin', normalized.origin);
    this.applyCoverHeaderCandidate(target, 'Accept', normalized.accept);
    this.applyCoverHeaderCandidate(target, 'Cookie', normalized.cookie);
    this.applyCoverHeaderCandidate(target, 'Authorization', normalized.authorization);
    this.applyCoverHeaderCandidate(target, 'Accept-Language', normalized.acceptLanguage);
    this.applyCoverHeaderCandidate(target, 'Cache-Control', normalized.cacheControl);
    this.applyCoverHeaderCandidate(target, 'Pragma', normalized.pragma);
    this.applyCoverHeaderCandidate(target, 'Sec-Fetch-Dest', normalized.secFetchDest);
    this.applyCoverHeaderCandidate(target, 'Sec-Fetch-Mode', normalized.secFetchMode);
    this.applyCoverHeaderCandidate(target, 'Sec-Fetch-Site', normalized.secFetchSite);
    this.applyCoverHeaderCandidate(target, 'Cache-Partition', normalized.cachePartition);
  }

  private hasConfiguredCoverHeaders(headers: OnlineRequestHeaders): boolean {
    if (headers.userAgent && headers.userAgent.length > 0) { return true; }
    if (headers.accept && headers.accept.length > 0) { return true; }
    if (headers.referer && headers.referer.length > 0) { return true; }
    if (headers.origin && headers.origin.length > 0) { return true; }
    if (headers.cookie && headers.cookie.length > 0) { return true; }
    if (headers.authorization && headers.authorization.length > 0) { return true; }
    if (headers.acceptLanguage && headers.acceptLanguage.length > 0) { return true; }
    if (headers.cacheControl && headers.cacheControl.length > 0) { return true; }
    if (headers.pragma && headers.pragma.length > 0) { return true; }
    if (headers.secFetchDest && headers.secFetchDest.length > 0) { return true; }
    if (headers.secFetchMode && headers.secFetchMode.length > 0) { return true; }
    if (headers.secFetchSite && headers.secFetchSite.length > 0) { return true; }
    if (headers.cachePartition && headers.cachePartition.length > 0) { return true; }
    if (headers.extraHeaders && headers.extraHeaders.length > 0) { return true; }
    return false;
  }

  private updateCoverPartitionFromHeaders(headers: OnlineRequestHeaders): void {
    if (headers.referer && headers.referer.length > 0) {
      let hash = 0;
      const referer = headers.referer;
      for (let i = 0; i < referer.length; i++) {
        const char = referer.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash;
      }
      this.photos18CoverPartition = `photos18_detail_${Math.abs(hash).toString(36)}`;
    }
  }

  private initCoverHeadersFromSourceConfig(sourceConfig: MangaDetailSourceHeaderConfig): void {
    const headers: OnlineRequestHeaders = {} as OnlineRequestHeaders;
    if (sourceConfig.network && sourceConfig.network.headers) {
      this.applyConfiguredCoverHeaderMap(headers, sourceConfig.network.headers);
    }
    if (sourceConfig.imageHeaders) {
      this.applyConfiguredCoverHeaderMap(headers, sourceConfig.imageHeaders);
    }
    if (sourceConfig.coverHeaders) {
      this.applyConfiguredCoverHeaderMap(headers, sourceConfig.coverHeaders);
    }

    if (this.hasConfiguredCoverHeaders(headers)) {
      this.coverHttpHeaders = headers;
      this.updateCoverPartitionFromHeaders(headers);
      logger.info(TAG, `封面HTTP headers已设置: ${JSON.stringify(headers)}`);
    }
  }
  
  /**
   * 使用WebView加载漫画数据
   */
  private async loadMangaDataWithWebView(): Promise<void> {
    try {
      logger.info(TAG, `开始使用WebView加载漫画详情: sourceId=${this.sourceId}, mangaId=${this.pageParams?.mangaId}`);
      
      // 获取图源配置以获取名称和网络headers
      try {
        const sources = await DataManager.getInstance().getAllComicSources();
        logger.debug(TAG, `获取到 ${sources.length} 个图源，当前sourceId=${this.sourceId}`);
        for (let i = 0; i < sources.length; i++) {
          const s: ESObject = sources[i] as ESObject;
          if (Number(s.id) === this.sourceId) {
            this.sourceName = String(s.name);
            if (s.pkg) {
              this.sourcePkg = String(s.pkg);
            }
            logger.info(TAG, `图源名称: ${this.sourceName}`);
            
            try {
              const configJson = s.configJson as string;
              if (configJson) {
                const config: MangaDetailSourceHeaderConfig = SafeUtils.parseObj(configJson) as MangaDetailSourceHeaderConfig;
                this.initCoverHeadersFromSourceConfig(config);
              }
            } catch (parseErr) {
              logger.warn(TAG, `解析图源配置失败: ${String(parseErr)}`);
            }
            break;
          }
        }
        if (!this.sourceName) {
          logger.warn(TAG, `未找到sourceId=${this.sourceId}的图源`);
        }
      } catch (err) {
        logger.warn(TAG, `获取图源名称失败: ${String(err)}`);
      }
      
      // 获取MangaSourceEngine（【关键】必须传递sourceName确保图源正确）
      if (!this.sourceName) {
        throw new Error(`图源名称为空，无法初始化MangaSourceEngine: sourceId=${this.sourceId}`);
      }
      logger.info(TAG, `🔄 初始化MangaSourceEngine: sourceName="${this.sourceName}", sourceId=${this.sourceId}`);
      this.mangaEngine = await this.webViewManager.getMangaEngine(this.sourceId, this.sourceName);
      
      if (!this.pageParams?.mangaId) {
        throw new Error('漫画ID为空');
      }
      
      let mangaInfo: MangaInfo | null = null;
      let useCache = false;
      
      // [重构] 检查数据库是否有可用章节（非强制刷新时，离线优先）
      if (!this.isRefreshing) {
        try {
          const dbComic = await DataManager.getInstance().getComicById(this.pageParams.mangaId);
          // [重构] WebView源使用online_chapter表
          const dbChapters = await DataManager.getInstance().getOnlineComicChapters(this.pageParams.mangaId);
          if (dbChapters && dbChapters.length > 0 && dbComic) {
            logger.info(TAG, `数据库命中（online_chapter表）：${dbComic.title}，章节数: ${dbChapters.length}`);
            useCache = true;

            // 从数据库加载漫画基本信息
            this.currentManga = await ComicConverter.convertComicInfoToMangaAsync(dbComic);

            // [重构] 转换在线章节数据为Manga格式
            const mangaChapters: MangaChapter[] = [];
            for (let i: number = 0; i < dbChapters.length; i++) {
              const ch = dbChapters[i];
              const chapter: MangaChapter = {
                id: ch.id,
                title: ch.title,
                chapterNumber: ch.chapterNumber,  // OnlineChapterInfo使用chapterNumber
                pages: [],
                publishDate: ch.publishTime || Date.now(),
                language: 'zh-CN',
                scanlationGroup: '',
                isDownloaded: ch.isDownloaded || false,
                downloadProgress: ch.isDownloaded ? 100 : 0,
                downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                localPath: ch.downloadPath,
                externalId: ch.externalId // [重构] 从online_chapter表读取外部ID
              };
              mangaChapters.push(chapter);
            }

            this.currentManga.chapters = mangaChapters;
            this.filteredChapters = this.currentManga.chapters;
            this.applyChapterFilters();

            // 加载章节进度
            await this.loadChapterProgressData();

            if (!this.isSilentRefresh) {
              this.isLoading = false;
            }
            this.isChapterLoading = false;
            this.isRefreshing = false;

            logger.info(TAG, '✅ 使用数据库章节，跳过网络请求');
            return;
          } else {
            logger.info(TAG, '数据库未命中章节，需从网络获取');
          }
        } catch (dbErr) {
          logger.warn(TAG, `检查数据库缓存失败: ${String(dbErr)}`);
        }
      } else {
        logger.info(TAG, '强制刷新模式，跳过数据库缓存');
      }
      
      // 获取外部图源ID（如果存在）
      let externalMangaId = this.pageParams.mangaId;
      
      // 优先从currentManga.sourceInfo.sourceUrl获取（首次加载时设置）
      if (this.currentManga && this.currentManga.sourceInfo && this.currentManga.sourceInfo.sourceUrl) {
        const sourceUrl = this.currentManga.sourceInfo.sourceUrl;
        logger.debug(TAG, `检查currentManga.sourceInfo.sourceUrl: ${sourceUrl}`);
        // 如果sourceUrl不是内部ID格式，使用它作为外部ID
        if (!sourceUrl.startsWith('id_')) {
          externalMangaId = sourceUrl;
          logger.info(TAG, `从currentManga.sourceInfo.sourceUrl获取外部ID: ${externalMangaId}`);
        } else {
          logger.warn(TAG, `sourceInfo.sourceUrl也是内部ID格式: ${sourceUrl}`);
        }
      } else {
        logger.debug(TAG, `currentManga.sourceInfo不可用: currentManga=${!!this.currentManga}, sourceInfo=${!!this.currentManga?.sourceInfo}, sourceUrl=${this.currentManga?.sourceInfo?.sourceUrl}`);
      }
      
      // 如果还是内部ID格式，尝试从数据库获取
      if (externalMangaId.startsWith('id_')) {
        try {
          // 尝试从comic_info表获取externalId、webUrl或apiUrl
          const dbComicRecord = await DataManager.getInstance().getComicById(this.pageParams.mangaId);
          if (dbComicRecord && dbComicRecord.externalId && !dbComicRecord.externalId.startsWith('id_')) {
            externalMangaId = dbComicRecord.externalId as string;
            logger.info(TAG, `从comic_info获取外部ID: ${externalMangaId} (内部ID: ${this.pageParams.mangaId})`);
          } else if (dbComicRecord && (dbComicRecord as ESObject).webUrl) {
            // 尝试从webUrl提取外部ID
            const webUrl = String((dbComicRecord as ESObject).webUrl);
            const match = webUrl.match(/\/comic\/(\d+)/);
            if (match && match[1]) {
              externalMangaId = match[1];
              logger.info(TAG, `从webUrl提取外部ID: ${externalMangaId} (webUrl: ${webUrl})`);
            } else {
              logger.warn(TAG, `无法从webUrl提取外部ID: ${webUrl}`);
            }
          } else if (dbComicRecord && (dbComicRecord as ESObject).apiUrl) {
            // 尝试从apiUrl提取外部ID
            const apiUrl = String((dbComicRecord as ESObject).apiUrl);
            const match = apiUrl.match(/comicId=(\d+)/);
            if (match && match[1]) {
              externalMangaId = match[1];
              logger.info(TAG, `从apiUrl提取外部ID: ${externalMangaId} (apiUrl: ${apiUrl})`);
            } else {
              logger.warn(TAG, `无法从apiUrl提取外部ID: ${apiUrl}`);
            }
          }
          
          if (externalMangaId.startsWith('id_')) {
            // [重构] 如果comic_info中没有有效的externalId，尝试从在线章节的externalId推断
            logger.info(TAG, `comic_info中未找到有效externalId，尝试从online_chapter表推断`);
            const dbChapters = await DataManager.getInstance().getOnlineComicChapters(this.pageParams.mangaId);
            if (dbChapters && dbChapters.length > 0) {
              // 检查第一个章节的externalId
              const firstChapter = dbChapters[0];
              if (firstChapter.externalId && !firstChapter.externalId.startsWith('id_')) {
                // 对于Komiic，章节ID格式通常是纯数字，漫画ID也是纯数字
                // 我们需要从其他地方获取漫画ID，这里先尝试使用章节所属的漫画信息
                logger.info(TAG, `从online_chapter找到章节externalId: ${firstChapter.externalId}，但无法直接推断漫画ID`);
              }
            }
            
            // 尝试从online_comic_info表获取
            logger.info(TAG, `尝试从online_comic_info查询`);
            const onlineComic = await DataManager.getInstance().getOnlineComicByExternalId(this.pageParams.mangaId);
            if (onlineComic && onlineComic.externalId && !onlineComic.externalId.startsWith('id_')) {
              externalMangaId = onlineComic.externalId;
              logger.info(TAG, `从online_comic_info获取外部ID: ${externalMangaId}`);
            } else if (onlineComic && !onlineComic.id.startsWith('id_')) {
              // 如果online_comic_info中也没有，但找到了记录且id不是内部格式，使用其id
              externalMangaId = onlineComic.id;
              logger.info(TAG, `使用online_comic_info的id作为外部ID: ${externalMangaId}`);
            } else {
              // 最后的尝试：提示用户这是数据问题，需要重新添加
              const errorMsg = `此漫画数据不完整（缺少有效的外部ID）。\n\n解决方法：\n1. 从图源页面重新进入此漫画\n2. 或从书库中删除后重新添加`;
              logger.warn(TAG, `未找到有效的外部ID: ${errorMsg}`);
              throw new Error(errorMsg);
            }
          }
        } catch (err) {
          logger.error(TAG, `获取外部ID失败: ${String(err)}`);
          throw err as Error;
        }
      }
      
      // 尝试从内存缓存获取漫画详情
      mangaInfo = this.cacheManager.getMangaDetail(this.sourceId, externalMangaId);
      let chapters: WebViewChapterInfo[] | null = this.cacheManager.getChapterList(this.sourceId, externalMangaId);
      
      // 检查是否需要从网络获取
      const needFetchDetail = !mangaInfo || this.isRefreshing;
      const needFetchChapters = !chapters;
      
      if (needFetchDetail || needFetchChapters) {
        // 使用合并工作流一次性获取详情和章节（优化）
        if (needFetchDetail && needFetchChapters) {
          logger.info(TAG, '使用合并工作流获取详情和章节');
          const combinedResult: EngineResult<MangaDetailWithChapters> = await this.mangaEngine.getMangaDetailWithChapters(externalMangaId);
          
          if (!combinedResult.success || !combinedResult.data) {
            throw new Error(combinedResult.error || '获取漫画数据失败');
          }
          
          const detailData = combinedResult.data.detail;
          const chaptersData = combinedResult.data.chapters;
          
          if (detailData && chaptersData) {
            mangaInfo = detailData;
            chapters = chaptersData;
            logger.info(TAG, `合并获取成功: ${mangaInfo.title}, ${chapters.length}章`);
            
            // 缓存数据
            this.cacheManager.setMangaDetail(this.sourceId, externalMangaId, mangaInfo);
            this.cacheManager.setChapterList(this.sourceId, externalMangaId, chapters);
          }
        } else {
          // 单独获取缺失的部分
          if (needFetchDetail) {
            logger.info(TAG, this.isRefreshing ? '强制刷新，从网络获取详情' : '缓存未命中，从网络获取漫画详情');
            const detailResult: EngineResult<MangaInfo> = await this.mangaEngine.getMangaDetail(externalMangaId);
            if (!detailResult.success || !detailResult.data) {
              throw new Error(detailResult.error || '获取漫画详情失败');
            }
            mangaInfo = detailResult.data;
            logger.info(TAG, `漫画详情获取成功: ${mangaInfo.title}`);
            this.cacheManager.setMangaDetail(this.sourceId, externalMangaId, mangaInfo);
          }
          
          if (needFetchChapters) {
            logger.info(TAG, '缓存未命中，从网络获取章节列表');
            const chaptersResult: EngineResult<WebViewChapterInfo[]> = await this.mangaEngine.getChapterList(externalMangaId);
            if (chaptersResult.success && chaptersResult.data) {
              chapters = chaptersResult.data;
              logger.info(TAG, `章节列表获取成功，共${chapters.length}章`);
              this.cacheManager.setChapterList(this.sourceId, externalMangaId, chapters);
              
              const nm2: string = this.sourceName ? this.sourceName.toLowerCase() : '';
              if ((nm2.indexOf('再漫画') >= 0 || nm2.indexOf('zai') >= 0) && this.mangaEngine && this.mangaEngine.isLastChapterAccessDenied()) {
                this.accessDenied = true;
                logger.warn(TAG, '检测到再漫画章节接口返回 errno=0, errmsg=""，提示登录或权限不足');
              }
            } else {
              logger.warn(TAG, `章节列表获取失败: ${chaptersResult.error}`);
              chapters = [];
            }
          }
        }
      } else {
        logger.info(TAG, `从缓存加载: ${mangaInfo?.title || 'unknown'}, ${chapters?.length || 0}章`);
      }
      
      // 验证数据是否有效
      if (!mangaInfo || !chapters) {
        throw new Error('漫画数据获取失败');
      }
      
      // [修复] 验证漫画详情是否有效（仅在刷新模式下严格验证）
      if (this.isRefreshing && (!mangaInfo.title || mangaInfo.title.trim() === '')) {
        throw new Error('漫画标题为空，可能是页面未完全加载，请稍后重试');
      }
      
      // [修复] 如果详情页没有返回标题或封面，使用从列表页面传递的缓存值
      if ((!mangaInfo.title || mangaInfo.title.trim() === '') && this.pageParams?.cachedTitle) {
        mangaInfo.title = this.pageParams.cachedTitle;
        logger.info(TAG, `使用缓存的标题: ${mangaInfo.title}`);
      }
      if ((!mangaInfo.cover || mangaInfo.cover.trim() === '') && this.pageParams?.cachedCover) {
        mangaInfo.cover = this.pageParams.cachedCover;
        logger.info(TAG, `使用缓存的封面URL: ${mangaInfo.cover}`);
      }
      
      // 转换为Manga对象
      this.currentManga = await this.convertMangaInfoToManga(mangaInfo);
      
      // 如果有缓存的封面路径，优先使用
      if (this.pageParams?.cachedCoverPath) {
        this.currentManga.coverImagePath = this.pageParams.cachedCoverPath;
        this.currentManga.coverSourceType = ImageSourceType.LOCAL;
        logger.info(TAG, `使用图源详情页缓存的封面: ${this.pageParams.cachedCoverPath}`);
      }
      
      if (!this.isSilentRefresh) {
        this.isLoading = false;
      }
      this.isChapterLoading = true;

      // 在线漫画初始收藏状态检测（通过externalId映射到本地漫画ID）
      try {
        const externalIdForCheck: string = externalMangaId;
        const record = await DataManager.getInstance().getComicByExternalId(externalIdForCheck);
        if (record) {
          const obj: ESObject = record as ESObject;
          const internalId: string = String(obj.id);
          const favorited: boolean = await this.dataService.isFavorited(internalId);
          this.currentManga.isFavorite = favorited;
          const updated = this.currentManga;
          this.currentManga = null;
          this.currentManga = updated;
          logger.info(TAG, `在线漫画初始收藏状态: ${String(favorited)} (externalId映射ID=${internalId})`);
        } else {
          logger.info(TAG, '在线漫画初始收藏状态: 未在本地表找到externalId映射记录');
        }
      } catch (initFavErr) {
        logger.warn(TAG, `在线漫画收藏状态检测失败: ${String(initFavErr)}`);
      }
      
      // [修复] 验证章节列表是否有效
      if (chapters && chapters.length > 0) {
        // 检查是否包含DEBUG章节（刷新模式下严格验证，防止覆盖正确数据）
        const hasDebugChapter = chapters.some((ch: WebViewChapterInfo) => 
          ch.id === 'DEBUG' || ch.title.includes('DEBUG') || ch.title.includes('Total:')
        );
        if (hasDebugChapter) {
          if (this.isRefreshing) {
            // 刷新模式：抛出异常，保留原数据
            throw new Error('章节列表提取失败（包含调试数据），保留原有数据');
          } else {
            // 正常加载：警告但不阻止
            logger.warn(TAG, '⚠️ 检测到DEBUG章节，但这是首次加载，继续处理');
          }
        }
      } else if (this.isRefreshing) {
        // 仅在刷新模式下对空章节列表抛出异常
        throw new Error('章节列表为空，可能是页面未完全加载，保留原有数据');
      }
      
      if (chapters && this.isKomiicSource()) {
        chapters = this.deduplicateWebViewChapters(chapters);
        logger.info(TAG, `Komiic章节去重后数量: ${chapters.length}`);
      }

      const convertedChapters: MangaChapter[] = this.convertWebViewChapterInfoToMangaChapter(chapters);
      if (this.currentManga) {
        this.currentManga.chapters = convertedChapters;
      }
      
      // 从数据库加载阅读进度和漫画信息
      await this.loadOnlineMangaDataFromDatabase();
      
      // 保存在线漫画信息到数据库（避免与已有书库重复）
      await this.saveOnlineMangaToDatabase();
      
      // 清理重复章节
      try {
        const duplicateCount = await DataManager.getInstance().cleanDuplicateChapters(this.pageParams.mangaId);
        if (duplicateCount > 0) {
          logger.info(TAG, `已清理 ${duplicateCount} 个重复章节`);
        }
      } catch (cleanError) {
        logger.warn(TAG, `清理重复章节失败: ${String(cleanError)}`);
      }
      
      if (this.currentManga) {
        this.filteredChapters = this.currentManga.chapters;
      } else {
        this.filteredChapters = [];
      }
      this.chapterDataSource.setChapters(this.filteredChapters);
      
      // 加载章节进度数据（用于显示章节进度和判断是否有阅读记录）
      await this.loadChapterProgressData();
      this.isChapterLoading = false;
      
      logger.info(TAG, 'WebView漫画数据加载完成');
      
      // 立即触发章节预加载（在获取到章节列表后）
      this.triggerChapterPreload();
      
    } catch (error) {
      logger.error(TAG, `WebView加载失败: ${error instanceof Error ? error.message : String(error)}`);
      this.loadError = `加载失败: ${error instanceof Error ? error.message : String(error)}`;
      throw error as Error;
    }
  }

  private deduplicateWebViewChapters(chapters: WebViewChapterInfo[]): WebViewChapterInfo[] {
    const seen: Set<string> = new Set<string>();
    const result: WebViewChapterInfo[] = [];
    for (let i: number = 0; i < chapters.length; i++) {
      const ch: WebViewChapterInfo = chapters[i];
      let idStr: string = '';
      if (ch.id) {
        idStr = ch.id;
      } else if (ch.url) {
        idStr = ch.url;
      } else {
        idStr = 'chapter_' + String(i);
      }
      if (!seen.has(idStr)) {
        seen.add(idStr);
        result.push(ch);
      } else {
        logger.warn(TAG, `检测到重复章节，已忽略: id=${idStr}, title=${ch.title}`);
      }
    }
    return result;
  }

  /**
   * [场景1] 从书库进入：仅从数据库加载在线漫画（使用内部ID）
   * 不进行任何网络请求，除非用户手动刷新
   */
  private async loadOnlineMangaFromLibrary(internalId: string): Promise<boolean> {
    try {
      const dm = DataManager.getInstance();
      logger.info(TAG, `📚 [场景1] 从书库加载在线漫画，内部ID: ${internalId}`);
      
      // 从online_comic_info表查询（使用强类型方法）
      const onlineComic = await dm.getOnlineComicInfoById(internalId);
      if (!onlineComic) {
        logger.warn(TAG, `未在online_comic_info表中找到漫画: ${internalId}`);
        return false;
      }
      
      // [修复] 设置sourceId和sourceName，用于显示图源信息
      if (onlineComic.sourceId) {
        this.sourceId = Number(onlineComic.sourceId);
        
        // [修复] 定义无效的图源名称列表
        const invalidSourceNames = ['本地导入', 'LOCAL', 'UNKNOWN', 'WEBVIEW', 'WebView Source', ''];
        const dbSourceName = onlineComic.sourceName || '';
        const isInvalidName = invalidSourceNames.some(inv => dbSourceName.startsWith(inv));
        
        // [修复] 优先从comic_source表查询正确的图源名称
        // 因为数据库中的sourceName可能是错误的（之前的bug导致）
        try {
          const sources = await dm.getAllComicSources();
          for (let i = 0; i < sources.length; i++) {
            const s: ESObject = sources[i] as ESObject;
            if (Number(s.id) === this.sourceId) {
              this.sourceName = String(s.name);
              logger.info(TAG, `从comic_source表获取图源名称: ${this.sourceName}`);
              break;
            }
          }
        } catch (err) {
          logger.warn(TAG, `查询图源名称失败: ${String(err)}`);
        }
        
        // 如果从comic_source表没有获取到，且数据库中的名称有效，则使用数据库中的名称
        if (!this.sourceName && !isInvalidName && dbSourceName.length > 0) {
          this.sourceName = dbSourceName;
          logger.info(TAG, `使用数据库中的图源名称: ${this.sourceName}`);
        }
        
        // 如果还是没有，使用默认值（不应该到达这里）
        if (!this.sourceName) {
          this.sourceName = `WebView Source ${this.sourceId}`;
          logger.warn(TAG, `⚠️ 无法获取有效图源名称，使用默认值: ${this.sourceName}`);
        }
        
        logger.info(TAG, `设置图源信息: sourceId=${this.sourceId}, sourceName=${this.sourceName}`);
      }
      
      // 构建Manga对象
      this.currentManga = await this.buildMangaFromOnlineComicInfo(onlineComic);
      
      // 加载章节列表（从online_chapter表）
      const chapters = await this.loadChaptersFromDatabase(String(onlineComic.id));
      if (this.currentManga) {
        this.currentManga.chapters = chapters;
        this.filteredChapters = chapters;
        // [修复] 同步数据源以供LazyForEach使用
        this.chapterDataSource.setChapters(chapters);
      }
      
      // 加载阅读进度
      await this.loadReadingProgressFromDatabase(internalId);
      
      // 加载收藏状态
      await this.loadFavoriteStatus(internalId);
      
      // 加载章节进度
      await this.loadChapterProgressData();
      
      logger.info(TAG, `✅ [场景1] 从书库加载完成: ${onlineComic.title}, 章节数: ${chapters.length}`);
      return true;
    } catch (error) {
      logger.error(TAG, `[场景1] 从书库加载失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * [场景2] 从图源进入已存在的在线漫画：加载数据库信息 + 网络更新章节
   * 使用外部ID查询数据库，如果存在则加载，然后网络更新章节列表
   */
  private async loadOnlineMangaFromSourceWithUpdate(externalId: string): Promise<boolean> {
    try {
      const dm = DataManager.getInstance();
      logger.info(TAG, `🔄 [场景2] 从图源加载已存在的在线漫画，外部ID: ${externalId}`);
      
      // 从online_comic_info表查询（通过externalId）
      const onlineComic = await dm.getOnlineComicByExternalId(externalId);
      if (!onlineComic) {
        logger.info(TAG, `未在online_comic_info表中找到漫画，转到场景3`);
        return false;
      }
      
      logger.info(TAG, `✅ 找到已存在的在线漫画: ${onlineComic.title}, 内部ID: ${onlineComic.id}`);
      
      // 构建Manga对象
      this.currentManga = await this.buildMangaFromOnlineComicInfo(onlineComic);
      
      // 先加载数据库中的章节（快速显示）
      const dbChapters = await this.loadChaptersFromDatabase(onlineComic.id);
      if (this.currentManga) {
        this.currentManga.chapters = dbChapters;
        this.filteredChapters = dbChapters;
        // [修复] 同步数据源以供LazyForEach使用
        this.chapterDataSource.setChapters(dbChapters);
      }
      
      // 加载阅读进度和收藏状态
      await this.loadReadingProgressFromDatabase(onlineComic.id);
      await this.loadFavoriteStatus(onlineComic.id);
      await this.loadChapterProgressData();
      
      // [修复] 初始化MangaEngine用于网络请求
      if (!this.mangaEngine && this.sourceId > 0) {
        try {
          // 获取图源名称
          if (!this.sourceName) {
            const sources = await dm.getAllComicSources();
            for (let i = 0; i < sources.length; i++) {
              const s: ESObject = sources[i] as ESObject;
              if (Number(s.id) === this.sourceId) {
                this.sourceName = String(s.name);
                logger.info(TAG, `[场景2] 获取图源名称: ${this.sourceName}`);
                break;
              }
            }
          }
          
          if (this.sourceName) {
            logger.info(TAG, `[场景2] 初始化MangaEngine: sourceName="${this.sourceName}", sourceId=${this.sourceId}`);
            this.mangaEngine = await this.webViewManager.getMangaEngine(this.sourceId, this.sourceName);
          } else {
            logger.warn(TAG, `[场景2] 无法获取图源名称，跳过MangaEngine初始化`);
          }
        } catch (engineErr) {
          logger.warn(TAG, `[场景2] MangaEngine初始化失败: ${String(engineErr)}`);
        }
      }
      
      // [修复] 从网络获取漫画详情（作者、简介、标签等）
      if (this.mangaEngine && this.currentManga) {
        try {
          logger.info(TAG, `📡 [场景2] 开始获取漫画详情...`);
          const detailResult = await this.mangaEngine.getMangaDetail(externalId);
          if (detailResult.success && detailResult.data) {
            const detail = detailResult.data;
            // 更新漫画详情信息
            if (detail.author) {
              this.currentManga.metadata.authors = [detail.author];
              this.currentManga.metadata.artists = [detail.author];
            }
            if (detail.description) {
              this.currentManga.description = detail.description;
            }
            if (detail.genres && detail.genres.length > 0) {
              this.currentManga.metadata.genres = detail.genres;
            }
            if (detail.status) {
              // 转换状态
              if (detail.status === '连载中') {
                this.currentManga.status = MangaStatus.ONGOING;
              } else if (detail.status === '已完结') {
                this.currentManga.status = MangaStatus.COMPLETED;
              }
            }
            logger.info(TAG, `✅ [场景2] 漫画详情已更新: 作者=${detail.author || '未知'}, 简介长度=${detail.description?.length || 0}`);
          }
        } catch (detailErr) {
          logger.warn(TAG, `[场景2] 获取漫画详情失败: ${String(detailErr)}`);
        }
      }
      
      logger.info(TAG, `📡 开始网络请求更新章节列表...`);
      
      // 网络请求获取最新章节列表
      const networkChapters = await this.fetchChapterListFromNetwork(externalId);
      if (networkChapters && networkChapters.length > 0) {
        // 对比并更新章节
        await this.updateChaptersIfNeeded(onlineComic.id, dbChapters, networkChapters);
        
        // 重新加载章节列表
        const updatedChapters = await this.loadChaptersFromDatabase(onlineComic.id);
        if (this.currentManga) {
          this.currentManga.chapters = updatedChapters;
          this.filteredChapters = updatedChapters;
          // [修复] 同步数据源以供LazyForEach使用
          this.chapterDataSource.setChapters(updatedChapters);
        }
        
        logger.info(TAG, `✅ [场景2] 章节列表已更新: ${updatedChapters.length} 个章节`);
      }
      
      return true;
    } catch (error) {
      logger.error(TAG, `[场景2] 加载失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * [场景3] 从图源进入全新的在线漫画：完整网络请求 + 存储
   * 全新漫画，需要完整的网络请求获取所有信息
   */
  private async loadOnlineMangaFromSourceNew(externalId: string): Promise<boolean> {
    try {
      logger.info(TAG, `🆕 [场景3] 从图源加载全新的在线漫画，外部ID: ${externalId}`);
      
      // 使用WebView完整加载
      await this.loadMangaDataWithWebView();
      
      logger.info(TAG, `✅ [场景3] 全新在线漫画加载完成`);
      return true;
    } catch (error) {
      logger.error(TAG, `[场景3] 加载失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 仅从数据库加载在线漫画数据（离线优先，不触发网络）
   * 智能判断使用哪个场景
   */
  private async loadOnlineMangaFromDatabaseOnly(): Promise<boolean> {
    try {
      const dm = DataManager.getInstance();
      const mangaId: string = this.pageParams?.mangaId || '';
      if (!mangaId) {
        this.loadError = '无效的漫画ID';
        return false;
      }

      // 判断mangaId是内部ID还是外部ID
      const isInternalId = mangaId.startsWith('id_');
      
      if (isInternalId) {
        // 场景1：从书库进入（内部ID）
        return await this.loadOnlineMangaFromLibrary(mangaId);
      } else {
        // 场景2或3：从图源进入（外部ID）
        // 先尝试场景2（已存在）
        const loaded = await this.loadOnlineMangaFromSourceWithUpdate(mangaId);
        if (loaded) {
          return true;
        }
        // 场景3：全新漫画（但这里是离线模式，返回false让上层走网络）
        logger.info(TAG, `离线模式下未找到漫画，需要网络请求`);
        return false;
      }
    } catch (error) {
      logger.error(TAG, `离线加载失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 辅助方法：从OnlineComicInfo构建Manga对象
   * [修复] 改为异步方法，正确加载阅读设置（图源设置 > 全局设置 > 默认值）
   */
  private async buildMangaFromOnlineComicInfo(onlineComic: OnlineComicInfo): Promise<Manga> {
    // [修复] 优先使用onlineComic的sourceName，其次使用this.sourceName，最后回退到默认值
    const displaySourceName = onlineComic.sourceName || this.sourceName || `WebView Source ${this.sourceId}`;
    logger.info(TAG, `构建 Manga 对象: sourceName=${displaySourceName}`);
    
    // [修复] 加载正确的阅读设置（图源设置 > 全局设置 > 默认值）
    const sourceIdStr = onlineComic.sourceId ? String(onlineComic.sourceId) : String(this.sourceId);
    const readingSettings = await ComicConverter.loadReadingSettings(onlineComic.id, 'default_user', sourceIdStr);
    logger.info(TAG, `加载阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}, animation=${readingSettings.pageTurnAnimation}`);
    
    return {
      id: onlineComic.id,
      title: onlineComic.title,
      alternativeTitles: [],
      description: onlineComic.description || '',
      coverImagePath: onlineComic.coverUrl || '',
      coverSourceType: ImageSourceType.NETWORK,
      status: MangaStatus.UNKNOWN,
      metadata: {
        authors: onlineComic.author ? [onlineComic.author] : [],
        artists: onlineComic.author ? [onlineComic.author] : [],
        genres: onlineComic.tags,
        themes: [],
        demographics: [],
        contentRating: undefined,
        publicationYear: undefined,
        publisher: undefined,
        serialization: undefined
      },
      chapters: [],
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: 0,
        readingStatus: ReadingStatus.UNREAD,
        totalReadingTime: 0,
        lastReadAt: 0,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: false,
      lastUpdatedAt: onlineComic.lastUpdateTime,
      sourceInfo: {
        sourceName: displaySourceName,
        sourceUrl: onlineComic.externalId,
        sourceId: String(onlineComic.sourceId || this.sourceId),
        sourceLanguage: 'zh',
        requiresLogin: false,
        apiVersion: '1.0'
      }
    };
  }

  /**
   * 辅助方法：从数据库加载章节列表
   */
  private async loadChaptersFromDatabase(comicId: string): Promise<MangaChapter[]> {
    const dm = DataManager.getInstance();
    const onlineChapters = await dm.getOnlineComicChapters(comicId);
    const mangaChapters: MangaChapter[] = [];
    
    // [修复] 即使章节信息不完整，也要显示章节
    logger.info(TAG, `从数据库加载章节: ${onlineChapters.length} 个`);
    
    for (let i = 0; i < onlineChapters.length; i++) {
      const ch = onlineChapters[i];
      
      // [调试] 详细输出从数据库读取的章节信息
      logger.debug(TAG, `📋 [数据库读取] 章节 ${i + 1}/${onlineChapters.length}: title="${ch.title}", id="${ch.id}", externalId="${ch.externalId || 'undefined'}"`);
      
      // [修复] 即使没有章节标题，也要显示
      const displayTitle = ch.title || `第${ch.chapterNumber || i + 1}章`;
      
      // [修复] 使用getOnlineChapterPages而不是getChapterPages
      const pageInfos = await dm.getOnlineChapterPages(ch.id);
      const isDownloaded: boolean = pageInfos.length > 0;
      
      // [修复] 将数据库中的页面信息转换为MangaPage格式，保留页面数据
      const pages: MangaPage[] = pageInfos.map((pageInfo, arrayIndex) => {
        let sourceType: ImageSourceType;
        if (pageInfo.imageUrl.startsWith('http://') || pageInfo.imageUrl.startsWith('https://')) {
          sourceType = ImageSourceType.NETWORK;
        } else if (pageInfo.imageUrl.startsWith('/')) {
          sourceType = ImageSourceType.LOCAL;
        } else {
          sourceType = ImageSourceType.RAWFILE;
        }
        
        const page: MangaPage = {
          id: pageInfo.id,
          index: arrayIndex,
          sourceType: sourceType,
          imagePath: pageInfo.imageUrl,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width,
          height: pageInfo.height,
          fileSize: pageInfo.fileSize,
          isLoaded: false
        };
        return page;
      });
      
      const chapter: MangaChapter = {
        id: ch.id,
        title: displayTitle,
        chapterNumber: ch.chapterNumber || i + 1,
        pages: pages, // [修复] 使用转换后的页面数据而不是空数组
        publishDate: ch.publishTime || Date.now(),
        language: 'zh-CN',
        scanlationGroup: '',
        isDownloaded: isDownloaded,
        downloadProgress: isDownloaded ? 100 : 0,
        downloadStatus: isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
        localPath: undefined,
        externalId: ch.externalId
      };
      mangaChapters.push(chapter);
      
      // [调试] 输出转换后的章节信息
      logger.debug(TAG, `  ✅ 章节转换完成 ${i + 1}: title="${displayTitle}", id="${chapter.id}", externalId="${chapter.externalId || 'undefined'}", pages=${pageInfos.length}`);
    }
    
    logger.info(TAG, `章节加载完成: ${mangaChapters.length} 个`);
    return mangaChapters;
  }

  /**
   * 辅助方法：从数据库加载阅读进度
   */
  private async loadReadingProgressFromDatabase(comicId: string): Promise<void> {
    try {
      const dm = DataManager.getInstance();
      const history: ReadHistory[] = await dm.getReadHistoryByComic(comicId, 'default_user', 1);
      if (history && history.length > 0 && this.currentManga) {
        const lastRead: ReadHistory = history[0];
        this.currentManga.readingProgress = {
          currentChapterId: lastRead.chapterId,
          currentPageIndex: lastRead.pageIndex,
          readingStatus: ReadingStatus.READING,
          totalReadingTime: 0,
          lastReadAt: lastRead.readTime,
          readingPercentage: 0
        };
        logger.info(TAG, `阅读进度加载: 章节=${lastRead.chapterId}, 页=${lastRead.pageIndex}`);
      }
    } catch (error) {
      logger.warn(TAG, `加载阅读进度失败: ${String(error)}`);
    }
  }

  /**
   * 辅助方法：加载收藏状态
   */
  private async loadFavoriteStatus(comicId: string): Promise<void> {
    try {
      const favorited: boolean = await this.dataService.isFavorited(comicId);
      if (this.currentManga) {
        this.currentManga.isFavorite = favorited;
      }
      logger.info(TAG, `收藏状态: ${String(favorited)}`);
    } catch (error) {
      logger.warn(TAG, `加载收藏状态失败: ${String(error)}`);
    }
  }

  /**
   * 辅助方法：从网络获取章节列表
   */
  private async fetchChapterListFromNetwork(externalId: string): Promise<WebViewChapterInfo[]> {
    try {
      if (!this.mangaEngine) {
        logger.warn(TAG, `MangaEngine未初始化`);
        return [];
      }
      
      const result = await this.mangaEngine.getChapterList(externalId);
      if (result.success && result.data) {
        logger.info(TAG, `网络获取章节列表成功: ${result.data.length} 个章节`);
        return result.data;
      } else {
        logger.warn(TAG, `网络获取章节列表失败: ${result.error}`);
        return [];
      }
    } catch (error) {
      logger.error(TAG, `网络请求失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 辅助方法：对比并更新章节
   */
  private async updateChaptersIfNeeded(
    comicId: string,
    dbChapters: MangaChapter[],
    networkChapters: WebViewChapterInfo[]
  ): Promise<void> {
    try {
      const dm = DataManager.getInstance();
      
      // 创建数据库章节的externalId映射
      const dbChapterMap = new Map<string, MangaChapter>();
      for (const ch of dbChapters) {
        if (ch.externalId) {
          dbChapterMap.set(ch.externalId, ch);
        }
      }
      
      // 检查网络章节，找出新增的
      let newChapterCount = 0;
      for (const networkCh of networkChapters) {
        const externalId = networkCh.externalId || networkCh.id || networkCh.url;
        if (!externalId) {
          logger.warn(TAG, `章节缺少externalId: ${networkCh.title}`);
          continue;
        }
        
        if (!dbChapterMap.has(externalId)) {
          // 新章节，添加到数据库
          const chapterInput: OnlineChapterInfoInput = {
            comicId: comicId,
            externalId: externalId,
            title: networkCh.title,
            chapterNumber: networkCh.number || 0,
            url: networkCh.url || '',
            pageCount: 0,
            publishTime: typeof networkCh.publishTime === 'number' ? networkCh.publishTime : Date.now(),
            isDownloaded: false,
            downloadPath: undefined,
            index: networkCh.number || 0
          };
          
          await dm.addOnlineChapterInfo(chapterInput);
          newChapterCount++;
          logger.info(TAG, `新增章节: ${networkCh.title}`);
        }
      }
      
      if (newChapterCount > 0) {
        logger.info(TAG, `✅ 新增了 ${newChapterCount} 个章节`);
      } else {
        logger.info(TAG, `章节列表无更新`);
      }
    } catch (error) {
      logger.error(TAG, `更新章节失败: ${String(error)}`);
    }
  }

  // 保留原有方法的剩余部分
  private async _loadOnlineMangaFromDatabaseOnly_OLD(): Promise<boolean> {
    try {
      const dm = DataManager.getInstance();
      const externalId: string = this.pageParams?.mangaId || '';
      if (!externalId) {
        this.loadError = '无效的漫画ID';
        return false;
      }

      // 优先查询在线独立表
      const onlineComic = await dm.getOnlineComicByExternalId(externalId);
      if (onlineComic) {
        const mangaObj: Manga = await this.buildMangaFromOnlineComicInfo(onlineComic);
        this.currentManga = mangaObj;

        // 章节列表（来自 online_chapter）
        const mangaChapters = await this.loadChaptersFromDatabase(onlineComic.id);
        if (this.currentManga) {
          this.currentManga.chapters = mangaChapters;
          this.filteredChapters = this.currentManga.chapters;
        } else {
          this.filteredChapters = mangaChapters;
        }
        this.chapterSortOrder = ChapterSortOrder.ASCENDING;
        this.applyChapterFilters();
        await this.loadChapterProgressData();
        this.isChapterLoading = false;
        logger.info(TAG, `✅ 离线章节加载完成(online_chapter)，共 ${mangaChapters.length} 章`);
        return mangaChapters.length > 0;
      }

      // 兼容旧数据：回退到本地通用表
      const comicInfo = await dm.getComicById(externalId);
      if (comicInfo) {
        this.currentManga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
        const dbChapters = await dm.getComicChapters(externalId);
        const mangaChapters: MangaChapter[] = [];
        for (let i = 0; i < dbChapters.length; i++) {
          const ch = dbChapters[i];
          const chapter: MangaChapter = {
            id: ch.id,
            title: ch.title,
            chapterNumber: ch.index,
            pages: [],
            publishDate: ch.publishTime || Date.now(),
            language: 'zh-CN',
            scanlationGroup: '',
            isDownloaded: ch.isDownloaded || false,
            downloadProgress: ch.isDownloaded ? 100 : 0,
            downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
            localPath: ch.downloadPath,
            externalId: ch.externalId // [修复] 从数据库读取外部章节ID
          };
          mangaChapters.push(chapter);
        }
        this.currentManga.chapters = mangaChapters;
        this.filteredChapters = this.currentManga.chapters;
        this.chapterSortOrder = ChapterSortOrder.ASCENDING;
        this.applyChapterFilters();
        await this.loadChapterProgressData();
        this.isChapterLoading = false;
        logger.info(TAG, `✅ 离线章节加载完成(compat_local)，共 ${mangaChapters.length} 章`);
        return mangaChapters.length > 0;
      }

      // 数据库无记录，保持空展示
      this.currentManga = null;
      logger.warn(TAG, '离线优先加载：数据库无在线漫画记录');
      return false;
    } catch (error) {
      logger.error(TAG, `离线优先加载失败: ${String(error)}`);
      return false;
    }
  }
  
  /**
   * 转换MangaInfo到Manga
   * [修复] 改为异步方法，正确加载阅读设置（图源设置 > 全局设置 > 默认值）
   */
  private async convertMangaInfoToManga(info: MangaInfo): Promise<Manga> {
    // 处理简介中的转义符和HTML标签
    let processedDescription = info.description || '暂无简介';
    if (processedDescription !== '暂无简介') {
      // 替换 \n 为真正的换行符
      processedDescription = processedDescription.replace(/\\n/g, '\n');
      // 移除HTML标签（如果有）
      processedDescription = processedDescription.replace(/<[^>]*>/g, '');
      // 处理其他常见转义符
      processedDescription = processedDescription.replace(/\\t/g, '\t');
      processedDescription = processedDescription.replace(/\\r/g, '\r');
    }
    
    // [修复] 加载正确的阅读设置（图源设置 > 全局设置 > 默认值）
    const mangaId = info.id || '';
    const sourceIdStr = String(this.sourceId);
    logger.info(TAG, `convertMangaInfoToManga: 准备加载阅读设置, mangaId=${mangaId}, sourceId=${this.sourceId}, sourceIdStr=${sourceIdStr}`);
    const readingSettings = await ComicConverter.loadReadingSettings(mangaId, 'default_user', sourceIdStr);
    logger.info(TAG, `加载阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}, animation=${readingSettings.pageTurnAnimation}`);
    
    const manga: Manga = {
      id: info.id || '',
      title: info.title,
      alternativeTitles: [],
      description: processedDescription,
      coverImagePath: info.cover,
      coverSourceType: ImageSourceType.NETWORK,
      status: this.convertMangaStatus(info.status),
      metadata: {
        authors: info.author ? [info.author] : [],
        artists: info.author ? [info.author] : [],
        genres: info.genres || [],
        themes: [],
        demographics: [],
        contentRating: undefined,
        publicationYear: undefined,
        publisher: undefined,
        serialization: undefined
      },
      chapters: [],
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: 0,
        readingStatus: ReadingStatus.UNREAD,
        totalReadingTime: 0,
        lastReadAt: 0,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: false,
      lastUpdatedAt: info.updated ? new Date(info.updated).getTime() : Date.now(),
      sourceInfo: {
        sourceName: this.sourceName || `WebView Source ${this.sourceId}`,
        sourceUrl: info.url || info.id || '',
        sourceId: this.sourceId.toString(),
        sourceLanguage: 'zh',
        requiresLogin: false,
        apiVersion: '1.0'
      }
    };
    
    logger.debug(TAG, `转换Manga: id="${manga.id}", title="${manga.title}", cover="${manga.coverImagePath}"`);
    return manga;
  }
  
  /**
   * 转换WebView章节信息到MangaChapter
   */
  private convertWebViewChapterInfoToMangaChapter(chapters: WebViewChapterInfo[]): MangaChapter[] {
    const allChapters = chapters.map((ch, index) => {
      // [修复] WebView章节的id字段就是完整的外部ID（例如 /comic/xxx/chapter/xxx）
      // 不要混淆：ch.id = 外部ID, chapter.id = 临时内部ID（稍后会被数据库ID覆盖）
      const externalChapterId = ch.externalId || ch.id || ch.url;
      
      // [严格验证] 确保externalId有效
      if (!externalChapterId || externalChapterId.trim() === '') {
        const errorMsg = `❌ 章节 "${ch.title}" 缺少有效的外部ID！ch.externalId=${ch.externalId}, ch.id=${ch.id}, ch.url=${ch.url}`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
      
      // [修复] 临时使用外部ID作为内部ID，稍后会被数据库生成的ID覆盖
      // 但externalId字段必须保持不变
      const chapterId = externalChapterId;
      
      let publishMs: number = Date.now();
      if (ch.publishTime) {
        const raw = String(ch.publishTime);
        const num = Number(raw);
        if (!Number.isNaN(num)) {
          publishMs = num;
        } else {
          const parsed = Date.parse(raw);
          if (!Number.isNaN(parsed)) {
            publishMs = parsed;
          }
        }
      }
      const chapter: MangaChapter = {
        id: chapterId,  // 临时ID，稍后会被覆盖
        title: ch.title,
        chapterNumber: ch.number || (index + 1),
        pages: [],
        publishDate: publishMs,
        language: 'zh',
        scanlationGroup: '',
        isDownloaded: false,
        downloadStatus: DownloadStatus.PENDING,
        downloadProgress: 0,
        localPath: undefined,
        externalId: externalChapterId // [关键] 外部ID，用于WebView请求
      };
      logger.debug(TAG, `📄 转换章节: title="${ch.title}", 临时id=${chapterId}, externalId=${externalChapterId}`);
      return chapter;
    });
    
    // [修复] 去重：根据externalId去重
    const uniqueChapters: MangaChapter[] = [];
    const seenExternalIds = new Set<string>();
    for (const chapter of allChapters) {
      const extId = chapter.externalId;
      if (extId && typeof extId === 'string' && !seenExternalIds.has(extId)) {
        seenExternalIds.add(extId);
        uniqueChapters.push(chapter);
      }
    }
    
    logger.info(TAG, `章节去重: 原始${allChapters.length}章 -> 去重后${uniqueChapters.length}章`);
    return uniqueChapters;
  }
  
  /**
   * 转换漫画状态
   */
  private convertMangaStatus(status?: string): MangaStatus {
    if (!status) return MangaStatus.UNKNOWN;
    
    const statusLower = status.toLowerCase();
    if (statusLower.includes('ongoing') || statusLower.includes('连载') || statusLower.includes('連')) {
      return MangaStatus.ONGOING;
    } else if (statusLower.includes('completed') || statusLower.includes('完结') || statusLower.includes('完')) {
      return MangaStatus.COMPLETED;
    } else if (statusLower.includes('hiatus') || statusLower.includes('暂停')) {
      return MangaStatus.HIATUS;
    } else if (statusLower.includes('cancelled') || statusLower.includes('取消')) {
      return MangaStatus.CANCELLED;
    }
    
    return MangaStatus.UNKNOWN;
  }

  /**
   * 从数据库加载在线漫画数据（阅读进度）
   */
  private async loadOnlineMangaDataFromDatabase(): Promise<void> {
    try {
      if (!this.currentManga) {
        return;
      }
      
      const dataManager = DataManager.getInstance();
      
      // 查询阅读历史记录
      const history: ReadHistory[] = await dataManager.getReadHistoryByComic(this.currentManga.id, 'default_user', 1);
      if (history && history.length > 0) {
        const lastRead: ReadHistory = history[0];
        this.currentManga.readingProgress = {
          currentChapterId: lastRead.chapterId,
          currentPageIndex: lastRead.pageIndex,
          readingStatus: ReadingStatus.READING,
          totalReadingTime: 0,
          lastReadAt: lastRead.readTime,
          readingPercentage: 0
        };
        logger.info(TAG, `从数据库加载阅读进度: 章节=${lastRead.chapterId}, 页=${lastRead.pageIndex}`);
      }
      
    } catch (error) {
      logger.error(TAG, `从数据库加载在线漫画数据失败: ${error}`);
    }
  }
  
  /**
   * 保存在线漫画信息到数据库
   */
  private async saveOnlineMangaToDatabase(): Promise<void> {
    try {
      if (!this.currentManga || !this.pageParams?.mangaId) {
        return;
      }
      
      const dm = DataManager.getInstance();
      
      // 获取作者信息
      let authorStr = '';
      if (this.currentManga.metadata && this.currentManga.metadata.authors && this.currentManga.metadata.authors.length > 0) {
        authorStr = this.currentManga.metadata.authors[0];
        for (let i = 1; i < this.currentManga.metadata.authors.length; i++) {
          authorStr += ', ' + this.currentManga.metadata.authors[i];
        }
      }
      
      // [重构] 确保externalId不是内部ID格式
      let validExternalId = this.pageParams.mangaId;
      if (validExternalId.startsWith('id_')) {
        // 如果pageParams.mangaId是内部ID，尝试从sourceInfo获取真实外部ID
        if (this.currentManga.sourceInfo && this.currentManga.sourceInfo.sourceUrl && !this.currentManga.sourceInfo.sourceUrl.startsWith('id_')) {
          validExternalId = this.currentManga.sourceInfo.sourceUrl;
          logger.info(TAG, `使用sourceInfo.sourceUrl作为externalId: ${validExternalId}`);
        } else {
          const errorMsg = `❌ 无法获取有效的externalId！mangaId=${this.pageParams.mangaId}`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
      }
      
      // [重构] 先检查online_comic_info表中是否已存在（通过externalId）
      let internalComicId: string;
      const existingComic = await dm.getOnlineComicByExternalId(validExternalId);
      if (existingComic) {
        internalComicId = existingComic.id;
        logger.info(TAG, `✅ 在线漫画已存在于online_comic_info表: ${this.currentManga.title}, ID: ${internalComicId}`);
      } else {
        // [重构] 使用saveComicFromSource保存到online_comic_info表
        const comicTags: string[] = [];
        const comicData: OnlineComicSourceSaveInput = {
          id: validExternalId,  // 使用外部ID作为id字段
          title: this.currentManga.title,
          author: authorStr,
          description: this.currentManga.description || '',
          coverUrl: (this.currentManga.coverImagePath as string) || '',
          tags: comicTags,
          rating: 0,
          updateTime: Date.now(),
          sourceName: this.sourceName || ''  // [修复] 传递图源名称
        };
        
        logger.info(TAG, `📝 准备保存在线漫画: sourceName="${this.sourceName || 'N/A'}"`);
        internalComicId = await dm.saveComicFromSource(this.sourceId, comicData, undefined);
        logger.info(TAG, `✅ 在线漫画已保存到online_comic_info表: ${this.currentManga.title}, 章节数: ${this.currentManga.chapters.length}, 内部ID: ${internalComicId}`);
      }
      
      // 更新currentManga的ID为内部ID（仅在新保存或已存在时）
      this.currentManga.id = internalComicId;
      
      // 保存章节信息和页面信息
      for (let i = 0; i < this.currentManga.chapters.length; i++) {
        const chapter = this.currentManga.chapters[i];
        
        // 获取章节页数和页面信息
        let chapterPageCount = 0;
        let pageInfos: SourcePageInfo[] = [];
        
        // 如果章节已有页面数据，直接使用
        if (chapter.pages && chapter.pages.length > 0) {
          chapterPageCount = chapter.pages.length;
          pageInfos = chapter.pages.map((page: MangaPage, index: number): SourcePageInfo => ({
            page: index,
            imageUrl: page.imageUrl || page.imagePath || '',
            width: page.width || 0,
            height: page.height || 0
          }));
        } else if (this.mangaEngine && chapter.id && this.shouldPrefetchPagesForSource()) {
          // WebView图源：动态获取页面列表
          try {
            logger.info(TAG, `📥 获取章节 "${chapter.title}" 的页面列表...`);
            const pageListResult = await this.mangaEngine.getPageList(chapter.id, this.pageParams.mangaId);
            
            if (pageListResult.success && pageListResult.data) {
              pageInfos = pageListResult.data;
              chapterPageCount = pageInfos.length;
              logger.info(TAG, `✅ 章节 "${chapter.title}" 获取到 ${chapterPageCount} 个页面`);
            } else {
              logger.warn(TAG, `⚠️ 章节 "${chapter.title}" 获取页面列表失败: ${pageListResult.error}`);
            }
          } catch (error) {
            logger.error(TAG, `❌ 获取章节 "${chapter.title}" 页面列表异常: ${error}`);
          }
        } else if (this.mangaEngine && chapter.id && !this.shouldPrefetchPagesForSource()) {
          logger.info(TAG, '当前图源禁用页面预取');
        }
        
        // [严格验证] 检查章节是否包含有效的externalId
        const externalIdToSave = chapter.externalId || chapter.id;
        
        // [调试] 详细输出章节信息
        logger.debug(TAG, `📋 [保存前] 章节 ${i + 1}/${this.currentManga.chapters.length}: title="${chapter.title}", id="${chapter.id}", externalId="${chapter.externalId}", 使用externalId="${externalIdToSave}"`);
        
        if (!externalIdToSave || externalIdToSave.startsWith('id_')) {
          const errorMsg = `❌ 严重错误：章节 "${chapter.title}" 缺少有效的外部ID！externalId=${chapter.externalId}, id=${chapter.id}`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
        
        logger.info(TAG, `✅ 准备保存在线章节 "${chapter.title}": externalId=${externalIdToSave}`);
        
        // [重构] 使用online_chapter表存储在线章节信息
        // [修复] 从章节标题提取真实的章节号，而不是使用数组索引
        const extractedChapterNumber = this.extractChapterNumber(chapter.title);
        const finalChapterNumber = extractedChapterNumber > 0 ? extractedChapterNumber : (i + 1);
        logger.debug(TAG, `📊 章节 "${chapter.title}": 提取的章节号=${extractedChapterNumber}, 最终使用=${finalChapterNumber}`);
        
        const onlineChapterInput: OnlineChapterInfoInput = {
          comicId: internalComicId,
          externalId: externalIdToSave,
          title: chapter.title,
          chapterNumber: finalChapterNumber,  // 使用从标题提取的章节号
          url: '',  // MangaChapter没有url字段，留空
          pageCount: chapterPageCount,
          publishTime: typeof chapter.publishDate === 'number' ? chapter.publishDate : Date.now(),
          isDownloaded: false,
          downloadPath: undefined,
          index: i
        };
        
        const chapterId = await dm.addOnlineChapterInfo(onlineChapterInput);
        
        // [修复] 更新章节的内部ID，但必须保持externalId不变
        const savedExternalId = chapter.externalId;  // 保存原始externalId
        chapter.id = chapterId;
        chapter.externalId = savedExternalId;  // 恢复externalId，防止被覆盖
        logger.info(TAG, `✅ 在线章节保存成功: title="${chapter.title}", externalId=${savedExternalId}, internalId=${chapterId}`);
        
        // [重构] 保存在线页面信息到online_page表
        if (pageInfos.length > 0) {
          for (let j = 0; j < pageInfos.length; j++) {
            const pageInfo = pageInfos[j];
            const onlinePageInput: OnlinePageInfoInput = {
              chapterId: chapterId,
              pageNumber: j,
              imageUrl: pageInfo.imageUrl,
              width: pageInfo.width || 0,
              height: pageInfo.height || 0,
              fileSize: 0
            };
            
            await dm.addOnlinePageInfo(onlinePageInput);
          }
          logger.info(TAG, `✅ 已保存在线章节 "${chapter.title}" 的 ${pageInfos.length} 个页面信息到online_page表`);
        }
      }
      
      logger.info(TAG, `✅ 已保存 ${this.currentManga.chapters.length} 个章节信息到数据库`);
      
      // [修复] 保存后重新加载章节信息，确保UI正确显示
      logger.info(TAG, `📡 重新加载章节信息以更新UI...`);
      await this.loadChaptersFromDatabase(internalComicId);
      
    } catch (error) {
      logger.error(TAG, `保存在线漫画信息到数据库失败: ${error}`);
    }
  }
  
  /**
   * 转换状态枚举为字符串
   */
  private convertStatusToString(status: MangaStatus): string {
    switch (status) {
      case MangaStatus.ONGOING: return '连载中';
      case MangaStatus.COMPLETED: return '已完结';
      case MangaStatus.HIATUS: return '暂停';
      case MangaStatus.CANCELLED: return '已取消';
      default: return '未知';
    }
  }

  /**
   * 更新过滤后的章节列表
   */
  private updateFilteredChapters(): void {
    logger.debug(TAG, '开始更新过滤章节列表');

    if (!this.currentManga) {
      logger.warn(TAG, 'currentManga为空，无法更新章节列表');
      return;
    }

    logger.info(TAG, `当前漫画章节总数: ${this.currentManga.chapters.length}`);

    let chapters: MangaChapter[] = [];
    for (const chapter of this.currentManga.chapters) {
      chapters.push(chapter);
    }

    logger.debug(TAG, `复制章节数组，长度: ${chapters.length}`);

    // 应用过滤器
    switch (this.chapterFilter) {
      case ChapterFilterType.UNREAD:
        chapters = chapters.filter((ch: MangaChapter) => !this.isChapterRead(ch));
        logger.debug(TAG, `应用未读过滤器后，章节数: ${chapters.length}`);
        break;
      case ChapterFilterType.DOWNLOADED:
        chapters = chapters.filter((ch: MangaChapter) => ch.isDownloaded);
        logger.debug(TAG, `应用已下载过滤器后，章节数: ${chapters.length}`);
        break;
      case ChapterFilterType.BOOKMARKED:
        chapters = chapters.filter((ch: MangaChapter) => (this.currentManga as Manga).bookmarks.some((bookmark: MangaBookmark) => bookmark.chapterId === ch.id));
        logger.debug(TAG, `应用书签过滤器后，章节数: ${chapters.length}`);
        break;
      default:
        logger.debug(TAG, `使用默认过滤器（显示全部），章节数: ${chapters.length}`);
        break;
    }

    let compareResult: number = 0;
    chapters.sort((a: MangaChapter, b: MangaChapter) => {
      const order: number = this.chapterSortOrder === ChapterSortOrder.ASCENDING ? 1 : -1;
      let keyA: number = 0;
      let keyB: number = 0;
      if (this.chapterSortKey === ChapterSortKey.CHAPTER_NUMBER) {
        keyA = a.chapterNumber;
        keyB = b.chapterNumber;
      } else {
        const aTime: number = a.publishDate !== undefined
          ? this.getTimestampFromPublishDate(a.publishDate as number | Date)
          : 0;
        const bTime: number = b.publishDate !== undefined
          ? this.getTimestampFromPublishDate(b.publishDate as number | Date)
          : 0;
        keyA = aTime;
        keyB = bTime;
      }
      if (keyA < keyB) {
        compareResult = -1 * order;
      } else if (keyA > keyB) {
        compareResult = 1 * order;
      } else {
        compareResult = 0;
      }
      return compareResult;
    });

    logger.info(TAG, `排序后的最终章节数: ${chapters.length}`);

    // 输出前几个章节的信息用于调试
    chapters.slice(0, 3).forEach((chapter: MangaChapter, index: number) => {
      logger.debug(TAG, `章节${index + 1}: ${chapter.title} (编号: ${chapter.chapterNumber})`);
    });

    this.filteredChapters = chapters;
    logger.info(TAG, `filteredChapters已更新，长度: ${this.filteredChapters.length}`);

    // 同步数据源以供LazyForEach使用
    this.chapterDataSource.setChapters(chapters);
  }

  private showChapterSortMenu(): void {
    if (!this.uiContext) {
      return;
    }
    const prompt = this.uiContext.getPromptAction();
    if (!prompt) {
      return;
    }
    interface ActionMenuButtonDef { text: string; color: Resource }
    interface ActionMenuOptionsDef {
      title: string;
      buttons: [
        ActionMenuButtonDef,
        ActionMenuButtonDef?,
        ActionMenuButtonDef?,
        ActionMenuButtonDef?,
        ActionMenuButtonDef?,
        ActionMenuButtonDef?
      ];
      isModal?: boolean;
      showInSubWindow?: boolean;
    }
    interface ActionMenuResult { index: number }
    const btnPrimary: Resource = ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    const btnInactive: Resource = ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme);
    const buttons: [ActionMenuButtonDef, ActionMenuButtonDef, ActionMenuButtonDef, ActionMenuButtonDef] = [
      { text: '按章节顺序（升序）', color: btnPrimary },
      { text: '按章节顺序（降序）', color: btnPrimary },
      { text: '按时间顺序（升序）', color: btnPrimary },
      { text: '按时间顺序（降序）', color: btnPrimary }
    ];
    const options: ActionMenuOptionsDef = {
      title: '章节排序',
      buttons: buttons,
      isModal: false
    };
    prompt.showActionMenu(options)
      .then((data: ActionMenuResult) => {
        const idx: number = data.index;
        if (idx === 0) {
          this.chapterSortKey = ChapterSortKey.CHAPTER_NUMBER;
          this.chapterSortOrder = ChapterSortOrder.ASCENDING;
        } else if (idx === 1) {
          this.chapterSortKey = ChapterSortKey.CHAPTER_NUMBER;
          this.chapterSortOrder = ChapterSortOrder.DESCENDING;
        } else if (idx === 2) {
          this.chapterSortKey = ChapterSortKey.PUBLISH_TIME;
          this.chapterSortOrder = ChapterSortOrder.ASCENDING;
        } else if (idx === 3) {
          this.chapterSortKey = ChapterSortKey.PUBLISH_TIME;
          this.chapterSortOrder = ChapterSortOrder.DESCENDING;
        }
        this.updateFilteredChapters();
      })
      .catch((err: Error) => {
        logger.warn(TAG, `排序菜单取消或错误: ${err.message}`);
      });
  }

  /**
   * 切换收藏状态（持久化）
   */
  private async toggleFavorite(): Promise<void> {
    const mangaObj: Manga | null = this.currentManga;
    if (!mangaObj) {
      return;
    }

    const mangaId: string = mangaObj.id;
    const nextState: boolean = !mangaObj.isFavorite;
    try {
      if (nextState) {
        // 如果是WebView图源，先检查重复
        if (this.useWebView && this.sourceId) {
          try {
            // 检查是否存在相似漫画
            const similarComics = await DataManager.getInstance().findSimilarComics(mangaObj.title, 0.85);
            
            // 排除当前漫画自己
            const otherComics = similarComics.filter((comic: DatabaseRecord) => {
              const comicObj: ESObject = comic as ESObject;
              return (comicObj.id as string) !== mangaObj.id;
            });
            
            if (otherComics.length > 0) {
              // 显示重复确认对话框
              this.showDuplicateDialog(mangaObj, otherComics);
              return; // 等待用户选择
            }
            
            // 没有重复，确保保存到本地通用表并加入收藏
            if (!mangaId.startsWith('id_')) {
              await this.saveOnlineMangaToDatabase();
            }
            // [修复] 使用更新后的内部ID
            const internalId: string = this.currentManga?.id || mangaId;
            await this.dataService.addToFavorites(internalId, []);
            logger.info(TAG, `在线漫画已加入收藏: ${mangaObj.title}, 内部ID=${internalId}`);
            
            // [修复] 下载封面时使用内部ID
            if (mangaObj.coverImagePath) {
              this.downloadAndSaveCover(internalId, mangaObj.coverImagePath).catch((err: Error) => {
                logger.warn(TAG, `封面下载失败: ${err.message}`);
              });
            }
          } catch (saveErr) {
            logger.warn(TAG, `保存漫画到数据库失败: ${String(saveErr)}`);
          }
        } else {
          // [修复] 非WebView图源也需要正确处理收藏
          const internalId: string = this.currentManga?.id || mangaId;
          await this.dataService.addToFavorites(internalId, []);
          logger.info(TAG, `漫画已加入收藏: ${mangaObj.title}, ID=${internalId}`);
          
          // 下载并保存封面
          if (mangaObj.coverImagePath) {
            this.downloadAndSaveCover(internalId, mangaObj.coverImagePath).catch((err: Error) => {
              logger.warn(TAG, `封面下载失败: ${err.message}`);
            });
          }
        }
      } else {
        const internalIdToRemove: string = this.currentManga?.id || mangaId;
        await this.dataService.removeFromFavorites(internalIdToRemove);
        logger.info(TAG, `已移除收藏: ${internalIdToRemove}`);
      }
      
      // 更新状态并触发UI刷新
      if (this.currentManga) {
        this.currentManga.isFavorite = nextState;
        // 重新赋值以触发@State更新
        const updatedManga = this.currentManga;
        this.currentManga = null;
        this.currentManga = updatedManga;
      }
      logger.info(TAG, `漫画收藏状态已保存: ${String(nextState)}`);
    } catch (err) {
      logger.error(TAG, `收藏状态更新失败: ${String(err)}`);
    }
  }
  
  /**
   * 显示重复漫画确认对话框
   */
  private showDuplicateDialog(newManga: Manga, existingComics: DatabaseRecord[]): void {
    const existingComic: ESObject = existingComics[0] as ESObject; // 取第一个最相似的
    
    const message = `书库中已存在相似的漫画：\n\n` +
      `📚 已有: ${existingComic.title}\n` +
      `   作者: ${existingComic.author || '未知'}\n` +
      `   章节: ${existingComic.chapterCount || 0}章\n` +
      `   来源: 图源${existingComic.sourceId}\n\n` +
      `🆕 新增: ${newManga.title}\n` +
      `   作者: ${newManga.metadata.authors.join(', ') || '未知'}\n` +
      `   章节: ${newManga.chapters.length}章\n` +
      `   来源: 图源${this.sourceId}\n\n` +
      `建议合并到已有漫画，避免重复。`;
    
    this.getUIContext().showAlertDialog({
      title: '发现重复漫画',
      message: message,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: async () => {
          try {
            logger.info(TAG, '用户取消添加重复漫画，回滚可能的数据库写入');
            const externalId: string = String(this.pageParams?.mangaId || newManga.id);
            const dm = DataManager.getInstance();
            const record = await dm.getComicByExternalId(externalId);
            if (record) {
              const obj: ESObject = record as ESObject;
              const internalId: string = String(obj.id);
              await dm.deleteComic(internalId);
              logger.info(TAG, `已删除取消前写入的在线漫画记录: externalId=${externalId}, id=${internalId}`);
            } else {
              logger.info(TAG, `未发现需要回滚的记录 externalId=${externalId}`);
            }
          } catch (err) {
            logger.warn(TAG, `取消操作回滚失败: ${String(err)}`);
          }
        }
      },
      secondaryButton: {
        value: '合并到已有',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme),
        action: async () => {
          try {
            // 合并漫画数据
            await DataManager.getInstance().mergeComics(
              existingComic.id as string,
              newManga.id
            );
            
            // 添加到收藏
            await this.dataService.addToFavorites(existingComic.id as string, []);
            
            this.getUIContext().getPromptAction().showToast({
              message: '已合并到现有漫画',
              duration: 2000
            });
            
            logger.info(TAG, `漫画已合并: ${newManga.id} -> ${existingComic.id}`);
            
            // 更新UI状态
            if (this.currentManga) {
              this.currentManga.id = existingComic.id as string;  // 更新为内部ID
              this.currentManga.isFavorite = true;
              const updatedManga = this.currentManga;
              this.currentManga = null;
              this.currentManga = updatedManga;
            }
          } catch (error) {
            logger.error(TAG, '合并漫画失败', String(error));
            this.getUIContext().getPromptAction().showToast({
              message: '合并失败',
              duration: 2000
            });
          }
        }
      }
    });
  }
  
  /**
   * 下载并保存封面图片
   */
  private async downloadAndSaveCover(mangaId: string, coverUrl: string): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取Context');
      }
      
      // 创建漫画目录
      const mangaDir = `${context.filesDir}/manga_covers/${mangaId}`;
      if (!SafeFileUtils.accessSync(mangaDir)) {
        SafeFileUtils.mkdirSync(mangaDir, true);
      }
      
      // 确定文件扩展名
      const urlParts = coverUrl.split('.');
      const ext = urlParts.length > 1 ? urlParts[urlParts.length - 1].split('?')[0] : 'jpg';
      const coverPath = `${mangaDir}/cover.${ext}`;
      
      logger.info(TAG, `开始下载封面: ${coverUrl} -> ${coverPath}`);
      
      // 使用http下载图片
      const request = http.createHttp();
      const response = await request.request(coverUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      
      if (response.responseCode === 200 && response.result) {
        // 保存图片数据
        const file = SafeFileUtils.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        SafeFileUtils.writeSync(file.fd, response.result as ArrayBuffer);
        SafeFileUtils.closeSync(file);
        
        logger.info(TAG, `封面保存成功: ${coverPath}`);
      } else {
        throw new Error(`下载失败，状态码: ${response.responseCode}`);
      }
      
      request.destroy();
    } catch (err) {
      logger.error(TAG, `下载封面失败: ${String(err)}`);
      throw err as Error;
    }
  }

  /**
   * 使用OnlineImageLoader加载封面图片（支持自定义headers）
   * 用于加载需要Referer等headers的网络封面图片
   */
  private isPhotos18Source(): boolean {
    if (this.sourcePkg === 'com.manxia.extension.all.photos18') {
      return true;
    }
    if (this.sourceName && this.sourceName.toLowerCase().includes('photos18')) {
      return true;
    }
    return false;
  }

  private getPhotos18SiteOrigin(): string {
    return 'https://www.photos18.com';
  }

  private buildPhotos18CoverHeaders(_coverUrl: string): OnlineRequestHeaders {
    const siteOrigin = this.getPhotos18SiteOrigin();
    const fallbackReferer = this.coverHttpHeaders.referer || siteOrigin;
    const headers: OnlineRequestHeaders = {
      referer: fallbackReferer,
      origin: siteOrigin,
      userAgent: this.coverHttpHeaders.userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      accept: this.coverHttpHeaders.accept || 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
      acceptLanguage: this.coverHttpHeaders.acceptLanguage || 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      cachePartition: this.photos18CoverPartition
    };
    return headers;
  }

  private cloneCoverExtraHeaders(entries?: OnlineRequestHeaderEntry[]): OnlineRequestHeaderEntry[] | undefined {
    if (!entries || entries.length === 0) {
      return undefined;
    }
    const cloned: OnlineRequestHeaderEntry[] = [];
    let index = 0;
    while (index < entries.length) {
      const entry = entries[index];
      cloned.push({
        name: entry.name,
        value: entry.value
      } as OnlineRequestHeaderEntry);
      index = index + 1;
    }
    return cloned;
  }

  private buildGenericCoverHeaders(coverUrl: string): OnlineRequestHeaders {
    const fallbackReferer = coverUrl.split('/').slice(0, 3).join('/') + '/';
    const headers: OnlineRequestHeaders = {
      referer: this.coverHttpHeaders.referer || fallbackReferer,
      userAgent: this.coverHttpHeaders.userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      accept: this.coverHttpHeaders.accept,
      origin: this.coverHttpHeaders.origin,
      cookie: this.coverHttpHeaders.cookie,
      authorization: this.coverHttpHeaders.authorization,
      acceptLanguage: this.coverHttpHeaders.acceptLanguage,
      cacheControl: this.coverHttpHeaders.cacheControl,
      pragma: this.coverHttpHeaders.pragma,
      secFetchDest: this.coverHttpHeaders.secFetchDest,
      secFetchMode: this.coverHttpHeaders.secFetchMode,
      secFetchSite: this.coverHttpHeaders.secFetchSite,
      cachePartition: this.coverHttpHeaders.cachePartition,
      extraHeaders: this.cloneCoverExtraHeaders(this.coverHttpHeaders.extraHeaders)
    };
    return headers;
  }


  private async loadCoverWithHeaders(coverUrl: string): Promise<void> {
    if (!coverUrl || coverUrl.trim() === '') {
      logger.warn(TAG, '封面URL为空，跳过加载');
      return;
    }
    
    try {
      logger.info(TAG, `使用OnlineImageLoader加载封面: ${coverUrl}`);
      
      // 构建请求headers - 从图源配置中继承 imageHeaders/coverHeaders，缺省再使用站点来源
      let headers: OnlineRequestHeaders = this.buildGenericCoverHeaders(coverUrl);
      if (this.isPhotos18Source()) {
        headers = this.buildPhotos18CoverHeaders(coverUrl);
      }
      
      // 使用OnlineImageLoader加载
      const loader = OnlineImageLoader.getInstance();
      if (this.isPhotos18Source() && this.sourceId > 0) {
        loader.clearCookieCache(this.sourceId);
      }
      const pixelMap: image.PixelMap | null = await loader.load(coverUrl, { 
        headers,
        sourceId: this.sourceId > 0 ? this.sourceId : undefined,
        priority: 10,  // 高优先级
        partitionKey: this.isPhotos18Source() ? this.photos18CoverPartition : undefined
      });


      
      if (pixelMap) {
        this.coverPixelMap = pixelMap;
        logger.info(TAG, `封面PixelMap加载成功: ${coverUrl}`);
        
        // 获取图片尺寸用于显示
        try {
          const imageInfo: image.ImageInfo = await pixelMap.getImageInfo();
          const width: number = imageInfo.size.width;
          const height: number = imageInfo.size.height;
          if (width > 0 && height > 0) {
            const ratio = height / width;
            const newWidth = COVER_IMAGE_WIDTH;
            const newHeight = Math.min(Math.round(newWidth * ratio), COVER_IMAGE_HEIGHT * 1.5);
            this.coverDisplayWidth = newWidth;
            this.coverDisplayHeight = newHeight;
            logger.info(TAG, `封面尺寸: ${width}x${height}, 显示: ${newWidth}x${newHeight}`);
          }
        } catch (e) {
          logger.warn(TAG, `获取封面尺寸失败: ${String(e)}`);
        }
      } else {
        logger.warn(TAG, `封面PixelMap加载返回null: ${coverUrl}`);
      }
    } catch (err) {
      logger.error(TAG, `使用OnlineImageLoader加载封面失败: ${String(err)}`);
    }
  }

  /**
   * 触发章节预加载
   */
  private triggerChapterPreload(): void {
    if (!this.currentManga || !this.currentManga.chapters || this.currentManga.chapters.length === 0) {
      logger.debug(TAG, '无可用章节，跳过预加载');
      return;
    }
    
    if (!this.pageParams?.sourceId || !this.pageParams?.mangaId) {
      logger.debug(TAG, '缺少sourceId或mangaId，跳过预加载');
      return;
    }
    
    // 获取外部漫画ID
    let externalMangaId = this.pageParams.mangaId;
    if (this.currentManga.sourceInfo && this.currentManga.sourceInfo.sourceUrl && !this.currentManga.sourceInfo.sourceUrl.startsWith('id_')) {
      externalMangaId = this.currentManga.sourceInfo.sourceUrl;
    }
    
    // 确定要预加载的章节
    const chaptersToPreload: ChapterInfo[] = [];
    
    // 获取用户阅读进度
    const readingProgress = this.hasReadingProgress() ? this.determineResumeTarget() : null;
    let startIndex = 0;
    
    if (readingProgress && readingProgress.chapterId) {
      // 从阅读进度之后的章节开始预加载
      // 找到当前章节的索引
      const currentChapterIndex = this.currentManga.chapters.findIndex(ch => ch.id === readingProgress.chapterId);
      if (currentChapterIndex >= 0) {
        startIndex = currentChapterIndex + 1;
        logger.info(TAG, `从阅读进度后开始预加载: 章节${startIndex}`);
      }
    } else {
      // 从第一章开始预加载
      logger.info(TAG, '从第一章开始预加载');
    }
    
    // 选择前3个章节进行预加载
    const maxPreloadChapters = 3;
    for (let i = startIndex; i < Math.min(startIndex + maxPreloadChapters, this.currentManga.chapters.length); i++) {
      const chapter = this.currentManga.chapters[i];
      if (chapter.externalId) {
        const chapterInfo: ChapterInfo = {
          id: chapter.id,
          externalId: chapter.externalId,
          title: chapter.title
        };
        chaptersToPreload.push(chapterInfo);
      }
    }
    
    if (chaptersToPreload.length === 0) {
      logger.warn(TAG, '没有找到可预加载的章节（缺少externalId）');
      return;
    }
    
    logger.info(TAG, `准备预加载 ${chaptersToPreload.length} 个章节`);
    
    // 启动预加载（【关键】必须传递sourceName）
    const preloadManager = ChapterPreloadManager.getInstance();
    if (!this.sourceName) {
      logger.warn(TAG, `图源名称为空，跳过预加载: sourceId=${this.pageParams.sourceId}`);
      return;
    }
    preloadManager.startPreload(
      this.pageParams.mangaId,
      externalMangaId,
      this.pageParams.sourceId,
      this.sourceName,
      chaptersToPreload
    ).catch((error: Error) => {
      logger.error(TAG, `预加载失败: ${error.message}`);
    });
  }

  /**
   * 开始/继续阅读
   */
  private async startReading(): Promise<void> {
    if (!this.currentManga) return;

    // 通知预加载管理器：阅读器即将激活
    ChapterPreloadManager.getInstance().setReaderActive(true);

    logger.info(TAG, '开始/继续阅读入口');
    const nm: string = this.sourceName ? this.sourceName.toLowerCase() : '';
    if ((nm.indexOf('再漫画') >= 0 || nm.indexOf('zai') >= 0) && this.accessDenied) {
      this.getUIContext().showAlertDialog({
        title: '提示',
        message: '未登录账号或权限不足，无法查看此漫画',
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: { value: '确定', action: () => {} }
      });
      return;
    }
    const target: ResumeTarget | null = this.determineResumeTarget();
    const readerParams: MangaReaderPageParams = {
      fromPage: 'MangaDetailPage'
    } as MangaReaderPageParams;
    readerParams.readerTitle = this.currentManga?.title || '';
    
    // 修复：即使不是WebView源，如果有sourceId也应该传递，避免在线漫画被错误标记为Local
    if (this.pageParams?.sourceId) {
      readerParams.manga = this.currentManga;
      readerParams.sourceId = this.pageParams.sourceId;
      readerParams.sourcePkg = this.sourcePkg || this.pageParams.sourcePkg;
      readerParams.mangaId = this.pageParams.mangaId; // 传递外部ID用于API请求

      let sn1: string = '';

      const dm = DataManager.getInstance();
      const invalidNames = ['本地导入', 'LOCAL', 'UNKNOWN', 'WEBVIEW', 'WebView Source', ''];
      
      // [关键修复] 优先使用当前页面已确定的图源名称（this.sourceName）
      // 这是最可靠的来源，因为 MangaDetailPage 在初始化时已经正确设置了 sourceName
      // 数据库中的 sourceName 可能是错误的（之前的 bug 导致），所以不再优先使用
      if (this.sourceName && !invalidNames.includes(this.sourceName)) {
        sn1 = this.sourceName;
        logger.info(TAG, `✅ 使用当前页面的图源名称: "${sn1}"`);
      }
      
      // 降级方案1：从 comic_source 表通过 sourceId 获取（比数据库中的 sourceName 更可靠）
      if (!sn1 && this.pageParams.sourceId) {
        const srcRecord = await dm.getComicSourceById(this.pageParams.sourceId);
        if (srcRecord && srcRecord.name && srcRecord.name.length > 0) {
          sn1 = srcRecord.name;
          logger.info(TAG, `从comic_source获取图源名称: "${sn1}" (sourceId=${this.pageParams.sourceId})`);
        }
      }
      
      // 降级方案2：从 online_comic_info 表获取图源名称，并尝试通过 sourcePkg 恢复图源关联
      if (!sn1 && this.pageParams.mangaId) {
        const onlineInfo = await dm.getOnlineComicInfoById(this.pageParams.mangaId);
        if (onlineInfo) {
          // [修复] 优先通过 sourcePkg 查找图源（解决图源删除后重新导入的问题）
          if (onlineInfo.sourcePkg) {
            const newSourceId = await dm.findSourceIdByPkgOrName(onlineInfo.sourcePkg, onlineInfo.sourceName);
            if (newSourceId !== null) {
              // 更新 pageParams.sourceId 以便后续使用正确的图源ID
              this.pageParams.sourceId = newSourceId;
              const srcRecord = await dm.getComicSourceById(newSourceId);
              if (srcRecord && srcRecord.name) {
                sn1 = srcRecord.name;
                logger.info(TAG, `[修复] 通过sourcePkg="${onlineInfo.sourcePkg}"恢复图源: "${sn1}" (newSourceId=${newSourceId})`);
              }
            }
          }
          // 如果仍未找到，使用 online_comic_info 中的 sourceName
          if (!sn1 && onlineInfo.sourceName && !invalidNames.includes(onlineInfo.sourceName)) {
            sn1 = onlineInfo.sourceName;
            logger.debug(TAG, `从online_comic_info获取图源名称: "${sn1}"`);
          }
        }
      }
      
      // 降级方案3：从漫画对象的 sourceInfo 获取
      if (!sn1 && this.currentManga?.sourceInfo?.sourceName) {
        const mangaSourceName = this.currentManga.sourceInfo.sourceName;
        if (!invalidNames.includes(mangaSourceName)) {
          sn1 = mangaSourceName;
          logger.debug(TAG, `从manga.sourceInfo获取图源名称: "${sn1}"`);
        }
      }
      
      // 最终降级：使用占位符（不应该到达这里）
      if (!sn1) {
        sn1 = 'WebView图源';
        logger.warn(TAG, `⚠️ 无法获取有效图源名称，使用占位符: "${sn1}"，sourceId=${this.pageParams.sourceId}`);
      }
      
      readerParams.sourceName = sn1;
      let isDownloaded: boolean = false;
      if (target) {
        for (let i = 0; i < this.currentManga.chapters.length; i++) {
          const ch = this.currentManga.chapters[i];
          if (ch.id === target.chapterId) {
            isDownloaded = ch.isDownloaded || false;
            break;
          }
        }
      }
      readerParams.contentType = isDownloaded ? MangaReaderContentType.OnlineDownloaded : MangaReaderContentType.OnlineUndownloaded;
      logger.info(TAG, `在线漫画（继续阅读）: sourceId=${this.pageParams.sourceId}, mangaId=${this.pageParams.mangaId}, contentType=${readerParams.contentType}, isDownloaded=${isDownloaded}`);
    } else {
      // 传统图源，只传递mangaId
      readerParams.mangaId = this.currentManga.id;
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      logger.info(TAG, `本地漫画（继续阅读）: 无sourceId`);
    }

    if (target) {
      // [修复] 对于WebView图源，需要将内部章节ID转换为外部ID
      let chapterIdToPass = target.chapterId;
      if (this.pageParams?.sourceId && this.currentManga?.chapters) {
        const targetChapter = this.currentManga.chapters.find(ch => ch.id === target.chapterId);
        if (targetChapter?.externalId) {
          chapterIdToPass = targetChapter.externalId;
          logger.debug(TAG, `转换章节ID: 内部ID=${target.chapterId} -> 外部ID=${chapterIdToPass}`);
        }
      }
      readerParams.chapterId = chapterIdToPass;
      readerParams.pageIndex = target.pageIndex;
      logger.info(TAG, `恢复阅读目标: 章节 ${chapterIdToPass}, 页 ${String(target.pageIndex)}`);
    } else {
      logger.warn(TAG, '无法确定恢复目标，按默认进入阅读页面');
    }

    try {
      const ctStr: string = String(readerParams.contentType);
      const sidStr: string = readerParams.sourceId !== undefined ? String(readerParams.sourceId) : '未指定';
      const snameStr: string = readerParams.sourceName ? String(readerParams.sourceName) : '未指定';
      const midStr: string = readerParams.mangaId ? String(readerParams.mangaId) : '未指定';
      logger.info(TAG, `准备传递阅读器参数: mangaId=${midStr}, chapterId=${readerParams.chapterId || '未指定'}, pageIndex=${readerParams.pageIndex ?? 0}, contentType=${ctStr}, sourceId=${sidStr}, sourceName=${snameStr}`);
      if (readerParams.manga) {
        const mTitle: string = readerParams.manga.title || '未知标题';
        const mId: string = readerParams.manga.id || '未知ID';
        const mSrcName: string = readerParams.manga.sourceInfo && readerParams.manga.sourceInfo.sourceName ? String(readerParams.manga.sourceInfo.sourceName) : '未指定';
        logger.info(TAG, `传递漫画对象: title=${mTitle}, id=${mId}, sourceName=${mSrcName}`);
      }
      
      // [优化] 在动画期间后台预取页面列表，阅读器打开后可直接使用
      if (this.mangaEngine && readerParams.sourceId && readerParams.chapterId) {
        const prefetchSourceId = readerParams.sourceId;
        const prefetchChapterId = readerParams.chapterId;
        const prefetchMangaId = readerParams.mangaId || '';
        this.mangaEngine.getPageList(prefetchChapterId, prefetchMangaId).then((result) => {
          if (result.success && result.data && result.data.length > 0) {
            MangaSourceEngine.setPrefetchedPages(prefetchSourceId, prefetchChapterId, result.data);
            logger.info(TAG, `[预取] 页面列表预取成功: ${result.data.length} 页`);
          } else {
            logger.warn(TAG, `[预取] 页面列表预取失败或为空: ${result.error || 'empty'}`);
          }
        }).catch((e: Error) => {
          logger.warn(TAG, `[预取] 页面列表预取异常: ${e.message}`);
        });
      }

      // 触发翻开过渡动画（使用组件ID获取准确封面位置）
      const coverPath: string = this.currentManga.coverImagePath || '';
      const coverComponentId: string = `cover_manga_detail_${this.currentManga.id}`;
      readerParams.coverComponentId = coverComponentId;
      
      logger.info(TAG, `触发翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
      startBookOpenTransitionWithComponentId(
        coverPath,
        coverComponentId,
        this.currentManga.id,
        'manga',
        () => {
          logger.info(TAG, '翻开过渡动画完成');
          openMangaReaderInIsolatedAbility(this.getUIContext(), this.pathStack, readerParams, TAG, false);
          logger.info(TAG, `${this.hasReadingProgress() ? '继续' : '开始'}阅读漫画: ${this.currentManga?.title}`);
        },
        undefined,
        {
          title: this.currentManga?.title || '',
          author: this.currentManga?.metadata?.authors?.[0] || '',
          intro: this.currentManga?.description || ''
        }
      );
    } catch (error) {
      logger.error(TAG, `导航到阅读页面失败: ${String(error)}`);
    }
  }

  /**
   * 判断是否有阅读进度
   */
  private hasReadingProgress(): boolean {
    if (!this.currentManga) {
      return false;
    }

    // 检查章节进度列表中是否有任何已读记录
    for (let i: number = 0; i < this.chapterProgressList.length; i++) {
      const info: ChapterProgressInfo = this.chapterProgressList[i];
      if (info.currentPageIndex >= 0) {
        return true;
      }
    }

    return false;
  }

  /**
   * 计算漫画阅读进度百分比
   * 基于已阅读的页数占总页数的比例
   * @returns 阅读进度百分比 (0-100)
   */
  private calculateReadingPercentage(): number {
    if (!this.currentManga || this.chapterProgressList.length === 0) {
      return 0;
    }

    let totalPages = 0;
    let readPages = 0;

    // 遍历所有章节，计算总页数和已读页数
    for (const progress of this.chapterProgressList) {
      if (progress.totalPages > 0) {
        totalPages += progress.totalPages;
        // currentPageIndex >= 0 表示已开始阅读该章节
        // currentPageIndex + 1 表示已阅读的页数（因为索引从0开始）
        if (progress.currentPageIndex >= 0) {
          readPages += progress.currentPageIndex + 1;
        }
      }
    }

    if (totalPages === 0) {
      return 0;
    }

    // 计算百分比，保留整数
    const percentage = Math.floor((readPages / totalPages) * 100);
    return Math.min(percentage, 100); // 确保不超过100%
  }

  /**
   * 阅读指定章节
   */
  private async readChapter(chapter: MangaChapter): Promise<void> {
    if (!this.currentManga) return;

    logger.debug(TAG, `🔍 开始准备阅读章节: ${chapter.title} (ID: ${chapter.id})`);
    
    // [修复] 对于WebView图源，如果章节列表为空，先从网络获取
    if (this.pageParams?.sourceId && this.useWebView && 
        (!this.currentManga.chapters || this.currentManga.chapters.length === 0)) {
      logger.warn(TAG, `⚠️ WebView图源章节列表为空，尝试从网络获取`);
      try {
        const externalId = this.pageParams.mangaId || this.currentManga.id;
        const webViewChapters = await this.fetchChapterListFromNetwork(externalId);
        if (webViewChapters && webViewChapters.length > 0) {
          logger.info(TAG, `✅ 从网络获取到 ${webViewChapters.length} 个章节`);
          // 转换为MangaChapter格式并填充
          const mangaChapters: MangaChapter[] = webViewChapters.map((ch: WebViewChapterInfo, index: number) => {
            const chapterNum: number = this.extractChapterNumber(ch.title);
            const mangaChapter: MangaChapter = {
              id: ch.id || `chapter_${index}`,
              title: ch.title,
              chapterNumber: chapterNum > 0 ? chapterNum : (index + 1),
              pages: [],
              publishDate: (typeof ch.publishTime === 'number' ? ch.publishTime : Date.now()),
              language: 'zh-CN',
              scanlationGroup: '',
              isDownloaded: false,
              downloadProgress: 0,
              downloadStatus: DownloadStatus.PENDING,
              localPath: undefined,
              externalId: ch.id || `chapter_${index}`
            };
            return mangaChapter;
          });
          this.currentManga.chapters = mangaChapters;
          this.filteredChapters = mangaChapters;
          // 重新赋值以触发@State更新
          const updatedManga = this.currentManga;
          this.currentManga = null;
          this.currentManga = updatedManga;
          logger.info(TAG, `✅ 已填充 ${mangaChapters.length} 个章节到currentManga并触发更新`);
        } else {
          logger.error(TAG, `❌ 从网络获取章节失败或章节列表为空`);
          this.getUIContext().getPromptAction().showToast({ message: '获取章节列表失败' });
          return;
        }
      } catch (error) {
        logger.error(TAG, `❌ 获取章节列表异常: ${error}`);
        this.getUIContext().getPromptAction().showToast({ message: '获取章节列表失败' });
        return;
      }
    }
    
    // [修复] 直接从数据库读取最新的阅读进度，而不是依赖可能过时的 chapterProgressList
    // 问题：chapterProgressList 可能在 onPageShow 的异步刷新完成之前就被使用，导致使用旧数据
    let resumePageIndex: number = 0;
    try {
      const dm = DataManager.getInstance();
      const mangaId = this.currentManga.id;
      
      // 根据漫画类型选择正确的阅读历史表
      let latestHistory: ReadHistory | null = null;
      if (this.pageParams?.sourceId) {
        // 在线漫画：查询 online_read_history 表
        const onlineHistoryRecords = await dm.getOnlineReadHistoryByComic(mangaId);
        // 找到该章节的最新阅读记录
        for (const record of onlineHistoryRecords) {
          if (record.chapterId === chapter.id) {
            if (!latestHistory || record.readTime > latestHistory.readTime) {
              latestHistory = {
                id: record.id,
                userId: 'default_user',
                comicId: record.comicId,
                chapterId: record.chapterId,
                pageIndex: record.pageIndex,
                readTime: record.readTime,
                readDuration: 0
              };
            }
          }
        }
      } else {
        // 本地漫画：查询 read_history 表
        const historyList = await dm.getReadHistoryByComic(mangaId, 'default_user', 1000);
        // 找到该章节的最新阅读记录
        for (const record of historyList) {
          if (record.chapterId === chapter.id) {
            if (!latestHistory || record.readTime > latestHistory.readTime) {
              latestHistory = record;
            }
          }
        }
      }
      
      if (latestHistory && latestHistory.pageIndex >= 0) {
        resumePageIndex = latestHistory.pageIndex;
        logger.info(TAG, `📖 [修复] 从数据库直接读取章节进度: chapterId=${chapter.id}, pageIndex=${resumePageIndex}, readTime=${latestHistory.readTime}`);
      } else {
        logger.debug(TAG, `📖 未找到章节 ${chapter.id} 的阅读记录，从第1页开始`);
      }
    } catch (err) {
      logger.warn(TAG, `📖 读取章节进度失败: ${String(err)}，从第1页开始`);
    }

    logger.debug(TAG, `📄 最终恢复页面索引: ${resumePageIndex}`);

    // [重构] 根据章节类型决定传递哪个ID
    const mangaIdForReader = this.pageParams?.mangaId || this.currentManga.id;
    
    // 章节ID传递规则：
    // 1. 在线未下载：传递externalId（用于网络请求）
    // 2. 在线已下载：传递内部ID（用于查询本地文件）
    // 3. 本地漫画：传递内部ID
    let chapterIdForReader: string;
    if (this.pageParams?.sourceId && !chapter.isDownloaded && chapter.externalId) {
      // 在线未下载：使用外部ID
      chapterIdForReader = chapter.externalId;
      logger.debug(TAG, `📋 在线未下载章节，使用外部ID: ${chapterIdForReader}`);
    } else {
      // 在线已下载或本地漫画：使用内部ID
      chapterIdForReader = chapter.id;
      logger.debug(TAG, `📋 ${chapter.isDownloaded ? '在线已下载' : '本地'}章节，使用内部ID: ${chapterIdForReader}`);
    }
    
    const readerParams: MangaReaderPageParams = {
      mangaId: mangaIdForReader,
      contentType: MangaReaderContentType.Local,
      chapterId: chapterIdForReader,
      pageIndex: resumePageIndex,
      fromPage: 'MangaDetailPage',
      chapterTitle: chapter.title  // 传递章节标题用于数据库查询
    } as MangaReaderPageParams;
    readerParams.readerTitle = this.currentManga?.title || '';

    // 设置阅读内容类型并补充必要参数
    // 修复：即使不是WebView源，如果有sourceId也应该传递，避免在线漫画被错误标记为Local
    if (this.pageParams?.sourceId) {
      // [修复] 确保传递的manga对象包含完整的章节列表
      if (this.currentManga && (!this.currentManga.chapters || this.currentManga.chapters.length === 0)) {
        logger.warn(TAG, `⚠️ currentManga.chapters仍为空（不应该发生）`);
      }
      logger.debug(TAG, `📚 传递manga对象: chapters数量=${this.currentManga?.chapters?.length || 0}`);
      readerParams.manga = this.currentManga;
      readerParams.sourceId = this.pageParams.sourceId;
      readerParams.sourcePkg = this.sourcePkg || this.pageParams.sourcePkg;
      let sn2: string = '';

      const dm = DataManager.getInstance();
      const invalidNames = ['本地导入', 'LOCAL', 'UNKNOWN', 'WEBVIEW', 'WebView Source', ''];
      
      // [关键修复] 优先使用当前页面已确定的图源名称（this.sourceName）
      // 这是最可靠的来源，因为 MangaDetailPage 在初始化时已经正确设置了 sourceName
      if (this.sourceName && !invalidNames.includes(this.sourceName)) {
        sn2 = this.sourceName;
        logger.info(TAG, `✅ 使用当前页面的图源名称: "${sn2}"`);
      }
      
      // 降级方案1：从online_comic_info表获取图源名称
      if (!sn2 && this.pageParams.mangaId) {
        const onlineInfo = await dm.getOnlineComicByExternalId(this.pageParams.mangaId);
        if (onlineInfo) {
          // [修复] 优先通过 sourcePkg 查找图源（解决图源删除后重新导入的问题）
          if (onlineInfo.sourcePkg) {
            const newSourceId = await dm.findSourceIdByPkgOrName(onlineInfo.sourcePkg, onlineInfo.sourceName);
            if (newSourceId !== null) {
              this.pageParams.sourceId = newSourceId;
              const srcRecord = await dm.getComicSourceById(newSourceId);
              if (srcRecord && srcRecord.name) {
                sn2 = srcRecord.name;
                logger.info(TAG, `[修复] 通过sourcePkg="${onlineInfo.sourcePkg}"恢复图源: "${sn2}" (newSourceId=${newSourceId})`);
              }
            }
          }
          // 如果仍未找到，使用 online_comic_info 中的 sourceName
          if (!sn2 && onlineInfo.sourceName && !invalidNames.includes(onlineInfo.sourceName)) {
            sn2 = onlineInfo.sourceName;
            logger.debug(TAG, `从online_comic_info获取有效图源名称: "${sn2}"`);
          }
        }
      }
      
      // 降级方案2：从 comic_source 表通过 sourceId 获取
      if (!sn2 && this.pageParams.sourceId) {
        logger.info(TAG, `尝试通过当前sourceId=${this.pageParams.sourceId}查找图源名称`);
        const srcRecord = await dm.getComicSourceById(this.pageParams.sourceId);
        if (srcRecord && srcRecord.name && srcRecord.name.length > 0) {
          sn2 = srcRecord.name;
          logger.info(TAG, `✅ 找到图源名称: "${sn2}" (ID=${this.pageParams.sourceId})`);
        } else {
          logger.warn(TAG, `⚠️ 未找到sourceId=${this.pageParams.sourceId}的图源记录`);
        }
      }
      
      // 降级方案3：从漫画对象的 sourceInfo 获取
      if (!sn2 && this.currentManga?.sourceInfo?.sourceName) {
        const mangaSourceName = this.currentManga.sourceInfo.sourceName;
        if (!invalidNames.includes(mangaSourceName)) {
          sn2 = mangaSourceName;
          logger.debug(TAG, `从manga.sourceInfo获取图源名称: "${sn2}"`);
        }
      }
      
      // 最终降级：使用占位符（不应该到达这里）
      if (!sn2) {
        sn2 = 'WebView图源';
        logger.warn(TAG, `⚠️ 无法获取有效图源名称，使用占位符: "${sn2}"，sourceId=${this.pageParams.sourceId}`);
      }
      
      readerParams.sourceName = sn2;
      // 根据章节的下载状态设置contentType
      readerParams.contentType = chapter.isDownloaded ? MangaReaderContentType.OnlineDownloaded : MangaReaderContentType.OnlineUndownloaded;
      
      // [修复] 如果章节没有页面信息（pages为空），设置skipDatabaseLookup标志
      const hasPageInfo = chapter.pages && chapter.pages.length > 0;
      if (!hasPageInfo && !chapter.isDownloaded) {
        readerParams.skipDatabaseLookup = true;
        logger.info(TAG, `⚠️ 章节 "${chapter.title}" 无页面信息，设置skipDatabaseLookup=true，阅读器将直接使用externalId请求`);
      }
      
      logger.info(TAG, `在线漫画章节: sourceId=${readerParams.sourceId}, sourceName=${sn2}, isDownloaded=${chapter.isDownloaded}, skipDatabaseLookup=${readerParams.skipDatabaseLookup || false}`);
    } else {
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      logger.info(TAG, `本地漫画章节: 无sourceId`);
    }

    logger.debug(TAG, `📦 阅读器参数: mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}, pageIndex=${readerParams.pageIndex}`);

    try {
      const ctStr2: string = String(readerParams.contentType);
      const sidStr2: string = readerParams.sourceId !== undefined ? String(readerParams.sourceId) : '未指定';
      const snameStr2: string = readerParams.sourceName ? String(readerParams.sourceName) : '未指定';
      const midStr2: string = readerParams.mangaId ? String(readerParams.mangaId) : '未指定';
      logger.info(TAG, `准备传递阅读器参数(章节): mangaId=${midStr2}, chapterId=${readerParams.chapterId || '未指定'}, pageIndex=${readerParams.pageIndex ?? 0}, contentType=${ctStr2}, sourceId=${sidStr2}, sourceName=${snameStr2}`);
      if (readerParams.manga) {
        const mTitle2: string = readerParams.manga.title || '未知标题';
        const mId2: string = readerParams.manga.id || '未知ID';
        const mSrcName2: string = readerParams.manga.sourceInfo && readerParams.manga.sourceInfo.sourceName ? String(readerParams.manga.sourceInfo.sourceName) : '未指定';
        logger.info(TAG, `传递漫画对象(章节): title=${mTitle2}, id=${mId2}, sourceName=${mSrcName2}`);
      }
      
      // 触发翻开过渡动画（使用组件ID获取准确封面位置）
      const coverPath2: string = this.currentManga?.coverImagePath || '';
      const coverComponentId2: string = `cover_manga_detail_${this.currentManga?.id || ''}`;
      readerParams.coverComponentId = coverComponentId2;
      
      logger.info(TAG, `触发翻开过渡动画(章节): coverPath=${coverPath2}, componentId=${coverComponentId2}`);
      startBookOpenTransitionWithComponentId(
        coverPath2,
        coverComponentId2,
        this.currentManga?.id || '',
        'manga',
        () => {
          logger.info(TAG, '翻开过渡动画完成(章节)');
          openMangaReaderInIsolatedAbility(this.getUIContext(), this.pathStack, readerParams, TAG, false);
          logger.info(TAG, `开始阅读章节: ${chapter.title}`);
        },
        undefined,
        {
          title: this.currentManga?.title || '',
          author: this.currentManga?.metadata?.authors?.[0] || '',
          intro: this.currentManga?.description || ''
        }
      );
    } catch (error) {
      logger.error(TAG, `导航到章节阅读失败: ${String(error)}`);
    }
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `返回失败: ${String(error)}`);
    }
  }

  /**
   * 更新设备方向状态
   */
  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    this.currentBreakpoint = deviceInfo.breakpoint;
    logger.info(TAG, `设备方向初始化: ${this.isLandscape ? '横屏' : '竖屏'}, 断点: ${this.currentBreakpoint}`);
  }

  /**
   * 根据断点计算网格列数
   * sm: 2列, md: 3列, lg: 4列
   */
  private getGridColumns(): number {
    switch (this.currentBreakpoint) {
      case Breakpoint.SM:
        return 2;
      case Breakpoint.MD:
        return 3;
      case Breakpoint.LG:
        return 4;
      default:
        return 2;
    }
  }

  /**
   * 生成网格列模板字符串
   * 例如：2列返回 "1fr 1fr"，3列返回 "1fr 1fr 1fr"
   */
  private getGridColumnsTemplate(): string {
    const columns = this.getGridColumns();
    const template: string[] = [];
    for (let i = 0; i < columns; i++) {
      template.push('1fr');
    }
    return template.join(' ');
  }

  /**
   * 构建封面和基本信息区域
   */
  @Builder
  buildCoverSection() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 背景渐变区域
      Column()
        .width('100%')
        .height(this.coverDisplayHeight)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_start', this.themeState.currentTheme), 0.0],
            [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_mid', this.themeState.currentTheme), 0.4],
            [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_end', this.themeState.currentTheme), 1.0]
          ]
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 封面图片和信息
      Row({ space: 16 }) {
        // 封面图片区域 - 占40%宽度
        Stack() {
          if (this.coverImageLoaded) {
            // 封面图片容器，添加阴影效果
            Column() {
              // 使用方法返回的渲染源，避免在 UI 语法块内声明变量
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(this.getCoverImageSourceForUI())
                  .width(this.coverDisplayWidth)
                  .height(this.coverDisplayHeight)
                .objectFit(ImageFit.Contain) // 仅缩放，完整显示，不裁剪
                .backgroundColor(Color.Transparent)
                .id(`cover_manga_detail_${this.currentManga?.id || ''}`)  // 用于翻开动画定位
                .onError(() => {
                  // 图片加载失败时的回调 - 尝试使用OnlineImageLoader加载（支持headers）
                  const coverUrl = this.currentManga?.coverImagePath as string;
                  logger.warn(TAG, `封面图片加载失败，尝试使用OnlineImageLoader: raw='${coverUrl}', source=${String(this.currentManga?.coverSourceType)}`);
                  
                  // 如果是网络图片且尚未使用PixelMap加载，尝试用OnlineImageLoader加载
                  if (coverUrl && coverUrl.startsWith('http') && !this.coverPixelMap) {
                    this.loadCoverWithHeaders(coverUrl).catch((err: Error) => {
                      logger.warn(TAG, `OnlineImageLoader加载封面也失败: ${err.message}`);
                    });
                  } else {
                    // 非网络图片或已尝试过，回退到占位图
                    if (this.currentManga) {
                      this.currentManga.coverImagePath = '';
                    }
                    this.refreshCoverSize().catch((err: Error) => {
                      logger.warn(TAG, `封面尺寸回退失败: ${err.message}`);
                    });
                  }
                })
                .alt($r('app.media.mangabook'))
                
                if (LabelUtils.isTranslatedContent(this.currentManga?.title)) {
                  Text('汉化')
                    .fontSize(10)
                    .fontColor(Color.White)
                    .backgroundColor('#E6F44336')
                    .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                    .borderRadius({ bottomLeft: 6, topRight: 8 })
                }
              }
              .width(this.coverDisplayWidth)
              .height(this.coverDisplayHeight)// 设置加载失败时的替代图片
            }
            .backgroundColor(Color.Transparent)
            .width(this.coverDisplayWidth)
            .height(this.coverDisplayHeight)
          } else {
            // 加载中的占位符
            Column() {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
            .width(this.coverDisplayWidth)
            .height(this.coverDisplayHeight)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            // .justifyContent(FlexAlign.Center)
          }
        }
        .animation({
          duration: 600,
          curve: curves.springMotion(0.6, 0.8)
        })
        // 修复溢出：避免百分比宽度与Row空间叠加导致超出
        // 使用内容宽度（封面显示宽度）保证在不同设备上不超过行总宽度
        .width(this.coverDisplayWidth)

        // 漫画信息区域 - 占60%宽度
        Column({ space: 8 }) {
          // 标题 - 长按搜索
          Text(this.currentManga?.title || '加载中...')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start)
            .gesture(
              LongPressGesture({ repeat: false, duration: 500 })
                .onAction(() => {
                  if (this.currentManga?.title) {
                    this.navigateToGlobalSearch(this.currentManga.title);
                  }
                })
            )

          // 作者信息 - 长按搜索
          if (this.currentManga?.metadata.authors) {
            Text(`作者: ${this.currentManga.metadata.authors}`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .opacity(0.8)
              .width('100%')
              .textAlign(TextAlign.Start)
              .gesture(
                LongPressGesture({ repeat: false, duration: 500 })
                  .onAction(() => {
                    if (this.currentManga?.metadata.authors && this.currentManga.metadata.authors.length > 0) {
                      // 搜索第一个作者
                      const firstAuthor = Array.isArray(this.currentManga.metadata.authors) 
                        ? this.currentManga.metadata.authors[0] 
                        : String(this.currentManga.metadata.authors);
                      this.navigateToGlobalSearch(firstAuthor);
                    }
                  })
              )
          }

          // 图源信息
          if (this.sourceName) {
            Text(`图源: ${this.sourceName}`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .opacity(0.8)
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          // 状态标签
          Row({ space: 8 }) {
            Text(this.getStatusText())
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor(this.getStatusColor())
              .borderRadius(4)

            if (this.currentManga?.metadata.publicationYear) {
              Text(`${this.currentManga.metadata.publicationYear}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .opacity(0.6)
                .borderRadius(4)
            }
          }
          .width('100%')

          // 阅读进度 - 使用动态计算的百分比
          if (this.hasReadingProgress()) {
            Text(`阅读进度: ${this.calculateReadingPercentage()}%`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .opacity(0.8)
              .width('100%')
              .textAlign(TextAlign.Start)
          }

          Blank()
          
          // NSFW开关（紧凑布局）
          Row({ space: 4 }) {
            Text('NSFW')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Toggle({ type: ToggleType.Switch, isOn: this.mangaIsNSFW })
              .width(36)
              .height(20)
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .onChange(async (isOn: boolean) => {
                await this.updateMangaNSFW(isOn);
              })
          }
          .padding({ left: 8, right: 8 })

          // 操作按钮
          Row({ space: 8 }) {
            // 使用ArkUI官方Button替换自定义AnimatedButton，启用stateEffect点击动效
            Button({ stateEffect: true }) {
              Text(this.hasReadingProgress() ? '继续阅读' : '开始阅读')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .key('start_continue_read_button')
            .height(40)
            .layoutWeight(3) // 占3份
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(6)
            .enabled(true)
            .onClick(() => {
              logger.info(TAG, '点击开始/继续阅读按钮');
              this.startReading();
            })

            Button() {
              Image(this.currentManga?.isFavorite ? $r('app.media.ic_favorite_filled') : $r('app.media.ic_favorite_outline'))
                .width(20)
                .height(20)
                .fillColor(this.currentManga?.isFavorite ?
                  ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .layoutWeight(1) // 占1份
            .height(40)
            .backgroundColor(Color.Transparent)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
              radius: 6
            })
            .onClick(() => {
              this.toggleFavorite().catch((error: Error) => {
                logger.error(TAG, `收藏切换失败: ${error.message}`);
              });
            })

            // 设置按钮：仅对已添加到书库的漫画显示
            if (this.currentManga?.isFavorite) {
              Button() {
                SymbolGlyph($r('sys.symbol.gearshape'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              }
              .layoutWeight(1) // 占1份
              .height(40)
              .backgroundColor(Color.Transparent)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
                radius: 6
              })
              .onClick(() => {
                this.navigateToMangaSettings();
              })
            }


          }
          .width('100%')

          Blank(1)
        }
        .alignItems(HorizontalAlign.Start)
        // 修复溢出：改为权重填充，避免与左侧固定宽度及space叠加造成超出
        .layoutWeight(1)
        .height(this.coverDisplayHeight)
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Bottom)

      Column() {
        Blank(10)
      }
      .width('100%')
    }
  }

  /**
   * 构建描述区域
   */
  @Builder
  buildDescriptionSection() {
    Column({ space: 12 }) {
      Text('简介')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text(this.currentManga?.description || '')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .lineHeight(20)
        .maxLines(this.expandDescription ? 1000 : 3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick(() => {
          this.expandDescription = !this.expandDescription;
        })

      if (this.currentManga?.metadata.genres && 
          Array.isArray(this.currentManga.metadata.genres) && 
          this.currentManga.metadata.genres.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(this.currentManga.metadata.genres, (genre: string) => {
            Text(genre)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
              .borderRadius(4)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
              })
              .onClick(() => {
                // 点击标签跳转到全局搜索
                this.navigateToGlobalSearch(genre);
              })
          })
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(12)
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 2 })
    // 修复溢出：移除左右外边距以避免与宽度100%叠加导致超出
    .margin({ top: 16, bottom: 16 })
  }

  /**
   * 下载选项弹出气泡
   */
  @Builder
  buildDownloadOptionsPopup() {
    Column() {
      Text('选择下载方式')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 12 })
      
      Button('下载所有')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.downloadAllChapters();
          this.showDownloadOptions = false;
        })
      
      Button('下载未读')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.downloadUnreadChapters();
          this.showDownloadOptions = false;
        })
    }
    .padding(16)
  }

  /**
   * 删除选项弹出气泡
   */
  @Builder
  buildDeleteOptionsPopup() {
    Column() {
      Text('选择删除方式')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 12 })
      
      Button('删除已下载')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.deleteAllDownloadedChapters();
          this.showDeleteOptions = false;
        })
      
      Button('删除选中')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.deleteSelectedChapters();
          this.showDeleteOptions = false;
        })
    }
    .padding(16)
  }

  /**
   * 排序选项弹出气泡
   */
  @Builder
  buildSortOptionsPopup() {
    Column() {
      Text('排序方式')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 12 })
      
      Button('按章节号正序')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.chapterSortKey = ChapterSortKey.CHAPTER_NUMBER;
          this.chapterSortOrder = ChapterSortOrder.ASCENDING;
          this.applyChapterFilters();
          this.showSortOptions = false;
        })
      
      Button('按章节号倒序')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.chapterSortKey = ChapterSortKey.CHAPTER_NUMBER;
          this.chapterSortOrder = ChapterSortOrder.DESCENDING;
          this.applyChapterFilters();
          this.showSortOptions = false;
        })

      Button('按发布时间正序')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.chapterSortKey = ChapterSortKey.PUBLISH_TIME;
          this.chapterSortOrder = ChapterSortOrder.ASCENDING;
          this.applyChapterFilters();
          this.showSortOptions = false;
        })

      Button('按发布时间倒序')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.chapterSortKey = ChapterSortKey.PUBLISH_TIME;
          this.chapterSortOrder = ChapterSortOrder.DESCENDING;
          this.applyChapterFilters();
          this.showSortOptions = false;
        })
    }
    .padding(16)
  }

  /**
   * 筛选选项弹出气泡
   */
  @Builder
  buildFilterOptionsPopup() {
    Column() {
      Text('筛选章节')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 12 })
      
      Button('所有章节')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.chapterFilter = ChapterFilterType.ALL;
          this.applyChapterFilters();
          this.showFilterOptions = false;
        })
      
      Button('未读章节')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.chapterFilter = ChapterFilterType.UNREAD;
          this.applyChapterFilters();
          this.showFilterOptions = false;
        })
      
      Button('已下载')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.chapterFilter = ChapterFilterType.DOWNLOADED;
          this.applyChapterFilters();
          this.showFilterOptions = false;
        })
      
      Button('已添加书签')
        .width('100%')
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          this.chapterFilter = ChapterFilterType.BOOKMARKED;
          this.applyChapterFilters();
          this.showFilterOptions = false;
        })
    }
    .padding(16)
  }

  /**
   * 构建章节列表头部
   */
  @Builder
  buildChapterListHeader() {
    Row() {
      // 章节标题
      Text(this.isSelectionMode ? `已选 (${this.selectedChapters.size})` : `章节 (${this.filteredChapters.length})`)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .layoutWeight(1)

      // 排序和筛选按钮
      Row({ space: 8 }) {
        // 多选模式按钮
        if (!this.isSelectionMode) {
          Button() {
            Image($r('app.media.ic_checkbox'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.isSelectionMode = true;
            logger.info(TAG, '进入多选模式');
          })
        } else {
          // 根据是否为本地漫画显示不同按钮
          if (!this.isLocalManga) {
            // 下载按钮（在线漫画）
            Button('下载')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(4)
              .enabled(this.selectedChapters.size > 0)
              .onClick(() => {
                this.showDownloadOptions = true;
              })
              .bindPopup(this.showDownloadOptions, {
                builder: this.buildDownloadOptionsPopup(),
                placement: Placement.Bottom,
                width: '300vp',
                onStateChange: (e) => {
                  if (!e.isVisible) {
                    this.showDownloadOptions = false;
                  }
                }
              })
          }
          
          // 删除按钮
          Button('删除')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(4)
            .enabled(this.selectedChapters.size > 0)
            .onClick(() => {
              this.showDeleteOptions = true;
            })
            .bindPopup(this.showDeleteOptions, {
              builder: this.buildDeleteOptionsPopup(),
              placement: Placement.Bottom,
              width: '300vp',
              onStateChange: (e) => {
                if (!e.isVisible) {
                  this.showDeleteOptions = false;
                }
              }
            })
          
          // 取消按钮
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(Color.Transparent)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.isSelectionMode = false;
              this.selectedChapters.clear();
              logger.info(TAG, '退出多选模式');
            })
        }
        
        if (!this.isSelectionMode) {
          // 显示模式切换按钮（仅在横屏模式下显示）
          if (this.isLandscape) {
            Button() {
              Image(this.chapterDisplayMode === ChapterDisplayMode.LIST ? 
                $r('app.media.ic_view_grid_selected') : $r('app.media.ic_view_list_selected'))
                .width(20)
                .height(20)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.chapterDisplayMode = this.chapterDisplayMode === ChapterDisplayMode.LIST ? 
                ChapterDisplayMode.GRID : ChapterDisplayMode.LIST;
              logger.info(TAG, `切换章节显示模式: ${this.chapterDisplayMode}`);
            })
          }
          
          // 排序按钮
          Button() {
            Image($r('app.media.ic_sort'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showSortOptions = true;
          })
          .bindPopup(this.showSortOptions, {
            builder: this.buildSortOptionsPopup(),
            placement: Placement.Bottom,
            width: '200vp',
            onStateChange: (e) => {
              if (!e.isVisible) {
                this.showSortOptions = false;
              }
            }
          })

          // 筛选按钮
          Button() {
            Image($r('app.media.ic_filter'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showFilterOptions = true;
          })
          .bindPopup(this.showFilterOptions, {
            builder: this.buildFilterOptionsPopup(),
            placement: Placement.Bottom,
            width: '200vp',
            onStateChange: (e) => {
              if (!e.isVisible) {
                this.showFilterOptions = false;
              }
            }
          })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  /**
   * 构建网格模式章节项（紧凑版）
   */
  @Builder
  buildChapterGridItem(chapter: MangaChapter, index: number) {
    Column({ space: 6 }) {
      // 多选模式复选框
      if (this.isSelectionMode) {
        Checkbox({ name: `chapter_${chapter.id}`, group: 'chapterSelection' })
          .select(this.selectedChapters.has(chapter.id))
          .onChange((value: boolean) => {
            if (value) {
              this.selectedChapters.add(chapter.id);
            } else {
              this.selectedChapters.delete(chapter.id);
            }
            logger.debug(TAG, `章节选择状态变更: ${chapter.title}, 已选: ${value}`);
          })
      }
      
      // 章节标题
      Text(this.getDisplayChapterTitle(chapter, index))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getChapterTitleColor(chapter))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      // 阅读进度
      Text(this.getChapterProgressText(chapter))
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      // 状态标签（紧凑显示）
      Row({ space: 4 }) {
        if (chapter.id === this.currentManga?.readingProgress.currentChapterId) {
          Circle({ width: 6, height: 6 })
            .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        if (chapter.isDownloaded) {
          Image($r('app.media.ic_download_done'))
            .width(12)
            .height(12)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        }
        if (this.hasBookmarkInChapter(chapter)) {
          Image($r('app.media.ic_bookmark'))
            .width(10)
            .height(10)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.Transparent)
    .border({ width: 1, color: colorMap['app.color.settings_panel_border'] })
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => this.readChapter(chapter))
  }

  /**
   * 构建章节列表项
   */
  @Builder
  buildChapterItem(chapter: MangaChapter, index: number) {
    Row({ space: 12 }) {
      // 多选模式复选框
      if (this.isSelectionMode) {
        Checkbox({ name: `chapter_${chapter.id}`, group: 'chapterSelection' })
          .select(this.selectedChapters.has(chapter.id))
          .onChange((value: boolean) => {
            if (value) {
              this.selectedChapters.add(chapter.id);
            } else {
              this.selectedChapters.delete(chapter.id);
            }
            logger.debug(TAG, `章节选择状态变更: ${chapter.title}, 已选: ${value}`);
          })
      }
      
      Column({ space: 6 }) {
        //  
        Text(this.getDisplayChapterTitle(chapter, index))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getChapterTitleColor(chapter))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 阅读进度（总页数/当前页）
        Text(this.getChapterProgressText(chapter))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

        // 发布日期和扫描组
        Row({ space: 12 }) {
          if (chapter.publishDate !== undefined) {
            Text(this.formatDetailedDate(this.getTimestampFromPublishDate(chapter.publishDate as number | Date)))
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }

          if (chapter.scanlationGroup) {
            Text(`• ${chapter.scanlationGroup}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }

        // 状态标签
        Row({ space: 8 }) {
          // readingProgress.currentChapterId存储的是内部ID（chapter.id）
          if (chapter.id === this.currentManga?.readingProgress.currentChapterId) {
            Text('正在阅读')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          } else if (this.isChapterRead(chapter)) {
            Text('已读')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }

          if (chapter.isDownloaded) {
            Text('已下载')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          } else if (chapter.downloadProgress > 0 && chapter.downloadProgress < 100) {
            Text(`下载中 ${chapter.downloadProgress}%`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 4 }) {
        if (chapter.id === this.currentManga?.readingProgress.currentChapterId) {
          Circle({ width: 8, height: 8 })
            .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }

        if (chapter.isDownloaded) {
          Image($r('app.media.ic_download_done'))
            .width(16)
            .height(16)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        }

        if (this.hasBookmarkInChapter(chapter)) {
          Image($r('app.media.ic_bookmark'))
            .width(14)
            .height(14)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Color.Transparent)
    .border({ width: 1, color: colorMap['app.color.settings_panel_border'] })
    .borderRadius(8)
    .onClick(() => this.readChapter(chapter))
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          logger.info(TAG, `长按章节: ${chapter.title}`);
        })
    )
  }

  private getChapterTitleColor(chapter: MangaChapter): ResourceColor {
    if (chapter.id === this.currentManga?.readingProgress.currentChapterId) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
    } else if (this.isChapterRead(chapter)) {
      return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    } else {
      // 修复默认颜色：使用文本主色，避免与浅色背景融合
      return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
    }
  }

  private getChapterBackgroundColor(chapter: MangaChapter): ResourceColor {
    if (chapter.id === this.currentManga?.readingProgress.currentChapterId) {
      return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
    } else {
      // 修复：使用有效的主题键 'background'，避免渲染项构建失败
      return ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme);
    }
  }

  /**
   * 章节标题显示：当标题为空或仅为空白时，使用“第N章”作为回退
   */
  private getDisplayChapterTitle(chapter: MangaChapter, index: number): string {
    const rawTitle: string | undefined = chapter.title as string | undefined;
    if (rawTitle && rawTitle.trim().length > 0) {
      return rawTitle.trim();
    }
    const n: number = (typeof chapter.chapterNumber === 'number' && chapter.chapterNumber > 0)
      ? chapter.chapterNumber
      : (index + 1);
    return `第${n}章`;
  }

  private isChapterRead(chapter: MangaChapter): boolean {
    const mg: Manga | null = this.currentManga;
    if (!mg || !mg.readingProgress) return false;

    if (chapter.id === mg.readingProgress.currentChapterId) {
      const totalPages: number = chapter.pages.length;
      const currentPage: number = mg.readingProgress.currentPageIndex;
      return currentPage >= totalPages - 1;
    }

    const currentChapter: MangaChapter | undefined = mg.chapters.find((c: MangaChapter) => c.id === mg.readingProgress.currentChapterId);
    if (currentChapter) {
      return chapter.chapterNumber < currentChapter.chapterNumber;
    }
    return false;
  }

  private hasBookmarkInChapter(chapter: MangaChapter): boolean {
    const mg: Manga | null = this.currentManga;
    return !!mg && mg.bookmarks.some((bookmark: MangaBookmark) => bookmark.chapterId === chapter.id);
  }

  private formatDate(timestamp: number): string {
    return TimeUtils.getRelativeTime(timestamp);
  }
  
  /**
   * 格式化详细日期（年月日时分）
   */
  private formatDetailedDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    
    return `${year}-${month}-${day} ${hours}:${minutes}`;
  }
  
  private getTimestampFromPublishDate(date: number | Date): number {
    if (date instanceof Date) {
      return date.getTime();
    }
    return date as number;
  }

  private getStatusText(): string {
    if (this.currentManga?.status) {
      return StatusConverter.mangaStatusToDisplayText(this.currentManga.status);
    }
    return '未知';
  }

  private getStatusColor(): ResourceColor {
    switch (this.currentManga?.status) {
      case MangaStatus.ONGOING:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme);
      case MangaStatus.COMPLETED:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      case MangaStatus.HIATUS:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme);
      case MangaStatus.CANCELLED:
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
  }

  /**
   * 构建章节筛选选项弹窗
   */
  @Builder
  buildChapterFilterDialog() {
    Column({ space: 8 }) {
      // 标题
      Row() {
        Text('筛选章节')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Button('✕')
          .fontSize(20)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .backgroundColor(Color.Transparent)
          .width(32)
          .height(32)
          .onClick(() => {
            this.showChapterOptions = false;
          })
      }
      .width('100%')
      .padding({ bottom: 12 })
      
      // 筛选选项
      Column({ space: 12 }) {
        this.buildFilterOption('全部章节', ChapterFilterType.ALL)
        this.buildFilterOption('未读章节', ChapterFilterType.UNREAD)
        this.buildFilterOption('已下载', ChapterFilterType.DOWNLOADED)
        this.buildFilterOption('已添加书签', ChapterFilterType.BOOKMARKED)
      }
      .width('100%')
    }
    .width('90%')
    .padding(20)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(12)
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
  }

  /**
   * 构建章节筛选静态菜单（位于按钮下方）
   */
  @Builder
  buildChapterFilterStaticMenu() {
    Column({ space: 12 }) {
      this.buildFilterOption('全部章节', ChapterFilterType.ALL)
      this.buildFilterOption('未读章节', ChapterFilterType.UNREAD)
      this.buildFilterOption('已下载', ChapterFilterType.DOWNLOADED)
      this.buildFilterOption('已添加书签', ChapterFilterType.BOOKMARKED)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(12)
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 2 })
  }

  @Builder
  buildFilterOption(label: string, filterType: ChapterFilterType) {
    Row() {
      Text(label)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
      
      if (this.chapterFilter === filterType) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.chapterFilter === filterType 
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.chapterFilter = filterType;
      this.updateFilteredChapters();
      this.showChapterOptions = false;
      logger.info(TAG, `章节筛选已更改为: ${filterType}`);
    })
  }

  /**
   * 构建横屏模式布局
   * 左侧40%显示漫画信息和简介，右侧60%显示章节列表
   */
  @Builder
  buildLandscapeLayout() {
    Row({ space: 0 }) {
      // 左侧40%：漫画信息和简介（可滚动）
      Scroll() {
        Column({ space: 16 }) {
          // 封面和基本信息（简化版）
          Column({ space: 12 }) {
          // 封面图片
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(this.getCoverImageSourceForUI())
              .width(120)
              .height(180)
            .objectFit(ImageFit.Contain)
            .borderRadius(8)
            .onError(() => {
              logger.warn(TAG, `封面图片加载失败`);
            })
            .alt($r('app.media.mangabook'))
            
            if (LabelUtils.isTranslatedContent(this.currentManga?.title)) {
              Text('汉化')
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#E6F44336')
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius({ bottomLeft: 6, topRight: 8 })
            }
          }
          .width(120)
          .height(180)

          // 标题
          Text(this.currentManga?.title || '加载中...')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Center)

          // 作者信息
          if (this.currentManga?.metadata.authors) {
            Text(`作者: ${this.currentManga.metadata.authors}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
              .textAlign(TextAlign.Center)
          }

          // 状态和年份
          Row({ space: 8 }) {
            Text(this.getStatusText())
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .backgroundColor(this.getStatusColor())
              .borderRadius(4)

            if (this.currentManga?.metadata.publicationYear) {
              Text(`${this.currentManga.metadata.publicationYear}`)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .opacity(0.6)
                .borderRadius(4)
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          // 操作按钮（缩小尺寸）
          Row({ space: 6 }) {
            Button({ stateEffect: true }) {
              Text(this.hasReadingProgress() ? '继续' : '开始')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            }
            .height(32)
            .layoutWeight(1)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(6)
            .onClick(() => this.startReading())

            Button() {
              Image(this.currentManga?.isFavorite ? $r('app.media.ic_favorite_filled') : $r('app.media.ic_favorite_outline'))
                .width(16)
                .height(16)
                .fillColor(this.currentManga?.isFavorite ?
                  ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
              radius: 6
            })
            .onClick(() => {
              this.toggleFavorite().catch((error: Error) => {
                logger.error(TAG, `收藏切换失败: ${error.message}`);
              });
            })

            Button() {
              SymbolGlyph($r('sys.symbol.gearshape'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
              radius: 6
            })
            .onClick(() => this.navigateToMangaSettings())
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .padding({ top: 8 })

          // 简介区域
          Column({ space: 12 }) {
            Text('简介')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')

            Text(this.currentManga?.description || '')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .lineHeight(18)
              .maxLines(this.expandDescription ? 1000 : 5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.expandDescription = !this.expandDescription;
              })

            if (this.currentManga?.metadata.genres && 
                Array.isArray(this.currentManga.metadata.genres) && 
                this.currentManga.metadata.genres.length > 0) {
              Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
                ForEach(this.currentManga.metadata.genres, (genre: string) => {
                  Text(genre)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
                    .borderRadius(4)
                    .border({
                      width: 1,
                      color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                    })
                })
              }
            }
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .padding({ top: 8, bottom: 16 })
      }
      .width('40%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))

      // 右侧60%：章节列表
      Column() {
        // 章节列表头部
        Column() {
          this.buildChapterListHeader()
          
          // 筛选菜单
          if (this.showChapterOptions) {
            this.buildChapterFilterStaticMenu()
          }
          
          // 章节统计
          if (this.isChapterLoading) {
            Column({ space: 12 }) {
              LoadingProgress().width(32).height(32)
              Text('章节加载中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .padding(20)
            .width('100%')
          } else {
            if (this.filteredChapters.length === 0) {
              Text('暂无章节')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .padding(20)
                .textAlign(TextAlign.Center)
            } else {
              Text(`共 ${this.filteredChapters.length} 个章节`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              if (this.accessDenied) {
                Text('未登录账号或权限不足，无法查看此漫画')
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
                  .padding({ left: 16, right: 16, bottom: 8 })
              }
            }
          }
        }
        .width('100%')
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius(12)
        .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 2 })
        .margin({ left: 16, right: 16, top: 16 })

        // 章节列表（可滚动）- 支持LIST和GRID两种显示模式
        if (!this.isChapterLoading) {
          if (this.chapterDisplayMode === ChapterDisplayMode.LIST) {
            // LIST模式：传统列表显示
            List({ space: 8 }) {
              LazyForEach(this.chapterDataSource, (chapter: MangaChapter, index: number) => {
                ListItem() {
                  this.buildChapterItem(chapter, index)
                }
                .width('100%')
              }, (chapter: MangaChapter) => chapter.id)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          } else {
            // GRID模式：网格显示，根据断点自适应列数
            Scroll() {
              Grid() {
                LazyForEach(this.chapterDataSource, (chapter: MangaChapter, index: number) => {
                  GridItem() {
                    this.buildChapterGridItem(chapter, index)
                  }
                }, (chapter: MangaChapter) => chapter.id)
              }
              .columnsTemplate(this.getGridColumnsTemplate())
              .rowsGap(8)
              .columnsGap(8)
              .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .padding({ left: 16, right: 16, top: 8, bottom: 16 })
          }
        }
      }
      .width('60%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
    }
    .width('100%')
    .height('100%')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景渐变区域（横屏）
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [
              [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_start', this.themeState.currentTheme), 0.0],
              [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_mid', this.themeState.currentTheme), 0.4],
              [ThemeAwareHelper.getTestManagementThemedColor('manga_detail_gradient_end', this.themeState.currentTheme), 1.0]
            ]
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Column() {
          // 添加下拉刷新组件
          if (this.isLoading) {
            Column({ space: 20 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

              Text('加载中...')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)

          } else if (this.loadError) {
            Column({ space: 20 }) {
              Image($r('sys.symbol.exclamationmark_circle_fill'))
                .width(64)
                .height(64)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))

              Text(this.loadError)
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)

              Button('重试')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .borderRadius(8)
                .padding({ left: 20, right: 20, top: 10, bottom: 10 })
                .onClick(() => this.retryLoad())
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .padding(20)

          } else if (this.isLandscape) {
            // 横屏模式：使用专用横屏布局
            this.buildLandscapeLayout()
          } else {
            // 下拉刷新组件包裹List
            Refresh({ refreshing: this.isPullRefreshing }) {
              // 单一List作为页面滚动容器，避免双滚动导致底部空白，保留回弹效果
              List({ space: 8 }) {
              // 封面区域
              ListItem() {
                this.buildCoverSection()
              }
              .width('100%')

              // 描述区域
              ListItem() {
                this.buildDescriptionSection()
              }
              .width('100%')

              // 章节列表头部与统计
              ListItem() {
                Column() {
                  this.buildChapterListHeader()
                  // 条件渲染：在按钮下方展示静态筛选菜单
                  if (this.showChapterOptions) {
                    this.buildChapterFilterStaticMenu()
                  }
                  if (this.isChapterLoading) {
                    Column({ space: 12 }) {
                      LoadingProgress().width(32).height(32)
                      Text('章节加载中...')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    }
                    .padding(20)
                    .width('100%')
                  } else {
                    if (this.filteredChapters.length === 0) {
                      Text('暂无章节')
                        .fontSize(16)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                        .padding(20)
                        .textAlign(TextAlign.Center)
                    } else {
                      Text(`共 ${this.filteredChapters.length} 个章节`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                      if (this.accessDenied) {
                        Text('未登录账号或权限不足，无法查看此漫画')
                          .fontSize(13)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
                          .padding({ left: 16, right: 16, bottom: 8 })
                      }
                    }
                  }
                }
                .width('100%')
                .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
                .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
                .borderRadius(12)
                .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 2 })
              }
              .width('100%')

              // 章节列表
              if (!this.isChapterLoading) {
                LazyForEach(this.chapterDataSource, (chapter: MangaChapter, index: number) => {
                  ListItem() {
                    this.buildChapterItem(chapter, index)
                  }
                  .width('100%')
                }, (chapter: MangaChapter) => chapter.id)
              }
              }
              .width('100%')
              .height('100%')
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .onScrollIndex((start: number, end: number) => {
                // onScrollIndex 替代 onScroll，这里不再需要scrollOffset
                // 如果需要滚动位置，可以使用 Scroller 对象
              })
            }
            .onStateChange((refreshStatus: RefreshStatus) => {
              logger.debug(TAG, `下拉刷新状态变化: ${refreshStatus}`);
            })
            .onRefreshing(() => {
              logger.info(TAG, '触发下拉刷新');
              this.refreshMangaData();
            })
            .refreshOffset(64)
            .pullToRefresh(true)
            .width('100%')
            .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 隐藏的WebView组件（用于网络漫画）
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(1)
          .height(1)
          .visibility(Visibility.None)

        // 移除模态遮罩弹窗，改为静态菜单（已在章节列表头部内条件渲染）
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.pageParams = context.pathInfo.param as MangaDetailPageParams;
      logger.info(TAG, `页面参数: ${JSON.stringify(this.pageParams)}`);

      logger.info(TAG, '参数设置完成，开始加载数据');
      this.loadMangaData().catch((error: Error) => {
        logger.error(TAG, `初始加载失败: ${error.message}`);
      });
    })
    .onShown(() => {
      // 从阅读器返回时自动刷新阅读进度
      logger.lifecycle(TAG, '📱 页面显示，自动刷新阅读进度');
      this.refreshReadingProgressSilently();
    })
  }

  /**
   * 跳转到漫画设置页面
   */
  private navigateToMangaSettings(): void {
    const mg: Manga | null = this.currentManga;
    if (!mg) {
      logger.warn(TAG, '当前漫画为空，无法跳转到设置页面');
      return;
    }

    const params: MangaSettingsPageParams = { mangaId: mg.id, fromPage: 'MangaDetailPage' } as MangaSettingsPageParams;
    try {
      this.pathStack.pushPathByName('MangaSettingsPage', params);
      logger.info(TAG, `已跳转到漫画设置页面: mangaId=${mg.id}`);
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `跳转漫画设置页面失败: ${errorMessage}`);
    }
  }

  /**
   * 跳转到全局搜索页面并搜索指定关键词
   */
  private navigateToGlobalSearch(keyword: string): void {
    if (!keyword || keyword.trim().length === 0) {
      logger.warn(TAG, '搜索关键词为空');
      return;
    }
    
    try {
      const searchParams: GlobalSearchPageParams = { initialKeyword: keyword.trim() };
      this.pathStack.pushPathByName('GlobalSearchPage', searchParams);
      logger.info(TAG, `跳转到全局搜索页面: keyword=${keyword}`);
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `跳转全局搜索页面失败: ${errorMessage}`);
    }
  }

  /**
   * 下载选中的章节
   */
  private async downloadSelectedChapters(): Promise<void> {
    if (this.selectedChapters.size === 0) {
      logger.warn(TAG, '没有选中任何章节');
      return;
    }

    const manga = this.currentManga;
    if (!manga) {
      logger.warn(TAG, '当前漫画为空，无法下载');
      return;
    }

    try {
      logger.info(TAG, `开始下载 ${this.selectedChapters.size} 个章节`);
      
      // 获取选中的章节对象
      const selectedChapterList: MangaChapter[] = manga.chapters.filter(
        (ch: MangaChapter) => this.selectedChapters.has(ch.id)
      );

      // 导入下载管理器
      const DownloadModule = await import('../Framework/Download/DownloadManager');
      const downloadManager = DownloadModule.MangaDownloadManager.getInstance();

      // 为每个选中的章节创建下载任务
      let successCount = 0;
      let failCount = 0;

      for (const chapter of selectedChapterList) {
        try {
          // 如果是WebView图源，需要先获取图片列表
          let imageUrls: string[] = [];
          
          // [关键] 对于在线漫画，使用externalId（外部ID）而不是内部数据库ID
          // PicaComic等API需要真实的漫画ID和章节顺序号
          const chapterIdForApi: string = chapter.externalId || chapter.id;
          const mangaIdForApi: string = this.pageParams?.mangaId || manga.id;
          
          logger.info(TAG, `下载章节: ${chapter.title}, chapterIdForApi=${chapterIdForApi}, mangaIdForApi=${mangaIdForApi}`);
          
          if (this.useWebView && this.mangaEngine) {
            // 从WebView图源获取图片列表（使用外部ID）
            const pageListResult = await this.mangaEngine.getPageList(chapterIdForApi, mangaIdForApi);
            if (pageListResult.success && pageListResult.data) {
              const pages = pageListResult.data as Array<SourcePageInfo>;
              imageUrls = pages.map((page: SourcePageInfo) => page.imageUrl);
            }
          } else if (chapter.pages && chapter.pages.length > 0) {
            // 从本地数据获取图片URL
            imageUrls = chapter.pages.map((page: MangaPage) => page.imageUrl);
          }

          // 创建下载任务
          // 根据是否为在线漫画选择不同的下载方法
          if (this.pageParams?.sourceId) {
            // 在线漫画：使用公共Download目录
            if (imageUrls.length > 0) {
              // 已有图片列表，直接下载
              await downloadManager.createOnlineMangaDownloadTask(
                manga.id,
                manga.title,
                chapter.id,
                chapter.title,
                imageUrls,
                this.pageParams.sourceId
              );
            } else if (this.useWebView && this.mangaEngine) {
              // 没有图片列表，使用延迟获取方式（下载时再获取）
              const engine = this.mangaEngine;
              const externalMangaId: string = mangaIdForApi;
              const externalChapterId: string = chapterIdForApi;
              await downloadManager.createOnlineMangaDownloadTaskWithFetcher(
                manga.id,
                manga.title,
                chapter.id,
                chapter.title,
                this.pageParams.sourceId,
                async (_chapterId: string, _mangaId: string): Promise<string[]> => {
                  // 使用外部ID调用API
                  const result = await engine.getPageList(externalChapterId, externalMangaId);
                  if (result.success && result.data) {
                    const pages = result.data as Array<SourcePageInfo>;
                    return pages.map((page: SourcePageInfo) => page.imageUrl);
                  }
                  return [];
                }
              );
            } else {
              logger.warn(TAG, `章节 ${chapter.title} 没有可下载的图片且无法获取`);
              failCount++;
              continue;
            }
          } else {
            // 本地漫画：使用应用私有目录
            if (imageUrls.length === 0) {
              logger.warn(TAG, `章节 ${chapter.title} 没有可下载的图片`);
              failCount++;
              continue;
            }
            await downloadManager.createDownloadTask(
              manga.id,
              manga.title,
              chapter.id,
              chapter.title,
              imageUrls
            );
          }
          
          successCount++;
          logger.info(TAG, `章节下载任务已创建: ${chapter.title}`);
        } catch (error) {
          const errorMessage: string = error instanceof Error ? error.message : String(error);
          logger.error(TAG, `创建下载任务失败: ${chapter.title}, ${errorMessage}`);
          failCount++;
        }
      }

      // 显示结果提示
      if (successCount > 0) {
        this.getUIContext().getPromptAction().showToast({
          message: `已添加 ${successCount} 个下载任务${failCount > 0 ? `，${failCount} 个失败` : ''}`,
          duration: 2000
        });
      } else {
        this.getUIContext().getPromptAction().showToast({
          message: '下载任务创建失败',
          duration: 2000
        });
      }

      // 退出多选模式
      this.isSelectionMode = false;
      this.selectedChapters.clear();

    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `下载章节失败: ${errorMessage}`);
      this.getUIContext().getPromptAction().showToast({
        message: '下载失败，请稍后重试',
        duration: 2000
      });
    }
  }

  /**
   * 注册下载进度监听器
   */
  private async registerDownloadProgressListener(): Promise<void> {
    try {
      const DownloadModule = await import('../Framework/Download/DownloadManager');
      const downloadManager = DownloadModule.MangaDownloadManager.getInstance();
      
      // 生成唯一的监听器ID
      this.downloadProgressListenerId = `manga_detail_${Date.now()}`;
      
      // 注册进度回调
      downloadManager.registerProgressCallback(
        this.downloadProgressListenerId,
        (taskId: string, chapterId: string, progress: number, downloadedCount: number, totalCount: number) => {
          logger.debug(TAG, `下载进度更新: chapterId=${chapterId}, progress=${progress}%, ${downloadedCount}/${totalCount}`);
          
          // 更新章节下载进度
          this.chapterDownloadProgress.set(chapterId, progress);
          
          // 更新章节列表中的进度
          if (this.currentManga && this.currentManga.chapters) {
            const chapter = this.currentManga.chapters.find(ch => ch.id === chapterId);
            if (chapter) {
              chapter.downloadProgress = progress;
              if (progress >= 100) {
                chapter.isDownloaded = true;
                chapter.downloadStatus = DownloadStatus.COMPLETED;
              } else {
                chapter.downloadStatus = DownloadStatus.DOWNLOADING;
              }
              // 触发UI刷新 - 直接修改chapters数组引用
              this.currentManga.chapters = [...this.currentManga.chapters];
            }
          }
        }
      );
      
      logger.info(TAG, `下载进度监听器已注册: ${this.downloadProgressListenerId}`);
    } catch (error) {
      logger.warn(TAG, `注册下载进度监听器失败: ${String(error)}`);
    }
  }

  /**
   * 取消下载进度监听器
   */
  private async unregisterDownloadProgressListener(): Promise<void> {
    if (this.downloadProgressListenerId) {
      try {
        const DownloadModule = await import('../Framework/Download/DownloadManager');
        const downloadManager = DownloadModule.MangaDownloadManager.getInstance();
        downloadManager.unregisterProgressCallback(this.downloadProgressListenerId);
        logger.info(TAG, `下载进度监听器已取消: ${this.downloadProgressListenerId}`);
      } catch (error) {
        logger.warn(TAG, `取消下载进度监听器失败: ${String(error)}`);
      }
      this.downloadProgressListenerId = '';
    }
  }

  /**
   * 应用章节筛选和排序
   */
  private applyChapterFilters(): void {
    // 统一入口，复用 updateFilteredChapters，避免逻辑分叉
    this.updateFilteredChapters();
  }

  /**
   * 下载所有章节
   */
  private async downloadAllChapters(): Promise<void> {
    const manga = this.currentManga;
    if (!manga || !manga.chapters || manga.chapters.length === 0) {
      logger.warn(TAG, '没有可下载的章节');
      this.getUIContext().getPromptAction().showToast({
        message: '没有可下载的章节',
        duration: 2000
      });
      return;
    }

    // 选中所有章节
    this.selectedChapters.clear();
    for (const chapter of manga.chapters) {
      this.selectedChapters.add(chapter.id);
    }

    logger.info(TAG, `选中所有章节进行下载，共 ${this.selectedChapters.size} 个`);
    
    // 调用下载选中章节的方法
    await this.downloadSelectedChapters();
    
    // 退出多选模式
    this.isSelectionMode = false;
    this.selectedChapters.clear();
  }

  /**
   * 下载未读章节
   */
  private async downloadUnreadChapters(): Promise<void> {
    const manga = this.currentManga;
    if (!manga || !manga.chapters || manga.chapters.length === 0) {
      logger.warn(TAG, '没有可下载的章节');
      this.getUIContext().getPromptAction().showToast({
        message: '没有可下载的章节',
        duration: 2000
      });
      return;
    }

    // 选中所有未读章节
    this.selectedChapters.clear();
    for (const chapter of manga.chapters) {
      // 判断章节是否已读：检查是否有阅读历史且进度为100%
      const isRead = this.isChapterRead(chapter);
      if (!isRead) {
        this.selectedChapters.add(chapter.id);
      }
    }

    if (this.selectedChapters.size === 0) {
      logger.info(TAG, '没有未读章节需要下载');
      this.getUIContext().getPromptAction().showToast({
        message: '没有未读章节',
        duration: 2000
      });
      return;
    }

    logger.info(TAG, `选中未读章节进行下载，共 ${this.selectedChapters.size} 个`);
    
    // 调用下载选中章节的方法
    await this.downloadSelectedChapters();
    
    // 退出多选模式
    this.isSelectionMode = false;
    this.selectedChapters.clear();
  }

  /**
   * 删除选中的章节（包括本地文件和数据库记录）
   */
  private async deleteSelectedChapters(): Promise<void> {
    if (this.selectedChapters.size === 0) {
      logger.warn(TAG, '没有选中任何章节');
      return;
    }

    const manga = this.currentManga;
    if (!manga) {
      logger.warn(TAG, '当前漫画信息不存在');
      return;
    }

    try {
      logger.info(TAG, `开始删除选中的章节，共 ${this.selectedChapters.size} 个`);
      const dm: DataManager = DataManager.getInstance();
      
      // 遍历选中的章节进行删除
      for (const chapterId of this.selectedChapters) {
        const chapter = manga.chapters.find(ch => ch.id === chapterId);
        if (!chapter) {
          continue;
        }

        // 1. 删除本地下载的图片文件
        try {
          const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
          if (context) {
            const chapterDir = `${context.filesDir}/comics/${manga.id}/chapters/${chapterId}`;
            if (SafeFileUtils.accessSync(chapterDir)) {
              SafeFileUtils.rmdirSync(chapterDir);
              logger.info(TAG, `已删除章节目录: ${chapterDir}`);
            }
          }
        } catch (fileErr) {
          logger.warn(TAG, `删除章节文件失败: ${String(fileErr)}`);
        }

        // 2. 删除数据库中的下载记录
        try {
          await dm.deleteDownloadTasksByChapter(manga.id, chapterId);
        } catch (dbErr) {
          logger.warn(TAG, `删除下载记录失败: ${String(dbErr)}`);
        }

        // 3. 更新章节状态
        chapter.isDownloaded = false;
        chapter.downloadProgress = 0;
        try {
          await dm.updateChapterInfo(chapterId, {
            isDownloaded: false,
            downloadPath: ''
          });
        } catch (chapterErr) {
          logger.warn(TAG, `更新章节下载状态失败: ${String(chapterErr)}`);
        }
      }

      // 刷新章节列表
      this.filteredChapters = [...this.filteredChapters];
      this.applyChapterFilters();
      
      logger.info(TAG, `成功删除 ${this.selectedChapters.size} 个章节`);
      
      // 退出多选模式
      this.isSelectionMode = false;
      this.selectedChapters.clear();
      
    } catch (error) {
      logger.error(TAG, `删除章节失败: ${String(error)}`);
    }
  }

  /**
   * 删除所有已下载章节
   */
  private async deleteAllDownloadedChapters(): Promise<void> {
    const manga = this.currentManga;
    if (!manga || !manga.chapters || manga.chapters.length === 0) {
      logger.warn(TAG, '没有可删除的章节');
      return;
    }

    // 选中所有已下载的章节
    this.selectedChapters.clear();
    for (const chapter of manga.chapters) {
      if (chapter.isDownloaded) {
        this.selectedChapters.add(chapter.id);
      }
    }

    if (this.selectedChapters.size === 0) {
      logger.warn(TAG, '没有已下载的章节');
      return;
    }

    logger.info(TAG, `选中所有已下载章节进行删除，共 ${this.selectedChapters.size} 个`);
    
    // 调用删除选中章节的方法
    await this.deleteSelectedChapters();
  }
}

class ChapterDataSource implements IDataSource {
  private chapters: MangaChapter[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(chapters: MangaChapter[]) {
    this.chapters = chapters;
  }

  totalCount(): number {
    return this.chapters.length;
  }

  getData(index: number): MangaChapter {
    return this.chapters[index];
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

  notifyDataReload(): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    listenersSnapshot.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  notifyDataAdd(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    listenersSnapshot.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index);
    });
  }

  notifyDataChange(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    listenersSnapshot.forEach((listener: DataChangeListener) => {
      listener.onDataChange(index);
    });
  }

  notifyDataDelete(index: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    listenersSnapshot.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }

  notifyDataMove(from: number, to: number): void {
    const listenersSnapshot: DataChangeListener[] = this.listeners.slice();
    listenersSnapshot.forEach((listener: DataChangeListener) => {
      listener.onDataMove(from, to);
    });
  }
}

export { MangaDetailPage }

