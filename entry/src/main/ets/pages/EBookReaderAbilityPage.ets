import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DisplayMode, WindowManager } from 'manxia_theme/src/main/ets/Utils/WindowManager';
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
} from 'manxia_core/src/main/ets/Models/EBookModels';
import { createUserManualEBookFromRawFile, isUserManualId } from 'manxia_core/src/main/ets/Framework/Data/UserManualData';
import { READER_ABILITY_HOST_MULTITON } from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';
import { RemoteControlSocketChannel, RemoteFileRequestOptions } from '../Framework/Distributed/RemoteControlSocketChannel';
import { OnlineEBookImportService } from '../Framework/Services/OnlineEBookImportService';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import {
  EBookReaderAbilityParamStore,
  EBookReaderAbilityWindowPayload
} from '../Framework/Reader/EBookReaderAbilityParamStore';
import { ContinuationBootstrap } from '../Framework/Initialization/ContinuationBootstrap';

const TAG: string = 'EBookReaderAbilityPage';

class EBookReaderNavigationFrameCallback extends FrameCallback {
  private callback: () => void;
  private hasRun: boolean = false;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onFrame(_frameTimeInNano: number): void {
  }

  onIdle(_timeLeftInNano: number): void {
    if (this.hasRun) {
      return;
    }
    this.hasRun = true;
    this.callback();
  }
}

