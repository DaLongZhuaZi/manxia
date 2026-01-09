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
import { logger } from '../../Utils/Logger';
import { EBook, EBookReadingProgress, EBookReadingSettings } from '../../Models/EBookModels';

const TAG = 'PdfKitViewerComponent';

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
  @Prop themeBgColor: string = '#FFFFFF';
  // 回调
  callbacks: PdfViewerCallbacks = {};
  
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

  aboutToAppear(): void {
    logger.info(TAG, 'PdfKitViewerComponent aboutToAppear');
    
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
      // 点击中间 -> 显示/隐藏页码指示器
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
  private goToPrevPage(): void {
    if (this.currentPage > 1) {
      this.setCurrentPage(this.currentPage - 1);
      this.showIndicator();
    }
  }

  /**
   * 下一页
   */
  private goToNextPage(): void {
    if (this.currentPage < this.totalPages) {
      this.setCurrentPage(this.currentPage + 1);
      this.showIndicator();
    }
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
          pageFit: pdfService.PageFit.FIT_PAGE, // 适应页面，保持比例完整显示
          isContinuous: false, // 非连续模式，每次只显示一页
          showScroll: false,
          pageLayout: pdfService.PageLayout.LAYOUT_SINGLE
        })
          .width('100%')
          .height('100%')
      }

      // 手势检测层 - 覆盖在 PdfView 上方，用于检测滑动和点击
      if (!this.isLoading && !this.errorMessage) {
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

      // 加载指示器
      if (this.isLoading) {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color('#007AFF')
          
          Text('正在加载 PDF...')
            .fontSize(14)
            .fontColor('#666666')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F5F5F5')
      }

      // 错误提示
      if (this.errorMessage.length > 0) {
        Column({ space: 16 }) {
          Image($r('sys.symbol.exclamationmark_circle_fill'))
            .width(80)
            .height(80)
            .fillColor('#FF3B30')
          
          Text('PDF 加载失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF3B30')
          
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#666666')
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
        .backgroundColor('#FFFFFF')
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
                .fontColor('#FFFFFF')
                .backgroundColor('#60000000')
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
                .fontColor('#FFFFFF')
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
              .fontColor('#CCCCCC')
            Text(`${this.totalPages}`)
              .fontSize(16)
              .fontColor('#CCCCCC')
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#CC000000')
          .borderRadius(20)
        }
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: -80 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBgColor)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.componentWidth = newValue.width as number;
    })
  }
}
