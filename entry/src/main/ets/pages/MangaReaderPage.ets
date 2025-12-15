/**
 * 漫画阅读器页面
 * 实现沉浸式显示、Navigation架构、状态管理
 * 支持单页/双页/连续滚动模式、缩放、手势翻页等功能
 */

import { logger } from '../Utils/Logger';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { globalAnimationManager, AnimationType, AnimationState,
  AnimationEasing } from '../Framework/Animation/GlobalAnimationSystem';
import { ThemeManager, ThemeType, GlassEffectContext } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { UIContext, curves } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { DataManager, PageInfo, ChapterInfo, OnlineChapterInfo, OnlinePageInfo, OnlinePageInfoInput } from '../Framework/Data/DataManager';
import { DatabaseManager } from '../Framework/Database/DatabaseManager';
import CookieManager from '../Framework/Managers/CookieManager';
import { DataService } from '../Framework/Services/DataService';
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
  DoublePagePortraitLayout
} from '../Models/MangaModels';
import { MangaViewer } from '../components/MangaViewer';
import { MangaReaderSettings } from '../components/MangaReaderSettings';
import { ImageCacheManager, LoadOptions, RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import fs from '@ohos.file.fs';
import { MangaQuickSettings } from '../components/MangaQuickSettings';
import { MangaReaderChapterList } from '../components/MangaReaderChapterList';
import { MangaInteractionOverlay, MangaInteractionOverlayParams } from '../components/MangaInteractionOverlay';
import { MangaDetailPageParams } from './MangaDetailPage';
import { DownloadStatus, ReadingStatus } from '../Framework/Types/StatusEnums';
import { AutoPageTurnController, AutoPageTurnState, AutoPageTurnConfig } from '../Framework/Utils/AutoPageTurnController';
import { PageTurnAnimationType } from '../Models/MangaModels';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { MangaSourceEngine, EngineResult } from '../Framework/WebView/MangaSourceEngine';
import { PageInfo as SourcePageInfo } from '../Framework/WebView/MangaSourceTypes';
import { MangaSourceAPIEngine } from '../Framework/WebView/MangaSourceAPIEngine';
import { ChapterPreloadManager } from '../Framework/Preload/ChapterPreloadManager';
import { webview } from '@kit.ArkWeb';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { KeyCode, inputConsumer } from '@kit.InputKit';
import type { KeyEvent as InputKeyEvent } from '@kit.InputKit';
import { window } from '@kit.ArkUI';
import { eventBus, GameEvent, BasePayload } from '../Framework/EventBus';

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
  totalPages?: number; // [新增] 实际总页数（用于动态加载场景）
  publishDate: number | Date;
  isRead: boolean;
  readProgress: number;
  language: string;
  scanlationGroup: string;
  isDownloaded: boolean;
  downloadProgress: number;
  downloadStatus: DownloadStatus;
  localPath?: string;
  externalId?: string; // [修复] 添加外部ID字段
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

@Component
export struct MangaReaderPage {
  @State isNetworkConfigReady: boolean = false; // 新增状态：网络配置是否就绪
  // 导航相关
  @State pathStack: NavPathStack = new NavPathStack();
  @State pageParams: MangaReaderPageParams | null = null;

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'MangaReaderPage';

  // 动画相关
  private uiContext: UIContext | undefined = undefined;
  private animationManager = globalAnimationManager; // 使用统一的动画管理器
  @State isVisible: boolean = false;
  @State contentOpacity: number = 0;
  @State titleTranslateY: number = -50;

  // 数据服务与阅读进度状态
  private dataService: DataService = DataService.getInstance();
  private lastProgressSaveTime: number = 0;
  private lastSavedPageIndex: number = -1;
  private sessionStartTimestamp: number = 0;
  
  // 阅读时间定时记录相关
  private readingTimeTimer: number = -1;  // 阅读时间定时器
  private static readonly READING_TIME_SAVE_INTERVAL: number = 1000;  // 阅读时间保存间隔（1秒）
  
  // WebView图源相关
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private mangaEngine: MangaSourceEngine | null = null;
  @State networkHeaders: RequestHeaders | undefined = undefined;
  @State networkHeadersTick: number = 0;
  @State chapterTick: number = 0; // [新增] 章节切换计数器，用于通知MangaViewer重新加载
  private currentSourceId: number = -1;
  @State private dailyLimitReached: boolean = false;
  @State private dailyLimitPromptVisible: boolean = false;
  @State private dailyLimitMessage: string = '';
  // WebView控制器（用于动态加载页面列表）
  private webviewController: webview.WebviewController = new webview.WebviewController();
  
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

  // 阅读设置
  @State readingSettings: ReadingSettings = DEFAULT_READING_SETTINGS;

  // UI控制状态 - 默认隐藏工具栏实现完全沉浸式体验
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0.0;
  @State toolbarTranslateY: number = 0; // 工具栏动画位移
  @State autoHideTimer: number = -1;
  @State showSettingsPanel: boolean = false;
  @State showQuickSettings: boolean = false;
  @State showMoreMenu: boolean = false;
  @State showChapterList: boolean = false;
  // 自动翻页设置面板与控制状态
  @State showAutoPageTurnSettings: boolean = false;
  @State autoPageTurnEnabled: boolean = false;
  @State autoPageTurnIntervalSeconds: number = 5;
  private interactionPauseTimer: number = -1;
  
  // 自动翻页控制
  private autoPageTurnController: AutoPageTurnController | null = null;
  @State autoPageTurnState: AutoPageTurnState = AutoPageTurnState.STOPPED;
  
  // MangaViewer组件引用
  private mangaViewerRef: MangaViewer | null = null;
  
  // 用于获取MangaViewer组件实例的引用变量
  @State private mangaViewerComponent: MangaViewer | null = null;
  
  // 交互区域提示
  @State showInteractionOverlay: boolean = false; // 初次进入不显示，等待读取真实阅读设置后再显示
  @State overlayDismissTimer: number = -1;
  @State isReadingSettingsReady: boolean = false; // 阅读设置是否已加载
  
  // 调试：显示点击位置
  @State showDebugClickIndicator: boolean = false;
  @State debugClickX: number = 0;
  @State debugClickY: number = 0;
  
  // 设置面板动画状态
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  @State settingsPanelTranslateY: number = 20;
  // 更多菜单动画状态
  @State moreMenuOpacity: number = 0;
  @State moreMenuScale: number = 0.95;
  @State moreMenuTranslateY: number = -10;
  // 快速设置面板动画状态
  @State quickSettingsOpacity: number = 0;
  @State quickSettingsScale: number = 0.95;
  @State quickSettingsTranslateY: number = 20;
  // 自动翻页设置面板动画状态
  @State autoPageTurnSettingsOpacity: number = 0;
  @State autoPageTurnSettingsScale: number = 0.95;
  @State autoPageTurnSettingsTranslateY: number = 20;
  // 翻页动画设置面板状态
  @State showPageTurnAnimationSettings: boolean = false;
  @State pageTurnAnimationSettingsOpacity: number = 0;
  @State pageTurnAnimationSettingsScale: number = 0.95;
  @State pageTurnAnimationSettingsTranslateY: number = 20;
  // 跳转页面对话框状态
  @State showJumpToPageDialog: boolean = false;
  @State jumpToPageInput: string = '';
  @State jumpToPageDialogOpacity: number = 0;
  @State jumpToPageDialogScale: number = 0.9;
  
  // 屏幕尺寸
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;
  // 组件实际渲染尺寸（通过onAreaChange获取）
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  // 沉浸式安全区高度（遵循沉浸式显示规范）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局相关
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State shouldUseDoublePage: boolean = false; // 是否应该使用双页模式
  
  // 图片加载状态 - 用于控制titlebar显示
  @State isImageLoaded: boolean = false;
  
  // [修复] 阅读器初始化完成标志，用于阻止初始化期间的错误阅读进度保存
  // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，覆盖正确的阅读进度
  private isReaderInitialized: boolean = false;

  // 手势和交互状态
  @State isDragging: boolean = false;
  @State lastTapTime: number = 0;
  @State tapCount: number = 0;
  private singleTapTimer: number = -1; // 单击延迟定时器，用于双击检测时取消单击
  
  // 音量键翻页回调函数（用于inputConsumer注册/注销）
  private volumeUpCallback: ((event: InputKeyEvent) => void) | null = null;
  private volumeDownCallback: ((event: InputKeyEvent) => void) | null = null;
  private isVolumeKeyListenerRegistered: boolean = false;

  onPageShow() {
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
              logger.info(TAG, `  - 漫画ID: ${typedParams.manga.id}`);
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
              fromPage: hasFromPage ? String(rawParamsObj['fromPage']) : '未指定'
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
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题已切换到: ${newTheme}`);
    });

    
  }

  aboutToAppear() {
    logger.lifecycle(TAG, '漫画阅读器页面即将出现');
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    
    // 初始化屏幕尺寸
    this.initScreenSize();
    
    // 初始化响应式布局
    this.initResponsiveLayout();
    
    // 初始化自动翻页控制器
    this.initAutoPageTurnController();
    
    // 初始化WebView控制器（用于WebView图源动态加载）
    this.initWebViewController();

    // 设置全屏阅读模式的状态栏
    this.setupFullscreenMode();
    
    // 应用屏幕常亮设置
    this.applyKeepScreenOnSetting();
    
    // 亮度设置已移除，不再应用
    
    // 注册音量键监听（如果启用了音量键翻页）
    this.updateVolumeKeyListener();
    
    // 启动阅读器流程
    this.startReaderFlow();
    
    // 启动入场动画
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
    // 清除可能存在的旧定时器
    if (this.readingTimeTimer !== -1) {
      clearInterval(this.readingTimeTimer);
    }
    
    // 每1秒保存一次阅读进度 
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
      // 检查是否应该使用双页模式
      this.shouldUseDoublePage = ResponsiveLayoutHelper.shouldUseDoublePage();
      
      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 横屏=${deviceInfo.isLandscape}, 宽度=${deviceInfo.screenWidth.toFixed(2)}vp`);
        const newShouldUseDoublePage = ResponsiveLayoutHelper.shouldUseDoublePage();
        
        if (newShouldUseDoublePage !== this.shouldUseDoublePage) {
          this.shouldUseDoublePage = newShouldUseDoublePage;
          logger.info(TAG, `双页模式状态变化: ${this.shouldUseDoublePage ? '开启' : '关闭'}`);
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
    // 通知预加载管理器：阅读器已关闭
    ChapterPreloadManager.getInstance().setReaderActive(false);
    
    // 停止阅读时间定时记录
    this.stopReadingTimeTracking();
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    
    // 离开前尝试保存阅读进度
    this.saveReadingProgressInternal('aboutToDisappear').catch((error: Error) => {
      logger.error(TAG, '离开页面前保存阅读进度失败', error.message);
    });
    
    // 销毁自动翻页控制器
    if (this.autoPageTurnController) {
      this.autoPageTurnController.destroy();
      this.autoPageTurnController = null;
    }
    
    // 清理WebView资源
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

    // 恢复屏幕常亮设置（关闭常亮）
    this.restoreKeepScreenOnSetting();
    
    // 恢复系统默认亮度
    this.restoreBrightnessSetting();
    
    // 注销音量键监听
    this.unregisterVolumeKeyListener();

    // 恢复正常状态栏模式
    this.restoreNormalMode();

    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // [修复] 发布阅读进度更新事件，通知书库页面刷新
    eventBus.publish(GameEvent.MANGA_READING_PROGRESS_UPDATED, new BasePayload());
    
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
      // 获取屏幕显示信息
      displayClass = display.getDefaultDisplaySync();
      if (displayClass) {
        // 获取物理像素尺寸和屏幕密度
        const physicalWidth = displayClass.width;
        const physicalHeight = displayClass.height;
        const densityPixels = displayClass.densityPixels || 1.0;
        
        // 转换为vp单位（ClickEvent.displayX/displayY使用vp单位）
        // vp = px / densityPixels
        this.screenWidth = physicalWidth / densityPixels;
        this.screenHeight = physicalHeight / densityPixels;
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
    
    // 设置回调函数，为条漫模式提供特殊的异步翻页支持
    this.autoPageTurnController.setCallbacks(
      () => {
        if (this.isWebtoonMode()) {
          // 条漫模式：使用异步翻页，等待滚动完成
          logger.debug(TAG, '自动翻页触发（条漫模式）');
          this.goToNextPage(() => {
            // 翻页完成后，通知控制器继续下一次翻页
            logger.debug(TAG, '条漫模式自动翻页完成，准备下一次翻页');
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
      // 清理WebView控制器
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
    this.readingSettings.autoPageTurnInterval = clamped;
    this.updateAutoPageTurnConfig();
    logger.info(TAG, `自动翻页间隔更新为: ${clamped}s`);
  }

  /**
   * 设置自动翻页启用状态
   */
  private setAutoPageTurnEnabled(enabled: boolean): void {
    this.autoPageTurnEnabled = enabled;
    if (!this.autoPageTurnController) {
      logger.warn(TAG, '自动翻页控制器未初始化');
      return;
    }
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
    this.showAutoPageTurnSettings = true;
    
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 200,
        curve: Curve.EaseOut
      }, () => {
        this.autoPageTurnSettingsOpacity = 1;
        this.autoPageTurnSettingsScale = 1;
        this.autoPageTurnSettingsTranslateY = 0;
      });
    } else {
      this.autoPageTurnSettingsOpacity = 1;
      this.autoPageTurnSettingsScale = 1;
      this.autoPageTurnSettingsTranslateY = 0;
    }
  }
  
  /**
   * 隐藏自动翻页设置面板（带动画）
   */
  private hideAutoPageTurnSettingsWithAnimation(): void {
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 150,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showAutoPageTurnSettings = false;
        }
      }, () => {
        this.autoPageTurnSettingsOpacity = 0;
        this.autoPageTurnSettingsScale = 0.95;
        this.autoPageTurnSettingsTranslateY = 20;
      });
    } else {
      this.showAutoPageTurnSettings = false;
    }
  }

  /**
   * 自动翻页按钮图标（启用/禁用）
   */
  private getAutoPageTurnIconResource(): Resource {
    return this.autoPageTurnEnabled ? $r('app.media.ic_auto_selected') : $r('app.media.ic_auto');
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
      logger.info(TAG, '自动翻页已启动');
    } else if (currentState === AutoPageTurnState.RUNNING) {
      this.autoPageTurnController.pause();
      this.autoPageTurnState = AutoPageTurnState.PAUSED;
      logger.info(TAG, '自动翻页已暂停');
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
  private updateNetworkHeadersForChapter(): void {
    const engine = this.mangaEngine;
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;

    if ( !manga || !chapter ) {
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
      // 获取外部 Manga ID
      let externalMangaId = this.pageParams?.mangaId || manga.id;
      
      // [修复] 优先使用 manga.sourceInfo.externalId
      if (externalMangaId.startsWith('id_')) {
        if (manga.sourceInfo?.externalId) {
          externalMangaId = manga.sourceInfo.externalId;
          logger.info(TAG, `✅ 使用manga.sourceInfo.externalId: ${externalMangaId}`);
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
      
      // 只有当 Referer 真的变化时才更新，避免死循环
      if (this.networkHeaders) {
        // 如果 headers 已存在，检查 Referer 是否需要更新
        if (this.networkHeaders.referer !== newReferer) {
           const prev: RequestHeaders = this.networkHeaders;
           // 创建新对象，保留旧属性 (不使用 ... 语法，明确赋值)
           const updated: RequestHeaders = {
             userAgent: prev?.userAgent || 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
             accept: prev?.accept || 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
             referer: newReferer,// 更新 Referer
             origin: newReferer,
             acceptLanguage: prev && prev.acceptLanguage ? prev.acceptLanguage : 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
             cacheControl: prev.cacheControl,
             pragma: prev.pragma,
             secFetchDest: prev.secFetchDest,
             secFetchMode: prev.secFetchMode,
             secFetchSite: prev.secFetchSite,
             cookie: prev?.cookie
           } as RequestHeaders;
           
           this.networkHeaders = updated;
           this.networkHeadersTick = this.networkHeadersTick + 1; // 递增 Tick
           
           logger.info(TAG, `✅ [二次确认] 强制更新Referer: ${newReferer}, Tick=${this.networkHeadersTick}`);
        }
      } else {
        // 如果 headers 为空，进行初始化
        const updated: RequestHeaders = {
          userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36',
          referer: newReferer,
          origin: newReferer,
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
    // 1. 如果mangaId不是内部ID格式，直接返回（它本身就是外部ID）
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
          const errorMsg = `❌ online_comic表中漫画 ${mangaId} 的externalId为空！\\n` +
            `这是数据完整性错误，请检查数据保存逻辑！`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
      } else {
        const errorMsg = `❌ online_comic表中未找到漫画: ${mangaId}`;
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
    // 1. 优先使用内存中的externalId
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
          const errorMsg = `❌ online_chapter表中章节 ${chapter.id} 的externalId为空！\\n` +
            `  - title: ${chapter.title}\\n` +
            `  - id: ${chapter.id}\\n` +
            `这是数据完整性错误，请检查数据保存逻辑！`;
          logger.error(TAG, errorMsg);
          throw new Error(errorMsg);
        }
      } catch (err) {
        logger.error(TAG, `❌ 从online_chapter表获取externalId失败: ${String(err)}`);
        throw err as Error;
      }
    }
    
    // 3. 如果chapter.id本身就是外部ID（不是id_或local_开头），直接使用
    if (chapter.id && !chapter.id.startsWith('id_') && !chapter.id.startsWith('local_')) {
      logger.info(TAG, `✅ chapter.id本身就是外部ID: ${chapter.id}`);
      return chapter.id;
    }
    
    // 4. 所有方法都失败，抛出错误
    const errorMsg = `❌ 无法获取章节 "${chapter.title}" 的有效externalId！\\n` +
      `  - chapter.id: ${chapter.id}\\n` +
      `  - chapter.externalId: ${chapter.externalId}\\n` +
      `请检查数据完整性！`;
    logger.error(TAG, errorMsg);
    throw new Error(errorMsg);
  }

  /**
   * 初始化漫画阅读器
   */
  private isInitializing: boolean = false; // 防止重复初始化
  private initPromise: Promise<void> | null = null; // 保存初始化Promise
  
  private async initializeMangaReader(params: MangaReaderPageParams): Promise<void> {
    // 如果正在初始化，等待完成而不是直接返回
    if (this.isInitializing && this.initPromise) {
      logger.warn(TAG, '⚠️ 初始化已在进行中，等待完成...');
      await this.initPromise;
      return;
    }
    
    this.isInitializing = true;
    logger.info(TAG, '🚀 开始初始化漫画阅读器');
    this.isNetworkConfigReady = false; // 重置配置就绪状态，阻止 Viewer 渲染
    
    // 执行初始化并保存Promise
    this.initPromise = (async () => {
      try {
        await this.doActualInitialization(params);
      } finally {
        this.isInitializing = false;
        this.initPromise = null;
      }
    })();
    
    await this.initPromise;
  }
  
  /**
   * 实际的初始化逻辑
   */
  private async doActualInitialization(params: MangaReaderPageParams): Promise<void> {
    // ==================== [修复核心] 立即构造 Referer ====================
    // 1. 判定是否为 Komiic (Source ID 6 或 14，或名称包含 Komiic)
    const srcId = params.sourceId || this.currentSourceId;
    const srcName = params.sourceName || params.manga?.sourceInfo?.sourceName || '';
    const isKomiic = (srcId === 6 || srcId === 14) || srcName.toLowerCase().includes('komiic');

    if (params.sourceId && typeof params.sourceId === 'number' && params.sourceId > 0) {
      this.currentSourceId = params.sourceId;
    }

    // 在构造 Referer 的同时，根据数据库是否存在Cookie决定是否携带
    let cookies: string = '';
    try {
      if (srcId && typeof srcId === 'number') {
        const cm: CookieManager = CookieManager.getInstance();
        const has: boolean = await cm.hasCookie(srcId);
        if (has) {
          cookies = await cm.getCookieString(srcId);
          logger.info(TAG, `🔑 采用数据库Cookie: len=${cookies.length}`);
        } else {
          logger.info(TAG, '🔒 数据库无Cookie，初始化阶段不携带Cookie');
        }
      }
    } catch (e) {
      logger.error(TAG, 'Cookie判定失败', String(e));
    }

    // 2. 获取 ID 信息
    let targetMangaId = params.mangaId || (params.manga ? params.manga.id : '');
    let targetChapterId = params.chapterId || '';

    // 尝试从 SourceURL 获取外部 Manga ID (针对内部 ID 格式)
    if (params.manga && params.manga.sourceInfo && params.manga.sourceInfo.sourceUrl) {
      targetMangaId = params.manga.sourceInfo.sourceUrl;
    }

    // [重构] 根据是否有sourceId判断是在线还是本地漫画
    const hasSourceId = srcId && typeof srcId === 'number' && srcId > 0;
    
    // [修复] 如果mangaId是内部ID格式，从数据库查询真实的externalId
    if (targetMangaId.startsWith('id_')) {
      try {
        if (hasSourceId) {
          // 在线漫画：查询online_comic表（使用强类型方法）
          const dbComicRecord = await DataManager.getInstance().getOnlineComicInfoById(targetMangaId);
          if (dbComicRecord && dbComicRecord.externalId) {
            targetMangaId = dbComicRecord.externalId;
            logger.info(TAG, `🔍 [早期] 从online_comic表获取外部漫画ID: ${targetMangaId}`);
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

    // [修复] 如果chapterId是内部ID格式，从数据库查询真实的externalId
    if (targetChapterId.startsWith('id_')) {
      try {
        if (hasSourceId) {
          // 在线漫画：查询online_chapter表
          const dbChapterRecord = await DataManager.getInstance().getOnlineChapterById(targetChapterId);
          if (dbChapterRecord && dbChapterRecord.externalId) {
            targetChapterId = dbChapterRecord.externalId;
            logger.info(TAG, `🔍 [早期] 从online_chapter表获取外部章节ID: ${targetChapterId}`);
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

    // 3. 如果是 Komiic 且有 ID，立即设置 Headers
    if (isKomiic && targetMangaId && targetChapterId) {
      // 构造 Referer，使用真实的外部ID
      const referer = `https://komiic.com/comic/${targetMangaId}/chapter/${targetChapterId}/images/all`;

      this.networkHeaders = {
        userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        referer: referer,
        origin: referer,
        accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
        acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        cookie: cookies
      } as RequestHeaders;
      this.networkHeadersTick++;
      // [修复] 早期网络配置准备完成，允许Viewer渲染
      this.isNetworkConfigReady = true;
      logger.info(TAG, `🚀 [初始化抢跑] 预设 Komiic Referer: ${referer}`);
      logger.info(TAG, `✅ 早期网络配置就绪，允许Viewer渲染`);
    }
    // ==================== [修复结束] ====================

    try {
      this.readerState.isLoading = true;
      logger.debug(TAG, '📚 设置加载状态');

      // 获取漫画数据
      let manga: Manga;
      // [修复] OnlineDownloaded也需要初始化MangaEngine以支持章节切换
      let isWebViewSource = params.contentType === MangaReaderContentType.OnlineUndownloaded || 
                           params.contentType === MangaReaderContentType.OnlineDownloaded;
      
      

      if (params.manga) {
        // 直接使用传递的漫画对象（通常来自WebView图源）
        manga = params.manga;
        logger.debug(TAG, `📖 使用直接传递的漫画对象，内容类型: ${params.contentType}`);
        
        // [修复] 对于WebView图源的在线漫画，从数据库加载章节和页面信息
        // [修复] 如果设置了skipDatabaseLookup，跳过数据库查找
        if (isWebViewSource && manga.id && !params.skipDatabaseLookup) {
          logger.info(TAG, `🌐 WebView图源在线漫画，从online_chapter表加载章节信息: ${manga.id}`);
          try {
            // [重构] 使用getOnlineComicChapters从online_chapter表加载
            const chapters = await DataManager.getInstance().getOnlineComicChapters(manga.id);
            logger.debug(TAG, `📚 online_chapter表返回章节数量: ${chapters ? chapters.length : 0}`);
            if (chapters && chapters.length > 0) {
              const mangaChapters: MangaChapter[] = [];
              
              for (const chapterInfo of chapters) {
                logger.debug(TAG, `📄 加载在线章节页面信息: ${chapterInfo.title} (ID: ${chapterInfo.id}, externalId: ${chapterInfo.externalId})`);
                const pageInfos = await DataManager.getInstance().getOnlineChapterPages(chapterInfo.id);
                logger.debug(TAG, `📄 在线章节 ${chapterInfo.title} 有 ${pageInfos.length} 页`);
                
                // 转换页面信息为MangaPage格式
                // [修复] 使用数组索引而不是pageNumber，确保index是0-indexed
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
                    index: arrayIndex, // [修复] 使用0-indexed数组索引
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
                
                logger.debug(TAG, `📄 转换后页面数量: ${pages.length}`);
                
                const chapter: MangaChapter = {
                  id: chapterInfo.id,
                  title: chapterInfo.title,
                  chapterNumber: chapterInfo.chapterNumber,
                  pages: pages,
                  publishDate: chapterInfo.publishTime || Date.now(),
                  language: 'zh-CN',
                  scanlationGroup: '',
                  isDownloaded: chapterInfo.isDownloaded || false,
                  downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
                  downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
                  localPath: chapterInfo.downloadPath,
                  externalId: chapterInfo.externalId // [重构] 从online_chapter表读取外部ID
                };
                
                mangaChapters.push(chapter);
                logger.debug(TAG, `✅ 在线章节 ${chapter.title} 转换完成 (externalId: ${chapter.externalId})`);
              }
              
              manga.chapters = mangaChapters;
              logger.info(TAG, `✅ 从online_chapter表加载了 ${manga.chapters.length} 个章节`);
            } else {
              logger.warn(TAG, '⚠️ online_chapter表中没有章节信息，将使用动态加载');
              manga.chapters = [];
            }
          } catch (error) {
            logger.error(TAG, `❌ 从online_chapter表加载章节失败: ${String(error)}`);
            manga.chapters = [];
          }
          logger.debug(TAG, `🔄 WebView图源章节加载完成，继续初始化MangaSourceEngine`);
        } else if (isWebViewSource && manga.id && params.skipDatabaseLookup) {
          logger.info(TAG, `⚠️ skipDatabaseLookup=true，跳过数据库查找章节列表`);
          // [修复] 保留从MangaDetailPage传递的完整章节列表，不要覆盖
          logger.info(TAG, `📚 保留传入的章节列表，共 ${manga.chapters.length} 个章节`);
          // 如果传递了chapterTitle，可以用于验证或日志记录，但不覆盖chapters
          if (params.chapterTitle) {
            logger.info(TAG, `🔍 当前章节标题: "${params.chapterTitle}"`);
          }
        }
        
        // 如果是WebView图源，初始化MangaSourceEngine
        if (isWebViewSource && params.sourceId) {
          this.currentSourceId = params.sourceId;
          logger.info(TAG, `🌐 WebView图源，初始化MangaSourceEngine，sourceId=${params.sourceId}, sourceName=${params.sourceName || '未指定'}`);
          
          try {
            // [修复] 传递图源名称，支持按名称降级查找
            this.mangaEngine = await this.webViewManager.getMangaEngine(params.sourceId, params.sourceName);
            logger.info(TAG, `✅ MangaSourceEngine初始化成功`);
            
            // 加载图源的预加载设置
            await this.loadSourcePreloadSettings(params.sourceId);
            
            const engine: MangaSourceEngine | null = this.mangaEngine;
            logger.debug(TAG, `🔍 检查engine对象: engine=${engine ? '存在' : 'null'}, this.mangaEngine=${this.mangaEngine ? '存在' : 'null'}`);
            logger.info(TAG, `🔄 准备配置网络请求头`);
            if (engine) {
              logger.debug(TAG, '📋 步骤1: 获取engine配置');
              const cfg = engine.getConfig();
              let baseUrl: string = '';
              if (cfg && cfg.metadata && cfg.metadata.baseUrl) {
                baseUrl = String(cfg.metadata.baseUrl);
              }
              logger.debug(TAG, `📋 步骤2: baseUrl=${baseUrl}`);
              
              let ua: string = '';
              try {
                logger.debug(TAG, '📋 步骤3: 开始获取WebView UserAgent');
                ua = await engine.getWebViewUserAgent();
                logger.debug(TAG, `📋 步骤4: UserAgent获取成功，长度=${ua.length}`);
              } catch (uaError) {
                const uaMsg = uaError instanceof Error ? uaError.message : String(uaError);
                logger.warn(TAG, `⚠️ 获取WebView UserAgent失败: ${uaMsg}，使用默认值`);
                ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
              }
              
              logger.debug(TAG, '📋 步骤5: 准备构造Referer');
              let dynamicReferer: string = baseUrl;
              logger.debug(TAG, `🔍 准备构造Referer: isKomiic=${isKomiic}, baseUrl=${baseUrl}`);
              
              // 注意：此时currentChapter可能还未设置，使用params.chapterId
              if (isKomiic && params.chapterId) {
                logger.debug(TAG, '📋 步骤6: Komiic图源，构造特定Referer');
                const base: string = baseUrl;
                // [修复] 确保使用外部ID而不是内部ID
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
                // 如果chapterId是内部ID格式，尝试获取外部ID
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
                
                logger.debug(TAG, `使用mangaId作为externalId: ${externalMangaId}`);
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
                logger.debug(TAG, `使用默认Referer: ${dynamicReferer}`);
              }
              logger.debug(TAG, '📋 步骤7: 构造请求头对象');
              const headers: RequestHeaders = {
                userAgent: ua,
                accept: 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5',
                referer: dynamicReferer,
                origin: dynamicReferer,
                acceptLanguage: 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
                cacheControl: 'no-cache',
                pragma: 'no-cache',
                secFetchDest: 'image',
                secFetchMode: 'no-cors',
                secFetchSite: 'same-origin'
              } as RequestHeaders;
              
              logger.debug(TAG, '📋 步骤8: 开始获取Cookie');
              try {
                const cm2: CookieManager = CookieManager.getInstance();
                logger.debug(TAG, '📋 步骤9: CookieManager实例已获取，准备读取Cookie');
                const cookieStr2: string = await cm2.getCookieString(this.currentSourceId);
                logger.debug(TAG, `📋 步骤10: Cookie读取完成，长度=${cookieStr2.length}`);
                if (cookieStr2.length > 0) {
                  headers.cookie = cookieStr2;
                  logger.debug(TAG, '📋 步骤11: Cookie已添加到请求头');
                } else {
                  logger.warn(TAG, '⚠️ Cookie为空，跳过添加');
                }
              } catch (cookieError) {
                const msg: string = cookieError instanceof Error ? cookieError.message : String(cookieError);
                logger.warn(TAG, `读取Cookie失败: ${msg}`);
              }
              logger.debug(TAG, '📋 步骤12: 设置networkHeaders');
              this.networkHeaders = headers;
              this.networkHeadersTick++;
              logger.debug(TAG, `📋 步骤13: networkHeadersTick=${this.networkHeadersTick}`);
              
              // [修复] 网络配置准备完成，允许Viewer渲染
              this.isNetworkConfigReady = true;
              logger.debug(TAG, '📋 步骤14: isNetworkConfigReady已设置为true');
              
              logger.debug(TAG, `🌐 网络请求头已准备: UA=${ua.substring(0, Math.min(64, ua.length))}, Referer=${dynamicReferer}`);
              logger.info(TAG, `✅ 网络配置就绪，允许Viewer渲染`);
              logger.debug(TAG, '📋 步骤15: 网络请求头配置完成，准备退出if块');
            } else {
              logger.warn(TAG, `⚠️ engine对象为null，跳过网络请求头配置`);
            }
          } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            const errorStack = error instanceof Error ? error.stack : undefined;
            logger.error(TAG, `❌ MangaSourceEngine初始化失败: ${errorMsg}`);
            if (errorStack) {
              logger.error(TAG, `错误堆栈: ${errorStack}`);
            }
            throw new Error(`图源引擎初始化失败: ${errorMsg}`);
          }
          logger.info(TAG, `🔄 WebView图源MangaSourceEngine配置完成，继续设置漫画和章节`);
        }
        logger.info(TAG, `✅ WebView图源分支执行完成，准备进入章节设置阶段`);
      } else if (params.mangaId) {
        // 从DataManager加载漫画数据
        logger.debug(TAG, `🔍 从DataManager加载漫画数据，ID: ${params.mangaId}, sourceId: ${params.sourceId || 'none'}`);
        const comicInfo = await DataManager.getInstance().getComicById(params.mangaId);
        if (!comicInfo) {
          throw new Error(`未找到ID为 ${params.mangaId} 的漫画`);
        }
        
        // 转换为Manga对象（使用异步方法，从数据库加载完整的阅读设置和进度）
        manga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
        logger.debug(TAG, `✅ 漫画基本信息加载完成: ${manga.title}`);
        
        // [重构] 根据是否有sourceId判断是在线漫画还是本地漫画
        const hasSourceId = params.sourceId && typeof params.sourceId === 'number' && params.sourceId > 0;
        logger.debug(TAG, `📚 开始加载章节信息，hasSourceId: ${hasSourceId}`);
        
        let chapters: ChapterInfo[] | OnlineChapterInfo[];
        if (hasSourceId) {
          // 在线漫画：从online_chapter表加载
          logger.info(TAG, `📚 在线漫画，从online_chapter表加载章节`);
          chapters = await DataManager.getInstance().getOnlineComicChapters(params.mangaId);
        } else {
          // 本地漫画：从chapter表加载
          logger.info(TAG, `📚 本地漫画，从chapter表加载章节`);
          chapters = await DataManager.getInstance().getComicChapters(params.mangaId);
        }
        
        if (chapters && chapters.length > 0) {
          // 转换章节信息为MangaChapter格式，并加载页面信息
          const mangaChapters: MangaChapter[] = [];
          
          for (const chapterInfo of chapters) {
            // [重构] 根据是否为在线漫画选择页面加载方法
            logger.debug(TAG, `📄 加载章节页面信息: ${chapterInfo.title} (ID: ${chapterInfo.id})`);
            const pageInfos: PageInfo[] | OnlinePageInfo[] = hasSourceId 
              ? await DataManager.getInstance().getOnlineChapterPages(chapterInfo.id)
              : await DataManager.getInstance().getChapterPages(chapterInfo.id);
            
            // 转换页面信息为MangaPage格式
            // [修复] 使用数组索引而不是pageNumber/index，确保index是0-indexed
            const pages: MangaPage[] = pageInfos.map((pageInfo: PageInfo | OnlinePageInfo, arrayIndex: number) => {
              // 根据图片路径判断sourceType
              let sourceType: ImageSourceType;
              if (pageInfo.imageUrl.startsWith('http://') || pageInfo.imageUrl.startsWith('https://')) {
                sourceType = ImageSourceType.NETWORK;
              } else if (pageInfo.imageUrl.startsWith('/')) {
                // 本地文件系统路径，使用LOCAL类型
                sourceType = ImageSourceType.LOCAL;
              } else {
                // 默认为rawfile资源
                sourceType = ImageSourceType.RAWFILE;
              }
              
              // [重构] 根据是否为在线漫画选择字段映射
              const localPath = hasSourceId 
                ? undefined                                 // OnlinePageInfo没有localPath
                : (pageInfo as PageInfo).localPath;
              
              const converter: PageInfoToMangaPageConverter = {
                id: pageInfo.id,
                pageNumber: arrayIndex, // [修复] 使用0-indexed数组索引
                imageUrl: pageInfo.imageUrl,
                localPath: localPath,
                width: pageInfo.width,
                height: pageInfo.height,
                fileSize: pageInfo.fileSize,
                isLoaded: false,
                index: arrayIndex, // [修复] 使用0-indexed数组索引
                sourceType: sourceType,
                imagePath: pageInfo.imageUrl,
                loadProgress: 0
              };
              return converter as MangaPage;
            });
            
            // [重构] 根据是否为在线漫画选择字段映射
            const chapterNumber = hasSourceId
              ? (chapterInfo as OnlineChapterInfo).chapterNumber  // OnlineChapterInfo使用chapterNumber
              : (chapterInfo as ChapterInfo).index;                // ChapterInfo使用index
            
            const converter: ChapterInfoToMangaChapterConverter = {
              id: chapterInfo.id,
              title: chapterInfo.title,
              chapterNumber: chapterNumber,
              pages: pages, // 使用加载的页面信息
              publishDate: chapterInfo.publishTime || Date.now(),
              isRead: false,
              readProgress: 0,
              language: 'zh-CN',
              scanlationGroup: '',
              isDownloaded: chapterInfo.isDownloaded || false,
              downloadProgress: chapterInfo.isDownloaded ? 100 : 0,
              downloadStatus: chapterInfo.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
              localPath: chapterInfo.downloadPath,
              externalId: chapterInfo.externalId // [重构] 从online_chapter或chapter表读取外部ID
            };
            
            logger.debug(TAG, `转换章节: ${converter.title}, 编号: ${converter.chapterNumber}, 页数: ${pages.length}`);
            mangaChapters.push(converter as MangaChapter);
          }
          
          manga.chapters = mangaChapters;
          logger.info(TAG, `✅ 章节信息加载完成，共 ${manga.chapters.length} 个章节`);
          
          // [修复] 检查是否有章节缺少externalId，如果有则尝试从MangaSourceEngine补全
          const chaptersWithoutExternalId = manga.chapters.filter(ch => 
            !ch.externalId || ch.externalId.startsWith('id_')
          );
          if (chaptersWithoutExternalId.length > 0) {
            logger.warn(TAG, `⚠️ 发现 ${chaptersWithoutExternalId.length} 个章节缺少有效的externalId，尝试补全`);
            // 这里暂时记录警告，后续可以考虑从MangaSourceEngine重新获取
            chaptersWithoutExternalId.forEach(ch => {
              logger.warn(TAG, `  - 章节 ${ch.title} (id=${ch.id}) 缺少externalId`);
            });
          }
          
          // 输出章节页面统计信息
          manga.chapters.forEach((chapter, index) => {
            logger.info(TAG, `章节${index + 1}: ${chapter.title} (页数: ${chapter.pages.length}, externalId: ${chapter.externalId || 'N/A'})`);
          });
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
        throw new Error('参数错误：必须提供manga或mangaId');
      }

      logger.info(TAG, `🔄 准备设置当前漫画和章节`);
      logger.info(TAG, `📊 当前状态: manga=${manga ? manga.title : 'null'}, chapters=${manga ? manga.chapters.length : 0}`);
      this.readerState.currentManga = manga;
      logger.info(TAG, `📚 设置当前漫画: ${manga.title}`);

      // 设置当前章节 - 增强错误处理和日志
      logger.info(TAG, `📚 开始章节初始化，漫画总章节数: ${manga.chapters.length}`);
      
      if (params.chapterId) {
        logger.debug(TAG, `🔍 查找指定章节ID: ${params.chapterId}`);
        
        // [修复] 对于WebView图源，params.chapterId是外部ID，需要通过externalId字段匹配
        let chapter: MangaChapter | undefined;
        
        if (isWebViewSource) {
          // WebView图源：通过externalId匹配
          logger.debug(TAG, `🌐 WebView图源，使用externalId匹配章节`);
          chapter = manga.chapters.find(ch => ch.externalId === params.chapterId);
          if (chapter) {
            logger.info(TAG, `✅ 通过externalId找到章节: ${chapter.title} (internalId: ${chapter.id}, externalId: ${chapter.externalId}, 页数: ${chapter.pages.length})`);
          } else {
            logger.warn(TAG, `⚠️ 未通过externalId找到章节: ${params.chapterId}`);
            logger.warn(TAG, `可用章节externalId列表: ${manga.chapters.map(ch => `${ch.externalId || 'undefined'}`).join(', ')}`);
          }
        } else {
          // 非WebView图源：通过id匹配
          logger.debug(TAG, `📚 非WebView图源，使用id匹配章节`);
          chapter = manga.chapters.find(ch => ch.id === params.chapterId);
          if (chapter) {
            logger.info(TAG, `✅ 通过id找到章节: ${chapter.title} (ID: ${chapter.id}, 页数: ${chapter.pages.length})`);
          } else {
            logger.warn(TAG, `⚠️ 未通过id找到章节: ${params.chapterId}`);
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
        logger.error(TAG, '❌ 漫画没有可用章节');
        logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
        this.readerState.errorMessage = `漫画"${manga.title}"没有可用章节\n章节总数: ${manga.chapters.length}\n${params.chapterId ? `指定章节ID: ${params.chapterId}` : '未指定章节'}`;
        this.readerState.isLoading = false;
        return;
      }

      // [重构] 在线已下载：从online_page表加载本地文件路径
      if (params.contentType === MangaReaderContentType.OnlineDownloaded && this.readerState.currentChapter.pages.length === 0) {
        logger.info(TAG, '📥 在线已下载章节：从online_page表加载页面');
        
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
            index: arrayIndex, // [修复] 使用0-indexed数组索引
            sourceType: sourceType,
            imagePath: imagePath,
            imageUrl: pageInfo.imageUrl,
            width: pageInfo.width,
            height: pageInfo.height,
            fileSize: pageInfo.fileSize,
            isLoaded: false
          };
          return page;
        });
        this.readerState.currentChapter.pages = mangaPages;
        logger.info(TAG, `✅ 从online_page表加载 ${mangaPages.length} 张页面`);
        if (this.mangaViewerComponent) {
          this.mangaViewerComponent.kickstartLoading();
        }
      }

      // 在线未下载：使用WebView动态加载页面列表
      let didDynamicPageList: boolean = false;
      // [修改] 增加对页面数据有效性的检查
      // 如果页面数量为0，或者页面数量>0但第一页没有有效的图片链接，都视为需要动态加载
      const hasValidPages = this.readerState.currentChapter.pages.length > 0 &&
        (!!this.readerState.currentChapter.pages[0].imageUrl || !!this.readerState.currentChapter.pages[0].imagePath);

      // 调试日志：输出页面数据状态
      logger.debug(TAG, `📊 页面数据检查: 页数=${this.readerState.currentChapter.pages.length}, hasValidPages=${hasValidPages}`);
      if (this.readerState.currentChapter.pages.length > 0) {
        const firstPage = this.readerState.currentChapter.pages[0];
        logger.debug(TAG, `📄 第一页数据: imageUrl="${firstPage.imageUrl}", imagePath="${firstPage.imagePath}"`);
      }

      if (isWebViewSource && this.mangaEngine && !hasValidPages) {
        logger.info(TAG, `🌐 WebView图源章节无页面数据，开始动态加载页面列表`);

        // [重构] 使用专门的方法获取外部漫画ID（不与本地方法混用）
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
          this.readerState.loadingMessage = '正在获取章节图片列表...';
          logger.info(TAG, `🔄 开始获取页面列表: mangaId=${externalMangaId}, chapterId=${externalChapterId}`);
          
          // [新增] 等待WebView组件完全初始化（避免"WebviewController must be associated with a Web component"错误）
          logger.debug(TAG, `⏳ 等待WebView组件就绪...`);
          await new Promise<void>((resolve) => {
            setTimeout(() => {
              logger.debug(TAG, `✅ WebView等待完成，开始请求页面列表`);
              resolve();
            }, 500); // 延迟500ms确保WebView组件已渲染
          });
          
          // [新增] 智能重试机制：页面列表为空时自动重试
          let pageListResult: ESObject | null = null;
          const maxRetries = 2; // 最多重试2次
          let retryCount = 0;
          
          while (retryCount <= maxRetries) {
            if (retryCount > 0) {
              const retryDelay = retryCount * 1000; // 递增延迟：1s, 2s
              logger.info(TAG, `🔄 第${retryCount}次重试，等待${retryDelay}ms后重新获取页面列表...`);
              this.readerState.loadingMessage = `页面加载中，正在重试(${retryCount}/${maxRetries})...`;
              await new Promise<void>((resolve) => {
                setTimeout(() => resolve(), retryDelay);
              });
            }
            
            // 使用修正后的ID请求页面列表
            pageListResult = await this.mangaEngine.getPageList(externalChapterId, externalMangaId);
            
            // 检查结果是否有效
            if (pageListResult.success && pageListResult.data && pageListResult.data.length > 0) {
              logger.info(TAG, `✅ 页面列表获取成功，共 ${pageListResult.data.length} 页`);
              break; // 成功获取，退出重试循环
            }
            
            // 如果是最后一次尝试，记录失败
            if (retryCount === maxRetries) {
              logger.warn(TAG, `⚠️ 已重试${maxRetries}次，页面列表仍为空`);
            }
            
            retryCount++;
          }
          
          if (!pageListResult) {
            throw new Error('页面列表获取失败：未能获取有效结果');
          }
          
          logger.info(TAG, `📊 页面列表获取结果: success=${pageListResult.success}, hasData=${!!pageListResult.data}, dataLength=${pageListResult.data?.length || 0}, 重试次数=${retryCount}`);
          if (pageListResult.error) {
            logger.error(TAG, `❌ 页面列表获取错误: ${pageListResult.error}`);
          }

          // [删除] 针对 Komiic 更新 Referer
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
          //    logger.info(TAG, `🔄 更新图片加载 Referer: ${newReferer}, Tick=${this.networkHeadersTick}`);
          // }
          
          if (!pageListResult.success || !pageListResult.data) {
            const errorMsg: string = (pageListResult.error as string) || '获取页面列表失败';
            logger.error(TAG, `❌ 页面列表获取失败: ${errorMsg}`);
            this.readerState.errorMessage = `无法获取章节图片列表\n${errorMsg}`;
            this.readerState.isLoading = false;
            throw new Error(errorMsg);
          }
          
          logger.info(TAG, `✅ 页面列表获取成功，共 ${pageListResult.data.length} 页`);
          
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
          const dbPages = await dataManager.getOnlineChapterPages(this.readerState.currentChapter.id);

          // 如果网络获取的页面列表为空，但数据库有数据，则使用数据库数据作为后备
          let sourcePages: SourcePageInfo[] = pageListResult.data;
          if (sourcePages.length === 0 && dbPages.length > 0) {
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
            const errorMsg = '提取到的图片列表为空或所有URL无效';
            logger.error(TAG, `❌ ${errorMsg}`);
            logger.error(TAG, `原始数据: ${JSON.stringify(sourcePages.slice(0, 3))}`);
            this.readerState.errorMessage = `无法加载章节图片\n${errorMsg}\n请检查图源配置或网络连接`;
            this.readerState.isLoading = false;
            throw new Error(errorMsg);
          }
          
          logger.info(TAG, `✅ 有效图片数量: ${validPages.length}`);
          
          // 转换SourcePageInfo为MangaPage
          const pagesToConvert = validPages;
          const mangaPages: MangaPage[] = pagesToConvert.map((pageInfo: SourcePageInfo, index: number) => {
            // [重构] 在线未下载漫画直接使用网络URL，不查找本地文件
            const page: MangaPage = {
              id: `page_${pageInfo.page}`,
              index: index,
              sourceType: ImageSourceType.NETWORK,
              imagePath: pageInfo.imageUrl || '', // 占位页面可能为空
              imageUrl: pageInfo.imageUrl || '', // 占位页面可能为空
              width: pageInfo.width,
              height: pageInfo.height,
              fileSize: 0,
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
          logger.info(TAG, `✅ 章节页面数据已更新，共 ${mangaPages.length} 页`);
          
          // 保存页面列表到数据库
          if (validPages.length > 0) {
            this.saveChapterPagesToDatabase(externalChapterId, validPages).catch((err: Error) => {
              logger.warn(TAG, `保存页面列表失败: ${err.message}`);
            });
          }

          if (this.mangaViewerComponent) {
            this.mangaViewerComponent.kickstartLoading();
          }
          // 强制触发首张网络图片加载，确保OnlineUndownloaded路径发起HTTP请求
          try {
            const firstIndex: number = this.readerState.currentPageIndex >= 0 ? this.readerState.currentPageIndex : 0;
            const firstPage: MangaPage | undefined = mangaPages && mangaPages.length > 0 ? mangaPages[firstIndex] : undefined;
            if (firstPage && firstPage.sourceType === ImageSourceType.NETWORK) {
              const cacheMgr: ImageCacheManager = ImageCacheManager.getInstance();
              const opts: LoadOptions = {
                width: firstPage.width,
                height: firstPage.height,
                headers: this.networkHeaders,
                sourceId: this.currentSourceId
              } as LoadOptions;
              logger.debug(TAG, `🛰️ 首图网络加载预检: url=${firstPage.imageUrl}`);
              cacheMgr.loadImage(firstPage.imageUrl, opts).then((_pm) => {
                logger.info(TAG, '🛰️ 首图网络加载完成');
              }).catch((err: Error) => {
                const msg: string = err instanceof Error ? err.message : String(err);
                logger.warn(TAG, `🛰️ 首图网络加载失败: ${msg}`);
              });
            }
          } catch (preloadErr) {
            const preMsg: string = preloadErr instanceof Error ? preloadErr.message : String(preloadErr);
            logger.warn(TAG, `🛰️ 首图网络加载触发异常: ${preMsg}`);
          }
          
        // 保存页面信息到数据库
        // [修改] 仅当 sourcePages 有数据且来自网络时保存
        if (sourcePages.length > 0) {
          await this.savePageInfoToDatabase(this.readerState.currentChapter.id, sourcePages);
          
          // 当前章节页面信息加载完成后，立即预加载下一章节（如果启用）
          this.preloadNextChapterAfterCurrentLoaded();
        }
          // 在线图源：检测每日限额（仅对支持的图源如Komiic执行）
          await this.detectDailyImageLimitIfSupported(externalChapterId);

        } catch (error) {
          logger.error(TAG, `❌ 动态加载页面列表失败: ${String(error)}`);
          this.readerState.errorMessage = `加载章节页面失败: ${String(error)}`;
          this.readerState.isLoading = false;
          return;
        }
        didDynamicPageList = true;
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
          // 主动预加载当前页的网络图片，确保HTTP请求被触发
          const firstIndex: number = this.readerState.currentPageIndex >= 0 ? this.readerState.currentPageIndex : 0;
          const firstPage: MangaPage | undefined = pages && pages.length > 0 ? pages[firstIndex] : undefined;
          if (firstPage && firstPage.sourceType === ImageSourceType.NETWORK) {
            const cacheMgr: ImageCacheManager = ImageCacheManager.getInstance();
            const opts: LoadOptions = {
              width: firstPage.width,
              height: firstPage.height,
              headers: this.networkHeaders,
              sourceId: this.currentSourceId
            } as LoadOptions;
            logger.debug(TAG, `🛰️ 首图网络加载预检(已有页面): url=${firstPage.imageUrl}`);
            cacheMgr.loadImage(firstPage.imageUrl, opts).then((_pm) => {
              logger.info(TAG, '🛰️ 首图网络加载完成(已有页面)');
            }).catch((err: Error) => {
              const msg: string = err instanceof Error ? err.message : String(err);
              logger.warn(TAG, `🛰️ 首图网络加载失败(已有页面): ${msg}`);
            });
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
      
      logger.debug(TAG, `📄 页面初始化参数:`);
      logger.debug(TAG, `  - 请求页面索引: ${requestedPageIndex}`);
      logger.debug(TAG, `  - 章节总页数: ${totalPages}`);
      logger.debug(TAG, `  - 最大页面索引: ${maxPageIndex}`);
      
      if (totalPages === 0) {
        logger.error(TAG, `❌ 当前章节没有页面数据`);
        this.readerState.errorMessage = `章节"${this.readerState.currentChapter.title}"没有页面数据`;
        this.readerState.isLoading = false;
        return;
      }
      
      // 确保页面索引在有效范围内
      this.readerState.currentPageIndex = Math.max(0, Math.min(requestedPageIndex, maxPageIndex));
      
      if (requestedPageIndex !== this.readerState.currentPageIndex) {
        logger.warn(TAG, `⚠️ 请求的页面索引 ${requestedPageIndex} 超出范围 [0, ${maxPageIndex}]，已调整为 ${this.readerState.currentPageIndex}`);
      }
      
      // [修复] 优先使用currentChapter.totalPages，如果未设置则使用pages.length
      const displayTotalPages = this.readerState.currentChapter.totalPages || totalPages;
      logger.info(TAG, `📄 页面初始化完成: 第 ${this.readerState.currentPageIndex + 1}/${displayTotalPages} 页`);

      // 记录当前页面详细信息
      const currentPage = this.readerState.currentChapter.pages[this.readerState.currentPageIndex];
      if (currentPage) {
        logger.debug(TAG, `📄 当前页面信息:`);
        logger.debug(TAG, `  - 页面ID: ${currentPage.id}`);
        logger.debug(TAG, `  - 页面索引: ${currentPage.index}`);
        logger.debug(TAG, `  - 图片源类型: ${currentPage.sourceType}`);
        logger.debug(TAG, `  - 图片URL: ${currentPage.imageUrl}`);
      }

      // 加载阅读设置
      logger.debug(TAG, '⚙️ 开始加载阅读设置');
      this.loadReadingSettings();

      // [新增] 此时章节已确定，强制刷新一次 Headers 以确保 Referer 正确
      this.updateNetworkHeadersForChapter(); 

      // 预加载图片
      logger.debug(TAG, '🖼️ 开始预加载图片');
      this.preloadImages();

      // 初始化阅读会话计时与保存状态
      this.sessionStartTimestamp = Date.now();
      this.lastProgressSaveTime = 0;
      this.lastSavedPageIndex = -1;

      // [修复] 最终确保配置就绪（如果之前未设置）
      if (!this.isNetworkConfigReady) {
        this.isNetworkConfigReady = true;
        logger.info(TAG, `✅ 最终确保配置就绪，允许Viewer渲染`);
      }
      this.readerState.isLoading = false;
      logger.info(TAG, '✅ 漫画阅读器初始化完成');
      logger.info(TAG, `📊 初始化摘要:`);
      logger.info(TAG, `  - 漫画: ${this.readerState.currentManga?.title}`);
      logger.info(TAG, `  - 当前章节: ${this.readerState.currentChapter?.title}`);
      // [修复] 优先使用totalPages显示实际总页数
      const summaryTotalPages = this.readerState.currentChapter?.totalPages || this.readerState.currentChapter?.pages.length || 0;
      logger.info(TAG, `  - 当前页面: 第${this.readerState.currentPageIndex + 1}页/${summaryTotalPages}页`);
      logger.info(TAG, `  - 阅读模式: ${this.readingSettings.readingMode}`);
      logger.info(TAG, `  - 阅读方向: ${this.readingSettings.readingDirection}`);
      
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
      this.readerState.errorMessage = `初始化失败: ${errorMessage}\n\n漫画: ${mangaInfo}\n章节ID: ${params?.chapterId || '未指定'}\n页面索引: ${params?.pageIndex || 0}\n\n请检查网络连接或重试`;
      this.readerState.isLoading = false;
      
      logger.error(TAG, '❌ 漫画阅读器初始化失败', errorMessage);
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
      logger.error(TAG, `错误堆栈: ${error instanceof Error ? error.stack : 'N/A'}`);
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

    // 统一User-Agent：优先使用WebView UA
    let ua: string = '';
    try {
      ua = await engine.getWebViewUserAgent();
    } catch (_e) {
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
        this.dailyLimitMessage = '当前图源已达到每日图片访问限额';
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
   * 现在Manga对象已经从数据库加载了完整的阅读设置，直接使用即可
   */
  private loadReadingSettings(): void {
    logger.debug(TAG, '⚙️ 开始加载阅读设置');
    
    try {
      if (!this.readerState.currentManga) {
        logger.warn(TAG, '⚠️ 当前漫画为空，无法加载阅读设置');
        this.readingSettings = DEFAULT_READING_SETTINGS;
        this.isReadingSettingsReady = true;
        logger.info(TAG, '📋 使用默认阅读设置，准备显示交互提示Overlay');
        if (!this.showInteractionOverlay) {
          this.showInteractionOverlay = true;
          this.showInteractionOverlayWithAnimation();
        }
        return;
      }

      const mangaId = this.readerState.currentManga.id;
      logger.debug(TAG, `📖 加载漫画ID=${mangaId}的阅读设置`);

      // Manga对象的readingSettings已经在convertComicInfoToMangaAsync中从数据库加载
      // 直接使用即可，无需再从AppStorage或其他地方加载
      const settings = this.readerState.currentManga.readingSettings;
      
      logger.debug(TAG, `📖 从漫画对象加载设置（已从数据库加载）:`);
      logger.debug(TAG, `  - 阅读模式: ${settings.readingMode}`);
      logger.debug(TAG, `  - 阅读方向: ${settings.readingDirection}`);
      logger.debug(TAG, `  - 亮度: ${settings.brightness}`);
      logger.debug(TAG, `  - 保持屏幕常亮: ${settings.keepScreenOn}`);
      
      // 直接引用漫画对象的设置（避免不必要的复制）
      this.readingSettings = settings;
      this.isReadingSettingsReady = true;
      
      logger.info(TAG, '✅ 阅读设置加载完成（来自数据库），准备显示交互提示Overlay');
      if (!this.showInteractionOverlay) {
        this.showInteractionOverlay = true;
        this.showInteractionOverlayWithAnimation();
      }
      logger.debug(TAG, `📋 最终阅读设置:`);
      logger.debug(TAG, `  - 阅读模式: ${this.readingSettings.readingMode}`);
      logger.debug(TAG, `  - 阅读方向: ${this.readingSettings.readingDirection}`);
      logger.debug(TAG, `  - 亮度: ${this.readingSettings.brightness}`);
      logger.debug(TAG, `  - 自动翻页间隔: ${this.readingSettings.autoPageTurnInterval}ms`);
      logger.debug(TAG, `  - 显示页面信息: ${this.readingSettings.showPageInfo}`);
      
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
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
      this.readingSettings = DEFAULT_READING_SETTINGS;
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
      logger.debug(TAG, `  - 总页数: ${totalPages}`);
      logger.debug(TAG, `  - 当前页面: ${currentPageIndex + 1}`);
      
      // 预加载当前页面和相邻页面
      const preloadRange = 50; // 预加载前后50页（全局默认）
      const startIndex = Math.max(0, currentPageIndex - preloadRange);
      const endIndex = Math.min(totalPages - 1, currentPageIndex + preloadRange);
      
      logger.debug(TAG, `  - 预加载范围: ${startIndex + 1} - ${endIndex + 1}`);
      
      for (let i = startIndex; i <= endIndex; i++) {
        const page = currentChapter.pages[i];
        if (page && page.imageUrl) {
          logger.debug(TAG, `🖼️ 预加载页面 ${i + 1}: ${page.imageUrl}`);
        }
      }
      
      logger.info(TAG, `✅ 图片预加载计划完成，预加载 ${endIndex - startIndex + 1} 页`);
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
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
    }
  }

  /**
   * 设置全屏阅读模式
   */
  private setupFullscreenMode(): void {
    try {
      // 使用WindowManager设置完全沉浸式模式
      const uiContext = this.getUIContext();
      if (!uiContext) {
        logger.error(TAG, '❌ 无法获取UIContext，设置全屏模式失败');
        return;
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
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
    }
  }

  /**
   * 恢复正常模式
   */
  private restoreNormalMode(): void {
    try {
      // 使用WindowManager恢复默认显示模式
      const uiContext = this.getUIContext();
      if (!uiContext) {
        logger.error(TAG, '❌ 无法获取UIContext，恢复正常模式失败');
        return;
      }
      
      WindowManager.setDisplayMode(DisplayMode.DEFAULT, uiContext);
      logger.info(TAG, '✅ 使用WindowManager恢复默认显示模式');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const errorDetails: OperationErrorDetails = {
        errorType: error instanceof Error ? error.constructor.name : 'Unknown',
        errorMessage: errorMessage,
        operation: 'restoreNormalMode',
        timestamp: new Date().toISOString()
      };
      
      logger.error(TAG, '❌ 恢复正常模式失败', errorMessage);
      logger.error(TAG, `错误详情: ${JSON.stringify(errorDetails, null, 2)}`);
    }
  }
  /**
   * 启动入场动画
   * 修复：使用animateTo在回调中直接修改状态，确保动画和状态同步
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
   * 显示交互区域提示overlay
   */
  private showInteractionOverlayWithAnimation(): void {
    if (!this.showInteractionOverlay) {
      return;
    }
    
    // 5秒后自动隐藏
    this.overlayDismissTimer = setTimeout(() => {
      this.hideInteractionOverlay();
    }, 5000);
    
    logger.info(TAG, '显示交互提示Overlay，5秒后自动隐藏');
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
   * 简化版：移除双击检测，单击立即响应
   * 注：双击缩放功能已禁用，如需恢复请使用GestureGroup处理
   */
  private handlePageTap(event: ClickEvent): void {
    // 直接处理单击，无延迟
    this.handleSingleTap(event);
    // 交互触发：暂停自动翻页1s
    this.delayAutoPageTurnForInteraction();
  }

  /**
   * 显示工具栏动画
   * 修复：使用animateTo在回调中直接修改状态，确保动画和状态同步
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
   * 修复：使用animateTo在回调中直接修改状态，动画完成后隐藏组件
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
   * 判断当前阅读模式是否支持卷页动画
   * 卷页动画只支持：单页模式 + 从左到右/从右到左阅读方向
   */
  private isCurlAnimationSupported(): boolean {
    const mode = this.readingSettings.readingMode;
    const direction = this.readingSettings.readingDirection;
    
    // 单页从右到左模式
    if (mode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    
    // 单页模式 + 从左到右或从右到左方向
    if (mode === ReadingMode.SINGLE_PAGE) {
      return direction === ReadingDirection.LEFT_TO_RIGHT || 
             direction === ReadingDirection.RIGHT_TO_LEFT;
    }
    
    return false;
  }

  /**
   * 处理设置变更
   */
  private handleSettingsChange(settings: ReadingSettings): void {
    logger.info(TAG, `阅读设置已更新: pageTurnAnimation=${settings.pageTurnAnimation}, brightness=${settings.brightness}`);
    
    // 检查屏幕常亮设置是否变更
    const keepScreenOnChanged = this.readingSettings.keepScreenOn !== settings.keepScreenOn;
    // 检查亮度设置是否变更（在更新前检测，使用容差比较浮点数）
    const brightnessChanged = Math.abs(this.readingSettings.brightness - settings.brightness) > 0.01;
    // 检查音量键翻页设置是否变更
    const volumeKeyChanged = this.readingSettings.volumeKeyNavigation !== settings.volumeKeyNavigation;
    
    // 保存设置到数据库和AppStorage（针对当前漫画）
    if (this.readerState.currentManga) {
      const mangaId = this.readerState.currentManga.id;
      const settingsJson = JSON.stringify(settings);
      
      // 保存到数据库
      ComicConverter.saveReadingSettings(mangaId, settings).then(() => {
        logger.info(TAG, `✅ 阅读设置已保存到数据库: manga_settings_${mangaId}`);
      }).catch((error: Error) => {
        logger.error(TAG, `❌ 保存阅读设置到数据库失败: ${error.message}`);
      });
      
      // 同时保存到AppStorage作为缓存
      AppStorage.setOrCreate(`manga_settings_${mangaId}`, settingsJson);
      logger.info(TAG, `已保存漫画独立设置到AppStorage: manga_settings_${mangaId}`);
      
      // 更新Manga对象的阅读设置
      this.readerState.currentManga.readingSettings = settings;
    }
    
    // 立即更新当前阅读设置
    this.readingSettings = settings;
    
    // 如果屏幕常亮设置变更，立即应用
    if (keepScreenOnChanged) {
      this.applyKeepScreenOnSetting();
    }
    
    // 亮度设置已移除，不再处理亮度变更
    
    // 如果音量键翻页设置变更，更新监听状态
    if (volumeKeyChanged) {
      logger.info(TAG, `音量键翻页设置变更: ${settings.volumeKeyNavigation}`);
      this.updateVolumeKeyListener();
    }
    
    // 更新自动翻页配置
    this.updateAutoPageTurnConfig();

    // 注意：不要在设置变更时自动启动/停止自动翻页
    // 自动翻页的启用/停止应该由用户通过自动翻页设置面板明确控制
    // 只有当用户明确禁用（间隔设为0）时才停止
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
   * 修复：添加真正的动画效果
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
   * 修复：添加真正的动画效果
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
   * 修复：添加真正的动画效果
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
   * 修复：添加真正的动画效果
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
    
    this.showPageTurnAnimationSettings = true;
    this.handleMenusVisibilityChange();
    if (this.uiContext) {
      setTimeout(() => {
        const animateOptions: AnimationConfig = { duration: 200, curve: Curve.EaseOut };
        this.uiContext!.animateTo(animateOptions, () => {
          this.pageTurnAnimationSettingsOpacity = 1;
          this.pageTurnAnimationSettingsScale = 1;
          this.pageTurnAnimationSettingsTranslateY = 0;
        });
      }, 0);
    } else {
      this.pageTurnAnimationSettingsOpacity = 1;
      this.pageTurnAnimationSettingsScale = 1;
      this.pageTurnAnimationSettingsTranslateY = 0;
    }
  }

  /**
   * 注册音量键监听（使用inputConsumer API拦截系统音量调节）
   * 这是实现音量键翻页的正确方式，可以阻止系统音量条弹出
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
        action: 1, // 按下按键的行为
        isRepeat: false // 优先消费掉按键事件，不上报给系统
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
   * @param keyCode 按键码
   * @returns 是否消费了该按键事件
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
      // 音量上键 - 上一页
      logger.info(TAG, '音量键翻页: 上一页');
      this.goToPreviousPage();
      return true;
    } else if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN || keyCode === 17) {
      // 音量下键 - 下一页
      logger.info(TAG, '音量键翻页: 下一页');
      this.goToNextPage();
      return true;
    }
    
    return false;
  }

  /**
   * 隐藏翻页动画设置面板
   */
  private hidePageTurnAnimationSettingsWithAnimation(): void {
    if (this.uiContext) {
      const animateOptions: AnimationConfig = { duration: 160, curve: Curve.EaseIn };
      this.uiContext.animateTo(animateOptions, () => {
        this.pageTurnAnimationSettingsOpacity = 0;
        this.pageTurnAnimationSettingsScale = 0.95;
        this.pageTurnAnimationSettingsTranslateY = 20;
      });
      setTimeout(() => {
        this.showPageTurnAnimationSettings = false;
      }, 160);
    } else {
      this.pageTurnAnimationSettingsOpacity = 0;
      this.pageTurnAnimationSettingsScale = 0.95;
      this.pageTurnAnimationSettingsTranslateY = 20;
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
      this.readerState.currentPageIndex = targetIndex;
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
    if (!this.uiContext) return;
    // 根据阅读方向选择翻页轴：
    // 水平阅读（LTR/RTL）使用 Y 轴翻页；垂直阅读（TTB）使用 X 轴翻页
    const isVertical: boolean = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
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
   * 使用photoAccessHelper的showAssetsCreationDialog方式，无需申请权限
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
        AlertDialog.show({ message: '网络图片暂不支持直接保存，请先下载章节' });
        return;
      }
      
      // 本地图片路径
      if (!imagePath.startsWith('/')) {
        logger.error(TAG, `无效的图片路径: ${imagePath}`);
        AlertDialog.show({ message: '无法保存：图片路径无效' });
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
    try {
      const dataManager = DataManager.getInstance();
      
      // 检查是否已经保存过页面信息
      const existingPages = await dataManager.getPageInfoList(chapterId);
      if (existingPages.length > 0) {
        logger.debug(TAG, `章节 ${chapterId} 的页面信息已存在，跳过保存`);
        return;
      }
      
      // 批量保存页面信息
      for (let i = 0; i < pages.length; i++) {
        const pageInfo = pages[i];
        await dataManager.addPageInfo({
          chapterId: chapterId,
          index: i,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width || 0,
          height: pageInfo.height || 0,
          fileSize: 0
        });
      }
      
      logger.info(TAG, `✅ 已保存章节 ${chapterId} 的 ${pages.length} 个页面信息到数据库`);
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
    
    // 查找下一章节
    const currentIndex = manga.chapters.findIndex(ch => ch.id === chapter.id);
    if (currentIndex < 0 || currentIndex >= manga.chapters.length - 1) {
      logger.debug(TAG, '已是最后一章，无需预加载下一章节');
      return; // 已是最后一章
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
    // 保留空实现以避免破坏现有调用
  }

  /**
   * 加载图源的预加载设置
   */
  private async loadSourcePreloadSettings(sourceId: number): Promise<void> {
    try {
      const dbManager = DatabaseManager.getInstance();
      const sql = 'SELECT preloadCurrentChapter, preloadCurrentPages, preloadNextChapter, preloadNextPages FROM comic_source WHERE id = ?';
      const records = await dbManager.querySql(sql, [sourceId]);
      
      if (records && records.length > 0) {
        const record = records[0] as Record<string, number>;
        const settings: SourcePreloadSettings = {
          preloadCurrentChapter: (record['preloadCurrentChapter'] || 1) === 1,
          preloadCurrentPages: record['preloadCurrentPages'] || 10,
          preloadNextChapter: (record['preloadNextChapter'] || 1) === 1,
          preloadNextPages: record['preloadNextPages'] || -1
        };
        this.sourcePreloadSettings = settings;
        logger.info(TAG, `✅ 已加载图源预加载设置: 当前章节=${this.sourcePreloadSettings.preloadCurrentChapter}(${this.sourcePreloadSettings.preloadCurrentPages}页), 下一章节=${this.sourcePreloadSettings.preloadNextChapter}(${this.sourcePreloadSettings.preloadNextPages}页)`);
      } else {
        logger.warn(TAG, `⚠️ 未找到图源ID=${sourceId}的预加载设置，使用默认值`);
      }
    } catch (error) {
      logger.error(TAG, `加载图源预加载设置失败: ${String(error)}`);
    }
  }

  
  /**
   * 保存章节页面到数据库
   */
  private async saveChapterPagesToDatabase(chapterId: string, pages: SourcePageInfo[]): Promise<void> {
    try {
      const dataManager = DataManager.getInstance();
      
      for (let i = 0; i < pages.length; i++) {
        const pageInfo = pages[i];
        const onlinePageInput: OnlinePageInfoInput = {
          chapterId: chapterId,
          pageNumber: i,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width || 0,
          height: pageInfo.height || 0,
          fileSize: 0
        };
        
        await dataManager.addOnlinePageInfo(onlinePageInput);
      }
      
      logger.info(TAG, `✅ 已保存章节 ${chapterId} 的 ${pages.length} 个页面信息到数据库`);
    } catch (error) {
      logger.error(TAG, `保存页面信息失败: ${error}`);
    }
  }

  /**
   * 预加载章节页面
   * @param chapter 要预加载的章节
   * @param maxPages 最大预加载页数（-1表示全部，0表示不预加载）
   */
  private async preloadChapterPages(chapter: MangaChapter, maxPages: number = -1): Promise<void> {
    if (!this.mangaEngine) {
      const error = 'MangaEngine未初始化';
      logger.error(TAG, error);
      throw new Error(error);
    }
    
    // 如果maxPages为0，不预加载
    if (maxPages === 0) {
      logger.debug(TAG, '预加载页数为0，跳过预加载');
      return;
    }
    
    try {
      // 获取外部章节ID
      const externalChapterId = await this.getExternalChapterIdForOnlineUndownloaded(chapter);
      const externalMangaId = await this.getExternalMangaIdForOnlineUndownloaded(this.readerState.currentManga?.id || '');
      
      // 检查是否已经在详情页预加载过
      const preloadManager = ChapterPreloadManager.getInstance();
      const preloadTask = preloadManager.getTaskStatus(chapter.id);
      
      let pageListResult: EngineResult<SourcePageInfo[]>;
      
      if (preloadTask && preloadTask.status === 'completed' && preloadTask.pageCount > 0) {
        logger.info(TAG, `✅ 章节已在详情页预加载: ${chapter.title}, 共${preloadTask.pageCount}页, 已预加载${preloadTask.preloadedPages}页图片`);
        
        // 尝试从数据库读取页面列表，避免重复调用getPageList
        const dataManager = DataManager.getInstance();
        const dbPages = await dataManager.getPageInfoList(chapter.id);
        
        if (dbPages.length > 0) {
          logger.info(TAG, `✅ 从数据库读取页面列表: ${chapter.title}, 共${dbPages.length}页`);
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
        logger.info(TAG, `✅ 预加载成功，获取到 ${pageListResult.data.length} 页，实际预加载 ${pagesToPreload.length} 页`);
      } else {
        logger.info(TAG, `✅ 预加载成功，获取到 ${pageListResult.data.length} 页，全部预加载`);
      }
      
      // 转换为MangaPage格式
      const mangaPages: MangaPage[] = pagesToPreload.map((pageInfo: SourcePageInfo, index: number) => {
        return {
          id: `page_${pageInfo.page}`,
          index: index,
          sourceType: ImageSourceType.NETWORK,
          imagePath: pageInfo.imageUrl,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width,
          height: pageInfo.height,
          fileSize: 0,
          isLoaded: false
        } as MangaPage;
      });
      
      // 更新章节的页面列表（内存中）
      chapter.pages = mangaPages;
      
      // 保存到数据库（保存全部页面信息，即使只预加载部分）
      await this.savePageInfoToDatabase(chapter.id, pageListResult.data);
      
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
    // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，传递错误的页面索引
    // 只有在退出时（aboutToDisappear）才允许强制保存
    if (!this.isReaderInitialized && trigger !== 'aboutToDisappear') {
      logger.debug(TAG, `[修复] 阻止初始化期间的阅读进度保存: trigger=${trigger}`);
      return;
    }
    
    const manga = this.readerState.currentManga;
    const chapter = this.readerState.currentChapter;
    if (!manga || !chapter) {
      return;
    }

    // 使用 readerState.currentPageIndex 作为当前页面索引
    let pageIndex: number = this.readerState.currentPageIndex;
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
    // 对于在线漫画，即使未收藏也会自动保存到comic_info表
    await this.dataService.saveReadingProgress(manga.id, chapter.id, pageIndex, duration, sourceId, mangaData);

    // 更新Manga对象的阅读进度（确保内存中的数据和数据库一致）
    manga.readingProgress.currentChapterId = chapter.id;
    manga.readingProgress.currentPageIndex = pageIndex;
    manga.readingProgress.lastReadAt = now;
    manga.readingProgress.readingStatus = ReadingStatus.READING;
    
    // 累加总阅读时间（转换为分钟）
    manga.readingProgress.totalReadingTime += (duration / 1000 / 60);
    
    logger.info(TAG, `✅ 阅读进度已更新: 章节=${chapter.title}, 页码=${pageIndex + 1}, 时间=${now}`);

    this.lastSavedPageIndex = pageIndex;
    this.lastProgressSaveTime = now;
    this.sessionStartTimestamp = now;
    logger.debug(TAG, `已保存阅读进度[${trigger}]: ${manga.title} / ${chapter.title} -> 第${pageIndex + 1}页, 时长${duration}ms`);
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
      this.saveReadingProgressInternal('switchChapter').then(() => {
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
        
        logger.info(TAG, `切换到章节: ${targetChapter.title}`);
      }).catch((error: Error) => {
        logger.error(TAG, '切换章节前保存进度失败', error.message);
        // 即使保存失败也继续切换
        this.readerState.currentChapter = targetChapter;
        this.readerState.currentPageIndex = 0;
        this.sessionStartTimestamp = Date.now();
        this.lastProgressSaveTime = 0;
        this.lastSavedPageIndex = -1;
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
   * 简化交互规则：
   * 1. 首次点击隐藏交互提示overlay
   * 2. 如果设置面板或菜单已显示，点击任意位置关闭
   * 3. 如果工具栏已显示且点击在工具栏区域内，交给工具栏处理
   * 4. 根据阅读模式划分区域：
   *    - 单页模式（LTR）：左侧上一页 | 中央切换工具栏 | 右侧下一页
   *    - 单页模式（RTL）：右侧上一页 | 中央切换工具栏 | 左侧下一页
   *    - 单页模式（TTB）：上侧上一页 | 中央切换工具栏 | 下侧下一页
   *    - 双页模式：左右区域翻页，中央切换工具栏
   *    - 条漫模式：点击任意位置切换工具栏（滚动翻页）
   */
  private handleSingleTap(event: ClickEvent): void {
    // 注意：双击检测已在handlePageTap中处理，这里直接处理单击逻辑
    // 不再重复进行双击检测，避免300ms延迟叠加导致响应迟钝
    this.processSingleTap(event);
  }

  /**
   * 处理单击事件的具体逻辑
   * 注意：ClickEvent.displayX/displayY 返回的是vp单位的坐标
   * 因此所有区域计算都必须使用vp单位
   */
  private processSingleTap(event: ClickEvent): void {
    // 使用显示坐标（vp单位，相对于窗口的坐标）
    const clickX = event.displayX;
    const clickY = event.displayY;
    
    // 获取显示区域的实际尺寸和设备方向
    // 关键修复：统一使用vp单位，与ClickEvent坐标系统一致
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
    const topToolbarHeight = this.statusBarHeight + 56 + 16;
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
    
    const isDoublePage = this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;
    
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
   * 优化：支持TTB模式（上下翻页）
   */
  private handleDoublePageTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const centerAreaRatio = 0.4; // 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2; // 两侧各占比 = 0.3
    
    // 判断阅读方向
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const isTTB: boolean = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
    
    if (isTTB) {
      // TTB模式（上下翻页）：使用垂直区域划分
      const effectiveHeight = this.componentHeight > 0 ? this.componentHeight : displayHeight;
      const topZoneEnd = effectiveHeight * sideAreaRatio;
      const bottomZoneStart = effectiveHeight * (1 - sideAreaRatio);
      
      logger.debug(TAG, `双页TTB模式区域划分: 组件高度=${this.componentHeight.toFixed(0)}vp, 有效高度=${effectiveHeight.toFixed(0)}vp, topZoneEnd=${topZoneEnd.toFixed(0)}vp, bottomZoneStart=${bottomZoneStart.toFixed(0)}vp, clickY=${clickY.toFixed(0)}vp`);
      
      if (clickY < topZoneEnd) {
        // 上侧区域：上一页
        this.goToPreviousPage();
        logger.info(TAG, `✋ 双页TTB-${deviceOrientation}-上侧区域，上一页`);
      } else if (clickY > bottomZoneStart) {
        // 下侧区域：下一页
        this.goToNextPage();
        logger.info(TAG, `✋ 双页TTB-${deviceOrientation}-下侧区域，下一页`);
      } else {
        // 中央区域
        this.toggleToolbars();
        logger.info(TAG, `✋ 双页TTB-${deviceOrientation}-中央区域，切换工具栏（${this.showTopToolbar ? '显示' : '隐藏'}）`);
      }
    } else {
      // 水平模式（LTR/RTL）：使用水平区域划分
      const effectiveWidth = this.componentWidth > 0 ? this.componentWidth : displayWidth;
      const leftZoneEnd = effectiveWidth * sideAreaRatio;
      const rightZoneStart = effectiveWidth * (1 - sideAreaRatio);
      
      logger.debug(TAG, `双页模式区域划分: 组件宽度=${this.componentWidth.toFixed(0)}vp, 有效宽度=${effectiveWidth.toFixed(0)}vp, leftZoneEnd=${leftZoneEnd.toFixed(0)}vp, rightZoneStart=${rightZoneStart.toFixed(0)}vp, clickX=${clickX.toFixed(0)}vp, 方向=${isRTL ? 'RTL' : 'LTR'}`);
      
      if (clickX < leftZoneEnd) {
        // 左侧区域
        if (isRTL) {
          this.goToNextPage();
          logger.info(TAG, `✋ 双页-${deviceOrientation}-左侧区域（RTL），下一页`);
        } else {
          this.goToPreviousPage();
          logger.info(TAG, `✋ 双页-${deviceOrientation}-左侧区域（LTR），上一页`);
        }
      } else if (clickX > rightZoneStart) {
        // 右侧区域
        if (isRTL) {
          this.goToPreviousPage();
          logger.info(TAG, `✋ 双页-${deviceOrientation}-右侧区域（RTL），上一页`);
        } else {
          this.goToNextPage();
          logger.info(TAG, `✋ 双页-${deviceOrientation}-右侧区域（LTR），下一页`);
        }
      } else {
        // 中央区域
        this.toggleToolbars();
        logger.info(TAG, `✋ 双页-${deviceOrientation}-中央区域，切换工具栏（${this.showTopToolbar ? '显示' : '隐藏'}）`);
      }
    }
  }

  /**
   * 处理单页模式的点击事件
   */
  private handleSinglePageTap(clickX: number, clickY: number, deviceOrientation: string, displayWidth: number, displayHeight: number): void {
    const centerAreaRatio = 0.4; // 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2; // 两侧各占比 = 0.3
    
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
        logger.info(TAG, `✋ 中央区域点击，切换工具栏（${this.showTopToolbar ? '显示' : '隐藏'}）`);
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
    const centerAreaRatio = 0.4; // 中央区域占比
    const sideAreaRatio = (1 - centerAreaRatio) / 2; // 两侧各占比 = 0.3
    
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
        logger.info(TAG, `✋ ${deviceOrientation}-左侧区域（RTL），下一页`);
      } else {
        this.goToPreviousPage();
        logger.info(TAG, `✋ ${deviceOrientation}-左侧区域（LTR），上一页`);
      }
    } else if (clickX > rightZoneStart) {
      // 右侧区域
      if (isRTL) {
        this.goToPreviousPage();
        logger.info(TAG, `✋ ${deviceOrientation}-右侧区域（RTL），上一页`);
      } else {
        this.goToNextPage();
        logger.info(TAG, `✋ ${deviceOrientation}-右侧区域（LTR），下一页`);
      }
    } else {
      // 中央区域
      this.toggleToolbars();
      logger.info(TAG, `✋ ${deviceOrientation}-中央区域，切换工具栏（${this.showTopToolbar ? '显示' : '隐藏'}）`);
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
    }, 3000); // 3秒后自动隐藏
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      this.saveReadingProgressInternal('goBack').then(() => {
        this.pathStack.pop();
        logger.info(TAG, '返回上一页');
      }).catch((error: Error) => {
        logger.error(TAG, '返回前保存阅读进度失败', error.message);
        this.pathStack.pop();
        logger.info(TAG, '返回上一页（忽略保存失败）');
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '返回上一页失败', errorMessage);
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

  /**
   * 滚动到条漫模式的指定页面
   * 使用平滑滚动实现信息流式的翻页效果
   * 支持屏幕滚动模式，提供更自然的阅读体验
   */
  private scrollToWebtoonPage(pageIndex: number): void {
    if (!this.readerState.currentChapter || pageIndex < 0 || pageIndex >= this.readerState.currentChapter.pages.length) {
      logger.warn(TAG, `无效的页面索引: ${pageIndex}`);
      return;
    }
    
    logger.debug(TAG, `条漫模式滚动到页面: ${pageIndex + 1}`);
    
    // 使用MangaViewer的平滑滚动功能代替强制重新渲染
    if (this.mangaViewerComponent && this.mangaViewerComponent.smoothScrollToPage) {
      // 根据自动翻页间隔计算滚动速度，实现更自然的节奏
      // 间隔越短，滚动速度越快（0.5-2.0倍速）
      const scrollSpeed = Math.max(0.5, Math.min(2.0, 5000 / this.readingSettings.autoPageTurnInterval));
      
      // 对于自动翻页，我们需要立即更新页面索引，然后执行平滑滚动
      const currentIndex = this.readerState.currentPageIndex;
      this.readerState.currentPageIndex = pageIndex;
      
      // 调用MangaViewer的平滑滚动到指定页面的方法
      const success = this.mangaViewerComponent.smoothScrollToPage(pageIndex, scrollSpeed);
      if (success) {
        logger.debug(TAG, `条漫模式平滑滚动成功: 页面${currentIndex + 1} -> ${pageIndex + 1}, 速度: ${scrollSpeed}x`);
      } else {
        logger.warn(TAG, `条漫模式平滑滚动失败，回退到传统方法`);
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
        logger.warn(TAG, `条漫模式平滑滚动失败，回退到传统方法`);
        this.readerState.currentPageIndex = pageIndex;
      }
    } else {
      logger.warn(TAG, 'MangaViewer未初始化或不支持平滑滚动，使用传统翻页');
      // 传统方法作为后备方案
      this.readerState.currentPageIndex = pageIndex;
    }
  }

  /**
   * 翻到上一页
   */
  private goToPreviousPage(): void {
    if (this.readerState.currentPageIndex > 0) {
      // 先更新页面索引，确保MangaViewer能够检测到变化
      const newPageIndex = this.readerState.currentPageIndex - 1;
      logger.debug(TAG, `翻到上一页: ${this.readerState.currentPageIndex} -> ${newPageIndex}`);
      
      // 根据阅读模式处理不同的翻页逻辑
      if (this.isWebtoonMode()) {
        // 条漫模式：使用平滑滚动到上一页
        if (this.mangaViewerComponent && this.mangaViewerComponent.smoothScrollToPreviousPage) {
          const scrollSpeed = Math.max(0.5, Math.min(2.0, this.readingSettings.autoPageTurnInterval / 5000));
          const scrollMode = this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 'screen' : 'page';
          
          const success = this.mangaViewerComponent.smoothScrollToPreviousPage(scrollSpeed, scrollMode);
          if (success) {
            logger.debug(TAG, `条漫模式平滑向上滚动成功: 页面${this.readerState.currentPageIndex + 1} -> ${newPageIndex + 1}`);
          } else {
            logger.warn(TAG, `条漫模式平滑向上滚动失败，使用传统方法`);
            this.readerState.currentPageIndex = newPageIndex;
          }
        } else {
          // 回退到传统方法
          this.readerState.currentPageIndex = newPageIndex;
        }
      } else {
        // 其他模式：触发动画和索引更新
        this.animatePageTransition('previous');
        this.readerState.currentPageIndex = newPageIndex;
      }
      
      // 通过底部按钮翻页也需要保存进度
      this.saveReadingProgressInternal('prevPageButton').catch((error: Error) => {
        logger.error(TAG, '翻到上一页时保存阅读进度失败', error.message);
      });
    } else {
      // 切换到上一章节的最后一页
      // 章节切换前先保存当前章节进度
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
   * 支持自动翻页模式下的异步翻页完成通知
   */
  private goToNextPage(onComplete?: (() => void) | undefined): void {
    const currentChapter = this.readerState.currentChapter;
    const isAutoScroll = !!onComplete; // 判断是否为自动翻页
    
    if (currentChapter && this.readerState.currentPageIndex < currentChapter.pages.length - 1) {
      // 先更新页面索引，确保MangaViewer能够检测到变化
      const newPageIndex = this.readerState.currentPageIndex + 1;
      logger.debug(TAG, `翻到下一页: ${this.readerState.currentPageIndex} -> ${newPageIndex}${isAutoScroll ? ' (自动翻页)' : ''}`);
      
      // 根据阅读模式处理不同的翻页逻辑
      if (this.isWebtoonMode()) {
        // 条漫模式：使用平滑滚动到下一页，实现信息流效果
        if (this.mangaViewerComponent) {
          const scrollSpeed = Math.max(0.5, Math.min(2.0, this.readingSettings.autoPageTurnInterval / 5000));
          const scrollMode = this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 'screen' : 'page';
          
          // 对于自动翻页模式，我们需要同步更新页面索引，然后让平滑滚动处理视觉效果
          if (isAutoScroll) {
            // 自动翻页模式：不提前更新索引，等待MangaViewer动画完成后通过回调更新
            const success = this.mangaViewerComponent.smoothScrollToNextPage(scrollSpeed, scrollMode, onComplete);
            if (success) {
              logger.debug(TAG, `条漫模式自动翻页平滑滚动成功，等待页面索引更新回调`);
            } else {
              logger.warn(TAG, `条漫模式自动翻页平滑滚动失败`);
              if (onComplete) { (onComplete as () => void)(); }
            }
          } else {
            // 手动翻页模式：使用传统逻辑
            const success = this.mangaViewerComponent.smoothScrollToNextPage(scrollSpeed, scrollMode, () => {
              this.readerState.currentPageIndex = newPageIndex;
              if (onComplete) { (onComplete as () => void)(); }
            });
            if (!success) {
              this.readerState.currentPageIndex = newPageIndex;
              if (onComplete) { (onComplete as () => void)(); }
            }
          }
        } else {
          // 回退到传统方法
          logger.warn(TAG, 'MangaViewer组件未就绪，使用传统翻页方法');
          this.readerState.currentPageIndex = newPageIndex;
          if (onComplete) { (onComplete as () => void)(); }
        }
      } else {
        // 其他模式：触发动画和索引更新
        this.animatePageTransition('next');
        this.readerState.currentPageIndex = newPageIndex;
        if (onComplete) { (onComplete as () => void)(); }
      }
      
      // 通过底部按钮翻页也需要保存进度
      this.saveReadingProgressInternal('nextPageButton').catch((error: Error) => {
        logger.error(TAG, '翻到下一页时保存阅读进度失败', error.message);
      });
    } else {
      // 切换到下一章节的第一页
      logger.debug(TAG, `到达章节末尾，切换到下一章节${isAutoScroll ? ' (自动翻页)' : ''}`);
      // 章节切换前先保存当前章节进度
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
          this.readerState.currentChapter = prevChapter;
          this.readerState.isLoading = true;
          this.readerState.loadingMessage = '正在加载上一章节...';
          
          // 异步加载页面信息
          this.preloadChapterPages(prevChapter).then(() => {
            // 加载成功后，验证页面数据
            if (!prevChapter.pages || prevChapter.pages.length === 0) {
              const errorMsg = `章节加载后仍然无页面数据: ${prevChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.getUIContext().getPromptAction().showToast({ message: '章节加载失败，页面为空' });
              return;
            }
            
            // 加载成功且有有效页面，更新页面索引
            this.readerState.currentPageIndex = prevChapter.pages.length - 1;
            this.readerState.isLoading = false;
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            logger.info(TAG, `✅ 已切换到上一章节: ${prevChapter.title}，页面数: ${prevChapter.pages.length}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载上一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载上一章节失败: ${error.message}`;
            this.getUIContext().getPromptAction().showToast({ message: '加载上一章节失败' });
          });
        } else {
          // 已有页面信息，但仍需加载页面数据
          logger.info(TAG, `上一章节 ${prevChapter.title} 已有章节信息，开始加载页面数据...`);
          
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          this.readerState.currentChapter = prevChapter;
          this.readerState.isLoading = true;
          this.readerState.loadingMessage = `正在加载 ${prevChapter.title}...`;
          
          // 异步加载页面信息
          this.preloadChapterPages(prevChapter).then(() => {
            // 验证页面数据
            if (!prevChapter.pages || prevChapter.pages.length === 0) {
              const errorMsg = `章节加载后仍然无页面数据: ${prevChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.getUIContext().getPromptAction().showToast({ message: '章节加载失败，页面为空' });
              return;
            }
            
            // 加载成功，更新页面索引
            this.readerState.currentPageIndex = prevChapter.pages.length - 1;
            this.readerState.isLoading = false;
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            // [修复] 触发章节变化通知，让MangaViewer重新加载
            this.chapterTick = this.chapterTick + 1;
            logger.info(TAG, `✅ 已切换到上一章节: ${prevChapter.title}，页面数: ${prevChapter.pages.length}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载上一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载上一章节失败: ${error.message}`;
            this.getUIContext().getPromptAction().showToast({ message: '加载上一章节失败' });
          });
        }
      } else {
        // 已是第一章
        logger.info(TAG, '已是第一章');
        this.getUIContext().getPromptAction().showToast({ message: '已是第一章' });
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
          this.readerState.currentChapter = nextChapter;
          this.readerState.isLoading = true;
          this.readerState.loadingMessage = '正在加载下一章节...';
          
          // 异步加载页面信息
          this.preloadChapterPages(nextChapter).then(() => {
            // 加载成功后，验证页面数据
            if (!nextChapter.pages || nextChapter.pages.length === 0) {
              const errorMsg = `章节加载后仍然无页面数据: ${nextChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.getUIContext().getPromptAction().showToast({ message: '章节加载失败，页面为空' });
              return;
            }
            
            // 加载成功且有有效页面，更新页面索引
            this.readerState.currentPageIndex = 0;
            this.readerState.isLoading = false;
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            logger.info(TAG, `✅ 已切换到下一章节: ${nextChapter.title}，页面数: ${nextChapter.pages.length}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载下一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载下一章节失败: ${error.message}`;
            this.getUIContext().getPromptAction().showToast({ message: '加载下一章节失败' });
          });
        } else {
          // 已有页面信息，但仍需加载页面数据
          logger.info(TAG, `下一章节 ${nextChapter.title} 已有章节信息，开始加载页面数据...`);
          
          // 先更新当前章节，再显示加载状态（这样加载UI能显示正确的章节名称）
          this.readerState.currentChapter = nextChapter;
          this.readerState.isLoading = true;
          this.readerState.loadingMessage = `正在加载 ${nextChapter.title}...`;
          
          // 异步加载页面信息
          this.preloadChapterPages(nextChapter).then(() => {
            // 验证页面数据
            if (!nextChapter.pages || nextChapter.pages.length === 0) {
              const errorMsg = `章节加载后仍然无页面数据: ${nextChapter.title}`;
              logger.error(TAG, errorMsg);
              this.readerState.isLoading = false;
              this.readerState.errorMessage = errorMsg;
              this.getUIContext().getPromptAction().showToast({ message: '章节加载失败，页面为空' });
              return;
            }
            
            // 加载成功，更新页面索引
            this.readerState.currentPageIndex = 0;
            this.readerState.isLoading = false;
            // 切换章节后重置阅读会话计时
            this.sessionStartTimestamp = Date.now();
            this.lastProgressSaveTime = 0;
            this.lastSavedPageIndex = -1;
            // [修复] 触发章节变化通知，让MangaViewer重新加载
            this.chapterTick = this.chapterTick + 1;
            logger.info(TAG, `✅ 已切换到下一章节: ${nextChapter.title}，页面数: ${nextChapter.pages.length}, chapterTick=${this.chapterTick}`);
          }).catch((error: Error) => {
            logger.error(TAG, `加载下一章节失败: ${error.message}`);
            this.readerState.isLoading = false;
            this.readerState.errorMessage = `加载下一章节失败: ${error.message}`;
            this.getUIContext().getPromptAction().showToast({ message: '加载下一章节失败' });
          });
        }
      } else {
        // 已是最后一章
        logger.info(TAG, '已是最后一章');
        this.getUIContext().getPromptAction().showToast({ message: '已是最后一章' });
      }
    }
  }

  /**
   * 构建翻页动画按钮
   */
  @Builder
  buildAnimButton(label: string, type: PageTurnAnimationType) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.readingSettings.pageTurnAnimation === type ? 
          $r('app.color.accent') : $r('app.color.text_secondary'))
    }
    .width('31%')
    .padding(10)
    .backgroundColor(this.readingSettings.pageTurnAnimation === type ? 
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      this.readingSettings.pageTurnAnimation = type;
      this.handleSettingsChange(this.readingSettings);
      logger.info(TAG, `翻页动画已更改为: ${type}`);
    })
  }

  /**
   * 构建顶部工具栏
   */
  @Builder
  buildTopToolbar() {
    Row() {
      // 返回按钮
      Button() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())

      // 标题
      Column() {
        Text(this.readerState.currentManga?.title || '漫画阅读器')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.readerState.currentChapter) {
          Text(this.readerState.currentChapter.title)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      // 菜单按钮（更多选项）
      Button() {
        Image($r('app.media.ic_more_vert'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showMoreMenuWithAnimation();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .shadow({ radius: ThemeManager.getInstance().getGlassRadius(), color: ThemeManager.getInstance().getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
  }

  /**
   * 构建底部工具栏
   */
  @Builder
  buildBottomToolbar() {
    Column() {
      // 进度条
      Row() {
        Text(`${this.readerState.currentPageIndex + 1}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .textAlign(TextAlign.Center)

        Slider({
          value: this.readerState.currentPageIndex,
          min: 0,
          max: (this.readerState.currentChapter?.pages.length || 1) - 1,
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number) => {
            const targetPage = Math.round(value);
            this.readerState.currentPageIndex = targetPage;
            
            // 条漫模式下需要滚动到对应页面
            if (this.isWebtoonMode() && this.mangaViewerComponent) {
              this.mangaViewerComponent.smoothScrollToPage(targetPage, 1.5);
            }
            
            // 进度条变更也触发保存
            this.saveReadingProgressInternal('sliderChange').catch((error: Error) => {
              logger.error(TAG, '通过进度条变更保存阅读进度失败', error.message);
            });
          })

        Text(`${this.readerState.currentChapter?.totalPages || this.readerState.currentChapter?.pages.length || 0}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(40)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 控制按钮
      Row() {
        // 目录按钮
        Button() {
          Image($r('app.media.ic_reading_settings'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .width(64)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openTableOfContents();
        })

        Blank()

        // 阅读模式快捷设置按钮
        Button() {
          Image($r('app.media.ic_book'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showQuickSettingsWithAnimation();
        })

        Blank()

        // 翻页动画设置按钮
        Button() {
          Image($r('app.media.ic_page_turn_animation'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showPageTurnAnimationSettingsWithAnimation();
        })

        Blank()

        // 显示效果设置按钮
        Button() {
          Image($r('app.media.ic_brightness_high'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showSettingsPanelWithAnimation();
        })

        Blank()

        // 自动翻页设置按钮（最右侧）
        Button() {
          Image(this.getAutoPageTurnIconResource())
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
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
  }


  /**
   * 构建漫画内容区域
   */
  @Builder
  buildMangaContent() {
    if (this.readerState.isLoading || (!this.isNetworkConfigReady && !this.readerState.errorMessage)) {
      // 加载状态
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color($r('app.color.accent_primary'))

        Text('加载中...')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
        
        // 显示章节名称
        if (this.readerState.currentChapter?.title) {
          Text(this.readerState.currentChapter.title)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.7)
            .margin({ top: 8 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

    } else if (this.readerState.errorMessage) {
      // 错误状态1：加载失败
      Column() {
        Image($r('app.media.ic_error'))
          .width(64)
          .height(64)
          .fillColor($r('app.color.color_error'))

        Text('加载失败')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })

        // 显示详细错误信息，支持多行显示
        Text(this.readerState.errorMessage)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .padding({ left: 32, right: 32 })
          .maxLines(10)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 操作按钮组
        Row() {
          Button('重试')
            .fontSize(16)
            .fontColor($r('app.color.text_white'))
            .backgroundColor($r('app.color.accent_primary'))
            .onClick(() => {
              logger.info(TAG, '🔄 用户点击重试按钮');
              if (this.pageParams) {
                // 重置错误状态
                this.readerState.errorMessage = '';
                this.readerState.isLoading = true;
                this.initializeMangaReader(this.pageParams);
              } else {
                logger.error(TAG, '❌ 重试失败：页面参数为空');
              }
            })

          Button('返回')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border_light') })
            .margin({ left: 16 })
            .onClick(() => {
              logger.info(TAG, '🔙 用户点击返回按钮');
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
      // 错误状态2：章节数据为空
      Column() {
        Image($r('app.media.ic_error'))
          .width(64)
          .height(64)
          .fillColor($r('app.color.color_error'))

        Text('章节数据加载失败')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })

        Text('无法获取章节信息，请检查网络连接或返回重试')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .padding({ left: 32, right: 32 })
          .maxLines(5)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 操作按钮组
        Row() {
          Button('重新加载')
            .fontSize(16)
            .fontColor($r('app.color.text_white'))
            .backgroundColor($r('app.color.accent_primary'))
            .onClick(() => {
              logger.info(TAG, '🔄 用户点击重新加载按钮（章节数据为空）');
              if (this.pageParams) {
                // 重置状态并重新初始化
                this.readerState.currentChapter = null;
                this.readerState.isLoading = true;
                this.initializeMangaReader(this.pageParams);
              } else {
                logger.error(TAG, '❌ 重新加载失败：页面参数为空');
              }
            })

          Button('返回')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border_light') })
            .margin({ left: 16 })
            .onClick(() => {
              logger.info(TAG, '🔙 用户点击返回按钮（章节数据为空）');
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
      // 正常显示漫画内容
      Stack() {
        MangaViewer({
          chapter: this.readerState.currentChapter as MangaChapter,
          currentPageIndex: this.readerState.currentPageIndex,
          readingSettings: this.readingSettings,
          zoomScale: this.readerState.zoomScale,
          toolbarsVisible: (this.showTopToolbar || this.showBottomToolbar),
          networkHeaders: this.networkHeaders,
          networkHeadersTick: this.networkHeadersTick,
          chapterTick: this.chapterTick, // [新增] 传递章节切换计数器
          sourceId: this.currentSourceId > 0 ? this.currentSourceId : undefined,
          mangaId: this.pageParams?.mangaId,
          preloadCurrentPages: this.sourcePreloadSettings.preloadCurrentPages,
          preloadNextPages: this.sourcePreloadSettings.preloadNextPages,
          contentType: this.pageParams?.contentType, // [新增] 传递内容类型（用于区分在线/本地漫画）
          callbacks: {
            onPageChange: (pageIndex: number) => {
              logger.info(TAG, `页面变更回调: 切换到第 ${pageIndex + 1} 页`);
              
              // [修复] 阻止初始化期间的页面变更修改 readerState.currentPageIndex
              // 问题：MangaViewer 在初始化时会触发 onPageChange 回调，传入错误的页面索引
              // 这会覆盖正确的 readerState.currentPageIndex，导致后续的修复逻辑失效
              if (!this.isReaderInitialized) {
                logger.debug(TAG, `[修复] 阻止初始化期间的页面变更: pageIndex=${pageIndex}, 当前readerState.currentPageIndex=${this.readerState.currentPageIndex}`);
                // 不更新 readerState.currentPageIndex，保持正确的初始值
                return;
              }
              
              // 手动重新创建对象，确保触发 @State 响应式更新（ArkTS不支持展开运算符）
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
              // 交互触发：页面变更视为交互，暂停自动翻页1s
              this.delayAutoPageTurnForInteraction();
              this.startAutoHideTimer();
              // 页面变更后保存阅读进度（限流）
              this.saveReadingProgressInternal('onPageChange').catch((error: Error) => {
                logger.error(TAG, '页面变更保存阅读进度失败', error.message);
              });
              // 预加载下一章节（当接近章节末尾时）
              this.preloadNextChapterIfNeeded(pageIndex);
            },
            onChapterChange: (direction: 'prev' | 'next') => {
              // 章节切换前先保存当前章节进度
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
              // 不再使用MangaViewer的点击事件，坐标不准确
              logger.debug(TAG, 'MangaViewer点击事件（已忽略）');
            },
            onDoubleTap: (event: ClickEvent) => {
              this.handleDoubleTap(event);
            },
            onComponentReady: (component: MangaViewer) => {
              // 获取MangaViewer组件实例引用
              this.mangaViewerComponent = component;
              logger.info(TAG, '🔔 触发MangaViewer预加载');
              component.kickstartLoading();
              const chapter = this.readerState.currentChapter;
              const expectedIndex = this.readerState.currentPageIndex;
              
              // [修复] 检查 MangaViewer 的当前页面索引是否与期望的页面索引一致
              // 由于异步初始化，MangaViewer 可能在 readerState.currentPageIndex 被正确设置之前就被创建了
              const viewerIndex = component.currentPageIndex;
              logger.info(TAG, `🔧 [修复] 页面索引检查: viewer=${viewerIndex}, expected=${expectedIndex}`);
              if (viewerIndex !== expectedIndex && expectedIndex >= 0) {
                logger.info(TAG, `🔧 [修复] 检测到页面索引不一致: viewer=${viewerIndex}, expected=${expectedIndex}，通过readerState同步`);
                // 通过更新 readerState.currentPageIndex 来同步 MangaViewer（@Prop绑定）
                this.readerState.currentPageIndex = expectedIndex;
              } else {
                logger.info(TAG, `🔧 [修复] 页面索引一致，无需跳转`);
              }
              
              if (chapter && this.isWebtoonMode() && expectedIndex > 0) {
                let savedPos: number = 0;
                const key = `webtoon_scroll_${chapter.id}`;
                try {
                  const value = AppStorage.get<number>(key);
                  if (typeof value === 'number') {
                    savedPos = value as number;
                  }
                } catch (_e) {
                  savedPos = 0;
                }
                if (!(savedPos > 0)) {
                  this.scrollToWebtoonPage(expectedIndex);
                }
              }
              
              // [修复] 延迟设置初始化完成标志，确保 MangaViewer 完全初始化后才允许保存阅读进度
              // 使用 setTimeout 确保 MangaViewer 的初始化回调（如 onPageChange）已经执行完毕
              setTimeout(() => {
                this.isReaderInitialized = true;
                logger.info(TAG, '✅ [修复] 阅读器初始化完成，允许保存阅读进度');
              }, 500);
              
              logger.debug(TAG, 'MangaViewer组件实例已通过回调获取');
            }
          }
        })
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .onClick((event: ClickEvent) => {
        // 在Stack层捕获点击事件，获取正确的屏幕坐标
        this.handlePageTap(event);
      })
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 获取组件实际渲染尺寸（vp单位）
        // Area.width和Area.height返回的是vp值，与ClickEvent.displayX/displayY一致
        const widthVp = Number(newArea.width);
        const heightVp = Number(newArea.height);
        
        if (widthVp > 0 && heightVp > 0) {
          this.componentWidth = widthVp;
          this.componentHeight = heightVp;
          logger.debug(TAG, `📐 组件尺寸更新: ${widthVp.toFixed(0)}x${heightVp.toFixed(0)}vp`);
        }
      })
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层 - 扩展到系统栏区域实现完全沉浸式，使用透明背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层 - 占满全屏，使用安全区 padding 以遵循沉浸式规范
        Column() {
          // 漫画内容区域 - 占满全屏
          this.buildMangaContent()
        }
        .width('100%')
        .height('100%')
        // .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })

        // 顶部工具栏（悬浮覆盖）
        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // 每日限额提示横幅（顶部悬浮）
        if (this.dailyLimitPromptVisible) {
          Row({ space: 12 }) {
            Text(this.dailyLimitMessage)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank().layoutWeight(1)
            Button('知道了')
              .fontSize(14)
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

        // 底部工具栏（悬浮覆盖，略高于底部）
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

        // 快速设置面板（带动画）
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
        
        // 完整设置面板（带动画）
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

        // 自动翻页设置面板（居中弹窗样式，类似翻页动画设置）
        if (this.showAutoPageTurnSettings) {
          Stack() {
            // 遮罩
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('app.color.background_overlay'))
              .opacity(0.5)
              .onClick(() => {
                this.hideAutoPageTurnSettingsWithAnimation();
              })

            // 面板
            Column() {
              // 标题
              Row() {
                Text('自动翻页设置')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

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

              Row() {
                Text(`${this.autoPageTurnIntervalSeconds}秒`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.accent'))
                  .width(50)

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
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

        // 悬浮式章节列表面板
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
          .zIndex(1000)
        }

        // 悬浮式"更多选项"菜单（移动到主Stack内部，顶部右侧）
        if (this.showMoreMenu) {
          Stack() {
            // 点击遮罩关闭
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.hideMoreMenuWithAnimation();
              })

            // 菜单面板
            Column() {
              // 跳转到页面
              Row() {
                Text('跳转到页面')
                  .fontColor($r('app.color.text_primary'))
                  .fontSize(16)
                Blank().layoutWeight(1)
                Text(`${this.readerState.currentPageIndex + 1}/${this.readerState.currentChapter?.pages.length || 0}`)
                  .fontColor($r('app.color.text_secondary'))
                  .fontSize(14)
              }
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                logger.info(TAG, 'MoreMenu: 跳转到页面');
                this.hideMoreMenuWithAnimation();
                setTimeout(() => {
                  this.showJumpToPageDialogWithAnimation();
                }, 200);
              })

              Divider().color($r('app.color.divider'))

              // 保存本页到图库
              Row() {
                Text('保存本页到图库')
                  .fontColor($r('app.color.text_primary'))
                  .fontSize(16)
                Blank().layoutWeight(1)
              }
              .height(44)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                logger.info(TAG, 'MoreMenu: 保存本页到图库');
                this.hideMoreMenuWithAnimation();
                this.saveCurrentPageToGallery();
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
            .margin({ top: this.statusBarHeight + 56 + 8, right: 12 })
            .constraintSize({ maxWidth: 260 })
            .zIndex(1100)
          }
          .width('100%')
          .height('100%')
          .zIndex(1100)
        }

        // 跳转到页面对话框
        if (this.showJumpToPageDialog) {
          Stack() {
            // 半透明遮罩（显示漫画背景）
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#80000000')
              .opacity(this.jumpToPageDialogOpacity)
              .onClick(() => {
                this.hideJumpToPageDialogWithAnimation();
              })

            // 对话框
            Column({ space: 16 }) {
              Text('跳转到页面')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))

              Text(`当前: ${this.readerState.currentPageIndex + 1} / ${this.readerState.currentChapter?.pages.length || 0}`)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))

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
                  .fontColor($r('app.color.text_secondary'))
                  .backgroundColor($r('app.color.background_secondary'))
                  .onClick(() => {
                    this.hideJumpToPageDialogWithAnimation();
                  })

                Button('跳转')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
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
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

        // 翻页动画设置面板
        if (this.showPageTurnAnimationSettings) {
          Stack() {
            // 遮罩
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor($r('app.color.background_overlay'))
              .opacity(0.5)
              .onClick(() => {
                this.hidePageTurnAnimationSettingsWithAnimation();
              })

            // 面板
            Column() {
              // 标题
              Row() {
                Text('翻页动画设置')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)

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

              // 动画类型选择
              Text('基础动画')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ bottom: 8 })

              // 第一行：基础动画
              Row() {
                this.buildAnimButton('无', PageTurnAnimationType.NONE)
                this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
                this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ bottom: 8 })

              // 第二行：3D动画
              Row() {
                this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
                this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
                this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ bottom: 16 })

              // 拟真动画分类
              Text('拟真动画')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .margin({ bottom: 8 })

              // 拟真动画：卷页效果（只有单页LTR/RTL模式可用）
              Row() {
                if (this.isCurlAnimationSupported()) {
                  this.buildAnimButton('卷页', PageTurnAnimationType.CURL)
                } else {
                  // 禁用状态的卷页按钮
                  Column() {
                    Text('卷页')
                      .fontSize(13)
                      .fontColor($r('app.color.text_secondary'))
                    Text('(仅单页左右翻页)')
                      .fontSize(10)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 2 })
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
              
              // 卷页透明度设置（仅在选择卷页动画且模式支持时显示）
              if (this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL && this.isCurlAnimationSupported()) {
                Column() {
                  Row() {
                    Text('卷页背面透明度')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                    Text(`${this.readingSettings.curlBackOpacity ?? 90}%`)
                      .fontSize(14)
                      .fontColor($r('app.color.accent'))
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
          .width('100%')
          .height('100%')
          .zIndex(1200)
        }

        // 交互区域提示overlay（最高层级）
        // 关键：使用componentWidth/componentHeight（组件实际渲染尺寸）
        // 确保与handleHorizontalTap等交互判断使用相同的尺寸来源
        if (this.showInteractionOverlay) {
          MangaInteractionOverlay({
            params: {
              readingMode: this.readingSettings.readingMode,
              readingDirection: this.readingSettings.readingDirection,
              componentWidth: this.componentWidth > 0 ? this.componentWidth : this.screenWidth,
              componentHeight: this.componentHeight > 0 ? this.componentHeight : this.screenHeight,
              deviceOrientation: this.getDeviceOrientation(),
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

        // 调试：点击位置指示器（已禁用，用于调试点击坐标）
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

        // 隐藏的WebView组件（用于WebView图源动态加载页面列表）
        Web({ src: 'about:blank', controller: this.webviewController })
          .width(0)
          .height(0)
          .visibility(Visibility.None)
          .zIndex(-1)
      }
      .width('100%')
      .height('100%')
      .opacity(this.contentOpacity)
      .focusable(true)
      .defaultFocus(true)
      .onKeyEvent((event: KeyEvent) => {
        // 处理音量键翻页
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
      // 返回键处理
      return false;
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      
      // 获取传入的参数
      const params = context.pathInfo.param as MangaReaderPageParams;
      if (params) {
        const ctStr: string = String(params.contentType);
        const sidStr: string = params.sourceId !== undefined ? String(params.sourceId) : '未指定';
        const snameStr: string = params.sourceName ? String(params.sourceName) : '未指定';
        logger.info(TAG, `接收到阅读器参数: mangaId=${params.mangaId}, chapterId=${params.chapterId}, pageIndex=${params.pageIndex ?? '未指定'}, contentType=${ctStr}, sourceId=${sidStr}, sourceName=${snameStr}`);
        if (params.manga) {
          const mTitle: string = params.manga.title || '未知标题';
          const mId: string = params.manga.id || '未知ID';
          const mSrcName: string = params.manga.sourceInfo && params.manga.sourceInfo.sourceName ? String(params.manga.sourceInfo.sourceName) : '未指定';
          logger.info(TAG, `接收到漫画对象: title=${mTitle}, id=${mId}, sourceName=${mSrcName}`);
        }
        
        // [修复] 始终调用初始化，即使参数已存在（可能是章节切换）
        if (!this.pageParams) {
          this.initializeMangaReader(params);
        } else {
          logger.debug(TAG, '参数已存在，但仍需更新配置（可能是章节切换）');
          this.initializeMangaReader(params);
        }
      } else {
        logger.error(TAG, '未接收到有效的阅读器参数');
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
      logger.error(TAG, '解析GlobalNavStack参数失败', e instanceof Error ? e.message : String(e));
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
        fromPage: hasFromPage ? String(raw['fromPage']) : '未指定'
      } as MangaReaderPageParams;
      return result;
    } catch (e) {
      logger.error(TAG, '解析Router参数失败', e instanceof Error ? e.message : String(e));
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
      logger.error(TAG, '未找到阅读器参数');
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
  OnlineDownloaded = 'OnlineDownloaded'
}
