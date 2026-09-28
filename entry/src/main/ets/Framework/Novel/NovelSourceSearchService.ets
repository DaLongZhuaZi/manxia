/**
 * 小说换源搜索服务
 * 提供独立的书源搜索功能，支持分批并行搜索、进度回调和任务取消
 * 可用于换源、全局搜索等场景
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceSearchService.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getNovelSourceManager, NovelSourceManager } from './NovelSourceManager';
import { NovelSearchResult, NovelSourceInfo } from 'manxia_core/src/main/ets/Models/NovelModels';

const TAG = 'NovelSourceSearchService';

// 搜索常量
const MAX_CONCURRENT_SOURCES = 50;  // 最大并发搜索数
const SEARCH_BATCH_SIZE = 10;       // 每批搜索数量
const SEARCH_BATCH_DELAY = 50;      // 批次间延迟(ms)
const PROGRESS_THROTTLE_MS = 300;   // 进度更新节流(ms)
const MAX_RESULTS_PER_SOURCE = 100; // 每个书源最大结果数
const CACHE_EXPIRE_MS = 30 * 60 * 1000; // 搜索结果缓存有效期30分钟

/**
 * 搜索结果缓存
 */
export interface SearchResultCache {
  keyword: string;
  author?: string;
  timestamp: number;
  results: NovelSearchResult[];
  sourceResults: SourceSearchResult[];
}

/**
 * 书源搜索结果分组
 */
export interface SourceSearchResult {
  sourceId: string;
  sourceName: string;
  sourceGroup: string;
  results: NovelSearchResult[];
  isLoading: boolean;
  hasError: boolean;
  errorMsg: string;
}

/**
 * 搜索进度回调
 */
export interface SearchProgressCallback {
  /**
   * 单个书源搜索完成
   * @param sourceResult 该书源的搜索结果
   */
  onSourceComplete?: (sourceResult: SourceSearchResult) => void;
  
  /**
   * 搜索进度更新
   * @param completed 已完成的书源数
   * @param total 总书源数
   */
  onProgress?: (completed: number, total: number) => void;
  
  /**
   * 所有搜索完成
   * @param allResults 所有搜索结果
   * @param sourceResults 按书源分组的结果
   */
  onComplete?: (allResults: NovelSearchResult[], sourceResults: SourceSearchResult[]) => void;
  
  /**
   * 搜索被取消
   */
  onCancelled?: () => void;
}

/**
 * 搜索任务配置
 */
export interface SearchTaskConfig {
  /** 搜索关键词 */
  keyword: string;
  /** 指定搜索的书源ID列表（可选，不指定则搜索所有启用的书源） */
  sourceIds?: string[];
  /** 最大并发搜索书源数 */
  maxConcurrent?: number;
  /** 是否只匹配同名或相似名称的书籍（用于换源） */
  matchSimilarName?: boolean;
  /** 原书名（用于换源时的精确匹配） */
  originalBookName?: string;
  /** 原作者（用于换源时的作者匹配） */
  originalAuthor?: string;
}

/**
 * 搜索任务句柄
 */
export interface SearchTaskHandle {
  /** 取消搜索 */
  cancel: () => void;
  /** 是否已取消 */
  isCancelled: () => boolean;
}

/**
 * 小说换源搜索服务类
 */
export class NovelSourceSearchService {
  private static instance: NovelSourceSearchService | null = null;
  private sourceManager: NovelSourceManager;
  private currentTaskId: number = 0;
  private lastProgressUpdate: number = 0;
  
  // 搜索结果缓存（按关键词+作者缓存）
  private searchCache: Map<string, SearchResultCache> = new Map();

  private constructor() {
    this.sourceManager = getNovelSourceManager();
  }
  
  /**
   * 生成缓存键
   */
  private getCacheKey(keyword: string, author?: string): string {
    return `${keyword.trim().toLowerCase()}_${(author || '').trim().toLowerCase()}`;
  }
  
  /**
   * 获取缓存的搜索结果
   * @param keyword 搜索关键词
   * @param author 作者（可选）
   * @returns 缓存的结果，如果缓存不存在或已过期则返回null
   */
  getCachedResults(keyword: string, author?: string): SearchResultCache | null {
    const cacheKey = this.getCacheKey(keyword, author);
    const cached = this.searchCache.get(cacheKey);
    
    if (!cached) {
      return null;
    }
    
    // 检查缓存是否过期
    if (Date.now() - cached.timestamp > CACHE_EXPIRE_MS) {
      this.searchCache.delete(cacheKey);
      logger.info(TAG, `搜索缓存已过期: ${keyword}`);
      return null;
    }
    
    logger.info(TAG, `命中搜索缓存: ${keyword}, ${cached.sourceResults.length}个书源, ${cached.results.length}本书`);
    return cached;
  }
  
