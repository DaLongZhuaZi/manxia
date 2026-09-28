// 文件路径: entry/src/main/ets/Framework/Scraper/ScraperManager.ets
/**
 * 刮削管理器
 * 提供统一的刮削接口，支持多个数据源
 */

import { logger } from '../../Utils/Logger';
import {
  ScraperSource,
  ScraperContentType,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  ScraperRequestConfig
} from './ScraperTypes';
import { BangumiScraper, BangumiSubjectType, BangumiScraperConfig } from './BangumiScraper';
import { AniListScraper, AniListMediaType, AniListScraperConfig } from './AniListScraper';
import { BookOfMoeScraper, BookOfMoeScraperConfig } from './BookOfMoeScraper';
import { GoogleBooksScraper, GoogleBooksScraperConfig } from './GoogleBooksScraper';

const TAG = 'ScraperManager';

/**
 * 刮削管理器配置
 */
export interface ScraperManagerConfig {
  bangumi?: BangumiScraperConfig;
  anilist?: AniListScraperConfig;
  bookofmoe?: BookOfMoeScraperConfig;
  googlebooks?: GoogleBooksScraperConfig;
  defaultTimeout?: number;
  enabledSources?: ScraperSource[];
}

/**
 * 多源搜索结果
 */
export interface MultiSourceSearchResult {
  success: boolean;
  results: Map<ScraperSource, ScraperSearchResult>;
  mergedResults: ScrapedMetadata[];
  errors: Map<ScraperSource, string>;
}

/**
 * 刮削管理器 - 单例模式
 */
export class ScraperManager {
  private static instance: ScraperManager | null = null;
  
  private bangumiScraper: BangumiScraper;
  private anilistScraper: AniListScraper;
  private bookofmoeScraper: BookOfMoeScraper;
  private googleBooksScraper: GoogleBooksScraper;
  private config: ScraperManagerConfig;
  private enabledSources: Set<ScraperSource>;

  private constructor(config?: ScraperManagerConfig) {
    this.config = config || {};
    this.bangumiScraper = new BangumiScraper(this.config.bangumi);
    this.anilistScraper = new AniListScraper(this.config.anilist);
    this.bookofmoeScraper = new BookOfMoeScraper(this.config.bookofmoe);
    this.googleBooksScraper = new GoogleBooksScraper(this.config.googlebooks);
    
    // 默认启用所有源
    this.enabledSources = new Set(
      this.config.enabledSources || [
        ScraperSource.BANGUMI,
        ScraperSource.ANILIST,
        ScraperSource.BOOKOF_MOE,
        ScraperSource.GOOGLE_BOOKS
      ]
    );
    
    logger.info(TAG, `刮削管理器初始化完成，启用源: ${Array.from(this.enabledSources).join(', ')}`);
  }

  /**
   * 获取单例实例
   */
  public static getInstance(config?: ScraperManagerConfig): ScraperManager {
    if (!ScraperManager.instance) {
      ScraperManager.instance = new ScraperManager(config);
    }
    return ScraperManager.instance;
  }

  /**
   * 重置实例（用于测试或重新配置）
   */
  public static resetInstance(): void {
    ScraperManager.instance = null;
  }

  // ==================== 配置方法 ====================

  /**
   * 设置Bangumi访问令牌
   */
  public setBangumiToken(token: string): void {
    this.bangumiScraper.setAccessToken(token);
    logger.info(TAG, 'Bangumi访问令牌已设置');
  }

  /**
   * 设置AniList访问令牌
   */
  public setAniListToken(token: string): void {
    this.anilistScraper.setAccessToken(token);
    logger.info(TAG, 'AniList访问令牌已设置');
  }

  /**
   * 设置Google Books API Key
   */
  public setGoogleBooksApiKey(apiKey: string): void {
    this.googleBooksScraper.setApiKey(apiKey);
    logger.info(TAG, 'Google Books API Key已设置');
  }

  /**
   * 启用/禁用刮削源
   */
  public setSourceEnabled(source: ScraperSource, enabled: boolean): void {
    if (enabled) {
      this.enabledSources.add(source);
    } else {
      this.enabledSources.delete(source);
    }
    logger.info(TAG, `刮削源 ${source} ${enabled ? '已启用' : '已禁用'}`);
  }

  /**
   * 检查刮削源是否启用
   */
  public isSourceEnabled(source: ScraperSource): boolean {
    return this.enabledSources.has(source);
  }

  /**
   * 获取所有启用的刮削源
   */
  public getEnabledSources(): ScraperSource[] {
    return Array.from(this.enabledSources);
  }

  // ==================== 单源搜索方法 ====================

