/**
 * 增强版备份管理器
 * 支持完整的数据备份、用户选择、tar打包
 * 
 * 文件路径: entry/src/main/ets/Framework/Managers/EnhancedBackupManager.ets
 */

import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { getNovelDataManager } from '../Novel/NovelDataManager';
import { getNovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelSettingsManager } from '../Novel/NovelSettingsManager';
import { SettingsManager } from './SettingsManager';
import { AppInfoManager } from './AppInfoManager';
import { getTarPackager } from '../Utils/TarPackager';
import {
  BackupData,
  BackupOptions,
  BackupMetadata,
  DEFAULT_BACKUP_OPTIONS,
  WebViewConfigBackup,
  DownloadTaskBackup,
  CacheInfoBackup,
  PluginBackup,
  FavoriteBackup,
  OnlineComicBackup,
  OnlineChapterBackup,
  OnlinePageBackup,
  OnlineReadHistoryBackup,
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
  BrowseHistoryBackup,
  SearchHistoryBackup,
  SettingsBackupSection,
  HistoryBackupSection,
  BackupItemCounts,
  OnlineDataBackupSection,
  CloudConfigBackupSection,
  ProxyConfigBackup
} from '../../Models/BackupModels';

import { NovelBook, NovelSourceInfo, NovelReadStatus } from '../../Models/NovelModels';
import { BrowseHistoryInput, BrowseHistoryItem } from '../Novel/NovelSettingsManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { DatabaseRecord } from '../Database/DatabaseTypes';

// WebDAV配置类型
interface WebDAVSettingsConfig {
  serverUrl: string;
  username: string;
  password: string;
  basePath: string;
  autoBackup: boolean;
  autoBackupInterval: 'manual' | 'daily' | 'weekly';
  keepBackupCount: number;
}

// WebDAV恢复配置类型
interface WebDAVSettingsForRestore {
  enabled: boolean;
  serverUrl: string;
  username: string;
  password: string;
  basePath: string;
  autoBackup: boolean;
  autoBackupInterval: 'manual' | 'daily' | 'weekly';
  keepBackupCount: number;
  lastSyncTime: number;
  connectionStatus: string;
  lastTestTime: number;
  lastTestMessage: string;
  needCreateDir: boolean;
}


const TAG = 'EnhancedBackupManager';
const BACKUP_VERSION = '2.0';
const BACKUP_EXTENSION = '.mxbackup';

/**
 * 恢复选项接口
 */
export interface RestoreOptions {
  restoreMangaLibrary: boolean;
  restoreNovelLibrary: boolean;
  restoreEBookLibrary: boolean;
  restoreSources: boolean;
  restoreReadProgress: boolean;
  restoreSettings: boolean;
  restoreHistory: boolean;
  restoreWebViewConfig: boolean;
  restoreDownloadTasks: boolean;
  restoreFavorites: boolean;
  restoreOnlineData: boolean;
  restoreMediaFiles: boolean;
  restoreCloudConfig: boolean;
  conflictStrategy: 'skip' | 'replace' | 'merge';
}

export class EnhancedBackupManager {
  private static instance: EnhancedBackupManager;
  private dbManager: DatabaseManager;
  private sandboxManager: SandboxManager;
  private novelDataManager = getNovelDataManager();
  private novelSourceManager = getNovelSourceManager();
  private novelSettingsManager = getNovelSettingsManager();
  private settingsManager = SettingsManager.getInstance();
  private appInfoManager = AppInfoManager.getInstance();
  private tarPackager = getTarPackager();

  private constructor() {
    this.dbManager = DatabaseManager.getInstance();
    this.sandboxManager = SandboxManager.getInstance();
  }

  static getInstance(): EnhancedBackupManager {
    if (!EnhancedBackupManager.instance) {
      EnhancedBackupManager.instance = new EnhancedBackupManager();
    }
    return EnhancedBackupManager.instance;
  }

