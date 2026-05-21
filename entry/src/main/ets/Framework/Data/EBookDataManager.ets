// 文件路径: entry/src/main/ets/Framework/Data/EBookDataManager.ets
/**
 * 电子书数据管理器
 * 负责电子书的数据库操作
 */

import { DatabaseManager } from '../Database/DatabaseManager';
import { DatabaseRecord } from '../Database/DatabaseTypes';
import {
  EBook,
  EBookChapter,
  EBookReadingProgress,
  EBookReadingSettings,
  EBookFormat,
  EBookStatus,
  EBookPageMode,
  EBookContentMode,
  EBookReaderEngine,
  DEFAULT_EBOOK_READING_SETTINGS,
  EBOOK_THEME_PRESETS,
  EBookThemePreset
} from '../../Models/EBookModels';
import {
  ReadingSettings as ImageReaderSettings,
  DEFAULT_READING_SETTINGS as DEFAULT_IMAGE_READING_SETTINGS
} from '../../Models/MangaModels';
import { logger } from '../../Utils/Logger';
import { SettingsManager, SettingKeys } from '../Managers/SettingsManager';
import { getUnifiedAnnotationManager } from '../Annotations/UnifiedAnnotationManager';
import { UnifiedContentType } from '../../Models/UnifiedContentModels';
import { fileIo as fs } from '@kit.CoreFileKit';
import DownloadDirManager from '../Storage/DownloadDirManager';
import { DataManager } from './DataManager';

const TAG = 'EBookDataManager';

/**
 * 背景图片信息接口
 */
export interface BackgroundImageInfo {
  bookId: string;
  bookTitle: string;
  imagePath: string;
}

interface PendingReadingSettingsSaveState {
  latestSettings: EBookReadingSettings | null;
  runningPromise: Promise<void> | null;
}

interface PendingReadingProgressSaveState {
  latestProgress: EBookReadingProgress | null;
  runningPromise: Promise<void> | null;
}

interface PendingImageReaderSettingsSaveState {
  latestSettings: ImageReaderSettings | null;
  runningPromise: Promise<void> | null;
}

interface SaveEBookOptions {
  skipReadingSettings?: boolean;
}

