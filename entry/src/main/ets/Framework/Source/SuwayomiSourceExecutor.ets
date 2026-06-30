/**
 * Suwayomi 图源执行器
 * 将 Suwayomi 图源集成到现有的图源管理系统中
 */

import { logger } from '../../Utils/Logger';
import { ComicInfo, ChapterInfo, PageInfo, ComicDetailInfo } from './SourceExecutor';
import { getSuwayomiSource, SuwayomiSource, SuwayomiSourceConfig, SuwayomiCategory, PaginatedResult, MangaSortType, SortDirection, MangaSortOption, MANGA_SORT_OPTIONS } from './SuwayomiSource';

const TAG = 'SuwayomiSourceExecutor';
const DETAIL_CACHE_TTL_MS: number = 5 * 60 * 1000;
const PAGES_CACHE_TTL_MS: number = 10 * 60 * 1000;

interface SuwayomiDetailCacheEntry {
  detail: ComicDetailInfo;
  timestamp: number;
}

interface SuwayomiPagesCacheEntry {
  pages: PageInfo[];
  timestamp: number;
}

// Suwayomi 源信息（用于选择不同的 Suwayomi 扩展源）
export interface SuwayomiExtensionSource {
  id: string;
  name: string;
  lang: string;
  iconUrl: string;
  isNsfw: boolean;
}

/**
 * Suwayomi 图源执行器类
 * 实现与 SourceExecutor 相同的接口，但使用 Suwayomi GraphQL API
 */
export class SuwayomiSourceExecutor {
  private static instance: SuwayomiSourceExecutor | null = null;
  private suwayomiSource: SuwayomiSource;
  private currentSourceId: string = ''; // 当前选择的 Suwayomi 扩展源 ID
  private sourceNsfwMap: Map<string, boolean> = new Map(); // 缓存源NSFW状态
  private detailCache: Map<string, SuwayomiDetailCacheEntry> = new Map();
  private pagesCache: Map<string, SuwayomiPagesCacheEntry> = new Map();
  private detailInFlight: Map<string, Promise<ComicDetailInfo | null>> = new Map();
  private pagesInFlight: Map<string, Promise<PageInfo[]>> = new Map();

  private constructor() {
    this.suwayomiSource = getSuwayomiSource();
  }

  public static getInstance(): SuwayomiSourceExecutor {
    if (!SuwayomiSourceExecutor.instance) {
      SuwayomiSourceExecutor.instance = new SuwayomiSourceExecutor();
    }
    return SuwayomiSourceExecutor.instance;
  }

  /**
   * 初始化
   */
  public async initialize(forceReload: boolean = false): Promise<void> {
    await this.suwayomiSource.initialize(forceReload);
    if (forceReload) {
      this.clearDataCache();
    }
    logger.info(TAG, `初始化完成: forceReload=${forceReload}`);
  }

  public clearDataCache(): void {
    this.detailCache.clear();
    this.pagesCache.clear();
    this.detailInFlight.clear();
    this.pagesInFlight.clear();
    logger.debug(TAG, '已清理 SuwayomiSourceExecutor 数据缓存');
  }

  /**
   * 检查是否已配置
   */
  public isConfigured(): boolean {
    return this.suwayomiSource.isConfigured();
  }

  /**
   * 获取配置
   */
  public getConfig(): SuwayomiSourceConfig {
    return this.suwayomiSource.getConfig();
  }

  /**
   * 获取服务器地址
   */
  public getServerUrl(): string {
    return this.suwayomiSource.getServerUrl();
  }

  /**
   * 保存配置
   */
  public async saveConfig(config: SuwayomiSourceConfig): Promise<void> {
    await this.suwayomiSource.saveConfig(config);
  }

  /**
   * 设置当前使用的 Suwayomi 扩展源
   */
  public setCurrentSource(sourceId: string): void {
    this.currentSourceId = sourceId;
    logger.debug(TAG, `设置当前源: ${sourceId}`);
  }

  /**
   * 获取当前使用的 Suwayomi 扩展源 ID
   */
  public getCurrentSourceId(): string {
    return this.currentSourceId;
  }

