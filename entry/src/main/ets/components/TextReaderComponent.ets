/**
 * 文本阅读器核心组件
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
 */

import { logger } from '../Utils/Logger';
import { curves, componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import measure from '@ohos.measure';
import { display } from '@kit.ArkUI';
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
  private pagePixelMapCache: Map<number, image.PixelMap> = new Map();  // 页面 PixelMap 缓存
  private isGeneratingPixelMap: boolean = false;  // 是否正在生成 PixelMap
  private isPaginating: boolean = false;  // 是否正在分页
  private paginationVersion: number = 0;  // 分页版本号，用于取消旧的分页任务
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
  
  // ========== 生命周期 ==========
  aboutToAppear(): void {
    logger.info(TAG, '文本阅读器组件初始化');
    // 启动时间更新定时器
    this.startTimeUpdate();
    // 获取电量
    this.updateBatteryLevel();
    // 记录初始内容和章节索引
    this.lastContent = this.content;
    this.lastChapterIndex = this.currentChapterIndex;
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
      
      // 停止正在进行的动画
      this.stopCurlAnimation();
      this.isAnimating = false;
      
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
      logger.info(TAG, `组件尺寸未初始化，延迟分页`);
      // 延迟重试，等待组件尺寸初始化
      setTimeout(() => {
        if (currentVersion === this.paginationVersion) {
          this.paginateContentAsync();
        }
      }, 100);
      return;
    }
    
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
        this.currentPageIndex = this.totalPages - 1;
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
   */
  private getAvgCharWidth(): number {
    const fontSize = this.settings.textStyle.fontSize;
    if (this.cachedAvgCharWidth > 0 && this.cachedFontSize === fontSize) {
      return this.cachedAvgCharWidth;
    }
    
    // 使用常见中文字符测量平均宽度
    const sampleText = '测试文本字符';
    const width = this.measureTextWidthFast(sampleText);
    this.cachedAvgCharWidth = width / sampleText.length;
    this.cachedFontSize = fontSize;
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
    const charsPerLine = Math.max(1, Math.floor(maxWidth / avgCharWidth * widthFactor));
    
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
   * 使用精确测量确保分页结果与实际渲染一致
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
      // 注意：段落间距通过空行实现，需要同时添加到 currentPageLines 和 currentLineCount
      if (currentLineCount > 0 && currentLineCount < linesPerPage) {
        currentPageLines.push('');  // 添加空行作为段落间距
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
    
    // 更新当前页面内容
    this.updatePageContents();
    
    // 分页完成后预加载相邻页面的 PixelMap（用于卷页动画）
    this.preloadAdjacentPagePixelMaps();
    
    logger.info(TAG, `分页完成: 总页数=${this.totalPages}, 每页行数=${linesPerPage}`);
    
    // 触发就绪回调
    this.onReady();
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
    // 安全检查：分页中、加载中、动画中、或页面数据无效时不允许翻页
    if (this.isAnimating || this.isPaginating || this.isLoading || this.pages.length === 0) {
      logger.debug(TAG, `goToNextPage 被阻止: isAnimating=${this.isAnimating}, isPaginating=${this.isPaginating}, isLoading=${this.isLoading}, pages=${this.pages.length}`);
      return;
    }
    if (this.currentPageIndex >= this.totalPages - 1) {
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
        return;
      }
      
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
    // 安全检查
    if (this.pages.length === 0 || targetPageIndex < 0 || targetPageIndex >= this.pages.length) {
      logger.warn(TAG, `performFadeAnimation: 页面数据无效，跳过动画`);
      return;
    }
    
    this.isAnimating = true;
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
    
    this.isAnimating = true;
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
      // 显示过渡页
      this.isChapterTransition = true;
      this.slideOffset = 0;
      
      // 100ms 后切换章节并滑动过去
      setTimeout(() => {
        // 切换章节
        this.currentChapterIndex = nextChapterIndex;
        this.currentPageIndex = 0;
        
        // 通知章节变化（外部会更新内容）
        this.onChapterChange(this.currentChapterIndex);
        
        // 延迟一帧后滑动出过渡页
        setTimeout(() => {
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
    
    this.isAnimating = true;
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
      // 显示过渡页
      this.isChapterTransition = true;
      this.slideOffset = 0;
      
      // 100ms 后切换章节并滑动过去
      setTimeout(() => {
        // 切换章节
        this.currentChapterIndex = prevChapterIndex;
        
        // 通知章节变化（外部会更新内容，分页完成后会检查 shouldJumpToLastPage）
        this.onChapterChange(this.currentChapterIndex);
        
        // 延迟一帧后滑动出过渡页
        setTimeout(() => {
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
    // 使用整个组件高度，通过 padding 避让底部信息栏（与实际显示一致）
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
      // 通过 padding 避让底部信息栏，与实际显示的 buildPageMode 一致
      Text(content)
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
        logger.debug(TAG, `handlePanUpdate: slideOffset=${this.slideOffset.toFixed(2)}`);
      }
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
    const flipThreshold = 0.35;  // 卷页翻页阈值
    
    logger.info(TAG, `handlePanEnd: deltaX=${deltaX.toFixed(2)}, threshold=${threshold.toFixed(2)}, componentWidth=${this.componentWidth}, animation=${this.settings.pageTurnAnimation}, readingMode=${this.settings.readingMode}`);
    
    // 只在翻页模式下处理翻页
    if (this.settings.readingMode !== TextReadingMode.PAGE) {
      logger.info(TAG, `handlePanEnd: 非翻页模式，不处理翻页`);
      return;
    }
    
    // 卷页动画模式 - 正在显示卷页效果
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
   * 包含：背景设置、文字样式（颜色、字号、行高、字间距、字重、对齐方式）、页边距
   */
  private getRenderSignature(): string {
    const bg = this.settings.background;
    const ts = this.settings.textStyle;
    const pm = this.settings.pageMargins;
    return `${bg.type}|${bg.color}|${bg.imagePath}|${bg.imageOpacity}|` +
           `${ts.textColor}|${ts.fontSize}|${ts.lineHeight}|${ts.letterSpacing}|${ts.fontWeight}|${ts.textAlignment}|` +
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
      } else {
        // 翻页模式
        this.buildPageMode()
      }
      
      // 卷页效果层（当使用卷页动画时）
      // 卷页动画需要基于文本区域（避让底部信息栏），而非整个组件
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
          curlTouchX: this.curlTouchX,
          curlTouchY: this.curlTouchY,
          externalProgress: this.curlProgress,
          animateToTarget: this.curlAnimateTarget,
          animateFromProgress: this.curlAnimateFrom,
          curlBackOpacity: 100,  // 被卷起的页面完全不透明
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
      
      // 底部信息栏（使用 position 定位在底部）
      if (this.settings.showPageNumber || this.settings.showProgress || this.settings.showTime || this.settings.showBattery) {
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
      // 左侧容器（固定宽度，确保中间内容居中）
      Row() {
        // 左下角：电量显示（精美的电池图标设计）
        if (this.settings.showBattery) {
          Row({ space: 6 }) {
            // 精美电池图标
            Stack({ alignContent: Alignment.Start }) {
              // 电池外框（圆角矩形）
              Row()
                .width(22)
                .height(11)
                .borderRadius(3)
                .border({ width: 1.5, color: this.settings.textStyle.textColor })
                .opacity(0.5)
              // 电池电量填充（渐变色）
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
              // 电池正极头（圆角）
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
      
      // 中央：时间显示（使用 layoutWeight 确保居中）
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
      
      // 右侧容器（固定宽度，确保中间内容居中）
      Row() {
        // 右下角：页码或进度（二选一）
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
