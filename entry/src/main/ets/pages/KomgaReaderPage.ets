import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ChapterInfo, ComicDetailInfo, PageInfo } from '../Framework/Source/SourceExecutor';
import { getKomgaSourceExecutor, KomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';
import { KomgaContentType, KomgaReaderProgress } from '../Framework/Source/KomgaModels';
import { KomgaImage } from '../components/KomgaImage';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';

const TAG = 'KomgaReaderPage';
const READING_PROGRESS_STORE: string = 'komga_reading_progress';

interface KomgaReaderParams {
  itemId: string;
  contentType: KomgaContentType;
  bookId: string;
  chapterIndex: number;
  mangaTitle: string;
}

@Component
export struct KomgaReaderPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State itemId: string = '';
  @State contentType: KomgaContentType = 'SERIES';
  @State mangaTitle: string = '';
  @State chapterId: string = '';
  @State chapterIndex: number = 0;
  @State chapterTitle: string = '';
  @State pages: PageInfo[] = [];
  @State currentPage: number = 0;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State showControls: boolean = true;
  @State controlsOpacity: number = 1;
  @State topBarTranslateY: number = 0;
  @State bottomBarTranslateY: number = 0;
  @State controlsBackdropOpacity: number = 1;

  private swiperController: SwiperController = new SwiperController();
  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private chapterList: ChapterInfo[] = [];
  private componentId: string = 'KomgaReaderPage';
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private controlsVisibilityTimer: number = -1;
  private isFullscreenApplied: boolean = false;

  private getHostContext(): common.UIAbilityContext {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('Komga 阅读器无法获取 UIAbilityContext');
    }
    return context;
  }

  aboutToAppear(): void {
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    this.isFullscreenApplied = false;
  }

  aboutToDisappear(): void {
    void this.saveReadingProgress();
    if (this.controlsVisibilityTimer >= 0) {
      clearTimeout(this.controlsVisibilityTimer);
      this.controlsVisibilityTimer = -1;
    }
    this.exitFullScreen('aboutToDisappear');
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  onPageHide(): void {
    void this.saveReadingProgress();
  }

  onPageShow(): void {
    this.enterFullScreen('onPageShow');
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 1600 });
  }

  private enterFullScreen(reason: string): void {
    try {
      const uiContext = this.getUIContext();
      if (!uiContext) {
        logger.warn(TAG, `进入 Komga 阅读沉浸模式失败: UIContext 为空, reason=${reason}`);
        return;
      }
      const currentMode = WindowManager.getCurrentMode();
      if (!this.isFullscreenApplied && currentMode !== DisplayMode.FULL_IMMERSIVE) {
        this.previousDisplayMode = currentMode;
      }
      if (currentMode !== DisplayMode.FULL_IMMERSIVE) {
        WindowManager.setDisplayModeWithTransition(DisplayMode.FULL_IMMERSIVE, uiContext);
      } else {
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext);
      }
      WindowManager.reapplyCurrentDisplayMode(24);
      this.isFullscreenApplied = true;
      logger.info(TAG, `Komga 阅读器已进入全沉浸模式, reason=${reason}, previousMode=${this.previousDisplayMode}`);
    } catch (error) {
      logger.warn(TAG, `进入 Komga 阅读沉浸模式失败: reason=${reason}, error=${String(error)}`);
    }
  }

  private exitFullScreen(reason: string): void {
    try {
      const uiContext = this.getUIContext();
      if (!uiContext) {
        logger.warn(TAG, `退出 Komga 阅读沉浸模式失败: UIContext 为空, reason=${reason}`);
        return;
      }
      const targetMode = this.previousDisplayMode === DisplayMode.FULL_IMMERSIVE
        ? DisplayMode.DEFAULT
        : this.previousDisplayMode;
      if (WindowManager.getCurrentMode() !== targetMode) {
        WindowManager.setDisplayMode(targetMode, uiContext);
        WindowManager.reapplyCurrentDisplayMode(180);
      }
      this.isFullscreenApplied = false;
      logger.info(TAG, `Komga 阅读器已退出全沉浸模式, reason=${reason}, targetMode=${targetMode}`);
    } catch (error) {
      logger.warn(TAG, `退出 Komga 阅读沉浸模式失败: reason=${reason}, error=${String(error)}`);
    }
  }

  private setControlsVisible(visible: boolean): void {
    if (this.controlsVisibilityTimer >= 0) {
      clearTimeout(this.controlsVisibilityTimer);
      this.controlsVisibilityTimer = -1;
    }
    if (visible) {
      this.showControls = true;
      animateTo({
        duration: 260,
        curve: Curve.EaseOut
      }, () => {
        this.controlsOpacity = 1;
        this.topBarTranslateY = 0;
        this.bottomBarTranslateY = 0;
        this.controlsBackdropOpacity = 1;
      });
      return;
    }

    animateTo({
      duration: 220,
      curve: Curve.EaseInOut
    }, () => {
      this.controlsOpacity = 0;
      this.topBarTranslateY = -24;
      this.bottomBarTranslateY = 28;
      this.controlsBackdropOpacity = 0;
    });
    this.controlsVisibilityTimer = setTimeout(() => {
      this.showControls = false;
      this.controlsVisibilityTimer = -1;
    }, 220);
  }

  private getProgressKey(): string {
    return `${this.contentType}_${this.itemId}`;
  }

  private copyChapters(source?: ChapterInfo[]): ChapterInfo[] {
    if (source === null || source === undefined || source.length <= 0) {
      return [];
    }
    return source.concat();
  }

  private sortChapters(detail: ComicDetailInfo | null): ChapterInfo[] {
    const chapters: ChapterInfo[] = this.copyChapters(detail?.chapters);
    chapters.sort((left: ChapterInfo, right: ChapterInfo) => {
      const leftNumber: number = this.getChapterNumber(left);
      const rightNumber: number = this.getChapterNumber(right);
      return rightNumber - leftNumber;
    });
    return chapters;
  }

  private getChapterNumber(chapter: ChapterInfo): number {
    return typeof chapter.chapterNumber === 'number' ? Number(chapter.chapterNumber) : 0;
  }

  private async loadChapterList(): Promise<void> {
    await this.executor.initialize(true);
    const detail: ComicDetailInfo | null = await this.executor.getDetail(this.itemId, this.contentType);
    this.chapterList = this.sortChapters(detail);
    if (this.chapterList.length <= 0) {
      this.chapterTitle = '';
      return;
    }

    if (this.chapterId.length > 0) {
      const matchedIndex: number = this.chapterList.findIndex((item: ChapterInfo) => item.id === this.chapterId);
      if (matchedIndex >= 0) {
        this.chapterIndex = matchedIndex;
      }
    }

    if (this.chapterIndex < 0 || this.chapterIndex >= this.chapterList.length) {
      this.chapterIndex = 0;
    }

    const current: ChapterInfo = this.chapterList[this.chapterIndex];
    this.chapterId = current.id;
    this.chapterTitle = current.title;
  }

  private async loadPages(): Promise<void> {
    if (this.chapterId.length <= 0) {
      this.errorMessage = '章节 ID 无效';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    try {
      await this.executor.initialize(true);
      this.pages = await this.executor.getPages(this.chapterId);
      await this.restoreReadingProgress();
      if (this.currentPage >= 0 && this.currentPage < this.pages.length) {
        this.swiperController.changeIndex(this.currentPage);
      }
    } catch (error) {
      logger.error(TAG, `加载 Komga 阅读页面失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private async restoreReadingProgress(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: READING_PROGRESS_STORE });
      const rawText = store.getSync(this.getProgressKey(), '') as string;
      if (!rawText) {
        this.currentPage = 0;
        return;
      }

      const progress: KomgaReaderProgress = JSON.parse(rawText) as KomgaReaderProgress;
      if (progress.bookId === this.chapterId && progress.pageIndex >= 0 && progress.pageIndex < this.pages.length) {
        this.currentPage = progress.pageIndex;
      } else {
        this.currentPage = 0;
      }
    } catch (error) {
      logger.warn(TAG, `读取 Komga 阅读器进度失败: ${String(error)}`);
      this.currentPage = 0;
    }
  }

  private async saveReadingProgress(): Promise<void> {
    if (this.chapterId.length <= 0) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: READING_PROGRESS_STORE });
      const payload: KomgaReaderProgress = {
        itemKey: this.getProgressKey(),
        bookId: this.chapterId,
        chapterIndex: this.chapterIndex,
        pageIndex: this.currentPage,
        timestamp: Date.now()
      };
      store.putSync(this.getProgressKey(), JSON.stringify(payload));
      await store.flush();
    } catch (error) {
      logger.warn(TAG, `保存 Komga 阅读进度失败: ${String(error)}`);
    }
  }

  private async switchChapter(index: number): Promise<void> {
    if (index < 0 || index >= this.chapterList.length) {
      return;
    }

    await this.saveReadingProgress();
    this.chapterIndex = index;
    this.chapterId = this.chapterList[index].id;
    this.chapterTitle = this.chapterList[index].title;
    this.currentPage = 0;
    this.pages = [];
    this.showControls = true;
    this.controlsOpacity = 1;
    this.topBarTranslateY = 0;
    this.bottomBarTranslateY = 0;
    this.controlsBackdropOpacity = 1;
    await this.loadPages();
  }

  private async goToPreviousChapter(): Promise<void> {
    if (this.chapterIndex + 1 >= this.chapterList.length) {
      this.toast('已是最旧内容');
      return;
    }
    await this.switchChapter(this.chapterIndex + 1);
  }

  private async goToNextChapter(): Promise<void> {
    if (this.chapterIndex - 1 < 0) {
      this.toast('已是最新内容');
      return;
    }
    await this.switchChapter(this.chapterIndex - 1);
  }

  private toggleControls(): void {
    this.setControlsVisible(!this.showControls);
  }

  private goBack(): void {
    void this.saveReadingProgress();
    this.exitFullScreen('goBack');
    this.pathStack.pop();
  }

  private goToPage(index: number): void {
    if (index < 0 || index >= this.pages.length) {
      return;
    }
    this.currentPage = index;
    this.swiperController.changeIndex(index);
    void this.saveReadingProgress();
  }

  private buildChapterProgressText(): string {
    if (this.chapterList.length <= 0) {
      return '章节信息未加载';
    }
    return `内容 ${this.chapterIndex + 1} / ${this.chapterList.length}`;
  }

  @Builder
  private buildTopBar() {
    Row({ space: 10 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(44)
      .height(44)
      .backgroundColor('rgba(255,255,255,0.12)')
      .borderRadius(22)
      .onClick(() => this.goBack())

      Column({ space: 4 }) {
        Text(this.mangaTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.chapterTitle.length > 0 ? this.chapterTitle : '正在加载章节…')
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.78)')
          .fontFamily(this.appFontFamily)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 2 }) {
        Text(`${this.currentPage + 1} / ${Math.max(1, this.pages.length)}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)

        Text(this.buildChapterProgressText())
          .fontSize(10)
          .fontColor('rgba(255,255,255,0.66)')
          .fontFamily(this.appFontFamily)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#CC000000')
    .opacity(this.controlsOpacity)
  }

  @Builder
  private buildBottomBar() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(`${this.currentPage + 1}`)
          .fontSize(13)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .width(42)
          .textAlign(TextAlign.Center)

        Slider({
          value: this.currentPage,
          min: 0,
          max: Math.max(0, this.pages.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .selectedColor('#007AFF')
          .trackColor('rgba(255,255,255,0.28)')
          .onChange((value: number) => {
            const nextPage: number = Math.round(value);
            if (nextPage !== this.currentPage) {
              this.goToPage(nextPage);
            }
          })

        Text(`${Math.max(1, this.pages.length)}`)
          .fontSize(13)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .width(42)
          .textAlign(TextAlign.Center)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('上一章')
          .height(38)
          .layoutWeight(1)
          .backgroundColor(this.chapterIndex + 1 < this.chapterList.length ? '#007AFF' : 'rgba(255,255,255,0.18)')
          .fontColor(this.chapterIndex + 1 < this.chapterList.length ? Color.White : 'rgba(255,255,255,0.5)')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .enabled(this.chapterIndex + 1 < this.chapterList.length)
          .onClick(() => {
            void this.goToPreviousChapter();
          })

        Button('下一章')
          .height(38)
          .layoutWeight(1)
          .backgroundColor(this.chapterIndex - 1 >= 0 ? '#007AFF' : 'rgba(255,255,255,0.18)')
          .fontColor(this.chapterIndex - 1 >= 0 ? Color.White : 'rgba(255,255,255,0.5)')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .enabled(this.chapterIndex - 1 >= 0)
          .onClick(() => {
            void this.goToNextChapter();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    .backgroundColor('#CC000000')
    .opacity(this.controlsOpacity)
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Color.White)
      Text('正在加载页面…')
        .fontSize(14)
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildErrorState() {
    Column({ space: 16 }) {
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor('#FF6B6B')
        .fontFamily(this.appFontFamily)
        .textAlign(TextAlign.Center)

      Button('重试')
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          void this.loadPages();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }

  @Builder
  private buildEmptyState() {
    Column({ space: 12 }) {
      Text('暂无页面')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .fontFamily(this.appFontFamily)
      Text('请检查该内容是否已完成同步或转码。')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.66)')
        .fontFamily(this.appFontFamily)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }

  @Builder
  private buildPageContent() {
    if (this.isLoading) {
      this.buildLoadingState()
    } else if (this.errorMessage.length > 0) {
      this.buildErrorState()
    } else if (this.pages.length <= 0) {
      this.buildEmptyState()
    } else {
      Swiper(this.swiperController) {
        ForEach(this.pages, (page: PageInfo, index: number) => {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Column() {
              KomgaImage({
                src: page.url,
                imageWidth: '100%',
                imageHeight: '100%',
                objectFit: ImageFit.Contain,
                imgBorderRadius: 0
              })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .backgroundColor(Color.Black)

            Text(`${index + 1}`)
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.88)')
              .fontFamily(this.appFontFamily)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('rgba(0,0,0,0.36)')
              .borderRadius(999)
              .margin({ right: 12, bottom: 12 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
        }, (page: PageInfo, index: number) => `komga_page_${index}_${page.url}`)
      }
      .width('100%')
      .height('100%')
      .index(this.currentPage)
      .indicator(false)
      .loop(false)
      .onChange((index: number) => {
        this.currentPage = index;
        void this.saveReadingProgress();
      })
      .onClick(() => this.toggleControls())
    }
  }

  build() {
    NavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        this.buildPageContent()

        if (this.showControls) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.16)')
            .opacity(this.controlsBackdropOpacity)
            .onClick(() => this.toggleControls())
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          Column() {
            this.buildTopBar()
          }
          .width('100%')
          .position({ top: 0 })
          .translate({ x: 0, y: this.topBarTranslateY })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        }

        if (this.showControls) {
          Column() {
            Blank()
            this.buildBottomBar()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .translate({ x: 0, y: this.bottomBarTranslateY })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: KomgaReaderParams = param as KomgaReaderParams;
        this.itemId = params.itemId;
        this.contentType = params.contentType;
        this.chapterId = params.bookId;
        this.chapterIndex = params.chapterIndex;
        this.mangaTitle = params.mangaTitle;
      }

      void (async () => {
        await this.loadChapterList();
        await this.loadPages();
      })();
    })
    .onShown(() => {
      WindowManager.reapplyCurrentDisplayMode(24);
      this.setControlsVisible(this.showControls);
    })
    .backgroundColor(Color.Black)
  }
}
