/**
 * 全局搜索服务
 * 统一管理所有内容类型的搜索逻辑
 * 
 * 文件路径: entry/src/main/ets/Framework/Services/GlobalSearchService.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataService } from './DataService';
import { ComicInfo } from '../Data/DataManager';
import { ComicInfo as OnlineComicInfo } from '../Source/SourceExecutor';
import { EBookDataManager } from '../Data/EBookDataManager';
import { getNovelDataManager, NovelDataManager } from '../Novel/NovelDataManager';
import { getNovelSourceManager, NovelSourceManager } from '../Novel/NovelSourceManager';
import { SearchParseOptions } from '../Novel/NovelSourceExecutor';
import { SourceManager, SourceInfo } from '../Source/SourceManager';
import { SuwayomiSourceExecutor, SuwayomiExtensionSource } from '../Source/SuwayomiSourceExecutor';
import { EBook } from '../../Models/EBookModels';
import { NovelBook, NovelSearchResult, NovelSourceInfo } from '../../Models/NovelModels';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { SourceDetailSearchExecutor, SourceDetailSearchResult, getSourceDetailSearchExecutor } from './SourceDetailSearchExecutor';
import { LegadoBookSourceType } from '../Novel/LegadoSourceTypes';
import { SettingsManager } from '../Managers/SettingsManager';
import { GlobalSearchScheduler, GlobalSearchQueuedTask } from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchScheduler';
import { GlobalSearchFlowMonitor, getGlobalSearchFlowMonitor } from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowMonitor';
import {
  GlobalSearchFlowEvent,
  GlobalSearchFlowEventType,
  GlobalSearchFlowSessionInfo,
  GlobalSearchFlowSeverity
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchFlowTypes';
import {
  GlobalSearchCancelSignal,
  GlobalSearchMetrics,
  GlobalSearchPatchCallback,
  GlobalSearchPatchType,
  GlobalSearchProgressPatch,
  GlobalSearchSessionHandle,
  GlobalSearchTaskKind,
  GlobalSearchTimeoutResult
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchSessionTypes';
import {
  getGlobalSearchIndexManager,
  GlobalSearchIndexManager,
  GlobalSearchIndexSummary,
  GlobalSearchLocalIndexContentType
} from 'manxia_source_engine/src/main/ets/Framework/Search/GlobalSearchIndexManager';

const TAG = 'GlobalSearchService';
const DEFAULT_LOCAL_TIMEOUT_MS: number = 2500;
const DEFAULT_NETWORK_TIMEOUT_MS: number = 12000;
const DEFAULT_WEBVIEW_TIMEOUT_MS: number = 30000;
const DEFAULT_GLOBAL_TIMEOUT_MS: number = 75000;
const DEFAULT_LOCAL_RESULT_LIMIT: number = 1000;
const DEFAULT_ONLINE_RESULT_LIMIT_PER_SOURCE: number = 80;
const DEFAULT_LOCAL_CONCURRENCY: number = 2;
const DEFAULT_NETWORK_CONCURRENCY: number = 3;
const DEFAULT_WEBVIEW_CONCURRENCY: number = 1;
const DEFAULT_SUWAYOMI_CONCURRENCY: number = 1;
const RUNTIME_CACHE_TTL_MS: number = 5 * 60 * 1000;

// ==================== 类型定义 ====================

/**
 * 搜索内容类型
 */
export enum SearchContentType {
  ALL = 'all',           // 全部
  MANGA = 'manga',       // 漫画
  NOVEL = 'novel',       // 小说
  EBOOK = 'ebook'        // 电子书
}

/**
 * 搜索来源类型
 */
export enum SearchSourceType {
  ALL = 'all',           // 全部
  LOCAL = 'local',       // 本地
  ONLINE = 'online'      // 在线
}

/**
 * 在线源类型
 */
export enum OnlineSourceType {
  MANGA_SOURCE = 'manga_source',     // 漫画图源
  SUWAYOMI = 'suwayomi',             // Suwayomi
  NOVEL_SOURCE = 'novel_source'      // 小说书源
}

/**
 * 统一搜索结果项
 */
export interface UnifiedSearchItem {
  id: string;                        // 唯一ID
  title: string;                     // 标题
  author?: string;                   // 作者
  coverUrl?: string;                 // 封面URL
  description?: string;              // 简介
  contentType: SearchContentType;    // 内容类型
  sourceType: SearchSourceType;      // 来源类型（本地/在线）
  onlineSourceType?: OnlineSourceType; // 在线源类型
  sourceId: string;                  // 源ID
  sourceName: string;                // 源名称
  sourcePkg?: string;                // 图源稳定包名（Legado IMAGE 虚拟图源恢复用）
  // 原始数据
  rawManga?: ComicInfo;
  rawEbook?: EBook;
  rawNovelBook?: NovelBook;
  rawNovelSearch?: NovelSearchResult;
  rawOnlineComic?: OnlineComicInfo;
}

/**
 * 搜索源分组结果
 */
export interface SearchSourceGroup {
  groupId: string;                   // 分组ID
  groupName: string;                 // 分组名称
  contentType: SearchContentType;    // 内容类型
  sourceType: SearchSourceType;      // 来源类型
  onlineSourceType?: OnlineSourceType; // 在线源类型
  usesWebViewEngine?: boolean;       // 是否使用 WebView workflow 引擎
  items: UnifiedSearchItem[];        // 搜索结果
  isSearching: boolean;              // 是否正在搜索
  hasError: boolean;                 // 是否有错误
  errorMessage?: string;             // 错误信息
}

/**
 * 搜索筛选配置
 */
export interface SearchFilterConfig {
  contentType: SearchContentType;     // 内容类型筛选
  sourceType: SearchSourceType;       // 来源类型筛选
  selectedMangaSources: string[];     // 选中的漫画图源ID列表
  selectedNovelSources: string[];     // 选中的小说书源ID列表
  enableSuwayomi: boolean;            // 是否启用Suwayomi搜索
  maxConcurrent: number;              // 最大并发数
  sessionId?: string;                  // 搜索会话ID
  perSourceTimeoutMs?: number;         // 单源超时
  globalTimeoutMs?: number;            // 全局超时
  localResultLimit?: number;           // 本地结果上限
  onlineResultLimitPerSource?: number; // 在线单源结果上限
  enableRuntimeCache?: boolean;        // 是否启用在线短期缓存
}

/**
 * 搜索进度回调
 */
export type SearchProgressCallback = (
  completedGroups: number,
  totalGroups: number,
  currentGroupName: string,
  results: SearchSourceGroup[]
) => void;

/**
 * 任务分类结果
 */
interface ClassifiedTasks {
  local: Array<() => Promise<void>>;
  mangaHttp: Array<() => Promise<void>>;
  mangaWebView: Array<() => Promise<void>>;
  novel: Array<() => Promise<void>>;
  suwayomi: Array<() => Promise<void>>;
}

interface GlobalSearchRuntimeCacheEntry {
  cacheKey: string;
  createTime: number;
  items: UnifiedSearchItem[];
}

interface GlobalSearchFullResultCacheEntry {
  cacheKey: string;
  createTime: number;
  groups: SearchSourceGroup[];
  itemCount: number;
}

/**
 * 全局搜索服务类
 */
export class GlobalSearchService {
  private static instance: GlobalSearchService | null = null;
  
  private dataService: DataService;
  private ebookDataManager: EBookDataManager;
  private novelDataManager: NovelDataManager;
  private novelSourceManager: NovelSourceManager;
  private sourceManager: SourceManager;
  private suwayomiExecutor: SuwayomiSourceExecutor;
  private webViewSourceManager: WebViewSourceManager;
  private sourceDetailSearchExecutor: SourceDetailSearchExecutor;
  private settingsManager: SettingsManager;
  private indexManager: GlobalSearchIndexManager;
  private flowMonitor: GlobalSearchFlowMonitor;
  private sessionCounter: number = 0;
  private runtimeCache: Map<string, GlobalSearchRuntimeCacheEntry> = new Map();
  private inFlightRequests: Map<string, Promise<UnifiedSearchItem[]>> = new Map();
  private fullResultCache: Map<string, GlobalSearchFullResultCacheEntry> = new Map();
  private readonly FULL_RESULT_CACHE_LIMIT: number = 20;

