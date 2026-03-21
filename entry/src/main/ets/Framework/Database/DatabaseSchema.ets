// 文件路径: src/main/ets/Framework/Database/DatabaseSchema.ets
/**
 * 漫画软件数据库架构定义
 * 基于HarmonyOS relationalStore实现
 */

// 数据库配置
export interface DatabaseConfig {
  name: string;
  version: number;
  encrypt: boolean;
}

// 图源信息表
export interface ComicSourceTable {
  id: string;                    // 主键，使用UUID
  name: string;                  // 图源名称
  baseUrl: string;              // 基础URL
  version: string;              // 版本号
  description: string;          // 描述
  language: string;             // 语言
  isEnabled: boolean;           // 是否启用
  priority: number;             // 优先级
  lastUpdateTime: number;       // 最后更新时间
  configJson: string;           // 配置JSON
  createTime: number;           // 创建时间
  preloadCurrentChapter: boolean; // 是否预加载当前章节
  preloadCurrentPages: number;    // 当前章节预加载页数（0=不预加载，-1=全部）
  preloadNextChapter: boolean;    // 是否预加载下一章节
  preloadNextPages: number;       // 下一章节预加载页数（0=不预加载，-1=全部）
  downloadWhileReading: boolean;  // 是否开启边看边下载
  maxCacheSize: number;           // 最大缓存大小（字节）
  isNSFW: boolean;               // 是否为成人内容（NSFW）
}

// 漫画信息表
export interface ComicInfoTable {
  id: string;                   // 主键（内部ID），使用UUID，用于本地数据库查询和关联
  sourceId: string;             // 图源ID，外键，关联到comic_source表
  externalId: string;           // 外部ID（图源漫画ID），用于API调用，从图源获取的原始漫画ID
  title: string;                // 漫画标题
  author: string;               // 作者
  description: string;          // 描述
  coverUrl: string;             // 封面URL
  coverLocalPath: string;       // 封面本地路径
  status: string;               // 状态：连载中、已完结、暂停等
  tags: string;                 // 标签，JSON数组字符串
  categories: string;           // 分类，JSON数组字符串
  rating: number;               // 评分
  viewCount: number;            // 浏览次数
  favoriteCount: number;        // 收藏次数
  lastChapterTitle: string;     // 最新章节标题
  lastChapterTime: number;      // 最新章节时间
  isCompleted: boolean;         // 是否完结
  createTime: number;           // 创建时间
  updateTime: number;           // 更新时间
  webUrl: string;               // 网页URL，用户可在浏览器中打开的漫画页面地址
  apiUrl: string;               // API请求地址，用于刷新时直接请求漫画详情
  isNSFW: boolean;              // 是否为成人内容（NSFW）
}

// 章节信息表
export interface ChapterTable {
  id: string;                   // 主键（内部ID），使用UUID，用于本地数据库查询和关联
  comicId: string;              // 漫画ID（内部ID），外键，关联到comic_info表的id字段
  externalId: string;           // 外部ID（图源章节ID），用于API调用，从图源获取的原始章节ID
  title: string;                // 章节标题
  chapterNumber: number;        // 章节序号
  url: string;                  // 章节URL（可选，某些图源可能提供）
  pageCount: number;            // 页数
  isDownloaded: boolean;        // 是否已下载
  downloadPath: string;         // 下载路径
  fileSize: number;             // 文件大小（字节）
  publishTime: number;          // 发布时间
  createTime: number;           // 创建时间
  updateTime: number;           // 更新时间
}

// 页面信息表
export interface PageTable {
  id: string;                   // 主键（内部ID），使用UUID
  chapterId: string;            // 章节ID（内部ID），外键，关联到chapter表的id字段
  pageNumber: number;           // 页码（从0开始）
  imageUrl: string;             // 图片URL（从图源获取的原始URL）
  localPath: string;            // 本地路径（下载后的本地文件路径）
  width: number;                // 图片宽度
  height: number;               // 图片高度
  fileSize: number;             // 文件大小（字节）
  isDownloaded: boolean;        // 是否已下载
  createTime: number;           // 创建时间
}

// 用户收藏表
export interface FavoriteTable {
  id: string;                   // 主键，使用UUID
  comicId: string;              // 漫画ID，外键
  userId: string;               // 用户ID
  folderName: string;           // 收藏夹名称
  addTime: number;              // 添加时间
  lastReadChapterId: string;    // 最后阅读章节ID
  lastReadPageNumber: number;   // 最后阅读页码
  lastReadTime: number;         // 最后阅读时间
  readProgress: number;         // 阅读进度百分比
}

// 阅读历史表
export interface ReadHistoryTable {
  id: string;                   // 主键，使用UUID
  comicId: string;              // 漫画ID，外键
  chapterId: string;            // 章节ID，外键
  userId: string;               // 用户ID（预留）
  pageNumber: number;           // 阅读到的页码
  readTime: number;             // 阅读时间
  readDuration: number;         // 阅读时长（秒）
}

// 下载任务表
export interface DownloadTaskTable {
  id: number;                   // 主键，自增
  comicId: number;              // 漫画ID，外键
  chapterId: number;            // 章节ID，外键
  taskType: string;             // 任务类型：chapter、comic
  status: string;               // 状态：pending、downloading、completed、failed、paused
  progress: number;             // 进度百分比
  downloadedSize: number;       // 已下载大小
  totalSize: number;            // 总大小
  downloadSpeed: number;        // 下载速度（字节/秒）
  errorMessage: string;         // 错误信息
  priority: number;             // 优先级
  createTime: number;           // 创建时间
  startTime: number;            // 开始时间
  completeTime: number;         // 完成时间
}

