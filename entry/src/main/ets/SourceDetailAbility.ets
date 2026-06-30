import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import type { SourceDetailParams } from './pages/SourceDetailPage';
import {
  SOURCE_DETAIL_ABILITY_INSTANCE_ID_KEY,
  SOURCE_DETAIL_ABILITY_PAGE,
  SOURCE_DETAIL_ABILITY_PARAMS_KEY
} from './Framework/Source/SourceDetailAbilityConstants';
import { SourceDetailAbilityParamStore } from './Framework/Source/SourceDetailAbilityParamStore';

const TAG: string = 'SourceDetailAbility';
const DEFAULT_SOURCE_DETAIL_TITLE: string = '图源详情';
const MAX_SOURCE_DETAIL_TITLE_LENGTH: number = 18;

interface SourceDetailAbilityWantParameters {
  sourceDetailAbilityInstanceId?: string;
}

export default class SourceDetailAbility extends UIAbility {
  private instanceId: string = '';
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立图源详情实例创建: instanceId=${this.instanceId}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const previousInstanceId = this.instanceId;
    this.instanceId = this.resolveInstanceId(want);
    this.refreshWindowPayload('new_want');
    if (previousInstanceId.length > 0 && previousInstanceId !== this.instanceId) {
      SourceDetailAbilityParamStore.getInstance().remove(previousInstanceId);
    }
    logger.lifecycle(TAG, 'onNewWant', `独立图源详情接收新参数: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    const params: SourceDetailParams | null = SourceDetailAbilityParamStore.getInstance().getParams(this.instanceId);
    const mainWindow: window.Window | null = this.resolveMainWindow(windowStage);
    const windowId = this.resolveMainWindowId(mainWindow);
    SourceDetailAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, params, mainWindow);

    if (!params) {
      logger.error(TAG, `独立图源详情参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, params);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(SOURCE_DETAIL_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    localStorage.setOrCreate<SourceDetailParams | null>(SOURCE_DETAIL_ABILITY_PARAMS_KEY, params);

    windowStage.loadContent(SOURCE_DETAIL_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立图源详情页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立图源详情页面加载成功: instanceId=${this.instanceId}, key=${SOURCE_DETAIL_ABILITY_PARAMS_KEY}`);
    });
  }

  onWindowStageDestroy(): void {
    this.windowStage = null;
    SourceDetailAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立图源详情窗口销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    logger.lifecycle(TAG, 'onForeground', `独立图源详情进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立图源详情进入后台: instanceId=${this.instanceId}`);
  }

  onDestroy(): void {
    this.windowStage = null;
    SourceDetailAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立图源详情结束: instanceId=${this.instanceId}`);
  }

  private refreshWindowPayload(source: string): void {
    if (!this.windowStage) {
      return;
    }
    const params: SourceDetailParams | null = SourceDetailAbilityParamStore.getInstance().getParams(this.instanceId);
    const mainWindow: window.Window | null = this.resolveMainWindow(this.windowStage);
    const windowId = this.resolveMainWindowId(mainWindow);
    SourceDetailAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, params, mainWindow);
    this.applyInstanceTitle(this.windowStage, params);
    logger.info(TAG, `独立图源详情窗口参数已刷新: source=${source}, instanceId=${this.instanceId}, windowId=${windowId}`);
  }

  private resolveInstanceId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return this.instanceId;
    }
    const typedParams = params as SourceDetailAbilityWantParameters;
    const rawValue = typedParams.sourceDetailAbilityInstanceId;
    return rawValue ? String(rawValue) : this.instanceId;
  }

  private resolveMainWindow(windowStage: window.WindowStage): window.Window | null {
    try {
      return windowStage.getMainWindowSync();
    } catch (error) {
      logger.warn(TAG, `获取独立图源详情主窗口失败: ${String(error)}`);
      return null;
    }
  }

  private resolveMainWindowId(mainWindow: window.Window | null): number {
    if (!mainWindow) {
      return -1;
    }
    try {
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立图源详情窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立图源详情窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: SourceDetailParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立图源详情任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立图源详情任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立图源详情窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立图源详情窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立图源详情主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: SourceDetailParams | null): string {
    if (params) {
      const sourceName = params.sourceName ? params.sourceName.trim() : '';
      if (sourceName.length > 0) {
        return this.truncateInstanceTitle(sourceName);
      }
      if (params.sourceId > 0) {
        return this.truncateInstanceTitle(`图源${params.sourceId}`);
      }
    }
    return DEFAULT_SOURCE_DETAIL_TITLE;
  }

  private truncateInstanceTitle(title: string): string {
    if (title.length <= MAX_SOURCE_DETAIL_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_SOURCE_DETAIL_TITLE_LENGTH)}...`;
  }
}