  /**
   * 获取所有可用的 Suwayomi 扩展源
   */
  public async getAvailableSources(): Promise<SuwayomiExtensionSource[]> {
    try {
      const sources = await this.suwayomiSource.getSources();
      // 缓存所有源的NSFW状态
      for (const s of sources) {
        this.sourceNsfwMap.set(s.id, s.isNsfw);
      }
      return sources.map((s): SuwayomiExtensionSource => {
        const result: SuwayomiExtensionSource = {
          id: s.id,
          name: s.name,
          lang: s.lang,
          iconUrl: s.iconUrl,
          isNsfw: s.isNsfw
        };
        return result;
      });
    } catch (error) {
      logger.error(TAG, `获取源列表失败: ${error}`);
      return [];
    }
  }

  /**
   * 为ComicInfo结果注入当前源的isNSFW标记
   */
  private injectNsfwFlag(results: ComicInfo[], sourceId?: string): ComicInfo[] {
    const sid = sourceId || this.currentSourceId;
    const isNsfw = sid ? (this.sourceNsfwMap.get(sid) === true) : false;
    if (isNsfw) {
      for (const item of results) {
        (item as ESObject).isNSFW = true;
      }
    }
    return results;
  }

  /**
   * 搜索漫画
   * 如果设置了当前源，则从该源搜索；否则从库中搜索
   */
  public async search(query: string): Promise<ComicInfo[]> {
    try {
      let results: ComicInfo[];
      if (this.currentSourceId) {
        results = await this.suwayomiSource.searchManga(this.currentSourceId, query);
      } else {
        results = await this.suwayomiSource.searchLibrary(query);
      }
      return this.injectNsfwFlag(results);
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
      return [];
    }
  }

