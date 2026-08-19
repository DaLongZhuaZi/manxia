import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { continuationStateHelper } from './Framework/Distributed/ContinuationStateHelper';
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
    logger.lifecycle(TAG, 'onCreate', `独立小说阅读器实例创建: instanceId=${this.instanceId}`);
  }

  /**
   * [修复] 源端接续打包：阅读器前台时由本 Ability 打包阅读状态（快照 + 分布式会话）
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.info(TAG, 'onContinue: 小说阅读器开始打包接续状态');
    return continuationStateHelper.packContinuationWant(wantParam, this.context);
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
    this.detachWindowLifecycleController();
    NovelReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立小说阅读器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    // [修复] 激活接续入口（入口按场景显示；权限在触发接续时校验，此处异步确保权限就绪）
    continuationStateHelper.activateMissionContinueEntry(this.context);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityForeground();
    }
    logger.lifecycle(TAG, 'onForeground', `独立小说阅读器实例进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立小说阅读器实例进入后台: instanceId=${this.instanceId}`);
    // [修复] 离开前台时关闭接续入口
    continuationStateHelper.setMissionContinueState(this.context, false);
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
