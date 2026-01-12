/**
 * Suwayomi 跟踪器
 * 支持两种模式：
 * 1. 图源模式 - 作为漫画源使用，可同步进度
 * 2. 服务器模式 - 直接访问 WebUI
 */

import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { logger } from '../../../Utils/Logger';
import { BaseTracker, TrackerAuthState } from './BaseTracker';
import {
  TrackRecord,
  TrackStatus,
  TrackSearchResult,
  UpdateTrackRecordParams,
  TrackerId
} from '../TrackingModels';

const TAG = 'SuwayomiTracker';

// Suwayomi 配置接口
export interface SuwayomiConfig {
  serverUrl: string;      // 服务器地址 (如 http://192.168.1.100:4567)
  username: string;       // 用户名（可选）
  password: string;       // 密码（可选）
  useAuth: boolean;       // 是否使用认证
  useBrowsePageAsEntry?: boolean;  // 使用浏览页面作为入口
}

// Suwayomi 漫画信息
export interface SuwayomiManga {
  id: number;
  title: string;
  thumbnailUrl: string;
  url: string;
  artist: string;
  author: string;
  description: string;
  genre: string[];
  status: string;
  inLibrary: boolean;
  lastChapterRead: number;
  totalChapters: number;
}

// Suwayomi 章节信息
export interface SuwayomiChapter {
  id: number;
  name: string;
  chapterNumber: number;
  isRead: boolean;
  isDownloaded: boolean;
  pageCount: number;
  uploadDate: number;
  url: string;
}

// Suwayomi 源信息
export interface SuwayomiSource {
  id: string;
  name: string;
  lang: string;
  iconUrl: string;
  isNsfw: boolean;
}

// GraphQL 响应接口
interface GraphQLResponse {
  data?: GraphQLData;
  errors?: GraphQLError[];
}

interface GraphQLData {
  mangas?: GraphQLMangaConnection;
  manga?: SuwayomiManga;
  chapters?: GraphQLChapterConnection;
  sources?: SuwayomiSource[];
  searchManga?: GraphQLMangaConnection;
}

interface GraphQLMangaConnection {
  nodes: SuwayomiManga[];
  totalCount: number;
}

interface GraphQLChapterConnection {
  nodes: SuwayomiChapter[];
  totalCount: number;
}

interface GraphQLError {
  message: string;
}

// GraphQL 变量接口
interface SourceSearchVariables {
  sourceId: string;
  query: string;
}

interface MangaIdVariables {
  id: number;
}

interface MangaIdNumberVariables {
  mangaId: number;
}

interface ChapterUpdateVariables {
  id: number;
  isRead: boolean;
}

interface SearchQueryVariables {
  query: string;
}

// 单例实例
let suwayomiTrackerInstance: SuwayomiTracker | null = null;

/**
 * 获取 SuwayomiTracker 单例
 */
export function getSuwayomiTracker(): SuwayomiTracker {
  if (!suwayomiTrackerInstance) {
    suwayomiTrackerInstance = new SuwayomiTracker();
  }
  return suwayomiTrackerInstance;
}

/**
 * Suwayomi 跟踪器实现
 */
export class SuwayomiTracker extends BaseTracker {
  private config: SuwayomiConfig = {
    serverUrl: '',
    username: '',
    password: '',
    useAuth: false
  };
  private _isInitialized: boolean = false;

  constructor() {
    super(TrackerId.SUWAYOMI, 'Suwayomi');
  }

  /**
   * 初始化跟踪器
   */
  public async initialize(): Promise<void> {
    if (this._isInitialized) {
      return;
    }
    await this.loadConfig();
    this._isInitialized = true;
    this.log('初始化完成');
  }

