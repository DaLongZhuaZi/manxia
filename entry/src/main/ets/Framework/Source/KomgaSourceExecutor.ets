import { logger } from '../../Utils/Logger';
import { ChapterInfo, ComicDetailInfo, ComicInfo, PageInfo } from './SourceExecutor';
import { getKomgaSource, KomgaSource } from './KomgaSource';
import {
  KomgaBrowseRequest,
  KomgaConfig,
  KomgaContentType,
  KomgaFilterOptions,
  KomgaInstanceConfig,
  KomgaPaginatedResult
} from './KomgaModels';

const TAG = 'KomgaSourceExecutor';

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

  constructor() {
    this.source = getKomgaSource();
  }

  public async initialize(forceReload: boolean = false): Promise<void> {
    await this.source.initialize(forceReload);
    const currentInstance = this.source.getCurrentInstance();
    const stillExists = this.source.getInstances().some(item => item.id === this.currentInstanceId);
    if (forceReload || this.currentInstanceId.length <= 0 || !stillExists) {
      this.currentInstanceId = currentInstance?.id || '';
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
      const matched = this.source.getInstances().find(item => item.id === this.currentInstanceId);
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
    }
    return success;
  }

  public getCurrentInstanceId(): string {
    return this.currentInstanceId;
  }

  public getServerUrl(): string {
    return this.source.getServerUrl(this.currentInstanceId);
  }

  public getImageHeaders(): Record<string, string> {
    return this.source.getImageHeaders(this.currentInstanceId);
  }

  public async getFilterOptions(forceRefresh: boolean = false): Promise<KomgaFilterOptions> {
    return this.source.getFilterOptions(this.currentInstanceId, forceRefresh);
  }

  public async browse(request: KomgaBrowseRequest): Promise<KomgaPaginatedResult<ComicInfo>> {
    try {
      const currentInstance = this.getCurrentInstance();
      const effectiveInstanceId = request.instanceId || currentInstance?.id || this.currentInstanceId;
      const effectiveRequest: KomgaBrowseRequest = {
        instanceId: effectiveInstanceId,
        contentType: request.contentType,
        browseMode: request.browseMode,
        feedType: request.feedType,
        page: request.page,
        query: request.query,
        filters: request.filters
      };
      return await this.source.browse(effectiveRequest);
    } catch (error) {
      logger.error(TAG, `浏览 Komga 内容失败: ${String(error)}`);
      return { items: [], totalCount: 0, hasMore: false };
    }
  }

  public async getDetail(itemId: string, contentType: KomgaContentType): Promise<ComicDetailInfo | null> {
    try {
      return await this.source.getMangaDetail(itemId, contentType, this.currentInstanceId);
    } catch (error) {
      logger.error(TAG, `加载 Komga 详情失败: ${String(error)}`);
      return null;
    }
  }

  public async getPages(bookId: string): Promise<PageInfo[]> {
    try {
      return await this.source.getPages(bookId, this.currentInstanceId);
    } catch (error) {
      logger.error(TAG, `加载 Komga 页面失败: ${String(error)}`);
      return [];
    }
  }

  public async getChapters(itemId: string, contentType: KomgaContentType): Promise<ChapterInfo[]> {
    const detail = await this.getDetail(itemId, contentType);
    return detail?.chapters || [];
  }
}
