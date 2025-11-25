// 文件路径: src/main/ets/Framework/Utils/ComicConverter.ets
// 职责: 提供ComicInfo与Manga对象之间的转换工具方法

import { 
  Manga, 
  MangaMetadata,
  ReadingProgress,
  ReadingSettings,
  ImageSourceType,
  ReadingMode,
  ReadingDirection,
  DEFAULT_READING_SETTINGS
} from '../../Models/MangaModels';
import { ComicInfo, ReadHistory, OnlineComicInfo } from '../Data/DataManager';
import { MangaStatus, ReadingStatus, StatusConverter } from '../Types/StatusEnums';
import { DataManager } from '../Data/DataManager';
import { logger } from '../../Utils/Logger';

const TAG = 'ComicConverter';

/**
 * 漫画数据转换工具类
 */
export class ComicConverter {
  /**
   * 将ComicInfo转换为Manga对象（同步版本，使用默认设置）
   * @deprecated 请使用 convertComicInfoToMangaAsync 以加载完整的阅读设置和进度
   */
  public static convertComicInfoToManga(comic: ComicInfo): Manga {
    logger.warn(TAG, `使用同步转换方法，将返回默认设置。建议使用 convertComicInfoToMangaAsync 以加载完整数据`);
    
    // 根据封面路径判断图片来源类型（网络/本地/rawfile）
    const detectImageSourceType = (path: string): ImageSourceType => {
      const src: string = path;
      if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
        return ImageSourceType.NETWORK;
      }
      if (src.indexOf('$rawfile(') === 0) {
        return ImageSourceType.RAWFILE;
      }
      return ImageSourceType.LOCAL;
    };

    const defaultMetadata: MangaMetadata = {
      authors: comic.author ? [comic.author] : [],
      publisher: '',
      publicationYear: new Date(comic.addTime).getFullYear(),
      genres: comic.tags ? comic.tags : [],
      artists: [],
      themes: [],
      demographics: []
    };

    const defaultReadingProgress: ReadingProgress = {
      currentChapterId: '',
      currentPageIndex: 0,
      lastReadAt: 0,   
      readingStatus: ReadingStatus.UNREAD,
      totalReadingTime: 0,
      readingPercentage: 0
    };

