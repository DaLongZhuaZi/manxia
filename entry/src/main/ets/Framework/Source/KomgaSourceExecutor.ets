import { logger } from '../../Utils/Logger';
import { ChapterInfo, ComicDetailInfo, ComicInfo, PageInfo } from './SourceExecutor';
import { getKomgaSource, KomgaSource } from './KomgaSource';
import {
  KomgaBrowseRequest,
  KomgaConfig,
  KomgaContentType,
  KomgaDetailCacheEntry,
  KomgaFilterOptions,
  KomgaInstanceConfig,
  KomgaPaginatedResult,
  KomgaPagesCacheEntry
} from './KomgaModels';

const TAG = 'KomgaSourceExecutor';
const DETAIL_CACHE_TTL_MS: number = 5 * 60 * 1000;
const PAGES_CACHE_TTL_MS: number = 10 * 60 * 1000;

let komgaSourceExecutorInstance: KomgaSourceExecutor | null = null;

export function getKomgaSourceExecutor(): KomgaSourceExecutor {
  if (!komgaSourceExecutorInstance) {
    komgaSourceExecutorInstance = new KomgaSourceExecutor();
  }
  return komgaSourceExecutorInstance;
}

export class KomgaSourceExecutor {
  private source: KomgaSource;
  private currentInstanceId: string = '';
  private detailCache: Map<string, KomgaDetailCacheEntry> = new Map();
  private pagesCache: Map<string, KomgaPagesCacheEntry> = new Map();

  constructor() {
    this.source = getKomgaSource();
  }

  public async initialize(forceReload: boolean = false): Promise<void> {
    logger.info(TAG, `初始化 KomgaSourceExecutor: forceReload=${forceReload}, currentInstance=${this.currentInstanceId || '-'}`);
    await this.source.initialize(forceReload);
    const currentInstance = this.source.getCurrentInstance();
    const stillExists = this.source.getInstances().some((item: KomgaInstanceConfig) => item.id === this.currentInstanceId);
    if (forceReload || this.currentInstanceId.length <= 0 || !stillExists) {
      this.currentInstanceId = currentInstance?.id || '';
    }
    if (forceReload) {
      this.clearDataCache();
    }
    logger.info(TAG, `KomgaSourceExecutor 初始化完成: configured=${this.isConfigured()}, instances=${this.getInstances().length}, currentInstance=${this.currentInstanceId || '-'}`);
  }

  public clearDataCache(instanceId?: string): void {
    if (instanceId !== undefined && instanceId.length > 0) {
      this.removeCacheByInstance(this.detailCache, instanceId);
      this.removeCacheByInstance(this.pagesCache, instanceId);
      logger.debug(TAG, `已清理 KomgaSourceExecutor 指定实例缓存: instanceId=${instanceId}`);
      return;
    }
    this.detailCache.clear();
    this.pagesCache.clear();
    logger.debug(TAG, '已清理 KomgaSourceExecutor 全部缓存');
  }

  public isConfigured(): boolean {
    return this.source.isConfigured();
  }

  public getConfig(): KomgaConfig {
    return this.source.getConfig();
  }

  public getInstances(): KomgaInstanceConfig[] {
    return this.source.getInstances();
  }

  public getCurrentInstance(): KomgaInstanceConfig | null {
    if (this.currentInstanceId.length > 0) {
      const matched = this.source.getInstances().find((item: KomgaInstanceConfig) => item.id === this.currentInstanceId);
      if (matched) {
        return matched;
      }
    }
    return this.source.getCurrentInstance();
  }

  public async setCurrentInstance(instanceId: string): Promise<boolean> {
    const success = await this.source.setCurrentInstance(instanceId);
    if (success) {
      this.currentInstanceId = instanceId;
      logger.info(TAG, `KomgaSourceExecutor 已切换实例: instanceId=${instanceId}`);
    } else {
      logger.warn(TAG, `KomgaSourceExecutor 切换实例失败: instanceId=${instanceId}`);
    }
    return success;
  }

  public getCurrentInstanceId(): string {
    return this.currentInstanceId;
  }

  public getServerUrl(instanceId?: string): string {
    return this.source.getServerUrl(this.getEffectiveInstanceId(instanceId));
  }

  public getImageHeaders(instanceId?: string): Record<string, string> {
    return this.source.getImageHeaders(this.getEffectiveInstanceId(instanceId));
  }

  public async getFilterOptions(forceRefresh: boolean = false): Promise<KomgaFilterOptions> {
    return this.source.getFilterOptions(this.currentInstanceId, forceRefresh);
  }

