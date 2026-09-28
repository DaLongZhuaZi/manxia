/**
 * WebView漫画加载器主实现
 * 整合WebView源管理、图片拦截、缓存等功能
 * 提供完整的漫画图片加载解决方案
 * 符合HarmonyOS API 19和ArkTS规范
 */

import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { 
  ChapterInfoDatabaseRecord,
  PageInfoDatabaseRecord,
  ComicSourceDatabaseRecord
} from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { 
  IWebViewImageLoader,
  ImageRequestInfo,
  WebViewLoadingResult,
  WebViewLoadingState,
  WebViewImageLoadListener,
  WebViewImageInterceptor,
  WebViewImageCache,
  WebViewSourceConfig
} from 'manxia_source_engine/src/main/ets/Framework/WebView/WebViewImageLoader';
import { WebViewSourceManager } from './WebViewSourceManager';

const TAG = 'WebViewMangaLoader';

/**
 * 章节加载配置接口
 */
interface ChapterLoadConfig {
  /** 并发加载数量 */
  readonly concurrency: number;
  /** 预加载页数 */
  readonly preloadPages: number;
  /** 加载超时时间 */
  readonly timeout: number;
  /** 重试次数 */
  readonly retryCount: number;
  /** 是否启用预加载 */
  readonly enablePreload: boolean;
}

/**
 * 加载进度信息接口
 */
interface LoadingProgress {
  /** 章节ID */
  readonly chapterId: string;
  /** 总页数 */
  totalPages: number;
  /** 已加载页数 */
  loadedPages: number;
  /** 失败页数 */
  failedPages: number;
  /** 加载进度百分比 */
  progress: number;
  /** 是否完成 */
  isCompleted: boolean;
}

/**
 * WebView漫画加载器实现类
 */
export class WebViewMangaLoader implements IWebViewImageLoader, WebViewImageLoadListener {
  private static instance: WebViewMangaLoader | null = null;
  
  private readonly sourceManager: WebViewSourceManager;
  private readonly imageInterceptor: WebViewImageInterceptor;
  private readonly imageCache: WebViewImageCache;
  private readonly databaseManager: DatabaseManager;
  
  private readonly loadingChapters: Map<string, LoadingProgress> = new Map();
  private readonly cancelTokens: Map<string, boolean> = new Map();
  private readonly loadListeners: Set<WebViewImageLoadListener> = new Set();
  
  private readonly defaultConfig: ChapterLoadConfig = {
    concurrency: 3,
    preloadPages: 5,
    timeout: 30000,
    retryCount: 3,
    enablePreload: true
  };
  
  private isInitialized: boolean = false;