    return {
      id: comic.id,
      title: comic.title,
      alternativeTitles: [],
      description: comic.description,
      coverImagePath: comic.coverUrl,
      coverSourceType: detectImageSourceType(comic.coverUrl),
      status: StatusConverter.toMangaStatus(comic.status),
      metadata: defaultMetadata,
      chapters: [], // 章节信息需要单独加载
      readingProgress: defaultReadingProgress,
      bookmarks: [],
      readingSettings: DEFAULT_READING_SETTINGS,
      isFavorite: false,
      addedToLibraryAt: comic.addTime,
      lastUpdatedAt: comic.lastUpdateTime,
      sourceInfo: {
        sourceId: comic.sourceId,
        sourceName: '本地导入',
        sourceUrl: '',
        sourceLanguage: 'zh-CN',
        requiresLogin: false
      }
    };
  }

  /**
   * 将ComicInfo转换为Manga对象（异步版本，加载完整的阅读设置和进度）
   * @param comic 漫画基本信息
   * @param userId 用户ID（默认为'default_user'）
   * @returns Promise<Manga> 包含完整阅读设置和进度的漫画对象
   */
  public static async convertComicInfoToMangaAsync(comic: ComicInfo, userId: string = 'default_user'): Promise<Manga> {
    logger.info(TAG, `异步转换漫画信息: ${comic.title} (ID: ${comic.id})`);
    
    // 根据封面路径判断图片来源类型（网络/本地/rawfile）
    const detectImageSourceType = (path: string): ImageSourceType => {
      const src: string = path;
      if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
        return ImageSourceType.NETWORK;
      }
      if (src.indexOf('$rawfile(') === 0) {
        return ImageSourceType.RAWFILE;
      }
      return ImageSourceType.LOCAL;
    };

    const defaultMetadata: MangaMetadata = {
      authors: comic.author ? [comic.author] : [],
      publisher: '',
      publicationYear: new Date(comic.addTime).getFullYear(),
      genres: comic.tags ? comic.tags : [],
      artists: [],
      themes: [],
      demographics: []
    };

    // 从数据库加载阅读设置
    const readingSettings = await ComicConverter.loadReadingSettings(comic.id, userId);
    logger.debug(TAG, `加载的阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}`);

    // 从数据库加载阅读进度
    const readingProgress = await ComicConverter.loadReadingProgress(comic.id, userId);
    logger.debug(TAG, `加载的阅读进度: chapter=${readingProgress.currentChapterId}, page=${readingProgress.currentPageIndex}`);

    // 加载收藏状态
    let favorited: boolean = false;
    try {
      const dm = DataManager.getInstance();
      const favorites = await dm.getUserFavorites(userId);
      for (let i: number = 0; i < favorites.length; i++) {
        const fav = favorites[i];
        if (fav.comicId === comic.id) {
          favorited = true;
          break;
        }
      }
      logger.debug(TAG, `收藏状态加载完成: ${String(favorited)} (comicId=${comic.id})`);
    } catch (favErr) {
      const em: string = favErr instanceof Error ? favErr.message : String(favErr);
      logger.warn(TAG, `加载收藏状态失败: ${em}`);
    }

    return {
      id: comic.id,
      title: comic.title,
      alternativeTitles: [],
      description: comic.description,
      coverImagePath: comic.coverUrl,
      coverSourceType: detectImageSourceType(comic.coverUrl),
      status: StatusConverter.toMangaStatus(comic.status),
      metadata: defaultMetadata,
      chapters: [], // 章节信息需要单独加载
      readingProgress: readingProgress,
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: favorited,
      addedToLibraryAt: comic.addTime,
      lastUpdatedAt: comic.lastUpdateTime,
      sourceInfo: {
        sourceId: comic.sourceId,
        sourceName: '本地导入',
        sourceUrl: '',
        sourceLanguage: 'zh-CN',
        requiresLogin: false
      }
    };
  }

  /**
   * 从数据库加载漫画的阅读设置
   * @param comicId 漫画ID
   * @param userId 用户ID
   * @returns Promise<ReadingSettings> 阅读设置
   */
  private static async loadReadingSettings(comicId: string, userId: string): Promise<ReadingSettings> {
    const dataManager = DataManager.getInstance();
    
    try {
      // 从user_settings表加载设置（键名格式：manga_settings_{comicId}）
      const settingKey = `manga_settings_${comicId}`;
      const settingsJson = await dataManager.getUserSetting(userId, settingKey);
      
      if (settingsJson) {
        // 解析JSON字符串
        const settings = JSON.parse(settingsJson) as ReadingSettings;
        logger.info(TAG, `成功从数据库加载漫画 ${comicId} 的阅读设置`);
        return settings;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `加载漫画 ${comicId} 的阅读设置失败: ${errorMessage}，使用默认设置`);
    }
    
    // 如果没有保存的设置，使用全局阅读模式作为回退
    logger.info(TAG, `漫画 ${comicId} 未找到保存的阅读设置，使用全局阅读设置回退`);
    const globalMode = AppStorage.get<ReadingMode>('global_reading_mode');
    const globalDirection = AppStorage.get<ReadingDirection>('global_reading_direction');

    const mode: ReadingMode = globalMode ? globalMode : DEFAULT_READING_SETTINGS.readingMode;
    let direction: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
    if (globalDirection) {
      direction = globalDirection;
    } else {
      if (mode === ReadingMode.WEBTOON) {
        direction = ReadingDirection.TOP_TO_BOTTOM;
      }
    }

    const fallbackSettings: ReadingSettings = {
      readingMode: mode,
      readingDirection: direction,
      brightness: DEFAULT_READING_SETTINGS.brightness,
      keepScreenOn: DEFAULT_READING_SETTINGS.keepScreenOn,
      pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
      showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
      doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation,
      curlBackOpacity: 0
    };
    return fallbackSettings;
  }

  /**
   * 从数据库加载漫画的阅读进度
   * @param comicId 漫画ID
   * @param userId 用户ID
   * @returns Promise<ReadingProgress> 阅读进度
   */
  private static async loadReadingProgress(comicId: string, userId: string): Promise<ReadingProgress> {
    const dataManager = DataManager.getInstance();
    
    try {
      // 从read_history表获取最新的阅读记录
      const historyList = await dataManager.getReadHistoryByComic(comicId, userId, 1);
      
      if (historyList && historyList.length > 0) {
        const latestHistory: ReadHistory = historyList[0];
        
        // 调试：检查原始history数据
        logger.debug(TAG, `原始history数据: chapterId=${latestHistory.chapterId}, pageIndex=${latestHistory.pageIndex}, comicId=${latestHistory.comicId}`);
        
        const progress: ReadingProgress = {
          currentChapterId: latestHistory.chapterId || '',  // 添加空值保护
          currentPageIndex: latestHistory.pageIndex || 0,   // 添加空值保护
          lastReadAt: latestHistory.readTime || 0,
          readingStatus: ReadingStatus.READING,
          totalReadingTime: (latestHistory.readDuration || 0) / 1000 / 60, // ReadHistory使用readDuration字段，转换为分钟
          readingPercentage: 0 // 需要计算总页数才能得到百分比
        };
        
        logger.info(TAG, `成功从数据库加载漫画 ${comicId} 的阅读进度: chapter=${progress.currentChapterId}, page=${progress.currentPageIndex}`);
        return progress;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `加载漫画 ${comicId} 的阅读进度失败: ${errorMessage}，使用默认进度`);
    }
    
    // 如果没有阅读记录，返回默认进度
    logger.info(TAG, `漫画 ${comicId} 未找到阅读记录，使用默认进度`);
    const defaultReadingProgress: ReadingProgress = {
      currentChapterId: '',
      currentPageIndex: 0,
      lastReadAt: 0,   
      readingStatus: ReadingStatus.UNREAD,
      totalReadingTime: 0,
      readingPercentage: 0
    };
    return defaultReadingProgress;
  }

  /**
   * [新增] 将OnlineComicInfo转换为Manga对象（异步版本）
   * @param onlineComic 在线漫画基本信息
   * @param userId 用户ID（默认为'default_user'）
   * @returns Promise<Manga> 包含完整阅读设置和进度的漫画对象
   */
  public static async convertOnlineComicInfoToMangaAsync(onlineComic: OnlineComicInfo, userId: string = 'default_user'): Promise<Manga> {
    logger.info(TAG, `异步转换在线漫画信息: ${onlineComic.title} (ID: ${onlineComic.id})`);
    
    // 根据封面路径判断图片来源类型（网络/本地/rawfile）
    const detectImageSourceType = (path: string): ImageSourceType => {
      const src: string = path;
      if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
        return ImageSourceType.NETWORK;
      }
      if (src.indexOf('$rawfile(') === 0) {
        return ImageSourceType.RAWFILE;
      }
      return ImageSourceType.LOCAL;
    };

    const defaultMetadata: MangaMetadata = {
      authors: onlineComic.author ? [onlineComic.author] : [],
      publisher: '',
      publicationYear: new Date(onlineComic.addTime).getFullYear(),
      genres: onlineComic.tags ? onlineComic.tags : [],
      artists: [],
      themes: [],
      demographics: []
    };

    // 从数据库加载阅读设置
    const readingSettings = await ComicConverter.loadReadingSettings(onlineComic.id, userId);
    logger.debug(TAG, `加载的阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}`);

    // 从数据库加载阅读进度
    const readingProgress = await ComicConverter.loadReadingProgress(onlineComic.id, userId);
    logger.debug(TAG, `加载的阅读进度: chapter=${readingProgress.currentChapterId}, page=${readingProgress.currentPageIndex}`);

    // 加载收藏状态
    let favorited: boolean = false;
    try {
      const dm = DataManager.getInstance();
      const favorites = await dm.getUserFavorites(userId);
      for (let i: number = 0; i < favorites.length; i++) {
        const fav = favorites[i];
        if (fav.comicId === onlineComic.id) {
          favorited = true;
          break;
        }
      }
      logger.debug(TAG, `收藏状态加载完成: ${String(favorited)} (comicId=${onlineComic.id})`);
    } catch (favErr) {
      const em: string = favErr instanceof Error ? favErr.message : String(favErr);
      logger.warn(TAG, `加载收藏状态失败: ${em}`);
    }

    return {
      id: onlineComic.id,
      title: onlineComic.title,
      alternativeTitles: [],
      description: onlineComic.description,
      coverImagePath: onlineComic.coverUrl,
      coverSourceType: detectImageSourceType(onlineComic.coverUrl),
      status: MangaStatus.ONGOING, // 在线漫画默认为连载中
      metadata: defaultMetadata,
      chapters: [], // 章节信息需要单独加载
      readingProgress: readingProgress,
      bookmarks: [],
      readingSettings: readingSettings,
      isFavorite: favorited,
      addedToLibraryAt: onlineComic.addTime,
      lastUpdatedAt: onlineComic.lastUpdateTime,
      sourceInfo: {
        sourceId: onlineComic.sourceId,
        sourceName: onlineComic.sourceName || 'WebView Source',
        sourceUrl: '',
        sourceLanguage: 'zh-CN',
        requiresLogin: false
      }
    };
  }

  /**
   * 保存漫画的阅读设置到数据库
   * @param comicId 漫画ID
   * @param settings 阅读设置
   * @param userId 用户ID
   */
  public static async saveReadingSettings(comicId: string, settings: ReadingSettings, userId: string = 'default_user'): Promise<void> {
    const dataManager = DataManager.getInstance();
    
    try {
      const settingKey = `manga_settings_${comicId}`;
      const settingsJson = JSON.stringify(settings);
      
      await dataManager.saveUserSetting(userId, settingKey, settingsJson);
      logger.info(TAG, `成功保存漫画 ${comicId} 的阅读设置到数据库`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存漫画 ${comicId} 的阅读设置失败: ${errorMessage}`);
      // 确保throw的是Error对象
      throw error instanceof Error ? error : new Error(errorMessage);
    }
  }
}