/**
 * 小说章节缓存管理器
 * 负责章节内容的缓存、下载和离线阅读支持
 * 
 * 缓存存储结构：
 * /files/novels/{bookId}/
 *   ├── metadata.json     # 书籍元数据
 *   ├── chapters/
 *   │   ├── 0001.txt      # 第1章内容
 *   │   ├── 0002.txt      # 第2章内容
 *   │   └── ...
 *   └── cache_info.json   # 缓存信息
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelChapterCacheManager.ets
 */

import { logger } from '../../Utils/Logger';
import { getNovelDataManager } from './NovelDataManager';
import { getNovelSourceManager } from './NovelSourceManager';
import { LegadoChapter } from './LegadoSourceTypes';
import { NovelDownloadTask, NovelCacheInfo, BookMetadata } from '../../Models/NovelModels';
import { AppNotificationManager } from '../Managers/NotificationManager';
import { SandboxManager } from '../Storage/SandboxManager';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'NovelChapterCacheManager';

/**
 * 下载任务状态
 */
export type DownloadTaskStatus = 'pending' | 'downloading' | 'paused' | 'completed' | 'failed';

/**
 * 下载进度回调
 */
export interface DownloadProgressCallback {
  onProgress: (current: number, total: number, chapterTitle: string) => void;
  onComplete: () => void;
  onError: (error: string) => void;
}

/**
 * 小说章节缓存管理器类
 */
export class NovelChapterCacheManager {
  private static instance: NovelChapterCacheManager | null = null;
  private dataManager = getNovelDataManager();
  private sourceManager = getNovelSourceManager();
  private notificationManager = AppNotificationManager.getInstance();
  private sandboxManager = SandboxManager.getInstance();
  private downloadTasks: Map<string, NovelDownloadTask> = new Map();
  private activeDownloads: Set<string> = new Set();
  private maxConcurrentDownloads: number = 3;
  private downloadCallbacks: Map<string, DownloadProgressCallback> = new Map();
  
  // 小说缓存根目录
  private novelsCacheDir: string = '';
  private isInitialized: boolean = false;
  private initPromise: Promise<void> | null = null;

  private constructor() {
    // 启动初始化但不等待
    this.initPromise = this.initCacheDir();
  }
  
  /**
   * 初始化缓存目录
   */
  private async initCacheDir(): Promise<void> {
    if (this.isInitialized) return;
    
    try {
      const filesDir = this.sandboxManager.getDirectory('files');
      this.novelsCacheDir = `${filesDir}/novels`;
      await this.sandboxManager.createDirectory(this.novelsCacheDir);
      this.isInitialized = true;
      logger.info(TAG, `小说缓存目录初始化: ${this.novelsCacheDir}`);
    } catch (error) {
      logger.error(TAG, `初始化缓存目录失败: ${String(error)}`);
    }
  }
  
  /**
   * 确保缓存目录已初始化
   */
  private async ensureInitialized(): Promise<void> {
    if (this.isInitialized) return;
    if (this.initPromise) {
      await this.initPromise;
    } else {
      await this.initCacheDir();
    }
  }

  static getInstance(): NovelChapterCacheManager {
    if (!NovelChapterCacheManager.instance) {
      NovelChapterCacheManager.instance = new NovelChapterCacheManager();
    }
    return NovelChapterCacheManager.instance;
  }

  /**
   * 获取书籍缓存目录路径
   * 格式: /files/novels/{safeBookId}/
   */
  private getBookCacheDir(bookId: string): string {
    // 将bookId转换为安全的目录名（移除特殊字符）
    const safeBookId = this.sanitizeFileName(bookId);
    return `${this.novelsCacheDir}/${safeBookId}`;
  }
  
  /**
   * 获取章节文件路径
   * 格式: /files/novels/{safeBookId}/chapters/{chapterIndex}.txt
   */
  private getChapterFilePath(bookId: string, chapterIndex: number): string {
    const bookDir = this.getBookCacheDir(bookId);
    // 使用4位数字格式化章节索引，如 0001.txt, 0002.txt
    const chapterFileName = String(chapterIndex + 1).padStart(4, '0') + '.txt';
    return `${bookDir}/chapters/${chapterFileName}`;
  }
  
