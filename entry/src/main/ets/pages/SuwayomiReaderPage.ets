/**
 * Suwayomi 阅读器页面
 * 阅读 Suwayomi 服务器上的漫画章节
 * 与漫画阅读器功能对齐
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareState } from '../Framework/Components/FontAware';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor } from '../Framework/Source/SuwayomiSourceExecutor';
import { PageInfo, ChapterInfo, ComicDetailInfo } from '../Framework/Source/SourceExecutor';
import { display, curves, UIContext } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { AvifDecoder, isAvifFormat } from '../Framework/Image/AvifDecoder';
import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';

const TAG = 'SuwayomiReaderPage';

// 阅读模式
enum SuwayomiReadingMode {
  VERTICAL_SCROLL = 0,  // 垂直滚动（条漫模式）
  HORIZONTAL_PAGE = 1,  // 水平翻页
  SINGLE_PAGE = 2       // 单页模式
}

// 页面参数接口
interface SuwayomiReaderParams {
  mangaId?: string;
  chapterId?: string;
  chapterTitle?: string;
  chapterIndex?: number;
  totalChapters?: number;
}

@Component
export struct SuwayomiReaderPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  // 章节数据
  @State mangaId: string = '';
  @State chapterId: string = '';
  @State chapterTitle: string = '';
  @State chapterIndex: number = 0;
  @State totalChapters: number = 0;
  @State pages: PageInfo[] = [];
  @State currentPage: number = 0;

  // 章节列表（用于章节切换）
  @State chapterList: ChapterInfo[] = [];
  @State isLoadingChapters: boolean = false;

  // 显示控制
  @State showControls: boolean = false;
  @State isFullScreen: boolean = true;
  @State controlsOpacity: number = 0;

  // 阅读设置
  @State readingMode: SuwayomiReadingMode = SuwayomiReadingMode.VERTICAL_SCROLL;
  @State screenBrightness: number = 1.0;
  @State showSettingsPanel: boolean = false;

  // 图片请求头（用于认证）
  @State imageHeaders: Record<string, string> = {};

  // 图片加载状态
  @State loadedPages: Set<number> = new Set();
  @State failedPages: Set<number> = new Set();
  
  // AVIF 图片解码缓存 (pageIndex -> PixelMap)
  private avifPixelMaps: Map<number, image.PixelMap> = new Map();
  @State avifLoadingPages: Set<number> = new Set();

  // 屏幕尺寸
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;

  private executor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private scrollerController: Scroller = new Scroller();
  private swiperController: SwiperController = new SwiperController();

  aboutToDisappear(): void {
    // 保存阅读进度并标记章节为已读
    if (this.chapterId) {
      this.saveReadingProgress();
      this.markAsRead();
    }
    // 恢复默认显示模式
    this.restoreDefaultMode();
    // 释放 AVIF PixelMap 资源
    this.releaseAvifPixelMaps();
  }

  /**
   * 释放所有 AVIF PixelMap 资源
   */
  private releaseAvifPixelMaps(): void {
    this.avifPixelMaps.forEach((pixelMap: image.PixelMap) => {
      try {
        pixelMap.release();
      } catch (e) {
        logger.warn(TAG, `释放 PixelMap 失败: ${e}`);
      }
    });
    this.avifPixelMaps.clear();
  }

  /**
   * 下载并解码图片（支持 AVIF）
   */
  private async loadAndDecodeImage(url: string, pageIndex: number): Promise<void> {
    // 已经在加载或已加载完成，跳过
    if (this.avifLoadingPages.has(pageIndex) || this.avifPixelMaps.has(pageIndex)) {
      return;
    }

    // 标记为加载中
    this.avifLoadingPages.add(pageIndex);
    this.avifLoadingPages = new Set(this.avifLoadingPages);

    try {
      // 下载图片数据
      const buffer = await this.downloadImageWithAuth(url);
      if (!buffer) {
        throw new Error('下载图片失败');
      }

      let pixelMap: image.PixelMap | null = null;

      // 检测是否为 AVIF 格式
      if (isAvifFormat(buffer)) {
        logger.info(TAG, `页面 ${pageIndex + 1} 检测到 AVIF 格式，使用 AVIF 解码器`);
        const avifDecoder = AvifDecoder.getInstance();
        if (avifDecoder.isSupported()) {
          pixelMap = await avifDecoder.decode(buffer);
          if (pixelMap) {
            logger.info(TAG, `页面 ${pageIndex + 1} AVIF 解码成功`);
          } else {
            logger.warn(TAG, `页面 ${pageIndex + 1} AVIF 解码返回 null，尝试系统解码器`);
          }
        } else {
          logger.warn(TAG, `AVIF 解码器不可用，尝试系统解码器`);
        }
      }

      // 如果 AVIF 解码失败或不是 AVIF 格式，使用系统解码器
      if (!pixelMap) {
        const imageSource = image.createImageSource(buffer);
        pixelMap = await imageSource.createPixelMap();
        imageSource.release();
      }

      if (pixelMap) {
        this.avifPixelMaps.set(pageIndex, pixelMap);
        this.loadedPages.add(pageIndex);
        this.loadedPages = new Set(this.loadedPages);
      } else {
        throw new Error('解码图片失败');
      }
    } catch (error) {
      logger.error(TAG, `页面 ${pageIndex + 1} 加载失败: ${error}`);
      this.failedPages.add(pageIndex);
      this.failedPages = new Set(this.failedPages);
    } finally {
      this.avifLoadingPages.delete(pageIndex);
      this.avifLoadingPages = new Set(this.avifLoadingPages);
    }
  }

  /**
   * 下载图片（带认证头）
   */
  private async downloadImageWithAuth(url: string): Promise<ArrayBuffer | null> {
    try {
      const httpRequest = http.createHttp();
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
      };

      // 添加认证头
      if (this.imageHeaders['Authorization']) {
        headers['Authorization'] = this.imageHeaders['Authorization'];
      }

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000,
        header: headers
      });

      httpRequest.destroy();

      if (response.responseCode === 200 && response.result) {
        return response.result as ArrayBuffer;
      }

      logger.warn(TAG, `下载图片失败: HTTP ${response.responseCode}`);
      return null;
    } catch (e) {
      logger.error(TAG, `下载图片异常: ${e}`);
      return null;
    }
  }

  /**
   * 获取页面的 PixelMap（如果已解码）
   */
  private getPagePixelMap(pageIndex: number): image.PixelMap | undefined {
    return this.avifPixelMaps.get(pageIndex);
  }

  /**
   * 重试加载失败的页面
   */
  private retryLoadPage(pageIndex: number, url: string): void {
    this.failedPages.delete(pageIndex);
    this.failedPages = new Set(this.failedPages);
    this.loadAndDecodeImage(url, pageIndex);
  }

  private async loadChapterPages(): Promise<void> {
    if (!this.chapterId) {
      this.errorMessage = '章节 ID 无效';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      // 获取图片请求头（用于认证）
      this.imageHeaders = this.executor.getImageHeaders();
      this.pages = await this.executor.getPages(this.chapterId);
      logger.info(TAG, `加载章节页面: ${this.pages.length} 页`);
      
      // 恢复上次阅读进度
      await this.restoreReadingProgress();
    } catch (error) {
      logger.error(TAG, `加载页面失败: ${error}`);
      this.errorMessage = `加载失败: ${error}`;
    }

    this.isLoading = false;
  }

  private async markAsRead(): Promise<void> {
    try {
      await this.executor.markRead(this.chapterId, true);
      logger.debug(TAG, `标记章节已读: ${this.chapterId}`);
    } catch (error) {
      logger.error(TAG, `标记已读失败: ${error}`);
    }
  }

  /**
   * 保存阅读进度到服务器
   */
  private async saveReadingProgress(): Promise<void> {
    try {
      await this.executor.updateReadingProgress(this.chapterId, this.currentPage);
      logger.debug(TAG, `保存阅读进度: 章节=${this.chapterId}, 页码=${this.currentPage}`);
    } catch (error) {
      logger.error(TAG, `保存阅读进度失败: ${error}`);
    }
  }

  /**
   * 恢复上次阅读进度
   */
  private async restoreReadingProgress(): Promise<void> {
    try {
      const lastPage = await this.executor.getChapterProgress(this.chapterId);
      if (lastPage > 0 && lastPage < this.pages.length) {
        this.currentPage = lastPage;
        // 延迟跳转，确保UI已渲染
        setTimeout(() => {
          this.goToPage(lastPage);
        }, 100);
        logger.info(TAG, `恢复阅读进度: 页码=${lastPage}`);
      }
    } catch (error) {
      logger.error(TAG, `恢复阅读进度失败: ${error}`);
    }
  }

  /**
   * 加载漫画章节列表（用于章节切换）
   */
  private async loadChapterList(): Promise<void> {
    if (!this.mangaId || this.isLoadingChapters) {
      return;
    }

    this.isLoadingChapters = true;
    try {
      const detail = await this.executor.getDetail(this.mangaId);
      if (detail?.chapters) {
        this.chapterList = detail.chapters;
        this.totalChapters = detail.chapters.length;
        // 更新当前章节索引
        const currentIndex = this.chapterList.findIndex(
          (ch: ChapterInfo) => ch.id === this.chapterId
        );
        if (currentIndex >= 0) {
          this.chapterIndex = currentIndex;
        }
        logger.info(TAG, `加载章节列表成功: ${this.chapterList.length} 章, 当前索引=${this.chapterIndex}`);
      }
    } catch (error) {
      logger.error(TAG, `加载章节列表失败: ${error}`);
    }
    this.isLoadingChapters = false;
  }

  /**
   * 切换到上一章
   */
  private async goToPreviousChapter(): Promise<void> {
    if (this.chapterList.length === 0) {
      await this.loadChapterList();
    }

    // 注意：章节列表通常按倒序排列（新章在前），所以"上一章"实际是数组中的下一个
    const prevIndex = this.chapterIndex + 1;
    if (prevIndex < this.chapterList.length) {
      await this.switchToChapter(prevIndex);
    } else {
      this.showToast('已是第一章');
    }
  }

  /**
   * 切换到下一章
   */
  private async goToNextChapter(): Promise<void> {
    if (this.chapterList.length === 0) {
      await this.loadChapterList();
    }

    // 注意：章节列表通常按倒序排列（新章在前），所以"下一章"实际是数组中的上一个
    const nextIndex = this.chapterIndex - 1;
    if (nextIndex >= 0) {
      await this.switchToChapter(nextIndex);
    } else {
      this.showToast('已是最新章节');
    }
  }

  /**
   * 切换到指定章节
   */
  private async switchToChapter(index: number): Promise<void> {
    if (index < 0 || index >= this.chapterList.length) {
      return;
    }

    // 保存当前章节进度并标记已读
    await this.saveReadingProgress();
    await this.markAsRead();

    // 释放当前章节的 AVIF PixelMap 资源
    this.releaseAvifPixelMaps();

    // 切换到新章节
    const chapter = this.chapterList[index];
    this.chapterIndex = index;
    this.chapterId = chapter.id;
    this.chapterTitle = chapter.title;
    this.currentPage = 0;
    this.pages = [];
    this.loadedPages = new Set();
    this.failedPages = new Set();
    this.avifLoadingPages = new Set();

    logger.info(TAG, `切换到章节: ${chapter.title} (index=${index})`);
    await this.loadChapterPages();
  }

  aboutToAppear(): void {
    // 获取屏幕尺寸
    try {
      const displayInfo = display.getDefaultDisplaySync();
      this.screenWidth = px2vp(displayInfo.width);
      this.screenHeight = px2vp(displayInfo.height);
    } catch (e) {
      this.screenWidth = 360;
      this.screenHeight = 780;
    }
  }

  /**
   * 设置沉浸式全屏模式
   */
  private setupFullscreenMode(): void {
    try {
      const uiContext = this.getUIContext();
      if (uiContext) {
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext);
        logger.info(TAG, '✅ 设置沉浸式阅读模式');
      }
    } catch (error) {
      logger.error(TAG, `设置全屏模式失败: ${error}`);
    }
  }

  /**
   * 恢复默认显示模式
   */
  private restoreDefaultMode(): void {
    try {
      const uiContext = this.getUIContext();
      if (uiContext) {
        WindowManager.setDisplayMode(DisplayMode.DEFAULT, uiContext);
        logger.info(TAG, '✅ 恢复默认显示模式');
      }
    } catch (error) {
      logger.error(TAG, `恢复显示模式失败: ${error}`);
    }
  }

  private toggleControls(): void {
    if (this.showControls) {
      // 隐藏控制栏
      animateTo({
        duration: 200,
        curve: Curve.EaseOut
      }, () => {
        this.controlsOpacity = 0;
      });
      setTimeout(() => {
        this.showControls = false;
      }, 200);
    } else {
      // 显示控制栏
      this.showControls = true;
      animateTo({
        duration: 200,
        curve: Curve.EaseOut
      }, () => {
        this.controlsOpacity = 1;
      });
    }
  }

  private goBack(): void {
    this.pathStack.pop();
  }

  private goToPage(index: number): void {
    if (index >= 0 && index < this.pages.length) {
      this.currentPage = index;
      if (this.readingMode === SuwayomiReadingMode.VERTICAL_SCROLL) {
        this.scrollerController.scrollToIndex(index);
      } else {
        this.swiperController.changeIndex(index);
      }
    }
  }

  private nextPage(): void {
    if (this.currentPage < this.pages.length - 1) {
      this.goToPage(this.currentPage + 1);
    }
  }

  private prevPage(): void {
    if (this.currentPage > 0) {
      this.goToPage(this.currentPage - 1);
    }
  }

  private cycleReadingMode(): void {
    this.readingMode = (this.readingMode + 1) % 3;
    this.showToast(this.getReadingModeName());
  }

  private getReadingModeName(): string {
    switch (this.readingMode) {
      case SuwayomiReadingMode.VERTICAL_SCROLL:
        return '垂直滚动';
      case SuwayomiReadingMode.HORIZONTAL_PAGE:
        return '水平翻页';
      case SuwayomiReadingMode.SINGLE_PAGE:
        return '单页模式';
      default:
        return '未知';
    }
  }

  private showToast(message: string): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
        message: message,
        duration: 1500
      });
    });
  }

  @Builder
  buildTopBar() {
    Row() {
      // 返回按钮
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.goBack())
      .fontFamily(this.appFontFamily)

      Column({ space: 2 }) {
        Text(this.chapterTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)

        Text(`${this.currentPage + 1} / ${this.pages.length}`)
          .fontSize(12)
          .fontColor(Color.White)
          .opacity(0.8)
          .fontFamily(this.appFontFamily)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 阅读模式切换
      Button() {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.cycleReadingMode())
      .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor('#CC000000')
    .opacity(this.controlsOpacity)
  }

  @Builder
  buildBottomBar() {
    Column({ space: 12 }) {
      // 页面滑块
      Row({ space: 12 }) {
        Text(`${this.currentPage + 1}`)
          .fontSize(14)
          .fontColor(Color.White)
          .width(40)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)

        Slider({
          value: this.currentPage,
          min: 0,
          max: Math.max(0, this.pages.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .selectedColor('#007AFF')
          .trackColor('rgba(255,255,255,0.3)')
          .onChange((value: number) => {
            const newPage = Math.round(value);
            if (newPage !== this.currentPage) {
              this.goToPage(newPage);
            }
          })

        Text(`${this.pages.length}`)
          .fontSize(14)
          .fontColor(Color.White)
          .width(40)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 章节导航按钮
      Row({ space: 16 }) {
        Button('上一章')
          .fontSize(14)
          .fontColor(this.chapterIndex < this.totalChapters - 1 ? Color.White : 'rgba(255,255,255,0.5)')
          .backgroundColor(this.chapterIndex < this.totalChapters - 1 ? '#007AFF' : 'rgba(255,255,255,0.2)')
          .height(36)
          .layoutWeight(1)
          .enabled(this.chapterIndex < this.totalChapters - 1)
          .onClick(() => {
            this.goToPreviousChapter();
          })
          .fontFamily(this.appFontFamily)

        Button('下一章')
          .fontSize(14)
          .fontColor(this.chapterIndex > 0 ? Color.White : 'rgba(255,255,255,0.5)')
          .backgroundColor(this.chapterIndex > 0 ? '#007AFF' : 'rgba(255,255,255,0.2)')
          .height(36)
          .layoutWeight(1)
          .enabled(this.chapterIndex > 0)
          .onClick(() => {
            this.goToNextChapter();
          })
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .padding({ top: 12, bottom: 24 })
    .backgroundColor('#CC000000')
    .opacity(this.controlsOpacity)
  }

  @Builder
  buildPageImage(page: PageInfo, index: number) {
    Stack() {
      // 加载中占位
      if (!this.loadedPages.has(index) && !this.failedPages.has(index)) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(Color.White)
          Text(`加载第 ${index + 1} 页...`)
            .fontSize(12)
            .fontColor('rgba(255,255,255,0.6)')
            .margin({ top: 8 })
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .height(this.screenHeight * 0.8)
        .justifyContent(FlexAlign.Center)
      }

      // 加载失败占位
      if (this.failedPages.has(index)) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(32)
            .fontColor(['#FF6B6B'])
          Text(`第 ${index + 1} 页加载失败`)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .fontFamily(this.appFontFamily)
          Button('重试')
            .fontSize(12)
            .height(28)
            .backgroundColor('#007AFF')
            .onClick(() => {
              this.retryLoadPage(index, page.url);
            })
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .height(this.screenHeight * 0.5)
        .justifyContent(FlexAlign.Center)
      }

      // 图片显示：优先使用解码后的 PixelMap，否则使用原始 URL
      if (this.avifPixelMaps.has(index)) {
        // 使用解码后的 PixelMap（支持 AVIF）
        Image(this.avifPixelMaps.get(index))
          .width('100%')
          .objectFit(ImageFit.Contain)
      } else if (!this.failedPages.has(index) && !this.avifLoadingPages.has(index)) {
        // 尚未加载，显示透明占位并触发加载
        Column()
          .width('100%')
          .height(1)
          .onAppear(() => {
            // 触发图片加载
            this.loadAndDecodeImage(page.url, index);
          })
      }
    }
    .width('100%')
  }

  @Builder
  buildVerticalScrollContent() {
    List({ scroller: this.scrollerController }) {
      ForEach(this.pages, (page: PageInfo, index: number) => {
        ListItem() {
          this.buildPageImage(page, index)
        }
      }, (page: PageInfo, index: number) => `page_${index}_${page.url}`)
    }
    .width('100%')
    .height('100%')
    .listDirection(Axis.Vertical)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScrollIndex((start: number) => {
      this.currentPage = start;
    })
    .onClick(() => this.toggleControls())
  }

  @Builder
  buildHorizontalPageContent() {
    Swiper(this.swiperController) {
      ForEach(this.pages, (page: PageInfo, index: number) => {
        Column() {
          this.buildPageImage(page, index)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }, (page: PageInfo, index: number) => `page_${index}_${page.url}`)
    }
    .width('100%')
    .height('100%')
    .index(this.currentPage)
    .indicator(false)
    .loop(false)
    .onChange((index: number) => {
      this.currentPage = index;
    })
    .onClick(() => this.toggleControls())
  }

  @Builder
  buildSinglePageContent() {
    Column() {
      if (this.pages.length > 0 && this.currentPage < this.pages.length) {
        this.buildPageImage(this.pages[this.currentPage], this.currentPage)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .gesture(
      SwipeGesture({ direction: SwipeDirection.Horizontal })
        .onAction((event: GestureEvent) => {
          if (event.angle > 0) {
            this.prevPage();
          } else {
            this.nextPage();
          }
        })
    )
    .onClick(() => this.toggleControls())
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
            Text('加载中...')
              .fontSize(14)
              .fontColor(Color.White)
              .margin({ top: 16 })
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMessage) {
          Column({ space: 16 }) {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor('#FF6B6B')
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)

            Button('重试')
              .backgroundColor('#007AFF')
              .fontColor(Color.White)
              .onClick(() => this.loadChapterPages())
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(16)
        } else if (this.pages.length === 0) {
          Column() {
            Text('暂无页面')
              .fontSize(14)
              .fontColor(Color.White)
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          // 根据阅读模式显示不同内容
          if (this.readingMode === SuwayomiReadingMode.VERTICAL_SCROLL) {
            this.buildVerticalScrollContent()
          } else if (this.readingMode === SuwayomiReadingMode.HORIZONTAL_PAGE) {
            this.buildHorizontalPageContent()
          } else {
            this.buildSinglePageContent()
          }
        }

        // 顶部控制栏
        if (this.showControls) {
          Column() {
            this.buildTopBar()
          }
          .width('100%')
          .position({ top: 0 })
        }

        // 底部控制栏
        if (this.showControls) {
          Column() {
            this.buildBottomBar()
          }
          .width('100%')
          .position({ bottom: 0 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 设置沉浸式全屏模式
      this.setupFullscreenMode();
      
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: SuwayomiReaderParams = param as SuwayomiReaderParams;
        if (params.mangaId) {
          this.mangaId = params.mangaId;
        }
        if (params.chapterId) {
          this.chapterId = params.chapterId;
        }
        if (params.chapterTitle) {
          this.chapterTitle = params.chapterTitle;
        }
        if (params.chapterIndex !== undefined) {
          this.chapterIndex = params.chapterIndex;
        }
        if (params.totalChapters !== undefined) {
          this.totalChapters = params.totalChapters;
        }
        this.loadChapterPages();
        // 加载章节列表用于章节切换
        this.loadChapterList();
      }
    })
  }
}
