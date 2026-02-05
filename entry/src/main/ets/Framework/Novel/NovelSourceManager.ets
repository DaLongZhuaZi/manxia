/**
 * 小说源管理器
 * 统一管理小说书源的导入、存储、执行
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelSourceManager.ets
 */

import { logger } from '../../Utils/Logger';
import { LegadoBookSource, LegadoSearchBook, LegadoBook, LegadoChapter, LegadoSourceImportResult, LegadoExploreKind } from './LegadoSourceTypes';
import { LegadoSourceParser } from './LegadoSourceParser';
import { NovelSourceExecutor } from './NovelSourceExecutor';
import { NovelSourceInfo, NovelSearchResult } from '../../Models/NovelModels';
import { getNovelDataManager } from './NovelDataManager';
import { LargeFileJSONParser, ParseProgressCallback, ParseConfig, ParseResult } from './LargeFileJSONParser';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG = 'NovelSourceManager';

/**
 * 大文件导入进度回调接口
 */
export interface LargeFileImportProgress {
  /**
   * 文件读取阶段
   * @param percent 读取百分比 0-100
   * @param bytesRead 已读取字节数
   * @param totalBytes 总字节数
   */
  onFileReadProgress?: (percent: number, bytesRead: number, totalBytes: number) => void;
  
  /**
   * 解析阶段
   * @param parsedCount 已解析书源数
   * @param currentSourceName 当前解析的书源名称
   */
  onParseProgress?: (parsedCount: number, currentSourceName: string) => void;
  
  /**
   * 导入阶段（保存到数据库）
   * @param importedCount 已导入数量
   * @param totalCount 总数量
   * @param currentSourceName 当前导入的书源名称
   */
  onImportProgress?: (importedCount: number, totalCount: number, currentSourceName: string) => void;
  
  /**
   * 阶段变化
   * @param stage 当前阶段: 'reading' | 'parsing' | 'importing' | 'complete'
   */
  onStageChange?: (stage: string) => void;
  
  /**
   * 错误（可恢复）
   * @param error 错误信息
   * @param sourceName 相关书源名称（如果有）
   */
  onError?: (error: string, sourceName?: string) => void;
}

/**
 * 大文件导入结果
 */
export interface LargeFileImportResult {
  success: boolean;
  totalParsed: number;
  successCount: number;
  failedCount: number;
  skippedCount: number;
  errors: string[];
  elapsedMs: number;
}

/**
 * 小说源管理器类
 */
