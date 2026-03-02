// 文件路径: src/main/ets/Framework/Data/DataManager.ets
/**
 * 数据管理核心类
 * 整合沙箱存储、数据库、文件操作、缓存管理等功能
 */

import { logger } from '../../Utils/Logger';
import { DatabaseManager } from '../Database/DatabaseManager';
import { UUIDGenerator, generateUUID, generateDbId, convertLegacyId, isValidId } from '../Utils/UUIDGenerator';
import { OnlineComicConverter } from '../Utils/OnlineComicConverter';
import { MangaStatus, DownloadStatus } from '../Types/StatusEnums';
import { 
  DatabaseRecord, 
  ComicSourceDatabaseRecord,
  ComicInfoDatabaseRecord,
  ChapterInfoDatabaseRecord,
  PageInfoDatabaseRecord,
  FavoriteInfoDatabaseRecord,
  ReadHistoryDatabaseRecord,
  DownloadTaskDatabaseRecord,
  UserSettingsDatabaseRecord,
  PluginDatabaseRecord,
  DatabaseValue,
  safeJsonParse,
  ComicSourceUpdateData,
  ChapterUpdateData,
  DownloadTaskUpdateData,
  GeneralUpdateData,
  UpdateRecordData,
  GenericQueryRecord
} from '../Database/DatabaseTypes';
import { SandboxManager } from '../Storage/SandboxManager';
import { ImageCacheManager, ImageCacheConfig, MemoryCacheConfig, DiskCacheConfig} from '../Cache/ImageCacheManager';
import { ComicArchiveManager, ComicChapterInfo, ComicPageInfo } from '../Compress/ComicArchiveManager';
import { HSPPluginManager } from '../Plugin/HSPPluginManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { TimeUtils } from '../Utils/TimeUtils';
import fs from '@ohos.file.fs';

const TAG = 'DataManager';

// ==================== 查询结果接口定义 ====================

/**
 * 用户设置查询结果接口
 * 直接使用UserSettingsDatabaseRecord类型（字段名已匹配数据库）
 */
type UserSettingQueryResult = UserSettingsDatabaseRecord;

/**
 * 阅读历史查询结果接口
 * 直接使用ReadHistoryDatabaseRecord类型（字段名已匹配数据库）
 */
type ReadHistoryQueryResult = ReadHistoryDatabaseRecord;

/**
 * 图源配置查询结果接口
 * [新增] 用于按名称查找图源时的返回值
 */
export interface SourceConfigResult {
  id: number;
  config: ESObject;
}

// ==================== 数据库记录转换接口定义 ====================

// 定义明确的配置对象接口，避免使用索引签名
export interface ConfigObject {
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  version?: string;
  description?: string;
  author?: string;
  enabled?: boolean;
  priority?: number;
  timeout?: number;
  retryCount?: number;
  userAgent?: string;
  headers?: string;
  cookies?: string;
}

/**
 * 更新数据记录接口
 */
export interface UpdateDataRecord {
  isDownloaded: boolean;
  downloadPath: string | null;
  // 添加其他可能的更新字段
  lastUpdateTime?: number;
  id?: string;
  sourceId?: string;
  title?: string;
  status?: string;
  metadata?: ConfigObject;
}

/**
 * 页面缓存更新接口
 */
export interface PageCacheUpdate {
  imageUrl: string;
  localPath: string;
  fileSize: number;
}

/**
 * 批量删除漫画结果接口
 */
export interface DeleteComicsResult {
  successCount: number;
  failedCount: number;
  errors: string[];
}

/**
 * 章节更新数据接口
 */
export interface ChapterUpdateRecord {
  isDownloaded?: boolean;
  downloadPath?: string;
}

/**
 * COUNT查询结果接口
 */
export interface CountQueryResult {
  count: DatabaseValue;
}

/**
 * 缓存漫画信息接口
 * 用于返回有缓存页面的漫画列表
 */
export interface CachedMangaInfo {
  mangaId: string;
  mangaTitle: string;
  sourceId: number;
}
export interface ComicSource {
  id: string;
  name: string;
  baseUrl: string;
  pluginId: string;
  isEnabled: boolean;
  priority: number;
  lastUpdateTime: number;
  config: ConfigObject;
  addTime: number;
  preloadCurrentChapter?: boolean;  // 是否预加载当前章节
  preloadCurrentPages?: number;     // 当前章节预加载页数（0=不预加载，-1=全部）
  preloadNextChapter?: boolean;     // 是否预加载下一章节
  preloadNextPages?: number;        // 下一章节预加载页数（0=不预加载，-1=全部）
}

export interface ComicInfo {
  id: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  coverLocalPath?: string; // 封面本地路径
  sourceId: string;
  status: MangaStatus;
  tags: string[];
  rating: number;
  chapterCount: number;
  lastUpdateTime: number;
  addTime: number;
  externalId?: string; // 外部图源ID
  contentType?: string; // 内容类型：'manga' = 漫画, 'ebook' = 电子书类PDF
  isNSFW?: number | boolean; // 是否为NSFW内容（数据库中为0/1，代码中可为boolean）
  isPrivate?: number | boolean; // 是否为隐私内容（数据库中为0/1，代码中可为boolean）
}

export interface ChapterInfo {
  id: string;
  comicId: string;
  title: string;
  index: number;
  pageCount: number;
  isDownloaded: boolean;
  downloadPath?: string;
  publishTime: number;
  addTime: number;
  externalId?: string; // 外部图源章节ID
}

export interface PageInfo {
  id: string;
  chapterId: string;
  index: number;
  imageUrl: string;
  localPath?: string;
  width: number;
  height: number;
  fileSize: number;
}

/**
 * WebView图源章节及页面查询结果接口
 */
export interface ChapterWithPages {
  chapter: ChapterInfo;
  pages: PageInfo[];
}

export interface FavoriteInfo {
  id: string;
  comicId: string;
  userId: string;
  addTime: number;
  lastReadChapterId?: string;
  lastReadTime?: number;
  tags: string[];
}

/**
 * 图源登录凭据
 */
export class SourceCredentials {
  username: string;
  password: string;
  constructor(username: string, password: string) {
    this.username = username;
    this.password = password;
  }
}

export interface ReadHistory {
  id: string;
  comicId: string;
  chapterId: string;
  pageIndex: number;
  userId: string;
  readTime: number;
  readDuration: number;
}

export interface DownloadTask {
  id: string;
  comicId: string;
  chapterId: string;
  status: DownloadStatus;
  progress: number;
  totalPages: number;
  downloadedPages: number;
  createTime: number;
  startTime?: number;
  completeTime?: number;
  errorMessage?: string;
}

export interface CacheConfig {
  maxImageCacheSize: number;
  maxDiskCacheAge: number;
}

export interface DataManagerConfig {
  enableAutoBackup: boolean;
  backupInterval: number;
  maxBackupFiles: number;
  enableDataSync: boolean;
  syncInterval: number;
  cacheConfig: CacheConfig;
}

export interface QueryOptions {
  where?: string;
  whereArgs?: Array<string | number>;
  orderBy?: string;
  limit?: number;
  offset?: number;
}

export interface StorageStats {
  totalSize: number;
  cacheSize: number;
  comicsSize: number;
  coversSize: number;
  chaptersSize: number;
  tempSize: number;
}

export interface CacheStats {
  memoryCache: MemoryCacheStats;
  diskCache: DiskCacheStats;
}

// 定义明确的接口替代对象字面量类型声明
export interface MemoryCacheStats {
  size: number;
  count: number;
  hitRate: number;
}

export interface DiskCacheStats {
  size: number;
  count: number;
}

export interface DataStats {
  comicCount: number;
  chapterCount: number;
  favoriteCount: number;
  downloadTaskCount: number;
  storageStats: StorageStats;
  cacheStats: CacheStats;
}

export interface ChapterArchiveInfo {
  chapterId: string;
  chapterTitle: string;
  comicId: string;
  comicTitle: string;
  pageCount: number;
  pages: PageArchiveInfo[];
}

export interface PageArchiveInfo {
  pageIndex: number;
  fileName: string;
  filePath: string;
  fileSize: number;
  mimeType: string;
}

// 替代工具类型的明确接口定义
export interface DataManagerConfigInput {
  enableAutoBackup?: boolean;
  backupInterval?: number;
  maxBackupFiles?: number;
  enableDataSync?: boolean;
  syncInterval?: number;
  cacheConfig?: CacheConfigInput;
}

// 定义明确的缓存配置接口
export interface CacheConfigInput {
  maxImageCacheSize?: number;
  maxDiskCacheAge?: number;
}

export interface ComicSourceInput {
  name: string;
  baseUrl: string;
  pluginId: string;
  isEnabled: boolean;
  priority: number;
  config: ConfigObject;
}

export interface ComicSourceUpdate {
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  isEnabled?: boolean;
  priority?: number;
  config?: ConfigObject;
}

export interface ComicInfoInput {
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  coverLocalPath?: string;     // 封面本地路径（可选）
  sourceId: string;
  externalId: string;          // 外部图源漫画ID（必需）
  status: MangaStatus;
  tags: string[];
  rating: number;
  chapterCount: number;
  lastUpdateTime: number;
  webUrl?: string;             // 网页URL（可选）
  apiUrl?: string;             // API请求地址（可选）
  contentType?: string;        // 内容类型：'manga' = 漫画, 'ebook' = 电子书类PDF（可选，默认'manga'）
  isNSFW?: boolean;            // 是否为NSFW内容
  isPrivate?: boolean;         // 是否为隐私内容
}

export interface ChapterInfoInput {
  comicId: string;
  title: string;
  index: number;
  pageCount: number;
  isDownloaded: boolean;
  downloadPath?: string;
  publishTime: number;
  externalId: string;          // 外部图源章节ID（必需）
}

export interface PageInfoInput {
  chapterId: string;
  index: number;
  imageUrl: string;
  localPath?: string;
  width: number;
  height: number;
  fileSize: number;
  pageNumber?: number;
}

// ==================== 在线漫画独立输入类型 ====================

export interface OnlineComicInfoInput {
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  sourceId: string;
  externalId: string;
  status: string;
  tags: string[];
  rating: number;
  lastUpdateTime: number;
}

export interface OnlineChapterInfoInput {
  comicId: string;
  externalId: string;  // 外部图源章节ID（必需）
  title: string;
  chapterNumber: number;
  url?: string;
  pageCount: number;
  publishTime: number;
  // [新增] 下载相关字段
  isDownloaded?: boolean;  // 默认false
  downloadPath?: string;
  index?: number;  // 默认使用chapterNumber
}

export interface OnlinePageInfoInput {
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  width: number;
  height: number;
  fileSize: number;
}

export interface OnlineReadHistory {
  id: string;
  comicId: string;
  chapterId: string;
  pageIndex: number;
  readTime: number;
  createTime: number;
}

// ==================== 在线漫画强类型（业务层使用） ====================

export interface OnlineComicInfo {
  id: string;
  sourceId: string;
  externalId: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  tags: string[];
  rating: number;
  lastUpdateTime: number;
  addTime: number;
  createTime: number;
  updateTime: number;
  sourceName: string;
  sourcePkg: string;  // 图源唯一包名标识符，用于在图源删除后重新导入时正确识别图源
  isNSFW?: number;
  isPrivate?: number;
}

export interface OnlineChapterInfo {
  id: string;
  comicId: string;
  externalId: string;  // 外部图源章节ID（必需）
  title: string;
  chapterNumber: number;
  url: string;
  pageCount: number;
  publishTime: number;
  addTime: number;
  createTime: number;
  updateTime: number;
  // [新增] 从ChapterInfo继承的字段，用于支持下载功能
  isDownloaded: boolean;
  downloadPath?: string;
  index: number;  // 章节索引（与chapterNumber相同）
}

export interface OnlinePageInfo {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  localPath?: string;  // [新增] 下载后的本地文件路径
  width: number;
  height: number;
  fileSize: number;
  createTime: number;
}

export interface FavoriteInfoInput {
  comicId: string;
  userId: string;
  lastReadChapterId?: string;
  lastReadTime?: number;
  tags: string[];
}

export interface ReadHistoryInput {
  comicId: string;
  chapterId: string;
  pageIndex: number;
  userId: string;
  readTime: number;
  readDuration: number;
}

export interface DownloadTaskInput {
  comicId: string;
  chapterId: string;
  status: DownloadStatus;
  progress: number;
  totalPages: number;
  downloadedPages: number;
  startTime?: number;
  completeTime?: number;
  errorMessage?: string;
}

export interface DownloadTaskUpdate {
  status?: DownloadStatus;
  progress?: number;
  totalPages?: number;
  downloadedPages?: number;
  startTime?: number;
  completeTime?: number;
  errorMessage?: string;
}

/**
 * 漫画基础信息更新接口
 */
export interface ComicBasicInfoUpdate {
  title?: string;
  description?: string;
  authors?: string[];
  genres?: string[];
  isPrivate?: boolean;
}

export class DataManager {
  private static instance: DataManager | null = null;

  // 核心管理器
  private databaseManager: DatabaseManager;
  private sandboxManager: SandboxManager;
  private imageCacheManager: ImageCacheManager;
  private archiveManager: ComicArchiveManager;
  private pluginManager: HSPPluginManager;

  // 配置
  private config: DataManagerConfig = {
    enableAutoBackup: true,
    backupInterval: 24 * 60 * 60 * 1000, // 24小时
    maxBackupFiles: 7,
    enableDataSync: false,
    syncInterval: 60 * 60 * 1000, // 1小时
    cacheConfig: {
      maxImageCacheSize: 500 * 1024 * 1024, // 500MB
      maxDiskCacheAge: 7 * 24 * 60 * 60 * 1000 // 7天
    }
  };

  // 定时器
  private backupTimer: number | null = null;
  private syncTimer: number | null = null;

  private constructor() {
    this.databaseManager = DatabaseManager.getInstance();
    this.sandboxManager = SandboxManager.getInstance();
    this.imageCacheManager = ImageCacheManager.getInstance();
    this.archiveManager = ComicArchiveManager.getInstance();
    this.pluginManager = HSPPluginManager.getInstance();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): DataManager {
    if (!DataManager.instance) {
      DataManager.instance = new DataManager();
    }
    return DataManager.instance;
  }

