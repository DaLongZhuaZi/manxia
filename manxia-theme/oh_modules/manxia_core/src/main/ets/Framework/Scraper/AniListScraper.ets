import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Scraper/AniListScraper.ets
/**
 * AniList 刮削器
 * API文档: https://docs.anilist.co/
 * GraphQL端点: https://graphql.anilist.co
 */

import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  ScraperSource,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  AniListMedia,
  AniListResponse,
  AniListStaffEdge,
  AniListDate
} from './ScraperTypes';

const TAG = 'AniListScraper';

/**
 * AniList GraphQL 变量接口
 */
interface AniListSearchVariables {
  search: string;
  type: string;
  page: number;
  perPage: number;
}

interface AniListDetailVariables {
  id: number;
}

interface AniListGraphQLRequest {
  query: string;
  variables: AniListSearchVariables | AniListDetailVariables;
}


/**
 * AniList 媒体类型
 */
export enum AniListMediaType {
  ANIME = 'ANIME',
  MANGA = 'MANGA'
}

/**
 * AniList 媒体格式
 */
export enum AniListMediaFormat {
  TV = 'TV',
  TV_SHORT = 'TV_SHORT',
  MOVIE = 'MOVIE',
  SPECIAL = 'SPECIAL',
  OVA = 'OVA',
  ONA = 'ONA',
  MUSIC = 'MUSIC',
  MANGA = 'MANGA',
  NOVEL = 'NOVEL',
  ONE_SHOT = 'ONE_SHOT'
}

/**
 * AniList 刮削器配置
 */
export interface AniListScraperConfig {
  accessToken?: string;
  timeout?: number;
}

/**
 * AniList 刮削器
 */
export class AniListScraper {
  private static readonly GRAPHQL_URL = 'https://graphql.anilist.co';
  private config: AniListScraperConfig;

  constructor(config?: AniListScraperConfig) {
    this.config = config || {};
  }

  /**
   * 设置访问令牌
   */
  public setAccessToken(token: string): void {
    this.config.accessToken = token;
  }

