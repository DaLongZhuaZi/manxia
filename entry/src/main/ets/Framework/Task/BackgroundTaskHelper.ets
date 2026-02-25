/**
 * 后台长时任务辅助器
 * 封装 backgroundTaskManager 的 DATA_TRANSFER 长时任务申请与停止
 *
 * 核心规则：
 *  - 业务开始时（用户触发下载/校验）申请后台任务
 *  - 业务完成后立即停止，避免持续占用系统资源
 *  - 任务必须与实际的数据传输行为匹配，否则系统会强制取消
 *  - ⚠️ 系统限制：若检测到10分钟内无有效网络流量，会强制取消 DATA_TRANSFER 任务
 *      → 已通过「每8分钟主动重启任务」来规避此限制（refreshTask）
 *
 * 文件路径: entry/src/main/ets/Framework/Task/BackgroundTaskHelper.ets
 */

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import wantAgent, { WantAgent } from '@ohos.app.ability.wantAgent';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';

const TAG = 'BackgroundTaskHelper';

/**
 * 自动刷新间隔：8 分钟
 * 比系统的「10 分钟无流量取消」限制提前 2 分钟重启，确保任务持续有效
 */
const AUTO_REFRESH_INTERVAL_MS = 8 * 60 * 1000;

export class BackgroundTaskHelper {
  /** 当前是否已有后台长时任务在运行 */
  private static taskRunning: boolean = false;
  /** 自动刷新定时器 ID，-1 表示未启动 */
  private static refreshTimer: number = -1;

  // ─── 公开接口 ──────────────────────────────────────────────────────────────

  /**
   * 申请 DATA_TRANSFER 后台长时任务
   * APP 被挂起后，网络、CPU 等资源仍可使用
   * 同时启动自动刷新定时器，防止系统因10分钟无流量而强制取消
   * @param context UIAbility 上下文
   */
  static async startDataTransferTask(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundTaskHelper.taskRunning) {
      logger.info(TAG, '后台长时任务已在运行，跳过重复申请');
      return;
    }

    try {
      const wantAgentObj: WantAgent = await BackgroundTaskHelper.buildWantAgent(context);

      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        wantAgentObj
      );

      BackgroundTaskHelper.taskRunning = true;
      // 启动自动刷新：每8分钟重启任务，防止触发系统「10分钟无流量取消」
      BackgroundTaskHelper.startAutoRefresh(context);
      logger.info(TAG, '✅ DATA_TRANSFER 后台长时任务已启动');
    } catch (error) {
      // 不抛出异常：即使申请失败（如设备不支持），业务仍可在前台继续运行
      logger.warn(TAG, `⚠️ 启动后台长时任务失败（前台仍可运行）: ${String(error)}`);
    }
  }

  /**
   * 停止 DATA_TRANSFER 后台长时任务
   * 业务完成后必须立即调用
   * @param context UIAbility 上下文
   */
  static async stopDataTransferTask(context: common.UIAbilityContext): Promise<void> {
    // 先停自动刷新，再停后台任务
    BackgroundTaskHelper.stopAutoRefresh();

    if (!BackgroundTaskHelper.taskRunning) {
      return;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundTaskHelper.taskRunning = false;
      logger.info(TAG, '✅ DATA_TRANSFER 后台长时任务已停止');
    } catch (error) {
      logger.warn(TAG, `⚠️ 停止后台长时任务失败: ${String(error)}`);
      // 无论是否成功，重置状态标记，避免后续申请被拦截
      BackgroundTaskHelper.taskRunning = false;
    }
  }

  /**
   * 查询当前是否有后台长时任务在运行
   */
  static isRunning(): boolean {
    return BackgroundTaskHelper.taskRunning;
  }

  // ─── 自动刷新（防止系统10分钟无流量超时） ─────────────────────────────────

  /**
   * 启动自动刷新定时器
   * 每 AUTO_REFRESH_INTERVAL_MS 毫秒重启一次后台任务
   */
  private static startAutoRefresh(context: common.UIAbilityContext): void {
    BackgroundTaskHelper.stopAutoRefresh();
    BackgroundTaskHelper.refreshTimer = setInterval(async () => {
      if (!BackgroundTaskHelper.taskRunning) {
        BackgroundTaskHelper.stopAutoRefresh();
        return;
      }
      logger.info(TAG, '🔄 定时刷新后台长时任务（防止10分钟无流量超时）');
      await BackgroundTaskHelper.refreshTask(context);
    }, AUTO_REFRESH_INTERVAL_MS) as number;
  }

  /** 停止自动刷新定时器 */
  private static stopAutoRefresh(): void {
    if (BackgroundTaskHelper.refreshTimer !== -1) {
      clearInterval(BackgroundTaskHelper.refreshTimer);
      BackgroundTaskHelper.refreshTimer = -1;
    }
  }

  /**
   * 刷新后台任务：先 stop 再立即 start，重置系统的10分钟计时器
   * stop → start 的间隔极短（< 200ms），系统不会在此窗口内杀死进程
   */
  private static async refreshTask(context: common.UIAbilityContext): Promise<void> {
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      BackgroundTaskHelper.taskRunning = false;

      const wantAgentObj: WantAgent = await BackgroundTaskHelper.buildWantAgent(context);
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        wantAgentObj
      );
      BackgroundTaskHelper.taskRunning = true;
      logger.info(TAG, '✅ DATA_TRANSFER 后台长时任务已刷新');
    } catch (error) {
      logger.warn(TAG, `⚠️ 刷新后台长时任务失败: ${String(error)}`);
      BackgroundTaskHelper.taskRunning = false;
    }
  }

  /**
   * 构建 WantAgent（供 startBackgroundRunning 关联通知栏入口）
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
