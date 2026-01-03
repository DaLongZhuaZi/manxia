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
  PageTurnAnimationType,
  DEFAULT_READING_SETTINGS
} from '../../Models/MangaModels';
import { ComicInfo, ReadHistory, OnlineComicInfo, UserSettingsDatabaseRecord } from '../Data/DataManager';
import { MangaStatus, ReadingStatus, StatusConverter } from '../Types/StatusEnums';
import { DataManager } from '../Data/DataManager';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';
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
      },
      contentType: comic.contentType || 'manga',
      isNSFW: comic.isNSFW === 1 || comic.isNSFW === true,
      isPrivate: comic.isPrivate === 1 || comic.isPrivate === true
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
    logger.debug(TAG, `[NSFW调试] ComicInfo.isNSFW=${comic.isNSFW}, 类型=${typeof comic.isNSFW}`);
    
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

    // 从数据库加载阅读设置（传入sourceId以支持图源级别设置）
    const readingSettings = await ComicConverter.loadReadingSettings(comic.id, userId, comic.sourceId);
    logger.debug(TAG, `加载的阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}, animation=${readingSettings.pageTurnAnimation}`);

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
      },
      contentType: comic.contentType || 'manga',
      isNSFW: comic.isNSFW === 1 || comic.isNSFW === true,
      isPrivate: comic.isPrivate === 1 || comic.isPrivate === true
    };
  }

  /**
   * 从数据库加载漫画的阅读设置
   * 设置优先级：单本漫画设置 > 图源设置 > 全局设置 > 默认值
   * @param comicId 漫画ID
   * @param userId 用户ID
   * @param sourceId 图源ID（可选，用于加载图源级别设置）
   * @returns Promise<ReadingSettings> 阅读设置
   */
  public static async loadReadingSettings(comicId: string, userId: string = 'default_user', sourceId?: string): Promise<ReadingSettings> {
    const dataManager = DataManager.getInstance();
    const settingsManager = SettingsManager.getInstance();
    
    try {
      // 1. 首先尝试从user_settings表加载单本漫画的设置（最高优先级）
      const settingKey = `manga_settings_${comicId}`;
      const settingsJson = await dataManager.getUserSetting(userId, settingKey);
      
      if (settingsJson) {
        // 解析JSON字符串
        const settings = JSON.parse(settingsJson) as ReadingSettings;
        logger.info(TAG, `成功从数据库加载漫画 ${comicId} 的独立阅读设置`);
        return settings;
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `加载漫画 ${comicId} 的阅读设置失败: ${errorMessage}`);
    }
    
    // 2. 漫画没有独立设置，尝试加载图源级别设置
    logger.info(TAG, `漫画 ${comicId} 未找到独立设置，尝试加载图源/全局设置`);
    
    let sourceSettingsEnabled = false;
    let sourceMode: ReadingMode | null = null;
    let sourceDirection: ReadingDirection | null = null;
    let sourceAnimation: PageTurnAnimationType | null = null;
    
    logger.info(TAG, `loadReadingSettings 参数: comicId=${comicId}, userId=${userId}, sourceId=${sourceId}`);
    
    if (sourceId) {
      try {
        const sid = Number(sourceId);
        logger.info(TAG, `解析后的图源ID: sid=${sid}, isNaN=${isNaN(sid)}`);
        if (!isNaN(sid) && sid > 0) {
          // 检查图源漫画设置是否启用
          const enabledRecord: UserSettingsDatabaseRecord | null = await dataManager.getSourceUserSetting(sid, 'manga.settingsEnabled');
          logger.info(TAG, `图源设置启用记录: ${JSON.stringify(enabledRecord)}`);
          sourceSettingsEnabled = enabledRecord?.settingValue === '1' || enabledRecord?.settingValue === 'true';
          
          if (sourceSettingsEnabled) {
            logger.info(TAG, `图源 ${sid} 的漫画默认设置已启用`);
            
            const modeRecord: UserSettingsDatabaseRecord | null = await dataManager.getSourceUserSetting(sid, 'manga.readingMode');
            const directionRecord: UserSettingsDatabaseRecord | null = await dataManager.getSourceUserSetting(sid, 'manga.readingDirection');
            const animationRecord: UserSettingsDatabaseRecord | null = await dataManager.getSourceUserSetting(sid, 'manga.pageTurnAnimation');
            
            logger.info(TAG, `图源设置记录: mode=${JSON.stringify(modeRecord)}, direction=${JSON.stringify(directionRecord)}, animation=${JSON.stringify(animationRecord)}`);
            
            if (modeRecord?.settingValue) {
              sourceMode = modeRecord.settingValue as ReadingMode;
            }
            if (directionRecord?.settingValue) {
              sourceDirection = directionRecord.settingValue as ReadingDirection;
            }
            if (animationRecord?.settingValue) {
              sourceAnimation = animationRecord.settingValue as PageTurnAnimationType;
            }
            
            logger.info(TAG, `图源设置: mode=${sourceMode}, direction=${sourceDirection}, animation=${sourceAnimation}`);
          }
        }
      } catch (sourceErr) {
        logger.warn(TAG, `加载图源设置失败: ${String(sourceErr)}`);
      }
    }
    
    // 3. 加载全局设置
    const globalMode = settingsManager.getString(SettingKeys.GLOBAL_READING_MODE, '') as ReadingMode | '';
    const globalDirection = settingsManager.getString(SettingKeys.GLOBAL_READING_DIRECTION, '') as ReadingDirection | '';
    const globalAnimation = settingsManager.getString(SettingKeys.GLOBAL_PAGE_TURN_ANIMATION, '') as PageTurnAnimationType | '';
    const globalKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, DEFAULT_READING_SETTINGS.keepScreenOn);
    const globalVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, DEFAULT_READING_SETTINGS.volumeKeyNavigation);
    
    logger.info(TAG, `全局设置: mode=${globalMode}, direction=${globalDirection}, animation=${globalAnimation}`);
    
    // 4. 按优先级合并设置：图源设置 > 全局设置 > 默认值
    let finalMode: ReadingMode = DEFAULT_READING_SETTINGS.readingMode;
    let finalDirection: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
    let finalAnimation: PageTurnAnimationType = DEFAULT_READING_SETTINGS.pageTurnAnimation;
    
    // 阅读模式
    if (sourceSettingsEnabled && sourceMode) {
      finalMode = sourceMode;
      logger.debug(TAG, `使用图源阅读模式: ${finalMode}`);
    } else if (globalMode) {
      finalMode = globalMode;
      logger.debug(TAG, `使用全局阅读模式: ${finalMode}`);
    }
    
    // 阅读方向
    if (sourceSettingsEnabled && sourceDirection) {
      finalDirection = sourceDirection;
      logger.debug(TAG, `使用图源阅读方向: ${finalDirection}`);
    } else if (globalDirection) {
      finalDirection = globalDirection;
      logger.debug(TAG, `使用全局阅读方向: ${finalDirection}`);
    } else if (finalMode === ReadingMode.WEBTOON) {
      finalDirection = ReadingDirection.TOP_TO_BOTTOM;
      logger.debug(TAG, `条漫模式自动设置阅读方向: ${finalDirection}`);
    }
    
    // 翻页动画
    if (sourceSettingsEnabled && sourceAnimation) {
      finalAnimation = sourceAnimation;
      logger.debug(TAG, `使用图源翻页动画: ${finalAnimation}`);
    } else if (globalAnimation) {
      finalAnimation = globalAnimation;
      logger.debug(TAG, `使用全局翻页动画: ${finalAnimation}`);
    }
    
    logger.info(TAG, `最终设置: mode=${finalMode}, direction=${finalDirection}, animation=${finalAnimation}`);

    const fallbackSettings: ReadingSettings = {
      readingMode: finalMode,
      readingDirection: finalDirection,
      brightness: DEFAULT_READING_SETTINGS.brightness,
      keepScreenOn: globalKeepScreenOn,
      pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
      showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: finalAnimation,
      doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: globalVolumeKeyNav,
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

    // 从数据库加载阅读设置（传入sourceId以支持图源级别设置）
    const readingSettings = await ComicConverter.loadReadingSettings(onlineComic.id, userId, onlineComic.sourceId);
    logger.debug(TAG, `加载的阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}, animation=${readingSettings.pageTurnAnimation}`);

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

    const isNSFWBoolean = onlineComic.isNSFW === 1;
    logger.debug(TAG, `[NSFW调试] convertOnlineComicInfoToMangaAsync: title="${onlineComic.title}", OnlineComicInfo.isNSFW=${onlineComic.isNSFW}, Manga.isNSFW=${isNSFWBoolean}`);
    
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
      },
      contentType: 'manga',
      isNSFW: isNSFWBoolean,
      isPrivate: onlineComic.isPrivate === 1
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