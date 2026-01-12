/**
 * Suwayomi 图源
 * 将 Suwayomi 服务器作为漫画源使用
 * 通过 GraphQL API 获取漫画列表、详情和章节
 */

import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';
import { ComicInfo, ChapterInfo, PageInfo, ComicDetailInfo } from './SourceExecutor';

const TAG = 'SuwayomiSource';

// Suwayomi 配置接口
export interface SuwayomiSourceConfig {
  serverUrl: string;
  username: string;
  password: string;
  useAuth: boolean;
}

// Suwayomi 漫画信息
interface SuwayomiManga {
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
}

// Suwayomi 章节信息
interface SuwayomiChapter {
  id: number;
  name: string;
  chapterNumber: number;
  isRead: boolean;
  isDownloaded: boolean;
  pageCount: number;
  uploadDate: number;
  url: string;
  lastPageRead: number;  // 最后阅读的页码
}

// Suwayomi 源信息
interface SuwayomiSourceInfo {
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

interface GraphQLError {
  message: string;
}

// GraphQL 数据接口
interface GraphQLData {
  sources?: GraphQLSourcesConnection;
  mangas?: GraphQLMangasConnection;
  manga?: SuwayomiMangaDetail;
  chapter?: GraphQLChapter;
  fetchSourceManga?: GraphQLFetchSourceManga;
  fetchChapterPages?: GraphQLFetchChapterPages;
  updateManga?: GraphQLUpdateManga;
  updateChapter?: GraphQLUpdateChapter;
  categories?: GraphQLCategoriesConnection;
  category?: GraphQLCategoryWithMangas;
}

interface GraphQLFetchChapterPages {
  pages: string[];
}

interface GraphQLCategoriesConnection {
  nodes: GraphQLCategory[];
}

interface GraphQLCategory {
  id: number;
  name: string;
  order: number;
  mangas?: GraphQLMangaCount;
}

interface GraphQLMangaCount {
  totalCount: number;
}

interface GraphQLSourcesConnection {
  nodes: SuwayomiSourceInfo[];
}

interface GraphQLMangasConnection {
  nodes: SuwayomiManga[];
}

interface GraphQLMangasConnectionWithCount extends GraphQLMangasConnection {
  totalCount: number;
}

interface PaginationVariables {
  offset: number;
  limit: number;
}

interface CategoryPaginationVariables {
  categoryId: number;
  offset: number;
  limit: number;
}

interface GraphQLCategoryWithMangas {
  mangas?: GraphQLMangasConnectionWithCount;
}

interface GraphQLCategoryWithFullMangas {
  id: number;
  name: string;
  mangas?: GraphQLMangasConnection;
}

interface GraphQLFetchSourceManga {
  mangas: SuwayomiManga[];
  hasNextPage: boolean;
}

interface GraphQLChapter {
  pageCount: number;
  lastPageRead?: number;
}

interface GraphQLUpdateManga {
  manga: SuwayomiManga;
}

interface GraphQLUpdateChapter {
  chapter: SuwayomiChapter;
}

interface SuwayomiMangaDetail extends SuwayomiManga {
  chapters?: GraphQLChaptersConnection;
}

interface GraphQLChaptersConnection {
  nodes: SuwayomiChapter[];
}

// GraphQL 变量接口
interface SearchVariables {
  source: string;
  query: string;
}

interface MangaIdVariables {
  id: number;
}

interface ChapterIdVariables {
  id: number;
}

interface BrowseVariables {
  source: string;
  type: string;
  page: number;
}

interface UpdateChapterVariables {
  id: number;
  isRead?: boolean;
  lastPageRead?: number;
}

interface QueryVariables {
  query: string;
}

interface UpdateMangaVariables {
  id: number;
}

interface CategoryVariables {
  categoryId: number;
  offset: number;
  limit: number;
}

// 漫画排序类型
export type MangaSortType = 'ID' | 'TITLE' | 'LAST_FETCHED_AT' | 'IN_LIBRARY_AT' | 'UNREAD_COUNT' | 'LAST_READ_AT';
export type SortDirection = 'ASC' | 'DESC';

export interface MangaSortOption {
  type: MangaSortType;
  direction: SortDirection;
  label: string;
}

// 预定义排序选项
export const MANGA_SORT_OPTIONS: MangaSortOption[] = [
  { type: 'TITLE', direction: 'ASC', label: '标题 A-Z' },
  { type: 'TITLE', direction: 'DESC', label: '标题 Z-A' },
  { type: 'LAST_READ_AT', direction: 'DESC', label: '最近阅读' },
  { type: 'LAST_FETCHED_AT', direction: 'DESC', label: '最近更新' },
  { type: 'IN_LIBRARY_AT', direction: 'DESC', label: '最近添加' },
  { type: 'IN_LIBRARY_AT', direction: 'ASC', label: '最早添加' },
  { type: 'UNREAD_COUNT', direction: 'DESC', label: '未读最多' },
  { type: 'UNREAD_COUNT', direction: 'ASC', label: '未读最少' },
];

// Suwayomi 分类信息
export interface SuwayomiCategory {
  id: number;
  name: string;
  order: number;
  mangaCount: number;
}

// 分页结果
export interface PaginatedResult<T> {
  items: T[];
  totalCount: number;
  hasMore: boolean;
}

/**
 * Suwayomi 图源类
 */
export class SuwayomiSource {
  private static instance: SuwayomiSource | null = null;
  private config: SuwayomiSourceConfig = {
    serverUrl: '',
    username: '',
    password: '',
    useAuth: false
  };
  private isInitialized: boolean = false;

