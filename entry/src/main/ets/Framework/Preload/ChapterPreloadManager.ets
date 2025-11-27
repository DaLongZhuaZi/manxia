/**
 * 章节预加载管理器
 * 负责在漫画详情页后台预加载章节的页面列表和首图
 */
import { logger } from '../../Utils/Logger';
import { MangaSourceEngine } from '../WebView/MangaSourceEngine';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { DataManager } from '../Data/DataManager';
import { ImageCacheManager } from '../Cache/ImageCacheManager';
import { PageInfo } from '../WebView/MangaSourceTypes';

const TAG = 'ChapterPreloadManager';

/**
 * 预加载任务状态
 */
export enum PreloadStatus {
  PENDING = 'pending',       // 等待中
  LOADING = 'loading',       // 加载中
  COMPLETED = 'completed',   // 已完成
  FAILED = 'failed'          // 失败
}

/**
 * 预加载任务
 */
export interface PreloadTask {
  chapterId: string;           // 章节ID（内部ID）
  externalChapterId: string;   // 外部章节ID
  chapterTitle: string;        // 章节标题
  status: PreloadStatus;       // 任务状态
  pageCount: number;           // 页面总数
  preloadedPages: number;      // 已预加载的页面数
  startTime?: number;          // 开始时间
  endTime?: number;            // 结束时间
  error?: string;              // 错误信息
}

/**
 * 预加载配置
 */
export interface PreloadConfig {
  maxConcurrentTasks: number;  // 最大并发任务数
  preloadPageCount: number;    // 每个章节预加载的页面数（首N页）
  enabled: boolean;            // 是否启用预加载
}

/**
 * 章节信息
 */
export interface ChapterInfo {
  id: string;
  externalId: string;
  title: string;
}

/**
 * 章节预加载管理器（单例）
 */
export class ChapterPreloadManager {
  private static instance: ChapterPreloadManager;
  
  private tasks: Map<string, PreloadTask> = new Map();
  private activeTaskCount: number = 0;
  private config: PreloadConfig = {
    maxConcurrentTasks: 1,     // 默认同时只处理1个任务，避免占用过多资源
    preloadPageCount: 3,       // 默认预加载前3页
    enabled: true
  };
  
  private isReaderActive: boolean = false;  // 阅读器是否活跃
  private currentMangaId: string = '';      // 当前漫画ID
  private currentSourceId: number = 0;      // 当前图源ID
  private currentSourceName: string = '';   // 当前图源名称（【关键】用于确保图源正确）
  
  private constructor() {}
  
  public static getInstance(): ChapterPreloadManager {
    if (!ChapterPreloadManager.instance) {
      ChapterPreloadManager.instance = new ChapterPreloadManager();
    }
    return ChapterPreloadManager.instance;
  }
  
  /**
   * 设置预加载配置
   */
  public setConfig(config: PreloadConfig): void {
    if (config.maxConcurrentTasks !== undefined) {
      this.config.maxConcurrentTasks = config.maxConcurrentTasks;
    }
    if (config.preloadPageCount !== undefined) {
      this.config.preloadPageCount = config.preloadPageCount;
    }
    if (config.enabled !== undefined) {
      this.config.enabled = config.enabled;
    }
    logger.info(TAG, `预加载配置已更新: ${JSON.stringify(this.config)}`);
  }
  
  /**
   * 设置阅读器活跃状态
   */
  public setReaderActive(active: boolean): void {
    this.isReaderActive = active;
    logger.info(TAG, `阅读器活跃状态: ${active}`);
    
    // 如果阅读器激活，暂停所有预加载任务
    if (active) {
      logger.info(TAG, '阅读器已激活，暂停预加载任务');
    } else {
      // 阅读器关闭，可以恢复预加载
      logger.info(TAG, '阅读器已关闭，可以恢复预加载');
      this.processNextTask();
    }
  }
  
