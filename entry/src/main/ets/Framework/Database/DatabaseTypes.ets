import { SafeUtils } from '../../Utils/SafeUtils';
// 文件路径: src/main/ets/Framework/Database/DatabaseTypes.ets
/**
 * 数据库类型定义
 * 符合ArkTS规范的类型安全设计
 */

import { logger } from '../../Utils/Logger';

const TAG = 'DatabaseTypes';

/**
 * 数据库基础值类型
 */
export type DatabaseValue = string | number | boolean | Uint8Array | null;

/**
 * 漫画源配置类型接口
 */
export interface ComicSourceConfig {
  readonly baseUrl: string;
  readonly timeout: number;
  readonly retryCount: number;
  readonly userAgent: string;
  readonly headers: string; // JSON字符串格式
}

/**
 * 漫画标签数组类型
 */
export interface ComicTagsArray extends ReadonlyArray<string> {}

// ==================== 明确的数据库记录接口定义 ====================

/**
 * 图源类型
 */
export type SourceType = 'manga' | 'ebook' | 'novel' | 'video' | 'audio' | 'image';

/**
 * 漫画源数据库记录
 */
export interface ComicSourceDatabaseRecord {
  id: string;
  pkg?: string; // 图源唯一包名
  type?: SourceType; // 图源类型（默认为manga）
  name: string;
  baseUrl: string;
  pluginId: string;
  isEnabled: boolean;
  priority: number;
  lastUpdateTime: number;
  configJson: string; // JSON字符串 - 与数据库字段名一致
  addTime: number;
  userAgent?: string;
  enableJavaScript?: number; // 0: 禁用, 1: 启用
  enableImages?: number; // 0: 禁用, 1: 启用
  timeout?: number;
  cookies?: string;
  preloadCurrentChapter?: number; // 是否预加载当前章节（0/1）
  preloadCurrentPages?: number;    // 当前章节预加载页数（0=不预加载，-1=全部）
  preloadNextChapter?: number;     // 是否预加载下一章节（0/1）
  preloadNextPages?: number;       // 下一章节预加载页数（0=不预加载，-1=全部）
  isNSFW?: number;                 // 是否为NSFW内容（0=SFW, 1=NSFW）
}

/**
 * 漫画信息数据库记录
 */
export interface ComicInfoDatabaseRecord {
  id: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  coverLocalPath?: string;  // 封面本地路径
  sourceId: string;
  externalId: string;  // 外部图源ID
  status: string;
  tags: string; // JSON字符串
  rating: number;
  chapterCount: number;
  lastUpdateTime: number;
  addTime: number;
  createTime: number;  // 创建时间
  updateTime: number;  // 更新时间
  webUrl: string | null;  // 网页URL
  apiUrl: string | null;  // API请求地址
  contentType?: string;  // 内容类型：'manga' = 漫画, 'ebook' = 电子书类PDF
  isNSFW?: number;       // 是否为NSFW内容（0=SFW, 1=NSFW）
  isPrivate?: number;    // 是否为隐私内容（0=普通, 1=隐私）
}

/**
 * 章节信息数据库记录
 */
export interface ChapterInfoDatabaseRecord {
  id: string;
  comicId: string;
  externalId: string;  // 外部章节ID
  title: string;
  chapterIndex: number;
  chapterNumber: number;  // 章节编号
  pageCount: number;
  isDownloaded: boolean;
  downloadPath: string | null;
  publishTime: number;
  addTime: number;
  createTime: number;  // 创建时间
  updateTime: number;  // 更新时间
}

/**
 * 页面信息数据库记录
 */
export interface PageInfoDatabaseRecord {
  id: string;
  chapterId: string;
  index: number;
  imageUrl: string;
  localPath: string | null;
  width: number;
  height: number;
  fileSize: number;
}

/**
 * 收藏信息数据库记录
 */
export interface FavoriteInfoDatabaseRecord {
  id: string;
  comicId: string;
  userId: string;
  addTime: number;
  lastReadChapterId: string | null;
  lastReadTime: number | null;
  tags: string; // JSON字符串
  notes: string | null;
}

/**
 * 阅读历史数据库记录
 * 注意：字段名必须与数据库表read_history的实际字段名一致
 * 数据库字段：pageNumber, duration
 */
export interface ReadHistoryDatabaseRecord {
  id: string;
  comicId: string;
  chapterId: string;
  pageNumber: number;      // 数据库字段名：pageNumber
  userId: string;
  readTime: number;
  duration: number;         // 数据库字段名：duration
  createTime?: number;      // 数据库字段：createTime
}

/**
 * 下载任务数据库记录
 */
