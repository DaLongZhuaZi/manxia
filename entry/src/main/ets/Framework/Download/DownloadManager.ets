/**
 * 下载管理器
 * 负责漫画章节的下载任务管理、队列控制、断点续传
 */

import request from '@ohos.request';
import { logger } from '../../Utils/Logger';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { DownloadDirManager } from '../Storage/DownloadDirManager';
import http from '@ohos.net.http';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppNotificationManager, NotificationType } from '../Managers/NotificationManager';
import { DataManager, DownloadTask, DownloadTaskInput, DownloadTaskUpdate } from '../Data/DataManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { UpdateRecordData } from '../Database/DatabaseTypes';
import { DownloadStatus } from '../Types/StatusEnums';

const TAG = 'DownloadManager';

/**
 * 下载任务状态
 */
export enum TaskStatus {
  PENDING = 'pending',      // 等待中
  DOWNLOADING = 'downloading', // 下载中
  PAUSED = 'paused',        // 已暂停
  COMPLETED = 'completed',  // 已完成
  FAILED = 'failed'         // 失败
}

/**
 * 下载任务类型
 */
export enum DownloadTaskType {
  MANGA_CHAPTER = 'manga_chapter',  // 漫画章节
  EBOOK = 'ebook'                   // 电子书
}

/**
 * 图片获取回调函数类型
 */
export type PageListFetcher = (chapterId: string, mangaId: string) => Promise<string[]>;

/**
 * 下载任务信息
 */
export interface DownloadTaskInfo {
  id: string;                    // 任务ID
  mangaId: string;               // 漫画ID
  chapterId: string;             // 章节ID
  chapterTitle: string;          // 章节标题
  mangaTitle: string;            // 漫画标题
  urls: string[];                // 图片URL列表
  savePath: string;              // 保存路径
  status: TaskStatus;            // 任务状态
  progress: number;              // 进度 (0-100)
  downloadedCount: number;       // 已下载数量
  totalCount: number;            // 总数量
  createdTime: number;           // 创建时间
  completedTime?: number;        // 完成时间
  error?: string;                // 错误信息
  isOnlineManga?: boolean;       // 是否为在线漫画（用于区分存储表）
  taskType?: DownloadTaskType;   // 任务类型
  fileFormat?: string;           // 电子书格式（epub/mobi/pdf等）
  sourceId?: number;             // 图源ID
  needFetchPages?: boolean;      // 是否需要先获取图片列表
  pageListFetcher?: PageListFetcher; // 图片列表获取函数
}

/**
 * 下载配置
 */
export interface DownloadConfig {
  maxConcurrent: number;         // 最大并发数
  retryCount: number;            // 重试次数
  timeout: number;               // 超时时间(ms)
}

/**
 * 下载进度回调类型
 */
export type DownloadProgressCallback = (taskId: string, chapterId: string, progress: number, downloadedCount: number, totalCount: number) => void;

/**
 * 下载管理器类
 */
export class MangaDownloadManager {
  private static instance: MangaDownloadManager;
  private context: common.UIAbilityContext | null = null;
  private tasks: Map<string, DownloadTaskInfo> = new Map();
  private downloadQueue: string[] = [];
  private activeDownloads: Set<string> = new Set();
  private notificationManager: AppNotificationManager;
  private dataManager: DataManager;
  private databaseManager: DatabaseManager;
  private downloadDirManager: DownloadDirManager;
  private usePublicDownloadDir: boolean = true;  // 是否使用公共Download目录
  private progressCallbacks: Map<string, DownloadProgressCallback> = new Map();  // 进度回调
  
  private config: DownloadConfig = {
    maxConcurrent: 3,
    retryCount: 3,
    timeout: 30000
  };

  private constructor() {
    this.notificationManager = AppNotificationManager.getInstance();
    this.dataManager = DataManager.getInstance();
    this.databaseManager = DatabaseManager.getInstance();
    this.downloadDirManager = DownloadDirManager.getInstance();
    logger.info(TAG, '下载管理器初始化');
  }

  public static getInstance(): MangaDownloadManager {
    if (!MangaDownloadManager.instance) {
      MangaDownloadManager.instance = new MangaDownloadManager();
    }
    return MangaDownloadManager.instance;
  }

