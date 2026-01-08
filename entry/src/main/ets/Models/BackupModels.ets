/**
 * 备份数据模型
 * 支持漫画、小说、电子书的完整备份和恢复
 * 
 * 文件路径: entry/src/main/ets/Models/BackupModels.ets
 */

import { NovelBook } from './NovelModels';

/**
 * 完整备份数据结构
 */
export interface BackupData {
  version: string;                    // 备份格式版本
  appVersion: string;                 // 应用版本
  timestamp: number;                  // 备份时间戳
  deviceInfo?: string;                // 设备信息
  
  // 漫画数据
  manga: MangaBackupSection;
  
  // 小说数据
  novel: NovelBackupSection;
  
  // 电子书数据
  ebook: EBookBackupSection;
  
  // 书源数据
  sources: SourcesBackupSection;
  
  // 设置数据
  settings: SettingsBackupSection;
  
  // 历史记录
  history: HistoryBackupSection;
  
  // WebView配置
  webview?: WebViewBackupSection;
  
  // 下载任务
  downloads?: DownloadBackupSection;
  
  // 缓存信息
  cache?: CacheBackupSection;
  
  // 插件信息
  plugins?: PluginBackupSection;
  
  // 收藏标签
  favorites?: FavoriteBackupSection;
  
  // 在线漫画数据
  onlineData?: OnlineDataBackupSection;
  
  // 云存储配置
  cloudConfig?: CloudConfigBackupSection;
}

/**
 * 云存储配置备份
 */
export interface CloudConfigBackupSection {
  webdav?: WebDAVConfigBackup;
}

/**
 * WebDAV配置备份
 */
export interface WebDAVConfigBackup {
  serverUrl: string;
  username: string;
  password: string;
  basePath: string;
  autoBackup: boolean;
  autoBackupInterval: 'manual' | 'daily' | 'weekly';
  keepBackupCount: number;
}

/**
 * 漫画备份项
 */
export interface MangaBackupItem {
  id: string;
  sourceId: string;
  sourceName: string;
  url: string;
  title: string;
  author: string;
  artist: string;
  description: string;
  genre: string[];
  status: string;
  coverUrl: string;
  coverLocalPath?: string;
  isFavorite: boolean;
  isPrivate?: boolean;
  isNSFW?: boolean;
  categories: string[];
  lastUpdateTime: number;
  dateAdded: number;
  
  // 章节信息
  chapters: MangaChapterBackup[];
  
  // 阅读状态
  lastReadChapterId?: string;
  lastReadChapterIndex?: number;
  lastReadPage?: number;
  lastReadTime?: number;
  
  // 内容类型（用于区分Download同步导入的内容）
  contentType?: string;  // 'manga' | 'ebook' | 'online'
  webUrl?: string;
  apiUrl?: string;
}

/**
 * 漫画章节备份（包含下载相关字段）
 */
export interface MangaChapterBackup {
  id: string;
  title: string;
  url: string;
  chapterNumber: string;
  scanlator: string;
  uploadDate: number;
  dateUploaded: number;
  chapterIndex: number;
  read: boolean;
  bookmark: boolean;
  lastPageRead: number;
  dateFetch: number;
  sourceOrder: number;
  // 下载相关字段
  pageCount?: number;
  isDownloaded?: boolean;
  downloadPath?: string;
  fileSize?: number;
  externalId?: string;
  // [修复] 添加页面数据，用于本地漫画恢复
  pages?: MangaPageBackup[];
}

/**
 * 漫画页面备份
 */
export interface MangaPageBackup {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  localPath: string;
  width?: number;
  height?: number;
  fileSize?: number;
  isDownloaded?: number;
  createTime?: number;
}

/**
 * 小说备份项
 */
export interface NovelBackupItem {
  id: string;
  sourceId: string;
  sourceName: string;
  bookUrl: string;
  name: string;
  author: string;
  kind: string;
  intro: string;
  coverUrl: string;
  coverLocalPath?: string;
  tocUrl: string;
  latestChapterTitle: string;
  wordCount: string;
  chapterCount: number;
  readStatus: string;
  isFavorite: boolean;
  isPrivate?: boolean;
  isNSFW?: boolean;
  groupName?: string;
  createTime: number;
  updateDbTime: number;
  
  // 阅读状态
  lastReadChapterId?: string;
  lastReadChapterIndex?: number;
  lastReadPosition?: number;
  lastReadTime?: number;
  totalReadingTime?: number;
}

/**
 * 电子书备份项
 */
export interface EBookBackupItem {
  id: string;
  format: string;
  title: string;
  author: string;
  publisher: string;
  publishDate: string;
  isbn: string;
  language: string;
  description: string;
  coverPath: string;
  filePath: string;
  fileSize: number;
  totalPages: number;
  currentPage: number;
  readProgress: number;
  lastReadTime: number;
  lastUpdateTime: number;
  isFavorite: boolean;
  isPrivate: boolean;
  isNSFW: boolean;
  totalWordCount: number;
}

/**
 * 漫画书源备份（完整字段）
 */