export class NovelSourceManager {
  private static instance: NovelSourceManager | null = null;
  private sources: Map<string, LegadoBookSource> = new Map();
  private executors: Map<string, NovelSourceExecutor> = new Map();

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): NovelSourceManager {
    if (!NovelSourceManager.instance) {
      NovelSourceManager.instance = new NovelSourceManager();
    }
    return NovelSourceManager.instance;
  }

  /**
   * 导入书源（从JSON字符串）
   * 支持单个书源或书源数组，同时持久化到数据库
   */
  async importFromJSON(jsonStr: string, persistToDb: boolean = true): Promise<LegadoSourceImportResult[]> {
    const results: LegadoSourceImportResult[] = [];
    const parser = new LegadoSourceParser();
    const sources = parser.parseMultipleFromJSON(jsonStr);
    
    const totalCount = sources.length;
    let processedCount = 0;
    
    logger.info(TAG, `开始导入 ${totalCount} 个书源`);

    for (const source of sources) {
      processedCount++;
      try {
        if (!parser.validate(source)) {
          results.push({
            success: false,
            sourceName: source.bookSourceName,
            error: '书源配置验证失败'
          });
          continue;
        }

        const isUpdate = this.sources.has(source.bookSourceUrl);
        
        // 添加或更新内存中的书源
        this.sources.set(source.bookSourceUrl, source);
        this.executors.delete(source.bookSourceUrl);
        
        // 持久化到数据库
        if (persistToDb) {
          try {
            const dataManager = getNovelDataManager();
            await dataManager.saveSource(source);
          } catch (dbError) {
            logger.warn(TAG, `书源 ${source.bookSourceName} 保存到数据库失败: ${String(dbError)}`);
          }
        }
        
        results.push({
          success: true,
          sourceId: source.bookSourceUrl,
          sourceName: source.bookSourceName
        });
        
        if (isUpdate) {
          logger.debug(TAG, `更新书源: ${source.bookSourceName} (${processedCount}/${totalCount})`);
        } else {
          logger.debug(TAG, `导入书源: ${source.bookSourceName} (${processedCount}/${totalCount})`);
        }
      } catch (error) {
        results.push({
          success: false,
          sourceName: source.bookSourceName,
          error: String(error)
        });
      }
    }
    
    const successCount = results.filter(r => r.success).length;
    logger.info(TAG, `书源导入完成: 成功 ${successCount}/${totalCount}`);

    return results;
  }
  
  /**
   * 批量导入书源（带进度回调）
   * 适用于大量书源导入场景
   */
  async importFromJSONWithProgress(
    jsonStr: string,
    onProgress?: (current: number, total: number, sourceName: string) => void
  ): Promise<LegadoSourceImportResult[]> {
    const results: LegadoSourceImportResult[] = [];
    const parser = new LegadoSourceParser();
    const sources = parser.parseMultipleFromJSON(jsonStr);
    
    const totalCount = sources.length;
    logger.info(TAG, `开始批量导入 ${totalCount} 个书源`);

    for (let i = 0; i < sources.length; i++) {
      const source = sources[i];
      const current = i + 1;
      
      // 回调进度
      if (onProgress) {
        onProgress(current, totalCount, source.bookSourceName);
      }
      
      try {
        if (!parser.validate(source)) {
          results.push({
            success: false,
            sourceName: source.bookSourceName,
            error: '书源配置验证失败'
          });
          continue;
        }

        // 添加或更新内存中的书源
        this.sources.set(source.bookSourceUrl, source);
        this.executors.delete(source.bookSourceUrl);
        
        // 持久化到数据库
        try {
          const dataManager = getNovelDataManager();
          await dataManager.saveSource(source);
        } catch (dbError) {
          logger.warn(TAG, `书源 ${source.bookSourceName} 保存到数据库失败: ${String(dbError)}`);
        }
        
        results.push({
          success: true,
          sourceId: source.bookSourceUrl,
          sourceName: source.bookSourceName
        });
      } catch (error) {
        results.push({
          success: false,
          sourceName: source.bookSourceName,
          error: String(error)
        });
      }
    }
    
    const successCount = results.filter(r => r.success).length;
    logger.info(TAG, `批量导入完成: 成功 ${successCount}/${totalCount}`);

    return results;
  }

  /**
   * 获取所有书源
   * 排序规则：启用的书源按 customOrder 排序，未启用的书源放在末尾
   */
  getAllSources(): NovelSourceInfo[] {
    const infos: NovelSourceInfo[] = [];
    
    this.sources.forEach((source, url) => {
      infos.push({
        id: url,
        name: source.bookSourceName,
        url: url,
        group: source.bookSourceGroup,
        enabled: source.enabled !== false,
        weight: source.weight || 0,
        customOrder: source.customOrder ?? 0,
        lastUpdateTime: source.lastUpdateTime || 0,
        respondTime: source.respondTime || 180000,
        searchable: !!source.searchUrl,
        hasExplore: !!source.exploreUrl
      });
    });

    // 排序规则：启用的书源按 customOrder 升序（越小越靠前），未启用的放在末尾
    infos.sort((a, b) => {
      // 启用状态不同：启用的在前，未启用的在后
      if (a.enabled !== b.enabled) {
        return a.enabled ? -1 : 1;
      }
      // 同为启用或同为未启用：按 customOrder 升序
      return a.customOrder - b.customOrder;
    });
    return infos;
  }

  /**
   * 获取启用的书源
   */
  getEnabledSources(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => s.enabled);
  }

  /**
   * 删除书源（同时从数据库删除）
   */
  async deleteSource(sourceId: string): Promise<boolean> {
    this.executors.delete(sourceId);
    const deleted = this.sources.delete(sourceId);
    
    // 从数据库删除
    if (deleted) {
      try {
        const dataManager = getNovelDataManager();
        await dataManager.deleteSource(sourceId);
        logger.info(TAG, `已删除书源: ${sourceId}`);
      } catch (error) {
        logger.warn(TAG, `从数据库删除书源失败: ${String(error)}`);
      }
    }
    
    return deleted;
  }

  /**
   * 启用/禁用书源（同时更新数据库）
   */
  async setSourceEnabled(sourceId: string, enabled: boolean): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (source) {
      source.enabled = enabled;
      
      // 更新数据库
      try {
        const dataManager = getNovelDataManager();
        await dataManager.saveSource(source);
      } catch (error) {
        logger.warn(TAG, `更新书源状态失败: ${String(error)}`);
      }
      
      return true;
    }
    return false;
  }

  /**
   * 获取原始书源对象
   */
  getSource(sourceId: string): LegadoBookSource | null {
    return this.sources.get(sourceId) || null;
  }

  /**
   * 获取执行器
   */
  private getExecutor(sourceId: string): NovelSourceExecutor | null {
    if (this.executors.has(sourceId)) {
      return this.executors.get(sourceId)!;
    }

    const source = this.sources.get(sourceId);
    if (!source) {
      return null;
    }

    const executor = new NovelSourceExecutor(source);
    this.executors.set(sourceId, executor);
    return executor;
  }

  /**
   * 搜索书籍（单个书源）
   */
  async search(sourceId: string, keyword: string, page: number = 1): Promise<NovelSearchResult[]> {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      logger.warn(TAG, `书源不存在: ${sourceId}`);
      return [];
    }

    const source = this.sources.get(sourceId)!;
    const results = await executor.search(keyword, page);

    return results.map((book: LegadoSearchBook): NovelSearchResult => {
      const result: NovelSearchResult = {
        sourceId: sourceId,
        sourceName: source.bookSourceName,
        bookUrl: book.bookUrl,
        name: book.name,
        author: book.author,
        kind: book.kind,
        intro: book.intro,
        coverUrl: book.coverUrl,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount
      };
      return result;
    });
  }

  /**
   * 搜索书籍（多个书源并行，限制并发数）
   * @param keyword 搜索关键词
   * @param page 页码
   * @param maxConcurrent 最大并发书源数，默认10
   */
  async searchAll(keyword: string, page: number = 1, maxConcurrent: number = 10): Promise<NovelSearchResult[]> {
    const enabledSources = this.getEnabledSources().filter(s => s.searchable);
    const allResults: NovelSearchResult[] = [];
    
    // 限制搜索的书源数量，避免同时搜索太多导致主线程阻塞
    const sourcesToSearch = enabledSources.slice(0, maxConcurrent);
    
    logger.info(TAG, `搜索 "${keyword}"，使用 ${sourcesToSearch.length}/${enabledSources.length} 个书源`);

    // 并行搜索选中的书源
    const promises = sourcesToSearch.map(async (sourceInfo) => {
      try {
        const results = await this.search(sourceInfo.id, keyword, page);
        return results;
      } catch (error) {
        logger.warn(TAG, `书源 ${sourceInfo.name} 搜索失败: ${String(error)}`);
        return [];
      }
    });

    const resultsArray = await Promise.all(promises);
    for (const results of resultsArray) {
      allResults.push(...results);
    }

    return allResults;
  }
  
  /**
   * 搜索书籍（分批并行，适用于大量书源）
   * @param keyword 搜索关键词
   * @param page 页码
   * @param batchSize 每批并发数
   * @param onProgress 进度回调
   */
  async searchAllBatched(
    keyword: string, 
    page: number = 1, 
    batchSize: number = 5,
    onProgress?: (completed: number, total: number, results: NovelSearchResult[]) => void
  ): Promise<NovelSearchResult[]> {
    const enabledSources = this.getEnabledSources().filter(s => s.searchable);
    const allResults: NovelSearchResult[] = [];
    const totalSources = enabledSources.length;
    
    logger.info(TAG, `分批搜索 "${keyword}"，共 ${totalSources} 个书源，每批 ${batchSize} 个`);

    // 分批处理
    for (let i = 0; i < totalSources; i += batchSize) {
      const batch = enabledSources.slice(i, Math.min(i + batchSize, totalSources));
      
      const promises = batch.map(async (sourceInfo) => {
        try {
          const results = await this.search(sourceInfo.id, keyword, page);
          return results;
        } catch (error) {
          logger.warn(TAG, `书源 ${sourceInfo.name} 搜索失败: ${String(error)}`);
          return [];
        }
      });

      const batchResults = await Promise.all(promises);
      for (const results of batchResults) {
        allResults.push(...results);
      }
      
      // 回调进度
      if (onProgress) {
        const completed = Math.min(i + batchSize, totalSources);
        onProgress(completed, totalSources, allResults);
      }
    }

    return allResults;
  }

  /**
   * 获取书籍详情
   */
  async getBookInfo(sourceId: string, bookUrl: string): Promise<LegadoBook | null> {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return null;
    }

    return await executor.getBookInfo(bookUrl);
  }

  /**
   * 获取章节列表
   */
  async getChapterList(sourceId: string, book: LegadoBook): Promise<LegadoChapter[]> {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }

    return await executor.getChapterList(book);
  }

  /**
   * 获取章节正文
   */
  async getContent(sourceId: string, chapter: LegadoChapter): Promise<string> {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return '';
    }

    return await executor.getContent(chapter);
  }

  // ==================== 发现页功能 ====================

  /**
   * 获取支持发现功能的书源
   */
  getExploreSources(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => s.hasExplore && s.enabled);
  }

  /**
   * 获取书源的发现分类
   */
  getExploreKinds(sourceId: string): LegadoExploreKind[] {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }
    return executor.getExploreKinds();
  }

  /**
   * 获取发现页书籍列表
   */
  async explore(sourceId: string, exploreUrl: string, page: number = 1): Promise<NovelSearchResult[]> {
    const executor = this.getExecutor(sourceId);
    if (!executor) {
      return [];
    }

    const source = this.sources.get(sourceId)!;
    const results = await executor.explore(exploreUrl, page);
    const searchResults: NovelSearchResult[] = [];

    for (let i = 0; i < results.length; i++) {
      const book = results[i];
      const searchResult: NovelSearchResult = {
        sourceId: sourceId,
        sourceName: source.bookSourceName,
        bookUrl: book.bookUrl,
        name: book.name,
        author: book.author,
        kind: book.kind,
        intro: book.intro,
        coverUrl: book.coverUrl,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount
      };
      searchResults.push(searchResult);
    }

    return searchResults;
  }

  /**
   * 获取书源数量
   */
  getSourceCount(): number {
    return this.sources.size;
  }

  /**
   * 清除所有书源（同时清除数据库）
   */
  async clearAll(): Promise<void> {
    // 从数据库删除所有书源
    try {
      const dataManager = getNovelDataManager();
      const allSources = this.getAllSources();
      for (const source of allSources) {
        await dataManager.deleteSource(source.id);
      }
    } catch (error) {
      logger.warn(TAG, `清除数据库书源失败: ${String(error)}`);
    }
    
    this.sources.clear();
    this.executors.clear();
    logger.info(TAG, '已清除所有书源');
  }
  
  /**
   * 从数据库加载书源到内存（仅内部使用）
   * 注意：这个方法不会持久化，用于初始化时加载
   */
  loadSourceToMemory(source: LegadoBookSource): void {
    this.sources.set(source.bookSourceUrl, source);
  }

  // ==================== 大文件流式导入 ====================

  /**
   * 从大文件流式导入书源
   * 适用于50M~100M+的大型书源JSON文件
   * 
   * @param filePath 文件路径
   * @param progress 进度回调
   * @returns 导入结果
   */
  async importFromLargeFile(
    filePath: string,
    progress?: LargeFileImportProgress
  ): Promise<LargeFileImportResult> {
    const startTime = Date.now();
    const result: LargeFileImportResult = {
      success: false,
      totalParsed: 0,
      successCount: 0,
      failedCount: 0,
      skippedCount: 0,
      errors: [],
      elapsedMs: 0
    };

    try {
      logger.info(TAG, `开始大文件流式导入: ${filePath}`);
      progress?.onStageChange?.('reading');

      // 配置解析器
      const parseConfig: ParseConfig = {
        chunkSize: 512 * 1024,    // 512KB 每次读取
        batchSize: 100,            // 每批100个对象
        batchDelayMs: 5,           // 5ms 让出主线程
        maxObjectSize: 2 * 1024 * 1024  // 单个书源最大2MB
      };

      // 待导入的书源列表
      const parsedSources: LegadoBookSource[] = [];
      const parser = new LegadoSourceParser();

      // 解析回调
      const parseCallback: ParseProgressCallback = {
        onFileProgress: (bytesRead, totalBytes) => {
          const percent = Math.round((bytesRead / totalBytes) * 100);
          progress?.onFileReadProgress?.(percent, bytesRead, totalBytes);
        },
        onObjectParsed: (parsedCount, currentObject) => {
          // 验证并转换为书源对象
          const rawSource = currentObject as Record<string, ESObject>;
          if (rawSource && rawSource['bookSourceUrl'] && rawSource['bookSourceName']) {
            const source = this.convertRawToSource(rawSource);
            if (source && parser.validate(source)) {
              parsedSources.push(source);
              progress?.onParseProgress?.(parsedSources.length, source.bookSourceName);
            } else {
              result.skippedCount++;
            }
          } else {
            result.skippedCount++;
          }
        },
        onBatchComplete: (batchIndex, batchSize, totalParsed) => {
          logger.debug(TAG, `解析批次 ${batchIndex} 完成, 批次大小: ${batchSize}, 总计: ${totalParsed}`);
        },
        onError: (error, recoverable) => {
          if (recoverable) {
            result.errors.push(error);
            progress?.onError?.(error);
          } else {
            throw new Error(error);
          }
        }
      };

      // 流式解析文件
      progress?.onStageChange?.('parsing');
      const parseResult = await LargeFileJSONParser.parseFile<Record<string, ESObject>>(
        filePath,
        parseConfig,
        parseCallback
      );

      result.totalParsed = parseResult.totalParsed;
      logger.info(TAG, `解析完成: 有效书源 ${parsedSources.length}, 跳过 ${result.skippedCount}`);

      // 批量导入到数据库
      progress?.onStageChange?.('importing');
      const importBatchSize = 50;  // 每批导入50个
      const dataManager = getNovelDataManager();

      for (let i = 0; i < parsedSources.length; i += importBatchSize) {
        const batch = parsedSources.slice(i, Math.min(i + importBatchSize, parsedSources.length));
        
        for (const source of batch) {
          try {
            // 添加到内存
            this.sources.set(source.bookSourceUrl, source);
            this.executors.delete(source.bookSourceUrl);
            
            // 保存到数据库
            await dataManager.saveSource(source);
            
            result.successCount++;
            progress?.onImportProgress?.(result.successCount, parsedSources.length, source.bookSourceName);
          } catch (error) {
            result.failedCount++;
            const errorMsg = `导入失败: ${source.bookSourceName} - ${String(error)}`;
            result.errors.push(errorMsg);
            progress?.onError?.(errorMsg, source.bookSourceName);
          }
        }
        
        // 每批之间让出主线程
        await this.sleep(10);
      }

      result.success = result.successCount > 0;
      progress?.onStageChange?.('complete');
      
      logger.info(TAG, `大文件导入完成: 成功 ${result.successCount}, 失败 ${result.failedCount}, 跳过 ${result.skippedCount}`);

    } catch (error) {
      const errorMsg = `大文件导入失败: ${String(error)}`;
      logger.error(TAG, errorMsg);
      result.errors.push(errorMsg);
      progress?.onError?.(errorMsg);
    }

    result.elapsedMs = Date.now() - startTime;
    return result;
  }

  /**
   * 将原始对象转换为书源对象
   */
  private convertRawToSource(obj: Record<string, ESObject>): LegadoBookSource | null {
    try {
      if (!obj['bookSourceUrl'] || !obj['bookSourceName']) {
        return null;
      }

      const source: LegadoBookSource = {
        bookSourceUrl: String(obj['bookSourceUrl']),
        bookSourceName: String(obj['bookSourceName']),
        bookSourceType: typeof obj['bookSourceType'] === 'number' ? obj['bookSourceType'] : 0,
        bookSourceGroup: obj['bookSourceGroup'] ? String(obj['bookSourceGroup']) : undefined,
        bookUrlPattern: obj['bookUrlPattern'] ? String(obj['bookUrlPattern']) : undefined,
        customOrder: typeof obj['customOrder'] === 'number' ? obj['customOrder'] : 0,
        enabled: obj['enabled'] !== false,
        enabledExplore: obj['enabledExplore'] !== false,
        jsLib: obj['jsLib'] ? String(obj['jsLib']) : undefined,
        enabledCookieJar: obj['enabledCookieJar'] === true,
        concurrentRate: obj['concurrentRate'] ? String(obj['concurrentRate']) : undefined,
        header: obj['header'] ? String(obj['header']) : undefined,
        loginUrl: obj['loginUrl'] ? String(obj['loginUrl']) : undefined,
        loginUi: obj['loginUi'] ? String(obj['loginUi']) : undefined,
        loginCheckJs: obj['loginCheckJs'] ? String(obj['loginCheckJs']) : undefined,
        coverDecodeJs: obj['coverDecodeJs'] ? String(obj['coverDecodeJs']) : undefined,
        bookSourceComment: obj['bookSourceComment'] ? String(obj['bookSourceComment']) : undefined,
        variableComment: obj['variableComment'] ? String(obj['variableComment']) : undefined,
        lastUpdateTime: typeof obj['lastUpdateTime'] === 'number' ? obj['lastUpdateTime'] : Date.now(),
        respondTime: typeof obj['respondTime'] === 'number' ? obj['respondTime'] : 180000,
        weight: 0,
        exploreUrl: obj['exploreUrl'] ? String(obj['exploreUrl']) : undefined,
        exploreScreen: obj['exploreScreen'] ? String(obj['exploreScreen']) : undefined,
        searchUrl: obj['searchUrl'] ? String(obj['searchUrl']) : undefined,
        ruleExplore: obj['ruleExplore'] as ESObject,
        ruleSearch: obj['ruleSearch'] as ESObject,
        ruleBookInfo: obj['ruleBookInfo'] as ESObject,
        ruleToc: obj['ruleToc'] as ESObject,
        ruleContent: obj['ruleContent'] as ESObject
      };

      return source;
    } catch (error) {
      logger.warn(TAG, `转换书源对象失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 休眠指定毫秒
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 检查文件是否为大文件（超过阈值则建议使用流式导入）
   * @param filePath 文件路径
   * @param thresholdMB 阈值（MB），默认5MB
   * @returns 是否为大文件
   */
  static isLargeFile(filePath: string, thresholdMB: number = 5): boolean {
    try {
      const stat = fs.statSync(filePath);
      return stat.size > thresholdMB * 1024 * 1024;
    } catch (error) {
      logger.warn(TAG, `检查文件大小失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 获取文件大小（字节）
   */
  static getFileSize(filePath: string): number {
    try {
      const stat = fs.statSync(filePath);
      return stat.size;
    } catch (error) {
      logger.warn(TAG, `获取文件大小失败: ${String(error)}`);
      return 0;
    }
  }

  /**
   * 格式化文件大小
   */
  static formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes}B`;
    } else if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)}KB`;
    } else if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
    } else {
      return `${(bytes / 1024 / 1024 / 1024).toFixed(2)}GB`;
    }
  }

  /**
   * 导出所有书源为JSON
   */
  exportToJSON(): string {
    const sources: LegadoBookSource[] = [];
    this.sources.forEach(source => {
      sources.push(source);
    });
    return JSON.stringify(sources, null, 2);
  }

  // ==================== 分组管理功能 ====================

  /**
   * 更新书源分组
   */
  async updateSourceGroup(sourceId: string, group: string): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.bookSourceGroup = group;
    
    // 更新数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `更新书源分组: ${source.bookSourceName} -> ${group}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `更新书源分组失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 更新书源响应时间
   */
  async updateSourceRespondTime(sourceId: string, respondTime: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.respondTime = respondTime;
    
    // 更新数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      return true;
    } catch (error) {
      logger.warn(TAG, `更新书源响应时间失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 批量添加书源到分组
   */
  async addSourcesToGroup(sourceIds: string[], groupName: string): Promise<number> {
    let successCount = 0;
    
    for (const sourceId of sourceIds) {
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 获取当前分组
      const currentGroups = source.bookSourceGroup 
        ? source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0)
        : [];
      
      // 如果已经在该分组中，跳过
      if (currentGroups.includes(groupName)) {
        successCount++;
        continue;
      }
      
      // 添加新分组
      currentGroups.push(groupName);
      const newGroupStr = currentGroups.join(',');
      
      if (await this.updateSourceGroup(sourceId, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量添加到分组 "${groupName}": ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量从分组移除书源
   */
  async removeSourcesFromGroup(sourceIds: string[], groupName: string): Promise<number> {
    let successCount = 0;
    
    for (const sourceId of sourceIds) {
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 获取当前分组
      const currentGroups = source.bookSourceGroup 
        ? source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0)
        : [];
      
      // 移除指定分组
      const newGroups = currentGroups.filter(g => g !== groupName);
      
      // 如果分组没有变化，跳过
      if (newGroups.length === currentGroups.length) {
        continue;
      }
      
      const newGroupStr = newGroups.join(',');
      
      if (await this.updateSourceGroup(sourceId, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量从分组 "${groupName}" 移除: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 获取所有分组名称
   */
  getAllGroups(): string[] {
    const groupSet = new Set<string>();
    
    this.sources.forEach(source => {
      if (source.bookSourceGroup) {
        const groups = source.bookSourceGroup.split(',').map(g => g.trim()).filter(g => g.length > 0);
        groups.forEach(g => groupSet.add(g));
      }
    });
    
    return Array.from(groupSet).sort();
  }

  /**
   * 获取分组内的书源
   */
  getSourcesByGroup(groupName: string): NovelSourceInfo[] {
    return this.getAllSources().filter(s => {
      if (!s.group) return false;
      const groups = s.group.split(',').map(g => g.trim());
      return groups.includes(groupName);
    });
  }

  /**
   * 获取无分组的书源
   */
  getSourcesWithoutGroup(): NovelSourceInfo[] {
    return this.getAllSources().filter(s => !s.group || s.group.trim().length === 0);
  }

  /**
   * 重命名分组
   */
  async renameGroup(oldName: string, newName: string): Promise<number> {
    let successCount = 0;
    const sourcesInGroup = this.getSourcesByGroup(oldName);
    
    for (const sourceInfo of sourcesInGroup) {
      const source = this.sources.get(sourceInfo.id);
      if (!source || !source.bookSourceGroup) continue;
      
      const groups = source.bookSourceGroup.split(',').map(g => g.trim());
      const newGroups = groups.map(g => g === oldName ? newName : g);
      const newGroupStr = newGroups.join(',');
      
      if (await this.updateSourceGroup(sourceInfo.id, newGroupStr)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `重命名分组 "${oldName}" -> "${newName}": ${successCount} 个书源`);
    return successCount;
  }

  /**
   * 删除分组（仅移除分组标签，不删除书源）
   */
  async deleteGroup(groupName: string): Promise<number> {
    return this.removeSourcesFromGroup(
      this.getSourcesByGroup(groupName).map(s => s.id),
      groupName
    );
  }

  /**
   * 设置书源权重（用于置顶）
   */
  async setSourceWeight(sourceId: string, weight: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.weight = weight;
    
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `设置书源权重: ${source.bookSourceName} -> ${weight}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `设置书源权重失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 设置书源自定义排序
   * @param sourceId 书源ID
   * @param order 排序顺序（越小越靠前）
   */
  async setSourceCustomOrder(sourceId: string, order: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source) {
      return false;
    }
    
    source.customOrder = order;
    
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(source);
      logger.debug(TAG, `设置书源排序: ${source.bookSourceName} -> ${order}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `设置书源排序失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 批量更新书源排序
   * 将传入的书源ID列表按顺序设置 customOrder
   * @param sourceIds 按顺序排列的书源ID列表
   */
  async batchUpdateSourceOrder(sourceIds: string[]): Promise<number> {
    let successCount = 0;
    
    for (let i = 0; i < sourceIds.length; i++) {
      const sourceId = sourceIds[i];
      const source = this.sources.get(sourceId);
      if (!source) continue;
      
      // 只为启用的书源设置排序
      if (source.enabled !== false) {
        source.customOrder = i;
        try {
          const dataManager = getNovelDataManager();
          await dataManager.saveSource(source);
          successCount++;
        } catch (error) {
          logger.warn(TAG, `更新书源排序失败: ${source.bookSourceName}, ${String(error)}`);
        }
      }
    }
    
    logger.info(TAG, `批量更新书源排序完成: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量置顶书源
   */
  async topSources(sourceIds: string[]): Promise<number> {
    // 获取当前最小的 customOrder
    let minOrder = 0;
    this.sources.forEach(source => {
      if (source.enabled !== false && source.customOrder !== undefined && source.customOrder < minOrder) {
        minOrder = source.customOrder;
      }
    });
    
    let successCount = 0;
    // 从最小值开始向前分配
    for (let i = 0; i < sourceIds.length; i++) {
      const newOrder = minOrder - sourceIds.length + i;
      if (await this.setSourceCustomOrder(sourceIds[i], newOrder)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量置顶: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 批量置底书源
   */
  async bottomSources(sourceIds: string[]): Promise<number> {
    // 获取当前最大的 customOrder
    let maxOrder = 0;
    this.sources.forEach(source => {
      if (source.enabled !== false && source.customOrder !== undefined && source.customOrder > maxOrder) {
        maxOrder = source.customOrder;
      }
    });
    
    let successCount = 0;
    // 从最大值开始向后分配
    for (let i = 0; i < sourceIds.length; i++) {
      const newOrder = maxOrder + i + 1;
      if (await this.setSourceCustomOrder(sourceIds[i], newOrder)) {
        successCount++;
      }
    }
    
    logger.info(TAG, `批量置底: ${successCount}/${sourceIds.length}`);
    return successCount;
  }

  /**
   * 移动书源到指定位置
   * @param sourceId 要移动的书源ID
   * @param targetIndex 目标位置索引
   */
  async moveSource(sourceId: string, targetIndex: number): Promise<boolean> {
    const source = this.sources.get(sourceId);
    if (!source || source.enabled === false) {
      return false;
    }
    
    // 获取当前启用的书源列表（按 customOrder 排序）
    const enabledSources = this.getAllSources().filter(s => s.enabled);
    const currentIndex = enabledSources.findIndex(s => s.id === sourceId);
    
    if (currentIndex === -1 || targetIndex < 0 || targetIndex >= enabledSources.length) {
      return false;
    }
    
    // 从当前位置移除
    enabledSources.splice(currentIndex, 1);
    // 插入到目标位置
    const movedSource = this.getAllSources().find(s => s.id === sourceId)!;
    enabledSources.splice(targetIndex, 0, movedSource);
    
    // 更新所有书源的 customOrder
    const sourceIdsInOrder = enabledSources.map(s => s.id);
    await this.batchUpdateSourceOrder(sourceIdsInOrder);
    
    return true;
  }
}

/**
 * 获取小说源管理器实例
 */
export function getNovelSourceManager(): NovelSourceManager {
  return NovelSourceManager.getInstance();
}