  /**
   * 将字符串转换为安全的文件名
   */
  private sanitizeFileName(name: string): string {
    // 移除或替换不安全的字符
    return name
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/%/g, '_')
      .replace(/\s+/g, '_')
      .substring(0, 100); // 限制长度
  }

  /**
   * 缓存单个章节内容（保存为txt文件）
   */
  async cacheChapter(
    sourceId: string,
    bookId: string,
    chapter: LegadoChapter
  ): Promise<boolean> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      // 检查是否已缓存
      const cached = await this.getChapterCache(bookId, chapter.index);
      if (cached) {
        logger.debug(TAG, `章节已缓存: ${chapter.title}`);
        return true;
      }

      // 获取章节内容
      const content = await this.sourceManager.getContent(sourceId, chapter);
      if (!content) {
        logger.warn(TAG, `获取章节内容失败: ${chapter.title}`);
        return false;
      }

      // 保存到txt文件
      await this.saveChapterToFile(bookId, chapter.index, chapter.title, content);

      logger.info(TAG, `章节缓存成功: ${chapter.title}`);
      return true;
    } catch (error) {
      logger.error(TAG, `缓存章节失败: ${chapter.title}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 检查章节是否已缓存（检查txt文件是否存在）
   */
  async isChapterCached(bookId: string, chapterIndex: number): Promise<boolean> {
    try {
      const filePath = this.getChapterFilePath(bookId, chapterIndex);
      return await this.sandboxManager.exists(filePath);
    } catch (error) {
      return false;
    }
  }

  /**
   * 获取已缓存的章节索引列表（扫描chapters目录）
   */
  async getCachedChapterIndexes(bookId: string, totalChapters: number): Promise<Set<number>> {
    const cachedIndexes = new Set<number>();
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      const bookDir = this.getBookCacheDir(bookId);
      const chaptersDir = `${bookDir}/chapters`;
      
      // 检查目录是否存在
      if (!await this.sandboxManager.exists(chaptersDir)) {
        return cachedIndexes;
      }
      
      // 列出目录中的所有txt文件
      const files = await fileIo.listFile(chaptersDir);
      for (const file of files) {
        if (file.endsWith('.txt')) {
          // 从文件名提取章节索引（0001.txt -> 0）
          const indexStr = file.replace('.txt', '');
          const index = parseInt(indexStr, 10) - 1; // 文件名是1-based，索引是0-based
          if (!isNaN(index) && index >= 0 && index < totalChapters) {
            cachedIndexes.add(index);
          }
        }
      }
      
      logger.debug(TAG, `书籍 ${bookId} 已缓存 ${cachedIndexes.size} 章`);
    } catch (error) {
      logger.error(TAG, `获取缓存章节列表失败: ${String(error)}`);
    }
    return cachedIndexes;
  }

  /**
   * 获取章节缓存内容（从txt文件读取）
   * @param bookIdOrChapterId 可以是bookId或旧格式的chapterId
   * @param chapterIndex 章节索引（如果第一个参数是bookId）
   */
  async getChapterCache(bookIdOrChapterId: string, chapterIndex?: number): Promise<string | null> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      let bookId: string;
      let index: number;
      
      if (chapterIndex !== undefined) {
        // 新格式：bookId + chapterIndex
        bookId = bookIdOrChapterId;
        index = chapterIndex;
      } else {
        // 旧格式兼容：chapterId = bookId_chapterIndex
        const parts = bookIdOrChapterId.split('_');
        if (parts.length < 2) {
          logger.warn(TAG, `无效的chapterId格式: ${bookIdOrChapterId}`);
          return null;
        }
        index = parseInt(parts[parts.length - 1], 10);
        bookId = parts.slice(0, -1).join('_');
      }
      
      const filePath = this.getChapterFilePath(bookId, index);
      
      // 检查文件是否存在
      if (!await this.sandboxManager.exists(filePath)) {
        logger.debug(TAG, `缓存未命中: ${filePath}`);
        return null;
      }
      
      // 读取txt文件内容
      const content = await this.sandboxManager.readTextFile(filePath);
      logger.info(TAG, `✅ 缓存命中: ${filePath}, 内容长度=${content?.length || 0}`);
      return content;
    } catch (error) {
      logger.error(TAG, `获取章节缓存失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 保存章节内容到txt文件
   */
  private async saveChapterToFile(
    bookId: string,
    chapterIndex: number,
    chapterTitle: string,
    content: string
  ): Promise<void> {
    try {
      const bookDir = this.getBookCacheDir(bookId);
      const chaptersDir = `${bookDir}/chapters`;
      
      // 确保目录存在
      await this.sandboxManager.createDirectory(chaptersDir);
      
      // 构建文件内容（包含章节标题）
      const fileContent = `${chapterTitle}\n\n${content}`;
      
      // 写入txt文件
      const filePath = this.getChapterFilePath(bookId, chapterIndex);
      await this.sandboxManager.writeFile(filePath, fileContent);
      
      logger.debug(TAG, `章节保存成功: ${filePath}`);
    } catch (error) {
      logger.error(TAG, `保存章节文件失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 创建下载任务
   */
  createDownloadTask(
    bookId: string,
    bookName: string,
    startIndex: number,
    endIndex: number
  ): string {
    const taskId = `download_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    const now = Date.now();

    const task: NovelDownloadTask = {
      id: taskId,
      bookId: bookId,
      bookName: bookName,
      startChapterIndex: startIndex,
      endChapterIndex: endIndex,
      currentChapterIndex: startIndex,
      status: 'pending',
      progress: 0,
      createTime: now,
      updateTime: now
    };

    this.downloadTasks.set(taskId, task);
    logger.info(TAG, `创建下载任务: ${bookName}, 章节 ${startIndex}-${endIndex}`);
    return taskId;
  }

  /**
   * 开始下载任务
   */
  async startDownload(
    taskId: string,
    sourceId: string,
    chapters: LegadoChapter[],
    callback?: DownloadProgressCallback
  ): Promise<void> {
    const task = this.downloadTasks.get(taskId);
    if (!task) {
      logger.error(TAG, `下载任务不存在: ${taskId}`);
      return;
    }

    if (this.activeDownloads.has(taskId)) {
      logger.warn(TAG, `下载任务已在进行中: ${taskId}`);
      return;
    }

    if (callback) {
      this.downloadCallbacks.set(taskId, callback);
    }

    task.status = 'downloading';
    this.activeDownloads.add(taskId);

    try {
      const startIdx = task.startChapterIndex;
      const endIdx = Math.min(task.endChapterIndex, chapters.length - 1);
      const total = endIdx - startIdx + 1;
      let successCount = 0;
      let failCount = 0;

      for (let i = startIdx; i <= endIdx; i++) {
        // 检查任务是否被暂停或取消
        const currentTask = this.downloadTasks.get(taskId);
        if (!currentTask || currentTask.status === 'paused') {
          logger.info(TAG, `下载任务已暂停: ${taskId}`);
          break;
        }

        const chapter = chapters[i];
        if (!chapter) continue;

        // 下载章节
        const success = await this.cacheChapter(sourceId, task.bookId, chapter);
        
        task.currentChapterIndex = i;
        task.progress = ((i - startIdx + 1) / total) * 100;
        task.updateTime = Date.now();

        if (success) {
          successCount++;
          // 回调进度
          const cb = this.downloadCallbacks.get(taskId);
          if (cb) {
            cb.onProgress(i - startIdx + 1, total, chapter.title);
          }
        } else {
          failCount++;
          logger.warn(TAG, `章节下载失败: ${chapter.title} (${failCount}/${total})`);
        }

        // 添加延迟避免请求过快
        await this.delay(500);
      }

      // 完成下载（即使有部分失败也标记为完成）
      if (failCount > 0 && failCount === total) {
        // 全部失败
        task.status = 'failed';
        task.errorMessage = `全部 ${failCount} 章下载失败`;
        logger.error(TAG, `下载任务失败: ${task.bookName}, 全部 ${failCount} 章下载失败`);
        
        // 发送失败通知
        this.notificationManager.sendDownloadFailedNotification(
          taskId, 
          task.bookName, 
          `全部 ${failCount} 章下载失败`
        );
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onError(`全部 ${failCount} 章下载失败`);
        }
      } else if (failCount > 0) {
        // 部分失败
        task.status = 'completed';
        task.progress = 100;
        task.errorMessage = `${failCount} 章下载失败`;
        logger.warn(TAG, `下载任务完成（部分失败）: ${task.bookName}, 成功 ${successCount}/${total}, 失败 ${failCount}`);
        
        // 发送完成通知（带警告）
        this.notificationManager.sendDownloadCompleteNotification(
          taskId, 
          `${task.bookName} (${failCount}章失败)`
        );
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onComplete();
        }
      } else {
        // 全部成功
        task.status = 'completed';
        task.progress = 100;
        logger.info(TAG, `下载任务完成: ${task.bookName}, 成功 ${successCount}/${total}`);
        
        // 发送完成通知
        this.notificationManager.sendDownloadCompleteNotification(taskId, task.bookName);
        
        const cb = this.downloadCallbacks.get(taskId);
        if (cb) {
          cb.onComplete();
        }
      }
      task.updateTime = Date.now();
    } catch (error) {
      task.status = 'failed';
      task.errorMessage = String(error);
      task.updateTime = Date.now();

      // 发送失败通知
      this.notificationManager.sendDownloadFailedNotification(taskId, task.bookName, String(error));

      const cb = this.downloadCallbacks.get(taskId);
      if (cb) {
        cb.onError(String(error));
      }

      logger.error(TAG, `下载任务失败: ${String(error)}`);
    } finally {
      this.activeDownloads.delete(taskId);
    }
  }

  /**
   * 暂停下载任务
   */
  pauseDownload(taskId: string): void {
    const task = this.downloadTasks.get(taskId);
    if (task && task.status === 'downloading') {
      task.status = 'paused';
      task.updateTime = Date.now();
      logger.info(TAG, `下载任务已暂停: ${taskId}`);
    }
  }

  /**
   * 取消下载任务
   */
  cancelDownload(taskId: string): void {
    const task = this.downloadTasks.get(taskId);
    if (task) {
      task.status = 'failed';
      task.errorMessage = '用户取消';
      task.updateTime = Date.now();
      this.activeDownloads.delete(taskId);
      this.downloadCallbacks.delete(taskId);
      logger.info(TAG, `下载任务已取消: ${taskId}`);
    }
  }

  /**
   * 获取下载任务状态
   */
  getDownloadTask(taskId: string): NovelDownloadTask | undefined {
    return this.downloadTasks.get(taskId);
  }

  /**
   * 获取所有下载任务
   */
  getAllDownloadTasks(): NovelDownloadTask[] {
    return Array.from(this.downloadTasks.values());
  }

  /**
   * 获取书籍缓存信息（从文件系统读取）
   */
  async getBookCacheInfo(bookId: string): Promise<NovelCacheInfo> {
    try {
      const bookDir = this.getBookCacheDir(bookId);
      const chaptersDir = `${bookDir}/chapters`;
      
      // 检查目录是否存在
      if (!await this.sandboxManager.exists(chaptersDir)) {
        return {
          bookId: bookId,
          cachedChapterCount: 0,
          totalChapterCount: 0,
          cacheSize: 0,
          lastCacheTime: 0
        };
      }
      
      // 统计缓存信息
      const files = await fileIo.listFile(chaptersDir);
      let cachedCount = 0;
      let cacheSize = 0;
      let lastCacheTime = 0;
      
      for (const file of files) {
        if (file.endsWith('.txt')) {
          cachedCount++;
          const filePath = `${chaptersDir}/${file}`;
          try {
            const stat = await fileIo.stat(filePath);
            cacheSize += stat.size;
            if (stat.mtime > lastCacheTime) {
              lastCacheTime = stat.mtime;
            }
          } catch (e) {
            // 忽略单个文件的错误
          }
        }
      }

      return {
        bookId: bookId,
        cachedChapterCount: cachedCount,
        totalChapterCount: 0, // 需要从其他地方获取
        cacheSize: cacheSize,
        lastCacheTime: lastCacheTime
      };
    } catch (error) {
      logger.error(TAG, `获取缓存信息失败: ${String(error)}`);
      return {
        bookId: bookId,
        cachedChapterCount: 0,
        totalChapterCount: 0,
        cacheSize: 0,
        lastCacheTime: 0
      };
    }
  }

  /**
   * 清理过期缓存（基于文件修改时间）
   * 默认清理30天未访问的缓存
   */
  async cleanExpiredCache(maxAgeDays: number = 30): Promise<number> {
    try {
      const expireTime = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
      let count = 0;
      
      // 检查novels目录是否存在
      if (!await this.sandboxManager.exists(this.novelsCacheDir)) {
        return 0;
      }
      
      // 遍历所有书籍目录
      const bookDirs = await fileIo.listFile(this.novelsCacheDir);
      for (const bookDir of bookDirs) {
        const chaptersDir = `${this.novelsCacheDir}/${bookDir}/chapters`;
        if (!await this.sandboxManager.exists(chaptersDir)) {
          continue;
        }
        
        const files = await fileIo.listFile(chaptersDir);
        for (const file of files) {
          if (file.endsWith('.txt')) {
            const filePath = `${chaptersDir}/${file}`;
            try {
              const stat = await fileIo.stat(filePath);
              if (stat.mtime < expireTime) {
                await fileIo.unlink(filePath);
                count++;
              }
            } catch (e) {
              // 忽略单个文件的错误
            }
          }
        }
      }

      logger.info(TAG, `清理过期缓存: ${count} 个文件`);
      return count;
    } catch (error) {
      logger.error(TAG, `清理过期缓存失败: ${String(error)}`);
      return 0;
    }
  }

  /**
   * 清理指定书籍的缓存（删除整个书籍目录）
   */
  async clearBookCache(bookId: string): Promise<void> {
    try {
      const bookDir = this.getBookCacheDir(bookId);
      
      // 检查目录是否存在
      if (await this.sandboxManager.exists(bookDir)) {
        await this.sandboxManager.deleteDirectory(bookDir);
        logger.info(TAG, `清理书籍缓存: ${bookDir}`);
      }
    } catch (error) {
      logger.error(TAG, `清理书籍缓存失败: ${String(error)}`);
    }
  }
  
  /**
   * 保存书籍元数据
   */
  async saveBookMetadata(bookId: string, bookName: string, author: string, coverUrl: string): Promise<void> {
    try {
      // 确保缓存目录已初始化
      await this.ensureInitialized();
      
      const bookDir = this.getBookCacheDir(bookId);
      await this.sandboxManager.createDirectory(bookDir);
      
      const metadata: BookMetadata = {
        bookId: bookId,
        bookName: bookName,
        author: author,
        coverUrl: coverUrl,
        createTime: Date.now(),
        updateTime: Date.now()
      };
      
      const metadataPath = `${bookDir}/metadata.json`;
      await this.sandboxManager.writeFile(metadataPath, JSON.stringify(metadata, null, 2));
      logger.debug(TAG, `保存书籍元数据: ${metadataPath}`);
    } catch (error) {
      logger.error(TAG, `保存书籍元数据失败: ${String(error)}`);
    }
  }
  
  /**
   * 获取缓存目录路径（供外部使用）
   */
  getCacheDirectory(): string {
    return this.novelsCacheDir;
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

export function getNovelChapterCacheManager(): NovelChapterCacheManager {
  return NovelChapterCacheManager.getInstance();
}
