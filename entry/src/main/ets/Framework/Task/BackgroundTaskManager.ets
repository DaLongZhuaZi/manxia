/**
 * 后台任务管理器
 * 支持在离开页面后继续执行耗时任务，并通过悬浮球显示进度
 */
import { logger } from '../../Utils/Logger';
import { generateUUID } from '../Utils/UUIDGenerator';

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
  EXPORT = 'EXPORT',
  OTHER = 'OTHER'
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
 * 内部任务数据结构
 */
interface InternalTask extends BackgroundTask {
  executor: TaskExecutor;
  cancelSignal: TaskCancelSignal;
  promise?: Promise<void>;
}

/**
 * 后台任务管理器单例
 */
export class BackgroundTaskManager {
  private static instance: BackgroundTaskManager | null = null;
  private tasks: Map<string, InternalTask> = new Map();
  private listeners: Set<TaskStatusListener> = new Set();
  private isFloatingBallVisible: boolean = false;
  private floatingBallUpdateCallback: ((tasks: BackgroundTask[]) => void) | null = null;

  private constructor() {
    logger.info(TAG, '后台任务管理器初始化');
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
    executor: TaskExecutor
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
      cancelSignal: { isCancelled: false }
    };

    this.tasks.set(taskId, task);
    logger.info(TAG, `创建任务: ${taskId}, 类型: ${type}, 名称: ${name}`);
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
      logger.error(TAG, `任务不存在: ${taskId}`);
      throw new Error(`任务不存在: ${taskId}`);
    }

    if (task.status !== TaskStatus.PENDING) {
      logger.warn(TAG, `任务状态不正确: ${task.status}`);
      return task.result;
    }

    task.status = TaskStatus.RUNNING;
    task.startTime = Date.now();
    this.notifyListeners(task);
    this.updateFloatingBall();

    logger.info(TAG, `开始执行任务: ${taskId}`);

    try {
      const result = await task.executor(
        (current: number, total: number, message: string) => {
          this.updateTaskProgress(taskId, current, total, message);
        },
        task.cancelSignal
      );

      task.status = TaskStatus.COMPLETED;
      task.endTime = Date.now();
      task.result = result;
      task.progress.percentage = 100;
      task.progress.message = '完成';
      
      logger.info(TAG, `任务完成: ${taskId}, 耗时: ${task.endTime - (task.startTime || task.createTime)}ms`);
      this.notifyListeners(task);
      this.updateFloatingBall();

      // 延迟移除已完成的任务
      setTimeout(() => {
        this.removeTask(taskId);
      }, 3000);

      return result;
    } catch (error) {
      if (task.cancelSignal.isCancelled) {
        task.status = TaskStatus.CANCELLED;
        task.errorMessage = '任务已取消';
        logger.info(TAG, `任务已取消: ${taskId}`);
      } else {
        task.status = TaskStatus.FAILED;
        task.errorMessage = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `任务失败: ${taskId}, 错误: ${task.errorMessage}`);
      }
      task.endTime = Date.now();
      this.notifyListeners(task);
      this.updateFloatingBall();

      // 延迟移除失败的任务
      setTimeout(() => {
        this.removeTask(taskId);
      }, 5000);

      const err = new Error(task.errorMessage || '任务执行失败');
      throw err;
    }
  }

  /**
   * 更新任务进度
   */
  private updateTaskProgress(taskId: string, current: number, total: number, message: string): void {
    const task = this.tasks.get(taskId);
    if (!task) return;

    task.progress = {
      current: current,
      total: total,
      percentage: total > 0 ? Math.floor((current / total) * 100) : 0,
      message: message
    };

    this.notifyListeners(task);
    this.updateFloatingBall();
  }

  /**
   * 取消任务
   */
  public cancelTask(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return;
    }

    if (task.status === TaskStatus.RUNNING) {
      task.cancelSignal.isCancelled = true;
      logger.info(TAG, `请求取消任务: ${taskId}`);
    }
  }

  /**
   * 移除任务
   */
  private removeTask(taskId: string): void {
    this.tasks.delete(taskId);
    this.updateFloatingBall();
    logger.info(TAG, `移除任务: ${taskId}`);
  }

  /**
   * 获取任务
   */
  public getTask(taskId: string): BackgroundTask | undefined {
    return this.tasks.get(taskId);
  }

  /**
   * 获取所有活跃任务
   */
  public getActiveTasks(): BackgroundTask[] {
    const activeTasks: BackgroundTask[] = [];
    this.tasks.forEach((task) => {
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
    this.tasks.forEach((task) => {
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
    this.listeners.forEach((listener) => {
      try {
        listener(task);
      } catch (error) {
        logger.error(TAG, `监听器执行失败: ${error}`);
      }
    });
  }

  /**
   * 设置悬浮球更新回调
   */
  public setFloatingBallCallback(callback: ((tasks: BackgroundTask[]) => void) | null): void {
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
      logger.info(TAG, `悬浮球可见性变化: ${shouldShow}`);
    }

    if (this.floatingBallUpdateCallback) {
      this.floatingBallUpdateCallback(activeTasks);
    }
  }

  /**
   * 检查是否有活跃任务
   */
  public hasActiveTasks(): boolean {
    return this.getActiveTasks().length > 0;
  }

  /**
   * 获取当前主要任务的进度（用于悬浮球显示）
   */
  public getMainTaskProgress(): TaskProgress | null {
    const activeTasks = this.getActiveTasks();
    if (activeTasks.length === 0) {
      return null;
    }
    // 返回第一个运行中的任务进度
    const runningTask = activeTasks.find(t => t.status === TaskStatus.RUNNING);
    return runningTask ? runningTask.progress : activeTasks[0].progress;
  }
}