export interface DownloadTaskDatabaseRecord {
  id?: string | number;  // 自增ID，插入时可选
  comicId: string;
  chapterId: string;
  taskType: string;
  status: string;
  progress: number;
  totalSize: number;
  downloadedSize: number;
  downloadSpeed: number;
  priority: number;
  createTime: number;
  startTime: number;
  completeTime: number;
  errorMessage: string | null;
}

/**
 * 用户设置数据库记录
 * 注意：字段名必须与数据库表user_settings的实际字段名一致
 * 数据库字段：settingKey, settingValue, settingType
 */
export interface UserSettingsDatabaseRecord {
  id: string;
  userId: string;
  settingKey: string;        // 数据库字段名：settingKey
  settingValue: string;      // 数据库字段名：settingValue
  settingType: string;       // 数据库字段名：settingType
  description?: string;
  createTime: number;
  updateTime: number;
}

/**
 * 插件数据库记录
 */
export interface PluginDatabaseRecord {
  id: string;
  name: string;
  version: string;
  author: string;
  description: string;
  isEnabled: boolean;
  configSchema: string; // JSON字符串
  installTime: number;
  updateTime: number;
}
// 在线漫画独立数据结构
export interface OnlineComicInfoDatabaseRecord {
  id: string;
  sourceId: string;
  externalId: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  tags: string;
  rating: number;
  lastUpdateTime: number;
  addTime: number;
  createTime: number;
  updateTime: number;
  sourceName: string;
  isNSFW: number;
  isPrivate: number;
}

// 在线章节独立数据结构
export interface OnlineChapterInfoDatabaseRecord {
  id: string;
  comicId: string;
  externalId: string;
  title: string;
  chapterNumber: number;
  url: string | null;
  pageCount: number;
  publishTime: number;
  addTime: number;
  createTime: number;
  updateTime: number;
}

// 在线页面独立数据结构
export interface OnlinePageInfoDatabaseRecord {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  requestHeaders?: string;
  width: number;
  height: number;
  fileSize: number;
  createTime: number;
}

/**
 * WebView源配置数据库记录
 */
export interface WebViewSourceConfigDatabaseRecord {
  id: string;
  sourceId: string;
  webViewConfig: string; // JSON字符串，包含WebView配置
  userAgent: string;
  customHeaders: string; // JSON字符串，自定义请求头
  cookiePolicy: string;
  jsEnabled: boolean;
  imageLoadingEnabled: boolean;
  cacheMode: string;
  timeout: number;
  retryCount: number;
  antiDetectionConfig: string; // JSON字符串，反检测配置
  createTime: number;
  updateTime: number;
}

/**
 * WebView图片元数据数据库记录
 */
export interface WebViewImageMetadataDatabaseRecord {
  id: string;
  imageUrl: string;
  sourceId: string;
  chapterId: string;
  pageIndex: number;
  originalWidth: number;
  originalHeight: number;
  fileSize: number;
  mimeType: string;
  cacheKey: string;
  loadTime: number;
  fromCache: boolean;
  compressionRatio: number;
  qualityScore: number;
  loadDuration: number;
  errorCount: number;
  lastErrorMessage: string | null;
  createTime: number;
  updateTime: number;
}

/**
 * WebView请求统计数据库记录
 */
export interface WebViewRequestStatsDatabaseRecord {
  id: string;
  sourceId: string;
  requestUrl: string;
  requestMethod: string;
  responseStatus: number;
  responseTime: number;
  dataSize: number;
  cacheHit: boolean;
  userAgent: string;
  referer: string | null;
  errorMessage: string | null;
  requestTime: number;
}

// ==================== 数据库记录工厂类 ====================

/**
 * 数据库记录工厂类
 * 提供类型安全的记录创建方法
 */
export class DatabaseRecordFactory {
  /**
   * 创建漫画源数据库记录
   */
  static createComicSourceRecord(): ComicSourceDatabaseRecord {
    return {
      id: '',
      name: '',
      baseUrl: '',
      pluginId: '',
      isEnabled: true,
      priority: 0,
      lastUpdateTime: 0,
      configJson: '{}',
      addTime: 0
    };
  }

  /**
   * 创建漫画信息数据库记录
   */
  static createComicInfoRecord(): ComicInfoDatabaseRecord {
    return {
      id: '',
      title: '',
      author: '',
      description: '',
      coverUrl: '',
      sourceId: '',
      externalId: '',  // 外部图源ID
      status: '',
      tags: '[]',
      rating: 0,
      chapterCount: 0,
      lastUpdateTime: 0,
      addTime: 0,
      createTime: 0,
      updateTime: 0,
      webUrl: null,
      apiUrl: null
    };
  }