// 缓存信息表
export interface CacheInfoTable {
  id: number;                   // 主键，自增
  cacheKey: string;             // 缓存键
  cacheType: string;            // 缓存类型：image、data、config
  filePath: string;             // 文件路径
  fileSize: number;             // 文件大小
  expireTime: number;           // 过期时间
  accessCount: number;          // 访问次数
  lastAccessTime: number;       // 最后访问时间
  createTime: number;           // 创建时间
}

// 用户设置表
export interface UserSettingsTable {
  id: number;                   // 主键，自增
  userId: string;               // 用户ID
  settingKey: string;           // 设置键
  settingValue: string;         // 设置值
  settingType: string;          // 设置类型：string、number、boolean、json
  description: string;          // 描述
  createTime: number;           // 创建时间
  updateTime: number;           // 更新时间
}

// 图源插件表
export interface PluginTable {
  id: number;                   // 主键，自增
  pluginId: string;             // 插件ID
  name: string;                 // 插件名称
  version: string;              // 版本号
  description: string;          // 描述
  author: string;               // 作者
  hspPath: string;              // HSP文件路径
  configSchema: string;         // 配置架构JSON
  isEnabled: boolean;           // 是否启用
  installTime: number;          // 安装时间
  updateTime: number;           // 更新时间
}

// WebView源配置表
export interface WebViewSourceConfigTable {
  id: number;                   // 主键，自增
  sourceId: number;             // 图源ID，外键
  userAgent: string;            // 用户代理
  referer: string;              // 引用页
  headers: string;              // 请求头JSON
  cookies: string;              // Cookie JSON
  timeout: number;              // 超时时间（毫秒）
  retryCount: number;           // 重试次数
  enableCache: boolean;         // 是否启用缓存
  cacheExpireTime: number;      // 缓存过期时间（秒）
  enableJavaScript: boolean;    // 是否启用JavaScript
  enableImages: boolean;        // 是否启用图片加载
  enableCookies: boolean;       // 是否启用Cookie
  enableLocalStorage: boolean;  // 是否启用本地存储
  createTime: number;           // 创建时间
  updateTime: number;           // 更新时间
}

// WebView图片元数据表
export interface WebViewImageMetadataTable {
  id: number;                   // 主键，自增
  sourceId: number;             // 图源ID，外键
  imageUrl: string;             // 图片URL
  originalUrl: string;          // 原始URL
  refererUrl: string;           // 引用页URL
  userAgent: string;            // 用户代理
  headers: string;              // 请求头JSON
  contentType: string;          // 内容类型
  contentLength: number;        // 内容长度
  width: number;                // 图片宽度
  height: number;               // 图片高度
  fileSize: number;             // 文件大小
  cacheKey: string;             // 缓存键
  isValid: boolean;             // 是否有效
  errorMessage: string;         // 错误信息
  loadTime: number;             // 加载时间（毫秒）
  createTime: number;           // 创建时间
  updateTime: number;           // 更新时间
}

// WebView请求统计表
export interface WebViewRequestStatsTable {
  id: number;                   // 主键，自增
  sourceId: number;             // 图源ID，外键
  requestType: string;          // 请求类型：image、page、api
  requestUrl: string;           // 请求URL
  method: string;               // 请求方法
  statusCode: number;           // 状态码
  responseTime: number;         // 响应时间（毫秒）
  requestSize: number;          // 请求大小
  responseSize: number;         // 响应大小
  isSuccess: boolean;           // 是否成功
  errorMessage: string;         // 错误信息
  userAgent: string;            // 用户代理
  referer: string;              // 引用页
  requestTime: number;          // 请求时间
  createTime: number;           // 创建时间
}

// 跟踪记录表（用于与第三方服务同步阅读进度）
export interface TrackRecordTable {
  id: string;                     // 主键，使用UUID
  contentId: string;              // 内容ID（漫画/电子书/小说的本地ID）
  contentType: string;            // 内容类型：manga, ebook, novel
  trackerId: number;              // 跟踪服务ID：1=MAL, 2=AniList, 3=Kitsu, 4=MangaUpdates, 5=Bangumi, 6=Suwayomi
  remoteId: string;               // 远程服务上的内容ID
  remoteTitle: string;            // 远程服务上的标题
  remoteUrl: string;              // 远程服务上的URL
  lastChapterRead: number;        // 最后阅读章节号
  totalChapters: number;          // 总章节数
  score: number;                  // 评分（0-10或0-100，取决于服务）
  status: number;                 // 阅读状态：0=未知, 1=阅读中, 2=已完成, 3=暂停, 4=弃坑, 5=计划阅读
  startedReadingDate: number;     // 开始阅读日期（时间戳）
  finishedReadingDate: number;    // 完成阅读日期（时间戳）
  lastSyncTime: number;           // 最后同步时间
  syncStatus: string;             // 同步状态：synced, pending, failed
  createTime: number;             // 创建时间
  updateTime: number;             // 更新时间
}

