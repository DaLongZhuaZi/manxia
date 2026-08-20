import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 图源执行引擎
 * 负责执行图源的各种操作（搜索、获取详情等）
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { JSONSourceParser, JSONSourceConfig } from './JSONSourceParser';
import { http } from '@kit.NetworkKit';
import { ProxyManager } from 'manxia_network/src/main/ets/Framework/Network/ProxyManager';
import { UserAgentManager } from 'manxia_core/src/main/ets/Framework/Managers/UserAgentManager';

const TAG = 'SourceExecutor';

/**
 * 漫画信息
 */
export interface ComicInfo {
  id: string;
  title: string;
  author?: string;
  coverUrl?: string;
  description?: string;
  status?: string;
  tags?: string[];
  url?: string;
  updateTime?: number;
  instanceId?: string;
}

/**
 * 章节信息
 */
export interface ChapterInfo {
  id: string;
  title: string;
  url?: string;
  updateTime?: number;
  chapterNumber?: number;
  seriesTitle?: string;
  pageCount?: number;
  coverUrl?: string;
  instanceId?: string;
}


/**
 * 页面信息
 */
export interface PageInfo {
  url: string;
  width?: number;
  height?: number;
}

/**
 * 漫画详情信息（包含章节列表）
 */
export interface ComicDetailInfo extends ComicInfo {
  chapters?: ChapterInfo[];
}

/**
 * HTTP请求选项
 */
export interface HttpRequestOptions {
  method: string;
  headers: ESObject;
  body?: ESObject;
  timeout: number;
}

/**
 * 图源执行器类
 */
export class SourceExecutor {
  private dataManager: DataManager;
  private parsers: Map<number, JSONSourceParser> = new Map();
  private userAgentManager: UserAgentManager;

  constructor() {
    this.dataManager = DataManager.getInstance();
    this.userAgentManager = UserAgentManager.getInstance();
  }

  /**
   * 获取或创建解析器
   */
  private async getParser(sourceId: number): Promise<JSONSourceParser> {
    // 检查缓存
    if (this.parsers.has(sourceId)) {
      return this.parsers.get(sourceId)!;
    }

    // 从数据库加载配置
    const config: Object | null = await this.dataManager.getSourceConfig(sourceId);
    if (!config) {
      throw new Error(`图源不存在: ${sourceId}`);
    }

    // 创建解析器
    const parser = new JSONSourceParser(config as JSONSourceConfig);
    if (!parser.validate()) {
      throw new Error(`图源配置无效: ${sourceId}`);
    }

    // 缓存解析器
    this.parsers.set(sourceId, parser);
    return parser;
  }