  /**
   * 创建章节信息数据库记录
   */
  static createChapterInfoRecord(): ChapterInfoDatabaseRecord {
    return {
      id: '',
      comicId: '',
      externalId: '',
      title: '',
      chapterIndex: 0,
      chapterNumber: 0,
      pageCount: 0,
      isDownloaded: false,
      downloadPath: null,
      publishTime: 0,
      addTime: 0,
      createTime: 0,
      updateTime: 0
    };
  }

  /**
   * 创建页面信息数据库记录
   */
  static createPageInfoRecord(): PageInfoDatabaseRecord {
    return {
      id: '',
      chapterId: '',
      index: 0,
      imageUrl: '',
      localPath: null,
      width: 0,
      height: 0,
      fileSize: 0
    };
  }

  /**
   * 创建收藏信息数据库记录
   */
  static createFavoriteInfoRecord(): FavoriteInfoDatabaseRecord {
    return {
      id: '',
      comicId: '',
      userId: '',
      addTime: 0,
      lastReadChapterId: null,
      lastReadTime: null,
      tags: '[]',
      notes: null
    };
  }

  /**
   * 创建阅读历史数据库记录
   */
  static createReadHistoryRecord(): ReadHistoryDatabaseRecord {
    return {
      id: '',
      comicId: '',
      chapterId: '',
      pageNumber: 0,        // 使用pageNumber字段
      userId: '',
      readTime: 0,
      duration: 0,          // 使用duration字段
      createTime: 0
    };
  }

  /**
   * 创建下载任务数据库记录
   */
  static createDownloadTaskRecord(): DownloadTaskDatabaseRecord {
    return {
      id: '',
      comicId: '',
      chapterId: '',
      taskType: 'chapter',
      status: '',
      progress: 0,
      totalSize: 0,
      downloadedSize: 0,
      downloadSpeed: 0,
      priority: 0,
      createTime: 0,
      startTime: 0,
      completeTime: 0,
      errorMessage: null
    };
  }

  /**
   * 创建用户设置数据库记录
   */
  static createUserSettingsRecord(): UserSettingsDatabaseRecord {
    return {
      id: '',
      userId: '',
      settingKey: '',        // 使用settingKey字段
      settingValue: '',      // 使用settingValue字段
      settingType: 'string',  // 使用settingType字段
      description: '',
      createTime: 0,
      updateTime: 0
    };
  }

  /**
   * 创建插件数据库记录
   */
  static createPluginRecord(): PluginDatabaseRecord {
    return {
      id: '',
      name: '',
      version: '',
      author: '',
      description: '',
      isEnabled: true,
      configSchema: '{}',
      installTime: 0,
      updateTime: 0
    };
  }

  /**
   * 创建WebView源配置数据库记录
   */
  static createWebViewSourceConfigRecord(): WebViewSourceConfigDatabaseRecord {
    return {
      id: '',
      sourceId: '',
      webViewConfig: '{}',
      userAgent: 'Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36',
      customHeaders: '{}',
      cookiePolicy: 'accept_all',
      jsEnabled: true,
      imageLoadingEnabled: true,
      cacheMode: 'default',
      timeout: 30000,
      retryCount: 3,
      antiDetectionConfig: '{}',
      createTime: 0,
      updateTime: 0
    };
  }

  /**
   * 创建WebView图片元数据数据库记录
   */
  static createWebViewImageMetadataRecord(): WebViewImageMetadataDatabaseRecord {
    return {
      id: '',
      imageUrl: '',
      sourceId: '',
      chapterId: '',
      pageIndex: 0,
      originalWidth: 0,
      originalHeight: 0,
      fileSize: 0,
      mimeType: 'image/jpeg',
      cacheKey: '',
      loadTime: 0,
      fromCache: false,
      compressionRatio: 1.0,
      qualityScore: 100,
      loadDuration: 0,
      errorCount: 0,
      lastErrorMessage: null,
      createTime: 0,
      updateTime: 0
    };
  }

  /**
   * 创建WebView请求统计数据库记录
   */
  static createWebViewRequestStatsRecord(): WebViewRequestStatsDatabaseRecord {
    return {
      id: '',
      sourceId: '',
      requestUrl: '',
      requestMethod: 'GET',
      responseStatus: 0,
      responseTime: 0,
      dataSize: 0,
      cacheHit: false,
      userAgent: '',
      referer: null,
      errorMessage: null,
      requestTime: 0
    };
  }
}

