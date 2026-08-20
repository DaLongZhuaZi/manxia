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
  options?: BackupOptions;            // backup options used during creation
  
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

  // 第三方追踪/同步记录
  tracking?: TrackingBackupSection;

  // 统一标注（书签/划线/想法）
  annotations?: AnnotationBackupSection;
  
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
  suwayomi?: SuwayomiConfigBackup;
  komga?: KomgaConfigBackup;
  ftp?: FTPConnectionsBackup;
  preferences?: PreferenceBackupSection;
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
 * Suwayomi服务器配置备份
 */
export interface SuwayomiConfigBackup {
  serverUrl: string;
  username: string;
  password: string;
  useAuth: boolean;
  useBrowsePageAsEntry: boolean;
}

/**
 * Komga 配置备份
 */
export interface KomgaConfigBackup {
  instances: KomgaInstanceConfigBackup[];
  currentInstanceId: string;
  useBrowsePageAsEntry: boolean;
}

/**
 * 单个 Komga 实例配置备份
 */
export interface KomgaInstanceConfigBackup {
  id: string;
  displayName: string;
  serverUrl: string;
  authMode: 'NONE' | 'BASIC' | 'API_KEY';
  username: string;
  password: string;
  apiKey: string;
  defaultLibraryIds: string[];
  chapterTitleTemplate: string;
  enabled: boolean;
}

/**
 * FTP连接配置备份
 */
export interface FTPConnectionsBackup {
  connections: FTPConnectionBackup[];
}

/**
 * 单个FTP连接备份
 */
export interface FTPConnectionBackup {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  password: string;
  useFTPS: boolean;
  passive: boolean;
  timeoutMs: number;
  lastUsedAt?: number;
}

/**
 * 漫画备份项
 */
