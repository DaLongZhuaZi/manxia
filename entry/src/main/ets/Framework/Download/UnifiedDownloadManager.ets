/**
 * 统一下载管理器
 * 整合漫画和小说的下载功能，提供统一的下载接口
 * 支持后台下载、队列管理、进度回调
 * 
 * 文件路径: entry/src/main/ets/Framework/Download/UnifiedDownloadManager.ets
 */

import { logger } from '../../Utils/Logger';
import { MangaDownloadManager, DownloadTaskInfo, TaskStatus, PageListFetcher, DownloadPageItem } from './DownloadManager';
import { getNovelChapterCacheManager, NovelChapterCacheManager, DownloadProgressCallback as NovelDownloadCallback } from '../Novel/NovelChapterCacheManager';
import { LegadoChapter } from '../Novel/LegadoSourceTypes';
import { AppNotificationManager } from '../Managers/NotificationManager';
import { common } from '@kit.AbilityKit';

const TAG = 'UnifiedDownloadManager';

/**
 * 统一下载内容类型
 */
export enum UnifiedDownloadType {
  MANGA = 'manga',
  NOVEL = 'novel',
  EBOOK = 'ebook'
}

/**
 * 统一下载任务状态
 */
export enum UnifiedTaskStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

/**
 * 统一下载任务信息
 */
export interface UnifiedDownloadTask {
  id: string;
  type: UnifiedDownloadType;
  contentId: string;
  contentTitle: string;
  
  // 章节信息（漫画/小说）
  chapterId?: string;
  chapterTitle?: string;
  chapterIndex?: number;
  
  // 范围下载（小说批量下载）
  startChapterIndex?: number;
  endChapterIndex?: number;
  
  // 状态
  status: UnifiedTaskStatus;
  progress: number;
  downloadedCount: number;
  totalCount: number;
  
  // 时间
  createdTime: number;
  completedTime?: number;
  
  // 错误信息
  error?: string;
  
  // 来源信息
  sourceId?: number;
  sourceName?: string;
}

/**
 * 下载进度回调
 */
export interface UnifiedDownloadCallback {
  onProgress: (task: UnifiedDownloadTask) => void;
  onComplete: (task: UnifiedDownloadTask) => void;
  onError: (task: UnifiedDownloadTask, error: string) => void;
}

/**
 * 漫画章节下载参数
 */
export interface MangaChapterDownloadParams {
  mangaId: string;
  mangaTitle: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  sourceId: number;
  imageUrls?: string[];
  pageListFetcher?: PageListFetcher;
}

/**
 * 小说章节下载参数
 */
export interface NovelChapterDownloadParams {
  bookId: string;
  bookTitle: string;
  sourceId: string;
  chapters: LegadoChapter[];
  startIndex: number;
  endIndex: number;
}

/**
 * 漫画章节下载项（用于批量下载）
 */
export interface MangaChapterDownloadItem {
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  imageUrls?: string[];
  pageListFetcher?: PageListFetcher;
}

/**
 * 下载统计结果
 */
export interface DownloadStatsResult {
  total: number;
  pending: number;
  downloading: number;
  completed: number;
  failed: number;
  paused: number;
}

export interface MangaBatchDownloadFailure {
  chapterId: string;
  chapterTitle: string;
  reason: string;
}

export interface MangaBatchDownloadResult {
  taskIds: string[];
  createdCount: number;
  failedCount: number;
  failedChapters: MangaBatchDownloadFailure[];
}

export interface ContentDownloadAggregate {
  activeCount: number;
  completedCount: number;
  failedCount: number;
  downloadedCount: number;
  totalCount: number;
  currentTitle: string;
}

/**
 * 统一下载管理器类
 */
export class UnifiedDownloadManager {
  private static instance: UnifiedDownloadManager | null = null;
  
  private mangaDownloadManager: MangaDownloadManager;
  private novelCacheManager: NovelChapterCacheManager;
  private notificationManager: AppNotificationManager;
  
