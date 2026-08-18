import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ReadAloudPlayerPage } from './ReadAloudPlayerPage';
import {
  ReadAloudPlayerAbilityParams,
  ReadAloudPlayerAbilityParamStore,
  ReadAloudPlayerAbilityWindowPayload
} from '../Framework/ReadAloud/ReadAloudPlayerAbilityParamStore';

const TAG: string = 'ReadAloudPlayerAbilityPage';
let readAloudPlayerAbilityPageStorage: LocalStorage = new LocalStorage();

class ReadAloudPlayerNavigationFrameCallback extends FrameCallback {
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

@Entry(readAloudPlayerAbilityPageStorage)
@Component
struct ReadAloudPlayerAbilityPage {
  @LocalStorageProp('readAloudPlayerAbilityInstanceId') private playerAbilityInstanceId: string = '';
  @StorageProp('readAloudPlayerAbilityRefreshTrigger') @Watch('onRefreshTriggerChanged') private refreshTrigger: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  @State private playerParams: ReadAloudPlayerAbilityParams = new ReadAloudPlayerAbilityParams();
  @State private routeVersion: number = 0;
  private hasOpenedPlayer: boolean = false;
  private hasScheduledInitialPlayerOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: ReadAloudPlayerNavigationFrameCallback | null = null;
  private lastRefreshTrigger: number = 0;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.resolvePlayerLaunchPayload('appear');
    this.scheduleInitialPlayerOpen();
  }

  onPageShow(): void {
    this.isPageActive = true;
    this.handleRefreshTrigger('page_show');
    this.scheduleInitialPlayerOpen();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.navigationScheduleGeneration += 1;
    this.hasScheduledInitialPlayerOpen = false;
    this.scheduledFrameCallback = null;
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

  private scheduleInitialPlayerOpen(): void {
    if (!this.isPageActive ||
      this.hasOpenedPlayer ||
      this.hasScheduledInitialPlayerOpen) {
      return;
    }
    try {
      const uiContext: UIContext = this.getUIContext();
      const scheduleGeneration: number = this.navigationScheduleGeneration + 1;
      this.navigationScheduleGeneration = scheduleGeneration;
      this.hasScheduledInitialPlayerOpen = true;
      const frameCallback = new ReadAloudPlayerNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialPlayerOpen = false;
        if (!this.isPageActive || this.hasOpenedPlayer) {
          return;
        }
        this.resolvePlayerLaunchPayload('frame_idle');
        this.openInitialPlayer();
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialPlayerOpen = false;
      logger.warn(TAG, `调度独立听书播放器初始路由失败: ${String(error)}`);
    }
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

  private openInitialPlayer(): boolean {
    if (this.hasOpenedPlayer) {
      return true;
    }
    try {
      this.pathStack.pushPathByName('ReadAloudPlayerPage', this.playerParams, false);
      this.hasOpenedPlayer = true;
      logger.info(TAG, `打开独立听书播放器目标页: instanceId=${this.playerAbilityInstanceId}`);
      return true;
    } catch (error) {
      logger.error(TAG, `打开独立听书播放器目标页失败: instanceId=${this.playerAbilityInstanceId}, error=${String(error)}`);
      return false;
    }
  }

  private replacePlayerParams(source: string): void {
    if (!this.hasOpenedPlayer) {
      this.scheduleInitialPlayerOpen();
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