  /**
   * 私有构造函数
   */
  private constructor() {
    this.sourceManager = WebViewSourceManager.getInstance();
    this.imageInterceptor = WebViewImageInterceptor.getInstance();
    this.imageCache = WebViewImageCache.getInstance();
    this.databaseManager = DatabaseManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  static getInstance(): WebViewMangaLoader {
    if (!WebViewMangaLoader.instance) {
      WebViewMangaLoader.instance = new WebViewMangaLoader();
    }
    return WebViewMangaLoader.instance;
  }

  /**
   * 初始化加载器
   */
  initialize(): void {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化WebView漫画加载器');
      
      // 初始化依赖组件
      this.sourceManager.initialize();
      this.imageInterceptor.initialize();
      this.imageCache.initialize();
      
      // 注册为图片拦截器的监听器
      this.imageInterceptor.addLoadListener(this);
      
      this.isInitialized = true;
      logger.info(TAG, 'WebView漫画加载器初始化完成');
      
    } catch (error) {
      logger.error(TAG, `初始化WebView漫画加载器失败: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 加载单个图片 - IWebViewImageLoader接口实现
   */
  loadImage(request: ImageRequestInfo): WebViewLoadingResult {
    try {
      logger.debug(TAG, `加载单个图片: ${request.url}`);
      
      // 委托给图片拦截器处理
      return this.imageInterceptor.interceptImageRequest(request);
      
    } catch (error) {
      logger.error(TAG, `加载图片失败: ${request.url}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      
      const result: WebViewLoadingResult = {
        success: false,
        data: null,
        error: error instanceof Error ? error.message : String(error),
        headers: {},
        statusCode: 0,
        loadTime: 0
      };
      
      return result;
    }
  }

  /**
   * 取消加载 - IWebViewImageLoader接口实现
   */
  cancelLoad(requestId: string): void {
    logger.info(TAG, `取消图片加载: ${requestId}`);
    
    // 设置取消标志
    this.cancelTokens.set(requestId, true);
    
    // 如果是章节加载，也取消章节加载
    this.cancelLoading(requestId);
  }

  /**
   * 加载章节图片
   */
  loadChapterImages(chapter: ChapterInfoDatabaseRecord): PageInfoDatabaseRecord[] {
    try {
      logger.info(TAG, `开始加载章节图片: ${chapter.title} (${chapter.id})`);
      
      // 检查是否已在加载中
      if (this.loadingChapters.has(chapter.id)) {
        throw new Error(`章节正在加载中: ${chapter.id}`);
      }

      // 获取源配置
      const sourceConfig = this.sourceManager.getSourceConfig(chapter.comicId);
      if (!sourceConfig) {
        throw new Error(`找不到源配置: ${chapter.comicId}`);
      }

      // 初始化加载进度
      const progress: LoadingProgress = {
        chapterId: chapter.id,
        totalPages: chapter.pageCount,
        loadedPages: 0,
        failedPages: 0,
        progress: 0,
        isCompleted: false
      };
      this.loadingChapters.set(chapter.id, progress);

      // 创建取消令牌
      this.cancelTokens.set(chapter.id, false);

      try {
        // 获取章节页面URL列表
        const pageUrls = this.getChapterPageUrls(chapter, sourceConfig);
        
        // 更新总页数
        progress.totalPages = pageUrls.length;
        
        // 并发加载图片
        const pageRecords = this.loadPagesWithConcurrency(
          chapter, 
          pageUrls, 
          this.defaultConfig
        );

        // 标记完成
        progress.isCompleted = true;
        progress.progress = 100;

        logger.info(TAG, `章节图片加载完成: ${chapter.title}, 成功: ${pageRecords.length}/${pageUrls.length}`);
        
        return pageRecords;

      } finally {
        // 清理资源
        this.loadingChapters.delete(chapter.id);
        this.cancelTokens.delete(chapter.id);
      }

    } catch (error) {
      logger.error(TAG, `加载章节图片失败: ${chapter.title}, 错误: ${error instanceof Error ? error.message : String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取章节页面URL列表
   */
  private getChapterPageUrls(chapter: ChapterInfoDatabaseRecord, sourceConfig: WebViewSourceConfig): string[] {
    // 这里应该根据源配置解析章节页面
    // 暂时返回空数组，实际实现需要根据具体的源配置来解析
    logger.debug(TAG, `获取章节页面URL: ${chapter.id}`);
    return [];
  }

  /**
   * 并发加载页面
   */
  private loadPagesWithConcurrency(
    chapter: ChapterInfoDatabaseRecord,
    pageUrls: string[],
    config: ChapterLoadConfig
  ): PageInfoDatabaseRecord[] {
    const results: PageInfoDatabaseRecord[] = [];
    
    const loadPage = (url: string, index: number): PageInfoDatabaseRecord | null => {
      try {
        // 检查是否被取消
        if (this.cancelTokens.get(chapter.id)) {
          return null;
        }

        // 这里应该实现具体的页面加载逻辑
        logger.debug(TAG, `加载页面: ${url}`);
        
        // 创建页面记录 - 修复类型匹配问题
        const pageRecord: PageInfoDatabaseRecord = {
          id: `${chapter.id}_${index}`,
          chapterId: chapter.id,
          index: index,  // 使用index而不是pageNumber
          imageUrl: url,
          localPath: null,  // 使用null而不是空字符串
          width: 0,
          height: 0,
          fileSize: 0
        };

        return pageRecord;

      } catch (error) {
        logger.error(TAG, `加载页面失败: ${url}, 错误: ${error instanceof Error ? error.message : String(error)}`);
        return null;
      }
    };

    // 同步执行加载任务
    pageUrls.forEach((url, index) => {
      const result = loadPage(url, index);
      if (result) {
        results.push(result);
      }
    });

    return results;
  }

  /**
   * 取消加载
   */
  cancelLoading(chapterId: string): void {
    logger.info(TAG, `取消章节加载: ${chapterId}`);
    this.cancelTokens.set(chapterId, true);
  }

  /**
   * 获取加载进度
   */
  getLoadingProgress(chapterId: string): LoadingProgress | null {
    return this.loadingChapters.get(chapterId) || null;
  }

  /**
   * 添加加载监听器
   */
  addLoadListener(listener: WebViewImageLoadListener): void {
    this.loadListeners.add(listener);
  }

  /**
   * 移除加载监听器
   */
  removeLoadListener(listener: WebViewImageLoadListener): void {
    this.loadListeners.delete(listener);
  }

  /**
   * 更新章节进度
   */
  private updateChapterProgress(chapterId: string, isSuccess: boolean, isError: boolean): void {
    const progress = this.loadingChapters.get(chapterId);
    if (!progress) {
      return;
    }

    if (isSuccess) {
      progress.loadedPages++;
    }
    if (isError) {
      progress.failedPages++;
    }

    const totalProcessed = progress.loadedPages + progress.failedPages;
    progress.progress = Math.round((totalProcessed / progress.totalPages) * 100);
    
    if (totalProcessed >= progress.totalPages) {
      progress.isCompleted = true;
    }
  }

  /**
   * 清理资源
   */
  cleanup(): void {
    logger.info(TAG, '清理WebView漫画加载器资源');
    
    // 取消所有加载任务
    this.loadingChapters.forEach((_, chapterId) => {
      this.cancelLoading(chapterId);
    });
    
    // 清理监听器
    this.loadListeners.clear();
    
    // 从图片拦截器移除监听
    this.imageInterceptor.removeLoadListener(this);
  }

  // ==================== WebViewImageLoadListener 实现 ====================

  /**
   * 加载开始回调
   */
  onLoadStart(request: ImageRequestInfo): void {
    logger.debug(TAG, `图片开始加载: ${request.url}`);
    
    // 转发给其他监听器
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadStart(request);
      } catch (error) {
        logger.error(TAG, `通知加载开始失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 加载进度回调
   */
  onLoadProgress(request: ImageRequestInfo, progress: number): void {
    // 更新章节加载进度
    this.updateChapterProgress(request.chapterId, false, false);
    
    // 转发给其他监听器
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadProgress(request, progress);
      } catch (error) {
        logger.error(TAG, `通知加载进度失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 加载成功回调
   */
  onLoadSuccess(request: ImageRequestInfo, response: WebViewLoadingResult): void {
    logger.debug(TAG, `图片加载成功: ${request.url}`);
    
    // 更新章节加载进度
    this.updateChapterProgress(request.chapterId, true, false);
    
    // 转发给其他监听器
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadSuccess(request, response);
      } catch (error) {
        logger.error(TAG, `通知加载成功失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 加载失败回调
   */
  onLoadError(request: ImageRequestInfo, error: string): void {
    logger.warn(TAG, `图片加载失败: ${request.url}, 错误: ${error}`);
    
    // 更新章节加载进度
    this.updateChapterProgress(request.chapterId, false, true);
    
    // 转发给其他监听器
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadError(request, error);
      } catch (error) {
        logger.error(TAG, `通知加载失败失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  /**
   * 加载完成回调
   */
  onLoadComplete(request: ImageRequestInfo, result: WebViewLoadingResult): void {
    // 转发给其他监听器
    this.loadListeners.forEach(listener => {
      try {
        listener.onLoadComplete(request, result);
      } catch (error) {
        logger.error(TAG, `通知加载完成失败: ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }
}