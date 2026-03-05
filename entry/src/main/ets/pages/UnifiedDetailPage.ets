// 文件路径: entry/src/main/ets/pages/UnifiedDetailPage.ets
/**
 * 统一详情页
 * 支持显示漫画、电子书、小说的详细信息
 * 通过适配器模式将不同类型数据转换为统一展示格式
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction, curves } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';

import {
  UnifiedContent,
  UnifiedChapter,
  UnifiedContentType,
  UnifiedReadStatus,
  UnifiedDetailPageParams,
  UnifiedContentActions,
  ChapterFilterType,
  ChapterSortOrder,
  ChapterDisplayMode,
  OriginalBookInfo
} from '../Models/UnifiedContentModels';

import {
  UnifiedContentAdapterFactory,
  MangaAdapter,
  EBookAdapter,
  NovelAdapter,
  AdapterOptions
} from '../Framework/Adapters/UnifiedContentAdapter';

// 数据管理器导入
import { DataManager, ChapterInfo, OnlineChapterInfo } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { MangaDetailLoader, MangaDetailLoadParams, MangaDetailLoadResult, MangaLoadProgressCallback, ChapterProgressInfo } from '../Framework/Loaders/MangaDetailLoader';
import webview from '@ohos.web.webview';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { AntiCrawlerConfig } from '../Framework/WebView/MangaSourceTypes';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelSourceSearchService, SourceSearchResult, SearchTaskHandle, SearchResultCache } from '../Framework/Novel/NovelSourceSearchService';
import { getCacheStatusService, CacheStatusService, ContentCacheStats, CacheContentType } from '../Framework/Services/CacheStatusService';
import { getUnifiedDownloadManager, UnifiedDownloadManager, UnifiedDownloadType, UnifiedTaskStatus, UnifiedDownloadTask, UnifiedDownloadCallback, MangaChapterDownloadItem, PageListFetcher } from '../Framework/Download/UnifiedDownloadManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { getCoverImageManager, CoverImageManager } from '../Framework/Image/CoverImageManager';
import { image } from '@kit.ImageKit';
import { getNovelCoverGenerator, NovelCoverGenerator } from '../Framework/Novel/NovelCoverGenerator';
import { ZLibraryReaderParams } from './ZLibraryReaderPage';
import { AvifImage } from '../components/AvifImage';
import { eventBus, GameEvent, IEventPayload, CoverChangedPayload, BasePayload } from '../Framework/EventBus';
import { getTypeShelfManager, TypeShelfManager, TypeShelf, ShelfType, ShelfContentType } from '../Framework/Data/TypeShelfManager';
import { BookshelfCategoryManager, ContentType, CategoryItem } from '../Framework/Data/BookshelfCategoryManager';
import { GlobalSearchPageParams } from './GlobalSearchPage';
import { GlobalSearchService, UnifiedSearchItem } from '../Framework/Services/GlobalSearchService';

// 模型导入
import { Manga, MangaChapter, ReadingProgress, ReadingSettings, MangaBookmark, MangaMetadata, ImageSourceType, DEFAULT_READING_SETTINGS } from '../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { EBook, EBookChapter, EBookFormat, EBookStatus, EBookMetadata } from '../Models/EBookModels';
import { LegadoBook, LegadoChapter, LegadoBookSource } from '../Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus, NovelSearchResult } from '../Models/NovelModels';

// 阅读器参数导入
import { MangaReaderPageParams, MangaReaderContentType } from './MangaReaderPage';
import { MangaSettingsPageParams } from './MangaSettingsPage';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { EBookReaderParams } from './EBookReaderPage';
import { NovelReaderPageParams } from './NovelBookshelfPage';

import { startBookOpenTransitionWithComponentId } from '../components/BookTransitionOverlay';

const TAG = 'UnifiedDetailPage';
const TITLE_BAR_HEIGHT = 56;
const COVER_HEIGHT = 200;
const COVER_WIDTH = 140;

// ==================== 智能推荐栏常量 ====================
const RECOMMEND_CARD_COVER_W = 90;   // 推荐卡片封面宽度
const RECOMMEND_CARD_COVER_H = 130;  // 推荐卡片封面高度
const RECOMMEND_MAX_COUNT = 8;       // 最多显示推荐数量
const RECOMMEND_MIN_SCORE = 15;      // 本地推荐最低相关度阈值

// ==================== 同书架内容常量 ====================
const SHELF_CONTENT_CARD_COVER_W = 90;   // 同书架卡片封面宽度
const SHELF_CONTENT_CARD_COVER_H = 130;  // 同书架卡片封面高度
const SHELF_CONTENT_MAX_COUNT = 20;      // 最多显示同书架内容数量

/**
 * 同书架内容筛选类型
 */
type ShelfContentFilterType = 'all' | 'manga' | 'novel' | 'ebook';

/**
 * 同书架内容项
 */
interface ShelfContentItem {
  id: string;
  title: string;
  coverUrl: string;
  contentType: UnifiedContentType;
  /** 导航时使用的内容ID */
  navContentId: string;
  /** 导航时使用的图源ID（在线内容） */
  navSourceId?: string;
}

/**
 * 同书架筛选标签
 */
interface ShelfFilterTab {
  key: ShelfContentFilterType;
  label: string;
}

/**
 * 智能推荐内容项
 */
interface RecommendationItem {
  id: string;
  title: string;
  coverUrl: string;
  contentType: UnifiedContentType;
  isLocal: boolean;
  sourceId?: string;
  sourceName?: string;
  score: number;
  /** 导航时使用的内容ID */
  navContentId: string;
  /** 导航时使用的图源ID（在线内容） */
  navSourceId?: string;
}