  /**
   * 设置应用上下文
   */
  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
    this.downloadDirManager.setContext(context);
    logger.info(TAG, '应用上下文已设置');
  }

  /**
   * 设置是否使用公共Download目录
   */
  public setUsePublicDownloadDir(use: boolean): void {
    this.usePublicDownloadDir = use;
    logger.info(TAG, `使用公共Download目录: ${use}`);
  }

  /**
   * 检查Download目录是否已初始化
   */
  public isDownloadDirReady(): boolean {
    return this.downloadDirManager.isReady();
  }

  /**
   * 请求Download目录访问权限
   */
  public async requestDownloadDirAccess(): Promise<boolean> {
    return this.downloadDirManager.requestAccess();
  }

  /**
   * 注册下载进度回调
   * @param listenerId 监听器ID（用于取消注册）
   * @param callback 进度回调函数
   */
  public registerProgressCallback(listenerId: string, callback: DownloadProgressCallback): void {
    this.progressCallbacks.set(listenerId, callback);
    logger.debug(TAG, `注册进度回调: ${listenerId}`);
  }

  /**
   * 取消注册下载进度回调
   */
  public unregisterProgressCallback(listenerId: string): void {
    this.progressCallbacks.delete(listenerId);
    logger.debug(TAG, `取消进度回调: ${listenerId}`);
  }

  /**
   * 通知所有进度回调
   */
  private notifyProgressCallbacks(task: DownloadTaskInfo): void {
    this.progressCallbacks.forEach((callback: DownloadProgressCallback) => {
      try {
        callback(task.id, task.chapterId, task.progress, task.downloadedCount, task.totalCount);
      } catch (error) {
        logger.warn(TAG, `进度回调执行失败: ${String(error)}`);
      }
    });
  }

  /**
   * 创建下载任务（本地漫画，保存到应用私有目录）
   */
  public async createDownloadTask(
    mangaId: string,
    mangaTitle: string,
    chapterId: string,
    chapterTitle: string,
    imageUrls: string[]
  ): Promise<string> {
    try {
      if (!this.context) {
        throw new Error('应用上下文未设置');
      }

      // 生成任务ID
      const taskId = `${mangaId}_${chapterId}_${Date.now()}`;
      
      // 创建保存目录
      const savePath = `${this.context.filesDir}/downloads/${mangaId}/${chapterId}`;
      await this.ensureDirectory(savePath);

      // 创建任务信息
      const taskInfo: DownloadTaskInfo = {
        id: taskId,
        mangaId,
        chapterId,
        chapterTitle,
        mangaTitle,
        urls: imageUrls,
        savePath,
        status: TaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: imageUrls.length,
        createdTime: Date.now()
      };

      // 保存到内存
      this.tasks.set(taskId, taskInfo);
      
      // 保存到数据库
      await this.saveTaskToDatabase(taskInfo);

      // 添加到下载队列
      this.downloadQueue.push(taskId);
      
      logger.info(TAG, `下载任务已创建: ${taskId}, 章节: ${chapterTitle}, 图片数: ${imageUrls.length}`);
      
      // 开始处理队列
      this.processQueue();
      
      return taskId;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建下载任务失败: ${err.message}`);
      throw error  as Error;
    }
  }

  /**
   * 创建在线漫画下载任务（保存到公共Download目录）
   * @param mangaId 漫画ID
   * @param mangaTitle 漫画标题
   * @param chapterId 章节ID
   * @param chapterTitle 章节标题
   * @param imageUrls 图片URL列表
   * @param sourceId 图源ID
   * @param headers 请求头（用于需要认证的图源）
   */
  public async createOnlineMangaDownloadTask(
    mangaId: string,
    mangaTitle: string,
    chapterId: string,
    chapterTitle: string,
    imageUrls: string[],
    sourceId: number,
    headers?: Record<string, string>
  ): Promise<string> {
    try {
      if (!this.context) {
        throw new Error('应用上下文未设置');
      }

      // 检查Download目录是否已初始化
      if (this.usePublicDownloadDir && !this.downloadDirManager.isReady()) {
        // 尝试请求访问权限
        const granted = await this.downloadDirManager.requestAccess();
        if (!granted) {
          throw new Error('需要授权访问Download目录才能下载在线漫画');
        }
      }

      // 生成任务ID
      const taskId = `online_${mangaId}_${chapterId}_${Date.now()}`;
      
      // 确定保存路径
      let savePath: string;
      if (this.usePublicDownloadDir && this.downloadDirManager.isReady()) {
        // 使用公共Download目录
        savePath = this.downloadDirManager.getMangaDownloadPath(mangaTitle, chapterTitle);
        logger.info(TAG, `使用公共Download目录: ${savePath}`);
      } else {
        // 回退到应用私有目录
        savePath = `${this.context.filesDir}/downloads/online/${mangaId}/${chapterId}`;
        await this.ensureDirectory(savePath);
        logger.info(TAG, `使用应用私有目录: ${savePath}`);
      }

      // 创建任务信息
      const taskInfo: DownloadTaskInfo = {
        id: taskId,
        mangaId,
        chapterId,
        chapterTitle,
        mangaTitle,
        urls: imageUrls,
        savePath,
        status: TaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: imageUrls.length,
        createdTime: Date.now(),
        isOnlineManga: true,
        sourceId: sourceId
      };

      // 保存到内存
      this.tasks.set(taskId, taskInfo);
      
      // 保存到数据库
      await this.saveTaskToDatabase(taskInfo);

      // 添加到下载队列
      this.downloadQueue.push(taskId);
      
      logger.info(TAG, `在线漫画下载任务已创建: ${taskId}, 漫画: ${mangaTitle}, 章节: ${chapterTitle}, 图片数: ${imageUrls.length}`);
      
      // 开始处理队列
      this.processQueue();
      
      return taskId;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建在线漫画下载任务失败: ${err.message}`);
      throw error as Error;
    }
  }

  /**
   * 创建在线漫画下载任务（延迟获取图片列表）
   * 适用于在图源详情页下载时，还没有获取到章节图片数据的情况
   */
  public async createOnlineMangaDownloadTaskWithFetcher(
    mangaId: string,
    mangaTitle: string,
    chapterId: string,
    chapterTitle: string,
    sourceId: number,
    pageListFetcher: PageListFetcher
  ): Promise<string> {
    try {
      if (!this.context) {
        throw new Error('应用上下文未设置');
      }

      // 检查Download目录是否已初始化
      if (this.usePublicDownloadDir && !this.downloadDirManager.isReady()) {
        const granted = await this.downloadDirManager.requestAccess();
        if (!granted) {
          throw new Error('需要授权访问Download目录才能下载在线漫画');
        }
      }

      // 生成任务ID
      const taskId = `online_${mangaId}_${chapterId}_${Date.now()}`;
      
      // 确定保存路径
      let savePath: string;
      if (this.usePublicDownloadDir && this.downloadDirManager.isReady()) {
        savePath = this.downloadDirManager.getMangaDownloadPath(mangaTitle, chapterTitle);
        logger.info(TAG, `使用公共Download目录: ${savePath}`);
      } else {
        savePath = `${this.context.filesDir}/downloads/online/${mangaId}/${chapterId}`;
        logger.info(TAG, `使用应用私有目录: ${savePath}`);
      }

      // 创建任务信息（图片列表为空，需要在下载时获取）
      const taskInfo: DownloadTaskInfo = {
        id: taskId,
        mangaId,
        chapterId,
        chapterTitle,
        mangaTitle,
        urls: [],  // 空列表，下载时获取
        savePath,
        status: TaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: 0,  // 未知，下载时更新
        createdTime: Date.now(),
        isOnlineManga: true,
        sourceId: sourceId,
        needFetchPages: true,
        pageListFetcher: pageListFetcher
      };

      // 保存到内存
      this.tasks.set(taskId, taskInfo);
      
      // 保存到数据库
      await this.saveTaskToDatabase(taskInfo);

      // 添加到下载队列
      this.downloadQueue.push(taskId);
      
      logger.info(TAG, `在线漫画下载任务已创建(延迟获取): ${taskId}, 漫画: ${mangaTitle}, 章节: ${chapterTitle}`);
      
      // 开始处理队列
      this.processQueue();
      
      return taskId;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建在线漫画下载任务失败: ${err.message}`);
      throw error as Error;
    }
  }

  /**
   * 处理下载队列
   */
  private async processQueue(): Promise<void> {
    // 检查是否有空闲槽位
    while (this.activeDownloads.size < this.config.maxConcurrent && this.downloadQueue.length > 0) {
      const taskId = this.downloadQueue.shift();
      if (taskId && this.tasks.has(taskId)) {
        const task = this.tasks.get(taskId)!;
        if (task.status === TaskStatus.PENDING) {
          this.activeDownloads.add(taskId);
          // 根据任务类型分发到不同的下载方法
          if (task.taskType === DownloadTaskType.EBOOK) {
            this.downloadEBookTask(taskId).catch((error: Error) => {
              logger.error(TAG, `电子书下载任务执行失败: ${taskId}, ${error.message}`);
            });
          } else {
            this.downloadTask(taskId).catch((error: Error) => {
              logger.error(TAG, `下载任务执行失败: ${taskId}, ${error.message}`);
            });
          }
        }
      }
    }
  }

  /**
   * 下载单个任务
   */
  private async downloadTask(taskId: string): Promise<void> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return;
    }

    try {
      logger.info(TAG, `开始下载任务: ${taskId}`);
      task.status = TaskStatus.DOWNLOADING;
      await this.updateTaskInDatabase(task);

      // 如果需要先获取图片列表
      if (task.needFetchPages && task.pageListFetcher && task.urls.length === 0) {
        logger.info(TAG, `获取章节图片列表: ${task.chapterTitle}`);
        try {
          const imageUrls = await task.pageListFetcher(task.chapterId, task.mangaId);
          if (imageUrls.length === 0) {
            throw new Error('获取图片列表为空');
          }
          task.urls = imageUrls;
          task.totalCount = imageUrls.length;
          logger.info(TAG, `获取到 ${imageUrls.length} 张图片`);
          
          // 更新数据库中的任务信息
          await this.updateTaskInDatabase(task);
        } catch (fetchError) {
          logger.error(TAG, `获取图片列表失败: ${String(fetchError)}`);
          throw new Error(`获取图片列表失败: ${String(fetchError)}`);
        }
      }

      // 确保保存目录存在
      if (task.isOnlineManga && this.usePublicDownloadDir && this.downloadDirManager.isReady()) {
        await this.downloadDirManager.ensureDirectory(task.savePath);
      } else {
        await this.ensureDirectory(task.savePath);
      }

      // 下载所有图片
      for (let i = 0; i < task.urls.length; i++) {
        const url = task.urls[i];
        // 根据URL确定文件扩展名
        const ext = this.getFileExtension(url) || 'jpg';
        const fileName = `page_${String(i + 1).padStart(4, '0')}.${ext}`;
        const filePath = `${task.savePath}/${fileName}`;

        try {
          // 在线漫画使用HTTP下载，本地漫画使用系统下载API
          if (task.isOnlineManga) {
            await this.downloadFileWithHttp(url, filePath);
          } else {
            await this.downloadFile(url, filePath);
          }
          task.downloadedCount++;
          task.progress = Math.floor((task.downloadedCount / task.totalCount) * 100);
          
          // [重构] 根据任务类型更新不同的数据表
          try {
            if (task.isOnlineManga) {
              // 在线漫画：更新online_page表
              // 使用imageUrl来匹配，支持完整URL和短URL两种格式
              // PicaComic等图源的URL可能包含图片处理参数，需要提取基础URL
              const baseUrl = this.extractBaseImageUrl(url);
              const sql = 'UPDATE online_page SET localPath = ?, isDownloaded = 1 WHERE imageUrl = ? OR imageUrl LIKE ?';
              await this.databaseManager.executeSql(sql, [filePath, url, `%${baseUrl}%`]);
              logger.debug(TAG, `✅ 更新online_page本地路径: ${fileName} -> ${filePath}, baseUrl=${baseUrl.substring(0, 50)}...`);
            } else {
              // 本地漫画：更新page表
              const updateData: UpdateRecordData = {
                id: '', // 使用whereClause定位，id字段留空
                localPath: filePath
              };
              await this.databaseManager.update(
                'page',
                updateData,
                'chapterId = ? AND pageIndex = ?',
                [task.chapterId, String(i)]
              );
              logger.debug(TAG, `✅ 更新page本地路径: ${fileName} -> ${filePath}`);
            }
          } catch (dbErr) {
            logger.warn(TAG, `更新页面本地路径失败: ${String(dbErr)}`);
          }
          
          // 通知进度回调
          this.notifyProgressCallbacks(task);
          
          // 更新进度通知
          if (task.downloadedCount % 5 === 0 || task.downloadedCount === task.totalCount) {
            await this.notificationManager.sendDownloadProgressNotification(
              taskId,
              `${task.mangaTitle} - ${task.chapterTitle}`,
              task.downloadedCount,
              task.totalCount
            );
          }
          
          logger.debug(TAG, `图片下载成功: ${fileName}, 进度: ${task.progress}%`);
        } catch (error) {
          logger.error(TAG, `图片下载失败: ${fileName}, ${error}`);
          throw error as Error;
        }
      }

      // 下载完成
      task.status = TaskStatus.COMPLETED;
      task.progress = 100;
      task.completedTime = Date.now();
      await this.updateTaskInDatabase(task);
      
      // 更新章节下载状态
      await this.updateChapterDownloadStatus(task.chapterId, true, task.isOnlineManga || false);
      
      // 发送完成通知
      await this.notificationManager.sendDownloadCompleteNotification(
        taskId,
        `${task.mangaTitle} - ${task.chapterTitle}`
      );
      
      logger.info(TAG, `任务下载完成: ${taskId}`);
    } catch (error) {
      const err = error as Error;
      task.status = TaskStatus.FAILED;
      task.error = err.message;
      await this.updateTaskInDatabase(task);
      
      // 发送失败通知
      await this.notificationManager.sendDownloadFailedNotification(
        taskId,
        `${task.mangaTitle} - ${task.chapterTitle}`,
        err.message
      );
      
      logger.error(TAG, `任务下载失败: ${taskId}, ${err.message}`);
    } finally {
      // 从活动下载中移除
      this.activeDownloads.delete(taskId);
      
      // 继续处理队列
      this.processQueue();
    }
  }

  /**
   * 下载单个文件（使用系统下载API，仅支持应用私有目录）
   */
  private async downloadFile(url: string, filePath: string): Promise<void> {
    if (!this.context) {
      throw new Error('应用上下文未设置');
    }

    try {
      const downloadConfig: request.DownloadConfig = {
        url: url,
        filePath: filePath,
        enableMetered: true,
        enableRoaming: true
      };

      const downloadTask = await request.downloadFile(this.context, downloadConfig);
      
      return new Promise<void>((resolve, reject) => {
        downloadTask.on('complete', () => {
          logger.debug(TAG, `文件下载完成: ${filePath}`);
          resolve();
        });

        downloadTask.on('fail', (err: number) => {
          logger.error(TAG, `文件下载失败: ${filePath}, 错误码: ${err}`);
          reject(new Error(`下载失败: ${err}`));
        });
      });
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建下载任务失败: ${err.message}`);
      throw error  as Error;
    }
  }

  /**
   * 使用HTTP直接下载文件（支持写入任意目录，包括公共Download目录）
   */
  private async downloadFileWithHttp(
    url: string, 
    filePath: string, 
    headers?: Record<string, string>
  ): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const httpRequest = http.createHttp();
      
      // 构建请求头
      const requestHeaders: Record<string, string> = this.buildDownloadHeaders(headers);

      httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: requestHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000
      }).then((response: http.HttpResponse) => {
        if (response.responseCode === 200) {
          const data = response.result as ArrayBuffer;
          try {
            // 写入文件
            const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
            fs.writeSync(file.fd, data);
            fs.closeSync(file.fd);
            logger.debug(TAG, `HTTP下载完成: ${filePath}, 大小: ${data.byteLength}`);
            resolve();
          } catch (writeError) {
            logger.error(TAG, `写入文件失败: ${filePath}, ${String(writeError)}`);
            reject(new Error(`写入文件失败: ${String(writeError)}`));
          }
        } else {
          logger.error(TAG, `HTTP下载失败: ${url}, 状态码: ${response.responseCode}`);
          reject(new Error(`HTTP下载失败: ${response.responseCode}`));
        }
        httpRequest.destroy();
      }).catch((error: Error) => {
        logger.error(TAG, `HTTP请求失败: ${url}, ${error.message}`);
        httpRequest.destroy();
        reject(error);
      });
    });
  }

  /**
   * 暂停任务
   */
  public async pauseTask(taskId: string): Promise<boolean> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }

    if (task.status !== TaskStatus.DOWNLOADING) {
      logger.warn(TAG, `任务状态不允许暂停: ${task.status}`);
      return false;
    }

    task.status = TaskStatus.PAUSED;
    await this.updateTaskInDatabase(task);
    logger.info(TAG, `任务已暂停: ${taskId}`);
    return true;
  }

  /**
   * 恢复任务
   */
  public async resumeTask(taskId: string): Promise<boolean> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }

    if (task.status !== TaskStatus.PAUSED) {
      logger.warn(TAG, `任务状态不允许恢复: ${task.status}`);
      return false;
    }

    task.status = TaskStatus.PENDING;
    this.downloadQueue.push(taskId);
    await this.updateTaskInDatabase(task);
    this.processQueue();
    logger.info(TAG, `任务已恢复: ${taskId}`);
    return true;
  }

  /**
   * 删除任务
   */
  public async deleteTask(taskId: string): Promise<boolean> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return false;
    }

    try {
      // 删除文件
      await this.deleteDirectory(task.savePath);
      
      // 从内存中删除
      this.tasks.delete(taskId);
      this.activeDownloads.delete(taskId);
      
      // 从数据库删除
      await this.databaseManager.delete('download_tasks', 'id = ?', [taskId]);
      
      logger.info(TAG, `任务已删除: ${taskId}`);
      return true;
    } catch (error) {
      logger.error(TAG, `删除任务失败: ${taskId}, ${error}`);
      return false;
    }
  }

  /**
   * 获取任务信息
   */
  public getTask(taskId: string): DownloadTaskInfo | undefined {
    return this.tasks.get(taskId);
  }

  /**
   * 获取所有任务
   */
  public getAllTasks(): DownloadTaskInfo[] {
    return Array.from(this.tasks.values());
  }

  /**
   * 获取指定漫画的所有任务
   */
  public getTasksByManga(mangaId: string): DownloadTaskInfo[] {
    return Array.from(this.tasks.values()).filter((task: DownloadTaskInfo) => task.mangaId === mangaId);
  }

  /**
   * 更新章节下载状态
   * 在线漫画更新online_chapter表，本地漫画更新chapter_info表
   */
  private async updateChapterDownloadStatus(chapterId: string, isDownloaded: boolean, isOnlineManga: boolean = false): Promise<void> {
    try {
      if (isOnlineManga) {
        // 在线漫画：更新online_chapter表
        const sql = 'UPDATE online_chapter SET isDownloaded = ? WHERE id = ?';
        await this.databaseManager.executeSql(sql, [isDownloaded ? 1 : 0, chapterId]);
        logger.info(TAG, `✅ 在线章节下载状态已更新: ${chapterId}, isDownloaded=${isDownloaded}`);
      } else {
        // 本地漫画：更新chapter_info表
        const updateData: UpdateRecordData = {
          id: '', // 使用whereClause定位，id字段留空
          isDownloaded: isDownloaded
        };
        await this.databaseManager.update(
          'chapter_info',
          updateData,
          'id = ?',
          [chapterId]
        );
        logger.info(TAG, `✅ 章节下载状态已更新: ${chapterId}, isDownloaded=${isDownloaded}`);
      }
    } catch (error) {
      logger.error(TAG, `更新章节下载状态失败: ${String(error)}`);
    }
  }

  /**
   * 确保目录存在
   */
  private async ensureDirectory(dirPath: string): Promise<void> {
    try {
      const stat = fs.statSync(dirPath);
      if (!stat.isDirectory()) {
        throw new Error('路径不是目录');
      }
    } catch (error) {
      // 目录不存在，创建它
      fs.mkdirSync(dirPath, true);
      logger.debug(TAG, `目录已创建: ${dirPath}`);
    }
  }

  /**
   * 删除目录
   */
  private async deleteDirectory(dirPath: string): Promise<void> {
    try {
      fs.rmdirSync(dirPath);
      logger.debug(TAG, `目录已删除: ${dirPath}`);
    } catch (error) {
      logger.warn(TAG, `删除目录失败: ${dirPath}, ${error}`);
    }
  }

  /**
   * 构建下载请求头
   */
  private buildDownloadHeaders(customHeaders?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
    };
    if (customHeaders) {
      const keys = Object.keys(customHeaders);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        headers[key] = customHeaders[key];
      }
    }
    return headers;
  }

  /**
   * 提取图片URL的基础部分（去除图片处理参数）
   * PicaComic等图源的URL格式: https://storage-b.picacomic.com/static/tobeimg/xxx.../rs:fit:800:800:0/g:ce/...
   * 需要提取: xxx（基础标识符）
   */
  private extractBaseImageUrl(url: string): string {
    try {
      // 提取URL中的唯一标识符部分
      // 格式1: https://storage-b.picacomic.com/static/tobeimg/xxx
      // 格式2: https://storage-b.picacomic.com/static/tobeimg/xxx.../rs:fit:...
      const match = url.match(/\/static\/tobeimg\/([^\/]+)/);
      if (match && match[1]) {
        return match[1];
      }
      // 如果没有匹配到，返回URL的最后一段
      const segments = url.split('/');
      return segments[segments.length - 1].split('?')[0];
    } catch (error) {
      return url;
    }
  }

  /**
   * 从URL中提取文件扩展名
   */
  private getFileExtension(url: string): string {
    try {
      // 移除查询参数
      const urlWithoutQuery = url.split('?')[0];
      // 获取最后一个路径段
      const lastSegment = urlWithoutQuery.split('/').pop() || '';
      // 获取扩展名
      const lastDot = lastSegment.lastIndexOf('.');
      if (lastDot === -1) return 'jpg';
      const ext = lastSegment.substring(lastDot + 1).toLowerCase();
      // 验证是否为有效的图片扩展名
      const validExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'avif'];
      return validExtensions.includes(ext) ? ext : 'jpg';
    } catch (error) {
      return 'jpg';
    }
  }

  /**
   * 保存任务到数据库
   * 注意：在线漫画下载任务不保存到download_task表，因为主要数据在online_page表中
   */
  private async saveTaskToDatabase(task: DownloadTaskInfo): Promise<void> {
    // 在线漫画下载任务跳过download_task表操作
    if (task.isOnlineManga) {
      logger.debug(TAG, `在线漫画下载任务跳过数据库保存: ${task.id}`);
      return;
    }
    
    try {
      const taskInput: DownloadTaskInput = {
        comicId: task.mangaId,
        chapterId: task.chapterId,
        totalPages: task.totalCount,
        downloadedPages: task.downloadedCount,
        status: this.convertTaskStatusToDownloadStatus(task.status),
        progress: task.progress
      };
      
      const taskId = await this.dataManager.createDownloadTask(taskInput);
      // 更新内存中的任务ID为数据库生成的ID
      const oldId = task.id;
      task.id = taskId;
      this.tasks.delete(oldId);
      this.tasks.set(taskId, task);
      
      logger.debug(TAG, `任务已保存到数据库: ${task.id}`);
    } catch (error) {
      logger.error(TAG, `保存任务到数据库失败: ${error}`);
    }
  }

  /**
   * 更新数据库中的任务
   * 注意：在线漫画下载任务不更新download_task表
   */
  private async updateTaskInDatabase(task: DownloadTaskInfo): Promise<void> {
    // 在线漫画下载任务跳过download_task表操作
    if (task.isOnlineManga) {
      logger.debug(TAG, `在线漫画下载任务跳过数据库更新: ${task.id}, 状态: ${task.status}`);
      return;
    }
    
    try {
      const updateData: DownloadTaskUpdate = {
        downloadedPages: task.downloadedCount,
        progress: task.progress,
        status: this.convertTaskStatusToDownloadStatus(task.status)
      };
      
      await this.dataManager.updateDownloadTask(task.id, updateData);
      logger.debug(TAG, `任务已更新到数据库: ${task.id}`);
    } catch (error) {
      logger.error(TAG, `更新任务到数据库失败: ${error}`);
    }
  }

  /**
   * 转换任务状态到数据库状态
   */
  private convertTaskStatusToDownloadStatus(status: TaskStatus): DownloadStatus {
    switch (status) {
      case TaskStatus.PENDING:
        return DownloadStatus.PENDING;
      case TaskStatus.DOWNLOADING:
        return DownloadStatus.DOWNLOADING;
      case TaskStatus.PAUSED:
        return DownloadStatus.PAUSED;
      case TaskStatus.COMPLETED:
        return DownloadStatus.COMPLETED;
      case TaskStatus.FAILED:
        return DownloadStatus.FAILED;
      default:
        return DownloadStatus.PENDING;
    }
  }

  // ==================== 电子书下载支持 ====================

  /**
   * 创建电子书下载任务
   */
  public async createEBookDownloadTask(
    bookId: string,
    bookTitle: string,
    downloadUrl: string,
    fileFormat: string,
    sourceId?: number
  ): Promise<string> {
    try {
      if (!this.context) {
        throw new Error('应用上下文未设置');
      }

      // 生成任务ID
      const taskId = `ebook_${bookId}_${Date.now()}`;
      
      // 创建保存目录
      const savePath = `${this.context.filesDir}/ebooks/${bookId}`;
      await this.ensureDirectory(savePath);
      const filePath = `${savePath}/${bookTitle}.${fileFormat}`;

      // 创建任务信息
      const taskInfo: DownloadTaskInfo = {
        id: taskId,
        mangaId: bookId,
        chapterId: bookId,
        chapterTitle: fileFormat.toUpperCase(),
        mangaTitle: bookTitle,
        urls: [downloadUrl],
        savePath: filePath,
        status: TaskStatus.PENDING,
        progress: 0,
        downloadedCount: 0,
        totalCount: 1,
        createdTime: Date.now(),
        taskType: DownloadTaskType.EBOOK,
        fileFormat: fileFormat,
        sourceId: sourceId
      };

      // 保存到内存
      this.tasks.set(taskId, taskInfo);
      
      // 保存到数据库
      await this.saveTaskToDatabase(taskInfo);

      // 添加到下载队列
      this.downloadQueue.push(taskId);
      
      logger.info(TAG, `电子书下载任务已创建: ${taskId}, 书名: ${bookTitle}, 格式: ${fileFormat}`);
      
      // 开始处理队列
      this.processQueue();
      
      return taskId;
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建电子书下载任务失败: ${err.message}`);
      throw error as Error;
    }
  }

  /**
   * 下载电子书任务
   */
  private async downloadEBookTask(taskId: string): Promise<void> {
    const task = this.tasks.get(taskId);
    if (!task) {
      logger.warn(TAG, `任务不存在: ${taskId}`);
      return;
    }

    try {
      logger.info(TAG, `开始下载电子书: ${taskId}`);
      task.status = TaskStatus.DOWNLOADING;
      await this.updateTaskInDatabase(task);

      // 发送开始下载通知
      await this.notificationManager.sendDownloadProgressNotification(
        taskId,
        `${task.mangaTitle} (${task.fileFormat?.toUpperCase() || 'EBOOK'})`,
        0,
        100
      );

      // 下载文件
      const downloadUrl = task.urls[0];
      await this.downloadFileWithProgress(downloadUrl, task.savePath, (progress: number) => {
        task.progress = progress;
        // 每10%更新一次通知
        if (progress % 10 === 0) {
          this.notificationManager.sendDownloadProgressNotification(
            taskId,
            `${task.mangaTitle} (${task.fileFormat?.toUpperCase() || 'EBOOK'})`,
            progress,
            100
          );
        }
      });

      // 下载完成
      task.status = TaskStatus.COMPLETED;
      task.progress = 100;
      task.downloadedCount = 1;
      task.completedTime = Date.now();
      await this.updateTaskInDatabase(task);
      
      // 发送完成通知
      await this.notificationManager.sendDownloadCompleteNotification(
        taskId,
        `${task.mangaTitle} (${task.fileFormat?.toUpperCase() || 'EBOOK'})`
      );
      
      logger.info(TAG, `电子书下载完成: ${taskId}, 保存路径: ${task.savePath}`);
    } catch (error) {
      const err = error as Error;
      task.status = TaskStatus.FAILED;
      task.error = err.message;
      await this.updateTaskInDatabase(task);
      
      // 发送失败通知
      await this.notificationManager.sendDownloadFailedNotification(
        taskId,
        `${task.mangaTitle} (${task.fileFormat?.toUpperCase() || 'EBOOK'})`,
        err.message
      );
      
      logger.error(TAG, `电子书下载失败: ${taskId}, ${err.message}`);
    } finally {
      // 从活动下载中移除
      this.activeDownloads.delete(taskId);
      
      // 继续处理队列
      this.processQueue();
    }
  }

  /**
   * 带进度回调的文件下载
   */
  private async downloadFileWithProgress(
    url: string, 
    filePath: string, 
    onProgress: (progress: number) => void
  ): Promise<void> {
    if (!this.context) {
      throw new Error('应用上下文未设置');
    }

    try {
      const downloadConfig: request.DownloadConfig = {
        url: url,
        filePath: filePath,
        enableMetered: true,
        enableRoaming: true
      };

      const downloadTask = await request.downloadFile(this.context, downloadConfig);
      
      return new Promise<void>((resolve, reject) => {
        downloadTask.on('progress', (receivedSize: number, totalSize: number) => {
          if (totalSize > 0) {
            const progress = Math.floor((receivedSize / totalSize) * 100);
            onProgress(progress);
          }
        });

        downloadTask.on('complete', () => {
          logger.debug(TAG, `电子书下载完成: ${filePath}`);
          onProgress(100);
          resolve();
        });

        downloadTask.on('fail', (err: number) => {
          logger.error(TAG, `电子书下载失败: ${filePath}, 错误码: ${err}`);
          reject(new Error(`下载失败: ${err}`));
        });
      });
    } catch (error) {
      const err = error as BusinessError;
      logger.error(TAG, `创建下载任务失败: ${err.message}`);
      throw error as Error;
    }
  }

  /**
   * 获取电子书下载任务列表
   */
  public getEBookTasks(): DownloadTaskInfo[] {
    return Array.from(this.tasks.values()).filter(
      (task: DownloadTaskInfo) => task.taskType === DownloadTaskType.EBOOK
    );
  }

  /**
   * 获取指定电子书的下载任务
   */
  public getEBookTask(bookId: string): DownloadTaskInfo | undefined {
    return Array.from(this.tasks.values()).find(
      (task: DownloadTaskInfo) => task.taskType === DownloadTaskType.EBOOK && task.mangaId === bookId
    );
  }

  /**
   * 检查电子书是否已下载
   */
  public isEBookDownloaded(bookId: string): boolean {
    const task = this.getEBookTask(bookId);
    return task?.status === TaskStatus.COMPLETED;
  }

  /**
   * 获取电子书本地路径
   */
  public getEBookLocalPath(bookId: string): string | undefined {
    const task = this.getEBookTask(bookId);
    if (task?.status === TaskStatus.COMPLETED) {
      return task.savePath;
    }
    return undefined;
  }
}

// 导出单例
export default MangaDownloadManager.getInstance();
