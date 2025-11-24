// 文件路径: src/main/ets/components/MangaViewer.ets
/**
 * 漫画查看器核心组件
 * 支持单页/双页/连续滚动模式、缩放、手势翻页、图片预加载等功能
 */

import { logger } from '../Utils/Logger';
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
  ImageSourceType
} from '../Models/MangaModels';
import { colorMap } from '../Data/ResourceMap';
import { 
  curves, 
  UIContext
} from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { ImageCacheManager, LoadOptions, RequestHeaders } from '../Framework/Cache/ImageCacheManager';

const TAG = 'MangaViewer';

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
 * 条漫/页面 懒加载数据源
 * 实现 ArkUI 的 IDataSource 接口，供 LazyForEach 使用
 */
class MangaPageDataSource implements IDataSource {
  private pages: MangaPage[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(pages: MangaPage[]) {
    this.pages = pages;
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): MangaPage {
    return this.pages[index];
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

  setPages(pages: MangaPage[]): void {
    this.pages = pages;
    this.notifyDataReload();
  }

  notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  notifyDataAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index);
    });
  }

  notifyDataChange(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataChange(index);
    });
  }

  notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }
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

/**
 * 图片加载状态
 */
interface dimensions {
  width: number;
  height: number;
}

interface ImageLoadState {
  /** 是否正在加载 */
  isLoading: boolean;
  /** 是否加载成功 */
  isLoaded: boolean;
  /** 错误信息 */
  error?: string;
  /** 图片尺寸 */
  dimensions?: dimensions;
}

interface PixelMapMeta {
  path: string;
  size: number;
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
}

@Component
export struct MangaViewer {
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
  @State private previewPrevImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevPageId: string = '';
  @State private previewNextImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewNextPageId: string = '';
  @State private previewPrevLeftImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevLeftPageId: string = '';
  @State private previewPrevRightImageInput: Resource | string | image.PixelMap = $r('app.media.ic_image');
  @State private previewPrevRightPageId: string = '';
  private networkLoadInProgress: number = 0;
  private readonly MAX_NETWORK_CONCURRENCY: number = 10; // 优化：增加并发数到10，提升加载速度
  private pendingNetworkLoads: string[] = [];
  private priorityLoadQueue: string[] = []; // 高优先级加载队列（当前页和相邻页）

  public kickstartLoading(): void {
    this.preloadSinglePageWebtoonStyle();
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
        // 触发预加载相邻页面
        this.preloadSinglePageNeighbors();
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
  private pagePixelMapMeta: Map<string, PixelMapMeta> = new Map();
  @State private currentScale: number = 1.0;
  // 双页模式渲染所需的左右页索引（使用@State确保UI响应式刷新）
  @State private leftPageIndex: number = -1;
  @State private rightPageIndex: number = -1;
  @State private translateX: number = 0;
  @State private translateY: number = 0;
  @State private isDragging: boolean = false;
  @State private swipeTriggered: boolean = false;
  @State private lastSwipeAt: number = 0;
  private readonly SWIPE_COOLDOWN_MS: number = 250;
  @State private pageChangeCommitted: boolean = false;
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
  private lastUpdateTime: number = 0;
  private scrollPositionKey: string = ''; // 滚动位置存储键

  // 图片缓存管理
  private imageCache: Map<string, PixelMapMeta> = new Map();
  private imageCacheSize: number = 0;
  private readonly MAX_CACHE_SIZE: number = 50 * 1024 * 1024; // 50MB
  private readonly PRELOAD_RANGE: number = 8; // 预加载前后页的基础范围
  private readonly CACHE_CLEANUP_THRESHOLD: number = 0.8; // 缓存使用率达到80%时清理
  private pendingLoadTimers: Map<string, number> = new Map();
  
  // 图源预加载设置（从外部传入）
  @Prop preloadCurrentPages?: number; // 当前章节预加载页数，默认10
  @Prop preloadNextPages?: number;    // 下一章节预加载页数，默认-1（全部）

  // 条漫手势优化
  @State private webtoonZoomScale: number = 1.0;
  @State private webtoonOffsetX: number = 0;
  @State private webtoonOffsetY: number = 0;
  @State private isZooming: boolean = false;
  private readonly DOUBLE_TAP_THRESHOLD: number = 300; // 双击间隔阈值（毫秒）
  private readonly MIN_ZOOM_SCALE: number = 1.0;
  private readonly MAX_ZOOM_SCALE: number = 3.0;

  // 手势相关
  @State private panStartX: number = 0;
  @State private panStartY: number = 0;
  @State private initialTranslateX: number = 0;
  @State private initialTranslateY: number = 0;

  // 滚动相关（连续滚动模式）
  @State private scrollOffset: number = 0;
  private scroller: Scroller = new Scroller();

  // 动画系统
  private animationManager: GlobalAnimationManager = globalAnimationManager;
  private animationId: string = '';
  private uiContext: UIContext | undefined = undefined;

  // 翻页动画状态
  @State private isPageTurning: boolean = false;
  @State private suppressExternalIndex: boolean = false;
  @State private pageTurnDirection: 'left' | 'right' | 'up' | 'down' | null = null;
  @State private pageTurnProgress: number = 0;
  @State private renderEpoch: number = 0;

  // 预加载相关
  private preloadRange: number = 2; // 预加载前后2页
  
  // 内容类型（用于判断预加载策略）
  @Prop contentType?: string;

  // LazyForEach 数据源（ArkUI 要求 IDataSource 实例）
  private pageDataSource: MangaPageDataSource = new MangaPageDataSource([]);

  aboutToAppear() {
    this.currentScale = this.zoomScale;
    this.animationId = AnimationUtils.generateAnimationId();
    this.uiContext = this.getUIContext();
    this.viewCurrentPageIndex = this.currentPageIndex;
    this.updateSinglePageDisplay();
    
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
    }
    
    // 初始化屏幕尺寸
    this.initScreenSize();
    
    this.initializeImageStates();
    // 初始化双页模式的左右页索引
    this.updateDoublePageIndices();
    
    // 初始化滚动位置键
    this.initScrollPositionKey();
    
    // 恢复滚动位置
    this.restoreScrollPosition();
    if (this.isWebtoonMode() && this.currentPageIndex > 0 && this.savedScrollPosition <= 0) {
      setTimeout(() => {
        this.smoothScrollToPage(this.currentPageIndex, 1.0);
      }, 0);
    }
    
    // 初始化可见页面
    this.updateVisiblePages();
    
    // 预加载初始图片
    this.preloadNearbyImages();
    this.preloadImages();

    // 初始化 LazyForEach 数据源
    if (this.chapter && this.chapter.pages) {
      this.pageDataSource.setPages(this.chapter.pages);
    }
    
    // 通知父组件组件已准备就绪
    if (this.callbacks.onComponentReady) {
      this.callbacks.onComponentReady(this);
    }
    
    // 添加空值检查，防止访问null对象的属性
    const chapterTitle = this.chapter ? this.chapter.title : '未知章节';
    const currentPage = this.chapter && this.chapter.pages ? (this.currentPageIndex + 1) : 0;
    const totalPages = this.chapter && this.chapter.pages ? this.chapter.pages.length : 0;
    
    logger.info(TAG, '漫画查看器组件初始化' + "当前章节: " + chapterTitle +
      "当前页面: " + '第' + currentPage + '/' + totalPages + '页' +
      "阅读模式: " + this.readingSettings.readingMode.toString());
  }

