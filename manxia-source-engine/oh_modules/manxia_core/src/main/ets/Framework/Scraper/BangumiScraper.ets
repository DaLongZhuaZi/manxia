import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Scraper/BangumiScraper.ets
/**
 * Bangumi 番组计划刮削器
 * API文档: https://bangumi.github.io/api/
 */

import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  ScraperSource,
  ScraperContentType,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  BangumiSubject,
  BangumiSearchResult,
  BangumiInfoboxItem,
  BangumiInfoboxValue
} from './ScraperTypes';

const TAG = 'BangumiScraper';

/**
 * Bangumi 搜索请求体
 */
interface BangumiSearchRequestBody {
  keyword: string;
  limit: number;
  offset: number;
  filter?: BangumiSearchFilter;
}

interface BangumiSearchFilter {
  type: number[];
}

/**
 * Bangumi 条目类型
 * 1 = 书籍, 2 = 动画, 3 = 音乐, 4 = 游戏, 6 = 三次元
 */
export enum BangumiSubjectType {
  BOOK = 1,
  ANIME = 2,
  MUSIC = 3,
  GAME = 4,
  REAL = 6
}

/**
 * Bangumi 刮削器配置
 */
export interface BangumiScraperConfig {
  accessToken?: string;
  userAgent?: string;
  timeout?: number;
}

/**
 * Bangumi 刮削器
 */
export class BangumiScraper {
  private static readonly BASE_URL = 'https://api.bgm.tv';
  private static readonly API_VERSION = 'v0';
  private config: BangumiScraperConfig;

  constructor(config?: BangumiScraperConfig) {
    this.config = config || {};
  }

  /**
   * 设置访问令牌
   */
  public setAccessToken(token: string): void {
    this.config.accessToken = token;
  }

  /**
   * 搜索条目
   * @param keyword 搜索关键词
   * @param type 条目类型
   * @param limit 返回数量限制
   * @param offset 偏移量
   */
  public async search(
    keyword: string,
    type?: BangumiSubjectType,
    limit: number = 25,
    offset: number = 0
  ): Promise<ScraperSearchResult> {
    try {
      logger.info(TAG, `搜索Bangumi: keyword=${keyword}, type=${type}`);

      // 使用新版 v0 API 搜索
      const url = `${BangumiScraper.BASE_URL}/${BangumiScraper.API_VERSION}/search/subjects`;
      
      const requestBody: BangumiSearchRequestBody = {
        keyword: keyword,
        limit: limit,
        offset: offset
      };
      
      if (type !== undefined) {
        const filter: BangumiSearchFilter = {
          type: [type]
        };
        requestBody.filter = filter;
      }

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: JSON.stringify(requestBody),
        connectTimeout: this.config.timeout || 15000,
        readTimeout: this.config.timeout || 15000
      });

      httpRequest.destroy();

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const data = SafeUtils.parseObj(response.result as string) as BangumiSearchResult;
      const results: ScrapedMetadata[] = data.data.map(subject => this.convertToMetadata(subject));

      logger.info(TAG, `Bangumi搜索成功: 找到 ${results.length} 条结果`);

