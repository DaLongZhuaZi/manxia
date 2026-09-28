/**
 * 后台任务管理器
 * 支持在离开页面后继续执行耗时任务，并通过悬浮球展示任务进度。
 * 同时负责为特定任务接入后台长时任务与系统通知。
 */

import { common } from '@kit.AbilityKit';
import { AppNotificationManager } from 'manxia_core/src/main/ets/Framework/Managers/NotificationManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { generateUUID } from 'manxia_core/src/main/ets/Framework/Utils/UUIDGenerator';
import { BackgroundTaskHelper } from './BackgroundTaskHelper';
import { TaskNavigationTarget } from 'manxia_core/src/main/ets/Framework/Task/TaskNavigationTypes';

const TAG = 'BackgroundTaskManager';

/**
 * 任务状态枚举
 */
export enum TaskStatus {
  PENDING = 'PENDING',
  RUNNING = 'RUNNING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  CANCELLED = 'CANCELLED'
}

/**
 * 任务类型枚举
 */
export enum TaskType {
  PDF_IMPORT = 'PDF_IMPORT',
  MANGA_IMPORT = 'MANGA_IMPORT',
  DOWNLOAD = 'DOWNLOAD',
  SOURCE_AUTO_CHECK = 'SOURCE_AUTO_CHECK',
  EXPORT = 'EXPORT',
  OTHER = 'OTHER'
}

/**
 * 任务通知场景
 */
export enum TaskNotificationScene {
  PDF_IMPORT = 'PDF_IMPORT',
  NETWORK_CACHE = 'NETWORK_CACHE',
  SOURCE_AUTO_CHECK = 'SOURCE_AUTO_CHECK'
}

/**
 * 任务进度信息
 */
export interface TaskProgress {
  current: number;
  total: number;
  percentage: number;
  message: string;
}

/**
 * 任务通知配置
 */
export interface TaskNotificationOptions {
  scene: TaskNotificationScene;
  targetName: string;
}

/**
 * 后台任务附加选项
 */
export interface BackgroundTaskOptions {
  context?: common.UIAbilityContext;
  enableBackgroundRunning?: boolean;
  notification?: TaskNotificationOptions;
  navigation?: TaskNavigationTarget;
}

/**
 * 后台任务接口
 */
export interface BackgroundTask {
  id: string;
  type: TaskType;
  name: string;
  status: TaskStatus;
  progress: TaskProgress;
  createTime: number;
  startTime?: number;
  endTime?: number;
  errorMessage?: string;
  result?: Object;
  navigation?: TaskNavigationTarget;
}

/**
 * 任务取消信号
 */
export interface TaskCancelSignal {
  isCancelled: boolean;
}

/**
 * 任务执行函数类型
 */
export type TaskExecutor = (
  onProgress: (current: number, total: number, message: string) => void,
  cancelSignal: TaskCancelSignal
) => Promise<Object | undefined>;

/**
 * 任务状态变化监听器
 */
export type TaskStatusListener = (task: BackgroundTask) => void;

/**
 * 悬浮球更新回调
 */
export type FloatingBallUpdateCallback = (tasks: BackgroundTask[]) => void;

/**
 * 任务进度通知快照
 */
interface TaskProgressNotificationSnapshot {
  scene: TaskNotificationScene;
  targetName: string;
  current: number;
  total: number;
  percentage: number;
  message: string;
  navigation?: TaskNavigationTarget;
}

interface TaskResultWithSummary {
  summary?: string;
}

/**
 * 内部任务数据结构
 */
interface InternalTask extends BackgroundTask {
  executor: TaskExecutor;
  cancelSignal: TaskCancelSignal;
  options?: BackgroundTaskOptions;
  lastProgressNotificationPercentage: number;
  lastProgressNotificationMessage: string;
  isSendingProgressNotification: boolean;
  pendingProgressNotification?: TaskProgressNotificationSnapshot;
}

/**
 * 后台任务管理器单例
 */
export class BackgroundTaskManager {
  private static instance: BackgroundTaskManager | null = null;

  private tasks: Map<string, InternalTask> = new Map<string, InternalTask>();
  private listeners: Set<TaskStatusListener> = new Set<TaskStatusListener>();
  private isFloatingBallVisible: boolean = false;
  private floatingBallUpdateCallback: FloatingBallUpdateCallback | null = null;
  private notificationManager: AppNotificationManager = AppNotificationManager.getInstance();

