/**
 * 小说模块数据库表定义
 * 独立的表结构，不影响现有数据库
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelDatabaseSchema.ets
 */

/**
 * 小说书源表结构
 */
export interface NovelSourceTable {
  id: string;
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceGroup: string;
  bookSourceType: number;
  enabled: number;
  weight: number;
  lastUpdateTime: number;
  respondTime: number;
  configJson: string;
  isNSFW: number;
  createTime: number;
  updateTime: number;
}

/**
 * 小说书籍表结构
 */
export interface NovelBookTable {
  id: string;
  sourceId: string;
  sourceName: string;
  bookUrl: string;
  name: string;
  author: string;
  kind: string;
  intro: string;
  coverUrl: string;
  coverLocalPath: string;
  tocUrl: string;
  latestChapterTitle: string;
  wordCount: string;
  chapterCount: number;
  readStatus: string;
  lastReadChapterId: string;
  lastReadChapterIndex: number;
  lastReadPosition: number;
  lastReadTime: number;
  isFavorite: number;
  createTime: number;
  updateTime: number;
}

/**
 * 小说章节表结构
 */
export interface NovelChapterTable {
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
 * 小说正文缓存表结构
 */
export interface NovelContentCacheTable {
  id: string;
  chapterId: string;
  content: string;
  wordCount: number;
  createTime: number;
  expireTime: number;
}

/**
 * 小说阅读进度表结构
 */
export interface NovelReadProgressTable {
  id: string;
  bookId: string;
  chapterId: string;
  chapterIndex: number;
  position: number;
  progress: number;
  readTime: number;
  createTime: number;
  updateTime: number;
}

/**
 * 小说阅读设置表结构
 */
export interface NovelReaderSettingsTable {
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
 * 小说替换规则表结构
 */
export interface NovelReplaceRuleTable {
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
 * 小说搜索历史表结构
 */
export interface NovelSearchHistoryTable {
  id: string;
  keyword: string;
  searchTime: number;
  resultCount: number;
}

/**
 * 小说数据库表创建SQL接口
 */
interface NovelCreateTableSql {
  NOVEL_SOURCE: string;
  NOVEL_BOOK: string;
  NOVEL_CHAPTER: string;
  NOVEL_CONTENT_CACHE: string;
  NOVEL_READ_PROGRESS: string;
  NOVEL_READER_SETTINGS: string;
  NOVEL_REPLACE_RULE: string;
  NOVEL_SEARCH_HISTORY: string;
  NOVEL_TXT_TOC_RULE: string;
  NOVEL_DICT_RULE: string;
}

/**
 * 小说数据库表创建SQL
 */
export const NOVEL_CREATE_TABLE_SQL: NovelCreateTableSql = {
  /**
   * 小说书源表
   * 存储Legado格式的书源配置
   */
  NOVEL_SOURCE: `
    CREATE TABLE IF NOT EXISTS novel_source (
      id TEXT PRIMARY KEY,
      bookSourceUrl TEXT NOT NULL UNIQUE,
      bookSourceName TEXT NOT NULL,
      bookSourceGroup TEXT DEFAULT '',
      bookSourceType INTEGER DEFAULT 0,
      enabled INTEGER DEFAULT 1,
      weight INTEGER DEFAULT 0,
      lastUpdateTime INTEGER DEFAULT 0,
      respondTime INTEGER DEFAULT 180000,
      configJson TEXT NOT NULL,
      isNSFW INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  /**
   * 小说书籍表
   * 存储用户收藏/阅读过的书籍
   */
  NOVEL_BOOK: `
    CREATE TABLE IF NOT EXISTS novel_book (
      id TEXT PRIMARY KEY,
      sourceId TEXT NOT NULL,
      sourceName TEXT NOT NULL,
      bookUrl TEXT NOT NULL,
      name TEXT NOT NULL,
      author TEXT DEFAULT '',
      kind TEXT DEFAULT '',
      intro TEXT DEFAULT '',
      coverUrl TEXT DEFAULT '',
      coverLocalPath TEXT DEFAULT '',
      tocUrl TEXT DEFAULT '',
      latestChapterTitle TEXT DEFAULT '',
      wordCount TEXT DEFAULT '',
      chapterCount INTEGER DEFAULT 0,
      readStatus TEXT DEFAULT 'unread',
      lastReadChapterId TEXT DEFAULT '',
      lastReadChapterIndex INTEGER DEFAULT 0,
      lastReadPosition INTEGER DEFAULT 0,
      lastReadTime INTEGER DEFAULT 0,
      totalReadingTime INTEGER DEFAULT 0,
      isFavorite INTEGER DEFAULT 0,
      isPrivate INTEGER DEFAULT 0,
      isNSFW INTEGER DEFAULT 0,
      groupName TEXT DEFAULT '',
      sortOrder INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      UNIQUE(sourceId, bookUrl)
    )
  `,

  /**
   * 小说章节表
   * 存储书籍的章节信息
   */
  NOVEL_CHAPTER: `
    CREATE TABLE IF NOT EXISTS novel_chapter (
      id TEXT PRIMARY KEY,
      bookId TEXT NOT NULL,
      url TEXT NOT NULL,
      title TEXT NOT NULL,
      chapterIndex INTEGER NOT NULL,
      isVolume INTEGER DEFAULT 0,
      isVip INTEGER DEFAULT 0,
      isPay INTEGER DEFAULT 0,
      isDownloaded INTEGER DEFAULT 0,
      contentPath TEXT DEFAULT '',
      wordCount INTEGER DEFAULT 0,
      updateTime INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      FOREIGN KEY (bookId) REFERENCES novel_book (id) ON DELETE CASCADE,
      UNIQUE(bookId, url)
    )
  `,

  /**
   * 小说正文缓存表
   * 缓存已获取的章节正文
   */
  NOVEL_CONTENT_CACHE: `
    CREATE TABLE IF NOT EXISTS novel_content_cache (
      id TEXT PRIMARY KEY,
      chapterId TEXT NOT NULL UNIQUE,
      content TEXT NOT NULL,
      wordCount INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      expireTime INTEGER NOT NULL,
      FOREIGN KEY (chapterId) REFERENCES novel_chapter (id) ON DELETE CASCADE
    )
  `,

  /**
   * 小说阅读进度表
   * 记录每本书的阅读进度
   */
  NOVEL_READ_PROGRESS: `
    CREATE TABLE IF NOT EXISTS novel_read_progress (
      id TEXT PRIMARY KEY,
      bookId TEXT NOT NULL UNIQUE,
      chapterId TEXT NOT NULL,
      chapterIndex INTEGER DEFAULT 0,
      position INTEGER DEFAULT 0,
      progress REAL DEFAULT 0.0,
      readTime INTEGER NOT NULL,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      FOREIGN KEY (bookId) REFERENCES novel_book (id) ON DELETE CASCADE
    )
  `,

  /**
   * 小说阅读设置表
   * 存储用户的阅读偏好设置
   */
  NOVEL_READER_SETTINGS: `
    CREATE TABLE IF NOT EXISTS novel_reader_settings (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL DEFAULT 'default',
      fontSize INTEGER DEFAULT 18,
      lineHeight REAL DEFAULT 1.8,
      letterSpacing INTEGER DEFAULT 0,
      paragraphSpacing INTEGER DEFAULT 16,
      fontFamily TEXT DEFAULT 'HarmonyOS Sans',
      textColor TEXT DEFAULT '#333333',
      backgroundColor TEXT DEFAULT '#F5F5DC',
      brightness REAL DEFAULT 1.0,
      keepScreenOn INTEGER DEFAULT 1,
      volumeKeyTurn INTEGER DEFAULT 1,
      clickTurn INTEGER DEFAULT 1,
      autoScroll INTEGER DEFAULT 0,
      autoScrollSpeed INTEGER DEFAULT 50,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL,
      UNIQUE(userId)
    )
  `,

  /**
   * 小说替换规则表
   * 存储正文净化替换规则
   */
  NOVEL_REPLACE_RULE: `
    CREATE TABLE IF NOT EXISTS novel_replace_rule (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      pattern TEXT NOT NULL,
      replacement TEXT DEFAULT '',
      isRegex INTEGER DEFAULT 0,
      scope TEXT DEFAULT 'all',
      enabled INTEGER DEFAULT 1,
      ruleOrder INTEGER DEFAULT 0,
      sourceIds TEXT DEFAULT '',
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  /**
   * 小说搜索历史表
   * 记录用户的搜索历史
   */
  NOVEL_SEARCH_HISTORY: `
    CREATE TABLE IF NOT EXISTS novel_search_history (
      id TEXT PRIMARY KEY,
      keyword TEXT NOT NULL UNIQUE,
      searchTime INTEGER NOT NULL,
      resultCount INTEGER DEFAULT 0
    )
  `,

  /**
   * TXT目录规则表
   * 存储本地TXT文件章节识别规则
   */
  NOVEL_TXT_TOC_RULE: `
    CREATE TABLE IF NOT EXISTS novel_txt_toc_rule (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      rule TEXT NOT NULL,
      example TEXT DEFAULT '',
      serialNumber INTEGER DEFAULT 0,
      enabled INTEGER DEFAULT 1,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `,

  /**
   * 字典规则表
   * 存储在线词典查询规则
   */
  NOVEL_DICT_RULE: `
    CREATE TABLE IF NOT EXISTS novel_dict_rule (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      urlRule TEXT NOT NULL,
      showRule TEXT DEFAULT '',
      enabled INTEGER DEFAULT 1,
      sortNumber INTEGER DEFAULT 0,
      createTime INTEGER NOT NULL,
      updateTime INTEGER NOT NULL
    )
  `
};

/**
 * 小说数据库索引创建SQL
 */
export const NOVEL_CREATE_INDEX_SQL = [
  // 书源索引
  'CREATE INDEX IF NOT EXISTS idx_novel_source_name ON novel_source(bookSourceName)',
  'CREATE INDEX IF NOT EXISTS idx_novel_source_group ON novel_source(bookSourceGroup)',
  'CREATE INDEX IF NOT EXISTS idx_novel_source_enabled ON novel_source(enabled)',
  
  // 书籍索引
  'CREATE INDEX IF NOT EXISTS idx_novel_book_source ON novel_book(sourceId)',
  'CREATE INDEX IF NOT EXISTS idx_novel_book_name ON novel_book(name)',
  'CREATE INDEX IF NOT EXISTS idx_novel_book_author ON novel_book(author)',
  'CREATE INDEX IF NOT EXISTS idx_novel_book_favorite ON novel_book(isFavorite)',
  'CREATE INDEX IF NOT EXISTS idx_novel_book_read_status ON novel_book(readStatus)',
  'CREATE INDEX IF NOT EXISTS idx_novel_book_last_read ON novel_book(lastReadTime)',
  
  // 章节索引
  'CREATE INDEX IF NOT EXISTS idx_novel_chapter_book ON novel_chapter(bookId)',
  'CREATE INDEX IF NOT EXISTS idx_novel_chapter_index ON novel_chapter(bookId, chapterIndex)',
  
  // 正文缓存索引
  'CREATE INDEX IF NOT EXISTS idx_novel_content_expire ON novel_content_cache(expireTime)',
  
  // 阅读进度索引
  'CREATE INDEX IF NOT EXISTS idx_novel_progress_time ON novel_read_progress(readTime)',
  
  // 替换规则索引
  'CREATE INDEX IF NOT EXISTS idx_novel_replace_rule_order ON novel_replace_rule(ruleOrder)',
  'CREATE INDEX IF NOT EXISTS idx_novel_replace_rule_enabled ON novel_replace_rule(enabled)',
  
  // 搜索历史索引
  'CREATE INDEX IF NOT EXISTS idx_novel_search_history_time ON novel_search_history(searchTime)',
  
  // TXT目录规则索引
  'CREATE INDEX IF NOT EXISTS idx_novel_txt_toc_rule_order ON novel_txt_toc_rule(serialNumber)',
  'CREATE INDEX IF NOT EXISTS idx_novel_txt_toc_rule_enabled ON novel_txt_toc_rule(enabled)',
  
  // 字典规则索引
  'CREATE INDEX IF NOT EXISTS idx_novel_dict_rule_order ON novel_dict_rule(sortNumber)',
  'CREATE INDEX IF NOT EXISTS idx_novel_dict_rule_enabled ON novel_dict_rule(enabled)'
];