      return {
        success: true,
        source: ScraperSource.BANGUMI,
        results: results,
        totalCount: data.total
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Bangumi搜索失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.BANGUMI,
        results: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 获取条目详情
   * @param subjectId 条目ID
   */
  public async getDetail(subjectId: number | string): Promise<ScraperDetailResult> {
    try {
      logger.info(TAG, `获取Bangumi条目详情: ${subjectId}`);

      const url = `${BangumiScraper.BASE_URL}/${BangumiScraper.API_VERSION}/subjects/${subjectId}`;

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(),
        connectTimeout: this.config.timeout || 15000,
        readTimeout: this.config.timeout || 15000
      });

      httpRequest.destroy();

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      const subject = SafeUtils.parseObj(response.result as string) as BangumiSubject;
      const metadata = this.convertToMetadata(subject);

      logger.info(TAG, `Bangumi详情获取成功: ${metadata.title}`);

      return {
        success: true,
        source: ScraperSource.BANGUMI,
        data: metadata
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Bangumi详情获取失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.BANGUMI,
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 按类型搜索漫画
   */
  public async searchManga(keyword: string, limit: number = 25): Promise<ScraperSearchResult> {
    return this.search(keyword, BangumiSubjectType.BOOK, limit);
  }

  /**
   * 按类型搜索动画
   */
  public async searchAnime(keyword: string, limit: number = 25): Promise<ScraperSearchResult> {
    return this.search(keyword, BangumiSubjectType.ANIME, limit);
  }

  /**
   * 按类型搜索游戏
   */
  public async searchGame(keyword: string, limit: number = 25): Promise<ScraperSearchResult> {
    return this.search(keyword, BangumiSubjectType.GAME, limit);
  }

  /**
   * 构建请求头
   */
  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': this.config.userAgent || 'Manxia/1.0 (https://github.com/manxia)'
    };

    if (this.config.accessToken) {
      headers['Authorization'] = `Bearer ${this.config.accessToken}`;
    }

    return headers;
  }

  /**
   * 将Bangumi条目转换为统一元数据格式
   */
  private convertToMetadata(subject: BangumiSubject): ScrapedMetadata {
    // 从infobox提取作者信息
    const authors = this.extractFromInfobox(subject.infobox, ['作者', '原作', '著者']);
    const artists = this.extractFromInfobox(subject.infobox, ['作画', '插图', '插画']);
    const publisher = this.extractFromInfobox(subject.infobox, ['出版社']);

    // 提取标签
    const tags = subject.tags?.map(t => t.name) || [];

    return {
      id: `bangumi_${subject.id}`,
      source: ScraperSource.BANGUMI,
      externalId: String(subject.id),
      title: subject.name_cn || subject.name,
      titleNative: subject.name,
      titleEnglish: subject.name_cn ? subject.name : undefined,
      description: subject.summary,
      summary: subject.summary,
      coverUrl: subject.images?.large || subject.images?.common,
      coverUrlLarge: subject.images?.large,
      coverUrlMedium: subject.images?.medium,
      coverUrlSmall: subject.images?.small,
      authors: authors.length > 0 ? authors : undefined,
      author: authors.length > 0 ? authors[0] : undefined,
      artists: artists.length > 0 ? artists : undefined,
      artist: artists.length > 0 ? artists[0] : undefined,
      publisher: publisher.length > 0 ? publisher[0] : undefined,
      tags: tags,
      genres: tags.slice(0, 5), // 取前5个作为分类
      score: subject.rating?.score,
      scoreMax: 10,
      ratingCount: subject.rating?.total,
      rank: subject.rating?.rank || subject.rank,
      releaseDate: subject.date,
      volumes: subject.volumes,
      chapters: subject.eps || subject.total_episodes,
      status: this.mapStatus(subject),
      rawData: subject as Object
    };
  }

  /**
   * 从infobox提取信息
   */
  private extractFromInfobox(infobox: BangumiInfoboxItem[] | undefined, keys: string[]): string[] {
    if (!infobox) return [];

    const results: string[] = [];
    for (const item of infobox) {
      if (keys.includes(item.key)) {
        if (typeof item.value === 'string') {
          results.push(item.value);
        } else if (Array.isArray(item.value)) {
          for (const v of item.value as BangumiInfoboxValue[]) {
            if (v.v) {
              results.push(v.v);
            }
          }
        }
      }
    }
    return results;
  }

  /**
   * 映射状态
   */
  private mapStatus(subject: BangumiSubject): string {
    // Bangumi没有明确的状态字段，根据其他信息推断
    if (subject.date) {
      const releaseDate = new Date(subject.date);
      if (releaseDate > new Date()) {
        return 'upcoming';
      }
    }
    return 'unknown';
  }
}
