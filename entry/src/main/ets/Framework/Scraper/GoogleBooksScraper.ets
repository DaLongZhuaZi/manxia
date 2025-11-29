// 文件路径: entry/src/main/ets/Framework/Scraper/GoogleBooksScraper.ets
/**
 * Google Books 刮削器
 * Google图书API，支持中英文书籍搜索
 * API文档: https://developers.google.com/books/docs/v1/using
 * 
 * 注意：
 * - 无需API Key也可使用，但有请求配额限制
 * - 使用API Key可获得更高配额
 * - 搜索支持特殊关键词: intitle:, inauthor:, inpublisher:, subject:, isbn:
 */

import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  ScraperSource,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  GoogleBooksSearchResponse,
  GoogleBooksVolume,
  GoogleBooksVolumeInfo,
  GoogleBooksImageLinks
} from './ScraperTypes';

const TAG = 'GoogleBooksScraper';

/**
 * Google Books 刮削器配置
 */
export interface GoogleBooksScraperConfig {
  apiKey?: string;        // Google API Key (可选，但推荐使用)
  timeout?: number;
  language?: string;      // 语言限制，如 'zh-CN', 'en'
  country?: string;       // 国家/地区，如 'CN', 'US'
}

/**
 * 封面URL结果接口
 */
interface CoverUrlResult {
  thumbnail?: string;
  medium?: string;
  large?: string;
}

/**
 * Google Books 刮削器
 */
export class GoogleBooksScraper {
  private static readonly BASE_URL = 'https://www.googleapis.com/books/v1';
  private config: GoogleBooksScraperConfig;

  constructor(config?: GoogleBooksScraperConfig) {
    this.config = config || {};
  }

  /**
   * 设置API Key
   */
  public setApiKey(apiKey: string): void {
    this.config.apiKey = apiKey;
    logger.info(TAG, 'Google Books API Key已设置');
  }

  /**
   * 按标题搜索书籍
   * @param title 书籍标题
   * @param limit 返回数量限制 (最大40)
   */
  public async searchByTitle(title: string, limit: number = 20): Promise<ScraperSearchResult> {
    const query = `intitle:${title}`;
    return this.searchVolumes(query, limit);
  }

  /**
   * 按作者搜索书籍
   * @param author 作者名
   * @param limit 返回数量限制
   */
  public async searchByAuthor(author: string, limit: number = 20): Promise<ScraperSearchResult> {
    const query = `inauthor:${author}`;
    return this.searchVolumes(query, limit);
  }

  /**
   * 按ISBN搜索书籍
   * @param isbn ISBN号
   */
  public async searchByIsbn(isbn: string): Promise<ScraperSearchResult> {
    const cleanIsbn = isbn.replace(/[\s\-]/g, '');
    const query = `isbn:${cleanIsbn}`;
    return this.searchVolumes(query, 1);
  }

  /**
   * 按出版社搜索书籍
   * @param publisher 出版社名称
   * @param limit 返回数量限制
   */
  public async searchByPublisher(publisher: string, limit: number = 20): Promise<ScraperSearchResult> {
    const query = `inpublisher:${publisher}`;
    return this.searchVolumes(query, limit);
  }

  /**
   * 按分类/主题搜索书籍
   * @param subject 分类/主题
   * @param limit 返回数量限制
   */
  public async searchBySubject(subject: string, limit: number = 20): Promise<ScraperSearchResult> {
    const query = `subject:${subject}`;
    return this.searchVolumes(query, limit);
  }

  /**
   * 通用搜索方法
   * 自动检测ISBN格式，否则进行全文搜索
   */
  public async search(keyword: string, limit: number = 20): Promise<ScraperSearchResult> {
    // 检查是否是ISBN格式
    const isbnPattern = /^[\d\-X]{10,17}$/i;
    const cleanKeyword = keyword.replace(/[\s\-]/g, '');
    
    if (isbnPattern.test(cleanKeyword) && (cleanKeyword.length === 10 || cleanKeyword.length === 13)) {
      return this.searchByIsbn(keyword);
    }
    
    // 普通搜索
    return this.searchVolumes(keyword, limit);
  }