  /**
   * 使用指定源搜索
   */
  public async searchWithSource(
    source: ScraperSource,
    keyword: string,
    contentType?: ScraperContentType,
    limit: number = 25
  ): Promise<ScraperSearchResult> {
    logger.info(TAG, `单源搜索: source=${source}, keyword=${keyword}, type=${contentType}`);

    switch (source) {
      case ScraperSource.BANGUMI:
        return this.searchBangumi(keyword, contentType, limit);
      case ScraperSource.ANILIST:
        return this.searchAniList(keyword, contentType, limit);
      case ScraperSource.BOOKOF_MOE:
        return this.bookofmoeScraper.search(keyword);
      case ScraperSource.GOOGLE_BOOKS:
        return this.googleBooksScraper.search(keyword, limit);
      default:
        return {
          success: false,
          source: source,
          results: [],
          errorMessage: `不支持的刮削源: ${source}`
        };
    }
  }

  /**
   * 搜索Bangumi
   */
  private async searchBangumi(
    keyword: string,
    contentType?: ScraperContentType,
    limit: number = 25
  ): Promise<ScraperSearchResult> {
    let bangumiType: BangumiSubjectType | undefined;
    
    switch (contentType) {
      case ScraperContentType.MANGA:
      case ScraperContentType.BOOK:
        bangumiType = BangumiSubjectType.BOOK;
        break;
      case ScraperContentType.ANIME:
        bangumiType = BangumiSubjectType.ANIME;
        break;
      case ScraperContentType.GAME:
        bangumiType = BangumiSubjectType.GAME;
        break;
    }
    
    return this.bangumiScraper.search(keyword, bangumiType, limit);
  }

  /**
   * 搜索AniList
   */
  private async searchAniList(
    keyword: string,
    contentType?: ScraperContentType,
    limit: number = 25
  ): Promise<ScraperSearchResult> {
    let anilistType = AniListMediaType.MANGA;
    
    if (contentType === ScraperContentType.ANIME) {
      anilistType = AniListMediaType.ANIME;
    }
    
    return this.anilistScraper.search(keyword, anilistType, 1, limit);
  }

  // ==================== 多源搜索方法 ====================

  /**
   * 多源并行搜索
   * @param keyword 搜索关键词
   * @param contentType 内容类型
   * @param sources 指定源列表（可选，默认使用所有启用的源）
   */
  public async searchMultipleSources(
    keyword: string,
    contentType?: ScraperContentType,
    sources?: ScraperSource[]
  ): Promise<MultiSourceSearchResult> {
    const targetSources = sources || Array.from(this.enabledSources);
    logger.info(TAG, `多源搜索: keyword=${keyword}, sources=${targetSources.join(',')}`);

    const results = new Map<ScraperSource, ScraperSearchResult>();
    const errors = new Map<ScraperSource, string>();
    const allResults: ScrapedMetadata[] = [];

    // 并行执行所有搜索
    const searchPromises = targetSources.map(async (source) => {
      try {
        const result = await this.searchWithSource(source, keyword, contentType);
        results.set(source, result);
        
        if (result.success) {
          allResults.push(...result.results);
        } else if (result.errorMessage) {
          errors.set(source, result.errorMessage);
        }
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        errors.set(source, errorMsg);
        results.set(source, {
          success: false,
          source: source,
          results: [],
          errorMessage: errorMsg
        });
      }
    });

    await Promise.all(searchPromises);

    // 合并和去重结果
    const mergedResults = this.mergeAndDeduplicateResults(allResults);

    logger.info(TAG, `多源搜索完成: 总计 ${mergedResults.length} 条结果，${errors.size} 个错误`);

    return {
      success: errors.size < targetSources.length, // 至少有一个源成功
      results: results,
      mergedResults: mergedResults,
      errors: errors
    };
  }

  /**
   * 搜索漫画（多源）
   */
  public async searchManga(keyword: string, sources?: ScraperSource[]): Promise<MultiSourceSearchResult> {
    return this.searchMultipleSources(keyword, ScraperContentType.MANGA, sources);
  }

  /**
   * 搜索动画（多源）
   */
  public async searchAnime(keyword: string, sources?: ScraperSource[]): Promise<MultiSourceSearchResult> {
    return this.searchMultipleSources(keyword, ScraperContentType.ANIME, sources);
  }

  /**
   * 搜索书籍（多源）
   */
  public async searchBook(keyword: string, sources?: ScraperSource[]): Promise<MultiSourceSearchResult> {
    return this.searchMultipleSources(keyword, ScraperContentType.BOOK, sources);
  }

  /**
   * 搜索电子书（使用专门的电子书刮削源）
   * 优先使用 Google Books 和 BookOf.Moe
   */
  public async searchEbook(keyword: string): Promise<MultiSourceSearchResult> {
    const ebookSources = [
      ScraperSource.GOOGLE_BOOKS,
      ScraperSource.BOOKOF_MOE
    ].filter(source => this.isSourceEnabled(source));
    
    return this.searchMultipleSources(keyword, ScraperContentType.BOOK, ebookSources);
  }

