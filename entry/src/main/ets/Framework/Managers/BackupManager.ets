import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 备份管理器
 * 负责导出和导入所有应用数据
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import { DatabaseManager } from 'manxia_core/src/main/ets/Framework/Database/DatabaseManager';
import { getNovelDataManager, NovelDataManager } from '../Novel/NovelDataManager';
import { getNovelSourceManager, NovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelSettingsManager, NovelSettingsManager } from 'manxia_core/src/main/ets/Framework/Novel/NovelSettingsManager';
import { SettingsManager, SettingKeys } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { AppInfoManager } from 'manxia_core/src/main/ets/Framework/Managers/AppInfoManager';
import {
  BackupData,
  BackupMetadata,
  MangaBackupItem,
  NovelBackupItem,
  EBookBackupItem,
  EBookReadingSettingsBackup,
  MangaSourceBackup,
  NovelSourceBackup,
  MangaChapterBackup,
  MangaReadProgressBackup,
  NovelReadProgressBackup,
  ReaderSettingsBackup,
  GenericReaderSettingsBackup,
  GlobalEBookReaderSettingsBackup,
  GlobalTextReaderSettingsBackup,
  GeneralSettingsBackup,
  PrivacySettingsBackup,
  BackupItemCounts,
  BrowseHistoryBackup,
  SearchHistoryBackup,
  SettingsBackupSection,
  HistoryBackupSection,
  SettingItemBackup,
  DEFAULT_BACKUP_OPTIONS,
  UnifiedAnnotationBackupItem
} from 'manxia_core/src/main/ets/Models/BackupModels';
import { NovelBook, NovelSourceInfo, NovelReadStatus } from 'manxia_core/src/main/ets/Models/NovelModels';
import { BrowseHistoryInput, BrowseHistoryItem } from 'manxia_core/src/main/ets/Framework/Novel/NovelSettingsManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';

const TAG = 'BackupManager';
const BACKUP_VERSION = '1.0.0';
const CREATE_UNIFIED_ANNOTATION_TABLE_SQL = `
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
`;

interface UnifiedAnnotationAnchorJson {
  chapterId?: string;
  chapterTitle?: string;
  chapterIndex?: number;
  pageIndex?: number;
  pageProgress?: number;
  startOffset?: number;
  endOffset?: number;
}

export class BackupManager {
  private static instance: BackupManager;
  // [修复] 所有管理器改为延迟初始化，避免在构造时访问未就绪的单例导致崩溃
  private _dbManager: DatabaseManager | null = null;
  private _novelDataManager: NovelDataManager | null = null;
  private _novelSourceManager: NovelSourceManager | null = null;
  private _novelSettingsManager: NovelSettingsManager | null = null;
  private _settingsManager: SettingsManager | null = null;
  private _appInfoManager: AppInfoManager | null = null;

  private get dbManager(): DatabaseManager {
    if (!this._dbManager) this._dbManager = DatabaseManager.getInstance();
    return this._dbManager;
  }
  private get novelDataManager(): NovelDataManager {
    if (!this._novelDataManager) this._novelDataManager = getNovelDataManager();
    return this._novelDataManager;
  }
  private get novelSourceManager(): NovelSourceManager {
    if (!this._novelSourceManager) this._novelSourceManager = getNovelSourceManager();
    return this._novelSourceManager;
  }
  private get novelSettingsManager(): NovelSettingsManager {
    if (!this._novelSettingsManager) this._novelSettingsManager = getNovelSettingsManager();
    return this._novelSettingsManager;
  }
  private get settingsManager(): SettingsManager {
    if (!this._settingsManager) this._settingsManager = SettingsManager.getInstance();
    return this._settingsManager;
  }
  private get appInfoManager(): AppInfoManager {
    if (!this._appInfoManager) this._appInfoManager = AppInfoManager.getInstance();
    return this._appInfoManager;
  }

  private constructor() {
    // [修复] 构造函数不再立即初始化管理器，推迟到首次访问时
  }

  static getInstance(): BackupManager {
    if (!BackupManager.instance) {
      BackupManager.instance = new BackupManager();
    }
    return BackupManager.instance;
  }

  async createBackup(): Promise<string> {
    try {
      logger.info(TAG, 'Starting backup creation');
      
      const appVersion = await this.getAppVersion();
      
      const backupData: BackupData = {
        version: BACKUP_VERSION,
        appVersion: appVersion,
        timestamp: Date.now(),
        deviceInfo: this.getDeviceInfo(),
        
        manga: {
          library: await this.exportMangaLibrary(),
          readProgress: await this.exportMangaReadProgress(),
          categories: await this.exportMangaCategories()
        },
        
        novel: {
          library: await this.exportNovelLibrary(),
          readProgress: await this.exportNovelReadProgress(),
          categories: await this.exportNovelCategories()
        },
        
        ebook: {
          library: await this.exportEBookLibrary()
        },
        
        sources: {
          manga: await this.exportMangaSources(),
          novel: await this.exportNovelSources()
        },
        
        settings: {
          reader: await this.exportReaderSettings(),
          general: await this.exportGeneralSettings(),
          privacy: await this.exportPrivacySettings(),
          allSettings: await this.exportAllSettings()
        },
        
        history: {
          browse: await this.exportBrowseHistory(),
          search: await this.exportSearchHistory()
        },

        annotations: {
          records: await this.exportUnifiedAnnotations()
        }
      };

      const fileName = `manxia_backup_${this.formatDate(Date.now())}.json`;
      const filePath = await this.saveBackupFile(fileName, backupData);
      
      logger.info(TAG, `Backup created: ${filePath}`);
      return filePath;
    } catch (error) {
      logger.error(TAG, `Backup creation failed: ${error}`);
      throw new Error(`Backup creation failed: ${error}`);
    }
  }