// SQL语句集合接口
export interface CreateTableSQLCollection {
  COMIC_SOURCE: string;
  TEMP_MANGA_INFO: string;
  COMIC_INFO: string;
  CHAPTER: string;
  CHAPTER_UNIQUE_INDEX: string;
  PAGE: string;
  PAGE_UNIQUE_INDEX: string;
  FAVORITE: string;
  READ_HISTORY: string;
  DOWNLOAD_TASK: string;
  CACHE_INFO: string;
  USER_SETTINGS: string;
  PLUGIN: string;
  WEBVIEW_SOURCE_CONFIG: string;
  WEBVIEW_IMAGE_METADATA: string;
  WEBVIEW_REQUEST_STATS: string;
  EBOOK_INFO: string;
  EBOOK_CHAPTER: string;
  EBOOK_READING_PROGRESS: string;
  EBOOK_READING_SETTINGS: string;
  ONLINE_COMIC_INFO?: string;
  ONLINE_COMIC_UNIQUE_INDEX?: string;
  ONLINE_CHAPTER?: string;
  ONLINE_CHAPTER_UNIQUE_INDEX?: string;
  ONLINE_PAGE?: string;
  ONLINE_READ_HISTORY?: string;
  TRACK_RECORD?: string;
  TRACK_RECORD_UNIQUE_INDEX?: string;
  UNIFIED_ANNOTATION?: string;
}

