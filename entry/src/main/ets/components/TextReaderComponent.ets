/**
 * 文本阅读器核心组件
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
  */

import { logger } from '../Utils/Logger';
import { curves, componentSnapshot, font, promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import measure from '@ohos.measure';
import { display } from '@kit.ArkUI';
import { KeyCode } from '@kit.InputKit';
import batteryInfo from '@ohos.batteryInfo';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  TextReaderSettings,
  TextReaderParams,
  TextReaderCallbacks,
  TextPage,
  TextChapter,
  PageMargins,
  TextReadingMode,
  TextReadingDirection,
  TextPageTurnAnimation,
  TextAlignment,
  BackgroundType,
  DEFAULT_TEXT_READER_SETTINGS
} from '../Models/TextReaderModels';
import { HighlightLineType } from '../Models/AnnotationModels';
import { PageCurlEffectV2, PageCurlConfigV2, CurlStartPosition } from './PageCurlEffectV2';
import { DualPageCurlEffect } from './DualPageCurlEffect';
import { InteractionManager, VibrationScene } from '../Framework/Managers/InteractionManager';


const TAG = 'TextReaderComponent';
const READ_ALOUD_HISTORY_HIGHLIGHT = '#334A90E2';
const READ_ALOUD_READ_HIGHLIGHT = '#CC66BB6A';
const READ_ALOUD_CURRENT_SENTENCE_HIGHLIGHT = '#CCFFCA28';
const HIGHLIGHT_POPUP_COLOR_OPTIONS: string[] = ['#E8A317', '#3B82F6', '#EF4444', '#22C55E', '#A855F7'];

/**
 * RGB颜色接口
  */
interface RGBColor {
  r: number;
  g: number;
  b: number;
}

interface SelectionRange {
  start: number;
  end: number;
}

export interface TextReaderHighlightRange {
  id: string;
  startOffset: number;
  endOffset: number;
  color: string;
  lineType?: HighlightLineType;
  quoteText?: string;
  pageIndex?: number;
  thoughtText?: string;
}

interface LocalHighlightRange {
  id: string;
  start: number;
  end: number;
  color: string;
  lineType: HighlightLineType;
  thoughtText: string;
  quoteText: string;
}

interface TextRenderSegment {
  key: string;
  text: string;
  highlighted: boolean;
  color: string;
  lineType: HighlightLineType;
  highlightId: string;
  thoughtText: string;
  quoteText: string;
}

interface CompactTextMapping {
  compactText: string;
  originIndices: number[];
}

/**
 * 分页模式枚举
  */
export enum PaginationMode {
  /** 本地文件模式：使用保守的字符估算（0.92系数） */
  LOCAL = 'LOCAL',
  /** 在线小说模式：使用更宽松的字符估算（1.0系数，让Text组件自动换行） */
  ONLINE = 'ONLINE'
}

/**
 * 文本阅读器组件
  */
@Component
export struct TextReaderComponent {
  // ========== 外部参数 ==========
  /** 文本内容 */
  @Prop @Watch('onContentChange') content: string = '';
  /** 章节列表（可选） */
  @Prop chapters: TextChapter[] = [];
  /** 阅读设置 */
  @Link @Watch('onSettingsChange') settings: TextReaderSettings;
  /** 当前章节索引 */
  @Link @Watch('onChapterIndexChange') currentChapterIndex: number;
  /** 当前页面索引 */
  @Link @Watch('onPageIndexChange') currentPageIndex: number;
  @Prop @Watch('onReadAloudCharIndexChange') readAloudCurrentCharIndex: number = -1;
  @Prop readAloudFollowEnabled: boolean = false;
  @Prop readAloudHighlightEnabled: boolean = false;
  /** 底部状态栏高度（用于避让底部信息显示区域） */
  @Prop bottomStatusBarHeight: number = 28;
  /** 分页模式：LOCAL（本地文件）或 ONLINE（在线小说） */
  @Prop paginationMode: PaginationMode = PaginationMode.LOCAL;
  @Prop enableNovelAnnotations: boolean = false;
  @Prop @Watch('onNovelHighlightRangesChange') novelHighlightRanges: TextReaderHighlightRange[] = [];
  
  // ========== 内容变化追踪 ==========
  /** 上一次的内容（用于检测变化） */
  private lastContent: string = '';
  /** 上一次的章节索引 */
  private lastChapterIndex: number = -1;
  /** 上一次的渲染设置签名（用于检测影响 PixelMap 渲染的设置变化） */
  private lastRenderSignature: string = '';
  /** 分页完成后是否跳转到最后一页（用于返回上一章节时） */
  private shouldJumpToLastPage: boolean = false;
  
  // ========== 回调函数 ==========
  onPageChange: (pageIndex: number, totalPages: number) => void = () => {};
  onPageCharRangeChange: (startCharIndex: number, endCharIndex: number) => void = () => {};
  onUserPageTurnStart: () => void = () => {};
  onChapterChange: (chapterIndex: number) => void = () => {};
  onProgressChange: (progress: number) => void = () => {};
  /** 点击中间区域回调（用于显示/隐藏工具栏） */
  onTapCenter: () => void = () => {};
  /** 分页完成回调（组件就绪） */
  onReady: () => void = () => {};
  /** 文本选择回调（用于添加净化规则等） */
  onTextSelected: (selectedText: string) => void = () => {};
  /** 添加净化规则回调 */
  onAddPurifyRule: (pattern: string) => void = () => {};
  /** 百科搜索回调 */
  onSearchEncyclopedia: (keyword: string) => void = () => {};
  /** 从指定字符位置开始听书 */
  onStartReadAloudFromCharIndex: (charIndex: number) => void = () => {};
  onAddHighlight: (selectedText: string, globalStart: number, globalEnd: number) => void = () => {};
  onAddHighlightWithThought: (selectedText: string, globalStart: number, globalEnd: number) => void = () => {};
  onAddThought: (selectedText: string, globalStart: number, globalEnd: number) => void = () => {};
  onUpdateHighlightStyle: (highlightId: string, lineType: HighlightLineType, color: string) => void = () => {};
  onUpdateHighlightThought: (highlightId: string, thoughtText: string) => void = () => {};
  
  // ========== 文本选择状态 ==========
  /** 当前选中的文本 */
  @State private selectionStart: number = -1;
  /** 当前选中的文本 */
  @State private selectionEnd: number = -1;
  /** 分页后的页面列表 */
  @State private selectedText: string = '';
  @State private showHighlightThoughtPopup: boolean = false;
  @State private highlightThoughtPopupText: string = '';
  @State private highlightThoughtPopupIsPlaceholder: boolean = false;
  @State private highlightThoughtPopupHighlightId: string = '';
  @State private highlightThoughtPopupColor: string = '#E8A317';
  @State private highlightThoughtPopupLineType: HighlightLineType = HighlightLineType.UNDERLINE;
  @State private highlightThoughtPopupQuoteText: string = '';
  @State private highlightThoughtPopupEditing: boolean = false;
  @State private highlightThoughtPopupInputText: string = '';
  @State private highlightThoughtPopupMaskOpacity: number = 0;
  @State private highlightThoughtPopupOpacity: number = 0;
  @State private highlightThoughtPopupScale: number = 0.92;
  @State private highlightThoughtPopupTranslateY: number = 10;
  @State private highlightThoughtPopupLeftVp: number = 16;
  @State private highlightThoughtPopupTopVp: number = 16;
  private highlightThoughtPopupTimer: number = -1;
  private highlightThoughtPopupHideTimer: number = -1;
  private pendingThoughtPopupTimer: number = -1;
  private pendingThoughtPopupStartOffset: number = -1;
  private pendingThoughtPopupEndOffset: number = -1;
  private pendingThoughtPopupQuoteText: string = '';
  private pendingThoughtPopupRetryCount: number = 0;
  private static readonly PENDING_THOUGHT_POPUP_MAX_RETRIES: number = 24;
  private suppressNextTapEvent: boolean = false;
  private suppressNextTapResetTimer: number = -1;
  
  // ========== 内部状态 ==========
  /** 当前显示的文本内容 */
  @State private pages: TextPage[] = [];
  /** 下一页的文本内容 */
  @State private totalPages: number = 0;
  /** 上一页的文本内容 */
  @State private currentPageContent: string = '';
  /** 上一页的文本内容 */
  @State private nextPageContent: string = '';
  /** 上一页的文本内容 */
  @State private prevPageContent: string = '';
  private scrollHighlightSegmentsCacheSignature: string = '';
  private scrollHighlightSegmentsCache: TextRenderSegment[] = [];
  
  // ========== 翻页动画状态 ==========
  @State private componentWidth: number = 0;
  @State private componentHeight: number = 0;
  @State private contentAreaWidth: number = 0;
  @State private contentAreaHeight: number = 0;
  @State private relayoutOpacity: number = 1;
  
  // ========== 卷页动画状态 ==========
  @State private isAnimating: boolean = false;
  @State private slideOffset: number = 0;
  @State private slideOpacity: number = 1;
  @State private isForward: boolean = true;
  
  // ========== 卷页动画状态 ==========
  @State private showCurlEffect: boolean = false;
  @State private curlProgress: number = 0;
  @State private currentPixelMap: image.PixelMap | null = null;
  @State private nextPixelMap: image.PixelMap | null = null;
  @State private prevPixelMap: image.PixelMap | null = null;// 上一页 PixelMap（预加载）
  @State private curlStartPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
  @State private curlTouchX: number = 0;// 卷曲触摸点X坐标
  @State private curlTouchY: number = 0;// 卷曲触摸点Y坐标
  @State private curlAnimateTarget: number = -1;// 内部动画目标进度（-1表示不使用）
  @State private curlAnimateFrom: number = 0;// 内部动画起始进度
  private curlPendingPageIndex: number = -1;// 待切换的页面索引
  private curlAnimationTimer: number = -1;// 卷页动画定时器
  private animationTimeoutTimer: number = -1;// 动画超时保护定时器
  private static readonly ANIMATION_TIMEOUT_MS: number = 3000;// 动画超时时间(3秒)
  private pagePixelMapCache: Map<number, image.PixelMap> = new Map();// 页面 PixelMap 缓存
  private isGeneratingPixelMap: boolean = false;// 是否正在生成 PixelMap
  private panStartTime: number = 0;// 拖拽起始时间戳（用于快速翻页速度检测）
  // 小说专用卷页配置：针对全屏场景优化动画曲线
  private novelCurlConfig: PageCurlConfigV2 = {
    stripCount: 24,
    maxCurlHeight: 120,
    shadowIntensity: 0.5,
    animationDuration: 350,// 全屏页面较大，动画时长稍长以保证流畅感
    enableShadow: true,
    enableHighlight: true,
    flipThreshold: 0.28// 全屏场景降低阈值，更容易触发翻页
  };
  private isPaginating: boolean = false;// 是否正在分页
  private paginationVersion: number = 0;// 分页版本号，用于取消旧的分页任务
  private paginationRetryCount: number = 0;// 分页重试次数
  private static readonly MAX_PAGINATION_RETRIES: number = 10;// 最大分页重试次数
  private areaChangeDebounceTimer: number = -1;// onAreaChange防抖定时器
  private static readonly AREA_CHANGE_DEBOUNCE_MS: number = 100;// 防抖时间(100ms)
  private settingsRepaginateDebounceTimer: number = -1;
  private static readonly SETTINGS_REPAGINATE_DEBOUNCE_MS: number = 60;
  private static readonly MIN_CONTENT_WIDTH_VP: number = 120;
  private static readonly MIN_CONTENT_LINE_COUNT: number = 2;
  private lastContentAreaWidth: number = 0;// 上次内容区域宽度
  private lastContentAreaHeight: number = 0;// 上次内容区域高度
  private lastPaginationSignature: string = '';
  private pendingAnchorCharIndex: number = -1;
  private pendingRelayoutAnimation: boolean = false;
  private lastReadAloudHighlightLogTime: number = 0;
  private lastReadAloudScrollFollowTime: number = 0;
  @State private isLoading: boolean = false;// 加载状态
  
  // ========== 手势状态 ==========
  @State private isChapterTransition: boolean = false;// 是否正在章节过渡
  @State private transitionChapterName: string = '';     // 过渡显示的章节名
  @State private transitionDirection: boolean = true;// true=下一章, false=上一章
  
  // ========== 滚动模式状态 ==========
  @State private touchStartX: number = 0;
  @State private touchStartY: number = 0;
  @State private isDragging: boolean = false;
  private initialTouchX: number = 0;// 初始触摸X坐标（用于卷页拖拽）
  
  // ========== 滚动模式状态 ==========
  private scrollController: Scroller = new Scroller();
  @State private scrollOffset: number = 0;
  private autoPageTurnTimer: number = -1;
  private autoPageTurnBusy: boolean = false;
  private isAutoScrollStepInProgress: boolean = false;
  private autoScrollStepGuardTimer: number = -1;
  private static readonly AUTO_SCROLL_STEP_RATIO: number = 0.85;
  private static readonly AUTO_SCROLL_MIN_STEP_VP: number = 120;
  private static readonly AUTO_SCROLL_MAX_STEP_VP: number = 720;
  private static readonly AUTO_SCROLL_END_THRESHOLD_VP: number = 36;
  private static readonly READ_ALOUD_SCROLL_FOLLOW_INTERVAL_MS: number = 380;
  private static readonly READ_ALOUD_SCROLL_FOLLOW_MIN_DELTA_VP: number = 36;
  
  // ========== 音量键翻页状态 ==========
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  
  // ========== 时间和电量显示状态 ==========
  // ========== 时间和电量显示状态 ==========
  
  // ========== 双页模式状态 ==========
  @State private currentTime: string = '';
  @State private batteryLevel: number = 0;
  private timeUpdateInterval: number = -1;
  
  // ========== 双页模式状态 ==========
  /** 双页模式左页索引 */
  @State private dualLeftPageContent: string = '';
  /** 双页模式右页索引 */
  @State private dualRightPageContent: string = '';
  /** 双页模式当前展开页基础索引（始终为偶数） */
  @State private dualLeftPageIndex: number = 0;
  /** 双页模式当前展开页基础索引（始终为偶数） */
  @State private dualRightPageIndex: number = 1;
  /** 双页模式翻页动画作用侧：'left' 或 'right' */
  private dualPageBaseIndex: number = 0;
  // ========== 双页卷页动画 PixelMap ==========
  @State private dualCurlLeftPM: image.PixelMap | null = null;
  @State private dualCurlRightPM: image.PixelMap | null = null;
  @State private dualCurlNextLeftPM: image.PixelMap | null = null;
  @State private dualCurlNextRightPM: image.PixelMap | null = null;
  /** 双页模式翻页动画下方页面内容（左侧） */
  @State private dualAnimSide: string = 'right';
  /** 双页模式翻页动画下方页面内容（右侧） */
  @State private dualSlideOffset: number = 0;
  /** 双页卷页动画定时器（父组件驱动模式） */
  @State private dualUnderLeftContent: string = '';
  /** 双页卷页动画定时器（父组件驱动模式） */
  @State private dualUnderRightContent: string = '';
  /** 双页卷页动画定时器（父组件驱动模式） */
  private dualCurlAnimTimer: number = -1;
  
    // 注册自定义字体（如果有）
  aboutToAppear(): void {
    logger.info(TAG, '文本阅读器组件初始化');
    // 获取电量
    this.registerCustomFontIfNeeded();
    // 记录初始内容和章节索引
    this.startTimeUpdate();
    // 记录初始内容和章节索引
    this.updateBatteryLevel();
    // 记录初始内容和章节索引
    this.lastContent = this.content;
    this.lastChapterIndex = this.currentChapterIndex;
    this.syncAutoPageTurnState('component-appear');
  }
  
  /**
  * 注册自定义字体（如果设置了fontPath）
  */
  private registerCustomFontIfNeeded(): void {
    // 防御性检查：确保textStyle对象存在
    if (!this.settings?.textStyle) {
      return;
    }
    const fontPath = this.settings.textStyle.fontPath;
    if (fontPath && fontPath.length > 0) {
      try {
        const fontUri = fontPath.startsWith('file://') ? fontPath : `file://${fontPath}`;
        font.registerFont({
          familyName: this.settings.textStyle.fontFamily,
          familySrc: fontUri
        });
        logger.info(TAG, `自定义字体已注册: ${this.settings.textStyle.fontFamily}, 路径: ${fontUri}`);
      } catch (error) {
        logger.warn(TAG, `注册自定义字体失败: ${String(error)}`);
      }
    }
  }
  
  /**
  * 内容变化回调
  * 当外部传入的 content 变化时触发重新分页
  */
  private onContentChange(): void {
    if (this.content !== this.lastContent) {
      logger.info(TAG, `内容变化，重新分页。旧长度: ${this.lastContent.length}, 新长度: ${this.content.length}`);
      this.lastContent = this.content;
      
      // 清空旧的页面数据和缓存，避免访问旧数据导致崩溃
      const preservedPageIndex = Math.max(0, Math.floor(this.currentPageIndex));
      this.lastExternalPageIndex = preservedPageIndex;
      
      // 清空 PixelMap 缓存
      this.pages = [];
      this.totalPages = 0;
      this.currentPageContent = '';
      this.prevPageContent = '';
      this.nextPageContent = '';
      
      // 清空 PixelMap 缓存
      this.releaseAllPixelMapCache();
      this.currentPixelMap = null;
      this.nextPixelMap = null;
      this.prevPixelMap = null;
      this.dualCurlLeftPM = null;
      this.dualCurlRightPM = null;
      this.dualCurlNextLeftPM = null;
      this.dualCurlNextRightPM = null;
      
      // 异步分页
      this.stopCurlAnimation();
      this.isAnimating = false;
      this.showCurlEffect = false;
      this.clearAutoPageTurnTimer();
      
      // 异步分页
      this.paginateContentAsync();
    }
  }
  
  /**
  * 异步分页，避免阻塞主线程
  */
  private paginateContentAsync(): void {
    // 如果已经在分页，记录日志并等待下一帧
    this.paginationVersion++;
    const currentVersion = this.paginationVersion;
    
    // 显示加载状态
    if (this.isPaginating) {
      logger.info(TAG, `分页任务已在运行，新任务将取消旧任务`);
    }
    
    // 检查内容是否有效
    this.isLoading = true;
    
    // 检查组件尺寸是否有效
    if (!this.content || this.content.length === 0) {
      this.isLoading = false;
      this.finishPendingRelayoutIfNeeded();
      return;
    }
    
    // 检查组件尺寸是否有效
    if (this.contentAreaWidth <= 0 || this.contentAreaHeight <= 0) {
      this.paginationRetryCount++;
      if (this.paginationRetryCount > TextReaderComponent.MAX_PAGINATION_RETRIES) {
        logger.error(TAG, `分页重试次数超过限制(${TextReaderComponent.MAX_PAGINATION_RETRIES})，停止重试`);
        this.isLoading = false;
        this.paginationRetryCount = 0;
        this.finishPendingRelayoutIfNeeded();
        return;
      }
      logger.info(TAG, `组件尺寸未初始化，延迟分页(重试${this.paginationRetryCount}/${TextReaderComponent.MAX_PAGINATION_RETRIES})`);
      // 延迟重试，等待组件尺寸初始化
      setTimeout(() => {
        if (currentVersion === this.paginationVersion) {
          this.paginateContentAsync();
        }
      }, 100);
      return;
    }
    
    // 使用 setTimeout 延迟执行，让 UI 有机会更新
    this.paginationRetryCount = 0;
    
      // 检查版本号，如果不匹配则取消
    setTimeout(() => {
      // 检查版本号，如果不匹配则取消
      if (currentVersion !== this.paginationVersion) {
        logger.info(TAG, `分页任务已过期，取消`);
        return;
      }
      
      try {
        this.isPaginating = true;
        this.paginateContent();
      } catch (error) {
        logger.error(TAG, `分页失败: ${error instanceof Error ? error.message : String(error)}`);
      } finally {
        this.isPaginating = false;
        this.isLoading = false;
      }
      
          // 双页模式：跳转到最后一对页面（偶数索引）
      if (this.shouldJumpToLastPage && this.totalPages > 0) {
        if (this.isDualPageMode()) {
          // 双页模式：跳转到最后一对页面（偶数索引）
          this.dualPageBaseIndex = this.totalPages - 1 - ((this.totalPages - 1) % 2);
          this.currentPageIndex = this.dualPageBaseIndex;
        } else {
          this.currentPageIndex = this.totalPages - 1;
        }
        this.lastExternalPageIndex = this.currentPageIndex;
        this.shouldJumpToLastPage = false;
        this.pendingAnchorCharIndex = -1;
        logger.info(TAG, `分页完成，跳转到最后一页: ${this.currentPageIndex + 1}/${this.totalPages}`);
      }

      this.restorePageIndexByAnchor();
      
      // 每次分页完成都更新签名，确保与当前设置同步
      this.updatePageContents();
      
      // 通知页面变化（确保进度正确保存）
      this.lastRenderSignature = this.getRenderSignature();
      this.lastPaginationSignature = this.getPaginationSignature();
      
      // 通知分页完成
      this.notifyPageChange();
      
      // 通知分页完成
      this.onReady();
      this.finishPendingRelayoutIfNeeded();
    }, 50);// 延迟 50ms 让 UI 有机会更新
  }
  
  /**
  * 章节索引变化回调
  * 当外部传入的 currentChapterIndex 变化时触发
  */
  private onChapterIndexChange(): void {
    if (this.currentChapterIndex !== this.lastChapterIndex) {
      logger.info(TAG, `章节索引变化: ${this.lastChapterIndex} -> ${this.currentChapterIndex}`);
      this.lastChapterIndex = this.currentChapterIndex;
      this.clearAutoPageTurnTimer();
      // 章节变化时，页码会在 onContentChange 中重置
    }
  }

  private onSettingsChange(): void {
    this.syncAutoPageTurnState('settings-change');
    this.checkAndInvalidatePixelMapCache();
    this.stopCurlAnimation();

    const nextSignature = this.getPaginationSignature();
    if (this.lastPaginationSignature.length === 0) {
      this.lastPaginationSignature = nextSignature;
      return;
    }
    if (nextSignature === this.lastPaginationSignature) {
      return;
    }

    if (this.settingsRepaginateDebounceTimer !== -1) {
      clearTimeout(this.settingsRepaginateDebounceTimer);
    }
    this.settingsRepaginateDebounceTimer = setTimeout(() => {
      this.settingsRepaginateDebounceTimer = -1;
      if (!this.content || this.content.length === 0) {
        return;
      }

      this.pendingAnchorCharIndex = this.getCurrentAnchorCharIndex();
      this.pendingRelayoutAnimation = true;
      this.startRelayoutAnimation();
      this.recalculateContentArea();
      this.releaseAllPixelMapCache();
      this.paginateContentAsync();
    }, TextReaderComponent.SETTINGS_REPAGINATE_DEBOUNCE_MS);
  }

  private getPaginationSignature(): string {
    const ts = this.settings.textStyle;
    const pm = this.getEffectivePageMargins();
    return `${this.settings.readingMode}|${this.settings.readingDirection}|${ts.fontSize}|${ts.lineHeight}|` +
      `${ts.letterSpacing}|${ts.paragraphSpacing}|${ts.firstLineIndent}|${pm.top}|${pm.bottom}|${pm.left}|${pm.right}|` +
      `${this.getEffectiveBottomBarHeight()}|${this.componentWidth}|${this.componentHeight}`;
  }

  private getCurrentAnchorCharIndex(): number {
    if (this.pages.length === 0) {
      return -1;
    }
    const safeIndex = Math.max(0, Math.min(this.currentPageIndex, this.pages.length - 1));
    const page = this.pages[safeIndex];
    if (!page) {
      return -1;
    }
    return Math.max(0, page.startCharIndex);
  }

  private findPageIndexByCharIndex(charIndex: number): number {
    if (this.pages.length === 0 || charIndex <= 0) {
      return 0;
    }
    for (let i = 0; i < this.pages.length; i++) {
      const page = this.pages[i];
      if (charIndex >= page.startCharIndex && charIndex < page.endCharIndex) {
        return i;
      }
    }
    return this.pages.length - 1;
  }

  private restorePageIndexByAnchor(): void {
    if (this.pendingAnchorCharIndex < 0 || this.pages.length === 0) {
      return;
    }
    const targetIndex = this.findPageIndexByCharIndex(this.pendingAnchorCharIndex);
    this.pendingAnchorCharIndex = -1;

    if (this.isDualPageMode()) {
      const safeTarget = Math.max(0, Math.min(targetIndex, this.pages.length - 1));
      this.dualPageBaseIndex = safeTarget - (safeTarget % 2);
      this.currentPageIndex = this.dualPageBaseIndex;
    } else {
      this.currentPageIndex = Math.max(0, Math.min(targetIndex, this.pages.length - 1));
    }
    this.lastExternalPageIndex = this.currentPageIndex;
  }

  private startRelayoutAnimation(): void {
    if (this.showCurlEffect || this.isAnimating || this.isChapterTransition) {
      this.relayoutOpacity = 1;
      return;
    }
    animateTo({
      duration: 90,
      curve: Curve.EaseOut
    }, () => {
      this.relayoutOpacity = 0.9;
    });
  }

  private finishRelayoutAnimation(): void {
    animateTo({
      duration: 120,
      curve: Curve.EaseIn
    }, () => {
      this.relayoutOpacity = 1;
    });
  }

  private finishPendingRelayoutIfNeeded(): void {
    if (!this.pendingRelayoutAnimation) {
      return;
    }
    this.pendingRelayoutAnimation = false;
    this.finishRelayoutAnimation();
  }

  private getEffectivePageMargins(): PageMargins {
    const defaultMargins = DEFAULT_TEXT_READER_SETTINGS.pageMargins;
    const baseMargins = this.settings.pageMargins ?? defaultMargins;
    const safeMargins: PageMargins = {
      top: Math.max(0, Math.round(Number(baseMargins.top) || 0)),
      bottom: Math.max(0, Math.round(Number(baseMargins.bottom) || 0)),
      left: Math.max(0, Math.round(Number(baseMargins.left) || 0)),
      right: Math.max(0, Math.round(Number(baseMargins.right) || 0))
    };

    const baseWidth = this.isDualPageMode() ? Math.floor(this.componentWidth / 2) : this.componentWidth;
    const baseHeight = this.componentHeight;
    if (baseWidth <= 0 || baseHeight <= 0) {
      return safeMargins;
    }

    const minContentWidth = Math.min(
      TextReaderComponent.MIN_CONTENT_WIDTH_VP,
      Math.max(48, baseWidth - 16)
    );
    const maxHorizontalMargins = Math.max(0, baseWidth - minContentWidth);
    const totalHorizontalMargins = safeMargins.left + safeMargins.right;
    if (totalHorizontalMargins > maxHorizontalMargins && totalHorizontalMargins > 0) {
      const ratio = maxHorizontalMargins / totalHorizontalMargins;
      safeMargins.left = Math.floor(safeMargins.left * ratio);
      safeMargins.right = Math.floor(safeMargins.right * ratio);
    }

    const bottomBarHeight = this.getEffectiveBottomBarHeight();
    const lineHeightVp = this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight;
    const minContentHeight = Math.max(
      lineHeightVp * TextReaderComponent.MIN_CONTENT_LINE_COUNT,
      lineHeightVp
    );
    const maxVerticalMargins = Math.max(0, baseHeight - bottomBarHeight - minContentHeight);
    const totalVerticalMargins = safeMargins.top + safeMargins.bottom;
    if (totalVerticalMargins > maxVerticalMargins && totalVerticalMargins > 0) {
      const ratio = maxVerticalMargins / totalVerticalMargins;
      safeMargins.top = Math.floor(safeMargins.top * ratio);
      safeMargins.bottom = Math.floor(safeMargins.bottom * ratio);
    }

    return safeMargins;
  }