  /**
   * 创建备份（支持用户选项）
   */
  async createBackup(options: BackupOptions = DEFAULT_BACKUP_OPTIONS): Promise<string> {
    try {
      logger.info(TAG, 'Starting backup creation with options');
      
      const timestamp = Date.now();
      const appVersion = await this.getAppVersion();
      
      // 创建临时工作目录
      const tempDir = await this.createTempBackupDir(timestamp);
      
      try {
        // 1. 导出 JSON 数据
        const backupData: BackupData = await this.exportBackupData(options);
        backupData.version = BACKUP_VERSION;
        backupData.appVersion = appVersion;
        backupData.timestamp = timestamp;
        backupData.deviceInfo = this.getDeviceInfo();
        
        const jsonPath = `${tempDir}/backup.json`;
        await this.saveJSON(jsonPath, backupData);
        
        // 2. 复制媒体文件
        await this.copyMediaFiles(tempDir, options, backupData);
        
        // 3. 打包成 tar 文件
        const backupFileName = `manxia_backup_${this.formatDate(timestamp)}${BACKUP_EXTENSION}`;
        const backupsDir = await this.getBackupsDirectory();
        const finalPath = `${backupsDir}/${backupFileName}`;
        
        await this.tarPackager.createTarArchive(tempDir, finalPath);
        
        // 4. 清理临时目录
        await this.cleanupTempDir(tempDir);
        
        logger.info(TAG, `Backup created successfully: ${finalPath}`);
        return finalPath;
        
      } catch (error) {
        // 清理临时目录
        await this.cleanupTempDir(tempDir);
        throw new Error(`Backup cleanup failed: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `Backup creation failed: ${error}`);
      throw new Error(`Backup creation failed: ${error}`);
    }
  }

  /**
   * 恢复备份（完整恢复）
   */
  async restoreBackup(filePath: string): Promise<void> {
    const defaultOptions: RestoreOptions = {
      restoreMangaLibrary: true,
      restoreNovelLibrary: true,
      restoreEBookLibrary: true,
      restoreSources: true,
      restoreReadProgress: true,
      restoreSettings: true,
      restoreHistory: true,
      restoreWebViewConfig: true,
      restoreDownloadTasks: true,
      restoreFavorites: true,
      restoreOnlineData: true,
      restoreMediaFiles: true,
      restoreCloudConfig: true,
      conflictStrategy: 'replace'
    };
    
    return this.restoreBackupWithOptions(filePath, defaultOptions);
  }

  /**
   * 恢复备份（支持选择性恢复）
   */
  async restoreBackupWithOptions(filePath: string, options: RestoreOptions): Promise<void> {
    try {
      logger.info(TAG, `Starting backup restore with options: ${filePath}`);
      
      // 创建临时解压目录
      const tempDir = await this.createTempRestoreDir();
      
      try {
        // 1. 解压 tar 文件
        await this.tarPackager.extractTarArchive(filePath, tempDir);
        
        // 2. 读取 JSON 数据
        const jsonPath = `${tempDir}/backup.json`;
        const backupData = await this.loadJSON(jsonPath);
        
        this.validateBackupData(backupData);
        
        // 3. 选择性恢复数据
        await this.restoreBackupDataWithOptions(backupData, options);
        
        // 4. 恢复媒体文件
        if (options.restoreMediaFiles) {
          await this.restoreMediaFiles(tempDir);
        }
        
        // 5. 清理临时目录
        await this.cleanupTempDir(tempDir);
        
        logger.info(TAG, 'Backup restore completed');
        
      } catch (error) {
        await this.cleanupTempDir(tempDir);
        throw new Error(`Backup restore cleanup failed: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `Backup restore failed: ${error}`);
      throw new Error(`Backup restore failed: ${error}`);
    }
  }

  /**
   * 获取备份元数据
   */
  async getBackupMetadata(filePath: string): Promise<BackupMetadata> {
    try {
      const tempDir = await this.createTempRestoreDir();
      
      try {
        await this.tarPackager.extractTarArchive(filePath, tempDir);
        
        const jsonPath = `${tempDir}/backup.json`;
        const backupData: BackupData = await this.loadJSON(jsonPath);
        
        const stat = fs.statSync(filePath);
        
        const metadata: BackupMetadata = {
          version: backupData.version,
          appVersion: backupData.appVersion,
          timestamp: backupData.timestamp,
          deviceInfo: backupData.deviceInfo,
          itemCounts: {
            manga: backupData.manga?.library?.length || 0,
            novel: backupData.novel?.library?.length || 0,
            ebook: backupData.ebook?.library?.length || 0,
            sources: (backupData.sources?.manga?.length || 0) + (backupData.sources?.novel?.length || 0)
          },
          options: DEFAULT_BACKUP_OPTIONS,
          fileSize: stat.size
        };
        
        await this.cleanupTempDir(tempDir);
        
        return metadata;
        
      } catch (error) {
        await this.cleanupTempDir(tempDir);
        throw new Error(`Metadata cleanup failed: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `Failed to read backup metadata: ${error}`);
      throw new Error(`Failed to read backup metadata: ${error}`);
    }
  }

  /**
   * 导出备份数据（根据选项）
   */
  private async exportBackupData(options: BackupOptions): Promise<BackupData> {
    const appInfoManager = AppInfoManager.getInstance();
    const versionName = await appInfoManager.getVersionName();
    const versionCode = await appInfoManager.getVersionCode();
    const appVersion = `${versionName}(${versionCode})`;
    
    const readerSettings: ReaderSettingsBackup = { manga: {}, novel: {} };
    
    // 导出代理配置
    let proxyConfig: ProxyConfigBackup | undefined = undefined;
    try {
      const proxySettingsStr = this.settingsManager.getString('network_proxy_settings', '');
      if (proxySettingsStr) {
        const proxySettings = JSON.parse(proxySettingsStr) as ProxyConfigBackup;
        proxyConfig = {
          enabled: proxySettings.enabled || false,
          httpEnabled: proxySettings.httpEnabled !== undefined ? proxySettings.httpEnabled : true,
          httpHost: proxySettings.httpHost || '',
          httpPort: proxySettings.httpPort || 7890,
          httpsEnabled: proxySettings.httpsEnabled || false,
          httpsHost: proxySettings.httpsHost || '',
          httpsPort: proxySettings.httpsPort || 7890
        };
        logger.info(TAG, `导出代理配置: enabled=${proxyConfig.enabled}`);
      }
    } catch (error) {
      logger.warn(TAG, `导出代理配置失败: ${error}`);
    }
    
    const generalSettings: GeneralSettingsBackup = {
      theme: this.settingsManager.getString('app_theme', 'auto'),
      language: this.settingsManager.getString('app_language', 'zh-CN'),
      proxyConfig: proxyConfig
    };
    const privacySettings: PrivacySettingsBackup = {
      sfwMode: this.settingsManager.getBoolean('sfw_mode_enabled', false),
      privateLibraryEnabled: this.settingsManager.getBoolean('private_library_enabled', false)
    };
    
    const data: BackupData = {
      version: BACKUP_VERSION,
      appVersion: appVersion,
      timestamp: Date.now(),
      deviceInfo: `${deviceInfo.brand} ${deviceInfo.marketName}`,
      
      manga: {
        library: options.includeMangaLibrary ? await this.exportMangaLibrary() : [],
        readProgress: options.includeReadProgress ? await this.exportMangaReadProgress() : [],
        categories: []
      },
      
      novel: {
        library: options.includeNovelLibrary ? await this.exportNovelLibrary() : [],
        readProgress: options.includeReadProgress ? await this.exportNovelReadProgress() : [],
        categories: []
      },
      
      ebook: {
        library: options.includeEBookLibrary ? await this.exportEBookLibrary() : []
      },
      
      sources: {
        manga: options.includeSources ? await this.exportMangaSources() : [],
        novel: options.includeSources ? await this.exportNovelSources() : []
      },
      
      settings: {
        reader: readerSettings,
        general: generalSettings,
        privacy: privacySettings
      },
      
      history: {
        browse: options.includeHistory ? await this.exportBrowseHistory() : [],
        search: options.includeHistory ? await this.exportSearchHistory() : []
      },
      
      cloudConfig: options.includeCloudConfig ? await this.exportCloudConfig() : undefined
    };
    
    return data;
  }
  
  /**
   * 导出云存储配置
   */
  private async exportCloudConfig(): Promise<CloudConfigBackupSection> {
    try {
      const webdavConfig = this.settingsManager.getString('webdav_settings', '');
      if (webdavConfig) {
        const config = JSON.parse(webdavConfig) as WebDAVSettingsConfig;
        const result: CloudConfigBackupSection = {
          webdav: {
            serverUrl: config.serverUrl || '',
            username: config.username || '',
            password: config.password || '',
            basePath: config.basePath || '/manxia',
            autoBackup: config.autoBackup || false,
            autoBackupInterval: config.autoBackupInterval || 'manual',
            keepBackupCount: config.keepBackupCount || 5
          }
        };
        return result;
      }
    } catch (error) {
      logger.warn(TAG, `Failed to export cloud config: ${error}`);
    }
    const emptyResult: CloudConfigBackupSection = {};
    return emptyResult;
  }

  /**
   * 恢复备份数据（完整恢复）
   */
  private async restoreBackupData(backupData: BackupData): Promise<void> {
    const defaultOptions: RestoreOptions = {
      restoreMangaLibrary: true,
      restoreNovelLibrary: true,
      restoreEBookLibrary: true,
      restoreSources: true,
      restoreReadProgress: true,
      restoreSettings: true,
      restoreHistory: true,
      restoreWebViewConfig: true,
      restoreDownloadTasks: true,
      restoreFavorites: true,
      restoreOnlineData: true,
      restoreMediaFiles: true,
      restoreCloudConfig: true,
      conflictStrategy: 'replace'
    };
    
    return this.restoreBackupDataWithOptions(backupData, defaultOptions);
  }

  /**
   * 恢复备份数据（支持选择性恢复和冲突处理）
   */
  private async restoreBackupDataWithOptions(backupData: BackupData, options: RestoreOptions): Promise<void> {
    logger.info(TAG, `Starting selective data restoration with strategy: ${options.conflictStrategy}`);
    
    if (options.restoreMangaLibrary && backupData.manga?.library) {
      await this.restoreMangaLibraryWithStrategy(backupData.manga.library, options.conflictStrategy);
    }
    
    if (options.restoreNovelLibrary && backupData.novel?.library) {
      await this.restoreNovelLibraryWithStrategy(backupData.novel.library, options.conflictStrategy);
    }
    
    if (options.restoreEBookLibrary && backupData.ebook?.library) {
      await this.restoreEBookLibraryWithStrategy(backupData.ebook.library, options.conflictStrategy);
    }
    
    if (options.restoreSources && backupData.sources?.manga) {
      await this.restoreMangaSourcesWithStrategy(backupData.sources.manga, options.conflictStrategy);
    }
    
    if (options.restoreSources && backupData.sources?.novel) {
      await this.restoreNovelSourcesWithStrategy(backupData.sources.novel, options.conflictStrategy);
    }
    
    if (options.restoreReadProgress && backupData.manga?.readProgress) {
      await this.restoreMangaReadProgress(backupData.manga.readProgress);
    }
    
    if (options.restoreReadProgress && backupData.novel?.readProgress) {
      await this.restoreNovelReadProgress(backupData.novel.readProgress);
    }
    
    if (options.restoreSettings && backupData.settings) {
      await this.restoreSettings(backupData.settings);
    }
    
    if (options.restoreHistory && backupData.history) {
      await this.restoreHistory(backupData.history);
    }
    
    if (options.restoreWebViewConfig && backupData.webview) {
      await this.restoreWebViewConfigs(backupData.webview.configs);
    }
    
    if (options.restoreDownloadTasks && backupData.downloads) {
      await this.restoreDownloadTasks(backupData.downloads.tasks);
    }
    
    if (options.restoreFavorites && backupData.favorites) {
      await this.restoreFavorites(backupData.favorites.favorites);
    }
    
    if (options.restoreOnlineData && backupData.onlineData) {
      await this.restoreOnlineData(backupData.onlineData);
    }
    
    if (options.restoreCloudConfig && backupData.cloudConfig) {
      await this.restoreCloudConfig(backupData.cloudConfig);
    }
    
    logger.info(TAG, 'Data restoration completed');
  }
  
  /**
   * 恢复云存储配置
   */
  private async restoreCloudConfig(cloudConfig: CloudConfigBackupSection): Promise<void> {
    try {
      if (cloudConfig.webdav) {
        const webdavSettings: WebDAVSettingsForRestore = {
          enabled: false,
          serverUrl: cloudConfig.webdav.serverUrl,
          username: cloudConfig.webdav.username,
          password: cloudConfig.webdav.password,
          basePath: cloudConfig.webdav.basePath,
          autoBackup: cloudConfig.webdav.autoBackup,
          autoBackupInterval: cloudConfig.webdav.autoBackupInterval,
          keepBackupCount: cloudConfig.webdav.keepBackupCount,
          lastSyncTime: 0,
          connectionStatus: 'untested',
          lastTestTime: 0,
          lastTestMessage: '',
          needCreateDir: false
        };
        
        this.settingsManager.setString('webdav_settings', JSON.stringify(webdavSettings));
        logger.info(TAG, 'Cloud config restored successfully');
      }
    } catch (error) {
      logger.error(TAG, `Failed to restore cloud config: ${error}`);
    }
  }

  /**
   * 复制媒体文件到备份目录
   */
  private async copyMediaFiles(tempDir: string, options: BackupOptions, backupData: BackupData): Promise<void> {
    try {
      if (options.includeCoverImages) {
        logger.info(TAG, 'Copying media files: covers');
        const coversDir = `${tempDir}/covers`;
        if (!fs.accessSync(coversDir)) {
          fs.mkdirSync(coversDir, true);
        }
        await this.copyCoverImages(coversDir, backupData.manga.library);
        logger.info(TAG, 'Media files copied: covers');
      }
      
      if (options.includeChapterImages) {
        logger.info(TAG, 'Copying media files: chapters');
        const chaptersDir = `${tempDir}/chapters`;
        if (!fs.accessSync(chaptersDir)) {
          fs.mkdirSync(chaptersDir, true);
        }
        await this.copyChapterImages(chaptersDir);
        logger.info(TAG, 'Media files copied: chapters');
      }
      
      if (options.includeEBookFiles) {
        logger.info(TAG, 'Copying media files: ebooks');
        const ebooksDir = `${tempDir}/ebooks`;
        if (!fs.accessSync(ebooksDir)) {
          fs.mkdirSync(ebooksDir, true);
        }
        await this.copyEBookFiles(ebooksDir);
        logger.info(TAG, 'Media files copied: ebooks');
      }
    } catch (error) {
      logger.error(TAG, `Failed to copy media files: ${error}`);
    }
  }

  /**
   * 复制封面图片
   */
  private async copyCoverImages(targetDir: string, mangaList: MangaBackupItem[]): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    let totalDirs = 0;
    let totalFiles = 0;
    
    try {
      // 复制漫画相关文件（包括封面和章节图片）
      const comicsDir = this.sandboxManager.getDirectory('comics');
      logger.debug(TAG, `Comics directory: ${comicsDir}, exists: ${fs.accessSync(comicsDir)}`);
      
      if (fs.accessSync(comicsDir)) {
        const mangaTarget = `${targetDir}/manga`;
        if (!fs.accessSync(mangaTarget)) {
          fs.mkdirSync(mangaTarget, true);
        }
        
        // 方法1：基于数据库记录的漫画列表
        logger.debug(TAG, `Processing ${mangaList.length} manga from database`);
        for (const manga of mangaList) {
          try {
            // 尝试从coverLocalPath提取路径
            let sourceName = '';
            let comicName = '';
            
            if (manga.coverLocalPath) {
              logger.debug(TAG, `Manga: ${manga.title}, coverPath: ${manga.coverLocalPath}`);
              const relativePath = manga.coverLocalPath.replace(`${comicsDir}/`, '').replace(`${comicsDir}\\`, '');
              const parts = relativePath.split(/[\/\\]/);
              
              if (parts.length >= 2) {
                sourceName = parts[0];
                comicName = parts[1];
              }
            }
            
            // 如果无法从coverLocalPath提取，尝试使用sourceId和title
            if (!sourceName || !comicName) {
              sourceName = manga.sourceId || manga.sourceName || 'unknown';
              comicName = manga.title.replace(/[\\/:*?"<>|]/g, '_');
              logger.debug(TAG, `Using fallback path: ${sourceName}/${comicName}`);
            }
            
            const mangaDir = `${comicsDir}/${sourceName}/${comicName}`;
            logger.debug(TAG, `Checking manga directory: ${mangaDir}, exists: ${fs.accessSync(mangaDir)}`);
            
            if (fs.accessSync(mangaDir)) {
              const targetMangaDir = `${mangaTarget}/${sourceName}/${comicName}`;
              if (!fs.accessSync(targetMangaDir)) {
                fs.mkdirSync(targetMangaDir, true);
              }
              const count = await this.copyDirectoryRecursive(mangaDir, targetMangaDir);
              totalFiles += count;
              totalDirs++;
              logger.info(TAG, `Copied manga: ${comicName} (${count} files)`);
            } else {
              logger.warn(TAG, `Manga directory not found: ${mangaDir}`);
            }
          } catch (error) {
            logger.error(TAG, `Failed to copy manga ${manga.title}: ${error}`);
          }
        }
        
        // 方法2：直接遍历comics目录，备份所有源的所有漫画（兜底策略）
        logger.debug(TAG, `Scanning comics directory for additional files`);
        try {
          const sourceEntries = fs.listFileSync(comicsDir);
          logger.debug(TAG, `Found ${sourceEntries.length} source directories`);
          
          for (const sourceEntry of sourceEntries) {
            const sourcePath = `${comicsDir}/${sourceEntry}`;
            const stat = fs.statSync(sourcePath);
            
            if (stat.isDirectory()) {
              const comicEntries = fs.listFileSync(sourcePath);
              logger.debug(TAG, `Source ${sourceEntry}: ${comicEntries.length} comics`);
              
              for (const comicEntry of comicEntries) {
                const comicPath = `${sourcePath}/${comicEntry}`;
                const comicStat = fs.statSync(comicPath);
                
                if (comicStat.isDirectory()) {
                  const targetPath = `${mangaTarget}/${sourceEntry}/${comicEntry}`;
                  
                  // 检查是否已经复制过
                  if (!fs.accessSync(targetPath)) {
                    if (!fs.accessSync(`${mangaTarget}/${sourceEntry}`)) {
                      fs.mkdirSync(`${mangaTarget}/${sourceEntry}`, true);
                    }
                    const count = await this.copyDirectoryRecursive(comicPath, targetPath);
                    if (count > 0) {
                      totalFiles += count;
                      totalDirs++;
                      logger.info(TAG, `Copied additional manga: ${comicEntry} (${count} files)`);
                    }
                  }
                }
              }
            }
          }
        } catch (error) {
          logger.error(TAG, `Failed to scan comics directory: ${error}`);
        }
        
        logger.info(TAG, `Copied ${totalFiles} files from ${totalDirs} manga directories`);
      } else {
        logger.warn(TAG, `Comics directory not found: ${comicsDir}`);
      }
      
      // 复制小说封面
      const novelCoversDir = `${filesDir}/novel_covers`;
      logger.debug(TAG, `Novel covers directory: ${novelCoversDir}, exists: ${fs.accessSync(novelCoversDir)}`);
      if (fs.accessSync(novelCoversDir)) {
        const novelTarget = `${targetDir}/novel`;
        if (!fs.accessSync(novelTarget)) {
          fs.mkdirSync(novelTarget, true);
        }
        const count = await this.copyDirectoryRecursive(novelCoversDir, novelTarget);
        totalFiles += count;
        if (count > 0) totalDirs++;
        logger.info(TAG, `Copied ${count} novel cover files`);
      } else {
        logger.warn(TAG, `Novel covers directory not found: ${novelCoversDir}`);
      }
      
      // 复制电子书封面
      const ebookCoversDir = `${filesDir}/ebook_covers`;
      logger.debug(TAG, `Ebook covers directory: ${ebookCoversDir}, exists: ${fs.accessSync(ebookCoversDir)}`);
      if (fs.accessSync(ebookCoversDir)) {
        const ebookTarget = `${targetDir}/ebook`;
        if (!fs.accessSync(ebookTarget)) {
          fs.mkdirSync(ebookTarget, true);
        }
        const count = await this.copyDirectoryRecursive(ebookCoversDir, ebookTarget);
        totalFiles += count;
        if (count > 0) totalDirs++;
        logger.info(TAG, `Copied ${count} ebook cover files`);
      } else {
        logger.warn(TAG, `Ebook covers directory not found: ${ebookCoversDir}`);
      }
      
      logger.info(TAG, `Copied ${totalFiles} files from ${totalDirs} cover directories`);
    } catch (error) {
      logger.error(TAG, `Failed to copy cover images: ${error}`);
    }
  }

  /**
   * 复制章节图片（缓存）
   */
  private async copyChapterImages(targetDir: string): Promise<void> {
    const cacheDir = this.sandboxManager.getDirectory('cache');
    let totalFiles = 0;
    
    try {
      // 复制漫画章节图片缓存
      const mangaCacheDir = `${cacheDir}/manga_images`;
      if (fs.accessSync(mangaCacheDir)) {
        const mangaTarget = `${targetDir}/manga`;
        if (!fs.accessSync(mangaTarget)) {
          fs.mkdirSync(mangaTarget, true);
        }
        const count = await this.copyDirectoryRecursive(mangaCacheDir, mangaTarget);
        totalFiles += count;
        logger.info(TAG, `Copied ${count} manga chapter images`);
      } else {
        logger.warn(TAG, `Manga cache directory not found: ${mangaCacheDir}`);
      }
      
      // 复制其他图片缓存
      const imagesDir = `${cacheDir}/images`;
      if (fs.accessSync(imagesDir)) {
        const count = await this.copyDirectoryRecursive(imagesDir, targetDir);
        totalFiles += count;
        logger.info(TAG, `Copied ${count} cached images`);
      } else {
        logger.warn(TAG, `Images cache directory not found: ${imagesDir}`);
      }
      
      logger.info(TAG, `Total chapter images copied: ${totalFiles}`);
    } catch (error) {
      logger.error(TAG, `Failed to copy chapter images: ${error}`);
    }
  }

  /**
   * 复制电子书文件
   */
  private async copyEBookFiles(targetDir: string): Promise<void> {
    const ebooksDir = `${this.sandboxManager.getDirectory('files')}/ebooks`;
    if (!fs.accessSync(ebooksDir)) {
      logger.warn(TAG, `Ebooks directory not found: ${ebooksDir}`);
      return;
    }
    
    try {
      const count = await this.copyDirectoryRecursive(ebooksDir, targetDir);
      logger.info(TAG, `Copied ${count} ebook files`);
    } catch (error) {
      logger.error(TAG, `Failed to copy ebook files: ${error}`);
    }
  }

  /**
   * 递归复制目录
   * @returns 复制的文件数量
   */
  private async copyDirectoryRecursive(sourceDir: string, targetDir: string): Promise<number> {
    if (!fs.accessSync(targetDir)) {
      fs.mkdirSync(targetDir, true);
    }
    
    let fileCount = 0;
    const entries = fs.listFileSync(sourceDir);
    
    for (const entry of entries) {
      const sourcePath = `${sourceDir}/${entry}`;
      const targetPath = `${targetDir}/${entry}`;
      
      const stat = fs.statSync(sourcePath);
      if (stat.isDirectory()) {
        const subCount = await this.copyDirectoryRecursive(sourcePath, targetPath);
        fileCount += subCount;
      } else {
        fs.copyFileSync(sourcePath, targetPath);
        fileCount++;
      }
    }
    
    return fileCount;
  }

  /**
   * 恢复媒体文件
   */
  private async restoreMediaFiles(tempDir: string): Promise<void> {
    logger.info(TAG, 'Restoring media files...');
    
    try {
      const coversDir = `${tempDir}/covers`;
      if (fs.accessSync(coversDir)) {
        await this.restoreCoverImages(coversDir);
      }
      
      const chaptersDir = `${tempDir}/chapters`;
      if (fs.accessSync(chaptersDir)) {
        await this.restoreChapterImages(chaptersDir);
      }
      
      const ebooksDir = `${tempDir}/ebooks`;
      if (fs.accessSync(ebooksDir)) {
        await this.restoreEBookFiles(ebooksDir);
      }
      
      logger.info(TAG, 'Media files restored successfully');
    } catch (error) {
      logger.error(TAG, `Failed to restore media files: ${error}`);
    }
  }

  /**
   * 恢复封面图片
   */
  private async restoreCoverImages(sourceDir: string): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    
    try {
      // 恢复漫画封面（到comics目录）
      const mangaSource = `${sourceDir}/manga`;
      if (fs.accessSync(mangaSource)) {
        const mangaTarget = this.sandboxManager.getDirectory('comics');
        if (!fs.accessSync(mangaTarget)) {
          fs.mkdirSync(mangaTarget, true);
        }
        await this.copyDirectoryRecursive(mangaSource, mangaTarget);
        logger.info(TAG, 'Restored manga covers');
      }
      
      // 恢复小说封面
      const novelSource = `${sourceDir}/novel`;
      if (fs.accessSync(novelSource)) {
        const novelTarget = `${filesDir}/novel_covers`;
        if (!fs.accessSync(novelTarget)) {
          fs.mkdirSync(novelTarget, true);
        }
        await this.copyDirectoryRecursive(novelSource, novelTarget);
        logger.info(TAG, 'Restored novel covers');
      }
      
      // 恢复电子书封面
      const ebookSource = `${sourceDir}/ebook`;
      if (fs.accessSync(ebookSource)) {
        const ebookTarget = `${filesDir}/ebook_covers`;
        if (!fs.accessSync(ebookTarget)) {
          fs.mkdirSync(ebookTarget, true);
        }
        await this.copyDirectoryRecursive(ebookSource, ebookTarget);
        logger.info(TAG, 'Restored ebook covers');
      }
    } catch (error) {
      logger.error(TAG, `Failed to restore cover images: ${error}`);
    }
  }

  /**
   * 恢复章节图片
   */
  private async restoreChapterImages(sourceDir: string): Promise<void> {
    const cacheDir = this.sandboxManager.getDirectory('cache');
    
    try {
      // 恢复漫画章节图片
      const mangaSource = `${sourceDir}/manga`;
      if (fs.accessSync(mangaSource)) {
        const mangaTarget = `${cacheDir}/manga_images`;
        if (!fs.accessSync(mangaTarget)) {
          fs.mkdirSync(mangaTarget, true);
        }
        await this.copyDirectoryRecursive(mangaSource, mangaTarget);
        logger.info(TAG, 'Restored manga chapter images');
      }
      
      // 恢复其他图片缓存
      const imagesSource = `${sourceDir}/images`;
      if (fs.accessSync(imagesSource)) {
        const imagesTarget = `${cacheDir}/images`;
        if (!fs.accessSync(imagesTarget)) {
          fs.mkdirSync(imagesTarget, true);
        }
        await this.copyDirectoryRecursive(imagesSource, imagesTarget);
        logger.info(TAG, 'Restored cached images');
      }
    } catch (error) {
      logger.error(TAG, `Failed to restore chapter images: ${error}`);
    }
  }

  /**
   * 恢复电子书文件
   */
  private async restoreEBookFiles(sourceDir: string): Promise<void> {
    const targetDir = `${this.sandboxManager.getDirectory('files')}/ebooks`;
    if (!fs.accessSync(targetDir)) {
      fs.mkdirSync(targetDir, true);
    }
    
    await this.copyDirectoryRecursive(sourceDir, targetDir);
    logger.info(TAG, 'Ebook files restored');
  }

  /**
   * 恢复漫画库
   */
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

  /**
   * 恢复小说库
   */
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

  /**
   * 恢复电子书库
   */
  private async restoreEBookLibrary(items: EBookBackupItem[]): Promise<void> {
    logger.info(TAG, `Restoring ebook library: ${items.length} items`);
    
    for (const item of items) {
      // 跳过内置电子书
      if (item.title === '漫匣使用手册') {
        logger.info(TAG, 'Skipping builtin ebook: 漫匣使用手册');
        continue;
      }
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

  /**
   * 导出漫画库
   */
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

  /**
   * 导出小说库
   */
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

  /**
   * 导出电子书库
   */
  private async exportEBookLibrary(): Promise<EBookBackupItem[]> {
    try {
      const sql = 'SELECT * FROM ebook_info WHERE title != ?';
      const results = await this.dbManager.querySql(sql, ['漫匣使用手册']);
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

  /**
   * 导出漫画书源
   */
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

  /**
   * 导出小说书源
   */
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

  /**
   * 导出漫画阅读进度
   */
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

  /**
   * 导出小说阅读进度
   */
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

  /**
   * 导出浏览历史
   */
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

  /**
   * 导出搜索历史
   */
  private async exportSearchHistory(): Promise<SearchHistoryBackup[]> {
    return [];
  }

  /**
   * 恢复漫画书源
   */
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

  /**
   * 恢复小说书源
   */
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

  /**
   * 恢复漫画阅读进度
   */
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

  /**
   * 恢复小说阅读进度
   */
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

  /**
   * 恢复设置
   */
  private async restoreSettings(settings: SettingsBackupSection): Promise<void> {
    logger.info(TAG, 'Restoring settings');
    
    try {
      if (settings.reader) {
        if (settings.reader.manga) {
          await this.settingsManager.setJSON('manga_reader_settings', settings.reader.manga);
        }
        if (settings.reader.novel) {
          await this.settingsManager.setJSON('novel_reader_settings', settings.reader.novel);
        }
      }
      
      if (settings.general) {
        if (settings.general.theme) {
          await this.settingsManager.setString('app_theme', settings.general.theme);
        }
        if (settings.general.language) {
          await this.settingsManager.setString('app_language', settings.general.language);
        }
        // 恢复代理配置
        if (settings.general.proxyConfig) {
          const proxyConfig = settings.general.proxyConfig;
          const proxySettingsStr = JSON.stringify({
            enabled: proxyConfig.enabled,
            httpEnabled: proxyConfig.httpEnabled,
            httpHost: proxyConfig.httpHost,
            httpPort: proxyConfig.httpPort,
            httpsEnabled: proxyConfig.httpsEnabled,
            httpsHost: proxyConfig.httpsHost,
            httpsPort: proxyConfig.httpsPort
          });
          await this.settingsManager.setString('network_proxy_settings', proxySettingsStr);
          logger.info(TAG, `代理配置已恢复: enabled=${proxyConfig.enabled}`);
        }
      }
      
      if (settings.privacy) {
        if (settings.privacy.sfwMode !== undefined) {
          await this.settingsManager.setBoolean('sfw_mode_enabled', settings.privacy.sfwMode);
        }
        if (settings.privacy.privateLibraryEnabled !== undefined) {
          await this.settingsManager.setBoolean('private_library_enabled', settings.privacy.privateLibraryEnabled);
        }
      }
      
      logger.info(TAG, 'Settings restore completed');
    } catch (error) {
      logger.error(TAG, `Failed to restore settings: ${error}`);
    }
  }

  /**
   * 恢复历史记录
   */
  private async restoreHistory(history: HistoryBackupSection): Promise<void> {
    logger.info(TAG, 'Restoring history');
    
    try {
      if (history.browse && Array.isArray(history.browse)) {
        for (const item of history.browse as BrowseHistoryBackup[]) {
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

  /**
   * 恢复 WebView 配置
   */
  private async restoreWebViewConfigs(configs: WebViewConfigBackup[]): Promise<void> {
    logger.info(TAG, `Restoring WebView configs: ${configs.length} items`);
    
    for (const config of configs) {
      try {
        const sql = 'INSERT OR REPLACE INTO webview_source_config (id, sourceId, userAgent, enableJavaScript, enableCookies, customHeaders, refererPolicy, imageLoadingStrategy, timeout, retryCount, lastUpdateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          config.id, config.sourceId, config.userAgent,
          config.enableJavaScript ? 1 : 0, config.enableCookies ? 1 : 0,
          config.customHeaders, config.refererPolicy, config.imageLoadingStrategy,
          config.timeout, config.retryCount, config.lastUpdateTime
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore WebView config: ${error}`);
      }
    }
    
    logger.info(TAG, 'WebView configs restore completed');
  }

  /**
   * 恢复下载任务
   */
  private async restoreDownloadTasks(tasks: DownloadTaskBackup[]): Promise<void> {
    logger.info(TAG, `Restoring download tasks: ${tasks.length} items`);
    
    for (const task of tasks) {
      try {
        const sql = 'INSERT OR REPLACE INTO download_task (id, comicId, chapterId, taskType, status, progress, totalSize, downloadedSize, createTime, updateTime, errorMessage) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          task.id, task.comicId, task.chapterId || null,
          task.taskType, task.status, task.progress,
          task.totalSize, task.downloadedSize, task.createTime,
          task.updateTime, task.errorMessage || null
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore download task: ${error}`);
      }
    }
    
    logger.info(TAG, 'Download tasks restore completed');
  }

  /**
   * 恢复收藏标签
   */
  private async restoreFavorites(favorites: FavoriteBackup[]): Promise<void> {
    logger.info(TAG, `Restoring favorites: ${favorites.length} items`);
    
    for (const fav of favorites) {
      try {
        const sql = 'INSERT OR REPLACE INTO favorite (id, comicId, userId, tags, note, rating, addTime, updateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          fav.id, fav.comicId, fav.userId,
          JSON.stringify(fav.tags), fav.note, fav.rating,
          fav.addTime, fav.updateTime
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore favorite: ${error}`);
      }
    }
    
    logger.info(TAG, 'Favorites restore completed');
  }