  private constructor() {}

  public static getInstance(): SuwayomiSource {
    if (!SuwayomiSource.instance) {
      SuwayomiSource.instance = new SuwayomiSource();
    }
    return SuwayomiSource.instance;
  }

  /**
   * 初始化
   */
  public async initialize(): Promise<void> {
    if (this.isInitialized) {
      return;
    }
    await this.loadConfig();
    this.isInitialized = true;
    logger.info(TAG, '初始化完成');
  }

  /**
   * 加载配置
   * 优先从 SuwayomiTracker 的配置中读取，以保持一致性
   */
  private async loadConfig(): Promise<void> {
    try {
      // 从 SuwayomiTracker 的配置中读取（使用同步方法保持一致）
      const store = preferences.getPreferencesSync(getContext(), { name: 'suwayomi_config' });
      const serverUrl = store.getSync('serverUrl', '') as string;
      const username = store.getSync('username', '') as string;
      const password = store.getSync('password', '') as string;
      const useAuth = store.getSync('useAuth', false) as boolean;

      this.config = {
        serverUrl: serverUrl,
        username: username,
        password: password,
        useAuth: useAuth
      };
      logger.debug(TAG, `配置加载完成: ${this.config.serverUrl}`);
    } catch (error) {
      logger.error(TAG, `加载配置失败: ${error}`);
    }
  }