  /**
   * 执行HTTP请求
   */
  private async executeRequest(url: string, options: HttpRequestOptions, sourceId?: number): Promise<ESObject> {
    try {
      logger.debug(TAG, `HTTP请求: ${options.method} ${url}`);

      // 获取自定义User-Agent
      let userAgent: string | undefined = undefined;
      if (sourceId !== undefined) {
        const configUA = options.headers?.['User-Agent'] as string;
        userAgent = await this.userAgentManager.getUserAgent(sourceId, configUA);
      }

      const requestOptions: http.HttpRequestOptions = {
        method: options.method as http.RequestMethod,
        header: options.headers as Object,
        connectTimeout: options.timeout,
        readTimeout: options.timeout,
      };

      // 应用自定义User-Agent
      if (userAgent) {
        const headers: ESObject = requestOptions.header as ESObject || {};
        headers['User-Agent'] = userAgent;
        requestOptions.header = headers as Object;
      }

      // 添加请求体
      if (options.body && (options.method === 'POST' || options.method === 'PUT')) {
        requestOptions.extraData = JSON.stringify(options.body);
        const headers: ESObject = requestOptions.header as ESObject || {};
        headers['Content-Type'] = 'application/json';
        requestOptions.header = headers as Object;
      }

      // 应用代理配置
      const proxyManager = ProxyManager.getInstance();
      if (proxyManager.isEnabled()) {
        await proxyManager.applyToHttpOptions(requestOptions, url);
        const proxyUrl = proxyManager.getHttpRequestProxy() || 'custom';
        logger.debug(TAG, `使用代理: ${proxyUrl}`);
      }

      const request = http.createHttp();
      const response = await request.request(url, requestOptions);

      // 解析响应
      const data: ESObject = typeof response.result === 'string' ?
        SafeUtils.parseObj(response.result) as ESObject :
        response.result as ESObject;

      request.destroy();
      return data;
    } catch (error) {
      logger.error(TAG, `HTTP请求失败: ${url}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 获取热门漫画
   */
  async getPopular(sourceId: number, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    try {
      const parser = await this.getParser(sourceId);
      
      // 构建请求
      const params: Record<string, Object> = {
        'page': page,
        'limit': limit,
        'offset': (page - 1) * limit
      };
      const requestInfo = parser.buildRequest('popular', params);

      // 执行请求
      const httpOptions: HttpRequestOptions = {
        method: requestInfo.method,
        headers: requestInfo.headers,
        body: requestInfo.body,
        timeout: requestInfo.timeout
      };
      const response: ESObject = await this.executeRequest(requestInfo.url, httpOptions, sourceId);

      // 解析响应
      const items: ESObject[] = parser.parseResponse('popular', response);
      
      return items.map((item: ESObject): ComicInfo => this.mapToComicInfo(item));
    } catch (error) {
      logger.error(TAG, `获取热门漫画失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 获取最新更新
   */
  async getLatest(sourceId: number, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    try {
      const parser = await this.getParser(sourceId);
      
      const params: Record<string, Object> = {
        'page': page,
        'limit': limit,
        'offset': (page - 1) * limit
      };
      const requestInfo = parser.buildRequest('latest', params);

      const httpOptions: HttpRequestOptions = {
        method: requestInfo.method,
        headers: requestInfo.headers,
        body: requestInfo.body,
        timeout: requestInfo.timeout
      };
      const response: ESObject = await this.executeRequest(requestInfo.url, httpOptions, sourceId);

      const items: ESObject[] = parser.parseResponse('latest', response);
      return items.map((item: ESObject): ComicInfo => this.mapToComicInfo(item));
    } catch (error) {
      logger.error(TAG, `获取最新更新失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 搜索漫画
   */
  async search(sourceId: number, keyword: string, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    try {
      const parser = await this.getParser(sourceId);
      
      const params: Record<string, Object> = {
        'keyword': keyword,
        'page': page,
        'limit': limit,
        'offset': (page - 1) * limit
      };
      const requestInfo = parser.buildRequest('search', params);

      const httpOptions: HttpRequestOptions = {
        method: requestInfo.method,
        headers: requestInfo.headers,
        body: requestInfo.body,
        timeout: requestInfo.timeout
      };
      const response: ESObject = await this.executeRequest(requestInfo.url, httpOptions, sourceId);

      const items: ESObject[] = parser.parseResponse('search', response);
      return items.map((item: ESObject): ComicInfo => this.mapToComicInfo(item));
    } catch (error) {
      logger.error(TAG, `搜索失败: sourceId=${sourceId}, keyword=${keyword}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 获取漫画详情
   */
  async getDetail(sourceId: number, comicId: string): Promise<ComicDetailInfo> {
    try {
      const parser = await this.getParser(sourceId);
      
      const params: Record<string, Object> = {
        'comicId': comicId
      };
      const requestInfo = parser.buildRequest('detail', params);

      const httpOptions: HttpRequestOptions = {
        method: requestInfo.method,
        headers: requestInfo.headers,
        body: requestInfo.body,
        timeout: requestInfo.timeout
      };
      const response: ESObject = await this.executeRequest(requestInfo.url, httpOptions, sourceId);

      const items: ESObject[] = parser.parseResponse('detail', response);
      if (items.length === 0) {
        throw new Error('未找到漫画详情');
      }

      const detail: ESObject = items[0];
      const comicInfo: ComicInfo = this.mapToComicInfo(detail);

      // 解析章节列表
      if (detail.chapters && Array.isArray(detail.chapters)) {
        const chapters: ChapterInfo[] = (detail.chapters as ESObject[]).map((chapter: ESObject): ChapterInfo => {
          const chapterInfo: ChapterInfo = {
            id: chapter.id as string,
            title: chapter.title as string,
            url: chapter.url as string,
            updateTime: chapter.updateTime as number
          };
          return chapterInfo;
        });
        (comicInfo as ESObject).chapters = chapters;
      }

      return comicInfo as ComicDetailInfo;
    } catch (error) {
      logger.error(TAG, `获取详情失败: sourceId=${sourceId}, comicId=${comicId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 获取章节图片
   */
  async getPages(sourceId: number, chapterId: string): Promise<PageInfo[]> {
    try {
      const parser = await this.getParser(sourceId);
      
      const params: Record<string, Object> = {
        'chapterId': chapterId
      };
      const requestInfo = parser.buildRequest('pages', params);

      const httpOptions: HttpRequestOptions = {
        method: requestInfo.method,
        headers: requestInfo.headers,
        body: requestInfo.body,
        timeout: requestInfo.timeout
      };
      const response: ESObject = await this.executeRequest(requestInfo.url, httpOptions, sourceId);

      const items: ESObject[] = parser.parseResponse('pages', response);
      
      const pages: PageInfo[] = items.map((item: ESObject): PageInfo => {
        const page: PageInfo = {
          url: item.url as string,
          width: item.width as number,
          height: item.height as number
        };
        return page;
      });
      return pages;
    } catch (error) {
      logger.error(TAG, `获取章节图片失败: sourceId=${sourceId}, chapterId=${chapterId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 映射到ComicInfo
   */
  private mapToComicInfo(item: ESObject): ComicInfo {
    return {
      id: item.id as string || '',
      title: item.title as string || '',
      author: item.author as string,
      coverUrl: item.coverUrl as string,
      description: item.description as string,
      status: item.status as string,
      tags: item.tags as string[],
      url: item.url as string,
      updateTime: item.updateTime as number
    };
  }

  /**
   * 清除缓存
   */
  clearCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      this.parsers.delete(sourceId);
    } else {
      this.parsers.clear();
    }
  }
}
