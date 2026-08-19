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
import { getNovelSettingsManager, NovelSettingsManager } from '../Novel/NovelSettingsManager';
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
  DEFAULT_BACKUP_OPTIONS,
  UnifiedAnnotationBackupItem
} from '../../Models/BackupModels';
import { NovelBook, NovelSourceInfo, NovelReadStatus } from '../../Models/NovelModels';
import { BrowseHistoryInput, BrowseHistoryItem } from '../Novel/NovelSettingsManager';
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
          privacy: await this.exportPrivacySettings()
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
      
      await this.restoreMangaLibrary(backupData.manga.library);
      await this.restoreMangaReadProgress(backupData.manga.readProgress);
      
      await this.restoreNovelLibrary(backupData.novel.library);
      await this.restoreNovelReadProgress(backupData.novel.readProgress);
      
      await this.restoreEBookLibrary(backupData.ebook.library);
      
      await this.restoreMangaSources(backupData.sources.manga);
      await this.restoreNovelSources(backupData.sources.novel);
      
      await this.restoreSettings(backupData.settings);
      await this.restoreHistory(backupData.history);
      if (backupData.annotations?.records) {
        await this.restoreUnifiedAnnotations(backupData.annotations.records);
      }
      
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
        logger.warn(TAG, `Failed to restore unified annotation: id=${item.id}, error=${error}`);
      }
    }
    logger.info(TAG, `Unified annotations restore completed: success=${successCount}, fail=${failCount}`);
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
    try {
      SafeUtils.parseObj(trimmed);
      return trimmed;
    } catch {
      return '{}';
    }
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