// 数据库表创建SQL语句
export const CREATE_TABLE_SQL: CreateTableSQLCollection = {
  // 图源信息表
  COMIC_SOURCE: `
    CREATE TABLE IF NOT EXISTS comic_source (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pkg TEXT,
      name TEXT UNIQUE NOT NULL,
      baseUrl TEXT NOT NULL,
      version TEXT NOT NULL,
      description TEXT,
      language TEXT DEFAULT 'zh-CN',
      type TEXT DEFAULT 'manga',
      isEnabled INTEGER DEFAULT 1,
      priority INTEGER DEFAULT 0,
      lastUpdateTime INTEGER DEFAULT 0,
      configJson TEXT,
      cookies TEXT DEFAULT '',
      tabs_config TEXT,
      createTime INTEGER NOT NULL,
      preloadCurrentChapter INTEGER DEFAULT 1,
      preloadCurrentPages INTEGER DEFAULT 10,
      preloadNextChapter INTEGER DEFAULT 1,
      preloadNextPages INTEGER DEFAULT -1,
      downloadWhileReading INTEGER DEFAULT 1,
      maxCacheSize INTEGER DEFAULT 1073741824,
      requireProxy INTEGER DEFAULT 0,
      isNSFW INTEGER DEFAULT 0
    )
  `,

  // 临时漫画信息表（用于缓存封面）
  TEMP_MANGA_INFO: `
    CREATE TABLE IF NOT EXISTS temp_manga_info (
      id TEXT PRIMARY KEY,
      sourceId INTEGER NOT NULL,
      externalId TEXT NOT NULL,
      title TEXT NOT NULL,
      coverUrl TEXT NOT NULL,
      localCoverPath TEXT,
      createTime INTEGER NOT NULL,
      lastAccessTime INTEGER NOT NULL,
      UNIQUE(sourceId, externalId)
    )
  `,

  // 漫画信息表
  COMIC_INFO: `
    CREATE TABLE IF NOT EXISTS comic_info (
      id TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      externalId TEXT NOT NULL,
      title TEXT NOT NULL,
      author TEXT,
      description TEXT,
      coverUrl TEXT,
      coverLocalPath TEXT,
      status TEXT DEFAULT 'unknown',
      tags TEXT,
      categories TEXT,
      rating REAL DEFAULT 0.0,
      viewCount INTEGER DEFAULT 0,
      favoriteCount INTEGER DEFAULT 0,
      lastChapterTitle TEXT,
      lastChapterTime INTEGER DEFAULT 0,
      isCompleted INTEGER DEFAULT 0,
      chapterCount INTEGER DEFAULT 0,
      lastUpdateTime INTEGER DEFAULT 0,
      addTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      webUrl TEXT,
      apiUrl TEXT,
      contentType TEXT DEFAULT 'manga',
      isNSFW INTEGER DEFAULT 0,
      isPrivate INTEGER DEFAULT 0
    )
  `,

  // 章节信息表
  CHAPTER: `
    CREATE TABLE IF NOT EXISTS chapter (
      id TEXT PRIMARY KEY,
      comicId TEXT NOT NULL,
      externalId TEXT NOT NULL,
      title TEXT NOT NULL,
      chapterNumber INTEGER NOT NULL,
      url TEXT,
      pageCount INTEGER DEFAULT 0,
      isDownloaded INTEGER DEFAULT 0,
      downloadPath TEXT,
      fileSize INTEGER DEFAULT 0,
      publishTime INTEGER DEFAULT 0,
      addTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (comicId) REFERENCES comic_info (id),
      UNIQUE(comicId, externalId)
    )
  `,

  // 章节唯一性索引：防止同一漫画下重复添加相同的外部章节ID
  CHAPTER_UNIQUE_INDEX: `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_chapter_unique 
    ON chapter(comicId, externalId)
  `,

  // 页面信息表
  PAGE: `
    CREATE TABLE IF NOT EXISTS page (
      id TEXT PRIMARY KEY,
      chapterId TEXT NOT NULL,
      pageNumber INTEGER NOT NULL,
      imageUrl TEXT NOT NULL,
      localPath TEXT,
      width INTEGER DEFAULT 0,
      height INTEGER DEFAULT 0,
      fileSize INTEGER DEFAULT 0,
      isDownloaded INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (chapterId) REFERENCES chapter (id),
      UNIQUE(chapterId, pageNumber)
    )
  `,

  // 页面唯一性索引：防止同一章节下重复添加相同页码
  PAGE_UNIQUE_INDEX: `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_page_unique 
    ON page(chapterId, pageNumber)
  `,

  ONLINE_COMIC_INFO: `
    CREATE TABLE IF NOT EXISTS online_comic_info (
      id TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      externalId TEXT NOT NULL,
      title TEXT NOT NULL,
      author TEXT,
      description TEXT,
      coverUrl TEXT,
      tags TEXT,
      rating REAL DEFAULT 0.0,
      lastUpdateTime INTEGER DEFAULT 0,
      addTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      sourceName TEXT DEFAULT '',
      sourcePkg TEXT DEFAULT '',
      isNSFW INTEGER DEFAULT 0,
      isPrivate INTEGER DEFAULT 0,
      UNIQUE(sourceId, externalId)
    )
  `,

  // 在线漫画唯一性索引：防止同一图源下重复添加相同的外部漫画ID
  ONLINE_COMIC_UNIQUE_INDEX: `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_online_comic_unique 
    ON online_comic_info(sourceId, externalId)
  `,

  ONLINE_CHAPTER: `
    CREATE TABLE IF NOT EXISTS online_chapter (
      id TEXT PRIMARY KEY,
      comicId TEXT NOT NULL,
      externalId TEXT NOT NULL,
      title TEXT NOT NULL,
      chapterNumber INTEGER DEFAULT 0,
      url TEXT,
      pageCount INTEGER DEFAULT 0,
      publishTime INTEGER DEFAULT 0,
      addTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      isDownloaded INTEGER DEFAULT 0,
      downloadPath TEXT,
      \`index\` INTEGER DEFAULT 0,
      FOREIGN KEY (comicId) REFERENCES online_comic_info (id),
      UNIQUE(comicId, externalId)
    )
  `,

  // 在线章节唯一性索引：防止同一在线漫画下重复添加相同的外部章节ID
  ONLINE_CHAPTER_UNIQUE_INDEX: `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_online_chapter_unique 
    ON online_chapter(comicId, externalId)
  `,

  ONLINE_PAGE: `
    CREATE TABLE IF NOT EXISTS online_page (
      id TEXT PRIMARY KEY,
      chapterId TEXT NOT NULL,
      pageNumber INTEGER NOT NULL,
      imageUrl TEXT NOT NULL,
      localPath TEXT,
      width INTEGER DEFAULT 0,
      height INTEGER DEFAULT 0,
      fileSize INTEGER DEFAULT 0,
      isDownloaded INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (chapterId) REFERENCES online_chapter (id)
    )
  `,

  ONLINE_READ_HISTORY: `
    CREATE TABLE IF NOT EXISTS online_read_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      comicId TEXT NOT NULL,
      chapterId TEXT NOT NULL,
      userId TEXT NOT NULL,
      pageNumber INTEGER NOT NULL,
      readTime INTEGER NOT NULL,
      duration INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (comicId) REFERENCES online_comic_info (id),
      FOREIGN KEY (chapterId) REFERENCES online_chapter (id)
    )
  `,

  // 用户收藏表
  FAVORITE: `
    CREATE TABLE IF NOT EXISTS favorite (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      comicId TEXT NOT NULL,
      userId TEXT NOT NULL,
      folderName TEXT DEFAULT 'default',
      addTime INTEGER NOT NULL,
      lastReadChapterId TEXT DEFAULT '',
      lastReadPageNumber INTEGER DEFAULT 0,
      lastReadTime INTEGER DEFAULT 0,
      readProgress REAL DEFAULT 0.0,
      FOREIGN KEY (comicId) REFERENCES comic_info (id),
      UNIQUE (comicId, userId)
    )
  `,

  // 阅读历史表
  READ_HISTORY: `
    CREATE TABLE IF NOT EXISTS read_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      comicId TEXT NOT NULL,
      chapterId TEXT NOT NULL,
      userId TEXT NOT NULL,
      pageNumber INTEGER NOT NULL,
      readTime INTEGER NOT NULL,
      duration INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (comicId) REFERENCES comic_info (id),
      FOREIGN KEY (chapterId) REFERENCES chapter (id)
    )
  `,

  // 下载任务表
  DOWNLOAD_TASK: `
    CREATE TABLE IF NOT EXISTS download_task (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      comicId TEXT NOT NULL,
      chapterId TEXT,
      taskType TEXT NOT NULL,
      status TEXT DEFAULT 'pending',
      progress REAL DEFAULT 0.0,
      downloadedSize INTEGER DEFAULT 0,
      totalSize INTEGER DEFAULT 0,
      downloadSpeed REAL DEFAULT 0.0,
      errorMessage TEXT,
      priority INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      startTime INTEGER DEFAULT 0,
      completeTime INTEGER DEFAULT 0,
      FOREIGN KEY (comicId) REFERENCES comic_info (id),
      FOREIGN KEY (chapterId) REFERENCES chapter (id)
    )
  `,

  // 缓存信息表
  CACHE_INFO: `
    CREATE TABLE IF NOT EXISTS cache_info (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cacheKey TEXT NOT NULL UNIQUE,
      cacheType TEXT NOT NULL,
      filePath TEXT NOT NULL,
      fileSize INTEGER DEFAULT 0,
      expireTime INTEGER DEFAULT 0,
      accessCount INTEGER DEFAULT 0,
      lastAccessTime INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL
    )
  `,

  // 用户设置表
  USER_SETTINGS: `
    CREATE TABLE IF NOT EXISTS user_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      userId TEXT NOT NULL,
      settingKey TEXT NOT NULL,
      settingValue TEXT,
      settingType TEXT DEFAULT 'string',
      description TEXT,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      UNIQUE (userId, settingKey)
    )
  `,

  // 图源插件表
  PLUGIN: `
    CREATE TABLE IF NOT EXISTS plugin (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      pluginId TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      version TEXT NOT NULL,
      description TEXT,
      author TEXT,
      hspPath TEXT,
      configSchema TEXT,
      isEnabled INTEGER DEFAULT 1,
      installTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  // WebView源配置表
  WEBVIEW_SOURCE_CONFIG: `
    CREATE TABLE IF NOT EXISTS webview_source_config (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sourceId INTEGER NOT NULL,
      userAgent TEXT DEFAULT '',
      referer TEXT DEFAULT '',
      headers TEXT DEFAULT '{}',
      cookies TEXT DEFAULT '{}',
      timeout INTEGER DEFAULT 30000,
      retryCount INTEGER DEFAULT 3,
      enableCache INTEGER DEFAULT 1,
      cacheExpireTime INTEGER DEFAULT 3600,
      enableJavaScript INTEGER DEFAULT 1,
      enableImages INTEGER DEFAULT 1,
      enableCookies INTEGER DEFAULT 1,
      enableLocalStorage INTEGER DEFAULT 1,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (sourceId) REFERENCES comic_source (id),
      UNIQUE (sourceId)
    )
  `,

  // WebView图片元数据表
  WEBVIEW_IMAGE_METADATA: `
    CREATE TABLE IF NOT EXISTS webview_image_metadata (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sourceId INTEGER NOT NULL,
      imageUrl TEXT NOT NULL,
      originalUrl TEXT DEFAULT '',
      refererUrl TEXT DEFAULT '',
      userAgent TEXT DEFAULT '',
      headers TEXT DEFAULT '{}',
      contentType TEXT DEFAULT '',
      contentLength INTEGER DEFAULT 0,
      width INTEGER DEFAULT 0,
      height INTEGER DEFAULT 0,
      fileSize INTEGER DEFAULT 0,
      cacheKey TEXT DEFAULT '',
      isValid INTEGER DEFAULT 1,
      errorMessage TEXT DEFAULT '',
      loadTime INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (sourceId) REFERENCES comic_source (id),
      UNIQUE (sourceId, imageUrl)
    )
  `,

  // WebView请求统计表
  WEBVIEW_REQUEST_STATS: `
    CREATE TABLE IF NOT EXISTS webview_request_stats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sourceId INTEGER NOT NULL,
      requestType TEXT NOT NULL,
      requestUrl TEXT NOT NULL,
      method TEXT DEFAULT 'GET',
      statusCode INTEGER DEFAULT 0,
      responseTime INTEGER DEFAULT 0,
      requestSize INTEGER DEFAULT 0,
      responseSize INTEGER DEFAULT 0,
      isSuccess INTEGER DEFAULT 0,
      errorMessage TEXT DEFAULT '',
      userAgent TEXT DEFAULT '',
      referer TEXT DEFAULT '',
      requestTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (sourceId) REFERENCES comic_source (id)
    )
  `,

  // 电子书信息表
  EBOOK_INFO: `
    CREATE TABLE IF NOT EXISTS ebook_info (
      id TEXT PRIMARY KEY,
      format TEXT NOT NULL,
      filePath TEXT NOT NULL,
      fileSize INTEGER DEFAULT 0,
      title TEXT NOT NULL,
      author TEXT DEFAULT '',
      publisher TEXT DEFAULT '',
      publishDate TEXT DEFAULT '',
      isbn TEXT DEFAULT '',
      language TEXT DEFAULT 'zh-CN',
      description TEXT DEFAULT '',
      coverImagePath TEXT DEFAULT '',
      tags TEXT DEFAULT '[]',
      rating REAL DEFAULT 0.0,
      status TEXT DEFAULT 'UNREAD',
      isFavorite INTEGER DEFAULT 0,
      totalWordCount INTEGER DEFAULT 0,
      addTime INTEGER NOT NULL,
      lastUpdateTime INTEGER NOT NULL,
      isPrivate INTEGER DEFAULT 0,
      isNSFW INTEGER DEFAULT 0
    )
  `,

  // 电子书章节表
  EBOOK_CHAPTER: `
    CREATE TABLE IF NOT EXISTS ebook_chapter (
      id TEXT PRIMARY KEY,
      bookId TEXT NOT NULL,
      chapterNumber INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      startPosition INTEGER DEFAULT 0,
      endPosition INTEGER DEFAULT 0,
      wordCount INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (bookId) REFERENCES ebook_info (id)
    )
  `,

  // 电子书阅读进度表
  EBOOK_READING_PROGRESS: `
    CREATE TABLE IF NOT EXISTS ebook_reading_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId TEXT NOT NULL,
      userId TEXT NOT NULL,
      currentChapterId TEXT NOT NULL,
      currentChapterIndex INTEGER DEFAULT 0,
      currentPosition INTEGER DEFAULT 0,
      domPos TEXT DEFAULT '',
      progress REAL DEFAULT 0.0,
      lastReadTime INTEGER DEFAULT 0,
      totalReadingTime INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (bookId) REFERENCES ebook_info (id),
      UNIQUE (bookId, userId)
    )
  `,

  // 电子书阅读设置表
  EBOOK_READING_SETTINGS: `
    CREATE TABLE IF NOT EXISTS ebook_reading_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId TEXT NOT NULL,
      userId TEXT NOT NULL,
      fontSize INTEGER DEFAULT 18,
      fontFamily TEXT DEFAULT 'HarmonyOS Sans',
      fontPath TEXT DEFAULT '',
      fontWeight INTEGER DEFAULT 400,
      lineHeight REAL DEFAULT 1.5,
      backgroundColor TEXT DEFAULT '#FFFFFF',
      textColor TEXT DEFAULT '#000000',
      themeBgImage TEXT DEFAULT '',
      nightMode INTEGER DEFAULT 0,
      followSystemTheme INTEGER DEFAULT 1,
      pageMargin INTEGER DEFAULT 16,
      pageMode TEXT DEFAULT '0',
      brightness INTEGER DEFAULT 100,
      autoSave INTEGER DEFAULT 1,
      saveInterval INTEGER DEFAULT 30,
      letterSpacing REAL DEFAULT 0,
      paragraphSpacing INTEGER DEFAULT 8,
      firstLineIndent INTEGER DEFAULT 2,
      textAlignment TEXT DEFAULT 'JUSTIFY',
      pageTurnAnimation TEXT DEFAULT 'SLIDE',
      tapToTurn INTEGER DEFAULT 1,
      volumeKeyNavigation INTEGER DEFAULT 1,
      keepScreenOn INTEGER DEFAULT 0,
      showPageNumber INTEGER DEFAULT 1,
      showProgress INTEGER DEFAULT 0,
      showTime INTEGER DEFAULT 1,
      showBattery INTEGER DEFAULT 0,
      backgroundType TEXT DEFAULT 'COLOR',
      backgroundImagePath TEXT DEFAULT '',
      backgroundImageOpacity REAL DEFAULT 0.3,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (bookId) REFERENCES ebook_info (id),
      UNIQUE (bookId, userId)
    )
  `,

  // 跟踪记录表（用于与第三方服务同步阅读进度）
  TRACK_RECORD: `
    CREATE TABLE IF NOT EXISTS track_record (
      id TEXT PRIMARY KEY,
      contentId TEXT NOT NULL,
      contentType TEXT NOT NULL DEFAULT 'manga',
      trackerId INTEGER NOT NULL,
      remoteId TEXT NOT NULL,
      remoteTitle TEXT,
      remoteUrl TEXT,
      lastChapterRead REAL DEFAULT 0,
      totalChapters INTEGER DEFAULT 0,
      score REAL DEFAULT 0,
      status INTEGER DEFAULT 0,
      startedReadingDate INTEGER DEFAULT 0,
      finishedReadingDate INTEGER DEFAULT 0,
      lastSyncTime INTEGER DEFAULT 0,
      syncStatus TEXT DEFAULT 'pending',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  // 跟踪记录唯一索引
  TRACK_RECORD_UNIQUE_INDEX: `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_track_record_unique 
    ON track_record (contentId, trackerId)
  `,

  UNIFIED_ANNOTATION: `
    CREATE TABLE IF NOT EXISTS unified_annotation (
      id TEXT PRIMARY KEY,
      contentType TEXT NOT NULL,
      contentId TEXT NOT NULL,
      annotationType TEXT NOT NULL,
      title TEXT DEFAULT '',
      textContent TEXT DEFAULT '',
      quoteText TEXT DEFAULT '',
      chapterId TEXT DEFAULT '',
      chapterTitle TEXT DEFAULT '',
      chapterIndex INTEGER DEFAULT -1,
      pageIndex INTEGER DEFAULT -1,
      pageProgress REAL DEFAULT -1,
      startOffset INTEGER DEFAULT -1,
      endOffset INTEGER DEFAULT -1,
      anchorJson TEXT DEFAULT '',
      styleJson TEXT DEFAULT '',
      linkedAnnotationId TEXT DEFAULT '',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      isDeleted INTEGER DEFAULT 0
    )
  `
};

