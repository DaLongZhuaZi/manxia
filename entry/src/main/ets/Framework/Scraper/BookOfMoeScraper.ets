import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Scraper/BookOfMoeScraper.ets
/**
 * BookOf.Moe 刮削器
 * 轻小说/书籍元数据API
 */

import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  ScraperSource,
  ScrapedMetadata,
  ScraperSearchResult,
  ScraperDetailResult,
  BookOfMoeBook,
  BookOfMoeSearchResult
} from './ScraperTypes';

const TAG = 'BookOfMoeScraper';

/**
 * BookOf.Moe API响应接口
 */
interface BookOfMoeApiResponse {
  success?: boolean;
  data?: BookOfMoeBook[];
  error?: string;
  title?: string;
}

/**
 * BookOf.Moe 刮削器配置
 */
export interface BookOfMoeScraperConfig {
  timeout?: number;
}

/**
 * BookOf.Moe 刮削器
 */
export class BookOfMoeScraper {
  private static readonly BASE_URL = 'https://bookof.moe/api';
  private config: BookOfMoeScraperConfig;

  constructor(config?: BookOfMoeScraperConfig) {
    this.config = config || {};
  }

  /**
   * 按标题搜索书籍
   * @param title 书籍标题
   */
  public async searchByTitle(title: string): Promise<ScraperSearchResult> {
    try {
      logger.info(TAG, `搜索BookOf.Moe: title=${title}`);

      const encodedTitle = encodeURIComponent(title);
      const url = `${BookOfMoeScraper.BASE_URL}/book?title=${encodedTitle}`;

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

      const responseText = response.result as string;
      
      // 尝试解析响应
      const books: BookOfMoeBook[] = this.parseApiResponse(responseText);

      const results: ScrapedMetadata[] = books.map(book => this.convertToMetadata(book));

      logger.info(TAG, `BookOf.Moe搜索成功: 找到 ${results.length} 条结果`);

      return {
        success: true,
        source: ScraperSource.BOOKOF_MOE,
        results: results,
        totalCount: results.length
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `BookOf.Moe搜索失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.BOOKOF_MOE,
        results: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 按ISBN搜索书籍
   * @param isbn ISBN号
   */
  public async searchByIsbn(isbn: string): Promise<ScraperSearchResult> {
    try {
      logger.info(TAG, `按ISBN搜索BookOf.Moe: isbn=${isbn}`);

      const url = `${BookOfMoeScraper.BASE_URL}/book?isbn=${isbn}`;

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

      const responseText = response.result as string;
      const books: BookOfMoeBook[] = this.parseApiResponse(responseText);

      const results: ScrapedMetadata[] = books.map(book => this.convertToMetadata(book));

      logger.info(TAG, `BookOf.Moe ISBN搜索成功: 找到 ${results.length} 条结果`);

      return {
        success: true,
        source: ScraperSource.BOOKOF_MOE,
        results: results,
        totalCount: results.length
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `BookOf.Moe ISBN搜索失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.BOOKOF_MOE,
        results: [],
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 搜索书籍（通用方法）
   */
  public async search(keyword: string): Promise<ScraperSearchResult> {
    // 检查是否是ISBN格式
    const isbnPattern = /^[\d\-X]{10,17}$/i;
    if (isbnPattern.test(keyword.replace(/[\s\-]/g, ''))) {
      return this.searchByIsbn(keyword);
    }
    return this.searchByTitle(keyword);
  }

  /**
   * 获取书籍详情
   * 注意：BookOf.Moe可能没有独立的详情API，使用搜索API获取
   */
  public async getDetail(bookId: string): Promise<ScraperDetailResult> {
    try {
      logger.info(TAG, `获取BookOf.Moe书籍详情: ${bookId}`);

      // 尝试使用ID或标题搜索
      const searchResult = await this.searchByTitle(bookId);
      
      if (searchResult.success && searchResult.results.length > 0) {
        // 查找匹配的结果
        const match = searchResult.results.find(r => 
          r.externalId === bookId || r.title === bookId
        );
        
        if (match) {
          return {
            success: true,
            source: ScraperSource.BOOKOF_MOE,
            data: match
          };
        }
        
        // 返回第一个结果
        return {
          success: true,
          source: ScraperSource.BOOKOF_MOE,
          data: searchResult.results[0]
        };
      }

      return {
        success: false,
        source: ScraperSource.BOOKOF_MOE,
        errorMessage: '未找到书籍'
      };
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `BookOf.Moe详情获取失败: ${errorMsg}`);
      return {
        success: false,
        source: ScraperSource.BOOKOF_MOE,
        errorMessage: errorMsg
      };
    }
  }

  /**
   * 解析API响应
   */
  private parseApiResponse(responseText: string): BookOfMoeBook[] {
    try {
      const data: BookOfMoeApiResponse = SafeUtils.parseObj(responseText) as BookOfMoeApiResponse;
      
      // 检查是否是数组响应
      if (Array.isArray(data)) {
        return data as BookOfMoeBook[];
      }
      
      // 检查是否有data字段
      if (data.data && Array.isArray(data.data)) {
        return data.data;
      }
      
      // 检查是否是错误响应
      if (data.success === false) {
        logger.warn(TAG, `API返回错误: ${data.error}`);
        return [];
      }
      
      // 检查是否是单个结果
      if (data.title) {
        return [data as BookOfMoeBook];
      }
      
      return [];
    } catch (parseError) {
      logger.warn(TAG, `解析响应失败: ${parseError}`);
      return [];
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
   * 将BookOf.Moe书籍转换为统一元数据格式
   */
  private convertToMetadata(book: BookOfMoeBook): ScrapedMetadata {
    return {
      id: `bookofmoe_${book.id || book.isbn || book.title}`,
      source: ScraperSource.BOOKOF_MOE,
      externalId: book.id || book.isbn || '',
      title: book.title || '',
      description: book.description,
      summary: book.description,
      coverUrl: book.cover,
      coverUrlLarge: book.cover,
      author: book.author,
      authors: book.author ? [book.author] : undefined,
      publisher: book.publisher,
      tags: book.tags,
      genres: book.tags?.slice(0, 5),
      score: book.rating,
      scoreMax: 10,
      releaseDate: book.publishDate,
      rawData: book as Object
    };
  }
}
