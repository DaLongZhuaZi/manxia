/**
 * 漫画详情加载器
 * 封装漫画详情页的完整加载逻辑，支持本地漫画和网络漫画
 * 
 * 文件路径: entry/src/main/ets/Framework/Loaders/MangaDetailLoader.ets
 */

import { logger } from '../../Utils/Logger';
import { SafeUtils } from '../../Utils/SafeUtils';
import {
  Manga,
  MangaChapter,
  MangaPage,
  ReadingProgress,
  ImageSourceType,
  MangaMetadata,
  MangaImageRequestHeader
} from '../../Models/MangaModels';
import { DEFAULT_READING_SETTINGS, ReadingSettings } from '../../Models/MangaModels';
import { DownloadStatus, MangaStatus, ReadingStatus } from '../Types/StatusEnums';
import { ComicConverter } from '../Utils/ComicConverter';
import { 
  DataManager, 
  ComicInfo, 
  ChapterInfo, 
  OnlineChapterInfo, 
  OnlineComicInfo,
  OnlineChapterInfoInput,
  OnlinePageInfoInput,
  OnlineComicSourceSaveInput
} from '../Data/DataManager';
import { DataService } from '../Services/DataService';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { MangaSourceEngine, EngineResult, MangaDetailWithChapters } from '../WebView/MangaSourceEngine';
import { MangaInfo, ChapterInfo as WebViewChapterInfo, PageInfo as SourcePageInfo, PageRequestHeader } from '../WebView/MangaSourceTypes';
import { WebViewDataCacheManager } from '../Cache/WebViewDataCacheManager';
import { getLegadoMangaSourceBridge, LegadoMangaDetailResult } from '../Novel/LegadoMangaSourceBridge';
import { MangaIdentityResolver, MangaIdentityResolveResult } from '../Reader/MangaIdentityResolver';
import webview from '@ohos.web.webview';

const TAG = 'MangaDetailLoader';

/**
 * 漫画详情加载参数
 */
export interface MangaDetailLoadParams {
  mangaId: string;
  sourceId?: number;
  sourceName?: string;
  sourcePkg?: string;
  cachedTitle?: string;
  cachedCover?: string;
  cachedCoverPath?: string;
  forceRefresh?: boolean;
  externalMangaId?: string;  // 外部漫画ID（用于强制刷新时从网络获取）
}

/**
 * 漫画详情加载结果
 */
export interface MangaDetailLoadResult {
  success: boolean;
  manga: Manga | null;
  chapters: MangaChapter[];
  isFavorite: boolean;
  isLocalManga: boolean;
  sourceId: number;
  sourceName: string;
  coverHttpHeaders: Record<string, string>;
  errorMessage?: string;
  chapterProgressList?: ChapterProgressInfo[];  // 章节进度列表
  lastReadChapterIndex?: number;  // 最后阅读的章节索引
  readChapterIds?: Set<string>;   // 已读章节ID集合
}

/**
 * 章节进度信息
 */
export interface ChapterProgressInfo {
  chapterId: string;
  lastReadPageIndex: number;
  totalPages: number;
  isCompleted: boolean;
  lastReadTime?: number;  // 最后阅读时间
}

/**
 * 章节进度加载结果
 */
export interface ChapterProgressLoadResult {
  progressList: ChapterProgressInfo[];
  readChapterIds: Set<string>;
  lastReadChapterIndex: number;
}

/**
 * 章节页面数量查询结果
 */
interface ChapterPageCount {
  chapterId: string;
  count: number;
}

/**
 * 分阶段加载回调接口
 * [修复] 支持异步回调（返回 void 或 Promise<void>）
 */
export interface MangaLoadProgressCallback {
  onBasicInfoLoaded?: (manga: Manga, isFavorite: boolean) => void | Promise<void>;
  onChaptersLoaded?: (chapters: MangaChapter[]) => void | Promise<void>;
  onChapterProgressLoaded?: (progressList: ChapterProgressInfo[], readChapterIds: Set<string>, lastReadChapterIndex: number) => void | Promise<void>;
  onChapterPagesLoaded?: (chapterId: string, pageCount: number) => void | Promise<void>;
  onPagesPreloadProgress?: (current: number, total: number) => void;
  onPagesPreloadComplete?: () => void;
  onError?: (error: string) => void;
}

/**
 * 漫画详情加载器类
 * 提供完整的漫画详情加载功能，包括本地漫画和网络漫画
 */
export class MangaDetailLoader {
  private static instance: MangaDetailLoader | null = null;
  
  private dataManager: DataManager = DataManager.getInstance();
  private dataService: DataService = DataService.getInstance();
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private cacheManager: WebViewDataCacheManager = WebViewDataCacheManager.getInstance();
  
  // WebView引擎（每次加载时初始化）
  private mangaEngine: MangaSourceEngine | null = null;
  private webViewController: webview.WebviewController | null = null;
  
  // 当前加载状态
  private currentSourceId: number = 0;
  private currentSourceName: string = '';
  private currentSourcePkg: string = '';
  private coverHttpHeaders: Record<string, string> = {};
  
  private constructor() {
    logger.info(TAG, '漫画详情加载器已创建');
  }
  
  /**
   * 获取单例实例
   */
  public static getInstance(): MangaDetailLoader {
    if (!MangaDetailLoader.instance) {
      MangaDetailLoader.instance = new MangaDetailLoader();
    }
    return MangaDetailLoader.instance;
  }
  
  /**
   * 设置WebView控制器（必须在加载网络漫画前调用）
   */
  public setWebViewController(controller: webview.WebviewController): void {
    this.webViewController = controller;
    logger.info(TAG, 'WebView控制器已设置');
  }
  