  async restoreBackup(filePath: string): Promise<void> {
    try {
      logger.info(TAG, `Starting backup restore: ${filePath}`);
      
      const backupData = await this.loadBackupFile(filePath);
      this.validateBackupData(backupData);

      const failures: string[] = [];
      await this.runLegacyRestoreTask('漫画库', async () => { await this.restoreMangaLibrary(backupData.manga.library); }, failures);
      await this.runLegacyRestoreTask('小说库', async () => { await this.restoreNovelLibrary(backupData.novel.library); }, failures);
      await this.runLegacyRestoreTask('电子书库', async () => { await this.restoreEBookLibrary(backupData.ebook.library); }, failures);
      await this.runLegacyRestoreTask('漫画源', async () => { await this.restoreMangaSources(backupData.sources.manga); }, failures);
      await this.runLegacyRestoreTask('小说源', async () => { await this.restoreNovelSources(backupData.sources.novel); }, failures);
      await this.runLegacyRestoreTask('漫画阅读进度', async () => { await this.restoreMangaReadProgress(backupData.manga.readProgress); }, failures);
      await this.runLegacyRestoreTask('小说阅读进度', async () => { await this.restoreNovelReadProgress(backupData.novel.readProgress); }, failures);
      await this.runLegacyRestoreTask('设置', async () => { await this.restoreSettings(backupData.settings); }, failures);
      await this.runLegacyRestoreTask('历史记录', async () => { await this.restoreHistory(backupData.history); }, failures);
      if (backupData.annotations && backupData.annotations.records) {
        const annotationRecords = backupData.annotations.records;
        await this.runLegacyRestoreTask('统一标注', async () => { await this.restoreUnifiedAnnotations(annotationRecords); }, failures);
      }

      if (failures.length > 0) {
        throw new Error(`旧版JSON备份恢复部分失败: ${failures.join('; ')}`);
      }
      
      logger.info(TAG, 'Backup restore completed');
    } catch (error) {
      logger.error(TAG, `Backup restore failed: ${error}`);
      throw new Error(`Backup restore failed: ${error}`);
    }
  }

  private async runLegacyRestoreTask(name: string, runner: () => Promise<void>, failures: string[]): Promise<void> {
    try {
      await runner();
    } catch (error) {
      const message = `${name}: ${String(error)}`;
      failures.push(message);
      logger.error(TAG, `旧版JSON恢复${name}失败: ${error}`);
    }
  }

  async getBackupMetadata(filePath: string): Promise<BackupMetadata> {
    try {
      const sandboxManager = SandboxManager.getInstance();
      const content = await sandboxManager.readTextFile(filePath);
      const data = SafeUtils.parseObj(content) as BackupData;
      
      const itemCounts: BackupItemCounts = {
        manga: data.manga?.library?.length || 0,
        novel: data.novel?.library?.length || 0,
        ebook: data.ebook?.library?.length || 0,
        sources: (data.sources?.manga?.length || 0) + (data.sources?.novel?.length || 0),
        annotations: data.annotations?.records?.length || 0
      };
      
      return {
        version: data.version,
        appVersion: data.appVersion,
        timestamp: data.timestamp,
        deviceInfo: data.deviceInfo,
        itemCounts: itemCounts,
        options: DEFAULT_BACKUP_OPTIONS,
        fileSize: 0
      };
    } catch (error) {
      logger.error(TAG, `Failed to read backup metadata: ${error}`);
      throw new Error(`Failed to read backup metadata: ${error}`);
    }
  }

