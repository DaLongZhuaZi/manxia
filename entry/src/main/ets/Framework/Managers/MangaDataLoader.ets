/**
 * 漫画数据加载策略管理器
 * 实现"优先使用缓存，按需请求"的策略
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { 
  Manga, 
  OnlineManga, 
  Chapter, 
  OnlineChapter, 
  PageInfo,
  isOnlineManga,
  isOnlineChapter,
  hasLocalImage,
  OnlineChapterDownloadStatus
} from 'manxia_core/src/main/ets/Framework/Types/MangaTypes';
import { MangaTypeAdapter } from '../Adapters/MangaTypeAdapter';

const TAG = 'MangaDataLoader';

/**
 * 漫画详情加载结果
 */
export interface MangaDetailLoadResult {
  /** 漫画信息 */
  manga: Manga;
  
  /** 章节列表 */
  chapters: Chapter[];
  
  /** 数据来源 */
  dataSource: 'cache' | 'network';
  
  /** 是否需要刷新 */
  needsRefresh: boolean;
}

/**
 * 章节页面加载结果
 */
export interface ChapterPagesLoadResult {
  /** 页面列表 */
  pages: PageInfo[];
  
  /** 数据来源 */
  dataSource: 'cache' | 'network';
}

/**
 * 漫画数据加载器
 *
 * @deprecated 当前主在线链路已迁移到图源引擎和详情页专用加载流程。本类仅保留旧调用兼容，
 * 不再直接发起 WebView 网络刷新。
 */
export class MangaDataLoader {
  private static instance: MangaDataLoader;
  private dataManager: DataManager;
  
  /** 缓存过期时间（毫秒）：24小时 */
  private readonly CACHE_EXPIRE_TIME = 24 * 60 * 60 * 1000;
  
  private constructor() {
    this.dataManager = DataManager.getInstance();
  }
  
  public static getInstance(): MangaDataLoader {
    if (!MangaDataLoader.instance) {
      MangaDataLoader.instance = new MangaDataLoader();
    }
    return MangaDataLoader.instance;
  }
  
  /**
   * 加载漫画详情和章节列表
   * 策略：
   * 1. 优先从数据库加载
   * 2. 如果是在线漫画且缓存过期或为空，则从网络加载
   * 3. 如果用户手动刷新，强制从网络加载
   */
  async loadMangaDetail(
    mangaId: string,
    forceRefresh: boolean = false
  ): Promise<MangaDetailLoadResult> {
    logger.info(TAG, `加载漫画详情: mangaId=${mangaId}, forceRefresh=${forceRefresh}`);
    
    try {
      // 1. 从数据库加载漫画信息
      const legacyManga = await this.dataManager.getComicById(mangaId);
      if (!legacyManga) {
        throw new Error(`漫画不存在: ${mangaId}`);
      }
      
      // 获取图源名称（如果是在线漫画）
      let sourceName: string | undefined;
      if (legacyManga.sourceId) {
        const sourceIdNum = typeof legacyManga.sourceId === 'string' 
          ? parseInt(legacyManga.sourceId) 
          : legacyManga.sourceId;
        const name = await this.getSourceNameById(sourceIdNum);
        sourceName = name || undefined;
      }
      
      // 转换为新类型
      const manga = MangaTypeAdapter.convertToManga(legacyManga as any, sourceName || undefined);
      
      // 2. 从数据库加载章节列表
      const legacyChapters = await this.dataManager.getChaptersByMangaId(mangaId);
      const cachedChapters = MangaTypeAdapter.convertToChapters(legacyChapters as any[]);
      
      // 3. 判断是否需要从网络加载
      const needsNetworkLoad = this.shouldLoadFromNetwork(manga, cachedChapters, forceRefresh);
      
      if (needsNetworkLoad && isOnlineManga(manga)) {
        logger.info(TAG, `从网络加载在线漫画数据: ${manga.title}`);
        return await this.loadOnlineMangaFromNetwork(manga, cachedChapters);
      } else {
        logger.info(TAG, `使用缓存数据: ${manga.title}`);
        return {
          manga,
          chapters: cachedChapters,
          dataSource: 'cache',
          needsRefresh: needsNetworkLoad // 如果应该刷新但没有刷新，标记为需要刷新
        };
      }
    } catch (error) {
      logger.error(TAG, `加载漫画详情失败: ${error}`);
      throw error;
    }
  }
  
  /**
   * 判断是否需要从网络加载
   */
  private shouldLoadFromNetwork(
    manga: Manga,
    cachedChapters: Chapter[],
    forceRefresh: boolean
  ): boolean {
    // 强制刷新
    if (forceRefresh) {
      logger.debug(TAG, '用户手动刷新，需要从网络加载');
      return true;
    }
    
    // 本地漫画不需要网络加载
    if (!isOnlineManga(manga)) {
      logger.debug(TAG, '本地漫画，不需要网络加载');
      return false;
    }
    
    // 没有缓存的章节数据
    if (!cachedChapters || cachedChapters.length === 0) {
      logger.debug(TAG, '没有缓存章节，需要从网络加载');
      return true;
    }
    
    // 检查缓存是否过期
    const now = Date.now();
    const lastSyncTime = manga.lastSyncTime || 0;
    const cacheAge = now - lastSyncTime;
    
    if (cacheAge > this.CACHE_EXPIRE_TIME) {
      logger.debug(TAG, `缓存已过期（${Math.floor(cacheAge / 1000 / 60)}分钟），需要从网络加载`);
      return true;
    }
    
    logger.debug(TAG, `缓存未过期（${Math.floor(cacheAge / 1000 / 60)}分钟），使用缓存`);
    return false;
  }
  