  // 统一任务列表
  private unifiedTasks: Map<string, UnifiedDownloadTask> = new Map();
  private taskIdsByType: Map<string, Set<string>> = new Map();
  private taskIdsByContent: Map<string, Set<string>> = new Map();
  private taskIdsByStatus: Map<string, Set<string>> = new Map();
  
  // 回调管理
  private callbacks: Map<string, UnifiedDownloadCallback> = new Map();
  private globalCallbacks: Set<UnifiedDownloadCallback> = new Set();
  private lastProgressNotifyAtByTaskId: Map<string, number> = new Map();
  private readonly PROGRESS_NOTIFY_INTERVAL_MS: number = 250;
  
  private constructor() {
    this.mangaDownloadManager = MangaDownloadManager.getInstance();
    this.novelCacheManager = getNovelChapterCacheManager();
    this.notificationManager = AppNotificationManager.getInstance();
    
    logger.info(TAG, '统一下载管理器初始化');
  }
  
  public static getInstance(): UnifiedDownloadManager {
    if (!UnifiedDownloadManager.instance) {
      UnifiedDownloadManager.instance = new UnifiedDownloadManager();
    }
    return UnifiedDownloadManager.instance;
  }
  
  /**
   * 设置应用上下文
   */
  public setContext(context: common.UIAbilityContext): void {
    this.mangaDownloadManager.setContext(context);
    logger.info(TAG, '应用上下文已设置');
  }
  
  // ==================== 漫画下载 ====================
  
