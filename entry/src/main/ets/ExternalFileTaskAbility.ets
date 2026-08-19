import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataInitializer } from './Framework/Initialization/DataInitializer';
import { SettingsManager } from './Framework/Managers/SettingsManager';
import {
  EXTERNAL_FILE_TASK_ABILITY_INSTANCE_ID_KEY,
  EXTERNAL_FILE_TASK_ABILITY_PAGE
} from './Framework/ExternalFile/ExternalFileTaskAbilityConstants';
import { ExternalFileTaskParamStore } from './Framework/ExternalFile/ExternalFileTaskParamStore';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskKind,
  ExternalFileTaskParams
} from './Framework/ExternalFile/ExternalFileTaskTypes';

const TAG: string = 'ExternalFileTaskAbility';
const DEFAULT_TASK_TITLE: string = '外部文件任务';
const MAX_TASK_TITLE_LENGTH: number = 24;

interface ExternalFileTaskAbilityWantParameters {
  externalFileTaskAbilityInstanceId?: string;
  externalFileTaskAbilityParamsJson?: string;
}

export default class ExternalFileTaskAbility extends UIAbility {
  private instanceId: string = '';
  private params: ExternalFileTaskParams | null = null;
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.restoreLaunchPayload(want, 'create');
    logger.lifecycle(TAG, 'onCreate', `外部文件独立任务实例创建: instanceId=${this.instanceId}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const previousInstanceId = this.instanceId;
    this.restoreLaunchPayload(want, 'new_want');
    this.refreshWindowPayload('new_want');
    if (previousInstanceId.length > 0 && previousInstanceId !== this.instanceId) {
      ExternalFileTaskParamStore.getInstance().remove(previousInstanceId);
    }
    logger.lifecycle(TAG, 'onNewWant', `外部文件独立任务接收新参数: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    const windowId = this.resolveMainWindowId(windowStage);
    ExternalFileTaskParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, this.params);

    if (!this.params) {
      logger.warn(TAG, `外部文件独立任务参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, this.params);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(EXTERNAL_FILE_TASK_ABILITY_INSTANCE_ID_KEY, this.instanceId);

    void this.prepareFeatureGateAndLoadContent(windowStage, localStorage);
  }

  /**
   * An external file may launch this Ability without first bringing the entry
   * Ability to foreground.  In that path AppStorage has not yet been hydrated
   * from persisted settings, which would incorrectly hide the book-source
   * choice from a user who already enabled it.  Synchronize settings before
   * constructing the page so its StorageLink observes the persisted value on
   * its first render.
   */
  private async prepareFeatureGateAndLoadContent(
    windowStage: window.WindowStage,
    localStorage: LocalStorage
  ): Promise<void> {
    try {
      await DataInitializer.getInstance().initialize(this.context);
      const settingsManager = SettingsManager.getInstance();
      await settingsManager.initialize();
      settingsManager.syncToAppStorage();
      logger.info(TAG, '外部文件任务已同步持久化功能开关');
    } catch (error) {
      // Do not leave an external-file task on a blank window when optional
      // settings hydration fails. The page retains its explicit fallback
      // surface and the failure remains visible in the ability log.
      logger.warn(TAG, `外部文件任务同步功能开关失败: ${String(error)}`);
    }

    windowStage.loadContent(EXTERNAL_FILE_TASK_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载外部文件独立任务页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `外部文件独立任务页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  onWindowStageDestroy(): void {
    this.windowStage = null;
    ExternalFileTaskParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `外部文件独立任务窗口销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    logger.lifecycle(TAG, 'onForeground', `外部文件独立任务进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `外部文件独立任务进入后台: instanceId=${this.instanceId}`);
  }

  onDestroy(): void {
    ExternalFileTaskParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `外部文件独立任务结束: instanceId=${this.instanceId}`);
  }