  private recalculateContentArea(): boolean {
    const baseWidth = this.isDualPageMode() ? Math.floor(this.componentWidth / 2) : this.componentWidth;
    if (baseWidth <= 0 || this.componentHeight <= 0) {
      return false;
    }

    const pageMargins = this.getEffectivePageMargins();
    const bottomBarHeight = this.getEffectiveBottomBarHeight();
    const newContentWidth = Math.max(1, baseWidth - pageMargins.left - pageMargins.right);
    const newContentHeight = Math.max(1, this.componentHeight - pageMargins.top - pageMargins.bottom - bottomBarHeight);

    const widthChanged = Math.abs(newContentWidth - this.lastContentAreaWidth) > 1;
    const heightChanged = Math.abs(newContentHeight - this.lastContentAreaHeight) > 1;
    if (!widthChanged && !heightChanged) {
      return false;
    }

    this.contentAreaWidth = newContentWidth;
    this.contentAreaHeight = newContentHeight;
    this.lastContentAreaWidth = newContentWidth;
    this.lastContentAreaHeight = newContentHeight;
    logger.debug(TAG, `内容区域变化: ${this.contentAreaWidth.toFixed(0)}x${this.contentAreaHeight.toFixed(0)}`);
    return true;
  }

  private getEffectiveContentPadding(): PageMargins {
    const pageMargins = this.getEffectivePageMargins();
    const padding: PageMargins = {
      top: pageMargins.top,
      bottom: pageMargins.bottom + this.getEffectiveBottomBarHeight(),
      left: pageMargins.left,
      right: pageMargins.right
    };
    return padding;
  }

  /**
  * 当上下边距都为0时，轻度收紧文本行高，减少首尾行盒留白的视觉空隙
  */
  private getEffectiveTextLineHeight(): number {
    const fontSize = this.settings.textStyle.fontSize;
    const baseLineHeight = fontSize * this.settings.textStyle.lineHeight;
    const pageMargins = this.settings.pageMargins;
    if (!pageMargins) {
      return baseLineHeight;
    }

    const top = Math.max(0, Math.round(Number(pageMargins.top) || 0));
    const bottom = Math.max(0, Math.round(Number(pageMargins.bottom) || 0));
    if (top > 0 || bottom > 0) {
      return baseLineHeight;
    }

    const extraLeading = Math.max(0, baseLineHeight - fontSize);
    const trim = Math.min(extraLeading, fontSize * 0.28);
    const minLineHeight = fontSize * 1.12;
    return Math.max(minLineHeight, baseLineHeight - trim);
  }

  private isAutoPageTurnActive(): boolean {
    if (this.settings.autoPageTurnEnabled !== true) {
      return false;
    }
    return this.getAutoPageTurnIntervalMs() > 0;
  }

  private getAutoPageTurnIntervalMs(): number {
    const rawInterval = this.settings.autoPageTurnInterval;
    if (typeof rawInterval !== 'number' || rawInterval <= 0) {
      return 8000;
    }
    const seconds = Math.max(1, Math.min(60, Math.round(rawInterval)));
    return seconds * 1000;
  }

  private clearAutoPageTurnTimer(): void {
    if (this.autoPageTurnTimer !== -1) {
      clearTimeout(this.autoPageTurnTimer);
      this.autoPageTurnTimer = -1;
    }
  }

  private clearAutoScrollStepGuard(): void {
    if (this.autoScrollStepGuardTimer !== -1) {
      clearTimeout(this.autoScrollStepGuardTimer);
      this.autoScrollStepGuardTimer = -1;
    }
    this.isAutoScrollStepInProgress = false;
  }

  private syncAutoPageTurnState(reason: string): void {
    if (!this.isAutoPageTurnActive()) {
      this.clearAutoPageTurnTimer();
      return;
    }
    this.scheduleAutoPageTurnTimer(reason);
  }

  private scheduleAutoPageTurnTimer(reason: string): void {
    this.clearAutoPageTurnTimer();
    if (!this.isAutoPageTurnActive()) {
      return;
    }
    const intervalMs = this.getAutoPageTurnIntervalMs();
    this.autoPageTurnTimer = setTimeout(() => {
      this.autoPageTurnTimer = -1;
      this.handleAutoPageTurnTick();
    }, intervalMs);
    logger.debug(TAG, `autoPageTurn scheduled: reason=${reason}, interval=${intervalMs}ms`);
  }

  private resetAutoPageTurnTimerForInteraction(reason: string): void {
    if (!this.isAutoPageTurnActive()) {
      return;
    }
    this.scheduleAutoPageTurnTimer(`interaction:${reason}`);
  }

  private trySwitchToNextChapterForAuto(): boolean {
    if (this.chapters.length > 0 && this.currentChapterIndex < this.chapters.length - 1) {
      this.switchToNextChapter();
      return true;
    }
    return false;
  }

  private getCurrentScrollOffsetY(): number {
    try {
      const offset = this.scrollController.currentOffset();
      if (offset && typeof offset.yOffset === 'number' && Number.isFinite(offset.yOffset)) {
        return Math.max(0, offset.yOffset);
      }
    } catch (_error) {
      // ignore
    }
    return Math.max(0, this.scrollOffset);
  }

  private getEstimatedScrollEndOffsetY(): number {
    const pageHeight = Math.max(1, this.contentAreaHeight);
    return Math.max(0, (this.totalPages - 1) * pageHeight);
  }

  private getAutoScrollStepDistance(): number {
    const baseDistance = this.contentAreaHeight * TextReaderComponent.AUTO_SCROLL_STEP_RATIO;
    return Math.max(
      TextReaderComponent.AUTO_SCROLL_MIN_STEP_VP,
      Math.min(TextReaderComponent.AUTO_SCROLL_MAX_STEP_VP, baseDistance)
    );
  }

  private getAutoScrollAnimationDurationMs(): number {
    const intervalMs = this.getAutoPageTurnIntervalMs();
    return Math.max(180, Math.min(1200, intervalMs - 120));
  }

  private markAutoScrollStepInProgress(durationMs: number): void {
    this.isAutoScrollStepInProgress = true;
    this.clearAutoScrollStepGuard();
    const guardDuration = Math.max(220, durationMs + 80);
    this.autoScrollStepGuardTimer = setTimeout(() => {
      this.isAutoScrollStepInProgress = false;
      this.autoScrollStepGuardTimer = -1;
    }, guardDuration);
  }

  private performAutoScrollStep(): 'continue' | 'chapter-switch' | 'end' {
    const currentOffsetY = this.getCurrentScrollOffsetY();
    const stepDistance = this.getAutoScrollStepDistance();
    const targetOffsetY = currentOffsetY + stepDistance;
    const estimatedEndY = this.getEstimatedScrollEndOffsetY();
    const endThreshold = Math.max(TextReaderComponent.AUTO_SCROLL_END_THRESHOLD_VP, stepDistance * 0.2);

    if (estimatedEndY <= TextReaderComponent.AUTO_SCROLL_END_THRESHOLD_VP) {
      if (this.trySwitchToNextChapterForAuto()) {
        return 'chapter-switch';
      }
      logger.info(TAG, 'autoPageTurn reached end of book in scroll mode');
      this.clearAutoPageTurnTimer();
      return 'end';
    }

    if (estimatedEndY > 0 && targetOffsetY >= estimatedEndY - endThreshold) {
      if (this.trySwitchToNextChapterForAuto()) {
        return 'chapter-switch';
      }
      logger.info(TAG, 'autoPageTurn reached end of book in scroll mode');
      this.clearAutoPageTurnTimer();
      return 'end';
    }

    const animationDuration = this.getAutoScrollAnimationDurationMs();
    this.markAutoScrollStepInProgress(animationDuration);
    try {
      this.scrollController.scrollTo({
        xOffset: 0,
        yOffset: targetOffsetY,
        animation: { duration: animationDuration }
      });
    } catch (error) {
      logger.warn(TAG, `auto scroll failed: ${String(error)}`);
      this.clearAutoScrollStepGuard();
    }
    return 'continue';
  }

  private handleAutoPageTurnTick(): void {
    if (!this.isAutoPageTurnActive()) {
      this.clearAutoPageTurnTimer();
      return;
    }

    if (this.autoPageTurnBusy) {
      this.scheduleAutoPageTurnTimer('tick-busy');
      return;
    }

    if (this.isPaginating || this.isLoading || this.isAnimating || this.isChapterTransition) {
      this.scheduleAutoPageTurnTimer('reader-busy');
      return;
    }

    if (this.totalPages <= 0) {
      this.scheduleAutoPageTurnTimer('no-pages');
      return;
    }

    this.autoPageTurnBusy = true;
    try {
      if (this.settings.readingMode === TextReadingMode.SCROLL) {
        const scrollResult = this.performAutoScrollStep();
        if (scrollResult === 'continue') {
          this.scheduleAutoPageTurnTimer('auto-scroll-step');
        }
        return;
      }

      if (this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
        const nextBase = this.dualPageBaseIndex + 2;
        if (nextBase < this.totalPages) {
          this.goToNextDualPage('auto_page_turn');
        } else if (!this.trySwitchToNextChapterForAuto()) {
          logger.info(TAG, 'autoPageTurn reached end of book in dual-page mode');
          this.clearAutoPageTurnTimer();
        }
        return;
      }

      if (this.currentPageIndex < this.totalPages - 1) {
        this.goToNextPage('auto_page_turn');
      } else if (!this.trySwitchToNextChapterForAuto()) {
        logger.info(TAG, 'autoPageTurn reached end of book in page mode');
        this.clearAutoPageTurnTimer();
      }
    } finally {
      this.autoPageTurnBusy = false;
    }
  }

  /**
  * 页面索引变化回调（用于外部触发翻页，如音量键翻页）
  * 当外部传入的 currentPageIndex 变化时触发
  */
  private lastExternalPageIndex: number = -1;
  private onPageIndexChange(): void {
    if (this.lastExternalPageIndex === this.currentPageIndex) {
      return;
    }

    if (this.isAnimating || this.showCurlEffect) {
      logger.debug(TAG, `外部页面索引变化被跳过（动画中）: ${this.lastExternalPageIndex} -> ${this.currentPageIndex}`);
      return;
    }

    // Keep external index untouched before pagination is ready.
    if (this.totalPages <= 0) {
      this.lastExternalPageIndex = this.currentPageIndex;
      return;
    }

    const safeIndex = Math.max(0, Math.min(this.currentPageIndex, this.totalPages - 1));
    if (safeIndex !== this.currentPageIndex) {
      this.currentPageIndex = safeIndex;
    }

    logger.info(TAG, `外部页面索引变化: ${this.lastExternalPageIndex} -> ${this.currentPageIndex}, totalPages=${this.totalPages}`);
    this.lastExternalPageIndex = this.currentPageIndex;
    this.updatePageContents();
    this.notifyPageChange();
  }

  private onReadAloudCharIndexChange(): void {
    this.tryFollowPageForReadAloud();
    if (!this.readAloudHighlightEnabled || this.readAloudCurrentCharIndex < 0) {
      return;
    }
    const now = Date.now();
    if ((now - this.lastReadAloudHighlightLogTime) < 1200) {
      return;
    }
    this.lastReadAloudHighlightLogTime = now;
    logger.debug(
      TAG,
      `听书高亮定位: page=${this.currentPageIndex + 1}/${this.totalPages}, char=${this.readAloudCurrentCharIndex}`
    );
  }

  private onNovelHighlightRangesChange(): void {
    this.scrollHighlightSegmentsCacheSignature = '';
    this.scrollHighlightSegmentsCache = [];
    this.tryPresentPendingThoughtPopup('highlight_ranges_change');
  }

  private tryFollowPageForReadAloud(): void {
    if (!this.readAloudFollowEnabled) {
      return;
    }
    if (this.readAloudCurrentCharIndex < 0) {
      return;
    }
    if (this.settings.readingMode === TextReadingMode.SCROLL) {
      this.tryFollowScrollForReadAloud();
      return;
    }
    if (this.pages.length === 0 || this.totalPages <= 0) {
      return;
    }
    if (this.isAnimating || this.showCurlEffect || this.isPaginating || this.isLoading) {
      return;
    }

    const dualMode = this.isDualPageMode();
    const targetPageIndex = this.findPageIndexByCharIndex(this.readAloudCurrentCharIndex);
    let safeTargetPageIndex = Math.max(0, Math.min(targetPageIndex, this.totalPages - 1));
    if (dualMode) {
      safeTargetPageIndex = safeTargetPageIndex - (safeTargetPageIndex % 2);
    }

    const currentEffectivePageIndex = dualMode ? this.dualPageBaseIndex : this.currentPageIndex;
    if (safeTargetPageIndex === currentEffectivePageIndex) {
      return;
    }

    if (!dualMode && Math.abs(safeTargetPageIndex - currentEffectivePageIndex) === 1) {
      if (safeTargetPageIndex > currentEffectivePageIndex) {
        this.goToNextPage('read_aloud_follow');
      } else {
        this.goToPrevPage('read_aloud_follow');
      }
      return;
    }

    this.goToPage(safeTargetPageIndex, 'read_aloud_follow');
  }