  /**
   * 搜索媒体
   * @param keyword 搜索关键词
   * @param type 媒体类型
   * @param page 页码
   * @param perPage 每页数量
   */
  public async search(
    keyword: string,
    type: AniListMediaType = AniListMediaType.MANGA,
    page: number = 1,
    perPage: number = 25
  ): Promise<ScraperSearchResult> {
    try {
      logger.info(TAG, `搜索AniList: keyword=${keyword}, type=${type}`);

      const query = `
        query ($search: String, $type: MediaType, $page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            pageInfo {
              total
              currentPage
              lastPage
              hasNextPage
              perPage
            }
            media(type: $type, search: $search, sort: SEARCH_MATCH) {
              id
              idMal
              title {
                romaji
                english
                native
                userPreferred
              }
              type
              format
              status
              description(asHtml: false)
              startDate {
                year
                month
                day
              }
              endDate {
                year
                month
                day
              }
              chapters
              volumes
              coverImage {
                extraLarge
                large
                medium
                color
              }
              bannerImage
              genres
              synonyms
              averageScore
              meanScore
              popularity
              favourites
              tags {
                id
                name
                rank
                isAdult
              }
              staff(perPage: 10) {
                edges {
                  role
                  node {
                    id
                    name {
                      full
                      native
                    }
                  }
                }
              }
              siteUrl
            }
          }
        }
      `;

      const variables: AniListSearchVariables = {
        search: keyword,
        type: type,
        page: page,
        perPage: perPage
      };

      const response = await this.executeQuery(query, variables);

      if (response.errors && response.errors.length > 0) {
        throw new Error(response.errors[0].message);
      }

      const pageData = response.data?.Page;
      const mediaList = pageData?.media || [];
      const results: ScrapedMetadata[] = mediaList.map((media: AniListMedia) => this.convertToMetadata(media));

      logger.info(TAG, `AniList搜索成功: 找到 ${results.length} 条结果`);

      return {
        success: true,
        source: ScraperSource.ANILIST,
        results: results,
        totalCount: pageData?.pageInfo?.total
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `AniList搜索失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.ANILIST,
        results: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 获取媒体详情
   * @param mediaId 媒体ID
   */
  public async getDetail(mediaId: number | string): Promise<ScraperDetailResult> {
    try {
      logger.info(TAG, `获取AniList媒体详情: ${mediaId}`);

      const query = `
        query ($id: Int) {
          Media(id: $id) {
            id
            idMal
            title {
              romaji
              english
              native
              userPreferred
            }
            type
            format
            status
            description(asHtml: false)
            startDate {
              year
              month
              day
            }
            endDate {
              year
              month
              day
            }
            chapters
            volumes
            countryOfOrigin
            isLicensed
            source
            coverImage {
              extraLarge
              large
              medium
              color
            }
            bannerImage
            genres
            synonyms
            averageScore
            meanScore
            popularity
            trending
            favourites
            tags {
              id
              name
              description
              category
              rank
              isGeneralSpoiler
              isMediaSpoiler
              isAdult
            }
            staff(perPage: 25) {
              edges {
                role
                node {
                  id
                  name {
                    first
                    middle
                    last
                    full
                    native
                  }
                }
              }
            }
            siteUrl
          }
        }
      `;

      const variables: AniListDetailVariables = {
        id: typeof mediaId === 'string' ? parseInt(mediaId) : mediaId
      };

      const response = await this.executeQuery(query, variables);

      if (response.errors && response.errors.length > 0) {
        throw new Error(response.errors[0].message);
      }

      const media = response.data?.Media;
      if (!media) {
        throw new Error('Media not found');
      }

      const metadata = this.convertToMetadata(media);

      logger.info(TAG, `AniList详情获取成功: ${metadata.title}`);

      return {
        success: true,
        source: ScraperSource.ANILIST,
        data: metadata
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `AniList详情获取失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.ANILIST,
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 搜索漫画
   */
  public async searchManga(keyword: string, perPage: number = 25): Promise<ScraperSearchResult> {
    return this.search(keyword, AniListMediaType.MANGA, 1, perPage);
  }

  /**
   * 搜索动画
   */
  public async searchAnime(keyword: string, perPage: number = 25): Promise<ScraperSearchResult> {
    return this.search(keyword, AniListMediaType.ANIME, 1, perPage);
  }

  /**
   * 执行GraphQL查询
   */
  private async executeQuery(query: string, variables: AniListSearchVariables | AniListDetailVariables): Promise<AniListResponse> {
    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(AniListScraper.GRAPHQL_URL, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(),
        extraData: JSON.stringify({
          query: query,
          variables: variables
        }),
        connectTimeout: this.config.timeout || 15000,
        readTimeout: this.config.timeout || 15000
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      return SafeUtils.parseObj(response.result as string) as AniListResponse;
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 构建请求头
   */
  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };

    if (this.config.accessToken) {
      headers['Authorization'] = `Bearer ${this.config.accessToken}`;
    }

    return headers;
  }

  /**
   * 将AniList媒体转换为统一元数据格式
   */
  private convertToMetadata(media: AniListMedia): ScrapedMetadata {
    // 提取作者和画师
    const authors: string[] = [];
    const artists: string[] = [];
    
    if (media.staff?.edges) {
      for (const edge of media.staff.edges as AniListStaffEdge[]) {
        const name = edge.node?.name?.full || edge.node?.name?.native || '';
        const role = edge.role?.toLowerCase() || '';
        
        if (role.includes('story') || role.includes('original') || role.includes('author')) {
          if (name && !authors.includes(name)) {
            authors.push(name);
          }
        }
        if (role.includes('art') || role.includes('illustration')) {
          if (name && !artists.includes(name)) {
            artists.push(name);
          }
        }
      }
    }

    // 提取标签（过滤成人内容标签）
    const tags = media.tags
      ?.filter(t => !t.isAdult)
      .map(t => t.name) || [];

    // 格式化日期
    const formatDate = (date: AniListDate | undefined): string | undefined => {
      if (!date || !date.year) return undefined;
      const parts = [String(date.year)];
      if (date.month) parts.push(String(date.month).padStart(2, '0'));
      if (date.day) parts.push(String(date.day).padStart(2, '0'));
      return parts.join('-');
    };

    return {
      id: `anilist_${media.id}`,
      source: ScraperSource.ANILIST,
      externalId: String(media.id),
      title: media.title?.userPreferred || media.title?.romaji || media.title?.english || media.title?.native || '',
      titleNative: media.title?.native,
      titleRomaji: media.title?.romaji,
      titleEnglish: media.title?.english,
      alternativeTitles: media.synonyms,
      description: media.description,
      summary: media.description,
      coverUrl: media.coverImage?.extraLarge || media.coverImage?.large,
      coverUrlLarge: media.coverImage?.extraLarge,
      coverUrlMedium: media.coverImage?.large,
      coverUrlSmall: media.coverImage?.medium,
      authors: authors.length > 0 ? authors : undefined,
      author: authors.length > 0 ? authors[0] : undefined,
      artists: artists.length > 0 ? artists : undefined,
      artist: artists.length > 0 ? artists[0] : undefined,
      genres: media.genres,
      tags: tags,
      score: media.averageScore ? media.averageScore / 10 : undefined, // 转换为10分制
      scoreMax: 10,
      popularity: media.popularity,
      releaseDate: formatDate(media.startDate),
      endDate: formatDate(media.endDate),
      volumes: media.volumes,
      chapters: media.chapters,
      status: this.mapStatus(media.status),
      rawData: media as Object
    };
  }

  /**
   * 映射状态
   */
  private mapStatus(status: string | undefined): string {
    switch (status) {
      case 'FINISHED':
        return 'completed';
      case 'RELEASING':
        return 'ongoing';
      case 'NOT_YET_RELEASED':
        return 'upcoming';
      case 'CANCELLED':
        return 'cancelled';
      case 'HIATUS':
        return 'hiatus';
      default:
        return 'unknown';
    }
  }
}
