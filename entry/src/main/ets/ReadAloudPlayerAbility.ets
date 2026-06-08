import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import {
  READ_ALOUD_PLAYER_ABILITY_INSTANCE_ID_KEY,
  READ_ALOUD_PLAYER_ABILITY_PAGE
} from './Framework/ReadAloud/ReadAloudPlayerAbilityConstants';
import {
  ReadAloudPlayerAbilityParams,
  ReadAloudPlayerAbilityParamStore
} from './Framework/ReadAloud/ReadAloudPlayerAbilityParamStore';
import { ReadAloudController } from './Framework/ReadAloud/ReadAloudController';
import { ReadAloudSessionContext } from './Framework/ReadAloud/ReadAloudTypes';
import {
  getNovelAudioReadAloudSessionManager,
  NovelAudioReadAloudSnapshot
} from './Framework/ReadAloud/NovelAudioReadAloudSessionManager';

const TAG: string = 'ReadAloudPlayerAbility';
const DEFAULT_PLAYER_INSTANCE_TITLE: string = '听书播放器';
const PLAYER_INSTANCE_TITLE_SUFFIX: string = '听书';
const MAX_PLAYER_INSTANCE_TITLE_LENGTH: number = 18;

interface ReadAloudPlayerAbilityWantParameters {
  readAloudPlayerAbilityInstanceId?: string;
}

export default class ReadAloudPlayerAbility extends UIAbility {
  private instanceId: string = '';
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立听书播放器实例创建: instanceId=${this.instanceId}`);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const previousInstanceId = this.instanceId;
    this.instanceId = this.resolveInstanceId(want);
    this.refreshWindowPayload('new_want');
    if (previousInstanceId.length > 0 && previousInstanceId !== this.instanceId) {
      ReadAloudPlayerAbilityParamStore.getInstance().remove(previousInstanceId);
    }
    logger.lifecycle(TAG, 'onNewWant', `独立听书播放器接收新参数: instanceId=${this.instanceId}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    const playerParams: ReadAloudPlayerAbilityParams | null =
      ReadAloudPlayerAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    ReadAloudPlayerAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, playerParams);

    if (!playerParams) {
      logger.warn(TAG, `独立听书播放器参数缺失，将打开当前会话: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, playerParams);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(READ_ALOUD_PLAYER_ABILITY_INSTANCE_ID_KEY, this.instanceId);

    windowStage.loadContent(READ_ALOUD_PLAYER_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立听书播放器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立听书播放器页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  onWindowStageDestroy(): void {
    this.windowStage = null;
    ReadAloudPlayerAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立听书播放器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    logger.lifecycle(TAG, 'onForeground', `独立听书播放器进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立听书播放器进入后台: instanceId=${this.instanceId}`);
  }

  onDestroy(): void {
    ReadAloudPlayerAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立听书播放器结束: instanceId=${this.instanceId}`);
  }

  private resolveInstanceId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return ReadAloudPlayerAbilityParamStore.getInstance().getActiveInstanceId();
    }
    const typedParams = params as ReadAloudPlayerAbilityWantParameters;
    const rawValue = typedParams.readAloudPlayerAbilityInstanceId;
    return rawValue ? String(rawValue) : ReadAloudPlayerAbilityParamStore.getInstance().getActiveInstanceId();
  }

  private refreshWindowPayload(source: string): void {
    if (!this.windowStage) {
      return;
    }
    const playerParams: ReadAloudPlayerAbilityParams | null =
      ReadAloudPlayerAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(this.windowStage);
    ReadAloudPlayerAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, playerParams);
    this.applyInstanceTitle(this.windowStage, playerParams);
    logger.info(TAG, `独立听书播放器窗口参数已刷新: source=${source}, instanceId=${this.instanceId}, windowId=${windowId}`);
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立听书播放器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立听书播放器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: ReadAloudPlayerAbilityParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立听书播放器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立听书播放器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立听书播放器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立听书播放器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立听书播放器主窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: ReadAloudPlayerAbilityParams | null): string {
    const contentName = this.resolveContentName(params);
    if (contentName.length > 0) {
      return this.truncateInstanceTitle(`${contentName}${PLAYER_INSTANCE_TITLE_SUFFIX}`);
    }
    return DEFAULT_PLAYER_INSTANCE_TITLE;
  }

  private resolveContentName(params: ReadAloudPlayerAbilityParams | null): string {
    if (params && params.launchParams) {
      const bookName = params.launchParams.bookName ? params.launchParams.bookName.trim() : '';
      if (bookName.length > 0) {
        return bookName;
      }
    }
    const audioSnapshot: NovelAudioReadAloudSnapshot = getNovelAudioReadAloudSessionManager().getSnapshot();
    if (audioSnapshot.hasSession) {
      const audioBookName = audioSnapshot.bookName ? audioSnapshot.bookName.trim() : '';
      if (audioBookName.length > 0) {
        return audioBookName;
      }
    }
    const readAloudContext: ReadAloudSessionContext | null = ReadAloudController.getInstance().getContextSnapshot();
    if (readAloudContext) {
      const bookTitle = readAloudContext.bookTitle ? readAloudContext.bookTitle.trim() : '';
      if (bookTitle.length > 0) {
        return bookTitle;
      }
    }
    return '';
  }

  private truncateInstanceTitle(title: string): string {
    if (title.length <= MAX_PLAYER_INSTANCE_TITLE_LENGTH) {
      return title;
    }
    return `${title.substring(0, MAX_PLAYER_INSTANCE_TITLE_LENGTH)}...`;
  }
}