export interface MangaBackupItem {
  id: string;
  externalId?: string;
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
 * 小说章节备份项
 */
export interface NovelChapterBackup {
  id: string;
  bookId: string;
  url: string;
  title: string;
  chapterIndex: number;
  isVolume: number;
  isVip: number;
  isPay: number;
  isDownloaded: number;
  contentPath: string;
  wordCount: number;
  updateTime: number;
  createTime: number;
}

/**
 * 小说正文缓存备份项
 */
export interface NovelContentCacheBackup {
  id: string;
  chapterId: string;
  content: string;
  wordCount: number;
  createTime: number;
  expireTime: number;
}

/**
 * 小说阅读器设置备份项
 */
export interface NovelReaderSettingsBackup {
  id: string;
  userId: string;
  fontSize: number;
  lineHeight: number;
  letterSpacing: number;
  paragraphSpacing: number;
  fontFamily: string;
  textColor: string;
  backgroundColor: string;
  brightness: number;
  keepScreenOn: number;
  volumeKeyTurn: number;
  clickTurn: number;
  autoScroll: number;
  autoScrollSpeed: number;
  createTime: number;
  updateTime: number;
}

/**
 * 小说替换规则备份项
 */
export interface NovelReplaceRuleBackup {
  id: string;
  name: string;
  pattern: string;
  replacement: string;
  isRegex: number;
  scope: string;
  enabled: number;
  ruleOrder: number;
  sourceIds: string;
  createTime: number;
  updateTime: number;
}

/**
 * TXT目录识别规则备份项
 */
export interface NovelTxtTocRuleBackup {
  id: string;
  name: string;
  rule: string;
  example: string;
  serialNumber: number;
  enabled: number;
  createTime: number;
  updateTime: number;
}

/**
 * 小说词典规则备份项
 */
export interface NovelDictRuleBackup {
  id: string;
  name: string;
  urlRule: string;
  showRule: string;
  enabled: number;
  sortNumber: number;
  createTime: number;
  updateTime: number;
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
  currentChapterIndex?: number;
  currentChapterId?: string;
  domPos?: string;
  isFavorite: boolean;
  isPrivate: boolean;
  isNSFW: boolean;
  totalWordCount: number;
  readingSettings?: EBookReadingSettingsBackup;
}

/**
 * 电子书阅读设置备份项
 */
export interface EBookReadingSettingsBackup {
  bookId?: string;
  userId?: string;
  fontSize?: number;
  fontFamily?: string;
  fontPath?: string;
  fontWeight?: number;
  lineHeight?: number;
  backgroundColor?: string;
  textColor?: string;
  themeBgImage?: string;
  nightMode?: number;
  followSystemTheme?: number;
  pageMargin?: number;
  pageTopMargin?: number;
  pageBottomMargin?: number;
  pageMode?: string;
  brightness?: number;
  autoSave?: number;
  saveInterval?: number;
  letterSpacing?: number;
  paragraphSpacing?: number;
  firstLineIndent?: number;
  textAlignment?: string;
  pageTurnAnimation?: string;
  tapToTurn?: number;
  volumeKeyNavigation?: number;
  keepScreenOn?: number;
  lockDeviceOrientation?: number;
  showPageNumber?: number;
  showProgress?: number;
  showTime?: number;
  showBattery?: number;
  backgroundType?: string;
  backgroundImagePath?: string;
  backgroundImageOpacity?: number;
  imageReaderSettingsJson?: string;
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
 * 统一标注备份项
 */
export interface UnifiedAnnotationBackupItem {
  id: string;
  contentType: 'manga' | 'novel' | 'ebook';
  contentId: string;
  annotationType: string;
  title: string;
  textContent: string;
  quoteText: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  pageIndex: number;
  pageProgress: number;
  startOffset: number;
  endOffset: number;
  anchorJson: string;
  styleJson: string;
  linkedAnnotationId: string;
  createTime: number;
  updateTime: number;
}

/**
 * 统一标注备份数据段
 */
export interface AnnotationBackupSection {
  records: UnifiedAnnotationBackupItem[];
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
  chapters?: NovelChapterBackup[];
  contentCache?: NovelContentCacheBackup[];
  readerSettings?: NovelReaderSettingsBackup[];
  replaceRules?: NovelReplaceRuleBackup[];
  txtTocRules?: NovelTxtTocRuleBackup[];
  dictRules?: NovelDictRuleBackup[];
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
  // 完整的设置表数据（新增）
  allSettings?: SettingItemBackup[];
  preferenceStores?: PreferenceBackupSection;
}

/**
 * 单个设置项备份
 */
export interface SettingItemBackup {
  settingKey: string;
  settingValue: string;
  settingType: string;
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
export interface GenericReaderSettingsBackup {
}

export interface GlobalEBookReaderSettingsBackup {
  global_ebook_lock_device_orientation: boolean;
}

export interface GlobalTextReaderSettingsBackup {
  global_text_lock_device_orientation: boolean;
}

export interface ReaderSettingsBackup {
  manga: GenericReaderSettingsBackup;
  novel: GenericReaderSettingsBackup;
  ebook?: GlobalEBookReaderSettingsBackup;
  text?: GlobalTextReaderSettingsBackup;
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
  protocol: string;
  sharedAuthEnabled: boolean;
  sharedUsername: string;
  sharedPassword: string;
  httpEnabled: boolean;
  httpHost: string;
  httpPort: number;
  httpAuthEnabled: boolean;
  httpUsername: string;
  httpPassword: string;
  httpsEnabled: boolean;
  httpsHost: string;
  httpsPort: number;
  httpsAuthEnabled: boolean;
  httpsUsername: string;
  httpsPassword: string;
  socks5Host: string;
  socks5Port: number;
  socks5AuthEnabled: boolean;
  socks5Username: string;
  socks5Password: string;
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

export type PreferenceEntryValue = string | number | boolean | string[] | number[] | boolean[];

/**
 * Preferences文件备份集合
 */
export interface PreferenceBackupSection {
  stores: PreferenceStoreBackup[];
}

/**
 * 单个Preferences文件备份
 */
export interface PreferenceStoreBackup {
  storeName: string;
  entries: PreferenceEntryBackup[];
}

/**
 * 单个Preferences键值备份
 */
export interface PreferenceEntryBackup {
  key: string;
  value: PreferenceEntryValue;
}

/**
 * 第三方追踪记录备份段
 */
export interface TrackingBackupSection {
  records: TrackRecordBackup[];
}

/**
 * 第三方追踪记录备份项
 */
export interface TrackRecordBackup {
  id: string;
  contentId: string;
  contentType: string;
  trackerId: number;
  remoteId: string;
  remoteTitle: string;
  remoteUrl: string;
  lastChapterRead: number;
  totalChapters: number;
  score: number;
  status: number;
  startedReadingDate: number;
  finishedReadingDate: number;
  lastSyncTime: number;
  syncStatus: string;
  createTime: number;
  updateTime: number;
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
  annotations?: number;
  tracking?: number;
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
  timeout: number;
  retryCount: number;
  referer?: string;
  headers?: string;
  cookies?: string;
  enableCache?: boolean;
  cacheExpireTime?: number;
  enableImages?: boolean;
  enableLocalStorage?: boolean;
  createTime?: number;
  updateTime?: number;
  // legacy compatibility fields
  customHeaders?: string;
  refererPolicy?: string;
  imageLoadingStrategy?: string;
  lastUpdateTime?: number;
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
  downloadSpeed?: number;
  priority?: number;
  createTime: number;
  startTime?: number;
  completeTime?: number;
  // legacy compatibility fields
  updateTime?: number;
  errorMessage?: string;
}

/**
 * 缓存信息备份项
 */
export interface CacheInfoBackup {
  id: number;
  cacheKey: string;
  cacheType: string;
  filePath?: string;
  fileSize?: number;
  expireTime?: number;
  accessCount?: number;
  // legacy compatibility fields
  cacheSize?: number;
  createTime: number;
  lastAccessTime: number;
  expiryTime?: number;
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
  hspPath?: string;
  configSchema?: string;
  isEnabled?: boolean;
  // legacy compatibility fields
  enabled?: boolean;
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
  folderName?: string;
  addTime: number;
  lastReadChapterId?: string;
  lastReadPageNumber?: number;
  lastReadTime?: number;
  readProgress?: number;
  // legacy compatibility fields
  tags?: string[];
  note?: string;
  rating?: number;
  updateTime?: number;
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
  tags?: string;
  rating?: number;
  lastUpdateTime: number;
  addTime?: number;
  createTime?: number;
  updateTime?: number;
  sourceName?: string;
  sourcePkg?: string;
  isNSFW?: boolean;
  isPrivate?: boolean;
  chapters?: OnlineChapterBackup[];
  // legacy compatibility fields
  status?: string;
}

/**
 * 在线章节备份项
 */
export interface OnlineChapterBackup {
  id: string;
  comicId: string;
  externalId: string;
  title: string;
  chapterNumber: number | string;
  url?: string;
  pageCount?: number;
  publishTime: number;
  addTime?: number;
  createTime?: number;
  updateTime?: number;
  isDownloaded?: boolean;
  downloadPath?: string;
  index?: number;
  pages?: OnlinePageBackup[];
}

/**
 * 在线页面备份项
 */
export interface OnlinePageBackup {
  id: string;
  chapterId: string;
  pageNumber: number;
  imageUrl: string;
  requestHeaders?: string;
  localPath?: string;
  width: number;
  height: number;
  fileSize?: number;
  isDownloaded?: boolean;
  createTime?: number;
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
  userId?: string;
  pageNumber?: number;
  readTime: number;
  duration?: number;
  createTime?: number;
  // legacy compatibility fields
  pageIndex?: number;
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
  includeAnnotations: boolean;        // 统一标注（书签/划线/想法）
  
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
  includeAnnotations: true,
  includeWebViewConfig: false,
  includeDownloadTasks: false,
  includeCacheInfo: false,
  includePlugins: false,
  includeFavorites: true,
  includeOnlineData: false,
  includeCloudConfig: false,
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