  /**
   * 下载漫画章节
   * @param params 下载参数
   * @returns 任务ID
   */
  public async downloadMangaChapter(params: MangaChapterDownloadParams): Promise<string> {
    try {
      logger.info(TAG, `创建漫画章节下载任务: ${params.mangaTitle} - ${params.chapterTitle}`);

      const existingTask = this.findActiveMangaUnifiedTask(params.mangaId, params.sourceId, params.chapterId);
      if (existingTask) {
        logger.info(
          TAG,
          `统一漫画下载任务去重命中: manga=${params.mangaId}, chapter=${params.chapterId}, taskId=${existingTask.id}`
        );
        this.registerMangaProgressCallback(existingTask.id);
        return existingTask.id;
      }
      
      let taskId: string;
      
      if (params.imageUrls && params.imageUrls.length > 0) {
        // 已有图片URL列表
        taskId = await this.mangaDownloadManager.createOnlineMangaDownloadTask(
          params.mangaId,
          params.mangaTitle,
          params.chapterId,
          params.chapterTitle,
          params.imageUrls,
          params.sourceId
        );
      } else if (params.pageListFetcher) {
        // 需要延迟获取图片列表
        taskId = await this.mangaDownloadManager.createOnlineMangaDownloadTaskWithFetcher(
          params.mangaId,
          params.mangaTitle,
          params.chapterId,
          params.chapterTitle,
          params.sourceId,
          params.pageListFetcher
        );
      } else {
        throw new Error('缺少图片URL列表或获取方法');
      }
      
      // 创建统一任务记录
      const unifiedTask: UnifiedDownloadTask = {
        id: taskId,
        type: UnifiedDownloadType.MANGA,
        contentId: params.mangaId,
        contentTitle: params.mangaTitle,
        chapterId: params.chapterId,
        chapterTitle: params.chapterTitle,
        chapterIndex: params.chapterIndex,
        status: UnifiedTaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: params.imageUrls?.length || 0,
        createdTime: Date.now(),
        sourceId: params.sourceId
      };
      
      this.registerUnifiedTask(unifiedTask);
      
      // 注册进度回调
      this.registerMangaProgressCallback(taskId);
      
      return taskId;
    } catch (error) {
      logger.error(TAG, `创建漫画下载任务失败: ${String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 批量下载漫画章节
   */
  public async downloadMangaChapters(
    mangaId: string,
    mangaTitle: string,
    sourceId: number,
    chapters: MangaChapterDownloadItem[]
  ): Promise<MangaBatchDownloadResult> {
    const taskIds: string[] = [];
    const failedChapters: MangaBatchDownloadFailure[] = [];
    
    for (const chapter of chapters) {
      try {
        const taskId = await this.downloadMangaChapter({
          mangaId,
          mangaTitle,
          chapterId: chapter.chapterId,
          chapterTitle: chapter.chapterTitle,
          chapterIndex: chapter.chapterIndex,
          sourceId,
          imageUrls: chapter.imageUrls,
          pageListFetcher: chapter.pageListFetcher
        });
        if (!taskIds.includes(taskId)) {
          taskIds.push(taskId);
        }
      } catch (error) {
        const reason = String(error);
        const failure: MangaBatchDownloadFailure = {
          chapterId: chapter.chapterId,
          chapterTitle: chapter.chapterTitle,
          reason: reason
        };
        failedChapters.push(failure);
        logger.error(TAG, `创建漫画下载章节任务失败: ${chapter.chapterTitle}, ${reason}`);
      }
    }

    const result: MangaBatchDownloadResult = {
      taskIds: taskIds,
      createdCount: taskIds.length,
      failedCount: failedChapters.length,
      failedChapters: failedChapters
    };
    logger.info(
      TAG,
      `批量漫画下载任务创建完成: manga=${mangaTitle}, requested=${chapters.length}, created=${result.createdCount}, failed=${result.failedCount}`
    );
    return result;
  }
  
  /**
   * 注册漫画进度回调
   */
  private registerMangaProgressCallback(taskId: string): void {
    this.mangaDownloadManager.registerProgressCallback(
      `unified_${taskId}`,
      (id: string, chapterId: string, progress: number, downloaded: number, total: number) => {
        const task = this.unifiedTasks.get(id);
        if (task) {
          const sourceTask = this.mangaDownloadManager.getTask(id);
          task.progress = progress;
          task.downloadedCount = downloaded;
          task.totalCount = total;

          if (sourceTask && sourceTask.status === TaskStatus.COMPLETED) {
            if (task.status !== UnifiedTaskStatus.COMPLETED) {
              this.updateTaskStatus(task, UnifiedTaskStatus.COMPLETED);
              task.progress = 100;
              task.completedTime = sourceTask.completedTime || Date.now();
              this.notifyComplete(task);
            }
            return;
          }

          if (sourceTask && sourceTask.status === TaskStatus.FAILED) {
            if (task.status !== UnifiedTaskStatus.FAILED) {
              this.updateTaskStatus(task, UnifiedTaskStatus.FAILED);
              task.error = sourceTask.error || '下载失败';
              this.notifyError(task, task.error);
            }
            return;
          }

          if (sourceTask && sourceTask.status === TaskStatus.PAUSED) {
            this.updateTaskStatus(task, UnifiedTaskStatus.PAUSED);
          } else if (progress > 0 || downloaded > 0) {
            this.updateTaskStatus(task, UnifiedTaskStatus.DOWNLOADING);
          }
          
          // 通知回调
          this.notifyProgress(task);
        }
      }
    );
  }
  
  // ==================== 小说下载 ====================
  
  /**
   * 下载小说章节（批量）
   */
  public async downloadNovelChapters(params: NovelChapterDownloadParams): Promise<string> {
    try {
      logger.info(TAG, `创建小说下载任务: ${params.bookTitle}, 章节 ${params.startIndex}-${params.endIndex}`);
      
      // 创建下载任务
      const taskId = this.novelCacheManager.createDownloadTask(
        params.bookId,
        params.bookTitle,
        params.startIndex,
        params.endIndex
      );
      
      // 创建统一任务记录
      const totalCount = params.endIndex - params.startIndex + 1;
      const unifiedTask: UnifiedDownloadTask = {
        id: taskId,
        type: UnifiedDownloadType.NOVEL,
        contentId: params.bookId,
        contentTitle: params.bookTitle,
        startChapterIndex: params.startIndex,
        endChapterIndex: params.endIndex,
        status: UnifiedTaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: totalCount,
        createdTime: Date.now()
      };
      
      this.registerUnifiedTask(unifiedTask);
      
      // 创建进度回调
      const callback: NovelDownloadCallback = {
        onProgress: (current: number, total: number, chapterTitle: string) => {
          const task = this.unifiedTasks.get(taskId);
          if (task) {
            task.downloadedCount = current;
            task.totalCount = total;
            task.progress = Math.round((current / total) * 100);
            this.updateTaskStatus(task, UnifiedTaskStatus.DOWNLOADING);
            task.chapterTitle = chapterTitle;
            this.notifyProgress(task);
          }
        },
        onComplete: () => {
          const task = this.unifiedTasks.get(taskId);
          if (task) {
            this.updateTaskStatus(task, UnifiedTaskStatus.COMPLETED);
            task.progress = 100;
            task.completedTime = Date.now();
            this.notifyComplete(task);
          }
        },
        onError: (error: string) => {
          const task = this.unifiedTasks.get(taskId);
          if (task) {
            this.updateTaskStatus(task, UnifiedTaskStatus.FAILED);
            task.error = error;
            this.notifyError(task, error);
          }
        }
      };
      
      // 开始下载
      this.novelCacheManager.startDownload(taskId, params.sourceId, params.chapters, callback);
      
      return taskId;
    } catch (error) {
      logger.error(TAG, `创建小说下载任务失败: ${String(error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 下载单个小说章节
   */
  public async downloadNovelChapter(
    bookId: string,
    bookTitle: string,
    sourceId: string,
    chapter: LegadoChapter
  ): Promise<string> {
    return this.downloadNovelChapters({
      bookId,
      bookTitle,
      sourceId,
      chapters: [chapter],
      startIndex: chapter.index,
      endIndex: chapter.index
    });
  }
  
  // ==================== 任务管理 ====================
  
  /**
   * 暂停下载任务
   */
  public async pauseTask(taskId: string): Promise<boolean> {
    const task = this.unifiedTasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }
    
    try {
      if (task.type === UnifiedDownloadType.MANGA) {
        const success = await this.mangaDownloadManager.pauseTask(taskId);
        if (success) {
          this.updateTaskStatus(task, UnifiedTaskStatus.PAUSED);
        }
        return success;
      } else if (task.type === UnifiedDownloadType.NOVEL) {
        this.novelCacheManager.pauseDownload(taskId);
        this.updateTaskStatus(task, UnifiedTaskStatus.PAUSED);
        return true;
      }
      return false;
    } catch (error) {
      logger.error(TAG, `暂停任务失败: ${String(error)}`);
      return false;
    }
  }
  
  /**
   * 恢复下载任务
   */
  public async resumeTask(taskId: string): Promise<boolean> {
    const task = this.unifiedTasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }
    
    try {
      if (task.type === UnifiedDownloadType.MANGA) {
        const success = await this.mangaDownloadManager.resumeTask(taskId);
        if (success) {
          this.updateTaskStatus(task, UnifiedTaskStatus.PENDING);
        }
        return success;
      } else if (task.type === UnifiedDownloadType.NOVEL) {
        // 小说恢复需要重新创建任务
        logger.warn(TAG, '小说下载任务暂不支持恢复');
        return false;
      }
      return false;
    } catch (error) {
      logger.error(TAG, `恢复任务失败: ${String(error)}`);
      return false;
    }
  }
  
  /**
   * 取消/删除下载任务
   */
  public async cancelTask(taskId: string): Promise<boolean> {
    const task = this.unifiedTasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }
    
    try {
      if (task.type === UnifiedDownloadType.MANGA) {
        await this.mangaDownloadManager.deleteTask(taskId);
      } else if (task.type === UnifiedDownloadType.NOVEL) {
        this.novelCacheManager.cancelDownload(taskId);
      }
      
      this.unregisterUnifiedTask(taskId);
      
      logger.info(TAG, `任务已取消: ${taskId}`);
      return true;
    } catch (error) {
      logger.error(TAG, `取消任务失败: ${String(error)}`);
      return false;
    }
  }
  
  // ==================== 部分保存 ====================

  /**
   * 手动保存部分下载为归档
   * @param contentId 漫画ID
   * @param chapterId 章节ID
   * @returns 是否保存成功
   */
  public async savePartialDownload(contentId: string, chapterId: string): Promise<boolean> {
    try {
      const tasks = this.getTasksByContent(contentId);
      const task = tasks.find(t => t.chapterId === chapterId);
      if (!task) {
        logger.warn(TAG, `未找到章节对应的下载任务: contentId=${contentId}, chapterId=${chapterId}`);
        return false;
      }
      return await this.mangaDownloadManager.savePartialDownload(task.id);
    } catch (error) {
      logger.error(TAG, `保存部分下载失败: ${String(error)}`);
      return false;
    }
  }

  // ==================== 查询方法 ====================

  /**
   * 获取所有下载任务
   */
  public getAllTasks(): UnifiedDownloadTask[] {
    return Array.from(this.unifiedTasks.values());
  }
  
  /**
   * 获取指定类型的下载任务
   */
  public getTasksByType(type: UnifiedDownloadType): UnifiedDownloadTask[] {
    return this.getIndexedTasks(this.taskIdsByType.get(type));
  }
  
  /**
   * 获取指定内容的下载任务
   */
  public getTasksByContent(contentId: string): UnifiedDownloadTask[] {
    return this.getIndexedTasks(this.taskIdsByContent.get(contentId));
  }

  public getContentDownloadAggregate(contentId: string, type?: UnifiedDownloadType): ContentDownloadAggregate {
    const tasks = this.getTasksByContent(contentId);
    let activeCount = 0;
    let completedCount = 0;
    let failedCount = 0;
    let downloadedCount = 0;
    let totalCount = 0;
    let currentTitle = '';

    for (const task of tasks) {
      if (type !== undefined && task.type !== type) {
        continue;
      }

      if (task.status === UnifiedTaskStatus.PENDING || task.status === UnifiedTaskStatus.DOWNLOADING) {
        activeCount++;
        if (currentTitle.length === 0 && task.chapterTitle && task.chapterTitle.length > 0) {
          currentTitle = task.chapterTitle;
        }
      } else if (task.status === UnifiedTaskStatus.COMPLETED) {
        completedCount++;
      } else if (task.status === UnifiedTaskStatus.FAILED) {
        failedCount++;
      }

      downloadedCount += Math.max(0, task.downloadedCount);
      totalCount += Math.max(0, task.totalCount);
    }

    const aggregate: ContentDownloadAggregate = {
      activeCount: activeCount,
      completedCount: completedCount,
      failedCount: failedCount,
      downloadedCount: downloadedCount,
      totalCount: totalCount,
      currentTitle: currentTitle
    };
    return aggregate;
  }
  
  /**
   * 获取指定状态的下载任务
   */
  public getTasksByStatus(status: UnifiedTaskStatus): UnifiedDownloadTask[] {
    return this.getIndexedTasks(this.taskIdsByStatus.get(status));
  }
  
  /**
   * 获取单个任务
   */
  public getTask(taskId: string): UnifiedDownloadTask | undefined {
    return this.unifiedTasks.get(taskId);
  }
  
  /**
   * 获取活跃的下载任务数量
   */
  public getActiveTaskCount(): number {
    return this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.DOWNLOADING) +
      this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.PENDING);
  }
  
