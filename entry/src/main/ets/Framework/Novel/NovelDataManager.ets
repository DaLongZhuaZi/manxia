/**
 * 小说数据管理器
 * 独立管理小说相关数据，不影响现有数据库
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelDataManager.ets
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { NOVEL_CREATE_TABLE_SQL, NOVEL_CREATE_INDEX_SQL } from './NovelDatabaseSchema';
import { LegadoBookSource } from './LegadoSourceTypes';
import { NovelBook, NovelChapter, NovelReadProgress, NovelReaderSettings, DEFAULT_NOVEL_READER_SETTINGS, NovelReadStatus } from '../../Models/NovelModels';
import { getNovelLoginManager } from './NovelLoginManager';
import { getNovelCoverGenerator } from './NovelCoverGenerator';

const TAG = 'NovelDataManager';

/**
 * 表信息接口
 */
interface TableInfo {
  name: string;
  sql: string;
}

/**
 * 小说数据管理器类
 */
export class NovelDataManager {
  private static instance: NovelDataManager | null = null;
  private store: relationalStore.RdbStore | null = null;
  private isInitialized: boolean = false;

  private constructor() {}

  static getInstance(): NovelDataManager {
    if (!NovelDataManager.instance) {
      NovelDataManager.instance = new NovelDataManager();
    }
    return NovelDataManager.instance;
  }