  private tryFollowScrollForReadAloud(): void {
    if (this.content.length <= 0 || this.contentAreaHeight <= 0) {
      return;
    }
    const now = Date.now();
    if ((now - this.lastReadAloudScrollFollowTime) < TextReaderComponent.READ_ALOUD_SCROLL_FOLLOW_INTERVAL_MS) {
      return;
    }

    const estimatedEndY = this.getEstimatedScrollEndOffsetY();
    if (estimatedEndY <= 0) {
      return;
    }

    const currentOffsetY = this.getCurrentScrollOffsetY();
    const ratio = Math.max(0, Math.min(1, this.readAloudCurrentCharIndex / Math.max(1, this.content.length)));
    const targetOffsetY = Math.max(0, Math.min(estimatedEndY, Math.floor(estimatedEndY * ratio)));
    const minDelta = Math.max(
      TextReaderComponent.READ_ALOUD_SCROLL_FOLLOW_MIN_DELTA_VP,
      Math.floor(this.contentAreaHeight * 0.08)
    );
    if (Math.abs(targetOffsetY - currentOffsetY) < minDelta) {
      return;
    }

    this.lastReadAloudScrollFollowTime = now;
    try {
      this.scrollController.scrollTo({
        xOffset: 0,
        yOffset: targetOffsetY,
        animation: { duration: 260 }
      });
    } catch (error) {
      logger.debug(TAG, `听书滚动跟随失败: ${String(error)}`);
    }
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, '文本阅读器组件销毁');
    this.releaseAllPixelMapCache();
    this.stopCurlAnimation();
    // 清理防抖定时器
    this.stopTimeUpdate();
    // 清理防抖定时器
    this.clearAnimationTimeout();
    // 清理防抖定时器
    if (this.areaChangeDebounceTimer !== -1) {
      clearTimeout(this.areaChangeDebounceTimer);
      this.areaChangeDebounceTimer = -1;
    }
    if (this.settingsRepaginateDebounceTimer !== -1) {
      clearTimeout(this.settingsRepaginateDebounceTimer);
      this.settingsRepaginateDebounceTimer = -1;
    }
    this.clearAutoPageTurnTimer();
    this.clearAutoScrollStepGuard();
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    if (this.highlightThoughtPopupHideTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupHideTimer);
      this.highlightThoughtPopupHideTimer = -1;
    }
    this.clearPendingThoughtPopupRequest();
    if (this.suppressNextTapResetTimer !== -1) {
      clearTimeout(this.suppressNextTapResetTimer);
      this.suppressNextTapResetTimer = -1;
    }
    this.suppressNextTapEvent = false;
    this.pendingAnchorCharIndex = -1;
    this.pendingRelayoutAnimation = false;
    this.relayoutOpacity = 1;
  }
  
  /**
   * 启动动画超时保护
   * 如果动画在指定时间内未完成，强制重置动画状态
   */
  private startAnimationTimeout(): void {
    this.clearAnimationTimeout();
    this.animationTimeoutTimer = setTimeout(() => {
      if (this.isAnimating) {
        logger.warn(TAG, `动画超时(${TextReaderComponent.ANIMATION_TIMEOUT_MS}ms)，强制重置动画状态`);
        this.forceResetAnimationState();
      }
    }, TextReaderComponent.ANIMATION_TIMEOUT_MS);
  }
  
  /**
   * 清理动画超时定时器
   */
  private clearAnimationTimeout(): void {
    if (this.animationTimeoutTimer !== -1) {
      clearTimeout(this.animationTimeoutTimer);
      this.animationTimeoutTimer = -1;
    }
  }
  
  /**
  * 强制重置所有动画状态
  */
  private forceResetAnimationState(): void {
    this.isAnimating = false;
    this.showCurlEffect = false;
    this.isChapterTransition = false;
    this.slideOffset = 0;
    this.slideOpacity = 1;
    this.curlProgress = 0;
    this.curlAnimateTarget = -1;
    this.isDragging = false;
    this.dualSlideOffset = 0;
    this.clearAnimationTimeout();
    logger.info(TAG, '动画状态已强制重置');
  }
  
  /**
  * 提供边界反馈（已到达第一页或最后一页时）
  */
  private provideBoundaryFeedback(): void {
    try {
      // 震动失败不影响正常使用
      InteractionManager.getInstance().vibrate(VibrationScene.WARNING);
    } catch (error) {
      // 震动失败不影响正常使用
      logger.debug(TAG, `边界反馈失败: ${String(error)}`);
    }
  }
  
  /**
  * 启动时间更新定时器
  */
  private startTimeUpdate(): void {
    this.updateCurrentTime();
    this.timeUpdateInterval = setInterval(() => {
      this.updateCurrentTime();
      this.updateBatteryLevel();
    }, 30000);// 每30秒更新一次
  }
  
  /**
  * 停止时间更新
  */
  private stopTimeUpdate(): void {
    if (this.timeUpdateInterval !== -1) {
      clearInterval(this.timeUpdateInterval);
      this.timeUpdateInterval = -1;
    }
  }
  
  /**
  * 更新当前时间
  */
  private updateCurrentTime(): void {
    const now = new Date();
    const hours = now.getHours().toString().padStart(2, '0');
    const minutes = now.getMinutes().toString().padStart(2, '0');
    this.currentTime = `${hours}:${minutes}`;
  }
  
  /**
  * 更新电量
  */
  private updateBatteryLevel(): void {
    try {
      this.batteryLevel = batteryInfo.batterySOC;
    } catch (error) {
      logger.error(TAG, `获取电量失败: ${JSON.stringify(error)}`);
      this.batteryLevel = 100;
    }
  }
  
  /**
  * 根据电量获取电池颜色（起始色）
  * 高电量：绿色，中电量：黄绿色，低电量：红色
  */
  private getBatteryColor(level: number): string {
    if (level > 60) {
      return '#FFC107';  // 黄色
    } else if (level > 40) {
      return '#FF5722';  // 橙红色
    } else if (level > 20) {
      return '#FF5722';  // 橙红色
    } else {
      return '#FF5722';  // 橙红色
    }
  }
  
  /**
  * 根据电量获取电池颜色（结束色，用于渐变）
  */
  private getBatteryColorEnd(level: number): string {
    if (level > 60) {
      return '#FFD54F';  // 浅黄色
    } else if (level > 40) {
      return '#FF8A65';  // 浅橙色
    } else if (level > 20) {
      return '#FF8A65';  // 浅橙色
    } else {
      return '#FF8A65';  // 浅橙色
    }
  }
  
  /**
  * 处理音量键翻页（通过组件级 onKeyEvent 调用）
  * @param keyCode 按键码
  * @returns 是否消费了该按键事件
  */
  private handleVolumeKeyPageTurn(keyCode: number): boolean {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, '已屏蔽音量键翻页: 划线悬浮窗显示中');
      return true;
    }
    if (!this.settings.volumeKeyNavigation) {
      return false;
    }
    
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP) {
      logger.info(TAG, 'Volume key page turn: previous page');
      if (this.isDualPageMode()) {
        this.goToPrevDualPage();
      } else {
        this.goToPrevPage();
      }
      this.resetAutoPageTurnTimerForInteraction('volume-key');
      return true;
    } else if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      logger.info(TAG, 'Volume key page turn: next page');
      if (this.isDualPageMode()) {
        this.goToNextDualPage();
      } else {
        this.goToNextPage();
      }
      this.resetAutoPageTurnTimerForInteraction('volume-key');
      return true;
    }
    
    return false;
  }
  
  // 缓存屏幕密度，避免重复调用 display.getDefaultDisplaySync()
  private cachedScreenDensity: number = 0;
  
  /**
  * 获取屏幕密度比例（用于 vp 和 px 转换）
  * 缓存结果避免重复系统调用
  */
  private getScreenDensity(): number {
    if (this.cachedScreenDensity > 0) {
      return this.cachedScreenDensity;
    }
    try {
      const displayInfo = display.getDefaultDisplaySync();
      this.cachedScreenDensity = displayInfo.densityDPI / 160;
      return this.cachedScreenDensity;
    } catch (e) {
      this.cachedScreenDensity = 3;// 默认密度
      return this.cachedScreenDensity;
    }
  }
  
  /**
  * 将 vp 转换为 px
  */
  private vp2px(vp: number): number {
    return vp * this.getScreenDensity();
  }
  
  /**
  * 将 px 转换为 vp
  */
  private px2vp(px: number): number {
    return px / this.getScreenDensity();
  }
  
  // 缓存平均字符宽度，避免重复计算
  private cachedAvgCharWidth: number = 0;
  private cachedFontSize: number = 0;
  
  /**
  * 获取平均字符宽度（缓存）
  * 注意：这里计算的是单个字符的宽度（不包含字间距）
  */
  private getAvgCharWidth(): number {
    const fontSize = this.settings.textStyle.fontSize;
    const letterSpacing = this.settings.textStyle.letterSpacing;
    const cacheKey = `${fontSize}_${letterSpacing}`;
    
    if (this.cachedAvgCharWidth > 0 && this.cachedFontSize === fontSize) {
      return this.cachedAvgCharWidth;
    }
    
    // 单个字符宽度 = (总宽度 - (n-1)*字间距) / n
    const sampleText = '测试文本字符';
    const totalWidth = this.measureTextWidthFast(sampleText);
    // 单个字符宽度 = (总宽度 - (n-1)*字间距) / n
    // 单个字符宽度 = (总宽度 - (n-1)*字间距) / n
    const charCount = sampleText.length;
    this.cachedAvgCharWidth = (totalWidth - (charCount - 1) * letterSpacing) / charCount;
    this.cachedFontSize = fontSize;
    
    logger.debug(TAG, `[字符宽度] 总宽度=${totalWidth.toFixed(2)}, 字符数=${charCount}, 字间距=${letterSpacing}, 单字符宽度=${this.cachedAvgCharWidth.toFixed(2)}`);
    return this.cachedAvgCharWidth;
  }
  
  /**
  * 快速测量文本宽度（直接调用API）
  */
  private measureTextWidthFast(text: string): number {
    if (!text) return 0;
    
    const fontSizePx = this.vp2px(this.settings.textStyle.fontSize);
    const letterSpacingPx = this.vp2px(this.settings.textStyle.letterSpacing);
    
    const result = measure.measureTextSize({
      textContent: text,
      fontSize: `${fontSizePx}px`,
      fontWeight: this.settings.textStyle.fontWeight,
      letterSpacing: letterSpacingPx
    });
    
    const widthPx = typeof result.width === 'number' ? result.width : parseFloat(String(result.width)) || 0;
    return this.px2vp(widthPx);
  }
  
  /**
   * @param isFirstLine 是否为段落首行（需要缩进）
   * @returns 分割后的行数组
   */
  private splitTextToLines(text: string, maxWidth: number, isFirstLine: boolean): string[] {
    const lines: string[] = [];
    const firstLineIndent = this.settings.textStyle.firstLineIndent;
    
    // 获取平均字符宽度用于估算
    const indentText = isFirstLine && firstLineIndent > 0 ? '　'.repeat(Math.floor(firstLineIndent)) : '';
    let currentText = indentText + text;
    
    // LOCAL模式：使用0.92的保守系数，适合本地TXT文件
    const avgCharWidth = this.getAvgCharWidth();
    
    // 计算每行字符数：考虑字间距
    // 计算每行字符数：考虑字间距
    // 总宽度 = n个字符宽度 + (n-1)个字间距
    const widthFactor = this.paginationMode === PaginationMode.ONLINE ? 1.0 : 0.92;
    
    // maxWidth + letterSpacing = n * (avgCharWidth + letterSpacing)
    // n = (maxWidth + letterSpacing) / (avgCharWidth + letterSpacing)
    // maxWidth = n * avgCharWidth + (n-1) * letterSpacing
    // maxWidth = n * avgCharWidth + n * letterSpacing - letterSpacing
    // maxWidth + letterSpacing = n * (avgCharWidth + letterSpacing)
    // n = (maxWidth + letterSpacing) / (avgCharWidth + letterSpacing)
    const letterSpacing = this.settings.textStyle.letterSpacing;
    const charsPerLine = Math.max(1, Math.floor((maxWidth + letterSpacing) / (avgCharWidth + letterSpacing) * widthFactor));
    
    // 纯字符估算分割，不调用 measureTextSize
    const actualLineWidth = charsPerLine * avgCharWidth + (charsPerLine - 1) * letterSpacing;
    logger.debug(TAG, `[分页调试] maxWidth=${maxWidth.toFixed(2)}, avgCharWidth=${avgCharWidth.toFixed(2)}, letterSpacing=${letterSpacing}, widthFactor=${widthFactor}, charsPerLine=${charsPerLine}, actualLineWidth=${actualLineWidth.toFixed(2)}, 利用率=${(actualLineWidth/maxWidth*100).toFixed(1)}%`);
    
    // 纯字符估算分割，不调用 measureTextSize
    while (currentText.length > 0) {
      const lineLength = Math.min(charsPerLine, currentText.length);
      const lineText = currentText.substring(0, lineLength);
      lines.push(lineText);
      currentText = currentText.substring(lineLength);
    }
    
    return lines;
  }
  
  /**
  * 计算并分页文本内容
  * ONLINE模式：使用按字符数分页，让Text组件自然换行，确保JUSTIFY正确生效
  * LOCAL模式：使用按行分页，精确控制每行内容
  */
  private paginateContent(): void {
    if (!this.content || this.contentAreaWidth <= 0 || this.contentAreaHeight <= 0) {
      return;
    }
    
    const fontSize = this.settings.textStyle.fontSize;
    const lineHeight = this.settings.textStyle.lineHeight;
    const actualLineHeight = this.getEffectiveTextLineHeight();
    
    // 计算每页可容纳的行数
    const linesPerPage = Math.floor(this.contentAreaHeight / actualLineHeight);
    
    logger.info(TAG, `分页参数: fontSize=${fontSize}, lineHeight=${lineHeight}, actualLineHeight=${actualLineHeight}, contentAreaHeight=${this.contentAreaHeight}, linesPerPage=${linesPerPage}`);
    
    if (linesPerPage <= 0) {
      logger.warn(TAG, `每页行数计算异常: contentAreaHeight=${this.contentAreaHeight}, actualLineHeight=${actualLineHeight}`);
      return;
    }
    
    // 更新当前页面内容
    if (this.paginationMode === PaginationMode.ONLINE) {
      this.paginateContentOnlineMode(linesPerPage);
    } else {
      this.paginateContentLocalMode(linesPerPage);
    }
    
    // 分页完成后预加载相邻页面的 PixelMap（用于卷页动画）
    this.updatePageContents();
    
    // 触发就绪回调
    this.preloadAdjacentPagePixelMaps();
    
    logger.info(TAG, `分页完成: 总页数=${this.totalPages}, 每页行数=${linesPerPage}`);
    
    // 触发就绪回调
    this.onReady();
  }
  
  /**
  * ONLINE模式分页：按段落分页，让Text组件自然换行
  * 这样JUSTIFY会正确生效，避免右边空白问题
  */
  private paginateContentOnlineMode(linesPerPage: number): void {
    const avgCharWidth = this.getAvgCharWidth();
    const letterSpacing = this.settings.textStyle.letterSpacing;
    const firstLineIndent = this.settings.textStyle.firstLineIndent;
    
    // 每页大约能容纳的字符数（考虑首行缩进占用的字符数）
    const charsPerLine = Math.max(1, Math.floor((this.contentAreaWidth + letterSpacing) / (avgCharWidth + letterSpacing)));
    // 分段处理，保留原始段落结构
    const charsPerPage = charsPerLine * linesPerPage;
    
    logger.info(TAG, `[ONLINE分页] charsPerLine=${charsPerLine}, charsPerPage=${charsPerPage}`);
    
    // 分段处理，保留原始段落结构
    const paragraphs = this.content.split(/\n/);
    const pages: TextPage[] = [];
    let currentPageParagraphs: string[] = [];
    let currentPageCharCount = 0;
    let charIndex = 0;
    let pageStartCharIndex = 0;
    
    for (let pIdx = 0; pIdx < paragraphs.length; pIdx++) {
      const paragraph = paragraphs[pIdx];
      
          // 当前页已满，创建新页
      if (!paragraph.trim()) {
          // 当前页已满，创建新页
        const emptyLineChars = charsPerLine;
        if (currentPageCharCount + emptyLineChars > charsPerPage && currentPageParagraphs.length > 0) {
          // 当前页已满，创建新页
          this.pushOnlinePage(
            pages,
            currentPageParagraphs,
            pageStartCharIndex,
            charIndex
          );
          pageStartCharIndex = charIndex;
          currentPageParagraphs = [];
          currentPageCharCount = 0;
        }
        currentPageParagraphs.push('');
        currentPageCharCount += emptyLineChars;
        charIndex += paragraph.length + 1;
        continue;
      }
      
      // 检查是否能放入当前页
      const indentChars = Math.floor(firstLineIndent);
      const paragraphCharsWithIndent = paragraph.length + indentChars;
      const paragraphLines = Math.ceil(paragraphCharsWithIndent / charsPerLine);
      const paragraphCharCost = paragraphLines * charsPerLine;
      
        // 计算当前页还能容纳多少行
      if (currentPageCharCount + paragraphCharCost > charsPerPage && currentPageParagraphs.length > 0) {
          // 至少能放2行，尝试分割段落
          // 至少能放2行，尝试分割段落
        const remainingLines = Math.floor((charsPerPage - currentPageCharCount) / charsPerLine);
        
        if (remainingLines >= 2) {
            // 能放下足够的内容，分割段落
          const remainingChars = remainingLines * charsPerLine - indentChars;
          if (remainingChars > charsPerLine / 2) {
              // 分割段落
            const splitPoint = this.findParagraphSplitPoint(paragraph, remainingChars);
            if (splitPoint > 0 && splitPoint < paragraph.length - charsPerLine / 2) {
              // 首部分添加到当前页（带首行缩进）
              const firstPart = paragraph.substring(0, splitPoint);
              const secondPart = paragraph.substring(splitPoint);
              
              // 首部分添加到当前页（带首行缩进）
          currentPageParagraphs.push('  '.repeat(indentChars) + firstPart);
              this.pushOnlinePage(
                pages,
                currentPageParagraphs,
                pageStartCharIndex,
                charIndex + splitPoint
              );
              
              // 开始新页，放剩余部分（不需要首行缩进，因为是段落中间）
              pageStartCharIndex = charIndex + splitPoint;
              currentPageParagraphs = [secondPart];
              const secondPartLines = Math.ceil(secondPart.length / charsPerLine);
              currentPageCharCount = secondPartLines * charsPerLine;
              charIndex += paragraph.length + 1;
              continue;
            }
          }
        }
        
        // 无法分割或不值得分割，直接换页
        this.pushOnlinePage(
          pages,
          currentPageParagraphs,
          pageStartCharIndex,
          charIndex
        );
        pageStartCharIndex = charIndex;
        currentPageParagraphs = [];
        currentPageCharCount = 0;
      }
      
    // 处理最后一页
          currentPageParagraphs.push('  '.repeat(indentChars) + paragraph);
      currentPageCharCount += paragraphCharCost;
      charIndex += paragraph.length + 1;
    }
    
    // 处理最后一页
    if (currentPageParagraphs.length > 0) {
      this.pushOnlinePage(
        pages,
        currentPageParagraphs,
        pageStartCharIndex,
        charIndex
      );
    }
    
    this.pages = pages;
    this.totalPages = pages.length;
  }

  /**
  * 向 ONLINE 分页结果中添加页面（裁掉首尾空白行，稳定首行/末行视觉位置）
  */
  private pushOnlinePage(
    pages: TextPage[],
    paragraphs: string[],
    startCharIndex: number,
    endCharIndex: number
  ): void {
    const rawContent = paragraphs.join('\n');
    const normalizedContent = this.trimBoundaryEmptyLines(rawContent);
    if (normalizedContent.length <= 0) {
      return;
    }

    const safeStartCharIndex = Math.max(0, Math.floor(startCharIndex));
    const safeEndCharIndex = Math.max(safeStartCharIndex, Math.floor(endCharIndex));
    pages.push({
      index: pages.length,
      content: normalizedContent,
      startCharIndex: safeStartCharIndex,
      endCharIndex: safeEndCharIndex
    });
  }

  /**
  * 裁掉文本首尾空白行（保留中间空行）
  */
  private trimBoundaryEmptyLines(text: string): string {
    if (!text) {
      return '';
    }

    const lines = text.split('\n');
    let start = 0;
    let end = lines.length - 1;
    while (start <= end && lines[start].trim().length === 0) {
      start += 1;
    }
    while (end >= start && lines[end].trim().length === 0) {
      end -= 1;
    }
    if (start > end) {
      return '';
    }
    if (start === 0 && end === lines.length - 1) {
      return text;
    }
    return lines.slice(start, end + 1).join('\n');
  }
  
  /**
  * 找到段落的合适分割点（尽量在标点符号后分割）
  */
  private findParagraphSplitPoint(text: string, targetChars: number): number {
    if (targetChars >= text.length) return text.length;
    
    // 在目标位置附近找标点符号
    const searchRange = Math.min(20, targetChars / 4);
    const startSearch = Math.max(0, targetChars - searchRange);
    const endSearch = Math.min(text.length, targetChars + searchRange / 2);
    
    // 优先在句号、问号、感叹号后分割
    const sentenceEnders = ['。', '！', '？', '…', '.', '!', '?'];
    for (let i = endSearch - 1; i >= startSearch; i--) {
      if (sentenceEnders.includes(text[i])) {
        return i + 1;
      }
    }
    
    // 其次在逗号、分号后分割
    const clauseEnders = ['\uff0c', '\u3001', '\uff1b', ',', ';', ':'];
    for (let i = endSearch - 1; i >= startSearch; i--) {
      if (clauseEnders.includes(text[i])) {
        return i + 1;
      }
    }
    
    // 找不到合适的标点，直接在目标位置分割
    return targetChars;
  }
  
  /**
  * LOCAL模式分页：按行分页，精确控制每行内容
  */
  private paginateContentLocalMode(linesPerPage: number): void {
    const paragraphs = this.content.split(/\n+/);
    const pages: TextPage[] = [];
    let currentPageLines: string[] = [];
    let currentLineCount = 0;
    let charIndex = 0;
    let pageStartCharIndex = 0;
    
    for (const paragraph of paragraphs) {
      if (!paragraph.trim()) {
        charIndex += paragraph.length + 1;
        continue;
      }
      
      // 使用精确测量将段落分成行
      const paragraphLines = this.splitTextToLines(
        paragraph.trim(),
        this.contentAreaWidth,
        true// 段落首行需要缩进
      );
      
      for (let i = 0; i < paragraphLines.length; i++) {
        const line = paragraphLines[i];
        currentPageLines.push(line);
        currentLineCount++;
        
        // 检查是否需要换页
        if (currentLineCount >= linesPerPage) {
          const pageContent = currentPageLines.join('\n');
          const endCharIndex = charIndex + pageContent.length;
          
          pages.push({
            index: pages.length,
            content: pageContent,
            startCharIndex: pageStartCharIndex,
            endCharIndex: endCharIndex
          });
          
          pageStartCharIndex = endCharIndex;
          currentPageLines = [];
          currentLineCount = 0;
        }
      }
      
      // 段落结束后添加段落间距（如果还有空间）
      if (currentLineCount > 0 && currentLineCount < linesPerPage) {
        currentPageLines.push('');
        currentLineCount++;
      }
      
      charIndex += paragraph.length + 1;
    }
    
    // 处理最后一页
    if (currentPageLines.length > 0) {
      pages.push({
        index: pages.length,
        content: currentPageLines.join('\n'),
        startCharIndex: pageStartCharIndex,
        endCharIndex: charIndex
      });
    }
    
    this.pages = pages;
    this.totalPages = pages.length;
  }
  
  /**
  * 更新当前、上一页、下一页的内容
  */
  private updatePageContents(): void {
    if (this.pages.length === 0) {
      this.currentPageContent = '';
      this.prevPageContent = '';
      this.nextPageContent = '';
      return;
    }
    
    const safeIndex = Math.max(0, Math.min(this.currentPageIndex, this.pages.length - 1));
    
    this.currentPageContent = this.pages[safeIndex]?.content || '';
    this.prevPageContent = safeIndex > 0 ? this.pages[safeIndex - 1]?.content || '' : '';
    this.nextPageContent = safeIndex < this.pages.length - 1 ? this.pages[safeIndex + 1]?.content || '' : '';
    
    // 双页模式同步更新左右页内容
    if (this.isDualPageMode()) {
      this.updateDualPageContents();
    }
  }

  private getReadAloudHighlightSplitIndex(): number {
    if (!this.readAloudHighlightEnabled) {
      return -1;
    }
    if (this.readAloudCurrentCharIndex < 0 || this.pages.length === 0) {
      return -1;
    }

    const safePageIndex = Math.max(0, Math.min(this.currentPageIndex, this.pages.length - 1));
    const page = this.pages[safePageIndex];
    if (!page) {
      return -1;
    }
    if (page.endCharIndex <= page.startCharIndex) {
      return -1;
    }

    const pageCharSpan = Math.max(1, page.endCharIndex - page.startCharIndex);
    const clampedReadCharIndex = Math.max(
      page.startCharIndex,
      Math.min(this.readAloudCurrentCharIndex, page.endCharIndex)
    );
    const splitRatio = (clampedReadCharIndex - page.startCharIndex) / pageCharSpan;
    const maxSplitIndex = Math.max(0, this.currentPageContent.length);
    const localSplitIndex = Math.floor(maxSplitIndex * splitRatio);
    return Math.max(0, Math.min(localSplitIndex, maxSplitIndex));
  }

  private hasReadAloudHighlight(): boolean {
    return this.getReadAloudHighlightSplitIndex() >= 0;
  }

  private isReadAloudSentenceBoundary(char: string): boolean {
    return char === '\n' ||
      char === '\r' ||
      char === '\u3002' ||
      char === '\uff01' ||
      char === '\uff1f' ||
      char === '\u2026' ||
      char === '\u2014' ||
      char === '\u2025' ||
      char === '\u3001' ||
      char === '\u300d' ||
      char === '\u300f' ||
      char === '\u3011' ||
      char === '.' ||
      char === '!' ||
      char === '?' ||
      char === ';' ||
      char === '\uff1b';
  }

  private isReadAloudSentenceTailChar(char: string): boolean {
    return char === '"' ||
      char === '\'' ||
      char === ')' ||
      char === '\uff09' ||
      char === '\u300d' ||
      char === '\u300f' ||
      char === '\u3011' ||
      char === '\u300b' ||
      char === '\u201d' ||
      char === '\u2019';
  }

  private getReadAloudSentenceStartIndex(): number {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceStart = splitIndex;
    while (sentenceStart > 0) {
      const prevChar = this.currentPageContent.charAt(sentenceStart - 1);
      if (this.isReadAloudSentenceBoundary(prevChar)) {
        break;
      }
      sentenceStart -= 1;
    }
    return sentenceStart;
  }

  private getReadAloudSentenceEndIndex(): number {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceEnd = Math.max(0, splitIndex);
    while (sentenceEnd < this.currentPageContent.length) {
      const currentChar = this.currentPageContent.charAt(sentenceEnd);
      sentenceEnd += 1;
      if (this.isReadAloudSentenceBoundary(currentChar)) {
        while (sentenceEnd < this.currentPageContent.length) {
          const tailChar = this.currentPageContent.charAt(sentenceEnd);
          if (!this.isReadAloudSentenceTailChar(tailChar)) {
            break;
          }
          sentenceEnd += 1;
        }
        break;
      }
    }
    return sentenceEnd;
  }

  private getReadAloudBeforeSentenceText(): string {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudSentenceStartIndex();
    if (sentenceStart <= 0) {
      return '';
    }
    return this.currentPageContent.substring(0, sentenceStart);
  }

  private getReadAloudSentenceReadText(): string {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudSentenceStartIndex();
    if (splitIndex <= sentenceStart) {
      return '';
    }
    return this.currentPageContent.substring(sentenceStart, splitIndex);
  }

  private getReadAloudSentenceUnreadText(): string {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex < 0) {
      return '';
    }
    const sentenceEnd = this.getReadAloudSentenceEndIndex();
    if (sentenceEnd <= splitIndex) {
      return '';
    }
    return this.currentPageContent.substring(splitIndex, sentenceEnd);
  }

  private getReadAloudAfterSentenceText(): string {
    const splitIndex = this.getReadAloudHighlightSplitIndex();
    if (splitIndex < 0) {
      return this.currentPageContent;
    }
    const sentenceEnd = this.getReadAloudSentenceEndIndex();
    if (sentenceEnd >= this.currentPageContent.length) {
      return '';
    }
    return this.currentPageContent.substring(sentenceEnd);
  }

  private getReadAloudHighlightSplitIndexForPage(pageIndex: number, pageContent: string): number {
    if (!this.readAloudHighlightEnabled) {
      return -1;
    }
    if (this.readAloudCurrentCharIndex < 0 || this.pages.length === 0) {
      return -1;
    }
    if (pageIndex < 0 || pageIndex >= this.pages.length) {
      return -1;
    }

    const page = this.pages[pageIndex];
    if (!page || page.endCharIndex <= page.startCharIndex) {
      return -1;
    }

    const pageCharSpan = Math.max(1, page.endCharIndex - page.startCharIndex);
    const clampedReadCharIndex = Math.max(
      page.startCharIndex,
      Math.min(this.readAloudCurrentCharIndex, page.endCharIndex)
    );
    const splitRatio = (clampedReadCharIndex - page.startCharIndex) / pageCharSpan;
    const maxSplitIndex = Math.max(0, pageContent.length);
    const localSplitIndex = Math.floor(maxSplitIndex * splitRatio);
    return Math.max(0, Math.min(localSplitIndex, maxSplitIndex));
  }

  private hasReadAloudHighlightForPage(pageIndex: number, pageContent: string): boolean {
    return this.getReadAloudHighlightSplitIndexForPage(pageIndex, pageContent) >= 0;
  }

  private getReadAloudSentenceStartIndexForText(pageContent: string, splitIndex: number): number {
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceStart = splitIndex;
    while (sentenceStart > 0) {
      const prevChar = pageContent.charAt(sentenceStart - 1);
      if (this.isReadAloudSentenceBoundary(prevChar)) {
        break;
      }
      sentenceStart -= 1;
    }
    return sentenceStart;
  }

  private getReadAloudSentenceEndIndexForText(pageContent: string, splitIndex: number): number {
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceEnd = Math.max(0, splitIndex);
    while (sentenceEnd < pageContent.length) {
      const currentChar = pageContent.charAt(sentenceEnd);
      sentenceEnd += 1;
      if (this.isReadAloudSentenceBoundary(currentChar)) {
        while (sentenceEnd < pageContent.length) {
          const tailChar = pageContent.charAt(sentenceEnd);
          if (!this.isReadAloudSentenceTailChar(tailChar)) {
            break;
          }
          sentenceEnd += 1;
        }
        break;
      }
    }
    return sentenceEnd;
  }

  private getReadAloudBeforeSentenceTextForPage(pageIndex: number, pageContent: string): string {
    const splitIndex = this.getReadAloudHighlightSplitIndexForPage(pageIndex, pageContent);
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudSentenceStartIndexForText(pageContent, splitIndex);
    if (sentenceStart <= 0) {
      return '';
    }
    return pageContent.substring(0, sentenceStart);
  }

  private getReadAloudSentenceReadTextForPage(pageIndex: number, pageContent: string): string {
    const splitIndex = this.getReadAloudHighlightSplitIndexForPage(pageIndex, pageContent);
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudSentenceStartIndexForText(pageContent, splitIndex);
    if (splitIndex <= sentenceStart) {
      return '';
    }
    return pageContent.substring(sentenceStart, splitIndex);
  }

  private getReadAloudSentenceUnreadTextForPage(pageIndex: number, pageContent: string): string {
    const splitIndex = this.getReadAloudHighlightSplitIndexForPage(pageIndex, pageContent);
    if (splitIndex < 0) {
      return '';
    }
    const sentenceEnd = this.getReadAloudSentenceEndIndexForText(pageContent, splitIndex);
    if (sentenceEnd <= splitIndex) {
      return '';
    }
    return pageContent.substring(splitIndex, sentenceEnd);
  }

  private getReadAloudAfterSentenceTextForPage(pageIndex: number, pageContent: string): string {
    const splitIndex = this.getReadAloudHighlightSplitIndexForPage(pageIndex, pageContent);
    if (splitIndex < 0) {
      return pageContent;
    }
    const sentenceEnd = this.getReadAloudSentenceEndIndexForText(pageContent, splitIndex);
    if (sentenceEnd >= pageContent.length) {
      return '';
    }
    return pageContent.substring(sentenceEnd);
  }

  private getReadAloudScrollSplitIndex(): number {
    if (!this.readAloudHighlightEnabled) {
      return -1;
    }
    if (this.readAloudCurrentCharIndex < 0 || this.content.length === 0) {
      return -1;
    }
    const contentLastCharIndex = Math.max(0, this.content.length - 1);
    const safeReadCharIndex = Math.max(0, Math.min(this.readAloudCurrentCharIndex, contentLastCharIndex));
    return safeReadCharIndex;
  }

  private hasReadAloudScrollHighlight(): boolean {
    return this.getReadAloudScrollSplitIndex() >= 0;
  }

  private getReadAloudScrollSentenceStartIndex(): number {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceStart = splitIndex;
    while (sentenceStart > 0) {
      const prevChar = this.content.charAt(sentenceStart - 1);
      if (this.isReadAloudSentenceBoundary(prevChar)) {
        break;
      }
      sentenceStart -= 1;
    }
    return sentenceStart;
  }

  private getReadAloudScrollSentenceEndIndex(): number {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex < 0) {
      return 0;
    }

    let sentenceEnd = Math.max(0, splitIndex);
    while (sentenceEnd < this.content.length) {
      const currentChar = this.content.charAt(sentenceEnd);
      sentenceEnd += 1;
      if (this.isReadAloudSentenceBoundary(currentChar)) {
        while (sentenceEnd < this.content.length) {
          const tailChar = this.content.charAt(sentenceEnd);
          if (!this.isReadAloudSentenceTailChar(tailChar)) {
            break;
          }
          sentenceEnd += 1;
        }
        break;
      }
    }
    return sentenceEnd;
  }

  private getReadAloudScrollBeforeSentenceText(): string {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudScrollSentenceStartIndex();
    if (sentenceStart <= 0) {
      return '';
    }
    return this.content.substring(0, sentenceStart);
  }

  private getReadAloudScrollSentenceReadText(): string {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex <= 0) {
      return '';
    }
    const sentenceStart = this.getReadAloudScrollSentenceStartIndex();
    if (splitIndex <= sentenceStart) {
      return '';
    }
    return this.content.substring(sentenceStart, splitIndex);
  }

  private getReadAloudScrollSentenceUnreadText(): string {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex < 0) {
      return '';
    }
    const sentenceEnd = this.getReadAloudScrollSentenceEndIndex();
    if (sentenceEnd <= splitIndex) {
      return '';
    }
    return this.content.substring(splitIndex, sentenceEnd);
  }

  private getReadAloudScrollAfterSentenceText(): string {
    const splitIndex = this.getReadAloudScrollSplitIndex();
    if (splitIndex < 0) {
      return this.content;
    }
    const sentenceEnd = this.getReadAloudScrollSentenceEndIndex();
    if (sentenceEnd >= this.content.length) {
      return '';
    }
    return this.content.substring(sentenceEnd);
  }

  private getCurrentPageStartCharIndex(): number {
    if (this.pages.length <= 0) {
      return 0;
    }
    const safePageIndex = Math.max(0, Math.min(this.currentPageIndex, this.pages.length - 1));
    const page = this.pages[safePageIndex];
    if (!page) {
      return 0;
    }
    return Math.max(0, page.startCharIndex);
  }

  private getPageStartCharIndexByPageIndex(pageIndex: number): number {
    if (this.pages.length <= 0) {
      return 0;
    }
    const safePageIndex = Math.max(0, Math.min(pageIndex, this.pages.length - 1));
    const page = this.pages[safePageIndex];
    if (page) {
      return Math.max(0, page.startCharIndex);
    }
    for (let i = 0; i < this.pages.length; i++) {
      const pageItem = this.pages[i];
      if (pageItem && pageItem.index === pageIndex) {
        return Math.max(0, pageItem.startCharIndex);
      }
    }
    return 0;
  }

  private normalizeHighlightComparableText(text: string): string {
    if (!text || text.length <= 0) {
      return '';
    }
    return text.replace(/\s+/g, '');
  }

  private isHighlightTextMatch(sourceText: string, quoteText: string): boolean {
    if (sourceText === quoteText) {
      return true;
    }
    const normalizedSource = this.normalizeHighlightComparableText(sourceText);
    const normalizedQuote = this.normalizeHighlightComparableText(quoteText);
    if (normalizedSource.length <= 0 || normalizedQuote.length <= 0) {
      return false;
    }
    return normalizedSource === normalizedQuote;
  }

  private buildCompactTextMapping(text: string): CompactTextMapping {
    let compactText = '';
    const originIndices: number[] = [];
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (/\s/.test(ch)) {
        continue;
      }
      compactText += ch;
      originIndices.push(i);
    }
    const mapping: CompactTextMapping = {
      compactText,
      originIndices
    };
    return mapping;
  }

  private findNearestTextIndex(text: string, target: string, preferredStart: number): number {
    const firstIndex = text.indexOf(target);
    if (firstIndex < 0) {
      return -1;
    }
    if (preferredStart < 0) {
      return firstIndex;
    }
    let bestIndex = firstIndex;
    let bestDistance = Math.abs(firstIndex - preferredStart);
    let cursor = text.indexOf(target, firstIndex + 1);
    while (cursor >= 0) {
      const distance = Math.abs(cursor - preferredStart);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = cursor;
      }
      cursor = text.indexOf(target, cursor + 1);
    }
    return bestIndex;
  }

  private findQuoteLocalRange(pageContent: string, quoteText?: string, preferredLocalStart: number = -1): SelectionRange | null {
    const quote = quoteText ? quoteText.trim() : '';
    if (pageContent.length <= 0 || quote.length <= 0) {
      return null;
    }

    const directIndex = this.findNearestTextIndex(pageContent, quote, preferredLocalStart);
    if (directIndex >= 0) {
      const range: SelectionRange = {
        start: directIndex,
        end: directIndex + quote.length
      };
      return range;
    }

    const compactQuote = this.normalizeHighlightComparableText(quote);
    if (compactQuote.length <= 0) {
      return null;
    }
    const mapping = this.buildCompactTextMapping(pageContent);
    if (mapping.compactText.length <= 0 || mapping.originIndices.length <= 0) {
      return null;
    }

    const compactPreferred = preferredLocalStart >= 0
      ? Math.max(0, Math.min(mapping.compactText.length - 1, preferredLocalStart))
      : -1;
    const compactIndex = this.findNearestTextIndex(mapping.compactText, compactQuote, compactPreferred);
    if (compactIndex < 0) {
      return null;
    }

    const endCompactIndex = compactIndex + compactQuote.length - 1;
    if (endCompactIndex < compactIndex || endCompactIndex >= mapping.originIndices.length) {
      return null;
    }
    const range: SelectionRange = {
      start: mapping.originIndices[compactIndex],
      end: mapping.originIndices[endCompactIndex] + 1
    };
    return range;
  }

  private getLocalHighlightRanges(pageContent: string, pageStartCharIndex: number, _pageIndex: number = -1): LocalHighlightRange[] {
    const ranges: LocalHighlightRange[] = [];
    if (pageContent.length <= 0 || this.novelHighlightRanges.length <= 0) {
      return ranges;
    }

    const pageEndCharIndex = pageStartCharIndex + pageContent.length;
    for (let i = 0; i < this.novelHighlightRanges.length; i++) {
      const sourceRange = this.novelHighlightRanges[i];
      const safeStart = Math.max(0, Math.floor(sourceRange.startOffset));
      const safeEnd = Math.max(safeStart + 1, Math.floor(sourceRange.endOffset));
      const preferredLocalStart = safeStart >= pageStartCharIndex
        ? Math.max(0, Math.min(pageContent.length - 1, safeStart - pageStartCharIndex))
        : -1;
      let resolvedLocalStart = -1;
      let resolvedLocalEnd = -1;

      if (safeEnd > pageStartCharIndex && safeStart < pageEndCharIndex) {
        const localStart = Math.max(0, safeStart - pageStartCharIndex);
        const localEnd = Math.min(pageContent.length, safeEnd - pageStartCharIndex);
        if (localEnd > localStart) {
          resolvedLocalStart = localStart;
          resolvedLocalEnd = localEnd;
          const quote = sourceRange.quoteText ? sourceRange.quoteText.trim() : '';
          if (quote.length > 0) {
            const candidateText = pageContent.substring(localStart, localEnd);
            if (!this.isHighlightTextMatch(candidateText, quote)) {
              const quoteRange = this.findQuoteLocalRange(pageContent, sourceRange.quoteText, preferredLocalStart);
              if (quoteRange && quoteRange.end > quoteRange.start) {
                resolvedLocalStart = quoteRange.start;
                resolvedLocalEnd = quoteRange.end;
              }
            }
          }
        }
      }

      if (resolvedLocalEnd <= resolvedLocalStart) {
        const quoteRange = this.findQuoteLocalRange(pageContent, sourceRange.quoteText, preferredLocalStart);
        if (quoteRange && quoteRange.end > quoteRange.start) {
          resolvedLocalStart = quoteRange.start;
          resolvedLocalEnd = quoteRange.end;
        }
      }

      if (resolvedLocalEnd <= resolvedLocalStart) {
        continue;
      }

      const highlightRange: LocalHighlightRange = {
        id: sourceRange.id,
        start: resolvedLocalStart,
        end: resolvedLocalEnd,
        color: sourceRange.color && sourceRange.color.trim().length > 0 ? sourceRange.color : '#E8A317',
        lineType: sourceRange.lineType === HighlightLineType.WAVY ? HighlightLineType.WAVY : HighlightLineType.UNDERLINE,
        thoughtText: sourceRange.thoughtText ? sourceRange.thoughtText : '',
        quoteText: sourceRange.quoteText && sourceRange.quoteText.trim().length > 0
          ? sourceRange.quoteText
          : pageContent.substring(resolvedLocalStart, resolvedLocalEnd)
      };
      ranges.push(highlightRange);
    }

    ranges.sort((a: LocalHighlightRange, b: LocalHighlightRange) => a.start - b.start || a.end - b.end);
    return ranges;
  }

  private buildTextRenderSegments(pageContent: string, pageStartCharIndex: number, pageIndex: number = -1): TextRenderSegment[] {
    const segments: TextRenderSegment[] = [];
    if (pageContent.length <= 0) {
      return segments;
    }

    const ranges = this.getLocalHighlightRanges(pageContent, pageStartCharIndex, pageIndex);
    if (ranges.length <= 0) {
      const plainSegment: TextRenderSegment = {
        key: 'plain_0',
        text: pageContent,
        highlighted: false,
        color: '',
        lineType: HighlightLineType.UNDERLINE,
        highlightId: '',
        thoughtText: '',
        quoteText: ''
      };
      segments.push(plainSegment);
      return segments;
    }

    const boundaries: number[] = [0, pageContent.length];
    for (let i = 0; i < ranges.length; i++) {
      boundaries.push(ranges[i].start);
      boundaries.push(ranges[i].end);
    }
    boundaries.sort((a: number, b: number) => a - b);

    const uniqueBoundaries: number[] = [];
    for (let i = 0; i < boundaries.length; i++) {
      const boundary = boundaries[i];
      if (uniqueBoundaries.length <= 0 || uniqueBoundaries[uniqueBoundaries.length - 1] !== boundary) {
        uniqueBoundaries.push(boundary);
      }
    }

    for (let i = 0; i < uniqueBoundaries.length - 1; i++) {
      const start = uniqueBoundaries[i];
      const end = uniqueBoundaries[i + 1];
      if (end <= start) {
        continue;
      }
      const segmentText = pageContent.substring(start, end);
      if (segmentText.length <= 0) {
        continue;
      }

      let highlighted = false;
      let color = '#E8A317';
      let lineType: HighlightLineType = HighlightLineType.UNDERLINE;
      let highlightId = '';
      let thoughtText = '';
      let quoteText = '';
      for (let j = 0; j < ranges.length; j++) {
        const range = ranges[j];
        if (start >= range.start && end <= range.end) {
          highlighted = true;
          color = range.color;
          lineType = range.lineType;
          highlightId = range.id;
          thoughtText = range.thoughtText;
          quoteText = range.quoteText;
        }
      }
      if (highlighted && quoteText.length <= 0) {
        quoteText = segmentText;
      }

      const segment: TextRenderSegment = {
        key: `${start}_${end}_${highlighted ? 1 : 0}_${color}_${lineType}_${highlightId}_${thoughtText.length}_${quoteText.length}`,
        text: segmentText,
        highlighted,
        color,
        lineType,
        highlightId,
        thoughtText,
        quoteText
      };
      segments.push(segment);
    }

    if (segments.length <= 0) {
      const fallbackSegment: TextRenderSegment = {
        key: 'fallback_0',
        text: pageContent,
        highlighted: false,
        color: '',
        lineType: HighlightLineType.UNDERLINE,
        highlightId: '',
        thoughtText: '',
        quoteText: ''
      };
      segments.push(fallbackSegment);
    }

    return segments;
  }

  private buildScrollHighlightSegmentsSignature(): string {
    const contentHead = this.content.substring(0, Math.min(24, this.content.length));
    const contentTail = this.content.length > 24
      ? this.content.substring(Math.max(0, this.content.length - 24))
      : this.content;
    let signature = `${this.content.length}|${contentHead}|${contentTail}|${this.novelHighlightRanges.length}|`;
    for (let i = 0; i < this.novelHighlightRanges.length; i++) {
      const range = this.novelHighlightRanges[i];
      signature += `${range.id}_${range.startOffset}_${range.endOffset}_${range.color}_${range.lineType || ''}_${range.thoughtText || ''}|`;
    }
    return signature;
  }

  private getScrollHighlightSegments(): TextRenderSegment[] {
    if (this.novelHighlightRanges.length <= 0 || this.content.length <= 0) {
      this.scrollHighlightSegmentsCacheSignature = '';
      this.scrollHighlightSegmentsCache = [];
      return [];
    }
    const signature = this.buildScrollHighlightSegmentsSignature();
    if (signature === this.scrollHighlightSegmentsCacheSignature) {
      return this.scrollHighlightSegmentsCache;
    }
    const segments = this.buildTextRenderSegments(this.content, 0);
    this.scrollHighlightSegmentsCacheSignature = signature;
    this.scrollHighlightSegmentsCache = segments;
    return segments;
  }

  private hasHighlightInPage(pageContent: string, pageStartCharIndex: number, pageIndex: number = -1): boolean {
    return this.getLocalHighlightRanges(pageContent, pageStartCharIndex, pageIndex).length > 0;
  }

  private isHighlightThoughtPopupActive(): boolean {
    return this.showHighlightThoughtPopup || this.highlightThoughtPopupOpacity > 0.01;
  }

  private clearPendingThoughtPopupRequest(): void {
    if (this.pendingThoughtPopupTimer !== -1) {
      clearTimeout(this.pendingThoughtPopupTimer);
      this.pendingThoughtPopupTimer = -1;
    }
    this.pendingThoughtPopupStartOffset = -1;
    this.pendingThoughtPopupEndOffset = -1;
    this.pendingThoughtPopupQuoteText = '';
    this.pendingThoughtPopupRetryCount = 0;
  }

  private preparePendingThoughtPopupBySelection(
    startOffset: number,
    endOffset: number,
    quoteText: string
  ): void {
    this.clearPendingThoughtPopupRequest();
    const safeStart = Math.max(0, Math.floor(startOffset));
    const safeEnd = Math.max(safeStart + 1, Math.floor(endOffset));
    this.pendingThoughtPopupStartOffset = safeStart;
    this.pendingThoughtPopupEndOffset = safeEnd;
    this.pendingThoughtPopupQuoteText = quoteText;
    this.pendingThoughtPopupRetryCount = 0;
    this.pendingThoughtPopupTimer = setTimeout(() => {
      this.pendingThoughtPopupTimer = -1;
      this.tryPresentPendingThoughtPopup('initial_schedule');
    }, 180);
    logger.info(
      TAG,
      `已登记划线想法悬浮窗待显示请求: start=${safeStart}, end=${safeEnd}, quoteLength=${quoteText.length}`
    );
  }

  private findPendingThoughtPopupTargetRange(): TextReaderHighlightRange | null {
    if (this.pendingThoughtPopupStartOffset < 0 || this.pendingThoughtPopupEndOffset <= this.pendingThoughtPopupStartOffset) {
      return null;
    }
    let exactHit: TextReaderHighlightRange | null = null;
    let containHit: TextReaderHighlightRange | null = null;
    let overlapHit: TextReaderHighlightRange | null = null;
    const pendingQuote = this.pendingThoughtPopupQuoteText;
    const targetLength = this.pendingThoughtPopupEndOffset - this.pendingThoughtPopupStartOffset;
    let bestContainLength = Number.MAX_SAFE_INTEGER;
    let bestOverlapLength = Number.MAX_SAFE_INTEGER;

    for (let i = 0; i < this.novelHighlightRanges.length; i++) {
      const range = this.novelHighlightRanges[i];
      const rangeStart = Math.floor(range.startOffset);
      const rangeEnd = Math.floor(range.endOffset);
      const rangeLength = rangeEnd - rangeStart;
      if (rangeEnd <= rangeStart) {
        continue;
      }
      if (rangeStart === this.pendingThoughtPopupStartOffset && rangeEnd === this.pendingThoughtPopupEndOffset) {
        exactHit = range;
        break;
      }
      const contains = rangeStart <= this.pendingThoughtPopupStartOffset && rangeEnd >= this.pendingThoughtPopupEndOffset;
      if (contains) {
        if (rangeLength < bestContainLength) {
          bestContainLength = rangeLength;
          containHit = range;
        }
      }
      const overlaps = !(rangeEnd <= this.pendingThoughtPopupStartOffset || rangeStart >= this.pendingThoughtPopupEndOffset);
      if (overlaps) {
        if (rangeLength < bestOverlapLength) {
          bestOverlapLength = rangeLength;
          overlapHit = range;
        }
      }
      if (pendingQuote.length > 0 && range.quoteText && range.quoteText.length > 0) {
        if (range.quoteText === pendingQuote && Math.abs(rangeLength - targetLength) <= 2) {
          containHit = range;
          bestContainLength = rangeLength;
        }
      }
    }

    if (exactHit) {
      return exactHit;
    }
    if (containHit) {
      return containHit;
    }
    if (overlapHit) {
      return overlapHit;
    }
    return null;
  }

  private tryPresentPendingThoughtPopup(trigger: string): void {
    if (this.pendingThoughtPopupStartOffset < 0 || this.pendingThoughtPopupEndOffset <= this.pendingThoughtPopupStartOffset) {
      return;
    }
    const targetRange = this.findPendingThoughtPopupTargetRange();
    if (!targetRange) {
      if (this.pendingThoughtPopupRetryCount >= TextReaderComponent.PENDING_THOUGHT_POPUP_MAX_RETRIES) {
        logger.warn(
          TAG,
          `划线想法悬浮窗待显示超时，未找到目标划线: trigger=${trigger}, start=${this.pendingThoughtPopupStartOffset}, end=${this.pendingThoughtPopupEndOffset}`
        );
        this.clearPendingThoughtPopupRequest();
        return;
      }
      this.pendingThoughtPopupRetryCount += 1;
      if (this.pendingThoughtPopupTimer !== -1) {
        clearTimeout(this.pendingThoughtPopupTimer);
      }
      this.pendingThoughtPopupTimer = setTimeout(() => {
        this.pendingThoughtPopupTimer = -1;
        this.tryPresentPendingThoughtPopup(`retry_${this.pendingThoughtPopupRetryCount}`);
      }, 130);
      return;
    }

    const thoughtText = targetRange.thoughtText ? targetRange.thoughtText.trim() : '';
    const popupText = thoughtText.length > 0 ? thoughtText : '补充想法';
    this.highlightThoughtPopupHighlightId = targetRange.id;
    this.highlightThoughtPopupColor = targetRange.color && targetRange.color.trim().length > 0 ? targetRange.color : '#E8A317';
    this.highlightThoughtPopupLineType = targetRange.lineType === HighlightLineType.WAVY
      ? HighlightLineType.WAVY
      : HighlightLineType.UNDERLINE;
    const quoteText = targetRange.quoteText && targetRange.quoteText.trim().length > 0
      ? targetRange.quoteText
      : this.pendingThoughtPopupQuoteText;
    this.highlightThoughtPopupQuoteText = quoteText;
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = thoughtText;
    const anchorXVp = this.px2vp(this.componentWidth > 0 ? (this.componentWidth / 2) : 180);
    const anchorYVp = this.getHighlightThoughtPopupTopPadding() + 56;
    this.presentHighlightThoughtPopup(popupText, thoughtText.length <= 0, anchorXVp, anchorYVp);
    this.suppressNextTapEvent = true;
    if (this.suppressNextTapResetTimer !== -1) {
      clearTimeout(this.suppressNextTapResetTimer);
    }
    this.suppressNextTapResetTimer = setTimeout(() => {
      this.suppressNextTapEvent = false;
      this.suppressNextTapResetTimer = -1;
    }, 180);
    if (thoughtText.length <= 0) {
      setTimeout(() => {
        this.startHighlightThoughtPopupEdit();
      }, 60);
    }
    logger.info(
      TAG,
      `自动展示划线想法悬浮窗成功: trigger=${trigger}, highlightId=${targetRange.id}, needInput=${thoughtText.length <= 0}`
    );
    this.clearPendingThoughtPopupRequest();
  }

  private showThoughtPopupForSegment(segment: TextRenderSegment, event?: ClickEvent): void {
    if (!segment.highlighted) {
      return;
    }
    const thoughtText = segment.thoughtText ? segment.thoughtText.trim() : '';
    const popupText = thoughtText.length > 0 ? thoughtText : '补充想法';
    this.highlightThoughtPopupHighlightId = segment.highlightId;
    this.highlightThoughtPopupColor = segment.color && segment.color.trim().length > 0 ? segment.color : '#E8A317';
    this.highlightThoughtPopupLineType = segment.lineType === HighlightLineType.WAVY
      ? HighlightLineType.WAVY
      : HighlightLineType.UNDERLINE;
    const quoteText = segment.quoteText && segment.quoteText.trim().length > 0 ? segment.quoteText : segment.text;
    this.highlightThoughtPopupQuoteText = quoteText;
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = thoughtText;
    const anchorXVp = event ? event.displayX : this.px2vp(this.componentWidth / 2);
    const anchorYVp = event ? event.displayY : this.getHighlightThoughtPopupTopPadding() + 56;
    this.presentHighlightThoughtPopup(popupText, thoughtText.length <= 0, anchorXVp, anchorYVp);
    logger.info(TAG, `点击划线文本，展示想法悬浮窗: highlightId=${segment.highlightId}, hasThought=${thoughtText.length > 0}`);
    this.suppressNextTapEvent = true;
    if (this.suppressNextTapResetTimer !== -1) {
      clearTimeout(this.suppressNextTapResetTimer);
    }
    this.suppressNextTapResetTimer = setTimeout(() => {
      this.suppressNextTapEvent = false;
      this.suppressNextTapResetTimer = -1;
    }, 120);
  }

  private applyHighlightStyleFromPopup(lineType: HighlightLineType, color: string): void {
    const targetColor = color && color.trim().length > 0 ? color : '#E8A317';
    this.highlightThoughtPopupLineType = lineType;
    this.highlightThoughtPopupColor = targetColor;
    if (!this.highlightThoughtPopupHighlightId || this.highlightThoughtPopupHighlightId.length <= 0) {
      return;
    }
    this.onUpdateHighlightStyle(this.highlightThoughtPopupHighlightId, lineType, targetColor);
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    logger.info(
      TAG,
      `触发划线样式更新: highlightId=${this.highlightThoughtPopupHighlightId}, lineType=${lineType}, color=${targetColor}`
    );
  }

  private startHighlightThoughtPopupEdit(): void {
    this.highlightThoughtPopupInputText = this.highlightThoughtPopupIsPlaceholder ? '' : this.highlightThoughtPopupText;
    this.highlightThoughtPopupEditing = true;
    logger.info(TAG, `进入划线想法编辑状态: highlightId=${this.highlightThoughtPopupHighlightId}`);
  }

  private cancelHighlightThoughtPopupEdit(): void {
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = this.highlightThoughtPopupIsPlaceholder ? '' : this.highlightThoughtPopupText;
    logger.info(TAG, `取消划线想法编辑: highlightId=${this.highlightThoughtPopupHighlightId}`);
  }

  private submitHighlightThoughtFromPopup(): void {
    if (!this.highlightThoughtPopupHighlightId || this.highlightThoughtPopupHighlightId.length <= 0) {
      logger.warn(TAG, '提交划线想法失败: highlightId 为空');
      return;
    }
    const nextThoughtText = this.highlightThoughtPopupInputText.trim();
    this.highlightThoughtPopupText = nextThoughtText.length > 0 ? nextThoughtText : '补充想法';
    this.highlightThoughtPopupIsPlaceholder = nextThoughtText.length <= 0;
    this.highlightThoughtPopupEditing = false;
    this.onUpdateHighlightThought(this.highlightThoughtPopupHighlightId, nextThoughtText);
    logger.info(
      TAG,
      `触发划线想法更新: highlightId=${this.highlightThoughtPopupHighlightId}, textLength=${nextThoughtText.length}`
    );
  }

  private presentHighlightThoughtPopup(text: string, isPlaceholder: boolean, anchorXVp: number, anchorYVp: number): void {
    this.highlightThoughtPopupText = text;
    this.highlightThoughtPopupIsPlaceholder = isPlaceholder;
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = isPlaceholder ? '' : text;
    this.updateHighlightThoughtPopupPosition(anchorXVp, anchorYVp);
    this.showHighlightThoughtPopup = true;
    this.highlightThoughtPopupMaskOpacity = 0;
    this.highlightThoughtPopupOpacity = 0;
    this.highlightThoughtPopupScale = 0.88;
    this.highlightThoughtPopupTranslateY = 14;
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    if (this.highlightThoughtPopupHideTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupHideTimer);
      this.highlightThoughtPopupHideTimer = -1;
    }
    animateTo({ duration: 180, curve: curves.cubicBezierCurve(0.22, 0.92, 0.28, 1.08) }, () => {
      this.highlightThoughtPopupMaskOpacity = 1;
      this.highlightThoughtPopupOpacity = 1;
      this.highlightThoughtPopupScale = 1.04;
      this.highlightThoughtPopupTranslateY = -3;
    });
    this.highlightThoughtPopupTimer = setTimeout(() => {
      animateTo({ duration: 120, curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1) }, () => {
        this.highlightThoughtPopupScale = 1;
        this.highlightThoughtPopupTranslateY = 0;
      });
      this.highlightThoughtPopupTimer = -1;
    }, 170);
  }

  private dismissHighlightThoughtPopup(): void {
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    if (this.highlightThoughtPopupHideTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupHideTimer);
      this.highlightThoughtPopupHideTimer = -1;
    }
    if (!this.showHighlightThoughtPopup) {
      return;
    }
    animateTo({ duration: 90, curve: curves.cubicBezierCurve(0.4, 0, 0.2, 1) }, () => {
      this.highlightThoughtPopupScale = 1.02;
      this.highlightThoughtPopupTranslateY = -2;
    });
    this.highlightThoughtPopupTimer = setTimeout(() => {
      animateTo({ duration: 170, curve: Curve.EaseIn }, () => {
        this.highlightThoughtPopupMaskOpacity = 0;
        this.highlightThoughtPopupOpacity = 0;
        this.highlightThoughtPopupScale = 0.9;
        this.highlightThoughtPopupTranslateY = 12;
      });
      this.highlightThoughtPopupHideTimer = setTimeout(() => {
        if (this.highlightThoughtPopupOpacity <= 0.01) {
          this.showHighlightThoughtPopup = false;
          this.highlightThoughtPopupQuoteText = '';
          this.highlightThoughtPopupEditing = false;
          this.highlightThoughtPopupInputText = '';
        }
        this.highlightThoughtPopupHideTimer = -1;
      }, 180);
      this.highlightThoughtPopupTimer = -1;
    }, 70);
  }

  private getHighlightThoughtPopupTopPadding(): number {
    const padding = this.getEffectiveContentPadding();
    return Math.max(16, padding.top + 8);
  }

  private getHighlightThoughtPopupWidthVp(): number {
    const screenWidthVp = this.getScreenWidthVp();
    return Math.max(180, Math.min(300, screenWidthVp * 0.78));
  }

  private getScreenWidthVp(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return this.px2vp(displayInfo.width);
    } catch (_error) {
      if (this.componentWidth > 0) {
        return this.px2vp(this.componentWidth);
      }
      return 360;
    }
  }

  private getScreenHeightVp(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return this.px2vp(displayInfo.height);
    } catch (_error) {
      if (this.componentHeight > 0) {
        return this.px2vp(this.componentHeight);
      }
      return 640;
    }
  }

  private updateHighlightThoughtPopupPosition(anchorXVp: number, anchorYVp: number): void {
    const popupWidth = this.getHighlightThoughtPopupWidthVp();
    const estimatedHeight = 196;
    const horizontalMargin = 12;
    const verticalGap = 12;
    const minTop = this.getHighlightThoughtPopupTopPadding();
    const screenWidth = this.getScreenWidthVp();
    const screenHeight = this.getScreenHeightVp();
    const maxLeft = Math.max(horizontalMargin, screenWidth - popupWidth - horizontalMargin);
    let left = anchorXVp - popupWidth / 2;
    if (left < horizontalMargin) {
      left = horizontalMargin;
    }
    if (left > maxLeft) {
      left = maxLeft;
    }

    let top = anchorYVp - estimatedHeight - verticalGap;
    if (top < minTop) {
      top = anchorYVp + verticalGap;
    }
    const maxTop = Math.max(minTop, screenHeight - estimatedHeight - 12);
    if (top > maxTop) {
      top = maxTop;
    }
    if (top < minTop) {
      top = minTop;
    }
    this.highlightThoughtPopupLeftVp = left;
    this.highlightThoughtPopupTopVp = top;
  }

  @Builder
  private buildHighlightThoughtPopupLayer() {
    if (this.showHighlightThoughtPopup) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#14000000')
          .backgroundBlurStyle(BlurStyle.Thin)
          .opacity(this.highlightThoughtPopupMaskOpacity)
          .clip(true)
          .zIndex(0)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.dismissHighlightThoughtPopup();
          })

        Column() {
          Row({ space: 10 }) {
            Column({ space: 8 }) {
              Button() {
                SymbolGlyph($r('sys.symbol.highlighter_line'))
                  .fontSize(16)
                  .fontColor([
                    this.highlightThoughtPopupLineType === HighlightLineType.UNDERLINE ? '#FFFFFF' : this.settings.textStyle.textColor
                  ])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(
                this.highlightThoughtPopupLineType === HighlightLineType.UNDERLINE ? this.highlightThoughtPopupColor : '#1A000000'
              )
              .onClick(() => {
                this.applyHighlightStyleFromPopup(HighlightLineType.UNDERLINE, this.highlightThoughtPopupColor);
              })

              Button() {
                SymbolGlyph($r('sys.symbol.scribble'))
                  .fontSize(16)
                  .fontColor([
                    this.highlightThoughtPopupLineType === HighlightLineType.WAVY ? '#FFFFFF' : this.settings.textStyle.textColor
                  ])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(
                this.highlightThoughtPopupLineType === HighlightLineType.WAVY ? this.highlightThoughtPopupColor : '#1A000000'
              )
              .onClick(() => {
                this.applyHighlightStyleFromPopup(HighlightLineType.WAVY, this.highlightThoughtPopupColor);
              })

              ForEach(HIGHLIGHT_POPUP_COLOR_OPTIONS, (colorItem: string) => {
                Button() {}
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .backgroundColor(colorItem)
                  .border({
                    width: this.highlightThoughtPopupColor === colorItem ? 2 : 1,
                    color: this.highlightThoughtPopupColor === colorItem ? this.settings.textStyle.textColor : '#33000000'
                  })
                  .onClick(() => {
                    this.applyHighlightStyleFromPopup(this.highlightThoughtPopupLineType, colorItem);
                  })
              }, (colorItem: string) => colorItem)
            }
            .width(32)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 8 }) {
              if (this.highlightThoughtPopupEditing) {
                TextInput({
                  text: this.highlightThoughtPopupInputText,
                  placeholder: '补充想法'
                })
                  .fontSize(14)
                  .fontColor(this.settings.textStyle.textColor)
                  .fontFamily(this.settings.textStyle.fontFamily)
                  .width('100%')
                  .onChange((value: string) => {
                    this.highlightThoughtPopupInputText = value;
                  })
                  .onSubmit(() => {
                    this.submitHighlightThoughtFromPopup();
                  })

                Row({ space: 8 }) {
                  Button('保存')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#2563EB')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => {
                      this.submitHighlightThoughtFromPopup();
                    })

                  Button('取消')
                    .fontSize(12)
                    .fontColor(this.settings.textStyle.textColor)
                    .backgroundColor('#1A000000')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => {
                      this.cancelHighlightThoughtPopupEdit();
                    })
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
              } else {
                Text(this.highlightThoughtPopupText)
                  .fontSize(14)
                  .fontColor(this.highlightThoughtPopupIsPlaceholder ? '#777777' : this.settings.textStyle.textColor)
                  .lineHeight(20)
                  .maxLines(4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.settings.textStyle.fontFamily)
                  .width('100%')
                  .onClick(() => {
                    this.startHighlightThoughtPopupEdit();
                  })
              }

              Column({ space: 6 }) {
                Text('当前划线内容（实时预览）')
                  .fontSize(11)
                  .fontColor('#777777')
                  .fontFamily(this.settings.textStyle.fontFamily)
                  .width('100%')

                if (this.highlightThoughtPopupQuoteText.trim().length > 0) {
                  Text() {
                    Span(this.highlightThoughtPopupQuoteText)
                      .decoration({ type: TextDecorationType.Underline, color: this.highlightThoughtPopupColor })
                      .textBackgroundStyle(
                        this.highlightThoughtPopupLineType === HighlightLineType.WAVY
                          ? { color: `${this.highlightThoughtPopupColor}33` }
                          : { color: '#00000000' }
                      )
                  }
                    .fontSize(13)
                    .fontColor(this.settings.textStyle.textColor)
                    .lineHeight(20)
                    .maxLines(4)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontFamily(this.settings.textStyle.fontFamily)
                    .width('100%')
                } else {
                  Text('暂无划线内容')
                    .fontSize(12)
                    .fontColor('#999999')
                    .fontFamily(this.settings.textStyle.fontFamily)
                    .width('100%')
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor('#12000000')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width(this.getHighlightThoughtPopupWidthVp())
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(this.getContentBackgroundColor())
        .borderRadius(12)
        .position({ x: this.highlightThoughtPopupLeftVp, y: this.highlightThoughtPopupTopVp })
        .opacity(this.highlightThoughtPopupOpacity)
        .scale({ x: this.highlightThoughtPopupScale, y: this.highlightThoughtPopupScale })
        .translate({ y: this.highlightThoughtPopupTranslateY })
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(1)
      }
      .width('100%')
      .height('100%')
      .zIndex(50)
    }
  }

  @Builder
  private buildPageTextWithHighlight(pageContent: string, pageStartCharIndex: number, pageIndex: number = -1) {
    Text() {
      ForEach(this.buildTextRenderSegments(pageContent, pageStartCharIndex, pageIndex), (segment: TextRenderSegment) => {
        if (segment.highlighted) {
          Span(segment.text)
            .decoration({ type: TextDecorationType.Underline, color: segment.color })
            .textBackgroundStyle(
              segment.lineType === HighlightLineType.WAVY ? { color: `${segment.color}33` } : { color: '#00000000' }
            )
            .onClick((event: ClickEvent) => {
              this.showThoughtPopupForSegment(segment, event);
            })
        } else {
          Span(segment.text)
        }
      }, (segment: TextRenderSegment) => segment.key)
    }
      .fontSize(this.settings.textStyle.fontSize)
      .fontColor(this.settings.textStyle.textColor)
      .lineHeight(this.getEffectiveTextLineHeight())
      .letterSpacing(this.settings.textStyle.letterSpacing)
      .fontWeight(this.settings.textStyle.fontWeight)
      .fontFamily(this.settings.textStyle.fontFamily)
      .textAlign(this.getTextAlign())
      .padding(this.getEffectiveContentPadding())
      .width('100%')
      .height('100%')
      .backgroundColor(this.getContentBackgroundColor())
      .copyOption(CopyOptions.InApp)
      .selection(this.selectionStart, this.selectionEnd)
      .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
        this.handleTextSelectionChange(selectionStart, selectionEnd);
      })
      .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
        onDisappear: () => {
          this.clearSelection();
        }
      })
  }

  @Builder
  private buildDualPageTextWithHighlight(pageContent: string, pageStartCharIndex: number, pageIndex: number = -1) {
    Text() {
      ForEach(this.buildTextRenderSegments(pageContent, pageStartCharIndex, pageIndex), (segment: TextRenderSegment) => {
        if (segment.highlighted) {
          Span(segment.text)
            .decoration({ type: TextDecorationType.Underline, color: segment.color })
            .textBackgroundStyle(
              segment.lineType === HighlightLineType.WAVY ? { color: `${segment.color}33` } : { color: '#00000000' }
            )
            .onClick((event: ClickEvent) => {
              this.showThoughtPopupForSegment(segment, event);
            })
        } else {
          Span(segment.text)
        }
      }, (segment: TextRenderSegment) => segment.key)
    }
      .fontSize(this.settings.textStyle.fontSize)
      .fontColor(this.settings.textStyle.textColor)
      .lineHeight(this.getEffectiveTextLineHeight())
      .letterSpacing(this.settings.textStyle.letterSpacing)
      .fontWeight(this.settings.textStyle.fontWeight)
      .fontFamily(this.settings.textStyle.fontFamily)
      .textAlign(this.getTextAlign())
      .padding(this.getEffectiveContentPadding())
      .width('100%')
      .height('100%')
  }

  @Builder
  private buildCurrentPageTextLayer() {
    if (!this.hasReadAloudHighlight()) {
      if (this.hasHighlightInPage(this.currentPageContent, this.getCurrentPageStartCharIndex(), this.currentPageIndex)) {
        this.buildPageTextWithHighlight(this.currentPageContent, this.getCurrentPageStartCharIndex(), this.currentPageIndex)
      } else {
        Text(this.currentPageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.getEffectiveTextLineHeight())
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .textAlign(this.getTextAlign())
          .padding(this.getEffectiveContentPadding())
          .width('100%')
          .height('100%')
          .backgroundColor(this.getContentBackgroundColor())
          .copyOption(CopyOptions.InApp)
          .selection(this.selectionStart, this.selectionEnd)
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.handleTextSelectionChange(selectionStart, selectionEnd);
          })
          .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
            onDisappear: () => {
              this.clearSelection();
            }
          })
      }
    } else {
      Text() {
        if (this.getReadAloudBeforeSentenceText().length > 0) {
          Span(this.getReadAloudBeforeSentenceText())
            .textBackgroundStyle({ color: READ_ALOUD_HISTORY_HIGHLIGHT })
        }
        if (this.getReadAloudSentenceReadText().length > 0) {
          Span(this.getReadAloudSentenceReadText())
            .textBackgroundStyle({ color: READ_ALOUD_READ_HIGHLIGHT })
        }
        if (this.getReadAloudSentenceUnreadText().length > 0) {
          Span(this.getReadAloudSentenceUnreadText())
            .textBackgroundStyle({ color: READ_ALOUD_CURRENT_SENTENCE_HIGHLIGHT })
        }
        if (this.getReadAloudAfterSentenceText().length > 0) {
          Span(this.getReadAloudAfterSentenceText())
        }
      }
        .fontSize(this.settings.textStyle.fontSize)
        .fontColor(this.settings.textStyle.textColor)
        .lineHeight(this.getEffectiveTextLineHeight())
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .fontFamily(this.settings.textStyle.fontFamily)
        .textAlign(this.getTextAlign())
        .padding(this.getEffectiveContentPadding())
        .width('100%')
        .height('100%')
        .backgroundColor(this.getContentBackgroundColor())
        .copyOption(CopyOptions.InApp)
        .selection(this.selectionStart, this.selectionEnd)
        .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
          this.handleTextSelectionChange(selectionStart, selectionEnd);
        })
        .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
          onDisappear: () => {
            this.clearSelection();
          }
        })
    }
  }

  @Builder
  private buildDualPageTextLayer(pageContent: string, pageIndex: number) {
    if (!this.hasReadAloudHighlightForPage(pageIndex, pageContent)) {
      if (this.hasHighlightInPage(pageContent, this.getPageStartCharIndexByPageIndex(pageIndex), pageIndex)) {
        this.buildDualPageTextWithHighlight(pageContent, this.getPageStartCharIndexByPageIndex(pageIndex), pageIndex)
      } else {
        Text(pageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.getEffectiveTextLineHeight())
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .textAlign(this.getTextAlign())
          .padding(this.getEffectiveContentPadding())
          .width('100%')
          .height('100%')
      }
    } else {
      Text() {
        if (this.getReadAloudBeforeSentenceTextForPage(pageIndex, pageContent).length > 0) {
          Span(this.getReadAloudBeforeSentenceTextForPage(pageIndex, pageContent))
            .textBackgroundStyle({ color: READ_ALOUD_HISTORY_HIGHLIGHT })
        }
        if (this.getReadAloudSentenceReadTextForPage(pageIndex, pageContent).length > 0) {
          Span(this.getReadAloudSentenceReadTextForPage(pageIndex, pageContent))
            .textBackgroundStyle({ color: READ_ALOUD_READ_HIGHLIGHT })
        }
        if (this.getReadAloudSentenceUnreadTextForPage(pageIndex, pageContent).length > 0) {
          Span(this.getReadAloudSentenceUnreadTextForPage(pageIndex, pageContent))
            .textBackgroundStyle({ color: READ_ALOUD_CURRENT_SENTENCE_HIGHLIGHT })
        }
        if (this.getReadAloudAfterSentenceTextForPage(pageIndex, pageContent).length > 0) {
          Span(this.getReadAloudAfterSentenceTextForPage(pageIndex, pageContent))
        }
      }
        .fontSize(this.settings.textStyle.fontSize)
        .fontColor(this.settings.textStyle.textColor)
        .lineHeight(this.getEffectiveTextLineHeight())
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .fontFamily(this.settings.textStyle.fontFamily)
        .textAlign(this.getTextAlign())
        .padding(this.getEffectiveContentPadding())
        .width('100%')
        .height('100%')
    }
  }
  
  // ========== 翻页逻辑 ==========
  /**
  * 翻到下一页
  */
  private goToNextPage(source: string = 'manual'): void {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, `goToNextPage 被阻止: 划线悬浮窗显示中, source=${source}`);
      return;
    }
    // 安全检查：分页中、加载中、动画中、或页面数据无效时不允许翻页
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) {
      logger.debug(TAG, `goToNextPage 被阻止: isAnimating=${this.isAnimating}, isPaginating=${this.isPaginating}, isLoading=${this.isLoading}, pages=${this.pages.length}`);
      return;
    }
    if (this.currentPageIndex >= this.totalPages - 1) {
      // 已是最后一页，提供边界反馈
      this.provideBoundaryFeedback();
      return;
    }

    this.notifyUserPageTurnStartIfNeeded(source);
    this.isForward = true;
    this.performPageTurn(this.currentPageIndex + 1);
  }
  
  /**
  * 翻到上一页
  */
  private goToPrevPage(source: string = 'manual'): void {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, `goToPrevPage 被阻止: 划线悬浮窗显示中, source=${source}`);
      return;
    }
    // 安全检查：分页中、加载中、动画中、或页面数据无效时不允许翻页
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) {
      logger.debug(TAG, `goToPrevPage 被阻止: isAnimating=${this.isAnimating}, isPaginating=${this.isPaginating}, isLoading=${this.isLoading}, pages=${this.pages.length}`);
      return;
    }
    if (this.currentPageIndex <= 0) {
      // 已是第一页，提供边界反馈
      this.provideBoundaryFeedback();
      return;
    }

    this.notifyUserPageTurnStartIfNeeded(source);
    this.isForward = false;
    this.performPageTurn(this.currentPageIndex - 1);
  }
  
  /**
  * 跳转到指定页面
  */
  private goToPage(pageIndex: number, source: string = 'programmatic'): void {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, `goToPage 被阻止: 划线悬浮窗显示中, target=${pageIndex}, source=${source}`);
      return;
    }
    // 安全检查
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) {
      logger.debug(TAG, `goToPage 被阻止: isAnimating=${this.isAnimating}, isPaginating=${this.isPaginating}, isLoading=${this.isLoading}, pages=${this.pages.length}`);
      return;
    }
    if (pageIndex < 0 || pageIndex >= this.totalPages) {
      return;
    }

    this.notifyUserPageTurnStartIfNeeded(source);
    this.isForward = pageIndex > this.currentPageIndex;
    this.performPageTurn(pageIndex);
  }

  private notifyUserPageTurnStartIfNeeded(source: string): void {
    if (source === 'manual') {
      this.onUserPageTurnStart();
    }
  }
  
  /**
  * 执行翻页动画
  */
  private performPageTurn(targetPageIndex: number): void {
    // 安全检查：确保目标页面有效
    if (targetPageIndex < 0 || targetPageIndex >= this.pages.length || this.pages.length === 0) {
      logger.warn(TAG, `performPageTurn: 无效的目标页面索引 ${targetPageIndex}, pages.length=${this.pages.length}`);
      return;
    }
    
    const animation = this.settings.pageTurnAnimation;
    
    switch (animation) {
      case TextPageTurnAnimation.NONE:
        this.performNoAnimation(targetPageIndex);
        break;
      case TextPageTurnAnimation.SLIDE:
        this.performSlideAnimation(targetPageIndex);
        break;
      case TextPageTurnAnimation.CURL:
        this.performCurlAnimation(targetPageIndex);
        break;
      case TextPageTurnAnimation.FADE:
        this.performFadeAnimation(targetPageIndex);
        break;
      default:
        this.performNoAnimation(targetPageIndex);
    }
  }
  
  /**
  * 无动画翻页
  */
  private performNoAnimation(targetPageIndex: number): void {
    // 安全检查
    if (this.pages.length === 0 || targetPageIndex < 0 || targetPageIndex >= this.pages.length) {
      logger.warn(TAG, 'performNoAnimation: invalid page data, skip');
      return;
    }
    
    this.currentPageIndex = targetPageIndex;
    this.updatePageContents();
    this.notifyPageChange();
  }
  
  /**
  * 滑动动画翻页
  */
  private performSlideAnimation(targetPageIndex: number): void {
    // 安全检查
    if (this.pages.length === 0 || targetPageIndex < 0 || targetPageIndex >= this.pages.length) {
      logger.warn(TAG, 'performSlideAnimation: invalid page data, skip');
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();// 启动动画超时保护
    const direction = this.isForward ? -1 : 1;
    const targetOffset = direction * this.componentWidth;
    const capturedVersion = this.paginationVersion;  // 捕获当前版本号，防止动画期间数据变化
    
    animateTo({
      duration: 300,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = targetOffset;
    });
    
    setTimeout(() => {
      // 检查版本号，如果已变化则取消
      if (capturedVersion !== this.paginationVersion || this.pages.length === 0) {
        logger.warn(TAG, 'performSlideAnimation: page data changed after animation, cancel update');
        this.slideOffset = 0;
        this.isAnimating = false;
        this.clearAnimationTimeout();
        return;
      }
      
      this.currentPageIndex = targetPageIndex;
      this.updatePageContents();
      this.slideOffset = 0;
      this.isAnimating = false;
      this.clearAnimationTimeout();
      this.notifyPageChange();
    }, 300);
  }
  
  /**
  * 淡入淡出动画翻页
  */
  private performFadeAnimation(targetPageIndex: number): void {
    // 安全检查
    if (this.pages.length === 0 || targetPageIndex < 0 || targetPageIndex >= this.pages.length) {
      logger.warn(TAG, 'performFadeAnimation: invalid page data, skip');
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();// 启动动画超时保护
    const capturedVersion = this.paginationVersion;
    
    animateTo({
      duration: 150,
      curve: Curve.EaseOut
    }, () => {
      this.slideOpacity = 0;
    });
    
    setTimeout(() => {
      // 检查版本号
      if (capturedVersion !== this.paginationVersion || this.pages.length === 0) {
        logger.warn(TAG, 'performFadeAnimation: page data changed after animation, cancel update');
        this.slideOpacity = 1;
        this.isAnimating = false;
        this.clearAnimationTimeout();
        return;
      }
      
      this.currentPageIndex = targetPageIndex;
      this.updatePageContents();
      
      animateTo({
        duration: 150,
        curve: Curve.EaseIn
      }, () => {
        this.slideOpacity = 1;
      });
      
      setTimeout(() => {
        this.isAnimating = false;
        this.clearAnimationTimeout();
        this.notifyPageChange();
      }, 150);
    }, 150);
  }
  
  /**
  * 完成滑动翻页（从当前拖拽位置继续动画到目标位置）
  * @param isForward true 表示向前翻页（下一页），false 表示向后翻页（上一页）
  */
  private completeSlidePageTurn(isForward: boolean): void {
    const targetPageIndex = isForward ? this.currentPageIndex + 1 : this.currentPageIndex - 1;
    
    logger.info(TAG, `completeSlidePageTurn: isForward=${isForward}, currentPage=${this.currentPageIndex}, targetPage=${targetPageIndex}, totalPages=${this.totalPages}, currentChapter=${this.currentChapterIndex}, totalChapters=${this.chapters.length}`);
    
      // 尝试切换到上一章节的最后一页
    if (targetPageIndex < 0) {
      // 尝试切换到上一章节的最后一页
      if (this.currentChapterIndex > 0) {
        logger.info(TAG, `completeSlidePageTurn: 已是第一章第一页，回弹`);
        this.switchToPrevChapter();
      } else {
        logger.info(TAG, `completeSlidePageTurn: 已是第一章第一页，回弹`);
        this.animateSlideBack();
      }
      return;
    }
    
    if (targetPageIndex >= this.totalPages) {
      // 尝试切换到下一章节的第一页
      if (this.chapters.length > 0 && this.currentChapterIndex < this.chapters.length - 1) {
        logger.info(TAG, `completeSlidePageTurn: 已是最后一章最后一页，回弹`);
        this.switchToNextChapter();
      } else {
        logger.info(TAG, `completeSlidePageTurn: 已是最后一章最后一页，回弹`);
        this.animateSlideBack();
      }
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();// 启动动画超时保护
    this.isForward = isForward;
    
    // 从当前位置继续滑动到目标位置
    const targetOffset = isForward ? -this.componentWidth : this.componentWidth;
    
    logger.info(TAG, `completeSlidePageTurn: 开始动画，targetOffset=${targetOffset}`);
    
    animateTo({
      duration: 200,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = targetOffset;
    });
    
    setTimeout(() => {
      this.currentPageIndex = targetPageIndex;
      this.updatePageContents();
      this.slideOffset = 0;
      this.isAnimating = false;
      this.clearAnimationTimeout();
      this.notifyPageChange();
      logger.info(TAG, `completeSlidePageTurn: 翻页完成，currentPage=${this.currentPageIndex}`);
    }, 200);
  }
  
  /**
  * 滑动回弹动画
  */
  private animateSlideBack(): void {
    animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.slideOffset = 0;
    });
  }
  
  /**
  * 切换到下一章节
  */
  private switchToNextChapter(): void {
    if (this.chapters.length === 0 || this.currentChapterIndex >= this.chapters.length - 1) {
      this.animateSlideBack();
      return;
    }
    
    const nextChapterIndex = this.currentChapterIndex + 1;
    const nextChapter = this.chapters[nextChapterIndex];
    const capturedVersion = this.paginationVersion;  // 捕获当前版本号，防止章节切换期间数据变化
    
    this.isAnimating = true;
    this.startAnimationTimeout();// 启动动画超时保护
    this.isForward = true;
    this.transitionDirection = true;
    this.transitionChapterName = nextChapter?.title || `第 ${nextChapterIndex + 1} 章`;
    
    // 第一步：滑动到过渡页
    animateTo({
      duration: 150,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = -this.componentWidth;
    });
    
    setTimeout(() => {
      // 检查是否被中断
      if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
        this.forceResetAnimationState();
        return;
      }
      
      // 显示过渡页
      this.isChapterTransition = true;
      this.slideOffset = 0;
      
        // 检查是否被中断
      setTimeout(() => {
        // 检查是否被中断
        if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
          this.forceResetAnimationState();
          return;
        }
        
        // 切换章节
        this.currentChapterIndex = nextChapterIndex;
        this.currentPageIndex = 0;
        
        // 延迟一帧后滑动出过渡页
        this.onChapterChange(this.currentChapterIndex);
        
          // 检查是否被中断
        setTimeout(() => {
            // 内容变化可能提前把 isAnimating 置为 false，仍需收敛章节过渡态
          if (!this.isAnimating) {
            // 内容变化可能提前把 isAnimating 置为 false，仍需收敛章节过渡态
            this.isChapterTransition = false;
            this.slideOffset = 0;
            this.clearAnimationTimeout();
            return;
          }
          
          this.slideOffset = this.componentWidth;
          animateTo({
            duration: 150,
            curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
          }, () => {
            this.slideOffset = 0;
          });
          
          setTimeout(() => {
            this.isChapterTransition = false;
            this.isAnimating = false;
            this.clearAnimationTimeout();
            logger.info(TAG, `switchToNextChapter: 切换到章节 ${this.currentChapterIndex}`);
          }, 150);
        }, 16);
      }, 100);
    }, 150);
  }
  
  /**
  * 切换到上一章节
  */
  private switchToPrevChapter(): void {
    if (this.chapters.length === 0 || this.currentChapterIndex <= 0) {
      this.animateSlideBack();
      return;
    }
    
    const prevChapterIndex = this.currentChapterIndex - 1;
    const prevChapter = this.chapters[prevChapterIndex];
    const capturedVersion = this.paginationVersion;  // 捕获当前版本号，防止章节切换期间数据变化
    
    this.isAnimating = true;
    this.startAnimationTimeout();// 启动动画超时保护
    this.isForward = false;
    this.transitionDirection = false;
    this.transitionChapterName = prevChapter?.title || `第 ${prevChapterIndex + 1} 章`;
    
    // 第一步：滑动到过渡页
    this.shouldJumpToLastPage = true;
    
    // 第一步：滑动到过渡页
    animateTo({
      duration: 150,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = this.componentWidth;
    });
    
    setTimeout(() => {
      // 检查是否被中断
      if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
        this.forceResetAnimationState();
        return;
      }
      
      // 显示过渡页
      this.isChapterTransition = true;
      this.slideOffset = 0;
      
        // 检查是否被中断
      setTimeout(() => {
        // 检查是否被中断
        if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
          this.forceResetAnimationState();
          return;
        }
        
        // 通知章节变化（外部会更新内容，分页完成后会检查 shouldJumpToLastPage）
        this.currentChapterIndex = prevChapterIndex;
        
        // 延迟一帧后滑动出过渡页
        this.onChapterChange(this.currentChapterIndex);
        
          // 检查是否被中断
        setTimeout(() => {
            // 内容变化可能提前把 isAnimating 置为 false，仍需收敛章节过渡态
          if (!this.isAnimating) {
            // 内容变化可能提前把 isAnimating 置为 false，仍需收敛章节过渡态
            this.isChapterTransition = false;
            this.slideOffset = 0;
            this.clearAnimationTimeout();
            return;
          }
          
          this.slideOffset = -this.componentWidth;
          animateTo({
            duration: 150,
            curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
          }, () => {
            this.slideOffset = 0;
          });
          
          setTimeout(() => {
            this.isChapterTransition = false;
            this.isAnimating = false;
            this.clearAnimationTimeout();
            logger.info(TAG, `switchToPrevChapter: switched to chapter ${this.currentChapterIndex}, jump to last page`);
          }, 150);
        }, 16);
      }, 100);
    }, 150);
  }
  
  /**
  * 卷页动画翻页（拟真翻页效果）
  * 支持交互式拖拽和自动动画两种模式
  */
  private performCurlAnimation(targetPageIndex: number): void {
    // 安全检查：确保页面数据有效
    if (this.pages.length === 0 || targetPageIndex < 0 || targetPageIndex >= this.pages.length) {
      logger.warn(TAG, 'performCurlAnimation: invalid page data, skip');
      return;
    }
    
    // 生成当前页和目标页的PixelMap
    this.checkAndInvalidatePixelMapCache();
    
      // 再次检查页面数据是否仍然有效（可能在异步过程中发生了章节切换）
    this.generatePagePixelMaps(this.currentPageIndex, targetPageIndex).then(() => {
      // 再次检查页面数据是否仍然有效（可能在异步过程中发生了章节切换）
      if (this.pages.length === 0 || this.isPaginating || this.isLoading) {
        logger.warn(TAG, 'performCurlAnimation: page data changed after async work, cancel');
        this.isAnimating = false;
        this.clearAnimationTimeout();
        return;
      }
      
      if (!this.currentPixelMap) {
        logger.warn(TAG, '无法生成页面PixelMap，降级到滑动动画');
        this.performSlideAnimation(targetPageIndex);
        return;
      }
      
      this.isAnimating = true;
      this.showCurlEffect = true;
      this.curlStartPosition = this.isForward ? CurlStartPosition.RIGHT_EDGE : CurlStartPosition.LEFT_EDGE;
      this.curlPendingPageIndex = targetPageIndex;
      this.curlProgress = 0;
      
      // 使用内部动画模式执行翻页
      this.curlAnimateFrom = 0;
      this.curlAnimateTarget = 1.0;
      this.startAnimationTimeout();

      const fallbackTargetPageIndex = targetPageIndex;
      const fallbackDelayMs = Math.max(420, this.novelCurlConfig.animationDuration + 140);
      this.curlAnimationTimer = setTimeout(() => {
        this.curlAnimationTimer = -1;
        if (!this.showCurlEffect || !this.isAnimating || this.curlPendingPageIndex !== fallbackTargetPageIndex) {
          return;
        }
        logger.warn(TAG, `performCurlAnimation fallback complete: ${this.currentPageIndex} -> ${fallbackTargetPageIndex}`);
        if (fallbackTargetPageIndex >= 0 && fallbackTargetPageIndex < this.totalPages) {
          this.currentPageIndex = fallbackTargetPageIndex;
          this.updatePageContents();
          this.notifyPageChange();
        }
        this.resetCurlState();
      }, fallbackDelayMs);
      
      logger.info(TAG, `执行卷页动画: ${this.currentPageIndex} -> ${targetPageIndex}`);
    }).catch((err: Error) => {
      logger.error(TAG, `生成页面PixelMap失败: ${err.message}`);
      this.isAnimating = false;
      this.clearAnimationTimeout();
      // 如果页面数据仍然有效，尝试降级到滑动动画
      if (this.pages.length > 0 && targetPageIndex < this.pages.length) {
        this.performSlideAnimation(targetPageIndex);
      }
    });
  }
  
  /**
  * 生成页面的PixelMap（用于卷页效果）
  * 使用 componentSnapshot.createFromBuilder 截取真实的页面渲染结果
  */
  private async generatePagePixelMaps(currentIndex: number, targetIndex: number): Promise<void> {
    if (this.isGeneratingPixelMap) {
      // 拖拽时会频繁触发，使用 debug 级别避免日志刷屏
      logger.debug(TAG, 'PixelMap is being cleaned up, skip new fetch');
      return;
    }
    
    // 捕获当前分页版本，用于检测异步过程中是否发生了章节切换
    const capturedVersion = this.paginationVersion;
    
    this.isGeneratingPixelMap = true;
    
    try {
      // 检查缓存
      const cachedCurrent = this.pagePixelMapCache.get(currentIndex);
      const cachedTarget = this.pagePixelMapCache.get(targetIndex);
      
      if (cachedCurrent) {
        this.currentPixelMap = cachedCurrent;
      } else {
        // 检查版本是否变化（章节切换）
        this.currentPixelMap = await this.renderPageToPixelMap(currentIndex);
        
        // 检查版本是否变化（章节切换）
        if (capturedVersion !== this.paginationVersion) {
          logger.warn(TAG, 'generatePagePixelMaps: 生成过程中发生章节切换，取消');
          return;
        }
        
        if (this.currentPixelMap) {
          this.pagePixelMapCache.set(currentIndex, this.currentPixelMap);
        }
      }
      
      // 再次检查版本
      if (capturedVersion !== this.paginationVersion) {
        logger.warn(TAG, 'generatePagePixelMaps: 生成过程中发生章节切换，取消');
        return;
      }
      
      if (cachedTarget) {
        this.nextPixelMap = cachedTarget;
      } else if (targetIndex >= 0 && targetIndex < this.totalPages) {
        // 检查版本是否变化
        this.nextPixelMap = await this.renderPageToPixelMap(targetIndex);
        
        // 检查版本是否变化
        if (capturedVersion !== this.paginationVersion) {
          logger.warn(TAG, 'generatePagePixelMaps: 生成过程中发生章节切换，取消');
          return;
        }
        
        if (this.nextPixelMap) {
          this.pagePixelMapCache.set(targetIndex, this.nextPixelMap);
        }
      }
      
      logger.info(TAG, `页面PixelMap生成完成: current=${this.currentPixelMap ? 'ok' : 'null'}, next=${this.nextPixelMap ? 'ok' : 'null'}`);
    } finally {
      this.isGeneratingPixelMap = false;
    }
  }
  
  /**
  * 预加载相邻页面的 PixelMap
  */
  private async preloadAdjacentPagePixelMaps(): Promise<void> {
    if (this.settings.pageTurnAnimation !== TextPageTurnAnimation.CURL) {
      return;
    }
    
    if (this.isDualPageMode()) {
      // 双页模式：预加载当前展开页 + 下一对 + 上一对（6 页）
      const base = this.dualPageBaseIndex;
      const pagesToPreload = [base, base + 1, base + 2, base + 3, base - 2, base - 1];
      
      for (const idx of pagesToPreload) {
        if (idx >= 0 && idx < this.totalPages && !this.pagePixelMapCache.has(idx)) {
          this.renderPageToPixelMap(idx).then(pm => {
            if (pm) {
              this.pagePixelMapCache.set(idx, pm);
            }
          });
        }
      }
      
      this.cleanupPixelMapCache(base, 5);
      return;
    }
    
    const currentIdx = this.currentPageIndex;
    const prevIdx = currentIdx - 1;
    const nextIdx = currentIdx + 1;
    
    // 预加载上一页
    if (prevIdx >= 0 && !this.pagePixelMapCache.has(prevIdx)) {
      this.renderPageToPixelMap(prevIdx).then(pm => {
        if (pm) {
          this.pagePixelMapCache.set(prevIdx, pm);
          this.prevPixelMap = pm;
        }
      });
    } else if (prevIdx >= 0) {
      this.prevPixelMap = this.pagePixelMapCache.get(prevIdx) || null;
    }
    
    // 预加载下一页
    if (nextIdx < this.totalPages && !this.pagePixelMapCache.has(nextIdx)) {
      this.renderPageToPixelMap(nextIdx).then(pm => {
        if (pm) {
          this.pagePixelMapCache.set(nextIdx, pm);
          this.nextPixelMap = pm;
        }
      });
    } else if (nextIdx < this.totalPages) {
      this.nextPixelMap = this.pagePixelMapCache.get(nextIdx) || null;
    }
    
    // 预加载当前页
    if (!this.pagePixelMapCache.has(currentIdx)) {
      this.renderPageToPixelMap(currentIdx).then(pm => {
        if (pm) {
          this.pagePixelMapCache.set(currentIdx, pm);
          this.currentPixelMap = pm;
        }
      });
    } else {
      this.currentPixelMap = this.pagePixelMapCache.get(currentIdx) || null;
    }
    
    // 清理过远的缓存（保留当前页前后各3页）
    this.cleanupPixelMapCache(currentIdx, 3);
  }
  
  /**
  * 清理过远的 PixelMap 缓存
  */
  private cleanupPixelMapCache(currentIndex: number, range: number): void {
    const keysToRemove: number[] = [];
    this.pagePixelMapCache.forEach((_, key) => {
      if (Math.abs(key - currentIndex) > range) {
        keysToRemove.push(key);
      }
    });
    
    for (const key of keysToRemove) {
      const pm = this.pagePixelMapCache.get(key);
      if (pm) {
        pm.release();
      }
      this.pagePixelMapCache.delete(key);
    }
  }
  
  /**
  * 将页面内容渲染为 PixelMap
  * 使用 componentSnapshot.createFromBuilder 截取真实的页面渲染
  */
  private async renderPageToPixelMap(pageIndex: number): Promise<image.PixelMap | null> {
    if (pageIndex < 0 || pageIndex >= this.pages.length) {
      return null;
    }
    
    const pageContent = this.pages[pageIndex]?.content || '';
    const width = Math.round(this.isDualPageMode() ? this.getDualPageWidth() : this.componentWidth);
    // 使用整个组件高度，通过 padding 避让底部信息栏（与实际显示一致）
    const height = Math.round(this.componentHeight);
    
    if (width <= 0 || height <= 0) {
      logger.warn(TAG, `组件尺寸无效: ${width}x${height}`);
      return null;
    }
    
    try {
      // 传递 pageIndex 以便在 PixelMap 中渲染页码
      // 传递 pageIndex 以便在 PixelMap 中渲染页码
      // 传递 pageIndex 以便在 PixelMap 中渲染页码
      const pixelMap: image.PixelMap = await componentSnapshot.createFromBuilder(
        () => { this.buildPageForSnapshot(pageContent, width, height, pageIndex); }
      );
      
      logger.info(TAG, `页面 ${pageIndex} PixelMap 生成成功`);
      return pixelMap;
    } catch (error) {
      logger.error(TAG, `渲染页面PixelMap失败: ${error instanceof Error ? error.message : String(error)}`);
      return null;
    }
  }
  
  /**
   * @param content 页面文本内容
   * @param width 页面宽度
   * @param height 页面高度
   * @param pageIndex 页码索引（用于在 PixelMap 中渲染页码）
   */
  @Builder
  buildPageForSnapshot(content: string, width: number, height: number, pageIndex: number = -1) {
    Stack() {
      // 背景层 - 始终显示底色
      Column()
        .width(width)
        .height(height)
        .backgroundColor(this.getBackgroundColor())
      
      // 图片背景层（如果有）
      if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
        Image(this.settings.background.imagePath.startsWith('/') 
          ? 'file://' + this.settings.background.imagePath 
          : this.settings.background.imagePath)
          .width(width)
          .height(height)
          .objectFit(ImageFit.Cover)
          .opacity(this.settings.background.imageOpacity ?? 1)
      }
      
      // 通过 padding 避让底部信息栏，与实际显示的 buildPageMode 一致
      // 通过 padding 避让底部信息栏，与实际显示的 buildPageMode 一致
      Text(content)
        .fontSize(this.settings.textStyle.fontSize)
        .fontColor(this.settings.textStyle.textColor)
        .lineHeight(this.getEffectiveTextLineHeight())
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .fontFamily(this.settings.textStyle.fontFamily)
        .textAlign(this.getTextAlign())
        .padding(this.getEffectiveContentPadding())
        .width(width)
        .height(height)
      
      // 页码层 - 渲染在 PixelMap 底部
      if (pageIndex >= 0) {
        Row() {
          Text(`${pageIndex + 1} / ${this.totalPages}`)
            .fontSize(12)
            .fontColor(this.settings.textStyle.textColor)
            .opacity(0.5)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 16, right: 16, bottom: 8 })
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }
    }
    .width(width)
    .height(height)
  }
  
  /**
  * 卷页动画完成回调
  */
  private onCurlAnimationComplete(): void {
    this.stopCurlAnimation();
    const targetIndex = this.curlPendingPageIndex;
    
    if (targetIndex >= 0 && targetIndex < this.totalPages) {
      this.currentPageIndex = targetIndex;
      this.updatePageContents();
      this.notifyPageChange();
    }
    
    // 重置状态
    setTimeout(() => {
      this.showCurlEffect = false;
      this.curlProgress = 0;
      this.curlAnimateTarget = -1;
      this.curlAnimateFrom = 0;
      this.curlPendingPageIndex = -1;
      this.isAnimating = false;
      this.clearAnimationTimeout();
      this.releasePixelMaps();
    }, 50);
  }
  
  /**
  * 卷页动画取消（回弹）
  */
  private animateCurlToCancel(): void {
    this.stopCurlAnimation();
    
    const startProgress = this.curlProgress;
    logger.info(TAG, `卷页回弹: progress=${startProgress.toFixed(2)}`);
    
    // 使用内部动画模式回弹
    this.curlAnimateFrom = startProgress;
    this.curlAnimateTarget = 0;
  }
  
  /**
  * 卷页动画完成（翻过去）
  */
  private animateCurlToComplete(): void {
    this.stopCurlAnimation();
    
    const startProgress = this.curlProgress;
    const targetIndex = this.curlPendingPageIndex;
    
    // 提前更新页面索引
    if (targetIndex >= 0 && targetIndex < this.totalPages) {
      this.currentPageIndex = targetIndex;
      this.updatePageContents();
      this.notifyPageChange();
    }
    
    logger.info(TAG, `卷页完成: progress=${startProgress.toFixed(2)}`);
    
    // 使用内部动画模式完成
    this.curlAnimateFrom = startProgress;
    this.curlAnimateTarget = 1.0;
  }
  
  /**
  * 停止卷页动画
  */
  private stopCurlAnimation(): void {
    if (this.curlAnimationTimer !== -1) {
      clearTimeout(this.curlAnimationTimer);
      this.curlAnimationTimer = -1;
    }
  }
  
  /**
  * 重置卷页状态
  */
  private resetCurlState(): void {
    this.stopCurlAnimation();
    this.showCurlEffect = false;
    this.curlProgress = 0;
    this.curlAnimateTarget = -1;
    this.curlAnimateFrom = 0;
    this.curlPendingPageIndex = -1;
    this.isAnimating = false;
    this.clearAnimationTimeout();
    this.releasePixelMaps();
  }
  
  /**
  * 更新卷页进度（实时拖拽）
  * 使用预加载的 PixelMap 提高响应速度
  */
  private updateCurlProgress(deltaX: number): void {
    const dragForward = deltaX < 0;// 向左拖拽为翻到下一页
    const dragDistance = Math.abs(deltaX);
    
    // 确定目标页面
    let targetIndex: number;
    let canFlip: boolean;
    
    if (dragForward) {
      targetIndex = this.currentPageIndex + 1;
      canFlip = targetIndex < this.totalPages;
      this.isForward = true;
      this.curlStartPosition = CurlStartPosition.RIGHT_EDGE;
    } else {
      targetIndex = this.currentPageIndex - 1;
      canFlip = targetIndex >= 0;
      this.isForward = false;
      this.curlStartPosition = CurlStartPosition.LEFT_EDGE;
    }
    
    if (!canFlip) {
      return;
    }
    
    // 计算卷曲进度
    let progress = dragDistance / this.componentWidth;
    progress = Math.max(0, Math.min(0.95, progress));
    
    // 当拖拽超过阈值时，显示卷页效果
    const showThreshold = 10;
    if (dragDistance > showThreshold) {
      if (!this.showCurlEffect) {
        // 检查背景设置是否变化，如果变化则清除缓存
        // 优先使用预加载的 PixelMap
        this.checkAndInvalidatePixelMapCache();
        // 优先使用预加载的 PixelMap
        const cachedCurrent = this.pagePixelMapCache.get(this.currentPageIndex);
        const cachedTarget = this.pagePixelMapCache.get(targetIndex);
        
        if (cachedCurrent) {
          // 使用缓存，立即进入卷页模式
          this.currentPixelMap = cachedCurrent;
          this.nextPixelMap = cachedTarget || null;
          this.showCurlEffect = true;
          this.curlPendingPageIndex = targetIndex;
          this.isAnimating = true;
          
          // 如果目标页没有缓存，异步加载
          if (!cachedTarget) {
            this.renderPageToPixelMap(targetIndex).then(pm => {
              if (pm) {
                this.pagePixelMapCache.set(targetIndex, pm);
                this.nextPixelMap = pm;
              }
            });
          }
          
          logger.debug(TAG, `进入卷页拖拽模式(缓存): ${this.currentPageIndex} -> ${targetIndex}`);
        } else {
          // 这样可以让用户立即看到翻页响应，而不是等待 PixelMap 生成
          // 这样可以让用户立即看到翻页响应，而不是等待 PixelMap 生成
          this.showCurlEffect = true;
          this.curlPendingPageIndex = targetIndex;
          this.isAnimating = true;
          
          this.generatePagePixelMaps(this.currentPageIndex, targetIndex).then(() => {
            if (this.currentPixelMap) {
              logger.debug(TAG, `卷页 PixelMap 生成完成: ${this.currentPageIndex} -> ${targetIndex}`);
            }
          });
          
          logger.debug(TAG, `进入卷页拖拽模式(待生成): ${this.currentPageIndex} -> ${targetIndex}`);
        }
      }
      
      if (this.showCurlEffect) {
        this.curlProgress = progress;
      }
    } else {
      if (this.showCurlEffect) {
        this.resetCurlState();
      }
    }
  }
  
  /**
  * 通知页面变化
  */
  private notifyPageChange(): void {
    this.dismissHighlightThoughtPopup();
    this.onPageChange(this.currentPageIndex, this.totalPages);
    this.notifyPageCharRangeChange();
    
    // 计算阅读进度
    let progress: number;
    if (this.isDualPageMode()) {
      const effectivePage = Math.min(this.dualPageBaseIndex + 2, this.totalPages);
      progress = this.totalPages > 0 ? effectivePage / this.totalPages * 100 : 0;
    } else {
      progress = this.totalPages > 0 ? (this.currentPageIndex + 1) / this.totalPages * 100 : 0;
    }
    this.onProgressChange(progress);
    
    // 预加载相邻页面的 PixelMap（用于卷页动画）
    this.preloadAdjacentPagePixelMaps();
    this.syncAutoPageTurnState('notify-page-change');
  }

  private notifyPageCharRangeChange(): void {
    if (this.pages.length === 0) {
      this.onPageCharRangeChange(0, 0);
      return;
    }

    let targetPageIndex = this.currentPageIndex;
    if (this.isDualPageMode()) {
      targetPageIndex = this.dualPageBaseIndex;
    }
    const safeIndex = Math.max(0, Math.min(targetPageIndex, this.pages.length - 1));
    const page = this.pages[safeIndex];
    this.onPageCharRangeChange(page.startCharIndex, page.endCharIndex);
  }
  
  // ========== 手势处理 ==========
  /**
  * 处理点击位置（简化版本，直接使用坐标）
  */
  private handleTapAtPosition(x: number, y: number): void {
    if (this.isHighlightThoughtPopupActive()) {
      return;
    }
    if (this.hasActiveSelectionRange()) {
      return;
    }
    if (!this.settings.tapToTurn) {
      // 创建简单的点击事件对象传递给回调
      this.onTapSimple();
      return;
    }
    
    // 防护：如果组件宽度未初始化，默认触发中间区域点击
    if (this.componentWidth <= 0) {
      logger.warn(TAG, `handleTapAtPosition: componentWidth=${this.componentWidth}，组件尺寸未初始化，触发中间区域点击`);
      this.onTapSimple();
      return;
    }
    
    const screenThird = this.componentWidth / 3;
    logger.debug(TAG, `handleTapAtPosition: x=${x.toFixed(0)}, componentWidth=${this.componentWidth.toFixed(0)}, screenThird=${screenThird.toFixed(0)}`);
    
    if (x < screenThird) {
      // 点击左侧区域
      if (this.settings.readingDirection === TextReadingDirection.HORIZONTAL) {
        this.goToPrevPage();
      } else {
        this.goToNextPage();
      }
    } else if (x > screenThird * 2) {
      // 点击右侧区域
      if (this.settings.readingDirection === TextReadingDirection.HORIZONTAL) {
        this.goToNextPage();
      } else {
        this.goToPrevPage();
      }
    } else {
      // 点击中间区域，触发回调（通常用于显示工具栏）
      this.onTapSimple();
    }
  }
  
  /**
  * 点击中间区域回调（用于显示/隐藏工具栏）
  */
  private onTapSimple(): void {
    if (this.isHighlightThoughtPopupActive()) {
      return;
    }
    // TextReaderComponent 内部已经处理了点击区域判断，外部只需要知道"用户点击了中间区域"
    // TextReaderComponent 内部已经处理了点击区域判断，外部只需要知道"用户点击了中间区域"
    this.resetAutoPageTurnTimerForInteraction('tap-center');
    this.onTapCenter();
  }

  /**
   * Whether a text selection range is active.
   * Used to block page-turn gestures while dragging selection handles.
   */
  private hasActiveSelectionRange(): boolean {
    return this.selectionStart >= 0 && this.selectionEnd > this.selectionStart;
  }
  
  /**
  * 处理滑动手势开始
  */
  private handlePanStart(event: GestureEvent): void {
    if (this.isHighlightThoughtPopupActive()) {
      this.isDragging = false;
      return;
    }
    if (this.hasActiveSelectionRange()) {
      this.isDragging = false;
      logger.debug(TAG, 'handlePanStart: skip page turn while text selection is active');
      return;
    }
    logger.info(TAG, `handlePanStart: offsetX=${event.offsetX}, offsetY=${event.offsetY}`);
    this.touchStartX = event.offsetX;
    this.touchStartY = event.offsetY;
    this.initialTouchX = event.offsetX;// 记录初始触摸位置用于卷页拖拽
    // 记录卷曲触摸点（用于从触摸位置开始卷曲）
    this.curlTouchX = event.fingerList[0]?.localX || event.offsetX;
    this.curlTouchY = event.fingerList[0]?.localY || event.offsetY;
    this.panStartTime = Date.now();
    this.isDragging = true;
    this.resetAutoPageTurnTimerForInteraction('pan-start');
  }
  
  /**
  * 处理滑动手势移动
  */
  private handlePanUpdate(event: GestureEvent): void {
    if (this.isHighlightThoughtPopupActive()) {
      this.isDragging = false;
      return;
    }
    if (this.hasActiveSelectionRange()) {
      this.isDragging = false;
      return;
    }
    if (!this.isDragging) {
      return;
    }
    
    const deltaX = event.offsetX - this.initialTouchX;
    
    if (this.settings.readingMode === TextReadingMode.PAGE) {
        // 如果已经在卷页动画中（非拖拽触发），不处理
      if (this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL) {
        // 如果已经在卷页动画中（非拖拽触发），不处理
        if (this.isAnimating && !this.showCurlEffect) {
          return;
        }
        // 动态更新手指Y坐标，让折叠角度跟随手指移动
        this.curlTouchY = event.fingerList[0]?.localY || this.curlTouchY;
        this.updateCurlProgress(deltaX);
        return;
      }
      
      // 滑动动画模式
      if (this.settings.pageTurnAnimation === TextPageTurnAnimation.SLIDE) {
        if (this.isAnimating) {
          return;
        }
        // 限制拖拽范围
        const maxOffset = this.componentWidth;
        this.slideOffset = Math.max(-maxOffset, Math.min(maxOffset, deltaX));
        logger.debug(TAG, `handlePanUpdate: slideOffset=${this.slideOffset.toFixed(2)}`);
      }
    }
    
    // 双页模式卷页拖拽
    if (this.settings.readingMode === TextReadingMode.DUAL_PAGE &&
        this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL) {
      if (this.isAnimating && !this.showCurlEffect) {
        return;
      }
      this.curlTouchY = event.fingerList[0]?.localY || this.curlTouchY;
      this.updateDualCurlProgress(deltaX);
    }
  }
  
  /**
  * 处理滑动手势结束
  */
  private handlePanEnd(event: GestureEvent): void {
    if (this.isHighlightThoughtPopupActive()) {
      this.isDragging = false;
      return;
    }
    if (this.hasActiveSelectionRange()) {
      this.isDragging = false;
      logger.debug(TAG, 'handlePanEnd: skip page turn while text selection is active');
      return;
    }
    logger.info(TAG, `handlePanEnd called: isDragging=${this.isDragging}, offsetX=${event.offsetX}, initialTouchX=${this.initialTouchX}`);
    
    if (!this.isDragging) {
      logger.info(TAG, `handlePanEnd: isDragging is false, returning`);
      return;
    }
    
    this.isDragging = false;
    
    const deltaX = event.offsetX - this.initialTouchX;
    const threshold = this.componentWidth * 0.2;
    const flipThreshold = this.novelCurlConfig.flipThreshold;// 使用小说专用卷页阈值
    
    logger.info(TAG, `handlePanEnd: deltaX=${deltaX.toFixed(2)}, threshold=${threshold.toFixed(2)}, componentWidth=${this.componentWidth}, animation=${this.settings.pageTurnAnimation}, readingMode=${this.settings.readingMode}`);
    
    // 只在翻页模式下处理翻页
    if (this.settings.readingMode !== TextReadingMode.PAGE) {
      logger.info(TAG, 'handlePanEnd: not page mode, skip');
      return;
    }
    
      // 快速翻页检测：小范围快速滑动也能触发翻页
    if (this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL && this.showCurlEffect) {
      // 快速翻页检测：小范围快速滑动也能触发翻页
      const elapsed: number = Math.max(Date.now() - this.panStartTime, 1);
      const swipeDist: number = Math.abs(event.offsetX - this.initialTouchX);
      const velocity: number = swipeDist / elapsed;  // px/ms
      const isQuickFlip: boolean = velocity > 0.35 && swipeDist > 25 && this.curlProgress > 0.02;
      if (this.curlProgress >= flipThreshold || isQuickFlip) {
        // 超过阈值 或 快速滑动，完成翻页
        if (isQuickFlip && this.curlProgress < flipThreshold) {
          logger.info(TAG, `小说快速翻页: velocity=${velocity.toFixed(2)}px/ms, dist=${swipeDist.toFixed(0)}, progress=${this.curlProgress.toFixed(2)}`);
        }
        this.animateCurlToComplete();
      } else {
        // 未超过阈值且非快速滑动，回弹
        this.animateCurlToCancel();
      }
      return;
    }
    
    // 卷页动画模式 - 但没有显示卷页效果（可能是边界页面，需要跨章节）
    if (this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL) {
      logger.info(TAG, `handlePanEnd: 卷页模式但无卷页效果，检查是否需要跨章节翻页`);
      if (Math.abs(deltaX) > threshold) {
        // 使用滑动翻页逻辑处理跨章节
        this.completeSlidePageTurn(deltaX < 0);
      }
      return;
    }
    
    // 滑动动画模式
    if (this.settings.pageTurnAnimation === TextPageTurnAnimation.SLIDE) {
      logger.info(TAG, `handlePanEnd: 滑动模式，|deltaX|=${Math.abs(deltaX).toFixed(2)} > threshold=${threshold.toFixed(2)} ? ${Math.abs(deltaX) > threshold}`);
      if (Math.abs(deltaX) > threshold) {
        // 回弹
        this.completeSlidePageTurn(deltaX < 0);
      } else {
        // 回弹
        animateTo({
          duration: 200,
          curve: Curve.EaseOut
        }, () => {
          this.slideOffset = 0;
        });
      }
      return;
    }
    
        // 向左滑动，下一页
    if (Math.abs(deltaX) > threshold) {
      if (deltaX < 0) {
        // 向右滑动，上一页
        this.goToNextPage();
      } else {
        // 向右滑动，上一页
        this.goToPrevPage();
      }
    }
  }
  
  // ========== 资源管理 ==========
  /**
  * 释放当前使用的 PixelMap 引用（不释放缓存）
  */
  private releasePixelMaps(): void {
    // 只清除引用，不释放缓存中的 PixelMap
    this.currentPixelMap = null;
    this.nextPixelMap = null;
    this.prevPixelMap = null;
  }
  
  /**
  * 释放所有 PixelMap 缓存（组件销毁时调用）
  */
  private releaseAllPixelMapCache(): void {
    this.pagePixelMapCache.forEach((pm) => {
      pm.release();
    });
    this.pagePixelMapCache.clear();
    this.currentPixelMap = null;
    this.nextPixelMap = null;
    this.prevPixelMap = null;
  }
  
  /**
  * 获取渲染设置签名（用于检测影响 PixelMap 渲染的设置变化）
  * 包含：背景设置、文字样式（颜色、字号、行高、字间距、字重、字体、字体路径、对齐方式）、页边距
  */
  private getRenderSignature(): string {
    const bg = this.settings.background;
    const ts = this.settings.textStyle;
    const pm = this.settings.pageMargins;
    return `${bg.type}|${bg.color}|${bg.imagePath}|${bg.imageOpacity}|` +
           `${ts.textColor}|${ts.fontSize}|${ts.lineHeight}|${ts.letterSpacing}|${ts.fontWeight}|${ts.fontFamily}|${ts.fontPath || ''}|${ts.textAlignment}|` +
           `${pm.top}|${pm.bottom}|${pm.left}|${pm.right}`;
  }
  
  /**
  * 检查渲染设置是否变化，如果变化则清除 PixelMap 缓存
  * 优化：如果正在卷页动画中，不清除缓存（避免动画中断）
  */
  private checkAndInvalidatePixelMapCache(): void {
    // 如果正在卷页动画中，不清除缓存
    if (this.showCurlEffect) {
      return;
    }
    
    const currentSignature = this.getRenderSignature();
    if (this.lastRenderSignature !== currentSignature) {
      // 首次初始化时不记录清除日志
      if (this.lastRenderSignature !== '') {
        logger.info(TAG, `渲染设置变化，清除 PixelMap 缓存`);
        this.releaseAllPixelMapCache();
        // 设置变化时重新注册自定义字体
        this.registerCustomFontIfNeeded();
      }
      this.lastRenderSignature = currentSignature;
      // 重新预加载
      this.preloadAdjacentPagePixelMaps();
    }
  }
  
  // ========== 辅助方法 ==========
  /**
  * 获取背景样式（仅用于纯色背景模式）
  */
  private getBackgroundColor(): ResourceColor {
    const bg = this.settings.background;
    if (bg.type === BackgroundType.COLOR && bg.color) {
      return bg.color;
    }
    return '#F5F0E1';
  }
  
  /**
  * 获取内容区背景色（图片背景时返回透明）
  */
  private getContentBackgroundColor(): ResourceColor {
    if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
      return Color.Transparent;
    }
    return this.getBackgroundColor();
  }
  
  /**
  * 将文本分段（用于滚动模式优化）
  */
  private getTextSegments(): string[] {
    if (!this.content) {
      return [];
    }
    
    // 每段最多5000字符，按段落分割
    const maxCharsPerSegment = 5000;
    const paragraphs = this.content.split(/\n/);
    const segments: string[] = [];
    let currentSegment = '';
    
    for (const para of paragraphs) {
      if (currentSegment.length + para.length > maxCharsPerSegment && currentSegment.length > 0) {
        segments.push(currentSegment);
        currentSegment = para;
      } else {
        currentSegment += (currentSegment.length > 0 ? '\n' : '') + para;
      }
    }
    
    if (currentSegment.length > 0) {
      segments.push(currentSegment);
    }
    
    return segments.length > 0 ? segments : [this.content];
  }
  
  /**
  * 获取有效的底部状态栏高度
  * 只有当底部信息显示开启时才返回高度
  */
  private getEffectiveBottomBarHeight(): number {
    const hasBottomInfo = this.settings.showPageNumber || 
                          this.settings.showProgress || 
                          this.settings.showTime || 
                          this.settings.showBattery;
    return hasBottomInfo ? this.bottomStatusBarHeight : 0;
  }
  
  /**
  * 获取文字对齐方式
  */
  private getTextAlign(): TextAlign {
    switch (this.settings.textStyle.textAlignment) {
      case TextAlignment.LEFT:
        return TextAlign.Start;
      case TextAlignment.CENTER:
        return TextAlign.Center;
      case TextAlignment.RIGHT:
        return TextAlign.End;
      case TextAlignment.JUSTIFY:
        return TextAlign.JUSTIFY;
      default:
        return TextAlign.Start;
    }
  }
  
  /**
  * 是否为双页模式
  */
  private isDualPageMode(): boolean {
    return this.settings.readingMode === TextReadingMode.DUAL_PAGE;
  }
  
  /**
  * 获取双页模式下单页宽度
  */
  private getDualPageWidth(): number {
    return Math.floor(this.componentWidth / 2);
  }
  
  /**
  * 更新双页模式左右页内容
  */
  private updateDualPageContents(): void {
    if (this.pages.length === 0) {
      this.dualLeftPageContent = '';
      this.dualRightPageContent = '';
      return;
    }
    
    // 确保 baseIndex 为偶数
    this.dualPageBaseIndex = Math.max(0, this.dualPageBaseIndex - (this.dualPageBaseIndex % 2));
    
    const isRTL = this.settings.readingDirection === TextReadingDirection.HORIZONTAL;
    // RTL方向暂不考虑，默认 LTR
    // RTL方向暂不考虑，默认 LTR
    this.dualLeftPageIndex = this.dualPageBaseIndex;
    this.dualRightPageIndex = this.dualPageBaseIndex + 1;
    
    this.dualLeftPageContent = this.dualLeftPageIndex < this.pages.length
      ? (this.pages[this.dualLeftPageIndex]?.content || '') : '';
    this.dualRightPageContent = this.dualRightPageIndex < this.pages.length
      ? (this.pages[this.dualRightPageIndex]?.content || '') : '';
    
    // 同步 currentPageIndex 为 baseIndex（便于外部进度记录）
    this.currentPageIndex = this.dualPageBaseIndex;
    this.lastExternalPageIndex = this.currentPageIndex;
    
    logger.debug(TAG, `双页内容更新: left=${this.dualLeftPageIndex}, right=${this.dualRightPageIndex}, total=${this.totalPages}`);
  }
  
  /**
  * 双页模式翻到下一对页面
  */
  private goToNextDualPage(source: string = 'manual'): void {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, `goToNextDualPage 被阻止: 划线悬浮窗显示中, source=${source}`);
      return;
    }
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) return;
    
    const nextBase = this.dualPageBaseIndex + 2;
    if (nextBase >= this.totalPages) {
      // 已是最后一对，尝试章节切换
      if (this.chapters.length > 0 && this.currentChapterIndex < this.chapters.length - 1) {
        this.switchToNextChapter();
      } else {
        this.provideBoundaryFeedback();
      }
      return;
    }

    this.notifyUserPageTurnStartIfNeeded(source);
    this.isForward = true;
    this.dualAnimSide = 'right';
    this.performDualPageTurn(nextBase);
  }
  
  /**
  * 双页模式翻到上一对页面
  */
  private goToPrevDualPage(source: string = 'manual'): void {
    if (this.isHighlightThoughtPopupActive()) {
      logger.debug(TAG, `goToPrevDualPage 被阻止: 划线悬浮窗显示中, source=${source}`);
      return;
    }
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) return;
    
    const prevBase = this.dualPageBaseIndex - 2;
    if (prevBase < 0) {
      // 已是第一对，尝试章节切换
      if (this.currentChapterIndex > 0) {
        this.shouldJumpToLastPage = true;
        this.switchToPrevChapter();
      } else {
        this.provideBoundaryFeedback();
      }
      return;
    }

    this.notifyUserPageTurnStartIfNeeded(source);
    this.isForward = false;
    this.dualAnimSide = 'left';
    this.performDualPageTurn(prevBase);
  }
  
  /**
  * 执行双页翻页动画
  */
  private performDualPageTurn(targetBase: number): void {
    const animation = this.settings.pageTurnAnimation;
    const halfWidth = this.getDualPageWidth();
    
    if (animation === TextPageTurnAnimation.SLIDE) {
      // 滑动动画
      this.isAnimating = true;
      this.startAnimationTimeout();
      
      // 准备动画下方层的内容（即目标页对内容）
      this.dualUnderLeftContent = targetBase < this.pages.length ? (this.pages[targetBase]?.content || '') : '';
      this.dualUnderRightContent = (targetBase + 1) < this.pages.length ? (this.pages[targetBase + 1]?.content || '') : '';
      
      const targetOffset = this.isForward ? -halfWidth : halfWidth;
      
      animateTo({
        duration: 300,
        curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
      }, () => {
        this.dualSlideOffset = targetOffset;
      });
      
      setTimeout(() => {
        this.dualPageBaseIndex = targetBase;
        this.updateDualPageContents();
        this.dualSlideOffset = 0;
        this.isAnimating = false;
        this.clearAnimationTimeout();
        this.notifyPageChange();
      }, 300);
    } else if (animation === TextPageTurnAnimation.FADE) {
      // 淡入淡出动画
      this.isAnimating = true;
      this.startAnimationTimeout();
      
      animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.slideOpacity = 0;
      });
      
      setTimeout(() => {
        this.dualPageBaseIndex = targetBase;
        this.updateDualPageContents();
        animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
          this.slideOpacity = 1;
        });
        setTimeout(() => {
          this.isAnimating = false;
          this.clearAnimationTimeout();
          this.notifyPageChange();
        }, 150);
      }, 150);
    } else if (animation === TextPageTurnAnimation.CURL) {
      // 无动画
      this.performDualCurlAnimation(targetBase);
    } else {
      // 无动画
      this.dualPageBaseIndex = targetBase;
      this.updateDualPageContents();
      this.notifyPageChange();
    }
  }
  
  /**
  * 双页模式手势点击处理
  */
  private handleDualPageTap(x: number, _y: number): void {
    if (this.isHighlightThoughtPopupActive()) {
      return;
    }
    if (this.hasActiveSelectionRange()) {
      return;
    }
    const halfWidth = this.getDualPageWidth();
    const isLeftSide = x < halfWidth;
    
    if (isLeftSide) {
        // 左页左侧1/3：上一页对
      const leftThird = halfWidth / 3;
      if (x < leftThird) {
        // 左页右侧1/3（靠近中缝）：显示工具栏
        this.goToPrevDualPage();
      } else if (x > halfWidth - leftThird) {
        // 左页右侧1/3（靠近中缝）：显示工具栏
        this.onTapSimple();
      } else {
        this.onTapSimple();
      }
    } else {
      // 右半区域
      const rightX = x - halfWidth;
      const rightThird = halfWidth / 3;
      if (rightX > halfWidth - rightThird) {
        // 右页左侧1/3（靠近中缝）：显示工具栏
        this.goToNextDualPage();
      } else if (rightX < rightThird) {
        // 右页左侧1/3（靠近中缝）：显示工具栏
        this.onTapSimple();
      } else {
        this.onTapSimple();
      }
    }
  }
  
  /**
  * 双页模式滑动手势结束处理
  */
  private handleDualPagePanEnd(deltaX: number): void {
    if (this.isHighlightThoughtPopupActive()) {
      return;
    }
    // 双页卷页动画完成/取消
    if (this.showCurlEffect && this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL) {
      const flipThreshold = this.novelCurlConfig.flipThreshold;
      const elapsed = Math.max(Date.now() - this.panStartTime, 1);
      const swipeDist = Math.abs(deltaX);
      const velocity = swipeDist / elapsed;
      const isQuickFlip = velocity > 0.35 && swipeDist > 25 && this.curlProgress > 0.02;
      
      if (this.curlProgress >= flipThreshold || isQuickFlip) {
        this.animateDualCurlToComplete();
      } else {
        // 回弹取消：父组件驱动动画回弹到 0，完成后重置双页卷页状态
        this.animateDualCurlProgressTo(0, () => {
          this.resetDualCurlState();
        });
      }
      return;
    }
    
    const halfWidth = this.getDualPageWidth();
    const threshold = halfWidth * 0.2;
    
    if (Math.abs(deltaX) > threshold) {
      if (deltaX < 0) {
        this.goToNextDualPage();
      } else {
        this.goToPrevDualPage();
      }
    }
  }
  
  /**
  * 双页滑动动画（提取公用 + 卷页降级备用）
  */
  private performDualSlideAnimation(targetBase: number): void {
    const halfWidth = this.getDualPageWidth();
    this.isAnimating = true;
    this.startAnimationTimeout();
    
    this.dualUnderLeftContent = targetBase < this.pages.length ? (this.pages[targetBase]?.content || '') : '';
    this.dualUnderRightContent = (targetBase + 1) < this.pages.length ? (this.pages[targetBase + 1]?.content || '') : '';
    
    const targetOffset = this.isForward ? -halfWidth : halfWidth;
    
    animateTo({
      duration: 300,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.dualSlideOffset = targetOffset;
    });
    
    setTimeout(() => {
      this.dualPageBaseIndex = targetBase;
      this.updateDualPageContents();
      this.dualSlideOffset = 0;
      this.isAnimating = false;
      this.clearAnimationTimeout();
      this.notifyPageChange();
    }, 300);
  }
  
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
  * 父组件驱动的双页卷页动画
  * 直接更新 curlProgress（映射到子组件的 externalProgress），完全绕过 @Watch/onReady 竞态
  */
  private animateDualCurlProgressTo(target: number, onComplete: () => void): void {
    this.stopDualCurlAnimation();
    
    const start: number = this.curlProgress;
    const delta: number = Math.abs(target - start);
    
    if (delta < 0.01) {
      this.curlProgress = target;
      onComplete();
      return;
    }
    
    const isForwardAnim: boolean = target > start;
    // - 第二阶段(0.5→1.0)：页面从书脊继续翻转落下
    // 设置最小时长确保动画可见
    // 设置最小时长确保动画可见
    // 设置最小时长确保动画可见
    const minDuration: number = isForwardAnim ? 450 : 250;
    const rawDuration: number = isForwardAnim
      ? this.novelCurlConfig.animationDuration * delta * 2.0// 增加系数
      : this.novelCurlConfig.animationDuration * delta;
    const duration: number = Math.max(minDuration, rawDuration);
    const startTime: number = Date.now();
    
    const animate = (): void => {
      const elapsed: number = Date.now() - startTime;
      const t: number = Math.min(elapsed / Math.max(duration, 50), 1.0);
      let eased: number;
      if (isForwardAnim) {
        // 弹簧过冲缓动
        const decay: number = Math.exp(-4.5 * t);
        const oscillation: number = Math.cos(3.5 * Math.PI * t);
        eased = 1 - decay * oscillation;
      } else {
        eased = 1 - Math.pow(1 - t, 3); // easeOutCubic
      }
      
      this.curlProgress = start + (target - start) * eased;
      
      if (t < 1.0) {
        const frameProcessTime: number = Date.now() - (startTime + elapsed);
        this.dualCurlAnimTimer = setTimeout(animate, Math.max(1, 16 - frameProcessTime));
      } else {
        this.curlProgress = target;
        this.dualCurlAnimTimer = -1;
        onComplete();
      }
    };
    
    animate();
  }
  
  /**
   * 动画由父组件定时器驱动 curlProgress，而非子组件内部 @Watch
   */
  private performDualCurlAnimation(targetBase: number): void {
    logger.info(TAG, `[双页卷页] 开始: base=${this.dualPageBaseIndex}, target=${targetBase}, forward=${this.isForward}, size=${this.componentWidth}x${this.componentHeight}`);
    
    // 提前设置 isAnimating，防止 PixelMap 生成期间用户重复触发翻页
    this.isAnimating = true;
    this.checkAndInvalidatePixelMapCache();
    this.curlTouchY = this.componentHeight / 2;
    
    this.generateDualCurlPixelMaps(this.dualPageBaseIndex, targetBase).then(ok => {
      logger.info(TAG, `[双页卷页] PixelMap结果: ok=${ok}, L=${this.dualCurlLeftPM !== null}, R=${this.dualCurlRightPM !== null}, NL=${this.dualCurlNextLeftPM !== null}, NR=${this.dualCurlNextRightPM !== null}`);
      
      if (!ok || this.pages.length === 0 || this.isPaginating || this.isLoading) {
        logger.warn(TAG, `[双页卷页] 降级滑动: ok=${ok}, pages=${this.pages.length}, paging=${this.isPaginating}, loading=${this.isLoading}`);
        this.isAnimating = false;
        this.performDualSlideAnimation(targetBase);
        return;
      }
      
      this.showCurlEffect = true;
      this.curlPendingPageIndex = targetBase;
      this.curlProgress = 0;
      
      logger.info(TAG, `[双页卷页] showCurlEffect=true, 延迟50ms启动动画`);
      
      // 可能阻塞 UI 线程导致 Canvas onReady 延迟甚至无法触发
      // 可能阻塞 UI 线程导致 Canvas onReady 延迟甚至无法触发
      // 可能阻塞 UI 线程导致 Canvas onReady 延迟甚至无法触发
      setTimeout(() => {
          logger.info(TAG, `[双页卷页] 动画完成`);
        this.animateDualCurlProgressTo(1.0, () => {
          logger.info(TAG, `[双页卷页] 动画完成`);
          this.onDualCurlAnimationComplete();
        });
      }, 50);
    }).catch((err: Error) => {
      logger.error(TAG, `[双页卷页] 异常: ${err}`);
      this.isAnimating = false;
      this.performDualSlideAnimation(targetBase);
    });
  }
  
  /**
  * 生成双页卷页所需的 4 张 PixelMap
  */
  private async generateDualCurlPixelMaps(currentBase: number, targetBase: number): Promise<boolean> {
    const indices = [currentBase, currentBase + 1, targetBase, targetBase + 1];
    const results: (image.PixelMap | null)[] = [];
    
    for (const idx of indices) {
      if (idx < 0 || idx >= this.totalPages) {
        results.push(null);
        continue;
      }
      
      const cached = this.pagePixelMapCache.get(idx);
      if (cached) {
        results.push(cached);
      } else {
        const pm = await this.renderPageToPixelMap(idx);
        if (pm) {
          this.pagePixelMapCache.set(idx, pm);
        }
        results.push(pm);
      }
    }
    
    this.dualCurlLeftPM = results[0];
    this.dualCurlRightPM = results[1];
    this.dualCurlNextLeftPM = results[2];
    this.dualCurlNextRightPM = results[3];
    
    // 至少需要当前翻起页的 PixelMap
    const turningPM = this.isForward ? this.dualCurlRightPM : this.dualCurlLeftPM;
    return turningPM !== null;
  }
  
  /**
  * 双页卷页拖拽进度更新
  */
  private updateDualCurlProgress(deltaX: number): void {
    const halfWidth = this.getDualPageWidth();
    const dragForward = deltaX < 0;
    const dragDistance = Math.abs(deltaX);
    
    const nextBase = dragForward ? this.dualPageBaseIndex + 2 : this.dualPageBaseIndex - 2;
    const canFlip = dragForward ? nextBase < this.totalPages : nextBase >= 0;
    
    if (!canFlip) return;
    
    this.isForward = dragForward;
    this.dualAnimSide = dragForward ? 'right' : 'left';
    
    let progress = dragDistance / halfWidth;
    progress = Math.max(0, Math.min(0.95, progress));
    
    const showThreshold = 10;
    if (dragDistance > showThreshold) {
      if (!this.showCurlEffect) {
        this.checkAndInvalidatePixelMapCache();
        this.curlPendingPageIndex = nextBase;
        this.isAnimating = true;
        this.showCurlEffect = true;
        
        // 异步生成 4 张 PixelMap
        this.generateDualCurlPixelMaps(this.dualPageBaseIndex, nextBase).then(ok => {
          if (ok) {
            logger.debug(TAG, `双页卷页 PixelMap 生成完成`);
          }
        });
      }
      
      if (this.showCurlEffect) {
        this.curlProgress = progress;
      }
    } else {
      if (this.showCurlEffect) {
        this.resetDualCurlState();
      }
    }
  }
  
  /**
   * 时序关键：必须在同一帧内完成以下操作：
   * 
   * 2. 然后关闭动画层（showCurlEffect = false）
   * 
   * 这样当 Canvas 层被移除时，底层 UI 已经显示新页面内容，不会闪烁。
   * 
   */
  private onDualCurlAnimationComplete(): void {
    const targetBase = this.curlPendingPageIndex;
    logger.info(TAG, `[onDualCurlAnimationComplete] 开始: targetBase=${targetBase}, showCurlEffect=${this.showCurlEffect}, isAnimating=${this.isAnimating}`);
    
    // 1. 先更新页面内容（此时 Canvas 层仍然覆盖在上面，用户看不到底层变化）
    if (targetBase >= 0) {
      logger.info(TAG, `[onDualCurlAnimationComplete] 1.更新页面内容: base ${this.dualPageBaseIndex} -> ${targetBase}`);
      this.dualPageBaseIndex = targetBase;
      this.updateDualPageContents();
      this.notifyPageChange();
    }
    
    // 2. 然后关闭动画层（底层已显示新内容，无缝过渡）
    logger.info(TAG, '[onDualCurlAnimationComplete] 2. close animation layer');
    this.showCurlEffect = false;
    this.curlProgress = 0;
    this.stopDualCurlAnimation();
    
    // 3. 完整重置状态
    logger.info(TAG, '[onDualCurlAnimationComplete] 3. reset state');
    this.curlAnimateTarget = -1;
    this.curlAnimateFrom = 0;
    this.curlPendingPageIndex = -1;
    this.isAnimating = false;
    
    // 4. 清除双页卷页 PixelMap 引用
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;
    logger.info(TAG, `[onDualCurlAnimationComplete] 完成`);
  }
  
  /**
  * 双页卷页完成动画（松手后继续翻到底）
  */
  private animateDualCurlToComplete(): void {
    this.stopDualCurlAnimation();
    
    // 底层 Row 会立即显示新页内容，导致用户看到“直接翻页”而不是卷曲动画。
    // 页面内容应该在动画完成后由 onDualCurlAnimationComplete 统一更新。
    // 页面内容应该在动画完成后由 onDualCurlAnimationComplete 统一更新。
    // 父组件驱动动画继续到 1.0
    
    // 父组件驱动动画继续到 1.0
    this.animateDualCurlProgressTo(1.0, () => {
      this.onDualCurlAnimationComplete();
    });
  }
  
  /**
  * 重置双页卷页状态（清理 4 张 PixelMap 引用）
  */
  private resetDualCurlState(): void {
    this.stopDualCurlAnimation();
    this.showCurlEffect = false;
    this.curlProgress = 0;
    this.curlAnimateTarget = -1;
    this.curlAnimateFrom = 0;
    this.curlPendingPageIndex = -1;
    this.isAnimating = false;
    // 清除双页卷页 PixelMap 引用（不释放缓存，由 cache 管理生命周期）
    this.dualCurlLeftPM = null;
    this.dualCurlRightPM = null;
    this.dualCurlNextLeftPM = null;
    this.dualCurlNextRightPM = null;
  }
  
    // 使用 Stack 布局：所有层叠加，底部信息栏使用 position 定位
  build() {
      // 背景层 - 图片模式下需要底色保证文字可读性
    Stack() {
        // 底层：半透明底色，确保文字可读
      if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
        // 底层：半透明底色，确保文字可读
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#F5F0E1')
        
        // 图片层：独立的不透明度控制（沙箱路径需要 file:// 前缀）
        Image(this.settings.background.imagePath?.startsWith('/') 
          ? 'file://' + this.settings.background.imagePath 
          : this.settings.background.imagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.settings.background.imageOpacity || 1)
      } else {
        // 纯色背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getBackgroundColor())
      }
      
          // 章节切换过渡页
      Stack() {
        if (this.isChapterTransition) {
          // 滚动模式
          this.buildChapterTransitionPage()
        } else if (this.settings.readingMode === TextReadingMode.SCROLL) {
          // 双页模式
          this.buildScrollMode()
        } else if (this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
          // 翻页模式
          this.buildDualPageMode()
        } else {
          // 翻页模式
          this.buildPageMode()
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.relayoutOpacity)

      // 卷页效果层（单页模式）
      if (this.showCurlEffect && this.currentPixelMap && !this.isDualPageMode()) {
        PageCurlEffectV2({
          currentPixelMap: this.currentPixelMap,
          nextPixelMap: this.nextPixelMap,
          componentWidth: this.componentWidth,
          componentHeight: this.componentHeight,
          imageDisplayX: 0,
          imageDisplayY: 0,
          imageDisplayWidth: this.componentWidth,
          imageDisplayHeight: this.componentHeight,
          config: this.novelCurlConfig,
          isForward: this.isForward,
          curlStartPosition: this.curlStartPosition,
          curlTouchX: this.curlTouchX,
          curlTouchY: this.curlTouchY,
          externalProgress: this.curlProgress,
          animateToTarget: this.curlAnimateTarget,
          animateFromProgress: this.curlAnimateFrom,
          curlBackOpacity: 100,
          onAnimationComplete: () => {
            if (this.curlAnimateTarget >= 1.0) {
              this.onCurlAnimationComplete();
            } else if (this.curlAnimateTarget <= 0) {
              this.resetCurlState();
            }
          }
        })
      }
      
      // 如果放在 @Builder buildDualPageMode() 内，Canvas 绘制调用产生的内容不可见）
      // 如果放在 @Builder buildDualPageMode() 内，Canvas 绘制调用产生的内容不可见）
      if (this.isDualPageMode() && this.showCurlEffect && (this.dualCurlLeftPM || this.dualCurlRightPM)) {
        DualPageCurlEffect({
          currentLeftPixelMap: this.dualCurlLeftPM,
          currentRightPixelMap: this.dualCurlRightPM,
          nextLeftPixelMap: this.dualCurlNextLeftPM,
          nextRightPixelMap: this.dualCurlNextRightPM,
          componentWidth: this.componentWidth,
          componentHeight: this.componentHeight,
          config: this.novelCurlConfig,
          isForward: this.isForward,
          curlTouchY: this.curlTouchY,
          curlBackOpacity: 100,
          externalProgress: this.curlProgress,
          animateToTarget: -1,
          animateFromProgress: 0,
          onAnimationComplete: () => {}
        })
      }
      
      // 双页模式不显示（页码已在各自页面组件内 + PixelMap 中）
      // 双页模式不显示（页码已在各自页面组件内 + PixelMap 中）
      if ((this.settings.showPageNumber || this.settings.showProgress || this.settings.showTime || this.settings.showBattery)
          && !this.isDualPageMode()) {
        this.buildPageInfo()
      }
      this.buildHighlightThoughtPopupLayer()
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Default)
    .onAreaChange((_, newArea) => {
      this.componentWidth = Number(newArea.width);
      this.componentHeight = Number(newArea.height);
      if (!this.recalculateContentArea()) {
        return;
      }
      
      // 使用防抖机制重新分页
      if (this.areaChangeDebounceTimer !== -1) {
        clearTimeout(this.areaChangeDebounceTimer);
      }
      this.areaChangeDebounceTimer = setTimeout(() => {
        this.areaChangeDebounceTimer = -1;
        if (!this.content || this.content.length === 0) {
          return;
        }
        this.pendingAnchorCharIndex = this.getCurrentAnchorCharIndex();
        this.pendingRelayoutAnimation = true;
        this.startRelayoutAnimation();
        this.releaseAllPixelMapCache();
        this.paginateContentAsync();
      }, TextReaderComponent.AREA_CHANGE_DEBOUNCE_MS);
    })
    .parallelGesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
            if (this.suppressNextTapEvent) {
              this.suppressNextTapEvent = false;
              return;
            }
            if (this.isHighlightThoughtPopupActive()) {
              return;
            }
            const x = event.fingerList[0]?.localX || 0;
            const y = event.fingerList[0]?.localY || 0;
            setTimeout(() => {
              if (this.suppressNextTapEvent) {
                this.suppressNextTapEvent = false;
                return;
              }
              if (this.isHighlightThoughtPopupActive()) {
                return;
              }
              if (this.isDualPageMode()) {
                this.handleDualPageTap(x, y);
              } else {
                this.handleTapAtPosition(x, y);
              }
            }, 0);
          }),
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart((event: GestureEvent) => this.handlePanStart(event))
          .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
          .onActionEnd((event: GestureEvent) => {
            if (this.hasActiveSelectionRange()) {
              this.isDragging = false;
              return;
            }
            if (this.isDualPageMode()) {
              this.isDragging = false;
              const deltaX = event.offsetX - this.initialTouchX;
              this.handleDualPagePanEnd(deltaX);
            } else {
              this.handlePanEnd(event);
            }
          })
      )
    )
    .onKeyEvent((event: KeyEvent) => {
      if (this.isHighlightThoughtPopupActive() &&
        event.type === KeyType.Up &&
        (event.keyCode === KeyCode.KEYCODE_VOLUME_UP || event.keyCode === KeyCode.KEYCODE_VOLUME_DOWN)) {
        event.stopPropagation();
        return;
      }
      // 处理音量键翻页
      if (event.type === KeyType.Up) {
        const consumed = this.handleVolumeKeyPageTurn(event.keyCode);
        if (consumed) {
          event.stopPropagation();
        }
      }
    })
    .focusable(true)
    .defaultFocus(true)
  }
  
  /**
  * 构建用于截图的页面内容
  * 注意：需要指定固定尺寸，因为 createFromBuilder 需要知道组件大小
  * @param content 页面文本内容
  * @param width 页面宽度
  * @param height 页面高度
  * @param pageIndex 页码索引（用于在 PixelMap 中渲染页码）
  */
  @Builder
  buildScrollMode() {
    Scroll(this.scrollController) {
      Column() {
        if (this.hasReadAloudScrollHighlight()) {
          Text() {
            if (this.getReadAloudScrollBeforeSentenceText().length > 0) {
              Span(this.getReadAloudScrollBeforeSentenceText())
                .textBackgroundStyle({ color: READ_ALOUD_HISTORY_HIGHLIGHT })
            }
            if (this.getReadAloudScrollSentenceReadText().length > 0) {
              Span(this.getReadAloudScrollSentenceReadText())
                .textBackgroundStyle({ color: READ_ALOUD_READ_HIGHLIGHT })
            }
            if (this.getReadAloudScrollSentenceUnreadText().length > 0) {
              Span(this.getReadAloudScrollSentenceUnreadText())
                .textBackgroundStyle({ color: READ_ALOUD_CURRENT_SENTENCE_HIGHLIGHT })
            }
            if (this.getReadAloudScrollAfterSentenceText().length > 0) {
              Span(this.getReadAloudScrollAfterSentenceText())
            }
          }
            .fontSize(this.settings.textStyle.fontSize)
            .fontColor(this.settings.textStyle.textColor)
            .lineHeight(this.getEffectiveTextLineHeight())
            .letterSpacing(this.settings.textStyle.letterSpacing)
            .fontWeight(this.settings.textStyle.fontWeight)
            .fontFamily(this.settings.textStyle.fontFamily)
            .textAlign(this.getTextAlign())
            .width('100%')
            .copyOption(CopyOptions.InApp)
            .selection(this.selectionStart, this.selectionEnd)
            .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
              this.handleTextSelectionChange(selectionStart, selectionEnd);
            })
            .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
              onDisappear: () => {
                this.clearSelection();
              }
            })
        } else {
          // 非听书高亮状态下使用分段渲染，避免一次性绘制大段文本导致卡顿
          if (this.novelHighlightRanges.length > 0) {
            Text() {
              ForEach(this.getScrollHighlightSegments(), (segment: TextRenderSegment) => {
                if (segment.highlighted) {
                  Span(segment.text)
                    .decoration({ type: TextDecorationType.Underline, color: segment.color })
                    .textBackgroundStyle(
                      segment.lineType === HighlightLineType.WAVY ? { color: `${segment.color}33` } : { color: '#00000000' }
                    )
                    .onClick((event: ClickEvent) => {
                      this.showThoughtPopupForSegment(segment, event);
                    })
                } else {
                  Span(segment.text)
                }
              }, (segment: TextRenderSegment) => segment.key)
            }
              .fontSize(this.settings.textStyle.fontSize)
              .fontColor(this.settings.textStyle.textColor)
              .lineHeight(this.getEffectiveTextLineHeight())
              .letterSpacing(this.settings.textStyle.letterSpacing)
              .fontWeight(this.settings.textStyle.fontWeight)
              .fontFamily(this.settings.textStyle.fontFamily)
              .textAlign(this.getTextAlign())
              .width('100%')
              .copyOption(CopyOptions.InApp)
              .selection(this.selectionStart, this.selectionEnd)
              .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                this.handleTextSelectionChange(selectionStart, selectionEnd);
              })
              .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
                onDisappear: () => {
                  this.clearSelection();
                }
              })
          } else {
            if (this.enableNovelAnnotations) {
              Text(this.content)
                .fontSize(this.settings.textStyle.fontSize)
                .fontColor(this.settings.textStyle.textColor)
                .lineHeight(this.getEffectiveTextLineHeight())
                .letterSpacing(this.settings.textStyle.letterSpacing)
                .fontWeight(this.settings.textStyle.fontWeight)
                .fontFamily(this.settings.textStyle.fontFamily)
                .textAlign(this.getTextAlign())
                .width('100%')
                .copyOption(CopyOptions.InApp)
                .selection(this.selectionStart, this.selectionEnd)
                .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                  this.handleTextSelectionChange(selectionStart, selectionEnd);
                })
                .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenuWithSymbol, TextResponseType.LONG_PRESS, {
                  onDisappear: () => {
                    this.clearSelection();
                  }
                })
            } else {
              ForEach(this.getTextSegments(), (segment: string, _index: number) => {
                Text(segment)
                  .fontSize(this.settings.textStyle.fontSize)
                  .fontColor(this.settings.textStyle.textColor)
                  .lineHeight(this.getEffectiveTextLineHeight())
                  .letterSpacing(this.settings.textStyle.letterSpacing)
                  .fontWeight(this.settings.textStyle.fontWeight)
                  .fontFamily(this.settings.textStyle.fontFamily)
                  .textAlign(this.getTextAlign())
                  .width('100%')
              })
            }
          }
        }
      }
      .padding(this.getEffectiveContentPadding())
      .width('100%')
      .backgroundColor(this.getContentBackgroundColor())
    }
    .width('100%')
    .height('100%')
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onScroll((xOffset: number, yOffset: number) => {
      this.scrollOffset += yOffset;
      if (!this.isAutoScrollStepInProgress) {
        this.resetAutoPageTurnTimerForInteraction('manual-scroll');
      }
    })
  }
  
  /**
  * 构建用于截图的页面内容
  * 注意：需要指定固定尺寸，因为 createFromBuilder 需要知道组件大小
  * @param content 页面文本内容
  * @param width 页面宽度
  * @param height 页面高度
  * @param pageIndex 页码索引（用于在 PixelMap 中渲染页码）
  */
  @Builder
  buildChapterTransitionPage() {
    Column() {
      // 加载动画
      LoadingProgress()
        .width(48)
        .height(48)
        .color(this.settings.textStyle.textColor)
      
      // 提示文字
      Text(this.transitionDirection ? '切换到下一章' : '切换到上一章')
        .fontSize(14)
        .fontColor(this.settings.textStyle.textColor)
        .opacity(0.6)
        .margin({ top: 16 })
      
      // 章节名
      Text(this.transitionChapterName)
        .fontSize(18)
        .fontColor(this.settings.textStyle.textColor)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 8 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.getContentBackgroundColor())
    .translate({ x: this.slideOffset, y: 0 })
  }
  
  /**
   * 这样文字内容会在状态栏上方结束，不会被遮挡
   */
  @Builder
  buildPageMode() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 下一页（在底层，滑动时露出）
      if (this.slideOffset !== 0 || this.showCurlEffect) {
        Text(this.isForward ? this.nextPageContent : this.prevPageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.getEffectiveTextLineHeight())
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .textAlign(this.getTextAlign())
          .padding(this.getEffectiveContentPadding())
          .width('100%')
          .height('100%')
          .backgroundColor(this.getContentBackgroundColor())
      }
      
        // 当前页内容（支持长按选择文本）
      Stack() {
        // 卷曲效果由 Canvas 层 PageCurlEffectV2 统一渲染（包含3D卷曲、光影、背面）
        this.buildCurrentPageTextLayer()
        
        // 无需额外的 ArkUI 叠加层
        // 无需额外的 ArkUI 叠加层
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.slideOffset })
        .opacity(this.slideOpacity)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
  
  /**
  * 构建用于截图的页面内容
  * 注意：需要指定固定尺寸，因为 createFromBuilder 需要知道组件大小
  * @param content 页面文本内容
  * @param width 页面宽度
  * @param height 页面高度
  * @param pageIndex 页码索引（用于在 PixelMap 中渲染页码）
  */
  @Builder
  buildDualPageMode() {
    Stack() {
        // === 左侧书页 ===
      Row() {
          // 左页背景
        Stack() {
          // 左页背景
          if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#F5F0E1')
            Image(this.settings.background.imagePath.startsWith('/')
              ? 'file://' + this.settings.background.imagePath
              : this.settings.background.imagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .opacity(this.settings.background.imageOpacity ?? 1)
          } else {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.getBackgroundColor())
          }
          
              // 底层背景
          if (this.dualSlideOffset !== 0 && this.dualAnimSide === 'left') {
            Stack() {
              // 底层背景
              if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor('#F5F0E1')
                Image(this.settings.background.imagePath.startsWith('/')
                  ? 'file://' + this.settings.background.imagePath
                  : this.settings.background.imagePath)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .opacity(this.settings.background.imageOpacity ?? 1)
              } else {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor(this.getBackgroundColor())
              }
              Text(this.dualUnderLeftContent)
                .fontSize(this.settings.textStyle.fontSize)
                .fontColor(this.settings.textStyle.textColor)
                .lineHeight(this.getEffectiveTextLineHeight())
                .letterSpacing(this.settings.textStyle.letterSpacing)
                .fontWeight(this.settings.textStyle.fontWeight)
                .fontFamily(this.settings.textStyle.fontFamily)
                .textAlign(this.getTextAlign())
                .padding(this.getEffectiveContentPadding())
                .width('100%')
                .height('100%')
            }
            .width('100%')
            .height('100%')
          }
          
          // 左页当前内容
          Stack() {
            if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor('#F5F0E1')
              Image(this.settings.background.imagePath.startsWith('/')
                ? 'file://' + this.settings.background.imagePath
                : this.settings.background.imagePath)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .opacity(this.settings.background.imageOpacity ?? 1)
            } else {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(this.getBackgroundColor())
            }
            this.buildDualPageTextLayer(this.dualLeftPageContent, this.dualLeftPageIndex)
            // 左页页码指示器
            if (this.settings.showPageNumber) {
              Row() {
                Text(`${this.dualLeftPageIndex + 1} / ${this.totalPages}`)
                  .fontSize(12)
                  .fontColor(this.settings.textStyle.textColor)
                  .opacity(0.5)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ left: 16, right: 16, bottom: 8 })
              .position({ x: 0, y: '100%' })
              .translate({ y: '-100%' })
            }
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.dualAnimSide === 'left' ? this.dualSlideOffset : 0 })
          .opacity(this.slideOpacity)
        }
        .layoutWeight(1)
        .height('100%')
        .clip(true)
        
          // 右页背景
        Stack() {
          // 右页背景
          if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#F5F0E1')
            Image(this.settings.background.imagePath.startsWith('/')
              ? 'file://' + this.settings.background.imagePath
              : this.settings.background.imagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .opacity(this.settings.background.imageOpacity ?? 1)
          } else {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.getBackgroundColor())
          }
          
              // 底层背景
          if (this.dualSlideOffset !== 0 && this.dualAnimSide === 'right') {
            Stack() {
              // 底层背景
              if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor('#F5F0E1')
                Image(this.settings.background.imagePath.startsWith('/')
                  ? 'file://' + this.settings.background.imagePath
                  : this.settings.background.imagePath)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .opacity(this.settings.background.imageOpacity ?? 1)
              } else {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor(this.getBackgroundColor())
              }
              Text(this.dualUnderRightContent)
                .fontSize(this.settings.textStyle.fontSize)
                .fontColor(this.settings.textStyle.textColor)
                .lineHeight(this.getEffectiveTextLineHeight())
                .letterSpacing(this.settings.textStyle.letterSpacing)
                .fontWeight(this.settings.textStyle.fontWeight)
                .fontFamily(this.settings.textStyle.fontFamily)
                .textAlign(this.getTextAlign())
                .padding(this.getEffectiveContentPadding())
                .width('100%')
                .height('100%')
            }
            .width('100%')
            .height('100%')
          }
          
          // 右页当前内容
          Stack() {
            if (this.settings.background.type === BackgroundType.IMAGE && this.settings.background.imagePath) {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor('#F5F0E1')
              Image(this.settings.background.imagePath.startsWith('/')
                ? 'file://' + this.settings.background.imagePath
                : this.settings.background.imagePath)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .opacity(this.settings.background.imageOpacity ?? 1)
            } else {
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor(this.getBackgroundColor())
            }
            this.buildDualPageTextLayer(this.dualRightPageContent, this.dualRightPageIndex)
            // 右页页码指示器
            if (this.settings.showPageNumber && this.dualRightPageIndex < this.totalPages) {
              Row() {
                Text(`${this.dualRightPageIndex + 1} / ${this.totalPages}`)
                  .fontSize(12)
                  .fontColor(this.settings.textStyle.textColor)
                  .opacity(0.5)
                  .fontWeight(FontWeight.Medium)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ left: 16, right: 16, bottom: 8 })
              .position({ x: 0, y: '100%' })
              .translate({ y: '-100%' })
            }
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.dualAnimSide === 'right' ? this.dualSlideOffset : 0 })
          .opacity(this.slideOpacity)
        }
        .layoutWeight(1)
        .height('100%')
        .clip(true)
      }
      .width('100%')
      .height('100%')
      
    }
    .width('100%')
    .height('100%')
  }
  
  /**
   * 双页布局：左下角(左页页码) | 中央(电量+时间) | 右下角(右页页码)
   */
  @Builder
  buildPageInfo() {
    if (this.isDualPageMode()) {
        // 左下角：左页页码（双页模式始终显示）
      Row() {
        // 左下角：左页页码（双页模式始终显示）
        Row() {
          Text(`${this.dualLeftPageIndex + 1} / ${this.totalPages}`)
            .fontSize(12)
            .fontColor(this.settings.textStyle.textColor)
            .opacity(0.5)
            .fontWeight(FontWeight.Medium)
        }
        .width(80)
        .justifyContent(FlexAlign.Start)
        
        // 中央：电量 + 时间
        Row({ space: 12 }) {
          if (this.settings.showBattery) {
            Row({ space: 6 }) {
              Stack({ alignContent: Alignment.Start }) {
                Row()
                  .width(22)
                  .height(11)
                  .borderRadius(3)
                  .border({ width: 1.5, color: this.settings.textStyle.textColor })
                  .opacity(0.5)
                Row()
                  .width(Math.max(2, 17 * this.batteryLevel / 100))
                  .height(7)
                  .borderRadius(1.5)
                  .position({ x: 2, y: 2 })
                  .linearGradient({
                    angle: 90,
                    colors: this.batteryLevel > 20 
                      ? [[this.getBatteryColor(this.batteryLevel), 0], [this.getBatteryColorEnd(this.batteryLevel), 1]]
                      : [['#FF4444', 0], ['#FF6666', 1]]
                  })
                Row()
                  .width(2.5)
                  .height(5)
                  .backgroundColor(this.settings.textStyle.textColor)
                  .opacity(0.5)
                  .borderRadius({ topRight: 1, bottomRight: 1 })
                  .position({ x: 22, y: 3 })
              }
              .width(26)
              .height(11)
              
              Text(`${this.batteryLevel}%`)
                .fontSize(11)
                .fontColor(this.settings.textStyle.textColor)
                .opacity(0.5)
                .fontWeight(FontWeight.Medium)
            }
          }
          if (this.settings.showTime) {
            Text(this.currentTime)
              .fontSize(12)
              .fontColor(this.settings.textStyle.textColor)
              .opacity(0.5)
              .fontWeight(FontWeight.Medium)
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        
        // 右下角：右页页码（双页模式始终显示）
        Row() {
          if (this.dualRightPageIndex < this.totalPages) {
            Text(`${this.dualRightPageIndex + 1} / ${this.totalPages}`)
              .fontSize(12)
              .fontColor(this.settings.textStyle.textColor)
              .opacity(0.5)
              .fontWeight(FontWeight.Medium)
          }
        }
        .width(80)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
    } else {
      // 单页模式布局
      Row() {
        Row() {
          if (this.settings.showBattery) {
            Row({ space: 6 }) {
              Stack({ alignContent: Alignment.Start }) {
                Row()
                  .width(22)
                  .height(11)
                  .borderRadius(3)
                  .border({ width: 1.5, color: this.settings.textStyle.textColor })
                  .opacity(0.5)
                Row()
                  .width(Math.max(2, 17 * this.batteryLevel / 100))
                  .height(7)
                  .borderRadius(1.5)
                  .position({ x: 2, y: 2 })
                  .linearGradient({
                    angle: 90,
                    colors: this.batteryLevel > 20 
                      ? [[this.getBatteryColor(this.batteryLevel), 0], [this.getBatteryColorEnd(this.batteryLevel), 1]]
                      : [['#FF4444', 0], ['#FF6666', 1]]
                  })
                Row()
                  .width(2.5)
                  .height(5)
                  .backgroundColor(this.settings.textStyle.textColor)
                  .opacity(0.5)
                  .borderRadius({ topRight: 1, bottomRight: 1 })
                  .position({ x: 22, y: 3 })
              }
              .width(26)
              .height(11)
              
              Text(`${this.batteryLevel}%`)
                .fontSize(11)
                .fontColor(this.settings.textStyle.textColor)
                .opacity(0.5)
                .fontWeight(FontWeight.Medium)
            }
          }
        }
        .width(80)
        .justifyContent(FlexAlign.Start)
        
        Row() {
          if (this.settings.showTime) {
            Text(this.currentTime)
              .fontSize(12)
              .fontColor(this.settings.textStyle.textColor)
              .opacity(0.5)
              .fontWeight(FontWeight.Medium)
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        
        Row() {
          if (this.settings.showPageNumber) {
            Text(`${this.currentPageIndex + 1} / ${this.totalPages}`)
              .fontSize(12)
              .fontColor(this.settings.textStyle.textColor)
              .opacity(0.5)
              .fontWeight(FontWeight.Medium)
          } else if (this.settings.showProgress) {
            Text(`${this.totalPages > 0 ? Math.round((this.currentPageIndex + 1) / this.totalPages * 100) : 0}%`)
              .fontSize(12)
              .fontColor(this.settings.textStyle.textColor)
              .opacity(0.5)
              .fontWeight(FontWeight.Medium)
          }
        }
        .width(80)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .position({ x: 0, y: '100%' })
      .translate({ y: '-100%' })
    }
  }
  
  /**
   * 构建文本选择菜单
   */
  @Builder
  buildTextSelectionMenuWithSymbol() {
    Menu() {
      MenuItem({
        content: '复制',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_text')).fontSize('18vp')
      })
        .onClick(() => {
          this.copySelectedText();
        })
      MenuItem({
        content: '百科搜索',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.magnifyingglass')).fontSize('18vp')
      })
        .onClick(() => {
          this.searchEncyclopedia();
        })
      MenuItem({
        content: '添加净化规则',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.slider_vertical_3')).fontSize('18vp')
      })
        .onClick(() => {
          this.addPurifyRuleFromSelection();
        })
      MenuItem({
        content: '开始听书',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.play_fill')).fontSize('18vp')
      })
        .onClick(() => {
          this.startReadAloudFromSelection();
        })
      if (this.enableNovelAnnotations) {
        MenuItem({
          content: '划线',
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')).fontSize('18vp')
        })
          .onClick(() => {
            this.addHighlightFromSelection(false);
          })
        MenuItem({
          content: '划线并添加想法',
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')).fontSize('18vp')
        })
          .onClick(() => {
            this.addHighlightFromSelection(true);
          })
      }
      MenuItem({
        content: '分享',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_up')).fontSize('18vp')
      })
        .onClick(() => {
          this.shareSelectedText();
        })
    }
    .radius(8)
    .backgroundColor($r('app.color.settings_panel_background'))
  }
  @Builder
  buildTextSelectionMenu() {
    Menu() {
      MenuItem({ content: '复制' })
        .onClick(() => {
          this.copySelectedText();
        })
      MenuItem({ content: '百科搜索' })
        .onClick(() => {
          this.searchEncyclopedia();
        })
      MenuItem({ content: '添加净化规则' })
        .onClick(() => {
          this.addPurifyRuleFromSelection();
        })
      MenuItem({ content: '开始听书' })
        .onClick(() => {
          this.startReadAloudFromSelection();
        })
      if (this.enableNovelAnnotations) {
        MenuItem({ content: '划线' })
          .onClick(() => {
            this.addHighlightFromSelection(false);
          })
        MenuItem({ content: '划线并添加想法' })
          .onClick(() => {
            this.addHighlightFromSelection(true);
          })
      }
      MenuItem({ content: '分享' })
        .onClick(() => {
          this.shareSelectedText();
        })
    }
    .radius(8)
    .backgroundColor($r('app.color.settings_panel_background'))
  }
  
  /**
   * 复制选中的文本
   */
  private copySelectedText(): void {
    if (this.selectedText) {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.selectedText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制', duration: 1500 });
    }
    this.clearSelection();
  }
  
  /**
   * 从选中文本添加净化规则
   */
  private addPurifyRuleFromSelection(): void {
    if (this.selectedText) {
      this.onAddPurifyRule(this.selectedText);
      promptAction.showToast({ message: '已添加净化规则', duration: 1500 });
    }
    this.clearSelection();
  }
  
  /**
   * 分享选中的文本
   */
  private shareSelectedText(): void {
    if (this.selectedText) {
      // 调用系统分享
      promptAction.showToast({ message: '分享功能开发中', duration: 1500 });
    }
    this.clearSelection();
  }
  
  /**
   * 百科搜索选中的文本
   */
  private searchEncyclopedia(): void {
    if (this.selectedText) {
      this.onSearchEncyclopedia(this.selectedText);
    }
    this.clearSelection();
  }

  private startReadAloudFromSelection(): void {
    const startCharIndex = this.getReadAloudStartCharIndexFromSelection();
    if (startCharIndex < 0) {
      promptAction.showToast({ message: '未获取到有效选区', duration: 1500 });
      this.clearSelection();
      return;
    }
    this.onStartReadAloudFromCharIndex(startCharIndex);
    promptAction.showToast({ message: '已从所选句开始听书', duration: 1500 });
    this.clearSelection();
  }

  private addHighlightFromSelection(withThought: boolean): void {
    const range = this.getGlobalSelectionRange();
    if (!range || !this.selectedText) {
      promptAction.showToast({ message: '未获取到有效选区', duration: 1500 });
      this.clearSelection();
      return;
    }
    if (withThought) {
      this.preparePendingThoughtPopupBySelection(range.start, range.end, this.selectedText);
      this.onAddHighlightWithThought(this.selectedText, range.start, range.end);
      logger.info(TAG, `触发“划线并添加想法”: start=${range.start}, end=${range.end}, textLength=${this.selectedText.length}`);
    } else {
      this.onAddHighlight(this.selectedText, range.start, range.end);
    }
    this.clearSelection();
  }

  private addThoughtFromSelection(): void {
    const range = this.getGlobalSelectionRange();
    if (!range || !this.selectedText) {
      promptAction.showToast({ message: '未获取到有效选区', duration: 1500 });
      this.clearSelection();
      return;
    }
    this.onAddThought(this.selectedText, range.start, range.end);
    this.clearSelection();
  }

  private createSafeGlobalRange(start: number, end: number): SelectionRange | null {
    if (this.content.length <= 0) {
      return null;
    }
    const safeStart = Math.max(0, Math.min(Math.floor(start), this.content.length - 1));
    const safeEnd = Math.max(safeStart + 1, Math.min(Math.floor(end), this.content.length));
    if (safeEnd <= safeStart) {
      return null;
    }
    const range: SelectionRange = { start: safeStart, end: safeEnd };
    return range;
  }

  private isRangeMatchedSelectedText(range: SelectionRange | null): boolean {
    if (!range || !this.selectedText || this.selectedText.length <= 0) {
      return false;
    }
    return this.content.substring(range.start, range.end) === this.selectedText;
  }

  private getGlobalSelectionRange(): SelectionRange | null {
    if (this.selectionStart < 0 || this.selectionEnd <= this.selectionStart || this.content.length <= 0) {
      return null;
    }

    if (this.settings.readingMode === TextReadingMode.SCROLL) {
      const start = Math.max(0, Math.min(this.selectionStart, this.content.length - 1));
      const end = Math.max(start + 1, Math.min(this.selectionEnd, this.content.length));
      const range: SelectionRange = { start, end };
      return range;
    }

    if (this.pages.length <= 0) {
      return null;
    }
    const safePageIndex = Math.max(0, Math.min(this.currentPageIndex, this.pages.length - 1));
    const page = this.pages[safePageIndex];
    if (!page) {
      return null;
    }
    const safeLocalStart = Math.max(0, Math.min(this.selectionStart, this.currentPageContent.length));
    const safeLocalEnd = Math.max(safeLocalStart + 1, Math.min(this.selectionEnd, this.currentPageContent.length));
    const localCandidate = this.createSafeGlobalRange(
      page.startCharIndex + safeLocalStart,
      page.startCharIndex + safeLocalEnd
    );
    const globalCandidate = this.createSafeGlobalRange(this.selectionStart, this.selectionEnd);

    const localMatch = this.isRangeMatchedSelectedText(localCandidate);
    const globalMatch = this.isRangeMatchedSelectedText(globalCandidate);
    if (globalMatch && !localMatch) {
      return globalCandidate;
    }
    if (localMatch && !globalMatch) {
      return localCandidate;
    }
    if (localMatch && globalMatch) {
      return localCandidate;
    }

    const pageStart = Math.max(0, page.startCharIndex);
    const pageEnd = page.endCharIndex > pageStart ? page.endCharIndex : (pageStart + this.currentPageContent.length);
    const localInPage = !!localCandidate && localCandidate.start >= pageStart && localCandidate.end <= pageEnd;
    const globalInPage = !!globalCandidate && globalCandidate.start >= pageStart && globalCandidate.end <= pageEnd;
    if (globalInPage && !localInPage) {
      return globalCandidate;
    }
    if (localInPage && !globalInPage) {
      return localCandidate;
    }

    const selectionLooksGlobal =
      this.selectionStart >= this.currentPageContent.length || this.selectionEnd > this.currentPageContent.length;
    if (selectionLooksGlobal && globalCandidate) {
      return globalCandidate;
    }
    return localCandidate || globalCandidate;
  }

  private getReadAloudStartCharIndexFromSelection(): number {
    if (this.selectionStart < 0 || this.selectionEnd <= this.selectionStart) {
      return -1;
    }
    if (this.content.length <= 0) {
      return -1;
    }

    const globalSelectionStart = this.getGlobalSelectionStartCharIndex();
    if (globalSelectionStart < 0) {
      return -1;
    }
    return this.resolveReadAloudSentenceStartCharIndex(globalSelectionStart);
  }

  private getGlobalSelectionStartCharIndex(): number {
    const range = this.getGlobalSelectionRange();
    if (!range) {
      return -1;
    }
    return range.start;
  }

  private resolveReadAloudSentenceStartCharIndex(charIndex: number): number {
    let sentenceStart = Math.max(0, Math.min(charIndex, this.content.length - 1));
    while (sentenceStart > 0) {
      const prevChar = this.content.charAt(sentenceStart - 1);
      if (this.isReadAloudSentenceBoundary(prevChar)) {
        break;
      }
      sentenceStart -= 1;
    }
    return sentenceStart;
  }
  
  /**
   * 显示长按操作菜单
   */
  private showLongPressMenu(): void {
    // 使用当前页面内容作为选中文本（用户可以在菜单中选择操作）
    this.selectedText = this.currentPageContent;
    
    promptAction.showActionMenu({
      title: '选择操作',
      buttons: [
        { text: '百科搜索', color: '#007AFF' },
        { text: '复制全文', color: '#007AFF' },
        { text: '添加净化规则', color: '#007AFF' },
        { text: '取消', color: '#999999' }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      switch (result.index) {
        case 0: // 百科搜索
          this.showEncyclopediaInputDialog();
          break;
        case 1: // 复制全文
          this.copySelectedText();
          break;
        case 2: // 添加净化规则
          this.showPurifyRuleInputDialog();
          break;
        default:
          this.clearSelection();
          break;
      }
    }).catch(() => {
      this.clearSelection();
    });
  }
  
  /**
   * 显示百科搜索输入对话框
   */
  private showEncyclopediaInputDialog(): void {
    promptAction.showDialog({
      title: '百科搜索',
      message: '请输入要搜索的关键词',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '搜索', color: '#007AFF' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        // 用户点击搜索，使用TextInputDialog获取输入
        this.onSearchEncyclopedia(this.currentPageContent.substring(0, 50));
      }
    }).catch(() => {});
  }
  
  /**
   * 显示添加净化规则输入对话框
   */
  private showPurifyRuleInputDialog(): void {
    promptAction.showDialog({
      title: '添加净化规则',
      message: '请输入要净化的文本内容',
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '添加', color: '#007AFF' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        // 用户点击添加
        promptAction.showToast({ message: '请在设置中手动添加净化规则', duration: 2000 });
      }
    }).catch(() => {});
  }
  
  /**
   * 清除选择状态
   */
  private clearSelection(): void {
    this.selectionStart = -1;
    this.selectionEnd = -1;
    this.selectedText = '';
  }
  
  /**
  * 处理文本选择变化
  */
  private handleTextSelectionChange(start: number, end: number): void {
    this.selectionStart = start;
    this.selectionEnd = end;
    if (start >= 0 && end > start && this.currentPageContent) {
      this.isDragging = false;
      this.selectedText = this.currentPageContent.substring(start, end);
      this.onTextSelected(this.selectedText);
    } else {
      this.selectedText = '';
    }
  }
}