  /**
   * 停止预加载（离开详情页时调用）
   */
  public stopPreload(): void {
    logger.info(TAG, '停止预加载，清除所有任务');
    this.clearAllTasks();
    this.currentMangaId = '';
    this.currentSourceId = 0;
    this.currentSourceName = '';
  }
  
  /**
   * 开始预加载章节列表
   * @param mangaId 漫画ID
   * @param externalMangaId 外部漫画ID
   * @param sourceId 图源ID
   * @param sourceName 图源名称（【关键】用于确保图源正确）
   * @param chapters 要预加载的章节列表（按顺序）
   */
  public async startPreload(
    mangaId: string,
    externalMangaId: string,
    sourceId: number,
    sourceName: string,
    chapters: ChapterInfo[]
  ): Promise<void> {
    if (!this.config.enabled) {
      logger.info(TAG, '预加载已禁用');
      return;
    }
    
    this.currentMangaId = mangaId;
    this.currentSourceId = sourceId;
    this.currentSourceName = sourceName;
    
    logger.info(TAG, `🔄 开始预加载 ${chapters.length} 个章节: sourceName="${sourceName}", sourceId=${sourceId}`);
    
    // 创建预加载任务
    for (const chapter of chapters) {
      if (!this.tasks.has(chapter.id)) {
        const task: PreloadTask = {
          chapterId: chapter.id,
          externalChapterId: chapter.externalId,
          chapterTitle: chapter.title,
          status: PreloadStatus.PENDING,
          pageCount: 0,
          preloadedPages: 0
        };
        this.tasks.set(chapter.id, task);
        logger.debug(TAG, `创建预加载任务: ${chapter.title}`);
      }
    }
    
    // 开始处理任务
    this.processNextTask();
  }
  
  /**
   * 处理下一个任务
   */
  private async processNextTask(): Promise<void> {
    // 如果阅读器活跃，不处理新任务
    if (this.isReaderActive) {
      logger.debug(TAG, '阅读器活跃中，跳过预加载');
      return;
    }
    
    // 如果已达到最大并发数，等待
    if (this.activeTaskCount >= this.config.maxConcurrentTasks) {
      logger.debug(TAG, `已达到最大并发数 ${this.config.maxConcurrentTasks}，等待`);
      return;
    }
    
    // 查找下一个待处理任务
    let nextTask: PreloadTask | null = null;
    for (const task of this.tasks.values()) {
      if (task.status === PreloadStatus.PENDING) {
        nextTask = task;
        break;
      }
    }
    
    if (!nextTask) {
      logger.info(TAG, '所有预加载任务已完成');
      return;
    }
    
    // 执行任务
    this.activeTaskCount++;
    await this.executeTask(nextTask);
    this.activeTaskCount--;
    
    // 继续处理下一个任务
    setTimeout(() => this.processNextTask(), 100);
  }
  