  /**
   * 初始化数据库（使用现有数据库连接）
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      return;
    }

    try {
      logger.info(TAG, '开始初始化小说数据库表');
      
      const config: relationalStore.StoreConfig = {
        name: 'manxia_comic.db',
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: false
      };

      this.store = await relationalStore.getRdbStore(context, config);
      
      // 创建小说相关表（增量添加，不影响现有表）
      await this.createNovelTables();
      
      // 创建索引
      await this.createNovelIndexes();
      
      // 初始化登录管理器（加载持久化的Cookie）
      const loginManager = getNovelLoginManager();
      await loginManager.initialize(context);
      
      // 初始化封面生成器
      const coverGenerator = getNovelCoverGenerator();
      await coverGenerator.initialize(context.filesDir);
      
      this.isInitialized = true;
      logger.info(TAG, '小说数据库表初始化完成');
    } catch (error) {
      const errMsg = `小说数据库初始化失败: ${String(error)}`;
      logger.error(TAG, errMsg);
      throw new Error(errMsg);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('小说数据库未初始化');
    }
    return this.store;
  }

  /**
   * 创建小说相关表
   */
  private async createNovelTables(): Promise<void> {
    const store = this.getStore();
    const tables: TableInfo[] = [
      { name: 'novel_source', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SOURCE } as TableInfo,
      { name: 'novel_book', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_BOOK } as TableInfo,
      { name: 'novel_chapter', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_CHAPTER } as TableInfo,
      { name: 'novel_content_cache', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_CONTENT_CACHE } as TableInfo,
      { name: 'novel_read_progress', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_READ_PROGRESS } as TableInfo,
      { name: 'novel_reader_settings', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_READER_SETTINGS } as TableInfo,
      { name: 'novel_replace_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_REPLACE_RULE } as TableInfo,
      { name: 'novel_search_history', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_SEARCH_HISTORY } as TableInfo,
      { name: 'novel_txt_toc_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_TXT_TOC_RULE } as TableInfo,
      { name: 'novel_dict_rule', sql: NOVEL_CREATE_TABLE_SQL.NOVEL_DICT_RULE } as TableInfo
    ];

    for (const table of tables) {
      try {
        await store.executeSql(table.sql);
        logger.debug(TAG, `创建表成功: ${table.name}`);
        
        // 为 novel_source 表添加可能缺失的 isNSFW 列
        if (table.name === 'novel_source') {
          try { await store.executeSql('ALTER TABLE novel_source ADD COLUMN isNSFW INTEGER DEFAULT 0'); } catch (e) {}
          try { await store.executeSql('UPDATE novel_source SET isNSFW = 0 WHERE isNSFW IS NULL'); } catch (e) {}
          logger.info(TAG, '✅ [NOVEL_SOURCE] isNSFW列添加完成');
        }
        
        // 为 novel_book 表添加可能缺失的列
        if (table.name === 'novel_book') {
          logger.info(TAG, '🔧 [NOVEL_BOOK] 添加隐私列');
          try { await store.executeSql('ALTER TABLE novel_book ADD COLUMN isPrivate INTEGER DEFAULT 0'); } catch (e) {}
          try { await store.executeSql('ALTER TABLE novel_book ADD COLUMN isNSFW INTEGER DEFAULT 0'); } catch (e) {}
          try { await store.executeSql('UPDATE novel_book SET isPrivate = 0 WHERE isPrivate IS NULL'); } catch (e) {}
          try { await store.executeSql('UPDATE novel_book SET isNSFW = 0 WHERE isNSFW IS NULL'); } catch (e) {}
          logger.info(TAG, '✅ [NOVEL_BOOK] 列添加完成');
        }
      } catch (error) {
        logger.error(TAG, `创建表失败: ${table.name}, ${String(error)}`);
      }
    }
  }

  /**
   * 创建索引
   */
  private async createNovelIndexes(): Promise<void> {
    const store = this.getStore();
    for (const sql of NOVEL_CREATE_INDEX_SQL) {
      try {
        await store.executeSql(sql);
      } catch (error) {
        // 索引可能已存在，忽略错误
      }
    }
  }

  // ==================== 书源操作 ====================

  /**
   * 保存书源
   */
  async saveSource(source: LegadoBookSource): Promise<string> {
    const store = this.getStore();
    const id = this.generateId();
    const now = Date.now();

    const sql = `INSERT OR REPLACE INTO novel_source 
      (id, bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, 
       enabled, weight, lastUpdateTime, respondTime, configJson, isNSFW, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id,
      source.bookSourceUrl,
      source.bookSourceName,
      source.bookSourceGroup || '',
      source.bookSourceType,
      source.enabled !== false ? 1 : 0,
      source.weight || 0,
      source.lastUpdateTime || now,
      source.respondTime || 180000,
      JSON.stringify(source),
      source.isNSFW ? 1 : 0,
      now,
      now
    ]);

    return id;
  }

  /**
   * 获取所有书源
   */
  async getAllSources(): Promise<LegadoBookSource[]> {
    const store = this.getStore();
    const rs = await store.querySql('SELECT configJson FROM novel_source ORDER BY weight DESC');
    const sources: LegadoBookSource[] = [];

    if (rs.goToFirstRow()) {
      do {
        try {
          const json = rs.getString(0);
          sources.push(JSON.parse(json) as LegadoBookSource);
        } catch (e) {
          // 忽略解析错误
        }
      } while (rs.goToNextRow());
    }
    rs.close();
    return sources;
  }

  /**
   * 删除书源
   */
  async deleteSource(bookSourceUrl: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql('DELETE FROM novel_source WHERE bookSourceUrl = ?', [bookSourceUrl]);
  }

  // ==================== 书籍操作 ====================

  /**
   * 保存书籍
   */
  async saveBook(book: NovelBook): Promise<string> {
    const store = this.getStore();
    const now = Date.now();
    const id = book.id || this.generateId();

    // 【NSFW作用域】从书源继承NSFW状态（受作用域开关控制）
    let isNSFWVal = book.isNSFW ? 1 : 0;
    if (isNSFWVal === 0 && book.isNSFW === undefined && book.sourceId) {
      try {
        const sourceNsfwRs = await store.querySql(
          'SELECT isNSFW FROM novel_source WHERE bookSourceUrl = ? OR id = ?',
          [book.sourceId, book.sourceId]
        );
        if (sourceNsfwRs.goToFirstRow()) {
          const sourceIsNSFW = sourceNsfwRs.getLong(0);
          if (sourceIsNSFW === 1) {
            // 检查书源NSFW作用域开关
            let scopeEnabled = true;
            try {
              const cfmModule = await import('../Managers/ContentFilterManager');
              scopeEnabled = cfmModule.ContentFilterManager.getInstance().isNsfwScopeBookSourceEnabled();
            } catch (_e) {
              // ContentFilterManager未初始化时默认启用
            }
            if (scopeEnabled) {
              isNSFWVal = 1;
              logger.debug(TAG, `【NSFW作用域】小说从书源继承NSFW标记: ${book.name}`);
            }
          }
          sourceNsfwRs.close();
        } else {
          sourceNsfwRs.close();
        }
      } catch (e) {
        logger.warn(TAG, `查询书源NSFW状态失败: ${e}`);
      }
    }

    const sql = `INSERT OR REPLACE INTO novel_book 
      (id, sourceId, sourceName, bookUrl, name, author, kind, intro, coverUrl, 
       coverLocalPath, tocUrl, latestChapterTitle, wordCount, chapterCount,
       readStatus, lastReadChapterId, lastReadChapterIndex, lastReadPosition,
       lastReadTime, isFavorite, isPrivate, isNSFW, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id, book.sourceId, book.sourceName, book.bookUrl, book.name,
      book.author || '', book.kind || '', book.intro || '', book.coverUrl || '',
      book.coverLocalPath || '', book.tocUrl || '', book.latestChapterTitle || '',
      book.wordCount || '', book.chapterCount || 0, book.readStatus || 'unread',
      book.lastReadChapterId || '', book.lastReadChapterIndex || 0,
      book.lastReadPosition || 0, book.lastReadTime || 0,
      book.isFavorite ? 1 : 0,
      book.isPrivate ? 1 : 0,  // isPrivate默认为0（普通内容）
      isNSFWVal,                // isNSFW：支持从书源自动继承
      book.createTime || now, now
    ]);

    return id;
  }

  /**
   * 获取收藏的书籍
   */
  async getFavoriteBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isFavorite = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * 获取最近阅读的书籍
   */
  async getRecentBooks(limit: number = 20): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE lastReadTime > 0 ORDER BY lastReadTime DESC LIMIT ?`,
      [limit]
    );
    return this.parseBookResults(rs);
  }

  /**
   * 搜索书库中的小说
   */
  async searchBooks(keyword: string): Promise<NovelBook[]> {
    const store = this.getStore();
    const searchPattern = `%${keyword}%`;
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE isFavorite = 1 AND (name LIKE ? OR author LIKE ?) ORDER BY lastReadTime DESC`,
      [searchPattern, searchPattern]
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取隐私小说列表
   * @returns Promise<NovelBook[]> 隐私小说列表
   */
  async getPrivateBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isPrivate = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取非隐私小说列表
   * @returns Promise<NovelBook[]> 非隐私小说列表
   */
  async getNonPrivateBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE (isPrivate = 0 OR isPrivate IS NULL) ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取SFW（非NSFW）小说列表
   * @returns Promise<NovelBook[]> SFW小说列表
   */
  async getSFWBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE (isNSFW = 0 OR isNSFW IS NULL) ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * [新增] 获取NSFW小说列表
   * @returns Promise<NovelBook[]> NSFW小说列表
   */
  async getNSFWBooks(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isNSFW = 1 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  /**
   * 解析书籍查询结果
   */
  private parseBookResults(rs: relationalStore.ResultSet): NovelBook[] {
    const books: NovelBook[] = [];
    if (rs.goToFirstRow()) {
      do {
        books.push({
          id: rs.getString(rs.getColumnIndex('id')),
          sourceId: rs.getString(rs.getColumnIndex('sourceId')),
          sourceName: rs.getString(rs.getColumnIndex('sourceName')),
          bookUrl: rs.getString(rs.getColumnIndex('bookUrl')),
          name: rs.getString(rs.getColumnIndex('name')),
          author: rs.getString(rs.getColumnIndex('author')),
          kind: rs.getString(rs.getColumnIndex('kind')),
          intro: rs.getString(rs.getColumnIndex('intro')),
          coverUrl: rs.getString(rs.getColumnIndex('coverUrl')),
          coverLocalPath: rs.getString(rs.getColumnIndex('coverLocalPath')),
          tocUrl: rs.getString(rs.getColumnIndex('tocUrl')),
          latestChapterTitle: rs.getString(rs.getColumnIndex('latestChapterTitle')),
          wordCount: rs.getString(rs.getColumnIndex('wordCount')),
          chapterCount: rs.getLong(rs.getColumnIndex('chapterCount')),
          readStatus: rs.getString(rs.getColumnIndex('readStatus')) as NovelReadStatus,
          lastReadChapterId: rs.getString(rs.getColumnIndex('lastReadChapterId')),
          lastReadChapterIndex: rs.getLong(rs.getColumnIndex('lastReadChapterIndex')),
          lastReadPosition: rs.getLong(rs.getColumnIndex('lastReadPosition')),
          lastReadTime: rs.getLong(rs.getColumnIndex('lastReadTime')),
          totalReadingTime: rs.getLong(rs.getColumnIndex('totalReadingTime')),
          isFavorite: rs.getLong(rs.getColumnIndex('isFavorite')) === 1,
          isPrivate: rs.getLong(rs.getColumnIndex('isPrivate')) === 1,  // 读取隐私状态
          isNSFW: rs.getLong(rs.getColumnIndex('isNSFW')) === 1,        // 读取NSFW状态
          createTime: rs.getLong(rs.getColumnIndex('createTime')),
          updateDbTime: rs.getLong(rs.getColumnIndex('updateTime'))
        });
      } while (rs.goToNextRow());
    }
    rs.close();
    return books;
  }

  // ==================== 阅读进度 ====================

  /**
   * 保存阅读进度
   */
  async saveReadProgress(progress: NovelReadProgress): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    const id = this.generateId();

    // 使用 readTime 保护的更新/插入策略，避免乱序写入覆盖新进度
    const safeReadTime = progress.readTime > 0 ? progress.readTime : now;
    
    const updateProgressSql = `UPDATE novel_read_progress SET
      chapterId = ?, chapterIndex = ?, position = ?, progress = ?, readTime = ?, updateTime = ?
      WHERE bookId = ? AND readTime <= ?`;
    await store.executeSql(updateProgressSql, [
      progress.chapterId, progress.chapterIndex, progress.position, progress.progress, safeReadTime, now,
      progress.bookId, safeReadTime
    ]);

    const insertProgressSql = `INSERT OR IGNORE INTO novel_read_progress
      (id, bookId, chapterId, chapterIndex, position, progress, readTime, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`;
    await store.executeSql(insertProgressSql, [
      id, progress.bookId, progress.chapterId, progress.chapterIndex,
      progress.position, progress.progress, safeReadTime, now, now
    ]);

    // 同时更新书籍表的阅读进度
    await store.executeSql(
      `UPDATE novel_book SET lastReadChapterId = ?, lastReadChapterIndex = ?, 
       lastReadPosition = ?, lastReadTime = ?, readStatus = 'reading', updateTime = ?
       WHERE id = ? AND (lastReadTime IS NULL OR lastReadTime <= ?)`,
      [progress.chapterId, progress.chapterIndex, progress.position, safeReadTime, now, progress.bookId, safeReadTime]
    );
  }

  /**
   * 获取阅读进度
   */
  async getReadProgress(bookId: string): Promise<NovelReadProgress | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_read_progress WHERE bookId = ?', [bookId]
    );

