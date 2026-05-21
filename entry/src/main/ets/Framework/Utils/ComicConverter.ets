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
  DoublePagePortraitLayout,
  DoublePageVerticalDirection,
  DEFAULT_READING_SETTINGS
} from '../../Models/MangaModels';
import { ComicInfo, ReadHistory, OnlineComicInfo, UserSettingsDatabaseRecord } from '../Data/DataManager';
import { ComicSourceDatabaseRecord } from '../Database/DatabaseTypes';
import { MangaStatus, ReadingStatus, StatusConverter } from '../Types/StatusEnums';
import { DataManager } from '../Data/DataManager';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';
import { logger } from '../../Utils/Logger';

const TAG = 'ComicConverter';

interface PendingReadingSettingsSaveState {
  latestSettings: ReadingSettings | null;
  runningPromise: Promise<void> | null;
}

interface SourceSettingsSnapshot {
  settingsEnabled: boolean;
  readingMode: ReadingMode | null;
  readingDirection: ReadingDirection | null;
  pageTurnAnimation: PageTurnAnimationType | null;
}

export interface PreloadedComicConversionContext {
  favoriteComicIds: Set<string>;
  latestReadHistoryMap: Map<string, ReadHistory>;
  userSettings: Map<string, UserSettingsDatabaseRecord>;
  sourceSettingsBySourceId: Map<number, SourceSettingsSnapshot>;
  comicSourceRecordsBySourceId: Map<number, ComicSourceDatabaseRecord>;
}

/**
 * 漫画数据转换工具类
 */
export class ComicConverter {
  private static readingSettingsSaveStates: Map<string, PendingReadingSettingsSaveState> =
    new Map<string, PendingReadingSettingsSaveState>();

