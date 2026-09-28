/** 数据契约（DataManager 契约化）—— 纯数据类型下沉，entry 本地导入并再导出。 */
import { DatabaseValue, ComicInfoDatabaseRecord } from '../Database/DatabaseTypes';
import { MangaStatus, DownloadStatus } from '../Types/StatusEnums';

export interface SourceConfigResult {
  id: number;
  config: ESObject;
}

// ==================== 数据库记录转换接口定义 ====================

// 定义明确的配置对象接口，避免使用索引签名
export interface ConfigObject {
  id?: string;
  name?: string;
  baseUrl?: string;
  pluginId?: string;
  type?: string;
  version?: string;
  description?: string;
  author?: string;
  language?: string;
  enabled?: boolean;
  priority?: number;
  timeout?: number;
  retryCount?: number;
  userAgent?: string;
  headers?: string;
  cookies?: string;
  Internet?: boolean;
  nsfw?: boolean | number;
}

export interface ComicSourceConfigPatch {
  metadata?: ConfigObject;
  baseUrl?: string;
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

export interface IncompleteLocalImportCleanupResult {
  deletedCount: number;
  deletedComicIds: string[];
}

export interface LocalComicCleanupRecord {
  localRowId: number;
  id: string;
  title: string;
  sourceId: string;
  addTime: number;
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

/** COUNT(*) 查询结果行 */
export interface CountRecord {
  cnt: number;
}

/** 章节页面完整性检查用的章节行（id + pageCount） */
export interface ChapterPageCountRecord {
  id: string;
  pageCount: number;
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

export interface ComicSourceDatabaseInput {
  pkg: string;
  name: string;
  baseUrl: string;
  version: string;
  description: string;
  language: string;
  type: string;
  isEnabled: boolean;
  priority: number;
  configJson: string;
  requireProxy: boolean;
  isNSFW: boolean;
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

export interface ChapterInfoCreationResult {
  id: string;
  created: boolean;
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

export interface ChapterComicIdRecord {
  comicId: string;
}

export interface OnlineComicSourceSaveInput {
  id?: string;
  title: string;
  author: string;
  description: string;
  coverUrl: string;
  tags: string[];
  rating: number;
  updateTime: number;
  sourceName?: string;
  sourcePkg?: string;
  isNSFW?: boolean | number;
  status?: string;
  chapterCount?: number;
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
  requestHeaders?: string;
  width: number;
  height: number;
  fileSize: number;
}

export interface OnlinePageRequestHeader {
  name: string;
  value: string;
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
  requestHeaders?: string;
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

export interface ComicInfoBatchRecord extends ComicInfoDatabaseRecord {
  _source: string;
  _priority: number;
}