  private constructor() {
    this.dataService = DataService.getInstance();
    this.ebookDataManager = EBookDataManager.getInstance();
    this.novelDataManager = getNovelDataManager();
    this.novelSourceManager = getNovelSourceManager();
    this.sourceManager = SourceManager.getInstance();
    this.suwayomiExecutor = SuwayomiSourceExecutor.getInstance();
    this.webViewSourceManager = WebViewSourceManager.getInstance();
    this.sourceDetailSearchExecutor = getSourceDetailSearchExecutor();
    this.settingsManager = SettingsManager.getInstance();
    this.indexManager = getGlobalSearchIndexManager();
    this.flowMonitor = getGlobalSearchFlowMonitor();
  }

  /**
   * 获取单例实例
   */
  static getInstance(): GlobalSearchService {
    if (!GlobalSearchService.instance) {
      GlobalSearchService.instance = new GlobalSearchService();
    }
    return GlobalSearchService.instance;
  }

  // ==================== 获取可用源 ====================

  /**
   * 获取可用的漫画图源列表（按置顶排序）
   */
  async getAvailableMangaSources(): Promise<SourceInfo[]> {
    try {
      return await this.sourceManager.getEnabledSourcesSortedByPinned();
    } catch (error) {
      logger.error(TAG, `获取漫画图源失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取可用的小说书源列表
   */
  getAvailableNovelSources(): NovelSourceInfo[] {
    try {
      return this.novelSourceManager.getEnabledSources().filter((source: NovelSourceInfo): boolean => {
        return source.searchable && source.bookSourceType !== LegadoBookSourceType.IMAGE;
      });
    } catch (error) {
      logger.error(TAG, `获取小说书源失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取可用的Suwayomi扩展源列表
   */
  async getAvailableSuwayomiSources(): Promise<SuwayomiExtensionSource[]> {
    try {
      if (!this.suwayomiExecutor.isConfigured()) {
        return [];
      }
      return await this.suwayomiExecutor.getAvailableSources();
    } catch (error) {
      logger.error(TAG, `获取Suwayomi源失败: ${error}`);
      return [];
    }
  }

  /**
   * 检查Suwayomi是否已配置
   */
  isSuwayomiConfigured(): boolean {
    return this.suwayomiExecutor.isConfigured();
  }

  // ==================== 本地搜索 ====================

  /**
   * 搜索本地漫画
   */
  async searchLocalManga(keyword: string): Promise<UnifiedSearchItem[]> {
    try {
      const searchResult = await this.dataService.searchComics(keyword);
      return searchResult.comics.map((comic: ComicInfo): UnifiedSearchItem => ({
        id: `local-manga-${comic.id}`,
        title: comic.title,
        author: comic.author,
        coverUrl: comic.coverLocalPath || comic.coverUrl,
        description: comic.description,
        contentType: SearchContentType.MANGA,
        sourceType: SearchSourceType.LOCAL,
        sourceId: 'local-manga',
        sourceName: '本地漫画',
        rawManga: comic
      }));
    } catch (error) {
      logger.error(TAG, `搜索本地漫画失败: ${error}`);
      return [];
    }
  }

  /**
   * 搜索本地电子书
   */
  async searchLocalEbooks(keyword: string): Promise<UnifiedSearchItem[]> {
    try {
      const ebooks = await this.ebookDataManager.searchEBooks(keyword);
      return ebooks.map((ebook: EBook): UnifiedSearchItem => ({
        id: `local-ebook-${ebook.id}`,
        title: ebook.metadata.title,
        author: ebook.metadata.author,
        coverUrl: ebook.metadata.coverImagePath,
        description: ebook.metadata.description,
        contentType: SearchContentType.EBOOK,
        sourceType: SearchSourceType.LOCAL,
        sourceId: 'local-ebook',
        sourceName: '本地电子书',
        rawEbook: ebook
      }));
    } catch (error) {
      logger.error(TAG, `搜索本地电子书失败: ${error}`);
      return [];
    }
  }

  /**
   * 搜索本地小说
   */
  async searchLocalNovels(keyword: string): Promise<UnifiedSearchItem[]> {
    try {
      const novels = await this.novelDataManager.searchBooks(keyword);
      return novels.map((novel: NovelBook): UnifiedSearchItem => ({
        id: `local-novel-${novel.id}`,
        title: novel.name,
        author: novel.author,
        coverUrl: novel.coverUrl,
        description: novel.intro,
        contentType: SearchContentType.NOVEL,
        sourceType: SearchSourceType.LOCAL,
        sourceId: 'local-novel',
        sourceName: '本地小说',
        rawNovelBook: novel
      }));
    } catch (error) {
      logger.error(TAG, `搜索本地小说失败: ${error}`);
      return [];
    }
  }

  private async searchLocalMangaV2(keyword: string, limit: number): Promise<UnifiedSearchItem[]> {
    const indexedItems: UnifiedSearchItem[] | null = await this.searchLocalIndex(
      keyword,
      limit,
      GlobalSearchLocalIndexContentType.MANGA
    );
    if (indexedItems !== null) {
      return indexedItems;
    }
    const items: UnifiedSearchItem[] = await this.searchLocalManga(keyword);
    return this.limitItems(items, limit);
  }

  private async searchLocalEbooksV2(keyword: string, limit: number): Promise<UnifiedSearchItem[]> {
    const indexedItems: UnifiedSearchItem[] | null = await this.searchLocalIndex(
      keyword,
      limit,
      GlobalSearchLocalIndexContentType.EBOOK
    );
    if (indexedItems !== null) {
      return indexedItems;
    }
    const items: UnifiedSearchItem[] = await this.searchLocalEbooks(keyword);
    return this.limitItems(items, limit);
  }

  private async searchLocalNovelsV2(keyword: string, limit: number): Promise<UnifiedSearchItem[]> {
    const items: UnifiedSearchItem[] = await this.searchLocalNovels(keyword);
    return this.limitItems(items, limit);
  }

  private async searchLocalIndex(
    keyword: string,
    limit: number,
    contentType: GlobalSearchLocalIndexContentType
  ): Promise<UnifiedSearchItem[] | null> {
    const summaries: GlobalSearchIndexSummary[] | null = await this.indexManager.search(contentType, keyword, limit);
    if (summaries === null) {
      return null;
    }
    const items: UnifiedSearchItem[] = [];
    for (const summary of summaries) {
      const item: UnifiedSearchItem = {
        id: `${summary.contentType === GlobalSearchLocalIndexContentType.EBOOK ? 'local-ebook' : 'local-manga'}-${summary.contentId}`,
        title: summary.title,
        author: summary.author,
        coverUrl: summary.coverUrl,
        description: summary.description,
        contentType: summary.contentType === GlobalSearchLocalIndexContentType.EBOOK ? SearchContentType.EBOOK : SearchContentType.MANGA,
        sourceType: SearchSourceType.LOCAL,
        sourceId: summary.sourceId.length > 0 ? summary.sourceId : summary.sourceName,
        sourceName: summary.sourceName
      };
      items.push(item);
    }
    return items;
  }

  // ==================== 在线搜索 ====================

  /**
   * 搜索在线漫画（单个图源）
   * 支持两种图源格式：
   * - HTTP 格式（features配置）：使用 SourceExecutor
   * - WebView 格式（workflows配置）：使用 MangaSourceEngine
   */
  async searchOnlineManga(
    sourceId: number,
    keyword: string,
    page: number = 1,
    sourceInfo?: SourceInfo,
    signal?: GlobalSearchCancelSignal,
    searchGeneration?: number
  ): Promise<UnifiedSearchItem[]> {
    try {
      // 获取图源信息
      const source = sourceInfo ? sourceInfo : null;
      const sourceName = source?.name || `图源${sourceId}`;
      if (signal && signal.isCancelled()) {
        return [];
      }
      const sourceSearchResult: SourceDetailSearchResult = await this.sourceDetailSearchExecutor.search({
        sourceId: sourceId,
        query: keyword,
        searchType: 'search',
        page: page,
        cancelSignal: signal,
        searchGeneration: searchGeneration
      });
      if (signal && signal.isCancelled()) {
        return [];
      }
      if (!sourceSearchResult.success) {
        throw new Error(sourceSearchResult.errorMessage || '图源搜索失败');
      }
      const results: OnlineComicInfo[] = sourceSearchResult.items;
      
      return results.map((comic: OnlineComicInfo): UnifiedSearchItem => ({
        id: `online-manga-${sourceId}-${comic.id}`,
        title: comic.title,
        author: comic.author,
        coverUrl: comic.coverUrl,
        description: comic.description,
        contentType: SearchContentType.MANGA,
        sourceType: SearchSourceType.ONLINE,
        onlineSourceType: OnlineSourceType.MANGA_SOURCE,
        sourceId: String(sourceId),
        sourceName: sourceSearchResult.sourceName || sourceName,
        sourcePkg: source?.pkg || '',
        rawOnlineComic: comic
      }));
    } catch (error) {
      logger.error(TAG, `搜索在线漫画失败 (sourceId=${sourceId}): ${error}`);
      throw new Error(`搜索在线漫画失败: ${String(error)}`);
    }
  }
  
  /**
   * 搜索Suwayomi漫画（库搜索或指定源搜索）
   */
  async searchSuwayomi(keyword: string, sourceId?: string): Promise<UnifiedSearchItem[]> {
    try {
      if (!this.suwayomiExecutor.isConfigured()) {
        logger.warn(TAG, 'Suwayomi未配置');
        return [];
      }

      let results: OnlineComicInfo[];
      if (sourceId) {
        this.suwayomiExecutor.setCurrentSource(sourceId);
        results = await this.suwayomiExecutor.search(keyword);
      } else {
        results = await this.suwayomiExecutor.searchLibrary(keyword);
      }

      return results.map((comic: OnlineComicInfo): UnifiedSearchItem => ({
        id: `suwayomi-${sourceId || 'library'}-${comic.id}`,
        title: comic.title,
        author: comic.author,
        coverUrl: comic.coverUrl,
        description: comic.description,
        contentType: SearchContentType.MANGA,
        sourceType: SearchSourceType.ONLINE,
        onlineSourceType: OnlineSourceType.SUWAYOMI,
        sourceId: sourceId || 'suwayomi-library',
        sourceName: sourceId ? `Suwayomi-${sourceId}` : 'Suwayomi库',
        rawOnlineComic: comic
      }));
    } catch (error) {
      logger.error(TAG, `搜索Suwayomi失败: ${error}`);
      return [];
    }
  }

  /**
   * 搜索在线小说（单个书源）
   */
  async searchOnlineNovel(sourceId: string, keyword: string, page: number = 1): Promise<UnifiedSearchItem[]> {
    try {
      const parseOptions: SearchParseOptions = {
        yieldSliceMs: 12
      };
      const results = await this.novelSourceManager.search(sourceId, keyword, page, parseOptions);
      return results.map((novel: NovelSearchResult): UnifiedSearchItem => ({
        id: `online-novel-${sourceId}-${novel.bookUrl}`,
        title: novel.name,
        author: novel.author,
        coverUrl: novel.coverUrl,
        description: novel.intro,
        contentType: SearchContentType.NOVEL,
        sourceType: SearchSourceType.ONLINE,
        onlineSourceType: OnlineSourceType.NOVEL_SOURCE,
        sourceId: sourceId,
        sourceName: novel.sourceName,
        rawNovelSearch: novel
      }));
    } catch (error) {
      logger.error(TAG, `搜索在线小说失败 (sourceId=${sourceId}): ${error}`);
      return [];
    }
  }

  // ==================== 统一搜索 ====================

  /**
   * 执行全局搜索。默认走 v2 session runner；关闭回滚开关后走旧流程。
   */
  async searchAll(
    keyword: string,
    filter: SearchFilterConfig,
    onProgress?: SearchProgressCallback,
    onPatch?: GlobalSearchPatchCallback
  ): Promise<SearchSourceGroup[]> {
    if (!this.settingsManager.getGlobalSearchV2Enabled()) {
      return await this.searchAllLegacy(keyword, filter, onProgress);
    }
    const handle: GlobalSearchSessionHandle<SearchSourceGroup[]> = this.createSearchSession(
      keyword,
      filter,
      onProgress,
      onPatch
    );
    return await handle.completion;
  }

  createSearchSession(
    keyword: string,
    filter: SearchFilterConfig,
    onProgress?: SearchProgressCallback,
    onPatch?: GlobalSearchPatchCallback
  ): GlobalSearchSessionHandle<SearchSourceGroup[]> {
    const sessionId: string = filter.sessionId && filter.sessionId.length > 0 ? filter.sessionId : this.createSessionId();
    const signal: GlobalSearchCancelSignal = new GlobalSearchCancelSignal();
    const normalizedFilter: SearchFilterConfig = this.normalizeFilterConfig(filter, sessionId);
    const sessionInfo: GlobalSearchFlowSessionInfo = this.buildFlowSessionInfo(sessionId, keyword, normalizedFilter, 'GlobalSearchService');
    this.flowMonitor.ensureSession(sessionInfo);
    const boundEvent: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.SESSION_BOUND, 'create_search_session');
    boundEvent.keyword = keyword;
    boundEvent.contentType = normalizedFilter.contentType;
    boundEvent.sourceType = normalizedFilter.sourceType;
    boundEvent.detail = `timeout=${normalizedFilter.perSourceTimeoutMs}/${normalizedFilter.globalTimeoutMs}, localLimit=${normalizedFilter.localResultLimit}, onlineLimit=${normalizedFilter.onlineResultLimitPerSource}, runtimeCache=${normalizedFilter.enableRuntimeCache}`;
    this.flowMonitor.record(boundEvent);
    const completion: Promise<SearchSourceGroup[]> = this.runSearchSession(
      sessionId,
      keyword,
      normalizedFilter,
      signal,
      onProgress,
      onPatch
    );
    return new GlobalSearchSessionHandle<SearchSourceGroup[]>(
      sessionId,
      signal,
      completion,
      (reason: string): void => {
        signal.cancel(reason);
        this.sourceDetailSearchExecutor.cancelGlobalSearchWork(reason);
      }
    );
  }

  public getCachedFullSearchResult(keyword: string, filter: SearchFilterConfig): SearchSourceGroup[] | null {
    const flowSessionId: string = filter.sessionId && filter.sessionId.length > 0 ? filter.sessionId : '';
    const cacheKey: string = this.buildFullResultCacheKey(keyword, this.normalizeFilterConfig(filter, 'full_result_cache_lookup'));
    const entry: GlobalSearchFullResultCacheEntry | undefined = this.fullResultCache.get(cacheKey);
    if (!entry) {
      this.recordFullResultCacheEvent(flowSessionId, keyword, cacheKey, GlobalSearchFlowEventType.FULL_CACHE_MISS, 0, 0);
      return null;
    }
    logger.info(TAG, `命中完整搜索结果运行期缓存: key=${cacheKey}, groups=${entry.groups.length}, items=${entry.itemCount}`);
    entry.createTime = Date.now();
    this.recordFullResultCacheEvent(flowSessionId, keyword, cacheKey, GlobalSearchFlowEventType.FULL_CACHE_HIT, entry.groups.length, entry.itemCount);
    return this.cloneSearchGroupsForProgress(entry.groups, true);
  }

  public cacheFullSearchResult(keyword: string, filter: SearchFilterConfig, groups: SearchSourceGroup[]): void {
    if (!this.canCacheFullSearchResult(groups)) {
      logger.info(TAG, `完整搜索结果未写入运行期缓存: keyword=${keyword}, groups=${groups.length}, reason=not_complete`);
      return;
    }
    const normalizedFilter: SearchFilterConfig = this.normalizeFilterConfig(filter, 'full_result_cache_store');
    const cacheKey: string = this.buildFullResultCacheKey(keyword, normalizedFilter);
    const snapshot: SearchSourceGroup[] = this.cloneSearchGroupsForProgress(groups, true);
    const entry: GlobalSearchFullResultCacheEntry = {
      cacheKey: cacheKey,
      createTime: Date.now(),
      groups: snapshot,
      itemCount: this.countItems(snapshot)
    };
    this.fullResultCache.set(cacheKey, entry);
    this.trimFullResultCache();
    logger.info(TAG, `完整搜索结果已写入运行期缓存: key=${cacheKey}, groups=${snapshot.length}, items=${entry.itemCount}`);
    const flowSessionId: string = normalizedFilter.sessionId && normalizedFilter.sessionId.length > 0 ? normalizedFilter.sessionId : '';
    if (flowSessionId.length > 0) {
      const event: GlobalSearchFlowEvent = this.flowMonitor.createEvent(flowSessionId, GlobalSearchFlowEventType.RUNTIME_CACHE_WRITTEN, 'full_result_cache_store');
      event.keyword = keyword;
      event.cacheKey = cacheKey;
      event.itemCount = entry.itemCount;
      event.totalGroups = snapshot.length;
      event.detail = 'full_result_cache';
      this.flowMonitor.record(event);
    }
  }

  private canCacheFullSearchResult(groups: SearchSourceGroup[]): boolean {
    for (const group of groups) {
      if (group.isSearching || group.hasError) {
        return false;
      }
    }
    return true;
  }

  private recordFullResultCacheEvent(
    sessionId: string,
    keyword: string,
    cacheKey: string,
    eventType: GlobalSearchFlowEventType,
    groupCount: number,
    itemCount: number
  ): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, eventType, 'full_result_cache');
    event.keyword = keyword;
    event.cacheKey = cacheKey;
    event.totalGroups = groupCount;
    event.itemCount = itemCount;
    event.cacheHit = eventType === GlobalSearchFlowEventType.FULL_CACHE_HIT;
    this.flowMonitor.record(event);
  }