export interface MangaSourceBackup {
  id: string;
  pkg?: string;
  name: string;
  baseUrl: string;
  version?: string;
  description?: string;
  lang: string;
  type?: string;
  isEnabled: boolean;
  priority?: number;
  configJson?: string;
  cookies?: string;
  tabsConfig?: string;
  createTime?: number;
  preloadCurrentChapter?: number;
  preloadCurrentPages?: number;
  preloadNextChapter?: number;
  preloadNextPages?: number;
  downloadWhileReading?: number;
  maxCacheSize?: number;
  requireProxy?: number;
  isNSFW?: boolean;
  lastUsedTime?: number;
}

/**
 * 小说书源备份（完整字段，包含configJson）
 */
export interface NovelSourceBackup {
  id: string;
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceGroup?: string;
  bookSourceType?: number;
  enabled: boolean;
  enabledExplore?: boolean;
  weight?: number;
  respondTime?: number;
  configJson: string;  // 完整的Legado书源配置JSON
  createTime?: number;
  updateTime?: number;
  isNSFW?: boolean;
  // 兼容旧版本的字段
  name?: string;
  sourceUrl?: string;
  lastUpdateTime?: number;
}

/**
 * 浏览历史备份
 */
export interface BrowseHistoryBackup {
  sourceId: string;
  contentId: string;
  contentType: 'manga' | 'novel' | 'ebook';
  title: string;
  coverUrl?: string;
  browseTime: number;
}

/**
 * 搜索历史备份
 */
export interface SearchHistoryBackup {
  keyword: string;
  searchTime: number;
  contentType: 'manga' | 'novel';
}

/**
 * 备份元数据
 */
/**
 * 漫画备份数据段
 */
export interface MangaBackupSection {
  library: MangaBackupItem[];
  readProgress: MangaReadProgressBackup[];
  categories: string[];
}

/**
 * 小说备份数据段
 */
export interface NovelBackupSection {
  library: NovelBackupItem[];
  readProgress: NovelReadProgressBackup[];
  categories: string[];
}

/**
 * 电子书备份数据段
 */
export interface EBookBackupSection {
  library: EBookBackupItem[];
}

/**
 * 书源备份数据段
 */
export interface SourcesBackupSection {
  manga: MangaSourceBackup[];
  novel: NovelSourceBackup[];
}

/**
 * 设置备份数据段
 */
export interface SettingsBackupSection {
  reader: ReaderSettingsBackup;
  general: GeneralSettingsBackup;
  privacy: PrivacySettingsBackup;
}

/**
 * 历史记录备份数据段
 */
export interface HistoryBackupSection {
  browse: BrowseHistoryBackup[];
  search: SearchHistoryBackup[];
}

/**
 * 阅读器设置备份
 */
export interface ReaderSettingsBackup {
  manga: Record<string, string | number | boolean>;
  novel: Record<string, string | number | boolean>;
}

/**
 * 通用设置备份
 */
export interface GeneralSettingsBackup {
  theme: string;
  language: string;
  // 网络代理设置
  proxyConfig?: ProxyConfigBackup;
  // 字体设置
  fontSettings?: FontSettingsBackup;
}

/**
 * 字体设置备份
 */
export interface FontSettingsBackup {
  appFontType: string;
  appSystemFontId: string;
  appCustomFontId: string;
  appFontSize: number;
  novelFontType: string;
  novelSystemFontId: string;
  novelCustomFontId: string;
  novelFontSize: number;
  novelLineHeight: number;
  ebookFontType: string;
  ebookSystemFontId: string;
  ebookCustomFontId: string;
  ebookFontSize: number;
  ebookLineHeight: number;
  // 自定义字体列表
  customFonts?: CustomFontBackup[];
}

/**
 * 自定义字体备份
 */
export interface CustomFontBackup {
  id: string;
  familyName: string;
  displayName: string;
  fileName: string;  // 字体文件名（不含路径）
}

/**
 * 代理配置备份
 */
export interface ProxyConfigBackup {
  enabled: boolean;
  httpEnabled: boolean;
  httpHost: string;
  httpPort: number;
  httpsEnabled: boolean;
  httpsHost: string;
  httpsPort: number;
}

/**
 * 隐私设置备份
 */
export interface PrivacySettingsBackup {
  sfwMode: boolean;
  privateLibraryEnabled: boolean;
}

/**
 * 漫画阅读进度备份
 */
export interface MangaReadProgressBackup {
  mangaId: string;
  chapterId: string;
  pageIndex: number;
  totalPages: number;
  lastReadTime: number;
}

/**
 * 小说阅读进度备份
 */
export interface NovelReadProgressBackup {
  bookId: string;
  chapterId: string;
  chapterIndex: number;
  position: number;
  progress: number;
  readTime: number;
}

/**
 * 备份元数据
 */
/**
 * 备份项目计数
 */
export interface BackupItemCounts {
  manga: number;
  novel: number;
  ebook: number;
  sources: number;
}

/**
 * WebView配置备份项
 */
export interface WebViewConfigBackup {
  id: number;
  sourceId: number;
  userAgent: string;
  enableJavaScript: boolean;
  enableCookies: boolean;
  customHeaders: string;
  refererPolicy: string;
  imageLoadingStrategy: string;
  timeout: number;
  retryCount: number;
  lastUpdateTime: number;
}