  /**
   * 清除搜索缓存
   * @param keyword 指定关键词清除，不传则清除所有
   */
  clearCache(keyword?: string, author?: string): void {
    if (keyword) {
      const cacheKey = this.getCacheKey(keyword, author);
      this.searchCache.delete(cacheKey);
      logger.info(TAG, `清除搜索缓存: ${keyword}`);
    } else {
      this.searchCache.clear();
      logger.info(TAG, '清除所有搜索缓存');
    }
  }
  
  /**
   * 保存搜索结果到缓存
   */
  private saveToCache(keyword: string, author: string | undefined, results: NovelSearchResult[], sourceResults: SourceSearchResult[]): void {
    const cacheKey = this.getCacheKey(keyword, author);
    const cache: SearchResultCache = {
      keyword: keyword,
      author: author,
      timestamp: Date.now(),
      results: results,
      sourceResults: sourceResults
    };
    this.searchCache.set(cacheKey, cache);
    logger.info(TAG, `保存搜索缓存: ${keyword}, ${sourceResults.length}个书源, ${results.length}本书`);
  }

  /**
   * 获取单例实例
   */
  static getInstance(): NovelSourceSearchService {
    if (!NovelSourceSearchService.instance) {
      NovelSourceSearchService.instance = new NovelSourceSearchService();
    }
    return NovelSourceSearchService.instance;
  }

  /**
   * 执行换源搜索
   * 搜索同名书籍的其他书源
   * 
   * @param bookName 书名
   * @param author 作者（可选，用于更精确匹配）
   * @param callback 进度回调
   * @param maxSources 最大搜索书源数，默认50
   * @returns 搜索任务句柄
   */
  searchForSource(
    bookName: string,
    author?: string,
    callback?: SearchProgressCallback,
    maxSources: number = MAX_CONCURRENT_SOURCES
  ): SearchTaskHandle {
    const config: SearchTaskConfig = {
      keyword: bookName,
      maxConcurrent: maxSources,
      matchSimilarName: true,
      originalBookName: bookName,
      originalAuthor: author
    };
    
    return this.search(config, callback);
  }

  /**
   * 执行通用搜索
   * 
   * @param config 搜索配置
   * @param callback 进度回调
   * @returns 搜索任务句柄
   */
  search(config: SearchTaskConfig, callback?: SearchProgressCallback): SearchTaskHandle {
    // 生成新的任务ID，取消之前的搜索
    this.currentTaskId++;
    const taskId = this.currentTaskId;
    let isCancelled = false;

    const handle: SearchTaskHandle = {
      cancel: () => {
        if (taskId === this.currentTaskId) {
          isCancelled = true;
          this.currentTaskId++;
          callback?.onCancelled?.();
        }
      },
      isCancelled: () => isCancelled
    };

    // 异步执行搜索
    this.executeSearch(taskId, config, callback, () => isCancelled);

    return handle;
  }