// ==================== 转换工具函数 ====================

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertComicSourceToDbFormat(record: ComicSourceDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "pkg": record.pkg ?? '',
    "type": record.type ?? 'manga',
    "name": record.name,
    "baseUrl": record.baseUrl,
    "pluginId": record.pluginId,
    "isEnabled": record.isEnabled,
    "priority": record.priority,
    "lastUpdateTime": record.lastUpdateTime,
    "configJson": record.configJson,
    "addTime": record.addTime,
    "cookies": record.cookies ?? ''
  } as Record<string, DatabaseValue>;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertComicInfoToDbFormat(record: ComicInfoDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "title": record.title,
    "author": record.author,
    "description": record.description,
    "coverUrl": record.coverUrl,
    "coverLocalPath": record.coverLocalPath || '',  // 封面本地路径
    "sourceId": record.sourceId,
    "externalId": record.externalId,  // 外部图源ID
    "status": record.status,
    "tags": record.tags,
    "rating": record.rating,
    "chapterCount": record.chapterCount,
    "lastUpdateTime": record.lastUpdateTime,
    "addTime": record.addTime,
    "createTime": record.createTime,
    "updateTime": record.updateTime,
    "webUrl": record.webUrl,
    "apiUrl": record.apiUrl,
    "contentType": record.contentType || 'manga',  // 内容类型
    "isNSFW": record.isNSFW || 0,  // NSFW标记
    "isPrivate": record.isPrivate || 0  // 隐私标记
  } as Record<string, DatabaseValue>;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertChapterInfoToDbFormat(record: ChapterInfoDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "comicId": record.comicId,
    "externalId": record.externalId,
    "title": record.title,
    "chapterNumber": record.chapterNumber,
    "pageCount": record.pageCount,
    "isDownloaded": record.isDownloaded ? 1 : 0,
    "downloadPath": record.downloadPath,
    "publishTime": record.publishTime,
    "addTime": record.addTime,
    "createTime": record.createTime,
    "updateTime": record.updateTime
  } as Record<string, DatabaseValue>;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertPageInfoToDbFormat(record: PageInfoDatabaseRecord): Record<string, DatabaseValue> {
  // 添加严格的类型检查和默认值
  const result: Record<string, DatabaseValue> = {
    "id": record.id || '',
    "chapterId": record.chapterId || '',
    "pageNumber": Math.floor(record.index) || 0,
    "imageUrl": record.imageUrl || '',
    "localPath": record.localPath,
    "width": Math.floor(record.width) || 0,
    "height": Math.floor(record.height) || 0,
    "fileSize": Math.floor(record.fileSize) || 0,
    "isDownloaded": 0,
    "createTime": Date.now()
  };
  
  // 记录转换后的数据用于调试
  logger.debug('DatabaseTypes', `convertPageInfoToDbFormat 转换结果: ${JSON.stringify(result)}`);
  
  return result;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 * 注意：favorite表的id是INTEGER PRIMARY KEY AUTOINCREMENT，不需要手动插入
 * 表结构：id, comicId, userId, folderName, addTime, lastReadChapterId, lastReadPageNumber, lastReadTime, readProgress
 */
export function convertFavoriteInfoToDbFormat(record: FavoriteInfoDatabaseRecord): Record<string, DatabaseValue> {
  // 不包含id字段，让数据库自动生成自增ID
  const mapped: Record<string, DatabaseValue> = {} as Record<string, DatabaseValue>;
  mapped["comicId"] = record.comicId as DatabaseValue;
  mapped["userId"] = record.userId as DatabaseValue;
  mapped["folderName"] = "default" as DatabaseValue; // 默认文件夹
  mapped["addTime"] = (record.addTime as number) as DatabaseValue;
  // lastReadChapterId为TEXT列，避免null
  mapped["lastReadChapterId"] = (record.lastReadChapterId ? record.lastReadChapterId : "") as DatabaseValue;
  // lastReadPageNumber为INTEGER列，默认0
  mapped["lastReadPageNumber"] = 0 as DatabaseValue;
  // lastReadTime为INTEGER列，避免null
  mapped["lastReadTime"] = ((record.lastReadTime as number) ?? 0) as DatabaseValue;
  // readProgress为REAL列，默认0.0
  mapped["readProgress"] = 0.0 as DatabaseValue;
  return mapped;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertReadHistoryToDbFormat(record: ReadHistoryDatabaseRecord): Record<string, DatabaseValue> {
  // ReadHistoryDatabaseRecord字段已与数据库表read_history对齐：pageNumber, duration, createTime
  const mapped: Record<string, DatabaseValue> = {} as Record<string, DatabaseValue>;
  mapped["comicId"] = record.comicId as DatabaseValue;
  mapped["chapterId"] = record.chapterId as DatabaseValue;
  mapped["userId"] = record.userId as DatabaseValue;
  mapped["pageNumber"] = Math.floor(record.pageNumber) as DatabaseValue;   // 直接使用pageNumber
  mapped["readTime"] = Math.floor(record.readTime) as DatabaseValue;
  mapped["duration"] = Math.floor(record.duration) as DatabaseValue;        // 直接使用duration
  // createTime 与 readTime 对齐，保证非空
  mapped["createTime"] = record.createTime ? Math.floor(record.createTime) : Math.floor(record.readTime) as DatabaseValue;
  return mapped;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertDownloadTaskToDbFormat(record: DownloadTaskDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "comicId": record.comicId,
    "chapterId": record.chapterId,
    "taskType": record.taskType,
    "status": record.status,
    "progress": record.progress,
    "totalSize": record.totalSize,
    "downloadedSize": record.downloadedSize,
    "downloadSpeed": record.downloadSpeed,
    "priority": record.priority,
    "createTime": record.createTime,
    "startTime": record.startTime,
    "completeTime": record.completeTime,
    "errorMessage": record.errorMessage
  } as Record<string, DatabaseValue>;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertUserSettingsToDbFormat(record: UserSettingsDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "userId": record.userId,
    "settingKey": record.settingKey,       // 使用settingKey字段
    "settingValue": record.settingValue,   // 使用settingValue字段
    "settingType": record.settingType,     // 使用settingType字段
    "description": record.description || '',
    "createTime": record.createTime,
    "updateTime": record.updateTime
  } as Record<string, DatabaseValue>;
}

/**
 * 将数据库记录转换为HarmonyOS兼容的格式
 */
export function convertPluginToDbFormat(record: PluginDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "name": record.name,
    "version": record.version,
    "author": record.author,
    "description": record.description,
    "isEnabled": record.isEnabled,
    "configSchema": record.configSchema,
    "installTime": record.installTime,
    "updateTime": record.updateTime
  } as Record<string, DatabaseValue>;
}

export function convertOnlineComicInfoToDbFormat(record: OnlineComicInfoDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "sourceId": record.sourceId,
    "externalId": record.externalId,
    "title": record.title,
    "author": record.author,
    "description": record.description,
    "coverUrl": record.coverUrl,
    "tags": record.tags,
    "rating": record.rating,
    "lastUpdateTime": record.lastUpdateTime,
    "addTime": record.addTime,
    "createTime": record.createTime,
    "updateTime": record.updateTime
  } as Record<string, DatabaseValue>;
}