/**
 * 下载任务备份项
 */
export interface DownloadTaskBackup {
  id: number;
  comicId: string;
  chapterId?: string;
  taskType: string;
  status: string;
  progress: number;
  totalSize: number;
  downloadedSize: number;
  createTime: number;
  updateTime: number;
  errorMessage?: string;
}

/**
 * 缓存信息备份项
 */
export interface CacheInfoBackup {
  id: number;
  cacheKey: string;
  cacheType: string;
  cacheSize: number;
  createTime: number;
  lastAccessTime: number;
  expiryTime: number;
}

/**
 * 插件信息备份项
 */
export interface PluginBackup {
  id: number;
  pluginId: string;
  name: string;
  version: string;
  author: string;
  description: string;
  enabled: boolean;
  installTime: number;
  updateTime: number;
}

/**
 * 收藏标签备份项
 */
export interface FavoriteBackup {
  id: number;
  comicId: string;
  userId: string;
  tags: string[];
  note: string;
  rating: number;
  addTime: number;
  updateTime: number;
}

/**
 * 在线漫画信息备份项
 */
export interface OnlineComicBackup {
  id: string;
  sourceId: string;
  externalId: string;
  title: string;
  author: string;
  coverUrl: string;
  description: string;
  status: string;
  lastUpdateTime: number;
  chapters: OnlineChapterBackup[];
}

/**
 * 在线章节备份项
 */
export interface OnlineChapterBackup {
  id: string;
  comicId: string;
  externalId: string;
  title: string;
  chapterNumber: string;
  publishTime: number;
  pages: OnlinePageBackup[];
}

/**
 * 在线页面备份项
 */
export interface OnlinePageBackup {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  width: number;
  height: number;
}

/**
 * WebView配置备份数据段
 */
export interface WebViewBackupSection {
  configs: WebViewConfigBackup[];
}

/**
 * 下载任务备份数据段
 */
export interface DownloadBackupSection {
  tasks: DownloadTaskBackup[];
}

/**
 * 缓存信息备份数据段
 */
export interface CacheBackupSection {
  items: CacheInfoBackup[];
}

/**
 * 插件信息备份数据段
 */
export interface PluginBackupSection {
  plugins: PluginBackup[];
}

/**
 * 收藏标签备份数据段
 */
export interface FavoriteBackupSection {
  favorites: FavoriteBackup[];
}

/**
 * 在线数据备份数据段
 */
export interface OnlineDataBackupSection {
  comics: OnlineComicBackup[];
  readHistory: OnlineReadHistoryBackup[];
}

/**
 * 在线阅读历史备份项
 */
export interface OnlineReadHistoryBackup {
  id: number;
  comicId: string;
  chapterId: string;
  pageIndex: number;
  readTime: number;
}

/**
 * 备份选项 - 用户可选择要备份的内容
 */
export interface BackupOptions {
  // 基础数据（必选）
  includeBasicData: boolean;          // 漫画/小说/电子书库信息
  
  // 详细选项
  includeMangaLibrary: boolean;       // 漫画库
  includeNovelLibrary: boolean;       // 小说库
  includeEBookLibrary: boolean;       // 电子书库
  includeSources: boolean;            // 书源配置
  includeReadProgress: boolean;       // 阅读进度
  includeSettings: boolean;           // 应用设置
  includeHistory: boolean;            // 浏览/搜索历史
  
  // 高级选项
  includeWebViewConfig: boolean;      // WebView配置
  includeDownloadTasks: boolean;      // 下载任务
  includeCacheInfo: boolean;          // 缓存信息
  includePlugins: boolean;            // 插件信息
  includeFavorites: boolean;          // 收藏标签
  includeOnlineData: boolean;         // 在线漫画数据
  includeCloudConfig: boolean;        // 云存储配置（WebDAV）
  
  // 媒体文件选项
  includeCoverImages: boolean;        // 封面图片
  includeChapterImages: boolean;      // 章节图片（缓存）
  includeEBookFiles: boolean;         // 电子书文件
}

/**
 * 默认备份选项
 */
export const DEFAULT_BACKUP_OPTIONS: BackupOptions = {
  includeBasicData: true,
  includeMangaLibrary: true,
  includeNovelLibrary: true,
  includeEBookLibrary: true,
  includeSources: true,
  includeReadProgress: true,
  includeSettings: true,
  includeHistory: true,
  includeWebViewConfig: false,
  includeDownloadTasks: false,
  includeCacheInfo: false,
  includePlugins: false,
  includeFavorites: true,
  includeOnlineData: false,
  includeCloudConfig: true,
  includeCoverImages: true,
  includeChapterImages: false,
  includeEBookFiles: false
};

/**
 * 备份元数据
 */
export interface BackupMetadata {
  version: string;
  appVersion: string;
  timestamp: number;
  deviceInfo?: string;
  itemCounts: BackupItemCounts;
  options: BackupOptions;             // 备份时选择的选项
  fileSize: number;                   // 备份文件大小（字节）
}
