/**
 * 文本阅读器核心组件
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
 */

import { logger } from '../Utils/Logger';
import { curves, componentSnapshot, font, promptAction } from '@kit.ArkUI';
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
  TextReadingMode,
  TextReadingDirection,
  TextPageTurnAnimation,
  TextAlignment,
  BackgroundType,
  DEFAULT_TEXT_READER_SETTINGS
} from '../Models/TextReaderModels';
import { PageCurlEffectV2, PageCurlConfigV2, CurlStartPosition } from './PageCurlEffectV2';
import { DualPageCurlEffect } from './DualPageCurlEffect';
import { InteractionManager, VibrationScene } from '../Framework/Managers/InteractionManager';


const TAG = 'TextReaderComponent';

/**
 * RGB颜色接口
 */
interface RGBColor {
  r: number;
  g: number;
  b: number;
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
  @Link settings: TextReaderSettings;
  /** 当前章节索引 */
  @Link @Watch('onChapterIndexChange') currentChapterIndex: number;
  /** 当前页面索引 */
  @Link @Watch('onPageIndexChange') currentPageIndex: number;
  /** 底部状态栏高度（用于避让底部信息显示区域） */
  @Prop bottomStatusBarHeight: number = 28;
  /** 分页模式：LOCAL（本地文件）或 ONLINE（在线小说） */
  @Prop paginationMode: PaginationMode = PaginationMode.LOCAL;
  
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
  
  // ========== 文本选择状态 ==========
  /** 选择开始位置 */
  @State private selectionStart: number = -1;
  /** 选择结束位置 */
  @State private selectionEnd: number = -1;
  /** 当前选中的文本 */
  @State private selectedText: string = '';
  
  // ========== 内部状态 ==========
  /** 分页后的页面列表 */
  @State private pages: TextPage[] = [];
  /** 总页数 */
  @State private totalPages: number = 0;
  /** 当前显示的文本内容 */
  @State private currentPageContent: string = '';
  /** 下一页的文本内容 */
  @State private nextPageContent: string = '';
  /** 上一页的文本内容 */
  @State private prevPageContent: string = '';
  
  // ========== 组件尺寸 ==========
  @State private componentWidth: number = 0;
  @State private componentHeight: number = 0;
  @State private contentAreaWidth: number = 0;
  @State private contentAreaHeight: number = 0;
  
  // ========== 翻页动画状态 ==========
  @State private isAnimating: boolean = false;
  @State private slideOffset: number = 0;
  @State private slideOpacity: number = 1;
  @State private isForward: boolean = true;
  
  // ========== 卷页动画状态 ==========
  @State private showCurlEffect: boolean = false;
  @State private curlProgress: number = 0;
  @State private currentPixelMap: image.PixelMap | null = null;
  @State private nextPixelMap: image.PixelMap | null = null;
  @State private prevPixelMap: image.PixelMap | null = null;  // 上一页 PixelMap（预加载）
  @State private curlStartPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
  @State private curlTouchX: number = 0;          // 卷曲触摸点X坐标
  @State private curlTouchY: number = 0;          // 卷曲触摸点Y坐标
  @State private curlAnimateTarget: number = -1;  // 内部动画目标进度（-1表示不使用）
  @State private curlAnimateFrom: number = 0;     // 内部动画起始进度
  private curlPendingPageIndex: number = -1;      // 待切换的页面索引
  private curlAnimationTimer: number = -1;        // 卷页动画定时器
  private animationTimeoutTimer: number = -1;     // 动画超时保护定时器
  private static readonly ANIMATION_TIMEOUT_MS: number = 3000;  // 动画超时时间(3秒)
  private pagePixelMapCache: Map<number, image.PixelMap> = new Map();  // 页面 PixelMap 缓存
  private isGeneratingPixelMap: boolean = false;  // 是否正在生成 PixelMap
  private panStartTime: number = 0;  // 拖拽起始时间戳（用于快速翻页速度检测）
  // 小说专用卷页配置：针对全屏场景优化动画曲线
  private novelCurlConfig: PageCurlConfigV2 = {
    stripCount: 24,
    maxCurlHeight: 120,
    shadowIntensity: 0.5,
    animationDuration: 350,  // 全屏页面较大，动画时长稍长以保证流畅感
    enableShadow: true,
    enableHighlight: true,
    flipThreshold: 0.28       // 全屏场景降低阈值，更容易触发翻页
  };
  private isPaginating: boolean = false;  // 是否正在分页
  private paginationVersion: number = 0;  // 分页版本号，用于取消旧的分页任务
  private paginationRetryCount: number = 0;  // 分页重试次数
  private static readonly MAX_PAGINATION_RETRIES: number = 10;  // 最大分页重试次数
  private areaChangeDebounceTimer: number = -1;  // onAreaChange防抖定时器
  private static readonly AREA_CHANGE_DEBOUNCE_MS: number = 100;  // 防抖时间(100ms)
  private lastContentAreaWidth: number = 0;  // 上次内容区域宽度
  private lastContentAreaHeight: number = 0;  // 上次内容区域高度
  @State private isLoading: boolean = false;  // 加载状态
  
  // ========== 章节切换过渡状态 ==========
  @State private isChapterTransition: boolean = false;  // 是否正在章节过渡
  @State private transitionChapterName: string = '';     // 过渡显示的章节名
  @State private transitionDirection: boolean = true;    // true=下一章, false=上一章
  
