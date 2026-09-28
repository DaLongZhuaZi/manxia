import { common } from '@kit.AbilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { RemoteControlPage } from './RemoteControlPage';
import {
  REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY,
  REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY
} from '../Framework/RemoteControl/RemoteControlAbilityConstants';
import {
  RemoteControlAbilityParamStore,
  RemoteControlAbilityWindowPayload
} from '../Framework/RemoteControl/RemoteControlAbilityParamStore';
import { ContinuationTriggeredPayload } from '../Framework/EventBus';

const TAG: string = 'RemoteControlAbilityPage';
let remoteControlAbilityPageStorage: LocalStorage = new LocalStorage();

class RemoteControlNavigationFrameCallback extends FrameCallback {
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

@Entry(remoteControlAbilityPageStorage)
@Component
struct RemoteControlAbilityPage {
  @Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();
  @State private remoteParams: ContinuationTriggeredPayload | null = null;
  @LocalStorageProp(REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY) private remoteInstanceId: string = '';
  @StorageProp(REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY) @Watch('onRefreshTriggerChanged') private refreshTrigger: number = 0;
  private hasOpenedRemoteControl: boolean = false;
  private hasScheduledInitialRemoteControlOpen: boolean = false;
  private navigationScheduleGeneration: number = 0;
  private isPageActive: boolean = false;
  private scheduledFrameCallback: RemoteControlNavigationFrameCallback | null = null;
  private lastRefreshTrigger: number = 0;

  aboutToAppear(): void {
    this.isPageActive = true;
    this.resolveRemoteControlLaunchPayload('appear');
    this.scheduleInitialRemoteControlOpen();
  }

  onRefreshTriggerChanged(_changedPropertyName?: string): void {
    this.handleRefreshTrigger('watch');
  }

  onPageShow(): void {
    this.isPageActive = true;
    this.handleRefreshTrigger('page_show');
    this.scheduleInitialRemoteControlOpen();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.navigationScheduleGeneration += 1;
    this.hasScheduledInitialRemoteControlOpen = false;
    this.scheduledFrameCallback = null;
  }

  private handleRefreshTrigger(source: string): void {
    if (this.lastRefreshTrigger === this.refreshTrigger) {
      return;
    }
    this.lastRefreshTrigger = this.refreshTrigger;
    const activeInstanceId = RemoteControlAbilityParamStore.getInstance().getActiveInstanceId();
    if (activeInstanceId.length > 0) {
      this.remoteInstanceId = activeInstanceId;
    }
    this.resolveRemoteControlLaunchPayload(source, true);
    this.replaceRemoteControlParams(source);
  }

  private scheduleInitialRemoteControlOpen(): void {
    if (!this.isPageActive ||
      this.hasOpenedRemoteControl ||
      this.hasScheduledInitialRemoteControlOpen) {
      return;
    }
    try {
      const uiContext: UIContext = this.getUIContext();
      const scheduleGeneration: number = this.navigationScheduleGeneration + 1;
      this.navigationScheduleGeneration = scheduleGeneration;
      this.hasScheduledInitialRemoteControlOpen = true;
      const frameCallback = new RemoteControlNavigationFrameCallback((): void => {
        if (scheduleGeneration !== this.navigationScheduleGeneration) {
          return;
        }
        this.scheduledFrameCallback = null;
        this.hasScheduledInitialRemoteControlOpen = false;
        if (!this.isPageActive || this.hasOpenedRemoteControl) {
          return;
        }
        this.resolveRemoteControlLaunchPayload('frame_idle');
        this.openInitialRemoteControl();
      });
      this.scheduledFrameCallback = frameCallback;
      uiContext.postFrameCallback(frameCallback);
    } catch (error) {
      this.scheduledFrameCallback = null;
      this.hasScheduledInitialRemoteControlOpen = false;
      logger.warn(TAG, `调度独立遥控器初始路由失败: ${String(error)}`);
    }
  }

  private resolveRemoteControlLaunchPayload(source: string, allowReplace: boolean = false): void {
    if (this.remoteParams && !allowReplace) {
      return;
    }
    const store = RemoteControlAbilityParamStore.getInstance();
    const windowId = this.resolveHostWindowId();
    let payload: RemoteControlAbilityWindowPayload | null = store.resolveWindowPayload(windowId);
    if (!payload) {
      payload = store.consumePendingPayload();
    }
    if (!payload && this.remoteInstanceId.length > 0) {
      const params = store.getParams(this.remoteInstanceId);
      if (params) {
        this.remoteParams = params;
        logger.info(TAG, `独立遥控器参数已从实例恢复: source=${source}, instanceId=${this.remoteInstanceId}`);
        return;
      }
    }
    if (!payload) {
      logger.error(TAG, `独立遥控器参数未绑定: source=${source}, windowId=${windowId}`);
      return;
    }
    this.remoteParams = payload.params;
    this.remoteInstanceId = payload.instanceId;
    logger.info(TAG, `独立遥控器参数已解析: source=${source}, instanceId=${this.remoteInstanceId}, windowId=${windowId}, payloadWindowId=${payload.windowId}`);
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
      logger.warn(TAG, `获取独立遥控器页面窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private openInitialRemoteControl(): boolean {
    if (this.hasOpenedRemoteControl) {
      return true;
    }

    if (!this.remoteParams) {
      logger.error(TAG, `独立遥控器参数为空: instanceId=${this.remoteInstanceId}`);
      return false;
    }

    try {
      logger.info(TAG, `打开独立遥控器目标页: instanceId=${this.remoteInstanceId}, sessionId=${this.remoteParams.sessionId}`);
      this.pathStack.pushPathByName('RemoteControlPage', this.remoteParams, false);
      this.hasOpenedRemoteControl = true;
      return true;
    } catch (error) {
      logger.error(TAG, `打开独立遥控器目标页失败: instanceId=${this.remoteInstanceId}, error=${String(error)}`);
      return false;
    }
  }

  private replaceRemoteControlParams(source: string): void {
    if (!this.hasOpenedRemoteControl) {
      this.scheduleInitialRemoteControlOpen();
      return;
    }
    if (!this.remoteParams) {
      return;
    }
    try {
      this.pathStack.replacePathByName('RemoteControlPage', this.remoteParams, false);
      logger.info(TAG, `独立遥控器参数已刷新: source=${source}, instanceId=${this.remoteInstanceId}, sessionId=${this.remoteParams.sessionId}`);
    } catch (error) {
      logger.warn(TAG, `刷新独立遥控器参数失败: source=${source}, reason=${String(error)}`);
    }
  }

  @Builder
  private buildDestination(name: string, _param: Object) {
    if (name === 'RemoteControlPage') {
      RemoteControlPage()
    }
  }

  @Builder
  private buildFallbackContent() {
    Column() {
      Text('遥控器启动失败')
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
      Text('未获取到遥控会话参数')
        .fontSize(13)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('sys.color.background_primary'))
  }

  build() {
    Navigation(this.pathStack) {
      if (!this.remoteParams) {
        this.buildFallbackContent()
      } else {
        Column() {
          Blank()
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.background_primary'))
      }
    }
    .hideNavBar(true)
    .navDestination(this.buildDestination)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
  }
}
