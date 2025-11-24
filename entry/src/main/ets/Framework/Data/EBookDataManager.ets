// 文件路径: entry/src/main/ets/Framework/Data/EBookDataManager.ets
/**
 * 电子书数据管理器
 * 负责电子书的数据库操作
 */

import { DatabaseManager } from '../Database/DatabaseManager';
import { DatabaseRecord } from '../Database/DatabaseTypes';
import { EBook, EBookChapter, EBookReadingProgress, EBookReadingSettings, EBookFormat, EBookStatus, EBookPageMode } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';

const TAG = 'EBookDataManager';

/**
 * 从DatabaseRecord安全地获取字段值
 * 使用Reflect.get避免索引访问限制
 */
function getRecordValue(record: DatabaseRecord, fieldName: string, defaultValue: string | number): string | number {
  try {
    const value: string | number | null | undefined = Reflect.get(record, fieldName) as string | number | null | undefined;
    if (value !== null && value !== undefined) {
      return value as string | number;
    }
  } catch (e) {
    logger.warn(TAG, `获取字段${fieldName}失败: ${String(e)}`);
  }
  return defaultValue;
}

/**
 * 电子书数据管理器单例
 */
export class EBookDataManager {
  private static instance: EBookDataManager;
  private dbManager: DatabaseManager;

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
  }

  public static getInstance(): EBookDataManager {
    if (!EBookDataManager.instance) {
      EBookDataManager.instance = new EBookDataManager();
    }
    return EBookDataManager.instance;
  }

  /**
   * 保存电子书信息到数据库
   */
  public async saveEBook(ebook: EBook): Promise<void> {
    try {
      logger.info(TAG, `开始保存电子书: ${ebook.metadata.title}`);

      // 1. 保存电子书基本信息
      await this.saveEBookInfo(ebook);

      // 2. 保存章节信息
      for (const chapter of ebook.chapters) {
        await this.saveEBookChapter(chapter);
      }

      // 3. 保存阅读进度
      await this.saveReadingProgress(ebook.readingProgress);

      // 4. 保存阅读设置
      await this.saveReadingSettings(ebook.id, ebook.readingSettings);

      logger.info(TAG, `电子书保存成功: ${ebook.metadata.title}`);
    } catch (error) {
      logger.error(TAG, `保存电子书失败: ${String(error instanceof Error ? error.message : error)}`);
      throw error as Error;
    }
  }

  /**
   * 保存电子书基本信息
   */
  private async saveEBookInfo(ebook: EBook): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_info (
        id, format, filePath, fileSize, title, author, publisher, publishDate,
        isbn, language, description, coverImagePath, tags, rating, status,
        isFavorite, totalWordCount, addTime, lastUpdateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const params = [
      ebook.id,
      ebook.format,
      ebook.filePath,
      ebook.fileSize,
      ebook.metadata.title,
      ebook.metadata.author,
      ebook.metadata.publisher,
      ebook.metadata.publishDate,
      ebook.metadata.isbn,
      ebook.metadata.language,
      ebook.metadata.description,
      ebook.metadata.coverImagePath,
      JSON.stringify(ebook.metadata.tags),
      ebook.metadata.rating,
      ebook.status,
      ebook.isFavorite ? 1 : 0,
      ebook.totalWordCount,
      ebook.addTime,
      ebook.lastUpdateTime
    ];

    await this.dbManager.executeSql(sql, params);
  }

  /**
   * 保存章节信息
   */
  private async saveEBookChapter(chapter: EBookChapter): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_chapter (
        id, bookId, chapterNumber, title, content, startPosition,
        endPosition, wordCount, createTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const params = [
      chapter.id,
      chapter.bookId,
      chapter.chapterNumber,
      chapter.title,
      chapter.content,
      chapter.startPosition,
      chapter.endPosition,
      chapter.wordCount,
      chapter.createTime
    ];

    await this.dbManager.executeSql(sql, params);
  }

  /**
   * 保存阅读进度
   */
  public async saveReadingProgress(progress: EBookReadingProgress): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_reading_progress (
        bookId, userId, currentChapterId, currentPosition, progress,
        lastReadTime, totalReadingTime, createTime, updateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const now = Date.now();
    const params = [
      progress.bookId,
      'default_user',
      progress.currentChapterId,
      progress.currentPosition,
      progress.progress,
      progress.lastReadTime,
      progress.totalReadingTime,
      now,
      now
    ];

    await this.dbManager.executeSql(sql, params);
  }

  /**
   * 保存阅读设置
   */
  public async saveReadingSettings(bookId: string, settings: EBookReadingSettings): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_reading_settings (
        bookId, userId, fontSize, lineHeight, fontFamily, backgroundColor,
        textColor, pageMargin, pageMode, brightness, autoSave, saveInterval,
        createTime, updateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const now = Date.now();
    const params = [
      bookId,
      'default_user',
      settings.fontSize,
      settings.lineHeight,
      settings.fontFamily,
      settings.backgroundColor,
      settings.textColor,
      settings.pageMargin,
      settings.pageMode,
      settings.brightness,
      settings.autoSave ? 1 : 0,
      settings.saveInterval,
      now,
      now
    ];

    await this.dbManager.executeSql(sql, params);
  }

  /**
   * 获取电子书列表
   */
  public async getEBookList(): Promise<EBook[]> {
    try {
      const sql = `SELECT * FROM ebook_info ORDER BY lastUpdateTime DESC`;
      const records = await this.dbManager.querySql(sql, []);
      
      const ebooks: EBook[] = [];
      
      for (const record of records) {
        const ebook = await this.buildEBookFromRecord(record);
        ebooks.push(ebook);
      }

      logger.info(TAG, `查询到 ${ebooks.length} 本电子书`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `获取电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * 根据ID获取电子书
   */
  public async getEBookById(id: string): Promise<EBook | null> {
    try {
      const sql = `SELECT * FROM ebook_info WHERE id = ?`;
      const records = await this.dbManager.querySql(sql, [id]);
      
      if (records && records.length > 0) {
        return await this.buildEBookFromRecord(records[0]);
      }

      return null;
    } catch (error) {
      logger.error(TAG, `获取电子书失败: ${String(error instanceof Error ? error.message : error)}`);
      return null;
    }
  }

  /**
   * 从数据库记录构建EBook对象
   */
  private async buildEBookFromRecord(record: DatabaseRecord): Promise<EBook> {
    const id = String(getRecordValue(record, 'id', ''));
    const format = String(getRecordValue(record, 'format', '')) as EBookFormat;
    const filePath = String(getRecordValue(record, 'filePath', ''));
    const fileSize = Number(getRecordValue(record, 'fileSize', 0));
    const title = String(getRecordValue(record, 'title', ''));
    const author = String(getRecordValue(record, 'author', ''));
    const publisher = String(getRecordValue(record, 'publisher', ''));
    const publishDate = String(getRecordValue(record, 'publishDate', ''));
    const isbn = String(getRecordValue(record, 'isbn', ''));
    const language = String(getRecordValue(record, 'language', ''));
    const description = String(getRecordValue(record, 'description', ''));
    const coverImagePath = String(getRecordValue(record, 'coverImagePath', ''));
    const tagsJson = String(getRecordValue(record, 'tags', '[]'));
    const rating = Number(getRecordValue(record, 'rating', 0));
    const status = String(getRecordValue(record, 'status', 'UNREAD')) as EBookStatus;
    const isFavorite = Number(getRecordValue(record, 'isFavorite', 0)) === 1;
    const totalWordCount = Number(getRecordValue(record, 'totalWordCount', 0));
    const addTime = Number(getRecordValue(record, 'addTime', 0));
    const lastUpdateTime = Number(getRecordValue(record, 'lastUpdateTime', 0));

    const tags = JSON.parse(tagsJson) as string[];

    // 获取章节列表
    const chapters = await this.getChaptersByBookId(id);

    // 获取阅读进度
    const readingProgress = await this.getReadingProgress(id);

    // 获取阅读设置
    const readingSettings = await this.getReadingSettings(id);

    return new EBook(
      id,
      format,
      filePath,
      fileSize,
      {
        title,
        author,
        publisher,
        publishDate,
        isbn,
        language,
        description,
        coverImagePath,
        tags,
        rating
      },
      chapters,
      status,
      readingProgress,
      readingSettings,
      addTime,
      lastUpdateTime,
      isFavorite,
      totalWordCount
    );
  }

  /**
   * 获取章节列表
   */
  private async getChaptersByBookId(bookId: string): Promise<EBookChapter[]> {
    try {
      const sql = `SELECT * FROM ebook_chapter WHERE bookId = ? ORDER BY chapterNumber ASC`;
      const records = await this.dbManager.querySql(sql, [bookId]);
      
      const chapters: EBookChapter[] = [];
      
      for (const record of records) {
        const chapter: EBookChapter = {
          id: String(getRecordValue(record, 'id', '')),
          bookId: String(getRecordValue(record, 'bookId', '')),
          chapterNumber: Number(getRecordValue(record, 'chapterNumber', 0)),
          title: String(getRecordValue(record, 'title', '')),
          content: String(getRecordValue(record, 'content', '')),
          startPosition: Number(getRecordValue(record, 'startPosition', 0)),
          endPosition: Number(getRecordValue(record, 'endPosition', 0)),
          wordCount: Number(getRecordValue(record, 'wordCount', 0)),
          createTime: Number(getRecordValue(record, 'createTime', 0))
        };
        chapters.push(chapter);
      }

      return chapters;
    } catch (error) {
      logger.error(TAG, `获取章节列表失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * 获取阅读进度
   */
  private async getReadingProgress(bookId: string): Promise<EBookReadingProgress | null> {
    try {
      const sql = `SELECT * FROM ebook_reading_progress WHERE bookId = ? AND userId = ?`;
      const records = await this.dbManager.querySql(sql, [bookId, 'default_user']);
      
      if (records && records.length > 0) {
        const record = records[0];
        return {
          bookId: String(getRecordValue(record, 'bookId', '')),
          currentChapterId: String(getRecordValue(record, 'currentChapterId', '')),
          currentPosition: Number(getRecordValue(record, 'currentPosition', 0)),
          progress: Number(getRecordValue(record, 'progress', 0)),
          lastReadTime: Number(getRecordValue(record, 'lastReadTime', 0)),
          totalReadingTime: Number(getRecordValue(record, 'totalReadingTime', 0))
        };
      }

      return null;
    } catch (error) {
      logger.error(TAG, `获取阅读进度失败: ${String(error instanceof Error ? error.message : error)}`);
      return null;
    }
  }

  /**
   * 获取阅读设置
   */
  private async getReadingSettings(bookId: string): Promise<EBookReadingSettings | null> {
    try {
      const sql = `SELECT * FROM ebook_reading_settings WHERE bookId = ? AND userId = ?`;
      const records = await this.dbManager.querySql(sql, [bookId, 'default_user']);
      
      if (records && records.length > 0) {
        const record = records[0];
        const pageModeValue = String(getRecordValue(record, 'pageMode', 'PAGE'));
        
        return {
          fontSize: Number(getRecordValue(record, 'fontSize', 18)),
          lineHeight: Number(getRecordValue(record, 'lineHeight', 1.8)),
          fontFamily: String(getRecordValue(record, 'fontFamily', 'HarmonyOS Sans')),
          backgroundColor: String(getRecordValue(record, 'backgroundColor', '#FFFFFF')),
          textColor: String(getRecordValue(record, 'textColor', '#333333')),
          pageMargin: Number(getRecordValue(record, 'pageMargin', 20)),
          pageMode: pageModeValue as EBookPageMode,
          brightness: Number(getRecordValue(record, 'brightness', 100)),
          autoSave: Number(getRecordValue(record, 'autoSave', 1)) === 1,
          saveInterval: Number(getRecordValue(record, 'saveInterval', 30))
        };
      }

      return null;
    } catch (error) {
      logger.error(TAG, `获取阅读设置失败: ${String(error instanceof Error ? error.message : error)}`);
      return null;
    }
  }

  /**
   * 删除电子书
   */
  public async deleteEBook(bookId: string): Promise<void> {
    try {
      // 删除章节
      await this.dbManager.executeSql(`DELETE FROM ebook_chapter WHERE bookId = ?`, [bookId]);
      
      // 删除阅读进度
      await this.dbManager.executeSql(`DELETE FROM ebook_reading_progress WHERE bookId = ?`, [bookId]);
      
      // 删除阅读设置
      await this.dbManager.executeSql(`DELETE FROM ebook_reading_settings WHERE bookId = ?`, [bookId]);
      
      // 删除电子书信息
      await this.dbManager.executeSql(`DELETE FROM ebook_info WHERE id = ?`, [bookId]);
      
      logger.info(TAG, `成功删除电子书: ${bookId}`);
    } catch (error) {
      logger.error(TAG, `删除电子书失败: ${String(error instanceof Error ? error.message : error)}`);
      throw error as Error;
    }
  }
}