  /**
   * 在库中搜索漫画
   */
  public async searchLibrary(query: string): Promise<ComicInfo[]> {
    try {
      return await this.suwayomiSource.searchLibrary(query);
    } catch (error) {
      logger.error(TAG, `库搜索失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取所有分类
   */
  public async getCategories(): Promise<SuwayomiCategory[]> {
    try {
      return await this.suwayomiSource.getCategories();
    } catch (error) {
      logger.error(TAG, `获取分类失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取库中的漫画列表（分页+排序）
   * @param categoryId 分类ID，-1表示所有
   * @param offset 偏移量
   * @param limit 每页数量
   * @param sortType 排序类型
   * @param sortDirection 排序方向
   */
  public async getLibraryPaginated(
    categoryId: number = -1,
    offset: number = 0,
    limit: number = 50,
    sortType: MangaSortType = 'TITLE',
    sortDirection: SortDirection = 'ASC'
  ): Promise<PaginatedResult<ComicInfo>> {
    try {
      return await this.suwayomiSource.getLibraryMangasPaginated(categoryId, offset, limit, sortType, sortDirection);
    } catch (error) {
      logger.error(TAG, `获取库列表失败: ${error}`);
      return { items: [], totalCount: 0, hasMore: false };
    }
  }

  /**
   * 获取可用的排序选项
   */
  public getSortOptions(): MangaSortOption[] {
    return MANGA_SORT_OPTIONS;
  }

  /**
   * 获取库中的漫画列表（不推荐用于大型库）
   * @deprecated 使用 getLibraryPaginated 代替
   */
  public async getLibrary(): Promise<ComicInfo[]> {
    try {
      return await this.suwayomiSource.getLibraryMangas();
    } catch (error) {
      logger.error(TAG, `获取库列表失败: ${error}`);
      return [];
    }
  }

  /**
   * 浏览源（热门/最新）
   */
  public async browse(type: 'POPULAR' | 'LATEST' = 'POPULAR', page: number = 1): Promise<ComicInfo[]> {
    if (!this.currentSourceId) {
      logger.warn(TAG, '未选择源，无法浏览');
      return [];
    }
    try {
      const results = await this.suwayomiSource.browseSource(this.currentSourceId, type, page);
      return this.injectNsfwFlag(results);
    } catch (error) {
      logger.error(TAG, `浏览失败: ${error}`);
      return [];
    }
  }

  /**
   * 获取漫画详情
   */
  public async getDetail(mangaId: string): Promise<ComicDetailInfo | null> {
    try {
      const cached = this.detailCache.get(mangaId);
      if (cached && this.isCacheValid(cached.timestamp, DETAIL_CACHE_TTL_MS)) {
        logger.debug(TAG, `Suwayomi 详情缓存命中: mangaId=${mangaId}`);
        return cached.detail;
      }
      const inFlight = this.detailInFlight.get(mangaId);
      if (inFlight) {
        logger.debug(TAG, `Suwayomi 详情请求合并: mangaId=${mangaId}`);
        return await inFlight;
      }
      const detailPromise = this.suwayomiSource.getMangaDetail(mangaId);
      this.detailInFlight.set(mangaId, detailPromise);
      const detail = await detailPromise;
      if (detail !== null) {
        this.detailCache.set(mangaId, {
          detail: detail,
          timestamp: Date.now()
        });
      }
      this.detailInFlight.delete(mangaId);
      return detail;
    } catch (error) {
      this.detailInFlight.delete(mangaId);
      logger.error(TAG, `获取详情失败: ${error}`);
      return null;
    }
  }

  /**
   * 获取章节页面
   */
  public async getPages(chapterId: string): Promise<PageInfo[]> {
    try {
      const cached = this.pagesCache.get(chapterId);
      if (cached && this.isCacheValid(cached.timestamp, PAGES_CACHE_TTL_MS)) {
        logger.debug(TAG, `Suwayomi 页面缓存命中: chapterId=${chapterId}, count=${cached.pages.length}`);
        return cached.pages.concat();
      }
      const inFlight = this.pagesInFlight.get(chapterId);
      if (inFlight) {
        logger.debug(TAG, `Suwayomi 页面请求合并: chapterId=${chapterId}`);
        const pages = await inFlight;
        return pages.concat();
      }
      const pagesPromise = this.suwayomiSource.getChapterPages(chapterId);
      this.pagesInFlight.set(chapterId, pagesPromise);
      const pages = await pagesPromise;
      this.pagesCache.set(chapterId, {
        pages: pages.concat(),
        timestamp: Date.now()
      });
      this.pagesInFlight.delete(chapterId);
      return pages;
    } catch (error) {
      this.pagesInFlight.delete(chapterId);
      logger.error(TAG, `获取页面失败: ${error}`);
      return [];
    }
  }

  public warmPages(chapterId: string): void {
    void this.getPages(chapterId).catch((error: Error) => {
      logger.debug(TAG, `Suwayomi 页面预热失败: chapterId=${chapterId}, error=${error.message}`);
    });
  }

  /**
   * 标记章节为已读
   */
  public async markRead(chapterId: string, isRead: boolean = true): Promise<boolean> {
    try {
      return await this.suwayomiSource.markChapterRead(chapterId, isRead);
    } catch (error) {
      logger.error(TAG, `标记已读失败: ${error}`);
      return false;
    }
  }

  /**
   * 更新章节阅读进度（保存当前阅读页码）
   */
  public async updateReadingProgress(chapterId: string, lastPageRead: number): Promise<boolean> {
    try {
      return await this.suwayomiSource.updateReadingProgress(chapterId, lastPageRead);
    } catch (error) {
      logger.error(TAG, `更新阅读进度失败: ${error}`);
      return false;
    }
  }

  /**
   * 获取章节阅读进度
   */
  public async getChapterProgress(chapterId: string): Promise<number> {
    try {
      return await this.suwayomiSource.getChapterProgress(chapterId);
    } catch (error) {
      logger.error(TAG, `获取阅读进度失败: ${error}`);
      return 0;
    }
  }

  /**
   * 添加漫画到库
   */
  public async addToLibrary(mangaId: string): Promise<boolean> {
    try {
      return await this.suwayomiSource.addToLibrary(mangaId);
    } catch (error) {
      logger.error(TAG, `添加到库失败: ${error}`);
      return false;
    }
  }

  /**
   * 从库中移除漫画
   */
  public async removeFromLibrary(mangaId: string): Promise<boolean> {
    try {
      return await this.suwayomiSource.removeFromLibrary(mangaId);
    } catch (error) {
      logger.error(TAG, `从库移除失败: ${error}`);
      return false;
    }
  }

  /**
   * 获取图片请求头
   */
  public getImageHeaders(): Record<string, string> {
    return this.suwayomiSource.getImageHeaders();
  }

  private isCacheValid(timestamp: number, ttlMs: number): boolean {
    return timestamp > 0 && (Date.now() - timestamp) < ttlMs;
  }
}

/**
 * 获取 Suwayomi 图源执行器实例
 */
export function getSuwayomiSourceExecutor(): SuwayomiSourceExecutor {
  return SuwayomiSourceExecutor.getInstance();
}