  /**
   * 保存配置
   */
  public async saveConfig(config: SuwayomiSourceConfig): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), 'suwayomi_source_config');
      await store.put('serverUrl', config.serverUrl);
      await store.put('username', config.username);
      await store.put('password', config.password);
      await store.put('useAuth', config.useAuth);
      await store.flush();
      this.config = config;
      logger.info(TAG, '配置保存成功');
    } catch (error) {
      logger.error(TAG, `保存配置失败: ${error}`);
    }
  }

  /**
   * 获取配置
   */
  public getConfig(): SuwayomiSourceConfig {
    return {
      serverUrl: this.config.serverUrl,
      username: this.config.username,
      password: this.config.password,
      useAuth: this.config.useAuth
    };
  }

  /**
   * 检查是否已配置
   */
  public isConfigured(): boolean {
    return !!this.config.serverUrl;
  }

  /**
   * 执行 GraphQL 查询
   */
  private async executeGraphQL(query: string, variables?: Object): Promise<GraphQLData | null> {
    if (!this.config.serverUrl) {
      logger.error(TAG, '服务器地址未配置');
      return null;
    }

    try {
      const url = `${this.config.serverUrl}/api/graphql`;
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      };

      // 添加认证头
      if (this.config.useAuth && this.config.username && this.config.password) {
        const credentials = `${this.config.username}:${this.config.password}`;
        const encoded = this.base64Encode(credentials);
        headers['Authorization'] = `Basic ${encoded}`;
      }

      // 构建请求体
      let bodyStr: string;
      if (variables) {
        bodyStr = JSON.stringify({ query: query, variables: variables });
      } else {
        bodyStr = JSON.stringify({ query: query });
      }

      const request = http.createHttp();
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyStr,
        connectTimeout: 30000,
        readTimeout: 30000
      });

      request.destroy();

      if (response.responseCode !== 200) {
        logger.error(TAG, `GraphQL 请求失败: ${response.responseCode}`);
        return null;
      }

      const result: GraphQLResponse = JSON.parse(response.result as string);
      if (result.errors && result.errors.length > 0) {
        logger.error(TAG, `GraphQL 错误: ${result.errors[0].message}`);
        return null;
      }

      return result.data || null;
    } catch (error) {
      logger.error(TAG, `GraphQL 请求异常: ${error}`);
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

  // ==================== 图源 API ====================

  /**
   * 获取所有 Suwayomi 源
   */
  public async getSources(): Promise<SuwayomiSourceInfo[]> {
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
    const sources = data?.sources?.nodes as SuwayomiSourceInfo[] | undefined;
    return sources || [];
  }

  /**
   * 获取所有分类
   */
  public async getCategories(): Promise<SuwayomiCategory[]> {
    const query = `
      query {
        categories {
          nodes {
            id
            name
            order
            mangas {
              totalCount
            }
          }
        }
      }
    `;
    const data = await this.executeGraphQL(query);
    const categories: GraphQLCategory[] | undefined = data?.categories?.nodes;
    if (!categories) {
      return [];
    }

    return categories.map((cat: GraphQLCategory): SuwayomiCategory => ({
      id: cat.id,
      name: cat.name,
      order: cat.order,
      mangaCount: cat.mangas?.totalCount || 0
    }));
  }

  /**
   * 获取指定分类的所有漫画
   * 通过 category(id) 查询获取特定分类的漫画列表
   */
  public async getCategoryMangas(categoryId: number): Promise<ComicInfo[]> {
    const query = `
      query GetCategoryMangas($id: Int!) {
        category(id: $id) {
          id
          name
          mangas {
            nodes {
              id
              title
              thumbnailUrl
              author
              artist
              description
              genre
              status
            }
          }
        }
      }
    `;
    const variables: MangaIdVariables = { id: categoryId };
    const data = await this.executeGraphQL(query, variables);
    const rawCategory: ESObject = data?.category;
    if (!rawCategory) {
      logger.warn(TAG, `分类 ${categoryId} 查询返回空`);
      return [];
    }
    const mangasConnection: ESObject = rawCategory.mangas;
    const mangas: SuwayomiManga[] | undefined = mangasConnection?.nodes as SuwayomiManga[] | undefined;

    if (!mangas) {
      logger.warn(TAG, `分类 ${categoryId} 没有漫画或查询失败`);
      return [];
    }

    logger.info(TAG, `分类 ${categoryId} 获取到 ${mangas.length} 本漫画`);
    return mangas.map((manga: SuwayomiManga): ComicInfo => ({
      id: String(manga.id),
      title: manga.title,
      author: manga.author || manga.artist,
      coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
      description: manga.description,
      status: manga.status,
      tags: manga.genre,
      url: `${this.config.serverUrl}/manga/${manga.id}`
    }));
  }

  /**
   * 获取指定分类的漫画并排序
   */
  private async getCategoryMangasSorted(categoryId: number, sortType: MangaSortType, sortDirection: SortDirection): Promise<ComicInfo[]> {
    const mangas = await this.getCategoryMangas(categoryId);
    return this.sortMangas(mangas, sortType, sortDirection);
  }

  /**
   * 构建 GraphQL orderBy 字段
   * Suwayomi 使用格式: FIELD_ASC 或 FIELD_DESC
   * 有效值参考: ID, TITLE, IN_LIBRARY_AT, LAST_FETCHED_AT 等
   */
  private buildOrderByField(sortType: MangaSortType, sortDirection: SortDirection): string {
    // Suwayomi MangaOrderBy 枚举格式
    // 注意：需要根据实际 API 支持的值调整
    switch (sortType) {
      case 'TITLE':
        return sortDirection === 'ASC' ? 'TITLE_ASC' : 'TITLE_DESC';
      case 'LAST_FETCHED_AT':
        return sortDirection === 'ASC' ? 'LAST_FETCHED_AT_ASC' : 'LAST_FETCHED_AT_DESC';
      case 'IN_LIBRARY_AT':
        return sortDirection === 'ASC' ? 'IN_LIBRARY_AT_ASC' : 'IN_LIBRARY_AT_DESC';
      case 'UNREAD_COUNT':
        return sortDirection === 'ASC' ? 'UNREAD_COUNT_ASC' : 'UNREAD_COUNT_DESC';
      case 'LAST_READ_AT':
        return sortDirection === 'ASC' ? 'LAST_READ_AT_ASC' : 'LAST_READ_AT_DESC';
      default:
        return sortDirection === 'ASC' ? 'ID_ASC' : 'ID_DESC';
    }
  }

  /**
   * 本地排序漫画列表
   */
  private sortMangas(mangas: ComicInfo[], sortType: MangaSortType, sortDirection: SortDirection): ComicInfo[] {
    const sorted = [...mangas];
    const multiplier = sortDirection === 'ASC' ? 1 : -1;

    sorted.sort((a: ComicInfo, b: ComicInfo): number => {
      switch (sortType) {
        case 'TITLE':
          return multiplier * a.title.localeCompare(b.title);
        default:
          return multiplier * a.title.localeCompare(b.title);
      }
    });

    return sorted;
  }

  /**
   * 获取库中的漫画列表（分页+排序）
   * @param categoryId 分类ID，-1表示所有，>=0表示特定分类
   * @param offset 偏移量
   * @param limit 每页数量
   * @param sortType 排序类型
   * @param sortDirection 排序方向
   */
  public async getLibraryMangasPaginated(
    categoryId: number = -1,
    offset: number = 0,
    limit: number = 50,
    sortType: MangaSortType = 'TITLE',
    sortDirection: SortDirection = 'ASC'
  ): Promise<PaginatedResult<ComicInfo>> {
    // 如果指定了分类，使用 getCategoryMangas 获取该分类的所有漫画，然后手动分页和排序
    if (categoryId >= 0) {
      const allMangas = await this.getCategoryMangasSorted(categoryId, sortType, sortDirection);
      const totalCount = allMangas.length;
      const items = allMangas.slice(offset, offset + limit);
      return {
        items: items,
        totalCount: totalCount,
        hasMore: offset + items.length < totalCount
      };
    }

    // 获取所有库中的漫画，然后本地排序和分页
    // 注意：Suwayomi GraphQL API 的 orderBy 枚举值可能因版本不同而不同
    // 为了兼容性，我们先获取数据再本地排序
    const allMangas = await this.getAllLibraryMangas();
    const sortedMangas = this.sortMangas(allMangas, sortType, sortDirection);
    const totalCount = sortedMangas.length;
    const items = sortedMangas.slice(offset, offset + limit);

    return {
      items: items,
      totalCount: totalCount,
      hasMore: offset + items.length < totalCount
    };
  }

  /**
   * 获取所有库中的漫画（不分页，用于本地排序）
   */
  private async getAllLibraryMangas(): Promise<ComicInfo[]> {
    // 分批获取所有漫画
    const batchSize = 100;
    let offset = 0;
    let allMangas: ComicInfo[] = [];
    let hasMore = true;

    while (hasMore) {
      const query = `
        query GetLibraryMangas($offset: Int!, $limit: Int!) {
          mangas(condition: { inLibrary: true }, offset: $offset, first: $limit) {
            totalCount
            nodes {
              id
              title
              thumbnailUrl
              author
              artist
              description
              genre
              status
            }
          }
        }
      `;
      const variables: PaginationVariables = { offset: offset, limit: batchSize };
      const data = await this.executeGraphQL(query, variables);

      const mangasData: GraphQLMangasConnectionWithCount | undefined = data?.mangas as GraphQLMangasConnectionWithCount | undefined;
      const totalCount: number = mangasData?.totalCount || 0;
      const mangas: SuwayomiManga[] | undefined = mangasData?.nodes;

      if (!mangas || mangas.length === 0) {
        hasMore = false;
        break;
      }

      const items = mangas.map((manga: SuwayomiManga): ComicInfo => ({
        id: String(manga.id),
        title: manga.title,
        author: manga.author || manga.artist,
        coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
        description: manga.description,
        status: manga.status,
        tags: manga.genre,
        url: `${this.config.serverUrl}/manga/${manga.id}`
      }));

      allMangas = allMangas.concat(items);
      offset += mangas.length;
      hasMore = offset < totalCount;

      // 安全限制：最多获取5000本漫画
      if (allMangas.length >= 5000) {
        logger.warn(TAG, `达到最大获取限制 5000 本，停止获取`);
        break;
      }
    }

    logger.info(TAG, `获取所有库漫画完成: ${allMangas.length} 本`);
    return allMangas;
  }

  /**
   * 获取库中的漫画列表（不推荐用于大型库）
   * @deprecated 使用 getLibraryMangasPaginated 代替
   */
  public async getLibraryMangas(): Promise<ComicInfo[]> {
    const result = await this.getLibraryMangasPaginated(-1, 0, 100);
    return result.items;
  }

  /**
   * 搜索漫画（从指定源）
   * 使用 mutation，input 需要 source 字段
   */
  public async searchManga(sourceId: string, searchQuery: string): Promise<ComicInfo[]> {
    const query = `
      mutation SearchManga($source: LongString!, $query: String!) {
        fetchSourceManga(input: { source: $source, type: SEARCH, query: $query }) {
          mangas {
            id
            title
            thumbnailUrl
            author
            artist
            description
            genre
            status
          }
        }
      }
    `;
    const variables: SearchVariables = { source: sourceId, query: searchQuery };
    const data = await this.executeGraphQL(query, variables);
    const mangas = data?.fetchSourceManga?.mangas as SuwayomiManga[] | undefined;
    if (!mangas) {
      return [];
    }

    return mangas.map((manga: SuwayomiManga): ComicInfo => ({
      id: String(manga.id),
      title: manga.title,
      author: manga.author || manga.artist,
      coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
      description: manga.description,
      status: manga.status,
      tags: manga.genre,
      url: `${this.config.serverUrl}/manga/${manga.id}`
    }));
  }

  /**
   * 搜索库中的漫画
   */
  public async searchLibrary(searchQuery: string): Promise<ComicInfo[]> {
    const query = `
      query SearchLibrary($query: String!) {
        mangas(condition: { inLibrary: true }, filter: { title: { includesInsensitive: $query } }) {
          nodes {
            id
            title
            thumbnailUrl
            author
            artist
            description
            genre
            status
          }
        }
      }
    `;
    const variables: QueryVariables = { query: searchQuery };
    const data = await this.executeGraphQL(query, variables);
    const mangas = data?.mangas?.nodes as SuwayomiManga[] | undefined;
    if (!mangas) {
      return [];
    }

    return mangas.map((manga: SuwayomiManga): ComicInfo => ({
      id: String(manga.id),
      title: manga.title,
      author: manga.author || manga.artist,
      coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
      description: manga.description,
      status: manga.status,
      tags: manga.genre,
      url: `${this.config.serverUrl}/manga/${manga.id}`
    }));
  }

  /**
   * 获取漫画详情
   */
  public async getMangaDetail(mangaId: string): Promise<ComicDetailInfo | null> {
    const query = `
      query GetManga($id: Int!) {
        manga(id: $id) {
          id
          title
          thumbnailUrl
          author
          artist
          description
          genre
          status
          inLibrary
          chapters {
            nodes {
              id
              name
              chapterNumber
              isRead
              isDownloaded
              uploadDate
            }
          }
        }
      }
    `;
    const variables: MangaIdVariables = { id: parseInt(mangaId) };
    const data = await this.executeGraphQL(query, variables);
    const manga: SuwayomiMangaDetail | undefined = data?.manga;
    if (!manga) {
      return null;
    }

    const chapters: SuwayomiChapter[] | undefined = manga.chapters?.nodes;
    const chapterList: ChapterInfo[] = chapters ? chapters.map((ch: SuwayomiChapter): ChapterInfo => {
      const chapterInfo: ChapterInfo = {
        id: String(ch.id),
        title: ch.name || `第 ${ch.chapterNumber} 章`,
        url: `${this.config.serverUrl}/manga/${mangaId}/chapter/${ch.id}`,
        updateTime: ch.uploadDate
      };
      // 使用 extra 字段存储额外信息
      (chapterInfo as ESObject)['isRead'] = ch.isRead;
      (chapterInfo as ESObject)['isDownloaded'] = ch.isDownloaded;
      return chapterInfo;
    }) : [];

    const result: ComicDetailInfo = {
      id: String(manga.id),
      title: manga.title,
      author: manga.author || manga.artist,
      coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
      description: manga.description,
      status: manga.status,
      tags: manga.genre,
      url: `${this.config.serverUrl}/manga/${mangaId}`,
      chapters: chapterList
    };
    // 存储 inLibrary 状态
    (result as ESObject)['inLibrary'] = manga.inLibrary;
    return result;
  }

  /**
   * 获取章节页面
   * 需要先调用 fetchChapterPages mutation 来确保页面已加载
   */
  public async getChapterPages(chapterId: string): Promise<PageInfo[]> {
    // 先调用 fetchChapterPages 确保页面已加载到服务器
    const fetchMutation = `
      mutation FetchChapterPages($id: Int!) {
        fetchChapterPages(input: { chapterId: $id }) {
          pages
        }
      }
    `;
    const fetchVariables: ChapterIdVariables = { id: parseInt(chapterId) };
    const fetchData = await this.executeGraphQL(fetchMutation, fetchVariables);
    const fetchedPages: string[] | undefined = fetchData?.fetchChapterPages?.pages;

    if (fetchedPages && fetchedPages.length > 0) {
      // 使用 mutation 返回的页面 URL
      logger.info(TAG, `获取到 ${fetchedPages.length} 个页面 URL`);
      return fetchedPages.map((pageUrl: string): PageInfo => ({
        url: pageUrl.startsWith('http') ? pageUrl : `${this.config.serverUrl}${pageUrl}`
      }));
    }

    // 如果 mutation 失败，回退到查询 pageCount 方式
    const query = `
      query GetChapterPages($id: Int!) {
        chapter(id: $id) {
          pageCount
        }
      }
    `;
    const variables: ChapterIdVariables = { id: parseInt(chapterId) };
    const data = await this.executeGraphQL(query, variables);
    const pageCount: number | undefined = data?.chapter?.pageCount;
    if (!pageCount) {
      logger.warn(TAG, `章节 ${chapterId} 没有页面`);
      return [];
    }

    const pages: PageInfo[] = [];
    for (let i = 0; i < pageCount; i++) {
      const pageUrl = `${this.config.serverUrl}/api/v1/manga/chapter/${chapterId}/page/${i}`;
      pages.push({ url: pageUrl });
    }
    logger.info(TAG, `生成 ${pages.length} 个页面 URL，示例: ${pages[0]?.url}`);
    return pages;
  }

  /**
   * 标记章节为已读
   */
  public async markChapterRead(chapterId: string, isRead: boolean = true): Promise<boolean> {
    const query = `
      mutation UpdateChapter($id: Int!, $isRead: Boolean!) {
        updateChapter(input: { id: $id, patch: { isRead: $isRead } }) {
          chapter {
            id
            isRead
          }
        }
      }
    `;
    const variables: UpdateChapterVariables = { id: parseInt(chapterId), isRead: isRead };
    const data = await this.executeGraphQL(query, variables);
    return !!data?.updateChapter?.chapter;
  }

  /**
   * 更新章节阅读进度（保存当前阅读页码）
   */
  public async updateReadingProgress(chapterId: string, lastPageRead: number): Promise<boolean> {
    const query = `
      mutation UpdateChapterProgress($id: Int!, $lastPageRead: Int!) {
        updateChapter(input: { id: $id, patch: { lastPageRead: $lastPageRead } }) {
          chapter {
            id
            lastPageRead
          }
        }
      }
    `;
    const variables: UpdateChapterVariables = { id: parseInt(chapterId), lastPageRead: lastPageRead };
    const data = await this.executeGraphQL(query, variables);
    return !!data?.updateChapter?.chapter;
  }

  /**
   * 获取章节阅读进度
   */
  public async getChapterProgress(chapterId: string): Promise<number> {
    const query = `
      query GetChapterProgress($id: Int!) {
        chapter(id: $id) {
          id
          lastPageRead
          pageCount
        }
      }
    `;
    const variables: MangaIdVariables = { id: parseInt(chapterId) };
    const data = await this.executeGraphQL(query, variables);
    return data?.chapter?.lastPageRead ?? 0;
  }

  /**
   * 获取浏览源的漫画列表（热门/最新）
   * 使用 mutation，input 需要 source 字段而不是 sourceId
   */
  public async browseSource(sourceId: string, type: 'POPULAR' | 'LATEST' = 'POPULAR', page: number = 1): Promise<ComicInfo[]> {
    const query = `
      mutation FetchSourceManga($source: LongString!, $type: FetchSourceMangaType!, $page: Int!) {
        fetchSourceManga(input: { source: $source, type: $type, page: $page }) {
          mangas {
            id
            title
            thumbnailUrl
            author
            artist
            description
            genre
            status
          }
          hasNextPage
        }
      }
    `;
    const variables: BrowseVariables = { source: sourceId, type: type, page: page };
    const data = await this.executeGraphQL(query, variables);
    const mangas = data?.fetchSourceManga?.mangas as SuwayomiManga[] | undefined;
    if (!mangas) {
      return [];
    }

    return mangas.map((manga: SuwayomiManga): ComicInfo => ({
      id: String(manga.id),
      title: manga.title,
      author: manga.author || manga.artist,
      coverUrl: manga.thumbnailUrl ? `${this.config.serverUrl}${manga.thumbnailUrl}` : '',
      description: manga.description,
      status: manga.status,
      tags: manga.genre,
      url: `${this.config.serverUrl}/manga/${manga.id}`
    }));
  }

  /**
   * 添加漫画到库
   */
  public async addToLibrary(mangaId: string): Promise<boolean> {
    const query = `
      mutation AddToLibrary($id: Int!) {
        updateManga(input: { id: $id, patch: { inLibrary: true } }) {
          manga {
            id
            inLibrary
          }
        }
      }
    `;
    const variables: UpdateMangaVariables = { id: parseInt(mangaId) };
    const data = await this.executeGraphQL(query, variables);
    return !!data?.updateManga?.manga;
  }

  /**
   * 从库中移除漫画
   */
  public async removeFromLibrary(mangaId: string): Promise<boolean> {
    const query = `
      mutation RemoveFromLibrary($id: Int!) {
        updateManga(input: { id: $id, patch: { inLibrary: false } }) {
          manga {
            id
            inLibrary
          }
        }
      }
    `;
    const variables: UpdateMangaVariables = { id: parseInt(mangaId) };
    const data = await this.executeGraphQL(query, variables);
    return !!data?.updateManga?.manga;
  }

  /**
   * 获取图片请求头（用于需要认证的图片）
   */
  public getImageHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    if (this.config.useAuth && this.config.username && this.config.password) {
      const credentials = `${this.config.username}:${this.config.password}`;
      const encoded = this.base64Encode(credentials);
      headers['Authorization'] = `Basic ${encoded}`;
    }
    return headers;
  }
}

/**
 * 获取 Suwayomi 图源实例
 */
export function getSuwayomiSource(): SuwayomiSource {
  return SuwayomiSource.getInstance();
}
