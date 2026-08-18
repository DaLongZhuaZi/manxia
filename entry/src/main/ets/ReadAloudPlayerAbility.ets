import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from './Utils/Logger';
import { continuationStateHelper, ContinuationPackSource } from './Framework/Distributed/ContinuationStateHelper';
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
  /** 目标端接续启动转交模式：加载"正在恢复"中转页，转交完成后由 ContinuationStateHelper 终止本 Ability */
  private continuationRedirectMode: boolean = false;
  /** 跨端接续恢复使用的 LocalStorage（restoreWindowStage 传入，onWindowStageRestore 中随 loadContent 传递） */
  private continuationWindowStorage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // [修复] 目标端接续启动：恢复接续状态（立即入会+权限确保）并转交 EntryAbility 统一处理接续导航
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      logger.lifecycle(TAG, 'onCreate', '收到跨端接续启动，恢复接续状态并转交入口 Ability');
      this.continuationRedirectMode = true;
      continuationStateHelper.restoreContinuationState(want, this.context);
      continuationStateHelper.redirectContinuationToEntryAbility(this.context);
      // [官方文档修复] 接续落地时系统不会回调 onWindowStageCreate，而是回调 onWindowStageRestore；
      // 必须在 onCreate 中同步调用 restoreWindowStage 触发该回调（异步调用会导致页面加载失败）
      this.prepareContinuationWindowStage();
      return;
    }
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立听书播放器实例创建: instanceId=${this.instanceId}`);
  }

  /**
   * [修复] 源端接续打包：听书前台时用当前听书会话快照打包接续状态
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.info(TAG, 'onContinue: 听书播放器开始打包接续状态');
    const source: ContinuationPackSource | null = this.buildContinuationPackSource();
    return continuationStateHelper.packContinuationWant(wantParam, this.context, source ?? undefined);
  }

  private buildContinuationPackSource(): ContinuationPackSource | null {
    const readAloudContext: ReadAloudSessionContext | null = ReadAloudController.getInstance().getContextSnapshot();
    if (readAloudContext && readAloudContext.bookId && readAloudContext.bookId.trim().length > 0) {
      logger.info(TAG, `onContinue: 使用阅读器听书会话快照, bookId=${readAloudContext.bookId}, chapterIndex=${readAloudContext.chapterIndex}, pageIndex=${readAloudContext.pageIndex}`);
      return {
        bookId: readAloudContext.bookId,
        chapterIndex: readAloudContext.chapterIndex >= 0 ? readAloudContext.chapterIndex : 0,
        pageIndex: readAloudContext.pageIndex >= 0 ? readAloudContext.pageIndex : 0,
        offset: readAloudContext.resumeCharIndex !== undefined && readAloudContext.resumeCharIndex >= 0
          ? readAloudContext.resumeCharIndex
          : 0,
        sourceType: 'novel',
        isLocal: false
      };
    }
    // 备用：音频小说会话快照
    const audioSnapshot: NovelAudioReadAloudSnapshot = getNovelAudioReadAloudSessionManager().getSnapshot();
    if (audioSnapshot.hasSession && audioSnapshot.bookId && audioSnapshot.bookId.trim().length > 0) {
      logger.info(TAG, `onContinue: 使用音频小说会话快照, bookId=${audioSnapshot.bookId}, chapterIndex=${audioSnapshot.chapterIndex}`);
      return {
        bookId: audioSnapshot.bookId,
        chapterIndex: audioSnapshot.chapterIndex >= 0 ? audioSnapshot.chapterIndex : 0,
        pageIndex: 0,
        offset: 0,
        sourceType: 'novel',
        isLocal: false
      };
    }
    logger.warn(TAG, 'onContinue: 当前无有效听书会话（阅读器会话与音频会话均不可用），拒绝接续流转');
    return null;
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
    // [修复] 接续转交模式：加载"正在恢复"中转页，转交完成后由 ContinuationStateHelper 终止本 Ability
    if (this.continuationRedirectMode) {
      const restoreLocalStorage = new LocalStorage();
      windowStage.loadContent('pages/ContinuationRestorePage', restoreLocalStorage, (err) => {
        if (err && err.code !== 0) {
          logger.error(TAG, `加载接续恢复中转页失败: ${JSON.stringify(err)}`);
          return;
        }
        logger.info(TAG, '接续恢复中转页加载成功（等待转交 EntryAbility 完成）');
      });
      return;
    }
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

  /**
   * [官方文档修复] 跨端接续落地的窗口恢复回调：
   * 接续启动时（冷启动）系统不会回调 onWindowStageCreate，而是回调本方法；
   * 接续转交模式下在此手动加载"正在恢复"中转页（与 onWindowStageCreate 的转交分支一致）。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    logger.lifecycle(TAG, 'onWindowStageRestore', '跨端接续落地：手动加载接续恢复中转页');
    windowStage.loadContent('pages/ContinuationRestorePage', this.continuationWindowStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `接续落地加载接续恢复中转页失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, '接续落地中转页加载成功（等待转交 EntryAbility 完成）');
    });
  }

  /**
   * [官方文档修复] 接续落地准备：必须同步调用 restoreWindowStage（异步调用会导致页面加载失败），
   * 同时按官方建议将目标端接续状态置为 ACTIVE 保证迁移连续性。
   */
  private prepareContinuationWindowStage(): void {
    try {
      this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE).then(() => {
        logger.info(TAG, '接续落地：目标端接续状态已置 ACTIVE');
      }).catch((error: Error) => {
        logger.warn(TAG, `接续落地 setMissionContinueState 失败: ${String(error)}`);
      });
      this.continuationWindowStorage = new LocalStorage();
      this.context.restoreWindowStage(this.continuationWindowStorage);
      logger.info(TAG, '接续落地：已同步调用 restoreWindowStage（等待 onWindowStageRestore）');
    } catch (error) {
      logger.error(TAG, `接续落地 restoreWindowStage 异常: ${String(error)}`);
    }
  }

  onWindowStageDestroy(): void {
    this.windowStage = null;
    ReadAloudPlayerAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立听书播放器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    // [修复] 激活接续入口（入口统一挂在入口 Ability mission 上）；
    // 同时注册接续状态来源提供器：接续入口迁移的是入口任务，onContinue 由 EntryAbility 触发，
    // 由本提供器提供听书会话最新快照
    continuationStateHelper.activateMissionContinueEntry(this.context);
    continuationStateHelper.setContinuationPackSourceProvider((): ContinuationPackSource | null => {
      return this.buildContinuationPackSource();
    });
    logger.lifecycle(TAG, 'onForeground', `独立听书播放器进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立听书播放器进入后台: instanceId=${this.instanceId}`);
    // [修复] 离开前台时关闭接续入口并清除接续状态来源提供器
    continuationStateHelper.setMissionContinueState(this.context, false);
    continuationStateHelper.setContinuationPackSourceProvider(null);
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
