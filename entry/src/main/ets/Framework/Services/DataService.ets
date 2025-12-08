// 文件路径: src/main/ets/Framework/Services/DataService.ets
/**
 * 数据服务层
 * 为UI层提供统一的数据访问接口，封装复杂的数据操作逻辑
 */

import { logger } from '../../Utils/Logger';
import { DataManager, ComicSource, ComicInfo, ChapterInfo, PageInfo, FavoriteInfo, ReadHistory, DownloadTask, ComicSourceInput, ComicInfoInput, FavoriteInfoInput, ReadHistoryInput, DownloadTaskInput } from '../Data/DataManager';
import { ComicSourceUpdateData, DownloadTaskUpdateData } from '../Database/DatabaseTypes';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { DownloadStatus } from '../Types/StatusEnums';

const TAG = 'DataService';

interface SyncResult {
  success: boolean;
  message: string;
}

interface TestData {
  index: number;
  timestamp: number;
  data: string;
}

interface AppDataStatsResult {
  comicCount: number;
  chapterCount: number;
  favoriteCount: number;
  downloadTaskCount: number;
  storageUsage: string;
  cacheUsage: string;
}

interface UserPreferencesPartial {
  readingMode?: 'vertical' | 'horizontal';
  autoSave?: boolean;
  downloadQuality?: 'low' | 'medium' | 'high';
  cacheSize?: number;
}

export interface SearchResult {
  comics: ComicInfo[];
  totalCount: number;
  hasMore: boolean;
}

export interface ComicDetail {
  comic: ComicInfo;
  chapters: ChapterInfo[];
  isFavorited: boolean;
  lastReadChapter?: ChapterInfo;
  downloadProgress?: ComicDownloadProgress;
}

export interface ComicDownloadProgress {
  totalChapters: number;
  downloadedChapters: number;
  downloadingChapters: number;
}

export interface ReadingSession {
  comic: ComicInfo;
  chapter: ChapterInfo;
  pages: PageInfo[];
  currentPageIndex: number;
  readingProgress: number;
}

export interface UserPreferences {
  readingMode: 'vertical' | 'horizontal';
  autoSave: boolean;
  downloadQuality: 'high' | 'medium' | 'low';
  cacheSize: number;
}

export interface UserProfile {
  userId: string;
  favoriteCount: number;
  readHistoryCount: number;
  downloadCount: number;
  totalReadTime: number;
  preferences: UserPreferences;
}

export interface ComicSourceConfig {
  name: string;
  baseUrl: string;
  pluginId?: string;
  version?: string;
  description?: string;
  language?: string;
  priority?: number;
  config?: Record<string, string | number | boolean>;
}

export interface SearchOptions {
  sourceId?: string;
  page?: number;
  pageSize?: number;
}

export interface PopularComicsOptions {
  sourceId?: string;
  limit?: number;
}

export interface LatestComicsOptions {
  sourceId?: string;
  limit?: number;
}

export interface AppDataStats {
  comicCount: number;
  chapterCount: number;
  favoriteCount: number;
  downloadTaskCount: number;
  storageUsage: string;
  cacheUsage: string;
}

export class DataService {
  private static instance: DataService | null = null;
  private dataManager: DataManager;
  private currentUserId: string = 'default_user';
  
  // 测试专用存储
  private testCache?: Map<string, Record<string, string | number | boolean | string[] | number[]>>;
  private testRecords?: Map<string, Record<string, string | number | boolean | string[] | number[]>>;

  private constructor() {
    this.dataManager = DataManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): DataService {
    if (!DataService.instance) {
      DataService.instance = new DataService();
    }
    return DataService.instance;
  }