@Component
export struct UnifiedDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = `UnifiedDetailPage_${Date.now()}`;
  private scroller: Scroller = new Scroller();

  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 页面参数
  private pageParams: UnifiedDetailPageParams | null = null;

  // 统一内容数据
  @State content: UnifiedContent | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  
  // 分阶段加载状态
  @State isBasicInfoLoaded: boolean = false;  // 基本信息是否加载完成
  @State isCoverLoading: boolean = true;      // 封面是否正在加载
  @State isChaptersLoading: boolean = true;   // 章节是否正在加载
  @State isPagesPreloading: boolean = false;  // 页面是否正在预加载
  @State chaptersLoadProgress: string = '';   // 章节加载进度文本
  
  // 下拉刷新状态
  @State isRefreshing: boolean = false;       // 是否正在刷新
  @State refreshProgress: string = '';        // 刷新进度文本
  
  // 重新获取状态（在线漫画）
  @State isRefetchingManga: boolean = false;  // 是否正在重新获取漫画信息
  @State isRefetchingCover: boolean = false;  // 是否正在重新获取封面
  
  // 封面预览状态
  @State showCoverPreview: boolean = false;   // 是否显示封面全屏预览
  @State coverPreviewOpacity: number = 0;     // 封面预览背景透明度
  @State coverPreviewScale: number = 0.3;     // 封面预览缩放比例
  @State isSavingCover: boolean = false;      // 是否正在保存封面
  
  // 在线漫画封面缓存
  @State localCoverPath: string = '';         // 本地缓存的封面路径
  @State coverPixelMap: image.PixelMap | null = null;  // 封面 PixelMap（优先使用）
  private coverPixelMapOwned: boolean = false;         // 是否拥有 PixelMap 的所有权（需要负责释放）
  
  // 漫画章节进度数据
  @State chapterProgressMap: Map<string, ChapterProgressInfo> = new Map();
  
  // 缓存状态服务和数据
  private cacheStatusService: CacheStatusService = getCacheStatusService();
  private unifiedDownloadManager: UnifiedDownloadManager = getUnifiedDownloadManager();
  @State cacheStats: ContentCacheStats | null = null;
  @State isCacheStatsLoading: boolean = false;
  @State showCacheStatusCard: boolean = false;  // 控制是否显示缓存卡片
  @State isDownloading: boolean = false;        // 是否正在下载
  
  // 下载对话框状态
  @State showDownloadDialog: boolean = false;           // 显示下载对话框
  @State downloadDialogOpacity: number = 0;             // 对话框背景透明度
  @State downloadDialogScale: number = 0.8;             // 对话框缩放
  @State downloadDialogTranslateY: number = 50;         // 对话框Y偏移
  @State downloadSelectionMode: 'range' | 'individual' = 'range';  // 选择模式
  @State downloadRangeStart: number = 0;                // 区间开始
  @State downloadRangeEnd: number = 0;                  // 区间结束
  @State downloadSelectedChapters: Set<number> = new Set();  // 单独选中的章节
  @State downloadChapterListExpanded: boolean = false;  // 章节列表是否展开
  
  // 下载进度实时显示状态
  @State downloadProgressCurrent: number = 0;           // 当前下载进度
  @State downloadProgressTotal: number = 0;             // 总下载数量
  @State downloadCurrentChapterTitle: string = '';      // 当前正在下载的章节标题
  private downloadCallbackRegistered: boolean = false;  // 是否已注册下载回调
  
  // 换源对话框状态
  @State showChangeSourceDialog: boolean = false;       // 显示换源对话框
  @State changeSourceDialogOpacity: number = 0;         // 对话框背景透明度
  @State changeSourceDialogScale: number = 0.8;         // 对话框缩放
  @State changeSourceDialogTranslateY: number = 30;     // 对话框Y偏移
  @State isSearchingSource: boolean = false;            // 是否正在搜索书源
  @State searchSourceProgress: number = 0;              // 搜索进度(0-100)
  @State searchSourceTotal: number = 0;                 // 总书源数
  @State searchSourceCompleted: number = 0;             // 已完成搜索的书源数
  @State alternativeSourceResults: SourceSearchResult[] = [];  // 按书源分组的搜索结果
  @State alternativeSources: NovelSearchResult[] = [];  // 所有搜索结果
  @State changeSourceKeyword: string = '';              // 换源搜索关键词
  private searchTaskHandle: SearchTaskHandle | null = null;    // 搜索任务句柄
  private sourceSearchService = getNovelSourceSearchService(); // 换源搜索服务
  
  // 换源替换相关状态
  @State isFromChangeSource: boolean = false;           // 是否来自换源
  @State originalBookInfo: OriginalBookInfo | null = null;  // 原书信息
  @State showReplaceBookDialog: boolean = false;        // 显示替换小说对话框
  @State replaceDialogOpacity: number = 0;              // 替换对话框透明度
  @State replaceDialogScale: number = 0.8;              // 替换对话框缩放
  @State replaceDialogTranslateY: number = 30;          // 替换对话框Y偏移
  @State matchedChapterIndex: number = -1;              // 匹配到的新书章节索引

  // UI状态
  @State isFavorite: boolean = false;
  @State showFullDescription: boolean = false;
  @State descriptionSelectedText: string = '';  // 简介中当前选中的文本
  @State showChapterPanel: boolean = false;
  @State chapterFilter: ChapterFilterType = ChapterFilterType.ALL;
  @State chapterSortOrder: ChapterSortOrder = ChapterSortOrder.ASCENDING;
  @State chapterDisplayMode: ChapterDisplayMode = ChapterDisplayMode.LIST;
  
  // 书架相关状态
  private typeShelfManager: TypeShelfManager = getTypeShelfManager();
  @State isInShelf: boolean = false;                    // 是否已在书架中
  @State currentShelfName: string = '';                 // 当前所在书架名称
  @State currentShelfId: string = '';                   // 当前所在书架ID
  @State showAddToShelfDialog: boolean = false;         // 显示添加到书架对话框
  @State addToShelfDialogOpacity: number = 0;           // 对话框背景透明度
  @State addToShelfDialogScale: number = 0.8;           // 对话框缩放
  @State availableCustomShelves: TypeShelf[] = [];      // 可用的自定义书架列表
  
  // 同书架内容状态
  @State shelfContentItems: ShelfContentItem[] = [];    // 同书架的其他内容
  @State isLoadingShelfContent: boolean = false;        // 是否正在加载同书架内容
  @State shelfContentFilter: ShelfContentFilterType = 'all';  // 内容类型筛选
  @State isShelfContentExpanded: boolean = true;        // 同书架内容是否展开
  @State isRecommendationsExpanded: boolean = true;     // 相关推荐是否展开

  // 数据管理器
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private novelSourceManager = getNovelSourceManager();
  private novelDataManager = getNovelDataManager();
  private novelCacheManager = getNovelChapterCacheManager();
  private coverGenerator = getNovelCoverGenerator();
  
  // 生成封面状态
  @State isGeneratingCover: boolean = false;
  @State showGenerateCoverDialog: boolean = false;
  @State coverTitleInput: string = '';
  @State coverFontScale: number = 1.0;
  @State dialogOpacity: number = 0;
  @State dialogScale: number = 0.8;
  @State dialogTranslateY: number = 30;
  @State coverRefreshKey: number = 0;

  // 封面生成器常量
  static readonly COVER_WIDTH = 400;
  static readonly COVER_HEIGHT = 600;
  static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;
  
  // 漫画详情加载器
  private mangaDetailLoader: MangaDetailLoader = MangaDetailLoader.getInstance();
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  @State private webViewControllerAttached: boolean = false;
  private pendingInitialContentLoad: boolean = false;
  private initialContentLoadTriggered: boolean = false;
  
  /**
   * 生成小说缓存用的bookId
   * 格式与NovelReaderPage保持一致：${sourceId}_${encodeURIComponent(bookUrl)}
   */
  private getNovelCacheBookId(sourceId: string, bookUrl: string): string {
    return `${sourceId}_${encodeURIComponent(bookUrl)}`;
  }
  
  /**
   * 判断下载任务是否属于当前内容
   * 小说使用 novelCacheBookId 格式，漫画使用原始 id
   */
  private isCurrentContentTask(task: UnifiedDownloadTask): boolean {
    if (!this.content) return false;
    
    // 小说使用特殊的 bookId 格式
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      // [修复] 优先使用content.sourceId，因为loadNovelContent已经从数据库获取了正确的sourceId
      const sourceId = this.content.sourceId || this.pageParams?.sourceId;
      if (sourceId) {
        const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
        return task.contentId === novelCacheBookId;
      }
    }
    
    // 漫画和其他类型直接比较原始 id
    return task.contentId === this.content.id;
  }
  
  // 在线电子书相关
  private sourceManager: SourceManager = SourceManager.getInstance();
  private ebookSourceEngine: MangaSourceEngine | null = null;
  @State private ebookWebViewReady: boolean = false;
  @State private ebookSourceInfo: SourceInfo | null = null;
  @State private onlineReaderUrl: string = '';
  
  // 设置管理器
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  
  // 智能推荐状态
  @State recommendedItems: RecommendationItem[] = [];
  @State isLoadingRecommendations: boolean = false;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
    this.webViewControllerAttached = false;
    logger.info(TAG, 'Waiting hidden WebView controller attach');
  }

  private triggerInitialContentLoadIfReady(): void {
    if (this.initialContentLoadTriggered || !this.pageParams) {
      return;
    }

    if (!this.webViewControllerAttached) {
      this.pendingInitialContentLoad = true;
      logger.info(TAG, 'WebView控制器未附加，延迟加载详情页内容');
      return;
    }

    this.pendingInitialContentLoad = false;
    this.initialContentLoadTriggered = true;
    this.loadContent();
  }

  private lifecycle = new PageLifecycleManager('UnifiedDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);

    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

    this.webViewControllerAttached = false;
    this.pendingInitialContentLoad = false;
    this.initialContentLoadTriggered = false;
    
    // 取消下载回调注册
    if (this.downloadCallbackRegistered) {
      this.unregisterDownloadCallback();
    }
    
    // 取消正在进行的换源搜索
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
    
    // 释放封面 PixelMap 资源（仅释放自己拥有的，不释放从 CoverImageManager 借用的）
    if (this.coverPixelMap && this.coverPixelMapOwned) {
      this.coverPixelMap.release();
    }
    this.coverPixelMap = null;
    this.coverPixelMapOwned = false;
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 加载内容数据
   */
  private async loadContent(): Promise<void> {
    if (!this.pageParams) {
      this.errorMessage = '缺少页面参数';
      this.isLoading = false;
      return;
    }

    try {
      this.isLoading = true;
      this.errorMessage = '';

      switch (this.pageParams.contentType) {
        case UnifiedContentType.MANGA:
          await this.loadMangaContent();
          break;
        case UnifiedContentType.EBOOK:
          await this.loadEBookContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.loadNovelContent();
          break;
        default:
          this.errorMessage = '未知的内容类型';
      }

      // 检查SFW模式
      if (this.content && this.content.isNSFW) {
        const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
        if (sfwEnabled) {
          logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
          promptAction.showToast({
            message: 'SFW模式已启用，无法查看此内容',
            duration: 2000
          });
          this.pathStack.pop();
          return;
        }
      }
      
      // 加载缓存状态（在线漫画和小说）
      await this.loadCacheStatus();
      
      // 检查是否已在书架中
      await this.checkIfInShelf();
      
      // 加载同书架内容（非阻塞，仅当在自定义书架中且设置开启时）
      if (this.currentShelfId && this.settingsManager.getBoolean(SettingKeys.SHELF_CONTENT_ENABLED, true)) {
        this.loadShelfContent();
      } else {
        logger.debug(TAG, '同书架内容功能已关闭或不在自定义书架中，跳过加载');
      }
      
      // 触发智能推荐加载（非阻塞，仅当设置开启时）
      if (this.settingsManager.getBoolean(SettingKeys.RECOMMENDATION_ENABLED, true)) {
        this.loadRecommendations();
      } else {
        logger.debug(TAG, '相关推荐功能已关闭，跳过加载');
      }

    } catch (error) {
      logger.error(TAG, '加载内容失败', String(error));
      this.errorMessage = '加载失败，请重试';
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载漫画内容（使用MangaDetailLoader分阶段加载）
   */
  private async loadMangaContent(): Promise<void> {
    if (!this.pageParams) return;

    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载漫画内容: mangaId=${mangaId}, sourceId=${sourceId}`);

    // 重置加载状态
    this.isBasicInfoLoaded = false;
    this.isCoverLoading = true;
    this.isChaptersLoading = true;
    this.isPagesPreloading = false;
    this.chaptersLoadProgress = '';

    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);

    // 构建加载参数
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: sourceId ? Number(sourceId) : undefined,
      cachedTitle: this.pageParams.cachedTitle,
      cachedCover: this.pageParams.cachedCover,
      forceRefresh: false
    };

    // 构建已读/已下载/书签章节ID集合
    const readChapterIds = new Set<string>();
    const downloadedChapterIds = new Set<string>();
    const bookmarkedChapterIds = new Set<string>();
    let lastReadChapterIndex = -1;

    // 分阶段加载回调
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        logger.info(TAG, `[分阶段] 基本信息已加载: ${manga.title}`);
        this.isFavorite = isFavorite;
        this.isBasicInfoLoaded = true;
        this.isLoading = false;  // 基本信息加载完成，停止主加载动画
        
        // 先显示基本信息（无章节）
        this.content = MangaAdapter.toUnifiedContent(
          manga,
          [],  // 章节稍后加载
          isFavorite,
          readChapterIds,
          downloadedChapterIds,
          bookmarkedChapterIds,
          lastReadChapterIndex,
          sourceId
        );
        
        // 封面加载完成
        this.isCoverLoading = false;
        
        // 在线漫画：加载本地缓存的封面
        if (sourceId && Number(sourceId) > 0) {
          this.loadCachedCover(Number(sourceId), mangaId);
        }
      },
      
      onChaptersLoaded: async (chapters: MangaChapter[]) => {
        logger.info(TAG, `[分阶段] 章节已加载: ${chapters.length}章`);
        logger.debug(TAG, `[DEBUG-1] onChaptersLoaded 开始执行`);
        this.isChaptersLoading = false;
        
        // 标记已下载章节
        logger.debug(TAG, `[DEBUG-2] 开始标记已下载章节`);
        chapters.forEach((ch: MangaChapter) => {
          if (ch.isDownloaded) {
            downloadedChapterIds.add(ch.id);
          }
        });
        logger.debug(TAG, `[DEBUG-3] 已下载章节标记完成`);
        
        // 加载章节进度数据
        logger.debug(TAG, `[DEBUG-4] 开始加载章节进度数据`);
        const isOnline = sourceId !== undefined && Number(sourceId) > 0;
        const progressData = await this.mangaDetailLoader.loadChapterProgressData(
          mangaId, 
          chapters, 
          isOnline
        );
        logger.debug(TAG, `[DEBUG-5] 章节进度数据加载完成`);
        
        // 更新已读章节ID集合和最后阅读章节索引
        logger.debug(TAG, `[DEBUG-6] 开始更新已读章节ID集合`);
        progressData.readChapterIds.forEach(id => readChapterIds.add(id));
        lastReadChapterIndex = progressData.lastReadChapterIndex;
        logger.debug(TAG, `[DEBUG-7] lastReadChapterIndex 原始值: ${lastReadChapterIndex}`);
        
        // [修复] 确保 lastReadChapterIndex 在有效范围内
        if (typeof lastReadChapterIndex !== 'number' || isNaN(lastReadChapterIndex)) {
          lastReadChapterIndex = -1;
        } else if (lastReadChapterIndex >= chapters.length) {
          lastReadChapterIndex = -1;
        }
        logger.debug(TAG, `[DEBUG-8] lastReadChapterIndex 验证后: ${lastReadChapterIndex}`);
        
        // 保存章节进度到Map中（用于UI显示）
        logger.debug(TAG, `[DEBUG-9] 开始保存章节进度到Map`);
        const newProgressMap = new Map<string, ChapterProgressInfo>();
        progressData.progressList.forEach((progress: ChapterProgressInfo) => {
          newProgressMap.set(progress.chapterId, progress);
        });
        this.chapterProgressMap = newProgressMap;
        logger.debug(TAG, `[DEBUG-10] 章节进度Map保存完成, 大小: ${newProgressMap.size}`);
        
        // [修复] 安全获取最后阅读章节的信息
        logger.debug(TAG, `[DEBUG-11] 开始安全获取最后阅读章节`);
        let lastReadChapter: MangaChapter | null = null;
        if (lastReadChapterIndex >= 0 && lastReadChapterIndex < chapters.length) {
          lastReadChapter = chapters[lastReadChapterIndex];
        }
        let lastReadProgress: ChapterProgressInfo | null = null;
        if (lastReadChapter !== null) {
          const progress = this.chapterProgressMap.get(lastReadChapter.id);
          if (progress !== undefined) {
            lastReadProgress = progress;
          }
        }
        logger.debug(TAG, `[DEBUG-12] 最后阅读章节获取完成: lastReadChapter=${lastReadChapter !== null ? lastReadChapter.id : 'null'}`);
        
        // 更新内容，添加章节
        logger.debug(TAG, `[DEBUG-13] 检查 this.content: ${this.content !== undefined && this.content !== null}`);
        if (this.content) {
          // 获取原始Manga对象以保留genres等元数据
          logger.debug(TAG, `[DEBUG-14] 开始获取原始Manga`);
          const originalManga = MangaAdapter.getOriginalManga(this.content);
          logger.debug(TAG, `[DEBUG-15] 原始Manga获取完成: ${originalManga !== null}`);
          
          logger.debug(TAG, `[DEBUG-16] 开始构建 updatedManga`);
          const updatedManga: Manga = {
            id: this.content.id,
            title: this.content.title,
            alternativeTitles: originalManga?.alternativeTitles || [],
            description: this.content.description,
            coverImagePath: this.content.coverUrl,
            coverSourceType: this.content.isLocal ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
            status: originalManga?.status || MangaStatus.UNKNOWN,
            metadata: {
              authors: this.content.author ? [this.content.author] : [],
              artists: originalManga?.metadata?.artists || [],
              genres: this.content.genres || originalManga?.metadata?.genres || [],
              themes: this.content.tags || originalManga?.metadata?.themes || [],
              demographics: originalManga?.metadata?.demographics || []
            },
            chapters: chapters,
            readingProgress: {
              currentChapterId: lastReadChapter !== null ? lastReadChapter.id : '',
              currentPageIndex: lastReadProgress !== null ? lastReadProgress.lastReadPageIndex : 0,
              lastReadAt: Date.now(),
              readingStatus: readChapterIds.size > 0 ? ReadingStatus.READING : ReadingStatus.UNREAD,
              totalReadingTime: 0,
              readingPercentage: chapters.length > 0 ? Math.round((readChapterIds.size / chapters.length) * 100) : 0
            },
            bookmarks: originalManga?.bookmarks || [],
            readingSettings: originalManga?.readingSettings || DEFAULT_READING_SETTINGS,
            isFavorite: this.isFavorite,
            lastUpdatedAt: Date.now(),
            isNSFW: this.content.isNSFW || false,
            sourceInfo: originalManga?.sourceInfo
          };
          logger.debug(TAG, `[DEBUG-17] updatedManga 构建完成`);
          
          logger.debug(TAG, `[DEBUG-18] 准备调用 toUnifiedContent, 参数: chapters=${chapters.length}, lastReadChapterIndex=${lastReadChapterIndex}`);
          this.content = MangaAdapter.toUnifiedContent(
            updatedManga,
            chapters,
            this.isFavorite,
            readChapterIds,
            downloadedChapterIds,
            bookmarkedChapterIds,
            lastReadChapterIndex,
            sourceId
          );
          logger.debug(TAG, `[DEBUG-19] toUnifiedContent 调用完成`);
          
          logger.info(TAG, `章节进度已更新: 已读${readChapterIds.size}章, 最后阅读章节=${lastReadChapterIndex}`);
        }
        logger.debug(TAG, `[DEBUG-20] onChaptersLoaded 回调执行完成`);
      },
      
      onChapterPagesLoaded: (chapterId: string, pageCount: number) => {
        logger.debug(TAG, `[分阶段] 章节页面已加载: ${chapterId}, ${pageCount}页`);
        // 可以在这里更新章节的页数显示
      },
      
      onPagesPreloadProgress: (current: number, total: number) => {
        this.isPagesPreloading = true;
        this.chaptersLoadProgress = `预加载页面 ${current}/${total}`;
        logger.debug(TAG, `[分阶段] 页面预加载进度: ${current}/${total}`);
      },
      
      onPagesPreloadComplete: () => {
        this.isPagesPreloading = false;
        this.chaptersLoadProgress = '';
        logger.info(TAG, `[分阶段] 页面预加载完成`);
      },
      
      onError: (error: string) => {
        logger.error(TAG, `[分阶段] 加载错误: ${error}`);
        this.errorMessage = error;
        this.isLoading = false;
        this.isChaptersLoading = false;
        this.isCoverLoading = false;
      }
    };

    // 使用分阶段加载
    const result = await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);

    if (!result.success) {
      logger.error(TAG, `漫画加载失败: ${result.errorMessage}`);
      if (!this.isBasicInfoLoaded) {
        this.errorMessage = result.errorMessage || '漫画加载失败';
      }
    } else {
      logger.info(TAG, `漫画内容加载完成: ${this.content?.title}`);
    }
  }

  /**
   * 下拉刷新处理
   */
  private async onRefresh(): Promise<void> {
    if (!this.content || !this.pageParams) {
      this.isRefreshing = false;
      return;
    }
    
    logger.info(TAG, `开始刷新: ${this.content.contentType}`);
    this.isRefreshing = true;
    this.refreshProgress = '正在刷新...';
    
    try {
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaContent();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelContent();
          break;
        case UnifiedContentType.EBOOK:
          // 电子书是本地文件，不需要刷新
          this.refreshProgress = '电子书无需刷新';
          break;
      }
      
      this.refreshProgress = '刷新完成';
      logger.info(TAG, '刷新完成');
    } catch (error) {
      logger.error(TAG, `刷新失败: ${String(error)}`);
      this.refreshProgress = '刷新失败';
    } finally {
      // 延迟关闭刷新状态，让用户看到结果
      setTimeout(() => {
        this.isRefreshing = false;
        this.refreshProgress = '';
      }, 500);
    }
  }
  
  /**
   * 刷新漫画内容（增量更新）
   */
  private async refreshMangaContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    
    // 只有在线漫画才需要刷新
    if (!sourceId || Number(sourceId) <= 0) {
      this.refreshProgress = '本地漫画无需刷新';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    // 设置WebView控制器
    this.mangaDetailLoader.setWebViewController(this.webViewController);
    
    // 构建加载参数，强制刷新
    const loadParams: MangaDetailLoadParams = {
      mangaId: mangaId,
      sourceId: Number(sourceId),
      forceRefresh: true
    };
    
    // 保存当前内容用于增量更新
    const currentChapterCount = this.content.chapters.length;
    const currentChapterIds = new Set(this.content.chapters.map(ch => ch.id));
    
    // 使用分阶段加载刷新
    const progressCallback: MangaLoadProgressCallback = {
      onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
        try {
          this.refreshProgress = '更新基本信息...';
          // 增量更新：只更新有变化的字段
          if (this.content && manga.description && manga.description !== this.content.description) {
            // 更新描述等基本信息
            logger.info(TAG, '更新漫画描述');
          }
        } catch (error) {
          logger.error(TAG, `onBasicInfoLoaded 回调异常: ${String(error)}`);
        }
      },
      
      onChaptersLoaded: (chapters: MangaChapter[]) => {
        try {
          const newChapterCount = chapters.length;
          const addedCount = newChapterCount - currentChapterCount;
          
          if (addedCount > 0) {
            this.refreshProgress = `发现 ${addedCount} 个新章节`;
            logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
          } else {
            this.refreshProgress = '已是最新';
          }
          
          // 更新章节列表
          if (this.content) {
            const readChapterIds = new Set<string>();
            const downloadedChapterIds = new Set<string>();
            const bookmarkedChapterIds = new Set<string>();
            
            // 保留已有的阅读/下载/书签状态
            this.content.chapters.forEach(ch => {
              if (ch.isRead) readChapterIds.add(ch.id);
              if (ch.isDownloaded) downloadedChapterIds.add(ch.id);
              if (ch.isBookmarked) bookmarkedChapterIds.add(ch.id);
            });
            
            // 获取原始Manga对象并更新章节
            const originalManga = MangaAdapter.getOriginalManga(this.content);
            if (originalManga) {
              originalManga.chapters = chapters;
              
              // 确保 lastReadChapterIndex 在有效范围内
              let safeLastReadIndex = this.content.lastReadChapterIndex;
              if (typeof safeLastReadIndex !== 'number' || isNaN(safeLastReadIndex)) {
                safeLastReadIndex = -1;
              } else if (safeLastReadIndex >= chapters.length) {
                // 如果旧的索引超出新章节列表范围，重置为 -1
                safeLastReadIndex = -1;
              }
              
              this.content = MangaAdapter.toUnifiedContent(
                originalManga,
                chapters,
                this.isFavorite,
                readChapterIds,
                downloadedChapterIds,
                bookmarkedChapterIds,
                safeLastReadIndex,
                this.pageParams?.sourceId
              );
            }
          }
        } catch (error) {
          logger.error(TAG, `onChaptersLoaded 回调异常: ${String(error)}`);
        }
      },
      
      onError: (error: string) => {
        this.refreshProgress = `刷新失败: ${error}`;
        logger.error(TAG, `刷新漫画失败: ${error}`);
      }
    };
    
    await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
  }
  
  /**
   * 刷新小说内容（增量更新）
   */
  private async refreshNovelContent(): Promise<void> {
    if (!this.pageParams || !this.content) return;
    
    // [修复] 优先使用content.sourceId和content.id（bookUrl），因为loadNovelContent已经从数据库获取了正确的值
    const sourceId = this.content.sourceId || this.pageParams.sourceId || '';
    const bookUrl = this.content.id || this.pageParams.contentId;
    
    if (!sourceId) {
      this.refreshProgress = '缺少图源信息';
      return;
    }
    
    this.refreshProgress = '获取最新章节...';
    
    try {
      // 获取原始小说数据
      const originalBook = NovelAdapter.getOriginalNovel(this.content);
      if (!originalBook) {
        this.refreshProgress = '无法获取小说数据';
        return;
      }
      
      // 从网络获取最新章节列表（需要传递LegadoBook对象）
      const chapters = await this.novelSourceManager.getChapterList(sourceId, originalBook);
      
      if (!chapters || chapters.length === 0) {
        this.refreshProgress = '获取章节失败';
        return;
      }
      
      const currentChapterCount = this.content.chapters.length;
      const newChapterCount = chapters.length;
      const addedCount = newChapterCount - currentChapterCount;
      
      if (addedCount > 0) {
        this.refreshProgress = `发现 ${addedCount} 个新章节`;
        logger.info(TAG, `刷新发现 ${addedCount} 个新章节`);
      } else {
        this.refreshProgress = '已是最新';
      }
      
      // 获取缓存状态（使用与NovelReaderPage一致的bookId格式）
      const novelCacheBookId = this.getNovelCacheBookId(sourceId, bookUrl);
      const cachedIndexes = new Set<number>();
      for (let i = 0; i < chapters.length; i++) {
        const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
        if (isCached) {
          cachedIndexes.add(i);
        }
      }
      
      // 更新内容
      this.content = NovelAdapter.toUnifiedContent(
        originalBook,
        chapters,
        this.isFavorite,
        cachedIndexes,
        this.content.lastReadChapterIndex,
        sourceId
      );
    } catch (error) {
      this.refreshProgress = `刷新失败: ${String(error)}`;
      logger.error(TAG, `刷新小说失败: ${String(error)}`);
    }
  }

  /**
   * 加载电子书内容
   */
  private async loadEBookContent(): Promise<void> {
    if (!this.pageParams) return;

    const bookId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    logger.info(TAG, `加载电子书内容: bookId=${bookId}, sourceId=${sourceId}`);

    // 判断是在线电子书还是本地电子书
    if (sourceId && sourceId.length > 0) {
      // 在线电子书 - 使用WebView引擎加载
      await this.loadOnlineEBookContent(bookId, sourceId);
    } else {
      // 本地电子书 - 从数据库加载
      await this.loadLocalEBookContent(bookId);
    }
  }

  /**
   * 加载本地电子书内容
   */
  private async loadLocalEBookContent(bookId: string): Promise<void> {
    // 重置加载状态
    this.isChaptersLoading = true;
    this.chaptersLoadProgress = '';
    
    // 获取电子书数据
    const ebook = await this.ebookDataManager.getEBookById(bookId);
    if (!ebook) {
      this.errorMessage = '电子书不存在';
      logger.error(TAG, `电子书不存在: ${bookId}`);
      this.isChaptersLoading = false;
      return;
    }

    logger.info(TAG, `电子书加载成功: ${ebook.metadata?.title}, 章节数: ${ebook.chapters?.length || 0}`);

    // 检查收藏状态
    this.isFavorite = ebook.isFavorite || false;

    // 转换为统一模型
    this.content = EBookAdapter.toUnifiedContent(ebook, this.isFavorite);
    logger.info(TAG, `统一模型转换完成: 章节数=${this.content.totalChapters}`);
    
    // 章节加载完成
    this.isChaptersLoading = false;

    // 检测是否为在线电子书（filePath是JSON格式的扩展数据且id是URL）
    const isOnlineEbook = bookId.startsWith('http://') || bookId.startsWith('https://');
    if (isOnlineEbook && ebook.filePath) {
      try {
        // 尝试从filePath解析扩展数据
        const extendedData = JSON.parse(ebook.filePath) as Record<string, string>;
        const sourceId = extendedData['sourceId'] || '';
        const onlineReaderUrl = extendedData['onlineReaderUrl'] || '';
        
        logger.info(TAG, `检测到在线电子书，sourceId=${sourceId}, onlineReaderUrl=${onlineReaderUrl.substring(0, 50)}...`);
        
        if (onlineReaderUrl) {
          // 直接使用存储的onlineReaderUrl
          this.onlineReaderUrl = onlineReaderUrl;
          logger.info(TAG, `从存储中恢复在线阅读器URL`);
        } else if (sourceId) {
          // 如果没有存储onlineReaderUrl，则重新获取
          this.loadOnlineReaderUrl(bookId, sourceId);
        }
      } catch (e) {
        logger.warn(TAG, `解析在线电子书扩展数据失败: ${e}`);
      }
    }
  }

  /**
   * 加载在线电子书内容
   */
  private async loadOnlineEBookContent(bookId: string, sourceId: string): Promise<void> {
    logger.info(TAG, `加载在线电子书: bookId=${bookId}, sourceId=${sourceId}`);
    
    // 重置加载状态
    this.isBasicInfoLoaded = false;
    this.isCoverLoading = true;
    this.isChaptersLoading = true;
    
    try {
      // 加载图源信息
      const sources = await this.sourceManager.getAllSources();
      this.ebookSourceInfo = sources.find((s: SourceInfo) => s.id === Number(sourceId)) || null;
      
      if (!this.ebookSourceInfo) {
        this.errorMessage = '图源不存在';
        logger.error(TAG, `图源不存在: ${sourceId}`);
        this.isChaptersLoading = false;
        return;
      }
      
      logger.info(TAG, `图源信息加载完成: ${this.ebookSourceInfo.name}`);
      
      // 先设置缓存的基本信息
      const cachedTitle = this.pageParams?.cachedTitle || '未知书名';
      const cachedCover = this.pageParams?.cachedCover || '';
      
      // 创建初始的UnifiedContent
      const emptyGenres: string[] = [];
      const emptyTags: string[] = [];
      const emptyChapters: UnifiedChapter[] = [];
      const emptyOriginalData: Object = new Object();
      const initialContent: UnifiedContent = {
        id: bookId,
        title: cachedTitle,
        coverUrl: cachedCover,
        author: '',
        description: '',
        contentType: UnifiedContentType.EBOOK,
        genres: emptyGenres,
        tags: emptyTags,
        readStatus: UnifiedReadStatus.UNREAD,
        isFavorite: false,
        isNSFW: false,
        totalChapters: 0,
        readChapters: 0,
        lastReadChapterIndex: -1,
        lastReadChapterTitle: '',
        readProgress: 0,
        sourceId: sourceId,
        sourceName: this.ebookSourceInfo.name,
        isLocal: false,
        chapters: emptyChapters,
        originalData: emptyOriginalData,
        originalType: UnifiedContentType.EBOOK
      };
      this.content = initialContent;
      
      this.isBasicInfoLoaded = true;
      this.isCoverLoading = false;
      this.isLoading = false;
      
      // 初始化WebView引擎并获取详情
      await this.initializeEBookWebViewEngine(Number(sourceId));
      
      if (this.ebookSourceEngine && this.ebookWebViewReady) {
        // 使用WebView获取详情
        // 构建完整的URL：如果bookId不是完整路径，需要添加baseUrl
        let fullUrl = bookId;
        if (!bookId.startsWith('http')) {
          // bookId可能是/book/xxx格式或者只是文件名
          if (bookId.startsWith('/')) {
            fullUrl = `${this.ebookSourceInfo?.baseUrl || 'https://zh.chris101.ru'}${bookId}`;
          } else {
            // 尝试从缓存的URL构建
            fullUrl = `${this.ebookSourceInfo?.baseUrl || 'https://zh.chris101.ru'}/${bookId}`;
          }
        }
        logger.info(TAG, `使用WebView获取电子书详情: bookId=${bookId}, fullUrl=${fullUrl}`);
        const result = await this.ebookSourceEngine.getBookDetail(fullUrl);
        
        if (result.success && result.data) {
          const detail = result.data as Record<string, ESObject>;
          logger.info(TAG, `电子书详情获取成功: ${JSON.stringify(detail).substring(0, 200)}`);
          
          // 更新内容
          if (this.content) {
            this.content.title = String(detail['title'] || cachedTitle);
            this.content.author = String(detail['author'] || '');
            this.content.description = String(detail['description'] || '');
            this.content.coverUrl = String(detail['cover'] || cachedCover);
            if (detail['categories']) {
              this.content.genres = [String(detail['categories'])];
            }
            if (detail['tags']) {
              this.content.tags = [String(detail['tags'])];
            }
          }
          
          // 保存在线阅读器URL
          const readerUrlValue: string = String(detail['readerUrl'] || '');
          logger.info(TAG, `readerUrl字段值: ${readerUrlValue.substring(0, 80)}`);
          if (readerUrlValue && readerUrlValue.length > 0) {
            this.onlineReaderUrl = readerUrlValue;
            logger.info(TAG, `获取到在线阅读器URL: ${this.onlineReaderUrl.substring(0, 80)}...`);
          } else {
            logger.warn(TAG, '未获取到在线阅读器URL');
          }
          
          logger.info(TAG, `在线电子书详情加载成功: ${this.content?.title}`);
        } else {
          logger.warn(TAG, `获取电子书详情失败: ${result.error}`);
        }
      } else {
        logger.warn(TAG, 'WebView引擎未就绪，使用缓存数据');
      }
      
      this.isChaptersLoading = false;
      
    } catch (error) {
      logger.error(TAG, `加载在线电子书失败: ${String(error)}`);
      this.errorMessage = `加载失败: ${String(error)}`;
    }
  }

  /**
   * 加载在线阅读器URL（用于已收藏的在线电子书）
   */
  private async loadOnlineReaderUrl(bookId: string, sourceId: string): Promise<void> {
    try {
      // 加载图源信息
      const sources = await this.sourceManager.getAllSources();
      const sourceInfo = sources.find((s: SourceInfo) => s.id === Number(sourceId)) || null;
      
      if (!sourceInfo) {
        logger.warn(TAG, `图源不存在: ${sourceId}`);
        return;
      }

      // 初始化WebView引擎
      await this.initializeEBookWebViewEngine(Number(sourceId));
      
      if (this.ebookWebViewReady && this.ebookSourceEngine) {
        // 获取电子书详情
        const result = await this.ebookSourceEngine.getBookDetail(bookId);
        
        if (result.success && result.data) {
          const detail = result.data as Record<string, ESObject>;
          const readerUrlValue: string = String(detail['readerUrl'] || '');
          if (readerUrlValue && readerUrlValue.length > 0) {
            this.onlineReaderUrl = readerUrlValue;
            logger.info(TAG, `获取到在线阅读器URL: ${this.onlineReaderUrl.substring(0, 80)}...`);
          }
        }
      }
    } catch (error) {
      logger.error(TAG, `加载在线阅读器URL失败: ${String(error)}`);
    }
  }

  /**
   * 初始化电子书WebView引擎
   */
  private async initializeEBookWebViewEngine(sourceId: number): Promise<void> {
    try {
      // 获取图源配置
      const sourceConfig = await this.dataManager.getSourceConfig(sourceId) as Record<string, Object> | null;
      if (!sourceConfig) {
        logger.warn(TAG, '无法获取图源配置');
        return;
      }
      
      // 将配置对象序列化为JSON字符串
      const configJson = JSON.stringify(sourceConfig);
      
      // 初始化WebView引擎
      const engineConfig: EngineConfig = {
        webViewController: this.webViewController,
        antiCrawlerConfig: {} as AntiCrawlerConfig,
        debug: false,
        timeout: 30000,
        caseSensitive: false,
        sourceId: sourceId
      };
      this.ebookSourceEngine = new MangaSourceEngine(engineConfig);
      
      const loadResult = await this.ebookSourceEngine.loadConfig(configJson, true);
      if (!loadResult.success) {
        logger.error(TAG, `加载图源配置失败: ${loadResult.error}`);
        return;
      }
      
      this.ebookWebViewReady = true;
      logger.info(TAG, '电子书WebView引擎初始化成功（跳过initialize工作流）');
    } catch (error) {
      logger.error(TAG, `初始化电子书WebView引擎失败: ${String(error)}`);
    }
  }

  /**
   * 加载小说内容
   */
  private async loadNovelContent(): Promise<void> {
    if (!this.pageParams) return;

    // 重置加载状态
    this.isChaptersLoading = true;
    this.chaptersLoadProgress = '';

    const sourceId = this.pageParams.sourceId || '';
    const bookUrl = this.pageParams.contentId;
    
    logger.debug(TAG, `loadNovelContent: sourceId=${sourceId}, bookUrl=${bookUrl}`);

    // 优先从数据库获取书籍信息（尝试多种查询方式）
    let bookInDb = await this.novelDataManager.getBookByUrl(sourceId, bookUrl);
    
    // 如果按 sourceId + bookUrl 查询不到，尝试直接按 ID 查询
    if (!bookInDb) {
      // 尝试直接用 bookUrl 作为 ID 查询（可能传入的是 novel.id 格式）
      bookInDb = await this.novelDataManager.getBook(bookUrl);
      logger.debug(TAG, `尝试按ID查询: ${bookUrl}, 结果: ${bookInDb ? '找到' : '未找到'}`);
    }
    
    // 如果还是查不到，尝试构建 ID 来查询
    if (!bookInDb && sourceId) {
      const constructedId = `${sourceId}_${bookUrl}`;
      bookInDb = await this.novelDataManager.getBook(constructedId);
      logger.debug(TAG, `尝试按构建ID查询: ${constructedId}, 结果: ${bookInDb ? '找到' : '未找到'}`);
    }
    
    // 重要：如果通过任何方式找到了书籍，使用数据库中的正确 sourceId 和 bookUrl
    // 这确保后续加载章节等操作使用正确的值
    let actualSourceId = sourceId;
    let actualBookUrl = bookUrl;
    if (bookInDb) {
      actualSourceId = bookInDb.sourceId || sourceId;
      actualBookUrl = bookInDb.bookUrl || bookUrl;
      logger.debug(TAG, `使用数据库中的值: sourceId=${actualSourceId}, bookUrl=${actualBookUrl}`);
    }
    
    let book: LegadoBook | null = null;
    let chapters: LegadoChapter[] = [];
    
    // 换源模式：强制从网络加载并保存
    const shouldForceNetworkLoad = this.isFromChangeSource;

    if (bookInDb && !shouldForceNetworkLoad) {
      // 数据库中有书籍信息，尝试从缓存获取章节
      logger.info(TAG, `从数据库加载小说: ${bookInDb.name}`);
      
      // 使用缓存的书籍信息构建LegadoBook
      book = {
        bookUrl: bookInDb.bookUrl,
        name: bookInDb.name,
        author: bookInDb.author,
        kind: bookInDb.kind,
        intro: bookInDb.intro,
        coverUrl: bookInDb.coverUrl,
        tocUrl: bookInDb.tocUrl,
        latestChapterTitle: bookInDb.latestChapterTitle,
        wordCount: bookInDb.wordCount
      } as LegadoBook;

      // 优先从缓存获取章节列表，缓存有效期24小时
      chapters = await this.novelCacheManager.getCachedChapterList(actualBookUrl, 24) || [];
      
      if (chapters.length === 0) {
        // 缓存不存在或已过期，从网络获取
        try {
          chapters = await this.novelSourceManager.getChapterList(actualSourceId, book);
          // 保存章节列表到缓存
          if (chapters.length > 0) {
            await this.novelCacheManager.saveChapterList(actualBookUrl, chapters);
          }
        } catch (error) {
          logger.warn(TAG, `获取章节列表失败: ${String(error)}`);
          chapters = [];
        }
      }
    } else {
      // 数据库中没有（或换源模式强制从网络加载）
      // 换源模式下使用原始sourceId（不是actualSourceId）
      const loadSourceId = shouldForceNetworkLoad ? sourceId : actualSourceId;
      const loadBookUrl = shouldForceNetworkLoad ? bookUrl : actualBookUrl;
      
      logger.info(TAG, `从网络加载小说: ${loadBookUrl}, 换源模式=${shouldForceNetworkLoad}`);
      book = await this.novelSourceManager.getBookInfo(loadSourceId, loadBookUrl);
      if (!book) {
        this.errorMessage = '小说不存在';
        this.isChaptersLoading = false;
        return;
      }

      // 获取章节列表
      try {
        chapters = await this.novelSourceManager.getChapterList(loadSourceId, book);
        // 保存章节列表到缓存（避免下次重新加载）
        if (chapters.length > 0) {
          await this.novelCacheManager.saveChapterList(loadBookUrl, chapters);
        }
      } catch (error) {
        logger.warn(TAG, `获取章节列表失败: ${String(error)}`);
        chapters = [];
      }
      
      // 获取书源名称
      let sourceName = '';
      try {
        const sourceInfo: LegadoBookSource | null = this.novelSourceManager.getSource(loadSourceId);
        sourceName = sourceInfo?.bookSourceName || '';
      } catch (e) {
        logger.warn(TAG, `获取书源名称失败: ${String(e)}`);
      }

      // 保存小说信息到数据库（持久化缓存）
      try {
        const novelBook: NovelBook = {
          id: `${loadSourceId}_${book.bookUrl}`,
          sourceId: loadSourceId,
          sourceName: sourceName,
          bookUrl: book.bookUrl,
          name: book.name || '未知书名',
          author: book.author || '未知作者',
          kind: book.kind,
          intro: book.intro,
          coverUrl: book.coverUrl,
          tocUrl: book.tocUrl,
          latestChapterTitle: book.latestChapterTitle,
          wordCount: book.wordCount,
          chapterCount: chapters.length,
          readStatus: NovelReadStatus.UNREAD,
          totalReadingTime: 0,
          isFavorite: false,
          createTime: Date.now(),
          updateDbTime: Date.now()
        };
        await this.novelDataManager.saveBook(novelBook);
        logger.info(TAG, `小说信息已保存到数据库: ${book.name}, 书源: ${sourceName}`);
        // 更新bookInDb引用
        bookInDb = novelBook;
        
        // 换源模式下更新actualSourceId和actualBookUrl
        if (shouldForceNetworkLoad) {
          actualSourceId = loadSourceId;
          actualBookUrl = loadBookUrl;
        }
      } catch (error) {
        logger.warn(TAG, `保存小说信息失败: ${String(error)}`);
      }
    }

    // 获取缓存状态（使用与NovelReaderPage一致的bookId格式）
    const novelCacheBookId = this.getNovelCacheBookId(actualSourceId, actualBookUrl);
    const cachedIndexes = new Set<number>();
    for (let i = 0; i < chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
      if (isCached) {
        cachedIndexes.add(i);
      }
    }

    // 获取阅读进度（使用之前已查询的bookInDb）
    const lastReadIndex = bookInDb?.lastReadChapterIndex || -1;

    // 检查收藏状态
    this.isFavorite = bookInDb?.isFavorite || false;

    // 转换为统一模型
    this.content = NovelAdapter.toUnifiedContent(
      book,
      chapters,
      this.isFavorite,
      cachedIndexes,
      lastReadIndex,
      actualSourceId
    );
    
    // 章节加载完成
    this.isChaptersLoading = false;
  }

  /**
   * 开始阅读
   */
  private startReading(chapterIndex: number): void {
    if (!this.content || !this.pageParams) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        this.openMangaReader(chapterIndex);
        break;
      case UnifiedContentType.EBOOK:
        this.openEBookReader(chapterIndex);
        break;
      case UnifiedContentType.NOVEL:
        this.openNovelReader(chapterIndex);
        break;
    }
  }

  /**
   * 继续阅读
   */
  private continueReading(): void {
    if (!this.content) return;

    logger.info(TAG, `continueReading: contentType=${this.content.contentType}, onlineReaderUrl=${this.onlineReaderUrl ? this.onlineReaderUrl.substring(0, 50) + '...' : 'null'}, sourceId=${this.content.sourceId}`);

    // 电子书特殊处理
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      // 在线电子书：如果有在线阅读器URL，跳转到ZLibraryReaderPage
      if (this.onlineReaderUrl) {
        logger.info(TAG, '使用在线阅读器');
        this.openOnlineEBookReader();
        return;
      }
      // 本地电子书：直接打开阅读器
      logger.info(TAG, '使用本地电子书阅读器');
      this.openEBookReader(0);
      return;
    }

    const lastIndex = this.content.lastReadChapterIndex;
    if (lastIndex >= 0 && lastIndex < this.content.chapters.length) {
      this.startReading(lastIndex);
    } else {
      // 从第一章开始
      this.startReading(0);
    }
  }

  /**
   * 继续听书（仅小说）
   */
  private continueReadAloud(): void {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) return;

    const lastIndex = this.content.lastReadChapterIndex;
    if (lastIndex >= 0 && lastIndex < this.content.chapters.length) {
      this.openNovelReadAloudPage(lastIndex);
    } else {
      this.openNovelReadAloudPage(0);
    }
  }

  /**
   * 打开在线电子书阅读器（ZLibrary等）
   */
  private openOnlineEBookReader(): void {
    if (!this.content || !this.onlineReaderUrl) return;

    logger.info(TAG, `打开在线电子书阅读器: ${this.content.title}, URL: ${this.onlineReaderUrl.substring(0, 50)}...`);

    const params: ZLibraryReaderParams = {
      readerUrl: this.onlineReaderUrl,
      bookTitle: this.content.title,
      sourceId: this.content.sourceId || ''
    };

    this.pathStack.pushPathByName('ZLibraryReaderPage', params);
  }

  /**
   * 打开漫画阅读器
   */
  private openMangaReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    
    // 获取原始Manga对象
    const originalManga = MangaAdapter.getOriginalManga(this.content);
    
    // 构建阅读器参数（参考MangaDetailPage的实现）
    const readerParams: MangaReaderPageParams = {
      fromPage: 'UnifiedDetailPage'
    } as MangaReaderPageParams;
    
    // 判断是否为在线漫画
    const hasSourceId = this.content.sourceId && Number(this.content.sourceId) > 0;
    
    if (hasSourceId && originalManga) {
      // 在线漫画：传递完整的manga对象和sourceId
      readerParams.manga = originalManga;
      readerParams.sourceId = Number(this.content.sourceId);
      readerParams.mangaId = this.content.id;
      readerParams.sourceName = this.content.sourceName || '';
      
      // 判断章节是否已下载
      const isDownloaded = chapter.isDownloaded || false;
      readerParams.contentType = isDownloaded ? MangaReaderContentType.OnlineDownloaded : MangaReaderContentType.OnlineUndownloaded;
      
      // 对于WebView图源，需要传递外部章节ID
      const originalChapter = originalManga.chapters.find(ch => ch.id === chapter.id);
      if (originalChapter?.externalId) {
        readerParams.chapterId = originalChapter.externalId;
        logger.info(TAG, `转换章节ID: 内部ID=${chapter.id} -> 外部ID=${originalChapter.externalId}`);
      } else {
        readerParams.chapterId = chapter.id;
      }
      
      logger.info(TAG, `在线漫画阅读: sourceId=${readerParams.sourceId}, mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    } else {
      // 本地漫画：不传递manga对象，让MangaReaderPage从数据库加载完整的章节和页面信息
      readerParams.mangaId = this.content.id;
      readerParams.chapterId = chapter.id;
      readerParams.contentType = MangaReaderContentType.Local;
      readerParams.sourceName = 'LOCAL';
      // 注意：不传递manga对象，因为传递的manga对象中章节的pages数组可能为空
      // MangaReaderPage会通过mangaId从数据库加载完整的章节和页面信息
      logger.info(TAG, `本地漫画阅读: mangaId=${readerParams.mangaId}, chapterId=${readerParams.chapterId}`);
    }
    
    // [修复] 使用章节阅读进度中的页码，而不是总是从第一页开始
    const chapterProgress = this.chapterProgressMap.get(chapter.id);
    readerParams.pageIndex = chapterProgress ? chapterProgress.lastReadPageIndex : 0;
    logger.info(TAG, `阅读页码: chapterId=${chapter.id}, pageIndex=${readerParams.pageIndex} (来源: ${chapterProgress ? 'chapterProgressMap' : '默认'})`);

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    
    logger.info(TAG, `触发漫画翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'manga',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '漫画翻开过渡动画触发导航');
        this.pathStack.pushPathByName('MangaReaderPage', readerParams);
      }
    );
  }

  /**
   * 打开电子书阅读器
   */
  private openEBookReader(chapterIndex: number): void {
    if (!this.content) return;

    // EBookReaderParams只需要bookId，章节索引通过阅读进度恢复
    const params: EBookReaderParams = {
      bookId: this.content.id
    };

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    
    logger.info(TAG, `触发电子书翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'ebook',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '电子书翻开过渡动画触发导航');
        this.pathStack.pushPathByName('EBookReaderPage', params);
      }
    );
  }

  /**
   * 打开小说阅读器
   */
  private openNovelReader(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    // 获取原始小说章节数据
    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    const originalBook = NovelAdapter.getOriginalNovel(this.content);

    const params: NovelReaderPageParams = {
      sourceId: this.content.sourceId || '',
      bookUrl: this.content.id,
      bookName: this.content.title,
      chapterUrl: originalChapter?.url || '',
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      totalChapters: this.content.totalChapters,
      tocUrl: originalBook?.tocUrl,
      author: this.content.author,
      coverUrl: this.content.coverUrl
    };

    // 触发翻开过渡动画
    // 优先使用本地缓存的封面路径（可直接加载PixelMap），回退到网络URL
    const coverPath: string = this.localCoverPath || this.content.coverUrl || '';
    const coverComponentId: string = `cover_${this.componentId}`;
    
    logger.info(TAG, `触发小说翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      this.content.id,
      'novel',
      () => {
        // 动画完成时触发导航
        logger.info(TAG, '小说翻开过渡动画触发导航');
        this.pathStack.pushPathByName('NovelReaderPage', params);
      }
    );
  }

  /**
   * 打开小说听书播放器（通过阅读器初始化上下文后自动跳转播放器页）
   */
  private openNovelReadAloudPage(chapterIndex: number): void {
    if (!this.content) return;

    const chapter = this.content.chapters[chapterIndex];
    if (!chapter) return;

    const originalChapter = NovelAdapter.getOriginalChapter(chapter);
    const originalBook = NovelAdapter.getOriginalNovel(this.content);

    const params: NovelReaderPageParams = {
      sourceId: this.content.sourceId || '',
      bookUrl: this.content.id,
      bookName: this.content.title,
      chapterUrl: originalChapter?.url || '',
      chapterTitle: chapter.title,
      chapterIndex: chapterIndex,
      totalChapters: this.content.totalChapters,
      tocUrl: originalBook?.tocUrl,
      author: this.content.author,
      coverUrl: this.content.coverUrl,
      autoStartReadAloud: true,
      autoOpenReadAloudPlayer: true
    };

    this.pathStack.pushPathByName('NovelReaderPage', params);
  }

  /**
   * 切换收藏状态
   */
  private async toggleFavorite(): Promise<void> {
    if (!this.content) return;

    try {
      this.isFavorite = !this.isFavorite;

      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          // 漫画收藏通过DataService处理
          const dataService = DataService.getInstance();
          if (this.isFavorite) {
            await dataService.addToFavorites(this.content.id);
          } else {
            await dataService.removeFromFavorites(this.content.id);
          }
          logger.info(TAG, `漫画收藏状态切换: ${this.isFavorite}`);
          break;
        case UnifiedContentType.EBOOK:
          // 电子书收藏需要重新保存整个对象
          const ebook = EBookAdapter.getOriginalEBook(this.content);
          // 检查是否是有效的本地电子书（有metadata属性）
          if (ebook && ebook.metadata) {
            ebook.isFavorite = this.isFavorite;
            await this.ebookDataManager.saveEBook(ebook);
          } else if (this.isFavorite && this.content.sourceId) {
            // 在线电子书：创建新的EBook对象并保存
            const now = Date.now();
            const metadata: EBookMetadata = {
              title: this.content.title,
              author: this.content.author,
              publisher: '',
              publishDate: '',
              isbn: '',
              language: '',
              description: this.content.description,
              coverImagePath: this.content.coverUrl,
              tags: this.content.tags || [],
              rating: 0
            };
            const emptyChapters: EBookChapter[] = [];
            logger.info(TAG, `创建在线电子书: id=${this.content.id}, title=${metadata.title}`);
            // 将sourceId和onlineReaderUrl存储在filePath字段中（JSON格式）
            const extendedDataMap = new Map<string, string>();
            extendedDataMap.set('sourceId', this.content.sourceId || '');
            extendedDataMap.set('sourceName', this.content.sourceName || '');
            extendedDataMap.set('onlineReaderUrl', this.onlineReaderUrl || '');
            const extendedDataObj: Record<string, string> = {};
            extendedDataMap.forEach((value: string, key: string) => {
              extendedDataObj[key] = value;
            });
            const extendedDataJson = JSON.stringify(extendedDataObj);
            // 直接创建EBook对象并手动设置所有属性
            const onlineEbook = new EBook(
              this.content.id,
              EBookFormat.EPUB,
              extendedDataJson,  // 使用filePath存储扩展数据
              0,
              metadata,
              emptyChapters
            );
            // 手动设置所有属性确保正确
            onlineEbook.metadata = metadata;
            onlineEbook.status = EBookStatus.UNREAD;
            onlineEbook.addTime = now;
            onlineEbook.lastUpdateTime = now;
            onlineEbook.isFavorite = true;
            onlineEbook.totalWordCount = 0;
            onlineEbook.isPrivate = false;
            onlineEbook.isNSFW = this.content.isNSFW || false;
            logger.info(TAG, `保存前检查: metadata.title=${onlineEbook.metadata?.title}`);
            await this.ebookDataManager.saveEBook(onlineEbook);
            logger.info(TAG, `在线电子书已添加到书库: ${this.content.title}`);
          }
          break;
        case UnifiedContentType.NOVEL:
          // 小说收藏通过saveBook更新isFavorite字段
          const novelBook = await this.novelDataManager.getBookByUrl(this.content.sourceId || '', this.content.id);
          if (novelBook) {
            novelBook.isFavorite = this.isFavorite;
            await this.novelDataManager.saveBook(novelBook);
          } else if (this.isFavorite) {
            // 如果书籍不存在且要收藏，需要先创建
            const now = Date.now();
            const newBook: NovelBook = {
              id: '',
              sourceId: this.content.sourceId || '',
              sourceName: this.content.sourceName || '',
              bookUrl: this.content.id,
              name: this.content.title,
              author: this.content.author,
              intro: this.content.description,
              coverUrl: this.content.coverUrl,
              chapterCount: this.content.totalChapters,
              readStatus: NovelReadStatus.UNREAD,
              totalReadingTime: 0,
              isFavorite: true,
              createTime: now,
              updateDbTime: now
            };
            await this.novelDataManager.saveBook(newBook);
          }
          break;
      }

      promptAction.showToast({
        message: this.isFavorite ? '已添加到收藏' : '已取消收藏',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, '切换收藏状态失败', String(error));
      this.isFavorite = !this.isFavorite; // 回滚
      promptAction.showToast({
        message: '操作失败',
        duration: 1500
      });
    }
  }

  /**
   * 获取过滤后的章节列表
   */
  private getFilteredChapters(): UnifiedChapter[] {
    if (!this.content) return [];

    let chapters = [...this.content.chapters];

    // 应用过滤
    switch (this.chapterFilter) {
      case ChapterFilterType.UNREAD:
        chapters = chapters.filter(c => !c.isRead);
        break;
      case ChapterFilterType.DOWNLOADED:
        chapters = chapters.filter(c => c.isDownloaded);
        break;
      case ChapterFilterType.BOOKMARKED:
        chapters = chapters.filter(c => c.isBookmarked);
        break;
    }

    // 应用排序
    if (this.chapterSortOrder === ChapterSortOrder.DESCENDING) {
      chapters.reverse();
    }

    return chapters;
  }

  /**
   * 获取内容类型显示名称
   * 对于在线漫画显示"在线漫画"，本地漫画显示"本地漫画"
   */
  private getContentTypeName(): string {
    if (!this.content) return '';
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        // 判断是否为在线漫画
        if (this.isOnlineManga()) {
          return '在线漫画';
        }
        return '本地漫画';
      case UnifiedContentType.EBOOK:
        return this.content.isLocal ? '本地电子书' : '在线电子书';
      case UnifiedContentType.NOVEL:
        return '小说';
      default:
        return '';
    }
  }
  
  /**
   * 判断当前内容是否为在线漫画
   */
  private isOnlineManga(): boolean {
    if (!this.content || this.content.contentType !== UnifiedContentType.MANGA) {
      return false;
    }
    // 有sourceId且大于0表示在线漫画
    const sourceId = this.pageParams?.sourceId;
    return sourceId !== undefined && sourceId !== '' && Number(sourceId) > 0;
  }
  
  /**
   * 判断当前内容是否为在线内容（在线漫画或小说）
   * 用于决定是否显示下载按钮
   */
  private isOnlineContent(): boolean {
    if (!this.content) return false;
    
    // 在线漫画
    if (this.content.contentType === UnifiedContentType.MANGA) {
      return this.isOnlineManga();
    }
    
    // 小说始终被视为在线内容（因为小说来源于书源）
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      return true;
    }
    
    // 电子书：根据 isLocal 判断
    if (this.content.contentType === UnifiedContentType.EBOOK) {
      return !this.content.isLocal;
    }
    
    return false;
  }
  
  /**
   * 创建图片列表获取函数
   * 用于漫画下载时延迟获取图片URL列表
   */
  private createPageListFetcher(): PageListFetcher {
    const dataManager = this.dataManager;
    const fetcher: PageListFetcher = async (chapterId: string, mangaId: string): Promise<string[]> => {
      const pages = await dataManager.getOnlineChapterPages(chapterId);
      return pages.map(p => p.imageUrl);
    };
    return fetcher;
  }
  
  /**
   * 加载封面（在线漫画）
   * 优先级：
   * 1. CoverCacheManager 磁盘缓存（最快）
   * 2. CoverImageManager 内存缓存（快）
   * 3. 触发 CoverImageManager 预加载
   */
  private async loadCachedCover(sourceId: number, externalId: string): Promise<void> {
    try {
      // 1. 尝试从 CoverCacheManager 获取本地磁盘缓存
      const coverCache = CoverCacheManager.getInstance();
      const localPath = await coverCache.getLocalCoverPath(sourceId, externalId);
      
      if (localPath) {
        logger.info(TAG, `找到本地磁盘缓存封面: ${localPath}`);
        
        // 使用 PixelMap 加载封面
        const imageSource = image.createImageSource(localPath);
        const pixelMap = await imageSource.createPixelMap({ 
          desiredSize: { width: COVER_WIDTH * 2, height: COVER_HEIGHT * 2 } 
        });
        imageSource.release();
        
        if (pixelMap) {
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = pixelMap;
          this.coverPixelMapOwned = true;  // 我们拥有这个 PixelMap
          this.localCoverPath = localPath;
          logger.info(TAG, `封面 PixelMap 加载成功（磁盘缓存）`);
          return;
        }
      }
      
      // 2. 尝试从 CoverImageManager 获取内存缓存或预加载
      const coverUrl = this.content?.coverUrl || '';
      if (coverUrl && (coverUrl.startsWith('http://') || coverUrl.startsWith('https://'))) {
        const coverImageManager = getCoverImageManager();
        
        // 先检查内存缓存
        let cachedPixelMap = coverImageManager.getCachedPixelMap(coverUrl);
        if (cachedPixelMap) {
          logger.info(TAG, `找到内存缓存封面`);
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = cachedPixelMap;
          this.coverPixelMapOwned = false;  // 从 CoverImageManager 借用，不拥有所有权
          return;
        }
        
        // 触发预加载
        logger.info(TAG, `触发封面预加载: ${coverUrl.substring(0, 50)}...`);
        const preloadedPixelMap = await coverImageManager.preloadCover(coverUrl);
        if (preloadedPixelMap) {
          if (this.coverPixelMap && this.coverPixelMapOwned) {
            this.coverPixelMap.release();
          }
          this.coverPixelMap = preloadedPixelMap;
          this.coverPixelMapOwned = false;  // 从 CoverImageManager 借用，不拥有所有权
          logger.info(TAG, `封面预加载成功`);
        } else {
          logger.warn(TAG, `封面预加载失败，将回退到 AvifImage 组件`);
        }
      } else {
        logger.debug(TAG, `未找到本地缓存封面且无网络 URL: sourceId=${sourceId}, externalId=${externalId}`);
      }
    } catch (error) {
      logger.warn(TAG, `加载封面失败: ${String(error)}`);
    }
  }
  
  /**
   * 加载缓存状态信息
   * 对于在线漫画和小说，检查并加载缓存状态
   */
  private async loadCacheStatus(): Promise<void> {
    if (!this.content || !this.pageParams) return;
    
    try {
      // 判断是否需要显示缓存卡片
      const isOnline = this.isOnlineManga();
      const isNovel = this.content.contentType === UnifiedContentType.NOVEL;
      
      // 只有在线漫画和小说需要显示缓存状态
      if (!isOnline && !isNovel) {
        this.showCacheStatusCard = false;
        return;
      }
      
      this.isCacheStatsLoading = true;
      
      if (isOnline) {
        // 在线漫画：检查边看边下载是否开启
        const sourceId = Number(this.pageParams.sourceId);
        const downloadWhileReadingEnabled = await this.cacheStatusService.isDownloadWhileReadingEnabled(sourceId);
        
        if (downloadWhileReadingEnabled) {
          // 加载漫画缓存状态
          this.cacheStats = await this.cacheStatusService.getMangaCacheStatus(
            sourceId,
            this.content.id,
            this.content.title
          );
          this.showCacheStatusCard = true;
          logger.info(TAG, `漫画缓存状态加载完成: ${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}章`);
        } else {
          // 边看边下载未开启，不显示缓存卡片
          this.showCacheStatusCard = false;
          this.cacheStats = null;
        }
      } else if (isNovel) {
        // 小说：始终加载并显示缓存状态（使用与NovelReaderPage一致的bookId格式）
        // [修复] 优先使用content.sourceId，因为loadNovelContent已经从数据库获取了正确的sourceId
        const sourceId = this.content.sourceId || this.pageParams?.sourceId || '';
        const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
        this.cacheStats = await this.cacheStatusService.getNovelCacheStatus(
          novelCacheBookId,
          this.content.title,
          this.content.totalChapters
        );
        // 小说始终显示缓存卡片，方便用户了解缓存情况和进行下载操作
        this.showCacheStatusCard = true;
        logger.info(TAG, `小说缓存状态加载完成: ${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}章`);
      }
    } catch (error) {
      logger.error(TAG, `加载缓存状态失败: ${String(error)}`);
      this.showCacheStatusCard = false;
      this.cacheStats = null;
    } finally {
      this.isCacheStatsLoading = false;
    }
  }

  /**
   * 获取阅读状态显示文本
   */
  private getReadStatusText(): string {
    if (!this.content) return '';
    switch (this.content.readStatus) {
      case UnifiedReadStatus.UNREAD:
        return '未读';
      case UnifiedReadStatus.READING:
        return `阅读中 ${this.content.readProgress}%`;
      case UnifiedReadStatus.COMPLETED:
        return '已读完';
      default:
        return '';
    }
  }

  // ==================== 快捷搜索功能 ====================
  
  /**
   * 复制文本到剪贴板
   */
  private copyToClipboard(text: string): void {
    try {
      const cleanText = this.stripHtmlTags(text).trim();
      if (!cleanText) return;
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cleanText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `复制到剪贴板失败: ${String(error)}`);
      promptAction.showToast({ message: '复制失败', duration: 1500 });
    }
  }
  
  /**
   * 导航到全局搜索页面
   * 根据当前内容类型自动设置搜索范围：
   * - 漫画：仅搜索已开启的图源+本地漫画
   * - 小说：仅搜索已开启的书源+本地小说
   * - 电子书：仅搜索本地内容
   */
  private navigateToSearch(keyword: string): void {
    if (!keyword || keyword.trim() === '') return;
    
    const cleanKeyword = this.stripHtmlTags(keyword).trim();
    if (!cleanKeyword) return;
    
    // 根据当前内容类型确定搜索范围
    let initialContentType: string = 'all';
    let initialSourceType: string = 'all';
    
    if (this.content) {
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          // 漫画：搜索漫画类型，本地+已开启图源
          initialContentType = 'manga';
          initialSourceType = 'all';
          break;
        case UnifiedContentType.NOVEL:
          // 小说：搜索小说类型，本地+已开启书源
          initialContentType = 'novel';
          initialSourceType = 'all';
          break;
        case UnifiedContentType.EBOOK:
          // 电子书：仅搜索本地内容
          initialContentType = 'all';
          initialSourceType = 'local';
          break;
      }
    }
    
    const params: GlobalSearchPageParams = {
      initialKeyword: cleanKeyword,
      initialContentType: initialContentType,
      initialSourceType: initialSourceType,
      autoSelectAllSources: initialSourceType !== 'local'  // 非纯本地搜索时自动选中所有已开启源
    };
    
    logger.info(TAG, `快捷搜索: keyword="${cleanKeyword}", contentType=${initialContentType}, sourceType=${initialSourceType}`);
    this.pathStack.pushPathByName('GlobalSearchPage', params);
  }

  // ==================== 智能推荐功能 ====================

  /**
   * 判断当前内容是否应使用在线推荐（搜索图源）
   * 小说始终使用本地推荐（在数据库中搜索），因为小说数据本地化存储
   * 在线漫画 / 在线电子书 使用图源搜索
   */
  private shouldUseOnlineRecommendation(): boolean {
    if (!this.content) return false;
    if (this.content.contentType === UnifiedContentType.NOVEL) return false;
    return this.isOnlineContent();
  }

  /**
   * 拆分多作者字符串
   * 支持中文/日文/英文常见分隔符：，、·/&,；×xX 及空格
   */
  private splitAuthorNames(authorStr: string): string[] {
    if (!authorStr || !authorStr.trim()) return [];
    return authorStr
      .split(/[，、·\/&,；\s×xX]+/)
      .map((a: string) => a.trim())
      .filter((a: string) => a.length > 0);
  }

  /**
   * 计算字符串 bigram 集合（用于相似度计算）
   */
  private computeBigramSet(text: string): string[] {
    if (!text || text.length < 2) return text.length === 1 ? [text] : [];
    const bigrams: string[] = [];
    for (let i = 0; i < text.length - 1; i++) {
      bigrams.push(text.substring(i, i + 2));
    }
    return bigrams;
  }

  /**
   * Bigram Jaccard 相似度（0~1）
   * 用于估算两个字符串的相关程度
   */
  private bigramJaccard(a: string, b: string): number {
    if (!a || !b) return 0;
    if (a === b) return 1;
    const bigramsA = this.computeBigramSet(a);
    const bigramsB = this.computeBigramSet(b);
    if (bigramsA.length === 0 || bigramsB.length === 0) return 0;
    const setB = new Set<string>(bigramsB);
    let intersection = 0;
    for (let i = 0; i < bigramsA.length; i++) {
      if (setB.has(bigramsA[i])) intersection++;
    }
    const union = bigramsA.length + bigramsB.length - intersection;
    return union > 0 ? intersection / union : 0;
  }

  /**
   * 计算候选内容与当前内容的综合相关度评分
   * 标题（权重3）> 作者（权重2）> 标签（每个 10 分，上限 30）
   */
  private calculateRelevanceScore(
    currentTitle: string,
    currentAuthor: string,
    currentTags: string[],
    candidateTitle: string,
    candidateAuthor: string,
    candidateTags: string[]
  ): number {
    let score = 0;

    // 标题相似度（权重 3）
    const titleSim = this.bigramJaccard(currentTitle, candidateTitle);
    score += titleSim * 100 * 3;

    // 作者匹配（权重 2）
    if (currentAuthor && candidateAuthor) {
      if (currentAuthor === candidateAuthor) {
        score += 80 * 2;
      } else if (currentAuthor.includes(candidateAuthor) || candidateAuthor.includes(currentAuthor)) {
        score += 40 * 2;
      }
    }

    // 标签重叠（每个 10 分，上限 30）
    if (currentTags.length > 0 && candidateTags.length > 0) {
      let tagMatches = 0;
      for (let i = 0; i < currentTags.length; i++) {
        if (candidateTags.indexOf(currentTags[i]) >= 0) tagMatches++;
      }
      score += Math.min(tagMatches * 10, 30);
    }

    return Math.round(score);
  }

  /**
   * 触发智能推荐加载（内容加载完成后调用）
   */
  private async loadRecommendations(): Promise<void> {
    if (!this.content) return;

    this.isLoadingRecommendations = true;
    this.recommendedItems = [];

    try {
      if (this.shouldUseOnlineRecommendation()) {
        await this.loadOnlineRecommendations();
      } else {
        await this.loadLocalRecommendations();
      }
    } catch (error) {
      logger.warn(TAG, `智能推荐加载失败: ${String(error)}`);
    } finally {
      this.isLoadingRecommendations = false;
    }
  }

  /**
   * 本地推荐：在本地数据库中搜索相关内容并按相关度排序
   * 覆盖本地漫画、本地电子书、数据库中的小说
   */
  private async loadLocalRecommendations(): Promise<void> {
    if (!this.content) return;

    const currentId = this.content.id;
    const currentTitle = this.stripHtmlTags(this.content.title || '').toLowerCase().trim();
    const currentAuthor = this.stripHtmlTags(this.content.author || '').toLowerCase().trim();
    const currentGenres = (this.content.genres || []).map((g: string) => this.stripHtmlTags(g).toLowerCase().trim());
    const currentTags = (this.content.tags || []).map((t: string) => this.stripHtmlTags(t).toLowerCase().trim());
    const allCurrentTags: string[] = [...currentGenres, ...currentTags].filter((t: string) => t.length > 0);

    const candidates: RecommendationItem[] = [];

    // ---- 查询本地漫画 ----
    // [性能优化] 使用 SQL LIKE 预过滤，缩小候选集
    try {
      const comics = await this.dataManager.getRecommendationCandidateComics(currentAuthor, allCurrentTags);
      for (let ci = 0; ci < comics.length; ci++) {
        const comic = comics[ci];
        if (comic.id === currentId) continue;
        const cTitle = (comic.title || '').toLowerCase().trim();
        const cAuthor = (comic.author || '').toLowerCase().trim();
        const cTags = (comic.tags || []).map((t: string) => t.toLowerCase().trim());
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const coverUrl = comic.coverLocalPath || comic.coverUrl || '';
          const item: RecommendationItem = {
            id: `rec_manga_${comic.id}`,
            title: comic.title || '未知标题',
            coverUrl: coverUrl,
            contentType: UnifiedContentType.MANGA,
            isLocal: true,
            score: score,
            navContentId: comic.id
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `本地漫画推荐查询失败: ${String(e)}`);
    }

    // ---- 查询本地电子书 ----
    try {
      const ebooks = await this.ebookDataManager.getNonPrivateEBooks();
      for (let ei = 0; ei < ebooks.length; ei++) {
        const ebook = ebooks[ei];
        if (!ebook.metadata) continue;
        if (ebook.id === currentId) continue;
        const cTitle = (ebook.metadata.title || '').toLowerCase().trim();
        const cAuthor = (ebook.metadata.author || '').toLowerCase().trim();
        const cTags = (ebook.metadata.tags || []).map((t: string) => t.toLowerCase().trim());
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const item: RecommendationItem = {
            id: `rec_ebook_${ebook.id}`,
            title: ebook.metadata.title || '未知标题',
            coverUrl: ebook.metadata.coverImagePath || '',
            contentType: UnifiedContentType.EBOOK,
            isLocal: true,
            score: score,
            navContentId: ebook.id
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `本地电子书推荐查询失败: ${String(e)}`);
    }

    // ---- 查询数据库中的小说 ----
    try {
      const novels = await this.novelDataManager.getNonPrivateBooks();
      for (let ni = 0; ni < novels.length; ni++) {
        const novel = novels[ni];
        if (novel.bookUrl === currentId || novel.id === currentId) continue;
        const cTitle = (novel.name || '').toLowerCase().trim();
        const cAuthor = (novel.author || '').toLowerCase().trim();
        // kind 字段存放分类/标签，按逗号等分隔
        const cTags = (novel.kind || '')
          .split(/[,，、\s]+/)
          .map((t: string) => t.trim().toLowerCase())
          .filter((t: string) => t.length > 0);
        const score = this.calculateRelevanceScore(currentTitle, currentAuthor, allCurrentTags, cTitle, cAuthor, cTags);
        if (score >= RECOMMEND_MIN_SCORE) {
          const item: RecommendationItem = {
            id: `rec_novel_${novel.id}`,
            title: novel.name || '未知标题',
            coverUrl: novel.coverUrl || '',
            contentType: UnifiedContentType.NOVEL,
            isLocal: false,
            sourceName: novel.sourceName,
            score: score,
            navContentId: novel.bookUrl,
            navSourceId: novel.sourceId
          };
          candidates.push(item);
        }
      }
    } catch (e) {
      logger.warn(TAG, `小说推荐查询失败: ${String(e)}`);
    }

    // 按相关度降序排列，取前 RECOMMEND_MAX_COUNT 条
    candidates.sort((a: RecommendationItem, b: RecommendationItem) => b.score - a.score);
    this.recommendedItems = candidates.slice(0, RECOMMEND_MAX_COUNT);
    logger.info(TAG, `本地推荐加载完成: ${this.recommendedItems.length} 条`);
  }

  /**
   * 在线推荐：使用当前内容的作者名在同图源搜索
   * 适用于在线漫画、在线电子书
   */
  private async loadOnlineRecommendations(): Promise<void> {
    if (!this.content) return;

    const authorStr = this.stripHtmlTags(this.content.author || '').trim();
    if (!authorStr) {
      logger.info(TAG, '在线推荐: 无作者信息，跳过');
      return;
    }

    // 拆分多作者，取第一个作为搜索关键词
    const authors = this.splitAuthorNames(authorStr);
    if (authors.length === 0) return;
    const searchKeyword = authors[0];

    const sourceIdNum = this.content.sourceId ? Number(this.content.sourceId) : 0;
    if (!sourceIdNum || sourceIdNum <= 0) return;

    const currentContentId = this.content.id;
    const results: RecommendationItem[] = [];
    const seenIds = new Set<string>();
    seenIds.add(currentContentId);

    try {
      logger.info(TAG, `在线推荐搜索: sourceId=${sourceIdNum}, keyword="${searchKeyword}"`);
      const globalSearch = GlobalSearchService.getInstance();
      const searchItems = await globalSearch.searchOnlineManga(sourceIdNum, searchKeyword);

      for (let si = 0; si < searchItems.length; si++) {
        if (results.length >= RECOMMEND_MAX_COUNT) break;
        const item = searchItems[si];
        const comic = item.rawOnlineComic;
        if (!comic) continue;
        const comicId = comic.id || comic.url || '';
        if (!comicId || seenIds.has(comicId)) continue;
        seenIds.add(comicId);

        const recItem: RecommendationItem = {
          id: `rec_online_${sourceIdNum}_${comicId}`,
          title: item.title || '未知标题',
          coverUrl: item.coverUrl || '',
          contentType: this.content.contentType,
          isLocal: false,
          sourceId: String(sourceIdNum),
          sourceName: this.content.sourceName,
          score: 0,
          navContentId: comicId,
          navSourceId: String(sourceIdNum)
        };
        results.push(recItem);
      }
    } catch (e) {
      logger.warn(TAG, `在线推荐搜索失败: ${String(e)}`);
    }

    this.recommendedItems = results;
    logger.info(TAG, `在线推荐加载完成: ${this.recommendedItems.length} 条`);
  }

  /**
   * 点击推荐项，导航到对应的统一详情页
   */
  private navigateToRecommendedItem(item: RecommendationItem): void {
    const params: UnifiedDetailPageParams = {
      contentType: item.contentType,
      contentId: item.navContentId,
      sourceId: item.navSourceId,
      cachedTitle: item.title,
      cachedCover: item.coverUrl
    };
    logger.info(TAG, `跳转推荐内容: type=${item.contentType}, id=${item.navContentId}`);
    this.pathStack.pushPathByName('UnifiedDetailPage', params);
  }

  // ==================== 同书架内容功能 ====================

  /**
   * 加载同书架的其他内容
   * 仅当内容在自定义书架中时执行
   */
  private async loadShelfContent(): Promise<void> {
    if (!this.content || !this.currentShelfId) return;

    this.isLoadingShelfContent = true;
    this.shelfContentItems = [];
    this.shelfContentFilter = 'all';

    try {
      const shelfItems: CategoryItem[] = this.typeShelfManager.getShelfItems(this.currentShelfId);
      const currentId = this.content.id;
      const items: ShelfContentItem[] = [];

      for (let i = 0; i < shelfItems.length && items.length < SHELF_CONTENT_MAX_COUNT; i++) {
        const catItem = shelfItems[i];

        // 跳过当前内容
        if (catItem.itemId === currentId) continue;

        try {
          switch (catItem.contentType) {
            case ContentType.MANGA: {
              const comic = await this.dataManager.getComicById(catItem.itemId);
              if (comic) {
                const coverUrl = comic.coverLocalPath || comic.coverUrl || '';
                const item: ShelfContentItem = {
                  id: `shelf_manga_${catItem.itemId}`,
                  title: comic.title || '未知标题',
                  coverUrl: coverUrl,
                  contentType: UnifiedContentType.MANGA,
                  navContentId: catItem.itemId
                };
                items.push(item);
              }
              break;
            }
            case ContentType.EBOOK: {
              const ebook = await this.ebookDataManager.getEBookById(catItem.itemId);
              if (ebook && ebook.metadata) {
                const item: ShelfContentItem = {
                  id: `shelf_ebook_${catItem.itemId}`,
                  title: ebook.metadata.title || '未知标题',
                  coverUrl: ebook.metadata.coverImagePath || '',
                  contentType: UnifiedContentType.EBOOK,
                  navContentId: catItem.itemId
                };
                items.push(item);
              }
              break;
            }
            case ContentType.NOVEL: {
              const novel = await this.novelDataManager.getBook(catItem.itemId);
              if (novel) {
                const item: ShelfContentItem = {
                  id: `shelf_novel_${catItem.itemId}`,
                  title: novel.name || '未知标题',
                  coverUrl: novel.coverUrl || '',
                  contentType: UnifiedContentType.NOVEL,
                  navContentId: novel.bookUrl,
                  navSourceId: novel.sourceId
                };
                items.push(item);
              }
              break;
            }
          }
        } catch (e) {
          logger.warn(TAG, `加载书架内容项失败: ${catItem.itemId}, ${String(e)}`);
        }
      }

      this.shelfContentItems = items;
      logger.info(TAG, `同书架内容加载完成: ${items.length} 项 (书架: ${this.currentShelfName})`);
    } catch (error) {
      logger.warn(TAG, `加载同书架内容失败: ${String(error)}`);
    } finally {
      this.isLoadingShelfContent = false;
    }
  }

  /**
   * 获取经筛选后的同书架内容列表
   */
  private getFilteredShelfContentItems(): ShelfContentItem[] {
    if (this.shelfContentFilter === 'all') {
      return this.shelfContentItems;
    }
    const filterType: UnifiedContentType = this.shelfContentFilter === 'manga'
      ? UnifiedContentType.MANGA
      : this.shelfContentFilter === 'novel'
        ? UnifiedContentType.NOVEL
        : UnifiedContentType.EBOOK;
    return this.shelfContentItems.filter((item: ShelfContentItem) => item.contentType === filterType);
  }

  /**
   * 点击同书架内容项，导航到对应的统一详情页
   */
  private navigateToShelfContentItem(item: ShelfContentItem): void {
    const params: UnifiedDetailPageParams = {
      contentType: item.contentType,
      contentId: item.navContentId,
      sourceId: item.navSourceId,
      cachedTitle: item.title,
      cachedCover: item.coverUrl
    };
    logger.info(TAG, `跳转同书架内容: type=${item.contentType}, id=${item.navContentId}`);
    this.pathStack.pushPathByName('UnifiedDetailPage', params);
  }

  /**
   * 检查同书架内容是否包含多种类型（用于决定是否显示筛选栏）
   */
  private hasMultipleContentTypes(): boolean {
    const types = new Set<UnifiedContentType>();
    for (const item of this.shelfContentItems) {
      types.add(item.contentType);
      if (types.size > 1) return true;
    }
    return false;
  }

  // ==================== UI构建 ====================

  /**
   * 获取封面图片路径（处理本地文件路径）
   */
  private getCoverImageSource(): string | Resource {
    const coverUrl = this.content?.coverUrl || '';
    if (!coverUrl) {
      return '';
    }
    
    // 如果是网络URL，直接返回
    if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
      return coverUrl;
    }
    
    // 如果已经是file://开头，直接返回
    if (coverUrl.startsWith('file://')) {
      return coverUrl;
    }
    
    // 本地文件路径，添加file://前缀
    if (coverUrl.startsWith('/')) {
      return `file://${coverUrl}`;
    }
    
    return coverUrl;
  }

  /**
   * 判断封面是否为本地文件（非网络URL）
   */
  private isLocalFileCover(): boolean {
    const coverUrl = this.content?.coverUrl || '';
    if (!coverUrl) return false;
    return !coverUrl.startsWith('http://') && !coverUrl.startsWith('https://');
  }
  
  /**
   * 清理章节标题，移除"第X话"等前缀，只保留真实标题
   * 支持多种语言格式
   * @returns [prefix, cleanTitle] 数组
   */
  private cleanChapterTitle(title: string, chapterIndex: number): string[] {
    const defaultPrefix = `第${chapterIndex + 1}话`;
    
    if (!title) {
      return [defaultPrefix, ''];
    }
    
    // 匹配各种章节前缀格式
    const prefixPatterns: RegExp[] = [
      // 中文格式
      /^第\s*(\d+(?:\.\d+)?)\s*[话話章回集卷]/,
      /^第\s*([零一二三四五六七八九十百千万]+)\s*[话話章回集卷]/,
      // 日文格式
      /^第\s*(\d+(?:\.\d+)?)\s*話/,
      // 英文格式
      /^(?:Chapter|Ch\.?|Episode|Ep\.?|Vol\.?|Part)\s*(\d+(?:\.\d+)?)/i,
      // 韩文格式
      /^(\d+)\s*화/,
      // 纯数字格式
      /^(\d+(?:\.\d+)?)\s*[\.:\-\s]/,
    ];
    
    for (const pattern of prefixPatterns) {
      const match = title.match(pattern);
      if (match) {
        const matchedPrefix = match[0];
        let cleanTitle = title.substring(matchedPrefix.length).trim();
        
        // 移除可能的分隔符
        cleanTitle = cleanTitle.replace(/^[\s\-:：\.\|]+/, '').trim();
        
        // 如果清理后的标题为空，使用原标题
        if (!cleanTitle) {
          return [defaultPrefix, title];
        }
        
        return [defaultPrefix, cleanTitle];
      }
    }
    
    // 没有匹配到前缀，返回原标题
    return [defaultPrefix, title];
  }

  @Builder
  buildHeader() {
    Row({ space: 16 }) {
      // 封面（优先使用本地缓存的 PixelMap）
      Stack() {
        if (this.coverPixelMap) {
          // 优先使用本地缓存的 PixelMap（速度最快）
          Image(this.coverPixelMap)
            .width(COVER_WIDTH)
            .height(COVER_HEIGHT)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        } else if (this.content?.coverUrl && this.isLocalFileCover()) {
          // 本地电子书封面：直接使用Image组件加载
          Image(this.getCoverImageSource())
            .width(COVER_WIDTH)
            .height(COVER_HEIGHT)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .onError(() => {
              logger.warn(TAG, `本地封面加载失败: ${this.content?.coverUrl}`);
            })
        } else if (this.content?.coverUrl) {
          // 网络封面：使用 AvifImage 组件加载
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: COVER_WIDTH,
            imageHeight: COVER_HEIGHT,
            objectFit: ImageFit.Cover,
            imageBorderRadius: 8
          })
        } else {
          // 占位符
          Column() {
            SymbolGlyph($r('sys.symbol.text_book_closed'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
          .width(COVER_WIDTH)
          .height(COVER_HEIGHT)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }

        // 内容类型标签
        Text(this.getContentTypeName())
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(0,0,0,0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 4, y: 4 })
        
        // 在线漫画封面刷新按钮（右下角）
        if (this.isOnlineManga()) {
          Button() {
            if (this.isRefetchingCover) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(14)
                .fontColor([Color.White])
            }
          }
          .width(28)
          .height(28)
          .backgroundColor('rgba(0,0,0,0.5)')
          .borderRadius(14)
          .position({ x: COVER_WIDTH - 32, y: COVER_HEIGHT - 32 })
          .enabled(!this.isRefetchingCover)
          .onClick(() => this.refetchCoverImage())
        }
      }
      .id(`cover_${this.componentId}`)
      .onClick(() => this.openCoverPreview())

      // 信息区域
      Column({ space: 8 }) {
      Text(this.stripHtmlTags(this.content?.title || '加载中...'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => {
            this.navigateToSearch(this.content?.title || '');
          })

        if (this.content?.author) {
          Text(this.stripHtmlTags(this.content.author))
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.navigateToSearch(this.content?.author || '');
            })
        } else {
          Text('')
            .fontSize(14)
        }

        Row({ space: 8 }) {
          Text(this.getReadStatusText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

          Text(`${this.content?.totalChapters || 0}章`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }

        if (this.content?.sourceName) {
          Text(`来源: ${this.content.sourceName}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }

        Blank()

        // 操作按钮
        Column({ space: 8 }) {
          // 添加书架/替换原小说按钮
          if (this.isFromChangeSource && this.originalBookInfo) {
            // 换源模式：显示替换原小说按钮
            Button('替换原小说')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .fontColor(Color.White)
              .height(32)
              .width('100%')
              .onClick(() => this.openReplaceBookDialog())
          } else {
            // 正常模式：显示添加书架按钮
            Button(this.isInShelf ? (this.currentShelfName ? `在「${this.currentShelfName}」书架中` : '在书架中') : '添加书架')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(this.isInShelf 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20'
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.isInShelf
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .height(32)
              .width('100%')
              .onClick(() => this.showAddToShelfSelection())
          }

          // 阅读按钮
          Button((this.content?.lastReadChapterIndex ?? -1) >= 0 ? '继续阅读' : '开始阅读')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(Color.White)
            .height(36)
            .width('100%')
            .onClick(() => this.continueReading())

          if (this.content?.contentType === UnifiedContentType.NOVEL) {
            Button('开始听书')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '22')
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .height(34)
              .width('100%')
              .onClick(() => this.continueReadAloud())
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(COVER_HEIGHT)
    }
    .width('100%')
    .padding(16)
  }

  /**
   * 简介文本选中后的自定义工具栏（长按选中触发）
   * 具备主题背景、阴影、边框和按下反馈效果
   */
  @Builder
  buildDescriptionSelectionMenu() {
    Row({ space: 0 }) {
      // 复制按钮
      Button('复制', { type: ButtonType.Normal })
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .height(40)
        .padding({ left: 20, right: 14 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onClick(() => {
          if (this.descriptionSelectedText) {
            this.copyToClipboard(this.descriptionSelectedText);
          }
          this.descriptionSelectedText = '';
        })

      // 垂直分隔线
      Column()
        .width(0.5)
        .height(18)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      // 搜索按钮
      Button('搜索', { type: ButtonType.Normal })
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .height(40)
        .padding({ left: 14, right: 20 })
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .onClick(() => {
          if (this.descriptionSelectedText) {
            this.navigateToSearch(this.descriptionSelectedText);
          }
          this.descriptionSelectedText = '';
        })
    }
    .height(40)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(10)
    .border({
      width: 0.5,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 4 })
    .clip(true)
  }

  @Builder
  buildDescription() {
    Column({ space: 12 }) {
      // 标签区域
      if (this.content && ((this.content.genres && this.content.genres.length > 0) || (this.content.tags && this.content.tags.length > 0))) {
        Column({ space: 8 }) {
          Text('标签')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            // 显示genres
            ForEach(this.content.genres || [], (genre: string) => {
              Text(this.stripHtmlTags(genre))
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                .padding({ left: 10, right: 10 })
                .height(26)
                .borderRadius(13)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.navigateToSearch(genre);
                })
            }, (genre: string, index: number) => `genre_${index}_${genre}`)
            
            // 显示tags
            ForEach(this.content.tags || [], (tag: string) => {
              Text(this.stripHtmlTags(tag))
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
                .padding({ left: 10, right: 10 })
                .height(26)
                .borderRadius(13)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.navigateToSearch(tag);
                })
            }, (tag: string, index: number) => `tag_${index}_${tag}`)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      
      // 简介区域
      Column({ space: 8 }) {
        Text('简介')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.stripHtmlTags(this.content?.description || '暂无简介'))
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(this.showFullDescription ? undefined : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .copyOption(CopyOptions.InApp)
          .onTextSelectionChange((start: number, end: number) => {
            const fullText = this.stripHtmlTags(this.content?.description || '');
            if (start >= 0 && end > start) {
              this.descriptionSelectedText = fullText.substring(start, end);
            }
          })
          .bindSelectionMenu(TextSpanType.TEXT, this.buildDescriptionSelectionMenu, TextResponseType.LONG_PRESS, {
            onDisappear: () => { this.descriptionSelectedText = ''; }
          })

        if (this.content?.description && this.content.description.length > 100) {
          Text(this.showFullDescription ? '收起' : '展开')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showFullDescription = !this.showFullDescription;
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildActionBar() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Start, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
      // 根据内容类型显示不同的设置入口
      if (this.content?.contentType === UnifiedContentType.MANGA) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('漫画设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openMangaSettings())
        
        // 在线漫画显示"重新获取"按钮
        if (this.isOnlineManga()) {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor([this.isRefetchingManga 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text(this.isRefetchingManga ? '获取中...' : '重新获取')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(this.isRefetchingManga 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .enabled(!this.isRefetchingManga)
          .onClick(() => this.refetchOnlineMangaInfo())
          
          // 在浏览器中打开
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.worldclock_fill_1'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
              Text('浏览器')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
          }
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => this.openInBrowser())
        }
      } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('电子书设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openEBookSettings())
        
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.wand_and_stars'))
              .fontSize(16)
              .fontColor([this.isGeneratingCover 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(this.isGeneratingCover ? '生成中...' : '生成封面')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.isGeneratingCover 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isGeneratingCover)
        .onClick(() => this.showGenerateCoverPrompt())
      } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('小说设置')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .onClick(() => this.openNovelSettings())
        
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.wand_and_stars'))
              .fontSize(16)
              .fontColor([this.isGeneratingCover 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(this.isGeneratingCover ? '生成中...' : '生成封面')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.isGeneratingCover 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isGeneratingCover)
        .onClick(() => this.showGenerateCoverPrompt())
        
        // 换源按钮
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(16)
              .fontColor([this.isSearchingSource 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text(this.isSearchingSource ? '搜索中...' : '换源')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(this.isSearchingSource 
                ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isSearchingSource)
        .onClick(() => this.openChangeSourceDialog())
      }

      // 下载按钮（仅在线漫画和小说显示，排除本地内容）
      if (this.isOnlineContent()) {
        Button() {
          if (this.isDownloading) {
            Row({ space: 6 }) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              Text('缓存中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
          } else {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
              Text('缓存')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
          }
        }
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(18)
        .enabled(!this.isDownloading)
        .onClick(() => this.showDownloadOptions())
      }

      // NSFW 标记按钮（PornHub 配色风格）
      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(16)
            .fontColor([this.content?.isNSFW ? '#FF9800' : '#FF9800'])
          Text(this.content?.isNSFW ? 'NSFW' : 'NSFW')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.content?.isNSFW ? '#FF9800' : '#FF9800')
        }
      }
      .height(36)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.content?.isNSFW ? '#1A1A1A' : 'transparent')
      .borderRadius(18)
      .borderWidth(this.content?.isNSFW ? 0 : 1)
      .borderColor('#FF9800')
      .onClick(() => this.toggleNSFW())
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }
  
  /**
   * 切换NSFW标记状态
   * 更新内存状态和数据库，支持所有内容类型
   */
  private async toggleNSFW(): Promise<void> {
    if (!this.content) return;

    const newNSFW = !(this.content.isNSFW || false);
    logger.info(TAG, `切换NSFW标记: ${this.content.id}, ${this.content.isNSFW} -> ${newNSFW}`);

    try {
      const success = await this.dataManager.updateContentNSFW(this.content.id, newNSFW);
      if (success) {
        this.content.isNSFW = newNSFW;
        promptAction.showToast({
          message: newNSFW ? '已标记为NSFW' : '已取消NSFW标记',
          duration: 1500
        });
        logger.info(TAG, `NSFW标记更新成功: ${this.content.id}, isNSFW=${newNSFW}`);
      } else {
        promptAction.showToast({
          message: 'NSFW标记更新失败',
          duration: 1500
        });
        logger.error(TAG, `NSFW标记更新失败: ${this.content.id}`);
      }
    } catch (error) {
      logger.error(TAG, `切换NSFW标记异常: ${String(error)}`);
      promptAction.showToast({
        message: '操作失败，请重试',
        duration: 1500
      });
    }
  }

  /**
   * 缓存状态卡片
   * 显示边看边下载的缓存情况
   */
  @Builder
  buildCacheStatusCard() {
    if (this.showCacheStatusCard && this.cacheStats) {
      Column({ space: 12 }) {
        // 标题行
        Row() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
            Text(this.cacheStats.contentType === CacheContentType.MANGA ? '漫画缓存' : '章节缓存')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          
          Blank()
          
          // 清理缓存按钮
          if (this.cacheStats.cacheSize > 0) {
            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(12)
                  .fontColor([Color.White])
                Text('清理')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
            .height(28)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#FF5252')
            .borderRadius(14)
            .onClick(() => this.showClearCacheConfirm())
          }
        }
        .width('100%')
        
        // 缓存统计信息
        Row({ space: 16 }) {
          // 章节缓存进度
          Column({ space: 4 }) {
            Text(`${this.cacheStats.cachedChapterCount}/${this.cacheStats.totalChapterCount}`)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('已缓存章节')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          
          // 分隔线
          Divider()
            .vertical(true)
            .height(36)
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          
          // 漫画显示页面数，小说显示缓存进度
          Column({ space: 4 }) {
            if (this.cacheStats.contentType === CacheContentType.MANGA) {
              Text(`${this.cacheStats.cachedPageCount}/${this.cacheStats.totalPageCount}`)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              Text('已缓存页面')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            } else {
              Text(`${this.cacheStatusService.calculateProgress(this.cacheStats)}%`)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              Text('缓存进度')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          
          // 分隔线
          Divider()
            .vertical(true)
            .height(36)
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          
          // 缓存大小
          Column({ space: 4 }) {
            Text(this.cacheStatusService.formatSize(this.cacheStats.cacheSize))
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            Text('缓存大小')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        
        // 进度条
        Column({ space: 4 }) {
          Progress({ value: this.cacheStatusService.calculateProgress(this.cacheStats), total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        }
        .width('100%')
        
        // 下载进度实时显示（正在下载时显示）
        if (this.isDownloading && this.downloadProgressTotal > 0) {
          Column({ space: 8 }) {
            // 分隔线
            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
            
            // 下载状态标题
            Row({ space: 6 }) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              Text('正在缓存中...')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              Blank()
              Text(`${this.downloadProgressCurrent}/${this.downloadProgressTotal}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            
            // 当前章节标题
            if (this.downloadCurrentChapterTitle) {
              Text(this.downloadCurrentChapterTitle)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            
            // 下载进度条
            Progress({ 
              value: this.downloadProgressTotal > 0 ? Math.round((this.downloadProgressCurrent / this.downloadProgressTotal) * 100) : 0, 
              total: 100, 
              type: ProgressType.Linear 
            })
              .width('100%')
              .height(6)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(3)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    } else if (this.isCacheStatsLoading) {
      // 加载中状态
      Row({ space: 8 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        Text('加载缓存状态...')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }
  
  /**
   * 显示清理缓存确认对话框
   */
  private showClearCacheConfirm(): void {
    if (!this.cacheStats) return;
    
    const contentTypeName = this.cacheStats.contentType === CacheContentType.MANGA ? '漫画' : '小说';
    const sizeText = this.cacheStatusService.formatSize(this.cacheStats.cacheSize);
    
    AlertDialog.show({
      title: '清理缓存',
      message: `确定要清理此${contentTypeName}的所有缓存吗？\n\n缓存大小: ${sizeText}\n已缓存章节: ${this.cacheStats.cachedChapterCount}章\n\n清理后需要重新阅读才能再次缓存。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清理',
        fontColor: ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme),
        action: () => this.clearContentCache()
      }
    });
  }
  
  /**
   * 清理内容缓存
   */
  private async clearContentCache(): Promise<void> {
    if (!this.cacheStats || !this.content) return;
    
    try {
      const sourceId = this.cacheStats.contentType === CacheContentType.MANGA 
        ? Number(this.pageParams?.sourceId) 
        : undefined;
      
      const success = await this.cacheStatusService.clearContentCache(
        this.cacheStats.contentType,
        this.content.id,
        sourceId
      );
      
      if (success) {
        promptAction.showToast({ message: '缓存已清理', duration: 2000 });
        // 重新加载缓存状态
        await this.loadCacheStatus();
      } else {
        promptAction.showToast({ message: '清理失败', duration: 2000 });
      }
    } catch (error) {
      logger.error(TAG, `清理缓存失败: ${String(error)}`);
      promptAction.showToast({ message: '清理失败', duration: 2000 });
    }
  }

  /**
   * 打开漫画设置
   */
  private openMangaSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    const params: MangaSettingsPageParams = {
      mangaId: this.content.id,
      fromPage: 'UnifiedDetailPage'
    };
    this.pathStack.pushPathByName('MangaSettingsPage', params);
  }
  
  /**
   * 重新获取在线漫画信息（增量更新）
   * 通过WebView重新获取漫画详情和章节列表，更新缺失或默认占位的信息
   */
  private async refetchOnlineMangaInfo(): Promise<void> {
    if (!this.content || !this.pageParams || !this.isOnlineManga()) {
      return;
    }
    
    const mangaId = this.pageParams.contentId;
    const sourceId = this.pageParams.sourceId;
    
    if (!sourceId || Number(sourceId) <= 0) {
      promptAction.showToast({ message: '缺少图源信息', duration: 2000 });
      return;
    }
    
    logger.info(TAG, `开始重新获取在线漫画信息: mangaId=${mangaId}, sourceId=${sourceId}`);
    this.isRefetchingManga = true;
    
    try {
      // 设置WebView控制器
      this.mangaDetailLoader.setWebViewController(this.webViewController);
      
      // 保存当前已有的阅读进度和状态
      const currentReadChapterIds = new Set<string>();
      const currentDownloadedChapterIds = new Set<string>();
      const currentBookmarkedChapterIds = new Set<string>();
      const currentLastReadChapterIndex = this.content.lastReadChapterIndex;
      
      this.content.chapters.forEach(ch => {
        if (ch.isRead) currentReadChapterIds.add(ch.id);
        if (ch.isDownloaded) currentDownloadedChapterIds.add(ch.id);
        if (ch.isBookmarked) currentBookmarkedChapterIds.add(ch.id);
      });
      
      // 构建加载参数，强制刷新
      const loadParams: MangaDetailLoadParams = {
        mangaId: mangaId,
        sourceId: Number(sourceId),
        forceRefresh: true
      };
      
      // 分阶段加载回调
      const progressCallback: MangaLoadProgressCallback = {
        onBasicInfoLoaded: (manga: Manga, isFavorite: boolean) => {
          logger.info(TAG, `[重新获取] 基本信息已更新: ${manga.title}, 封面=${manga.coverImagePath}, 简介长度=${manga.description?.length || 0}`);
          
          // 增量更新：用新获取的数据更新UI（如果新数据有效）
          if (this.content) {
            // 更新标题（如果新标题有效）
            if (manga.title && manga.title.trim() !== '') {
              this.content.title = manga.title;
            }
            // 更新简介（如果新简介有效）
            if (manga.description && manga.description.trim() !== '') {
              this.content.description = manga.description;
            }
            // 更新作者（如果新作者有效）
            if (manga.metadata?.authors?.[0]) {
              this.content.author = manga.metadata.authors[0];
            }
            // 更新标签（如果新标签有效）
            if (manga.metadata?.genres && manga.metadata.genres.length > 0) {
              this.content.genres = manga.metadata.genres;
            }
            // 更新封面（如果新封面有效）
            if (manga.coverImagePath && manga.coverImagePath.trim() !== '') {
              this.content.coverUrl = manga.coverImagePath;
            }
            
            logger.info(TAG, `[重新获取] UI已更新: 标题=${this.content.title}, 封面=${this.content.coverUrl}`);
          }
        },
        
        onChaptersLoaded: (chapters: MangaChapter[]) => {
          logger.info(TAG, `[重新获取] 章节已更新: ${chapters.length}章`);
          
          const currentChapterCount = this.content?.chapters.length || 0;
          const newChapterCount = chapters.length;
          const addedCount = newChapterCount - currentChapterCount;
          
          if (addedCount > 0) {
            promptAction.showToast({ message: `发现 ${addedCount} 个新章节`, duration: 2000 });
          } else {
            promptAction.showToast({ message: '信息已更新', duration: 1500 });
          }
          
          // 更新章节列表，保留已有的阅读/下载/书签状态
          if (this.content) {
            const originalManga = MangaAdapter.getOriginalManga(this.content);
            if (originalManga) {
              originalManga.chapters = chapters;
              
              this.content = MangaAdapter.toUnifiedContent(
                originalManga,
                chapters,
                this.isFavorite,
                currentReadChapterIds,
                currentDownloadedChapterIds,
                currentBookmarkedChapterIds,
                currentLastReadChapterIndex,
                sourceId
              );
            }
          }
        },
        
        onError: (error: string) => {
          logger.error(TAG, `[重新获取] 失败: ${error}`);
          promptAction.showToast({ message: `获取失败: ${error}`, duration: 2000 });
        }
      };
      
      await this.mangaDetailLoader.loadMangaDetailWithProgress(loadParams, progressCallback);
      
      logger.info(TAG, `重新获取在线漫画信息完成`);
    } catch (error) {
      logger.error(TAG, `重新获取在线漫画信息异常: ${String(error)}`);
      promptAction.showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isRefetchingManga = false;
    }
  }

  /**
   * 重新获取封面图片
   */
  private async refetchCoverImage(): Promise<void> {
    if (!this.isOnlineManga() || !this.pageParams) {
      return;
    }
    
    this.isRefetchingCover = true;
    
    try {
      const sourceId = Number(this.pageParams.sourceId);
      const mangaId = this.pageParams.contentId;
      
      // 从数据库获取externalId
      const comicInfo = await this.dataManager.getComicById(mangaId);
      const externalId = comicInfo?.externalId || mangaId;
      
      logger.info(TAG, `重新获取封面: sourceId=${sourceId}, externalId=${externalId}`);
      
      // 初始化MangaEngine获取封面
      await this.loadSourceName(sourceId);
      const mangaEngine = await this.webViewManager.getMangaEngine(sourceId, this.currentSourceName);
      
      if (mangaEngine) {
        const detailResult = await mangaEngine.getMangaDetail(externalId);
        if (detailResult.success && detailResult.data?.cover) {
          const newCoverUrl = detailResult.data.cover;
          logger.info(TAG, `获取到新封面: ${newCoverUrl}`);
          
          // 更新UI
          if (this.content) {
            this.content.coverUrl = newCoverUrl;
          }
          
          // 更新数据库
          await this.dataManager.updateComicCoverUrl(mangaId, newCoverUrl);
          
          promptAction.showToast({ message: '封面已更新', duration: 1500 });
        } else {
          promptAction.showToast({ message: '获取封面失败', duration: 2000 });
        }
      }
    } catch (error) {
      logger.error(TAG, `重新获取封面失败: ${String(error)}`);
      promptAction.showToast({ message: `获取失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isRefetchingCover = false;
    }
  }
  
  // 当前图源名称（用于封面刷新）
  private currentSourceName: string = '';
  
  /**
   * 加载图源名称
   */
  private async loadSourceName(sourceId: number): Promise<void> {
    try {
      const sources: SourceInfo[] = await this.sourceManager.getAllSources();
      const sourceInfo: SourceInfo | undefined = sources.find((s: SourceInfo) => s.id === sourceId);
      if (sourceInfo) {
        this.currentSourceName = sourceInfo.name;
      }
    } catch (error) {
      logger.warn(TAG, `加载图源名称失败: ${String(error)}`);
    }
  }
  
  /**
   * 根据ID获取图源信息
   */
  private async getSourceInfoById(sourceId: number): Promise<SourceInfo | null> {
    try {
      const sources: SourceInfo[] = await this.sourceManager.getAllSources();
      const sourceInfo: SourceInfo | undefined = sources.find((s: SourceInfo) => s.id === sourceId);
      return sourceInfo || null;
    } catch (error) {
      logger.warn(TAG, `获取图源信息失败: ${String(error)}`);
      return null;
    }
  }
  
  /**
   * 在浏览器中打开在线漫画网页
   */
  private async openInBrowser(): Promise<void> {
    if (!this.isOnlineManga() || !this.pageParams) {
      promptAction.showToast({ message: '无法获取网页地址', duration: 2000 });
      return;
    }
    
    try {
      // 获取图源信息以构建URL
      const sourceId = Number(this.pageParams.sourceId);
      const mangaId = this.pageParams.contentId;
      
      // 从数据库获取externalId
      const comicInfo = await this.dataManager.getComicById(mangaId);
      const externalId = comicInfo?.externalId || mangaId;
      
      // 获取图源配置
      const sourceInfo: SourceInfo | null = await this.getSourceInfoById(sourceId);
      if (!sourceInfo || !sourceInfo.baseUrl) {
        promptAction.showToast({ message: '无法获取图源信息', duration: 2000 });
        return;
      }
      
      // 构建漫画详情页URL
      let mangaUrl: string = sourceInfo.baseUrl;
      if (!mangaUrl.endsWith('/')) {
        mangaUrl += '/';
      }
      mangaUrl += externalId;
      
      logger.info(TAG, `在浏览器中打开: ${mangaUrl}`);
      
      // 使用系统API打开浏览器
      const context = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: mangaUrl
      };
      
      await context.startAbility(want);
    } catch (error) {
      logger.error(TAG, `打开浏览器失败: ${String(error)}`);
      promptAction.showToast({ message: `打开失败: ${String(error)}`, duration: 2000 });
    }
  }
  
  /**
   * 打开电子书设置
   */
  private openEBookSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    const params: EBookSettingsPageParams = {
      bookId: this.content.id
    };
    this.pathStack.pushPathByName('EBookSettingsPage', params);
  }

  /**
   * 打开小说设置（显示阅读设置弹窗）
   */
  private openNovelSettings(): void {
    if (!this.content || !this.pageParams) return;
    
    // 显示小说设置选项
    AlertDialog.show({
      title: '小说设置',
      message: '请选择要执行的操作',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '进入阅读器设置',
        action: () => {
          // 跳转到阅读器，用户可以在阅读器中调整设置
          this.continueReading();
        }
      },
      secondaryButton: {
        value: '管理缓存',
        action: () => {
          this.showNovelCacheOptions();
        }
      }
    });
  }

  /**
   * 显示小说缓存选项
   */
  private showNovelCacheOptions(): void {
    AlertDialog.show({
      title: '缓存管理',
      message: '选择缓存操作',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '缓存全部章节',
        action: () => {
          this.cacheAllNovelChapters();
        }
      },
      secondaryButton: {
        value: '清除缓存',
        action: () => {
          this.clearNovelCache();
        }
      }
    });
  }

  /**
   * 缓存全部小说章节（旧版本，直接使用 NovelChapterCacheManager）
   */
  private async cacheAllNovelChapters(): Promise<void> {
    if (!this.content || this.content.chapters.length === 0) {
      promptAction.showToast({ message: '没有可缓存的章节' });
      return;
    }
    
    // [修复] 优先使用content.sourceId，因为loadNovelContent已经从数据库获取了正确的sourceId
    const sourceId = this.content.sourceId || this.pageParams?.sourceId;
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }
    
    // 使用与NovelReaderPage一致的bookId格式
    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    
    // 从统一章节中提取原始 LegadoChapter 数据
    const chapters: LegadoChapter[] = [];
    for (const unifiedChapter of this.content.chapters) {
      const originalChapter = NovelAdapter.getOriginalChapter(unifiedChapter);
      if (originalChapter) {
        chapters.push(originalChapter);
      }
    }
    
    if (chapters.length === 0) {
      promptAction.showToast({ message: '没有可缓存的章节' });
      return;
    }
    
    // 获取未缓存的章节
    const uncachedChapters: LegadoChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
      if (!isCached) {
        uncachedChapters.push(chapters[i]);
      }
    }
    
    if (uncachedChapters.length === 0) {
      promptAction.showToast({ message: '所有章节已缓存' });
      return;
    }
    
    // 创建下载任务（使用一致的bookId）
    const taskId = this.novelCacheManager.createDownloadTask(
      novelCacheBookId,
      this.content.title,
      0,
      chapters.length - 1
    );
    
    promptAction.showToast({ message: `开始缓存 ${uncachedChapters.length} 章...` });
    
    // 开始下载
    await this.novelCacheManager.startDownload(taskId, sourceId, chapters, {
      onProgress: (current: number, total: number, chapterTitle: string) => {
        logger.debug(TAG, `缓存进度: ${current}/${total} - ${chapterTitle}`);
      },
      onComplete: () => {
        promptAction.showToast({ message: '缓存完成' });
        // 刷新章节列表以更新缓存状态
        this.refreshNovelChapterCacheStatus();
        this.loadCacheStatus();
      },
      onError: (error: string) => {
        promptAction.showToast({ message: `缓存失败: ${error}` });
      }
    });
  }
  
  /**
   * 刷新小说章节缓存状态
   */
  private async refreshNovelChapterCacheStatus(): Promise<void> {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) return;
    
    // [修复] 优先使用content.sourceId，因为loadNovelContent已经从数据库获取了正确的sourceId
    const sourceId = this.content.sourceId || this.pageParams?.sourceId || '';
    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    
    const cachedIndexes = new Set<number>();
    for (let i = 0; i < this.content.chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
      if (isCached) {
        cachedIndexes.add(i);
      }
    }
    
    // 更新章节的缓存状态
    this.content.chapters.forEach((ch, index) => {
      ch.isDownloaded = cachedIndexes.has(index);
    });
  }

  /**
   * 清除小说缓存
   */
  private async clearNovelCache(): Promise<void> {
    if (!this.content) return;
    
    try {
      // [修复] 优先使用content.sourceId，因为loadNovelContent已经从数据库获取了正确的sourceId
      const sourceId = this.content.sourceId || this.pageParams?.sourceId || '';
      const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
      
      await this.novelCacheManager.clearBookCache(novelCacheBookId);
      promptAction.showToast({ message: '缓存已清除' });
      
      // 更新章节的缓存状态
      this.content.chapters.forEach(ch => {
        ch.isDownloaded = false;
      });
      
      // 刷新缓存状态卡片
      await this.loadCacheStatus();
    } catch (error) {
      promptAction.showToast({ message: `清除缓存失败: ${String(error)}` });
    }
  }

  /**
   * 显示下载选项对话框
   */
  private showDownloadOptions(): void {
    if (!this.content || this.content.chapters.length === 0) return;
    
    // 初始化下载对话框状态
    this.downloadSelectionMode = 'range';
    this.downloadChapterListExpanded = false;
    
    // 找到第一个未缓存的章节作为起始位置
    let firstUncachedIndex = 0;
    for (let i = 0; i < this.content.chapters.length; i++) {
      if (!this.content.chapters[i].isDownloaded) {
        firstUncachedIndex = i;
        break;
      }
    }
    
    // 如果所有章节都已缓存，则从0开始
    this.downloadRangeStart = firstUncachedIndex;
    this.downloadRangeEnd = this.content.chapters.length - 1;
    
    // 初始化单独选择模式：默认不选中任何章节
    this.downloadSelectedChapters = new Set<number>();
    
    // 显示对话框并播放动画
    this.showDownloadDialog = true;
    animateTo({
      duration: 300,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.downloadDialogOpacity = 1;
      this.downloadDialogScale = 1;
      this.downloadDialogTranslateY = 0;
    });
  }
  
  /**
   * 关闭下载对话框
   */
  private closeDownloadDialog(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.downloadDialogOpacity = 0;
      this.downloadDialogScale = 0.8;
      this.downloadDialogTranslateY = 50;
    });
    
    setTimeout(() => {
      this.showDownloadDialog = false;
    }, 260);
  }
  
  /**
   * 切换章节选中状态
   */
  private toggleChapterSelection(index: number): void {
    // 已缓存章节不可选中
    if (this.content && this.content.chapters[index]?.isDownloaded) {
      return;
    }
    
    const newSet = new Set(this.downloadSelectedChapters);
    if (newSet.has(index)) {
      newSet.delete(index);
    } else {
      newSet.add(index);
    }
    this.downloadSelectedChapters = newSet;
  }
  
  /**
   * 获取选中的章节数量（排除已缓存章节）
   */
  private getSelectedChapterCount(): number {
    if (!this.content) return 0;
    
    if (this.downloadSelectionMode === 'range') {
      // 区间选择模式：计算区间内未缓存的章节数
      let count = 0;
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        if (!this.content.chapters[i]?.isDownloaded) {
          count++;
        }
      }
      return count;
    } else {
      return this.downloadSelectedChapters.size;
    }
  }
  
  /**
   * 执行下载选中的章节
   */
  private async executeDownloadSelected(): Promise<void> {
    if (!this.content) return;
    
    const selectedCount = this.getSelectedChapterCount();
    if (selectedCount === 0) {
      promptAction.showToast({ message: '请选择要下载的章节' });
      return;
    }
    
    // 关闭对话框
    this.closeDownloadDialog();
    
    // 根据内容类型执行下载
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      await this.downloadSelectedNovelChapters();
    } else if (this.content.contentType === UnifiedContentType.MANGA) {
      await this.downloadSelectedMangaChapters();
    }
  }
  
  /**
   * 下载选中的小说章节
   */
  private async downloadSelectedNovelChapters(): Promise<void> {
    if (!this.content) return;
    
    const sourceId = this.pageParams?.sourceId;
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }
    
    // 获取选中的章节索引
    const selectedIndexes: number[] = [];
    if (this.downloadSelectionMode === 'range') {
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        selectedIndexes.push(i);
      }
    } else {
      this.downloadSelectedChapters.forEach(idx => selectedIndexes.push(idx));
      selectedIndexes.sort((a, b) => a - b);
    }
    
    // 提取原始章节数据
    const chapters: LegadoChapter[] = [];
    for (const idx of selectedIndexes) {
      if (idx < this.content.chapters.length) {
        const originalChapter = NovelAdapter.getOriginalChapter(this.content.chapters[idx]);
        if (originalChapter) {
          chapters.push(originalChapter);
        }
      }
    }
    
    if (chapters.length === 0) {
      promptAction.showToast({ message: '无可下载的章节' });
      return;
    }
    
    // 注册下载回调以实时更新进度
    this.registerDownloadCallback();
    
    // 初始化进度状态
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chapters.length;
    this.downloadCurrentChapterTitle = '';
    
    // 使用与NovelReaderPage一致的bookId格式
    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    
    promptAction.showToast({ message: `开始缓存 ${chapters.length} 章...` });
    
    try {
      await this.unifiedDownloadManager.downloadNovelChapters({
        bookId: novelCacheBookId,
        bookTitle: this.content.title,
        sourceId: sourceId,
        chapters: chapters,
        startIndex: selectedIndexes[0],
        endIndex: selectedIndexes[selectedIndexes.length - 1]
      });
      
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
    } catch (error) {
      logger.error(TAG, `创建小说下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
      this.isDownloading = false;
      this.downloadProgressCurrent = 0;
      this.downloadProgressTotal = 0;
    }
  }
  
  /**
   * 下载选中的漫画章节
   */
  private async downloadSelectedMangaChapters(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) return;
    
    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      promptAction.showToast({ message: '缺少图源信息' });
      return;
    }
    
    // 获取选中的章节索引
    const selectedIndexes: number[] = [];
    if (this.downloadSelectionMode === 'range') {
      for (let i = this.downloadRangeStart; i <= this.downloadRangeEnd; i++) {
        selectedIndexes.push(i);
      }
    } else {
      this.downloadSelectedChapters.forEach(idx => selectedIndexes.push(idx));
      selectedIndexes.sort((a, b) => a - b);
    }
    
    // 获取未下载的章节
    const chaptersToDownload = selectedIndexes
      .filter(idx => idx < this.content!.chapters.length && !this.content!.chapters[idx].isDownloaded)
      .map(idx => this.content!.chapters[idx]);
    
    if (chaptersToDownload.length === 0) {
      promptAction.showToast({ message: '选中的章节已全部下载' });
      return;
    }
    
    // 注册下载回调以实时更新进度
    this.registerDownloadCallback();
    
    // 初始化进度状态
    this.isDownloading = true;
    this.downloadProgressCurrent = 0;
    this.downloadProgressTotal = chaptersToDownload.length;
    this.downloadCurrentChapterTitle = '';
    
    promptAction.showToast({ message: `开始下载 ${chaptersToDownload.length} 章...` });
    
    try {
      const downloadChapters: MangaChapterDownloadItem[] = [];
      for (const ch of chaptersToDownload) {
        const item: MangaChapterDownloadItem = {
          chapterId: ch.id,
          chapterTitle: ch.title,
          chapterIndex: ch.index,
          pageListFetcher: this.createPageListFetcher()
        };
        downloadChapters.push(item);
      }
      
      await this.unifiedDownloadManager.downloadMangaChapters(
        this.content.id,
        this.content.title,
        sourceId,
        downloadChapters
      );
      
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
    } catch (error) {
      logger.error(TAG, `创建漫画下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
      this.isDownloading = false;
      this.downloadProgressCurrent = 0;
      this.downloadProgressTotal = 0;
    }
  }
  
  /**
   * 下载全部小说章节（使用统一下载管理器）
   */
  private async downloadAllNovelChapters(): Promise<void> {
    if (!this.content || this.content.chapters.length === 0) {
      promptAction.showToast({ message: '无可下载的章节' });
      return;
    }
    
    const sourceId = this.pageParams?.sourceId;
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }
    
    // 从统一章节中提取原始 LegadoChapter 数据
    const chapters: LegadoChapter[] = [];
    for (const unifiedChapter of this.content.chapters) {
      const originalChapter = NovelAdapter.getOriginalChapter(unifiedChapter);
      if (originalChapter) {
        chapters.push(originalChapter);
      }
    }
    
    if (chapters.length === 0) {
      promptAction.showToast({ message: '无可下载的章节' });
      return;
    }
    
    this.isDownloading = true;
    promptAction.showToast({ message: `开始缓存 ${chapters.length} 章...` });
    
    try {
      await this.unifiedDownloadManager.downloadNovelChapters({
        bookId: this.content.id,
        bookTitle: this.content.title,
        sourceId: sourceId,
        chapters: chapters,
        startIndex: 0,
        endIndex: chapters.length - 1
      });
      
      // 下载任务已创建，实际下载在后台进行
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
      
      // 刷新缓存状态
      await this.loadCacheStatus();
    } catch (error) {
      logger.error(TAG, `创建小说下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
    } finally {
      this.isDownloading = false;
    }
  }
  
  /**
   * 下载未读小说章节（使用统一下载管理器）
   */
  private async downloadUnreadNovelChapters(): Promise<void> {
    if (!this.content || this.content.chapters.length === 0) {
      promptAction.showToast({ message: '无可下载的章节' });
      return;
    }
    
    const sourceId = this.pageParams?.sourceId;
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }
    
    const lastReadIndex = this.content.lastReadChapterIndex || 0;
    
    if (lastReadIndex >= this.content.chapters.length - 1) {
      promptAction.showToast({ message: '没有未读章节' });
      return;
    }
    
    // 从统一章节中提取未读的原始 LegadoChapter 数据
    const chapters: LegadoChapter[] = [];
    for (let i = lastReadIndex; i < this.content.chapters.length; i++) {
      const originalChapter = NovelAdapter.getOriginalChapter(this.content.chapters[i]);
      if (originalChapter) {
        chapters.push(originalChapter);
      }
    }
    
    if (chapters.length === 0) {
      promptAction.showToast({ message: '没有未读章节' });
      return;
    }
    
    this.isDownloading = true;
    promptAction.showToast({ message: `开始缓存 ${chapters.length} 章未读内容...` });
    
    try {
      await this.unifiedDownloadManager.downloadNovelChapters({
        bookId: this.content.id,
        bookTitle: this.content.title,
        sourceId: sourceId,
        chapters: chapters,
        startIndex: lastReadIndex,
        endIndex: this.content.chapters.length - 1
      });
      
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
      
      // 刷新缓存状态
      await this.loadCacheStatus();
    } catch (error) {
      logger.error(TAG, `创建小说下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
    } finally {
      this.isDownloading = false;
    }
  }
  
  /**
   * 下载全部漫画章节（使用统一下载管理器）
   */
  private async downloadAllMangaChapters(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) return;
    
    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      promptAction.showToast({ message: '缺少图源信息' });
      return;
    }
    
    const chapters = this.content.chapters;
    if (chapters.length === 0) {
      promptAction.showToast({ message: '无可下载的章节' });
      return;
    }
    
    // 过滤已下载的章节
    const undownloadedChapters = chapters.filter(ch => !ch.isDownloaded);
    if (undownloadedChapters.length === 0) {
      promptAction.showToast({ message: '所有章节已下载' });
      return;
    }
    
    this.isDownloading = true;
    promptAction.showToast({ message: `开始下载 ${undownloadedChapters.length} 章...` });
    
    try {
      // 构建下载参数
      const downloadChapters: MangaChapterDownloadItem[] = [];
      for (const ch of undownloadedChapters) {
        const item: MangaChapterDownloadItem = {
          chapterId: ch.id,
          chapterTitle: ch.title,
          chapterIndex: ch.index,
          pageListFetcher: this.createPageListFetcher()
        };
        downloadChapters.push(item);
      }
      
      await this.unifiedDownloadManager.downloadMangaChapters(
        this.content.id,
        this.content.title,
        sourceId,
        downloadChapters
      );
      
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
    } catch (error) {
      logger.error(TAG, `创建漫画下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
    } finally {
      this.isDownloading = false;
    }
  }
  
  /**
   * 下载未读漫画章节（使用统一下载管理器）
   */
  private async downloadUnreadMangaChapters(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) return;
    
    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) {
      promptAction.showToast({ message: '缺少图源信息' });
      return;
    }
    
    const lastReadIndex = this.content.lastReadChapterIndex || 0;
    const chapters = this.content.chapters;
    
    // 获取未读且未下载的章节
    const unreadUndownloaded = chapters.filter(ch => 
      ch.index >= lastReadIndex && !ch.isDownloaded
    );
    
    if (unreadUndownloaded.length === 0) {
      promptAction.showToast({ message: '未读章节已全部下载' });
      return;
    }
    
    this.isDownloading = true;
    promptAction.showToast({ message: `开始下载 ${unreadUndownloaded.length} 章未读内容...` });
    
    try {
      const downloadChapters: MangaChapterDownloadItem[] = [];
      for (const ch of unreadUndownloaded) {
        const item: MangaChapterDownloadItem = {
          chapterId: ch.id,
          chapterTitle: ch.title,
          chapterIndex: ch.index,
          pageListFetcher: this.createPageListFetcher()
        };
        downloadChapters.push(item);
      }
      
      await this.unifiedDownloadManager.downloadMangaChapters(
        this.content.id,
        this.content.title,
        sourceId,
        downloadChapters
      );
      
      promptAction.showToast({ message: '下载任务已创建，后台进行中...' });
    } catch (error) {
      logger.error(TAG, `创建漫画下载任务失败: ${String(error)}`);
      promptAction.showToast({ message: `下载失败: ${String(error)}` });
    } finally {
      this.isDownloading = false;
    }
  }
  
  /**
   * 注册下载进度回调
   * 用于实时显示下载进度
   */
  private registerDownloadCallback(): void {
    if (this.downloadCallbackRegistered) return;
    
    const callback: UnifiedDownloadCallback = {
      onProgress: (task: UnifiedDownloadTask) => {
        // 只处理当前内容的下载任务
        // 小说使用 novelCacheBookId 格式，漫画使用原始 id
        if (this.content && this.isCurrentContentTask(task)) {
          // 先保存旧值用于判断是否需要刷新缓存状态
          const previousDownloaded = this.downloadProgressCurrent;
          
          this.downloadProgressCurrent = task.downloadedCount;
          this.downloadProgressTotal = task.totalCount;
          this.downloadCurrentChapterTitle = task.chapterTitle || '';
          this.isDownloading = task.status === UnifiedTaskStatus.DOWNLOADING || task.status === UnifiedTaskStatus.PENDING;
          
          // 每完成一章刷新缓存状态
          if (task.downloadedCount > 0 && task.downloadedCount !== previousDownloaded) {
            this.loadCacheStatus();
          }
        }
      },
      onComplete: (task: UnifiedDownloadTask) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadProgressCurrent = 0;
          this.downloadProgressTotal = 0;
          this.downloadCurrentChapterTitle = '';
          // 完成时刷新缓存状态
          this.loadCacheStatus();
          logger.info(TAG, `下载完成: ${task.contentTitle}`);
        }
      },
      onError: (task: UnifiedDownloadTask, error: string) => {
        if (this.content && this.isCurrentContentTask(task)) {
          this.isDownloading = false;
          this.downloadCurrentChapterTitle = '';
          logger.error(TAG, `下载失败: ${task.contentTitle}, ${error}`);
        }
      }
    };
    
    this.unifiedDownloadManager.registerGlobalCallback(callback);
    this.downloadCallbackRegistered = true;
    logger.info(TAG, '已注册下载进度回调');
  }
  
  /**
   * 取消下载进度回调注册
   */
  private unregisterDownloadCallback(): void {
    // 由于 UnifiedDownloadManager 的全局回调是 Set 结构，无法通过引用删除
    // 这里标记为未注册，在下次需要时重新注册
    this.downloadCallbackRegistered = false;
    logger.info(TAG, '已标记下载回调为未注册');
  }
  
  /**
   * 清除漫画缓存
   */
  private async clearMangaCache(): Promise<void> {
    if (!this.content || !this.isOnlineManga()) return;
    
    const sourceId = Number(this.pageParams?.sourceId);
    if (!sourceId || sourceId <= 0) return;
    
    try {
      await this.cacheStatusService.clearContentCache(
        CacheContentType.MANGA,
        this.content.id,
        sourceId
      );
      promptAction.showToast({ message: '缓存已清除' });
      
      // 重新加载缓存状态
      await this.loadCacheStatus();
    } catch (error) {
      promptAction.showToast({ message: `清除缓存失败: ${String(error)}` });
    }
  }
  
  /**
   * 缓存未读小说章节
   */
  private async cacheUnreadNovelChapters(): Promise<void> {
    if (!this.content || !this.content.originalData) return;
    
    const sourceId = this.pageParams?.sourceId;
    if (!sourceId) {
      promptAction.showToast({ message: '缺少书源信息' });
      return;
    }
    
    // 使用与NovelReaderPage一致的bookId格式
    const novelCacheBookId = this.getNovelCacheBookId(sourceId, this.content.id);
    
    const chapters = this.content.originalData as LegadoChapter[];
    const lastReadIndex = this.content.lastReadChapterIndex || 0;
    
    // 获取未读且未缓存的章节
    const uncachedChapters: LegadoChapter[] = [];
    for (let i = lastReadIndex; i < chapters.length; i++) {
      const isCached = await this.novelCacheManager.isChapterCached(novelCacheBookId, i);
      if (!isCached) {
        uncachedChapters.push(chapters[i]);
      }
    }
    
    if (uncachedChapters.length === 0) {
      promptAction.showToast({ message: '未读章节已全部缓存' });
      return;
    }
    
    const taskId = this.novelCacheManager.createDownloadTask(
      novelCacheBookId,
      this.content.title,
      lastReadIndex,
      chapters.length - 1
    );
    
    promptAction.showToast({ message: `开始缓存 ${uncachedChapters.length} 章未读内容...` });
    
    await this.novelCacheManager.startDownload(taskId, sourceId, chapters.slice(lastReadIndex), {
      onProgress: (current: number, total: number, chapterTitle: string) => {
        logger.debug(TAG, `缓存进度: ${current}/${total} - ${chapterTitle}`);
      },
      onComplete: () => {
        promptAction.showToast({ message: '缓存完成' });
        this.refreshNovelChapterCacheStatus();
      },
      onError: (error: string) => {
        promptAction.showToast({ message: `缓存失败: ${error}` });
      }
    });
  }

  /**
   * 同书架内容区域
   * 显示当前内容所在书架的其他内容，支持按内容类型筛选
   * 仅在内容在自定义书架中且有其他内容时显示
   */
  @Builder
  buildShelfContentSection() {
    if (this.isLoadingShelfContent || this.shelfContentItems.length > 0) {
      Column({ space: 12 }) {
        // 标题行
        Row() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.heart_square_stack_fill'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(this.currentShelfName ? `「${this.currentShelfName}」书架` : '同书架内容')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          Blank()
          if (this.isLoadingShelfContent) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          if (this.shelfContentItems.length > 0) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              .rotate({ angle: this.isShelfContentExpanded ? 0 : -90 })
              .animation({ duration: 250, curve: Curve.EaseInOut })
              .onClick(() => {
                animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                  this.isShelfContentExpanded = !this.isShelfContentExpanded;
                });
              })
          }
        }
        .width('100%')
        .onClick(() => {
          if (this.shelfContentItems.length > 0) {
            animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
              this.isShelfContentExpanded = !this.isShelfContentExpanded;
            });
          }
        })

        // 可展开/收起的内容区域
        if (this.isShelfContentExpanded) {
          Column({ space: 12 }) {
            // 筛选栏（仅在包含多种内容类型时显示）
            if (this.shelfContentItems.length > 0 && this.hasMultipleContentTypes()) {
              Row({ space: 8 }) {
                ForEach(
                  [
                    { key: 'all' as ShelfContentFilterType, label: '全部' },
                    { key: 'manga' as ShelfContentFilterType, label: '漫画' },
                    { key: 'novel' as ShelfContentFilterType, label: '小说' },
                    { key: 'ebook' as ShelfContentFilterType, label: '电子书' }
                  ],
                  (tab: ShelfFilterTab) => {
                    Text(tab.label)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(this.shelfContentFilter === tab.key
                        ? Color.White
                        : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .backgroundColor(this.shelfContentFilter === tab.key
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                        : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                      .borderRadius(14)
                      .animation({ duration: 200, curve: Curve.EaseInOut })
                      .onClick(() => {
                        animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
                          this.shelfContentFilter = tab.key;
                        });
                      })
                  },
                  (tab: ShelfFilterTab) => `filter_${tab.key}`
                )
              }
              .width('100%')
            }

            // 内容卡片横向列表
            if (this.shelfContentItems.length > 0) {
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.getFilteredShelfContentItems(), (item: ShelfContentItem) => {
                    Column({ space: 6 }) {
                      // 封面图片
                      Stack() {
                        if (item.coverUrl && (item.coverUrl.startsWith('http://') || item.coverUrl.startsWith('https://'))) {
                          AvifImage({
                            src: item.coverUrl,
                            imageWidth: SHELF_CONTENT_CARD_COVER_W,
                            imageHeight: SHELF_CONTENT_CARD_COVER_H,
                            objectFit: ImageFit.Cover,
                            imageBorderRadius: 6
                          })
                        } else if (item.coverUrl) {
                          Image(`file://${item.coverUrl}`)
                            .width(SHELF_CONTENT_CARD_COVER_W)
                            .height(SHELF_CONTENT_CARD_COVER_H)
                            .objectFit(ImageFit.Cover)
                            .borderRadius(6)
                        } else {
                          Column() {
                            SymbolGlyph($r('sys.symbol.text_book_closed'))
                              .fontSize(32)
                              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                          }
                          .width(SHELF_CONTENT_CARD_COVER_W)
                          .height(SHELF_CONTENT_CARD_COVER_H)
                          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                          .borderRadius(6)
                          .justifyContent(FlexAlign.Center)
                        }

                        // 内容类型角标
                        Text(item.contentType === UnifiedContentType.MANGA ? '漫画'
                          : item.contentType === UnifiedContentType.EBOOK ? '电子书' : '小说')
                          .fontSize(9)
                          .fontColor(Color.White)
                          .backgroundColor('rgba(0,0,0,0.55)')
                          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                          .borderRadius(3)
                          .position({ x: 4, y: 4 })
                      }

                      // 标题
                      Text(item.title)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width(SHELF_CONTENT_CARD_COVER_W)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .onClick(() => this.navigateToShelfContentItem(item))
                  }, (item: ShelfContentItem) => `${item.id}_${this.shelfContentFilter}`)
                }
                .padding({ left: 4, right: 4 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
            }
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .clip(true)
    }
  }

  /**
   * 智能推荐区域
   * 在内容加载完成后异步填充，显示横向可滚动的推荐卡片列表
   * 仅在有推荐内容或正在加载时渲染
   */
  @Builder
  buildRecommendationSection() {
    if (this.isLoadingRecommendations || this.recommendedItems.length > 0) {
      Column({ space: 12 }) {
        // 标题行
        Row() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.diamond'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('相关推荐')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          Blank()
          if (this.isLoadingRecommendations) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          if (this.recommendedItems.length > 0) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              .rotate({ angle: this.isRecommendationsExpanded ? 0 : -90 })
              .animation({ duration: 250, curve: Curve.EaseInOut })
              .onClick(() => {
                animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                  this.isRecommendationsExpanded = !this.isRecommendationsExpanded;
                });
              })
          }
        }
        .width('100%')
        .onClick(() => {
          if (this.recommendedItems.length > 0) {
            animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
              this.isRecommendationsExpanded = !this.isRecommendationsExpanded;
            });
          }
        })

        // 可展开/收起的推荐内容
        if (this.isRecommendationsExpanded && this.recommendedItems.length > 0) {
          Scroll() {
            Row({ space: 12 }) {
              ForEach(this.recommendedItems, (item: RecommendationItem) => {
                Column({ space: 6 }) {
                  // 封面图片
                  Stack() {
                    if (item.coverUrl && (item.coverUrl.startsWith('http://') || item.coverUrl.startsWith('https://'))) {
                      AvifImage({
                        src: item.coverUrl,
                        imageWidth: RECOMMEND_CARD_COVER_W,
                        imageHeight: RECOMMEND_CARD_COVER_H,
                        objectFit: ImageFit.Cover,
                        imageBorderRadius: 6
                      })
                    } else if (item.coverUrl) {
                      Image(`file://${item.coverUrl}`)
                        .width(RECOMMEND_CARD_COVER_W)
                        .height(RECOMMEND_CARD_COVER_H)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(6)
                    } else {
                      Column() {
                        SymbolGlyph($r('sys.symbol.text_book_closed'))
                          .fontSize(32)
                          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                      }
                      .width(RECOMMEND_CARD_COVER_W)
                      .height(RECOMMEND_CARD_COVER_H)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(6)
                      .justifyContent(FlexAlign.Center)
                    }

                    // 内容类型角标
                    Text(item.contentType === UnifiedContentType.MANGA ? '漫画'
                      : item.contentType === UnifiedContentType.EBOOK ? '电子书' : '小说')
                      .fontSize(9)
                      .fontColor(Color.White)
                      .backgroundColor('rgba(0,0,0,0.55)')
                      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                      .borderRadius(3)
                      .position({ x: 4, y: 4 })
                  }

                  // 标题
                  Text(item.title)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width(RECOMMEND_CARD_COVER_W)
                }
                .alignItems(HorizontalAlign.Start)
                .onClick(() => this.navigateToRecommendedItem(item))
              }, (item: RecommendationItem) => item.id)
            }
            .padding({ left: 4, right: 4 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .clip(true)
    }
  }

  @Builder
  buildChapterList() {
    // 电子书特殊处理：如果有章节则显示章节列表，否则显示阅读进度信息
    if (this.content?.contentType === UnifiedContentType.EBOOK && this.content.chapters.length === 0) {
      this.buildEBookProgressInfo()
    } else {
      Column({ space: 12 }) {
        // 章节列表头部
        Row() {
          Text(`章节列表 (${this.isChaptersLoading ? '...' : (this.content?.totalChapters || 0)})`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Blank()

          // 排序按钮（章节加载中时隐藏）
          if (!this.isChaptersLoading) {
            Button() {
              SymbolGlyph(this.chapterSortOrder === ChapterSortOrder.ASCENDING 
                ? $r('sys.symbol.arrow_up') 
                : $r('sys.symbol.arrow_down'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.chapterSortOrder = this.chapterSortOrder === ChapterSortOrder.ASCENDING 
                ? ChapterSortOrder.DESCENDING 
                : ChapterSortOrder.ASCENDING;
            })
          }
        }
        .width('100%')

        // 章节加载中显示加载动画
        if (this.isChaptersLoading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            
            Text(this.chaptersLoadProgress || '正在加载章节列表...')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 根据内容类型显示不同的章节列表
          if (this.content?.contentType === UnifiedContentType.MANGA) {
            this.buildMangaChapterList()
          } else if (this.content?.contentType === UnifiedContentType.NOVEL) {
            this.buildNovelChapterList()
          } else if (this.content?.contentType === UnifiedContentType.EBOOK) {
            this.buildEBookChapterList()
          }
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }
  
  /**
   * 电子书阅读进度信息（替代章节列表）
   */
  @Builder
  buildEBookProgressInfo() {
    Column({ space: 16 }) {
      Text('阅读信息')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      // 阅读进度
      Column({ space: 8 }) {
        Row() {
          Text('阅读进度')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.content?.readProgress || 0}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Progress({ value: this.content?.readProgress || 0, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
      }
      
      // 当前章节
      if (this.content?.lastReadChapterTitle) {
        Row() {
          Text('当前章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.content.lastReadChapterTitle)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' })
        }
        .width('100%')
      }
      
      // 文件信息
      Row() {
        Text('文件格式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text(this.getEBookFormat())
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }
  
  /**
   * 获取电子书格式
   */
  private getEBookFormat(): string {
    if (!this.content) return '未知';
    const originalEBook = EBookAdapter.getOriginalEBook(this.content);
    if (originalEBook && originalEBook.format) {
      return originalEBook.format.toUpperCase();
    }
    // 对于在线电子书，尝试从content.format获取
    if (this.content.format) {
      return this.content.format.toUpperCase();
    }
    return '未知';
  }

  /**
   * 漫画章节列表（显示图片数量、阅读进度、更新时间等）
   */
  @Builder
  buildMangaChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：已读指示器
            Column() {
              if (chapter.isRead) {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              } else {
                Circle()
                  .width(8)
                  .height(8)
                  .fill(Color.Transparent)
                  .stroke(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .strokeWidth(1)
              }
            }
            .width(20)
            .justifyContent(FlexAlign.Center)

            // 中间：章节信息
            Column({ space: 4 }) {
              // 章节号 + 清理后的标题
              Row({ space: 6 }) {
                // 固定的章节号前缀
                Text(this.cleanChapterTitle(chapter.title, chapter.index)[0])
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(chapter.isRead 
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .flexShrink(0)
                
                // 清理后的真实标题
                Text(this.cleanChapterTitle(chapter.title, chapter.index)[1])
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                  .fontColor(chapter.isRead 
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              Row({ space: 12 }) {
                // 章节进度信息（从chapterProgressMap获取）
                Text(this.getChapterProgressText(chapter.id))
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                // 更新时间
                if (chapter.publishDate) {
                  Text(this.formatDate(chapter.publishDate))
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：状态图标/文字
            Row({ space: 6 }) {
              // 在线漫画显示"已下载"文字标记
              if (chapter.isDownloaded && !this.content?.isLocal) {
                Text('已下载')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '15')
                  .borderRadius(8)
              }
              if (chapter.isBookmarked) {
                SymbolGlyph($r('sys.symbol.bookmark_fill'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              }
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 小说章节列表（更直观的已读/未读状态）
   */
  @Builder
  buildNovelChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节序号和已读状态
            Column() {
              Text(`${chapter.index + 1}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontWeight(chapter.isRead ? FontWeight.Bold : FontWeight.Normal)
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(chapter.isRead 
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .justifyContent(FlexAlign.Center)

            // 中间：章节标题
            Column({ space: 2 }) {
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数和缓存状态
              Row({ space: 8 }) {
                if (chapter.wordCount) {
                  Text(`${chapter.wordCount}字`)
                    .fontSize(11)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                }
                if (chapter.isDownloaded) {
                  Row({ space: 2 }) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                      .fontSize(10)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                    Text('已缓存')
                      .fontSize(10)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  }
                }
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (chapter.isRead) {
              Text('已读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            } else if (chapter.index === this.content?.lastReadChapterIndex) {
              Text('阅读中')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 电子书章节列表
   */
  @Builder
  buildEBookChapterList() {
    List() {
      ForEach(this.getFilteredChapters(), (chapter: UnifiedChapter) => {
        ListItem() {
          Row({ space: 12 }) {
            // 左侧：章节信息
            Column({ space: 4 }) {
              // 章节标题
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(chapter.isRead ? FontWeight.Normal : FontWeight.Medium)
                .fontColor(chapter.isRead 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 字数信息
              if (chapter.wordCount && chapter.wordCount > 0) {
                Text(`${chapter.wordCount}字`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧：阅读状态标签
            if (chapter.isRead) {
              Text('已读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            } else if (chapter.index === this.content?.lastReadChapterIndex) {
              Text('阅读中')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
            }
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
          .onClick(() => this.startReading(chapter.index))
        }
      }, (chapter: UnifiedChapter) => chapter.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
  }

  /**
   * 格式化日期（支持时间戳和ISO字符串）
   */
  private formatDate(dateValue: string | number | undefined): string {
    if (!dateValue) return '';
    
    let timestamp: number;
    if (typeof dateValue === 'string') {
      // ISO字符串格式
      const parsed = Date.parse(dateValue);
      if (isNaN(parsed)) return '';
      timestamp = parsed;
    } else {
      timestamp = dateValue;
    }
    
    return this.formatRelativeTime(timestamp);
  }

  /**
   * 移除HTML标签和实体
   */
  private stripHtmlTags(text: string): string {
    if (!text) return text;
    return text
      .replace(/<br\s*\/?>/gi, '\n')  // 将<br>转换为换行
      .replace(/<\/p>/gi, '\n')       // 将</p>转换为换行
      .replace(/<[^>]*>/g, '')        // 移除所有HTML标签
      .replace(/&nbsp;/g, ' ')        // 转换空格实体
      .replace(/&amp;/g, '&')         // 转换&实体
      .replace(/&lt;/g, '<')          // 转换<实体
      .replace(/&gt;/g, '>')          // 转换>实体
      .replace(/&quot;/g, '"')        // 转换"实体
      .replace(/&#39;/g, "'")         // 转换'实体
      .replace(/\n\s*\n/g, '\n')      // 移除多余空行
      .trim();
  }

  /**
   * 格式化时间戳为相对时间
   */
  private formatRelativeTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    
    if (days === 0) return '今天';
    if (days === 1) return '昨天';
    if (days < 7) return `${days}天前`;
    if (days < 30) return `${Math.floor(days / 7)}周前`;
    if (days < 365) return `${Math.floor(days / 30)}月前`;
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }
  
  /**
   * 获取章节进度显示文本
   */
  private getChapterProgressText(chapterId: string): string {
    const progress = this.chapterProgressMap.get(chapterId);
    if (!progress) {
      return '页数未知';
    }
    
    const total = progress.totalPages;
    if (total <= 0) {
      return '页数未知';
    }
    
    const current = progress.lastReadPageIndex >= 0 ? (progress.lastReadPageIndex + 1) : 0;
    if (current > 0) {
      return `共 ${total} 页 • 已读 ${current}/${total}`;
    }
    return `共 ${total} 页 • 未开始`;
  }

  @Builder
  buildLoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(48)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])

      Text(this.errorMessage)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Button('重试')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .onClick(() => this.loadContent())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 打开封面预览（带动画）
   */
  private openCoverPreview(): void {
    if (!this.content?.coverUrl) {
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    
    // 初始化动画状态
    this.coverPreviewOpacity = 0;
    this.coverPreviewScale = 0.3;
    this.showCoverPreview = true;
    
    // 延迟执行动画，确保 UI 已渲染
    setTimeout(() => {
      animateTo({
        duration: 300,
        curve: curves.springMotion(0.6, 0.9)
      }, () => {
        this.coverPreviewOpacity = 1;
        this.coverPreviewScale = 1;
      });
    }, 16);
  }
  
  /**
   * 关闭封面预览（带动画）
   */
  private closeCoverPreview(): void {
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.coverPreviewOpacity = 0;
      this.coverPreviewScale = 0.3;
    });
    
    setTimeout(() => {
      this.showCoverPreview = false;
    }, 200);
  }

  /**
   * 封面预览弹窗
   */
  @Builder
  buildCoverPreviewOverlay() {
    Stack() {
      // 背景层：封面图片高斯模糊效果
      Stack() {
        // 封面图片作为背景（高斯模糊）
        if (this.coverPixelMap) {
          Image(this.coverPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .blur(50)
            .brightness(0.7)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: '100%',
            imageHeight: '100%',
            objectFit: ImageFit.Cover
          })
            .blur(50)
            .brightness(0.7)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        
        // 暗色遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.3)')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .opacity(this.coverPreviewOpacity)
      .onClick(() => this.closeCoverPreview())
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      
      // 封面图片（居中显示，带缩放动画）
      Column() {
        if (this.coverPixelMap) {
          Image(this.coverPixelMap)
            .width('100%')
            .height('70%')
            .objectFit(ImageFit.Contain)
        } else {
          AvifImage({
            src: this.getCoverImageSource() as string,
            imageWidth: '100%',
            imageHeight: '70%',
            objectFit: ImageFit.Contain
          })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.coverPreviewScale, y: this.coverPreviewScale })
      .opacity(this.coverPreviewOpacity)
      
      // 底部操作按钮（保存、分享、关闭）
      Row({ space: 24 }) {
        // 保存到相册
        Button() {
          Column({ space: 4 }) {
            if (this.isSavingCover) {
              LoadingProgress()
                .width(22)
                .height(22)
                .color(Color.White)
            } else {
              SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
                .fontSize(24)
                .fontColor([Color.White])
            }
            Text('保存')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .enabled(!this.isSavingCover)
        .onClick(() => this.saveCoverToGallery())
        
        // 分享
        Button() {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right'))
              .fontSize(24)
              .fontColor([Color.White])
            Text('分享')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .onClick(() => this.shareCover())
        
        // 关闭按钮
        Button() {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(24)
              .fontColor([Color.White])
            Text('关闭')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .width(70)
        .height(70)
        .backgroundColor('rgba(255,255,255,0.2)')
        .borderRadius(35)
        .onClick(() => this.closeCoverPreview())
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: this.navigationBarHeight + 32 })
      .position({ x: 0, y: '85%' })
      .opacity(this.coverPreviewOpacity)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  
  /**
   * 保存封面到相册
   * 使用 showAssetsCreationDialog 方式，无需申请权限
   */
  private async saveCoverToGallery(): Promise<void> {
    const coverUrl = this.content?.coverUrl || '';
    if (!coverUrl) {
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    
    this.isSavingCover = true;
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
      let localFilePath: string;
      
      // 判断是本地文件还是网络图片
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        // 网络图片：先下载到沙箱临时文件
        const httpRequest = http.createHttp();
        const response = await httpRequest.request(coverUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        httpRequest.destroy();
        
        if (response.responseCode !== 200) {
          throw new Error(`下载失败: ${response.responseCode}`);
        }
        
        const imageData = response.result as ArrayBuffer;
        localFilePath = `${context.cacheDir}/save_cover_${Date.now()}.jpg`;
        const tempFile = fs.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(tempFile.fd, imageData);
        fs.closeSync(tempFile);
      } else {
        // 本地文件：直接使用
        localFilePath = coverUrl.startsWith('file://') ? coverUrl.substring(7) : coverUrl;
      }
      
      // 获取文件后缀名
      const lastDotIndex = localFilePath.lastIndexOf('.');
      const fileExtension = lastDotIndex > 0 ? localFilePath.substring(lastDotIndex + 1) : 'jpg';
      
      // 转换为沙箱文件 URI
      const sandboxUri = fileUri.getUriFromPath(localFilePath);
      
      // 创建 photoAccessHelper
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      
      // 准备保存配置
      const srcFileUris: Array<string> = [sandboxUri];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: `cover_${this.content?.title || 'image'}`,
        fileNameExtension: fileExtension,
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }];
      
      // 显示保存对话框让用户确认
      const desFileUris: Array<string> = await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
      
      if (desFileUris.length > 0) {
        // 打开目标文件和源文件
        const destFile = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
        const srcFile = await fs.open(sandboxUri, fs.OpenMode.READ_ONLY);
        
        // 复制文件内容
        await fs.copyFile(srcFile.fd, destFile.fd);
        
        // 关闭文件
        fs.closeSync(destFile);
        fs.closeSync(srcFile);
        
        logger.info(TAG, `封面已保存到相册: ${desFileUris[0]}`);
        promptAction.showToast({ message: '已保存到相册', duration: 2000 });
      } else {
        logger.info(TAG, '用户取消保存');
      }
      
    } catch (error) {
      logger.error(TAG, `保存封面失败: ${String(error)}`);
      promptAction.showToast({ message: `保存失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isSavingCover = false;
    }
  }
  
  /**
   * 分享封面
   * 使用系统 Share Kit API
   */
  private async shareCover(): Promise<void> {
    const coverUrl = this.content?.coverUrl || '';
    if (!coverUrl) {
      promptAction.showToast({ message: '无封面图片', duration: 2000 });
      return;
    }
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
      let localFilePath: string;
      
      // 判断是本地文件还是网络图片
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        // 网络图片：先下载到临时文件
        const httpRequest = http.createHttp();
        const response = await httpRequest.request(coverUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER
        });
        httpRequest.destroy();
        
        if (response.responseCode !== 200) {
          throw new Error(`下载失败: ${response.responseCode}`);
        }
        
        const imageData = response.result as ArrayBuffer;
        localFilePath = `${context.cacheDir}/share_cover_${Date.now()}.jpg`;
        const tempFile = fs.openSync(localFilePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(tempFile.fd, imageData);
        fs.closeSync(tempFile);
      } else {
        // 本地文件：直接使用
        localFilePath = coverUrl.startsWith('file://') ? coverUrl.substring(7) : coverUrl;
      }
      
      // 转换为 URI
      const shareUri = fileUri.getUriFromPath(localFilePath);
      
      // 构建分享数据
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.JPEG,
        uri: shareUri,
        title: this.content?.title || '封面图片',
        description: `${this.content?.title || ''} - ${this.content?.author || ''}`
      });
      
      // 构建 ShareController
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      
      // 显示分享面板
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      
      logger.info(TAG, '封面分享成功');
      
    } catch (error) {
      logger.error(TAG, `分享封面失败: ${String(error)}`);
      promptAction.showToast({ message: `分享失败: ${String(error)}`, duration: 2000 });
    }
  }

  // ==================== 横屏布局 ====================

  /**
   * 横屏布局 - 左侧面板
   * 包含：封面图片、标题/作者、标签、简介、书架按钮
   */
  @Builder
  buildLandscapeLeftPanel() {
    Scroll() {
      Column({ space: 16 }) {
        // 封面图片
        Stack() {
          if (this.coverPixelMap) {
            Image(this.coverPixelMap)
              .width('100%')
              .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else if (this.content?.coverUrl) {
            AvifImage({
              src: this.getCoverImageSource() as string,
              imageWidth: '100%',
              imageHeight: undefined,
              objectFit: ImageFit.Cover,
              imageBorderRadius: 12
            })
              .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
          } else {
            Column() {
              SymbolGlyph($r('sys.symbol.text_book_closed'))
                .fontSize(48)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            }
            .width('100%')
            .aspectRatio(COVER_WIDTH / COVER_HEIGHT)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)
          }

          // 内容类型标签
          Text(this.getContentTypeName())
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor('rgba(0,0,0,0.6)')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .position({ x: 8, y: 8 })

          // 在线漫画封面刷新按钮
          if (this.isOnlineManga()) {
            Button() {
              if (this.isRefetchingCover) {
                LoadingProgress()
                  .width(16)
                  .height(16)
                  .color(Color.White)
              } else {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(14)
                  .fontColor([Color.White])
              }
            }
            .width(28)
            .height(28)
            .backgroundColor('rgba(0,0,0,0.5)')
            .borderRadius(14)
            .position({ right: 4, bottom: 4 })
            .enabled(!this.isRefetchingCover)
            .onClick(() => this.refetchCoverImage())
          }
        }
        .id(`cover_${this.componentId}`)
        .width('100%')
        .onClick(() => this.openCoverPreview())

        // 标题和作者
        Column({ space: 6 }) {
          Text(this.stripHtmlTags(this.content?.title || '加载中...'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.navigateToSearch(this.content?.title || '');
            })

          Text(this.stripHtmlTags(this.content?.author || ''))
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .onClick(() => {
              this.navigateToSearch(this.content?.author || '');
            })

          Row({ space: 8 }) {
            Text(this.getReadStatusText())
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text(`${this.content?.totalChapters || 0}章`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }

          if (this.content?.sourceName) {
            Text(`来源: ${this.content.sourceName}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 标签区域
        if (this.content && ((this.content.genres && this.content.genres.length > 0) || (this.content.tags && this.content.tags.length > 0))) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            ForEach(this.content.genres || [], (genre: string) => {
              Text(this.stripHtmlTags(genre))
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                .padding({ left: 8, right: 8 })
                .height(24)
                .borderRadius(12)
                .margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.navigateToSearch(genre);
                })
            }, (genre: string, index: number) => `ls_genre_${index}_${genre}`)

            ForEach(this.content.tags || [], (tag: string) => {
              Text(this.stripHtmlTags(tag))
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
                .padding({ left: 8, right: 8 })
                .height(24)
                .borderRadius(12)
                .margin({ right: 6, bottom: 6 })
                .onClick(() => {
                  this.navigateToSearch(tag);
                })
            }, (tag: string, index: number) => `ls_tag_${index}_${tag}`)
          }
          .width('100%')
        }

        // 简介
        Column({ space: 6 }) {
          Text('简介')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(this.stripHtmlTags(this.content?.description || '暂无简介'))
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(this.showFullDescription ? undefined : 4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .copyOption(CopyOptions.InApp)
            .onTextSelectionChange((start: number, end: number) => {
              const fullText = this.stripHtmlTags(this.content?.description || '');
              if (start >= 0 && end > start) {
                this.descriptionSelectedText = fullText.substring(start, end);
              }
            })
            .bindSelectionMenu(TextSpanType.TEXT, this.buildDescriptionSelectionMenu, TextResponseType.LONG_PRESS, {
              onDisappear: () => { this.descriptionSelectedText = ''; }
            })

          if (this.content?.description && this.content.description.length > 80) {
            Text(this.showFullDescription ? '收起' : '展开')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.showFullDescription = !this.showFullDescription;
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // 书架按钮
        if (this.isFromChangeSource && this.originalBookInfo) {
          Button('替换原小说')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            .fontColor(Color.White)
            .height(36)
            .width('100%')
            .borderRadius(18)
            .onClick(() => this.openReplaceBookDialog())
        } else {
          Button(this.isInShelf ? (this.currentShelfName ? `在「${this.currentShelfName}」书架中` : '在书架中') : '添加书架')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(this.isInShelf
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20'
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(this.isInShelf
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .height(36)
            .width('100%')
            .borderRadius(18)
            .onClick(() => this.showAddToShelfSelection())
        }

        // 同书架内容
        this.buildShelfContentSection()

        // 智能推荐
        this.buildRecommendationSection()

        Blank().height(16)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  /**
   * 横屏布局 - 右侧面板
   * 包含：工具栏、缓存状态卡片、章节列表，右下角浮动阅读按钮
   */
  @Builder
  buildLandscapeRightPanel() {
    Stack() {
      // 主内容区
      Column({ space: 12 }) {
        // 工具栏
        this.buildActionBar()

        // 缓存状态卡片
        this.buildCacheStatusCard()

        // 章节列表（占满剩余空间）
        Column() {
          this.buildChapterList()
        }
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, right: 16, top: 16, bottom: 16 })

      // 右下角浮动阅读按钮组
      Column({ space: 10 }) {
        Button((this.content?.lastReadChapterIndex ?? -1) >= 0 ? '继续阅读' : '开始阅读')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(Color.White)
          .height(44)
          .padding({ left: 24, right: 24 })
          .borderRadius(22)
          .shadow({
            radius: 12,
            color: 'rgba(0,0,0,0.15)',
            offsetX: 0,
            offsetY: 4
          })
          .onClick(() => this.continueReading())

        if (this.content?.contentType === UnifiedContentType.NOVEL) {
          Button('开始听书')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '22')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .height(40)
            .padding({ left: 20, right: 20 })
            .borderRadius(20)
            .onClick(() => this.continueReadAloud())
        }
      }
      .position({ right: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 横屏布局 - 主容器
   * 左侧封面信息 + 右侧章节列表
   */
  @Builder
  buildLandscapeLayout() {
    Row() {
      // 左侧面板（封面、标签、简介、书架按钮）
      Column() {
        this.buildLandscapeLeftPanel()
      }
      .width('38%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) + '80')
      .borderRadius({ topRight: 16, bottomRight: 16 })

      // 右侧面板（工具栏、章节列表、阅读按钮）
      Column() {
        this.buildLandscapeRightPanel()
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    NavDestination() {
      Stack() {
        // 隐藏的WebView用于执行在线电子书脚本
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: 0, y: 0 })
          .zIndex(-1)
          .onControllerAttached(() => {
            logger.info(TAG, '隐藏WebView控制器已附加');
            this.webViewControllerAttached = true;
            try {
              this.webViewManager.setGlobalWebViewController(this.webViewController);
            } catch (error) {
              logger.warn(TAG, `设置全局WebView控制器失败: ${String(error)}`);
            }
            if (this.pendingInitialContentLoad || !this.initialContentLoadTriggered) {
              this.triggerInitialContentLoadIfReady();
            }
          })
        
        // 背景层：封面图片毛玻璃效果
        Stack() {
          // 默认背景色（防止闪烁）
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
          // 封面图片作为背景（优先使用 PixelMap）
          if (this.coverPixelMap) {
            Image(this.coverPixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          } else if (this.content?.coverUrl) {
            // 回退到 AvifImage
            AvifImage({
              src: this.getCoverImageSource() as string,
              imageWidth: '100%',
              imageHeight: '100%',
              objectFit: ImageFit.Cover
            })
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .transition({ type: TransitionType.Insert, opacity: 0 })
              .animation({ duration: 300, curve: Curve.EaseOut })
          }
          // 渐变遮罩
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.2)' : 'rgba(245,245,245,0.2)', 0],
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.7)' : 'rgba(245,245,245,0.7)', 0.3],
                [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.6]
              ]
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage) {
          this.buildErrorView()
        } else if (this.responsive_isLandscape) {
          // 横屏布局：左侧封面信息 + 右侧章节列表
          this.buildLandscapeLayout()
        } else {
          // 竖屏布局：垂直滚动
          Refresh({ refreshing: $$this.isRefreshing }) {
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                // 刷新进度提示
                if (this.refreshProgress) {
                  Text(this.refreshProgress)
                    .fontSize(12)
                    .fontColor(this.themeState.currentTheme === ThemeType.DARK ? '#AAAAAA' : '#666666')
                    .padding({ top: 8, bottom: 8 })
                }
                
                this.buildHeader()
                this.buildDescription()
                this.buildActionBar()
                this.buildCacheStatusCard()
                this.buildShelfContentSection()
                this.buildRecommendationSection()
                this.buildChapterList()

                Blank().height(40)
              }
              .width('100%')
              .constraintSize({ maxWidth: this.responsive_maxContentWidth })
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
            }
            .width('100%')
            .height('100%')
            .align(Alignment.TopStart)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .onRefreshing(() => {
            this.onRefresh();
          })
          .width('100%')
          .height('100%')
        }
        
        // 封面预览弹窗
        if (this.showCoverPreview && this.content?.coverUrl) {
          this.buildCoverPreviewOverlay()
        }
        
        // 生成封面对话框
        this.buildGenerateCoverDialog()
        
        // 下载章节选择对话框
        this.buildDownloadDialog()
        
        // 换源对话框
        this.buildChangeSourceDialog()
        
        // 添加书架选择对话框
        this.buildAddToShelfDialog()
        
        // 替换小说对话框
        this.buildReplaceBookDialog()
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as UnifiedDetailPageParams;
      if (params) {
        this.pageParams = params;
        this.pendingInitialContentLoad = false;
        this.initialContentLoadTriggered = false;
        this.triggerInitialContentLoadIfReady();
      }
    })
    .onShown(() => {
      // 页面显示时刷新阅读记录（从阅读器返回时）
      this.refreshReadingProgress();
    })
    .backgroundColor(Color.Transparent)
  }
  
  /**
   * 刷新阅读进度（页面返回时调用）
   */
  private async refreshReadingProgress(): Promise<void> {
    if (!this.content || !this.pageParams) return;
    
    try {
      logger.info(TAG, `刷新阅读进度: ${this.content.contentType}`);
      
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          await this.refreshMangaReadingProgress();
          break;
        case UnifiedContentType.EBOOK:
          await this.refreshEBookReadingProgress();
          break;
        case UnifiedContentType.NOVEL:
          await this.refreshNovelReadingProgress();
          break;
      }
    } catch (error) {
      logger.error(TAG, `刷新阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新漫画阅读进度
   */
  private async refreshMangaReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    const mangaId = this.content.id;
    const isOnline = this.content.sourceId !== undefined && Number(this.content.sourceId) > 0;
    const chapters = this.content.chapters.map(ch => {
      const originalChapter = MangaAdapter.getOriginalChapter(ch);
      return originalChapter as MangaChapter;
    }).filter(ch => ch !== null);
    
    if (chapters.length === 0) return;
    
    // 重新加载章节进度
    const progressData = await this.mangaDetailLoader.loadChapterProgressData(mangaId, chapters, isOnline);
    
    // 更新章节进度Map
    const newProgressMap = new Map<string, ChapterProgressInfo>();
    progressData.progressList.forEach((progress: ChapterProgressInfo) => {
      newProgressMap.set(progress.chapterId, progress);
    });
    this.chapterProgressMap = newProgressMap;
    
    // 更新章节已读状态
    const updatedChapters: UnifiedChapter[] = [];
    for (let i = 0; i < this.content.chapters.length; i++) {
      const ch = this.content.chapters[i];
      const isRead = progressData.readChapterIds.has(ch.id);
      const updatedChapter: UnifiedChapter = {
        id: ch.id,
        title: ch.title,
        index: ch.index,
        isRead: isRead,
        isDownloaded: ch.isDownloaded,
        isBookmarked: ch.isBookmarked,
        pageCount: ch.pageCount,
        publishDate: ch.publishDate,
        originalData: ch.originalData,
        originalType: ch.originalType
      };
      updatedChapters.push(updatedChapter);
    }
    
    // 更新content（显式赋值而不是spread）
    this.content.chapters = updatedChapters;
    this.content.readChapters = progressData.readChapterIds.size;
    this.content.lastReadChapterIndex = progressData.lastReadChapterIndex;
    this.content.readProgress = this.content.totalChapters > 0 
      ? Math.round((progressData.readChapterIds.size / this.content.totalChapters) * 100) 
      : 0;
    
    logger.info(TAG, `漫画阅读进度已刷新: 已读${progressData.readChapterIds.size}章`);
  }
  
  /**
   * 刷新电子书阅读进度
   */
  private async refreshEBookReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    try {
      const ebook: EBook | null = await this.ebookDataManager.getEBookById(this.content.id);
      if (ebook) {
        const currentChapterIndex: number = ebook.readingProgress?.currentChapterIndex || 0;
        const progress: number = ebook.readingProgress?.progress || 0;
        
        this.content.lastReadChapterIndex = currentChapterIndex;
        this.content.lastReadChapterTitle = currentChapterIndex < (ebook.chapters?.length || 0) 
          ? ebook.chapters![currentChapterIndex].title 
          : '';
        // progress已经是0-100的百分比值，不需要再乘以100
        this.content.readProgress = Math.round(progress);
        
        logger.info(TAG, `电子书阅读进度已刷新: 章节${currentChapterIndex}, 进度${progress}%`);
      }
    } catch (error) {
      logger.error(TAG, `刷新电子书阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新小说阅读进度
   */
  private async refreshNovelReadingProgress(): Promise<void> {
    if (!this.content) return;
    
    try {
      const novelBook: NovelBook | null = await this.novelDataManager.getBookByUrl(
        this.content.sourceId || '', 
        this.content.id
      );
      
      if (novelBook) {
        const lastChapterIndex: number = novelBook.lastReadChapterIndex || 0;
        const readChapters: number = novelBook.chapterCount || 0;
        
        this.content.lastReadChapterIndex = lastChapterIndex;
        this.content.readChapters = readChapters;
        this.content.readProgress = this.content.totalChapters > 0 
          ? Math.round((readChapters / this.content.totalChapters) * 100) 
          : 0;
        
        logger.info(TAG, `小说阅读进度已刷新: 章节${lastChapterIndex}, 已读${readChapters}章`);
      }
    } catch (error) {
      logger.error(TAG, `刷新小说阅读进度失败: ${String(error)}`);
    }
  }
  
  /**
   * 显示生成封面提示对话框
   */
  private showGenerateCoverPrompt(): void {
    this.coverTitleInput = this.content?.title || '';
    this.coverFontScale = 1.0;
    
    // 重置动画状态
    this.dialogOpacity = 0;
    this.dialogScale = 0.8;
    this.dialogTranslateY = 30;
    
    // 显示对话框
    this.showGenerateCoverDialog = true;
    
    // 触发入场动画（使用弹簧动画）
    animateTo({
      duration: 350,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.dialogOpacity = 1;
      this.dialogScale = 1;
      this.dialogTranslateY = 0;
    });
  }
  
  /**
   * 生成封面
   */
  private async generateCoverForContent(): Promise<void> {
    if (!this.content || !this.coverTitleInput.trim()) {
      promptAction.showToast({ message: '请输入标题', duration: 2000 });
      return;
    }
    
    this.isGeneratingCover = true;
    this.showGenerateCoverDialog = false;
    
    try {
      logger.info(TAG, `开始生成封面: ${this.coverTitleInput}`);
      
      const coverPath = await this.coverGenerator.generateCover(
        this.content.id,
        this.coverTitleInput,
        () => { this.buildCoverForSnapshot(this.coverTitleInput); }
      );
      
      if (coverPath) {
        await this.updateContentCover(coverPath);
        // 强制刷新封面显示
        this.coverRefreshKey = Date.now();
        promptAction.showToast({ message: '封面生成成功', duration: 2000 });
        logger.info(TAG, `封面生成成功: ${coverPath}`);
      } else {
        promptAction.showToast({ message: '封面生成失败', duration: 2000 });
        logger.warn(TAG, '封面生成失败');
      }
    } catch (error) {
      logger.error(TAG, `生成封面异常: ${String(error)}`);
      promptAction.showToast({ message: `生成失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isGeneratingCover = false;
    }
  }
  
  /**
   * 更新内容封面
   */
  private async updateContentCover(coverPath: string): Promise<void> {
    if (!this.content) return;
    
    try {
      if (this.content.contentType === UnifiedContentType.EBOOK) {
        await this.ebookDataManager.updateEBookCover(this.content.id, coverPath);
        this.content.coverUrl = coverPath;
        logger.info(TAG, '电子书封面已更新');
        // 发送事件通知书库页面刷新
        const ebookPayload: CoverChangedPayload = { 
          bookId: this.content.id, 
          coverPath: coverPath 
        };
        eventBus.publish(GameEvent.EBOOK_COVER_CHANGED, ebookPayload);
      } else if (this.content.contentType === UnifiedContentType.NOVEL) {
        const novel = await this.novelDataManager.getBookByUrl(
          this.content.sourceId || '',
          this.content.id
        );
        if (novel) {
          // 本地生成的封面应该存储在coverLocalPath字段
          novel.coverLocalPath = coverPath;
          await this.novelDataManager.saveBook(novel);
          this.content.coverUrl = coverPath;
          logger.info(TAG, '小说封面已更新');
          // 发送事件通知书库页面刷新
          const novelPayload: CoverChangedPayload = { 
            bookId: this.content.id, 
            coverPath: coverPath 
          };
          eventBus.publish(GameEvent.NOVEL_COVER_CHANGED, novelPayload);
        }
      }
    } catch (error) {
      logger.error(TAG, `更新封面失败: ${String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 构建封面组件（用于componentSnapshot）
   */
  @Builder
  buildCoverForSnapshot(title: string) {
    Stack() {
      Image($r('app.media.ebook'))
        .width(COVER_WIDTH)
        .height(COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      Text(this.formatCoverTitle(title))
        .fontFamily(this.appFontFamily)
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(COVER_WIDTH * (UnifiedDetailPage.TITLE_AREA_RIGHT_PERCENT - UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT - UnifiedDetailPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: COVER_WIDTH * UnifiedDetailPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: COVER_HEIGHT * (UnifiedDetailPage.TITLE_AREA_TOP_PERCENT + UnifiedDetailPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(COVER_WIDTH)
    .height(COVER_HEIGHT)
  }
  
  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }
  
  /**
   * 计算封面字体大小
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    let baseSize = 24;
    if (length <= 2) baseSize = 70;
    else if (length <= 4) baseSize = 56;
    else if (length <= 6) baseSize = 48;
    else if (length <= 8) baseSize = 36;
    else if (length <= 12) baseSize = 32;
    else if (length <= 16) baseSize = 28;
    
    return baseSize * this.coverFontScale;
  }
  
  /**
   * 关闭生成封面对话框（带动画）
   */
  private closeGenerateCoverDialog(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.dialogOpacity = 0;
      this.dialogScale = 0.8;
      this.dialogTranslateY = 30;
    });
    
    setTimeout(() => {
      this.showGenerateCoverDialog = false;
    }, 250);
  }
  
  /**
   * 单章节下载视图（针对只有1章的漫画）
   */
  @Builder
  buildSingleChapterDownloadView() {
    Column({ space: 16 }) {
      // 章节信息卡片
      Row({ space: 12 }) {
        // 章节图标
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext_2'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        }
        .width(48)
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        
        // 章节信息
        Column({ space: 4 }) {
          Text(this.content?.chapters[0]?.title || '第1章')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          
          Row({ space: 8 }) {
            if (this.content?.chapters[0]?.pageCount && this.content.chapters[0].pageCount > 0) {
              Text(`${this.content.chapters[0].pageCount} 页`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            
            if (this.content?.chapters[0]?.isDownloaded) {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                  .fontSize(12)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                Text('已缓存')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              }
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
      
      // 提示文字
      if (this.content?.chapters[0]?.isDownloaded) {
        Text('该章节已缓存，可离线阅读')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Text('点击下载按钮缓存该章节，缓存后可离线阅读')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
  }
  
  /**
   * 下载章节选择对话框
   */
  @Builder
  buildDownloadDialog() {
    if (this.showDownloadDialog && this.content) {
      Column() {
        // 对话框内容
        Column({ space: 16 }) {
          // 标题栏
          Row() {
            Text(this.content.contentType === UnifiedContentType.NOVEL ? '缓存章节' : '缓存章节')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            Blank()
            
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.closeDownloadDialog())
          }
          .width('100%')
          
          // 根据章节数量显示不同的UI
          if (this.content.chapters.length === 1) {
            // 单章节漫画：简化UI
            this.buildSingleChapterDownloadView()
          } else {
            // 多章节：显示完整的选择界面
            // 选择模式切换
            Row({ space: 8 }) {
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.slider_horizontal_2_1'))
                    .fontSize(14)
                    .fontColor([this.downloadSelectionMode === 'range' 
                      ? Color.White 
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  Text('区间选择')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.downloadSelectionMode === 'range' 
                      ? Color.White 
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.downloadSelectionMode === 'range' 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(18)
              .animation({ duration: 200, curve: Curve.EaseOut })
              .onClick(() => {
                animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.downloadSelectionMode = 'range';
                });
              })
              
              Button() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(14)
                    .fontColor([this.downloadSelectionMode === 'individual' 
                      ? Color.White 
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                  Text('单独选择')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.downloadSelectionMode === 'individual' 
                      ? Color.White 
                      : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
              }
              .height(36)
              .padding({ left: 14, right: 14 })
              .backgroundColor(this.downloadSelectionMode === 'individual' 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(18)
              .animation({ duration: 200, curve: Curve.EaseOut })
              .onClick(() => {
                animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.downloadSelectionMode = 'individual';
                  // 单独选择模式默认展开章节列表
                  this.downloadChapterListExpanded = true;
                });
              })
            }
            .width('100%')
            
            // 区间选择模式
            if (this.downloadSelectionMode === 'range') {
            Column({ space: 12 }) {
              // 区间显示
              Row() {
                Text(`第 ${this.downloadRangeStart + 1} 章`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                
                Text(' — ')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                Text(`第 ${this.downloadRangeEnd + 1} 章`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                
                Blank()
                
                Text(`共 ${this.downloadRangeEnd - this.downloadRangeStart + 1} 章`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')
              
              // 开始位置滑块
              Column({ space: 4 }) {
                Text('开始章节')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                Slider({
                  value: this.downloadRangeStart,
                  min: 0,
                  max: this.content.chapters.length - 1,
                  step: 1,
                  style: SliderStyle.OutSet
                })
                  .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .onChange((value: number) => {
                    this.downloadRangeStart = Math.round(value);
                    if (this.downloadRangeStart > this.downloadRangeEnd) {
                      this.downloadRangeEnd = this.downloadRangeStart;
                    }
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              
              // 结束位置滑块
              Column({ space: 4 }) {
                Text('结束章节')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                Slider({
                  value: this.downloadRangeEnd,
                  min: 0,
                  max: this.content.chapters.length - 1,
                  step: 1,
                  style: SliderStyle.OutSet
                })
                  .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .onChange((value: number) => {
                    this.downloadRangeEnd = Math.round(value);
                    if (this.downloadRangeEnd < this.downloadRangeStart) {
                      this.downloadRangeStart = this.downloadRangeEnd;
                    }
                  })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              
              // 快捷选择按钮
              Row({ space: 8 }) {
                Button('全部')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    animateTo({ duration: 150 }, () => {
                      this.downloadRangeStart = 0;
                      this.downloadRangeEnd = this.content!.chapters.length - 1;
                    });
                  })
                
                Button('前50章')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    animateTo({ duration: 150 }, () => {
                      this.downloadRangeStart = 0;
                      this.downloadRangeEnd = Math.min(49, this.content!.chapters.length - 1);
                    });
                  })
                
                Button('后50章')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    animateTo({ duration: 150 }, () => {
                      const total = this.content!.chapters.length;
                      this.downloadRangeStart = Math.max(0, total - 50);
                      this.downloadRangeEnd = total - 1;
                    });
                  })
              }
              .width('100%')
            }
            .width('100%')
            .animation({ duration: 200, curve: Curve.EaseOut })
          } else {
            // 单独选择模式
            Column({ space: 8 }) {
              Row() {
                Text(`已选择 ${this.downloadSelectedChapters.size} 章`)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                
                Blank()
                
                Button(this.downloadChapterListExpanded ? '收起' : '展开列表')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                      this.downloadChapterListExpanded = !this.downloadChapterListExpanded;
                    });
                  })
              }
              .width('100%')
              
              // 章节列表
              if (this.downloadChapterListExpanded) {
                List() {
                  ForEach(this.content.chapters, (chapter: UnifiedChapter, index: number) => {
                    ListItem() {
                      Row() {
                        Checkbox({ name: `chapter_${index}` })
                          .select(this.downloadSelectedChapters.has(index))
                          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                          .enabled(!chapter.isDownloaded)  // 已缓存章节禁用选择
                          .hitTestBehavior(HitTestMode.Block)  // 阻止事件穿透到Row
                          .onChange((checked: boolean) => {
                            // 已缓存章节不可选中
                            if (chapter.isDownloaded) return;
                            
                            const newSet = new Set(this.downloadSelectedChapters);
                            if (checked) {
                              newSet.add(index);
                            } else {
                              newSet.delete(index);
                            }
                            this.downloadSelectedChapters = newSet;
                          })
                        
                        Text(`${index + 1}. ${chapter.title}`)
                          .fontSize(13)
                          .fontFamily(this.appFontFamily)
                          .fontColor(chapter.isDownloaded 
                            ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .layoutWeight(1)
                        
                        if (chapter.isDownloaded) {
                          Text('已缓存')
                            .fontSize(11)
                            .fontFamily(this.appFontFamily)
                            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                        }
                      }
                      .width('100%')
                      .height(40)
                      .padding({ left: 8, right: 8 })
                      .backgroundColor(this.downloadSelectedChapters.has(index) 
                        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15'
                        : Color.Transparent)
                      .borderRadius(8)
                      .enabled(!chapter.isDownloaded)  // 已缓存章节整行不可点击
                      .opacity(chapter.isDownloaded ? 0.5 : 1)  // 已缓存章节半透明
                      .onClick(() => this.toggleChapterSelection(index))
                    }
                  }, (chapter: UnifiedChapter, index: number) => `dl_chapter_${index}_${chapter.id}_${this.downloadSelectedChapters.has(index)}`)
                }
                .width('100%')
                .height(200)
                .scrollBar(BarState.Auto)
                .edgeEffect(EdgeEffect.Spring)
                .cachedCount(10)  // 缓存列表项，提升滚动性能
              }
              
              // 快捷选择
              Row({ space: 8 }) {
                Button('全选')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    // 全选只选中未缓存的章节
                    const newSet = new Set<number>();
                    this.content!.chapters.forEach((ch, idx) => {
                      if (!ch.isDownloaded) {
                        newSet.add(idx);
                      }
                    });
                    this.downloadSelectedChapters = newSet;
                  })
                
                Button('全不选')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .height(28)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .borderRadius(14)
                  .onClick(() => {
                    this.downloadSelectedChapters = new Set();
                  })
              }
              .width('100%')
            }
            .width('100%')
            .animation({ duration: 200, curve: Curve.EaseOut })
          }
          }  // 多章节UI结束
          
          // 底部按钮
          Row({ space: 12 }) {
            Button()
            {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(16)
                  .fontColor([Color.White])
                Text(`清除缓存`)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .height(44)
              .backgroundColor('#FF5252')
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => {
                this.closeDownloadDialog();
                if (this.content?.contentType === UnifiedContentType.NOVEL) {
                  this.clearNovelCache();
                } else {
                  this.clearMangaCache();
                }
              })
            
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.arrow_down_circle'))
                  .fontSize(16)
                  .fontColor([Color.White])
                Text(`缓存 ${this.getSelectedChapterCount()} 章`)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .layoutWeight(2)
            .borderRadius(22)
            .onClick(() => this.executeDownloadSelected())
          }
          .width('100%')
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(16)
        .scale({ x: this.downloadDialogScale, y: this.downloadDialogScale })
        .translate({ y: this.downloadDialogTranslateY })
        .opacity(this.downloadDialogOpacity)
        .shadow({
          radius: 20,
          color: 'rgba(0,0,0,0.2)',
          offsetX: 0,
          offsetY: 10
        })
        .onClick(() => {
          // 空处理器阻止点击事件冒泡到背景
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(`rgba(0,0,0,${0.5 * this.downloadDialogOpacity})`)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.closeDownloadDialog())
    }
  }
  
  /**
   * 打开换源对话框
   */
  private openChangeSourceDialog(): void {
    if (!this.content || this.content.contentType !== UnifiedContentType.NOVEL) return;
    
    // 初始化搜索关键词
    this.changeSourceKeyword = this.content.title;
    
    // 显示对话框（带动画）
    this.showChangeSourceDialog = true;
    animateTo({
      duration: 350,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.changeSourceDialogOpacity = 1;
      this.changeSourceDialogScale = 1;
      this.changeSourceDialogTranslateY = 0;
    });
    
    // 开始搜索（使用缓存）
    this.startChangeSourceSearch(false);
  }
  
  /**
   * 开始换源搜索
   * @param forceRefresh 是否强制刷新（手动点击搜索按钮时为true）
   */
  private startChangeSourceSearch(forceRefresh: boolean = false): void {
    // 取消之前的搜索任务
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
    }
    
    const keyword = this.changeSourceKeyword.trim();
    if (!keyword) {
      promptAction.showToast({ message: '请输入搜索关键词' });
      return;
    }
    
    const bookAuthor = this.content?.author;
    
    // 检查缓存（非强制刷新模式）
    if (!forceRefresh) {
      const cached = this.sourceSearchService.getCachedResults(keyword, bookAuthor);
      if (cached) {
        // 使用缓存结果
        this.alternativeSources = cached.results;
        this.alternativeSourceResults = cached.sourceResults;
        this.searchSourceCompleted = cached.sourceResults.length;
        this.searchSourceTotal = cached.sourceResults.length;
        this.searchSourceProgress = 100;
        this.isSearchingSource = false;
        logger.info(TAG, `使用缓存的换源搜索结果: ${keyword}`);
        return;
      }
    } else {
      // 强制刷新时清除缓存
      this.sourceSearchService.clearCache(keyword, bookAuthor);
    }
    
    // 重置状态
    this.isSearchingSource = true;
    this.alternativeSources = [];
    this.alternativeSourceResults = [];
    this.searchSourceCompleted = 0;
    this.searchSourceTotal = this.sourceSearchService.getSearchableSourceCount();
    this.searchSourceProgress = 0;
    
    logger.info(TAG, `开始换源搜索: ${keyword}, 共 ${this.searchSourceTotal} 个书源`);
    
    // 使用换源搜索服务，传入 0 表示不限制书源数量
    this.searchTaskHandle = this.sourceSearchService.searchForSource(
      keyword,
      bookAuthor,
      {
        onSourceComplete: (sourceResult: SourceSearchResult) => {
          // 实时更新结果
          this.alternativeSourceResults = [...this.alternativeSourceResults, sourceResult];
          this.alternativeSources = [...this.alternativeSources, ...sourceResult.results];
        },
        onProgress: (completed: number, total: number) => {
          this.searchSourceCompleted = completed;
          this.searchSourceTotal = total;
          this.searchSourceProgress = total > 0 ? Math.round((completed / total) * 100) : 0;
        },
        onComplete: (allResults: NovelSearchResult[], sourceResults: SourceSearchResult[]) => {
          this.isSearchingSource = false;
          this.searchSourceProgress = 100;
          this.searchTaskHandle = null;
          logger.info(TAG, `换源搜索完成: 共 ${sourceResults.length} 个书源有结果`);
        },
        onCancelled: () => {
          this.isSearchingSource = false;
          this.searchTaskHandle = null;
          logger.info(TAG, '换源搜索已取消');
        }
      },
      0  // 传入 0 表示搜索所有启用的书源
    );
  }
  
  /**
   * 关闭换源对话框（带动画）
   */
  private closeChangeSourceDialog(): void {
    // 取消搜索
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
    this.isSearchingSource = false;
    
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.changeSourceDialogOpacity = 0;
      this.changeSourceDialogScale = 0.8;
      this.changeSourceDialogTranslateY = 30;
    });
    
    setTimeout(() => {
      this.showChangeSourceDialog = false;
    }, 250);
  }
  
  /**
   * 切换小说书源
   */
  private async changeNovelSource(source: NovelSearchResult): Promise<void> {
    if (!this.content) return;
    
    logger.info(TAG, `切换书源: ${source.sourceName}`);
    
    // 保存原书信息（只要进行了换源操作，就允许替换）
    let originalInfo: OriginalBookInfo | null = null;
    let originalShelfId: string = '';  // 原书所在的书架ID
    if (this.content.contentType === UnifiedContentType.NOVEL) {
      // 获取原书的详细信息（尝试多种方式查询）
      const sourceId = this.content.sourceId || this.pageParams?.sourceId || '';
      let bookInDb = await this.novelDataManager.getBookByUrl(sourceId, this.content.id);
      
      // 如果找不到，尝试用构建ID查询
      if (!bookInDb) {
        const constructedId = `${sourceId}_${this.content.id}`;
        bookInDb = await this.novelDataManager.getBook(constructedId);
        logger.info(TAG, `通过构建ID查询原书: ${constructedId}, 结果: ${bookInDb ? '找到' : '未找到'}`);
      }
      
      // 查找原书所在的书架
      if (bookInDb) {
        const allShelves = this.typeShelfManager.getShelves();
        // 使用完整的novel.id格式查找（${sourceId}_${bookUrl}）
        const originalBookId = bookInDb.id;
        for (const shelf of allShelves) {
          if (shelf.isSystem) continue;
          const itemIds = this.typeShelfManager.getShelfItemIdsByType(shelf.id, ContentType.NOVEL);
          if (itemIds.includes(originalBookId)) {
            originalShelfId = shelf.id;
            logger.info(TAG, `原书在书架: ${shelf.name} (${shelf.id}), bookId=${originalBookId}`);
            break;
          }
        }
      }
      
      // 获取原书最后阅读章节标题
      let lastReadChapterTitle = '';
      if (this.content.lastReadChapterIndex >= 0 && this.content.lastReadChapterIndex < this.content.chapters.length) {
        lastReadChapterTitle = this.content.chapters[this.content.lastReadChapterIndex].title;
      }
      
      originalInfo = {
        bookId: bookInDb?.id || '',
        bookUrl: this.content.id,
        sourceId: sourceId,
        sourceName: this.content.sourceName || '',
        name: this.content.title,
        author: this.content.author,
        coverUrl: this.content.coverUrl,
        lastReadChapterIndex: bookInDb?.lastReadChapterIndex ?? this.content.lastReadChapterIndex,
        lastReadChapterTitle: lastReadChapterTitle,
        lastReadPosition: bookInDb?.lastReadPosition || 0,
        chapterCount: this.content.totalChapters,
        isFavorite: bookInDb?.isFavorite || this.isFavorite,
        shelfId: originalShelfId  // 保存原书所在书架
      };
      logger.info(TAG, `保存原书信息: ${originalInfo.name}, 阅读至第${originalInfo.lastReadChapterIndex}章, 原书收藏状态=${originalInfo.isFavorite}, 书架ID=${originalShelfId}`);
    }
    
    // 关闭对话框
    this.closeChangeSourceDialog();
    
    // 显示加载状态
    this.isLoading = true;
    
    try {
      // 设置换源标记和原书信息
      this.isFromChangeSource = originalInfo !== null;
      this.originalBookInfo = originalInfo;
      
      // 更新页面参数
      if (this.pageParams) {
        this.pageParams.sourceId = source.sourceId;
        this.pageParams.contentId = source.bookUrl;
        this.pageParams.isFromChangeSource = this.isFromChangeSource;
        this.pageParams.originalBookInfo = originalInfo || undefined;
      }
      
      // 重新加载内容
      await this.loadContent();
      
      if (this.isFromChangeSource) {
        promptAction.showToast({ message: `已切换到: ${source.sourceName}，点“替换原小说”按钮进行替换` });
      } else {
        promptAction.showToast({ message: `已切换到: ${source.sourceName}` });
      }
    } catch (error) {
      logger.error(TAG, `切换书源失败: ${String(error)}`);
      promptAction.showToast({ message: '切换失败，请重试' });
      // 失败时重置换源标记
      this.isFromChangeSource = false;
      this.originalBookInfo = null;
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 打开替换小说对话框
   */
  private openReplaceBookDialog(): void {
    if (!this.content || !this.originalBookInfo) return;
    
    // 计算章节匹配
    this.matchedChapterIndex = this.findMatchingChapterIndex(
      this.originalBookInfo.lastReadChapterTitle,
      this.originalBookInfo.lastReadChapterIndex
    );
    
    logger.info(TAG, `打开替换对话框: 原章节=${this.originalBookInfo.lastReadChapterIndex}, 匹配章节=${this.matchedChapterIndex}`);
    
    // 显示对话框
    this.showReplaceBookDialog = true;
    animateTo({
      duration: 350,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.replaceDialogOpacity = 1;
      this.replaceDialogScale = 1;
      this.replaceDialogTranslateY = 0;
    });
  }
  
  /**
   * 关闭替换小说对话框
   */
  private closeReplaceBookDialog(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.replaceDialogOpacity = 0;
      this.replaceDialogScale = 0.8;
      this.replaceDialogTranslateY = 30;
    });
    
    setTimeout(() => {
      this.showReplaceBookDialog = false;
    }, 250);
  }
  
  /**
   * 章节匹配算法
   * 根据原书的阅读位置在新书中找到对应章节
   */
  private findMatchingChapterIndex(originalChapterTitle: string, originalChapterIndex: number): number {
    if (!this.content || this.content.chapters.length === 0) {
      return -1;
    }
    
    // 1. 精确匹配：章节标题完全相同
    for (let i = 0; i < this.content.chapters.length; i++) {
      if (this.content.chapters[i].title === originalChapterTitle) {
        logger.info(TAG, `精确匹配章节: "${originalChapterTitle}" -> 第${i}章`);
        return i;
      }
    }
    
    // 2. 模糊匹配：章节标题包含关系
    const normalizedOriginal = this.normalizeChapterTitle(originalChapterTitle);
    for (let i = 0; i < this.content.chapters.length; i++) {
      const normalizedNew = this.normalizeChapterTitle(this.content.chapters[i].title);
      if (normalizedOriginal === normalizedNew ||
          normalizedNew.includes(normalizedOriginal) ||
          normalizedOriginal.includes(normalizedNew)) {
        logger.info(TAG, `模糊匹配章节: "${originalChapterTitle}" -> "${this.content.chapters[i].title}" (第${i}章)`);
        return i;
      }
    }
    
    // 3. 序号回退：使用相同索引或最近的索引
    if (originalChapterIndex >= 0) {
      if (originalChapterIndex < this.content.chapters.length) {
        logger.info(TAG, `序号回退匹配: 第${originalChapterIndex}章`);
        return originalChapterIndex;
      }
      // 如果原索引超出范围，返回最后一章
      logger.info(TAG, `序号回退匹配(超出范围): 第${this.content.chapters.length - 1}章`);
      return this.content.chapters.length - 1;
    }
    
    return -1;
  }
  
  /**
   * 标准化章节标题（用于模糊匹配）
   */
  private normalizeChapterTitle(title: string): string {
    return title
      .replace(/\s+/g, '')  // 移除空白
      .replace(/[，。！？、：；“”‘’【】《》「」『』—…]/g, '')  // 移除中文标点
      .replace(/[,.!?;:"'\[\]<>\-\.]/g, '')  // 移除英文标点
      .toLowerCase();
  }
  
  /**
   * 执行替换小说
   */
  private async executeReplaceBook(): Promise<void> {
    if (!this.content || !this.originalBookInfo) return;
    
    this.closeReplaceBookDialog();
    this.isLoading = true;
    
    try {
      const originalInfo = this.originalBookInfo;
      const newSourceId = this.content.sourceId || this.pageParams?.sourceId || '';
      const newBookUrl = this.content.id;
      
      logger.info(TAG, `开始替换小说: ${originalInfo.name} -> ${this.content.title}`);
      logger.info(TAG, `新书源信息: sourceId=${newSourceId}, bookUrl=${newBookUrl}`);
      
      // 1. 获取新书信息（尝试多种方式查询）
      let newBookInDb = await this.novelDataManager.getBookByUrl(newSourceId, newBookUrl);
      
      // 如果找不到，尝试用构建ID查询
      if (!newBookInDb) {
        const constructedId = `${newSourceId}_${newBookUrl}`;
        newBookInDb = await this.novelDataManager.getBook(constructedId);
        logger.info(TAG, `通过构建ID查询: ${constructedId}, 结果: ${newBookInDb ? '找到' : '未找到'}`);
      }
      
      // 2. 计算新的阅读位置
      const newLastReadIndex = this.matchedChapterIndex >= 0 ? this.matchedChapterIndex : 0;
      const newLastReadChapterId = newLastReadIndex < this.content.chapters.length 
        ? this.content.chapters[newLastReadIndex].id 
        : '';
      
      // 3. 更新或创建新书的收藏状态和阅读进度
      if (newBookInDb) {
        // 更新现有记录
        newBookInDb.isFavorite = true;
        newBookInDb.lastReadChapterIndex = newLastReadIndex;
        newBookInDb.lastReadChapterId = newLastReadChapterId;
        newBookInDb.lastReadPosition = 0;  // 重置位置，从章节开头开始
        newBookInDb.lastReadTime = Date.now();
        newBookInDb.readStatus = originalInfo.lastReadChapterIndex >= 0 ? NovelReadStatus.READING : NovelReadStatus.UNREAD;
        await this.novelDataManager.saveBook(newBookInDb);
        logger.info(TAG, `新书已更新: isFavorite=true, lastReadIndex=${newLastReadIndex}`);
      } else {
        // 创建新记录（理论上 loadNovelContent 应该已经创建，但以防万一）
        logger.warn(TAG, `未找到新书记录，创建新记录`);
        const now = Date.now();
        const newBook: NovelBook = {
          id: `${newSourceId}_${newBookUrl}`,
          sourceId: newSourceId,
          sourceName: this.content.sourceName || '',
          bookUrl: newBookUrl,
          name: this.content.title,
          author: this.content.author,
          intro: this.content.description,
          coverUrl: this.content.coverUrl,
          chapterCount: this.content.totalChapters,
          readStatus: originalInfo.lastReadChapterIndex >= 0 ? NovelReadStatus.READING : NovelReadStatus.UNREAD,
          totalReadingTime: 0,
          isFavorite: true,
          lastReadChapterIndex: newLastReadIndex,
          lastReadChapterId: newLastReadChapterId,
          lastReadPosition: 0,
          lastReadTime: now,
          createTime: now,
          updateDbTime: now
        };
        await this.novelDataManager.saveBook(newBook);
        logger.info(TAG, `新书已创建: ${newBook.name}, lastReadIndex=${newLastReadIndex}`);
      }
      
      // 4. 确保章节列表已缓存（避免返回书架后重新加载）
      if (this.content.chapters.length > 0) {
        const originalNovel = NovelAdapter.getOriginalNovel(this.content);
        if (originalNovel) {
          const legadoChapters: LegadoChapter[] = this.content.chapters.map((ch: UnifiedChapter) => {
            const original = NovelAdapter.getOriginalChapter(ch);
            return original || { title: ch.title, url: ch.id } as LegadoChapter;
          });
          await this.novelCacheManager.saveChapterList(newBookUrl, legadoChapters);
          logger.info(TAG, `章节列表已缓存: ${legadoChapters.length}章`);
        }
      }
      
      // 5. 将新书添加到书架（如果原书在某个书架中，将新书也添加到同一个书架）
      const newBookId = newBookInDb?.id || `${newSourceId}_${newBookUrl}`;
      if (originalInfo.shelfId) {
        // 原书在自定义书架中，将新书添加到同一个书架
        // 注意：itemId必须使用完整的novel.id格式（${sourceId}_${bookUrl}），与数据库中的NovelBook.id一致
        await this.typeShelfManager.moveItemToShelf(newBookId, ContentType.NOVEL, originalInfo.shelfId);
        logger.info(TAG, `新书已添加到书架: ${originalInfo.shelfId}, bookId=${newBookId}`);
      } else {
        // 原书不在自定义书架中，只设置收藏状态（已在步骤3中完成）
        logger.info(TAG, `新书已设置为收藏状态`);
      }
      
      // 6. 删除原书数据
      if (originalInfo.bookId && originalInfo.isFavorite) {
        // 从书架分类中移除原书
        try {
          const categoryManager = this.typeShelfManager.getCategoryManager();
          // 注意：itemId必须使用完整的novel.id格式（${sourceId}_${bookUrl}）
          await categoryManager.removeItemFromCategory(originalInfo.bookId, ContentType.NOVEL);
          logger.info(TAG, `原书已从书架分类移除: ${originalInfo.bookId}`);
        } catch (e) {
          logger.warn(TAG, `从书架移除原书失败: ${String(e)}`);
        }
        
        // 删除原书章节缓存
        const originalCacheBookId = this.getNovelCacheBookId(originalInfo.sourceId, originalInfo.bookUrl);
        await this.novelCacheManager.clearBookCache(originalCacheBookId);
        logger.info(TAG, `原书章节缓存已清除: ${originalCacheBookId}`);
        
        // 删除原书数据库记录
        await this.novelDataManager.deleteBook(originalInfo.bookId);
        logger.info(TAG, `原书已删除: ${originalInfo.name}`);
      }
      
      // 7. 重置换源标记
      this.isFromChangeSource = false;
      this.originalBookInfo = null;
      
      // 8. 更新UI状态
      this.isFavorite = true;
      this.isInShelf = true;
      if (this.content) {
        this.content.lastReadChapterIndex = newLastReadIndex;
        this.content.isFavorite = true;
      }
      
      // 9. 检查更新书架状态
      await this.checkIfInShelf();
      
      promptAction.showToast({ 
        message: `已替换为「${this.content?.sourceName || '新书源'}」的版本`, 
        duration: 2500 
      });
      
      // 10. 发布事件通知 MainMenuPage 刷新小说列表
      eventBus.publish(GameEvent.NOVEL_LIST_REFRESH_NEEDED, new BasePayload());
      
      logger.info(TAG, `替换小说完成: ${this.content?.title}`);
      
    } catch (error) {
      logger.error(TAG, `替换小说失败: ${String(error)}`);
      promptAction.showToast({ message: `替换失败: ${String(error)}`, duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }
  
  /**
   * 生成封面对话框
   */
  @Builder
  buildGenerateCoverDialog() {
    if (this.showGenerateCoverDialog) {
      Column() {
        Column({ space: 20 }) {
          Text('生成封面')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Column({ space: 8 }) {
            Text('请输入要显示在封面上的标题：')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            TextInput({ text: this.coverTitleInput })
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .onChange((value: string) => {
                this.coverTitleInput = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          
          Column({ space: 8 }) {
            Row() {
              Text('字体倍率：')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              
              Text(this.coverFontScale.toFixed(1) + 'x')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            
            Slider({
              value: this.coverFontScale,
              min: 0.1,
              max: 2.0,
              step: 0.1,
              style: SliderStyle.OutSet
            })
              .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .trackColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .showSteps(false)
              .showTips(false)
              .onChange((value: number) => {
                this.coverFontScale = value;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          
          Row({ space: 12 }) {
            Button('取消')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .onClick(() => {
                this.closeGenerateCoverDialog();
              })
            
            Button('确定')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .fontColor(Color.White)
              .layoutWeight(1)
              .onClick(() => {
                this.generateCoverForContent();
              })
          }
          .width('100%')
        }
        .width('80%')
        .constraintSize({ maxWidth: 400 })
        .padding(24)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(16)
        .scale({ x: this.dialogScale, y: this.dialogScale })
        .translate({ y: this.dialogTranslateY })
        .opacity(this.dialogOpacity)
        .shadow({
          radius: 20,
          color: 'rgba(0,0,0,0.2)',
          offsetX: 0,
          offsetY: 10
        })
        .onClick(() => {
          // 空处理器阻止点击事件冒泡到背景
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(`rgba(0,0,0,${0.5 * this.dialogOpacity})`)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.closeGenerateCoverDialog();
      })
    }
  }
  
  /**
   * 换源对话框（带丰富动画效果）
   */
  @Builder
  buildChangeSourceDialog() {
    if (this.showChangeSourceDialog) {
      Column() {
        // 对话框内容
        Column({ space: 0 }) {
          // 标题栏
          Row() {
            Column() {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                  .fontSize(20)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                
                Text('换源')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                
                if (this.alternativeSourceResults.length > 0) {
                  Text(`(${this.alternativeSourceResults.length}个书源)`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    .opacity(this.changeSourceDialogOpacity)
                    .animation({ duration: 200, curve: Curve.EaseOut })
                }
              }
              
              // 进度条
              if (this.isSearchingSource) {
                Row() {
                  Progress({ value: this.searchSourceProgress, total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .height(3)
                    .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
                    .animation({ duration: 150, curve: Curve.EaseOut })
                }
                .width('100%')
                .margin({ top: 10 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            
            Row({ space: 8 }) {
              if (this.isSearchingSource) {
                Text(`${this.searchSourceCompleted}/${this.searchSourceTotal}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .animation({ duration: 200, curve: Curve.EaseOut })
              }
              
              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.closeChangeSourceDialog())
            }
          }
          .width('100%')
          .padding({ left: 20, right: 16, top: 16, bottom: 12 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          
          // 搜索关键词输入框
          Row({ space: 8 }) {
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
              
              TextInput({ text: this.changeSourceKeyword, placeholder: '输入搜索关键词' })
                .layoutWeight(1)
                .height(36)
                .backgroundColor(Color.Transparent)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                .padding({ left: 8, right: 8 })
                .onChange((value: string) => {
                  this.changeSourceKeyword = value;
                })
                .onSubmit(() => {
                  this.startChangeSourceSearch(true);  // 手动输入后回车强制刷新
                })
              
              if (this.changeSourceKeyword.length > 0) {
                Button() {
                  SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                    .fontSize(16)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                }
                .width(28)
                .height(28)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.changeSourceKeyword = '';
                })
              }
            }
            .layoutWeight(1)
            .height(40)
            .padding({ left: 12, right: 4 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(20)
            
            Button() {
              if (this.isSearchingSource) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(Color.White)
              } else {
                Text('搜索')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
              }
            }
            .width(60)
            .height(40)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .borderRadius(20)
            .enabled(!this.isSearchingSource && this.changeSourceKeyword.trim().length > 0)
            .opacity(!this.isSearchingSource && this.changeSourceKeyword.trim().length > 0 ? 1 : 0.5)
            .onClick(() => {
              this.startChangeSourceSearch(true);  // 手动点击搜索按钮强制刷新
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
          .animation({ duration: 200, curve: Curve.EaseOut })
          
          // 搜索结果列表
          if (this.isSearchingSource && this.alternativeSourceResults.length === 0) {
            // 正在搜索且还没有结果
            Column() {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
              
              Text(`正在搜索可用书源...`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .margin({ top: 16 })
              
              Text(`${this.searchSourceCompleted} / ${this.searchSourceTotal}`)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .margin({ top: 8 })
            }
            .width('100%')
            .height(280)
            .justifyContent(FlexAlign.Center)
            .animation({ duration: 300, curve: Curve.EaseOut })
          } else if (!this.isSearchingSource && this.alternativeSourceResults.length === 0) {
            // 搜索完成但没有结果
            Column() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(56)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
              
              Text('未找到其他书源')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 16 })
              
              Text('试试导入更多书源后再换源')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .margin({ top: 6 })
            }
            .width('100%')
            .height(280)
            .justifyContent(FlexAlign.Center)
          } else {
            // 有结果，按书源分组展示
            List() {
              ForEach(this.alternativeSourceResults, (sourceResult: SourceSearchResult, sourceIndex: number) => {
                // 书源分组标题
                ListItem() {
                  Row() {
                    Row({ space: 6 }) {
                      Text(sourceResult.sourceName)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      
                      Text(`${sourceResult.results.length}本`)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    }
                    
                    Blank()
                    
                    if (sourceResult.sourceGroup && sourceResult.sourceGroup !== '未分组') {
                      Text(sourceResult.sourceGroup)
                        .fontSize(10)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20')
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(10)
                    }
                  }
                  .width('100%')
                  .padding({ left: 20, right: 20, top: 12, bottom: 6 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                }
                .animation({
                  duration: 250,
                  delay: sourceIndex * 30,
                  curve: Curve.EaseOut
                })
                
                // 该书源下的书籍列表
                ForEach(sourceResult.results, (book: NovelSearchResult, bookIndex: number) => {
                  ListItem() {
                    Row() {
                      Column() {
                        Row({ space: 6 }) {
                          Text(book.name)
                            .fontSize(14)
                            .fontWeight(FontWeight.Medium)
                            .fontFamily(this.appFontFamily)
                            .fontColor(book.sourceId === this.pageParams?.sourceId
                              ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          
                          if (book.author) {
                            Text(`· ${book.author}`)
                              .fontSize(12)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                              .maxLines(1)
                          }
                        }
                        
                        Text(book.latestChapterTitle || '暂无最新章节信息')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                          .margin({ top: 4 })
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      
                      if (book.sourceId === this.pageParams?.sourceId) {
                        Row({ space: 4 }) {
                          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                            .fontSize(14)
                            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                          Text('当前')
                            .fontSize(12)
                            .fontFamily(this.appFontFamily)
                            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                        }
                        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '20')
                        .borderRadius(12)
                      } else {
                        SymbolGlyph($r('sys.symbol.chevron_right'))
                          .fontSize(16)
                          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                      }
                    }
                    .width('100%')
                    .padding({ left: 20, right: 16, top: 12, bottom: 12 })
                    .backgroundColor(book.sourceId === this.pageParams?.sourceId
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) + '08'
                      : Color.Transparent)
                    .onClick(() => {
                      if (book.sourceId !== this.pageParams?.sourceId) {
                        this.changeNovelSource(book);
                      }
                    })
                  }
                  .animation({
                    duration: 200,
                    delay: sourceIndex * 30 + bookIndex * 20,
                    curve: Curve.EaseOut
                  })
                }, (book: NovelSearchResult) => `${sourceResult.sourceId}_${book.bookUrl}`)
              }, (sourceResult: SourceSearchResult) => sourceResult.sourceId)
            }
            .width('100%')
            .height(350)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .divider({ 
              strokeWidth: 0.5, 
              color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme),
              startMargin: 20,
              endMargin: 16
            })
          }
        }
        .width('92%')
        .constraintSize({ maxWidth: 420, maxHeight: '80%' })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .scale({ x: this.changeSourceDialogScale, y: this.changeSourceDialogScale })
        .translate({ y: this.changeSourceDialogTranslateY })
        .opacity(this.changeSourceDialogOpacity)
        .shadow({
          radius: 30,
          color: 'rgba(0,0,0,0.25)',
          offsetX: 0,
          offsetY: 15
        })
        .clip(true)
        .onClick(() => {
          // 空处理器阻止点击事件冒泡到背景
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(`rgba(0,0,0,${0.5 * this.changeSourceDialogOpacity})`)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.closeChangeSourceDialog())
    }
  }

  /**
   * 添加书架选择对话框
   */
  @Builder
  buildAddToShelfDialog() {
    if (this.showAddToShelfDialog) {
      Column() {
        // 对话框内容
        Column({ space: 16 }) {
          // 标题栏
          Row() {
            Text('添加到书架')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            Blank()
            
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.closeAddToShelfDialog())
          }
          .width('100%')
          
          // 书架列表（始终显示默认书架选项）
          List({ space: 8 }) {
            // 默认书架选项（始终显示在最前面）
            ListItem() {
              Row({ space: 12 }) {
                // 默认书架图标
                Column() {
                  SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                    .fontSize(24)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                }
                .width(44)
                .height(44)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                .borderRadius(10)
                
                // 默认书架信息
                Column({ space: 4 }) {
                  Text('默认书架')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  
                  Text('仅收藏到默认书库，不添加到自定义书架')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .borderRadius(12)
              .onClick(async () => {
                await this.addToFavoriteOnly();
                this.closeAddToShelfDialog();
              })
            }

            // 自定义书架列表
            ForEach(this.availableCustomShelves, (shelf: TypeShelf) => {
              ListItem() {
                Row({ space: 12 }) {
                  // 书架图标
                  Column() {
                    SymbolGlyph($r('sys.symbol.books_vertical_fill'))
                      .fontSize(24)
                      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                  }
                  .width(44)
                  .height(44)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
                  .borderRadius(10)
                  
                  // 书架信息
                  Column({ space: 4 }) {
                    Text(shelf.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    
                    Text(shelf.shelfType === ShelfType.MIXED ? '混合书架' : 
                      shelf.shelfType === ShelfType.DYNAMIC ? '动态书架' :
                      shelf.contentTypes.includes(ShelfContentType.MANGA) ? '漫画' : 
                      shelf.contentTypes.includes(ShelfContentType.EBOOK) ? '电子书' : '小说')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  
                  // 选中指示
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(12)
                .onClick(() => this.addToShelf(shelf))
              }
            }, (shelf: TypeShelf) => shelf.id)
          }
          .width('100%')
          .constraintSize({ maxHeight: 300 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('90%')
        .constraintSize({ maxWidth: 360 })
        .padding(20)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .scale({ x: this.addToShelfDialogScale, y: this.addToShelfDialogScale })
        .opacity(this.addToShelfDialogOpacity)
        .shadow({
          radius: 30,
          color: 'rgba(0,0,0,0.25)',
          offsetX: 0,
          offsetY: 15
        })
        .onClick(() => {
          // 阻止点击冒泡
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.closeAddToShelfDialog())
    }
  }
  
  /**
   * 替换小说对话框
   */
  @Builder
  buildReplaceBookDialog() {
    if (this.showReplaceBookDialog && this.originalBookInfo && this.content) {
      Column() {
        // 对话框内容
        Column({ space: 16 }) {
          // 标题栏
          Row() {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.wrench_arrow_counterclockwise'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
              
              Text('替换小说')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            
            Blank()
            
            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.closeReplaceBookDialog())
          }
          .width('100%')
          
          // 对比信息
          Column({ space: 12 }) {
            // 原书信息卡片
            Column({ space: 8 }) {
              Row() {
                Text('原书源')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme) + '20')
                  .borderRadius(4)
              }
              .width('100%')
              
              Text(this.originalBookInfo.sourceName || '未知书源')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              
              Row({ space: 6 }) {
                Text('共')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                Text(`${this.originalBookInfo.chapterCount}`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                
                Text('章')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(12)
            
            // 箭头指示
            Row() {
              SymbolGlyph($r('sys.symbol.arrow_down'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            
            // 新书源信息卡片
            Column({ space: 8 }) {
              Row() {
                Text('新书源')
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                  .borderRadius(4)
              }
              .width('100%')
              
              Text(this.content.sourceName || '未知书源')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              
              Row({ space: 6 }) {
                Text('共')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                Text(`${this.content.totalChapters}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                
                Text('章')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                
                // 显示章节数差异
                if (this.content.totalChapters !== this.originalBookInfo.chapterCount) {
                  Text(`(${this.content.totalChapters > this.originalBookInfo.chapterCount ? '+' : ''}${this.content.totalChapters - this.originalBookInfo.chapterCount})`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.content.totalChapters > this.originalBookInfo.chapterCount 
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
                }
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .alignItems(HorizontalAlign.Start)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '15')
            .borderRadius(12)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme) + '40'
            })
            
            // 阅读进度迁移信息
            if (this.originalBookInfo.lastReadChapterIndex >= 0) {
              Column({ space: 6 }) {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.bookmark_fill'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                  
                  Text('阅读进度迁移')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                
                Text(`原书阅读至: 第${this.originalBookInfo.lastReadChapterIndex + 1}章`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                
                if (this.originalBookInfo.lastReadChapterTitle) {
                  Text(`「${this.originalBookInfo.lastReadChapterTitle}」`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.arrow_right_circle'))
                    .fontSize(12)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                  
                  if (this.matchedChapterIndex >= 0) {
                    Text(`将从新书第${this.matchedChapterIndex + 1}章继续`)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  } else {
                    Text('将从第1章开始')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  }
                }
                .margin({ top: 4 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '10')
              .borderRadius(12)
            }
            
            // 提示文字（根据原书是否在收藏中显示不同内容）
            Text(this.originalBookInfo.isFavorite 
              ? '替换后原书将从书架中删除，缓存数据也将清除'
              : '新书将添加到书架收藏')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          
          // 按钮栏
          Row({ space: 12 }) {
            Button('取消')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .height(44)
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => this.closeReplaceBookDialog())
            
            Button('确认替换')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
              .fontColor(Color.White)
              .height(44)
              .layoutWeight(1)
              .borderRadius(22)
              .onClick(() => this.executeReplaceBook())
          }
          .width('100%')
        }
        .width('90%')
        .constraintSize({ maxWidth: 380 })
        .padding(20)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .scale({ x: this.replaceDialogScale, y: this.replaceDialogScale })
        .translate({ y: this.replaceDialogTranslateY })
        .opacity(this.replaceDialogOpacity)
        .shadow({
          radius: 30,
          color: 'rgba(0,0,0,0.25)',
          offsetX: 0,
          offsetY: 15
        })
        .onClick(() => {
          // 阻止点击冒泡
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.closeReplaceBookDialog())
    }
  }

  /**
   * 显示添加书架选择
   */
  private async showAddToShelfSelection(): Promise<void> {
    if (!this.content) return;
    
    // 如果已在书架中，提示用户
    if (this.isInShelf) {
      promptAction.showToast({ 
        message: this.currentShelfName ? `已在「${this.currentShelfName}」中` : '已在书架中',
        duration: 1500 
      });
      return;
    }
    
    // 获取可用的自定义书架
    await this.getAvailableCustomShelves();
    
    // 始终显示对话框（包含默认书架选项）
    this.showAddToShelfDialog = true;
    animateTo({
      duration: 300,
      curve: curves.springMotion(0.6, 0.9)
    }, () => {
      this.addToShelfDialogOpacity = 1;
      this.addToShelfDialogScale = 1;
    });
  }

  /**
   * 关闭添加书架对话框
   */
  private closeAddToShelfDialog(): void {
    animateTo({
      duration: 250,
      curve: Curve.EaseOut
    }, () => {
      this.addToShelfDialogOpacity = 0;
      this.addToShelfDialogScale = 0.8;
    });
    
    setTimeout(() => {
      this.showAddToShelfDialog = false;
    }, 260);
  }

  /**
   * 检查内容是否已在书架中
   */
  private async checkIfInShelf(): Promise<void> {
    if (!this.content) return;
    
    try {
      // 获取所有书架
      const allShelves: TypeShelf[] = this.typeShelfManager.getShelves();
      
      // 遍历检查是否在某个自定义书架中
      for (const shelf of allShelves) {
        // 跳过系统书架
        if (shelf.isSystem) continue;
        
        // 根据内容类型检查
        let contentType: ContentType;
        switch (this.content.contentType) {
          case UnifiedContentType.MANGA:
            contentType = ContentType.MANGA;
            break;
          case UnifiedContentType.EBOOK:
            contentType = ContentType.EBOOK;
            break;
          case UnifiedContentType.NOVEL:
            contentType = ContentType.NOVEL;
            break;
          default:
            continue;
        }
        
        // 检查书架是否包含该内容
        const itemIds = this.typeShelfManager.getShelfItemIdsByType(shelf.id, contentType);
        if (itemIds.includes(this.content.id)) {
          this.isInShelf = true;
          this.currentShelfName = shelf.name;
          this.currentShelfId = shelf.id;
          return;
        }
      }
      
      // 如果不在任何自定义书架中，检查是否已收藏
      if (this.isFavorite) {
        this.isInShelf = true;
        this.currentShelfName = '';  // 已收藏但不在自定义书架中
        this.currentShelfId = '';
        return;
      }
      
      this.isInShelf = false;
      this.currentShelfName = '';
      this.currentShelfId = '';
    } catch (error) {
      logger.error(TAG, `检查书架状态失败: ${String(error)}`);
      this.isInShelf = false;
      this.currentShelfName = '';
      this.currentShelfId = '';
    }
  }

  /**
   * 获取可用的自定义书架
   */
  private async getAvailableCustomShelves(): Promise<void> {
    if (!this.content) {
      this.availableCustomShelves = [];
      return;
    }
    
    try {
      // 根据内容类型获取对应的书架
      let contentType: ContentType;
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          contentType = ContentType.MANGA;
          break;
        case UnifiedContentType.EBOOK:
          contentType = ContentType.EBOOK;
          break;
        case UnifiedContentType.NOVEL:
          contentType = ContentType.NOVEL;
          break;
        default:
          this.availableCustomShelves = [];
          return;
      }
      
      // 获取包含该内容类型的自定义书架（getShelvesForContentType已排除系统书架）
      this.availableCustomShelves = this.typeShelfManager.getShelvesForContentType(contentType);
    } catch (error) {
      logger.error(TAG, `获取自定义书架失败: ${String(error)}`);
      this.availableCustomShelves = [];
    }
  }

  /**
   * 添加到指定书架
   */
  private async addToShelf(shelf: TypeShelf): Promise<void> {
    if (!this.content) return;
    
    try {
      // 根据内容类型获取类型
      let contentType: ContentType;
      switch (this.content.contentType) {
        case UnifiedContentType.MANGA:
          contentType = ContentType.MANGA;
          break;
        case UnifiedContentType.EBOOK:
          contentType = ContentType.EBOOK;
          break;
        case UnifiedContentType.NOVEL:
          contentType = ContentType.NOVEL;
          break;
        default:
          return;
      }
      
      // 添加到书架
      await this.typeShelfManager.moveItemToShelf(this.content.id, contentType, shelf.id);
      
      // 同时设置为收藏
      if (!this.isFavorite) {
        await this.setFavoriteStatus(true);
      }
      
      // 更新状态
      this.isInShelf = true;
      this.currentShelfName = shelf.name;
      this.currentShelfId = shelf.id;
      
      // 关闭对话框
      this.closeAddToShelfDialog();
      
      // 加载同书架内容
      this.loadShelfContent();
      
      promptAction.showToast({ 
        message: `已添加到「${shelf.name}」书架`,
        duration: 1500 
      });
    } catch (error) {
      logger.error(TAG, `添加到书架失败: ${String(error)}`);
      promptAction.showToast({ 
        message: '添加失败，请重试',
        duration: 1500 
      });
    }
  }

  /**
   * 仅添加到收藏（没有自定义书架时调用）
   */
  private async addToFavoriteOnly(): Promise<void> {
    if (!this.content) return;
    
    try {
      await this.setFavoriteStatus(true);
      this.isInShelf = true;
      this.currentShelfName = '';
      promptAction.showToast({ 
        message: '已添加到默认书架',
        duration: 1500 
      });
    } catch (error) {
      logger.error(TAG, `添加到收藏失败: ${String(error)}`);
      promptAction.showToast({ 
        message: '添加失败，请重试',
        duration: 1500 
      });
    }
  }

  /**
   * 设置收藏状态（内部方法）
   */
  private async setFavoriteStatus(isFavorite: boolean): Promise<void> {
    if (!this.content) return;
    
    this.isFavorite = isFavorite;
    
    switch (this.content.contentType) {
      case UnifiedContentType.MANGA:
        const dataService = DataService.getInstance();
        if (isFavorite) {
          await dataService.addToFavorites(this.content.id);
        } else {
          await dataService.removeFromFavorites(this.content.id);
        }
        break;
      case UnifiedContentType.EBOOK:
        const ebook = EBookAdapter.getOriginalEBook(this.content);
        if (ebook && ebook.metadata) {
          ebook.isFavorite = isFavorite;
          await this.ebookDataManager.saveEBook(ebook);
        } else if (isFavorite && this.content.sourceId) {
          // 在线电子书：创建新的EBook对象并保存
          const now = Date.now();
          const metadata: EBookMetadata = {
            title: this.content.title,
            author: this.content.author,
            publisher: '',
            publishDate: '',
            isbn: '',
            language: '',
            description: this.content.description,
            coverImagePath: this.content.coverUrl,
            tags: this.content.tags || [],
            rating: 0
          };
          const emptyChapters: EBookChapter[] = [];
          const extendedDataMap = new Map<string, string>();
          extendedDataMap.set('sourceId', this.content.sourceId || '');
          extendedDataMap.set('sourceName', this.content.sourceName || '');
          extendedDataMap.set('onlineReaderUrl', this.onlineReaderUrl || '');
          const extendedDataObj: Record<string, string> = {};
          extendedDataMap.forEach((value: string, key: string) => {
            extendedDataObj[key] = value;
          });
          const extendedDataJson = JSON.stringify(extendedDataObj);
          const onlineEbook = new EBook(
            this.content.id,
            EBookFormat.EPUB,
            extendedDataJson,
            0,
            metadata,
            emptyChapters
          );
          onlineEbook.metadata = metadata;
          onlineEbook.status = EBookStatus.UNREAD;
          onlineEbook.addTime = now;
          onlineEbook.lastUpdateTime = now;
          onlineEbook.isFavorite = true;
          onlineEbook.totalWordCount = 0;
          onlineEbook.isPrivate = false;
          onlineEbook.isNSFW = this.content.isNSFW || false;
          await this.ebookDataManager.saveEBook(onlineEbook);
        }
        break;
      case UnifiedContentType.NOVEL:
        const novelBook = await this.novelDataManager.getBookByUrl(this.content.sourceId || '', this.content.id);
        if (novelBook) {
          novelBook.isFavorite = isFavorite;
          await this.novelDataManager.saveBook(novelBook);
        } else if (isFavorite) {
          const now = Date.now();
          const newBook: NovelBook = {
            id: '',
            sourceId: this.content.sourceId || '',
            sourceName: this.content.sourceName || '',
            bookUrl: this.content.id,
            name: this.content.title,
            author: this.content.author,
            intro: this.content.description,
            coverUrl: this.content.coverUrl,
            chapterCount: this.content.totalChapters,
            readStatus: NovelReadStatus.UNREAD,
            totalReadingTime: 0,
            isFavorite: true,
            createTime: now,
            updateDbTime: now
          };
          await this.novelDataManager.saveBook(newBook);
        }
        break;
    }
  }
}
