/**
 * 文本阅读器核心组件
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
 */

import { logger } from '../Utils/Logger';
import { curves, componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { KeyCode } from '@kit.InputKit';
import batteryInfo from '@ohos.batteryInfo';
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
 * 文本阅读器组件
 */
@Component
export struct TextReaderComponent {
  // ========== 外部参数 ==========
  /** 文本内容 */
  @Prop content: string = '';
  /** 章节列表（可选） */
  @Prop chapters: TextChapter[] = [];
  /** 阅读设置 */
  @Link settings: TextReaderSettings;
  /** 当前章节索引 */
  @Link currentChapterIndex: number;
  /** 当前页面索引 */
  @Link currentPageIndex: number;
  /** 底部状态栏高度（用于避让底部信息显示区域） */
  @Prop bottomStatusBarHeight: number = 28;
  
  // ========== 回调函数 ==========
  onPageChange: (pageIndex: number, totalPages: number) => void = () => {};
  onChapterChange: (chapterIndex: number) => void = () => {};
  onProgressChange: (progress: number) => void = () => {};
  onTap: (event: ClickEvent) => void = () => {};
  
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
  @State private curlAnimateTarget: number = -1;  // 内部动画目标进度（-1表示不使用）
  @State private curlAnimateFrom: number = 0;     // 内部动画起始进度
  private curlPendingPageIndex: number = -1;      // 待切换的页面索引
  private curlAnimationTimer: number = -1;        // 卷页动画定时器
  private pagePixelMapCache: Map<number, image.PixelMap> = new Map();  // 页面 PixelMap 缓存
  private isGeneratingPixelMap: boolean = false;  // 是否正在生成 PixelMap
  
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
  
  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, '文本阅读器组件初始化');
    // 启动时间更新定时器
    this.startTimeUpdate();
    // 获取电量
    this.updateBatteryLevel();
  }
  
  aboutToDisappear(): void {
    logger.info(TAG, '文本阅读器组件销毁');
    this.releaseAllPixelMapCache();
    this.stopCurlAnimation();
    // 停止时间更新
    this.stopTimeUpdate();
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
      this.goToPrevPage();
      return true;
    } else if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      logger.info(TAG, '音量键翻页: 下一页');
      this.goToNextPage();
      return true;
    }
    
    return false;
  }
  
  // ========== 分页算法 ==========
  /**
   * 计算并分页文本内容
   */
  private paginateContent(): void {
    if (!this.content || this.contentAreaWidth <= 0 || this.contentAreaHeight <= 0) {
      return;
    }
    
    const fontSize = this.settings.textStyle.fontSize;
    const lineHeight = this.settings.textStyle.lineHeight;
    const paragraphSpacing = this.settings.textStyle.paragraphSpacing;
    const firstLineIndent = this.settings.textStyle.firstLineIndent;
    const actualLineHeight = fontSize * lineHeight;
    
    // 计算每页可容纳的行数
    const linesPerPage = Math.floor(this.contentAreaHeight / actualLineHeight);
    
    // 计算每行可容纳的字符数（粗略估计）
    const charsPerLine = Math.floor(this.contentAreaWidth / (fontSize * 0.6));
    
    // 分段处理
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
      
      // 处理首行缩进
      const indentChars = firstLineIndent > 0 ? '　'.repeat(Math.floor(firstLineIndent)) : '';
      const indentedParagraph = indentChars + paragraph.trim();
      
      // 将段落分成行
      let remainingText = indentedParagraph;
      let isFirstLine = true;
      
      while (remainingText.length > 0) {
        const effectiveCharsPerLine = isFirstLine ? charsPerLine - Math.floor(firstLineIndent) : charsPerLine;
        const lineText = remainingText.substring(0, effectiveCharsPerLine);
        remainingText = remainingText.substring(effectiveCharsPerLine);
        
        currentPageLines.push(lineText);
        currentLineCount++;
        isFirstLine = false;
        
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
      
      // 段落结束后添加空行
      if (currentLineCount < linesPerPage - 1) {
        currentLineCount++; // 段落间距
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
    
    // 更新当前页面内容
    this.updatePageContents();
    
    logger.info(TAG, `分页完成: 总页数=${this.totalPages}`);
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
  }
  
  // ========== 翻页逻辑 ==========
  /**
   * 翻到下一页
   */
  private goToNextPage(): void {
    if (this.isAnimating || this.currentPageIndex >= this.totalPages - 1) {
      return;
    }
    
    this.isForward = true;
    this.performPageTurn(this.currentPageIndex + 1);
  }
  
  /**
   * 翻到上一页
   */
  private goToPrevPage(): void {
    if (this.isAnimating || this.currentPageIndex <= 0) {
      return;
    }
    
    this.isForward = false;
    this.performPageTurn(this.currentPageIndex - 1);
  }
  
  /**
   * 跳转到指定页面
   */
  private goToPage(pageIndex: number): void {
    if (this.isAnimating || pageIndex < 0 || pageIndex >= this.totalPages) {
      return;
    }
    
    this.isForward = pageIndex > this.currentPageIndex;
    this.performPageTurn(pageIndex);
  }
  
  /**
   * 执行翻页动画
   */
  private performPageTurn(targetPageIndex: number): void {
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
    this.currentPageIndex = targetPageIndex;
    this.updatePageContents();
    this.notifyPageChange();
  }
  
  /**
   * 滑动动画翻页
   */
  private performSlideAnimation(targetPageIndex: number): void {
    this.isAnimating = true;
    const direction = this.isForward ? -1 : 1;
    const targetOffset = direction * this.componentWidth;
    
    animateTo({
      duration: 300,
      curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1)
    }, () => {
      this.slideOffset = targetOffset;
    });
    
    setTimeout(() => {
      this.currentPageIndex = targetPageIndex;
      this.updatePageContents();
      this.slideOffset = 0;
      this.isAnimating = false;
      this.notifyPageChange();
    }, 300);
  }
  
  /**
   * 淡入淡出动画翻页
   */
  private performFadeAnimation(targetPageIndex: number): void {
    this.isAnimating = true;
    
    animateTo({
      duration: 150,
      curve: Curve.EaseOut
    }, () => {
      this.slideOpacity = 0;
    });
    
    setTimeout(() => {
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
        this.notifyPageChange();
      }, 150);
    }, 150);
  }
  
  /**
   * 卷页动画翻页（拟真翻页效果）
   * 支持交互式拖拽和自动动画两种模式
   */
  private performCurlAnimation(targetPageIndex: number): void {
    // 生成当前页和目标页的PixelMap
    this.generatePagePixelMaps(this.currentPageIndex, targetPageIndex).then(() => {
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
      this.performSlideAnimation(targetPageIndex);
    });
  }
  
  /**
   * 生成页面的PixelMap（用于卷页效果）
   * 使用 componentSnapshot.createFromBuilder 截取真实的页面渲染结果
   */
  private async generatePagePixelMaps(currentIndex: number, targetIndex: number): Promise<void> {
    if (this.isGeneratingPixelMap) {
      logger.warn(TAG, '正在生成 PixelMap，跳过重复请求');
      return;
    }
    
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
        if (this.currentPixelMap) {
          this.pagePixelMapCache.set(currentIndex, this.currentPixelMap);
        }
      }
      
      if (cachedTarget) {
        this.nextPixelMap = cachedTarget;
      } else if (targetIndex >= 0 && targetIndex < this.totalPages) {
        // 生成目标页 PixelMap
        this.nextPixelMap = await this.renderPageToPixelMap(targetIndex);
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
    const width = Math.round(this.componentWidth);
    const height = Math.round(this.componentHeight);
    
    if (width <= 0 || height <= 0) {
      logger.warn(TAG, `组件尺寸无效: ${width}x${height}`);
      return null;
    }
    
    try {
      // 使用 componentSnapshot.createFromBuilder 截取页面
      // 参数：builder 函数, delay(可选), checkImageStatus(可选), options(可选)
      const pixelMap: image.PixelMap = await componentSnapshot.createFromBuilder(
        () => { this.buildPageForSnapshot(pageContent, width, height); }
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
   */
  @Builder
  buildPageForSnapshot(content: string, width: number, height: number) {
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
      Text(content)
        .fontSize(this.settings.textStyle.fontSize)
        .fontColor(this.settings.textStyle.textColor)
        .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
        .letterSpacing(this.settings.textStyle.letterSpacing)
        .fontWeight(this.settings.textStyle.fontWeight)
        .textAlign(this.getTextAlign())
        .padding({
          top: this.settings.pageMargins.top,
          bottom: this.settings.pageMargins.bottom,
          left: this.settings.pageMargins.left,
          right: this.settings.pageMargins.right
        })
        .width(width)
        .height(height)
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
          
          logger.info(TAG, `进入卷页拖拽模式(缓存): ${this.currentPageIndex} -> ${targetIndex}`);
        } else {
          // 没有缓存，异步生成
          this.generatePagePixelMaps(this.currentPageIndex, targetIndex).then(() => {
            if (this.currentPixelMap) {
              this.showCurlEffect = true;
              this.curlPendingPageIndex = targetIndex;
              this.isAnimating = true;
              logger.info(TAG, `进入卷页拖拽模式(生成): ${this.currentPageIndex} -> ${targetIndex}`);
            }
          });
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
    const progress = this.totalPages > 0 ? (this.currentPageIndex + 1) / this.totalPages * 100 : 0;
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
    
    const screenThird = this.componentWidth / 3;
    
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
   * 简化的点击回调（不需要完整的 ClickEvent）
   */
  private onTapSimple(): void {
    // 直接调用外部回调，不传递事件对象
    // 这里我们传递一个简化的事件对象
    this.onTap({} as ClickEvent);
  }
  
  /**
   * 处理滑动手势开始
   */
  private handlePanStart(event: GestureEvent): void {
    this.touchStartX = event.offsetX;
    this.touchStartY = event.offsetY;
    this.initialTouchX = event.offsetX;  // 记录初始触摸位置用于卷页拖拽
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
      }
    }
  }
  
  /**
   * 处理滑动手势结束
   */
  private handlePanEnd(event: GestureEvent): void {
    if (!this.isDragging) {
      return;
    }
    
    this.isDragging = false;
    
    const deltaX = event.offsetX - this.initialTouchX;
    const threshold = this.componentWidth * 0.2;
    const flipThreshold = 0.35;  // 卷页翻页阈值
    
    // 卷页动画模式
    if (this.settings.pageTurnAnimation === TextPageTurnAnimation.CURL && this.showCurlEffect) {
      if (this.curlProgress >= flipThreshold) {
        // 超过阈值，完成翻页
        this.animateCurlToComplete();
      } else {
        // 未超过阈值，回弹
        this.animateCurlToCancel();
      }
      return;
    }
    
    // 滑动动画模式
    if (Math.abs(deltaX) > threshold) {
      if (deltaX < 0) {
        // 向左滑动，下一页
        this.goToNextPage();
      } else {
        // 向右滑动，上一页
        this.goToPrevPage();
      }
    } else {
      // 回弹
      animateTo({
        duration: 200,
        curve: Curve.EaseOut
      }, () => {
        this.slideOffset = 0;
      });
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
  
  // ========== UI构建 ==========
  build() {
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
      if (this.settings.readingMode === TextReadingMode.SCROLL) {
        // 滚动模式
        this.buildScrollMode()
      } else {
        // 翻页模式
        this.buildPageMode()
      }
      
      // 卷页效果层（当使用卷页动画时）
      if (this.showCurlEffect && this.currentPixelMap) {
        PageCurlEffectV2({
          currentPixelMap: this.currentPixelMap,
          nextPixelMap: this.nextPixelMap,
          componentWidth: this.componentWidth,
          componentHeight: this.componentHeight,
          imageDisplayX: 0,
          imageDisplayY: 0,
          imageDisplayWidth: this.componentWidth,
          imageDisplayHeight: this.componentHeight,
          isForward: this.isForward,
          curlStartPosition: this.curlStartPosition,
          externalProgress: this.curlProgress,
          animateToTarget: this.curlAnimateTarget,
          animateFromProgress: this.curlAnimateFrom,
          curlBackOpacity: this.settings.curlBackOpacity ?? 90,
          onAnimationComplete: () => {
            // 内部动画完成回调
            if (this.curlAnimateTarget >= 1.0) {
              this.onCurlAnimationComplete();
            } else if (this.curlAnimateTarget <= 0) {
              this.resetCurlState();
            }
          }
        })
      }
      
      // 页码信息层
      if (this.settings.showPageNumber || this.settings.showProgress) {
        this.buildPageInfo()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_, newArea) => {
      this.componentWidth = newArea.width as number;
      this.componentHeight = newArea.height as number;
      this.contentAreaWidth = this.componentWidth - this.settings.pageMargins.left - this.settings.pageMargins.right;
      // 内容区域高度 = 组件高度 - 上下页边距 - 底部状态栏高度
      // 分页时需要考虑底部状态栏，确保每页文字不会被遮挡
      const bottomBarHeight = this.getEffectiveBottomBarHeight();
      this.contentAreaHeight = this.componentHeight - this.settings.pageMargins.top - this.settings.pageMargins.bottom - bottomBarHeight;
      
      logger.debug(TAG, `内容区域: ${this.contentAreaWidth}x${this.contentAreaHeight}, 底部状态栏高度: ${bottomBarHeight}`);
      
      // 重新分页
      this.paginateContent();
    })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction((event: GestureEvent) => {
            // 简化处理：直接从手势事件获取坐标
            const x = event.fingerList[0]?.localX || 0;
            const y = event.fingerList[0]?.localY || 0;
            this.handleTapAtPosition(x, y);
          }),
        PanGesture({ direction: PanDirection.Horizontal })
          .onActionStart((event: GestureEvent) => this.handlePanStart(event))
          .onActionUpdate((event: GestureEvent) => this.handlePanUpdate(event))
          .onActionEnd((event: GestureEvent) => this.handlePanEnd(event))
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
   * 构建翻页模式视图
   * 注意：分页时已经考虑了底部状态栏高度，所以这里的 padding.bottom 需要加上状态栏高度
   * 这样文字内容会在状态栏上方结束，不会被遮挡
   */
  @Builder
  buildPageMode() {
    Stack() {
      // 下一页（在底层，滑动时露出）
      if (this.slideOffset !== 0 || this.showCurlEffect) {
        Text(this.isForward ? this.nextPageContent : this.prevPageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
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
        // 当前页内容
        Text(this.currentPageContent)
          .fontSize(this.settings.textStyle.fontSize)
          .fontColor(this.settings.textStyle.textColor)
          .lineHeight(this.settings.textStyle.fontSize * this.settings.textStyle.lineHeight)
          .letterSpacing(this.settings.textStyle.letterSpacing)
          .fontWeight(this.settings.textStyle.fontWeight)
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
        
        // 卷曲效果叠加层
        if (this.showCurlEffect && this.curlProgress > 0) {
            // 页面内侧阴影（模拟纸张弯曲产生的阴影）
            Column()
              .width(80 * this.curlProgress)
              .height('100%')
              .position({ x: this.isForward ? '100%' : 0, y: 0 })
              .translate({ x: this.isForward ? -80 * this.curlProgress : 0 })
              .linearGradient({
                angle: this.isForward ? 90 : 270,
                colors: [
                  ['rgba(0,0,0,0.4)', 0],
                  ['rgba(0,0,0,0.15)', 0.3],
                  ['rgba(0,0,0,0)', 1]
                ]
              })
            
            // 页面翻起边缘高光（模拟纸张边缘的反光）
            Column()
              .width(3)
              .height('100%')
              .position({ x: this.isForward ? '100%' : 0, y: 0 })
              .translate({ x: this.isForward ? -3 : 0 })
              .linearGradient({
                angle: this.isForward ? 90 : 270,
                colors: [
                  ['rgba(255,255,255,0.6)', 0],
                  ['rgba(255,255,255,0.2)', 0.5],
                  ['rgba(255,255,255,0)', 1]
                ]
              })
              .opacity(this.curlProgress * 0.7)
            
            // 纸张背面渐变（模拟翻起页面的背面）
            if (this.curlProgress > 0.2) {
              Column()
                .width(50 * this.curlProgress)
                .height('100%')
                .position({ x: this.isForward ? '100%' : 0, y: 0 })
                .translate({ x: this.isForward ? -50 * this.curlProgress - 3 : 3 })
                .linearGradient({
                  angle: this.isForward ? 270 : 90,
                  colors: [
                    ['rgba(240,235,220,0.9)', 0],
                    ['rgba(220,215,200,0.7)', 0.5],
                    ['rgba(200,195,180,0.4)', 1]
                  ]
                })
                .opacity(Math.min((this.curlProgress - 0.2) * 1.25, 0.8))
            }
          }
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.slideOffset })
        .opacity(this.slideOpacity)
        // 卷曲动画时添加更明显的3D透视效果
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.showCurlEffect ? this.curlProgress * (this.isForward ? -25 : 25) : 0,
          centerX: this.isForward ? '100%' : '0%',
          centerY: '50%'
        })
        // 添加轻微的缩放效果模拟透视
        .scale({
          x: this.showCurlEffect ? 1 - this.curlProgress * 0.02 : 1,
          y: this.showCurlEffect ? 1 - this.curlProgress * 0.01 : 1,
          centerX: this.isForward ? '0%' : '100%',
          centerY: '50%'
        })
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
  
  /**
   * 构建页码信息视图
   * 布局：左下角(电量) | 中央(时间) | 右下角(页码或进度)
   */
  @Builder
  buildPageInfo() {
    Row() {
      // 左下角：电量显示
      if (this.settings.showBattery) {
        Row({ space: 4 }) {
          // 电池图标
          Stack() {
            // 电池外框
            Row()
              .width(20)
              .height(10)
              .borderRadius(2)
              .border({ width: 1, color: this.settings.textStyle.textColor })
              .opacity(0.6)
            // 电池电量
            Row()
              .width(16 * this.batteryLevel / 100)
              .height(6)
              .backgroundColor(this.batteryLevel > 20 ? this.settings.textStyle.textColor : '#FF4444')
              .opacity(0.6)
              .borderRadius(1)
              .margin({ left: 2 })
            // 电池头
            Row()
              .width(2)
              .height(4)
              .backgroundColor(this.settings.textStyle.textColor)
              .opacity(0.6)
              .position({ x: 20, y: 3 })
          }
          .width(24)
          .height(10)
          
          Text(`${this.batteryLevel}%`)
            .fontSize(11)
            .fontColor(this.settings.textStyle.textColor)
            .opacity(0.6)
        }
      }
      
      Blank()
      
      // 中央：时间显示
      if (this.settings.showTime) {
        Text(this.currentTime)
          .fontSize(12)
          .fontColor(this.settings.textStyle.textColor)
          .opacity(0.6)
      }
      
      Blank()
      
      // 右下角：页码或进度（二选一）
      if (this.settings.showPageNumber) {
        Text(`${this.currentPageIndex + 1} / ${this.totalPages}`)
          .fontSize(12)
          .fontColor(this.settings.textStyle.textColor)
          .opacity(0.6)
      } else if (this.settings.showProgress) {
        Text(`${this.totalPages > 0 ? Math.round((this.currentPageIndex + 1) / this.totalPages * 100) : 0}%`)
          .fontSize(12)
          .fontColor(this.settings.textStyle.textColor)
          .opacity(0.6)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 8 })
    .position({ x: 0, y: '100%' })
    .translate({ y: '-100%' })
  }
}