  // ==================== 回调管理 ====================
  
  /**
   * 注册任务回调
   */
  public registerCallback(taskId: string, callback: UnifiedDownloadCallback): void {
    this.callbacks.set(taskId, callback);
  }
  
  /**
   * 取消任务回调
   */
  public unregisterCallback(taskId: string): void {
    this.callbacks.delete(taskId);
  }
  
  /**
   * 注册全局回调（监听所有任务）
   */
  public registerGlobalCallback(callback: UnifiedDownloadCallback): void {
    this.globalCallbacks.add(callback);
  }
  
  /**
   * 取消全局回调
   */
  public unregisterGlobalCallback(callback: UnifiedDownloadCallback): void {
    this.globalCallbacks.delete(callback);
  }
  
  /**
   * 通知进度更新
   */
  private notifyProgress(task: UnifiedDownloadTask): void {
    const now = Date.now();
    const lastNotifyAt = this.lastProgressNotifyAtByTaskId.get(task.id) || 0;
    if (now - lastNotifyAt < this.PROGRESS_NOTIFY_INTERVAL_MS && task.status === UnifiedTaskStatus.DOWNLOADING) {
      return;
    }
    this.lastProgressNotifyAtByTaskId.set(task.id, now);

    // 任务特定回调
    const callback = this.callbacks.get(task.id);
    if (callback) {
      try {
        callback.onProgress(task);
      } catch (error) {
        logger.warn(TAG, `回调执行失败: ${String(error)}`);
      }
    }
    
    // 全局回调
    const globalCallbackSnapshot: UnifiedDownloadCallback[] = Array.from(this.globalCallbacks);
    for (const cb of globalCallbackSnapshot) {
      try {
        cb.onProgress(task);
      } catch (error) {
        logger.warn(TAG, `全局回调执行失败: ${String(error)}`);
      }
    }
  }

