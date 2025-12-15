// 文件路径: entry/src/main/ets/Framework/Data/EBookDataManager.ets
/**
 * 电子书数据管理器
 * 负责电子书的数据库操作
 */

import { DatabaseManager } from '../Database/DatabaseManager';
import { DatabaseRecord } from '../Database/DatabaseTypes';
import { EBook, EBookChapter, EBookReadingProgress, EBookReadingSettings, EBookFormat, EBookStatus, EBookPageMode } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';
import { PRESET_BACKGROUNDS } from '../../Models/TextReaderModels';

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

  private settingsColumnsChecked: boolean = false;

  /**
   * 确保 ebook_reading_settings 表有所有需要的列
   * 注意：暂时移除缓存检查，确保每次都执行列检查
   */
  private async ensureSettingsColumns(): Promise<void> {
    // 暂时禁用缓存，确保每次都检查
    // if (this.settingsColumnsChecked) {
    //   return;
    // }
    
    try {
      logger.info(TAG, '检查 ebook_reading_settings 表列...');
      const result = await this.dbManager.querySql("PRAGMA table_info('ebook_reading_settings')", []);
      
      // 收集已存在的列名
      const existingColumns: Set<string> = new Set();
      for (const row of result) {
        const colName = String(getRecordValue(row, 'name', ''));
        existingColumns.add(colName);
      }
      
      logger.info(TAG, `已存在的列: ${Array.from(existingColumns).join(', ')}`);
      
      // 需要检查的新列及其定义
      interface ColumnDef {
        name: string;
        definition: string;
      }
      
      const requiredColumns: ColumnDef[] = [
        { name: 'letterSpacing', definition: 'REAL DEFAULT 0' },
        { name: 'paragraphSpacing', definition: 'INTEGER DEFAULT 8' },
        { name: 'firstLineIndent', definition: 'INTEGER DEFAULT 2' },
        { name: 'textAlignment', definition: "TEXT DEFAULT 'JUSTIFY'" },
        { name: 'pageTurnAnimation', definition: "TEXT DEFAULT 'SLIDE'" },
        { name: 'tapToTurn', definition: 'INTEGER DEFAULT 1' },
        { name: 'volumeKeyNavigation', definition: 'INTEGER DEFAULT 1' },
        { name: 'keepScreenOn', definition: 'INTEGER DEFAULT 0' },
        { name: 'showPageNumber', definition: 'INTEGER DEFAULT 1' },
        { name: 'showProgress', definition: 'INTEGER DEFAULT 0' },
        { name: 'showTime', definition: 'INTEGER DEFAULT 1' },
        { name: 'showBattery', definition: 'INTEGER DEFAULT 0' },
        { name: 'backgroundType', definition: "TEXT DEFAULT 'COLOR'" },
        { name: 'backgroundImagePath', definition: "TEXT DEFAULT ''" },
        { name: 'backgroundImageOpacity', definition: 'REAL DEFAULT 0.3' }
      ];
      
      for (const col of requiredColumns) {
        if (!existingColumns.has(col.name)) {
          try {
            const alterSql = `ALTER TABLE ebook_reading_settings ADD COLUMN ${col.name} ${col.definition}`;
            await this.dbManager.executeSql(alterSql, []);
            logger.info(TAG, `✅ 已添加列: ${col.name}`);
          } catch (e) {
            logger.warn(TAG, `添加 ${col.name} 列失败: ${String(e)}`);
          }
        }
      }
      
      this.settingsColumnsChecked = true;
    } catch (error) {
      logger.error(TAG, `检查设置表列失败: ${String(error)}`);
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
   * 保存阅读设置（包含纯文本阅读器专用设置）
   * 使用 DELETE + 单次完整 INSERT 策略，避免 UPDATE 静默失败问题
   * 新电子书会自动应用全局设置
   */
  public async saveReadingSettings(bookId: string, settings: EBookReadingSettings): Promise<void> {
    // 首次保存时检查并添加缺失的列
    await this.ensureSettingsColumns();
    
    const now = Date.now();
    
    // 检查是否是新记录（没有自定义设置），如果是则应用全局设置
    const finalSettings = await this.applyGlobalSettingsIfNew(settings);
    
    try {
      // 1. 先删除旧记录
      const deleteSql = `DELETE FROM ebook_reading_settings WHERE bookId = ? AND userId = ?`;
      await this.dbManager.executeSql(deleteSql, [bookId, 'default_user']);
      logger.debug(TAG, `阅读设置旧记录已删除: bookId=${bookId}`);
      
      const bgType = finalSettings.backgroundType ?? 'COLOR';
      const bgImagePath = finalSettings.backgroundImagePath ?? '';
      const bgImageOpacity = finalSettings.backgroundImageOpacity ?? 0.3;
      
      // 2. 单次完整 INSERT 所有字段（UPDATE 在 HarmonyOS RdbStore 中会静默失败）
      const insertSql = `
        INSERT INTO ebook_reading_settings (
          bookId, userId, fontSize, fontFamily, fontPath, fontWeight, lineHeight,
          backgroundColor, textColor, themeBgImage, nightMode, followSystemTheme,
          pageMargin, pageMode, brightness, autoSave, saveInterval,
          letterSpacing, paragraphSpacing, firstLineIndent, textAlignment,
          pageTurnAnimation, tapToTurn, volumeKeyNavigation, keepScreenOn,
          showPageNumber, showProgress, showTime, showBattery,
          backgroundType, backgroundImagePath, backgroundImageOpacity,
          createTime, updateTime
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;

      const insertParams: (string | number)[] = [
        bookId,
        'default_user',
        finalSettings.fontSize,
        finalSettings.fontFamily,
        finalSettings.fontPath || '',
        finalSettings.fontWeight || 400,
        finalSettings.lineHeight,
        finalSettings.backgroundColor,
        finalSettings.textColor,
        finalSettings.themeBgImage || '',
        finalSettings.nightMode ? 1 : 0,
        finalSettings.followSystemTheme !== false ? 1 : 0,
        finalSettings.pageMargin,
        finalSettings.pageMode,
        finalSettings.brightness,
        finalSettings.autoSave ? 1 : 0,
        finalSettings.saveInterval,
        // 扩展字段
        finalSettings.letterSpacing ?? 0,
        finalSettings.paragraphSpacing ?? 8,
        finalSettings.firstLineIndent ?? 2,
        finalSettings.textAlignment ?? 'JUSTIFY',
        finalSettings.pageTurnAnimation ?? 'SLIDE',
        finalSettings.tapToTurn !== false ? 1 : 0,
        finalSettings.volumeKeyNavigation !== false ? 1 : 0,
        finalSettings.keepScreenOn ? 1 : 0,
        finalSettings.showPageNumber !== false ? 1 : 0,
        finalSettings.showProgress ? 1 : 0,
        finalSettings.showTime !== false ? 1 : 0,
        finalSettings.showBattery ? 1 : 0,
        bgType,
        bgImagePath,
        bgImageOpacity,
        now,
        now
      ];
      
      logger.info(TAG, `INSERT 参数数量: ${insertParams.length}, bgType=${bgType}, bgImagePath=${bgImagePath}`);
      await this.dbManager.executeSql(insertSql, insertParams);
      logger.info(TAG, `阅读设置完整插入成功: bookId=${bookId}`);
      
      // 3. 验证保存结果 - 使用显式字段名查询（SELECT * 可能不返回通过 UPDATE 添加的字段）
      const verifySql = `SELECT backgroundType, backgroundImagePath, backgroundImageOpacity, volumeKeyNavigation FROM ebook_reading_settings WHERE bookId = ? AND userId = ?`;
      const verifyResult = await this.dbManager.querySql(verifySql, [bookId, 'default_user']);
      
      if (verifyResult && verifyResult.length > 0) {
        const record = verifyResult[0];
        
        // 打印完整记录的所有键，用于调试
        const recordKeys = Object.keys(record);
        logger.info(TAG, `验证记录的字段列表: ${recordKeys.join(', ')}`);
        
        const savedBgType = String(getRecordValue(record, 'backgroundType', 'COLOR'));
        const savedBgImagePath = String(getRecordValue(record, 'backgroundImagePath', ''));
        const savedVolumeKey = Number(getRecordValue(record, 'volumeKeyNavigation', 1)) === 1;
        
        logger.info(TAG, `阅读设置验证: savedBgType=${savedBgType}, savedBgImagePath=${savedBgImagePath}, savedVolumeKey=${savedVolumeKey}`);
        
        if (savedBgType !== bgType || savedBgImagePath !== bgImagePath) {
          logger.error(TAG, `❌ 阅读设置验证失败! 期望: bgType=${bgType}, bgImagePath=${bgImagePath}; 实际: bgType=${savedBgType}, bgImagePath=${savedBgImagePath}`);
        } else {
          logger.info(TAG, `✅ 阅读设置保存成功`);
        }
      } else {
        logger.error(TAG, `❌ 阅读设置验证失败! 未找到记录`);
      }
      
    } catch (error) {
      logger.error(TAG, `保存阅读设置失败: ${String(error)}`);
    }
  }

  /**
   * 对于新电子书，应用全局设置中的纯文本阅读器默认值
   * 检测方式：如果设置是默认值（没有自定义背景图片路径），则应用全局设置
   */
  private async applyGlobalSettingsIfNew(settings: EBookReadingSettings): Promise<EBookReadingSettings> {
    try {
      const settingsManager = SettingsManager.getInstance();
      
      // 检查是否使用全局背景图片设置
      const useGlobalBgImage = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
      const globalBgImagePath = settingsManager.getString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, '');
      const globalBgImageOpacity = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, 0.3);
      
      // 如果全局设置启用了背景图片，并且当前设置没有自定义背景图片，则应用全局设置
      if (useGlobalBgImage && globalBgImagePath && globalBgImagePath.length > 0 && !settings.backgroundImagePath) {
        logger.info(TAG, `应用全局背景图片设置: ${globalBgImagePath}`);
        
        // 获取其他全局设置
        const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, settings.fontSize);
        const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, settings.lineHeight);
        const globalParagraphSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, settings.paragraphSpacing ?? 8);
        const globalFirstLineIndent = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, settings.firstLineIndent ?? 2);
        const globalLetterSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LETTER_SPACING, settings.letterSpacing ?? 0);
        const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, settings.pageMargin);
        const globalBgColorIndex = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, 0);
        const globalPageTurnAnimation = settingsManager.getString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, settings.pageTurnAnimation ?? 'SLIDE');
        const globalKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, settings.keepScreenOn ?? true);
        const globalVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, settings.volumeKeyNavigation ?? true);
        const globalTapToTurn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, settings.tapToTurn ?? true);
        
        // 获取预设背景的颜色
        const preset = PRESET_BACKGROUNDS[globalBgColorIndex] || PRESET_BACKGROUNDS[0];
        
        const result: EBookReadingSettings = {
          fontSize: globalFontSize,
          fontFamily: settings.fontFamily,
          fontPath: settings.fontPath,
          fontWeight: settings.fontWeight,
          lineHeight: globalLineHeight,
          backgroundColor: preset.backgroundColor,
          textColor: preset.textColor,
          themeBgImage: settings.themeBgImage,
          nightMode: settings.nightMode,
          followSystemTheme: settings.followSystemTheme,
          pageMargin: globalPageMargin,
          pageMode: settings.pageMode,
          brightness: settings.brightness,
          autoSave: settings.autoSave,
          saveInterval: settings.saveInterval,
          paragraphSpacing: globalParagraphSpacing,
          firstLineIndent: globalFirstLineIndent,
          letterSpacing: globalLetterSpacing,
          textAlignment: settings.textAlignment,
          pageTurnAnimation: globalPageTurnAnimation,
          tapToTurn: globalTapToTurn,
          volumeKeyNavigation: globalVolumeKeyNav,
          keepScreenOn: globalKeepScreenOn,
          showPageNumber: settings.showPageNumber,
          showProgress: settings.showProgress,
          showTime: settings.showTime,
          showBattery: settings.showBattery,
          backgroundType: 'IMAGE',
          backgroundImagePath: globalBgImagePath,
          backgroundImageOpacity: globalBgImageOpacity
        };
        return result;
      }
      
      // 即使没有启用背景图片，也应用其他全局设置（如果当前是默认设置）
      if (!settings.backgroundImagePath) {
        const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, settings.fontSize);
        const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, settings.lineHeight);
        const globalParagraphSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, settings.paragraphSpacing ?? 8);
        const globalFirstLineIndent = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, settings.firstLineIndent ?? 2);
        const globalLetterSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LETTER_SPACING, settings.letterSpacing ?? 0);
        const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, settings.pageMargin);
        const globalBgColorIndex = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, 0);
        const globalPageTurnAnimation = settingsManager.getString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, settings.pageTurnAnimation ?? 'SLIDE');
        const globalKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, settings.keepScreenOn ?? true);
        const globalVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, settings.volumeKeyNavigation ?? true);
        const globalTapToTurn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, settings.tapToTurn ?? true);
        
        // 获取预设背景的颜色
        const preset = PRESET_BACKGROUNDS[globalBgColorIndex] || PRESET_BACKGROUNDS[0];
        
        logger.info(TAG, `应用全局纯色背景设置: bgColor=${preset.backgroundColor}, textColor=${preset.textColor}`);
        
        const result: EBookReadingSettings = {
          fontSize: globalFontSize,
          fontFamily: settings.fontFamily,
          fontPath: settings.fontPath,
          fontWeight: settings.fontWeight,
          lineHeight: globalLineHeight,
          backgroundColor: preset.backgroundColor,
          textColor: preset.textColor,
          themeBgImage: settings.themeBgImage,
          nightMode: settings.nightMode,
          followSystemTheme: settings.followSystemTheme,
          pageMargin: globalPageMargin,
          pageMode: settings.pageMode,
          brightness: settings.brightness,
          autoSave: settings.autoSave,
          saveInterval: settings.saveInterval,
          paragraphSpacing: globalParagraphSpacing,
          firstLineIndent: globalFirstLineIndent,
          letterSpacing: globalLetterSpacing,
          textAlignment: settings.textAlignment,
          pageTurnAnimation: globalPageTurnAnimation,
          tapToTurn: globalTapToTurn,
          volumeKeyNavigation: globalVolumeKeyNav,
          keepScreenOn: globalKeepScreenOn,
          showPageNumber: settings.showPageNumber,
          showProgress: settings.showProgress,
          showTime: settings.showTime,
          showBattery: settings.showBattery,
          backgroundType: settings.backgroundType,
          backgroundImagePath: settings.backgroundImagePath,
          backgroundImageOpacity: settings.backgroundImageOpacity
        };
        return result;
      }
      
      return settings;
    } catch (error) {
      logger.error(TAG, `应用全局设置失败: ${String(error)}`);
      return settings;
    }
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
   * 获取所有有阅读记录的电子书及其阅读进度
   * 用于阅读报告统计
   */
  public async getEBooksWithReadingProgress(): Promise<EBook[]> {
    try {
      const allEbooks = await this.getEBookList();
      // 筛选有阅读进度的电子书
      const ebooksWithProgress = allEbooks.filter((ebook: EBook) => {
        if (!ebook.readingProgress) {
          return false;
        }
        // 检查是否有真正的阅读进度
        const hasDomPos = ebook.readingProgress.domPos && ebook.readingProgress.domPos.length > 0;
        const hasChapterProgress = ebook.readingProgress.currentChapterIndex > 0;
        const hasProgress = ebook.readingProgress.progress > 0;
        return hasDomPos || hasChapterProgress || hasProgress;
      });
      
      logger.info(TAG, `获取到 ${ebooksWithProgress.length} 本有阅读记录的电子书`);
      return ebooksWithProgress;
    } catch (error) {
      logger.error(TAG, `获取电子书阅读进度失败: ${String(error instanceof Error ? error.message : error)}`);
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

    // 根据阅读进度动态计算正确的状态
    let finalStatus = status;
    if (readingProgress) {
      const hasProgress = readingProgress.progress > 0 || 
                          readingProgress.currentPosition > 0 || 
                          readingProgress.currentChapterIndex > 0 ||
                          (readingProgress.domPos && readingProgress.domPos.length > 0);
      
      if (readingProgress.progress >= 100) {
        finalStatus = EBookStatus.COMPLETED;
      } else if (hasProgress) {
        finalStatus = EBookStatus.READING;
      }
    }

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
      finalStatus,
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
   * 获取阅读设置（包含纯文本阅读器专用设置）
   */
  private async getReadingSettings(bookId: string): Promise<EBookReadingSettings | null> {
    // 确保表结构完整
    await this.ensureSettingsColumns();
    
    try {
      // 使用显式字段名查询（SELECT * 可能不返回通过 ALTER TABLE 或 UPDATE 添加的字段）
      const sql = `SELECT 
        bookId, userId, fontSize, fontFamily, fontPath, fontWeight, lineHeight,
        backgroundColor, textColor, themeBgImage, nightMode, followSystemTheme,
        pageMargin, pageMode, brightness, autoSave, saveInterval,
        letterSpacing, paragraphSpacing, firstLineIndent, textAlignment,
        pageTurnAnimation, tapToTurn, volumeKeyNavigation, keepScreenOn,
        showPageNumber, showProgress, showTime, showBattery,
        backgroundType, backgroundImagePath, backgroundImageOpacity
      FROM ebook_reading_settings WHERE bookId = ? AND userId = ?`;
      const records = await this.dbManager.querySql(sql, [bookId, 'default_user']);
      
      if (records && records.length > 0) {
        const record = records[0];
        const pageModeValue = String(getRecordValue(record, 'pageMode', '0'));
        
        const settings: EBookReadingSettings = {
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
          saveInterval: Number(getRecordValue(record, 'saveInterval', 30)),
          // ========== 纯文本阅读器专用设置 ==========
          // 高级字体设置
          letterSpacing: Number(getRecordValue(record, 'letterSpacing', 0)),
          paragraphSpacing: Number(getRecordValue(record, 'paragraphSpacing', 8)),
          firstLineIndent: Number(getRecordValue(record, 'firstLineIndent', 2)),
          textAlignment: String(getRecordValue(record, 'textAlignment', 'JUSTIFY')),
          // 翻页动画设置
          pageTurnAnimation: String(getRecordValue(record, 'pageTurnAnimation', 'SLIDE')),
          tapToTurn: Number(getRecordValue(record, 'tapToTurn', 1)) === 1,
          volumeKeyNavigation: Number(getRecordValue(record, 'volumeKeyNavigation', 1)) === 1,
          keepScreenOn: Number(getRecordValue(record, 'keepScreenOn', 0)) === 1,
          // 显示设置
          showPageNumber: Number(getRecordValue(record, 'showPageNumber', 1)) === 1,
          showProgress: Number(getRecordValue(record, 'showProgress', 0)) === 1,
          showTime: Number(getRecordValue(record, 'showTime', 1)) === 1,
          showBattery: Number(getRecordValue(record, 'showBattery', 0)) === 1,
          // 背景设置
          backgroundType: String(getRecordValue(record, 'backgroundType', 'COLOR')),
          backgroundImagePath: String(getRecordValue(record, 'backgroundImagePath', '')),
          backgroundImageOpacity: Number(getRecordValue(record, 'backgroundImageOpacity', 0.3))
        };
        
        logger.info(TAG, `读取阅读设置: volumeKeyNavigation=${settings.volumeKeyNavigation}, tapToTurn=${settings.tapToTurn}, bgType=${settings.backgroundType}, bgColor=${settings.backgroundColor}, textColor=${settings.textColor}, bgImagePath=${settings.backgroundImagePath}, followSystemTheme=${settings.followSystemTheme}`);
        return settings;
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

