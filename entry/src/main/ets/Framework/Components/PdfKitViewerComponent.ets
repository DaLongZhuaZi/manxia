// 文件路径: entry/src/main/ets/Framework/Components/PdfKitViewerComponent.ets
/**
 * PDF Kit 阅读器组件
 * 使用 PDF Kit 的 PdfView 组件进行 PDF 文档预览
 * 支持阅读进度保存和恢复
 * 
 * 实现方案：
 * 1. 使用单页非连续模式 (isContinuous: false)
 * 2. 通过手势检测实现左右滑动翻页
 * 3. 滑动完成后调用 goToPage() 并更新页码
 * 4. 点击屏幕中央显示页码指示器
 */

import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { EBook, EBookReadingProgress, EBookReadingSettings, EBookPageMode } from 'manxia_core/src/main/ets/Models/EBookModels';

const TAG = 'PdfKitViewerComponent';
/** 批注颜色（数值型，传给 PDF Kit 的 addMarkupAnnotation，不属于 UI 样式） */
const ANNOTATION_HIGHLIGHT_COLOR: number = 0xFFFFEB3B;
const ANNOTATION_UNDERLINE_COLOR: number = 0xFF1976D2;

// 滑动翻页的阈值（像素）
const SWIPE_THRESHOLD = 50;
// 滑动速度阈值
const SWIPE_VELOCITY_THRESHOLD = 300;

/**
 * PDF 阅读器回调接口
 */
export interface PdfViewerCallbacks {
  onPageChange?: (currentPage: number, totalPages: number) => void;
  onLoadComplete?: (pageCount: number) => void;
  onLoadError?: (error: string) => void;
  /** 文本选择变化（text 为空表示取消选择） */
  onTextSelected?: (text: string, pageIndex: number) => void;
  /** 批注发生变更（新增/删除） */
  onAnnotationChanged?: () => void;
  /** 点击屏幕中间区域（用于切换阅读器工具栏） */
  onCenterTap?: () => void;
}

export interface PdfViewerController {
  goToPreviousPage: () => boolean;
  goToNextPage: () => boolean;
  isControllerReady: () => boolean;
  /** 跳转到 0-indexed 页 */
  goToPage: (pageIndex: number) => void;
  getCurrentPageIndex: () => number;
  getTotalPages: () => number;
  /** 页面适配：整页/适宽/适高 */
  setPageFit: (mode: pdfService.PageFit) => void;
  getPageFit: () => pdfService.PageFit;
  /** 连续滚动 */
  setContinuous: (continuous: boolean) => void;
  isContinuous: () => boolean;
  /** 缩放（0.1-10） */
  setZoom: (zoom: number) => void;
  getZoom: () => number;
  /** 文本选择/划重点模式（开启后由 PdfView 接管手势） */
  setSelectionMode: (enabled: boolean) => void;
  isSelectionMode: () => boolean;
  /** 夜间整体压暗 */
  setNightOverlay: (enabled: boolean) => void;
  isNightOverlay: () => boolean;
  /** 应用电子书阅读设置（字号->缩放、主题/背景->页面底色） */
  applyReadingSettings: (settings: EBookReadingSettings, isInit: boolean) => void;
  /** PDF Kit 全文检索：返回匹配总数（0 表示未命中） */
  searchKeyword: (keyword: string) => Promise<number>;
  goToNextSearchMatch: () => number;
  goToPreviousSearchMatch: () => number;
  getSearchMatchIndex: () => number;
  getSearchMatchCount: () => number;
  clearSearchKeyword: () => void;
  /** 用给定颜色高亮当前选中的文本 */
  highlightSelection: (color: number) => boolean;
  /** 将当前批注保存到指定文件（通常为工作副本） */
  saveAnnotatedCopy: (targetPath: string) => Promise<boolean>;
}

/**
 * PDF Kit 阅读器组件
 */
@Component
export struct PdfKitViewerComponent {
  // 电子书数据
  @Prop ebook: EBook | null = null;
  // 阅读设置
  @Prop readingSettings: EBookReadingSettings | null = null;
  // 背景色（响应主题）- 使用 themeBgColor 避免与 CustomComponent 的 backgroundColor 冲突
  /** 背景色（由宿主页面传入主题色；为空时回退系统资源） */
  @Prop themeBgColor: string = '';
  // 回调
  callbacks: PdfViewerCallbacks = {};
  onControllerReady: (controller: PdfViewerController) => void = (_controller: PdfViewerController): void => {};
  