  private addTaskIdToIndex(index: Map<string, Set<string>>, key: string, taskId: string): void {
    let taskIds = index.get(key);
    if (!taskIds) {
      taskIds = new Set<string>();
      index.set(key, taskIds);
    }
    taskIds.add(taskId);
  }

  private removeTaskIdFromIndex(index: Map<string, Set<string>>, key: string, taskId: string): void {
    const taskIds = index.get(key);
    if (!taskIds) {
      return;
    }
    taskIds.delete(taskId);
    if (taskIds.size === 0) {
      index.delete(key);
    }
  }

  private addTaskToIndexes(task: UnifiedDownloadTask): void {
    this.addTaskIdToIndex(this.taskIdsByType, task.type, task.id);
    this.addTaskIdToIndex(this.taskIdsByContent, task.contentId, task.id);
    this.addTaskIdToIndex(this.taskIdsByStatus, task.status, task.id);
  }

  private removeTaskFromIndexes(task: UnifiedDownloadTask): void {
    this.removeTaskIdFromIndex(this.taskIdsByType, task.type, task.id);
    this.removeTaskIdFromIndex(this.taskIdsByContent, task.contentId, task.id);
    this.removeTaskIdFromIndex(this.taskIdsByStatus, task.status, task.id);
  }

  private registerUnifiedTask(task: UnifiedDownloadTask): void {
    const existingTask = this.unifiedTasks.get(task.id);
    if (existingTask) {
      this.removeTaskFromIndexes(existingTask);
    }
    this.unifiedTasks.set(task.id, task);
    this.addTaskToIndexes(task);
  }

