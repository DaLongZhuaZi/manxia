import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import { ReaderAbilityWindowLifecycleController } from './Framework/Reader/ReaderAbilityWindowLifecycleController';
import { FileEditorOpenParams } from './Framework/Editor/FileEditorService';
import {
  FILE_EDITOR_ABILITY_INSTANCE_ID_KEY,
  FILE_EDITOR_ABILITY_PAGE
} from './Framework/Editor/FileEditorAbilityConstants';
import { FileEditorAbilityParamStore } from './Framework/Editor/FileEditorAbilityParamStore';

const TAG: string = 'FileEditorAbility';
const DEFAULT_EDITOR_INSTANCE_TITLE: string = '文件编辑器';
const MAX_EDITOR_INSTANCE_TITLE_LENGTH: number = 18;

interface FileEditorAbilityWantParameters {
  fileEditorAbilityInstanceId?: string;
}

export default class FileEditorAbility extends UIAbility {
  private instanceId: string = '';
  private windowLifecycleController: ReaderAbilityWindowLifecycleController | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立文件编辑器实例创建: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const editorParams: FileEditorOpenParams | null = FileEditorAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    FileEditorAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, editorParams);

    if (!editorParams) {
      logger.error(TAG, `独立文件编辑器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, editorParams);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(FILE_EDITOR_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    this.windowLifecycleController = new ReaderAbilityWindowLifecycleController(TAG, this.instanceId, localStorage);
    this.windowLifecycleController.attach(windowStage);

    windowStage.loadContent(FILE_EDITOR_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立文件编辑器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立文件编辑器页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  onWindowStageDestroy(): void {
    this.detachWindowLifecycleController();
    FileEditorAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立文件编辑器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityForeground();
    }
    logger.lifecycle(TAG, 'onForeground', `独立文件编辑器实例进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立文件编辑器实例进入后台: instanceId=${this.instanceId}`);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityBackground();
    }
  }

  onDestroy(): void {
    this.detachWindowLifecycleController();
    FileEditorAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立文件编辑器实例结束: instanceId=${this.instanceId}`);
  }

  private detachWindowLifecycleController(): void {
    if (!this.windowLifecycleController) {
      return;
    }
    this.windowLifecycleController.detach();
    this.windowLifecycleController = null;
  }

  private resolveInstanceId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return '';
    }
    const typedParams = params as FileEditorAbilityWantParameters;
    const rawValue = typedParams.fileEditorAbilityInstanceId;
    return rawValue ? String(rawValue) : '';
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立文件编辑器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立文件编辑器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: FileEditorOpenParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立文件编辑器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立文件编辑器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立文件编辑器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立文件编辑器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立文件编辑器主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: FileEditorOpenParams | null): string {
    if (params) {
      const title = params.title ? params.title.trim() : '';
      if (title.length > 0) {
        return this.truncateInstanceTitle(title);
      }
      const filePath = params.filePath ? params.filePath.trim() : '';
      if (filePath.length > 0) {
        return this.truncateInstanceTitle(this.getNameFromPath(filePath));
      }
    }
    return DEFAULT_EDITOR_INSTANCE_TITLE;
  }

  private getNameFromPath(path: string): string {
    const normalized = path.replace(/\\/g, '/');
    const parts = normalized.split('/');
    const last = parts.length > 0 ? parts[parts.length - 1] : '';
    return last.length > 0 ? decodeURIComponent(last) : DEFAULT_EDITOR_INSTANCE_TITLE;
  }

  private truncateInstanceTitle(title: string): string {
    if (title.length <= MAX_EDITOR_INSTANCE_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_EDITOR_INSTANCE_TITLE_LENGTH)}...`;
  }
}
