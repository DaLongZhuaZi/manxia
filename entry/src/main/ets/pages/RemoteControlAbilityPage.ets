import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
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

@Entry(remoteControlAbilityPageStorage)
@Component
struct RemoteControlAbilityPage {
  @Provide('NavPathStack') pathStack: NavPathStack = new NavPathStack();
  @State private remoteParams: ContinuationTriggeredPayload | null = null;
  @LocalStorageProp(REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY) private remoteInstanceId: string = '';
  @StorageProp(REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY) @Watch('onRefreshTriggerChanged') private refreshTrigger: number = 0;
  private hasOpenedRemoteControl: boolean = false;
  private lastRefreshTrigger: number = 0;

  aboutToAppear(): void {
    this.resolveRemoteControlLaunchPayload('appear');
    this.openInitialRemoteControl();
    setTimeout((): void => {
      this.resolveRemoteControlLaunchPayload('deferred');
      this.openInitialRemoteControl();
    }, 0);
  }

  onRefreshTriggerChanged(_changedPropertyName?: string): void {
    this.handleRefreshTrigger('watch');
  }

  onPageShow(): void {
    this.handleRefreshTrigger('page_show');
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

  private openInitialRemoteControl(): void {
    if (this.hasOpenedRemoteControl) {
      return;
    }

    if (!this.remoteParams) {
      logger.error(TAG, `独立遥控器参数为空: instanceId=${this.remoteInstanceId}`);
      return;
    }

    this.hasOpenedRemoteControl = true;
    logger.info(TAG, `打开独立遥控器目标页: instanceId=${this.remoteInstanceId}, sessionId=${this.remoteParams.sessionId}`);
    this.pathStack.pushPathByName('RemoteControlPage', this.remoteParams);
  }

  private replaceRemoteControlParams(source: string): void {
    if (!this.hasOpenedRemoteControl) {
      this.openInitialRemoteControl();
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
