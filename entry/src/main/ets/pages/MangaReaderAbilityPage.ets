import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { MangaReaderPage, MangaReaderPageParams } from './MangaReaderPage';
import { MANGA_READER_ABILITY_HOST_MULTITON } from '../Framework/Reader/MangaReaderAbilityConstants';
import { ReaderAbilityBackgroundBlurOverlay } from '../Framework/Reader/ReaderAbilityBackgroundBlurOverlay';
import {
  MangaReaderAbilityParamStore,
  MangaReaderAbilityWindowPayload
} from '../Framework/Reader/MangaReaderAbilityParamStore';

const TAG: string = 'MangaReaderAbilityPage';

@Entry
@Component
struct MangaReaderAbilityPage {
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private readerParams: MangaReaderPageParams | null = null;
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
    const store = MangaReaderAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: MangaReaderAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload) {
      logger.error(TAG, `独立漫画阅读器参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.readerParams = payload.params;
    this.readerInstanceId = payload.instanceId;
    logger.info(TAG, `独立漫画阅读器参数已解析: source=${source}, instanceId=${this.readerInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
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
      logger.warn(TAG, `获取独立漫画阅读器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialReader(): void {
    if (this.hasOpenedReader) {
      return;
    }

    if (!this.readerParams) {
      logger.error(TAG, `独立漫画阅读器参数为空: instanceId=${this.readerInstanceId}`);
      return;
    }

    this.hasOpenedReader = true;
    const params = this.buildIsolatedReaderParams(this.readerParams);
    logger.info(TAG, `打开独立漫画阅读器目标页: instanceId=${this.readerInstanceId}, chapterId=${params.chapterId || ''}`);
    this.pathStack.pushPathByName('MangaReaderPage', params);
  }

  private buildIsolatedReaderParams(source: MangaReaderPageParams): MangaReaderPageParams {
    const params: MangaReaderPageParams = {
      manga: source.manga,
      mangaId: source.mangaId,
      sourceId: source.sourceId,
      sourcePkg: source.sourcePkg,
      sourceName: source.sourceName,
      contentType: source.contentType,
      chapterId: source.chapterId,
      pageIndex: source.pageIndex,
      fromPage: source.fromPage,
      coverComponentId: source.coverComponentId,
      skipDatabaseLookup: source.skipDatabaseLookup,
      chapterTitle: source.chapterTitle,
      readerHostMode: MANGA_READER_ABILITY_HOST_MULTITON,
      readerInstanceId: this.readerInstanceId,
      readerTitle: source.readerTitle
    };
    return params;
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'MangaReaderPage') {
      MangaReaderPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('阅读器启动失败')
        .fontSize(18)
        .fontColor(Color.White)
      Text('未获取到阅读参数')
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
