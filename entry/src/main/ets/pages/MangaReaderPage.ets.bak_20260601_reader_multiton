/**
 * 漫画阅读器页面
 * 实现沉浸式显示、Navigation架构、状态管理
 * 支持单页/双页/连续滚动模式、缩放、手势翻页等功能
  */

import { logger } from '../Utils/Logger';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { common } from '@kit.AbilityKit';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { ReaderOrientationLockHelper } from '../Utils/ReaderOrientationLockHelper';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { globalAnimationManager, AnimationType, AnimationState,
  AnimationEasing } from '../Framework/Animation/GlobalAnimationSystem';
import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { UIContext, curves, promptAction } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { DataManager, PageInfo, PageInfoInput, ChapterInfo, OnlineChapterInfo, OnlinePageInfo, OnlinePageInfoInput, UserSettingsDatabaseRecord } from '../Framework/Data/DataManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';
import { DatabaseManager } from '../Framework/Database/DatabaseManager';
import CookieManager from '../Framework/Managers/CookieManager';
import { DataService } from '../Framework/Services/DataService';
import { RemoteLibraryMangaBridge } from '../Framework/Source/RemoteLibraryMangaBridge';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor } from '../Framework/Source/SuwayomiSourceExecutor';
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { 
  Manga, 
  MangaChapter, 
  MangaPage, 
  MangaReaderState, 
  ReadingMode, 
  ReadingDirection,
  ReadingSettings,
  DEFAULT_READING_SETTINGS,
  ImageSourceType,
  MangaSourceInfo,
  MangaImageRequestHeader,
  DoublePagePortraitLayout,
  DoublePageVerticalDirection
} from '../Models/MangaModels';
import { MangaViewer } from '../components/MangaViewer';
import { MangaReaderSettings } from '../components/MangaReaderSettings';
import { ImageCacheManager, RequestHeaderEntry, RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { OnlineImageLoader } from '../Framework/Cache/OnlineImageLoader';
import { PreloadDebugOverlay, PreloadDebugInfo } from '../components/PreloadDebugOverlay';
import fs from '@ohos.file.fs';
import { MangaQuickSettings } from '../components/MangaQuickSettings';
import { MangaReaderChapterList } from '../components/MangaReaderChapterList';
import { MangaInteractionOverlay, MangaInteractionOverlayParams } from '../components/MangaInteractionOverlay';
import { setReaderReady, setReaderLoadingProgress, startBookCloseTransitionWithComponentId, CoverPosition, cancelTransition } from '../components/BookTransitionOverlay';
import { MangaDetailPageParams } from './MangaDetailPage';
import { DownloadStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { AutoPageTurnController, AutoPageTurnState, AutoPageTurnConfig } from '../Framework/Utils/AutoPageTurnController';
import { PageTurnAnimationType } from '../Models/MangaModels';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { MangaSourceEngine, EngineResult } from '../Framework/WebView/MangaSourceEngine';
import {
  DoublePageSmartDisplayMode,
  DoublePageSmartDisplayPlan,
  DoublePageSmartDisplayReason,
  DoublePageSmartLayoutHelper,
  PageDimensionsInfo
} from '../Utils/DoublePageSmartLayoutHelper';
import { PageInfo as SourcePageInfo, PageRequestHeader as SourcePageRequestHeader } from '../Framework/WebView/MangaSourceTypes';
import { MangaSourceAPIEngine } from '../Framework/WebView/MangaSourceAPIEngine';
import { ChapterPreloadManager } from '../Framework/Preload/ChapterPreloadManager';
import { OnlineArchiveExtractedPage, OnlineArchiveExtractResult, OnlineMangaArchiveService } from '../Framework/Download/OnlineMangaArchiveService';
import { webview } from '@kit.ArkWeb';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { TrackingManager } from '../Framework/Tracking/TrackingManager';
import { TrackContentType } from '../Framework/Tracking/TrackingModels';
import { window } from '@kit.ArkUI';
import { eventBus, GameEvent, BasePayload } from '../Framework/EventBus';
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { getUnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { AnnotationAnchor, UnifiedAnnotationType } from '../Models/AnnotationModels';
import { AnnotationCenterPageParams } from './AnnotationCenterPage';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';

const TAG = 'MangaReaderPage';

/**
* 漫画阅读器页面参数接口
*/
export interface MangaReaderPageParams {
  /** 漫画信息（直接传递） */
  manga?: Manga;
  /** 漫画ID（需要从DataManager加载） */
  mangaId?: string;
  /** 图源ID（用于WebView图源） */
  sourceId?: number;
  /** 图源包名（用于特定图源专用逻辑） */
  sourcePkg?: string;
  /** 图源名称（例如：KOMIIC；本地则为 LOCAL） */
  sourceName?: string;
  /** 阅读内容类型（本地/在线未下载/在线已下载） */
  contentType: MangaReaderContentType;
  /** 初始章节ID（可选） */
  chapterId?: string;
  /** 初始页面索引（可选） */
  pageIndex?: number;
  /** 来源页面（用于日志记录） */
  fromPage?: string;
  /** 打开动画来源封面组件ID（用于关闭动画精准回落） */
  coverComponentId?: string;
  /** 跳过数据库查找，直接使用外部ID请求（用于在线漫画且详情页未获取章节信息的情况） */
  skipDatabaseLookup?: boolean;
  /** 章节标题（用于通过标题查询数据库获取章节信息） */
  chapterTitle?: string;
}

/**
* 临时阅读设置接口（用于修复对象字面量问题）
*/
interface TempReadingSettings {
  readingMode: ReadingMode;
  brightness: number;
  autoPlay: boolean;
  pageTransition: boolean;
  showPageNumber: boolean;
}

/**
* 动画配置接口（用于修复未类型化对象字面量问题）
*/
interface AnimationConfig {
  duration: number;
  curve: Curve;
}

/**
* PageInfo到MangaPage转换接口
* 用于修复未类型化对象字面量错误
*/
interface PageInfoToMangaPageConverter {
  id: string;
  pageNumber: number;
  imageUrl: string;
  localPath?: string;
  width: number;
  height: number;
  fileSize: number;
  isLoaded: boolean;
  index: number;
  sourceType: ImageSourceType;
  imagePath: string;
  loadProgress?: number;
}

/**
* ChapterInfo到MangaChapter转换接口
* 用于修复未类型化对象字面量错误
*/
interface ChapterInfoToMangaChapterConverter {
  id: string;
  title: string;
  chapterNumber: number;
  pages: MangaPage[];
  totalPages?: number;// [新增] 实际总页数（用于动态加载场景）
  publishDate: number | Date;
  isRead: boolean;
  readProgress: number;
  language: string;
  scanlationGroup: string;
  isDownloaded: boolean;
  downloadProgress: number;
  downloadStatus: DownloadStatus;
  localPath?: string;
  externalId?: string;// [修复] 添加外部ID字段
}

/**
* 错误详情接口
*/
interface ErrorDetails {
  errorType: string;
  errorMessage: string;
  errorStack?: string;
  mangaTitle?: string;
  mangaId?: string;
  chapterId?: string;
  pageIndex?: number;
  timestamp: string;
}

/**
* 章节错误详情接口
*/
interface ChapterErrorDetails {
  mangaTitle: string;
  mangaId: string;
  chaptersCount: number;
  specifiedChapterId?: string;
  availableChapterIds: string[];
}

/**
* 阅读设置错误详情接口
*/
interface ReadingSettingsErrorDetails {
  errorType: string;
  errorMessage: string;
  mangaTitle?: string;
  mangaId?: string;
  hasReadingSettings: boolean;
  timestamp: string;
}

/**
* 预加载错误详情接口
*/
interface PreloadErrorDetails {
  errorType: string;
  errorMessage: string;
  chapterTitle?: string;
  chapterId?: string;
  currentPageIndex: number;
  totalPages?: number;
  timestamp: string;
}

/**
* 操作错误详情接口
*/
interface OperationErrorDetails {
  errorType: string;
  errorMessage: string;
  operation: string;
  timestamp: string;
}

interface ChapterSwitchPageGuard {
  chapterId: string;
  pageIndex: number;
  direction: 'prev' | 'next';
  expiresAt: number;
}

/**
* 工具栏动画错误详情接口
*/
interface ToolbarAnimationErrorDetails {
  errorType: string;
  errorMessage: string;
  operation: string;
  showTopToolbar: boolean;
  timestamp: string;
}

/**
* 图源预加载设置接口
*/
interface SourcePreloadSettings {
  preloadCurrentChapter: boolean;
  preloadCurrentPages: number;
  preloadNextChapter: boolean;
  preloadNextPages: number;
}

interface SourceConfigDefaultSetting {
  default?: string;
}

type SourceConfigHeaderMap = Record<string, string>;

interface SourceConfigNetworkLike {
  userAgent?: string;
  headers?: SourceConfigHeaderMap;
}

interface SourceConfigMetadataLike {
  baseUrl?: string;
  alternativeUrls?: Record<string, string>;
}

interface SourceConfigSettingsLike {
  domain?: SourceConfigDefaultSetting;
  apiDomain?: SourceConfigDefaultSetting;
}

interface SourceConfigJsonLike {
  metadata?: SourceConfigMetadataLike;
  settings?: SourceConfigSettingsLike;
  network?: SourceConfigNetworkLike;
  imageHeaders?: SourceConfigHeaderMap;
}

interface SourceRequestContext {
  requestBaseUrl: string;
  refererHint: string;
  originHint: string;
  headerTemplate: RequestHeaders;
  userAgentLocked: boolean;
}

interface WebtoonAdjacentChapterLoadTarget {
  direction: 'prev' | 'next';
  chapter: MangaChapter;
}

interface MangaBookmarkContext {
  mangaId: string;
  chapter: MangaChapter;
  chapterIndex: number;
  currentPage: number;
  totalPages: number;
  chapterTitle: string;
}

@Component
export struct MangaReaderPage {
  @State isNetworkConfigReady: boolean = false;// 新增状态：网络配置是否就绪
  // 主题相关状态
  @State pathStack: NavPathStack = new NavPathStack();
  @State pageParams: MangaReaderPageParams | null = null;

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('isInBackground') @Watch('onAppBackgroundStateChanged') appInBackground: boolean = false;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'MangaReaderPage';
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  private isPageVisible: boolean = false;
  
  // 动画相关
  private lifecycle = new PageLifecycleManager('MangaReaderPage', {
    enableDebug: true
  });

  // 动画相关
  private uiContext: UIContext | undefined = undefined;
  private animationManager = globalAnimationManager;// 使用统一的动画管理器
  @State isVisible: boolean = false;
  @State contentOpacity: number = 0;
  @State titleTranslateY: number = -50;

  // 数据服务与阅读进度状态
  private dataService: DataService = DataService.getInstance();
  private remoteLibraryBridge: RemoteLibraryMangaBridge = RemoteLibraryMangaBridge.getInstance();
  private suwayomiExecutor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private annotationManager = getUnifiedAnnotationManager();
  private lastProgressSaveTime: number = 0;
  private lastSavedPageIndex: number = -1;
  private sessionStartTimestamp: number = 0;
  
  // WebView图源相关
  private readingTimeTimer: number = -1;// 阅读时间定时器
  private orientationLockToken: string = '';
  private static readonly READING_TIME_SAVE_INTERVAL: number = 1000;// 阅读时间保存间隔（1秒）
  
  // WebView图源相关
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private mangaEngine: MangaSourceEngine | null = null;
  @State networkHeaders: RequestHeaders | undefined = undefined;
  @State networkHeadersTick: number = 0;
  @State chapterTick: number = 0;// [新增] 章节切换计数器，用于通知MangaViewer重新加载
  private currentSourceId: number = -1;
  private currentSourcePkg: string = '';
  private photos18PageCachePartition: string = 'photos18_reader';
  private shouldKeepConfiguredImageUserAgent: boolean = false;

  @State private dailyLimitReached: boolean = false;
  @State private dailyLimitPromptVisible: boolean = false;
  @State private dailyLimitMessage: string = '';
  
  // 新增：预加载调试相关
  @StorageLink('preload_debug_mode') preloadDebugMode: string = 'off';
  @State private preloadDebugInfo: PreloadDebugInfo = {
    currentPage: 0,
    totalPages: 0,
    preloadRange: 2,
    queueItems: [],
    completedCount: 0,
    failedCount: 0,
    memCacheHits: 0,
    diskCacheHits: 0,
    networkLoads: 0
  };
  // 图源预加载设置
  private webviewController: webview.WebviewController = new webview.WebviewController();
  @State private webViewControllerAttached: boolean = false;
  
  // 图源预加载设置
  private sourcePreloadSettings: SourcePreloadSettings = {
    preloadCurrentChapter: true,
    preloadCurrentPages: 10,
    preloadNextChapter: true,
    preloadNextPages: -1
  };

  // 阅读器核心状态
  @State readerState: MangaReaderState = {
    currentManga: null,
    currentChapter: null,
    currentPageIndex: 0,
    isFullscreen: false,
    showControls: true,
    isLoading: false,
    zoomScale: 1.0,
    errorMessage: ''
  };
  @State isCurrentPageBookmarked: boolean = false;
  @State currentPageBookmarkId: string = '';

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State readingSettings: ReadingSettings = DEFAULT_READING_SETTINGS;
  private viewerReadingSettingsCacheKey: string = '';
  private viewerReadingSettingsCache: ReadingSettings = DEFAULT_READING_SETTINGS;

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State toolbarTranslateY: number = 0;// 工具栏动画位移
  @State autoHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;
  @State showSettingsPanel: boolean = false;
  @State showQuickSettings: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showChapterList: boolean = false;
  // 自动翻页控制
  @State showAutoPageTurnSettings: boolean = false;
  @State autoPageTurnEnabled: boolean = false;
  @State autoPageTurnIntervalSeconds: number = 5;
  private interactionPauseTimer: number = -1;
  
  // MangaViewer组件引用
  private autoPageTurnController: AutoPageTurnController | null = null;
  @State autoPageTurnState: AutoPageTurnState = AutoPageTurnState.STOPPED;
  
  // 用于获取MangaViewer组件实例的引用变量
  private mangaViewerRef: MangaViewer | null = null;
  
  // 交互区域提示
  @State private mangaViewerComponent: MangaViewer | null = null;
  
  // 调试：显示点击位置
  @State showInteractionOverlay: boolean = false;// 初次进入不显示，等待读取真实阅读设置后再显示
  @State overlayDismissTimer: number = -1;
  @State isReadingSettingsReady: boolean = false;// 阅读设置是否已加载
  private static hasShownInteractionHint: boolean = false;// 是否已经显示过交互提示（应用级别）
  private static lastShownReadingMode: ReadingMode | null = null;// 上次显示提示时的阅读模式
  
  // 设置面板动画状态
  @State showDebugClickIndicator: boolean = false;
  @State debugClickX: number = 0;
  @State debugClickY: number = 0;
  
  // 更多菜单动画状态
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  @State settingsPanelTranslateY: number = 20;
  // 快速设置面板动画状态
  @State moreMenuOpacity: number = 0;
  @State moreMenuScale: number = 0.95;
  @State moreMenuTranslateY: number = -10;
  // 自动翻页设置面板动画状态
  @State quickSettingsOpacity: number = 0;
  @State quickSettingsScale: number = 0.95;
  @State quickSettingsTranslateY: number = 20;
  // 翻页动画设置面板状态
  @State autoPageTurnSettingsOpacity: number = 0;
  @State autoPageTurnSettingsScale: number = 0.95;
  @State autoPageTurnSettingsTranslateY: number = 20;
  @State autoPageTurnSettingsTranslateX: number = 320;
  // 跳转页面对话框状态
  @State showPageTurnAnimationSettings: boolean = false;
  @State pageTurnAnimationSettingsOpacity: number = 0;
  @State pageTurnAnimationSettingsScale: number = 0.95;
  @State pageTurnAnimationSettingsTranslateY: number = 20;
  @State pageTurnAnimationSettingsTranslateX: number = 320;
  // 屏幕尺寸
  @State showJumpToPageDialog: boolean = false;
  @State jumpToPageInput: string = '';
  @State jumpToPageDialogOpacity: number = 0;
  @State jumpToPageDialogScale: number = 0.9;
  
  // 组件实际渲染尺寸（通过onAreaChange获取）
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;
  // 横竖屏状态（用于对话框布局自适应）
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  // 沉浸式安全区高度（遵循沉浸式显示规范）
  @State private isLandscapeMode: boolean = false;
  // 响应式布局相关
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 图片加载状态 - 用于控制titlebar显示
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private onlineArchiveService: OnlineMangaArchiveService = OnlineMangaArchiveService.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State shouldUseDoublePage: boolean = false;// 是否应该使用双页模式
  
  // 条漫模式相邻章节（用于无缝章节切换）
  @State isImageLoaded: boolean = false;

  // [修复] 章节边界状态：使用@State确保条漫模式下章节切换时能正确更新MangaViewer
  @State prevChapterForWebtoon: MangaChapter | undefined = undefined;
  @State nextChapterForWebtoon: MangaChapter | undefined = undefined;
  // [修复] 章节边界状态：使用@State确保条漫模式下章节切换时能正确更新MangaViewer
  @State isFirstChapterState: boolean = false;
  @State isLastChapterState: boolean = false;
  private webtoonOnlineAdjacentWarmupTimer: number = -1;
  private webtoonOnlineAdjacentLoadingChapterIds: Set<string> = new Set();
  private lastWebtoonSwitchChapterId: string = '';
  private lastWebtoonSwitchAt: number = 0;
  private readonly WEBTOON_SWITCH_DEBOUNCE_LOCAL_MS: number = 120;
  private readonly WEBTOON_SWITCH_DEBOUNCE_ONLINE_MS: number = 280;
  
  // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，覆盖正确的阅读进度
  // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，覆盖正确的阅读进度
  private isReaderInitialized: boolean = false;
  private chapterSwitchPageGuard: ChapterSwitchPageGuard | null = null;
  private static readonly CHAPTER_SWITCH_PAGE_GUARD_MS: number = 3000;
  private hasNotifiedTransitionReaderReady: boolean = false;
  private transitionLoadingProgress: number = 0;
  private isCloseTransitionNavigating: boolean = false;
  private transitionReaderReadyPollTimer: number = -1;
  private transitionReaderReadyTimeoutTimer: number = -1;
  private static readonly TRANSITION_READY_POLL_MS: number = 80;
  private static readonly TRANSITION_READY_TIMEOUT_MS: number = 2500;

  // 音量键翻页回调函数（用于inputConsumer注册/注销）
  @State isDragging: boolean = false;
  @State lastTapTime: number = 0;
  @State tapCount: number = 0;
  private singleTapTimer: number = -1;// 单击延迟定时器，用于双击检测时取消单击
  
  // 音量键翻页回调函数（用于inputConsumer注册/注销）
  private volumeUpCallback: ((event: InputKeyEvent) => void) | null = null;
  private volumeDownCallback: ((event: InputKeyEvent) => void) | null = null;
  private isVolumeKeyListenerRegistered: boolean = false;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  onPageShow() {
    this.isPageVisible = true;
    this.uiContext = this.getUIContext();
    this.setupFullscreenMode();
    this.scheduleFullscreenRestore('page_show');
    this.refreshCurrentMangaBookmarkState('on_page_show');
    logger.lifecycle(TAG, '漫画阅读器页面开始显示');
    
    // 通知预加载管理器：阅读器已激活
    ChapterPreloadManager.getInstance().setReaderActive(true);
    
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
        
        // 获取页面参数 - getParamByName返回Array<unknown>
        const paramDataArray = this.pathStack.getParamByName('MangaReaderPage') as MangaReaderPageParams[];
        logger.debug(TAG, `📋 获取到参数数组，长度: ${paramDataArray?.length || 0}`);
        
        if (paramDataArray && paramDataArray.length > 0) {
          const latestParam = paramDataArray[paramDataArray.length - 1]; // 获取最新参数
          logger.debug(TAG, `📋 使用最新参数 (索引: ${paramDataArray.length - 1})`);
          
          if (latestParam && typeof latestParam === 'object' && 
              (Object.keys(latestParam).includes('manga') || Object.keys(latestParam).includes('mangaId'))) {
            const typedParams = latestParam as MangaReaderPageParams;
            this.pageParams = typedParams;
            
            // 详细记录参数信息
            logger.info(TAG, `📖 漫画参数解析成功:`);
            if (typedParams.manga) {
              logger.info(TAG, `  - 漫画标题: ${typedParams.manga.title}`);
              logger.info(TAG, `  - 漫画ID: ${typedParams.mangaId}`);
              logger.info(TAG, `  - 章节总数: ${typedParams.manga.chapters.length}`);
            } else if (typedParams.mangaId) {
              logger.info(TAG, `  - 漫画ID: ${typedParams.mangaId}`);
              logger.info(TAG, `  - 需要从DataManager加载漫画数据`);
            }
            logger.info(TAG, `  - 指定章节ID: ${typedParams.chapterId || '未指定'}`);
            logger.info(TAG, `  - 指定页面索引: ${typedParams.pageIndex || 0}`);
            logger.info(TAG, `  - 来源页面: ${typedParams.fromPage || '未指定'}`);
            
            this.initializeMangaReader(typedParams);
          } else {
            logger.error(TAG, '❌ 参数格式不正确或缺少必需的manga/mangaId属性');
            logger.error(TAG, `参数类型: ${typeof latestParam}, 包含manga属性: ${latestParam && typeof latestParam === 'object' ? Object.keys(latestParam).includes('manga') : false}, 包含mangaId属性: ${latestParam && typeof latestParam === 'object' ? Object.keys(latestParam).includes('mangaId') : false}`);
          }
        } else {
          logger.error(TAG, '❌ 未找到页面参数，参数数组为空或不存在');
        }
      } else {
        logger.error(TAG, '❌ 无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : String(err);
      logger.error(TAG, '❌ AppStorage.get 异常', errorMessage);
    }

    if (!this.pageParams) {
      try {
        const router = this.getUIContext()?.getRouter();
        if (router) {
          const rawParamsObj = router.getParams() as Record<string, Object>;
          const rawKeys: string[] = Object.keys(rawParamsObj as Object);
          const hasManga: boolean = rawKeys.includes('manga');
          const hasMangaId: boolean = rawKeys.includes('mangaId');
          const hasSourceId: boolean = rawKeys.includes('sourceId');
          const hasChapterId: boolean = rawKeys.includes('chapterId');
          const hasPageIndex: boolean = rawKeys.includes('pageIndex');
          const hasFromPage: boolean = rawKeys.includes('fromPage');
          const hasCoverComponentId: boolean = rawKeys.includes('coverComponentId');

          if (hasManga || hasMangaId) {
            let inferredContentType: MangaReaderContentType = MangaReaderContentType.Local;
            if (hasSourceId) {
              // 路由参数没有下载状态信息，默认为在线未下载以触发网络链路
              inferredContentType = MangaReaderContentType.OnlineUndownloaded;
            }

            const resultParams: MangaReaderPageParams = {
              manga: hasManga ? (rawParamsObj['manga'] as Manga) : undefined,
              mangaId: hasMangaId ? String(rawParamsObj['mangaId']) : undefined,
              sourceId: hasSourceId ? Number(rawParamsObj['sourceId']) : undefined,
              contentType: inferredContentType,
              chapterId: hasChapterId ? String(rawParamsObj['chapterId']) : undefined,
              pageIndex: hasPageIndex ? Number(rawParamsObj['pageIndex']) : 0,
              fromPage: hasFromPage ? String(rawParamsObj['fromPage']) : '未指定',
              coverComponentId: hasCoverComponentId ? String(rawParamsObj['coverComponentId']) : undefined
            } as MangaReaderPageParams;

            this.pageParams = resultParams;
            logger.info(TAG, `📖 通过Router解析参数成功`);
            logger.info(TAG, `  - 内容类型: ${resultParams.contentType}`);
            logger.info(TAG, `  - 指定章节ID: ${resultParams.chapterId || '未指定'}`);
            logger.info(TAG, `  - 指定页面索引: ${resultParams.pageIndex || 0}`);
            this.initializeMangaReader(resultParams);
          } else {
            logger.error(TAG, '❌ Router参数缺少manga/mangaId字段');
          }
        } else {
          logger.error(TAG, '❌ UIContext Router不可用');
        }
      } catch (routerErr) {
        const msg: string = routerErr instanceof Error ? routerErr.message : String(routerErr);
        logger.error(TAG, `❌ 解析Router参数异常: ${msg}`);
      }
    }

    
    
    logger.lifecycle(TAG, '漫画阅读器页面显示完成');
    void this.refreshPageGuide('onPageShow');
  }

  private onAppBackgroundStateChanged(): void {
    if (this.appInBackground || !this.isPageVisible) {
      return;
    }
    this.scheduleFullscreenRestore('app_foreground', 80);
  }

  onPageHide() {
    this.isPageVisible = false;
    this.clearFullscreenRestoreTimer();
    logger.lifecycle(TAG, '漫画阅读器页面隐藏（进入后台）');
    // 初始化主题感知
    this.saveReadingProgressInternal('onPageHide').catch((error: Error) => {
      logger.error(TAG, '页面隐藏时保存阅读进度失败', error.message);
    });
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题已切换到: ${newTheme}`);
    });

    
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_manga_reader_root');
    } catch (error) {
      logger.warn(TAG, `获取漫画阅读器引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private async waitForGuideLayout(delayMs: number = 140): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }

  private async prepareGuidePresentation(anchorId?: string): Promise<void> {
    if (!anchorId || anchorId.length <= 0) {
      return;
    }
    let changed: boolean = false;
    if (this.autoHideTimer !== -1) {
      clearTimeout(this.autoHideTimer);
      this.autoHideTimer = -1;
    }
    switch (anchorId) {
      case 'guide_manga_reader_top_toolbar':
      case 'guide_manga_reader_bottom_toolbar':
        changed = !this.showTopToolbar || !this.showBottomToolbar || this.showSettingsPanel ||
          this.showQuickSettings || this.showMoreMenu || this.showChapterList ||
          this.showAutoPageTurnSettings || this.showPageTurnAnimationSettings || this.showJumpToPageDialog ||
          this.toolbarOpacity < 0.99;
        this.showSettingsPanel = false;
        this.showQuickSettings = false;
        this.showMoreMenu = false;
        this.showChapterList = false;
        this.showAutoPageTurnSettings = false;
        this.showPageTurnAnimationSettings = false;
        this.showJumpToPageDialog = false;
        this.showTopToolbar = true;
        this.showBottomToolbar = true;
        this.toolbarOpacity = 1;
        this.toolbarTranslateY = 0;
        break;
      case 'guide_manga_reader_chapter_list':
        changed = this.showTopToolbar || this.showBottomToolbar || !this.showChapterList ||
          this.showSettingsPanel || this.showQuickSettings || this.showMoreMenu ||
          this.showAutoPageTurnSettings || this.showPageTurnAnimationSettings || this.showJumpToPageDialog ||
          this.toolbarOpacity > 0.01;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.toolbarTranslateY = 0;
        this.showSettingsPanel = false;
        this.showQuickSettings = false;
        this.showMoreMenu = false;
        this.showAutoPageTurnSettings = false;
        this.showPageTurnAnimationSettings = false;
        this.showJumpToPageDialog = false;
        this.showChapterList = true;
        break;
      default:
        changed = this.showTopToolbar || this.showBottomToolbar || this.showSettingsPanel ||
          this.showQuickSettings || this.showMoreMenu || this.showChapterList ||
          this.showAutoPageTurnSettings || this.showPageTurnAnimationSettings || this.showJumpToPageDialog ||
          this.toolbarOpacity > 0.01;
        this.showTopToolbar = false;
        this.showBottomToolbar = false;
        this.toolbarOpacity = 0;
        this.toolbarTranslateY = 0;
        this.showSettingsPanel = false;
        this.showQuickSettings = false;
        this.showMoreMenu = false;
        this.showChapterList = false;
        this.showAutoPageTurnSettings = false;
        this.showPageTurnAnimationSettings = false;
        this.showJumpToPageDialog = false;
        break;
    }
    this.handleMenusVisibilityChange();
    if (changed) {
      await this.waitForGuideLayout();
    }
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.MANGA_READER);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.MANGA_READER) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      return;
    }
    await this.prepareGuidePresentation(step.anchorId);
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18);
    if (!this.appGuideHighlightRect && trigger !== 'retry_layout') {
      setTimeout(() => {
        void this.refreshPageGuide('retry_layout');
      }, 120);
    }
    logger.debug(TAG, `漫画阅读器引导已刷新: 触发源=${trigger}, 步骤=${step.id}`);
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

  aboutToAppear() {
    this.isPageVisible = true;
    logger.lifecycle(TAG, '漫画阅读器页面即将出现');
    
    // 初始化屏幕尺寸
    this.uiContext = this.getUIContext();
    const hostContext = this.uiContext.getHostContext();
    if (hostContext) {
      this.onlineArchiveService.setContext(hostContext as common.UIAbilityContext);
    }
    
    // 初始化响应式布局
    this.initScreenSize();
    
    // 初始化自动翻页控制器
    this.initResponsiveLayout();
    
    // 初始化WebView控制器（用于WebView图源动态加载）
    this.initAutoPageTurnController();
    
    // 设置全屏阅读模式的状态栏
    this.initWebViewController();

    // 应用屏幕常亮设置
    void this.refreshPageGuide('aboutToAppear');
    
    // 亮度设置已移除，不再应用
    this.applyKeepScreenOnSetting();
    
    // 启动阅读器流程
    
    // 启动阅读器流程
    this.updateVolumeKeyListener();
    
    // 启动入场动画
    this.startReaderFlow();
    
    // 启动阅读时间定时记录
    setTimeout(() => {
      this.startEntranceAnimation();
    }, 100);
    
    // 启动阅读时间定时记录
    this.startReadingTimeTracking();
  }
  
  /**
  * 启动阅读时间定时记录
  * 每1秒自动保存一次阅读进度，确保停留在同一页面时也能记录阅读时间
  */
  private startReadingTimeTracking(): void {
    // 每1秒保存一次阅读进度 
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
    }
    
      // 只有在阅读器已初始化后才保存
    this.readingTimeTimer = setInterval(() => {
      // 只有在阅读器已初始化后才保存
      if (this.isReaderInitialized && this.readerState.currentManga && this.readerState.currentChapter) {
        this.saveReadingProgressInternal('timer').catch((error: Error) => {
          logger.debug(TAG, `定时保存阅读进度失败: ${error.message}`);
        });
      }
    }, MangaReaderPage.READING_TIME_SAVE_INTERVAL);
    
    logger.info(TAG, '阅读时间定时记录已启动');
  }
  
  /**
  * 停止阅读时间定时记录
  */
  private stopReadingTimeTracking(): void {
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
      this.readingTimeTimer = -1;
      logger.info(TAG, '阅读时间定时记录已停止');
    }
  }
  
  /**
  * 应用屏幕常亮设置
  */
  private applyKeepScreenOnSetting(): void {
    try {
      const keepScreenOn = this.readingSettings.keepScreenOn;
      logger.info(TAG, `应用屏幕常亮设置: ${keepScreenOn}`);
      
      // 获取当前窗口并设置屏幕常亮
      window.getLastWindow(getContext(this)).then((windowStage: window.Window) => {
        windowStage.setWindowKeepScreenOn(keepScreenOn).then(() => {
          logger.info(TAG, `屏幕常亮设置成功: ${keepScreenOn}`);
        }).catch((err: BusinessError) => {
          logger.error(TAG, `设置屏幕常亮失败: ${err.message}`);
        });
      }).catch((err: BusinessError) => {
        logger.error(TAG, `获取窗口失败: ${err.message}`);
      });
    } catch (error) {
      logger.error(TAG, `应用屏幕常亮设置异常: ${String(error)}`);
    }
  }

  private syncDeviceOrientationLock(reason: string): void {
    if (!this.uiContext) {
      this.uiContext = this.getUIContext();
    }
    const enabled: boolean = this.readingSettings.lockDeviceOrientation ??
      DEFAULT_READING_SETTINGS.lockDeviceOrientation ??
      false;
    this.orientationLockToken = ReaderOrientationLockHelper.syncCurrentOrientationLock(
      'MangaReaderPage',
      this.orientationLockToken,
      enabled,
      this.uiContext
    );
    logger.info(TAG, `设备方向锁同步完成: enabled=${enabled}, reason=${reason}`);
  }

  /**
  * 应用亮度设置
  * brightness 范围: 0.1 - 2.0，其中 1.0 为默认亮度
  * 窗口亮度 API 范围: 0.0 - 1.0 或 -1.0（系统默认）
  */
  private applyBrightnessSetting(): void {
    try {
      let brightness = this.readingSettings.brightness;
      
      // 兼容旧数据：如果亮度值大于2.0，说明是旧的百分比格式（0-100或更大）
      // 将其转换为新格式（0.1-2.0）
      if (brightness > 2.0) {
        // 旧格式：50 表示 50%，对应新格式的 1.0
        brightness = brightness / 50.0;
        brightness = Math.max(0.1, Math.min(2.0, brightness));
        logger.info(TAG, `亮度值格式转换: 旧值=${this.readingSettings.brightness}, 新值=${brightness}`);
        // 更新设置中的亮度值
        this.readingSettings.brightness = brightness;
      }
      
      // 将 0.1-2.0 的范围映射到 0.0-1.0
      // brightness = 1.0 对应窗口亮度 0.5（中间值）
      // brightness = 0.1 对应窗口亮度 0.05
      // brightness = 2.0 对应窗口亮度 1.0
      const windowBrightness = Math.max(0.0, Math.min(1.0, brightness / 2.0));
      
      logger.info(TAG, `应用亮度设置: readingBrightness=${brightness.toFixed(2)}, windowBrightness=${windowBrightness.toFixed(2)}`);
      
      window.getLastWindow(getContext(this)).then((windowStage: window.Window) => {
        windowStage.setWindowBrightness(windowBrightness).then(() => {
          logger.info(TAG, `窗口亮度设置成功: ${windowBrightness.toFixed(2)}`);
        }).catch((err: BusinessError) => {
          logger.error(TAG, `设置窗口亮度失败: ${err.message}`);
        });
      }).catch((err: BusinessError) => {
        logger.error(TAG, `获取窗口失败: ${err.message}`);
      });
    } catch (error) {
      logger.error(TAG, `应用亮度设置异常: ${String(error)}`);
    }
  }

  /**
  * 恢复默认亮度
  */
  private restoreBrightnessSetting(): void {
    try {
      window.getLastWindow(getContext(this)).then((windowStage: window.Window) => {
        // 设置为 -1 表示使用系统默认亮度
        windowStage.setWindowBrightness(-1).then(() => {
          logger.info(TAG, '窗口亮度已恢复为系统默认');
        }).catch((err: BusinessError) => {
          logger.error(TAG, `恢复窗口亮度失败: ${err.message}`);
        });
      }).catch((err: BusinessError) => {
        logger.error(TAG, `获取窗口失败: ${err.message}`);
      });
    } catch (error) {
      logger.error(TAG, `恢复亮度设置异常: ${String(error)}`);
    }
  }

  /**
  * 初始化响应式布局
  */
  private initResponsiveLayout(): void {
    try {
      // 创建并注册设备变化监听器
      this.shouldUseDoublePage = ResponsiveLayoutHelper.shouldUseDoublePage();
      
      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
          logger.info(TAG, `双页模式状态变化: ${this.shouldUseDoublePage ? '开启' : '关闭'}`);
        const newShouldUseDoublePage = ResponsiveLayoutHelper.shouldUseDoublePage();
        
        if (newShouldUseDoublePage !== this.shouldUseDoublePage) {
          this.shouldUseDoublePage = newShouldUseDoublePage;
      logger.info(TAG, `✅ 响应式布局初始化完成, 建议双页模式: ${this.shouldUseDoublePage}`);
          // 注意：阅读模式的实际切换应该根据用户设置，这里仅作提示
        }
      };
      
      this.deviceManager.addListener(this.deviceChangeListener);
      
      logger.info(TAG, `✅ 响应式布局初始化完成, 建议双页模式: ${this.shouldUseDoublePage}`);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  aboutToDisappear() {
    this.isPageVisible = false;
    this.webViewControllerAttached = false;
    this.clearFullscreenRestoreTimer();
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    
    // 通知预加载管理器：阅读器已关闭
    this.lifecycle.destroy();
    
    // 停止阅读时间定时记录
    ChapterPreloadManager.getInstance().setReaderActive(false);
    
    // 移除设备变化监听器
    this.stopReadingTimeTracking();
    
    // 离开前尝试保存阅读进度
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    
    // 销毁自动翻页控制器
    void this.persistReadingSettings('about_to_disappear');
    this.saveReadingProgressInternal('aboutToDisappear').catch((error: Error) => {
      logger.error(TAG, '离开页面前保存阅读进度失败', error.message);
    });
    
    // 清理WebView资源
    if (this.autoPageTurnController) {
      this.autoPageTurnController.destroy();
      this.autoPageTurnController = null;
    }
    
    // 清理定时器
    this.cleanupWebView();

    // 清理定时器
    if (this.autoHideTimer !== -1) {
      clearTimeout(this.autoHideTimer);
      this.autoHideTimer = -1;
    }
    
    if (this.overlayDismissTimer !== -1) {
      clearTimeout(this.overlayDismissTimer);
      this.overlayDismissTimer = -1;
    }
    
    if (this.singleTapTimer !== -1) {
      clearTimeout(this.singleTapTimer);
      this.singleTapTimer = -1;
    }
    if (this.webtoonOnlineAdjacentWarmupTimer !== -1) {
      clearTimeout(this.webtoonOnlineAdjacentWarmupTimer);
      this.webtoonOnlineAdjacentWarmupTimer = -1;
    }
    this.webtoonOnlineAdjacentLoadingChapterIds.clear();
    this.clearTransitionReaderReadyTimers();

    // 恢复系统默认亮度
    this.restoreKeepScreenOnSetting();
    
    // 注销音量键监听
    this.restoreBrightnessSetting();
    
    // 恢复正常状态栏模式
    this.unregisterVolumeKeyListener();
    this.orientationLockToken = ReaderOrientationLockHelper.release(this.orientationLockToken, this.uiContext);

    // 清理主题感知
    this.restoreNormalMode();

    // [修复] 发布阅读进度更新事件，通知书库页面刷新
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    eventBus.publish(GameEvent.MANGA_READING_PROGRESS_UPDATED, new BasePayload());
    
    // [修复] 安全清理过渡动画状态，防止页面销毁后覆盖层仍然阻止交互
    if (this.shouldUseReaderTransition() && !this.isCloseTransitionNavigating) {
      cancelTransition();
    } else if (this.shouldUseReaderTransition()) {
      logger.info(TAG, 'aboutToDisappear: close transition in progress, skip cancelTransition');
    }
    
    logger.lifecycle(TAG, '漫画阅读器页面即将消失');
  }
  
  /**
  * 恢复屏幕常亮设置（离开页面时关闭常亮）
  */
  private restoreKeepScreenOnSetting(): void {
    try {
      window.getLastWindow(getContext(this)).then((windowStage: window.Window) => {
        windowStage.setWindowKeepScreenOn(false).then(() => {
          logger.info(TAG, '屏幕常亮已关闭');
        }).catch((err: BusinessError) => {
          logger.error(TAG, `关闭屏幕常亮失败: ${err.message}`);
        });
      }).catch((err: BusinessError) => {
        logger.error(TAG, `获取窗口失败: ${err.message}`);
      });
    } catch (error) {
      logger.error(TAG, `恢复屏幕常亮设置异常: ${String(error)}`);
    }
  }

  /**
  * 初始化屏幕尺寸
  * 注意：统一使用vp单位，确保与ClickEvent.displayX/displayY坐标系统一致
  */
  private initScreenSize(): void {
    let displayClass: display.Display | null = null;
    try {
        // 获取物理像素尺寸和屏幕密度
      displayClass = display.getDefaultDisplaySync();
      if (displayClass) {
        // 转换为vp单位（ClickEvent.displayX/displayY使用vp单位）
        const physicalWidth = displayClass.width;
        const physicalHeight = displayClass.height;
        const densityPixels = displayClass.densityPixels || 1.0;
        
        // 使用默认值（vp单位）
        // vp = px / densityPixels
        this.screenWidth = physicalWidth / densityPixels;
        this.screenHeight = physicalHeight / densityPixels;
        this.isLandscapeMode = this.screenWidth > this.screenHeight;
        logger.debug(TAG, `屏幕尺寸初始化: ${physicalWidth}x${physicalHeight}px -> ${this.screenWidth.toFixed(0)}x${this.screenHeight.toFixed(0)}vp (density=${densityPixels})`);
      } else {
      // 使用默认值（vp单位）
        this.screenWidth = 360;
        this.screenHeight = 780;
        logger.warn(TAG, '无法获取屏幕尺寸，使用默认值(vp)');
      }
    } catch (exception) {
      // 使用默认值（vp单位）
      this.screenWidth = 360;
      this.screenHeight = 780;
      logger.error(TAG, `获取屏幕尺寸失败，使用默认值(vp). Code: ${(exception as BusinessError).code}, message: ${(exception as BusinessError).message}`);
    }
  }
  
  /**
  * 初始化自动翻页控制器
  */
  private initAutoPageTurnController(): void {
    const config: AutoPageTurnConfig = {
      interval: this.readingSettings.autoPageTurnInterval,
      skipIntro: this.readingSettings.skipIntroPages > 0,
      skipIntroPages: this.readingSettings.skipIntroPages,
      autoSwitchChapter: false
    };
    
    this.autoPageTurnController = new AutoPageTurnController(config);
    
          // 条漫模式：使用异步翻页，等待滚动完成
    this.autoPageTurnController.setCallbacks(
      () => {
        if (this.isScrollableReaderMode()) {
            // 翻页完成后，通知控制器继续下一次翻页
            logger.debug(TAG, '条漫模式自动翻页完成，准备下一次翻页');
          this.goToNextPage(() => {
          // 其他模式：使用同步翻页
          logger.debug(TAG, '自动翻页触发（非条漫模式）');
          });
        } else {
          // 其他模式：使用同步翻页
          logger.debug(TAG, '自动翻页触发（非条漫模式）');
          this.goToNextPage();
        }
      },
      () => this.readerState.currentPageIndex,
      () => this.readerState.currentChapter?.pages.length || 0
    );
    
    logger.info(TAG, '自动翻页控制器已初始化');
  }

  /**
  * 初始化WebView控制器
  * 用于WebView图源的动态页面加载
  */
  private initWebViewController(): void {
    try {
      // 将WebView控制器注册到WebViewSourceManager
      this.webViewManager.setGlobalWebViewController(this.webviewController);
      logger.info(TAG, '✅ WebView控制器已初始化并注册到WebViewSourceManager');
    } catch (error) {
      logger.error(TAG, '❌ WebView控制器初始化失败', String(error));
    }
  }

  /**
  * 清理WebView资源
  */
  private cleanupWebView(): void {
    try {
        // 注意：WebviewController不需要显式销毁，但可以清理相关状态
      if (this.webviewController) {
        logger.info(TAG, '🧹 清理WebView控制器资源');
        // 注意：WebviewController不需要显式销毁，但可以清理相关状态
      }
    } catch (error) {
      logger.error(TAG, '❌ 清理WebView资源失败', String(error));
    }
  }

  /**
  * 自动翻页完成回调
  * 用于处理异步翻页操作完成后的状态更新
  */
  private onAutoPageTurnComplete(): void {
    logger.debug(TAG, '自动翻页操作完成，准备下一次翻页');
    // 控制器会自动安排下一次翻页
  }

  /**
  * 设置自动翻页间隔（秒，1-10），并更新阅读设置与控制器配置
  */
  private setAutoPageTurnIntervalSeconds(value: number): void {
    const clamped: number = Math.max(1, Math.min(10, value));
    this.autoPageTurnIntervalSeconds = clamped;
    this.readingSettings.autoPageTurnInterval = this.autoPageTurnEnabled ? clamped : 0;
    this.updateAutoPageTurnConfig();
    void this.persistReadingSettings('update_auto_page_turn_interval');
    logger.info(TAG, `自动翻页间隔更新为: ${clamped}s`);
  }

  /**
  * 设置自动翻页启用状态
  */
  private setAutoPageTurnEnabled(enabled: boolean): void {
    this.autoPageTurnEnabled = enabled;
    this.readingSettings.autoPageTurnInterval = enabled ? this.autoPageTurnIntervalSeconds : 0;
    const persistTrigger = enabled ? 'toggle_auto_page_turn_enabled' : 'toggle_auto_page_turn_disabled';
    void this.persistReadingSettings(persistTrigger);
    if (!this.autoPageTurnController) {
      logger.warn(TAG, '自动翻页控制器未初始化');
      return;
    }
    this.updateAutoPageTurnConfig();
    if (enabled) {
      this.autoPageTurnController.start();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
      logger.info(TAG, '自动翻页已开启');
    } else {
      this.autoPageTurnController.stop();
      this.autoPageTurnState = AutoPageTurnState.STOPPED;
      // 清理交互暂停定时器
      if (this.interactionPauseTimer !== -1) {
        clearTimeout(this.interactionPauseTimer);
        this.interactionPauseTimer = -1;
      }
      logger.info(TAG, '自动翻页已关闭');
    }
  }

  /**
  * 用户交互触发暂停1s（点击、滑动等）
  */
  private delayAutoPageTurnForInteraction(): void {
    if (!this.autoPageTurnEnabled || !this.autoPageTurnController) {
      return;
    }
    const currentState: AutoPageTurnState = this.autoPageTurnController.getState();
    if (currentState === AutoPageTurnState.RUNNING) {
      this.autoPageTurnController.pause();
      logger.info(TAG, '自动翻页：检测到用户交互，暂停1s');
    }
    if (this.interactionPauseTimer !== -1) {
      clearTimeout(this.interactionPauseTimer);
    }
    this.interactionPauseTimer = setTimeout(() => {
      this.interactionPauseTimer = -1;
      if (!this.areMenusVisible() && this.autoPageTurnEnabled && this.autoPageTurnController) {
        this.autoPageTurnController.resume();
        logger.info(TAG, '自动翻页：交互暂停结束，恢复');
      }
    }, 1000) as number;
  }

  /**
  * 菜单显示状态变化时的处理：暂停并重置计时/恢复计时
  */
  private handleMenusVisibilityChange(): void {
    if (this.areMenusVisible()) {
      this.pauseAutoPageTurnAndResetTimer('menus-visible');
    } else {
      this.resumeAutoPageTurnIfEnabled('menus-hidden');
    }
  }

  private areMenusVisible(): boolean {
    return this.showTopToolbar || this.showBottomToolbar || this.showSettingsPanel ||
      this.showQuickSettings || this.showMoreMenu || this.showChapterList || 
      this.showAutoPageTurnSettings || this.showPageTurnAnimationSettings || this.showJumpToPageDialog;
  }

  private pauseAutoPageTurnAndResetTimer(reason: string): void {
    if (!this.autoPageTurnController || !this.autoPageTurnEnabled) {
      return;
    }
    const state: AutoPageTurnState = this.autoPageTurnController.getState();
    if (state === AutoPageTurnState.RUNNING) {
      this.autoPageTurnController.pause();
      logger.info(TAG, `自动翻页：${reason}，暂停并重置计时`);
    }
    if (this.interactionPauseTimer !== -1) {
      clearTimeout(this.interactionPauseTimer);
      this.interactionPauseTimer = -1;
    }
  }

  private resumeAutoPageTurnIfEnabled(reason: string): void {
    if (!this.autoPageTurnController || !this.autoPageTurnEnabled) {
      return;
    }
    const state: AutoPageTurnState = this.autoPageTurnController.getState();
    if (state === AutoPageTurnState.PAUSED) {
      // 为满足“重置计时”要求，先停止再启动，确保计时从零开始
      this.autoPageTurnController.stop();
      this.autoPageTurnController.start();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
      logger.info(TAG, `自动翻页：${reason}，重置并继续计时`);
    }
  }

  /**
  * 自动翻页设置面板开关
  */
  private toggleAutoPageTurnSettings(): void {
    if (this.showAutoPageTurnSettings) {
      this.hideAutoPageTurnSettingsWithAnimation();
    } else {
      this.showAutoPageTurnSettingsWithAnimation();
    }
    this.handleMenusVisibilityChange();
  }
  
  /**
  * 显示自动翻页设置面板（带动画）
  */
  private showAutoPageTurnSettingsWithAnimation(): void {
    // 设置初始状态
    this.autoPageTurnSettingsOpacity = 0;
    this.autoPageTurnSettingsScale = 0.95;
    this.autoPageTurnSettingsTranslateY = 20;
    this.autoPageTurnSettingsTranslateX = 320;
    this.showAutoPageTurnSettings = true;
    
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 250,
        curve: Curve.EaseOut
      }, () => {
        this.autoPageTurnSettingsOpacity = 1;
        this.autoPageTurnSettingsScale = 1;
        this.autoPageTurnSettingsTranslateY = 0;
        this.autoPageTurnSettingsTranslateX = 0;
      });
    } else {
      this.autoPageTurnSettingsOpacity = 1;
      this.autoPageTurnSettingsScale = 1;
      this.autoPageTurnSettingsTranslateY = 0;
      this.autoPageTurnSettingsTranslateX = 0;
    }
  }
  
  /**
  * 隐藏自动翻页设置面板（带动画）
  */
  private hideAutoPageTurnSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showAutoPageTurnSettings = false;
        }
      }, () => {
        this.autoPageTurnSettingsOpacity = 0;
        this.autoPageTurnSettingsScale = 0.95;
        this.autoPageTurnSettingsTranslateY = 20;
        this.autoPageTurnSettingsTranslateX = 320;
      });
    } else {
      this.showAutoPageTurnSettings = false;
    }
  }

  /**
  * 自动翻页按钮图标（启用/禁用）
  */
  private getAutoPageTurnIconResource(): Resource {
    return this.autoPageTurnEnabled ? $r('sys.symbol.airplane_departure') : $r('sys.symbol.airplane_arrival');
  }
  
  /**
  * 切换自动翻页状态
  */
  private toggleAutoPageTurn(): void {
    if (!this.autoPageTurnController) {
      logger.error(TAG, '自动翻页控制器未初始化');
      return;
    }
    
    const currentState = this.autoPageTurnController.getState();
    
    if (currentState === AutoPageTurnState.STOPPED) {
      this.autoPageTurnController.start();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
      logger.info(TAG, '自动翻页已暂停');
    } else if (currentState === AutoPageTurnState.RUNNING) {
      this.autoPageTurnController.pause();
      this.autoPageTurnState = AutoPageTurnState.PAUSED;
      logger.info(TAG, '自动翻页已恢复');
    } else if (currentState === AutoPageTurnState.PAUSED) {
      this.autoPageTurnController.resume();
      this.autoPageTurnState = AutoPageTurnState.RUNNING;
      logger.info(TAG, '自动翻页已恢复');
    }
  }
  
  /**
  * 停止自动翻页
  */
  private stopAutoPageTurn(): void {
    if (this.autoPageTurnController) {
      this.autoPageTurnController.stop();
      this.autoPageTurnState = AutoPageTurnState.STOPPED;
      logger.info(TAG, '自动翻页已停止');
    }
  }
  
  /**
  * 更新自动翻页配置
  */
  private updateAutoPageTurnConfig(): void {
    if (!this.autoPageTurnController) {
      return;
    }
    
    const config: AutoPageTurnConfig = {
      interval: this.readingSettings.autoPageTurnInterval,
      skipIntro: this.readingSettings.skipIntroPages > 0,
      skipIntroPages: this.readingSettings.skipIntroPages,
      autoSwitchChapter: false
    };
    
    this.autoPageTurnController.setConfig(config);
    logger.info(TAG, '自动翻页配置已更新');
  }

  /**
  * [新增] 强制更新网络请求头，确保Referer正确
  * 必须在 currentChapter 确定后调用
  */
  private isPhotos18Source(): boolean {
    if (this.currentSourcePkg === 'com.manxia.extension.all.photos18') {
      return true;
    }
    if (this.pageParams?.sourcePkg === 'com.manxia.extension.all.photos18') {
      return true;
    }
    const sourceName = this.pageParams?.sourceName || '';
    if (sourceName.toLowerCase().includes('photos18')) {
      return true;
    }
    return false;
  }

  private trimTrailingSlash(url: string): string {
    const trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  private isHttpUrl(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  private extractUrlOrigin(value: string): string {
    const trimmed = value.trim();
    const match = trimmed.match(/^(https?:\/\/[^\/]+)/);
    if (match && match[1]) {
      return match[1];
    }
    return '';
  }

  private extractUrlHost(value: string): string {
    const origin = this.extractUrlOrigin(value);
    const match = origin.match(/^https?:\/\/(.+)$/);
    if (match && match[1]) {
      return match[1];
    }
    return '';
  }

  private isApiLikeUrl(value: string): boolean {
    const normalized = this.trimTrailingSlash(value);
    const host = this.extractUrlHost(normalized);
    if (host.startsWith('api.') || host.startsWith('mapi.')) {
      return true;
    }
    return normalized.includes('/api/');
  }

  private buildRequestOrigin(referer: string, explicitOrigin?: string): string {
    if (explicitOrigin && explicitOrigin.trim().length > 0) {
      const explicitValue = this.extractUrlOrigin(explicitOrigin);
      if (explicitValue.length > 0) {
        return explicitValue;
      }
    }
    return this.extractUrlOrigin(referer);
  }

  private getDefaultReaderRequestUserAgent(): string {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
  }

  private getPhotos18RequestUserAgent(): string {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  }

  private normalizeUserAgentValue(userAgent?: string): string {
    return userAgent ? userAgent.trim() : '';
  }

  private syncHiddenWebViewUserAgent(expectedUserAgent?: string): boolean {
    const normalizedExpected = this.normalizeUserAgentValue(expectedUserAgent);
    if (normalizedExpected.length === 0) {
      return false;
    }

    try {
      const currentCustomUserAgent = this.normalizeUserAgentValue(this.webviewController.getCustomUserAgent());
      if (currentCustomUserAgent === normalizedExpected) {
        return false;
      }
    } catch (error) {
      logger.debug(TAG, `Hidden WebView getCustomUserAgent failed, force sync continues: ${String(error)}`);
    }

    this.webviewController.setCustomUserAgent(normalizedExpected);
    logger.info(TAG, `Hidden WebView user agent synced: length=${normalizedExpected.length}`);
    return true;
  }

  private cloneRequestHeaderEntries(entries?: RequestHeaderEntry[]): RequestHeaderEntry[] | undefined {
    if (!entries || entries.length === 0) {
      return undefined;
    }
    const clonedEntries: RequestHeaderEntry[] = [];
    let index = 0;
    while (index < entries.length) {
      const entry = entries[index];
      if (entry && entry.name && entry.value) {
        clonedEntries.push({
          name: String(entry.name),
          value: String(entry.value)
        } as RequestHeaderEntry);
      }
      index = index + 1;
    }
    return clonedEntries.length > 0 ? clonedEntries : undefined;
  }

  private cloneRequestHeaders(headers?: RequestHeaders): RequestHeaders {
    const clonedHeaders: RequestHeaders = {} as RequestHeaders;
    if (!headers) {
      return clonedHeaders;
    }
    if (headers.userAgent) { clonedHeaders.userAgent = String(headers.userAgent); }
    if (headers.accept) { clonedHeaders.accept = String(headers.accept); }
    if (headers.referer) { clonedHeaders.referer = String(headers.referer); }
    if (headers.origin) { clonedHeaders.origin = String(headers.origin); }
    if (headers.cookie) { clonedHeaders.cookie = String(headers.cookie); }
    if (headers.authorization) { clonedHeaders.authorization = String(headers.authorization); }
    if (headers.acceptLanguage) { clonedHeaders.acceptLanguage = String(headers.acceptLanguage); }
    if (headers.cacheControl) { clonedHeaders.cacheControl = String(headers.cacheControl); }
    if (headers.pragma) { clonedHeaders.pragma = String(headers.pragma); }
    if (headers.secFetchDest) { clonedHeaders.secFetchDest = String(headers.secFetchDest); }
    if (headers.secFetchMode) { clonedHeaders.secFetchMode = String(headers.secFetchMode); }
    if (headers.secFetchSite) { clonedHeaders.secFetchSite = String(headers.secFetchSite); }
    if (headers.cachePartition) { clonedHeaders.cachePartition = String(headers.cachePartition); }
    const extraHeaders = this.cloneRequestHeaderEntries(headers.extraHeaders);
    if (extraHeaders) {
      clonedHeaders.extraHeaders = extraHeaders;
    }
    return clonedHeaders;
  }

  private cloneSourcePageRequestHeaders(pageInfo: SourcePageInfo): MangaImageRequestHeader[] | undefined {
    const sourceHeaders: SourcePageRequestHeader[] | undefined = pageInfo.requestHeaders;
    if (!sourceHeaders || sourceHeaders.length === 0) {
      return undefined;
    }
    const clonedHeaders: MangaImageRequestHeader[] = [];
    let index = 0;
    while (index < sourceHeaders.length) {
      const header = sourceHeaders[index];
      if (header && header.name && header.value) {
        clonedHeaders.push({
          name: String(header.name),
          value: String(header.value)
        } as MangaImageRequestHeader);
      }
      index = index + 1;
    }
    return clonedHeaders.length > 0 ? clonedHeaders : undefined;
  }

  private isKomiicSourceForReader(): boolean {
    let baseUrl = '';
    const engine: MangaSourceEngine | null = this.mangaEngine;
    if (engine) {
      const config = engine.getConfig();
      if (config && config.metadata && config.metadata.baseUrl) {
        baseUrl = String(config.metadata.baseUrl).toLowerCase();
      }
    }

    const sourceName = this.pageParams && this.pageParams.sourceName
      ? String(this.pageParams.sourceName).toLowerCase()
      : '';
    const sourcePkg = this.pageParams && this.pageParams.sourcePkg
      ? String(this.pageParams.sourcePkg).toLowerCase()
      : String(this.currentSourcePkg || '').toLowerCase();
    const mangaSourceName = this.readerState.currentManga && this.readerState.currentManga.sourceInfo && this.readerState.currentManga.sourceInfo.sourceName
      ? String(this.readerState.currentManga.sourceInfo.sourceName).toLowerCase()
      : '';

    return baseUrl.indexOf('komiic.com') >= 0 ||
      sourceName.indexOf('komiic') >= 0 ||
      sourcePkg.indexOf('komiic') >= 0 ||
      mangaSourceName.indexOf('komiic') >= 0;
  }

  private shouldRefreshVolatileSourcePages(): boolean {
    return this.isKomiicSourceForReader();
  }

  private appendExtraRequestHeader(target: RequestHeaders, headerName: string, headerValue: string): void {
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
    } as RequestHeaderEntry);
  }

  private applyConfiguredRequestHeader(
    target: RequestHeaders,
    headerName: string,
    headerValue: string,
    allowExtraHeaders: boolean,
    includeExtendedFields: boolean
  ): void {
    const normalizedName = headerName.trim().toLowerCase();
    const normalizedValue = headerValue.trim();
    if (normalizedName.length === 0 || normalizedValue.length === 0) {
      return;
    }
    switch (normalizedName) {
      case 'user-agent':
        target.userAgent = normalizedValue;
        return;
      case 'referer':
        target.referer = normalizedValue;
        return;
      case 'origin':
        target.origin = this.buildRequestOrigin('', normalizedValue);
        return;
      case 'authorization':
        target.authorization = normalizedValue;
        return;
      case 'cookie':
        target.cookie = normalizedValue;
        return;
      case 'accept-language':
        target.acceptLanguage = normalizedValue;
        return;
      case 'accept':
        if (includeExtendedFields) {
          target.accept = normalizedValue;
        }
        return;
      case 'cache-control':
        if (includeExtendedFields) {
          target.cacheControl = normalizedValue;
        }
        return;
      case 'pragma':
        if (includeExtendedFields) {
          target.pragma = normalizedValue;
        }
        return;
      case 'sec-fetch-dest':
        if (includeExtendedFields) {
          target.secFetchDest = normalizedValue;
        }
        return;
      case 'sec-fetch-mode':
        if (includeExtendedFields) {
          target.secFetchMode = normalizedValue;
        }
        return;
      case 'sec-fetch-site':
        if (includeExtendedFields) {
          target.secFetchSite = normalizedValue;
        }
        return;
      case 'cache-partition':
        if (includeExtendedFields) {
          target.cachePartition = normalizedValue;
        }
        return;
      default:
        if (allowExtraHeaders) {
          this.appendExtraRequestHeader(target, headerName, normalizedValue);
        }
        return;
    }
  }

  private applyConfiguredRequestHeaderMap(
    target: RequestHeaders,
    headerMap?: SourceConfigHeaderMap,
    allowExtraHeaders: boolean = true,
    includeExtendedFields: boolean = true
  ): void {
    if (!headerMap) {
      return;
    }
    const headerKeys = Object.keys(headerMap);
    let index = 0;
    while (index < headerKeys.length) {
      const headerKey = headerKeys[index];
      const headerValue = String(headerMap[headerKey]).trim();
      if (headerValue.length > 0) {
        this.applyConfiguredRequestHeader(target, headerKey, headerValue, allowExtraHeaders, includeExtendedFields);
      }
      index = index + 1;
    }
  }

  private normalizeConfiguredDomainValue(value: string, sourceConfig: SourceConfigJsonLike | null): string {
    const trimmedValue = this.trimTrailingSlash(value);
    if (trimmedValue.length === 0) {
      return '';
    }
    if (this.isHttpUrl(trimmedValue)) {
      return trimmedValue;
    }
    if (sourceConfig && sourceConfig.metadata && sourceConfig.metadata.alternativeUrls) {
      const alternativeUrls = sourceConfig.metadata.alternativeUrls;
      const keys = Object.keys(alternativeUrls);
      let index = 0;
      while (index < keys.length) {
        const key = keys[index];
        if (key === trimmedValue) {
          const resolvedUrl = alternativeUrls[key];
          if (resolvedUrl && this.isHttpUrl(String(resolvedUrl))) {
            return this.trimTrailingSlash(String(resolvedUrl));
          }
        }
        index++;
      }
    }
    return '';
  }

  private buildSourceReferer(baseUrl: string, originHint: string, refererHint: string): string {
    const normalizedRefererHint = this.trimTrailingSlash(refererHint);
    if (normalizedRefererHint.length > 0) {
      return normalizedRefererHint;
    }
    const normalizedOriginHint = this.trimTrailingSlash(originHint);
    const normalizedBaseUrl = this.trimTrailingSlash(baseUrl);
    if (normalizedBaseUrl.length === 0) {
      return normalizedOriginHint.length > 0 ? `${normalizedOriginHint}/` : '';
    }
    if (normalizedOriginHint.length > 0 && this.isApiLikeUrl(normalizedBaseUrl)) {
      return `${normalizedOriginHint}/`;
    }
    return normalizedBaseUrl;
  }

  private parseSourceConfigJson(configJson: string): SourceConfigJsonLike | null {
    try {
      return JSON.parse(configJson) as SourceConfigJsonLike;
    } catch (error) {
      logger.warn(TAG, `解析图源配置失败: ${String(error)}`);
      return null;
    }
  }

  private async resolveSourceRequestContext(sourceId: number, fallbackBaseUrl: string): Promise<SourceRequestContext> {
    const requestContext: SourceRequestContext = {
      requestBaseUrl: this.trimTrailingSlash(fallbackBaseUrl),
      refererHint: '',
      originHint: '',
      headerTemplate: {} as RequestHeaders,
      userAgentLocked: false
    } as SourceRequestContext;

    let sourceConfig: SourceConfigJsonLike | null = null;
    try {
      const sourceRecord: ComicSourceDatabaseRecord | null = await DataManager.getInstance().getComicSourceById(sourceId);
      if (sourceRecord && sourceRecord.configJson) {
        sourceConfig = this.parseSourceConfigJson(String(sourceRecord.configJson));
      }
      if (sourceConfig && sourceConfig.network) {
        if (sourceConfig.network.userAgent) {
          const configuredUserAgent = String(sourceConfig.network.userAgent).trim();
          if (configuredUserAgent.length > 0) {
            requestContext.headerTemplate.userAgent = configuredUserAgent;
            requestContext.userAgentLocked = true;
          }
        }
        this.applyConfiguredRequestHeaderMap(requestContext.headerTemplate, sourceConfig.network.headers, false, false);
      }
      if (sourceConfig && sourceConfig.imageHeaders) {
        this.applyConfiguredRequestHeaderMap(requestContext.headerTemplate, sourceConfig.imageHeaders, true, true);
      }
      if (requestContext.headerTemplate.referer && requestContext.headerTemplate.referer.length > 0) {
        requestContext.refererHint = String(requestContext.headerTemplate.referer);
      }
      if (requestContext.headerTemplate.origin && requestContext.headerTemplate.origin.length > 0) {
        requestContext.originHint = this.buildRequestOrigin('', String(requestContext.headerTemplate.origin));
      }
      if (requestContext.headerTemplate.userAgent && requestContext.headerTemplate.userAgent.length > 0) {
        requestContext.userAgentLocked = true;
      }
      if (sourceConfig && sourceConfig.settings) {
        const defaultDomain = sourceConfig.settings.domain && sourceConfig.settings.domain.default
          ? this.normalizeConfiguredDomainValue(String(sourceConfig.settings.domain.default), sourceConfig)
          : '';
        if (defaultDomain.length > 0) {
          requestContext.requestBaseUrl = defaultDomain;
        }
        if (requestContext.requestBaseUrl.length === 0) {
          const defaultApiDomain = sourceConfig.settings.apiDomain && sourceConfig.settings.apiDomain.default
            ? this.normalizeConfiguredDomainValue(String(sourceConfig.settings.apiDomain.default), sourceConfig)
            : '';
          if (defaultApiDomain.length > 0) {
            requestContext.requestBaseUrl = defaultApiDomain;
          }
        }
      }

      const domainSetting: UserSettingsDatabaseRecord | null = await DataManager.getInstance().getSourceUserSetting(sourceId, 'domain');
      if (domainSetting && domainSetting.settingValue) {
        const resolvedDomain = this.normalizeConfiguredDomainValue(String(domainSetting.settingValue), sourceConfig);
        if (resolvedDomain.length > 0) {
          requestContext.requestBaseUrl = resolvedDomain;
        }
      }
      const apiDomainSetting: UserSettingsDatabaseRecord | null = await DataManager.getInstance().getSourceUserSetting(sourceId, 'apiDomain');
      if (apiDomainSetting && apiDomainSetting.settingValue) {
        const resolvedApiDomain = this.normalizeConfiguredDomainValue(String(apiDomainSetting.settingValue), sourceConfig);
        if (resolvedApiDomain.length > 0) {
          requestContext.requestBaseUrl = resolvedApiDomain;
        }
      }
    } catch (error) {
      logger.warn(TAG, `读取图源请求上下文失败: sourceId=${sourceId}, error=${String(error)}`);
    }

    if (requestContext.originHint.length === 0) {
      requestContext.originHint = this.buildRequestOrigin(requestContext.refererHint, requestContext.requestBaseUrl);
    }
    requestContext.refererHint = this.buildSourceReferer(
      requestContext.requestBaseUrl,
      requestContext.originHint,
      requestContext.refererHint
    );
    return requestContext;
  }

  private getPhotos18Origin(): string {
    return 'https://www.photos18.com';
  }

  private isInvalidPhotos18RefererCandidate(value: string): boolean {
    const trimmed = value.trim();
    return trimmed.length === 0 || trimmed.startsWith('id_') || trimmed.startsWith('local_');
  }

  private buildPhotos18GalleryUrl(rawValue: string): string {
    let candidate = rawValue.trim();
    if (candidate.length === 0) {
      return '';
    }
    const schemeIndex = candidate.indexOf('://');
    if (schemeIndex >= 0) {
      const pathIndex = candidate.indexOf('/', schemeIndex + 3);
      candidate = pathIndex >= 0 ? candidate.substring(pathIndex) : '';
    }
    const queryIndex = candidate.indexOf('?');
    if (queryIndex >= 0) {
      candidate = candidate.substring(0, queryIndex);
    }
    const hashIndex = candidate.indexOf('#');
    if (hashIndex >= 0) {
      candidate = candidate.substring(0, hashIndex);
    }
    if (candidate.startsWith('/zh-hans/')) {
      candidate = candidate.substring('/zh-hans/'.length);
    } else if (candidate === '/zh-hans') {
      candidate = '';
    }
    candidate = candidate.replace(/^\/+/, '').replace(/\/+$/, '');
    if (candidate.startsWith('v/')) {
      candidate = candidate.substring(2);
    }
    if (candidate.length === 0) {
      return '';
    }
    return `${this.getPhotos18Origin()}/v/${candidate}`;
  }

  private buildPhotos18CachePartition(referer: string): string {
    const normalizedReferer = referer.trim().length > 0 ? referer.trim() : this.getPhotos18Origin();
    let hash = 0;
    for (let i = 0; i < normalizedReferer.length; i++) {
      const charCode = normalizedReferer.charCodeAt(i);
      hash = ((hash << 5) - hash) + charCode;
      hash = hash & hash;
    }
    return `photos18_reader_${Math.abs(hash).toString(36)}`;
  }

  private resolvePhotos18ReaderReferer(manga?: Manga | null, chapter?: MangaChapter | null): string {
    let candidate = '';
    if (chapter) {
      const chapterWithExternalId = chapter as ChapterInfoToMangaChapterConverter;
      if (chapterWithExternalId.externalId && !this.isInvalidPhotos18RefererCandidate(chapterWithExternalId.externalId)) {
        candidate = chapterWithExternalId.externalId;
      } else if (!this.isInvalidPhotos18RefererCandidate(chapter.id)) {
        candidate = chapter.id;
      }
    }
    if (candidate.length === 0 && manga && manga.sourceInfo && !this.isInvalidPhotos18RefererCandidate(manga.sourceInfo.sourceUrl)) {
      candidate = manga.sourceInfo.sourceUrl;
    }
    const referer = this.buildPhotos18GalleryUrl(candidate);
    return referer.length > 0 ? referer : this.getPhotos18Origin();
  }

  private resolvePhotos18ReaderRefererFromParams(
    params: MangaReaderPageParams,
    manga?: Manga | null,
    chapter?: MangaChapter | null
  ): string {
    const resolvedFromState = this.resolvePhotos18ReaderReferer(manga, chapter);
    if (resolvedFromState !== this.getPhotos18Origin()) {
      return resolvedFromState;
    }

    let candidate = '';
    if (params.chapterId && !this.isInvalidPhotos18RefererCandidate(params.chapterId)) {
      candidate = params.chapterId;
    }

    if (candidate.length === 0 && params.manga && params.manga.sourceInfo &&
      !this.isInvalidPhotos18RefererCandidate(params.manga.sourceInfo.sourceUrl)) {
      candidate = params.manga.sourceInfo.sourceUrl;
    }

    if (candidate.length === 0 && params.mangaId && !this.isInvalidPhotos18RefererCandidate(params.mangaId)) {
      candidate = params.mangaId;
    }

    const referer = this.buildPhotos18GalleryUrl(candidate);
    return referer.length > 0 ? referer : this.getPhotos18Origin();
  }

  private async preparePhotos18ImageSession(baseUrl: string): Promise<void> {
    if (!this.isPhotos18Source() || this.currentSourceId <= 0) {
      return;
    }
    const contextUrl = baseUrl.trim().length > 0 ? baseUrl.trim() : this.getPhotos18Origin();
    const requestUserAgent = this.getPhotos18RequestUserAgent();
    try {
      await new Promise<void>((resolve) => setTimeout(resolve, 1200));
      await this.ensureHiddenWebViewSourceContextReady(contextUrl, requestUserAgent);
      const cookieManager = CookieManager.getInstance();
      const refreshed: boolean = await cookieManager.forceCaptureWebViewCookies(this.currentSourceId, this.webviewController, contextUrl);
      const cookieStr: string = await cookieManager.getCookieString(this.currentSourceId);
      ImageCacheManager.getInstance().clearCookieCache(this.currentSourceId);
      OnlineImageLoader.getInstance().clearCookieCache(this.currentSourceId);
      logger.info(TAG, `Photos18阅读器图片会话预热完成: refreshed=${refreshed}, cookieLen=${cookieStr.length}, contextUrl=${contextUrl}`);
    } catch (error) {
      logger.warn(TAG, `Photos18阅读器图片会话预热失败: ${String(error)}`);
    }
  }

  private async updateNetworkHeadersForChapter(): Promise<void> {
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;

    if ( !manga || !chapter ) {
      return;
    }

    if (this.isPhotos18Source()) {
      try {
        const cm = CookieManager.getInstance();
        const cookieStr = await cm.getCookieString(this.currentSourceId);
        const referer = this.resolvePhotos18ReaderReferer(manga, chapter);
        this.photos18PageCachePartition = this.buildPhotos18CachePartition(referer);
        const photos18Headers: RequestHeaders = {
          userAgent: this.getPhotos18RequestUserAgent(),
          accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
          referer: referer,
          origin: this.getPhotos18Origin(),
          acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
          cacheControl: 'no-cache',
          pragma: 'no-cache',
          secFetchDest: 'image',
          secFetchMode: 'no-cors',
          secFetchSite: 'same-origin',
          cookie: cookieStr,
          cachePartition: this.photos18PageCachePartition
        } as RequestHeaders;

        this.networkHeaders = photos18Headers;
        this.networkHeadersTick = this.networkHeadersTick + 1;
        logger.info(TAG, `Photos18章节图片请求头已刷新: referer=${referer}, cookieLen=${cookieStr.length}`);
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        logger.warn(TAG, `Photos18章节Cookie获取失败: ${errorMessage}`);
      }
      return;
    }

    // [修改] 更鲁棒的判断逻辑，不单纯依赖 engine.config
    const engineConfig = this.mangaEngine?.getConfig();
    const baseUrl = engineConfig?.metadata?.baseUrl || '';
    const srcNameLowerFromParams: string = this.pageParams && this.pageParams.sourceName ? String(this.pageParams.sourceName).toLowerCase() : '';
    const firstPageUrl: string = (chapter.pages && chapter.pages.length > 0) ? String(chapter.pages[0].imageUrl || '') : '';
    const domainKomiic: boolean = firstPageUrl.includes('komiic.com');

    const isKomiic = baseUrl.includes('komiic.com') ||
                     (this.currentSourceId === 6) ||
                     (manga.sourceInfo?.sourceName?.toLowerCase().includes('komiic')) ||
                     (srcNameLowerFromParams.length > 0 && srcNameLowerFromParams.includes('komiic')) ||
                     domainKomiic;

    if (isKomiic) {
      // [修复] 优先使用 manga.sourceInfo.externalId
      let externalMangaId = this.pageParams?.mangaId || manga.id;
      
          // 尝试从sourceUrl提取ID
      if (externalMangaId.startsWith('id_')) {
        if (manga.sourceInfo?.externalId) {
          externalMangaId = manga.sourceInfo.externalId;
            logger.info(TAG, `✅ 从sourceUrl提取mangaId: ${externalMangaId}`);
        } else if (manga.sourceInfo?.sourceUrl) {
          // 尝试从sourceUrl提取ID
          const match = manga.sourceInfo.sourceUrl.match(/\/comic\/(\d+)/);
          if (match && match[1]) {
            externalMangaId = match[1];
            logger.info(TAG, `✅ 从sourceUrl提取mangaId: ${externalMangaId}`);
          }
        }
      }

      // [修复] 获取外部 Chapter ID - 优先使用 chapter.externalId
      let externalChapterId = chapter.id;
      logger.debug(TAG, `🔍 原始chapter.id: ${externalChapterId}, chapter.externalId: ${chapter.externalId || 'undefined'}`);
      if (externalChapterId.startsWith('id_')) {
        if (chapter.externalId) {
          externalChapterId = chapter.externalId;
          logger.info(TAG, `✅ 使用chapter.externalId: ${externalChapterId}`);
        } else {
          logger.warn(TAG, `⚠️ chapter.externalId为空，无法替换内部ID: ${externalChapterId}`);
        }
      }
      
      // 构造正确的 Referer
      let newReferer = `https://komiic.com/comic/${externalMangaId}/chapter/${externalChapterId}/images/all`;
      const needFallback: boolean = (externalMangaId.length === 0) || (externalMangaId.startsWith('id_')) || (externalChapterId.length === 0) || (externalChapterId.startsWith('id_'));
      if (needFallback) {
        logger.warn(TAG, `⚠️ 无法获取有效的外部ID, mangaId=${externalMangaId}, chapterId=${externalChapterId}, 使用fallback`);
        newReferer = 'https://komiic.com/';
      } else {
        logger.info(TAG, `✅ 构造完整Referer: ${newReferer}`);
      }
      
           // 创建新对象，保留旧属性 (不使用 ... 语法，明确赋值)
      if (this.networkHeaders) {
           // 创建新对象，保留旧属性 (不使用 ... 语法，明确赋值)
        if (this.networkHeaders.referer !== newReferer) {
           const prev: RequestHeaders = this.networkHeaders;
           // 创建新对象，保留旧属性 (不使用 ... 语法，明确赋值)
           const updated: RequestHeaders = this.cloneRequestHeaders(prev);
           updated.userAgent = prev?.userAgent || 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';
           updated.accept = prev?.accept || 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
           updated.referer = newReferer;
           updated.origin = this.buildRequestOrigin(newReferer, prev.origin);
           updated.acceptLanguage = prev && prev.acceptLanguage ? prev.acceptLanguage : 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
           updated.cookie = prev?.cookie;
           
           this.networkHeaders = updated;
           this.networkHeadersTick = this.networkHeadersTick + 1;// 递增 Tick
           
           logger.info(TAG, `✅ [二次确认] 强制更新Referer: ${newReferer}, Tick=${this.networkHeadersTick}`);
        }
      } else {
        // 如果 headers 为空，进行初始化
        const updated: RequestHeaders = {
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
          referer: newReferer,
          origin: this.isPhotos18Source() ? this.getPhotos18Origin() : this.buildRequestOrigin(newReferer),
          accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
          acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7'
        } as RequestHeaders;
        
        this.networkHeaders = updated;
        this.networkHeadersTick = this.networkHeadersTick + 1;
        
        logger.info(TAG, `✅ [修正逻辑] 初始化并更新Referer: ${newReferer}, Tick=${this.networkHeadersTick}`);
      }
    }
  }

  /**
  * [新增] 专门处理在线未下载漫画的外部漫画ID获取
  * 这是一个独立的方法，不与本地漫画逻辑混合
  */
  private async getExternalMangaIdForOnlineUndownloaded(mangaId: string): Promise<string> {
    // 2. 如果是内部ID，从online_comic表查询（使用强类型方法）
    if (!mangaId.startsWith('id_') && !mangaId.startsWith('local_')) {
      logger.info(TAG, `✅ mangaId本身就是外部ID: ${mangaId}`);
      return mangaId;
    }
    
    // 2. 如果是内部ID，从online_comic表查询（使用强类型方法）
    try {
      const onlineComic = await DataManager.getInstance().getOnlineComicInfoById(mangaId);
      if (onlineComic) {
        if (onlineComic.externalId) {
          logger.info(TAG, `✅ 从online_comic表获取externalId: ${onlineComic.externalId}`);
          return onlineComic.externalId;
        } else {
          const errorMsg = `online_comic record ${mangaId} exists but externalId is missing\n` +
            `  online_comic record found but externalId is missing; fallback mapping cannot continue`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
      } else {
        const errorMsg = `online_comic record not found for mangaId: ${mangaId}`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
    } catch (err) {
      logger.error(TAG, `❌ 从online_comic表获取externalId失败: ${String(err)}`);
      throw err as Error;
    }
  }

  /**
  * [新增] 专门处理在线未下载漫画的外部章节ID获取
  * 这是一个独立的方法，不与本地漫画逻辑混合
  */
  private async getExternalChapterIdForOnlineUndownloaded(chapter: MangaChapter): Promise<string> {
    // 2. 如果内存中没有，从online_chapter表查询
    if (chapter.externalId && !chapter.externalId.startsWith('id_') && !chapter.externalId.startsWith('local_')) {
      logger.info(TAG, `✅ 使用内存中的章节externalId: ${chapter.externalId}`);
      return chapter.externalId;
    }
    
    // 2. 如果内存中没有，从online_chapter表查询
    if (chapter.id && (chapter.id.startsWith('id_') || chapter.id.startsWith('local_'))) {
      try {
        const onlineChapter = await DataManager.getInstance().getOnlineChapterById(chapter.id);
        if (onlineChapter && onlineChapter.externalId) {
          logger.info(TAG, `✅ 从online_chapter表获取externalId: ${onlineChapter.externalId}`);
          return onlineChapter.externalId;
        } else {
          const errorMsg = `online_chapter record ${chapter.id} exists but externalId is missing\n` +
            `  - title: ${chapter.title}\\n` +
            `  - id: ${chapter.id}\\n` +
            `  online_chapter record found but externalId is missing; fallback mapping cannot continue`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
      } catch (err) {
        logger.error(TAG, `❌ 从online_chapter表获取externalId失败: ${String(err)}`);
        throw err as Error;
      }
    }
    
    // 4. 所有方法都失败，抛出错误
    if (chapter.id && !chapter.id.startsWith('id_') && !chapter.id.startsWith('local_')) {
      logger.info(TAG, `✅ chapter.id本身就是外部ID: ${chapter.id}`);
      return chapter.id;
    }
    
    // 4. 所有方法都失败，抛出错误
    const errorMsg = `无法解析章节外部 ID: "${chapter.title}"\n` +
      `  - chapter.id: ${chapter.id}\\n` +
      `  - chapter.externalId: ${chapter.externalId}\\n` +
      `Please verify source parsing rules and chapter mapping`;
    logger.error(TAG, errorMsg);
    throw new Error(errorMsg);
  }

  /**
   * 初始化漫画阅读器
   */
  private isInitializing: boolean = false;// 防止重复初始化
  private initPromise: Promise<void> | null = null;// 保存初始化Promise
  private pendingParams: MangaReaderPageParams | null = null;// 保存待处理的参数
  private activeInitParamsKey: string = '';
  private lastInitializedParamsKey: string = '';

  private buildInitParamsKey(params: MangaReaderPageParams): string {
    const mangaId: string = params.mangaId || params.manga?.id || '';
    const chapterId: string = params.chapterId || '';
    const pageIndex: number = params.pageIndex !== undefined ? params.pageIndex : 0;
    const contentType: string = String(params.contentType || '');
    const sourceId: number = params.sourceId !== undefined ? params.sourceId : -1;
    return `${mangaId}|${chapterId}|${pageIndex}|${contentType}|${sourceId}`;
  }

  private isRemoteProviderContentType(contentType: MangaReaderContentType): boolean {
    return contentType === MangaReaderContentType.Suwayomi || contentType === MangaReaderContentType.Komga;
  }

  private shouldUseReaderTransition(params?: MangaReaderPageParams | null): boolean {
    const effectiveParams = params ? params : this.pageParams;
    if (!effectiveParams) {
      return true;
    }
    return !this.isRemoteProviderContentType(effectiveParams.contentType);
  }

  private resolveRemoteProviderReadingSettingsScopeKey(mangaId: string): string | null {
    const parsedProviderId = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    if (parsedProviderId === null) {
      return null;
    }
    if (parsedProviderId.providerType === 'suwayomi') {
      return 'manga_settings_provider_suwayomi';
    }
    const instanceId = parsedProviderId.instanceId ? parsedProviderId.instanceId : 'default';
    return `manga_settings_provider_komga_${instanceId}`;
  }

  private async hasPersistedPerMangaReadingSettings(mangaId: string): Promise<boolean> {
    const settingKey = `manga_settings_${mangaId}`;
    try {
      const settingsJson = await DataManager.getInstance().getUserSetting('default_user', settingKey);
      return settingsJson !== null && settingsJson.length > 0;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `检查单漫画阅读设置失败: key=${settingKey}, error=${errorMessage}`);
      return false;
    }
  }

  private async loadRemoteProviderScopedReadingSettings(mangaId: string): Promise<ReadingSettings | null> {
    const scopeKey = this.resolveRemoteProviderReadingSettingsScopeKey(mangaId);
    if (scopeKey === null) {
      return null;
    }

    try {
      const settingsJson = await DataManager.getInstance().getUserSetting('default_user', scopeKey);
      if (settingsJson === null || settingsJson.length <= 0) {
        return null;
      }
      const parsedSettings = JSON.parse(settingsJson) as ReadingSettings;
      const normalizedSettings = this.cloneReadingSettings(parsedSettings);
      AppStorage.setOrCreate(scopeKey, settingsJson);
      logger.info(TAG, `已加载远程图源阅读设置: key=${scopeKey}`);
      return normalizedSettings;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `加载远程图源阅读设置失败: mangaId=${mangaId}, error=${errorMessage}`);
      return null;
    }
  }

  private async persistRemoteProviderScopedReadingSettings(
    mangaId: string,
    settings: ReadingSettings,
    trigger: string
  ): Promise<boolean> {
    const scopeKey = this.resolveRemoteProviderReadingSettingsScopeKey(mangaId);
    if (scopeKey === null) {
      return false;
    }

    const settingsJson = JSON.stringify(settings);
    AppStorage.setOrCreate(scopeKey, settingsJson);

    try {
      await DataManager.getInstance().saveUserSetting('default_user', scopeKey, settingsJson);
      logger.info(TAG, `远程图源阅读设置已持久化: key=${scopeKey}, trigger=${trigger}`);
      return true;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `远程图源阅读设置持久化失败: key=${scopeKey}, trigger=${trigger}, error=${errorMessage}`);
      return false;
    }
  }

  private getFirstLoadedMangaChapter(manga: Manga): MangaChapter | undefined {
    if (manga.chapters.length <= 0) {
      return undefined;
    }
    let firstChapter: MangaChapter = manga.chapters[0];
    for (let index = 1; index < manga.chapters.length; index++) {
      const currentChapter = manga.chapters[index];
      if (currentChapter.chapterNumber < firstChapter.chapterNumber) {
        firstChapter = currentChapter;
      }
    }
    return firstChapter;
  }

  private normalizeAnnotationCenterMangaContentType(contentType?: MangaReaderContentType): 'Local' | 'OnlineUndownloaded' | 'OnlineDownloaded' {
    if (contentType === MangaReaderContentType.OnlineDownloaded) {
      return 'OnlineDownloaded';
    }
    if (
      contentType === MangaReaderContentType.OnlineUndownloaded ||
      contentType === MangaReaderContentType.Suwayomi ||
      contentType === MangaReaderContentType.Komga
    ) {
      return 'OnlineUndownloaded';
    }
    return 'Local';
  }

  private resolveRemoteProviderChapter(manga: Manga, requestedChapterId?: string): MangaChapter | null {
    const normalizedChapterId = String(requestedChapterId || '').trim();
    if (normalizedChapterId.length > 0) {
      const parsedRequestedChapter = RemoteLibraryMangaBridge.parseProviderChapterId(normalizedChapterId);
      const rawRequestedChapterId = parsedRequestedChapter ? parsedRequestedChapter.rawChapterId : normalizedChapterId;

      for (let index = 0; index < manga.chapters.length; index++) {
        const chapter = manga.chapters[index];
        if (chapter.id === normalizedChapterId || chapter.externalId === normalizedChapterId) {
          return chapter;
        }

        const parsedChapter = RemoteLibraryMangaBridge.parseProviderChapterId(chapter.id);
        if (parsedChapter && parsedChapter.rawChapterId === rawRequestedChapterId) {
          return chapter;
        }

        if (!parsedChapter && chapter.id === rawRequestedChapterId) {
          return chapter;
        }
      }
    }

    const firstChapter = this.getFirstLoadedMangaChapter(manga);
    return firstChapter ? firstChapter : null;
  }

  private async initializeRemoteProviderReaderSafe(params: MangaReaderPageParams): Promise<boolean> {
    if (!this.isRemoteProviderContentType(params.contentType)) {
      return false;
    }

    const providerMangaId = params.mangaId || params.manga?.id || '';
    if (providerMangaId.length <= 0) {
      throw new Error('Remote provider reader missing mangaId');
    }

    this.currentSourceId = -1;
    this.currentSourcePkg = '';
    this.mangaEngine = null;
    this.shouldKeepConfiguredImageUserAgent = false;
    this.networkHeaders = undefined;
    this.readerState.isLoading = true;
    this.readerState.errorMessage = '';
    this.readerState.loadingMessage = 'Loading remote manga...';

    let manga = params.manga;
    if (!manga || !this.remoteLibraryBridge.isRemoteProviderManga(manga) || manga.chapters.length <= 0) {
      const detailManga = await this.remoteLibraryBridge.loadRemoteMangaDetail(manga || null, providerMangaId);
      if (detailManga === null) {
        throw new Error('Failed to load remote manga detail');
      }
      manga = detailManga;
    }

    this.readerState.currentManga = manga;
    this.reportTransitionLoadingProgress(0.28, 'manga_bound');

    const chapter = this.resolveRemoteProviderChapter(manga, params.chapterId);
    if (chapter === null) {
      this.readerState.errorMessage = `Remote manga has no readable chapter: ${manga.title}`;
      this.readerState.isLoading = false;
      this.notifyTransitionReaderReadyOnce('remote_provider_no_chapter');
      return true;
    }

    this.readerState.currentChapter = chapter;
    this.reportTransitionLoadingProgress(0.46, 'chapter_bound');

    if (chapter.pages.length <= 0) {
      this.readerState.loadingMessage = `Loading chapter ${chapter.title}...`;
      const remotePages = await this.remoteLibraryBridge.loadChapterPages(manga, chapter);
      if (remotePages.length <= 0) {
        throw new Error(`Remote chapter has no pages: ${chapter.title}`);
      }
      chapter.pages = remotePages;
    }

    if (!chapter.totalPages || chapter.totalPages <= 0) {
      chapter.totalPages = chapter.pages.length;
    }

    this.shouldKeepConfiguredImageUserAgent = false;
    this.networkHeaders = await this.remoteLibraryBridge.getRequestHeaders(manga);
    this.networkHeadersTick = this.networkHeadersTick + 1;
    this.isNetworkConfigReady = true;

    const totalPages = chapter.totalPages || chapter.pages.length;
    if (totalPages <= 0 || chapter.pages.length <= 0) {
      this.readerState.errorMessage = `Remote chapter has no pages: ${chapter.title}`;
      this.readerState.isLoading = false;
      this.notifyTransitionReaderReadyOnce('remote_provider_no_pages');
      return true;
    }

    const requestedPageIndex = params.pageIndex !== undefined ? params.pageIndex : 0;
    const maxPageIndex = Math.max(0, chapter.pages.length - 1);
    this.readerState.currentPageIndex = Math.max(0, Math.min(requestedPageIndex, maxPageIndex));
    this.refreshCurrentMangaBookmarkState('initialize_remote_provider_reader');
    this.reportTransitionLoadingProgress(0.72, 'chapter_pages_ready');

    await this.loadReadingSettings();
    this.reportTransitionLoadingProgress(0.84, 'reading_settings_ready');

    setTimeout(() => {
      this.preloadImages();
    }, 0);

    this.sessionStartTimestamp = Date.now();
    this.lastProgressSaveTime = 0;
    this.lastSavedPageIndex = -1;
    this.readerState.loadingMessage = '';
    this.lastInitializedParamsKey = this.buildInitParamsKey(params);
    this.readerState.isLoading = false;
    this.reportTransitionLoadingProgress(0.94, 'init_done_wait_visual_ready');
    this.waitForTransitionReaderReady('remote_provider_init_success');

    logger.info(TAG, `Remote provider reader initialized: manga=${manga.title}, chapter=${chapter.title}, pages=${chapter.pages.length}`);
    return true;
  }

  private refreshNetworkUserAgentAsync(engine: MangaSourceEngine, params: MangaReaderPageParams): void {
    if (this.isPhotos18Source()) {
      return;
    }
    if (this.shouldKeepConfiguredImageUserAgent) {
      logger.debug(TAG, '图源已锁定图片请求 User-Agent，跳过 WebView User-Agent 覆盖');
      return;
    }
    if (!this.webViewControllerAttached) {
      logger.debug(TAG, '隐藏WebView控制器尚未附加，跳过异步刷新WebView UserAgent');
      return;
    }
    const expectedKey = this.buildInitParamsKey(params);
    engine.getWebViewUserAgent().then((ua: string) => {
      const normalizedUa = ua ? ua.trim() : '';
      if (!normalizedUa) {
        return;
      }
      if (this.pageParams && this.buildInitParamsKey(this.pageParams) !== expectedKey) {
        return;
      }
      if (!this.networkHeaders) {
        return;
      }
      if (this.networkHeaders.userAgent === normalizedUa) {
        return;
      }
      const prevHeaders: RequestHeaders = this.networkHeaders;
      const refreshedHeaders: RequestHeaders = this.cloneRequestHeaders(prevHeaders);
      refreshedHeaders.userAgent = normalizedUa;
      this.networkHeaders = refreshedHeaders;
      this.networkHeadersTick++;
      logger.debug(TAG, `异步刷新WebView UserAgent完成，长度=${normalizedUa.length}`);
    }).catch((error: Error) => {
      logger.debug(TAG, `异步刷新WebView UserAgent失败（已忽略）: ${String(error)}`);
    });
  }

  private async waitForHiddenWebViewAttached(timeoutMs: number = 3000): Promise<void> {
    if (this.webViewControllerAttached) {
      return;
    }

    const startTime = Date.now();
    while (!this.webViewControllerAttached && Date.now() - startTime < timeoutMs) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 50);
      });
    }

    if (!this.webViewControllerAttached) {
      throw new Error(`隐藏WebView控制器附加超时(${timeoutMs}ms)`);
    }
  }

  private async waitForHiddenWebViewUrl(baseUrl: string, timeoutMs: number = 5000): Promise<void> {
    const startTime = Date.now();
    while (Date.now() - startTime < timeoutMs) {
      if (!this.mangaEngine) {
        throw new Error('MangaSourceEngine未初始化');
      }

      try {
        const currentUrl: string = await this.mangaEngine.getCurrentUrl();
        if (currentUrl.startsWith(baseUrl)) {
          return;
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logger.debug(TAG, `等待隐藏WebView进入图源上下文时读取URL失败: ${message}`);
      }

      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 150);
      });
    }

    throw new Error(`隐藏WebView未进入图源上下文: ${baseUrl}`);
  }

  private async ensureHiddenWebViewSourceContextReady(baseUrl: string, expectedUserAgent?: string): Promise<void> {
    const normalizedBaseUrl: string = baseUrl.trim();
    if (normalizedBaseUrl.length === 0) {
      return;
    }

    await this.waitForHiddenWebViewAttached();
    const userAgentChanged: boolean = this.syncHiddenWebViewUserAgent(expectedUserAgent);

    if (!this.mangaEngine) {
      return;
    }

    let currentUrl: string = '';
    try {
      currentUrl = await this.mangaEngine.getCurrentUrl();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.debug(TAG, `读取隐藏WebView当前URL失败，将直接预热图源上下文: ${message}`);
    }

    if (currentUrl.startsWith(normalizedBaseUrl) && !userAgentChanged) {
      logger.debug(TAG, `隐藏WebView已处于图源上下文: ${currentUrl}`);
      return;
    }

    logger.info(TAG, `隐藏WebView预热图源上下文: ${normalizedBaseUrl}`);
    this.webviewController.loadUrl(normalizedBaseUrl);
    await this.waitForHiddenWebViewUrl(normalizedBaseUrl);
    logger.info(TAG, `隐藏WebView图源上下文已就绪: ${normalizedBaseUrl}`);
  }

  /**
   * 通过隐藏WebView加载Pixiv CDN图片（HTTP模块无法直接连接i.pximg.net）
   * 使用同步XHR在WebView的浏览器上下文中加载图片，利用Pixiv的cookies/session
   */
  public async loadPixivImage(imageUrl: string): Promise<ArrayBuffer | null> {
    try {
      // 使用同步XHR加载图片（在WebView上下文中，有正确的cookies和浏览器环境）
      const script = `(() => {
        try {
          var xhr = new XMLHttpRequest();
          xhr.open('GET', ${JSON.stringify(imageUrl)}, false);
          xhr.responseType = 'arraybuffer';
          xhr.send(null);
          if (xhr.status >= 200 && xhr.status < 300 && xhr.response) {
            return xhr.response;
          }
          return 'XHR_STATUS:' + xhr.status;
        } catch(e) {
          return 'XHR_ERROR:' + e.message;
        }
      })()`;
      const jsResult = await this.webviewController.runJavaScriptExt(script);
      const resultType = jsResult.getType();
      if (resultType === webview.JsMessageType.ARRAY_BUFFER) {
        const buffer = jsResult.getArrayBuffer();
        if (buffer && buffer.byteLength > 0) {
          logger.info(TAG, `Pixiv WebView图片加载成功: ${imageUrl.substring(0, 60)}, bytes=${buffer.byteLength}`);
          return buffer;
        }
      }
      if (resultType === webview.JsMessageType.STRING) {
        const errStr = jsResult.getString();
        logger.warn(TAG, `Pixiv WebView图片加载失败: ${errStr}, url=${imageUrl.substring(0, 60)}`);
      } else {
        logger.warn(TAG, `Pixiv WebView图片加载无数据: type=${resultType}, url=${imageUrl.substring(0, 60)}`);
      }
      return null;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `Pixiv WebView图片加载异常: ${errMsg}, url=${imageUrl.substring(0, 60)}`);
      return null;
    }
  }
  
  private async initializeMangaReader(params: MangaReaderPageParams): Promise<void> {
    this.pageParams = params;
    const initKey = this.buildInitParamsKey(params);
    if (!this.isInitializing &&
      this.lastInitializedParamsKey === initKey &&
      !this.readerState.isLoading &&
      !this.readerState.errorMessage) {
      logger.info(TAG, `⏭️ 检测到重复初始化请求，已跳过: ${initKey}`);
      return;
    }

    // 如果正在初始化，保存参数并等待完成后重新初始化
    if (this.isInitializing && this.initPromise) {
      const pendingKey = this.pendingParams ? this.buildInitParamsKey(this.pendingParams) : '';
      if (this.activeInitParamsKey === initKey || pendingKey === initKey) {
        logger.info(TAG, `⏭️ 初始化请求与进行中任务相同，等待现有流程完成: ${initKey}`);
        await this.initPromise;
        return;
      }
      logger.warn(TAG, '⚠️ 初始化已在进行中，保存新参数并等待完成...');
      this.pendingParams = params;
      await this.initPromise;
      
      // 如果有待处理的参数，使用新参数重新初始化
      if (this.pendingParams) {
        logger.info(TAG, '🔄 使用新参数重新初始化');
        const newParams = this.pendingParams;
        this.pendingParams = null;
        await this.initializeMangaReader(newParams);
      }
      return;
    }
    
    this.isInitializing = true;
    this.activeInitParamsKey = initKey;
    logger.info(TAG, '🚀 开始初始化漫画阅读器');
    this.hasNotifiedTransitionReaderReady = false;
    this.transitionLoadingProgress = 0;
    this.clearTransitionReaderReadyTimers();
    this.reportTransitionLoadingProgress(0.06, 'init_start');
    this.isNetworkConfigReady = false;// 重置配置就绪状态，阻止 Viewer 渲染
    
    // 执行初始化并保存Promise
    this.initPromise = (async () => {
      try {
        await this.doActualInitialization(params);
      } finally {
        this.isInitializing = false;
        this.initPromise = null;
        if (this.activeInitParamsKey === initKey) {
          this.activeInitParamsKey = '';
        }
      }
    })();
    
    await this.initPromise;
  }

  private async tryLoadOnlineDownloadedArchivePagesForChapter(
    chapter: MangaChapter,
    kickstartViewer: boolean
  ): Promise<boolean> {
    try {
      let archivePath = chapter.localPath || '';
      if (!this.isCbzArchivePath(archivePath)) {
        const dbChapter = await DataManager.getInstance().getOnlineChapterById(chapter.id);
        if (dbChapter && dbChapter.downloadPath && this.isCbzArchivePath(dbChapter.downloadPath)) {
          archivePath = dbChapter.downloadPath;
          chapter.localPath = archivePath;
        }
      }

      if (!archivePath || !this.isCbzArchivePath(archivePath)) {
        return false;
      }
      if (!this.onlineArchiveService.fileExists(archivePath)) {
        logger.warn(TAG, `在线已下载章节CBZ不存在，回退旧链路: ${archivePath}`);
        return false;
      }

      const pageInfos = await DataManager.getInstance().getOnlineChapterPages(chapter.id);
      const extractResult: OnlineArchiveExtractResult = await this.onlineArchiveService.extractArchiveForReader({
        archivePath: archivePath,
        chapterId: chapter.id,
        pages: pageInfos
      });
      chapter.pages = this.convertArchivePagesToMangaPages(extractResult.pages);
      chapter.totalPages = chapter.pages.length;
      chapter.isDownloaded = true;
      chapter.downloadStatus = DownloadStatus.COMPLETED;
      chapter.downloadProgress = 100;

      const networkPages = chapter.pages.filter(p => p.sourceType === ImageSourceType.NETWORK).length;
      if (networkPages > 0) {
        logger.info(TAG, `在线已下载章节(部分归档)已从CBZ解压加载: ${chapter.title}, pages=${chapter.pages.length}, network=${networkPages}, archive=${archivePath}`);
      } else {
        logger.info(TAG, `在线已下载章节已从CBZ解压加载: ${chapter.title}, pages=${chapter.pages.length}, archive=${archivePath}`);
      }
      if (kickstartViewer && this.mangaViewerComponent) {
        this.mangaViewerComponent.kickstartLoading();
      }
      return true;
    } catch (error) {
      logger.warn(TAG, `在线已下载章节CBZ解压加载失败，回退旧链路: chapter=${chapter.title}, ${String(error)}`);
      return false;
    }
  }

  private convertArchivePagesToMangaPages(pages: OnlineArchiveExtractedPage[]): MangaPage[] {
    const mangaPages: MangaPage[] = [];
    let placeholderCount = 0;
    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      // 占位图页面：设置为NETWORK类型，阅读器将从网络加载
      const isPlaceholder = page.isPlaceholder === true || (!page.localPath && !!page.imageUrl);
      const sourceType = isPlaceholder ? ImageSourceType.NETWORK : ImageSourceType.LOCAL;
      if (isPlaceholder) {
        placeholderCount++;
      }
      const mangaPage: MangaPage = {
        id: page.pageId,
        index: page.pageIndex,
        sourceType: sourceType,
        imagePath: isPlaceholder ? page.imageUrl : page.localPath,
        imageUrl: page.imageUrl,
        localPath: isPlaceholder ? '' : page.localPath,
        width: page.width,
        height: page.height,
        fileSize: page.fileSize,
        isLoaded: false
      };
      mangaPages.push(mangaPage);
    }
    if (placeholderCount > 0) {
      logger.info(TAG, `部分归档检测: ${placeholderCount}/${pages.length} 页为占位图，将从网络加载`);
    }
    return mangaPages;
  }

  private isCbzArchivePath(path: string): boolean {
    return path.toLowerCase().endsWith('.cbz');
  }
  
  /**
  * 实际的初始化逻辑
  */
  private async doActualInitialization(params: MangaReaderPageParams): Promise<void> {
    if (await this.initializeRemoteProviderReaderSafe(params)) {
      return;
    }
    this.shouldKeepConfiguredImageUserAgent = false;

    // 1. 判定是否为 Komiic (Source ID 6 或 14，或名称包含 Komiic)
    // 1. 判定是否为 Komiic (Source ID 6 或 14，或名称包含 Komiic)
      const srcId = params.sourceId || this.currentSourceId;
      const srcName = params.sourceName || params.manga?.sourceInfo?.sourceName || '';
      const isKomiic = (srcId === 6 || srcId === 14) || srcName.toLowerCase().includes('komiic');

      if (params.sourceId && typeof params.sourceId === 'number' && params.sourceId > 0) {
        this.currentSourceId = params.sourceId;
      }
      this.currentSourcePkg = params.sourcePkg || this.currentSourcePkg;


    // 在构造 Referer 的同时，根据数据库是否存在Cookie决定是否携带
    let cookies: string = '';
    try {
      if (srcId && typeof srcId === 'number') {
        const cm: CookieManager = CookieManager.getInstance();
        const has: boolean = await cm.hasCookie(srcId);
        if (has) {
          cookies = await cm.getCookieString(srcId);
          logger.info(TAG, '🔒 数据库无Cookie，初始化阶段不携带Cookie');
        } else {
          logger.info(TAG, '🔒 数据库无Cookie，初始化阶段不携带Cookie');
        }
      }
    } catch (e) {
      logger.error(TAG, 'Cookie判定失败', String(e));
    }

    // 尝试从 SourceURL 获取外部 Manga ID (针对内部 ID 格式)
    let targetMangaId = params.mangaId || (params.manga ? params.manga.id : '');
    let targetChapterId = params.chapterId || '';

    // [重构] 根据是否有sourceId判断是在线还是本地漫画
    if (params.manga && params.manga.sourceInfo && params.manga.sourceInfo.sourceUrl) {
      targetMangaId = params.manga.sourceInfo.sourceUrl;
    }

    // [修复] 如果mangaId是内部ID格式，从数据库查询真实的externalId
    const hasSourceId = srcId && typeof srcId === 'number' && srcId > 0;
    
          // 在线漫画：查询online_comic表（使用强类型方法）
    if (targetMangaId.startsWith('id_')) {
      try {
        if (hasSourceId) {
          // 本地漫画：查询comic表
          const dbComicRecord = await DataManager.getInstance().getOnlineComicInfoById(targetMangaId);
          if (dbComicRecord && dbComicRecord.externalId) {
            targetMangaId = dbComicRecord.externalId;
            logger.info(TAG, `🔍 [早期] 从comic表获取外部漫画ID: ${targetMangaId}`);
          }
        } else {
          // 本地漫画：查询comic表
          const dbComicRecord = await DataManager.getInstance().getComicById(targetMangaId);
          if (dbComicRecord && dbComicRecord.externalId) {
            targetMangaId = dbComicRecord.externalId as string;
            logger.info(TAG, `🔍 [早期] 从comic表获取外部漫画ID: ${targetMangaId}`);
          }
        }
      } catch (err) {
        logger.warn(TAG, `⚠️ [早期] 获取外部漫画ID失败: ${String(err)}`);
      }
    }

          // 在线漫画：查询online_chapter表
    if (targetChapterId.startsWith('id_')) {
      try {
        if (hasSourceId) {
          // 本地漫画：查询chapter表
          const dbChapterRecord = await DataManager.getInstance().getOnlineChapterById(targetChapterId);
          if (dbChapterRecord && dbChapterRecord.externalId) {
            targetChapterId = dbChapterRecord.externalId;
            logger.info(TAG, `🔍 [早期] 从chapter表获取外部章节ID: ${targetChapterId}`);
          }
        } else {
          // 本地漫画：查询chapter表
          const dbChapterRecord = await DataManager.getInstance().getChapterById(targetChapterId);
          if (dbChapterRecord && dbChapterRecord.externalId) {
            targetChapterId = dbChapterRecord.externalId as string;
            logger.info(TAG, `🔍 [早期] 从chapter表获取外部章节ID: ${targetChapterId}`);
          }
        }
      } catch (err) {
        logger.warn(TAG, `⚠️ [早期] 获取外部章节ID失败: ${String(err)}`);
      }
    }

      // 构造 Referer，使用真实的外部ID
    if (isKomiic && targetMangaId && targetChapterId) {
      // 构造 Referer，使用真实的外部ID
      const referer = `https://komiic.com/comic/${targetMangaId}/chapter/${targetChapterId}/images/all`;

      this.networkHeaders = {
        userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        referer: referer,
        origin: this.buildRequestOrigin(referer),
        accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
        acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        cookie: cookies
      } as RequestHeaders;
      this.networkHeadersTick++;
    // ==================== [修复结束] ====================
      this.isNetworkConfigReady = true;
      logger.info(TAG, `✅ 早期网络配置就绪，允许Viewer渲染`);
      logger.info(TAG, `✅ 早期网络配置就绪，允许Viewer渲染`);
    }
      // 获取漫画数据

    try {
      this.readerState.isLoading = true;
      logger.debug(TAG, '📚 设置加载状态');

      // [修复] OnlineDownloaded也需要初始化MangaEngine以支持章节切换
      let manga: Manga;
        // 直接使用传递的漫画对象（通常来自WebView图源）
      const isWebViewSource = params.contentType === MangaReaderContentType.OnlineUndownloaded ||
                           params.contentType === MangaReaderContentType.OnlineDownloaded;


      if (params.manga) {
        // [懒加载优化] 对于WebView图源的在线漫画，只加载章节骨架信息，不加载页面数据
        manga = params.manga;
        logger.debug(TAG, `📖 使用直接传递的漫画对象，内容类型: ${params.contentType}`);
        
        // Step 1: 加载所有章节基本信息（不加载pages）
        if (isWebViewSource && manga.id && !params.skipDatabaseLookup) {
          try {
            // Step 2: 章节很多时，跳过online_page聚合查询，避免初始化首屏阻塞
            const chapters = await DataManager.getInstance().getOnlineComicChapters(manga.id);
            logger.info(TAG, `📚 [懒加载] online_chapter表返回章节数量: ${chapters ? chapters.length : 0}`);
            
            if (chapters && chapters.length > 0) {
              // 小章节集合保留聚合查询，保证totalPages准确度
              // 小章节集合保留聚合查询，保证totalPages准确度
              const pageCountMap = new Map<string, number>();
              const shouldQueryPageCounts = chapters.length <= 120;
              if (shouldQueryPageCounts) {
                const counts = await DataManager.getInstance().getOnlineChapterPageCounts(manga.id);
                counts.forEach((count: number, chapterId: string) => pageCountMap.set(chapterId, count));
                logger.info(TAG, `⚡ [懒加载] 章节数=${chapters.length}，跳过online_page页数聚合查询，使用chapter.pageCount加速首屏`);
              } else {
                logger.info(TAG, `[source-loader] skip online_page count query, chapterCount=${chapters.length}, use chapter.pageCount`);
              }
              
              // Step 3: 转换为MangaChapter骨架（pages为空数组，使用totalPages存储页数）
              const mangaChapters: MangaChapter[] = [];
              for (const chapterInfo of chapters) {
                const chapter: MangaChapter = {
                  id: chapterInfo.id,
                  title: chapterInfo.title,
                  chapterNumber: chapterInfo.chapterNumber,
                  pages: [],// [懒加载] 初始化时不加载页面数据
                  publishDate: chapterInfo.publishTime || Date.now(),
                  language: 'zh-CN',
                  scanlationGroup: '',
                  isDownloaded: chapterInfo.isDownloaded || false,
                  downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                  downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                  localPath: chapterInfo.downloadPath,
                  externalId: chapterInfo.externalId
                };
                mangaChapters.push(chapter);
              }
              
              manga.chapters = mangaChapters;
              logger.info(TAG, `[source-loader] chapter mapping completed, count=${manga.chapters.length}`);
            } else {
              logger.warn(TAG, '⚠️ online_chapter表中没有章节信息，将使用动态加载');
              manga.chapters = [];
            }
          } catch (error) {
            logger.error(TAG, `❌ [懒加载] 加载章节骨架失败: ${String(error)}`);
            manga.chapters = [];
          }
          logger.debug(TAG, `🔄 [懒加载] 章节骨架加载完成，继续初始化MangaSourceEngine`);
        } else if (isWebViewSource && manga.id && params.skipDatabaseLookup) {
          logger.info(TAG, `📚 保留传入的章节列表，共 ${manga.chapters.length} 个章节`);
          // 如果传递了chapterTitle，可以用于验证或日志记录，但不覆盖chapters
          logger.info(TAG, `[skipDatabaseLookup] reused chapter list, count=${manga.chapters.length}`);
          // 如果传递了chapterTitle，可以用于验证或日志记录，但不覆盖chapters
          if (params.chapterTitle) {
            logger.info(TAG, `🔍 当前章节标题: "${params.chapterTitle}"`);
          }
        }
        
        // 如果是WebView图源，初始化MangaSourceEngine
        if (isWebViewSource && params.sourceId) {
            this.currentSourceId = params.sourceId;
            this.currentSourcePkg = params.sourcePkg || '';
              logger.info(TAG, `✅ MangaSourceEngine初始化成功`);

          
          try {
            // 加载图源的预加载设置
            this.mangaEngine = await this.webViewManager.getMangaEngine(params.sourceId, params.sourceName);
            logger.info(TAG, 'MangaSourceEngine acquired successfully');
            
            // 加载图源的预加载设置
            await this.loadSourcePreloadSettings(params.sourceId);
            
            const engine: MangaSourceEngine | null = this.mangaEngine;
              logger.debug(TAG, '📋 步骤1: 获取engine配置');
            logger.info(TAG, '请求头已初始化');
            if (engine) {
              logger.debug(TAG, '📋 步骤1: 获取engine配置');
              const cfg = engine.getConfig();
              let baseUrl: string = '';
              if (cfg && cfg.metadata && cfg.metadata.baseUrl) {
                baseUrl = String(cfg.metadata.baseUrl);
              }
              const effectiveSourceId: number = params.sourceId && params.sourceId > 0 ? params.sourceId : this.currentSourceId;
              const sourceRequestContext: SourceRequestContext = effectiveSourceId > 0
                ? await this.resolveSourceRequestContext(effectiveSourceId, baseUrl)
                : {
                    requestBaseUrl: this.trimTrailingSlash(baseUrl),
                    refererHint: this.trimTrailingSlash(baseUrl),
                    originHint: this.buildRequestOrigin('', baseUrl),
                    headerTemplate: {} as RequestHeaders,
                    userAgentLocked: false
                  } as SourceRequestContext;
              const photos18Referer: string = this.isPhotos18Source()
                ? this.resolvePhotos18ReaderRefererFromParams(params, manga, this.readerState.currentChapter)
                : '';
              const ua: string = this.isPhotos18Source()
                ? this.getPhotos18RequestUserAgent()
                : this.getDefaultReaderRequestUserAgent();
              if (this.isPhotos18Source()) {
                this.photos18PageCachePartition = this.buildPhotos18CachePartition(photos18Referer);
                await this.preparePhotos18ImageSession(photos18Referer);
              } else {
                const preheatUserAgent: string = sourceRequestContext.headerTemplate.userAgent &&
                  sourceRequestContext.headerTemplate.userAgent.length > 0
                  ? sourceRequestContext.headerTemplate.userAgent
                  : ua;
                await this.ensureHiddenWebViewSourceContextReady(sourceRequestContext.requestBaseUrl, preheatUserAgent);
              }

              logger.debug(TAG, `📋 步骤3: 使用快速默认UserAgent，长度=${ua.length}`);
              logger.debug(TAG, '📋 步骤5: 准备构造Referer');
              
              logger.debug(TAG, `🔍 准备构造Referer: isKomiic=${isKomiic}, baseUrl=${baseUrl}, requestBase=${sourceRequestContext.requestBaseUrl}, originHint=${sourceRequestContext.originHint}`);
              let dynamicReferer: string = sourceRequestContext.refererHint.length > 0
                ? sourceRequestContext.refererHint
                : sourceRequestContext.requestBaseUrl;
                logger.debug(TAG, '📋 步骤6: Komiic图源，构造特定Referer');
              
                // [修复] 确保使用外部ID而不是内部ID
              if (isKomiic && params.chapterId) {
                logger.debug(TAG, '📋 步骤6: Komiic图源，构造特定Referer');
                const base: string = baseUrl;
                // 如果mangaId是内部ID格式(id_开头)，尝试从manga.sourceInfo获取外部ID
                let externalMangaId: string = params.mangaId || params.manga?.id || '';
                
                // 如果mangaId是内部ID格式(id_开头)，尝试从manga.sourceInfo获取外部ID
                if (externalMangaId.startsWith('id_')) {
                  logger.warn(TAG, `⚠️ 检测到内部mangaId格式: ${externalMangaId}，尝试获取外部ID`);
                  if (params.manga?.sourceInfo?.externalId) {
                    externalMangaId = params.manga.sourceInfo.externalId;
                    logger.info(TAG, `✅ 从manga.sourceInfo.externalId获取外部ID: ${externalMangaId}`);
                  } else if (params.manga?.sourceInfo?.sourceUrl) {
                    // sourceUrl可能包含漫画ID
                    const urlMatch = params.manga.sourceInfo.sourceUrl.match(/\/comic\/(\d+)/);
                    if (urlMatch && urlMatch[1]) {
                      externalMangaId = urlMatch[1];
                      logger.info(TAG, `✅ 从sourceUrl提取外部ID: ${externalMangaId}`);
                    }
                  }
                }
                
                let externalChapterId: string = params.chapterId;
                  // [修复] 从manga对象中查找当前章节的externalId
                if (externalChapterId.startsWith('id_')) {
                  logger.warn(TAG, `⚠️ 检测到内部chapterId格式: ${externalChapterId}，需要获取外部ID`);
                  // [修复] 从manga对象中查找当前章节的externalId
                  if (params.manga?.chapters) {
                    const currentChapter = params.manga.chapters.find(ch => ch.id === params.chapterId);
                    if (currentChapter?.externalId && !currentChapter.externalId.startsWith('id_')) {
                      externalChapterId = currentChapter.externalId;
                      logger.info(TAG, `✅ 从章节对象获取外部ID: ${externalChapterId}`);
                    } else {
                      logger.warn(TAG, `⚠️ 章节对象中未找到有效的externalId`);
                    }
                  }
                }
                
                logger.debug(TAG, `使用chapterId: ${externalChapterId}`);
                logger.debug(TAG, `使用chapterId: ${externalChapterId}`);
                
                // 如果ID仍然是内部格式，使用基础URL作为Referer
                if (externalMangaId.startsWith('id_') || externalChapterId.startsWith('id_')) {
                  dynamicReferer = base + '/';
                  logger.warn(TAG, `⚠️ ID仍为内部格式，使用基础Referer: ${dynamicReferer}`);
                } else {
                  dynamicReferer = `${base}/comic/${externalMangaId}/chapter/${externalChapterId}/images/all`;
                  logger.info(TAG, `✅ 为Komiic构造特定Referer: ${dynamicReferer}`);
                }
              } else {
              logger.debug(TAG, '📋 步骤7: 构造请求头对象');
              }
              logger.debug(TAG, '📋 步骤7: 构造请求头对象');
              const resolvedPhotos18Referer: string = this.isPhotos18Source()
                ? this.resolvePhotos18ReaderRefererFromParams(params, manga, this.readerState.currentChapter)
                : '';
              const headers: RequestHeaders = this.cloneRequestHeaders(sourceRequestContext.headerTemplate);
              headers.userAgent = this.isPhotos18Source()
                ? this.getPhotos18RequestUserAgent()
                : (headers.userAgent && headers.userAgent.length > 0 ? headers.userAgent : ua);
              headers.accept = headers.accept && headers.accept.length > 0
                ? headers.accept
                : 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
              headers.referer = this.isPhotos18Source() ? resolvedPhotos18Referer : dynamicReferer;
              headers.origin = this.isPhotos18Source()
                ? this.getPhotos18Origin()
                : this.buildRequestOrigin(headers.referer, sourceRequestContext.originHint.length > 0 ? sourceRequestContext.originHint : headers.origin);
              headers.acceptLanguage = headers.acceptLanguage && headers.acceptLanguage.length > 0
                ? headers.acceptLanguage
                : 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
              headers.cacheControl = headers.cacheControl && headers.cacheControl.length > 0
                ? headers.cacheControl
                : 'no-cache';
              headers.pragma = headers.pragma && headers.pragma.length > 0 ? headers.pragma : 'no-cache';
              headers.secFetchDest = headers.secFetchDest && headers.secFetchDest.length > 0 ? headers.secFetchDest : 'image';
              headers.secFetchMode = headers.secFetchMode && headers.secFetchMode.length > 0 ? headers.secFetchMode : 'no-cors';
              if (this.isPhotos18Source()) {
                headers.secFetchSite = 'same-origin';
                headers.cachePartition = this.photos18PageCachePartition;
              }
              
              logger.debug(TAG, '📋 步骤9: CookieManager实例已获取，准备读取Cookie');
              try {
                const cm2: CookieManager = CookieManager.getInstance();
                const cookieStr2: string = await cm2.getCookieString(this.currentSourceId);
                logger.debug(TAG, `📋 步骤10: Cookie读取完成，长度=${cookieStr2.length}`);
                logger.debug(TAG, '📋 步骤11: Cookie已添加到请求头');
                if (cookieStr2.length > 0) {
                  headers.cookie = cookieStr2;
                  logger.debug(TAG, '📋 步骤11: Cookie已添加到请求头');
                } else {
                  logger.warn(TAG, '读取Cookie失败: Cookie为空');
                }
              } catch (cookieError) {
                const msg: string = cookieError instanceof Error ? cookieError.message : String(cookieError);
                logger.warn(TAG, `读取Cookie失败: ${msg}`);
              }
              logger.debug(TAG, `📋 步骤13: networkHeadersTick=${this.networkHeadersTick}`);
              this.shouldKeepConfiguredImageUserAgent = sourceRequestContext.userAgentLocked;
              this.networkHeaders = headers;
              this.networkHeadersTick++;
              logger.debug(TAG, '📋 步骤14: isNetworkConfigReady已设置为true');
              this.refreshNetworkUserAgentAsync(engine, params);
              
              // [修复] 网络配置准备完成，允许Viewer渲染
              this.isNetworkConfigReady = true;
              logger.debug(TAG, `🌐 网络请求头已准备: UA=${ua.substring(0, Math.min(64, ua.length))}, Referer=${this.isPhotos18Source() ? resolvedPhotos18Referer : dynamicReferer}`);
              
              logger.debug(TAG, '📋 步骤15: 网络请求头配置完成，准备退出if块');
              logger.info(TAG, `✅ 网络配置就绪，允许Viewer渲染`);
              logger.debug(TAG, '📋 步骤15: 网络请求头配置完成，准备退出if块');
            } else {
              logger.warn(TAG, `⚠️ engine对象为null，跳过网络请求头配置`);
            }
          } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            const errorStack = error instanceof Error ? error.stack : undefined;
              logger.error(TAG, `错误堆栈: ${errorStack}`);
            if (errorStack) {
              logger.error(TAG, `错误堆栈: ${errorStack}`);
            }
            throw new Error(`WebView 图源引擎初始化失败: ${errorMsg}`);
          }
        logger.info(TAG, `✅ WebView图源分支执行完成，准备进入章节设置阶段`);
        }
        logger.info(TAG, 'WebView source initialization complete, continue loading manga');
      } else if (params.mangaId) {
        // 从DataManager加载漫画数据
        logger.debug(TAG, `🔍 从DataManager加载漫画数据，ID: ${params.mangaId}, sourceId: ${params.sourceId || 'none'}`);
        const comicInfo = await DataManager.getInstance().getComicById(params.mangaId);
        if (!comicInfo) {
          throw new Error(`未找到漫画信息: mangaId=${params.mangaId}`);
        }
        
        // [重构] 根据是否有sourceId判断是在线漫画还是本地漫画
        manga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
        
        // [重构] 根据是否有sourceId判断是在线漫画还是本地漫画
        const hasSourceId = params.sourceId && typeof params.sourceId === 'number' && params.sourceId > 0;
        logger.debug(TAG, `📚 开始加载章节信息，hasSourceId: ${hasSourceId}`);
        
        let chapters: ChapterInfo[] | OnlineChapterInfo[];
        if (hasSourceId) {
          // 本地漫画：从chapter表加载
          logger.info(TAG, '正在从 online_chapter 表加载章节');
          chapters = await DataManager.getInstance().getOnlineComicChapters(params.mangaId);
        } else {
          // 本地漫画：从chapter表加载
          logger.info(TAG, '正在从 chapter 表加载章节');
          chapters = await DataManager.getInstance().getComicChapters(params.mangaId);
        }
        
        if (chapters && chapters.length > 0) {
          const dataManager = DataManager.getInstance();
          const allPagesMap: Map<string, PageInfo[] | OnlinePageInfo[]> = new Map<string, PageInfo[] | OnlinePageInfo[]>();

          if (hasSourceId) {
            // [首屏优化] 在线漫画初始化仅加载目标章节页面，避免章节过多时阻塞首屏
            const onlineChapters = chapters as OnlineChapterInfo[];
            const requestedChapterId: string = params.chapterId ? String(params.chapterId) : '';
            const targetChapter = onlineChapters.find((ch: OnlineChapterInfo) =>
              ch.id === requestedChapterId || (!!ch.externalId && ch.externalId === requestedChapterId)
            ) || onlineChapters[0];

            if (targetChapter) {
              if (this.shouldRefreshVolatileSourcePages()) {
                allPagesMap.set(targetChapter.id, [] as OnlinePageInfo[]);
                logger.info(TAG, `⚡ 易失票据图源跳过 online_page 首屏缓存: chapterId=${targetChapter.id}`);
              } else {
                try {
                  const targetPages = await dataManager.getOnlineChapterPages(targetChapter.id);
                  allPagesMap.set(targetChapter.id, targetPages);
                  logger.info(TAG, `⚡ 在线首屏优化：仅加载目标章节页面，chapterId=${targetChapter.id}, pages=${targetPages.length}, 总章节=${onlineChapters.length}`);
                } catch (targetPageError) {
                  logger.warn(TAG, `在线首屏优化：加载目标章节页面失败，继续骨架初始化: ${String(targetPageError)}`);
                }
              }
            }
          } else {
            // 本地漫画保持批量页面加载策略
            const localPagesMap = await dataManager.getAllLocalPagesByComicId(params.mangaId);
            localPagesMap.forEach((pages: PageInfo[], chapterId: string) => {
              allPagesMap.set(chapterId, pages);
            });
            logger.info(TAG, `📄 批量加载页面完成，共 ${allPagesMap.size} 个章节有页面数据`);
          }

          // 转换章节信息为MangaChapter格式
          const mangaChapters: MangaChapter[] = [];
          const chapterConvertLogLimit: number = hasSourceId ? 12 : Number.MAX_SAFE_INTEGER;
          let chapterConvertLogCount = 0;

          for (const chapterInfo of chapters) {
            // 转换页面信息为MangaPage格式
            const pageInfos: PageInfo[] | OnlinePageInfo[] = (allPagesMap.get(chapterInfo.id) || []) as PageInfo[] | OnlinePageInfo[];

            // [修复] 对于已下载的章节，优先使用本地路径
              // [修复] 获取localPath - OnlinePageInfo和PageInfo都有localPath字段
              // [修复] 获取localPath - OnlinePageInfo和PageInfo都有localPath字段
            const pages: MangaPage[] = pageInfos.map((pageInfo: PageInfo | OnlinePageInfo, arrayIndex: number) => {
              // [修复] 已下载章节优先使用本地路径
              const localPath = hasSourceId
                ? (pageInfo as OnlinePageInfo).localPath
                : (pageInfo as PageInfo).localPath;

              // [修复] 已下载章节优先使用本地路径
              let sourceType: ImageSourceType;
              let imagePath: string = pageInfo.imageUrl;

              if (localPath && localPath.length > 0) {
                sourceType = ImageSourceType.LOCAL;
                imagePath = localPath;
              } else if (pageInfo.imageUrl.startsWith('http://') || pageInfo.imageUrl.startsWith('https://')) {
                sourceType = ImageSourceType.NETWORK;
              } else if (pageInfo.imageUrl.startsWith('/')) {
                // 默认为rawfile资源
                sourceType = ImageSourceType.LOCAL;
              } else {
                // 默认为rawfile资源
                sourceType = ImageSourceType.RAWFILE;
              }

              const converter: PageInfoToMangaPageConverter = {
                id: pageInfo.id,
                pageNumber: arrayIndex,// [修复] 使用0-indexed数组索引
                imageUrl: pageInfo.imageUrl,
                localPath: localPath,
                width: pageInfo.width,
                height: pageInfo.height,
                fileSize: pageInfo.fileSize,
                isLoaded: false,
                index: arrayIndex,// [修复] 使用0-indexed数组索引
                sourceType: sourceType,
                imagePath: imagePath,
                loadProgress: 0
              };
              return converter as MangaPage;
            });

            // [重构] 根据是否为在线漫画选择字段映射
            const chapterNumber = hasSourceId
              ? (chapterInfo as OnlineChapterInfo).chapterNumber// OnlineChapterInfo使用chapterNumber
              : (chapterInfo as ChapterInfo).index;// ChapterInfo使用index
            const chapterTotalPages = hasSourceId
              ? ((chapterInfo as OnlineChapterInfo).pageCount || pages.length)
              : pages.length;

            const converter: ChapterInfoToMangaChapterConverter = {
              id: chapterInfo.id,
              title: chapterInfo.title,
              chapterNumber: chapterNumber,
              pages: pages,// 使用加载的页面信息
              publishDate: chapterInfo.publishTime || Date.now(),
              isRead: false,
              readProgress: 0,
              language: 'zh-CN',
              scanlationGroup: '',
              isDownloaded: chapterInfo.isDownloaded || false,
              downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
              downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
              localPath: chapterInfo.downloadPath,
              externalId: chapterInfo.externalId// [重构] 从online_chapter或chapter表读取外部ID
            };

            if (chapterConvertLogCount < chapterConvertLogLimit) {
              logger.debug(TAG, `转换章节: ${converter.title}, 编号: ${converter.chapterNumber}, 页数: ${pages.length}`);
              chapterConvertLogCount++;
            }
            mangaChapters.push(converter as MangaChapter);
          }
          if (chapterConvertLogCount >= chapterConvertLogLimit && hasSourceId && chapters.length > chapterConvertLogLimit) {
            logger.debug(TAG, `章节转换日志已截断: 已记录${chapterConvertLogLimit}/${chapters.length}`);
          }

          manga.chapters = mangaChapters;
          logger.info(TAG, `Chapter list mapped from source, count=${manga.chapters.length}`);

          // [修复] 检查是否有章节缺少externalId，如果有则尝试从MangaSourceEngine补全
          const chaptersWithoutExternalId = manga.chapters.filter(ch =>
            !ch.externalId || ch.externalId.startsWith('id_')
          );
          if (chaptersWithoutExternalId.length > 0) {
            logger.warn(TAG, `Found ${chaptersWithoutExternalId.length} chapters missing valid externalId`);
            // 这里暂时记录警告，后续可以考虑从MangaSourceEngine重新获取
            chaptersWithoutExternalId.forEach(ch => {
              logger.warn(TAG, `  - 章节 ${ch.title} (id=${ch.id}) 缺少externalId`);
            });
          }

          // 输出章节页面统计信息（在线长目录场景限制日志量，避免初始化阶段日志阻塞）
          const chapterDetailLogLimit = hasSourceId ? 12 : manga.chapters.length;
          for (let index = 0; index < manga.chapters.length && index < chapterDetailLogLimit; index++) {
            const chapter = manga.chapters[index];
            const chapterPages = chapter.pages.length > 0 ? chapter.pages.length : (chapter.totalPages || 0);
            logger.info(TAG, `章节详情日志已截断: 已记录${chapterDetailLogLimit}/${manga.chapters.length}`);
          }
          if (manga.chapters.length > chapterDetailLogLimit) {
            logger.info(TAG, `章节详情日志已截断: 已记录${chapterDetailLogLimit}/${manga.chapters.length}`);
          }
        } else {
          logger.warn(TAG, '⚠️ 未找到章节信息');
          manga.chapters = [];
        }
        // [修复] 本地漫画加载完成，设置网络配置就绪（虽然不需要网络，但需要允许Viewer渲染）
        if (!this.isNetworkConfigReady) {
          this.isNetworkConfigReady = true;
          logger.info(TAG, `✅ 本地漫画配置就绪，允许Viewer渲染`);
        }
      } else {
        logger.error(TAG, '❌ 参数错误：必须提供manga或mangaId');
        throw new Error('路由参数无效：缺少 manga 或 mangaId');
      }

      logger.debug(TAG, `Requested chapterId from params: ${params.chapterId}`);
      logger.info(TAG, `📚 设置当前漫画: ${manga.title}`);
      this.readerState.currentManga = manga;
      this.reportTransitionLoadingProgress(0.28, 'manga_bound');
      logger.info(TAG, `📚 开始章节初始化，漫画总章节数: ${manga.chapters.length}`);

      // 设置当前章节 - 增强错误处理和日志
      logger.info(TAG, `📚 开始章节初始化，漫画总章节数: ${manga.chapters.length}`);
      
      if (params.chapterId) {
        logger.debug(TAG, `🔍 查找指定章节ID: ${params.chapterId}`);
        
        // [修复] 对于WebView图源，params.chapterId可能是外部ID或内部ID
        let chapter: MangaChapter | undefined;
        
        if (isWebViewSource) {
          // WebView图源：先尝试通过externalId匹配，如果失败则尝试内部ID
          logger.debug(TAG, `🌐 WebView图源，优先使用externalId匹配章节`);
          chapter = manga.chapters.find(ch => ch.externalId === params.chapterId);
          if (chapter) {
            logger.info(TAG, `✅ 通过externalId找到章节: ${chapter.title} (internalId: ${chapter.id}, externalId: ${chapter.externalId}, 页数: ${chapter.pages.length})`);
          } else {
            // [修复] 从最近阅读进入时，可能传递的是内部ID，尝试通过内部ID匹配
            logger.debug(TAG, `🔄 externalId未匹配，尝试使用内部ID匹配`);
            chapter = manga.chapters.find(ch => ch.id === params.chapterId);
            if (chapter) {
              logger.info(TAG, `✅ 通过内部ID找到章节: ${chapter.title} (ID: ${chapter.id}, externalId: ${chapter.externalId}, 页数: ${chapter.pages.length})`);
            } else {
              logger.warn(TAG, `可用章节externalId列表: ${manga.chapters.map(ch => `${ch.externalId || 'undefined'}`).join(', ')}`);
              logger.warn(TAG, `可用章节externalId列表: ${manga.chapters.map(ch => `${ch.externalId || 'undefined'}`).join(', ')}`);
            }
          }
        } else {
          // 非WebView图源：通过id匹配
          logger.debug(TAG, `📚 非WebView图源，使用id匹配章节`);
          chapter = manga.chapters.find(ch => ch.id === params.chapterId);
          if (chapter) {
            logger.info(TAG, `✅ 通过id找到章节: ${chapter.title} (ID: ${chapter.id}, 页数: ${chapter.pages.length})`);
          } else {
            logger.warn(TAG, `可用章节ID列表: ${manga.chapters.map(ch => ch.id).join(', ')}`);
            logger.warn(TAG, `可用章节ID列表: ${manga.chapters.map(ch => ch.id).join(', ')}`);
          }
        }
        
        if (chapter) {
          this.readerState.currentChapter = chapter;
        } else {
          logger.warn(TAG, `⚠️ 未找到指定章节，将使用第一个章节作为回退`);
        }
      } else {
        logger.debug(TAG, '📖 未指定章节ID，将使用第一个章节');
      }

      // 如果没有指定章节或未找到，使用编号最小的章节
      if (!this.readerState.currentChapter && manga.chapters.length > 0) {
        let firstChapter: MangaChapter = manga.chapters[0];
        for (let i: number = 1; i < manga.chapters.length; i++) {
          const ch: MangaChapter = manga.chapters[i];
          if (ch.chapterNumber < firstChapter.chapterNumber) {
            firstChapter = ch;
          }
        }
        this.readerState.currentChapter = firstChapter;
        logger.info(TAG, `📖 使用最旧章节(编号最小): ${this.readerState.currentChapter.title} (ID: ${this.readerState.currentChapter.id}, 页数: ${this.readerState.currentChapter.pages.length})`);
      } else if (!this.readerState.currentChapter) {
        // 没有可用章节的错误处理
        const errorDetails: ChapterErrorDetails = {
          mangaTitle: manga.title,
          mangaId: manga.id,
          chaptersCount: manga.chapters.length,
          specifiedChapterId: params.chapterId,
          availableChapterIds: manga.chapters.map(ch => ch.id)
        };
        logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
        logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
        this.readerState.errorMessage =
          `漫画《${manga.title}》没有可用章节\n章节数量: ${manga.chapters.length}\n${params.chapterId ? `请求章节 ID: ${params.chapterId}` : '请求章节 ID: 无'}`;
        this.readerState.isLoading = false;
        // [修复] 提前返回时也要通知过渡动画，防止覆盖层阻止交互
        this.notifyTransitionReaderReadyOnce('no_available_chapter');
        return;
      }

      this.reportTransitionLoadingProgress(0.46, 'chapter_bound');

      const shouldTryOnlineArchivePages =
        params.contentType === MangaReaderContentType.OnlineDownloaded ||
        params.contentType === MangaReaderContentType.OnlineUndownloaded;
      const didLoadOnlineArchivePages = shouldTryOnlineArchivePages
        ? await this.tryLoadOnlineDownloadedArchivePagesForChapter(this.readerState.currentChapter, true)
        : false;

      // [修复] 扩展条件：当页面为空，或页面存在但第一页的sourceType仍为NETWORK时，重新加载
      const needsLocalPathReload = !didLoadOnlineArchivePages && params.contentType === MangaReaderContentType.OnlineDownloaded && (
        this.readerState.currentChapter.pages.length === 0 ||
        (this.readerState.currentChapter.pages.length > 0 && 
         this.readerState.currentChapter.pages[0].sourceType === ImageSourceType.NETWORK)
      );
      if (needsLocalPathReload) {
        logger.info(TAG, '📥 在线已下载章节：从online_page表重新加载页面以获取本地路径');
        
        // [修复] 使用getOnlineChapterPages查询online_page表
        const pageInfos = await DataManager.getInstance().getOnlineChapterPages(this.readerState.currentChapter.id);
        // [修复] 使用数组索引而不是pageNumber，确保index是0-indexed
        const mangaPages: MangaPage[] = pageInfos.map((pageInfo: OnlinePageInfo, arrayIndex: number) => {
          // 在线已下载的页面应该有localPath
          let sourceType: ImageSourceType;
          let imagePath: string;
          
          // 优先使用localPath（如果已下载）
          if (pageInfo.localPath && pageInfo.localPath.length > 0) {
            sourceType = ImageSourceType.LOCAL;
            imagePath = pageInfo.localPath;
            logger.debug(TAG, `  - 页面 ${pageInfo.pageNumber}: 使用本地路径 ${imagePath}`);
          } else {
            // 如果没有localPath，使用imageUrl（可能是网络URL）
            if (pageInfo.imageUrl.startsWith('http://') || pageInfo.imageUrl.startsWith('https://')) {
              sourceType = ImageSourceType.NETWORK;
            } else {
              sourceType = ImageSourceType.RAWFILE;
            }
            imagePath = pageInfo.imageUrl;
            logger.warn(TAG, `  - 页面 ${pageInfo.pageNumber}: 未找到本地路径，使用 ${sourceType}`);
          }
          
          const page: MangaPage = {
            id: pageInfo.id,
            index: arrayIndex,// [修复] 使用0-indexed数组索引
            sourceType: sourceType,
            imagePath: imagePath,
            imageUrl: pageInfo.imageUrl,
            localPath: pageInfo.localPath,// [新增] 保留本地路径
            width: pageInfo.width,
            height: pageInfo.height,
            fileSize: pageInfo.fileSize,
            isLoaded: false
          };
          return page;
        });
        this.readerState.currentChapter.pages = mangaPages;
        // [新增] 输出加载统计
        const localCount = mangaPages.filter(p => p.sourceType === ImageSourceType.LOCAL).length;
        const networkCount = mangaPages.filter(p => p.sourceType === ImageSourceType.NETWORK).length;
        logger.info(TAG, `✅ 从online_page表加载 ${mangaPages.length} 张页面 (本地: ${localCount}, 网络: ${networkCount})`);
        if (this.mangaViewerComponent) {
          this.mangaViewerComponent.kickstartLoading();
        }
      }

      // 在线未下载：使用WebView动态加载页面列表
      let didDynamicPageList: boolean = false;
      // 如果页面数量为0，或者页面数量>0但第一页没有有效的图片链接，都视为需要动态加载
      // 如果页面数量为0，或者页面数量>0但第一页没有有效的图片链接，都视为需要动态加载
      const shouldRefreshVolatilePages = this.shouldRefreshVolatileSourcePages();
      const hasValidPages = !shouldRefreshVolatilePages &&
        this.readerState.currentChapter.pages.length > 0 &&
        (!!this.readerState.currentChapter.pages[0].imageUrl || !!this.readerState.currentChapter.pages[0].imagePath);

      // 调试日志：输出页面数据状态
      logger.debug(TAG, `📊 页面数据检查: 页数=${this.readerState.currentChapter.pages.length}, hasValidPages=${hasValidPages}`);
      if (this.readerState.currentChapter.pages.length > 0) {
        const firstPage = this.readerState.currentChapter.pages[0];
        logger.debug(TAG, `📄 第一页数据: imageUrl="${firstPage.imageUrl}", imagePath="${firstPage.imagePath}"`);
      }

      if (isWebViewSource && this.mangaEngine && !hasValidPages) {
        logger.info(TAG, 'WebView chapter has no valid local pages, fallback to source getPageList');

        // [P0] Cache-first: already cached online pages should bypass network page-list flow.
        // [P0] Cache-first: already cached online pages should bypass network page-list flow.
        let validCachedDbPages: OnlinePageInfo[] = [];
        if (shouldRefreshVolatilePages) {
          logger.info(TAG, '[缓存优先] 易失票据图源跳过 online_page 缓存，刷新页面票据');
        } else {
          try {
            const cachedDataManager = DataManager.getInstance();
            const cachedDbPages = await cachedDataManager.getOnlineChapterPages(this.readerState.currentChapter.id);
            validCachedDbPages = cachedDbPages.filter((p: OnlinePageInfo) => p.imageUrl && p.imageUrl.trim().length > 0);
          } catch (cacheError) {
            logger.warn(TAG, `[缓存优先] 查询失败，回退到引擎路径: ${String(cacheError)}`);
          }
        }
        if (validCachedDbPages.length > 0) {
          const currentChapterId = this.readerState.currentChapter.id;
          const shouldForceNetworkSource = params.contentType === MangaReaderContentType.OnlineUndownloaded;
          const cachedMangaPages: MangaPage[] = validCachedDbPages.map((pageInfo: OnlinePageInfo, index: number) => {
            const hasLocalPath = !!pageInfo.localPath && pageInfo.localPath.trim().length > 0;
            const useLocalPath = !shouldForceNetworkSource && hasLocalPath;
            const sourceType: ImageSourceType = useLocalPath ? ImageSourceType.LOCAL : ImageSourceType.NETWORK;
            const imagePath = useLocalPath ? pageInfo.localPath : pageInfo.imageUrl;
            return {
              id: pageInfo.id || `${currentChapterId}_page_${pageInfo.pageNumber}`,
              index: index,
              sourceType: sourceType,
              imagePath: imagePath,
              imageUrl: pageInfo.imageUrl,
              localPath: pageInfo.localPath,
              width: pageInfo.width,
              height: pageInfo.height,
              fileSize: pageInfo.fileSize,
              isLoaded: false
            } as MangaPage;
          });
          this.readerState.currentChapter.pages = cachedMangaPages;
          logger.info(TAG, `[P0] Cache-first hit online_page: count=${cachedMangaPages.length}`);
          if (this.mangaViewerComponent) {
            this.mangaViewerComponent.kickstartLoading();
          }
          this.preloadNextChapterAfterCurrentLoaded();
          didDynamicPageList = true;
        } else {
          const externalMangaId = await this.getExternalMangaIdForOnlineUndownloaded(params.mangaId || manga.id);
        logger.info(TAG, `  - 最终使用的外部漫画ID: ${externalMangaId}`);

        // [修复] 优先使用传入的params.chapterId（它就是正确的externalId）
        let externalChapterId: string;
        if (params.chapterId && !params.chapterId.startsWith('id_') && !params.chapterId.startsWith('local_')) {
          // params.chapterId本身就是外部ID，直接使用
          externalChapterId = params.chapterId;
          logger.info(TAG, `✅ 直接使用传入的chapterId作为externalId: ${externalChapterId}`);
        } else {
          // 否则尝试从章节对象或数据库获取
          externalChapterId = await this.getExternalChapterIdForOnlineUndownloaded(this.readerState.currentChapter);
          logger.info(TAG, `✅ 从章节对象/数据库获取externalId: ${externalChapterId}`);
        }
        logger.info(TAG, `  - 最终使用的外部章节ID: ${externalChapterId}`);

        try {
          // [修复] 显示加载状态
          this.readerState.loadingMessage = '正在从源站加载章节页面...';
          logger.info(TAG, `🔄 开始获取页面列表: mangaId=${externalMangaId}, chapterId=${externalChapterId}`);

          // [优化] 检查 MangaDetailPage 预取的页面列表缓存
          let pageListResult: ESObject | null = null;
          if (params.sourceId && externalChapterId) {
            const prefetched = MangaSourceEngine.getPrefetchedPages(params.sourceId, externalChapterId);
            if (prefetched && prefetched.length > 0) {
              pageListResult = { success: true, data: prefetched, duration: 0, actionCount: 0 };
              logger.info(TAG, `[预取] 使用预取的页面列表: ${prefetched.length} 页`);
            }
          }

          if (!pageListResult) {
            // [P0] 首屏不做固定延迟和长退避重试：立即请求，失败后仅即时重试一次
            pageListResult = await this.mangaEngine.getPageList(externalChapterId, externalMangaId);
            if (!pageListResult.success || !pageListResult.data || pageListResult.data.length === 0) {
              logger.warn(TAG, '[P0] 首次获取页面列表失败/为空，立即重试一次');
              pageListResult = await this.mangaEngine.getPageList(externalChapterId, externalMangaId);
            }

            if (!pageListResult) {
              throw new Error('从源站加载页面列表失败');
            }
          }
          
          logger.info(TAG, `📊 页面列表获取结果: success=${pageListResult.success}, hasData=${!!pageListResult.data}, dataLength=${pageListResult.data?.length || 0}`);
          if (pageListResult.error) {
            logger.error(TAG, `❌ 页面列表获取错误: ${pageListResult.error}`);
          }

          // if (this.networkHeaders && this.networkHeaders.referer && this.networkHeaders.referer.includes('komiic.com')) {
          // if (this.networkHeaders && this.networkHeaders.referer && this.networkHeaders.referer.includes('komiic.com')) {
          //    const newReferer = `https://komiic.com/comic/${externalMangaId}/chapter/${externalChapterId}/images/all`;
          //    const prev: RequestHeaders = this.networkHeaders as RequestHeaders;
          //    const updated: RequestHeaders = {
          //      userAgent: prev.userAgent,
          //      accept: prev.accept,
          //      referer: newReferer,
          //      acceptLanguage: prev.acceptLanguage,
          //      cacheControl: prev.cacheControl,
          //      pragma: prev.pragma,
          //      secFetchDest: prev.secFetchDest,
          //      secFetchMode: prev.secFetchMode,
          //      secFetchSite: prev.secFetchSite
          //    } as RequestHeaders;
          //    if (prev.cookie) {
          //      updated.cookie = prev.cookie;
          //    }
          //    this.networkHeaders = updated as RequestHeaders;
          //    this.networkHeadersTick = this.networkHeadersTick + 1;
          logger.info(TAG, `✅ 页面列表获取成功，共 ${pageListResult.data.length} 页`);
          // }
          
          if (!pageListResult.success || !pageListResult.data) {
            const errorMsg: string = (pageListResult.error as string) || '获取页面列表失败';
            logger.error(TAG, `❌ 页面列表获取失败: ${errorMsg}`);
            this.readerState.errorMessage = `加载章节页面失败\n${errorMsg}`;
            this.readerState.isLoading = false;
            throw new Error(errorMsg);
          }
          
          logger.info(TAG, `Source getPageList 返回 ${pageListResult.data.length} 页`);
          
          // [调试] 输出所有页面详情
          logger.info(TAG, `📊 [MangaReaderPage] 从MangaSourceEngine获取到的页面详情:`);
          pageListResult.data.forEach((page: SourcePageInfo, idx: number) => {
            if (idx < 10) {
              logger.info(TAG, `  - 页面${idx}: imageUrl=${page.imageUrl?.substring(0, 80) || 'URL为空'}, page=${page.page}`);
            }
          });
          if (pageListResult.data.length > 10) {
            logger.info(TAG, `  ... 还有 ${pageListResult.data.length - 10} 页未显示`);
          }
          
          // [重构] 对于在线未下载漫画，从online_page表查询（不与本地方法混用）
          const dataManager = DataManager.getInstance();
          let dbPages: OnlinePageInfo[] = [];
          if (!shouldRefreshVolatilePages) {
            dbPages = await dataManager.getOnlineChapterPages(this.readerState.currentChapter.id);
          } else {
            logger.info(TAG, '易失票据图源跳过网络为空时的 online_page 回退');
          }

          // 如果网络获取的页面列表为空，但数据库有数据，则使用数据库数据作为后备
          let sourcePages: SourcePageInfo[] = pageListResult.data;
          if (!shouldRefreshVolatilePages && sourcePages.length === 0 && dbPages.length > 0) {
            logger.warn(TAG, '⚠️ 网络获取页面列表为空，回退使用online_page表缓存页面');
            sourcePages = dbPages.map((p: OnlinePageInfo): SourcePageInfo => {
              const sp: SourcePageInfo = {
                page: p.pageNumber,
                imageUrl: p.imageUrl,
                width: p.width,
                height: p.height
              } as SourcePageInfo;
              return sp;
            });
          }

          // [修复] 检查是否有有效的图片URL
          const validPages = sourcePages.filter(p => p.imageUrl && p.imageUrl.trim().length > 0);
          
          if (validPages.length === 0) {
            const errorMsg = 'No valid page URL found in source response';
            logger.error(TAG, `原始数据: ${JSON.stringify(sourcePages.slice(0, 3))}`);
            logger.error(TAG, `原始数据: ${JSON.stringify(sourcePages.slice(0, 3))}`);
            this.readerState.errorMessage = `构建章节页面失败\n${errorMsg}\n请检查源站解析规则后重试`;
            this.readerState.isLoading = false;
            throw new Error(errorMsg);
          }
          
          logger.info(TAG, `✅ 有效图片数量: ${validPages.length}`);
          
          // 转换SourcePageInfo为MangaPage
          const pagesToConvert = validPages;
          const currentChapterId = this.readerState.currentChapter.id;
          const mangaPages: MangaPage[] = pagesToConvert.map((pageInfo: SourcePageInfo, index: number) => {
            // [修复] 使用章节ID+页码作为唯一ID，避免不同章节的页面ID冲突导致PixelMap缓存返回错误图片
            // [修复] 使用章节ID+页码作为唯一ID，避免不同章节的页面ID冲突导致PixelMap缓存返回错误图片
            const page: MangaPage = {
              id: `${currentChapterId}_page_${pageInfo.page}`,
              index: index,
              sourceType: ImageSourceType.NETWORK,
              imagePath: pageInfo.imageUrl || '', // 占位页面可能为空
              imageUrl: pageInfo.imageUrl || '', // 占位页面可能为空
              width: pageInfo.width,
              height: pageInfo.height,
              fileSize: 0,
              requestHeaders: this.cloneSourcePageRequestHeaders(pageInfo),
              isLoaded: false
            };
            
            return page;
          });
          
          // 更新章节的页面列表
          this.readerState.currentChapter.pages = mangaPages;
          
          logger.info(TAG, `📊 [MangaReaderPage] 转换后的MangaPage详情:`);
          mangaPages.forEach((page: MangaPage, idx: number) => {
            if (idx < 10) {
              logger.info(TAG, `  - MangaPage${idx}: id=${page.id}, imageUrl=${page.imageUrl?.substring(0, 80) || 'URL为空'}`);
            }
          });
          if (mangaPages.length > 10) {
            logger.info(TAG, `  ... 还有 ${mangaPages.length - 10} 页未显示`);
          }
          logger.info(TAG, `Converted source pages to MangaPage, count=${mangaPages.length}`);
          
          // [修复] 保存页面列表到数据库 - 使用内部章节ID而不是外部ID
          if (validPages.length > 0) {
            const internalChapterId = this.readerState.currentChapter.id;
            logger.info(TAG, `💾 准备保存页面信息: 内部ID=${internalChapterId}, 外部ID=${externalChapterId}, 页数=${validPages.length}`);
            this.saveChapterPagesToDatabase(internalChapterId, validPages).catch((err: Error) => {
              logger.warn(TAG, `保存页面列表失败: ${err.message}`);
            });
          }

          if (this.mangaViewerComponent) {
            this.mangaViewerComponent.kickstartLoading();
          }
          
        // [修改] 仅当 sourcePages 有数据且来自网络时保存
        // [修改] 仅当 sourcePages 有数据且来自网络时保存
        if (sourcePages.length > 0) {
          this.savePageInfoToDatabase(this.readerState.currentChapter.id, sourcePages).catch((err: Error) => {
            logger.warn(TAG, `保存page表页面列表失败: ${err.message}`);
          });
          
          // 当前章节页面信息加载完成后，立即预加载下一章节（如果启用）
          this.preloadNextChapterAfterCurrentLoaded();
        }
          // 在线图源：检测每日限额（仅对支持的图源如Komiic执行）
          this.detectDailyImageLimitIfSupported(externalChapterId).catch((limitError: Error) => {
            logger.warn(TAG, `检测每日限额失败（忽略，不影响阅读首屏）: ${String(limitError)}`);
          });

        } catch (error) {
          logger.error(TAG, `❌ 动态加载页面列表失败: ${String(error)}`);
          this.readerState.errorMessage = `切换章节页面失败: ${String(error)}`;
          this.readerState.isLoading = false;
          // [修复] 提前返回时也要通知过渡动画，防止覆盖层阻止交互
          this.notifyTransitionReaderReadyOnce('dynamic_page_list_failed');
          return;
        }
        didDynamicPageList = true;
        }
      }
      // 在线未下载：章节已有页面数据（来自数据库或上游），也需要校验并主动触发网络加载
      if (!didDynamicPageList && params.contentType === MangaReaderContentType.OnlineUndownloaded && this.readerState.currentChapter && this.readerState.currentChapter.pages && this.readerState.currentChapter.pages.length > 0) {
        logger.info(TAG, '📥 检测到已有页面数据，准备校验并加载');
        try {
          const pages: MangaPage[] = this.readerState.currentChapter.pages;
          for (let i: number = 0; i < pages.length; i++) {
            const pg: MangaPage = pages[i];
            if (pg.sourceType === ImageSourceType.LOCAL) {
              const rawPath: string = (pg.imagePath && pg.imagePath.length > 0) ? (pg.imagePath.startsWith('file://') ? pg.imagePath.substring(7) : pg.imagePath) : '';
              let exists: boolean = false;
              if (rawPath.length > 0) {
                try {
                  const st = await fs.stat(rawPath);
                  exists = !!st && !!st.size;
                } catch (_e) {
                  exists = false;
                }
              }
              if (!exists) {
                pg.sourceType = ImageSourceType.NETWORK;
                pg.imagePath = pg.imageUrl;
                logger.warn(TAG, `🔁 校正页面为网络源(预校验): index=${pg.index}, 原本地路径不存在: ${rawPath}`);
              }
            } else if (pg.sourceType === ImageSourceType.RAWFILE) {
              const isHttp: boolean = pg.imageUrl.startsWith('http://') || pg.imageUrl.startsWith('https://');
              if (isHttp) {
                pg.sourceType = ImageSourceType.NETWORK;
                pg.imagePath = pg.imageUrl;
                logger.warn(TAG, `🔁 校正页面为网络源(原RAWFILE): index=${pg.index}`);
              }
            }
          }
          // 触发MangaViewer的首图加载（若组件已就绪）
          if (this.mangaViewerComponent) {
            this.mangaViewerComponent.kickstartLoading();
          }
        } catch (primeErr) {
          const pmsg: string = primeErr instanceof Error ? primeErr.message : String(primeErr);
          logger.warn(TAG, `在线未下载预触发网络加载异常: ${pmsg}`);
        }
      }
      
      // 设置当前页面索引 - 增强验证和日志
      const requestedPageIndex = params.pageIndex !== undefined ? params.pageIndex : 0;
      // [修复] 使用totalPages而不是pages.length来显示实际总页数
      const totalPages = this.readerState.currentChapter.totalPages || this.readerState.currentChapter.pages.length;
      const maxPageIndex = Math.max(0, this.readerState.currentChapter.pages.length - 1);
      
      logger.debug(TAG, `  - 请求页面索引: ${requestedPageIndex}`);
      logger.debug(TAG, `  - 章节总页数: ${totalPages}`);
      logger.debug(TAG, `  - 最大页面索引: ${maxPageIndex}`);
      logger.debug(TAG, `  - 最大页面索引: ${maxPageIndex}`);
      
      if (totalPages === 0) {
        logger.error(TAG, `❌ 当前章节没有页面数据`);
        this.readerState.errorMessage = `章节《${this.readerState.currentChapter.title}》没有页面数据`;
        this.readerState.isLoading = false;
        // [修复] 提前返回时也要通知过渡动画，防止覆盖层阻止交互
        this.notifyTransitionReaderReadyOnce('chapter_without_pages');
        return;
      }
      
      // 确保页面索引在有效范围内
      this.readerState.currentPageIndex = Math.max(0, Math.min(requestedPageIndex, maxPageIndex));
      this.refreshCurrentMangaBookmarkState('initialize_reader_page_index');
      
      if (requestedPageIndex !== this.readerState.currentPageIndex) {
        logger.warn(TAG, `⚠️ 请求的页面索引 ${requestedPageIndex} 超出范围 [0, ${maxPageIndex}]，已调整为 ${this.readerState.currentPageIndex}`);
      }
      
      // [修复] 优先使用currentChapter.totalPages，如果未设置则使用pages.length
      const displayTotalPages = this.readerState.currentChapter.totalPages || totalPages;
      logger.info(TAG, `Current page: ${this.readerState.currentPageIndex + 1}/${displayTotalPages}`);

      // 记录当前页面详细信息
      const currentPage = this.readerState.currentChapter.pages[this.readerState.currentPageIndex];
      if (currentPage) {
        logger.debug(TAG, `  - 页面ID: ${currentPage.id}`);
        logger.debug(TAG, `  - 页面索引: ${currentPage.index}`);
        logger.debug(TAG, `  - 图片源类型: ${currentPage.sourceType}`);
        logger.debug(TAG, `  - 图片URL: ${currentPage.imageUrl}`);
        logger.debug(TAG, `  - 图片URL: ${currentPage.imageUrl}`);
      }

      this.reportTransitionLoadingProgress(0.72, 'chapter_pages_ready');

      logger.debug(TAG, '⚙️ 开始加载阅读设置');
      await this.loadReadingSettings();
      this.reportTransitionLoadingProgress(0.84, 'reading_settings_ready');

      // [新增] 此时章节已确定，强制刷新一次 Headers 以确保 Referer 正确
      await this.updateNetworkHeadersForChapter(); 

      logger.debug(TAG, '🖼️ 开始预加载图片');
      setTimeout(() => {
        this.preloadImages();
      }, 0);

      // 初始化阅读会话计时与保存状态
      this.sessionStartTimestamp = Date.now();
      this.lastProgressSaveTime = 0;
      this.lastSavedPageIndex = -1;

      // [修复] 最终确保配置就绪（如果之前未设置）
      if (!this.isNetworkConfigReady) {
        this.isNetworkConfigReady = true;
        logger.info(TAG, `✅ 最终确保配置就绪，允许Viewer渲染`);
      }
      this.lastInitializedParamsKey = this.buildInitParamsKey(params);
      this.readerState.isLoading = false;
      this.reportTransitionLoadingProgress(0.94, 'init_done_wait_visual_ready');
      logger.info(TAG, '✅ 漫画阅读器初始化完成');
      
      // 动画覆盖层退出时机：等待首屏视觉内容就绪（由MangaViewer回调+轮询共同保障）
      this.waitForTransitionReaderReady('init_success');
      
      logger.info(TAG, `📊 初始化摘要:`);
      logger.info(TAG, `📊 初始化摘要:`);
      logger.info(TAG, `  - 漫画: ${this.readerState.currentManga?.title}`);
      // [修复] 优先使用totalPages显示实际总页数
      const summaryTotalPages = this.readerState.currentChapter?.totalPages || this.readerState.currentChapter?.pages.length || 0;
      logger.info(TAG, `  - page summary: ${this.readerState.currentPageIndex + 1}/${summaryTotalPages}`);
      logger.info(TAG, `  - 当前页面: 第${this.readerState.currentPageIndex + 1}页/${summaryTotalPages}页`);
      logger.info(TAG, `  - 阅读模式: ${this.readingSettings.readingMode}`);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: ErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        errorStack: error instanceof Error ? error.stack : undefined,
        mangaTitle: params?.manga?.title || (params?.mangaId ? `ID: ${params.mangaId}` : undefined),
        mangaId: params?.manga?.id || params?.mangaId,
        chapterId: params?.chapterId,
        pageIndex: params?.pageIndex,
        timestamp: new Date().toISOString()
      };
      
      const mangaInfo = params?.manga?.title || (params?.mangaId ? `ID: ${params.mangaId}` : '未知');
      this.readerState.errorMessage =
        `阅读器初始化失败: ${errorMessage}\n\n漫画: ${mangaInfo}\n章节 ID: ${params?.chapterId || '未提供'}\n页码: ${params?.pageIndex || 0}\n\n请检查网络和数据源状态后重试。`;
      this.readerState.isLoading = false;
      
      // [修复] 初始化失败时也要通知过渡动画，防止覆盖层阻止交互
      this.notifyTransitionReaderReadyOnce('init_failed');
      
      logger.error(TAG, '❌ 漫画阅读器初始化失败', errorMessage);
      logger.error(TAG, '❌ 漫画阅读器初始化失败', errorMessage);
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
    }
  }

  private clearTransitionReaderReadyTimers(): void {
    if (this.transitionReaderReadyPollTimer !== -1) {
      clearInterval(this.transitionReaderReadyPollTimer);
      this.transitionReaderReadyPollTimer = -1;
    }
    if (this.transitionReaderReadyTimeoutTimer !== -1) {
      clearTimeout(this.transitionReaderReadyTimeoutTimer);
      this.transitionReaderReadyTimeoutTimer = -1;
    }
  }

  private reportTransitionLoadingProgress(progress: number, reason: string): void {
    if (!this.shouldUseReaderTransition()) {
      return;
    }
    const normalized = Math.max(0, Math.min(1, progress > 1 ? progress / 100 : progress));
    if (normalized <= this.transitionLoadingProgress + 0.001) {
      return;
    }
    this.transitionLoadingProgress = normalized;
    setReaderLoadingProgress(normalized);
    logger.debug(TAG, `过渡加载进度: ${(normalized * 100).toFixed(1)}%, 原因=${reason}`);
  }

  private notifyTransitionReaderReadyOnce(reason: string): void {
    if (!this.shouldUseReaderTransition()) {
      return;
    }
    if (this.hasNotifiedTransitionReaderReady) {
      logger.debug(TAG, `过渡动画就绪已通知，忽略重复触发: ${reason}`);
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    this.clearTransitionReaderReadyTimers();
    this.reportTransitionLoadingProgress(1, `ready_${reason}`);
    setReaderReady();
    logger.info(TAG, `📤 已通知过渡动画阅读器就绪: ${reason}`);
  }

  private waitForTransitionReaderReady(trigger: string): void {
    if (!this.shouldUseReaderTransition()) {
      return;
    }
    if (this.hasNotifiedTransitionReaderReady) {
      return;
    }

    const checkVisualReady = (): boolean => {
      const viewer = this.mangaViewerComponent;
      if (!viewer) {
        return false;
      }

      let isReady: boolean = false;
      try {
        isReady = viewer.isCurrentVisualReady();
      } catch (error) {
        logger.warn(TAG, `检查MangaViewer视觉就绪异常: ${String(error)}`);
        return false;
      }

      if (isReady) {
        this.notifyTransitionReaderReadyOnce(`visual_ready_${trigger}`);
        return true;
      }
      return false;
    };

    if (checkVisualReady()) {
      return;
    }

    if (this.transitionReaderReadyPollTimer === -1) {
      this.transitionReaderReadyPollTimer = setInterval(() => {
        checkVisualReady();
      }, MangaReaderPage.TRANSITION_READY_POLL_MS);
    }

    if (this.transitionReaderReadyTimeoutTimer === -1) {
      this.transitionReaderReadyTimeoutTimer = setTimeout(() => {
        if (!this.hasNotifiedTransitionReaderReady) {
          logger.warn(TAG, `等待首屏视觉就绪超时，降级放行过渡动画: 触发源=${trigger}`);
          this.notifyTransitionReaderReadyOnce(`timeout_${trigger}`);
        }
      }, MangaReaderPage.TRANSITION_READY_TIMEOUT_MS);
    }
  }

  /**
   * 检测图源每日图片访问限额（仅对支持的图源执行，例如Komiic）
    */
  private async detectDailyImageLimitIfSupported(externalChapterId: string): Promise<void> {
    const engine: MangaSourceEngine | null = this.mangaEngine;
    if (!engine) {
      return;
    }
    const cfg = engine.getConfig();
    if (!cfg || !cfg.metadata || !cfg.metadata.baseUrl) {
      return;
    }
    const baseUrl: string = cfg.metadata.baseUrl;
    const isKomiic: boolean = (baseUrl.indexOf('komiic.com') >= 0);
    if (!isKomiic) {
      return;
    }

    const apiEngine = new MangaSourceAPIEngine();

    // GraphQL端点与查询
    const endpoint: string = 'https://komiic.com/api/query';
    const query: string = 'query imagesByChapterId($chapterId: ID!) { imagesByChapterId(chapterId: $chapterId) { kid } reachedImageLimit }';

    // 统一User-Agent：优先使用已存在请求头，避免阻塞首屏流程
    let ua: string = this.networkHeaders?.userAgent || '';
    if (!ua) {
      ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    }

    // 明确的请求头类型定义，避免未类型化对象字面量
    interface GraphQLHeaders {
      'Content-Type': string;
      'Accept': string;
      'User-Agent': string;
      'Referer': string;
      'Origin'?: string;
      'Cookie'?: string;
    }
    const headers: GraphQLHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': ua,
      'Referer': baseUrl,
      'Origin': baseUrl
    };

    try {
      const cmg = CookieManager.getInstance();
      const sidVal: number = this.currentSourceId > 0 ? this.currentSourceId : 0;
      const cookieStr: string = await cmg.getCookieString(sidVal);
      if (cookieStr.length > 0) {
        let raw: string = String(cookieStr).trim();
        const rawLen: number = raw.length;
        if (rawLen >= 2 && ((raw.charAt(0) === '"' && raw.charAt(rawLen - 1) === '"') || (raw.charAt(0) === '\'' && raw.charAt(rawLen - 1) === '\''))) {
          raw = raw.substring(1, rawLen - 1).trim();
        }
        const parts: string[] = raw.split(';');
        const names: string[] = [];
        const resultPairs: string[] = [];
        let i: number = 0;
        while (i < parts.length) {
          const item: string = parts[i].trim();
          const eq: number = item.indexOf('=');
          if (eq > 0) {
            let name: string = item.substring(0, eq).trim();
            let value: string = item.substring(eq + 1).trim();
            const nLen: number = name.length;
            if (nLen >= 2 && ((name.charAt(0) === '"' && name.charAt(nLen - 1) === '"') || (name.charAt(0) === '\'' && name.charAt(nLen - 1) === '\''))) {
              name = name.substring(1, nLen - 1).trim();
            }
            const vLen: number = value.length;
            if (vLen >= 2 && ((value.charAt(0) === '"' && value.charAt(vLen - 1) === '"') || (value.charAt(0) === '\'' && value.charAt(vLen - 1) === '\''))) {
              value = value.substring(1, vLen - 1).trim();
            }
            const exists: boolean = names.indexOf(name) >= 0;
            if (!exists) {
              names.push(name);
              resultPairs.push(name + '=' + value);
            }
          }
          i = i + 1;
        }
        headers.Cookie = resultPairs.join('; ');
      }
    } catch (cookieError) {
      const msg: string = cookieError instanceof Error ? cookieError.message : String(cookieError);
      logger.warn(TAG, `读取并注入GraphQL Cookie失败: ${msg}`);
    }

    // 变量对象类型定义
    interface ImagesByChapterVariables {
      chapterId: string;
    }
    const variables: ImagesByChapterVariables = { chapterId: externalChapterId };

    try {
      const resp = await apiEngine.graphql(endpoint, query, variables, headers);

      // 响应类型定义并解析
      interface KomiicImagesByChapterItem {
        url: string;
        width?: number;
        height?: number;
        kid?: string;
      }
      interface KomiicImagesByChapterData {
        imagesByChapterId?: KomiicImagesByChapterItem[];
        reachedImageLimit?: boolean;
      }
      interface KomiicImagesByChapterResponse {
        data?: KomiicImagesByChapterData;
      }

      const responseObj: KomiicImagesByChapterResponse = resp as KomiicImagesByChapterResponse;
      let reached: boolean = false;
      if (responseObj && responseObj.data && typeof responseObj.data.reachedImageLimit === 'boolean') {
        reached = responseObj.data.reachedImageLimit as boolean;
      }

      if (reached) {
        this.dailyLimitReached = true;
        this.dailyLimitMessage = 'Daily limit reached, please try again later';
        this.dailyLimitPromptVisible = true;
        logger.warn(TAG, '⚠️ 检测到每日图片访问限额已达上限');
      } else {
        this.dailyLimitReached = false;
        this.dailyLimitPromptVisible = false;
        this.dailyLimitMessage = '';
      }
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `每日限额检测失败: ${msg}`);
    }
  }

  /**
   * 加载阅读设置
   * 加载阅读设置
   * [修复] 始终从数据库加载最新的阅读设置，避免params.manga传入的对象设置过时
    */
  private cloneReadingSettings(settings: ReadingSettings): ReadingSettings {
    const lockMode: boolean = settings.lockMode ??
      settings.lockOrientation ??
      DEFAULT_READING_SETTINGS.lockMode ??
      DEFAULT_READING_SETTINGS.lockOrientation ??
      false;
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: lockMode,
      lockOrientation: lockMode,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      doublePageVerticalDirection: settings.doublePageVerticalDirection ??
        DEFAULT_READING_SETTINGS.doublePageVerticalDirection ??
        DoublePageVerticalDirection.TOP_TO_BOTTOM,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: settings.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: settings.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
  }

  private isSinglePageReadingMode(mode: ReadingMode): boolean {
    return mode === ReadingMode.SINGLE_PAGE ||
      mode === ReadingMode.SINGLE_PAGE_LTR ||
      mode === ReadingMode.SINGLE_PAGE_RTL ||
      mode === ReadingMode.SINGLE_PAGE_TTB;
  }

  private resolveLandscapeDoublePageDirection(settings: ReadingSettings): ReadingDirection {
    if (settings.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
      return ReadingDirection.RIGHT_TO_LEFT;
    }
    if (settings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      settings.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    if (settings.readingDirection === ReadingDirection.RIGHT_TO_LEFT) {
      return ReadingDirection.RIGHT_TO_LEFT;
    }
    return ReadingDirection.LEFT_TO_RIGHT;
  }

  private shouldUseLandscapeAutoDoublePage(): boolean {
    return this.isLandscapeScreen() &&
      !this.isModeLocked() &&
      this.isSinglePageReadingMode(this.readingSettings.readingMode);
  }

  private isModeLocked(): boolean {
    return this.readingSettings.lockMode ??
      this.readingSettings.lockOrientation ??
      DEFAULT_READING_SETTINGS.lockMode ??
      DEFAULT_READING_SETTINGS.lockOrientation ??
      false;
  }

  private getViewerReadingSettingsCacheKey(): string {
    return `${this.isLandscapeScreen() ? 'landscape' : 'portrait'}|${JSON.stringify(this.readingSettings)}`;
  }

  private getViewerReadingSettings(): ReadingSettings {
    const cacheKey: string = this.getViewerReadingSettingsCacheKey();
    if (cacheKey === this.viewerReadingSettingsCacheKey) {
      return this.viewerReadingSettingsCache;
    }

    const settings: ReadingSettings = this.cloneReadingSettings(this.readingSettings);
    if (this.shouldUseLandscapeAutoDoublePage()) {
      settings.readingMode = ReadingMode.DOUBLE_PAGE;
      settings.readingDirection = this.resolveLandscapeDoublePageDirection(this.readingSettings);
      settings.doublePagePortraitLayout = DoublePagePortraitLayout.HORIZONTAL;
      settings.pageTurnAnimation = this.normalizePageTurnAnimationForSettings(settings);
    }
    this.viewerReadingSettingsCacheKey = cacheKey;
    this.viewerReadingSettingsCache = settings;
    return settings;
  }

  private isEffectiveDoublePageMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE ||
      this.shouldUseLandscapeAutoDoublePage();
  }

  private getEffectiveDoublePageReadingDirection(): ReadingDirection {
    if (this.shouldUseLandscapeAutoDoublePage()) {
      return this.resolveLandscapeDoublePageDirection(this.readingSettings);
    }
    return this.readingSettings.readingDirection;
  }

  private syncAutoPageTurnStateFromSettings(updateController: boolean = false): void {
    const rawInterval = this.readingSettings.autoPageTurnInterval ?? 0;
    const interval = Math.max(0, Math.min(10, Math.round(rawInterval)));
    this.autoPageTurnEnabled = interval > 0;
    this.autoPageTurnIntervalSeconds = interval > 0 ? interval : Math.max(1, this.autoPageTurnIntervalSeconds);
    this.readingSettings.autoPageTurnInterval = interval;
    if (updateController) {
      this.updateAutoPageTurnConfig();
    }
  }

  private async persistReadingSettings(trigger: string): Promise<void> {
    const currentManga = this.readerState.currentManga;
    if (!currentManga) {
      return;
    }

    const mangaId = currentManga.id;
    const settingKey = `manga_settings_${mangaId}`;
    const snapshot = this.cloneReadingSettings(this.readingSettings);
    this.readingSettings = snapshot;
    currentManga.readingSettings = snapshot;
    AppStorage.setOrCreate(settingKey, JSON.stringify(snapshot));

    let savedAnySettings = false;
    try {
      await ComicConverter.saveReadingSettings(mangaId, snapshot);
      savedAnySettings = true;
      logger.info(TAG, `漫画阅读设置已持久化: key=${settingKey}, 触发源=${trigger}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存漫画阅读设置失败: 触发源=${trigger}, 错误=${errorMessage}`);
    }

    if (this.pageParams && this.isRemoteProviderContentType(this.pageParams.contentType)) {
      const didPersistRemoteProviderSettings = await this.persistRemoteProviderScopedReadingSettings(mangaId, snapshot, trigger);
      savedAnySettings = savedAnySettings || didPersistRemoteProviderSettings;
    }

    if (!savedAnySettings) {
      logger.warn(TAG, `阅读设置未成功持久化: mangaId=${mangaId}, trigger=${trigger}`);
    }
  }

  private async loadReadingSettings(): Promise<void> {
    logger.debug(TAG, '⚙️ 开始加载阅读设置');
    
    try {
      if (!this.readerState.currentManga) {
        logger.warn(TAG, '⚠️ 当前漫画为空，无法加载阅读设置');
        this.readingSettings = this.cloneReadingSettings(DEFAULT_READING_SETTINGS);
        this.syncDeviceOrientationLock('default_settings_no_manga');
        this.updateVolumeKeyListener();
        this.syncAutoPageTurnStateFromSettings();
        this.isReadingSettingsReady = true;
        logger.info(TAG, '📋 使用默认阅读设置，准备显示交互提示Overlay');
        if (!this.showInteractionOverlay) {
          this.showInteractionOverlay = true;
          this.showInteractionOverlayWithAnimation();
        }
        return;
      }

      const mangaId = this.readerState.currentManga.id;
      logger.debug(TAG, `加载漫画阅读设置: mangaId=${mangaId}`);

      // [修复] 始终从数据库加载最新设置，而不是依赖Manga对象上可能过时的设置
      // [修复] 始终从数据库加载最新设置，而不是依赖Manga对象上可能过时的设置
      // 原因：params.manga由详情页传入，可能在阅读器中修改设置后未同步回详情页的Manga对象
      const sourceIdStr = this.currentSourceId > 0 ? String(this.currentSourceId) : undefined;
      let settings: ReadingSettings;
      try {
        if (await this.hasPersistedPerMangaReadingSettings(mangaId)) {
          settings = await ComicConverter.loadReadingSettings(mangaId, 'default_user', sourceIdStr);
        } else {
          const remoteProviderScopedSettings = await this.loadRemoteProviderScopedReadingSettings(mangaId);
          if (remoteProviderScopedSettings !== null) {
            settings = remoteProviderScopedSettings;
          } else {
            settings = await ComicConverter.loadReadingSettings(mangaId, 'default_user', sourceIdStr);
          }
        }
        logger.info(TAG, `✅ 从数据库加载阅读设置成功: mode=${settings.readingMode}, direction=${settings.readingDirection}`);
      } catch (dbError) {
        const dbMsg = dbError instanceof Error ? dbError.message : String(dbError);
        logger.warn(TAG, `⚠️ 从数据库加载阅读设置失败: ${dbMsg}，回退使用Manga对象设置`);
        settings = this.readerState.currentManga.readingSettings;
      }
      
      logger.debug(TAG, `📖 最终使用的阅读设置:`);
      logger.debug(TAG, `📖 最终使用的阅读设置:`);
      logger.debug(TAG, `  - 阅读模式: ${settings.readingMode}`);
      logger.debug(TAG, `  - 阅读方向: ${settings.readingDirection}`);
      logger.debug(TAG, `  - 亮度: ${settings.brightness}`);
      
      // 应用设置
      const normalizedSettings = this.cloneReadingSettings(settings);
      this.readingSettings = normalizedSettings;
      this.syncDeviceOrientationLock('settings_loaded');
      // 应用设置
      this.readerState.currentManga.readingSettings = normalizedSettings;
      this.updateVolumeKeyListener();
      this.syncAutoPageTurnStateFromSettings();
      this.isReadingSettingsReady = true;
      
      logger.info(TAG, '✅ 阅读设置加载完成（来自数据库），准备显示交互提示Overlay');
      if (!this.showInteractionOverlay) {
        this.showInteractionOverlay = true;
        this.showInteractionOverlayWithAnimation();
      }
      logger.debug(TAG, `📋 最终阅读设置:`);
      logger.debug(TAG, `📋 最终阅读设置:`);
      logger.debug(TAG, `  - 阅读模式: ${this.readingSettings.readingMode}`);
      logger.debug(TAG, `  - 阅读方向: ${this.readingSettings.readingDirection}`);
      logger.debug(TAG, `  - 亮度: ${this.readingSettings.brightness}`);
      logger.debug(TAG, `  - 自动翻页间隔: ${this.readingSettings.autoPageTurnInterval}ms`);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: ReadingSettingsErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        mangaTitle: this.readerState.currentManga?.title,
        mangaId: this.readerState.currentManga?.id,
        hasReadingSettings: !!this.readerState.currentManga?.readingSettings,
        timestamp: new Date().toISOString()
      };
      
      logger.error(TAG, '❌ 加载阅读设置失败', errorMessage);
      logger.error(TAG, '❌ 加载阅读设置失败', errorMessage);
      this.readingSettings = this.cloneReadingSettings(DEFAULT_READING_SETTINGS);
      this.syncDeviceOrientationLock('default_settings_load_failed');
      this.updateVolumeKeyListener();
      this.syncAutoPageTurnStateFromSettings();
      this.isReadingSettingsReady = true;
      logger.info(TAG, '📋 回退到默认阅读设置，准备显示交互提示Overlay');
      if (!this.showInteractionOverlay) {
        this.showInteractionOverlay = true;
        this.showInteractionOverlayWithAnimation();
      }
    }
  }

  /**
   * 预加载图片
    */
  private preloadImages(): void {
    logger.info(TAG, '🖼️ 开始预加载图片');
    
    try {
      const currentChapter = this.readerState.currentChapter;
      if (!currentChapter) {
        logger.warn(TAG, '⚠️ 当前章节为空，无法预加载图片');
        return;
      }
      
      const totalPages = currentChapter.pages.length;
      const currentPageIndex = this.readerState.currentPageIndex;
      
      logger.debug(TAG, `📊 预加载计划:`);
      logger.debug(TAG, `📊 预加载计划:`);
      logger.debug(TAG, `  - 总页数: ${totalPages}`);
      
      // 预加载当前页面和相邻页面
      const isOnlineReader = this.isOnlineReaderContentType();
      const preloadRange = isOnlineReader ? 8 : 50;// 在线首屏缩小范围，降低初始化阶段压力
      const startIndex = Math.max(0, currentPageIndex - preloadRange);
      const endIndex = Math.min(totalPages - 1, currentPageIndex + preloadRange);
      
      logger.debug(TAG, `  - 预加载范围: ${startIndex + 1} - ${endIndex + 1}`);
      
      const logLimit = isOnlineReader ? 12 : 200;
      let loggedCount = 0;
      for (let i = startIndex; i <= endIndex; i++) {
        const page = currentChapter.pages[i];
        if (page && page.imageUrl) {
          if (loggedCount < logLimit) {
            logger.debug(TAG, `🖼️ 预加载页面 ${i + 1}: ${page.imageUrl}`);
            loggedCount++;
          }
        }
      }
      if ((endIndex - startIndex + 1) > loggedCount) {
        logger.debug(TAG, `Preload logging truncated: logged=${loggedCount}, total=${endIndex - startIndex + 1}`);
      }
      
      logger.info(TAG, `Queued pages for preload: ${endIndex - startIndex + 1}`);

      // 更新条漫模式相邻章节信息（用于无缝章节切换）
      this.updateAdjacentChaptersForWebtoon();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: PreloadErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        chapterTitle: this.readerState.currentChapter?.title,
        chapterId: this.readerState.currentChapter?.id,
        currentPageIndex: this.readerState.currentPageIndex,
        totalPages: this.readerState.currentChapter?.pages.length,
        timestamp: new Date().toISOString()
      };
      
      logger.error(TAG, '❌ 预加载图片失败', errorMessage);
      logger.error(TAG, '❌ 预加载图片失败', errorMessage);
    }
  }

  /**
   * 设置全屏阅读模式
    */
  private setupFullscreenMode(): void {
    try {
      // 使用WindowManager设置完全沉浸式模式
      const uiContext = this.getUIContext() ?? this.uiContext;
      if (!uiContext) {
        logger.error(TAG, '❌ 无法获取UIContext，设置全屏模式失败');
        return;
      }
      
      const currentMode = WindowManager.getCurrentMode();
      if (currentMode !== DisplayMode.FULL_IMMERSIVE) {
        this.previousDisplayMode = currentMode;
      }
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext);
      logger.info(TAG, '✅ 使用WindowManager设置完全沉浸式阅读模式');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: OperationErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        operation: 'setupFullscreenMode',
        timestamp: new Date().toISOString()
      };
      
      logger.error(TAG, '❌ 设置全屏阅读模式失败', errorMessage);
      logger.error(TAG, '❌ 设置全屏阅读模式失败', errorMessage);
    }
  }

  /**
   * 恢复正常模式
    */
  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer !== -1) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      if (!this.isPageVisible) {
        return;
      }
      const uiContext = this.getUIContext() ?? this.uiContext;
      logger.debug(TAG, `重新应用沉浸模式: 原因=${reason}`);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext ?? undefined);
      WindowManager.reapplyCurrentDisplayMode(24);
    }, delayMs);
  }

  private restoreNormalMode(): void {
    try {
      // 使用WindowManager恢复默认显示模式
      const uiContext = this.getUIContext() ?? this.uiContext;
      if (!uiContext) {
        logger.error(TAG, '❌ 无法获取UIContext，恢复正常模式失败');
        return;
      }
      
      const targetMode = this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE
        ? DisplayMode.DEFAULT
        : this.previousDisplayMode;
      if (WindowManager.getCurrentMode() === targetMode) {
        return;
      }
      WindowManager.setDisplayMode(targetMode, uiContext);
      logger.info(TAG, `✅ 使用WindowManager恢复显示模式: ${targetMode}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: OperationErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        operation: 'restoreNormalMode',
        timestamp: new Date().toISOString()
      };
      
      logger.error(TAG, '❌ 恢复正常模式失败', errorMessage);
      logger.error(TAG, '❌ 恢复正常模式失败', errorMessage);
    }
  }
  /**
   * 启动入场动画
   * 启动入场动画
    */
  private startEntranceAnimation(): void {
    this.isVisible = true;
    
    // 确保UIContext已设置
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      // 直接设置最终状态，跳过动画
      this.contentOpacity = 1;
      this.titleTranslateY = 0;
      // 仅在阅读设置已就绪时显示交互提示
      if (this.isReadingSettingsReady) {
        this.showInteractionOverlay = true;
        this.showInteractionOverlayWithAnimation();
      }
      return;
    }
    
    // 设置初始状态
    this.contentOpacity = 0;
    this.titleTranslateY = -20;
    
    // 使用animateTo执行淡入动画
    this.uiContext.animateTo({
      duration: 300,
      curve: Curve.EaseOut,
      onFinish: () => {
        // 入场动画完成后，仅在阅读设置已就绪时显示交互提示
        if (this.isReadingSettingsReady) {
          this.showInteractionOverlay = true;
          this.showInteractionOverlayWithAnimation();
        } else {
          logger.debug(TAG, '入场动画完成，但阅读设置尚未就绪，延迟显示Overlay');
        }
      }
    }, () => {
      this.contentOpacity = 1;
    });

    // 标题滑入动画
    this.uiContext.animateTo({
      duration: 400,
      curve: Curve.EaseOut
    }, () => {
      this.titleTranslateY = 0;
    });
    
    logger.debug(TAG, '入场动画已启动');
  }

  /**
   * 检查是否应该显示交互提示
   * 检查是否应该显示交互提示
   * 只在以下情况显示：
   * 1. 第一次进入阅读器（应用级别）
    */
  private shouldShowInteractionHint(): boolean {
    const currentMode = this.readingSettings.readingMode;
    
    // 情况1：第一次进入阅读器
    if (!MangaReaderPage.hasShownInteractionHint) {
      logger.info(TAG, '首次进入阅读器，显示交互提示');
      return true;
    }
    
    // 情况2：阅读模式发生变化
    if (MangaReaderPage.lastShownReadingMode !== null && MangaReaderPage.lastShownReadingMode !== currentMode) {
      logger.info(TAG, `Reading mode changed: ${MangaReaderPage.lastShownReadingMode} -> ${currentMode}`);
      return true;
    }
    
    logger.debug(TAG, '已显示过交互提示且阅读模式未变化，跳过显示');
    return false;
  }

  /**
   * 显示交互区域提示overlay
    */
  private showInteractionOverlayWithAnimation(): void {
    if (!this.showInteractionOverlay) {
      return;
    }
    
    // 检查是否应该显示提示
    if (!this.shouldShowInteractionHint()) {
      this.showInteractionOverlay = false;
      return;
    }
    
    // 记录当前阅读模式和已显示状态
    if (this.overlayDismissTimer !== -1) {
      clearTimeout(this.overlayDismissTimer);
      this.overlayDismissTimer = -1;
    }
    MangaReaderPage.lastShownReadingMode = this.readingSettings.readingMode;
    MangaReaderPage.hasShownInteractionHint = true;
    
    // 5秒后自动隐藏
    this.overlayDismissTimer = setTimeout(() => {
      this.hideInteractionOverlay();
    }, 5000);
    
    logger.info(TAG, `显示交互提示Overlay（模式: ${this.readingSettings.readingMode}），5秒后自动隐藏`);
  }

  /**
   * 隐藏交互区域提示overlay
    */
  private hideInteractionOverlay(): void {
    // 清除自动隐藏定时器
    if (this.overlayDismissTimer !== -1) {
      clearTimeout(this.overlayDismissTimer);
      this.overlayDismissTimer = -1;
    }
    
    this.showInteractionOverlay = false;
    logger.info(TAG, '隐藏交互提示Overlay');
  }

  /**
   * 处理页面点击
   * 处理页面点击
   * 简化版：移除双击检测，单击立即响应
    */
  private handlePageTap(event: ClickEvent): void {
    // 直接处理单击，无延迟
    this.handleSingleTap(event);
    // 直接处理单击，无延迟
    this.delayAutoPageTurnForInteraction();
  }

  /**
   * 显示工具栏动画
   * 显示工具栏动画
    */
  private showToolbarsWithAnimation(): void {
    // 先设置可见性，让组件渲染出来
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    
    if (this.uiContext) {
      // 使用animateTo执行淡入动画
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseOut
      }, () => {
        this.toolbarOpacity = 1.0;
        this.toolbarTranslateY = 0;
      });
    } else {
      // 无动画直接设置
      this.toolbarOpacity = 1.0;
      this.toolbarTranslateY = 0;
    }
    this.handleMenusVisibilityChange();
    logger.debug(TAG, '显示工具栏动画');
  }

  /**
   * 隐藏工具栏动画
   * 隐藏工具栏动画
    */
  private hideToolbarsWithAnimation(): void {
    if (this.uiContext) {
      // 使用animateTo执行淡出动画
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseIn,
        onFinish: () => {
          // 动画完成后隐藏组件
          this.showTopToolbar = false;
          this.showBottomToolbar = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.toolbarOpacity = 0.0;
      });
    } else {
      // 无动画直接设置
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
      this.toolbarOpacity = 0.0;
      this.handleMenusVisibilityChange();
    }
    logger.debug(TAG, '隐藏工具栏动画');
  }

  /**
   * 判断当前屏幕是否为横屏模式
    */
  private isLandscapeScreen(): boolean {
    return this.isLandscapeMode;
  }

  /**
   * 判断当前阅读模式是否支持卷页动画
   * 判断当前阅读模式是否支持卷页动画
   * 卷页动画支持：
   * - 单页模式 + 从左到右/从右到左阅读方向
    */
  private isCurlAnimationSupported(): boolean {
    const viewerSettings: ReadingSettings = this.getViewerReadingSettings();
    const mode = viewerSettings.readingMode;
    const direction = viewerSettings.readingDirection;
    
    // 单页从右到左模式
    if (mode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    
    // 单页模式 + 从左到右或从右到左方向
    if (mode === ReadingMode.SINGLE_PAGE) {
      return direction === ReadingDirection.LEFT_TO_RIGHT || 
             direction === ReadingDirection.RIGHT_TO_LEFT;
    }
    
    // 双页模式 + 横屏
    if (mode === ReadingMode.DOUBLE_PAGE && this.isLandscapeScreen()) {
      if (this.shouldUseSmartDoublePageLayout()) {
        return false;
      }
      return true;
    }
    
    return false;
  }

  private getDoublePageVerticalDirection(): DoublePageVerticalDirection {
    return this.readingSettings.doublePageVerticalDirection ?? DEFAULT_READING_SETTINGS.doublePageVerticalDirection ??
      DoublePageVerticalDirection.TOP_TO_BOTTOM;
  }

  private getChapterPageCount(chapter: MangaChapter): number {
    if (chapter.pages && chapter.pages.length > 0) {
      return chapter.pages.length;
    }
    if (chapter.totalPages && chapter.totalPages > 0) {
      return chapter.totalPages;
    }
    return 0;
  }

  private clampPageIndexForChapter(chapter: MangaChapter, pageIndex: number): number {
    const pageCount: number = this.getChapterPageCount(chapter);
    const safeInteger: number = Number.isFinite(pageIndex) ? Math.max(0, Math.floor(pageIndex)) : 0;
    if (pageCount <= 0) {
      return safeInteger;
    }
    return Math.max(0, Math.min(safeInteger, pageCount - 1));
  }

  private normalizeReaderPageIndexForChapter(chapter: MangaChapter, pageIndex: number): number {
    const safeIndex: number = this.clampPageIndexForChapter(chapter, pageIndex);
    if (this.isDoublePageVerticalPortraitMode()) {
      return safeIndex - (safeIndex % 2);
    }
    if (this.isEffectiveDoublePageMode()) {
      if (chapter.pages && chapter.pages.length > 0 && this.shouldUseSmartDoublePageLayout()) {
        const isRtl: boolean = this.getEffectiveDoublePageReadingDirection() === ReadingDirection.RIGHT_TO_LEFT;
        const plan: DoublePageSmartDisplayPlan = DoublePageSmartLayoutHelper.resolvePlanAtIndex(
          chapter.pages,
          safeIndex,
          isRtl,
          (targetPageIndex: number): PageDimensionsInfo | null => {
            if (targetPageIndex < 0 || targetPageIndex >= chapter.pages.length) {
              return null;
            }
            return DoublePageSmartLayoutHelper.resolvePageDimensionsFromMetadata(chapter.pages[targetPageIndex]);
          }
        );
        if (plan.startIndex >= 0) {
          return plan.startIndex;
        }
      }
      return safeIndex - (safeIndex % 2);
    }
    return safeIndex;
  }

  private getVerticalDoublePageChapterEntryIndex(chapter: MangaChapter, direction: 'prev' | 'next'): number {
    const pageCount: number = this.getChapterPageCount(chapter);
    if (pageCount <= 0) {
      return 0;
    }
    if (direction === 'next') {
      return 0;
    }
    const maxIndex: number = pageCount - 1;
    return maxIndex - (maxIndex % 2);
  }

  private getChapterBoundaryEntryIndex(chapter: MangaChapter, direction: 'prev' | 'next'): number {
    const pageCount: number = this.getChapterPageCount(chapter);
    if (pageCount <= 0) {
      return 0;
    }
    if (direction === 'next') {
      return 0;
    }
    const maxIndex: number = pageCount - 1;
    return this.normalizeReaderPageIndexForChapter(chapter, maxIndex);
  }

  private shouldUseBoundaryEntryForChapterSwitch(): boolean {
    return this.isEffectiveDoublePageMode();
  }

  private async resolveChapterSwitchTargetPageIndex(
    mangaId: string,
    chapter: MangaChapter,
    direction: 'prev' | 'next'
  ): Promise<number> {
    if (this.shouldUseBoundaryEntryForChapterSwitch()) {
      const boundaryIndex: number = this.getChapterBoundaryEntryIndex(chapter, direction);
      logger.info(TAG, `双页边界跨章定位: direction=${direction}, chapter=${chapter.title}, page=${boundaryIndex + 1}`);
      return boundaryIndex;
    }

    const pageCount: number = this.getChapterPageCount(chapter);
    let targetPageIndex: number = direction === 'prev' ? Math.max(0, pageCount - 1) : 0;
    try {
      const progress = await this.dataService.getReadingProgress(mangaId, chapter.id);
      if (progress && progress.pageIndex >= 0 && progress.pageIndex < pageCount) {
        targetPageIndex = progress.pageIndex;
        logger.info(TAG, `✅ 找到${direction === 'prev' ? '上一' : '下一'}章节阅读记录: ${chapter.title}, 页码=${targetPageIndex + 1}`);
      } else {
        logger.info(TAG, `✅ 使用${direction === 'prev' ? '上一章节默认末页' : '下一章节默认首页'}: ${chapter.title}, 页码=${targetPageIndex + 1}`);
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `获取${direction === 'prev' ? '上一' : '下一'}章节阅读记录失败，使用边界页: ${errorMsg}`);
    }
    return targetPageIndex;
  }

  private setChapterSwitchPageGuard(chapter: MangaChapter, pageIndex: number, direction: 'prev' | 'next'): void {
    const normalizedPageIndex: number = this.normalizeReaderPageIndexForChapter(chapter, pageIndex);
    this.isReaderInitialized = false;
    this.chapterSwitchPageGuard = {
      chapterId: chapter.id,
      pageIndex: normalizedPageIndex,
      direction: direction,
      expiresAt: Date.now() + MangaReaderPage.CHAPTER_SWITCH_PAGE_GUARD_MS
    };
    logger.debug(TAG, `跨章页码守门已设置: chapter=${chapter.title}, direction=${direction}, target=${normalizedPageIndex + 1}`);
  }

  private getActiveChapterSwitchPageGuard(chapter: MangaChapter | null): ChapterSwitchPageGuard | null {
    if (!this.chapterSwitchPageGuard) {
      return null;
    }
    if (Date.now() > this.chapterSwitchPageGuard.expiresAt) {
      logger.debug(TAG, `跨章页码守门已过期: chapterId=${this.chapterSwitchPageGuard.chapterId}`);
      this.chapterSwitchPageGuard = null;
      return null;
    }
    if (chapter && this.chapterSwitchPageGuard.chapterId !== chapter.id) {
      return null;
    }
    return this.chapterSwitchPageGuard;
  }

  private clearChapterSwitchPageGuard(reason: string): void {
    if (!this.chapterSwitchPageGuard) {
      return;
    }
    logger.debug(TAG, `跨章页码守门已清除: reason=${reason}, chapterId=${this.chapterSwitchPageGuard.chapterId}, target=${this.chapterSwitchPageGuard.pageIndex + 1}`);
    this.chapterSwitchPageGuard = null;
  }

  private shouldAcceptPageChangeDuringChapterSwitch(pageIndex: number): boolean {
    const chapter = this.readerState.currentChapter;
    if (!chapter) {
      return true;
    }
    const guard: ChapterSwitchPageGuard | null = this.getActiveChapterSwitchPageGuard(chapter);
    if (!guard) {
      return true;
    }
    const normalizedPageIndex: number = this.normalizeReaderPageIndexForChapter(chapter, pageIndex);
    if (normalizedPageIndex === guard.pageIndex) {
      this.clearChapterSwitchPageGuard('matched_page_change');
      return true;
    }
    logger.debug(TAG, `忽略跨章期间不匹配的页码回调: incoming=${pageIndex + 1}, normalized=${normalizedPageIndex + 1}, expected=${guard.pageIndex + 1}, direction=${guard.direction}`);
    return false;
  }

  private scheduleChapterSwitchReaderReady(chapter: MangaChapter, pageIndex: number, reason: string): void {
    const expectedIndex: number = this.normalizeReaderPageIndexForChapter(chapter, pageIndex);
    setTimeout(() => {
      const currentChapter = this.readerState.currentChapter;
      if (!currentChapter || currentChapter.id !== chapter.id) {
        logger.debug(TAG, `跨章阅读器就绪检查跳过: reason=${reason}, 当前章节已变化`);
        return;
      }
      const guard: ChapterSwitchPageGuard | null = this.getActiveChapterSwitchPageGuard(currentChapter);
      const finalExpectedIndex: number = guard ? guard.pageIndex : expectedIndex;
      if (this.mangaViewerComponent) {
        const viewerPageIndex: number = this.mangaViewerComponent.getCurrentViewPageIndex();
        const normalizedViewerIndex: number = this.normalizeReaderPageIndexForChapter(currentChapter, viewerPageIndex);
        if (normalizedViewerIndex !== finalExpectedIndex) {
          logger.info(TAG, `跨章后校正阅读组件页组: viewer=${viewerPageIndex + 1}, normalized=${normalizedViewerIndex + 1}, expected=${finalExpectedIndex + 1}, reason=${reason}`);
          this.mangaViewerComponent.setPageIndex(finalExpectedIndex);
          if (this.isDoublePageVerticalPortraitMode()) {
            this.mangaViewerComponent.syncVerticalDoublePageToPageIndex(finalExpectedIndex, reason);
          }
        }
      }
      this.syncReaderPageState(finalExpectedIndex);
      this.isReaderInitialized = true;
      this.clearChapterSwitchPageGuard(reason);
      logger.info(TAG, `跨章阅读器页码同步完成: chapter=${currentChapter.title}, page=${finalExpectedIndex + 1}, reason=${reason}`);
    }, 500);
  }

  private isDoublePageVerticalPortraitMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL &&
      !this.isLandscapeScreen();
  }

  private isDoublePageVerticalAnimationLockedForSettings(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL;
  }

  private normalizePageTurnAnimationForMode(
    animationType: PageTurnAnimationType,
    mode: ReadingMode,
    doublePagePortraitLayout: DoublePagePortraitLayout
  ): PageTurnAnimationType {
    if (mode === ReadingMode.DOUBLE_PAGE && doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      return PageTurnAnimationType.SLIDE;
    }
    return animationType;
  }

  private normalizePageTurnAnimationForSettings(settings: ReadingSettings): PageTurnAnimationType {
    return this.normalizePageTurnAnimationForMode(
      settings.pageTurnAnimation,
      settings.readingMode,
      settings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
  }

  private isDoublePageVerticalNextAtTop(): boolean {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP;
  }

  private shouldUseSmartDoublePageLayout(): boolean {
    return this.isEffectiveDoublePageMode() &&
      !this.isDoublePageVerticalPortraitMode();
  }

  private getDoublePageSmartDimensions(pageIndex: number): PageDimensionsInfo | null {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || pageIndex < 0 || pageIndex >= currentChapter.pages.length) {
      return null;
    }
    return DoublePageSmartLayoutHelper.resolvePageDimensionsFromMetadata(currentChapter.pages[pageIndex]);
  }

  private resolveCurrentDoublePageDisplayPlan(): DoublePageSmartDisplayPlan {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || currentChapter.pages.length === 0) {
      return {
        startIndex: -1,
        endIndex: -1,
        leftPageIndex: -1,
        rightPageIndex: -1,
        pageCount: 0,
        mode: DoublePageSmartDisplayMode.DUAL,
        reason: DoublePageSmartDisplayReason.NORMAL_PAIR
      } as DoublePageSmartDisplayPlan;
    }
    const isRtl: boolean = this.getEffectiveDoublePageReadingDirection() === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolvePlanAtIndex(
      currentChapter.pages,
      this.readerState.currentPageIndex,
      isRtl,
      (pageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(pageIndex)
    );
  }

  private resolvePreviousDoublePageDisplayPlan(): DoublePageSmartDisplayPlan {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || currentChapter.pages.length === 0) {
      return {
        startIndex: -1,
        endIndex: -1,
        leftPageIndex: -1,
        rightPageIndex: -1,
        pageCount: 0,
        mode: DoublePageSmartDisplayMode.DUAL,
        reason: DoublePageSmartDisplayReason.NORMAL_PAIR
      } as DoublePageSmartDisplayPlan;
    }
    const isRtl: boolean = this.getEffectiveDoublePageReadingDirection() === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolvePreviousPlan(
      currentChapter.pages,
      this.readerState.currentPageIndex,
      isRtl,
      (pageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(pageIndex)
    );
  }

  private resolveNextDoublePageDisplayPlan(): DoublePageSmartDisplayPlan {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || currentChapter.pages.length === 0) {
      return {
        startIndex: -1,
        endIndex: -1,
        leftPageIndex: -1,
        rightPageIndex: -1,
        pageCount: 0,
        mode: DoublePageSmartDisplayMode.DUAL,
        reason: DoublePageSmartDisplayReason.NORMAL_PAIR
      } as DoublePageSmartDisplayPlan;
    }
    const isRtl: boolean = this.getEffectiveDoublePageReadingDirection() === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolveNextPlan(
      currentChapter.pages,
      this.readerState.currentPageIndex,
      isRtl,
      (pageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(pageIndex)
    );
  }

  private getCurrentDoublePagePairStart(): number {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || currentChapter.pages.length === 0) {
      return 0;
    }
    if (this.shouldUseSmartDoublePageLayout()) {
      return this.resolveCurrentDoublePageDisplayPlan().startIndex;
    }
    const maxIndex = currentChapter.pages.length - 1;
    const currentIndex = Math.min(Math.max(0, this.readerState.currentPageIndex), maxIndex);
    return currentIndex - (currentIndex % 2);
  }

  private getPreviousDoublePagePairStart(): number {
    if (this.shouldUseSmartDoublePageLayout()) {
      return this.resolvePreviousDoublePageDisplayPlan().startIndex;
    }
    const pairStart = this.getCurrentDoublePagePairStart();
    return pairStart > 0 ? Math.max(pairStart - 2, 0) : -1;
  }

  private getNextDoublePagePairStart(): number {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || !currentChapter.pages || currentChapter.pages.length === 0) {
      return -1;
    }
    if (this.shouldUseSmartDoublePageLayout()) {
      return this.resolveNextDoublePageDisplayPlan().startIndex;
    }
    const pairStart = this.getCurrentDoublePagePairStart();
    const maxIndex = currentChapter.pages.length - 1;
    const nextPairStart = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    return nextPairStart > pairStart ? nextPairStart : -1;
  }

  /**
   * 处理设置变更
    */
  private handleSettingsChange(settings: ReadingSettings): void {
    const normalizedSettings: ReadingSettings = this.cloneReadingSettings(settings);
    normalizedSettings.pageTurnAnimation = this.normalizePageTurnAnimationForSettings(normalizedSettings);
    logger.info(TAG, `阅读设置已更新: pageTurnAnimation=${normalizedSettings.pageTurnAnimation}, brightness=${normalizedSettings.brightness}`);
    
    // 检查阅读模式是否变更
    const readingModeChanged = this.readingSettings.readingMode !== normalizedSettings.readingMode;
    // 检查阅读模式是否变更
    const keepScreenOnChanged = this.readingSettings.keepScreenOn !== normalizedSettings.keepScreenOn;
    // 检查屏幕常亮设置是否变更
    const brightnessChanged = Math.abs(this.readingSettings.brightness - normalizedSettings.brightness) > 0.01;
    // 检查亮度设置是否变更（在更新前检测，使用容差比较浮点数）
    const volumeKeyChanged = this.readingSettings.volumeKeyNavigation !== normalizedSettings.volumeKeyNavigation;
    
    // 如果阅读模式变更，显示交互提示
    if (readingModeChanged) {
      logger.info(TAG, `阅读模式变更: ${this.readingSettings.readingMode} -> ${normalizedSettings.readingMode}，将显示交互提示`);
    }
    
    // 保存设置到数据库和AppStorage（针对当前漫画）
    const snapshot = this.cloneReadingSettings(normalizedSettings);
    if (this.readerState.currentManga) {
      const mangaId = this.readerState.currentManga.id;
      const settingsJson = JSON.stringify(snapshot);
      
      // 保存到数据库
      ComicConverter.saveReadingSettings(mangaId, snapshot).then(() => {
        logger.info(TAG, `✅ 阅读设置已保存到数据库: manga_settings_${mangaId}`);
      }).catch((error: Error) => {
        logger.error(TAG, `❌ 保存阅读设置到数据库失败: ${error.message}`);
      });
      
      // 同时保存到AppStorage作为缓存
      AppStorage.setOrCreate(`manga_settings_${mangaId}`, settingsJson);
      logger.info(TAG, `已保存漫画独立设置到AppStorage: manga_settings_${mangaId}`);
      
      // 更新Manga对象的阅读设置
      this.readerState.currentManga.readingSettings = snapshot;
    }
    
    // 立即更新当前阅读设置
    this.readingSettings = snapshot;
    this.syncDeviceOrientationLock('settings_change');
    void this.persistReadingSettings('handle_settings_change');

    // 如果屏幕常亮设置变更，立即应用
    if (keepScreenOnChanged) {
      this.applyKeepScreenOnSetting();
    }
    
    // 亮度设置已移除，不再处理亮度变更
    
    // 亮度设置已移除，不再处理亮度变更
    if (volumeKeyChanged) {
      logger.info(TAG, `音量键翻页设置变更: ${normalizedSettings.volumeKeyNavigation}`);
      this.updateVolumeKeyListener();
    }
    
    // 更新自动翻页配置
    this.syncAutoPageTurnStateFromSettings(true);
    
    // 如果阅读模式变更，显示交互提示
    if (readingModeChanged) {
      this.showInteractionOverlay = true;
      this.showInteractionOverlayWithAnimation();
    }

    // 注意：不要在设置变更时自动启动/停止自动翻页
    // 注意：不要在设置变更时自动启动/停止自动翻页
    // 自动翻页的启用/停止应该由用户通过自动翻页设置面板明确控制
    if (this.autoPageTurnController && this.readingSettings.autoPageTurnInterval === 0) {
      const currentState: AutoPageTurnState = this.autoPageTurnController.getState();
      if (currentState !== AutoPageTurnState.STOPPED) {
        this.autoPageTurnController.stop();
        this.autoPageTurnState = AutoPageTurnState.STOPPED;
        this.autoPageTurnEnabled = false;
        logger.info(TAG, '设置变更触发：自动翻页间隔为0，已停止');
      }
    }
    
    logger.debug(TAG, '阅读设置应用完成');
  }
  
  /**
   * 显示快速设置面板
   * 显示快速设置面板
    */
  private showQuickSettingsWithAnimation(): void {
    // 关闭其他面板
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.handleMenusVisibilityChange();
    
    // 重置动画初始状态
    this.quickSettingsOpacity = 0;
    this.quickSettingsScale = 0.95;
    this.quickSettingsTranslateY = 20;
    
    // 显示快速设置
    this.showQuickSettings = true;
    this.handleMenusVisibilityChange();
    
    // 执行入场动画
    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.quickSettingsOpacity = 1;
          this.quickSettingsScale = 1;
          this.quickSettingsTranslateY = 0;
        });
      }, 0);
    } else {
      this.quickSettingsOpacity = 1;
      this.quickSettingsScale = 1;
      this.quickSettingsTranslateY = 0;
    }
    logger.info(TAG, '显示快速设置面板');
  }
  
  /**
   * 隐藏快速设置面板
   * 隐藏快速设置面板
    */
  private hideQuickSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 160,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showQuickSettings = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.quickSettingsOpacity = 0;
        this.quickSettingsScale = 0.95;
        this.quickSettingsTranslateY = 20;
      });
    } else {
      this.quickSettingsOpacity = 0;
      this.quickSettingsScale = 0.95;
      this.quickSettingsTranslateY = 20;
      this.showQuickSettings = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '隐藏快速设置面板');
  }

  /**
   * 设置面板显示动画
   * 设置面板显示动画
    */
  private showSettingsPanelWithAnimation(): void {
    // 打开阅读设置前，关闭其他面板
    this.showQuickSettings = false;
    this.showMoreMenu = false;
    this.showChapterList = false;
    this.handleMenusVisibilityChange();
    
    // 重置动画初始状态
    this.settingsPanelOpacity = 0;
    this.settingsPanelScale = 0.95;
    this.settingsPanelTranslateY = 20;
    
    // 显示设置面板
    this.showSettingsPanel = true;
    this.handleMenusVisibilityChange();
    
    // 执行入场动画
    if (this.uiContext) {
      setTimeout(() => {
        this.uiContext!.animateTo({
          duration: 250,
          curve: Curve.EaseOut
        }, () => {
          this.settingsPanelOpacity = 1;
          this.settingsPanelScale = 1;
          this.settingsPanelTranslateY = 0;
        });
      }, 0);
    } else {
      this.settingsPanelOpacity = 1;
      this.settingsPanelScale = 1;
      this.settingsPanelTranslateY = 0;
    }
    logger.info(TAG, '显示完整设置面板');
  }

  /**
   * 设置面板隐藏动画
   * 设置面板隐藏动画
    */
  private hideSettingsPanelWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showSettingsPanel = false;
          this.handleMenusVisibilityChange();
        }
      }, () => {
        this.settingsPanelOpacity = 0;
        this.settingsPanelScale = 0.95;
        this.settingsPanelTranslateY = 20;
      });
    } else {
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.95;
      this.settingsPanelTranslateY = 20;
      this.showSettingsPanel = false;
      this.handleMenusVisibilityChange();
    }
    logger.info(TAG, '设置面板已关闭');
  }

  /**
   * 显示“更多选项”菜单
    */
  private showMoreMenuWithAnimation(): void {
    // 打开“更多”菜单前，关闭阅读设置面板避免重叠
    if (this.showSettingsPanel) {
      this.showSettingsPanel = false;
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.8;
      this.settingsPanelTranslateY = 50;
      this.handleMenusVisibilityChange();
    }
    this.showMoreMenu = true;
    this.handleMenusVisibilityChange();
    if (this.uiContext) {
      setTimeout(() => {
        const animateOptions: AnimationConfig = { duration: 200, curve: Curve.EaseOut };
        this.uiContext!.animateTo(animateOptions, () => {
          this.moreMenuOpacity = 1;
          this.moreMenuScale = 1;
          this.moreMenuTranslateY = 0;
        });
      }, 0);
    } else {
      this.moreMenuOpacity = 1;
      this.moreMenuScale = 1;
      this.moreMenuTranslateY = 0;
    }
  }

  /**
   * 隐藏“更多选项”菜单
    */
  private hideMoreMenuWithAnimation(): void {
    if (this.uiContext) {
      const animateOptions: AnimationConfig = { duration: 160, curve: Curve.EaseIn };
      this.uiContext.animateTo(animateOptions, () => {
        this.moreMenuOpacity = 0;
        this.moreMenuScale = 0.95;
        this.moreMenuTranslateY = -10;
      });
      setTimeout(() => {
        this.showMoreMenu = false;
      }, 160);
    } else {
      this.moreMenuOpacity = 0;
      this.moreMenuScale = 0.95;
      this.moreMenuTranslateY = -10;
      this.showMoreMenu = false;
    }
  }

  /**
   * 显示翻页动画设置面板
    */
  private showPageTurnAnimationSettingsWithAnimation(): void {
    // 关闭其他面板
    this.showSettingsPanel = false;
    this.showMoreMenu = false;
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.handleMenusVisibilityChange();
    
    this.pageTurnAnimationSettingsTranslateX = 320;
    this.showPageTurnAnimationSettings = true;
    this.handleMenusVisibilityChange();
    if (this.uiContext) {
      setTimeout(() => {
        const animateOptions: AnimationConfig = { duration: 250, curve: Curve.EaseOut };
        this.uiContext!.animateTo(animateOptions, () => {
          this.pageTurnAnimationSettingsOpacity = 1;
          this.pageTurnAnimationSettingsScale = 1;
          this.pageTurnAnimationSettingsTranslateY = 0;
          this.pageTurnAnimationSettingsTranslateX = 0;
        });
      }, 0);
    } else {
      this.pageTurnAnimationSettingsOpacity = 1;
      this.pageTurnAnimationSettingsScale = 1;
      this.pageTurnAnimationSettingsTranslateY = 0;
      this.pageTurnAnimationSettingsTranslateX = 0;
    }
  }

  /**
   * 注册音量键监听（使用inputConsumer API拦截系统音量调节）
   * 注册音量键监听（使用inputConsumer API拦截系统音量调节）
    */
  private registerVolumeKeyListener(): void {
    if (this.isVolumeKeyListenerRegistered) {
      logger.debug(TAG, '音量键监听已注册，跳过');
      return;
    }
    
    if (!this.readingSettings.volumeKeyNavigation) {
      logger.debug(TAG, '音量键翻页未启用，不注册监听');
      return;
    }
    
    try {
      // 音量上键配置
      const volumeUpConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_UP,
        action: 1,// 按下按键的行为
        isRepeat: false// 优先消费掉按键事件，不上报给系统
      };
      
      // 音量下键配置
      const volumeDownConfig: inputConsumer.KeyPressedConfig = {
        key: KeyCode.KEYCODE_VOLUME_DOWN,
        action: 1,
        isRepeat: false
      };
      
      // 音量上键回调
      this.volumeUpCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 上一页 (inputConsumer)');
        if (!this.areMenusVisible()) {
          this.goToPreviousPage();
        }
      };
      
      // 音量下键回调
      this.volumeDownCallback = (event: InputKeyEvent) => {
        logger.info(TAG, '音量键翻页: 下一页 (inputConsumer)');
        if (!this.areMenusVisible()) {
          this.goToNextPage();
        }
      };
      
      // 注册监听
      inputConsumer.on('keyPressed', volumeUpConfig, this.volumeUpCallback);
      inputConsumer.on('keyPressed', volumeDownConfig, this.volumeDownCallback);
      
      this.isVolumeKeyListenerRegistered = true;
      logger.info(TAG, '✅ 音量键翻页监听已注册');
    } catch (error) {
      logger.error(TAG, `注册音量键监听失败: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 注销音量键监听
    */
  private unregisterVolumeKeyListener(): void {
    if (!this.isVolumeKeyListenerRegistered) {
      return;
    }
    
    try {
      if (this.volumeUpCallback) {
        inputConsumer.off('keyPressed', this.volumeUpCallback);
        this.volumeUpCallback = null;
      }
      if (this.volumeDownCallback) {
        inputConsumer.off('keyPressed', this.volumeDownCallback);
        this.volumeDownCallback = null;
      }
      
      this.isVolumeKeyListenerRegistered = false;
      logger.info(TAG, '✅ 音量键翻页监听已注销');
    } catch (error) {
      logger.error(TAG, `注销音量键监听失败: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 更新音量键监听状态（根据设置启用/禁用）
    */
  private updateVolumeKeyListener(): void {
    if (this.readingSettings.volumeKeyNavigation) {
      this.registerVolumeKeyListener();
    } else {
      this.unregisterVolumeKeyListener();
    }
  }

  /**
   * 处理音量键翻页（备用方法，用于onKeyEvent）
   * 处理音量键翻页（备用方法，用于onKeyEvent）
   * @param keyCode 按键码
    */
  private handleVolumeKeyPageTurn(keyCode: number): boolean {
    logger.debug(TAG, `按键事件: keyCode=${keyCode}, volumeKeyNavigation=${this.readingSettings.volumeKeyNavigation}`);
    
    // 检查是否启用音量键翻页
    if (!this.readingSettings.volumeKeyNavigation) {
      logger.debug(TAG, '音量键翻页未启用');
      return false;
    }
    
    // 如果有菜单打开，不处理翻页
    if (this.areMenusVisible()) {
      logger.debug(TAG, '菜单可见，不处理音量键翻页');
      return false;
    }
    
    // KeyCode.KEYCODE_VOLUME_UP = 16, KeyCode.KEYCODE_VOLUME_DOWN = 17
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP || keyCode === 16) {
    // KeyCode.KEYCODE_VOLUME_UP = 16, KeyCode.KEYCODE_VOLUME_DOWN = 17
      logger.info(TAG, '音量键翻页: 上一页');
      this.goToPreviousPageByVolumeKey();
      return true;
    } else if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN || keyCode === 17) {
      // 音量下键 - 下一页
      logger.info(TAG, '音量键翻页: 下一页');
      this.goToNextPageByVolumeKey();
      return true;
    }
    
    return false;
  }

  private getEffectivePageIndexForVolumeKey(): number {
    const currentChapter = this.readerState.currentChapter;
    let pageIndex = this.readerState.currentPageIndex;
    if (!currentChapter) {
      return pageIndex;
    }

    if (this.mangaViewerComponent) {
      const viewerPageIndex = this.mangaViewerComponent.getCurrentViewPageIndex();
      if (viewerPageIndex >= 0 && viewerPageIndex < currentChapter.pages.length && viewerPageIndex !== pageIndex) {
        logger.debug(TAG, `音量键翻页页码同步: state=${pageIndex}, viewer=${viewerPageIndex}`);
        pageIndex = viewerPageIndex;
      }
    }

    return pageIndex;
  }

  private goToPreviousPageByVolumeKey(): void {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || currentChapter.pages.length === 0) {
      return;
    }

    const effectivePageIndex = this.getEffectivePageIndexForVolumeKey();
    if (effectivePageIndex !== this.readerState.currentPageIndex) {
      this.readerState.currentPageIndex = effectivePageIndex;
    }

    if (effectivePageIndex <= 0) {
      this.saveReadingProgressInternal('beforePrevChapterFromVolumeKey').then(() => {
        this.goToPreviousChapter();
      }).catch((error: Error) => {
        logger.error(TAG, '切到上一章节前保存进度失败', error.message);
        this.goToPreviousChapter();
      });
      return;
    }

    this.goToPreviousPage();
  }

  private goToNextPageByVolumeKey(): void {
    const currentChapter = this.readerState.currentChapter;
    if (!currentChapter || currentChapter.pages.length === 0) {
      return;
    }

    const effectivePageIndex = this.getEffectivePageIndexForVolumeKey();
    if (effectivePageIndex !== this.readerState.currentPageIndex) {
      this.readerState.currentPageIndex = effectivePageIndex;
    }

    if (effectivePageIndex >= currentChapter.pages.length - 1) {
      this.saveReadingProgressInternal('beforeNextChapterFromVolumeKey').then(() => {
        this.goToNextChapter();
      }).catch((error: Error) => {
        logger.error(TAG, '切到下一章节前保存进度失败', error.message);
        this.goToNextChapter();
      });
      return;
    }

    this.goToNextPage();
  }

  /**
   * 隐藏翻页动画设置面板
    */
  private hidePageTurnAnimationSettingsWithAnimation(): void {
    if (this.uiContext) {
      const animateOptions: AnimationConfig = { duration: 200, curve: Curve.EaseIn };
      this.uiContext.animateTo(animateOptions, () => {
        this.pageTurnAnimationSettingsOpacity = 0;
        this.pageTurnAnimationSettingsScale = 0.95;
        this.pageTurnAnimationSettingsTranslateY = 20;
        this.pageTurnAnimationSettingsTranslateX = 320;
      });
      setTimeout(() => {
        this.showPageTurnAnimationSettings = false;
      }, 200);
    } else {
      this.pageTurnAnimationSettingsOpacity = 0;
      this.pageTurnAnimationSettingsScale = 0.95;
      this.pageTurnAnimationSettingsTranslateY = 20;
      this.pageTurnAnimationSettingsTranslateX = 320;
      this.showPageTurnAnimationSettings = false;
    }
  }

  /**
   * 显示跳转页面对话框（带动画）
    */
  private showJumpToPageDialogWithAnimation(): void {
    this.showJumpToPageDialog = true;
    this.jumpToPageInput = '';
    this.jumpToPageDialogOpacity = 0;
    this.jumpToPageDialogScale = 0.9;
    
    if (this.uiContext) {
      setTimeout(() => {
        const animateOptions: AnimationConfig = { duration: 200, curve: Curve.EaseOut };
        this.uiContext!.animateTo(animateOptions, () => {
          this.jumpToPageDialogOpacity = 1;
          this.jumpToPageDialogScale = 1;
        });
      }, 0);
    } else {
      this.jumpToPageDialogOpacity = 1;
      this.jumpToPageDialogScale = 1;
    }
  }

  /**
   * 隐藏跳转页面对话框（带动画）
    */
  private hideJumpToPageDialogWithAnimation(): void {
    if (this.uiContext) {
      const animateOptions: AnimationConfig = { duration: 150, curve: Curve.EaseIn };
      this.uiContext.animateTo(animateOptions, () => {
        this.jumpToPageDialogOpacity = 0;
        this.jumpToPageDialogScale = 0.9;
      });
      setTimeout(() => {
        this.showJumpToPageDialog = false;
        this.jumpToPageInput = '';
      }, 150);
    } else {
      this.showJumpToPageDialog = false;
      this.jumpToPageInput = '';
    }
  }

  /**
   * 跳转到指定页面
    */
  private jumpToPage(pageNumber: number): void {
    const totalPages = this.readerState.currentChapter?.pages.length || 0;
    if (pageNumber >= 1 && pageNumber <= totalPages) {
      const targetIndex = pageNumber - 1;
      logger.info(TAG, `跳转到页面: ${pageNumber}/${totalPages}`);
      this.syncReaderPageState(targetIndex);
      if (this.isScrollableReaderMode() && this.mangaViewerComponent?.smoothScrollToPage) {
        this.mangaViewerComponent.smoothScrollToPage(targetIndex, 1.0);
      } else if (this.isDoublePageVerticalPortraitMode() && this.mangaViewerComponent) {
        this.mangaViewerComponent.syncVerticalDoublePageToPageIndex(targetIndex, 'jump_to_page');
      }
      this.hideJumpToPageDialogWithAnimation();
      // 保存进度
      this.saveReadingProgressInternal('jumpToPage').catch((error: Error) => {
        logger.error(TAG, '跳转页面后保存进度失败', error.message);
      });
    } else {
      logger.warn(TAG, `无效的页码: ${pageNumber}, 总页数: ${totalPages}`);
    }
  }

  /**
   * 页面切换动画
    */
  private animatePageTransition(direction: 'next' | 'previous'): void {
    if (this.isDoublePageVerticalPortraitMode()) {
      logger.debug(TAG, `双页竖向模式由 MangaViewer 接管翻页动画，跳过父级动画: ${direction}`);
      return;
    }
    if (!this.uiContext) return;
    const isVertical: boolean = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM ||
      this.isDoublePageVerticalPortraitMode();
    const animationType: AnimationType = isVertical ? AnimationType.FLIP_IN_X : AnimationType.FLIP_IN_Y;

    this.animationManager.animate(
      animationType,
      (state: AnimationState) => {
        logger.debug(TAG, `页面切换动画状态: ${JSON.stringify(state)}`);
      },
      { duration: 280, easing: AnimationEasing.EASE_IN_OUT, type: animationType },
      this.uiContext
    );
  }

  /**
   * 保存当前页面到图库
   */
  private async saveCurrentPageToGallery(): Promise<void> {
    try {
      const chapter = this.readerState.currentChapter;
      const pageIndex = this.readerState.currentPageIndex;
      
      if (!chapter || !chapter.pages || pageIndex < 0 || pageIndex >= chapter.pages.length) {
        logger.error(TAG, '无法保存：当前页面无效');
        AlertDialog.show({ message: '无法保存：当前页面无效' });
        return;
      }
      
      const currentPage = chapter.pages[pageIndex];
      let imagePath = currentPage.imagePath;
      
      // 如果是网络图片，需要先下载到沙箱
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        logger.info(TAG, `保存网络图片到图库: ${imagePath}`);
        AlertDialog.show({ message: '暂不支持直接保存网络图片，请先缓存到本地' });
        return;
      }
      
      // 本地图片路径
      if (!imagePath.startsWith('/')) {
        logger.error(TAG, `无效的图片路径: ${imagePath}`);
        AlertDialog.show({ message: '保存失败：图片路径无效' });
        return;
      }
      
      const context = getContext(this);
      
      // 获取文件后缀名
      const lastDotIndex = imagePath.lastIndexOf('.');
      const fileExtension = lastDotIndex > 0 ? imagePath.substring(lastDotIndex + 1) : 'jpg';
      
      // 转换为沙箱文件URI
      const sandboxUri = fileUri.getUriFromPath(imagePath);
      
      // 创建photoAccessHelper
      const phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      
      // 准备保存配置
      const srcFileUris: Array<string> = [sandboxUri];
      const photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        title: `manga_page_${pageIndex + 1}`,
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
        
        logger.info(TAG, `图片保存成功: ${desFileUris[0]}`);
        AlertDialog.show({ message: '图片已保存到图库' });
      } else {
        logger.info(TAG, '用户取消保存');
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存图片到图库失败: ${errorMsg}`);
      AlertDialog.show({ message: `保存失败: ${errorMsg}` });
    }
  }

  /**
   * 保存页面信息到数据库
    */
  private async savePageInfoToDatabase(chapterId: string, pages: SourcePageInfo[]): Promise<void> {
    if (this.shouldRefreshVolatileSourcePages()) {
      logger.debug(TAG, `易失票据图源跳过 page 表保存: chapterId=${chapterId}, count=${pages.length}`);
      return;
    }

    try {
      const dataManager = DataManager.getInstance();
      
      // 检查是否已经保存过页面信息
      const existingPages = await dataManager.getPageInfoList(chapterId);
      if (existingPages.length > 0) {
        logger.debug(TAG, `Chapter ${chapterId} already has cached page info, skip save`);
        return;
      }
      
      // [优化] 批量保存页面信息（事务包裹）
      const pageInputs: PageInfoInput[] = pages.map((pageInfo: SourcePageInfo, i: number): PageInfoInput => ({
        chapterId: chapterId,
        index: i,
        imageUrl: pageInfo.imageUrl,
        width: pageInfo.width || 0,
        height: pageInfo.height || 0,
        fileSize: 0
      }));
      await dataManager.batchAddPageInfo(pageInputs);
      
      logger.info(TAG, `Saved page info for chapter ${chapterId}, count=${pages.length}`);
    } catch (error) {
      logger.error(TAG, `保存页面信息失败: ${String(error)}`);
    }
  }

  /**
   * 当前章节加载完成后，立即预加载下一章节
    */
  private preloadNextChapterAfterCurrentLoaded(): void {
    // 检查是否启用下一章节预加载
    if (!this.sourcePreloadSettings.preloadNextChapter) {
      logger.debug(TAG, '下一章节预加载未启用');
      return;
    }
    
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    
    if (!manga || !chapter || !this.mangaEngine) {
      return;
    }
    
    // 只在WebView在线漫画时预加载
    if (this.currentSourceId <= 0) {
      return;
    }

    if (this.shouldRefreshVolatileSourcePages()) {
      logger.debug(TAG, '易失票据图源跳过下一章节提前预加载，切章时再刷新票据');
      return;
    }
    
    // 查找下一章节
    const currentIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    if (currentIndex < 0 || currentIndex >= manga.chapters.length - 1) {
      logger.debug(TAG, '已是最后一章，无需预加载下一章节');
      return; // 已到最后一章
    }
    
    const nextChapter = manga.chapters[currentIndex + 1];
    
    // 检查下一章节是否已有页面信息
    if (nextChapter.pages && nextChapter.pages.length > 0) {
      logger.debug(TAG, `下一章节 ${nextChapter.title} 已有页面信息，跳过预加载`);
      return;
    }
    
    // 异步预加载（不阻塞当前操作）
    logger.info(TAG, `🔄 当前章节加载完成，立即开始预加载下一章节: ${nextChapter.title}`);
    this.preloadChapterPages(nextChapter, this.sourcePreloadSettings.preloadNextPages).catch((error: Error) => {
      logger.warn(TAG, `预加载下一章节失败: ${error.message}`);
    });
  }

  /**
   * 预加载下一章节（当接近章节末尾时）- 已废弃，保留用于兼容
    */
  private preloadNextChapterIfNeeded(currentPageIndex: number): void {
    // 此方法已被 preloadNextChapterAfterCurrentLoaded 替代
    // 此方法已被 preloadNextChapterAfterCurrentLoaded 替代
  }

  /**
   * 更新条漫模式下的相邻章节信息
   * 更新条漫模式下的相邻章节信息
    */
  private updateAdjacentChaptersForWebtoon(): void {
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    
    if (!manga || !chapter) {
      this.prevChapterForWebtoon = undefined;
      this.nextChapterForWebtoon = undefined;
      // [修复] 数据不完整时设置为false，允许尝试加载章节
      this.isFirstChapterState = false;
      this.isLastChapterState = false;
      return;
    }

    const currentIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    if (currentIndex < 0) {
      this.prevChapterForWebtoon = undefined;
      this.nextChapterForWebtoon = undefined;
      this.isFirstChapterState = false;
      this.isLastChapterState = false;
      return;
    }

    // [修复] 更新章节边界状态，确保条漫模式下能正确触发章节加载
    this.isFirstChapterState = currentIndex === 0;
    this.isLastChapterState = currentIndex >= manga.chapters.length - 1;
    logger.info(TAG, `📊 章节边界状态更新: currentChapter=${chapter.title}, index=${currentIndex}/${manga.chapters.length - 1}, isFirst=${this.isFirstChapterState}, isLast=${this.isLastChapterState}`);

    // 获取前一章
    if (currentIndex > 0) {
      const prevChapter = manga.chapters[currentIndex - 1];
      // 检查前一章是否有页面信息
      if (prevChapter.pages && prevChapter.pages.length > 0) {
        this.prevChapterForWebtoon = prevChapter;
        logger.info(TAG, `Prepared previous adjacent chapter: ${prevChapter.title}, pages=${prevChapter.pages.length}`);
      } else {
        this.prevChapterForWebtoon = undefined;
        logger.info(TAG, `条漫前一章(未加载): ${prevChapter.title}`);
      }
    } else {
      this.prevChapterForWebtoon = undefined;
      logger.debug(TAG, `条漫前一章: 无（已是第一章）`);
    }

    // 获取下一章
    if (currentIndex < manga.chapters.length - 1) {
      const nextChapter = manga.chapters[currentIndex + 1];
      // 检查下一章是否有页面信息
      if (nextChapter.pages && nextChapter.pages.length > 0) {
        this.nextChapterForWebtoon = nextChapter;
        logger.info(TAG, `Prepared next adjacent chapter: ${nextChapter.title}, pages=${nextChapter.pages.length}`);
      } else {
        this.nextChapterForWebtoon = undefined;
        logger.info(TAG, `条漫下一章(未加载): ${nextChapter.title}`);
      }
    } else {
      this.nextChapterForWebtoon = undefined;
      logger.debug(TAG, `条漫下一章: 无（已是最后一章）`);
    }
  }

  /**
   * 检查当前章节是否是第一章
   * 检查当前章节是否是第一章
    */
  private isCurrentChapterFirst(): boolean {
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    
    // [修复] 数据不完整时返回 false，而不是 true
    // [修复] 数据不完整时返回 false，而不是 true
    if (!manga || !chapter || !manga.chapters || manga.chapters.length === 0) {
      return false;
    }
    
    const currentIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    // 找不到索引时返回 false，允许尝试加载
    if (currentIndex < 0) {
      return false;
    }
    return currentIndex === 0;
  }

  /**
   * 检查当前章节是否是最后一章
   * 检查当前章节是否是最后一章
    */
  private isCurrentChapterLast(): boolean {
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    
    // [修复] 数据不完整时返回 false，而不是 true
    // [修复] 数据不完整时返回 false，而不是 true
    if (!manga || !chapter || !manga.chapters || manga.chapters.length === 0) {
      return false;
    }
    
    const currentIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    // 找不到索引时返回 false，允许尝试加载
    if (currentIndex < 0) {
      return false;
    }
    return currentIndex >= manga.chapters.length - 1;
  }

  /**
   * 处理条漫模式请求加载相邻章节
   * 处理条漫模式请求加载相邻章节
    */
  private async handleWebtoonAdjacentChapterRequest(direction: 'prev' | 'next'): Promise<void> {
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    
    if (!manga || !chapter) {
      logger.warn(TAG, '无法加载相邻章节: 漫画或章节数据为空');
      return;
    }

    // [修复2] 条漫边界请求时，应基于已加载的最远章节而非当前章节来查找下一个要加载的章节
    // [修复2] 条漫边界请求时，应基于已加载的最远章节而非当前章节来查找下一个要加载的章节
    let anchorIndex: number;
    if (direction === 'next' && this.nextChapterForWebtoon) {
      const nextIdx = manga.chapters.findIndex(ch => ch.id === this.nextChapterForWebtoon!.id);
      anchorIndex = nextIdx >= 0 ? nextIdx : manga.chapters.findIndex(ch => ch.id === chapter.id);
    } else if (direction === 'prev' && this.prevChapterForWebtoon) {
      const prevIdx = manga.chapters.findIndex(ch => ch.id === this.prevChapterForWebtoon!.id);
      anchorIndex = prevIdx >= 0 ? prevIdx : manga.chapters.findIndex(ch => ch.id === chapter.id);
    } else {
      anchorIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    }
    
    if (anchorIndex < 0) {
      logger.warn(TAG, '无法找到锚点章节索引');
      return;
    }

    const targetIndex = direction === 'prev' ? anchorIndex - 1 : anchorIndex + 1;
    if (targetIndex < 0 || targetIndex >= manga.chapters.length) {
      logger.info(TAG, `No ${direction === 'prev' ? 'previous' : 'next'} chapter available`);
      return;
    }

    const targetChapter = manga.chapters[targetIndex];
    logger.info(TAG, `🔍 条漫相邻章节请求: direction=${direction}, targetChapter=${targetChapter.title}, hasPages=${!!targetChapter.pages && targetChapter.pages.length > 0}`);
    
    // 如果目标章节已有页面信息，直接更新状态
    if (targetChapter.pages && targetChapter.pages.length > 0) {
      this.assignWebtoonAdjacentChapter(direction, targetChapter);
      logger.info(TAG, `Prepared ${direction === 'prev' ? 'previous' : 'next'} adjacent chapter from cache: ${targetChapter.title}, pages=${targetChapter.pages.length}`);
      return;
    }

    // 否则异步加载章节页面信息
    logger.info(TAG, `📥 开始加载${direction === 'prev' ? '前' : '后'}一章: ${targetChapter.title}`);
    
    try {
      await this.preloadChapterPages(targetChapter, -1);
      
      // 加载完成后更新状态
      if (targetChapter.pages && targetChapter.pages.length > 0) {
        this.assignWebtoonAdjacentChapter(direction, targetChapter);
        logger.info(TAG, `Prepared ${direction === 'prev' ? 'previous' : 'next'} adjacent chapter after preload: ${targetChapter.title}, pages=${targetChapter.pages.length}`);
      } else {
        logger.warn(TAG, `⚠️ ${direction === 'prev' ? '前' : '后'}一章加载后仍无页面数据: ${targetChapter.title}`);
        // 在线条漫保留旧邻章引用，避免反复置空触发Viewer重排
        if (!this.isOnlineReaderContentType()) {
          this.assignWebtoonAdjacentChapter(direction, undefined);
        }
      }
    } catch (error) {
      logger.error(TAG, `❌ 加载${direction === 'prev' ? '前' : '后'}一章失败: ${String(error)}`);
      // 在线条漫保留旧邻章引用，避免边界失败后抖动；本地模式保持原有可重试行为
      if (!this.isOnlineReaderContentType()) {
        this.assignWebtoonAdjacentChapter(direction, undefined);
      }
    }
  }

  private isOnlineReaderContentType(): boolean {
    const ct = this.pageParams?.contentType;
    return ct === 'OnlineUndownloaded' ||
      ct === 'OnlineDownloaded' ||
      ct === MangaReaderContentType.Suwayomi ||
      ct === MangaReaderContentType.Komga;
  }

  private getWebtoonSwitchDebounceMs(): number {
    return this.isOnlineReaderContentType()
      ? this.WEBTOON_SWITCH_DEBOUNCE_ONLINE_MS
      : this.WEBTOON_SWITCH_DEBOUNCE_LOCAL_MS;
  }

  private assignWebtoonAdjacentChapter(direction: 'prev' | 'next', chapter?: MangaChapter): void {
    if (direction === 'prev') {
      if (!chapter) {
        if (this.prevChapterForWebtoon !== undefined) {
          this.prevChapterForWebtoon = undefined;
        }
        return;
      }
      const current = this.prevChapterForWebtoon;
      const currentPages = current?.pages ? current.pages.length : 0;
      const incomingPages = chapter.pages ? chapter.pages.length : 0;
      if (!current || current.id !== chapter.id || currentPages !== incomingPages) {
        this.prevChapterForWebtoon = chapter;
      }
      return;
    }

    if (!chapter) {
      if (this.nextChapterForWebtoon !== undefined) {
        this.nextChapterForWebtoon = undefined;
      }
      return;
    }
    const current = this.nextChapterForWebtoon;
    const currentPages = current?.pages ? current.pages.length : 0;
    const incomingPages = chapter.pages ? chapter.pages.length : 0;
    if (!current || current.id !== chapter.id || currentPages !== incomingPages) {
      this.nextChapterForWebtoon = chapter;
    }
  }

  private scheduleOnlineAdjacentChapterWarmup(currentIndex: number): void {
    if (this.webtoonOnlineAdjacentWarmupTimer !== -1) {
      clearTimeout(this.webtoonOnlineAdjacentWarmupTimer);
      this.webtoonOnlineAdjacentWarmupTimer = -1;
    }
    this.webtoonOnlineAdjacentWarmupTimer = setTimeout(() => {
      this.webtoonOnlineAdjacentWarmupTimer = -1;
      this.loadOnlineAdjacentChaptersForWebtoon(currentIndex).catch((error: Error) => {
        logger.warn(TAG, `在线条漫相邻章节预热失败: ${error.message}`);
      });
    }, 140);
  }

  private async loadOnlineAdjacentChaptersForWebtoon(currentIndex: number): Promise<void> {
    const manga = this.readerState.currentManga;
    if (!manga) {
      return;
    }

    const chapterCount = manga.chapters.length;
    if (currentIndex <= 0) {
      this.assignWebtoonAdjacentChapter('prev', undefined);
    }
    if (currentIndex >= chapterCount - 1) {
      this.assignWebtoonAdjacentChapter('next', undefined);
    }
    const loadTargets: WebtoonAdjacentChapterLoadTarget[] = [];
    if (currentIndex > 0) {
      loadTargets.push({
        direction: 'prev',
        chapter: manga.chapters[currentIndex - 1]
      });
    }
    if (currentIndex < chapterCount - 1) {
      loadTargets.push({
        direction: 'next',
        chapter: manga.chapters[currentIndex + 1]
      });
    }

    for (const target of loadTargets) {
      const chapter = target.chapter;
      if (chapter.pages && chapter.pages.length > 0) {
        this.assignWebtoonAdjacentChapter(target.direction, chapter);
        continue;
      }
      if (this.webtoonOnlineAdjacentLoadingChapterIds.has(chapter.id)) {
        continue;
      }
      this.webtoonOnlineAdjacentLoadingChapterIds.add(chapter.id);
      try {
        await this.preloadChapterPages(chapter, -1);
      } catch (error) {
        logger.warn(TAG, `在线条漫预热章节失败: ${chapter.title}, error=${String(error)}`);
      } finally {
        this.webtoonOnlineAdjacentLoadingChapterIds.delete(chapter.id);
      }
      if (chapter.pages && chapter.pages.length > 0) {
        this.assignWebtoonAdjacentChapter(target.direction, chapter);
      }
    }
  }

  /**
   * [新增] 处理条漫模式章节切换
   * [新增] 处理条漫模式章节切换
   * 当用户在条漫模式下滚动到其他章节时调用
   * @param chapterId 新章节ID
   * @param chapterTitle 新章节标题
    */
  private handleWebtoonChapterSwitch(chapterId: string, chapterTitle: string, pageIndex: number): void {
    const manga = this.readerState.currentManga;
    const currentChapter = this.readerState.currentChapter;
    
    if (!manga || !currentChapter) {
      logger.warn(TAG, '条漫章节切换: 漫画或章节数据为空');
      return;
    }
    
    // 如果是同一章节，只更新页码
    if (chapterId === currentChapter.id) {
      if (pageIndex !== this.readerState.currentPageIndex) {
        this.readerState = {
          currentManga: this.readerState.currentManga,
          currentChapter: this.readerState.currentChapter,
          currentPageIndex: pageIndex,
          isFullscreen: this.readerState.isFullscreen,
          showControls: this.readerState.showControls,
          isLoading: this.readerState.isLoading,
          zoomScale: this.readerState.zoomScale,
          errorMessage: this.readerState.errorMessage
        };
      }
      return;
    }

    const now = Date.now();
    if (this.lastWebtoonSwitchChapterId === chapterId &&
      now - this.lastWebtoonSwitchAt < this.getWebtoonSwitchDebounceMs()) {
      logger.debug(TAG, `条漫章节切换防抖命中: chapterId=${chapterId}`);
      return;
    }
    this.lastWebtoonSwitchChapterId = chapterId;
    this.lastWebtoonSwitchAt = now;
    
    // 查找新章节
    const newChapter = manga.chapters.find(ch => ch.id === chapterId);
    if (!newChapter) {
      logger.warn(TAG, `条漫章节切换: 未找到章节 ${chapterId}`);
      return;
    }
    
    // [修复B2] 确保新章节有有效的页面数据
    // [修复B2] 确保新章节有有效的页面数据
    if (!newChapter.pages || newChapter.pages.length === 0) {
    // 如果章节对象的pages为空，尝试从已加载的条漫相邻章节中获取页面数据
      if (this.prevChapterForWebtoon && this.prevChapterForWebtoon.id === chapterId && 
          this.prevChapterForWebtoon.pages && this.prevChapterForWebtoon.pages.length > 0) {
        newChapter.pages = this.prevChapterForWebtoon.pages;
        logger.info(TAG, `[B2 cache] restored previous adjacent chapter pages: ${newChapter.title}, pages=${newChapter.pages.length}`);
      } else if (this.nextChapterForWebtoon && this.nextChapterForWebtoon.id === chapterId &&
                 this.nextChapterForWebtoon.pages && this.nextChapterForWebtoon.pages.length > 0) {
        newChapter.pages = this.nextChapterForWebtoon.pages;
        logger.info(TAG, `[B2 cache] restored next adjacent chapter pages: ${newChapter.title}, pages=${newChapter.pages.length}`);
      } else {
        logger.warn(TAG, `条漫章节切换: 章节 ${chapterTitle} 无页面数据，工具栏可能显示不正确`);
      }
    }
    
    // [修复B2] 确保pageIndex在有效范围内
    const totalPages = newChapter.pages ? newChapter.pages.length : 0;
    const safePageIndex = totalPages > 0 ? Math.min(pageIndex, totalPages - 1) : 0;
    
    logger.info(TAG, `条漫章节切换: ${currentChapter.title} -> ${chapterTitle}, 页码=${safePageIndex + 1}/${totalPages}`);
    
    // 先保存旧章节的阅读进度
    this.saveReadingProgressInternal('webtoonChapterSwitch').catch((error: Error) => {
      logger.error(TAG, `保存旧章节阅读进度失败: ${error.message}`);
    });
    
    // 更新当前章节和页码
    this.readerState = {
      currentManga: this.readerState.currentManga,
      currentChapter: newChapter,
      currentPageIndex: safePageIndex,
      isFullscreen: this.readerState.isFullscreen,
      showControls: this.readerState.showControls,
      isLoading: this.readerState.isLoading,
      zoomScale: this.readerState.zoomScale,
      errorMessage: this.readerState.errorMessage
    };
    
    // 重置阅读会话计时
    this.sessionStartTimestamp = Date.now();
    this.lastProgressSaveTime = 0;
    this.lastSavedPageIndex = -1;
    
    // [修复] 条漫滚动切换章节时，不调用 updateAdjacentChaptersForWebtoon（它会导致MangaViewer全量重建数据列表）
    // [修复] 条漫滚动切换章节时，不调用 updateAdjacentChaptersForWebtoon（它会导致MangaViewer全量重建数据列表）
    const newChapterIndex = manga.chapters.findIndex(ch => ch.id === chapterId);
    if (newChapterIndex >= 0) {
      this.isFirstChapterState = newChapterIndex === 0;
      this.isLastChapterState = newChapterIndex >= manga.chapters.length - 1;
      logger.info(TAG, `条漫章节边界更新: index=${newChapterIndex}/${manga.chapters.length - 1}, isFirst=${this.isFirstChapterState}, isLast=${this.isLastChapterState}`);
      
      if (this.isOnlineReaderContentType()) {
        // 在线/在线已下载：使用温和预热，避免跨章瞬间并发抢占导致卡顿
        this.scheduleOnlineAdjacentChapterWarmup(newChapterIndex);
      } else {
        // 本地：保持轻量同步刷新
        this.loadNewAdjacentChaptersForWebtoon(newChapterIndex);
      }
    } else {
      // 找不到章节索引，回退到全量更新
      this.updateAdjacentChaptersForWebtoon();
    }
    
    logger.info(TAG, `条漫章节切换完成: ${newChapter.title}, 页码=${safePageIndex + 1}/${totalPages}`);
  }
  
  /**
   * [新增] 条漫模式滚动切换章节后，异步加载新的相邻章节
   * [新增] 条漫模式滚动切换章节后，异步加载新的相邻章节
   * 与 updateAdjacentChaptersForWebtoon 不同，此方法不会立即更新 prevChapterForWebtoon/nextChapterForWebtoon
    */
  private loadNewAdjacentChaptersForWebtoon(currentIndex: number): void {
    const manga = this.readerState.currentManga;
    if (!manga) return;
    
    // 检查下一章是否需要加载
    if (currentIndex < manga.chapters.length - 1) {
      const nextChapter = manga.chapters[currentIndex + 1];
      // 如果下一章已有页面，直接更新（会触发MangaViewer增量更新）
      if (nextChapter.pages && nextChapter.pages.length > 0) {
        this.assignWebtoonAdjacentChapter('next', nextChapter);
        logger.info(TAG, `[条漫滚动切换] 下一章已加载: ${nextChapter.title}`);
      } else {
        // 下一章无页面，异步加载，加载完成后更新
        this.assignWebtoonAdjacentChapter('next', undefined);
        logger.info(TAG, `[条漫滚动切换] 下一章未加载，异步触发: ${nextChapter.title}`);
      }
    } else {
      this.assignWebtoonAdjacentChapter('next', undefined);
    }
    
    // 检查上一章是否需要加载
    if (currentIndex > 0) {
      const prevChapter = manga.chapters[currentIndex - 1];
      if (prevChapter.pages && prevChapter.pages.length > 0) {
        this.assignWebtoonAdjacentChapter('prev', prevChapter);
        logger.info(TAG, `[条漫滚动切换] 上一章已加载: ${prevChapter.title}`);
      } else {
        this.assignWebtoonAdjacentChapter('prev', undefined);
        logger.info(TAG, `[条漫滚动切换] 上一章未加载: ${prevChapter.title}`);
      }
    } else {
      this.assignWebtoonAdjacentChapter('prev', undefined);
    }
  }

  /**
   * 加载图源的预加载设置
   * 加载图源的预加载设置
    */
  private async loadSourcePreloadSettings(sourceId: number): Promise<void> {
    try {
      const dataManager = DataManager.getInstance();
      
      // [性能优化] 使用批量查询，单次 getSourcePkgById + 单条 SQL 替代 4×2=8 次数据库查询
      const settingsMap = await dataManager.getSourceUserSettings(sourceId, [
        'readerPreloadCount', 'preloadCurrentChapter', 'preloadNextChapter', 'downloadWhileReading'
      ]);
      
      const preloadCountRecord = settingsMap.get('readerPreloadCount');
      const preloadCurrentRecord = settingsMap.get('preloadCurrentChapter');
      const preloadNextRecord = settingsMap.get('preloadNextChapter');
      
      const settings: SourcePreloadSettings = {
        preloadCurrentChapter: preloadCurrentRecord?.settingValue === '1' || preloadCurrentRecord?.settingValue === undefined,
        preloadCurrentPages: preloadCountRecord?.settingValue ? Number(preloadCountRecord.settingValue) : 10,
        preloadNextChapter: preloadNextRecord?.settingValue === '1' || preloadNextRecord?.settingValue === undefined,
        preloadNextPages: -1
      };
      
      this.sourcePreloadSettings = settings;
      logger.info(TAG, `✅ 已加载图源预加载设置: 当前章节=${this.sourcePreloadSettings.preloadCurrentChapter}(${this.sourcePreloadSettings.preloadCurrentPages}页), 下一章节=${this.sourcePreloadSettings.preloadNextChapter}(${this.sourcePreloadSettings.preloadNextPages}页)`);
    } catch (error) {
      logger.error(TAG, `加载图源预加载设置失败: ${String(error)}`);
    }
  }

  
  /**
   * 保存章节页面到数据库
    */
  private async saveChapterPagesToDatabase(chapterId: string, pages: SourcePageInfo[]): Promise<void> {
    if (this.shouldRefreshVolatileSourcePages()) {
      logger.debug(TAG, `易失票据图源跳过 online_page 表保存: chapterId=${chapterId}, count=${pages.length}`);
      return;
    }

    try {
      const dataManager = DataManager.getInstance();
      
      // [修复] 先删除该章节的旧页面数据，避免重复插入
      logger.debug(TAG, `🗑️ 删除章节 ${chapterId} 的旧页面数据`);
      await dataManager.deleteOnlineChapterPages(chapterId);
      
      // [性能优化] 使用事务批量插入，替代逐条 addOnlinePageInfo
      const pageInputs: OnlinePageInfoInput[] = pages.map((pageInfo: SourcePageInfo, i: number): OnlinePageInfoInput => ({
        chapterId: chapterId,
        pageNumber: i,
        imageUrl: pageInfo.imageUrl,
        width: pageInfo.width || 0,
        height: pageInfo.height || 0,
        fileSize: 0
      }));
      
      await dataManager.batchAddOnlinePages(chapterId, pageInputs);
      
      logger.info(TAG, `Saved online pages for chapter ${chapterId}, count=${pages.length}`);
    } catch (error) {
      logger.error(TAG, `保存页面信息失败: ${error}`);
    }
  }

  /**
   * 预加载章节页面
   * 预加载章节页面
   * @param chapter 要预加载的章节
    */
  private async preloadChapterPages(chapter: MangaChapter, maxPages: number = -1): Promise<void> {
    if (maxPages === 0) {
      logger.debug(TAG, '棰勫姞杞介〉鏁颁负0锛岃烦杩囬鍔犺浇');
      return;
    }

    const currentManga = this.readerState.currentManga;
    if (currentManga && this.remoteLibraryBridge.isRemoteProviderManga(currentManga)) {
      try {
        const remotePages = await this.remoteLibraryBridge.loadChapterPages(currentManga, chapter);
        if (remotePages.length <= 0) {
          throw new Error(`remote provider chapter has no pages: ${chapter.title}`);
        }

        if (!chapter.totalPages || chapter.totalPages <= 0) {
          chapter.totalPages = remotePages.length;
        }

        chapter.pages = maxPages > 0 && maxPages < remotePages.length
          ? remotePages.slice(0, maxPages)
          : remotePages;
        logger.info(TAG, `Remote provider pages loaded: chapter=${chapter.title}, count=${chapter.pages.length}`);
        return;
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `Remote provider preload failed: ${errorMessage}`);
        throw new Error(`棰勫姞杞界珷鑺傞〉闈㈠け璐? ${errorMessage}`);
      }
    }

    const shouldTryOnlineArchive =
      this.pageParams?.contentType === MangaReaderContentType.OnlineDownloaded ||
      this.pageParams?.contentType === MangaReaderContentType.OnlineUndownloaded;
    if (shouldTryOnlineArchive) {
      const archiveLoaded = await this.tryLoadOnlineDownloadedArchivePagesForChapter(chapter, false);
      if (archiveLoaded) {
        return;
      }
    }

    // 如果MangaEngine未初始化，尝试从数据库加载页面信息
    if (!this.mangaEngine) {
      logger.warn(TAG, 'MangaEngine未初始化，尝试从数据库加载页面信息');
      
      try {
        const dataManager = DataManager.getInstance();
        
        // [修复] 先尝试从page表加载（本地漫画），再尝试从online_page表加载
        // [修复] 先尝试从page表加载（本地漫画），再尝试从online_page表加载
        const localPages = await dataManager.getChapterPages(chapter.id);
        
        if (localPages && localPages.length > 0) {
          logger.info(TAG, `Loaded local page records from chapter_pages: ${chapter.title}, count=${localPages.length}`);
          
          // 转换为MangaPage格式
          chapter.pages = localPages.map((localPage, index): MangaPage => {
          // 转换为MangaPage格式
            const imagePath = localPage.localPath || localPage.imageUrl || '';
            let sourceType: ImageSourceType;
            if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
              sourceType = ImageSourceType.NETWORK;
            } else if (imagePath.startsWith('/') || imagePath.includes('data/') || imagePath.includes('storage/')) {
              sourceType = ImageSourceType.LOCAL;
            } else {
              sourceType = ImageSourceType.RAWFILE;
            }
            
            return {
              id: localPage.id,
              index: index,
              sourceType: sourceType,
              imagePath: imagePath,
              imageUrl: localPage.imageUrl || imagePath,
              width: localPage.width,
              height: localPage.height,
              fileSize: localPage.fileSize,
              isLoaded: false
            };
          });
          
          return;
        }
        
        // 本地page表没有数据，尝试从online_page表加载
        const dbPages = await dataManager.getOnlineChapterPages(chapter.id);
        
        if (dbPages && dbPages.length > 0) {
          logger.info(TAG, `Loaded page records from online_page table: ${chapter.title}, count=${dbPages.length}`);
          
          // 转换为MangaPage格式
          chapter.pages = dbPages.map((dbPage, index): MangaPage => {
            const localPath = dbPage.localPath || '';
            const imagePath = localPath.length > 0 ? localPath : dbPage.imageUrl;
            let sourceType: ImageSourceType;
            if (localPath.length > 0) {
              sourceType = ImageSourceType.LOCAL;
            } else if (dbPage.imageUrl.startsWith('http://') || dbPage.imageUrl.startsWith('https://')) {
              sourceType = ImageSourceType.NETWORK;
            } else if (dbPage.imageUrl.startsWith('/')) {
              sourceType = ImageSourceType.LOCAL;
            } else {
              sourceType = ImageSourceType.RAWFILE;
            }
            
            return {
              id: dbPage.id,
              index: index,
              sourceType: sourceType,
              imagePath: imagePath,
              imageUrl: dbPage.imageUrl,
              localPath: localPath,
              width: dbPage.width,
              height: dbPage.height,
              fileSize: dbPage.fileSize,
              isLoaded: false
            };
          });
          
          return;
        }
        
        // 两个表都没有页面信息
        const error = `MangaEngine未初始化且数据库中无页面信息: ${chapter.title}`;
        logger.error(TAG, error);
        throw new Error(error);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `从数据库加载页面信息失败: ${errorMsg}`);
        throw new Error(`预加载章节页面失败: ${errorMsg}`);
      }
    }
    
    // 如果maxPages为0，不预加载
    if (maxPages === 0) {
      logger.debug(TAG, '预加载页数为0，跳过预加载');
      return;
    }

    // [P0] Cache-first for chapter switch/preload path.
    if (this.pageParams?.contentType === MangaReaderContentType.OnlineUndownloaded && !this.shouldRefreshVolatileSourcePages()) {
      try {
        const dataManager = DataManager.getInstance();
        const cachedOnlinePages = await dataManager.getOnlineChapterPages(chapter.id);
        const validCachedOnlinePages = cachedOnlinePages.filter((p: OnlinePageInfo) => p.imageUrl && p.imageUrl.trim().length > 0);
        if (validCachedOnlinePages.length > 0) {
          chapter.pages = validCachedOnlinePages.map((p: OnlinePageInfo, index: number): MangaPage => {
            // OnlineUndownloaded 场景统一按网络源处理，避免缓存记录中的失效 localPath 导致章节切换加载异常
            const sourceType: ImageSourceType = ImageSourceType.NETWORK;
            const imagePath = p.imageUrl;
            return {
              id: p.id || `${chapter.id}_page_${p.pageNumber}`,
              index: index,
              sourceType: sourceType,
              imagePath: imagePath,
              imageUrl: p.imageUrl,
              width: p.width,
              height: p.height,
              fileSize: p.fileSize,
              isLoaded: false
            } as MangaPage;
          });
          logger.info(TAG, `[缓存优先] 命中 online_page: 章节=${chapter.title}, 页数=${chapter.pages.length}`);
          return;
        }
      } catch (cacheError) {
        logger.warn(TAG, `预加载章节页面时缓存优先查询失败: ${String(cacheError)}`);
      }
    }
    
    try {
      // 获取外部章节ID
      const externalChapterId = await this.getExternalChapterIdForOnlineUndownloaded(chapter);
      const externalMangaId = await this.getExternalMangaIdForOnlineUndownloaded(this.readerState.currentManga?.id || '');
      
      // 检查是否已经在详情页预加载过
      const preloadManager = ChapterPreloadManager.getInstance();
      const preloadTask = preloadManager.getTaskStatus(chapter.id);
      
      let pageListResult: EngineResult<SourcePageInfo[]>;
      
      if (preloadTask && preloadTask.status === 'completed' && preloadTask.pageCount > 0 && !this.shouldRefreshVolatileSourcePages()) {
        logger.info(TAG, `使用章节预加载缓存: ${chapter.title}, 页面数=${preloadTask.pageCount}, 已缓存页数=${preloadTask.preloadedPages}`);
        
        // 尝试从数据库读取页面列表，避免重复调用getPageList
        const dataManager = DataManager.getInstance();
        const dbPages = await dataManager.getPageInfoList(chapter.id);
        
        if (dbPages.length > 0) {
          logger.info(TAG, `预加载后从本地缓存读取页面列表: ${chapter.title}, 数量=${dbPages.length}`);
          // 转换为SourcePageInfo格式
          const sourcePages: SourcePageInfo[] = dbPages.map((dbPage, index): SourcePageInfo => {
            return {
              page: index + 1,
              imageUrl: dbPage.imageUrl,
              width: dbPage.width,
              height: dbPage.height
            };
          });
          pageListResult = {
            success: true,
            data: sourcePages,
            duration: 0,
            actionCount: 0
          };
        } else {
          // 数据库中没有，仍然需要调用getPageList
          logger.info(TAG, `数据库中无页面列表，调用getPageList: ${chapter.title}`);
          pageListResult = await this.mangaEngine.getPageList(externalChapterId, externalMangaId);
        }
      } else {
        // 未预加载，正常调用getPageList
        logger.info(TAG, `📥 预加载章节页面: chapterId=${externalChapterId}, mangaId=${externalMangaId}, maxPages=${maxPages}`);
        pageListResult = await this.mangaEngine.getPageList(externalChapterId, externalMangaId);
      }
      
      if (!pageListResult.success || !pageListResult.data || pageListResult.data.length === 0) {
        const errorMsg = pageListResult.error || '页面列表为空';
        logger.error(TAG, `预加载失败: ${errorMsg}`);
        throw new Error(errorMsg);
      }
      
      // 根据maxPages限制预加载的页数
      let pagesToPreload = pageListResult.data;
      if (maxPages > 0 && maxPages < pageListResult.data.length) {
        pagesToPreload = pageListResult.data.slice(0, maxPages);
        logger.info(TAG, `预加载源返回 ${pageListResult.data.length} 页，已截断为 ${pagesToPreload.length} 页`);
      } else {
        logger.info(TAG, `预加载源返回 ${pageListResult.data.length} 页，使用完整列表`);
      }
      
      // 转换为MangaPage格式
      // 转换为MangaPage格式
      const mangaPages: MangaPage[] = pagesToPreload.map((pageInfo: SourcePageInfo, index: number) => {
        return {
          id: `${chapter.id}_page_${pageInfo.page}`,
          index: index,
          sourceType: ImageSourceType.NETWORK,
          imagePath: pageInfo.imageUrl,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width,
          height: pageInfo.height,
          fileSize: 0,
          requestHeaders: this.cloneSourcePageRequestHeaders(pageInfo),
          isLoaded: false
        } as MangaPage;
      });
      
      // 更新章节的页面列表（内存中）
      chapter.pages = mangaPages;
      
      // [P0] Non-blocking save: avoid blocking chapter switch on per-page DB writes.
      this.savePageInfoToDatabase(chapter.id, pageListResult.data).catch((err: Error) => {
        logger.warn(TAG, `预加载后保存页面信息失败: ${err.message}`);
      });
      
      logger.info(TAG, `✅ 预加载章节 ${chapter.title} 完成，已保存到数据库`);
    } catch (error) {
      logger.error(TAG, `预加载章节页面失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 保存阅读进度（带限流与空值检查）
    */
  private async saveReadingProgressInternal(trigger: string): Promise<void> {
    // [修复] 阻止初始化期间的阅读进度保存，避免覆盖正确的阅读进度
    // [修复] 阻止初始化期间的阅读进度保存，避免覆盖正确的阅读进度
    // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，传递错误的页面索引
    if (!this.isReaderInitialized && trigger !== 'aboutToDisappear') {
      logger.debug(TAG, `[修复] 阻止初始化期间的阅读进度保存: 触发源=${trigger}`);
      return;
    }
    
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    if (!manga || !chapter) {
      return;
    }

    let pageIndex: number = this.normalizeReaderPageIndexForChapter(chapter, this.readerState.currentPageIndex);
    const guard: ChapterSwitchPageGuard | null = this.getActiveChapterSwitchPageGuard(chapter);
    if (guard) {
      pageIndex = guard.pageIndex;
      logger.debug(TAG, `[保存进度] 跨章同步中，使用目标页码: chapter=${chapter.title}, page=${pageIndex + 1}, trigger=${trigger}`);
    }
    if (this.mangaViewerComponent) {
      const viewerPageIndex: number = this.mangaViewerComponent.getCurrentViewPageIndex();
      const pageCount: number = this.getChapterPageCount(chapter);
      if (viewerPageIndex >= 0 && (pageCount <= 0 || viewerPageIndex < pageCount)) {
        const normalizedViewerIndex: number = this.normalizeReaderPageIndexForChapter(chapter, viewerPageIndex);
        if (guard && normalizedViewerIndex !== guard.pageIndex) {
          logger.debug(TAG, `[保存进度] 忽略跨章期间不匹配的组件页码: viewer=${viewerPageIndex + 1}, normalized=${normalizedViewerIndex + 1}, expected=${guard.pageIndex + 1}`);
        } else if (normalizedViewerIndex !== pageIndex) {
          logger.debug(TAG, `[保存进度] 页码不一致: 阅读器状态页=${pageIndex}, 组件可视页=${viewerPageIndex}, 规范化=${normalizedViewerIndex}, 改用组件可视页码`);
          pageIndex = normalizedViewerIndex;
        }
      } else if (viewerPageIndex >= 0) {
        logger.debug(TAG, `[保存进度] 忽略超出当前章节范围的组件页码: viewer=${viewerPageIndex + 1}, total=${pageCount}, chapter=${chapter.title}`);
      }
    }
    const now: number = Date.now();

    // 限流：同页且1秒内不重复写入
    if (this.lastSavedPageIndex === pageIndex && (now - this.lastProgressSaveTime) < 1000) {
      return;
    }

    const start: number = this.sessionStartTimestamp > 0 ? this.sessionStartTimestamp : now;
    const duration: number = now - start;

    // 准备在线漫画数据（如果是WebView图源）
    let sourceId: number | undefined = undefined;
    let mangaData: Record<string, Object> | undefined = undefined;
    
    if (this.currentSourceId > 0 && this.mangaEngine) {
      sourceId = this.currentSourceId;
      // 创建临时对象并转换为Record类型
      const tempData: Record<string, Object> = {} as Record<string, Object>;
      tempData['title'] = manga.title;
      tempData['author'] = manga.metadata.authors.join(', ');
      tempData['description'] = manga.description;
      tempData['coverUrl'] = manga.coverImagePath;
      tempData['status'] = String(manga.status);
      tempData['tags'] = manga.metadata.genres;
      tempData['rating'] = 0;
      tempData['chapterCount'] = manga.chapters.length;
      tempData['updateTime'] = Date.now();
      mangaData = tempData;
    }

    // 保存到数据库（会插入新记录，新章节的记录自动覆盖旧章节）
    // 保存到数据库（会插入新记录，新章节的记录自动覆盖旧章节）
    await this.dataService.saveReadingProgress(manga.id, chapter.id, pageIndex, duration, sourceId, mangaData);

    // 更新Manga对象的阅读进度（确保内存中的数据和数据库一致）
    manga.readingProgress.currentChapterId = chapter.id;
    manga.readingProgress.currentPageIndex = pageIndex;
    manga.readingProgress.lastReadAt = now;
    manga.readingProgress.readingStatus = ReadingStatus.READING;
    
    // 累加总阅读时间（转换为分钟）
    manga.readingProgress.totalReadingTime += (duration / 1000 / 60);

    if (this.remoteLibraryBridge.isRemoteProviderManga(manga)) {
      void this.remoteLibraryBridge.updateCachedReadingProgress(manga.id, chapter.id, pageIndex, duration).catch((error: Error) => {
        logger.debug(TAG, `更新远程缓存阅读进度失败: ${error.message}`);
      });

      if (manga.sourceInfo?.providerType === 'suwayomi') {
        const parsedChapter = RemoteLibraryMangaBridge.parseProviderChapterId(chapter.id);
        const rawChapterId = chapter.externalId && chapter.externalId.length > 0
          ? chapter.externalId
          : (parsedChapter ? parsedChapter.rawChapterId : '');
        if (rawChapterId.length > 0) {
          void (async () => {
            const updated = await this.suwayomiExecutor.updateReadingProgress(rawChapterId, pageIndex);
            if (!updated) {
              logger.debug(TAG, `Suwayomi 进度同步失败: chapter=${rawChapterId}`);
            }

            const totalPages = chapter.totalPages || chapter.pages.length;
            if (totalPages > 0 && pageIndex >= totalPages - 1) {
              const marked = await this.suwayomiExecutor.markRead(rawChapterId, true);
              if (!marked) {
                logger.debug(TAG, `Suwayomi 已读状态同步失败: chapter=${rawChapterId}`);
              }
            }
          })().catch((error: Error) => {
            logger.debug(TAG, `同步 Suwayomi 阅读进度失败: ${error.message}`);
          });
        }
      }
    }
    
    logger.info(TAG, `✅ 阅读进度已更新: 章节=${chapter.title}, 页码=${pageIndex + 1}, 时间=${now}`);

    // 更新跟踪服务进度（异步，不阻塞主流程）
    this.updateTrackingProgress(manga.id, chapter, manga.chapters.length).catch((error: Error) => {
      logger.debug(TAG, `更新跟踪进度失败: ${error.message}`);
    });

    this.lastSavedPageIndex = pageIndex;
    this.lastProgressSaveTime = now;
    this.sessionStartTimestamp = now;
    logger.debug(TAG, `已保存阅读进度[${trigger}]: ${manga.title} / ${chapter.title} -> 第${pageIndex + 1}页, 时长${duration}ms`);
  }

  /**
   * 更新跟踪服务进度
    */
  private async updateTrackingProgress(mangaId: string, chapter: MangaChapter, totalChapters: number): Promise<void> {
    try {
      const trackingManager = TrackingManager.getInstance();
      const trackRecords = await trackingManager.getTrackRecords(mangaId);
      
      if (trackRecords.length === 0) {
        return; // 未启用追踪，直接返回
      }

      // 计算章节号（从章节索引或标题中提取）
      const chapterNumber = this.extractChapterNumber(chapter);
      
      // 更新所有跟踪服务的进度
      for (let i = 0; i < trackRecords.length; i++) {
        const record = trackRecords[i];
        await trackingManager.updateReadingProgress(
          mangaId,
          record.trackerId,
          chapterNumber,
          totalChapters
        );
      }
    } catch (error) {
      logger.debug(TAG, `更新跟踪进度异常: ${String(error)}`);
    }
  }

  /**
   * 从章节信息中提取章节号
    */
  private extractChapterNumber(chapter: MangaChapter): number {
    // 尝试从章节索引获取
    if (chapter.chapterNumber !== undefined && chapter.chapterNumber > 0) {
      return chapter.chapterNumber;
    }
    
    // 尝试从标题中提取数字
    const title = chapter.title || '';
    const match = title.match(/(\d+(?:\.\d+)?)/);
    if (match) {
      return parseFloat(match[1]);
    }
    
    // 使用章节在列表中的索引作为备选
    const manga = this.readerState.currentManga;
    if (manga && manga.chapters) {
      const index = manga.chapters.findIndex(c => c.id === chapter.id);
      if (index >= 0) {
        return index + 1;
      }
    }
    
    return 1;
  }

  /**
   * 打开目录（章节列表）- 在阅读器内显示章节列表面板
    */
  private openTableOfContents(): void {
    try {
      const manga = this.readerState.currentManga;
      if (!manga) {
        logger.warn(TAG, '无法打开目录：当前漫画信息为空');
        return;
      }

      if (manga.chapters.length === 0) {
        logger.warn(TAG, '无法打开目录：没有可用章节');
        return;
      }

      // 显示章节列表面板
      this.showChapterList = true;
      this.handleMenusVisibilityChange();
      logger.info(TAG, '打开章节列表面板');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '打开章节列表面板失败', errorMessage);
    }
  }

  /**
   * 切换到指定章节
    */
  private switchToChapter(chapterId: string): void {
    try {
      const manga = this.readerState.currentManga;
      if (!manga) {
        logger.warn(TAG, '无法切换章节：当前漫画信息为空');
        return;
      }

      const targetChapter = manga.chapters.find(ch => ch.id === chapterId);
      if (!targetChapter) {
        logger.warn(TAG, `无法切换章节：未找到章节ID ${chapterId}`);
        return;
      }

      // 保存当前章节进度
      this.saveReadingProgressInternal('switchChapter').then(async () => {
      // 保存当前章节进度
        if (!targetChapter.pages || targetChapter.pages.length === 0 || this.shouldRefreshVolatileSourcePages()) {
          logger.info(TAG, `章节 ${targetChapter.title} 需要刷新页面信息，开始加载...`);
          this.readerState.isLoading = true;
          this.readerState.loadingMessage = `正在加载章节 ${targetChapter.title}...`;
          
          try {
            await this.preloadChapterPages(targetChapter);
            logger.info(TAG, `章节 ${targetChapter.title} 页面加载完成，数量=${targetChapter.pages?.length || 0}`);
          } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error(TAG, `加载章节页面失败: ${errorMsg}`);
            this.readerState.errorMessage = `加载章节页面失败: ${errorMsg}`;
            this.readerState.isLoading = false;
            return;
          }
          
          this.readerState.isLoading = false;
        }
        
        // 切换章节
        this.readerState.currentChapter = targetChapter;
        this.readerState.currentPageIndex = 0;
        
        // 通知自动翻页控制器新章节开始
        if (this.autoPageTurnController) {
          this.autoPageTurnController.notifyNewChapter();
        }
        
        // 重置阅读会话计时
        this.sessionStartTimestamp = Date.now();
        this.lastProgressSaveTime = 0;
        this.lastSavedPageIndex = -1;
        
        // [修复B1] 触发章节变化通知，让MangaViewer重新加载
        this.chapterTick = this.chapterTick + 1;
        
        // [修复B1] 更新条漫模式相邻章节状态
        this.updateAdjacentChaptersForWebtoon();
        
        logger.info(TAG, `切换到章节: ${targetChapter.title}, chapterTick=${this.chapterTick}`);
      }).catch((error: Error) => {
        logger.error(TAG, '切换章节前保存进度失败', error.message);
        // 即使保存失败也继续切换（但不加载页面，避免错误）
        this.readerState.currentChapter = targetChapter;
        this.readerState.currentPageIndex = 0;
        this.sessionStartTimestamp = Date.now();
        this.lastProgressSaveTime = 0;
        this.lastSavedPageIndex = -1;
        // [修复B1] 即使保存失败也需要更新chapterTick和条漫状态
        this.chapterTick = this.chapterTick + 1;
        this.updateAdjacentChaptersForWebtoon();
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '切换章节失败', errorMessage);
    }
  }

  /**
   * 判断设备类型和屏幕方向
    */
  private getDeviceOrientation(): 'portrait' | 'landscape' | 'square' {
    try {
      const displayWidth = display.getDefaultDisplaySync().width;
      const displayHeight = display.getDefaultDisplaySync().height;
      const aspectRatio = displayWidth / displayHeight;
      
      // 竖屏设备：宽高比 < 0.75 (例如：手机竖屏)
      if (aspectRatio < 0.75) {
        return 'portrait';
      }
      // 横屏设备：宽高比 > 1.5 (例如：平板横屏、手机横屏)
      else if (aspectRatio > 1.5) {
        return 'landscape';
      }
      // 方形或近方形屏幕：宽高比在 0.75-1.5 之间 (例如：折叠屏、方形平板)
      else {
        return 'square';
      }
    } catch (error) {
      logger.error(TAG, `获取设备方向失败: ${String(error)}`);
      return 'portrait'; // 默认为竖屏
    }
  }

  /**
   * 处理单击
   * 处理单击
   * 简化交互规则：
   * 1. 首次点击隐藏交互提示overlay
   * 2. 如果设置面板或菜单已显示，点击任意位置关闭
   * 3. 如果工具栏已显示且点击在工具栏区域内，交给工具栏处理
   * 4. 根据阅读模式划分区域：
   *    - 单页模式（LTR）：左侧上一页 | 中央切换工具栏 | 右侧下一页
   *    - 单页模式（RTL）：右侧上一页 | 中央切换工具栏 | 左侧下一页
   *    - 单页模式（TTB）：上侧上一页 | 中央切换工具栏 | 下侧下一页
   *    - 双页模式：左右区域翻页，中央切换工具栏
    */
  private handleSingleTap(event: ClickEvent): void {
    // 注意：双击检测已在handlePageTap中处理，这里直接处理单击逻辑
    // 注意：双击检测已在handlePageTap中处理，这里直接处理单击逻辑
    this.processSingleTap(event);
  }

  /**
   * 处理单击事件的具体逻辑
   * 处理单击事件的具体逻辑
   * 注意：ClickEvent.displayX/displayY 返回的是vp单位的坐标
    */
  private processSingleTap(event: ClickEvent): void {
    // 使用显示坐标（vp单位，相对于窗口的坐标）
    const clickX = event.displayX;
    const clickY = event.displayY;
    
    // 获取显示区域的实际尺寸和设备方向
    // 获取显示区域的实际尺寸和设备方向
    let displayWidth: number;
    let displayHeight: number;
    let aspectRatio: number;
    let deviceOrientation: 'portrait' | 'landscape' | 'square';
    
    try {
      const displayInfo = display.getDefaultDisplaySync();
      // 获取物理像素尺寸和屏幕密度
      const physicalWidth = displayInfo.width;
      const physicalHeight = displayInfo.height;
      const densityPixels = displayInfo.densityPixels || 1.0;
      
      // 转换为vp单位（与ClickEvent.displayX/displayY一致）
      displayWidth = physicalWidth / densityPixels;
      displayHeight = physicalHeight / densityPixels;
      aspectRatio = displayWidth / displayHeight;
      deviceOrientation = this.getDeviceOrientation();
    } catch (error) {
      logger.error(TAG, `获取屏幕尺寸失败: ${String(error)}`);
      // 使用备用值（已经是vp单位）
      displayWidth = this.screenWidth;
      displayHeight = this.screenHeight;
      aspectRatio = displayWidth / displayHeight;
      deviceOrientation = 'portrait';
    }
    
    logger.debug(TAG, `✋ 单击事件: displayX=${clickX.toFixed(2)}vp, displayY=${clickY.toFixed(2)}vp, 屏幕=${displayWidth.toFixed(0)}x${displayHeight.toFixed(0)}vp, 宽高比=${aspectRatio.toFixed(2)}, 设备类型=${deviceOrientation}`);
    
    // 规则1：首次点击隐藏交互提示
    if (this.showInteractionOverlay) {
      this.hideInteractionOverlay();
      return;
    }
    
    // 规则2：如果设置面板或更多菜单已显示，点击任意位置都关闭
    if (this.showSettingsPanel) {
      this.hideSettingsPanelWithAnimation();
      logger.debug(TAG, '关闭设置面板');
      return;
    }
    
    if (this.showMoreMenu) {
      this.hideMoreMenuWithAnimation();
      logger.debug(TAG, '关闭更多菜单');
      return;
    }
    
    // 规则3：如果工具栏已显示，检查点击是否在工具栏区域内
    const topToolbarHeight = ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight) + 16;
    const bottomToolbarHeight = this.navigationBarHeight + 120;
    
    if (this.showTopToolbar && clickY < topToolbarHeight) {
      logger.debug(TAG, '点击在顶部工具栏区域，交给工具栏处理');
      return;
    }
    
    if (this.showBottomToolbar && clickY > (this.screenHeight - bottomToolbarHeight)) {
      logger.debug(TAG, '点击在底部工具栏区域，交给工具栏处理');
      return;
    }
    
    // 规则4：根据阅读模式确定交互区域
    this.handleReadingModeTap(clickX, clickY, deviceOrientation, displayWidth, displayHeight);
  }

  /**
   * 根据阅读模式处理点击事件
    */
  private handleReadingModeTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const isWebtoon = this.readingSettings.readingMode === ReadingMode.WEBTOON ||
                      this.readingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
                      this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
    
    const isDoublePage = this.isEffectiveDoublePageMode();
    
    if (isWebtoon) {
      // 条漫模式：点击任意位置切换工具栏
      this.toggleToolbars();
      logger.debug(TAG, `条漫模式点击，切换工具栏: ${this.showTopToolbar}`);
      return;
    }
    
    if (isDoublePage) {
      // 双页模式：左右区域翻页，中央切换工具栏
      this.handleDoublePageTap(clickX, clickY, deviceOrientation, displayWidth, displayHeight);
      return;
    }
    
    // 单页模式：根据设备类型和屏幕方向划分区域
    this.handleSinglePageTap(clickX, clickY, deviceOrientation, displayWidth, displayHeight);
  }

  /**
   * 处理双页模式的点击事件
   * 处理双页模式的点击事件
    */
  private handleDoublePageTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const centerAreaRatio = 0.4;// 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2;// 两侧各占比 = 0.3

    const isRTL: boolean = this.getEffectiveDoublePageReadingDirection() === ReadingDirection.RIGHT_TO_LEFT;
    const isVerticalDoublePage: boolean = this.isDoublePageVerticalPortraitMode();

    if (isVerticalDoublePage) {
      const effectiveHeight = this.componentHeight > 0 ? this.componentHeight : displayHeight;
      logger.debug(TAG, `双页竖向模式点击已禁用翻页: 组件高度=${this.componentHeight.toFixed(0)}vp, 有效高度=${effectiveHeight.toFixed(0)}vp, clickY=${clickY.toFixed(0)}vp, direction=${this.getDoublePageVerticalDirection()}`);
      this.toggleToolbars();
      logger.info(TAG, `双页竖向模式点击仅切换工具栏: 方向=${deviceOrientation}, 状态=${this.showTopToolbar ? '显示' : '隐藏'}`);
      return;
    } else {
      const effectiveWidth = this.componentWidth > 0 ? this.componentWidth : displayWidth;
      const leftZoneEnd = effectiveWidth * sideAreaRatio;
      const rightZoneStart = effectiveWidth * (1 - sideAreaRatio);
      
      logger.debug(TAG, `双页模式区域划分: 组件宽度=${this.componentWidth.toFixed(0)}vp, 有效宽度=${effectiveWidth.toFixed(0)}vp, leftZoneEnd=${leftZoneEnd.toFixed(0)}vp, rightZoneStart=${rightZoneStart.toFixed(0)}vp, clickX=${clickX.toFixed(0)}vp, 方向=${isRTL ? 'RTL' : 'LTR'}`);
      
      if (clickX < leftZoneEnd) {
        // 左侧区域
        if (isRTL) {
          this.goToNextPage();
          logger.info(TAG, `左侧区域点击：RTL 模式进入下一页，方向=${deviceOrientation}`);
        } else {
          this.goToPreviousPage();
          logger.info(TAG, `左侧区域点击：LTR 模式返回上一页，方向=${deviceOrientation}`);
        }
      } else if (clickX > rightZoneStart) {
        // 右侧区域
        if (isRTL) {
          this.goToPreviousPage();
          logger.info(TAG, `右侧区域点击：RTL 模式返回上一页，方向=${deviceOrientation}`);
        } else {
          this.goToNextPage();
          logger.info(TAG, `右侧区域点击：LTR 模式进入下一页，方向=${deviceOrientation}`);
        }
      } else {
        // 中央区域
        this.toggleToolbars();
        logger.info(TAG, `中央区域点击切换工具栏: 方向=${deviceOrientation}, 状态=${this.showTopToolbar ? '显示' : '隐藏'}`);
      }
    }
  }

  /**
   * 处理单页模式的点击事件
    */
  private handleSinglePageTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const centerAreaRatio = 0.4;// 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2;// 两侧各占比 = 0.3
    
    // 上下翻页模式
    if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
        (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM)) {
      // 垂直阅读：上 | 中 | 下
      const effectiveHeight = this.componentHeight > 0 ? this.componentHeight : displayHeight;
      const topZoneEnd = effectiveHeight * sideAreaRatio;
      const bottomZoneStart = effectiveHeight * (1 - sideAreaRatio);
      
      logger.debug(TAG, `垂直模式区域划分: 组件高度=${this.componentHeight.toFixed(0)}vp, 有效高度=${effectiveHeight.toFixed(0)}vp, topZoneEnd=${topZoneEnd.toFixed(0)}vp, bottomZoneStart=${bottomZoneStart.toFixed(0)}vp, clickY=${clickY.toFixed(0)}vp`);
      
      if (clickY < topZoneEnd) {
        this.goToPreviousPage();
        logger.info(TAG, '✋ 上侧区域点击，上一页');
      } else if (clickY > bottomZoneStart) {
        this.goToNextPage();
        logger.info(TAG, '✋ 下侧区域点击，下一页');
      } else {
        this.toggleToolbars();
        logger.info(TAG, `单页上下阅读点击中央区域切换工具栏: 状态=${this.showTopToolbar ? '显示' : '隐藏'}`);
      }
      return;
    }
    
    // 左右翻页模式
    this.handleHorizontalTap(clickX, clickY, deviceOrientation, displayWidth, displayHeight);
  }

  /**
   * 处理水平翻页模式的点击事件
    */
  private handleHorizontalTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const centerAreaRatio = 0.4;// 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2;// 两侧各占比 = 0.3
    
    // 获取有效宽度
    let effectiveWidth: number;
    if (deviceOrientation === 'landscape') {
      effectiveWidth = this.componentWidth > 0 ? this.componentWidth : displayHeight;
    } else if (deviceOrientation === 'square') {
      effectiveWidth = this.componentWidth > 0 ? this.componentWidth : Math.min(displayWidth, displayHeight);
    } else {
      effectiveWidth = this.componentWidth > 0 ? this.componentWidth : displayWidth;
    }
    
    const leftZoneEnd = effectiveWidth * sideAreaRatio;
    const rightZoneStart = effectiveWidth * (1 - sideAreaRatio);
    
    // 判断阅读方向
    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    const isLTR: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.LEFT_TO_RIGHT);
    
    logger.debug(TAG, `${deviceOrientation}模式区域划分: 组件宽度=${this.componentWidth.toFixed(0)}vp, 有效宽度=${effectiveWidth.toFixed(0)}vp, leftZoneEnd=${leftZoneEnd.toFixed(0)}vp, rightZoneStart=${rightZoneStart.toFixed(0)}vp, clickX=${clickX.toFixed(0)}vp, isRTL=${isRTL}, isLTR=${isLTR}`);
    
    if (clickX < leftZoneEnd) {
      // 左侧区域
      if (isRTL) {
        this.goToNextPage();
        logger.info(TAG, `左侧区域点击：RTL 模式进入下一页，方向=${deviceOrientation}`);
      } else {
        this.goToPreviousPage();
        logger.info(TAG, `左侧区域点击：LTR 模式返回上一页，方向=${deviceOrientation}`);
      }
    } else if (clickX > rightZoneStart) {
      // 右侧区域
      if (isRTL) {
        this.goToPreviousPage();
        logger.info(TAG, `右侧区域点击：RTL 模式返回上一页，方向=${deviceOrientation}`);
      } else {
        this.goToNextPage();
        logger.info(TAG, `右侧区域点击：LTR 模式进入下一页，方向=${deviceOrientation}`);
      }
    } else {
      // 中央区域
      this.toggleToolbars();
      logger.info(TAG, `中央区域点击切换工具栏: 方向=${deviceOrientation}, 状态=${this.showTopToolbar ? '显示' : '隐藏'}`);
    }
  }

  /**
   * 处理双击
    */
  private handleDoubleTap(event: ClickEvent): void {
    // 缩放功能
    if (this.readerState.zoomScale === 1.0) {
      this.readerState.zoomScale = 2.0;
    } else {
      this.readerState.zoomScale = 1.0;
    }
    // 交互触发：暂停自动翻页1s
    this.delayAutoPageTurnForInteraction();
  }

  /**
   * 切换工具栏显示状态
    */
  private toggleToolbars(): void {
    const willShow: boolean = !this.showTopToolbar;
    if (willShow) {
      this.showToolbarsWithAnimation();
      this.startAutoHideTimer();
    } else {
      this.hideToolbarsWithAnimation();
      this.scheduleFullscreenRestore('hide_toolbar', 240);
    }
  }

  /**
   * 启动自动隐藏定时器
    */
  private startAutoHideTimer(): void {
    if (this.autoHideTimer !== -1) {
      clearTimeout(this.autoHideTimer);
    }
    
    this.autoHideTimer = setTimeout(() => {
      if (this.showTopToolbar) {
        this.toggleToolbars();
      }
    }, 3000);// 3秒后自动隐藏
  }

  /**
   * 返回上一页
    */
  private async goBack(): Promise<void> {
    try {
      const shouldUseTransition = this.shouldUseReaderTransition(this.pageParams);
      // Build cover component id used by close animation.
      const mangaId = this.readerState.currentManga?.id || '';
      const coverComponentId = this.pageParams?.coverComponentId || (mangaId ? `cover_manga_lib_${mangaId}` : '');

      // Save progress before triggering transition.
      try {
        try {
          await this.persistReadingSettings('go_back');
        } catch (_settingsError) {}
        await this.saveReadingProgressInternal('goBack');
      } catch (saveError) {
        logger.error(TAG, '返回前保存阅读进度失败', saveError instanceof Error ? saveError.message : String(saveError));
      }

      if (!shouldUseTransition) {
        logger.info(TAG, '远程图源阅读器退出时跳过书籍开合转场');
        this.pathStack.pop();
        return;
      }

      logger.info(TAG, `触发关闭过渡动画（带截图），封面组件ID: ${coverComponentId}`);
      await startBookCloseTransitionWithComponentId(
        'manga_reader_root',
        coverComponentId
      );

      // Pop immediately after transition starts so detail page is visible during shrink.
      this.isCloseTransitionNavigating = true;
      this.pathStack.pop();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '返回上一页失败', errorMessage);
      this.isCloseTransitionNavigating = false;
      if (this.shouldUseReaderTransition(this.pageParams)) {
        cancelTransition();
      }
      this.pathStack.pop();
    }
  }


  /**
   * 判断是否为条漫模式
    */
  private isWebtoonMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.WEBTOON ||
           this.readingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
           this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isContinuousScrollMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private isScrollableReaderMode(): boolean {
    return this.isWebtoonMode() || this.isContinuousScrollMode();
  }

  private isReaderProgressRtl(): boolean {
    if (this.isDoublePageVerticalPortraitMode()) {
      return false;
    }
    if (this.getEffectiveDoublePageReadingDirection() !== ReadingDirection.RIGHT_TO_LEFT) {
      return false;
    }
    const mode = this.readingSettings.readingMode;
    return mode === ReadingMode.SINGLE_PAGE ||
      mode === ReadingMode.SINGLE_PAGE_RTL ||
      mode === ReadingMode.DOUBLE_PAGE ||
      this.shouldUseLandscapeAutoDoublePage() ||
      mode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private getToolbarTotalPageCount(): number {
    return this.readerState.currentChapter?.totalPages || this.readerState.currentChapter?.pages.length || 0;
  }

  /**
   * 滚动到条漫模式的指定页面
   * 滚动到条漫模式的指定页面
   * 使用平滑滚动实现信息流式的翻页效果
    */
  private scrollToWebtoonPage(pageIndex: number): void {
    if (!this.readerState.currentChapter || pageIndex < 0 || pageIndex >= this.readerState.currentChapter.pages.length) {
      logger.warn(TAG, `无效的页面索引: ${pageIndex}`);
      return;
    }
    
    logger.debug(TAG, `条漫模式滚动到页面: ${pageIndex + 1}`);
    
    // 使用MangaViewer的平滑滚动功能代替强制重新渲染
    if (this.mangaViewerComponent && this.mangaViewerComponent.smoothScrollToPage) {
    // 使用MangaViewer的平滑滚动功能代替强制重新渲染
      // 根据自动翻页间隔计算滚动速度，实现更自然的节奏
      const scrollSpeed = Math.max(0.5, Math.min(2.0, 5000 / this.readingSettings.autoPageTurnInterval));
      
      // 对于自动翻页，我们需要立即更新页面索引，然后执行平滑滚动
      const currentIndex = this.readerState.currentPageIndex;
      this.readerState.currentPageIndex = pageIndex;
      
      // 调用MangaViewer的平滑滚动到指定页面的方法
      const success = this.mangaViewerComponent.smoothScrollToPage(pageIndex, scrollSpeed);
      if (success) {
        logger.debug(TAG, `条漫模式平滑滚动成功: 页面${currentIndex + 1} -> ${pageIndex + 1}, 速度: ${scrollSpeed}x`);
      } else {
        logger.warn(TAG, '条漫平滑滚动失败，回退到直接更新页码');
        // 回退到传统方法（仅在不支持平滑滚动时使用）
        this.readerState.currentPageIndex = pageIndex;
      }
    } else if (this.mangaViewerComponent && this.mangaViewerComponent.smoothScrollToNextPage) {
      // 回退到旧的平滑滚动方法
      const scrollSpeed = Math.max(0.5, Math.min(2.0, 5000 / this.readingSettings.autoPageTurnInterval));
      const scrollMode = this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 'screen' : 'page';
      
      const currentIndex = this.readerState.currentPageIndex;
      this.readerState.currentPageIndex = pageIndex;
      
      const success = this.mangaViewerComponent.smoothScrollToNextPage(scrollSpeed, scrollMode);
      if (success) {
        logger.debug(TAG, `条漫模式平滑滚动成功: 页面${currentIndex + 1} -> ${pageIndex + 1}, 模式: ${scrollMode}, 速度: ${scrollSpeed}x`);
      } else {
        logger.warn(TAG, '条漫平滑滚动失败，回退到直接更新页码');
        this.readerState.currentPageIndex = pageIndex;
      }
    } else {
      logger.warn(TAG, '漫画阅读组件未初始化或不支持平滑滚动，使用传统翻页');
      // 传统方法作为后备方案
      this.readerState.currentPageIndex = pageIndex;
    }
  }

  /**
   * 翻到上一页
    */
  private goToPreviousPage(): void {
    const currentChapter = this.readerState.currentChapter;
    const isDoublePage = this.isEffectiveDoublePageMode();
    const targetPageIndex = isDoublePage ? this.getPreviousDoublePagePairStart() : this.readerState.currentPageIndex - 1;

    if (currentChapter && targetPageIndex >= 0) {
      logger.debug(TAG, `${isDoublePage ? '翻到上一对页' : '翻到上一页'}: ${this.readerState.currentPageIndex} -> ${targetPageIndex}`);
      
      // 根据阅读模式处理不同的翻页逻辑
      if (this.isScrollableReaderMode()) {
      // 根据阅读模式处理不同的翻页逻辑
        if (this.mangaViewerComponent && this.mangaViewerComponent.smoothScrollToPreviousPage) {
          const scrollSpeed = Math.max(0.5, Math.min(2.0, this.readingSettings.autoPageTurnInterval / 5000));
          const scrollMode = this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 'screen' : 'page';
          
          const success = this.mangaViewerComponent.smoothScrollToPreviousPage(scrollSpeed, scrollMode);
          if (success) {
            logger.debug(TAG, `条漫模式平滑向上滚动成功: 页面${this.readerState.currentPageIndex + 1} -> ${targetPageIndex + 1}`);
          } else {
            logger.warn(TAG, '条漫向上一页平滑滚动失败，回退到直接更新索引');
            this.syncReaderPageState(targetPageIndex);
          }
        } else {
          // 回退到传统方法
          this.syncReaderPageState(targetPageIndex);
        }
      } else {
        // 其他模式：触发动画和索引更新
        this.animatePageTransition('previous');
        this.syncReaderPageState(targetPageIndex);
        if (this.isDoublePageVerticalPortraitMode() && this.mangaViewerComponent) {
          this.mangaViewerComponent.syncVerticalDoublePageToPageIndex(targetPageIndex, 'prev_page_button');
        }
      }
      
      // 通过底部按钮翻页也需要保存进度
      this.saveReadingProgressInternal('prevPageButton').catch((error: Error) => {
        logger.error(TAG, '翻到上一页时保存阅读进度失败', error.message);
      });
    } else {
      // 切换到上一章节的最后一页
      // 切换到上一章节的最后一页
      this.saveReadingProgressInternal('beforePrevChapterFromPrevPage').then(() => {
        this.goToPreviousChapter();
      }).catch((error: Error) => {
        logger.error(TAG, '切到上一章节前保存进度失败', error.message);
        this.goToPreviousChapter();
      });
    }
  }

  /**
   * 翻到下一页
   * 翻到下一页
    */
  private goToNextPage(onComplete?: (() => void) | undefined): void {
    const currentChapter = this.readerState.currentChapter;
    const isAutoScroll = !!onComplete;// 判断是否为自动翻页
    const isDoublePage = this.isEffectiveDoublePageMode();
    const targetPageIndex = isDoublePage ? this.getNextDoublePagePairStart() : this.readerState.currentPageIndex + 1;

    if (currentChapter && targetPageIndex >= 0) {
      logger.debug(TAG, `${isDoublePage ? '翻到下一对页' : '翻到下一页'}: ${this.readerState.currentPageIndex} -> ${targetPageIndex}${isAutoScroll ? ' (自动翻页)' : ''}`);
      
      // 根据阅读模式处理不同的翻页逻辑
      if (this.isScrollableReaderMode()) {
      // 根据阅读模式处理不同的翻页逻辑
        if (this.mangaViewerComponent) {
          const scrollSpeed = Math.max(0.5, Math.min(2.0, this.readingSettings.autoPageTurnInterval / 5000));
          const scrollMode = this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 'screen' : 'page';
          
          // 对于自动翻页模式，我们需要同步更新页面索引，然后让平滑滚动处理视觉效果
          if (isAutoScroll) {
          // 对于自动翻页模式，我们需要同步更新页面索引，然后让平滑滚动处理视觉效果
            const success = this.mangaViewerComponent.smoothScrollToNextPage(scrollSpeed, scrollMode, onComplete);
            if (success) {
              logger.debug(TAG, '条漫自动翻页已成功启动下一页滚动');
            } else {
              logger.warn(TAG, `条漫模式自动翻页平滑滚动失败`);
              if (onComplete) { (onComplete as () => void)(); }
            }
          } else {
            // 手动翻页模式：使用传统逻辑
            const success = this.mangaViewerComponent.smoothScrollToNextPage(scrollSpeed, scrollMode, () => {
              this.syncReaderPageState(targetPageIndex);
              if (onComplete) { (onComplete as () => void)(); }
            });
            if (!success) {
              this.syncReaderPageState(targetPageIndex);
              if (onComplete) { (onComplete as () => void)(); }
            }
          }
        } else {
          // 回退到传统方法
          logger.warn(TAG, '漫画阅读组件未就绪，使用传统翻页方法');
          this.syncReaderPageState(targetPageIndex);
          if (onComplete) { (onComplete as () => void)(); }
        }
      } else {
        // 其他模式：触发动画和索引更新
        this.animatePageTransition('next');
        this.syncReaderPageState(targetPageIndex);
        if (this.isDoublePageVerticalPortraitMode() && this.mangaViewerComponent) {
          this.mangaViewerComponent.syncVerticalDoublePageToPageIndex(targetPageIndex, 'next_page_button');
        }
        if (onComplete) { (onComplete as () => void)(); }
      }
      
      // 通过底部按钮翻页也需要保存进度
      this.saveReadingProgressInternal('nextPageButton').catch((error: Error) => {
        logger.error(TAG, '翻到下一页时保存阅读进度失败', error.message);
      });
    } else {
      // 切换到下一章节的第一页
      logger.debug(TAG, `到达章节末尾，切换到下一章节${isAutoScroll ? ' (自动翻页)' : ''}`);
      // 切换到下一章节的第一页
      this.saveReadingProgressInternal('beforeNextChapterFromNextPage').then(() => {
        this.goToNextChapter();
        if (onComplete) { (onComplete as () => void)(); }
      }).catch((error: Error) => {
        logger.error(TAG, '切到下一章节前保存进度失败', error.message);
        this.goToNextChapter();
        if (onComplete) { (onComplete as () => void)(); }
      });
    }
  }

  /**
   * 切换到上一章节
    */
  private goToPreviousChapter(): void {
    const currentManga = this.readerState.currentManga;
    const currentChapter = this.readerState.currentChapter;
    
    if (currentManga && currentChapter) {
      const currentIndex = currentManga.chapters.findIndex(ch => ch.id === currentChapter.id);
      if (currentIndex > 0) {
        const prevChapter = currentManga.chapters[currentIndex - 1];
        
        // 检查上一章节是否已有页面信息
        if (!prevChapter.pages || prevChapter.pages.length === 0) {
          logger.info(TAG, `上一章节 ${prevChapter.title} 无页面信息，开始加载...`);
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          const loadingTargetPageIndex: number = this.getChapterBoundaryEntryIndex(prevChapter, 'prev');
          this.setChapterSwitchPageGuard(prevChapter, loadingTargetPageIndex, 'prev');
          this.syncReaderChapterPageState(prevChapter, loadingTargetPageIndex, true, '正在加载上一章节...');
          
          // 异步加载页面信息
          this.preloadChapterPages(prevChapter).then(async () => {
          // 异步加载页面信息
            if (!prevChapter.pages || prevChapter.pages.length === 0) {
              const errorMsg = `上一章节没有页面数据: ${prevChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.clearChapterSwitchPageGuard('prev_chapter_no_pages');
              this.isReaderInitialized = true;
              this.getUIContext().getPromptAction().showToast({ message: '章节预加载失败' });
              return;
            }
            
            const targetPageIndex: number = await this.resolveChapterSwitchTargetPageIndex(currentManga.id, prevChapter, 'prev');
            
            // 加载成功且有有效页面，原子更新章节与页面索引
            this.setChapterSwitchPageGuard(prevChapter, targetPageIndex, 'prev');
            this.syncReaderChapterPageState(prevChapter, targetPageIndex, false, '');
            this.refreshCurrentMangaBookmarkState('switch_prev_chapter_loaded');
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            this.chapterTick = this.chapterTick + 1;
            this.scheduleChapterSwitchReaderReady(prevChapter, targetPageIndex, 'switch_prev_chapter_loaded');
            logger.info(TAG, `✅ 已切换到上一章节: ${prevChapter.title}，页面数: ${prevChapter.pages.length}, 目标页=${targetPageIndex + 1}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载上一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载上一章节失败: ${error.message}`;
            this.clearChapterSwitchPageGuard('prev_chapter_load_failed');
            this.isReaderInitialized = true;
            this.getUIContext().getPromptAction().showToast({ message: '加载上一章节失败' });
          });
        } else {
          // 已有页面信息，但仍需加载页面数据
          logger.info(TAG, `上一章节 ${prevChapter.title} 已有章节信息，开始加载页面数据...`);
          
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          const loadingTargetPageIndex: number = this.getChapterBoundaryEntryIndex(prevChapter, 'prev');
          this.setChapterSwitchPageGuard(prevChapter, loadingTargetPageIndex, 'prev');
          this.syncReaderChapterPageState(prevChapter, loadingTargetPageIndex, true, `正在加载 ${prevChapter.title}...`);
          
          // 异步加载页面信息
          this.preloadChapterPages(prevChapter).then(async () => {
          // 异步加载页面信息
            if (!prevChapter.pages || prevChapter.pages.length === 0) {
              const errorMsg = `上一章节没有页面数据: ${prevChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.clearChapterSwitchPageGuard('prev_chapter_cached_no_pages');
              this.isReaderInitialized = true;
              this.getUIContext().getPromptAction().showToast({ message: '章节预加载失败' });
              return;
            }
            
            const targetPageIndex: number = await this.resolveChapterSwitchTargetPageIndex(currentManga.id, prevChapter, 'prev');
            
            // 加载成功，原子更新章节与页面索引
            this.setChapterSwitchPageGuard(prevChapter, targetPageIndex, 'prev');
            this.syncReaderChapterPageState(prevChapter, targetPageIndex, false, '');
            this.refreshCurrentMangaBookmarkState('switch_prev_chapter_cached');
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            // [修复] 触发章节变化通知，让MangaViewer重新加载
            this.chapterTick = this.chapterTick + 1;
            this.scheduleChapterSwitchReaderReady(prevChapter, targetPageIndex, 'switch_prev_chapter_cached');
            logger.info(TAG, `✅ 已切换到上一章节: ${prevChapter.title}，页面数: ${prevChapter.pages.length}, 目标页=${targetPageIndex + 1}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载上一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载上一章节失败: ${error.message}`;
            this.clearChapterSwitchPageGuard('prev_chapter_cached_load_failed');
            this.isReaderInitialized = true;
            this.getUIContext().getPromptAction().showToast({ message: '加载上一章节失败' });
          });
        }
      } else {
        // 已是第一章
        logger.info(TAG, '已是第一章');
        this.getUIContext().getPromptAction().showToast({ message: '当前已是最前' });
      }
    }
  }

  /**
   * 切换到下一章节
    */
  private goToNextChapter(): void {
    const currentManga = this.readerState.currentManga;
    const currentChapter = this.readerState.currentChapter;
    
    if (currentManga && currentChapter) {
      logger.debug(TAG, `🔍 查找下一章: 当前章节="${currentChapter.title}", id="${currentChapter.id}", 总章节数=${currentManga.chapters.length}`);
      
      const currentIndex = currentManga.chapters.findIndex(ch => ch.id === currentChapter.id);
      logger.debug(TAG, `🔍 当前章节索引: ${currentIndex}, 章节列表: ${currentManga.chapters.map((ch, idx) => `[${idx}]${ch.title}`).join(', ')}`);
      
      if (currentIndex < 0) {
        logger.error(TAG, `❌ 未找到当前章节: ${currentChapter.title} (${currentChapter.id})`);
        this.getUIContext().getPromptAction().showToast({ message: '章节索引错误' });
        return;
      }
      
      if (currentIndex < currentManga.chapters.length - 1) {
        const nextChapter = currentManga.chapters[currentIndex + 1];
        
        // 检查下一章节是否已有页面信息
        if (!nextChapter.pages || nextChapter.pages.length === 0) {
          logger.info(TAG, `下一章节 ${nextChapter.title} 无页面信息，开始加载...`);
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          const loadingTargetPageIndex: number = this.getChapterBoundaryEntryIndex(nextChapter, 'next');
          this.setChapterSwitchPageGuard(nextChapter, loadingTargetPageIndex, 'next');
          this.syncReaderChapterPageState(nextChapter, loadingTargetPageIndex, true, '正在加载下一章节...');
          
          // 异步加载页面信息
          this.preloadChapterPages(nextChapter).then(async () => {
          // 异步加载页面信息
            if (!nextChapter.pages || nextChapter.pages.length === 0) {
              const errorMsg = `下一章节没有页面数据: ${nextChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.clearChapterSwitchPageGuard('next_chapter_no_pages');
              this.isReaderInitialized = true;
              this.getUIContext().getPromptAction().showToast({ message: '章节预加载失败' });
              return;
            }
            
            const targetPageIndex: number = await this.resolveChapterSwitchTargetPageIndex(currentManga.id, nextChapter, 'next');
            
            // 加载成功且有有效页面，原子更新章节与页面索引
            this.setChapterSwitchPageGuard(nextChapter, targetPageIndex, 'next');
            this.syncReaderChapterPageState(nextChapter, targetPageIndex, false, '');
            this.refreshCurrentMangaBookmarkState('switch_next_chapter_loaded');
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            this.chapterTick = this.chapterTick + 1;
            this.scheduleChapterSwitchReaderReady(nextChapter, targetPageIndex, 'switch_next_chapter_loaded');
            logger.info(TAG, `✅ 已切换到下一章节: ${nextChapter.title}，页面数: ${nextChapter.pages.length}, 目标页=${targetPageIndex + 1}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载下一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载下一章节失败: ${error.message}`;
            this.clearChapterSwitchPageGuard('next_chapter_load_failed');
            this.isReaderInitialized = true;
            this.getUIContext().getPromptAction().showToast({ message: '加载下一章节失败' });
          });
        } else {
          // 已有页面信息，但仍需加载页面数据
          logger.info(TAG, `下一章节 ${nextChapter.title} 已有章节信息，开始加载页面数据...`);
          
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          const loadingTargetPageIndex: number = this.getChapterBoundaryEntryIndex(nextChapter, 'next');
          this.setChapterSwitchPageGuard(nextChapter, loadingTargetPageIndex, 'next');
          this.syncReaderChapterPageState(nextChapter, loadingTargetPageIndex, true, `正在加载 ${nextChapter.title}...`);
          
          // 异步加载页面信息
          this.preloadChapterPages(nextChapter).then(async () => {
          // 异步加载页面信息
            if (!nextChapter.pages || nextChapter.pages.length === 0) {
              const errorMsg = `下一章节没有页面数据: ${nextChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.clearChapterSwitchPageGuard('next_chapter_cached_no_pages');
              this.isReaderInitialized = true;
              this.getUIContext().getPromptAction().showToast({ message: '章节预加载失败' });
              return;
            }
            
            const targetPageIndex: number = await this.resolveChapterSwitchTargetPageIndex(currentManga.id, nextChapter, 'next');
            
            // 加载成功，原子更新章节与页面索引
            this.setChapterSwitchPageGuard(nextChapter, targetPageIndex, 'next');
            this.syncReaderChapterPageState(nextChapter, targetPageIndex, false, '');
            this.refreshCurrentMangaBookmarkState('switch_next_chapter_cached');
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            // [修复] 触发章节变化通知，让MangaViewer重新加载
            this.chapterTick = this.chapterTick + 1;
            this.scheduleChapterSwitchReaderReady(nextChapter, targetPageIndex, 'switch_next_chapter_cached');
            logger.info(TAG, `✅ 已切换到下一章节: ${nextChapter.title}，页面数: ${nextChapter.pages.length}, 目标页=${targetPageIndex + 1}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载下一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载下一章节失败: ${error.message}`;
            this.clearChapterSwitchPageGuard('next_chapter_cached_load_failed');
            this.isReaderInitialized = true;
            this.getUIContext().getPromptAction().showToast({ message: '加载下一章节失败' });
          });
        }
      } else {
        // 已是最后一章
        logger.info(TAG, '已是最后一章');
        this.getUIContext().getPromptAction().showToast({ message: '当前已是最后' });
      }
    }
  }

  /**
   * 构建翻页动画按钮
    */
  @Builder
  buildVerticalDoublePageAnimationLockPanel() {
    Column({ space: 8 }) {
      Column() {
        Text('上下专属')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.accent_background'))
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)

      Text('当前上下双页只支持触顶/触底专属动画，其他翻页动画已锁定。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildAnimButton(label: string, type: PageTurnAnimationType) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.readingSettings.pageTurnAnimation === type ? 
          $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .width('31%')
    .padding(10)
    .backgroundColor(this.readingSettings.pageTurnAnimation === type ? 
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.readingSettings.pageTurnAnimation = this.normalizePageTurnAnimationForMode(
        type,
        this.readingSettings.readingMode,
        this.readingSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
      );
      this.handleSettingsChange(this.readingSettings);
      logger.info(TAG, `翻页动画已更改为: ${this.readingSettings.pageTurnAnimation}`);
    })
  }

  /**
   * 添加当前漫画书签
   */
  private getCurrentMangaBookmarkContext(): MangaBookmarkContext | null {
    const mangaId = this.readerState.currentManga?.id || this.pageParams?.mangaId || '';
    const chapter = this.readerState.currentChapter;
    if (!mangaId || !chapter) {
      return null;
    }
    const chapterIndex = this.readerState.currentManga?.chapters.findIndex((item: MangaChapter) => item.id === chapter.id) ?? -1;
    const currentPage = Math.max(0, this.readerState.currentPageIndex);
    const totalPages = chapter.totalPages || chapter.pages.length || 0;
    const chapterTitle = chapter.title || `第${chapterIndex + 1}话`;
    return {
      mangaId,
      chapter,
      chapterIndex,
      currentPage,
      totalPages,
      chapterTitle
    };
  }

  private buildMangaBookmarkTitle(context: MangaBookmarkContext): string {
    const pageLabel = context.totalPages > 0
      ? `${context.currentPage + 1}/${context.totalPages}`
      : `${context.currentPage + 1}`;
    return `${context.chapterTitle} · P${pageLabel}`;
  }

  private buildCurrentMangaBookmarkAnchor(context: MangaBookmarkContext): AnnotationAnchor {
    return {
      chapterId: context.chapter.id,
      chapterTitle: context.chapterTitle,
      chapterIndex: context.chapterIndex,
      pageIndex: context.currentPage,
      progress: context.totalPages > 0 ? Math.max(0, Math.min(1, (context.currentPage + 1) / context.totalPages)) : -1
    };
  }

  private refreshCurrentMangaBookmarkState(trigger: string): void {
    void this.refreshCurrentMangaBookmarkStateInternal(trigger);
  }

  private syncReaderPageState(currentPageIndex: number): void {
    this.readerState = {
      currentManga: this.readerState.currentManga,
      currentChapter: this.readerState.currentChapter,
      currentPageIndex: currentPageIndex,
      isFullscreen: this.readerState.isFullscreen,
      showControls: this.readerState.showControls,
      isLoading: this.readerState.isLoading,
      loadingMessage: this.readerState.loadingMessage,
      zoomScale: this.readerState.zoomScale,
      errorMessage: this.readerState.errorMessage
    };
  }

  private syncReaderChapterPageState(chapter: MangaChapter, currentPageIndex: number, isLoading: boolean, loadingMessage: string): void {
    this.readerState = {
      currentManga: this.readerState.currentManga,
      currentChapter: chapter,
      currentPageIndex: currentPageIndex,
      isFullscreen: this.readerState.isFullscreen,
      showControls: this.readerState.showControls,
      isLoading: isLoading,
      loadingMessage: loadingMessage,
      zoomScale: this.readerState.zoomScale,
      errorMessage: ''
    };
  }

  private async refreshCurrentMangaBookmarkStateInternal(trigger: string): Promise<void> {
    const context = this.getCurrentMangaBookmarkContext();
    if (!context) {
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      return;
    }
    try {
      const bookmarks = await this.annotationManager.getContentAnnotations(
        UnifiedContentType.MANGA,
        context.mangaId,
        UnifiedAnnotationType.BOOKMARK,
        context.chapter.id,
        context.chapterIndex
      );
      let matchedId = '';
      for (let i = 0; i < bookmarks.length; i++) {
        const item = bookmarks[i];
        if (item.pageIndex >= 0 && item.pageIndex === context.currentPage) {
          matchedId = item.id;
          break;
        }
      }
      this.currentPageBookmarkId = matchedId;
      this.isCurrentPageBookmarked = matchedId.length > 0;
      logger.debug(
        TAG,
        `刷新漫画书签状态: 触发源=${trigger}, 章节索引=${context.chapterIndex}, 页索引=${context.currentPage}, 已加书签=${this.isCurrentPageBookmarked}, 书签ID=${matchedId || '无'}`
      );
    } catch (error) {
      logger.error(TAG, `刷新漫画书签状态失败: 触发源=${trigger}, 错误=${String(error)}`);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
    }
  }

  /**
   * 分享当前页面图片（系统安全分享）
   */
  private async shareCurrentPageImage(): Promise<void> {
    try {
      const chapter = this.readerState.currentChapter;
      const pageIndex = this.readerState.currentPageIndex;
      if (!chapter || !chapter.pages || pageIndex < 0 || pageIndex >= chapter.pages.length) {
        logger.error(TAG, '无法分享：当前页面无效');
        AlertDialog.show({ message: '无法分享：当前页面无效' });
        return;
      }

      const currentPage = chapter.pages[pageIndex];
      const imagePath = currentPage.imagePath;
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        logger.warn(TAG, `当前页为网络图片，无法直接分享: ${imagePath}`);
        AlertDialog.show({ message: '当前页为网络图片，请先缓存后再分享' });
        return;
      }
      if (!imagePath.startsWith('/')) {
        logger.error(TAG, `无法分享：图片路径无效: ${imagePath}`);
        AlertDialog.show({ message: '分享失败：图片路径无效' });
        return;
      }

      const context = getContext(this) as common.UIAbilityContext;
      const shareUri = fileUri.getUriFromPath(imagePath);
      const title = `${this.readerState.currentManga?.title || '漫画'} 第${pageIndex + 1}页`;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.JPEG,
        uri: shareUri,
        title: title,
        description: title
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      logger.info(TAG, `分享当前页面成功: page=${pageIndex + 1}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `分享当前页面失败: ${errorMessage}`);
      AlertDialog.show({ message: `分享失败: ${errorMessage}` });
    }
  }

  private async createCurrentMangaBookmark(): Promise<void> {
    const context = this.getCurrentMangaBookmarkContext();
    if (!context) {
      promptAction.showToast({ message: '漫画信息未就绪' });
      return;
    }
    try {
      const bookmark = await this.annotationManager.createBookmark({
        contentType: UnifiedContentType.MANGA,
        contentId: context.mangaId,
        title: this.buildMangaBookmarkTitle(context),
        anchor: this.buildCurrentMangaBookmarkAnchor(context)
      });
      this.currentPageBookmarkId = bookmark.id;
      this.isCurrentPageBookmarked = true;
      promptAction.showToast({ message: '书签已添加' });
      logger.info(
        TAG,
        `漫画书签添加成功: chapterIndex=${context.chapterIndex}, pageIndex=${context.currentPage}, bookmarkId=${bookmark.id}`
      );
    } catch (error) {
      logger.error(TAG, `添加漫画书签失败: ${String(error)}`);
      promptAction.showToast({ message: '添加书签失败' });
    }
  }

  private async removeCurrentMangaBookmark(): Promise<void> {
    let bookmarkId = this.currentPageBookmarkId;
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      await this.refreshCurrentMangaBookmarkStateInternal('remove_before_refresh');
      bookmarkId = this.currentPageBookmarkId;
    }
    if (!bookmarkId || bookmarkId.trim().length <= 0) {
      promptAction.showToast({ message: '当前页暂无书签' });
      return;
    }
    try {
      await this.annotationManager.deleteAnnotation(bookmarkId);
      this.currentPageBookmarkId = '';
      this.isCurrentPageBookmarked = false;
      promptAction.showToast({ message: '书签已移除' });
      logger.info(TAG, `漫画书签移除成功: bookmarkId=${bookmarkId}`);
    } catch (error) {
      logger.error(TAG, `移除漫画书签失败: ${String(error)}`);
      promptAction.showToast({ message: '移除书签失败' });
    }
  }

  private toggleCurrentMangaBookmark(): void {
    if (this.isCurrentPageBookmarked) {
      void this.removeCurrentMangaBookmark();
      return;
    }
    void this.createCurrentMangaBookmark();
  }

  private addCurrentMangaBookmark(): void {
    this.toggleCurrentMangaBookmark();
  }

  private openCurrentMangaAnnotationCenter(): void {
    const manga = this.readerState.currentManga;
    const mangaId = manga?.id || this.pageParams?.mangaId || '';
    if (!mangaId) {
      promptAction.showToast({ message: '漫画信息未就绪' });
      return;
    }
    const params: AnnotationCenterPageParams = {
      contentType: UnifiedContentType.MANGA,
      contentId: mangaId,
      contentTitle: manga?.title || '',
      readerContext: {
        manga: {
          sourceId: this.currentSourceId > 0 ? this.currentSourceId : undefined,
          sourceName: this.pageParams?.sourceName,
          contentType: this.normalizeAnnotationCenterMangaContentType(this.pageParams?.contentType),
          chapterId: this.readerState.currentChapter?.id,
          pageIndex: this.readerState.currentPageIndex
        }
      }
    };
    try {
      PageWindowCoordinator.navigateWithManagedTransition(
        'MangaReaderPage',
        'AnnotationCenterPage',
        () => {
          try {
            this.pathStack.pushPathByName('AnnotationCenterPage', params);
          } catch (error) {
            logger.error(TAG, `打开灵感页面失败: ${String(error)}`);
            promptAction.showToast({ message: '打开灵感页面失败' });
          }
        },
        this.getUIContext()
      );
    } catch (error) {
      logger.error(TAG, `打开灵感页面失败: ${String(error)}`);
      promptAction.showToast({ message: '打开灵感页面失败' });
    }
  }

  private getToolbarIconColor(isActive: boolean = false) {
    if (this.themeManager.isDarkThemeSync()) {
      return Color.White;
    }
    return isActive ? $r('app.color.accent_primary') : $r('app.color.text_primary');
  }

  @Builder
  buildTopToolbar() {
    Row() {
            // 条漫模式下需要滚动到对应页面
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontColor([this.getToolbarIconColor()])

      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())

            // 条漫模式下需要滚动到对应页面
      Column() {
        Text(this.readerState.currentManga?.title || '漫画阅读器')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.readerState.currentChapter) {
          Text(this.readerState.currentChapter.title)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .fontFamily(this.appFontFamily)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Button() {
        SymbolGlyph(this.isCurrentPageBookmarked ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontColor([this.getToolbarIconColor(this.isCurrentPageBookmarked)])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addCurrentMangaBookmark();
      })

      Button() {
        SymbolGlyph($r('sys.symbol.stickers'))
          .fontColor([this.getToolbarIconColor()])
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.openCurrentMangaAnnotationCenter();
      })

        // 阅读模式快捷设置按钮
      Button() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontColor([this.getToolbarIconColor()])

      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showMoreMenuWithAnimation();
        })
    }
    .width('100%')
    .height(ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight))
    .padding({ left: 8, right: 8, top: ReaderSafeAreaUtils.getStatusBarInset(this.statusBarHeight) })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
    .id('guide_manga_reader_top_toolbar')
  }

  /**
   * 构建漫画内容区域
    */
  @Builder
  buildBottomToolbar() {
    Column() {
        // 显示效果设置按钮
      Row() {
        if (this.isReaderProgressRtl()) {
          Text(`${this.getToolbarTotalPageCount()}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        } else {
          Text(`${this.readerState.currentPageIndex + 1}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        }

        Slider({
          value: this.readerState.currentPageIndex,
          min: 0,
          max: (this.readerState.currentChapter?.pages.length || 1) - 1,
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .scale({ x: this.isReaderProgressRtl() ? -1 : 1, y: 1 })
          .onChange((value: number) => {
            const targetPage = Math.round(value);
            this.readerState.currentPageIndex = targetPage;
            this.refreshCurrentMangaBookmarkState('toolbar_slider_change');
            
        // 自动翻页设置按钮（最右侧）
            if (this.isScrollableReaderMode() && this.mangaViewerComponent) {
              this.mangaViewerComponent.smoothScrollToPage(targetPage, 1.5);
            }
            
      // 加载状态
            this.saveReadingProgressInternal('sliderChange').catch((error: Error) => {
                logger.error(TAG, '❌ 重试失败：页面参数为空');
            });
          })

        if (this.isReaderProgressRtl()) {
          Text(`${this.readerState.currentPageIndex + 1}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        } else {
          Text(`${this.getToolbarTotalPageCount()}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width(40)
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 加载状态
      Row() {
      // 加载状态
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontColor([this.getToolbarIconColor()])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openTableOfContents();
        })

        Blank()

        // 显示章节名称
        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontColor([this.getToolbarIconColor()])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showQuickSettingsWithAnimation();
        })

        Blank()

      // 错误状态1：加载失败
        Button() {
          SymbolGlyph($r('sys.symbol.circle_on_circle'))
            .fontColor([this.getToolbarIconColor()])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showPageTurnAnimationSettingsWithAnimation();
        })

        Blank()

        // 显示详细错误信息，支持多行显示
        Button() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontColor([this.getToolbarIconColor()])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showSettingsPanelWithAnimation();
        })

        Blank()

                // 重置错误状态
        Button() {
          SymbolGlyph(this.getAutoPageTurnIconResource())
            .fontColor([this.getToolbarIconColor()])

        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.toggleAutoPageTurnSettings();
        })

      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
    .id('guide_manga_reader_bottom_toolbar')
  }


  /**
  * 构建翻页动画按钮
  */
  @Builder
  buildMangaContent() {
    if (this.readerState.isLoading || (!this.isNetworkConfigReady && !this.readerState.errorMessage)) {
      // 错误状态2：章节数据为空
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.accent_primary'))

        Text(this.readerState.loadingMessage || '正在加载章节数据...')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
          .fontFamily(this.appFontFamily)
        
      // 错误状态2：章节数据为空
        if (this.readerState.currentChapter?.title) {
          Text(this.readerState.currentChapter.title)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.7)
            .margin({ top: 8 })
            .maxLines(2)
            .fontFamily(this.appFontFamily)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

    } else if (this.readerState.errorMessage) {
        // 操作按钮组
      Column() {
        Image($r('sys.symbol.exclamationmark_circle_fill'))
          .width(64)
          .height(64)
          .fillColor($r('app.color.color_error'))

        Text('无法获取章节信息，请检查网络连接或返回重试')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
          .fontFamily(this.appFontFamily)

                // 重置状态并重新初始化
        Text(this.readerState.errorMessage)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .padding({ left: 32, right: 32 })
          .maxLines(10)
          .fontFamily(this.appFontFamily)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 正常显示漫画内容
        Row() {
          Button('返回')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_white'))
            .backgroundColor($r('app.color.accent_primary'))
            .onClick(() => {
              logger.info(TAG, '🔙 用户点击返回按钮（章节数据为空）');
              if (this.pageParams) {
      // 正常显示漫画内容
                this.readerState.errorMessage = '';
                this.readerState.isLoading = true;
                this.initializeMangaReader(this.pageParams);
              } else {
                logger.error(TAG, '❌ 重新加载失败：页面参数为空');
              }
            })

          Button('返回')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border_light') })
            .margin({ left: 16 })
            .onClick(() => {
              logger.info(TAG, `返回首页，当前页: ${this.readerState.currentPageIndex + 1}`);
              this.goBack();
            })
        }
        .margin({ top: 24 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

    } else if (!this.readerState.currentChapter) {
              // [修复] 阻止初始化期间的页面变更修改 readerState.currentPageIndex
      Column() {
        Image($r('sys.symbol.exclamationmark_circle_fill'))
          .width(64)
          .height(64)
          .fillColor($r('app.color.color_error'))

        Text('无法获取章节信息，请检查网络连接或返回重试')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
          .fontFamily(this.appFontFamily)

        Text('无法获取章节信息，请检查网络连接或返回重试')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .padding({ left: 32, right: 32 })
          .maxLines(5)
          .fontFamily(this.appFontFamily)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

              // 页面变更后保存阅读进度（限流）
        Row() {
          Button('返回')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_white'))
            .backgroundColor($r('app.color.accent_primary'))
            .onClick(() => {
              logger.info(TAG, `重新加载当前阅读器，当前页: ${this.readerState.currentPageIndex + 1}`);
              if (this.pageParams) {
              // 章节切换前先保存当前章节进度
                this.readerState.currentChapter = null;
                this.readerState.isLoading = true;
                this.initializeMangaReader(this.pageParams);
              } else {
                logger.error(TAG, '重新加载阅读器失败：缺少页面参数');
              }
            })

          Button('返回')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border_light') })
            .margin({ left: 16 })
            .onClick(() => {
              logger.info(TAG, '触发漫画阅读组件预加载');
              this.goBack();
            })
        }
        .margin({ top: 24 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

    } else {
              // 获取MangaViewer组件实例引用
      Stack() {
        MangaViewer({
          chapter: this.readerState.currentChapter as MangaChapter,
          currentPageIndex: this.readerState.currentPageIndex,
          readingSettings: this.getViewerReadingSettings(),
          zoomScale: this.readerState.zoomScale,
          toolbarsVisible: (this.showTopToolbar || this.showBottomToolbar),
          networkHeaders: this.networkHeaders,
          networkHeadersTick: this.networkHeadersTick,
          chapterTick: this.chapterTick,// [新增] 传递章节切换计数器
          sourceId: this.currentSourceId > 0 ? this.currentSourceId : undefined,
          mangaId: this.readerState.currentManga ? this.readerState.currentManga.id : this.pageParams?.mangaId,
          preloadCurrentPages: this.sourcePreloadSettings.preloadCurrentPages,
          preloadNextPages: this.sourcePreloadSettings.preloadNextPages,
          contentType: this.pageParams?.contentType,// [新增] 传递内容类型（用于区分在线/本地漫画）
          preloadDebugInfo: $preloadDebugInfo,// [新增] 传递预加载调试信息
              // [修复] 条漫模式初始化时跳转到阅读记录位置
          prevChapter: this.prevChapterForWebtoon,
          nextChapter: this.nextChapterForWebtoon,
              // [修复] 条漫模式初始化时跳转到阅读记录位置
          isFirstChapter: this.isFirstChapterState,
          isLastChapter: this.isLastChapterState,
          onRequestAdjacentChapter: (direction: 'prev' | 'next') => {
            this.handleWebtoonAdjacentChapterRequest(direction);
          },
          loadPixivImageCallback: async (imageUrl: string): Promise<ArrayBuffer | null> => {
            return await this.loadPixivImage(imageUrl);
          },
          callbacks: {
            onPageChange: (pageIndex: number) => {
              logger.info(TAG, `漫画阅读组件页码变化: ${pageIndex + 1}`);
              
              // 因此直接调用 jumpToPageImmediate 无效。使用 setTimeout 延迟到渲染完成后。
              // 因此直接调用 jumpToPageImmediate 无效。使用 setTimeout 延迟到渲染完成后。
              // 因此直接调用 jumpToPageImmediate 无效。使用 setTimeout 延迟到渲染完成后。
              if (!this.isReaderInitialized) {
                logger.debug(TAG, `漫画阅读组件尚未初始化完成，暂不处理页码变化: ${pageIndex + 1}`);
              // [修复] 延迟设置初始化完成标志，确保 MangaViewer 完全初始化后才允许保存阅读进度
                return;
              }
              if (!this.shouldAcceptPageChangeDuringChapterSwitch(pageIndex)) {
                return;
              }
              
              // [修复] 延迟设置初始化完成标志，确保 MangaViewer 完全初始化后才允许保存阅读进度
              const chapterForPageChange = this.readerState.currentChapter;
              const safePageIndex = chapterForPageChange
                ? this.normalizeReaderPageIndexForChapter(chapterForPageChange, pageIndex)
                : pageIndex;
              this.syncReaderPageState(safePageIndex);
              this.refreshCurrentMangaBookmarkState('viewer_page_change');
              // 使用 setTimeout 确保 MangaViewer 的初始化回调（如 onPageChange）已经执行完毕
              this.delayAutoPageTurnForInteraction();
              this.startAutoHideTimer();
        // 在Stack层捕获点击事件，获取正确的屏幕坐标
              this.saveReadingProgressInternal('onPageChange').catch((error: Error) => {
                logger.error(TAG, '章节切换前保存阅读进度失败', error.message);
              });
        // 在Stack层捕获点击事件，获取正确的屏幕坐标
              this.preloadNextChapterIfNeeded(safePageIndex);
            },
            onChapterChange: (direction: 'prev' | 'next') => {
        // 获取组件实际渲染尺寸（vp单位）
              this.saveReadingProgressInternal('onChapterChange').then(() => {
                if (direction === 'prev') {
                  this.goToPreviousChapter();
                } else {
                  this.goToNextChapter();
                }
              }).catch((error: Error) => {
                logger.error(TAG, '章节切换前保存阅读进度失败', error.message);
                if (direction === 'prev') {
                  this.goToPreviousChapter();
                } else {
                  this.goToNextChapter();
                }
              });
            },
            onZoomChange: (scale: number) => {
              this.readerState.zoomScale = scale;
            },
            onSingleTap: (event: ClickEvent) => {
              this.handlePageTap(event);
            },
            onDoubleTap: (event: ClickEvent) => {
              this.handleDoubleTap(event);
            },
        // 内容层 - 占满全屏，使用安全区 padding 以遵循沉浸式规范
            onWebtoonChapterSwitch: (chapterId: string, chapterTitle: string, pageIndex: number) => {
              this.handleWebtoonChapterSwitch(chapterId, chapterTitle, pageIndex);
            },
            onComponentReady: (component: MangaViewer) => {
          // 漫画内容区域 - 占满全屏
              this.mangaViewerComponent = component;
              logger.info(TAG, '漫画阅读组件已通过回调绑定');
              const pendingKickstart = () => {
                component.kickstartLoading();
                this.waitForTransitionReaderReady('component_ready');
              };
              const chapter = this.readerState.currentChapter;
              const expectedIndex = this.readerState.currentPageIndex;
              
        // 顶部工具栏（悬浮覆盖）
        // 每日限额提示横幅（顶部悬浮）
              const viewerIndex: number = component.getCurrentViewPageIndex();
              logger.debug(TAG, `初始化同步检查当前页: 组件页=${viewerIndex}, 预期页=${expectedIndex}`);
              if (viewerIndex !== expectedIndex && expectedIndex >= 0) {
                logger.info(TAG, `[初始化同步] 发现页码不一致: 组件页=${viewerIndex}, 预期页=${expectedIndex}`);
                component.setPageIndex(expectedIndex);
              } else {
                logger.debug(TAG, '[初始化同步] 当前页与预期页一致，无需校正');
              }
              
        // 每日限额提示横幅（顶部悬浮）
              if (chapter && this.isScrollableReaderMode() && (expectedIndex > 0 || this.isContinuousScrollMode())) {
                setTimeout(() => {
                  if (component.jumpToPageImmediate) {
                    const success = component.jumpToPageImmediate(expectedIndex);
                    if (success) {
                      logger.info(TAG, `[初始化同步] 已立即跳转到目标页: ${expectedIndex + 1}`);
                    } else {
                      logger.warn(TAG, '[初始化同步] 立即跳转失败，回退到条漫页码滚动');
                      this.scrollToWebtoonPage(expectedIndex);
                    }
                  } else {
                    this.scrollToWebtoonPage(expectedIndex);
                  }
                }, 150);
              }
              
        // 底部工具栏（悬浮覆盖，略高于底部）
        // 底部工具栏（悬浮覆盖，略高于底部）
              setTimeout(() => {
                this.isReaderInitialized = true;
                const readyChapter = this.readerState.currentChapter;
                if (readyChapter) {
                  const guard: ChapterSwitchPageGuard | null = this.getActiveChapterSwitchPageGuard(readyChapter);
                  if (guard) {
                    const readyViewerIndex: number = component.getCurrentViewPageIndex();
                    const normalizedViewerIndex: number = this.normalizeReaderPageIndexForChapter(readyChapter, readyViewerIndex);
                    if (normalizedViewerIndex !== guard.pageIndex) {
                      logger.info(TAG, `组件就绪后校正跨章页组: viewer=${readyViewerIndex + 1}, normalized=${normalizedViewerIndex + 1}, expected=${guard.pageIndex + 1}`);
                      component.setPageIndex(guard.pageIndex);
                      if (this.isDoublePageVerticalPortraitMode()) {
                        component.syncVerticalDoublePageToPageIndex(guard.pageIndex, 'component_ready_chapter_guard');
                      }
                    }
                    this.syncReaderPageState(guard.pageIndex);
                    this.clearChapterSwitchPageGuard('component_ready');
                  }
                }
                logger.info(TAG, '漫画阅读组件初始化完成');
              }, 500);
              
              logger.debug(TAG, '漫画阅读组件已就绪');
            }
          }
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
      }
      .width('100%')
      .height('100%')
      .onClick((event: ClickEvent) => {
          // .padding({ bottom: this.navigationBarHeight + 8 })
        this.handlePageTap(event);
      })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 预加载调试 Overlay（在底部工具栏下方）
        // 预加载调试 Overlay（在底部工具栏下方）
        const widthVp = Number(newArea.width);
        const heightVp = Number(newArea.height);
        
        if (widthVp > 0 && heightVp > 0) {
          const widthChanged = Math.abs(widthVp - this.componentWidth) > 1;
          const heightChanged = Math.abs(heightVp - this.componentHeight) > 1;
          this.componentWidth = widthVp;
          this.componentHeight = heightVp;
        // 快速设置面板（带动画）
          this.isLandscapeMode = widthVp > heightVp;
          if ((widthChanged || heightChanged) && this.isPageVisible) {
            this.scheduleFullscreenRestore('area_change', 120);
          }
          logger.debug(TAG, `📐 组件尺寸更新: ${widthVp.toFixed(0)}x${heightVp.toFixed(0)}vp, 横屏=${this.isLandscapeMode}`);
        }
      })
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 快速设置面板（带动画）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .id('guide_manga_reader_root')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 快速设置面板（带动画）
        Column() {
        // 快速设置面板（带动画）
          this.buildMangaContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        // .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })

        // 完整设置面板（带动画）
        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // 完整设置面板（带动画）
        if (this.dailyLimitPromptVisible) {
          Row({ space: 12 }) {
            Text(this.dailyLimitMessage)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank().layoutWeight(1)
              Button('完成')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: $r('app.color.border_light') })
              .onClick(() => {
                logger.info(TAG, '用户关闭每日限额提示横幅');
                this.dailyLimitPromptVisible = false;
              })
          }
          .width('100%')
          .height(44)
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .padding({ left: 16, right: 16, top: this.statusBarHeight })
          .backgroundColor($r('app.color.system_resource_background_overlay'))
          .zIndex(900)
        }

              // 横屏：右侧贴边面板
        if (this.showBottomToolbar) {
          Column() {
            this.buildBottomToolbar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ x: 0, y: '-100%' })
          // .padding({ bottom: this.navigationBarHeight + 8 })
          .zIndex(100)
        }

                  // 标题
        Column() {
          Blank()
          
          if (this.preloadDebugMode === 'always' || 
              (this.preloadDebugMode === 'on' && (this.showTopToolbar || this.showBottomToolbar))) {
            PreloadDebugOverlay({
              debugInfo: $preloadDebugInfo,
              visible: true
            })
              .margin({ left: 16, right: 16, bottom: 80 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(99)

                  // 间隔设置
        if (this.showQuickSettings) {
          MangaQuickSettings({
            readingSettings: this.readingSettings,
            isVisible: this.showQuickSettings,
            callbacks: {
              onSettingsChange: (settings: ReadingSettings) => {
                this.handleSettingsChange(settings);
              },
              onClose: () => {
                this.hideQuickSettingsWithAnimation();
              },
              onOpenFullSettings: () => {
                this.showQuickSettings = false;
                this.showSettingsPanelWithAnimation();
              }
            }
          })
          .opacity(this.quickSettingsOpacity)
          .scale({ x: this.quickSettingsScale, y: this.quickSettingsScale })
          .translate({ y: this.quickSettingsTranslateY })
          .zIndex(1000)
        }
        
                  // 启用开关
        if (this.showSettingsPanel) {
          MangaReaderSettings({
            readingSettings: this.readingSettings,
            isVisible: this.showSettingsPanel,
            callbacks: {
              onSettingsChange: (settings: ReadingSettings) => {
                this.handleSettingsChange(settings);
              },
              onClose: () => {
                this.hideSettingsPanelWithAnimation();
              }
            }
          })
          .opacity(this.settingsPanelOpacity)
          .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
          .translate({ y: this.settingsPanelTranslateY })
          .zIndex(1000)
        }

                  // 启用开关
        if (this.showAutoPageTurnSettings) {
          Stack() {
                  // 启用开关
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('app.color.background_overlay'))
              .opacity(0.5)
              .onClick(() => {
                this.hideAutoPageTurnSettingsWithAnimation();
              })

            if (this.isLandscapeMode) {
              // 竖屏：居中弹窗
              Row() {
              // 竖屏：居中弹窗
                Column()
                  .layoutWeight(1)
                  .height('100%')
                  .onClick(() => {
                    this.hideAutoPageTurnSettingsWithAnimation();
                  })

              // 竖屏：居中弹窗
                Column() {
                // 标题
                  Row() {
                  Text('自动翻页设置')
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .fontFamily(this.appFontFamily)

                    Button() {
                      Image($r('app.media.ic_close'))
                        .width(20)
                        .height(20)
                        .fillColor($r('app.color.text_secondary'))
                    }
                    .width(36)
                    .height(36)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.hideAutoPageTurnSettingsWithAnimation();
                    })
                  }
                  .width('100%')
                  .margin({ bottom: 16 })

                // 间隔设置
                Text('翻页间隔')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .margin({ bottom: 8 })
                    .fontFamily(this.appFontFamily)

                  Row() {
                    Text(`${this.autoPageTurnIntervalSeconds}s`)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.accent'))
                      .width(50)
                      .fontFamily(this.appFontFamily)

                    Slider({
                      value: this.autoPageTurnIntervalSeconds,
                      min: 1,
                      max: 10,
                      step: 1
                    })
                      .layoutWeight(1)
                      .trackColor($r('app.color.divider'))
                      .selectedColor($r('app.color.accent'))
                      .onChange((v: number) => {
                        this.setAutoPageTurnIntervalSeconds(Math.round(v));
                      })
                  }
                  .width('100%')
                  .margin({ bottom: 16 })

                // 启用开关
                  Row() {
                  Text('启用自动翻页')
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .fontFamily(this.appFontFamily)

                    Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
                      .selectedColor($r('app.color.accent'))
                      .onChange((isOn: boolean) => {
                        this.setAutoPageTurnEnabled(isOn);
                      })
                  }
                  .width('100%')
                }
                .width(320)
                .height('100%')
                .padding(16)
                .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
                .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
                .borderRadius({ topLeft: 16, bottomLeft: 16 })
                .opacity(this.autoPageTurnSettingsOpacity)
                .translate({ x: this.autoPageTurnSettingsTranslateX })
                .hitTestBehavior(HitTestMode.Default)
              }
              .width('100%')
              .height('100%')
            } else {
        // 悬浮式章节列表面板
              Column() {
        // 悬浮式章节列表面板
                Row() {
                  Text('启用自动翻页')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .fontFamily(this.appFontFamily)

                  Button() {
                    Image($r('app.media.ic_close'))
                      .width(20)
                      .height(20)
                      .fillColor($r('app.color.text_secondary'))
                  }
                  .width(36)
                  .height(36)
                  .backgroundColor(Color.Transparent)
                  .onClick(() => {
                    this.hideAutoPageTurnSettingsWithAnimation();
                  })
                }
                .width('100%')
                .margin({ bottom: 16 })

            // 点击遮罩关闭
                    Text('更多选项')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })
                  .fontFamily(this.appFontFamily)

                Row() {
                  Text(`${this.autoPageTurnIntervalSeconds}s`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.accent'))
                    .width(50)
                    .fontFamily(this.appFontFamily)

                  Slider({
                    value: this.autoPageTurnIntervalSeconds,
                    min: 1,
                    max: 10,
                    step: 1
                  })
                    .layoutWeight(1)
                    .trackColor($r('app.color.divider'))
                    .selectedColor($r('app.color.accent'))
                    .onChange((v: number) => {
                      this.setAutoPageTurnIntervalSeconds(Math.round(v));
                    })
                }
                .width('100%')
                .margin({ bottom: 16 })

                  // 跳转到页面
                Row() {
                    Text('跳转到页面')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .fontFamily(this.appFontFamily)

                  Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
                    .selectedColor($r('app.color.accent'))
                    .onChange((isOn: boolean) => {
                      this.setAutoPageTurnEnabled(isOn);
                    })
                }
                .width('100%')
              }
              .width('90%')
              .constraintSize({ maxWidth: 400 })
              .padding(20)
              .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
              .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
              .borderRadius(16)
              .opacity(this.autoPageTurnSettingsOpacity)
              .scale({ x: this.autoPageTurnSettingsScale, y: this.autoPageTurnSettingsScale })
              .translate({ y: this.autoPageTurnSettingsTranslateY })
            }
          }
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

                  // 保存本页到图库
        if (this.showChapterList && this.readerState.currentManga) {
          MangaReaderChapterList({
            chapters: this.readerState.currentManga.chapters,
            currentChapterId: this.readerState.currentChapter?.id || '',
            isVisible: this.showChapterList,
            callbacks: {
              onChapterSelect: (chapterId: string) => {
                this.switchToChapter(chapterId);
              },
              onClose: () => {
                this.showChapterList = false;
              }
            }
          })
          .id('guide_manga_reader_chapter_list')
          .zIndex(1000)
        }

              // 竖屏：顶部右侧下拉菜单
        if (this.showMoreMenu) {
          Stack() {
              // 竖屏：顶部右侧下拉菜单
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.isLandscapeMode ? $r('app.color.background_overlay') : Color.Transparent)
              .opacity(this.isLandscapeMode ? 0.5 : 1)
              .onClick(() => {
                this.hideMoreMenuWithAnimation();
              })

            if (this.isLandscapeMode) {
              // 竖屏：顶部右侧下拉菜单
              Row() {
                Column()
                  .layoutWeight(1)
                  .height('100%')
                  .onClick(() => { this.hideMoreMenuWithAnimation(); })

                Column() {
              // 竖屏：顶部右侧下拉菜单
                  Row() {
                  Text('更多选项')
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .fontFamily(this.appFontFamily)

                    Button() {
                      Image($r('app.media.ic_close'))
                        .width(18)
                        .height(18)
                        .fillColor($r('app.color.text_secondary'))
                    }
                    .width(32)
                    .height(32)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => { this.hideMoreMenuWithAnimation(); })
                  }
                  .width('100%')
                  .margin({ bottom: 16 })

        // 跳转到页面对话框
                  Row() {
                    Text('跳转页面')
                      .fontColor($r('app.color.text_primary'))
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                    Blank().layoutWeight(1)
                    Text(`${this.readerState.currentPageIndex + 1}/${this.readerState.currentChapter?.pages.length || 0}`)
                      .fontColor($r('app.color.text_secondary'))
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                  }
                  .height(44)
                  .width('100%')
                  .onClick(() => {
                  logger.info(TAG, '更多菜单：跳转页面');
                    this.hideMoreMenuWithAnimation();
                    setTimeout(() => { this.showJumpToPageDialogWithAnimation(); }, 200);
                  })

                  Divider().color($r('app.color.divider'))

            // 半透明遮罩（显示漫画背景）
                  Row() {
                    Text('保存本张到图库')
                      .fontColor($r('app.color.text_primary'))
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                    Blank().layoutWeight(1)
                  }
                  .height(44)
                  .width('100%')
                  .onClick(() => {
                  logger.info(TAG, '更多菜单：保存当前页到图库');
                    this.hideMoreMenuWithAnimation();
                    this.saveCurrentPageToGallery();
                  })

                  Divider().color($r('app.color.divider'))

                  Row() {
                    Text('分享本张图片')
                      .fontColor($r('app.color.text_primary'))
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                    Blank().layoutWeight(1)
                  }
                  .height(44)
                  .width('100%')
                  .onClick(() => {
                    logger.info(TAG, '更多菜单：分享当前页图片');
                    this.hideMoreMenuWithAnimation();
                    this.shareCurrentPageImage();
                  })
                }
                .width(320)
                .height('100%')
                .padding(16)
                .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
                .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
                .borderRadius({ topLeft: 16, bottomLeft: 16 })
                .opacity(this.moreMenuOpacity)
                .hitTestBehavior(HitTestMode.Default)
              }
              .width('100%')
              .height('100%')
            } else {
                  // 标题栏
              Column() {
                Row() {
                  Text('跳转页面')
                    .fontColor($r('app.color.text_primary'))
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                  Blank().layoutWeight(1)
                  Text(`${this.readerState.currentPageIndex + 1}/${this.readerState.currentChapter?.pages.length || 0}`)
                    .fontColor($r('app.color.text_secondary'))
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                }
                .height(44)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  logger.info(TAG, '更多菜单：跳转页面');
                  this.hideMoreMenuWithAnimation();
                  setTimeout(() => { this.showJumpToPageDialogWithAnimation(); }, 200);
                })

                Divider().color($r('app.color.divider'))

                Row() {
                  Text('保存本张到图库')
                    .fontColor($r('app.color.text_primary'))
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                  Blank().layoutWeight(1)
                }
                .height(44)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  logger.info(TAG, '更多菜单：保存当前页到图库');
                  this.hideMoreMenuWithAnimation();
                  this.saveCurrentPageToGallery();
                })

                Divider().color($r('app.color.divider'))

                Row() {
                  Text('分享本张图片')
                    .fontColor($r('app.color.text_primary'))
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                  Blank().layoutWeight(1)
                }
                .height(44)
                .padding({ left: 16, right: 16 })
                .onClick(() => {
                  logger.info(TAG, '更多菜单：分享当前页图片');
                  this.hideMoreMenuWithAnimation();
                  this.shareCurrentPageImage();
                })
              }
              .backgroundColor(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.MENU).backgroundColorResource)
              .backgroundBlurStyle(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.MENU).blurStyle)
              .borderRadius(ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.MENU).radius)
              .shadow({ radius: ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.MENU).radius, color: ThemeManager.getInstance().getGlassEffectOptions(GlassEffectContext.MENU).shadowColor, offsetX: 0, offsetY: 4 })
              .opacity(this.moreMenuOpacity)
              .scale({ x: this.moreMenuScale, y: this.moreMenuScale })
              .translate({ y: this.moreMenuTranslateY })
              .align(Alignment.TopEnd)
              .margin({ top: ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight) + 8, right: 12 })
              .constraintSize({ maxWidth: 260 })
              .zIndex(1100)
            }
          }
          .width('100%')
          .height('100%')
          .zIndex(1100)
        }

              // 竖屏：居中对话框
        if (this.showJumpToPageDialog) {
          Stack() {
              // 竖屏：居中对话框
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#80000000')
              .opacity(this.jumpToPageDialogOpacity)
              .onClick(() => {
                this.hideJumpToPageDialogWithAnimation();
              })

            if (this.isLandscapeMode) {
              // 竖屏：居中对话框
              Row() {
                Column()
                  .layoutWeight(1)
                  .height('100%')
                  .onClick(() => {
                    this.hideJumpToPageDialogWithAnimation();
                  })

                Column() {
              // 竖屏：居中对话框
                  Row() {
                    Text('跳转到指定页')
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .fontFamily(this.appFontFamily)

                    Button() {
                      Image($r('app.media.ic_close'))
                        .width(20)
                        .height(20)
                        .fillColor($r('app.color.text_secondary'))
                    }
                    .width(36)
                    .height(36)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.hideJumpToPageDialogWithAnimation();
                    })
                  }
                  .width('100%')
                  .margin({ bottom: 16 })

                  Text(`当前: ${this.readerState.currentPageIndex + 1} / ${this.readerState.currentChapter?.pages.length || 0}`)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .fontFamily(this.appFontFamily)
                    .margin({ bottom: 16 })

                  TextInput({ placeholder: '输入页码', text: this.jumpToPageInput })
                    .type(InputType.Number)
                    .width('100%')
                    .height(44)
                    .fontSize(16)
                    .onChange((value: string) => {
                      this.jumpToPageInput = value;
                    })
                    .margin({ bottom: 16 })

                  Row({ space: 12 }) {
                  Button('跳转')
                      .layoutWeight(1)
                      .height(40)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor($r('app.color.text_secondary'))
                      .backgroundColor($r('app.color.background_secondary'))
                      .onClick(() => {
                        this.hideJumpToPageDialogWithAnimation();
                      })

                  Button('跳转')
                      .layoutWeight(1)
                      .height(40)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor($r('app.color.text_on_accent'))
                      .backgroundColor($r('app.color.accent'))
                      .onClick(() => {
                        const pageNum = parseInt(this.jumpToPageInput);
                        if (!isNaN(pageNum)) {
                          this.jumpToPage(pageNum);
                        }
                      })
                  }
                  .width('100%')
                }
                .width(320)
                .height('100%')
                .padding(16)
                .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
                .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
                .borderRadius({ topLeft: 16, bottomLeft: 16 })
                .opacity(this.jumpToPageDialogOpacity)
                .hitTestBehavior(HitTestMode.Default)
              }
              .width('100%')
              .height('100%')
            } else {
              // 标题
              Column({ space: 16 }) {
                Text('跳转到指定页面')
                  .fontSize(18)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))

                Text(`当前: ${this.readerState.currentPageIndex + 1} / ${this.readerState.currentChapter?.pages.length || 0}`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .fontFamily(this.appFontFamily)

                TextInput({ placeholder: '输入页码', text: this.jumpToPageInput })
                  .type(InputType.Number)
                  .width('100%')
                  .height(44)
                  .fontSize(16)
                  .onChange((value: string) => {
                    this.jumpToPageInput = value;
                  })

                Row({ space: 12 }) {
                  Button('取消')
                    .layoutWeight(1)
                    .height(40)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.text_secondary'))
                    .backgroundColor($r('app.color.background_secondary'))
                    .onClick(() => {
                      this.hideJumpToPageDialogWithAnimation();
                    })

                  Button('跳转')
                    .layoutWeight(1)
                    .height(40)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.text_on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .onClick(() => {
                      const pageNum = parseInt(this.jumpToPageInput);
                      if (!isNaN(pageNum)) {
                        this.jumpToPage(pageNum);
                      }
                    })
                }
                .width('100%')
              }
              .width('80%')
              .constraintSize({ maxWidth: 320 })
              .padding(20)
              .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
              .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
              .borderRadius(16)
              .opacity(this.jumpToPageDialogOpacity)
              .scale({ x: this.jumpToPageDialogScale, y: this.jumpToPageDialogScale })
            }
          }
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

                      // 拟真动画
        if (this.showPageTurnAnimationSettings) {
          Stack() {
                      // 拟真动画
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('app.color.background_overlay'))
              .opacity(0.5)
              .onClick(() => {
                this.hidePageTurnAnimationSettingsWithAnimation();
              })

            if (this.isLandscapeMode) {
                      // 拟真动画
              Row() {
                Column()
                  .layoutWeight(1)
                  .height('100%')
                  .onClick(() => {
                    this.hidePageTurnAnimationSettingsWithAnimation();
                  })

                Column() {
                      // 拟真动画
                  Row() {
                            Text('翻页动画设置')
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                      .fontFamily(this.appFontFamily)

                    Button() {
                      Image($r('app.media.ic_close'))
                        .width(20)
                        .height(20)
                        .fillColor($r('app.color.text_secondary'))
                    }
                    .width(36)
                    .height(36)
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.hidePageTurnAnimationSettingsWithAnimation();
                    })
                  }
                  .width('100%')
                  .margin({ bottom: 16 })

                  Scroll() {
                    Column() {
              // 竖屏：居中面板
                            Text('选择翻页动画')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                        .margin({ bottom: 8 })
                        .fontFamily(this.appFontFamily)

                      if (this.isDoublePageVerticalAnimationLockedForSettings()) {
                        this.buildVerticalDoublePageAnimationLockPanel()
                      } else {
                      Row() {
                        this.buildAnimButton('无', PageTurnAnimationType.NONE)
                        this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
                        this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.SpaceBetween)
                      .margin({ bottom: 8 })

                      Row() {
                        this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
                        this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
                        this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.SpaceBetween)
                      .margin({ bottom: 16 })

                // 标题
                  Text('卷页参数')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                        .margin({ bottom: 8 })
                        .fontFamily(this.appFontFamily)

                      Row() {
                        if (this.isCurlAnimationSupported()) {
                          this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
                        } else {
                          Column() {
                  Text('卷页模式')
                              .fontSize(13)
                              .fontColor($r('app.color.text_secondary'))
                              .fontFamily(this.appFontFamily)
                Text('设备不支持')
                              .fontSize(10)
                              .fontColor($r('app.color.text_secondary'))
                              .margin({ top: 2 })
                              .fontFamily(this.appFontFamily)
                          }
                          .width(100)
                          .height(50)
                          .backgroundColor($r('app.color.background_secondary'))
                          .borderRadius(8)
                          .justifyContent(FlexAlign.Center)
                          .opacity(0.5)
                        }
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.Start)

                      if (this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL && this.isCurlAnimationSupported()) {
                        Column() {
                          Row() {
                            Text('卷页背面透明度')
                              .fontSize(14)
                              .fontColor($r('app.color.text_secondary'))
                              .fontFamily(this.appFontFamily)
                            Text(`${this.readingSettings.curlBackOpacity ?? 90}%`)
                              .fontSize(14)
                              .fontColor($r('app.color.accent'))
                              .fontFamily(this.appFontFamily)
                          }
                          .width('100%')
                          .justifyContent(FlexAlign.SpaceBetween)
                          .margin({ top: 16, bottom: 8 })

                          Slider({
                            value: this.readingSettings.curlBackOpacity ?? 90,
                            min: 0,
                            max: 100,
                            step: 5,
                            style: SliderStyle.OutSet
                          })
                            .blockColor($r('app.color.accent'))
                            .trackColor($r('app.color.background_secondary'))
                            .selectedColor($r('app.color.accent'))
                            .onChange((value: number) => {
                              this.readingSettings.curlBackOpacity = value;
                              this.handleSettingsChange(this.readingSettings);
                            })
                        }
                        .width('100%')
                      }
                      }
                    }
                    .width('100%')
                  }
                  .layoutWeight(1)
                  .scrollBar(BarState.Off)
                }
                .width(320)
                .height('100%')
                .padding(16)
                .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
                .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
                .borderRadius({ topLeft: 16, bottomLeft: 16 })
                .opacity(this.pageTurnAnimationSettingsOpacity)
                .translate({ x: this.pageTurnAnimationSettingsTranslateX })
                .hitTestBehavior(HitTestMode.Default)
              }
              .width('100%')
              .height('100%')
            } else {
                // 卷页透明度设置（仅在选择卷页动画且模式支持时显示）
              Column() {
                // 卷页透明度设置（仅在选择卷页动画且模式支持时显示）
                Row() {
                      Text('翻页动画设置')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .fontFamily(this.appFontFamily)

                  Button() {
                    Image($r('app.media.ic_close'))
                      .width(20)
                      .height(20)
                      .fillColor($r('app.color.text_secondary'))
                  }
                  .width(36)
                  .height(36)
                  .backgroundColor(Color.Transparent)
                  .onClick(() => {
                    this.hidePageTurnAnimationSettingsWithAnimation();
                  })
                }
                .width('100%')
                .margin({ bottom: 16 })

                // 卷页透明度设置（仅在选择卷页动画且模式支持时显示）
                      Text('选择翻页动画')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })
                  .fontFamily(this.appFontFamily)

                if (this.isDoublePageVerticalAnimationLockedForSettings()) {
                  this.buildVerticalDoublePageAnimationLockPanel()
                } else {
        // 交互区域提示overlay（最高层级）
                Row() {
                  this.buildAnimButton('无', PageTurnAnimationType.NONE)
                  this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
                  this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ bottom: 8 })

        // 交互区域提示overlay（最高层级）
                Row() {
                  this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
                  this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
                  this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ bottom: 16 })

        // 确保与handleHorizontalTap等交互判断使用相同的尺寸来源
                      Text('卷页参数')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .margin({ bottom: 8 })
                  .fontFamily(this.appFontFamily)

        // 确保与handleHorizontalTap等交互判断使用相同的尺寸来源
                Row() {
                  if (this.isCurlAnimationSupported()) {
                    this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
                  } else {
        // 调试：点击位置指示器（已禁用，用于调试点击坐标）
                    Column() {
                      Text('卷页模式')
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                        .fontFamily(this.appFontFamily)
                      Text('设备不支持')
                        .fontSize(10)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ top: 2 })
                        .fontFamily(this.appFontFamily)
                    }
                    .width(100)
                    .height(50)
                    .backgroundColor($r('app.color.background_secondary'))
                    .borderRadius(8)
                    .justifyContent(FlexAlign.Center)
                    .opacity(0.5)
                  }
                }
                .width('100%')
                .justifyContent(FlexAlign.Start)
                
        //       .margin({ top: 8 })
                if (this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL && this.isCurlAnimationSupported()) {
                  Column() {
                    Row() {
                      Text('卷页背面透明度')
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .fontFamily(this.appFontFamily)
                      Text(`${this.readingSettings.curlBackOpacity ?? 90}%`)
                        .fontSize(14)
                        .fontColor($r('app.color.accent'))
                        .fontFamily(this.appFontFamily)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                    .margin({ top: 16, bottom: 8 })
                    
                    Slider({
                      value: this.readingSettings.curlBackOpacity ?? 90,
                      min: 0,
                      max: 100,
                      step: 5,
                      style: SliderStyle.OutSet
                    })
                      .blockColor($r('app.color.accent'))
                      .trackColor($r('app.color.background_secondary'))
                      .selectedColor($r('app.color.accent'))
                      .onChange((value: number) => {
                        this.readingSettings.curlBackOpacity = value;
                        this.handleSettingsChange(this.readingSettings);
                      })
                  }
                  .width('100%')
                }
                }
              }
              .width('90%')
              .constraintSize({ maxWidth: 400 })
              .padding(20)
              .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
              .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
              .borderRadius(16)
              .opacity(this.pageTurnAnimationSettingsOpacity)
              .scale({ x: this.pageTurnAnimationSettingsScale, y: this.pageTurnAnimationSettingsScale })
              .translate({ y: this.pageTurnAnimationSettingsTranslateY })
            }
          }
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        if (this.showInteractionOverlay) {
          MangaInteractionOverlay({
            params: {
              readingMode: this.getViewerReadingSettings().readingMode,
              readingDirection: this.getViewerReadingSettings().readingDirection,
              doublePagePortraitLayout: this.getViewerReadingSettings().doublePagePortraitLayout,
              doublePageVerticalDirection: this.getViewerReadingSettings().doublePageVerticalDirection,
              componentWidth: this.componentWidth > 0 ? this.componentWidth : this.screenWidth,
              componentHeight: this.componentHeight > 0 ? this.componentHeight : this.screenHeight,
              deviceOrientation: this.getDeviceOrientation(),
              modeLocked: this.isModeLocked(),
              orientationLocked: this.isModeLocked(),
              singlePageAutoDoublePageAvailable: !this.isModeLocked() &&
                this.isSinglePageReadingMode(this.readingSettings.readingMode),
              landscapeAutoDoublePageActive: this.shouldUseLandscapeAutoDoublePage(),
              statusBarHeight: this.statusBarHeight,
              navigationBarHeight: this.navigationBarHeight,
              onDismiss: () => {
                this.hideInteractionOverlay();
              }
            }
          })
            .width('100%')
            .height('100%')
            .zIndex(2000)
        }

        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        // if (this.showDebugClickIndicator) {
        //   Column() {
        //     Circle()
        //       .width(60)
        //       .height(60)
        //       .fill('#FF4081')
        //       .opacity(0.6)
        //     
        //     Text(`(${this.debugClickX.toFixed(0)}, ${this.debugClickY.toFixed(0)})`)
        //       .fontSize(12)
        //       .fontColor(Color.White)
        //       .backgroundColor('#FF4081')
        //       .padding(4)
        //       .borderRadius(4)
        //       .margin({ top: 8 })
        //   }
        //   .position({ x: this.debugClickX - 30, y: this.debugClickY - 30 })
        //   .zIndex(3000)
        // }

        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            immersiveMode: true,
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

        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        Web({ src: 'about:blank', controller: this.webviewController })
          .width(0)
          .height(0)
          .visibility(Visibility.None)
          .zIndex(-1)
          .onControllerAttached(() => {
            this.webViewControllerAttached = true;
            logger.info(TAG, '隐藏WebView控制器已附加');
            this.initWebViewController();
            if (this.mangaEngine && this.pageParams) {
              this.refreshNetworkUserAgentAsync(this.mangaEngine, this.pageParams);
            }
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .opacity(this.contentOpacity)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .focusable(true)
      .defaultFocus(true)
      .id('manga_reader_root')
      .onKeyEvent((event: KeyEvent) => {
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        if (event.type === KeyType.Up) {
          const consumed = this.handleVolumeKeyPageTurn(event.keyCode);
          if (consumed) {
            event.stopPropagation();
          }
        }
      })
    }
    .title(this.isImageLoaded ? '' : (this.readerState.currentManga?.title || '漫画阅读器'))
    .hideTitleBar(true)
    .onBackPressed(() => {
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
      this.goBack();
      return true;// 返回 true 表示已处理返回事件
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
      
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
      const params = context.pathInfo.param as MangaReaderPageParams;
      if (params) {
        this.pageParams = params;
        const ctStr: string = String(params.contentType);
        const sidStr: string = params.sourceId !== undefined ? String(params.sourceId) : '未指定';
        const snameStr: string = params.sourceName ? String(params.sourceName) : '未指定';
        logger.info(TAG, `开始初始化阅读器: contentType=${params.contentType}, chapterId=${params.chapterId || '未指定'}, pageIndex=${params.pageIndex || 0}`);
        if (params.manga) {
          const mTitle: string = params.manga.title || '未知标题';
          const mId: string = params.manga.id || '未知ID';
          const mSrcName: string = params.manga.sourceInfo && params.manga.sourceInfo.sourceName ? String(params.manga.sourceInfo.sourceName) : '未指定';
    logger.info(TAG, `开始初始化阅读器: contentType=${params.contentType}, chapterId=${params.chapterId || '未指定'}, pageIndex=${params.pageIndex || 0}`);
        }
        
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        logger.debug(TAG, '参数已存在，但仍需更新配置（可能是章节切换）');
        this.initializeMangaReader(params);
      } else {
        logger.error(TAG, '初始化阅读器失败：未获取到页面参数');
      }
    })
  }
  private resolveParamsFromNavStack(): MangaReaderPageParams | null {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (!stack) {
        return null;
      }
      this.pathStack = stack;
      const arr = this.pathStack.getParamByName('MangaReaderPage') as MangaReaderPageParams[];
      const len: number = arr ? arr.length : 0;
      if (!arr || len === 0) {
        return null;
      }
      const latest = arr[len - 1];
      if (!latest || typeof latest !== 'object') {
        return null;
      }
      const keys: string[] = Object.keys(latest as Object);
      const ok: boolean = keys.includes('manga') || keys.includes('mangaId');
      if (!ok) {
        return null;
      }
      return latest as MangaReaderPageParams;
    } catch (e) {
      logger.error(TAG, '初始化阅读器失败', e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  private resolveParamsFromRouter(): MangaReaderPageParams | null {
    try {
      const router = this.getUIContext()?.getRouter();
      if (!router) {
        return null;
      }
      const raw = router.getParams() as Record<string, Object>;
      const keys: string[] = Object.keys(raw as Object);
      const hasManga: boolean = keys.includes('manga');
      const hasMangaId: boolean = keys.includes('mangaId');
      if (!hasManga && !hasMangaId) {
        return null;
      }
      const hasSourceId: boolean = keys.includes('sourceId');
      const hasChapterId: boolean = keys.includes('chapterId');
      const hasPageIndex: boolean = keys.includes('pageIndex');
      const hasFromPage: boolean = keys.includes('fromPage');
      const hasCoverComponentId: boolean = keys.includes('coverComponentId');
      const hasSourceName: boolean = keys.includes('sourceName');
      let ct: MangaReaderContentType = MangaReaderContentType.Local;
      if (hasSourceId) {
        ct = MangaReaderContentType.OnlineUndownloaded;
      }
      const result: MangaReaderPageParams = {
        manga: hasManga ? (raw['manga'] as Manga) : undefined,
        mangaId: hasMangaId ? String(raw['mangaId']) : undefined,
        sourceId: hasSourceId ? Number(raw['sourceId']) : undefined,
        sourceName: hasSourceName ? String(raw['sourceName']) : undefined,
        contentType: ct,
        chapterId: hasChapterId ? String(raw['chapterId']) : undefined,
        pageIndex: hasPageIndex ? Number(raw['pageIndex']) : 0,
        fromPage: hasFromPage ? String(raw['fromPage']) : '未指定',
        coverComponentId: hasCoverComponentId ? String(raw['coverComponentId']) : undefined
      } as MangaReaderPageParams;
      return result;
    } catch (e) {
      logger.error(TAG, '初始化阅读器失败', e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  private startReaderFlow(): void {
    if (this.pageParams) {
      return;
    }
    let params: MangaReaderPageParams | null = this.resolveParamsFromNavStack();
    if (!params) {
      params = this.resolveParamsFromRouter();
    }
    if (!params) {
      logger.error(TAG, '初始化阅读器失败：未找到阅读参数');
      return;
    }
    this.pageParams = params;
    logger.info(TAG, `开始初始化阅读器: contentType=${params.contentType}, chapterId=${params.chapterId || '未指定'}, pageIndex=${params.pageIndex || 0}`);
    try {
      this.initializeMangaReader(params);
    } catch (e) {
      logger.error(TAG, '初始化阅读器失败', e instanceof Error ? e.message : String(e));
    }
  }
}
/**
* 漫画阅读内容类型
*/
export enum MangaReaderContentType {
  Local = 'Local',
  OnlineUndownloaded = 'OnlineUndownloaded',
  OnlineDownloaded = 'OnlineDownloaded',
  Suwayomi = 'Suwayomi',
  Komga = 'Komga'
}
