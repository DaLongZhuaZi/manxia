import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import { NovelReaderPageParams } from './pages/NovelBookshelfPage';
import {
  NOVEL_READER_ABILITY_INSTANCE_ID_KEY,
  NOVEL_READER_ABILITY_PAGE
} from './Framework/Reader/MangaReaderAbilityConstants';
import { NovelReaderAbilityParamStore } from './Framework/Reader/NovelReaderAbilityParamStore';
import { ReaderAbilityWindowLifecycleController } from './Framework/Reader/ReaderAbilityWindowLifecycleController';

const TAG: string = 'NovelReaderAbility';
const DEFAULT_READER_INSTANCE_TITLE: string = '小说阅读器';
const MAX_READER_INSTANCE_TITLE_LENGTH: number = 18;

interface NovelReaderAbilityWantParameters {
  novelReaderAbilityInstanceId?: string;
}

export default class NovelReaderAbility extends UIAbility {
  private instanceId: string = '';
  private windowLifecycleController: ReaderAbilityWindowLifecycleController | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立小说阅读器实例创建: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const readerParams: NovelReaderPageParams | null = NovelReaderAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    NovelReaderAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, readerParams);

    if (!readerParams) {
      logger.error(TAG, `独立小说阅读器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, readerParams);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(NOVEL_READER_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    this.windowLifecycleController = new ReaderAbilityWindowLifecycleController(TAG, this.instanceId, localStorage);
    this.windowLifecycleController.attach(windowStage);

    windowStage.loadContent(NOVEL_READER_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立小说阅读器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立小说阅读器页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  onWindowStageDestroy(): void {
    this.detachWindowLifecycleController();
    NovelReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立小说阅读器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityForeground();
    }
    logger.lifecycle(TAG, 'onForeground', `独立小说阅读器实例进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立小说阅读器实例进入后台: instanceId=${this.instanceId}`);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityBackground();
    }
  }

  onDestroy(): void {
    this.detachWindowLifecycleController();
    NovelReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立小说阅读器实例结束: instanceId=${this.instanceId}`);
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
    const typedParams = params as NovelReaderAbilityWantParameters;
    const rawValue = typedParams.novelReaderAbilityInstanceId;
    return rawValue ? String(rawValue) : '';
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立小说阅读器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立小说阅读器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: NovelReaderPageParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立小说阅读器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立小说阅读器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立小说阅读器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立小说阅读器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立小说阅读器主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: NovelReaderPageParams | null): string {
    if (params) {
      const explicitTitle = params.readerTitle ? params.readerTitle.trim() : '';
      if (explicitTitle.length > 0) {
        return this.truncateInstanceTitle(explicitTitle);
      }
      const bookName = params.bookName ? params.bookName.trim() : '';
      if (bookName.length > 0) {
        return this.truncateInstanceTitle(bookName);
      }
    }
    return DEFAULT_READER_INSTANCE_TITLE;
  }

  private truncateInstanceTitle(title: string): string {
    if (title.length <= MAX_READER_INSTANCE_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_READER_INSTANCE_TITLE_LENGTH)}...`;
  }
}
