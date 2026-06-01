import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { NovelReaderPage } from './NovelReaderPage';
import { NovelReaderPageParams } from './NovelBookshelfPage';
import { READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import {
  NovelReaderAbilityParamStore,
  NovelReaderAbilityWindowPayload
} from '../Framework/Reader/NovelReaderAbilityParamStore';

const TAG: string = 'NovelReaderAbilityPage';

@Entry
@Component
struct NovelReaderAbilityPage {
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private readerParams: NovelReaderPageParams | null = null;
  @State private readerInstanceId: string = '';
  private hasOpenedReader: boolean = false;

  aboutToAppear(): void {
    this.resolveReaderLaunchPayload('appear');
    this.openInitialReader();
    setTimeout((): void => {
      this.resolveReaderLaunchPayload('deferred');
      this.openInitialReader();
    }, 0);
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

  private openInitialReader(): void {
    if (this.hasOpenedReader) {
      return;
    }

    if (!this.readerParams) {
      logger.error(TAG, `独立小说阅读器参数为空: instanceId=${this.readerInstanceId}`);
      return;
    }

    this.hasOpenedReader = true;
    const params = this.buildIsolatedReaderParams(this.readerParams);
    logger.info(TAG, `打开独立小说阅读器目标页: instanceId=${this.readerInstanceId}, book=${params.bookName}, chapterIndex=${params.chapterIndex}`);
    this.pathStack.pushPathByName('NovelReaderPage', params);
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
      author: source.author,
      coverUrl: source.coverUrl,
      sourceName: source.sourceName,
      coverComponentId: source.coverComponentId,
      autoStartReadAloud: source.autoStartReadAloud,
      autoOpenReadAloudPlayer: source.autoOpenReadAloudPlayer,
      localEbookId: source.localEbookId,
      readerHostMode: READER_ABILITY_HOST_MULTITON,
      readerInstanceId: this.readerInstanceId,
      readerTitle: source.readerTitle
    };
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