export function convertOnlineChapterInfoToDbFormat(record: OnlineChapterInfoDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "comicId": record.comicId,
    "externalId": record.externalId,
    "title": record.title,
    "chapterNumber": record.chapterNumber,
    "url": record.url ? record.url : '',
    "pageCount": record.pageCount,
    "publishTime": record.publishTime,
    "addTime": record.addTime,
    "createTime": record.createTime,
    "updateTime": record.updateTime
  } as Record<string, DatabaseValue>;
}

export function convertOnlinePageInfoToDbFormat(record: OnlinePageInfoDatabaseRecord): Record<string, DatabaseValue> {
  return {
    "id": record.id,
    "chapterId": record.chapterId,
    "pageNumber": record.pageNumber,
    "imageUrl": record.imageUrl,
    "requestHeaders": record.requestHeaders ? record.requestHeaders : '',
    "width": record.width,
    "height": record.height,
    "fileSize": record.fileSize,
    "createTime": record.createTime
  } as Record<string, DatabaseValue>;
}

/**
 * 安全的JSON解析函数
 */
export function safeJsonParse<T>(jsonString: string, defaultValue: T): T {
  if (!jsonString) {
    return defaultValue;
  }
  
  try {
    return SafeUtils.parseObj(jsonString) as T;
  } catch (error) {
    logger.warn(TAG, `JSON解析失败: ${error}, 使用默认值`);
    return defaultValue;
  }
}

// ==================== 聚合查询结果接口 ====================

/**
 * 聚合查询结果值类型（不包含Uint8Array和null）
 */
export type AggregationValue = string | number;

/**
 * COUNT 查询结果接口
 */
export interface CountQueryResult {
  count: number;
}

/**
 * COUNT 查询结果实现类
 */
export class CountResult implements CountQueryResult {
  count: number;
  
  constructor(count: number) {
    this.count = count;
  }
}

/**
 * SUM 查询结果接口
 */
export interface SumQueryResult {
  sum: number;
}

/**
 * SUM 查询结果实现类
 */
export class SumResult implements SumQueryResult {
  sum: number;
  