  /**
   * 初始化数据管理器
   */
  public async initialize(context: common.UIAbilityContext, config?: DataManagerConfigInput): Promise<void> {
    try {
      logger.info(TAG, '开始初始化数据管理器');

      // 合并配置 - 避免使用扩展运算符
      if (config) {
        this.config.enableAutoBackup = config.enableAutoBackup ?? this.config.enableAutoBackup;
        this.config.backupInterval = config.backupInterval ?? this.config.backupInterval;
        this.config.maxBackupFiles = config.maxBackupFiles ?? this.config.maxBackupFiles;
        this.config.enableDataSync = config.enableDataSync ?? this.config.enableDataSync;
        this.config.syncInterval = config.syncInterval ?? this.config.syncInterval;
        if (config.cacheConfig) {
          this.config.cacheConfig.maxImageCacheSize = config.cacheConfig.maxImageCacheSize ?? this.config.cacheConfig.maxImageCacheSize;
          this.config.cacheConfig.maxDiskCacheAge = config.cacheConfig.maxDiskCacheAge ?? this.config.cacheConfig.maxDiskCacheAge;
        }
      }

      // 初始化沙箱管理器
      await this.sandboxManager.initialize(context);

      // 初始化数据库管理器
      await this.databaseManager.initialize(context);

      // 初始化图片缓存管理器 - 使用明确的接口定义
      const memoryCacheConfig: MemoryCacheConfig = {
        maxSize: this.config.cacheConfig.maxImageCacheSize,
        maxCount: 200,
        evictionPolicy: 'LRU'
      };

      const diskCacheConfig: DiskCacheConfig = {
        maxSize: this.config.cacheConfig.maxImageCacheSize,
        maxAge: this.config.cacheConfig.maxDiskCacheAge,
        compressionQuality: 85
      };

      const cacheConfig: ImageCacheConfig = {
        memoryCache: memoryCacheConfig,
        diskCache: diskCacheConfig,
        network: {
          timeout: 30000,
          retryCount: 3,
          retryDelay: 1000
        }
      };

      await this.imageCacheManager.initialize(cacheConfig);

      // 初始化插件管理器
      await this.pluginManager.initialize();

      // 启动定时任务
      this.startTimers();

      logger.info(TAG, '数据管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '数据管理器初始化失败', String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 数据库记录转换为业务对象的工具方法
   */
  private convertRecordToComicSource(record: ComicSourceDatabaseRecord): ComicSource {
    // 处理configJson属性的类型转换
    const defaultConfig: ConfigObject = {};
    let config: ConfigObject = defaultConfig;
    if (record.configJson) {
      if (typeof record.configJson === 'string') {
        config = safeJsonParse<ConfigObject>(record.configJson, defaultConfig);
      } else if (typeof record.configJson === 'object') {
        config = record.configJson as ConfigObject;
      }
    }

    return {
      id: record.id,
      name: record.name,
      baseUrl: record.baseUrl,
      pluginId: record.pluginId,
      isEnabled: record.isEnabled,
      priority: record.priority,
      lastUpdateTime: record.lastUpdateTime,
      config: config,
      addTime: record.addTime
    };
  }

  private convertRecordToComicInfo(record: ComicInfoDatabaseRecord): ComicInfo {
    logger.debug(TAG, `[NSFW调试] 数据库记录 record.isNSFW=${record.isNSFW}, 类型=${typeof record.isNSFW}`);
    return {
      id: record.id,
      title: record.title,
      author: record.author,
      description: record.description,
      coverUrl: record.coverUrl,
      coverLocalPath: record.coverLocalPath || undefined,
      sourceId: record.sourceId,
      status: record.status as MangaStatus,
      tags: safeJsonParse(record.tags, []),
      rating: record.rating,
      chapterCount: record.chapterCount,
      lastUpdateTime: record.lastUpdateTime,
      addTime: record.addTime,
      externalId: record.externalId || undefined,
      isPrivate: (record.isPrivate !== undefined && record.isPrivate !== null) ? (record.isPrivate === 1) : false,
      isNSFW: (record.isNSFW !== undefined && record.isNSFW !== null) ? (record.isNSFW === 1) : false
    };
  }

  /**
   * 将 online_comic_info 数据库记录转换为 ComicInfo
   * [修复] 用于支持从 online_comic_info 表查询漫画
   */
  private convertOnlineComicRecordToComicInfo(record: ESObject): ComicInfo {
    const isPrivateValue = record.isPrivate as number | undefined | null;
    const isNSFWValue = record.isNSFW as number | undefined | null;
    
    return {
      id: record.id as string,
      title: record.title as string,
      author: (record.author as string) || '',
      description: (record.description as string) || '',
      coverUrl: (record.coverUrl as string) || '',
      sourceId: record.sourceId as string,
      status: 'unknown' as MangaStatus,
      tags: safeJsonParse(record.tags as string, []),
      rating: (record.rating as number) || 0,
      chapterCount: 0,
      lastUpdateTime: (record.lastUpdateTime as number) || 0,
      addTime: (record.addTime as number) || 0,
      externalId: (record.externalId as string) || undefined,
      isPrivate: (isPrivateValue !== undefined && isPrivateValue !== null) ? (isPrivateValue === 1) : false,
      isNSFW: (isNSFWValue !== undefined && isNSFWValue !== null) ? (isNSFWValue === 1) : false
    };
  }

  private convertRecordToChapterInfo(record: ChapterInfoDatabaseRecord): ChapterInfo {
    // [调试] 打印原始数据库记录的externalId字段
    logger.debug(TAG, `🔄 [convertRecordToChapterInfo] 原始record.externalId=${record.externalId || 'undefined'}, record.id=${record.id}, record.title="${record.title}"`);
    
    const result: ChapterInfo = {
      id: record.id,
      comicId: record.comicId,
      title: record.title,
      index: record.chapterIndex,
      pageCount: record.pageCount,
      isDownloaded: record.isDownloaded,
      downloadPath: record.downloadPath || undefined,
      publishTime: record.publishTime,
      addTime: record.addTime,
      externalId: record.externalId || undefined // [修复] 读取外部ID
    };
    
    logger.debug(TAG, `🔄 [convertRecordToChapterInfo] 转换后result.externalId=${result.externalId || 'undefined'}, result.id=${result.id}`);
    
    return result;
  }

  private convertRecordToPageInfo(record: PageInfoDatabaseRecord): PageInfo {
    return {
      id: record.id,
      chapterId: record.chapterId,
      index: record.index,
      imageUrl: record.imageUrl,
      localPath: record.localPath || undefined,
      width: record.width,
      height: record.height,
      fileSize: record.fileSize
    };
  }

  private convertRecordToFavoriteInfo(record: FavoriteInfoDatabaseRecord): FavoriteInfo {
    return {
      id: record.id,
      comicId: record.comicId,
      userId: record.userId,
      addTime: record.addTime,
      lastReadChapterId: record.lastReadChapterId || undefined,
      lastReadTime: record.lastReadTime || undefined,
      tags: safeJsonParse(record.tags, [] as string[])
    };
  }

  private convertRecordToReadHistory(record: ReadHistoryDatabaseRecord): ReadHistory {
    return {
      id: record.id,
      comicId: record.comicId,
      chapterId: record.chapterId,
      pageIndex: record.pageNumber,      // ReadHistoryDatabaseRecord.pageNumber -> ReadHistory.pageIndex
      userId: record.userId,
      readTime: record.readTime,
      readDuration: record.duration       // ReadHistoryDatabaseRecord.duration -> ReadHistory.readDuration
    };
  }

  // ==================== 在线漫画强类型转换 ====================

  private convertRecordToOnlineComicInfo(record: DatabaseRecord): OnlineComicInfo {
    const obj: ESObject = record as ESObject;
    const tagsJson: string = (obj.tags as string) || '[]';
    let tags: string[] = [];
    try {
      const parsed: ESObject = JSON.parse(tagsJson) as ESObject;
      const keys: string[] = Object.keys(parsed);
      if (keys.length > 0) {
        const values: string[] = [];
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i];
          const v: string = (parsed as ESObject)[k] as string;
          values.push(v);
        }
        tags = values;
      } else {
        const arr: string[] = parsed as string[];
        if (arr && arr.length > 0) {
          const result: string[] = [];
          for (let i = 0; i < arr.length; i++) {
            result.push(arr[i]);
          }
          tags = result;
        }
      }
    } catch (e) {
      logger.warn(TAG, `在线漫画标签解析失败: ${String(e)}`);
    }
    
    const isNSFWValue = Number(obj.isNSFW) || 0;
    const isPrivateValue = Number(obj.isPrivate) || 0;
    logger.debug(TAG, `[NSFW调试] convertRecordToOnlineComicInfo: title="${(obj.title as string)}", 原始isNSFW=${obj.isNSFW}, 转换后=${isNSFWValue}, isPrivate=${isPrivateValue}`);
    
    const info: OnlineComicInfo = {
      id: (obj.id as string) || '',
      sourceId: String(obj.sourceId),
      externalId: (obj.externalId as string) || '',
      title: (obj.title as string) || '',
      author: (obj.author as string) || '',
      description: (obj.description as string) || '',
      coverUrl: (obj.coverUrl as string) || '',
      tags: tags,
      rating: Number(obj.rating) || 0,
      lastUpdateTime: Number(obj.lastUpdateTime) || 0,
      addTime: Number(obj.addTime) || 0,
      createTime: Number(obj.createTime) || 0,
      updateTime: Number(obj.updateTime) || 0,
      sourceName: (obj.sourceName as string) || '',
      sourcePkg: (obj.sourcePkg as string) || '',
      isNSFW: isNSFWValue,
      isPrivate: isPrivateValue
    };
    return info;
  }

  private convertRecordToOnlineChapterInfo(record: DatabaseRecord): OnlineChapterInfo {
    const obj: ESObject = record as ESObject;
    
    // [调试] 输出原始数据库记录
    logger.debug(TAG, `📋 [DB→Model] 原始记录: id="${obj.id}", comicId="${obj.comicId}", externalId="${obj.externalId}"`);
    
    const info: OnlineChapterInfo = {
      id: (obj.id as string) || '',
      comicId: (obj.comicId as string) || '',
      externalId: (obj.externalId as string) || '',
      title: (obj.title as string) || '',
      chapterNumber: Number(obj.chapterNumber) || 0,
      url: (obj.url as string) || '',
      pageCount: Number(obj.pageCount) || 0,
      publishTime: Number(obj.publishTime) || 0,
      addTime: Number(obj.addTime) || 0,
      createTime: Number(obj.createTime) || 0,
      updateTime: Number(obj.updateTime) || 0,
      // [新增] 下载相关字段
      isDownloaded: Boolean(obj.isDownloaded) || false,
      downloadPath: (obj.downloadPath as string) || undefined,
      index: Number(obj.index) || Number(obj.chapterNumber) || 0
    };
    
    // [调试] 输出转换后的数据
    logger.debug(TAG, `  ✅ [DB→Model] 转换完成: id="${info.id}", externalId="${info.externalId}", title="${info.title}"`);
    
    return info;
  }

  private convertRecordToOnlinePageInfo(record: DatabaseRecord): OnlinePageInfo {
    const obj: ESObject = record as ESObject;
    const info: OnlinePageInfo = {
      id: (obj.id as string) || '',
      chapterId: (obj.chapterId as string) || '',
      pageNumber: Number(obj.pageNumber) || Number((obj as ESObject).index as number) || 0,
      imageUrl: (obj.imageUrl as string) || '',
      localPath: (obj.localPath as string) || undefined,  // [新增] 本地文件路径
      width: Number(obj.width) || 0,
      height: Number(obj.height) || 0,
      fileSize: Number(obj.fileSize) || 0,
      createTime: Number(obj.createTime) || 0
    };
    return info;
  }

  // ==================== 在线漫画强类型获取 ====================

  public async getOnlineComicByExternalId(externalId: string): Promise<OnlineComicInfo | null> {
    try {
      const sql = 'SELECT * FROM online_comic_info WHERE externalId = ?';
      const result = await this.databaseManager.querySql(sql, [externalId]);
      if (result && result.length > 0) {
        return this.convertRecordToOnlineComicInfo(result[0] as DatabaseRecord);
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取在线漫画失败: externalId=${externalId}`, String(error));
      return null;
    }
  }

  /**
   * [新增] 根据外部章节ID查询online_chapter表
   * 用于在线漫画章节的查询（支持不同图源的外部ID）
   */
  public async getOnlineChapterByExternalId(comicId: string, externalChapterId: string): Promise<OnlineChapterInfo | null> {
    try {
      logger.info(TAG, `🔍 查询在线章节: comicId=${comicId}, externalId=${externalChapterId}`);
      // [性能优化] 只查询实际使用的列，避免 SELECT * 的数据传输开销
      const sql = `SELECT id, comicId, externalId, title, chapterNumber, url, pageCount,
                          publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath
                   FROM online_chapter WHERE comicId = ? AND externalId = ?`;
      const result = await this.databaseManager.querySql(sql, [comicId, externalChapterId]);
      if (result && result.length > 0) {
        const chapterInfo = OnlineComicConverter.convertToOnlineChapterInfo(result[0] as DatabaseRecord);
        logger.info(TAG, `✅ 找到在线章节: ${chapterInfo.title}`);
        return chapterInfo;
      }
      logger.warn(TAG, `⚠️ 未找到在线章节: comicId=${comicId}, externalId=${externalChapterId}`);
      return null;
    } catch (error) {
      logger.error(TAG, `查询在线章节失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 根据外部图源ID查询本地通用表中的漫画记录
   */
  public async getComicByExternalId(externalId: string): Promise<DatabaseRecord | null> {
    try {
      const sql = 'SELECT * FROM comic_info WHERE externalId = ?';
      const result = await this.databaseManager.querySql(sql, [externalId]);
      if (result && result.length > 0) {
        return result[0] as DatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取漫画失败: externalId=${externalId}`, String(error));
      return null;
    }
  }

  /**
   * 删除外部图源ID对应的本地漫画记录（含章节、页面、收藏、历史、下载任务）
   */
  public async deleteComicByExternalId(externalId: string): Promise<void> {
    try {
      const record = await this.getComicByExternalId(externalId);
      if (!record) {
        logger.warn(TAG, `未找到externalId对应的漫画: ${externalId}`);
        return;
      }
      const obj: ESObject = record as ESObject;
      const internalId: string = String(obj.id);
      await this.deleteComic(internalId);
      logger.info(TAG, `已按externalId删除漫画: ${externalId} -> ${internalId}`);
    } catch (error) {
      logger.error(TAG, `按externalId删除漫画失败: ${externalId}`, String(error));
      throw error as Error;
    }
  }

  public async getOnlineComicChapters(comicId: string): Promise<OnlineChapterInfo[]> {
    try {
      // [性能优化] 只查询必要字段，避免SELECT *造成的数据传输开销
      const sql = `SELECT id, comicId, externalId, title, chapterNumber, url, pageCount, 
                          publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath 
                   FROM online_chapter WHERE comicId = ? ORDER BY chapterNumber ASC`;
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      // [修复] 使用专门的在线漫画转换器
      logger.info(TAG, `📚 查询到 ${result.length} 个在线章节记录，开始转换`);
      const chapters = OnlineComicConverter.convertToOnlineChapterInfoArray(result as DatabaseRecord[]);
      logger.info(TAG, `✅ 在线章节转换完成，成功 ${chapters.length} 个`);
      
      return chapters;
    } catch (error) {
      logger.error(TAG, `获取在线章节失败: comicId=${comicId}`, String(error));
      return [];
    }
  }

  public async getOnlineChapterById(chapterId: string): Promise<OnlineChapterInfo | null> {
    try {
      // [性能优化] 只查询实际使用的列，避免 SELECT * 的数据传输开销
      const sql = `SELECT id, comicId, externalId, title, chapterNumber, url, pageCount,
                          publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath
                   FROM online_chapter WHERE id = ?`;
      const result = await this.databaseManager.querySql(sql, [chapterId]);
      if (result.length > 0) {
        return OnlineComicConverter.convertToOnlineChapterInfo(result[0] as DatabaseRecord);
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取在线章节失败: chapterId=${chapterId}`, String(error));
      return null;
    }
  }

  /**
   * [新增] 根据漫画ID和章节标题查询在线章节
   * 用于WebView图源通过章节标题匹配数据库中的章节
   */
  public async getOnlineChapterByTitle(comicId: string, chapterTitle: string): Promise<OnlineChapterInfo | null> {
    try {
      logger.info(TAG, `🔍 通过标题查询在线章节: comicId=${comicId}, title="${chapterTitle}"`);
      // [性能优化] 只查询实际使用的列
      const sql = `SELECT id, comicId, externalId, title, chapterNumber, url, pageCount,
                          publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath
                   FROM online_chapter WHERE comicId = ? AND title = ?`;
      const result = await this.databaseManager.querySql(sql, [comicId, chapterTitle]);
      if (result && result.length > 0) {
        const chapterInfo = OnlineComicConverter.convertToOnlineChapterInfo(result[0] as DatabaseRecord);
        logger.info(TAG, `✅ 找到在线章节: id=${chapterInfo.id}, externalId=${chapterInfo.externalId}`);
        return chapterInfo;
      }
      logger.warn(TAG, `⚠️ 未找到标题匹配的在线章节: "${chapterTitle}"`);
      return null;
    } catch (error) {
      logger.error(TAG, `通过标题查询在线章节失败: ${String(error)}`);
      return null;
    }
  }

  public async getOnlineChapterPages(chapterId: string): Promise<OnlinePageInfo[]> {
    try {
      // [性能优化] 只查询实际使用的列，避免 SELECT * 的数据传输开销
      const sql = `SELECT id, chapterId, pageNumber, imageUrl, localPath, width, height, fileSize, createTime
                   FROM online_page WHERE chapterId = ? ORDER BY pageNumber ASC`;
      const result = await this.databaseManager.querySql(sql, [chapterId]);
      const pages: OnlinePageInfo[] = [];
      for (let i = 0; i < result.length; i++) {
        pages.push(this.convertRecordToOnlinePageInfo(result[i] as DatabaseRecord));
      }
      return pages;
    } catch (error) {
      logger.error(TAG, `获取在线页面失败: chapterId=${chapterId}`, String(error));
      return [];
    }
  }

  /**
   * [懒加载优化] 批量查询在线章节的页面数量
   * 使用单条SQL查询所有章节的页数，避免逐个章节查询
   * @param comicId 漫画ID
   * @returns Map<章节ID, 页面数量>
   */
  public async getOnlineChapterPageCounts(comicId: string): Promise<Map<string, number>> {
    try {
      // 使用子查询获取所有属于该漫画的章节的页面数量
      const sql = `
        SELECT chapterId, COUNT(*) as pageCount 
        FROM online_page 
        WHERE chapterId IN (SELECT id FROM online_chapter WHERE comicId = ?)
        GROUP BY chapterId
      `;
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      const pageCountMap = new Map<string, number>();
      for (let i = 0; i < result.length; i++) {
        const record = result[i] as GenericQueryRecord;
        const chapterId = String(record.chapterId || '');
        const pageCount = Number(record.pageCount || 0);
        if (chapterId) {
          pageCountMap.set(chapterId, pageCount);
        }
      }
      
      logger.debug(TAG, `[懒加载] 批量查询章节页数完成: comicId=${comicId}, 章节数=${pageCountMap.size}`);
      return pageCountMap;
    } catch (error) {
      logger.error(TAG, `批量查询章节页数失败: comicId=${comicId}`, String(error));
      return new Map<string, number>();
    }
  }

  /**
   * [懒加载优化] 批量查询本地章节的页面数量
   * @param comicId 漫画ID
   * @returns Map<章节ID, 页面数量>
   */
  public async getLocalChapterPageCounts(comicId: string): Promise<Map<string, number>> {
    try {
      const sql = `
        SELECT chapterId, COUNT(*) as pageCount 
        FROM page 
        WHERE chapterId IN (SELECT id FROM chapter WHERE comicId = ?)
        GROUP BY chapterId
      `;
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      const pageCountMap = new Map<string, number>();
      for (let i = 0; i < result.length; i++) {
        const record = result[i] as GenericQueryRecord;
        const chapterId = String(record.chapterId || '');
        const pageCount = Number(record.pageCount || 0);
        if (chapterId) {
          pageCountMap.set(chapterId, pageCount);
        }
      }
      
      logger.debug(TAG, `[懒加载] 批量查询本地章节页数完成: comicId=${comicId}, 章节数=${pageCountMap.size}`);
      return pageCountMap;
    } catch (error) {
      logger.error(TAG, `批量查询本地章节页数失败: comicId=${comicId}`, String(error));
      return new Map<string, number>();
    }
  }

  /**
   * [性能优化] 批量获取漫画所有章节的页面信息（在线漫画）
   * 单条SQL替代N次逐章节查询，返回按chapterId分组的Map
   */
  public async getAllOnlinePagesByComicId(comicId: string): Promise<Map<string, OnlinePageInfo[]>> {
    try {
      const sql = `SELECT op.id, op.chapterId, op.pageNumber, op.imageUrl, op.localPath,
                          op.width, op.height, op.fileSize, op.createTime
                   FROM online_page op
                   INNER JOIN online_chapter oc ON op.chapterId = oc.id
                   WHERE oc.comicId = ?
                   ORDER BY op.chapterId, op.pageNumber ASC`;
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      const pageMap = new Map<string, OnlinePageInfo[]>();
      for (let i = 0; i < result.length; i++) {
        const pageInfo = this.convertRecordToOnlinePageInfo(result[i] as DatabaseRecord);
        const chId = pageInfo.chapterId;
        let arr = pageMap.get(chId);
        if (!arr) {
          arr = [];
          pageMap.set(chId, arr);
        }
        arr.push(pageInfo);
      }
      
      logger.debug(TAG, `[性能优化] 批量获取在线页面完成: comicId=${comicId}, 章节数=${pageMap.size}, 总页数=${result.length}`);
      return pageMap;
    } catch (error) {
      logger.error(TAG, `批量获取在线页面失败: comicId=${comicId}`, String(error));
      return new Map<string, OnlinePageInfo[]>();
    }
  }

  /**
   * [性能优化] 批量获取漫画所有章节的页面信息（本地漫画）
   * 单条SQL替代N次逐章节查询，返回按chapterId分组的Map
   */
  public async getAllLocalPagesByComicId(comicId: string): Promise<Map<string, PageInfo[]>> {
    try {
      const sql = `SELECT p.id, p.chapterId, p.pageNumber, p.imageUrl, p.localPath,
                          p.width, p.height, p.fileSize
                   FROM page p
                   INNER JOIN chapter c ON p.chapterId = c.id
                   WHERE c.comicId = ?
                   ORDER BY p.chapterId, p.pageNumber ASC`;
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      const pageMap = new Map<string, PageInfo[]>();
      for (let i = 0; i < result.length; i++) {
        const pageInfo = this.convertRecordToPageInfo(result[i] as PageInfoDatabaseRecord);
        const chId = pageInfo.chapterId;
        let arr = pageMap.get(chId);
        if (!arr) {
          arr = [];
          pageMap.set(chId, arr);
        }
        arr.push(pageInfo);
      }
      
      logger.debug(TAG, `[性能优化] 批量获取本地页面完成: comicId=${comicId}, 章节数=${pageMap.size}, 总页数=${result.length}`);
      return pageMap;
    } catch (error) {
      logger.error(TAG, `批量获取本地页面失败: comicId=${comicId}`, String(error));
      return new Map<string, PageInfo[]>();
    }
  }

  private convertRecordToDownloadTask(record: DownloadTaskDatabaseRecord): DownloadTask {
    return {
      id: String(record.id || ''),
      comicId: record.comicId,
      chapterId: record.chapterId,
      status: record.status as DownloadStatus,
      progress: record.progress,
      totalPages: record.totalSize, // 映射totalSize到totalPages
      downloadedPages: record.downloadedSize, // 映射downloadedSize到downloadedPages
      createTime: record.createTime,
      startTime: undefined, // DownloadTaskDatabaseRecord没有startTime字段
      completeTime: undefined, // DownloadTaskDatabaseRecord没有completeTime字段
      errorMessage: record.errorMessage || undefined
    };
  }

  // ==================== 漫画信息管理 ====================

  /**
   * 添加漫画信息
   */
  public async addComicInfo(comic: ComicInfoInput): Promise<string> {
    try {
      const generatedId = this.generateId();
      const now = Date.now();
      const comicData: ComicInfo = {
        id: generatedId,
        title: comic.title,
        author: comic.author,
        description: comic.description,
        coverUrl: comic.coverUrl,
        sourceId: comic.sourceId,
        externalId: comic.externalId,  // 外部图源ID
        status: comic.status,
        tags: comic.tags,
        rating: comic.rating,
        chapterCount: comic.chapterCount,
        lastUpdateTime: comic.lastUpdateTime,
        addTime: now
      };

      // 确保externalId不为undefined，如果未提供则使用内部ID
      const finalExternalId = comicData.externalId || generatedId;

      // 【NSFW自动继承】从图源和标签自动判断
      let isNSFW = false;
      
      // 1. 从图源继承（受作用域开关控制）
      try {
        const sourceId = Number(comicData.sourceId);
        const source = await this.getComicSourceById(sourceId);
        if (source && source.isNSFW === 1) {
          try {
            const cfmModule = await import('../Managers/ContentFilterManager');
            const filterManager = cfmModule.ContentFilterManager.getInstance();
            if (filterManager.isNsfwScopeImageSourceEnabled()) {
              isNSFW = true;
              logger.debug(TAG, `漫画从图源继承NSFW标记: ${comicData.title}`);
            }
          } catch (e) {
            isNSFW = true;
            logger.debug(TAG, `漫画从图源继承NSFW标记(默认): ${comicData.title}`);
          }
        }
      } catch (error) {
        logger.warn(TAG, `获取图源NSFW状态失败: ${error}`);
      }
      
      // 2. 从标签判断
      if (!isNSFW && comicData.tags && comicData.tags.length > 0) {
        const nsfwKeywords = ['nsfw', '18+', 'adult', '成人', 'r18', 'h', '里番', '肉番', '色情', '成人向'];
        const tagsLower = comicData.tags.map(t => t.toLowerCase()).join(',');
        const hasNSFWTag = nsfwKeywords.some(keyword => tagsLower.includes(keyword));
        if (hasNSFWTag) {
          isNSFW = true;
          logger.debug(TAG, `漫画从标签判断NSFW: ${comicData.title}`);
        }
      }
      
      // 3. 手动设置优先
      if (comic.isNSFW !== undefined) {
        isNSFW = comic.isNSFW;
        logger.debug(TAG, `漫画使用手动设置NSFW: ${comicData.title} = ${isNSFW}`);
      }
      
      const record: ComicInfoDatabaseRecord = {
        id: comicData.id,
        title: comicData.title,
        author: comicData.author || '',  // 确保不为undefined
        description: comicData.description || '',  // 确保不为undefined
        coverUrl: comicData.coverUrl || '',  // 确保不为undefined
        coverLocalPath: comic.coverLocalPath || '',  // 封面本地路径
        sourceId: comicData.sourceId,
        externalId: finalExternalId,  // 确保不为undefined
        status: String(comicData.status),  // 确保转换为字符串
        tags: JSON.stringify(comicData.tags || []),  // 确保不为undefined
        rating: comicData.rating || 0,  // 确保不为undefined
        chapterCount: comicData.chapterCount || 0,  // 确保不为undefined
        lastUpdateTime: comicData.lastUpdateTime || now,  // 确保不为undefined
        addTime: comicData.addTime || now,  // 确保不为undefined
        createTime: now,  // 创建时间
        updateTime: now,   // 更新时间
        webUrl: comic.webUrl || null,  // 网页URL
        apiUrl: comic.apiUrl || null,   // API请求地址
        contentType: comic.contentType || 'manga',  // 内容类型，默认为漫画
        isNSFW: isNSFW ? 1 : 0,  // NSFW标记
        isPrivate: 0  // 隐私标记，默认为普通内容
      };
      
      await this.databaseManager.insert('comic_info', record);
      logger.info(TAG, `添加漫画: ${comicData.title}`);

      return comicData.id;
    } catch (error) {
      logger.error(TAG, `添加漫画信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取漫画信息
   */
  public async getComicInfo(comicId: string): Promise<ComicInfo | null> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        'id = ?',
        [comicId]
      );
      return records.length > 0 ? this.convertRecordToComicInfo(records[0] as ComicInfoDatabaseRecord) : null;
    } catch (error) {
      logger.error(TAG, `获取漫画信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 搜索漫画
   */
  public async searchComics(keyword: string, sourceId?: string): Promise<ComicInfo[]> {
    try {
      // 支持多字段搜索：title/author/description/tags
      let whereClause: string = '(title LIKE ? OR author LIKE ? OR description LIKE ? OR tags LIKE ?)';
      let whereArgs: (string | number)[] = [`%${keyword}%`, `%${keyword}%`, `%${keyword}%`, `%${keyword}%`];

      if (sourceId) {
        whereClause += ' AND sourceId = ?';
        whereArgs.push(sourceId);
      }

      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        whereClause,
        whereArgs,
        'lastUpdateTime DESC'
      );

      return records.map((record: object) => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `搜索漫画失败: ${message}`);
      throw error as Error;
    }
  }

  /**
   * 获取所有漫画列表
   */
  public async getAllComics(): Promise<ComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        undefined,
        undefined,
        'lastUpdateTime DESC'
      );

      return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取所有漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取所有在线漫画列表
   */
  public async getAllOnlineComics(): Promise<OnlineComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'online_comic_info',
        undefined,
        undefined,
        undefined,
        'lastUpdateTime DESC'
      );

      return records.map(record => this.convertRecordToOnlineComicInfo(record as DatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取所有在线漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取隐私漫画列表（本地漫画）
   * @returns Promise<ComicInfo[]> 隐私漫画列表
   */
  public async getPrivateComics(): Promise<ComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        'isPrivate = ?',
        [1],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条隐私本地漫画`);
      return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取隐私漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [性能优化] 获取推荐候选漫画（使用 SQL LIKE 预过滤）
   * 只查询推荐所需的最少字段，通过作者/标签模糊匹配缩小候选集
   * @param authorFilter 作者过滤关键词
   * @param tagFilters 标签过滤关键词数组
   * @returns Promise<ComicInfo[]> 匹配的候选漫画列表
   */
  public async getRecommendationCandidateComics(authorFilter: string, tagFilters: string[]): Promise<ComicInfo[]> {
    try {
      // 构建 WHERE 条件: 非隐私 AND (作者 LIKE 或 标签 LIKE)
      const conditions: string[] = ['(isPrivate = 0 OR isPrivate IS NULL)'];
      const args: (string | number)[] = [];
      
      const filterParts: string[] = [];
      if (authorFilter && authorFilter.length > 0) {
        filterParts.push('author LIKE ?');
        args.push(`%${authorFilter}%`);
      }
      for (let i = 0; i < tagFilters.length && i < 5; i++) {
        if (tagFilters[i] && tagFilters[i].length > 1) {
          filterParts.push('tags LIKE ?');
          args.push(`%${tagFilters[i]}%`);
        }
      }
      
      if (filterParts.length === 0) {
        // 无过滤条件时退回全量查询
        return await this.getNonPrivateComics();
      }
      
      conditions.push(`(${filterParts.join(' OR ')})`);
      
      const sql = `SELECT id, title, author, coverUrl, coverLocalPath, tags, isPrivate, isNSFW, 
                          rating, chapterCount, lastUpdateTime, addTime, sourceId, externalId, description, status
                   FROM comic_info WHERE ${conditions.join(' AND ')} ORDER BY lastUpdateTime DESC`;
      const result = await this.databaseManager.querySql(sql, args);
      logger.debug(TAG, `推荐候选漫画查询: 过滤条件${filterParts.length}个, 结果${result.length}条`);
      return result.map((record: DatabaseRecord) => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取推荐候选漫画失败: ${error}`);
      return [];
    }
  }

  /**
   * [新增] 获取非隐私漫画列表（本地漫画）
   * @returns Promise<ComicInfo[]> 非隐私漫画列表
   */
  public async getNonPrivateComics(): Promise<ComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        '(isPrivate = ? OR isPrivate IS NULL)',
        [0],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条非隐私本地漫画`);
      return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取非隐私漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取隐私在线漫画列表
   * @returns Promise<OnlineComicInfo[]> 隐私在线漫画列表
   */
  public async getPrivateOnlineComics(): Promise<OnlineComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'online_comic_info',
        undefined,
        'isPrivate = ?',
        [1],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条隐私在线漫画`);
      return records.map(record => this.convertRecordToOnlineComicInfo(record as DatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取隐私在线漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取非隐私在线漫画列表
   * @returns Promise<OnlineComicInfo[]> 非隐私在线漫画列表
   */
  public async getNonPrivateOnlineComics(): Promise<OnlineComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'online_comic_info',
        undefined,
        '(isPrivate = ? OR isPrivate IS NULL)',
        [0],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条非隐私在线漫画`);
      return records.map(record => this.convertRecordToOnlineComicInfo(record as DatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取非隐私在线漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取SFW（非NSFW）漫画列表（本地漫画）
   * @returns Promise<ComicInfo[]> SFW漫画列表
   */
  public async getSFWComics(): Promise<ComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        '(isNSFW = ? OR isNSFW IS NULL)',
        [0],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条SFW本地漫画`);
      return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取SFW漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取NSFW漫画列表（本地漫画）
   * @returns Promise<ComicInfo[]> NSFW漫画列表
   */
  public async getNSFWComics(): Promise<ComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'comic_info',
        undefined,
        'isNSFW = ?',
        [1],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条NSFW本地漫画`);
      return records.map(record => this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取NSFW漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取SFW（非NSFW）在线漫画列表
   * @returns Promise<OnlineComicInfo[]> SFW在线漫画列表
   */
  public async getSFWOnlineComics(): Promise<OnlineComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'online_comic_info',
        undefined,
        '(isNSFW = ? OR isNSFW IS NULL)',
        [0],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条SFW在线漫画`);
      return records.map(record => this.convertRecordToOnlineComicInfo(record as DatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取SFW在线漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * [新增] 获取NSFW在线漫画列表
   * @returns Promise<OnlineComicInfo[]> NSFW在线漫画列表
   */
  public async getNSFWOnlineComics(): Promise<OnlineComicInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'online_comic_info',
        undefined,
        'isNSFW = ?',
        [1],
        'lastUpdateTime DESC'
      );
      logger.info(TAG, `查询到 ${records.length} 条NSFW在线漫画`);
      return records.map(record => this.convertRecordToOnlineComicInfo(record as DatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取NSFW在线漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 更新漫画封面路径
   */
  public async updateComicCoverUrl(comicId: string, coverUrl: string): Promise<void> {
    try {
      const updateData: UpdateRecordData = {
        id: comicId,
        coverUrl: coverUrl
      };

      await this.databaseManager.update(
        'comic_info',
        updateData,
        'id = ?',
        [comicId]
      );

      logger.info(TAG, `成功更新漫画封面: ${comicId} -> ${coverUrl}`);
    } catch (error) {
      logger.error(TAG, `更新漫画封面失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 根据ID获取单个漫画
   * [性能优化] 使用 UNION ALL 单条 SQL 同时查询 comic_info 和 online_comic_info 表
   */
  public async getComicById(comicId: string): Promise<ComicInfo | null> {
    try {
      const sql = `
        SELECT id, sourceId, externalId, title, author, description, coverUrl, coverLocalPath,
               tags, rating, chapterCount, lastUpdateTime, addTime, isPrivate, isNSFW, 'local' as _source
        FROM comic_info WHERE id = ?
        UNION ALL
        SELECT id, sourceId, externalId, title, author, description, coverUrl, '' as coverLocalPath,
               tags, rating, 0 as chapterCount, lastUpdateTime, addTime, isPrivate, isNSFW, 'online' as _source
        FROM online_comic_info WHERE id = ?
        LIMIT 1
      `;
      const result = await this.databaseManager.querySql(sql, [comicId, comicId]);

      if (result.length > 0) {
        const record: DatabaseRecord = result[0] as DatabaseRecord;
        const obj: ESObject = record as ESObject;
        const source: string = (obj._source as string) || '';
        if (source === 'local') {
          logger.debug(TAG, `从 comic_info 表找到漫画: ${comicId}`);
          return this.convertRecordToComicInfo(record as ComicInfoDatabaseRecord);
        } else {
          logger.debug(TAG, `从 online_comic_info 表找到漫画: ${comicId}`);
          return this.convertOnlineComicRecordToComicInfo(obj);
        }
      }

      logger.warn(TAG, `未找到ID为 ${comicId} 的漫画（已查询 comic_info 和 online_comic_info 表）`);
      return null;
    } catch (error) {
      logger.error(TAG, `根据ID获取漫画失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 更新漫画基础信息
   * @param comicId 漫画ID
   * @param basicInfo 基础信息对象
   * 注意：comic_info表的时间字段是updateTime（INTEGER），不是updatedAt
   */
  public async updateComicBasicInfo(comicId: string, basicInfo: ComicBasicInfoUpdate): Promise<void> {
    try {
      logger.info(TAG, `更新漫画基础信息: ${comicId}`);
      
      // 直接使用SQL更新，避免UpdateRecordData类型转换问题
      // comic_info表字段：id, sourceId, externalId, title, author, description, coverUrl, coverLocalPath,
      //                   status, tags, categories, rating, viewCount, favoriteCount, lastChapterTitle,
      //                   lastChapterTime, isCompleted, chapterCount, lastUpdateTime, addTime, createTime, updateTime, webUrl, apiUrl, contentType
      
      const setClauses: string[] = [];
      const values: (string | number)[] = [];
      
      // 更新时间
      setClauses.push('updateTime = ?');
      values.push(Date.now());
      
      if (basicInfo.title !== undefined) {
        setClauses.push('title = ?');
        values.push(basicInfo.title);
      }
      if (basicInfo.description !== undefined) {
        setClauses.push('description = ?');
        values.push(basicInfo.description);
      }
      if (basicInfo.authors !== undefined) {
        setClauses.push('author = ?');
        values.push(basicInfo.authors.join(', '));
      }
      if (basicInfo.genres !== undefined) {
        setClauses.push('tags = ?');
        values.push(JSON.stringify(basicInfo.genres));
      }
      if (basicInfo.isPrivate !== undefined) {
        setClauses.push('isPrivate = ?');
        values.push(basicInfo.isPrivate ? 1 : 0);
      }
      
      if (setClauses.length === 1) {
        // 只有updateTime，没有其他字段需要更新
        logger.warn(TAG, `没有需要更新的字段: ${comicId}`);
        return;
      }
      
      // 添加WHERE条件的值
      values.push(comicId);
      
      const sql = `UPDATE comic_info SET ${setClauses.join(', ')} WHERE id = ?`;
      logger.debug(TAG, `执行更新SQL: ${sql}, 参数: ${JSON.stringify(values)}`);
      
      await this.databaseManager.executeSql(sql, values);
      logger.info(TAG, `漫画基础信息更新成功: ${comicId}`);
      
      // 验证更新是否成功
      const verifySql = 'SELECT * FROM comic_info WHERE id = ?';
      const verifyResult = await this.databaseManager.querySql(verifySql, [comicId]);
      if (verifyResult.length > 0) {
        const record = verifyResult[0] as Record<string, ESObject>;
        logger.info(TAG, `验证更新结果: comicId=${comicId}, isPrivate=${record.isPrivate}, 记录字段: ${Object.keys(record).join(', ')}`);
      }
    } catch (error) {
      logger.error(TAG, `更新漫画基础信息失败: ${comicId}`);
      logger.error(TAG, `错误详情: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 通用：通过逐表查询检测内容类型
   * [修复] HarmonyOS RDB 的 UNION ALL 查询不保留列别名，改为逐表 COUNT 查询
   * @returns 'comic' | 'online' | 'ebook' | 'novel' | null
   */
  private async detectContentType(contentId: string): Promise<string | null> {
    try {
      // 按优先级顺序检查各表
      const tables: [string, string][] = [
        ['comic_info', 'comic'],
        ['online_comic_info', 'online'],
        ['ebook_info', 'ebook'],
        ['novel_book', 'novel']
      ];
      for (const entry of tables) {
        const tableName = entry[0];
        const typeName = entry[1];
        const result = await this.databaseManager.querySql(
          `SELECT id FROM ${tableName} WHERE id = ? LIMIT 1`, [contentId]
        );
        if (result && result.length > 0) {
          logger.debug(TAG, `detectContentType: id=${contentId}, type=${typeName} (找到于 ${tableName})`);
          return typeName;
        }
      }
      logger.debug(TAG, `detectContentType: id=${contentId}, 未在任何表中找到`);
      return null;
    } catch (error) {
      logger.error(TAG, `检测内容类型失败: ${contentId}`, String(error));
      return null;
    }
  }

  /**
   * 通用方法：根据ID更新任意内容的隐私状态
   * [性能优化] 使用 UNION ALL 单条 SQL 检测类型，在线漫画改用 UPDATE 替代 DELETE+INSERT
   */
  public async updateContentPrivacy(contentId: string, isPrivate: boolean): Promise<boolean> {
    try {
      logger.info(TAG, `更新内容隐私状态: ${contentId}, isPrivate=${isPrivate}`);
      const now = Date.now();
      const privacyValue = isPrivate ? 1 : 0;
      
      const contentType = await this.detectContentType(contentId);
      if (!contentType) {
        logger.error(TAG, `未找到内容: ${contentId}`);
        return false;
      }
      
      switch (contentType) {
        case 'comic':
          await this.updateComicBasicInfo(contentId, { isPrivate });
          logger.info(TAG, `已更新本地漫画隐私状态: ${contentId}`);
          return true;
        case 'online':
          await this.databaseManager.executeSql(
            'UPDATE online_comic_info SET isPrivate = ?, updateTime = ? WHERE id = ?',
            [privacyValue, now, contentId]
          );
          logger.info(TAG, `已更新在线漫画隐私状态: ${contentId}`);
          return true;
        case 'ebook':
          await this.databaseManager.executeSql(
            'UPDATE ebook_info SET isPrivate = ?, updateTime = ? WHERE id = ?',
            [privacyValue, now, contentId]
          );
          logger.info(TAG, `已更新电子书隐私状态: ${contentId}`);
          return true;
        case 'novel':
          await this.databaseManager.executeSql(
            'UPDATE novel_book SET isPrivate = ?, updateTime = ? WHERE id = ?',
            [privacyValue, now, contentId]
          );
          logger.info(TAG, `已更新小说隐私状态: ${contentId}`);
          return true;
        default:
          logger.error(TAG, `未知内容类型: ${contentType}`);
          return false;
      }
    } catch (error) {
      logger.error(TAG, `更新内容隐私状态失败: ${contentId}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 通用方法：根据ID更新任意内容的NSFW状态
   * [性能优化] 使用 UNION ALL 单条 SQL 检测类型，在线漫画改用 UPDATE 替代 DELETE+INSERT
   */
  public async updateContentNSFW(contentId: string, isNSFW: boolean): Promise<boolean> {
    try {
      logger.info(TAG, `更新内容NSFW状态: ${contentId}, isNSFW=${isNSFW}`);
      const now = Date.now();
      const nsfwValue = isNSFW ? 1 : 0;
      
      const contentType = await this.detectContentType(contentId);
      if (!contentType) {
        logger.error(TAG, `未找到内容: ${contentId}`);
        return false;
      }
      
      switch (contentType) {
        case 'comic':
          await this.databaseManager.executeSql(
            'UPDATE comic_info SET isNSFW = ?, updateTime = ? WHERE id = ?',
            [nsfwValue, now, contentId]
          );
          logger.info(TAG, `已更新本地漫画NSFW状态: ${contentId}`);
          return true;
        case 'online':
          await this.databaseManager.executeSql(
            'UPDATE online_comic_info SET isNSFW = ?, updateTime = ? WHERE id = ?',
            [nsfwValue, now, contentId]
          );
          logger.info(TAG, `已更新在线漫画NSFW状态: ${contentId}`);
          return true;
        case 'ebook':
          await this.databaseManager.executeSql(
            'UPDATE ebook_info SET isNSFW = ?, updateTime = ? WHERE id = ?',
            [nsfwValue, now, contentId]
          );
          logger.info(TAG, `已更新电子书NSFW状态: ${contentId}`);
          return true;
        case 'novel':
          await this.databaseManager.executeSql(
            'UPDATE novel_book SET isNSFW = ?, updateTime = ? WHERE id = ?',
            [nsfwValue, now, contentId]
          );
          logger.info(TAG, `已更新小说NSFW状态: ${contentId}`);
          return true;
        default:
          logger.error(TAG, `未知内容类型: ${contentType}`);
          return false;
      }
    } catch (error) {
      logger.error(TAG, `更新内容NSFW状态失败: ${contentId}, ${String(error)}`);
      return false;
    }
  }

  /**
   * 根据ID获取单个章节
   */
  public async getChapterById(chapterId: string): Promise<ChapterInfo | null> {
    try {
      const records = await this.databaseManager.query(
        'chapter',
        undefined, // columns
        `id = ?`, // whereClause
        [chapterId] // whereArgs
      );

      if (records.length === 0) {
        logger.warn(TAG, `未找到ID为 ${chapterId} 的章节`);
        return null;
      }

      return this.convertRecordToChapterInfo(records[0] as ChapterInfoDatabaseRecord);
    } catch (error) {
      logger.error(TAG, `根据ID获取章节失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 添加章节信息
   */
  public async addChapterInfo(chapter: ChapterInfoInput): Promise<string> {
    try {
      // 确保externalId不为undefined
      const tempExternalId = chapter.externalId || this.generateId();
      
      // 检查是否已存在相同externalId的章节（根据数据库唯一性约束）
      const checkSql = `SELECT id FROM chapter WHERE comicId = ? AND externalId = ?`;
      logger.debug(TAG, `🔍 [数据库SELECT] 表名=chapter, 查询条件: comicId=${chapter.comicId}, externalId=${tempExternalId}`);
      const existing = await this.databaseManager.querySql(checkSql, [chapter.comicId, tempExternalId]);
      
      if (existing.length > 0) {
        logger.info(TAG, `⚠️ [数据库SELECT结果] 表名=chapter, 章节已存在: "${chapter.title}", internalId=${existing[0].id}, externalId=${tempExternalId}`);
        return String(existing[0].id);
      }
      
      logger.debug(TAG, `📋 [数据库SELECT结果] 表名=chapter, 章节不存在，准备插入新记录`);
      
      const generatedId = this.generateId();
      const now = Date.now();
      const chapterData: ChapterInfo = {
        id: generatedId,
        comicId: chapter.comicId,
        title: chapter.title,
        index: chapter.index,
        pageCount: chapter.pageCount,
        isDownloaded: chapter.isDownloaded,
        downloadPath: chapter.downloadPath,
        publishTime: chapter.publishTime,
        addTime: now
      };
      
      // 确保externalId不为undefined
      const finalExternalId = chapter.externalId || generatedId;
      
      const record: ChapterInfoDatabaseRecord = {
        id: chapterData.id,
        comicId: chapterData.comicId,
        externalId: finalExternalId,  // 外部章节ID
        title: chapterData.title,
        chapterIndex: chapterData.index,
        chapterNumber: chapter.index,  // 使用index作为chapterNumber
        pageCount: chapterData.pageCount,
        isDownloaded: chapterData.isDownloaded,
        downloadPath: chapterData.downloadPath || null,
        publishTime: chapterData.publishTime,
        addTime: chapterData.addTime,
        createTime: now,  // 创建时间
        updateTime: now   // 更新时间
      };

      logger.info(TAG, `📝 [数据库INSERT] 表名=chapter` +
        `, id=${record.id}` +
        `, comicId=${record.comicId}` +
        `, externalId=${record.externalId}` +
        `, title="${record.title}"` +
        `, chapterIndex=${record.chapterIndex}`);

      await this.databaseManager.insert('chapter', record);
      logger.info(TAG, `✅ [数据库INSERT成功] 表名=chapter, 章节="${chapterData.title}", internalId=${chapterData.id}, externalId=${finalExternalId}`);

      return chapterData.id;
    } catch (error) {
      logger.error(TAG, `添加章节信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 更新章节信息
   */
  public async updateChapterInfo(chapterId: string, updates: Partial<ChapterInfo>): Promise<void> {
    try {
      // 构建更新记录，使用UpdateRecordData接口
      const updateRecord: UpdateRecordData = {
        id: chapterId // 必须提供id字段
      };
      
      if (updates.title !== undefined) {
        updateRecord.title = updates.title;
      }
      if (updates.index !== undefined) {
        // UpdateRecordData没有index字段，需要通过其他方式处理或忽略
        logger.warn(TAG, 'index字段更新暂不支持');
      }
      if (updates.pageCount !== undefined) {
        updateRecord.totalPages = updates.pageCount; // 映射到totalPages字段
      }
      if (updates.isDownloaded !== undefined) {
        updateRecord.isDownloaded = updates.isDownloaded;
      }
      if (updates.downloadPath !== undefined) {
        updateRecord.downloadPath = updates.downloadPath;
      }
      if (updates.publishTime !== undefined) {
        // UpdateRecordData没有publishTime字段，需要通过其他方式处理或忽略
        logger.warn(TAG, 'publishTime字段更新暂不支持');
      }

      await this.databaseManager.update(
        'chapter',
        updateRecord,
        'id = ?',
        [chapterId]
      );
      
      logger.debug(TAG, `更新章节信息: ${chapterId}`);
    } catch (error) {
      logger.error(TAG, `更新章节信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 根据ID获取单个章节
   */
  public async getChapterInfo(chapterId: string): Promise<ChapterInfo | null> {
    try {
      const records = await this.databaseManager.query(
        'chapter',
        undefined, // columns
        `id = ?`, // whereClause
        [chapterId] // whereArgs
      );

      if (records.length === 0) {
        logger.warn(TAG, `未找到ID为 ${chapterId} 的章节`);
        return null;
      }

      return this.convertRecordToChapterInfo(records[0] as ChapterInfoDatabaseRecord);
    } catch (error) {
      logger.error(TAG, `根据ID获取章节失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取漫画章节列表
   */
  public async getComicChapters(comicId: string): Promise<ChapterInfo[]> {
    try {
      logger.info(TAG, `🔍 [数据库QUERY] 表名=chapter, 查询条件: comicId=${comicId}, 排序: chapterNumber ASC`);
      
      const records = await this.databaseManager.query(
        'chapter',
        undefined,
        'comicId = ?',
        [comicId],
        'chapterNumber ASC'
      );
      
      logger.info(TAG, `📊 [数据库QUERY结果] 表名=chapter, 查询到章节记录数量: ${records.length}`);
      
      // 先打印原始数据库记录
      if (records.length > 0) {
        const firstRecord = records[0] as ChapterInfoDatabaseRecord;
        logger.debug(TAG, `📋 [数据库原始记录示例] 表名=chapter, id=${firstRecord.id}, externalId=${firstRecord.externalId || 'undefined'}, title="${firstRecord.title}"`);
      }
      
      const chapters = records.map(record => this.convertRecordToChapterInfo(record as ChapterInfoDatabaseRecord));
      
      // [调试] 输出每个章节的externalId以验证数据库存储和转换
      chapters.forEach(ch => {
        logger.info(TAG, `📄 [转换后章节] 表名=chapter, title="${ch.title}", internalId=${ch.id}, externalId=${ch.externalId || 'undefined'}`);
      });
      
      return chapters;
    } catch (error) {
      logger.error(TAG, `获取章节列表失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 根据漫画ID获取章节列表（别名方法，用于新的类型系统）
   */
  public async getChaptersByMangaId(mangaId: string): Promise<ChapterInfo[]> {
    return this.getComicChapters(mangaId);
  }

  /**
   * 根据章节ID获取页面列表（别名方法，用于新的类型系统）
   */
  public async getPagesByChapterId(chapterId: string): Promise<PageInfo[]> {
    return this.getChapterPages(chapterId);
  }

  /**
   * 【WebView专用】根据外部章节ID获取章节信息（包括内部ID）
   * 用于WebView图源，通过外部ID查找数据库中的章节记录
   * @param comicId 漫画的内部ID
   * @param externalChapterId 章节的外部ID（从图源API获取的原始ID）
   * @returns 章节信息，如果未找到则返回null
   */
  public async getChapterByExternalId(comicId: string, externalChapterId: string): Promise<ChapterInfo | null> {
    try {
      logger.info(TAG, `🔍 [数据库QUERY] [WebView专用] 表名=chapter, 查询条件: comicId=${comicId}, externalId=${externalChapterId}`);
      
      if (!externalChapterId || externalChapterId.trim().length === 0) {
        const errorMsg = `❌ 严重错误：外部章节ID为空！comicId=${comicId}`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
      
      const records = await this.databaseManager.query(
        'chapter',
        undefined,
        'comicId = ? AND externalId = ?',
        [comicId, externalChapterId]
      );
      
      if (records.length === 0) {
        logger.warn(TAG, `⚠️ [数据库QUERY结果] 表名=chapter, 未找到章节: comicId=${comicId}, externalChapterId=${externalChapterId}`);
        return null;
      }
      
      if (records.length > 1) {
        logger.warn(TAG, `⚠️ [数据库QUERY结果] 表名=chapter, 发现重复章节记录: comicId=${comicId}, externalChapterId=${externalChapterId}, count=${records.length}`);
      }
      
      const rawRecord = records[0] as ChapterInfoDatabaseRecord;
      logger.debug(TAG, `📋 [数据库原始记录] 表名=chapter, id=${rawRecord.id}, externalId=${rawRecord.externalId || 'undefined'}, title="${rawRecord.title}"`);
      
      const chapterInfo = this.convertRecordToChapterInfo(rawRecord);
      logger.info(TAG, `✅ [数据库QUERY结果] [转换后] 表名=chapter, title="${chapterInfo.title}", internalId=${chapterInfo.id}, externalId=${chapterInfo.externalId || 'undefined'}`);
      
      return chapterInfo;
    } catch (error) {
      const errorMsg = `❌ [WebView] 根据外部ID查询章节失败: comicId=${comicId}, externalChapterId=${externalChapterId}, error=${error}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 【WebView专用】根据外部章节ID获取完整章节信息（包括页面列表）
   * 用于WebView图源阅读器，一次性获取章节和页面信息
   * @param comicId 漫画的内部ID
   * @param externalChapterId 章节的外部ID
   * @returns 包含章节信息和页面列表的对象，如果未找到则返回null
   */
  public async getChapterWithPagesByExternalId(
    comicId: string, 
    externalChapterId: string
  ): Promise<ChapterWithPages | null> {
    try {
      logger.info(TAG, `🔍 [WebView专用方法] 查询章节及页面: comicId=${comicId}, externalChapterId=${externalChapterId}`);
      
      // 1. 获取章节信息
      const chapterInfo = await this.getChapterByExternalId(comicId, externalChapterId);
      if (!chapterInfo) {
        logger.warn(TAG, `⚠️ [WebView专用方法] 章节不存在，无法获取页面`);
        return null;
      }
      
      // 2. 获取页面列表
      logger.info(TAG, `📄 [数据库QUERY] 表名=page, 查询条件: chapterId=${chapterInfo.id}`);
      const pages = await this.getChapterPages(chapterInfo.id);
      logger.info(TAG, `✅ [数据库QUERY结果] 表名=page, 获取到 ${pages.length} 个页面`);
      
      const result: ChapterWithPages = {
        chapter: chapterInfo,
        pages: pages
      };
      
      return result;
    } catch (error) {
      const errorMsg = `❌ [WebView] 根据外部ID查询章节及页面失败: comicId=${comicId}, externalChapterId=${externalChapterId}, error=${error}`;
      logger.error(TAG, errorMsg);
      throw new Error(errorMsg);
    }
  }

  /**
   * 按章节标题搜索章节（支持模糊匹配）
   */
  public async searchChaptersByTitle(keyword: string, comicId?: string): Promise<ChapterInfo[]> {
    try {
      let whereClause: string = 'title LIKE ?';
      const whereArgs: (string | number)[] = [`%${keyword}%`];

      if (comicId) {
        whereClause += ' AND comicId = ?';
        whereArgs.push(comicId);
      }

      const records = await this.databaseManager.query(
        'chapter',
        undefined,
        whereClause,
        whereArgs,
        'chapterNumber ASC'
      );

      return records.map((record: object) => this.convertRecordToChapterInfo(record as ChapterInfoDatabaseRecord));
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `按章节标题搜索失败: ${message}`);
      throw error as Error;
    }
  }

  /**
   * 按章节标题搜索关联的漫画（返回唯一漫画列表）
   */
  public async searchComicsByChapterTitle(keyword: string): Promise<ComicInfo[]> {
    try {
      const chapterRecords = await this.databaseManager.query(
        'chapter',
        undefined,
        'title LIKE ?',
        [`%${keyword}%`],
        'chapterNumber ASC'
      );

      // 收集唯一的漫画ID
      const comicIdSet: Set<string> = new Set<string>();
      for (let i = 0; i < chapterRecords.length; i++) {
        const record = chapterRecords[i] as ChapterInfoDatabaseRecord;
        if (typeof record.comicId === 'string' && record.comicId.length > 0) {
          comicIdSet.add(record.comicId);
        }
      }

      // 根据漫画ID获取漫画信息
      const comics: ComicInfo[] = [];
      const ids: string[] = Array.from(comicIdSet);
      for (let i = 0; i < ids.length; i++) {
        const id: string = ids[i];
        const comic = await this.getComicInfo(id);
        if (comic) {
          comics.push(comic);
        }
      }

      return comics;
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `按章节标题搜索关联漫画失败: ${message}`);
      throw error as Error;
    }
  }

  /**
   * 批量添加章节
   */
  public async batchAddChapters(comicId: string, chapterData: ChapterInfo[]): Promise<void> {
    try {
      const now = Date.now();
      const records: ChapterInfoDatabaseRecord[] = chapterData.map(chapter => {
        const record: ChapterInfoDatabaseRecord = {
          id: chapter.id,
          comicId: chapter.comicId,
          externalId: chapter.id,  // 使用章节ID作为externalId
          title: chapter.title,
          chapterIndex: chapter.index,
          chapterNumber: chapter.index,  // 使用index作为chapterNumber
          pageCount: chapter.pageCount,
          isDownloaded: chapter.isDownloaded,
          downloadPath: chapter.downloadPath || null,
          publishTime: chapter.publishTime,
          addTime: chapter.addTime,
          createTime: now,
          updateTime: now
        };
        return record;
      });

      // 使用IGNORE策略防止重复章节导致的插入失败
      await this.databaseManager.batchInsert('chapter', records, 'IGNORE');
      logger.info(TAG, `批量添加章节: ${chapterData.length} 个（重复章节已自动忽略）`);
    } catch (error) {
      logger.error(TAG, `批量添加章节失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 添加页面信息
   */
  public async addPageInfo(pageInfoInput: PageInfoInput): Promise<string> {
    try {
      const pageId = this.generateId();
      
      // 确保所有数值字段都是有效的整数
      const record: PageInfoDatabaseRecord = {
        id: pageId,
        chapterId: pageInfoInput.chapterId,
        index: Math.floor(pageInfoInput.index),
        imageUrl: pageInfoInput.imageUrl,
        localPath: pageInfoInput.localPath || null,
        width: Math.floor(pageInfoInput.width),
        height: Math.floor(pageInfoInput.height),
        fileSize: Math.floor(pageInfoInput.fileSize)
      };

      await this.databaseManager.insert('page', record);
      logger.debug(TAG, `添加页面信息成功: ${pageId}, index: ${record.index}, fileSize: ${record.fileSize}`);
      return pageId;
    } catch (error) {
      logger.error(TAG, `添加页面信息失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取章节页面列表
   */
  public async getChapterPages(chapterId: string): Promise<PageInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'page',
        undefined,
        'chapterId = ?',
        [chapterId],
        'pageNumber ASC'
      );
      return records.map(record => this.convertRecordToPageInfo(record as PageInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取页面列表失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取页面信息列表（别名方法）
   */
  public async getPageInfoList(chapterId: string): Promise<PageInfo[]> {
    return this.getChapterPages(chapterId);
  }

  /**
   * 删除指定章节的所有页面记录
   */
  public async removeChapterPages(chapterId: string): Promise<void> {
    try {
      await this.databaseManager.executeSql('DELETE FROM page WHERE chapterId = ?', [chapterId]);
      logger.debug(TAG, `删除章节页面记录: ${chapterId}`);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `删除章节页面记录失败: ${message}`);
      throw error as Error;
    }
  }

  // ==================== 收藏管理 ====================

  /**
   * 添加收藏
   * 注意：favorite表的id是INTEGER PRIMARY KEY AUTOINCREMENT，由数据库自动生成
   */
  public async addFavorite(favorite: FavoriteInfoInput): Promise<string> {
    try {
      // 先检查是否已存在
      const checkSql = `SELECT id FROM favorite WHERE comicId = ? AND userId = ?`;
      const existing = await this.databaseManager.querySql(checkSql, [favorite.comicId, favorite.userId]);
      
      if (existing.length > 0) {
        logger.info(TAG, `漫画已在收藏中: ${favorite.comicId}`);
        return String(existing[0].id);
      }
      
      const addTime = Date.now();
      
      // 使用直接SQL插入，避免INSERT OR REPLACE在AUTOINCREMENT表上的问题
      // favorite表的id是INTEGER PRIMARY KEY AUTOINCREMENT，由数据库自动生成
      const insertSql = `INSERT INTO favorite (comicId, userId, folderName, addTime, lastReadChapterId, lastReadPageNumber, lastReadTime, readProgress) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
      const values: (string | number)[] = [
        favorite.comicId,
        favorite.userId,
        'default',
        addTime,
        favorite.lastReadChapterId || '',
        0,
        favorite.lastReadTime || 0,
        0.0
      ];
      
      await this.databaseManager.executeSql(insertSql, values);
      logger.info(TAG, `添加收藏: ${favorite.comicId}`);

      // 查询刚插入的记录获取自动生成的ID
      const insertedRecords = await this.databaseManager.querySql(
        `SELECT id FROM favorite WHERE comicId = ? AND userId = ?`,
        [favorite.comicId, favorite.userId]
      );
      
      if (insertedRecords.length > 0) {
        return String(insertedRecords[0].id);
      }
      
      // 如果查询失败，返回comicId作为标识
      return favorite.comicId;
    } catch (error) {
      logger.error(TAG, `添加收藏失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取用户收藏列表
   */
  public async getUserFavorites(userId: string): Promise<FavoriteInfo[]> {
    try {
      const records = await this.databaseManager.query(
        'favorite',
        undefined,
        'userId = ?',
        [userId],
        'addTime DESC'
      );
      return records.map(record => this.convertRecordToFavoriteInfo(record as FavoriteInfoDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取收藏列表失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 移除收藏
   */
  public async removeFavorite(comicId: string, userId: string): Promise<void> {
    try {
      await this.databaseManager.delete('favorite', 'comicId = ? AND userId = ?', [comicId, userId]);
      logger.info(TAG, `移除收藏: ${comicId}`);
    } catch (error) {
      logger.error(TAG, `移除收藏失败: ${error}`);
      throw error as Error;
    }
  }

  // ==================== 阅读历史管理 ====================

  /**
   * 添加阅读历史
   */
  public async addReadHistory(history: ReadHistoryInput): Promise<number> {
    try {
      const historyData: ReadHistory = {
        id: this.generateId(),
        comicId: history.comicId,
        chapterId: history.chapterId,
        pageIndex: history.pageIndex,
        userId: history.userId,
        readTime: history.readTime,
        readDuration: history.readDuration
      };

      // 映射到数据库记录格式：pageIndex -> pageNumber, readDuration -> duration
      const record: ReadHistoryDatabaseRecord = {
        id: historyData.id,
        comicId: historyData.comicId,
        chapterId: historyData.chapterId,
        pageNumber: historyData.pageIndex,      // ReadHistory.pageIndex -> ReadHistoryDatabaseRecord.pageNumber
        userId: historyData.userId,
        readTime: historyData.readTime,
        duration: historyData.readDuration,     // ReadHistory.readDuration -> ReadHistoryDatabaseRecord.duration
        createTime: historyData.readTime
      };

      const rowId: number = await this.databaseManager.insert('read_history', record);
      // 返回数据库自增ID，确保后续使用一致
      return rowId;
    } catch (error) {
      logger.error(TAG, `添加阅读历史失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 添加在线阅读历史
   */
  public async addOnlineReadHistory(history: ReadHistoryInput): Promise<number> {
    try {
      const historyData: ReadHistory = {
        id: this.generateId(),
        comicId: history.comicId,
        chapterId: history.chapterId,
        pageIndex: history.pageIndex,
        userId: history.userId,
        readTime: history.readTime,
        readDuration: history.readDuration
      };

      const record: ReadHistoryDatabaseRecord = {
        id: historyData.id,
        comicId: historyData.comicId,
        chapterId: historyData.chapterId,
        pageNumber: historyData.pageIndex,
        userId: historyData.userId,
        readTime: historyData.readTime,
        duration: historyData.readDuration,
        createTime: historyData.readTime
      };

      const rowId: number = await this.databaseManager.insert('online_read_history', record);
      return rowId;
    } catch (error) {
      logger.error(TAG, `添加在线阅读历史失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取在线漫画的阅读历史记录
   */
  public async getOnlineReadHistoryByComic(comicId: string): Promise<OnlineReadHistory[]> {
    try {
      const sql = 'SELECT * FROM online_read_history WHERE comicId = ? ORDER BY readTime DESC';
      const result = await this.databaseManager.querySql(sql, [comicId]);
      
      if (!result || result.length === 0) {
        return [];
      }
      
      const historyList: OnlineReadHistory[] = [];
      for (const record of result) {
        const rec: ESObject = record as ESObject;
        const history: OnlineReadHistory = {
          id: String(rec.id),
          comicId: String(rec.comicId),
          chapterId: String(rec.chapterId),
          pageIndex: Number(rec.pageNumber),
          readTime: Number(rec.readTime),
          createTime: Number(rec.createTime)
        };
        historyList.push(history);
      }
      
      return historyList;
    } catch (error) {
      logger.error(TAG, `获取在线漫画阅读历史失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 获取用户阅读历史
   */
  public async getUserReadHistory(userId: string, limit: number = 50): Promise<ReadHistory[]> {
    try {
      // [修复] 同时获取本地和在线阅读历史
      const localRecords = await this.databaseManager.query(
        'read_history',
        undefined,
        'userId = ?',
        [userId],
        'readTime DESC',
        limit
      );
      const localHistory = localRecords.map(record => this.convertRecordToReadHistory(record as ReadHistoryDatabaseRecord));
      
      // 获取在线阅读历史
      let onlineHistory: ReadHistory[] = [];
      try {
        const onlineRecords = await this.databaseManager.query(
          'online_read_history',
          undefined,
          'userId = ?',
          [userId],
          'readTime DESC',
          limit
        );
        onlineHistory = onlineRecords.map(record => this.convertRecordToReadHistory(record as ReadHistoryDatabaseRecord));
      } catch (onlineErr) {
        logger.warn(TAG, `获取在线阅读历史失败: ${String(onlineErr)}`);
      }
      
      // 合并并按时间排序
      const allHistory = [...localHistory, ...onlineHistory];
      allHistory.sort((a, b) => b.readTime - a.readTime);
      
      // 返回限制数量
      return allHistory.slice(0, limit);
    } catch (error) {
      logger.error(TAG, `获取阅读历史失败: ${error}`);
      throw error as Error;
    }
  }
  
  /**
   * 清除用户阅读历史
   */
  public async clearUserReadHistory(userId: string): Promise<void> {
    try {
      await this.databaseManager.delete('read_history', 'userId = ?', [userId]);
      logger.info(TAG, `用户 ${userId} 的阅读历史已清除`);
    } catch (error) {
      logger.error(TAG, `清除阅读历史失败: ${error}`);
      throw error as Error;
    }
  }

  // ==================== 下载管理 ====================

  /**
   * 创建下载任务
   */
  public async createDownloadTask(task: DownloadTaskInput): Promise<string> {
    try {
      const taskData: DownloadTask = {
        id: this.generateId(),
        comicId: task.comicId,
        chapterId: task.chapterId,
        status: task.status,
        progress: task.progress,
        totalPages: task.totalPages,
        downloadedPages: task.downloadedPages,
        startTime: task.startTime,
        completeTime: task.completeTime,
        errorMessage: task.errorMessage,
        createTime: Date.now()
      };

      // 不包含id字段，让数据库自动生成
      const record: DownloadTaskDatabaseRecord = {
        comicId: taskData.comicId,
        chapterId: taskData.chapterId || '',
        taskType: 'chapter',
        status: taskData.status,
        progress: taskData.progress,
        totalSize: taskData.totalPages,
        downloadedSize: taskData.downloadedPages,
        downloadSpeed: 0.0,
        priority: 0,
        createTime: taskData.createTime,
        startTime: taskData.startTime || 0,
        completeTime: taskData.completeTime || 0,
        errorMessage: taskData.errorMessage || null
      };

      const insertedId = await this.databaseManager.insert('download_task', record);
      logger.info(TAG, `创建下载任务: ${task.chapterId}, ID: ${insertedId}`);

      return String(insertedId);
    } catch (error) {
      logger.error(TAG, `创建下载任务失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 更新下载任务状态
   */
  public async updateDownloadTask(taskId: string, updates: DownloadTaskUpdate): Promise<void> {
    try {
      const updateData: UpdateRecordData = {
        id: taskId
      };

      // 逐个赋值属性而不是使用扩展运算符
      if (updates.status !== undefined) updateData.status = updates.status;
      if (updates.progress !== undefined) updateData.progress = updates.progress;
      if (updates.downloadedPages !== undefined) updateData.downloadPath = updates.downloadedPages.toString(); // 映射到downloadPath
      if (updates.errorMessage !== undefined) updateData.description = updates.errorMessage; // 映射到description
      // 更新updateTime
      updateData.updatedAt = Date.now().toString();

      await this.databaseManager.update(
        'download_task',
        updateData,
        'id = ?',
        [taskId]
      );
    } catch (error) {
      logger.error(TAG, `更新下载任务失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 获取下载任务列表
   */
  public async getDownloadTasks(status?: string): Promise<DownloadTask[]> {
    try {
      const whereClause = status ? 'status = ?' : undefined;
      const whereArgs = status ? [status] : undefined;
      const records = await this.databaseManager.query(
        'download_task',
        undefined,
        whereClause,
        whereArgs,
        'createTime DESC'
      );
      return records.map(record => this.convertRecordToDownloadTask(record as DownloadTaskDatabaseRecord));
    } catch (error) {
      logger.error(TAG, `获取下载任务失败: ${error}`);
      throw error as Error;
    }
  }

  // ==================== 文件操作 ====================

  /**
   * 保存图片到本地
   */
  public async saveImageToLocal(imageUrl: string, fileName: string, directory: 'covers' | 'chapters'): Promise<string> {
    try {
      // 使用图片缓存管理器加载图片
      const pixelMap = await this.imageCacheManager.loadImage(imageUrl);

      if (!pixelMap) {
        throw new Error('加载图片失败');
      }

      // 生成本地文件路径
      const localPath = `${this.sandboxManager.getDirectory(directory)}/${fileName}`;

      // 将PixelMap保存为JPEG文件
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 85
      };

      const imagePacker = image.createImagePacker();
      const imageBuffer: ArrayBuffer = await imagePacker.packing(pixelMap, packOpts);

      // 写入文件到沙箱
      await this.sandboxManager.writeFile(localPath, imageBuffer);

      // 释放PixelMap资源，避免内存泄漏
      pixelMap.release();

      logger.debug(TAG, `保存图片: ${imageUrl} -> ${localPath}`);
      return localPath;
    } catch (error) {
      logger.error(TAG, '保存图片失败', String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 创建漫画归档
   */
  public async createComicArchive(chapterId: string): Promise<string> {
    try {
      // 获取章节信息
      const chapters = await this.databaseManager.query(
        'chapter',
        undefined,
        'id = ?',
        [chapterId]
      );

      if (chapters.length === 0) {
        throw new Error('章节不存在');
      }

      const chapter = chapters[0] as ChapterInfoDatabaseRecord;

      // 获取页面信息
      const pages = await this.getChapterPages(chapterId);

      // 构建章节信息
      const chapterInfo: ComicChapterInfo = {
        chapterId: chapter.id as string,
        chapterTitle: chapter.title as string,
        comicId: chapter.comicId as string,
        comicTitle: '', // 需要从漫画信息中获取
        pageCount: pages.length,
        pages: pages.map(page => {
          const pageRecord = page as PageInfoDatabaseRecord;
          const pageArchive: ComicPageInfo = {
            pageIndex: pageRecord.index,
            fileName: `page_${pageRecord.index}.jpg`,
            filePath: pageRecord.localPath ?? '',
            fileSize: pageRecord.fileSize,
            mimeType: 'image/jpeg'
          };
          return pageArchive;
        })
      };

      // 创建CBZ归档
      const archivePath = await this.archiveManager.createCbzArchive(chapterInfo);
      // 更新章节下载状态 - 使用明确的接口定义
      const chapterUpdateData: UpdateRecordData = {
        id: chapterId,
        isDownloaded: true,
        downloadPath: archivePath
      };

      await this.databaseManager.update(
        'chapter',
        chapterUpdateData,
        'id = ?',
        [chapterId]
      );

      return archivePath;
    } catch (error) {
      logger.error(TAG, '创建漫画归档失败', String(error));
      throw new Error(String(error));
    }
  }

  // ==================== 数据备份与恢复 ====================

  /**
   * 备份数据
   */
  public async backupData(): Promise<string> {
    try {
      const backupDir = `${this.sandboxManager.getDirectory('database')}/backups`;
      const backupFileName = `backup_${TimeUtils.toISOString(Date.now()).replace(/[:.]/g, '-')}.db`;
      const backupPath = `${backupDir}/${backupFileName}`;

      // 创建备份目录
      if (!await this.sandboxManager.exists(backupDir)) {
        await this.sandboxManager.createDirectory(backupDir);
      }

      // 执行数据库备份 - 使用文件复制方式
      const dbPath = this.sandboxManager.getDirectory('database') + '/manxia_comic.db';
      await this.sandboxManager.copyFile(dbPath, backupPath);

      // 清理旧备份文件
      await this.cleanupOldBackups(backupDir);

      logger.info(TAG, `数据备份完成: ${backupPath}`);
      return backupPath;
    } catch (error) {
      logger.error(TAG, '数据备份失败', String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 恢复数据
   */
  public async restoreData(backupPath: string): Promise<void> {
    try {
      if (!await this.sandboxManager.exists(backupPath)) {
        throw new Error('备份文件不存在');
      }

      // 关闭当前数据库连接
      await this.databaseManager.close();

      // 恢复数据库文件
      const dbPath = this.sandboxManager.getDirectory('database') + '/manxia_comic.db';
      await this.sandboxManager.copyFile(backupPath, dbPath);

      // 重新初始化数据库
      // 这里需要获取context，可能需要从外部传入

      logger.info(TAG, `数据恢复完成: ${backupPath}`);
    } catch (error) {
      logger.error(TAG, '数据恢复失败', String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 清理旧备份文件
   */
  private async cleanupOldBackups(backupDir: string): Promise<void> {
    try {
      const files = await this.sandboxManager.listDirectory(backupDir);
      const backupFiles = files.filter(file => file.startsWith('backup_') && file.endsWith('.db'));

      if (backupFiles.length > this.config.maxBackupFiles) {
        // 按文件名排序（时间戳）
        backupFiles.sort();

        // 删除最旧的文件
        const filesToDelete = backupFiles.slice(0, backupFiles.length - this.config.maxBackupFiles);

        for (const file of filesToDelete) {
          const filePath = `${backupDir}/${file}`;
          await this.sandboxManager.deleteFile(filePath);
          logger.debug(TAG, `删除旧备份文件: ${file}`);
        }
      }
    } catch (error) {
      logger.error(TAG, '清理旧备份文件失败', String(error));
    }
  }

  // ==================== 统计信息 ====================

  /**
   * 获取数据统计信息
   */
  public async getDataStats(): Promise<DataStats> {
    try {
      const results = await Promise.all([
        this.getTableCount('comic_info'),
        this.getTableCount('chapter'),
        this.getTableCount('favorite'),
        this.getTableCount('download_task'),
        this.sandboxManager.getStorageStats(),
        this.imageCacheManager.getCacheStats()
      ]);

      const comicCount = results[0];
      const chapterCount = results[1];
      const favoriteCount = results[2];
      const downloadTaskCount = results[3];
      const storageStats = results[4];
      const cacheStats = results[5];

      return {
        comicCount,
        chapterCount,
        favoriteCount,
        downloadTaskCount,
        storageStats,
        cacheStats
      };
    } catch (error) {
      logger.error(TAG, '获取数据统计失败', String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 获取表记录数量
   * 使用 DatabaseManager 的类型安全聚合查询方法
   */
  private async getTableCount(tableName: string): Promise<number> {
    try {
      return await this.databaseManager.getTableCount(tableName);
    } catch (error) {
      logger.error(TAG, `获取表 ${tableName} 记录数失败`, String(error));
      return 0;
    }
  }

  // ==================== 工具方法 ====================

  /**
   * 生成唯一ID - 使用UUID生成器
   */
  private generateId(): string {
    return generateDbId('id');
  }

  /**
   * 转换遗留数字ID为字符串ID（用于数据迁移）
   */
  private convertLegacyIdToString(id: number | string): string {
    return convertLegacyId(id);
  }

  /**
   * 验证ID格式是否有效
   */
  private validateId(id: string): boolean {
    return isValidId(id);
  }

  /**
   * 启动定时任务
   */
  private startTimers(): void {
    if (this.config.enableAutoBackup && !this.backupTimer) {
      this.backupTimer = setInterval(() => {
        this.backupData().catch((error: BusinessError) => {
          logger.error(TAG, '自动备份失败', String(error));
        });
      }, this.config.backupInterval);
    }

    if (this.config.enableDataSync && !this.syncTimer) {
      this.syncTimer = setInterval(() => {
        // 这里可以实现数据同步逻辑
        logger.debug(TAG, '执行数据同步');
      }, this.config.syncInterval);
    }
  }

  /**
   * 停止定时任务
   */
  private stopTimers(): void {
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
      this.backupTimer = null;
    }

    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
  }

  /**
   * 销毁数据管理器
   */
  public destroy(): void {
    this.stopTimers();
    this.sandboxManager.destroy();
    DataManager.instance = null;
    logger.info(TAG, '数据管理器已销毁');
  }

  // ==================== 用户设置管理 ====================

  /**
   * 获取用户设置
   * @param userId 用户ID
   * @param key 设置键名
   * @returns Promise<string | null> 设置值（JSON字符串）
   */
  public async getUserSetting(userId: string, key: string): Promise<string | null> {
    try {
      const sql = 'SELECT settingValue FROM user_settings WHERE userId = ? AND settingKey = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [userId, key]);
      
      if (result && result.length > 0) {
        const row: UserSettingQueryResult = result[0] as UserSettingQueryResult;
        const settingValue = row.settingValue;
        return settingValue !== null && settingValue !== undefined ? String(settingValue) : null;
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, `获取用户设置失败: userId=${userId}, key=${key}`, String(error));
      throw new Error(String(error));
    }
  }

  /**
   * 保存用户设置
   * @param userId 用户ID
   * @param key 设置键名
   * @param value 设置值（JSON字符串）
   */
  public async saveUserSetting(userId: string, key: string, value: string): Promise<void> {
    try {
      const now = Date.now();
      
      // 使用INSERT OR REPLACE确保设置能被更新
      const sql = `
        INSERT OR REPLACE INTO user_settings 
        (userId, settingKey, settingValue, settingType, createTime, updateTime)
        VALUES (?, ?, ?, 'json', ?, ?)
      `;
      
      await this.databaseManager.executeSql(sql, [userId, key, value, now, now]);
      logger.info(TAG, `成功保存用户设置: userId=${userId}, key=${key}`);
    } catch (error) {
      logger.error(TAG, `保存用户设置失败: userId=${userId}, key=${key}`, String(error));
      throw new Error(String(error));
    }
  }

  /**
   * [性能优化] 获取指定漫画的最新一条阅读历史记录
   * 使用 UNION ALL 合并 read_history 和 online_read_history 两表，单条 SQL 完成
   * @param comicId 漫画ID
   * @param userId 用户ID
   * @returns Promise<ReadHistory | null> 最新的阅读历史记录
   */
  public async getLatestReadHistory(comicId: string, userId: string): Promise<ReadHistory | null> {
    try {
      const sql = `
        SELECT id, comicId, chapterId, userId, pageNumber, readTime, duration, createTime
        FROM (
          SELECT id, comicId, chapterId, userId, pageNumber, readTime, duration, createTime
          FROM read_history WHERE comicId = ? AND userId = ?
          UNION ALL
          SELECT id, comicId, chapterId, userId, pageNumber, readTime, duration, createTime
          FROM online_read_history WHERE comicId = ? AND userId = ?
        ) ORDER BY readTime DESC LIMIT 1
      `;
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [comicId, userId, comicId, userId]);
      if (result && result.length > 0) {
        const r = result[0] as ReadHistoryQueryResult;
        return {
          id: String(r.id),
          comicId: String(r.comicId),
          chapterId: String(r.chapterId),
          pageIndex: Number(r.pageNumber) || 0,
          userId: String(r.userId),
          readTime: Number(r.readTime),
          readDuration: Number(r.duration) || 0
        };
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取最新阅读历史失败: comicId=${comicId}`, String(error));
      return null;
    }
  }

  /**
   * 获取指定漫画的阅读历史记录（按时间倒序）
   * @param comicId 漫画ID
   * @param userId 用户ID
   * @param limit 返回记录数量限制
   * @returns Promise<ReadHistory[]> 阅读历史列表
   */
  public async getReadHistoryByComic(comicId: string, userId: string, limit: number = 10): Promise<ReadHistory[]> {
    try {
      // [修复] 同时查询本地和在线阅读历史表
      const localSql = `
        SELECT 
          id,
          comicId,
          chapterId,
          userId,
          pageNumber,
          readTime,
          duration,
          createTime
        FROM read_history 
        WHERE comicId = ? AND userId = ? 
        ORDER BY readTime DESC 
        LIMIT ?
      `;
      
      const onlineSql = `
        SELECT 
          id,
          comicId,
          chapterId,
          userId,
          pageNumber,
          readTime,
          duration,
          createTime
        FROM online_read_history 
        WHERE comicId = ? AND userId = ? 
        ORDER BY readTime DESC 
        LIMIT ?
      `;
      
      const historyList: ReadHistory[] = [];
      
      // 查询本地阅读历史
      try {
        const localResult: DatabaseRecord[] = await this.databaseManager.querySql(localSql, [comicId, userId, String(limit)]);
        if (localResult && localResult.length > 0) {
          for (const row of localResult) {
            const r = row as ReadHistoryQueryResult;
            historyList.push({
              id: String(r.id),
              comicId: String(r.comicId),
              chapterId: String(r.chapterId),
              pageIndex: Number(r.pageNumber) || 0,
              userId: String(r.userId),
              readTime: Number(r.readTime),
              readDuration: Number(r.duration) || 0
            });
          }
        }
      } catch (localErr) {
        logger.debug(TAG, `查询本地阅读历史失败: ${String(localErr)}`);
      }
      
      // 查询在线阅读历史
      try {
        const onlineResult: DatabaseRecord[] = await this.databaseManager.querySql(onlineSql, [comicId, userId, String(limit)]);
        if (onlineResult && onlineResult.length > 0) {
          for (const row of onlineResult) {
            const r = row as ReadHistoryQueryResult;
            historyList.push({
              id: String(r.id),
              comicId: String(r.comicId),
              chapterId: String(r.chapterId),
              pageIndex: Number(r.pageNumber) || 0,
              userId: String(r.userId),
              readTime: Number(r.readTime),
              readDuration: Number(r.duration) || 0
            });
          }
        }
      } catch (onlineErr) {
        logger.debug(TAG, `查询在线阅读历史失败: ${String(onlineErr)}`);
      }
      
      // 按时间排序并限制数量
      historyList.sort((a, b) => b.readTime - a.readTime);
      const result = historyList.slice(0, limit);
      
      logger.debug(TAG, `getReadHistoryByComic返回${result.length}条记录`);
      return result;
    } catch (error) {
      logger.error(TAG, `获取漫画阅读历史失败: comicId=${comicId}`, String(error));
      throw new Error(String(error));
    }
  }

  // ==================== 漫画删除 ====================

  /**
   * 删除漫画及其所有相关数据
   * @param comicId 漫画ID
   * @returns Promise<void>
   */
  public async deleteComic(comicId: string): Promise<void> {
    try {
      logger.info(TAG, `开始删除漫画: ${comicId}`);

      // 1. 获取漫画信息，用于确定文件存储路径和类型
      const comicInfo = await this.getComicById(comicId);
      const onlineComicInfo = await this.getOnlineComicInfoById(comicId);
      
      if (!comicInfo && !onlineComicInfo) {
        logger.warn(TAG, `漫画不存在: ${comicId}`);
        return;
      }
      
      const isOnlineManga = !!onlineComicInfo;
      logger.info(TAG, `漫画类型: ${isOnlineManga ? '在线漫画' : '本地漫画'}`);

      // 2. 获取所有章节信息，用于删除章节文件
      const chapters = isOnlineManga ? 
        await this.getOnlineComicChapters(comicId) : 
        await this.getComicChapters(comicId);
      
      // 3. 删除数据库中的所有相关记录
      if (isOnlineManga) {
        // 删除在线漫画相关表
        await this.databaseManager.executeSql('DELETE FROM online_page WHERE chapterId IN (SELECT id FROM online_chapter WHERE comicId = ?)', [comicId]);
        logger.debug(TAG, `删除在线漫画页面记录: ${comicId}`);
        
        await this.databaseManager.executeSql('DELETE FROM online_chapter WHERE comicId = ?', [comicId]);
        logger.debug(TAG, `删除在线漫画章节记录: ${comicId}`);
        
        await this.databaseManager.executeSql('DELETE FROM online_comic_info WHERE id = ?', [comicId]);
        logger.debug(TAG, `删除在线漫画信息记录: ${comicId}`);
      } else {
        // 删除本地漫画相关表
        await this.databaseManager.executeSql('DELETE FROM page WHERE chapterId IN (SELECT id FROM chapter WHERE comicId = ?)', [comicId]);
        logger.debug(TAG, `删除本地漫画页面记录: ${comicId}`);
        
        await this.databaseManager.executeSql('DELETE FROM chapter WHERE comicId = ?', [comicId]);
        logger.debug(TAG, `删除本地漫画章节记录: ${comicId}`);
        
        await this.databaseManager.executeSql('DELETE FROM comic_info WHERE id = ?', [comicId]);
        logger.debug(TAG, `删除本地漫画信息记录: ${comicId}`);
      }
      
      // 删除通用表（阅读历史、收藏、下载任务）
      await this.databaseManager.executeSql('DELETE FROM read_history WHERE comicId = ?', [comicId]);
      logger.debug(TAG, `删除漫画阅读历史: ${comicId}`);
      
      await this.databaseManager.executeSql('DELETE FROM favorite WHERE comicId = ?', [comicId]);
      logger.debug(TAG, `删除漫画收藏记录: ${comicId}`);
      
      await this.databaseManager.executeSql('DELETE FROM download_task WHERE comicId = ?', [comicId]);
      logger.debug(TAG, `删除漫画下载任务: ${comicId}`);

      // 4. 删除本地文件
      try {
        const actualComicInfo = comicInfo || onlineComicInfo;
        if (actualComicInfo) {
          // 检查是否是Download目录导入的漫画（sourceId为download_import）
          const isDownloadImport = actualComicInfo.sourceId === 'download_import';
          logger.info(TAG, `删除漫画文件: sourceId=${actualComicInfo.sourceId}, isDownloadImport=${isDownloadImport}, 章节数=${chapters.length}`);
          
          if (isDownloadImport) {
            // Download目录导入的漫画：直接删除章节目录
            for (const chapter of chapters) {
              logger.info(TAG, `章节信息: title=${chapter.title}, downloadPath=${chapter.downloadPath}`);
              if (chapter.downloadPath) {
                try {
                  fs.accessSync(chapter.downloadPath);
                  logger.info(TAG, `开始删除章节目录: ${chapter.downloadPath}`);
                  // 递归删除目录
                  this.deleteDirectoryRecursive(chapter.downloadPath);
                  logger.debug(TAG, `删除Download章节目录: ${chapter.downloadPath}`);
                } catch (e) {
                  logger.warn(TAG, `删除Download章节目录失败: ${chapter.downloadPath}`);
                }
              }
            }
            
            // [修复] 尝试多种方式找到漫画目录并删除
            let mangaPath = '';
            
            // 方式1：从章节的downloadPath推断
            if (chapters.length > 0 && chapters[0].downloadPath) {
              mangaPath = chapters[0].downloadPath.substring(0, chapters[0].downloadPath.lastIndexOf('/'));
            }
            
            // 方式2：从coverLocalPath推断（仅本地漫画有此字段）
            const localComicInfo = actualComicInfo as ComicInfo;
            if (!mangaPath && localComicInfo.coverLocalPath) {
              const coverPath: string = localComicInfo.coverLocalPath;
              // 封面路径格式可能是: /Download/漫匣/漫画名/cover.jpg 或 /Download/漫匣/manga/漫画名/cover.jpg
              const pathParts: string[] = coverPath.split('/');
              // 找到漫画名所在的目录
              for (let i = pathParts.length - 2; i >= 0; i--) {
                if (pathParts[i] === actualComicInfo.title || 
                    pathParts[i] === this.sanitizeFileName(actualComicInfo.title)) {
                  mangaPath = pathParts.slice(0, i + 1).join('/');
                  break;
                }
              }
            }
            
            // 方式3：从Download同步目录直接构建路径
            if (!mangaPath) {
              const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
              if (downloadDirPath) {
                const sanitizedTitle = this.sanitizeFileName(actualComicInfo.title);
                // 检查manga子目录
                const mangaSubPath = `${downloadDirPath}/manga/${sanitizedTitle}`;
                if (fs.accessSync(mangaSubPath)) {
                  mangaPath = mangaSubPath;
                } else {
                  // 检查根目录
                  const rootPath = `${downloadDirPath}/${sanitizedTitle}`;
                  if (fs.accessSync(rootPath)) {
                    mangaPath = rootPath;
                  }
                }
              }
            }
            
            // 删除漫画主目录
            if (mangaPath) {
              try {
                if (fs.accessSync(mangaPath)) {
                  this.deleteDirectoryRecursive(mangaPath);
                  logger.info(TAG, `删除Download漫画目录: ${mangaPath}`);
                }
              } catch (e) {
                logger.warn(TAG, `删除Download漫画目录失败: ${mangaPath}, 错误: ${String(e)}`);
              }
            } else {
              logger.warn(TAG, `无法确定Download漫画目录路径: ${actualComicInfo.title}`);
            }
          } else {
            // 沙箱目录的漫画：使用原有逻辑
            const comicsDir = this.sandboxManager.getDirectory('comics');
            const sourceName = this.sanitizeFileName(actualComicInfo.sourceId || 'local');
            const comicName = this.sanitizeFileName(actualComicInfo.title);
            const comicPath = `${comicsDir}/${sourceName}/${comicName}`;
            
            // 检查目录是否存在，如果存在则删除
            if (await this.sandboxManager.exists(comicPath)) {
              // 删除所有章节目录及其内容
              for (const chapter of chapters) {
                if (chapter.downloadPath && await this.sandboxManager.exists(chapter.downloadPath)) {
                  await this.sandboxManager.deleteDirectory(chapter.downloadPath, true);
                  logger.debug(TAG, `删除章节目录: ${chapter.downloadPath}`);
                }
              }
              
              // 删除漫画主目录
              await this.sandboxManager.deleteDirectory(comicPath, true);
              logger.info(TAG, `删除漫画文件目录: ${comicPath}`);
            } else {
              logger.debug(TAG, `漫画文件目录不存在: ${comicPath}`);
            }
          }

          // 删除封面缓存
          if (actualComicInfo.coverUrl) {
            const coverPath = `${this.sandboxManager.getDirectory('covers')}/${comicId}.jpg`;
            if (await this.sandboxManager.exists(coverPath)) {
              await this.sandboxManager.deleteFile(coverPath);
              logger.debug(TAG, `删除封面缓存: ${coverPath}`);
            }
          }
        }
      } catch (fileError) {
        logger.error(TAG, `删除漫画文件失败: ${String(fileError)}`);
        // 文件删除失败不影响数据库删除，继续执行
      }

      logger.info(TAG, `成功删除漫画: ${comicId}`);
    } catch (error) {
      logger.error(TAG, `删除漫画失败: ${String(error instanceof Error ? error.message : error)}`);
      throw new Error(`删除漫画失败: ${String(error)}`);
    }
  }

  /**
   * 批量删除漫画
   * @param comicIds 漫画ID数组
   * @returns Promise<DeleteComicsResult>
   */
  public async deleteComics(comicIds: string[]): Promise<DeleteComicsResult> {
    const result: DeleteComicsResult = {
      successCount: 0,
      failedCount: 0,
      errors: []
    };

    for (const comicId of comicIds) {
      try {
        await this.deleteComic(comicId);
        result.successCount++;
      } catch (error) {
        result.failedCount++;
        result.errors.push(`${comicId}: ${String(error)}`);
      }
    }

    logger.info(TAG, `批量删除漫画完成: 成功=${result.successCount}, 失败=${result.failedCount}`);
    return result;
  }

  /**
   * 清理文件名中的非法字符（用于文件路径构建）
   */
  private sanitizeFileName(fileName: string): string {
    return fileName
      .replace(/[<>:"/\\|?*]/g, '_')  // 替换Windows非法字符
      .replace(/\s+/g, '_')          // 替换空格为下划线
      .replace(/_{2,}/g, '_')        // 合并多个下划线
      .replace(/^_|_$/g, '')         // 移除首尾下划线
      .substring(0, 100);            // 限制长度
  }

  // ==================== 设置管理方法 ====================

  /**
   * 获取所有设置
   */
  async getAllSettings(): Promise<UserSettingsDatabaseRecord[]> {
    try {
      const sql = 'SELECT * FROM user_settings WHERE userId = ?';
      const result = await this.databaseManager.querySql(sql, ['default_user']);
      return result as UserSettingsDatabaseRecord[];
    } catch (error) {
      logger.error(TAG, '获取所有设置失败', String(error));
      return [];
    }
  }

  /**
   * 获取单个设置
   */
  async getSetting(key: string): Promise<UserSettingsDatabaseRecord | null> {
    try {
      const sql = 'SELECT * FROM user_settings WHERE userId = ? AND settingKey = ?';
      const result = await this.databaseManager.querySql(sql, ['default_user', key]);
      if (result && result.length > 0) {
        return result[0] as UserSettingsDatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取设置失败: ${key}`, String(error));
      return null;
    }
  }

  /**
   * 保存设置
   */
  async saveSetting(key: string, value: string, type: string): Promise<void> {
    try {
      const existing = await this.getSetting(key);
      const now = Date.now();

      if (existing) {
        // 更新现有设置
        const sql = `UPDATE user_settings 
                     SET settingValue = ?, settingType = ?, updateTime = ? 
                     WHERE userId = ? AND settingKey = ?`;
        await this.databaseManager.executeSql(sql, [value, type, now, 'default_user', key]);
      } else {
        // 插入新设置（id使用自动递增，不需要手动指定）
        const sql = `INSERT INTO user_settings 
                     (userId, settingKey, settingValue, settingType, createTime, updateTime) 
                     VALUES (?, ?, ?, ?, ?, ?)`;
        await this.databaseManager.executeSql(sql, ['default_user', key, value, type, now, now]);
      }

      logger.debug(TAG, `设置已保存: ${key} = ${value}`);
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${key}`, String(error));
      throw error as Error;
    } 
  }

  /**
   * 删除设置
   */
  async deleteSetting(key: string): Promise<void> {
    try {
      const sql = 'DELETE FROM user_settings WHERE userId = ? AND settingKey = ?';
      await this.databaseManager.executeSql(sql, ['default_user', key]);
      logger.debug(TAG, `设置已删除: ${key}`);
    } catch (error) {
      logger.error(TAG, `删除设置失败: ${key}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 清空所有设置
   */
  async clearAllSettings(): Promise<void> {
    try {
      const sql = 'DELETE FROM user_settings WHERE userId = ?';
      await this.databaseManager.executeSql(sql, ['default_user']);
      logger.info(TAG, '所有设置已清空');
    } catch (error) {
      logger.error(TAG, '清空设置失败', String(error));
      throw error as Error;
    }
  }

  // ==================== 图源管理方法 ====================

  /**
   * 获取所有图源
   */
  async getAllComicSources(): Promise<DatabaseRecord[]> {
    try {
      const sql = 'SELECT * FROM comic_source ORDER BY priority DESC, createTime DESC';
      const result = await this.databaseManager.querySql(sql);
      return result;
    } catch (error) {
      logger.error(TAG, '获取所有图源失败', String(error));
      return [];
    }
  }

  /**
   * 获取启用的图源
   */
  async getEnabledComicSources(): Promise<DatabaseRecord[]> {
    try {
      const sql = 'SELECT * FROM comic_source WHERE isEnabled = 1 ORDER BY priority DESC';
      const result = await this.databaseManager.querySql(sql);
      return result;
    } catch (error) {
      logger.error(TAG, '获取启用的图源失败', String(error));
      return [];
    }
  }

  /**
   * 根据 pkg 获取图源记录
   */
  async getComicSourceByPkg(pkg: string): Promise<ComicSourceDatabaseRecord | null> {
    try {
      const sql: string = 'SELECT * FROM comic_source WHERE pkg = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [pkg]);
      if (result && result.length > 0) {
        return result[0] as ComicSourceDatabaseRecord;
      }
      logger.debug(TAG, `未找到图源记录: pkg=${pkg}`);
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源记录失败: pkg=${pkg}`, String(error));
      return null;
    }
  }

  /**
   * 根据名称获取图源记录
   */
  async getComicSourceByName(sourceName: string): Promise<ComicSourceDatabaseRecord | null> {
    try {
      const sql: string = 'SELECT * FROM comic_source WHERE name = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [sourceName]);
      if (result && result.length > 0) {
        return result[0] as ComicSourceDatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源记录失败: sourceName=${sourceName}`, String(error));
      return null;
    }
  }

  /**
   * 根据ID获取图源记录（兼容旧接口）
   * @deprecated 请使用 getComicSourceByName
   */
  async getComicSourceById(sourceId: number): Promise<ComicSourceDatabaseRecord | null> {
    try {
      const sql: string = 'SELECT * FROM comic_source WHERE id = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [String(sourceId)]);
      if (result && result.length > 0) {
        return result[0] as ComicSourceDatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源记录失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  // ==================== 图源置顶管理 ====================

  /**
   * 获取置顶图源ID列表
   */
  async getSourcePinnedList(): Promise<number[]> {
    try {
      const record = await this.getSetting('source:pinned_list');
      if (record && record.settingValue) {
        const ids = JSON.parse(record.settingValue) as number[];
        return ids;
      }
      return [];
    } catch (error) {
      logger.error(TAG, '获取置顶图源列表失败', String(error));
      return [];
    }
  }

  /**
   * 保存置顶图源ID列表
   */
  async setSourcePinnedList(ids: number[]): Promise<void> {
    try {
      await this.saveSetting('source:pinned_list', JSON.stringify(ids), 'json');
      logger.info(TAG, `已保存置顶图源列表: ${ids.length}个`);
    } catch (error) {
      logger.error(TAG, '保存置顶图源列表失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 添加图源到置顶列表
   */
  async addSourceToPinnedList(sourceId: number): Promise<void> {
    const pinnedList = await this.getSourcePinnedList();
    if (!pinnedList.includes(sourceId)) {
      pinnedList.unshift(sourceId);  // 添加到开头
      await this.setSourcePinnedList(pinnedList);
    }
  }

  /**
   * 从置顶列表移除图源
   */
  async removeSourceFromPinnedList(sourceId: number): Promise<void> {
    const pinnedList = await this.getSourcePinnedList();
    const index = pinnedList.indexOf(sourceId);
    if (index !== -1) {
      pinnedList.splice(index, 1);
      await this.setSourcePinnedList(pinnedList);
    }
  }

  /**
   * 检查图源是否已置顶
   */
  async isSourcePinned(sourceId: number): Promise<boolean> {
    const pinnedList = await this.getSourcePinnedList();
    return pinnedList.includes(sourceId);
  }

  // ==================== WebView 源配置：Cookie 管理 ====================

  /**
   * 获取指定图源的 WebView 源配置记录
   */
  async getWebViewSourceConfigRecord(sourceId: number): Promise<DatabaseRecord | null> {
    try {
      const sql: string = 'SELECT * FROM webview_source_config WHERE sourceId = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sql, [String(sourceId)]);
      if (result && result.length > 0) {
        return result[0] as DatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取WebView源配置失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  async ensureWebViewSourceConfigRecord(sourceId: number): Promise<void> {
    try {
      const sqlCheck: string = 'SELECT COUNT(1) AS cnt FROM webview_source_config WHERE sourceId = ?';
      const result: DatabaseRecord[] = await this.databaseManager.querySql(sqlCheck, [String(sourceId)]);
      let hasRow: boolean = false;
      if (!!result && result.length > 0) {
        const entries: [string, Object][] = Object.entries(result[0] as Object) as [string, Object][];
        let idx: number = 0;
        while (idx < entries.length) {
          const keyLower: string = entries[idx][0].toLowerCase();
          if (keyLower === 'cnt') {
            const cntVal: number = Number(entries[idx][1]);
            hasRow = cntVal > 0;
            break;
          }
          idx = idx + 1;
        }
      }
      if (hasRow) {
        return;
      }
      const now: number = Date.now();
      const sqlInsert: string = `INSERT INTO webview_source_config 
        (sourceId, webViewConfig, userAgent, customHeaders, cookiePolicy, jsEnabled, imageLoadingEnabled, cacheMode, timeout, retryCount, antiDetectionConfig, cookies, createTime, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      await this.databaseManager.executeSql(sqlInsert, [
        String(sourceId),
        '{}',
        '',
        '{}',
        'accept_all',
        1,
        1,
        'default',
        String(30000),
        String(3),
        '{}',
        '',
        String(now),
        String(now)
      ]);
      logger.info(TAG, `已初始化WebView源配置记录: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `初始化WebView源配置记录失败: sourceId=${sourceId}`, String(error));
    }
  }

  /**
   * 更新指定图源的 Cookie JSON
   */
  async updateWebViewSourceCookies(sourceId: number, cookiesJson: string): Promise<void> {
    try {
      await this.ensureWebViewSourceConfigRecord(sourceId);
      const now: number = Date.now();
      const sql: string = `UPDATE webview_source_config SET cookies = ?, updateTime = ? WHERE sourceId = ?`;
      await this.databaseManager.executeSql(sql, [cookiesJson, String(now), String(sourceId)]);
      logger.info(TAG, `已更新WebView源Cookie: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `更新WebView源Cookie失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  async updateSourceUserAgent(sourceId: number, userAgent: string): Promise<void> {
    try {
      await this.ensureWebViewSourceConfigRecord(sourceId);
      const now: number = Date.now();
      const sql: string = `UPDATE webview_source_config SET userAgent = ?, updateTime = ? WHERE sourceId = ?`;
      await this.databaseManager.executeSql(sql, [userAgent, String(now), String(sourceId)]);
      logger.info(TAG, `已更新图源User-Agent: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `更新图源User-Agent失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 清空指定图源的 Cookie
   */
  async clearWebViewSourceCookies(sourceId: number): Promise<void> {
    try {
      const now: number = Date.now();
      const sql: string = `UPDATE webview_source_config SET cookies = '', updateTime = ? WHERE sourceId = ?`;
      await this.databaseManager.executeSql(sql, [String(now), String(sourceId)]);
      logger.info(TAG, `已清空WebView源Cookie: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `清空WebView源Cookie失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  // ==================== ComicSource 表：Cookie 管理（统一存储） ====================

  async updateComicSourceCookiesByName(sourceName: string, cookiesJson: string): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = ? WHERE name = ?`;
      await this.databaseManager.executeSql(sql, [cookiesJson, sourceName]);
      logger.info(TAG, `已更新图源Cookie到comic_source: sourceName=${sourceName}`);
    } catch (error) {
      logger.error(TAG, `更新图源Cookie失败: sourceName=${sourceName}`, String(error));
      throw error as Error;
    }
  }

  async clearComicSourceCookiesByName(sourceName: string): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = '' WHERE name = ?`;
      await this.databaseManager.executeSql(sql, [sourceName]);
      logger.info(TAG, `已清空图源Cookie(comic_source): sourceName=${sourceName}`);
    } catch (error) {
      logger.error(TAG, `清空图源Cookie失败: sourceName=${sourceName}`, String(error));
      throw error as Error;
    }
  }

  async updateComicSourceCookiesByPkg(pkg: string, cookiesJson: string): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = ? WHERE pkg = ?`;
      await this.databaseManager.executeSql(sql, [cookiesJson, pkg]);
      logger.info(TAG, `已更新图源Cookie到comic_source: pkg=${pkg}`);
    } catch (error) {
      logger.error(TAG, `更新图源Cookie失败: pkg=${pkg}`, String(error));
      throw error as Error;
    }
  }

  async clearComicSourceCookiesByPkg(pkg: string): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = '' WHERE pkg = ?`;
      await this.databaseManager.executeSql(sql, [pkg]);
      logger.info(TAG, `已清空图源Cookie(comic_source): pkg=${pkg}`);
    } catch (error) {
      logger.error(TAG, `清空图源Cookie失败: pkg=${pkg}`, String(error));
      throw error as Error;
    }
  }

  /**
   * @deprecated 请使用 updateComicSourceCookiesByPkg
   */
  async updateComicSourceCookies(sourceId: number, cookiesJson: string): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = ? WHERE id = ?`;
      await this.databaseManager.executeSql(sql, [cookiesJson, String(sourceId)]);
      logger.info(TAG, `已更新图源Cookie到comic_source: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `更新图源Cookie失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * @deprecated 请使用 clearComicSourceCookiesByPkg
   */
  async clearComicSourceCookies(sourceId: number): Promise<void> {
    try {
      const sql: string = `UPDATE comic_source SET cookies = '' WHERE id = ?`;
      await this.databaseManager.executeSql(sql, [String(sourceId)]);
      logger.info(TAG, `已清空图源Cookie(comic_source): sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `清空图源Cookie失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 保存图源登录凭据（用户名/密码），存储到用户设置
   */
  async saveSourceCredentials(sourceId: number, username: string, password: string): Promise<void> {
    const key: string = `source:${String(sourceId)}:credentials`;
    const value: string = JSON.stringify({ username, password });
    await this.saveSetting(key, value, 'json');
  }

  /**
   * 获取图源登录凭据
   */
  async getSourceCredentials(sourceId: number): Promise<SourceCredentials | null> {
    const key: string = `source:${String(sourceId)}:credentials`;
    const record: UserSettingsDatabaseRecord | null = await this.getSetting(key);
    if (!record || !record.settingValue) {
      return null;
    }
    try {
      const parsed: Record<string, Object> = JSON.parse(record.settingValue);
      const username: string = parsed['username'] as string;
      const password: string = parsed['password'] as string;
      if (!username || !password) {
        return null;
      }
      return new SourceCredentials(username, password);
    } catch (error) {
      logger.error(TAG, `解析图源凭据失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  /**
   * 通过 sourceId 获取图源的 pkg（唯一标识符）
   * @param sourceId 数据库自动生成的图源ID
   * @returns pkg 字符串，如果未找到则返回 null
   */
  async getSourcePkgById(sourceId: number): Promise<string | null> {
    try {
      const sql = 'SELECT pkg FROM comic_source WHERE id = ?';
      const result = await this.databaseManager.querySql(sql, [sourceId]);
      if (result && result.length > 0) {
        const row: ESObject = result[0] as ESObject;
        const pkg = row.pkg as string;
        if (pkg && pkg.length > 0) {
          return pkg;
        }
        // 如果 pkg 为空，尝试从 configJson 中提取
        const configResult = await this.databaseManager.querySql(
          'SELECT configJson FROM comic_source WHERE id = ?', [sourceId]
        );
        if (configResult && configResult.length > 0) {
          const configRow: ESObject = configResult[0] as ESObject;
          const configJson = configRow.configJson as string;
          if (configJson) {
            try {
              const config: ESObject = JSON.parse(configJson) as ESObject;
              const metadata: ESObject = config.metadata as ESObject;
              if (metadata && metadata.id) {
                const extractedPkg = metadata.id as string;
                // 同时更新数据库中的 pkg 字段
                await this.databaseManager.executeSql(
                  'UPDATE comic_source SET pkg = ? WHERE id = ?', [extractedPkg, sourceId]
                );
                logger.info(TAG, `已从 configJson 提取并保存 pkg: ${extractedPkg} (sourceId=${sourceId})`);
                return extractedPkg;
              }
            } catch (parseErr) {
              logger.warn(TAG, `解析 configJson 失败: ${String(parseErr)}`);
            }
          }
        }
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源 pkg 失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  /**
   * 保存图源用户设置（通用键值）
   * [重构] 使用 pkg 作为键的一部分，确保图源删除/重装后设置不丢失
   */
  async saveSourceUserSetting(sourceId: number, keyName: string, value: string, type: string): Promise<void> {
    // 优先使用 pkg，如果获取不到则回退到 sourceId
    const pkg = await this.getSourcePkgById(sourceId);
    const keyIdentifier = pkg || `id_${String(sourceId)}`;
    const key: string = `source:${keyIdentifier}:${keyName}`;
    logger.debug(TAG, `保存图源设置: key=${key}, value=${value}`);
    await this.saveSetting(key, value, type);
  }

  /**
   * 获取图源用户设置
   * [重构] 使用 pkg 作为键的一部分，确保图源删除/重装后设置不丢失
   */
  async getSourceUserSetting(sourceId: number, keyName: string): Promise<UserSettingsDatabaseRecord | null> {
    // 优先使用 pkg，如果获取不到则回退到 sourceId
    const pkg = await this.getSourcePkgById(sourceId);
    const keyIdentifier = pkg || `id_${String(sourceId)}`;
    const key: string = `source:${keyIdentifier}:${keyName}`;
    logger.debug(TAG, `获取图源设置: key=${key}`);
    return await this.getSetting(key);
  }

  /**
   * [性能优化] 批量获取图源用户设置
   * 只调用一次 getSourcePkgById，使用 WHERE IN 单条 SQL 查询所有设置
   * @param sourceId 图源ID
   * @param keyNames 设置键名数组
   * @returns Map<keyName, UserSettingsDatabaseRecord>
   */
  async getSourceUserSettings(sourceId: number, keyNames: string[]): Promise<Map<string, UserSettingsDatabaseRecord>> {
    const result = new Map<string, UserSettingsDatabaseRecord>();
    if (keyNames.length === 0) return result;
    try {
      const pkg = await this.getSourcePkgById(sourceId);
      const keyIdentifier = pkg || `id_${String(sourceId)}`;
      
      // 构建完整 key 列表和占位符
      const fullKeys: string[] = keyNames.map((k: string) => `source:${keyIdentifier}:${k}`);
      const placeholders = fullKeys.map(() => '?').join(', ');
      const sql = `SELECT * FROM user_settings WHERE userId = ? AND settingKey IN (${placeholders})`;
      const args: (string | number)[] = ['default_user', ...fullKeys];
      
      const records = await this.databaseManager.querySql(sql, args);
      if (records && records.length > 0) {
        const prefix = `source:${keyIdentifier}:`;
        for (let i = 0; i < records.length; i++) {
          const rec = records[i] as UserSettingsDatabaseRecord;
          if (rec.settingKey && rec.settingKey.startsWith(prefix)) {
            const shortKey = rec.settingKey.substring(prefix.length);
            result.set(shortKey, rec);
          }
        }
      }
      logger.debug(TAG, `批量获取图源设置: sourceId=${sourceId}, 请求${keyNames.length}个, 返回${result.size}个`);
    } catch (error) {
      logger.error(TAG, `批量获取图源设置失败: sourceId=${sourceId}`, String(error));
    }
    return result;
  }

  /**
   * 获取图源所有自定义设置（以 custom. 开头的设置）
   * 返回 Map<settingKey, settingValue>，其中 settingKey 去掉了 'custom.' 前缀
   */
  async getSourceCustomSettings(sourceId: number): Promise<Map<string, string>> {
    const result = new Map<string, string>();
    try {
      // 获取 pkg 标识符
      const pkg = await this.getSourcePkgById(sourceId);
      const keyIdentifier = pkg || `id_${String(sourceId)}`;
      const keyPrefix: string = `source:${keyIdentifier}:custom.`;
      
      // 查询所有以 custom. 开头的设置
      const sql = `SELECT settingKey, settingValue FROM user_settings WHERE userId = ? AND settingKey LIKE ?`;
      const records = await this.databaseManager.querySql(sql, ['default_user', `${keyPrefix}%`]);
      
      if (records && records.length > 0) {
        for (let i = 0; i < records.length; i++) {
          const record: ESObject = records[i] as ESObject;
          const fullKey = record.settingKey as string;
          const value = record.settingValue as string;
          
          // 提取设置键名（去掉 source:xxx:custom. 前缀）
          if (fullKey && fullKey.startsWith(keyPrefix)) {
            const settingKey = fullKey.substring(keyPrefix.length);
            if (settingKey && value) {
              result.set(settingKey, value);
              logger.debug(TAG, `加载自定义设置: ${settingKey}=${value}`);
            }
          }
        }
      }
      
      logger.debug(TAG, `获取图源自定义设置: sourceId=${sourceId}, 数量=${result.size}`);
    } catch (error) {
      logger.error(TAG, `获取图源自定义设置失败: sourceId=${sourceId}`, String(error));
    }
    return result;
  }

  /**
   * 更新图源
   */
  async updateComicSource(id: number, updates: ESObject): Promise<void> {
    try {
      const fields: string[] = [];
      const values: DatabaseValue[] = [];

      if (updates.isEnabled !== undefined) {
        fields.push('isEnabled = ?');
        values.push(updates.isEnabled ? 1 : 0);
      }
      if (updates.priority !== undefined) {
        fields.push('priority = ?');
        values.push(updates.priority as number);
      }
      if (updates.configJson !== undefined) {
        fields.push('configJson = ?');
        values.push(updates.configJson as string);
      }
      if (updates.name !== undefined) {
        fields.push('name = ?');
        values.push(updates.name as string);
      }
      if (updates.baseUrl !== undefined) {
        fields.push('baseUrl = ?');
        values.push(updates.baseUrl as string);
      }
      if (updates.version !== undefined) {
        fields.push('version = ?');
        values.push(updates.version as string);
      }
      if (updates.description !== undefined) {
        fields.push('description = ?');
        values.push(updates.description as string);
      }
      if (updates.language !== undefined) {
        fields.push('language = ?');
        values.push(updates.language as string);
      }
      if (updates.type !== undefined) {
        fields.push('type = ?');
        values.push(updates.type as string);
      }
      if (updates.pkg !== undefined) {
        fields.push('pkg = ?');
        values.push(updates.pkg as string);
      }
      if (updates.lastUpdateTime !== undefined) {
        fields.push('lastUpdateTime = ?');
        values.push(updates.lastUpdateTime as number);
      }

      if (fields.length === 0) {
        return;
      }

      // 如果没有显式设置lastUpdateTime，自动添加
      if (updates.lastUpdateTime === undefined) {
        fields.push('lastUpdateTime = ?');
        values.push(Date.now());
      }
      values.push(id);

      const sql = `UPDATE comic_source SET ${fields.join(', ')} WHERE id = ?`;
      await this.databaseManager.executeSql(sql, values);

      logger.debug(TAG, `图源已更新: id=${id}`);
    } catch (error) {
      logger.error(TAG, `更新图源失败: id=${id}`, String(error));
      throw error as Error;
    }
  }

  /**
   * [修复] 批量修复所有图源的 pkg 字段
   * 遍历所有 pkg 为空的图源，从 configJson 中提取 metadata.id 并更新
   * @returns 修复的图源数量
   */
  async fixAllSourcePkgFields(): Promise<number> {
    try {
      // 查询所有 pkg 为空的图源
      const sql = `SELECT id, name, configJson FROM comic_source WHERE pkg IS NULL OR pkg = ''`;
      const result = await this.databaseManager.querySql(sql, []);
      
      if (!result || result.length === 0) {
        logger.info(TAG, `[修复] 所有图源的 pkg 字段已完整，无需修复`);
        return 0;
      }
      
      logger.info(TAG, `[修复] 发现 ${result.length} 个图源缺少 pkg 字段，开始修复...`);
      
      let fixedCount = 0;
      for (const record of result) {
        const row: ESObject = record as ESObject;
        const sourceId = row.id as number;
        const sourceName = row.name as string;
        const configJson = row.configJson as string;
        
        if (!configJson) {
          logger.warn(TAG, `[修复] 图源 ${sourceName} (id=${sourceId}) 没有 configJson，跳过`);
          continue;
        }
        
        try {
          const config: ESObject = JSON.parse(configJson) as ESObject;
          const metadata: ESObject = config.metadata as ESObject;
          
          if (metadata && metadata.id) {
            const extractedPkg = metadata.id as string;
            await this.databaseManager.executeSql(
              'UPDATE comic_source SET pkg = ? WHERE id = ?', [extractedPkg, sourceId]
            );
            logger.info(TAG, `[修复] 已修复图源 ${sourceName}: pkg=${extractedPkg}`);
            fixedCount++;
          } else {
            logger.warn(TAG, `[修复] 图源 ${sourceName} 的 metadata.id 为空，跳过`);
          }
        } catch (parseErr) {
          logger.warn(TAG, `[修复] 解析图源 ${sourceName} 的 configJson 失败: ${String(parseErr)}`);
        }
      }
      
      logger.info(TAG, `[修复] pkg 字段修复完成，共修复 ${fixedCount} 个图源`);
      return fixedCount;
    } catch (error) {
      logger.error(TAG, `[修复] 批量修复 pkg 字段失败`, String(error));
      return 0;
    }
  }

  /**
   * 更新图源预加载设置
   */
  async updateSourcePreloadSettings(
    sourceId: number,
    preloadCurrentChapter: boolean,
    preloadCurrentPages: number,
    preloadNextChapter: boolean,
    preloadNextPages: number
  ): Promise<void> {
    try {
      const sql = `UPDATE comic_source SET 
        preloadCurrentChapter = ?, 
        preloadCurrentPages = ?, 
        preloadNextChapter = ?, 
        preloadNextPages = ?,
        lastUpdateTime = ?
        WHERE id = ?`;
      
      await this.databaseManager.executeSql(sql, [
        preloadCurrentChapter ? 1 : 0,
        preloadCurrentPages,
        preloadNextChapter ? 1 : 0,
        preloadNextPages,
        Date.now(),
        sourceId
      ]);
      
      logger.info(TAG, `✅ 已更新图源ID=${sourceId}的预加载设置`);
    } catch (error) {
      logger.error(TAG, `更新图源预加载设置失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 删除图源
   */
  async deleteComicSource(id: number): Promise<void> {
    try {
      const sql = 'DELETE FROM comic_source WHERE id = ?';
      await this.databaseManager.executeSql(sql, [id]);
      logger.debug(TAG, `图源已删除: id=${id}`);
    } catch (error) {
      logger.error(TAG, `删除图源失败: id=${id}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 添加图源
   */
  async addComicSource(source: ESObject): Promise<string> {
    try {
      const now = Date.now();
      const pkg = source.pkg as string;
      
      if (!pkg) {
        throw new Error('图源缺少 pkg 字段');
      }
      
      const sql = `INSERT INTO comic_source 
                   (pkg, name, baseUrl, version, description, language, type, isEnabled, priority, lastUpdateTime, configJson, cookies, createTime, requireProxy, isNSFW) 
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      
      await this.databaseManager.executeSql(sql, [
        pkg,
        source.name as string,
        source.baseUrl as string,
        source.version as string,
        source.description as string || '',
        source.language as string || 'zh-CN',
        source.type as string || 'manga',
        source.isEnabled ? 1 : 0,
        source.priority as number || 0,
        now,
        source.configJson as string || '{}',
        '',
        now,
        source.requireProxy ? 1 : 0,
        source.isNSFW ? 1 : 0
      ]);
      
      logger.info(TAG, `图源已添加: ${source.name} (pkg: ${pkg}, type: ${source.type || 'manga'})`);
      
      return pkg;
    } catch (error) {
      logger.error(TAG, `添加图源失败: ${source.name}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 从JSON导入图源
   */
  async importSourceFromJSON(jsonContent: string): Promise<string> {
    try {
      const config: ESObject = JSON.parse(jsonContent) as ESObject;
      
      // 验证必需字段
      const metadata: ESObject = config.metadata as ESObject;
      if (!metadata || !metadata.id || !metadata.name || !metadata.baseUrl) {
        throw new Error('图源配置缺少必需字段（id、name或baseUrl）');
      }

      const pkg = metadata.id as string;
      const metadataType = metadata.type as string;
      logger.info(TAG, `[调试] 图源 ${metadata.name} 的metadata.type = "${metadataType}"`);
      
      // 检查图源是否已存在
      const existingSource: ESObject | null = await this.getSourceConfigByPkg(pkg);
      
      // 读取是否需要代理（metadata.Internet）
      const requireProxy = metadata.Internet === true ? 1 : 0;
      
      if (existingSource) {
        // 更新现有图源（保留 Cookie）
        const now = Date.now();
        const sourceType = metadata.type as string || 'manga';
        const isNSFW = (metadata.nsfw === true || metadata.nsfw === 1) ? 1 : 0;
        const updateSql = `UPDATE comic_source 
                          SET name = ?, baseUrl = ?, version = ?, description = ?, 
                              language = ?, type = ?, lastUpdateTime = ?, configJson = ?, requireProxy = ?, isNSFW = ? 
                          WHERE pkg = ?`;
        
        await this.databaseManager.executeSql(updateSql, [
          metadata.name as string,
          metadata.baseUrl as string,
          metadata.version as string || '1.0.0',
          metadata.description as string || '',
          metadata.language as string || 'zh-CN',
          sourceType,
          now,
          jsonContent,
          requireProxy,
          isNSFW,
          pkg
        ]);
        
        logger.info(TAG, `图源已更新: ${metadata.name} (pkg: ${pkg}, v${metadata.version}, type=${sourceType}, requireProxy=${requireProxy})`);
      } else {
        // 构建图源数据
        const sourceData: ESObject = {
          pkg: pkg,
          name: metadata.name,
          baseUrl: metadata.baseUrl,
          version: metadata.version || '1.0.0',
          description: metadata.description || '',
          language: metadata.language || 'zh-CN',
          type: metadata.type || 'manga',
          isEnabled: true,
          priority: 0,
          configJson: jsonContent,
          requireProxy: requireProxy === 1,
          isNSFW: metadata.nsfw === true || metadata.nsfw === 1
        };

        // 保存到数据库
        await this.addComicSource(sourceData);
        
        logger.info(TAG, `图源导入成功: ${metadata.name} (pkg: ${pkg}, v${metadata.version}, type=${metadata.type || 'manga'}, requireProxy=${requireProxy})`);
      }
      
      return pkg;
    } catch (error) {
      logger.error(TAG, '图源导入失败', String(error));
      throw error as Error;
    }
  }

  /**
   * 获取图源配置（通过 pkg）
   */
  async getSourceConfigByPkg(pkg: string): Promise<ESObject | null> {
    try {
      const sql = 'SELECT * FROM comic_source WHERE pkg = ?';
      const result = await this.databaseManager.querySql(sql, [pkg]);
      
      logger.debug(TAG, `查询图源配置: pkg=${pkg}, 结果数量=${result?.length || 0}`);
      
      if (result && result.length > 0) {
        const row: ESObject = result[0] as ESObject;
        logger.debug(TAG, `图源记录: pkg=${row.pkg}, name=${row.name}`);
        
        const configJson: string | null | undefined = row.configJson as string;
        
        if (!configJson) {
          logger.error(TAG, `图源配置为空: pkg=${pkg}`);
          return null;
        }
        
        logger.debug(TAG, `读取图源配置，长度: ${configJson.length}, 前100字符: ${configJson.substring(0, 100)}`);
        
        try {
          const config: ESObject = JSON.parse(configJson) as ESObject;
          logger.info(TAG, `图源配置解析成功: ${row.name}`);
          
          // 调试：检查workflows字段
          const workflows: ESObject | undefined = config.workflows as ESObject;
          if (workflows) {
            const workflowKeys = Object.keys(workflows);
            logger.debug(TAG, `workflows包含 ${workflowKeys.length} 个工作流: ${workflowKeys.join(', ')}`);
          } else {
            logger.warn(TAG, `⚠️ 警告：配置中没有workflows字段！`);
          }
          
          return config;
        } catch (parseError) {
          logger.error(TAG, `JSON解析失败: ${String(parseError)}`);
          return null;
        }
      }
      
      logger.warn(TAG, `未找到图源配置: pkg=${pkg}`);
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源配置失败: pkg=${pkg}`, String(error));
      return null;
    }
  }

  /**
   * 获取图源配置（兼容旧的数字 ID 接口）
   * @deprecated 请使用 getSourceConfigByPkg
   */
  async getSourceConfig(sourceId: number): Promise<ESObject | null> {
    try {
      const sql = 'SELECT * FROM comic_source WHERE id = ?';
      const result = await this.databaseManager.querySql(sql, [sourceId]);
      
      if (result && result.length > 0) {
        const row: ESObject = result[0] as ESObject;
        const configJson: string | null | undefined = row.configJson as string;
        
        if (configJson) {
          const config: ESObject = JSON.parse(configJson) as ESObject;
          
          // 调试：检查workflows字段
          const workflows: ESObject | undefined = config.workflows as ESObject;
          if (workflows) {
            const workflowKeys = Object.keys(workflows);
            logger.debug(TAG, `[ID查询] workflows包含 ${workflowKeys.length} 个工作流: ${workflowKeys.join(', ')}`);
          } else {
            logger.warn(TAG, `[ID查询] ⚠️ 警告：配置中没有workflows字段！sourceId=${sourceId}`);
          }
          
          return config;
        }
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源配置失败: id=${sourceId}`, String(error));
      return null;
    }
  }

  /**
   * 按名称查找图源配置（用于图源ID失效后的降级查找）
   * [新增] 支持按图源名称查找，实现更灵活的图源管理
   */
  async getSourceConfigByName(sourceName: string): Promise<SourceConfigResult | null> {
    try {
      const sql = 'SELECT * FROM comic_source WHERE name = ? LIMIT 1';
      const result = await this.databaseManager.querySql(sql, [sourceName]);
      
      if (result && result.length > 0) {
        const row: ESObject = result[0] as ESObject;
        const configJson: string | null | undefined = row.configJson as string;
        const sourceId: number = row.id as number;
        
        if (configJson) {
          logger.info(TAG, `按名称找到图源: "${sourceName}", ID=${sourceId}`);
          const resultObj: SourceConfigResult = {
            id: sourceId,
            config: JSON.parse(configJson) as ESObject
          };
          return resultObj;
        }
      }
      
      logger.warn(TAG, `未找到名称为 "${sourceName}" 的图源`);
      return null;
    } catch (error) {
      logger.error(TAG, `按名称查找图源配置失败: name="${sourceName}"`, String(error));
      return null;
    }
  }

  /**
   * 更新图源的baseUrl（用于换源功能）
   */
  async updateSourceBaseUrl(sourceId: number, newBaseUrl: string): Promise<void> {
    try {
      const sql = 'UPDATE comic_source SET baseUrl = ?, updateTime = ? WHERE id = ?';
      await this.databaseManager.executeSql(sql, [newBaseUrl, Date.now(), sourceId]);
      logger.info(TAG, `图源baseUrl已更新: id=${sourceId}, newBaseUrl=${newBaseUrl}`);
    } catch (error) {
      logger.error(TAG, `更新图源baseUrl失败: id=${sourceId}`, String(error));
      throw new Error(`更新图源baseUrl失败: ${String(error)}`);
    }
  }
  
  /**
   * 更新图源的NSFW状态
   * @param sourceId 图源ID
   * @param isNSFW 是否为NSFW图源
   */
  async updateSourceNSFW(sourceId: number, isNSFW: boolean): Promise<void> {
    try {
      const sql = 'UPDATE comic_source SET isNSFW = ?, lastUpdateTime = ? WHERE id = ?';
      await this.databaseManager.executeSql(sql, [isNSFW ? 1 : 0, Date.now(), sourceId]);
      logger.info(TAG, `图源NSFW状态已更新: id=${sourceId}, isNSFW=${isNSFW}`);
    } catch (error) {
      logger.error(TAG, `更新图源NSFW状态失败: id=${sourceId}`, String(error));
      throw new Error(`更新图源NSFW状态失败: ${String(error)}`);
    }
  }

  /**
   * 更新图源的代理设置
   * @param sourceId 图源ID
   * @param requireProxy 是否需要代理
   */
  async updateSourceProxySetting(sourceId: number, requireProxy: boolean): Promise<void> {
    try {
      const sql = 'UPDATE comic_source SET requireProxy = ?, lastUpdateTime = ? WHERE id = ?';
      await this.databaseManager.executeSql(sql, [requireProxy ? 1 : 0, Date.now(), sourceId]);
      logger.info(TAG, `图源代理设置已更新: id=${sourceId}, requireProxy=${requireProxy}`);
    } catch (error) {
      logger.error(TAG, `更新图源代理设置失败: id=${sourceId}`, String(error));
      throw new Error(`更新图源代理设置失败: ${String(error)}`);
    }
  }

  /**
   * 从图源保存漫画信息
   */
  async saveComicFromSource(sourceId: number, comicData: ESObject, externalId?: string): Promise<string> {
    try {
      const now = Date.now();
      
      // finalExternalId用于online_comic_info表的externalId字段
      const finalExternalId = (comicData.id as string) || externalId || this.generateId();
      
      logger.info(TAG, `📝 [SQL] 开始保存在线漫画: title="${comicData.title}", sourceId=${sourceId}, externalId="${finalExternalId}"`);
      
      // 先查询是否已存在相同的 sourceId + externalId 组合
      const checkSql = 'SELECT id FROM online_comic_info WHERE sourceId = ? AND externalId = ?';
      const existing = await this.databaseManager.querySql(checkSql, [String(sourceId), finalExternalId]);
      
      let comicId: string;
      if (existing && existing.length > 0) {
        // 已存在，使用现有ID进行更新
        comicId = (existing[0] as ESObject).id as string;
        logger.info(TAG, `📝 [SQL] 找到现有记录，将更新: id="${comicId}"`);
      } else {
        // 不存在，生成新ID
        comicId = externalId || this.generateId();
        logger.info(TAG, `📝 [SQL] 创建新记录: id="${comicId}"`);
      }
      
      // [修复] 解析sourceName和sourcePkg，优先级：comicData > comic_source表 > 默认值
      // sourcePkg 是图源的唯一包名标识符，用于在图源删除后重新导入时正确识别图源
      let sourceNameVal: string = '';
      let sourcePkgVal: string = '';
      
      // 1. 优先使用comicData中传递的sourceName和sourcePkg
      if (comicData.sourceName && typeof comicData.sourceName === 'string' && comicData.sourceName.length > 0) {
        sourceNameVal = comicData.sourceName as string;
        logger.info(TAG, `📝 [SQL] 使用传递的图源名称: "${sourceNameVal}"`);
      }
      if (comicData.sourcePkg && typeof comicData.sourcePkg === 'string' && comicData.sourcePkg.length > 0) {
        sourcePkgVal = comicData.sourcePkg as string;
        logger.info(TAG, `📝 [SQL] 使用传递的图源包名: "${sourcePkgVal}"`);
      }
      
      // 2. 从comic_source表查询图源信息（也用于NSFW继承判断）
      const srcRecord: ComicSourceDatabaseRecord | null = await this.getComicSourceById(sourceId);
      if (srcRecord) {
        if (!sourceNameVal && typeof srcRecord.name === 'string' && srcRecord.name.length > 0) {
          sourceNameVal = srcRecord.name;
          logger.info(TAG, `📝 [SQL] 从comic_source表获取图源名称: "${sourceNameVal}"`);
        }
        if (!sourcePkgVal && srcRecord.pkg && typeof srcRecord.pkg === 'string' && srcRecord.pkg.length > 0) {
          sourcePkgVal = srcRecord.pkg;
          logger.info(TAG, `📝 [SQL] 从comic_source表获取图源包名: "${sourcePkgVal}"`);
        }
      }
      
      // 3. 使用默认值
      if (!sourceNameVal) {
        sourceNameVal = 'WEBVIEW';
        logger.warn(TAG, `📝 [SQL] 未找到sourceId=${sourceId}的图源记录，使用默认名称: "${sourceNameVal}"`);
      }
      
      // 使用INSERT OR REPLACE，基于主键id
      // [修复] 添加 isNSFW 列，确保在线漫画的 NSFW 标记能正确保存
      const sql = `INSERT OR REPLACE INTO online_comic_info 
                   (id, sourceId, externalId, title, author, description, coverUrl, tags, rating, lastUpdateTime, addTime, createTime, updateTime, sourceName, sourcePkg, isPrivate, isNSFW) 
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      
      // [修复] 读取 comicData 中的 isNSFW 值，支持 boolean 和 number 类型
      const isNSFWRaw: boolean | number = comicData.isNSFW as boolean | number;
      let isNSFWVal: number = (isNSFWRaw === true || isNSFWRaw === 1) ? 1 : 0;
      
      // 【NSFW作用域】从图源继承NSFW状态：如果图源是NSFW且作用域开关开启，则其内容自动继承
      if (isNSFWVal === 0 && srcRecord && srcRecord.isNSFW === 1) {
        try {
          const cfmModule = await import('../Managers/ContentFilterManager');
          const filterManager = cfmModule.ContentFilterManager.getInstance();
          if (filterManager.isNsfwScopeImageSourceEnabled()) {
            isNSFWVal = 1;
            logger.debug(TAG, `📝 [NSFW作用域] 在线漫画从图源继承NSFW标记: ${comicData.title}`);
          }
        } catch (e) {
          // ContentFilterManager未初始化时默认继承
          isNSFWVal = 1;
          logger.debug(TAG, `📝 [NSFW作用域] 在线漫画从图源继承NSFW标记(默认): ${comicData.title}`);
        }
      }
      
      const params = [
        comicId,
        String(sourceId),
        finalExternalId,
        comicData.title as string,
        comicData.author as string || '',
        comicData.description as string || '',
        comicData.coverUrl as string || '',
        JSON.stringify(comicData.tags || []),
        (comicData.rating as number) || 0,
        (comicData.updateTime as number) || now,
        now,
        now,
        now,
        sourceNameVal,
        sourcePkgVal,
        0,  // isPrivate默认为0（普通内容）
        isNSFWVal  // isNSFW：从comicData读取或默认为0
      ];
      
      logger.debug(TAG, `📝 [SQL] 执行SQL: ${sql}`);
      logger.debug(TAG, `📝 [SQL] 参数: id=${params[0]}, sourceId=${params[1]}, externalId=${params[2]}, title=${params[3]}`);
      
      await this.databaseManager.executeSql(sql, params);

      logger.info(TAG, `✅ [SQL] 在线漫画已保存/更新: ${comicData.title} (ID=${comicId}, 图源${sourceId}, 外部ID=${finalExternalId})`);
      return comicId;
    } catch (error) {
      logger.error(TAG, `❌ [SQL] 保存在线漫画失败: ${comicData.title}, sourceId=${sourceId}`, String(error));
      logger.error(TAG, `❌ [SQL] comicData: ${JSON.stringify(comicData)}`);
      throw error as Error;
    }
  }

  /**
   * 从图源保存章节信息到在线章节表
   */
  async saveOnlineChapterFromSource(comicId: string, chapterData: ESObject, externalId?: string): Promise<string> {
    try {
      const now = Date.now();
      const chapterId = this.generateId();
      const finalExternalId = externalId || chapterId;
      const sql = `INSERT INTO online_chapter 
                   (id, comicId, externalId, title, chapterNumber, url, pageCount, publishTime, addTime, createTime, updateTime) 
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      await this.databaseManager.executeSql(sql, [
        chapterId,
        comicId,
        finalExternalId,
        chapterData.title as string,
        ((chapterData.chapterNumber as number) ?? (chapterData.index as number) ?? 0),
        (chapterData.url as string) || '',
        (chapterData.pageCount as number) || 0,
        (chapterData.publishTime as number) || 0,
        now,
        now,
        now
      ]);
      logger.info(TAG, `在线章节已保存: ${chapterData.title} (comicId=${comicId})`);
      return chapterId;
    } catch (error) {
      logger.error(TAG, `保存在线章节失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 添加在线章节信息（完整版，支持所有字段）
   */
  public async addOnlineChapterInfo(chapterInput: OnlineChapterInfoInput): Promise<string> {
    try {
      // [严格验证] 必须提供有效的externalId
      if (!chapterInput.externalId || chapterInput.externalId.trim() === '') {
        const errorMsg = `❌ 严重错误：章节 "${chapterInput.title}" 缺少externalId！\n` +
          `  - comicId: ${chapterInput.comicId}\n` +
          `  - title: ${chapterInput.title}\n` +
          `  - chapterNumber: ${chapterInput.chapterNumber}\n` +
          `  - externalId: "${chapterInput.externalId}"\n` +
          `拒绝保存，请检查数据来源！`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
      
      // [严格验证] externalId不能是内部ID格式
      if (chapterInput.externalId.startsWith('id_') || chapterInput.externalId.startsWith('local_')) {
        const errorMsg = `❌ 严重错误：章节 "${chapterInput.title}" 的externalId是内部ID格式！\n` +
          `  - externalId: ${chapterInput.externalId}\n` +
          `  - 期望格式: /comic/xxx/chapter/xxx 或其他外部ID\n` +
          `拒绝保存，请检查数据转换逻辑！`;
        logger.error(TAG, errorMsg);
        throw new Error(errorMsg);
      }
      
      const now = Date.now();
      const chapterIndex = chapterInput.index ?? chapterInput.chapterNumber;
      const isDownloaded = chapterInput.isDownloaded ?? false;
      
      // [修复] 先检查是否存在相同externalId的章节
      const checkSql = 'SELECT id FROM online_chapter WHERE comicId = ? AND externalId = ?';
      const existingChapters = await this.databaseManager.querySql(checkSql, [chapterInput.comicId, chapterInput.externalId]);
      
      let chapterId: string;
      if (existingChapters.length > 0) {
        // 更新现有章节（包括externalId，防止旧数据externalId为空）
        chapterId = (existingChapters[0] as ESObject).id as string;
        const updateSql = `UPDATE online_chapter 
                          SET externalId = ?, title = ?, chapterNumber = ?, url = ?, pageCount = ?, publishTime = ?, 
                              updateTime = ?, isDownloaded = ?, downloadPath = ?, \`index\` = ?
                          WHERE id = ?`;
        await this.databaseManager.executeSql(updateSql, [
          chapterInput.externalId,  // [修复] 更新externalId
          chapterInput.title,
          chapterInput.chapterNumber,
          chapterInput.url || '',
          chapterInput.pageCount,
          chapterInput.publishTime,
          now,
          isDownloaded ? 1 : 0,
          chapterInput.downloadPath || null,
          chapterIndex,
          chapterId
        ]);
        logger.info(TAG, `✅ 在线章节已更新: title="${chapterInput.title}", externalId=${chapterInput.externalId}, internalId=${chapterId}`);
      } else {
        // 插入新章节
        chapterId = this.generateId();
        const sql = `INSERT INTO online_chapter 
                     (id, comicId, externalId, title, chapterNumber, url, pageCount, publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath, \`index\`) 
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
        await this.databaseManager.executeSql(sql, [
          chapterId,
          chapterInput.comicId,
          chapterInput.externalId,
          chapterInput.title,
          chapterInput.chapterNumber,
          chapterInput.url || '',
          chapterInput.pageCount,
          chapterInput.publishTime,
          now,
          now,
          now,
          isDownloaded ? 1 : 0,
          chapterInput.downloadPath || null,
          chapterIndex
        ]);
        logger.info(TAG, `✅ 在线章节已保存: title="${chapterInput.title}", externalId=${chapterInput.externalId}, internalId=${chapterId}`);
      }
      
      return chapterId;
    } catch (error) {
      logger.error(TAG, `❌ 保存在线章节失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 兼容API：保存在线漫画（包装原有方法）
   */
  async saveOnlineComicFromSource(sourceId: number, comicData: ESObject, externalId?: string): Promise<string> {
    return await this.saveComicFromSource(sourceId, comicData, externalId);
  }

  /**
   * 添加在线页面信息（完整版）
   */
  public async addOnlinePageInfo(pageInput: OnlinePageInfoInput): Promise<string> {
    try {
      const now = Date.now();
      const pageId = this.generateId();
      const sql = `INSERT INTO online_page 
                   (id, chapterId, pageNumber, imageUrl, width, height, fileSize, createTime) 
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
      await this.databaseManager.executeSql(sql, [
        pageId,
        pageInput.chapterId,
        pageInput.pageNumber,
        pageInput.imageUrl,
        pageInput.width,
        pageInput.height,
        pageInput.fileSize,
        now
      ]);
      logger.debug(TAG, `在线页面已保存: chapterId=${pageInput.chapterId}, page=${pageInput.pageNumber}`);
      return pageId;
    } catch (error) {
      logger.error(TAG, `保存在线页面失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * [性能优化] 批量添加在线页面信息（事务包裹）
   * 替代逐条 addOnlinePageInfo，将所有 INSERT 放在一个事务内执行
   * @param chapterId 章节ID
   * @param pages 页面信息数组
   */
  public async batchAddOnlinePages(chapterId: string, pages: OnlinePageInfoInput[]): Promise<void> {
    if (pages.length === 0) return;
    try {
      const now = Date.now();
      await this.databaseManager.beginTransaction();
      try {
        const sql = `INSERT INTO online_page 
                     (id, chapterId, pageNumber, imageUrl, width, height, fileSize, createTime) 
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
        for (let i = 0; i < pages.length; i++) {
          const p = pages[i];
          const pageId = this.generateId();
          await this.databaseManager.executeSql(sql, [
            pageId, chapterId, p.pageNumber, p.imageUrl, p.width, p.height, p.fileSize, now
          ]);
        }
        await this.databaseManager.commit();
        logger.debug(TAG, `批量保存在线页面完成: chapterId=${chapterId}, count=${pages.length}`);
      } catch (txError) {
        await this.databaseManager.rollBack();
        throw txError as Error;
      }
    } catch (error) {
      logger.error(TAG, `批量保存在线页面失败: chapterId=${chapterId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 删除指定章节的所有页面数据
   */
  public async deleteOnlineChapterPages(chapterId: string): Promise<void> {
    try {
      const sql = 'DELETE FROM online_page WHERE chapterId = ?';
      await this.databaseManager.executeSql(sql, [chapterId]);
      logger.debug(TAG, `已删除章节 ${chapterId} 的所有页面数据`);
    } catch (error) {
      logger.error(TAG, `删除章节页面数据失败: chapterId=${chapterId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 更新在线页面的缓存状态
   * 用于同步磁盘缓存到数据库
   */
  public async updateOnlinePageCacheStatus(
    imageUrl: string,
    localPath: string,
    fileSize: number
  ): Promise<void> {
    try {
      const sql = `UPDATE online_page 
                   SET localPath = ?, fileSize = ? 
                   WHERE imageUrl = ?`;
      await this.databaseManager.executeSql(sql, [localPath, fileSize, imageUrl]);
      logger.debug(TAG, `更新页面缓存状态: ${imageUrl.substring(0, 80)}`);
    } catch (error) {
      logger.error(TAG, `更新页面缓存状态失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 批量更新在线页面的缓存状态
   */
  public async batchUpdateOnlinePageCacheStatus(
    updates: Array<PageCacheUpdate>
  ): Promise<void> {
    if (updates.length === 0) {
      return;
    }

    try {
      const sql = `UPDATE online_page 
                   SET localPath = ?, fileSize = ? 
                   WHERE imageUrl = ?`;

      await this.databaseManager.beginTransaction();
      try {
        for (const update of updates) {
          await this.databaseManager.executeSql(sql, [update.localPath, update.fileSize, update.imageUrl]);
        }
        await this.databaseManager.commit();
      } catch (txError) {
        await this.databaseManager.rollBack();
        throw txError as Error;
      }
      logger.info(TAG, `批量更新页面缓存状态: ${updates.length}条`);
    } catch (error) {
      logger.error(TAG, `批量更新页面缓存状态失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 保存在线页面信息（兼容旧方法）
   */
  async saveOnlinePageFromSource(chapterId: string, pageData: ESObject): Promise<string> {
    try {
      const now = Date.now();
      const pageId = this.generateId();
      const sql = `INSERT INTO online_page 
                   (id, chapterId, pageNumber, imageUrl, width, height, fileSize, createTime) 
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
      await this.databaseManager.executeSql(sql, [
        pageId,
        chapterId,
        (pageData.pageNumber as number) ?? (pageData.index as number) ?? 0,
        pageData.imageUrl as string,
        (pageData.width as number) || 0,
        (pageData.height as number) || 0,
        (pageData.fileSize as number) || 0,
        now
      ]);
      logger.info(TAG, `在线页面已保存: chapterId=${chapterId}, page=${(pageData.pageNumber as number) ?? 0}`);
      return pageId;
    } catch (error) {
      logger.error(TAG, `保存在线页面失败: ${String(error)}`);
      throw error as Error;
    }
  }

  /**
   * 获取图源的在线漫画列表
   */
  async getOnlineComicsBySource(sourceId: number, limit: number = 20, offset: number = 0): Promise<DatabaseRecord[]> {
    try {
      const sql = `SELECT * FROM online_comic_info WHERE sourceId = ? ORDER BY addTime DESC LIMIT ? OFFSET ?`;
      const result = await this.databaseManager.querySql(sql, [String(sourceId), limit, offset]);
      return result;
    } catch (error) {
      logger.error(TAG, `获取在线漫画列表失败: sourceId=${sourceId}`, String(error));
      return [];
    }
  }

  /**
   * 根据ID获取在线漫画
   */
  async getOnlineComicById(comicId: string): Promise<DatabaseRecord | null> {
    try {
      const sql = 'SELECT * FROM online_comic_info WHERE id = ?';
      const result = await this.databaseManager.querySql(sql, [comicId]);
      if (result && result.length > 0) {
        return result[0] as DatabaseRecord;
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取在线漫画失败: id=${comicId}`, String(error));
      return null;
    }
  }

  /**
   * 获取在线漫画（强类型）
   */
  public async getOnlineComicInfoById(comicId: string): Promise<OnlineComicInfo | null> {
    try {
      const sql = 'SELECT * FROM online_comic_info WHERE id = ?';
      const result = await this.databaseManager.querySql(sql, [comicId]);
      if (result && result.length > 0) {
        return this.convertRecordToOnlineComicInfo(result[0] as DatabaseRecord);
      }
      return null;
    } catch (error) {
      logger.error(TAG, `获取在线漫画(强类型)失败: id=${comicId}`, String(error));
      return null;
    }
  }

  /**
   * 根据外部ID更新在线漫画的sourceName
   */
  public async updateOnlineComicSourceNameByExternalId(externalId: string, sourceName: string): Promise<void> {
    try {
      const sql = 'UPDATE online_comic_info SET sourceName = ?, updateTime = ? WHERE externalId = ?';
      await this.databaseManager.executeSql(sql, [sourceName, Date.now(), externalId]);
      logger.info(TAG, `更新在线漫画sourceName成功: externalId=${externalId}, sourceName=${sourceName}`);
    } catch (error) {
      logger.error(TAG, `更新在线漫画sourceName失败: externalId=${externalId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 根据内部ID更新在线漫画的sourceName
   */
  public async updateOnlineComicSourceNameById(comicId: string, sourceName: string): Promise<void> {
    try {
      const sql = 'UPDATE online_comic_info SET sourceName = ?, updateTime = ? WHERE id = ?';
      await this.databaseManager.executeSql(sql, [sourceName, Date.now(), comicId]);
      logger.info(TAG, `更新在线漫画sourceName成功: id=${comicId}, sourceName=${sourceName}`);
    } catch (error) {
      logger.error(TAG, `更新在线漫画sourceName失败: id=${comicId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * [修复] 通过 sourcePkg 恢复在线漫画与图源的关联
   * 当图源被删除后重新导入时，通过 sourcePkg 查找新的 sourceId 并更新在线漫画
   * @param sourcePkg 图源唯一包名
   * @returns 更新的漫画数量
   */
  public async restoreOnlineComicSourceByPkg(sourcePkg: string): Promise<number> {
    try {
      if (!sourcePkg) {
        logger.warn(TAG, `restoreOnlineComicSourceByPkg: sourcePkg 为空`);
        return 0;
      }

      // 1. 通过 pkg 查找图源
      const sourceRecord = await this.getComicSourceByPkg(sourcePkg);
      if (!sourceRecord) {
        logger.warn(TAG, `restoreOnlineComicSourceByPkg: 未找到 pkg="${sourcePkg}" 的图源`);
        return 0;
      }

      const newSourceId = sourceRecord.id;
      const sourceName = sourceRecord.name;
      logger.info(TAG, `[修复] 找到图源: pkg="${sourcePkg}", id=${newSourceId}, name="${sourceName}"`);

      // 2. 查找所有使用该 sourcePkg 的在线漫画
      const sql = 'SELECT id, sourceId FROM online_comic_info WHERE sourcePkg = ?';
      const comics = await this.databaseManager.querySql(sql, [sourcePkg]);

      if (!comics || comics.length === 0) {
        logger.info(TAG, `[修复] 没有找到使用 sourcePkg="${sourcePkg}" 的在线漫画`);
        return 0;
      }

      // 3. 更新这些漫画的 sourceId 和 sourceName
      let updatedCount = 0;
      for (const comic of comics) {
        const comicObj: ESObject = comic as ESObject;
        const comicId = comicObj.id as string;
        const oldSourceId = comicObj.sourceId as string;

        if (oldSourceId !== String(newSourceId)) {
          const updateSql = 'UPDATE online_comic_info SET sourceId = ?, sourceName = ?, updateTime = ? WHERE id = ?';
          await this.databaseManager.executeSql(updateSql, [String(newSourceId), sourceName, Date.now(), comicId]);
          updatedCount++;
          logger.info(TAG, `[修复] 更新漫画 "${comicId}" 的 sourceId: ${oldSourceId} -> ${newSourceId}`);
        }
      }

      logger.info(TAG, `[修复] 通过 sourcePkg="${sourcePkg}" 恢复了 ${updatedCount} 部漫画的图源关联`);
      return updatedCount;
    } catch (error) {
      logger.error(TAG, `restoreOnlineComicSourceByPkg 失败: sourcePkg="${sourcePkg}"`, String(error));
      return 0;
    }
  }

  /**
   * [修复] 尝试通过 sourcePkg 或 sourceName 查找图源ID
   * 用于在 sourceId 失效时的降级查找
   * @param sourcePkg 图源唯一包名（优先）
   * @param sourceName 图源名称（备选）
   * @returns 图源ID，如果未找到返回 null
   */
  public async findSourceIdByPkgOrName(sourcePkg?: string, sourceName?: string): Promise<number | null> {
    try {
      // 1. 优先通过 pkg 查找
      if (sourcePkg) {
        const sourceByPkg = await this.getComicSourceByPkg(sourcePkg);
        if (sourceByPkg) {
          logger.info(TAG, `[修复] 通过 pkg="${sourcePkg}" 找到图源 ID=${sourceByPkg.id}`);
          return Number(sourceByPkg.id);
        }
      }

      // 2. 通过 name 查找
      if (sourceName) {
        const sourceByName = await this.getComicSourceByName(sourceName);
        if (sourceByName) {
          logger.info(TAG, `[修复] 通过 name="${sourceName}" 找到图源 ID=${sourceByName.id}`);
          return Number(sourceByName.id);
        }
      }

      logger.warn(TAG, `[修复] 未找到图源: pkg="${sourcePkg}", name="${sourceName}"`);
      return null;
    } catch (error) {
      logger.error(TAG, `findSourceIdByPkgOrName 失败`, String(error));
      return null;
    }
  }

  /**
   * 获取图源的漫画列表
   */
  async getComicsBySource(sourceId: number, limit: number = 20, offset: number = 0): Promise<DatabaseRecord[]> {
    try {
      const sql = `SELECT * FROM comic_info WHERE sourceId = ? ORDER BY addTime DESC LIMIT ? OFFSET ?`;
      const result = await this.databaseManager.querySql(sql, [String(sourceId), limit, offset]);
      return result;
    } catch (error) {
      logger.error(TAG, `获取图源漫画列表失败: sourceId=${sourceId}`, String(error));
      return [];
    }
  }

  /**
   * 根据标题查找相似的漫画（模糊匹配）
   */
  async findSimilarComics(title: string, threshold: number = 0.8): Promise<DatabaseRecord[]> {
    try {
      // 先精确匹配
      const exactSql = `SELECT * FROM comic_info WHERE title = ?`;
      const exactResult = await this.databaseManager.querySql(exactSql, [title]);
      
      if (exactResult.length > 0) {
        logger.info(TAG, `精确匹配到${exactResult.length}部漫画: "${title}"`);
        return exactResult;
      }
      
      // 模糊匹配：使用LIKE查询
      const fuzzyTitle = title.replace(/\s+/g, '%'); // 将空格替换为通配符
      const fuzzySql = `SELECT * FROM comic_info WHERE title LIKE ?`;
      const fuzzyResult = await this.databaseManager.querySql(fuzzySql, [`%${fuzzyTitle}%`]);
      
      // 计算相似度并过滤
      const similarComics = fuzzyResult.filter((record: DatabaseRecord) => {
        const comicTitle = (record as ESObject).title as string;
        const similarity = this.calculateSimilarity(title, comicTitle);
        return similarity >= threshold;
      });
      
      logger.info(TAG, `找到${similarComics.length}部相似漫画: "${title}"`);
      return similarComics;
    } catch (error) {
      logger.error(TAG, `查找相似漫画失败: ${title}`, String(error));
      return [];
    }
  }

  /**
   * 计算两个字符串的相似度
   */
  private calculateSimilarity(str1: string, str2: string): number {
    // 移除空格和标点符号，转小写
    const normalize = (s: string) => s.replace(/[\s\p{P}]/gu, '').toLowerCase();
    const s1 = normalize(str1);
    const s2 = normalize(str2);
    
    // 完全匹配
    if (s1 === s2) return 1.0;
    
    // 包含关系
    if (s1.includes(s2) || s2.includes(s1)) {
      const shorter = Math.min(s1.length, s2.length);
      const longer = Math.max(s1.length, s2.length);
      return shorter / longer;
    }
    
    // 简单的字符匹配度
    const maxLen = Math.max(s1.length, s2.length);
    if (maxLen === 0) return 1.0;
    
    let matches = 0;
    for (let i = 0; i < Math.min(s1.length, s2.length); i++) {
      if (s1[i] === s2[i]) matches++;
    }
    
    return matches / maxLen;
  }

  /**
   * 清理重复的章节
   * @param comicId 漫画ID
   * @returns 删除的重复章节数量
   */
  async cleanDuplicateChapters(comicId: string): Promise<number> {
    try {
      logger.info(TAG, `开始清理漫画 ${comicId} 的重复章节`);
      
      let totalDeleted = 0;
      
      // [修复] 先尝试清理 online_chapter 表（WebView图源）
      try {
        const onlineSql = `SELECT id, externalId, title, \`index\`, createTime FROM online_chapter WHERE comicId = ? ORDER BY externalId, title, \`index\`, createTime ASC`;
        const onlineChapters = await this.databaseManager.querySql(onlineSql, [comicId]);
        
        if (onlineChapters.length > 0) {
          logger.info(TAG, `找到 ${onlineChapters.length} 个在线章节，开始去重`);
          const seenOnline = new Map<string, string>(); // key: externalId -> 保留的章节ID
          const duplicateOnlineIds: string[] = [];
          
          for (const chapter of onlineChapters) {
            const chapterObj: ESObject = chapter as ESObject;
            const key = chapterObj.externalId as string;
            
            if (seenOnline.has(key)) {
              // 重复章节，标记删除
              duplicateOnlineIds.push(chapterObj.id as string);
              logger.debug(TAG, `发现重复在线章节: ${chapterObj.title} (externalId: ${key}, ID: ${chapterObj.id})`);
            } else {
              // 第一次见到，保留
              seenOnline.set(key, chapterObj.id as string);
            }
          }
          
          // 删除重复的在线章节
          if (duplicateOnlineIds.length > 0) {
            for (const id of duplicateOnlineIds) {
              await this.databaseManager.executeSql(`DELETE FROM online_page WHERE chapterId = ?`, [id]);
              await this.databaseManager.executeSql(`DELETE FROM online_chapter WHERE id = ?`, [id]);
            }
            totalDeleted += duplicateOnlineIds.length;
            logger.info(TAG, `已删除 ${duplicateOnlineIds.length} 个重复在线章节`);
          }
        }
      } catch (onlineError) {
        logger.warn(TAG, `清理在线章节失败: ${String(onlineError)}`);
      }
      
      // 然后清理 chapter 表（本地图源）
      const sql = `SELECT id, title, chapterIndex, addTime FROM chapter WHERE comicId = ? ORDER BY title, chapterIndex, addTime ASC`;
      const chapters = await this.databaseManager.querySql(sql, [comicId]);
      
      if (chapters.length === 0) {
        logger.info(TAG, totalDeleted > 0 ? `本地章节表为空，已清理在线章节` : '没有找到章节');
        return totalDeleted;
      }
      
      // 使用Map记录已见过的章节（key: title_index）
      const seenChapters = new Map<string, string>(); // key -> 保留的章节ID
      const duplicateIds: string[] = [];
      
      for (const chapter of chapters) {
        const chapterObj: ESObject = chapter as ESObject;
        const key = `${chapterObj.title}_${chapterObj.chapterIndex}`;
        
        if (seenChapters.has(key)) {
          // 这是重复章节，标记为删除
          duplicateIds.push(chapterObj.id as string);
          logger.debug(TAG, `发现重复章节: ${chapterObj.title} (ID: ${chapterObj.id})`);
        } else {
          // 第一次见到这个章节，保留它
          seenChapters.set(key, chapterObj.id as string);
        }
      }
      
      // 批量删除重复章节
      if (duplicateIds.length > 0) {
        for (const id of duplicateIds) {
          // 删除章节的页面数据
          await this.databaseManager.executeSql(`DELETE FROM page WHERE chapterId = ?`, [id]);
          // 删除章节
          await this.databaseManager.executeSql(`DELETE FROM chapter WHERE id = ?`, [id]);
        }
        totalDeleted += duplicateIds.length;
        logger.info(TAG, `已删除 ${duplicateIds.length} 个重复本地章节`);
      } else {
        logger.info(TAG, '没有发现重复本地章节');
      }
      
      return totalDeleted;
    } catch (error) {
      logger.error(TAG, `清理重复章节失败: ${comicId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 合并两部漫画的数据
   */
  async mergeComics(targetId: string, sourceId: string): Promise<void> {
    try {
      logger.info(TAG, `开始合并漫画: ${sourceId} -> ${targetId}`);
      
      // 1. 更新章节的comicId
      const updateChaptersSql = `UPDATE chapter SET comicId = ? WHERE comicId = ?`;
      await this.databaseManager.executeSql(updateChaptersSql, [targetId, sourceId]);
      
      // 2. 更新阅读历史的comicId
      const updateHistorySql = `UPDATE read_history SET comicId = ? WHERE comicId = ?`;
      await this.databaseManager.executeSql(updateHistorySql, [targetId, sourceId]);
      
      // 3. 更新收藏的comicId（如果存在）
      const updateFavoriteSql = `UPDATE favorite SET comicId = ? WHERE comicId = ?`;
      await this.databaseManager.executeSql(updateFavoriteSql, [targetId, sourceId]);
      
      // 4. 删除源漫画
      const deleteComicSql = `DELETE FROM comic_info WHERE id = ?`;
      await this.databaseManager.executeSql(deleteComicSql, [sourceId]);
      
      logger.info(TAG, `漫画合并完成: ${sourceId} -> ${targetId}`);
    } catch (error) {
      logger.error(TAG, `合并漫画失败: ${sourceId} -> ${targetId}`, String(error));
      throw error as Error;
    }
  }

  // ==================== 标签页配置管理 ====================

  /**
   * 保存图源的标签页配置
   */
  async saveSourceTabsConfig(sourceId: number, configJson: string): Promise<void> {
    try {
      const sql = `UPDATE comic_source SET tabs_config = ? WHERE id = ?`;
      await this.databaseManager.executeSql(sql, [configJson, sourceId]);
      logger.info(TAG, `已保存图源标签配置: sourceId=${sourceId}`);
    } catch (error) {
      logger.error(TAG, `保存图源标签配置失败: sourceId=${sourceId}`, String(error));
      throw error as Error;
    }
  }

  /**
   * 获取图源的标签页配置
   */
  async getSourceTabsConfig(sourceId: number): Promise<string | null> {
    try {
      const sql = `SELECT tabs_config FROM comic_source WHERE id = ?`;
      const result = await this.databaseManager.querySql(sql, [sourceId]);
      
      if (result && result.length > 0) {
        const record = result[0] as Record<string, DatabaseValue>;
        return record['tabs_config'] ? String(record['tabs_config']) : null;
      }
      
      return null;
    } catch (error) {
      logger.error(TAG, `获取图源标签配置失败: sourceId=${sourceId}`, String(error));
      return null;
    }
  }

  /**
   * 检查用户是否已登录（通过检查cookie是否存在）
   */
  async isSourceLoggedIn(sourceId: number): Promise<boolean> {
    try {
      const source = await this.getComicSourceById(sourceId);
      if (!source || !source.cookies) {
        return false;
      }
      
      const cookiesStr = String(source.cookies);
      return cookiesStr.length > 0 && cookiesStr !== '[]';
    } catch (error) {
      logger.error(TAG, `检查登录状态失败: sourceId=${sourceId}`, String(error));
      return false;
    }
  }

  /**
   * 递归删除目录及其所有内容
   */
  private deleteDirectoryRecursive(dirPath: string): void {
    try {
      if (!fs.accessSync(dirPath)) {
        return;
      }
      
      const entries = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        const stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          this.deleteDirectoryRecursive(fullPath);
        } else {
          fs.unlinkSync(fullPath);
        }
      }
      
      fs.rmdirSync(dirPath);
    } catch (error) {
      logger.warn(TAG, `递归删除目录失败 ${dirPath}: ${error}`);
    }
  }
  
  // ==================== 缓存管理 ====================
  
  /**
   * [新增] 获取指定图源下所有有缓存的漫画列表
   * 通过检查online_page表的localPath字段来判断是否已缓存
   * @param sourceId 图源ID
   * @returns 有缓存页面的漫画信息列表
   */
  async getCachedMangasBySource(sourceId: number): Promise<CachedMangaInfo[]> {
    try {
      // 从数据库查询所有有缓存页面的漫画
      // 通过online_page表的localPath字段判断是否已缓存
      const sql = `
        SELECT DISTINCT 
          oci.id as mangaId,
          oci.title as mangaTitle,
          oci.sourceId as sourceId
        FROM online_comic_info oci
        INNER JOIN online_chapter oc ON oc.comicId = oci.id
        INNER JOIN online_page op ON op.chapterId = oc.id
        WHERE oci.sourceId = ? 
          AND op.localPath IS NOT NULL 
          AND op.localPath != ''
        GROUP BY oci.id
      `;
      
      const result = await this.databaseManager.querySql(sql, [String(sourceId)]);
      const cachedMangas: CachedMangaInfo[] = [];
      
      for (const record of result) {
        const obj = record as Record<string, DatabaseValue>;
        const info: CachedMangaInfo = {
          mangaId: String(obj['mangaId'] || ''),
          mangaTitle: String(obj['mangaTitle'] || ''),
          sourceId: Number(obj['sourceId'] || 0)
        };
        cachedMangas.push(info);
      }
      
      logger.info(TAG, `获取已缓存漫画列表: sourceId=${sourceId}, 找到 ${cachedMangas.length} 部漫画`);
      return cachedMangas;
    } catch (error) {
      logger.error(TAG, `获取已缓存漫画列表失败: sourceId=${sourceId}`, String(error));
      return [];
    }
  }
  
  /**
   * [新增] 清理指定漫画的缓存记录
   * 将online_page表中该漫画所有页面的localPath和fileSize清空
   * @param mangaId 漫画ID
   */
  async clearMangaCacheRecords(mangaId: string): Promise<void> {
    try {
      // 更新该漫画所有章节的所有页面，清空localPath和fileSize
      const sql = `
        UPDATE online_page 
        SET localPath = NULL, fileSize = 0 
        WHERE chapterId IN (
          SELECT id FROM online_chapter WHERE comicId = ?
        )
      `;
      await this.databaseManager.executeSql(sql, [mangaId]);
      logger.info(TAG, `已清理漫画缓存记录: mangaId=${mangaId}`);
    } catch (error) {
      logger.error(TAG, `清理漫画缓存记录失败: mangaId=${mangaId}`, String(error));
      throw error as Error;
    }
  }
  
  /**
   * [新增] 获取所有有缓存的漫画列表（不限图源）
   * 通过检查online_page表的localPath字段来判断是否已缓存
   * @returns 有缓存页面的漫画信息列表
   */
  async getAllCachedMangas(): Promise<CachedMangaInfo[]> {
    try {
      // 从数据库查询所有有缓存页面的漫画（不限图源）
      // 注意：HarmonyOS数据库可能不支持别名，直接选择原始字段
      const sql = `
        SELECT DISTINCT 
          oci.id,
          oci.title,
          oci.sourceId
        FROM online_comic_info oci
        INNER JOIN online_chapter oc ON oc.comicId = oci.id
        INNER JOIN online_page op ON op.chapterId = oc.id
        WHERE op.localPath IS NOT NULL 
          AND op.localPath != ''
        GROUP BY oci.id
      `;
      
      const result = await this.databaseManager.querySql(sql, []);
      const cachedMangas: CachedMangaInfo[] = [];
      
      logger.debug(TAG, `查询结果原始数据: ${JSON.stringify(result)}`);
      
      for (const record of result) {
        const obj = record as Record<string, DatabaseValue>;
        // 使用原始字段名
        const info: CachedMangaInfo = {
          mangaId: String(obj['id'] || ''),
          mangaTitle: String(obj['title'] || ''),
          sourceId: Number(obj['sourceId'] || 0)
        };
        logger.debug(TAG, `解析漫画: id=${info.mangaId}, title=${info.mangaTitle}, sourceId=${info.sourceId}`);
        cachedMangas.push(info);
      }
      
      logger.info(TAG, `获取所有已缓存漫画列表: 找到 ${cachedMangas.length} 部漫画`);
      return cachedMangas;
    } catch (error) {
      logger.error(TAG, `获取所有已缓存漫画列表失败`, String(error));
      return [];
    }
  }
}

export { UserSettingsDatabaseRecord };