  /**
   * 按ISBN搜索电子书
   * @param isbn ISBN号（支持ISBN-10和ISBN-13）
   */
  public async searchByIsbn(isbn: string): Promise<MultiSourceSearchResult> {
    logger.info(TAG, `按ISBN搜索: ${isbn}`);
    
    const results = new Map<ScraperSource, ScraperSearchResult>();
    const errors = new Map<ScraperSource, string>();
    const allResults: ScrapedMetadata[] = [];

    // 并行搜索所有支持ISBN的源
    const searchPromises: Promise<void>[] = [];

    if (this.isSourceEnabled(ScraperSource.GOOGLE_BOOKS)) {
      searchPromises.push(
        this.googleBooksScraper.searchByIsbn(isbn).then(result => {
          results.set(ScraperSource.GOOGLE_BOOKS, result);
          if (result.success) {
            allResults.push(...result.results);
          } else if (result.errorMessage) {
            errors.set(ScraperSource.GOOGLE_BOOKS, result.errorMessage);
          }
        }).catch((error: Error) => {
          errors.set(ScraperSource.GOOGLE_BOOKS, String(error));
        })
      );
    }

    if (this.isSourceEnabled(ScraperSource.BOOKOF_MOE)) {
      searchPromises.push(
        this.bookofmoeScraper.searchByIsbn(isbn).then(result => {
          results.set(ScraperSource.BOOKOF_MOE, result);
          if (result.success) {
            allResults.push(...result.results);
          } else if (result.errorMessage) {
            errors.set(ScraperSource.BOOKOF_MOE, result.errorMessage);
          }
        }).catch((error: Error) => {
          errors.set(ScraperSource.BOOKOF_MOE, String(error));
        })
      );
    }

    await Promise.all(searchPromises);

    const mergedResults = this.mergeAndDeduplicateResults(allResults);

    logger.info(TAG, `ISBN搜索完成: 找到 ${mergedResults.length} 条结果`);

    return {
      success: mergedResults.length > 0,
      results: results,
      mergedResults: mergedResults,
      errors: errors
    };
  }

  // ==================== 详情获取方法 ====================

  /**
   * 获取条目详情
   * @param source 刮削源
   * @param externalId 外部ID
   */
  public async getDetail(source: ScraperSource, externalId: string): Promise<ScraperDetailResult> {
    logger.info(TAG, `获取详情: source=${source}, id=${externalId}`);

    switch (source) {
      case ScraperSource.BANGUMI:
        return this.bangumiScraper.getDetail(externalId);
      case ScraperSource.ANILIST:
        return this.anilistScraper.getDetail(externalId);
      case ScraperSource.BOOKOF_MOE:
        return this.bookofmoeScraper.getDetail(externalId);
      case ScraperSource.GOOGLE_BOOKS:
        return this.googleBooksScraper.getDetail(externalId);
      default:
        return {
          success: false,
          source: source,
          errorMessage: `不支持的刮削源: ${source}`
        };
    }
  }

  /**
   * 根据统一ID获取详情
   * @param unifiedId 统一ID（格式：source_externalId）
   */
  public async getDetailByUnifiedId(unifiedId: string): Promise<ScraperDetailResult> {
    const parts = unifiedId.split('_');
    if (parts.length < 2) {
      return {
        success: false,
        source: ScraperSource.BANGUMI,
        errorMessage: '无效的统一ID格式'
      };
    }

    const sourceStr = parts[0];
    const externalId = parts.slice(1).join('_');

    let source: ScraperSource;
    switch (sourceStr) {
      case 'bangumi':
        source = ScraperSource.BANGUMI;
        break;
      case 'anilist':
        source = ScraperSource.ANILIST;
        break;
      case 'bookofmoe':
        source = ScraperSource.BOOKOF_MOE;
        break;
      case 'googlebooks':
        source = ScraperSource.GOOGLE_BOOKS;
        break;
      default:
        return {
          success: false,
          source: ScraperSource.BANGUMI,
          errorMessage: `未知的刮削源: ${sourceStr}`
        };
    }

    return this.getDetail(source, externalId);
  }

  // ==================== 辅助方法 ====================

  /**
   * 合并和去重搜索结果
   */
  private mergeAndDeduplicateResults(results: ScrapedMetadata[]): ScrapedMetadata[] {
    const seen = new Map<string, ScrapedMetadata>();

    for (const item of results) {
      // 使用标题的规范化形式作为去重键
      const normalizedTitle = this.normalizeTitle(item.title);
      
      if (!seen.has(normalizedTitle)) {
        seen.set(normalizedTitle, item);
      } else {
        // 如果已存在，合并信息（优先保留更完整的数据）
        const existing = seen.get(normalizedTitle)!;
        seen.set(normalizedTitle, this.mergeMetadata(existing, item));
      }
    }

    // 按评分排序
    return Array.from(seen.values()).sort((a, b) => {
      const scoreA = a.score || 0;
      const scoreB = b.score || 0;
      return scoreB - scoreA;
    });
  }