  private constructor() {
    logger.info(TAG, '后台任务管理器已初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): BackgroundTaskManager {
    if (!BackgroundTaskManager.instance) {
      BackgroundTaskManager.instance = new BackgroundTaskManager();
    }
    return BackgroundTaskManager.instance;
  }

  /**
   * 创建新任务
   */
  public createTask(
    type: TaskType,
    name: string,
    executor: TaskExecutor,
    options?: BackgroundTaskOptions
  ): string {
    const taskId = generateUUID();
    const task: InternalTask = {
      id: taskId,
      type: type,
      name: name,
      status: TaskStatus.PENDING,
      progress: {
        current: 0,
        total: 100,
        percentage: 0,
        message: '等待开始...'
      },
      createTime: Date.now(),
      executor: executor,
      cancelSignal: { isCancelled: false },
      options: options,
      navigation: options?.navigation,
      lastProgressNotificationPercentage: -1,
      lastProgressNotificationMessage: '',
      isSendingProgressNotification: false,
      pendingProgressNotification: undefined
    };

    this.tasks.set(taskId, task);
    logger.info(
      TAG,
      `创建后台任务：id=${taskId}，类型=${type}，名称=${name}，启用后台运行=${options?.enableBackgroundRunning === true}`
    );
    this.notifyListeners(task);
    this.updateFloatingBall();

    return taskId;
  }

  /**
   * 启动任务
   */
  public async startTask(taskId: string): Promise<Object | undefined> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.error(TAG, `任务不存在：${taskId}`);
      throw new Error(`任务不存在：${taskId}`);
    }

    if (task.status !== TaskStatus.PENDING) {
      logger.warn(TAG, `任务状态不正确，无法重复启动：id=${taskId}，状态=${task.status}`);
      return task.result;
    }

    task.status = TaskStatus.RUNNING;
    task.startTime = Date.now();
    this.notifyListeners(task);
    this.updateFloatingBall();

    logger.info(TAG, `开始执行后台任务：id=${taskId}，名称=${task.name}`);

    await this.startBackgroundRunningIfNeeded(task);
    await this.sendTaskProgressNotification(task, true);

    try {
      const result = await task.executor(
        (current: number, total: number, message: string): void => {
          this.updateTaskProgress(taskId, current, total, message);
        },
        task.cancelSignal
      );

      task.status = TaskStatus.COMPLETED;
      task.endTime = Date.now();
      task.result = result;
      task.progress = {
        current: task.progress.total > 0 ? task.progress.total : 100,
        total: task.progress.total > 0 ? task.progress.total : 100,
        percentage: 100,
        message: '完成'
      };

      logger.info(
        TAG,
        `后台任务执行完成：id=${taskId}，耗时=${task.endTime - (task.startTime || task.createTime)}ms`
      );

      this.notifyListeners(task);
      this.updateFloatingBall();
      await this.waitForProgressNotificationIdle(task);
      await this.sendTaskCompletionNotification(task);

      setTimeout(() => {
        this.removeTask(taskId);
      }, 3000);

      return result;
    } catch (error) {
      if (task.cancelSignal.isCancelled) {
        task.status = TaskStatus.CANCELLED;
        task.errorMessage = '任务已取消';
        logger.info(TAG, `后台任务已取消：id=${taskId}`);
        await this.waitForProgressNotificationIdle(task);
        await this.cancelTaskNotification(task);
      } else {
        task.status = TaskStatus.FAILED;
        task.errorMessage = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `后台任务执行失败：id=${taskId}，错误=${task.errorMessage}`);
        await this.waitForProgressNotificationIdle(task);
        await this.sendTaskFailedNotification(task);
      }

      task.endTime = Date.now();
      this.notifyListeners(task);
      this.updateFloatingBall();

      setTimeout(() => {
        this.removeTask(taskId);
      }, 5000);