  /**
   * 执行搜索（内部方法）
   */
  private async executeSearch(
    taskId: number,
    config: SearchTaskConfig,
    callback?: SearchProgressCallback,
    checkCancelled?: () => boolean
  ): Promise<void> {
    const keyword = config.keyword.trim();
    if (!keyword) {
      callback?.onComplete?.([], []);
      return;
    }

    const allResults: NovelSearchResult[] = [];
    const sourceResults: SourceSearchResult[] = [];
    let completedCount = 0;
    this.lastProgressUpdate = 0;

    // 获取要搜索的书源列表
    let sourcesToSearch: NovelSourceInfo[];
    if (config.sourceIds && config.sourceIds.length > 0) {
      const allSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      sourcesToSearch = allSources.filter(s => config.sourceIds!.includes(s.id));
    } else {
      const enabledSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      // maxConcurrent <= 0 表示不限制，搜索所有启用的书源
      const maxSources = config.maxConcurrent && config.maxConcurrent > 0
        ? config.maxConcurrent
        : enabledSources.length;
      sourcesToSearch = enabledSources.slice(0, maxSources);
    }

    const totalCount = sourcesToSearch.length;
    logger.info(TAG, `开始搜索 "${keyword}"，共 ${totalCount} 个书源`);

    // 分批执行搜索
    for (let batchStart = 0; batchStart < sourcesToSearch.length; batchStart += SEARCH_BATCH_SIZE) {
      // 检查任务是否已取消
      if (taskId !== this.currentTaskId || (checkCancelled && checkCancelled())) {
        logger.info(TAG, '搜索任务已取消');
        return;
      }

      const batchEnd = Math.min(batchStart + SEARCH_BATCH_SIZE, sourcesToSearch.length);
      const batchSources = sourcesToSearch.slice(batchStart, batchEnd);

      // 并行搜索当前批次
      const batchPromises = batchSources.map(async (source: NovelSourceInfo) => {
        const sourceResult = await this.searchSingleSource(
          source,
          keyword,
          taskId,
          config,
          checkCancelled
        );
        
        completedCount++;
        
        // 节流更新进度
        const now = Date.now();
        if (now - this.lastProgressUpdate >= PROGRESS_THROTTLE_MS) {
          this.lastProgressUpdate = now;
          callback?.onProgress?.(completedCount, totalCount);
        }

        // 只添加有结果的书源
        if (sourceResult.results.length > 0) {
          sourceResults.push(sourceResult);
          allResults.push(...sourceResult.results);
          callback?.onSourceComplete?.(sourceResult);
        }

        return sourceResult;
      });

      await Promise.all(batchPromises);

      // 批次间延迟，让UI有时间响应
      if (batchEnd < sourcesToSearch.length) {
        await this.delay(SEARCH_BATCH_DELAY);
      }
    }

    // 检查最终状态
    if (taskId === this.currentTaskId && !(checkCancelled && checkCancelled())) {
      logger.info(TAG, `搜索完成，共 ${sourceResults.length} 个书源有结果，总计 ${allResults.length} 本`);
      
      // 保存到缓存
      this.saveToCache(keyword, config.originalAuthor, allResults, sourceResults);
      
      callback?.onProgress?.(totalCount, totalCount);
      callback?.onComplete?.(allResults, sourceResults);
    }
  }

  /**
   * 搜索单个书源
   */
  private async searchSingleSource(
    source: NovelSourceInfo,
    keyword: string,
    taskId: number,
    config: SearchTaskConfig,
    checkCancelled?: () => boolean
  ): Promise<SourceSearchResult> {
    const sourceResult: SourceSearchResult = {
      sourceId: source.id,
      sourceName: source.name,
      sourceGroup: source.group || '未分组',
      results: [],
      isLoading: true,
      hasError: false,
      errorMsg: ''
    };

    try {
      // 检查任务是否已取消
      if (taskId !== this.currentTaskId || (checkCancelled && checkCancelled())) {
        return sourceResult;
      }

      const results = await this.sourceManager.search(source.id, keyword, 1);

      // 再次检查任务是否已取消
      if (taskId !== this.currentTaskId || (checkCancelled && checkCancelled())) {
        return sourceResult;
      }

      // 如果需要匹配相似名称（换源模式）
      let filteredResults = results;
      if (config.matchSimilarName && config.originalBookName) {
        filteredResults = results.filter(r =>
          r.name === config.originalBookName ||
          r.name.includes(config.originalBookName!) ||
          config.originalBookName!.includes(r.name)
        );
        
        // 如果同时有作者信息，优先排序作者匹配的结果
        if (config.originalAuthor) {
          filteredResults.sort((a, b) => {
            const aMatch = a.author === config.originalAuthor ? 1 : 0;
            const bMatch = b.author === config.originalAuthor ? 1 : 0;
            return bMatch - aMatch;
          });
        }
      }

      // 限制每个书源的结果数量
      const limitedResults = filteredResults.slice(0, MAX_RESULTS_PER_SOURCE);
      sourceResult.results = limitedResults;
      sourceResult.isLoading = false;

      logger.debug(TAG, `书源 ${source.name} 搜索完成: ${limitedResults.length} 本`);
    } catch (error) {
      sourceResult.isLoading = false;
      sourceResult.hasError = true;
      sourceResult.errorMsg = String(error);
      logger.warn(TAG, `书源 ${source.name} 搜索失败: ${String(error)}`);
    }

    return sourceResult;
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 获取所有可用于搜索的书源
   */
  getSearchableSources(): NovelSourceInfo[] {
    return this.sourceManager.getEnabledSources().filter(s => s.searchable);
  }

  /**
   * 获取可用书源数量
   */
  getSearchableSourceCount(): number {
    return this.getSearchableSources().length;
  }
}

/**
 * 获取小说换源搜索服务实例
 */
export function getNovelSourceSearchService(): NovelSourceSearchService {
  return NovelSourceSearchService.getInstance();
}
