/**
 * 备份管理器
 * 负责导出和导入所有应用数据
 */

import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { getNovelDataManager } from '../Novel/NovelDataManager';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelSettingsManager } from '../Novel/NovelSettingsManager';
import { SettingsManager } from './SettingsManager';
import { AppInfoManager } from './AppInfoManager';
import {
  BackupData,
  BackupMetadata,
  MangaBackupItem,
  NovelBackupItem,
  EBookBackupItem,
  MangaSourceBackup,
  NovelSourceBackup,
  MangaChapterBackup,
  MangaReadProgressBackup,
  NovelReadProgressBackup,
  ReaderSettingsBackup,
  GeneralSettingsBackup,
  PrivacySettingsBackup,
  BackupItemCounts,
  BrowseHistoryBackup,
  SearchHistoryBackup,
  SettingsBackupSection,
  HistoryBackupSection,
  DEFAULT_BACKUP_OPTIONS
} from '../../Models/BackupModels';
import { NovelBook, NovelSourceInfo, NovelReadStatus } from '../../Models/NovelModels';
import { BrowseHistoryInput, BrowseHistoryItem } from '../Novel/NovelSettingsManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DatabaseRecord } from '../Database/DatabaseTypes';

const TAG = 'BackupManager';
const BACKUP_VERSION = '1.0.0';

