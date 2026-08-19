import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 章节预加载管理器
 * 负责在漫画详情页后台预加载章节的页面列表和首图
 */
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { MangaSourceEngine } from '../WebView/MangaSourceEngine';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { DataManager } from '../Data/DataManager';
import { ComicSourceDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { ImageCacheManager, LoadOptions, RequestHeaders } from '../Cache/ImageCacheManager';
import { MangaRequestHeaderContract } from '../Reader/MangaRequestHeaderContract';
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

interface SourcePreloadHeaderMap {
  Referer?: string;
  referer?: string;
  Origin?: string;
  origin?: string;
  Accept?: string;
  accept?: string;
  Cookie?: string;
  cookie?: string;
  Authorization?: string;
  authorization?: string;
  UserAgent?: string;
  userAgent?: string;
  AcceptLanguage?: string;
  acceptLanguage?: string;
  CacheControl?: string;
  cacheControl?: string;
  Pragma?: string;
  pragma?: string;
  SecFetchDest?: string;
  secFetchDest?: string;
  SecFetchMode?: string;
  secFetchMode?: string;
  SecFetchSite?: string;
  secFetchSite?: string;
  CachePartition?: string;
  cachePartition?: string;
}

class SourcePreloadNormalizedHeaders {
  userAgent: string = '';
  referer: string = '';
  origin: string = '';
  accept: string = '';
  cookie: string = '';
  authorization: string = '';
  acceptLanguage: string = '';
  cacheControl: string = '';
  pragma: string = '';
  secFetchDest: string = '';
  secFetchMode: string = '';
  secFetchSite: string = '';
  cachePartition: string = '';
}

interface SourcePreloadNetworkConfig {
  headers?: SourcePreloadHeaderMap;
}

interface SourcePreloadConfig {
  network?: SourcePreloadNetworkConfig;
  imageHeaders?: SourcePreloadHeaderMap;
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
  private currentSourceHeaders: RequestHeaders = {} as RequestHeaders; // 当前图源的图片请求头
  
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
   * [优化] 阅读器活跃时降低预加载优先级而非完全暂停
   */
  public setReaderActive(active: boolean): void {
    this.isReaderActive = active;
    logger.info(TAG, `阅读器活跃状态: ${active}`);

    if (active) {
      // 阅读器激活：降低预加载并发数（而非完全暂停）
      logger.info(TAG, '阅读器已激活，降低预加载优先级');
    } else {
      // 阅读器关闭：恢复预加载
      logger.info(TAG, '阅读器已关闭，恢复预加载');
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
    this.currentSourceHeaders = {} as RequestHeaders;
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
    
    // 获取图源的图片请求头，优先使用 imageHeaders，兼容 network.headers
    await this.loadSourceHeaders(sourceId);
    
    logger.info(TAG, `🔄 开始预加载 ${chapters.length} 个章节: sourceName="${sourceName}", sourceId=${sourceId}, headers=${JSON.stringify(this.currentSourceHeaders)}`);
    
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
   * [优化] 阅读器活跃时降低并发而非完全暂停
   */
  private async processNextTask(): Promise<void> {
    // [优化] 阅读器活跃时，将并发限制降到0（不再启动新任务，但不阻塞队列处理逻辑）
    const effectiveMaxConcurrent = this.isReaderActive ? 0 : this.config.maxConcurrentTasks;

    // 如果已达到最大并发数，等待
    if (this.activeTaskCount >= effectiveMaxConcurrent) {
      logger.debug(TAG, `已达到最大并发数 ${effectiveMaxConcurrent}（阅读器活跃: ${this.isReaderActive}），等待`);
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
            // 使用ImageCacheManager预加载图片（传递图源headers，如Referer）
            const preloadOptions = this.buildPreloadOptions();
            await ImageCacheManager.getInstance().preloadImage(pageInfo.imageUrl, preloadOptions);
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
  
  private normalizeConfiguredHeaderValue(value?: string): string {
    if (!value) {
      return '';
    }
    return value.trim();
  }

  private readHeaderAlias(headers: SourcePreloadHeaderMap, fieldName: string): string {
    try {
      const value = Reflect.get(headers, fieldName) as string | undefined;
      return this.normalizeConfiguredHeaderValue(value);
    } catch (_error) {
      return '';
    }
  }

  private chooseHeaderValue(first: string, second: string, third: string): string {
    if (first.length > 0) {
      return first;
    }
    if (second.length > 0) {
      return second;
    }
    return third;
  }

  private normalizeSourceHeaderMap(headers: SourcePreloadHeaderMap): SourcePreloadNormalizedHeaders {
    const normalized = new SourcePreloadNormalizedHeaders();
    normalized.userAgent = this.chooseHeaderValue(this.readHeaderAlias(headers, 'User-Agent'), this.readHeaderAlias(headers, 'UserAgent'), this.readHeaderAlias(headers, 'userAgent'));
    normalized.referer = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Referer'), this.readHeaderAlias(headers, 'referer'), '');
    normalized.origin = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Origin'), this.readHeaderAlias(headers, 'origin'), '');
    normalized.accept = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Accept'), this.readHeaderAlias(headers, 'accept'), '');
    normalized.cookie = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Cookie'), this.readHeaderAlias(headers, 'cookie'), '');
    normalized.authorization = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Authorization'), this.readHeaderAlias(headers, 'authorization'), '');
    normalized.acceptLanguage = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Accept-Language'), this.readHeaderAlias(headers, 'AcceptLanguage'), this.readHeaderAlias(headers, 'acceptLanguage'));
    normalized.cacheControl = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Cache-Control'), this.readHeaderAlias(headers, 'CacheControl'), this.readHeaderAlias(headers, 'cacheControl'));
    normalized.pragma = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Pragma'), this.readHeaderAlias(headers, 'pragma'), '');
    normalized.secFetchDest = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Sec-Fetch-Dest'), this.readHeaderAlias(headers, 'SecFetchDest'), this.readHeaderAlias(headers, 'secFetchDest'));
    normalized.secFetchMode = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Sec-Fetch-Mode'), this.readHeaderAlias(headers, 'SecFetchMode'), this.readHeaderAlias(headers, 'secFetchMode'));
    normalized.secFetchSite = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Sec-Fetch-Site'), this.readHeaderAlias(headers, 'SecFetchSite'), this.readHeaderAlias(headers, 'secFetchSite'));
    normalized.cachePartition = this.chooseHeaderValue(this.readHeaderAlias(headers, 'Cache-Partition'), this.readHeaderAlias(headers, 'CachePartition'), this.readHeaderAlias(headers, 'cachePartition'));
    return normalized;
  }

  private applyConfiguredRequestHeader(target: RequestHeaders, headerName: string, headerValue: string): void {
    MangaRequestHeaderContract.apply(target, headerName, headerValue);
  }

  private applyHeaderCandidate(headerName: string, headerValue?: string): void {
    const normalizedValue = this.normalizeConfiguredHeaderValue(headerValue);
    if (normalizedValue.length > 0) {
      this.applyConfiguredRequestHeader(this.currentSourceHeaders, headerName, normalizedValue);
    }
  }

  private applySourceHeaderMap(headers?: SourcePreloadHeaderMap): void {
    if (!headers) {
      return;
    }
    const normalized = this.normalizeSourceHeaderMap(headers);
    this.applyHeaderCandidate('User-Agent', normalized.userAgent);
    this.applyHeaderCandidate('Referer', normalized.referer);
    this.applyHeaderCandidate('Origin', normalized.origin);
    this.applyHeaderCandidate('Accept', normalized.accept);
    this.applyHeaderCandidate('Cookie', normalized.cookie);
    this.applyHeaderCandidate('Authorization', normalized.authorization);
    this.applyHeaderCandidate('Accept-Language', normalized.acceptLanguage);
    this.applyHeaderCandidate('Cache-Control', normalized.cacheControl);
    this.applyHeaderCandidate('Pragma', normalized.pragma);
    this.applyHeaderCandidate('Sec-Fetch-Dest', normalized.secFetchDest);
    this.applyHeaderCandidate('Sec-Fetch-Mode', normalized.secFetchMode);
    this.applyHeaderCandidate('Sec-Fetch-Site', normalized.secFetchSite);
    this.applyHeaderCandidate('Cache-Partition', normalized.cachePartition);
  }

  /**
   * 从图源配置中加载图片请求头
   */
  private async loadSourceHeaders(sourceId: number): Promise<void> {
    try {
      this.currentSourceHeaders = {} as RequestHeaders;
      const sources = await DataManager.getInstance().getAllComicSources();
      
      for (let i = 0; i < sources.length; i++) {
        const s = sources[i] as ComicSourceDatabaseRecord;
        if (Number(s.id) === sourceId) {
          const configJson = s.configJson as string;
          if (configJson) {
            const config: SourcePreloadConfig = SafeUtils.parseObj(configJson) as SourcePreloadConfig;
            if (config.network && config.network.headers) {
              this.applySourceHeaderMap(config.network.headers);
            }
            if (config.imageHeaders) {
              this.applySourceHeaderMap(config.imageHeaders);
            }
            logger.info(TAG, `图源图片headers已加载: ${JSON.stringify(this.currentSourceHeaders)}`);
          }
          break;
        }
      }
    } catch (error) {
      logger.warn(TAG, `加载图源headers失败: ${error}`);
    }
  }
  
  /**
   * 构建预加载选项（包含headers）
   */
  private buildPreloadOptions(): LoadOptions | undefined {
    if (!this.hasConfiguredSourceHeaders(this.currentSourceHeaders)) {
      return undefined;
    }
    
    const headers: RequestHeaders = {} as RequestHeaders;
    this.copyConfiguredSourceHeaders(headers, this.currentSourceHeaders);

    
    const options: LoadOptions = {} as LoadOptions;
    options.headers = headers;
    options.sourceId = this.currentSourceId;
    return options;
  }

  private hasConfiguredSourceHeaders(headers: RequestHeaders): boolean {
    if (headers.userAgent && headers.userAgent.length > 0) { return true; }
    if (headers.accept && headers.accept.length > 0) { return true; }
    if (headers.referer && headers.referer.length > 0) { return true; }
    if (headers.origin && headers.origin.length > 0) { return true; }
    if (headers.cookie && headers.cookie.length > 0) { return true; }
    if (headers.authorization && headers.authorization.length > 0) { return true; }
    if (headers.acceptLanguage && headers.acceptLanguage.length > 0) { return true; }
    if (headers.cacheControl && headers.cacheControl.length > 0) { return true; }
    if (headers.pragma && headers.pragma.length > 0) { return true; }
    if (headers.secFetchDest && headers.secFetchDest.length > 0) { return true; }
    if (headers.secFetchMode && headers.secFetchMode.length > 0) { return true; }
    if (headers.secFetchSite && headers.secFetchSite.length > 0) { return true; }
    if (headers.cachePartition && headers.cachePartition.length > 0) { return true; }
    if (headers.extraHeaders && headers.extraHeaders.length > 0) { return true; }
    return false;
  }

  private copyConfiguredSourceHeaders(target: RequestHeaders, source: RequestHeaders): void {
    if (source.userAgent && source.userAgent.length > 0) { target.userAgent = source.userAgent; }
    if (source.accept && source.accept.length > 0) { target.accept = source.accept; }
    if (source.referer && source.referer.length > 0) { target.referer = source.referer; }
    if (source.origin && source.origin.length > 0) { target.origin = source.origin; }
    if (source.cookie && source.cookie.length > 0) { target.cookie = source.cookie; }
    if (source.authorization && source.authorization.length > 0) { target.authorization = source.authorization; }
    if (source.acceptLanguage && source.acceptLanguage.length > 0) { target.acceptLanguage = source.acceptLanguage; }
    if (source.cacheControl && source.cacheControl.length > 0) { target.cacheControl = source.cacheControl; }
    if (source.pragma && source.pragma.length > 0) { target.pragma = source.pragma; }
    if (source.secFetchDest && source.secFetchDest.length > 0) { target.secFetchDest = source.secFetchDest; }
    if (source.secFetchMode && source.secFetchMode.length > 0) { target.secFetchMode = source.secFetchMode; }
    if (source.secFetchSite && source.secFetchSite.length > 0) { target.secFetchSite = source.secFetchSite; }
    if (source.cachePartition && source.cachePartition.length > 0) { target.cachePartition = source.cachePartition; }
    if (source.extraHeaders && source.extraHeaders.length > 0) {
      let index = 0;
      while (index < source.extraHeaders.length) {
        const entry = source.extraHeaders[index];
        MangaRequestHeaderContract.apply(target, entry.name, entry.value);
        index = index + 1;
      }
    }
  }
}