  /**
   * 恢复在线数据
   */
  private async restoreOnlineData(data: OnlineDataBackupSection): Promise<void> {
    logger.info(TAG, `Restoring online data: ${data.comics.length} comics`);
    
    for (const comic of data.comics as OnlineComicBackup[]) {
      try {
        const sqlComic = 'INSERT OR REPLACE INTO online_comic_info (id, sourceId, externalId, title, author, coverUrl, description, status, lastUpdateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sqlComic, [
          comic.id, comic.sourceId, comic.externalId, comic.title,
          comic.author, comic.coverUrl, comic.description, comic.status,
          comic.lastUpdateTime
        ]);
        
        for (const chapter of comic.chapters as OnlineChapterBackup[]) {
          const sqlChapter = 'INSERT OR REPLACE INTO online_chapter (id, comicId, externalId, title, chapterNumber, publishTime) VALUES (?, ?, ?, ?, ?, ?)';
          
          await this.dbManager.executeSql(sqlChapter, [
            chapter.id, chapter.comicId, chapter.externalId,
            chapter.title, chapter.chapterNumber, chapter.publishTime
          ]);
          
          for (const page of chapter.pages as OnlinePageBackup[]) {
            const sqlPage = 'INSERT OR REPLACE INTO online_page (id, chapterId, pageNumber, imageUrl, width, height) VALUES (?, ?, ?, ?, ?, ?)';
            
            await this.dbManager.executeSql(sqlPage, [
              page.id, page.chapterId, page.pageNumber,
              page.imageUrl, page.width, page.height
            ]);
          }
        }
      } catch (error) {
        logger.error(TAG, `Failed to restore online comic: ${comic.title}, ${error}`);
      }
    }
    
    for (const history of data.readHistory as OnlineReadHistoryBackup[]) {
      try {
        const sql = 'INSERT OR REPLACE INTO online_read_history (id, comicId, chapterId, pageIndex, readTime) VALUES (?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          history.id, history.comicId, history.chapterId,
          history.pageIndex, history.readTime
        ]);
      } catch (error) {
        logger.error(TAG, `Failed to restore online read history: ${error}`);
      }
    }
    
    logger.info(TAG, 'Online data restore completed');
  }

  /**
   * 工具方法
   */
  private async createTempBackupDir(timestamp: number): Promise<string> {
    const tempDir = `${this.sandboxManager.getDirectory('cache')}/backup_temp_${timestamp}`;
    if (!fs.accessSync(tempDir)) {
      fs.mkdirSync(tempDir, true);
    }
    return tempDir;
  }

  private async createTempRestoreDir(): Promise<string> {
    const tempDir = `${this.sandboxManager.getDirectory('cache')}/restore_temp_${Date.now()}`;
    if (!fs.accessSync(tempDir)) {
      fs.mkdirSync(tempDir, true);
    }
    return tempDir;
  }

  private async cleanupTempDir(dir: string): Promise<void> {
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
      }
    } catch (error) {
      logger.warn(TAG, `Failed to cleanup temp dir: ${error}`);
    }
  }

  private async getBackupsDirectory(): Promise<string> {
    const backupsDir = `${this.sandboxManager.getDirectory('files')}/backups`;
    if (!fs.accessSync(backupsDir)) {
      fs.mkdirSync(backupsDir, true);
    }
    return backupsDir;
  }

  private async saveJSON(path: string, data: BackupData): Promise<void> {
    const jsonStr = JSON.stringify(data, null, 2);
    await this.sandboxManager.writeFile(path, jsonStr);
  }

  private async loadJSON(path: string): Promise<BackupData> {
    const content = await this.sandboxManager.readTextFile(path);
    return JSON.parse(content) as BackupData;
  }

  private validateBackupData(data: BackupData): void {
    if (!data.version) {
      throw new Error('Invalid backup file: missing version');
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

  /**
   * 带冲突处理策略的恢复方法
   */
  private async restoreMangaLibraryWithStrategy(items: MangaBackupItem[], strategy: 'skip' | 'replace' | 'merge'): Promise<void> {
    logger.info(TAG, `Restoring manga library with strategy: ${strategy}, ${items.length} items`);
    
    for (const item of items) {
      try {
        // 检查是否已存在
        const existingResults = await this.dbManager.querySql('SELECT id FROM comic_info WHERE id = ?', [item.id]);
        const exists = existingResults.length > 0;
        
        if (exists && strategy === 'skip') {
          logger.debug(TAG, `Skipping existing manga: ${item.title}`);
          continue;
        }
        
        // 对于merge策略，保留现有的阅读进度
        if (exists && strategy === 'merge') {
          const existing = existingResults[0] as Record<string, DatabaseRecord>;
          item.lastReadChapterId = String(existing['lastReadChapterId'] || item.lastReadChapterId || '');
          item.lastReadChapterIndex = Number(existing['lastReadChapterIndex'] || item.lastReadChapterIndex || 0);
          item.lastReadPage = Number(existing['lastReadPage'] || item.lastReadPage || 0);
          item.lastReadTime = Number(existing['lastReadTime'] || item.lastReadTime || 0);
        }
        
        await this.restoreMangaLibrary([item]);
      } catch (error) {
        logger.error(TAG, `Failed to restore manga: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Manga library restore completed');
  }

  private async restoreNovelLibraryWithStrategy(items: NovelBackupItem[], strategy: 'skip' | 'replace' | 'merge'): Promise<void> {
    logger.info(TAG, `Restoring novel library with strategy: ${strategy}, ${items.length} items`);
    
    for (const item of items) {
      try {
        const existingBook = await this.novelDataManager.getBook(item.id);
        const exists = existingBook !== null;
        
        if (exists && strategy === 'skip') {
          logger.debug(TAG, `Skipping existing novel: ${item.name}`);
          continue;
        }
        
        // 对于merge策略，保留现有的阅读进度
        if (exists && strategy === 'merge' && existingBook) {
          item.lastReadChapterId = existingBook.lastReadChapterId || item.lastReadChapterId;
          item.lastReadChapterIndex = existingBook.lastReadChapterIndex || item.lastReadChapterIndex;
          item.lastReadPosition = existingBook.lastReadPosition || item.lastReadPosition;
          item.lastReadTime = existingBook.lastReadTime || item.lastReadTime;
          item.totalReadingTime = (existingBook.totalReadingTime || 0) + (item.totalReadingTime || 0);
        }
        
        await this.restoreNovelLibrary([item]);
      } catch (error) {
        logger.error(TAG, `Failed to restore novel: ${item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Novel library restore completed');
  }

  private async restoreEBookLibraryWithStrategy(items: EBookBackupItem[], strategy: 'skip' | 'replace' | 'merge'): Promise<void> {
    logger.info(TAG, `Restoring ebook library with strategy: ${strategy}, ${items.length} items`);
    
    for (const item of items) {
      try {
        const existingResults = await this.dbManager.querySql('SELECT id, currentPage, readProgress, lastReadTime FROM ebook_info WHERE id = ?', [item.id]);
        const exists = existingResults.length > 0;
        
        if (exists && strategy === 'skip') {
          logger.debug(TAG, `Skipping existing ebook: ${item.title}`);
          continue;
        }
        
        // 对于merge策略，保留更新的阅读进度
        if (exists && strategy === 'merge') {
          const existing = existingResults[0] as Record<string, DatabaseRecord>;
          const existingReadTime = Number(existing['lastReadTime'] || 0);
          const backupReadTime = item.lastReadTime || 0;
          
          if (existingReadTime > backupReadTime) {
            item.currentPage = Number(existing['currentPage'] || item.currentPage);
            item.readProgress = Number(existing['readProgress'] || item.readProgress);
            item.lastReadTime = existingReadTime;
          }
        }
        
        await this.restoreEBookLibrary([item]);
      } catch (error) {
        logger.error(TAG, `Failed to restore ebook: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Ebook library restore completed');
  }

  private async restoreMangaSourcesWithStrategy(items: MangaSourceBackup[], strategy: 'skip' | 'replace' | 'merge'): Promise<void> {
    logger.info(TAG, `Restoring manga sources with strategy: ${strategy}, ${items.length} items`);
    
    // 漫画源通常直接替换，因为源配置不涉及用户数据
    await this.restoreMangaSources(items);
    
    logger.info(TAG, 'Manga sources restore completed');
  }

  private async restoreNovelSourcesWithStrategy(items: NovelSourceBackup[], strategy: 'skip' | 'replace' | 'merge'): Promise<void> {
    logger.info(TAG, `Restoring novel sources with strategy: ${strategy}, ${items.length} items`);
    
    // 小说源直接恢复，由restoreNovelSources内部处理冲突
    // 因为NovelSourceManager使用LegadoBookSource类型，不便于在此处检查
    await this.restoreNovelSources(items);
    
    logger.info(TAG, 'Novel sources restore completed');
  }
}

export function getEnhancedBackupManager(): EnhancedBackupManager {
  return EnhancedBackupManager.getInstance();
}