// 创建索引SQL语句
export const CREATE_INDEX_SQL: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_comic_info_source ON comic_info (sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_comic_info_external ON comic_info (sourceId, externalId)',
  'CREATE INDEX IF NOT EXISTS idx_comic_info_title ON comic_info (title)',
  'CREATE INDEX IF NOT EXISTS idx_chapter_comic ON chapter (comicId)',
  'CREATE INDEX IF NOT EXISTS idx_chapter_external ON chapter (comicId, externalId)',
  'CREATE INDEX IF NOT EXISTS idx_chapter_number ON chapter (comicId, chapterNumber)',
  'CREATE INDEX IF NOT EXISTS idx_page_chapter ON page (chapterId)',
  'CREATE INDEX IF NOT EXISTS idx_page_number ON page (chapterId, pageNumber)',
  'CREATE INDEX IF NOT EXISTS idx_favorite_user ON favorite (userId)',
  'CREATE INDEX IF NOT EXISTS idx_favorite_comic ON favorite (comicId)',
  'CREATE INDEX IF NOT EXISTS idx_history_user ON read_history (userId)',
  'CREATE INDEX IF NOT EXISTS idx_history_comic ON read_history (comicId)',
  'CREATE INDEX IF NOT EXISTS idx_history_time ON read_history (readTime)',
  'CREATE INDEX IF NOT EXISTS idx_download_status ON download_task (status)',
  'CREATE INDEX IF NOT EXISTS idx_cache_type ON cache_info (cacheType)',
  'CREATE INDEX IF NOT EXISTS idx_cache_expire ON cache_info (expireTime)',
  'CREATE INDEX IF NOT EXISTS idx_settings_user ON user_settings (userId)',
  'CREATE INDEX IF NOT EXISTS idx_webview_config_source ON webview_source_config (sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_webview_metadata_source ON webview_image_metadata (sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_webview_metadata_url ON webview_image_metadata (imageUrl)',
  'CREATE INDEX IF NOT EXISTS idx_webview_stats_source ON webview_request_stats (sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_webview_stats_type ON webview_request_stats (requestType)',
  'CREATE INDEX IF NOT EXISTS idx_webview_stats_time ON webview_request_stats (requestTime)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_format ON ebook_info (format)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_title ON ebook_info (title)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_author ON ebook_info (author)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_status ON ebook_info (status)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_chapter_book ON ebook_chapter (bookId)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_chapter_number ON ebook_chapter (bookId, chapterNumber)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_progress_book ON ebook_reading_progress (bookId)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_progress_user ON ebook_reading_progress (userId)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_settings_book ON ebook_reading_settings (bookId)',
  'CREATE INDEX IF NOT EXISTS idx_ebook_settings_user ON ebook_reading_settings (userId)'
  ,
  'CREATE INDEX IF NOT EXISTS idx_online_comic_source ON online_comic_info (sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_online_comic_external ON online_comic_info (sourceId, externalId)',
  'CREATE INDEX IF NOT EXISTS idx_online_chapter_comic ON online_chapter (comicId)',
  'CREATE INDEX IF NOT EXISTS idx_online_chapter_external ON online_chapter (comicId, externalId)',
  'CREATE INDEX IF NOT EXISTS idx_online_page_chapter ON online_page (chapterId)',
  'CREATE INDEX IF NOT EXISTS idx_online_page_number ON online_page (chapterId, pageNumber)',
  'CREATE INDEX IF NOT EXISTS idx_online_page_image_url ON online_page (imageUrl)'
  ,
  'CREATE INDEX IF NOT EXISTS idx_online_read_user ON online_read_history (userId)',
  'CREATE INDEX IF NOT EXISTS idx_online_read_comic ON online_read_history (comicId)',
  'CREATE INDEX IF NOT EXISTS idx_online_read_time ON online_read_history (readTime)',
  // 跟踪记录表索引
  'CREATE INDEX IF NOT EXISTS idx_track_record_content ON track_record (contentId)',
  'CREATE INDEX IF NOT EXISTS idx_track_record_tracker ON track_record (trackerId)',
  'CREATE INDEX IF NOT EXISTS idx_track_record_sync ON track_record (syncStatus)',
  'CREATE INDEX IF NOT EXISTS idx_track_record_update ON track_record (updateTime)',
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_content ON unified_annotation (contentType, contentId, createTime DESC)',
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_type ON unified_annotation (annotationType, createTime DESC)',
  'CREATE INDEX IF NOT EXISTS idx_unified_annotation_linked ON unified_annotation (linkedAnnotationId)'
];