  /**
   * 规范化标题用于去重
   */
  private normalizeTitle(title: string): string {
    return title
      .toLowerCase()
      .replace(/[\s\-_:：·・]/g, '')
      .replace(/[！!？?。.，,、]/g, '')
      .trim();
  }

  /**
   * 合并两个元数据对象
   */
  private mergeMetadata(existing: ScrapedMetadata, newItem: ScrapedMetadata): ScrapedMetadata {
    const merged: ScrapedMetadata = {
      id: existing.id,
      source: existing.source,
      externalId: existing.externalId,
      title: existing.title,
      titleNative: existing.titleNative || newItem.titleNative,
      titleRomaji: existing.titleRomaji || newItem.titleRomaji,
      titleEnglish: existing.titleEnglish || newItem.titleEnglish,
      alternativeTitles: existing.alternativeTitles || newItem.alternativeTitles,
      description: existing.description || newItem.description,
      summary: existing.summary || newItem.summary,
      coverUrl: existing.coverUrl || newItem.coverUrl,
      coverUrlLarge: existing.coverUrlLarge || newItem.coverUrlLarge,
      coverUrlMedium: existing.coverUrlMedium || newItem.coverUrlMedium,
      coverUrlSmall: existing.coverUrlSmall || newItem.coverUrlSmall,
      author: existing.author || newItem.author,
      authors: existing.authors && existing.authors.length > 0 ? existing.authors : newItem.authors,
      artist: existing.artist || newItem.artist,
      artists: existing.artists && existing.artists.length > 0 ? existing.artists : newItem.artists,
      publisher: existing.publisher || newItem.publisher,
      genres: this.mergeArrays(existing.genres, newItem.genres),
      tags: this.mergeArrays(existing.tags, newItem.tags),
      themes: existing.themes || newItem.themes,
      score: Math.max(existing.score || 0, newItem.score || 0) || undefined,
      scoreMax: existing.scoreMax || newItem.scoreMax,
      ratingCount: Math.max(existing.ratingCount || 0, newItem.ratingCount || 0) || undefined,
      rank: existing.rank || newItem.rank,
      popularity: existing.popularity || newItem.popularity,
      status: existing.status !== 'unknown' ? existing.status : newItem.status,
      releaseDate: existing.releaseDate || newItem.releaseDate,
      endDate: existing.endDate || newItem.endDate,
      volumes: existing.volumes || newItem.volumes,
      chapters: existing.chapters || newItem.chapters,
      rawData: existing.rawData
    };
    return merged;
  }

  /**
   * 合并数组并去重
   */
  private mergeArrays(arr1?: string[], arr2?: string[]): string[] | undefined {
    const result: string[] = [];
    const seen = new Set<string>();
    
    if (arr1) {
      for (const item of arr1) {
        if (!seen.has(item)) {
          seen.add(item);
          result.push(item);
        }
      }
    }
    
    if (arr2) {
      for (const item of arr2) {
        if (!seen.has(item)) {
          seen.add(item);
          result.push(item);
        }
      }
    }
    
    if (result.length === 0) return undefined;
    return result;
  }

  // ==================== 便捷方法 ====================

  /**
   * 快速搜索 - 返回最佳匹配结果
   */
  public async quickSearch(
    keyword: string,
    contentType?: ScraperContentType
  ): Promise<ScrapedMetadata | null> {
    const result = await this.searchMultipleSources(keyword, contentType);
    
    if (result.success && result.mergedResults.length > 0) {
      return result.mergedResults[0];
    }
    
    return null;
  }

  /**
   * 自动填充元数据
   * 根据标题搜索并返回最匹配的元数据
   */
  public async autoFillMetadata(
    title: string,
    contentType?: ScraperContentType,
    preferredSource?: ScraperSource
  ): Promise<ScrapedMetadata | null> {
    logger.info(TAG, `自动填充元数据: title=${title}, preferredSource=${preferredSource}`);

    // 如果指定了优先源，先尝试该源
    if (preferredSource && this.isSourceEnabled(preferredSource)) {
      const result = await this.searchWithSource(preferredSource, title, contentType, 5);
      if (result.success && result.results.length > 0) {
        return result.results[0];
      }
    }

    // 否则使用多源搜索
    return this.quickSearch(title, contentType);
  }
}

// 导出便捷函数
export function getScraperManager(config?: ScraperManagerConfig): ScraperManager {
  return ScraperManager.getInstance(config);
}