@Entry
@Component
struct EBookReaderAbilityPage {
  private pathStack: NavPathStack = new NavPathStack();
  @State private readerParams: EBookReaderParams | null = null;
  // [跨端接续] 本地书籍从源设备传输期间的加载动画状态
  @State private transferProgressVisible: boolean = false;
  @State private transferProgressPercent: number = 0;
  @State private transferProgressText: string = '';
  private readerInstanceId: string = '';
  private hasOpenedReader: boolean = false;
  private hasScheduledInitialReaderOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private openingScheduleGeneration: number = 0;
  private isOpeningReader: boolean = false;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: EBookReaderNavigationFrameCallback | null = null;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    this.isPageActive = true;
    this.applyRootImmersiveWindow('appear');
    this.resolveReaderLaunchPayload('appear');
    this.scheduleInitialReaderOpen();
  }

  onPageShow(): void {
    this.isPageActive = true;
    this.applyRootImmersiveWindow('page_show');
    if (this.hasOpenedReader) {
      return;
    }
    this.resolveReaderLaunchPayload('page_show');
    this.scheduleInitialReaderOpen();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.navigationScheduleGeneration += 1;
    this.hasScheduledInitialReaderOpen = false;
    this.scheduledFrameCallback = null;
  }

  private scheduleInitialReaderOpen(): void {
    if (!this.isPageActive ||
      this.hasOpenedReader ||
      this.hasScheduledInitialReaderOpen) {
      return;
    }
    try {
      const uiContext: UIContext = this.getUIContext();
      const scheduleGeneration: number = this.navigationScheduleGeneration + 1;
      this.navigationScheduleGeneration = scheduleGeneration;
      this.hasScheduledInitialReaderOpen = true;
      const frameCallback = new EBookReaderNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialReaderOpen = false;
        if (!this.isPageActive || this.hasOpenedReader) {
          return;
        }
        this.applyRootImmersiveWindow('frame_idle');
        this.resolveReaderLaunchPayload('frame_idle');
        void this.openInitialReader(scheduleGeneration);
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialReaderOpen = false;
      logger.warn(TAG, `调度独立电子书阅读器初始路由失败: ${String(error)}`);
    }
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

  private async ensureReaderBootstrapReady(): Promise<void> {
    try {
      const hostContext = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
      if (!hostContext) {
        logger.warn(TAG, '等待全局依赖就绪：无法获取宿主上下文，跳过等待');
        return;
      }
      const startTime = Date.now();
      await ContinuationBootstrap.getInstance().ensureReady(hostContext);
      logger.info(TAG, `全局依赖已就绪（GlobalContext + 数据库），等待耗时${Date.now() - startTime}ms`);
    } catch (error) {
      logger.warn(TAG, `等待全局依赖就绪失败，继续尝试打开阅读器: ${String(error)}`);
    }
  }

  private async openInitialReader(scheduleGeneration: number): Promise<void> {
    if (this.hasOpenedReader) {
      return;
    }

    if (!this.readerParams) {
      logger.error(TAG, `独立电子书阅读器参数为空: instanceId=${this.readerInstanceId}`);
      return;
    }

    if (this.isOpeningReader && this.openingScheduleGeneration === scheduleGeneration) {
      return;
    }
    this.isOpeningReader = true;
    this.openingScheduleGeneration = scheduleGeneration;
    try {
      // [修复] 接续冷启动落地时，等待 GlobalContext + 数据库就绪后再解析 bookId，
      // 避免“数据库未初始化 / 电子书不存在”；正常应用内打开时此处立即返回。
      await this.ensureReaderBootstrapReady();
      const params = this.buildIsolatedReaderParams(this.readerParams);
      const routeName = await this.resolveInitialRouteName(params);
      if (scheduleGeneration !== this.navigationScheduleGeneration ||
        !this.isPageActive ||
        this.hasOpenedReader) {
        return;
      }
      logger.info(TAG, `打开独立电子书阅读器目标页: instanceId=${this.readerInstanceId}, route=${routeName}, bookId=${params.bookId}`);
      this.pathStack.pushPathByName(routeName, params, false);
      this.hasOpenedReader = true;
    } catch (error) {
      logger.error(TAG, `打开独立电子书阅读器目标页失败: instanceId=${this.readerInstanceId}, error=${String(error)}`);
    } finally {
      if (this.openingScheduleGeneration === scheduleGeneration) {
        this.isOpeningReader = false;
      }
    }
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
      readerTitle: source.readerTitle,
      originImportId: source.originImportId,
      originImportKind: source.originImportKind,
      readerOpenFlowId: source.readerOpenFlowId
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
    // [修复] 接续时若命中此前“传输损坏被降级解析入库”的残留记录（文件缺失或 EPUB 无 zip 魔数），
    // 先清理记录再经通道重新拉取，避免直接打开损坏文件报“File is not exist”。
    if (ebook && this.isContinuationRestoreActive() && !this.isLocalBookFileUsable(ebook)) {
      logger.warn(TAG, `接续命中损坏的本地书籍残留记录，清理后重新从源设备拉取: bookId=${params.bookId}`);
      try {
        await this.ebookDataManager.deleteEBook(ebook.id);
      } catch (deleteError) {
        logger.warn(TAG, `清理损坏书籍记录失败: ${String(deleteError)}`);
      }
      ebook = null;
    }
    // [修复] 本地书跨端接续：目标端没有该书时，经独立连接通道向源端拉取文件并自动导入（保留源端 bookId）
    if (!ebook) {
      ebook = await this.recoverLocalEBookViaSocket(params.bookId);
    }
    return ebook;
  }

  private isContinuationRestoreActive(): boolean {
    const sessionId = AppStorage.get<string>('continuationSessionId');
    return sessionId !== undefined && sessionId.length > 0;
  }

  private isLocalBookFileUsable(ebook: EBook): boolean {
    const filePath = ebook.filePath || '';
    if (filePath.length <= 0 || !SafeFileUtils.accessSync(filePath)) {
      return false;
    }
    if (ebook.format === EBookFormat.EPUB) {
      return this.hasZipMagic(filePath);
    }
    return true;
  }

  private hasZipMagic(filePath: string): boolean {
    try {
      const file = SafeFileUtils.openSync(filePath);
      if (typeof file.fd !== 'number' || file.fd < 0) {
        return false;
      }
      const head = new ArrayBuffer(4);
      const readBytes = SafeFileUtils.readSync(file.fd, head);
      SafeFileUtils.closeSync(file.fd);
      if (readBytes < 4) {
        return false;
      }
      const view = new Uint8Array(head);
      return view[0] === 0x50 && view[1] === 0x4B;
    } catch (error) {
      return false;
    }
  }

  private async recoverLocalEBookViaSocket(bookId: string): Promise<EBook | null> {
    const continuationSessionId = AppStorage.get<string>('continuationSessionId');
    if (!continuationSessionId || continuationSessionId.length <= 0) {
      return null;
    }
    this.transferProgressVisible = true;
    this.transferProgressPercent = 0;
    this.transferProgressText = '正在从源设备同步本地书籍…';
    let receivedTempPath = '';
    try {
      const options: RemoteFileRequestOptions = {
        onProgress: (receivedBytes: number, totalBytes: number): void => {
          const percent = totalBytes > 0 ? Math.min(100, Math.round(receivedBytes * 100 / totalBytes)) : 0;
          this.transferProgressPercent = percent;
          this.transferProgressText = `正在从源设备同步本地书籍… ${percent}%`;
        }
      };
      const receiveResult = await RemoteControlSocketChannel.getInstance().requestBookFile(bookId, options);
      if (!receiveResult) {
        logger.warn(TAG, `从源设备传输书籍文件失败: bookId=${bookId}`);
        this.getUIContext().getPromptAction().showToast({ message: '本地书籍传输失败，请确认源设备遥控通道正常' });
        return null;
      }
      receivedTempPath = receiveResult.tempPath;
      this.transferProgressText = '正在导入本地书籍…';
      const imported = await OnlineEBookImportService.getInstance().importTransferredBook(
        receiveResult.tempPath,
        bookId,
        receiveResult.fileName
      );
      this.getUIContext().getPromptAction().showToast({ message: '本地书籍已从源设备同步完成' });
      return imported;
    } catch (error) {
      logger.warn(TAG, `恢复本地书籍失败（经独立通道传输）: bookId=${bookId}, error=${String(error)}`);
      return null;
    } finally {
      this.transferProgressVisible = false;
      if (receivedTempPath.length > 0) {
        try {
          SafeFileUtils.unlinkSync(receivedTempPath);
        } catch (cleanupError) {
          logger.debug(TAG, `清理传输临时文件失败: ${String(cleanupError)}`);
        }
      }
    }
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

      if (this.transferProgressVisible) {
        Column() {
          LoadingProgress()
            .width(46)
            .height(46)
            .color(Color.White)
          Text(this.transferProgressText)
            .fontSize(14)
            .fontColor(Color.White)
            .opacity(0.85)
            .margin({ top: 18 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Color.Black)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }
}