  // ========== 手势状态 ==========
  @State private touchStartX: number = 0;
  @State private touchStartY: number = 0;
  @State private isDragging: boolean = false;
  private initialTouchX: number = 0;  // 初始触摸X坐标（用于卷页拖拽）
  
  // ========== 滚动模式状态 ==========
  private scrollController: Scroller = new Scroller();
  @State private scrollOffset: number = 0;
  
  // ========== Canvas渲染上下文 ==========
  private renderingSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderingSettings);
  
  // ========== 音量键翻页状态 ==========
  // 音量键翻页使用组件级 onKeyEvent 处理，无需额外状态
  
  // ========== 时间和电量显示状态 ==========
  @State private currentTime: string = '';
  @State private batteryLevel: number = 0;
  private timeUpdateInterval: number = -1;
  
  // ========== 双页模式状态 ==========
  /** 双页模式左页内容 */
  @State private dualLeftPageContent: string = '';
  /** 双页模式右页内容 */
  @State private dualRightPageContent: string = '';
  /** 双页模式左页索引 */
  @State private dualLeftPageIndex: number = 0;
  /** 双页模式右页索引 */
  @State private dualRightPageIndex: number = 1;
  /** 双页模式当前展开页基础索引（始终为偶数） */
  private dualPageBaseIndex: number = 0;
  // ========== 双页卷页动画 PixelMap ==========
  @State private dualCurlLeftPM: image.PixelMap | null = null;
  @State private dualCurlRightPM: image.PixelMap | null = null;
  @State private dualCurlNextLeftPM: image.PixelMap | null = null;
  @State private dualCurlNextRightPM: image.PixelMap | null = null;
  /** 双页模式翻页动画作用侧：'left' 或 'right' */
  @State private dualAnimSide: string = 'right';
  /** 双页模式翻页动画偏移 */
  @State private dualSlideOffset: number = 0;
  /** 双页模式翻页动画下方页面内容（左侧） */
  @State private dualUnderLeftContent: string = '';
  /** 双页模式翻页动画下方页面内容（右侧） */
  @State private dualUnderRightContent: string = '';
  /** 双页卷页动画定时器（父组件驱动模式） */
  private dualCurlAnimTimer: number = -1;
  
  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, '文本阅读器组件初始化');
    // 注册自定义字体（如果有）
    this.registerCustomFontIfNeeded();
    // 启动时间更新定时器
    this.startTimeUpdate();
    // 获取电量
    this.updateBatteryLevel();
    // 记录初始内容和章节索引
    this.lastContent = this.content;
    this.lastChapterIndex = this.currentChapterIndex;
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
      
      // 重置状态
      this.currentPageIndex = 0;
      this.lastExternalPageIndex = 0;
      
      // 清空旧的页面数据和缓存，避免访问旧数据导致崩溃
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
      
      // 停止正在进行的动画
      this.stopCurlAnimation();
      this.isAnimating = false;
      this.showCurlEffect = false;
      
      // 异步分页
      this.paginateContentAsync();
    }
  }
  
  /**
   * 异步分页，避免阻塞主线程
   */
  private paginateContentAsync(): void {
    // 增加版本号，取消之前的分页任务
    this.paginationVersion++;
    const currentVersion = this.paginationVersion;
    
    // 如果已经在分页，记录日志并等待下一帧
    if (this.isPaginating) {
      logger.info(TAG, `分页任务已在运行，新任务将取消旧任务`);
    }
    
    // 显示加载状态
    this.isLoading = true;
    
    // 检查内容是否有效
    if (!this.content || this.content.length === 0) {
      logger.warn(TAG, `内容为空，跳过分页`);
      this.isLoading = false;
      return;
    }
    
    // 检查组件尺寸是否有效
    if (this.contentAreaWidth <= 0 || this.contentAreaHeight <= 0) {
      this.paginationRetryCount++;
      if (this.paginationRetryCount > TextReaderComponent.MAX_PAGINATION_RETRIES) {
        logger.error(TAG, `分页重试次数超过限制(${TextReaderComponent.MAX_PAGINATION_RETRIES})，停止重试`);
        this.isLoading = false;
        this.paginationRetryCount = 0;
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
    
    // 重置重试计数
    this.paginationRetryCount = 0;
    
    // 使用 setTimeout 延迟执行，让 UI 有机会更新
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
      
      // 检查是否需要跳转到最后一页（返回上一章节时）
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
        logger.info(TAG, `分页完成，跳转到最后一页: ${this.currentPageIndex + 1}/${this.totalPages}`);
      }
      
      // 更新当前页面内容
      this.updatePageContents();
      
      // 每次分页完成都更新签名，确保与当前设置同步
      this.lastRenderSignature = this.getRenderSignature();
      
      // 通知页面变化（确保进度正确保存）
      this.notifyPageChange();
      
      // 通知分页完成
      this.onReady();
    }, 50);  // 延迟 50ms 让 UI 有机会更新
  }
  
  /**
   * 章节索引变化回调
   * 当外部传入的 currentChapterIndex 变化时触发
   */
  private onChapterIndexChange(): void {
    if (this.currentChapterIndex !== this.lastChapterIndex) {
      logger.info(TAG, `章节索引变化: ${this.lastChapterIndex} -> ${this.currentChapterIndex}`);
      this.lastChapterIndex = this.currentChapterIndex;
      // 章节变化时，页码会在 onContentChange 中重置
    }
  }

  /**
   * 页面索引变化回调（用于外部触发翻页，如音量键翻页）
   * 当外部传入的 currentPageIndex 变化时触发
   */
  private lastExternalPageIndex: number = -1;
  private onPageIndexChange(): void {
    // 防止内部翻页触发重复更新
    if (this.lastExternalPageIndex === this.currentPageIndex) {
      return;
    }
    
    // 动画进行中不处理外部页面索引变化，避免破坏卷页动画状态
    if (this.isAnimating || this.showCurlEffect) {
      logger.debug(TAG, `外部页面索引变化被跳过（动画中）: ${this.lastExternalPageIndex} -> ${this.currentPageIndex}`);
      return;
    }
    
    // 边界检查
    const safeIndex = Math.max(0, Math.min(this.currentPageIndex, this.totalPages - 1));
    if (safeIndex !== this.currentPageIndex) {
      this.currentPageIndex = safeIndex;
    }
    
    logger.info(TAG, `外部页面索引变化: ${this.lastExternalPageIndex} -> ${this.currentPageIndex}, totalPages=${this.totalPages}`);
    this.lastExternalPageIndex = this.currentPageIndex;
    
    // 更新页面内容
    if (this.totalPages > 0) {
      this.updatePageContents();
      this.notifyPageChange();
    }
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, '文本阅读器组件销毁');
    this.releaseAllPixelMapCache();
    this.stopCurlAnimation();
    // 停止时间更新
    this.stopTimeUpdate();
    // 清理动画超时定时器
    this.clearAnimationTimeout();
    // 清理防抖定时器
    if (this.areaChangeDebounceTimer !== -1) {
      clearTimeout(this.areaChangeDebounceTimer);
      this.areaChangeDebounceTimer = -1;
    }
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
      // 使用警告震动提示用户已到达边界
      InteractionManager.getInstance().vibrate(VibrationScene.WARNING);
      logger.debug(TAG, '边界反馈：已到达页面边界');
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
    }, 30000); // 每30秒更新一次
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
      return '#4CAF50';  // 绿色
    } else if (level > 40) {
      return '#8BC34A';  // 黄绿色
    } else if (level > 20) {
      return '#FFC107';  // 黄色
    } else {
      return '#FF5722';  // 橙红色
    }
  }
  
  /**
   * 根据电量获取电池颜色（结束色，用于渐变）
   */
  private getBatteryColorEnd(level: number): string {
    if (level > 60) {
      return '#66BB6A';  // 浅绿色
    } else if (level > 40) {
      return '#AED581';  // 浅黄绿色
    } else if (level > 20) {
      return '#FFD54F';  // 浅黄色
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
    if (!this.settings.volumeKeyNavigation) {
      return false;
    }
    
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP) {
      logger.info(TAG, '音量键翻页: 上一页');
      if (this.isDualPageMode()) {
        this.goToPrevDualPage();
      } else {
        this.goToPrevPage();
      }
      return true;
    } else if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      logger.info(TAG, '音量键翻页: 下一页');
      if (this.isDualPageMode()) {
        this.goToNextDualPage();
      } else {
        this.goToNextPage();
      }
      return true;
    }
    
    return false;
  }
  
  // ========== 分页算法 ==========
  /**
   * 使用 measure API 精确测量文本宽度
   * @param text 要测量的文本
   * @returns 文本宽度（像素）
   */
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
      this.cachedScreenDensity = 3; // 默认密度
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
    
    // 使用常见中文字符测量平均宽度
    const sampleText = '测试文本字符';
    const totalWidth = this.measureTextWidthFast(sampleText);
    // 总宽度 = n个字符宽度 + (n-1)个字间距
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
   * 将文本按行分割，使用纯字符估算（快速版本）
   * 不使用 measureTextSize，避免主线程阻塞
   * @param text 要分割的文本
   * @param maxWidth 每行最大宽度
   * @param isFirstLine 是否为段落首行（需要缩进）
   * @returns 分割后的行数组
   */
  private splitTextToLines(text: string, maxWidth: number, isFirstLine: boolean): string[] {
    const lines: string[] = [];
    const firstLineIndent = this.settings.textStyle.firstLineIndent;
    
    // 首行缩进使用全角空格
    const indentText = isFirstLine && firstLineIndent > 0 ? '　'.repeat(Math.floor(firstLineIndent)) : '';
    let currentText = indentText + text;
    
    // 获取平均字符宽度用于估算
    const avgCharWidth = this.getAvgCharWidth();
    
    // 根据分页模式选择不同的系数
    // LOCAL模式：使用0.92的保守系数，适合本地TXT文件
    // ONLINE模式：使用1.0的系数，让每行尽可能填满，适合在线小说
    const widthFactor = this.paginationMode === PaginationMode.ONLINE ? 1.0 : 0.92;
    
    // 计算每行字符数：考虑字间距
    // 总宽度 = n个字符宽度 + (n-1)个字间距
    // maxWidth = n * avgCharWidth + (n-1) * letterSpacing
    // maxWidth = n * avgCharWidth + n * letterSpacing - letterSpacing
    // maxWidth + letterSpacing = n * (avgCharWidth + letterSpacing)
    // n = (maxWidth + letterSpacing) / (avgCharWidth + letterSpacing)
    const letterSpacing = this.settings.textStyle.letterSpacing;
    const charsPerLine = Math.max(1, Math.floor((maxWidth + letterSpacing) / (avgCharWidth + letterSpacing) * widthFactor));
    
    // 计算实际一行文字的宽度
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
    const actualLineHeight = fontSize * lineHeight;
    
    // 计算每页可容纳的行数
    const linesPerPage = Math.floor(this.contentAreaHeight / actualLineHeight);
    
    logger.info(TAG, `分页参数: fontSize=${fontSize}, lineHeight=${lineHeight}, actualLineHeight=${actualLineHeight}, contentAreaHeight=${this.contentAreaHeight}, linesPerPage=${linesPerPage}`);
    
    if (linesPerPage <= 0) {
      logger.warn(TAG, `每页行数计算异常: contentAreaHeight=${this.contentAreaHeight}, actualLineHeight=${actualLineHeight}`);
      return;
    }
    
    // 根据分页模式选择不同的策略
    if (this.paginationMode === PaginationMode.ONLINE) {
      this.paginateContentOnlineMode(linesPerPage);
    } else {
      this.paginateContentLocalMode(linesPerPage);
    }
    
    // 更新当前页面内容
    this.updatePageContents();
    
    // 分页完成后预加载相邻页面的 PixelMap（用于卷页动画）
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
    
    // 计算每行大约能容纳的字符数
    const charsPerLine = Math.max(1, Math.floor((this.contentAreaWidth + letterSpacing) / (avgCharWidth + letterSpacing)));
    // 每页大约能容纳的字符数（考虑首行缩进占用的字符数）
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
      
      // 空段落也要处理（保留换行）
      if (!paragraph.trim()) {
        // 空行占用一行的空间
        const emptyLineChars = charsPerLine;
        if (currentPageCharCount + emptyLineChars > charsPerPage && currentPageParagraphs.length > 0) {
          // 当前页已满，创建新页
          pages.push({
            index: pages.length,
            content: currentPageParagraphs.join('\n'),
            startCharIndex: pageStartCharIndex,
            endCharIndex: charIndex
          });
          pageStartCharIndex = charIndex;
          currentPageParagraphs = [];
          currentPageCharCount = 0;
        }
        currentPageParagraphs.push('');
        currentPageCharCount += emptyLineChars;
        charIndex += paragraph.length + 1;
        continue;
      }
      
      // 计算段落占用的行数（考虑首行缩进）
      const indentChars = Math.floor(firstLineIndent);
      const paragraphCharsWithIndent = paragraph.length + indentChars;
      const paragraphLines = Math.ceil(paragraphCharsWithIndent / charsPerLine);
      const paragraphCharCost = paragraphLines * charsPerLine;
      
      // 检查是否能放入当前页
      if (currentPageCharCount + paragraphCharCost > charsPerPage && currentPageParagraphs.length > 0) {
        // 当前页放不下整个段落
        // 计算当前页还能容纳多少行
        const remainingLines = Math.floor((charsPerPage - currentPageCharCount) / charsPerLine);
        
        if (remainingLines >= 2) {
          // 至少能放2行，尝试分割段落
          const remainingChars = remainingLines * charsPerLine - indentChars;
          if (remainingChars > charsPerLine / 2) {
            // 能放下足够的内容，分割段落
            const splitPoint = this.findParagraphSplitPoint(paragraph, remainingChars);
            if (splitPoint > 0 && splitPoint < paragraph.length - charsPerLine / 2) {
              // 分割段落
              const firstPart = paragraph.substring(0, splitPoint);
              const secondPart = paragraph.substring(splitPoint);
              
              // 首部分添加到当前页（带首行缩进）
              currentPageParagraphs.push('　'.repeat(indentChars) + firstPart);
              pages.push({
                index: pages.length,
                content: currentPageParagraphs.join('\n'),
                startCharIndex: pageStartCharIndex,
                endCharIndex: charIndex + splitPoint
              });
              
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
        pages.push({
          index: pages.length,
          content: currentPageParagraphs.join('\n'),
          startCharIndex: pageStartCharIndex,
          endCharIndex: charIndex
        });
        pageStartCharIndex = charIndex;
        currentPageParagraphs = [];
        currentPageCharCount = 0;
      }
      
      // 添加段落到当前页（带首行缩进）
      currentPageParagraphs.push('　'.repeat(indentChars) + paragraph);
      currentPageCharCount += paragraphCharCost;
      charIndex += paragraph.length + 1;
    }
    
    // 处理最后一页
    if (currentPageParagraphs.length > 0) {
      pages.push({
        index: pages.length,
        content: currentPageParagraphs.join('\n'),
        startCharIndex: pageStartCharIndex,
        endCharIndex: charIndex
      });
    }
    
    this.pages = pages;
    this.totalPages = pages.length;
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
    const clauseEnders = ['，', '；', '：', ',', ';', ':'];
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
        true  // 段落首行需要缩进
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
  
  // ========== 翻页逻辑 ==========
  /**
   * 翻到下一页
   */
  private goToNextPage(): void {
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
    
    this.isForward = true;
    this.performPageTurn(this.currentPageIndex + 1);
  }
  
  /**
   * 翻到上一页
   */
  private goToPrevPage(): void {
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
    
    this.isForward = false;
    this.performPageTurn(this.currentPageIndex - 1);
  }
  
  /**
   * 跳转到指定页面
   */
  private goToPage(pageIndex: number): void {
    // 安全检查
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) {
      logger.debug(TAG, `goToPage 被阻止: isAnimating=${this.isAnimating}, isPaginating=${this.isPaginating}, isLoading=${this.isLoading}, pages=${this.pages.length}`);
      return;
    }
    if (pageIndex < 0 || pageIndex >= this.totalPages) {
      return;
    }
    
    this.isForward = pageIndex > this.currentPageIndex;
    this.performPageTurn(pageIndex);
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
      logger.warn(TAG, `performNoAnimation: 页面数据无效，跳过`);
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
      logger.warn(TAG, `performSlideAnimation: 页面数据无效，跳过动画`);
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();  // 启动动画超时保护
    const direction = this.isForward ? -1 : 1;
    const targetOffset = direction * this.componentWidth;
    const capturedVersion = this.paginationVersion;  // 捕获当前版本
    
    animateTo({
      duration: 300,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = targetOffset;
    });
    
    setTimeout(() => {
      // 检查版本号，如果已变化则取消
      if (capturedVersion !== this.paginationVersion || this.pages.length === 0) {
        logger.warn(TAG, `performSlideAnimation: 动画完成后页面数据已变化，取消更新`);
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
      logger.warn(TAG, `performFadeAnimation: 页面数据无效，跳过动画`);
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();  // 启动动画超时保护
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
        logger.warn(TAG, `performFadeAnimation: 动画完成后页面数据已变化，取消更新`);
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
    
    // 边界检查 - 支持跨章节翻页
    if (targetPageIndex < 0) {
      // 尝试切换到上一章节的最后一页
      if (this.currentChapterIndex > 0) {
        logger.info(TAG, `completeSlidePageTurn: 切换到上一章节`);
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
        logger.info(TAG, `completeSlidePageTurn: 切换到下一章节`);
        this.switchToNextChapter();
      } else {
        logger.info(TAG, `completeSlidePageTurn: 已是最后一章最后一页，回弹`);
        this.animateSlideBack();
      }
      return;
    }
    
    this.isAnimating = true;
    this.startAnimationTimeout();  // 启动动画超时保护
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
    const capturedVersion = this.paginationVersion;  // 捕获版本用于中断检测
    
    this.isAnimating = true;
    this.startAnimationTimeout();  // 启动动画超时保护
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
      
      // 100ms 后切换章节并滑动过去
      setTimeout(() => {
        // 检查是否被中断
        if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
          this.forceResetAnimationState();
          return;
        }
        
        // 切换章节
        this.currentChapterIndex = nextChapterIndex;
        this.currentPageIndex = 0;
        
        // 通知章节变化（外部会更新内容）
        this.onChapterChange(this.currentChapterIndex);
        
        // 延迟一帧后滑动出过渡页
        setTimeout(() => {
          // 检查是否被中断
          if (!this.isAnimating) {
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
    const capturedVersion = this.paginationVersion;  // 捕获版本用于中断检测
    
    this.isAnimating = true;
    this.startAnimationTimeout();  // 启动动画超时保护
    this.isForward = false;
    this.transitionDirection = false;
    this.transitionChapterName = prevChapter?.title || `第 ${prevChapterIndex + 1} 章`;
    
    // 标记分页完成后跳转到最后一页
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
      
      // 100ms 后切换章节并滑动过去
      setTimeout(() => {
        // 检查是否被中断
        if (capturedVersion !== this.paginationVersion || !this.isAnimating) {
          this.forceResetAnimationState();
          return;
        }
        
        // 切换章节
        this.currentChapterIndex = prevChapterIndex;
        
        // 通知章节变化（外部会更新内容，分页完成后会检查 shouldJumpToLastPage）
        this.onChapterChange(this.currentChapterIndex);
        
        // 延迟一帧后滑动出过渡页
        setTimeout(() => {
          // 检查是否被中断
          if (!this.isAnimating) {
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
            logger.info(TAG, `switchToPrevChapter: 切换到章节 ${this.currentChapterIndex}，将跳转到最后一页`);
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
      logger.warn(TAG, `performCurlAnimation: 页面数据无效，跳过动画`);
      return;
    }
    
    // 检查背景设置是否变化，如果变化则清除缓存
    this.checkAndInvalidatePixelMapCache();
    
    // 生成当前页和目标页的PixelMap
    this.generatePagePixelMaps(this.currentPageIndex, targetPageIndex).then(() => {
      // 再次检查页面数据是否仍然有效（可能在异步过程中发生了章节切换）
      if (this.pages.length === 0 || this.isPaginating || this.isLoading) {
        logger.warn(TAG, `performCurlAnimation: 异步完成后页面数据已变化，取消动画`);
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
      logger.debug(TAG, '正在生成 PixelMap，跳过重复请求');
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
        // 生成当前页 PixelMap
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
        // 生成目标页 PixelMap
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
      // 使用 componentSnapshot.createFromBuilder 截取页面
      // 参数：builder 函数, delay(可选), checkImageStatus(可选), options(可选)
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
   * 构建用于截图的页面内容
   * 注意：需要指定固定尺寸，因为 createFromBuilder 需要知道组件大小
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
      
      // 文本内容层
      // 通过 padding 避让底部信息栏，与实际显示的 buildPageMode 一致
      Text(content)
        .fontSize(this.settings.textStyle.fontSize)
        .fontColor(this.settings.textStyle.textColor)
        .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .fontFamily(this.settings.textStyle.fontFamily)
        .textAlign(this.getTextAlign())
        .padding({
          top: this.settings.pageMargins.top,
          bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
          left: this.settings.pageMargins.left,
          right: this.settings.pageMargins.right
        })
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
    this.showCurlEffect = false;
    this.curlProgress = 0;
    this.curlAnimateTarget = -1;
    this.curlAnimateFrom = 0;
    this.curlPendingPageIndex = -1;
    this.isAnimating = false;
    this.releasePixelMaps();
  }
  
  /**
   * 更新卷页进度（实时拖拽）
   * 使用预加载的 PixelMap 提高响应速度
   */
  private updateCurlProgress(deltaX: number): void {
    const dragForward = deltaX < 0;  // 向左拖拽为翻到下一页
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
        // 首次进入卷页模式
        // 检查背景设置是否变化，如果变化则清除缓存
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
          // 没有缓存，先进入卷页模式（显示简化效果），同时异步生成 PixelMap
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
    this.onPageChange(this.currentPageIndex, this.totalPages);
    
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
  }
  
  // ========== 手势处理 ==========
  /**
   * 处理点击位置（简化版本，直接使用坐标）
   */
  private handleTapAtPosition(x: number, y: number): void {
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
    // 直接调用外部回调，不传递事件对象
    // TextReaderComponent 内部已经处理了点击区域判断，外部只需要知道"用户点击了中间区域"
    this.onTapCenter();
  }
  
  /**
   * 处理滑动手势开始
   */
  private handlePanStart(event: GestureEvent): void {
    logger.info(TAG, `handlePanStart: offsetX=${event.offsetX}, offsetY=${event.offsetY}`);
    this.touchStartX = event.offsetX;
    this.touchStartY = event.offsetY;
    this.initialTouchX = event.offsetX;  // 记录初始触摸位置用于卷页拖拽
    // 记录卷曲触摸点（用于从触摸位置开始卷曲）
    this.curlTouchX = event.fingerList[0]?.localX || event.offsetX;
    this.curlTouchY = event.fingerList[0]?.localY || event.offsetY;
    this.panStartTime = Date.now();
    this.isDragging = true;
  }
  
  /**
   * 处理滑动手势移动
   */
  private handlePanUpdate(event: GestureEvent): void {
    if (!this.isDragging) {
      return;
    }
    
    const deltaX = event.offsetX - this.initialTouchX;
    
    if (this.settings.readingMode === TextReadingMode.PAGE) {
      // 卷页动画模式
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
    logger.info(TAG, `handlePanEnd called: isDragging=${this.isDragging}, offsetX=${event.offsetX}, initialTouchX=${this.initialTouchX}`);
    
    if (!this.isDragging) {
      logger.info(TAG, `handlePanEnd: isDragging is false, returning`);
      return;
    }
    
    this.isDragging = false;
    
    const deltaX = event.offsetX - this.initialTouchX;
    const threshold = this.componentWidth * 0.2;
    const flipThreshold = this.novelCurlConfig.flipThreshold;  // 使用小说专用卷页阈值
    
    logger.info(TAG, `handlePanEnd: deltaX=${deltaX.toFixed(2)}, threshold=${threshold.toFixed(2)}, componentWidth=${this.componentWidth}, animation=${this.settings.pageTurnAnimation}, readingMode=${this.settings.readingMode}`);
    
    // 只在翻页模式下处理翻页
    if (this.settings.readingMode !== TextReadingMode.PAGE) {
      logger.info(TAG, `handlePanEnd: 非翻页模式，不处理翻页`);
      return;
    }
    
    // 卷页动画模式 - 正在显示卷页效果
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
        // 超过阈值，完成滑动翻页
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
    
    // 其他动画模式（无动画、淡入淡出等）
    if (Math.abs(deltaX) > threshold) {
      if (deltaX < 0) {
        // 向左滑动，下一页
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
    // LTR: 左=baseIndex, 右=baseIndex+1 (default, like a real book in CJK)
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
  private goToNextDualPage(): void {
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
    
    this.isForward = true;
    this.dualAnimSide = 'right';
    this.performDualPageTurn(nextBase);
  }
  
  /**
   * 双页模式翻到上一对页面
   */
  private goToPrevDualPage(): void {
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
      // 双页卷页动画
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
    const halfWidth = this.getDualPageWidth();
    const isLeftSide = x < halfWidth;
    
    if (isLeftSide) {
      // 左半区域
      const leftThird = halfWidth / 3;
      if (x < leftThird) {
        // 左页左侧1/3：上一页对
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
        // 右页右侧1/3：下一页对
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
    // 双页卷页动画需要更长时间：
    // - 第一阶段(0→0.5)：页面从边缘翻到书脊
    // - 第二阶段(0.5→1.0)：页面从书脊继续翻转落下
    // 设置最小时长确保动画可见
    const minDuration: number = isForwardAnim ? 450 : 250;
    const rawDuration: number = isForwardAnim
      ? this.novelCurlConfig.animationDuration * delta * 2.0  // 增加系数
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
   * 双页卷页动画（tap 触发的自动播放）
   * 生成 4 张 PixelMap：当前左/右 + 目标左/右
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
      
      // 延迟启动动画定时器，确保 DualPageCurlEffect Canvas 已挂载并触发 onReady
      // 如果立即启动，curlProgress @State 每16ms变化一次会触发父组件频繁重渲染，
      // 可能阻塞 UI 线程导致 Canvas onReady 延迟甚至无法触发
      setTimeout(() => {
        logger.info(TAG, `[双页卷页] 启动动画定时器, curlProgress=${this.curlProgress}`);
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
   * 双页卷页动画完成回调
   * 
   * 时序关键：必须在同一帧内完成以下操作：
   * 1. 先更新页面内容（dualLeftPageContent/dualRightPageContent）
   * 2. 然后关闭动画层（showCurlEffect = false）
   * 
   * 这样当 Canvas 层被移除时，底层 UI 已经显示新页面内容，不会闪烁。
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
    logger.info(TAG, `[onDualCurlAnimationComplete] 2.关闭动画层`);
    this.showCurlEffect = false;
    this.curlProgress = 0;
    this.stopDualCurlAnimation();
    
    // 3. 完整重置状态
    logger.info(TAG, `[onDualCurlAnimationComplete] 3.重置状态`);
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
    
    // 注意：不要在这里立即更新页面内容！
    // 如果在动画开始前就更新 dualPageBaseIndex/dualLeftPageContent，
    // 底层 Row 会立即显示新页内容，导致用户看到“直接翻页”而不是卷曲动画。
    // 页面内容应该在动画完成后由 onDualCurlAnimationComplete 统一更新。
    
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
  
  // ========== UI构建 ==========
  build() {
    // 使用 Stack 布局：所有层叠加，底部信息栏使用 position 定位
    Stack() {
      // 背景层 - 图片模式下需要底色保证文字可读性
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
      
      // 内容层
      if (this.isChapterTransition) {
        // 章节切换过渡页
        this.buildChapterTransitionPage()
      } else if (this.settings.readingMode === TextReadingMode.SCROLL) {
        // 滚动模式
        this.buildScrollMode()
      } else if (this.settings.readingMode === TextReadingMode.DUAL_PAGE) {
        // 双页模式
        this.buildDualPageMode()
      } else {
        // 翻页模式
        this.buildPageMode()
      }
      
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
      
      // 双页卷页效果层（必须放在主 build() 中，与 PageCurlEffectV2 同级；
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
      
      // 底部信息栏（使用 position 定位在底部）
      // 双页模式不显示（页码已在各自页面组件内 + PixelMap 中）
      if ((this.settings.showPageNumber || this.settings.showProgress || this.settings.showTime || this.settings.showBattery)
          && !this.isDualPageMode()) {
        this.buildPageInfo()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_, newArea) => {
      this.componentWidth = newArea.width as number;
      this.componentHeight = newArea.height as number;
      // 双页模式下每页宽度为半屏
      const baseWidth = this.isDualPageMode() ? Math.floor(this.componentWidth / 2) : this.componentWidth;
      const newContentWidth = baseWidth - this.settings.pageMargins.left - this.settings.pageMargins.right;
      // 内容区域高度 = 组件高度 - 上下页边距 - 底部状态栏高度
      const bottomBarHeight = this.getEffectiveBottomBarHeight();
      const newContentHeight = this.componentHeight - this.settings.pageMargins.top - this.settings.pageMargins.bottom - bottomBarHeight;
      
      // 检查内容区域是否真正变化（避免重复分页）
      const widthChanged = Math.abs(newContentWidth - this.lastContentAreaWidth) > 1;
      const heightChanged = Math.abs(newContentHeight - this.lastContentAreaHeight) > 1;
      
      if (!widthChanged && !heightChanged) {
        return;  // 尺寸未变化，跳过分页
      }
      
      this.contentAreaWidth = newContentWidth;
      this.contentAreaHeight = newContentHeight;
      this.lastContentAreaWidth = newContentWidth;
      this.lastContentAreaHeight = newContentHeight;
      
      logger.debug(TAG, `内容区域变化: ${this.contentAreaWidth.toFixed(0)}x${this.contentAreaHeight.toFixed(0)}`);
      
      // 使用防抖机制重新分页
      if (this.areaChangeDebounceTimer !== -1) {
        clearTimeout(this.areaChangeDebounceTimer);
      }
      this.areaChangeDebounceTimer = setTimeout(() => {
        this.areaChangeDebounceTimer = -1;
        this.paginateContent();
      }, TextReaderComponent.AREA_CHANGE_DEBOUNCE_MS);
    })
    .parallelGesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
            const x = event.fingerList[0]?.localX || 0;
            const y = event.fingerList[0]?.localY || 0;
            if (this.isDualPageMode()) {
              this.handleDualPageTap(x, y);
            } else {
              this.handleTapAtPosition(x, y);
            }
          }),
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart((event: GestureEvent) => this.handlePanStart(event))
          .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
          .onActionEnd((event: GestureEvent) => {
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
   * 构建滚动模式视图（优化：分段加载避免卡顿）
   */
  @Builder
  buildScrollMode() {
    Scroll(this.scrollController) {
      Column() {
        // 分段显示文本，避免一次性渲染大量内容导致卡顿
        ForEach(this.getTextSegments(), (segment: string, index: number) => {
          Text(segment)
            .fontSize(this.settings.textStyle.fontSize)
            .fontColor(this.settings.textStyle.textColor)
            .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
            .letterSpacing(this.settings.textStyle.letterSpacing)
            .fontWeight(this.settings.textStyle.fontWeight)
            .fontFamily(this.settings.textStyle.fontFamily)
            .textAlign(this.getTextAlign())
            .width('100%')
        })
      }
      .padding({
        top: this.settings.pageMargins.top,
        bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
        left: this.settings.pageMargins.left,
        right: this.settings.pageMargins.right
      })
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
    })
  }
  
  /**
   * 构建章节切换过渡页
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
   * 构建翻页模式视图
   * 注意：分页时已经考虑了底部状态栏高度，所以这里的 padding.bottom 需要加上状态栏高度
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
          .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .textAlign(this.getTextAlign())
          .padding({
            top: this.settings.pageMargins.top,
            bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
            left: this.settings.pageMargins.left,
            right: this.settings.pageMargins.right
          })
          .width('100%')
          .height('100%')
          .backgroundColor(this.getContentBackgroundColor())
      }
      
      // 当前页容器（支持卷曲效果）
      Stack() {
        // 当前页内容（支持长按选择文本）
        Text(this.currentPageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
          .fontFamily(this.settings.textStyle.fontFamily)
          .textAlign(this.getTextAlign())
          .padding({
            top: this.settings.pageMargins.top,
            bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
            left: this.settings.pageMargins.left,
            right: this.settings.pageMargins.right
          })
          .width('100%')
          .height('100%')
          .backgroundColor(this.getContentBackgroundColor())
          .copyOption(CopyOptions.InApp)
          .selection(this.selectionStart, this.selectionEnd)
          .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
            this.handleTextSelectionChange(selectionStart, selectionEnd);
          })
          .bindSelectionMenu(TextSpanType.TEXT, this.buildTextSelectionMenu, TextResponseType.LONG_PRESS, {
            onDisappear: () => {
              this.clearSelection();
            }
          })
        
        // 卷曲效果由 Canvas 层 PageCurlEffectV2 统一渲染（包含3D卷曲、光影、背面）
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
   * 构建双页模式视图
   * Stack 包裹：底层 Row（左右两页）+ 卷页动画层（横跨全宽）
   */
  @Builder
  buildDualPageMode() {
    Stack() {
      // === 底层：左右两页内容 ===
      Row() {
        // === 左侧书页 ===
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
          
          // 底层内容：滑动动画期间显示目标页内容
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
                .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
                .letterSpacing(this.settings.textStyle.letterSpacing)
                .fontWeight(this.settings.textStyle.fontWeight)
                .fontFamily(this.settings.textStyle.fontFamily)
                .textAlign(this.getTextAlign())
                .padding({
                  top: this.settings.pageMargins.top,
                  bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
                  left: this.settings.pageMargins.left,
                  right: this.settings.pageMargins.right
                })
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
            Text(this.dualLeftPageContent)
              .fontSize(this.settings.textStyle.fontSize)
              .fontColor(this.settings.textStyle.textColor)
              .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
              .letterSpacing(this.settings.textStyle.letterSpacing)
              .fontWeight(this.settings.textStyle.fontWeight)
              .fontFamily(this.settings.textStyle.fontFamily)
              .textAlign(this.getTextAlign())
              .padding({
                top: this.settings.pageMargins.top,
                bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
                left: this.settings.pageMargins.left,
                right: this.settings.pageMargins.right
              })
              .width('100%')
              .height('100%')
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
        
        // === 右侧书页 ===
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
          
          // 底层内容：滑动动画期间显示目标页内容
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
                .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
                .letterSpacing(this.settings.textStyle.letterSpacing)
                .fontWeight(this.settings.textStyle.fontWeight)
                .fontFamily(this.settings.textStyle.fontFamily)
                .textAlign(this.getTextAlign())
                .padding({
                  top: this.settings.pageMargins.top,
                  bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
                  left: this.settings.pageMargins.left,
                  right: this.settings.pageMargins.right
                })
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
            Text(this.dualRightPageContent)
              .fontSize(this.settings.textStyle.fontSize)
              .fontColor(this.settings.textStyle.textColor)
              .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
              .letterSpacing(this.settings.textStyle.letterSpacing)
              .fontWeight(this.settings.textStyle.fontWeight)
              .fontFamily(this.settings.textStyle.fontFamily)
              .textAlign(this.getTextAlign())
              .padding({
                top: this.settings.pageMargins.top,
                bottom: this.settings.pageMargins.bottom + this.getEffectiveBottomBarHeight(),
                left: this.settings.pageMargins.left,
                right: this.settings.pageMargins.right
              })
              .width('100%')
              .height('100%')
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
   * 构建页码信息视图
   * 单页布局：左下角(电量) | 中央(时间) | 右下角(页码或进度)
   * 双页布局：左下角(左页页码) | 中央(电量+时间) | 右下角(右页页码)
   */
  @Builder
  buildPageInfo() {
    if (this.isDualPageMode()) {
      // 双页模式布局
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
      this.selectedText = this.currentPageContent.substring(start, end);
      this.onTextSelected(this.selectedText);
    }
  }
}