  private async runSearchSession(
    sessionId: string,
    keyword: string,
    filter: SearchFilterConfig,
    signal: GlobalSearchCancelSignal,
    onProgress?: SearchProgressCallback,
    onPatch?: GlobalSearchPatchCallback
  ): Promise<SearchSourceGroup[]> {
    const groups: SearchSourceGroup[] = [];
    const tasks: GlobalSearchQueuedTask[] = [];
    const metrics: GlobalSearchMetrics = new GlobalSearchMetrics();
    const scheduler: GlobalSearchScheduler = new GlobalSearchScheduler({
      localConcurrency: DEFAULT_LOCAL_CONCURRENCY,
      networkConcurrency: Math.max(1, Math.min(filter.maxConcurrent || DEFAULT_NETWORK_CONCURRENCY, DEFAULT_NETWORK_CONCURRENCY)),
      webViewConcurrency: DEFAULT_WEBVIEW_CONCURRENCY,
      suwayomiConcurrency: DEFAULT_SUWAYOMI_CONCURRENCY,
      flowSessionId: sessionId
    });

    await this.buildSessionTasks(sessionId, keyword, filter, signal, scheduler, groups, tasks, metrics, onProgress, onPatch);
    metrics.begin(sessionId, keyword, groups.length);
    const tasksBuiltEvent: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.TASKS_BUILT, 'build_session_tasks');
    tasksBuiltEvent.keyword = keyword;
    tasksBuiltEvent.contentType = filter.contentType;
    tasksBuiltEvent.sourceType = filter.sourceType;
    tasksBuiltEvent.totalGroups = groups.length;
    tasksBuiltEvent.itemCount = tasks.length;
    tasksBuiltEvent.detail = `tasks=${tasks.length}, maxConcurrent=${filter.maxConcurrent}`;
    this.flowMonitor.record(tasksBuiltEvent);

