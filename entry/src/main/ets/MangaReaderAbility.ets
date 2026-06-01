import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import { MangaReaderPageParams } from './pages/MangaReaderPage';
import {
  MANGA_READER_ABILITY_INSTANCE_ID_KEY,
  MANGA_READER_ABILITY_PAGE,
  MANGA_READER_ABILITY_PARAMS_KEY
} from './Framework/Reader/MangaReaderAbilityConstants';
import { MangaReaderAbilityParamStore } from './Framework/Reader/MangaReaderAbilityParamStore';
import { ReaderAbilityWindowLifecycleController } from './Framework/Reader/ReaderAbilityWindowLifecycleController';

const TAG: string = 'MangaReaderAbility';
const DEFAULT_READER_INSTANCE_TITLE: string = '漫画阅读器';
const MAX_READER_INSTANCE_TITLE_LENGTH: number = 18;

interface MangaReaderAbilityWantParameters {
  mangaReaderAbilityInstanceId?: string;
}

export default class MangaReaderAbility extends UIAbility {
  private instanceId: string = '';
  private windowLifecycleController: ReaderAbilityWindowLifecycleController | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立漫画阅读器实例创建: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const readerParams: MangaReaderPageParams | null = MangaReaderAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    MangaReaderAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, readerParams);

    if (!readerParams) {
      logger.error(TAG, `独立漫画阅读器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, readerParams);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(MANGA_READER_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    localStorage.setOrCreate<MangaReaderPageParams | null>(MANGA_READER_ABILITY_PARAMS_KEY, readerParams);
    this.windowLifecycleController = new ReaderAbilityWindowLifecycleController(TAG, this.instanceId, localStorage);
    this.windowLifecycleController.attach(windowStage);

    windowStage.loadContent(MANGA_READER_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立漫画阅读器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立漫画阅读器页面加载成功: instanceId=${this.instanceId}, key=${MANGA_READER_ABILITY_PARAMS_KEY}`);
    });
  }

  onWindowStageDestroy(): void {
    this.detachWindowLifecycleController();
    MangaReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立漫画阅读器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityForeground();
    }
    logger.lifecycle(TAG, 'onForeground', `独立漫画阅读器实例进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立漫画阅读器实例进入后台: instanceId=${this.instanceId}`);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityBackground();
    }
  }

  onDestroy(): void {
    this.detachWindowLifecycleController();
    MangaReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立漫画阅读器实例结束: instanceId=${this.instanceId}`);
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
    const typedParams = params as MangaReaderAbilityWantParameters;
    const rawValue = typedParams.mangaReaderAbilityInstanceId;
    return rawValue ? String(rawValue) : '';
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立漫画阅读器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立漫画阅读器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: MangaReaderPageParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立漫画阅读器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立漫画阅读器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立漫画阅读器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立漫画阅读器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立漫画阅读器主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: MangaReaderPageParams | null): string {
    if (params) {
      const explicitTitle = params.readerTitle ? params.readerTitle.trim() : '';
      if (explicitTitle.length > 0) {
        return this.truncateInstanceTitle(explicitTitle);
      }
      const mangaTitle = params.manga?.title ? params.manga.title.trim() : '';
      if (mangaTitle.length > 0) {
        return this.truncateInstanceTitle(mangaTitle);
      }
      const mangaId = params.mangaId ? params.mangaId.trim() : '';
      if (mangaId.length > 0) {
        return this.truncateInstanceTitle(mangaId);
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
