import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { ReadAloudPlayerPage } from './ReadAloudPlayerPage';
import {
  ReadAloudPlayerAbilityParams,
  ReadAloudPlayerAbilityParamStore,
  ReadAloudPlayerAbilityWindowPayload
} from '../Framework/ReadAloud/ReadAloudPlayerAbilityParamStore';

const TAG: string = 'ReadAloudPlayerAbilityPage';
let readAloudPlayerAbilityPageStorage: LocalStorage = new LocalStorage();

@Entry(readAloudPlayerAbilityPageStorage)
@Component
struct ReadAloudPlayerAbilityPage {
  @LocalStorageProp('readAloudPlayerAbilityInstanceId') private playerAbilityInstanceId: string = '';
  @StorageProp('readAloudPlayerAbilityRefreshTrigger') @Watch('onRefreshTriggerChanged') private refreshTrigger: number = 0;
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private playerParams: ReadAloudPlayerAbilityParams = new ReadAloudPlayerAbilityParams();
  @State private routeVersion: number = 0;
  private hasOpenedPlayer: boolean = false;
  private lastRefreshTrigger: number = 0;

  aboutToAppear(): void {
    this.resolvePlayerLaunchPayload('appear');
    this.openInitialPlayer();
    setTimeout((): void => {
      this.resolvePlayerLaunchPayload('deferred');
      this.openInitialPlayer();
    }, 0);
  }

  onPageShow(): void {
    this.handleRefreshTrigger('page_show');
  }

  onRefreshTriggerChanged(_changedPropertyName?: string): void {
    this.handleRefreshTrigger('watch');
  }

  private handleRefreshTrigger(source: string): void {
    if (this.lastRefreshTrigger === this.refreshTrigger) {
      return;
    }
    this.lastRefreshTrigger = this.refreshTrigger;
    const activeInstanceId = ReadAloudPlayerAbilityParamStore.getInstance().getActiveInstanceId();
    if (activeInstanceId.length > 0) {
      this.playerAbilityInstanceId = activeInstanceId;
    }
    this.resolvePlayerLaunchPayload(source);
    this.replacePlayerParams(source);
  }

  private resolvePlayerLaunchPayload(source: string): void {
    const store = ReadAloudPlayerAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: ReadAloudPlayerAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }

    if (payload) {
      this.playerParams = this.resolveSafePlayerParams(payload.params);
      this.playerAbilityInstanceId = payload.instanceId;
      logger.info(
        TAG,
        `独立听书播放器参数已解析: source=${source}, instanceId=${this.playerAbilityInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`
      );
      return;
    }

    if (this.playerAbilityInstanceId.length > 0) {
      const params = store.getParams(this.playerAbilityInstanceId);
      if (params) {
        this.playerParams = params;
        logger.info(TAG, `独立听书播放器参数已从实例恢复: source=${source}, instanceId=${this.playerAbilityInstanceId}`);
        return;
      }
    }

    logger.warn(TAG, `独立听书播放器参数未绑定，将打开当前会话: source=${source}, windowId=${windowId}`);
  }

  private resolveSafePlayerParams(params: ReadAloudPlayerAbilityParams | null): ReadAloudPlayerAbilityParams {
    if (params) {
      return params;
    }
    return new ReadAloudPlayerAbilityParams();
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
      logger.warn(TAG, `获取独立听书播放器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialPlayer(): void {
    if (this.hasOpenedPlayer) {
      return;
    }
    this.hasOpenedPlayer = true;
    this.pathStack.pushPathByName('ReadAloudPlayerPage', this.playerParams);
    logger.info(TAG, `打开独立听书播放器目标页: instanceId=${this.playerAbilityInstanceId}`);
  }

  private replacePlayerParams(source: string): void {
    if (!this.hasOpenedPlayer) {
      this.openInitialPlayer();
      return;
    }
    try {
      this.routeVersion = this.routeVersion + 1;
      this.pathStack.replacePathByName('ReadAloudPlayerPage', this.playerParams, false);
      logger.info(TAG, `独立听书播放器参数已刷新: source=${source}, instanceId=${this.playerAbilityInstanceId}, version=${this.routeVersion}`);
    } catch (error) {
      logger.warn(TAG, `刷新独立听书播放器参数失败: source=${source}, reason=${String(error)}`);
    }
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'ReadAloudPlayerPage') {
      ReadAloudPlayerPage()
    }
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Blank()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
    }
    .hideNavBar(true)
    .navDestination(this.buildDestination)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_primary'))
  }
}
