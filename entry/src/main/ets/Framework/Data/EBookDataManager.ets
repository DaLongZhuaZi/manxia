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
  private columnsChecked: boolean = false;

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
   * 确保 ebook_reading_progress 表有 domPos 和 currentChapterIndex 列
   */
  private async ensureProgressColumns(): Promise<void> {
    if (this.columnsChecked) {
      return;
    }
    
    try {
      logger.info(TAG, '检查 ebook_reading_progress 表列...');
      const result = await this.dbManager.querySql("PRAGMA table_info('ebook_reading_progress')", []);
      
      let hasDomPos = false;
      let hasCurrentChapterIndex = false;
      
      for (const row of result) {
        const colName = String(getRecordValue(row, 'name', ''));
        if (colName === 'domPos') { hasDomPos = true; }
        if (colName === 'currentChapterIndex') { hasCurrentChapterIndex = true; }
      }
      
      logger.info(TAG, `列检查结果: hasDomPos=${hasDomPos}, hasCurrentChapterIndex=${hasCurrentChapterIndex}`);
      
      if (!hasCurrentChapterIndex) {
        try {
          await this.dbManager.executeSql("ALTER TABLE ebook_reading_progress ADD COLUMN currentChapterIndex INTEGER DEFAULT 0", []);
          logger.info(TAG, '已添加 currentChapterIndex 列');
        } catch (e) {
          logger.warn(TAG, `添加 currentChapterIndex 列失败: ${String(e)}`);
        }
      }
      
      if (!hasDomPos) {
        try {
          await this.dbManager.executeSql("ALTER TABLE ebook_reading_progress ADD COLUMN domPos TEXT DEFAULT ''", []);
          logger.info(TAG, '已添加 domPos 列');
        } catch (e) {
          logger.warn(TAG, `添加 domPos 列失败: ${String(e)}`);
        }
      }
      
      this.columnsChecked = true;
    } catch (error) {
      logger.error(TAG, `检查列失败: ${String(error)}`);
    }
  }

  /**
   * 保存阅读进度
   * 使用 DELETE + 单次完整 INSERT 策略，避免 UPDATE 静默失败问题
   * 参考：HarmonyOS RdbStore UPDATE 语句存在静默失败的已知问题
   */
  public async saveReadingProgress(progress: EBookReadingProgress): Promise<void> {
    // 首次保存时检查并添加缺失的列
    await this.ensureProgressColumns();
    
    const domPosValue = progress.domPos || '';
    const chapterIndexValue = progress.currentChapterIndex || 0;
    
    // 详细日志：记录保存的数据
    logger.info(TAG, `保存阅读进度: bookId=${progress.bookId}, chapterIndex=${chapterIndexValue}, domPos长度=${domPosValue.length}`);
    
    const now = Date.now();
    
    try {
      // 1. 先删除旧记录
      const deleteSql = `DELETE FROM ebook_reading_progress WHERE bookId = ? AND userId = ?`;
      await this.dbManager.executeSql(deleteSql, [progress.bookId, 'default_user']);
      logger.debug(TAG, `旧记录已删除`);
      
      // 2. 一次性插入完整记录（包含所有字段，避免使用 UPDATE）
      // 关键：将 currentChapterIndex 和 domPos 直接包含在 INSERT 语句中
      const insertSql = `
        INSERT INTO ebook_reading_progress (
          bookId, userId, currentChapterId, currentChapterIndex, currentPosition,
          domPos, progress, lastReadTime, totalReadingTime, createTime, updateTime
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;
      
      const insertParams = [
        progress.bookId,
        'default_user',
        progress.currentChapterId || '',
        chapterIndexValue,
        progress.currentPosition || 0,
        domPosValue,
        progress.progress || 0,
        progress.lastReadTime || now,
        progress.totalReadingTime || 0,
        now,
        now
      ];
      
      await this.dbManager.executeSql(insertSql, insertParams);
      logger.debug(TAG, `完整记录插入成功: chapterIndex=${chapterIndexValue}, domPosLen=${domPosValue.length}`);
      
      // 3. 验证保存结果
      const verifySql = `SELECT currentChapterIndex, domPos FROM ebook_reading_progress WHERE bookId = ? AND userId = ?`;
      const verifyResult = await this.dbManager.querySql(verifySql, [progress.bookId, 'default_user']);
      
      if (verifyResult && verifyResult.length > 0) {
        const record = verifyResult[0];
        const savedChapterIndex = Number(getRecordValue(record, 'currentChapterIndex', 0));
        const savedDomPos = String(getRecordValue(record, 'domPos', ''));
        
        logger.info(TAG, `验证结果: savedChapterIndex=${savedChapterIndex}, savedDomPos长度=${savedDomPos.length}`);
        
        if (savedChapterIndex === chapterIndexValue && savedDomPos.length === domPosValue.length) {
          logger.info(TAG, `✅ 阅读进度保存成功`);
        } else {
          logger.error(TAG, `❌ 验证失败! 期望: index=${chapterIndexValue}, domPosLen=${domPosValue.length}; 实际: index=${savedChapterIndex}, domPosLen=${savedDomPos.length}`);
          
          // 调试：查询所有列名
          const schemaResult = await this.dbManager.querySql("PRAGMA table_info('ebook_reading_progress')", []);
          const columnNames: string[] = [];
          for (const row of schemaResult) {
            columnNames.push(String(getRecordValue(row, 'name', '')));
          }
          logger.error(TAG, `表列名: ${columnNames.join(', ')}`);
        }
      } else {
        logger.error(TAG, `❌ 验证失败! 未找到记录`);
      }
      
    } catch (error) {
      logger.error(TAG, `保存阅读进度失败: ${String(error)}`);
    }
  }

  /**
   * 保存阅读设置
   */
  public async saveReadingSettings(bookId: string, settings: EBookReadingSettings): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_reading_settings (
        bookId, userId, fontSize, fontFamily, fontPath, fontWeight, lineHeight,
        backgroundColor, textColor, themeBgImage, nightMode, followSystemTheme,
        pageMargin, pageMode, brightness, autoSave, saveInterval,
        createTime, updateTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;

    const now = Date.now();
    const params = [
      bookId,
      'default_user',
      settings.fontSize,
      settings.fontFamily,
      settings.fontPath || '',
      settings.fontWeight || 400,
      settings.lineHeight,
      settings.backgroundColor,
      settings.textColor,
      settings.themeBgImage || '',
      settings.nightMode ? 1 : 0,
      settings.followSystemTheme !== false ? 1 : 0,  // 默认为 true
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
   * 更新电子书封面
   */
  public async updateEBookCover(bookId: string, coverPath: string): Promise<void> {
    try {
      const sql = `UPDATE ebook_info SET coverImagePath = ?, lastUpdateTime = ? WHERE id = ?`;
      const now = Date.now();
      await this.dbManager.executeSql(sql, [coverPath, now, bookId]);
      logger.info(TAG, `电子书封面已更新: ${bookId} -> ${coverPath}`);
    } catch (error) {
      logger.error(TAG, `更新电子书封面失败: ${String(error)}`);
      throw error as Error;
    }
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
        const currentChapterIndex = Number(getRecordValue(record, 'currentChapterIndex', 0));
        const domPos = String(getRecordValue(record, 'domPos', ''));
        
        // 如果 domPos 包含 resourceIndex，优先使用 domPos 中的值
        let finalChapterIndex = currentChapterIndex;
        if (domPos && domPos.startsWith('{')) {
          try {
            const domPosData = JSON.parse(domPos) as Record<string, Object>;
            if (typeof domPosData['resourceIndex'] === 'number') {
              finalChapterIndex = domPosData['resourceIndex'] as number;
              logger.info(TAG, `从 domPos 中恢复章节索引: ${finalChapterIndex}`);
            }
          } catch (parseError) {
            logger.warn(TAG, `解析 domPos 失败: ${String(parseError)}`);
          }
        }
        
        logger.info(TAG, `读取阅读进度: currentChapterIndex=${currentChapterIndex}, finalChapterIndex=${finalChapterIndex}, domPos长度=${domPos.length}`);
        
        return {
          bookId: String(getRecordValue(record, 'bookId', '')),
          currentChapterId: String(getRecordValue(record, 'currentChapterId', '')),
          currentChapterIndex: finalChapterIndex,
          currentPosition: Number(getRecordValue(record, 'currentPosition', 0)),
          domPos: domPos,
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
        const pageModeValue = String(getRecordValue(record, 'pageMode', '0'));
        
        return {
          // 字体设置
          fontSize: Number(getRecordValue(record, 'fontSize', 18)),
          fontFamily: String(getRecordValue(record, 'fontFamily', 'HarmonyOS Sans')),
          fontPath: String(getRecordValue(record, 'fontPath', '')),
          fontWeight: Number(getRecordValue(record, 'fontWeight', 400)),
          // 排版设置
          lineHeight: Number(getRecordValue(record, 'lineHeight', 1.5)),
          // 颜色主题设置
          backgroundColor: String(getRecordValue(record, 'backgroundColor', '#FFFFFF')),
          textColor: String(getRecordValue(record, 'textColor', '#000000')),
          themeBgImage: String(getRecordValue(record, 'themeBgImage', '')),
          nightMode: Number(getRecordValue(record, 'nightMode', 0)) === 1,
          followSystemTheme: Number(getRecordValue(record, 'followSystemTheme', 1)) === 1,
          // 翻页设置
          pageMargin: Number(getRecordValue(record, 'pageMargin', 16)),
          pageMode: pageModeValue as EBookPageMode,
          // 系统设置
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
   * 搜索电子书
   * @param keyword 搜索关键词
   * @returns 匹配的电子书列表
   */
  public async searchEBooks(keyword: string): Promise<EBook[]> {
    try {
      const lowerKeyword = keyword.toLowerCase();
      const sql = `
        SELECT * FROM ebook_info 
        WHERE LOWER(title) LIKE ? 
           OR LOWER(author) LIKE ? 
           OR LOWER(tags) LIKE ?
        ORDER BY lastUpdateTime DESC
      `;
      const searchPattern = `%${lowerKeyword}%`;
      const records: DatabaseRecord[] = await this.dbManager.querySql(sql, [searchPattern, searchPattern, searchPattern]);
      
      const ebooks: EBook[] = [];
      for (const record of records) {
        const ebook: EBook = await this.buildEBookFromRecord(record);
        if (ebook) {
          ebooks.push(ebook);
        }
      }
      
      logger.info(TAG, `搜索电子书完成，关键词: "${keyword}"，结果: ${ebooks.length}条`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `搜索电子书失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
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