  public async browse(request: KomgaBrowseRequest): Promise<KomgaPaginatedResult<ComicInfo>> {
    try {
      const currentInstance = this.getCurrentInstance();
      const effectiveInstanceId = request.instanceId || currentInstance?.id || this.currentInstanceId;
      logger.info(TAG, `KomgaSourceExecutor 浏览请求: instance=${effectiveInstanceId || '-'}, mode=${request.browseMode}, type=${request.contentType}, feed=${request.feedType}, page=${request.page}, query="${request.query}"`);
      const effectiveRequest: KomgaBrowseRequest = {
        instanceId: effectiveInstanceId,
        contentType: request.contentType,
        browseMode: request.browseMode,
        feedType: request.feedType,
        page: request.page,
        query: request.query,
        filters: request.filters
      };
      const result = await this.source.browse(effectiveRequest);
      logger.info(TAG, `KomgaSourceExecutor 浏览完成: instance=${effectiveInstanceId || '-'}, received=${result.items.length}, total=${result.totalCount}, hasMore=${result.hasMore}`);
      return result;
    } catch (error) {
      logger.error(TAG, `浏览 Komga 内容失败: ${String(error)}`);
      return { items: [], totalCount: 0, hasMore: false };
    }
  }

  public async getDetail(
    itemId: string,
    contentType: KomgaContentType,
    instanceId?: string,
    forceRefresh: boolean = false
  ): Promise<ComicDetailInfo | null> {
    try {
      const effectiveInstanceId = this.getEffectiveInstanceId(instanceId);
      const cacheKey = this.buildDetailCacheKey(itemId, contentType, effectiveInstanceId);
      const cached = this.detailCache.get(cacheKey);
      if (!forceRefresh && cached && this.isCacheValid(cached.timestamp, DETAIL_CACHE_TTL_MS)) {
        logger.debug(TAG, `KomgaSourceExecutor 详情缓存命中: cacheKey=${cacheKey}`);
        return cached.detail;
      }

      logger.info(TAG, `KomgaSourceExecutor 加载详情: cacheKey=${cacheKey}, forceRefresh=${forceRefresh}`);
      const detail = await this.source.getMangaDetail(itemId, contentType, effectiveInstanceId);
      if (detail !== null) {
        this.detailCache.set(cacheKey, {
          detail: detail,
          timestamp: Date.now()
        });
        logger.info(TAG, `KomgaSourceExecutor 详情已缓存: cacheKey=${cacheKey}, chapters=${detail.chapters ? detail.chapters.length : 0}`);
      } else {
        logger.warn(TAG, `KomgaSourceExecutor 详情为空: cacheKey=${cacheKey}`);
      }
      return detail;
    } catch (error) {
      logger.error(TAG, `加载 Komga 详情失败: ${String(error)}`);
      return null;
    }
  }

  public async getPages(bookId: string, instanceId?: string, forceRefresh: boolean = false): Promise<PageInfo[]> {
    try {
      const effectiveInstanceId = this.getEffectiveInstanceId(instanceId);
      const cacheKey = this.buildPagesCacheKey(bookId, effectiveInstanceId);
      const cached = this.pagesCache.get(cacheKey);
      if (!forceRefresh && cached && this.isCacheValid(cached.timestamp, PAGES_CACHE_TTL_MS)) {
        logger.debug(TAG, `KomgaSourceExecutor 页面缓存命中: cacheKey=${cacheKey}, count=${cached.pages.length}`);
        return cached.pages.concat();
      }

      logger.info(TAG, `KomgaSourceExecutor 加载页面: cacheKey=${cacheKey}, forceRefresh=${forceRefresh}`);
      const pages = await this.source.getPages(bookId, effectiveInstanceId);
      this.pagesCache.set(cacheKey, {
        pages: pages.concat(),
        timestamp: Date.now()
      });
      logger.info(TAG, `KomgaSourceExecutor 页面缓存已更新: cacheKey=${cacheKey}, count=${pages.length}`);
      return pages;
    } catch (error) {
      logger.error(TAG, `加载 Komga 页面失败: ${String(error)}`);
      return [];
    }
  }

  public async getChapters(
    itemId: string,
    contentType: KomgaContentType,
    instanceId?: string,
    forceRefresh: boolean = false
  ): Promise<ChapterInfo[]> {
    const detail = await this.getDetail(itemId, contentType, instanceId, forceRefresh);
    return detail?.chapters || [];
  }

  private getEffectiveInstanceId(instanceId?: string): string {
    if (instanceId !== undefined && instanceId.length > 0) {
      return instanceId;
    }
    const currentInstance = this.getCurrentInstance();
    if (currentInstance !== null && currentInstance.id.length > 0) {
      return currentInstance.id;
    }
    return this.currentInstanceId;
  }

  private buildDetailCacheKey(itemId: string, contentType: KomgaContentType, instanceId: string): string {
    return `${instanceId}_${contentType}_${itemId}`;
  }

  private buildPagesCacheKey(bookId: string, instanceId: string): string {
    return `${instanceId}_${bookId}`;
  }

  private isCacheValid(timestamp: number, ttlMs: number): boolean {
    return timestamp > 0 && (Date.now() - timestamp) < ttlMs;
  }

  private removeCacheByInstance<T>(cache: Map<string, T>, instanceId: string): void {
    const keys: string[] = Array.from(cache.keys());
    keys.forEach((key: string) => {
      if (key.startsWith(`${instanceId}_`)) {
        cache.delete(key);
      }
    });
  }
}