  /**
   * 分阶段加载漫画详情（支持回调）
   * 先返回基本信息，然后异步加载章节和页面
   */
  public async loadMangaDetailWithProgress(
    params: MangaDetailLoadParams, 
    callback: MangaLoadProgressCallback
  ): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: 0,
      sourceName: '',
      coverHttpHeaders: {}
    };
    
    try {
      logger.info(TAG, `[分阶段] 开始加载漫画详情: mangaId=${params.mangaId}, sourceId=${params.sourceId}`);
      
      // 初始化图源信息
      this.currentSourceId = params.sourceId || 0;
      this.currentSourceName = params.sourceName || '';
      this.currentSourcePkg = params.sourcePkg || '';
      this.coverHttpHeaders = {};

      let resolvedIdentity: MangaIdentityResolveResult | null = null;
      const identityInput = MangaIdentityResolver.getInstance().buildInput(
        params.mangaId,
        '',
        this.currentSourceId,
        this.currentSourceId > 0 ? 'OnlineUndownloaded' : '',
        'MangaDetailLoader.loadMangaDetailWithProgress'
      );
      identityInput.sourceName = this.currentSourceName;
      identityInput.sourcePkg = this.currentSourcePkg;
      resolvedIdentity = await MangaIdentityResolver.getInstance().resolve(identityInput);
      if (resolvedIdentity.success) {
        if (resolvedIdentity.canonicalMangaId.length > 0 && resolvedIdentity.canonicalMangaId !== params.mangaId) {
          logger.info(TAG, `[分阶段] 漫画ID已校准: ${params.mangaId} -> ${resolvedIdentity.canonicalMangaId}`);
          params.mangaId = resolvedIdentity.canonicalMangaId;
        }
        if (!params.externalMangaId && resolvedIdentity.externalMangaId.length > 0) {
          params.externalMangaId = resolvedIdentity.externalMangaId;
        }
        if (resolvedIdentity.sourceId > 0) {
          params.sourceId = resolvedIdentity.sourceId;
          this.currentSourceId = resolvedIdentity.sourceId;
        }
        if (resolvedIdentity.sourceName.length > 0) {
          this.currentSourceName = resolvedIdentity.sourceName;
        }
        if (resolvedIdentity.sourcePkg.length > 0) {
          this.currentSourcePkg = resolvedIdentity.sourcePkg;
        }
        if (resolvedIdentity.onlineComicInfo) {
          if (resolvedIdentity.onlineComicInfo.sourceName.length > 0) {
            this.currentSourceName = resolvedIdentity.onlineComicInfo.sourceName;
          }
          if (resolvedIdentity.onlineComicInfo.sourcePkg.length > 0) {
            this.currentSourcePkg = resolvedIdentity.onlineComicInfo.sourcePkg;
          }
        }
      } else {
        logger.warn(TAG, `[分阶段] 漫画身份未解析，继续原始加载: ${resolvedIdentity.detail}`);
      }

      // 第一阶段：获取基本信息
      let comicInfo = resolvedIdentity && resolvedIdentity.comicInfo
        ? resolvedIdentity.comicInfo
        : await this.dataManager.getComicById(params.mangaId);

      // Decide whether IMAGE traffic belongs to V2 before creating a visual
      // fallback. The fallback (or an entry written by an earlier legacy
      // execution) must never suppress a V2 detail/Toc workflow in full
      // cutover mode.
      const legadoMangaBridge = getLegadoMangaSourceBridge();
      const isLegadoMangaSource: boolean = this.currentSourceId > 0 &&
        await legadoMangaBridge.isLegadoMangaSourceId(this.currentSourceId);
      const shouldForceLegadoNetworkDetail: boolean = isLegadoMangaSource &&
        await legadoMangaBridge.shouldForceNetworkDetail(this.currentSourceId);
      const shouldLoadLegadoFromNetwork: boolean = isLegadoMangaSource &&
        (params.forceRefresh === true || comicInfo === null || shouldForceLegadoNetworkDetail);
      // This deliberately carries only lengths and route decisions. It makes
      // IMAGE detail dispatch auditable without persisting a book URL or title.
      logger.warn(
        TAG,
        `[Legado漫画路由] sourceId=${this.currentSourceId};mangaIdLength=${params.mangaId.length};` +
        `externalIdLength=${(params.externalMangaId || '').length};identity=${resolvedIdentity ? resolvedIdentity.reason : 'none'};` +
        `hasCache=${comicInfo !== null};isLegado=${isLegadoMangaSource};forceNetwork=${shouldForceLegadoNetworkDetail};` +
        `shouldLoadV2=${shouldLoadLegadoFromNetwork}`
      );
      if (shouldLoadLegadoFromNetwork) {
        const legadoResult = await this.loadLegadoMangaWithProgress(params, callback);
        return legadoResult;
      }

      if (comicInfo === null) {
        comicInfo = await this.tryBuildFallbackLocalComicInfo(params, '[分阶段]');
      }
      
      // [修复] 如果forceRefresh=true且有sourceId，强制从网络重新获取
      if (params.forceRefresh && params.sourceId && params.sourceId > 0) {
        logger.info(TAG, `[分阶段] forceRefresh=true，强制从网络重新获取`);
        
        // 如果没有提供externalMangaId，尝试从数据库获取
        if (!params.externalMangaId && comicInfo) {
          params.externalMangaId = comicInfo.externalId || params.mangaId;
          logger.info(TAG, `[分阶段] 从数据库获取externalMangaId: ${params.externalMangaId}`);
        }
        
        const onlineResult = await this.loadNewOnlineMangaFromNetwork(params, callback);
        return onlineResult;
      }
      
      if (comicInfo) {
        const sourceIdStr = String(comicInfo.sourceId || '');
        const isLocalSource = this.isLocalSourceId(sourceIdStr);
        
        // 构建基本Manga对象
        const basicManga = this.buildBasicMangaFromComicInfo(comicInfo, isLocalSource);
        const isFavorite = await this.checkFavoriteStatus(params.mangaId);
        
        // 回调：基本信息已加载
        if (callback.onBasicInfoLoaded) {
          await callback.onBasicInfoLoaded(basicManga, isFavorite);
        }
        
        result.manga = basicManga;
        result.isFavorite = isFavorite;
        result.isLocalManga = isLocalSource;
        result.sourceId = this.currentSourceId;
        result.sourceName = this.currentSourceName;
        
        // 第二阶段：加载章节信息
        if (isLocalSource) {
          const chapters = await this.loadLocalChapters(params.mangaId);
          result.chapters = chapters;
          result.manga.chapters = chapters;
          
          if (callback.onChaptersLoaded) {
            await callback.onChaptersLoaded(chapters);
          }
        } else {
          // 在线漫画：从数据库加载已有章节
          const chapters = await this.loadOnlineChaptersFromDatabase(params.mangaId);
          result.chapters = chapters;
          result.manga.chapters = chapters;
          
          if (callback.onChaptersLoaded) {
            await callback.onChaptersLoaded(chapters);
          }
          
          // 第三阶段：后台预加载页面信息（不阻塞）
          this.preloadChapterPagesInBackground(params.mangaId, chapters, callback);
        }
        
        result.success = true;
        result.coverHttpHeaders = this.coverHttpHeaders;
        
      } else {
        // 数据库中不存在，尝试其他方式查找
        const onlineResult = await this.loadNewOnlineMangaWithProgress(params, callback);
        return onlineResult;
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `[分阶段] 加载漫画详情失败: ${String(error)}`);
      result.errorMessage = `加载失败: ${String(error)}`;
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    }
  }
  
  /**
   * 构建基本Manga对象（不含章节）
   */
  private buildBasicMangaFromComicInfo(comicInfo: ComicInfo, isLocal: boolean): Manga {
    const metadata: MangaMetadata = {
      authors: comicInfo.author ? [comicInfo.author] : [],
      artists: [],
      genres: comicInfo.tags || [],
      themes: [],
      demographics: []
    };
    
    return {
      id: comicInfo.id,
      title: comicInfo.title,
      alternativeTitles: [],
      description: comicInfo.description || '',
      coverImagePath: comicInfo.coverUrl || '',
      coverSourceType: isLocal ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
      status: this.convertStatus(comicInfo.status as string),
      metadata: metadata,
      chapters: [],
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: 0,
        lastReadAt: Date.now(),
        readingStatus: ReadingStatus.UNREAD,
        totalReadingTime: 0,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: DEFAULT_READING_SETTINGS,
      isFavorite: false,
      lastUpdatedAt: comicInfo.lastUpdateTime || Date.now(),
      isNSFW: Boolean(comicInfo.isNSFW)
    };
  }

  private async tryBuildFallbackLocalComicInfo(
    params: MangaDetailLoadParams,
    logPrefix: string
  ): Promise<ComicInfo | null> {
    if (params.mangaId.length <= 0) {
      return null;
    }

    try {
      const chapters: ChapterInfo[] = await this.dataManager.getComicChapters(params.mangaId);
      if (chapters.length <= 0) {
        logger.warn(TAG, `${logPrefix}本地漫画兜底失败：未找到章节，mangaId=${params.mangaId}`);
        return null;
      }

      const coverPath: string = params.cachedCoverPath && params.cachedCoverPath.length > 0
        ? params.cachedCoverPath
        : (params.cachedCover || '');
      const now: number = Date.now();
      const fallback: ComicInfo = {
        id: params.mangaId,
        title: params.cachedTitle && params.cachedTitle.length > 0 ? params.cachedTitle : params.mangaId,
        author: '',
        description: '',
        coverUrl: coverPath,
        coverLocalPath: coverPath.length > 0 ? coverPath : undefined,
        sourceId: 'local_import',
        status: MangaStatus.UNKNOWN,
        tags: [],
        rating: 0,
        chapterCount: chapters.length,
        lastUpdateTime: now,
        addTime: now,
        contentType: 'manga',
        isNSFW: false,
        isPrivate: false
      };
      logger.warn(TAG, `${logPrefix}已启用本地漫画详情兜底: mangaId=${params.mangaId}, chapters=${chapters.length}`);
      return fallback;
    } catch (error) {
      logger.warn(TAG, `${logPrefix}本地漫画详情兜底异常: mangaId=${params.mangaId}, ${String(error)}`);
      return null;
    }
  }
  
  /**
   * 检查收藏状态
   */
  private async checkFavoriteStatus(mangaId: string): Promise<boolean> {
    try {
      return await this.dataService.isFavorited(mangaId);
    } catch (error) {
      logger.warn(TAG, `获取收藏状态失败: ${String(error)}`);
      return false;
    }
  }
  
  /**
   * 加载本地章节
   */
  private async loadLocalChapters(mangaId: string): Promise<MangaChapter[]> {
    const localChapters = await this.dataManager.getComicChapters(mangaId);
    return localChapters.map((ch: ChapterInfo, index: number): MangaChapter => ({
      id: ch.id,
      title: ch.title,
      chapterNumber: ch.index || index,
      pages: [],
      publishDate: ch.publishTime || Date.now(),
      language: '',
      scanlationGroup: '',
      isDownloaded: ch.isDownloaded || false,
      downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
      downloadProgress: ch.isDownloaded ? 100 : 0
    }));
  }
  
  /**
   * 从数据库加载在线章节
   */
  private async loadOnlineChaptersFromDatabase(mangaId: string): Promise<MangaChapter[]> {
    const onlineChapters = await this.dataManager.getOnlineComicChapters(mangaId);
    return onlineChapters.map((ch: OnlineChapterInfo, index: number): MangaChapter => ({
      id: ch.id,
      title: ch.title,
      chapterNumber: ch.index || ch.chapterNumber || index,
      pages: [],
      publishDate: ch.publishTime || ch.addTime || Date.now(),
      language: '',
      scanlationGroup: '',
      isDownloaded: ch.isDownloaded || false,
      downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
      downloadProgress: ch.isDownloaded ? 100 : 0,
      externalId: ch.externalId
    }));
  }
  
  /**
   * 后台预加载章节页面信息
   */
  private async preloadChapterPagesInBackground(
    mangaId: string, 
    chapters: MangaChapter[], 
    callback: MangaLoadProgressCallback
  ): Promise<void> {
    // 异步执行，不阻塞主流程
    setTimeout(async () => {
      try {
        logger.info(TAG, `[后台] 开始预加载 ${chapters.length} 个章节的页面信息`);
        
        let loadedCount = 0;
        const totalChapters = chapters.length;
        
        for (const chapter of chapters) {
          // 检查章节是否已有页面数据
          const existingPages = await this.dataManager.getOnlineChapterPages(chapter.id);
          if (existingPages && existingPages.length > 0) {
            loadedCount++;
            if (callback.onChapterPagesLoaded) {
              callback.onChapterPagesLoaded(chapter.id, existingPages.length);
            }
            continue;
          }
          
          // 需要从网络获取页面信息
          if (this.mangaEngine && chapter.externalId) {
            try {
              const pageListResult = await this.mangaEngine.getPageList(chapter.externalId, mangaId);
              if (pageListResult.success && pageListResult.data) {
                const pageInfos = pageListResult.data;
                
                // 保存页面信息到数据库
                for (let j = 0; j < pageInfos.length; j++) {
                  const pageInfo = pageInfos[j];
                  const onlinePageInput: OnlinePageInfoInput = {
                    chapterId: chapter.id,
                    pageNumber: j,
                    imageUrl: pageInfo.imageUrl,
                    requestHeaders: this.serializePageRequestHeaders(pageInfo.requestHeaders),
                    width: pageInfo.width || 0,
                    height: pageInfo.height || 0,
                    fileSize: 0
                  };
                  await this.dataManager.addOnlinePageInfo(onlinePageInput);
                }
                
                if (callback.onChapterPagesLoaded) {
                  callback.onChapterPagesLoaded(chapter.id, pageInfos.length);
                }
              }
            } catch (error) {
              logger.warn(TAG, `[后台] 获取章节 "${chapter.title}" 页面失败: ${String(error)}`);
            }
          }
          
          loadedCount++;
          if (callback.onPagesPreloadProgress) {
            callback.onPagesPreloadProgress(loadedCount, totalChapters);
          }
        }
        
        if (callback.onPagesPreloadComplete) {
          callback.onPagesPreloadComplete();
        }
        
        logger.info(TAG, `[后台] 页面预加载完成`);
      } catch (error) {
        logger.error(TAG, `[后台] 页面预加载失败: ${String(error)}`);
      }
    }, 100);
  }
  
  /**
   * 加载全新网络漫画（带进度回调）
   */
  private async loadNewOnlineMangaWithProgress(
    params: MangaDetailLoadParams,
    callback: MangaLoadProgressCallback
  ): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: this.currentSourceId,
      sourceName: this.currentSourceName,
      coverHttpHeaders: {}
    };
    
    try {
      // 尝试通过externalId查找
      const comicByExternalRecord = await this.dataManager.getComicByExternalId(params.mangaId);
      if (comicByExternalRecord) {
        const recordObj: ESObject = comicByExternalRecord as ESObject;
        const comicInfo: ComicInfo = {
          id: String(recordObj.id || ''),
          title: String(recordObj.title || ''),
          author: String(recordObj.author || ''),
          description: String(recordObj.description || ''),
          coverUrl: String(recordObj.coverUrl || ''),
          sourceId: String(recordObj.sourceId || ''),
          status: recordObj.status as MangaStatus || MangaStatus.UNKNOWN,
          tags: Array.isArray(recordObj.tags) ? recordObj.tags as string[] : [],
          rating: Number(recordObj.rating || 0),
          chapterCount: Number(recordObj.chapterCount || 0),
          lastUpdateTime: Number(recordObj.lastUpdateTime || Date.now()),
          addTime: Number(recordObj.addTime || Date.now()),
          externalId: String(recordObj.externalId || ''),
          isNSFW: Boolean(recordObj.isNSFW)
        };
        
        const basicManga = this.buildBasicMangaFromComicInfo(comicInfo, false);
        const isFavorite = await this.checkFavoriteStatus(comicInfo.id);
        
        if (callback.onBasicInfoLoaded) {
          await callback.onBasicInfoLoaded(basicManga, isFavorite);
        }
        
        const chapters = await this.loadOnlineChaptersFromDatabase(comicInfo.id);
        result.chapters = chapters;
        basicManga.chapters = chapters;
        
        if (callback.onChaptersLoaded) {
          await callback.onChaptersLoaded(chapters);
        }
        
        result.success = true;
        result.manga = basicManga;
        result.isFavorite = isFavorite;
        
        this.preloadChapterPagesInBackground(comicInfo.id, chapters, callback);
        
        return result;
      }
      
      // 尝试从online_comic_info表查找
      const onlineComic = await this.dataManager.getOnlineComicByExternalId(params.mangaId);
      if (onlineComic) {
        return await this.loadOnlineMangaFromInfoWithProgress(onlineComic, params, callback);
      }
      
      // 全新的网络漫画，需要从网络加载
      if (params.sourceId && params.sourceId > 0) {
        return await this.loadNewOnlineMangaFromNetwork(params, callback);
      }
      
      result.errorMessage = '漫画不存在';
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    } catch (error) {
      result.errorMessage = `加载失败: ${String(error)}`;
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    }
  }
  
  /**
   * 从OnlineComicInfo加载（带进度回调）
   */
  private async loadOnlineMangaFromInfoWithProgress(
    onlineComic: OnlineComicInfo,
    params: MangaDetailLoadParams,
    callback: MangaLoadProgressCallback
  ): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: this.currentSourceId,
      sourceName: this.currentSourceName,
      coverHttpHeaders: {}
    };
    
    try {
      const chapters = await this.loadOnlineChaptersFromDatabase(onlineComic.id);
      const basicManga = await this.buildMangaFromOnlineComicInfo(onlineComic, chapters);
      const isFavorite = await this.checkFavoriteStatus(onlineComic.id);
      
      if (callback.onBasicInfoLoaded) {
        await callback.onBasicInfoLoaded(basicManga, isFavorite);
      }
      
      result.chapters = chapters;
      basicManga.chapters = chapters;
      
      if (callback.onChaptersLoaded) {
        await callback.onChaptersLoaded(chapters);
      }
      
      result.success = true;
      result.manga = basicManga;
      result.isFavorite = isFavorite;
      
      this.preloadChapterPagesInBackground(onlineComic.id, chapters, callback);
      
      return result;
    } catch (error) {
      result.errorMessage = `加载失败: ${String(error)}`;
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    }
  }
  
  /**
   * 从网络加载全新漫画（带进度回调）
   */
  private async loadNewOnlineMangaFromNetwork(
    params: MangaDetailLoadParams,
    callback: MangaLoadProgressCallback
  ): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: this.currentSourceId,
      sourceName: this.currentSourceName,
      coverHttpHeaders: {}
    };
    
    try {
      // 初始化图源信息
      if (!this.currentSourceName) {
        await this.loadSourceName(this.currentSourceId);
      }
      
      if (!this.currentSourceName) {
        result.errorMessage = '图源名称为空，无法加载网络漫画';
        if (callback.onError) {
          callback.onError(result.errorMessage);
        }
        return result;
      }
      
      result.sourceName = this.currentSourceName;
      
      // 初始化MangaEngine
      logger.info(TAG, `[网络加载] 初始化MangaEngine: sourceName="${this.currentSourceName}", sourceId=${this.currentSourceId}`);
      this.mangaEngine = await this.webViewManager.getMangaEngine(
        this.currentSourceId,
        this.currentSourceName,
        this.currentSourcePkg
      );
      
      if (!this.mangaEngine) {
        result.errorMessage = '无法初始化漫画引擎';
        if (callback.onError) {
          callback.onError(result.errorMessage);
        }
        return result;
      }
      
      // 从网络获取漫画详情和章节
      // 优先使用externalMangaId，否则使用mangaId
      const externalMangaId = params.externalMangaId || params.mangaId;
      logger.info(TAG, `[网络加载] 获取漫画详情: ${externalMangaId}`);
      
      const combinedResult = await this.mangaEngine.getMangaDetailWithChapters(externalMangaId);
      if (!combinedResult.success || !combinedResult.data) {
        result.errorMessage = combinedResult.error || '获取漫画详情失败';
        if (callback.onError) {
          callback.onError(result.errorMessage);
        }
        return result;
      }
      
      const mangaInfo: MangaInfo = combinedResult.data.detail;
      let webViewChapters: WebViewChapterInfo[] = combinedResult.data.chapters;
      if (webViewChapters.length === 0) {
        logger.warn(TAG, `[网络加载] 合并工作流未返回章节，回退独立章节工作流: ${externalMangaId}`);
        const chapterListResult = await this.mangaEngine.getChapterList(externalMangaId);
        if (chapterListResult.success && chapterListResult.data) {
          webViewChapters = chapterListResult.data;
          logger.info(TAG, `[网络加载] 独立章节工作流回退成功: ${webViewChapters.length}章`);
        } else {
          logger.warn(TAG, `[网络加载] 独立章节工作流回退失败: ${chapterListResult.error || ''}`);
        }
      }
      
      // 使用缓存的标题和封面（如果网络获取的为空）
      if ((!mangaInfo.title || mangaInfo.title.trim() === '') && params.cachedTitle) {
        mangaInfo.title = params.cachedTitle;
      }
      if (params.cachedCoverPath && params.cachedCoverPath.trim() !== '') {
        mangaInfo.cover = params.cachedCoverPath;
      } else if ((!mangaInfo.cover || mangaInfo.cover.trim() === '') && params.cachedCover) {
        mangaInfo.cover = params.cachedCover;
      }
      
      // 转换章节
      const chapters = this.convertWebViewChaptersToMangaChapters(webViewChapters);
      
      // 构建基本Manga对象
      const basicManga = this.buildMangaFromMangaInfo(mangaInfo, chapters, externalMangaId);
      
      // [修复] 先同步保存漫画和章节到数据库，确保manga.id和chapter.id被正确更新
      // 这样回调时UI可以使用正确的ID进行后续操作（如阅读）
      await this.saveOnlineMangaToDatabaseFast(basicManga, chapters, externalMangaId);
      logger.info(TAG, `[网络加载] 漫画已保存到数据库，内部ID: ${basicManga.id}`);
      
      // 检查收藏状态（使用更新后的内部ID）
      logger.debug(TAG, `[网络加载] 准备检查收藏状态: mangaId=${basicManga.id}`);
      const isFavorite = await this.checkFavoriteStatus(basicManga.id);
      result.isFavorite = isFavorite;
      logger.debug(TAG, `[网络加载] 收藏状态检查完成: isFavorite=${isFavorite}`);
      
      // 回调：基本信息已加载（manga.id已经是正确的内部ID）
      if (callback.onBasicInfoLoaded) {
        try {
          logger.debug(TAG, `[网络加载] 准备调用 onBasicInfoLoaded 回调`);
          await callback.onBasicInfoLoaded(basicManga, isFavorite);
          logger.debug(TAG, `[网络加载] onBasicInfoLoaded 回调执行完成`);
        } catch (callbackError) {
          logger.error(TAG, `[网络加载] onBasicInfoLoaded 回调抛出异常: ${String(callbackError)}`);
          throw callbackError as Error;
        }
      }
      
      // 回调：章节已加载（chapter.id已经是正确的内部ID）
      // [修复] 使用 await 等待异步回调完成，确保章节进度数据加载和UI更新完成
      if (callback.onChaptersLoaded) {
        try {
          logger.debug(TAG, `[网络加载] 准备调用 onChaptersLoaded 回调, 章节数: ${chapters.length}`);
          await callback.onChaptersLoaded(chapters);
          logger.debug(TAG, `[网络加载] onChaptersLoaded 回调执行完成`);
        } catch (callbackError) {
          logger.error(TAG, `[网络加载] onChaptersLoaded 回调抛出异常: ${String(callbackError)}`);
          throw callbackError as Error;
        }
      }
      
      // 异步预加载页面（不阻塞UI）
      this.preloadChapterPagesInBackground(basicManga.id, chapters, callback);
      
      result.success = true;
      result.manga = basicManga;
      result.chapters = chapters;
      result.coverHttpHeaders = this.coverHttpHeaders;
      
      logger.info(TAG, `[网络加载] 漫画加载成功: ${basicManga.title}, ${chapters.length}章`);
      return result;
    } catch (error) {
      result.errorMessage = `加载失败: ${String(error)}`;
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    }
  }

  private async loadLegadoMangaWithProgress(
    params: MangaDetailLoadParams,
    callback: MangaLoadProgressCallback
  ): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: this.currentSourceId,
      sourceName: this.currentSourceName,
      coverHttpHeaders: {}
    };

    try {
      const externalMangaId = params.externalMangaId || params.mangaId;
      logger.warn(
        TAG,
        `[Legado漫画路由] V2详情桥接调用: sourceId=${this.currentSourceId};` +
        `externalIdLength=${externalMangaId.length};cachedTitle=${(params.cachedTitle || '').length > 0};` +
        `cachedCover=${(params.cachedCover || params.cachedCoverPath || '').length > 0}`
      );
      const bridgeResult: LegadoMangaDetailResult | null =
        await getLegadoMangaSourceBridge().loadDetailWithChapters(
          this.currentSourceId,
          externalMangaId,
          params.cachedTitle,
          params.cachedCover || params.cachedCoverPath
        );

      if (!bridgeResult) {
        logger.warn(TAG, `[Legado漫画路由] V2详情桥接返回空: sourceId=${this.currentSourceId}`);
        result.errorMessage = 'Legado漫画桥接加载失败';
        if (callback.onError) {
          callback.onError(result.errorMessage);
        }
        return result;
      }

      this.currentSourceName = bridgeResult.sourceName;
      this.currentSourcePkg = bridgeResult.sourcePkg;
      result.sourceName = bridgeResult.sourceName;
      result.manga = bridgeResult.manga;
      result.chapters = bridgeResult.chapters;
      result.manga.chapters = bridgeResult.chapters;
      this.coverHttpHeaders = this.buildLegadoCoverHeaderMap(bridgeResult);
      result.coverHttpHeaders = this.coverHttpHeaders;
      result.isFavorite = await this.checkFavoriteStatus(bridgeResult.manga.id);
      result.success = true;

      logger.warn(
        TAG,
        `[Legado漫画路由] V2详情桥接成功: sourceId=${this.currentSourceId};` +
        `titleLength=${bridgeResult.manga.title.length};` +
        `authorLength=${bridgeResult.manga.metadata && bridgeResult.manga.metadata.authors.length > 0 ? bridgeResult.manga.metadata.authors[0].length : 0};` +
        `chapterCount=${bridgeResult.chapters.length}`
      );

      if (callback.onBasicInfoLoaded) {
        await callback.onBasicInfoLoaded(bridgeResult.manga, result.isFavorite);
      }
      if (callback.onChaptersLoaded) {
        await callback.onChaptersLoaded(bridgeResult.chapters);
      }

      logger.info(TAG, `[Legado漫画] 详情加载完成: ${bridgeResult.manga.title}, chapters=${bridgeResult.chapters.length}`);
      return result;
    } catch (error) {
      result.errorMessage = `Legado漫画加载失败: ${String(error)}`;
      logger.error(TAG, result.errorMessage);
      if (callback.onError) {
        callback.onError(result.errorMessage);
      }
      return result;
    }
  }

  private buildLegadoCoverHeaderMap(bridgeResult: LegadoMangaDetailResult): Record<string, string> {
    const coverUrl = bridgeResult.manga.coverImagePath || '';
    const mangaExternalId = bridgeResult.manga.sourceInfo && bridgeResult.manga.sourceInfo.externalId ?
      bridgeResult.manga.sourceInfo.externalId : bridgeResult.manga.id;
    if (coverUrl.length <= 0) {
      return {};
    }
    const headers = getLegadoMangaSourceBridge().buildImageRequestHeaders({
      source: bridgeResult.source,
      pageUrl: coverUrl,
      chapterUrl: mangaExternalId
    });
    return this.convertMangaHeadersToRecord(headers);
  }

  private convertMangaHeadersToRecord(headers: MangaImageRequestHeader[]): Record<string, string> {
    const result: Record<string, string> = {};
    for (let i = 0; i < headers.length; i++) {
      const header = headers[i];
      const key = header.name.trim();
      const value = header.value.trim();
      if (key.length > 0 && value.length > 0) {
        result[key] = value;
      }
    }
    return result;
  }
  
  /**
   * 异步保存漫画到数据库（不阻塞UI）
   * [修复] 先快速保存基本信息，不预取页面，让UI立即响应
   */
  private async saveOnlineMangaToDatabaseAsync(
    manga: Manga,
    chapters: MangaChapter[],
    externalId: string,
    callback: MangaLoadProgressCallback
  ): Promise<void> {
    setTimeout(async () => {
      try {
        // 快速保存漫画和章节基本信息（不预取页面）
        await this.saveOnlineMangaToDatabaseFast(manga, chapters, externalId);
        
        // 保存完成后，开始后台预加载页面
        this.preloadChapterPagesInBackground(manga.id, chapters, callback);
      } catch (error) {
        logger.error(TAG, `[异步] 保存漫画到数据库失败: ${String(error)}`);
      }
    }, 100);
  }
  
  /**
   * 快速保存在线漫画到数据库（不预取页面信息）
   * 用于首次加载时快速响应UI
   */
  private async saveOnlineMangaToDatabaseFast(manga: Manga, chapters: MangaChapter[], externalId: string): Promise<void> {
    try {
      // 获取作者信息
      let authorStr = '';
      if (manga.metadata && manga.metadata.authors && manga.metadata.authors.length > 0) {
        authorStr = manga.metadata.authors[0];
      }
      
      // 保存漫画信息到online_comic_info表
      const comicData: OnlineComicSourceSaveInput = {
        id: externalId,
        title: manga.title,
        author: authorStr,
        description: manga.description || '',
        coverUrl: manga.coverImagePath || '',
        tags: manga.metadata.genres || [],
        rating: 0,
        updateTime: Date.now(),
        sourceName: this.currentSourceName
      };
      
      const internalComicId = await this.dataManager.saveComicFromSource(this.currentSourceId, comicData, externalId);
      logger.info(TAG, `[快速保存] 漫画信息已保存: ${manga.title}, 内部ID: ${internalComicId}`);
      
      // 更新manga的ID为内部ID
      manga.id = internalComicId;
      
      // 快速保存章节信息（不获取页面）
      for (let i = 0; i < chapters.length; i++) {
        const ch = chapters[i];
        const chapterExternalId = ch.externalId || ch.id;
        
        const chapterInput: OnlineChapterInfoInput = {
          comicId: internalComicId,
          externalId: chapterExternalId,
          title: ch.title,
          chapterNumber: ch.chapterNumber || i,
          url: '',
          pageCount: 0,  // 页面数稍后预取
          publishTime: typeof ch.publishDate === 'number' ? ch.publishDate : Date.now(),
          isDownloaded: false,
          downloadPath: undefined,
          index: ch.chapterNumber || i
        };
        
        const chapterId = await this.dataManager.addOnlineChapterInfo(chapterInput);
        ch.id = chapterId;
      }
      
      logger.info(TAG, `[快速保存] 章节信息已保存: ${chapters.length}章`);
    } catch (error) {
      logger.error(TAG, `[快速保存] 保存漫画到数据库失败: ${String(error)}`);
    }
  }
  
  /**
   * 加载漫画详情（主入口）
   */
  public async loadMangaDetail(params: MangaDetailLoadParams): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: 0,
      sourceName: '',
      coverHttpHeaders: {}
    };
    
    try {
      logger.info(TAG, `开始加载漫画详情: mangaId=${params.mangaId}, sourceId=${params.sourceId}`);
      
      // 初始化图源信息
      this.currentSourceId = params.sourceId || 0;
      this.currentSourceName = params.sourceName || '';
      this.currentSourcePkg = params.sourcePkg || '';
      this.coverHttpHeaders = {};

      let resolvedIdentity: MangaIdentityResolveResult | null = null;
      const identityInput = MangaIdentityResolver.getInstance().buildInput(
        params.mangaId,
        '',
        this.currentSourceId,
        this.currentSourceId > 0 ? 'OnlineUndownloaded' : '',
        'MangaDetailLoader.loadMangaDetail'
      );
      identityInput.sourceName = this.currentSourceName;
      identityInput.sourcePkg = this.currentSourcePkg;
      resolvedIdentity = await MangaIdentityResolver.getInstance().resolve(identityInput);
      if (resolvedIdentity.success) {
        if (resolvedIdentity.canonicalMangaId.length > 0 && resolvedIdentity.canonicalMangaId !== params.mangaId) {
          logger.info(TAG, `漫画ID已校准: ${params.mangaId} -> ${resolvedIdentity.canonicalMangaId}`);
          params.mangaId = resolvedIdentity.canonicalMangaId;
        }
        if (!params.externalMangaId && resolvedIdentity.externalMangaId.length > 0) {
          params.externalMangaId = resolvedIdentity.externalMangaId;
        }
        if (resolvedIdentity.sourceId > 0) {
          params.sourceId = resolvedIdentity.sourceId;
          this.currentSourceId = resolvedIdentity.sourceId;
        }
        if (resolvedIdentity.sourceName.length > 0) {
          this.currentSourceName = resolvedIdentity.sourceName;
        }
        if (resolvedIdentity.sourcePkg.length > 0) {
          this.currentSourcePkg = resolvedIdentity.sourcePkg;
        }
      } else {
        logger.warn(TAG, `漫画身份未解析，继续原始加载: ${resolvedIdentity.detail}`);
      }
      
      // 判断是本地漫画还是网络漫画
      let comicInfo = resolvedIdentity && resolvedIdentity.comicInfo
        ? resolvedIdentity.comicInfo
        : await this.dataManager.getComicById(params.mangaId);
      if (comicInfo === null) {
        comicInfo = await this.tryBuildFallbackLocalComicInfo(params, '');
      }
      
      if (comicInfo) {
        // 数据库中存在，判断类型
        const sourceIdStr = String(comicInfo.sourceId || '');
        const isLocalSource = this.isLocalSourceId(sourceIdStr);
        
        if (isLocalSource) {
          // 本地漫画
          logger.info(TAG, `加载本地漫画: ${comicInfo.title}`);
          return await this.loadLocalManga(comicInfo, params);
        } else {
          // 在线漫画（已存在于数据库）
          logger.info(TAG, `加载已存在的在线漫画: ${comicInfo.title}`);
          return await this.loadExistingOnlineManga(comicInfo, params);
        }
      } else {
        // 数据库中不存在，尝试通过externalId查找
        const comicByExternalRecord = await this.dataManager.getComicByExternalId(params.mangaId);
        if (comicByExternalRecord) {
          // 将DatabaseRecord转换为ComicInfo
          const recordObj: ESObject = comicByExternalRecord as ESObject;
          const comicByExternal: ComicInfo = {
            id: String(recordObj.id || ''),
            title: String(recordObj.title || ''),
            author: String(recordObj.author || ''),
            description: String(recordObj.description || ''),
            coverUrl: String(recordObj.coverUrl || ''),
            sourceId: String(recordObj.sourceId || ''),
            status: recordObj.status as MangaStatus || MangaStatus.UNKNOWN,
            tags: Array.isArray(recordObj.tags) ? recordObj.tags as string[] : [],
            rating: Number(recordObj.rating || 0),
            chapterCount: Number(recordObj.chapterCount || 0),
            lastUpdateTime: Number(recordObj.lastUpdateTime || Date.now()),
            addTime: Number(recordObj.addTime || Date.now()),
            externalId: String(recordObj.externalId || ''),
            isNSFW: Boolean(recordObj.isNSFW)
          };
          logger.info(TAG, `通过externalId找到漫画: ${comicByExternal.title}`);
          return await this.loadExistingOnlineManga(comicByExternal, params);
        }
        
        // 尝试从online_comic_info表查找
        const onlineComic = await this.dataManager.getOnlineComicByExternalId(params.mangaId);
        if (onlineComic) {
          logger.info(TAG, `从online_comic_info找到漫画: ${onlineComic.title}`);
          return await this.loadOnlineMangaFromInfo(onlineComic, params);
        }
        
        // 全新的网络漫画，需要从网络加载
        if (params.sourceId && params.sourceId > 0) {
          logger.info(TAG, `加载全新的网络漫画: ${params.mangaId}`);
          return await this.loadNewOnlineManga(params);
        } else {
          result.errorMessage = '漫画不存在';
          return result;
        }
      }
    } catch (error) {
      logger.error(TAG, `加载漫画详情失败: ${String(error)}`);
      result.errorMessage = `加载失败: ${String(error)}`;
      return result;
    }
  }
  
  /**
   * 判断是否为本地图源ID
   */
  private isLocalSourceId(sourceId: string): boolean {
    return sourceId === 'local_import' || 
           sourceId === 'local_pdf' || 
           sourceId === 'download_import' || 
           sourceId === '0' || 
           sourceId === '';
  }
  
  /**
   * 加载本地漫画
   */
  private async loadLocalManga(comicInfo: ComicInfo, params: MangaDetailLoadParams): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: true,
      sourceId: 0,
      sourceName: '本地导入',
      coverHttpHeaders: {}
    };
    
    try {
      // 获取章节列表
      const chapters = await this.dataManager.getComicChapters(comicInfo.id);
      logger.info(TAG, `本地漫画章节数: ${chapters.length}`);
      
      // 转换为MangaChapter格式
      const mangaChapters = await this.convertLocalChaptersToMangaChapters(chapters);
      
      // 获取收藏状态
      result.isFavorite = await this.dataService.isFavorited(comicInfo.id);
      
      // 构建Manga对象
      result.manga = await this.buildMangaFromComicInfo(comicInfo, mangaChapters);
      result.chapters = mangaChapters;
      result.success = true;
      
      logger.info(TAG, `本地漫画加载完成: ${comicInfo.title}`);
      return result;
    } catch (error) {
      logger.error(TAG, `加载本地漫画失败: ${String(error)}`);
      result.errorMessage = String(error);
      return result;
    }
  }
  
  /**
   * 加载已存在的在线漫画（从数据库）
   */
  private async loadExistingOnlineManga(comicInfo: ComicInfo, params: MangaDetailLoadParams): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: Number(comicInfo.sourceId) || 0,
      sourceName: '',
      coverHttpHeaders: {}
    };
    
    try {
      // 设置图源信息
      this.currentSourceId = result.sourceId;
      await this.loadSourceName(result.sourceId);
      result.sourceName = this.currentSourceName;
      
      // 获取章节列表（从online_chapter表）
      const onlineChapters = await this.dataManager.getOnlineComicChapters(comicInfo.id);
      logger.info(TAG, `在线漫画章节数: ${onlineChapters.length}`);
      
      // 转换为MangaChapter格式
      const mangaChapters = await this.convertOnlineChaptersToMangaChapters(onlineChapters);
      
      // 获取收藏状态
      result.isFavorite = await this.dataService.isFavorited(comicInfo.id);
      
      // 构建Manga对象
      result.manga = await this.buildMangaFromComicInfo(comicInfo, mangaChapters);
      if (result.manga) {
        result.manga.sourceInfo = {
          sourceId: String(result.sourceId),
          sourceName: result.sourceName,
          sourcePkg: this.currentSourcePkg || undefined,
          sourceUrl: comicInfo.externalId || '',
          sourceLanguage: 'zh',
          requiresLogin: false
        };
      }
      result.chapters = mangaChapters;
      result.coverHttpHeaders = this.coverHttpHeaders;
      result.success = true;
      
      // 如果需要刷新，尝试从网络更新
      if (params.forceRefresh) {
        await this.refreshOnlineMangaFromNetwork(comicInfo, result);
      }
      
      logger.info(TAG, `在线漫画加载完成: ${comicInfo.title}`);
      return result;
    } catch (error) {
      logger.error(TAG, `加载在线漫画失败: ${String(error)}`);
      result.errorMessage = String(error);
      return result;
    }
  }
  
  /**
   * 从OnlineComicInfo加载漫画
   */
  private async loadOnlineMangaFromInfo(onlineComic: OnlineComicInfo, params: MangaDetailLoadParams): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: Number(onlineComic.sourceId) || 0,
      sourceName: onlineComic.sourceName || '',
      coverHttpHeaders: {}
    };
    
    try {
      // 设置图源信息
      this.currentSourceId = result.sourceId;
      this.currentSourcePkg = onlineComic.sourcePkg || this.currentSourcePkg;
      if (!result.sourceName) {
        await this.loadSourceName(result.sourceId);
        result.sourceName = this.currentSourceName;
      } else {
        this.currentSourceName = result.sourceName;
      }
      
      // 获取章节列表
      const onlineChapters = await this.dataManager.getOnlineComicChapters(onlineComic.id);
      logger.info(TAG, `在线漫画章节数: ${onlineChapters.length}`);
      
      // 转换为MangaChapter格式
      const mangaChapters = await this.convertOnlineChaptersToMangaChapters(onlineChapters);
      
      // 获取收藏状态
      result.isFavorite = await this.dataService.isFavorited(onlineComic.id);
      
      // 构建Manga对象
      result.manga = await this.buildMangaFromOnlineComicInfo(onlineComic, mangaChapters);
      result.chapters = mangaChapters;
      result.coverHttpHeaders = this.coverHttpHeaders;
      result.success = true;
      
      logger.info(TAG, `在线漫画加载完成: ${onlineComic.title}`);
      return result;
    } catch (error) {
      logger.error(TAG, `加载在线漫画失败: ${String(error)}`);
      result.errorMessage = String(error);
      return result;
    }
  }
  
  /**
   * 加载全新的网络漫画（从网络获取）
   */
  private async loadNewOnlineManga(params: MangaDetailLoadParams): Promise<MangaDetailLoadResult> {
    const result: MangaDetailLoadResult = {
      success: false,
      manga: null,
      chapters: [],
      isFavorite: false,
      isLocalManga: false,
      sourceId: params.sourceId || 0,
      sourceName: params.sourceName || '',
      coverHttpHeaders: {}
    };
    
    try {
      // 初始化图源信息
      this.currentSourceId = result.sourceId;
      if (!result.sourceName) {
        await this.loadSourceName(result.sourceId);
        result.sourceName = this.currentSourceName;
      } else {
        this.currentSourceName = result.sourceName;
      }
      
      // 初始化MangaEngine
      if (!this.currentSourceName) {
        result.errorMessage = '图源名称为空，无法加载网络漫画';
        return result;
      }
      
      logger.info(TAG, `初始化MangaEngine: sourceName="${this.currentSourceName}", sourceId=${this.currentSourceId}`);
      this.mangaEngine = await this.webViewManager.getMangaEngine(
        this.currentSourceId,
        this.currentSourceName,
        this.currentSourcePkg
      );
      
      if (!this.mangaEngine) {
        result.errorMessage = '无法初始化漫画引擎';
        return result;
      }
      
      // 从网络获取漫画详情和章节
      const externalMangaId = params.mangaId;
      
      // 尝试从缓存获取
      let mangaInfo = this.cacheManager.getMangaDetail(this.currentSourceId, externalMangaId);
      let chapters = this.cacheManager.getChapterList(this.currentSourceId, externalMangaId);
      
      if (!mangaInfo || !chapters) {
        // 使用合并工作流获取详情和章节
        logger.info(TAG, '从网络获取漫画详情和章节');
        const combinedResult = await this.mangaEngine.getMangaDetailWithChapters(externalMangaId);
        
        if (!combinedResult.success || !combinedResult.data) {
          result.errorMessage = combinedResult.error || '获取漫画数据失败';
          return result;
        }
        
        mangaInfo = combinedResult.data.detail;
        chapters = combinedResult.data.chapters;
        
        if (mangaInfo && chapters) {
          // 缓存数据
          this.cacheManager.setMangaDetail(this.currentSourceId, externalMangaId, mangaInfo);
          this.cacheManager.setChapterList(this.currentSourceId, externalMangaId, chapters);
          logger.info(TAG, `网络获取成功: ${mangaInfo.title}, ${chapters.length}章`);
        }
      }
      
      if (!mangaInfo || !chapters) {
        result.errorMessage = '漫画数据获取失败';
        return result;
      }
      
      // 使用缓存的标题和封面（如果网络获取的为空）
      if ((!mangaInfo.title || mangaInfo.title.trim() === '') && params.cachedTitle) {
        mangaInfo.title = params.cachedTitle;
      }
      if (params.cachedCoverPath && params.cachedCoverPath.trim() !== '') {
        mangaInfo.cover = params.cachedCoverPath;
      } else if ((!mangaInfo.cover || mangaInfo.cover.trim() === '') && params.cachedCover) {
        mangaInfo.cover = params.cachedCover;
      }
      
      // 转换章节
      const mangaChapters = this.convertWebViewChaptersToMangaChapters(chapters);
      
      // 构建Manga对象
      result.manga = this.buildMangaFromMangaInfo(mangaInfo, mangaChapters, externalMangaId);
      result.chapters = mangaChapters;
      result.coverHttpHeaders = this.coverHttpHeaders;
      
      // 保存到数据库
      await this.saveOnlineMangaToDatabase(result.manga, mangaChapters, externalMangaId);
      
      result.success = true;
      logger.info(TAG, `全新网络漫画加载完成: ${mangaInfo.title}`);
      return result;
    } catch (error) {
      logger.error(TAG, `加载网络漫画失败: ${String(error)}`);
      result.errorMessage = String(error);
      return result;
    }
  }
  
  /**
   * 从网络刷新在线漫画
   */
  private async refreshOnlineMangaFromNetwork(comicInfo: ComicInfo, result: MangaDetailLoadResult): Promise<void> {
    try {
      if (!this.currentSourceName || this.currentSourceId <= 0) {
        logger.warn(TAG, '无法刷新：图源信息不完整');
        return;
      }
      
      // 初始化MangaEngine
      this.mangaEngine = await this.webViewManager.getMangaEngine(
        this.currentSourceId,
        this.currentSourceName,
        this.currentSourcePkg
      );
      if (!this.mangaEngine) {
        logger.warn(TAG, '无法初始化漫画引擎');
        return;
      }
      
      const externalId = comicInfo.externalId || comicInfo.id;
      
      // 获取最新章节列表
      const chaptersResult = await this.mangaEngine.getChapterList(externalId);
      if (chaptersResult.success && chaptersResult.data && chaptersResult.data.length > 0) {
        const newChapters = chaptersResult.data;
        logger.info(TAG, `网络获取到 ${newChapters.length} 个章节`);
        
        // 更新章节到数据库
        await this.updateChaptersToDatabase(comicInfo.id, newChapters);
        
        // 重新加载章节
        const updatedChapters = await this.dataManager.getOnlineComicChapters(comicInfo.id);
        result.chapters = await this.convertOnlineChaptersToMangaChapters(updatedChapters);
        if (result.manga) {
          result.manga.chapters = result.chapters;
        }
      }
    } catch (error) {
      logger.warn(TAG, `刷新漫画失败: ${String(error)}`);
    }
  }
  
  /**
   * 加载图源名称
   * 优先使用name字段，如果为空则使用pkg字段
   */
  private async loadSourceName(sourceId: number): Promise<void> {
    if (sourceId <= 0) {
      this.currentSourceName = '';
      this.currentSourcePkg = '';
      return;
    }
    
    try {
      const sources = await this.dataManager.getAllComicSources();
      for (let i = 0; i < sources.length; i++) {
        const s: ESObject = sources[i] as ESObject;
        if (Number(s.id) === sourceId) {
          // 优先使用name，如果为空则使用pkg
          const name = String(s.name || '');
          const pkg = String(s.pkg || '');
          this.currentSourcePkg = pkg;
          if (name && name.trim() !== '') {
            this.currentSourceName = name;
          } else if (pkg && pkg.trim() !== '') {
            this.currentSourceName = pkg;
          } else {
            this.currentSourceName = `WebView Source ${sourceId}`;
          }
          logger.info(TAG, `获取图源名称: ${this.currentSourceName} (name="${name}", pkg="${pkg}")`);
          return;
        }
      }
      logger.warn(TAG, `未找到sourceId=${sourceId}对应的图源记录`);
      this.currentSourceName = `WebView Source ${sourceId}`;
      this.currentSourcePkg = '';
    } catch (error) {
      logger.warn(TAG, `获取图源名称失败: ${String(error)}`);
      this.currentSourceName = `WebView Source ${sourceId}`;
      this.currentSourcePkg = '';
    }
  }
  
  /**
   * 转换本地章节为MangaChapter格式
   */
  private async convertLocalChaptersToMangaChapters(chapters: ChapterInfo[]): Promise<MangaChapter[]> {
    const mangaChapters: MangaChapter[] = [];
    
    for (let i = 0; i < chapters.length; i++) {
      const ch = chapters[i];
      const chapter: MangaChapter = {
        id: ch.id,
        title: ch.title,
        chapterNumber: ch.index || i,
        pages: [],
        publishDate: ch.publishTime || Date.now(),
        language: 'zh-CN',
        scanlationGroup: '',
        isDownloaded: ch.isDownloaded || false,
        downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
        downloadProgress: ch.isDownloaded ? 100 : 0
      };
      mangaChapters.push(chapter);
    }
    
    return mangaChapters;
  }
  
  /**
   * 转换在线章节为MangaChapter格式
   */
  private async convertOnlineChaptersToMangaChapters(chapters: OnlineChapterInfo[]): Promise<MangaChapter[]> {
    const mangaChapters: MangaChapter[] = [];
    
    for (let i = 0; i < chapters.length; i++) {
      const ch = chapters[i];
      
      // 获取页面信息
      const pageInfos = await this.dataManager.getOnlineChapterPages(ch.id);
      const pages: MangaPage[] = pageInfos.map((pageInfo, arrayIndex): MangaPage => {
        let sourceType: ImageSourceType;
        if (pageInfo.imageUrl.startsWith('http://') || pageInfo.imageUrl.startsWith('https://')) {
          sourceType = ImageSourceType.NETWORK;
        } else if (pageInfo.imageUrl.startsWith('/')) {
          sourceType = ImageSourceType.LOCAL;
        } else {
          sourceType = ImageSourceType.RAWFILE;
        }
        
        return {
          id: pageInfo.id,
          index: arrayIndex,
          sourceType: sourceType,
          imagePath: pageInfo.imageUrl,
          imageUrl: pageInfo.imageUrl,
          width: pageInfo.width,
          height: pageInfo.height,
          fileSize: pageInfo.fileSize,
          isLoaded: false
        };
      });
      
      const chapter: MangaChapter = {
        id: ch.id,
        title: ch.title || `第${ch.chapterNumber || i + 1}章`,
        chapterNumber: ch.chapterNumber || i,
        pages: pages,
        publishDate: ch.publishTime || ch.addTime || Date.now(),
        language: 'zh-CN',
        scanlationGroup: '',
        isDownloaded: ch.isDownloaded || false,
        downloadStatus: ch.isDownloaded ? DownloadStatus.COMPLETED : DownloadStatus.PENDING,
        downloadProgress: ch.isDownloaded ? 100 : 0,
        externalId: ch.externalId
      };
      mangaChapters.push(chapter);
    }
    
    return mangaChapters;
  }
  
  /**
   * 转换WebView章节为MangaChapter格式
   * [修复] 使用原始章节的number字段，并进行智能排序
   */
  private convertWebViewChaptersToMangaChapters(chapters: WebViewChapterInfo[]): MangaChapter[] {
    const mangaChapters: MangaChapter[] = [];
    
    for (let i = 0; i < chapters.length; i++) {
      const ch = chapters[i];
      // [修复] 使用原始章节的number字段，如果没有则从标题提取或使用索引
      let chapterNumber = i;
      if (ch.number !== undefined && ch.number !== null && !isNaN(ch.number)) {
        chapterNumber = ch.number;
      } else {
        // 尝试从标题中提取章节号
        const extractedNum = this.extractChapterNumberFromTitle(ch.title);
        if (extractedNum !== null) {
          chapterNumber = extractedNum;
        }
      }
      
      const chapter: MangaChapter = {
        id: ch.id || `chapter_${i}`,
        title: ch.title || `第${i + 1}章`,
        chapterNumber: chapterNumber,
        pages: [],
        publishDate: ch.publishTime ? new Date(ch.publishTime).getTime() : Date.now(),
        language: 'zh-CN',
        scanlationGroup: '',
        isDownloaded: false,
        downloadStatus: DownloadStatus.PENDING,
        downloadProgress: 0,
        externalId: ch.id
      };
      mangaChapters.push(chapter);
    }
    
    // [修复] 对章节进行智能排序（按chapterNumber升序）
    mangaChapters.sort((a: MangaChapter, b: MangaChapter) => {
      return a.chapterNumber - b.chapterNumber;
    });
    
    logger.info(TAG, `章节转换完成并排序: ${mangaChapters.length}章, 第一章: ${mangaChapters[0]?.title || 'N/A'}, 最后一章: ${mangaChapters[mangaChapters.length - 1]?.title || 'N/A'}`);
    
    return mangaChapters;
  }
  
  /**
   * 从章节标题中提取章节号
   * [增强] 支持多种语言、符号格式，提高准确性和兼容性
   */
  private extractChapterNumberFromTitle(title: string): number | null {
    if (!title) return null;

    // 预处理：去除首尾空格
    const cleanTitle = title.trim();

    // 中文数字映射（扩展支持）
    const chineseNumMap: Record<string, number> = {
      '零': 0, '〇': 0,
      '一': 1, '壹': 1,
      '二': 2, '贰': 2, '两': 2,
      '三': 3, '叁': 3,
      '四': 4, '肆': 4,
      '五': 5, '伍': 5,
      '六': 6, '陆': 6,
      '七': 7, '柒': 7,
      '八': 8, '捌': 8,
      '九': 9, '玖': 9,
      '十': 10, '拾': 10,
      '百': 100, '佰': 100,
      '千': 1000, '仟': 1000
    };

    // ========== 高优先级：明确的章节标识格式 ==========

    // 格式1: 中文格式 - 第X章/话/回/集/卷/篇/幕/节 (阿拉伯数字)
    let match = cleanTitle.match(/第\s*(\d+(?:\.\d+)?)\s*[章话回集卷篇幕节]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式2: 中文格式 - 第X章/话/回/集 (中文数字)
    match = cleanTitle.match(/第\s*([零〇一二三四五六七八九十百千壹贰叁肆伍陆柒捌玖拾佰仟两]+)\s*[章话回集卷篇幕节]/);
    if (match) {
      const chineseNum = this.parseChineseNumber(match[1], chineseNumMap);
      if (chineseNum !== null) return chineseNum;
    }

    // 格式3: 英文格式 - Chapter/Ch./Ch/Chap/Chpt X
    match = cleanTitle.match(/(?:Chapter|Chap(?:ter)?|Chpt|Ch\.?)\s*[:\-]?\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式4: 英文格式 - Episode/EP./Ep X
    match = cleanTitle.match(/(?:Episode|Ep\.?)\s*[:\-]?\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式5: 日文格式 - 第X話/回/巻
    match = cleanTitle.match(/第\s*(\d+(?:\.\d+)?)\s*[話巻]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式6: 韩文格式 - X화/회/장
    match = cleanTitle.match(/(\d+(?:\.\d+)?)\s*[화회장]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式7: 符号格式 - #X, No.X, No X, Vol.X, Volume X
    match = cleanTitle.match(/(?:#|No\.?|Vol(?:ume)?\.?)\s*(\d+(?:\.\d+)?)/i);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式8: 括号格式 - (X), [X], 【X】, 「X」
    match = cleanTitle.match(/[(\[【「]\s*(\d+(?:\.\d+)?)\s*[)\]】」]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式9: 连字符/冒号格式 - X - Title, X: Title, X. Title
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s*[:\-\.]\s*\S/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式10: 数字+单位格式 - X话/章/回/集 (数字在前，无"第"字)
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s*[话章回集卷篇話巻]/);
    if (match) {
      return parseFloat(match[1]);
    }

    // ========== 中优先级：数字开头格式 ==========

    // 格式11: 纯数字开头 (如 "001", "1", "1.5", "001 标题")
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)\s/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式12: 纯数字标题 (如 "001", "1", "1.5")
    match = cleanTitle.match(/^(\d+(?:\.\d+)?)$/);
    if (match) {
      return parseFloat(match[1]);
    }

    // ========== 低优先级：标题中的数字 ==========

    // 格式13: 标题末尾的数字 (如 "番外1", "特别篇2")
    match = cleanTitle.match(/[^\d](\d+(?:\.\d+)?)$/);
    if (match) {
      return parseFloat(match[1]);
    }

    // 格式14: 标题中包含的第一个数字（最后手段）
    // 排除年份格式（4位数字且在1900-2100范围）
    const allNumbers = cleanTitle.match(/\d+(?:\.\d+)?/g);
    if (allNumbers) {
      for (const numStr of allNumbers) {
        const num = parseFloat(numStr);
        // 排除可能是年份的数字
        if (num >= 1900 && num <= 2100 && numStr.length === 4) {
          continue;
        }
        // 排除过大的数字（可能是日期、ID等）
        if (num < 10000) {
          return num;
        }
      }
    }

    return null;
  }
  
  /**
   * 解析中文数字
   */
  private parseChineseNumber(chineseStr: string, numMap: Record<string, number>): number | null {
    if (!chineseStr) return null;

    let result = 0;
    let temp = 0;

    for (let i = 0; i < chineseStr.length; i++) {
      const char = chineseStr[i];
      const num = numMap[char];

      if (num === undefined) {
        return null;
      }

      if (num >= 10) {
        if (temp === 0) temp = 1;
        temp *= num;
        result += temp;
        temp = 0;
      } else {
        temp = num;
      }
    }

    result += temp;
    return result > 0 ? result : null;
  }
  
  /**
   * 从ComicInfo构建Manga对象
   */
  private async buildMangaFromComicInfo(comicInfo: ComicInfo, chapters: MangaChapter[]): Promise<Manga> {
    const readingSettings = await ComicConverter.loadReadingSettings(comicInfo.id, 'default_user', String(comicInfo.sourceId));
    
    const metadata: MangaMetadata = {
      authors: comicInfo.author ? [comicInfo.author] : [],
      artists: [],
      genres: comicInfo.tags || [],
      themes: [],
      demographics: []
    };
    
    const readingProgress: ReadingProgress = {
      currentChapterId: '',
      currentPageIndex: 0,
      lastReadAt: Date.now(),
      readingStatus: ReadingStatus.UNREAD,
      totalReadingTime: 0,
      readingPercentage: 0
    };
    
    return {
      id: comicInfo.id,
      title: comicInfo.title,
      alternativeTitles: [],
      description: comicInfo.description || '',
      coverImagePath: comicInfo.coverUrl || '',
      coverSourceType: this.isLocalSourceId(String(comicInfo.sourceId)) ? ImageSourceType.LOCAL : ImageSourceType.NETWORK,
      status: comicInfo.status || MangaStatus.UNKNOWN,
      metadata: metadata,
      chapters: chapters,
      readingProgress: readingProgress,
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: false,
      lastUpdatedAt: comicInfo.lastUpdateTime || Date.now(),
      isNSFW: Boolean(comicInfo.isNSFW) || false
    };
  }
  
  /**
   * 从OnlineComicInfo构建Manga对象
   */
  private async buildMangaFromOnlineComicInfo(onlineComic: OnlineComicInfo, chapters: MangaChapter[]): Promise<Manga> {
    const sourceIdStr = onlineComic.sourceId ? String(onlineComic.sourceId) : String(this.currentSourceId);
    const readingSettings = await ComicConverter.loadReadingSettings(onlineComic.id, 'default_user', sourceIdStr);
    
    const displaySourceName = onlineComic.sourceName || this.currentSourceName || `WebView Source ${this.currentSourceId}`;
    
    return {
      id: onlineComic.id,
      title: onlineComic.title,
      alternativeTitles: [],
      description: onlineComic.description || '',
      coverImagePath: onlineComic.coverUrl || '',
      coverSourceType: ImageSourceType.NETWORK,
      status: MangaStatus.UNKNOWN,
      metadata: {
        authors: onlineComic.author ? [onlineComic.author] : [],
        artists: onlineComic.author ? [onlineComic.author] : [],
        genres: onlineComic.tags || [],
        themes: [],
        demographics: []
      },
      chapters: chapters,
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: 0,
        readingStatus: ReadingStatus.UNREAD,
        totalReadingTime: 0,
        lastReadAt: 0,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: false,
      lastUpdatedAt: onlineComic.lastUpdateTime || Date.now(),
      sourceInfo: {
        sourceName: displaySourceName,
        sourcePkg: this.currentSourcePkg || undefined,
        sourceUrl: onlineComic.externalId || '',
        sourceId: sourceIdStr,
        sourceLanguage: 'zh',
        requiresLogin: false
      }
    };
  }
  
  /**
   * 从MangaInfo构建Manga对象
   */
  private buildMangaFromMangaInfo(mangaInfo: MangaInfo, chapters: MangaChapter[], externalId: string): Manga {
    const internalId = `id_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
    
    return {
      id: internalId,
      title: mangaInfo.title || '未知标题',
      alternativeTitles: [],
      description: mangaInfo.description || '',
      coverImagePath: mangaInfo.cover || '',
      coverSourceType: ImageSourceType.NETWORK,
      status: this.convertStatus(mangaInfo.status),
      metadata: {
        authors: mangaInfo.author ? [mangaInfo.author] : [],
        artists: mangaInfo.author ? [mangaInfo.author] : [],
        genres: mangaInfo.genres || [],
        themes: [],
        demographics: []
      },
      chapters: chapters,
      readingProgress: {
        currentChapterId: '',
        currentPageIndex: 0,
        readingStatus: ReadingStatus.UNREAD,
        totalReadingTime: 0,
        lastReadAt: 0,
        readingPercentage: 0
      },
      bookmarks: [],
      readingSettings: DEFAULT_READING_SETTINGS,
      isFavorite: false,
      lastUpdatedAt: Date.now(),
      sourceInfo: {
        sourceName: this.currentSourceName,
        sourcePkg: this.currentSourcePkg || undefined,
        sourceUrl: externalId,
        sourceId: String(this.currentSourceId),
        sourceLanguage: 'zh',
        requiresLogin: false
      }
    };
  }
  
  /**
   * 转换状态
   */
  private convertStatus(status?: string): MangaStatus {
    if (!status) return MangaStatus.UNKNOWN;
    if (status === '连载中' || status.toLowerCase().includes('ongoing')) {
      return MangaStatus.ONGOING;
    }
    if (status === '已完结' || status.toLowerCase().includes('completed')) {
      return MangaStatus.COMPLETED;
    }
    return MangaStatus.UNKNOWN;
  }
  
  /**
   * 保存在线漫画到数据库（包含页面预取）
   */
  private async saveOnlineMangaToDatabase(manga: Manga, chapters: MangaChapter[], externalId: string): Promise<void> {
    try {
      // 获取作者信息
      let authorStr = '';
      if (manga.metadata && manga.metadata.authors && manga.metadata.authors.length > 0) {
        authorStr = manga.metadata.authors[0];
      }
      
      // 保存漫画信息到online_comic_info表（使用saveComicFromSource）
      const comicData: OnlineComicSourceSaveInput = {
        id: externalId,
        title: manga.title,
        author: authorStr,
        description: manga.description || '',
        coverUrl: manga.coverImagePath || '',
        tags: manga.metadata.genres || [],
        rating: 0,
        updateTime: Date.now(),
        sourceName: this.currentSourceName
      };
      
      const internalComicId = await this.dataManager.saveComicFromSource(this.currentSourceId, comicData, externalId);
      logger.info(TAG, `保存漫画信息成功: ${manga.title}, 内部ID: ${internalComicId}`);
      
      // 更新manga的ID为内部ID
      manga.id = internalComicId;
      
      // 保存章节信息到online_chapter表（包含页面预取）
      for (let i = 0; i < chapters.length; i++) {
        const ch = chapters[i];
        const chapterExternalId = ch.externalId || ch.id;
        
        // 获取章节页数和页面信息
        let chapterPageCount = 0;
        let pageInfos: SourcePageInfo[] = [];
        
        // 如果章节已有页面数据，直接使用
        if (ch.pages && ch.pages.length > 0) {
          chapterPageCount = ch.pages.length;
          pageInfos = ch.pages.map((page: MangaPage, index: number): SourcePageInfo => ({
            page: index,
            imageUrl: page.imageUrl || page.imagePath || '',
            width: page.width || 0,
            height: page.height || 0
          }));
        } else if (this.mangaEngine && chapterExternalId && this.shouldPrefetchPages()) {
          // WebView图源：动态获取页面列表
          try {
            logger.info(TAG, `📥 获取章节 "${ch.title}" 的页面列表...`);
            const pageListResult = await this.mangaEngine.getPageList(chapterExternalId, externalId);
            
            if (pageListResult.success && pageListResult.data) {
              pageInfos = pageListResult.data;
              chapterPageCount = pageInfos.length;
              logger.info(TAG, `✅ 章节 "${ch.title}" 获取到 ${chapterPageCount} 个页面`);
            } else {
              logger.warn(TAG, `⚠️ 章节 "${ch.title}" 获取页面列表失败: ${pageListResult.error}`);
            }
          } catch (error) {
            logger.error(TAG, `❌ 获取章节 "${ch.title}" 页面列表异常: ${error}`);
          }
        }
        
        const chapterInput: OnlineChapterInfoInput = {
          comicId: internalComicId,
          externalId: chapterExternalId,
          title: ch.title,
          chapterNumber: ch.chapterNumber || i,
          url: '',
          pageCount: chapterPageCount,
          publishTime: typeof ch.publishDate === 'number' ? ch.publishDate : Date.now(),
          isDownloaded: false,
          downloadPath: undefined,
          index: i
        };
        
        const chapterId = await this.dataManager.addOnlineChapterInfo(chapterInput);
        
        // 更新章节的内部ID
        ch.id = chapterId;
        
        // 保存页面信息到online_page表
        if (pageInfos.length > 0) {
          for (let j = 0; j < pageInfos.length; j++) {
            const pageInfo = pageInfos[j];
            const onlinePageInput: OnlinePageInfoInput = {
              chapterId: chapterId,
              pageNumber: j,
              imageUrl: pageInfo.imageUrl,
              requestHeaders: this.serializePageRequestHeaders(pageInfo.requestHeaders),
              width: pageInfo.width || 0,
              height: pageInfo.height || 0,
              fileSize: 0
            };
            await this.dataManager.addOnlinePageInfo(onlinePageInput);
          }
          logger.info(TAG, `✅ 已保存章节 "${ch.title}" 的 ${pageInfos.length} 个页面信息`);
        }
      }
      logger.info(TAG, `保存章节信息成功: ${chapters.length}章`);
    } catch (error) {
      logger.error(TAG, `保存漫画到数据库失败: ${String(error)}`);
    }
  }
  
  /**
   * 判断是否应该预取页面
   * 某些图源可能不支持或不需要预取
   */
  private shouldPrefetchPages(): boolean {
    // 默认启用页面预取
    // 可以根据图源ID或其他条件决定是否预取
    return true;
  }

  private serializePageRequestHeaders(headers: PageRequestHeader[] | undefined): string {
    if (!headers || headers.length <= 0) {
      return '';
    }
    const normalized: PageRequestHeader[] = [];
    for (let i = 0; i < headers.length; i++) {
      const header = headers[i];
      if (!header) {
        continue;
      }
      const name = String(header.name || '').trim();
      const value = String(header.value || '').trim();
      if (name.length <= 0 || value.length <= 0) {
        continue;
      }
      normalized.push({
        name: name,
        value: value
      } as PageRequestHeader);
    }
    if (normalized.length <= 0) {
      return '';
    }
    return SafeUtils.stringifyJson(normalized, '');
  }
  
  /**
   * 更新章节到数据库
   * [修复] 使用原始章节的number字段或从标题提取章节号
   */
  private async updateChaptersToDatabase(comicId: string, newChapters: WebViewChapterInfo[]): Promise<void> {
    try {
      for (let i = 0; i < newChapters.length; i++) {
        const ch = newChapters[i];
        const chapterExternalId = ch.id || `chapter_${i}`;
        
        // [修复] 使用原始章节的number字段，如果没有则从标题提取
        let chapterNumber = i;
        if (ch.number !== undefined && ch.number !== null && !isNaN(ch.number)) {
          chapterNumber = ch.number;
        } else {
          const extractedNum = this.extractChapterNumberFromTitle(ch.title);
          if (extractedNum !== null) {
            chapterNumber = extractedNum;
          }
        }
        
        // 检查是否已存在
        const existing = await this.dataManager.getOnlineChapterByExternalId(comicId, chapterExternalId);
        if (!existing) {
          const chapterInput: OnlineChapterInfoInput = {
            comicId: comicId,
            externalId: chapterExternalId,
            title: ch.title || `第${i + 1}章`,
            chapterNumber: chapterNumber,
            url: '',
            pageCount: 0,
            publishTime: ch.publishTime ? new Date(ch.publishTime).getTime() : Date.now(),
            isDownloaded: false,
            downloadPath: undefined,
            index: chapterNumber  // [修复] 使用章节号作为index
          };
          await this.dataManager.addOnlineChapterInfo(chapterInput);
        }
      }
      logger.info(TAG, `更新章节完成: ${newChapters.length}章`);
    } catch (error) {
      logger.error(TAG, `更新章节失败: ${String(error)}`);
    }
  }
  
  /**
   * 加载章节阅读进度数据
   * @param mangaId 漫画ID
   * @param chapters 章节列表
   * @param isOnline 是否为在线漫画
   */
  public async loadChapterProgressData(
    mangaId: string, 
    chapters: MangaChapter[], 
    isOnline: boolean
  ): Promise<ChapterProgressLoadResult> {
    const progressList: ChapterProgressInfo[] = [];
    const readChapterIds = new Set<string>();
    let lastReadChapterIndex = -1;
    let latestReadTime = 0;
    
    try {
      logger.info(TAG, `开始加载章节进度数据，共${chapters.length}个章节，isOnline=${isOnline}`);
      
      // 获取阅读历史
      let historyList: ESObject[] = [];
      if (isOnline) {
        // 在线漫画：查询online_read_history表
        const onlineHistoryRecords = await this.dataManager.getOnlineReadHistoryByComic(mangaId);
        historyList = onlineHistoryRecords as ESObject[];
        logger.debug(TAG, `获取到在线漫画阅读历史: ${historyList.length}条`);
      } else {
        // 本地漫画：查询read_history表
        const localHistory = await this.dataManager.getReadHistoryByComic(mangaId, 'default_user', 1000);
        historyList = localHistory as ESObject[];
        logger.debug(TAG, `获取到本地漫画阅读历史: ${historyList.length}条`);
      }
      
      // 批量查询所有章节的页面数
      const pageCountMap = new Map<string, number>();
      try {
        const pageQueries = chapters.map(async (chapter: MangaChapter): Promise<ChapterPageCount> => {
          try {
            if (isOnline) {
              const pages = await this.dataManager.getOnlineChapterPages(chapter.id);
              const result: ChapterPageCount = { chapterId: chapter.id, count: pages ? pages.length : 0 };
              return result;
            } else {
              const pages = await this.dataManager.getPageInfoList(chapter.id);
              const result: ChapterPageCount = { chapterId: chapter.id, count: pages.length };
              return result;
            }
          } catch (err) {
            const result: ChapterPageCount = { chapterId: chapter.id, count: 0 };
            return result;
          }
        });
        
        const results = await Promise.all(pageQueries);
        results.forEach(result => {
          pageCountMap.set(result.chapterId, result.count);
        });
      } catch (err) {
        logger.warn(TAG, `批量查询章节页面失败: ${String(err)}`);
      }
      
      // 构建章节进度列表
      for (let i = 0; i < chapters.length; i++) {
        const chapter = chapters[i];
        const totalPages = pageCountMap.get(chapter.id) || 0;
        
        // 查找该章节的阅读历史
        let lastReadPageIndex = -1;
        let lastReadTime = 0;
        
        for (let j = 0; j < historyList.length; j++) {
          const h: ESObject = historyList[j];
          const historyChapterId = String(h.chapterId || '');
          if (historyChapterId === chapter.id) {
            const readTime = Number(h.readTime || 0);
            if (readTime > lastReadTime) {
              lastReadTime = readTime;
              lastReadPageIndex = Number(h.pageIndex || 0);
            }
          }
        }
        
        // 判断是否已读（有阅读记录）
        const isRead = lastReadPageIndex >= 0;
        if (isRead) {
          readChapterIds.add(chapter.id);
        }
        
        // 判断是否读完
        const isCompleted = isRead && totalPages > 0 && lastReadPageIndex >= totalPages - 1;
        
        // 记录最后阅读的章节
        if (lastReadTime > latestReadTime) {
          latestReadTime = lastReadTime;
          lastReadChapterIndex = i;
        }
        
        const progressInfo: ChapterProgressInfo = {
          chapterId: chapter.id,
          lastReadPageIndex: lastReadPageIndex,
          totalPages: totalPages,
          isCompleted: isCompleted,
          lastReadTime: lastReadTime
        };
        progressList.push(progressInfo);
      }
      
      logger.info(TAG, `章节进度加载完成: ${progressList.length}章, 已读${readChapterIds.size}章, 最后阅读章节索引=${lastReadChapterIndex}`);
    } catch (error) {
      logger.error(TAG, `加载章节进度失败: ${String(error)}`);
    }
    
    const result: ChapterProgressLoadResult = {
      progressList: progressList,
      readChapterIds: readChapterIds,
      lastReadChapterIndex: lastReadChapterIndex
    };
    return result;
  }
  
  /**
   * 清理资源
   */
  public dispose(): void {
    this.mangaEngine = null;
    this.webViewController = null;
    logger.info(TAG, '漫画详情加载器资源已清理');
  }
}