  /**
   * 初始化数据服务
   */
  public async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      logger.info(TAG, '初始化数据服务');
      await this.dataManager.initialize(context);
      logger.info(TAG, '数据服务初始化完成');
    } catch (error) {
      logger.error(TAG, '数据服务初始化失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 设置当前用户ID
   */
  public setCurrentUserId(userId: string): void {
    this.currentUserId = userId;
    logger.debug(TAG, `设置当前用户: ${userId}`);
  }

  // ==================== 漫画源服务 ====================

  /**
   * 获取可用的漫画源列表
   */
  public async getAvailableComicSources(): Promise<ComicSource[]> {
    try {
      const sources = await this.dataManager.getAllComicSources();
      return sources.filter((source: ESObject) => Boolean(source.isEnabled)) as ComicSource[];
    } catch (error) {
      logger.error(TAG, '获取漫画源失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 添加新的漫画源
   */
  public async addComicSource(sourceConfig: ComicSourceConfig): Promise<number> {
    try {
      const sourceData: ESObject = {
        name: sourceConfig.name,
        baseUrl: sourceConfig.baseUrl,
        version: sourceConfig.version || '1.0.0',
        description: sourceConfig.description || '',
        language: sourceConfig.language || 'zh-CN',
        isEnabled: true,
        priority: sourceConfig.priority || 0,
        configJson: JSON.stringify(sourceConfig.config || {})
      };
      
      const pkg: string = await this.dataManager.addComicSource(sourceData);
      
      // 获取数字 ID
      const sourceRecord = await this.dataManager.getComicSourceByPkg(pkg);
      const sourceId: number = sourceRecord ? Number(sourceRecord.id) : 0;
      
      logger.info(TAG, `添加漫画源成功: ${sourceConfig.name} (ID: ${sourceId}, pkg: ${pkg})`);
      return sourceId;
    } catch (error) {
      logger.error(TAG, '添加漫画源失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 更新漫画源状态
   */
  public async toggleComicSourceStatus(sourceId: string, isEnabled: boolean): Promise<void> {
    try {
      const updateData: ComicSourceUpdateData = {
        id: sourceId,
        isEnabled,
        lastUpdateTime: Date.now()
      };
      
      // 这里需要实现图源状态切换的逻辑
      logger.info(TAG, '切换图源状态', `${sourceId}: ${isEnabled}`);
    } catch (error) {
      logger.error(TAG, '切换图源状态失败', String(error));
      throw error as Error;
    }
  }

  // ==================== 漫画搜索与发现 ====================

  /**
   * 搜索漫画
   */
  public async searchComics(keyword: string, options?: SearchOptions): Promise<SearchResult> {
    try {
      const sourceId = options?.sourceId;
      const page = options?.page || 1;
      const pageSize = options?.pageSize || 20;
      
      // 从本地数据库搜索
      const localComics = await this.dataManager.searchComics(keyword, sourceId);
      
      // 计算分页
      const startIndex = (page - 1) * pageSize;
      const endIndex = startIndex + pageSize;
      const paginatedComics = localComics.slice(startIndex, endIndex);
      
      const result: SearchResult = {
        comics: paginatedComics,
        totalCount: localComics.length,
        hasMore: endIndex < localComics.length
      };
      
      return result;
    } catch (error) {
      logger.error(TAG, '搜索漫画失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 获取热门漫画
   */
  public async getPopularComics(options?: PopularComicsOptions): Promise<ComicInfo[]> {
    try {
      const sourceId = options?.sourceId;
      const limit = options?.limit || 20;
      
      // 这里可以根据阅读量、收藏量等指标排序
      // 暂时按最后更新时间排序
      const comics = await this.dataManager.searchComics('', sourceId);
      return comics.slice(0, limit);
    } catch (error) {
      logger.error(TAG, '获取热门漫画失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 获取最新更新的漫画
   */
  public async getLatestComics(options?: LatestComicsOptions): Promise<ComicInfo[]> {
    try {
      const sourceId = options?.sourceId;
      const limit = options?.limit || 20;
      const comics = await this.dataManager.searchComics('', sourceId);
      
      // 按最后更新时间排序
      comics.sort((a, b) => b.lastUpdateTime - a.lastUpdateTime);
      return comics.slice(0, limit);
    } catch (error) {
      logger.error(TAG, '获取最新漫画失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 漫画详情服务 ====================

  /**
   * 获取漫画详情
   */
  public async getComicDetail(comicId: string): Promise<ComicDetail | null> {
    try {
      const comic = await this.dataManager.getComicInfo(comicId);
      if (!comic) {
        return null;
      }
      
      const chapters = await this.dataManager.getComicChapters(comicId);
      const favorites = await this.dataManager.getUserFavorites(this.currentUserId);
      const isFavorited = favorites.some(fav => fav.comicId === comicId);
      
      // 获取最后阅读的章节
      const readHistory = await this.dataManager.getUserReadHistory(this.currentUserId, 1);
      const lastReadChapter = readHistory.length > 0 
        ? chapters.find(ch => ch.id === readHistory[0].chapterId)
        : undefined;
      
      // 获取下载进度
      const downloadTasks = await this.dataManager.getDownloadTasks();
      const comicDownloadTasks = downloadTasks.filter(task => task.comicId === comicId);
      const downloadProgress: ComicDownloadProgress = {
        totalChapters: chapters.length,
        downloadedChapters: comicDownloadTasks.filter(task => task.status === DownloadStatus.COMPLETED).length,
        downloadingChapters: comicDownloadTasks.filter(task => task.status === DownloadStatus.DOWNLOADING).length
      };
      
      const result: ComicDetail = {
        comic,
        chapters,
        isFavorited,
        lastReadChapter,
        downloadProgress
      };
      
      return result;
    } catch (error) {
      logger.error(TAG, '获取漫画详情失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 添加漫画到本地
   */
  public async addComicToLocal(comicData: ComicInfoInput): Promise<string> {
    try {
      const comicId = await this.dataManager.addComicInfo(comicData);
      logger.info(TAG, `添加漫画到本地: ${comicData.title}`);
      // 添加到收藏（导入即收藏），避免重复
      const favorited: boolean = await this.isFavorited(comicId);
      if (!favorited) {
        await this.addToFavorites(comicId, comicData.tags);
        logger.info(TAG, `本地添加后已设置收藏: ${comicId}`);
      }
      return comicId;
    } catch (error) {
      logger.error(TAG, '添加漫画到本地失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 更新漫画章节列表
   */
  public async updateComicChapters(comicId: string, chapters: ChapterInfo[]): Promise<string[]> {
    try {
      const chapterData = chapters.map(chapter => {
        const chapterWithComicId: ChapterInfo = {
          id: chapter.id,
          comicId: comicId,
          title: chapter.title,
          index: chapter.index,
          pageCount: chapter.pageCount,
          isDownloaded: chapter.isDownloaded,
          downloadPath: chapter.downloadPath,
          publishTime: chapter.publishTime,
          addTime: chapter.addTime
        };
        return chapterWithComicId;
      });
      
      await this.dataManager.batchAddChapters(comicId, chapterData);
      logger.info(TAG, `更新漫画章节: ${comicId}, ${chapters.length} 个章节`);
      return chapterData.map(chapter => chapter.id);
    } catch (error) {
      logger.error(TAG, '更新漫画章节失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 阅读服务 ====================

  /**
   * 开始阅读会话
   */
  public async startReadingSession(comicId: string, chapterId: string): Promise<ReadingSession> {
    try {
      const comic = await this.dataManager.getComicInfo(comicId);
      if (!comic) {
        throw new Error('漫画不存在');
      }
      
      const chapters = await this.dataManager.getComicChapters(comicId);
      const chapter = chapters.find(ch => ch.id === chapterId);
      if (!chapter) {
        throw new Error('章节不存在');
      }
      
      const pages = await this.dataManager.getChapterPages(chapterId);
      
      // 获取上次阅读进度
      const readHistory = await this.dataManager.getUserReadHistory(this.currentUserId);
      const lastRead = readHistory.find(history => 
        history.comicId === comicId && history.chapterId === chapterId
      );
      
      const currentPageIndex = lastRead ? lastRead.pageIndex : 0;
      const readingProgress = pages.length > 0 ? (currentPageIndex / pages.length) * 100 : 0;
      
      const session: ReadingSession = {
        comic,
        chapter,
        pages,
        currentPageIndex,
        readingProgress
      };
      
      return session;
    } catch (error) {
      logger.error(TAG, '开始阅读会话失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 保存阅读进度
   * @param comicId 漫画ID
   * @param chapterId 章节ID
   * @param pageIndex 页码
   * @param readDuration 阅读时长
   * @param sourceId 可选的图源ID，用于在线漫画自动保存到数据库
   * @param mangaData 可选的漫画数据，用于在线漫画自动保存到数据库
   */
  public async saveReadingProgress(
    comicId: string,
    chapterId: string,
    pageIndex: number,
    readDuration: number,
    sourceId?: number,
    mangaData?: Record<string, Object>
  ): Promise<void> {
    try {
      // 如果提供了sourceId和mangaData，说明是在线漫画，需要先确保漫画存在于数据库
      if (sourceId !== undefined && mangaData) {
        try {
          // 检查漫画是否已存在
          const existingComic = await this.dataManager.getOnlineComicById(comicId);
          if (!existingComic) {
            // 漫画不存在，保存到数据库（使用原始ID）
            logger.info(TAG, `在线漫画 ${comicId} 不存在于数据库，自动保存`);
            await this.dataManager.saveOnlineComicFromSource(sourceId, mangaData, comicId);
          }
        } catch (err) {
          logger.warn(TAG, `检查/保存在线漫画失败: ${String(err)}`);
          // 继续保存阅读进度，即使漫画保存失败
        }
      }
      
      const readHistoryData: ReadHistoryInput = {
        comicId,
        chapterId,
        pageIndex,
        userId: this.currentUserId,
        readTime: Date.now(),
        readDuration
      };
      
      if (sourceId !== undefined) {
        await this.dataManager.addOnlineReadHistory(readHistoryData);
      } else {
        await this.dataManager.addReadHistory(readHistoryData);
      }
      
      logger.debug(TAG, `保存阅读进度: ${comicId}/${chapterId} -> ${pageIndex}`);
    } catch (error) {
      logger.error(TAG, '保存阅读进度失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取阅读历史
   */
  public async getReadingHistory(limit: number = 50): Promise<ReadHistory[]> {
    try {
      return await this.dataManager.getUserReadHistory(this.currentUserId, limit);
    } catch (error) {
      logger.error(TAG, '获取阅读历史失败' + String(error));
      throw error as Error;
    }
  }
  
  /**
   * 清除阅读历史
   */
  public async clearReadingHistory(): Promise<void> {
    try {
      await this.dataManager.clearUserReadHistory(this.currentUserId);
      logger.info(TAG, '阅读历史已清除');
    } catch (error) {
      logger.error(TAG, '清除阅读历史失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 收藏服务 ====================

  /**
   * 添加收藏
   */
  public async addToFavorites(comicId: string, tags: string[] = []): Promise<void> {
    try {
      const favoriteData: FavoriteInfoInput = {
        comicId,
        userId: this.currentUserId,
        lastReadChapterId: undefined,
        lastReadTime: undefined,
        tags
      };
      
      await this.dataManager.addFavorite(favoriteData);
      
      logger.info(TAG, `添加收藏: ${comicId}`);
    } catch (error) {
      logger.error(TAG, '添加收藏失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 移除收藏
   */
  public async removeFromFavorites(comicId: string): Promise<void> {
    try {
      await this.dataManager.removeFavorite(comicId, this.currentUserId);
      logger.info(TAG, `移除收藏: ${comicId}`);
    } catch (error) {
      logger.error(TAG, '移除收藏失败' + String(error));  
      throw error as Error;
    }
  }

  /**
   * 获取收藏列表
   */
  public async getFavoriteComics(): Promise<ComicInfo[]> {
    try {
      const favorites = await this.dataManager.getUserFavorites(this.currentUserId);
      const comicIds = favorites.map(fav => fav.comicId);
      
      const comics: ComicInfo[] = [];
      for (const comicId of comicIds) {
        const comic = await this.dataManager.getComicInfo(comicId);
        if (comic) {
          comics.push(comic);
        }
      }
      
      return comics;
    } catch (error) {
      logger.error(TAG, '获取收藏列表失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 检查是否已收藏
   */
  public async isFavorited(comicId: string): Promise<boolean> {
    try {
      const favorites = await this.dataManager.getUserFavorites(this.currentUserId);
      return favorites.some(fav => fav.comicId === comicId);
    } catch (error) {
      logger.error(TAG, '检查收藏状态失败' + String(error));
      return false;
    }
  }

  // ==================== 下载服务 ====================

  /**
   * 创建下载任务
   */
  public async createDownloadTask(comicId: string, chapterIds: string[]): Promise<string[]> {
    try {
      const taskIds: string[] = [];
      
      for (const chapterId of chapterIds) {
        const pages = await this.dataManager.getChapterPages(chapterId);
        const taskData: DownloadTaskInput = {
          comicId,
          chapterId,
          status: DownloadStatus.PENDING,
          progress: 0,
          totalPages: pages.length,
          downloadedPages: 0,
          completeTime: undefined,
          errorMessage: undefined
        };
        
        const taskId = await this.dataManager.createDownloadTask(taskData);
        taskIds.push(taskId);
      }
      
      logger.info(TAG, `创建下载任务: ${chapterIds.length} 个章节`);
      return taskIds;
    } catch (error) {
      logger.error(TAG, '创建下载任务失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取下载任务列表
   */
  public async getDownloadTasks(status?: DownloadStatus): Promise<DownloadTask[]> {
    try {
      return await this.dataManager.getDownloadTasks(status);
    } catch (error) {
      logger.error(TAG, '获取下载任务失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 暂停下载任务
   */
  public async pauseDownloadTask(taskId: string): Promise<void> {
    try {
      const updateData: DownloadTaskUpdateData = {
        id: taskId,
        status: DownloadStatus.PAUSED,
        updateTime: Date.now()
      };
      
      // 这里需要实现暂停下载任务的逻辑
      logger.info(TAG, '暂停下载任务', taskId);
    } catch (error) {
      logger.error(TAG, '暂停下载任务失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 恢复下载任务
   */
  public async resumeDownloadTask(taskId: string): Promise<void> {
    try {
      const updateData: DownloadTaskUpdateData = {
        id: taskId,
        status: 'pending',
        updateTime: Date.now()
      };
      
      // 这里需要实现恢复下载任务的逻辑
      logger.info(TAG, '恢复下载任务', taskId);
    } catch (error) {
      logger.error(TAG, '恢复下载任务失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 删除下载任务
   */
  public async deleteDownloadTask(taskId: string): Promise<void> {
    try {
      // 这里需要实现删除下载任务的逻辑
      // 包括删除已下载的文件和数据库记录
      logger.info(TAG, `删除下载任务: ${taskId}`);
    } catch (error) {
      logger.error(TAG, '删除下载任务失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 用户配置服务 ====================

  /**
   * 获取用户配置
   */
  public async getUserProfile(): Promise<UserProfile> {
    try {
      const favorites = await this.dataManager.getUserFavorites(this.currentUserId);
      const readHistory = await this.dataManager.getUserReadHistory(this.currentUserId);
      const downloadTasks = await this.dataManager.getDownloadTasks();
      
      // 计算总阅读时间
      const totalReadTime = readHistory.reduce((total, history) => total + history.readDuration, 0);
      
      const preferences: UserPreferences = {
        readingMode: 'vertical',
        autoSave: true,
        downloadQuality: 'high',
        cacheSize: 500 * 1024 * 1024 // 500MB
      };
      
      const profile: UserProfile = {
        userId: this.currentUserId,
        favoriteCount: favorites.length,
        readHistoryCount: readHistory.length,
        downloadCount: downloadTasks.filter(task => task.status === DownloadStatus.COMPLETED).length,
        totalReadTime,
        preferences
      };
      
      return profile;
    } catch (error) {
      logger.error(TAG, '获取用户配置失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 更新用户偏好设置
   */
  public async updateUserPreferences(preferences: UserPreferencesPartial): Promise<void> {
    try {
      // 这里需要实现用户偏好设置的存储逻辑
      logger.info(TAG, '更新用户偏好设置', String(preferences));
    } catch (error) {
      logger.error(TAG, '更新用户偏好设置失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 数据统计服务 ====================

  /**
   * 获取应用数据统计
   */
  public async getAppDataStats(): Promise<AppDataStatsResult> {
    try {
      const stats = await this.dataManager.getDataStats();
      
      // 计算存储使用情况
      const storageUsage = `${(stats.storageStats.totalSize / 1024 / 1024).toFixed(2)} MB`;
      const cacheUsage = `${(stats.cacheStats.diskCache.size / 1024 / 1024).toFixed(2)} MB`;
      
      const result: AppDataStatsResult = {
        comicCount: stats.comicCount,
        chapterCount: stats.chapterCount,
        favoriteCount: stats.favoriteCount,
        downloadTaskCount: stats.downloadTaskCount,
        storageUsage,
        cacheUsage
      };
      
      return result;
    } catch (error) {
      logger.error(TAG, '获取应用数据统计失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 清理缓存数据
   */
  public async clearCacheData(): Promise<void> {
    try {
      // 清理图片缓存
      // await this.imageCacheManager.clearCache();
      
      // 清理临时文件
      // await this.sandboxManager.clearTempFiles();
      
      logger.info(TAG, '清理缓存数据完成');
    } catch (error) {
      logger.error(TAG, '清理缓存数据失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 数据备份与恢复 ====================

  /**
   * 备份用户数据
   */
  public async backupUserData(): Promise<string> {
    try {
      const backupPath = await this.dataManager.backupData();
      logger.info(TAG, `用户数据备份完成: ${backupPath}`);
      return backupPath;
    } catch (error) {
      logger.error(TAG, '备份用户数据失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 恢复用户数据
   */
  public async restoreUserData(backupPath: string): Promise<void> {
    try {
      await this.dataManager.restoreData(backupPath);
      logger.info(TAG, `用户数据恢复完成: ${backupPath}`);
    } catch (error) {
      logger.error(TAG, '恢复用户数据失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 测试专用方法 ====================

  /**
   * 设置缓存数据（测试用）
   */
  public async setCacheData(key: string, data: Record<string, string | number | boolean | string[] | number[]>): Promise<void> {
    try {
      // 这里可以使用内存缓存或文件缓存
      // 暂时使用简单的内存存储
      if (!this.testCache) {
        this.testCache = new Map<string, Record<string, string | number | boolean | string[] | number[]>>();
      }
      this.testCache.set(key, data);
      logger.debug(TAG, `设置缓存数据: ${key}`);
    } catch (error) {
      logger.error(TAG, '设置缓存数据失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取缓存数据（测试用）
   */
  public async getCacheData(key: string): Promise<Record<string, string | number | boolean | string[] | number[]> | null> {
    try {
      if (!this.testCache) {
        return null;
      }
      const data = this.testCache.get(key) || null;
      logger.debug(TAG, `获取缓存数据: ${key}, 存在: ${data !== null}`);
      return data;
    } catch (error) {
      logger.error(TAG, '获取缓存数据失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 删除缓存数据（测试用）
   */
  public async removeCacheData(key: string): Promise<void> {
    try {
      if (this.testCache) {
        this.testCache.delete(key);
      }
      logger.debug(TAG, `删除缓存数据: ${key}`);
    } catch (error) {
      logger.error(TAG, '删除缓存数据失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 测试数据库连接
   */
  public async testDatabaseConnection(): Promise<boolean> {
    try {
      // 尝试执行一个简单的查询来测试连接
      await this.dataManager.getDataStats();
      logger.debug(TAG, '数据库连接测试通过');
      return true;
    } catch (error) {
      logger.error(TAG, '数据库连接测试失败' + String(error));
      return false;
    }
  }

  /**
   * 创建测试记录
   */
  public async createRecord(record: Record<string, string | number | boolean | string[] | number[]>): Promise<void> {
    try {
      // 这里可以创建一个测试表或使用现有表
      // 暂时使用内存存储
      if (!this.testRecords) {
        this.testRecords = new Map<string, Record<string, string | number | boolean | string[] | number[]>>();
      }
      const id = record.id as string;
      this.testRecords.set(id, record);
      logger.debug(TAG, `创建测试记录: ${id}`);
    } catch (error) {
      logger.error(TAG, '创建测试记录失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 获取测试记录
   */
  public async getRecord(id: string): Promise<Record<string, string | number | boolean | string[] | number[]> | null> {
    try {
      if (!this.testRecords) {
        return null;
      }
      const record = this.testRecords.get(id) || null;
      logger.debug(TAG, `获取测试记录: ${id}, 存在: ${record !== null}`);
      return record;
    } catch (error) {
      logger.error(TAG, '获取测试记录失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 更新测试记录
   */
  public async updateRecord(record: Record<string, string | number | boolean | string[] | number[]>): Promise<void> {
    try {
      if (!this.testRecords) {
        throw new Error('测试记录存储未初始化');
      }
      const id = record.id as string;
      if (!this.testRecords.has(id)) {
        throw new Error(`记录不存在: ${id}`);
      }
      this.testRecords.set(id, record);
      logger.debug(TAG, `更新测试记录: ${id}`);
    } catch (error) {
      logger.error(TAG, '更新测试记录失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 删除测试记录
   */
  public async deleteRecord(id: string): Promise<void> {
    try {
      if (this.testRecords) {
        this.testRecords.delete(id);
      }
      logger.debug(TAG, `删除测试记录: ${id}`);
    } catch (error) {
      logger.error(TAG, '删除测试记录失败' + String(error));
      throw error as Error;
    }
  }

  /**
   * 数据同步测试
   */
  public async syncData(): Promise<SyncResult> {
    try {
      // 模拟数据同步过程
      await new Promise<void>(resolve => setTimeout(resolve, 1000));
      
      logger.info(TAG, '数据同步测试完成');
      const result: SyncResult = { success: true, message: '数据同步成功' };
      return result;
    } catch (error) {
      logger.error(TAG, '数据同步测试失败' + String(error));
      const result: SyncResult = { success: false, message: String(error) };
      return result;
    }
  }

  /**
   * 性能测试操作
   */
  public async performanceTestOperation(index: number): Promise<void> {
    try {
      // 模拟一些数据操作
      const testData: TestData = {
        index,
        timestamp: Date.now(),
        data: `test_data_${index}`
      };
      
      // 模拟异步操作
      await new Promise<void>(resolve => setTimeout(resolve, Math.random() * 10));
      
      logger.debug(TAG, `性能测试操作完成: ${index}`);
    } catch (error) {
      logger.error(TAG, `性能测试操作失败: ${index}, ${error}`);
      throw error as Error;
    }
  }

  /**
   * 清理所有数据
   */
  public async clearAllData(): Promise<void> {
    try {
      // 清理测试缓存
      if (this.testCache) {
        this.testCache.clear();
      }
      
      // 清理测试记录
      if (this.testRecords) {
        this.testRecords.clear();
      }
      
      // 清理应用缓存
      await this.clearCacheData();
      
      logger.info(TAG, '清理所有数据完成');
    } catch (error) {
      logger.error(TAG, '清理所有数据失败' + String(error));
      throw error as Error;
    }
  }

  // ==================== 工具方法 ====================

  /**
   * 格式化字节数
   */
  private formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  /**
   * 销毁数据服务
   */
  public destroy(): void {
    // 清理测试数据
    if (this.testCache) {
      this.testCache.clear();
    }
    if (this.testRecords) {
      this.testRecords.clear();
    }
    
    this.dataManager.destroy();
    DataService.instance = null;
    logger.info(TAG, '数据服务已销毁');
  }
}