  private static getImageSourceType(path: string): ImageSourceType {
    const src: string = path;
    if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
      return ImageSourceType.NETWORK;
    }
    if (src.indexOf('$rawfile(') === 0) {
      return ImageSourceType.RAWFILE;
    }
    return ImageSourceType.LOCAL;
  }

  private static buildDefaultMetadata(author: string, tags: string[], addTime: number): MangaMetadata {
    return {
      authors: author ? [author] : [],
      publisher: '',
      publicationYear: new Date(addTime).getFullYear(),
      genres: tags,
      artists: [],
      themes: [],
      demographics: []
    };
  }

  private static cloneReadingSettings(settings: ReadingSettings): ReadingSettings {
    const lockMode: boolean = settings.lockMode ??
      settings.lockOrientation ??
      DEFAULT_READING_SETTINGS.lockMode ??
      DEFAULT_READING_SETTINGS.lockOrientation ??
      false;
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: lockMode,
      lockOrientation: lockMode,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      doublePageVerticalDirection: settings.doublePageVerticalDirection ??
        DEFAULT_READING_SETTINGS.doublePageVerticalDirection ??
        DoublePageVerticalDirection.TOP_TO_BOTTOM,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: settings.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: settings.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
  }

  private static normalizePageTurnAnimationForMode(
    animationType: PageTurnAnimationType,
    readingMode: ReadingMode,
    doublePagePortraitLayout: DoublePagePortraitLayout
  ): PageTurnAnimationType {
    if (readingMode === ReadingMode.DOUBLE_PAGE && doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      return PageTurnAnimationType.SLIDE;
    }
    return animationType;
  }

  private static normalizeReadingSettings(settings: ReadingSettings | null | undefined): ReadingSettings {
    const base = settings || DEFAULT_READING_SETTINGS;
    const filterSettings = base.filterSettings || DEFAULT_READING_SETTINGS.filterSettings;
    const readingMode: ReadingMode = base.readingMode ?? DEFAULT_READING_SETTINGS.readingMode;
    const doublePagePortraitLayout: DoublePagePortraitLayout =
      base.doublePagePortraitLayout ?? DEFAULT_READING_SETTINGS.doublePagePortraitLayout;
    let readingDirection: ReadingDirection = base.readingDirection ?? DEFAULT_READING_SETTINGS.readingDirection;

    if (readingDirection === ReadingDirection.VERTICAL) {
      readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }

    if (readingMode === ReadingMode.DOUBLE_PAGE) {
      if (doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
        readingDirection = ReadingDirection.TOP_TO_BOTTOM;
      } else if (readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
        readingDirection = ReadingDirection.LEFT_TO_RIGHT;
      }
    } else if ((readingMode === ReadingMode.WEBTOON ||
      readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      readingMode === ReadingMode.CONTINUOUS_VERTICAL) &&
      readingDirection !== ReadingDirection.TOP_TO_BOTTOM) {
      readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    } else if (readingMode === ReadingMode.CONTINUOUS_SCROLL &&
      readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      readingDirection = ReadingDirection.LEFT_TO_RIGHT;
    }

    const pageTurnAnimation: PageTurnAnimationType = ComicConverter.normalizePageTurnAnimationForMode(
      base.pageTurnAnimation ?? DEFAULT_READING_SETTINGS.pageTurnAnimation,
      readingMode,
      doublePagePortraitLayout
    );

    return ComicConverter.cloneReadingSettings({
      readingMode: readingMode,
      readingDirection: readingDirection,
      brightness: base.brightness ?? DEFAULT_READING_SETTINGS.brightness,
      keepScreenOn: base.keepScreenOn ?? DEFAULT_READING_SETTINGS.keepScreenOn,
      lockDeviceOrientation: base.lockDeviceOrientation ?? DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: base.lockMode ?? base.lockOrientation ?? DEFAULT_READING_SETTINGS.lockMode ?? false,
      lockOrientation: base.lockMode ?? base.lockOrientation ?? DEFAULT_READING_SETTINGS.lockMode ?? false,
      pageSpacing: base.pageSpacing ?? DEFAULT_READING_SETTINGS.pageSpacing,
      showPageInfo: base.showPageInfo ?? DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: base.showPageIndicator ?? DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: base.fitMode ?? DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: base.autoPageTurnInterval ?? DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: base.skipIntroPages ?? DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: pageTurnAnimation,
      doublePagePortraitLayout: doublePagePortraitLayout,
      doublePageVerticalDirection: base.doublePageVerticalDirection ??
        DEFAULT_READING_SETTINGS.doublePageVerticalDirection ??
        DoublePageVerticalDirection.TOP_TO_BOTTOM,
      filterSettings: {
        enabled: filterSettings.enabled ?? DEFAULT_READING_SETTINGS.filterSettings.enabled,
        brightness: filterSettings.brightness ?? DEFAULT_READING_SETTINGS.filterSettings.brightness,
        contrast: filterSettings.contrast ?? DEFAULT_READING_SETTINGS.filterSettings.contrast,
        saturation: filterSettings.saturation ?? DEFAULT_READING_SETTINGS.filterSettings.saturation,
        hue: filterSettings.hue ?? DEFAULT_READING_SETTINGS.filterSettings.hue,
        gamma: filterSettings.gamma ?? DEFAULT_READING_SETTINGS.filterSettings.gamma,
        sepia: filterSettings.sepia ?? DEFAULT_READING_SETTINGS.filterSettings.sepia,
        invert: filterSettings.invert ?? DEFAULT_READING_SETTINGS.filterSettings.invert,
        grayscale: filterSettings.grayscale ?? DEFAULT_READING_SETTINGS.filterSettings.grayscale,
        blur: filterSettings.blur ?? DEFAULT_READING_SETTINGS.filterSettings.blur
      },
      volumeKeyNavigation: base.volumeKeyNavigation ?? DEFAULT_READING_SETTINGS.volumeKeyNavigation,
      curlBackOpacity: base.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: base.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: base.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: base.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync
    });
  }

  private static convertReadHistoryToProgress(history: ReadHistory | null): ReadingProgress {
    if (history !== null) {
      return {
        currentChapterId: history.chapterId || '',
        currentPageIndex: history.pageIndex || 0,
        lastReadAt: history.readTime || 0,
        readingStatus: ReadingStatus.READING,
        totalReadingTime: (history.readDuration || 0) / 1000 / 60,
        readingPercentage: 0
      };
    }
    return {
      currentChapterId: '',
      currentPageIndex: 0,
      lastReadAt: 0,
      readingStatus: ReadingStatus.UNREAD,
      totalReadingTime: 0,
      readingPercentage: 0
    };
  }

  private static async resolveSourceSettingsSnapshot(
    dataManager: DataManager,
    sourceId: string | undefined,
    userId: string,
    preloadedContext?: PreloadedComicConversionContext
  ): Promise<SourceSettingsSnapshot> {
    const emptySnapshot: SourceSettingsSnapshot = {
      settingsEnabled: false,
      readingMode: null,
      readingDirection: null,
      pageTurnAnimation: null
    };
    if (!sourceId) {
      return emptySnapshot;
    }

    const sid = Number(sourceId);
    if (isNaN(sid) || sid <= 0) {
      return emptySnapshot;
    }

    if (preloadedContext) {
      const cachedSnapshot = preloadedContext.sourceSettingsBySourceId.get(sid);
      if (cachedSnapshot) {
        return cachedSnapshot;
      }
    }

    try {
      const settingsMap = await dataManager.getSourceUserSettings(sid, [
        'manga.settingsEnabled',
        'manga.readingMode',
        'manga.readingDirection',
        'manga.pageTurnAnimation'
      ]);
      const enabledRecord = settingsMap.get('manga.settingsEnabled');
      const settingsEnabled = enabledRecord?.settingValue === '1' || enabledRecord?.settingValue === 'true';
      return {
        settingsEnabled: settingsEnabled,
        readingMode: settingsMap.get('manga.readingMode')?.settingValue as ReadingMode | null,
        readingDirection: settingsMap.get('manga.readingDirection')?.settingValue as ReadingDirection | null,
        pageTurnAnimation: settingsMap.get('manga.pageTurnAnimation')?.settingValue as PageTurnAnimationType | null
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `加载图源设置快照失败: sourceId=${sourceId}, userId=${userId}, error=${errorMessage}`);
      return emptySnapshot;
    }
  }

  private static async flushReadingSettingsSaveQueue(
    saveKey: string,
    comicId: string,
    userId: string,
    state: PendingReadingSettingsSaveState
  ): Promise<void> {
    try {
      while (state.latestSettings !== null) {
        const snapshot = state.latestSettings;
        state.latestSettings = null;
        await ComicConverter.saveReadingSettingsInternal(comicId, snapshot, userId);
      }
    } finally {
      state.runningPromise = null;
      if (state.latestSettings === null) {
        ComicConverter.readingSettingsSaveStates.delete(saveKey);
      }
    }
  }

  private static async saveReadingSettingsInternal(
    comicId: string,
    settings: ReadingSettings,
    userId: string
  ): Promise<void> {
    const dataManager = DataManager.getInstance();
    const settingKey = `manga_settings_${comicId}`;
    const snapshot = ComicConverter.normalizeReadingSettings(settings);
    const settingsJson = JSON.stringify(snapshot);

    try {
      await dataManager.saveUserSetting(userId, settingKey, settingsJson);
      logger.info(TAG, `漫画阅读设置保存成功: comicId=${comicId}, userId=${userId}, readingMode=${snapshot.readingMode}, pageTurnAnimation=${snapshot.pageTurnAnimation}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存漫画阅读设置失败: comicId=${comicId}, userId=${userId}, 错误=${errorMessage}`);
      throw error instanceof Error ? error : new Error(errorMessage);
    }
  }
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
      coverImagePath: comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl,
      coverSourceType: detectImageSourceType(comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl),
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
    const readingSettings = await ComicConverter.loadReadingSettings(comic.id, userId, comic.sourceId);
    logger.debug(TAG, `加载的阅读设置: mode=${readingSettings.readingMode}, direction=${readingSettings.readingDirection}, animation=${readingSettings.pageTurnAnimation}`);
    const readingProgress = await ComicConverter.loadReadingProgress(comic.id, userId);
    logger.debug(TAG, `加载的阅读进度: chapter=${readingProgress.currentChapterId}, page=${readingProgress.currentPageIndex}`);

    let favorited: boolean = false;
    try {
      const dm = DataManager.getInstance();
      const favoriteComicIds = await dm.getFavoriteComicIdSet(userId);
      favorited = favoriteComicIds.has(comic.id);
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
      coverImagePath: comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl,
      coverSourceType: ComicConverter.getImageSourceType(comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl),
      status: StatusConverter.toMangaStatus(comic.status),
      metadata: ComicConverter.buildDefaultMetadata(comic.author, comic.tags ? comic.tags : [], comic.addTime),
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
        return ComicConverter.normalizeReadingSettings(settings);
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
    const globalBrightness = settingsManager.getNumber(SettingKeys.GLOBAL_BRIGHTNESS, DEFAULT_READING_SETTINGS.brightness);
    const globalPageSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_PAGE_SPACING, DEFAULT_READING_SETTINGS.pageSpacing);
    const globalShowPageInfo = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INFO, DEFAULT_READING_SETTINGS.showPageInfo);
    const globalShowPageIndicator = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INDICATOR, DEFAULT_READING_SETTINGS.showPageIndicator);
    const globalFitMode = settingsManager.getString(SettingKeys.GLOBAL_MANGA_FIT_MODE, DEFAULT_READING_SETTINGS.fitMode);
    const globalAutoPageTurnInterval = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_AUTO_PAGE_TURN_INTERVAL, DEFAULT_READING_SETTINGS.autoPageTurnInterval);
    const globalSkipIntroPages = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_SKIP_INTRO_PAGES, DEFAULT_READING_SETTINGS.skipIntroPages);
    const globalDoublePagePortraitLayout = settingsManager.getString(
      SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT,
      DEFAULT_READING_SETTINGS.doublePagePortraitLayout
    ) as DoublePagePortraitLayout;
    const globalDoublePageVerticalDirection = settingsManager.getString(
      SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_VERTICAL_DIRECTION,
      DEFAULT_READING_SETTINGS.doublePageVerticalDirection ?? DoublePageVerticalDirection.TOP_TO_BOTTOM
    ) as DoublePageVerticalDirection;
    const globalCurlBackOpacity = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_CURL_BACK_OPACITY, DEFAULT_READING_SETTINGS.curlBackOpacity);
    const globalWebtoonLeftMargin = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN, DEFAULT_READING_SETTINGS.webtoonLeftMargin);
    const globalWebtoonRightMargin = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN, DEFAULT_READING_SETTINGS.webtoonRightMargin);
    const globalWebtoonMarginSync = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_WEBTOON_MARGIN_SYNC, DEFAULT_READING_SETTINGS.webtoonMarginSync);
    
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
      brightness: Math.max(0.1, Math.min(2.0, globalBrightness)),
      keepScreenOn: globalKeepScreenOn,
      lockDeviceOrientation: DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: DEFAULT_READING_SETTINGS.lockMode ?? false,
      lockOrientation: DEFAULT_READING_SETTINGS.lockMode ?? false,
      pageSpacing: Math.max(0, Math.min(50, Math.round(globalPageSpacing))),
      showPageInfo: globalShowPageInfo,
      showPageIndicator: globalShowPageIndicator,
      fitMode: globalFitMode,
      autoPageTurnInterval: Math.max(0, Math.min(60, Math.round(globalAutoPageTurnInterval))),
      skipIntroPages: Math.max(0, Math.min(20, Math.round(globalSkipIntroPages))),
      pageTurnAnimation: finalAnimation,
      doublePagePortraitLayout: globalDoublePagePortraitLayout,
      doublePageVerticalDirection: globalDoublePageVerticalDirection,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: globalVolumeKeyNav,
      curlBackOpacity: Math.max(50, Math.min(100, Math.round(globalCurlBackOpacity))),
      webtoonLeftMargin: Math.max(0, Math.min(50, Math.round(globalWebtoonLeftMargin))),
      webtoonRightMargin: Math.max(0, Math.min(50, Math.round(globalWebtoonRightMargin))),
      webtoonMarginSync: globalWebtoonMarginSync
    };
    return ComicConverter.normalizeReadingSettings(fallbackSettings);
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

  public static async buildPreloadedConversionContext(
    comics: ComicInfo[],
    onlineComics: OnlineComicInfo[],
    userId: string = 'default_user'
  ): Promise<PreloadedComicConversionContext> {
    const dataManager = DataManager.getInstance();
    const favoriteComicIds = await dataManager.getFavoriteComicIdSet(userId);

    const allComicIds: string[] = [];
    for (let index = 0; index < comics.length; index++) {
      allComicIds.push(comics[index].id);
    }
    for (let index = 0; index < onlineComics.length; index++) {
      allComicIds.push(onlineComics[index].id);
    }

    const latestReadHistoryMap = await dataManager.getLatestReadHistoryMap(allComicIds, userId);

    const settingKeys: string[] = [];
    for (let index = 0; index < comics.length; index++) {
      settingKeys.push(`manga_settings_${comics[index].id}`);
    }
    for (let index = 0; index < onlineComics.length; index++) {
      settingKeys.push(`manga_settings_${onlineComics[index].id}`);
    }
    const userSettings = await dataManager.getSettingsByKeys(settingKeys, userId);

    const sourceIdValues: number[] = [];
    for (let index = 0; index < comics.length; index++) {
      const sourceId = Number(comics[index].sourceId);
      if (!isNaN(sourceId) && sourceId > 0) {
        sourceIdValues.push(sourceId);
      }
    }
    for (let index = 0; index < onlineComics.length; index++) {
      const sourceId = Number(onlineComics[index].sourceId);
      if (!isNaN(sourceId) && sourceId > 0) {
        sourceIdValues.push(sourceId);
      }
    }

    const comicSourceRecordsBySourceId = await dataManager.getComicSourcesByIds(sourceIdValues);
    const sourceSettingsBySourceId: Map<number, SourceSettingsSnapshot> = new Map<number, SourceSettingsSnapshot>();
    for (let index = 0; index < sourceIdValues.length; index++) {
      const sourceId = sourceIdValues[index];
      if (sourceSettingsBySourceId.has(sourceId)) {
        continue;
      }
      const sourceRecord = comicSourceRecordsBySourceId.get(sourceId);
      const keyIdentifier = sourceRecord?.pkg || `id_${String(sourceId)}`;
      const sourceSettingsKeys = [
        `source:${keyIdentifier}:manga.settingsEnabled`,
        `source:${keyIdentifier}:manga.readingMode`,
        `source:${keyIdentifier}:manga.readingDirection`,
        `source:${keyIdentifier}:manga.pageTurnAnimation`
      ];
      const sourceSettings = await dataManager.getSettingsByKeys(sourceSettingsKeys, userId);
      const enabledRecord = sourceSettings.get(`source:${keyIdentifier}:manga.settingsEnabled`);
      sourceSettingsBySourceId.set(sourceId, {
        settingsEnabled: enabledRecord?.settingValue === '1' || enabledRecord?.settingValue === 'true',
        readingMode: sourceSettings.get(`source:${keyIdentifier}:manga.readingMode`)?.settingValue as ReadingMode | null,
        readingDirection: sourceSettings.get(`source:${keyIdentifier}:manga.readingDirection`)?.settingValue as ReadingDirection | null,
        pageTurnAnimation: sourceSettings.get(`source:${keyIdentifier}:manga.pageTurnAnimation`)?.settingValue as PageTurnAnimationType | null
      });
    }

    return {
      favoriteComicIds: favoriteComicIds,
      latestReadHistoryMap: latestReadHistoryMap,
      userSettings: userSettings,
      sourceSettingsBySourceId: sourceSettingsBySourceId,
      comicSourceRecordsBySourceId: comicSourceRecordsBySourceId
    };
  }

  public static async convertComicInfoToMangaWithContext(
    comic: ComicInfo,
    userId: string,
    preloadedContext: PreloadedComicConversionContext
  ): Promise<Manga> {
    const settingsKey = `manga_settings_${comic.id}`;
    let readingSettings: ReadingSettings;
    const directSettingsRecord = preloadedContext.userSettings.get(settingsKey);
    if (directSettingsRecord && directSettingsRecord.settingValue) {
      readingSettings = ComicConverter.normalizeReadingSettings(JSON.parse(directSettingsRecord.settingValue) as ReadingSettings);
    } else {
      const sourceSnapshot = await ComicConverter.resolveSourceSettingsSnapshot(
        DataManager.getInstance(),
        comic.sourceId,
        userId,
        preloadedContext
      );
      const settingsManager = SettingsManager.getInstance();
      const globalMode = settingsManager.getString(SettingKeys.GLOBAL_READING_MODE, '') as ReadingMode | '';
      const globalDirection = settingsManager.getString(SettingKeys.GLOBAL_READING_DIRECTION, '') as ReadingDirection | '';
      const globalAnimation = settingsManager.getString(SettingKeys.GLOBAL_PAGE_TURN_ANIMATION, '') as PageTurnAnimationType | '';
      const globalKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, DEFAULT_READING_SETTINGS.keepScreenOn);
      const globalVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, DEFAULT_READING_SETTINGS.volumeKeyNavigation);
      const globalBrightness = settingsManager.getNumber(SettingKeys.GLOBAL_BRIGHTNESS, DEFAULT_READING_SETTINGS.brightness);
      const globalPageSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_PAGE_SPACING, DEFAULT_READING_SETTINGS.pageSpacing);
      const globalShowPageInfo = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INFO, DEFAULT_READING_SETTINGS.showPageInfo);
      const globalShowPageIndicator = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INDICATOR, DEFAULT_READING_SETTINGS.showPageIndicator);
      const globalFitMode = settingsManager.getString(SettingKeys.GLOBAL_MANGA_FIT_MODE, DEFAULT_READING_SETTINGS.fitMode);
      const globalAutoPageTurnInterval = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_AUTO_PAGE_TURN_INTERVAL, DEFAULT_READING_SETTINGS.autoPageTurnInterval);
      const globalSkipIntroPages = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_SKIP_INTRO_PAGES, DEFAULT_READING_SETTINGS.skipIntroPages);
      const globalDoublePagePortraitLayout = settingsManager.getString(
        SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT,
        DEFAULT_READING_SETTINGS.doublePagePortraitLayout
      ) as DoublePagePortraitLayout;
      const globalDoublePageVerticalDirection = settingsManager.getString(
        SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_VERTICAL_DIRECTION,
        DEFAULT_READING_SETTINGS.doublePageVerticalDirection ?? DoublePageVerticalDirection.TOP_TO_BOTTOM
      ) as DoublePageVerticalDirection;
      const globalCurlBackOpacity = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_CURL_BACK_OPACITY, DEFAULT_READING_SETTINGS.curlBackOpacity);
      const globalWebtoonLeftMargin = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN, DEFAULT_READING_SETTINGS.webtoonLeftMargin);
      const globalWebtoonRightMargin = settingsManager.getNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN, DEFAULT_READING_SETTINGS.webtoonRightMargin);
      const globalWebtoonMarginSync = settingsManager.getBoolean(SettingKeys.GLOBAL_MANGA_WEBTOON_MARGIN_SYNC, DEFAULT_READING_SETTINGS.webtoonMarginSync);

      let finalMode: ReadingMode = DEFAULT_READING_SETTINGS.readingMode;
      let finalDirection: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
      let finalAnimation: PageTurnAnimationType = DEFAULT_READING_SETTINGS.pageTurnAnimation;
      if (sourceSnapshot.settingsEnabled && sourceSnapshot.readingMode) {
        finalMode = sourceSnapshot.readingMode;
      } else if (globalMode) {
        finalMode = globalMode;
      }
      if (sourceSnapshot.settingsEnabled && sourceSnapshot.readingDirection) {
        finalDirection = sourceSnapshot.readingDirection;
      } else if (globalDirection) {
        finalDirection = globalDirection;
      } else if (finalMode === ReadingMode.WEBTOON) {
        finalDirection = ReadingDirection.TOP_TO_BOTTOM;
      }
      if (sourceSnapshot.settingsEnabled && sourceSnapshot.pageTurnAnimation) {
        finalAnimation = sourceSnapshot.pageTurnAnimation;
      } else if (globalAnimation) {
        finalAnimation = globalAnimation;
      }

      readingSettings = ComicConverter.normalizeReadingSettings({
        readingMode: finalMode,
        readingDirection: finalDirection,
        brightness: Math.max(0.1, Math.min(2.0, globalBrightness)),
        keepScreenOn: globalKeepScreenOn,
        lockDeviceOrientation: DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
        lockMode: DEFAULT_READING_SETTINGS.lockMode ?? false,
        lockOrientation: DEFAULT_READING_SETTINGS.lockMode ?? false,
        pageSpacing: Math.max(0, Math.min(50, Math.round(globalPageSpacing))),
        showPageInfo: globalShowPageInfo,
        showPageIndicator: globalShowPageIndicator,
        fitMode: globalFitMode,
        autoPageTurnInterval: Math.max(0, Math.min(60, Math.round(globalAutoPageTurnInterval))),
        skipIntroPages: Math.max(0, Math.min(20, Math.round(globalSkipIntroPages))),
        pageTurnAnimation: finalAnimation,
        doublePagePortraitLayout: globalDoublePagePortraitLayout,
        doublePageVerticalDirection: globalDoublePageVerticalDirection,
        filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
        volumeKeyNavigation: globalVolumeKeyNav,
        curlBackOpacity: Math.max(50, Math.min(100, Math.round(globalCurlBackOpacity))),
        webtoonLeftMargin: Math.max(0, Math.min(50, Math.round(globalWebtoonLeftMargin))),
        webtoonRightMargin: Math.max(0, Math.min(50, Math.round(globalWebtoonRightMargin))),
        webtoonMarginSync: globalWebtoonMarginSync
      });
    }

    const latestHistory = preloadedContext.latestReadHistoryMap.get(comic.id) || null;
    const readingProgress = ComicConverter.convertReadHistoryToProgress(latestHistory);
    const favorited = preloadedContext.favoriteComicIds.has(comic.id);
    return {
      id: comic.id,
      title: comic.title,
      alternativeTitles: [],
      description: comic.description,
      coverImagePath: comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl,
      coverSourceType: ComicConverter.getImageSourceType(comic.coverLocalPath && comic.coverLocalPath.length > 0 ? comic.coverLocalPath : comic.coverUrl),
      status: StatusConverter.toMangaStatus(comic.status),
      metadata: ComicConverter.buildDefaultMetadata(comic.author, comic.tags ? comic.tags : [], comic.addTime),
      chapters: [],
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

  public static async convertOnlineComicInfoToMangaWithContext(
    onlineComic: OnlineComicInfo,
    userId: string,
    preloadedContext: PreloadedComicConversionContext
  ): Promise<Manga> {
    const baseManga = await ComicConverter.convertComicInfoToMangaWithContext({
      id: onlineComic.id,
      title: onlineComic.title,
      author: onlineComic.author,
      description: onlineComic.description,
      coverUrl: onlineComic.coverUrl,
      sourceId: onlineComic.sourceId,
      status: MangaStatus.ONGOING,
      tags: onlineComic.tags,
      rating: onlineComic.rating,
      chapterCount: 0,
      lastUpdateTime: onlineComic.lastUpdateTime,
      addTime: onlineComic.addTime,
      externalId: onlineComic.externalId,
      contentType: 'manga',
      isNSFW: onlineComic.isNSFW === 1,
      isPrivate: onlineComic.isPrivate === 1
    }, userId, preloadedContext);

    const sourceIdNum = Number(onlineComic.sourceId);
    const sourceRecord = !isNaN(sourceIdNum) && sourceIdNum > 0
      ? preloadedContext.comicSourceRecordsBySourceId.get(sourceIdNum)
      : undefined;
    let resolvedSourceName: string = onlineComic.sourceName || sourceRecord?.name || 'WebView Source';
    let resolvedSourcePkg: string = onlineComic.sourcePkg || sourceRecord?.pkg || '';

    return {
      id: baseManga.id,
      title: baseManga.title,
      alternativeTitles: baseManga.alternativeTitles,
      description: baseManga.description,
      coverImagePath: onlineComic.coverUrl,
      coverSourceType: ComicConverter.getImageSourceType(onlineComic.coverUrl),
      status: MangaStatus.ONGOING,
      metadata: baseManga.metadata,
      chapters: baseManga.chapters,
      readingProgress: baseManga.readingProgress,
      bookmarks: baseManga.bookmarks,
      readingSettings: baseManga.readingSettings,
      isFavorite: baseManga.isFavorite,
      addedToLibraryAt: baseManga.addedToLibraryAt,
      lastUpdatedAt: baseManga.lastUpdatedAt,
      sourceInfo: {
        sourceId: onlineComic.sourceId,
        sourceName: resolvedSourceName,
        sourcePkg: resolvedSourcePkg || undefined,
        sourceUrl: '',
        sourceLanguage: 'zh-CN',
        requiresLogin: false
      },
      contentType: baseManga.contentType,
      isNSFW: onlineComic.isNSFW === 1,
      isPrivate: onlineComic.isPrivate === 1
    };
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

    // [修复] 解析sourceName和sourcePkg：如果数据库记录为空，则从comic_source表按sourceId查询并回填
    let resolvedSourceName: string = onlineComic.sourceName || '';
    let resolvedSourcePkg: string = '';
    try {
      const sourceIdNum = Number(onlineComic.sourceId);
      if (!isNaN(sourceIdNum)) {
        const dmResolve: DataManager = DataManager.getInstance();
        const sourceRecord: ComicSourceDatabaseRecord | null = await dmResolve.getComicSourceById(sourceIdNum);
        if (sourceRecord) {
          if (!resolvedSourceName && sourceRecord.name) {
            resolvedSourceName = sourceRecord.name;
            logger.info(TAG, `[修复] 从comic_source表获取sourceName: sourceId=${sourceIdNum}, name="${resolvedSourceName}"`);
            await dmResolve.updateOnlineComicSourceNameById(onlineComic.id, resolvedSourceName);
          }
          if (sourceRecord.pkg) {
            resolvedSourcePkg = sourceRecord.pkg;
          }
        }
      }
    } catch (e) {
      logger.warn(TAG, `解析sourceName/sourcePkg失败: ${String(e)}`);
    }
    if (!resolvedSourceName) {
      resolvedSourceName = 'WebView Source';
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
        sourceName: resolvedSourceName,
        sourcePkg: resolvedSourcePkg || undefined,
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
    const saveKey = `${comicId}|${userId}|reading_settings`;
    let state = ComicConverter.readingSettingsSaveStates.get(saveKey);
    if (!state) {
      state = {
        latestSettings: null,
        runningPromise: null
      };
      ComicConverter.readingSettingsSaveStates.set(saveKey, state);
    }

    state.latestSettings = ComicConverter.normalizeReadingSettings(settings);
    if (state.runningPromise === null) {
      state.runningPromise = ComicConverter.flushReadingSettingsSaveQueue(saveKey, comicId, userId, state);
    }
    return await state.runningPromise;
  }

  private static async saveReadingSettingsLegacy(comicId: string, settings: ReadingSettings, userId: string = 'default_user'): Promise<void> {
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