  /**
   * 加载配置
   */
  private async loadConfig(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: 'suwayomi_config' });
      const serverUrl = store.getSync('serverUrl', '') as string;
      const username = store.getSync('username', '') as string;
      const password = store.getSync('password', '') as string;
      const useAuth = store.getSync('useAuth', false) as boolean;
      const useBrowsePageAsEntry = store.getSync('useBrowsePageAsEntry', false) as boolean;

      this.config = { serverUrl, username, password, useAuth, useBrowsePageAsEntry };

      // 如果有服务器配置，认为已登录
      if (serverUrl) {
        this.authState.isLoggedIn = true;
        this.authState.username = serverUrl;
      }

      this.log(`配置加载完成: ${serverUrl}`);
    } catch (error) {
      this.logError('加载配置失败', String(error));
    }
  }

  /**
   * 保存配置
   */
  public async saveConfig(config: SuwayomiConfig): Promise<boolean> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: 'suwayomi_config' });
      store.putSync('serverUrl', config.serverUrl);
      store.putSync('username', config.username);
      store.putSync('password', config.password);
      store.putSync('useAuth', config.useAuth);
      store.putSync('useBrowsePageAsEntry', config.useBrowsePageAsEntry ?? false);
      await store.flush();

      this.config = config;
      this.authState.isLoggedIn = !!config.serverUrl;
      this.authState.username = config.serverUrl;

      this.log('配置保存成功');
      return true;
    } catch (error) {
      this.logError('保存配置失败', String(error));
      return false;
    }
  }

  /**
   * 获取当前配置
   */
  public getConfig(): SuwayomiConfig {
    const result: SuwayomiConfig = {
      serverUrl: this.config.serverUrl,
      username: this.config.username,
      password: this.config.password,
      useAuth: this.config.useAuth,
      useBrowsePageAsEntry: this.config.useBrowsePageAsEntry ?? false
    };
    return result;
  }

  /**
   * 测试服务器连接
   */
  public async testConnection(): Promise<boolean> {
    try {
      if (!this.config.serverUrl) {
        return false;
      }

      // 使用简单的 introspection 查询测试连接
      const query = `query { __typename }`;
      const response = await this.executeGraphQL(query);
      return !!response;
    } catch (error) {
      this.logError('连接测试失败', String(error));
      return false;
    }
  }

  /**
   * 执行 GraphQL 查询
   */
  private async executeGraphQL(query: string, variables?: SourceSearchVariables | MangaIdVariables | MangaIdNumberVariables | ChapterUpdateVariables | SearchQueryVariables): Promise<GraphQLData | null> {
    if (!this.config.serverUrl) {
      this.logError('服务器地址未配置');
      return null;
    }

    try {
      const httpRequest = http.createHttp();
      const url = `${this.config.serverUrl}/api/graphql`;

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      };

      // 添加基本认证
      if (this.config.useAuth && this.config.username) {
        const credentials = `${this.config.username}:${this.config.password}`;
        const base64Credentials = this.base64Encode(credentials);
        headers['Authorization'] = `Basic ${base64Credentials}`;
      }

      const body = JSON.stringify({ query, variables });

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 30000
      });

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const responseText = response.result as string;
        this.log(`GraphQL 响应: ${responseText.substring(0, 200)}`);
        const result = JSON.parse(responseText) as GraphQLResponse;
        if (result.errors && result.errors.length > 0) {
          const errorMsg = result.errors[0].message;
          this.logError(`GraphQL 错误: ${errorMsg}`);
          return null;
        }
        return result.data || null;
      } else {
        this.logError(`HTTP 错误: ${response.responseCode}, 响应: ${String(response.result).substring(0, 200)}`);
        return null;
      }
    } catch (error) {
      this.logError('GraphQL 请求失败', String(error));
      return null;
    }
  }

  /**
   * Base64 编码
   */
  private base64Encode(str: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    while (i < str.length) {
      const a = str.charCodeAt(i++);
      const b = i < str.length ? str.charCodeAt(i++) : 0;
      const c = i < str.length ? str.charCodeAt(i++) : 0;
      const triplet = (a << 16) | (b << 8) | c;
      result += chars.charAt((triplet >> 18) & 0x3F);
      result += chars.charAt((triplet >> 12) & 0x3F);
      result += i > str.length + 1 ? '=' : chars.charAt((triplet >> 6) & 0x3F);
      result += i > str.length ? '=' : chars.charAt(triplet & 0x3F);
    }
    return result;
  }

  // ==================== 图源模式 API ====================

  /**
   * 获取所有源
   */
  public async getSources(): Promise<SuwayomiSource[]> {
    const query = `
      query {
        sources {
          nodes {
            id
            name
            lang
            iconUrl
            isNsfw
          }
        }
      }
    `;
    const data = await this.executeGraphQL(query);
    return data?.sources || [];
  }

  /**
   * 搜索漫画
   */
  public async searchManga(sourceId: string, searchQuery: string): Promise<SuwayomiManga[]> {
    const query = `
      query SearchManga($sourceId: LongString!, $query: String!) {
        fetchSourceManga(sourceId: $sourceId, type: SEARCH, query: $query) {
          mangas {
            id
            title
            thumbnailUrl
            url
            author
            artist
            description
            genre
            status
            inLibrary
          }
        }
      }
    `;
    const variables: SourceSearchVariables = { sourceId, query: searchQuery };
    const data = await this.executeGraphQL(query, variables);
    return data?.searchManga?.nodes || [];
  }

  /**
   * 获取漫画详情
   */
  public async getMangaDetails(mangaId: number): Promise<SuwayomiManga | null> {
    const query = `
      query GetManga($id: Int!) {
        manga(id: $id) {
          id
          title
          thumbnailUrl
          url
          author
          artist
          description
          genre
          status
          inLibrary
          lastChapterRead {
            chapterNumber
          }
          chapters {
            totalCount
          }
        }
      }
    `;
    const variables: MangaIdVariables = { id: mangaId };
    const data = await this.executeGraphQL(query, variables);
    return data?.manga || null;
  }

  /**
   * 获取章节列表
   */
  public async getChapters(mangaId: number): Promise<SuwayomiChapter[]> {
    const query = `
      query GetChapters($mangaId: Int!) {
        chapters(condition: { mangaId: $mangaId }, orderBy: SOURCE_ORDER) {
          nodes {
            id
            name
            chapterNumber
            isRead
            isDownloaded
            pageCount
            uploadDate
            url
          }
        }
      }
    `;
    const variables: MangaIdNumberVariables = { mangaId };
    const data = await this.executeGraphQL(query, variables);
    return data?.chapters?.nodes || [];
  }

  /**
   * 获取章节页面
   */
  public async getChapterPages(chapterId: number): Promise<string[]> {
    const query = `
      query GetChapterPages($id: Int!) {
        chapter(id: $id) {
          pageCount
        }
      }
    `;
    const chapterVariables: MangaIdVariables = { id: chapterId };
    const data = await this.executeGraphQL(query, chapterVariables);
    const pageCount = (data as Record<string, Record<string, number>>)?.chapter?.pageCount || 0;

    // 生成页面 URL 列表
    const pages: string[] = [];
    for (let i = 0; i < pageCount; i++) {
      pages.push(`${this.config.serverUrl}/api/v1/manga/chapter/${chapterId}/page/${i}`);
    }
    return pages;
  }

  /**
   * 标记章节为已读
   */
  public async markChapterRead(chapterId: number, isRead: boolean = true): Promise<boolean> {
    const mutation = `
      mutation UpdateChapter($id: Int!, $isRead: Boolean!) {
        updateChapter(input: { id: $id, patch: { isRead: $isRead } }) {
          chapter {
            id
            isRead
          }
        }
      }
    `;
    const updateVariables: ChapterUpdateVariables = { id: chapterId, isRead };
    const data = await this.executeGraphQL(mutation, updateVariables);
    return !!data;
  }

  /**
   * 更新阅读进度
   */
  public async updateReadProgress(mangaId: number, chapterNumber: number): Promise<boolean> {
    // 获取章节列表找到对应章节
    const chapters = await this.getChapters(mangaId);
    const targetChapter = chapters.find(ch => ch.chapterNumber <= chapterNumber);

    if (targetChapter) {
      return await this.markChapterRead(targetChapter.id, true);
    }
    return false;
  }

  // ==================== BaseTracker 抽象方法实现 ====================

  /**
   * 搜索（用于跟踪绑定）
   */
  public async search(query: string): Promise<TrackSearchResult[]> {
    // 从库中搜索
    const graphqlQuery = `
      query SearchLibrary($query: String!) {
        mangas(condition: { inLibrary: true }, filter: { title: { includesInsensitive: $query } }) {
          nodes {
            id
            title
            thumbnailUrl
            url
          }
        }
      }
    `;
    const searchVariables: SearchQueryVariables = { query };
    const data = await this.executeGraphQL(graphqlQuery, searchVariables);
    const mangas = data?.mangas?.nodes || [];

    const results: TrackSearchResult[] = [];
    for (let i = 0; i < mangas.length; i++) {
      const manga = mangas[i];
      const result: TrackSearchResult = {
        remoteId: String(manga.id),
        title: manga.title,
        coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
        summary: '',
        publishingType: '',
        startDate: '',
        status: 'unknown',
        totalChapters: 0,
        trackingUrl: `${this.config.serverUrl}/manga/${manga.id}`
      };
      results.push(result);
    }
    return results;
  }

  /**
   * 绑定跟踪
   */
  public async bind(trackRecord: TrackRecord): Promise<boolean> {
    if (!trackRecord.remoteId) {
      return false;
    }
    const mangaId = parseInt(trackRecord.remoteId);
    const manga = await this.getMangaDetails(mangaId);
    return !!manga;
  }

  /**
   * 更新远程进度
   */
  public async updateRemoteProgress(trackRecord: TrackRecord): Promise<boolean> {
    if (!trackRecord.remoteId) {
      return false;
    }

    const mangaId = parseInt(trackRecord.remoteId);
    return await this.updateReadProgress(mangaId, trackRecord.lastChapterRead);
  }

  /**
   * 获取远程进度
   */
  public async getRemoteProgress(remoteId: string): Promise<UpdateTrackRecordParams | null> {
    const mangaId = parseInt(remoteId);
    const manga = await this.getMangaDetails(mangaId);

    if (!manga) {
      return null;
    }

    const params: UpdateTrackRecordParams = {
      lastChapterRead: manga.lastChapterRead || 0,
      totalChapters: manga.totalChapters || 0
    };
    return params;
  }

  /**
   * 获取登录URL（Suwayomi不使用OAuth）
   */
  public getLoginUrl(): string {
    return '';
  }

  /**
   * 处理OAuth回调（Suwayomi不使用OAuth）
   */
  public async handleAuthCallback(code: string): Promise<boolean> {
    return false;
  }

  /**
   * 刷新访问令牌（Suwayomi不使用OAuth）
   */
  public async refreshAccessToken(): Promise<boolean> {
    return true;
  }

  /**
   * 保存认证状态
   */
  protected async saveAuthState(): Promise<void> {
    // Suwayomi使用saveConfig保存配置
  }

  /**
   * 加载认证状态
   */
  protected async loadAuthState(): Promise<void> {
    await this.loadConfig();
  }

  /**
   * 登出
   */
  public async logout(): Promise<void> {
    const emptyConfig: SuwayomiConfig = {
      serverUrl: '',
      username: '',
      password: '',
      useAuth: false
    };
    await this.saveConfig(emptyConfig);
    this.authState.isLoggedIn = false;
    this.authState.username = '';
    this.log('已登出');
  }

  /**
   * 获取 WebUI URL
   */
  public getWebUIUrl(): string {
    return this.config.serverUrl || '';
  }
}