  /**
   * 执行预加载任务
   */
  private async executeTask(task: PreloadTask): Promise<void> {
    task.status = PreloadStatus.LOADING;
    task.startTime = Date.now();
    
    logger.info(TAG, `开始预加载章节: ${task.chapterTitle}`);
    
    try {
      // 1. 获取页面列表（【关键】必须传递sourceName）
      if (!this.currentSourceName) {
        throw new Error(`图源名称为空，无法预加载: sourceId=${this.currentSourceId}`);
      }
      const webViewManager = WebViewSourceManager.getInstance();
      const engine: MangaSourceEngine = await webViewManager.getMangaEngine(this.currentSourceId, this.currentSourceName);
      
      const pageListResult = await engine.getPageList(task.externalChapterId, this.currentMangaId);
      
      if (!pageListResult.success || !pageListResult.data || pageListResult.data.length === 0) {
        throw new Error(`获取页面列表失败: ${pageListResult.error || '未知错误'}`);
      }
      
      task.pageCount = pageListResult.data.length;
      logger.info(TAG, `章节 ${task.chapterTitle} 共 ${task.pageCount} 页`);
      
      // 保存页面列表到数据库
      await this.savePageListToDatabase(task.chapterId, pageListResult.data);
      
      // 2. 预加载前N页的图片
      const pagesToPreload = Math.min(this.config.preloadPageCount, task.pageCount);
      logger.info(TAG, `开始预加载前 ${pagesToPreload} 页图片`);
      
      for (let i = 0; i < pagesToPreload; i++) {
        // 检查阅读器是否激活
        if (this.isReaderActive) {
          logger.info(TAG, `阅读器已激活，中断预加载: ${task.chapterTitle}`);
          task.status = PreloadStatus.PENDING; // 重置为待处理，稍后继续
          return;
        }
        
        const pageInfo = pageListResult.data[i];
        if (pageInfo.imageUrl) {
          try {
            // 使用ImageCacheManager预加载图片
            await ImageCacheManager.getInstance().preloadImage(pageInfo.imageUrl);
            task.preloadedPages++;
            logger.debug(TAG, `预加载完成: ${task.chapterTitle} 第${i + 1}页`);
          } catch (error) {
            logger.warn(TAG, `预加载失败: ${task.chapterTitle} 第${i + 1}页, ${error}`);
          }
        }
      }
      
      task.status = PreloadStatus.COMPLETED;
      task.endTime = Date.now();
      const duration = task.endTime - (task.startTime || 0);
      logger.info(TAG, `章节预加载完成: ${task.chapterTitle}, 耗时${duration}ms, 已加载${task.preloadedPages}/${task.pageCount}页`);
      
    } catch (error) {
      task.status = PreloadStatus.FAILED;
      task.error = String(error);
      task.endTime = Date.now();
      logger.error(TAG, `章节预加载失败: ${task.chapterTitle}, ${error}`);
    }
  }
  
  /**
   * 获取章节预加载状态
   */
  public getTaskStatus(chapterId: string): PreloadTask | null {
    return this.tasks.get(chapterId) || null;
  }
  
  /**
   * 检查章节是否已预加载
   */
  public isChapterPreloaded(chapterId: string): boolean {
    const task = this.tasks.get(chapterId);
    return task?.status === PreloadStatus.COMPLETED && task.preloadedPages > 0;
  }
  
  /**
   * 获取章节已预加载的页面数
   */
  public getPreloadedPageCount(chapterId: string): number {
    const task = this.tasks.get(chapterId);
    return task?.preloadedPages || 0;
  }
  
  /**
   * 清除指定章节的预加载任务
   */
  public clearTask(chapterId: string): void {
    this.tasks.delete(chapterId);
    logger.debug(TAG, `清除预加载任务: ${chapterId}`);
  }
  
  /**
   * 清除所有预加载任务
   */
  public clearAllTasks(): void {
    this.tasks.clear();
    this.activeTaskCount = 0;
    logger.info(TAG, '清除所有预加载任务');
  }
  
  /**
   * 获取所有任务状态
   */
  public getAllTasks(): PreloadTask[] {
    return Array.from(this.tasks.values());
  }
  
  /**
   * 保存页面列表到数据库
   */
  private async savePageListToDatabase(chapterId: string, pages: PageInfo[]): Promise<void> {
    try {
      const dataManager = DataManager.getInstance();
      
      // 检查是否已经保存过
      const existingPages = await dataManager.getPageInfoList(chapterId);
      if (existingPages.length > 0) {
        logger.debug(TAG, `章节 ${chapterId} 的页面信息已存在，跳过保存`);
        return;
      }
      
      // 批量保存页面信息
      for (let i = 0; i < pages.length; i++) {
        const pageInfo = pages[i];
        await dataManager.addPageInfo({
          chapterId: chapterId,
          index: i,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width || 0,
          height: pageInfo.height || 0,
          fileSize: 0
        });
      }
      
      logger.info(TAG, `✅ 已保存章节 ${chapterId} 的 ${pages.length} 个页面信息到数据库`);
    } catch (error) {
      logger.error(TAG, `保存页面信息失败: ${error}`);
    }
  }
}