  /**
   * 执行卷搜索
   * @param query 搜索查询
   * @param limit 返回数量限制
   */
  private async searchVolumes(query: string, limit: number): Promise<ScraperSearchResult> {
    try {
      logger.info(TAG, `搜索Google Books: query=${query}`);

      const encodedQuery = encodeURIComponent(query);
      let url = `${GoogleBooksScraper.BASE_URL}/volumes?q=${encodedQuery}&maxResults=${Math.min(limit, 40)}`;
      
      // 添加语言限制
      if (this.config.language) {
        url += `&langRestrict=${this.config.language}`;
      }
      
      // 添加API Key
      if (this.config.apiKey) {
        url += `&key=${this.config.apiKey}`;
      }

      // 只返回书籍类型
      url += '&printType=books';

      const response = await this.makeRequest(url);
      const data: GoogleBooksSearchResponse = JSON.parse(response) as GoogleBooksSearchResponse;

      const results: ScrapedMetadata[] = [];
      if (data.items) {
        for (const volume of data.items) {
          results.push(this.convertVolumeToMetadata(volume));
        }
      }

      logger.info(TAG, `Google Books搜索成功: 找到 ${results.length} 条结果 (总计 ${data.totalItems})`);

      return {
        success: true,
        source: ScraperSource.GOOGLE_BOOKS,
        results: results,
        totalCount: data.totalItems
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Google Books搜索失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.GOOGLE_BOOKS,
        results: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 获取书籍详情
   * @param volumeId Google Books Volume ID
   */
  public async getDetail(volumeId: string): Promise<ScraperDetailResult> {
    try {
      logger.info(TAG, `获取Google Books书籍详情: ${volumeId}`);

      let url = `${GoogleBooksScraper.BASE_URL}/volumes/${volumeId}`;
      
      if (this.config.apiKey) {
        url += `?key=${this.config.apiKey}`;
      }

      const response = await this.makeRequest(url);
      const volume: GoogleBooksVolume = JSON.parse(response) as GoogleBooksVolume;

      const metadata = this.convertVolumeToMetadata(volume);

      return {
        success: true,
        source: ScraperSource.GOOGLE_BOOKS,
        data: metadata
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `Google Books详情获取失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.GOOGLE_BOOKS,
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 发送HTTP请求
   */
  private async makeRequest(url: string): Promise<string> {
    const httpRequest = http.createHttp();
    
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(),
        connectTimeout: this.config.timeout || 15000,
        readTimeout: this.config.timeout || 15000
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }

      return response.result as string;
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 构建请求头
   */
  private buildHeaders(): Record<string, string> {
    return {
      'Accept': 'application/json',
      'User-Agent': 'Manxia/1.0'
    };
  }

  /**
   * 将Google Books卷转换为统一元数据格式
   */
  private convertVolumeToMetadata(volume: GoogleBooksVolume): ScrapedMetadata {
    const info: GoogleBooksVolumeInfo = volume.volumeInfo;
    
    // 处理封面图片
    const coverUrls = this.extractCoverUrls(info.imageLinks);
    
    // 提取ISBN
    let isbn: string | undefined;
    if (info.industryIdentifiers) {
      // 优先使用ISBN_13
      const isbn13 = info.industryIdentifiers.find(id => id.type === 'ISBN_13');
      const isbn10 = info.industryIdentifiers.find(id => id.type === 'ISBN_10');
      isbn = isbn13?.identifier || isbn10?.identifier;
    }

    // 处理描述，移除HTML标签
    let description = info.description;
    if (description) {
      description = this.stripHtmlTags(description);
    }

    return {
      id: `googlebooks_${volume.id}`,
      source: ScraperSource.GOOGLE_BOOKS,
      externalId: volume.id,
      title: info.title,
      titleEnglish: info.title,
      description: description,
      summary: description,
      authors: info.authors,
      author: info.authors ? info.authors.join(', ') : undefined,
      publisher: info.publisher,
      coverUrl: coverUrls.large || coverUrls.medium || coverUrls.thumbnail,
      coverUrlLarge: coverUrls.large,
      coverUrlMedium: coverUrls.medium,
      coverUrlSmall: coverUrls.thumbnail,
      releaseDate: info.publishedDate,
      genres: info.categories,
      tags: info.categories,
      score: info.averageRating,
      scoreMax: 5,
      ratingCount: info.ratingsCount,
      chapters: info.pageCount,
      rawData: volume as Object
    };
  }

  /**
   * 提取封面URL
   * Google Books的封面URL需要处理以获取更高质量的图片
   */
  private extractCoverUrls(imageLinks?: GoogleBooksImageLinks): CoverUrlResult {
    if (!imageLinks) {
      const emptyResult: CoverUrlResult = {
        thumbnail: undefined,
        medium: undefined,
        large: undefined
      };
      return emptyResult;
    }

    // Google Books的图片URL可以通过修改参数获取不同尺寸
    // zoom=1 是缩略图，zoom=2 是中等，zoom=3 是大图
    const processUrl = (url: string | undefined, zoom: number): string | undefined => {
      if (!url) return undefined;
      
      // 移除现有的zoom参数并添加新的
      let processedUrl = url.replace(/&zoom=\d/, '');
      processedUrl = processedUrl.replace(/zoom=\d/, '');
      
      // 确保使用HTTPS
      processedUrl = processedUrl.replace('http://', 'https://');
      
      // 添加zoom参数
      if (processedUrl.includes('?')) {
        processedUrl += `&zoom=${zoom}`;
      } else {
        processedUrl += `?zoom=${zoom}`;
      }
      
      return processedUrl;
    };

    const baseUrl = imageLinks.extraLarge || imageLinks.large || imageLinks.medium || 
                    imageLinks.small || imageLinks.thumbnail || imageLinks.smallThumbnail;

    const result: CoverUrlResult = {
      thumbnail: processUrl(baseUrl, 1),
      medium: processUrl(baseUrl, 2),
      large: processUrl(baseUrl, 3)
    };
    return result;
  }

  /**
   * 移除HTML标签
   */
  private stripHtmlTags(html: string): string {
    return html
      .replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .trim();
  }
}