interface ReadingSettingsRowSnapshot {
  id: number;
  createTime: number;
  updateTime: number;
  imageReaderSettingsJson: string;
}

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
  private readingProgressSaveStates: Map<string, PendingReadingProgressSaveState> = new Map<string, PendingReadingProgressSaveState>();
  private readingSettingsSaveStates: Map<string, PendingReadingSettingsSaveState> = new Map<string, PendingReadingSettingsSaveState>();
  private imageReaderSettingsSaveStates: Map<string, PendingImageReaderSettingsSaveState> = new Map<string, PendingImageReaderSettingsSaveState>();
  private lastKnownImageReaderSettingsSnapshots: Map<string, ImageReaderSettings> = new Map<string, ImageReaderSettings>();

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
  public async saveEBook(ebook: EBook, options: SaveEBookOptions = {}): Promise<void> {
    try {
      let preservedImageReaderSettings: ImageReaderSettings | null = null;
      let preservedImageReaderSettingsSource: string = '';
      const title = ebook.metadata?.title || ebook.id || '未知书籍';
      logger.info(TAG, `开始保存电子书: ${title}`);

      // 1. 保存电子书基本信息
      if (options.skipReadingSettings) {
        const pendingSnapshot = this.getPendingImageReaderSettingsSnapshot(ebook.id);
        if (pendingSnapshot) {
          preservedImageReaderSettings = pendingSnapshot;
          preservedImageReaderSettingsSource = 'pending_memory';
        } else {
          const rememberedSnapshot = this.getRememberedImageReaderSettingsSnapshot(ebook.id);
          if (rememberedSnapshot) {
            preservedImageReaderSettings = rememberedSnapshot;
            preservedImageReaderSettingsSource = 'memory_cache';
          } else {
            preservedImageReaderSettings = await this.getStoredImageReaderSettingsSnapshot(ebook.id);
            if (preservedImageReaderSettings) {
              preservedImageReaderSettingsSource = 'database';
            }
          }
        }

        if (preservedImageReaderSettings) {
          logger.info(
            TAG,
            `skipReadingSettings=true，已预先保留图片阅读设置快照：书籍ID=${ebook.id}，来源=${preservedImageReaderSettingsSource}，阅读模式=${preservedImageReaderSettings.readingMode}，翻页动画=${preservedImageReaderSettings.pageTurnAnimation}`
          );
        } else {
          logger.info(TAG, `skipReadingSettings=true，未检测到可保留的图片阅读设置快照：书籍ID=${ebook.id}`);
        }
      }

      await this.saveEBookInfo(ebook);

      // 2. 保存章节信息
      await this.deleteEBookChapters(ebook.id);
      for (const chapter of ebook.chapters) {
        await this.saveEBookChapter(chapter);
      }

      // 3. 保存阅读进度
      await this.saveReadingProgress(ebook.readingProgress);

      // 4. 保存阅读设置
      if (options.skipReadingSettings) {
        logger.info(TAG, `已跳过纯文本阅读设置保存：书籍ID=${ebook.id}`);
        if (preservedImageReaderSettings) {
          await this.saveImageReaderSettings(ebook.id, preservedImageReaderSettings);
          logger.info(
            TAG,
            `saveEBook 完成后已回写图片阅读设置：书籍ID=${ebook.id}，来源=${preservedImageReaderSettingsSource}`
          );
        }
      } else {
        await this.saveReadingSettings(ebook.id, ebook.readingSettings);
      }

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
    const insertSql = `
      INSERT INTO ebook_info (
        id, format, filePath, fileSize, title, author, publisher, publishDate,
        isbn, language, description, coverImagePath, tags, rating, status,
        isFavorite, totalWordCount, contentMode, preferredReaderEngine, extractedRootPath,
        addTime, lastUpdateTime, isPrivate, isNSFW
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;
    const updateSql = `
      UPDATE ebook_info SET
        format = ?, filePath = ?, fileSize = ?, title = ?, author = ?, publisher = ?, publishDate = ?,
        isbn = ?, language = ?, description = ?, coverImagePath = ?, tags = ?, rating = ?, status = ?,
        isFavorite = ?, totalWordCount = ?, contentMode = ?, preferredReaderEngine = ?, extractedRootPath = ?,
        addTime = ?, lastUpdateTime = ?, isPrivate = ?, isNSFW = ?
      WHERE id = ?
    `;

    // 安全访问metadata，防止undefined
    const metadata = ebook.metadata || {
      title: '',
      author: '',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: '',
      description: '',
      coverImagePath: '',
      tags: [] as string[],
      rating: 0
    };

    logger.info(TAG, `[封面诊断] saveEBookInfo: id=${ebook.id}, coverImagePath='${metadata.coverImagePath}'`);

    const existingRecords = await this.dbManager.querySql('SELECT id, extractedRootPath FROM ebook_info WHERE id = ? LIMIT 1', [ebook.id]);

    // Never overwrite a non-empty extractedRootPath with an empty value.
    // This prevents stale saveEBook calls (with extractedRootPath='') from clearing a
    // path that was correctly saved by a prior session's lazy-extraction step.
    let safeExtractedRootPath = ebook.extractedRootPath || '';
    if (safeExtractedRootPath === '' && existingRecords && existingRecords.length > 0) {
      const existingPath = String(getRecordValue(existingRecords[0], 'extractedRootPath', ''));
      if (existingPath.length > 0) {
        safeExtractedRootPath = existingPath;
        logger.info(TAG, `saveEBookInfo: 保留已存在的 extractedRootPath=${safeExtractedRootPath}，避免被空值覆盖 (bookId=${ebook.id})`);
      }
    }

    const commonParams = [
      ebook.format,
      ebook.filePath,
      ebook.fileSize,
      metadata.title,
      metadata.author,
      metadata.publisher,
      metadata.publishDate,
      metadata.isbn,
      metadata.language,
      metadata.description,
      metadata.coverImagePath,
      JSON.stringify(metadata.tags || []),
      metadata.rating,
      ebook.status,
      ebook.isFavorite ? 1 : 0,
      ebook.totalWordCount,
      ebook.contentMode || EBookContentMode.UNKNOWN,
      ebook.preferredReaderEngine || EBookReaderEngine.READER_KIT,
      safeExtractedRootPath,
      ebook.addTime,
      ebook.lastUpdateTime,
      ebook.isPrivate ? 1 : 0
      , ebook.isNSFW ? 1 : 0
    ];
    if (existingRecords && existingRecords.length > 0) {
      await this.dbManager.executeSql(updateSql, [...commonParams, ebook.id]);
      return;
    }

    await this.dbManager.executeSql(insertSql, [ebook.id, ...commonParams]);
  }

  /**
   * 保存章节信息
   */
  private async saveEBookChapter(chapter: EBookChapter): Promise<void> {
    const sql = `
      INSERT OR REPLACE INTO ebook_chapter (
        id, bookId, chapterNumber, title, content, startPosition,
        endPosition, wordCount, resourceHref, resourceFile, resourceMediaType,
        resourceLayoutType, resourceImagePath, resourceImageRelativePath, createTime
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      chapter.resourceHref || '',
      chapter.resourceFile || '',
      chapter.resourceMediaType || '',
      chapter.resourceLayoutType || '',
      chapter.resourceImagePath || '',
      chapter.resourceImageRelativePath || '',
      chapter.createTime
    ];

    await this.dbManager.executeSql(sql, params);
  }

  /**
   * 确保 ebook_reading_progress 表有 domPos 和 currentChapterIndex 列
   */
  private async deleteEBookChapters(bookId: string): Promise<void> {
    await this.dbManager.executeSql('DELETE FROM ebook_chapter WHERE bookId = ?', [bookId]);
  }

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
        { name: 'fontFamily', definition: "TEXT DEFAULT 'HarmonyOS Sans'" },
        { name: 'fontPath', definition: "TEXT DEFAULT ''" },
        { name: 'fontWeight', definition: 'INTEGER DEFAULT 400' },
        { name: 'themeBgImage', definition: "TEXT DEFAULT ''" },
        { name: 'nightMode', definition: 'INTEGER DEFAULT 0' },
        { name: 'followSystemTheme', definition: 'INTEGER DEFAULT 1' },
        { name: 'pageTopMargin', definition: 'INTEGER DEFAULT 24' },
        { name: 'pageBottomMargin', definition: 'INTEGER DEFAULT 24' },
        { name: 'letterSpacing', definition: 'REAL DEFAULT 0' },
        { name: 'paragraphSpacing', definition: 'INTEGER DEFAULT 8' },
        { name: 'firstLineIndent', definition: 'INTEGER DEFAULT 2' },
        { name: 'textAlignment', definition: "TEXT DEFAULT 'JUSTIFY'" },
        { name: 'pageTurnAnimation', definition: "TEXT DEFAULT 'SLIDE'" },
        { name: 'tapToTurn', definition: 'INTEGER DEFAULT 1' },
        { name: 'volumeKeyNavigation', definition: 'INTEGER DEFAULT 1' },
        { name: 'keepScreenOn', definition: 'INTEGER DEFAULT 0' },
        { name: 'lockDeviceOrientation', definition: 'INTEGER DEFAULT 0' },
        { name: 'showPageNumber', definition: 'INTEGER DEFAULT 1' },
        { name: 'showProgress', definition: 'INTEGER DEFAULT 0' },
        { name: 'showTime', definition: 'INTEGER DEFAULT 1' },
        { name: 'showBattery', definition: 'INTEGER DEFAULT 0' },
        { name: 'backgroundType', definition: "TEXT DEFAULT 'COLOR'" },
        { name: 'backgroundImagePath', definition: "TEXT DEFAULT ''" },
        { name: 'backgroundImageOpacity', definition: 'REAL DEFAULT 0.3' },
        { name: 'imageReaderSettingsJson', definition: "TEXT DEFAULT ''" }
      ];
      
      for (const col of requiredColumns) {
        if (!existingColumns.has(col.name)) {
          try {
            const alterSql = `ALTER TABLE ebook_reading_settings ADD COLUMN ${col.name} ${col.definition}`;
            await this.dbManager.executeSql(alterSql, []);
            logger.info(TAG, `已添加数据列：${col.name}`);
          } catch (e) {
            logger.warn(TAG, `添加数据列失败：列名=${col.name}，错误=${String(e)}`);
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
   * 串行化同一本书的写入，并使用插入或替换避免并发唯一约束冲突
   * 仍然保留完整字段写入，避免依赖更新语句时出现静默失败
   */
  public async saveReadingProgress(progress: EBookReadingProgress): Promise<void> {
    const saveKey = `${progress.bookId}|default_user`;
    let state = this.readingProgressSaveStates.get(saveKey);
    if (!state) {
      state = {
        latestProgress: null,
        runningPromise: null
      };
      this.readingProgressSaveStates.set(saveKey, state);
    }

    state.latestProgress = this.cloneReadingProgress(progress);
    if (state.runningPromise === null) {
      state.runningPromise = this.flushReadingProgressSaveQueue(saveKey, state);
    }
    return await state.runningPromise;
  }

  private cloneReadingProgress(progress: EBookReadingProgress): EBookReadingProgress {
    return {
      bookId: progress.bookId,
      currentChapterId: progress.currentChapterId,
      currentChapterIndex: progress.currentChapterIndex,
      currentPosition: progress.currentPosition,
      domPos: progress.domPos,
      progress: progress.progress,
      lastReadTime: progress.lastReadTime,
      totalReadingTime: progress.totalReadingTime
    };
  }

  private async flushReadingProgressSaveQueue(
    saveKey: string,
    state: PendingReadingProgressSaveState
  ): Promise<void> {
    try {
      while (state.latestProgress !== null) {
        const snapshot = state.latestProgress;
        state.latestProgress = null;
        await this.saveReadingProgressInternal(snapshot);
      }
    } finally {
      state.runningPromise = null;
      if (state.latestProgress === null) {
        this.readingProgressSaveStates.delete(saveKey);
      }
    }
  }

  private async saveReadingProgressInternal(progress: EBookReadingProgress): Promise<void> {
    // 首次保存时检查并添加缺失的列
    await this.ensureProgressColumns();
    
    const domPosValue = progress.domPos || '';
    const chapterIndexValue = progress.currentChapterIndex || 0;
    
    // 详细记录本次写入的核心数据
    logger.info(TAG, `保存阅读进度：书籍ID=${progress.bookId}，章节索引=${chapterIndexValue}，位置串长度=${domPosValue.length}`);
    
    const now = Date.now();
    
    try {
      // 1. 读取已有记录的创建时间，保持历史数据稳定
      let createTime = now;
      try {
        const existingSql = `SELECT createTime FROM ebook_reading_progress WHERE bookId = ? AND userId = ? LIMIT 1`;
        const existingResult = await this.dbManager.querySql(existingSql, [progress.bookId, 'default_user']);
        if (existingResult && existingResult.length > 0) {
          createTime = Number(getRecordValue(existingResult[0], 'createTime', now));
        }
      } catch (queryError) {
        logger.warn(TAG, `查询现有阅读进度创建时间失败：错误=${String(queryError)}`);
      }
      logger.debug(TAG, '正在使用串行插入或替换方式保存阅读进度');
      
      // 2. 一次性写入完整记录，避免并发删除再插入带来的冲突
      const insertSql = `
        INSERT OR REPLACE INTO ebook_reading_progress (
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
        createTime,
        now
      ];
      
      await this.dbManager.executeSql(insertSql, insertParams);
      logger.debug(TAG, `完整记录写入成功：章节索引=${chapterIndexValue}，位置串长度=${domPosValue.length}`);
      
      // 3. 验证保存结果
      const verifySql = `SELECT currentChapterIndex, domPos FROM ebook_reading_progress WHERE bookId = ? AND userId = ?`;
      const verifyResult = await this.dbManager.querySql(verifySql, [progress.bookId, 'default_user']);
      
      if (verifyResult && verifyResult.length > 0) {
        const record = verifyResult[0];
        const savedChapterIndex = Number(getRecordValue(record, 'currentChapterIndex', 0));
        const savedDomPos = String(getRecordValue(record, 'domPos', ''));
        
        logger.info(TAG, `阅读进度校验结果：保存的章节索引=${savedChapterIndex}，保存的位置串长度=${savedDomPos.length}`);
        
        if (savedChapterIndex === chapterIndexValue && savedDomPos.length === domPosValue.length) {
          logger.info(TAG, '阅读进度保存成功');
        }
        else {
          logger.error(
            TAG,
            `阅读进度校验失败：期望章节索引=${chapterIndexValue}，期望位置串长度=${domPosValue.length}；实际章节索引=${savedChapterIndex}，实际位置串长度=${savedDomPos.length}`
          );
          
          // 调试：查询所有列名
          const schemaResult = await this.dbManager.querySql("PRAGMA table_info('ebook_reading_progress')", []);
          const columnNames: string[] = [];
          for (const row of schemaResult) {
            columnNames.push(String(getRecordValue(row, 'name', '')));
          }
          logger.error(TAG, `数据表列名：${columnNames.join('，')}`);
        }
      } else {
        logger.error(TAG, '阅读进度校验失败：未找到记录');
      }
      
    } catch (error) {
      logger.error(TAG, `保存阅读进度失败: ${String(error)}`);
    }
  }

  private async saveReadingSettingsInternal(bookId: string, settings: EBookReadingSettings): Promise<void> {
    await this.ensureSettingsColumns();

    const now = Date.now();
    const finalSettings = await this.applyGlobalSettingsIfNew(bookId, settings);

    try {
      const bgType = finalSettings.backgroundType ?? 'COLOR';
      const bgImagePath = finalSettings.backgroundImagePath ?? '';
      const bgImageOpacity = finalSettings.backgroundImageOpacity ?? 0.3;
      let existingRowId = 0;
      let existingCreateTime = now;
      let existingImageReaderSettingsJson = '';
      const pendingImageReaderSettings = this.getPendingImageReaderSettingsSnapshot(bookId);
      const preferredImageReaderSettingsJson = pendingImageReaderSettings ? JSON.stringify(pendingImageReaderSettings) : '';

      try {
        const existingRow = await this.reconcileReadingSettingsRows(bookId, preferredImageReaderSettingsJson);
        if (existingRow) {
          existingRowId = existingRow.id;
          existingCreateTime = existingRow.createTime > 0 ? existingRow.createTime : now;
          existingImageReaderSettingsJson = existingRow.imageReaderSettingsJson;
        }
      } catch (queryError) {
        logger.warn(TAG, `读取现有阅读设置记录失败：书籍ID=${bookId}，错误=${String(queryError)}`);
      }

      if (pendingImageReaderSettings) {
        existingImageReaderSettingsJson = preferredImageReaderSettingsJson;
        logger.info(TAG, `保存纯文本阅读设置时检测到待写入的图片阅读设置快照，将优先保留图片阅读数据：书籍ID=${bookId}`);
      }

      if (existingImageReaderSettingsJson.trim().length <= 0) {
        const rememberedSnapshot = this.getRememberedImageReaderSettingsSnapshot(bookId);
        if (rememberedSnapshot) {
          existingImageReaderSettingsJson = JSON.stringify(rememberedSnapshot);
          logger.info(TAG, `保存纯文本阅读设置时已从内存快照恢复图片阅读数据：书籍ID=${bookId}`);
          logger.info(TAG, `淇濆瓨绾枃鏈槄璇昏缃椂浠庡唴瀛樺揩鐓т腑鎭㈠鍥剧墖闃呰鏁版嵁锛氫功绫岻D=${bookId}`);
        }
      }

      const insertSql = `
        INSERT INTO ebook_reading_settings (
          bookId, userId, fontSize, fontFamily, fontPath, fontWeight, lineHeight,
          backgroundColor, textColor, themeBgImage, nightMode, followSystemTheme,
          pageMargin, pageTopMargin, pageBottomMargin, pageMode, brightness, autoSave, saveInterval,
          letterSpacing, paragraphSpacing, firstLineIndent, textAlignment,
          pageTurnAnimation, tapToTurn, volumeKeyNavigation, keepScreenOn, lockDeviceOrientation,
          showPageNumber, showProgress, showTime, showBattery,
          backgroundType, backgroundImagePath, backgroundImageOpacity, imageReaderSettingsJson,
          createTime, updateTime
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `;
      const updateSql = `
        UPDATE ebook_reading_settings SET
          fontSize = ?, fontFamily = ?, fontPath = ?, fontWeight = ?, lineHeight = ?,
          backgroundColor = ?, textColor = ?, themeBgImage = ?, nightMode = ?, followSystemTheme = ?,
          pageMargin = ?, pageTopMargin = ?, pageBottomMargin = ?, pageMode = ?, brightness = ?, autoSave = ?, saveInterval = ?,
          letterSpacing = ?, paragraphSpacing = ?, firstLineIndent = ?, textAlignment = ?,
          pageTurnAnimation = ?, tapToTurn = ?, volumeKeyNavigation = ?, keepScreenOn = ?, lockDeviceOrientation = ?,
          showPageNumber = ?, showProgress = ?, showTime = ?, showBattery = ?,
          backgroundType = ?, backgroundImagePath = ?, backgroundImageOpacity = ?, imageReaderSettingsJson = ?,
          updateTime = ?
        WHERE id = ?
      `;

      const commonParams: (string | number)[] = [
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
        finalSettings.pageTopMargin ?? finalSettings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin ?? 24,
        finalSettings.pageBottomMargin ?? finalSettings.pageMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin ?? 24,
        finalSettings.pageMode,
        finalSettings.brightness,
        finalSettings.autoSave ? 1 : 0,
        finalSettings.saveInterval,
        finalSettings.letterSpacing ?? 0,
        finalSettings.paragraphSpacing ?? 8,
        finalSettings.firstLineIndent ?? 2,
        finalSettings.textAlignment ?? 'JUSTIFY',
        finalSettings.pageTurnAnimation ?? 'SLIDE',
        finalSettings.tapToTurn !== false ? 1 : 0,
        finalSettings.volumeKeyNavigation !== false ? 1 : 0,
        finalSettings.keepScreenOn ? 1 : 0,
        finalSettings.lockDeviceOrientation ? 1 : 0,
        finalSettings.showPageNumber !== false ? 1 : 0,
        finalSettings.showProgress ? 1 : 0,
        finalSettings.showTime !== false ? 1 : 0,
        finalSettings.showBattery ? 1 : 0,
        bgType,
        bgImagePath,
        bgImageOpacity,
        existingImageReaderSettingsJson
      ];
      const insertParams = commonParams;

      logger.info(
        TAG,
        `写入阅读设置：参数数量=${insertParams.length}，fontSize=${finalSettings.fontSize}，lineHeight=${finalSettings.lineHeight}，pageMargin=${finalSettings.pageMargin}，pageTopMargin=${finalSettings.pageTopMargin ?? finalSettings.pageMargin}，pageBottomMargin=${finalSettings.pageBottomMargin ?? finalSettings.pageMargin}，背景类型=${bgType}，背景图片路径=${bgImagePath}`
      );
      if (existingRowId > 0) {
        await this.dbManager.executeSql(updateSql, [...commonParams, now, existingRowId]);
      } else {
        await this.dbManager.executeSql(insertSql, [
          bookId,
          'default_user',
          ...commonParams,
          existingCreateTime,
          now
        ]);
      }
      await this.reconcileReadingSettingsRows(bookId, existingImageReaderSettingsJson);
      logger.info(TAG, `阅读设置写入成功：书籍ID=${bookId}`);

      const verifySql = `
        SELECT fontFamily, fontPath, fontWeight, letterSpacing, paragraphSpacing, firstLineIndent, textAlignment,
               backgroundType, backgroundImagePath, backgroundImageOpacity, volumeKeyNavigation
        FROM ebook_reading_settings
        WHERE bookId = ? AND userId = ?
        ORDER BY updateTime DESC, createTime DESC, id DESC
        LIMIT 1
      `;
      const verifyResult = await this.dbManager.querySql(verifySql, [bookId, 'default_user']);

      if (verifyResult && verifyResult.length > 0) {
        const record = verifyResult[0];
        const recordKeys = Object.keys(record);
        const savedFontFamily = String(getRecordValue(record, 'fontFamily', DEFAULT_EBOOK_READING_SETTINGS.fontFamily));
        const savedFontPath = String(getRecordValue(record, 'fontPath', ''));
        const savedFontWeight = Number(getRecordValue(record, 'fontWeight', 400));
        const savedLetterSpacing = Number(getRecordValue(record, 'letterSpacing', 0));
        const savedParagraphSpacing = Number(getRecordValue(record, 'paragraphSpacing', 8));
        const savedFirstLineIndent = Number(getRecordValue(record, 'firstLineIndent', 2));
        const savedTextAlignment = String(getRecordValue(record, 'textAlignment', 'JUSTIFY'));
        const savedBgType = String(getRecordValue(record, 'backgroundType', 'COLOR'));
        const savedBgImagePath = String(getRecordValue(record, 'backgroundImagePath', ''));
        const savedVolumeKey = Number(getRecordValue(record, 'volumeKeyNavigation', 1)) === 1;
        const expectedFontFamily = finalSettings.fontFamily || DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
        const expectedFontPath = finalSettings.fontPath || '';
        const expectedFontWeight = finalSettings.fontWeight || 400;
        const expectedLetterSpacing = finalSettings.letterSpacing ?? 0;
        const expectedParagraphSpacing = finalSettings.paragraphSpacing ?? 8;
        const expectedFirstLineIndent = finalSettings.firstLineIndent ?? 2;
        const expectedTextAlignment = finalSettings.textAlignment ?? 'JUSTIFY';

        logger.info(TAG, `校验记录字段列表：${recordKeys.join('，')}`);
        logger.info(
          TAG,
          `阅读设置校验结果：fontFamily=${savedFontFamily}, fontPath=${savedFontPath}, fontWeight=${savedFontWeight}, letterSpacing=${savedLetterSpacing}, paragraphSpacing=${savedParagraphSpacing}, firstLineIndent=${savedFirstLineIndent}, textAlignment=${savedTextAlignment}, 背景类型=${savedBgType}，背景图片路径=${savedBgImagePath}，音量键翻页=${savedVolumeKey ? '已开启' : '已关闭'}`
        );

        const fontSettingsValid = savedFontFamily === expectedFontFamily &&
          savedFontPath === expectedFontPath &&
          savedFontWeight === expectedFontWeight &&
          Math.abs(savedLetterSpacing - expectedLetterSpacing) < 0.001 &&
          savedParagraphSpacing === expectedParagraphSpacing &&
          Math.abs(savedFirstLineIndent - expectedFirstLineIndent) < 0.001 &&
          savedTextAlignment === expectedTextAlignment;

        if (!fontSettingsValid || savedBgType !== bgType || savedBgImagePath !== bgImagePath) {
          logger.error(
            TAG,
            `阅读设置校验失败：期望fontFamily=${expectedFontFamily}, fontPath=${expectedFontPath}, fontWeight=${expectedFontWeight}, letterSpacing=${expectedLetterSpacing}, paragraphSpacing=${expectedParagraphSpacing}, firstLineIndent=${expectedFirstLineIndent}, textAlignment=${expectedTextAlignment}, 背景类型=${bgType}, 背景图片路径=${bgImagePath}；实际fontFamily=${savedFontFamily}, fontPath=${savedFontPath}, fontWeight=${savedFontWeight}, letterSpacing=${savedLetterSpacing}, paragraphSpacing=${savedParagraphSpacing}, firstLineIndent=${savedFirstLineIndent}, textAlignment=${savedTextAlignment}, 背景类型=${savedBgType}, 背景图片路径=${savedBgImagePath}`
          );
        } else {
          logger.info(TAG, `阅读设置保存成功：书籍ID=${bookId}`);
        }
      } else {
        logger.error(TAG, `阅读设置校验失败：未找到记录，书籍ID=${bookId}`);
      }
    } catch (error) {
      logger.error(TAG, `保存阅读设置失败：书籍ID=${bookId}，错误=${String(error)}`);
    }
  }

  /**
   * 保存阅读设置（包含纯文本阅读器专用设置）
   * 串行合并同一本书的连续保存，避免并发写入触发唯一约束冲突。
   */
  public async saveReadingSettings(bookId: string, settings: EBookReadingSettings): Promise<void> {
    const saveKey = `${bookId}|default_user`;
    let state = this.readingSettingsSaveStates.get(saveKey);
    if (!state) {
      state = {
        latestSettings: null,
        runningPromise: null
      };
      this.readingSettingsSaveStates.set(saveKey, state);
    }

    state.latestSettings = this.cloneReadingSettings(settings);
    if (state.runningPromise === null) {
      state.runningPromise = this.flushReadingSettingsSaveQueue(saveKey, bookId, state);
    }
    return await state.runningPromise;
  }

  private cloneReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
    return {
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontPath: settings.fontPath,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      themeBgImage: settings.themeBgImage,
      nightMode: settings.nightMode,
      followSystemTheme: settings.followSystemTheme,
      pageMargin: settings.pageMargin,
      pageTopMargin: settings.pageTopMargin,
      pageBottomMargin: settings.pageBottomMargin,
      pageMode: settings.pageMode,
      brightness: settings.brightness,
      autoSave: settings.autoSave,
      saveInterval: settings.saveInterval,
      letterSpacing: settings.letterSpacing,
      paragraphSpacing: settings.paragraphSpacing,
      firstLineIndent: settings.firstLineIndent,
      textAlignment: settings.textAlignment,
      pageTurnAnimation: settings.pageTurnAnimation,
      tapToTurn: settings.tapToTurn,
      volumeKeyNavigation: settings.volumeKeyNavigation,
      keepScreenOn: settings.keepScreenOn,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? DEFAULT_EBOOK_READING_SETTINGS.lockDeviceOrientation ?? false,
      showPageNumber: settings.showPageNumber,
      showProgress: settings.showProgress,
      showTime: settings.showTime,
      showBattery: settings.showBattery,
      backgroundType: settings.backgroundType,
      backgroundImagePath: settings.backgroundImagePath,
      backgroundImageOpacity: settings.backgroundImageOpacity
    };
  }

  private clampNumber(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  private getEBookThemePreset(themeIndex: number): EBookThemePreset {
    if (themeIndex >= 0 && themeIndex < EBOOK_THEME_PRESETS.length) {
      return EBOOK_THEME_PRESETS[themeIndex];
    }
    return EBOOK_THEME_PRESETS[0];
  }

  private normalizeEBookPageMode(pageModeValue: string): EBookPageMode {
    if (pageModeValue === EBookPageMode.HORIZONTAL) {
      return EBookPageMode.HORIZONTAL;
    }
    return EBookPageMode.SIMULATION;
  }

  private async hasReadingSettingsRecord(bookId: string): Promise<boolean> {
    await this.ensureSettingsColumns();
    const records = await this.dbManager.querySql(
      'SELECT id FROM ebook_reading_settings WHERE bookId = ? AND userId = ? LIMIT 1',
      [bookId, 'default_user']
    );
    return records !== null && records !== undefined && records.length > 0;
  }

  private async getStoredEBookFormat(bookId: string): Promise<EBookFormat | null> {
    try {
      const records = await this.dbManager.querySql(
        'SELECT format FROM ebook_info WHERE id = ? LIMIT 1',
        [bookId]
      );
      if (records && records.length > 0) {
        return String(getRecordValue(records[0], 'format', '')) as EBookFormat;
      }
    } catch (error) {
      logger.warn(TAG, `读取电子书格式失败：书籍ID=${bookId}，错误=${String(error)}`);
    }
    return null;
  }

  public buildGlobalEBookReadingSettings(baseSettings: EBookReadingSettings = DEFAULT_EBOOK_READING_SETTINGS): EBookReadingSettings {
    const settingsManager = SettingsManager.getInstance();
    const themeIndex = Math.round(this.clampNumber(
      settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_THEME, 0),
      0,
      Math.max(0, EBOOK_THEME_PRESETS.length - 1)
    ));
    const themePreset = this.getEBookThemePreset(themeIndex);
    const followSystemTheme = settingsManager.getBoolean(
      SettingKeys.GLOBAL_EBOOK_FOLLOW_SYSTEM_THEME,
      DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme
    );
    const pageMode = this.normalizeEBookPageMode(settingsManager.getString(
      SettingKeys.GLOBAL_EBOOK_PAGE_MODE,
      DEFAULT_EBOOK_READING_SETTINGS.pageMode
    ));
    const pageMargin = Math.round(this.clampNumber(
      settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, DEFAULT_EBOOK_READING_SETTINGS.pageMargin),
      0,
      64
    ));
    const defaultTopMargin = DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
    const defaultBottomMargin = DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
    const pageTopMargin = Math.round(this.clampNumber(
      settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_TOP_MARGIN, defaultTopMargin),
      0,
      96
    ));
    const pageBottomMargin = Math.round(this.clampNumber(
      settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_BOTTOM_MARGIN, defaultBottomMargin),
      0,
      96
    ));
    const pageTurnAnimation = settingsManager.getString(
      SettingKeys.GLOBAL_EBOOK_PAGE_TURN_ANIMATION,
      baseSettings.pageTurnAnimation ?? 'SLIDE'
    );

    let backgroundColor = themePreset.backgroundColor;
    let textColor = themePreset.textColor;
    let themeBgImage = themePreset.themeBgImage;
    let nightMode = themePreset.nightMode;
    if (followSystemTheme) {
      backgroundColor = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
      textColor = DEFAULT_EBOOK_READING_SETTINGS.textColor;
      themeBgImage = DEFAULT_EBOOK_READING_SETTINGS.themeBgImage;
      nightMode = DEFAULT_EBOOK_READING_SETTINGS.nightMode;
    }

    return {
      fontSize: Math.round(this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, DEFAULT_EBOOK_READING_SETTINGS.fontSize),
        12,
        48
      )),
      fontFamily: settingsManager.getString(
        SettingKeys.GLOBAL_EBOOK_FONT_FAMILY,
        DEFAULT_EBOOK_READING_SETTINGS.fontFamily
      ),
      fontPath: settingsManager.getString(
        SettingKeys.GLOBAL_EBOOK_FONT_PATH,
        DEFAULT_EBOOK_READING_SETTINGS.fontPath
      ),
      fontWeight: Math.round(this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FONT_WEIGHT, DEFAULT_EBOOK_READING_SETTINGS.fontWeight),
        100,
        900
      )),
      lineHeight: this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, DEFAULT_EBOOK_READING_SETTINGS.lineHeight),
        1.0,
        3.0
      ),
      backgroundColor: backgroundColor,
      textColor: textColor,
      themeBgImage: themeBgImage,
      nightMode: nightMode,
      followSystemTheme: followSystemTheme,
      pageMargin: pageMargin,
      pageTopMargin: pageTopMargin,
      pageBottomMargin: pageBottomMargin,
      pageMode: pageMode,
      brightness: baseSettings.brightness,
      autoSave: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_AUTO_SAVE,
        DEFAULT_EBOOK_READING_SETTINGS.autoSave
      ),
      saveInterval: Math.round(this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_SAVE_INTERVAL, DEFAULT_EBOOK_READING_SETTINGS.saveInterval),
        5,
        300
      )),
      letterSpacing: this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_LETTER_SPACING, baseSettings.letterSpacing ?? 0),
        0,
        5
      ),
      paragraphSpacing: Math.round(this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PARAGRAPH_SPACING, baseSettings.paragraphSpacing ?? 8),
        0,
        32
      )),
      firstLineIndent: this.clampNumber(
        settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FIRST_LINE_INDENT, baseSettings.firstLineIndent ?? 2),
        0,
        4
      ),
      textAlignment: settingsManager.getString(
        SettingKeys.GLOBAL_EBOOK_TEXT_ALIGNMENT,
        baseSettings.textAlignment ?? 'JUSTIFY'
      ),
      pageTurnAnimation: pageTurnAnimation,
      tapToTurn: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_TAP_TO_TURN,
        baseSettings.tapToTurn ?? true
      ),
      volumeKeyNavigation: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_VOLUME_KEY_NAV,
        baseSettings.volumeKeyNavigation ?? true
      ),
      keepScreenOn: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_KEEP_SCREEN_ON,
        baseSettings.keepScreenOn ?? false
      ),
      lockDeviceOrientation: baseSettings.lockDeviceOrientation ??
        DEFAULT_EBOOK_READING_SETTINGS.lockDeviceOrientation ??
        false,
      showPageNumber: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_SHOW_PAGE_NUMBER,
        DEFAULT_EBOOK_READING_SETTINGS.showPageNumber ?? true
      ),
      showProgress: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_SHOW_PROGRESS,
        DEFAULT_EBOOK_READING_SETTINGS.showProgress ?? false
      ),
      showTime: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_SHOW_TIME,
        DEFAULT_EBOOK_READING_SETTINGS.showTime ?? true
      ),
      showBattery: settingsManager.getBoolean(
        SettingKeys.GLOBAL_EBOOK_SHOW_BATTERY,
        DEFAULT_EBOOK_READING_SETTINGS.showBattery ?? false
      ),
      backgroundType: baseSettings.backgroundType ?? DEFAULT_EBOOK_READING_SETTINGS.backgroundType,
      backgroundImagePath: baseSettings.backgroundImagePath ?? DEFAULT_EBOOK_READING_SETTINGS.backgroundImagePath,
      backgroundImageOpacity: baseSettings.backgroundImageOpacity ?? DEFAULT_EBOOK_READING_SETTINGS.backgroundImageOpacity
    };
  }

  public async resolveEffectiveEBookReadingSettings(bookId: string, settings: EBookReadingSettings): Promise<EBookReadingSettings> {
    try {
      const hasStoredSettings = await this.hasReadingSettingsRecord(bookId);
      const shouldApplyGlobalDefaults = !hasStoredSettings || this.shouldApplyGlobalDefaultsForNewBook(settings);
      if (shouldApplyGlobalDefaults) {
        const globalSettings = this.buildGlobalEBookReadingSettings(settings);
        logger.info(
          TAG,
          `套用电子书全局默认设置：书籍ID=${bookId}，hasStoredSettings=${hasStoredSettings}，fontSize=${globalSettings.fontSize}，lineHeight=${globalSettings.lineHeight}，pageMargin=${globalSettings.pageMargin}`
        );
        return globalSettings;
      }
    } catch (error) {
      logger.warn(TAG, `解析电子书全局默认设置失败，使用当前设置：书籍ID=${bookId}，错误=${String(error)}`);
    }
    return this.cloneReadingSettings(settings);
  }

  private cloneImageReaderSettings(settings: ImageReaderSettings): ImageReaderSettings {
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      lockDeviceOrientation: settings.lockDeviceOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: settings.lockMode ?? settings.lockOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockMode ?? false,
      lockOrientation: settings.lockMode ?? settings.lockOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockMode ?? false,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      doublePageVerticalDirection: settings.doublePageVerticalDirection,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin ?? 0,
      webtoonRightMargin: settings.webtoonRightMargin ?? 0,
      webtoonMarginSync: settings.webtoonMarginSync ?? true
    };
  }

  private rememberImageReaderSettingsSnapshot(bookId: string, settings: ImageReaderSettings): void {
    this.lastKnownImageReaderSettingsSnapshots.set(bookId, this.cloneImageReaderSettings(settings));
  }

  private getRememberedImageReaderSettingsSnapshot(bookId: string): ImageReaderSettings | null {
    const snapshot = this.lastKnownImageReaderSettingsSnapshots.get(bookId);
    if (!snapshot) {
      return null;
    }
    return this.cloneImageReaderSettings(snapshot);
  }

  private getPendingImageReaderSettingsSnapshot(bookId: string): ImageReaderSettings | null {
    const saveKey = `${bookId}|default_user|image_reader`;
    const state = this.imageReaderSettingsSaveStates.get(saveKey);
    if (!state?.latestSettings) {
      return null;
    }
    return this.cloneImageReaderSettings(state.latestSettings);
  }

  private async persistRecoveredImageReaderSettings(
    bookId: string,
    settings: ImageReaderSettings,
    source: string
  ): Promise<void> {
    const normalized = this.normalizeImageReaderSettings(settings);
    try {
      await this.saveImageReaderSettings(bookId, normalized);
      logger.info(
        TAG,
        `已将${source}图片阅读设置回写到数据库：书籍ID=${bookId}，阅读模式=${normalized.readingMode}，翻页动画=${normalized.pageTurnAnimation}`
      );
    } catch (error) {
      logger.warn(TAG, `回写${source}图片阅读设置失败：书籍ID=${bookId}，错误=${String(error)}`);
    }
  }

  private normalizeImageReaderSettings(settings: ImageReaderSettings | null | undefined): ImageReaderSettings {
    const base = settings || DEFAULT_IMAGE_READING_SETTINGS;
    const filterSettings = base.filterSettings || DEFAULT_IMAGE_READING_SETTINGS.filterSettings;
    return this.cloneImageReaderSettings({
      readingMode: base.readingMode ?? DEFAULT_IMAGE_READING_SETTINGS.readingMode,
      readingDirection: base.readingDirection ?? DEFAULT_IMAGE_READING_SETTINGS.readingDirection,
      brightness: base.brightness ?? DEFAULT_IMAGE_READING_SETTINGS.brightness,
      keepScreenOn: base.keepScreenOn ?? DEFAULT_IMAGE_READING_SETTINGS.keepScreenOn,
      lockDeviceOrientation: base.lockDeviceOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: base.lockMode ?? base.lockOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockMode ?? false,
      lockOrientation: base.lockMode ?? base.lockOrientation ?? DEFAULT_IMAGE_READING_SETTINGS.lockMode ?? false,
      pageSpacing: base.pageSpacing ?? DEFAULT_IMAGE_READING_SETTINGS.pageSpacing,
      showPageInfo: base.showPageInfo ?? DEFAULT_IMAGE_READING_SETTINGS.showPageInfo,
      showPageIndicator: base.showPageIndicator ?? DEFAULT_IMAGE_READING_SETTINGS.showPageIndicator,
      fitMode: base.fitMode ?? DEFAULT_IMAGE_READING_SETTINGS.fitMode,
      autoPageTurnInterval: base.autoPageTurnInterval ?? DEFAULT_IMAGE_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: base.skipIntroPages ?? DEFAULT_IMAGE_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: base.pageTurnAnimation ?? DEFAULT_IMAGE_READING_SETTINGS.pageTurnAnimation,
      doublePagePortraitLayout: base.doublePagePortraitLayout ?? DEFAULT_IMAGE_READING_SETTINGS.doublePagePortraitLayout,
      doublePageVerticalDirection: base.doublePageVerticalDirection ?? DEFAULT_IMAGE_READING_SETTINGS.doublePageVerticalDirection,
      filterSettings: {
        enabled: filterSettings.enabled ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.enabled,
        brightness: filterSettings.brightness ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.brightness,
        contrast: filterSettings.contrast ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.contrast,
        saturation: filterSettings.saturation ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.saturation,
        hue: filterSettings.hue ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.hue,
        gamma: filterSettings.gamma ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.gamma,
        sepia: filterSettings.sepia ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.sepia,
        invert: filterSettings.invert ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.invert,
        grayscale: filterSettings.grayscale ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.grayscale,
        blur: filterSettings.blur ?? DEFAULT_IMAGE_READING_SETTINGS.filterSettings.blur
      },
      volumeKeyNavigation: base.volumeKeyNavigation ?? DEFAULT_IMAGE_READING_SETTINGS.volumeKeyNavigation,
      curlBackOpacity: base.curlBackOpacity ?? DEFAULT_IMAGE_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: base.webtoonLeftMargin ?? DEFAULT_IMAGE_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: base.webtoonRightMargin ?? DEFAULT_IMAGE_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: base.webtoonMarginSync ?? DEFAULT_IMAGE_READING_SETTINGS.webtoonMarginSync
    });
  }

  private async loadLegacyImageReaderSettings(bookId: string): Promise<ImageReaderSettings | null> {
    try {
      const dataManager = DataManager.getInstance();
      const settingKey = `manga_settings_${bookId}`;
      const settingsJson = await dataManager.getUserSetting('default_user', settingKey);
      if (!settingsJson || settingsJson.trim().length <= 0) {
        return null;
      }

      const parsed = JSON.parse(settingsJson) as ImageReaderSettings;
      const normalized = this.normalizeImageReaderSettings(parsed);
      this.rememberImageReaderSettingsSnapshot(bookId, normalized);
      logger.warn(
        TAG,
        `图片阅读设置缺失，已从旧版单书设置迁移：书籍ID=${bookId}，阅读模式=${normalized.readingMode}，翻页动画=${normalized.pageTurnAnimation}`
      );
      await this.persistRecoveredImageReaderSettings(bookId, normalized, '旧版迁移');
      return normalized;
    } catch (error) {
      logger.warn(TAG, `读取旧版图片阅读设置失败：书籍ID=${bookId}，错误=${String(error)}`);
      return null;
    }
  }

  private async getStoredImageReaderSettingsSnapshot(bookId: string): Promise<ImageReaderSettings | null> {
    await this.ensureSettingsColumns();
    try {
      const records = await this.queryOrderedReadingSettingsRows(bookId);
      if (!records || records.length <= 0) {
        return this.getRememberedImageReaderSettingsSnapshot(bookId);
      }

      for (const record of records) {
        const rowSnapshot = this.buildReadingSettingsRowSnapshot(record);
        const settingsJson = rowSnapshot.imageReaderSettingsJson.trim();
        if (settingsJson.length <= 0) {
          continue;
        }

        try {
          const normalized = this.normalizeImageReaderSettings(JSON.parse(settingsJson) as ImageReaderSettings);
          this.rememberImageReaderSettingsSnapshot(bookId, normalized);
          return normalized;
        } catch (parseError) {
          logger.warn(
            TAG,
            `预读图片阅读设置快照失败：书籍ID=${bookId}，记录ID=${rowSnapshot.id}，错误=${String(parseError)}`
          );
        }
      }
    } catch (error) {
      logger.warn(TAG, `预读图片阅读设置快照失败：书籍ID=${bookId}，错误=${String(error)}`);
    }

    return this.getRememberedImageReaderSettingsSnapshot(bookId);
  }

  private buildReadingSettingsRowSnapshot(record: DatabaseRecord): ReadingSettingsRowSnapshot {
    return {
      id: Number(getRecordValue(record, 'id', 0)),
      createTime: Number(getRecordValue(record, 'createTime', 0)),
      updateTime: Number(getRecordValue(record, 'updateTime', 0)),
      imageReaderSettingsJson: String(getRecordValue(record, 'imageReaderSettingsJson', ''))
    };
  }

  private getImageReaderSettingsJsonLength(record: DatabaseRecord): number {
    const explicitLength = Number(getRecordValue(record, 'imageReaderSettingsJsonLength', -1));
    if (explicitLength >= 0) {
      return explicitLength;
    }
    return this.buildReadingSettingsRowSnapshot(record).imageReaderSettingsJson.trim().length;
  }

  private describeReadingSettingsRow(record: DatabaseRecord): string {
    const snapshot = this.buildReadingSettingsRowSnapshot(record);
    return `id=${snapshot.id}, createTime=${snapshot.createTime}, updateTime=${snapshot.updateTime}, imageReaderSettingsJsonLength=${snapshot.imageReaderSettingsJson.trim().length}`;
  }

  private async queryOrderedReadingSettingsRows(bookId: string): Promise<DatabaseRecord[]> {
    const sql = `
      SELECT
        id,
        createTime,
        updateTime,
        imageReaderSettingsJson,
        LENGTH(TRIM(COALESCE(imageReaderSettingsJson, ''))) AS imageReaderSettingsJsonLength
      FROM ebook_reading_settings
      WHERE bookId = ? AND userId = ?
      ORDER BY updateTime DESC, createTime DESC, id DESC
    `;
    return await this.dbManager.querySql(sql, [bookId, 'default_user']);
  }

  private async reconcileReadingSettingsRows(
    bookId: string,
    preferredImageReaderSettingsJson: string = ''
  ): Promise<ReadingSettingsRowSnapshot | null> {
    const records = await this.queryOrderedReadingSettingsRows(bookId);
    if (!records || records.length <= 0) {
      return null;
    }

    const normalizedPreferredJson = preferredImageReaderSettingsJson.trim();
    let keeperRecord = records[0];
    if (normalizedPreferredJson.length <= 0) {
      const newestNonEmptyRecord = records.find((record: DatabaseRecord) => this.getImageReaderSettingsJsonLength(record) > 0);
      if (newestNonEmptyRecord) {
        keeperRecord = newestNonEmptyRecord;
      }
    }

    let keeperSnapshot = this.buildReadingSettingsRowSnapshot(keeperRecord);
    let finalImageReaderSettingsJson = normalizedPreferredJson;
    if (finalImageReaderSettingsJson.length <= 0) {
      const newestNonEmptyRecord = records.find((record: DatabaseRecord) => this.getImageReaderSettingsJsonLength(record) > 0);
      if (newestNonEmptyRecord) {
        finalImageReaderSettingsJson = this.buildReadingSettingsRowSnapshot(newestNonEmptyRecord).imageReaderSettingsJson;
      } else {
        finalImageReaderSettingsJson = keeperSnapshot.imageReaderSettingsJson;
      }
    }

    if (records.length > 1) {
      const rowDescriptions = records.map((record: DatabaseRecord) => this.describeReadingSettingsRow(record)).join(' | ');
      logger.warn(TAG, `检测到电子书阅读设置存在重复记录，准备自动合并：书籍ID=${bookId}，记录=${rowDescriptions}`);
    }

    const duplicateIds = records
      .map((record: DatabaseRecord) => Number(getRecordValue(record, 'id', 0)))
      .filter((id: number) => id > 0 && id !== keeperSnapshot.id);

    const currentImageReaderSettingsJson = keeperSnapshot.imageReaderSettingsJson.trim();
    const nextImageReaderSettingsJson = finalImageReaderSettingsJson.trim();
    if (keeperSnapshot.id > 0 && nextImageReaderSettingsJson !== currentImageReaderSettingsJson) {
      const repairedUpdateTime = Date.now();
      await this.dbManager.executeSql(
        'UPDATE ebook_reading_settings SET imageReaderSettingsJson = ?, updateTime = ? WHERE id = ?',
        [finalImageReaderSettingsJson, repairedUpdateTime, keeperSnapshot.id]
      );
      keeperSnapshot = {
        id: keeperSnapshot.id,
        createTime: keeperSnapshot.createTime,
        updateTime: repairedUpdateTime,
        imageReaderSettingsJson: finalImageReaderSettingsJson
      };
      logger.info(
        TAG,
        `已修复电子书阅读设置中的图片阅读数据：书籍ID=${bookId}，记录ID=${keeperSnapshot.id}，数据长度=${nextImageReaderSettingsJson.length}`
      );
    }

    if (duplicateIds.length > 0) {
      const placeholders = duplicateIds.map(() => '?').join(', ');
      await this.dbManager.executeSql(
        `DELETE FROM ebook_reading_settings WHERE id IN (${placeholders})`,
        duplicateIds
      );
      logger.info(
        TAG,
        `已清理重复的电子书阅读设置记录：书籍ID=${bookId}，保留记录ID=${keeperSnapshot.id}，删除数量=${duplicateIds.length}`
      );
    }

    return keeperSnapshot;
  }

  public async getImageReaderSettings(bookId: string): Promise<ImageReaderSettings> {
    await this.ensureSettingsColumns();

    const pendingSnapshot = this.getPendingImageReaderSettingsSnapshot(bookId);
    if (pendingSnapshot) {
      logger.info(
        TAG,
        `读取图片阅读设置：来源=内存快照，书籍ID=${bookId}，阅读模式=${pendingSnapshot.readingMode}，翻页动画=${pendingSnapshot.pageTurnAnimation}`
      );
      return pendingSnapshot;
    }

    try {
      const records = await this.queryOrderedReadingSettingsRows(bookId);
      if (records && records.length > 0) {
        const rowDescriptions = records.map((record: DatabaseRecord) => this.describeReadingSettingsRow(record)).join(' | ');
        let selectedSettingsJson = '';
        let hasNonEmptySettingsJson = false;
        for (const record of records) {
          const rowSnapshot = this.buildReadingSettingsRowSnapshot(record);
          const settingsJson = rowSnapshot.imageReaderSettingsJson.trim();
          if (settingsJson.length <= 0) {
            continue;
          }
          hasNonEmptySettingsJson = true;
          try {
            const parsed = JSON.parse(settingsJson) as ImageReaderSettings;
            const normalized = this.normalizeImageReaderSettings(parsed);
            this.rememberImageReaderSettingsSnapshot(bookId, normalized);
            selectedSettingsJson = rowSnapshot.imageReaderSettingsJson;
            if (records.length > 1) {
              await this.reconcileReadingSettingsRows(bookId, selectedSettingsJson);
            }
            logger.info(
              TAG,
              `读取图片阅读设置：来源=数据库图片阅读数据，书籍ID=${bookId}，阅读模式=${normalized.readingMode}，翻页动画=${normalized.pageTurnAnimation}`
            );
            return normalized;
          } catch (parseError) {
            logger.warn(TAG, `解析图片阅读设置失败：书籍ID=${bookId}，错误=${String(parseError)}`);
          }
        }
        if (selectedSettingsJson.length <= 0) {
          if (hasNonEmptySettingsJson) {
            logger.warn(
              TAG,
              `图片阅读设置记录已存在，但所有非空数据均解析失败：书籍ID=${bookId}，记录=${rowDescriptions}`
            );
          } else {
            logger.warn(
              TAG,
              `图片阅读设置记录已存在，但图片阅读数据为空：书籍ID=${bookId}，记录=${rowDescriptions}`
            );
          }
        }
      } else {
        logger.info(TAG, `未找到图片阅读设置记录：书籍ID=${bookId}`);
      }
    } catch (error) {
      logger.error(TAG, `读取图片阅读设置失败：书籍ID=${bookId}，错误=${String(error)}`);
    }

    try {
      const rememberedSnapshot = this.getRememberedImageReaderSettingsSnapshot(bookId);
      if (rememberedSnapshot) {
        logger.info(
          TAG,
          `璇诲彇鍥剧墖闃呰璁剧疆锛氭潵婧?鍐呭瓨鍏滃簳蹇収锛屼功绫岻D=${bookId}锛岄槄璇绘ā寮?${rememberedSnapshot.readingMode}锛岀炕椤靛姩鐢?${rememberedSnapshot.pageTurnAnimation}`
        );
        logger.info(
          TAG,
          `读取图片阅读设置：来源=内存兜底快照，书籍ID=${bookId}，阅读模式=${rememberedSnapshot.readingMode}，翻页动画=${rememberedSnapshot.pageTurnAnimation}`
        );
        await this.persistRecoveredImageReaderSettings(bookId, rememberedSnapshot, '内存兜底快照');
        return rememberedSnapshot;
      }

      const legacySettings = await this.loadLegacyImageReaderSettings(bookId);
      if (legacySettings) {
        return legacySettings;
      }

      const defaults = this.cloneImageReaderSettings(DEFAULT_IMAGE_READING_SETTINGS);
      this.rememberImageReaderSettingsSnapshot(bookId, defaults);
      logger.info(
        TAG,
        `读取图片阅读设置：来源=内置默认值，书籍ID=${bookId}，阅读模式=${defaults.readingMode}，翻页动画=${defaults.pageTurnAnimation}`
      );
      await this.persistRecoveredImageReaderSettings(bookId, defaults, '内置默认值');
      return defaults;
    } catch (error) {
      logger.warn(TAG, `加载图片阅读默认设置失败，改用内置默认值：书籍ID=${bookId}，错误=${String(error)}`);
      const defaults = this.cloneImageReaderSettings(DEFAULT_IMAGE_READING_SETTINGS);
      this.rememberImageReaderSettingsSnapshot(bookId, defaults);
      await this.persistRecoveredImageReaderSettings(bookId, defaults, '异常兜底默认值');
      return defaults;
    }
  }

  public async loadImageReaderSettings(bookId: string): Promise<ImageReaderSettings> {
    return this.getImageReaderSettings(bookId);
  }

  public async saveImageReaderSettings(bookId: string, settings: ImageReaderSettings): Promise<void> {
    const saveKey = `${bookId}|default_user|image_reader`;
    let state = this.imageReaderSettingsSaveStates.get(saveKey);
    if (!state) {
      state = {
        latestSettings: null,
        runningPromise: null
      };
      this.imageReaderSettingsSaveStates.set(saveKey, state);
    }

    const normalizedSettings = this.normalizeImageReaderSettings(settings);
    this.rememberImageReaderSettingsSnapshot(bookId, normalizedSettings);
    state.latestSettings = normalizedSettings;
    if (state.runningPromise === null) {
      state.runningPromise = this.flushImageReaderSettingsSaveQueue(saveKey, bookId, state);
    }
    return await state.runningPromise;
  }

  private async flushImageReaderSettingsSaveQueue(
    saveKey: string,
    bookId: string,
    state: PendingImageReaderSettingsSaveState
  ): Promise<void> {
    try {
      while (state.latestSettings !== null) {
        const snapshot = state.latestSettings;
        state.latestSettings = null;
        await this.saveImageReaderSettingsInternal(bookId, snapshot);
      }
    } finally {
      state.runningPromise = null;
      if (state.latestSettings === null) {
        this.imageReaderSettingsSaveStates.delete(saveKey);
      }
    }
  }

  private async saveImageReaderSettingsInternal(bookId: string, settings: ImageReaderSettings): Promise<void> {
    await this.ensureSettingsColumns();

    const now = Date.now();
    const snapshot = this.normalizeImageReaderSettings(settings);
    const settingsJson = JSON.stringify(snapshot);
    this.rememberImageReaderSettingsSnapshot(bookId, snapshot);

    try {
      const existingRow = await this.reconcileReadingSettingsRows(bookId, settingsJson);
      if (existingRow && existingRow.id > 0) {
        await this.dbManager.executeSql(
          'UPDATE ebook_reading_settings SET imageReaderSettingsJson = ?, updateTime = ? WHERE id = ?',
          [settingsJson, now, existingRow.id]
        );
      } else {
        await this.dbManager.executeSql(
          `INSERT INTO ebook_reading_settings (
            bookId, userId, createTime, updateTime, imageReaderSettingsJson
          ) VALUES (?, ?, ?, ?, ?)`,
          [bookId, 'default_user', now, now, settingsJson]
        );
      }
      logger.info(
        TAG,
        `图片阅读设置保存成功：书籍ID=${bookId}，阅读模式=${snapshot.readingMode}，翻页动画=${snapshot.pageTurnAnimation}`
      );
    } catch (error) {
      logger.error(TAG, `保存图片阅读设置失败：书籍ID=${bookId}，错误=${String(error)}`);
      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  private async flushReadingSettingsSaveQueue(
    saveKey: string,
    bookId: string,
    state: PendingReadingSettingsSaveState
  ): Promise<void> {
    try {
      while (state.latestSettings !== null) {
        const snapshot = state.latestSettings;
        state.latestSettings = null;
        await this.saveReadingSettingsInternal(bookId, snapshot);
      }
    } finally {
      state.runningPromise = null;
      if (state.latestSettings === null) {
        this.readingSettingsSaveStates.delete(saveKey);
      }
    }
  }

  /**
   * 对于新电子书，应用电子书全局默认阅读设置。
   * TXT/小说阅读器默认值由小说阅读设置链路单独处理。
   */
  private async applyGlobalSettingsIfNew(bookId: string, settings: EBookReadingSettings): Promise<EBookReadingSettings> {
    try {
      const existingSql = `
        SELECT bookId
        FROM ebook_reading_settings
        WHERE bookId = ? AND userId = ?
        ORDER BY updateTime DESC, createTime DESC, id DESC
        LIMIT 1
      `;
      const existingRecords = await this.dbManager.querySql(existingSql, [bookId, 'default_user']);
      if (existingRecords && existingRecords.length > 0) {
        return settings;
      }
      if (!this.shouldApplyGlobalDefaultsForNewBook(settings)) {
        logger.info(
          TAG,
          `检测到自定义设置，跳过套用全局默认值：书籍ID=${bookId}，fontSize=${settings.fontSize}，lineHeight=${settings.lineHeight}，pageMargin=${settings.pageMargin}`
        );
        return settings;
      }

      const storedFormat = await this.getStoredEBookFormat(bookId);
      if (storedFormat === EBookFormat.TXT) {
        logger.info(TAG, `TXT 电子书跳过电子书全局默认值，交由小说阅读默认设置处理：书籍ID=${bookId}`);
        return settings;
      }

      const result = this.buildGlobalEBookReadingSettings(settings);
      logger.info(
        TAG,
        `应用电子书全局默认设置: fontSize=${result.fontSize}, lineHeight=${result.lineHeight}, pageMargin=${result.pageMargin}, followSystemTheme=${result.followSystemTheme}`
      );
      return result;
    } catch (error) {
      logger.error(TAG, `应用全局设置失败: ${String(error)}`);
      return settings;
    }
  }

  /**
   * 更新电子书封面
   */
  private shouldApplyGlobalDefaultsForNewBook(settings: EBookReadingSettings): boolean {
    if ((settings.backgroundImagePath ?? '').length > 0) {
      return false;
    }

    const currentBg = (settings.backgroundColor || '').toUpperCase();
    const currentText = (settings.textColor || '').toUpperCase();
    const defaultBg = (DEFAULT_EBOOK_READING_SETTINGS.backgroundColor || '').toUpperCase();
    const defaultText = (DEFAULT_EBOOK_READING_SETTINGS.textColor || '').toUpperCase();
    const currentFontFamily = settings.fontFamily ?? DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
    const defaultFontFamily = DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
    const currentFontPath = settings.fontPath ?? DEFAULT_EBOOK_READING_SETTINGS.fontPath ?? '';
    const defaultFontPath = DEFAULT_EBOOK_READING_SETTINGS.fontPath ?? '';
    const currentFontWeight = settings.fontWeight ?? DEFAULT_EBOOK_READING_SETTINGS.fontWeight ?? 400;
    const defaultFontWeight = DEFAULT_EBOOK_READING_SETTINGS.fontWeight ?? 400;
    const currentThemeBgImage = settings.themeBgImage ?? DEFAULT_EBOOK_READING_SETTINGS.themeBgImage ?? '';
    const defaultThemeBgImage = DEFAULT_EBOOK_READING_SETTINGS.themeBgImage ?? '';
    const currentNightMode = settings.nightMode ?? DEFAULT_EBOOK_READING_SETTINGS.nightMode;
    const defaultNightMode = DEFAULT_EBOOK_READING_SETTINGS.nightMode;
    const currentLetterSpacing = settings.letterSpacing ?? 0;
    const currentParagraphSpacing = settings.paragraphSpacing ?? 8;
    const currentFirstLineIndent = settings.firstLineIndent ?? 2;
    const currentTextAlignment = settings.textAlignment ?? 'JUSTIFY';
    const currentPageTurnAnimation = settings.pageTurnAnimation ?? 'SLIDE';
    const currentTapToTurn = settings.tapToTurn ?? true;
    const currentVolumeKeyNavigation = settings.volumeKeyNavigation ?? true;
    const currentKeepScreenOn = settings.keepScreenOn ?? false;
    const currentShowPageNumber = settings.showPageNumber ?? true;
    const currentShowProgress = settings.showProgress ?? false;
    const currentShowTime = settings.showTime ?? true;
    const currentShowBattery = settings.showBattery ?? false;
    const currentBackgroundType = settings.backgroundType ?? 'COLOR';
    const currentBackgroundImageOpacity = settings.backgroundImageOpacity ?? 0.3;
    const currentFollowSystemTheme = settings.followSystemTheme ?? DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme;
    const defaultFollowSystemTheme = DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme;
    const currentPageTopMargin = settings.pageTopMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin ?? settings.pageMargin;
    const currentPageBottomMargin = settings.pageBottomMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin ?? settings.pageMargin;
    const defaultPageTopMargin = DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
    const defaultPageBottomMargin = DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin ?? DEFAULT_EBOOK_READING_SETTINGS.pageMargin;

    return settings.fontSize === DEFAULT_EBOOK_READING_SETTINGS.fontSize &&
      Math.abs(settings.lineHeight - DEFAULT_EBOOK_READING_SETTINGS.lineHeight) < 0.001 &&
      settings.pageMargin === DEFAULT_EBOOK_READING_SETTINGS.pageMargin &&
      currentPageTopMargin === defaultPageTopMargin &&
      currentPageBottomMargin === defaultPageBottomMargin &&
      currentFontFamily === defaultFontFamily &&
      currentFontPath === defaultFontPath &&
      currentFontWeight === defaultFontWeight &&
      currentBg === defaultBg &&
      currentText === defaultText &&
      currentThemeBgImage === defaultThemeBgImage &&
      currentNightMode === defaultNightMode &&
      currentFollowSystemTheme === defaultFollowSystemTheme &&
      settings.pageMode === DEFAULT_EBOOK_READING_SETTINGS.pageMode &&
      settings.brightness === DEFAULT_EBOOK_READING_SETTINGS.brightness &&
      settings.autoSave === DEFAULT_EBOOK_READING_SETTINGS.autoSave &&
      settings.saveInterval === DEFAULT_EBOOK_READING_SETTINGS.saveInterval &&
      Math.abs(currentLetterSpacing) < 0.001 &&
      currentParagraphSpacing === 8 &&
      currentFirstLineIndent === 2 &&
      currentTextAlignment === 'JUSTIFY' &&
      currentPageTurnAnimation === 'SLIDE' &&
      currentTapToTurn &&
      currentVolumeKeyNavigation &&
      !currentKeepScreenOn &&
      currentShowPageNumber &&
      !currentShowProgress &&
      currentShowTime &&
      !currentShowBattery &&
      currentBackgroundType === 'COLOR' &&
      Math.abs(currentBackgroundImageOpacity - 0.3) < 0.001;
  }

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
   * [新增] 获取隐私电子书列表
   * @returns Promise<EBook[]> 隐私电子书列表
   */
  public async getPrivateEBooks(): Promise<EBook[]> {
    try {
      const sql = `SELECT * FROM ebook_info WHERE isPrivate = 1 ORDER BY lastUpdateTime DESC`;
      const records = await this.dbManager.querySql(sql, []);
      
      const ebooks: EBook[] = [];
      for (const record of records) {
        const ebook = await this.buildEBookFromRecord(record);
        ebooks.push(ebook);
      }

      logger.info(TAG, `查询到 ${ebooks.length} 本隐私电子书`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `获取隐私电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * [新增] 获取非隐私电子书列表
   * @returns Promise<EBook[]> 非隐私电子书列表
   */
  public async getNonPrivateEBooks(): Promise<EBook[]> {
    try {
      const sql = `SELECT * FROM ebook_info WHERE (isPrivate = 0 OR isPrivate IS NULL) ORDER BY lastUpdateTime DESC`;
      const records = await this.dbManager.querySql(sql, []);
      
      const ebooks: EBook[] = [];
      for (const record of records) {
        const ebook = await this.buildEBookFromRecord(record);
        ebooks.push(ebook);
      }

      logger.info(TAG, `查询到 ${ebooks.length} 本非隐私电子书`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `获取非隐私电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * [新增] 获取SFW（非NSFW）电子书列表
   * @returns Promise<EBook[]> SFW电子书列表
   */
  public async getSFWEBooks(): Promise<EBook[]> {
    try {
      const sql = `SELECT * FROM ebook_info WHERE (isNSFW = 0 OR isNSFW IS NULL) ORDER BY lastUpdateTime DESC`;
      const records = await this.dbManager.querySql(sql, []);
      
      const ebooks: EBook[] = [];
      for (const record of records) {
        const ebook = await this.buildEBookFromRecord(record);
        ebooks.push(ebook);
      }

      logger.info(TAG, `查询到 ${ebooks.length} 本SFW电子书`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `获取SFW电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * [新增] 获取NSFW电子书列表
   * @returns Promise<EBook[]> NSFW电子书列表
   */
  public async getNSFWEBooks(): Promise<EBook[]> {
    try {
      const sql = `SELECT * FROM ebook_info WHERE isNSFW = 1 ORDER BY lastUpdateTime DESC`;
      const records = await this.dbManager.querySql(sql, []);
      
      const ebooks: EBook[] = [];
      for (const record of records) {
        const ebook = await this.buildEBookFromRecord(record);
        ebooks.push(ebook);
      }

      logger.info(TAG, `查询到 ${ebooks.length} 本NSFW电子书`);
      return ebooks;
    } catch (error) {
      logger.error(TAG, `获取NSFW电子书列表失败: ${String(error instanceof Error ? error.message : error)}`);
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
    const contentMode = String(getRecordValue(record, 'contentMode', EBookContentMode.UNKNOWN)) as EBookContentMode;
    const preferredReaderEngine = String(getRecordValue(record, 'preferredReaderEngine', EBookReaderEngine.READER_KIT)) as EBookReaderEngine;
    const extractedRootPath = String(getRecordValue(record, 'extractedRootPath', ''));
    const addTime = Number(getRecordValue(record, 'addTime', 0));
    const lastUpdateTime = Number(getRecordValue(record, 'lastUpdateTime', 0));
    const isNSFW = Number(getRecordValue(record, 'isNSFW', 0)) === 1;
    const isPrivate = Number(getRecordValue(record, 'isPrivate', 0)) === 1;  // 读取隐私状态

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

    const ebook = new EBook(
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
      totalWordCount,
      isPrivate,
      isNSFW
    );
    
    // 设置隐私状态
    
    ebook.contentMode = contentMode || EBookContentMode.UNKNOWN;
    ebook.preferredReaderEngine = preferredReaderEngine || EBookReaderEngine.READER_KIT;
    ebook.extractedRootPath = extractedRootPath || '';
    return ebook;
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
          resourceHref: String(getRecordValue(record, 'resourceHref', '')),
          resourceFile: String(getRecordValue(record, 'resourceFile', '')),
          resourceMediaType: String(getRecordValue(record, 'resourceMediaType', '')),
          resourceLayoutType: String(getRecordValue(record, 'resourceLayoutType', '')),
          resourceImagePath: String(getRecordValue(record, 'resourceImagePath', '')),
          resourceImageRelativePath: String(getRecordValue(record, 'resourceImageRelativePath', '')),
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
        pageMargin, pageTopMargin, pageBottomMargin, pageMode, brightness, autoSave, saveInterval,
        letterSpacing, paragraphSpacing, firstLineIndent, textAlignment,
        pageTurnAnimation, tapToTurn, volumeKeyNavigation, keepScreenOn, lockDeviceOrientation,
        showPageNumber, showProgress, showTime, showBattery,
        backgroundType, backgroundImagePath, backgroundImageOpacity
      FROM ebook_reading_settings
      WHERE bookId = ? AND userId = ?
      ORDER BY updateTime DESC, createTime DESC, id DESC
      LIMIT 1`;
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
          pageTopMargin: Number(getRecordValue(record, 'pageTopMargin', 24)),
          pageBottomMargin: Number(getRecordValue(record, 'pageBottomMargin', 24)),
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
          lockDeviceOrientation: Number(getRecordValue(record, 'lockDeviceOrientation', 0)) === 1,
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
        
        logger.info(
          TAG,
          `读取阅读设置: fontSize=${settings.fontSize}, fontFamily=${settings.fontFamily}, fontPath=${settings.fontPath}, fontWeight=${settings.fontWeight}, lineHeight=${settings.lineHeight}, pageMargin=${settings.pageMargin}, pageTopMargin=${settings.pageTopMargin}, pageBottomMargin=${settings.pageBottomMargin}, letterSpacing=${settings.letterSpacing}, paragraphSpacing=${settings.paragraphSpacing}, firstLineIndent=${settings.firstLineIndent}, textAlignment=${settings.textAlignment}, volumeKeyNavigation=${settings.volumeKeyNavigation}, tapToTurn=${settings.tapToTurn}, bgType=${settings.backgroundType}, bgColor=${settings.backgroundColor}, textColor=${settings.textColor}, bgImagePath=${settings.backgroundImagePath}, followSystemTheme=${settings.followSystemTheme}`
        );
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
   * 获取所有电子书的自定义背景图片路径
   * 用于在设置页面中选择已有的背景图片
   * [修复] 不再去重，显示每本使用背景图片的电子书
   */
  public async getAllCustomBackgroundImages(): Promise<BackgroundImageInfo[]> {
    try {
      const sql = `
        SELECT s.bookId, s.backgroundImagePath, i.title
        FROM ebook_reading_settings s
        LEFT JOIN ebook_info i ON s.bookId = i.id
        WHERE s.backgroundImagePath IS NOT NULL 
          AND s.backgroundImagePath != ''
          AND s.backgroundType = 'IMAGE'
      `;
      const records = await this.dbManager.querySql(sql, []);
      
      const results: BackgroundImageInfo[] = [];
      
      for (const record of records) {
        const bookId = String(getRecordValue(record, 'bookId', ''));
        const bookTitle = String(getRecordValue(record, 'title', '未知书籍'));
        const imagePath = String(getRecordValue(record, 'backgroundImagePath', ''));
        
        // [修复] 不去重，每本使用背景图片的电子书都显示
        if (imagePath && imagePath.length > 0) {
          const info: BackgroundImageInfo = { bookId: bookId, bookTitle: bookTitle, imagePath: imagePath };
          results.push(info);
        }
      }
      
      logger.info(TAG, `获取到 ${results.length} 本使用背景图片的电子书`);
      return results;
    } catch (error) {
      logger.error(TAG, `获取自定义背景图片失败: ${String(error instanceof Error ? error.message : error)}`);
      return [];
    }
  }

  /**
   * 清除使用特定背景图片的电子书阅读设置
   * 将使用该图片的电子书背景设置重置为默认颜色背景
   */
  public async clearBackgroundImageFromSettings(imagePath: string): Promise<number> {
    try {
      // 更新所有使用该背景图片的电子书阅读设置
      const sql = `UPDATE ebook_reading_settings 
                   SET backgroundType = 'COLOR', backgroundImagePath = '' 
                   WHERE backgroundImagePath = ?`;
      await this.dbManager.executeSql(sql, [imagePath]);
      
      // 查询受影响的记录数
      const countSql = `SELECT COUNT(*) as count FROM ebook_reading_settings WHERE backgroundImagePath = ?`;
      const result = await this.dbManager.querySql(countSql, [imagePath]);
      
      logger.info(TAG, `已清除使用背景图片 ${imagePath} 的电子书设置`);
      return 0; // 返回0表示已全部清除
    } catch (error) {
      logger.error(TAG, `清除背景图片设置失败: ${String(error instanceof Error ? error.message : error)}`);
      return -1;
    }
  }

  /**
   * 删除电子书
   */
  public async deleteEBook(bookId: string): Promise<void> {
    try {
      // 先获取电子书信息，用于删除文件
      const ebook = await this.getEBookById(bookId);
      
      // 删除章节
      await this.dbManager.executeSql(`DELETE FROM ebook_chapter WHERE bookId = ?`, [bookId]);
      
      // 删除阅读进度
      await this.dbManager.executeSql(`DELETE FROM ebook_reading_progress WHERE bookId = ?`, [bookId]);
      
      // 删除阅读设置
      await this.dbManager.executeSql(`DELETE FROM ebook_reading_settings WHERE bookId = ?`, [bookId]);
      
      // 删除电子书信息
      await this.dbManager.executeSql(`DELETE FROM ebook_info WHERE id = ?`, [bookId]);

      // 删除统一标注，避免删除书籍后仍残留灵感页记录。
      await getUnifiedAnnotationManager().deleteContentAnnotations(UnifiedContentType.EBOOK, bookId);
      
      // 删除电子书文件和封面
      if (ebook) {
        await this.deleteEBookFiles(ebook);
      }
      
      logger.info(TAG, `成功删除电子书: ${bookId}`);
    } catch (error) {
      logger.error(TAG, `删除电子书失败: ${String(error instanceof Error ? error.message : error)}`);
      throw error as Error;
    }
  }
  
  /**
   * 删除电子书相关文件
   * [修复] 删除整个电子书文件夹
   */
  private async deleteEBookFiles(ebook: EBook): Promise<void> {
    try {
      const candidateDirectories: Set<string> = this.collectManagedEBookDirectories(ebook);
      const candidateFiles: Set<string> = this.collectManagedEBookFiles(ebook);
      const deletedDirectories: string[] = [];

      for (const dirPath of Array.from(candidateDirectories).sort((left, right) => right.length - left.length)) {
        if (this.deleteManagedDirectoryIfExists(dirPath)) {
          deletedDirectories.push(dirPath);
        }
      }

      for (const filePath of candidateFiles) {
        const shouldSkip: boolean = deletedDirectories.some((dirPath: string) =>
          filePath === dirPath || filePath.startsWith(`${dirPath}/`)
        );
        if (!shouldSkip) {
          this.deleteFileIfExists(filePath);
        }
      }
    } catch (error) {
      logger.error(TAG, `删除电子书文件失败: ${String(error)}`);
    }
  }

  private collectManagedEBookDirectories(ebook: EBook): Set<string> {
    const directories: Set<string> = new Set<string>();
    this.addManagedLibraryDirectoryCandidate(directories, ebook.filePath);
    this.addManagedLibraryDirectoryCandidate(directories, ebook.metadata?.coverImagePath || '');

    const downloadScopedDir = this.getDownloadScopedEBookDirectory(ebook);
    if (downloadScopedDir) {
      directories.add(downloadScopedDir);
    }
    return directories;
  }

  private collectManagedEBookFiles(ebook: EBook): Set<string> {
    const files: Set<string> = new Set<string>();
    const normalizedFilePath = this.normalizeManagedLocalPath(ebook.filePath);
    const normalizedCoverPath = this.normalizeManagedLocalPath(ebook.metadata?.coverImagePath || '');

    if (normalizedFilePath) {
      files.add(normalizedFilePath);
    }
    if (normalizedCoverPath) {
      files.add(normalizedCoverPath);
    }
    return files;
  }

  private normalizeManagedLocalPath(rawPath: string): string {
    const trimmedPath = (rawPath || '').trim();
    if (!trimmedPath) {
      return '';
    }
    return trimmedPath.startsWith('file://') ? trimmedPath.substring(7) : trimmedPath;
  }

  private addManagedLibraryDirectoryCandidate(target: Set<string>, rawPath: string): void {
    const normalizedPath = this.normalizeManagedLocalPath(rawPath);
    if (!normalizedPath || !normalizedPath.startsWith('/')) {
      return;
    }

    const managedSegments: string[] = ['/ebooks/', '/novel/'];
    for (const segment of managedSegments) {
      const segmentIndex = normalizedPath.indexOf(segment);
      if (segmentIndex < 0) {
        continue;
      }

      const contentStart = segmentIndex + segment.length;
      const remainingPath = normalizedPath.substring(contentStart);
      const slashIndex = remainingPath.indexOf('/');
      if (slashIndex < 0) {
        return;
      }

      const directoryPath = normalizedPath.substring(0, contentStart + slashIndex);
      try {
        if (fs.accessSync(directoryPath) && fs.statSync(directoryPath).isDirectory()) {
          target.add(directoryPath);
        }
      } catch (_error) {
        // 目录不存在时直接跳过，继续走文件级删除回退
      }
      return;
    }
  }

  private getDownloadScopedEBookDirectory(ebook: EBook): string {
    if (!DownloadDirManager.isReady()) {
      return '';
    }

    const title = (ebook.metadata?.title || '').trim();
    if (!title) {
      return '';
    }

    const sanitizedTitle = title.replace(/[\\/:*?"<>|]/g, '_').substring(0, 100);
    if (!sanitizedTitle) {
      return '';
    }

    const candidatePath = `${DownloadDirManager.getPath()}/ebooks/${sanitizedTitle}`;
    try {
      if (!fs.accessSync(candidatePath)) {
        return '';
      }
      const stat = fs.statSync(candidatePath);
      if (!stat.isDirectory()) {
        return '';
      }
      if (this.containsManagedEBookArtifacts(candidatePath)) {
        return candidatePath;
      }
    } catch (_error) {
      return '';
    }
    return '';
  }

  private containsManagedEBookArtifacts(dirPath: string): boolean {
    try {
      const entries: string[] = fs.listFileSync(dirPath);
      for (const entry of entries) {
        if (/^cover([_-].+)?\.(jpg|jpeg|png|webp)$/i.test(entry)) {
          return true;
        }
        if (/\.(txt|epub|mobi|azw|azw3|pdf|xml)$/i.test(entry)) {
          return true;
        }
      }
    } catch (_error) {
      return false;
    }
    return false;
  }

  private deleteManagedDirectoryIfExists(dirPath: string): boolean {
    const normalizedPath = this.normalizeManagedLocalPath(dirPath);
    if (!normalizedPath) {
      return false;
    }

    try {
      if (!fs.accessSync(normalizedPath)) {
        return false;
      }
      const stat = fs.statSync(normalizedPath);
      if (!stat.isDirectory()) {
        return false;
      }

      this.deleteDirectoryRecursive(normalizedPath);
      const deleted = !fs.accessSync(normalizedPath);
      if (deleted) {
        logger.info(TAG, `成功删除电子书目录: ${normalizedPath}`);
      } else {
        logger.warn(TAG, `电子书目录删除后仍然存在: ${normalizedPath}`);
      }
      return deleted;
    } catch (error) {
      logger.warn(TAG, `删除电子书目录失败: ${normalizedPath}, 错误: ${String(error)}`);
      return false;
    }
  }

  /**
   * 递归删除目录
   */
  private deleteDirectoryRecursive(dirPath: string): void {
    try {
      if (!fs.accessSync(dirPath)) {
        return;
      }
      
      const entries: string[] = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        const stat: fs.Stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          this.deleteDirectoryRecursive(fullPath);
        } else {
          fs.unlinkSync(fullPath);
        }
      }
      
      fs.rmdirSync(dirPath);
    } catch (error) {
      logger.warn(TAG, `递归删除目录失败 ${dirPath}: ${error}`);
    }
  }

  /**
   * 删除文件（如果存在）
   */
  private deleteFileIfExists(filePath: string): void {
    try {
      if (fs.accessSync(filePath)) {
        fs.unlinkSync(filePath);
        logger.info(TAG, `成功删除文件: ${filePath}`);
      }
    } catch (e) {
      logger.warn(TAG, `文件不存在或删除失败: ${filePath}`);
    }
  }
}