  private restoreLaunchPayload(want: Want, source: string): void {
    const typedParams = this.resolveWantParameters(want);
    const resolvedInstanceId = typedParams ? typedParams.externalFileTaskAbilityInstanceId ?? '' : '';
    this.instanceId = resolvedInstanceId.length > 0
      ? resolvedInstanceId
      : ExternalFileTaskParamStore.getInstance().getActiveInstanceId();
    this.params = this.resolveTaskParams(typedParams);
    if (this.params && this.instanceId.length > 0) {
      ExternalFileTaskParamStore.getInstance().replaceParams(this.instanceId, this.params);
    }
    logger.info(TAG, `外部文件独立任务参数已恢复: source=${source}, instanceId=${this.instanceId}, hasParams=${this.params !== null}`);
  }

  private resolveWantParameters(want: Want): ExternalFileTaskAbilityWantParameters | null {
    const parameters = want.parameters;
    if (!parameters) {
      return null;
    }
    return parameters as ExternalFileTaskAbilityWantParameters;
  }

  private resolveTaskParams(typedParams: ExternalFileTaskAbilityWantParameters | null): ExternalFileTaskParams | null {
    const store = ExternalFileTaskParamStore.getInstance();
    if (this.instanceId.length > 0) {
      const storedParams = store.getParams(this.instanceId);
      if (storedParams) {
        return storedParams;
      }
    }
    if (!typedParams) {
      return null;
    }
    const json = typedParams.externalFileTaskAbilityParamsJson ?? '';
    if (json.length <= 0) {
      return null;
    }
    const restoredParams = ExternalFileTaskFactory.deserialize(json);
    if (restoredParams && this.instanceId.length > 0) {
      restoredParams.taskInstanceId = this.instanceId;
    }
    return restoredParams;
  }

  private refreshWindowPayload(source: string): void {
    if (!this.windowStage) {
      return;
    }
    const windowId = this.resolveMainWindowId(this.windowStage);
    ExternalFileTaskParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, this.params);
    this.applyInstanceTitle(this.windowStage, this.params);
    logger.info(TAG, `外部文件独立任务窗口参数已刷新: source=${source}, instanceId=${this.instanceId}, windowId=${windowId}`);
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `外部文件独立任务窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取外部文件独立任务窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: ExternalFileTaskParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `外部文件独立任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置外部文件独立任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `外部文件独立任务窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置外部文件独立任务窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取外部文件独立任务主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: ExternalFileTaskParams | null): string {
    if (!params) {
      return DEFAULT_TASK_TITLE;
    }
    const titleHint = params.titleHint.trim();
    if (titleHint.length > 0) {
      return this.truncateTitle(titleHint);
    }
    const fileName = ExternalFileTaskFactory.resolveDisplayName(params);
    const suffix = this.resolveTaskSuffix(params.kind);
    if (fileName.length > 0) {
      return this.truncateTitle(`${fileName}${suffix}`);
    }
    return this.resolveFallbackTitle(params.kind);
  }

  private resolveTaskSuffix(kind: ExternalFileTaskKind): string {
    switch (kind) {
      case ExternalFileTaskKind.BACKUP:
        return '恢复';
      case ExternalFileTaskKind.CODE:
        return '编辑';
      case ExternalFileTaskKind.AVIF:
      case ExternalFileTaskKind.IMAGE:
        return '预览';
      default:
        return '导入';
    }
  }

  private resolveFallbackTitle(kind: ExternalFileTaskKind): string {
    switch (kind) {
      case ExternalFileTaskKind.BACKUP:
        return '备份恢复';
      case ExternalFileTaskKind.CODE:
        return '文件编辑';
      case ExternalFileTaskKind.AVIF:
      case ExternalFileTaskKind.IMAGE:
        return '图片预览';
      default:
        return DEFAULT_TASK_TITLE;
    }
  }

  private truncateTitle(title: string): string {
    if (title.length <= MAX_TASK_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_TASK_TITLE_LENGTH)}...`;
  }
}
