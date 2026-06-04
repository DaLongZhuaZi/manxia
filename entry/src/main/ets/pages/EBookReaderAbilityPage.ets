import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { DisplayMode, WindowManager } from '../Utils/WindowManager';
import { EBookReaderPage } from './EBookReaderPage';
import { EBookImageReaderPage } from './EBookImageReaderPage';
import { EpubWebViewReaderPage } from './EpubWebViewReaderPage';
import { EBookReaderParams } from './EBookReaderRouteTypes';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { resolveEBookReaderRouteName } from '../Framework/Adapters/EBookImageReaderAdapter';
import { EBookParserFactory } from '../Framework/Parsers/EBookParser';
import {
  EBook,
  EBookChapter,
  EBookFormat,
  EBookReaderEngine
} from '../Models/EBookModels';
import { createUserManualEBookFromRawFile, isUserManualId } from '../Data/UserManualData';
import { READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import {
  EBookReaderAbilityParamStore,
  EBookReaderAbilityWindowPayload
} from '../Framework/Reader/EBookReaderAbilityParamStore';

const TAG: string = 'EBookReaderAbilityPage';

@Entry
@Component
struct EBookReaderAbilityPage {
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private readerParams: EBookReaderParams | null = null;
  @State private readerInstanceId: string = '';
  private hasOpenedReader: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    this.applyRootImmersiveWindow('appear');
    this.resolveReaderLaunchPayload('appear');
    void this.openInitialReader();
    setTimeout((): void => {
      this.applyRootImmersiveWindow('deferred');
      this.resolveReaderLaunchPayload('deferred');
      void this.openInitialReader();
    }, 0);
  }

  onPageShow(): void {
    this.applyRootImmersiveWindow('page_show');
  }

  private applyRootImmersiveWindow(source: string): void {
    try {
      const uiContext = this.getUIContext();
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext);
      setTimeout((): void => {
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, uiContext);
      }, 96);
      logger.info(TAG, `独立电子书阅读器根窗口已应用全沉浸: source=${source}`);
    } catch (error) {
      logger.warn(TAG, `独立电子书阅读器根窗口应用全沉浸失败: source=${source}, error=${String(error)}`);
    }
  }

  private resolveReaderLaunchPayload(source: string): void {
    if (this.readerParams) {
      return;
    }
    const store = EBookReaderAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: EBookReaderAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload) {
      logger.error(TAG, `独立电子书阅读器参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.readerParams = payload.params;
    this.readerInstanceId = payload.instanceId;
    logger.info(TAG, `独立电子书阅读器参数已解析: source=${source}, instanceId=${this.readerInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
  }

  private resolveHostWindowId(): number {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        return -1;
      }
      const mainWindow = hostContext.windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立电子书阅读器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private async openInitialReader(): Promise<void> {
    if (this.hasOpenedReader) {
      return;
    }

    if (!this.readerParams) {
      logger.error(TAG, `独立电子书阅读器参数为空: instanceId=${this.readerInstanceId}`);
      return;
    }

    this.hasOpenedReader = true;
    const params = this.buildIsolatedReaderParams(this.readerParams);
    const routeName = await this.resolveInitialRouteName(params);
    logger.info(TAG, `打开独立电子书阅读器目标页: instanceId=${this.readerInstanceId}, route=${routeName}, bookId=${params.bookId}`);
    this.pathStack.pushPathByName(routeName, params);
  }

  private buildIsolatedReaderParams(source: EBookReaderParams): EBookReaderParams {
    const params: EBookReaderParams = {
      bookId: source.bookId,
      coverComponentId: source.coverComponentId,
      routerBackOnClose: false,
      forceReaderKit: source.forceReaderKit,
      autoStartReadAloud: source.autoStartReadAloud,
      autoOpenReadAloudPlayer: source.autoOpenReadAloudPlayer,
      readerHostMode: READER_ABILITY_HOST_MULTITON,
      readerInstanceId: this.readerInstanceId,
      readerTitle: source.readerTitle
    };
    return params;
  }

  private async resolveInitialRouteName(params: EBookReaderParams): Promise<string> {
    if (params.forceReaderKit === true) {
      return 'EBookReaderPage';
    }
    try {
      const ebook = await this.resolveInitialEBook(params);
      if (ebook === null) {
        logger.warn(TAG, `无法解析独立电子书阅读路由：未找到书籍 bookId=${params.bookId}`);
        return 'EBookReaderPage';
      }
      const resolvedEBook: EBook = ebook;
      const repairedEBook = await this.repairKindleWebViewRouteIfNeeded(resolvedEBook);
      const routeName = resolveEBookReaderRouteName(repairedEBook);
      logger.info(TAG, `独立电子书阅读路由判定: bookId=${repairedEBook.id}, route=${routeName}`);
      return routeName;
    } catch (error) {
      logger.warn(TAG, `解析独立电子书阅读路由失败，回退普通阅读页: ${String(error)}`);
      return 'EBookReaderPage';
    }
  }

  private async resolveInitialEBook(params: EBookReaderParams): Promise<EBook | null> {
    let ebook: EBook | null = await this.ebookDataManager.getEBookById(params.bookId);
    if (!ebook && isUserManualId(params.bookId)) {
      ebook = await this.recoverUserManualEBook(params.bookId);
      if (ebook) {
        params.bookId = ebook.id;
      }
    }
    return ebook;
  }

  private async recoverUserManualEBook(requestedBookId: string): Promise<EBook | null> {
    try {
      const userManual = await createUserManualEBookFromRawFile();
      try {
        await this.ebookDataManager.saveEBook(userManual);
      } catch (saveError) {
        logger.warn(TAG, `恢复内置使用手册时保存数据库失败: requested=${requestedBookId}, current=${userManual.id}, error=${String(saveError)}`);
      }
      logger.info(TAG, `已从 rawfile 恢复内置使用手册: requested=${requestedBookId}, current=${userManual.id}`);
      return userManual;
    } catch (error) {
      logger.warn(TAG, `恢复内置使用手册失败: requested=${requestedBookId}, error=${String(error)}`);
      return null;
    }
  }

  private isKindleFormat(format: EBookFormat): boolean {
    return format === EBookFormat.MOBI || format === EBookFormat.AZW || format === EBookFormat.AZW3;
  }

  private async repairKindleWebViewRouteIfNeeded(ebook: EBook): Promise<EBook> {
    if (!this.isKindleFormat(ebook.format)) {
      return ebook;
    }
    if (ebook.preferredReaderEngine === EBookReaderEngine.WEBVIEW &&
      (ebook.extractedRootPath || '').length > 0) {
      return ebook;
    }

    try {
      const parser = EBookParserFactory.createParser(ebook.filePath);
      if (!parser) {
        return ebook;
      }
      const reparsed = await parser.parse();
      if (reparsed.preferredReaderEngine !== EBookReaderEngine.WEBVIEW ||
        (reparsed.extractedRootPath || '').length <= 0) {
        return ebook;
      }

      ebook.metadata = reparsed.metadata;
      ebook.fileSize = reparsed.fileSize;
      ebook.chapters = this.rebindChapterBookId(reparsed.chapters, ebook.id);
      ebook.totalWordCount = reparsed.totalWordCount;
      ebook.contentMode = reparsed.contentMode;
      ebook.preferredReaderEngine = reparsed.preferredReaderEngine;
      ebook.extractedRootPath = reparsed.extractedRootPath;
      if (ebook.chapters.length > 0) {
        const safeIndex = Math.max(0, Math.min(ebook.readingProgress.currentChapterIndex, ebook.chapters.length - 1));
        ebook.readingProgress.currentChapterIndex = safeIndex;
        ebook.readingProgress.currentChapterId = ebook.chapters[safeIndex].id;
      }
      ebook.lastUpdateTime = Date.now();
      await this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
      logger.info(TAG, `独立电子书 Kindle WebView 路由已修复: bookId=${ebook.id}, chapters=${ebook.chapters.length}`);
      return ebook;
    } catch (error) {
      logger.warn(TAG, `独立电子书 Kindle WebView 路由修复失败: ${String(error)}`);
      return ebook;
    }
  }

  private rebindChapterBookId(chapters: EBookChapter[], bookId: string): EBookChapter[] {
    const result: EBookChapter[] = [];
    const now = Date.now();
    for (let index = 0; index < chapters.length; index++) {
      const source = chapters[index];
      const chapter: EBookChapter = {
        id: source.id || `kindle_${bookId}_${index}`,
        bookId: bookId,
        chapterNumber: source.chapterNumber || index + 1,
        title: source.title || `第${index + 1}章`,
        content: source.content || '',
        startPosition: source.startPosition || 0,
        endPosition: source.endPosition || 0,
        wordCount: source.wordCount || 0,
        resourceHref: source.resourceHref || '',
        resourceFile: source.resourceFile || '',
        resourceMediaType: source.resourceMediaType || '',
        resourceLayoutType: source.resourceLayoutType || '',
        resourceImagePath: source.resourceImagePath || '',
        resourceImageRelativePath: source.resourceImageRelativePath || '',
        createTime: source.createTime || now
      };
      result.push(chapter);
    }
    return result;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'EBookReaderPage') {
      EBookReaderPage()
    } else if (name === 'EBookImageReaderPage') {
      EBookImageReaderPage()
    } else if (name === 'EpubWebViewReaderPage') {
      EpubWebViewReaderPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('阅读器启动失败')
        .fontSize(18)
        .fontColor(Color.White)
      Text('未获取到电子书阅读参数')
        .fontSize(13)
        .fontColor(Color.White)
        .opacity(0.6)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
  }

  build() {
    Stack() {
      Navigation(this.pathStack) {
        if (!this.readerParams) {
          this.buildFallbackContent()
        } else {
          Column() {
            Blank()
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Black)
        }
      }
      .hideNavBar(true)
      .navDestination(this.buildDestination)
      .mode(NavigationMode.Stack)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])

      ReaderAbilityBackgroundBlurOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