  private findActiveMangaUnifiedTask(mangaId: string, sourceId: number, chapterId: string): UnifiedDownloadTask | null {
    const tasks = this.getTasksByContent(mangaId);
    for (const task of tasks) {
      if (
        task.type === UnifiedDownloadType.MANGA &&
        task.sourceId === sourceId &&
        task.chapterId === chapterId &&
        (task.status === UnifiedTaskStatus.PENDING || task.status === UnifiedTaskStatus.DOWNLOADING)
      ) {
        return task;
      }
    }
    return null;
  }

  private unregisterUnifiedTask(taskId: string): void {
    const task = this.unifiedTasks.get(taskId);
    if (task) {
      this.removeTaskFromIndexes(task);
      if (task.type === UnifiedDownloadType.MANGA) {
        this.mangaDownloadManager.unregisterProgressCallback(`unified_${taskId}`);
      }
    }
    this.unifiedTasks.delete(taskId);
    this.callbacks.delete(taskId);
    this.lastProgressNotifyAtByTaskId.delete(taskId);
  }

  private updateTaskStatus(task: UnifiedDownloadTask, status: UnifiedTaskStatus): void {
    if (task.status === status) {
      return;
    }
    this.removeTaskIdFromIndex(this.taskIdsByStatus, task.status, task.id);
    task.status = status;
    this.addTaskIdToIndex(this.taskIdsByStatus, task.status, task.id);
  }

