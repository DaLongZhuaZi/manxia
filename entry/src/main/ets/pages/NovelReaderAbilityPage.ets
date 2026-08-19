import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { NovelReaderPage } from './NovelReaderPage';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import {
  NovelReaderAbilityParamStore,
  NovelReaderAbilityWindowPayload
} from '../Framework/Reader/NovelReaderAbilityParamStore';

const TAG: string = 'NovelReaderAbilityPage';

class NovelReaderNavigationFrameCallback extends FrameCallback {
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
struct NovelReaderAbilityPage {
  private pathStack: NavPathStack = new NavPathStack();
  @State private readerParams: NovelReaderPageParams | null = null;
  private readerInstanceId: string = '';
  private hasOpenedReader: boolean = false;
  private hasScheduledInitialReaderOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: NovelReaderNavigationFrameCallback | null = null;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.resolveReaderLaunchPayload('appear');
    this.scheduleInitialReaderOpen();
  }

  onPageShow(): void {
    this.isPageActive = true;
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
      const frameCallback = new NovelReaderNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialReaderOpen = false;
        if (!this.isPageActive || this.hasOpenedReader) {
          return;
        }
        this.resolveReaderLaunchPayload('frame_idle');
        this.openInitialReader();
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialReaderOpen = false;
      logger.warn(TAG, `调度独立小说阅读器初始路由失败: ${String(error)}`);
    }
  }

  private resolveReaderLaunchPayload(source: string): void {
    if (this.readerParams) {
      return;
    }
    const store = NovelReaderAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: NovelReaderAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload) {
      logger.error(TAG, `独立小说阅读器参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.readerParams = payload.params;
    this.readerInstanceId = payload.instanceId;
    logger.info(TAG, `独立小说阅读器参数已解析: source=${source}, instanceId=${this.readerInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
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
      logger.warn(TAG, `获取独立小说阅读器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialReader(): boolean {
    if (this.hasOpenedReader) {
      return true;
    }

    if (!this.readerParams) {
      logger.error(TAG, `独立小说阅读器参数为空: instanceId=${this.readerInstanceId}`);
      return false;
    }

    const params = this.buildIsolatedReaderParams(this.readerParams);
    this.pathStack.pushPathByName('NovelReaderPage', params, false);
    this.hasOpenedReader = true;
    logger.info(TAG, `打开独立小说阅读器目标页: instanceId=${this.readerInstanceId}, book=${params.bookName}, chapterIndex=${params.chapterIndex}`);
    return true;
  }

  private buildIsolatedReaderParams(source: NovelReaderPageParams): NovelReaderPageParams {
    const params: NovelReaderPageParams = {
      sourceId: source.sourceId,
      bookUrl: source.bookUrl,
      bookName: source.bookName,
      chapterUrl: source.chapterUrl,
      chapterTitle: source.chapterTitle,
      chapterIndex: source.chapterIndex,
      totalChapters: source.totalChapters,
      chapterPageIndex: source.chapterPageIndex,
      chapterStartOffset: source.chapterStartOffset,
      tocUrl: source.tocUrl,
      bookVariable: source.bookVariable,
      bookRequestUrlTemplate: source.bookRequestUrlTemplate,
      tocRequestUrlTemplate: source.tocRequestUrlTemplate,
      author: source.author,
      coverUrl: source.coverUrl,
      sourceName: source.sourceName,
      coverComponentId: source.coverComponentId,
      autoStartReadAloud: source.autoStartReadAloud,
      autoOpenReadAloudPlayer: source.autoOpenReadAloudPlayer,
      localEbookId: source.localEbookId,
      readerHostMode: READER_ABILITY_HOST_MULTITON,
      readerInstanceId: this.readerInstanceId,
      readerTitle: source.readerTitle,
      readerOpenFlowId: source.readerOpenFlowId,
      // Keep the V2 verification intent across the isolated Ability boundary.
      // The destination reader uses it only for its initial current chapter.
      forceNetworkContentRefresh: source.forceNetworkContentRefresh === true
    };
    logger.info(
      TAG,
      `独立小说阅读器刷新意图转发: instanceId=${this.readerInstanceId}, forceContentRefresh=${params.forceNetworkContentRefresh === true}`
    );
    return params;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'NovelReaderPage') {
      NovelReaderPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('阅读器启动失败')
        .fontSize(18)
        .fontColor(Color.White)
      Text('未获取到小说阅读参数')
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

      ReaderAbilityBackgroundBlurOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }
}
