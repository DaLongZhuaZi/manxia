import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { getContext } from 'manxia_theme/src/main/ets/GlobalContext';
import { preferences } from '@kit.ArkData';
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
const DETAIL_CACHE_TTL_MS: number = 7 * 24 * 60 * 60 * 1000;
const PAGES_CACHE_TTL_MS: number = 10 * 60 * 1000;
const KOMGA_DETAIL_PREF_NAME: string = 'komga_detail_cache';
const KOMGA_DETAIL_CACHE_KEY: string = 'komga_detail_cache_v1';
const KOMGA_DETAIL_CACHE_MAX_ENTRIES: number = 300;

interface KomgaPersistentDetailCacheEntry {
  key: string;
  timestamp: number;
  detail: ComicDetailInfo;
}

interface KomgaPersistentDetailCacheData {
  version: number;
  entries: KomgaPersistentDetailCacheEntry[];
}

interface KomgaPersistentDetailCachePayload {
  version?: number;
  entries?: KomgaPersistentDetailCacheEntry[];
}

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
  private detailInFlight: Map<string, Promise<ComicDetailInfo | null>> = new Map();
  private pagesInFlight: Map<string, Promise<PageInfo[]>> = new Map();
  private persistentDetailCacheLoaded: boolean = false;

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
      this.persistentDetailCacheLoaded = false;
    }
    await this.loadPersistentDetailCache();
    logger.info(TAG, `KomgaSourceExecutor 初始化完成: configured=${this.isConfigured()}, instances=${this.getInstances().length}, currentInstance=${this.currentInstanceId || '-'}`);
  }

  public clearDataCache(instanceId?: string): void {
    if (instanceId !== undefined && instanceId.length > 0) {
      this.removeCacheByInstance(this.detailCache, instanceId);
      this.removeCacheByInstance(this.pagesCache, instanceId);
      this.removeCacheByInstance(this.detailInFlight, instanceId);
      this.removeCacheByInstance(this.pagesInFlight, instanceId);
      logger.debug(TAG, `已清理 KomgaSourceExecutor 指定实例缓存: instanceId=${instanceId}`);
      return;
    }
    this.detailCache.clear();
    this.pagesCache.clear();
    this.detailInFlight.clear();
    this.pagesInFlight.clear();
    logger.debug(TAG, '已清理 KomgaSourceExecutor 全部缓存');
  }

  public async clearPersistentDetailCache(instanceId?: string): Promise<void> {
    const targetInstanceId = instanceId !== undefined ? String(instanceId || '').trim() : '';
    this.clearDataCache(targetInstanceId.length > 0 ? targetInstanceId : undefined);
    try {
      const store = await preferences.getPreferences(getContext(), KOMGA_DETAIL_PREF_NAME);
      if (targetInstanceId.length <= 0) {
        this.detailCache.clear();
        await store.delete(KOMGA_DETAIL_CACHE_KEY);
        await store.flush();
        this.persistentDetailCacheLoaded = true;
        logger.info(TAG, 'KomgaSourceExecutor 已清理全部持久详情缓存');
        return;
      }

      await this.loadPersistentDetailCache();
      this.removeCacheByInstance(this.detailCache, targetInstanceId);
      const entries: KomgaPersistentDetailCacheEntry[] = [];
      const keys: string[] = Array.from(this.detailCache.keys());
      for (let index = 0; index < keys.length; index++) {
        const key = keys[index];
        const entry = this.detailCache.get(key);
        if (entry === undefined || !this.isCacheValid(entry.timestamp, DETAIL_CACHE_TTL_MS)) {
          continue;
        }
        entries.push({
          key: key,
          timestamp: entry.timestamp,
          detail: this.cloneComicDetail(entry.detail)
        });
      }
      entries.sort((left: KomgaPersistentDetailCacheEntry, right: KomgaPersistentDetailCacheEntry) => right.timestamp - left.timestamp);
      const payload: KomgaPersistentDetailCacheData = {
        version: 1,
        entries: entries.slice(0, KOMGA_DETAIL_CACHE_MAX_ENTRIES)
      };
      await store.put(KOMGA_DETAIL_CACHE_KEY, JSON.stringify(payload));
      await store.flush();
      logger.info(TAG, `KomgaSourceExecutor 已清理指定实例持久详情缓存: instanceId=${targetInstanceId}`);
    } catch (error) {
      logger.warn(TAG, `KomgaSourceExecutor 清理持久详情缓存失败: ${String(error)}`);
    }
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
        return this.cloneComicDetail(cached.detail);
      }
      const inFlight = this.detailInFlight.get(cacheKey);
      if (!forceRefresh && inFlight) {
        logger.debug(TAG, `KomgaSourceExecutor 详情请求合并: cacheKey=${cacheKey}`);
        return await inFlight;
      }

      logger.info(TAG, `KomgaSourceExecutor 加载详情: cacheKey=${cacheKey}, forceRefresh=${forceRefresh}`);
      const detailPromise = this.source.getMangaDetail(itemId, contentType, effectiveInstanceId);
      this.detailInFlight.set(cacheKey, detailPromise);
      const detail = await detailPromise;
      if (detail !== null) {
        this.detailCache.set(cacheKey, {
          detail: detail,
          timestamp: Date.now()
        });
        await this.persistDetailCacheEntry(cacheKey, detail);
        logger.info(TAG, `KomgaSourceExecutor 详情已缓存: cacheKey=${cacheKey}, chapters=${detail.chapters ? detail.chapters.length : 0}`);
      } else {
        logger.warn(TAG, `KomgaSourceExecutor 详情为空: cacheKey=${cacheKey}`);
      }
      this.detailInFlight.delete(cacheKey);
      return detail;
    } catch (error) {
      const effectiveInstanceId = this.getEffectiveInstanceId(instanceId);
      const cacheKey = this.buildDetailCacheKey(itemId, contentType, effectiveInstanceId);
      this.detailInFlight.delete(cacheKey);
      logger.error(TAG, `加载 Komga 详情失败: ${String(error)}`);
      return null;
    }
  }

  public async getCachedDetail(
    itemId: string,
    contentType: KomgaContentType,
    instanceId?: string
  ): Promise<ComicDetailInfo | null> {
    await this.loadPersistentDetailCache();
    const effectiveInstanceId = this.getEffectiveInstanceId(instanceId);
    const cacheKey = this.buildDetailCacheKey(itemId, contentType, effectiveInstanceId);
    const cached = this.detailCache.get(cacheKey);
    if (cached === undefined || !this.isCacheValid(cached.timestamp, DETAIL_CACHE_TTL_MS)) {
      return null;
    }
    logger.debug(TAG, `KomgaSourceExecutor 详情持久缓存预取命中: cacheKey=${cacheKey}`);
    return this.cloneComicDetail(cached.detail);
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
      const inFlight = this.pagesInFlight.get(cacheKey);
      if (!forceRefresh && inFlight) {
        logger.debug(TAG, `KomgaSourceExecutor 页面请求合并: cacheKey=${cacheKey}`);
        const pages = await inFlight;
        return pages.concat();
      }

      logger.info(TAG, `KomgaSourceExecutor 加载页面: cacheKey=${cacheKey}, forceRefresh=${forceRefresh}`);
      const pagesPromise = this.source.getPages(bookId, effectiveInstanceId);
      this.pagesInFlight.set(cacheKey, pagesPromise);
      const pages = await pagesPromise;
      this.pagesCache.set(cacheKey, {
        pages: pages.concat(),
        timestamp: Date.now()
      });
      this.pagesInFlight.delete(cacheKey);
      logger.info(TAG, `KomgaSourceExecutor 页面缓存已更新: cacheKey=${cacheKey}, count=${pages.length}`);
      return pages;
    } catch (error) {
      const effectiveInstanceId = this.getEffectiveInstanceId(instanceId);
      const cacheKey = this.buildPagesCacheKey(bookId, effectiveInstanceId);
      this.pagesInFlight.delete(cacheKey);
      logger.error(TAG, `加载 Komga 页面失败: ${String(error)}`);
      return [];
    }
  }

  public warmPages(bookId: string, instanceId?: string): void {
    void this.getPages(bookId, instanceId).catch((error: Error) => {
      logger.debug(TAG, `KomgaSourceExecutor 页面预热失败: bookId=${bookId}, error=${error.message}`);
    });
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
    const signature = this.buildInstanceCacheSignature(instanceId);
    return `${instanceId}_${signature}_${contentType}_${itemId}`;
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

  private async loadPersistentDetailCache(): Promise<void> {
    if (this.persistentDetailCacheLoaded) {
      return;
    }

    try {
      const store = await preferences.getPreferences(getContext(), KOMGA_DETAIL_PREF_NAME);
      const cacheText = await store.get(KOMGA_DETAIL_CACHE_KEY, '') as string;
      if (cacheText.length <= 0) {
        this.persistentDetailCacheLoaded = true;
        return;
      }

      const parsed: KomgaPersistentDetailCachePayload = SafeUtils.parseObj<KomgaPersistentDetailCachePayload>(cacheText);
      const entries: KomgaPersistentDetailCacheEntry[] = parsed.entries !== undefined ? parsed.entries : [];
      let loadedCount = 0;
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index];
        if (entry.key.length <= 0 || !this.isCacheValid(entry.timestamp, DETAIL_CACHE_TTL_MS)) {
          continue;
        }
        this.detailCache.set(entry.key, {
          detail: this.cloneComicDetail(entry.detail),
          timestamp: entry.timestamp
        });
        loadedCount += 1;
      }
      this.persistentDetailCacheLoaded = true;
      logger.info(TAG, `KomgaSourceExecutor 持久详情缓存已加载: count=${loadedCount}`);
    } catch (error) {
      this.persistentDetailCacheLoaded = true;
      logger.warn(TAG, `KomgaSourceExecutor 加载持久详情缓存失败: ${String(error)}`);
    }
  }

  private async persistDetailCacheEntry(cacheKey: string, detail: ComicDetailInfo): Promise<void> {
    try {
      const entries: KomgaPersistentDetailCacheEntry[] = [];
      const keys: string[] = Array.from(this.detailCache.keys());
      for (let index = 0; index < keys.length; index++) {
        const key = keys[index];
        const entry = this.detailCache.get(key);
        if (entry === undefined || !this.isCacheValid(entry.timestamp, DETAIL_CACHE_TTL_MS)) {
          continue;
        }
        entries.push({
          key: key,
          timestamp: entry.timestamp,
          detail: this.cloneComicDetail(entry.detail)
        });
      }

      if (!this.hasPersistentEntry(entries, cacheKey)) {
        entries.push({
          key: cacheKey,
          timestamp: Date.now(),
          detail: this.cloneComicDetail(detail)
        });
      }

      entries.sort((left: KomgaPersistentDetailCacheEntry, right: KomgaPersistentDetailCacheEntry) => right.timestamp - left.timestamp);
      const limitedEntries: KomgaPersistentDetailCacheEntry[] = entries.slice(0, KOMGA_DETAIL_CACHE_MAX_ENTRIES);
      const payload: KomgaPersistentDetailCacheData = {
        version: 1,
        entries: limitedEntries
      };
      const store = await preferences.getPreferences(getContext(), KOMGA_DETAIL_PREF_NAME);
      await store.put(KOMGA_DETAIL_CACHE_KEY, JSON.stringify(payload));
      await store.flush();
    } catch (error) {
      logger.warn(TAG, `KomgaSourceExecutor 保存持久详情缓存失败: ${String(error)}`);
    }
  }

  private hasPersistentEntry(entries: KomgaPersistentDetailCacheEntry[], cacheKey: string): boolean {
    for (let index = 0; index < entries.length; index++) {
      if (entries[index].key === cacheKey) {
        return true;
      }
    }
    return false;
  }

  private buildInstanceCacheSignature(instanceId: string): string {
    const instances = this.getInstances();
    for (let index = 0; index < instances.length; index++) {
      if (instances[index].id === instanceId) {
        const instance = instances[index];
        const server = this.normalizeCacheText(this.getServerUrl(instance.id) || instance.serverUrl);
        const authMode = instance.authMode || 'NONE';
        const user = authMode === 'BASIC' ? this.normalizeCacheText(instance.username) : '';
        const keyHash = authMode === 'API_KEY' ? this.shortStableHash(instance.apiKey.trim()) : '';
        return this.shortStableHash(`${server}|${authMode}|${user}|${keyHash}`);
      }
    }
    return this.shortStableHash(instanceId);
  }

  private normalizeCacheText(value: string): string {
    let normalized = String(value || '').trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  private shortStableHash(value: string): string {
    if (value.length <= 0) {
      return '0';
    }

    let hash: number = 0;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(index);
      hash = hash & hash;
    }
    return Math.abs(hash).toString(36);
  }

  private cloneComicDetail(detail: ComicDetailInfo): ComicDetailInfo {
    const chapters: ChapterInfo[] = [];
    if (detail.chapters !== undefined) {
      for (let index = 0; index < detail.chapters.length; index++) {
        const chapter = detail.chapters[index];
        chapters.push({
          id: chapter.id,
          title: chapter.title,
          url: chapter.url,
          updateTime: chapter.updateTime,
          chapterNumber: chapter.chapterNumber,
          seriesTitle: chapter.seriesTitle,
          pageCount: chapter.pageCount,
          coverUrl: chapter.coverUrl,
          instanceId: chapter.instanceId
        });
      }
    }

    return {
      id: detail.id,
      title: detail.title,
      author: detail.author,
      coverUrl: detail.coverUrl,
      description: detail.description,
      status: detail.status,
      tags: detail.tags ? detail.tags.concat() : [],
      url: detail.url,
      updateTime: detail.updateTime,
      instanceId: detail.instanceId,
      chapters: chapters
    };
  }
}