  // 内部状态
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State currentPage: number = 1;
  @State totalPages: number = 0;
  @State showPageIndicator: boolean = false; // 是否显示页码指示器
  @State showPageInput: boolean = false;
  @State pageInputValue: string = '1';
  
  // 手势相关状态
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private touchStartTime: number = 0;
  private isSwiping: boolean = false;
  
  // 组件尺寸
  @State componentWidth: number = 360;
  
  // PDF Kit 控制器
  private pdfController: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private isDocumentLoaded: boolean = false;
  
  // 页码指示器自动隐藏定时器
  private indicatorTimer: number = -1;
  
  // 防止重复保存进度
  private hasSavedOnExit: boolean = false;

  // [Phase4] 阅读增强状态
  @State pageFitMode: number = pdfService.PageFit.FIT_PAGE;
  @State continuousMode: boolean = false;
  @State zoomLevel: number = 1;
  @State nightOverlayEnabled: boolean = false;
  /** 页面叠加底色（ARGB 十六进制，'#00000000' 表示不叠加） */
  @State tintColorValue: string = '#00000000';
  /** PDF Kit 检索结果 */
  @State searchMatchCount: number = 0;
  @State searchMatchIndex: number = 0;
  /** 用户是否已主动点击过上一处/下一处（PDF Kit 的 searchKey 会自行跳到首个匹配，
   *  因此检索后需要把页面恢复到用户原来位置，只有用户点击后才真正跳转） */
  private searchJumpedByUser: boolean = false;
  @State selectionMode: boolean = false;
  @State hasSelection: boolean = false;
  private lastSelectedText: string = '';
  private lastSelectedRects: Array<pdfViewManager.SelectedRects> = [];

  aboutToAppear(): void {
    logger.info(TAG, 'PdfKitViewerComponent aboutToAppear');
    const controller: PdfViewerController = {
      goToPreviousPage: (): boolean => this.goToPrevPage(),
      goToNextPage: (): boolean => this.goToNextPage(),
      isControllerReady: (): boolean => this.isDocumentLoaded && this.totalPages > 0 && !this.isLoading && this.errorMessage.length === 0,
      goToPage: (pageIndex: number): void => this.goToPageIndex(pageIndex),
      getCurrentPageIndex: (): number => this.currentPage - 1,
      getTotalPages: (): number => this.totalPages,
      setPageFit: (mode: pdfService.PageFit): void => this.applyPageFit(mode),
      getPageFit: (): pdfService.PageFit => this.pageFitMode as pdfService.PageFit,
      setContinuous: (continuous: boolean): void => this.applyContinuous(continuous),
      isContinuous: (): boolean => this.continuousMode,
      setZoom: (zoom: number): void => this.applyZoom(zoom),
      getZoom: (): number => this.zoomLevel,
      setSelectionMode: (enabled: boolean): void => this.setSelectionModeInternal(enabled),
      isSelectionMode: (): boolean => this.selectionMode,
      setNightOverlay: (enabled: boolean): void => this.setNightOverlayInternal(enabled),
      isNightOverlay: (): boolean => this.nightOverlayEnabled,
      applyReadingSettings: (settings: EBookReadingSettings, isInit: boolean): void => this.applyPdfReadingSettings(settings, isInit),
      searchKeyword: (keyword: string): Promise<number> => this.searchKeywordInView(keyword),
      goToNextSearchMatch: (): number => this.goToNextSearchMatch(),
      goToPreviousSearchMatch: (): number => this.goToPreviousSearchMatch(),
      getSearchMatchIndex: (): number => this.searchMatchIndex,
      getSearchMatchCount: (): number => this.searchMatchCount,
      clearSearchKeyword: (): void => this.clearSearchKeyword(),
      highlightSelection: (color: number): boolean => this.highlightCurrentSelection(color),
      saveAnnotatedCopy: (targetPath: string): Promise<boolean> => this.saveAnnotated(targetPath)
    };
    this.onControllerReady(controller);

    // [Phase4] 文本选择监听（用于划重点与复制）
    this.pdfController.registerTextSelectedListener((param: pdfViewManager.TextSelectedParam) => {
      this.lastSelectedText = param.text ?? '';
      this.lastSelectedRects = param.pdfRect ?? [];
      this.hasSelection = this.lastSelectedText.length > 0;
      if (this.callbacks.onTextSelected) {
        this.callbacks.onTextSelected(this.lastSelectedText, this.currentPage - 1);
      }
    });
    this.pdfController.registerAnnotationChangedListener((param: pdfViewManager.AnnotationChangedParam) => {
      if (this.callbacks.onAnnotationChanged) {
        this.callbacks.onAnnotationChanged();
      }
    });
    
    // 注册页数变化监听器
    this.pdfController.registerPageCountChangedListener((pageCount: number) => {
      logger.info(TAG, `PDF 页数变化: ${pageCount}`);
      this.totalPages = pageCount;
      if (this.callbacks.onLoadComplete) {
        this.callbacks.onLoadComplete(pageCount);
      }
    });
    
    // 加载 PDF 文档
    if (this.ebook && this.ebook.filePath) {
      this.loadPdfDocument();
    }
  }

