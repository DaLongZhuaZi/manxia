import { AbilityConstant, UIAbility, Want, common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { continuationStateHelper } from './Framework/Distributed/ContinuationStateHelper';
import { EBookReaderParams } from './pages/EBookReaderRouteTypes';
import {
  EBOOK_READER_ABILITY_INSTANCE_ID_KEY,
  EBOOK_READER_ABILITY_PAGE
} from 'manxia_reader_ui/src/main/ets/Framework/Reader/MangaReaderAbilityConstants';
import { EBookReaderAbilityParamStore } from './Framework/Reader/EBookReaderAbilityParamStore';
import { ReaderAbilityWindowLifecycleController } from 'manxia_reader_ui/src/main/ets/Framework/Reader/ReaderAbilityWindowLifecycleController';
import { ContinuationBootstrap } from './Framework/Initialization/ContinuationBootstrap';

const TAG: string = 'EBookReaderAbility';
const DEFAULT_READER_INSTANCE_TITLE: string = '电子书阅读器';
const MAX_READER_INSTANCE_TITLE_LENGTH: number = 18;

interface EBookReaderAbilityWantParameters {
  eBookReaderAbilityInstanceId?: string;
}

export default class EBookReaderAbility extends UIAbility {
  private instanceId: string = '';
  private windowLifecycleController: ReaderAbilityWindowLifecycleController | null = null;
  /** 跨端接续恢复使用的 LocalStorage（restoreWindowStage 传入，onWindowStageRestore 中随 loadContent 传递） */
  private continuationWindowStorage: LocalStorage = new LocalStorage();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // [修复] 自举全局依赖：接续冷启动时进程内可能没有 EntryAbility，
    // GlobalContext 与数据库均未初始化，落地页面解析 bookId 会失败（“电子书不存在”）。
    // 幂等：正常应用内打开时 EntryAbility 已完成初始化，此处立即返回。
    ContinuationBootstrap.getInstance().ensureReady(this.context)
      .then((): void => {
        logger.info(TAG, '独立电子书阅读器全局依赖已就绪（GlobalContext + 数据库）');
      })
      .catch((error: Error): void => {
        logger.warn(TAG, `独立电子书阅读器全局依赖初始化失败: ${String(error)}`);
      });
    // [修复] 目标端接续启动：恢复接续状态（立即入会+权限确保）后直接承载接续阅读。
    // 实证：接续启动的 Ability 若在 onCreate 内同步 startAbility 转交，
    // 启动请求会被系统吞掉且本 Ability 拿不到窗口舞台（目标端白屏、点击即退的根因）；
    // 改为直接注册书籍参数并走正常窗口加载流程，由 EBookReaderPage 应用接续快照。
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      logger.lifecycle(TAG, 'onCreate', '收到跨端接续启动：恢复状态并直接承载接续阅读');
      const continuationParams = this.buildContinuationReaderParams(want);
      if (continuationParams) {
        this.instanceId = EBookReaderAbilityParamStore.getInstance().register(continuationParams);
        logger.info(TAG, `接续启动已注册阅读参数: instanceId=${this.instanceId}, bookId=${continuationParams.bookId}`);
      } else {
        this.instanceId = `ebook_continuation_${Date.now()}`;
        logger.warn(TAG, `接续启动缺少 bookId，注册空实例占位: instanceId=${this.instanceId}`);
      }
      continuationStateHelper.restoreContinuationState(want, this.context);
      // [官方文档修复] 接续落地时系统不会回调 onWindowStageCreate，而是回调 onWindowStageRestore；
      // 必须在 onCreate 中同步调用 restoreWindowStage 触发该回调（异步调用会导致页面加载失败）
      this.prepareContinuationWindowStage();
      return;
    }
    this.instanceId = this.resolveInstanceId(want);
    logger.lifecycle(TAG, 'onCreate', `独立电子书阅读器实例创建: instanceId=${this.instanceId}`);
  }

  /**
   * 从接续 Want 构建阅读参数（接续快照由 EBookReaderPage 从 AppStorage continuation* 标志消费）
   */
  private buildContinuationReaderParams(want: Want): EBookReaderParams | null {
    const params = want.parameters;
    if (!params) {
      return null;
    }
    const rawBookId = params['bookId'] as string;
    const bookId = rawBookId ? String(rawBookId).trim() : '';
    if (bookId.length <= 0) {
      return null;
    }
    const readerParams: EBookReaderParams = {
      bookId: bookId
    };
    return readerParams;
  }

  /**
   * [修复] 源端接续打包：阅读器前台时由本 Ability 打包阅读状态（快照 + 分布式会话）
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.info(TAG, 'onContinue: 电子书阅读器开始打包接续状态');
    return continuationStateHelper.packContinuationWant(wantParam, this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    const readerParams: EBookReaderParams | null = EBookReaderAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    EBookReaderAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, readerParams);

    if (!readerParams) {
      logger.error(TAG, `独立电子书阅读器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, readerParams);
    this.applyReaderWindowImmersive(windowStage);

    const localStorage = new LocalStorage();
    localStorage.setOrCreate<string>(EBOOK_READER_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    this.windowLifecycleController = new ReaderAbilityWindowLifecycleController(TAG, this.instanceId, localStorage);
    this.windowLifecycleController.attach(windowStage);

    windowStage.loadContent(EBOOK_READER_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `加载独立电子书阅读器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `独立电子书阅读器页面加载成功: instanceId=${this.instanceId}`);
    });
  }

  /**
   * [官方文档修复] 跨端接续落地的窗口恢复回调：
   * 接续启动时（冷启动）系统不会回调 onWindowStageCreate，而是回调本方法；
   * 在此手动 loadContent 加载阅读器页面（与 onWindowStageCreate 一致的初始化流程），
   * 由 EBookReaderPage 从 AppStorage continuation* 标志消费接续快照。
   */
  onWindowStageRestore(windowStage: window.WindowStage): void {
    logger.lifecycle(TAG, 'onWindowStageRestore', '跨端接续落地：手动加载独立电子书阅读器页面');
    const readerParams: EBookReaderParams | null = EBookReaderAbilityParamStore.getInstance().getParams(this.instanceId);
    const windowId = this.resolveMainWindowId(windowStage);
    EBookReaderAbilityParamStore.getInstance().bindWindowPayload(windowId, this.instanceId, readerParams);

    if (!readerParams) {
      logger.error(TAG, `接续落地独立电子书阅读器参数缺失: instanceId=${this.instanceId}`);
    }

    this.applyInstanceTitle(windowStage, readerParams);
    this.applyReaderWindowImmersive(windowStage);

    const localStorage = this.continuationWindowStorage;
    localStorage.setOrCreate<string>(EBOOK_READER_ABILITY_INSTANCE_ID_KEY, this.instanceId);
    this.windowLifecycleController = new ReaderAbilityWindowLifecycleController(TAG, this.instanceId, localStorage);
    this.windowLifecycleController.attach(windowStage);

    windowStage.loadContent(EBOOK_READER_ABILITY_PAGE, localStorage, (err) => {
      if (err && err.code !== 0) {
        logger.error(TAG, `接续落地加载独立电子书阅读器页面失败: ${JSON.stringify(err)}`);
        return;
      }
      logger.info(TAG, `接续落地独立电子书阅读器页面加载成功: instanceId=${this.instanceId}`);
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
    EBookReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onWindowStageDestroy', `独立电子书阅读器实例销毁: instanceId=${this.instanceId}`);
  }

  onForeground(): void {
    // [修复] 激活接续入口（入口按场景显示；权限在触发接续时校验，此处异步确保权限就绪）
    continuationStateHelper.activateMissionContinueEntry(this.context);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityForeground();
    }
    logger.lifecycle(TAG, 'onForeground', `独立电子书阅读器实例进入前台: instanceId=${this.instanceId}`);
  }

  onBackground(): void {
    logger.lifecycle(TAG, 'onBackground', `独立电子书阅读器实例进入后台: instanceId=${this.instanceId}`);
    // [修复] 离开前台时关闭接续入口
    continuationStateHelper.setMissionContinueState(this.context, false);
    if (this.windowLifecycleController) {
      this.windowLifecycleController.markAbilityBackground();
    }
  }

  onDestroy(): void {
    this.detachWindowLifecycleController();
    EBookReaderAbilityParamStore.getInstance().remove(this.instanceId);
    logger.lifecycle(TAG, 'onDestroy', `独立电子书阅读器实例结束: instanceId=${this.instanceId}`);
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
    const typedParams = params as EBookReaderAbilityWantParameters;
    const rawValue = typedParams.eBookReaderAbilityInstanceId;
    return rawValue ? String(rawValue) : '';
  }

  private resolveMainWindowId(windowStage: window.WindowStage): number {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      const properties = mainWindow.getWindowProperties();
      logger.info(TAG, `独立电子书阅读器窗口ID已绑定: instanceId=${this.instanceId}, windowId=${properties.id}`);
      return properties.id;
    } catch (error) {
      logger.warn(TAG, `获取独立电子书阅读器窗口ID失败: ${String(error)}`);
      return -1;
    }
  }

  private applyInstanceTitle(windowStage: window.WindowStage, params: EBookReaderParams | null): void {
    const title = this.resolveInstanceTitle(params);
    this.context.setMissionLabel(title).then((): void => {
      logger.info(TAG, `独立电子书阅读器任务标题已设置: ${title}`);
    }).catch((error: Object | string | number | boolean): void => {
      logger.warn(TAG, `设置独立电子书阅读器任务标题失败: ${String(error)}`);
    });

    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowTitle(title).then((): void => {
        logger.info(TAG, `独立电子书阅读器窗口标题已设置: ${title}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `设置独立电子书阅读器窗口标题失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `获取独立电子书阅读器主窗口失败: ${String(error)}`);
    }
  }

  private applyReaderWindowImmersive(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true).then((): void => {
        logger.info(TAG, `独立电子书阅读器窗口已启用全屏布局: instanceId=${this.instanceId}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `独立电子书阅读器设置全屏布局失败: ${String(error)}`);
      });
      mainWindow.setWindowSystemBarEnable([]).then((): void => {
        logger.info(TAG, `独立电子书阅读器系统栏已隐藏: instanceId=${this.instanceId}`);
      }).catch((error: Object | string | number | boolean): void => {
        logger.warn(TAG, `独立电子书阅读器隐藏系统栏失败: ${String(error)}`);
      });
    } catch (error) {
      logger.warn(TAG, `独立电子书阅读器应用沉浸式窗口失败: ${String(error)}`);
    }
  }

  private resolveInstanceTitle(params: EBookReaderParams | null): string {
    if (params) {
      const explicitTitle = params.readerTitle ? params.readerTitle.trim() : '';
      if (explicitTitle.length > 0) {
        return this.truncateInstanceTitle(explicitTitle);
      }
      const bookId = params.bookId ? params.bookId.trim() : '';
      if (bookId.length > 0) {
        return this.truncateInstanceTitle(bookId);
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