  constructor(sum: number) {
    this.sum = sum;
  }
}

/**
 * AVG 查询结果接口
 */
export interface AvgQueryResult {
  avg: number;
}

/**
 * AVG 查询结果实现类
 */
export class AvgResult implements AvgQueryResult {
  avg: number;
  
  constructor(avg: number) {
    this.avg = avg;
  }
}

/**
 * MIN/MAX 查询结果接口
 */
export interface MinMaxQueryResult {
  min?: AggregationValue;
  max?: AggregationValue;
}

/**
 * MIN/MAX 查询结果实现类
 */
export class MinMaxResult implements MinMaxQueryResult {
  min?: AggregationValue;
  max?: AggregationValue;
  
  constructor(min?: AggregationValue, max?: AggregationValue) {
    this.min = min;
    this.max = max;
  }
}

/**
 * 聚合查询结果联合类型
 */
export type AggregationQueryResult = 
  | CountQueryResult
  | SumQueryResult
  | AvgQueryResult
  | MinMaxQueryResult;

/**
 * 数据库记录联合类型
 */
/**
 * 通用数据库查询结果记录 - 用于原生SQL查询
 * 包含所有可能的数据库字段，所有字段都是可选的
 * 这样可以匹配任何表的查询结果
 */
export interface GenericQueryRecord {
  // 通用字段
  id?: DatabaseValue;
  // read_history 表字段
  comicId?: DatabaseValue;
  chapterId?: DatabaseValue;
  // online_chapter 表字段
  externalId?: DatabaseValue;
  url?: DatabaseValue;  // 章节URL
  userId?: DatabaseValue;
  pageNumber?: DatabaseValue;
  readTime?: DatabaseValue;
  duration?: DatabaseValue;
  createTime?: DatabaseValue;
  // comic_info 表字段
  title?: DatabaseValue;
  author?: DatabaseValue;
  description?: DatabaseValue;
  coverUrl?: DatabaseValue;
  sourceId?: DatabaseValue;
  status?: DatabaseValue;
  tags?: DatabaseValue;
  rating?: DatabaseValue;
  chapterCount?: DatabaseValue;
  lastUpdateTime?: DatabaseValue;
  addTime?: DatabaseValue;
  // chapter 表字段
  chapterIndex?: DatabaseValue;
  pageCount?: DatabaseValue;
  isDownloaded?: DatabaseValue;
  downloadPath?: DatabaseValue;
  publishTime?: DatabaseValue;
  // page 表字段
  index?: DatabaseValue;
  imageUrl?: DatabaseValue;
  requestHeaders?: DatabaseValue;
  localPath?: DatabaseValue;
  width?: DatabaseValue;
  height?: DatabaseValue;
  fileSize?: DatabaseValue;
  // user_settings 表字段
  settingKey?: DatabaseValue;
  settingValue?: DatabaseValue;
  settingType?: DatabaseValue;
  updateTime?: DatabaseValue;
  // comic_source 表字段
  name?: DatabaseValue;
  baseUrl?: DatabaseValue;
  pluginId?: DatabaseValue;
  isEnabled?: DatabaseValue;
  priority?: DatabaseValue;
  config?: DatabaseValue;
  configJson?: DatabaseValue;  // 图源JSON配置字段
  userAgent?: DatabaseValue;
  enableJavaScript?: DatabaseValue;
  enableImages?: DatabaseValue;
  timeout?: DatabaseValue;
  cookies?: DatabaseValue;
  pkg?: DatabaseValue;         // 图源包名
  iconPath?: DatabaseValue;    // 图源图标路径
  type?: DatabaseValue;        // 图源类型 (manga/ebook/novel)
  requireProxy?: DatabaseValue; // 是否需要代理
  sourcePkg?: DatabaseValue;   // 在线漫画关联的图源包名
  // favorite 表字段
  favoriteType?: DatabaseValue;
  favoriteTime?: DatabaseValue;
  sortOrder?: DatabaseValue;
  // download_task 表字段
  taskType?: DatabaseValue;
  targetId?: DatabaseValue;
  targetTitle?: DatabaseValue;
  totalSize?: DatabaseValue;
  downloadedSize?: DatabaseValue;
  progress?: DatabaseValue;
  statusCode?: DatabaseValue;
  errorMessage?: DatabaseValue;
  startTime?: DatabaseValue;
  endTime?: DatabaseValue;
  // plugin 表字段
  version?: DatabaseValue;
  enabled?: DatabaseValue;
  configData?: DatabaseValue;
  installTime?: DatabaseValue;
  // webview_source_config 表字段
  enableCookie?: DatabaseValue;
  cookieData?: DatabaseValue;
  enableCache?: DatabaseValue;
  cacheMode?: DatabaseValue;
  customHeaders?: DatabaseValue;
  proxyConfig?: DatabaseValue;
  // webview_image_metadata 表字段
  pageIndex?: DatabaseValue;
  originalUrl?: DatabaseValue;
  finalUrl?: DatabaseValue;
  mimeType?: DatabaseValue;
  contentLength?: DatabaseValue;
  loadTime?: DatabaseValue;
  cacheStatus?: DatabaseValue;
  captureTime?: DatabaseValue;
  // webview_request_stats 表字段
  requestType?: DatabaseValue;
  requestUrl?: DatabaseValue;
  requestMethod?: DatabaseValue;
  statusText?: DatabaseValue;
  responseSize?: DatabaseValue;
  responseTime?: DatabaseValue;
  errorCode?: DatabaseValue;
  requestTime?: DatabaseValue;
  // ebook_info 表字段
  content?: DatabaseValue;
  bookId?: DatabaseValue;
  chapterNumber?: DatabaseValue;
  startPosition?: DatabaseValue;
  endPosition?: DatabaseValue;
  wordCount?: DatabaseValue;
  format?: DatabaseValue;
  filePath?: DatabaseValue;
  publisher?: DatabaseValue;
  publishDate?: DatabaseValue;
  isbn?: DatabaseValue;
  language?: DatabaseValue;
  coverImagePath?: DatabaseValue;
  isFavorite?: DatabaseValue;
  totalWordCount?: DatabaseValue;
  // ebook_reading_progress 表字段
  currentChapterId?: DatabaseValue;
  currentChapterIndex?: DatabaseValue;  // 当前章节索引
  currentPosition?: DatabaseValue;
  domPos?: DatabaseValue;  // Reader Kit DOM位置信息
  lastReadTime?: DatabaseValue;
  totalReadingTime?: DatabaseValue;
  // ebook_reading_settings 表字段
  fontSize?: DatabaseValue;
  lineHeight?: DatabaseValue;
  fontFamily?: DatabaseValue;
  fontPath?: DatabaseValue;  // 自定义字体路径
  fontWeight?: DatabaseValue;  // 字体粗细
  backgroundColor?: DatabaseValue;
  textColor?: DatabaseValue;
  themeBgImage?: DatabaseValue;  // 主题背景图片
  nightMode?: DatabaseValue;  // 夜间模式
  followSystemTheme?: DatabaseValue;  // 跟随系统主题
  pageMargin?: DatabaseValue;
  pageTopMargin?: DatabaseValue;
  pageBottomMargin?: DatabaseValue;
  pageMode?: DatabaseValue;
  brightness?: DatabaseValue;
  autoSave?: DatabaseValue;
  saveInterval?: DatabaseValue;
  // ========== 纯文本阅读器专用设置字段 ==========
  letterSpacing?: DatabaseValue;  // 字间距
  paragraphSpacing?: DatabaseValue;  // 段间距
  firstLineIndent?: DatabaseValue;  // 首行缩进
  textAlignment?: DatabaseValue;  // 文字对齐方式
  pageTurnAnimation?: DatabaseValue;  // 翻页动画
  tapToTurn?: DatabaseValue;  // 点击翻页
  volumeKeyNavigation?: DatabaseValue;  // 音量键翻页
  keepScreenOn?: DatabaseValue;  // 保持屏幕常亮
  showPageNumber?: DatabaseValue;  // 显示页码
  showProgress?: DatabaseValue;  // 显示进度
  showTime?: DatabaseValue;  // 显示时间
  showBattery?: DatabaseValue;  // 显示电量
  backgroundType?: DatabaseValue;  // 背景类型 (COLOR/IMAGE)
  backgroundImagePath?: DatabaseValue;  // 背景图片路径
  backgroundImageOpacity?: DatabaseValue;  // 背景图片透明度
  imageReaderSettingsJson?: DatabaseValue;  // 图片阅读设置 JSON
  imageReaderSettingsJsonLength?: DatabaseValue;  // 图片阅读设置 JSON 长度