    logger.info(TAG, `开始全局搜索v2: session=${sessionId}, keyword="${keyword}", groups=${groups.length}`);
    this.emitSnapshot(onProgress, 0, groups.length, '', groups, false);

    const globalTimeoutMs: number = filter.globalTimeoutMs || DEFAULT_GLOBAL_TIMEOUT_MS;
    const runResult: GlobalSearchTimeoutResult<void> = await scheduler.waitWithTimeout<void>(
      scheduler.run(tasks, signal),
      globalTimeoutMs,
      signal
    );

    if (runResult.timedOut) {
      logger.warn(TAG, `全局搜索v2超时: session=${sessionId}, timeout=${globalTimeoutMs}ms`);
      signal.cancel('global_timeout');
      this.sourceDetailSearchExecutor.cancelGlobalSearchWork('global_timeout');
      this.finishRemainingGroupsAsTimeout(groups, metrics);
      const timeoutEvent: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.GLOBAL_TIMEOUT, 'global_timeout');
      timeoutEvent.keyword = keyword;
      timeoutEvent.totalGroups = groups.length;
      timeoutEvent.completedGroups = metrics.completedGroups;
      timeoutEvent.elapsedMs = metrics.getDurationMs();
      timeoutEvent.success = false;
      timeoutEvent.timedOut = true;
      timeoutEvent.errorMessage = `timeout ${globalTimeoutMs}ms`;
      timeoutEvent.severity = GlobalSearchFlowSeverity.ERROR;
      this.flowMonitor.record(timeoutEvent);
    }

    for (const group of groups) {
      group.isSearching = false;
    }

    const resultCount: number = this.countItems(groups);
    metrics.finish(resultCount);
    if (!signal.isCancelled() || runResult.timedOut) {
      this.emitSnapshot(onProgress, groups.length, groups.length, '', groups, true);
      const donePatch: GlobalSearchProgressPatch = {
        sessionId: sessionId,
        patchType: GlobalSearchPatchType.SESSION_DONE,
        completedGroups: groups.length,
        totalGroups: groups.length,
        itemCount: resultCount
      };
      this.emitPatch(onPatch, donePatch, metrics);
    }
    this.logMetricsIfEnabled(metrics);
    const completedEvent: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.RESULT_COMPLETED, signal.isCancelled() ? signal.getReason() : 'completed');
    completedEvent.keyword = keyword;
    completedEvent.contentType = filter.contentType;
    completedEvent.sourceType = filter.sourceType;
    completedEvent.completedGroups = groups.length;
    completedEvent.totalGroups = groups.length;
    completedEvent.resultCount = resultCount;
    completedEvent.elapsedMs = metrics.getDurationMs();
    completedEvent.metricName = 'global_search_session_duration';
    completedEvent.metricValue = completedEvent.elapsedMs;
    completedEvent.metricUnit = 'ms';
    completedEvent.success = !runResult.timedOut;
    if (runResult.timedOut) {
      completedEvent.severity = GlobalSearchFlowSeverity.WARN;
    }
    this.flowMonitor.record(completedEvent);
    const endReason: string = runResult.timedOut ? 'global_timeout' : (signal.isCancelled() ? signal.getReason() : 'completed');
    this.flowMonitor.endSession(sessionId, endReason);
    return groups;
  }

  private async buildSessionTasks(
    sessionId: string,
    keyword: string,
    filter: SearchFilterConfig,
    signal: GlobalSearchCancelSignal,
    scheduler: GlobalSearchScheduler,
    groups: SearchSourceGroup[],
    tasks: GlobalSearchQueuedTask[],
    metrics: GlobalSearchMetrics,
    onProgress?: SearchProgressCallback,
    onPatch?: GlobalSearchPatchCallback
  ): Promise<void> {
    const localLimit: number = filter.localResultLimit || DEFAULT_LOCAL_RESULT_LIMIT;
    const onlineLimit: number = filter.onlineResultLimitPerSource || DEFAULT_ONLINE_RESULT_LIMIT_PER_SOURCE;

    if (filter.sourceType === SearchSourceType.ALL || filter.sourceType === SearchSourceType.LOCAL) {
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.MANGA) {
        const group: SearchSourceGroup = this.createGroup('local-manga', '本地漫画', SearchContentType.MANGA, SearchSourceType.LOCAL);
        groups.push(group);
        this.addSessionTask(sessionId, group, GlobalSearchTaskKind.LOCAL, DEFAULT_LOCAL_TIMEOUT_MS, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
          return await this.searchLocalMangaV2(keyword, localLimit);
        });
      }

      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.EBOOK) {
        const group: SearchSourceGroup = this.createGroup('local-ebook', '本地电子书', SearchContentType.EBOOK, SearchSourceType.LOCAL);
        groups.push(group);
        this.addSessionTask(sessionId, group, GlobalSearchTaskKind.LOCAL, DEFAULT_LOCAL_TIMEOUT_MS, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
          return await this.searchLocalEbooksV2(keyword, localLimit);
        });
      }

      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.NOVEL) {
        const group: SearchSourceGroup = this.createGroup('local-novel', '本地小说', SearchContentType.NOVEL, SearchSourceType.LOCAL);
        groups.push(group);
        this.addSessionTask(sessionId, group, GlobalSearchTaskKind.LOCAL, DEFAULT_LOCAL_TIMEOUT_MS, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
          return await this.searchLocalNovelsV2(keyword, localLimit);
        });
      }
    }

    if (filter.sourceType === SearchSourceType.ALL || filter.sourceType === SearchSourceType.ONLINE) {
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.MANGA) {
        const allSources: SourceInfo[] = await this.sourceManager.getAllSources();
        const searchGeneration: number = this.sourceDetailSearchExecutor.getGlobalSearchGeneration();
        for (const sourceId of filter.selectedMangaSources) {
          const numSourceId: number = parseInt(sourceId);
          if (isNaN(numSourceId)) {
            continue;
          }
          const source: SourceInfo | null = this.findSourceById(allSources, numSourceId);
          const sourceName: string = source ? source.name : `图源${sourceId}`;
          const isWebViewSource: boolean = await this.webViewSourceManager.isWebViewSource(numSourceId);
          const group: SearchSourceGroup = this.createGroup(
            `online-manga-${sourceId}`,
            sourceName,
            SearchContentType.MANGA,
            SearchSourceType.ONLINE,
            OnlineSourceType.MANGA_SOURCE,
            isWebViewSource
          );
          groups.push(group);
          const taskKind: GlobalSearchTaskKind = isWebViewSource ? GlobalSearchTaskKind.MANGA_WEBVIEW : GlobalSearchTaskKind.MANGA_HTTP;
          const timeoutMs: number = isWebViewSource ? DEFAULT_WEBVIEW_TIMEOUT_MS : (filter.perSourceTimeoutMs || DEFAULT_NETWORK_TIMEOUT_MS);
          const cacheKey: string = this.buildRuntimeCacheKey('manga', sourceId, keyword);
          this.addSessionTask(sessionId, group, taskKind, timeoutMs, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
            return await this.searchWithRuntimeCache(sessionId, keyword, group, cacheKey, filter.enableRuntimeCache === true, async (): Promise<UnifiedSearchItem[]> => {
              const items: UnifiedSearchItem[] = await this.searchOnlineManga(numSourceId, keyword, 1, source || undefined, signal, searchGeneration);
              return this.limitItems(items, onlineLimit);
            });
          });
        }

        if (filter.enableSuwayomi && this.isSuwayomiConfigured()) {
          const group: SearchSourceGroup = this.createGroup(
            'suwayomi-library',
            'Suwayomi',
            SearchContentType.MANGA,
            SearchSourceType.ONLINE,
            OnlineSourceType.SUWAYOMI
          );
          groups.push(group);
          const cacheKey: string = this.buildRuntimeCacheKey('suwayomi', 'library', keyword);
          this.addSessionTask(sessionId, group, GlobalSearchTaskKind.SUWAYOMI, filter.perSourceTimeoutMs || DEFAULT_NETWORK_TIMEOUT_MS, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
            return await this.searchWithRuntimeCache(sessionId, keyword, group, cacheKey, filter.enableRuntimeCache === true, async (): Promise<UnifiedSearchItem[]> => {
              const items: UnifiedSearchItem[] = await this.searchSuwayomi(keyword);
              return this.limitItems(items, onlineLimit);
            });
          });
        }
      }

      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.NOVEL) {
        for (const sourceId of filter.selectedNovelSources) {
          const sourceObj = this.novelSourceManager.getSource(sourceId);
          const sourceName: string = sourceObj?.bookSourceName || sourceId;
          const group: SearchSourceGroup = this.createGroup(
            `online-novel-${sourceId}`,
            sourceName,
            SearchContentType.NOVEL,
            SearchSourceType.ONLINE,
            OnlineSourceType.NOVEL_SOURCE
          );
          groups.push(group);
          const cacheKey: string = this.buildRuntimeCacheKey('novel', sourceId, keyword);
          this.addSessionTask(sessionId, group, GlobalSearchTaskKind.NOVEL, filter.perSourceTimeoutMs || DEFAULT_NETWORK_TIMEOUT_MS, groups, tasks, scheduler, signal, metrics, onProgress, onPatch, async (): Promise<UnifiedSearchItem[]> => {
            return await this.searchWithRuntimeCache(sessionId, keyword, group, cacheKey, filter.enableRuntimeCache === true, async (): Promise<UnifiedSearchItem[]> => {
              const items: UnifiedSearchItem[] = await this.searchOnlineNovel(sourceId, keyword);
              return this.limitItems(items, onlineLimit);
            });
          });
        }
      }
    }
  }

  private addSessionTask(
    sessionId: string,
    group: SearchSourceGroup,
    kind: GlobalSearchTaskKind,
    timeoutMs: number,
    groups: SearchSourceGroup[],
    tasks: GlobalSearchQueuedTask[],
    scheduler: GlobalSearchScheduler,
    signal: GlobalSearchCancelSignal,
    metrics: GlobalSearchMetrics,
    onProgress: SearchProgressCallback | undefined,
    onPatch: GlobalSearchPatchCallback | undefined,
    searchWork: () => Promise<UnifiedSearchItem[]>
  ): void {
    const task: GlobalSearchQueuedTask = {
      taskId: group.groupId,
      taskName: group.groupName,
      kind: kind,
      flowSessionId: sessionId,
      run: async (): Promise<void> => {
        const taskStartedAt: number = Date.now();
        if (signal.isCancelled()) {
          metrics.cancelledGroups++;
          group.isSearching = false;
          this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_CANCELLED, metrics, 0, 0, true, signal.getReason(), true, false);
          return;
        }
        this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_STARTED, metrics, 0, 0, true, '', false, false);
        this.emitGroupPatch(sessionId, group, GlobalSearchPatchType.GROUP_START, metrics, onPatch);
        const result: GlobalSearchTimeoutResult<UnifiedSearchItem[]> = await scheduler.waitWithTimeout<UnifiedSearchItem[]>(
          searchWork(),
          timeoutMs,
          signal
        );
        if (signal.isCancelled() && !result.timedOut) {
          metrics.cancelledGroups++;
          group.isSearching = false;
          this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_CANCELLED, metrics, Date.now() - taskStartedAt, 0, true, signal.getReason(), true, false);
          return;
        }
        if (result.completed) {
          group.items = result.value ? result.value : [];
          group.hasError = false;
          group.errorMessage = undefined;
          const elapsedMs: number = Date.now() - taskStartedAt;
          this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_SUCCEEDED, metrics, elapsedMs, group.items.length, true, '', false, false);
          if (group.items.length > 0 && !metrics.firstResultEmitted) {
            metrics.firstResultEmitted = true;
            const firstResultEvent: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, GlobalSearchFlowEventType.FIRST_RESULT, group.groupName);
            firstResultEvent.groupId = group.groupId;
            firstResultEvent.groupName = group.groupName;
            firstResultEvent.taskKind = kind;
            firstResultEvent.itemCount = group.items.length;
            firstResultEvent.elapsedMs = metrics.startTime > 0 ? Date.now() - metrics.startTime : elapsedMs;
            firstResultEvent.metricName = 'global_search_first_result';
            firstResultEvent.metricValue = firstResultEvent.elapsedMs;
            firstResultEvent.metricUnit = 'ms';
            this.flowMonitor.record(firstResultEvent);
          }
        } else {
          group.items = [];
          group.hasError = true;
          group.errorMessage = result.timedOut ? '搜索超时' : result.errorMessage;
          if (result.timedOut) {
            metrics.timeoutGroups++;
            this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_TIMEOUT, metrics, Date.now() - taskStartedAt, 0, false, group.errorMessage || '', false, true);
          } else {
            metrics.failedGroups++;
            this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_FAILED, metrics, Date.now() - taskStartedAt, 0, false, group.errorMessage || '', false, false);
          }
        }
        group.isSearching = false;
        metrics.completedGroups++;
        this.emitGroupPatch(sessionId, group, result.completed ? GlobalSearchPatchType.GROUP_ITEMS : GlobalSearchPatchType.GROUP_ERROR, metrics, onPatch);
        this.emitGroupPatch(sessionId, group, GlobalSearchPatchType.GROUP_DONE, metrics, onPatch);
        this.emitSnapshot(onProgress, metrics.completedGroups, metrics.totalGroups, group.groupName, groups, false);
      }
    };
    this.recordTaskEvent(sessionId, group, kind, GlobalSearchFlowEventType.TASK_QUEUED, metrics, 0, 0, true, `timeout=${timeoutMs}ms`, false, false);
    tasks.push(task);
  }

  private recordTaskEvent(
    sessionId: string,
    group: SearchSourceGroup,
    kind: GlobalSearchTaskKind,
    eventType: GlobalSearchFlowEventType,
    metrics: GlobalSearchMetrics,
    elapsedMs: number,
    itemCount: number,
    success: boolean,
    detailOrError: string,
    cancelled: boolean,
    timedOut: boolean
  ): void {
    const event: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, eventType, group.groupName);
    event.groupId = group.groupId;
    event.groupName = group.groupName;
    event.taskId = group.groupId;
    event.taskKind = kind;
    event.sourceType = group.sourceType;
    event.sourceName = group.groupName;
    event.completedGroups = metrics.completedGroups;
    event.totalGroups = metrics.totalGroups;
    event.itemCount = itemCount;
    event.elapsedMs = elapsedMs;
    event.success = success;
    event.cancelled = cancelled;
    event.timedOut = timedOut;
    if (success) {
      event.detail = detailOrError;
    } else {
      event.errorMessage = detailOrError;
      event.severity = timedOut ? GlobalSearchFlowSeverity.ERROR : GlobalSearchFlowSeverity.WARN;
    }
    if (elapsedMs > 0) {
      event.metricName = 'global_search_task_duration';
      event.metricValue = elapsedMs;
      event.metricUnit = 'ms';
    }
    this.flowMonitor.record(event);
  }

  private normalizeFilterConfig(filter: SearchFilterConfig, sessionId: string): SearchFilterConfig {
    const config: SearchFilterConfig = {
      contentType: filter.contentType,
      sourceType: filter.sourceType,
      selectedMangaSources: filter.selectedMangaSources.slice(),
      selectedNovelSources: filter.selectedNovelSources.slice(),
      enableSuwayomi: filter.enableSuwayomi,
      maxConcurrent: filter.maxConcurrent > 0 ? filter.maxConcurrent : DEFAULT_NETWORK_CONCURRENCY,
      sessionId: sessionId,
      perSourceTimeoutMs: filter.perSourceTimeoutMs && filter.perSourceTimeoutMs > 0 ? filter.perSourceTimeoutMs : DEFAULT_NETWORK_TIMEOUT_MS,
      globalTimeoutMs: filter.globalTimeoutMs && filter.globalTimeoutMs > 0 ? filter.globalTimeoutMs : DEFAULT_GLOBAL_TIMEOUT_MS,
      localResultLimit: filter.localResultLimit && filter.localResultLimit > 0 ? filter.localResultLimit : DEFAULT_LOCAL_RESULT_LIMIT,
      onlineResultLimitPerSource: filter.onlineResultLimitPerSource && filter.onlineResultLimitPerSource > 0 ? filter.onlineResultLimitPerSource : DEFAULT_ONLINE_RESULT_LIMIT_PER_SOURCE,
      enableRuntimeCache: filter.enableRuntimeCache === undefined ? this.settingsManager.getGlobalSearchOnlineCacheEnabled() : filter.enableRuntimeCache
    };
    return config;
  }

  private createGroup(
    groupId: string,
    groupName: string,
    contentType: SearchContentType,
    sourceType: SearchSourceType,
    onlineSourceType?: OnlineSourceType,
    usesWebViewEngine?: boolean
  ): SearchSourceGroup {
    const group: SearchSourceGroup = {
      groupId: groupId,
      groupName: groupName,
      contentType: contentType,
      sourceType: sourceType,
      onlineSourceType: onlineSourceType,
      usesWebViewEngine: usesWebViewEngine,
      items: [],
      isSearching: true,
      hasError: false
    };
    return group;
  }

  private createSessionId(): string {
    this.sessionCounter++;
    return `gsearch_${Date.now()}_${this.sessionCounter}`;
  }

  private buildFlowSessionInfo(
    sessionId: string,
    keyword: string,
    filter: SearchFilterConfig,
    pageInstanceId: string
  ): GlobalSearchFlowSessionInfo {
    const info: GlobalSearchFlowSessionInfo = new GlobalSearchFlowSessionInfo();
    info.sessionId = sessionId;
    info.keyword = keyword;
    info.contentType = filter.contentType;
    info.sourceType = filter.sourceType;
    info.selectedMangaSourceCount = filter.selectedMangaSources.length;
    info.selectedNovelSourceCount = filter.selectedNovelSources.length;
    info.enableSuwayomi = filter.enableSuwayomi;
    info.maxConcurrent = filter.maxConcurrent;
    info.pageInstanceId = pageInstanceId;
    info.startedAt = Date.now();
    return info;
  }

  private findSourceById(sources: SourceInfo[], sourceId: number): SourceInfo | null {
    for (const source of sources) {
      if (source.id === sourceId) {
        return source;
      }
    }
    return null;
  }

  private async searchWithRuntimeCache(
    sessionId: string,
    keyword: string,
    group: SearchSourceGroup,
    cacheKey: string,
    enabled: boolean,
    work: () => Promise<UnifiedSearchItem[]>
  ): Promise<UnifiedSearchItem[]> {
    if (!enabled) {
      return await work();
    }

    const cached: GlobalSearchRuntimeCacheEntry | undefined = this.runtimeCache.get(cacheKey);
    if (cached && Date.now() - cached.createTime <= RUNTIME_CACHE_TTL_MS) {
      logger.debug(TAG, `命中全局搜索运行期缓存: ${cacheKey}, count=${cached.items.length}`);
      this.recordRuntimeCacheEvent(sessionId, keyword, group, cacheKey, GlobalSearchFlowEventType.RUNTIME_CACHE_HIT, cached.items.length, true, 'runtime_cache_hit');
      return cached.items;
    }
    this.recordRuntimeCacheEvent(sessionId, keyword, group, cacheKey, GlobalSearchFlowEventType.RUNTIME_CACHE_MISS, 0, false, 'runtime_cache_miss');

    const inFlight: Promise<UnifiedSearchItem[]> | undefined = this.inFlightRequests.get(cacheKey);
    if (inFlight) {
      logger.debug(TAG, `复用全局搜索进行中请求: ${cacheKey}`);
      this.recordRuntimeCacheEvent(sessionId, keyword, group, cacheKey, GlobalSearchFlowEventType.RUNTIME_CACHE_IN_FLIGHT_REUSED, 0, true, 'in_flight_reused');
      return await inFlight;
    }

    const promise: Promise<UnifiedSearchItem[]> = work().then((items: UnifiedSearchItem[]): UnifiedSearchItem[] => {
      const entry: GlobalSearchRuntimeCacheEntry = {
        cacheKey: cacheKey,
        createTime: Date.now(),
        items: items
      };
      this.runtimeCache.set(cacheKey, entry);
      this.recordRuntimeCacheEvent(sessionId, keyword, group, cacheKey, GlobalSearchFlowEventType.RUNTIME_CACHE_WRITTEN, items.length, true, 'runtime_cache_written');
      return items;
    });
    this.inFlightRequests.set(cacheKey, promise);
    try {
      return await promise;
    } finally {
      this.inFlightRequests.delete(cacheKey);
    }
  }

  private buildRuntimeCacheKey(sourceType: string, sourceId: string, keyword: string): string {
    return `${sourceType}_${sourceId}_${keyword.trim().toLowerCase()}`;
  }

  private recordRuntimeCacheEvent(
    sessionId: string,
    keyword: string,
    group: SearchSourceGroup,
    cacheKey: string,
    eventType: GlobalSearchFlowEventType,
    itemCount: number,
    cacheHit: boolean,
    reason: string
  ): void {
    if (!sessionId || sessionId.length <= 0) {
      return;
    }
    const event: GlobalSearchFlowEvent = this.flowMonitor.createEvent(sessionId, eventType, reason);
    event.keyword = keyword;
    event.groupId = group.groupId;
    event.groupName = group.groupName;
    event.sourceType = group.sourceType;
    event.sourceName = group.groupName;
    event.cacheKey = cacheKey;
    event.cacheHit = cacheHit;
    event.itemCount = itemCount;
    event.detail = reason;
    this.flowMonitor.record(event);
  }

  private buildFullResultCacheKey(keyword: string, filter: SearchFilterConfig): string {
    const selectedMangaSources: string[] = filter.selectedMangaSources.slice().sort();
    const selectedNovelSources: string[] = filter.selectedNovelSources.slice().sort();
    const parts: string[] = [];
    parts.push(keyword.trim().toLowerCase());
    parts.push(filter.contentType);
    parts.push(filter.sourceType);
    parts.push(selectedMangaSources.join(','));
    parts.push(selectedNovelSources.join(','));
    parts.push(filter.enableSuwayomi ? 'suwayomi_on' : 'suwayomi_off');
    parts.push(`${filter.maxConcurrent}`);
    parts.push(`${filter.perSourceTimeoutMs || DEFAULT_NETWORK_TIMEOUT_MS}`);
    parts.push(`${filter.globalTimeoutMs || DEFAULT_GLOBAL_TIMEOUT_MS}`);
    parts.push(`${filter.localResultLimit || DEFAULT_LOCAL_RESULT_LIMIT}`);
    parts.push(`${filter.onlineResultLimitPerSource || DEFAULT_ONLINE_RESULT_LIMIT_PER_SOURCE}`);
    parts.push(filter.enableRuntimeCache === true ? 'runtime_cache_on' : 'runtime_cache_off');
    return parts.join('|');
  }

  private trimFullResultCache(): void {
    if (this.fullResultCache.size <= this.FULL_RESULT_CACHE_LIMIT) {
      return;
    }

    const entries: GlobalSearchFullResultCacheEntry[] = Array.from(this.fullResultCache.values());
    entries.sort((left: GlobalSearchFullResultCacheEntry, right: GlobalSearchFullResultCacheEntry): number => {
      return left.createTime - right.createTime;
    });
    while (entries.length > this.FULL_RESULT_CACHE_LIMIT) {
      const entry: GlobalSearchFullResultCacheEntry | undefined = entries.shift();
      if (entry) {
        this.fullResultCache.delete(entry.cacheKey);
      }
    }
  }

  private limitItems(items: UnifiedSearchItem[], limit: number): UnifiedSearchItem[] {
    if (limit <= 0 || items.length <= limit) {
      return items;
    }
    return items.slice(0, limit);
  }

  private countItems(groups: SearchSourceGroup[]): number {
    let total: number = 0;
    for (const group of groups) {
      total += group.items.length;
    }
    return total;
  }

  private finishRemainingGroupsAsTimeout(groups: SearchSourceGroup[], metrics: GlobalSearchMetrics): void {
    for (const group of groups) {
      if (group.isSearching) {
        group.isSearching = false;
        group.hasError = true;
        group.errorMessage = '搜索超时';
        metrics.timeoutGroups++;
      }
    }
  }

  private emitSnapshot(
    onProgress: SearchProgressCallback | undefined,
    completed: number,
    total: number,
    groupName: string,
    groups: SearchSourceGroup[],
    forceCompleted: boolean
  ): void {
    if (!onProgress) {
      return;
    }
    const snapshot: SearchSourceGroup[] = this.cloneSearchGroupsForProgress(groups, forceCompleted);
    onProgress(completed, total, groupName, snapshot);
  }

  private emitGroupPatch(
    sessionId: string,
    group: SearchSourceGroup,
    patchType: GlobalSearchPatchType,
    metrics: GlobalSearchMetrics,
    onPatch?: GlobalSearchPatchCallback
  ): void {
    const patch: GlobalSearchProgressPatch = {
      sessionId: sessionId,
      patchType: patchType,
      completedGroups: metrics.completedGroups,
      totalGroups: metrics.totalGroups,
      groupId: group.groupId,
      groupName: group.groupName,
      itemCount: group.items.length,
      errorMessage: group.errorMessage
    };
    this.emitPatch(onPatch, patch, metrics);
  }

  private emitPatch(
    onPatch: GlobalSearchPatchCallback | undefined,
    patch: GlobalSearchProgressPatch,
    metrics: GlobalSearchMetrics
  ): void {
    if (!onPatch) {
      return;
    }
    metrics.uiPatchCount++;
    onPatch(patch);
  }

  private cloneSearchGroupsForProgress(groups: SearchSourceGroup[], forceCompleted: boolean): SearchSourceGroup[] {
    const snapshot: SearchSourceGroup[] = [];
    for (const group of groups) {
      const cloned: SearchSourceGroup = {
        groupId: group.groupId,
        groupName: group.groupName,
        contentType: group.contentType,
        sourceType: group.sourceType,
        onlineSourceType: group.onlineSourceType,
        usesWebViewEngine: group.usesWebViewEngine,
        items: this.cloneSearchItems(group.items),
        isSearching: forceCompleted ? false : group.isSearching,
        hasError: group.hasError,
        errorMessage: group.errorMessage
      };
      snapshot.push(cloned);
    }
    return snapshot;
  }

  private cloneSearchItems(items: UnifiedSearchItem[]): UnifiedSearchItem[] {
    const clonedItems: UnifiedSearchItem[] = [];
    for (const item of items) {
      const clonedItem: UnifiedSearchItem = {
        id: item.id,
        title: item.title,
        author: item.author,
        coverUrl: item.coverUrl,
        description: item.description,
        contentType: item.contentType,
        sourceType: item.sourceType,
        onlineSourceType: item.onlineSourceType,
        sourceId: item.sourceId,
        sourceName: item.sourceName,
        sourcePkg: item.sourcePkg,
        rawManga: item.rawManga,
        rawEbook: item.rawEbook,
        rawNovelBook: item.rawNovelBook,
        rawNovelSearch: item.rawNovelSearch,
        rawOnlineComic: item.rawOnlineComic
      };
      clonedItems.push(clonedItem);
    }
    return clonedItems;
  }

  private logMetricsIfEnabled(metrics: GlobalSearchMetrics): void {
    if (!this.settingsManager.getGlobalSearchDebugMetricsEnabled()) {
      return;
    }
    logger.info(
      TAG,
      `globalSearch session=${metrics.sessionId}, keyword="${metrics.keyword}", duration=${metrics.getDurationMs()}ms, groups=${metrics.totalGroups}, completed=${metrics.completedGroups}, timeouts=${metrics.timeoutGroups}, cancelled=${metrics.cancelledGroups}, failed=${metrics.failedGroups}, results=${metrics.resultCount}, patches=${metrics.uiPatchCount}`
    );
  }

  /**
   * 执行全局搜索
   * @param keyword 搜索关键词
   * @param filter 筛选配置
   * @param onProgress 进度回调
   */
  private async searchAllLegacy(
    keyword: string,
    filter: SearchFilterConfig,
    onProgress?: SearchProgressCallback
  ): Promise<SearchSourceGroup[]> {
    const groups: SearchSourceGroup[] = [];
    const searchTasks: Array<() => Promise<void>> = [];
    
    // 根据筛选配置构建搜索任务
    
    // 1. 本地搜索
    if (filter.sourceType === SearchSourceType.ALL || filter.sourceType === SearchSourceType.LOCAL) {
      // 本地漫画
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.MANGA) {
        const group: SearchSourceGroup = {
          groupId: 'local-manga',
          groupName: '本地漫画',
          contentType: SearchContentType.MANGA,
          sourceType: SearchSourceType.LOCAL,
          items: [],
          isSearching: true,
          hasError: false
        };
        groups.push(group);
        searchTasks.push(async () => {
          try {
            group.items = await this.searchLocalManga(keyword);
            group.isSearching = false;
          } catch (error) {
            group.isSearching = false;
            group.hasError = true;
            group.errorMessage = String(error);
          }
        });
      }
      
      // 本地电子书
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.EBOOK) {
        const group: SearchSourceGroup = {
          groupId: 'local-ebook',
          groupName: '本地电子书',
          contentType: SearchContentType.EBOOK,
          sourceType: SearchSourceType.LOCAL,
          items: [],
          isSearching: true,
          hasError: false
        };
        groups.push(group);
        searchTasks.push(async () => {
          try {
            group.items = await this.searchLocalEbooks(keyword);
            group.isSearching = false;
          } catch (error) {
            group.isSearching = false;
            group.hasError = true;
            group.errorMessage = String(error);
          }
        });
      }
      
      // 本地小说
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.NOVEL) {
        const group: SearchSourceGroup = {
          groupId: 'local-novel',
          groupName: '本地小说',
          contentType: SearchContentType.NOVEL,
          sourceType: SearchSourceType.LOCAL,
          items: [],
          isSearching: true,
          hasError: false
        };
        groups.push(group);
        searchTasks.push(async () => {
          try {
            group.items = await this.searchLocalNovels(keyword);
            group.isSearching = false;
          } catch (error) {
            group.isSearching = false;
            group.hasError = true;
            group.errorMessage = String(error);
          }
        });
      }
    }
    
    // 2. 在线搜索
    if (filter.sourceType === SearchSourceType.ALL || filter.sourceType === SearchSourceType.ONLINE) {
      // 在线漫画图源
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.MANGA) {
        for (const sourceId of filter.selectedMangaSources) {
          const numSourceId = parseInt(sourceId);
          if (isNaN(numSourceId)) continue;
          
          const sources = await this.sourceManager.getAllSources();
          const source = sources.find(s => s.id === numSourceId);
          const sourceName = source?.name || `图源${sourceId}`;
          const isWebViewSource = await this.webViewSourceManager.isWebViewSource(numSourceId);
          
          const group: SearchSourceGroup = {
            groupId: `online-manga-${sourceId}`,
            groupName: sourceName,
            contentType: SearchContentType.MANGA,
            sourceType: SearchSourceType.ONLINE,
            onlineSourceType: OnlineSourceType.MANGA_SOURCE,
            usesWebViewEngine: isWebViewSource,
            items: [],
            isSearching: true,
            hasError: false
          };
          groups.push(group);
          searchTasks.push(async () => {
            try {
              group.items = await this.searchOnlineManga(numSourceId, keyword, 1);
              group.isSearching = false;
            } catch (error) {
              group.isSearching = false;
              group.hasError = true;
              group.errorMessage = String(error);
            }
          });
        }
        
        // Suwayomi
        if (filter.enableSuwayomi && this.isSuwayomiConfigured()) {
          const group: SearchSourceGroup = {
            groupId: 'suwayomi-library',
            groupName: 'Suwayomi',
            contentType: SearchContentType.MANGA,
            sourceType: SearchSourceType.ONLINE,
            onlineSourceType: OnlineSourceType.SUWAYOMI,
            items: [],
            isSearching: true,
            hasError: false
          };
          groups.push(group);
          searchTasks.push(async () => {
            try {
              group.items = await this.searchSuwayomi(keyword);
              group.isSearching = false;
            } catch (error) {
              group.isSearching = false;
              group.hasError = true;
              group.errorMessage = String(error);
            }
          });
        }
      }
      
      // 在线小说书源
      if (filter.contentType === SearchContentType.ALL || filter.contentType === SearchContentType.NOVEL) {
        for (const sourceId of filter.selectedNovelSources) {
          const sourceObj = this.novelSourceManager.getSource(sourceId);
          const sourceName = sourceObj?.bookSourceName || sourceId;
          
          const group: SearchSourceGroup = {
            groupId: `online-novel-${sourceId}`,
            groupName: sourceName,
            contentType: SearchContentType.NOVEL,
            sourceType: SearchSourceType.ONLINE,
            onlineSourceType: OnlineSourceType.NOVEL_SOURCE,
            items: [],
            isSearching: true,
            hasError: false
          };
          groups.push(group);
          searchTasks.push(async () => {
            try {
              group.items = await this.searchOnlineNovel(sourceId, keyword);
              group.isSearching = false;
            } catch (error) {
              group.isSearching = false;
              group.hasError = true;
              group.errorMessage = String(error);
            }
          });
        }
      }
    }
    
    // 3. 执行搜索任务
    // 【关键重构】将图源搜索和书源搜索完全分离，避免资源竞争
    const totalGroups = groups.length;
    let completedGroups = 0;
    
    logger.info(TAG, `开始全局搜索: keyword="${keyword}", 共${totalGroups}个分组`);
    
    // 【关键】立即触发一次进度回调，让 UI 显示所有正在搜索的分组
    if (onProgress) {
      onProgress(0, totalGroups, '', this.createProgressSnapshot(groups));
    }
    
    // 根据 group 类型对任务进行分类
    const tasksByType = this.classifyTasksByGroup(groups, searchTasks);
    
    // 创建进度更新函数
    const updateProgress = () => {
      completedGroups++;
      if (onProgress) {
        let currentGroupName = '';
        for (const group of groups) {
          if (!group.isSearching) {
            currentGroupName = group.groupName;
          }
        }
        onProgress(completedGroups, totalGroups, currentGroupName, this.createProgressSnapshot(groups));
      }
    };
    
    // 并行执行三类任务（各类内部串行/分批执行）
    const batchSize = filter.maxConcurrent || 3;
    
    // 滑动窗口任务调度机制（平滑处理并发，避免峰值阻塞主线程）
    const executeTasksWithSlidingWindow = async (tasks: Array<() => Promise<void>>, maxConcurrent: number): Promise<void> => {
      if (tasks.length === 0) return;
      const executing: Promise<void>[] = [];
      for (const task of tasks) {
        // 主动出让执行权，让 ArkUI 能够有时间片进行渲染和响应滑动
        await new Promise<void>(resolve => setTimeout(resolve, 10));
        
        const p = task().then(() => {
          updateProgress();
          // 执行完毕后从执行队列中移除自己
          executing.splice(executing.indexOf(p), 1);
        });
        executing.push(p);
        
        // 如果当前并发数达到上限，等待任意一个任务完成
        if (executing.length >= maxConcurrent) {
          await Promise.race(executing);
        }
      }
      // 等待所有剩余任务完成
      await Promise.all(executing);
    };

    // 【核心优化】将漫画图源和小说书源这两种依赖 HTTP 请求且有较重 CPU 解析的工作合并，共享并发上限。
    // 避免因为原来分开 Promise.all 导致并发数翻倍放大，引起 APP 瞬间卡死闪退。
    const networkTasks = [...tasksByType.mangaHttp, ...tasksByType.novel];
    
    // 启动各组并发控制队列
    await Promise.all([
      // 本地任务快速并行
      executeTasksWithSlidingWindow(tasksByType.local, batchSize),
      // 合并后的网络解析任务，共享设定的最大并发度
      executeTasksWithSlidingWindow(networkTasks, batchSize),
      // WebView 必须严格串行，防止加载相互覆盖
      executeTasksWithSlidingWindow(tasksByType.mangaWebView, 1),
      // Suwayomi 默认配置
      executeTasksWithSlidingWindow(tasksByType.suwayomi, 1)
    ]);

    // 兜底确保所有分组都已结束，避免 UI 长时间停留在“搜索中”
    for (const group of groups) {
      group.isSearching = false;
    }

    if (onProgress) {
      onProgress(totalGroups, totalGroups, '', this.createProgressSnapshot(groups));
    }
    
    logger.info(TAG, `全局搜索完成: 共${groups.reduce((sum, g) => sum + g.items.length, 0)}条结果`);
    
    return groups;
  }
  
  /**
   * 根据分组类型对任务进行分类
   */
  private classifyTasksByGroup(
    groups: SearchSourceGroup[], 
    tasks: Array<() => Promise<void>>
  ): ClassifiedTasks {
    const result: ClassifiedTasks = {
      local: [],
      mangaHttp: [],
      mangaWebView: [],
      novel: [],
      suwayomi: []
    };
    
    // tasks 和 groups 是一一对应的（同一顺序添加）
    for (let i = 0; i < tasks.length && i < groups.length; i++) {
      const group = groups[i];
      const task = tasks[i];
      
      if (group.sourceType === SearchSourceType.LOCAL) {
        result.local.push(task);
      } else if (group.onlineSourceType === OnlineSourceType.MANGA_SOURCE) {
        if (group.usesWebViewEngine === true) {
          result.mangaWebView.push(task);
        } else {
          result.mangaHttp.push(task);
        }
      } else if (group.onlineSourceType === OnlineSourceType.NOVEL_SOURCE) {
        result.novel.push(task);
      } else if (group.onlineSourceType === OnlineSourceType.SUWAYOMI) {
        result.suwayomi.push(task);
      } else {
        // 默认放到本地任务
        result.local.push(task);
      }
    }
    
    logger.info(TAG, `任务分类: 本地=${result.local.length}, HTTP图源=${result.mangaHttp.length}, WebView图源=${result.mangaWebView.length}, 书源=${result.novel.length}, Suwayomi=${result.suwayomi.length}`);
    
    return result;
  }

  /**
   * 生成进度快照：返回新数组和新分组对象，保证 UI 能感知到状态更新
   */
  private createProgressSnapshot(groups: SearchSourceGroup[]): SearchSourceGroup[] {
    const snapshot: SearchSourceGroup[] = [];
    for (const group of groups) {
      snapshot.push({
        groupId: group.groupId,
        groupName: group.groupName,
        contentType: group.contentType,
        sourceType: group.sourceType,
        onlineSourceType: group.onlineSourceType,
        usesWebViewEngine: group.usesWebViewEngine,
        // 进度快照只需要替换分组对象，避免频繁深拷贝大结果集导致主线程抖动
        items: group.items,
        isSearching: group.isSearching,
        hasError: group.hasError,
        errorMessage: group.errorMessage
      });
    }
    return snapshot;
  }

  /**
   * 获取默认筛选配置
   */
  getDefaultFilterConfig(): SearchFilterConfig {
    return {
      contentType: SearchContentType.ALL,
      sourceType: SearchSourceType.LOCAL,
      selectedMangaSources: [],
      selectedNovelSources: [],
      enableSuwayomi: false,
      maxConcurrent: 5
    };
  }
}

// 导出便捷函数
export function getGlobalSearchService(): GlobalSearchService {
  return GlobalSearchService.getInstance();
}