  private goToPageIndex(pageIndex: number): void {
    if (!this.isDocumentLoaded || pageIndex < 0) {
      return;
    }
    const clamped: number = Math.min(pageIndex, Math.max(0, this.totalPages - 1));
    try {
      this.pdfController.goToPage(clamped);
    } catch (error) {
      logger.warn(TAG, 'goToPage 失败: ' + String(error));
    }
    this.currentPage = clamped + 1;
    this.pageInputValue = String(this.currentPage);
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(this.currentPage, this.totalPages);
    }
  }

  private applyPageFit(mode: pdfService.PageFit): void {
    try {
      this.pdfController.setPageFit(mode);
      this.pageFitMode = mode;
      logger.info(TAG, 'setPageFit=' + String(mode));
    } catch (error) {
      logger.warn(TAG, 'setPageFit 失败: ' + String(error));
    }
  }

  private applyContinuous(continuous: boolean): void {
    try {
      this.pdfController.setPageContinuous(continuous);
      this.continuousMode = continuous;
      logger.info(TAG, 'setPageContinuous=' + continuous);
    } catch (error) {
      logger.warn(TAG, 'setPageContinuous 失败: ' + String(error));
    }
  }

  private applyZoom(zoom: number): void {
    const clamped: number = Math.max(0.1, Math.min(10, zoom));
    try {
      this.pdfController.setPageZoom(clamped);
      this.zoomLevel = clamped;
      logger.info(TAG, 'setPageZoom=' + clamped);
    } catch (error) {
      logger.warn(TAG, 'setPageZoom 失败: ' + String(error));
    }
  }

  private setSelectionModeInternal(enabled: boolean): void {
    this.selectionMode = enabled;
    if (enabled) {
      try {
        this.pdfController.enableAnnotation(pdfViewManager.SupportedAnnotationType.HIGHLIGHT, 0xFFFFEB3B);
      } catch (error) {
        logger.warn(TAG, 'enableAnnotation 失败: ' + String(error));
      }
    } else {
      try {
        this.pdfController.disableAnnotation();
      } catch (error) {
        logger.warn(TAG, 'disableAnnotation 失败: ' + String(error));
      }
      this.hasSelection = false;
      this.lastSelectedText = '';
      this.lastSelectedRects = [];
    }
    logger.info(TAG, 'selectionMode=' + enabled);
  }

  private setNightOverlayInternal(enabled: boolean): void {
    this.nightOverlayEnabled = enabled;
    this.tintColorValue = enabled ? '#8C000000' : '#00000000';
    logger.info(TAG, 'nightOverlay=' + enabled + ', tint=' + this.tintColorValue);
  }

  /**
   * 应用阅读设置：字号 -> 页面缩放；主题/背景/亮度 -> 页面叠加底色。
   * PDF 页面本身是固定白底，无法真正重排文字/换底，因此用缩放与整体着色近似，
   * 保证「字体」「阅读（主题/背景）」面板在 PDF 下也有可见效果。
   */
  /**
   * PDF Kit 视图级全文检索：searchKey 回调返回匹配总数（官方检索路径），
   * 配合 setSearchIndex(index) 逐条跳转并高亮。
   */
  private searchKeywordInView(keyword: string): Promise<number> {
    return new Promise<number>((resolve: (value: number) => void) => {
      const trimmed: string = keyword.trim();
      if (trimmed.length <= 0) {
        this.searchMatchCount = 0;
        this.searchMatchIndex = 0;
        resolve(0);
        return;
      }
      const restorePage: number = this.currentPage - 1;
      this.searchJumpedByUser = false;
      try {
        this.pdfController.searchKey(trimmed, (matchCount: number) => {
          this.searchMatchCount = matchCount;
          this.searchMatchIndex = 0;
          logger.info(TAG, 'searchKey 命中: keyword=' + trimmed + ', count=' + matchCount);
          // PDF Kit 的 searchKey 会自行跳到首个匹配项；这里把视图恢复到用户原来的页码，
          // 保证"搜索不自动跳转"，只有用户点击「上一处/下一处」后才跳转。
          if (restorePage >= 0) {
            try {
              this.pdfController.goToPage(restorePage);
              this.currentPage = restorePage + 1;
            } catch (restoreError) {
              logger.warn(TAG, 'searchKey 后恢复原页失败: ' + String(restoreError));
            }
          }
          resolve(matchCount);
        });
      } catch (error) {
        logger.warn(TAG, 'searchKey 调用失败: ' + String(error));
        this.searchMatchCount = 0;
        resolve(0);
      }
    });
  }

  private goToNextSearchMatch(): number {
    if (this.searchMatchCount <= 0) {
      return -1;
    }
    let next: number = 0;
    if (this.searchJumpedByUser) {
      const currentIndex: number = this.safeGetSearchIndex();
      next = (currentIndex + 1) % this.searchMatchCount;
    }
    this.searchJumpedByUser = true;
    this.searchMatchIndex = next;
    try {
      this.pdfController.setSearchIndex(next);
    } catch (error) {
      logger.warn(TAG, 'setSearchIndex(next) 失败: ' + String(error));
    }
    return next;
  }

  private safeGetSearchIndex(): number {
    try {
      return this.pdfController.getSearchIndex();
    } catch (error) {
      return this.searchMatchIndex;
    }
  }

  private goToPreviousSearchMatch(): number {
    if (this.searchMatchCount <= 0) {
      return -1;
    }
    let prev: number = this.searchMatchCount - 1;
    if (this.searchJumpedByUser) {
      const currentIndex: number = this.safeGetSearchIndex();
      prev = (currentIndex - 1 + this.searchMatchCount) % this.searchMatchCount;
    }
    this.searchJumpedByUser = true;
    this.searchMatchIndex = prev;
    try {
      this.pdfController.setSearchIndex(prev);
    } catch (error) {
      logger.warn(TAG, 'setSearchIndex(prev) 失败: ' + String(error));
    }
    return prev;
  }

  private clearSearchKeyword(): void {
    try {
      this.pdfController.clearSearch();
    } catch (error) {
      logger.warn(TAG, 'clearSearch 失败: ' + String(error));
    }
    this.searchMatchCount = 0;
    this.searchMatchIndex = 0;
  }

  /**
   * 把标准电子书阅读设置逐项映射到 PDF Kit API（不忽略、不静默降级）：
   * - 字体大小 -> setPageZoom（PDF 为固定版式，PDF Kit 无重排/字体 API，缩放是唯一的等价能力）
   * - 页边距   -> setPageSpacing（水平=左右边距，垂直=上下边距）
   * - 翻页模式 -> setDisplayDirection + setPageContinuous
   * - 阅读主题 -> 页面叠加底色（自动/默认/护眼/羊皮纸/夜间）
   * - 亮度     -> 在主题底色之上叠加压暗
   * 确实无对应 API 的项（行高、字体粗细、字体族、字体颜色），由标准设置面板对固定版式显式标注，不在此静默丢弃。
   */
  private applyPdfReadingSettings(settings: EBookReadingSettings | null, isInit: boolean): void {
    if (settings === null) {
      return;
    }
    // 1) 字体大小 -> 页面缩放
    const baseFontSize: number = 18;
    const zoom: number = Math.max(0.5, Math.min(4, settings.fontSize / baseFontSize));
    this.applyZoom(zoom);

    // 2) 页边距 -> 页面间距
    const horizontalSpacing: number = Math.max(0, Math.min(120, settings.pageMargin));
    const topMargin: number = settings.pageTopMargin ?? 0;
    const bottomMargin: number = settings.pageBottomMargin ?? 0;
    const verticalSpacing: number = Math.max(0, Math.min(120, Math.max(topMargin, bottomMargin)));
    try {
      this.pdfController.setPageSpacing(horizontalSpacing, verticalSpacing);
    } catch (spacingError) {
      logger.warn(TAG, 'setPageSpacing 失败: ' + String(spacingError));
    }

    // 3) 翻页模式 -> 显示方向 + 连续滚动
    const horizontal: boolean = settings.pageMode === EBookPageMode.HORIZONTAL;
    try {
      this.pdfController.setDisplayDirection(
        horizontal ? pdfViewManager.DisplayDirection.HORIZONTAL : pdfViewManager.DisplayDirection.VERTICAL
      );
    } catch (directionError) {
      logger.warn(TAG, 'setDisplayDirection 失败: ' + String(directionError));
    }
    this.applyContinuous(horizontal);

    // 4) 阅读主题 -> 页面叠加底色（十六进制值属主题数据，与 EBookModels.EBOOK_THEME_PRESETS 一致）
    const bg: string = (settings.backgroundColor ?? '#FFFFFF').toUpperCase();
    let alphaValue: number = 0;
    let color: string = 'FFFFFF';
    if (settings.nightMode || bg === '#1E1E1E' || bg === '#1B3B2F') {
      alphaValue = 140;
      color = '000000';
    } else if (bg === '#C7EDCC') {
      alphaValue = 51;
      color = 'C7EDCC';
    } else if (bg === '#F4ECD8') {
      alphaValue = 51;
      color = 'F4ECD8';
    }
    const brightness: number = Math.max(0, Math.min(100, settings.brightness));
    if (brightness < 100) {
      const extraAlpha: number = Math.round((100 - brightness) * 1.2);
      if (extraAlpha > alphaValue) {
        alphaValue = extraAlpha > 200 ? 200 : extraAlpha;
        color = '000000';
      }
    }
    let alphaHex: string = alphaValue.toString(16).toUpperCase();
    if (alphaHex.length < 2) {
      alphaHex = '0' + alphaHex;
    }
    this.tintColorValue = '#' + alphaHex + color;
    this.nightOverlayEnabled = alphaValue > 0 && color === '000000';
    logger.info(TAG, 'applyReadingSettings: fontSize=' + settings.fontSize + '->zoom=' + zoom
      + ', margin=' + horizontalSpacing + '/' + verticalSpacing
      + ', horizontal=' + horizontal
      + ', bg=' + bg + ', brightness=' + brightness
      + ', tint=' + this.tintColorValue + ', init=' + isInit);
  }
  private highlightCurrentSelection(color: number): boolean {
    if (this.lastSelectedRects.length <= 0) {
      return false;
    }
    try {
      this.pdfController.addMarkupAnnotation(pdfViewManager.SupportedAnnotationType.HIGHLIGHT, this.lastSelectedRects, color);
      this.hasSelection = false;
      this.lastSelectedText = '';
      this.lastSelectedRects = [];
      if (this.callbacks.onAnnotationChanged) {
        this.callbacks.onAnnotationChanged();
      }
      return true;
    } catch (error) {
      logger.warn(TAG, 'addMarkupAnnotation 失败: ' + String(error));
      return false;
    }
  }

  private async saveAnnotated(targetPath: string): Promise<boolean> {
    if (targetPath.length <= 0) {
      return false;
    }
    try {
      const result: number = await this.pdfController.saveDocument(targetPath);
      logger.info(TAG, 'saveDocument 完成: path=' + targetPath + ', ret=' + result);
      return true;
    } catch (error) {
      logger.warn(TAG, 'saveDocument 失败: ' + String(error));
      return false;
    }
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'PdfKitViewerComponent aboutToDisappear');
    
    // 清除定时器
    if (this.indicatorTimer !== -1) {
      clearTimeout(this.indicatorTimer);
      this.indicatorTimer = -1;
    }
    
    // 在退出前通知页面变化（保存进度）- 防止重复保存
    if (!this.hasSavedOnExit && this.callbacks.onPageChange && this.totalPages > 0) {
      this.hasSavedOnExit = true;
      logger.info(TAG, `退出前保存进度: 第 ${this.currentPage} 页`);
      this.callbacks.onPageChange(this.currentPage, this.totalPages);
    }
    
    // 释放资源
    try {
      if (this.isDocumentLoaded) {
        this.pdfController.releaseDocument();
        this.isDocumentLoaded = false;
      }
    } catch (e) {
      logger.warn(TAG, `释放 PDF 资源时出错: ${String(e)}`);
    }
  }

  /**
   * 显示页码指示器（自动隐藏）
   */
  private showIndicator(): void {
    this.showPageIndicator = true;
    
    // 清除之前的定时器
    if (this.indicatorTimer !== -1) {
      clearTimeout(this.indicatorTimer);
    }
    
    // 3秒后自动隐藏
    this.indicatorTimer = setTimeout(() => {
      this.showPageIndicator = false;
      this.showPageInput = false;
      this.indicatorTimer = -1;
    }, 3000);
  }

  /**
   * 处理触摸开始
   */
  private handleTouchStart(event: TouchEvent): void {
    if (event.touches.length > 0) {
      const touch = event.touches[0];
      this.touchStartX = touch.x;
      this.touchStartY = touch.y;
      this.touchStartTime = Date.now();
      this.isSwiping = false;
    }
  }

  /**
   * 处理触摸移动
   */
  private handleTouchMove(event: TouchEvent): void {
    if (event.touches.length > 0) {
      const touch = event.touches[0];
      const deltaX = touch.x - this.touchStartX;
      const deltaY = touch.y - this.touchStartY;
      
      // 如果水平移动大于垂直移动，认为是滑动翻页
      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 10) {
        this.isSwiping = true;
      }
    }
  }

  /**
   * 处理触摸结束
   */
  private handleTouchEnd(event: TouchEvent): void {
    if (event.changedTouches.length > 0) {
      const touch = event.changedTouches[0];
      const deltaX = touch.x - this.touchStartX;
      const deltaY = touch.y - this.touchStartY;
      const deltaTime = Date.now() - this.touchStartTime;
      
      // 计算滑动速度
      const velocityX = Math.abs(deltaX) / (deltaTime / 1000);
      
      // 判断是否是有效的滑动翻页
      const isValidSwipe = Math.abs(deltaX) > SWIPE_THRESHOLD || velocityX > SWIPE_VELOCITY_THRESHOLD;
      const isHorizontalSwipe = Math.abs(deltaX) > Math.abs(deltaY);
      
      if (isValidSwipe && isHorizontalSwipe && this.isSwiping) {
        if (deltaX < 0) {
          // 向左滑动 -> 下一页
          this.goToNextPage();
        } else {
          // 向右滑动 -> 上一页
          this.goToPrevPage();
        }
      } else if (!this.isSwiping && deltaTime < 300 && Math.abs(deltaX) < 10 && Math.abs(deltaY) < 10) {
        // 点击事件 - 显示/隐藏页码指示器
        this.handleTap(touch.x);
      }
      
      this.isSwiping = false;
    }
  }

  /**
   * 处理点击事件
   */
  private handleTap(x: number): void {
    // 获取屏幕宽度的三分之一区域
    // 左侧1/3: 上一页, 中间1/3: 显示菜单, 右侧1/3: 下一页
    const leftThird = this.componentWidth / 3;
    const rightThird = this.componentWidth * 2 / 3;
    
    if (x < leftThird) {
      // 点击左侧 -> 上一页
      this.goToPrevPage();
    } else if (x > rightThird) {
      // 点击右侧 -> 下一页
      this.goToNextPage();
    } else {
      // 点击中间 -> 切换宿主工具栏（并同步页码指示器）
      if (this.callbacks.onCenterTap) {
        this.callbacks.onCenterTap();
      }
      if (this.showPageIndicator) {
        this.showPageIndicator = false;
        this.showPageInput = false;
        if (this.indicatorTimer !== -1) {
          clearTimeout(this.indicatorTimer);
          this.indicatorTimer = -1;
        }
      } else {
        this.showIndicator();
      }
    }
  }

  /**
   * 上一页
   */
  private goToPrevPage(): boolean {
    if (this.currentPage > 1) {
      this.setCurrentPage(this.currentPage - 1);
      return true;
    }
    return false;
  }

  /**
   * 下一页
   */
  private goToNextPage(): boolean {
    if (this.currentPage < this.totalPages) {
      this.setCurrentPage(this.currentPage + 1);
      return true;
    }
    return false;
  }

  /**
   * 加载 PDF 文档
   */
  private loadPdfDocument(): void {
    if (!this.ebook || !this.ebook.filePath) {
      this.errorMessage = '无效的 PDF 文件路径';
      this.isLoading = false;
      return;
    }

    logger.info(TAG, `开始加载 PDF: ${this.ebook.filePath}`);
    this.isLoading = true;
    this.errorMessage = '';

    this.pdfController.loadDocument(this.ebook.filePath)
      .then((loadResult: pdfService.ParseResult) => {
        logger.info(TAG, `PDF 加载成功: ${JSON.stringify(loadResult)}`);
        this.isDocumentLoaded = true;
        this.isLoading = false;
        
        // 恢复阅读进度 - 延迟执行以确保文档完全加载
        setTimeout(() => {
          if (this.ebook && this.ebook.readingProgress && this.ebook.readingProgress.currentChapterIndex > 0) {
            const targetPage = this.ebook.readingProgress.currentChapterIndex + 1; // 转为 1-indexed
            logger.info(TAG, `恢复阅读进度到第 ${targetPage} 页`);
            const validPage = Math.min(targetPage, this.totalPages);
            if (validPage > 1) {
              this.setCurrentPage(validPage);
            }
          }
        }, 300); // 延迟 300ms 确保文档完全加载
      })
      .catch((err: BusinessError) => {
        logger.error(TAG, `PDF 加载失败: ${JSON.stringify(err)}`);
        this.errorMessage = `加载失败: ${err.message || '未知错误'}`;
        this.isLoading = false;
        if (this.callbacks.onLoadError) {
          this.callbacks.onLoadError(this.errorMessage);
        }
      });
  }

  /**
   * 设置当前页码并跳转
   */
  private setCurrentPage(page: number): void {
    if (page < 1) page = 1;
    if (page > this.totalPages) page = this.totalPages;
    
    const pageIndex = page - 1; // 转为 0-indexed
    
    // 使用 goToPage 跳转到指定页面
    if (this.isDocumentLoaded && pageIndex >= 0) {
      try {
        this.pdfController.goToPage(pageIndex);
        logger.info(TAG, `goToPage(${pageIndex}) 调用成功`);
      } catch (e) {
        logger.warn(TAG, `goToPage 失败: ${String(e)}`);
      }
    }
    
    this.currentPage = page;
    this.pageInputValue = String(page);
    logger.info(TAG, `设置当前页码: ${page}`);
    
    // 通知页面变化
    if (this.callbacks.onPageChange) {
      this.callbacks.onPageChange(this.currentPage, this.totalPages);
    }
  }

  /**
   * 获取当前页码（0-indexed）
   */
  public getCurrentPageIndex(): number {
    return this.currentPage - 1;
  }

  /**
   * 获取总页数
   */
  public getTotalPages(): number {
    return this.totalPages;
  }

  /**
   * 获取当前阅读进度（百分比）
   */
  public getProgress(): number {
    if (this.totalPages <= 0) {
      return 0;
    }
    return (this.currentPage / this.totalPages) * 100;
  }

  build() {
    Stack() {
      // PDF 预览 - 使用单页非连续模式
      // 使用 FIT_PAGE 让 PDF 内容保持比例完整显示，上下空白区域会显示背景色
      if (!this.errorMessage) {
        PdfView({
          controller: this.pdfController,
          pageFit: this.pageFitMode as pdfService.PageFit,
          isContinuous: this.continuousMode,
          showScroll: false,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE
        })
          .width('100%')
          .height('100%')
      }

      // 手势检测层 - 覆盖在 PdfView 上方，用于检测滑动和点击
      // [Phase4] 文本选择模式下必须让 PdfView 接管触摸，否则无法选中文本
      if (!this.isLoading && !this.errorMessage && !this.selectionMode) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onTouch((event: TouchEvent) => {
            switch (event.type) {
              case TouchType.Down:
                this.handleTouchStart(event);
                break;
              case TouchType.Move:
                this.handleTouchMove(event);
                break;
              case TouchType.Up:
              case TouchType.Cancel:
                this.handleTouchEnd(event);
                break;
            }
          })
      }

      // [Phase4] 页面叠加底色（夜间压暗 / 护眼 / 羊皮纸 / 亮度调节）
      // 注意：PDF 页面为固定白底，这里只做整体着色，不改变排版内容
      if (this.tintColorValue !== '#00000000' && !this.isLoading && this.errorMessage.length === 0) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.tintColorValue)
          .hitTestBehavior(HitTestMode.None)
      }

      // 加载指示器
      if (this.isLoading) {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color($r('app.color.accent_primary'))
          
          Text('正在加载 PDF...')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.background_secondary'))
      }

      // 错误提示
      if (this.errorMessage.length > 0) {
        Column({ space: 16 }) {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(80)
            .height(80)
            .fillColor($r('app.color.color_error'))
          
          Text('PDF 加载失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.color_error'))
          
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(3)
            .textAlign(TextAlign.Center)
            .width('80%')
          
          Button('重试')
            .fontSize(14)
            .height(40)
            .width(120)
            .onClick(() => {
              this.loadPdfDocument();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.background_primary'))
        .padding(20)
      }

      // 页码指示器（点击中间区域显示，自动隐藏）
      if (!this.isLoading && !this.errorMessage && this.totalPages > 0 && this.showPageIndicator) {
        Column() {
          // 页码显示（可点击编辑）
          Row({ space: 4 }) {
            if (this.showPageInput) {
              TextInput({ text: this.pageInputValue })
                .width(60)
                .height(36)
                .fontSize(16)
                .fontColor($r('app.color.text_white'))
                .backgroundColor($r('app.color.background_overlay'))
                .borderRadius(4)
                .type(InputType.Number)
                .onChange((value: string) => {
                  this.pageInputValue = value;
                })
                .onSubmit(() => {
                  const page = parseInt(this.pageInputValue);
                  if (!isNaN(page)) {
                    this.setCurrentPage(page);
                  }
                  this.showPageInput = false;
                })
            } else {
              Text(`${this.currentPage}`)
                .fontSize(18)
                .fontColor($r('app.color.text_white'))
                .fontWeight(FontWeight.Medium)
                .onClick(() => {
                  this.showPageInput = true;
                  this.pageInputValue = String(this.currentPage);
                  // 重置自动隐藏定时器
                  this.showIndicator();
                })
            }
            Text('/')
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text(`${this.totalPages}`)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.background_overlay'))
          .borderRadius(20)
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: -80 })
        .alignItems(HorizontalAlign.Center)
      }

      // [Phase4] 划重点模式工具条
      if (this.selectionMode && !this.isLoading && this.errorMessage.length === 0) {
        Column() {
          Row({ space: 12 }) {
            Button('高亮')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.color_warning'))
              .fontColor($r('app.color.text_black'))
              .onClick(() => {
                this.highlightCurrentSelection(ANNOTATION_HIGHLIGHT_COLOR);
              })
            Button('下划线')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.accent_primary'))
              .fontColor($r('app.color.text_white'))
              .onClick(() => {
                this.highlightCurrentSelection(ANNOTATION_UNDERLINE_COLOR);
              })
            Button('完成')
              .fontSize(13)
              .height(34)
              .backgroundColor($r('app.color.background_overlay'))
              .fontColor($r('app.color.text_white'))
              .onClick(() => {
                this.setSelectionModeInternal(false);
              })
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.background_overlay'))
          .borderRadius(20)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: 28 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBgColor.length > 0 ? this.themeBgColor : $r('app.color.background_primary'))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.componentWidth = newValue.width as number;
    })
  }
}