  private getIndexedTasks(taskIds: Set<string> | undefined): UnifiedDownloadTask[] {
    const tasks: UnifiedDownloadTask[] = [];
    if (!taskIds) {
      return tasks;
    }
    for (const taskId of taskIds) {
      const task = this.unifiedTasks.get(taskId);
      if (task) {
        tasks.push(task);
      }
    }
    return tasks;
  }

  private getIndexedTaskCount(index: Map<string, Set<string>>, key: string): number {
    const taskIds = index.get(key);
    return taskIds ? taskIds.size : 0;
  }
  
  /**
   * 通知任务完成
   */
  private notifyComplete(task: UnifiedDownloadTask): void {
    this.lastProgressNotifyAtByTaskId.delete(task.id);
    const callback = this.callbacks.get(task.id);
    if (callback) {
      try {
        callback.onComplete(task);
      } catch (error) {
        logger.warn(TAG, `完成回调执行失败: ${String(error)}`);
      }
    }
    
    const globalCallbackSnapshot: UnifiedDownloadCallback[] = Array.from(this.globalCallbacks);
    for (const cb of globalCallbackSnapshot) {
      try {
        cb.onComplete(task);
      } catch (error) {
        logger.warn(TAG, `全局完成回调执行失败: ${String(error)}`);
      }
    }
  }
  
  /**
   * 通知任务错误
   */
  private notifyError(task: UnifiedDownloadTask, error: string): void {
    this.lastProgressNotifyAtByTaskId.delete(task.id);
    const callback = this.callbacks.get(task.id);
    if (callback) {
      try {
        callback.onError(task, error);
      } catch (err) {
        logger.warn(TAG, `错误回调执行失败: ${String(err)}`);
      }
    }
    
    const globalCallbackSnapshot: UnifiedDownloadCallback[] = Array.from(this.globalCallbacks);
    for (const cb of globalCallbackSnapshot) {
      try {
        cb.onError(task, error);
      } catch (err) {
        logger.warn(TAG, `全局错误回调执行失败: ${String(err)}`);
      }
    }
  }
  
  // ==================== 统计方法 ====================
  
  /**
   * 获取下载统计信息
   */
  public getDownloadStats(): DownloadStatsResult {
    const result: DownloadStatsResult = {
      total: this.unifiedTasks.size,
      pending: this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.PENDING),
      downloading: this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.DOWNLOADING),
      completed: this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.COMPLETED),
      failed: this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.FAILED),
      paused: this.getIndexedTaskCount(this.taskIdsByStatus, UnifiedTaskStatus.PAUSED)
    };
    return result;
  }
  
  /**
   * 清理已完成的任务
   */
  public clearCompletedTasks(): number {
    const completedIds: string[] = [];
    const completedTaskIds = this.taskIdsByStatus.get(UnifiedTaskStatus.COMPLETED);
    if (completedTaskIds) {
      for (const taskId of completedTaskIds) {
        completedIds.push(taskId);
      }
    }
    
    completedIds.forEach(id => {
      this.unregisterUnifiedTask(id);
    });
    
    logger.info(TAG, `已清理 ${completedIds.length} 个已完成任务`);
    return completedIds.length;
  }
  
  /**
   * 清理失败的任务
   */
  public clearFailedTasks(): number {
    const failedIds: string[] = [];
    const failedTaskIds = this.taskIdsByStatus.get(UnifiedTaskStatus.FAILED);
    if (failedTaskIds) {
      for (const taskId of failedTaskIds) {
        failedIds.push(taskId);
      }
    }
    
    failedIds.forEach(id => {
      this.unregisterUnifiedTask(id);
    });
    
    logger.info(TAG, `已清理 ${failedIds.length} 个失败任务`);
    return failedIds.length;
  }
}

/**
 * 获取统一下载管理器实例
 */
export function getUnifiedDownloadManager(): UnifiedDownloadManager {
  return UnifiedDownloadManager.getInstance();
}

export { PageListFetcher, DownloadPageItem };