  /**
   * 从网络加载在线漫画数据
   */
  private async loadOnlineMangaFromNetwork(
    manga: OnlineManga,
    cachedChapters: Chapter[]
  ): Promise<MangaDetailLoadResult> {
    try {
      logger.warn(TAG, '旧 MangaDataLoader 不再直接接入 WebView 图源刷新，返回缓存并标记需要刷新');
      return {
        manga,
        chapters: cachedChapters,
        dataSource: 'cache',
        needsRefresh: true
      };
    } catch (error) {
      logger.error(TAG, `从网络加载失败，回退到缓存: ${error}`);
      return {
        manga,
        chapters: cachedChapters,
        dataSource: 'cache',
        needsRefresh: true
      };
    }
  }
  
  /**
   * 加载章节的页面列表
   * 策略：
   * 1. 优先从数据库加载
   * 2. 如果是在线章节且未下载，从网络加载
   * 3. 如果是在线章节且已下载，使用本地文件
   */
  async loadChapterPages(
    chapterId: string,
    manga: Manga
  ): Promise<ChapterPagesLoadResult> {
    logger.info(TAG, `加载章节页面: chapterId=${chapterId}`);
    
    try {
      // 1. 从数据库加载章节信息
      const legacyChapter = await this.dataManager.getChapterById(chapterId);
      if (!legacyChapter) {
        throw new Error(`章节不存在: ${chapterId}`);
      }
      
      // 转换为新类型
      const chapter = MangaTypeAdapter.convertToChapter(legacyChapter as any);
      
      // 2. 从数据库加载页面列表
      const legacyPages = await this.dataManager.getPagesByChapterId(chapterId);
      const cachedPages = MangaTypeAdapter.convertToPages(legacyPages as any[]);
      
      // 3. 判断数据来源
      if (isOnlineChapter(chapter)) {
        return await this.loadOnlineChapterPages(chapter, manga as OnlineManga, cachedPages);
      } else {
        // 本地章节，直接使用缓存
        logger.info(TAG, `本地章节，使用缓存数据: ${cachedPages.length}页`);
        return {
          pages: cachedPages,
          dataSource: 'cache'
        };
      }
    } catch (error) {
      logger.error(TAG, `加载章节页面失败: ${error}`);
      throw error;
    }
  }
  
  /**
   * 加载在线章节的页面
   */
  private async loadOnlineChapterPages(
    chapter: OnlineChapter,
    manga: OnlineManga,
    cachedPages: PageInfo[]
  ): Promise<ChapterPagesLoadResult> {
    // 如果章节已下载，使用本地文件
    if (chapter.downloadStatus === OnlineChapterDownloadStatus.DOWNLOADED) {
      logger.info(TAG, `章节已下载，使用本地文件: ${cachedPages.length}页`);
      
      // 验证缓存页面是否都有本地路径
      const allHaveLocalPath = cachedPages.every(page => hasLocalImage(page));
      if (allHaveLocalPath) {
        return {
          pages: cachedPages,
          dataSource: 'cache'
        };
      } else {
        logger.warn(TAG, '章节标记为已下载，但部分页面缺少本地路径');
      }
    }
    
    // 检查缓存是否有效（有imageUrl）
    const cacheHasUrls = cachedPages.length > 0 && cachedPages.every(page => !!page.imageUrl);
    if (cacheHasUrls) {
      logger.info(TAG, `使用缓存的页面URL: ${cachedPages.length}页`);
      return {
        pages: cachedPages,
        dataSource: 'cache'
      };
    }
    
    // 需要从网络加载
    logger.info(TAG, `从网络加载章节页面: ${chapter.title}`);
    return await this.loadOnlineChapterPagesFromNetwork(chapter, manga, cachedPages);
  }
  
  /**
   * 从网络加载在线章节页面
   */
  private async loadOnlineChapterPagesFromNetwork(
    chapter: OnlineChapter,
    manga: OnlineManga,
    cachedPages: PageInfo[]
  ): Promise<ChapterPagesLoadResult> {
    try {
      logger.warn(TAG, '旧 MangaDataLoader 不再直接接入 WebView 页面刷新，返回缓存页面');
      return {
        pages: cachedPages,
        dataSource: 'cache'
      };
    } catch (error) {
      logger.error(TAG, `从网络加载章节页面失败，回退到缓存: ${error}`);
      return {
        pages: cachedPages,
        dataSource: 'cache'
      };
    }
  }
  
  /**
   * 根据图源名称获取图源ID
   */
  async getSourceIdByName(sourceName: string): Promise<number | null> {
    try {
      const sources = await this.dataManager.getAllComicSources();
      const source = sources.find(s => {
        const name = s.name;
        return typeof name === 'string' && name === sourceName;
      });
      if (source && source.id !== undefined) {
        return typeof source.id === 'number' ? source.id : parseInt(String(source.id));
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源ID失败: ${error}`);
      return null;
    }
  }
  
  /**
   * 根据图源ID获取图源名称
   */
  async getSourceNameById(sourceId: number): Promise<string | null> {
    try {
      const source = await this.dataManager.getComicSourceById(sourceId);
      if (source && source.name) {
        return typeof source.name === 'string' ? source.name : String(source.name);
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源名称失败: ${error}`);
      return null;
    }
  }
}
