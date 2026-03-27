/**
 * 后台长时任务辅助器
 * 统一管理 DATA_TRANSFER 后台长时任务的申请、续期与释放。
 *
 * 设计说明：
 * 1. 支持多个业务同时持有后台运行资格，避免一个业务结束时误停另一个业务。
 * 2. 使用 owner 作为持有者标识，谁申请谁释放。
 * 3. 保留自动续期逻辑，规避系统对长时间无流量任务的回收。
 */

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';

const TAG = 'BackgroundTaskHelper';
const AUTO_REFRESH_INTERVAL_MS = 8 * 60 * 1000;
const DEFAULT_OWNER = 'default_background_owner';
const UI_ABILITY_BACKGROUND_MODES: string[] = ['dataTransfer'];

export class BackgroundTaskHelper {
  /** 当前后台长时任务是否处于运行状态 */
  private static taskRunning: boolean = false;
  /** 自动续期定时器，-1 表示未启动 */
  private static refreshTimer: number = -1;
  /** 当前所有持有后台资格的业务标识 */
  private static activeOwners: Set<string> = new Set<string>();
  /** 当前可用于续期的 UIAbilityContext */
  private static currentContext: common.UIAbilityContext | null = null;

  /**
   * 申请 DATA_TRANSFER 后台长时任务
   * @param context UIAbility 上下文
   * @param owner 业务持有者标识，必须成对调用 start/stop
   */
  static async startDataTransferTask(
    context: common.UIAbilityContext,
    owner: string = DEFAULT_OWNER
  ): Promise<void> {
    const normalizedOwner = BackgroundTaskHelper.normalizeOwner(owner);
    if (BackgroundTaskHelper.activeOwners.has(normalizedOwner)) {
      BackgroundTaskHelper.currentContext = context;
      logger.info(
        TAG,
        `后台长时任务重复申请，沿用现有持有者：${normalizedOwner}，当前持有者数=${BackgroundTaskHelper.activeOwners.size}`
      );
      return;
    }

    BackgroundTaskHelper.activeOwners.add(normalizedOwner);
    BackgroundTaskHelper.currentContext = context;
    logger.info(
      TAG,
      `收到后台长时任务申请：持有者=${normalizedOwner}，当前持有者数=${BackgroundTaskHelper.activeOwners.size}`
    );

    if (BackgroundTaskHelper.taskRunning) {
      logger.info(TAG, `后台长时任务已在运行，本次仅登记持有者：${normalizedOwner}`);
      return;
    }

    const started = await BackgroundTaskHelper.requestBackgroundRunning(context);
    if (!started) {
      BackgroundTaskHelper.activeOwners.delete(normalizedOwner);
      if (BackgroundTaskHelper.activeOwners.size === 0) {
        BackgroundTaskHelper.currentContext = null;
      }
      logger.warn(TAG, `后台长时任务启动失败，已回滚持有者：${normalizedOwner}`);
    }
  }

  /**
   * 释放 DATA_TRANSFER 后台长时任务
   * @param context UIAbility 上下文
   * @param owner 业务持有者标识，必须与 start 时保持一致
   */
  static async stopDataTransferTask(
    context: common.UIAbilityContext,
    owner: string = DEFAULT_OWNER
  ): Promise<void> {
    const normalizedOwner = BackgroundTaskHelper.normalizeOwner(owner);
    const removed = BackgroundTaskHelper.activeOwners.delete(normalizedOwner);
    if (!removed) {
      logger.info(
        TAG,
        `忽略未注册的后台长时任务释放请求：持有者=${normalizedOwner}，可能尚未申请成功或已提前释放`
      );
      return;
    }

    BackgroundTaskHelper.currentContext = context;
    logger.info(
      TAG,
      `释放后台长时任务持有者：${normalizedOwner}，剩余持有者数=${BackgroundTaskHelper.activeOwners.size}`
    );

    if (BackgroundTaskHelper.activeOwners.size > 0) {
      logger.info(TAG, '仍有其他业务持有后台长时任务，保持后台运行');
      return;
    }

    BackgroundTaskHelper.stopAutoRefresh();

    if (!BackgroundTaskHelper.taskRunning) {
      BackgroundTaskHelper.currentContext = null;
      logger.info(TAG, '后台长时任务当前未运行，无需再次停止');
      return;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundTaskHelper.taskRunning = false;
      BackgroundTaskHelper.currentContext = null;
      logger.info(TAG, '后台长时任务已停止，所有持有者均已释放');
    } catch (error) {
      BackgroundTaskHelper.taskRunning = false;
      BackgroundTaskHelper.currentContext = null;
      logger.warn(TAG, `停止后台长时任务失败，已强制重置状态：${String(error)}`);
    }
  }