// 数据库版本升级脚本
// 注意：从版本5开始，externalId已经是必需字段，包含在CREATE TABLE语句中
export const MIGRATION_SCRIPTS: Record<number, string[]> = {
  2: [
    // 版本2的升级脚本
    'ALTER TABLE comic_info ADD COLUMN rating REAL DEFAULT 0.0',
    'ALTER TABLE comic_info ADD COLUMN viewCount INTEGER DEFAULT 0'
  ],
  3: [
    // 版本3的升级脚本
    'ALTER TABLE chapter ADD COLUMN publishTime INTEGER DEFAULT 0',
    'CREATE INDEX IF NOT EXISTS idx_chapter_publish ON chapter (publishTime)'
  ],
  4: [
    // 版本4的升级脚本：添加外部图源ID字段（临时补丁）
    'ALTER TABLE comic_info ADD COLUMN externalId TEXT',
    'CREATE INDEX IF NOT EXISTS idx_comic_external ON comic_info (externalId, sourceId)',
    'ALTER TABLE chapter ADD COLUMN externalId TEXT',
    'CREATE INDEX IF NOT EXISTS idx_chapter_external ON chapter (externalId, comicId)'
  ],
  5: [
    // 版本5的升级脚本：重建表以确保externalId为NOT NULL
    // 注意：这会清空现有数据，仅用于开发阶段
    'DROP TABLE IF EXISTS page',
    'DROP TABLE IF EXISTS chapter',
    'DROP TABLE IF EXISTS comic_info',
    // 表会通过CREATE_TABLE_SQL重新创建
  ],
  6: [
    // 版本6的升级脚本：添加webUrl和apiUrl字段
    'ALTER TABLE comic_info ADD COLUMN webUrl TEXT',
    'ALTER TABLE comic_info ADD COLUMN apiUrl TEXT'
  ],
  7: [
    // 版本7的升级脚本：为电子书阅读进度表添加 currentChapterIndex 和 domPos 字段
    'ALTER TABLE ebook_reading_progress ADD COLUMN currentChapterIndex INTEGER DEFAULT 0',
    'ALTER TABLE ebook_reading_progress ADD COLUMN domPos TEXT DEFAULT \'\'',
    // 为电子书阅读设置表添加新字段
    'ALTER TABLE ebook_reading_settings ADD COLUMN fontPath TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN fontWeight INTEGER DEFAULT 400',
    'ALTER TABLE ebook_reading_settings ADD COLUMN themeBgImage TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN nightMode INTEGER DEFAULT 0'
  ],
  8: [
    // 版本8的补救脚本：确保所有新字段都存在（因为版本7的迁移可能因列已存在而部分失败）
    // 由于 DatabaseManager 现在会忽略错误，我们可以安全地重新执行这些命令
    'ALTER TABLE ebook_reading_progress ADD COLUMN currentChapterIndex INTEGER DEFAULT 0',
    'ALTER TABLE ebook_reading_progress ADD COLUMN domPos TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN fontPath TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN fontWeight INTEGER DEFAULT 400',
    'ALTER TABLE ebook_reading_settings ADD COLUMN themeBgImage TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN nightMode INTEGER DEFAULT 0'
  ],
  9: [
    // 版本9：添加 followSystemTheme 字段，用于控制是否跟随系统主题
    'ALTER TABLE ebook_reading_settings ADD COLUMN followSystemTheme INTEGER DEFAULT 1'
  ],
  10: [
    // 版本10：为comic_info表添加contentType字段，用于区分漫画和电子书类PDF
    // contentType: 'manga' = 漫画, 'ebook' = 电子书类PDF, 'online' = 在线漫画
    'ALTER TABLE comic_info ADD COLUMN contentType TEXT DEFAULT \'manga\''
  ],
  11: [
    // 版本11：为电子书阅读设置表添加纯文本阅读器专用字段
    // 高级字体设置
    'ALTER TABLE ebook_reading_settings ADD COLUMN letterSpacing REAL DEFAULT 0',
    'ALTER TABLE ebook_reading_settings ADD COLUMN paragraphSpacing INTEGER DEFAULT 8',
    'ALTER TABLE ebook_reading_settings ADD COLUMN firstLineIndent INTEGER DEFAULT 2',
    'ALTER TABLE ebook_reading_settings ADD COLUMN textAlignment TEXT DEFAULT \'JUSTIFY\'',
    // 翻页动画设置
    'ALTER TABLE ebook_reading_settings ADD COLUMN pageTurnAnimation TEXT DEFAULT \'SLIDE\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN tapToTurn INTEGER DEFAULT 1',
    'ALTER TABLE ebook_reading_settings ADD COLUMN volumeKeyNavigation INTEGER DEFAULT 1',
    'ALTER TABLE ebook_reading_settings ADD COLUMN keepScreenOn INTEGER DEFAULT 0',
    // 显示设置
    'ALTER TABLE ebook_reading_settings ADD COLUMN showPageNumber INTEGER DEFAULT 1',
    'ALTER TABLE ebook_reading_settings ADD COLUMN showProgress INTEGER DEFAULT 0',
    'ALTER TABLE ebook_reading_settings ADD COLUMN showTime INTEGER DEFAULT 1',
    'ALTER TABLE ebook_reading_settings ADD COLUMN showBattery INTEGER DEFAULT 0',
    // 背景设置
    'ALTER TABLE ebook_reading_settings ADD COLUMN backgroundType TEXT DEFAULT \'COLOR\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN backgroundImagePath TEXT DEFAULT \'\'',
    'ALTER TABLE ebook_reading_settings ADD COLUMN backgroundImageOpacity REAL DEFAULT 0.3'
  ],
  12: [
    // 版本12：为在线漫画表添加 sourcePkg 字段
    // sourcePkg 是图源的唯一包名标识符，用于在图源删除后重新导入时正确识别图源
    // 这解决了图源删除后 sourceId 失效导致无法识别图源的问题
    'ALTER TABLE online_comic_info ADD COLUMN sourcePkg TEXT DEFAULT \'\'',
    'CREATE INDEX IF NOT EXISTS idx_online_comic_pkg ON online_comic_info (sourcePkg)'
  ],
  13: [
    // 版本13：为图源表添加 type 字段，用于区分图源类型（manga/ebook/novel等）
    'ALTER TABLE comic_source ADD COLUMN type TEXT DEFAULT \'manga\''
  ],
  14: [
    // 版本14：添加跟踪记录表，用于与第三方服务同步阅读进度
    `CREATE TABLE IF NOT EXISTS track_record (
      id TEXT PRIMARY KEY,
      contentId TEXT NOT NULL,
      contentType TEXT NOT NULL DEFAULT 'manga',
      trackerId INTEGER NOT NULL,
      remoteId TEXT NOT NULL,
      remoteTitle TEXT,
      remoteUrl TEXT,
      lastChapterRead REAL DEFAULT 0,
      totalChapters INTEGER DEFAULT 0,
      score REAL DEFAULT 0,
      status INTEGER DEFAULT 0,
      startedReadingDate INTEGER DEFAULT 0,
      finishedReadingDate INTEGER DEFAULT 0,
      lastSyncTime INTEGER DEFAULT 0,
      syncStatus TEXT DEFAULT 'pending',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )`,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_track_record_unique ON track_record (contentId, trackerId)',
    'CREATE INDEX IF NOT EXISTS idx_track_record_content ON track_record (contentId)',
    'CREATE INDEX IF NOT EXISTS idx_track_record_tracker ON track_record (trackerId)',
    'CREATE INDEX IF NOT EXISTS idx_track_record_sync ON track_record (syncStatus)'
  ]
};