export class BackupManager {
  private static instance: BackupManager;
  private dbManager: DatabaseManager;
  private novelDataManager = getNovelDataManager();
  private novelSourceManager = getNovelSourceManager();
  private novelSettingsManager = getNovelSettingsManager();
  private settingsManager = SettingsManager.getInstance();
  private appInfoManager = AppInfoManager.getInstance();

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
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
          privacy: await this.exportPrivacySettings()
        },
        
        history: {
          browse: await this.exportBrowseHistory(),
          search: await this.exportSearchHistory()
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
      
      await this.restoreMangaLibrary(backupData.manga.library);
      await this.restoreMangaReadProgress(backupData.manga.readProgress);
      
      await this.restoreNovelLibrary(backupData.novel.library);
      await this.restoreNovelReadProgress(backupData.novel.readProgress);
      
      await this.restoreEBookLibrary(backupData.ebook.library);
      
      await this.restoreMangaSources(backupData.sources.manga);
      await this.restoreNovelSources(backupData.sources.novel);
      
      await this.restoreSettings(backupData.settings);
      await this.restoreHistory(backupData.history);
      
      logger.info(TAG, 'Backup restore completed');
    } catch (error) {
      logger.error(TAG, `Backup restore failed: ${error}`);
      throw new Error(`Backup restore failed: ${error}`);
    }
  }

  async getBackupMetadata(filePath: string): Promise<BackupMetadata> {
    try {
      const sandboxManager = SandboxManager.getInstance();
      const content = await sandboxManager.readTextFile(filePath);
      const data = JSON.parse(content) as BackupData;
      
      const itemCounts: BackupItemCounts = {
        manga: data.manga?.library?.length || 0,
        novel: data.novel?.library?.length || 0,
        ebook: data.ebook?.library?.length || 0,
        sources: (data.sources?.manga?.length || 0) + (data.sources?.novel?.length || 0)
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
          genre: JSON.parse(String(manga['genre'] || '[]')),
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
      const novels = await this.novelDataManager.getFavoriteBooks();
      const backupItems: NovelBackupItem[] = novels.map((novel: NovelBook): NovelBackupItem => ({
        id: novel.id,
        sourceId: novel.sourceId,
        sourceName: novel.sourceName,
        bookUrl: novel.bookUrl,
        name: novel.name,
        author: novel.author || '',
        kind: novel.kind || '',
        intro: novel.intro || '',
        coverUrl: novel.coverUrl || '',
        coverLocalPath: novel.coverLocalPath,
        tocUrl: novel.tocUrl || '',
        latestChapterTitle: novel.latestChapterTitle || '',
        wordCount: novel.wordCount || '',
        chapterCount: novel.chapterCount || 0,
        readStatus: novel.readStatus || 'unread',
        isFavorite: novel.isFavorite,
        isPrivate: novel.isPrivate,
        isNSFW: novel.isNSFW,
        groupName: novel.groupName,
        createTime: novel.createTime,
        updateDbTime: novel.updateDbTime,
        lastReadChapterId: novel.lastReadChapterId,
        lastReadChapterIndex: novel.lastReadChapterIndex,
        lastReadPosition: novel.lastReadPosition,
        lastReadTime: novel.lastReadTime,
        totalReadingTime: novel.totalReadingTime
      }));
      
      logger.info(TAG, `Exported novel library: ${backupItems.length} items`);
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
        backupItems.push({
          id: String(ebook['id']),
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
          totalWordCount: Number(ebook['totalWordCount'] || 0)
        });
      }
      
      logger.info(TAG, `Exported ebook library: ${backupItems.length} items`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export ebook library: ${error}`);
      return [];
    }
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
      const sources = await this.novelSourceManager.getAllSources();
      const backupItems: NovelSourceBackup[] = sources.map((source: NovelSourceInfo): NovelSourceBackup => ({
        id: source.url,
        name: source.name,
        sourceUrl: source.url,
        bookSourceGroup: source.group || '',
        bookSourceType: 0,
        enabled: source.enabled,
        enabledExplore: source.hasExplore,
        isNSFW: source.isNSFW,
        weight: source.weight,
        lastUpdateTime: source.lastUpdateTime
      }));
      
      logger.info(TAG, `Exported novel sources: ${backupItems.length} items`);
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
      const emptySettings: Record<string, string | number | boolean> = {};
      const mangaSettings: Record<string, string | number | boolean> = this.settingsManager.getJSON('manga_reader_settings', emptySettings) as Record<string, string | number | boolean>;
      const novelSettings: Record<string, string | number | boolean> = this.settingsManager.getJSON('novel_reader_settings', emptySettings) as Record<string, string | number | boolean>;
      return {
        manga: mangaSettings,
        novel: novelSettings
      };
    } catch (error) {
      logger.error(TAG, `Failed to export reader settings: ${error}`);
      const emptyRecord: Record<string, string | number | boolean> = {};
      return { manga: emptyRecord, novel: emptyRecord };
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
    return [];
  }

  private async restoreMangaLibrary(items: MangaBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring manga library: ${items.length} items`);
    
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
        logger.error(TAG, `Failed to restore manga: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Manga library restore completed');
  }

  private async restoreNovelLibrary(items: NovelBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring novel library: ${items.length} items`);
    
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
        logger.error(TAG, `Failed to restore novel: ${item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Novel library restore completed');
  }

  private async restoreEBookLibrary(items: EBookBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring ebook library: ${items.length} items`);
    
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
      } catch (error) {
        logger.error(TAG, `Failed to restore ebook: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Ebook library restore completed');
  }

  private async restoreMangaSources(items: MangaSourceBackup[]): Promise<void> {
    logger.info(TAG, `Restoring manga sources: ${items.length} items`);
    
    for (const item of items) {
      try {
        const sql = 'INSERT OR REPLACE INTO comic_source (id, name, baseUrl, lang, enabled, isNSFW, lastUsedTime) VALUES (?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.id, item.name, item.baseUrl, item.lang,
          item.isEnabled ? 1 : 0, item.isNSFW ? 1 : 0, item.lastUsedTime || 0
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore manga source: ${item.name}, ${error}`);
      }
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
    
    for (const item of items) {
      try {
        const sql = 'INSERT OR REPLACE INTO read_history (comicId, chapterId, pageIndex, totalPages, readTime) VALUES (?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.mangaId, item.chapterId, item.pageIndex,
          item.totalPages, item.lastReadTime
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore manga read progress: ${error}`);
      }
    }
    
    logger.info(TAG, 'Manga read progress restore completed');
  }

  private async restoreNovelReadProgress(items: NovelReadProgressBackup[]): Promise<void> {
    logger.info(TAG, `Restoring novel read progress: ${items.length} items`);
    
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
        logger.error(TAG, `Failed to restore novel read progress: ${error}`);
      }
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
      
      logger.info(TAG, 'Settings restore completed');
    } catch (error) {
      logger.error(TAG, `Failed to restore settings: ${error}`);
    }
  }

  private async restoreHistory(history: HistoryBackupSection): Promise<void> {
    logger.info(TAG, 'Restoring history');
    
    try {
      if (history.browse && Array.isArray(history.browse)) {
        for (const item of history.browse) {
          if (item.contentType === 'novel') {
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
      }
      
      logger.info(TAG, 'History restore completed');
    } catch (error) {
      logger.error(TAG, `Failed to restore history: ${error}`);
    }
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
      return JSON.parse(content) as BackupData;
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
