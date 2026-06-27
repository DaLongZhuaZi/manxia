// 文件路径: src/main/ets/components/MangaViewer.ets
/**
 * 漫画查看器核心组件
 * 支持单页/双页/连续滚动模式、缩放、手势翻页、图片预加载等功能
 */

import { logger } from '../Utils/Logger';
import {
  getHoldingAwarenessManager,
  HoldingAwarenessFeature,
  HoldingAwarenessManager,
  HoldingUiAnchor
} from '../Framework/Managers/HoldingAwarenessManager';
import {
  GlobalAnimationManager,
  AnimationType,
  AnimationUtils,
  globalAnimationManager
} from '../Framework/Animation/GlobalAnimationSystem';
import {
  MangaPage,
  MangaChapter,
  ReadingMode,
  ReadingDirection,
  ReadingSettings,
  ImageSourceType,
  PageTurnAnimationType,
  DoublePagePortraitLayout,
  DoublePageVerticalDirection
} from '../Models/MangaModels';
import { colorMap } from '../Data/ResourceMap';
import {
  curves,
  UIContext,
  matrix4
} from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { RequestHeaders } from '../Framework/Cache/ImageCacheManager';
import { PageCurlEffectV2, PageCurlConfigV2, CurlStartPosition } from './PageCurlEffectV2';
import { DualPageCurlEffect } from './DualPageCurlEffect';
import {
  ContinuousPageIndexDataSource,
  MangaPageDataSource,
  WebtoonLazyDataSource
} from './MangaLazyDataSources';
// 新增：预加载管理系统
import { PreloadManager, PreloadTaskItem } from './PreloadManager';
import { ImageLoadStateManager, ImageLoadState as NewImageLoadState, LoadStatsInfo, PageState } from './ImageLoadStateManager';
import { PreloadDebugInfo } from './PreloadDebugOverlay';
import { MangaPreloadRunnableBatch, MangaPreloadTaskCoordinator } from './MangaPreloadTaskCoordinator';
import {
  MangaNormalPreloadInput,
  MangaPreloadInitTarget,
  MangaPreloadPlan,
  MangaPreloadPlanner,
  MangaSinglePagePreloadInput,
  MangaWebtoonPreloadInput
} from './MangaPreloadPlanner';
import {
  ImageLoadState,
  MangaLoadStateCommitter,
  MangaViewerImageDimensions
} from './MangaLoadStateCommitter';
// 新增：本地图片缓存管理器
import { CacheStats, LocalImageCacheManager } from '../Framework/Cache/LocalImageCacheManager';
import { MangaAssetLoadCoordinator } from '../Framework/Reader/MangaAssetLoadCoordinator';
import { MangaAssetLoader } from '../Framework/Reader/MangaAssetLoader';
import { MangaAssetMetricsSnapshot, MangaAssetMonitor } from '../Framework/Reader/MangaAssetMonitor';
import { MangaAssetRequestContext, MangaAssetRequestFactory } from '../Framework/Reader/MangaAssetRequestFactory';
import {
  MangaAssetLoadReason,
  MangaAssetLoadRequest,
  MangaAssetLoadResult
} from '../Framework/Reader/MangaAssetTypes';
import {
  MangaReaderSessionGuard,
  MangaReaderSessionSnapshot
} from '../Framework/Reader/MangaReaderSessionGuard';
import {
  MangaAssetLoadContextInput,
  MangaAssetLoadContextResolver
} from './MangaAssetLoadContextResolver';
import {
  MangaLoadedPagePresentationContext,
  MangaLoadedPagePresentationPlan,
  MangaLoadedPagePresentationPlanner
} from './MangaLoadedPagePresentationPlanner';
import {
  MangaPageLoadResolver,
  MangaPageResolveContext,
  MangaPreloadPageResolveResult
} from './MangaPageLoadResolver';
import { MangaPagePathResolver } from './MangaPagePathResolver';
import {
  MangaPageVisibilityContext,
  MangaPageVisibilityResolver,
  MangaPageVisibilityResult
} from './MangaPageVisibilityResolver';
import {
  MangaPixelMapLifecycleManager,
  MangaPixelMapLifecycleResult,
  MangaPixelMapMeta
} from './MangaPixelMapLifecycleManager';
import { ChapterBoundary, WebtoonDataItem, WebtoonPageRef } from './MangaWebtoonTypes';
import {
  MangaWebtoonPositionContext,
  MangaWebtoonPositionManager
} from './MangaWebtoonPositionManager';
import {
  MangaWebtoonDataPlan,
  MangaWebtoonDataPlanKind,
  MangaWebtoonDataPlanner,
  MangaWebtoonDataPlannerInput
} from './MangaWebtoonDataPlanner';
import {
  MangaWebtoonChapterCleanupRange,
  MangaWebtoonCleanupInput,
  MangaWebtoonCleanupPlan,
  MangaWebtoonCleanupPlanner,
  MangaWebtoonLocalCacheCleanupPlan
} from './MangaWebtoonCleanupPlanner';
import {
  MangaWebtoonBoundaryInput,
  MangaWebtoonBoundaryPlan,
  MangaWebtoonBoundaryPlanner
} from './MangaWebtoonBoundaryPlanner';
import {
  MangaWebtoonChapterSwitchBoundaryRange,
  MangaWebtoonChapterSwitchInput,
  MangaWebtoonChapterSwitchPlan,
  MangaWebtoonChapterSwitchPlanner
} from './MangaWebtoonChapterSwitchPlanner';
import {
  MangaWebtoonGesturePlanner,
  MangaWebtoonPanInput,
  MangaWebtoonPanPlan,
  MangaWebtoonPinchEndInput,
  MangaWebtoonPinchEndPlan,
  MangaWebtoonPinchInput,
  MangaWebtoonPinchPlan
} from './MangaWebtoonGesturePlanner';
import {
  MangaWebtoonFallbackPageRange,
  MangaWebtoonFallbackViewportInput,
  MangaWebtoonProgressInput,
  MangaWebtoonProgressPlan,
  MangaWebtoonViewportInput,
  MangaWebtoonViewportItemRange,
  MangaWebtoonViewportPlan,
  MangaWebtoonViewportPlanner
} from './MangaWebtoonViewportPlanner';
import {
  MangaContinuousHorizontalBoundaryInput,
  MangaContinuousHorizontalBoundaryPlan,
  MangaContinuousHorizontalBoundaryPlanner
} from './MangaContinuousHorizontalBoundaryPlanner';
import {
  MangaWebtoonPrewarmInput,
  MangaWebtoonPrewarmPlan,
  MangaWebtoonPrewarmPlanner
} from './MangaWebtoonPrewarmPlanner';
import {
  MangaWebtoonAdjacentChapterInput,
  MangaWebtoonAdjacentChapterPlan,
  MangaWebtoonAdjacentChapterPlanner
} from './MangaWebtoonAdjacentChapterPlanner';
import {
  MangaContinuousHorizontalPageRange,
  MangaContinuousHorizontalProgressInput,
  MangaContinuousHorizontalProgressPlan,
  MangaContinuousHorizontalViewportInput,
  MangaContinuousHorizontalViewportPlan,
  MangaContinuousHorizontalViewportPlanner
} from './MangaContinuousHorizontalViewportPlanner';
import {
  MangaPageTurnInput,
  MangaPageTurnPlan,
  MangaPageTurnPlanner
} from './MangaPageTurnPlanner';
import {
  MangaCurlFallbackInput,
  MangaCurlFallbackPlan,
  MangaCurlProgressInput,
  MangaCurlProgressPlan,
  MangaCurlReleaseInput,
  MangaCurlReleasePlan,
  MangaCurlStartInput,
  MangaCurlStartPlan,
  MangaCurlSupportInput,
  MangaCurlTurnPlanner
} from './MangaCurlTurnPlanner';
import {
  MangaCurlDualPixelMapInput,
  MangaCurlDualPixelMapPlan,
  MangaCurlPixelMapResolver,
  MangaCurlPixelMapSlot,
  MangaCurlPixelMapSlotRequest,
  MangaCurlSinglePixelMapInput,
  MangaCurlSinglePixelMapPlan
} from './MangaCurlPixelMapResolver';
import {
  MangaDisplayInputRequest,
  MangaDisplayInputResolver,
  MangaDisplayInputResult,
  MangaDisplayInputValue
} from './MangaDisplayInputResolver';
import {
  MangaReaderCacheMonitor,
  MangaReaderCacheOwnershipItem,
  MangaReaderCacheSnapshot,
  MangaReaderCacheSnapshotInput
} from './MangaReaderCacheMonitor';
import { MangaReadFlowMonitor } from '../Framework/Reader/MangaReadFlowMonitor';
import {
  MangaReadFlowSessionBridge,
  MangaReadFlowSessionBridgeContext,
  MangaReadFlowSessionBridgeResult
} from '../Framework/Reader/MangaReadFlowSessionBridge';
import {
  MangaReadFlowEvent,
  MangaReadFlowEventType,
  MangaReadFlowSeverity,
  MangaReadFlowSourceKind,
  mapReadingModeToFlowMode
} from '../Framework/Reader/MangaReadFlowTypes';
import {
  MangaScrollableReadFlowContext,
  MangaScrollableReadFlowReporter
} from '../Framework/Reader/MangaScrollableReadFlowReporter';
import {
  DoublePageSmartDisplayMode,
  DoublePageSmartDisplayPlan,
  DoublePageSmartDisplayReason,
  DoublePageSmartLayoutHelper,
  PageDimensionsInfo
} from '../Utils/DoublePageSmartLayoutHelper';

const TAG = 'MangaViewer';
const SINGLE_CURL_PIXELMAP_WAIT_TIMEOUT_MS: number = 3000;
const DOUBLE_CURL_PIXELMAP_WAIT_TIMEOUT_MS: number = 500;

/**
 * 图片显示区域接口
 */
interface ImageDisplayRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * 漫画查看器参数接口
 */
export interface MangaViewerParams {
  /** 当前章节 */
  chapter: MangaChapter;
  /** 当前页面索引 */
  currentPageIndex: number;
  /** 阅读设置 */
  readingSettings: ReadingSettings;
  /** 缩放比例 */
  zoomScale: number;
  /** 页面切换回调 */
  onPageChange?: (pageIndex: number) => void;
  /** 章节切换回调 */
  onChapterChange?: (direction: 'prev' | 'next') => void;
  /** 缩放变化回调 */
  onZoomChange?: (scale: number) => void;
  /** 单击回调 */
  onSingleTap?: (event: ClickEvent) => void;
  /** 双击回调 */
  onDoubleTap?: (event: ClickEvent) => void;
  /** 滚动位置变化回调 */
  onScrollPositionChange?: (position: number) => void;
  /** 条漫检测回调 - 当检测到图片是条漫格式时触发 */
  onWebtoonDetected?: (isWebtoon: boolean, avgAspectRatio: number) => void;
  /** 前一章节（条漫模式连续滚动用） */
  prevChapter?: MangaChapter;
  /** 后一章节（条漫模式连续滚动用） */
  nextChapter?: MangaChapter;
  /** 请求加载相邻章节的回调 */
  onRequestAdjacentChapter?: (direction: 'prev' | 'next') => void;
}

/**
 * 页面数据接口
 */
interface PageData {
  /** 页面对象 */
  page: MangaPage | null;
  /** 加载状态 */
  loadState: ImageLoadState | undefined;
}

/**
 * 动画选项
 */
export interface AnimateOptions {
  /** 动画持续时间（毫秒） */
  duration: number;
  /** 动画曲线 */
  curve: Curve;
  /** 迭代次数 */
  iterations?: number;
  /** 播放模式 */
  playMode?: PlayMode;
}

// 定义事件回调接口
interface MangaViewerCallbacks {
  onPageChange: (pageIndex: number) => void;
  onChapterChange: (direction: 'prev' | 'next') => void;
  onZoomChange: (scale: number) => void;
  onSingleTap: (event: ClickEvent) => void;
  onDoubleTap: (event: ClickEvent) => void;
  onScrollPositionChange?: (position: number) => void;
  onComponentReady?: (component: MangaViewer) => void;
  onFirstVisibleDisplayCommitted?: (pageIndex: number, pageId: string, sourceType: ImageSourceType) => void;
  onWebtoonDetected?: (isWebtoon: boolean, avgAspectRatio: number) => void;  // 条漫检测回调
  // [新增] 条漫模式章节切换回调 - 当滚动到其他章节时通知父组件
  onWebtoonChapterSwitch?: (chapterId: string, chapterTitle: string, pageIndex: number) => void;
}

interface ImageCacheMeta {
  path: string;
  size: number;
}

@Component
export struct MangaViewer {
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_TOLERANCE_VP: number = 18;
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_GUIDE_ZONE_VP: number = 132;
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_HINT_VP: number = 28;
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_TRIGGER_VP: number = 76;
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_MAX_PULL_VP: number = 88;
  private static readonly VERTICAL_DOUBLE_PAGE_EDGE_COOLDOWN_MS: number = 420;

  @Prop chapter: MangaChapter;
  @Prop @Watch('onCurrentPageIndexChange') currentPageIndex: number;
  @State private viewCurrentPageIndex: number = 0;
  @Prop @Watch('onReadingSettingsChange') readingSettings: ReadingSettings;
  @Prop zoomScale: number;
  @Prop toolbarsVisible: boolean;
  @Prop callbacks: MangaViewerCallbacks;
  @Prop networkHeaders?: RequestHeaders;
  @Prop @Watch('onNetworkHeadersChange') networkHeadersTick: number = 0;
  @Prop @Watch('onChapterChange') chapterTick: number = 0; // [新增] 章节切换计数器
  @Prop sourceId?: number;
  @Prop mangaId?: string;
  @Prop readFlowSessionId: string = '';
  @Prop onlineDownloadedWarmupState?: string;
  @Prop onlineDownloadedArchivePath?: string;
  @Prop onlineDownloadedExtractDir?: string;
  @Prop onlineDownloadedReusedExtract: boolean = false;
  @Prop onlineDownloadedArchivePageCount: number = 0;
  @Prop onlineDownloadedNetworkPageCount: number = 0;
  @StorageProp('holding_awareness_preferred_anchor') private holdingAwarenessPreferredAnchor: HoldingUiAnchor = HoldingUiAnchor.RIGHT;
  @StorageProp('holding_awareness_enabled') private holdingAwarenessEnabled: boolean = true;
  @StorageProp('holding_awareness_manga_webtoon_quick_navigation_enabled') private holdingAwarenessMangaWebtoonQuickNavigationEnabled: boolean = true;
  private holdingAwarenessManager: HoldingAwarenessManager = getHoldingAwarenessManager();

  // [新增] 条漫模式多章节支持
  @Prop @Watch('onAdjacentChapterChange') prevChapter?: MangaChapter; // 前一章节
  @Prop @Watch('onAdjacentChapterChange') nextChapter?: MangaChapter; // 后一章节
  @Prop isFirstChapter: boolean = false; // 是否是第一章（没有上一章）
  @Prop isLastChapter: boolean = false;  // 是否是最后一章（没有下一章）
  // 注意：回调函数不能使用@Prop装饰器，直接作为普通属性传递
  onRequestAdjacentChapter?: (direction: 'prev' | 'next') => void; // 请求加载相邻章节
  loadPixivImageCallback?: (imageUrl: string) => Promise<ArrayBuffer | null>; // Pixiv WebView图片加载回调

  // [新增] 条漫多章节状态
  @State private webtoonDataItems: WebtoonDataItem[] = []; // 合并的多章节数据项
  @State private chapterBoundaries: ChapterBoundary[] = []; // 章节边界信息
  private webtoonPageRefById: Map<string, WebtoonPageRef> = new Map();
  private webtoonOrderedPageIds: string[] = [];
  private webtoonVisibleItemIndices: number[] = [];
  @State private currentChapterId: string = ''; // 当前显示的章节ID
  @State private isPrevChapterLoading: boolean = false; // 前一章节加载中
  @State private isNextChapterLoading: boolean = false; // 后一章节加载中
  @State private prevChapterRequested: boolean = false; // 是否已请求加载前一章节
  @State private nextChapterRequested: boolean = false; // 是否已请求加载后一章节

  // [修复②] 上一章双重上滑确认机制
  @State private prevChapterSwipeConfirmPending: boolean = false; // 等待第二次上滑确认
  private prevChapterSwipeConfirmTimer: number = -1; // 确认超时计时器
  private prevChapterSwipeConfirmTime: number = 0; // 首次上滑时间戳

  // 新增：预加载调试信息（用于传递给MangaReaderPage）
  @Link preloadDebugInfo: PreloadDebugInfo;

  // 新增：预加载管理器
  private preloadManager: PreloadManager = new PreloadManager();

  // 新增：图片加载状态管理器
  private imageLoadStateManager: ImageLoadStateManager = new ImageLoadStateManager();

  private mangaPreloadTaskCoordinator: MangaPreloadTaskCoordinator = new MangaPreloadTaskCoordinator();
  private mangaLoadStateCommitter: MangaLoadStateCommitter = new MangaLoadStateCommitter();
  private mangaPagePathResolver: MangaPagePathResolver = new MangaPagePathResolver();
  private mangaPageLoadResolver: MangaPageLoadResolver = new MangaPageLoadResolver();
  private mangaAssetLoadContextResolver: MangaAssetLoadContextResolver = new MangaAssetLoadContextResolver();
  private mangaPageVisibilityResolver: MangaPageVisibilityResolver = new MangaPageVisibilityResolver();
  private mangaLoadedPagePresentationPlanner: MangaLoadedPagePresentationPlanner = new MangaLoadedPagePresentationPlanner();
  private mangaPixelMapLifecycleManager: MangaPixelMapLifecycleManager = new MangaPixelMapLifecycleManager();
  private mangaPreloadPlanner: MangaPreloadPlanner = new MangaPreloadPlanner();
  private mangaWebtoonPositionManager: MangaWebtoonPositionManager = new MangaWebtoonPositionManager();
  private mangaWebtoonDataPlanner: MangaWebtoonDataPlanner = new MangaWebtoonDataPlanner();
  private mangaWebtoonCleanupPlanner: MangaWebtoonCleanupPlanner = new MangaWebtoonCleanupPlanner();
  private mangaWebtoonBoundaryPlanner: MangaWebtoonBoundaryPlanner = new MangaWebtoonBoundaryPlanner();
  private mangaWebtoonChapterSwitchPlanner: MangaWebtoonChapterSwitchPlanner = new MangaWebtoonChapterSwitchPlanner();
  private mangaWebtoonGesturePlanner: MangaWebtoonGesturePlanner = new MangaWebtoonGesturePlanner();
  private mangaWebtoonViewportPlanner: MangaWebtoonViewportPlanner = new MangaWebtoonViewportPlanner();
  private mangaContinuousHorizontalBoundaryPlanner: MangaContinuousHorizontalBoundaryPlanner =
    new MangaContinuousHorizontalBoundaryPlanner();
  private mangaWebtoonPrewarmPlanner: MangaWebtoonPrewarmPlanner = new MangaWebtoonPrewarmPlanner();
  private mangaWebtoonAdjacentChapterPlanner: MangaWebtoonAdjacentChapterPlanner =
    new MangaWebtoonAdjacentChapterPlanner();
  private mangaContinuousHorizontalViewportPlanner: MangaContinuousHorizontalViewportPlanner =
    new MangaContinuousHorizontalViewportPlanner();
  private mangaPageTurnPlanner: MangaPageTurnPlanner = new MangaPageTurnPlanner();
  private mangaCurlTurnPlanner: MangaCurlTurnPlanner = new MangaCurlTurnPlanner();
  private mangaCurlPixelMapResolver: MangaCurlPixelMapResolver = new MangaCurlPixelMapResolver();
  private mangaDisplayInputResolver: MangaDisplayInputResolver = new MangaDisplayInputResolver();
  private mangaReaderCacheMonitor: MangaReaderCacheMonitor = new MangaReaderCacheMonitor();
  private mangaReadFlowMonitor: MangaReadFlowMonitor = MangaReadFlowMonitor.getInstance();
  private mangaReadFlowSessionBridge: MangaReadFlowSessionBridge = new MangaReadFlowSessionBridge();
  private mangaScrollableReadFlowReporter: MangaScrollableReadFlowReporter = new MangaScrollableReadFlowReporter();
  private mangaReaderCacheOwnershipLogged: boolean = false;
  private firstVisibleDisplayCommitted: boolean = false;

  // 屏幕尺寸属性
  @State private screenWidth: number = 0;
  @State private screenHeight: number = 0;

  // 内部状态
  @State private imageLoadStates: Map<string, ImageLoadState> = new Map();
  @State private pagePixelMaps: Map<string, image.PixelMap> = new Map();
  @State private pixelMapEpochByPage: Map<string, number> = new Map();
  @State private pageImageBindings: Map<number, string> = new Map();
  @State private singlePageImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private singlePagePageId: string = '';
  @State private softTransitionOverlayInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private softTransitionOverlayPageId: string = '';
  @State private softTransitionOverlayOpacity: number = 0;
  @State private showSoftTransitionOverlay: boolean = false;
  @State private softTransitionOverlayTranslateX: number = 0;
  @State private softTransitionOverlayTranslateY: number = 0;
  @State private previewPrevImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevPageId: string = '';
  @State private previewNextImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewNextPageId: string = '';
  @State private previewPrevLeftImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevLeftPageId: string = '';
  @State private previewPrevRightImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevRightPageId: string = '';

  public kickstartLoading(): void {
    // 使用新的统一预加载方法
    this.triggerUnifiedPreload();
    try {
      if (this.chapter && this.chapter.pages && this.chapter.pages.length > 0) {
        const idx: number = (this.viewCurrentPageIndex >= 0 && this.viewCurrentPageIndex < this.chapter.pages.length) ? this.viewCurrentPageIndex : 0;
        const page: MangaPage = this.chapter.pages[idx];
        const st: ImageLoadState | undefined = this.getPageLoadState(page);
        const hasPm: boolean = this.pagePixelMaps.has(page.id);
        if (!hasPm && (!st || !st.isLoading)) {
          this.loadImage(page);
          logger.debug(TAG, `触发首图加载: index=${idx}, id=${page.id}`);
        }
      }
    } catch (e) {
      logger.warn(TAG, '触发首图加载失败' + String(e));
    }
  }
  @State private previewNextLeftImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewNextLeftPageId: string = '';
  @State private previewNextRightImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewNextRightPageId: string = '';
  @State private doubleLeftImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private doubleLeftPageId: string = '';
  @State private doubleRightImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private doubleRightPageId: string = '';
  @State private verticalDoubleTopPageIndex: number = -1;
  @State private verticalDoubleTopPageId: string = '';
  @State private verticalDoubleTopImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private verticalDoubleBottomPageIndex: number = -1;
  @State private verticalDoubleBottomPageId: string = '';
  @State private verticalDoubleBottomImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private verticalDoubleCurrentContentKey: string = 'vertical_current_empty';
  @State private verticalDoubleCurrentContentIdentity: string = 'vertical_identity_empty';
  @State private verticalDoubleCurrentLayerToggle: boolean = false;
  private pagePixelMapMeta: Map<string, MangaPixelMapMeta> = new Map();
  @State private currentScale: number = 1.0;
  // 双页模式渲染所需的左右页索引（使用@State确保UI响应式刷新）
  @State private leftPageIndex: number = -1;
  @State private rightPageIndex: number = -1;
  @State private currentDoublePageDisplayMode: DoublePageSmartDisplayMode = DoublePageSmartDisplayMode.DUAL;
  @State private currentDoublePageDisplayReason: DoublePageSmartDisplayReason = DoublePageSmartDisplayReason.NORMAL_PAIR;
  @State private previewPrevSingleDoublePage: boolean = false;
  @State private previewNextSingleDoublePage: boolean = false;
  @State private translateX: number = 0;
  @State private translateY: number = 0;
  @State private isDragging: boolean = false;
  @State private swipeTriggered: boolean = false;
  @State private lastSwipeAt: number = 0;
  private readonly SWIPE_COOLDOWN_MS: number = 250;
  @State private pageChangeCommitted: boolean = false;
  
  // 条漫自动检测相关
  private webtoonDetectionDone: boolean = false;  // 是否已完成检测
  private detectedAspectRatios: number[] = [];    // 已检测的图片宽高比
  private readonly WEBTOON_ASPECT_RATIO_THRESHOLD: number = 2.0;  // 条漫判定阈值（高/宽 > 2）
  private readonly WEBTOON_DETECTION_SAMPLE_COUNT: number = 3;    // 检测样本数量
  @State private isCommittingPageTurn: boolean = false;

  // 条漫优化相关状态
  @State visiblePageIndices: number[] = [];
  @State scrollPosition: number = 0;
  @State isScrolling: boolean = false;
  @State preloadedImages: Set<number> = new Set();
  @State savedScrollPosition: number = 0; // 保存的滚动位置
  @State smoothScrollTarget: number = -1; // 平滑滚动目标位置
  @State currentWebtoonPage: number = 0; // 当前条漫页面
  @State showWebtoonProgress: boolean = true; // 显示条漫进度
  @State webtoonScrollProgress: number = 0; // 条漫滚动进度 (0-1)
  private scrollTimer: number = -1;
  private pendingWebtoonSwitchNotifyTimer: number = -1; // 条漫章节切换通知防抖
  private webtoonStopCleanupTimer: number = -1; // 条漫滚动停止后延迟清理，减少闪烁
  private lastUpdateTime: number = 0;
  private scrollPositionKey: string = ''; // 滚动位置存储键
  private continuousHorizontalBoundarySuppressUntil: number = 0;
  private lastHeavyUpdateTime: number = 0; // [性能优化] 重型操作的上次执行时间
  private readonly WEBTOON_HEAVY_UPDATE_THROTTLE_LOCAL_MS: number = 160;
  private readonly WEBTOON_HEAVY_UPDATE_THROTTLE_ONLINE_MS: number = 260;
  private readonly WEBTOON_SWITCH_STABLE_MS_LOCAL: number = 90;
  private readonly WEBTOON_SWITCH_STABLE_MS_ONLINE: number = 220;
  private readonly WEBTOON_SWITCH_COOLDOWN_MS_LOCAL: number = 180;
  private readonly WEBTOON_SWITCH_COOLDOWN_MS_ONLINE: number = 420;
  private readonly WEBTOON_SWITCH_HYSTERESIS_RATIO: number = 0.18;
  private readonly WEBTOON_SWITCH_HYSTERESIS_MIN_PX: number = 120;
  private readonly WEBTOON_SWITCH_HYSTERESIS_MAX_PX: number = 320;
  private pendingWebtoonChapterCandidateId: string = '';
  private pendingWebtoonChapterCandidateSince: number = 0;
  private pendingWebtoonChapterCandidatePageIndex: number = 0;
  private lastCommittedWebtoonChapterSwitchAt: number = 0;
  private lastNotifiedWebtoonChapterId: string = '';
  private lastNotifiedWebtoonPageIndex: number = -1;
  private lastPrevAdjacentRequestAt: number = 0;
  private lastNextAdjacentRequestAt: number = 0;
  private webtoonBoundaryCacheProtectUntil: number = 0;
  private lastBoundaryPrewarmAt: Map<string, number> = new Map();
  // 旧 URL 元信息缓存：只记录优化图片链路的预加载 URL 和估算大小，不持有 PixelMap。
  private imageCache: Map<string, ImageCacheMeta> = new Map();
  private imageCacheSize: number = 0;
  private readonly MAX_CACHE_SIZE: number = 50 * 1024 * 1024; // 50MB
  private readonly PRELOAD_RANGE: number = 8; // 预加载前后页的基础范围
  private readonly CACHE_CLEANUP_THRESHOLD: number = 0.8; // 缓存使用率达到80%时清理
  private pendingLoadTimers: Map<string, number> = new Map();
  private softTransitionFallbackTimer: number = -1;
  private softTransitionStartTimer: number = -1;
  private softTransitionTargetTranslateX: number = 0;
  private softTransitionTargetTranslateY: number = 0;

  // 图源预加载设置（从外部传入）
  @Prop preloadCurrentPages?: number; // 当前章节预加载页数，默认10
  @Prop preloadNextPages?: number;    // 下一章节预加载页数，默认-1（全部）

  // 条漫手势优化
  @State private webtoonZoomScale: number = 1.0;
  @State private webtoonOffsetX: number = 0;
  @State private webtoonOffsetY: number = 0;
  @State private isZooming: boolean = false;
  // 缩放焦点（内容坐标系），用于以用户触点为中心缩放
  @State private webtoonScaleCenterX: number = 0;
  @State private webtoonScaleCenterY: number = 0;
  private webtoonPinchStartOffsetX: number = 0;
  private webtoonPinchStartOffsetY: number = 0;
  private readonly DOUBLE_TAP_THRESHOLD: number = 300; // 双击间隔阈值（毫秒）
  private readonly MIN_ZOOM_SCALE: number = 1.0;
  private readonly MAX_ZOOM_SCALE: number = 3.0;

  // 手势相关
  @State private panStartX: number = 0;
  @State private panStartY: number = 0;
  private panStartTime: number = 0;  // 拖拽起始时间戳（用于快速翻页速度检测）
  @State private initialTranslateX: number = 0;
  @State private initialTranslateY: number = 0;

  // 滚动相关（连续滚动模式）
  @State private scrollOffset: number = 0;
  private scroller: Scroller = new Scroller();
  @State private verticalDoublePageScrollOffset: number = 0;
  @State private verticalDoublePageTurnAction: 'next' | 'prev' | null = null;
  private verticalDoublePageBoundaryAccumulator: number = 0;
  private verticalDoublePageBoundaryDirection: 'top' | 'bottom' | '' = '';
  private verticalDoublePageBoundaryLastTime: number = 0;
  @State private verticalDoublePageEdgeHintProgress: number = 0;
  private verticalDoublePageLastPanOffsetY: number = 0;
  private verticalDoublePageLastScrollDeltaY: number = 0;
  private verticalDoublePagePanStartScrollOffset: number = 0;
  private verticalDoublePageReleasePullY: number = 0;
  private verticalDoublePageProgrammaticScrollUntil: number = 0;

  // 动画系统
  private animationManager: GlobalAnimationManager = globalAnimationManager;
  private animationId: string = '';
  private uiContext: UIContext | undefined = undefined;

  // 翻页动画状态
  @State private isPageTurning: boolean = false;
  @State private suppressExternalIndex: boolean = false;
  // [修复] 初始化保护标志，防止 onCurrentPageIndexChange 在初始化期间被错误触发
  private isInitialized: boolean = false;
  @State private pageTurnDirection: 'left' | 'right' | 'up' | 'down' | null = null;
  @State private pageTurnProgress: number = 0;
  @State private renderEpoch: number = 0;
  // 翻页动画效果状态变量
  @State private pageTurnOpacity: number = 1.0;        // 淡入淡出
  @State private pageTurnScale: number = 1.0;          // 缩放
  @State private pageTurnTranslateX: number = 0;       // 滑动X
  @State private pageTurnTranslateY: number = 0;       // 滑动Y
  @State private pageTurnRotateY: number = 0;          // 翻转Y轴旋转
  @State private pageTurnRotateX: number = 0;          // 翻转X轴旋转
  @State private pageTurnRotateZ: number = 0;          // 翻转Z轴旋转
  @State private pageTurnPerspective: number = 0;      // 3D透视深度
  @State private pageTurnSkewX: number = 0;            // 倾斜X
  @State private pageTurnSkewY: number = 0;            // 倾斜Y
  // 3D变换矩阵（用于真正的3D效果）
  @State private pageTurnMatrix: matrix4.Matrix4Transit = matrix4.identity();
  // 当前动画类型（用于UI判断使用哪种变换方式）
  @State private currentAnimationType: PageTurnAnimationType = PageTurnAnimationType.NONE;
  // Canvas卷页相关状态
  @State private showCanvasCurl: boolean = false;  // 是否显示Canvas卷页效果
  @State private curlProgress: number = 0;         // 卷页进度 (0-1)，用于实时拖拽
  @State private curlAnimateTarget: number = -1;   // 内部动画目标进度（-1 表示不使用）
  @State private curlAnimateFrom: number = 0;      // 内部动画起始进度
  @State private curlAnimateVelocity: number = 0;  // 脱手时的翻页速度（progress/ms），用于速度延续动画
  @State private curlCurrentPixelMap: image.PixelMap | null = null;  // 当前页PixelMap
  @State private curlNextPixelMap: image.PixelMap | null = null;     // 下一页PixelMap
  @State private curlIsForward: boolean = true;    // 翻页方向
  @State private curlStartPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;  // 翻页起始位置
  @State private curlTouchY: number = 0;           // 触摸起始Y坐标（用于角落翻页）
  // 卷页动画期间的待切换页面索引（延迟切换）
  private curlPendingPageIndex: number = -1;       // -1表示无待切换页面
  private curlAnimationCallbacks: (() => void)[] = [];  // 动画完成后的回调
  // 图片显示区域（用于Canvas卷页）
  @State private imageDisplayRect: ImageDisplayRect = { x: 0, y: 0, w: 360, h: 640 };
  // Canvas卷页配置
  private curlEffectConfig: PageCurlConfigV2 = {
    stripCount: 24,
    maxCurlHeight: 100,
    shadowIntensity: 0.6,
    animationDuration: 300,  // 回弹/完成动画时长
    enableShadow: true,
    enableHighlight: true,
    flipThreshold: 0.33      // 翻页阈值（单页宽度的 1/3）
  };

  // ========== 双页卷页动画状态 ==========
  @State private showDualCurlEffect: boolean = false;  // 是否显示双页卷页效果
  @State private dualCurlEffectOpacity: number = 1.0;  // 双页卷页效果层透明度（用于淡出过渡）
  @State private dualCurlProgress: number = 0;         // 双页卷页进度 (0-1)
  // 双页卷页的 4 张 PixelMap（不使用 @State 避免深拷贝）
  private dualCurlLeftPM: image.PixelMap | null = null;      // 当前左页
  private dualCurlRightPM: image.PixelMap | null = null;     // 当前右页
  private dualCurlNextLeftPM: image.PixelMap | null = null;  // 目标左页
  private dualCurlNextRightPM: image.PixelMap | null = null; // 目标右页
  private dualCurlPendingPairStart: number = -1;  // 待切换的页对起始索引
  private dualCurlAnimTimer: number = -1;         // 双页卷页动画定时器

  // 预加载相关
  private preloadRange: number = 2; // 预加载前后2页

  // 内容类型（用于判断预加载策略）
  @Prop contentType?: string;

  // LazyForEach 数据源（ArkUI 要求 IDataSource 实例）
  private pageDataSource: MangaPageDataSource = new MangaPageDataSource([]);
  private continuousHorizontalDataSource: ContinuousPageIndexDataSource = new ContinuousPageIndexDataSource([]);
  private continuousHorizontalDataSourceKey: string = '';
  private continuousHorizontalWidthCache: Map<string, number> = new Map();
  private continuousHorizontalWidthCacheKey: string = '';
  private lastReadingSettingsSideEffectKey: string = '';
  
  // [新增] 条漫多章节懒加载数据源
  private webtoonDataSource: WebtoonLazyDataSource = new WebtoonLazyDataSource([]);
  
  // [新增] 本地图片缓存管理器引用
  private localImageCache: LocalImageCacheManager = LocalImageCacheManager.getInstance();
  private mangaAssetLoadCoordinator: MangaAssetLoadCoordinator =
    new MangaAssetLoadCoordinator(new MangaAssetLoader(), new MangaAssetMonitor());
  private mangaAssetRequestFactory: MangaAssetRequestFactory = new MangaAssetRequestFactory();
  private mangaReaderSessionGuard: MangaReaderSessionGuard = new MangaReaderSessionGuard();
  
  // [新增] 滚动方向跟踪（用于智能缓存清理）
  private lastScrollDirection: 'up' | 'down' = 'down';
  private lastScrollY: number = 0;
  
  // [性能修复] 本地图片加载完成后 renderEpoch 的防抖定时器
  // 避免每张图加载完成都触发全组件重渲染，改为批量合并刷新
  private localImageRenderDebounceTimer: number = -1;

  // [性能修复] processPreloadQueue 的去重定时器
  // 防止多个 setTimeout 同时调度 processPreloadQueue 导致主线程阻塞（THREAD_BLOCK_6S）
  private processPreloadQueueTimer: number = -1;

  aboutToAppear() {
    // 新增：初始化预加载管理器
    this.initializePreloadManagers();
    
    this.currentScale = this.zoomScale;
    this.animationId = AnimationUtils.generateAnimationId();
    this.uiContext = this.getUIContext();
    
    // [修复] 在初始化期间设置保护标志，防止 onCurrentPageIndexChange 覆盖正确的页面索引
    // 问题：ArkUI 的 @Prop @Watch 机制在组件初始化后会触发 @Watch 回调，
    // 但此时 currentPageIndex 的值可能还没有被父组件正确设置
    this.isInitialized = false;
    
    this.viewCurrentPageIndex = this.currentPageIndex;
    this.updateSinglePageDisplay();

    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
    }

    // 初始化屏幕尺寸
    this.initScreenSize();
    this.lastReadingSettingsSideEffectKey = this.getReadingSettingsSideEffectKey();

    this.initializeImageStates();
    // 初始化双页模式的左右页索引
    this.updateDoublePageIndices();
    if (this.isDoublePageVerticalPortraitMode()) {
      this.syncVerticalDoublePagePositionForCurrentPair(false);
    }

    // 初始化滚动位置键
    this.initScrollPositionKey();

    // 恢复滚动位置
    // 条漫模式首屏定位统一交给父组件 onComponentReady 触发，避免重复跳转导致抖动。
    if (this.isWebtoonMode()) {
      // 清除旧的滚动位置缓存，避免与父组件的页面定位逻辑冲突
      this.savedScrollPosition = 0;
    } else {
      this.restoreScrollPosition();
    }

    // 初始化可见页面
    this.updateVisiblePages();

    // 预加载初始图片 - 使用新的统一预加载方法
    this.triggerUnifiedPreload();

    // 初始化 LazyForEach 数据源
    if (this.chapter && this.chapter.pages) {
      this.pageDataSource.setPages(this.chapter.pages);
      this.updateContinuousHorizontalDataSourceIfNeeded();
    }

    // 初始化条漫多章节数据
    this.initWebtoonMultiChapterData();

    // 通知父组件组件已准备就绪
    if (this.callbacks.onComponentReady) {
      this.callbacks.onComponentReady(this);
    }
    
    // [修复] 立即设置初始化完成标志，允许父组件通过 setPageIndex 方法同步页面索引
    this.isInitialized = true;
    logger.debug(TAG, `✅ MangaViewer初始化完成，当前页面索引: ${this.viewCurrentPageIndex + 1}`);

    // 添加空值检查，防止访问null对象的属性
    const chapterTitle = this.chapter ? this.chapter.title : '未知章节';
    const currentPage = this.chapter && this.chapter.pages ? (this.currentPageIndex + 1) : 0;
    const totalPages = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    const readingModeStr = this.readingSettings && this.readingSettings.readingMode !== undefined 
      ? String(this.readingSettings.readingMode) 
      : '未知';

    logger.info(TAG, '漫画查看器组件初始化' + "当前章节: " + chapterTitle +
      "当前页面: " + '第' + currentPage + '/' + totalPages + '页' +
      "阅读模式: " + readingModeStr);
  }

  /**
   * 监听章节切换
   * 由 chapterTick 变化触发
   */
  private onChapterChange(): void {
    logger.info(TAG, `🔔 [章节切换] 检测到章节切换，chapterTick=${this.chapterTick}，目标页=${this.currentPageIndex + 1}，重新初始化组件`);

    this.suppressExternalIndex = false;

    // 重置页面索引
    this.viewCurrentPageIndex = this.currentPageIndex;
    logger.debug(TAG, `章节切换同步页码: view=${this.viewCurrentPageIndex + 1}, prop=${this.currentPageIndex + 1}`);

    // 重置渲染计数器
    this.renderEpoch = 0;

    // 释放所有PixelMap资源后再清空
    this.releaseAllPagePixelMaps();
    this.imageLoadStates.clear();
    this.preloadManager.clearAll();
    this.imageLoadStateManager.clearAll();
    this.webtoonPageRefById.clear();
    this.webtoonOrderedPageIds = [];
    this.webtoonVisibleItemIndices = [];
    this.invalidateMangaReaderSession('chapterChange');
    this.clearPendingWebtoonSwitchCandidate();
    this.lastCommittedWebtoonChapterSwitchAt = 0;
    this.lastNotifiedWebtoonChapterId = '';
    this.lastNotifiedWebtoonPageIndex = -1;
    this.lastPrevAdjacentRequestAt = 0;
    this.lastNextAdjacentRequestAt = 0;
    this.webtoonBoundaryCacheProtectUntil = 0;
    this.lastBoundaryPrewarmAt.clear();
    this.firstVisibleDisplayCommitted = false;

    // 重置条漫多章节状态
    this.webtoonDataItems = [];
    this.chapterBoundaries = [];
    this.prevChapterRequested = false;
    this.nextChapterRequested = false;
    this.isPrevChapterLoading = false;
    this.isNextChapterLoading = false;
    // [修复②] 重置双重上滑确认状态
    this.prevChapterSwipeConfirmPending = false;
    if (this.prevChapterSwipeConfirmTimer !== -1) {
      clearTimeout(this.prevChapterSwipeConfirmTimer);
      this.prevChapterSwipeConfirmTimer = -1;
    }
    if (this.processPreloadQueueTimer !== -1) {
      clearTimeout(this.processPreloadQueueTimer);
      this.processPreloadQueueTimer = -1;
    }

    // 重新加载当前页和相邻页
    if (this.chapter && this.chapter.pages && this.chapter.pages.length > 0) {
      logger.info(TAG, `🔄 重新加载章节: ${this.chapter.title}，页面数: ${this.chapter.pages.length}`);
      this.preloadManager.setPageInfo(this.currentPageIndex, this.chapter.pages.length);
      this.pageDataSource.setPages(this.chapter.pages);
      this.updateContinuousHorizontalDataSourceIfNeeded();
      this.chapter.pages.forEach((page, index) => {
        this.imageLoadStateManager.initPage(page.id, index);
      });
      this.initializeImageStates();
      if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
        this.updateDoublePageIndices();
        this.updateDoublePagePreview();
        if (this.isDoublePageVerticalPortraitMode()) {
          this.syncVerticalDoublePagePositionForCurrentPair(false);
        }
      }

      // 关键修复：先更新显示变量为实际URL（而不是占位图）
      // 这样Image组件会立即使用新章节的URL
      if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
        this.updateDoublePageDisplay();
      } else {
        this.updateSinglePageDisplay();
      }

      // 然后预加载当前页和相邻页到缓存
      // Image组件会从缓存中快速读取
      this.loadCurrentAndNeighborPages();
    }
  }

  /**
   * 监听相邻章节变化
   * 当prevChapter或nextChapter变化时重新初始化多章节数据
   */
  private onAdjacentChapterChange(): void {
    const input: MangaWebtoonAdjacentChapterInput = this.createWebtoonAdjacentChapterInput();
    const plan: MangaWebtoonAdjacentChapterPlan = this.mangaWebtoonAdjacentChapterPlanner.buildPlan(input);
    if (!plan.shouldRun) {
      return;
    }
    
    logger.info(TAG, `🔔 [相邻章节变化] chapter=${this.chapter?.title || '无'}, prevChapter=${this.prevChapter?.title || '无'}(pages=${this.prevChapter?.pages?.length || 0}), nextChapter=${this.nextChapter?.title || '无'}(pages=${this.nextChapter?.pages?.length || 0})`);

    if (plan.shouldSyncCurrentChapterId) {
      logger.info(TAG, `[相邻章节变化] currentChapterId不在数据中，同步更新: ${this.currentChapterId} -> ${plan.syncedCurrentChapterId}`);
      this.currentChapterId = plan.syncedCurrentChapterId;
    }

    if (plan.shouldSkipDataRebuild) {
      logger.info(TAG, `[相邻章节变化] 相邻章节数据已存在或为空，跳过重建`);
      this.applyWebtoonAdjacentChapterStatePlan(plan);
      return;
    }

    this.applyWebtoonAdjacentChapterStatePlan(plan);
    if (plan.prevIsNew) {
      logger.info(TAG, `[相邻章节变化] 检测到新的上一章数据: ${this.prevChapter?.title}`);
    }
    if (plan.nextIsNew) {
      logger.info(TAG, `[相邻章节变化] 检测到新的下一章数据: ${this.nextChapter?.title}`);
    }

    if (plan.shouldInitWebtoonData) {
      this.initWebtoonMultiChapterData();
    }
    if (plan.shouldCheckBoundaryAfterData) {
      setTimeout(() => {
        this.checkWebtoonChapterBoundary();
      }, 100);
    }
  }

  private createWebtoonAdjacentChapterInput(): MangaWebtoonAdjacentChapterInput {
    const input: MangaWebtoonAdjacentChapterInput = new MangaWebtoonAdjacentChapterInput();
    input.isWebtoonMode = this.isWebtoonMode();
    input.currentChapter = this.chapter;
    input.prevChapter = this.prevChapter;
    input.nextChapter = this.nextChapter;
    input.currentChapterId = this.currentChapterId;
    input.chapterBoundaries = this.chapterBoundaries;
    return input;
  }

  private applyWebtoonAdjacentChapterStatePlan(plan: MangaWebtoonAdjacentChapterPlan): void {
    if (plan.shouldResetPrevLoading) {
      this.isPrevChapterLoading = false;
    }
    if (plan.shouldResetNextLoading) {
      this.isNextChapterLoading = false;
    }
    if (plan.shouldResetPrevRequest) {
      this.prevChapterRequested = false;
    }
    if (plan.shouldResetNextRequest) {
      this.nextChapterRequested = false;
    }
  }

  /**
   * 监听网络请求头变化
   * 由 networkHeadersTick 变化触发
   */
  private onNetworkHeadersChange(): void {
    // 这里的逻辑和之前一样，使用 this.networkHeaders 进行判断
    const referer = this.networkHeaders?.referer;
    logger.info(TAG, `🔔 [Tick触发] 检测到Headers更新，新Referer: ${referer || '空'}`);

    if (referer && referer.length > 0) {
      let retryCount = 0;

      // 1. 重置所有加载失败的页面状态
      this.imageLoadStates.forEach((state, pageId) => {
        if (state.error || (state.isLoading && !state.isLoaded)) {
          this.imageLoadStates.set(pageId, {
            isLoading: false,
            isLoaded: false,
            error: undefined
          });
          retryCount++;
        }
      });

      // 强制触发UI更新
      this.imageLoadStates = new Map(this.imageLoadStates);

      if (retryCount > 0) {
        logger.info(TAG, `🔄 触发 ${retryCount} 张图片的重试加载`);

        // 2. 重新触发预加载逻辑
        // 使用新的统一预加载方法
        this.triggerUnifiedPreload();

        // 3. 确保当前页立即加载
        const currentPageData = this.getCurrentPageData();
        if (currentPageData.page) {
          this.loadImage(currentPageData.page);
        }
      }
    }
  }

  /**
   * [修复] 公开方法：强制设置页面索引
   * 用于父组件在 onComponentReady 中同步正确的页面索引
   * 这个方法绕过 @Prop @Watch 的时序问题，直接设置内部状态
   */
  public setPageIndex(pageIndex: number): void {
    if (pageIndex >= 0 && this.chapter && this.chapter.pages && pageIndex < this.chapter.pages.length) {
      logger.info(TAG, `[修复] 强制设置页面索引: ${this.viewCurrentPageIndex + 1} -> ${pageIndex + 1}`);
      this.viewCurrentPageIndex = pageIndex;
      this.currentWebtoonPage = pageIndex;
      this.visiblePageIndices = [pageIndex];
      if (this.isContinuousScrollMode()) {
        this.suppressContinuousHorizontalBoundary();
        this.jumpToPageImmediate(pageIndex);
        this.triggerUnifiedPreload();
        return;
      }
      if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
        if (this.isDoublePageVerticalPortraitMode()) {
          this.forceRefreshVerticalDoublePageCurrentPair('set_page_index');
        } else {
          this.updateDoublePageIndices();
          this.updateDoublePagePreview();
        }
      } else {
        this.updateSinglePageDisplay();
        this.updateSinglePagePreview();
      }
      this.loadCurrentAndNeighborPages();
    }
  }

  /**
   * 暴露给父组件：当前可视页是否已经具备可展示内容
   * 用于过渡动画场景，避免在首屏内容未就绪时提前隐藏遮罩。
   */
  public isCurrentVisualReady(): boolean {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return false;
    }

    const pageCount: number = this.chapter.pages.length;
    const safeIndex: number = Math.max(0, Math.min(this.viewCurrentPageIndex, pageCount - 1));

    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      const leftIndex: number = (this.leftPageIndex >= 0 && this.leftPageIndex < pageCount)
        ? this.leftPageIndex
        : safeIndex;
      const rightIndex: number = (this.rightPageIndex >= 0 && this.rightPageIndex < pageCount)
        ? this.rightPageIndex
        : -1;

      const leftReady = this.isPageVisualReadyByIndex(leftIndex);
      const rightReady = rightIndex >= 0 ? this.isPageVisualReadyByIndex(rightIndex) : false;
      // 双页场景下任一可视页就绪即可视为可展示，避免遮罩卡死
      return leftReady || rightReady;
    }

    return this.isPageVisualReadyByIndex(safeIndex);
  }

  private isPageVisualReadyByIndex(pageIndex: number): boolean {
    if (!this.chapter || !this.chapter.pages || pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return false;
    }

    const page = this.chapter.pages[pageIndex];
    if (!page) {
      return false;
    }

    if (this.pagePixelMaps.has(page.id) || this.localImageCache.has(page.id)) {
      return true;
    }

    const state: ImageLoadState | undefined = this.getPageLoadState(page);
    if (!state) {
      return false;
    }

    // 加载成功或已进入错误态都可认为“首屏已可见”
    return state.isLoaded || !!state.error;
  }

  /**
   * 当前页面索引变化时的回调（@Watch监听）
   */
  onCurrentPageIndexChange(): void {
    if (this.suppressExternalIndex) {
      logger.debug(TAG, `忽略外部索引更新: 外部=${this.currentPageIndex + 1}, 本地=${this.viewCurrentPageIndex + 1}`);
      return;
    }
    
    // [修复] 在初始化期间忽略 @Watch 回调，防止错误的页面索引覆盖正确的初始值
    // 问题：ArkUI 的 @Prop @Watch 机制在组件初始化后会触发 @Watch 回调，
    // 但此时传入的 currentPageIndex 可能是默认值（0或1），而不是父组件期望的值
    if (!this.isInitialized) {
      logger.debug(TAG, `[修复] 忽略初始化期间的页面索引变化: 外部=${this.currentPageIndex + 1}, 本地=${this.viewCurrentPageIndex + 1}`);
      return;
    }

    const previousViewPageIndex: number = this.viewCurrentPageIndex;
    if (this.currentPageIndex === previousViewPageIndex) {
      logger.debug(TAG, `忽略同页索引回写: page=${this.currentPageIndex + 1}`);
      return;
    }
    
    logger.debug(TAG, `页面索引变化: ${previousViewPageIndex + 1} -> ${this.currentPageIndex + 1}`);
    this.viewCurrentPageIndex = this.currentPageIndex;
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageIndices();
      this.updateDoublePagePreview();
      if (this.isDoublePageVerticalPortraitMode()) {
        this.verticalDoublePageTurnAction = this.currentPageIndex > previousViewPageIndex ? 'next' : 'prev';
        this.syncVerticalDoublePagePositionForCurrentPair(false);
      }
    } else {
      this.updateSinglePageDisplay();
      this.updateSinglePagePreview();
    }

    // 触发翻页动画（双页卷曲动画期间不触发，避免重复动画）
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE && !this.showDualCurlEffect) {
      const isForwardExternalJump: boolean = this.currentPageIndex > previousViewPageIndex;
      if (this.isDoublePageVerticalPortraitMode()) {
        this.isCommittingPageTurn = true;
        const action: 'next' | 'prev' = isForwardExternalJump ? 'next' : 'prev';
        this.pageTurnDirection = this.getVerticalDoublePageTurnDirection(action);
      } else {
        const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
        this.pageTurnDirection = isForwardExternalJump
          ? (isRTL ? 'right' : 'left')
          : (isRTL ? 'left' : 'right');
      }
      this.animatePageTurn();
      this.translateX = 0;
      this.translateY = 0;
    }

    // 单页/双页模式：强制刷新锚点以确保UI重建
    // [性能修复] 条漫模式通过 LazyForEach item key 管理刷新，不需要 renderEpoch 全树重建
    if (!this.isWebtoonMode()) {
      this.renderEpoch = this.renderEpoch + 1;
    }

    // 优先加载当前页和相邻页
    this.loadCurrentAndNeighborPages();

    // 触发统一预加载
    if (this.isWebtoonMode()) {
      this.updateVisiblePages();
    }
    this.triggerUnifiedPreload();
    // 双页模式：更新左右页索引
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.preloadDoublePageNeighbors();
    }
    this.cleanupInvisiblePixelMaps();
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'MangaViewer组件即将销毁');

    // 保存当前滚动位置
    this.saveScrollPosition();

    // 清理定时器
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }

    // 清理图片加载超时定时器
    const keys = Array.from(this.pendingLoadTimers.keys());
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      const tid = this.pendingLoadTimers.get(k);
      if (typeof tid === 'number') { clearTimeout(tid); }
      this.pendingLoadTimers.delete(k);
    }
    if (this.softTransitionStartTimer !== -1) {
      clearTimeout(this.softTransitionStartTimer);
      this.softTransitionStartTimer = -1;
    }
    if (this.softTransitionFallbackTimer !== -1) {
      clearTimeout(this.softTransitionFallbackTimer);
      this.softTransitionFallbackTimer = -1;
    }

    // 清理预加载队列定时器
    if (this.processPreloadQueueTimer !== -1) {
      clearTimeout(this.processPreloadQueueTimer);
      this.processPreloadQueueTimer = -1;
    }
    if (this.pendingWebtoonSwitchNotifyTimer !== -1) {
      clearTimeout(this.pendingWebtoonSwitchNotifyTimer);
      this.pendingWebtoonSwitchNotifyTimer = -1;
    }
    if (this.webtoonStopCleanupTimer !== -1) {
      clearTimeout(this.webtoonStopCleanupTimer);
      this.webtoonStopCleanupTimer = -1;
    }
    this.clearPendingWebtoonSwitchCandidate();
    this.lastBoundaryPrewarmAt.clear();
    this.webtoonBoundaryCacheProtectUntil = 0;
    this.lastPrevAdjacentRequestAt = 0;
    this.lastNextAdjacentRequestAt = 0;
    this.lastNotifiedWebtoonChapterId = '';
    this.lastNotifiedWebtoonPageIndex = -1;

    // 清理双页卷页动画定时器
    this.stopDualCurlAnimation();
    // 清空双页卷页 PixelMap 引用（不释放，缓存由 pagePixelMaps 管理）
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;

    this.logMangaReaderCacheSnapshot('before_disappear_cleanup');

    // 释放所有页面PixelMap资源
    this.releaseAllPagePixelMaps();

    // 清理图片缓存
    this.clearImageCache();
    this.invalidateMangaReaderSession('disappear');
  }

  /**
   * 清理所有图片缓存
   */
  private clearImageCache(): void {
    const hadCache: boolean = this.imageCache.size > 0 || this.preloadedImages.size > 0;
    this.imageCache.clear();
    this.imageCacheSize = 0;
    this.preloadedImages.clear();
    if (hadCache) {
      logger.debug(TAG, '旧图片元信息缓存已清理');
      this.logMangaReaderCacheSnapshot('legacy_image_meta_cleared');
    }
  }

  /**
   * 释放所有页面PixelMap资源
   */
  private releaseAllPagePixelMaps(): void {
    const hadPixelMaps: boolean = this.pagePixelMaps.size > 0;
    this.mangaPixelMapLifecycleManager.releaseAll(this.pagePixelMaps);
    this.pagePixelMaps.clear();
    this.pagePixelMapMeta.clear();
    this.pixelMapEpochByPage.clear();
    this.pagePixelMaps = new Map(this.pagePixelMaps);
    this.pixelMapEpochByPage = new Map(this.pixelMapEpochByPage);
    if (hadPixelMaps) {
      this.logMangaReaderCacheSnapshot('active_pixel_maps_released');
    }
  }

  onPageShow() {
    // 重置状态
    this.resetViewerState();
  }

  /**
   * 初始化屏幕尺寸
   */
  private initScreenSize(): void {
    try {
      this.screenWidth = 0;
      this.screenHeight = 0;
      logger.debug(TAG, `屏幕尺寸初始化完成`);
    } catch (error) {
      logger.error(TAG, '初始化屏幕尺寸失败', String(error));
      this.screenWidth = 0;
      this.screenHeight = 0;
    }
  }

  /**
   * 新增：初始化预加载管理器
   */
  private initializePreloadManagers(): void {
    // 配置预加载参数（可根据需要调整）
    this.preloadManager.updateConfig({
      maxConcurrentOnline: 3,      // 在线漫画最大并发加载数
      maxConcurrentLocal: 5,       // 本地漫画最大并发加载数
      webtoonVisibleBuffer: 1.5,   // 条漫模式可见区域缓冲（屏幕高度倍数）
      webtoonPreloadRange: 8,      // 条漫模式预加载范围（页数）
      normalPreloadRange: 3        // 普通模式预加载范围（页数）
    });
    
    // 设置预加载管理器的调试信息回调
    this.preloadManager.setDebugInfoUpdateCallback((info: PreloadDebugInfo) => {
      this.preloadDebugInfo = info;
    });
    
    // 设置图片加载状态管理器的状态变化回调
    this.imageLoadStateManager.setStateChangeCallback((pageId: string, state: PageState) => {
      this.onPageStateChanged(pageId, state);
    });
    
    // 初始化页面信息
    if (this.chapter && this.chapter.pages) {
      this.preloadManager.setPageInfo(this.currentPageIndex, this.chapter.pages.length);
      
      // 初始化所有页面状态
      this.chapter.pages.forEach((page, index) => {
        this.imageLoadStateManager.initPage(page.id, index);
      });
      
      logger.info(TAG, `预加载管理器初始化完成: 总页数=${this.chapter.pages.length}, 当前页=${this.currentPageIndex}`);
    }
  }

  /**
   * 新增：页面状态变化回调
   */
  private onPageStateChanged(pageId: string, state: PageState): void {
    // 当页面状态变化时，更新UI相关的状态
    // 这里可以根据需要触发UI刷新
    logger.debug(TAG, `页面状态变化: ${pageId}, state=${state.loadState}`);
    
    // 如果是当前页，更新显示
    const currentPage = this.chapter?.pages[this.viewCurrentPageIndex];
    if (currentPage && currentPage.id === pageId) {
      this.updateSinglePageDisplay();
    }
  }

  /**
   * 初始化图片加载状态
   */
  private initializeImageStates(): void {
    // 添加空值检查，防止闪退
    if (!this.chapter || !this.chapter.pages) {
      logger.error(TAG, '章节数据为空，无法初始化图片状态');
      return;
    }

    this.chapter.pages.forEach(page => {
      this.imageLoadStates.set(page.id, {
        isLoading: false,
        isLoaded: false
      });
    });
    // 触发响应式更新：重新赋值Map以通知ArkUI状态变化
    this.imageLoadStates = new Map(this.imageLoadStates);
  }

  /**
   * 预加载图片
   */
  private preloadImages(): void {
    // 添加空值检查，防止chapter为null时闪退
    if (!this.chapter || !this.chapter.pages) {
      logger.error(TAG, '章节数据为空，无法预加载图片');
      return;
    }

    // 双页模式下不执行通用范围预加载，改为仅在ensureDoublePageImagesPreloaded中加载左右页
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      return;
    }

    // 条漫模式使用统一的预加载方法
    if (this.isWebtoonMode()) {
      this.triggerWebtoonPreload();
    }
  }

  /**
   * 优先加载当前页和相邻页（高优先级）
   * 支持异步等待加载完成
   */
  private loadCurrentAndNeighborPages(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    const currentIndex = this.viewCurrentPageIndex;
    const totalPages = this.chapter.pages.length;

    // 创建高优先级页面列表
    const priorityPages: MangaPage[] = [];

    // 优先加载当前页
    if (currentIndex >= 0 && currentIndex < totalPages) {
      const currentPage = this.chapter.pages[currentIndex];
      priorityPages.push(currentPage);
    }

    // 然后加载前后各1页
    for (let offset of [-1, 1]) {
      const targetIndex = currentIndex + offset;
      if (targetIndex >= 0 && targetIndex < totalPages) {
        const page = this.chapter.pages[targetIndex];
        priorityPages.push(page);
      }
    }

    // 本地+条漫专用：优先页仅做本地缓存预热，避免走通用 PixelMap 链路引发切源闪烁
    if (this.isWebtoonMode()) {
      const chapterId = this.chapter.id;
      for (let i = 0; i < priorityPages.length; i++) {
        const page = priorityPages[i];
        if (page.sourceType === ImageSourceType.LOCAL) {
          const pageIndex = page.index !== undefined ? page.index : this.getPageIndexById(page.id);
          this.triggerLocalImageLoad(page, chapterId, pageIndex);
          continue;
        }
        if (page.sourceType === ImageSourceType.NETWORK) {
          this.queueWebtoonNetworkPageLoad(page);
          continue;
        }
        if (!this.pagePixelMaps.has(page.id)) {
          this.ensurePixelMapLoaded(page).catch((_e: Error) => {});
        }
      }
      return;
    }

    // 异步加载所有高优先级页面
    Promise.all(priorityPages.map(page => {
      if (!this.pagePixelMaps.has(page.id)) {
        return this.ensurePixelMapLoaded(page);
      }
      return Promise.resolve();
    }))
      .then(() => {
        logger.info(TAG, `高优先级页面加载完成，刷新UI: currentIdx=${currentIndex}`);

        // 【修复】如果正在执行翻页动画，不要立即刷新UI，避免闪回
        if (this.isPageTurning) {
          logger.debug(TAG, `翻页动画执行中，延迟UI刷新`);
          return;
        }

        // 所有高优先级页面加载完成后，刷新UI
        if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
          this.updateDoublePageDisplay();
        } else {
          this.updateSinglePageDisplay();
        }
      })
      .catch((error: Error) => {
        logger.error(TAG, `高优先级页面加载失败: ${String(error)}`);
      });
  }

  /**
   * 加载单个图片（带优先级）
   */
  private loadImageWithPriority(page: MangaPage, priority: number): void {
    // 设置优先级到page对象（用于ImageCacheManager）
    if (!page.priority) {
      page.priority = priority;
    }
    // 调用原有的loadImage方法
    this.loadImage(page);
  }

  /**
   * 新增：重试加载页面
   */
  private retryLoadPage(page: MangaPage): void {
    logger.info(TAG, `重试加载页面: pageId=${page.id}, url=${page.imageUrl}`);
    
    // 清除旧的错误状态
    const oldState = this.imageLoadStates.get(page.id);
    if (oldState) {
      oldState.error = undefined;
      oldState.isLoading = false;
      oldState.isLoaded = false;
      this.imageLoadStates.set(page.id, oldState);
      this.imageLoadStates = new Map(this.imageLoadStates);
    }
    
    // 清除新状态管理器中的状态
    this.imageLoadStateManager.clearPage(page.id);
    this.preloadManager.clearPage(this.getPageIndexById(page.id));
    
    // 清除 PixelMap
    this.dropPagePixelMapReference(page.id, true);
    
    // 重新初始化页面状态
    this.imageLoadStateManager.initPage(page.id, this.getPageIndexById(page.id));
    
    // 重新加载图片
    this.loadImage(page);
    
    // 更新显示
    this.updateSinglePageDisplay();
  }

  /**
   * 加载单个图片
   */
  private loadImage(page: MangaPage): void {
    // [新增] 强校验：如果是 Komiic 源且 Referer 为空，挂起请求
    const isKomiic = (this.networkHeaders?.referer?.includes('komiic')) ||
      (page.imageUrl.includes('komiic.com'));

    const currentReferer = this.networkHeaders?.referer;

    if (isKomiic && (!currentReferer || currentReferer.length === 0)) {
      logger.warn(TAG, `🛑 拦截 Komiic 图片加载: Referer 为空，等待 Headers 更新。Page ID: ${page.id}`);
      // 设置为 loading 状态，但**不**调用 cacheManager
      this.imageLoadStates.set(page.id, { isLoading: true, isLoaded: false });
      return; // 直接返回，等待 onNetworkHeadersChange 触发
    }

    // 本地+条漫专用：不走通用 PixelMap 加载链路，避免 file/PixelMap 切换闪烁
    if (this.isWebtoonMode() && page.sourceType === ImageSourceType.LOCAL) {
      const chapterId = this.chapter ? this.chapter.id : '';
      const pageIndex = page.index !== undefined ? page.index : this.getPageIndexById(page.id);
      this.triggerLocalImageLoad(page, chapterId, pageIndex);
      return;
    }

    // 在线条漫专用：网络图仅通过预加载队列加载，避免双通路并发
    if (this.isWebtoonMode() && page.sourceType === ImageSourceType.NETWORK) {
      this.queueWebtoonNetworkPageLoad(page);
      return;
    }

    this.invalidatePixelMapIfSourceChanged(page);
    const currentState: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
    const hasPm: boolean = this.pagePixelMaps.has(page.id);
    if ((currentState && currentState.isLoading) || hasPm) {
      return;
    }

    this.imageLoadStates.set(page.id, {
      isLoading: true,
      isLoaded: false
    } as ImageLoadState);
    this.imageLoadStates = new Map(this.imageLoadStates);

    // 触发实际 Image 组件加载流程由 UI 构建时完成。
    // 这里仅记录诊断日志，避免与真实生命周期脱节。
    logger.debug(TAG, `开始加载图片: id=${page.id}, src=${String(this.getImageResource(page))}, priority=${page.priority || 1}`);
    this.verifyLocalFileAndLog(page, 'start');
    this.ensurePixelMapLoaded(page);

    // 仅在页面可视时启动超时定时器，避免不可视页面被误判为超时
    if (this.isPageCurrentlyVisible(page)) {
      const timeoutMs: number = 15000;
      const timerId: number = setTimeout(() => {
        const st = this.imageLoadStates.get(page.id);
        if (st && st.isLoading && !st.isLoaded) {
          this.imageLoadStates.set(page.id, {
            isLoading: false,
            isLoaded: false,
            error: '加载超时'
          } as ImageLoadState);
          this.imageLoadStates = new Map(this.imageLoadStates);
          logger.warn(TAG, `图片加载超时: id=${page.id}, src=${String(this.getImageResource(page))}`);
          this.logTimeoutDiagnosis(page);
        }
        this.pendingLoadTimers.delete(page.id);
      }, timeoutMs);
      this.pendingLoadTimers.set(page.id, timerId);
    } else {
      logger.debug(TAG, `跳过超时定时器（页面不可视）: id=${page.id}`);
    }
  }

  /**
   * 重置查看器状态
   */
  private resetViewerState(): void {
    this.currentScale = this.zoomScale;
    this.translateX = 0;
    this.translateY = 0;
    this.isDragging = false;
  }

  /**
   * 注意：点击事件已移至Page层统一处理
   * MangaViewer不再处理点击事件，避免重复触发
   */

  /**
   * 动画缩放
   */
  private animateZoom(targetScale: number): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行缩放动画');
      this.currentScale = targetScale;
      if (this.callbacks.onZoomChange) {
        this.callbacks.onZoomChange(targetScale);
      }
      return;
    }

    // 防止重复动画
    if (Math.abs(this.currentScale - targetScale) < 0.01) {
      return;
    }

    const animateOptions: AnimateParam = {
      duration: 300,
      curve: curves.initCurve(Curve.EaseOut)
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.currentScale = targetScale;
      if (this.callbacks.onZoomChange) {
        this.callbacks.onZoomChange(targetScale);
      }

      // 缩放时重置位移
      if (targetScale === 1.0) {
        this.translateX = 0;
        this.translateY = 0;
      }
    });
  }

  /**
   * 处理拖拽开始
   */
  private handlePanStart(event: GestureEvent): void {
    // 安全检查：确保fingerList存在且有元素
    if (!event.fingerList || event.fingerList.length === 0 || !event.fingerList[0]) {
      logger.warn(TAG, '拖拽开始时fingerList无效，忽略此事件');
      return;
    }

    // 如果正在缩放，不处理拖拽
    if (this.isZooming) {
      return;
    }

    this.isDragging = true;
    this.pageChangeCommitted = false;
    this.swipeTriggered = false;
    this.panStartX = event.fingerList[0].globalX;
    this.panStartY = event.fingerList[0].globalY;
    this.panStartTime = Date.now();
    this.initialTranslateX = this.translateX;
    this.initialTranslateY = this.translateY;

    if (this.isDoublePageVerticalPortraitMode() && this.currentScale <= 1.0) {
      this.verticalDoublePageLastPanOffsetY = 0;
      this.resetVerticalDoublePageBoundaryState();
    }

    // ========== 卷页动画：拖拽开始时立即进入交互模式 ==========
    const animationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
    const isVerticalPagingMode: boolean = this.isSinglePageVerticalPagingMode() || this.isDoublePageVerticalPortraitMode();

    if (animationType === PageTurnAnimationType.CURL && !isVerticalPagingMode && !this.shouldUseSmartDoublePageLayout()) {
      // 准备卷页模式（但不立即显示，等待有明显拖拽时再显示）
      // 支持单页和双页模式
      this.prepareCurlMode();
    }
    // ========== 卷页动画处理结束 ==========

    if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      // 使用新的统一预加载方法
      this.triggerUnifiedPreload();
      // 卷页模式下不更新预览（由Canvas层处理）
      if (animationType !== PageTurnAnimationType.CURL) {
        this.updateSinglePagePreview();
      }
    } else if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.preloadDoublePageNeighbors();
    }
  }

  /**
   * 准备卷页模式（预加载PixelMap）
   * 支持单页模式和双页模式
   */
  private prepareCurlMode(): void {
    const currentIndex: number = this.viewCurrentPageIndex;
    const isDoublePage: boolean = this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;

    // 根据触摸位置确定翻页起始位置
    this.determineCurlStartPosition();

    // 根据翻页方向决定加载哪一页
    const isLeftSide: boolean = this.curlStartPosition === CurlStartPosition.LEFT_EDGE ||
      this.curlStartPosition === CurlStartPosition.TOP_LEFT ||
      this.curlStartPosition === CurlStartPosition.BOTTOM_LEFT;

    if (isDoublePage) {
      // 双页模式：使用左页或右页的图片（根据翻页方向）
      const leftIdx: number = this.leftPageIndex;
      const rightIdx: number = this.rightPageIndex;

      // 当前页使用翻页方向对应的那一页
      const currentPageIdx: number = isLeftSide ?
        (leftIdx >= 0 ? leftIdx : rightIdx) :
        (rightIdx >= 0 ? rightIdx : leftIdx);

      if (currentPageIdx >= 0 && currentPageIdx < this.chapter.pages.length) {
        const currentPage: MangaPage = this.chapter.pages[currentPageIdx];
        this.curlCurrentPixelMap = this.pagePixelMaps.get(currentPage.id) || null;
      } else {
        this.curlCurrentPixelMap = null;
      }

      // 双页模式下，翻页是翻两页
      const pairStart: number = currentIndex - (currentIndex % 2);
      if (isLeftSide) {
        // 左侧翻页 = 向后翻（上一对页）
        const prevPairStart: number = Math.max(pairStart - 2, 0);
        if (prevPairStart < pairStart) {
          const nextPageIdx: number = prevPairStart + (isLeftSide ? 1 : 0);
          if (nextPageIdx >= 0 && nextPageIdx < this.chapter.pages.length) {
            const nextPage: MangaPage = this.chapter.pages[nextPageIdx];
            this.curlNextPixelMap = this.pagePixelMaps.get(nextPage.id) || null;
            if (!this.curlNextPixelMap) {
              this.ensurePixelMapLoaded(nextPage);
            }
          }
        } else {
          this.curlNextPixelMap = null;
        }
      } else {
        // 右侧翻页 = 向前翻（下一对页）
        const maxIndex: number = this.chapter.pages.length - 1;
        const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
        if (nextPairStart > pairStart) {
          const nextPageIdx: number = nextPairStart;
          if (nextPageIdx >= 0 && nextPageIdx < this.chapter.pages.length) {
            const nextPage: MangaPage = this.chapter.pages[nextPageIdx];
            this.curlNextPixelMap = this.pagePixelMaps.get(nextPage.id) || null;
            if (!this.curlNextPixelMap) {
              this.ensurePixelMapLoaded(nextPage);
            }
          }
        } else {
          this.curlNextPixelMap = null;
        }
      }
    } else {
      // 单页模式：原有逻辑
      const currentPage: MangaPage = this.chapter.pages[currentIndex];
      this.curlCurrentPixelMap = this.pagePixelMaps.get(currentPage.id) || null;

      if (isLeftSide) {
        // 左侧翻页 = 向后翻（上一页）
        if (currentIndex > 0) {
          const prevPage: MangaPage = this.chapter.pages[currentIndex - 1];
          this.curlNextPixelMap = this.pagePixelMaps.get(prevPage.id) || null;

          if (!this.curlNextPixelMap) {
            logger.info(TAG, `上一页PixelMap未加载，开始加载: ${prevPage.id}`);
            this.ensurePixelMapLoaded(prevPage).then(() => {
              const loadedPixelMap = this.pagePixelMaps.get(prevPage.id);
              if (loadedPixelMap) {
                this.curlNextPixelMap = loadedPixelMap;
                logger.info(TAG, `上一页PixelMap加载完成: ${prevPage.id}`);
              }
            }).catch((e: Error) => {
              logger.error(TAG, `上一页PixelMap加载失败: ${e.message}`);
            });
          }
        } else {
          this.curlNextPixelMap = null;
        }
      } else {
        // 右侧翻页 = 向前翻（下一页）
        if (currentIndex < this.chapter.pages.length - 1) {
          const nextPage: MangaPage = this.chapter.pages[currentIndex + 1];
          this.curlNextPixelMap = this.pagePixelMaps.get(nextPage.id) || null;

          if (!this.curlNextPixelMap) {
            logger.info(TAG, `下一页PixelMap未加载，开始加载: ${nextPage.id}`);
            this.ensurePixelMapLoaded(nextPage).then(() => {
              const loadedPixelMap = this.pagePixelMaps.get(nextPage.id);
              if (loadedPixelMap) {
                this.curlNextPixelMap = loadedPixelMap;
                logger.info(TAG, `下一页PixelMap加载完成: ${nextPage.id}`);
              }
            }).catch((e: Error) => {
              logger.error(TAG, `下一页PixelMap加载失败: ${e.message}`);
            });
          }
        } else {
          this.curlNextPixelMap = null;
        }
      }
    }

    // 计算图片显示区域
    this.calculateImageDisplayRect();

    logger.info(TAG, `准备卷页模式: currentIndex=${currentIndex}, isDouble=${isDoublePage}, pos=${this.curlStartPosition}, current=${this.curlCurrentPixelMap ? 'loaded' : 'null'}, next=${this.curlNextPixelMap ? 'loaded' : 'null'}`);
  }

  /**
   * 根据触摸位置确定翻页起始位置
   * 自由点翻页模式下，只需要区分左侧还是右侧
   */
  private determineCurlStartPosition(): void {
    const touchX: number = this.panStartX;
    const touchY: number = this.panStartY;
    const screenW: number = this.screenWidth;

    // 记录触摸坐标（用于自由点翻页）
    this.curlTouchY = touchY;
    const input: MangaCurlStartInput = new MangaCurlStartInput();
    input.touchX = touchX;
    input.screenWidth = screenW > 0 ? screenW : 360;
    const plan: MangaCurlStartPlan = this.mangaCurlTurnPlanner.buildStartPlan(input);
    this.curlStartPosition = plan.startPosition;

    logger.debug(TAG, `确定翻页起始位置(自由点): touchX=${touchX.toFixed(0)}, touchY=${touchY.toFixed(0)}, pos=${this.curlStartPosition}`);
  }

  /**
   * 判断当前阅读模式是否支持卷页动画
   * 卷页动画支持：
   * - 单页模式 + 从左到右/从右到左阅读方向
   * - 双页模式 + 横屏
   * 不支持：连续滚动、上下翻页
   */
  private isCurlAnimationSupported(): boolean {
    const input: MangaCurlSupportInput = new MangaCurlSupportInput();
    input.readingMode = this.readingSettings.readingMode;
    input.readingDirection = this.readingSettings.readingDirection;
    input.isLandscapeScreen = this.isLandscapeScreen();
    input.useSmartDoublePageLayout = this.shouldUseSmartDoublePageLayout();
    return this.mangaCurlTurnPlanner.isSupported(input);
  }

  /**
   * 根据翻页方向更新起始位置
   * 自由点翻页模式下，只需要区分左/右侧，实际折叠效果由触摸点位置动态计算
   * @param isRightSide true=右侧翻页，false=左侧翻页
   */
  private updateCurlStartPositionForDirection(isRightSide: boolean): void {
    // 自由点翻页：简化为只区分左/右
    this.curlStartPosition = this.mangaCurlTurnPlanner.resolveStartPositionForDirection(isRightSide);

    logger.debug(TAG, `更新翻页起始位置(自由点): isRightSide=${isRightSide}, touchX=${this.panStartX.toFixed(0)}, touchY=${this.panStartY.toFixed(0)}, pos=${this.curlStartPosition}`);
  }

  /**
   * 处理拖拽更新
   */
  private handlePanUpdate(event: GestureEvent): void {
    if (!this.isDragging) return;

    // 安全检查：确保fingerList存在且有元素
    if (!event.fingerList || event.fingerList.length === 0 || !event.fingerList[0]) {
      logger.warn(TAG, '拖拽更新时fingerList无效，忽略此事件');
      return;
    }

    // 如果正在缩放，不处理拖拽
    if (this.isZooming) {
      return;
    }

    const deltaX = event.fingerList[0].globalX - this.panStartX;
    const deltaY = event.fingerList[0].globalY - this.panStartY;

    if (this.isDoublePageVerticalPortraitMode() && this.currentScale <= 1.0) {
      return;
    }

    // ========== 卷页动画：实时更新卷曲进度 ==========
    const animationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
    const isDoublePage: boolean = this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;

    if (animationType === PageTurnAnimationType.CURL && this.currentScale <= 1.0) {
      // 双页檌屏卷页模式
      if (isDoublePage && this.isLandscapeScreen() && !this.shouldUseSmartDoublePageLayout()) {
        this.curlTouchY = event.fingerList[0].globalY;
        this.updateDualCurlProgress(deltaX);
        return;
      }
      // 单页卷页模式
      if (this.isCurlAnimationSupported()) {
        this.curlTouchY = event.fingerList[0].globalY;
        this.updateCurlProgress(deltaX);
        return;
      }
    }
    // ========== 卷页动画处理结束 ==========

    if (this.currentScale > 1.0) {
      // 缩放状态下允许拖拽
      this.translateX = this.initialTranslateX + deltaX;
      this.translateY = this.initialTranslateY + deltaY;
    } else if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      // 连续滚动模式下的垂直拖拽
      this.translateY = this.initialTranslateY + deltaY;
    } else if (this.isSinglePageVerticalPagingMode() || this.isDoublePageVerticalPortraitMode()) {
      // 上下翻页模式下使用垂直拖拽用于翻页预览
      this.translateY = this.initialTranslateY + deltaY;
    } else {
      // 单页模式下的水平拖拽（用于翻页）
      this.translateX = this.initialTranslateX + deltaX;
    }
  }

  /**
   * 更新卷页进度（实时交互）
   * 支持双向翻页：从右向左翻到下一页，从左向右翻到上一页
   * 支持单页模式和双页模式
   */
  private updateCurlProgress(deltaX: number): void {
    const currentIndex: number = this.viewCurrentPageIndex;
    const input: MangaCurlProgressInput = new MangaCurlProgressInput();
    input.readingMode = this.readingSettings.readingMode;
    input.readingDirection = this.readingSettings.readingDirection;
    input.currentPageIndex = currentIndex;
    input.pageCount = this.chapter.pages.length;
    input.deltaX = deltaX;
    input.imageWidth = this.imageDisplayRect.w > 0 ? this.imageDisplayRect.w : this.screenWidth;
    input.screenWidth = this.screenWidth > 0 ? this.screenWidth : 360;
    input.showThreshold = 10;
    const plan: MangaCurlProgressPlan = this.mangaCurlTurnPlanner.buildProgressPlan(input);
    this.curlIsForward = plan.isForward;
    this.curlStartPosition = plan.startPosition;

    // 检查是否可以翻页
    if (!plan.canFlip) {
      this.showCanvasCurl = false;
      this.translateX = this.initialTranslateX + deltaX;
      return;
    }

    // 检查当前页PixelMap是否已加载
    if (!this.curlCurrentPixelMap) {
      this.translateX = this.initialTranslateX + deltaX;
      return;
    }

    // 当拖拽超过一定距离时，显示卷页效果
    if (plan.shouldShowCurl) {
      if (!this.showCanvasCurl) {
        // 首次进入卷页模式
        const pixelMapPlan: MangaCurlSinglePixelMapPlan = this.resolveSingleCurlPixelMapPlan(
          currentIndex,
          plan.targetPageIndex
        );

        // 检查当前页PixelMap是否可用
        if (!pixelMapPlan.canStartCurl) {
          logger.warn(TAG, `当前页PixelMap为空，降级为普通翻页模式`);
          // 降级：不使用卷页动画，但允许翻页
          this.translateX = this.initialTranslateX + deltaX;
          return;
        }

        // 如果下一页PixelMap也未加载，尝试触发加载但不阻止卷页
        if (pixelMapPlan.shouldLoadTarget && pixelMapPlan.targetRequest.pageIndex >= 0 &&
          pixelMapPlan.targetRequest.pageIndex < this.chapter.pages.length) {
          const targetPage: MangaPage = this.chapter.pages[pixelMapPlan.targetRequest.pageIndex];
          logger.info(TAG, `下一页PixelMap未加载，触发异步加载: ${targetPage.id}`);
          this.ensurePixelMapLoaded(targetPage).catch((e: Error) => {
            logger.error(TAG, `下一页PixelMap加载失败: ${e.message}`);
          });
        }

        this.showCanvasCurl = true;
        this.curlPendingPageIndex = plan.targetPageIndex;
        this.isPageTurning = true;
        this.pageTurnDirection = plan.pageTurnDirection;
        this.currentAnimationType = PageTurnAnimationType.CURL;
        this.pageTurnOpacity = 0;
        logger.info(TAG, `进入卷页模式: currentIndex=${currentIndex}, targetIndex=${plan.targetPageIndex}, forward=${plan.dragForward}, pos=${this.curlStartPosition}`);
      }

      // 更新卷曲进度
      this.curlProgress = plan.progress;
    } else {
      // 拖拽距离不够，保持普通状态
      if (this.showCanvasCurl) {
        this.resetCurlState();
      }
    }
  }

  private resolveSingleCurlPixelMapPlan(
    currentPageIndex: number,
    targetPageIndex: number
  ): MangaCurlSinglePixelMapPlan {
    const currentPixelMap: image.PixelMap | null = this.resolvePagePixelMapByIndex(currentPageIndex);
    const targetPixelMap: image.PixelMap | null = this.resolvePagePixelMapByIndex(targetPageIndex);
    this.curlCurrentPixelMap = currentPixelMap;
    this.curlNextPixelMap = targetPixelMap;

    const input: MangaCurlSinglePixelMapInput = new MangaCurlSinglePixelMapInput();
    input.currentPageIndex = currentPageIndex;
    input.targetPageIndex = targetPageIndex;
    input.pageCount = this.chapter.pages.length;
    input.hasCurrentPixelMap = currentPixelMap !== null;
    input.hasTargetPixelMap = targetPixelMap !== null;
    return this.mangaCurlPixelMapResolver.buildSinglePlan(input);
  }

  private resolvePagePixelMapByIndex(pageIndex: number): image.PixelMap | null {
    if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return null;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    return this.pagePixelMaps.get(page.id) || null;
  }

  private createNormalPageTurnInput(
    isSinglePageTTB: boolean,
    isVerticalDoublePage: boolean,
    thresholdX: number,
    thresholdY: number
  ): MangaPageTurnInput {
    const input: MangaPageTurnInput = new MangaPageTurnInput();
    input.readingMode = this.readingSettings.readingMode;
    input.readingDirection = this.readingSettings.readingDirection;
    input.pageCount = this.chapter.pages.length;
    input.currentPageIndex = this.viewCurrentPageIndex;
    input.translateX = this.translateX;
    input.translateY = this.translateY;
    input.thresholdX = thresholdX;
    input.thresholdY = thresholdY;
    input.isSinglePageVerticalPagingMode = isSinglePageTTB;
    input.isDoublePageVerticalPortraitMode = isVerticalDoublePage;
    input.isDoublePageVerticalNextAtTop = this.isDoublePageVerticalNextAtTop();

    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE && !isVerticalDoublePage) {
      const currentPlan: DoublePageSmartDisplayPlan = this.resolveDoublePageSmartPlanForIndex(this.viewCurrentPageIndex);
      const previousPlan: DoublePageSmartDisplayPlan = this.resolvePreviousDoublePageSmartPlan(this.viewCurrentPageIndex);
      const nextPlan: DoublePageSmartDisplayPlan = this.resolveNextDoublePageSmartPlan(this.viewCurrentPageIndex);
      input.doubleCurrentStartIndex = currentPlan.startIndex;
      input.doublePreviousStartIndex = previousPlan.startIndex;
      input.doubleNextStartIndex = nextPlan.startIndex;
      input.doublePreviousModeLabel = `${previousPlan.mode}`;
      input.doubleNextModeLabel = `${nextPlan.mode}`;
    }
    return input;
  }

  private applyNormalPageTurnPlan(plan: MangaPageTurnPlan): boolean {
    if (plan.shouldSwitchChapter) {
      if (plan.chapterDirection === 'prev' || plan.chapterDirection === 'next') {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange(plan.chapterDirection);
        }
      }
      return false;
    }

    if (!plan.pageChanged || plan.targetPageIndex < 0 || plan.targetPageIndex >= this.chapter.pages.length) {
      return false;
    }

    this.viewCurrentPageIndex = plan.targetPageIndex;
    if (plan.shouldUpdateDoublePageIndices) {
      this.updateDoublePageIndices();
    }
    this.pageTurnDirection = plan.pageTurnDirection;

    if (plan.isSinglePageTurn) {
      this.applySinglePageTurnLoadingState(plan.targetPageIndex);
    }
    if (plan.logMessage.length > 0) {
      logger.info(TAG, plan.logMessage);
    }
    return true;
  }

  private applySinglePageTurnLoadingState(targetPageIndex: number): void {
    if (targetPageIndex < 0 || targetPageIndex >= this.chapter.pages.length) {
      return;
    }
    const newPage: MangaPage = this.chapter.pages[targetPageIndex];
    const targetLoadState: ImageLoadState | undefined = this.getPageLoadState(newPage);
    const hasPixelMap: boolean = this.pagePixelMaps.has(newPage.id);

    this.currentPageIndex = targetPageIndex;
    this.suppressExternalIndex = true;
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetPageIndex);
    }
    this.updateSinglePageDisplay();
    this.incrementPixelMapEpoch(newPage.id);
    this.renderEpoch = this.renderEpoch + 1;

    if (!hasPixelMap && (!targetLoadState || !targetLoadState.isLoading)) {
      logger.debug(TAG, `翻页后触发目标页面加载: ${newPage.id}`);
      this.loadImage(newPage);
    }
  }

  private createCurlReleasePlan(
    event: GestureEvent,
    progress: number,
    widthBasis: number,
    quickVelocityThreshold: number,
    quickDistanceThreshold: number
  ): MangaCurlReleasePlan {
    const input: MangaCurlReleaseInput = new MangaCurlReleaseInput();
    input.progress = progress;
    input.flipThreshold = this.curlEffectConfig.flipThreshold;
    input.elapsedMs = Date.now() - this.panStartTime;
    input.deltaDistance = Math.abs(event.fingerList[0].globalX - this.panStartX);
    input.widthBasis = widthBasis;
    input.quickVelocityThreshold = quickVelocityThreshold;
    input.quickDistanceThreshold = quickDistanceThreshold;
    input.quickProgressThreshold = 0.03;
    return this.mangaCurlTurnPlanner.buildReleasePlan(input);
  }

  private applySingleCurlReleasePlan(plan: MangaCurlReleasePlan): void {
    if (plan.action === 'complete') {
      if (plan.isQuickFlip && this.curlProgress < this.curlEffectConfig.flipThreshold) {
        logger.info(TAG, `快速翻页触发: velocity=${plan.velocity.toFixed(2)}px/ms, progress=${this.curlProgress.toFixed(2)}`);
      }
      this.animateCurlToComplete(plan.progressVelocity);
      return;
    }
    this.animateCurlToCancel();
  }

  private applyDualCurlReleasePlan(plan: MangaCurlReleasePlan): void {
    if (plan.action === 'complete') {
      this.animateDualCurlToComplete(plan.progressVelocity);
      return;
    }
    this.animateDualCurlToCancel();
  }

  private applyCurlFallbackTurn(plan: MangaCurlFallbackPlan): void {
    if (plan.shouldRun && plan.targetPageIndex >= 0 && plan.targetPageIndex < this.chapter.pages.length) {
      const targetIndex: number = plan.targetPageIndex;
      const targetPage: MangaPage = this.chapter.pages[targetIndex];
      if (!this.pagePixelMaps.has(targetPage.id)) {
        logger.info(TAG, `降级翻页：预加载目标页 ${targetPage.id}`);
        this.ensurePixelMapLoaded(targetPage).then(() => {
          this.commitCurlFallbackPage(targetIndex);
        }).catch((e: Error) => {
          logger.error(TAG, `降级翻页失败: ${e.message}`);
        });
      } else {
        this.commitCurlFallbackPage(targetIndex);
      }
      return;
    }

    if (plan.shouldSwitchChapter && (plan.chapterDirection === 'prev' || plan.chapterDirection === 'next')) {
      if (this.callbacks.onChapterChange) {
        this.callbacks.onChapterChange(plan.chapterDirection);
      }
    }
  }

  private commitCurlFallbackPage(targetIndex: number): void {
    this.viewCurrentPageIndex = targetIndex;
    this.currentPageIndex = targetIndex;
    this.suppressExternalIndex = true;
    this.updateSinglePageDisplay();
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetIndex);
    }
    setTimeout(() => { this.suppressExternalIndex = false; }, 50);
  }

  /**
   * 处理拖拽结束
   * 支持双页模式的拖拽翻页
   */
  private handlePanEnd(event: GestureEvent): void {
    // 如果正在缩放，不处理拖拽结束
    if (this.isZooming) {
      this.isDragging = false;
      return;
    }

    this.isDragging = false;
    if (this.swipeTriggered || this.pageChangeCommitted) {
      this.translateX = 0;
      this.translateY = 0;
      return;
    }

    const isDoublePage: boolean = this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;
    const isSinglePageTTB: boolean = this.isSinglePageVerticalPagingMode();
    const isVerticalDoublePage: boolean = this.isDoublePageVerticalPortraitMode();
    const usesVerticalPagingAxis: boolean = isSinglePageTTB || isVerticalDoublePage;

    if (this.currentScale <= 1.0) {
      if (isVerticalDoublePage) {
        this.translateX = 0;
        this.translateY = 0;
        return;
      }

      const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
      const thresholdY: number = Math.max(20, Math.floor(this.screenHeight * 0.05));
      logger.debug(TAG, `拖拽结束: tx=${this.translateX.toFixed ? this.translateX.toFixed(1) : this.translateX}, ty=${this.translateY.toFixed ? this.translateY.toFixed(1) : this.translateY}, thX=${thresholdX}, thY=${thresholdY}, cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);

      if (this.handleAlbumNonePageTurn(thresholdX, thresholdY)) {
        return;
      }

      // ========== 卷页动画特殊处理 ==========
      const animationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
      if (animationType === PageTurnAnimationType.CURL && !usesVerticalPagingAxis) {
        // 双页檌屏卷页模式
        if (isDoublePage && this.isLandscapeScreen() && this.showDualCurlEffect) {
          const halfW: number = this.screenWidth > 0 ? this.screenWidth / 2 : 360;
          const dualReleasePlan: MangaCurlReleasePlan = this.createCurlReleasePlan(event, this.dualCurlProgress, halfW, 0.35, 25);
          this.applyDualCurlReleasePlan(dualReleasePlan);
          return;
        }
        // 单页卷页模式下，根据当前进度决定是完成翻页还是回弹
        if (this.showCanvasCurl) {
          const imgW: number = this.imageDisplayRect.w > 0 ? this.imageDisplayRect.w : this.screenWidth;
          const singleReleasePlan: MangaCurlReleasePlan = this.createCurlReleasePlan(event, this.curlProgress, imgW, 0.4, 30);
          this.applySingleCurlReleasePlan(singleReleasePlan);
          return;
        } else {
          // 没有进入卷页模式（PixelMap未加载），降级为普通翻页
          const fallbackInput: MangaCurlFallbackInput = new MangaCurlFallbackInput();
          fallbackInput.readingMode = this.readingSettings.readingMode;
          fallbackInput.readingDirection = this.readingSettings.readingDirection;
          fallbackInput.currentPageIndex = this.viewCurrentPageIndex;
          fallbackInput.pageCount = this.chapter.pages.length;
          fallbackInput.translateX = this.translateX;
          fallbackInput.thresholdX = thresholdX;
          const fallbackPlan: MangaCurlFallbackPlan = this.mangaCurlTurnPlanner.buildFallbackPlan(fallbackInput);
          this.applyCurlFallbackTurn(fallbackPlan);
          this.animateToPosition(0, 0);
          return;
        }
      }
      // ========== 卷页动画特殊处理结束 ==========

      const currentSinglePage: MangaPage | null = this.isSinglePageMode() ? this.getCurrentPageData().page : null;
      const previousSinglePage: MangaPage | undefined = currentSinglePage ? currentSinglePage : undefined;
      const previousSinglePageInput: Resource | string | image.PixelMap = this.singlePageImageInput;
      const normalPageTurnInput: MangaPageTurnInput = this.createNormalPageTurnInput(
        isSinglePageTTB,
        isVerticalDoublePage,
        thresholdX,
        thresholdY
      );
      const normalPageTurnPlan: MangaPageTurnPlan = this.mangaPageTurnPlanner.buildPlan(normalPageTurnInput);
      const pageChanged: boolean = this.applyNormalPageTurnPlan(normalPageTurnPlan);

      if (pageChanged) {
        this.pageChangeCommitted = true;
        this.isCommittingPageTurn = true;
        const newPage: MangaPage | undefined = (this.chapter && this.chapter.pages && this.viewCurrentPageIndex >= 0 && this.viewCurrentPageIndex < this.chapter.pages.length)
          ? this.chapter.pages[this.viewCurrentPageIndex] : undefined;
        if (previousSinglePage && this.shouldUseSoftNoneCrossfade()) {
          this.startSoftTransitionOverlay(previousSinglePage, previousSinglePageInput);
        } else {
          this.resetSoftTransitionOverlay();
        }
        if (newPage) {
          this.ensurePixelMapLoaded(newPage).catch((_e: Error) => {});
          this.incrementPixelMapEpoch(newPage.id);
        }
        if (this.viewCurrentPageIndex !== this.currentPageIndex) {
          this.currentPageIndex = this.viewCurrentPageIndex;
        }
        this.suppressExternalIndex = true;

        // 执行翻页动画（所有模式都执行）
        this.animatePageTurn();

        if (isDoublePage) {
          this.updateDoublePageIndices();
          this.updateDoublePageDisplay();
        }
        setTimeout(() => {
          if (isDoublePage) {
            this.updateDoublePagePreview();
          } else {
            this.updateSinglePagePreview();
          }
        }, 200);
        this.renderEpoch = this.renderEpoch + 1;
        if (isDoublePage) {
          this.ensureDoublePageImagesPreloaded();
        }
        if (this.callbacks.onPageChange) { this.callbacks.onPageChange(this.viewCurrentPageIndex); }
        this.animateToPosition(0, 0);
        logger.debug(TAG, `页面已切换并同步: cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);
        setTimeout(() => { this.suppressExternalIndex = false; }, 0);
        setTimeout(() => { this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
        if (!this.showSoftTransitionOverlay) {
          setTimeout(() => { this.isCommittingPageTurn = false; }, this.isSoftNonePageTurn() ? this.getSoftTransitionDuration() : 200);
        }
      } else {
        this.animateToPosition(0, 0);
        logger.debug(TAG, `未触发翻页: 位移复位, cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);
      }
    }
  }

  private animateVerticalDoublePagePageTurn(): void {
    if (!this.uiContext) {
      this.isPageTurning = false;
      this.isCommittingPageTurn = false;
      this.pageTurnDirection = null;
      this.verticalDoublePageTurnAction = null;
      this.verticalDoublePageReleasePullY = 0;
      this.pageTurnProgress = 0;
      this.resetPageTurnAnimationState();
      return;
    }

    const action: 'next' | 'prev' = this.resolveVerticalDoublePageTurnAction();
    const origin: 'top' | 'bottom' = this.getVerticalDoublePageActionOrigin(action);
    const viewportHeight: number = this.getVerticalDoublePageViewportHeight();
    const releaseProgress: number = Math.min(
      1.0,
      Math.abs(this.verticalDoublePageReleasePullY) / MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_MAX_PULL_VP
    );
    const entryDistance: number = viewportHeight * (0.12 - releaseProgress * 0.04);
    const initialOffsetY: number = origin === 'top' ? -entryDistance : entryDistance;

    this.isPageTurning = true;
    this.pageTurnProgress = 0;
    this.resetPageTurnAnimationState();
    this.currentAnimationType = PageTurnAnimationType.SLIDE;
    this.pageTurnOpacity = 0.98;
    this.pageTurnMatrix = matrix4.identity()
      .translate({ x: 0, y: initialOffsetY, z: -24 })
      .scale({ x: 0.992, y: 0.992, z: 1 });

    setTimeout(() => {
      if (!this.uiContext) {
        return;
      }

      this.uiContext.animateTo({
        duration: 240,
        curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1),
        iterations: 1,
        playMode: PlayMode.Normal,
        onFinish: () => {
          this.isPageTurning = false;
          this.isCommittingPageTurn = false;
          this.pageTurnDirection = null;
          this.verticalDoublePageTurnAction = null;
          this.verticalDoublePageReleasePullY = 0;
          this.pageTurnProgress = 0;
          this.currentAnimationType = PageTurnAnimationType.NONE;
          this.resetSoftTransitionOverlay();
          this.resetVerticalDoublePageBoundaryState();
          this.forceRefreshVerticalDoublePageCurrentPair('animation_finish');
          logger.debug(TAG, '双页竖向边界翻页动画完成');
        }
      }, () => {
        this.pageTurnProgress = 1.0;
        this.pageTurnOpacity = 1.0;
        this.pageTurnMatrix = matrix4.identity();
        this.pageTurnScale = 1.0;
        this.pageTurnTranslateX = 0;
        this.pageTurnTranslateY = 0;
        this.pageTurnRotateY = 0;
        this.pageTurnRotateX = 0;
        this.pageTurnRotateZ = 0;
        this.pageTurnPerspective = 0;
        this.pageTurnSkewX = 0;
        this.pageTurnSkewY = 0;
      });
    }, 0);
  }

  /**
   * 执行翻页动画
   * 根据readingSettings.pageTurnAnimation设置使用不同的动画效果
   * 使用matrix4实现真正的3D翻页动画效果
   */
  private animatePageTurn(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext未初始化，跳过翻页动画');
      return;
    }

    if (this.isDoublePageVerticalPortraitMode()) {
      this.animateVerticalDoublePagePageTurn();
      return;
    }

    const configuredAnimationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
    const animationType = configuredAnimationType === PageTurnAnimationType.NONE
      ? PageTurnAnimationType.FADE
      : configuredAnimationType;
    const isForward = this.pageTurnDirection === 'left' || this.pageTurnDirection === 'up';
    const isVerticalTurn = this.pageTurnDirection === 'up' || this.pageTurnDirection === 'down';
    const screenW = this.screenWidth > 0 ? this.screenWidth : 360;
    const screenH = this.screenHeight > 0 ? this.screenHeight : 780;

    logger.info(TAG, `开始执行翻页动画: 类型=${animationType}, 配置=${configuredAnimationType}, 方向=${this.pageTurnDirection}`);

    const useSoftNoneTransition = configuredAnimationType === PageTurnAnimationType.NONE;
    const useSoftNoneCrossfade = useSoftNoneTransition && this.showSoftTransitionOverlay;
    if (useSoftNoneTransition) {
      logger.debug(TAG, '关闭动画档位保留轻量淡入过渡，仅禁用图片位移回弹');
      this.isPageTurning = false;
      this.pageTurnDirection = null;
      this.pageTurnProgress = 0;
      this.currentAnimationType = PageTurnAnimationType.NONE;
      this.resetPageTurnAnimationState();
      const targetPage = this.getCurrentPageData().page;
      if (useSoftNoneCrossfade && targetPage && this.isPageReadyForDisplay(targetPage)) {
        this.scheduleSoftTransitionOverlayOut();
      } else if (!useSoftNoneCrossfade) {
        this.isCommittingPageTurn = false;
      }
      return;
    }

    // 设置翻页动画状态
    this.isPageTurning = true;
    this.currentAnimationType = animationType;

    // 根据动画类型设置初始状态和动画参数
    let duration: number = 300;
    let animCurve: Curve = Curve.EaseInOut;

    // 重置所有动画状态
    this.resetPageTurnAnimationState();

    // 使用matrix4创建真正的3D变换矩阵
    // 先设置初始状态（新页面的起始状态）
    switch (animationType) {
      case PageTurnAnimationType.SLIDE:
        duration = 350;
        animCurve = Curve.FastOutSlowIn;
        this.pageTurnOpacity = 1.0;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: this.pageTurnDirection === 'up' ? screenH : -screenH, z: -50 })
              .scale({ x: 0.95, y: 0.95, z: 1 })
          : matrix4.identity()
              .translate({ x: isForward ? screenW : -screenW, y: 0, z: -50 })
              .scale({ x: 0.95, y: 0.95, z: 1 });
        break;

      case PageTurnAnimationType.FADE:
        // 淡入淡出效果：纯透明度变化，带轻微缩放
        duration = 280;
        animCurve = Curve.EaseOut;
        this.pageTurnOpacity = 0.3; // 从半透明开始，避免完全消失
        this.pageTurnMatrix = matrix4.identity()
          .scale({ x: 0.98, y: 0.98, z: 1 });
        break;

      case PageTurnAnimationType.CURL:
        logger.info(TAG, isVerticalTurn ? '纵向卷页回退到纵向滑动动画' : '卷页动画由独立流程处理，此处使用滑动动画');
        duration = 350;
        animCurve = Curve.EaseOut;
        this.pageTurnOpacity = 1.0;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity().translate({ x: 0, y: this.pageTurnDirection === 'up' ? screenH : -screenH, z: 0 })
          : matrix4.identity().translate({ x: isForward ? screenW : -screenW, y: 0, z: 0 });
        break;

      case PageTurnAnimationType.ZOOM:
        duration = 400;
        animCurve = Curve.FastOutSlowIn;
        this.pageTurnOpacity = 0.7;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: this.pageTurnDirection === 'up' ? screenH * 0.06 : -screenH * 0.06, z: -300 })
              .scale({ x: 0.6, y: 0.6, z: 1 })
              .rotate({ x: 1, y: 0, z: 0, angle: this.pageTurnDirection === 'up' ? 12 : -12 })
          : matrix4.identity()
              .translate({ x: 0, y: -screenH * 0.05, z: -300 })
              .scale({ x: 0.6, y: 0.6, z: 1 })
              .rotate({ x: 1, y: 0, z: 0, angle: -15 })
              .rotate({ x: 0, y: 1, z: 0, angle: isForward ? 8 : -8 });
        break;

      case PageTurnAnimationType.FLIP: {
        duration = 420;
        animCurve = Curve.EaseInOut;
        this.pageTurnOpacity = 1.0;
        const flipAngle = isVerticalTurn
          ? (this.pageTurnDirection === 'up' ? -90 : 90)
          : (isForward ? 90 : -90);
        const flipTranslateX = isForward ? screenW * 0.5 : -screenW * 0.5;
        const flipTranslateY = this.pageTurnDirection === 'up' ? screenH * 0.5 : -screenH * 0.5;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: flipTranslateY, z: -screenH * 0.25 })
              .rotate({ x: 1, y: 0, z: 0, angle: flipAngle })
              .scale({ x: 0.95, y: 0.95, z: 1 })
          : matrix4.identity()
              .translate({ x: flipTranslateX, y: 0, z: -screenW * 0.25 })
              .rotate({ x: 0, y: 1, z: 0, angle: flipAngle })
              .scale({ x: 0.95, y: 0.95, z: 1 });
        break;
      }

      case PageTurnAnimationType.CUBE: {
        duration = 420;
        animCurve = Curve.EaseInOut;
        this.pageTurnOpacity = 1.0;
        const cubeAngle = isVerticalTurn
          ? (this.pageTurnDirection === 'up' ? -90 : 90)
          : (isForward ? 90 : -90);
        const cubeTranslateX = isForward ? screenW * 0.5 : -screenW * 0.5;
        const cubeTranslateY = this.pageTurnDirection === 'up' ? screenH * 0.5 : -screenH * 0.5;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: cubeTranslateY, z: -screenH * 0.25 })
              .rotate({ x: 1, y: 0, z: 0, angle: cubeAngle })
              .scale({ x: 0.95, y: 0.95, z: 1 })
          : matrix4.identity()
              .translate({ x: cubeTranslateX, y: 0, z: -screenW * 0.25 })
              .rotate({ x: 0, y: 1, z: 0, angle: cubeAngle })
              .scale({ x: 0.95, y: 0.95, z: 1 });
        break;
      }

      case PageTurnAnimationType.COVER:
        duration = 400;
        animCurve = Curve.FastOutSlowIn;
        this.pageTurnOpacity = 0.5;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: this.pageTurnDirection === 'up' ? screenH : -screenH, z: 50 })
              .scale({ x: 1.02, y: 1.02, z: 1 })
              .rotate({ x: 1, y: 0, z: 0, angle: this.pageTurnDirection === 'up' ? -5 : 5 })
          : matrix4.identity()
              .translate({ x: isForward ? screenW : -screenW, y: 0, z: 50 })
              .scale({ x: 1.02, y: 1.02, z: 1 })
              .rotate({ x: 0, y: 1, z: 0, angle: isForward ? 5 : -5 });
        break;

      case PageTurnAnimationType.DEPTH:
        duration = 400;
        animCurve = Curve.FastOutSlowIn;
        this.pageTurnOpacity = 0.7;
        this.pageTurnMatrix = isVerticalTurn
          ? matrix4.identity()
              .translate({ x: 0, y: this.pageTurnDirection === 'up' ? screenH * 0.06 : -screenH * 0.06, z: -300 })
              .scale({ x: 0.6, y: 0.6, z: 1 })
              .rotate({ x: 1, y: 0, z: 0, angle: this.pageTurnDirection === 'up' ? 16 : -16 })
          : matrix4.identity()
              .translate({ x: 0, y: -screenH * 0.05, z: -300 })
              .scale({ x: 0.6, y: 0.6, z: 1 })
              .rotate({ x: 1, y: 0, z: 0, angle: -15 })
              .rotate({ x: 0, y: 1, z: 0, angle: isForward ? 8 : -8 });
        break;

      default:
        duration = 300;
        animCurve = Curve.EaseInOut;
        this.pageTurnOpacity = 0.5;
        this.pageTurnMatrix = matrix4.identity().scale({ x: 0.95, y: 0.95, z: 1 });
    }

    logger.debug(TAG, `翻页动画初始状态: 类型=${animationType}, opacity=${this.pageTurnOpacity}`);

    // Canvas卷页使用自定义动画更新curlProgress
    if (animationType === PageTurnAnimationType.CURL) {
      this.startCurlAnimation(duration, animCurve);
      logger.info(TAG, `执行Canvas卷页动画: 时长=${duration}ms`);
      return;
    }

    // 使用setTimeout确保初始状态已应用，然后执行动画到目标状态
    setTimeout(() => {
      if (!this.uiContext) return;

      this.uiContext.animateTo({
        duration: duration,
        curve: curves.initCurve(animCurve),
        iterations: 1,
        playMode: PlayMode.Normal,
        onFinish: () => {
          this.isPageTurning = false;
          this.pageTurnDirection = null;
          this.pageTurnProgress = 0;
          this.currentAnimationType = PageTurnAnimationType.NONE;
          this.resetSoftTransitionOverlay();
          logger.debug(TAG, `翻页动画完成`);

          // 【修复】动画完成后刷新UI，确保显示正确的页面
          if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
            this.updateDoublePageDisplay();
          } else {
            this.updateSinglePageDisplay();
          }
        }
      }, () => {
        // 动画目标状态：恢复正常（单位矩阵）
        this.pageTurnOpacity = 1.0;
        this.pageTurnMatrix = matrix4.identity();
        this.pageTurnScale = 1.0;
        this.pageTurnTranslateX = 0;
        this.pageTurnTranslateY = 0;
        this.pageTurnRotateY = 0;
        this.pageTurnRotateX = 0;
        this.pageTurnRotateZ = 0;
        this.pageTurnPerspective = 0;
        this.pageTurnSkewX = 0;
        this.pageTurnSkewY = 0;
      });
    }, 16); // 等待一帧确保初始状态渲染

    logger.info(TAG, `执行翻页动画: 类型=${animationType}, 方向=${this.pageTurnDirection}, 时长=${duration}ms`);
  }

  /**
   * 重置翻页动画状态到默认值
   */
  private resetPageTurnAnimationState(): void {
    this.pageTurnOpacity = 1.0;
    this.pageTurnScale = 1.0;
    this.pageTurnTranslateX = 0;
    this.pageTurnTranslateY = 0;
    this.pageTurnRotateY = 0;
    this.pageTurnRotateX = 0;
    this.pageTurnRotateZ = 0;
    this.pageTurnPerspective = 0;
    this.pageTurnSkewX = 0;
    this.pageTurnSkewY = 0;
    this.pageTurnMatrix = matrix4.identity();
    this.currentAnimationType = PageTurnAnimationType.NONE;
    // 重置Canvas卷页状态
    this.showCanvasCurl = false;
    this.curlProgress = 0;
    this.curlCurrentPixelMap = null;
    this.curlNextPixelMap = null;
  }

  /**
   * 准备卷页效果所需的图片路径
   */
  private prepareCurlPagePaths(isForward: boolean): void {
    const currentPageData = this.getCurrentPageData();
    const currentPage = currentPageData.page;
    if (!currentPage) {
      logger.warn(TAG, '当前页面数据不存在');
      return;
    }

    // 记录翻页方向
    this.curlIsForward = isForward;

    // 获取当前页PixelMap（从pagePixelMaps缓存中获取）
    if (currentPage) {
      this.curlCurrentPixelMap = this.pagePixelMaps.get(currentPage.id) || null;
    } else {
      this.curlCurrentPixelMap = null;
    }

    // 获取下一页/上一页PixelMap
    const targetIndex = isForward ?
      this.viewCurrentPageIndex + 1 :
      this.viewCurrentPageIndex - 1;

    if (targetIndex >= 0 && targetIndex < this.chapter.pages.length) {
      const targetPage = this.chapter.pages[targetIndex];
      this.curlNextPixelMap = this.pagePixelMaps.get(targetPage.id) || null;
    } else {
      this.curlNextPixelMap = null;
    }

    // 计算图片显示区域
    this.calculateImageDisplayRect();

    logger.info(TAG, `卷页PixelMap: current=${this.curlCurrentPixelMap ? 'loaded' : 'null'}, next=${this.curlNextPixelMap ? 'loaded' : 'null'}, isForward=${isForward}`);
  }

  /**
   * 计算图片在组件中的实际显示区域
   * 用于Canvas卷页效果基于图片实际位置渲染
   */
  private calculateImageDisplayRect(): void {
    if (!this.curlCurrentPixelMap) {
      // 默认全屏
      const defaultRect: ImageDisplayRect = { x: 0, y: 0, w: this.screenWidth, h: this.screenHeight };
      this.imageDisplayRect = defaultRect;
      return;
    }

    try {
      const pmInfo = this.curlCurrentPixelMap.getImageInfoSync();
      const imgW: number = pmInfo.size.width;
      const imgH: number = pmInfo.size.height;
      const compW: number = this.screenWidth;
      const compH: number = this.screenHeight;

      // 计算适应组件的缩放比例（保持宽高比）
      const scaleW: number = compW / imgW;
      const scaleH: number = compH / imgH;
      const scale: number = Math.min(scaleW, scaleH);

      // 计算显示尺寸
      const displayW: number = imgW * scale;
      const displayH: number = imgH * scale;

      // 居中显示
      const displayX: number = (compW - displayW) / 2;
      const displayY: number = (compH - displayH) / 2;

      const rect: ImageDisplayRect = { x: displayX, y: displayY, w: displayW, h: displayH };
      this.imageDisplayRect = rect;
      logger.debug(TAG, `图片显示区域: x=${displayX.toFixed(1)}, y=${displayY.toFixed(1)}, w=${displayW.toFixed(1)}, h=${displayH.toFixed(1)}`);
    } catch (e) {
      // 出错时使用全屏
      const fallbackRect: ImageDisplayRect = { x: 0, y: 0, w: this.screenWidth, h: this.screenHeight };
      this.imageDisplayRect = fallbackRect;
    }
  }

  // Canvas卷页动画定时器
  private curlAnimationTimer: number = -1;

  /**
   * 启动Canvas卷页动画
   * 使用自定义定时器更新curlProgress，实现平滑的卷页效果
   */
  private startCurlAnimation(duration: number, curve: Curve): void {
    // 停止之前的动画
    this.stopCurlAnimation();

    const startTime = Date.now();
    const startProgress = 0;
    const targetProgress = 1;

    const animate = () => {
      const elapsed = Date.now() - startTime;
      const t = Math.min(1, elapsed / duration);

      // 使用缓动函数（easeInOut）
      const easeT = t < 0.5
        ? 2 * t * t
        : 1 - Math.pow(-2 * t + 2, 2) / 2;

      this.curlProgress = startProgress + (targetProgress - startProgress) * easeT;

      if (t < 1) {
        this.curlAnimationTimer = setTimeout(animate, 16) as number; // ~60fps
      } else {
        // 动画完成
        this.curlProgress = targetProgress;
        this.onCurlAnimationComplete();
      }
    };

    // 开始动画
    this.curlAnimationTimer = setTimeout(animate, 16) as number;
  }

  /**
   * 停止Canvas卷页动画
   */
  private stopCurlAnimation(): void {
    if (this.curlAnimationTimer !== -1) {
      clearTimeout(this.curlAnimationTimer);
      this.curlAnimationTimer = -1;
    }
  }

  /**
   * 启动卷页翻页动画（独立流程，不使用预览）
   * 这是一个完全独立的翻页流程，不依赖普通的页面切换逻辑
   *
   * @param targetIndex 目标页面索引
   * @param isForward 是否向前翻页（下一页）
   */
  private startCurlPageTurn(targetIndex: number, isForward: boolean): void {
    const currentIndex: number = this.viewCurrentPageIndex;

    logger.info(TAG, `启动卷页翻页: 当前页=${currentIndex}, 目标页=${targetIndex}, isForward=${isForward}`);

    // 获取当前页的PixelMap（正在被翻走的页面）
    const currentPage: MangaPage = this.chapter.pages[currentIndex];
    this.curlCurrentPixelMap = this.pagePixelMaps.get(currentPage.id) || null;

    // 获取目标页的PixelMap（将要显示的页面）
    const targetPage: MangaPage = this.chapter.pages[targetIndex];
    this.curlNextPixelMap = this.pagePixelMaps.get(targetPage.id) || null;

    // 【修复】检查当前页PixelMap是否已加载
    if (!this.curlCurrentPixelMap) {
      logger.warn(TAG, `当前页PixelMap未加载，开始加载并等待`);
      this.recordReadFlowDegraded(
        currentPage,
        currentIndex,
        'curl_current_pixelmap_missing_wait',
        `target=${targetIndex}, forward=${isForward}`
      );

      // 【修复】显示Loading状态，避免黑屏
      this.isPageTurning = true;
      this.pageTurnOpacity = 0.5; // 半透明显示当前页

      // 【修复】设置3秒超时（而不是立即降级）
      const loadTimeout = setTimeout(() => {
        logger.error(TAG, `PixelMap加载超时，降级到普通翻页`);
        this.recordReadFlowDegraded(
          currentPage,
          currentIndex,
          'curl_current_pixelmap_timeout_fallback',
          `target=${targetIndex}, timeoutMs=${SINGLE_CURL_PIXELMAP_WAIT_TIMEOUT_MS}`
        );
        this.isPageTurning = false;
        this.pageTurnOpacity = 1.0;
        this.fallbackToNormalPageTurn(targetIndex, isForward);
      }, SINGLE_CURL_PIXELMAP_WAIT_TIMEOUT_MS);

      // 尝试加载
      this.ensurePixelMapLoaded(currentPage).then(() => {
        clearTimeout(loadTimeout);
        this.curlCurrentPixelMap = this.pagePixelMaps.get(currentPage.id) || null;

        if (this.curlCurrentPixelMap) {
          // 加载成功，执行卷页动画
          logger.info(TAG, `当前页PixelMap加载成功，执行卷页动画`);
          this.recordReadFlowRecovered(
            currentPage,
            currentIndex,
            'curl_current_pixelmap_loaded',
            `target=${targetIndex}`
          );
          this.executeCurlAnimation(targetIndex, isForward);
        } else {
          // 加载失败，降级
          logger.warn(TAG, `当前页PixelMap加载失败，降级到普通翻页`);
          this.recordReadFlowDegraded(
            currentPage,
            currentIndex,
            'curl_current_pixelmap_failed_fallback',
            `target=${targetIndex}`
          );
          this.isPageTurning = false;
          this.pageTurnOpacity = 1.0;
          this.fallbackToNormalPageTurn(targetIndex, isForward);
        }
      }).catch(() => {
        clearTimeout(loadTimeout);
        logger.error(TAG, `当前页PixelMap加载异常，降级到普通翻页`);
        this.recordReadFlowDegraded(
          currentPage,
          currentIndex,
          'curl_current_pixelmap_exception_fallback',
          `target=${targetIndex}`
        );
        this.isPageTurning = false;
        this.pageTurnOpacity = 1.0;
        this.fallbackToNormalPageTurn(targetIndex, isForward);
      });

      // 先复位位置
      this.animateToPosition(0, 0);
      return;
    }

    // 【修复】如果下一页PixelMap未加载，不影响卷页动画启动
    // 卷页动画可以显示空白的下一页，后台继续加载
    if (!this.curlNextPixelMap) {
      logger.info(TAG, `下一页PixelMap未加载，后台加载中`);
      this.recordReadFlowDegraded(
        targetPage,
        targetIndex,
        'curl_next_pixelmap_missing_continue',
        `current=${currentIndex}, forward=${isForward}`
      );
      this.ensurePixelMapLoaded(targetPage).then(() => {
        this.curlNextPixelMap = this.pagePixelMaps.get(targetPage.id) || null;
        if (this.curlNextPixelMap) {
          logger.info(TAG, `下一页PixelMap加载完成`);
          this.recordReadFlowRecovered(
            targetPage,
            targetIndex,
            'curl_next_pixelmap_loaded',
            `current=${currentIndex}`
          );
        }
      }).catch((err:Error) => {
        logger.error(TAG, `下一页PixelMap加载失败: ${err}`);
        this.recordReadFlowDegraded(
          targetPage,
          targetIndex,
          'curl_next_pixelmap_failed_continue',
          String(err)
        );
      });
    }

    // 执行卷页动画
    this.executeCurlAnimation(targetIndex, isForward);
  }

  /**
   * 执行卷页动画
   */
  private executeCurlAnimation(targetIndex: number, isForward: boolean): void {
    // 保存待切换的页面索引
    this.curlPendingPageIndex = targetIndex;
    this.curlIsForward = isForward;

    // 计算图片显示区域
    this.calculateImageDisplayRect();

    // 设置动画状态
    this.isPageTurning = true;
    this.pageTurnDirection = isForward ? 'left' : 'right';
    this.currentAnimationType = PageTurnAnimationType.CURL;
    this.pageChangeCommitted = true;
    this.isCommittingPageTurn = true;

    // 隐藏普通内容层，显示Canvas卷页层
    this.pageTurnOpacity = 0;
    this.showCanvasCurl = true;
    this.curlProgress = 0;

    // 复位拖拽位置
    this.translateX = 0;
    this.translateY = 0;

    logger.info(TAG, `执行卷页动画: current=${this.curlCurrentPixelMap ? 'loaded' : 'null'}, next=${this.curlNextPixelMap ? 'loaded' : 'null'}`);

    // 启动动画
    const duration: number = this.curlEffectConfig.animationDuration;
    const startTime: number = Date.now();

    const animateFrame = (): void => {
      const elapsed: number = Date.now() - startTime;
      const progress: number = Math.min(elapsed / duration, 1.0);

      // 使用缓动函数
      this.curlProgress = this.easeInOutCubic(progress);

      if (progress < 1.0) {
        const timerId: number = setTimeout(animateFrame, 16);
        this.curlAnimationTimer = timerId;
      } else {
        this.curlProgress = 1.0;
        this.curlAnimationTimer = -1;
        // 动画完成
        setTimeout(() => {
          this.onCurlAnimationComplete();
        }, 50);
      }
    };

    // 开始动画
    const startTimerId: number = setTimeout(animateFrame, 16);
    this.curlAnimationTimer = startTimerId;
  }

  /**
   * 缓动函数
   */
  private easeInOutCubic(t: number): number {
    return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  }

  /**
   * 缓动函数 - 缓出
   */
  private easeOutCubic(t: number): number {
    return 1 - Math.pow(1 - t, 3);
  }

  /**
   * 动画完成卷页翻页
   * @param velocity 脱手时的翻页速度 (progress/ms)，用于使动画延续用户力度
   */
  private animateCurlToComplete(velocity: number = 0): void {
    this.stopCurlAnimation();

    // 提前更新页面索引，让底层UI在动画过程中就切换到新页面
    // 这样动画结束移除Canvas时，底层已经稳定显示新页面，避免UI抄动
    const targetIndex: number = this.curlPendingPageIndex;
    if (targetIndex >= 0 && targetIndex < this.chapter.pages.length) {
      logger.info(TAG, `[animateCurlToComplete] 提前切换页面: ${this.viewCurrentPageIndex + 1} -> ${targetIndex + 1}`);

      // 更新页面索引
      this.viewCurrentPageIndex = targetIndex;
      this.currentPageIndex = targetIndex;
      this.suppressExternalIndex = true;

      // 强制刷新底层Image组件显示新页面
      this.updateSinglePageDisplay();

      // 触发页面变更回调
      if (this.callbacks.onPageChange) {
        this.callbacks.onPageChange(targetIndex);
      }

      // 更新预加载 - 使用新的统一预加载方法
      this.triggerUnifiedPreload();
    }

    const startProgress: number = this.curlProgress;

    logger.info(TAG, `动画完成卷页(内部模式): startProgress=${startProgress.toFixed(2)}, velocity=${velocity.toFixed(4)}`);

    // 禁用外部进度控制，避免与内部动画冲突
    this.curlProgress = -1;

    // 传递吸手速度给内部动画，使动画从用户的实际力度出发
    this.curlAnimateVelocity = velocity;
    // 使用内部动画模式：设置目标进度，让 PageCurlEffectV2 内部执行动画循环
    this.curlAnimateFrom = startProgress;
    this.curlAnimateTarget = 1.0;  // 触发内部动画
  }

  /**
   * 内部动画完成回调（高性能模式）
   */
  private onCurlInternalAnimationComplete(): void {
    const targetProgress: number = this.curlAnimateTarget;

    // 重置内部动画状态
    this.curlAnimateTarget = -1;
    this.curlAnimateFrom = 0;

    if (targetProgress >= 1.0) {
      // 完成翻页
      this.onCurlAnimationComplete();
    } else if (targetProgress <= 0) {
      // 回弹取消
      this.resetCurlState();
    }
  }

  /**
   * 动画取消卷页（回弹）
   * 使用内部动画模式提高性能
   */
  private animateCurlToCancel(): void {
    this.stopCurlAnimation();

    const startProgress: number = this.curlProgress;

    logger.info(TAG, `动画取消卷页(内部模式): startProgress=${startProgress.toFixed(2)}`);

    // 禁用外部进度控制，避免与内部动画冲突
    this.curlProgress = -1;

    // 回弹动画不使用速度延续，使用默认缓出
    this.curlAnimateVelocity = 0;
    // 使用内部动画模式
    this.curlAnimateFrom = startProgress;
    this.curlAnimateTarget = 0;  // 触发回弹动画
  }

  /**
   * 回退到普通翻页（当卷页动画无法执行时）
   */
  private fallbackToNormalPageTurn(targetIndex: number, isForward: boolean): void {
    logger.warn(TAG, `回退到普通翻页: target=${targetIndex}`);
    const targetPage: MangaPage | null = this.chapter && this.chapter.pages && targetIndex >= 0 && targetIndex < this.chapter.pages.length
      ? this.chapter.pages[targetIndex]
      : null;
    this.recordReadFlowDegraded(
      targetPage,
      targetIndex,
      'curl_fallback_to_normal_page_turn',
      `forward=${isForward}`
    );

    // 直接切换页面
    this.viewCurrentPageIndex = targetIndex;
    this.currentPageIndex = targetIndex;
    this.suppressExternalIndex = true;

    // 更新显示
    this.updateSinglePageDisplay();

    // 触发回调
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetIndex);
    }

    // 复位位置
    this.animateToPosition(0, 0);

    setTimeout(() => { this.suppressExternalIndex = false; }, 50);
  }

  /**
   * Canvas卷页动画完成回调
   * 注意：页面索引更新已在 animateCurlToComplete 中提前完成
   * 此处仅负责清理卷页状态和隐藏Canvas层
   */
  private onCurlAnimationComplete(): void {
    logger.info(TAG, `Canvas卷页动画完成，执行清理`);

    // 重要：先重置部分状态，但保持 curlProgress = 1.0 不变
    // 这样 Canvas 在隐藏前继续显示动画完成状态（即新页面），与底层 Image 一致
    this.curlPendingPageIndex = -1;
    this.isPageTurning = false;
    this.pageTurnDirection = null;
    this.currentAnimationType = PageTurnAnimationType.NONE;

    // 延迟隐藏Canvas层，确保底层图片组件完全稳定
    // 由于页面已在动画开始时切换，此时底层UI应该已经渲染完成
    setTimeout(() => {
      // 先隐藏 Canvas 层
      this.showCanvasCurl = false;
      // 恢复普通内容层的透明度
      this.pageTurnOpacity = 1.0;

      // Canvas 隐藏后再重置 curlProgress 和 PixelMap
      // 这样可以避免重置 curlProgress 时触发 PageCurlEffectV2 重新渲染导致的闪烁
      setTimeout(() => {
        this.curlProgress = 0;
        this.curlAnimateTarget = -1;  // 重置内部动画状态
        this.curlAnimateFrom = 0;
        this.curlAnimateVelocity = 0;  // 重置速度
        this.curlCurrentPixelMap = null;
        this.curlNextPixelMap = null;
        this.suppressExternalIndex = false;
      }, 0);
    }, 50);

    // 执行所有待处理的回调
    const callbacks = this.curlAnimationCallbacks.slice();
    this.curlAnimationCallbacks = [];
    callbacks.forEach(cb => {
      try { cb(); } catch (e) { /* ignore */ }
    });
  }

  // ========== 双页卷页动画方法 ==========

  /**
   * 停止双页卷页动画定时器
   */
  private stopDualCurlAnimation(): void {
    if (this.dualCurlAnimTimer !== -1) {
      clearTimeout(this.dualCurlAnimTimer);
      this.dualCurlAnimTimer = -1;
    }
  }

  /**
   * 重置双页卷页状态
   * 注意：不释放 PixelMap，只清空引用（缓存由 pagePixelMaps 管理）
   */
  private resetDualCurlState(): void {
    this.stopDualCurlAnimation();
    this.showDualCurlEffect = false;
    this.dualCurlEffectOpacity = 1.0; // 重置透明度
    this.dualCurlProgress = 0;
    this.dualCurlPendingPairStart = -1;
    this.isPageTurning = false;
    this.pageChangeCommitted = false;
    this.isCommittingPageTurn = false;
    this.pageTurnDirection = null;
    this.currentAnimationType = PageTurnAnimationType.NONE;
    // 重置位移状态，避免底层 Row 跳动
    this.translateX = 0;
    this.translateY = 0;
    this.initialTranslateX = 0;
    this.initialTranslateY = 0;
    // 清空引用，不释放（PixelMap 由 pagePixelMaps 缓存管理）
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;
  }

  /**
   * 双页卷页动画完成回调
   * 
   * 核心策略：
   * 1. 动画完成后 Canvas 继续显示静态新页面（progress=1.0 时 DualPageCurlEffect 绘制 next 页）
   * 2. 更新底层 Image 数据源后，等待底层完全渲染
   * 3. 然后直接隐藏 Canvas 层（不需要淡出，因为内容一致）
   */
  private onDualCurlAnimationComplete(): void {
    const targetPairStart: number = this.dualCurlPendingPairStart;
    logger.info(TAG, `[双页卷页] 动画完成: target=${targetPairStart}`);

    // 0. 立即重置动画类型，防止后续索引更新触发额外的翻页动画
    this.currentAnimationType = PageTurnAnimationType.NONE;
    this.pageTurnDirection = null;
    // 注意：保持 dualCurlProgress = 1.0，这样 Canvas 会绘制静态新页面

    // 1. 重置位移状态
    this.translateX = 0;
    this.translateY = 0;
    this.initialTranslateX = 0;
    this.initialTranslateY = 0;

    // 2. 更新页面索引（Canvas 层显示静态新页面，用户看不到底层变化）
    if (targetPairStart >= 0) {
      this.viewCurrentPageIndex = targetPairStart;
      this.currentPageIndex = targetPairStart;
      this.suppressExternalIndex = true;
      this.updateDoublePageIndices();
      this.updateDoublePageDisplay();
      if (this.callbacks.onPageChange) {
        this.callbacks.onPageChange(targetPairStart);
      }
    }

    // 3. 停止动画定时器
    this.stopDualCurlAnimation();

    // 4. 完整重置状态
    this.dualCurlPendingPairStart = -1;
    this.pageChangeCommitted = false;
    this.isCommittingPageTurn = false;

    // 5. 等待底层 Image 完全渲染后，直接隐藏 Canvas
    // 由于 Canvas 显示的内容与底层 Image 完全一致，不会有闪烁
    setTimeout(() => {
      this.finalizeDualCurlTransition();
    }, 150); // 等待 150ms 让底层 Image 完成渲染

    setTimeout(() => { this.suppressExternalIndex = false; }, 200);
    logger.info(TAG, `[双页卷页] 状态重置完成，等待底层渲染`);
  }

  /**
   * 最终化双页卷页过渡 - 直接隐藏 Canvas 层
   * 由于 Canvas 已经绘制了静态新页面（与底层 Image 一致），所以直接隐藏不会闪烁
   */
  private finalizeDualCurlTransition(): void {
    // 直接隐藏 Canvas 层，不需要淡出动画
    this.showDualCurlEffect = false;
    this.isPageTurning = false;
    this.dualCurlProgress = 0;
    this.dualCurlEffectOpacity = 1.0;
    // 清空 PixelMap 引用
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;
    logger.debug(TAG, `[双页卷页] Canvas 层已隐藏`);
  }

  /**
   * 双页卷页效果层淡出动画（备用，当前不使用）
   */
  private animateDualCurlFadeOut(): void {
    const FADE_DURATION: number = 120;
    const startTime: number = Date.now();
    const startOpacity: number = this.dualCurlEffectOpacity;

    const animateFade = (): void => {
      const elapsed: number = Date.now() - startTime;
      const t: number = Math.min(elapsed / FADE_DURATION, 1.0);
      const eased: number = 1 - Math.pow(1 - t, 2);
      this.dualCurlEffectOpacity = startOpacity * (1 - eased);

      if (t < 1.0) {
        setTimeout(animateFade, 16);
      } else {
        this.finalizeDualCurlTransition();
      }
    };

    animateFade();
  }

  /**
   * 父组件驱动的双页卷页动画
   *
   * 动画时长由脱手速度（velocity）决定，使动画无缝延续用户的翻页力度：
   *  - 有速度时：duration = 3 * Δ / v（easeOutCubic 初始斜率=3 → 动画开始速度 ≈ 用户脱手速度）
   *  - 无速度时：使用基于进度的默认时长
   *
   * @param target 目标进度 (0 或 1)
   * @param onComplete 完成回调
   * @param velocity 脱手速度 (progress/ms)，0 = 使用默认时长
   */
  private animateDualCurlProgressTo(target: number, onComplete: () => void, velocity: number = 0): void {
    this.stopDualCurlAnimation();

    const start: number = this.dualCurlProgress;
    const progressDelta: number = Math.abs(target - start);

    if (progressDelta < 0.01) {
      this.dualCurlProgress = target;
      onComplete();
      return;
    }

    const isComplete: boolean = target > start;

    let duration: number;
    if (velocity > 0.0003 && isComplete) {
      // ① 速度驱动时长（与 PageCurlEffectV2 完全一致）
      // easeOutCubic 的归一化初始斜率 = 3
      // 令 3 * Δ / T = v  →  T = 3 * Δ / v
      // 这样动画第一帧的实际速度恰好等于用户脱手时的速度，实现无缝衔接
      const physDuration: number = 3.0 * progressDelta / velocity;
      // 限制在合理范围：太短会看不清动画，太长则拖沓
      duration = Math.min(500, Math.max(120, physDuration));
    } else if (isComplete) {
      // ② 无速度信息（tap 触发翻页）：基于剩余进度估算
      duration = Math.max(200, this.curlEffectConfig.animationDuration * progressDelta * 1.5);
    } else {
      // ③ 回弹取消：固定底线确保平滑返回
      duration = Math.max(220, this.curlEffectConfig.animationDuration * progressDelta * 1.8);
    }

    const startTime: number = Date.now();

    const animate = (): void => {
      const now: number = Date.now();
      const elapsed: number = now - startTime;
      const t: number = Math.min(elapsed / Math.max(duration, 50), 1.0);

      // easeOutCubic：初始斜率=3，快速减速至终点
      // 与速度驱动时长配合，保证动画起始速度无缝衔接用户手势力度
      const eased: number = 1 - Math.pow(1 - t, 3);

      this.dualCurlProgress = start + (target - start) * eased;

      if (t < 1.0) {
        // 动态补偿帧处理时间，维持接近 60fps
        const frameTime: number = Date.now() - now;
        const nextDelay: number = Math.max(1, 16 - frameTime);
        this.dualCurlAnimTimer = setTimeout(animate, nextDelay);
      } else {
        this.dualCurlProgress = target;
        this.dualCurlAnimTimer = -1;
        onComplete();
      }
    };

    // 立即执行第一帧（同步），避免 setTimeout 引入额外延迟
    animate();
  }

  /**
   * 执行双页卷页动画（tap 触发）
   */
  private performDualCurlAnimation(targetPairStart: number, isForward: boolean): void {
    const currentPairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    logger.info(TAG, `[双页卷页] 开始: current=${currentPairStart}, target=${targetPairStart}, forward=${isForward}`);

    // 重置位移状态，确保底层 Row 在动画期间不会有任何偏移
    this.translateX = 0;
    this.translateY = 0;
    this.initialTranslateX = 0;
    this.initialTranslateY = 0;

    this.isPageTurning = true;
    this.curlIsForward = isForward;
    this.curlTouchY = this.screenHeight / 2;

    // 从缓存中获取 4 张 PixelMap（不进行拷贝，直接引用）
    this.prepareDualCurlPixelMaps(currentPairStart, targetPairStart).then(ok => {
      if (!ok || !this.chapter || this.chapter.pages.length === 0) {
        // PixelMap 未准备好，尝试等待加载后重试
        logger.info(TAG, `[双页卷页] PixelMap 未就绪，等待加载后重试...`);
        this.waitForPixelMapsAndRetry(currentPairStart, targetPairStart, isForward);
        return;
      }

      this.startDualCurlAnimationWithPixelMaps(targetPairStart, isForward);
    }).catch((err: Error) => {
      logger.error(TAG, `[双页卷页] 异常: ${err}`);
      this.isPageTurning = false;
      this.fallbackDoublePageTurn(targetPairStart);
    });
  }

  /**
   * 等待 PixelMap 加载完成后重试动画
   * 最多等待 500ms，超时则降级到普通翻页
   */
  private waitForPixelMapsAndRetry(currentPairStart: number, targetPairStart: number, isForward: boolean): void {
    const MAX_WAIT_TIME: number = DOUBLE_CURL_PIXELMAP_WAIT_TIMEOUT_MS;
    const CHECK_INTERVAL: number = 50; // 每 50ms 检查一次
    const startTime: number = Date.now();

    const checkAndRetry = (): void => {
      const elapsed: number = Date.now() - startTime;
      if (elapsed >= MAX_WAIT_TIME) {
        // 超时，降级到普通翻页
        logger.warn(TAG, `[双页卷页] 等待 PixelMap 超时，降级到普通翻页`);
        this.recordReadFlowDegraded(
          null,
          targetPairStart,
          'double_curl_pixelmap_timeout_fallback',
          `currentPair=${currentPairStart}, targetPair=${targetPairStart}, timeoutMs=${MAX_WAIT_TIME}`
        );
        this.isPageTurning = false;
        this.fallbackDoublePageTurn(targetPairStart);
        return;
      }

      // 再次尝试准备 PixelMap
      this.prepareDualCurlPixelMaps(currentPairStart, targetPairStart).then(ok => {
        if (ok) {
          logger.info(TAG, `[双页卷页] PixelMap 已就绪，启动动画`);
          this.recordReadFlowRecovered(
            null,
            targetPairStart,
            'double_curl_pixelmap_ready_after_wait',
            `currentPair=${currentPairStart}, targetPair=${targetPairStart}`
          );
          this.startDualCurlAnimationWithPixelMaps(targetPairStart, isForward);
        } else {
          // 继续等待
          setTimeout(checkAndRetry, CHECK_INTERVAL);
        }
      }).catch(() => {
        setTimeout(checkAndRetry, CHECK_INTERVAL);
      });
    };

    // 立即开始检查
    setTimeout(checkAndRetry, CHECK_INTERVAL);
  }

  /**
   * 使用已准备好的 PixelMap 启动双页卷页动画
   */
  private startDualCurlAnimationWithPixelMaps(targetPairStart: number, isForward: boolean): void {
    this.showDualCurlEffect = true;
    this.dualCurlEffectOpacity = 1.0; // 确保动画开始时完全不透明
    this.dualCurlPendingPairStart = targetPairStart;
    this.dualCurlProgress = 0;
    this.pageTurnDirection = isForward ? 'left' : 'right';
    this.currentAnimationType = PageTurnAnimationType.CURL;

    logger.info(TAG, `[双页卷页] 显示动画层, 延迟启动动画`);

    setTimeout(() => {
      this.animateDualCurlProgressTo(1.0, () => {
        this.onDualCurlAnimationComplete();
      });
    }, 50);
  }

  /**
   * 准备双页卷页所需的 4 张 PixelMap
   * 注意：不进行拷贝，直接从 pagePixelMaps 缓存中获取引用
   */
  private async prepareDualCurlPixelMaps(currentPairStart: number, targetPairStart: number): Promise<boolean> {
    const total: number = this.chapter.pages.length;
    const initialPlan: MangaCurlDualPixelMapPlan = this.createDualCurlPixelMapPlan(
      currentPairStart,
      targetPairStart,
      total
    );
    if (!initialPlan.shouldRun) {
      this.clearDualCurlPixelMapReferences();
      return false;
    }

    for (let i = 0; i < initialPlan.requests.length; i++) {
      const request: MangaCurlPixelMapSlotRequest = initialPlan.requests[i];
      const pixelMap: image.PixelMap | null = await this.resolveCurlPixelMapRequest(request, total);
      this.applyDualCurlPixelMapSlot(request.slot, pixelMap);
    }

    const finalPlan: MangaCurlDualPixelMapPlan = this.createDualCurlPixelMapPlan(
      currentPairStart,
      targetPairStart,
      total
    );
    logger.info(TAG, `[双页卷页] PixelMap准备: L=${this.dualCurlLeftPM !== null}, R=${this.dualCurlRightPM !== null}, NL=${this.dualCurlNextLeftPM !== null}, NR=${this.dualCurlNextRightPM !== null}, turning=${finalPlan.turningReady}`);
    return finalPlan.canStartCurl;
  }

  private createDualCurlPixelMapPlan(
    currentPairStart: number,
    targetPairStart: number,
    total: number
  ): MangaCurlDualPixelMapPlan {
    const input: MangaCurlDualPixelMapInput = new MangaCurlDualPixelMapInput();
    input.currentPairStart = currentPairStart;
    input.targetPairStart = targetPairStart;
    input.pageCount = total;
    input.readingDirection = this.readingSettings.readingDirection;
    input.isForward = this.curlIsForward;
    input.hasCurrentLeft = this.hasPagePixelMap(input.readingDirection === ReadingDirection.RIGHT_TO_LEFT
      ? (currentPairStart + 1 < total ? currentPairStart + 1 : -1)
      : currentPairStart);
    input.hasCurrentRight = this.hasPagePixelMap(input.readingDirection === ReadingDirection.RIGHT_TO_LEFT
      ? currentPairStart
      : (currentPairStart + 1 < total ? currentPairStart + 1 : -1));
    input.hasTargetLeft = this.hasPagePixelMap(input.readingDirection === ReadingDirection.RIGHT_TO_LEFT
      ? (targetPairStart + 1 < total ? targetPairStart + 1 : -1)
      : targetPairStart);
    input.hasTargetRight = this.hasPagePixelMap(input.readingDirection === ReadingDirection.RIGHT_TO_LEFT
      ? targetPairStart
      : (targetPairStart + 1 < total ? targetPairStart + 1 : -1));
    return this.mangaCurlPixelMapResolver.buildDualPlan(input);
  }

  private hasPagePixelMap(pageIndex: number): boolean {
    if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return false;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    return this.pagePixelMaps.has(page.id);
  }

  private async resolveCurlPixelMapRequest(
    request: MangaCurlPixelMapSlotRequest,
    total: number
  ): Promise<image.PixelMap | null> {
    if (request.pageIndex < 0 || request.pageIndex >= total) {
      return null;
    }
    const page: MangaPage = this.chapter.pages[request.pageIndex];
    let pixelMap: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    if (!pixelMap) {
      await this.ensurePixelMapLoaded(page);
      pixelMap = this.pagePixelMaps.get(page.id);
    }
    return pixelMap || null;
  }

  private applyDualCurlPixelMapSlot(slot: MangaCurlPixelMapSlot, pixelMap: image.PixelMap | null): void {
    if (slot === MangaCurlPixelMapSlot.CURRENT_LEFT) {
      this.dualCurlLeftPM = pixelMap;
      return;
    }
    if (slot === MangaCurlPixelMapSlot.CURRENT_RIGHT) {
      this.dualCurlRightPM = pixelMap;
      return;
    }
    if (slot === MangaCurlPixelMapSlot.TARGET_LEFT) {
      this.dualCurlNextLeftPM = pixelMap;
      return;
    }
    if (slot === MangaCurlPixelMapSlot.TARGET_RIGHT) {
      this.dualCurlNextRightPM = pixelMap;
    }
  }

  private clearDualCurlPixelMapReferences(): void {
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;
  }

  /**
   * 双页卷页拖拽进度更新
   */
  private updateDualCurlProgress(deltaX: number): void {
    const halfWidth: number = this.screenWidth / 2;
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const dragForward: boolean = isRTL ? deltaX > 0 : deltaX < 0;
    const dragDistance: number = Math.abs(deltaX);

    const currentPairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    const maxIndex: number = this.chapter.pages.length - 1;
    const nextPairStart: number = dragForward
      ? Math.min(currentPairStart + 2, maxIndex - (maxIndex % 2))
      : Math.max(currentPairStart - 2, 0);
    const canFlip: boolean = dragForward ? nextPairStart > currentPairStart : nextPairStart < currentPairStart;

    if (!canFlip) return;

    this.curlIsForward = dragForward;
    let progress: number = dragDistance / halfWidth;
    progress = Math.max(0, Math.min(0.95, progress));

    const showThreshold: number = 10;
    if (dragDistance > showThreshold) {
      if (!this.showDualCurlEffect) {
        this.dualCurlPendingPairStart = nextPairStart;
        this.isPageTurning = true;
        this.pageTurnDirection = dragForward ? 'left' : 'right';
        this.currentAnimationType = PageTurnAnimationType.CURL;
        this.dualCurlEffectOpacity = 1.0; // 确保拖拽开始时完全不透明
        this.showDualCurlEffect = true;

        // 异步准备 PixelMap
        this.prepareDualCurlPixelMaps(currentPairStart, nextPairStart).then(ok => {
          if (ok) {
            logger.debug(TAG, `双页卷页 PixelMap 准备完成`);
          }
        });
      }

      if (this.showDualCurlEffect) {
        this.dualCurlProgress = progress;
      }
    } else {
      if (this.showDualCurlEffect) {
        this.resetDualCurlState();
      }
    }
  }

  /**
   * 双页卷页完成动画（松手后继续翻到底）
   * @param velocity 脱手速度 (progress/ms)，使动画延续用户的翻页力度；0 = 使用默认时长
   */
  private animateDualCurlToComplete(velocity: number = 0): void {
    this.stopDualCurlAnimation();
    this.animateDualCurlProgressTo(1.0, () => {
      this.onDualCurlAnimationComplete();
    }, velocity);
  }

  /**
   * 双页卷页回弹取消
   */
  private animateDualCurlToCancel(): void {
    this.stopDualCurlAnimation();
    this.animateDualCurlProgressTo(0, () => {
      this.resetDualCurlState();
    });
  }

  /**
   * 双页模式普通翻页（降级）
   */
  private fallbackDoublePageTurn(targetPairStart: number): void {
    logger.warn(TAG, `双页降级翻页: target=${targetPairStart}`);
    this.recordReadFlowDegraded(
      null,
      targetPairStart,
      'double_curl_fallback_to_normal_page_turn',
      `targetPair=${targetPairStart}`
    );
    this.viewCurrentPageIndex = targetPairStart;
    this.currentPageIndex = targetPairStart;
    this.suppressExternalIndex = true;
    this.updateDoublePageIndices();
    this.updateDoublePageDisplay();
    this.preloadDoublePageNeighbors();
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetPairStart);
    }
    setTimeout(() => { this.suppressExternalIndex = false; }, 50);
  }

  /**
   * 动画移动到指定位置
   */
  private animateToPosition(targetX: number, targetY: number): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行位移动画');
      this.translateX = targetX;
      this.translateY = targetY;
      return;
    }

    // 防止微小位移的动画
    const deltaX = Math.abs(this.translateX - targetX);
    const deltaY = Math.abs(this.translateY - targetY);
    if (deltaX < 1 && deltaY < 1) {
      return;
    }

    const animationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
    if (animationType === PageTurnAnimationType.NONE && this.currentScale <= 1.0) {
      this.translateX = targetX;
      this.translateY = targetY;
      return;
    }

    const animateOptions: AnimateParam = {
      duration: 200,
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.translateX = targetX;
      this.translateY = targetY;
    });
  }

  private getDoublePrevOverlayOpacity(): number {
    if (this.isDoublePageVerticalPortraitMode()) {
      return this.getVerticalDoublePagePreviewOpacity('prev');
    }

    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (this.isCommittingPageTurn) {
      if (this.isSoftNonePageTurn()) {
        return 0.0;
      }
      return isRTL ? (this.pageTurnDirection === 'left' ? 1.0 : 0.0) : (this.pageTurnDirection === 'right' ? 1.0 : 0.0);
    }
    const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
    const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
    if (isRTL) {
      return this.translateX < 0 ? progress : 0.0;
    }
    return this.translateX > 0 ? progress : 0.0;
  }

  private getDoubleNextOverlayOpacity(): number {
    if (this.isDoublePageVerticalPortraitMode()) {
      return this.getVerticalDoublePagePreviewOpacity('next');
    }

    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (this.isCommittingPageTurn) {
      if (this.isSoftNonePageTurn()) {
        return 0.0;
      }
      return isRTL ? (this.pageTurnDirection === 'right' ? 1.0 : 0.0) : (this.pageTurnDirection === 'left' ? 1.0 : 0.0);
    }
    const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
    const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
    if (isRTL) {
      return this.translateX > 0 ? progress : 0.0;
    }
    return this.translateX < 0 ? progress : 0.0;
  }


  /**
   * 获取当前页面数据
   */
  private getCurrentPageData(): PageData {
    const idx: number = this.viewCurrentPageIndex;
    if (idx >= 0 && idx < this.chapter.pages.length) {
      const currentPage = this.chapter.pages[idx];
      const loadState = this.imageLoadStates.get(currentPage.id);
      return { page: currentPage, loadState } as PageData;
    }
    return { page: null, loadState: undefined } as PageData;
  }

  /**
   * 获取页面加载状态
   */
  private getPageLoadState(page: MangaPage): ImageLoadState | undefined {
    return this.imageLoadStates.get(page.id);
  }

  private createMangaPageResolveContext(): MangaPageResolveContext {
    const context: MangaPageResolveContext = new MangaPageResolveContext();
    context.chapter = this.chapter;
    context.isWebtoonMode = this.isWebtoonMode();
    context.webtoonDataItems = this.webtoonDataItems;
    context.webtoonPageRefById = this.webtoonPageRefById;
    context.webtoonVisibleItemIndices = this.webtoonVisibleItemIndices;
    context.currentPageIndex = this.viewCurrentPageIndex;
    return context;
  }

  private createMangaAssetLoadContextInput(): MangaAssetLoadContextInput {
    const input: MangaAssetLoadContextInput = new MangaAssetLoadContextInput();
    input.chapter = this.chapter;
    input.webtoonPageRefById = this.webtoonPageRefById;
    input.networkHeaders = this.networkHeaders;
    input.sourceId = this.sourceId;
    input.mangaId = this.mangaId;
    input.contentType = this.contentType;
    input.screenWidth = this.screenWidth > 0 ? this.screenWidth : 1080;
    input.isWebtoonMode = this.isWebtoonMode();
    return input;
  }

  private createMangaPageVisibilityContext(): MangaPageVisibilityContext {
    const context: MangaPageVisibilityContext = new MangaPageVisibilityContext();
    context.chapter = this.chapter;
    context.readingMode = this.readingSettings.readingMode;
    context.isWebtoonMode = this.isWebtoonMode();
    context.leftPageIndex = this.leftPageIndex;
    context.rightPageIndex = this.rightPageIndex;
    context.viewCurrentPageIndex = this.viewCurrentPageIndex;
    context.visiblePageIndices = this.visiblePageIndices;
    context.webtoonVisibleItemIndices = this.webtoonVisibleItemIndices;
    context.webtoonPageRefById = this.webtoonPageRefById;
    return context;
  }

  private createWebtoonPositionContext(): MangaWebtoonPositionContext {
    const context: MangaWebtoonPositionContext = new MangaWebtoonPositionContext();
    context.screenWidth = this.screenWidth > 0 ? this.screenWidth : 360;
    context.pageSpacing = this.readingSettings.pageSpacing || 16;
    context.webtoonLeftMargin = this.readingSettings.webtoonLeftMargin ?? 0;
    context.webtoonRightMargin = this.readingSettings.webtoonRightMargin ?? 0;
    context.isWebtoonMode = this.isWebtoonMode();
    context.zoomScale = this.webtoonZoomScale;
    return context;
  }

  private createLoadedPagePresentationContext(
    visibility: MangaPageVisibilityResult
  ): MangaLoadedPagePresentationContext {
    const context: MangaLoadedPagePresentationContext = new MangaLoadedPagePresentationContext();
    context.readingMode = this.readingSettings.readingMode;
    context.isWebtoonMode = this.isWebtoonMode();
    context.isVisible = visibility.isVisible;
    context.pageIndex = visibility.displayIndex;
    context.currentPageIndex = this.viewCurrentPageIndex;
    context.previousPageIndex = this.getPrevPageIndex();
    context.nextPageIndex = this.getNextPageIndex();
    context.useSmartDoublePageLayout = this.shouldUseSmartDoublePageLayout();
    context.useAlbumNoneTransition = this.shouldUseAlbumNoneTransition();
    context.useSoftNoneCrossfade = this.shouldUseSoftNoneCrossfade();
    context.showSoftTransitionOverlay = this.showSoftTransitionOverlay;
    return context;
  }

  private buildMangaAssetLoadRequest(
    page: MangaPage,
    pageIndex: number,
    reason: MangaAssetLoadReason
  ): MangaAssetLoadRequest {
    const requestContext: MangaAssetRequestContext = this.mangaAssetLoadContextResolver.build(
      page,
      pageIndex,
      reason,
      this.createMangaAssetLoadContextInput()
    );
    return this.mangaAssetRequestFactory.build(page, pageIndex, requestContext);
  }

  private invalidateMangaReaderSession(reason: string): void {
    const chapterId: string = this.chapter && this.chapter.id ? this.chapter.id : '';
    const snapshot: MangaReaderSessionSnapshot = this.mangaReaderSessionGuard.resetForChapter(chapterId, reason);
    this.logMangaAssetMetrics(reason);
    this.mangaAssetLoadCoordinator.clearActiveTasks();
    this.mangaAssetLoadCoordinator.resetMetrics();
    logger.debug(TAG, `漫画阅读会话已失效: reason=${reason}, version=${snapshot.version}, chapter=${snapshot.chapterId}`);
  }

  private captureMangaReaderSession(): MangaReaderSessionSnapshot {
    return this.mangaReaderSessionGuard.capture();
  }

  private isMangaReaderSessionActive(snapshot: MangaReaderSessionSnapshot, page: MangaPage): boolean {
    if (!this.mangaReaderSessionGuard.isCurrent(snapshot)) {
      return false;
    }
    if (!this.chapter || !this.chapter.pages) {
      return false;
    }
    return this.mangaPageLoadResolver.isPageResolvable(page, this.createMangaPageResolveContext());
  }

  private logMangaAssetMetrics(reason: string): void {
    const snapshot: MangaAssetMetricsSnapshot = this.mangaAssetLoadCoordinator.getMetricsSnapshot();
    if (snapshot.totalRequests <= 0 &&
      snapshot.completedRequests <= 0 &&
      snapshot.failedRequests <= 0 &&
      snapshot.dedupedRequests <= 0) {
      this.logMangaReaderCacheSnapshot(reason);
      return;
    }
    logger.performance(TAG, `manga_asset_${reason}_requests`, snapshot.totalRequests, 'count');
    logger.performance(TAG, `manga_asset_${reason}_completed`, snapshot.completedRequests, 'count');
    logger.performance(TAG, `manga_asset_${reason}_failed`, snapshot.failedRequests, 'count');
    logger.performance(TAG, `manga_asset_${reason}_deduped`, snapshot.dedupedRequests, 'count');
    logger.performance(TAG, `manga_asset_${reason}_avg_elapsed`, snapshot.averageElapsedMs, 'ms');
    this.logMangaReaderCacheSnapshot(reason);
  }

  private createMangaReaderCacheSnapshotInput(reason: string): MangaReaderCacheSnapshotInput {
    const localStats: CacheStats = this.localImageCache.getStats();
    const preloadDebugInfo: PreloadDebugInfo = this.preloadManager.getDebugInfo();
    const loadStats: LoadStatsInfo = this.imageLoadStateManager.getStats();
    const input: MangaReaderCacheSnapshotInput = new MangaReaderCacheSnapshotInput();
    input.reason = reason;
    input.pagePixelMapCount = this.pagePixelMaps.size;
    input.pagePixelMapMetaCount = this.pagePixelMapMeta.size;
    input.pixelMapEpochCount = this.pixelMapEpochByPage.size;
    input.reactiveImageLoadStateCount = this.imageLoadStates.size;
    input.legacyImageMetaCount = this.imageCache.size;
    input.legacyImageMetaBytes = this.imageCacheSize;
    input.legacyImageMetaMaxBytes = this.MAX_CACHE_SIZE;
    input.preloadedImageCount = this.preloadedImages.size;
    input.localCacheCount = localStats.count;
    input.localCacheBytes = localStats.size;
    input.localCacheMaxBytes = localStats.maxSize;
    input.preloadQueueCount = preloadDebugInfo.queueItems.length;
    input.preloadCompletedCount = preloadDebugInfo.completedCount;
    input.preloadFailedCount = preloadDebugInfo.failedCount;
    input.preloadMemCacheHits = preloadDebugInfo.memCacheHits;
    input.preloadDiskCacheHits = preloadDebugInfo.diskCacheHits;
    input.preloadNetworkLoads = preloadDebugInfo.networkLoads;
    input.managedLoadStateTotal = loadStats.total;
    input.managedLoadStateIdle = loadStats.idle;
    input.managedLoadStateLoading = loadStats.loading;
    input.managedLoadStateCompleted = loadStats.completed;
    input.managedLoadStateError = loadStats.error;
    input.warmupState = this.onlineDownloadedWarmupState ? this.onlineDownloadedWarmupState : '';
    input.archivePath = this.onlineDownloadedArchivePath ? this.onlineDownloadedArchivePath : '';
    input.extractDir = this.onlineDownloadedExtractDir ? this.onlineDownloadedExtractDir : '';
    input.reusedExtract = this.onlineDownloadedReusedExtract;
    input.archivePageCount = this.onlineDownloadedArchivePageCount;
    input.networkPageCount = this.onlineDownloadedNetworkPageCount;
    return input;
  }

  private logMangaReaderCacheOwnershipOnce(): void {
    if (this.mangaReaderCacheOwnershipLogged) {
      return;
    }
    const items: MangaReaderCacheOwnershipItem[] = this.mangaReaderCacheMonitor.createOwnershipItems();
    for (let i = 0; i < items.length; i++) {
      const item: MangaReaderCacheOwnershipItem = items[i];
      logger.debug(TAG, `漫画缓存归属: owner=${item.owner}, name=${item.name}, responsibility=${item.responsibility}, release=${item.releasePolicy}`);
    }
    this.mangaReaderCacheOwnershipLogged = true;
  }

  private logMangaReaderCacheSnapshot(reason: string): void {
    this.logMangaReaderCacheOwnershipOnce();
    const snapshot: MangaReaderCacheSnapshot = this.mangaReaderCacheMonitor.createSnapshot(
      this.createMangaReaderCacheSnapshotInput(reason)
    );
    if (!snapshot.hasActivity) {
      return;
    }
    logger.debug(TAG, this.mangaReaderCacheMonitor.describe(snapshot));
    logger.performance(TAG, `manga_cache_${reason}_active_pixel_maps`, snapshot.pagePixelMapCount, 'count');
    logger.performance(TAG, `manga_cache_${reason}_local_lru_count`, snapshot.localCacheCount, 'count');
    logger.performance(TAG, `manga_cache_${reason}_local_lru_bytes`, snapshot.localCacheBytes, 'bytes');
    logger.performance(TAG, `manga_cache_${reason}_legacy_meta_count`, snapshot.legacyImageMetaCount, 'count');
    logger.performance(TAG, `manga_cache_${reason}_legacy_meta_bytes`, snapshot.legacyImageMetaBytes, 'bytes');
    logger.performance(TAG, `manga_cache_${reason}_preload_queue`, snapshot.preloadQueueCount, 'count');
    logger.performance(TAG, `manga_cache_${reason}_load_states`, snapshot.managedLoadStateTotal, 'count');
    if (snapshot.hasLegacyMetaPressure) {
      logger.warn(TAG, `旧图片元信息缓存接近阈值: size=${snapshot.legacyImageMetaBytes}, max=${snapshot.legacyImageMetaMaxBytes}`);
    }
    if (snapshot.hasLocalCachePressure) {
      logger.warn(TAG, `本地图片LRU缓存接近阈值: size=${snapshot.localCacheBytes}, max=${snapshot.localCacheMaxBytes}`);
    }
    if (snapshot.hasSplitPixelMapOwnership) {
      logger.warn(TAG, `PixelMap双缓存运行态: active=${snapshot.pagePixelMapCount}, local=${snapshot.localCacheCount}`);
    }
    this.recordReadFlowCacheSnapshot(reason, snapshot);
  }

  private getReadFlowSessionId(): string {
    return this.resolveReadFlowSession().sessionId;
  }

  private resolveReadFlowSession(): MangaReadFlowSessionBridgeResult {
    const context: MangaReadFlowSessionBridgeContext = new MangaReadFlowSessionBridgeContext();
    context.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    context.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    context.contentId = this.mangaId ? this.mangaId : '';
    context.contentTitle = this.chapter ? this.chapter.title : '';
    context.chapterId = this.chapter ? this.chapter.id : '';
    context.chapterTitle = this.chapter ? this.chapter.title : '';
    context.pageIndex = this.viewCurrentPageIndex;
    context.pageCount = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    context.detail = `contentType=${this.contentType}, chapterTick=${this.chapterTick}`;
    return this.mangaReadFlowSessionBridge.resolve(this.readFlowSessionId, context);
  }

  private mapViewerContentTypeToReadFlowSourceKind(): MangaReadFlowSourceKind {
    if (this.contentType === 'OnlineUndownloaded') {
      return MangaReadFlowSourceKind.ONLINE_UNDOWNLOADED;
    }
    if (this.contentType === 'OnlineDownloaded') {
      return MangaReadFlowSourceKind.ONLINE_DOWNLOADED;
    }
    if (this.contentType === 'Suwayomi') {
      return MangaReadFlowSourceKind.SUWAYOMI;
    }
    if (this.contentType === 'Komga') {
      return MangaReadFlowSourceKind.KOMGA;
    }
    if (this.contentType === 'ebook') {
      return MangaReadFlowSourceKind.EBOOK_IMAGE;
    }
    return MangaReadFlowSourceKind.LOCAL;
  }

  private recordReadFlowEvent(
    eventType: MangaReadFlowEventType,
    page: MangaPage | null,
    pageIndex: number,
    reason: string,
    detail: string
  ): void {
    const sessionResult: MangaReadFlowSessionBridgeResult = this.resolveReadFlowSession();
    if (!sessionResult.valid) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      sessionResult.sessionId,
      eventType,
      this.mangaId ? this.mangaId : '',
      this.chapter ? this.chapter.id : '',
      pageIndex,
      reason
    );
    event.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    event.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    event.chapterTitle = this.chapter ? this.chapter.title : '';
    event.pageId = page ? page.id : '';
    event.pageCount = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    event.detail = detail;
    this.mangaReadFlowMonitor.record(event);
  }

  private notifyFirstVisibleDisplayCommitted(page: MangaPage, pageIndex: number): void {
    if (this.firstVisibleDisplayCommitted) {
      return;
    }
    if (!this.isPageCurrentlyVisible(page)) {
      return;
    }
    this.firstVisibleDisplayCommitted = true;
    if (this.callbacks.onFirstVisibleDisplayCommitted) {
      this.callbacks.onFirstVisibleDisplayCommitted(pageIndex, page.id, page.sourceType);
    }
  }

  private recordReadFlowAssetEvent(
    eventType: MangaReadFlowEventType,
    page: MangaPage,
    pageIndex: number,
    reason: string,
    elapsedMs: number,
    success: boolean,
    assetSource: string,
    errorMessage: string
  ): void {
    const sessionResult: MangaReadFlowSessionBridgeResult = this.resolveReadFlowSession();
    if (!sessionResult.valid) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      sessionResult.sessionId,
      eventType,
      this.mangaId ? this.mangaId : '',
      this.chapter ? this.chapter.id : '',
      pageIndex,
      reason
    );
    event.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    event.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    event.chapterTitle = this.chapter ? this.chapter.title : '';
    event.pageId = page.id;
    event.pageCount = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    event.elapsedMs = elapsedMs;
    event.success = success;
    event.assetSource = assetSource;
    event.errorMessage = errorMessage;
    event.severity = success ? MangaReadFlowSeverity.DEBUG : MangaReadFlowSeverity.ERROR;
    event.detail = `sourceType=${page.sourceType}, asset=${assetSource}`;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordReadFlowCacheSnapshot(reason: string, snapshot: MangaReaderCacheSnapshot): void {
    const sessionResult: MangaReadFlowSessionBridgeResult = this.resolveReadFlowSession();
    if (!sessionResult.valid) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      sessionResult.sessionId,
      MangaReadFlowEventType.CACHE_SNAPSHOT,
      this.mangaId ? this.mangaId : '',
      this.chapter ? this.chapter.id : '',
      this.viewCurrentPageIndex,
      reason
    );
    event.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    event.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    event.metricName = 'manga_read_flow_cache_active_pixel_maps';
    event.metricValue = snapshot.pagePixelMapCount;
    event.metricUnit = 'count';
    event.detail = `activePM=${snapshot.pagePixelMapCount}, localLRU=${snapshot.localCacheCount}, loading=${snapshot.managedLoadStateLoading}, error=${snapshot.managedLoadStateError}, warmupState=${snapshot.warmupState}, archivePath=${snapshot.archivePath}, extractDir=${snapshot.extractDir}, reusedExtract=${snapshot.reusedExtract}, pageCount=${snapshot.archivePageCount}, networkPageCount=${snapshot.networkPageCount}`;
    event.severity = snapshot.hasLegacyMetaPressure || snapshot.hasLocalCachePressure || snapshot.hasSplitPixelMapOwnership
      ? MangaReadFlowSeverity.WARN
      : MangaReadFlowSeverity.DEBUG;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordReadFlowStatus(
    eventType: MangaReadFlowEventType,
    page: MangaPage | null,
    pageIndex: number,
    reason: string,
    detail: string,
    severity: MangaReadFlowSeverity,
    success: boolean
  ): void {
    const sessionResult: MangaReadFlowSessionBridgeResult = this.resolveReadFlowSession();
    if (!sessionResult.valid) {
      return;
    }
    const event: MangaReadFlowEvent = this.mangaReadFlowMonitor.createEvent(
      sessionResult.sessionId,
      eventType,
      this.mangaId ? this.mangaId : '',
      this.chapter ? this.chapter.id : '',
      pageIndex,
      reason
    );
    event.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    event.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    event.chapterTitle = this.chapter ? this.chapter.title : '';
    event.pageId = page ? page.id : '';
    event.pageCount = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    event.detail = detail;
    event.severity = severity;
    event.success = success;
    this.mangaReadFlowMonitor.record(event);
  }

  private recordReadFlowDegraded(page: MangaPage | null, pageIndex: number, reason: string, detail: string): void {
    this.recordReadFlowStatus(
      MangaReadFlowEventType.FLOW_DEGRADED,
      page,
      pageIndex,
      reason,
      detail,
      MangaReadFlowSeverity.WARN,
      true
    );
  }

  private recordReadFlowRecovered(page: MangaPage | null, pageIndex: number, reason: string, detail: string): void {
    this.recordReadFlowStatus(
      MangaReadFlowEventType.FLOW_RECOVERED,
      page,
      pageIndex,
      reason,
      detail,
      MangaReadFlowSeverity.INFO,
      true
    );
  }

  private recordReadFlowGuardRejected(page: MangaPage | null, pageIndex: number, reason: string, detail: string): void {
    this.recordReadFlowStatus(
      MangaReadFlowEventType.FLOW_GUARD_REJECTED,
      page,
      pageIndex,
      reason,
      detail,
      MangaReadFlowSeverity.WARN,
      true
    );
  }

  private createScrollableReadFlowContext(chapterId: string, pageIndex: number): MangaScrollableReadFlowContext {
    const context: MangaScrollableReadFlowContext = new MangaScrollableReadFlowContext();
    const sessionResult: MangaReadFlowSessionBridgeResult = this.resolveReadFlowSession();
    if (!sessionResult.valid) {
      return context;
    }
    context.sessionId = sessionResult.sessionId;
    context.sourceKind = this.mapViewerContentTypeToReadFlowSourceKind();
    context.modeKind = mapReadingModeToFlowMode(this.readingSettings.readingMode);
    context.contentId = this.mangaId ? this.mangaId : '';
    context.chapterId = chapterId.length > 0 ? chapterId : (this.chapter ? this.chapter.id : '');
    context.chapterTitle = this.getChapterTitleById(context.chapterId);
    if (context.chapterTitle.length <= 0 && this.chapter) {
      context.chapterTitle = this.chapter.title;
    }
    context.pageIndex = pageIndex;
    context.pageCount = this.getScrollableReadFlowPageCount(context.chapterId);
    return context;
  }

  private getScrollableReadFlowPageCount(chapterId: string): number {
    if (!chapterId || !this.chapter) {
      return this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    }
    if (this.chapter.id === chapterId) {
      return this.chapter.pages ? this.chapter.pages.length : 0;
    }
    if (this.prevChapter && this.prevChapter.id === chapterId) {
      return this.prevChapter.pages ? this.prevChapter.pages.length : 0;
    }
    if (this.nextChapter && this.nextChapter.id === chapterId) {
      return this.nextChapter.pages ? this.nextChapter.pages.length : 0;
    }
    const boundary: ChapterBoundary | undefined = this.findChapterBoundary(this.chapterBoundaries, chapterId);
    if (boundary) {
      return Math.max(0, boundary.endIndex - boundary.startIndex + 1);
    }
    return this.chapter.pages ? this.chapter.pages.length : 0;
  }

  private recordScrollableReadFlow(
    eventType: MangaReadFlowEventType,
    chapterId: string,
    pageIndex: number,
    reason: string,
    detail: string,
    severity: MangaReadFlowSeverity
  ): void {
    const context: MangaScrollableReadFlowContext = this.createScrollableReadFlowContext(chapterId, pageIndex);
    this.mangaScrollableReadFlowReporter.record(context, eventType, reason, detail, severity);
  }

  private async loadPixelMapWithAssetPipeline(
    page: MangaPage,
    pageIndex: number,
    reason: MangaAssetLoadReason
  ): Promise<MangaAssetLoadResult> {
    this.mangaAssetLoadCoordinator.setPixivImageLoader(this.loadPixivImageCallback ? this.loadPixivImageCallback : null);
    const request: MangaAssetLoadRequest = this.buildMangaAssetLoadRequest(page, pageIndex, reason);
    this.recordReadFlowAssetEvent(
      MangaReadFlowEventType.ASSET_REQUEST,
      page,
      pageIndex,
      reason,
      0,
      true,
      String(page.sourceType),
      ''
    );
    return await this.mangaAssetLoadCoordinator.load(request);
  }

  private resolveAssetLoadReason(page: MangaPage): MangaAssetLoadReason {
    if (this.mangaPageVisibilityResolver.isPageVisible(page, this.createMangaPageVisibilityContext())) {
      return this.isWebtoonMode() ? MangaAssetLoadReason.WEBTOON : MangaAssetLoadReason.VISIBLE;
    }
    return MangaAssetLoadReason.PRELOAD;
  }

  private resolveManagedPageIndex(page: MangaPage, fallbackIndex: number = -1): number {
    return this.mangaPageLoadResolver.resolveManagedPageIndex(
      page,
      fallbackIndex,
      this.createMangaPageResolveContext()
    );
  }

  private markPagePixelMapLoaded(page: MangaPage, pixelMap: image.PixelMap): void {
    this.commitPagePixelMap(page.id, pixelMap);
    this.incrementPixelMapEpoch(page.id);
    const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
    const newState: ImageLoadState = {
      isLoading: false,
      isLoaded: true,
      dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
      error: undefined
    } as ImageLoadState;
    this.imageLoadStates.set(page.id, newState);
    this.imageLoadStates = new Map(this.imageLoadStates);
    this.clearPendingLoadTimer(page.id);
    this.notifyPixelMapLoaded(page);
    this.recordReadFlowEvent(
      MangaReadFlowEventType.DISPLAY_COMMITTED,
      page,
      this.resolveManagedPageIndex(page),
      this.isPageCurrentlyVisible(page) ? 'visible_pixelmap_ready' : 'preload_pixelmap_ready',
      'pixel_map_committed'
    );
    this.notifyFirstVisibleDisplayCommitted(page, this.resolveManagedPageIndex(page));
  }

  private markPagePixelMapLoadFailed(page: MangaPage, errorMessage: string): void {
    const st: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
    if (st) {
      st.isLoading = false;
      st.isLoaded = false;
      st.error = errorMessage;
      this.imageLoadStates.set(page.id, st);
    } else {
      this.imageLoadStates.set(page.id, {
        isLoading: false,
        isLoaded: false,
        error: errorMessage
      } as ImageLoadState);
    }
    this.imageLoadStates = new Map(this.imageLoadStates);
    this.clearPendingLoadTimer(page.id);
    this.recordReadFlowAssetEvent(
      MangaReadFlowEventType.ASSET_LOADED,
      page,
      this.resolveManagedPageIndex(page),
      this.isPageCurrentlyVisible(page) ? 'visible' : 'preload',
      0,
      false,
      'failed_state',
      errorMessage
    );
  }

  private isPagePixelMapUsable(pageId: string): boolean {
    return this.mangaPixelMapLifecycleManager.isUsable(this.pagePixelMaps, pageId);
  }

  private clearPendingLoadTimer(pageId: string): void {
    const timerId: number | undefined = this.pendingLoadTimers.get(pageId);
    if (typeof timerId === 'number') {
      clearTimeout(timerId);
    }
    this.pendingLoadTimers.delete(pageId);
  }

  private dropPagePixelMapReference(pageId: string, releasePixelMap: boolean): void {
    const result: MangaPixelMapLifecycleResult = this.mangaPixelMapLifecycleManager.dropReference(
      this.pagePixelMaps,
      this.pagePixelMapMeta,
      this.pixelMapEpochByPage,
      pageId,
      releasePixelMap
    );
    if (result.changed) {
      this.pagePixelMaps = new Map(this.pagePixelMaps);
      this.pixelMapEpochByPage = new Map(this.pixelMapEpochByPage);
    }
  }

  private refreshVisibleDisplayForPage(page: MangaPage): void {
    if (this.isWebtoonMode()) {
      const dataIndex: number = this.findWebtoonDataIndex(page.id);
      if (dataIndex >= 0) {
        this.webtoonDataSource.notifyDataChange(dataIndex);
      }
      return;
    }

    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageDisplay();
      return;
    }

    this.updateSinglePageDisplay();
  }

  private handleImageComponentError(page: MangaPage, error: ImageError, context: string): void {
    this.logDetailedImageError(page, error);
    this.clearPendingLoadTimer(page.id);

    if (this.isPagePixelMapUsable(page.id)) {
      logger.warn(TAG, `忽略显示层图片错误，PixelMap仍有效: context=${context}, id=${page.id}`);
      return;
    }

    if (page.sourceType === ImageSourceType.NETWORK) {
      if (this.pagePixelMaps.has(page.id)) {
        this.dropPagePixelMapReference(page.id, true);
      }

      const managedPageIndex: number = this.resolveManagedPageIndex(page);
      this.imageLoadStateManager.clearPage(page.id);
      this.imageLoadStateManager.initPage(page.id, managedPageIndex >= 0 ? managedPageIndex : 0);

      const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
      const resetState: ImageLoadState = {
        isLoading: false,
        isLoaded: false,
        dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
        error: undefined
      } as ImageLoadState;
      this.imageLoadStates.set(page.id, resetState);
      this.imageLoadStates = new Map(this.imageLoadStates);

      if (this.isPageCurrentlyVisible(page)) {
        logger.warn(TAG, `显示层图片错误，已清理失效PixelMap并重新加载: context=${context}, id=${page.id}`);
        this.recordReadFlowAssetEvent(
          MangaReadFlowEventType.ERROR,
          page,
          managedPageIndex,
          context,
          0,
          false,
          'image_component_retry',
          '显示层图片错误，触发网络图重载'
        );
        this.loadImage(page);
        this.refreshVisibleDisplayForPage(page);
      } else {
        logger.debug(TAG, `忽略不可见页面显示错误，等待下次可见时重载: context=${context}, id=${page.id}`);
        this.recordReadFlowAssetEvent(
          MangaReadFlowEventType.ERROR,
          page,
          managedPageIndex,
          context,
          0,
          false,
          'image_component_deferred',
          '不可见页面显示错误，延迟重载'
        );
      }
      return;
    }

    const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
    const newState: ImageLoadState = {
      isLoading: false,
      isLoaded: false,
      dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
      error: '图片加载失败'
    } as ImageLoadState;
    this.imageLoadStates.set(page.id, newState);
    this.imageLoadStates = new Map(this.imageLoadStates);
    this.logImageDisplayAfter(page, false);
    this.recordReadFlowAssetEvent(
      MangaReadFlowEventType.ERROR,
      page,
      this.resolveManagedPageIndex(page),
      context,
      0,
      false,
      'image_component',
      '图片加载失败'
    );
  }

  /**
   * 计算并更新双页模式的左右页索引。
   * 新规则：采用正确的双页配对逻辑，支持平滑单页翻页
   * - 左页显示偶数索引页面，右页显示奇数索引页面
   * - currentPageIndex指向当前"活动"页面，用于翻页控制
   * - 支持从左到右(LTR)、从右到左(RTL)和从上到下(TTB)三种阅读方向
   */
  private updateDoublePageIndices(): void {
    if (this.readingSettings.readingMode !== ReadingMode.DOUBLE_PAGE || !this.chapter || !this.chapter.pages) {
      this.leftPageIndex = -1;
      this.rightPageIndex = -1;
      this.currentDoublePageDisplayMode = DoublePageSmartDisplayMode.DUAL;
      this.currentDoublePageDisplayReason = DoublePageSmartDisplayReason.NORMAL_PAIR;
      return;
    }

    const total: number = this.chapter.pages.length;
    const current: number = Math.min(Math.max(0, this.viewCurrentPageIndex), total - 1);
    const isVerticalPortrait: boolean = this.isDoublePageVerticalPortraitMode();
    const isRTL: boolean = !isVerticalPortrait &&
      this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;

    const prevLeft: number = this.leftPageIndex;
    const prevRight: number = this.rightPageIndex;

    if (isVerticalPortrait) {
      const pairStart: number = current - (current % 2);
      this.leftPageIndex = pairStart;
      this.rightPageIndex = (pairStart + 1 < total) ? pairStart + 1 : -1;
      this.currentDoublePageDisplayMode = DoublePageSmartDisplayMode.DUAL;
      this.currentDoublePageDisplayReason = (pairStart + 1 < total)
        ? DoublePageSmartDisplayReason.NORMAL_PAIR
        : DoublePageSmartDisplayReason.TAIL_PAGE;
    } else {
      const currentPlan: DoublePageSmartDisplayPlan = this.resolveDoublePageSmartPlanForIndex(current);
      this.leftPageIndex = currentPlan.leftPageIndex;
      this.rightPageIndex = currentPlan.rightPageIndex;
      this.currentDoublePageDisplayMode = currentPlan.mode;
      this.currentDoublePageDisplayReason = currentPlan.reason;
    }

    const leftState: ImageLoadState | undefined = (this.leftPageIndex >= 0 && this.leftPageIndex < total)
      ? this.getPageLoadState(this.chapter.pages[this.leftPageIndex])
      : undefined;
    const rightState: ImageLoadState | undefined = (this.rightPageIndex >= 0 && this.rightPageIndex < total)
      ? this.getPageLoadState(this.chapter.pages[this.rightPageIndex])
      : undefined;

    const directionLabel: string = isVerticalPortrait
      ? `VERTICAL_${this.getDoublePageVerticalDirection()}`
      : `${isRTL ? 'RTL' : 'LTR'}_${this.currentDoublePageDisplayMode}_${this.currentDoublePageDisplayReason}`;
    logger.debug(TAG, `双页索引更新: 方向=${directionLabel}, left=${this.leftPageIndex}(${leftState?.isLoaded ? 'loaded' : leftState?.isLoading ? 'loading' : 'idle'}), right=${this.rightPageIndex}(${rightState?.isLoaded ? 'loaded' : rightState?.isLoading ? 'loading' : 'idle'}), current=${this.viewCurrentPageIndex}`);

    // 加载触发由组件onAppear完成，避免非可视页面提前进入超时逻辑
    const pairChanged: boolean = (prevLeft !== this.leftPageIndex) || (prevRight !== this.rightPageIndex);
    if (pairChanged) {
      this.ensureDoublePageImagesPreloaded();
      setTimeout(() => {
        this.renderEpoch = this.renderEpoch + 1;
        if (this.isDoublePageVerticalPortraitMode()) {
          this.updateVerticalDoublePageRenderSlots();
        }
      }, 0);
    }
    this.updateDoublePageDisplay();
    this.cleanupInvisiblePixelMaps();
  }

  private preloadDoublePageNeighbors(): void {
    if (this.readingSettings.readingMode !== ReadingMode.DOUBLE_PAGE) {
      return;
    }
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    if (this.isDoublePageVerticalPortraitMode()) {
      const maxIndex: number = this.chapter.pages.length - 1;
      const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
      const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
      const prevPairStart: number = Math.max(pairStart - 2, 0);
      const preloadPairStarts: number[] = [];
      if (prevPairStart < pairStart) {
        preloadPairStarts.push(prevPairStart);
      }
      if (nextPairStart > pairStart) {
        preloadPairStarts.push(nextPairStart);
      }
      for (let pairIndex = 0; pairIndex < preloadPairStarts.length; pairIndex++) {
        const preloadPairStart: number = preloadPairStarts[pairIndex];
        for (let i = preloadPairStart; i <= preloadPairStart + 1; i++) {
          if (i >= 0 && i < this.chapter.pages.length) {
            const page: MangaPage = this.chapter.pages[i];
            const st: ImageLoadState | undefined = this.getPageLoadState(page);
            const hasPm: boolean = this.pagePixelMaps.has(page.id);
            if (!hasPm && (!st || !st.isLoading)) {
              this.loadImage(page);
            }
          }
        }
      }
      return;
    }

    const previousPlan: DoublePageSmartDisplayPlan = this.resolvePreviousDoublePageSmartPlan(this.viewCurrentPageIndex);
    const nextPlan: DoublePageSmartDisplayPlan = this.resolveNextDoublePageSmartPlan(this.viewCurrentPageIndex);
    const preloadIndices: number[] = [];
    if (previousPlan.leftPageIndex >= 0) {
      preloadIndices.push(previousPlan.leftPageIndex);
    }
    if (previousPlan.rightPageIndex >= 0) {
      preloadIndices.push(previousPlan.rightPageIndex);
    }
    if (nextPlan.leftPageIndex >= 0) {
      preloadIndices.push(nextPlan.leftPageIndex);
    }
    if (nextPlan.rightPageIndex >= 0) {
      preloadIndices.push(nextPlan.rightPageIndex);
    }

    for (let i = 0; i < preloadIndices.length; i++) {
      const pageIndex: number = preloadIndices[i];
      if (pageIndex >= 0 && pageIndex < this.chapter.pages.length) {
        const page: MangaPage = this.chapter.pages[pageIndex];
        const st: ImageLoadState | undefined = this.getPageLoadState(page);
        const hasPm: boolean = this.pagePixelMaps.has(page.id);
        if (!hasPm && (!st || !st.isLoading)) {
          this.loadImage(page);
        }
      }
    }
  }

  /**
   * 确保双页模式当前显示的左右页图片已进入加载流程（若尚未加载或未在加载中）。
   * 优化：等待左右页都加载完成后再刷新UI，避免多次刷新
   */
  private ensureDoublePageImagesPreloaded(): void {
    if (!this.chapter || !this.chapter.pages) {
      logger.error(TAG, '章节数据为空，无法确保双页图片预加载');
      return;
    }

    const total: number = this.chapter.pages.length;
    const loadPromises: Promise<void>[] = [];

    if (this.leftPageIndex >= 0 && this.leftPageIndex < total) {
      const leftPage: MangaPage = this.chapter.pages[this.leftPageIndex];
      const leftState: ImageLoadState | undefined = this.getPageLoadState(leftPage);
      const hasPmLeft: boolean = this.pagePixelMaps.has(leftPage.id);
      const needLoadLeft: boolean = !hasPmLeft && (!leftState || !leftState.isLoading);
      if (needLoadLeft) {
        logger.debug(TAG, `双页预加载（左页）: index=${this.leftPageIndex}, id=${leftPage.id}, src=${String(this.getImageResource(leftPage))}`);
        loadPromises.push(this.ensurePixelMapLoaded(leftPage));
      }
    }

    if (this.rightPageIndex >= 0 && this.rightPageIndex < total) {
      const rightPage: MangaPage = this.chapter.pages[this.rightPageIndex];
      const rightState: ImageLoadState | undefined = this.getPageLoadState(rightPage);
      const hasPmRight: boolean = this.pagePixelMaps.has(rightPage.id);
      const needLoadRight: boolean = !hasPmRight && (!rightState || !rightState.isLoading);
      if (needLoadRight) {
        logger.debug(TAG, `双页预加载（右页）: index=${this.rightPageIndex}, id=${rightPage.id}, src=${String(this.getImageResource(rightPage))}`);
        loadPromises.push(this.ensurePixelMapLoaded(rightPage));
      }
    }

    // 等待所有页面加载完成后刷新UI
    if (loadPromises.length > 0) {
      Promise.all(loadPromises)
        .then(() => {
          logger.info(TAG, `双页图片加载完成，刷新UI: left=${this.leftPageIndex}, right=${this.rightPageIndex}`);
          this.updateDoublePageDisplay();
        })
        .catch((error: Error) => {
          logger.error(TAG, `双页图片加载失败: ${String(error)}`);
        });
    }
  }

  /**
   * 监听阅读设置变化：模式或方向改变时，重新计算双页索引
   */
  private getReadingSettingsSideEffectKey(): string {
    const mode: string = this.readingSettings.readingMode.toString();
    const direction: string = this.readingSettings.readingDirection.toString();
    const spacing: number = this.readingSettings.pageSpacing !== undefined ? this.readingSettings.pageSpacing : 16;
    const portraitLayout: string = (this.readingSettings.doublePagePortraitLayout || DoublePagePortraitLayout.VERTICAL).toString();
    const webtoonLeftMargin: number = this.readingSettings.webtoonLeftMargin !== undefined ? this.readingSettings.webtoonLeftMargin : 0;
    const webtoonRightMargin: number = this.readingSettings.webtoonRightMargin !== undefined ? this.readingSettings.webtoonRightMargin : 0;
    return `${mode}_${direction}_${spacing}_${portraitLayout}_${webtoonLeftMargin}_${webtoonRightMargin}`;
  }

  private onReadingSettingsChange(): void {
    const sideEffectKey: string = this.getReadingSettingsSideEffectKey();
    if (sideEffectKey === this.lastReadingSettingsSideEffectKey) {
      logger.debug(TAG, `忽略重复阅读设置副作用: mode=${this.readingSettings.readingMode.toString()}, direction=${this.readingSettings.readingDirection.toString()}`);
      return;
    }
    this.lastReadingSettingsSideEffectKey = sideEffectKey;
    this.invalidateWebtoonPositionCache();

    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageIndices();
      if (this.isDoublePageVerticalPortraitMode()) {
        this.syncVerticalDoublePagePositionForCurrentPair(false);
      }
    } else if (this.isContinuousScrollMode()) {
      this.leftPageIndex = -1;
      this.rightPageIndex = -1;
      this.currentWebtoonPage = this.viewCurrentPageIndex;
      this.visiblePageIndices = [this.viewCurrentPageIndex];
      this.updateContinuousHorizontalDataSourceIfNeeded();
      this.triggerUnifiedPreload();
      setTimeout(() => {
        this.jumpToPageImmediate(this.viewCurrentPageIndex);
      }, 0);
    } else if (this.isWebtoonMode()) {
      // [修复] 切换到条漫模式时，初始化多章节数据
      // 这是解决从单页模式切换到条漫模式后无法触发章节切换的关键
      logger.info(TAG, `切换到条漫模式，初始化多章节数据`);
      // 重置条漫状态
      this.prevChapterRequested = false;
      this.nextChapterRequested = false;
      this.isPrevChapterLoading = false;
      this.isNextChapterLoading = false;
      // 初始化多章节数据
      this.initWebtoonMultiChapterData();
      // 重置双页索引
      this.leftPageIndex = -1;
      this.rightPageIndex = -1;
    } else {
      // 非双页模式重置索引，避免残留
      this.leftPageIndex = -1;
      this.rightPageIndex = -1;
      this.currentDoublePageDisplayMode = DoublePageSmartDisplayMode.DUAL;
      this.currentDoublePageDisplayReason = DoublePageSmartDisplayReason.NORMAL_PAIR;
      this.updateSinglePageDisplay();
      this.updateSinglePagePreview();
      this.loadCurrentAndNeighborPages();
    }
    logger.debug(TAG, `阅读设置变更: mode=${this.readingSettings.readingMode.toString()}, direction=${this.readingSettings.readingDirection.toString()}`);
  }

  /**
   * 处理单页模式滑动手势
   */
  private handleSinglePageSwipe(event: GestureEvent): void {
    // 使用新的统一预加载方法
    this.triggerUnifiedPreload();
    const swipeDirection = event.angle || 0;
    const swipeSpeed = Math.abs(event.speed || 0);

    // 滑动速度阈值
    const SPEED_THRESHOLD = 100;
    if (swipeSpeed < SPEED_THRESHOLD) {
      return;
    }

    logger.debug(TAG, `单页滑动手势: angle=${swipeDirection}, speed=${swipeSpeed}`);

    // 判断阅读方向：当 readingMode 为 SINGLE_PAGE 时依据 readingDirection
    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    const isTTB: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM);

    if (isTTB) {
      // 上下翻页模式：使用垂直角度判断
      // 约定：-90°（上滑） -> 下一页； +90°（下滑） -> 上一页
      const isSwipeUp: boolean = swipeDirection <= -45 && swipeDirection >= -135;
      const isSwipeDown: boolean = swipeDirection >= 45 && swipeDirection <= 135;

      if (isSwipeDown) {
        // 下滑：上一页
        if (this.viewCurrentPageIndex > 0) {
          const newIndex: number = this.viewCurrentPageIndex - 1;
          this.viewCurrentPageIndex = newIndex;
          this.currentPageIndex = newIndex;
          this.suppressExternalIndex = true;
          // 条漫模式使用统一的预加载方法
          if (this.isWebtoonMode()) {
            this.triggerWebtoonPreload();
          }
          const newPage: MangaPage = this.chapter.pages[newIndex];
          this.updateSinglePageDisplay();
          this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
          this.incrementPixelMapEpoch(newPage.id);
          this.pageImageBindings.set(newIndex, newPage.id);
          this.pageImageBindings = new Map(this.pageImageBindings);
          this.renderEpoch = this.renderEpoch + 1;
          this.translateX = 0;
          this.translateY = 0;
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
          setTimeout(() => { this.suppressExternalIndex = false; }, 0);
          this.pageChangeCommitted = true;
          this.swipeTriggered = true;
          this.lastSwipeAt = Date.now();
          setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
          logger.info(TAG, '单页TTB模式：下滑，上一页');
        } else if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('prev');
          logger.info(TAG, '单页TTB模式：下滑，上一章');
        }
      } else if (isSwipeUp) {
        // 上滑：下一页
        if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
          const newIndex: number = this.viewCurrentPageIndex + 1;
          this.viewCurrentPageIndex = newIndex;
          this.currentPageIndex = newIndex;
          this.suppressExternalIndex = true;
          // 条漫模式使用统一的预加载方法
          if (this.isWebtoonMode()) {
            this.triggerWebtoonPreload();
          }
          const newPage: MangaPage = this.chapter.pages[newIndex];
          this.updateSinglePageDisplay();
          this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
          this.incrementPixelMapEpoch(newPage.id);
          this.pageImageBindings.set(newIndex, newPage.id);
          this.pageImageBindings = new Map(this.pageImageBindings);
          this.renderEpoch = this.renderEpoch + 1;
          this.translateX = 0;
          this.translateY = 0;
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
          setTimeout(() => { this.suppressExternalIndex = false; }, 0);
          this.pageChangeCommitted = true;
          this.swipeTriggered = true;
          this.lastSwipeAt = Date.now();
          setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
          logger.info(TAG, '单页TTB模式：上滑，下一页');
        } else if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('next');
          logger.info(TAG, '单页TTB模式：上滑，下一章');
        }
      }
    } else {
      // 左右翻页模式
      if (swipeDirection >= -45 && swipeDirection <= 45) {
        // 向右滑
        if (isRTL) {
          // RTL模式：向右滑是下一页
          if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
            const newIndex: number = this.viewCurrentPageIndex + 1;
            this.viewCurrentPageIndex = newIndex;
            this.currentPageIndex = newIndex;
            this.suppressExternalIndex = true;
            this.triggerWebtoonPreload();
            const newPage: MangaPage = this.chapter.pages[newIndex];
            this.updateSinglePageDisplay();
            this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
            this.incrementPixelMapEpoch(newPage.id);
            this.pageImageBindings.set(newIndex, newPage.id);
            this.pageImageBindings = new Map(this.pageImageBindings);
            this.renderEpoch = this.renderEpoch + 1;
            this.translateX = 0;
            this.translateY = 0;
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
            setTimeout(() => { this.suppressExternalIndex = false; }, 0);
            this.pageChangeCommitted = true;
            this.swipeTriggered = true;
            this.lastSwipeAt = Date.now();
            setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
            logger.info(TAG, 'RTL模式，向右滑动，下一页');
          } else if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('next');
            logger.info(TAG, 'RTL模式，向右滑动，下一章');
          }
        } else {
          // LTR模式：向右滑是上一页
          if (this.viewCurrentPageIndex > 0) {
            const newIndex: number = this.viewCurrentPageIndex - 1;
            this.viewCurrentPageIndex = newIndex;
            this.currentPageIndex = newIndex;
            this.suppressExternalIndex = true;
            this.triggerWebtoonPreload();
            const newPage: MangaPage = this.chapter.pages[newIndex];
            this.updateSinglePageDisplay();
            this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
            this.incrementPixelMapEpoch(newPage.id);
            this.pageImageBindings.set(newIndex, newPage.id);
            this.pageImageBindings = new Map(this.pageImageBindings);
            this.renderEpoch = this.renderEpoch + 1;
            this.translateX = 0;
            this.translateY = 0;
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
            setTimeout(() => { this.suppressExternalIndex = false; }, 0);
            this.pageChangeCommitted = true;
            this.swipeTriggered = true;
            this.lastSwipeAt = Date.now();
            setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
            logger.info(TAG, 'LTR模式，向右滑动，上一页');
          } else if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('prev');
            logger.info(TAG, 'LTR模式，向右滑动，上一章');
          }
        }
      } else if ((swipeDirection >= 135 || swipeDirection <= -135)) {
        // 向左滑
        if (isRTL) {
          // RTL模式：向左滑是上一页
          if (this.viewCurrentPageIndex > 0) {
            const newIndex: number = this.viewCurrentPageIndex - 1;
            this.viewCurrentPageIndex = newIndex;
            this.currentPageIndex = newIndex;
            this.suppressExternalIndex = true;
            this.triggerWebtoonPreload();
            const newPage: MangaPage = this.chapter.pages[newIndex];
            this.updateSinglePageDisplay();
            this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
            this.incrementPixelMapEpoch(newPage.id);
            this.pageImageBindings.set(newIndex, newPage.id);
            this.pageImageBindings = new Map(this.pageImageBindings);
            this.renderEpoch = this.renderEpoch + 1;
            this.translateX = 0;
            this.translateY = 0;
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
            setTimeout(() => { this.suppressExternalIndex = false; }, 0);
            this.pageChangeCommitted = true;
            this.swipeTriggered = true;
            this.lastSwipeAt = Date.now();
            setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
            logger.info(TAG, 'RTL模式，向左滑动，上一页');
          } else if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('prev');
            logger.info(TAG, 'RTL模式，向左滑动，上一章');
          }
        } else {
          // LTR模式：向左滑是下一页
          if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
            const newIndex: number = this.viewCurrentPageIndex + 1;
            this.viewCurrentPageIndex = newIndex;
            this.currentPageIndex = newIndex;
            this.suppressExternalIndex = true;
            this.triggerWebtoonPreload();
            const newPage: MangaPage = this.chapter.pages[newIndex];
            this.updateSinglePageDisplay();
            this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
            this.incrementPixelMapEpoch(newPage.id);
            this.pageImageBindings.set(newIndex, newPage.id);
            this.pageImageBindings = new Map(this.pageImageBindings);
            this.renderEpoch = this.renderEpoch + 1;
            this.translateX = 0;
            this.translateY = 0;
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
            setTimeout(() => { this.suppressExternalIndex = false; }, 0);
            this.pageChangeCommitted = true;
            this.swipeTriggered = true;
            this.lastSwipeAt = Date.now();
            setTimeout(() => { this.swipeTriggered = false; this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
            logger.info(TAG, 'LTR模式，向左滑动，下一页');
          } else if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('next');
            logger.info(TAG, 'LTR模式，向左滑动，下一章');
          }
        }
      }
    }
  }

  private preloadSinglePageNeighbors(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    // 根据内容类型和阅读模式决定预加载页数
    let preloadCount: number;
    if (this.contentType === 'OnlineUndownloaded') {
      // 【修复】在线漫画：增加单页模式预加载页数，确保卷页动画所需PixelMap提前加载
      const isWebtoon = this.isWebtoonMode();
      preloadCount = isWebtoon ? 3 : 2;  // 条漫3页，单页从1增加到2页
      logger.debug(TAG, `在线漫画模式（${isWebtoon ? '条漫' : '单页'}）：预加载${preloadCount}页`);
    } else {
      // 本地/下载漫画：使用图源设置的预加载页数，默认为10
      preloadCount = this.preloadCurrentPages !== undefined ? this.preloadCurrentPages : 10;
      logger.debug(TAG, `本地漫画模式：预加载前后${preloadCount}页`);
    }

    // 如果设置为0，不预加载
    if (preloadCount <= 0) {
      logger.debug(TAG, '预加载页数为0，跳过预加载');
      return;
    }

    const currentIndex = this.viewCurrentPageIndex;
    const totalPages = this.chapter.pages.length;

    logger.debug(TAG, `预加载范围: 当前页=${currentIndex + 1}, 预加载前后${preloadCount}页, contentType=${this.contentType}`);

    // [优化] 统一使用优先级策略预加载，前后对称加载
    // 优先级分级：当前页=10（最高）> 下一页=9 > 上一页=8 > 下下页=7 > 上上页=6 ...
    interface LoadOrderItem {
      idx: number;
      priority: number;
    }
    const loadOrder: Array<LoadOrderItem> = [];
    
    // 当前页（如果未加载）
    const currentItem: LoadOrderItem = { idx: currentIndex, priority: 10 };
    loadOrder.push(currentItem);
    
    // 前后对称预加载：+1, -1, +2, -2, +3, -3 ...
    for (let i = 1; i <= preloadCount; i++) {
      // 下一页优先级更高（用户更可能向前翻页）
      if (currentIndex + i < totalPages) {
        const forwardItem: LoadOrderItem = { idx: currentIndex + i, priority: Math.max(1, 10 - i) };
        loadOrder.push(forwardItem);
      }
      // 上一页
      if (currentIndex - i >= 0) {
        const backwardItem: LoadOrderItem = { idx: currentIndex - i, priority: Math.max(1, 10 - i - 1) };
        loadOrder.push(backwardItem);
      }
    }
    
    // 按优先级顺序加载
    for (const item of loadOrder) {
      if (item.idx >= 0 && item.idx < totalPages) {
        const page = this.chapter.pages[item.idx];
        const st = this.getPageLoadState(page);
        const hasPm = this.pagePixelMaps.has(page.id);
        
        if (!hasPm && (!st || !st.isLoading)) {
          this.loadImageWithPriority(page, item.priority);
          logger.debug(TAG, `预加载第${item.idx + 1}页: priority=${item.priority}, id=${page.id}`);
        }
      }
    }
  }

  /**
   * 构建单页显示
   */
  @Builder
  buildSinglePageView() {
    Stack() {
      if (this.previewPrevPageId && this.previewPrevPageId.length > 0) {
        Stack() {
          Image(this.previewPrevImageInput)
            .key(`${this.previewPrevPageId}_preview_prev_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewPrevPageId)}`)
            .width('100%')
            .height('100%')
            .objectFit(this.getImageFitMode(this.getPageById(this.previewPrevPageId)!))
            .padding(0)
            .margin(0)
            .borderWidth(0)
            .onAppear(() => {
              const pg = this.getPageById(this.previewPrevPageId);
              if (pg) { this.logImageDisplayBefore(pg, this.previewPrevImageInput); }
            })
            .onComplete(() => {
              const pg = this.getPageById(this.previewPrevPageId);
              if (pg) { this.logImageDisplayAfter(pg, true); }
            })
            .onError((error: ImageError) => {
              const pg = this.getPageById(this.previewPrevPageId);
              if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
            })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.getPrevOverlayTranslateX(), y: this.getPrevOverlayTranslateY() })
        // 移除transition动画，避免与翻页动画冲突，保持opacity即时响应
        .opacity(this.getPrevOverlayOpacity())
        .transition(TransitionEffect.IDENTITY)
      }
      if (this.previewNextPageId && this.previewNextPageId.length > 0) {
        Stack() {
          Image(this.previewNextImageInput)
            .key(`${this.previewNextPageId}_preview_next_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewNextPageId)}`)
            .width('100%')
            .height('100%')
            .objectFit(this.getImageFitMode(this.getPageById(this.previewNextPageId)!))
            .padding(0)
            .margin(0)
            .borderWidth(0)
            .onAppear(() => {
              const pg = this.getPageById(this.previewNextPageId);
              if (pg) { this.logImageDisplayBefore(pg, this.previewNextImageInput); }
            })
            .onComplete(() => {
              const pg = this.getPageById(this.previewNextPageId);
              if (pg) { this.logImageDisplayAfter(pg, true); }
            })
            .onError((error: ImageError) => {
              const pg = this.getPageById(this.previewNextPageId);
              if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
            })
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.getNextOverlayTranslateX(), y: this.getNextOverlayTranslateY() })
        // 移除transition动画，避免与翻页动画冲突，保持opacity即时响应
        .opacity(this.getNextOverlayOpacity())
        .transition(TransitionEffect.IDENTITY)
      }
      // 普通内容层（始终显示，作为底层）
      this.buildSinglePageContent()

      if (this.showSoftTransitionOverlay && this.softTransitionOverlayPageId.length > 0) {
        Stack() {
          Image(this.softTransitionOverlayInput)
            .key(`soft_none_overlay_${this.softTransitionOverlayPageId}`)
            .width('100%')
            .height('100%')
            .objectFit(this.getSoftTransitionOverlayFitMode())
            .padding(0)
            .margin(0)
            .borderWidth(0)
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.softTransitionOverlayTranslateX, y: this.softTransitionOverlayTranslateY })
        .opacity(this.softTransitionOverlayOpacity)
        .transition(TransitionEffect.IDENTITY)
      }

      // Canvas卷页层（卷页动画时显示）
      if (this.showCanvasCurl) {
        this.buildCanvasCurlLayer()
      }
    }
    .width('100%')
    .height('100%')
    // 单页模式下仅使用PanGesture进行翻页，避免与SwipeGesture产生冲突
  }

  /**
   * 构建Canvas卷页层
   * 使用PageCurlEffectV2组件实现真实的3D卷页效果
   * 传入PixelMap和图片显示区域，实现基于图片实际大小的卷页
   *
   * 交互模式：
   * - 组件内部处理触摸事件，实现可交互的翻页
   * - 通过externalProgress可以外部驱动动画
   * - 翻页完成/取消时通过onPageFlip回调通知
   */
  @Builder
  buildCanvasCurlLayer() {
    PageCurlEffectV2({
      currentPixelMap: this.curlCurrentPixelMap,
      nextPixelMap: this.curlNextPixelMap,
      componentWidth: this.screenWidth,
      componentHeight: this.screenHeight,
      imageDisplayX: this.imageDisplayRect.x,
      imageDisplayY: this.imageDisplayRect.y,
      imageDisplayWidth: this.imageDisplayRect.w,
      imageDisplayHeight: this.imageDisplayRect.h,
      config: this.curlEffectConfig,
      isForward: this.curlIsForward,
      curlStartPosition: this.curlStartPosition,  // 翻页起始位置
      curlTouchX: this.panStartX,                 // 触摸起始X坐标（锚点角落选择）
      curlTouchY: this.curlTouchY,                // 实时手指Y坐标（动态折叠角度）
      curlBackOpacity: this.readingSettings.curlBackOpacity ?? 90,  // 卷页背面透明度
      externalProgress: this.curlProgress,        // 外部驱动的进度（用于实时拖拽）
      animateToTarget: this.curlAnimateTarget,    // 内部动画目标（高性能模式）
      animateFromProgress: this.curlAnimateFrom,  // 内部动画起始进度
      animateVelocity: this.curlAnimateVelocity,  // 脱手速度，使动画延续用户力度
      onPageFlip: (completed: boolean) => {
        this.handleCurlFlipComplete(completed);
      },
      onAnimationComplete: () => {
        // 内部动画完成回调
        this.onCurlInternalAnimationComplete();
      }
    })
      .width('100%')
      .height('100%')
  }

  /**
   * 处理卷页翻页完成/取消
   */
  private handleCurlFlipComplete(completed: boolean): void {
    logger.info(TAG, `卷页翻页${completed ? '完成' : '取消'}, pendingIndex=${this.curlPendingPageIndex}`);

    if (completed && this.curlPendingPageIndex >= 0) {
      // 翻页完成，切换到目标页面
      this.onCurlAnimationComplete();
    } else {
      // 翻页取消，重置状态
      this.resetCurlState();
    }
  }

  /**
   * 重置卷页状态（不切换页面）
   */
  private resetCurlState(): void {
    this.curlPendingPageIndex = -1;
    this.showCanvasCurl = false;
    this.curlProgress = 0;
    this.curlAnimateTarget = -1;  // 重置内部动画状态
    this.curlAnimateFrom = 0;
    this.curlAnimateVelocity = 0;  // 重置速度
    this.curlCurrentPixelMap = null;
    this.curlNextPixelMap = null;
    this.isPageTurning = false;
    this.pageTurnDirection = null;
    this.currentAnimationType = PageTurnAnimationType.NONE;
    this.pageTurnOpacity = 1.0;
    this.pageChangeCommitted = false;
    this.isCommittingPageTurn = false;
  }

  /**
   * 构建单页内容
   * 使用matrix4.transform()实现真正的3D翻页效果
   */
  @Builder
  buildSinglePageContent() {
    if (this.getCurrentPageData().page) {
      Stack() {
        this.buildPageImageContent(this.getCurrentPageData().page!)
      }
      .key(this.getSinglePageContentKey(this.getCurrentPageData().page!))
      .width('100%')
      .height('100%')
      // 使用matrix4.transform()实现真正的3D变换效果
      // 先应用用户缩放和拖拽位移
      .scale({ x: this.currentScale, y: this.currentScale })
      .translate({ x: this.translateX, y: this.translateY })
      // 应用翻页动画的3D变换矩阵
      .transform(this.pageTurnMatrix)
      .opacity(this.pageTurnOpacity)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          // 单指拖动手势（用于翻页和缩放后平移）
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
            .onActionStart((event: GestureEvent) => this.handlePanStart(event))
            .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
            .onActionEnd((event: GestureEvent) => this.handlePanEnd(event)),
          // 双指捏合手势（用于缩放）
          PinchGesture({ fingers: 2, distance: 5 })
            .onActionStart(() => this.handlePinchStart())
            .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
            .onActionEnd(() => this.handlePinchEnd())
        )
      )
      .onAppear(() => {
        const curPage: MangaPage = this.getCurrentPageData().page!;
        logger.debug(TAG, `单页当前页出现: index=${this.viewCurrentPageIndex}, id=${curPage.id}`);
        const st: ImageLoadState | undefined = this.getPageLoadState(curPage);
        this.invalidatePixelMapIfSourceChanged(curPage);
        const hasPm: boolean = this.pagePixelMaps.has(curPage.id);
        if (!hasPm && (!st || !st.isLoading)) {
          this.loadImage(curPage);
        }
        this.updateSinglePageDisplay();
        this.updateSinglePagePreview();
        this.ensurePixelMapLoaded(curPage).then(() => { this.updateSinglePageDisplay(); });
      })
    }
  }

  /**
   * 构建双页显示
   * 支持平滑翻页动画和正确的阅读方向
   * 横屏：左右并排显示两页
   * 竖屏：根据组合方式显示上下或左右双页
   */
  @Builder
  buildDoublePageView() {
    if (this.isLandscapeScreen()) {
      // 横屏模式：左右并排显示两页
      this.buildDoublePageLandscapeView()
    } else {
      // 竖屏模式：使用双页竖屏布局
      this.buildDoublePagePortraitView()
    }
  }

  /**
   * 构建双页横屏视图
   * 左右并排显示两页，图片以高度为基准缩放
   */
  @Builder
  buildDoublePageLandscapeView() {
    Stack() {
      if ((this.previewPrevLeftPageId && this.previewPrevLeftPageId.length > 0) || (this.previewPrevRightPageId && this.previewPrevRightPageId.length > 0)) {
        if (this.previewPrevSingleDoublePage) {
          Stack() {
            if (this.previewPrevLeftPageId && this.previewPrevLeftPageId.length > 0) {
              Image(this.previewPrevLeftImageInput)
                .key(`${this.previewPrevLeftPageId}_preview_prev_single_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewPrevLeftPageId)}`)
                .width('100%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewPrevLeftPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewPrevLeftImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            }
          }
          .width('100%')
          .height('100%')
          .opacity(this.getDoublePrevOverlayOpacity())
        } else {
          Row({ space: 0 }) {
            if (this.previewPrevLeftPageId && this.previewPrevLeftPageId.length > 0) {
              Image(this.previewPrevLeftImageInput)
                .key(`${this.previewPrevLeftPageId}_preview_prev_left_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewPrevLeftPageId)}`)
                .width('50%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewPrevLeftPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewPrevLeftImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewPrevLeftPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            } else {
              Column().width('50%').height('100%')
            }
            if (this.previewPrevRightPageId && this.previewPrevRightPageId.length > 0) {
              Image(this.previewPrevRightImageInput)
                .key(`${this.previewPrevRightPageId}_preview_prev_right_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewPrevRightPageId)}`)
                .width('50%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewPrevRightPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewPrevRightPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewPrevRightImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewPrevRightPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewPrevRightPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            } else {
              Column().width('50%').height('100%')
            }
          }
          .width('100%')
          .height('100%')
          .opacity(this.getDoublePrevOverlayOpacity())
        }
      }
      if ((this.previewNextLeftPageId && this.previewNextLeftPageId.length > 0) || (this.previewNextRightPageId && this.previewNextRightPageId.length > 0)) {
        if (this.previewNextSingleDoublePage) {
          Stack() {
            if (this.previewNextLeftPageId && this.previewNextLeftPageId.length > 0) {
              Image(this.previewNextLeftImageInput)
                .key(`${this.previewNextLeftPageId}_preview_next_single_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewNextLeftPageId)}`)
                .width('100%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewNextLeftPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewNextLeftImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            }
          }
          .width('100%')
          .height('100%')
          .opacity(this.getDoubleNextOverlayOpacity())
        } else {
          Row({ space: 0 }) {
            if (this.previewNextLeftPageId && this.previewNextLeftPageId.length > 0) {
              Image(this.previewNextLeftImageInput)
                .key(`${this.previewNextLeftPageId}_preview_next_left_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewNextLeftPageId)}`)
                .width('50%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewNextLeftPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewNextLeftImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewNextLeftPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            } else {
              Column().width('50%').height('100%')
            }
            if (this.previewNextRightPageId && this.previewNextRightPageId.length > 0) {
              Image(this.previewNextRightImageInput)
                .key(`${this.previewNextRightPageId}_preview_next_right_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.previewNextRightPageId)}`)
                .width('50%')
                .height('100%')
                .objectFit(this.getImageFitMode(this.getPageById(this.previewNextRightPageId)!))
                .padding(0)
                .margin(0)
                .borderWidth(0)
                .onAppear(() => {
                  const pg = this.getPageById(this.previewNextRightPageId);
                  if (pg) { this.logImageDisplayBefore(pg, this.previewNextRightImageInput); }
                })
                .onComplete(() => {
                  const pg = this.getPageById(this.previewNextRightPageId);
                  if (pg) { this.logImageDisplayAfter(pg, true); }
                })
                .onError((error: ImageError) => {
                  const pg = this.getPageById(this.previewNextRightPageId);
                  if (pg) { this.logDetailedImageError(pg, error); this.logImageDisplayAfter(pg, false); }
                })
            } else {
              Column().width('50%').height('100%')
            }
          }
          .width('100%')
          .height('100%')
          .opacity(this.getDoubleNextOverlayOpacity())
        }
      }
      // 修复：横屏下双页模式图片间隔问题
      // 使用 space: 0 确保无间隔，使用 justifyContent: FlexAlign.Center 居中显示
      if (this.isDoublePageSingleDisplayActive()) {
        Stack() {
          if (this.leftPageIndex >= 0 && this.leftPageIndex < this.chapter.pages.length) {
            Image(this.doubleLeftImageInput)
              .key(`${this.doubleLeftPageId}_${this.leftPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleLeftPageId)}_${this.pagePixelMaps.has(this.doubleLeftPageId) ? 'pm' : 'url'}_single`)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .padding(0)
              .margin(0)
              .borderWidth(0)
              .brightness(this.getFilterBrightness())
              .contrast(this.getFilterContrast())
              .saturate(this.getFilterSaturation())
              .grayscale(this.getFilterGrayscale())
              .invert(this.getFilterInvert())
              .sepia(this.getFilterSepia())
              .onAppear(() => {
                const page = this.getPageById(this.doubleLeftPageId);
                if (page) {
                  this.logImageDisplayBefore(page, this.doubleLeftImageInput);
                }
              })
              .onComplete(() => {
                const page = this.getPageById(this.doubleLeftPageId);
                if (page) {
                  const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
                  const newState: ImageLoadState = { isLoading: false, isLoaded: true, dimensions: prev && prev.dimensions ? prev.dimensions : undefined, error: undefined } as ImageLoadState;
                  this.imageLoadStates.set(page.id, newState);
                  this.imageLoadStates = new Map(this.imageLoadStates);
                  this.logImageDisplayAfter(page, true);
                }
              })
              .onError((error: ImageError) => {
                const page = this.getPageById(this.doubleLeftPageId);
                if (page) {
                  this.handleImageComponentError(page, error, 'double_single');
                }
              })
          }
        }
        .width('100%')
        .height('100%')
        .key(`double_page_single_${this.renderEpoch}`)
        .scale({ x: this.currentScale, y: this.currentScale })
        .translate({ x: this.translateX, y: this.translateY })
        .transform(this.pageTurnMatrix)
        .opacity(this.pageTurnOpacity)
        .padding(0)
        .margin(0)
        .borderWidth(0)
      } else {
        Row({ space: 0 }) {
        // 左页（不存在时填充占位）
        // 左页（固定占据50%宽度，图片靠右对齐紧贴书脊）
        if (this.leftPageIndex >= 0) {
          Stack() {
            Image(this.doubleLeftImageInput)
              .key(`${this.doubleLeftPageId}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleLeftPageId)}_${this.pagePixelMaps.has(this.doubleLeftPageId) ? 'pm' : 'url'}`)
              .height('100%')
              // 使用Contain保持图片比例，以高度为基准缩放
              .objectFit(ImageFit.Contain)
              .padding(0)
              .margin(0)
              .borderWidth(0)
              // 应用滤镜效果
              .brightness(this.getFilterBrightness())
              .contrast(this.getFilterContrast())
              .saturate(this.getFilterSaturation())
              .grayscale(this.getFilterGrayscale())
              .invert(this.getFilterInvert())
              .sepia(this.getFilterSepia())
              .onAppear(() => {
                const lp = this.getPageById(this.doubleLeftPageId);
                if (lp) {
                  this.logImageDisplayBefore(lp, this.doubleLeftImageInput);
                }
              })
              .onComplete(() => {
                const lp = this.getPageById(this.doubleLeftPageId);
                if (lp) {
                  const prev: ImageLoadState | undefined = this.imageLoadStates.get(lp.id);
                  const newState: ImageLoadState = { isLoading: false, isLoaded: true, dimensions: prev && prev.dimensions ? prev.dimensions : undefined, error: undefined } as ImageLoadState;
                  this.imageLoadStates.set(lp.id, newState);
                  this.imageLoadStates = new Map(this.imageLoadStates);
                  this.logImageDisplayAfter(lp, true);
                }
              })
              .onError((error: ImageError) => {
                const lp = this.getPageById(this.doubleLeftPageId);
                if (lp) {
                  this.handleImageComponentError(lp, error, 'double_left');
                }
              })
          }
          .onDisAppear(() => {
            logger.debug(TAG, `左页消失: index=${this.leftPageIndex}`);
            this.cleanupInvisiblePixelMaps();
          })
          // 双页卷曲动画期间禁用 transition，避免 Canvas 层淡出时底层触发动画
          .transition(TransitionEffect.IDENTITY)
          // 双页卷曲动画期间保持 opacity=1.0，避免闪烁
          .opacity(1.0)
          // 左页Stack靠右对齐（图片紧贴书脊）
          .alignContent(Alignment.End)
          .width('50%')
          .height('100%')
          .padding(0)
          .margin(0)
          .borderWidth(0)
        } else {
          // 左页不存在时的占位，仍然占据50%宽度
          Column().width('50%').height('100%')
        }

        // 右页（固定占据50%宽度，图片靠左对齐紧贴书脊）
        if (this.rightPageIndex >= 0 && this.rightPageIndex < this.chapter.pages.length) {
          Stack() {
            Image(this.doubleRightImageInput)
              .key(`${this.doubleRightPageId}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleRightPageId)}_${this.pagePixelMaps.has(this.doubleRightPageId) ? 'pm' : 'url'}`)
              .height('100%')
              // 使用Contain保持图片比例，以高度为基准缩放
              .objectFit(ImageFit.Contain)
              .padding(0)
              .margin(0)
              .borderWidth(0)
              // 应用滤镜效果
              .brightness(this.getFilterBrightness())
              .contrast(this.getFilterContrast())
              .saturate(this.getFilterSaturation())
              .grayscale(this.getFilterGrayscale())
              .invert(this.getFilterInvert())
              .sepia(this.getFilterSepia())
              .onAppear(() => {
                const rp = this.getPageById(this.doubleRightPageId);
                if (rp) {
                  this.logImageDisplayBefore(rp, this.doubleRightImageInput);
                }
              })
              .onComplete(() => {
                const rp = this.getPageById(this.doubleRightPageId);
                if (rp) {
                  const prev: ImageLoadState | undefined = this.imageLoadStates.get(rp.id);
                  const newState: ImageLoadState = { isLoading: false, isLoaded: true, dimensions: prev && prev.dimensions ? prev.dimensions : undefined, error: undefined } as ImageLoadState;
                  this.imageLoadStates.set(rp.id, newState);
                  this.imageLoadStates = new Map(this.imageLoadStates);
                  this.logImageDisplayAfter(rp, true);
                }
              })
              .onError((error: ImageError) => {
                const rp = this.getPageById(this.doubleRightPageId);
                if (rp) {
                  this.handleImageComponentError(rp, error, 'double_right');
                }
              })
          }
          .onDisAppear(() => {
            logger.debug(TAG, `右页消失: index=${this.rightPageIndex}`);
            this.cleanupInvisiblePixelMaps();
          })
          // 双页卷曲动画期间禁用 transition，避免 Canvas 层淡出时底层触发动画
          .transition(TransitionEffect.IDENTITY)
          // 双页卷曲动画期间保持 opacity=1.0，避免闪烁
          .opacity(1.0)
          // 右页Stack靠左对齐（图片紧贴书脊）
          .alignContent(Alignment.Start)
          .width('50%')
          .height('100%')
          .padding(0)
          .margin(0)
          .borderWidth(0)
        } else {
          // 右页不存在时的占位，仍然占据50%宽度
          Column().width('50%').height('100%')
        }
      }
      .width('100%')
      .height('100%')
      // 简化 key，避免频繁重建组件树导致闪烁
      .key(`double_page_row_${this.renderEpoch}`)
      // 使用matrix4.transform()实现真正的3D变换效果
      .scale({ x: this.currentScale, y: this.currentScale })
      .translate({ x: this.translateX, y: this.translateY })
      .transform(this.pageTurnMatrix)
      .opacity(this.pageTurnOpacity)
      .padding(0)
      .margin(0)
      .borderWidth(0)
      }

      // 双页卷页效果层（使用 opacity 实现平滑淡出过渡）
      if (this.showDualCurlEffect && (this.dualCurlLeftPM || this.dualCurlRightPM)) {
        DualPageCurlEffect({
          currentLeftPixelMap: this.dualCurlLeftPM,
          currentRightPixelMap: this.dualCurlRightPM,
          nextLeftPixelMap: this.dualCurlNextLeftPM,
          nextRightPixelMap: this.dualCurlNextRightPM,
          componentWidth: this.screenWidth,
          componentHeight: this.screenHeight,
          config: this.curlEffectConfig,
          isForward: this.curlIsForward,
          curlTouchY: this.curlTouchY,
          curlBackOpacity: this.readingSettings.curlBackOpacity ?? 90,
          externalProgress: this.dualCurlProgress,
          animateToTarget: -1,
          animateFromProgress: 0,
          onAnimationComplete: () => {}
        })
          .opacity(this.dualCurlEffectOpacity)
      }

      // 页面指示器
      if (this.readingSettings.showPageInfo) {
        this.buildDoublePageIndicator()
      }
    }
    .width('100%')
    .height('100%')
    .onAppear(() => {
      logger.debug(TAG, `构建双页视图: left=${this.leftPageIndex}, right=${this.rightPageIndex}`);
    })
    .gesture(
      GestureGroup(GestureMode.Parallel,
        // 单指拖动手势（用于翻页和缩放后平移）
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
          .onActionStart((event: GestureEvent) => this.handlePanStart(event))
          .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
          .onActionEnd((event: GestureEvent) => this.handlePanEnd(event)),
        // 双指捏合手势（用于缩放）
        PinchGesture({ fingers: 2, distance: 5 })
          .onActionStart(() => this.handlePinchStart())
          .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
          .onActionEnd(() => this.handlePinchEnd())
      )
    )
  }

  /**
   * 判断是否为垂直布局
   */
  private isVerticalPortraitLayout(): boolean {
    return (this.readingSettings.doublePagePortraitLayout || DoublePagePortraitLayout.VERTICAL) === DoublePagePortraitLayout.VERTICAL;
  }

  private shouldUseVerticalDoublePageManualScrollMode(): boolean {
    return this.isDoublePageVerticalPortraitMode() && this.currentScale <= 1.0;
  }

  @Builder
  private buildDoublePagePortraitBody() {
    if (this.isVerticalPortraitLayout()) {
      // 上下组合布局：页码小的在上
      this.buildDoublePagePortraitVertical()
    } else {
      // 左右组合布局：根据阅读方向决定位置
      this.buildDoublePagePortraitHorizontal()
    }

    // 页面指示器
    if (this.readingSettings.showPageInfo) {
      this.buildDoublePageIndicator()
    }
  }

  /**
   * 构建双页竖屏视图
   * 支持两种组合方式：上下组合（VERTICAL）和左右组合（HORIZONTAL）
   */
  @Builder
  buildDoublePagePortraitView() {
    if (this.shouldUseVerticalDoublePageManualScrollMode()) {
      Stack() {
        this.buildDoublePagePortraitBody()
      }
      .width('100%')
      .height('100%')
      .onAppear(() => {
        logger.debug(TAG, `构建双页竖屏视图: layout=${this.isVerticalPortraitLayout() ? 'VERTICAL' : 'HORIZONTAL'}, left=${this.leftPageIndex}, right=${this.rightPageIndex}, interaction=manual_vertical_scroll`);
      })
      .gesture(
        PinchGesture({ fingers: 2, distance: 5 })
          .onActionStart(() => this.handlePinchStart())
          .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
          .onActionEnd(() => this.handlePinchEnd())
      )
    } else {
      Stack() {
        this.buildDoublePagePortraitBody()
      }
      .width('100%')
      .height('100%')
      .onAppear(() => {
        logger.debug(TAG, `构建双页竖屏视图: layout=${this.isVerticalPortraitLayout() ? 'VERTICAL' : 'HORIZONTAL'}, left=${this.leftPageIndex}, right=${this.rightPageIndex}, interaction=pan_and_pinch`);
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
            .onActionStart((event: GestureEvent) => this.handlePanStart(event))
            .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
            .onActionEnd((event: GestureEvent) => this.handlePanEnd(event)),
          PinchGesture({ fingers: 2, distance: 5 })
            .onActionStart(() => this.handlePinchStart())
            .onActionUpdate((event: GestureEvent) => this.handlePinchUpdate(event))
            .onActionEnd(() => this.handlePinchEnd())
        )
      )
    }
  }

  private getVerticalDoublePageImageHeight(pageIndex: number): number {
    if (!this.chapter || !this.chapter.pages || pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return 0;
    }
    return Math.max(1, Math.floor(this.getEstimatedImageHeight(this.chapter.pages[pageIndex])));
  }

  private getVerticalDoublePageContentHeight(): number {
    return this.getVerticalDoublePageImageHeight(this.getTopPageIndex()) +
      this.getVerticalDoublePageImageHeight(this.getBottomPageIndex());
  }

  private clampVerticalDoublePageScrollOffset(offset: number): number {
    const maxScroll: number = this.getVerticalDoublePageMaxScroll();
    return Math.max(0, Math.min(offset, maxScroll));
  }

  private isValidVerticalDoublePageIndex(pageIndex: number): boolean {
    return !!this.chapter && !!this.chapter.pages && pageIndex >= 0 && pageIndex < this.chapter.pages.length;
  }

  private getVerticalDoublePageDisplayInput(
    pageIndex: number,
    fallbackInput: Resource | string | image.PixelMap
  ): Resource | string | image.PixelMap {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return fallbackInput;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    return this.resolveDisplayInputForPage(page, fallbackInput, false, true);
  }

  private getVerticalDoublePagePageIdByIndex(pageIndex: number): string {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return '';
    }
    return this.chapter.pages[pageIndex].id;
  }

  private getVerticalDoublePageImageInputByIndex(pageIndex: number): Resource | string | image.PixelMap {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return $r('app.media.ic_image');
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    return this.getDisplayImageInput(page);
  }

  private updateVerticalDoublePageRenderSlots(): void {
    if (!this.isDoublePageVerticalPortraitMode() || !this.chapter || !this.chapter.pages) {
      this.verticalDoubleTopPageIndex = -1;
      this.verticalDoubleTopPageId = '';
      this.verticalDoubleTopImageInput = $r('app.media.ic_image');
      this.verticalDoubleBottomPageIndex = -1;
      this.verticalDoubleBottomPageId = '';
      this.verticalDoubleBottomImageInput = $r('app.media.ic_image');
      if (this.verticalDoubleCurrentContentIdentity !== 'vertical_identity_empty') {
        this.verticalDoubleCurrentLayerToggle = !this.verticalDoubleCurrentLayerToggle;
      }
      this.verticalDoubleCurrentContentIdentity = 'vertical_identity_empty';
      this.verticalDoubleCurrentContentKey = `vertical_current_empty_${this.renderEpoch}_${this.verticalDoubleCurrentLayerToggle ? 'A' : 'B'}`;
      return;
    }

    const topIndex: number = this.getTopPageIndex();
    const bottomIndex: number = this.getBottomPageIndex();
    const topId: string = this.getVerticalDoublePagePageIdByIndex(topIndex);
    const bottomId: string = this.getVerticalDoublePagePageIdByIndex(bottomIndex);

    this.verticalDoubleTopPageIndex = topIndex;
    this.verticalDoubleTopPageId = topId;
    this.verticalDoubleTopImageInput = this.getVerticalDoublePageImageInputByIndex(topIndex);
    this.verticalDoubleBottomPageIndex = bottomIndex;
    this.verticalDoubleBottomPageId = bottomId;
    this.verticalDoubleBottomImageInput = this.getVerticalDoublePageImageInputByIndex(bottomIndex);
    const contentIdentity: string = `vertical_identity_${this.viewCurrentPageIndex}_${topIndex}_${bottomIndex}_${topId}_${bottomId}_${this.getVerticalDoublePageSlotSourceState(topId)}_${this.getVerticalDoublePageSlotSourceState(bottomId)}`;
    if (contentIdentity !== this.verticalDoubleCurrentContentIdentity) {
      this.verticalDoubleCurrentLayerToggle = !this.verticalDoubleCurrentLayerToggle;
      this.verticalDoubleCurrentContentIdentity = contentIdentity;
      logger.debug(TAG, `双页竖向当前层身份变化: layer=${this.verticalDoubleCurrentLayerToggle ? 'A' : 'B'}, identity=${contentIdentity}`);
    }
    this.verticalDoubleCurrentContentKey = `${contentIdentity}_${this.renderEpoch}_${this.verticalDoubleCurrentLayerToggle ? 'A' : 'B'}`;
    const topPath: string = topIndex >= 0 && topIndex < this.chapter.pages.length
      ? (this.getFsPathFromPage(this.chapter.pages[topIndex]) || 'N/A')
      : 'N/A';
    const bottomPath: string = bottomIndex >= 0 && bottomIndex < this.chapter.pages.length
      ? (this.getFsPathFromPage(this.chapter.pages[bottomIndex]) || 'N/A')
      : 'N/A';
    logger.debug(TAG, `双页竖向渲染槽更新: top=${topIndex}/${topId}/${topPath}, bottom=${bottomIndex}/${bottomId}/${bottomPath}, key=${this.verticalDoubleCurrentContentKey}`);
  }

  private getVerticalDoublePageSlotSourceState(pageId: string): string {
    if (pageId.length === 0) {
      return 'none';
    }
    if (this.pagePixelMaps.has(pageId)) {
      return `pm_${this.getPixelMapEpoch(pageId)}`;
    }
    if (this.localImageCache.has(pageId)) {
      return `local_${this.getPixelMapEpoch(pageId)}`;
    }
    return `src_${this.getPixelMapEpoch(pageId)}`;
  }

  private shouldRenderVerticalDoublePageImage(pageIndex: number): boolean {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return false;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    if (this.pagePixelMaps.has(page.id) || this.localImageCache.has(page.id)) {
      return true;
    }
    const st: ImageLoadState | undefined = this.getPageLoadState(page);
    if ((st && st.isLoading && !st.isLoaded) || this.localImageCache.isLoading(page.id)) {
      return false;
    }
    if (page.sourceType === ImageSourceType.NETWORK) {
      return false;
    }
    if (page.sourceType === ImageSourceType.LOCAL) {
      const fsPath: string | undefined = this.getFsPathFromPage(page);
      return !!fsPath && fsPath.length > 0;
    }
    return page.imageUrl.length > 0;
  }

  private shouldShowVerticalDoublePageError(pageIndex: number): boolean {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return false;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    const st: ImageLoadState | undefined = this.getPageLoadState(page);
    return !!st && !!st.error && st.error.length > 0;
  }

  private getVerticalDoublePageErrorText(pageIndex: number): string {
    if (!this.isValidVerticalDoublePageIndex(pageIndex)) {
      return '图片加载失败';
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    const st: ImageLoadState | undefined = this.getPageLoadState(page);
    return st && st.error && st.error.length > 0 ? st.error : '图片加载失败';
  }

  private ensureVerticalDoublePagePageLoading(pageIndex: number): void {
    if (!this.isValidVerticalDoublePageIndex(pageIndex) ||
      this.shouldRenderVerticalDoublePageImage(pageIndex) ||
      this.shouldShowVerticalDoublePageError(pageIndex)) {
      return;
    }
    const page: MangaPage = this.chapter.pages[pageIndex];
    const st: ImageLoadState | undefined = this.getPageLoadState(page);
    if (st && st.isLoading) {
      return;
    }
    if (page.sourceType === ImageSourceType.LOCAL) {
      this.triggerLocalImageLoad(page, this.chapter.id, pageIndex);
      return;
    }
    this.loadImage(page);
  }

  private markVerticalDoublePageImageComplete(pageIndex: number, pageId: string): void {
    const page: MangaPage | undefined = this.isValidVerticalDoublePageIndex(pageIndex)
      ? this.chapter.pages[pageIndex]
      : this.getPageById(pageId);
    if (!page) {
      return;
    }
    const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
    const newState: ImageLoadState = {
      isLoading: false,
      isLoaded: true,
      dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
      error: undefined
    } as ImageLoadState;
    this.imageLoadStates.set(page.id, newState);
    this.imageLoadStates = new Map(this.imageLoadStates);
    this.clearPendingLoadTimer(page.id);
    this.logImageDisplayAfter(page, true);
  }

  private handleVerticalDoublePageImageError(pageIndex: number, pageId: string, error: ImageError, keyPrefix: string): void {
    const page: MangaPage | undefined = this.isValidVerticalDoublePageIndex(pageIndex)
      ? this.chapter.pages[pageIndex]
      : this.getPageById(pageId);
    if (!page) {
      return;
    }
    this.handleImageComponentError(page, error, `double_vertical_${keyPrefix}`);
  }

  @Builder
  private buildVerticalDoublePageLoading(heightValue: number) {
    Column() {
      LoadingProgress()
        .width(44)
        .height(44)
        .color(colorMap.accent)
      Text('加载中...')
        .fontSize(13)
        .fontColor(colorMap.textSecondary)
        .margin({ top: 8 })
    }
    .width('100%')
    .height(heightValue)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildVerticalDoublePageFailure(pageIndex: number, heightValue: number) {
    Column() {
      Image($r('app.media.ic_image'))
        .width(52)
        .height(52)
        .objectFit(ImageFit.Contain)
        .opacity(0.68)
      Text('加载失败')
        .fontSize(14)
        .fontColor(colorMap.textPrimary)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 8 })
      Text(this.getVerticalDoublePageErrorText(pageIndex))
        .fontSize(12)
        .fontColor(colorMap.textSecondary)
        .margin({ top: 4 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(heightValue)
    .justifyContent(FlexAlign.Center)
    .padding(16)
  }

  @Builder
  private buildVerticalDoublePageImageSlot(
    pageIndex: number,
    pageId: string,
    imageInput: Resource | string | image.PixelMap,
    keyPrefix: string
  ) {
    if (this.isValidVerticalDoublePageIndex(pageIndex)) {
      Stack() {
        if (this.shouldRenderVerticalDoublePageImage(pageIndex)) {
          Image(this.getVerticalDoublePageDisplayInput(pageIndex, imageInput))
            .key(`${pageId}_${keyPrefix}_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(pageId)}`)
            .width('100%')
            .height(this.getVerticalDoublePageImageHeight(pageIndex))
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .padding(0)
            .margin(0)
            .borderWidth(0)
            .brightness(this.getFilterBrightness())
            .contrast(this.getFilterContrast())
            .saturate(this.getFilterSaturation())
            .grayscale(this.getFilterGrayscale())
            .invert(this.getFilterInvert())
            .sepia(this.getFilterSepia())
            .onAppear(() => {
              const page: MangaPage = this.chapter.pages[pageIndex];
              const actualPath: string | undefined = this.getFsPathFromPage(page);
              logger.debug(TAG, `双页竖向图片槽显示: key=${keyPrefix}, index=${pageIndex}, pageId=${pageId}, actualId=${page.id}, path=${actualPath ? actualPath : 'N/A'}, view=${this.viewCurrentPageIndex}, left=${this.leftPageIndex}, right=${this.rightPageIndex}, epoch=${this.renderEpoch}`);
              this.logImageDisplayBefore(page, this.getVerticalDoublePageDisplayInput(pageIndex, imageInput));
            })
            .onComplete(() => {
              this.markVerticalDoublePageImageComplete(pageIndex, pageId);
            })
            .onError((error: ImageError) => {
              this.handleVerticalDoublePageImageError(pageIndex, pageId, error, keyPrefix);
            })
        } else if (this.shouldShowVerticalDoublePageError(pageIndex)) {
          this.buildVerticalDoublePageFailure(pageIndex, this.getVerticalDoublePageImageHeight(pageIndex))
        } else {
          this.buildVerticalDoublePageLoading(this.getVerticalDoublePageImageHeight(pageIndex))
        }
      }
      .width('100%')
      .height(this.getVerticalDoublePageImageHeight(pageIndex))
      .onAppear(() => {
        this.ensureVerticalDoublePagePageLoading(pageIndex);
      })
    }
  }

  private handleVerticalDoublePageManualPanStart(event: GestureEvent): void {
    if (!event.fingerList || event.fingerList.length === 0 || !event.fingerList[0]) {
      logger.warn(TAG, '双页竖向拖拽开始时fingerList无效，忽略此事件');
      return;
    }
    if (!this.shouldUseVerticalDoublePageManualScrollMode() || this.isZooming) {
      return;
    }

    this.isDragging = true;
    this.pageChangeCommitted = false;
    this.swipeTriggered = false;
    this.panStartY = event.fingerList[0].globalY;
    this.verticalDoublePageLastPanOffsetY = 0;
    this.verticalDoublePagePanStartScrollOffset = this.syncVerticalDoublePageScrollOffset();
    this.verticalDoublePageLastScrollDeltaY = 0;
    this.resetVerticalDoublePageBoundaryState();
    this.preloadDoublePageNeighbors();
    logger.debug(TAG, `双页竖向手动滚动开始: offset=${this.verticalDoublePagePanStartScrollOffset.toFixed(1)}, max=${this.getVerticalDoublePageMaxScroll().toFixed(1)}`);
  }

  private handleVerticalDoublePageManualPanUpdate(event: GestureEvent): void {
    if (!this.isDragging || !this.shouldUseVerticalDoublePageManualScrollMode()) {
      return;
    }
    if (!event.fingerList || event.fingerList.length === 0 || !event.fingerList[0]) {
      logger.warn(TAG, '双页竖向拖拽更新时fingerList无效，忽略此事件');
      return;
    }
    if (this.isZooming || this.isPageTurning || this.isCommittingPageTurn) {
      return;
    }

    const deltaY: number = event.fingerList[0].globalY - this.panStartY;
    const panFrameDeltaY: number = deltaY - this.verticalDoublePageLastPanOffsetY;
    this.verticalDoublePageLastPanOffsetY = deltaY;

    const scrollIntentY: number = -panFrameDeltaY;
    if (!Number.isFinite(scrollIntentY) || Math.abs(scrollIntentY) < 0.1) {
      return;
    }

    const previousOffsetY: number = this.verticalDoublePageScrollOffset;
    const nextOffsetY: number = this.clampVerticalDoublePageScrollOffset(
      this.verticalDoublePagePanStartScrollOffset - deltaY
    );
    this.verticalDoublePageLastScrollDeltaY = scrollIntentY;

    if (this.handleVerticalDoublePageBoundaryInteraction(scrollIntentY, previousOffsetY, nextOffsetY)) {
      logger.debug(TAG, `双页竖向触边拖拽: intent=${scrollIntentY.toFixed(1)}, offset=${previousOffsetY.toFixed(1)} -> ${nextOffsetY.toFixed(1)}, max=${this.getVerticalDoublePageMaxScroll().toFixed(1)}, action=${this.verticalDoublePageTurnAction ?? 'none'}`);
      return;
    }

    this.verticalDoublePageScrollOffset = nextOffsetY;
    if (Math.abs(scrollIntentY) > 1.0) {
      logger.debug(TAG, `双页竖向手动滚动: intent=${scrollIntentY.toFixed(1)}, offset=${nextOffsetY.toFixed(1)}, max=${this.getVerticalDoublePageMaxScroll().toFixed(1)}`);
    }
    if (!this.isPageTurning && !this.isCommittingPageTurn) {
      this.translateY = 0;
      this.verticalDoublePageTurnAction = null;
    }
  }

  private handleVerticalDoublePageManualPanEnd(): void {
    if (!this.isDoublePageVerticalPortraitMode()) {
      this.isDragging = false;
      return;
    }
    this.isDragging = false;
    this.verticalDoublePageLastPanOffsetY = 0;
    this.handleVerticalDoublePageScrollStop();
  }

  @Builder
  buildDoublePagePortraitVerticalPreview(
    topPageId: string,
    topImageInput: Resource | string | image.PixelMap,
    bottomPageId: string,
    bottomImageInput: Resource | string | image.PixelMap,
    keyPrefix: string
  ) {
    Column({ space: 0 }) {
      if (topPageId.length > 0) {
        this.buildVerticalDoublePageImageSlot(
          this.getPageIndexById(topPageId),
          topPageId,
          topImageInput,
          `${keyPrefix}_top`
        )
      }
      if (bottomPageId.length > 0) {
        this.buildVerticalDoublePageImageSlot(
          this.getPageIndexById(bottomPageId),
          bottomPageId,
          bottomImageInput,
          `${keyPrefix}_bottom`
        )
      }
    }
    .width('100%')
  }

  private shouldBuildVerticalDoublePagePreview(role: 'prev' | 'next'): boolean {
    if (this.getVerticalDoublePageActivePreviewRole() !== role) {
      return false;
    }
    if (role === 'prev') {
      return this.previewPrevLeftPageId.length > 0 || this.previewPrevRightPageId.length > 0;
    }
    return this.previewNextLeftPageId.length > 0 || this.previewNextRightPageId.length > 0;
  }

  @Builder
  private buildVerticalDoublePageCurrentLayer(layerName: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 0 }) {
        if (this.verticalDoubleTopPageIndex >= 0 && this.verticalDoubleTopPageIndex < this.chapter.pages.length) {
          this.buildVerticalDoublePageImageSlot(
            this.verticalDoubleTopPageIndex,
            this.verticalDoubleTopPageId,
            this.verticalDoubleTopImageInput,
            `portrait_v_${layerName}_top`
          )
        }
        if (this.verticalDoubleBottomPageIndex >= 0 && this.verticalDoubleBottomPageIndex < this.chapter.pages.length) {
          this.buildVerticalDoublePageImageSlot(
            this.verticalDoubleBottomPageIndex,
            this.verticalDoubleBottomPageId,
            this.verticalDoubleBottomImageInput,
            `portrait_v_${layerName}_bottom`
          )
        }
        if (this.verticalDoubleTopPageIndex < 0 && this.getTopPageIndex() >= 0 && this.getTopPageIndex() < this.chapter.pages.length) {
          this.buildVerticalDoublePageImageSlot(
            this.getTopPageIndex(),
            this.getVerticalDoublePagePageIdByIndex(this.getTopPageIndex()),
            this.getVerticalDoublePageImageInputByIndex(this.getTopPageIndex()),
            `portrait_v_${layerName}_top_fallback`
          )
        }
        if (this.verticalDoubleBottomPageIndex < 0 && this.getBottomPageIndex() >= 0 && this.getBottomPageIndex() < this.chapter.pages.length) {
          this.buildVerticalDoublePageImageSlot(
            this.getBottomPageIndex(),
            this.getVerticalDoublePagePageIdByIndex(this.getBottomPageIndex()),
            this.getVerticalDoublePageImageInputByIndex(this.getBottomPageIndex()),
            `portrait_v_${layerName}_bottom_fallback`
          )
        }
      }
      .width('100%')
      .height(this.getVerticalDoublePageContentHeight())
      .translate({ x: 0, y: -this.clampVerticalDoublePageScrollOffset(this.verticalDoublePageScrollOffset) })
    }
    .key(`${this.getVerticalDoublePageCurrentContentKey()}_${layerName}`)
    .width('100%')
    .height('100%')
    .clip(true)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 2 })
        .onActionStart((event: GestureEvent) => this.handleVerticalDoublePageManualPanStart(event))
        .onActionUpdate((event: GestureEvent) => this.handleVerticalDoublePageManualPanUpdate(event))
        .onActionEnd(() => this.handleVerticalDoublePageManualPanEnd())
    )
    .scale({
      x: this.currentScale * this.getVerticalDoublePageContentScaleFactor(),
      y: this.currentScale * this.getVerticalDoublePageContentScaleFactor()
    })
    .translate({ x: this.translateX, y: this.translateY })
    .transform(this.pageTurnMatrix)
    .opacity(this.pageTurnOpacity)
    .zIndex(10)
    .onAppear(() => {
      logger.debug(TAG, `双页竖向当前层显示: layer=${layerName}, key=${this.getVerticalDoublePageCurrentContentKey()}, top=${this.verticalDoubleTopPageIndex}/${this.verticalDoubleTopPageId}, bottom=${this.verticalDoubleBottomPageIndex}/${this.verticalDoubleBottomPageId}`);
    })
  }

  /**
   * 获取上下组合布局的上方页面索引
   */
  private getTopPageIndex(): number {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.rightPageIndex
      : this.leftPageIndex;
  }

  /**
   * 获取上下组合布局的下方页面索引
   */
  private getBottomPageIndex(): number {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.leftPageIndex
      : this.rightPageIndex;
  }

  /**
   * 获取上下组合布局的上方页面ID
   */
  private getTopPageId(): string {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.doubleRightPageId
      : this.doubleLeftPageId;
  }

  /**
   * 获取上下组合布局的下方页面ID
   */
  private getBottomPageId(): string {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.doubleLeftPageId
      : this.doubleRightPageId;
  }

  /**
   * 获取上下组合布局的上方图片输入
   */
  private getTopImageInput(): string | Resource | image.PixelMap {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.doubleRightImageInput
      : this.doubleLeftImageInput;
  }

  /**
   * 获取上下组合布局的下方图片输入
   */
  private getBottomImageInput(): string | Resource | image.PixelMap {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP
      ? this.doubleLeftImageInput
      : this.doubleRightImageInput;
  }

  private isVerticalDoublePageEdgeVisible(edge: 'top' | 'bottom'): boolean {
    if (!this.isDoublePageVerticalPortraitMode() || this.currentScale > 1.0) {
      return false;
    }
    const edgeTolerance: number = MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_TOLERANCE_VP;
    const offsetY: number = this.clampVerticalDoublePageScrollOffset(this.verticalDoublePageScrollOffset);
    if (edge === 'top') {
      return offsetY <= edgeTolerance;
    }
    const maxScroll: number = this.getVerticalDoublePageMaxScroll();
    return offsetY >= Math.max(0, maxScroll - edgeTolerance);
  }

  private shouldShowVerticalDoublePageEdgeHint(edge: 'top' | 'bottom'): boolean {
    if (!this.isDoublePageVerticalPortraitMode() || this.currentScale > 1.0) {
      return false;
    }
    return !this.isPageTurning && !this.isCommittingPageTurn && this.isVerticalDoublePageEdgeVisible(edge);
  }

  private shouldShowVerticalDoublePageEdgeHintText(edge: 'top' | 'bottom'): boolean {
    if (!this.isDoublePageVerticalPortraitMode() || this.currentScale > 1.0) {
      return false;
    }
    if (this.verticalDoublePageBoundaryDirection === edge && this.verticalDoublePageEdgeHintProgress > 0) {
      return true;
    }
    if ((this.isPageTurning || this.isCommittingPageTurn) && this.verticalDoublePageTurnAction) {
      return this.getVerticalDoublePageActionOrigin(this.resolveVerticalDoublePageTurnAction()) === edge;
    }
    return false;
  }

  private getVerticalDoublePageEdgeHintOpacity(edge: 'top' | 'bottom'): number {
    if (this.shouldShowVerticalDoublePageEdgeHintText(edge)) {
      return Math.max(0.68, this.getVerticalDoublePageEdgeHintTextOpacity(edge));
    }
    if (!this.shouldShowVerticalDoublePageEdgeHint(edge)) {
      return 0;
    }
    if (this.verticalDoublePageBoundaryDirection === edge) {
      return Math.min(1.0, 0.76 + this.verticalDoublePageEdgeHintProgress * 0.24);
    }
    return 0.68;
  }

  private getVerticalDoublePageEdgeHintLineWidth(edge: 'top' | 'bottom'): string {
    let progress: number = 0;
    if (this.verticalDoublePageBoundaryDirection === edge) {
      progress = this.verticalDoublePageEdgeHintProgress;
    }
    const widthValue: number = 34 + progress * 22;
    return `${Math.round(widthValue)}%`;
  }

  private getVerticalDoublePageEdgeHintZoneHeight(edge: 'top' | 'bottom'): number {
    if (this.verticalDoublePageBoundaryDirection === edge) {
      return MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_GUIDE_ZONE_VP +
        this.verticalDoublePageEdgeHintProgress * 28;
    }
    return MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_GUIDE_ZONE_VP;
  }

  private getVerticalDoublePageEdgeHintLineHeight(edge: 'top' | 'bottom'): number {
    if (this.verticalDoublePageBoundaryDirection === edge) {
      return 3 + this.verticalDoublePageEdgeHintProgress * 2;
    }
    return 3;
  }

  private getVerticalDoublePageEdgeHintText(edge: 'top' | 'bottom'): string {
    const action: 'next' | 'prev' = this.getVerticalDoublePageBoundaryAction(edge);
    if (action === 'prev' && this.isFirstChapter) {
      return '当前已是最前';
    }
    if (action === 'next' && this.isLastChapter) {
      return '当前已是最后';
    }
    const actionText: string = action === 'next' ? '下一组' : '上一组';
    if (this.verticalDoublePageBoundaryDirection === edge && this.verticalDoublePageEdgeHintProgress >= 1.0) {
      return `释放切换${actionText}`;
    }
    return edge === 'top' ? `下拉到提示线切换${actionText}` : `上拉到提示线切换${actionText}`;
  }

  private getVerticalDoublePageEdgeHintTextOpacity(edge: 'top' | 'bottom'): number {
    if (!this.shouldShowVerticalDoublePageEdgeHintText(edge)) {
      return 0;
    }
    if (this.verticalDoublePageBoundaryDirection === edge) {
      return Math.min(1.0, 0.45 + this.verticalDoublePageEdgeHintProgress * 0.55);
    }
    return Math.max(0.58, 0.92 - this.pageTurnProgress * 0.26);
  }

  @Builder
  private buildVerticalDoublePageEdgeHintLine(edge: 'top' | 'bottom') {
    Row() {
      Column()
        .width(this.getVerticalDoublePageEdgeHintLineWidth(edge))
        .height(this.getVerticalDoublePageEdgeHintLineHeight(edge))
        .backgroundColor(colorMap.accent)
        .borderRadius(3)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildVerticalDoublePageEdgeHintText(edge: 'top' | 'bottom') {
    if (this.shouldShowVerticalDoublePageEdgeHintText(edge)) {
      Row() {
        Text(this.getVerticalDoublePageEdgeHintText(edge))
          .fontSize(12)
          .fontColor(colorMap.textOnAccent)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(colorMap.backgroundOverlay)
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .maxLines(1)
          .opacity(this.getVerticalDoublePageEdgeHintTextOpacity(edge))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private buildVerticalDoublePageEdgeHint(edge: 'top' | 'bottom') {
    Stack({ alignContent: edge === 'top' ? Alignment.TopStart : Alignment.BottomStart }) {
      Column({ space: 6 }) {
        if (edge === 'top') {
          this.buildVerticalDoublePageEdgeHintLine(edge)
          this.buildVerticalDoublePageEdgeHintText(edge)
        } else {
          this.buildVerticalDoublePageEdgeHintText(edge)
          this.buildVerticalDoublePageEdgeHintLine(edge)
        }
      }
      .width('100%')
      .height(this.getVerticalDoublePageEdgeHintZoneHeight(edge))
      .justifyContent(edge === 'top' ? FlexAlign.Start : FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 24, right: 24, top: edge === 'top' ? 12 : 0, bottom: edge === 'bottom' ? 12 : 0 })
      .opacity(this.getVerticalDoublePageEdgeHintOpacity(edge))
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .hitTestBehavior(HitTestMode.Transparent)
    .zIndex(30)
  }

  /**
   * 双页竖屏-上下组合布局
   * 根据竖向双页方向决定上下页顺序
   */
  @Builder
  buildDoublePagePortraitVertical() {
    Stack() {
      if (this.shouldBuildVerticalDoublePagePreview('prev')) {
        Stack() {
          this.buildDoublePagePortraitVerticalPreview(
            this.isDoublePageVerticalNextAtTop() ? this.previewPrevRightPageId : this.previewPrevLeftPageId,
            this.isDoublePageVerticalNextAtTop() ? this.previewPrevRightImageInput : this.previewPrevLeftImageInput,
            this.isDoublePageVerticalNextAtTop() ? this.previewPrevLeftPageId : this.previewPrevRightPageId,
            this.isDoublePageVerticalNextAtTop() ? this.previewPrevLeftImageInput : this.previewPrevRightImageInput,
            'preview_prev_vertical'
          )
        }
        .width('100%')
        .height('100%')
        .translate({ x: 0, y: this.getVerticalDoublePagePreviewTranslateY('prev') })
        .scale({ x: this.getVerticalDoublePagePreviewScale('prev'), y: this.getVerticalDoublePagePreviewScale('prev') })
        .opacity(this.getDoublePrevOverlayOpacity())
        .zIndex(2)
      }
      if (this.shouldBuildVerticalDoublePagePreview('next')) {
        Stack() {
          this.buildDoublePagePortraitVerticalPreview(
            this.isDoublePageVerticalNextAtTop() ? this.previewNextRightPageId : this.previewNextLeftPageId,
            this.isDoublePageVerticalNextAtTop() ? this.previewNextRightImageInput : this.previewNextLeftImageInput,
            this.isDoublePageVerticalNextAtTop() ? this.previewNextLeftPageId : this.previewNextRightPageId,
            this.isDoublePageVerticalNextAtTop() ? this.previewNextLeftImageInput : this.previewNextRightImageInput,
            'preview_next_vertical'
          )
        }
        .width('100%')
        .height('100%')
        .translate({ x: 0, y: this.getVerticalDoublePagePreviewTranslateY('next') })
        .scale({ x: this.getVerticalDoublePagePreviewScale('next'), y: this.getVerticalDoublePagePreviewScale('next') })
        .opacity(this.getDoubleNextOverlayOpacity())
        .zIndex(2)
      }
      if (this.verticalDoubleCurrentLayerToggle) {
        this.buildVerticalDoublePageCurrentLayer('A')
      } else {
        this.buildVerticalDoublePageCurrentLayer('B')
      }
      this.buildVerticalDoublePageEdgeHint('top')
      this.buildVerticalDoublePageEdgeHint('bottom')
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 双页竖屏-左右组合布局
   * LTR: 页码小的在左边
   * RTL: 页码小的在右边
   */
  @Builder
  buildDoublePagePortraitHorizontal() {
    if (this.isDoublePageSingleDisplayActive()) {
      Stack() {
        if (this.leftPageIndex >= 0 && this.leftPageIndex < this.chapter.pages.length) {
          Image(this.doubleLeftImageInput)
            .key(`${this.doubleLeftPageId}_portrait_h_single_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleLeftPageId)}`)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .padding(0)
            .margin(0)
            .borderWidth(0)
            .brightness(this.getFilterBrightness())
            .contrast(this.getFilterContrast())
            .saturate(this.getFilterSaturation())
            .grayscale(this.getFilterGrayscale())
            .invert(this.getFilterInvert())
            .sepia(this.getFilterSepia())
        }
      }
      .width('100%')
      .height('100%')
      .scale({ x: this.currentScale, y: this.currentScale })
      .translate({ x: this.translateX, y: this.translateY })
      .transform(this.pageTurnMatrix)
      .opacity(this.pageTurnOpacity)
    } else {
      Row({ space: 0 }) {
      // 左侧页面
      if (this.leftPageIndex >= 0 && this.leftPageIndex < this.chapter.pages.length) {
        Image(this.doubleLeftImageInput)
          .key(`${this.doubleLeftPageId}_portrait_h_left_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleLeftPageId)}`)
          .width('50%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .padding(0)
          .margin(0)
          .borderWidth(0)
          // 应用滤镜效果
          .brightness(this.getFilterBrightness())
          .contrast(this.getFilterContrast())
          .saturate(this.getFilterSaturation())
          .grayscale(this.getFilterGrayscale())
          .invert(this.getFilterInvert())
          .sepia(this.getFilterSepia())
      } else {
        // 左页不存在时的占位
        Column().width('50%').height('100%')
      }
      // 右侧页面
      if (this.rightPageIndex >= 0 && this.rightPageIndex < this.chapter.pages.length) {
        Image(this.doubleRightImageInput)
          .key(`${this.doubleRightPageId}_portrait_h_right_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleRightPageId)}`)
          .width('50%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .padding(0)
          .margin(0)
          .borderWidth(0)
          // 应用滤镜效果
          .brightness(this.getFilterBrightness())
          .contrast(this.getFilterContrast())
          .saturate(this.getFilterSaturation())
          .grayscale(this.getFilterGrayscale())
          .invert(this.getFilterInvert())
          .sepia(this.getFilterSepia())
      } else {
        // 右页不存在时的占位
        Column().width('50%').height('100%')
      }
      }
      .width('100%')
      .height('100%')
      // 使用matrix4.transform()实现真正的3D变换效果
      .scale({ x: this.currentScale, y: this.currentScale })
      .translate({ x: this.translateX, y: this.translateY })
      .transform(this.pageTurnMatrix)
      .opacity(this.pageTurnOpacity)
    }
  }

  /**
   * 构建连续滚动显示
   * [修复] 使用per-page图片源，而不是共享的singlePageImageInput
   * 原buildPageImage→buildPageImageContent使用this.singlePageImageInput（单页模式共享状态），
   * 导致ForEach中所有页面都显示同一张图片
   */
  @Builder
  buildContinuousView() {
    if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      // 水平连续滚动
      Scroll(this.scroller) {
        Row() {
          LazyForEach(this.continuousHorizontalDataSource, (pageIndex: number) => {
            if (pageIndex >= 0 && pageIndex < this.chapter.pages.length) {
              this.buildContinuousPageImage(this.chapter.pages[pageIndex], pageIndex, true)
            }
          }, (pageIndex: number) => {
            if (pageIndex >= 0 && pageIndex < this.chapter.pages.length) {
              return this.chapter.pages[pageIndex].id;
            }
            return `continuous_invalid_${pageIndex}`;
          })
        }
        .height('100%')
        .scale({ x: this.webtoonZoomScale, y: this.webtoonZoomScale, centerX: this.webtoonScaleCenterX, centerY: this.webtoonScaleCenterY })
        .translate({ x: this.webtoonOffsetX, y: this.webtoonOffsetY })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .onDidScroll((xOffset: number, yOffset: number) => {
        this.handleContinuousHorizontalScroll(xOffset);
      })
      .onScrollStart(() => {
        this.isScrolling = true;
      })
      .onScrollStop(() => {
        this.isScrolling = false;
        this.updateContinuousHorizontalVisiblePages();
        this.triggerUnifiedPreload();
        this.checkContinuousHorizontalChapterBoundary();
        this.saveScrollPosition();
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2, distance: 3 })
            .onActionStart((event: GestureEvent) => {
              this.isZooming = true;
              this.initWebtoonPinchCenter(event, true);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handleWebtoonPinchUpdate(event);
            })
            .onActionEnd(() => {
              this.handleWebtoonPinchEnd();
            }),
          GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
              .onActionUpdate((event: GestureEvent) => {
                if (this.webtoonZoomScale > this.MIN_ZOOM_SCALE) {
                  this.handleWebtoonPan(event);
                }
              }),
            SwipeGesture({ fingers: 1, direction: SwipeDirection.Vertical, speed: 100 })
              .onAction((event: GestureEvent) => {
                this.handleEdgeSwipe(event);
              })
          )
        )
      )
    } else {
      // 垂直连续滚动
      Scroll(this.scroller) {
        Column() {
          ForEach(this.chapter.pages, (page: MangaPage, index: number) => {
            this.buildContinuousPageImage(page, index, false)
          }, (page: MangaPage) => page.id)
        }
        .width('100%')
        .scale({ x: this.webtoonZoomScale, y: this.webtoonZoomScale, centerX: this.webtoonScaleCenterX, centerY: this.webtoonScaleCenterY })
        .translate({ x: this.webtoonOffsetX, y: this.webtoonOffsetY })
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .onDidScroll((xOffset: number, yOffset: number) => {
        this.handleWebtoonScroll(yOffset);
      })
      .onScrollStart(() => {
        this.isScrolling = true;
        this.cancelWebtoonStopCleanup();
      })
      .onScrollStop(() => {
        this.isScrolling = false;
        this.updateVisiblePages();
        this.triggerWebtoonPreload();
        this.scheduleWebtoonStopCleanup();
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PinchGesture({ fingers: 2, distance: 3 })
            .onActionStart((event: GestureEvent) => {
              this.isZooming = true;
              this.initWebtoonPinchCenter(event, false);
            })
            .onActionUpdate((event: GestureEvent) => {
              this.handleWebtoonPinchUpdate(event);
            })
            .onActionEnd(() => {
              this.handleWebtoonPinchEnd();
            }),
          GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
              .onActionUpdate((event: GestureEvent) => {
                if (this.webtoonZoomScale > this.MIN_ZOOM_SCALE) {
                  this.handleWebtoonPan(event);
                }
              }),
            SwipeGesture({ fingers: 1, direction: SwipeDirection.Horizontal, speed: 100 })
              .onAction((event: GestureEvent) => {
                this.handleEdgeSwipe(event);
              })
          )
        )
      )
    }
  }

  /**
   * 构建连续滚动模式下的单个页面图片
   * [修复] 每个页面独立计算图片源，避免使用共享的singlePageImageInput
   * @param page 页面数据
   * @param pageIndex 页面索引
   * @param isHorizontal 是否为水平滚动模式
   */
  @Builder
  buildContinuousPageImage(page: MangaPage, pageIndex: number, isHorizontal: boolean) {
    Stack() {
      // 按优先级选择图片源：PixelMap > 本地缓存 > 原始资源
      if (this.pagePixelMaps.has(page.id)) {
        Image(this.pagePixelMaps.get(page.id))
          .width('100%')
          .height(isHorizontal ? '100%' : undefined)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .brightness(this.getFilterBrightness())
          .contrast(this.getFilterContrast())
          .saturate(this.getFilterSaturation())
          .grayscale(this.getFilterGrayscale())
          .invert(this.getFilterInvert())
          .sepia(this.getFilterSepia())
      } else if (page.sourceType === ImageSourceType.LOCAL) {
        if (this.localImageCache.has(page.id)) {
          Image(this.localImageCache.get(page.id)!)
            .width('100%')
            .height(isHorizontal ? '100%' : undefined)
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .brightness(this.getFilterBrightness())
            .contrast(this.getFilterContrast())
            .saturate(this.getFilterSaturation())
            .grayscale(this.getFilterGrayscale())
            .invert(this.getFilterInvert())
            .sepia(this.getFilterSepia())
            .onAppear(() => {
              this.triggerLocalImageLoad(page, this.chapter.id, pageIndex);
            })
        } else {
          Image(this.getImageResource(page))
            .width('100%')
            .height(isHorizontal ? '100%' : undefined)
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .brightness(this.getFilterBrightness())
            .contrast(this.getFilterContrast())
            .saturate(this.getFilterSaturation())
            .grayscale(this.getFilterGrayscale())
            .invert(this.getFilterInvert())
            .sepia(this.getFilterSepia())
            .onAppear(() => {
              this.triggerLocalImageLoad(page, this.chapter.id, pageIndex);
            })
        }
      } else if (page.sourceType === ImageSourceType.NETWORK) {
        // 网络图片：PixelMap未加载时显示占位图
        Image($r('app.media.ic_image'))
          .width('100%')
          .height(isHorizontal ? '100%' : this.getEstimatedImageHeight(page))
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        Image(this.getImageResource(page))
          .width('100%')
          .height(isHorizontal ? '100%' : undefined)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .brightness(this.getFilterBrightness())
          .contrast(this.getFilterContrast())
          .saturate(this.getFilterSaturation())
          .grayscale(this.getFilterGrayscale())
          .invert(this.getFilterInvert())
          .sepia(this.getFilterSepia())
      }

      // 加载动画
      if (this.shouldShowLoadingForPage(page)) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(colorMap.accent)
          Text('加载中...')
            .fontSize(14)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
      }

      // 加载失败提示
      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(48)
            .height(48)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(14)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 8 })
          Text('点击重试')
            .fontSize(12)
            .fontColor(colorMap.accent)
            .margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.retryLoadPage(page);
        })
      }
    }
    .width(isHorizontal ? this.getStableContinuousHorizontalItemWidth(page) : '100%')
    .height(isHorizontal ? '100%' : undefined)
    .alignContent(Alignment.Center)
    .key(`continuous_${page.id}`)
    .margin(isHorizontal ? { right: this.readingSettings.pageSpacing } : { bottom: this.readingSettings.pageSpacing })
    .onAppear((): void => {
      const state: ImageLoadState | undefined = this.getPageLoadState(page);
      const hasPm: boolean = this.pagePixelMaps.has(page.id);
      const needLoad: boolean = !hasPm && (!state || !state.isLoading);
      if (needLoad) {
        logger.debug(TAG, `连续滚动页面出现触发加载: id=${page.id}`);
        this.loadImage(page);
      }
    })
  }

  /**
   * 构建单个页面图片
   * 优化：双页模式下移除所有间距和边距
   */
  @Builder
  buildPageImage(page: MangaPage): void {
    Stack() {
      this.buildPageImageContent(page)
    }
    .width(this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE ? '50%' : '100%')
    .height((this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL ||
      this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL ||
      this.readingSettings.readingMode === ReadingMode.WEBTOON ||
      this.readingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP) ? 'auto' : '100%')
    .alignContent(Alignment.Center)
    .key(page.id)
    .padding(0)
    .margin(0)
    .borderWidth(0)
    .onAppear((): void => {
      const state: ImageLoadState | undefined = this.getPageLoadState(page);
      const hasPm: boolean = this.pagePixelMaps.has(page.id);
      const needLoad: boolean = !hasPm && (!state || !state.isLoading);
      if (needLoad) {
        logger.debug(TAG, `页面出现触发加载: id=${page.id}`);
        this.loadImage(page);
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }

  /**
   * 获取滤镜亮度值（转换为ArkUI的brightness格式）
   * filterSettings.brightness: 0-200, 100为默认
   * ArkUI brightness: 1.0为默认，小于1变暗，大于1变亮
   */
  private getFilterBrightness(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 1.0;
    }
    return this.readingSettings.filterSettings.brightness / 100;
  }

  /**
   * 获取滤镜对比度值
   * filterSettings.contrast: 0-200, 100为默认
   * ArkUI contrast: 1.0为默认
   */
  private getFilterContrast(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 1.0;
    }
    return this.readingSettings.filterSettings.contrast / 100;
  }

  /**
   * 获取滤镜饱和度值
   * filterSettings.saturation: 0-200, 100为默认
   * ArkUI saturate: 1.0为默认
   */
  private getFilterSaturation(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 1.0;
    }
    return this.readingSettings.filterSettings.saturation / 100;
  }

  /**
   * 获取滤镜灰度值
   * filterSettings.grayscale: boolean
   * ArkUI grayscale: 0-1
   */
  private getFilterGrayscale(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 0;
    }
    return this.readingSettings.filterSettings.grayscale ? 1.0 : 0;
  }

  /**
   * 获取滤镜反色值
   * filterSettings.invert: boolean
   * ArkUI invert: 0-1
   */
  private getFilterInvert(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 0;
    }
    return this.readingSettings.filterSettings.invert ? 1.0 : 0;
  }

  /**
   * 获取滤镜棕褐色值
   * filterSettings.sepia: 0-100
   * ArkUI sepia: 0-1
   */
  private getFilterSepia(): number {
    if (!this.readingSettings.filterSettings?.enabled) {
      return 0;
    }
    return this.readingSettings.filterSettings.sepia / 100;
  }

  /**
   * 构建页面图片内容
   * 优化：双页模式下使用Fill填充确保无缝拼接
   * 支持滤镜效果：亮度、对比度、饱和度、灰度、反色、棕褐色
   */
  @Builder
  buildPageImageContent(page: MangaPage) {
    Stack() {
      // 网络图片：仅在有PixelMap或已加载完成时显示Image，加载中/失败时完全隐藏
      // 本地图片：始终显示
      if (page.sourceType === ImageSourceType.LOCAL
        || this.pagePixelMaps.has(page.id)
        || (this.getPageLoadState(page)?.isLoaded === true)) {
        Image(this.singlePageImageInput)
          .key(this.getSinglePageContentKey(page))
          .width('100%')
          .height('100%')
          .objectFit(this.getImageFitMode(page))
          .padding(0)
          .margin(0)
          .borderWidth(0)
          // 应用滤镜效果
          .brightness(this.getFilterBrightness())
          .contrast(this.getFilterContrast())
          .saturate(this.getFilterSaturation())
          .grayscale(this.getFilterGrayscale())
          .invert(this.getFilterInvert())
          .sepia(this.getFilterSepia())
          .onAppear(() => {
            this.logImageDisplayBefore(page, this.singlePageImageInput);
          })
          .onComplete(() => {
            const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
            const newState: ImageLoadState = {
              isLoading: false,
              isLoaded: true,
              dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
              error: undefined
            } as ImageLoadState;
            this.imageLoadStates.set(page.id, newState);
            this.imageLoadStates = new Map(this.imageLoadStates);
            this.logImageDisplayAfter(page, true);
            const bindIdx: number = this.getPageIndexById(page.id);
            if (bindIdx >= 0) {
              this.pageImageBindings.set(bindIdx, page.id);
              this.pageImageBindings = new Map(this.pageImageBindings);
              
              // 更新PreloadManager状态
              const hasPixelMap = this.pagePixelMaps.has(page.id);
              if (hasPixelMap) {
                // 如果有PixelMap，说明是从内存缓存加载的
                this.preloadManager.markMemCacheHit(bindIdx);
              } else {
                // 否则标记为网络加载完成
                this.preloadManager.onLoadComplete(bindIdx, true);
              }
            }
            logger.debug(TAG, `单页图片加载完成: id=${page.id}, src=${String(this.getImageResource(page))}, pm=${this.pagePixelMaps.has(page.id)}, epoch=${this.getPixelMapEpoch(page.id)}`);
            const timerId = this.pendingLoadTimers.get(page.id);
            if (typeof timerId === 'number') { clearTimeout(timerId); }
            this.pendingLoadTimers.delete(page.id);
          })
          .onError((error: ImageError) => {
            this.handleImageComponentError(page, error, 'single_page');
          })
      }

      // 显示加载动画（单页模式）
      if (this.shouldShowLoadingForPage(page)) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(colorMap.accent)
          Text('加载中...')
            .fontSize(14)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
      }

      // 显示加载失败提示（增强版：添加重试按钮）
      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(48)
            .height(48)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(14)
            .fontColor(colorMap.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 8 })
          Text(this.getPageLoadState(page)?.error || '图片加载失败')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('重试')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(colorMap.accent)
            .borderRadius(8)
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .margin({ top: 12 })
            .onClick(() => {
              logger.info(TAG, `用户点击重试加载: pageId=${page.id}`);
              this.retryLoadPage(page);
            })
        }
        .justifyContent(FlexAlign.Center)
        .padding(16)
      }
    }
  }

  @Builder
  buildPageImagePreview(page: MangaPage) {
    Stack() {
      Image(this.computeImageInputForPage(page))
        .key(`${page.id}_preview_${this.renderEpoch}_${this.getPixelMapEpoch(page.id)}`)
        .width('100%')
        .height('100%')
        .objectFit(this.getImageFitMode(page))
        .padding(0)
        .margin(0)
        .borderWidth(0)
        .onAppear(() => {
          this.logImageDisplayBefore(page, this.computeImageInputForPage(page));
        })
        .onComplete(() => {
          this.logImageDisplayAfter(page, true);
        })
        .onError((error: ImageError) => {
          this.logDetailedImageError(page, error);
          this.logImageDisplayAfter(page, false);
        })
    }
  }

  /**
   * 构建双页模式图片内容
   * 专门处理双页模式下的图片显示，保持原始比例
   * 优化：使用Contain模式保持图片原始比例，避免拉伸变形
   */
  @Builder
  buildDoublePageImageContent(page: MangaPage) {
    Stack() {
      // 网络图片：仅在有PixelMap或已加载完成时显示Image，加载中/失败时完全隐藏
      // 本地图片：始终显示
      if (page.sourceType === ImageSourceType.LOCAL
        || this.pagePixelMaps.has(page.id)
        || (this.getPageLoadState(page)?.isLoaded === true)) {
        Image(this.getDisplayImageInput(page))
          .key(`${page.id}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(page.id)}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .padding(0)
          .margin(0)
          .borderWidth(0)
          .onAppear(() => {
            this.logImageDisplayBefore(page, this.getDisplayImageInput(page));
          })
          .onComplete(() => {
            const prev: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
            const newState: ImageLoadState = {
              isLoading: false,
              isLoaded: true,
              dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
              error: undefined
            } as ImageLoadState;
            this.imageLoadStates.set(page.id, newState);
            this.imageLoadStates = new Map(this.imageLoadStates);
            this.logImageDisplayAfter(page, true);
            const bindIdx: number = this.getPageIndexById(page.id);
            if (bindIdx >= 0) {
              this.pageImageBindings.set(bindIdx, page.id);
              this.pageImageBindings = new Map(this.pageImageBindings);
            }
            logger.debug(TAG, `双页图片加载完成: id=${page.id}, src=${String(this.getImageResource(page))}, left=${this.leftPageIndex}, right=${this.rightPageIndex}, pm=${this.pagePixelMaps.has(page.id)}, epoch=${this.getPixelMapEpoch(page.id)}`);
            const timerId = this.pendingLoadTimers.get(page.id);
            if (typeof timerId === 'number') { clearTimeout(timerId); }
            this.pendingLoadTimers.delete(page.id);
          })
          .onError((error: ImageError) => {
            this.handleImageComponentError(page, error, 'double_page_content');
          })
      }

      if (this.shouldShowLoadingForPage(page)) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(colorMap.accent)
          Text('加载中...')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 4 })
        }
        .justifyContent(FlexAlign.Center)
      }

      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(32)
            .height(32)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(12)
            .fontColor(colorMap.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 4 })
          Text(this.getPageLoadState(page)?.error || '图片加载失败')
            .fontSize(10)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 2 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('重试')
            .fontSize(12)
            .fontColor(Color.White)
            .backgroundColor(colorMap.accent)
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 4, bottom: 4 })
            .margin({ top: 8 })
            .onClick(() => {
              logger.info(TAG, `用户点击重试加载(双页): pageId=${page.id}`);
              this.retryLoadPage(page);
            })
        }
        .justifyContent(FlexAlign.Center)
        .padding(12)
      }
    }
  }

  /**
   * 处理双页模式滑动手势：支持平滑单页翻页
   * 新逻辑：每次滑动翻一页，保持双页显示
   * 修复：TTB模式使用正确的上下翻页逻辑
   * 新增：支持卷页动画
   */
  private handleDoublePageSwipe(event: GestureEvent): void {
    const now: number = Date.now();
    if (now - this.lastSwipeAt < this.SWIPE_COOLDOWN_MS || this.swipeTriggered) {
      return;
    }
    this.swipeTriggered = true;
    this.lastSwipeAt = now;
    const angle: number = event.angle || 0;
    const speed: number = Math.abs(event.speed || 0);
    logger.debug(TAG, `双页Swipe事件: angle=${angle.toFixed ? angle.toFixed(1) : angle}, speed=${speed.toFixed ? speed.toFixed(1) : speed}, direction=${this.readingSettings.readingDirection.toString()}`);
    const SPEED_THRESHOLD: number = 100;
    if (speed < SPEED_THRESHOLD) { return; }

    const isVerticalDoublePage: boolean = this.isDoublePageVerticalPortraitMode();
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const maxIndex: number = this.chapter.pages.length - 1;
    const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    const animationType: PageTurnAnimationType = this.readingSettings.pageTurnAnimation || PageTurnAnimationType.FADE;
    const useCurl: boolean = animationType === PageTurnAnimationType.CURL && this.isLandscapeScreen();

    if (isVerticalDoublePage) {
      const isSwipeUp: boolean = angle <= -45 && angle >= -135;
      const isSwipeDown: boolean = angle >= 45 && angle <= 135;
      const nextAtTop: boolean = this.isDoublePageVerticalNextAtTop();
      const goNext: boolean = nextAtTop ? isSwipeDown : isSwipeUp;
      const goPrev: boolean = nextAtTop ? isSwipeUp : isSwipeDown;

      if (goNext && nextPairStart <= maxIndex && nextPairStart > pairStart) {
        if (useCurl) {
          this.performDualCurlAnimation(nextPairStart, true);
        } else {
          this.viewCurrentPageIndex = nextPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
        }
        logger.info(TAG, `双页竖向：${nextAtTop ? '下滑' : '上滑'}，下一对页`);
      } else if (goPrev && prevPairStart < pairStart) {
        if (useCurl) {
          this.performDualCurlAnimation(prevPairStart, false);
        } else {
          this.viewCurrentPageIndex = prevPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
        }
        logger.info(TAG, `双页竖向：${nextAtTop ? '上滑' : '下滑'}，上一对页`);
      }
    } else {
      const isSwipeRight: boolean = angle >= -45 && angle <= 45;
      const isSwipeLeft: boolean = angle >= 135 || angle <= -135;

      if (isSwipeRight) {
        if (isRTL && nextPairStart > pairStart) {
          if (useCurl) {
            this.performDualCurlAnimation(nextPairStart, true);
          } else {
            this.viewCurrentPageIndex = nextPairStart;
            this.updateDoublePageIndices();
            this.preloadDoublePageNeighbors();
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
          }
          logger.info(TAG, '双页RTL：右滑，下一对页');
        } else if (!isRTL && prevPairStart < pairStart) {
          if (useCurl) {
            this.performDualCurlAnimation(prevPairStart, false);
          } else {
            this.viewCurrentPageIndex = prevPairStart;
            this.updateDoublePageIndices();
            this.preloadDoublePageNeighbors();
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
          }
          logger.info(TAG, '双页LTR：右滑，上一对页');
        }
      } else if (isSwipeLeft) {
        if (isRTL && prevPairStart < pairStart) {
          if (useCurl) {
            this.performDualCurlAnimation(prevPairStart, false);
          } else {
            this.viewCurrentPageIndex = prevPairStart;
            this.updateDoublePageIndices();
            this.preloadDoublePageNeighbors();
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
          }
          logger.info(TAG, '双页RTL：左滑，上一对页');
        } else if (!isRTL && nextPairStart > pairStart) {
          if (useCurl) {
            this.performDualCurlAnimation(nextPairStart, true);
          } else {
            this.viewCurrentPageIndex = nextPairStart;
            this.updateDoublePageIndices();
            this.preloadDoublePageNeighbors();
            if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
          }
          logger.info(TAG, '双页LTR：左滑，下一对页');
        }
      }
    }
    setTimeout(() => { this.swipeTriggered = false; }, this.SWIPE_COOLDOWN_MS);
  }

  /**
   * 水平平滑滚动到指定位置（连续滚动模式）
   */
  private smoothScrollToHorizontal(targetX: number): void {
    this.smoothScrollToHorizontalWithDuration(targetX, 500);
  }

  private smoothScrollToHorizontalWithDuration(targetX: number, duration: number): void {
    if (!this.scroller) { return; }
    try {
      const maxScrollX = this.getContinuousHorizontalMaxScroll();
      const clampedTargetX = Math.max(0, Math.min(targetX, maxScrollX));
      this.suppressContinuousHorizontalBoundary(duration + 240);
      this.scroller.scrollTo({
        xOffset: clampedTargetX,
        yOffset: 0,
        animation: { duration: duration, curve: curves.initCurve(Curve.EaseInOut) }
      });
    } catch (error) {
      logger.error(TAG, `水平平滑滚动失败`);
    }
  }

  private isContinuousScrollMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private isContinuousHorizontalRTL(): boolean {
    return this.isContinuousScrollMode() &&
      this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
  }

  private shouldReverseWebtoonProgressLayout(): boolean {
    return this.isContinuousHorizontalRTL();
  }

  private getActiveProgressChapterTitle(): string {
    if (this.currentChapterId) {
      const title = this.getChapterTitleById(this.currentChapterId);
      if (title.length > 0) {
        return title;
      }
    }
    return this.chapter.title || '未知章节';
  }

  private getWebtoonProgressPercentText(): string {
    return `${Math.round(this.webtoonScrollProgress * 100)}%`;
  }

  private getWebtoonPageProgressText(): string {
    if (this.shouldReverseWebtoonProgressLayout()) {
      return `${this.getCurrentChapterPageCount()} / ${this.currentWebtoonPage + 1}`;
    }
    return `${this.currentWebtoonPage + 1} / ${this.getCurrentChapterPageCount()}`;
  }

  private getContinuousHorizontalViewportWidth(): number {
    return (this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360;
  }

  private getContinuousHorizontalScaleFactor(): number {
    return this.webtoonZoomScale > 1.0 ? this.webtoonZoomScale : 1.0;
  }

  private getContinuousHorizontalPageOrder(): number[] {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return [];
    }

    const pageOrder: number[] = [];
    if (this.isContinuousHorizontalRTL()) {
      for (let index = this.chapter.pages.length - 1; index >= 0; index--) {
        pageOrder.push(index);
      }
    } else {
      for (let index = 0; index < this.chapter.pages.length; index++) {
        pageOrder.push(index);
      }
    }
    return pageOrder;
  }

  private getContinuousHorizontalDataSourceKey(): string {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return '';
    }
    const firstPage: MangaPage = this.chapter.pages[0];
    const lastPage: MangaPage = this.chapter.pages[this.chapter.pages.length - 1];
    const directionKey: string = this.isContinuousHorizontalRTL() ? 'rtl' : 'ltr';
    return `${this.chapter.id}_${this.chapter.pages.length}_${firstPage.id}_${lastPage.id}_${directionKey}`;
  }

  private updateContinuousHorizontalDataSourceIfNeeded(): void {
    const nextKey: string = this.getContinuousHorizontalDataSourceKey();
    if (nextKey === this.continuousHorizontalDataSourceKey) {
      return;
    }
    this.continuousHorizontalDataSourceKey = nextKey;
    this.continuousHorizontalDataSource.setPageIndices(this.getContinuousHorizontalPageOrder());
  }

  private getContinuousHorizontalWidthCacheKey(): string {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return '';
    }
    const screenHeightKey: number = Math.floor((this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800);
    return `${this.chapter.id}_${this.chapter.pages.length}_${screenHeightKey}`;
  }

  private ensureContinuousHorizontalWidthCache(): void {
    const nextKey: string = this.getContinuousHorizontalWidthCacheKey();
    if (nextKey === this.continuousHorizontalWidthCacheKey) {
      return;
    }
    this.continuousHorizontalWidthCacheKey = nextKey;
    this.continuousHorizontalWidthCache.clear();
  }

  private getStableContinuousHorizontalItemWidth(page: MangaPage): number {
    this.ensureContinuousHorizontalWidthCache();
    const cachedWidth: number | undefined = this.continuousHorizontalWidthCache.get(page.id);
    if (cachedWidth !== undefined && cachedWidth > 0) {
      return cachedWidth;
    }
    const width: number = Math.max(1, Math.floor(this.getEstimatedImageWidthForHorizontal(page)));
    this.continuousHorizontalWidthCache.set(page.id, width);
    return width;
  }

  private getContinuousHorizontalVisualIndex(pageIndex: number): number {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return 0;
    }
    if (!this.isContinuousHorizontalRTL()) {
      return pageIndex;
    }
    return this.chapter.pages.length - 1 - pageIndex;
  }

  private getContinuousHorizontalRawContentWidth(): number {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return 0;
    }

    const spacing = this.readingSettings.pageSpacing || 16;
    let totalWidth = 0;
    for (let index = 0; index < this.chapter.pages.length; index++) {
      totalWidth += this.getStableContinuousHorizontalItemWidth(this.chapter.pages[index]);
      if (index < this.chapter.pages.length - 1) {
        totalWidth += spacing;
      }
    }
    return totalWidth;
  }

  private getContinuousHorizontalContentWidth(): number {
    return this.getContinuousHorizontalRawContentWidth() * this.getContinuousHorizontalScaleFactor();
  }

  private getContinuousHorizontalMaxScroll(): number {
    const viewportWidth = this.getContinuousHorizontalViewportWidth();
    return Math.max(0, this.getContinuousHorizontalContentWidth() - viewportWidth);
  }

  private getContinuousHorizontalPageTargetX(pageIndex: number): number {
    if (!this.chapter || !this.chapter.pages || pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return Math.max(0, Math.min(this.scrollPosition, this.getContinuousHorizontalMaxScroll()));
    }

    const spacing = this.readingSettings.pageSpacing || 16;
    const scaleFactor = this.getContinuousHorizontalScaleFactor();
    const visualIndex = this.getContinuousHorizontalVisualIndex(pageIndex);
    const viewportWidth = this.getContinuousHorizontalViewportWidth();
    let currentLeft = 0;

    for (let index = 0; index < visualIndex; index++) {
      const logicalIndex = this.isContinuousHorizontalRTL()
        ? this.chapter.pages.length - 1 - index
        : index;
      currentLeft += this.getStableContinuousHorizontalItemWidth(this.chapter.pages[logicalIndex]) + spacing;
    }

    const pageWidth = this.getStableContinuousHorizontalItemWidth(this.chapter.pages[pageIndex]);
    const scaledLeft = currentLeft * scaleFactor;
    const scaledRight = (currentLeft + pageWidth) * scaleFactor;
    const targetX = this.isContinuousHorizontalRTL()
      ? scaledRight - viewportWidth
      : scaledLeft;
    return Math.max(0, Math.min(targetX, this.getContinuousHorizontalMaxScroll()));
  }

  private calculateContinuousHorizontalPageIndexFromScroll(scrollX: number): number {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return 0;
    }
    this.updateContinuousHorizontalDataSourceIfNeeded();

    const spacing = this.readingSettings.pageSpacing || 16;
    const scaleFactor = this.getContinuousHorizontalScaleFactor();
    const viewportWidth = this.getContinuousHorizontalViewportWidth();
    const clampedScrollX = Math.max(0, Math.min(scrollX, this.getContinuousHorizontalMaxScroll()));
    const viewportCenter = clampedScrollX + viewportWidth / 2;
    let currentLeft = 0;
    let fallbackPageIndex = this.chapter.pages.length - 1;
    let nearestDistance = Number.POSITIVE_INFINITY;
    const totalCount: number = this.continuousHorizontalDataSource.totalCount();

    for (let visualIndex = 0; visualIndex < totalCount; visualIndex++) {
      const pageIndex: number = this.continuousHorizontalDataSource.getData(visualIndex);
      if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
        continue;
      }
      const pageWidth = this.getStableContinuousHorizontalItemWidth(this.chapter.pages[pageIndex]);
      const itemLeft = currentLeft * scaleFactor;
      const itemRight = (currentLeft + pageWidth) * scaleFactor;
      const itemCenter = (itemLeft + itemRight) / 2;
      const distance = Math.abs(viewportCenter - itemCenter);

      if (distance < nearestDistance) {
        nearestDistance = distance;
        fallbackPageIndex = pageIndex;
      }

      if (viewportCenter >= itemLeft && viewportCenter <= itemRight) {
        return pageIndex;
      }

      currentLeft += pageWidth + spacing;
    }

    return fallbackPageIndex;
  }

  private suppressContinuousHorizontalBoundary(duration: number = 500): void {
    this.continuousHorizontalBoundarySuppressUntil = Date.now() + duration;
  }

  private checkContinuousHorizontalChapterBoundary(): void {
    const input: MangaContinuousHorizontalBoundaryInput = this.createContinuousHorizontalBoundaryInput();
    const plan: MangaContinuousHorizontalBoundaryPlan = this.mangaContinuousHorizontalBoundaryPlanner.buildPlan(input);
    this.applyContinuousHorizontalBoundaryPlan(plan, input.now);
  }

  private createContinuousHorizontalBoundaryInput(): MangaContinuousHorizontalBoundaryInput {
    const input: MangaContinuousHorizontalBoundaryInput = new MangaContinuousHorizontalBoundaryInput();
    input.isContinuousScrollMode = this.isContinuousScrollMode();
    input.hasChapter = !!this.chapter;
    input.hasChapterChangeCallback = !!this.callbacks.onChapterChange;
    input.suppressedUntil = this.continuousHorizontalBoundarySuppressUntil;
    input.now = Date.now();
    input.viewportWidth = this.getContinuousHorizontalViewportWidth();
    input.maxScrollX = this.getContinuousHorizontalMaxScroll();
    input.scrollPosition = this.scrollPosition;
    input.isOnlineContent = this.isOnlineWebtoonContent();
    input.isRtl = this.isContinuousHorizontalRTL();
    input.atFirstPage = this.viewCurrentPageIndex <= 0;
    input.atLastPage = this.chapter && this.chapter.pages
      ? this.viewCurrentPageIndex >= this.chapter.pages.length - 1
      : false;
    input.isFirstChapter = this.isFirstChapter;
    input.isLastChapter = this.isLastChapter;
    input.lastScrollDirection = this.lastScrollDirection;
    input.lastPrevRequestAt = this.lastPrevAdjacentRequestAt;
    input.lastNextRequestAt = this.lastNextAdjacentRequestAt;
    input.adjacentRequestIntervalMs = this.getWebtoonAdjacentRequestIntervalMs();
    return input;
  }

  private applyContinuousHorizontalBoundaryPlan(plan: MangaContinuousHorizontalBoundaryPlan, now: number): void {
    if (!plan.shouldRun) {
      return;
    }
    const chapterId: string = this.currentChapterId.length > 0 ? this.currentChapterId : this.chapter.id;
    if (plan.nextBlockedByBoundary) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_next_boundary_blocked',
        `nearLeft=${plan.nearLeftEdge}, nearRight=${plan.nearRightEdge}, isLastChapter=${this.isLastChapter}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.prevBlockedByBoundary) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_prev_boundary_blocked',
        `nearLeft=${plan.nearLeftEdge}, nearRight=${plan.nearRightEdge}, isFirstChapter=${this.isFirstChapter}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.nextBlockedByCooldown) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_next_cooldown_rejected',
        `now=${now}, lastNextRequestAt=${this.lastNextAdjacentRequestAt}, threshold=${plan.threshold}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.prevBlockedByCooldown) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_prev_cooldown_rejected',
        `now=${now}, lastPrevRequestAt=${this.lastPrevAdjacentRequestAt}, threshold=${plan.threshold}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.shouldRequestNext) {
      if (plan.shouldUpdateNextRequestTime) {
        this.lastNextAdjacentRequestAt = now;
      }
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_RECOVERED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_request_next',
        `nearLeft=${plan.nearLeftEdge}, nearRight=${plan.nearRightEdge}, threshold=${plan.threshold}`,
        MangaReadFlowSeverity.INFO
      );
      this.callbacks.onChapterChange('next');
      return;
    }
    if (plan.shouldRequestPrev) {
      if (plan.shouldUpdatePrevRequestTime) {
        this.lastPrevAdjacentRequestAt = now;
      }
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_RECOVERED,
        chapterId,
        this.viewCurrentPageIndex,
        'continuous_horizontal_request_prev',
        `nearLeft=${plan.nearLeftEdge}, nearRight=${plan.nearRightEdge}, threshold=${plan.threshold}`,
        MangaReadFlowSeverity.INFO
      );
      this.callbacks.onChapterChange('prev');
    }
  }

  /**
   * 判断是否为单页模式
   */
  private isSinglePageMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
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
   * 判断当前屏幕是否为横屏模式
   * 用于双页模式下调整图片显示方式
   */
  private isLandscapeScreen(): boolean {
    // 如果屏幕宽度大于高度，则为横屏
    if (this.screenWidth > 0 && this.screenHeight > 0) {
      return this.screenWidth > this.screenHeight;
    }
    // 默认返回false（竖屏）
    return false;
  }

  private getDoublePageVerticalDirection(): DoublePageVerticalDirection {
    return this.readingSettings.doublePageVerticalDirection ?? DoublePageVerticalDirection.TOP_TO_BOTTOM;
  }

  private isSinglePageVerticalPagingMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE &&
        this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM);
  }

  private isDoublePageVerticalPortraitMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      !this.isLandscapeScreen() &&
      this.isVerticalPortraitLayout();
  }

  private isDoublePageVerticalNextAtTop(): boolean {
    return this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP;
  }

  private shouldUseSmartDoublePageLayout(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      !this.isDoublePageVerticalPortraitMode();
  }

  private getDoublePageSmartDimensions(pageIndex: number): PageDimensionsInfo | null {
    if (!this.chapter || !this.chapter.pages || pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return null;
    }

    const page: MangaPage = this.chapter.pages[pageIndex];
    const stateDimensions: PageDimensionsInfo | null = DoublePageSmartLayoutHelper.resolvePageDimensionsFromMetadata(page);
    if (stateDimensions) {
      return stateDimensions;
    }

    const loadState: ImageLoadState | undefined = this.getPageLoadState(page);
    if (loadState && loadState.dimensions && loadState.dimensions.width > 0 && loadState.dimensions.height > 0) {
      return {
        width: loadState.dimensions.width,
        height: loadState.dimensions.height
      } as PageDimensionsInfo;
    }

    const pixelMap: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    if (!pixelMap) {
      return null;
    }

    try {
      const imageInfo = pixelMap.getImageInfoSync();
      if (imageInfo && imageInfo.size && imageInfo.size.width > 0 && imageInfo.size.height > 0) {
        return {
          width: imageInfo.size.width,
          height: imageInfo.size.height
        } as PageDimensionsInfo;
      }
    } catch (_error) {
    }

    return null;
  }

  private resolveDoublePageSmartPlanForIndex(pageIndex: number): DoublePageSmartDisplayPlan {
    if (!this.chapter || !this.chapter.pages) {
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

    const isRtl: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolvePlanAtIndex(
      this.chapter.pages,
      pageIndex,
      isRtl,
      (targetPageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(targetPageIndex)
    );
  }

  private resolvePreviousDoublePageSmartPlan(pageIndex: number): DoublePageSmartDisplayPlan {
    if (!this.chapter || !this.chapter.pages) {
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

    const isRtl: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolvePreviousPlan(
      this.chapter.pages,
      pageIndex,
      isRtl,
      (targetPageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(targetPageIndex)
    );
  }

  private resolveNextDoublePageSmartPlan(pageIndex: number): DoublePageSmartDisplayPlan {
    if (!this.chapter || !this.chapter.pages) {
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

    const isRtl: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    return DoublePageSmartLayoutHelper.resolveNextPlan(
      this.chapter.pages,
      pageIndex,
      isRtl,
      (targetPageIndex: number): PageDimensionsInfo | null => this.getDoublePageSmartDimensions(targetPageIndex)
    );
  }

  private isDoublePageSingleDisplayActive(): boolean {
    return this.currentDoublePageDisplayMode === DoublePageSmartDisplayMode.SINGLE;
  }

  private getVerticalDoublePageViewportHeight(): number {
    return this.screenHeight > 0 ? this.screenHeight : 780;
  }

  private getVerticalDoublePageMaxScroll(): number {
    if (!this.isDoublePageVerticalPortraitMode() || !this.chapter || !this.chapter.pages) {
      return 0;
    }

    const contentHeight: number = this.getVerticalDoublePageContentHeight();
    return Math.max(0, contentHeight - this.getVerticalDoublePageViewportHeight());
  }

  private getVerticalDoublePageStartScrollOffset(): number {
    const maxScroll: number = this.getVerticalDoublePageMaxScroll();
    return this.isDoublePageVerticalNextAtTop() ? maxScroll : 0;
  }

  private syncVerticalDoublePageScrollOffset(): number {
    const nextOffset: number = this.clampVerticalDoublePageScrollOffset(this.verticalDoublePageScrollOffset);
    this.verticalDoublePageScrollOffset = nextOffset;
    return nextOffset;
  }

  private resetVerticalDoublePageBoundaryState(clearAction: boolean = true): void {
    this.verticalDoublePageBoundaryAccumulator = 0;
    this.verticalDoublePageBoundaryDirection = '';
    this.verticalDoublePageEdgeHintProgress = 0;
    if (clearAction) {
      this.verticalDoublePageTurnAction = null;
    }
  }

  private syncVerticalDoublePagePositionForCurrentPair(animate: boolean = false): void {
    if (!this.isDoublePageVerticalPortraitMode()) {
      return;
    }

    const targetOffset: number = this.getVerticalDoublePageStartScrollOffset();
    this.verticalDoublePageScrollOffset = targetOffset;
    this.verticalDoublePageLastScrollDeltaY = 0;
    this.verticalDoublePageProgrammaticScrollUntil = Date.now() + (animate ? 320 : 180);
    this.translateY = 0;
    this.resetVerticalDoublePageBoundaryState(false);
  }

  private getVerticalDoublePageBoundaryAction(boundaryDirection: 'top' | 'bottom'): 'next' | 'prev' {
    if (boundaryDirection === 'top') {
      return this.isDoublePageVerticalNextAtTop() ? 'next' : 'prev';
    }
    return this.isDoublePageVerticalNextAtTop() ? 'prev' : 'next';
  }

  private getVerticalDoublePageActionOrigin(action: 'next' | 'prev'): 'top' | 'bottom' {
    if (action === 'next') {
      return this.isDoublePageVerticalNextAtTop() ? 'top' : 'bottom';
    }
    return this.isDoublePageVerticalNextAtTop() ? 'bottom' : 'top';
  }

  private resolveVerticalDoublePageTurnAction(): 'next' | 'prev' {
    if (this.verticalDoublePageTurnAction) {
      return this.verticalDoublePageTurnAction;
    }
    if (this.pageTurnDirection === 'down') {
      return this.isDoublePageVerticalNextAtTop() ? 'next' : 'prev';
    }
    return this.isDoublePageVerticalNextAtTop() ? 'prev' : 'next';
  }

  private getVerticalDoublePageTurnDirection(action: 'next' | 'prev'): 'up' | 'down' {
    return this.getVerticalDoublePageActionOrigin(action) === 'top' ? 'down' : 'up';
  }

  private getVerticalDoublePagePullProgress(): number {
    return Math.min(1.0, Math.abs(this.translateY) / MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_MAX_PULL_VP);
  }

  private getVerticalDoublePageActivePreviewRole(): 'prev' | 'next' | '' {
    const action: 'next' | 'prev' | null = this.verticalDoublePageTurnAction;
    if (!this.isDoublePageVerticalPortraitMode() || !action) {
      return '';
    }
    if (this.isPageTurning || this.isCommittingPageTurn) {
      return '';
    }
    if (Math.abs(this.translateY) > 0.5) {
      return action;
    }
    return '';
  }

  private getVerticalDoublePagePreviewOpacity(role: 'prev' | 'next'): number {
    const activeRole: 'prev' | 'next' | '' = this.getVerticalDoublePageActivePreviewRole();
    if (role !== activeRole) {
      return 0.0;
    }
    if (this.isPageTurning || this.isCommittingPageTurn) {
      return Math.max(0.0, 1.0 - this.pageTurnProgress);
    }
    const progress: number = this.getVerticalDoublePagePullProgress();
    if (progress <= 0.34) {
      return 0.0;
    }
    const previewProgress: number = Math.min(1.0, (progress - 0.34) / 0.66);
    return previewProgress * 0.52;
  }

  private getVerticalDoublePagePreviewTranslateY(role: 'prev' | 'next'): number {
    const activeRole: 'prev' | 'next' | '' = this.getVerticalDoublePageActivePreviewRole();
    if (role !== activeRole) {
      return 0;
    }

    if (this.isPageTurning || this.isCommittingPageTurn) {
      const travel: number = this.getVerticalDoublePageViewportHeight() * 0.08 * this.pageTurnProgress;
      return this.pageTurnDirection === 'down' ? travel : -travel;
    }

    const action: 'next' | 'prev' | null = this.verticalDoublePageTurnAction;
    if (!action) {
      return 0;
    }

    const hiddenOffset: number = this.getVerticalDoublePageViewportHeight() * 0.88;
    const visibleOffset: number = hiddenOffset * this.getVerticalDoublePagePullProgress();
    return this.getVerticalDoublePageActionOrigin(action) === 'top'
      ? -hiddenOffset + visibleOffset
      : hiddenOffset - visibleOffset;
  }

  private getVerticalDoublePagePreviewScale(role: 'prev' | 'next'): number {
    const activeRole: 'prev' | 'next' | '' = this.getVerticalDoublePageActivePreviewRole();
    if (role !== activeRole) {
      return 1.0;
    }
    if (this.isPageTurning || this.isCommittingPageTurn) {
      return 1.0 - this.pageTurnProgress * 0.018;
    }
    return 0.985 + this.getVerticalDoublePagePullProgress() * 0.015;
  }

  private getVerticalDoublePageContentScaleFactor(): number {
    if (!this.isDoublePageVerticalPortraitMode() || this.isPageTurning || this.isCommittingPageTurn) {
      return 1.0;
    }
    return 1.0 - this.getVerticalDoublePagePullProgress() * 0.01;
  }

  private triggerVerticalDoublePageBoundaryTurn(action: 'next' | 'prev'): boolean {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return false;
    }
    if (this.pageChangeCommitted || this.isPageTurning || this.isCommittingPageTurn) {
      return false;
    }

    const maxIndex: number = this.chapter.pages.length - 1;
    const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    const targetPairStart: number = action === 'next' ? nextPairStart : prevPairStart;
    const canTurn: boolean = action === 'next' ? targetPairStart > pairStart : targetPairStart < pairStart;

    this.verticalDoublePageBoundaryLastTime = Date.now();

    if (!canTurn) {
      this.animateToPosition(0, 0);
      this.resetVerticalDoublePageBoundaryState();
      this.suppressExternalIndex = false;
      if (this.callbacks.onChapterChange) {
        this.callbacks.onChapterChange(action);
      }
      return true;
    }

    this.pageChangeCommitted = true;
    this.swipeTriggered = true;
    this.isCommittingPageTurn = true;
    this.verticalDoublePageTurnAction = action;
    this.verticalDoublePageReleasePullY = this.translateY;
    this.pageTurnDirection = this.getVerticalDoublePageTurnDirection(action);
    this.translateX = 0;
    this.translateY = 0;
    this.viewCurrentPageIndex = targetPairStart;
    this.suppressExternalIndex = false;
    this.resetVerticalDoublePageBoundaryState(false);
    this.updateDoublePageIndices();
    this.updateDoublePageDisplay();
    this.updateDoublePagePreview();
    this.syncVerticalDoublePagePositionForCurrentPair(false);
    this.preloadDoublePageNeighbors();
    this.ensureDoublePageImagesPreloaded();
    this.updateVerticalDoublePageRenderSlots();
    this.animatePageTurn();
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetPairStart);
    }
    logger.info(TAG, `双页竖向边界翻页: action=${action}, pair=${pairStart} -> ${targetPairStart}, view=${this.viewCurrentPageIndex}, prop旧值=${this.currentPageIndex}, direction=${this.pageTurnDirection}`);
    setTimeout(() => { this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
    if (!this.showSoftTransitionOverlay) {
      setTimeout(() => { this.isCommittingPageTurn = false; }, 260);
    }
    return true;
  }

  private forceRefreshVerticalDoublePageCurrentPair(reason: string): void {
    if (!this.isDoublePageVerticalPortraitMode()) {
      return;
    }
    this.syncVerticalDoublePagePositionForCurrentPair(false);
    this.updateDoublePageIndices();
    this.updateDoublePageDisplay();
    this.updateDoublePagePreview();
    this.renderEpoch = this.renderEpoch + 1;
    this.updateVerticalDoublePageRenderSlots();
    logger.debug(TAG, `双页竖向强制刷新当前页组: reason=${reason}, view=${this.viewCurrentPageIndex}, left=${this.leftPageIndex}, right=${this.rightPageIndex}, epoch=${this.renderEpoch}`);
  }

  private handleVerticalDoublePageBoundaryInteraction(rawDeltaY: number, previousOffsetY: number, absoluteOffsetY: number): boolean {
    if (!this.isDoublePageVerticalPortraitMode()) {
      return false;
    }
    if (this.currentScale > 1.0 || this.isPageTurning || this.isCommittingPageTurn) {
      this.resetVerticalDoublePageBoundaryState();
      return false;
    }
    if (!Number.isFinite(rawDeltaY) || Math.abs(rawDeltaY) < 0.1) {
      return false;
    }

    const now: number = Date.now();
    if (now - this.verticalDoublePageBoundaryLastTime < MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_COOLDOWN_MS) {
      return false;
    }

    const edgeTolerance: number = MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_TOLERANCE_VP;
    const maxScroll: number = this.getVerticalDoublePageMaxScroll();
    const wasAtBottom: boolean = previousOffsetY >= Math.max(0, maxScroll - edgeTolerance);
    const isAtBottom: boolean = absoluteOffsetY >= Math.max(0, maxScroll - edgeTolerance);
    const wasAtTop: boolean = previousOffsetY <= edgeTolerance;
    const isAtTop: boolean = absoluteOffsetY <= edgeTolerance;

    let boundaryDirection: 'top' | 'bottom' | '' = '';
    if (rawDeltaY > 0 && wasAtBottom && isAtBottom) {
      boundaryDirection = 'bottom';
    } else if (rawDeltaY < 0 && wasAtTop && isAtTop) {
      boundaryDirection = 'top';
    }

    if (boundaryDirection === '') {
      this.resetVerticalDoublePageBoundaryState();
      return false;
    }

    if (this.verticalDoublePageBoundaryDirection !== boundaryDirection) {
      this.verticalDoublePageBoundaryDirection = boundaryDirection;
      this.verticalDoublePageBoundaryAccumulator = 0;
    }

    this.verticalDoublePageBoundaryAccumulator += Math.abs(rawDeltaY);
    this.verticalDoublePageEdgeHintProgress = Math.min(
      1.0,
      this.verticalDoublePageBoundaryAccumulator / MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_TRIGGER_VP
    );
    const pendingAction: 'next' | 'prev' = this.getVerticalDoublePageBoundaryAction(boundaryDirection);
    this.verticalDoublePageTurnAction = pendingAction;
    const pullAccumulator: number = Math.max(
      0,
      this.verticalDoublePageBoundaryAccumulator - MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_HINT_VP
    );
    const pullDistance: number = Math.min(
      MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_MAX_PULL_VP,
      pullAccumulator * 1.15
    );
    this.translateY = boundaryDirection === 'top' ? pullDistance : -pullDistance;

    return true;
  }

  private handleVerticalDoublePageScrollStop(): void {
    if (!this.isDoublePageVerticalPortraitMode()) {
      return;
    }
    if (this.currentScale > 1.0) {
      this.verticalDoublePageLastScrollDeltaY = 0;
      this.resetVerticalDoublePageBoundaryState();
      return;
    }
    if (this.isPageTurning || this.isCommittingPageTurn) {
      this.verticalDoublePageLastScrollDeltaY = 0;
      return;
    }

    const now: number = Date.now();
    if (now < this.verticalDoublePageProgrammaticScrollUntil) {
      logger.debug(TAG, '双页竖向滚动结束来自程序同步，忽略边界翻页检测');
      this.verticalDoublePageLastScrollDeltaY = 0;
      this.resetVerticalDoublePageBoundaryState();
      return;
    }

    const absoluteOffsetY: number = this.syncVerticalDoublePageScrollOffset();
    const maxScroll: number = this.getVerticalDoublePageMaxScroll();
    const edgeTolerance: number = MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_TOLERANCE_VP;
    const atTop: boolean = absoluteOffsetY <= edgeTolerance;
    const atBottom: boolean = absoluteOffsetY >= Math.max(0, maxScroll - edgeTolerance);

    let boundaryDirection: 'top' | 'bottom' | '' = this.verticalDoublePageBoundaryDirection;
    if (boundaryDirection === '' && atTop && this.verticalDoublePageLastScrollDeltaY < -0.1) {
      boundaryDirection = 'top';
    } else if (boundaryDirection === '' && atBottom && this.verticalDoublePageLastScrollDeltaY > 0.1) {
      boundaryDirection = 'bottom';
    }

    logger.debug(TAG, `双页竖向滚动结束: offset=${absoluteOffsetY.toFixed(1)}, max=${maxScroll.toFixed(1)}, lastDelta=${this.verticalDoublePageLastScrollDeltaY.toFixed(1)}, atTop=${atTop}, atBottom=${atBottom}, boundary=${boundaryDirection}`);

    if (boundaryDirection === '') {
      if (!this.isPageTurning && !this.isCommittingPageTurn) {
        this.translateY = 0;
        this.verticalDoublePageTurnAction = null;
      }
      this.verticalDoublePageLastScrollDeltaY = 0;
      this.resetVerticalDoublePageBoundaryState();
      return;
    }

    if (this.verticalDoublePageBoundaryAccumulator < MangaViewer.VERTICAL_DOUBLE_PAGE_EDGE_TRIGGER_VP) {
      this.animateToPosition(0, 0);
      this.verticalDoublePageLastScrollDeltaY = 0;
      this.resetVerticalDoublePageBoundaryState();
      return;
    }

    const action: 'next' | 'prev' = this.getVerticalDoublePageBoundaryAction(boundaryDirection);
    this.verticalDoublePageTurnAction = action;
    if (!this.triggerVerticalDoublePageBoundaryTurn(action)) {
      this.animateToPosition(0, 0);
      this.resetVerticalDoublePageBoundaryState();
    }
    this.verticalDoublePageLastScrollDeltaY = 0;
  }

  /**
   * 获取翻页方向
   */
  private getPageDirection(): 'horizontal' | 'vertical' {
    if (this.isSinglePageVerticalPagingMode() ||
      this.isDoublePageVerticalPortraitMode() ||
      this.isWebtoonMode()) {
      return 'vertical';
    }
    return 'horizontal';
  }

  private isSoftNonePageTurn(): boolean {
    return this.readingSettings.pageTurnAnimation === PageTurnAnimationType.NONE;
  }

  private shouldUseAlbumNoneTransition(): boolean {
    return this.isSoftNonePageTurn() && this.isSinglePageMode() && !this.isWebtoonMode() && this.currentScale <= 1.0;
  }

  private shouldUseSoftNoneCrossfade(): boolean {
    return false;
  }

  private getViewerModeKey(): string {
    return this.readingSettings && this.readingSettings.readingMode !== undefined
      ? String(this.readingSettings.readingMode)
      : 'default';
  }

  private getViewerContainerKey(): string {
    const modeKey: string = this.getViewerModeKey();
    if (this.isWebtoonMode()) {
      return `webtoon_${modeKey}`;
    }
    if (this.shouldUseAlbumNoneTransition()) {
      return `single_none_${modeKey}`;
    }
    return `${modeKey}_${this.viewCurrentPageIndex}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}`;
  }

  private getSinglePageContentKey(page: MangaPage): string {
    const pixelEpoch: number = this.getPixelMapEpoch(page.id);
    const sourceState: string = this.pagePixelMaps.has(page.id) ? 'pm' : 'url';
    if (this.shouldUseAlbumNoneTransition()) {
      return `${page.id}_${pixelEpoch}_${sourceState}`;
    }
    return `${page.id}_${this.viewCurrentPageIndex}_${this.renderEpoch}_${pixelEpoch}_${sourceState}`;
  }

  private getVerticalDoublePageCurrentContentKey(): string {
    return this.verticalDoubleCurrentContentKey;
  }

  private usesAlbumNoneVerticalAxis(): boolean {
    return this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE &&
        this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM);
  }

  private getAlbumNoneTravelDistanceX(): number {
    return this.screenWidth > 0 ? this.screenWidth : 360;
  }

  private getAlbumNoneTravelDistanceY(): number {
    return this.screenHeight > 0 ? this.screenHeight : 780;
  }

  private hasAlbumNonePrevReveal(): boolean {
    if (!this.shouldUseAlbumNoneTransition() || this.previewPrevPageId.length === 0) {
      return false;
    }
    if (this.usesAlbumNoneVerticalAxis()) {
      return this.translateY > 0.5;
    }
    return this.translateX > 0.5;
  }

  private hasAlbumNoneNextReveal(): boolean {
    if (!this.shouldUseAlbumNoneTransition() || this.previewNextPageId.length === 0) {
      return false;
    }
    if (this.usesAlbumNoneVerticalAxis()) {
      return this.translateY < -0.5;
    }
    return this.translateX < -0.5;
  }

  private getPrevOverlayTranslateX(): number {
    if (!this.shouldUseAlbumNoneTransition()) {
      return 0;
    }
    if (this.usesAlbumNoneVerticalAxis()) {
      return 0;
    }
    const travelDistance = this.getAlbumNoneTravelDistanceX();
    return this.hasAlbumNonePrevReveal() ? this.translateX - travelDistance : -travelDistance;
  }

  private getPrevOverlayTranslateY(): number {
    if (!this.shouldUseAlbumNoneTransition()) {
      return 0;
    }
    if (!this.usesAlbumNoneVerticalAxis()) {
      return 0;
    }
    const travelDistance = this.getAlbumNoneTravelDistanceY();
    return this.hasAlbumNonePrevReveal() ? this.translateY - travelDistance : -travelDistance;
  }

  private getNextOverlayTranslateX(): number {
    if (!this.shouldUseAlbumNoneTransition()) {
      return 0;
    }
    if (this.usesAlbumNoneVerticalAxis()) {
      return 0;
    }
    const travelDistance = this.getAlbumNoneTravelDistanceX();
    return this.hasAlbumNoneNextReveal() ? this.translateX + travelDistance : travelDistance;
  }

  private getNextOverlayTranslateY(): number {
    if (!this.shouldUseAlbumNoneTransition()) {
      return 0;
    }
    if (!this.usesAlbumNoneVerticalAxis()) {
      return 0;
    }
    const travelDistance = this.getAlbumNoneTravelDistanceY();
    return this.hasAlbumNoneNextReveal() ? this.translateY + travelDistance : travelDistance;
  }

  private getAlbumNoneSettleDuration(currentOffset: number, travelDistance: number, isCommit: boolean): number {
    const safeTravelDistance = travelDistance > 0 ? travelDistance : 1;
    const progress = Math.min(1.0, Math.abs(currentOffset) / safeTravelDistance);
    if (isCommit) {
      const remaining = Math.max(0.0, 1.0 - progress);
      const easedRemaining = Math.pow(remaining, 0.82);
      const shallowReleaseBonus = progress < 0.40
        ? Math.floor((0.40 - progress) * 140)
        : 0;
      const commitDuration = Math.floor(190 + 120 * easedRemaining) + shallowReleaseBonus;
      return Math.max(190, Math.min(360, commitDuration));
    }
    return Math.max(120, Math.floor(220 * Math.max(0.22, progress)));
  }

  private animateAlbumNoneCancel(): void {
    const isVertical = this.usesAlbumNoneVerticalAxis();
    const currentOffset = isVertical ? this.translateY : this.translateX;
    const travelDistance = isVertical ? this.getAlbumNoneTravelDistanceY() : this.getAlbumNoneTravelDistanceX();
    const duration = this.getAlbumNoneSettleDuration(currentOffset, travelDistance, false);
    this.isPageTurning = true;
    this.pageChangeCommitted = false;
    this.isCommittingPageTurn = true;
    this.currentAnimationType = PageTurnAnimationType.NONE;
    this.resetSoftTransitionOverlay();
    if (!this.uiContext) {
      this.translateX = 0;
      this.translateY = 0;
      this.isPageTurning = false;
      this.pageTurnDirection = null;
      this.isCommittingPageTurn = false;
      return;
    }
    this.uiContext.animateTo({
      duration: duration,
      curve: curves.initCurve(Curve.FastOutSlowIn),
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        this.translateX = 0;
        this.translateY = 0;
        this.isPageTurning = false;
        this.pageTurnDirection = null;
        this.isCommittingPageTurn = false;
        this.currentAnimationType = PageTurnAnimationType.NONE;
      }
    }, () => {
      this.translateX = 0;
      this.translateY = 0;
    });
  }

  private getAlbumNoneCommittedTranslateX(direction: 'left' | 'right' | 'up' | 'down'): number {
    const travelDistance = this.getAlbumNoneTravelDistanceX();
    if (direction === 'left') {
      return this.translateX + travelDistance;
    }
    if (direction === 'right') {
      return this.translateX - travelDistance;
    }
    return 0;
  }

  private getAlbumNoneCommittedTranslateY(direction: 'left' | 'right' | 'up' | 'down'): number {
    const travelDistance = this.getAlbumNoneTravelDistanceY();
    if (direction === 'up') {
      return this.translateY + travelDistance;
    }
    if (direction === 'down') {
      return this.translateY - travelDistance;
    }
    return 0;
  }

  private commitAlbumNoneTargetPage(targetIndex: number, direction: 'left' | 'right' | 'up' | 'down'): boolean {
    if (!this.chapter || !this.chapter.pages || targetIndex < 0 || targetIndex >= this.chapter.pages.length) {
      return false;
    }
    const committedTranslateX = this.getAlbumNoneCommittedTranslateX(direction);
    const committedTranslateY = this.getAlbumNoneCommittedTranslateY(direction);
    this.viewCurrentPageIndex = targetIndex;
    this.suppressExternalIndex = true;
    this.currentPageIndex = targetIndex;
    this.updateSinglePageDisplay();
    this.translateX = committedTranslateX;
    this.translateY = committedTranslateY;
    this.updateSinglePagePreview();
    this.loadCurrentAndNeighborPages();
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(targetIndex);
    }
    return true;
  }

  private completeAlbumNonePageTurn(): void {
    this.translateX = 0;
    this.translateY = 0;
    this.isPageTurning = false;
    this.pageTurnDirection = null;
    this.pageTurnProgress = 0;
    this.currentAnimationType = PageTurnAnimationType.NONE;
    this.isCommittingPageTurn = false;
    this.resetSoftTransitionOverlay();
    setTimeout(() => { this.suppressExternalIndex = false; }, 0);
    setTimeout(() => { this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
  }

  private startAlbumNoneCommit(targetIndex: number, direction: 'left' | 'right' | 'up' | 'down'): void {
    if (!this.chapter || !this.chapter.pages || targetIndex < 0 || targetIndex >= this.chapter.pages.length) {
      this.animateAlbumNoneCancel();
      return;
    }
    const targetPage: MangaPage = this.chapter.pages[targetIndex];
    const targetLoadState: ImageLoadState | undefined = this.getPageLoadState(targetPage);
    const hasPixelMap: boolean = this.pagePixelMaps.has(targetPage.id);
    if (!hasPixelMap && (!targetLoadState || !targetLoadState.isLoading)) {
      this.loadImage(targetPage);
    }
    this.ensurePixelMapLoaded(targetPage).catch((_e: Error) => {});
    this.pageChangeCommitted = true;
    this.isPageTurning = true;
    this.isCommittingPageTurn = true;
    this.pageTurnDirection = direction;
    this.currentAnimationType = PageTurnAnimationType.NONE;
    this.resetSoftTransitionOverlay();

    const isHorizontal: boolean = direction === 'left' || direction === 'right';
    const travelDistance: number = isHorizontal ? this.getAlbumNoneTravelDistanceX() : this.getAlbumNoneTravelDistanceY();
    const releaseOffset: number = isHorizontal ? this.translateX : this.translateY;
    const releaseProgress = Math.min(1.0, Math.abs(releaseOffset) / Math.max(travelDistance, 1));
    const duration = this.getAlbumNoneSettleDuration(releaseOffset, travelDistance, true);
    const settleCurve: Curve = releaseProgress < 0.40 ? Curve.EaseOut : Curve.FastOutSlowIn;

    if (!this.commitAlbumNoneTargetPage(targetIndex, direction)) {
      this.animateAlbumNoneCancel();
      return;
    }

    if (!this.uiContext) {
      this.completeAlbumNonePageTurn();
      return;
    }
    this.uiContext.animateTo({
      duration: duration,
      curve: curves.initCurve(settleCurve),
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        this.completeAlbumNonePageTurn();
      }
    }, () => {
      this.translateX = 0;
      this.translateY = 0;
    });
  }

  private handleAlbumNonePageTurn(thresholdX: number, thresholdY: number): boolean {
    if (!this.shouldUseAlbumNoneTransition()) {
      return false;
    }
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      this.animateAlbumNoneCancel();
      return true;
    }

    if (this.usesAlbumNoneVerticalAxis()) {
      if (Math.abs(this.translateY) <= thresholdY) {
        this.animateAlbumNoneCancel();
        return true;
      }
      if (this.translateY > 0) {
        if (this.viewCurrentPageIndex > 0) {
          this.startAlbumNoneCommit(this.viewCurrentPageIndex - 1, 'down');
        } else {
          if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('prev');
          }
          this.animateAlbumNoneCancel();
        }
        return true;
      }
      if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
        this.startAlbumNoneCommit(this.viewCurrentPageIndex + 1, 'up');
      } else {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('next');
        }
        this.animateAlbumNoneCancel();
      }
      return true;
    }

    if (Math.abs(this.translateX) <= thresholdX) {
      this.animateAlbumNoneCancel();
      return true;
    }

    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE &&
        this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);

    if (isRTL) {
      if (this.translateX > 0) {
        if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
          this.startAlbumNoneCommit(this.viewCurrentPageIndex + 1, 'right');
        } else {
          if (this.callbacks.onChapterChange) {
            this.callbacks.onChapterChange('next');
          }
          this.animateAlbumNoneCancel();
        }
        return true;
      }
      if (this.viewCurrentPageIndex > 0) {
        this.startAlbumNoneCommit(this.viewCurrentPageIndex - 1, 'left');
      } else {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('prev');
        }
        this.animateAlbumNoneCancel();
      }
      return true;
    }

    if (this.translateX > 0) {
      if (this.viewCurrentPageIndex > 0) {
        this.startAlbumNoneCommit(this.viewCurrentPageIndex - 1, 'right');
      } else {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('prev');
        }
        this.animateAlbumNoneCancel();
      }
      return true;
    }

    if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
      this.startAlbumNoneCommit(this.viewCurrentPageIndex + 1, 'left');
    } else {
      if (this.callbacks.onChapterChange) {
        this.callbacks.onChapterChange('next');
      }
      this.animateAlbumNoneCancel();
    }
    return true;
  }

  private getSoftTransitionHoldDelay(): number {
    return 24;
  }

  private getSoftTransitionDuration(): number {
    return 420;
  }

  private updateSoftTransitionTargetTranslate(): void {
    const horizontalOffset: number = Math.max(48, Math.floor(this.screenWidth * 0.22));
    const verticalOffset: number = Math.max(36, Math.floor(this.screenHeight * 0.12));
    this.softTransitionTargetTranslateX = 0;
    this.softTransitionTargetTranslateY = 0;

    if (this.pageTurnDirection === 'left') {
      this.softTransitionTargetTranslateX = -horizontalOffset;
      return;
    }
    if (this.pageTurnDirection === 'right') {
      this.softTransitionTargetTranslateX = horizontalOffset;
      return;
    }
    if (this.pageTurnDirection === 'up') {
      this.softTransitionTargetTranslateY = -verticalOffset;
      return;
    }
    if (this.pageTurnDirection === 'down') {
      this.softTransitionTargetTranslateY = verticalOffset;
    }
  }

  private getSoftTransitionOverlayPage(): MangaPage | null {
    if (this.softTransitionOverlayPageId.length > 0) {
      const overlayPage = this.getPageById(this.softTransitionOverlayPageId);
      if (overlayPage) {
        return overlayPage;
      }
    }
    const currentPage = this.getCurrentPageData().page;
    return currentPage ? currentPage : null;
  }

  private getSoftTransitionOverlayFitMode(): ImageFit {
    const overlayPage = this.getSoftTransitionOverlayPage();
    if (overlayPage) {
      return this.getImageFitMode(overlayPage);
    }
    return ImageFit.Contain;
  }

  private startSoftTransitionOverlay(
    page: MangaPage,
    displayedInput: Resource | string | image.PixelMap
  ): void {
    if (!this.shouldUseSoftNoneCrossfade()) {
      this.resetSoftTransitionOverlay();
      return;
    }
    if (this.softTransitionStartTimer !== -1) {
      clearTimeout(this.softTransitionStartTimer);
      this.softTransitionStartTimer = -1;
    }
    if (this.softTransitionFallbackTimer !== -1) {
      clearTimeout(this.softTransitionFallbackTimer);
      this.softTransitionFallbackTimer = -1;
    }
    this.softTransitionOverlayPageId = page.id;
    this.softTransitionOverlayInput = displayedInput;
    this.softTransitionOverlayOpacity = 1.0;
    this.softTransitionOverlayTranslateX = 0;
    this.softTransitionOverlayTranslateY = 0;
    this.updateSoftTransitionTargetTranslate();
    this.showSoftTransitionOverlay = true;
    this.softTransitionFallbackTimer = setTimeout(() => {
      this.softTransitionFallbackTimer = -1;
      if (this.showSoftTransitionOverlay) {
        this.animateSoftTransitionOverlayOut();
      }
    }, this.getSoftTransitionDuration() + this.getSoftTransitionHoldDelay() + 800);
  }

  private resetSoftTransitionOverlay(): void {
    if (this.softTransitionStartTimer !== -1) {
      clearTimeout(this.softTransitionStartTimer);
      this.softTransitionStartTimer = -1;
    }
    if (this.softTransitionFallbackTimer !== -1) {
      clearTimeout(this.softTransitionFallbackTimer);
      this.softTransitionFallbackTimer = -1;
    }
    this.showSoftTransitionOverlay = false;
    this.softTransitionOverlayOpacity = 0;
    this.softTransitionOverlayTranslateX = 0;
    this.softTransitionOverlayTranslateY = 0;
    this.softTransitionOverlayPageId = '';
    this.softTransitionOverlayInput = $r('app.media.ic_image');
    this.softTransitionTargetTranslateX = 0;
    this.softTransitionTargetTranslateY = 0;
  }

  private completeSoftTransitionOverlayHandoff(): void {
    if (this.softTransitionStartTimer !== -1) {
      clearTimeout(this.softTransitionStartTimer);
      this.softTransitionStartTimer = -1;
    }
    if (!this.showSoftTransitionOverlay) {
      this.isCommittingPageTurn = false;
      return;
    }
    this.softTransitionOverlayOpacity = 0.0;
    this.softTransitionOverlayTranslateX = 0;
    this.softTransitionOverlayTranslateY = 0;
    this.softTransitionStartTimer = setTimeout(() => {
      this.softTransitionStartTimer = -1;
      this.resetSoftTransitionOverlay();
      this.isCommittingPageTurn = false;
    }, 16);
  }

  private scheduleSoftTransitionOverlayOut(): void {
    if (!this.showSoftTransitionOverlay) {
      this.isCommittingPageTurn = false;
      return;
    }
    if (this.isSoftNonePageTurn()) {
      if (this.softTransitionStartTimer !== -1) {
        return;
      }
      this.softTransitionStartTimer = setTimeout(() => {
        this.completeSoftTransitionOverlayHandoff();
      }, 16);
      return;
    }
    if (this.softTransitionOverlayOpacity < 0.99) {
      return;
    }
    if (this.softTransitionStartTimer !== -1) {
      return;
    }
    this.softTransitionStartTimer = setTimeout(() => {
      this.softTransitionStartTimer = -1;
      this.animateSoftTransitionOverlayOut();
    }, this.getSoftTransitionHoldDelay());
  }

  private animateSoftTransitionOverlayOut(): void {
    if (this.softTransitionStartTimer !== -1) {
      clearTimeout(this.softTransitionStartTimer);
      this.softTransitionStartTimer = -1;
    }
    if (!this.showSoftTransitionOverlay) {
      this.isCommittingPageTurn = false;
      return;
    }
    if (this.softTransitionOverlayOpacity <= 0.01) {
      return;
    }
    if (!this.uiContext) {
      this.resetSoftTransitionOverlay();
      this.isCommittingPageTurn = false;
      return;
    }
    if (this.isSoftNonePageTurn()) {
      this.completeSoftTransitionOverlayHandoff();
      return;
    }
    this.uiContext.animateTo({
      duration: this.getSoftTransitionDuration(),
      curve: curves.initCurve(Curve.FastOutSlowIn),
      iterations: 1,
      playMode: PlayMode.Normal,
      onFinish: () => {
        this.resetSoftTransitionOverlay();
        this.isCommittingPageTurn = false;
      }
    }, () => {
      this.softTransitionOverlayOpacity = 0.0;
      this.softTransitionOverlayTranslateX = this.softTransitionTargetTranslateX;
      this.softTransitionOverlayTranslateY = this.softTransitionTargetTranslateY;
    });
  }

  private getPrevOverlayOpacity(): number {
    const isTTB: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    if (this.shouldUseAlbumNoneTransition()) {
      return this.hasAlbumNonePrevReveal() ? 1.0 : 0.0;
    }
    if (this.isCommittingPageTurn) {
      if (this.isSoftNonePageTurn()) {
        return 0.0;
      }
      if (isTTB) {
        return this.pageTurnDirection === 'down' ? 1.0 : 0.0;
      }
      if (isRTL) {
        return this.pageTurnDirection === 'left' ? 1.0 : 0.0;
      }
      return this.pageTurnDirection === 'right' ? 1.0 : 0.0;
    }
    const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
    const thresholdY: number = Math.max(20, Math.floor(this.screenHeight * 0.05));
    if (isTTB) {
      const progress: number = Math.min(1.0, Math.abs(this.translateY) / thresholdY);
      return this.translateY > 0 ? progress : 0.0;
    }
    if (isRTL) {
      const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
      return this.translateX < 0 ? progress : 0.0;
    }
    const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
    return this.translateX > 0 ? progress : 0.0;
  }
  private getNextOverlayOpacity(): number {
    const isTTB: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    if (this.shouldUseAlbumNoneTransition()) {
      return this.hasAlbumNoneNextReveal() ? 1.0 : 0.0;
    }
    if (this.isCommittingPageTurn) {
      if (this.isSoftNonePageTurn()) {
        return 0.0;
      }
      if (isTTB) {
        return this.pageTurnDirection === 'up' ? 1.0 : 0.0;
      }
      if (isRTL) {
        return this.pageTurnDirection === 'right' ? 1.0 : 0.0;
      }
      return this.pageTurnDirection === 'left' ? 1.0 : 0.0;
    }
    const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
    const thresholdY: number = Math.max(20, Math.floor(this.screenHeight * 0.05));
    if (isTTB) {
      const progress: number = Math.min(1.0, Math.abs(this.translateY) / thresholdY);
      return this.translateY < 0 ? progress : 0.0;
    }
    if (isRTL) {
      const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
      return this.translateX > 0 ? progress : 0.0;
    }
    const progress: number = Math.min(1.0, Math.abs(this.translateX) / thresholdX);
    return this.translateX < 0 ? progress : 0.0;
  }

  private getPrevPageIndex(): number {
    const idx: number = this.viewCurrentPageIndex - 1;
    if (!this.chapter || !this.chapter.pages) { return -1; }
    if (idx >= 0 && idx < this.chapter.pages.length) { return idx; }
    return -1;
  }
  private getNextPageIndex(): number {
    const idx: number = this.viewCurrentPageIndex + 1;
    if (!this.chapter || !this.chapter.pages) { return -1; }
    if (idx >= 0 && idx < this.chapter.pages.length) { return idx; }
    return -1;
  }

  private getPageById(pageId: string): MangaPage | undefined {
    return this.mangaPageLoadResolver.resolvePageById(pageId, this.createMangaPageResolveContext());
  }

  private rebuildWebtoonPageRefIndex(): void {
    if (!this.isWebtoonMode() || this.webtoonDataItems.length === 0) {
      this.webtoonPageRefById.clear();
      this.webtoonOrderedPageIds = [];
      this.webtoonVisibleItemIndices = [];
      return;
    }

    const pageRefById: Map<string, WebtoonPageRef> = new Map();
    const orderedPageIds: string[] = [];
    let orderIndex = 0;
    let imageStateChanged = false;

    for (let i = 0; i < this.webtoonDataItems.length; i++) {
      const item = this.webtoonDataItems[i];
      if (item.type !== 'page' || !item.page || !item.page.id) {
        continue;
      }

      const page = item.page;
      const chapterId = item.chapterId || this.chapter.id;
      const chapterPageIndex = item.pageIndex !== undefined ? item.pageIndex : orderIndex;
      pageRefById.set(page.id, {
        page: page,
        chapterId: chapterId,
        chapterPageIndex: chapterPageIndex,
        itemIndex: i,
        orderIndex: orderIndex
      } as WebtoonPageRef);
      orderedPageIds.push(page.id);
      orderIndex++;

      // 确保多章节页面在状态管理器中可追踪
      this.imageLoadStateManager.initPage(page.id, i);
      if (!this.imageLoadStates.has(page.id)) {
        this.imageLoadStates.set(page.id, {
          isLoading: false,
          isLoaded: false
        } as ImageLoadState);
        imageStateChanged = true;
      }
    }

    this.webtoonPageRefById = pageRefById;
    this.webtoonOrderedPageIds = orderedPageIds;
    if (imageStateChanged) {
      this.imageLoadStates = new Map(this.imageLoadStates);
    }
  }

  private resolvePreloadIndexForPage(page: MangaPage): number {
    return this.mangaPageLoadResolver.resolvePreloadIndexForPage(page, this.createMangaPageResolveContext());
  }

  private getCurrentWebtoonItemIndexForPreload(): number {
    return this.mangaPageLoadResolver.getCurrentWebtoonItemIndexForPreload(this.createMangaPageResolveContext());
  }

  private getWebtoonVisibleItemIndicesForPreload(): number[] {
    if (this.webtoonVisibleItemIndices.length > 0) {
      return this.webtoonVisibleItemIndices;
    }
    const fallbackIndex = this.getCurrentWebtoonItemIndexForPreload();
    return fallbackIndex >= 0 ? [fallbackIndex] : [];
  }

  /**
   * 获取图片适配模式
   */
  private getImageFitMode(page: MangaPage): ImageFit {
    // 判断是否为横向页面（宽度大于高度）
    const isLandscape = page.width && page.height && page.width > page.height;

    if (this.isWebtoonMode()) {
      // 条漫模式：以宽度占满并允许放大以适配屏宽
      return ImageFit.Contain;
    } else if (isLandscape && this.isSinglePageMode()) {
      // 单页横向：保持完整显示
      return ImageFit.Contain;
    } else {
      // 其他情况：保持完整显示，按宽度适配
      return ImageFit.Contain;
    }
  }

  private cancelWebtoonStopCleanup(): void {
    if (this.webtoonStopCleanupTimer !== -1) {
      clearTimeout(this.webtoonStopCleanupTimer);
      this.webtoonStopCleanupTimer = -1;
    }
  }

  private scheduleWebtoonStopCleanup(delayMs?: number): void {
    this.cancelWebtoonStopCleanup();
    const finalDelay = delayMs !== undefined
      ? delayMs
      : (this.isOnlineWebtoonContent() ? 900 : 500);
    this.webtoonStopCleanupTimer = setTimeout(() => {
      this.webtoonStopCleanupTimer = -1;
      if (this.isScrolling) {
        return;
      }
      this.cleanupInvisiblePixelMaps();
      this.cleanupDistantChapterResources();
    }, finalDelay);
  }

  /**
   * 构建优化的条漫视图（支持多章节）
   */
  @Builder
  buildWebtoonView() {
    Scroll(this.scroller) {
      Column() {
        // 顶部加载提示（加载上一章时显示，或显示已是第一章提示，或显示双重上滑确认提示）
        if (this.isPrevChapterLoading || this.isFirstChapter || this.prevChapterSwipeConfirmPending) {
          this.buildWebtoonLoadingIndicator('prev')
        }

        // [性能优化] 使用LazyForEach懒加载多章节数据
        if (this.webtoonDataSource.totalCount() > 0) {
          LazyForEach(this.webtoonDataSource, (item: WebtoonDataItem, index: number) => {
            if (item.type === 'chapter_divider') {
              // 章节分隔
              this.buildChapterDivider(item)
            } else if (item.type === 'page' && item.page) {
              // 页面图片（使用章节ID+页面ID作为唯一标识）
              this.buildOptimizedImageForWebtoon(item.page, item.chapterId || '', item.pageIndex !== undefined ? item.pageIndex : index)
            }
          }, (item: WebtoonDataItem, index: number) => {
            // 生成唯一key：章节分隔用direction+chapterId，页面用chapterId+pageId
            if (item.type === 'chapter_divider') {
              return `divider_${item.direction}_${item.chapterId}_${index}`;
            } else {
              return `page_${item.chapterId}_${item.page?.id}_${index}`;
            }
          })
        } else {
          // 回退到单章节模式
          LazyForEach(this.pageDataSource, (page: MangaPage, index: number) => {
            this.buildOptimizedImage(page, index)
          }, (page: MangaPage, index: number) => `${this.chapter.id}_${page.id}_${index}`)
        }

        // 底部加载提示（加载下一章时显示，或显示已是最后一章提示）
        if (this.isNextChapterLoading || this.isLastChapter) {
          this.buildWebtoonLoadingIndicator('next')
        }
      }
      .padding({
        left: `${this.readingSettings.webtoonLeftMargin ?? 0}%`,
        right: `${this.readingSettings.webtoonRightMargin ?? 0}%`
      })
      .scale({ x: this.webtoonZoomScale, y: this.webtoonZoomScale, centerX: this.webtoonScaleCenterX, centerY: this.webtoonScaleCenterY })
      .translate({ x: this.webtoonOffsetX, y: this.webtoonOffsetY })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .onDidScroll((xOffset: number, yOffset: number) => {
      this.handleWebtoonScroll(yOffset);
      // [性能优化] 对重型操作进行节流，避免滚动卡顿
      this.throttledWebtoonHeavyOperations();
    })
    .onScrollStart(() => {
      this.isScrolling = true;
      this.cancelWebtoonStopCleanup();
    })
    .onScrollStop(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      // 条漫模式使用专用的预加载方法
      this.triggerWebtoonPreload();
      this.scheduleWebtoonStopCleanup();
    })
    .gesture(
      // 使用Exclusive模式：双指缩放优先于单指滑动
      // 修复：条漫模式下双指缩放与滚动冲突问题
      GestureGroup(GestureMode.Exclusive,
        // 双指捏合手势（最高优先级）
        PinchGesture({ fingers: 2, distance: 3 })
          .onActionStart((event: GestureEvent) => {
            this.isZooming = true;
            this.initWebtoonPinchCenter(event, false);
            logger.debug(TAG, `条漫双指缩放开始: 初始缩放=${this.webtoonPinchStartScale}, 焦点=(${this.webtoonScaleCenterX}, ${this.webtoonScaleCenterY})`);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.handleWebtoonPinchUpdate(event);
          })
          .onActionEnd(() => {
            this.handleWebtoonPinchEnd();
          }),
        // 单指手势组（缩放状态下拖动 + 边缘滑动）
        GestureGroup(GestureMode.Parallel,
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
            .onActionUpdate((event: GestureEvent) => {
              if (this.webtoonZoomScale > this.MIN_ZOOM_SCALE) {
                this.handleWebtoonPan(event);
              }
            }),
          SwipeGesture({ fingers: 1, direction: SwipeDirection.Horizontal, speed: 100 })
            .onAction((event: GestureEvent) => {
              this.handleEdgeSwipe(event);
            })
        )
      )
    )
  }

  /**
   * 为条漫多章节模式构建优化的图片组件
   * 与buildOptimizedImage类似，但需要传入chapterId以正确关联PixelMap
   * [性能优化] 本地图片使用独立的LocalImageCacheManager缓存
   */
  @Builder
  buildOptimizedImageForWebtoon(page: MangaPage, chapterId: string, pageIndex: number) {
    Stack() {
      // [修复①③] 真实图片只设宽度，不设高度，让图片按原始比例等宽自适应高度
      // 之前设固定 height + ImageFit.Contain 导致图片居中产生上下空白
      if (page.sourceType !== ImageSourceType.LOCAL && this.pagePixelMaps.has(page.id)) {
        Image(this.pagePixelMaps.get(page.id))
          .width('100%')
          .draggable(false)
          .onComplete(() => {
            this.handleWebtoonImageLoad(page, chapterId, pageIndex);
          })
          .onError((error: ImageError) => {
            this.handleImageComponentError(page, error, `webtoon_pixel_${pageIndex}`);
            this.triggerWebtoonImageLoadIfNeeded(page, chapterId, pageIndex);
          })
      } else if (page.sourceType === ImageSourceType.LOCAL) {
        // 本地+条漫专用路径：保持 file:// 数据源稳定，避免 file/cache 源切换闪烁
        this.buildStableLocalImageForWebtoon(page, chapterId, pageIndex)
      } else if (page.sourceType === ImageSourceType.NETWORK) {
        // 网络图片必须通过带请求头的加载链路转成PixelMap后再显示，避免直接URL触发防盗链或缓存错误
        if (!this.getPageLoadState(page)?.error) {
          // 加载中：无占位图，仅触发加载（加载动画由下方统一层处理）
          Column()
            .width('100%')
            .height(this.getEstimatedImageHeight(page))
            .onAppear(() => {
              this.triggerWebtoonImageLoadIfNeeded(page, chapterId, pageIndex);
            })
        } else {
          // 加载失败：无占位图，仅保留高度占位（错误UI由下方统一层处理）
          Column()
            .width('100%')
            .height(this.getEstimatedImageHeight(page))
        }
      } else {
        Image(this.getImageResource(page))
          .width('100%')
          .draggable(false)
          .onAppear(() => {
            this.triggerWebtoonImageLoadIfNeeded(page, chapterId, pageIndex);
          })
          .onComplete(() => {
            this.handleWebtoonImageLoad(page, chapterId, pageIndex);
          })
          .onError((error: ImageError) => {
            this.handleWebtoonImageError(page, chapterId, pageIndex);
          })
      }

      // 加载动画（保留预估高度占位）
      if (this.shouldShowLoadingForPage(page)) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(colorMap.accent)
          Text('加载中...')
            .fontSize(14)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 8 })
        }
        .width('100%')
        .height(this.getEstimatedImageHeight(page))
        .justifyContent(FlexAlign.Center)
      }

      // 加载失败提示（保留预估高度占位）
      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(48)
            .height(48)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(14)
            .fontColor(colorMap.textPrimary)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 8 })
          Text(this.getPageLoadState(page)?.error || '图片加载失败')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button('重试')
            .fontSize(14)
            .fontColor(Color.White)
            .backgroundColor(colorMap.accent)
            .borderRadius(8)
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .margin({ top: 12 })
            .onClick(() => {
              logger.info(TAG, `用户点击重试加载(条漫): pageId=${page.id}`);
              this.retryLoadPage(page);
            })
        }
        .width('100%')
        .height(this.getEstimatedImageHeight(page))
        .justifyContent(FlexAlign.Center)
        .padding(16)
      }
    }
    .width('100%')
  }

  @Builder
  private buildStableLocalImageForWebtoon(page: MangaPage, chapterId: string, pageIndex: number) {
    Image(this.getImageResource(page))
      .key(`local_webtoon_${page.id}`)
      .width('100%')
      .draggable(false)
      .onAppear(() => {
        // 本地缓存仅用于后台预热，不回写到当前条目渲染源
        this.triggerLocalImageLoad(page, chapterId, pageIndex);
      })
      .onComplete(() => {
        this.handleWebtoonImageLoad(page, chapterId, pageIndex);
      })
      .onError((_error: ImageError) => {
        this.handleWebtoonImageError(page, chapterId, pageIndex);
      })
      .transition(TransitionEffect.IDENTITY)
  }

  /**
   * [性能修复] 根据 pageId 查找在 webtoonDataSource 中的索引
   * 用于 notifyDataChange 精准刷新单个 LazyForEach 项
   */
  private findWebtoonDataIndex(pageId: string): number {
    const totalCount = this.webtoonDataSource.totalCount();
    for (let i = 0; i < totalCount; i++) {
      const item = this.webtoonDataSource.getData(i);
      if (item.type === 'page' && item.page && item.page.id === pageId) {
        return i;
      }
    }
    return -1;
  }

  /**
   * [性能优化] 条漫模式触发图片加载（带去重检查）
   */
  private triggerWebtoonImageLoadIfNeeded(page: MangaPage, chapterId: string, pageIndex: number): void {
    // 检查是否已有PixelMap
    if (this.pagePixelMaps.has(page.id)) {
      return;
    }

    // 在线条漫统一走预加载队列，避免与 ensurePixelMapLoaded 并发竞争
    if (this.isWebtoonMode() && page.sourceType === ImageSourceType.NETWORK) {
      this.queueWebtoonNetworkPageLoad(page, pageIndex);
      return;
    }

    // 其他类型仍沿用原逻辑
    this.loadImage(page);
  }

  private queueWebtoonNetworkPageLoad(page: MangaPage, pageIndexHint: number = -1): void {
    if (!this.isWebtoonMode() || page.sourceType !== ImageSourceType.NETWORK) {
      return;
    }
    if (!page.imageUrl || page.imageUrl.length === 0) {
      return;
    }
    if (this.pagePixelMaps.has(page.id)) {
      return;
    }
    if (this.imageLoadStateManager.isLoading(page.id) || this.imageLoadStateManager.isCompleted(page.id)) {
      return;
    }

    const preloadIndex: number = this.mangaPageLoadResolver.resolveWebtoonQueueIndex(
      page,
      pageIndexHint,
      this.createMangaPageResolveContext()
    );
    if (preloadIndex < 0) {
      return;
    }

    const currentIndex: number = this.getCurrentWebtoonItemIndexForPreload();
    const input: MangaSinglePagePreloadInput = new MangaSinglePagePreloadInput();
    input.page = page;
    input.pageIndex = preloadIndex;
    input.currentIndex = currentIndex;
    const plan: MangaPreloadPlan = this.mangaPreloadPlanner.buildSingleNetworkPagePlan(input);
    if (plan.tasks.length <= 0) {
      return;
    }

    this.initPreloadPlanTargets(plan);
    const prev = this.imageLoadStates.get(page.id);
    this.imageLoadStates.set(page.id, {
      isLoading: true,
      isLoaded: false,
      dimensions: prev && prev.dimensions ? prev.dimensions : undefined,
      error: undefined
    } as ImageLoadState);
    this.imageLoadStates = new Map(this.imageLoadStates);

    this.applyPreloadPlan(plan, false);
  }

  /**
   * [性能优化] 条漫模式触发本地图片缓存加载
   * 使用LocalImageCacheManager进行降采样解码和LRU缓存
   */
  private triggerLocalImageLoad(page: MangaPage, chapterId: string, pageIndex: number): void {
    // 检查是否已在缓存中
    if (this.localImageCache.has(page.id)) {
      return;
    }
    
    // 检查是否已在加载中
    if (this.localImageCache.isLoading(page.id)) {
      return;
    }
    
    // 获取文件路径
    const filePath = this.getFsPathFromPage(page);
    if (!filePath) {
      logger.warn(TAG, `本地图片路径无效: ${page.id}`);
      return;
    }
    
    // 异步加载到本地缓存
    this.localImageCache.loadImage(page.id, filePath, {
      maxWidth: this.screenWidth > 0 ? this.screenWidth : 1080
    }).then((pixelMap) => {
      if (pixelMap) {
        logger.debug(TAG, `本地图片缓存加载成功: ${page.id}`);
        this.recordReadFlowAssetEvent(
          MangaReadFlowEventType.ASSET_LOADED,
          page,
          pageIndex,
          this.isWebtoonMode() ? 'webtoon_local_cache' : 'local_cache',
          0,
          true,
          'local_image_cache',
          ''
        );
        if (this.isWebtoonMode()) {
          // 本地+条漫专用：缓存只做预热，不触发条目重渲染，避免闪烁
          return;
        } else {
          // 非条漫模式：保留原有 renderEpoch 防抖逻辑
          if (this.localImageRenderDebounceTimer !== -1) {
            clearTimeout(this.localImageRenderDebounceTimer);
          }
          this.localImageRenderDebounceTimer = setTimeout(() => {
            this.localImageRenderDebounceTimer = -1;
            this.renderEpoch = this.renderEpoch + 1;
            logger.debug(TAG, `[性能] 本地图片批量加载完成，触发UI刷新: renderEpoch=${this.renderEpoch}`);
          }, 150);
        }
      }
    }).catch((error: Error) => {
      logger.error(TAG, `本地图片缓存加载失败: ${page.id}, error=${error.message}`);
      this.recordReadFlowAssetEvent(
        MangaReadFlowEventType.ERROR,
        page,
        pageIndex,
        'local_cache',
        0,
        false,
        'local_image_cache',
        error.message
      );
    });
  }

  /**
   * [性能优化] 条漫模式图片加载完成处理
   */
  private handleWebtoonImageLoad(page: MangaPage, chapterId: string, pageIndex: number): void {
    const loadState = this.imageLoadStates.get(page.id);
    if (loadState) {
      loadState.isLoading = false;
      if (page.sourceType !== ImageSourceType.LOCAL) {
        loadState.isLoaded = true;
      }
      loadState.error = undefined;
      this.imageLoadStates.set(page.id, loadState);
      // 不触发整个Map的响应式更新，减少不必要的重绘
    }
    this.recordReadFlowEvent(
      MangaReadFlowEventType.DISPLAY_COMMITTED,
      page,
      pageIndex,
      'webtoon_image_complete',
      `chapter=${chapterId}`
    );
    this.notifyFirstVisibleDisplayCommitted(page, pageIndex);
  }

  /**
   * [修复] 条漫模式图片加载失败处理
   * 本地图片失败时：先尝试通过 LocalImageCacheManager 重新加载，
   * 如果已经在缓存中则刷新显示，否则设置错误状态让用户看到重试按钮
   */
  private handleWebtoonImageError(page: MangaPage, chapterId: string, pageIndex: number): void {
    if (page.sourceType === ImageSourceType.LOCAL) {
      // 检查 LocalImageCacheManager 中是否已有缓存（可能是 Image 组件的 file:// 加载失败，但缓存已就绪）
      if (this.localImageCache.has(page.id)) {
        // 本地+条漫专用：不触发条目刷新，保持渲染源稳定避免闪烁
        logger.debug(TAG, `本地图片 file:// 加载失败但缓存已就绪: ${page.id}`);
        return;
      }

      // 缓存中也没有，尝试通过 LocalImageCacheManager 重新加载
      if (!this.localImageCache.isLoading(page.id)) {
        logger.info(TAG, `本地图片加载失败，尝试重新加载: ${page.id}`);
        this.triggerLocalImageLoad(page, chapterId, pageIndex);
        return;
      }

      // 正在加载中，等待完成即可
      logger.debug(TAG, `本地图片正在通过缓存加载中，等待完成: ${page.id}`);
      return;
    }
    
    const loadState = this.imageLoadStates.get(page.id);
    if (loadState) {
      loadState.isLoading = false;
      loadState.isLoaded = false;
      loadState.error = '加载失败';
      this.imageLoadStates.set(page.id, loadState);
    }
    logger.warn(TAG, `条漫图片加载失败: ${chapterId}_${page.id}`);
  }

  /**
   * 构建优化的带间隙条漫视图（支持多章节）
   */
  @Builder
  buildWebtoonWithGapView() {
    Scroll(this.scroller) {
      Column({ space: this.readingSettings.pageSpacing || 16 }) {
        // 顶部加载提示（或显示已是第一章提示，或显示双重上滑确认提示）
        if (this.isPrevChapterLoading || this.isFirstChapter || this.prevChapterSwipeConfirmPending) {
          this.buildWebtoonLoadingIndicator('prev')
        }

        // [性能优化] 使用LazyForEach懒加载多章节数据
        if (this.webtoonDataSource.totalCount() > 0) {
          LazyForEach(this.webtoonDataSource, (item: WebtoonDataItem, index: number) => {
            if (item.type === 'chapter_divider') {
              this.buildChapterDivider(item)
            } else if (item.type === 'page' && item.page) {
              this.buildOptimizedImageForWebtoon(item.page, item.chapterId || '', item.pageIndex !== undefined ? item.pageIndex : index)
            }
          }, (item: WebtoonDataItem, index: number) => {
            if (item.type === 'chapter_divider') {
              return `divider_${item.direction}_${item.chapterId}_${index}`;
            } else {
              return `page_${item.chapterId}_${item.page?.id}_${index}`;
            }
          })
        } else {
          // 回退到单章节模式
          LazyForEach(this.pageDataSource, (page: MangaPage, index: number) => {
            this.buildOptimizedImage(page, index)
          }, (page: MangaPage, index: number) => `${this.chapter.id}_${page.id}_${index}`)
        }

        // 底部加载提示（或显示已是最后一章提示）
        if (this.isNextChapterLoading || this.isLastChapter) {
          this.buildWebtoonLoadingIndicator('next')
        }
      }
      .padding({
        top: 8,
        bottom: 8,
        left: `${this.readingSettings.webtoonLeftMargin ?? 0}%`,
        right: `${this.readingSettings.webtoonRightMargin ?? 0}%`
      })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .onDidScroll((xOffset: number, yOffset: number) => {
      this.handleWebtoonScroll(yOffset);
      // [性能优化] 对重型操作进行节流，避免滚动卡顿
      this.throttledWebtoonHeavyOperations();
    })
    .onScrollStart(() => {
      this.isScrolling = true;
      this.cancelWebtoonStopCleanup();
    })
    .onScrollStop(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      // 条漫模式使用专用的预加载方法
      this.triggerWebtoonPreload();
      this.scheduleWebtoonStopCleanup();
    })
  }

  /**
   * 获取图片资源
   */
  private getImageResource(page: MangaPage): Resource | string {
    switch (page.sourceType) {
      case ImageSourceType.LOCAL:
        {
          const fsPath: string | undefined = this.getFsPathFromPage(page);
          if (fsPath && fsPath.length > 0) {
            if (fsPath.startsWith('file://')) {
              return fsPath;
            }
            return 'file://' + fsPath;
          }
          return $r('app.media.ic_image');
        }
      case ImageSourceType.NETWORK:
        return page.imageUrl;
      case ImageSourceType.RAWFILE:
        return $rawfile(page.imageUrl);
      case ImageSourceType.RESOURCE:
        return $r(page.imageUrl);
      default:
        return $r('app.media.ic_image');
    }
  }
  private getDisplayImageInput(page: MangaPage): Resource | string | image.PixelMap {
    return this.resolveDisplayInputForPage(page, $r('app.media.ic_image'), false, false);
  }

  private shouldShowLoadingForPage(page: MangaPage): boolean {
    const st: ImageLoadState | undefined = this.getPageLoadState(page);
    const hasPm: boolean = this.pagePixelMaps.has(page.id);
    
    // 如果已经有PixelMap，不显示加载动画
    if (hasPm) {
      return false;
    }
    
    // [优化] 本地图片特殊处理：检查LocalImageCacheManager
    if (page.sourceType === ImageSourceType.LOCAL) {
      // 条漫模式下本地图不显示加载层，避免滚动时频繁闪烁
      if (this.isWebtoonMode()) {
        return false;
      }
      // 本地图片如果在缓存中，不显示加载动画
      if (this.localImageCache.has(page.id)) {
        return false;
      }
      // 本地图片如果正在加载中，显示加载动画
      if (this.localImageCache.isLoading(page.id)) {
        return true;
      }
      // 本地图片可以直接从文件系统加载，不需要显示加载动画
      // （除非是条漫模式下的预缓存加载）
      return false;
    }
    
    // 以下是网络图片的处理逻辑
    // 如果没有加载状态记录，说明还未开始加载，显示加载动画
    if (!st) {
      return true;
    }
    
    // 如果正在加载且未完成，显示加载动画
    if (st.isLoading && !st.isLoaded) {
      return true;
    }
    
    // 如果既没有加载中也没有加载完成，且没有错误，说明还未开始加载
    if (!st.isLoading && !st.isLoaded && !st.error) {
      return true;
    }
    
    return false;
  }

  private computeImageInputForPage(page: MangaPage): Resource | string | image.PixelMap {
    return this.resolveDisplayInputForPage(page, $r('app.media.ic_image'), true, false);
  }

  private resolveDisplayInputForPage(
    page: MangaPage,
    fallbackInput: Resource | string | image.PixelMap,
    allowNetworkResourceWithoutPixelMap: boolean,
    preferLocalCachePixelMap: boolean
  ): Resource | string | image.PixelMap {
    const request: MangaDisplayInputRequest = new MangaDisplayInputRequest();
    const pagePixelMap: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    request.page = page;
    request.pagePixelMap = pagePixelMap ? pagePixelMap : null;
    request.localCachePixelMap = this.localImageCache.get(page.id);
    request.resourceInput = this.getImageResource(page) as MangaDisplayInputValue;
    request.fallbackInput = fallbackInput as MangaDisplayInputValue;
    request.allowNetworkResourceWithoutPixelMap = allowNetworkResourceWithoutPixelMap;
    request.preferLocalCachePixelMap = preferLocalCachePixelMap;
    const result: MangaDisplayInputResult = this.mangaDisplayInputResolver.resolve(request);
    return result.input;
  }

  private updateSinglePageDisplay(): void {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return;
    }
    const idx: number = Math.min(Math.max(0, this.viewCurrentPageIndex), this.chapter.pages.length - 1);
    const page: MangaPage = this.chapter.pages[idx];
    if (!page) {
      logger.warn(TAG, `页面对象为空: idx=${idx}, pages.length=${this.chapter.pages.length}`);
      return;
    }

    // 【架构优化】只在页面ID真正变化时才递增renderEpoch
    // 避免频繁重建Image组件导致的性能问题和缓存失效
    const pageChanged = this.singlePagePageId !== page.id;
    if (pageChanged) {
      this.renderEpoch = this.renderEpoch + 1;
      logger.debug(TAG, `[架构] 页面切换，递增renderEpoch: ${this.renderEpoch}`);
    }

    this.singlePagePageId = page.id;
    
    // 【架构核心】获取显示输入
    // 网络图片：必须有PixelMap才返回，否则返回占位图
    // 本地图片：可以直接使用路径
    const previousImageInput = this.singlePageImageInput;
    const newImageInput = this.getDisplayImageInput(page);
    
    // 【架构修复】检查PixelMap状态变化
    const hasPm = this.pagePixelMaps.has(page.id);
    const isNetwork = page.sourceType === ImageSourceType.NETWORK;
    const inputChanged = previousImageInput !== newImageInput;
    
    // 如果从无PixelMap切换到有PixelMap，必须强制递增renderEpoch
    // 否则Image组件的key不变，不会重新渲染，导致黑屏
    if (!pageChanged && isNetwork && hasPm && inputChanged) {
      // 当前页面没变，但PixelMap加载完成，强制刷新
      this.renderEpoch = this.renderEpoch + 1;
      logger.info(TAG, `[架构] PixelMap加载完成，强制递增renderEpoch: ${this.renderEpoch}`);
    }
    
    // 总是更新singlePageImageInput，确保UI能响应PixelMap的加载完成
    this.singlePageImageInput = newImageInput;

    // 记录当前状态用于调试
    const pmEpoch = this.getPixelMapEpoch(page.id);
    logger.debug(TAG, `[架构] 单页显示更新: idx=${idx}, id=${page.id}, network=${isNetwork}, hasPm=${hasPm}, epoch=${pmEpoch}, renderEpoch=${this.renderEpoch}, changed=${pageChanged}`);
  }
  private updateSinglePagePreview(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    const prevIdx: number = this.getPrevPageIndex();
    const nextIdx: number = this.getNextPageIndex();
    if (prevIdx >= 0) {
      const prevPage: MangaPage = this.chapter.pages[prevIdx];
      this.previewPrevPageId = prevPage.id;
      // 优先使用PixelMap（支持加密图片），否则使用URL
      this.previewPrevImageInput = this.getDisplayImageInput(prevPage);
      // 确保预览页也触发加载
      const st = this.getPageLoadState(prevPage);
      const hasPm = this.pagePixelMaps.has(prevPage.id);
      if (!hasPm && (!st || !st.isLoading)) {
        this.loadImage(prevPage);
      }
    } else {
      this.previewPrevPageId = '';
      this.previewPrevImageInput = $r('app.media.ic_image');
    }
    if (nextIdx >= 0) {
      const nextPage: MangaPage = this.chapter.pages[nextIdx];
      this.previewNextPageId = nextPage.id;
      // 优先使用PixelMap（支持加密图片），否则使用URL
      this.previewNextImageInput = this.getDisplayImageInput(nextPage);
      // 确保预览页也触发加载
      const st = this.getPageLoadState(nextPage);
      const hasPm = this.pagePixelMaps.has(nextPage.id);
      if (!hasPm && (!st || !st.isLoading)) {
        this.loadImage(nextPage);
      }
    } else {
      this.previewNextPageId = '';
      this.previewNextImageInput = $r('app.media.ic_image');
    }
  }
  private updateDoublePagePreview(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    this.previewPrevSingleDoublePage = false;
    this.previewNextSingleDoublePage = false;

    if (this.isDoublePageVerticalPortraitMode()) {
      const total: number = this.chapter.pages.length;
      const current: number = Math.min(Math.max(0, this.viewCurrentPageIndex), total - 1);
      const pairStart: number = current - (current % 2);
      const maxPairStart: number = total > 0 ? (total - 1) - ((total - 1) % 2) : -1;
      const prevPairStart: number = pairStart >= 2 ? pairStart - 2 : -1;
      const nextPairStart: number = pairStart + 2 <= maxPairStart ? pairStart + 2 : -1;

      if (prevPairStart >= 0 && prevPairStart < total) {
        const prevLeft: MangaPage = this.chapter.pages[prevPairStart];
        const prevRightIdx: number = prevPairStart + 1;
        const prevRightValid: boolean = prevRightIdx < total;
        this.previewPrevLeftPageId = prevLeft.id;
        this.previewPrevLeftImageInput = this.getDisplayImageInput(prevLeft);
        if (prevRightValid) {
          const prevRight: MangaPage = this.chapter.pages[prevRightIdx];
          this.previewPrevRightPageId = prevRight.id;
          this.previewPrevRightImageInput = this.getDisplayImageInput(prevRight);
        } else {
          this.previewPrevRightPageId = '';
          this.previewPrevRightImageInput = $r('app.media.ic_image');
        }
      } else {
        this.previewPrevLeftPageId = '';
        this.previewPrevLeftImageInput = $r('app.media.ic_image');
        this.previewPrevRightPageId = '';
        this.previewPrevRightImageInput = $r('app.media.ic_image');
      }

      if (nextPairStart >= 0 && nextPairStart < total) {
        const nextLeft: MangaPage = this.chapter.pages[nextPairStart];
        const nextRightIdx: number = nextPairStart + 1;
        const nextRightValid: boolean = nextRightIdx < total;
        this.previewNextLeftPageId = nextLeft.id;
        this.previewNextLeftImageInput = this.getDisplayImageInput(nextLeft);
        if (nextRightValid) {
          const nextRight: MangaPage = this.chapter.pages[nextRightIdx];
          this.previewNextRightPageId = nextRight.id;
          this.previewNextRightImageInput = this.getDisplayImageInput(nextRight);
        } else {
          this.previewNextRightPageId = '';
          this.previewNextRightImageInput = $r('app.media.ic_image');
        }
      } else {
        this.previewNextLeftPageId = '';
        this.previewNextLeftImageInput = $r('app.media.ic_image');
        this.previewNextRightPageId = '';
        this.previewNextRightImageInput = $r('app.media.ic_image');
      }
      return;
    }

    const previousPlan: DoublePageSmartDisplayPlan = this.resolvePreviousDoublePageSmartPlan(this.viewCurrentPageIndex);
    if (previousPlan.leftPageIndex >= 0 && previousPlan.leftPageIndex < this.chapter.pages.length) {
      const previousLeftPage: MangaPage = this.chapter.pages[previousPlan.leftPageIndex];
      this.previewPrevLeftPageId = previousLeftPage.id;
      this.previewPrevLeftImageInput = this.getDisplayImageInput(previousLeftPage);
      this.previewPrevSingleDoublePage = previousPlan.mode === DoublePageSmartDisplayMode.SINGLE;
      if (previousPlan.rightPageIndex >= 0 && previousPlan.rightPageIndex < this.chapter.pages.length) {
        const previousRightPage: MangaPage = this.chapter.pages[previousPlan.rightPageIndex];
        this.previewPrevRightPageId = previousRightPage.id;
        this.previewPrevRightImageInput = this.getDisplayImageInput(previousRightPage);
      } else {
        this.previewPrevRightPageId = '';
        this.previewPrevRightImageInput = $r('app.media.ic_image');
      }
    } else {
      this.previewPrevLeftPageId = '';
      this.previewPrevLeftImageInput = $r('app.media.ic_image');
      this.previewPrevRightPageId = '';
      this.previewPrevRightImageInput = $r('app.media.ic_image');
    }

    const nextPlan: DoublePageSmartDisplayPlan = this.resolveNextDoublePageSmartPlan(this.viewCurrentPageIndex);
    if (nextPlan.leftPageIndex >= 0 && nextPlan.leftPageIndex < this.chapter.pages.length) {
      const nextLeftPage: MangaPage = this.chapter.pages[nextPlan.leftPageIndex];
      this.previewNextLeftPageId = nextLeftPage.id;
      this.previewNextLeftImageInput = this.getDisplayImageInput(nextLeftPage);
      this.previewNextSingleDoublePage = nextPlan.mode === DoublePageSmartDisplayMode.SINGLE;
      if (nextPlan.rightPageIndex >= 0 && nextPlan.rightPageIndex < this.chapter.pages.length) {
        const nextRightPage: MangaPage = this.chapter.pages[nextPlan.rightPageIndex];
        this.previewNextRightPageId = nextRightPage.id;
        this.previewNextRightImageInput = this.getDisplayImageInput(nextRightPage);
      } else {
        this.previewNextRightPageId = '';
        this.previewNextRightImageInput = $r('app.media.ic_image');
      }
    } else {
      this.previewNextLeftPageId = '';
      this.previewNextLeftImageInput = $r('app.media.ic_image');
      this.previewNextRightPageId = '';
      this.previewNextRightImageInput = $r('app.media.ic_image');
    }
  }
  private updateDoublePageDisplay(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    // 强制递增renderEpoch，确保Image组件重新渲染
    this.renderEpoch = this.renderEpoch + 1;

    if (this.leftPageIndex >= 0 && this.leftPageIndex < this.chapter.pages.length) {
      const lp: MangaPage = this.chapter.pages[this.leftPageIndex];
      this.doubleLeftPageId = lp.id;
      // 优先使用PixelMap（支持加密图片解密后显示），否则使用URL
      this.doubleLeftImageInput = this.getDisplayImageInput(lp);
      const hasLPm = this.pagePixelMaps.has(lp.id);
      logger.debug(TAG, `双页左侧更新: idx=${this.leftPageIndex}, id=${lp.id}, hasPm=${hasLPm}, src=${String(this.doubleLeftImageInput)}`);
    } else {
      this.doubleLeftPageId = '';
      this.doubleLeftImageInput = $r('app.media.ic_image');
    }
    if (this.rightPageIndex >= 0 && this.rightPageIndex < this.chapter.pages.length) {
      const rp: MangaPage = this.chapter.pages[this.rightPageIndex];
      this.doubleRightPageId = rp.id;
      // 优先使用PixelMap（支持加密图片解密后显示），否则使用URL
      this.doubleRightImageInput = this.getDisplayImageInput(rp);
      const hasRPm = this.pagePixelMaps.has(rp.id);
      logger.debug(TAG, `双页右侧更新: idx=${this.rightPageIndex}, id=${rp.id}, hasPm=${hasRPm}, src=${String(this.doubleRightImageInput)}`);
    } else {
      this.doubleRightPageId = '';
      this.doubleRightImageInput = $r('app.media.ic_image');
    }
    this.updateVerticalDoublePageRenderSlots();
  }
  private invalidatePixelMapIfSourceChanged(page: MangaPage): void {
    const id: string = page.id;
    const meta: MangaPixelMapMeta | undefined = this.pagePixelMapMeta.get(id);
    const existed: image.PixelMap | undefined = this.pagePixelMaps.get(id);
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    if (!existed || !meta || !fsPath) {
      return;
    }
    try {
      fs.stat(fsPath).then((statInfo) => {
        const sizeNum: number = statInfo.size ? (statInfo.size as number) : 0;
        const pathChanged: boolean = meta.path !== fsPath;
        const sizeChanged: boolean = meta.size !== sizeNum;
        if (pathChanged || sizeChanged) {
          this.dropPagePixelMapReference(id, true);
          this.imageLoadStates.delete(id);
          this.imageLoadStates = new Map(this.imageLoadStates);
          logger.warn(TAG, `PixelMap失效: id=${id}, pathChanged=${pathChanged}, sizeChanged=${sizeChanged}`);
        }
      }).catch((_err: BusinessError) => {
      });
    } catch (_e) {
    }
  }
  private async ensurePixelMapLoaded(page: MangaPage): Promise<void> {
    const existed: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    if (existed) {
      // 【修复】验证 PixelMap 是否仍然有效（可能已被 ImageCacheManager LRU 淘汰后释放）
      try {
        const info = existed.getImageInfoSync();
        if (info && info.size && info.size.width > 0) {
          return; // PixelMap 有效，无需重新加载
        }
      } catch (_e) {
        // PixelMap 已释放，移除失效引用并重新加载
      }
      logger.warn(TAG, `PixelMap已失效，重新加载: id=${page.id}`);
      this.dropPagePixelMapReference(page.id, false);
    }
    if (this.isWebtoonMode() && page.sourceType === ImageSourceType.NETWORK) {
      this.queueWebtoonNetworkPageLoad(page);
      return;
    }
    if (page.sourceType !== ImageSourceType.LOCAL && page.sourceType !== ImageSourceType.NETWORK) {
      return;
    }

    const managedPageIndex: number = this.resolveManagedPageIndex(page);
    const currentReferer: string = this.networkHeaders?.referer || 'undefined';
    logger.debug(TAG, `统一资产管线加载图片: id=${page.id}, type=${page.sourceType}, referer=${currentReferer}`);
    const sessionSnapshot: MangaReaderSessionSnapshot = this.captureMangaReaderSession();

    try {
      const result: MangaAssetLoadResult = await this.loadPixelMapWithAssetPipeline(
        page,
        managedPageIndex,
        this.resolveAssetLoadReason(page)
      );
      this.recordReadFlowAssetEvent(
        MangaReadFlowEventType.ASSET_LOADED,
        page,
        managedPageIndex,
        this.resolveAssetLoadReason(page),
        result.elapsedMs,
        result.success,
        String(result.source),
        result.errorMessage
      );
      if (!this.isMangaReaderSessionActive(sessionSnapshot, page)) {
        logger.warn(TAG, `丢弃过期漫画资产加载结果: ${this.mangaReaderSessionGuard.describePage(page)}`);
        this.recordReadFlowEvent(
          MangaReadFlowEventType.CLEANUP,
          page,
          managedPageIndex,
          'stale_asset_discarded',
          this.mangaReaderSessionGuard.describePage(page)
        );
        return;
      }
      if (result.success && result.pixelMap) {
        this.markPagePixelMapLoaded(page, result.pixelMap);
        this.cleanupInvisiblePixelMaps();
      } else {
        const errMsg: string = result.errorMessage.length > 0 ? result.errorMessage : '图片加载失败';
        this.markPagePixelMapLoadFailed(page, errMsg);
        logger.error(TAG, `统一资产管线加载失败: id=${page.id}, url=${page.imageUrl}, error=${errMsg}`);
      }
    } catch (err) {
      if (!this.isMangaReaderSessionActive(sessionSnapshot, page)) {
        logger.warn(TAG, `忽略过期漫画资产加载异常: ${this.mangaReaderSessionGuard.describePage(page)}`);
        return;
      }
      const errMsg: string = '加载异常: ' + String(err);
      this.markPagePixelMapLoadFailed(page, errMsg);
      logger.error(TAG, `统一资产管线加载异常: id=${page.id}, error=${String(err)}`);
    }
  }
  private cleanupInvisiblePixelMaps(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    // 条漫滚动期间避免频繁扫描/清理，改为滚动停止后集中处理
    if (this.isWebtoonMode() && this.isScrolling) {
      return;
    }
    const isWebtoonMultiChapter = this.isWebtoonMode() && this.webtoonDataItems.length > 0;
    const totalPagesCount: number = isWebtoonMultiChapter ? this.webtoonDataItems.length : this.chapter.pages.length;
    let threshold: number = Math.floor(totalPagesCount / 5);
    if (threshold < 10) { threshold = 10; }
    if (this.pagePixelMaps.size < threshold) { return; }

    // 【修复】保护当前页和相邻页的PixelMap，防止卷页动画降级
    const protectedIndices = new Set<number>();
    const currentIndex = this.viewCurrentPageIndex;

    // 【条漫模式修复】条漫模式需要更大的保护范围，防止滚动时图片被清理
    if (this.isWebtoonMode()) {
      const visibleItemIndices = this.webtoonVisibleItemIndices.length > 0
        ? this.webtoonVisibleItemIndices
        : this.getWebtoonVisibleItemIndicesForPreload();
      // 保护所有可见条目
      for (let i = 0; i < visibleItemIndices.length; i++) {
        protectedIndices.add(visibleItemIndices[i]);
      }
      
      // 额外保护可见区域前后各8页作为缓冲（用于预加载）
      const minVisible = visibleItemIndices.length > 0 
        ? Math.min(...visibleItemIndices) 
        : currentIndex;
      const maxVisible = visibleItemIndices.length > 0 
        ? Math.max(...visibleItemIndices) 
        : currentIndex;
      
      for (let i = Math.max(0, minVisible - 8);
        i <= Math.min(totalPagesCount - 1, maxVisible + 8);
        i++) {
        protectedIndices.add(i);
      }
    } else {
      // 单页/双页模式：保护范围：当前页 ± 3页（确保卷页动画所需的PixelMap始终可用，
      // 包含快速翻页时的缓冲）
      for (let i = Math.max(0, currentIndex - 3);
        i <= Math.min(totalPagesCount - 1, currentIndex + 3);
        i++) {
        protectedIndices.add(i);
      }
    }

    const keys: string[] = Array.from(this.pagePixelMaps.keys());
    let cleanedCount = 0;
    for (let i = 0; i < keys.length; i++) {
      const id: string = keys[i];
      let idx: number;
      if (isWebtoonMultiChapter) {
        const ref = this.webtoonPageRefById.get(id);
        idx = ref ? ref.itemIndex : -1;
      } else {
        idx = this.getPageIndexById(id);
      }
      if (idx < 0) {
        continue;
      }

      // 【修复】跳过受保护的页面
      if (protectedIndices.has(idx)) {
        continue;
      }

      const p: MangaPage | undefined = this.getPageById(id);
      if (!p) {
        continue;
      }
      const visible: boolean = this.isPageCurrentlyVisible(p);
      if (!visible) {
        this.dropPagePixelMapReference(id, true);
        cleanedCount++;
      }
    }

    if (cleanedCount > 0) {
      logger.debug(TAG, `清理了${cleanedCount}个不可见PixelMap，保护了${protectedIndices.size}个相邻页`);
      this.logMangaReaderCacheSnapshot('invisible_pixel_maps_cleaned');
    }
    this.pagePixelMaps = new Map(this.pagePixelMaps);
  }

  private incrementPixelMapEpoch(pageId: string): void {
    this.mangaPixelMapLifecycleManager.incrementEpoch(this.pixelMapEpochByPage, pageId);
    this.pixelMapEpochByPage = new Map(this.pixelMapEpochByPage);
  }

  private getPixelMapEpoch(pageId: string): number {
    return this.mangaPixelMapLifecycleManager.getEpoch(this.pixelMapEpochByPage, pageId);
  }

  /**
   * 检查页面是否已就绪可以显示
   * 就绪条件：PixelMap已加载或图片加载状态为已完成
   */
  private isPageReadyForDisplay(page: MangaPage): boolean {
    // 检查PixelMap是否已加载
    const hasPm = this.pagePixelMaps.has(page.id);
    if (hasPm) {
      return true;
    }

    // 检查加载状态
    const state = this.imageLoadStates.get(page.id);
    if (state && state.isLoaded) {
      return true;
    }

    return false;
  }

  /**
   * 检查是否可以翻到指定页面
   * 如果页面未就绪，返回false
   */
  private canTurnToPage(pageIndex: number): boolean {
    if (pageIndex < 0 || !this.chapter || !this.chapter.pages || pageIndex >= this.chapter.pages.length) {
      return false;
    }

    const page = this.chapter.pages[pageIndex];
    return this.isPageReadyForDisplay(page);
  }

  /**
   * PixelMap加载完成通知
   * 如果加载的是当前可见页面，立即刷新UI
   */
  private notifyPixelMapLoaded(page: MangaPage): void {
    const visibility: MangaPageVisibilityResult = this.mangaPageVisibilityResolver.resolve(
      page,
      this.createMangaPageVisibilityContext()
    );
    const pageIdx: number = visibility.displayIndex;
    if (pageIdx < 0) {
      return;
    }
    
    // 条漫自动检测：分析已加载图片的宽高比
    this.analyzeImageForWebtoonDetection(page);

    const plan: MangaLoadedPagePresentationPlan = this.mangaLoadedPagePresentationPlanner.build(
      this.createLoadedPagePresentationContext(visibility)
    );
    if (!plan.isVisible) {
      if (plan.shouldUpdateDoublePagePreview) {
        this.updateDoublePagePreview();
      }
      if (plan.shouldUpdateSinglePagePreview) {
        this.updateSinglePagePreview();
      }
      logger.debug(TAG, `PixelMap加载完成但页面不可见: id=${page.id}, idx=${pageIdx}`);
      return;
    }

    logger.info(TAG, `PixelMap加载完成且页面可见，刷新UI: id=${page.id}, idx=${pageIdx}`);

    if (plan.shouldRefreshWebtoonItem) {
      const dataIndex = this.findWebtoonDataIndex(page.id);
      if (dataIndex >= 0) {
        this.webtoonDataSource.notifyDataChange(dataIndex);
      }
      return;
    }

    if (plan.shouldUpdateDoublePageIndices) {
      this.updateDoublePageIndices();
    }
    if (plan.shouldUpdateDoublePageDisplay) {
      this.updateDoublePageDisplay();
    }
    if (plan.shouldUpdateDoublePagePreview) {
      this.updateDoublePagePreview();
    }
    if (plan.shouldUpdateSinglePageDisplay) {
      this.updateSinglePageDisplay();
    }
    if (plan.shouldScheduleSoftTransitionOverlayOut) {
      this.scheduleSoftTransitionOverlayOut();
    }
  }
  
  /**
   * 分析图片宽高比，用于条漫自动检测
   * 条漫特征：图片高度远大于宽度（高/宽 > 2）
   */
  private async analyzeImageForWebtoonDetection(page: MangaPage): Promise<void> {
    // 如果已完成检测或当前是条漫/连续滚动模式，跳过
    if (this.webtoonDetectionDone) {
      return;
    }
    if (this.readingSettings.readingMode === ReadingMode.WEBTOON ||
        this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL ||
        this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      this.webtoonDetectionDone = true;
      return;
    }
    
    try {
      const pm = this.pagePixelMaps.get(page.id);
      if (!pm) {
        return;
      }
      
      const imageInfo = await pm.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      
      if (width > 0 && height > 0) {
        const aspectRatio = height / width;
        this.detectedAspectRatios.push(aspectRatio);
        logger.debug(TAG, `条漫检测: page=${page.id}, 尺寸=${width}x${height}, 宽高比=${aspectRatio.toFixed(2)}`);
        
        // 收集足够样本后进行判定
        if (this.detectedAspectRatios.length >= this.WEBTOON_DETECTION_SAMPLE_COUNT) {
          this.webtoonDetectionDone = true;
          
          // 计算平均宽高比
          const avgRatio = this.detectedAspectRatios.reduce((a, b) => a + b, 0) / this.detectedAspectRatios.length;
          const isWebtoon = avgRatio >= this.WEBTOON_ASPECT_RATIO_THRESHOLD;
          
          logger.info(TAG, `条漫检测完成: 样本数=${this.detectedAspectRatios.length}, 平均宽高比=${avgRatio.toFixed(2)}, 判定=${isWebtoon ? '条漫' : '普通漫画'}`);
          
          // 触发回调通知父组件
          if (this.callbacks && this.callbacks.onWebtoonDetected) {
            this.callbacks.onWebtoonDetected(isWebtoon, avgRatio);
          }
        }
      }
    } catch (e) {
      logger.warn(TAG, `条漫检测分析失败: ${String(e)}`);
    }
  }

  private getFsPathFromPage(page: MangaPage): string | undefined {
    return this.mangaPagePathResolver.getLocalFilePath(page);
  }

  private getPageIndexById(pageId: string): number {
    return this.mangaPageLoadResolver.getPageIndexById(this.chapter, pageId);
  }

  /**
   * 提交页面 PixelMap。
   * 条漫模式下优先做行级刷新，避免每张图都触发整树响应式重算。
   */
  private commitPagePixelMap(pageId: string, pixelMap: image.PixelMap): void {
    this.pagePixelMaps.set(pageId, pixelMap);
    const pageIndex: number = this.getPageIndexById(pageId);
    if (pageIndex >= 0 && this.chapter && this.chapter.pages && pageIndex < this.chapter.pages.length) {
      const page: MangaPage = this.chapter.pages[pageIndex];
      try {
        const imageInfo = pixelMap.getImageInfoSync();
        if (imageInfo && imageInfo.size && imageInfo.size.width > 0 && imageInfo.size.height > 0) {
          const oldWidth: number = page.width !== undefined ? page.width : 0;
          const oldHeight: number = page.height !== undefined ? page.height : 0;
          page.width = imageInfo.size.width;
          page.height = imageInfo.size.height;
          if (this.isWebtoonMode() &&
            (oldWidth !== imageInfo.size.width || oldHeight !== imageInfo.size.height)) {
            this.invalidateWebtoonPositionCache();
          }
          const previousState: ImageLoadState | undefined = this.imageLoadStates.get(pageId);
          const nextState: ImageLoadState = {
            isLoading: previousState ? previousState.isLoading : false,
            isLoaded: previousState ? previousState.isLoaded : false,
            dimensions: {
              width: imageInfo.size.width,
              height: imageInfo.size.height
            } as MangaViewerImageDimensions,
            error: previousState ? previousState.error : undefined
          } as ImageLoadState;
          this.imageLoadStates.set(pageId, nextState);
          this.imageLoadStates = new Map(this.imageLoadStates);
        }
      } catch (_error) {
      }
    }
    if (this.isWebtoonMode()) {
      const dataIndex = this.findWebtoonDataIndex(pageId);
      if (dataIndex >= 0) {
        this.webtoonDataSource.notifyDataChange(dataIndex);
        return;
      }
    }
    if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      const visualIndex: number = this.getContinuousHorizontalVisualIndex(pageIndex);
      if (visualIndex >= 0 && visualIndex < this.continuousHorizontalDataSource.totalCount()) {
        this.continuousHorizontalDataSource.notifyDataChange(visualIndex);
        return;
      }
    }
    this.pagePixelMaps = new Map(this.pagePixelMaps);
  }

  private isPageCurrentlyVisible(page: MangaPage): boolean {
    return this.mangaPageVisibilityResolver.isPageVisible(page, this.createMangaPageVisibilityContext());
  }

  private verifyLocalFileAndLog(page: MangaPage, stage: string): void {
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    if (!fsPath) {
      logger.debug(TAG, `文件访问检查(${stage}): id=${page.id}, type=${page.sourceType.toString()}, path=N/A`);
      return;
    }
    try {
      fs.stat(fsPath).then((statInfo) => {
        const sizeNum: number = statInfo.size ? (statInfo.size as number) : 0;
        logger.debug(TAG, `文件访问检查(${stage}): id=${page.id}, exists=true, size=${sizeNum}, path=${fsPath}`);
      }).catch((err: BusinessError) => {
        const msg: string = (err as Error).message;
        logger.error(TAG, `文件访问检查(${stage})失败: id=${page.id}, path=${fsPath}, error=${msg}`);
      });
    } catch (e) {
      logger.error(TAG, `文件访问检查(${stage})异常: id=${page.id}, error=${String((e as Error).message)}`);
    }
  }

  private logDetailedLoadError(page: MangaPage, error: BusinessError): void {
    const srcStr: string = String(this.getImageResource(page));
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const codeInfo: string = typeof error.code === 'number' ? String(error.code) : 'unknown';
    logger.error(TAG, `图片加载错误诊断: id=${page.id}, code=${codeInfo}, message=${String(error.message)}, src=${srcStr}, path=${fsPath ? fsPath : 'N/A'}`);
    this.verifyLocalFileAndLog(page, 'error');
  }
  private logDetailedImageError(page: MangaPage, error: ImageError): void {
    const srcStr: string = String(this.getImageResource(page));
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const msg: string = String(error.message);
    logger.error(TAG, `图片加载错误诊断(ImageError): id=${page.id}, message=${msg}, src=${srcStr}, path=${fsPath ? fsPath : 'N/A'}`);
    this.verifyLocalFileAndLog(page, 'error');
  }

  private logTimeoutDiagnosis(page: MangaPage): void {
    const srcStr: string = String(this.getImageResource(page));
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const visible: boolean = this.isPageCurrentlyVisible(page);
    const hasPixelMap: boolean = this.pagePixelMaps.has(page.id);
    logger.warn(TAG, `图片加载超时诊断: id=${page.id}, src=${srcStr}, path=${fsPath ? fsPath : 'N/A'}, visible=${visible}, pixelMap=${hasPixelMap}`);
    this.verifyLocalFileAndLog(page, 'timeout');
  }

  private logImageDisplayBefore(page: MangaPage, input: Resource | string | image.PixelMap): void {
    const pm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const inputStr: string = typeof input === 'string' ? String(input) : (fsPath ? fsPath : 'PixelMap');
    logger.debug(TAG, `开始显示图片: id=${page.id}, type=${page.sourceType.toString()}, input=${inputStr}, pixelMap=${pm ? true : false}`);
  }

  private logImageDisplayAfter(page: MangaPage, success: boolean): void {
    const pm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const resStr: string = String(this.getImageResource(page));
    logger.debug(TAG, `图片显示结束: id=${page.id}, success=${success}, type=${page.sourceType.toString()}, resource=${resStr}, path=${fsPath ? fsPath : 'N/A'}, pixelMap=${pm ? true : false}`);
  }

  /**
   * 注意：条漫双击事件也已移至Page层统一处理
   * 此方法已废弃，保留toggleWebtoonZoom供将来可能使用
   */

  /**
   * 初始化缩放焦点（捏合手势开始时调用）
   * 将屏幕触点坐标转换为内容坐标系，设为缩放锚点
   * @param event 手势事件
   * @param isHorizontalScroll 是否为水平滚动模式（CONTINUOUS_SCROLL）
   */
  private initWebtoonPinchCenter(event: GestureEvent, isHorizontalScroll: boolean): void {
    const oldCx = this.webtoonScaleCenterX;
    const oldCy = this.webtoonScaleCenterY;

    let newCx: number;
    let newCy: number;
    if (isHorizontalScroll) {
      // 水平滚动：X轴需要加滚动偏移
      const scrollX = this.scroller?.currentOffset()?.xOffset ?? 0;
      newCx = (event.pinchCenterX ?? (this.screenWidth / 2)) + scrollX;
      newCy = event.pinchCenterY ?? (this.screenHeight / 2);
    } else {
      // 垂直滚动：Y轴需要加滚动偏移
      const scrollY = this.scroller?.currentOffset()?.yOffset ?? 0;
      newCx = event.pinchCenterX ?? (this.screenWidth / 2);
      newCy = (event.pinchCenterY ?? (this.screenHeight / 2)) + scrollY;
    }

    // 如果当前已缩放，切换锚点时需要补偿translate，避免画面跳变
    if (this.webtoonZoomScale > this.MIN_ZOOM_SCALE) {
      const s = this.webtoonZoomScale;
      this.webtoonOffsetX += (oldCx - newCx) * (1 - s);
      this.webtoonOffsetY += (oldCy - newCy) * (1 - s);
    }

    this.webtoonScaleCenterX = newCx;
    this.webtoonScaleCenterY = newCy;
    this.webtoonPinchStartScale = this.webtoonZoomScale;
    this.webtoonPinchStartOffsetX = this.webtoonOffsetX;
    this.webtoonPinchStartOffsetY = this.webtoonOffsetY;
  }

  /**
   * 切换条漫缩放状态（双击缩放）
   * [修复] 以触点为焦点缩放，而非组件中心
   */
  private toggleWebtoonZoom(centerX: number, centerY: number): void {
    if (!this.uiContext) {
      return;
    }

    const targetScale = this.webtoonZoomScale > this.MIN_ZOOM_SCALE ? this.MIN_ZOOM_SCALE : 2.0;

    // 设置缩放焦点到触点位置（内容坐标系）
    const scrollY = this.scroller?.currentOffset()?.yOffset ?? 0;
    this.webtoonScaleCenterX = centerX;
    this.webtoonScaleCenterY = centerY + scrollY;

    const animateOptions: AnimateParam = {
      duration: 300,
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.webtoonZoomScale = targetScale;
      // 使用 centerX/centerY 锚点后，缩放自然以触点为中心，无需额外translate
      this.webtoonOffsetX = 0;
      this.webtoonOffsetY = 0;
    });

    logger.debug(TAG, `条漫缩放: ${this.webtoonZoomScale} -> ${targetScale}`);
  }

  /**
   * 处理条漫拖拽手势
   * [修复] 扩大拖拽范围，适配焦点锚点缩放
   */
  private handleWebtoonPan(event: GestureEvent): void {
    const input: MangaWebtoonPanInput = new MangaWebtoonPanInput();
    input.zoomScale = this.webtoonZoomScale;
    input.minZoomScale = this.MIN_ZOOM_SCALE;
    input.offsetX = this.webtoonOffsetX;
    input.offsetY = this.webtoonOffsetY;
    input.deltaX = event.offsetX;
    input.deltaY = event.offsetY;
    input.screenWidth = (this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360;
    input.screenHeight = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;

    const plan: MangaWebtoonPanPlan = this.mangaWebtoonGesturePlanner.buildPanPlan(input);
    if (!plan.shouldApply) {
      return;
    }
    this.webtoonOffsetX = plan.offsetX;
    this.webtoonOffsetY = plan.offsetY;
  }

  /** 条漫缩放开始时的初始缩放值 */
  private webtoonPinchStartScale: number = 1.0;

  /**
   * 处理条漫捏合缩放手势（旧方法，保留兼容）
   */
  private handleWebtoonPinch(event: GestureEvent): void {
    this.handleWebtoonPinchUpdate(event);
  }

  /**
   * 处理条漫捏合缩放更新
   * 修复：基于起始缩放值计算，避免抖动
   */
  private handleWebtoonPinchUpdate(event: GestureEvent): void {
    const input: MangaWebtoonPinchInput = new MangaWebtoonPinchInput();
    input.pinchStartScale = this.webtoonPinchStartScale;
    input.gestureScale = event.scale;
    input.minZoomScale = this.MIN_ZOOM_SCALE;
    input.maxZoomScale = this.MAX_ZOOM_SCALE;

    const plan: MangaWebtoonPinchPlan = this.mangaWebtoonGesturePlanner.buildPinchPlan(input);
    this.webtoonZoomScale = plan.zoomScale;

    if (plan.shouldResetOffset) {
      this.webtoonOffsetX = 0;
      this.webtoonOffsetY = 0;
    }
  }

  /**
   * 处理条漫捏合缩放结束
   * 修复：添加平滑的结束动画
   */
  private handleWebtoonPinchEnd(): void {
    this.isZooming = false;

    const input: MangaWebtoonPinchEndInput = new MangaWebtoonPinchEndInput();
    input.zoomScale = this.webtoonZoomScale;
    input.minZoomScale = this.MIN_ZOOM_SCALE;
    const plan: MangaWebtoonPinchEndPlan = this.mangaWebtoonGesturePlanner.buildPinchEndPlan(input);

    if (plan.shouldSnapToMin) {
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.webtoonZoomScale = plan.zoomScale;
          this.webtoonOffsetX = plan.offsetX;
          this.webtoonOffsetY = plan.offsetY;
        });
      } else {
        this.webtoonZoomScale = plan.zoomScale;
        this.webtoonOffsetX = plan.offsetX;
        this.webtoonOffsetY = plan.offsetY;
      }
    }

    logger.debug(TAG, `条漫双指缩放结束: 最终缩放=${this.webtoonZoomScale}`);
  }

  // ==================== 单页/双页模式缩放手势处理 ====================

  /** 缩放开始时的初始缩放值 */
  private pinchStartScale: number = 1.0;

  /**
   * 处理双指缩放开始
   */
  private handlePinchStart(): void {
    this.pinchStartScale = this.currentScale;
    this.isZooming = true;
    logger.debug(TAG, `双指缩放开始: 初始缩放=${this.pinchStartScale}`);
  }

  /**
   * 处理双指缩放更新
   */
  private handlePinchUpdate(event: GestureEvent): void {
    // 计算新的缩放值
    const newScale = Math.max(this.MIN_ZOOM_SCALE,
      Math.min(this.MAX_ZOOM_SCALE, this.pinchStartScale * event.scale));

    this.currentScale = newScale;

    // 通知外部缩放变化
    if (this.callbacks.onZoomChange) {
      this.callbacks.onZoomChange(newScale);
    }
  }

  /**
   * 处理双指缩放结束
   * 修复：添加平滑的结束动画
   */
  private handlePinchEnd(): void {
    this.isZooming = false;

    // 如果缩放接近最小值，平滑回弹到1.0
    if (this.currentScale < this.MIN_ZOOM_SCALE + 0.1) {
      if (this.uiContext) {
        this.uiContext.animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.currentScale = this.MIN_ZOOM_SCALE;
          this.translateX = 0;
          this.translateY = 0;
          if (this.callbacks.onZoomChange) {
            this.callbacks.onZoomChange(this.MIN_ZOOM_SCALE);
          }
        });
      } else {
        this.currentScale = this.MIN_ZOOM_SCALE;
        this.translateX = 0;
        this.translateY = 0;
      }
    }

    logger.debug(TAG, `双指缩放结束: 最终缩放=${this.currentScale}`);
  }

  /**
   * 处理边缘滑动
   */
  private handleEdgeSwipe(event: GestureEvent): void {
    const screenWidth: number = (this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360;
    const edgeThreshold: number = Math.floor(screenWidth * 0.14);

    if (event.fingerList && event.fingerList.length === 1) {
      const finger = event.fingerList[0];
      const startX = finger.localX;

      // 左边缘向右滑动 - 上一章
      if (startX < edgeThreshold && event.offsetX > 100) {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('prev');
        }
        return;
      }

      // 右边缘向左滑动 - 下一章
      if (startX > screenWidth - edgeThreshold && event.offsetX < -100) {
        if (this.callbacks.onChapterChange) {
          this.callbacks.onChapterChange('next');
        }
        return;
      }
    }
  }

  /**
   * 处理条漫滚动事件
   */
  private handleWebtoonScroll(yOffset: number): void {
    // 使用 scroller.currentOffset() 获取实际的绝对滚动位置
    // onScroll 的 yOffset 参数是增量，不是绝对位置
    const previousScrollY = this.scrollPosition;
    if (this.scroller) {
      const offset = this.scroller.currentOffset();
      this.scrollPosition = offset.yOffset;
    } else {
      // 回退方案：累加增量（不太准确）
      this.scrollPosition += yOffset;
    }
    
    // 更新滚动方向跟踪
    const scrollDelta = this.scrollPosition - previousScrollY;
    if (Math.abs(scrollDelta) > 1) { // 忽略微小的抖动
      this.lastScrollDirection = scrollDelta > 0 ? 'down' : 'up';
    }
    this.lastScrollY = this.scrollPosition;
    this.isScrolling = true;

    // 清除之前的定时器
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
    }

    // 设置滚动结束检测
    this.scrollTimer = setTimeout(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      // 条漫模式使用专用的预加载方法
      this.triggerWebtoonPreload();
      // 保存滚动位置
      this.saveScrollPosition();
    }, 150);

    // 实时更新可见页面（节流处理）
    this.throttledUpdateVisiblePages();

    // 通知父组件滚动位置变化
    if (this.callbacks.onScrollPositionChange) {
      this.callbacks.onScrollPositionChange(this.scrollPosition);
    }
  }

  /**
   * 处理连续水平滚动事件（CONTINUOUS_SCROLL模式）
   */
  private handleContinuousHorizontalScroll(xOffset: number): void {
    const previousScrollX = this.scrollPosition;
    if (this.scroller) {
      const offset = this.scroller.currentOffset();
      this.scrollPosition = offset.xOffset;
    } else {
      this.scrollPosition += xOffset;
    }

    // 更新滚动方向跟踪
    const scrollDelta = this.scrollPosition - previousScrollX;
    if (Math.abs(scrollDelta) > 1) {
      this.lastScrollDirection = scrollDelta > 0 ? 'down' : 'up';
    }
    this.isScrolling = true;

    // 清除之前的定时器
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
    }

    // 设置滚动结束检测
    this.scrollTimer = setTimeout(() => {
      this.isScrolling = false;
      this.updateContinuousHorizontalVisiblePages();
      this.triggerUnifiedPreload();
      this.checkContinuousHorizontalChapterBoundary();
      this.saveScrollPosition();
    }, 150);

    // 实时更新（节流）
    this.throttledUpdateContinuousHorizontalPages();

    if (this.callbacks.onScrollPositionChange) {
      this.callbacks.onScrollPositionChange(this.scrollPosition);
    }
  }

  /**
   * 节流更新水平连续滚动可见页面
   */
  private throttledUpdateContinuousHorizontalPages(): void {
    const now = Date.now();
    if (!this.lastUpdateTime || now - this.lastUpdateTime > 100) {
      this.updateContinuousHorizontalVisiblePages();
      this.triggerUnifiedPreload();
      this.checkContinuousHorizontalChapterBoundary();
      this.lastUpdateTime = now;
    }
  }

  /**
   * 更新水平连续滚动模式的可见页面
   */
  private updateContinuousHorizontalVisiblePages(): void {
    if (!this.scroller || !this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return;
    }
    const input: MangaContinuousHorizontalViewportInput = this.createContinuousHorizontalViewportInput();
    const plan: MangaContinuousHorizontalViewportPlan =
      this.mangaContinuousHorizontalViewportPlanner.buildViewportPlan(input);
    this.visiblePageIndices = plan.visiblePageIndices;
    this.updateContinuousHorizontalProgress();
  }

  private createContinuousHorizontalViewportInput(): MangaContinuousHorizontalViewportInput {
    const input: MangaContinuousHorizontalViewportInput = new MangaContinuousHorizontalViewportInput();
    input.scrollLeft = this.scrollPosition;
    input.containerWidth = this.getContinuousHorizontalViewportWidth();
    input.pageRanges = this.createContinuousHorizontalPageRanges();
    return input;
  }

  private createContinuousHorizontalPageRanges(): MangaContinuousHorizontalPageRange[] {
    const ranges: MangaContinuousHorizontalPageRange[] = [];
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return ranges;
    }
    this.updateContinuousHorizontalDataSourceIfNeeded();
    const spacing: number = this.readingSettings.pageSpacing || 16;
    const scaleFactor: number = this.getContinuousHorizontalScaleFactor();
    const totalCount: number = this.continuousHorizontalDataSource.totalCount();
    let currentLeft: number = 0;

    for (let visualIndex = 0; visualIndex < totalCount; visualIndex++) {
      const pageIndex: number = this.continuousHorizontalDataSource.getData(visualIndex);
      if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
        continue;
      }
      const page: MangaPage = this.chapter.pages[pageIndex];
      const pageWidth: number = this.getStableContinuousHorizontalItemWidth(page);
      const range: MangaContinuousHorizontalPageRange = new MangaContinuousHorizontalPageRange();
      range.pageIndex = pageIndex;
      range.left = currentLeft * scaleFactor;
      range.right = (currentLeft + pageWidth) * scaleFactor;
      ranges.push(range);
      currentLeft += pageWidth + spacing;
    }
    return ranges;
  }

  /**
   * 更新水平连续滚动进度
   */
  private updateContinuousHorizontalProgress(): void {
    const input: MangaContinuousHorizontalProgressInput = this.createContinuousHorizontalProgressInput();
    const plan: MangaContinuousHorizontalProgressPlan =
      this.mangaContinuousHorizontalViewportPlanner.buildProgressPlan(input);
    if (plan.shouldUpdatePage) {
      this.currentWebtoonPage = plan.pageIndex;
      this.viewCurrentPageIndex = plan.pageIndex;
      this.currentPageIndex = plan.pageIndex;
      if (plan.shouldNotifyPageChange && this.callbacks.onPageChange) {
        this.callbacks.onPageChange(plan.pageIndex);
      }
    }
    if (plan.shouldUpdateProgress) {
      this.webtoonScrollProgress = plan.progress;
    }
  }

  private createContinuousHorizontalProgressInput(): MangaContinuousHorizontalProgressInput {
    const input: MangaContinuousHorizontalProgressInput = new MangaContinuousHorizontalProgressInput();
    input.hasPages = !!(this.chapter && this.chapter.pages && this.chapter.pages.length > 0);
    input.currentPageIndex = input.hasPages
      ? this.calculateContinuousHorizontalPageIndexFromScroll(this.scrollPosition)
      : 0;
    input.currentWebtoonPage = this.currentWebtoonPage;
    input.scrollPosition = this.scrollPosition;
    input.maxScroll = this.getContinuousHorizontalMaxScroll();
    input.isRtl = this.isContinuousHorizontalRTL();
    return input;
  }

  /**
   * 估算水平滚动模式下页面的宽度
   * 根据图片宽高比和屏幕高度计算
   */
  private getEstimatedImageWidthForHorizontal(page: MangaPage): number {
    const screenH = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    // 优先使用已知的图片尺寸
    if (page.width && page.height && page.width > 0 && page.height > 0) {
      return screenH * (page.width / page.height);
    }
    // 默认：假设典型漫画页面宽高比约为 2:3
    return screenH * 0.67;
  }

  /**
   * 节流更新可见页面
   */
  private throttledUpdateVisiblePages(): void {
    // 简单的节流实现，每100ms最多执行一次
    const now = Date.now();
    if (!this.lastUpdateTime || now - this.lastUpdateTime > 100) {
      this.updateVisiblePages();
      this.lastUpdateTime = now;
    }
  }

  /**
   * [性能优化] 节流执行条漫重型操作
   * 包括章节边界检测、章节切换检测、资源清理等耗时操作
   * 避免在快速滚动时频繁执行导致卡顿
   */
  private throttledWebtoonHeavyOperations(): void {
    const now = Date.now();
    const throttleMs = this.getWebtoonHeavyUpdateThrottleMs();
    if (now - this.lastHeavyUpdateTime < throttleMs) {
      return; // 还在节流间隔内，跳过
    }
    this.lastHeavyUpdateTime = now;
    
    // 检测章节边界，触发预加载
    this.checkWebtoonChapterBoundary();
    // 更新当前章节
    this.updateCurrentChapterFromScroll();
    // 清理远离可见区域的资源
    this.cleanupDistantChapterResources();
  }

  /**
   * 更新可见页面索引
   * [修复] 支持多章节模式，同时检测章节切换
   */
  private updateVisiblePages(): void {
    if (!this.scroller) return;
    const containerHeight: number = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    const scrollTop = this.scrollPosition;
    const scrollBottom = scrollTop + containerHeight;

    if (this.isWebtoonMode() && this.webtoonDataItems.length > 0) {
      const plan: MangaWebtoonViewportPlan = this.mangaWebtoonViewportPlanner.buildMultiChapterPlan(
        this.createWebtoonViewportInput(scrollTop, scrollBottom, containerHeight)
      );
      this.applyWebtoonViewportPlan(plan);
      this.updateWebtoonProgress();
      return;
    }

    const fallbackPlan: MangaWebtoonViewportPlan = this.mangaWebtoonViewportPlanner.buildFallbackPlan(
      this.createWebtoonFallbackViewportInput(scrollTop, scrollBottom, containerHeight)
    );
    this.applyWebtoonViewportPlan(fallbackPlan);

    // [性能优化] 章节检测和边界检查已经在 throttledWebtoonHeavyOperations 中节流执行
    // 不再在这里重复调用，避免性能问题

    // 更新当前页面和滚动进度
    this.updateWebtoonProgress();
  }

  private createWebtoonViewportInput(
    scrollTop: number,
    scrollBottom: number,
    containerHeight: number
  ): MangaWebtoonViewportInput {
    const input: MangaWebtoonViewportInput = new MangaWebtoonViewportInput();
    input.activeChapterId = (this.currentChapterId && this.findChapterBoundary(this.chapterBoundaries, this.currentChapterId))
      ? this.currentChapterId
      : this.chapter.id;
    input.rangeStart = scrollTop - containerHeight;
    input.rangeEnd = scrollBottom + containerHeight;

    const firstCandidateIndex: number = this.findFirstWebtoonVisibleCandidate(input.rangeStart);
    for (let i = firstCandidateIndex; i >= 0 && i < this.webtoonDataItems.length; i++) {
      const item: WebtoonDataItem = this.webtoonDataItems[i];
      if (!item) {
        continue;
      }
      const itemTop: number = this.calculateWebtoonItemScrollPosition(i);
      if (itemTop > input.rangeEnd) {
        break;
      }
      const itemRange: MangaWebtoonViewportItemRange = new MangaWebtoonViewportItemRange();
      itemRange.itemIndex = i;
      itemRange.isPage = item.type === 'page' && !!item.page;
      itemRange.chapterId = item.chapterId || this.chapter.id;
      itemRange.pageIndex = item.pageIndex !== undefined ? item.pageIndex : 0;
      itemRange.top = itemTop;
      itemRange.bottom = itemTop + this.getWebtoonItemEstimatedHeight(item);
      input.items.push(itemRange);
    }
    return input;
  }

  private createWebtoonFallbackViewportInput(
    scrollTop: number,
    scrollBottom: number,
    containerHeight: number
  ): MangaWebtoonFallbackViewportInput {
    const input: MangaWebtoonFallbackViewportInput = new MangaWebtoonFallbackViewportInput();
    input.rangeStart = scrollTop - containerHeight;
    input.rangeEnd = scrollBottom + containerHeight;
    const spacing: number = this.readingSettings.pageSpacing || 16;
    let currentTop: number = 0;
    for (let i = 0; i < this.chapter.pages.length; i++) {
      const page: MangaPage = this.chapter.pages[i];
      const pageHeight: number = this.getEstimatedImageHeight(page);
      const range: MangaWebtoonFallbackPageRange = new MangaWebtoonFallbackPageRange();
      range.pageIndex = i;
      range.top = currentTop;
      range.bottom = currentTop + pageHeight;
      input.pages.push(range);
      currentTop += pageHeight + spacing;
    }
    return input;
  }

  private applyWebtoonViewportPlan(plan: MangaWebtoonViewportPlan): void {
    this.visiblePageIndices = plan.visiblePageIndices;
    this.webtoonVisibleItemIndices = plan.visibleItemIndices;
  }

  /**
   * 更新条漫进度信息
   * [修复] 支持多章节模式，根据当前所在章节计算页码和进度
   */
  private updateWebtoonProgress(): void {
    const input: MangaWebtoonProgressInput = this.createWebtoonProgressInput();
    const plan: MangaWebtoonProgressPlan = this.mangaWebtoonViewportPlanner.buildProgressPlan(input);
    this.applyWebtoonProgressPlan(plan);
  }

  private createWebtoonProgressInput(): MangaWebtoonProgressInput {
    const input: MangaWebtoonProgressInput = new MangaWebtoonProgressInput();
    input.currentChapterId = this.currentChapterId;
    input.primaryChapterId = this.chapter ? this.chapter.id : '';
    input.visiblePageIndices = this.visiblePageIndices;
    input.currentWebtoonPage = this.currentWebtoonPage;
    input.scrollPosition = this.scrollPosition;
    input.containerHeight = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;

    const currentBoundary: ChapterBoundary | undefined = this.currentChapterId
      ? this.findChapterBoundary(this.chapterBoundaries, this.currentChapterId)
      : undefined;
    if (currentBoundary) {
      input.useMultiChapter = true;
      input.currentBoundaryPageCount = currentBoundary.pageCount;
      input.currentBoundaryPageIndex = this.calculateCurrentPageInChapter(
        currentBoundary,
        this.scrollPosition,
        input.containerHeight
      );
      return input;
    }

    if (this.chapter && this.chapter.pages && this.chapter.pages.length > 0) {
      input.fallbackTotalPages = this.chapter.pages.length;
      input.fallbackTotalHeight = this.calculateFallbackWebtoonTotalHeight();
    }
    return input;
  }

  private calculateFallbackWebtoonTotalHeight(): number {
    if (!this.chapter || !this.chapter.pages) {
      return 0;
    }
    const totalPages: number = this.chapter.pages.length;
    const spacing: number = this.readingSettings.pageSpacing || 16;
    let totalHeight: number = 0;
    for (let i = 0; i < totalPages; i++) {
      const page: MangaPage = this.chapter.pages[i];
      totalHeight += this.getEstimatedImageHeight(page);
      if (i < totalPages - 1) {
        totalHeight += spacing;
      }
    }
    return totalHeight;
  }

  private applyWebtoonProgressPlan(plan: MangaWebtoonProgressPlan): void {
    if (plan.shouldUpdatePage) {
      this.currentWebtoonPage = plan.pageIndex;
      this.viewCurrentPageIndex = plan.pageIndex;
      if (plan.shouldSyncExternalPage) {
        this.currentPageIndex = plan.pageIndex;
      }
      if (plan.shouldNotifyPageChange && this.callbacks.onPageChange) {
        this.callbacks.onPageChange(plan.pageIndex);
      }
    }

    if (plan.shouldUpdateProgress) {
      this.webtoonScrollProgress = plan.progress;
    }
  }

  // 条漫预加载逻辑已移至 PreloadManager，使用 triggerWebtoonPreload() 方法

  /**
   * 处理图片加载完成
   */
  private handleImageLoad(index: number): void {
    try {
      const page: MangaPage | undefined = (this.chapter && this.chapter.pages && index >= 0 && index < this.chapter.pages.length) ? this.chapter.pages[index] : undefined;
      if (!page) { return; }
      const loadState: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
      if (loadState) {
        loadState.isLoading = false;
        if (page.sourceType !== ImageSourceType.LOCAL) {
          loadState.isLoaded = true;
        }
        loadState.error = undefined;
        this.imageLoadStates.set(page.id, loadState);
        this.imageLoadStates = new Map(this.imageLoadStates);
      }
      this.pageImageBindings.set(index, page.id);
      this.pageImageBindings = new Map(this.pageImageBindings);
      logger.debug(TAG, `图片加载完成: index=${index}, id=${page.id}, pm=${this.pagePixelMaps.has(page.id)}`);
    } catch (error) {
      logger.error(TAG, `处理图片加载完成失败: 页面${index}`, String(error));
    }
  }

  /**
   * 处理图片加载错误
   */
  private handleImageError(index: number): void {
    try {
      const page: MangaPage | undefined = (this.chapter && this.chapter.pages && index >= 0 && index < this.chapter.pages.length) ? this.chapter.pages[index] : undefined;
      if (!page) { return; }
      const loadState: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
      if (loadState) {
        loadState.isLoading = false;
        loadState.isLoaded = false;
        loadState.error = '图片加载失败';
        this.imageLoadStates.set(page.id, loadState);
        this.imageLoadStates = new Map(this.imageLoadStates);
      }
      logger.error(TAG, `图片加载失败: index=${index}, id=${page.id}`);
    } catch (error) {
      logger.error(TAG, `处理图片加载错误失败: 页面${index}`, String(error));
    }
  }

  /**
   * 清理预加载的图片
   */
  private cleanupPreloadedImages(keepIndices: Set<number>): void {
    const toRemove: number[] = [];

    for (const index of this.preloadedImages) {
      if (!keepIndices.has(index)) {
        toRemove.push(index);
      }
    }

    for (const index of toRemove) {
      this.preloadedImages.delete(index);

      // 从缓存中移除对应的图片
      const page = this.chapter.pages[index];
      if (page && this.imageCache.has(page.imageUrl)) {
        this.removeFromImageCache(page.imageUrl);
      }
    }

    if (toRemove.length > 0) {
      logger.debug(TAG, `清理预加载图片: ${toRemove.length}张`);
      this.logMangaReaderCacheSnapshot('preloaded_images_cleaned');
    }
  }

  /**
   * 清理图片缓存
   */
  private cleanupImageCache(): void {
    const keys = Array.from(this.imageCache.keys());
    let removed: number = 0;
    for (let i = 0; i < keys.length; i++) {
      if (this.imageCacheSize <= this.MAX_CACHE_SIZE * this.CACHE_CLEANUP_THRESHOLD) {
        break;
      }
      const url = keys[i];
      this.removeFromImageCache(url);
      removed = removed + 1;
    }
    if (removed > 0) {
      logger.debug(TAG, `清理图片缓存: 移除${removed}项, 剩余缓存大小: ${this.imageCacheSize / 1024 / 1024}MB`);
      this.logMangaReaderCacheSnapshot('legacy_image_meta_trimmed');
    }
  }

  /**
   * 从缓存中移除图片
   */
  private removeFromImageCache(imageUrl: string): void {
    if (this.imageCache.has(imageUrl)) {
      const meta: ImageCacheMeta | undefined = this.imageCache.get(imageUrl);
      const sizeNum: number = meta && meta.size ? meta.size : 1024 * 1024;
      this.imageCacheSize = Math.max(0, this.imageCacheSize - sizeNum);
      this.imageCache.delete(imageUrl);
    }
  }

  /**
   * 构建优化的图片组件
   */
  @Builder
  buildOptimizedImage(page: MangaPage, index: number) {
    if (this.shouldShowImage(index)) {
      Stack() {
        // 网络图片：仅在有PixelMap或已加载完成时显示Image，加载中/失败时完全隐藏
        // 本地图片：始终显示
        if (page.sourceType === ImageSourceType.LOCAL
          || this.pagePixelMaps.has(page.id)
          || (this.getPageLoadState(page)?.isLoaded === true)) {
          Image(this.getDisplayImageInput(page))
            .width('100%')
            .objectFit(this.getImageFitMode(page))
            .onAppear(() => {
              this.logImageDisplayBefore(page, this.getDisplayImageInput(page));
            })
            .onComplete(() => {
              this.handleImageLoad(index);
              // 图片加载完成后，添加到缓存
              this.addToImageCache(page.imageUrl, index);
              this.logImageDisplayAfter(page, true);
            })
            .onError((error: ImageError) => {
              this.handleImageComponentError(page, error, `optimized_${index}`);
            })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }
        
        // 显示加载动画
        if (this.shouldShowLoadingForPage(page)) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(colorMap.accent)
            Text('加载中...')
              .fontSize(14)
              .fontColor(colorMap.textSecondary)
              .margin({ top: 8 })
          }
          .width('100%')
          .height(this.getEstimatedImageHeight(page))
          .justifyContent(FlexAlign.Center)
        }
        
        // 显示加载失败提示
        if (this.getPageLoadState(page)?.error) {
          Column() {
            Image($r('sys.symbol.exclamationmark_circle_fill'))
              .width(48)
              .height(48)
              .fillColor(colorMap.error)
            Text('加载失败')
              .fontSize(14)
              .fontColor(colorMap.textPrimary)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 8 })
            Text(this.getPageLoadState(page)?.error || '图片加载失败')
              .fontSize(12)
              .fontColor(colorMap.textSecondary)
              .margin({ top: 4 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('重试')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor(colorMap.accent)
              .borderRadius(8)
              .padding({ left: 24, right: 24, top: 8, bottom: 8 })
              .margin({ top: 12 })
              .onClick(() => {
                logger.info(TAG, `用户点击重试加载(优化图片): pageId=${page.id}`);
                this.retryLoadPage(page);
              })
          }
          .width('100%')
          .height(this.getEstimatedImageHeight(page))
          .justifyContent(FlexAlign.Center)
          .padding(16)
        }
      }
      .width('100%')
    } else {
      // 占位符，保持布局稳定
      Column()
        .width('100%')
        .height(this.getEstimatedImageHeight(page))
        .backgroundColor(Color.Transparent)
    }
  }

  /**
   * 添加图片到缓存
   */
  private addToImageCache(imageUrl: string, pageIndex: number): void {
    if (!this.imageCache.has(imageUrl)) {
      const estimatedSize: number = 1024 * 1024;
      if (this.imageCacheSize + estimatedSize <= this.MAX_CACHE_SIZE) {
        const meta: ImageCacheMeta = { path: imageUrl, size: estimatedSize } as ImageCacheMeta;
        this.imageCache.set(imageUrl, meta);
        this.imageCacheSize += estimatedSize;
        logger.debug(TAG, `图片已缓存: 页面${pageIndex}, 缓存大小: ${this.imageCacheSize / 1024 / 1024}MB`);
      } else {
        this.cleanupImageCache();
        if (this.imageCacheSize + estimatedSize <= this.MAX_CACHE_SIZE) {
          const meta2: ImageCacheMeta = { path: imageUrl, size: estimatedSize } as ImageCacheMeta;
          this.imageCache.set(imageUrl, meta2);
          this.imageCacheSize += estimatedSize;
        }
      }
    }
  }

  /**
   * 获取条漫模式的实际内容宽度（考虑左右边距）
   * 条漫容器的padding使用百分比，实际图片宽度 = 屏幕宽度 * (1 - 左边距% - 右边距%)
   */
  private getWebtoonContentWidth(): number {
    const context: MangaWebtoonPositionContext = this.createWebtoonPositionContext();
    const sw: number = context.screenWidth > 0 ? context.screenWidth : 360;
    if (context.webtoonLeftMargin > 0 || context.webtoonRightMargin > 0) {
      return sw * (1 - context.webtoonLeftMargin / 100 - context.webtoonRightMargin / 100);
    }
    return sw;
  }

  /**
   * 获取预估图片高度
   * [修复①] 条漫模式下使用实际内容宽度（扣除边距）计算高度
   * 之前用 screenWidth 计算导致高度偏大，ImageFit.Contain 居中后产生上下空白
   */
  private getEstimatedImageHeight(page: MangaPage): number {
    return this.mangaWebtoonPositionManager.getEstimatedImageHeight(page, this.createWebtoonPositionContext());
  }

  /**
   * 获取图片加载优先级
   */
  private getImageLoadPriority(pageIndex: number): 'high' | 'normal' | 'low' {
    if (this.visiblePageIndices.includes(pageIndex)) {
      return 'high';
    } else if (this.preloadedImages.has(pageIndex)) {
      return 'normal';
    } else {
      return 'low';
    }
  }

  private getDynamicPreloadRange(): number {
    // 优先使用图源设置的预加载页数
    const configuredPreload = this.preloadCurrentPages !== undefined ? this.preloadCurrentPages : 10;

    // 如果设置为0，返回0（不预加载）
    if (configuredPreload <= 0) {
      return 0;
    }

    // 基础范围使用配置值
    let base: number = configuredPreload;

    // 根据滚动状态动态调整
    if (this.isScrolling) {
      // 滚动时减少预加载范围，避免过多并发请求
      base = Math.max(2, Math.floor(base * 0.6));
    } else {
      // 静止时增加预加载范围
      base = base + 2;
    }

    // 缩放时减少预加载
    if (this.webtoonZoomScale > 1.0) {
      base = Math.max(2, base - 1);
    }

    // 大屏幕增加预加载
    const ch: number = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    if (ch > 1200) {
      base = base + 2;
    }

    logger.debug(TAG, `动态预加载范围: 配置=${configuredPreload}, 最终=${base}, 滚动=${this.isScrolling}, 缩放=${this.webtoonZoomScale}`);
    return base;
  }

  /**
   * 新增：统一的预加载触发方法
   * 使用新的PreloadManager管理预加载队列
   */
  private triggerUnifiedPreload(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    if (this.isWebtoonMode()) {
      this.triggerWebtoonPreload();
      return;
    }

    const input: MangaNormalPreloadInput = new MangaNormalPreloadInput();
    input.pages = this.chapter.pages;
    input.currentIndex = this.viewCurrentPageIndex;
    input.range = this.getDynamicPreloadRange();
    const plan: MangaPreloadPlan = this.mangaPreloadPlanner.buildNormalPlan(input);
    this.applyPreloadPlan(plan);
  }

  private applyPreloadPlan(plan: MangaPreloadPlan, shouldInitTargets: boolean = true): void {
    this.updatePreloadManagerVisiblePages(plan);
    if (shouldInitTargets) {
      this.initPreloadPlanTargets(plan);
    }

    if (plan.shouldApplyPageInfo) {
      this.preloadManager.setPageInfo(plan.currentIndex, plan.totalCount);
      this.preloadManager.setPreloadRange(plan.range);
    }

    if (plan.tasks.length > 0) {
      this.preloadManager.addBatch(plan.tasks);
    }

    if (plan.shouldProcessQueue) {
      this.processPreloadQueue();
    }

    if (plan.shouldScheduleQueue && plan.tasks.length > 0) {
      this.scheduleProcessPreloadQueue(plan.scheduleDelay);
    }

    if (plan.shouldCleanupWebtoonCompleted && plan.tasks.length > 0) {
      this.preloadManager.cleanupDistantCompletedForWebtoon();
    }
  }

  private initPreloadPlanTargets(plan: MangaPreloadPlan): void {
    for (let i = 0; i < plan.initTargets.length; i++) {
      const target: MangaPreloadInitTarget = plan.initTargets[i];
      this.imageLoadStateManager.initPage(target.pageId, target.pageIndex);
    }
  }

  private updatePreloadManagerVisiblePages(plan: MangaPreloadPlan): void {
    if (plan.visibleIndicesForManager.length > 0) {
      this.preloadManager.updateVisiblePages(plan.visibleIndicesForManager);
    }
  }

  /**
   * 新增：处理预加载队列
   * 支持并发加载多个图片
   */
  private processPreloadQueue(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    const runnableBatch: MangaPreloadRunnableBatch = this.mangaPreloadTaskCoordinator.takeRunnableTasks(
      this.preloadManager,
      this.imageLoadStateManager,
      this.contentType ? this.contentType : ''
    );
    const nextBatch: PreloadTaskItem[] = runnableBatch.tasks;
    if (nextBatch.length <= 0) {
      return;
    }
    
    // 开始加载每个任务
    for (let i = 0; i < nextBatch.length; i++) {
      const task: PreloadTaskItem = nextBatch[i];

      const resolved: MangaPreloadPageResolveResult = this.mangaPageLoadResolver.resolvePreloadTask(
        task,
        this.createMangaPageResolveContext()
      );
      const page: MangaPage | null = resolved.page;

      if (!page) {
        this.mangaPreloadTaskCoordinator.markTaskPageMissing(this.preloadManager, this.imageLoadStateManager, task);
        const staleState: ImageLoadState | undefined = this.imageLoadStates.get(task.pageId);
        if (staleState && staleState.isLoading && !staleState.isLoaded) {
          staleState.isLoading = false;
          staleState.error = '页面已失效';
          this.imageLoadStates.set(task.pageId, staleState);
          this.imageLoadStates = new Map(this.imageLoadStates);
        }
        continue;
      }

      const loadQueueIndex: number = resolved.loadQueueIndex >= 0 ? resolved.loadQueueIndex : task.pageIndex;
      this.mangaPreloadTaskCoordinator.markTaskReady(this.imageLoadStateManager, task);
      this.loadImageWithNewManager(page, loadQueueIndex).catch((error: Error) => {
        logger.warn(TAG, `预加载任务执行异常: pageId=${task.pageId}, error=${error.message}`);
      });
    }
  }

  /**
   * [性能修复] 延迟调度 processPreloadQueue，确保同一时刻只有一个待执行的定时器
   * 防止大量本地图片在条漫模式下快速递归调度导致主线程阻塞
   */
  private scheduleProcessPreloadQueue(delay: number = 50): void {
    if (this.processPreloadQueueTimer !== -1) {
      return; // 已有待执行的定时器，无需重复调度
    }
    this.processPreloadQueueTimer = setTimeout(() => {
      this.processPreloadQueueTimer = -1;
      this.processPreloadQueue();
    }, delay);
  }

  /**
   * 【架构核心】使用统一缓存机制加载图片
   * 确保所有网络图片都转换为PixelMap后才显示
   * [性能修复] 本地图片在条漫模式下委托给 LocalImageCacheManager，避免双重PixelMap
   */
  private async loadImageWithNewManager(page: MangaPage, pageIndex: number): Promise<void> {
    const pageId = page.id;
    const requestUrl = page.sourceType === ImageSourceType.LOCAL
      ? (this.getFsPathFromPage(page) || page.imageUrl || '')
      : (page.imageUrl || '');

    // [性能修复] 本地图片在条漫模式下不应通过此路径加载
    // 因为 triggerLocalImageLoad 已经通过 LocalImageCacheManager 降采样加载
    // 此处再创建全分辨率 PixelMap 会导致内存爆炸
    if (page.sourceType === ImageSourceType.LOCAL && this.isWebtoonMode()) {
      // 委托给 LocalImageCacheManager，不创建重复的全分辨率 PixelMap
      const chapterId = this.chapter ? this.chapter.id : '';
      this.triggerLocalImageLoad(page, chapterId, pageIndex);
      this.imageLoadStates = this.mangaLoadStateCommitter.markDelegated(
        pageId,
        pageIndex,
        this.imageLoadStates,
        this.preloadManager
      );
      // [性能修复] 使用去重调度，避免递归洪泛导致 THREAD_BLOCK_6S
      this.scheduleProcessPreloadQueue(50);
      return;
    }

    if (!requestUrl || requestUrl.length === 0) {
      const errorMsg = '图片URL为空';
      this.imageLoadStates = this.mangaLoadStateCommitter.markFailed(
        pageId,
        pageIndex,
        errorMsg,
        this.imageLoadStates,
        this.imageLoadStateManager,
        this.preloadManager
      );
      this.scheduleProcessPreloadQueue(50);
      return;
    }

    this.imageLoadStates = this.mangaLoadStateCommitter.markLoading(
      pageId,
      pageIndex,
      this.imageLoadStates,
      this.imageLoadStateManager,
      this.preloadManager
    );
    const sessionSnapshot: MangaReaderSessionSnapshot = this.captureMangaReaderSession();

    try {
      // 1. 检查内存缓存（pagePixelMaps）
      const memCached = this.pagePixelMaps.get(pageId);
      if (memCached) {
        logger.debug(TAG, `[架构] 内存缓存命中: P${pageIndex + 1}`);
        this.imageLoadStates = this.mangaLoadStateCommitter.markMemCacheHit(
          pageId,
          pageIndex,
          memCached,
          this.imageLoadStates,
          this.imageLoadStateManager,
          this.preloadManager
        );
        this.notifyPixelMapLoaded(page);
        return;
      }

      // 2. 从统一漫画资产管线加载 PixelMap，预加载与可见页使用同一套去重/监控协议
      const result: MangaAssetLoadResult = await this.loadPixelMapWithAssetPipeline(
        page,
        pageIndex,
        this.isPageCurrentlyVisible(page) ? MangaAssetLoadReason.VISIBLE : MangaAssetLoadReason.PRELOAD
      );
      this.recordReadFlowAssetEvent(
        MangaReadFlowEventType.ASSET_LOADED,
        page,
        pageIndex,
        this.isPageCurrentlyVisible(page) ? 'visible' : 'preload',
        result.elapsedMs,
        result.success,
        String(result.source),
        result.errorMessage
      );
      if (!this.isMangaReaderSessionActive(sessionSnapshot, page)) {
        logger.warn(TAG, `[架构] 丢弃过期预加载结果: P${pageIndex + 1}, id=${pageId}`);
        this.recordReadFlowEvent(
          MangaReadFlowEventType.CLEANUP,
          page,
          pageIndex,
          'stale_preload_discarded',
          `pageId=${pageId}`
        );
        return;
      }
      const cachedPixelMap: image.PixelMap | null = result.pixelMap;

      if (result.success && cachedPixelMap) {
        logger.info(TAG, `[架构] 统一资产管线加载成功: P${pageIndex + 1}`);
        this.commitPagePixelMap(pageId, cachedPixelMap);
        this.incrementPixelMapEpoch(pageId);
        this.imageLoadStates = this.mangaLoadStateCommitter.markPreloadLoaded(
          pageId,
          pageIndex,
          cachedPixelMap,
          this.imageLoadStates,
          this.imageLoadStateManager,
          this.preloadManager
        );
        this.notifyPixelMapLoaded(page);
        this.cleanupInvisiblePixelMaps();
        
        return;
      }

      const resultError: string = result.errorMessage.length > 0 ? result.errorMessage : '统一资产管线加载失败：返回空PixelMap';
      throw new Error(resultError);
      
    } catch (error) {
      if (!this.isMangaReaderSessionActive(sessionSnapshot, page)) {
        logger.warn(TAG, `[架构] 忽略过期预加载异常: P${pageIndex + 1}, id=${pageId}`);
        return;
      }
      const errorMsg: string = String(error);
      logger.error(TAG, `[架构] 加载失败: P${pageIndex + 1}, error=${errorMsg}`);
      this.imageLoadStates = this.mangaLoadStateCommitter.markFailed(
        pageId,
        pageIndex,
        errorMsg,
        this.imageLoadStates,
        this.imageLoadStateManager,
        this.preloadManager
      );
      
      if (!this.isWebtoonMode() && pageIndex === this.viewCurrentPageIndex) {
        this.updateSinglePageDisplay();
      }

      if (this.isWebtoonMode() && this.isPageCurrentlyVisible(page)) {
        const dataIndex = this.findWebtoonDataIndex(pageId);
        if (dataIndex >= 0) {
          this.webtoonDataSource.notifyDataChange(dataIndex);
        }
      }
    } finally {
      this.scheduleProcessPreloadQueue(50);
    }
  }

  /**
   * 条漫模式专用：基于可见页面的统一预加载
   */
  private triggerWebtoonPreload(): void {
    if (!this.isWebtoonMode()) {
      return;
    }

    if (!this.chapter || !this.chapter.pages) {
      return;
    }

    const input: MangaWebtoonPreloadInput = new MangaWebtoonPreloadInput();
    input.chapterPages = this.chapter.pages;
    input.webtoonDataItems = this.webtoonDataItems;
    input.visibleItemIndices = this.getWebtoonVisibleItemIndicesForPreload();
    input.visiblePageIndices = this.visiblePageIndices;
    input.currentItemIndex = this.getCurrentWebtoonItemIndexForPreload();
    input.range = this.preloadCurrentPages !== undefined ? Math.max(1, this.preloadCurrentPages) : 8;

    const plan: MangaPreloadPlan = this.mangaPreloadPlanner.buildWebtoonPlan(input);
    this.applyPreloadPlan(plan);
  }

  /**
   * 检查图片是否应该显示
   */
  private shouldShowImage(index: number): boolean {
    // 为避免滚动过程中图片闪烁与消失，始终显示
    return true;
  }

  /**
   * 初始化滚动位置键
   */
  private initScrollPositionKey(): void {
    if (this.chapter && this.chapter.id) {
      this.scrollPositionKey = `webtoon_scroll_${this.chapter.id}`;
    }
  }

  /**
   * 保存滚动位置
   */
  private saveScrollPosition(): void {
    if (this.scrollPositionKey) {
      try {
        const normalizedPosition = Math.max(0, this.scrollPosition);
        // 使用AppStorage保存滚动位置
        AppStorage.setOrCreate(this.scrollPositionKey, normalizedPosition);
        logger.debug(TAG, `保存滚动位置: ${normalizedPosition}`);
      } catch (error) {
        logger.error(TAG, `保存滚动位置失败: ${error}`);
      }
    }
  }

  /**
   * 恢复滚动位置
   */
  private restoreScrollPosition(): void {
    if (this.scrollPositionKey) {
      try {
        const savedPosition = AppStorage.get<number>(this.scrollPositionKey);
        if (savedPosition && savedPosition > 0) {
          this.savedScrollPosition = savedPosition;
          // 延迟恢复滚动位置，确保组件已完全渲染
          setTimeout(() => {
            if (this.isContinuousScrollMode()) {
              this.smoothScrollToHorizontal(savedPosition);
            } else {
              this.smoothScrollTo(savedPosition);
            }
          }, 100);
          logger.debug(TAG, `恢复滚动位置: ${savedPosition}`);
        }
      } catch (error) {
        logger.error(TAG, `恢复滚动位置失败: ${error}`);
      }
    }
  }

  /**
   * 平滑滚动到指定位置
   * 支持自定义动画参数，实现更自然的滚动效果
   */
  private smoothScrollTo(targetPosition: number, duration: number = 500, curve: ICurve = curves.initCurve(Curve.EaseInOut)): void {
    if (!this.scroller) {
      logger.warn(TAG, 'Scroller未初始化，无法执行平滑滚动');
      return;
    }

    try {
      // 确保目标位置在有效范围内
      const maxScrollPosition = this.calculateMaxScrollPosition();
      const clampedTargetPosition = Math.max(0, Math.min(targetPosition, maxScrollPosition));

      this.smoothScrollTarget = clampedTargetPosition;
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: clampedTargetPosition,
        animation: {
          duration: duration,
          curve: curve
        }
      });
      logger.debug(TAG, `平滑滚动到位置: ${clampedTargetPosition} (原始: ${targetPosition}), 时长: ${duration}ms, 曲线: ${curve}`);
    } catch (error) {
      logger.error(TAG, `平滑滚动失败: ${error}`);
    }
  }

  /**
   * 计算最大滚动位置
   */
  private calculateMaxScrollPosition(): number {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return 0;
    }

    const ch: number = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    return this.mangaWebtoonPositionManager.calculateMaxScrollPosition(
      this.chapter.pages,
      ch,
      this.createWebtoonPositionContext()
    );
  }

  /**
   * [新增] 直接跳转到指定页面（无动画）
   * 用于条漫模式初始化时直接定位到阅读记录位置
   * @param targetPageIndex 目标页面索引
   */
  public jumpToPageImmediate(targetPageIndex: number): boolean {
    if ((!this.isWebtoonMode() && !this.isContinuousScrollMode()) || !this.scroller) {
      return false;
    }
    
    try {
      if (this.isContinuousScrollMode()) {
        const targetScrollX = this.getContinuousHorizontalPageTargetX(targetPageIndex);
        this.suppressContinuousHorizontalBoundary();
        this.scroller.scrollTo({
          xOffset: targetScrollX,
          yOffset: 0
        });
        this.scrollPosition = targetScrollX;
        this.currentWebtoonPage = targetPageIndex;
        this.viewCurrentPageIndex = targetPageIndex;
        this.visiblePageIndices = [targetPageIndex];
        this.triggerUnifiedPreload();
        return true;
      }

      const targetScrollY = this.calculatePageScrollPosition(targetPageIndex);
      
      // 直接设置滚动位置，无动画
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: targetScrollY
      });
      
      // 更新内部状态
      this.scrollPosition = targetScrollY;
      this.viewCurrentPageIndex = targetPageIndex;
      
      logger.info(TAG, `条漫模式直接跳转到页面: ${targetPageIndex + 1}, 位置: ${targetScrollY}`);
      return true;
    } catch (error) {
      logger.error(TAG, `条漫模式直接跳转失败: ${error}`);
      return false;
    }
  }

  /**
   * 平滑滚动到指定页面（条漫模式）
   * 支持精确的页面定位和动画效果
   * @param targetPageIndex 目标页面索引
   * @param scrollSpeed 滚动速度因子（0.5-2.0，1.0为正常速度）
   * @param onComplete 滚动完成回调
   */
  public smoothScrollToPage(targetPageIndex: number, scrollSpeed: number = 1.0, onComplete?: () => void): boolean {
    if ((!this.isWebtoonMode() && !this.isContinuousScrollMode()) || !this.scroller) {
      return false;
    }

    try {
      if (this.isContinuousScrollMode()) {
        const targetScrollX = this.getContinuousHorizontalPageTargetX(targetPageIndex);
        const normalizedSpeed = Math.max(0.5, Math.min(2.0, scrollSpeed));
        const distance = Math.abs(this.scrollPosition - targetScrollX);
        const baseDuration = Math.min(1000, Math.max(300, distance / 2));
        const duration = Math.max(300, Math.min(1200, baseDuration / normalizedSpeed));
        this.smoothScrollToHorizontalWithDuration(targetScrollX, duration);

        setTimeout(() => {
          if (targetPageIndex !== this.currentPageIndex && this.callbacks.onPageChange) {
            this.callbacks.onPageChange(targetPageIndex);
          }
          if (onComplete) {
            onComplete();
          }
        }, duration);
        return true;
      }

      const targetScrollY = this.calculatePageScrollPosition(targetPageIndex);

      // 计算动画时长，根据滚动距离和速度调整
      const distance = Math.abs(this.scrollPosition - targetScrollY);
      const baseDuration = Math.min(1000, Math.max(300, distance / 2)); // 根据距离调整基础时长
      const duration = Math.max(300, Math.min(1200, baseDuration / scrollSpeed));

      // 使用平滑的动画曲线
      const curve: ICurve = curves.initCurve(Curve.EaseInOut);

      // 执行平滑滚动动画
      this.smoothScrollTo(targetScrollY, duration, curve);

      // 更新当前页面索引（滚动完成后）
      setTimeout(() => {
        // 只有在需要更新页面索引时才调用回调
        if (targetPageIndex !== this.currentPageIndex && this.callbacks.onPageChange) {
          this.callbacks.onPageChange(targetPageIndex);
        }
        // 调用完成回调
        if (onComplete) {
          onComplete();
        }
      }, duration);

      logger.debug(TAG, `条漫平滑滚动到页面: ${this.currentPageIndex + 1} -> ${targetPageIndex + 1}, 滚动位置: ${this.scrollPosition} -> ${targetScrollY}, 时长: ${duration}ms`);
      return true;
    } catch (error) {
      logger.error(TAG, `条漫平滑滚动失败: ${error}`);
      return false;
    }
  }

  /**
   * 平滑滚动到下一页（条漫模式自动翻页）
   * 实现信息流式的平滑滚动效果
   * @param scrollSpeed 滚动速度因子（0.5-2.0，1.0为正常速度）
   * @param scrollDistance 滚动距离（'page'表示滚动一页，'screen'表示滚动一屏）
   * @param onComplete 滚动完成回调
   */
  public smoothScrollToNextPage(scrollSpeed: number = 1.0, scrollDistance: 'page' | 'screen' = 'page', onComplete?: () => void): boolean {
    if ((!this.isWebtoonMode() && !this.isContinuousScrollMode()) || !this.scroller) {
      return false;
    }

    try {
      if (this.isContinuousScrollMode()) {
        const currentScrollX = this.scrollPosition;
        const normalizedSpeed = Math.max(0.5, Math.min(2.0, scrollSpeed));
        const currentPageIndex = this.viewCurrentPageIndex;
        let targetScrollX: number;
        let nextPageIndex: number;

        if (scrollDistance === 'screen') {
          const screenWidth = this.getContinuousHorizontalViewportWidth();
          const proposedTarget = this.isContinuousHorizontalRTL()
            ? Math.max(0, currentScrollX - screenWidth * 0.8)
            : Math.min(this.getContinuousHorizontalMaxScroll(), currentScrollX + screenWidth * 0.8);
          const candidateIndex = this.calculateContinuousHorizontalPageIndexFromScroll(proposedTarget);
          if (candidateIndex <= currentPageIndex) {
            nextPageIndex = Math.min(currentPageIndex + 1, this.chapter.pages.length - 1);
            targetScrollX = this.getContinuousHorizontalPageTargetX(nextPageIndex);
          } else {
            nextPageIndex = candidateIndex;
            targetScrollX = proposedTarget;
          }
        } else {
          nextPageIndex = Math.min(currentPageIndex + 1, this.chapter.pages.length - 1);
          targetScrollX = this.getContinuousHorizontalPageTargetX(nextPageIndex);
        }

        if (Math.abs(currentScrollX - targetScrollX) < 1 && nextPageIndex === currentPageIndex) {
          return false;
        }

        const baseDuration = scrollDistance === 'screen' ? 800 : 600;
        const duration = Math.max(300, Math.min(1200, baseDuration / normalizedSpeed));
        this.smoothScrollToHorizontalWithDuration(targetScrollX, duration);

        setTimeout(() => {
          if (nextPageIndex !== this.currentPageIndex && this.callbacks.onPageChange) {
            this.callbacks.onPageChange(nextPageIndex);
          }
          if (onComplete) {
            onComplete();
          }
        }, duration);
        return true;
      }

      const currentScrollY = this.scrollPosition;
      let targetScrollY: number;
      let nextPageIndex: number;

      if (scrollDistance === 'screen') {
        const screenHeight: number = 800;
        const proposedTarget: number = currentScrollY + screenHeight * 0.8;
        const candidateIndex: number = this.calculatePageIndexFromScroll(proposedTarget);
        if (candidateIndex <= this.currentPageIndex) {
          nextPageIndex = Math.min(this.currentPageIndex + 1, this.chapter.pages.length - 1);
          targetScrollY = this.calculatePageScrollPosition(nextPageIndex);
        } else {
          nextPageIndex = candidateIndex;
          targetScrollY = proposedTarget;
        }
      } else {
        // 滚动到下一页
        nextPageIndex = Math.min(this.currentPageIndex + 1, this.chapter.pages.length - 1);
        targetScrollY = this.calculatePageScrollPosition(nextPageIndex);
      }

      // 如果已经在底部，不再滚动
      if (currentScrollY >= targetScrollY && nextPageIndex === this.chapter.pages.length - 1) {
        return false;
      }

      // 计算动画时长，根据滚动速度调整
      const baseDuration = scrollDistance === 'screen' ? 800 : 600; // 屏幕滚动稍慢
      const duration = Math.max(300, Math.min(1200, baseDuration / scrollSpeed));

      // 使用更自然的动画曲线
      const curve: ICurve = scrollDistance === 'screen' ? curves.initCurve(Curve.EaseOut) : curves.initCurve(Curve.EaseInOut);

      // 执行平滑滚动动画
      this.smoothScrollTo(targetScrollY, duration, curve);

      // 更新当前页面索引（滚动完成后）
      setTimeout(() => {
        // 只有在需要更新页面索引时才调用回调
        if (nextPageIndex !== this.currentPageIndex && this.callbacks.onPageChange) {
          this.callbacks.onPageChange(nextPageIndex);
        }
        // 调用完成回调
        if (onComplete) {
          onComplete();
        }
      }, duration);

      logger.debug(TAG, `条漫自动翻页滚动: 页面${this.currentPageIndex + 1} -> ${nextPageIndex + 1}, 滚动位置: ${currentScrollY} -> ${targetScrollY}, 时长: ${duration}ms`);
      return true;
    } catch (error) {
      logger.error(TAG, `条漫自动翻页滚动失败: ${error}`);
      return false;
    }
  }

  /**
   * 根据滚动位置计算页面索引
   */
  private calculatePageIndexFromScroll(scrollY: number): number {
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return 0;
    }

    const spacing = this.readingSettings.pageSpacing || 16;
    let currentPosition = 0;

    for (let i = 0; i < this.chapter.pages.length; i++) {
      const page = this.chapter.pages[i];
      const pageHeight = this.getEstimatedImageHeight(page);

      // 检查滚动位置是否在当前页面范围内
      if (scrollY >= currentPosition && scrollY < currentPosition + pageHeight) {
        return i;
      }

      currentPosition += pageHeight + spacing;
    }

    return this.chapter.pages.length - 1; // 默认返回最后一页
  }

  /**
   * 平滑滚动到上一页（条漫模式）
   * 实现信息流式的向上滚动效果
   * @param scrollSpeed 滚动速度因子（0.5-2.0，1.0为正常速度）
   * @param scrollDistance 滚动距离（'page'表示滚动一页，'screen'表示滚动一屏）
   * @param onComplete 滚动完成回调
   */
  public smoothScrollToPreviousPage(scrollSpeed: number = 1.0, scrollDistance: 'page' | 'screen' = 'page', onComplete?: () => void): boolean {
    if ((!this.isWebtoonMode() && !this.isContinuousScrollMode()) || !this.scroller) {
      return false;
    }

    try {
      if (this.isContinuousScrollMode()) {
        const currentScrollX = this.scrollPosition;
        const normalizedSpeed = Math.max(0.5, Math.min(2.0, scrollSpeed));
        const currentPageIndex = this.viewCurrentPageIndex;
        let targetScrollX: number;
        let prevPageIndex: number;

        if (scrollDistance === 'screen') {
          const screenWidth = this.getContinuousHorizontalViewportWidth();
          const proposedTarget = this.isContinuousHorizontalRTL()
            ? Math.min(this.getContinuousHorizontalMaxScroll(), currentScrollX + screenWidth * 0.8)
            : Math.max(0, currentScrollX - screenWidth * 0.8);
          const candidateIndex = this.calculateContinuousHorizontalPageIndexFromScroll(proposedTarget);
          if (candidateIndex >= currentPageIndex) {
            prevPageIndex = Math.max(0, currentPageIndex - 1);
            targetScrollX = this.getContinuousHorizontalPageTargetX(prevPageIndex);
          } else {
            prevPageIndex = candidateIndex;
            targetScrollX = proposedTarget;
          }
        } else {
          prevPageIndex = Math.max(0, currentPageIndex - 1);
          targetScrollX = this.getContinuousHorizontalPageTargetX(prevPageIndex);
        }

        if (Math.abs(currentScrollX - targetScrollX) < 1 && prevPageIndex === currentPageIndex) {
          return false;
        }

        const baseDuration = scrollDistance === 'screen' ? 800 : 600;
        const duration = Math.max(300, Math.min(1200, baseDuration / normalizedSpeed));
        this.smoothScrollToHorizontalWithDuration(targetScrollX, duration);

        setTimeout(() => {
          if (this.callbacks.onPageChange) {
            this.callbacks.onPageChange(prevPageIndex);
          }
          if (onComplete) {
            onComplete();
          }
        }, duration);
        return true;
      }

      const currentScrollY = this.scrollPosition;
      let targetScrollY: number;
      let prevPageIndex: number;

      if (scrollDistance === 'screen') {
        // 向上滚动一屏距离
        const screenHeight = 800; // 假设屏幕高度
        targetScrollY = Math.max(0, currentScrollY - screenHeight * 0.8); // 向上滚动80%屏幕高度

        // 根据滚动位置计算目标页面索引
        prevPageIndex = this.calculatePageIndexFromScroll(targetScrollY);
      } else {
        // 滚动到上一页
        prevPageIndex = Math.max(0, this.currentPageIndex - 1);
        targetScrollY = this.calculatePageScrollPosition(prevPageIndex);
      }

      // 如果已经在顶部，不再滚动
      if (currentScrollY <= targetScrollY && prevPageIndex === 0) {
        return false;
      }

      // 计算动画时长，根据滚动速度调整
      const baseDuration = scrollDistance === 'screen' ? 800 : 600; // 屏幕滚动稍慢
      const duration = Math.max(300, Math.min(1200, baseDuration / scrollSpeed));

      // 使用更自然的动画曲线
      const curve: ICurve = scrollDistance === 'screen' ? curves.initCurve(Curve.EaseOut) : curves.initCurve(Curve.EaseInOut);

      // 执行平滑滚动动画
      this.smoothScrollTo(targetScrollY, duration, curve);

      // 更新当前页面索引（滚动完成后）
      setTimeout(() => {
        if (this.callbacks.onPageChange) {
          this.callbacks.onPageChange(prevPageIndex);
        }
        // 调用完成回调
        if (onComplete) {
          onComplete();
        }
      }, duration);

      logger.debug(TAG, `条漫向上滚动: 页面${this.currentPageIndex + 1} -> ${prevPageIndex + 1}, 滚动位置: ${currentScrollY} -> ${targetScrollY}, 时长: ${duration}ms`);
      return true;
    } catch (error) {
      logger.error(TAG, `条漫向上滚动失败: ${error}`);
      return false;
    }
  }

  /**
   * 计算指定页面的滚动位置
   * 考虑页面高度、间距和当前缩放比例
   */
  private calculatePageScrollPosition(pageIndex: number): number {
    return this.mangaWebtoonPositionManager.calculatePageScrollPosition(
      pageIndex,
      this.chapter.pages,
      this.scrollPosition,
      this.createWebtoonPositionContext()
    );
  }

  /**
   * 构建章节分隔组件（条漫模式用）
   * 在前一章结束和下一章开始之间显示
   */
  @Builder
  buildChapterDivider(item: WebtoonDataItem) {
    Column() {
      // 分隔线
      Divider()
        .width('80%')
        .height(1)
        .color(colorMap.divider)
        .margin({ bottom: 16 })

      // 章节信息区域
      Column() {
        if (item.direction === 'prev') {
          // 上一章结束提示
          Text('— 上一章 —')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ bottom: 8 })
          Text(item.chapterTitle || '未知章节')
            .fontSize(16)
            .fontColor(colorMap.textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        } else {
          // 下一章开始提示
          Text('— 下一章 —')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ bottom: 8 })
          Text(item.chapterTitle || '未知章节')
            .fontSize(16)
            .fontColor(colorMap.textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }
      }
      .padding({ left: 24, right: 24, top: 16, bottom: 16 })

      // 分隔线
      Divider()
        .width('80%')
        .height(1)
        .color(colorMap.divider)
        .margin({ top: 16 })
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Black)
  }

  /**
   * 构建条漫模式的加载中/边界提示
   */
  @Builder
  buildWebtoonLoadingIndicator(direction: 'prev' | 'next') {
    // [修复②] 双重上滑确认提示（仅对上一章方向）
    if (direction === 'prev' && this.prevChapterSwipeConfirmPending) {
      Column() {
        Text('↑ 再次上滑加载上一章 ↑')
          .fontSize(15)
          .fontColor(colorMap.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .height(80)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Color.Black)
    } else if ((direction === 'prev' && this.isFirstChapter) || (direction === 'next' && this.isLastChapter)) {
      // 检查是否是边界章节 - 显示边界提示而不是加载中
      Column() {
        Text(direction === 'prev' ? '— 已是第一章 —' : '— 已是最后一章 —')
          .fontSize(14)
          .fontColor(colorMap.textSecondary)
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      // 显示加载中
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(colorMap.accent)
        Text(direction === 'prev' ? '正在加载上一章...' : '正在加载下一章...')
          .fontSize(14)
          .fontColor(colorMap.textSecondary)
          .margin({ top: 12 })
      }
      .width('100%')
      .height(100)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  /**
   * 初始化条漫多章节数据
   * 将当前章节、前一章、后一章的页面合并成一个列表
   * [性能优化] 使用增量更新策略，避免全量替换导致组件闪烁
   */
  private initWebtoonMultiChapterData(): void {
    if (!this.isWebtoonMode()) {
      return;
    }

    logger.info(TAG, `🔄 [初始化多章节数据] prevChapter=${this.prevChapter?.title || '无'}(页数:${this.prevChapter?.pages?.length || 0}), currentChapter=${this.chapter?.title || '无'}(页数:${this.chapter?.pages?.length || 0}), nextChapter=${this.nextChapter?.title || '无'}(页数:${this.nextChapter?.pages?.length || 0})`);
    const oldScrollY = this.scrollPosition;

    const input: MangaWebtoonDataPlannerInput = new MangaWebtoonDataPlannerInput();
    input.currentChapter = this.chapter;
    input.prevChapter = this.prevChapter;
    input.nextChapter = this.nextChapter;
    input.existingItems = this.webtoonDataItems;
    input.existingBoundaries = this.chapterBoundaries;
    input.existingDataCount = this.webtoonDataSource.totalCount();

    const plan: MangaWebtoonDataPlan = this.mangaWebtoonDataPlanner.buildPlan(input);
    this.applyWebtoonDataPlan(plan, oldScrollY);
  }

  private applyWebtoonDataPlan(plan: MangaWebtoonDataPlan, oldScrollY: number): void {
    if (plan.kind === MangaWebtoonDataPlanKind.NONE) {
      if (plan.shouldRebuildPageRefs) {
        this.rebuildWebtoonPageRefIndex();
      }
      return;
    }

    if (plan.kind === MangaWebtoonDataPlanKind.APPEND_NEXT) {
      logger.info(TAG, `[增量更新] 添加下一章条漫数据: count=${plan.appendItems.length}`);
      for (let i = 0; i < plan.appendItems.length; i++) {
        this.webtoonDataItems.push(plan.appendItems[i]);
      }
      this.chapterBoundaries = plan.boundaries;
      this.webtoonDataSource.appendItems(plan.appendItems);
      if (plan.shouldRebuildPositionCache) {
        this.rebuildWebtoonPositionCache();
      }
      logger.info(TAG, `✅ [增量更新完成] 总项数=${this.webtoonDataItems.length}, 章节数=${this.chapterBoundaries.length}`);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_RECOVERED,
        this.currentChapterId.length > 0 ? this.currentChapterId : this.chapter.id,
        this.currentWebtoonPage,
        'webtoon_data_append_next',
        `appendItems=${plan.appendItems.length}, totalItems=${this.webtoonDataItems.length}, boundaries=${this.chapterBoundaries.length}`,
        MangaReadFlowSeverity.INFO
      );
      this.logMangaReaderCacheSnapshot('webtoon_data_append_next');
    } else if (plan.kind === MangaWebtoonDataPlanKind.FULL_REBUILD) {
      this.webtoonDataItems = plan.items;
      this.chapterBoundaries = plan.boundaries;
      this.currentChapterId = plan.currentChapterId;
      this.webtoonDataSource.setItems(plan.items);
      if (plan.shouldRebuildPositionCache) {
        this.rebuildWebtoonPositionCache();
      }
      this.logWebtoonFullRebuildResult(plan);
      this.adjustScrollAfterPrependedWebtoonChapter(plan, oldScrollY);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_RECOVERED,
        plan.currentChapterId,
        this.currentWebtoonPage,
        'webtoon_data_full_rebuild',
        `items=${plan.items.length}, boundaries=${plan.boundaries.length}, hadPrevChapterInData=${plan.hadPrevChapterInData}`,
        MangaReadFlowSeverity.INFO
      );
      this.logMangaReaderCacheSnapshot('webtoon_data_full_rebuild');
    }

    if (plan.shouldRebuildPageRefs) {
      this.rebuildWebtoonPageRefIndex();
    }
  }

  private logWebtoonFullRebuildResult(plan: MangaWebtoonDataPlan): void {
    logger.info(TAG, `✅ [全量重建完成] 总项数=${plan.items.length}, 章节数=${plan.boundaries.length}`);
    for (let i = 0; i < plan.boundaries.length; i++) {
      const boundary: ChapterBoundary = plan.boundaries[i];
      logger.info(TAG, `  章节${i}: id=${boundary.chapterId}, range=[${boundary.startIndex}, ${boundary.endIndex}], pages=${boundary.pageCount}`);
    }
  }

  private adjustScrollAfterPrependedWebtoonChapter(plan: MangaWebtoonDataPlan, oldScrollY: number): void {
    if (plan.hadPrevChapterInData || !this.prevChapter || !this.prevChapter.pages || this.prevChapter.pages.length <= 0) {
      return;
    }
    const currentBoundary: ChapterBoundary | undefined = this.findChapterBoundary(plan.boundaries, this.chapter.id);
    if (!currentBoundary || currentBoundary.startIndex <= 0) {
      return;
    }
    const prependedHeight: number = this.mangaWebtoonPositionManager.calculatePrependedHeight(
      plan.items,
      currentBoundary.startIndex,
      this.createWebtoonPositionContext()
    );
    const newScrollY: number = oldScrollY + prependedHeight;
    logger.info(TAG, `[修复A] 上一章内容新增，补偿滚动位置: ${oldScrollY} + ${prependedHeight} = ${newScrollY}`);

    setTimeout(() => {
      if (this.scroller) {
        this.scroller.scrollTo({
          xOffset: 0,
          yOffset: newScrollY
        });
        this.scrollPosition = newScrollY;
      }
    }, 50);
  }

  private findChapterBoundary(boundaries: ChapterBoundary[], chapterId: string): ChapterBoundary | undefined {
    for (let i = 0; i < boundaries.length; i++) {
      const boundary: ChapterBoundary = boundaries[i];
      if (boundary.chapterId === chapterId) {
        return boundary;
      }
    }
    return undefined;
  }

  /**
   * 检测条漫滚动是否接近章节边界
   * 当接近顶部或底部时，触发加载相邻章节
   */
  private checkWebtoonChapterBoundary(): void {
    const now: number = Date.now();
    const containerHeight: number = this.screenHeight > 0 ? this.screenHeight : 800;
    const input: MangaWebtoonBoundaryInput = this.createWebtoonBoundaryInput(containerHeight, now);
    const plan: MangaWebtoonBoundaryPlan = this.mangaWebtoonBoundaryPlanner.buildPlan(input);
    this.applyWebtoonBoundaryPlan(plan, input.currentScrollY, now);
  }

  private createWebtoonBoundaryInput(containerHeight: number, now: number): MangaWebtoonBoundaryInput {
    const input: MangaWebtoonBoundaryInput = new MangaWebtoonBoundaryInput();
    input.isWebtoonMode = this.isWebtoonMode();
    input.hasChapter = !!this.chapter;
    input.currentScrollY = this.scrollPosition;
    input.containerHeight = containerHeight;
    input.totalHeight = this.calculateTotalWebtoonHeight();
    input.isOnlineContent = this.isOnlineWebtoonContent();
    input.isFirstChapter = this.isFirstChapter;
    input.isLastChapter = this.isLastChapter;
    input.hasPrevChapter = !!this.prevChapter;
    input.hasNextChapter = !!this.nextChapter;
    input.prevChapterInData = this.isAdjacentChapterInWebtoonData(this.prevChapter);
    input.nextChapterInData = this.isAdjacentChapterInWebtoonData(this.nextChapter);
    input.prevChapterRequested = this.prevChapterRequested;
    input.nextChapterRequested = this.nextChapterRequested;
    input.isPrevChapterLoading = this.isPrevChapterLoading;
    input.isNextChapterLoading = this.isNextChapterLoading;
    input.prevConfirmPending = this.prevChapterSwipeConfirmPending;
    input.prevConfirmTime = this.prevChapterSwipeConfirmTime;
    input.lastPrevRequestAt = this.lastPrevAdjacentRequestAt;
    input.lastNextRequestAt = this.lastNextAdjacentRequestAt;
    input.adjacentRequestIntervalMs = this.getWebtoonAdjacentRequestIntervalMs();
    input.now = now;
    return input;
  }

  private isAdjacentChapterInWebtoonData(chapter: MangaChapter | undefined): boolean {
    if (!chapter) {
      return false;
    }
    return !!this.findChapterBoundary(this.chapterBoundaries, chapter.id);
  }

  private applyWebtoonBoundaryPlan(plan: MangaWebtoonBoundaryPlan, currentScrollY: number, now: number): void {
    if (!plan.shouldRun) {
      return;
    }

    const containerHeight: number = this.screenHeight > 0 ? this.screenHeight : 800;
    if (plan.shouldProtectBoundaryCache) {
      this.markWebtoonBoundaryCacheProtection(containerHeight);
    }
    if (plan.shouldPrewarmCurrentChapter) {
      this.prewarmChapterObjectEdges(this.chapter);
    }
    if (plan.shouldPrewarmPrevChapter) {
      this.prewarmChapterObjectEdges(this.prevChapter);
    }
    if (plan.shouldPrewarmNextChapter) {
      this.prewarmChapterObjectEdges(this.nextChapter);
    }

    if (plan.nearBottom) {
      this.applyWebtoonNextBoundaryPlan(plan, currentScrollY, now);
    }

    if (plan.nearTop) {
      this.applyWebtoonPrevBoundaryPlan(plan, currentScrollY, now);
    }
  }

  private applyWebtoonNextBoundaryPlan(plan: MangaWebtoonBoundaryPlan, currentScrollY: number, now: number): void {
    const chapterId: string = this.currentChapterId.length > 0 ? this.currentChapterId : this.chapter.id;
    if (plan.shouldResetNextLoading) {
      this.isNextChapterLoading = false;
      logger.debug(TAG, `条漫边界检测：已是最后一章，不加载下一章`);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_next_boundary_blocked',
        `scrollY=${currentScrollY.toFixed(0)}, maxScrollY=${plan.maxScrollY.toFixed(0)}, isLastChapter=${this.isLastChapter}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }

    logger.debug(TAG, `条漫边界检测(底部): scrollY=${currentScrollY.toFixed(0)}, maxScrollY=${plan.maxScrollY.toFixed(0)}, isLast=${this.isLastChapter}, requested=${this.nextChapterRequested}, loading=${this.isNextChapterLoading}, hasNext=${!!this.nextChapter}, nextInData=${plan.nextAlreadyInData}, canRequest=${plan.nextCanRequest}`);
    if (plan.nextBlockedByCooldown) {
      logger.debug(TAG, `条漫边界检测(底部): 命中请求冷却，跳过下一章请求`);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_next_cooldown_rejected',
        `scrollY=${currentScrollY.toFixed(0)}, now=${now}, lastNextRequestAt=${this.lastNextAdjacentRequestAt}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (!plan.shouldRequestNext) {
      if (plan.nearBottom && !plan.nextCanRequest) {
        this.recordScrollableReadFlow(
          MangaReadFlowEventType.FLOW_GUARD_REJECTED,
          chapterId,
          this.currentWebtoonPage,
          'webtoon_next_request_not_ready',
          `requested=${this.nextChapterRequested}, loading=${this.isNextChapterLoading}, hasNext=${!!this.nextChapter}, nextInData=${plan.nextAlreadyInData}`,
          MangaReadFlowSeverity.WARN
        );
      }
      return;
    }

    this.nextChapterRequested = true;
    this.isNextChapterLoading = true;
    if (plan.shouldUpdateNextRequestTime) {
      this.lastNextAdjacentRequestAt = now;
    }
    logger.info(TAG, `条漫模式：接近底部，请求加载下一章`);
    this.recordScrollableReadFlow(
      MangaReadFlowEventType.FLOW_RECOVERED,
      chapterId,
      this.currentWebtoonPage,
      'webtoon_request_next_chapter',
      `scrollY=${currentScrollY.toFixed(0)}, maxScrollY=${plan.maxScrollY.toFixed(0)}, nextInData=${plan.nextAlreadyInData}`,
      MangaReadFlowSeverity.INFO
    );
    this.requestAdjacentChapter('next');
  }

  private applyWebtoonPrevBoundaryPlan(plan: MangaWebtoonBoundaryPlan, currentScrollY: number, now: number): void {
    const chapterId: string = this.currentChapterId.length > 0 ? this.currentChapterId : this.chapter.id;
    if (plan.shouldResetPrevLoading) {
      this.isPrevChapterLoading = false;
      logger.debug(TAG, `条漫边界检测：已是第一章，不加载上一章`);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_prev_boundary_blocked',
        `scrollY=${currentScrollY.toFixed(0)}, isFirstChapter=${this.isFirstChapter}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }

    logger.debug(TAG, `条漫边界检测(顶部): scrollY=${currentScrollY.toFixed(0)}, isFirst=${this.isFirstChapter}, requested=${this.prevChapterRequested}, loading=${this.isPrevChapterLoading}, hasPrev=${!!this.prevChapter}, prevInData=${plan.prevAlreadyInData}, canRequest=${plan.prevCanRequest}`);
    if (plan.shouldStartPrevConfirm) {
      this.startPrevChapterSwipeConfirm(now);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_prev_confirm_started',
        `scrollY=${currentScrollY.toFixed(0)}, hasPrev=${!!this.prevChapter}, prevInData=${plan.prevAlreadyInData}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.shouldKeepPrevConfirmWaiting) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_prev_confirm_waiting',
        `scrollY=${currentScrollY.toFixed(0)}, confirmSince=${this.prevChapterSwipeConfirmTime}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (plan.shouldClearPrevConfirm) {
      this.clearPrevChapterSwipeConfirm();
    }
    if (plan.prevBlockedByCooldown) {
      logger.debug(TAG, `条漫边界检测(顶部): 命中请求冷却，跳过上一章请求`);
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        chapterId,
        this.currentWebtoonPage,
        'webtoon_prev_cooldown_rejected',
        `scrollY=${currentScrollY.toFixed(0)}, now=${now}, lastPrevRequestAt=${this.lastPrevAdjacentRequestAt}`,
        MangaReadFlowSeverity.WARN
      );
      return;
    }
    if (!plan.shouldRequestPrev) {
      if (plan.nearTop && !plan.prevCanRequest) {
        this.recordScrollableReadFlow(
          MangaReadFlowEventType.FLOW_GUARD_REJECTED,
          chapterId,
          this.currentWebtoonPage,
          'webtoon_prev_request_not_ready',
          `requested=${this.prevChapterRequested}, loading=${this.isPrevChapterLoading}, hasPrev=${!!this.prevChapter}, prevInData=${plan.prevAlreadyInData}`,
          MangaReadFlowSeverity.WARN
        );
      }
      return;
    }

    this.prevChapterRequested = true;
    this.isPrevChapterLoading = true;
    if (plan.shouldUpdatePrevRequestTime) {
      this.lastPrevAdjacentRequestAt = now;
    }
    logger.info(TAG, `条漫模式：接近顶部，请求加载上一章`);
    this.recordScrollableReadFlow(
      MangaReadFlowEventType.FLOW_RECOVERED,
      chapterId,
      this.currentWebtoonPage,
      'webtoon_request_prev_chapter',
      `scrollY=${currentScrollY.toFixed(0)}, prevInData=${plan.prevAlreadyInData}`,
      MangaReadFlowSeverity.INFO
    );
    this.requestAdjacentChapter('prev');
  }

  private startPrevChapterSwipeConfirm(now: number): void {
    this.prevChapterSwipeConfirmPending = true;
    this.prevChapterSwipeConfirmTime = now;
    if (this.prevChapterSwipeConfirmTimer !== -1) {
      clearTimeout(this.prevChapterSwipeConfirmTimer);
    }
    this.prevChapterSwipeConfirmTimer = setTimeout(() => {
      this.prevChapterSwipeConfirmPending = false;
      this.prevChapterSwipeConfirmTimer = -1;
    }, 3000);
    logger.info(TAG, `条漫模式：首次上滑到顶，等待二次确认`);
  }

  private clearPrevChapterSwipeConfirm(): void {
    this.prevChapterSwipeConfirmPending = false;
    if (this.prevChapterSwipeConfirmTimer !== -1) {
      clearTimeout(this.prevChapterSwipeConfirmTimer);
      this.prevChapterSwipeConfirmTimer = -1;
    }
  }

  private requestAdjacentChapter(direction: 'prev' | 'next'): void {
    if (this.onRequestAdjacentChapter) {
      this.onRequestAdjacentChapter(direction);
    } else if (this.callbacks.onChapterChange) {
      this.callbacks.onChapterChange(direction);
    }
  }

  /**
   * 计算条漫总高度
   * [修复] 使用webtoonDataSource计算，包含所有已加载的章节
   */
  private calculateTotalWebtoonHeight(): number {
    const fallbackPages: MangaPage[] = (this.chapter && this.chapter.pages) ? this.chapter.pages : [];
    return this.mangaWebtoonPositionManager.calculateTotalWebtoonHeight(
      this.webtoonDataItems,
      fallbackPages,
      this.createWebtoonPositionContext()
    );
  }

  /**
   * 清理远离可见区域的章节图片资源
   * [性能优化] 增加清理阈值，添加滚动方向感知
   * 只在滚动停止时执行，避免滚动时频繁操作
   */
  private cleanupDistantChapterResources(): void {
    const input: MangaWebtoonCleanupInput = this.createWebtoonCleanupInput();
    const plan: MangaWebtoonCleanupPlan = this.mangaWebtoonCleanupPlanner.buildPlan(input);
    this.applyWebtoonCleanupPlan(plan);
  }

  private createWebtoonCleanupInput(): MangaWebtoonCleanupInput {
    const input: MangaWebtoonCleanupInput = new MangaWebtoonCleanupInput();
    input.isWebtoonMode = this.isWebtoonMode();
    input.isScrolling = this.isScrolling;
    input.isBoundaryProtected = this.isWebtoonBoundaryCleanupProtected();
    input.primaryChapterId = this.chapter ? this.chapter.id : '';
    input.currentChapterId = this.currentChapterId;
    input.scrollPosition = this.scrollPosition;
    input.containerHeight = this.screenHeight > 0 ? this.screenHeight : 800;
    input.scrollDirection = this.lastScrollDirection;
    input.chapterRanges = this.createWebtoonChapterCleanupRanges();
    input.chapterBoundaries = this.chapterBoundaries;
    input.webtoonDataItems = this.webtoonDataItems;
    input.fallbackPages = (this.chapter && this.chapter.pages) ? this.chapter.pages : [];
    input.visiblePageIndices = this.visiblePageIndices;
    input.currentWebtoonPage = this.currentWebtoonPage;
    return input;
  }

  private createWebtoonChapterCleanupRanges(): MangaWebtoonChapterCleanupRange[] {
    const ranges: MangaWebtoonChapterCleanupRange[] = [];
    for (let i = 0; i < this.chapterBoundaries.length; i++) {
      const boundary: ChapterBoundary = this.chapterBoundaries[i];
      const range: MangaWebtoonChapterCleanupRange = new MangaWebtoonChapterCleanupRange();
      range.chapterId = boundary.chapterId;
      range.startY = this.calculateWebtoonItemScrollPosition(boundary.startIndex);
      range.endY = this.calculateWebtoonItemScrollPosition(boundary.endIndex + 1);
      ranges.push(range);
    }
    return ranges;
  }

  private applyWebtoonCleanupPlan(plan: MangaWebtoonCleanupPlan): void {
    for (let i = 0; i < plan.chapterIdsToCleanup.length; i++) {
      this.cleanupChapterPixelMaps(plan.chapterIdsToCleanup[i]);
    }
    this.applyLocalCacheCleanupPlan(plan.localCachePlan);
  }

  private applyLocalCacheCleanupPlan(plan: MangaWebtoonLocalCacheCleanupPlan): void {
    if (!plan.shouldCleanup) {
      return;
    }
    this.localImageCache.cleanupDistant(plan.visiblePageIds, plan.allPageIds, 15);
    this.logMangaReaderCacheSnapshot('local_image_cache_cleanup');
  }

  /**
   * 清理指定章节的PixelMap
   */
  private cleanupChapterPixelMaps(chapterId: string): void {
    const keysToDelete: string[] = [];

    // 找出属于该章节的页面
    for (const item of this.webtoonDataItems) {
      if (item.type === 'page' && item.chapterId === chapterId && item.page) {
        const pageId = item.page.id;
        if (this.pagePixelMaps.has(pageId)) {
          keysToDelete.push(pageId);
        }
      }
    }

    // 释放PixelMap
    for (const pageId of keysToDelete) {
      this.dropPagePixelMapReference(pageId, true);
    }

    if (keysToDelete.length > 0) {
      logger.info(TAG, `清理章节 ${chapterId} 的 ${keysToDelete.length} 个PixelMap`);
      this.logMangaReaderCacheSnapshot('webtoon_chapter_pixel_maps_cleaned');
    }
  }

  /**
   * 计算条漫数据项的滚动位置
   * [性能优化] 使用缓存避免重复计算
   */
  private calculateWebtoonItemScrollPosition(itemIndex: number): number {
    return this.mangaWebtoonPositionManager.calculateItemScrollPosition(
      itemIndex,
      this.webtoonDataItems,
      this.createWebtoonPositionContext()
    );
  }

  private getWebtoonItemEstimatedHeight(item: WebtoonDataItem): number {
    return this.mangaWebtoonPositionManager.getWebtoonItemEstimatedHeight(
      item,
      this.createWebtoonPositionContext()
    );
  }

  private ensureWebtoonPositionCache(): void {
    this.mangaWebtoonPositionManager.ensurePositionCache(
      this.webtoonDataItems,
      this.createWebtoonPositionContext()
    );
  }

  private findFirstWebtoonVisibleCandidate(rangeStart: number): number {
    return this.mangaWebtoonPositionManager.findFirstVisibleCandidate(
      rangeStart,
      this.webtoonDataItems,
      this.createWebtoonPositionContext()
    );
  }
  
  /**
   * [性能优化] 重建条漫项位置缓存
   */
  private rebuildWebtoonPositionCache(): void {
    this.mangaWebtoonPositionManager.rebuildPositionCache(
      this.webtoonDataItems,
      this.createWebtoonPositionContext()
    );
  }
  
  /**
   * [性能优化] 失效条漫位置缓存
   */
  private invalidateWebtoonPositionCache(): void {
    this.mangaWebtoonPositionManager.invalidatePositionCache();
  }

  private isOnlineWebtoonContent(): boolean {
    return this.contentType === 'OnlineUndownloaded' || this.contentType === 'OnlineDownloaded';
  }

  private getWebtoonHeavyUpdateThrottleMs(): number {
    return this.isOnlineWebtoonContent()
      ? this.WEBTOON_HEAVY_UPDATE_THROTTLE_ONLINE_MS
      : this.WEBTOON_HEAVY_UPDATE_THROTTLE_LOCAL_MS;
  }

  private getWebtoonSwitchStableMs(): number {
    return this.isOnlineWebtoonContent()
      ? this.WEBTOON_SWITCH_STABLE_MS_ONLINE
      : this.WEBTOON_SWITCH_STABLE_MS_LOCAL;
  }

  private getWebtoonSwitchCooldownMs(): number {
    return this.isOnlineWebtoonContent()
      ? this.WEBTOON_SWITCH_COOLDOWN_MS_ONLINE
      : this.WEBTOON_SWITCH_COOLDOWN_MS_LOCAL;
  }

  private getWebtoonAdjacentRequestIntervalMs(): number {
    return this.isOnlineWebtoonContent() ? 1200 : 450;
  }

  private getWebtoonSwitchHysteresisPx(containerHeight: number): number {
    const raw = containerHeight * this.WEBTOON_SWITCH_HYSTERESIS_RATIO;
    const clamped = Math.max(this.WEBTOON_SWITCH_HYSTERESIS_MIN_PX, raw);
    return Math.min(this.WEBTOON_SWITCH_HYSTERESIS_MAX_PX, clamped);
  }

  private clearPendingWebtoonSwitchCandidate(): void {
    this.pendingWebtoonChapterCandidateId = '';
    this.pendingWebtoonChapterCandidateSince = 0;
    this.pendingWebtoonChapterCandidatePageIndex = 0;
  }

  private markWebtoonBoundaryCacheProtection(containerHeight: number): void {
    const now = Date.now();
    const baseMs = this.isOnlineWebtoonContent()
      ? Math.max(1400, Math.floor(containerHeight * 2))
      : 700;
    const targetUntil = now + baseMs;
    if (targetUntil > this.webtoonBoundaryCacheProtectUntil) {
      this.webtoonBoundaryCacheProtectUntil = targetUntil;
    }
  }

  private isWebtoonBoundaryCleanupProtected(): boolean {
    return Date.now() < this.webtoonBoundaryCacheProtectUntil;
  }

  private prewarmPageListEdges(chapterId: string, pages: MangaPage[]): void {
    const input: MangaWebtoonPrewarmInput = new MangaWebtoonPrewarmInput();
    input.chapterId = chapterId;
    input.pages = pages;
    input.isOnlineContent = this.isOnlineWebtoonContent();
    input.now = Date.now();
    input.lastPrewarmAt = this.lastBoundaryPrewarmAt.get(chapterId) || 0;

    const plan: MangaWebtoonPrewarmPlan = this.mangaWebtoonPrewarmPlanner.buildPlan(input);
    this.applyWebtoonPrewarmPlan(plan, input.now);
  }

  private applyWebtoonPrewarmPlan(plan: MangaWebtoonPrewarmPlan, now: number): void {
    if (!plan.shouldPrewarm) {
      return;
    }
    if (plan.shouldUpdatePrewarmTime) {
      this.lastBoundaryPrewarmAt.set(plan.chapterId, now);
    }
    this.recordScrollableReadFlow(
      MangaReadFlowEventType.FLOW_RECOVERED,
      plan.chapterId,
      this.currentWebtoonPage,
      'webtoon_boundary_prewarm',
      `pages=${plan.pages.length}, now=${now}`,
      MangaReadFlowSeverity.INFO
    );
    for (let i = 0; i < plan.pages.length; i++) {
      const page: MangaPage = plan.pages[i];
      if (page.sourceType === ImageSourceType.LOCAL) {
        const localIndex = page.index !== undefined ? page.index : this.getPageIndexById(page.id);
        this.triggerLocalImageLoad(page, plan.chapterId, localIndex >= 0 ? localIndex : 0);
      } else if (page.sourceType === ImageSourceType.NETWORK) {
        this.queueWebtoonNetworkPageLoad(page, -1);
      }
    }
  }

  private prewarmBoundaryEdgePages(boundary: ChapterBoundary | undefined): void {
    if (!boundary) {
      return;
    }
    const pages: MangaPage[] = [];
    for (let i = boundary.startIndex; i <= boundary.endIndex && i < this.webtoonDataItems.length; i++) {
      const item = this.webtoonDataItems[i];
      if (item && item.type === 'page' && item.page) {
        pages.push(item.page);
      }
    }
    this.prewarmPageListEdges(boundary.chapterId, pages);
  }

  private prewarmChapterObjectEdges(chapter: MangaChapter | undefined): void {
    if (!chapter || !chapter.pages || chapter.pages.length === 0) {
      return;
    }
    this.prewarmPageListEdges(chapter.id, chapter.pages);
  }

  private prewarmBoundaryContext(boundary: ChapterBoundary, boundaryIndex: number, nearStart: boolean, nearEnd: boolean): void {
    this.prewarmBoundaryEdgePages(boundary);
    if (nearStart && boundaryIndex > 0) {
      this.prewarmBoundaryEdgePages(this.chapterBoundaries[boundaryIndex - 1]);
    }
    if (nearEnd && boundaryIndex < this.chapterBoundaries.length - 1) {
      this.prewarmBoundaryEdgePages(this.chapterBoundaries[boundaryIndex + 1]);
    }
  }

  private scheduleWebtoonChapterSwitchNotify(chapterId: string, chapterTitle: string, pageIndex: number): void {
    if (!this.callbacks.onWebtoonChapterSwitch) {
      return;
    }
    if (this.lastNotifiedWebtoonChapterId === chapterId && this.lastNotifiedWebtoonPageIndex === pageIndex) {
      return;
    }
    if (this.pendingWebtoonSwitchNotifyTimer !== -1) {
      clearTimeout(this.pendingWebtoonSwitchNotifyTimer);
      this.pendingWebtoonSwitchNotifyTimer = -1;
    }
    const notifyDelay = this.isOnlineWebtoonContent() ? 180 : 90;
    this.pendingWebtoonSwitchNotifyTimer = setTimeout(() => {
      this.pendingWebtoonSwitchNotifyTimer = -1;
      // 定时器触发时如果章节已变化，丢弃过期通知
      if (this.currentChapterId !== chapterId) {
        return;
      }
      if (this.lastNotifiedWebtoonChapterId === chapterId && this.lastNotifiedWebtoonPageIndex === pageIndex) {
        return;
      }
      this.lastNotifiedWebtoonChapterId = chapterId;
      this.lastNotifiedWebtoonPageIndex = pageIndex;
      this.callbacks.onWebtoonChapterSwitch?.(chapterId, chapterTitle, pageIndex);
    }, notifyDelay);
  }

  /**
   * 更新当前显示的章节ID（根据滚动位置）
   * [修复] 当滚动到其他章节时，通知父组件更新当前章节和页码
   */
  private updateCurrentChapterFromScroll(): void {
    const input: MangaWebtoonChapterSwitchInput = this.createWebtoonChapterSwitchInput();
    const plan: MangaWebtoonChapterSwitchPlan = this.mangaWebtoonChapterSwitchPlanner.buildPlan(input);
    this.applyWebtoonChapterSwitchPlan(plan, input.now, input.containerHeight);
  }

  private createWebtoonChapterSwitchInput(): MangaWebtoonChapterSwitchInput {
    const input: MangaWebtoonChapterSwitchInput = new MangaWebtoonChapterSwitchInput();
    input.isWebtoonMode = this.isWebtoonMode();
    input.ranges = this.createWebtoonChapterSwitchRanges();
    input.currentScrollY = this.scrollPosition;
    input.containerHeight = this.screenHeight > 0 ? this.screenHeight : 800;
    input.currentChapterId = this.currentChapterId;
    input.pendingCandidateId = this.pendingWebtoonChapterCandidateId;
    input.pendingCandidateSince = this.pendingWebtoonChapterCandidateSince;
    input.pendingCandidatePageIndex = this.pendingWebtoonChapterCandidatePageIndex;
    input.lastCommittedSwitchAt = this.lastCommittedWebtoonChapterSwitchAt;
    input.hysteresisPx = this.getWebtoonSwitchHysteresisPx(input.containerHeight);
    input.stableMs = this.getWebtoonSwitchStableMs();
    input.cooldownMs = this.getWebtoonSwitchCooldownMs();
    input.now = Date.now();
    return input;
  }

  private createWebtoonChapterSwitchRanges(): MangaWebtoonChapterSwitchBoundaryRange[] {
    const ranges: MangaWebtoonChapterSwitchBoundaryRange[] = [];
    if (!this.isWebtoonMode() || this.chapterBoundaries.length === 0) {
      return ranges;
    }
    const containerHeight: number = this.screenHeight > 0 ? this.screenHeight : 800;
    for (let i = 0; i < this.chapterBoundaries.length; i++) {
      const boundary: ChapterBoundary = this.chapterBoundaries[i];
      const range: MangaWebtoonChapterSwitchBoundaryRange = new MangaWebtoonChapterSwitchBoundaryRange();
      range.boundary = boundary;
      range.boundaryIndex = i;
      range.startY = this.calculateWebtoonItemScrollPosition(boundary.startIndex);
      range.endY = this.calculateWebtoonItemScrollPosition(boundary.endIndex + 1);
      range.pageIndexInChapter = this.calculateCurrentPageInChapter(boundary, this.scrollPosition, containerHeight);
      ranges.push(range);
    }
    return ranges;
  }

  private applyWebtoonChapterSwitchPlan(
    plan: MangaWebtoonChapterSwitchPlan,
    now: number,
    containerHeight: number
  ): void {
    if (!plan.shouldRun || !plan.matchedBoundary) {
      return;
    }

    if (plan.shouldProtectBoundaryCache) {
      this.markWebtoonBoundaryCacheProtection(containerHeight);
    }
    if (plan.shouldPrewarmBoundaryContext) {
      this.prewarmBoundaryContext(plan.matchedBoundary, plan.matchedBoundaryIndex, plan.nearStart, plan.nearEnd);
    }
    if (plan.shouldClearPendingCandidate) {
      this.clearPendingWebtoonSwitchCandidate();
    }
    if (plan.shouldSetPendingCandidate) {
      this.pendingWebtoonChapterCandidateId = plan.pendingCandidateId;
      this.pendingWebtoonChapterCandidateSince = plan.pendingCandidateSince;
      this.pendingWebtoonChapterCandidatePageIndex = plan.pendingCandidatePageIndex;
    }
    if (plan.blockedByHysteresis) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        plan.pendingCandidateId,
        plan.pendingCandidatePageIndex,
        'webtoon_chapter_switch_hysteresis_rejected',
        `candidate=${plan.pendingCandidateId}, startY=${plan.matchedStartY.toFixed(0)}, endY=${plan.matchedEndY.toFixed(0)}`,
        MangaReadFlowSeverity.WARN
      );
    }
    if (plan.waitingForStability) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        plan.pendingCandidateId,
        plan.pendingCandidatePageIndex,
        'webtoon_chapter_switch_waiting_stability',
        `candidate=${plan.pendingCandidateId}, since=${plan.pendingCandidateSince}, now=${now}`,
        MangaReadFlowSeverity.WARN
      );
    }
    if (plan.blockedByCooldown) {
      this.recordScrollableReadFlow(
        MangaReadFlowEventType.FLOW_GUARD_REJECTED,
        plan.pendingCandidateId,
        plan.pendingCandidatePageIndex,
        'webtoon_chapter_switch_cooldown_rejected',
        `candidate=${plan.pendingCandidateId}, now=${now}, lastCommitted=${this.lastCommittedWebtoonChapterSwitchAt}`,
        MangaReadFlowSeverity.WARN
      );
    }
    if (!plan.shouldCommitSwitch) {
      return;
    }

    const oldChapterId: string = this.currentChapterId;
    this.currentChapterId = plan.committedChapterId;
    this.lastCommittedWebtoonChapterSwitchAt = now;
    logger.info(TAG, `条漫章节切换: ${plan.oldChapterId} -> ${plan.committedChapterId}`);

    const chapterTitle = this.getChapterTitleById(plan.committedChapterId);
    logger.info(TAG, `条漫章节切换通知: chapterId=${plan.committedChapterId}, title=${chapterTitle}, pageIndex=${plan.committedPageIndex}`);
    this.recordScrollableReadFlow(
      MangaReadFlowEventType.PAGE_CHANGED,
      plan.committedChapterId,
      plan.committedPageIndex,
      'webtoon_scroll_chapter_switch_committed',
      `oldChapterId=${oldChapterId}, newChapterId=${plan.committedChapterId}, pageIndex=${plan.committedPageIndex}`,
      MangaReadFlowSeverity.INFO
    );
    this.scheduleWebtoonChapterSwitchNotify(plan.committedChapterId, chapterTitle, plan.committedPageIndex);
  }

  /**
   * 计算当前在指定章节中的页码
   */
  private calculateCurrentPageInChapter(boundary: ChapterBoundary, scrollY: number, containerHeight: number): number {
    return this.mangaWebtoonPositionManager.calculateCurrentPageInChapter(
      boundary,
      this.webtoonDataItems,
      scrollY,
      containerHeight,
      this.createWebtoonPositionContext()
    );
  }

  /**
   * 根据章节ID获取章节标题
   */
  private getChapterTitleById(chapterId: string): string {
    if (this.chapter.id === chapterId) {
      return this.chapter.title;
    }
    if (this.prevChapter && this.prevChapter.id === chapterId) {
      return this.prevChapter.title;
    }
    if (this.nextChapter && this.nextChapter.id === chapterId) {
      return this.nextChapter.title;
    }
    return '';
  }

  /**
   * 获取当前章节的页数
   */
  private getCurrentChapterPageCount(): number {
    if (!this.currentChapterId) {
      return this.chapter.pages.length;
    }
    
    if (this.currentChapterId === this.chapter.id) {
      return this.chapter.pages.length;
    }
    if (this.prevChapter && this.currentChapterId === this.prevChapter.id) {
      return this.prevChapter.pages.length;
    }
    if (this.nextChapter && this.currentChapterId === this.nextChapter.id) {
      return this.nextChapter.pages.length;
    }
    
    // 回退到主章节
    return this.chapter.pages.length;
  }

  private getDoublePageIndicatorFirstLabel(): string {
    if (this.isDoublePageVerticalPortraitMode()) {
      const topPageIndex: number = this.getTopPageIndex();
      return `上${topPageIndex >= 0 ? topPageIndex + 1 : '-'}`;
    }
    if (this.isDoublePageSingleDisplayActive()) {
      return `${this.leftPageIndex >= 0 ? this.leftPageIndex + 1 : '-'}`;
    }
    return `${this.leftPageIndex >= 0 ? this.leftPageIndex + 1 : '-'}`;
  }

  private getDoublePageIndicatorSecondLabel(): string {
    if (this.isDoublePageVerticalPortraitMode()) {
      const bottomPageIndex: number = this.getBottomPageIndex();
      return `下${bottomPageIndex >= 0 ? bottomPageIndex + 1 : '-'}`;
    }
    if (this.isDoublePageSingleDisplayActive()) {
      return '';
    }
    return `${this.rightPageIndex >= 0 ? this.rightPageIndex + 1 : '-'}`;
  }

  private getDoublePageIndicatorLayoutStatus(): string {
    if (this.isDoublePageVerticalPortraitMode()) {
      return `上下双页·${this.getDoublePageVerticalDirection() === DoublePageVerticalDirection.BOTTOM_TO_TOP ? '下→上' : '上→下'}`;
    }

    switch (this.currentDoublePageDisplayReason) {
      case DoublePageSmartDisplayReason.LANDSCAPE_SPREAD:
        return '单显·横向跨页';
      case DoublePageSmartDisplayReason.ADJACENT_LANDSCAPE:
        return '单显·相邻大图保护';
      case DoublePageSmartDisplayReason.LARGE_SINGLE_PAGE:
        return '单显·大图';
      case DoublePageSmartDisplayReason.ASPECT_MISMATCH:
        return '单显·比例校正';
      case DoublePageSmartDisplayReason.TAIL_PAGE:
        return '单显·尾页';
      default:
        return '双页·智能配对';
    }
  }

  /**
   * 构建双页模式指示器
   */
  @Builder
  buildDoublePageIndicator() {
    Column() {
      Row() {
        Text(this.getDoublePageIndicatorFirstLabel())
          .fontSize(12)
          .fontColor(colorMap.textOnAccent)
          .fontWeight(FontWeight.Bold)

        if (!this.isDoublePageSingleDisplayActive()) {
          Text(' | ')
            .fontSize(10)
            .fontColor(colorMap.textSecondary)

          Text(this.getDoublePageIndicatorSecondLabel())
            .fontSize(12)
            .fontColor(colorMap.textOnAccent)
            .fontWeight(FontWeight.Bold)
        }

        Text(' / ')
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
          .margin({ left: 4 })

        Text(`${this.chapter.pages.length}`)
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
      }

      Text(this.getDoublePageIndicatorLayoutStatus())
        .fontSize(9)
        .fontColor(colorMap.accent)
        .margin({ top: 2 })
    }
    .backgroundColor(colorMap.backgroundOverlay)
    .borderRadius(12)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .position({ x: '50%', y: '90%' })
    .translate({ x: '-50%', y: '-50%' })
    .opacity(0.8)
  }

  /**
   * 构建条漫进度指示器
   * [修复] 支持多章节模式，显示当前章节的页数
   */
  @Builder
  buildWebtoonProgressIndicator() {
    if (this.showWebtoonProgress && (this.isWebtoonMode() || this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL)) {
      Column() {
        Row() {
          Text(this.getActiveProgressChapterTitle())
            .layoutWeight(1)
            .fontSize(10)
            .fontColor(colorMap.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)

          Text(this.getWebtoonProgressPercentText())
            .fontSize(10)
            .fontColor(colorMap.textSecondary)
        }
        .margin({ bottom: 4 })
        .width('100%')

        Text(this.getWebtoonPageProgressText())
          .width('100%')
          .textAlign(this.shouldReverseWebtoonProgressLayout() ? TextAlign.End : TextAlign.Start)
          .fontSize(12)
          .fontColor(colorMap.textSecondary)
          .margin({ bottom: 4 })

        Progress({
          value: this.webtoonScrollProgress * 100,
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(3)
          .color(colorMap.primary)
          .backgroundColor(colorMap.backgroundSecondary)
          .scale({ x: this.shouldReverseWebtoonProgressLayout() ? -1 : 1, y: 1 })
      }
      .width(168)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(colorMap.backgroundOverlay)
      .borderRadius(16)
      .position({ x: '50%', y: '10%' })
      .translate({ x: '-50%', y: '0%' })
      .opacity(this.isScrolling ? 1.0 : 0.7)
      .animation({
        duration: 200,
        curve: curves.initCurve(Curve.EaseOut)
      })
    }
  }

  private shouldAnchorWebtoonQuickNavigationToLeft(): boolean {
    if (!this.holdingAwarenessEnabled || !this.holdingAwarenessMangaWebtoonQuickNavigationEnabled) {
      return false;
    }
    if (!this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.MANGA_WEBTOON_QUICK_NAVIGATION)) {
      return false;
    }
    return this.holdingAwarenessPreferredAnchor === HoldingUiAnchor.LEFT;
  }

  private getWebtoonQuickNavigationX(): string {
    return this.shouldAnchorWebtoonQuickNavigationToLeft() ? '10%' : '90%';
  }

  /**
   * 构建条漫快速导航
   */
  @Builder
  buildWebtoonQuickNavigation() {
    if ((this.isWebtoonMode() || this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) && this.chapter.pages.length > 10) {
      Column() {
        // 快速跳转按钮
        Button('跳转')
          .fontSize(12)
          .fontColor(colorMap.accent)
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.showQuickNavigationDialog();
          })

        // 快速滚动条（垂直）
        Column() {
          Slider({
            value: this.webtoonScrollProgress * 100,
            min: 0,
            max: 100,
            step: 1,
            style: SliderStyle.InSet,
            direction: Axis.Vertical
          })
            .width(20)
            .height(200)
            .trackColor(colorMap.backgroundSecondary)
            .selectedColor(colorMap.primary)
            .blockColor(colorMap.accent)
            .onChange((value: number) => {
              const targetProgress = value / 100;
              if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
                const maxScroll = this.getContinuousHorizontalMaxScroll();
                const effectiveProgress = this.isContinuousHorizontalRTL() ? 1 - targetProgress : targetProgress;
                const targetPosition: number = effectiveProgress * maxScroll;
                this.smoothScrollToHorizontal(targetPosition);
              } else {
                const totalPages: number = this.chapter.pages.length;
                const spacing: number = this.readingSettings.pageSpacing || 16;
                // 垂直模式：计算总高度并垂直滚动
                let totalHeight: number = 0;
                for (let i = 0; i < totalPages; i++) {
                  const pg: MangaPage = this.chapter.pages[i];
                  totalHeight += this.getEstimatedImageHeight(pg);
                  if (i < totalPages - 1) { totalHeight += spacing; }
                }
                const targetPosition: number = targetProgress * totalHeight;
                this.smoothScrollTo(targetPosition);
              }
            })
        }
        .margin({ top: 8 })
      }
      .position({ x: this.getWebtoonQuickNavigationX(), y: '50%' })
      .translate({ x: '-50%', y: '-50%' })
      .opacity(this.isScrolling ? 1.0 : 0.3)
      .animation({
        duration: 200,
        curve: curves.initCurve(Curve.EaseOut)
      })
    }
  }

  /**
   * 显示快速导航对话框
   */
  private showQuickNavigationDialog(): void {
    // 这里可以实现一个快速跳转对话框
    // 暂时使用简单的页面跳转
    const targetPage = Math.floor(this.chapter.pages.length / 2);
    this.jumpToPage(targetPage);
  }

  /**
   * 快速跳转到页面
   */
  public jumpToPage(pageIndex: number): void {
    if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      logger.warn(TAG, `页面索引超出范围: ${pageIndex}`);
      return;
    }

    if (this.isContinuousScrollMode() || this.isWebtoonMode()) {
      if (this.smoothScrollToPage(pageIndex, 1.0)) {
        return;
      }
    }

    // 计算目标位置（简化计算，实际应该根据图片高度精确计算）
    const estimatedImageHeight: number = this.getEstimatedImageHeight(this.chapter.pages[pageIndex]);
    const spacing = this.readingSettings.pageSpacing || 16;
    const targetPosition = pageIndex * (estimatedImageHeight + spacing);

    this.smoothScrollTo(targetPosition);

    // 更新当前页面索引
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(pageIndex);
    }
  }

  /**
   * 获取MangaViewer组件实例（供父组件调用）
   * 用于实现自动翻页等功能
   */
  public getMangaViewerInstance(): MangaViewer {
    return this;
  }

  public getCurrentViewPageIndex(): number {
    return this.viewCurrentPageIndex;
  }

  public syncVerticalDoublePageToPageIndex(pageIndex: number, reason: string): void {
    if (!this.isDoublePageVerticalPortraitMode()) {
      return;
    }
    if (!this.chapter || !this.chapter.pages || this.chapter.pages.length === 0) {
      return;
    }
    const maxIndex: number = this.chapter.pages.length - 1;
    const safeIndex: number = Math.max(0, Math.min(pageIndex, maxIndex));
    const pairStart: number = safeIndex - (safeIndex % 2);
    this.viewCurrentPageIndex = pairStart;
    this.forceRefreshVerticalDoublePageCurrentPair(reason);
  }

  build() {
    Stack() {
      // 根据阅读模式选择不同的显示方式
      if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
        this.buildSinglePageView()
      } else if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
        this.buildDoublePageView()
      } else if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL ||
        this.readingSettings.readingMode === ReadingMode.WEBTOON) {
        this.buildWebtoonView()
      } else if (this.readingSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP) {
        this.buildWebtoonWithGapView()
      } else if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
        this.buildContinuousView()
      }

      // 页面指示器（仅在单页模式下显示）
      if (this.readingSettings.showPageInfo && this.isSinglePageMode()) {
        Text(`${this.viewCurrentPageIndex + 1} / ${this.chapter.pages.length}`)
          .fontSize(12)
          .fontColor(colorMap.textOnAccent)
          .backgroundColor(colorMap.backgroundOverlay)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(12)
          .position({ x: '50%', y: '90%' })
          .translate({ x: '-50%', y: '-50%' })
      }

      // 条漫覆盖层与工具栏显示状态联动
      if (this.toolbarsVisible) {
        // 条漫进度指示器
        this.buildWebtoonProgressIndicator()

        // 条漫快速导航
        this.buildWebtoonQuickNavigation()
      }
    }
    .key(this.getViewerContainerKey())
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w: number = Number(newArea.width);
      const h: number = Number(newArea.height);
      const oldW: number = this.screenWidth;
      const oldH: number = this.screenHeight;
      if (w > 0) { this.screenWidth = w; }
      if (h > 0) { this.screenHeight = h; }
      if ((w > 0 && w !== oldW) || (h > 0 && h !== oldH)) {
        this.invalidateWebtoonPositionCache();
      }

      // 检测屏幕方向变化（横竖屏切换）
      const wasLandscape: boolean = oldW > oldH;
      const isLandscape: boolean = w > h;
      if (wasLandscape !== isLandscape && this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
        // 屏幕方向变化且是双页模式，强制刷新UI
        logger.info(TAG, `屏幕方向变化: ${wasLandscape ? '横屏' : '竖屏'} -> ${isLandscape ? '横屏' : '竖屏'}`);
        this.renderEpoch = this.renderEpoch + 1;
      }
    })
  }
}