      throw new Error(task.errorMessage || '任务执行失败');
    } finally {
      await this.stopBackgroundRunningIfNeeded(task);
    }
  }

  /**
   * 更新任务进度
   */
  private updateTaskProgress(taskId: string, current: number, total: number, message: string): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      return;
    }

    const safeTotal = total > 0 ? total : 0;
    const safeCurrent = safeTotal > 0
      ? Math.max(0, Math.min(current, safeTotal))
      : Math.max(0, current);
    const percentage = safeTotal > 0
      ? Math.max(0, Math.min(100, Math.floor((safeCurrent / safeTotal) * 100)))
      : 0;

    task.progress = {
      current: safeCurrent,
      total: safeTotal,
      percentage: percentage,
      message: message
    };

    logger.debug(
      TAG,
      `后台任务进度更新：id=${taskId}，进度=${safeCurrent}/${safeTotal}，百分比=${percentage}%，消息=${message}`
    );

    this.notifyListeners(task);
    this.updateFloatingBall();
    void this.sendTaskProgressNotification(task);
  }

  /**
   * 取消任务
   */
  public cancelTask(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `取消任务失败，任务不存在：${taskId}`);
      return;
    }

    if (task.status === TaskStatus.PENDING) {
      task.cancelSignal.isCancelled = true;
      task.status = TaskStatus.CANCELLED;
      task.endTime = Date.now();
      task.errorMessage = '任务已取消';
      task.progress = {
        current: task.progress.current,
        total: task.progress.total,
        percentage: task.progress.percentage,
        message: '正在取消...'
      };
      logger.info(TAG, `已取消等待中的后台任务：${taskId}`);
      this.notifyListeners(task);
      this.updateFloatingBall();
      void this.cancelTaskNotification(task);
      setTimeout(() => {
        this.removeTask(taskId);
      }, 1500);
      return;
    }

    if (task.status === TaskStatus.RUNNING) {
      task.cancelSignal.isCancelled = true;
      task.progress = {
        current: task.progress.current,
        total: task.progress.total,
        percentage: task.progress.percentage,
        message: '正在取消...'
      };
      logger.info(TAG, `已请求取消后台任务：${taskId}`);
      this.notifyListeners(task);
      this.updateFloatingBall();
      void this.sendTaskProgressNotification(task, true);
    }
  }

  /**
   * 移除任务
   */
  private removeTask(taskId: string): void {
    this.tasks.delete(taskId);
    this.updateFloatingBall();
    logger.info(TAG, `后台任务已移除：${taskId}`);
  }

  /**
   * 获取单个任务
   */
  public getTask(taskId: string): BackgroundTask | undefined {
    return this.tasks.get(taskId);
  }

  public updateTaskNavigation(taskId: string, navigation: TaskNavigationTarget): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `更新任务导航目标失败，任务不存在：${taskId}`);
      return;
    }
    task.navigation = navigation;
    logger.debug(TAG, `后台任务导航目标已更新：id=${taskId}, route=${navigation.routeName}`);
  }

  /**
   * 获取所有活跃任务
   */
  public getActiveTasks(): BackgroundTask[] {
    const activeTasks: BackgroundTask[] = [];
    this.tasks.forEach((task: InternalTask) => {
      if (task.status === TaskStatus.PENDING || task.status === TaskStatus.RUNNING) {
        activeTasks.push(task);
      }
    });
    return activeTasks;
  }

  /**
   * 获取所有任务
   */
  public getAllTasks(): BackgroundTask[] {
    const allTasks: BackgroundTask[] = [];
    this.tasks.forEach((task: InternalTask) => {
      allTasks.push(task);
    });
    return allTasks;
  }

  /**
   * 添加任务状态监听器
   */
  public addListener(listener: TaskStatusListener): void {
    this.listeners.add(listener);
  }

  /**
   * 移除任务状态监听器
   */
  public removeListener(listener: TaskStatusListener): void {
    this.listeners.delete(listener);
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(task: BackgroundTask): void {
    this.listeners.forEach((listener: TaskStatusListener) => {
      try {
        listener(task);
      } catch (error) {
        logger.error(TAG, `后台任务监听器执行失败：${String(error)}`);
      }
    });
  }

  /**
   * 设置悬浮球更新回调
   */
  public setFloatingBallCallback(callback: FloatingBallUpdateCallback | null): void {
    this.floatingBallUpdateCallback = callback;
    if (callback) {
      callback(this.getActiveTasks());
    }
  }

  /**
   * 更新悬浮球状态
   */
  private updateFloatingBall(): void {
    const activeTasks = this.getActiveTasks();
    const shouldShow = activeTasks.length > 0;

    if (shouldShow !== this.isFloatingBallVisible) {
      this.isFloatingBallVisible = shouldShow;
      logger.info(TAG, `后台任务悬浮球可见性变更：${shouldShow}`);
    }

    if (this.floatingBallUpdateCallback) {
      this.floatingBallUpdateCallback(activeTasks);
    }
  }

  /**
   * 当前是否有活跃任务
   */
  public hasActiveTasks(): boolean {
    return this.getActiveTasks().length > 0;
  }

  /**
   * 获取当前主要任务进度
   */
  public getMainTaskProgress(): TaskProgress | null {
    const activeTasks = this.getActiveTasks();
    if (activeTasks.length === 0) {
      return null;
    }

    const runningTask = activeTasks.find((task: BackgroundTask) => task.status === TaskStatus.RUNNING);
    return runningTask ? runningTask.progress : activeTasks[0].progress;
  }

  /**
   * 如有需要，为任务申请后台长时运行
   */
  private async startBackgroundRunningIfNeeded(task: InternalTask): Promise<void> {
    if (!task.options?.enableBackgroundRunning || !task.options.context) {
      return;
    }

    const backgroundOwner = this.buildBackgroundOwner(task.id);
    logger.info(TAG, `准备为后台任务申请长时运行：id=${task.id}，持有者=${backgroundOwner}`);
    await BackgroundTaskHelper.startDataTransferTask(task.options.context, backgroundOwner);
  }

  /**
   * 如有需要，释放任务的后台长时运行资格
   */
  private async stopBackgroundRunningIfNeeded(task: InternalTask): Promise<void> {
    if (!task.options?.enableBackgroundRunning || !task.options.context) {
      return;
    }

    const backgroundOwner = this.buildBackgroundOwner(task.id);
    logger.info(TAG, `准备释放后台任务长时运行资格：id=${task.id}，持有者=${backgroundOwner}`);
    await BackgroundTaskHelper.stopDataTransferTask(task.options.context, backgroundOwner);
  }

  /**
   * 发送任务进度通知
   */
  private async sendTaskProgressNotification(task: InternalTask, force: boolean = false): Promise<void> {
    if (!task.options?.notification) {
      return;
    }

    const snapshot = this.buildProgressNotificationSnapshot(task);
    const samePercentage = task.lastProgressNotificationPercentage === snapshot.percentage;
    const sameMessage = task.lastProgressNotificationMessage === snapshot.message;
    if (!force && samePercentage && sameMessage) {
      return;
    }

    task.lastProgressNotificationPercentage = snapshot.percentage;
    task.lastProgressNotificationMessage = snapshot.message;
    task.pendingProgressNotification = snapshot;

    if (task.isSendingProgressNotification) {
      logger.debug(
        TAG,
        `后台任务进度通知仍在发送中，已合并最新进度：id=${task.id}，百分比=${snapshot.percentage}%`
      );
      return;
    }

    task.isSendingProgressNotification = true;
    await this.flushProgressNotifications(task);
  }

  /**
   * 发送任务完成通知
   */
  private async sendTaskCompletionNotification(task: InternalTask): Promise<void> {
    if (!task.options?.notification) {
      return;
    }

    switch (task.options.notification.scene) {
      case TaskNotificationScene.PDF_IMPORT:
        logger.info(TAG, `发送 PDF 导入完成通知：id=${task.id}，目标=${task.options.notification.targetName}`);
        await this.notificationManager.sendPdfImportCompleteNotification(
          task.id,
          task.options.notification.targetName
        );
        break;
      case TaskNotificationScene.NETWORK_CACHE:
        logger.info(TAG, `发送网络缓存完成通知：id=${task.id}，目标=${task.options.notification.targetName}`);
        await this.notificationManager.sendDownloadCompleteNotification(
          task.id,
          task.options.notification.targetName
        );
        break;
      case TaskNotificationScene.SOURCE_AUTO_CHECK:
        logger.info(TAG, `发送图源巡检完成通知：id=${task.id}，目标=${task.options.notification.targetName}`);
        await this.notificationManager.sendSourceAutoCheckCompleteNotification(
          task.id,
          task.options.notification.targetName,
          this.resolveResultSummary(task.result, '巡检已完成'),
          task.navigation,
          task.options.context
        );
        break;
      default:
        break;
    }
  }

  /**
   * 发送任务失败通知
   */
  private async sendTaskFailedNotification(task: InternalTask): Promise<void> {
    if (!task.options?.notification) {
      return;
    }

    const errorMessage = task.errorMessage || '未知错误';
    switch (task.options.notification.scene) {
      case TaskNotificationScene.PDF_IMPORT:
        logger.warn(
          TAG,
          `发送 PDF 导入失败通知：id=${task.id}，目标=${task.options.notification.targetName}，原因=${errorMessage}`
        );
        await this.notificationManager.sendPdfImportFailedNotification(
          task.id,
          task.options.notification.targetName,
          errorMessage
        );
        break;
      case TaskNotificationScene.NETWORK_CACHE:
        logger.warn(TAG, `发送网络缓存失败通知：id=${task.id}，目标=${task.options.notification.targetName}，原因=${errorMessage}`);
        await this.notificationManager.sendDownloadFailedNotification(
          task.id,
          task.options.notification.targetName,
          errorMessage
        );
        break;
      case TaskNotificationScene.SOURCE_AUTO_CHECK:
        logger.warn(TAG, `发送图源巡检失败通知：id=${task.id}，目标=${task.options.notification.targetName}，原因=${errorMessage}`);
        await this.notificationManager.sendSourceAutoCheckFailedNotification(
          task.id,
          task.options.notification.targetName,
          errorMessage,
          task.navigation,
          task.options.context
        );
        break;
      default:
        break;
    }
  }

  /**
   * 取消任务通知
   */
  private async cancelTaskNotification(task: InternalTask): Promise<void> {
    if (!task.options?.notification) {
      return;
    }

    logger.info(TAG, `取消后台任务通知：id=${task.id}，目标=${task.options.notification.targetName}`);
    await this.notificationManager.cancelTaskNotification(task.id);
  }

  /**
   * 构建后台任务持有者标识
   */
  private buildBackgroundOwner(taskId: string): string {
    return `background_task_${taskId}`;
  }

  private resolveResultSummary(result: Object | undefined, fallback: string): string {
    if (result === undefined) {
      return fallback;
    }
    const summaryResult: TaskResultWithSummary = result as TaskResultWithSummary;
    if (summaryResult.summary !== undefined && summaryResult.summary.length > 0) {
      return summaryResult.summary;
    }
    return fallback;
  }

  /**
   * 构建当前任务的进度通知快照，避免异步发送时读取到被后续覆盖的对象
   */
  private buildProgressNotificationSnapshot(task: InternalTask): TaskProgressNotificationSnapshot {
    return {
      scene: task.options?.notification?.scene || TaskNotificationScene.PDF_IMPORT,
      targetName: task.options?.notification?.targetName || task.name,
      current: task.progress.current,
      total: task.progress.total,
      percentage: task.progress.percentage,
      message: task.progress.message,
      navigation: task.navigation
    };
  }

  /**
   * 串行刷新任务进度通知，避免旧通知在新通知之后落地，导致进度回退
   */
  private async flushProgressNotifications(task: InternalTask): Promise<void> {
    try {
      while (task.pendingProgressNotification) {
        if (task.status !== TaskStatus.RUNNING) {
          logger.info(TAG, `任务已不在运行态，丢弃残留进度通知：id=${task.id}`);
          task.pendingProgressNotification = undefined;
          break;
        }

        const snapshot = task.pendingProgressNotification;
        if (!snapshot) {
          break;
        }
        task.pendingProgressNotification = undefined;

        switch (snapshot.scene) {
          case TaskNotificationScene.PDF_IMPORT:
            logger.info(
              TAG,
              `发送 PDF 导入进度通知：id=${task.id}，目标=${snapshot.targetName}，百分比=${snapshot.percentage}%`
            );
            await this.notificationManager.sendPdfImportProgressNotification(
              task.id,
              snapshot.targetName,
              snapshot.current,
              snapshot.total,
              snapshot.message
            );
            break;
          case TaskNotificationScene.NETWORK_CACHE:
            logger.info(TAG, `发送网络缓存进度通知：id=${task.id}，目标=${snapshot.targetName}，百分比=${snapshot.percentage}%`);
            await this.notificationManager.sendDownloadProgressNotification(
              task.id,
              snapshot.targetName,
              snapshot.current,
              snapshot.total
            );
            break;
          case TaskNotificationScene.SOURCE_AUTO_CHECK:
            logger.info(TAG, `发送图源巡检进度通知：id=${task.id}，目标=${snapshot.targetName}，百分比=${snapshot.percentage}%`);
            await this.notificationManager.sendSourceAutoCheckProgressNotification(
              task.id,
              snapshot.targetName,
              snapshot.current,
              snapshot.total,
              snapshot.message,
              snapshot.navigation,
              task.options?.context
            );
            break;
          default:
            break;
        }
      }
    } finally {
      task.isSendingProgressNotification = false;
      if (task.pendingProgressNotification && task.status === TaskStatus.RUNNING) {
        logger.debug(TAG, `检测到发送期间产生了新的进度快照，继续补发：id=${task.id}`);
        task.isSendingProgressNotification = true;
        await this.flushProgressNotifications(task);
      }
    }
  }

  /**
   * 等待当前任务的进度通知发送完成，避免完成/失败通知被旧进度覆盖
   */
  private async waitForProgressNotificationIdle(task: InternalTask): Promise<void> {
    let waitedTimes = 0;
    while (task.isSendingProgressNotification) {
      await new Promise<void>((resolve) => {
        setTimeout(() => {
          resolve();
        }, 12);
      });
      waitedTimes++;
      if (waitedTimes >= 250) {
        logger.warn(TAG, `等待进度通知发送完成超时，继续执行后续通知：id=${task.id}`);
        break;
      }
    }
  }
}