    if (rs.goToFirstRow()) {
      const progress: NovelReadProgress = {
        bookId: rs.getString(rs.getColumnIndex('bookId')),
        chapterId: rs.getString(rs.getColumnIndex('chapterId')),
        chapterIndex: rs.getLong(rs.getColumnIndex('chapterIndex')),
        position: rs.getLong(rs.getColumnIndex('position')),
        progress: rs.getDouble(rs.getColumnIndex('progress')),
        readTime: rs.getLong(rs.getColumnIndex('readTime'))
      };
      rs.close();
      return progress;
    }
    rs.close();
    return null;
  }

  // ==================== 阅读设置 ====================

  /**
   * 获取阅读设置
   */
  async getReaderSettings(userId: string = 'default'): Promise<NovelReaderSettings> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_reader_settings WHERE userId = ?', [userId]
    );

    if (rs.goToFirstRow()) {
      const settings: NovelReaderSettings = {
        fontSize: rs.getLong(rs.getColumnIndex('fontSize')),
        lineHeight: rs.getDouble(rs.getColumnIndex('lineHeight')),
        letterSpacing: rs.getLong(rs.getColumnIndex('letterSpacing')),
        paragraphSpacing: rs.getLong(rs.getColumnIndex('paragraphSpacing')),
        fontFamily: rs.getString(rs.getColumnIndex('fontFamily')),
        textColor: rs.getString(rs.getColumnIndex('textColor')),
        backgroundColor: rs.getString(rs.getColumnIndex('backgroundColor')),
        brightness: rs.getDouble(rs.getColumnIndex('brightness')),
        keepScreenOn: rs.getLong(rs.getColumnIndex('keepScreenOn')) === 1,
        volumeKeyTurn: rs.getLong(rs.getColumnIndex('volumeKeyTurn')) === 1,
        clickTurn: rs.getLong(rs.getColumnIndex('clickTurn')) === 1,
        autoScroll: rs.getLong(rs.getColumnIndex('autoScroll')) === 1,
        autoScrollSpeed: rs.getLong(rs.getColumnIndex('autoScrollSpeed'))
      };
      rs.close();
      return settings;
    }
    rs.close();
    return DEFAULT_NOVEL_READER_SETTINGS;
  }

  /**
   * 保存阅读设置
   */
  async saveReaderSettings(settings: NovelReaderSettings, userId: string = 'default'): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    const id = this.generateId();

    await store.executeSql('DELETE FROM novel_reader_settings WHERE userId = ?', [userId]);

    const sql = `INSERT INTO novel_reader_settings 
      (id, userId, fontSize, lineHeight, letterSpacing, paragraphSpacing, fontFamily,
       textColor, backgroundColor, brightness, keepScreenOn, volumeKeyTurn, clickTurn,
       autoScroll, autoScrollSpeed, createTime, updateTime)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;

    await store.executeSql(sql, [
      id, userId, settings.fontSize, settings.lineHeight, settings.letterSpacing,
      settings.paragraphSpacing, settings.fontFamily, settings.textColor,
      settings.backgroundColor, settings.brightness,
      settings.keepScreenOn ? 1 : 0, settings.volumeKeyTurn ? 1 : 0,
      settings.clickTurn ? 1 : 0, settings.autoScroll ? 1 : 0,
      settings.autoScrollSpeed, now, now
    ]);
  }

  // ==================== 书架管理 ====================

  /**
   * 获取所有书架分组
   */
  async getBookGroups(): Promise<string[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT DISTINCT groupName FROM novel_book WHERE isFavorite = 1 AND groupName != "" ORDER BY groupName'
    );
    const groups: string[] = [];
    if (rs.goToFirstRow()) {
      do {
        groups.push(rs.getString(0));
      } while (rs.goToNextRow());
    }
    rs.close();
    return groups;
  }

  /**
   * 获取指定分组的书籍
   */
  async getBooksByGroup(groupName: string): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE isFavorite = 1 AND groupName = ? ORDER BY sortOrder ASC, lastReadTime DESC',
      [groupName]
    );
    return this.parseBookResults(rs);
  }

  /**
   * 设置书籍分组
   */
  async setBookGroup(bookId: string, groupName: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET groupName = ?, updateTime = ? WHERE id = ?',
      [groupName, Date.now(), bookId]
    );
  }

  /**
   * 批量设置书籍分组
   */
  async setBookGroupBatch(bookIds: string[], groupName: string): Promise<void> {
    const store = this.getStore();
    const now = Date.now();
    for (const bookId of bookIds) {
      await store.executeSql(
        'UPDATE novel_book SET groupName = ?, updateTime = ? WHERE id = ?',
        [groupName, now, bookId]
      );
    }
  }

  /**
   * 设置书籍排序顺序
   */
  async setBookSortOrder(bookId: string, sortOrder: number): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET sortOrder = ?, updateTime = ? WHERE id = ?',
      [sortOrder, Date.now(), bookId]
    );
  }

  /**
   * 获取收藏书籍（支持排序）
   */
  async getFavoriteBooksSorted(sortType: string = 'lastRead', ascending: boolean = false): Promise<NovelBook[]> {
    const store = this.getStore();
    let orderBy = 'lastReadTime DESC';
    
    switch (sortType) {
      case 'lastRead':
        orderBy = ascending ? 'lastReadTime ASC' : 'lastReadTime DESC';
        break;
      case 'name':
        orderBy = ascending ? 'name ASC' : 'name DESC';
        break;
      case 'author':
        orderBy = ascending ? 'author ASC' : 'author DESC';
        break;
      case 'addTime':
        orderBy = ascending ? 'createTime ASC' : 'createTime DESC';
        break;
      case 'updateTime':
        orderBy = ascending ? 'updateTime ASC' : 'updateTime DESC';
        break;
      case 'custom':
        orderBy = ascending ? 'sortOrder ASC' : 'sortOrder DESC';
        break;
    }
    
    const rs = await store.querySql(
      `SELECT * FROM novel_book WHERE isFavorite = 1 ORDER BY ${orderBy}`
    );
    return this.parseBookResults(rs);
  }

  /**
   * 删除书籍
   */
  async deleteBook(bookId: string): Promise<void> {
    const store = this.getStore();
    // 删除相关章节缓存
    await store.executeSql(
      'DELETE FROM novel_content_cache WHERE chapterId IN (SELECT id FROM novel_chapter WHERE bookId = ?)',
      [bookId]
    );
    // 删除章节
    await store.executeSql('DELETE FROM novel_chapter WHERE bookId = ?', [bookId]);
    // 删除阅读进度
    await store.executeSql('DELETE FROM novel_read_progress WHERE bookId = ?', [bookId]);
    // 删除书籍
    await store.executeSql('DELETE FROM novel_book WHERE id = ?', [bookId]);
    logger.info(TAG, `删除书籍: ${bookId}`);
  }

  /**
   * 批量删除书籍
   */
  async deleteBooksBatch(bookIds: string[]): Promise<void> {
    for (const bookId of bookIds) {
      await this.deleteBook(bookId);
    }
  }

  /**
   * 取消收藏
   */
  async unfavoriteBook(bookId: string): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET isFavorite = 0, updateTime = ? WHERE id = ?',
      [Date.now(), bookId]
    );
  }

  /**
   * 获取书籍详情
   */
  async getBook(bookId: string): Promise<NovelBook | null> {
    const store = this.getStore();
    const rs = await store.querySql('SELECT * FROM novel_book WHERE id = ?', [bookId]);
    const books = this.parseBookResults(rs);
    return books.length > 0 ? books[0] : null;
  }

  /**
   * 通过URL获取书籍
   */
  async getBookByUrl(sourceId: string, bookUrl: string): Promise<NovelBook | null> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE sourceId = ? AND bookUrl = ?',
      [sourceId, bookUrl]
    );
    const books = this.parseBookResults(rs);
    return books.length > 0 ? books[0] : null;
  }

  /**
   * 更新书籍阅读时长
   * @param bookId 书籍ID
   * @param additionalTime 新增阅读时长（秒）
   */
  async updateReadingTime(bookId: string, additionalTime: number): Promise<void> {
    const store = this.getStore();
    await store.executeSql(
      'UPDATE novel_book SET totalReadingTime = totalReadingTime + ?, updateTime = ? WHERE id = ?',
      [additionalTime, Date.now(), bookId]
    );
    logger.debug(TAG, `更新书籍阅读时长: ${bookId}, 新增 ${additionalTime} 秒`);
  }

  /**
   * 获取所有有阅读记录的书籍（用于阅读统计）
   */
  async getBooksWithReadingTime(): Promise<NovelBook[]> {
    const store = this.getStore();
    const rs = await store.querySql(
      'SELECT * FROM novel_book WHERE totalReadingTime > 0 OR lastReadTime > 0 ORDER BY lastReadTime DESC'
    );
    return this.parseBookResults(rs);
  }

  // ==================== 工具方法 ====================

  private generateId(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}

export function getNovelDataManager(): NovelDataManager {
  return NovelDataManager.getInstance();
}

export { NovelBook };