  private async exportMangaLibrary(): Promise<MangaBackupItem[]> {
    try {
      const sql = 'SELECT * FROM comic_info';
      const results = await this.dbManager.querySql(sql);
      const backupItems: MangaBackupItem[] = [];
      
      for (const record of results) {
        const manga = record as Record<string, DatabaseRecord>;
        const mangaId = String(manga['id']);
        
        const chaptersSql = 'SELECT * FROM chapter WHERE comicId = ?';
        const chaptersResults = await this.dbManager.querySql(chaptersSql, [mangaId]);
        const chapters: MangaChapterBackup[] = [];
        
        for (const chRec of chaptersResults) {
          const ch = chRec as Record<string, DatabaseRecord>;
          chapters.push({
            id: String(ch['id']),
            title: String(ch['title'] || ''),
            url: String(ch['url'] || ''),
            chapterNumber: String(ch['chapterNumber'] || '0'),
            scanlator: String(ch['scanlator'] || ''),
            uploadDate: Number(ch['uploadDate'] || 0),
            dateUploaded: Number(ch['dateUploaded'] || 0),
            chapterIndex: Number(ch['chapterIndex'] || 0),
            read: Boolean(ch['read']),
            bookmark: Boolean(ch['bookmark']),
            lastPageRead: Number(ch['lastPageRead'] || 0),
            dateFetch: Number(ch['dateFetch'] || 0),
            sourceOrder: Number(ch['sourceOrder'] || 0)
          });
        }
        
        backupItems.push({
          id: mangaId,
          sourceId: String(manga['sourceId'] || ''),
          sourceName: String(manga['sourceName'] || ''),
          url: String(manga['url'] || ''),
          title: String(manga['title'] || ''),
          author: String(manga['author'] || ''),
          artist: String(manga['artist'] || ''),
          description: String(manga['description'] || ''),
          genre: SafeUtils.parseObj(String(manga['genre'] || '[]')),
          status: String(manga['status'] || ''),
          coverUrl: String(manga['coverUrl'] || ''),
          coverLocalPath: String(manga['coverLocalPath'] || ''),
          isFavorite: Boolean(manga['isFavorite']),
          isPrivate: Boolean(manga['isPrivate']),
          isNSFW: Boolean(manga['isNSFW']),
          categories: [],
          lastUpdateTime: Number(manga['lastUpdateTime'] || 0),
          dateAdded: Number(manga['dateAdded'] || Date.now()),
          chapters: chapters,
          lastReadChapterId: String(manga['lastReadChapterId'] || ''),
          lastReadChapterIndex: Number(manga['lastReadChapterIndex'] || 0),
          lastReadPage: Number(manga['lastReadPage'] || 0),
          lastReadTime: Number(manga['lastReadTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported manga library: ${backupItems.length} items`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export manga library: ${error}`);
      return [];
    }
  }

  private async exportNovelLibrary(): Promise<NovelBackupItem[]> {
    try {
      // [修复] 直接从数据库导出所有书籍，而不仅仅是收藏的
      const sql = 'SELECT * FROM novel_book ORDER BY lastReadTime DESC';
      const results = await this.dbManager.querySql(sql);
      const backupItems: NovelBackupItem[] = [];
      
      for (const record of results) {
        const novel = record as Record<string, string | number | boolean | null>;
        backupItems.push({
          id: String(novel['id'] || ''),
          sourceId: String(novel['sourceId'] || ''),
          sourceName: String(novel['sourceName'] || ''),
          bookUrl: String(novel['bookUrl'] || ''),
          name: String(novel['name'] || ''),
          author: String(novel['author'] || ''),
          kind: String(novel['kind'] || ''),
          intro: String(novel['intro'] || ''),
          coverUrl: String(novel['coverUrl'] || ''),
          coverLocalPath: String(novel['coverLocalPath'] || ''),
          tocUrl: String(novel['tocUrl'] || ''),
          latestChapterTitle: String(novel['latestChapterTitle'] || ''),
          wordCount: String(novel['wordCount'] || ''),
          chapterCount: Number(novel['chapterCount'] || 0),
          readStatus: String(novel['readStatus'] || 'unread'),
          isFavorite: Boolean(novel['isFavorite']),
          isPrivate: Boolean(novel['isPrivate']),
          isNSFW: Boolean(novel['isNSFW']),
          groupName: String(novel['groupName'] || ''),
          createTime: Number(novel['createTime'] || 0),
          updateDbTime: Number(novel['updateTime'] || 0),
          lastReadChapterId: String(novel['lastReadChapterId'] || ''),
          lastReadChapterIndex: Number(novel['lastReadChapterIndex'] || 0),
          lastReadPosition: Number(novel['lastReadPosition'] || 0),
          lastReadTime: Number(novel['lastReadTime'] || 0),
          totalReadingTime: Number(novel['totalReadingTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported novel library: ${backupItems.length} items (all books)`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export novel library: ${error}`);
      return [];
    }
  }

  private async exportEBookLibrary(): Promise<EBookBackupItem[]> {
    try {
      const sql = 'SELECT * FROM ebook_info';
      const results = await this.dbManager.querySql(sql);
      const backupItems: EBookBackupItem[] = [];
      
      for (const record of results) {
        const ebook = record as Record<string, DatabaseRecord>;
        const bookId = String(ebook['id']);
        const settingsSql = 'SELECT * FROM ebook_reading_settings WHERE bookId = ? LIMIT 1';
        const settingsResults = await this.dbManager.querySql(settingsSql, [bookId]);
        let readingSettings: EBookReadingSettingsBackup | undefined = undefined;
        if (settingsResults.length > 0) {
          const settingsRecord = settingsResults[0] as Record<string, string | number | boolean | null>;
          readingSettings = this.createEBookReadingSettingsBackup(settingsRecord);
        }

        backupItems.push({
          id: bookId,
          format: String(ebook['format']),
          title: String(ebook['title']),
          author: String(ebook['author'] || ''),
          publisher: String(ebook['publisher'] || ''),
          publishDate: String(ebook['publishDate'] || ''),
          isbn: String(ebook['isbn'] || ''),
          language: String(ebook['language'] || ''),
          description: String(ebook['description'] || ''),
          coverPath: String(ebook['coverPath'] || ''),
          filePath: String(ebook['filePath']),
          fileSize: Number(ebook['fileSize'] || 0),
          totalPages: Number(ebook['totalPages'] || 0),
          currentPage: Number(ebook['currentPage'] || 0),
          readProgress: Number(ebook['readProgress'] || 0),
          lastReadTime: Number(ebook['lastReadTime'] || 0),
          lastUpdateTime: Number(ebook['lastUpdateTime'] || 0),
          isFavorite: Boolean(ebook['isFavorite']),
          isPrivate: Boolean(ebook['isPrivate']),
          isNSFW: Boolean(ebook['isNSFW']),
          totalWordCount: Number(ebook['totalWordCount'] || 0),
          readingSettings: readingSettings
        });
      }
      
      logger.info(TAG, `Exported ebook library: ${backupItems.length} items`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export ebook library: ${error}`);
      return [];
    }
  }

  private createEBookReadingSettingsBackup(
    settings: Record<string, string | number | boolean | null>
  ): EBookReadingSettingsBackup {
    return {
      bookId: this.getRecordString(settings, 'bookId', ''),
      userId: this.getRecordString(settings, 'userId', 'default_user'),
      fontSize: this.getRecordNumber(settings, 'fontSize', 18),
      fontFamily: this.getRecordString(settings, 'fontFamily', 'HarmonyOS Sans'),
      fontPath: this.getRecordString(settings, 'fontPath', ''),
      fontWeight: this.getRecordNumber(settings, 'fontWeight', 400),
      lineHeight: this.getRecordNumber(settings, 'lineHeight', 1.5),
      backgroundColor: this.getRecordString(settings, 'backgroundColor', '#FFFFFF'),
      textColor: this.getRecordString(settings, 'textColor', '#000000'),
      themeBgImage: this.getRecordString(settings, 'themeBgImage', ''),
      nightMode: this.getRecordNumber(settings, 'nightMode', 0),
      followSystemTheme: this.getRecordNumber(settings, 'followSystemTheme', 1),
      pageMargin: this.getRecordNumber(settings, 'pageMargin', 16),
      pageTopMargin: this.getRecordNumber(settings, 'pageTopMargin', 24),
      pageBottomMargin: this.getRecordNumber(settings, 'pageBottomMargin', 24),
      pageMode: this.getRecordString(settings, 'pageMode', '0'),
      brightness: this.getRecordNumber(settings, 'brightness', 100),
      autoSave: this.getRecordNumber(settings, 'autoSave', 1),
      saveInterval: this.getRecordNumber(settings, 'saveInterval', 30),
      letterSpacing: this.getRecordNumber(settings, 'letterSpacing', 0),
      paragraphSpacing: this.getRecordNumber(settings, 'paragraphSpacing', 8),
      firstLineIndent: this.getRecordNumber(settings, 'firstLineIndent', 2),
      textAlignment: this.getRecordString(settings, 'textAlignment', 'JUSTIFY'),
      pageTurnAnimation: this.getRecordString(settings, 'pageTurnAnimation', 'SLIDE'),
      tapToTurn: this.getRecordNumber(settings, 'tapToTurn', 1),
      volumeKeyNavigation: this.getRecordNumber(settings, 'volumeKeyNavigation', 1),
      keepScreenOn: this.getRecordNumber(settings, 'keepScreenOn', 0),
      lockDeviceOrientation: this.getRecordNumber(settings, 'lockDeviceOrientation', 0),
      showPageNumber: this.getRecordNumber(settings, 'showPageNumber', 1),
      showProgress: this.getRecordNumber(settings, 'showProgress', 0),
      showTime: this.getRecordNumber(settings, 'showTime', 1),
      showBattery: this.getRecordNumber(settings, 'showBattery', 0),
      backgroundType: this.getRecordString(settings, 'backgroundType', 'COLOR'),
      backgroundImagePath: this.getRecordString(settings, 'backgroundImagePath', ''),
      backgroundImageOpacity: this.getRecordNumber(settings, 'backgroundImageOpacity', 0.3),
      imageReaderSettingsJson: this.getRecordString(settings, 'imageReaderSettingsJson', '')
    };
  }

  private getRecordString(
    record: Record<string, string | number | boolean | null>,
    key: string,
    fallback: string
  ): string {
    const value = record[key];
    if (value === null || value === undefined) {
      return fallback;
    }
    return String(value);
  }

  private getRecordNumber(
    record: Record<string, string | number | boolean | null>,
    key: string,
    fallback: number
  ): number {
    const value = record[key];
    if (value === null || value === undefined || value === '') {
      return fallback;
    }
    return Number(value);
  }

  private async exportMangaSources(): Promise<MangaSourceBackup[]> {
    try {
      const sql = 'SELECT * FROM comic_source';
      const results = await this.dbManager.querySql(sql);
      const backupItems: MangaSourceBackup[] = [];
      
      for (const record of results) {
        const source = record as Record<string, DatabaseRecord>;
        backupItems.push({
          id: String(source['id']),
          name: String(source['name']),
          baseUrl: String(source['baseUrl'] || ''),
          lang: String(source['lang'] || 'en'),
          isEnabled: Boolean(source['enabled']),
          isNSFW: Boolean(source['isNSFW']),
          lastUsedTime: Number(source['lastUsedTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported manga sources: ${backupItems.length} items`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export manga sources: ${error}`);
      return [];
    }
  }

  private async exportNovelSources(): Promise<NovelSourceBackup[]> {
    try {
      // [修复] 直接从数据库导出完整的书源配置
      const sql = 'SELECT * FROM novel_source';
      const results = await this.dbManager.querySql(sql);
      const backupItems: NovelSourceBackup[] = [];
      
      for (const record of results) {
        const source = record as Record<string, string | number | boolean | null>;
        backupItems.push({
          id: String(source['id'] || ''),
          bookSourceUrl: String(source['bookSourceUrl'] || ''),
          bookSourceName: String(source['bookSourceName'] || ''),
          bookSourceGroup: String(source['bookSourceGroup'] || ''),
          bookSourceType: Number(source['bookSourceType'] || 0),
          enabled: Boolean(source['enabled']),
          weight: Number(source['weight'] || 0),
          respondTime: Number(source['respondTime'] || 180000),
          configJson: String(source['configJson'] || ''),
          createTime: Number(source['createTime'] || 0),
          updateTime: Number(source['updateTime'] || 0),
          // 兼容字段
          name: String(source['bookSourceName'] || ''),
          sourceUrl: String(source['bookSourceUrl'] || ''),
          lastUpdateTime: Number(source['lastUpdateTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported novel sources: ${backupItems.length} items (with configJson)`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export novel sources: ${error}`);
      return [];
    }
  }

  private async exportMangaReadProgress(): Promise<MangaReadProgressBackup[]> {
    try {
      const sql = 'SELECT * FROM read_history';
      const results = await this.dbManager.querySql(sql);
      const progress: MangaReadProgressBackup[] = [];
      
      for (const record of results) {
        const rec = record as Record<string, DatabaseRecord>;
        progress.push({
          mangaId: String(rec['comicId']),
          chapterId: String(rec['chapterId']),
          pageIndex: Number(rec['pageIndex'] || 0),
          totalPages: Number(rec['totalPages'] || 0),
          lastReadTime: Number(rec['readTime'] || 0)
        });
      }
      
      return progress;
    } catch (error) {
      logger.error(TAG, `Failed to export manga read progress: ${error}`);
      return [];
    }
  }

  private async exportNovelReadProgress(): Promise<NovelReadProgressBackup[]> {
    try {
      const sql = 'SELECT * FROM novel_read_progress';
      const results = await this.dbManager.querySql(sql);
      const progress: NovelReadProgressBackup[] = [];
      
      for (const record of results) {
        const rec = record as Record<string, DatabaseRecord>;
        progress.push({
          bookId: String(rec['bookId']),
          chapterId: String(rec['chapterId']),
          chapterIndex: Number(rec['chapterIndex'] || 0),
          position: Number(rec['position'] || 0),
          progress: Number(rec['progress'] || 0),
          readTime: Number(rec['readTime'] || 0)
        });
      }
      
      return progress;
    } catch (error) {
      logger.error(TAG, `Failed to export novel read progress: ${error}`);
      return [];
    }
  }

  private async exportMangaCategories(): Promise<string[]> {
    return [];
  }

  private async exportNovelCategories(): Promise<string[]> {
    try {
      return await this.novelDataManager.getBookGroups();
    } catch (error) {
      logger.error(TAG, `Failed to export novel categories: ${error}`);
      return [];
    }
  }

  private async exportReaderSettings(): Promise<ReaderSettingsBackup> {
    try {
      const emptySettings: GenericReaderSettingsBackup = {};
      const mangaSettings = this.settingsManager.getJSON<GenericReaderSettingsBackup>('manga_reader_settings', emptySettings);
      const novelSettings = this.settingsManager.getJSON<GenericReaderSettingsBackup>('novel_reader_settings', emptySettings);
      const ebookSettings: GlobalEBookReaderSettingsBackup = {
        global_ebook_lock_device_orientation: this.settingsManager.getBoolean(
          SettingKeys.GLOBAL_EBOOK_LOCK_DEVICE_ORIENTATION,
          false
        )
      };
      const textSettings: GlobalTextReaderSettingsBackup = {
        global_text_lock_device_orientation: this.settingsManager.getBoolean(
          SettingKeys.GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION,
          false
        )
      };
      return {
        manga: mangaSettings,
        novel: novelSettings,
        ebook: ebookSettings,
        text: textSettings
      };
    } catch (error) {
      logger.error(TAG, `Failed to export reader settings: ${error}`);
      const emptyRecord: GenericReaderSettingsBackup = {};
      return { manga: emptyRecord, novel: emptyRecord };
    }
  }

  private async exportAllSettings(): Promise<SettingItemBackup[]> {
    try {
      const dataManager = (await import('../Data/DataManager')).DataManager.getInstance();
      const allSettings = await dataManager.getAllSettings();
      const result: SettingItemBackup[] = [];
      for (const setting of allSettings) {
        result.push({
          settingKey: setting.settingKey,
          settingValue: setting.settingValue,
          settingType: setting.settingType
        });
      }
      logger.info(TAG, `Exported all settings: ${result.length} items`);
      return result;
    } catch (error) {
      logger.error(TAG, `Failed to export all settings: ${error}`);
      return [];
    }
  }

  private async exportGeneralSettings(): Promise<GeneralSettingsBackup> {
    try {
      return {
        theme: this.settingsManager.getString('app_theme', 'auto'),
        language: this.settingsManager.getString('app_language', 'zh-CN')
      };
    } catch (error) {
      logger.error(TAG, `Failed to export general settings: ${error}`);
      return { theme: 'auto', language: 'zh-CN' };
    }
  }

  private async exportPrivacySettings(): Promise<PrivacySettingsBackup> {
    try {
      return {
        sfwMode: this.settingsManager.getBoolean('sfw_mode_enabled', false),
        privateLibraryEnabled: this.settingsManager.getBoolean('private_library_enabled', false)
      };
    } catch (error) {
      logger.error(TAG, `Failed to export privacy settings: ${error}`);
      return { sfwMode: false, privateLibraryEnabled: false };
    }
  }

  private async exportBrowseHistory(): Promise<BrowseHistoryBackup[]> {
    try {
      const novelHistory = this.novelSettingsManager.getBrowseHistory();
      return novelHistory.map((item: BrowseHistoryItem): BrowseHistoryBackup => ({
        sourceId: item.sourceId,
        contentId: item.bookUrl,
        contentType: 'novel' as 'manga' | 'novel' | 'ebook',
        title: item.bookName,
        coverUrl: item.coverUrl,
        browseTime: item.browseTime
      }));
    } catch (error) {
      logger.error(TAG, `Failed to export browse history: ${error}`);
      return [];
    }
  }

  private async exportSearchHistory(): Promise<SearchHistoryBackup[]> {
    const historyMap = new Map<string, SearchHistoryBackup>();
    const now = Date.now();
    
    try {
      const settingsHistory = this.novelSettingsManager.getSearchHistory();
      settingsHistory.forEach((keyword: string, index: number) => {
        const normalizedKeyword = keyword.trim();
        if (!normalizedKeyword) {
          return;
        }
        historyMap.set(normalizedKeyword, {
          keyword: normalizedKeyword,
          searchTime: now - index,
          contentType: 'novel'
        });
      });
    } catch (error) {
      logger.warn(TAG, `Failed to read search history from settings: ${error}`);
    }
    
    try {
      const sql = 'SELECT keyword, searchTime FROM novel_search_history ORDER BY searchTime DESC';
      const results = await this.dbManager.querySql(sql);
      for (const row of results) {
        const record = row as Record<string, DatabaseRecord>;
        const keyword = String(record['keyword'] || '').trim();
        if (!keyword) {
          continue;
        }
        const searchTime = Number(record['searchTime'] || now);
        const existing = historyMap.get(keyword);
        if (!existing || searchTime > existing.searchTime) {
          historyMap.set(keyword, {
            keyword: keyword,
            searchTime: searchTime,
            contentType: 'novel'
          });
        }
      }
    } catch (error) {
      logger.warn(TAG, `Failed to export search history from table novel_search_history: ${error}`);
    }
    
    return Array.from(historyMap.values()).sort((a, b) => b.searchTime - a.searchTime);
  }

  private async exportUnifiedAnnotations(): Promise<UnifiedAnnotationBackupItem[]> {
    try {
      await this.ensureUnifiedAnnotationTable();
      const sql = `
        SELECT
          id, contentType, contentId, annotationType, title, textContent, quoteText,
          chapterId, chapterTitle, chapterIndex, pageIndex, pageProgress,
          startOffset, endOffset, anchorJson, styleJson, linkedAnnotationId,
          createTime, updateTime
        FROM unified_annotation
        WHERE isDeleted = 0
        ORDER BY createTime DESC
      `;
      const results = await this.dbManager.querySql(sql);
      const records: UnifiedAnnotationBackupItem[] = [];
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        records.push({
          id: String(rec['id'] || ''),
          contentType: this.normalizeAnnotationContentTypeForBackup(String(rec['contentType'] || 'novel')),
          contentId: String(rec['contentId'] || ''),
          annotationType: this.normalizeAnnotationTypeForBackup(String(rec['annotationType'] || 'bookmark')),
          title: String(rec['title'] || ''),
          textContent: String(rec['textContent'] || ''),
          quoteText: String(rec['quoteText'] || ''),
          chapterId: String(rec['chapterId'] || ''),
          chapterTitle: String(rec['chapterTitle'] || ''),
          chapterIndex: Number(rec['chapterIndex'] ?? -1),
          pageIndex: Number(rec['pageIndex'] ?? -1),
          pageProgress: Number(rec['pageProgress'] ?? -1),
          startOffset: Number(rec['startOffset'] ?? -1),
          endOffset: Number(rec['endOffset'] ?? -1),
          anchorJson: this.normalizeAnnotationAnchorJson(String(rec['anchorJson'] || '')),
          styleJson: String(rec['styleJson'] || ''),
          linkedAnnotationId: String(rec['linkedAnnotationId'] || ''),
          createTime: Number(rec['createTime'] ?? 0),
          updateTime: Number(rec['updateTime'] ?? 0)
        });
      }
      logger.info(TAG, `导出统一标注: ${records.length} 条`);
      return records;
    } catch (error) {
      logger.warn(TAG, `导出统一标注失败，已跳过: ${error}`);
      return [];
    }
  }

  private async restoreMangaLibrary(items: MangaBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring manga library: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        const sqlManga = 'INSERT OR REPLACE INTO comic_info (id, sourceId, sourceName, url, title, author, artist, description, genre, status, coverUrl, coverLocalPath, isFavorite, isPrivate, isNSFW, lastUpdateTime, dateAdded, lastReadChapterId, lastReadChapterIndex, lastReadPage, lastReadTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sqlManga, [
          item.id, item.sourceId, item.sourceName, item.url, item.title,
          item.author, item.artist, item.description, JSON.stringify(item.genre), item.status,
          item.coverUrl, item.coverLocalPath || '', item.isFavorite ? 1 : 0,
          item.isPrivate ? 1 : 0, item.isNSFW ? 1 : 0, item.lastUpdateTime, item.dateAdded,
          item.lastReadChapterId || '', item.lastReadChapterIndex || 0, item.lastReadPage || 0, item.lastReadTime || 0
        ]);
        
        for (const chapter of item.chapters) {
          const sqlChapter = 'INSERT OR REPLACE INTO chapter (id, comicId, title, url, chapterNumber, scanlator, uploadDate, dateUploaded, chapterIndex, read, bookmark, lastPageRead, dateFetch, sourceOrder) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
          
          await this.dbManager.executeSql(sqlChapter, [
            chapter.id, item.id, chapter.title, chapter.url, chapter.chapterNumber,
            chapter.scanlator, chapter.uploadDate, chapter.dateUploaded, chapter.chapterIndex,
            chapter.read ? 1 : 0, chapter.bookmark ? 1 : 0, chapter.lastPageRead,
            chapter.dateFetch, chapter.sourceOrder
          ]);
        }
      } catch (error) {
        failures.push(`${item.title}: ${String(error)}`);
        logger.error(TAG, `Failed to restore manga: ${item.title}, ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`漫画库恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Manga library restore completed');
  }

  private async restoreNovelLibrary(items: NovelBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring novel library: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        const novel: NovelBook = {
          id: item.id,
          sourceId: item.sourceId,
          sourceName: item.sourceName,
          bookUrl: item.bookUrl,
          name: item.name,
          author: item.author,
          kind: item.kind,
          intro: item.intro,
          coverUrl: item.coverUrl,
          coverLocalPath: item.coverLocalPath,
          tocUrl: item.tocUrl,
          latestChapterTitle: item.latestChapterTitle,
          wordCount: item.wordCount,
          chapterCount: item.chapterCount,
          readStatus: (item.readStatus === 'unread' || item.readStatus === 'reading' || item.readStatus === 'finished') ? (item.readStatus === 'unread' ? NovelReadStatus.UNREAD : item.readStatus === 'reading' ? NovelReadStatus.READING : NovelReadStatus.FINISHED) : NovelReadStatus.UNREAD,
          lastReadChapterId: item.lastReadChapterId,
          lastReadChapterIndex: item.lastReadChapterIndex,
          lastReadPosition: item.lastReadPosition,
          lastReadTime: item.lastReadTime,
          totalReadingTime: item.totalReadingTime || 0,
          isFavorite: item.isFavorite,
          isPrivate: item.isPrivate,
          isNSFW: item.isNSFW,
          groupName: item.groupName,
          createTime: item.createTime,
          updateDbTime: item.updateDbTime
        };
        
        await this.novelDataManager.saveBook(novel);
      } catch (error) {
        failures.push(`${item.name}: ${String(error)}`);
        logger.error(TAG, `Failed to restore novel: ${item.name}, ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`小说库恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Novel library restore completed');
  }

  private async restoreEBookLibrary(items: EBookBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring ebook library: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        const sql = 'INSERT OR REPLACE INTO ebook_info (id, format, title, author, publisher, publishDate, isbn, language, description, coverPath, filePath, fileSize, totalPages, currentPage, readProgress, lastReadTime, lastUpdateTime, isFavorite, isPrivate, isNSFW, totalWordCount) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.id, item.format, item.title, item.author, item.publisher,
          item.publishDate, item.isbn, item.language, item.description,
          item.coverPath, item.filePath, item.fileSize, item.totalPages,
          item.currentPage, item.readProgress, item.lastReadTime,
          item.lastUpdateTime, item.isFavorite ? 1 : 0,
          item.isPrivate ? 1 : 0, item.isNSFW ? 1 : 0, item.totalWordCount || 0
        ]);
        if (item.readingSettings) {
          await this.restoreEBookReadingSettings(item.id, item.readingSettings);
        }
      } catch (error) {
        failures.push(`${item.title}: ${String(error)}`);
        logger.error(TAG, `Failed to restore ebook: ${item.title}, ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`电子书库恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Ebook library restore completed');
  }

  private async restoreEBookReadingSettings(bookId: string, settings: EBookReadingSettingsBackup): Promise<void> {
    const now = Date.now();
    const sql = `
      INSERT OR REPLACE INTO ebook_reading_settings (
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
    await this.dbManager.executeSql(sql, [
      bookId,
      settings.userId ?? 'default_user',
      settings.fontSize ?? 18,
      settings.fontFamily ?? 'HarmonyOS Sans',
      settings.fontPath ?? '',
      settings.fontWeight ?? 400,
      settings.lineHeight ?? 1.5,
      settings.backgroundColor ?? '#FFFFFF',
      settings.textColor ?? '#000000',
      settings.themeBgImage ?? '',
      settings.nightMode ?? 0,
      settings.followSystemTheme ?? 1,
      settings.pageMargin ?? 16,
      settings.pageTopMargin ?? settings.pageMargin ?? 24,
      settings.pageBottomMargin ?? settings.pageMargin ?? 24,
      settings.pageMode ?? '0',
      settings.brightness ?? 100,
      settings.autoSave ?? 1,
      settings.saveInterval ?? 30,
      settings.letterSpacing ?? 0,
      settings.paragraphSpacing ?? 8,
      settings.firstLineIndent ?? 2,
      settings.textAlignment ?? 'JUSTIFY',
      settings.pageTurnAnimation ?? 'SLIDE',
      settings.tapToTurn ?? 1,
      settings.volumeKeyNavigation ?? 1,
      settings.keepScreenOn ?? 0,
      settings.lockDeviceOrientation ?? 0,
      settings.showPageNumber ?? 1,
      settings.showProgress ?? 0,
      settings.showTime ?? 1,
      settings.showBattery ?? 0,
      settings.backgroundType ?? 'COLOR',
      settings.backgroundImagePath ?? '',
      settings.backgroundImageOpacity ?? 0.3,
      settings.imageReaderSettingsJson ?? '',
      now,
      now
    ]);
  }

  private async restoreMangaSources(items: MangaSourceBackup[]): Promise<void> {
    logger.info(TAG, `Restoring manga sources: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        const sql = 'INSERT OR REPLACE INTO comic_source (id, name, baseUrl, lang, enabled, isNSFW, lastUsedTime) VALUES (?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.id, item.name, item.baseUrl, item.lang,
          item.isEnabled ? 1 : 0, item.isNSFW ? 1 : 0, item.lastUsedTime || 0
        ]);
      } catch (error) {
        failures.push(`${item.name}: ${String(error)}`);
        logger.error(TAG, `Failed to restore manga source: ${item.name}, ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`漫画源恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Manga sources restore completed');
  }

  private async restoreNovelSources(items: NovelSourceBackup[]): Promise<void> {
    logger.info(TAG, `Restoring novel sources: ${items.length} items`);
    
    for (const item of items) {
      try {
        logger.warn(TAG, `Novel source restore requires full configuration, skipping: ${item.name}`);
      } catch (error) {
        logger.error(TAG, `Failed to restore novel source: ${item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Novel sources restore completed');
  }

  private async restoreMangaReadProgress(items: MangaReadProgressBackup[]): Promise<void> {
    logger.info(TAG, `Restoring manga read progress: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        const comicExists = await this.dbManager.querySql('SELECT id FROM comic_info WHERE id = ?', [item.mangaId]);
        const chapterExists = await this.dbManager.querySql('SELECT id FROM chapter WHERE id = ?', [item.chapterId]);
        if (comicExists.length === 0 || chapterExists.length === 0) {
          logger.debug(TAG, `Skipping read progress without matching comic/chapter: ${item.mangaId}/${item.chapterId}`);
          continue;
        }

        const now = Date.now();
        const sql = 'INSERT OR REPLACE INTO read_history (comicId, chapterId, userId, pageNumber, readTime, duration, createTime) VALUES (?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.mangaId,
          item.chapterId,
          'default',
          item.pageIndex || 0,
          item.lastReadTime || now,
          0,
          now
        ]);
      } catch (error) {
        failures.push(`${item.mangaId}/${item.chapterId}: ${String(error)}`);
        logger.error(TAG, `Failed to restore manga read progress: ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`漫画阅读进度恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Manga read progress restore completed');
  }

  private async restoreNovelReadProgress(items: NovelReadProgressBackup[]): Promise<void> {
    logger.info(TAG, `Restoring novel read progress: ${items.length} items`);
    const failures: string[] = [];
    
    for (const item of items) {
      try {
        await this.novelDataManager.saveReadProgress({
          bookId: item.bookId,
          chapterId: item.chapterId,
          chapterIndex: item.chapterIndex,
          position: item.position,
          progress: item.progress,
          readTime: item.readTime
        });
      } catch (error) {
        failures.push(`${item.bookId}/${item.chapterId}: ${String(error)}`);
        logger.error(TAG, `Failed to restore novel read progress: ${error}`);
      }
    }

    if (failures.length > 0) {
      throw new Error(`小说阅读进度恢复失败 ${failures.length}/${items.length}: ${failures.join('; ')}`);
    }
    
    logger.info(TAG, 'Novel read progress restore completed');
  }

  private async restoreSettings(settings: SettingsBackupSection): Promise<void> {
    logger.info(TAG, 'Restoring settings');
    
    try {
      if (settings.reader) {
        if (settings.reader.manga) {
          this.settingsManager.setJSON('manga_reader_settings', settings.reader.manga);
        }
        if (settings.reader.novel) {
          this.settingsManager.setJSON('novel_reader_settings', settings.reader.novel);
        }
        if (settings.reader.ebook) {
          const ebookLock = this.getBackupBooleanValue(
            settings.reader.ebook.global_ebook_lock_device_orientation
          );
          if (ebookLock !== null) {
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_EBOOK_LOCK_DEVICE_ORIENTATION, ebookLock);
          }
        }
        if (settings.reader.text) {
          const textLock = this.getBackupBooleanValue(
            settings.reader.text.global_text_lock_device_orientation
          );
          if (textLock !== null) {
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_LOCK_DEVICE_ORIENTATION, textLock);
          }
        }
      }
      
      if (settings.general) {
        if (settings.general.theme) {
          this.settingsManager.setString('app_theme', settings.general.theme);
        }
        if (settings.general.language) {
          this.settingsManager.setString('app_language', settings.general.language);
        }
      }
      
      if (settings.privacy) {
        if (settings.privacy.sfwMode !== undefined) {
          this.settingsManager.setBoolean('sfw_mode_enabled', settings.privacy.sfwMode);
        }
        if (settings.privacy.privateLibraryEnabled !== undefined) {
          this.settingsManager.setBoolean('private_library_enabled', settings.privacy.privateLibraryEnabled);
        }
      }

      if (settings.allSettings) {
        await this.restoreAllSettings(settings.allSettings);
      }
      
      logger.info(TAG, 'Settings restore completed');
    } catch (error) {
      logger.error(TAG, `Failed to restore settings: ${error}`);
      throw new Error(`设置恢复失败: ${error}`);
    }
  }

  private async restoreAllSettings(allSettings: SettingItemBackup[]): Promise<void> {
    if (allSettings.length === 0) {
      return;
    }

    const dataManager = (await import('../Data/DataManager')).DataManager.getInstance();
    const failures: string[] = [];
    for (const setting of allSettings) {
      try {
        await dataManager.saveSetting(setting.settingKey, setting.settingValue, setting.settingType);
      } catch (error) {
        failures.push(`${setting.settingKey}: ${String(error)}`);
      }
    }
    await this.settingsManager.initialize();
    this.settingsManager.syncToAppStorage();
    if (failures.length > 0) {
      throw new Error(`设置表恢复失败 ${failures.length}/${allSettings.length}: ${failures.join('; ')}`);
    }
  }

  private getBackupBooleanValue(value: string | number | boolean | undefined): boolean | null {
    if (value === undefined) {
      return null;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    return value === 'true';
  }

  private async restoreHistory(history: HistoryBackupSection): Promise<void> {
    logger.info(TAG, 'Restoring history');
    
    try {
      if (history.browse && Array.isArray(history.browse)) {
        for (const item of history.browse as BrowseHistoryBackup[]) {
          if (item.contentType !== 'novel') {
            logger.debug(TAG, `Skip unsupported browse history contentType: ${item.contentType}`);
            continue;
          }
          
          const browseInput: BrowseHistoryInput = {
            sourceId: item.sourceId,
            bookUrl: item.contentId,
            bookName: item.title,
            author: '',
            coverUrl: item.coverUrl || '',
            sourceName: ''
          };
          await this.novelSettingsManager.addBrowseHistory(browseInput);
        }
      }
      
      if (history.search && Array.isArray(history.search)) {
        for (const item of history.search as SearchHistoryBackup[]) {
          const keyword = String(item.keyword || '').trim();
          if (!keyword) {
            continue;
          }
          await this.novelSettingsManager.addSearchHistory(keyword);
        }
      }
      
      logger.info(TAG, 'History restore completed');
    } catch (error) {
      logger.error(TAG, `Failed to restore history: ${error}`);
      throw new Error(`历史记录恢复失败: ${error}`);
    }
  }

  private async restoreUnifiedAnnotations(items: UnifiedAnnotationBackupItem[]): Promise<void> {
    if (!items || items.length <= 0) {
      logger.info(TAG, 'No unified annotations to restore');
      return;
    }
    await this.ensureUnifiedAnnotationTable();
    const insertSql = `
      INSERT OR REPLACE INTO unified_annotation (
        id, contentType, contentId, annotationType, title, textContent, quoteText,
        chapterId, chapterTitle, chapterIndex, pageIndex, pageProgress,
        startOffset, endOffset, anchorJson, styleJson, linkedAnnotationId,
        createTime, updateTime, isDeleted
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
    `;

    let successCount = 0;
    let failCount = 0;
    const failures: string[] = [];
    for (const rawItem of items) {
      const item = this.normalizeUnifiedAnnotationBackupItem(rawItem);
      if (item.id.length <= 0 || item.contentId.length <= 0) {
        continue;
      }
      try {
        await this.dbManager.executeSql(insertSql, [
          item.id,
          item.contentType,
          item.contentId,
          item.annotationType,
          item.title,
          item.textContent,
          item.quoteText,
          item.chapterId,
          item.chapterTitle,
          item.chapterIndex,
          item.pageIndex,
          item.pageProgress,
          item.startOffset,
          item.endOffset,
          item.anchorJson,
          item.styleJson,
          item.linkedAnnotationId,
          item.createTime,
          item.updateTime
        ]);
        successCount++;
      } catch (error) {
        failCount++;
        failures.push(`${item.id}: ${String(error)}`);
        logger.warn(TAG, `Failed to restore unified annotation: id=${item.id}, error=${error}`);
      }
    }
    logger.info(TAG, `Unified annotations restore completed: success=${successCount}, fail=${failCount}`);
    if (failures.length > 0) {
      throw new Error(`统一标注恢复失败 ${failCount}/${items.length}: ${failures.join('; ')}`);
    }
  }

  private normalizeUnifiedAnnotationBackupItem(item: UnifiedAnnotationBackupItem): UnifiedAnnotationBackupItem {
    const now = Date.now();
    return {
      id: String(item.id || ''),
      contentType: this.normalizeAnnotationContentTypeForBackup(String(item.contentType || 'novel')),
      contentId: String(item.contentId || ''),
      annotationType: this.normalizeAnnotationTypeForBackup(String(item.annotationType || 'bookmark')),
      title: String(item.title || ''),
      textContent: String(item.textContent || ''),
      quoteText: String(item.quoteText || ''),
      chapterId: String(item.chapterId || ''),
      chapterTitle: String(item.chapterTitle || ''),
      chapterIndex: Number(item.chapterIndex ?? -1),
      pageIndex: Number(item.pageIndex ?? -1),
      pageProgress: Number(item.pageProgress ?? -1),
      startOffset: Number(item.startOffset ?? -1),
      endOffset: Number(item.endOffset ?? -1),
      anchorJson: this.normalizeAnnotationAnchorJson(String(item.anchorJson || '')),
      styleJson: String(item.styleJson || ''),
      linkedAnnotationId: String(item.linkedAnnotationId || ''),
      createTime: Number(item.createTime ?? now),
      updateTime: Number(item.updateTime ?? now)
    };
  }

  private normalizeAnnotationContentTypeForBackup(contentType: string): 'manga' | 'novel' | 'ebook' {
    const normalized = contentType.trim().toLowerCase();
    if (normalized === 'manga') {
      return 'manga';
    }
    if (normalized === 'ebook') {
      return 'ebook';
    }
    return 'novel';
  }

  private normalizeAnnotationTypeForBackup(annotationType: string): string {
    const normalized = annotationType.trim().toLowerCase();
    if (
      normalized === 'highlight' ||
      normalized === '1' ||
      normalized === '划线' ||
      normalized === 'underline'
    ) {
      return 'highlight';
    }
    if (
      normalized === 'thought' ||
      normalized === '2' ||
      normalized === '想法' ||
      normalized === 'note'
    ) {
      return 'thought';
    }
    return 'bookmark';
  }

  private normalizeAnnotationAnchorJson(anchorJson: string): string {
    const trimmed = anchorJson.trim();
    if (trimmed.length <= 0) {
      return '{}';
    }
    const parsed = SafeUtils.parseOptional<UnifiedAnnotationAnchorJson>(trimmed);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
      return trimmed;
    }
    return '{}';
  }

  private async ensureUnifiedAnnotationTable(): Promise<void> {
    await this.dbManager.executeSql(CREATE_UNIFIED_ANNOTATION_TABLE_SQL);
    await this.dbManager.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_unified_annotation_content ON unified_annotation (contentType, contentId, createTime DESC)'
    );
    await this.dbManager.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_unified_annotation_type ON unified_annotation (annotationType, createTime DESC)'
    );
    await this.dbManager.executeSql(
      'CREATE INDEX IF NOT EXISTS idx_unified_annotation_linked ON unified_annotation (linkedAnnotationId)'
    );
  }

  private async saveBackupFile(fileName: string, data: BackupData): Promise<string> {
    try {
      const sandboxManager = SandboxManager.getInstance();
      const filesDir = sandboxManager.getDirectory('files');
      const backupDir = `${filesDir}/backups`;
      
      if (!await sandboxManager.exists(backupDir)) {
        await sandboxManager.createDirectory(backupDir);
      }
      
      const filePath = `${backupDir}/${fileName}`;
      const jsonStr = JSON.stringify(data, null, 2);
      
      await sandboxManager.writeFile(filePath, jsonStr);
      
      logger.info(TAG, `Backup file saved: ${filePath}`);
      return filePath;
    } catch (error) {
      logger.error(TAG, `Failed to save backup file: ${error}`);
      throw new Error(`Failed to save backup file: ${error}`);
    }
  }

  private async loadBackupFile(filePath: string): Promise<BackupData> {
    try {
      const sandboxManager = SandboxManager.getInstance();
      const content = await sandboxManager.readTextFile(filePath);
      return SafeUtils.parseObj(content) as BackupData;
    } catch (error) {
      logger.error(TAG, `Failed to load backup file: ${error}`);
      throw new Error(`Failed to load backup file: ${error}`);
    }
  }

  private validateBackupData(data: BackupData): void {
    if (!data.version) {
      throw new Error('Invalid backup file: missing version');
    }
    
    if (!data.manga || !data.novel || !data.ebook) {
      throw new Error('Invalid backup file: missing required data');
    }
    
    logger.info(TAG, `Backup version: ${data.version}, App version: ${data.appVersion}`);
  }

  private async getAppVersion(): Promise<string> {
    try {
      const versionName = await this.appInfoManager.getVersionName();
      const versionCode = await this.appInfoManager.getVersionCode();
      return `${versionName} (${versionCode})`;
    } catch (error) {
      logger.error(TAG, `Failed to get app version: ${error}`);
      return '0.0.5 (1005027)';
    }
  }

  private getDeviceInfo(): string {
    try {
      return `${deviceInfo.brand} ${deviceInfo.marketName}`;
    } catch {
      return 'Unknown Device';
    }
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hour = String(date.getHours()).padStart(2, '0');
    const minute = String(date.getMinutes()).padStart(2, '0');
    return `${year}${month}${day}_${hour}${minute}`;
  }
}

export function getBackupManager(): BackupManager {
  return BackupManager.getInstance();
}