  /**
   * 当前是否存在后台长时任务在运行
   */
  static isRunning(): boolean {
    return BackgroundTaskHelper.taskRunning;
  }

  /**
   * 当前持有后台资格的业务数量
   */
  static getOwnerCount(): number {
    return BackgroundTaskHelper.activeOwners.size;
  }

  private static normalizeOwner(owner: string): string {
    const trimmedOwner = owner.trim();
    if (trimmedOwner.length > 0) {
      return trimmedOwner;
    }

    logger.warn(TAG, '后台长时任务未提供有效持有者标识，已回退为默认持有者');
    return DEFAULT_OWNER;
  }

  /**
   * 真正向系统申请后台运行资格
   */
  private static async requestBackgroundRunning(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const wantAgentObj: WantAgent = await BackgroundTaskHelper.buildWantAgent(context);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        UI_ABILITY_BACKGROUND_MODES,
        wantAgentObj
      );

      BackgroundTaskHelper.taskRunning = true;
      BackgroundTaskHelper.startAutoRefresh();
      logger.info(
        TAG,
        `后台长时任务已启动，模式=${UI_ABILITY_BACKGROUND_MODES.join(',')}，当前持有者数=${BackgroundTaskHelper.activeOwners.size}`
      );
      return true;
    } catch (error) {
      logger.warn(TAG, `启动后台长时任务失败，前台流程将继续执行：${String(error)}`);
      return false;
    }
  }

  /**
   * 启动自动续期，避免长任务在后台运行过程中被系统提前回收
   */
  private static startAutoRefresh(): void {
    BackgroundTaskHelper.stopAutoRefresh();
    BackgroundTaskHelper.refreshTimer = setInterval(() => {
      void BackgroundTaskHelper.handleAutoRefresh();
    }, AUTO_REFRESH_INTERVAL_MS) as number;
    logger.info(TAG, `后台长时任务自动续期已启动，间隔=${AUTO_REFRESH_INTERVAL_MS}ms`);
  }

  /**
   * 停止自动续期
   */
  private static stopAutoRefresh(): void {
    if (BackgroundTaskHelper.refreshTimer !== -1) {
      clearInterval(BackgroundTaskHelper.refreshTimer);
      BackgroundTaskHelper.refreshTimer = -1;
      logger.info(TAG, '后台长时任务自动续期已停止');
    }
  }

  /**
   * 自动续期处理
   */
  private static async handleAutoRefresh(): Promise<void> {
    if (BackgroundTaskHelper.activeOwners.size === 0 || BackgroundTaskHelper.currentContext === null) {
      logger.warn(TAG, '自动续期时发现没有有效持有者或上下文，已停止续期');
      BackgroundTaskHelper.stopAutoRefresh();
      return;
    }

    if (!BackgroundTaskHelper.taskRunning) {
      logger.warn(TAG, '自动续期时发现后台长时任务未运行，准备重新申请');
      await BackgroundTaskHelper.requestBackgroundRunning(BackgroundTaskHelper.currentContext);
      return;
    }

    logger.info(
      TAG,
      `开始自动续期后台长时任务，当前持有者数=${BackgroundTaskHelper.activeOwners.size}`
    );
    await BackgroundTaskHelper.refreshTask(BackgroundTaskHelper.currentContext);
  }

  /**
   * 通过 stop + start 的方式刷新后台长时任务
   */
  private static async refreshTask(context: common.UIAbilityContext): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundTaskHelper.taskRunning = false;

      const wantAgentObj: WantAgent = await BackgroundTaskHelper.buildWantAgent(context);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        UI_ABILITY_BACKGROUND_MODES,
        wantAgentObj
      );

      BackgroundTaskHelper.taskRunning = true;
      logger.info(
        TAG,
        `后台长时任务自动续期成功，当前持有者数=${BackgroundTaskHelper.activeOwners.size}`
      );
    } catch (error) {
      BackgroundTaskHelper.taskRunning = false;
      logger.warn(TAG, `后台长时任务自动续期失败：${String(error)}`);
    }
  }

  /**
   * 构建 WantAgent，供后台任务通知栏入口使用
   */
  private static async buildWantAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.abilityInfo.bundleName,
          abilityName: 'EntryAbility'
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(wantAgentInfo);
  }
}