  // unified_annotation 字段
  contentType?: DatabaseValue;
  contentId?: DatabaseValue;
  annotationType?: DatabaseValue;
  textContent?: DatabaseValue;
  quoteText?: DatabaseValue;
  chapterTitle?: DatabaseValue;
  pageProgress?: DatabaseValue;
  startOffset?: DatabaseValue;
  endOffset?: DatabaseValue;
  anchorJson?: DatabaseValue;
  styleJson?: DatabaseValue;
  linkedAnnotationId?: DatabaseValue;
  isDeleted?: DatabaseValue;

  // 隐私和NSFW字段
  isNSFW?: DatabaseValue;  // 是否为NSFW内容（0=SFW, 1=NSFW）
  isPrivate?: DatabaseValue;  // 是否为隐私内容（0=普通, 1=隐私）
}

// 跟踪记录数据库记录接口
export interface TrackRecordDatabaseRecord {
  id?: DatabaseValue;
  contentId?: DatabaseValue;
  contentType?: DatabaseValue;
  trackerId?: DatabaseValue;
  remoteId?: DatabaseValue;
  remoteTitle?: DatabaseValue;
  remoteUrl?: DatabaseValue;
  lastChapterRead?: DatabaseValue;
  totalChapters?: DatabaseValue;
  score?: DatabaseValue;
  status?: DatabaseValue;
  startedReadingDate?: DatabaseValue;
  finishedReadingDate?: DatabaseValue;
  lastSyncTime?: DatabaseValue;
  syncStatus?: DatabaseValue;
  createTime?: DatabaseValue;
  updateTime?: DatabaseValue;
}

