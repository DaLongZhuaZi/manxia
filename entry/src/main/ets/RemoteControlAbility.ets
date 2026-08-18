import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import { ContinuationTriggeredPayload } from './Framework/EventBus';
import {
  REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY,
  REMOTE_CONTROL_ABILITY_PAGE,
  REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY
} from './Framework/RemoteControl/RemoteControlAbilityConstants';
import { RemoteControlAbilityParamStore } from './Framework/RemoteControl/RemoteControlAbilityParamStore';

const TAG: string = 'RemoteControlAbility';
const DEFAULT_REMOTE_CONTROL_TITLE: string = '遥控器';
const REMOTE_CONTROL_TITLE_SUFFIX: string = '遥控';
const MAX_REMOTE_CONTROL_TITLE_LENGTH: number = 18;

interface RemoteControlAbilityWantParameters {
  remoteControlAbilityInstanceId?: string;
}

export default class RemoteControlAbility extends UIAbility {
  private instanceId: string = '';
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    // 写入存活 token：源端 ContinuationStateHelper 据此判断遥控器已成功拉起，
    // 避免重复启动尝试与入口 Ability 兜底拉起抢焦点
    AppStorage.setOrCreate('remoteControlAbilityActiveToken', Date.now());
    logger.lifecycle(TAG, 'onCreate', `独立遥控器实例创建: instanceId=${this.instanceId}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const previousInstanceId = this.instanceId;
    this.instanceId = this.resolveInstanceId(want);
    this.refreshWindowPayload('new_want');
    AppStorage.setOrCreate(REMOTE_CONTROL_ABILITY_REFRESH_TRIGGER_KEY, Date.now());
    if (previousInstanceId.length > 0 && previousInstanceId !== this.instanceId) {
      RemoteControlAbilityParamStore.getInstance().remove(previousInstanceId);
    }
    logger.lifecycle(TAG, 'onNewWant', `独立遥控器接收新参数: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    const params: ContinuationTriggeredPayload | null =
      RemoteControlAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    RemoteControlAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, params);

    if (!params) {
      logger.warn(TAG, `独立遥控器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, params);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(REMOTE_CONTROL_ABILITY_INSTANCE_ID_KEY, this.instanceId);

    windowStage.loadContent(REMOTE_CONTROL_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立遥控器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立遥控器页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  onWindowStageDestroy(): void {
    this.windowStage = null;
    RemoteControlAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立遥控器窗口销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    logger.lifecycle(TAG, 'onForeground', `独立遥控器进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立遥控器进入后台: instanceId=${this.instanceId}`);
  }

  onDestroy(): void {
    RemoteControlAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立遥控器结束: instanceId=${this.instanceId}`);
  }

  private resolveInstanceId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return RemoteControlAbilityParamStore.getInstance().getActiveInstanceId();
    }
    const typedParams = params as RemoteControlAbilityWantParameters;
    const rawValue = typedParams.remoteControlAbilityInstanceId;
    return rawValue ? String(rawValue) : RemoteControlAbilityParamStore.getInstance().getActiveInstanceId();
  }

  private refreshWindowPayload(source: string): void {
    if (!this.windowStage) {
      return;
    }
    const params: ContinuationTriggeredPayload | null =
      RemoteControlAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(this.windowStage);
    RemoteControlAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, params);
    this.applyInstanceTitle(this.windowStage, params);
    logger.info(TAG, `独立遥控器窗口参数已刷新: source=${source}, instanceId=${this.instanceId}, windowId=${windowId}`);
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立遥控器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立遥控器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: ContinuationTriggeredPayload | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立遥控器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立遥控器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立遥控器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立遥控器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立遥控器主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: ContinuationTriggeredPayload | null): string {
    if (params && params.bookId.length > 0) {
      return this.truncateInstanceTitle(`${params.bookId}${REMOTE_CONTROL_TITLE_SUFFIX}`);
    }
    return DEFAULT_REMOTE_CONTROL_TITLE;
  }

  private truncateInstanceTitle(title: string): string {
    if (title.length <= MAX_REMOTE_CONTROL_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_REMOTE_CONTROL_TITLE_LENGTH)}...`;
  }
}