  /**
   * 监听章节切换
   * 由 chapterTick 变化触发
   */
  private onChapterChange(): void {
    logger.info(TAG, `🔔 [章节切换] 检测到章节切换，chapterTick=${this.chapterTick}，重新初始化组件`);
    
    // 重置页面索引
    this.viewCurrentPageIndex = this.currentPageIndex;
    
    // 重置渲染计数器
    this.renderEpoch = 0;
    
    // 清空所有缓存状态
    this.pagePixelMaps.clear();
    this.imageLoadStates.clear();
    this.pixelMapEpochByPage.clear();
    
    // 重新加载当前页和相邻页
    if (this.chapter && this.chapter.pages && this.chapter.pages.length > 0) {
      logger.info(TAG, `🔄 重新加载章节: ${this.chapter.title}，页面数: ${this.chapter.pages.length}`);
      
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
        if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
           this.ensureDoublePageImagesPreloaded();
        } else if (this.isWebtoonMode()) {
           this.preloadNearbyImages();
        } else {
           this.preloadSinglePageWebtoonStyle();
        }
        
        // 3. 确保当前页立即加载
        const currentPageData = this.getCurrentPageData();
        if (currentPageData.page) {
          this.loadImage(currentPageData.page);
        }
      }
    }
  }

  /**
   * 当前页面索引变化时的回调（@Watch监听）
   */
  onCurrentPageIndexChange(): void {
    if (this.suppressExternalIndex) {
      logger.debug(TAG, `忽略外部索引更新: 外部=${this.currentPageIndex + 1}, 本地=${this.viewCurrentPageIndex + 1}`);
      return;
    }
    logger.debug(TAG, `页面索引变化: 新页面=${this.currentPageIndex + 1}`);
    this.viewCurrentPageIndex = this.currentPageIndex;
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageIndices();
      this.updateDoublePagePreview();
    } else {
      this.updateSinglePageDisplay();
      this.updateSinglePagePreview();
    }
    
    // 触发翻页动画
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.animatePageTurn();
      this.translateX = 0;
      this.translateY = 0;
    }
    
    // 单页模式：强制刷新锚点；双页模式也刷新一次以确保UI重建
    this.renderEpoch = this.renderEpoch + 1;
    
    // 优先加载当前页和相邻页
    this.loadCurrentAndNeighborPages();
    
    // 对于条漫模式，也触发预加载
    if (this.isWebtoonMode()) {
      this.updateVisiblePages();
      this.preloadNearbyImages();
    } else {
      // 非条漫模式，触发预加载
      this.preloadImages();
    }
    if (this.isSinglePageMode()) {
      this.preloadSinglePageWebtoonStyle();
    } else {
      this.preloadImages();
    }
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
    
    // 清理图片缓存
    this.clearImageCache();
  }

  /**
   * 清理所有图片缓存
   */
  private clearImageCache(): void {
    this.imageCache.clear();
    this.imageCacheSize = 0;
    this.preloadedImages.clear();
    logger.debug(TAG, '图片缓存已清理');
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
    
    this.preloadSinglePageWebtoonStyle();
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
    
    // 异步加载所有高优先级页面
    Promise.all(priorityPages.map(page => {
      if (!this.pagePixelMaps.has(page.id)) {
        return this.ensurePixelMapLoaded(page);
      }
      return Promise.resolve();
    }))
      .then(() => {
        logger.info(TAG, `高优先级页面加载完成，刷新UI: currentIdx=${currentIndex}`);
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
    this.isDragging = true;
    this.pageChangeCommitted = false;
    this.swipeTriggered = false;
    this.panStartX = event.fingerList[0].globalX;
    this.panStartY = event.fingerList[0].globalY;
    this.initialTranslateX = this.translateX;
    this.initialTranslateY = this.translateY;
    if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      this.preloadSinglePageNeighbors();
      this.preloadSinglePageWebtoonStyle();
      this.updateSinglePagePreview();
    } else if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.preloadDoublePageNeighbors();
    }
  }

  /**
   * 处理拖拽更新
   */
  private handlePanUpdate(event: GestureEvent): void {
    if (!this.isDragging) return;

    const deltaX = event.fingerList[0].globalX - this.panStartX;
    const deltaY = event.fingerList[0].globalY - this.panStartY;

    if (this.currentScale > 1.0) {
      // 缩放状态下允许拖拽
      this.translateX = this.initialTranslateX + deltaX;
      this.translateY = this.initialTranslateY + deltaY;
    } else if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      // 连续滚动模式下的垂直拖拽
      this.translateY = this.initialTranslateY + deltaY;
    } else if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM)) {
      // 单页上下翻页模式下使用垂直拖拽用于翻页预览
      this.translateY = this.initialTranslateY + deltaY;
    } else {
      // 单页模式下的水平拖拽（用于翻页）
      this.translateX = this.initialTranslateX + deltaX;
    }
  }

  /**
   * 处理拖拽结束
   * 支持双页模式的拖拽翻页
   */
  private handlePanEnd(event: GestureEvent): void {
    this.isDragging = false;
    if (this.swipeTriggered || this.pageChangeCommitted) {
      this.translateX = 0;
      this.translateY = 0;
      return;
    }

    const isDoublePage: boolean = this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;
    const isTTB: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM);

    if (this.currentScale <= 1.0) {
      const thresholdX: number = Math.max(20, Math.floor(this.screenWidth * 0.05));
      const thresholdY: number = Math.max(20, Math.floor(this.screenHeight * 0.05));
      logger.debug(TAG, `拖拽结束: tx=${this.translateX.toFixed ? this.translateX.toFixed(1) : this.translateX}, ty=${this.translateY.toFixed ? this.translateY.toFixed(1) : this.translateY}, thX=${thresholdX}, thY=${thresholdY}, cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);
      let pageChanged: boolean = false;

      if (isDoublePage) {
        const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
        const maxIndex: number = this.chapter.pages.length - 1;
        const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
        const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
        const prevPairStart: number = Math.max(pairStart - 2, 0);

        if (isRTL) {
          if (this.translateX > thresholdX) {
            this.viewCurrentPageIndex = nextPairStart;
            this.updateDoublePageIndices();
            logger.info(TAG, '双页RTL模式：向右拖拽，下一对页');
            pageChanged = true;
          } else if (this.translateX < -thresholdX) {
            this.viewCurrentPageIndex = prevPairStart;
            this.updateDoublePageIndices();
            logger.info(TAG, '双页RTL模式：向左拖拽，上一对页');
            pageChanged = true;
          }
        } else {
          if (this.translateX > thresholdX) {
            this.viewCurrentPageIndex = prevPairStart;
            this.updateDoublePageIndices();
            logger.info(TAG, '双页LTR模式：向右拖拽，上一对页');
            pageChanged = true;
          } else if (this.translateX < -thresholdX) {
            this.viewCurrentPageIndex = nextPairStart;
            this.updateDoublePageIndices();
            logger.info(TAG, '双页LTR模式：向左拖拽，下一对页');
            pageChanged = true;
          }
        }
      } else if (isTTB) {
        // 单页上下模式：依据垂直拖拽距离判断翻页
        if (Math.abs(this.translateY) > thresholdY) {
          if (this.translateY > 0) {
            // 向下拖拽 -> 上一页
            if (this.viewCurrentPageIndex > 0) {
              const newIndex: number = this.viewCurrentPageIndex - 1;
              this.viewCurrentPageIndex = newIndex;
              this.currentPageIndex = newIndex;
              this.suppressExternalIndex = true;
              if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
              this.updateSinglePageDisplay();
              const newPage: MangaPage = this.chapter.pages[newIndex];
              this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
              this.incrementPixelMapEpoch(newPage.id);
              this.renderEpoch = this.renderEpoch + 1;
              pageChanged = true;
            } else if (this.callbacks.onChapterChange) {
              this.callbacks.onChapterChange('prev');
            }
            logger.info(TAG, '单页TTB模式：向下拖拽，上一页');
          } else {
            // 向上拖拽 -> 下一页
            if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
              const newIndex: number = this.viewCurrentPageIndex + 1;
              this.viewCurrentPageIndex = newIndex;
              this.currentPageIndex = newIndex;
              this.suppressExternalIndex = true;
              if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
              this.updateSinglePageDisplay();
              const newPage: MangaPage = this.chapter.pages[newIndex];
              this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
              this.incrementPixelMapEpoch(newPage.id);
              this.renderEpoch = this.renderEpoch + 1;
              pageChanged = true;
            } else if (this.callbacks.onChapterChange) {
              this.callbacks.onChapterChange('next');
            }
            logger.info(TAG, '单页TTB模式：向上拖拽，下一页');
          }
        }
      } else if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
        this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL) {
        // 单页左右模式：依据水平拖拽距离判断翻页，考虑 RTL 映射
        const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
          (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);

        if (Math.abs(this.translateX) > thresholdX) {
          if (isRTL) {
            if (this.translateX > 0) {
              // RTL：向右拖拽，下一页
              if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
                const newIndex: number = this.viewCurrentPageIndex + 1;
                this.viewCurrentPageIndex = newIndex;
                this.currentPageIndex = newIndex;
                this.suppressExternalIndex = true;
                if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
                this.updateSinglePageDisplay();
                const newPage: MangaPage = this.chapter.pages[newIndex];
                this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
                this.incrementPixelMapEpoch(newPage.id);
                this.renderEpoch = this.renderEpoch + 1;
                pageChanged = true;
              } else if (this.callbacks.onChapterChange) {
                this.callbacks.onChapterChange('next');
              }
              logger.info(TAG, '单页RTL模式：向右拖拽，下一页');
            } else {
              // RTL：向左拖拽，上一页
              if (this.viewCurrentPageIndex > 0) {
                const newIndex: number = this.viewCurrentPageIndex - 1;
                this.viewCurrentPageIndex = newIndex;
                this.currentPageIndex = newIndex;
                this.suppressExternalIndex = true;
                if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
                this.updateSinglePageDisplay();
                const newPage: MangaPage = this.chapter.pages[newIndex];
                this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
                this.incrementPixelMapEpoch(newPage.id);
                this.renderEpoch = this.renderEpoch + 1;
                pageChanged = true;
              } else if (this.callbacks.onChapterChange) {
                this.callbacks.onChapterChange('prev');
              }
              logger.info(TAG, '单页RTL模式：向左拖拽，上一页');
            }
          } else {
            if (this.translateX > 0) {
              // LTR：向右拖拽，上一页
              if (this.viewCurrentPageIndex > 0) {
                const newIndex: number = this.viewCurrentPageIndex - 1;
                this.viewCurrentPageIndex = newIndex;
                this.currentPageIndex = newIndex;
                this.suppressExternalIndex = true;
                if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
                this.updateSinglePageDisplay();
                const newPage: MangaPage = this.chapter.pages[newIndex];
                this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
                this.incrementPixelMapEpoch(newPage.id);
                this.renderEpoch = this.renderEpoch + 1;
                pageChanged = true;
              } else if (this.callbacks.onChapterChange) {
                this.callbacks.onChapterChange('prev');
              }
              logger.info(TAG, '单页水平模式：向右拖拽，上一页');
            } else {
              // LTR：向左拖拽，下一页
              if (this.viewCurrentPageIndex < this.chapter.pages.length - 1) {
                const newIndex: number = this.viewCurrentPageIndex + 1;
                this.viewCurrentPageIndex = newIndex;
                this.currentPageIndex = newIndex;
                this.suppressExternalIndex = true;
                if (this.callbacks.onPageChange) { this.callbacks.onPageChange(newIndex); }
                this.updateSinglePageDisplay();
                const newPage: MangaPage = this.chapter.pages[newIndex];
                this.ensurePixelMapLoaded(newPage).then(() => { this.updateSinglePageDisplay(); }).catch((_e: Error) => {});
                this.incrementPixelMapEpoch(newPage.id);
                this.renderEpoch = this.renderEpoch + 1;
                pageChanged = true;
              } else if (this.callbacks.onChapterChange) {
                this.callbacks.onChapterChange('next');
              }
              logger.info(TAG, '单页水平模式：向左拖拽，下一页');
            }
          }
        }
      }

      if (pageChanged) {
        this.pageChangeCommitted = true;
        this.isCommittingPageTurn = true;
        if (this.viewCurrentPageIndex !== this.currentPageIndex) {
          this.currentPageIndex = this.viewCurrentPageIndex;
        }
        this.suppressExternalIndex = true;
        if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
          this.updateDoublePageIndices();
          this.updateDoublePageDisplay();
        }
        setTimeout(() => {
          if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
            this.updateDoublePagePreview();
          } else {
            this.updateSinglePagePreview();
          }
        }, 200);
        const newPage: MangaPage | undefined = (this.chapter && this.chapter.pages && this.viewCurrentPageIndex >= 0 && this.viewCurrentPageIndex < this.chapter.pages.length)
          ? this.chapter.pages[this.viewCurrentPageIndex] : undefined;
        if (newPage) {
          this.ensurePixelMapLoaded(newPage).catch((_e: Error) => {});
          this.incrementPixelMapEpoch(newPage.id);
        }
        this.renderEpoch = this.renderEpoch + 1;
        if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
          this.ensureDoublePageImagesPreloaded();
        }
        if (this.callbacks.onPageChange) { this.callbacks.onPageChange(this.viewCurrentPageIndex); }
        this.animateToPosition(0, 0);
        logger.debug(TAG, `页面已切换并同步: cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);
        setTimeout(() => { this.suppressExternalIndex = false; }, 0);
        setTimeout(() => { this.pageChangeCommitted = false; }, this.SWIPE_COOLDOWN_MS);
        setTimeout(() => { this.isCommittingPageTurn = false; }, 200);
      } else {
        this.animateToPosition(0, 0);
        logger.debug(TAG, `未触发翻页: 位移复位, cur=${this.currentPageIndex}, view=${this.viewCurrentPageIndex}`);
      }
    }
  }

  /**
   * 执行翻页动画
   */
  private animatePageTurn(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext未初始化，跳过翻页动画');
      return;
    }

    // 设置翻页动画状态
    this.isPageTurning = true;
    
    // 简单的淡入淡出动画
    const animateOptions: AnimateParam = {
      duration: 300,
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      // 动画完成后的回调
      this.isPageTurning = false;
      this.pageTurnDirection = null;
      this.pageTurnProgress = 0;
    });

    logger.debug(TAG, '执行翻页动画');
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
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (this.isCommittingPageTurn) {
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
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    if (this.isCommittingPageTurn) {
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
      return;
    }

    const total: number = this.chapter.pages.length;
    const current: number = Math.min(Math.max(0, this.viewCurrentPageIndex), total - 1);
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const isTTB: boolean = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
    const pairStart: number = current - (current % 2);

    const prevLeft: number = this.leftPageIndex;
    const prevRight: number = this.rightPageIndex;

    if (isRTL) {
      this.rightPageIndex = pairStart;
      this.leftPageIndex = (pairStart + 1 < total) ? pairStart + 1 : -1;
    } else {
      this.leftPageIndex = pairStart;
      this.rightPageIndex = (pairStart + 1 < total) ? pairStart + 1 : -1;
    }

    const leftState: ImageLoadState | undefined = (this.leftPageIndex >= 0 && this.leftPageIndex < total)
      ? this.getPageLoadState(this.chapter.pages[this.leftPageIndex])
      : undefined;
    const rightState: ImageLoadState | undefined = (this.rightPageIndex >= 0 && this.rightPageIndex < total)
      ? this.getPageLoadState(this.chapter.pages[this.rightPageIndex])
      : undefined;
    
    logger.debug(TAG, `双页索引更新: 方向=${isRTL ? 'RTL' : isTTB ? 'TTB' : 'LTR'}, left=${this.leftPageIndex}(${leftState?.isLoaded ? 'loaded' : leftState?.isLoading ? 'loading' : 'idle'}), right=${this.rightPageIndex}(${rightState?.isLoaded ? 'loaded' : rightState?.isLoading ? 'loading' : 'idle'}), current=${this.viewCurrentPageIndex}`);

    // 加载触发由组件onAppear完成，避免非可视页面提前进入超时逻辑
    const pairChanged: boolean = (prevLeft !== this.leftPageIndex) || (prevRight !== this.rightPageIndex);
    if (pairChanged) {
      this.ensureDoublePageImagesPreloaded();
      setTimeout(() => { this.renderEpoch = this.renderEpoch + 1; }, 0);
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
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const maxIndex: number = this.chapter.pages.length - 1;
    const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    const preloadStart: number = isRTL ? nextPairStart : prevPairStart;
    const preloadEnd: number = isRTL ? nextPairStart + 1 : prevPairStart + 1;
    for (let i = preloadStart; i <= preloadEnd; i++) {
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
  private onReadingSettingsChange(): void {
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageIndices();
    } else {
      // 非双页模式重置索引，避免残留
      this.leftPageIndex = -1;
      this.rightPageIndex = -1;
    }
    logger.debug(TAG, `阅读设置变更: mode=${this.readingSettings.readingMode.toString()}, direction=${this.readingSettings.readingDirection.toString()}`);
  }

  /**
   * 处理单页模式滑动手势
   */
  private handleSinglePageSwipe(event: GestureEvent): void {
    this.preloadSinglePageNeighbors();
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
          this.preloadSinglePageWebtoonStyle();
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
          this.preloadSinglePageWebtoonStyle();
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
            this.preloadSinglePageWebtoonStyle();
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
            this.preloadSinglePageWebtoonStyle();
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
            this.preloadSinglePageWebtoonStyle();
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
            this.preloadSinglePageWebtoonStyle();
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
      // 在线漫画：条漫模式预加载更多，单页模式保守
      const isWebtoon = this.isWebtoonMode();
      preloadCount = isWebtoon ? 3 : 1;  // 条漫3页，单页1页
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
    
    // 在线漫画：优先级策略预加载
    if (this.contentType === 'OnlineUndownloaded') {
      // 当前页：优先级10（已经在显示）
      // 预加载接下来的N页（根据preloadCount）
      for (let i = 1; i <= preloadCount; i++) {
        const targetIndex = currentIndex + i;
        if (targetIndex >= totalPages) break;
        
        const page = this.chapter.pages[targetIndex];
        const st = this.getPageLoadState(page);
        const hasPm = this.pagePixelMaps.has(page.id);
        
        if (!hasPm && (!st || !st.isLoading)) {
          // 优先级递减：下一页=8，下下页=6，第三页=4
          const priority = Math.max(2, 10 - i * 2);
          this.loadImageWithPriority(page, priority);
          logger.debug(TAG, `预加载第${targetIndex + 1}页: priority=${priority}`);
        }
      }
    } else {
      // 本地漫画：预加载前后N页
      for (let i = -preloadCount; i <= preloadCount; i++) {
        if (i === 0) continue; // 跳过当前页（已经在显示）
        
        const targetIndex = currentIndex + i;
        if (targetIndex >= 0 && targetIndex < totalPages) {
          const page = this.chapter.pages[targetIndex];
          const st = this.getPageLoadState(page);
          const hasPm = this.pagePixelMaps.has(page.id);
          
          if (!hasPm && (!st || !st.isLoading)) {
            this.loadImage(page);
            logger.debug(TAG, `预加载第${targetIndex + 1}页: ${page.id}`);
          }
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        .opacity(this.getPrevOverlayOpacity())
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        .opacity(this.getNextOverlayOpacity())
      }
      this.buildSinglePageContent()
    }
    .width('100%')
    .height('100%')
    // 单页模式下仅使用PanGesture进行翻页，避免与SwipeGesture产生冲突
  }

  /**
   * 构建单页内容
   */
  @Builder
  buildSinglePageContent() {
    if (this.getCurrentPageData().page) {
      Stack() {
        this.buildPageImageContent(this.getCurrentPageData().page!)
      }
      .key(`${this.getCurrentPageData().page!.id}_${this.viewCurrentPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.getCurrentPageData().page!.id)}`)
      .width('100%')
      .height('100%')
      .scale({ x: this.currentScale, y: this.currentScale })
      .translate({ x: this.translateX, y: this.translateY })
      .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
            .onActionStart((event: GestureEvent) => this.handlePanStart(event))
            .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
            .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
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
   * 优化：实现图片无缝拼接，保持原始比例，完全无间隔
   */
  @Builder
  buildDoublePageView() {
    Stack() {
      if ((this.previewPrevLeftPageId && this.previewPrevLeftPageId.length > 0) || (this.previewPrevRightPageId && this.previewPrevRightPageId.length > 0)) {
        Row() {
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        .opacity(this.getDoublePrevOverlayOpacity())
      }
      if ((this.previewNextLeftPageId && this.previewNextLeftPageId.length > 0) || (this.previewNextRightPageId && this.previewNextRightPageId.length > 0)) {
        Row() {
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
        .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
        .opacity(this.getDoubleNextOverlayOpacity())
      }
      Row() {
        // 左页（不存在时填充占位）
        if (this.leftPageIndex >= 0) {
          Stack() {
            Image(this.doubleLeftImageInput)
              .key(`${this.doubleLeftPageId}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleLeftPageId)}_${this.pagePixelMaps.has(this.doubleLeftPageId) ? 'pm' : 'url'}`)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .padding(0)
              .margin(0)
              .borderWidth(0)
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
                  const newState: ImageLoadState = { isLoading: false, isLoaded: false, error: '图片加载失败' } as ImageLoadState;
                  this.imageLoadStates.set(lp.id, newState);
                  this.imageLoadStates = new Map(this.imageLoadStates);
                  this.logDetailedImageError(lp, error);
                  this.logImageDisplayAfter(lp, false);
                }
              })
          }
          .onDisAppear(() => {
            logger.debug(TAG, `左页消失: index=${this.leftPageIndex}`);
            this.cleanupInvisiblePixelMaps();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
          .opacity(this.isPageTurning ? 0.7 : 1.0)
          .width('50%')
          .height('100%')
          .padding(0)
          .margin(0)
          .borderWidth(0)
        } else {
          Column()
            .width('50%')
            .height('100%')
            .backgroundColor(colorMap.backgroundSecondary)
            .padding(0)
            .margin(0)
            .borderWidth(0)
        }

        // 右页（当前页，边界检查）
        if (this.rightPageIndex >= 0 && this.rightPageIndex < this.chapter.pages.length) {
          Stack() {
            Image(this.doubleRightImageInput)
              .key(`${this.doubleRightPageId}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.getPixelMapEpoch(this.doubleRightPageId)}_${this.pagePixelMaps.has(this.doubleRightPageId) ? 'pm' : 'url'}`)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .padding(0)
              .margin(0)
              .borderWidth(0)
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
                  const newState: ImageLoadState = { isLoading: false, isLoaded: false, error: '图片加载失败' } as ImageLoadState;
                  this.imageLoadStates.set(rp.id, newState);
                  this.imageLoadStates = new Map(this.imageLoadStates);
                  this.logDetailedImageError(rp, error);
                  this.logImageDisplayAfter(rp, false);
                }
              })
          }
          .onDisAppear(() => {
            logger.debug(TAG, `右页消失: index=${this.rightPageIndex}`);
            this.cleanupInvisiblePixelMaps();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
          .opacity(this.isPageTurning ? 0.7 : 1.0)
          .width('50%')
          .height('100%')
          .padding(0)
          .margin(0)
          .borderWidth(0)
        } else {
          Column()
            .width('50%')
            .height('100%')
            .backgroundColor(colorMap.backgroundSecondary)
            .padding(0)
            .margin(0)
            .borderWidth(0)
        }
      }
      .width('100%')
      .height('100%')
    .key(`${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}_${this.viewCurrentPageIndex}_${this.currentPageIndex}_${this.getPixelMapEpoch(this.leftPageIndex >= 0 ? this.chapter.pages[this.leftPageIndex].id : 'L')}_${this.getPixelMapEpoch(this.rightPageIndex >= 0 ? this.chapter.pages[this.rightPageIndex].id : 'R')}`)
      .translate({ x: this.translateX, y: this.translateY })
      .scale({ x: this.currentScale, y: this.currentScale })
      .padding(0)
      .margin(0)
      .borderWidth(0)
      .justifyContent(FlexAlign.Start)
      
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
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
        .onActionStart((event: GestureEvent) => this.handlePanStart(event))
        .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
        .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
    )
  }

  /**
   * 构建连续滚动显示
   */
  @Builder
  buildContinuousView() {
    if (this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      // 水平连续滚动
      Scroll(this.scroller) {
        Row() {
          ForEach(this.chapter.pages, (page: MangaPage, index: number) => {
            Column() {
              this.buildPageImage(page)
            }
            .margin({ right: this.readingSettings.pageSpacing })
          }, (page: MangaPage) => page.id)
        }
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .onScroll((xOffset: number, yOffset: number) => {
        this.scrollOffset += xOffset;
      })
    } else {
      // 垂直连续滚动/条漫
      Scroll(this.scroller) {
        Column() {
          ForEach(this.chapter.pages, (page: MangaPage, index: number) => {
            Column() {
              this.buildPageImage(page)
            }
            .margin({ bottom: this.readingSettings.pageSpacing })
          }, (page: MangaPage) => page.id)
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Off)
      .onScroll((xOffset: number, yOffset: number) => {
        this.handleWebtoonScroll(yOffset);
      })
    }
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
   * 构建页面图片内容
   * 优化：双页模式下使用Fill填充确保无缝拼接
   */
  @Builder
  buildPageImageContent(page: MangaPage) {
    Stack() {
      Image(this.singlePageImageInput)
        .key(`${this.singlePagePageId}_${this.renderEpoch}_${this.getPixelMapEpoch(this.singlePagePageId)}_${this.pagePixelMaps.has(this.singlePagePageId) ? 'pm' : 'url'}`)
        .width('100%')
        .height('100%')
        .objectFit(this.getImageFitMode(page))
        .padding(0)
        .margin(0)
        .borderWidth(0)
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
          }
          logger.debug(TAG, `单页图片加载完成: id=${page.id}, src=${String(this.getImageResource(page))}, pm=${this.pagePixelMaps.has(page.id)}, epoch=${this.getPixelMapEpoch(page.id)}`);
          const timerId = this.pendingLoadTimers.get(page.id);
          if (typeof timerId === 'number') { clearTimeout(timerId); }
          this.pendingLoadTimers.delete(page.id);
        })
        .onError((error: ImageError) => {
          const newState: ImageLoadState = {
            isLoading: false,
            isLoaded: false,
            error: '图片加载失败'
          } as ImageLoadState;
          const existedPm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
          if (existedPm) {
            try { existedPm.release(); } catch (_e) {}
            this.pagePixelMaps.delete(page.id);
            this.pagePixelMapMeta.delete(page.id);
            this.incrementPixelMapEpoch(page.id);
            this.singlePageImageInput = this.getImageResource(page);
          }
          this.imageLoadStates.set(page.id, newState);
          this.imageLoadStates = new Map(this.imageLoadStates);
          this.logDetailedImageError(page, error);
          this.logImageDisplayAfter(page, false);
          const timerId = this.pendingLoadTimers.get(page.id);
          if (typeof timerId === 'number') { clearTimeout(timerId); }
          this.pendingLoadTimers.delete(page.id);
        })

      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('app.media.ic_error'))
            .width(32)
            .height(32)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 4 })
        }
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
          const newState: ImageLoadState = {
            isLoading: false,
            isLoaded: false,
            error: '图片加载失败'
          } as ImageLoadState;
          const existedPm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
          if (existedPm) {
            try { existedPm.release(); } catch (_e) {}
            this.pagePixelMaps.delete(page.id);
            this.pagePixelMapMeta.delete(page.id);
            this.incrementPixelMapEpoch(page.id);
            if (page.id === this.doubleLeftPageId) {
              this.doubleLeftImageInput = this.getImageResource(page);
            } else if (page.id === this.doubleRightPageId) {
              this.doubleRightImageInput = this.getImageResource(page);
            }
          }
          this.imageLoadStates.set(page.id, newState);
          this.imageLoadStates = new Map(this.imageLoadStates);
          this.logDetailedImageError(page, error);
          this.logImageDisplayAfter(page, false);
          const timerId = this.pendingLoadTimers.get(page.id);
          if (typeof timerId === 'number') { clearTimeout(timerId); }
          this.pendingLoadTimers.delete(page.id);
        })

      if (this.shouldShowLoadingForPage(page)) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(colorMap.accent)
      }

      if (this.getPageLoadState(page)?.error) {
        Column() {
          Image($r('app.media.ic_error'))
            .width(32)
            .height(32)
            .fillColor(colorMap.error)
          Text('加载失败')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
            .margin({ top: 4 })
        }
      }
    }
  }

  /**
   * 根据滚动位置更新当前页面索引
   */
  private updateCurrentPageFromScroll(): void {
    // TODO: 实现根据滚动位置计算当前页面的逻辑
    // 这需要知道每个页面的高度和位置
  }

  /**
   * 处理双页模式滑动手势：支持平滑单页翻页
   * 新逻辑：每次滑动翻一页，保持双页显示
   * 修复：TTB模式使用正确的上下翻页逻辑
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

    const isTTB: boolean = this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
    const isRTL: boolean = this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const maxIndex: number = this.chapter.pages.length - 1;
    const pairStart: number = this.viewCurrentPageIndex - (this.viewCurrentPageIndex % 2);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));
    const prevPairStart: number = Math.max(pairStart - 2, 0);

    if (isTTB) {
      const isSwipeUp: boolean = angle <= -45 && angle >= -135;
      const isSwipeDown: boolean = angle >= 45 && angle <= 135;

      if (isSwipeUp && nextPairStart <= maxIndex) {
        this.viewCurrentPageIndex = nextPairStart;
        this.updateDoublePageIndices();
        this.preloadDoublePageNeighbors();
        if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
        logger.info(TAG, '双页TTB：上滑，下一对页');
      } else if (isSwipeDown) {
        this.viewCurrentPageIndex = prevPairStart;
        this.updateDoublePageIndices();
        this.preloadDoublePageNeighbors();
        if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
        logger.info(TAG, '双页TTB：下滑，上一对页');
      }
    } else {
      const isSwipeRight: boolean = angle >= -45 && angle <= 45;
      const isSwipeLeft: boolean = angle >= 135 || angle <= -135;

      if (isSwipeRight) {
        if (isRTL) {
          this.viewCurrentPageIndex = nextPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
          logger.info(TAG, '双页RTL：右滑，下一对页');
        } else {
          this.viewCurrentPageIndex = prevPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
          logger.info(TAG, '双页LTR：右滑，上一对页');
        }
      } else if (isSwipeLeft) {
        if (isRTL) {
          this.viewCurrentPageIndex = prevPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(prevPairStart); }
          logger.info(TAG, '双页RTL：左滑，上一对页');
        } else {
          this.viewCurrentPageIndex = nextPairStart;
          this.updateDoublePageIndices();
          this.preloadDoublePageNeighbors();
          if (this.callbacks.onPageChange) { this.callbacks.onPageChange(nextPairStart); }
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
    if (!this.scroller) { return; }
    try {
      this.scroller.scrollTo({
        xOffset: targetX,
        yOffset: 0,
        animation: { duration: 500, curve: curves.initCurve(Curve.EaseInOut) }
      });
    } catch (error) {
      logger.error(TAG, `水平平滑滚动失败`);
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
   * 获取翻页方向
   */
  private getPageDirection(): 'horizontal' | 'vertical' {
    if (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
        this.isWebtoonMode()) {
      return 'vertical';
    }
    return 'horizontal';
  }

  private getPrevOverlayOpacity(): number {
    const isTTB: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
    const isRTL: boolean = this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      (this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE && this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT);
    if (this.isCommittingPageTurn) {
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
    if (this.isCommittingPageTurn) {
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
    if (!this.chapter || !this.chapter.pages) { return undefined; }
    const idx: number = this.getPageIndexById(pageId);
    if (idx >= 0 && idx < this.chapter.pages.length) { return this.chapter.pages[idx]; }
    return undefined;
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

  /**
   * 构建优化的条漫视图
   */
  @Builder
  buildWebtoonView() {
    Scroll(this.scroller) {
      Column() {
        LazyForEach(this.pageDataSource, (page: MangaPage, index: number) => {
          this.buildOptimizedImage(page, index)
        }, (page: MangaPage, index: number) => `${page.id}_${index}`)
      }
      .scale({ x: this.webtoonZoomScale, y: this.webtoonZoomScale })
      .translate({ x: this.webtoonOffsetX, y: this.webtoonOffsetY })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .onScroll((xOffset: number, yOffset: number) => {
      this.handleWebtoonScroll(yOffset);
    })
    .onScrollStart(() => {
      this.isScrolling = true;
    })
    .onScrollStop(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      this.preloadNearbyImages();
    })
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
          .onActionUpdate((event: GestureEvent) => {
            if (this.webtoonZoomScale > this.MIN_ZOOM_SCALE) {
              this.handleWebtoonPan(event);
            }
          }),
        PinchGesture({ fingers: 2, distance: 5 })
          .onActionUpdate((event: GestureEvent) => {
            this.handleWebtoonPinch(event);
          }),
        SwipeGesture({ fingers: 1, direction: SwipeDirection.Horizontal, speed: 100 })
          .onAction((event: GestureEvent) => {
            this.handleEdgeSwipe(event);
          })
      )
    )
  }

  /**
   * 构建优化的带间隙条漫视图
   */
  @Builder
  buildWebtoonWithGapView() {
    Scroll(this.scroller) {
      Column({ space: this.readingSettings.pageSpacing || 16 }) {
        LazyForEach(this.pageDataSource, (page: MangaPage, index: number) => {
          this.buildOptimizedImage(page, index)
        }, (page: MangaPage, index: number) => `${page.id}_${index}`)
      }
      .padding({ top: 8, bottom: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    .onScroll((xOffset: number, yOffset: number) => {
      this.handleWebtoonScroll(yOffset);
    })
    .onScrollStart(() => {
      this.isScrolling = true;
    })
    .onScrollStop(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      this.preloadNearbyImages();
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
    const pm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    if (pm) {
      return pm;
    }
    return this.getImageResource(page);
  }

  private shouldShowLoadingForPage(page: MangaPage): boolean {
    if (page.sourceType === ImageSourceType.LOCAL) {
      const st: ImageLoadState | undefined = this.getPageLoadState(page);
      const hasPm: boolean = this.pagePixelMaps.has(page.id);
      return (!hasPm && !!st && st.isLoading === true);
    } else {
      const st: ImageLoadState | undefined = this.getPageLoadState(page);
      return !!st && st.isLoading === true && st.isLoaded !== true;
    }
  }

  private computeImageInputForPage(page: MangaPage): Resource | string | image.PixelMap {
    const pm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    if (pm) {
      return pm;
    }
    return this.getImageResource(page);
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
    
    // 强制递增renderEpoch，确保Image组件重新渲染
    this.renderEpoch = this.renderEpoch + 1;
    
    this.singlePagePageId = page.id;
    // 始终使用URL，不使用PixelMap作为Image的src
    // PixelMap仅用于预加载和缓存，Image组件会从缓存中读取
    this.singlePageImageInput = this.getImageResource(page);
    
    // 记录当前状态用于调试
    const hasPm = this.pagePixelMaps.has(page.id);
    const pmEpoch = this.getPixelMapEpoch(page.id);
    logger.debug(TAG, `单页显示更新: idx=${idx}, id=${page.id}, hasPm=${hasPm}, epoch=${pmEpoch}, renderEpoch=${this.renderEpoch}, src=${String(this.singlePageImageInput)}`);
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
      // 始终使用URL，不使用PixelMap
      this.previewPrevImageInput = this.getImageResource(prevPage);
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
      // 始终使用URL，不使用PixelMap
      this.previewNextImageInput = this.getImageResource(nextPage);
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
    const total: number = this.chapter.pages.length;
    const current: number = Math.min(Math.max(0, this.viewCurrentPageIndex), total - 1);
    const pairStart: number = current - (current % 2);
    const maxIndex: number = total - 1;
    const prevPairStart: number = Math.max(pairStart - 2, 0);
    const nextPairStart: number = Math.min(pairStart + 2, maxIndex - (maxIndex % 2));

    if (prevPairStart >= 0 && prevPairStart < total) {
      const prevLeft: MangaPage = this.chapter.pages[prevPairStart];
      const prevRightIdx: number = prevPairStart + 1;
      const prevRightValid: boolean = prevRightIdx < total;
      this.previewPrevLeftPageId = prevLeft.id;
      // 始终使用URL，不使用PixelMap
      this.previewPrevLeftImageInput = this.getImageResource(prevLeft);
      if (prevRightValid) {
        const prevRight: MangaPage = this.chapter.pages[prevRightIdx];
        this.previewPrevRightPageId = prevRight.id;
        // 始终使用URL，不使用PixelMap
        this.previewPrevRightImageInput = this.getImageResource(prevRight);
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
      // 始终使用URL，不使用PixelMap
      this.previewNextLeftImageInput = this.getImageResource(nextLeft);
      if (nextRightValid) {
        const nextRight: MangaPage = this.chapter.pages[nextRightIdx];
        this.previewNextRightPageId = nextRight.id;
        // 始终使用URL，不使用PixelMap
        this.previewNextRightImageInput = this.getImageResource(nextRight);
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
      // 始终使用URL，不使用PixelMap作为Image的src
      this.doubleLeftImageInput = this.getImageResource(lp);
      const hasLPm = this.pagePixelMaps.has(lp.id);
      logger.debug(TAG, `双页左侧更新: idx=${this.leftPageIndex}, id=${lp.id}, hasPm=${hasLPm}, src=${String(this.doubleLeftImageInput)}`);
    } else {
      this.doubleLeftPageId = '';
      this.doubleLeftImageInput = $r('app.media.ic_image');
    }
    if (this.rightPageIndex >= 0 && this.rightPageIndex < this.chapter.pages.length) {
      const rp: MangaPage = this.chapter.pages[this.rightPageIndex];
      this.doubleRightPageId = rp.id;
      // 始终使用URL，不使用PixelMap作为Image的src
      this.doubleRightImageInput = this.getImageResource(rp);
      const hasRPm = this.pagePixelMaps.has(rp.id);
      logger.debug(TAG, `双页右侧更新: idx=${this.rightPageIndex}, id=${rp.id}, hasPm=${hasRPm}, src=${String(this.doubleRightImageInput)}`);
    } else {
      this.doubleRightPageId = '';
      this.doubleRightImageInput = $r('app.media.ic_image');
    }
  }
  private invalidatePixelMapIfSourceChanged(page: MangaPage): void {
    const id: string = page.id;
    const meta: PixelMapMeta | undefined = this.pagePixelMapMeta.get(id);
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
          try { existed.release(); } catch (_e) {}
          this.pagePixelMaps.delete(id);
          this.pagePixelMapMeta.delete(id);
          this.pagePixelMaps = new Map(this.pagePixelMaps);
          this.imageLoadStates.delete(id);
          this.imageLoadStates = new Map(this.imageLoadStates);
          this.incrementPixelMapEpoch(id);
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
      return;
    }
    if (page.sourceType === ImageSourceType.LOCAL) {
      const fsPath: string | undefined = this.getFsPathFromPage(page);
      if (!fsPath) {
        // 本地路径缺失，尝试网络回退
        if (page.imageUrl && page.imageUrl.length > 0) {
          await this.loadNetworkPixelMapWithConcurrency(page);
        }
        return;
      }
      try {
        const src: image.ImageSource = image.createImageSource(fsPath);
        const decodingOptions: image.DecodingOptions = { desiredPixelFormat: image.PixelMapFormat.RGBA_8888 } as image.DecodingOptions;
        const pm: image.PixelMap = await src.createPixelMap(decodingOptions);
        this.pagePixelMaps.set(page.id, pm);
        this.pagePixelMaps = new Map(this.pagePixelMaps);
        try {
          const statInfo = await fs.stat(fsPath);
          const sizeNum: number = statInfo.size ? (statInfo.size as number) : 0;
          this.pagePixelMapMeta.set(page.id, { path: fsPath, size: sizeNum } as PixelMapMeta);
        } catch (_e) {}
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
        logger.debug(TAG, `PixelMap加载完成: id=${page.id}, path=${fsPath}, epoch=${this.getPixelMapEpoch(page.id)}`);
        
        // PixelMap加载完成后，如果是当前可见页面，立即刷新UI
        this.notifyPixelMapLoaded(page);
      } catch (err) {
        this.logDetailedLoadError(page, err as BusinessError);
        // 本地加载失败时进行网络回退
        if (page.imageUrl && page.imageUrl.length > 0) {
          await this.loadNetworkPixelMapWithConcurrency(page);
        }
      }
      return;
    }
    if (page.sourceType === ImageSourceType.NETWORK) {
      // [新增] 详细日志，确认 headers 内容
      const currentReferer = this.networkHeaders?.referer || 'undefined';
      logger.debug(TAG, `准备加载网络图片: id=${page.id}, referer=${currentReferer}`);
      
      if (this.networkLoadInProgress >= this.MAX_NETWORK_CONCURRENCY) {
        const alreadyQueued: boolean = this.pendingNetworkLoads.indexOf(page.id) >= 0;
        if (!alreadyQueued) {
          this.pendingNetworkLoads.push(page.id);
        }
        return;
      }
      this.networkLoadInProgress++;
      try {
        const cacheManager: ImageCacheManager = ImageCacheManager.getInstance();
        const opts: LoadOptions = {
          width: page.width,
          height: page.height,
          headers: this.networkHeaders,
          sourceId: this.sourceId,
          mangaId: this.mangaId,
          chapterId: this.chapter.id,
          pageIndex: page.index,
          priority: page.priority || 1,
          contentType: this.contentType
        } as LoadOptions;
        const cookieStr: string = (this.networkHeaders && this.networkHeaders.cookie) ? String(this.networkHeaders.cookie) : '';
        const refererStr: string = (this.networkHeaders && this.networkHeaders.referer) ? String(this.networkHeaders.referer) : '';
        const uaStr: string = (this.networkHeaders && this.networkHeaders.userAgent) ? String(this.networkHeaders.userAgent) : '';
        const langStr: string = (this.networkHeaders && this.networkHeaders.acceptLanguage) ? String(this.networkHeaders.acceptLanguage) : '';
        const uaLog: string = uaStr.substring(0, Math.min(64, uaStr.length));
        logger.debug('MangaViewer', `开始网络加载: url=${page.imageUrl}, ua=${uaLog}, langLen=${langStr.length}, cookieLen=${cookieStr.length}, referer=${refererStr}`);
        const pm: image.PixelMap | null = await cacheManager.loadImage(page.imageUrl, opts);
        if (pm) {
          this.pagePixelMaps.set(page.id, pm);
          this.pagePixelMaps = new Map(this.pagePixelMaps);
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
          logger.debug(TAG, `网络PixelMap加载完成: id=${page.id}, url=${page.imageUrl}, epoch=${this.getPixelMapEpoch(page.id)}`);
          
          // PixelMap加载完成后，如果是当前可见页面，立即刷新UI
          this.notifyPixelMapLoaded(page);
          this.cleanupInvisiblePixelMaps();
        } else {
          const st: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
          if (st) {
            st.isLoading = false;
            st.isLoaded = false;
            st.error = '网络图片加载失败';
            this.imageLoadStates.set(page.id, st);
            this.imageLoadStates = new Map(this.imageLoadStates);
          }
          logger.error(TAG, `网络图片加载失败: id=${page.id}, url=${page.imageUrl}`);
        }
      } catch (err) {
        this.logDetailedLoadError(page, err as BusinessError);
      } finally {
        this.networkLoadInProgress = Math.max(0, this.networkLoadInProgress - 1);
        if (this.pendingNetworkLoads.length > 0) {
          const nextId: string = this.pendingNetworkLoads.shift() as string;
          const idx: number = this.getPageIndexById(nextId);
          if (idx >= 0 && this.chapter && this.chapter.pages && idx < this.chapter.pages.length) {
            const nextPage: MangaPage = this.chapter.pages[idx];
            this.ensurePixelMapLoaded(nextPage).catch((_e: Error) => {});
          }
        }
      }
      return;
    }
  }

  private async loadNetworkPixelMapWithConcurrency(page: MangaPage): Promise<void> {
    if (this.networkLoadInProgress >= this.MAX_NETWORK_CONCURRENCY) {
      const alreadyQueued: boolean = this.pendingNetworkLoads.indexOf(page.id) >= 0;
      if (!alreadyQueued) {
        this.pendingNetworkLoads.push(page.id);
      }
      return;
    }
    this.networkLoadInProgress++;
    try {
      const cacheManager: ImageCacheManager = ImageCacheManager.getInstance();
      const opts: LoadOptions = {
        width: page.width,
        height: page.height,
        headers: this.networkHeaders,
        sourceId: this.sourceId,
        mangaId: this.mangaId,
        chapterId: this.chapter.id,
        pageIndex: page.index
      } as LoadOptions;
      const pm: image.PixelMap | null = await cacheManager.loadImage(page.imageUrl, opts);
      if (pm) {
        this.pagePixelMaps.set(page.id, pm);
        this.pagePixelMaps = new Map(this.pagePixelMaps);
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
        logger.debug(TAG, `网络PixelMap加载完成(回退): id=${page.id}, url=${page.imageUrl}, epoch=${this.getPixelMapEpoch(page.id)}`);
        this.cleanupInvisiblePixelMaps();
      } else {
        const st: ImageLoadState | undefined = this.imageLoadStates.get(page.id);
        if (st) {
          st.isLoading = false;
          st.isLoaded = false;
          st.error = '网络图片加载失败(回退)';
          this.imageLoadStates.set(page.id, st);
          this.imageLoadStates = new Map(this.imageLoadStates);
        }
        logger.error(TAG, `网络图片加载失败(回退): id=${page.id}, url=${page.imageUrl}`);
      }
    } catch (err2) {
      this.logDetailedLoadError(page, err2 as BusinessError);
    } finally {
      this.networkLoadInProgress = Math.max(0, this.networkLoadInProgress - 1);
      if (this.pendingNetworkLoads.length > 0) {
        const nextId: string = this.pendingNetworkLoads.shift() as string;
        const idx: number = this.getPageIndexById(nextId);
        if (idx >= 0 && this.chapter && this.chapter.pages && idx < this.chapter.pages.length) {
          const nextPage: MangaPage = this.chapter.pages[idx];
          this.ensurePixelMapLoaded(nextPage).catch((_e: Error) => {});
        }
      }
    }
  }
  private cleanupInvisiblePixelMaps(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    const totalPagesCount: number = this.chapter.pages.length;
    let threshold: number = Math.floor(totalPagesCount / 5);
    if (threshold < 10) { threshold = 10; }
    if (this.pagePixelMaps.size < threshold) { return; }
    const keys: string[] = Array.from(this.pagePixelMaps.keys());
    for (let i = 0; i < keys.length; i++) {
      const id: string = keys[i];
      const idx: number = this.getPageIndexById(id);
      if (idx < 0) {
        continue;
      }
      const p: MangaPage = this.chapter.pages[idx];
      const visible: boolean = this.isPageCurrentlyVisible(p);
      if (!visible) {
        const pm: image.PixelMap | undefined = this.pagePixelMaps.get(id);
        if (pm) {
          try { pm.release(); } catch (e) {}
        }
        this.pagePixelMaps.delete(id);
        this.pagePixelMapMeta.delete(id);
      }
    }
    this.pagePixelMaps = new Map(this.pagePixelMaps);
  }

  private incrementPixelMapEpoch(pageId: string): void {
    const v: number | undefined = this.pixelMapEpochByPage.get(pageId);
    const nv: number = v && v > 0 ? v + 1 : 1;
    this.pixelMapEpochByPage.set(pageId, nv);
    this.pixelMapEpochByPage = new Map(this.pixelMapEpochByPage);
  }

  private getPixelMapEpoch(pageId: string): number {
    const v: number | undefined = this.pixelMapEpochByPage.get(pageId);
    if (v && v > 0) { return v; }
    return 0;
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
    const pageIdx = this.getPageIndexById(page.id);
    if (pageIdx < 0) {
      return;
    }
    
    // 检查是否是当前可见页面
    const isVisible = this.isPageCurrentlyVisible(page);
    if (!isVisible) {
      logger.debug(TAG, `PixelMap加载完成但页面不可见: id=${page.id}, idx=${pageIdx}`);
      return;
    }
    
    logger.info(TAG, `PixelMap加载完成且页面可见，刷新UI: id=${page.id}, idx=${pageIdx}`);
    
    // 根据阅读模式刷新对应的显示
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.updateDoublePageDisplay();
    } else {
      this.updateSinglePageDisplay();
    }
  }
  
  private getFsPathFromPage(page: MangaPage): string | undefined {
    if (page.sourceType !== ImageSourceType.LOCAL) {
      return undefined;
    }
    const candidate: string = (page.imageUrl && page.imageUrl.length > 0) ? page.imageUrl : page.imagePath;
    if (!candidate || candidate.length === 0) {
      return undefined;
    }
    if (candidate.startsWith('file://')) {
      const rawPath: string = candidate.substring(7);
      return rawPath;
    }
    if (candidate.startsWith('/')) {
      return candidate;
    }
    return undefined;
  }

  private getPageIndexById(pageId: string): number {
    if (!this.chapter || !this.chapter.pages) {
      return -1;
    }
    const total: number = this.chapter.pages.length;
    for (let i = 0; i < total; i++) {
      const p: MangaPage = this.chapter.pages[i];
      if (p && p.id === pageId) {
        return i;
      }
    }
    return -1;
  }

  private isPageCurrentlyVisible(page: MangaPage): boolean {
    const idx: number = this.getPageIndexById(page.id);
    if (idx < 0) {
      return false;
    }
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      return idx === this.leftPageIndex || idx === this.rightPageIndex;
    }
    if (this.isWebtoonMode()) {
      for (let i = 0; i < this.visiblePageIndices.length; i++) {
        if (this.visiblePageIndices[i] === idx) {
          return true;
        }
      }
      return false;
    }
    return idx === this.viewCurrentPageIndex;
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
    logger.info(TAG, `开始显示图片: id=${page.id}, type=${page.sourceType.toString()}, input=${inputStr}, pixelMap=${pm ? true : false}`);
  }

  private logImageDisplayAfter(page: MangaPage, success: boolean): void {
    const pm: image.PixelMap | undefined = this.pagePixelMaps.get(page.id);
    const fsPath: string | undefined = this.getFsPathFromPage(page);
    const resStr: string = String(this.getImageResource(page));
    logger.info(TAG, `图片显示结束: id=${page.id}, success=${success}, type=${page.sourceType.toString()}, resource=${resStr}, path=${fsPath ? fsPath : 'N/A'}, pixelMap=${pm ? true : false}`);
  }

  /**
   * 注意：条漫双击事件也已移至Page层统一处理
   * 此方法已废弃，保留toggleWebtoonZoom供将来可能使用
   */

  /**
   * 切换条漫缩放状态
   */
  private toggleWebtoonZoom(centerX: number, centerY: number): void {
    if (!this.uiContext) {
      return;
    }

    const targetScale = this.webtoonZoomScale > this.MIN_ZOOM_SCALE ? this.MIN_ZOOM_SCALE : 2.0;
    const animateOptions: AnimateParam = {
      duration: 300,
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(animateOptions, () => {
      this.webtoonZoomScale = targetScale;
      
      if (targetScale === this.MIN_ZOOM_SCALE) {
        // 重置偏移
        this.webtoonOffsetX = 0;
        this.webtoonOffsetY = 0;
      } else {
        // 计算缩放中心点的偏移
        const scaleRatio = targetScale - this.MIN_ZOOM_SCALE;
        const halfW: number = ((this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360) / 2;
        const halfH: number = ((this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800) / 2;
        this.webtoonOffsetX = -(centerX - halfW) * scaleRatio;
        this.webtoonOffsetY = -(centerY - halfH) * scaleRatio;
      }
    });

    logger.debug(TAG, `条漫缩放: ${this.webtoonZoomScale} -> ${targetScale}`);
  }

  /**
   * 处理条漫拖拽手势
   */
  private handleWebtoonPan(event: GestureEvent): void {
    if (this.webtoonZoomScale <= this.MIN_ZOOM_SCALE) {
      return; // 未缩放时不处理拖拽
    }

    const deltaX = event.offsetX;
    const deltaY = event.offsetY;

    // 限制拖拽范围
    const halfW: number = ((this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360) / 2;
    const halfH: number = ((this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800) / 2;
    const maxOffsetX = (this.webtoonZoomScale - 1) * halfW;
    const maxOffsetY = (this.webtoonZoomScale - 1) * halfH;

    this.webtoonOffsetX = Math.max(-maxOffsetX, Math.min(maxOffsetX, this.webtoonOffsetX + deltaX));
    this.webtoonOffsetY = Math.max(-maxOffsetY, Math.min(maxOffsetY, this.webtoonOffsetY + deltaY));
  }

  /**
   * 处理条漫捏合缩放手势
   */
  private handleWebtoonPinch(event: GestureEvent): void {
    const newScale = Math.max(this.MIN_ZOOM_SCALE, 
                             Math.min(this.MAX_ZOOM_SCALE, this.webtoonZoomScale * event.scale));
    
    this.webtoonZoomScale = newScale;
    
    // 如果缩放到最小值，重置偏移
    if (newScale === this.MIN_ZOOM_SCALE) {
      this.webtoonOffsetX = 0;
      this.webtoonOffsetY = 0;
    }
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
    this.scrollPosition = yOffset;
    this.isScrolling = true;
    
    // 清除之前的定时器
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
    }
    
    // 设置滚动结束检测
    this.scrollTimer = setTimeout(() => {
      this.isScrolling = false;
      this.updateVisiblePages();
      this.preloadNearbyImages();
      // 保存滚动位置
      this.saveScrollPosition();
    }, 150);
    
    // 实时更新可见页面（节流处理）
    this.throttledUpdateVisiblePages();
    
    // 通知父组件滚动位置变化
    if (this.callbacks.onScrollPositionChange) {
      this.callbacks.onScrollPositionChange(yOffset);
    }
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
   * 更新可见页面索引
   */
  private updateVisiblePages(): void {
    if (!this.scroller) return;
    const containerHeight: number = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    const spacing = this.readingSettings.pageSpacing || 16;
    
    const visibleIndices: number[] = [];
    const scrollTop = this.scrollPosition;
    const scrollBottom = scrollTop + containerHeight;
    
    for (let i = 0; i < this.chapter.pages.length; i++) {
      const page: MangaPage = this.chapter.pages[i];
      const ph: number = this.getEstimatedImageHeight(page);
      const itemTop = i * (ph + spacing);
      const itemBottom = itemTop + ph;
      
      // 检查是否在可见区域内（包含一定的缓冲区）
      if (itemBottom >= scrollTop - containerHeight && itemTop <= scrollBottom + containerHeight) {
        visibleIndices.push(i);
      }
    }
    
    this.visiblePageIndices = visibleIndices;
    
    // 更新当前页面和滚动进度
    this.updateWebtoonProgress();
  }

  /**
   * 更新条漫进度信息
   */
  private updateWebtoonProgress(): void {
    if (this.visiblePageIndices.length > 0) {
      // 取可见页面的中间页作为当前页
      const middleIndex = Math.floor(this.visiblePageIndices.length / 2);
      this.currentWebtoonPage = this.visiblePageIndices[middleIndex];
    }
    
    // 计算滚动进度
    if (this.chapter && this.chapter.pages && this.chapter.pages.length > 0) {
      const totalPages: number = this.chapter.pages.length;
      const spacing: number = this.readingSettings.pageSpacing || 16;
      let totalHeight: number = 0;
      for (let i = 0; i < totalPages; i++) {
        const page: MangaPage = this.chapter.pages[i];
        totalHeight += this.getEstimatedImageHeight(page);
        if (i < totalPages - 1) { totalHeight += spacing; }
      }
      this.webtoonScrollProgress = Math.min(1, Math.max(0, this.scrollPosition / Math.max(1, totalHeight)));
    }
  }

  /**
   * 预加载附近的图片
   */
  private preloadNearbyImages(): void {
    if (!this.isWebtoonMode()) {
      return;
    }

    const preloadIndices = new Set<number>();
    
    // 为每个可见页面添加前后PRELOAD_RANGE范围内的页面
    const range: number = this.getDynamicPreloadRange();
    for (let vi = 0; vi < this.visiblePageIndices.length; vi++) {
      const visibleIndex: number = this.visiblePageIndices[vi];
      const startIdx: number = Math.max(0, visibleIndex - range);
      const endIdx: number = Math.min(this.chapter.pages.length - 1, visibleIndex + range);
      for (let i = startIdx; i <= endIdx; i++) {
        preloadIndices.add(i);
      }
    }

    // 预加载新的图片
    for (const index of preloadIndices) {
      if (!this.preloadedImages.has(index)) {
        this.preloadImageWithCache(index);
      }
    }

    // 清理不需要的预加载图片
    this.cleanupPreloadedImages(preloadIndices);
  }

  /**
   * 带缓存的图片预加载
   */
  private preloadImageWithCache(pageIndex: number): void {
    if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return;
    }

    const page = this.chapter.pages[pageIndex];
    const imageUrl = page.imageUrl;
    
    // 检查缓存中是否已存在
    if (this.imageCache.has(imageUrl)) {
      this.preloadedImages.add(pageIndex);
      return;
    }

    // 检查缓存大小，必要时清理
    if (this.imageCacheSize > this.MAX_CACHE_SIZE * this.CACHE_CLEANUP_THRESHOLD) {
      this.cleanupImageCache();
    }

    // 使用HarmonyOS支持的图片预加载方式
    try {
      let estimatedSize: number = 1024 * 1024;
      if (page.width && page.height) {
        estimatedSize = Math.floor(page.width * page.height * 4);
      }
      if (this.imageCacheSize + estimatedSize <= this.MAX_CACHE_SIZE) {
        const fsPath: string | undefined = this.getFsPathFromPage(page);
        const meta: PixelMapMeta = { path: fsPath ? fsPath : imageUrl, size: estimatedSize } as PixelMapMeta;
        this.imageCache.set(imageUrl, meta);
        this.preloadedImages.add(pageIndex);
        this.imageCacheSize += estimatedSize;
        logger.debug(TAG, `图片预加载成功: 页面${pageIndex}, 估算大小: ${Math.floor(estimatedSize / 1024)}KB, 缓存大小: ${this.imageCacheSize / 1024 / 1024}MB`);
      }
    } catch (error) {
      logger.error(TAG, `图片预加载失败: 页面${pageIndex}`, String(error));
    }
  }

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
    }
  }

  /**
   * 从缓存中移除图片
   */
  private removeFromImageCache(imageUrl: string): void {
    if (this.imageCache.has(imageUrl)) {
      const meta = this.imageCache.get(imageUrl) as PixelMapMeta;
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
          this.handleImageError(index);
          this.logDetailedImageError(page, error);
          this.logImageDisplayAfter(page, false);
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
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
        const meta: PixelMapMeta = { path: imageUrl, size: estimatedSize } as PixelMapMeta;
        this.imageCache.set(imageUrl, meta);
        this.imageCacheSize += estimatedSize;
        logger.debug(TAG, `图片已缓存: 页面${pageIndex}, 缓存大小: ${this.imageCacheSize / 1024 / 1024}MB`);
      } else {
        this.cleanupImageCache();
        if (this.imageCacheSize + estimatedSize <= this.MAX_CACHE_SIZE) {
          const meta2: PixelMapMeta = { path: imageUrl, size: estimatedSize } as PixelMapMeta;
          this.imageCache.set(imageUrl, meta2);
          this.imageCacheSize += estimatedSize;
        }
      }
    }
  }

  /**
   * 获取预估图片高度
   */
  private getEstimatedImageHeight(page: MangaPage): number {
    if (page.height && page.width) {
      const vw: number = (this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360;
      return (page.height / page.width) * vw;
    }
    const fallbackW: number = (this.screenWidth && this.screenWidth > 0) ? this.screenWidth : 360;
    return Math.floor(fallbackW * 1.66);
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

  private preloadSinglePageWebtoonStyle(): void {
    if (!this.chapter || !this.chapter.pages) {
      return;
    }
    const range: number = this.getDynamicPreloadRange();
    const startIndex: number = Math.max(0, this.viewCurrentPageIndex - range);
    const endIndex: number = Math.min(this.chapter.pages.length - 1, this.viewCurrentPageIndex + range);
    for (let i = startIndex; i <= endIndex; i++) {
      const p: MangaPage = this.chapter.pages[i];
      const st: ImageLoadState | undefined = this.getPageLoadState(p);
      const hasPm: boolean = this.pagePixelMaps.has(p.id);
      if (!hasPm && (!st || !st.isLoading)) {
        this.loadImage(p);
      }
    }
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
    if (this.scrollPositionKey && this.scrollPosition > 0) {
      try {
        // 使用AppStorage保存滚动位置
        AppStorage.setOrCreate(this.scrollPositionKey, this.scrollPosition);
        logger.debug(TAG, `保存滚动位置: ${this.scrollPosition}`);
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
            this.smoothScrollTo(savedPosition);
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

    const spacing = this.readingSettings.pageSpacing || 16;
    let totalHeight = 0;
    
    for (let i = 0; i < this.chapter.pages.length; i++) {
      const page = this.chapter.pages[i];
      const pageHeight = this.getEstimatedImageHeight(page);
      totalHeight += pageHeight + spacing;
    }
    
    // 减去最后一个间距
    totalHeight -= spacing;
    
    // 考虑缩放比例
    if (this.webtoonZoomScale > 1.0) {
      totalHeight *= this.webtoonZoomScale;
    }
    
    const ch: number = (this.screenHeight && this.screenHeight > 0) ? this.screenHeight : 800;
    return Math.max(0, totalHeight - ch);
  }

  /**
   * 平滑滚动到指定页面（条漫模式）
   * 支持精确的页面定位和动画效果
   * @param targetPageIndex 目标页面索引
   * @param scrollSpeed 滚动速度因子（0.5-2.0，1.0为正常速度）
   * @param onComplete 滚动完成回调
   */
  public smoothScrollToPage(targetPageIndex: number, scrollSpeed: number = 1.0, onComplete?: () => void): boolean {
    if (!this.isWebtoonMode() || !this.scroller) {
      return false;
    }

    try {
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
    if (!this.isWebtoonMode() || !this.scroller) {
      return false;
    }

    try {
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
    if (!this.isWebtoonMode() || !this.scroller) {
      return false;
    }

    try {
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
    if (pageIndex < 0 || pageIndex >= this.chapter.pages.length) {
      return this.scrollPosition;
    }

    let scrollPosition = 0;
    const spacing = this.readingSettings.pageSpacing || 16;
    
    // 计算到目标页面之前的所有页面高度总和
    for (let i = 0; i < pageIndex; i++) {
      const page = this.chapter.pages[i];
      const pageHeight = this.getEstimatedImageHeight(page);
      scrollPosition += pageHeight + spacing;
    }

    // 考虑缩放比例对滚动位置的影响
    if (this.webtoonZoomScale > 1.0) {
      // 在缩放状态下，滚动到页面的顶部
      return scrollPosition * this.webtoonZoomScale;
    }

    return scrollPosition;
  }

  /**
   * 构建双页模式指示器
   */
  @Builder
  buildDoublePageIndicator() {
    Column() {
      Row() {
        Text(`${this.leftPageIndex >= 0 ? this.leftPageIndex + 1 : '-'}`)
          .fontSize(12)
          .fontColor(colorMap.textOnAccent)
          .fontWeight(FontWeight.Bold)
        
        Text(' | ')
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
        
        Text(`${this.rightPageIndex >= 0 ? this.rightPageIndex + 1 : '-'}`)
          .fontSize(12)
          .fontColor(colorMap.textOnAccent)
          .fontWeight(FontWeight.Bold)
        
        Text(' / ')
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
          .margin({ left: 4 })
        
        Text(`${this.chapter.pages.length}`)
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
      }
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
   */
  @Builder
  buildWebtoonProgressIndicator() {
    if (this.showWebtoonProgress && this.isWebtoonMode()) {
      Column() {
        // 页面信息
        Row() {
          Text(`${this.currentWebtoonPage + 1}`)
            .fontSize(14)
            .fontColor(colorMap.textOnAccent)
            .fontWeight(FontWeight.Bold)
          
          Text(' / ')
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
          
          Text(`${this.chapter.pages.length}`)
            .fontSize(12)
            .fontColor(colorMap.textSecondary)
        }
        .margin({ bottom: 4 })
        
        // 进度条
        Row() {
          Progress({
            value: this.webtoonScrollProgress * 100,
            total: 100,
            type: ProgressType.Linear
          })
            .width(120)
            .height(3)
            .color(colorMap.primary)
            .backgroundColor(colorMap.backgroundSecondary)
        }
        
        // 进度百分比
        Text(`${Math.round(this.webtoonScrollProgress * 100)}%`)
          .fontSize(10)
          .fontColor(colorMap.textSecondary)
          .margin({ top: 2 })
      }
      // .padding({ left: 12, right: 12, top: 8, bottom: 8 })
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

  /**
   * 构建条漫快速导航
   */
  @Builder
  buildWebtoonQuickNavigation() {
    if (this.isWebtoonMode() && this.chapter.pages.length > 10) {
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
              const totalPages: number = this.chapter.pages.length;
              const spacing: number = this.readingSettings.pageSpacing || 16;
              let totalHeight: number = 0;
              for (let i = 0; i < totalPages; i++) {
                const pg: MangaPage = this.chapter.pages[i];
                totalHeight += this.getEstimatedImageHeight(pg);
                if (i < totalPages - 1) { totalHeight += spacing; }
              }
              const targetPosition: number = targetProgress * totalHeight;
              this.smoothScrollTo(targetPosition);
            })
        }
        .margin({ top: 8 })
      }
      .position({ x: '95%', y: '50%' })
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
    .key(`${this.readingSettings.readingMode.toString()}_${this.viewCurrentPageIndex}_${this.leftPageIndex}_${this.rightPageIndex}_${this.renderEpoch}`)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const w: number = Number(newArea.width);
      const h: number = Number(newArea.height);
      if (w > 0) { this.screenWidth = w; }
      if (h > 0) { this.screenHeight = h; }
    })
  }
}