export type DatabaseRecord = 
  | ComicSourceDatabaseRecord
  | ComicInfoDatabaseRecord
  | ChapterInfoDatabaseRecord
  | PageInfoDatabaseRecord
  | FavoriteInfoDatabaseRecord
  | ReadHistoryDatabaseRecord
  | DownloadTaskDatabaseRecord
  | UserSettingsDatabaseRecord
  | PluginDatabaseRecord
  | WebViewSourceConfigDatabaseRecord
  | WebViewImageMetadataDatabaseRecord
  | WebViewRequestStatsDatabaseRecord
  | OnlineComicInfoDatabaseRecord
  | OnlineChapterInfoDatabaseRecord
  | OnlinePageInfoDatabaseRecord
  | GenericQueryRecord
  | TrackRecordDatabaseRecord;

// 统一的更新记录数据接口 - 支持所有数据库记录类型
export interface UpdateRecordData {
  id: string;
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  isEnabled?: boolean;
  priority?: number;
  config?: string;
  lastUpdateTime?: string;
  downloadPath?: string;
  isDownloaded?: boolean;
  sourceId?: string;
  chapterId?: string;
  comicId?: string;
  title?: string;
  url?: string;
  status?: string;
  progress?: number;
  totalPages?: number;
  currentPage?: number;
  readTime?: string;
  bookmarkTime?: string;
  tags?: string;
  description?: string;
  coverUrl?: string;
  author?: string;
  category?: string;
  rating?: number;
  viewCount?: number;
  favoriteCount?: number;
  commentCount?: number;
  createdAt?: string;
  updatedAt?: string;
  userAgent?: string;
  enableJavaScript?: boolean | number;
  enableImages?: boolean | number;
  timeout?: number;
  localPath?: string;
}

// 统一的漫画源更新数据接口
export interface ComicSourceUpdateData {
  id: string;
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  isEnabled?: boolean;
  priority?: number;
  config?: string; // JSON字符串格式，与数据库存储格式一致
  lastUpdateTime?: number;
}

// 统一的章节更新数据接口
export interface ChapterUpdateData {
  id: string;
  isDownloaded?: boolean;
  downloadPath?: string;
  sourceId?: string;
  sourceChapterId?: string;
  comicId?: string;
  title?: string;
  chapterNumber?: number;
  publishTime?: number;
  pageCount?: number;
  downloadTime?: number;
  fileSize?: number;
  lastReadTime?: number;
  readProgress?: number;
}

// 统一的下载任务更新数据接口
export interface DownloadTaskUpdateData {
  id: string;
  status?: 'pending' | 'downloading' | 'completed' | 'failed' | 'paused';
  progress?: number;
  downloadedPages?: number;
  errorMessage?: string;
  updateTime?: number;
}

// 通用更新数据接口（用于简单更新操作）
export interface GeneralUpdateData {
  id: string;
  lastUpdateTime?: number;
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  isEnabled?: boolean;
  priority?: number;
}

/**
 * 数据库记录类型枚举
 */
export enum DatabaseRecordType {
  COMIC_SOURCE = 'COMIC_SOURCE',
  COMIC_INFO = 'COMIC_INFO',
  CHAPTER_INFO = 'CHAPTER_INFO',
  PAGE_INFO = 'PAGE_INFO',
  FAVORITE_INFO = 'FAVORITE_INFO',
  read_HISTORY = 'read_HISTORY',
  DOWNLOAD_TASK = 'DOWNLOAD_TASK',
  USER_SETTINGS = 'USER_SETTINGS',
  PLUGIN = 'PLUGIN'
}
