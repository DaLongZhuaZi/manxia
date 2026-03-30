/**
 * 增强版备份管理器
 * 支持完整的数据备份、用户选择、tar打包
 * 
 * 文件路径: entry/src/main/ets/Framework/Managers/EnhancedBackupManager.ets
 */

import { logger } from '../../Utils/Logger';
import { SandboxManager } from '../Storage/SandboxManager';
import { DatabaseManager } from '../Database/DatabaseManager';
import { getNovelDataManager, NovelDataManager } from '../Novel/NovelDataManager';
import { getNovelSourceManager, NovelSourceManager } from '../Novel/NovelSourceManager';
import { getNovelSettingsManager, NovelSettingsManager } from '../Novel/NovelSettingsManager';
import { SettingsManager } from './SettingsManager';
import { AppInfoManager } from './AppInfoManager';
import { getTarPackager, TarPackager } from '../Utils/TarPackager';
import { preferences } from '@kit.ArkData';
import { getContext as getGlobalContext } from '../../GlobalContext';
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
  MangaPageBackup,
  MangaReadProgressBackup,
  NovelReadProgressBackup,
  ReaderSettingsBackup,
  GeneralSettingsBackup,
  PrivacySettingsBackup,
  BrowseHistoryBackup,
  SearchHistoryBackup,
  SettingsBackupSection,
  HistoryBackupSection,
  OnlineDataBackupSection,
  CloudConfigBackupSection,
  UnifiedAnnotationBackupItem,
  ProxyConfigBackup,
  FontSettingsBackup,
  CustomFontBackup,
  SettingItemBackup,
  SuwayomiConfigBackup,
  KomgaConfigBackup,
  KomgaInstanceConfigBackup,
  FTPConnectionsBackup,
  FTPConnectionBackup
} from '../../Models/BackupModels';
import { MetadataXmlGenerator, MangaMetadata, EBookMetadata, NovelMetadata } from '../../Utils/MetadataXmlGenerator';
import { KomgaAuthMode, KomgaConfig, KomgaInstanceConfig } from '../Source/KomgaModels';
import { loadKomgaConfig, saveKomgaConfig } from '../Source/KomgaConfigStore';

import { NovelBook, NovelSourceInfo, NovelReadStatus } from '../../Models/NovelModels';
import { LegadoBookSource, LegadoSourceImportResult } from '../Novel/LegadoSourceTypes';
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
const BACKUP_EXTENSION = '.mxbak';
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
  restoreAnnotations: boolean;
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
  // [修复] 所有管理器改为延迟初始化，避免在构造时访问未就绪的单例导致崩溃
  private _dbManager: DatabaseManager | null = null;
  private _sandboxManager: SandboxManager | null = null;
  private _novelDataManager: NovelDataManager | null = null;
  private _novelSourceManager: NovelSourceManager | null = null;
  private _novelSettingsManager: NovelSettingsManager | null = null;
  private _settingsManager: SettingsManager | null = null;
  private _appInfoManager: AppInfoManager | null = null;
  private _tarPackager: TarPackager | null = null;

  private get dbManager(): DatabaseManager {
    if (!this._dbManager) this._dbManager = DatabaseManager.getInstance();
    return this._dbManager;
  }
  private get sandboxManager(): SandboxManager {
    if (!this._sandboxManager) this._sandboxManager = SandboxManager.getInstance();
    return this._sandboxManager;
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
  private get tarPackager(): TarPackager {
    if (!this._tarPackager) this._tarPackager = getTarPackager();
    return this._tarPackager;
  }

  private constructor() {
    // [修复] 构造函数不再立即初始化管理器，推迟到首次访问时
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
      logger.info(TAG, '开始创建备份');
      
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
        
        // 5. [新增] 尝试导出到Download/漫匹/backup文件夹
        const exportedPath = await this.exportToDownloadBackupFolder(finalPath, backupFileName);
        
        logger.info(TAG, `备份创建成功: ${finalPath}`);
        if (exportedPath) {
          logger.info(TAG, `备份已导出到Download文件夹: ${exportedPath}`);
        }
        return finalPath;
        
      } catch (error) {
        // 清理临时目录
        await this.cleanupTempDir(tempDir);
        throw new Error(`备份清理失败: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `备份创建失败: ${error}`);
      throw new Error(`备份创建失败: ${error}`);
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
      restoreAnnotations: true,
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
      logger.info(TAG, `开始恢复备份: ${filePath}`);
      
      // 创建临时解压目录
      const tempDir = await this.createTempRestoreDir();
      
      try {
        // 1. 解压 tar 文件
        await this.tarPackager.extractTarArchive(filePath, tempDir);
        
        // 2. 读取 JSON 数据
        const jsonPath = `${tempDir}/backup.json`;
        const backupData = await this.loadJSON(jsonPath);
        
        this.validateBackupData(backupData);
        
        // 3. 先恢复媒体文件（包括字体文件），确保文件在设置恢复前就位
        if (options.restoreMediaFiles) {
          await this.restoreMediaFiles(tempDir);
        }
        
        // 4. 选择性恢复数据（包括字体设置，需要字体文件已存在）
        await this.restoreBackupDataWithOptions(backupData, options);
        
        // 5. 清理临时目录
        await this.cleanupTempDir(tempDir);
        
        logger.info(TAG, '备份恢复完成');
        
      } catch (error) {
        await this.cleanupTempDir(tempDir);
        throw new Error(`备份恢复清理失败: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `备份恢复失败: ${error}`);
      throw new Error(`备份恢复失败: ${error}`);
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
            sources: (backupData.sources?.manga?.length || 0) + (backupData.sources?.novel?.length || 0),
            annotations: backupData.annotations?.records?.length || 0
          },
          options: backupData.options || DEFAULT_BACKUP_OPTIONS,
          fileSize: stat.size
        };
        
        await this.cleanupTempDir(tempDir);
        
        return metadata;
        
      } catch (error) {
        await this.cleanupTempDir(tempDir);
        throw new Error(`元数据清理失败: ${error}`);
      }
      
    } catch (error) {
      logger.error(TAG, `读取备份元数据失败: ${error}`);
      throw new Error(`读取备份元数据失败: ${error}`);
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
    
    // 导出字体设置
    const fontSettings = await this.exportFontSettings();
    
    const generalSettings: GeneralSettingsBackup = {
      theme: this.settingsManager.getString('app_theme', 'auto'),
      language: this.settingsManager.getString('app_language', 'zh-CN'),
      proxyConfig: proxyConfig,
      fontSettings: fontSettings
    };
    const privacySettings: PrivacySettingsBackup = {
      sfwMode: this.settingsManager.getBoolean('sfw_mode_enabled', false),
      privateLibraryEnabled: this.settingsManager.getBoolean('private_library_enabled', false)
    };
    
    // 导出整个设置表
    const allSettings = options.includeSettings ? await this.exportAllSettings() : [];
    
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
        privacy: privacySettings,
        allSettings: allSettings
      },
      
      history: {
        browse: options.includeHistory ? await this.exportBrowseHistory() : [],
        search: options.includeHistory ? await this.exportSearchHistory() : []
      },

      annotations: {
        records: options.includeAnnotations ? await this.exportUnifiedAnnotations() : []
      },
      
      cloudConfig: options.includeCloudConfig ? await this.exportCloudConfig() : undefined,
      options: options,
      webview: {
        configs: options.includeWebViewConfig ? await this.exportWebViewConfigs() : []
      },
      downloads: {
        tasks: options.includeDownloadTasks ? await this.exportDownloadTasks() : []
      },
      cache: {
        items: options.includeCacheInfo ? await this.exportCacheInfo() : []
      },
      plugins: {
        plugins: options.includePlugins ? await this.exportPlugins() : []
      },
      favorites: {
        favorites: options.includeFavorites ? await this.exportFavorites() : []
      },
      onlineData: options.includeOnlineData ? await this.exportOnlineData() : {
        comics: [],
        readHistory: []
      }
    };
    
    return data;
  }
  
  /**
   * 导出云存储配置（包含WebDAV、Suwayomi、FTP）
   */
  private async exportCloudConfig(): Promise<CloudConfigBackupSection> {
    const result: CloudConfigBackupSection = {};
    
    // 1. 导出WebDAV配置
    try {
      const context = getGlobalContext();
      const webdavPrefs = await preferences.getPreferences(context, 'webdav_settings');
      const serverUrl = await webdavPrefs.get('serverUrl', '') as string;
      if (serverUrl) {
        result.webdav = {
          serverUrl: serverUrl,
          username: await webdavPrefs.get('username', '') as string,
          password: await webdavPrefs.get('password', '') as string,
          basePath: await webdavPrefs.get('basePath', '/manxia') as string,
          autoBackup: await webdavPrefs.get('autoBackup', false) as boolean,
          autoBackupInterval: await webdavPrefs.get('autoBackupInterval', 'daily') as 'manual' | 'daily' | 'weekly',
          keepBackupCount: await webdavPrefs.get('keepBackupCount', 5) as number
        };
        logger.info(TAG, `导出WebDAV配置: ${serverUrl}`);
      }
    } catch (error) {
      logger.warn(TAG, `导出WebDAV配置失败: ${error}`);
    }
    
    // 2. 导出Suwayomi配置
    try {
      const context = getGlobalContext();
      const suwayomiPrefs = await preferences.getPreferences(context, 'suwayomi_config');
      const serverUrl = await suwayomiPrefs.get('serverUrl', '') as string;
      if (serverUrl) {
        result.suwayomi = {
          serverUrl: serverUrl,
          username: await suwayomiPrefs.get('username', '') as string,
          password: await suwayomiPrefs.get('password', '') as string,
          useAuth: await suwayomiPrefs.get('useAuth', false) as boolean,
          useBrowsePageAsEntry: await suwayomiPrefs.get('useBrowsePageAsEntry', false) as boolean
        };
        logger.info(TAG, `导出Suwayomi配置: ${serverUrl}`);
      }
    } catch (error) {
      logger.warn(TAG, `导出Suwayomi配置失败: ${error}`);
    }
    
    // 3. 导出 Komga 配置
    try {
      const komgaConfig = await loadKomgaConfig();
      const hasMeaningfulInstance = komgaConfig.instances.some(instance =>
        instance.serverUrl.trim().length > 0 ||
        instance.displayName.trim().length > 0 ||
        instance.username.trim().length > 0 ||
        instance.password.trim().length > 0 ||
        instance.apiKey.trim().length > 0 ||
        instance.defaultLibraryIds.length > 0
      );
      if (hasMeaningfulInstance || komgaConfig.useBrowsePageAsEntry !== true) {
        const instances: KomgaInstanceConfigBackup[] = [];
        komgaConfig.instances.forEach((instance: KomgaInstanceConfig) => {
          const instanceBackup: KomgaInstanceConfigBackup = {
            id: instance.id,
            displayName: instance.displayName,
            serverUrl: instance.serverUrl,
            authMode: instance.authMode,
            username: instance.username,
            password: instance.password,
            apiKey: instance.apiKey,
            defaultLibraryIds: instance.defaultLibraryIds.concat(),
            chapterTitleTemplate: instance.chapterTitleTemplate,
            enabled: instance.enabled
          };
          instances.push(instanceBackup);
        });
        const komgaBackup: KomgaConfigBackup = {
          instances,
          currentInstanceId: komgaConfig.currentInstanceId,
          useBrowsePageAsEntry: komgaConfig.useBrowsePageAsEntry
        };
        result.komga = komgaBackup;
        logger.info(TAG, `已导出 Komga 配置，共 ${instances.length} 个实例`);
      }
    } catch (error) {
      logger.warn(TAG, `导出 Komga 配置失败：${String(error)}`);
    }
    
    try {
      const context = getGlobalContext();
      const ftpPrefs = await preferences.getPreferences(context, 'ftp_connections');
      const connectionsJson = await ftpPrefs.get('connections', '[]') as string;
      const connections = JSON.parse(connectionsJson) as FTPConnectionBackup[];
      if (connections.length > 0) {
        result.ftp = { connections: connections };
        logger.info(TAG, `导出FTP连接: ${connections.length}个`);
      }
    } catch (error) {
      logger.warn(TAG, `导出FTP配置失败: ${error}`);
    }
    
    return result;
  }
  
  /**
   * 导出整个设置表
   */
  private async exportAllSettings(): Promise<SettingItemBackup[]> {
    try {
      const dataManager = (await import('../Data/DataManager')).DataManager.getInstance();
      const allSettings = await dataManager.getAllSettings();
      
      const result: SettingItemBackup[] = [];
      for (const setting of allSettings) {
        const item: SettingItemBackup = {
          settingKey: setting.settingKey,
          settingValue: setting.settingValue,
          settingType: setting.settingType
        };
        result.push(item);
      }
      
      logger.info(TAG, `导出设置表: ${result.length}个设置项`);
      return result;
    } catch (error) {
      logger.error(TAG, `导出设置表失败: ${error}`);
      return [];
    }
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
      restoreAnnotations: true,
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
    logger.info(TAG, `开始选择性数据恢复，策略: ${options.conflictStrategy}`);
    logger.info(TAG, `备份数据检查: manga=${!!backupData.manga}, manga.library=${!!backupData.manga?.library}, 数量=${backupData.manga?.library?.length || 0}`);
    
    try {
      if (options.restoreMangaLibrary && backupData.manga?.library) {
        logger.info(TAG, `开始恢复漫画库，数量: ${backupData.manga.library.length}`);
        await this.restoreMangaLibraryWithStrategy(backupData.manga.library, options.conflictStrategy);
      } else {
        logger.info(TAG, `跳过漫画库恢复: restoreMangaLibrary=${options.restoreMangaLibrary}, hasLibrary=${!!backupData.manga?.library}`);
      }
    } catch (error) {
      logger.error(TAG, `恢复漫画库失败: ${error}`);
    }
    
    try {
      if (options.restoreNovelLibrary && backupData.novel?.library) {
        await this.restoreNovelLibraryWithStrategy(backupData.novel.library, options.conflictStrategy);
      }
    } catch (error) {
      logger.error(TAG, `恢复小说库失败: ${error}`);
    }
    
    try {
      if (options.restoreEBookLibrary && backupData.ebook?.library) {
        await this.restoreEBookLibraryWithStrategy(backupData.ebook.library, options.conflictStrategy);
      }
    } catch (error) {
      logger.error(TAG, `恢复电子书库失败: ${error}`);
    }
    
    try {
      if (options.restoreSources && backupData.sources?.manga) {
        await this.restoreMangaSourcesWithStrategy(backupData.sources.manga, options.conflictStrategy);
      }
    } catch (error) {
      logger.error(TAG, `恢复漫画源失败: ${error}`);
    }
    
    try {
      if (options.restoreSources && backupData.sources?.novel) {
        await this.restoreNovelSourcesWithStrategy(backupData.sources.novel, options.conflictStrategy);
      }
    } catch (error) {
      logger.error(TAG, `恢复小说源失败: ${error}`);
    }
    
    try {
      if (options.restoreReadProgress && backupData.manga?.readProgress) {
        await this.restoreMangaReadProgress(backupData.manga.readProgress);
      }
    } catch (error) {
      logger.error(TAG, `恢复漫画阅读进度失败: ${error}`);
    }
    
    try {
      if (options.restoreReadProgress && backupData.novel?.readProgress) {
        await this.restoreNovelReadProgress(backupData.novel.readProgress);
      }
    } catch (error) {
      logger.error(TAG, `恢复小说阅读进度失败: ${error}`);
    }
    
    try {
      if (options.restoreSettings && backupData.settings) {
        await this.restoreSettings(backupData.settings);
        // 恢复整个设置表
        if (backupData.settings.allSettings) {
          await this.restoreAllSettings(backupData.settings.allSettings);
        }
      }
    } catch (error) {
      logger.error(TAG, `恢复设置失败: ${error}`);
    }
    
    try {
      if (options.restoreHistory && backupData.history) {
        await this.restoreHistory(backupData.history);
      }
    } catch (error) {
      logger.error(TAG, `恢复历史记录失败: ${error}`);
    }

    try {
      if (options.restoreAnnotations && backupData.annotations?.records) {
        await this.restoreUnifiedAnnotationsWithStrategy(backupData.annotations.records, options.conflictStrategy);
      }
    } catch (error) {
      logger.error(TAG, `恢复统一标注失败: ${error}`);
    }
    
    try {
      if (options.restoreWebViewConfig && backupData.webview) {
        await this.restoreWebViewConfigs(backupData.webview.configs);
      }
    } catch (error) {
      logger.error(TAG, `恢复WebView配置失败: ${error}`);
    }
    
    try {
      if (options.restoreDownloadTasks && backupData.downloads) {
        await this.restoreDownloadTasks(backupData.downloads.tasks);
      }
    } catch (error) {
      logger.error(TAG, `恢复下载任务失败: ${error}`);
    }
    
    try {
      if (options.restoreFavorites && backupData.favorites) {
        await this.restoreFavorites(backupData.favorites.favorites);
      }
    } catch (error) {
      logger.error(TAG, `恢复收藏失败: ${error}`);
    }
    
    try {
      if (options.restoreOnlineData && backupData.onlineData) {
        await this.restoreOnlineData(backupData.onlineData);
      }
    } catch (error) {
      logger.error(TAG, `恢复在线数据失败: ${error}`);
    }
    
    try {
      if (options.restoreCloudConfig && backupData.cloudConfig) {
        await this.restoreCloudConfig(backupData.cloudConfig);
      }
    } catch (error) {
      logger.error(TAG, `恢复云存储配置失败: ${error}`);
    }
    
    logger.info(TAG, '数据恢复完成');
  }
  
  /**
   * 恢复云存储配置（包含WebDAV、Suwayomi、FTP）
   */
  private async restoreCloudConfig(cloudConfig: CloudConfigBackupSection): Promise<void> {
    const context = getGlobalContext();
    
    // 1. 恢复WebDAV配置
    if (cloudConfig.webdav) {
      try {
        const webdavPrefs = await preferences.getPreferences(context, 'webdav_settings');
        await webdavPrefs.put('serverUrl', cloudConfig.webdav.serverUrl);
        await webdavPrefs.put('username', cloudConfig.webdav.username);
        await webdavPrefs.put('password', cloudConfig.webdav.password);
        await webdavPrefs.put('basePath', cloudConfig.webdav.basePath);
        await webdavPrefs.put('autoBackup', cloudConfig.webdav.autoBackup);
        await webdavPrefs.put('autoBackupInterval', cloudConfig.webdav.autoBackupInterval);
        await webdavPrefs.put('keepBackupCount', cloudConfig.webdav.keepBackupCount);
        await webdavPrefs.put('enabled', false); // 恢复后需要用户手动启用
        await webdavPrefs.put('connectionStatus', 'untested');
        await webdavPrefs.flush();
        logger.info(TAG, `WebDAV配置恢复成功: ${cloudConfig.webdav.serverUrl}`);
      } catch (error) {
        logger.error(TAG, `恢复WebDAV配置失败: ${error}`);
      }
    }
    
    // 2. 恢复Suwayomi配置
    if (cloudConfig.suwayomi) {
      try {
        const suwayomiPrefs = await preferences.getPreferences(context, 'suwayomi_config');
        await suwayomiPrefs.put('serverUrl', cloudConfig.suwayomi.serverUrl);
        await suwayomiPrefs.put('username', cloudConfig.suwayomi.username);
        await suwayomiPrefs.put('password', cloudConfig.suwayomi.password);
        await suwayomiPrefs.put('useAuth', cloudConfig.suwayomi.useAuth);
        await suwayomiPrefs.put('useBrowsePageAsEntry', cloudConfig.suwayomi.useBrowsePageAsEntry);
        await suwayomiPrefs.flush();
        logger.info(TAG, `Suwayomi配置恢复成功: ${cloudConfig.suwayomi.serverUrl}`);
      } catch (error) {
        logger.error(TAG, `恢复Suwayomi配置失败: ${error}`);
      }
    }
    
    // 3. 恢复 Komga 配置
    if (cloudConfig.komga) {
      try {
        const komgaBackup: KomgaConfigBackup = cloudConfig.komga;
        const restoredInstances: KomgaInstanceConfig[] = [];
        (komgaBackup.instances || []).forEach((instance: KomgaInstanceConfigBackup) => {
          const authMode: KomgaAuthMode = instance.authMode === 'BASIC' || instance.authMode === 'API_KEY'
            ? instance.authMode
            : 'NONE';
          const defaultLibraryIds: string[] = Array.isArray(instance.defaultLibraryIds)
            ? instance.defaultLibraryIds.map((item: string) => String(item))
            : [];
          const restoredInstance: KomgaInstanceConfig = {
            id: typeof instance.id === 'string' ? instance.id : '',
            displayName: typeof instance.displayName === 'string' ? instance.displayName : '',
            serverUrl: typeof instance.serverUrl === 'string' ? instance.serverUrl : '',
            authMode: authMode,
            username: typeof instance.username === 'string' ? instance.username : '',
            password: typeof instance.password === 'string' ? instance.password : '',
            apiKey: typeof instance.apiKey === 'string' ? instance.apiKey : '',
            defaultLibraryIds: defaultLibraryIds,
            chapterTitleTemplate: typeof instance.chapterTitleTemplate === 'string' ? instance.chapterTitleTemplate : '',
            enabled: instance.enabled !== false
          };
          restoredInstances.push(restoredInstance);
        });
        const restoredConfig: KomgaConfig = {
          instances: restoredInstances,
          currentInstanceId: typeof komgaBackup.currentInstanceId === 'string' ? komgaBackup.currentInstanceId : '',
          useBrowsePageAsEntry: komgaBackup.useBrowsePageAsEntry !== false
        };
        const success = await saveKomgaConfig(restoredConfig);
        if (!success) {
          throw new Error('saveKomgaConfig failed');
        }
        logger.info(TAG, `已恢复 Komga 配置，共 ${restoredConfig.instances.length} 个实例`);
      } catch (error) {
        logger.error(TAG, `恢复 Komga 配置失败：${String(error)}`);
      }
    }
    
    if (cloudConfig.ftp && cloudConfig.ftp.connections.length > 0) {
      try {
        const ftpPrefs = await preferences.getPreferences(context, 'ftp_connections');
        await ftpPrefs.put('connections', JSON.stringify(cloudConfig.ftp.connections));
        await ftpPrefs.flush();
        logger.info(TAG, `FTP连接配置恢复成功: ${cloudConfig.ftp.connections.length}个`);
      } catch (error) {
        logger.error(TAG, `恢复FTP配置失败: ${error}`);
      }
    }
  }
  
  /**
   * 恢复整个设置表
   */
  private async restoreAllSettings(allSettings: SettingItemBackup[]): Promise<void> {
    if (!allSettings || allSettings.length === 0) {
      logger.info(TAG, '没有设置表数据需要恢复');
      return;
    }
    
    try {
      const dataManager = (await import('../Data/DataManager')).DataManager.getInstance();
      let successCount = 0;
      let failCount = 0;
      
      for (const setting of allSettings) {
        try {
          await dataManager.saveSetting(setting.settingKey, setting.settingValue, setting.settingType);
          successCount++;
        } catch (e) {
          failCount++;
          logger.warn(TAG, `恢复设置失败: ${setting.settingKey}`);
        }
      }
      
      // 重新加载设置到缓存
      await this.settingsManager.initialize();
      this.settingsManager.syncToAppStorage();
      
      logger.info(TAG, `设置表恢复完成: 成功=${successCount}, 失败=${failCount}`);
    } catch (error) {
      logger.error(TAG, `恢复设置表失败: ${error}`);
    }
  }

  /**
   * 复制媒体文件到备份目录
   */
  private async copyMediaFiles(tempDir: string, options: BackupOptions, backupData: BackupData): Promise<void> {
    try {
      if (options.includeCoverImages) {
        logger.info(TAG, '正在复制媒体文件: 封面');
        const coversDir = `${tempDir}/covers`;
        if (!fs.accessSync(coversDir)) {
          fs.mkdirSync(coversDir, true);
        }
        // [修复] 传入备份根目录，漫画放在根目录/manga下而不是covers/manga下
        await this.copyCoverImages(coversDir, tempDir, backupData.manga.library, backupData.novel?.library);
        logger.info(TAG, '媒体文件复制完成: 封面');
        
        // [新增] 复制图源封面到covers/{pkg}/目录
        await this.copyMangaSourceCovers(coversDir, backupData.sources.manga);
      }
      
      if (options.includeChapterImages) {
        logger.info(TAG, '正在复制媒体文件: 章节');
        const chaptersDir = `${tempDir}/chapters`;
        if (!fs.accessSync(chaptersDir)) {
          fs.mkdirSync(chaptersDir, true);
        }
        await this.copyChapterImages(chaptersDir);
        logger.info(TAG, '媒体文件复制完成: 章节');
      }
      
      if (options.includeEBookFiles) {
        logger.info(TAG, '正在复制媒体文件: 电子书');
        const ebooksDir = `${tempDir}/ebooks`;
        if (!fs.accessSync(ebooksDir)) {
          fs.mkdirSync(ebooksDir, true);
        }
        await this.copyEBookFiles(ebooksDir, backupData.ebook.library);
        logger.info(TAG, '媒体文件复制完成: 电子书');
      }
      
      // [新增] 导出书源为单独JSON文件到legadoextensions目录
      if (options.includeSources && backupData.sources.novel && backupData.sources.novel.length > 0) {
        logger.info(TAG, '正在导出书源文件');
        await this.exportNovelSourcesToFiles(tempDir, backupData.sources.novel);
        logger.info(TAG, '书源文件导出完成');
      }
      
      // [新增] 复制图源icon文件
      if (options.includeSources) {
        logger.info(TAG, '正在复制图源icon文件');
        await this.copySourceIcons(tempDir);
        logger.info(TAG, '图源icon文件复制完成');
      }
      
      // [新增] 复制自定义字体文件
      logger.info(TAG, '正在复制自定义字体文件');
      await this.copyCustomFonts(tempDir);
      logger.info(TAG, '自定义字体文件复制完成');
    } catch (error) {
      logger.error(TAG, `复制媒体文件失败: ${error}`);
    }
  }
  
  /**
   * 复制图源icon文件到备份目录
   */
  private async copySourceIcons(tempDir: string): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    const iconsSourceDir = `${filesDir}/extensions-source/icons`;
    
    if (!fs.accessSync(iconsSourceDir)) {
      logger.warn(TAG, `图源icon目录不存在: ${iconsSourceDir}`);
      return;
    }
    
    const iconsTargetDir = `${tempDir}/icons`;
    if (!fs.accessSync(iconsTargetDir)) {
      fs.mkdirSync(iconsTargetDir, true);
    }
    
    try {
      const count = await this.copyDirectoryRecursive(iconsSourceDir, iconsTargetDir);
      logger.info(TAG, `图源icon复制完成: ${count} 个文件`);
    } catch (error) {
      logger.error(TAG, `复制图源icon失败: ${error}`);
    }
  }
  
  /**
   * 复制自定义字体文件到备份目录
   * 从FontManager的preferences中读取字体文件路径，直接复制文件
   */
  private async copyCustomFonts(tempDir: string): Promise<void> {
    try {
      // 从FontManager的preferences读取自定义字体列表
      const context = getGlobalContext();
      const fontPrefs: preferences.Preferences = await preferences.getPreferences(context, 'font_settings');
      const customFontsStr = await fontPrefs.get('custom_fonts', '') as string;
      
      if (!customFontsStr) {
        logger.debug(TAG, '没有自定义字体需要备份');
        return;
      }
      
      const customFontsRaw = JSON.parse(customFontsStr) as Array<Record<string, Object>>;
      if (customFontsRaw.length === 0) {
        logger.debug(TAG, '自定义字体列表为空');
        return;
      }
      
      logger.info(TAG, `找到 ${customFontsRaw.length} 个自定义字体需要备份`);
      
      const fontsTargetDir = `${tempDir}/fonts`;
      if (!fs.accessSync(fontsTargetDir)) {
        fs.mkdirSync(fontsTargetDir, true);
      }
      
      let copiedCount = 0;
      for (const font of customFontsRaw) {
        const filePath = String(font['filePath'] || '');
        if (!filePath) {
          logger.warn(TAG, `字体缺少文件路径: ${font['displayName']}`);
          continue;
        }
        
        logger.info(TAG, `检查字体文件: ${filePath}`);
        
        if (!fs.accessSync(filePath)) {
          logger.warn(TAG, `字体文件不存在: ${filePath}`);
          continue;
        }
        
        // 从路径中提取文件名
        const fileName = filePath.split('/').pop() || '';
        const targetPath = `${fontsTargetDir}/${fileName}`;
        
        try {
          fs.copyFileSync(filePath, targetPath);
          copiedCount++;
          logger.info(TAG, `已复制字体文件: ${fileName}`);
        } catch (copyError) {
          logger.error(TAG, `复制字体文件失败: ${fileName}, ${copyError}`);
        }
      }
      
      logger.info(TAG, `自定义字体复制完成: ${copiedCount} 个文件`);
      
      // [修复] 验证字体目录和文件是否正确创建
      try {
        if (fs.accessSync(fontsTargetDir)) {
          const fontFiles = fs.listFileSync(fontsTargetDir);
          logger.info(TAG, `[验证] 字体目录存在: ${fontsTargetDir}, 包含文件: ${fontFiles.join(', ') || '空'}`);
        } else {
          logger.error(TAG, `[验证失败] 字体目录不存在: ${fontsTargetDir}`);
        }
      } catch (verifyError) {
        logger.error(TAG, `[验证失败] 无法验证字体目录: ${verifyError}`);
      }
    } catch (error) {
      logger.error(TAG, `复制自定义字体失败: ${error}`);
    }
  }
  
  /**
   * 复制图源封面到备份目录
   * 按照沙盒目录结构，使用pkg名称建立单独的文件夹
   */
  private async copyMangaSourceCovers(coversDir: string, mangaSources: MangaSourceBackup[]): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    const sourceCoversDir = `${filesDir}/covers`;
    
    logger.debug(TAG, `检查图源封面目录: ${sourceCoversDir}`);
    
    if (!fs.accessSync(sourceCoversDir)) {
      logger.warn(TAG, `图源封面目录不存在: ${sourceCoversDir}`);
      return;
    }
    
    let copiedCount = 0;
    
    try {
      // 列出所有封面子目录
      const coverDirs = fs.listFileSync(sourceCoversDir);
      logger.debug(TAG, `封面目录下的子目录: ${coverDirs.join(', ')}`);
      
      // 直接复制所有封面子目录（不仅限于已知图源）
      for (const dirName of coverDirs) {
        const sourcePath = `${sourceCoversDir}/${dirName}`;
        const stat = fs.statSync(sourcePath);
        
        if (!stat.isDirectory()) continue;
        
        // 跳过特殊目录
        if (['manga', 'ebook', 'novel', 'download_import'].includes(dirName)) continue;
        
        // 创建目标目录
        const targetDir = `${coversDir}/${dirName}`;
        if (!fs.accessSync(targetDir)) {
          fs.mkdirSync(targetDir, true);
        }
        
        // 复制封面文件
        const count = await this.copyDirectoryRecursive(sourcePath, targetDir);
        copiedCount += count;
        if (count > 0) {
          logger.debug(TAG, `已复制图源封面: ${dirName} (${count} 个文件)`);
        }
      }
      
      logger.info(TAG, `图源封面复制完成: ${copiedCount} 个文件`);
    } catch (error) {
      logger.error(TAG, `复制图源封面失败: ${error}`);
    }
  }
  
  /**
   * 导出书源为单独JSON文件到legadoextensions目录
   */
  private async exportNovelSourcesToFiles(tempDir: string, novelSources: NovelSourceBackup[]): Promise<void> {
    const legadoDir = `${tempDir}/legadoextensions`;
    if (!fs.accessSync(legadoDir)) {
      fs.mkdirSync(legadoDir, true);
    }
    
    let exportedCount = 0;
    
    for (const source of novelSources) {
      try {
        // 获取书源名称（优先仌configJson中获取）
        let sourceName = source.bookSourceName || source.name || '';
        
        // 从 configJson解析完整的书源配置
        let sourceConfig: Record<string, Object> | null = null;
        if (source.configJson) {
          try {
            sourceConfig = JSON.parse(source.configJson) as Record<string, Object>;
            // 仌configJson中获取书源名称
            if (sourceConfig['bookSourceName']) {
              sourceName = String(sourceConfig['bookSourceName']);
            }
          } catch {
            // 如果configJson解析失败，使用备份数据构建
            const fallbackConfig: Record<string, Object> = {};
            fallbackConfig['bookSourceUrl'] = source.bookSourceUrl;
            fallbackConfig['bookSourceName'] = sourceName;
            fallbackConfig['bookSourceGroup'] = source.bookSourceGroup || '';
            fallbackConfig['bookSourceType'] = source.bookSourceType || 0;
            fallbackConfig['enabled'] = source.enabled;
            fallbackConfig['weight'] = source.weight || 0;
            sourceConfig = fallbackConfig;
          }
        } else {
          const fallbackConfig: Record<string, Object> = {};
          fallbackConfig['bookSourceUrl'] = source.bookSourceUrl;
          fallbackConfig['bookSourceName'] = sourceName;
          fallbackConfig['bookSourceGroup'] = source.bookSourceGroup || '';
          fallbackConfig['bookSourceType'] = source.bookSourceType || 0;
          fallbackConfig['enabled'] = source.enabled;
          fallbackConfig['weight'] = source.weight || 0;
          sourceConfig = fallbackConfig;
        }
        
        // 跳过没有名称的书源
        if (!sourceName) {
          logger.warn(TAG, `跳过无名称书源: ${source.bookSourceUrl}`);
          continue;
        }
        
        // 生成安全的文件名
        const safeName = sourceName.replace(/[\\/:*?"<>|]/g, '_');
        const fileName = `${safeName}.json`;
        const filePath = `${legadoDir}/${fileName}`;
        
        // 写入JSON文件（数组格式，兼容Legado导入）
        const jsonContent = JSON.stringify([sourceConfig], null, 2);
        const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, jsonContent);
        fs.closeSync(file);
        
        exportedCount++;
        logger.debug(TAG, `已导出书源: ${source.bookSourceName}`);
      } catch (error) {
        logger.warn(TAG, `导出书源失败: ${source.bookSourceName}, ${error}`);
      }
    }
    
    logger.info(TAG, `书源导出完成: ${exportedCount}/${novelSources.length}`);
  }

  /**
   * 复制封面图片
   * @param coversDir 封面目录（用于电子书和小说封面）
   * @param backupRootDir 备份根目录（用于漫画，放在根目录/manga下）
   */
  private async copyCoverImages(coversDir: string, backupRootDir: string, mangaList: MangaBackupItem[], novelList?: NovelBackupItem[]): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    let totalDirs = 0;
    let totalFiles = 0;
    
    try {
      // 复制漫画相关文件（包括封面和章节图片）
      const comicsDir = this.sandboxManager.getDirectory('comics');
      logger.debug(TAG, `漫画目录: ${comicsDir}, 存在: ${fs.accessSync(comicsDir)}`);
      
      // [新增] 获取Download同步目录
      const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
      logger.debug(TAG, `Download同步目录: ${downloadDirPath || '未配置'}`);
      
      if (fs.accessSync(comicsDir)) {
        // [修复] 漫画放在备份根目录/manga下，而不是covers/manga下
        const mangaTarget = `${backupRootDir}/manga`;
        if (!fs.accessSync(mangaTarget)) {
          fs.mkdirSync(mangaTarget, true);
        }
        
        // 方法1：基于数据库记录的漫画列表
        logger.debug(TAG, `正在处理 ${mangaList.length} 个漫画`);
        for (const manga of mangaList) {
          try {
            // [修复] 检查是否为Download同步导入的漫画
            const isDownloadImport = manga.contentType === 'download_import' || 
                                     manga.sourceId === 'download_import' ||
                                     (manga.coverLocalPath && manga.coverLocalPath.includes('/storage/'));
            
            const sanitizedTitle = manga.title.replace(/[\\/:*?"<>|]/g, '_');
            
            // [修复] 对于Download同步导入的漫画，优先检查Download/manga目录
            if (isDownloadImport && downloadDirPath) {
              // [修复] 优先在manga子目录下查找
              const downloadMangaDirInManga = `${downloadDirPath}/manga/${sanitizedTitle}`;
              const downloadMangaDirInMangaOriginal = `${downloadDirPath}/manga/${manga.title}`;
              // 兼容旧版本：也检查根目录
              const downloadMangaDir = `${downloadDirPath}/${sanitizedTitle}`;
              const downloadMangaDirOriginal = `${downloadDirPath}/${manga.title}`;
              
              logger.debug(TAG, `检查Download漫画目录: ${downloadMangaDirInManga}`);
              
              let foundDir = '';
              if (fs.accessSync(downloadMangaDirInManga)) {
                foundDir = downloadMangaDirInManga;
              } else if (fs.accessSync(downloadMangaDirInMangaOriginal)) {
                foundDir = downloadMangaDirInMangaOriginal;
              } else if (fs.accessSync(downloadMangaDir)) {
                foundDir = downloadMangaDir;
              } else if (fs.accessSync(downloadMangaDirOriginal)) {
                foundDir = downloadMangaDirOriginal;
              }
              
              if (foundDir) {
                const targetMangaDir = `${mangaTarget}/download_import/${sanitizedTitle}`;
                if (!fs.accessSync(targetMangaDir)) {
                  fs.mkdirSync(targetMangaDir, true);
                }
                const count = await this.copyDirectoryRecursive(foundDir, targetMangaDir);
                totalFiles += count;
                totalDirs++;
                
                // [修复] 生成ComicInfo.xml元数据文件
                try {
                  this.generateMangaMetadataXml(manga, targetMangaDir);
                  logger.debug(TAG, `已生成漫画元数据: ${targetMangaDir}/ComicInfo.xml`);
                } catch (e) {
                  logger.warn(TAG, `生成漫画元数据失败: ${String(e)}`);
                }
                
                logger.info(TAG, `已复制Download漫画: ${sanitizedTitle} (${count} 个文件)`);
                continue;
              } else {
                logger.warn(TAG, `Download漫画目录未找到: ${downloadMangaDir}`);
              }
            }
            
            // [修复] 如果有coverLocalPath，尝试从中提取漫画目录路径
            if (isDownloadImport && manga.coverLocalPath) {
              const coverPath = manga.coverLocalPath;
              logger.debug(TAG, `Download漫画封面路径: ${coverPath}`);
              
              // 尝试找到漫画目录
              let mangaDir = '';
              const pathParts = coverPath.split('/');
              
              // 查找包含漫画标题的目录
              for (let i = pathParts.length - 1; i >= 0; i--) {
                if (pathParts[i] === sanitizedTitle || pathParts[i] === manga.title) {
                  mangaDir = pathParts.slice(0, i + 1).join('/');
                  break;
                }
              }
              
              if (mangaDir && fs.accessSync(mangaDir)) {
                const targetMangaDir = `${mangaTarget}/download_import/${sanitizedTitle}`;
                if (!fs.accessSync(targetMangaDir)) {
                  fs.mkdirSync(targetMangaDir, true);
                }
                const count = await this.copyDirectoryRecursive(mangaDir, targetMangaDir);
                totalFiles += count;
                totalDirs++;
                logger.info(TAG, `已复制Download漫画(从封面路径): ${sanitizedTitle} (${count} 个文件)`);
                continue;
              }
            }
            
            // 尝试从coverLocalPath提取路径（沙盒内的漫画）
            let sourceName = '';
            let comicName = '';
            
            if (manga.coverLocalPath) {
              logger.debug(TAG, `漫画: ${manga.title}, 封面路径: ${manga.coverLocalPath}`);
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
              logger.debug(TAG, `使用备用路径: ${sourceName}/${comicName}`);
            }
            
            const mangaDir = `${comicsDir}/${sourceName}/${comicName}`;
            logger.debug(TAG, `检查漫画目录: ${mangaDir}, 存在: ${fs.accessSync(mangaDir)}`);
            
            if (fs.accessSync(mangaDir)) {
              const targetMangaDir = `${mangaTarget}/${sourceName}/${comicName}`;
              if (!fs.accessSync(targetMangaDir)) {
                fs.mkdirSync(targetMangaDir, true);
              }
              const count = await this.copyDirectoryRecursive(mangaDir, targetMangaDir);
              totalFiles += count;
              totalDirs++;
              
              // [重构] 生成ComicInfo.xml元数据文件
              await this.generateMangaMetadataXml(manga, targetMangaDir);
              
              logger.info(TAG, `已复制漫画: ${comicName} (${count} 个文件，含元数据)`);
            } else {
              logger.warn(TAG, `漫画目录未找到: ${mangaDir}`);
            }
          } catch (error) {
            logger.error(TAG, `复制漫画失败 ${manga.title}: ${error}`);
          }
        }
        
        // 方法2：直接遍历comics目录，备份所有源的所有漫画（兜底策略）
        logger.debug(TAG, `扫描comics目录查找额外文件`);
        try {
          const sourceEntries = fs.listFileSync(comicsDir);
          logger.debug(TAG, `找到 ${sourceEntries.length} 个源目录`);
          
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
      
      // [重构] 复制小说封面（使用文件夹结构，每本小说一个文件夹）
      const novelCoversDir = `${filesDir}/novel_covers`;
      const novelTarget = `${coversDir}/novel`;
      if (!fs.accessSync(novelTarget)) {
        fs.mkdirSync(novelTarget, true);
      }
      
      if (novelList && novelList.length > 0) {
        for (const novel of novelList) {
          try {
            const sanitizedName = novel.name.replace(/[\\/:*?"<>|]/g, '_');
            const novelFolderPath = `${novelTarget}/${sanitizedName}`;
            
            if (!fs.accessSync(novelFolderPath)) {
              fs.mkdirSync(novelFolderPath, true);
            }
            
            // 复制封面图片（如果有本地封面）
            if (novel.coverLocalPath && fs.accessSync(novel.coverLocalPath)) {
              const coverExt = novel.coverLocalPath.includes('.') ? 
                novel.coverLocalPath.substring(novel.coverLocalPath.lastIndexOf('.')) : '.jpg';
              const coverTargetPath = `${novelFolderPath}/cover${coverExt}`;
              fs.copyFileSync(novel.coverLocalPath, coverTargetPath);
              totalFiles++;
              logger.debug(TAG, `已复制小说封面: ${sanitizedName}`);
            }
            
            // 生成metadata.xml
            await this.generateNovelMetadataXml(novel, novelFolderPath);
            totalDirs++;
          } catch (error) {
            logger.warn(TAG, `复制小说封面失败 ${novel.name}: ${error}`);
          }
        }
        logger.info(TAG, `已复制 ${totalDirs} 本小说（文件夹结构）`);
      } else if (fs.accessSync(novelCoversDir)) {
        // 回退：直接复制整个目录
        const count = await this.copyDirectoryRecursive(novelCoversDir, novelTarget);
        totalFiles += count;
        if (count > 0) totalDirs++;
        logger.info(TAG, `Copied ${count} novel cover files (legacy)`);
      }
      
      // 复制电子书封面
      const ebookCoversDir = `${filesDir}/ebook_covers`;
      logger.debug(TAG, `Ebook covers directory: ${ebookCoversDir}, exists: ${fs.accessSync(ebookCoversDir)}`);
      if (fs.accessSync(ebookCoversDir)) {
        const ebookTarget = `${coversDir}/ebook`;
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
   * 复制电子书文件（使用文件夹结构：每个电子书一个文件夹，包含文件本身和封面）
   * [重构] 与漫画保持一致的存储结构
   */
  private async copyEBookFiles(targetDir: string, ebookList: EBookBackupItem[]): Promise<void> {
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    const sandboxEbooksDir = `${this.sandboxManager.getDirectory('files')}/ebooks`;
    
    try {
      let copiedCount = 0;
      
      for (const ebook of ebookList) {
        try {
          // 跳过内置电子书
          if (ebook.title === '漫匣使用手册') {
            continue;
          }
          
          if (!ebook.filePath) {
            logger.warn(TAG, `电子书 ${ebook.title} 没有文件路径，跳过`);
            continue;
          }
          
          // [修复] 限制文件夹名长度，避免文件名过长导致截断
          const sanitizedTitle = ebook.title.replace(/[\\/:*?"<>|]/g, '_').substring(0, 100);
          
          // 创建电子书专属文件夹
          const ebookFolderPath = `${targetDir}/${sanitizedTitle}`;
          if (!fs.accessSync(ebookFolderPath)) {
            fs.mkdirSync(ebookFolderPath, true);
          }
          
          // [修复] 保留原始文件名，而不是使用书名作为文件名
          const originalFileName = ebook.filePath.split('/').pop() || '';
          // 如果原始文件名存在且合理，使用原始文件名；否则使用书名
          let newFileName = originalFileName;
          if (!newFileName || newFileName.length < 5) {
            const ext = originalFileName.includes('.') ? originalFileName.substring(originalFileName.lastIndexOf('.')) : '.epub';
            newFileName = `${sanitizedTitle}${ext}`;
          }
          
          // 复制电子书文件
          const sourcePath = ebook.filePath;
          const targetFilePath = `${ebookFolderPath}/${newFileName}`;
          
          if (fs.accessSync(sourcePath)) {
            await fs.copyFile(sourcePath, targetFilePath);
            logger.debug(TAG, `已复制电子书文件: ${newFileName}`);
          } else {
            // 尝试在Download目录查找
            if (downloadDirPath) {
              const downloadPath = `${downloadDirPath}/ebooks/${originalFileName}`;
              if (fs.accessSync(downloadPath)) {
                await fs.copyFile(downloadPath, targetFilePath);
                logger.debug(TAG, `已从Download复制电子书文件: ${newFileName}`);
              } else {
                logger.warn(TAG, `电子书文件未找到: ${sourcePath}`);
                continue;
              }
            } else {
              logger.warn(TAG, `电子书文件未找到: ${sourcePath}`);
              continue;
            }
          }
          
          // 复制封面图片
          if (ebook.coverPath && fs.accessSync(ebook.coverPath)) {
            const coverExt = ebook.coverPath.includes('.') ? ebook.coverPath.substring(ebook.coverPath.lastIndexOf('.')) : '.jpg';
            const coverTargetPath = `${ebookFolderPath}/cover${coverExt}`;
            await fs.copyFile(ebook.coverPath, coverTargetPath);
            logger.debug(TAG, `已复制电子书封面: cover${coverExt}`);
          }
          
          // [重构] 生成metadata.xml元数据文件
          await this.generateEBookMetadataXml(ebook, ebookFolderPath);
          
          copiedCount++;
        } catch (error) {
          logger.error(TAG, `复制电子书失败 ${ebook.title}: ${String(error)}`);
        }
      }
      
      logger.info(TAG, `已复制 ${copiedCount} 本电子书（文件夹结构）`);
    } catch (error) {
      logger.error(TAG, `复制电子书文件失败: ${error}`);
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
   * [修复] 每个恢复操作独立try-catch，确保一个失败不会影响其他操作（特别是字体恢复）
   */
  private async restoreMediaFiles(tempDir: string): Promise<void> {
    logger.info(TAG, 'Restoring media files...');
    
    // [修复] 首先列出临时目录内容，用于调试
    let tempContents: string[] = [];
    try {
      tempContents = fs.listFileSync(tempDir);
      logger.info(TAG, `临时目录内容: ${tempContents.join(', ')}`);
    } catch (e) {
      logger.warn(TAG, `无法列出临时目录: ${e}`);
    }
    
    // [修复] 优先恢复字体文件（关键功能，放在最前面确保执行）
    const fontsDir = `${tempDir}/fonts`;
    const hasFontsDir = tempContents.includes('fonts');
    logger.info(TAG, `临时目录是否包含fonts: ${hasFontsDir}`);
    
    if (hasFontsDir) {
      try {
        logger.info(TAG, `开始恢复字体文件，源目录: ${fontsDir}`);
        await this.restoreCustomFonts(fontsDir);
      } catch (fontError) {
        logger.error(TAG, `恢复字体文件失败: ${fontError}`);
      }
    } else {
      // 尝试使用accessSync检查
      try {
        const fontsDirExists = fs.accessSync(fontsDir);
        logger.info(TAG, `accessSync检查字体目录: ${fontsDir}, 存在: ${fontsDirExists}`);
        if (fontsDirExists) {
          await this.restoreCustomFonts(fontsDir);
        }
      } catch (accessError) {
        logger.warn(TAG, `字体目录不存在或无法访问: ${fontsDir}`);
      }
    }
    
    // [修复] 恢复漫画（独立try-catch）
    try {
      const mangaDir = `${tempDir}/manga`;
      if (fs.accessSync(mangaDir)) {
        await this.restoreMangaFromBackup(mangaDir);
      }
    } catch (mangaError) {
      logger.error(TAG, `恢复漫画失败: ${mangaError}`);
    }
    
    // [修复] 恢复封面（独立try-catch）
    try {
      const coversDir = `${tempDir}/covers`;
      if (fs.accessSync(coversDir)) {
        await this.restoreCoverImages(coversDir);
        await this.restoreMangaSourceCovers(coversDir);
      }
    } catch (coversError) {
      logger.error(TAG, `恢复封面失败: ${coversError}`);
    }
    
    // [修复] 恢复章节图片（独立try-catch）
    try {
      const chaptersDir = `${tempDir}/chapters`;
      if (fs.accessSync(chaptersDir)) {
        await this.restoreChapterImages(chaptersDir);
      }
    } catch (chaptersError) {
      logger.error(TAG, `恢复章节图片失败: ${chaptersError}`);
    }
    
    // [修复] 恢复电子书（独立try-catch）
    try {
      const ebooksDir = `${tempDir}/ebooks`;
      if (fs.accessSync(ebooksDir)) {
        await this.restoreEBookFiles(ebooksDir);
      }
    } catch (ebooksError) {
      logger.error(TAG, `恢复电子书失败: ${ebooksError}`);
    }
    
    // [修复] 恢复书源文件（独立try-catch）
    try {
      const legadoDir = `${tempDir}/legadoextensions`;
      if (fs.accessSync(legadoDir)) {
        await this.restoreNovelSourcesFromFiles(legadoDir);
      }
    } catch (legadoError) {
      logger.error(TAG, `恢复书源文件失败: ${legadoError}`);
    }
    
    // [修复] 恢复图源icon文件（独立try-catch）
    try {
      const iconsDir = `${tempDir}/icons`;
      if (fs.accessSync(iconsDir)) {
        await this.restoreSourceIcons(iconsDir);
      }
    } catch (iconsError) {
      logger.error(TAG, `恢复图源icon失败: ${iconsError}`);
    }
    
    logger.info(TAG, 'Media files restored successfully');
  }
  
  /**
   * 恢复图源icon文件
   */
  private async restoreSourceIcons(iconsDir: string): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    const targetDir = `${filesDir}/extensions-source/icons`;
    
    // 确保目标目录存在
    const parentDir = `${filesDir}/extensions-source`;
    if (!fs.accessSync(parentDir)) {
      fs.mkdirSync(parentDir, true);
    }
    if (!fs.accessSync(targetDir)) {
      fs.mkdirSync(targetDir, true);
    }
    
    try {
      const count = await this.copyDirectoryRecursive(iconsDir, targetDir);
      logger.info(TAG, `图源icon恢复完成: ${count} 个文件`);
    } catch (error) {
      logger.error(TAG, `恢复图源icon失败: ${error}`);
    }
  }
  
  /**
   * 恢复自定义字体文件
   * [修复] 增强日志和错误处理
   */
  private async restoreCustomFonts(fontsDir: string): Promise<void> {
    logger.info(TAG, `========== 开始恢复自定义字体 ==========`);
    logger.info(TAG, `字体源目录: ${fontsDir}`);
    
    const filesDir = this.sandboxManager.getDirectory('files');
    const targetDir = `${filesDir}/custom_fonts`;
    
    logger.info(TAG, `字体目标目录: ${targetDir}`);
    
    // 确保目标目录存在
    try {
      if (!fs.accessSync(targetDir)) {
        fs.mkdirSync(targetDir, true);
        logger.info(TAG, `已创建字体目标目录`);
      } else {
        logger.info(TAG, `字体目标目录已存在`);
      }
    } catch (mkdirError) {
      logger.error(TAG, `创建字体目标目录失败: ${mkdirError}`);
      return;
    }
    
    // 检查源目录是否存在
    try {
      if (!fs.accessSync(fontsDir)) {
        logger.warn(TAG, `字体源目录不存在: ${fontsDir}`);
        return;
      }
    } catch (accessError) {
      logger.error(TAG, `检查字体源目录失败: ${accessError}`);
      return;
    }
    
    // 列出源目录中的文件
    let sourceFiles: string[] = [];
    try {
      sourceFiles = fs.listFileSync(fontsDir);
      logger.info(TAG, `源目录中的字体文件(${sourceFiles.length}个): ${sourceFiles.join(', ') || '空'}`);
    } catch (e) {
      logger.error(TAG, `无法列出源目录文件: ${e}`);
      return;
    }
    
    if (sourceFiles.length === 0) {
      logger.warn(TAG, `字体源目录为空，无文件可恢复`);
      return;
    }
    
    // 逐个复制字体文件
    let copiedCount = 0;
    for (const fileName of sourceFiles) {
      const sourcePath = `${fontsDir}/${fileName}`;
      const targetPath = `${targetDir}/${fileName}`;
      
      try {
        // 检查是否是文件
        const stat = fs.statSync(sourcePath);
        if (stat.isDirectory()) {
          logger.debug(TAG, `跳过目录: ${fileName}`);
          continue;
        }
        
        logger.info(TAG, `正在复制: ${sourcePath} -> ${targetPath}`);
        fs.copyFileSync(sourcePath, targetPath);
        
        // 验证复制成功
        if (fs.accessSync(targetPath)) {
          copiedCount++;
          logger.info(TAG, `✓ 已复制字体文件: ${fileName}`);
        } else {
          logger.error(TAG, `✗ 复制后文件不存在: ${targetPath}`);
        }
      } catch (copyError) {
        logger.error(TAG, `复制字体文件失败: ${fileName}, ${copyError}`);
      }
    }
    
    logger.info(TAG, `自定义字体恢复完成: ${copiedCount}/${sourceFiles.length} 个文件`);
    
    // 验证目标目录中的文件
    try {
      const targetFiles = fs.listFileSync(targetDir);
      logger.info(TAG, `[最终验证] 目标目录中的字体文件: ${targetFiles.join(', ') || '空'}`);
    } catch (e) {
      logger.warn(TAG, `无法列出目标目录文件: ${e}`);
    }
    
    logger.info(TAG, `========== 自定义字体恢复结束 ==========`);
  }
  
  /**
   * 恢复图源封面
   * 从备份的covers/{pkg}/目录恢复到沙盒的covers/{pkg}/目录
   */
  private async restoreMangaSourceCovers(coversDir: string): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    const targetCoversDir = `${filesDir}/covers`;
    
    if (!fs.accessSync(targetCoversDir)) {
      fs.mkdirSync(targetCoversDir, true);
    }
    
    let restoredCount = 0;
    
    try {
      const entries = fs.listFileSync(coversDir);
      for (const entry of entries) {
        const sourcePath = `${coversDir}/${entry}`;
        const stat = fs.statSync(sourcePath);
        
        // 跳过非目录项和特殊目录（manga, ebook, novel等）
        if (!stat.isDirectory()) continue;
        if (['manga', 'ebook', 'novel', 'download_import'].includes(entry)) continue;
        
        // 这是图源封面目录（以pkg命名）
        const targetDir = `${targetCoversDir}/${entry}`;
        if (!fs.accessSync(targetDir)) {
          fs.mkdirSync(targetDir, true);
        }
        
        const count = await this.copyDirectoryRecursive(sourcePath, targetDir);
        restoredCount += count;
        logger.debug(TAG, `已恢复图源封面: ${entry} (${count} 个文件)`);
      }
      
      logger.info(TAG, `图源封面恢复完成: ${restoredCount} 个文件`);
    } catch (error) {
      logger.error(TAG, `恢复图源封面失败: ${error}`);
    }
  }
  
  /**
   * 从legadoextensions目录恢复书源
   * 使用NovelSourceManager的导入流程
   */
  private async restoreNovelSourcesFromFiles(legadoDir: string): Promise<void> {
    let importedCount = 0;
    let failedCount = 0;
    
    try {
      const files = fs.listFileSync(legadoDir);
      
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        
        const filePath = `${legadoDir}/${file}`;
        
        try {
          // 读取JSON文件
          const content = fs.readTextSync(filePath);
          
          // 使用NovelSourceManager导入
          const novelSourceModule = await import('../Novel/NovelSourceManager');
          const sourceManager = novelSourceModule.NovelSourceManager.getInstance();
          const results = await sourceManager.importFromJSON(content, true);
          
          const successCount = results.filter((r: LegadoSourceImportResult) => r.success).length;
          importedCount += successCount;
          failedCount += results.length - successCount;
          
          logger.debug(TAG, `已导入书源文件: ${file} (成功: ${successCount})`);
        } catch (error) {
          failedCount++;
          logger.warn(TAG, `导入书源文件失败: ${file}, ${error}`);
        }
      }
      
      logger.info(TAG, `书源恢复完成: 成功 ${importedCount}, 失败 ${failedCount}`);
    } catch (error) {
      logger.error(TAG, `恢复书源失败: ${error}`);
    }
  }

  /**
   * 从备份根目录/manga恢复漫画（新格式）
   */
  private async restoreMangaFromBackup(mangaSource: string): Promise<void> {
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    
    if (!downloadDirPath) {
      logger.warn(TAG, 'Download目录未配置，跳过漫画恢复');
      return;
    }
    
    const downloadMangaTarget = `${downloadDirPath}/manga`;
    if (!fs.accessSync(downloadMangaTarget)) {
      fs.mkdirSync(downloadMangaTarget, true);
    }
    
    // 遍历备份中的漫画目录
    const sourceEntries = fs.listFileSync(mangaSource);
    for (const sourceEntry of sourceEntries) {
      const sourcePath = `${mangaSource}/${sourceEntry}`;
      const stat = fs.statSync(sourcePath);
      
      if (stat.isDirectory()) {
        if (sourceEntry === 'download_import') {
          // download_import下的漫画恢复到Download/漫匣/manga目录
          const importEntries = fs.listFileSync(sourcePath);
          for (const importEntry of importEntries) {
            const importPath = `${sourcePath}/${importEntry}`;
            const importStat = fs.statSync(importPath);
            if (importStat.isDirectory()) {
              const targetPath = `${downloadMangaTarget}/${importEntry}`;
              if (!fs.accessSync(targetPath)) {
                fs.mkdirSync(targetPath, true);
              }
              await this.copyDirectoryRecursive(importPath, targetPath);
              logger.info(TAG, `已恢复漫画: ${importEntry}`);
            }
          }
        } else {
          // 其他源的漫画
          const targetPath = `${downloadMangaTarget}/${sourceEntry}`;
          if (!fs.accessSync(targetPath)) {
            fs.mkdirSync(targetPath, true);
          }
          await this.copyDirectoryRecursive(sourcePath, targetPath);
          logger.info(TAG, `已恢复漫画: ${sourceEntry}`);
        }
      }
    }
    logger.info(TAG, '漫画恢复完成');
  }

  /**
   * 恢复封面图片
   * [重构] 使用Download同步模式，将漫画文件恢复到Download/漫匹/manga目录
   */
  private async restoreCoverImages(sourceDir: string): Promise<void> {
    const filesDir = this.sandboxManager.getDirectory('files');
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    
    try {
      // 恢复漫画封面和章节图片
      const mangaSource = `${sourceDir}/manga`;
      if (fs.accessSync(mangaSource)) {
        // [重构] 优先恢复到Download/漫匹/manga目录（Download同步模式）
        if (downloadDirPath) {
          const downloadMangaTarget = `${downloadDirPath}/manga`;
          if (!fs.accessSync(downloadMangaTarget)) {
            fs.mkdirSync(downloadMangaTarget, true);
          }
          
          // 遍历备份中的漫画目录
          const sourceEntries = fs.listFileSync(mangaSource);
          for (const sourceEntry of sourceEntries) {
            const sourcePath = `${mangaSource}/${sourceEntry}`;
            const stat = fs.statSync(sourcePath);
            
            if (stat.isDirectory()) {
              // 检查是否为download_import目录
              if (sourceEntry === 'download_import') {
                // download_import下的漫画恢复到Download/漫匣/manga目录
                const importEntries = fs.listFileSync(sourcePath);
                for (const importEntry of importEntries) {
                  const importPath = `${sourcePath}/${importEntry}`;
                  const importStat = fs.statSync(importPath);
                  if (importStat.isDirectory()) {
                    const targetPath = `${downloadMangaTarget}/${importEntry}`;
                    if (!fs.accessSync(targetPath)) {
                      fs.mkdirSync(targetPath, true);
                    }
                    await this.copyDirectoryRecursive(importPath, targetPath);
                    logger.info(TAG, `已恢复Download漫画: ${importEntry}`);
                  }
                }
              } else {
                // 其他源的漫画恢复到Download/漫匣/manga目录
                const targetPath = `${downloadMangaTarget}/${sourceEntry}`;
                if (!fs.accessSync(targetPath)) {
                  fs.mkdirSync(targetPath, true);
                }
                await this.copyDirectoryRecursive(sourcePath, targetPath);
                logger.info(TAG, `Restored manga source: ${sourceEntry}`);
              }
            }
          }
          logger.info(TAG, 'Restored manga covers to Download sync folder');
        } else {
          // 回退：恢复到沙盒comics目录
          const mangaTarget = this.sandboxManager.getDirectory('comics');
          if (!fs.accessSync(mangaTarget)) {
            fs.mkdirSync(mangaTarget, true);
          }
          await this.copyDirectoryRecursive(mangaSource, mangaTarget);
          logger.info(TAG, 'Restored manga covers to sandbox');
        }
      }
      
      // 恢复小说封面（优先使用Download目录）
      const novelSource = `${sourceDir}/novel`;
      if (fs.accessSync(novelSource)) {
        let novelTarget: string;
        if (downloadDirPath) {
          novelTarget = `${downloadDirPath}/novel`;
        } else {
          novelTarget = `${filesDir}/novel_covers`;
        }
        if (!fs.accessSync(novelTarget)) {
          fs.mkdirSync(novelTarget, true);
        }
        await this.copyDirectoryRecursive(novelSource, novelTarget);
        logger.info(TAG, `已恢复小说封面到: ${novelTarget}`);
      }
      
      // 电子书封面已在restoreEBookFiles中处理（文件夹结构）
      // 这里只处理旧格式的电子书封面
      const ebookSource = `${sourceDir}/ebook`;
      if (fs.accessSync(ebookSource)) {
        const ebookTarget = `${filesDir}/ebook_covers`;
        if (!fs.accessSync(ebookTarget)) {
          fs.mkdirSync(ebookTarget, true);
        }
        await this.copyDirectoryRecursive(ebookSource, ebookTarget);
        logger.info(TAG, '已恢复电子书封面（旧格式）');
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
   * [重构] 使用文件夹结构，每个电子书一个文件夹，包含文件本身和封面
   */
  private async restoreEBookFiles(sourceDir: string): Promise<void> {
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    
    // 确定目标目录
    let targetBaseDir: string;
    if (downloadDirPath) {
      targetBaseDir = `${downloadDirPath}/ebooks`;
    } else {
      targetBaseDir = `${this.sandboxManager.getDirectory('files')}/ebooks`;
    }
    
    if (!fs.accessSync(targetBaseDir)) {
      fs.mkdirSync(targetBaseDir, true);
    }
    
    try {
      // 检查备份中的电子书结构
      const entries = fs.listFileSync(sourceDir);
      
      for (const entry of entries) {
        const sourcePath = `${sourceDir}/${entry}`;
        const stat = fs.statSync(sourcePath);
        
        if (stat.isDirectory()) {
          // 新的文件夹结构：每个电子书一个文件夹
          const targetFolderPath = `${targetBaseDir}/${entry}`;
          if (!fs.accessSync(targetFolderPath)) {
            fs.mkdirSync(targetFolderPath, true);
          }
          await this.copyDirectoryRecursive(sourcePath, targetFolderPath);
          logger.info(TAG, `已恢复电子书文件夹: ${entry}`);
        } else {
          // 旧的单文件结构：直接复制文件
          const targetFilePath = `${targetBaseDir}/${entry}`;
          fs.copyFileSync(sourcePath, targetFilePath);
          logger.info(TAG, `已恢复电子书文件: ${entry}`);
        }
      }
      
      logger.info(TAG, `电子书文件恢复完成，目标目录: ${targetBaseDir}`);
    } catch (error) {
      logger.error(TAG, `恢复电子书文件失败: ${error}`);
    }
  }

  /**
   * 恢复漫画库
   */
  private async restoreMangaLibrary(items: MangaBackupItem[]): Promise<void> {
    logger.info(TAG, `正在恢复漫画库: ${items.length} 项`);
    
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    
    for (const item of items) {
      try {
        const now = Date.now();
        
        // [修复] 计算新的封面路径
        let newCoverLocalPath = item.coverLocalPath || '';
        const sanitizedTitle = item.title.replace(/[\\/:*?"<>|]/g, '_');
        
        // 尝试多种方式找到封面路径
        if (downloadDirPath) {
          const coverFormats = ['jpg', 'jpeg', 'png', 'webp'];
          let foundCover = false;
          
          // 方式1：检查manga子目录
          for (const ext of coverFormats) {
            const testPath = `${downloadDirPath}/manga/${sanitizedTitle}/cover.${ext}`;
            if (fs.accessSync(testPath)) {
              newCoverLocalPath = testPath;
              foundCover = true;
              break;
            }
          }
          
          // 方式2：检查根目录（旧格式）
          if (!foundCover) {
            for (const ext of coverFormats) {
              const testPath = `${downloadDirPath}/${sanitizedTitle}/cover.${ext}`;
              if (fs.accessSync(testPath)) {
                newCoverLocalPath = testPath;
                foundCover = true;
                break;
              }
            }
          }
          
          // 方式3：检查漫画目录下的第一张图片作为封面
          if (!foundCover) {
            const mangaDir = `${downloadDirPath}/manga/${sanitizedTitle}`;
            if (fs.accessSync(mangaDir)) {
              try {
                const files = fs.listFileSync(mangaDir);
                for (const file of files) {
                  const lowerFile = file.toLowerCase();
                  if (lowerFile.endsWith('.jpg') || lowerFile.endsWith('.jpeg') || 
                      lowerFile.endsWith('.png') || lowerFile.endsWith('.webp')) {
                    newCoverLocalPath = `${mangaDir}/${file}`;
                    foundCover = true;
                    break;
                  }
                }
              } catch (e) {
                // 忽略错误
              }
            }
          }
          
          if (foundCover) {
            logger.debug(TAG, `漫画封面路径更新: ${item.coverLocalPath} -> ${newCoverLocalPath}`);
          }
        }
        
        // [修复] 使用正确的数据库字段名，添加必需的时间字段
        const sqlManga = `INSERT OR REPLACE INTO comic_info (
          id, sourceId, externalId, title, author, description, coverUrl, coverLocalPath, 
          status, tags, categories, lastUpdateTime, addTime, createTime, updateTime,
          webUrl, apiUrl, contentType, isNSFW, isPrivate
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
        
        await this.dbManager.executeSql(sqlManga, [
          item.id, 
          item.sourceId, 
          item.externalId || item.id,
          item.title,
          item.author || '',
          item.description || '',
          item.coverUrl || '',
          newCoverLocalPath,
          item.status || 'unknown',
          JSON.stringify(item.genre || []),
          JSON.stringify(item.categories || []),
          item.lastUpdateTime || now,
          item.dateAdded || now,
          now,
          now,
          item.webUrl || '',
          item.apiUrl || '',
          item.contentType || 'manga',
          item.isNSFW ? 1 : 0,
          item.isPrivate ? 1 : 0
        ]);
        
        for (const chapter of item.chapters) {
          // [修复] 添加下载相关字段和必需的时间字段
          const now = Date.now();
          
          // [修复] 计算新的章节下载路径
          let newDownloadPath = chapter.downloadPath || '';
          if (chapter.isDownloaded && downloadDirPath) {
            // 从旧路径或章节标题中提取章节目录名
            const oldPath = chapter.downloadPath || '';
            const pathParts = oldPath.split('/');
            // 优先使用路径中的最后一个目录名，如果没有则使用章节标题
            let chapterFolderName = pathParts.length > 0 ? pathParts[pathParts.length - 1] : '';
            if (!chapterFolderName || chapterFolderName === sanitizedTitle) {
              chapterFolderName = chapter.title.replace(/[\\/:*?"<>|]/g, '_');
            }
            
            // 漫画目录路径
            const mangaDir = `${downloadDirPath}/manga/${sanitizedTitle}`;
            
            if (chapterFolderName) {
              // 构建新路径：Download/漫匣/manga/漫画名/章节名
              newDownloadPath = `${mangaDir}/${chapterFolderName}`;
              
              // 验证新路径是否存在
              if (!fs.accessSync(newDownloadPath)) {
                // 如果新路径不存在，尝试在漫画目录下查找
                if (fs.accessSync(mangaDir)) {
                  try {
                    const files = fs.listFileSync(mangaDir);
                    // 查找匹配的章节目录
                    for (const file of files) {
                      if (file === chapterFolderName || file.includes(chapterFolderName)) {
                        newDownloadPath = `${mangaDir}/${file}`;
                        break;
                      }
                    }
                    // 如果还是找不到，使用漫画目录本身（适用于单章节漫画）
                    if (!fs.accessSync(newDownloadPath) && files.length > 0) {
                      // 检查是否有图片文件直接在漫画目录下
                      const hasImages = files.some(f => {
                        const lf = f.toLowerCase();
                        return lf.endsWith('.jpg') || lf.endsWith('.jpeg') || 
                               lf.endsWith('.png') || lf.endsWith('.webp');
                      });
                      if (hasImages) {
                        newDownloadPath = mangaDir;
                      }
                    }
                  } catch (e) {
                    // 忽略错误
                  }
                }
              }
              
              logger.info(TAG, `章节路径更新: ${chapter.title}, 旧=${oldPath}, 新=${newDownloadPath}, 存在=${fs.accessSync(newDownloadPath)}`);
            }
          }
          
          const sqlChapter = 'INSERT OR REPLACE INTO chapter (id, comicId, externalId, title, chapterNumber, url, pageCount, isDownloaded, downloadPath, fileSize, publishTime, addTime, createTime, updateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
          
          await this.dbManager.executeSql(sqlChapter, [
            chapter.id, 
            item.id, 
            chapter.externalId || chapter.id, 
            chapter.title, 
            chapter.chapterNumber,
            chapter.url || '',
            chapter.pageCount || 0, 
            chapter.isDownloaded ? 1 : 0, 
            newDownloadPath, 
            chapter.fileSize || 0,
            chapter.uploadDate || now,
            chapter.dateFetch || now,
            now,
            now
          ]);
          
          // [修复] 恢复章节的页面数据
          logger.info(TAG, `章节 ${chapter.title} 页面数据: ${chapter.pages ? chapter.pages.length : 'undefined'}`);
          if (chapter.pages && chapter.pages.length > 0) {
            for (const page of chapter.pages) {
              // 计算新的本地路径
              let newLocalPath = page.localPath || '';
              if (newDownloadPath && page.localPath) {
                // 从旧路径提取文件名
                const fileName = page.localPath.split('/').pop() || '';
                if (fileName) {
                  newLocalPath = `${newDownloadPath}/${fileName}`;
                }
              }
              
              const pageSql = 'INSERT OR REPLACE INTO page (id, chapterId, pageNumber, imageUrl, localPath, width, height, fileSize, isDownloaded, createTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
              await this.dbManager.executeSql(pageSql, [
                page.id,
                page.chapterId,
                page.pageNumber,
                page.imageUrl || '',
                newLocalPath,
                page.width || 0,
                page.height || 0,
                page.fileSize || 0,
                page.isDownloaded || 1,
                page.createTime || Date.now()
              ]);
            }
            logger.info(TAG, `恢复章节页面数据: ${chapter.title}, ${chapter.pages.length}页`);
          }
        }
        
        // [修复] 恢复漫画的阅读进度到read_history表
        if (item.lastReadChapterId && item.lastReadPage !== undefined && item.lastReadPage > 0) {
          try {
            const readHistorySql = 'INSERT OR REPLACE INTO read_history (comicId, chapterId, userId, pageNumber, readTime, duration, createTime) VALUES (?, ?, ?, ?, ?, ?, ?)';
            await this.dbManager.executeSql(readHistorySql, [
              item.id,
              item.lastReadChapterId,
              'default_user',
              item.lastReadPage,
              item.lastReadTime || Date.now(),
              0,
              Date.now()
            ]);
            logger.info(TAG, `恢复阅读进度: ${item.title}, chapter=${item.lastReadChapterId}, page=${item.lastReadPage}`);
          } catch (e) {
            logger.error(TAG, `恢复阅读进度失败: ${item.title}, ${e}`);
          }
        }
        
        // [修复] 恢复收藏状态到favorite表
        if (item.isFavorite) {
          try {
            const favoriteSql = 'INSERT OR REPLACE INTO favorite (comicId, userId, folderName, addTime, lastReadTime) VALUES (?, ?, ?, ?, ?)';
            await this.dbManager.executeSql(favoriteSql, [
              item.id,
              'default_user',
              'default',
              item.dateAdded || Date.now(),
              item.lastReadTime || Date.now()
            ]);
            logger.info(TAG, `恢复收藏状态: ${item.title}`);
          } catch (e) {
            logger.error(TAG, `恢复收藏状态失败: ${item.title}, ${e}`);
          }
        }
      } catch (error) {
        logger.error(TAG, `Failed to restore manga: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Manga library restore completed');
  }

  /**
   * 恢复小说库
   * [重构] 使用文件夹结构，更新封面路径
   */
  private async restoreNovelLibrary(items: NovelBackupItem[]): Promise<void> {
    logger.info(TAG, `正在恢复小说库: ${items.length} 项`);
    
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    const baseDir = downloadDirPath ? `${downloadDirPath}/novel` : `${this.sandboxManager.getDirectory('files')}/novel`;
    
    for (const item of items) {
      try {
        const sanitizedName = item.name.replace(/[\\/:*?"<>|]/g, '_');
        
        // [重构] 计算新的封面路径
        let newCoverLocalPath = item.coverLocalPath || '';
        
        // 尝试多种方式找到封面路径
        if (downloadDirPath) {
          const coverFormats = ['jpg', 'jpeg', 'png', 'webp'];
          let foundCover = false;
          
          // 方式1：检查novel子目录
          const novelFolderPath = `${baseDir}/${sanitizedName}`;
          if (fs.accessSync(novelFolderPath)) {
            for (const ext of coverFormats) {
              const testPath = `${novelFolderPath}/cover.${ext}`;
              if (fs.accessSync(testPath)) {
                newCoverLocalPath = testPath;
                foundCover = true;
                break;
              }
            }
          }
          
          // 方式2：检查沙箱novel_covers目录
          if (!foundCover) {
            const sandboxNovelCovers = `${this.sandboxManager.getDirectory('files')}/novel_covers`;
            for (const ext of coverFormats) {
              const testPath = `${sandboxNovelCovers}/${sanitizedName}.${ext}`;
              if (fs.accessSync(testPath)) {
                newCoverLocalPath = testPath;
                foundCover = true;
                break;
              }
            }
          }
          
          if (foundCover) {
            logger.debug(TAG, `小说封面路径更新: ${item.coverLocalPath} -> ${newCoverLocalPath}`);
          }
        }
        
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
          coverLocalPath: newCoverLocalPath,
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
        logger.info(TAG, `已恢复小说: ${item.name}`);
      } catch (error) {
        logger.error(TAG, `恢复小说失败: ${item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, '小说库恢复完成');
  }

  /**
   * 恢复电子书库
   * [重构] 使用文件夹结构，更新文件路径和封面路径
   */
  private async restoreEBookLibrary(items: EBookBackupItem[]): Promise<void> {
    logger.info(TAG, `正在恢复电子书库: ${items.length} 项`);
    
    const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
    const sandboxEbooksDir = `${this.sandboxManager.getDirectory('files')}/ebooks`;
    
    // 确定基础目录
    const baseDir = downloadDirPath ? `${downloadDirPath}/ebooks` : sandboxEbooksDir;
    
    for (const item of items) {
      // 跳过内置电子书
      if (item.title === '漫匣使用手册') {
        logger.info(TAG, '跳过内置电子书: 漫匣使用手册');
        continue;
      }
      try {
        // [修复] 限制文件夹名长度，与备份时保持一致
        const sanitizedTitle = item.title.replace(/[\\/:*?"<>|]/g, '_').substring(0, 100);
        
        // [重构] 使用文件夹结构计算新路径
        const ebookFolderPath = `${baseDir}/${sanitizedTitle}`;
        
        // [修复] 优先使用原始文件名，与备份时保持一致
        const originalFileName = item.filePath ? item.filePath.split('/').pop() || '' : '';
        // 新的文件路径：优先查找原始文件名，其次查找文件夹中的电子书文件
        let newFilePath = '';
        
        // [修复] 在文件夹中查找电子书文件
        if (fs.accessSync(ebookFolderPath)) {
          try {
            const files = fs.listFileSync(ebookFolderPath);
            // 优先查找原始文件名
            if (originalFileName && files.includes(originalFileName)) {
              newFilePath = `${ebookFolderPath}/${originalFileName}`;
              logger.info(TAG, `找到原始电子书文件: ${newFilePath}`);
            } else {
              // 查找任何电子书文件
              for (const file of files) {
                const lowerFile = file.toLowerCase();
                if (lowerFile.endsWith('.epub') || lowerFile.endsWith('.pdf') || 
                    lowerFile.endsWith('.txt') || lowerFile.endsWith('.mobi')) {
                  newFilePath = `${ebookFolderPath}/${file}`;
                  logger.info(TAG, `找到电子书文件: ${newFilePath}`);
                  break;
                }
              }
            }
          } catch (e) {
            logger.warn(TAG, `查找电子书文件失败: ${e}`);
          }
        }
        
        logger.debug(TAG, `电子书恢复: ${item.title}, 基础目录=${baseDir}, 文件路径=${newFilePath}, 文件存在=${fs.accessSync(newFilePath)}`);
        
        // 新的封面路径：/ebooks/书名/cover.xxx 或 cover_时间戳.xxx
        let newCoverPath = '';
        if (fs.accessSync(ebookFolderPath)) {
          // 检查封面文件是否存在
          const coverFormats = ['jpg', 'jpeg', 'png', 'webp'];
          // 方式1：检查标准封面文件名
          for (const coverExt of coverFormats) {
            const testPath = `${ebookFolderPath}/cover.${coverExt}`;
            if (fs.accessSync(testPath)) {
              newCoverPath = testPath;
              break;
            }
          }
          // 方式2：检查带时间戳的封面文件名（cover_时间戳.xxx）
          if (!newCoverPath) {
            try {
              const files = fs.listFileSync(ebookFolderPath);
              for (const file of files) {
                if (file.startsWith('cover_') || file.startsWith('cover.')) {
                  const lowerFile = file.toLowerCase();
                  if (lowerFile.endsWith('.jpg') || lowerFile.endsWith('.jpeg') || 
                      lowerFile.endsWith('.png') || lowerFile.endsWith('.webp')) {
                    newCoverPath = `${ebookFolderPath}/${file}`;
                    break;
                  }
                }
              }
            } catch (e) {
              // 忽略错误
            }
          }
        }
        
        // 方式3：检查沙盒封面目录
        if (!newCoverPath) {
          const sandboxCoverDir = `${this.sandboxManager.getDirectory('files')}/ebook_covers`;
          if (fs.accessSync(sandboxCoverDir)) {
            try {
              const files = fs.listFileSync(sandboxCoverDir);
              for (const file of files) {
                const lowerFile = file.toLowerCase();
                if (lowerFile.endsWith('.jpg') || lowerFile.endsWith('.jpeg') || 
                    lowerFile.endsWith('.png') || lowerFile.endsWith('.webp')) {
                  // 使用第一个找到的封面（可能需要更精确的匹配）
                  newCoverPath = `${sandboxCoverDir}/${file}`;
                  break;
                }
              }
            } catch (e) {
              // 忽略错误
            }
          }
        }
        
        logger.debug(TAG, `电子书路径更新: 文件=${newFilePath}, 封面=${newCoverPath}`);
        
        // [修复] 使用正确的表结构字段
        const now = Date.now();
        const sql = 'INSERT OR REPLACE INTO ebook_info (id, format, filePath, fileSize, title, author, publisher, publishDate, isbn, language, description, coverImagePath, totalWordCount, addTime, lastUpdateTime, isFavorite, isPrivate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.id, 
          item.format, 
          newFilePath, 
          item.fileSize || 0,
          item.title, 
          item.author || '', 
          item.publisher || '',
          item.publishDate || '', 
          item.isbn || '', 
          item.language || 'zh-CN', 
          item.description || '',
          newCoverPath, 
          item.totalWordCount || 0,
          now,
          item.lastUpdateTime || now,
          item.isFavorite ? 1 : 0,
          item.isPrivate ? 1 : 0
        ]);
        
        // [修复] 恢复电子书阅读进度到ebook_reading_progress表（包含关键字段）
        const itemObj = item as Object;
        const chapterIndex = Number((itemObj as Record<string, number>)['currentChapterIndex'] || 0);
        const domPosVal = String((itemObj as Record<string, string>)['domPos'] || '');
        const chapterIdVal = String((itemObj as Record<string, string>)['currentChapterId'] || '');
        if (item.currentPage > 0 || item.readProgress > 0 || chapterIndex > 0 || domPosVal.length > 0) {
          try {
            const progressSql = 'INSERT OR REPLACE INTO ebook_reading_progress (bookId, userId, currentChapterId, currentChapterIndex, currentPosition, domPos, progress, lastReadTime, totalReadingTime, createTime, updateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
            await this.dbManager.executeSql(progressSql, [
              item.id, 'default_user', chapterIdVal, chapterIndex, item.currentPage || 0, domPosVal,
              item.readProgress || 0, item.lastReadTime || now, 0, now, now
            ]);
            logger.info(TAG, `恢复电子书阅读进度: ${item.title}, chapterIndex=${chapterIndex}, domPos长度=${domPosVal.length}`);
          } catch (e) {
            logger.error(TAG, `恢复电子书阅读进度失败: ${item.title}, ${e}`);
          }
        }
        
        // [新增] 恢复电子书阅读设置到ebook_reading_settings表
        const settingsObj = (itemObj as Record<string, Object>)['readingSettings'];
        if (settingsObj) {
          try {
            const s = settingsObj as Record<string, string | number>;
            const settingsSql = `INSERT OR REPLACE INTO ebook_reading_settings (
              bookId, userId, fontSize, fontFamily, fontPath, fontWeight, lineHeight, backgroundColor, textColor,
              themeBgImage, nightMode, followSystemTheme, pageMargin, pageMode, brightness, autoSave, saveInterval,
              letterSpacing, paragraphSpacing, firstLineIndent, textAlignment, pageTurnAnimation, tapToTurn,
              volumeKeyNavigation, keepScreenOn, showPageNumber, showProgress, showTime, showBattery,
              backgroundType, backgroundImagePath, backgroundImageOpacity, createTime, updateTime
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
            await this.dbManager.executeSql(settingsSql, [
              item.id, 'default_user',
              s['fontSize'] || 18, s['fontFamily'] || 'HarmonyOS Sans', s['fontPath'] || '', s['fontWeight'] || 400,
              s['lineHeight'] || 1.5, s['backgroundColor'] || '#FFFFFF', s['textColor'] || '#000000',
              s['themeBgImage'] || '', s['nightMode'] || 0, s['followSystemTheme'] || 1,
              s['pageMargin'] || 16, s['pageMode'] || '0', s['brightness'] || 100,
              s['autoSave'] || 1, s['saveInterval'] || 30, s['letterSpacing'] || 0,
              s['paragraphSpacing'] || 8, s['firstLineIndent'] || 2, s['textAlignment'] || 'JUSTIFY',
              s['pageTurnAnimation'] || 'SLIDE', s['tapToTurn'] || 1, s['volumeKeyNavigation'] || 1,
              s['keepScreenOn'] || 0, s['showPageNumber'] || 1, s['showProgress'] || 0,
              s['showTime'] || 1, s['showBattery'] || 0, s['backgroundType'] || 'COLOR',
              s['backgroundImagePath'] || '', s['backgroundImageOpacity'] || 0.3, now, now
            ]);
            logger.info(TAG, `恢复电子书设置: ${item.title}`);
          } catch (e) {
            logger.error(TAG, `恢复电子书设置失败: ${item.title}, ${e}`);
          }
        }
        
        logger.info(TAG, `已恢复电子书: ${item.title}, 路径: ${newFilePath}`);
      } catch (error) {
        logger.error(TAG, `恢复电子书失败: ${item.title}, ${error}`);
      }
    }
    
    logger.info(TAG, '电子书库恢复完成');
  }

  /**
   * 导出漫画库
   * [修复] 从favorite表获取收藏状态和阅读进度，从read_history获取章节阅读状态
   */
  private async exportMangaLibrary(): Promise<MangaBackupItem[]> {
    try {
      const sql = 'SELECT * FROM comic_info';
      const results = await this.dbManager.querySql(sql);
      const backupItems: MangaBackupItem[] = [];
      
      for (const record of results) {
        const manga = record as Record<string, DatabaseRecord>;
        const mangaId = String(manga['id']);
        
        // [修复] 从favorite表获取收藏状态
        const favoriteSql = 'SELECT * FROM favorite WHERE comicId = ?';
        const favoriteResults = await this.dbManager.querySql(favoriteSql, [mangaId]);
        const isFavorite = favoriteResults.length > 0;
        
        // [修复] 从read_history表获取最新阅读进度（与阅读器和详情页保持一致）
        const readProgressSql = 'SELECT * FROM read_history WHERE comicId = ? ORDER BY readTime DESC LIMIT 1';
        const readProgressResults = await this.dbManager.querySql(readProgressSql, [mangaId]);
        let lastReadChapterId = '';
        let lastReadPageNumber = 0;
        let lastReadTime = 0;
        if (readProgressResults.length > 0) {
          const latestProgress = readProgressResults[0] as Record<string, DatabaseRecord>;
          lastReadChapterId = String(latestProgress['chapterId'] || '');
          lastReadPageNumber = Number(latestProgress['pageNumber'] || 0);
          lastReadTime = Number(latestProgress['readTime'] || 0);
        }
        logger.info(TAG, `漫画 ${manga['title']} 阅读进度: chapterId=${lastReadChapterId}, page=${lastReadPageNumber}`);
        
        // [修复] 获取所有已读章节ID（从read_history表）
        const readHistorySql = 'SELECT DISTINCT chapterId FROM read_history WHERE comicId = ?';
        const readHistoryResults = await this.dbManager.querySql(readHistorySql, [mangaId]);
        const readChapterIds = new Set(readHistoryResults.map(r => String((r as Record<string, DatabaseRecord>)['chapterId'])));
        
        const chaptersSql = 'SELECT * FROM chapter WHERE comicId = ?';
        const chaptersResults = await this.dbManager.querySql(chaptersSql, [mangaId]);
        const chapters: MangaChapterBackup[] = [];
        
        for (const chRec of chaptersResults) {
          const ch = chRec as Record<string, DatabaseRecord>;
          const chapterId = String(ch['id']);
          
          // [修复] 查询章节的页面数据
          const pagesSql = 'SELECT * FROM page WHERE chapterId = ? ORDER BY pageNumber ASC';
          const pagesResults = await this.dbManager.querySql(pagesSql, [chapterId]);
          const pages: MangaPageBackup[] = [];
          
          for (const pageRec of pagesResults) {
            const pg = pageRec as Record<string, DatabaseRecord>;
            pages.push({
              id: String(pg['id']),
              chapterId: String(pg['chapterId']),
              pageNumber: Number(pg['pageNumber'] || 0),
              imageUrl: String(pg['imageUrl'] || ''),
              localPath: String(pg['localPath'] || ''),
              width: Number(pg['width'] || 0),
              height: Number(pg['height'] || 0),
              fileSize: Number(pg['fileSize'] || 0),
              isDownloaded: Number(pg['isDownloaded'] || 0),
              createTime: Number(pg['createTime'] || Date.now())
            });
          }
          
          // [修复] 判断章节是否为当前阅读章节，获取lastPageRead
          const isCurrentReadChapter = chapterId === lastReadChapterId;
          const chapterLastPageRead = isCurrentReadChapter ? lastReadPageNumber : 0;
          
          chapters.push({
            id: chapterId,
            title: String(ch['title'] || ''),
            url: String(ch['url'] || ''),
            chapterNumber: String(ch['chapterNumber'] || '0'),
            scanlator: String(ch['scanlator'] || ''),
            uploadDate: Number(ch['uploadDate'] || 0),
            dateUploaded: Number(ch['dateUploaded'] || 0),
            chapterIndex: Number(ch['chapterIndex'] || 0),
            read: readChapterIds.has(chapterId),  // [修复] 从read_history判断是否已读
            bookmark: false,  // [修复] chapter表中没有bookmark字段
            lastPageRead: chapterLastPageRead,  // [修复] 从favorite表获取当前章节的阅读页码
            dateFetch: Number(ch['dateFetch'] || 0),
            sourceOrder: Number(ch['sourceOrder'] || 0),
            // [修复] 添加下载相关字段
            pageCount: Number(ch['pageCount'] || 0),
            isDownloaded: Boolean(ch['isDownloaded']),
            downloadPath: String(ch['downloadPath'] || ''),
            fileSize: Number(ch['fileSize'] || 0),
            externalId: String(ch['externalId'] || ''),
            // [修复] 添加页面数据
            pages: pages
          });
        }
        
        backupItems.push({
          id: mangaId,
          externalId: String(manga['externalId'] || ''),
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
          isFavorite: isFavorite,  // [修复] 从favorite表判断
          isPrivate: Boolean(manga['isPrivate']),
          isNSFW: Boolean(manga['isNSFW']),
          categories: [],
          lastUpdateTime: Number(manga['lastUpdateTime'] || 0),
          dateAdded: Number(manga['dateAdded'] || Date.now()),
          chapters: chapters,
          lastReadChapterId: lastReadChapterId,  // [修复] 从favorite表获取
          lastReadChapterIndex: 0,  // comic_info表中没有此字段
          lastReadPage: lastReadPageNumber,  // [修复] 从favorite表获取
          lastReadTime: lastReadTime,  // [修复] 从favorite表获取
          // [修复] 添加contentType等字段，支持Download同步导入的内容
          contentType: String(manga['contentType'] || 'manga'),
          webUrl: String(manga['webUrl'] || ''),
          apiUrl: String(manga['apiUrl'] || '')
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
   * 导出小说库（包含所有书籍，不仅仅是收藏）
   */
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
  
  /**
   * 导出小说库（旧方法，仅收藏）
   * @deprecated 使用 exportNovelLibrary 代替
   */
  private async exportNovelLibraryFavoritesOnly(): Promise<NovelBackupItem[]> {
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
   * [修复] 从ebook_reading_progress表获取阅读进度
   */
  private async exportEBookLibrary(): Promise<EBookBackupItem[]> {
    try {
      const sql = 'SELECT * FROM ebook_info WHERE title != ?';
      const results = await this.dbManager.querySql(sql, ['漫匣使用手册']);
      const backupItems: EBookBackupItem[] = [];
      
      for (const record of results) {
        const ebook = record as Record<string, DatabaseRecord>;
        const bookId = String(ebook['id']);
        
        // [修复] 从ebook_reading_progress表获取阅读进度（包含关键字段）
        const progressSql = 'SELECT * FROM ebook_reading_progress WHERE bookId = ? ORDER BY lastReadTime DESC LIMIT 1';
        const progressResults = await this.dbManager.querySql(progressSql, [bookId]);
        let currentPage = 0;
        let readProgress = 0;
        let lastReadTime = 0;
        let currentChapterIndex = 0;
        let domPos = '';
        let currentChapterId = '';
        if (progressResults.length > 0) {
          const progress = progressResults[0] as Record<string, DatabaseRecord>;
          currentPage = Number(progress['currentPosition'] || 0);
          readProgress = Number(progress['progress'] || 0);
          lastReadTime = Number(progress['lastReadTime'] || 0);
          currentChapterIndex = Number(progress['currentChapterIndex'] || 0);
          domPos = String(progress['domPos'] || '');
          currentChapterId = String(progress['currentChapterId'] || '');
          logger.info(TAG, `[导出调试] bookId=${bookId}, chapterIndex=${currentChapterIndex}, domPosLen=${domPos.length}, progress=${readProgress}`);
        } else {
          logger.info(TAG, `[导出调试] bookId=${bookId} 无阅读进度记录`);
        }
        
        // [新增] 获取电子书阅读设置
        const settingsSql = 'SELECT * FROM ebook_reading_settings WHERE bookId = ? LIMIT 1';
        const settingsResults = await this.dbManager.querySql(settingsSql, [bookId]);
        let readingSettings: Record<string, DatabaseRecord> | null = null;
        if (settingsResults.length > 0) {
          readingSettings = settingsResults[0] as Record<string, DatabaseRecord>;
          logger.info(TAG, `[导出调试] bookId=${bookId} 有阅读设置`);
        } else {
          logger.info(TAG, `[导出调试] bookId=${bookId} 无阅读设置`);
        }
        
        // [修复] 使用JSON对象方式创建，确保所有字段都能被序列化
        const itemData: Record<string, string | number | boolean | null | Record<string, DatabaseRecord>> = {
          'id': bookId,
          'format': String(ebook['format']),
          'title': String(ebook['title']),
          'author': String(ebook['author'] || ''),
          'publisher': String(ebook['publisher'] || ''),
          'publishDate': String(ebook['publishDate'] || ''),
          'isbn': String(ebook['isbn'] || ''),
          'language': String(ebook['language'] || ''),
          'description': String(ebook['description'] || ''),
          'coverPath': String(ebook['coverImagePath'] || ''),
          'filePath': String(ebook['filePath']),
          'fileSize': Number(ebook['fileSize'] || 0),
          'totalPages': 0,
          'currentPage': currentPage,
          'readProgress': readProgress,
          'lastReadTime': lastReadTime,
          'lastUpdateTime': Number(ebook['lastUpdateTime'] || 0),
          'isFavorite': Boolean(ebook['isFavorite']),
          'isPrivate': Boolean(ebook['isPrivate']),
          'isNSFW': false,
          'totalWordCount': Number(ebook['totalWordCount'] || 0),
          'currentChapterIndex': currentChapterIndex,
          'currentChapterId': currentChapterId,
          'domPos': domPos,
          'readingSettings': readingSettings
        };
        backupItems.push(itemData as Object as EBookBackupItem);
      }
      
      logger.info(TAG, `Exported ebook library: ${backupItems.length} items`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export ebook library: ${error}`);
      return [];
    }
  }

  /**
   * 导出漫画书源（完整字段）
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
          pkg: String(source['pkg'] || ''),
          name: String(source['name']),
          baseUrl: String(source['baseUrl'] || ''),
          version: String(source['version'] || ''),
          description: String(source['description'] || ''),
          lang: String(source['language'] || 'zh-CN'),
          type: String(source['type'] || 'manga'),
          isEnabled: Boolean(source['isEnabled']),
          priority: Number(source['priority'] || 0),
          configJson: String(source['configJson'] || ''),
          cookies: String(source['cookies'] || ''),
          tabsConfig: String(source['tabs_config'] || ''),
          createTime: Number(source['createTime'] || 0),
          preloadCurrentChapter: Number(source['preloadCurrentChapter'] || 1),
          preloadCurrentPages: Number(source['preloadCurrentPages'] || 10),
          preloadNextChapter: Number(source['preloadNextChapter'] || 1),
          preloadNextPages: Number(source['preloadNextPages'] || -1),
          downloadWhileReading: Number(source['downloadWhileReading'] || 1),
          maxCacheSize: Number(source['maxCacheSize'] || 1073741824),
          requireProxy: Number(source['requireProxy'] || 0),
          isNSFW: Boolean(source['isNSFW']),
          lastUsedTime: Number(source['lastUpdateTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported manga sources: ${backupItems.length} items (full fields)`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export manga sources: ${error}`);
      return [];
    }
  }

  /**
   * 导出小说书源（完整configJson）
   */
  private async exportNovelSources(): Promise<NovelSourceBackup[]> {
    try {
      // 直接从数据库导出完整的书源配置，而不是从内存中导出
      const sql = 'SELECT * FROM novel_source';
      const results = await this.dbManager.querySql(sql);
      const backupItems: NovelSourceBackup[] = [];
      
      for (const record of results) {
        const source = record as Record<string, DatabaseRecord>;
        backupItems.push({
          id: String(source['id']),
          bookSourceUrl: String(source['bookSourceUrl']),
          bookSourceName: String(source['bookSourceName']),
          bookSourceGroup: String(source['bookSourceGroup'] || ''),
          bookSourceType: Number(source['bookSourceType'] || 0),
          enabled: Boolean(source['enabled']),
          weight: Number(source['weight'] || 0),
          respondTime: Number(source['respondTime'] || 180000),
          configJson: String(source['configJson']),  // 完整的Legado书源配置
          createTime: Number(source['createTime'] || 0),
          updateTime: Number(source['updateTime'] || 0),
          isNSFW: Boolean(source['isNSFW']),
          // 兼容字段
          name: String(source['bookSourceName']),
          sourceUrl: String(source['bookSourceUrl']),
          lastUpdateTime: Number(source['lastUpdateTime'] || 0)
        });
      }
      
      logger.info(TAG, `Exported novel sources: ${backupItems.length} items (with full configJson)`);
      return backupItems;
    } catch (error) {
      logger.error(TAG, `Failed to export novel sources: ${error}`);
      return [];
    }
  }

  /**
   * 导出漫画阅读进度
   * [修复] 使用正确的数据库字段名：pageNumber而非pageIndex
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
          pageIndex: Number(rec['pageNumber'] || 0),  // [修复] 数据库字段是pageNumber
          totalPages: 0,  // [修复] 数据库中没有totalPages字段，设为0
          lastReadTime: Number(rec['readTime'] || 0)
        });
      }
      
      logger.info(TAG, `导出漫画阅读进度: ${progress.length} 条记录`);
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

  /**
   * 导出 WebView 源配置
   */
  private async exportWebViewConfigs(): Promise<WebViewConfigBackup[]> {
    try {
      const sql = `
        SELECT
          id, sourceId, userAgent, referer, headers, cookies,
          timeout, retryCount, enableCache, cacheExpireTime,
          enableJavaScript, enableImages, enableCookies, enableLocalStorage,
          createTime, updateTime
        FROM webview_source_config
      `;
      const results = await this.dbManager.querySql(sql);
      const configs: WebViewConfigBackup[] = [];
      
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        configs.push({
          id: Number(rec['id'] || 0),
          sourceId: Number(rec['sourceId'] || 0),
          userAgent: String(rec['userAgent'] || ''),
          referer: String(rec['referer'] || ''),
          headers: String(rec['headers'] || '{}'),
          cookies: String(rec['cookies'] || '{}'),
          timeout: Number(rec['timeout'] || 30000),
          retryCount: Number(rec['retryCount'] || 3),
          enableCache: Boolean(rec['enableCache']),
          cacheExpireTime: Number(rec['cacheExpireTime'] || 3600),
          enableJavaScript: Boolean(rec['enableJavaScript']),
          enableImages: Boolean(rec['enableImages']),
          enableCookies: Boolean(rec['enableCookies']),
          enableLocalStorage: Boolean(rec['enableLocalStorage']),
          createTime: Number(rec['createTime'] || 0),
          updateTime: Number(rec['updateTime'] || 0)
        });
      }
      
      return configs;
    } catch (error) {
      logger.error(TAG, `Failed to export webview source configs: ${error}`);
      return [];
    }
  }

  /**
   * 导出下载任务
   */
  private async exportDownloadTasks(): Promise<DownloadTaskBackup[]> {
    try {
      const sql = `
        SELECT
          id, comicId, chapterId, taskType, status, progress, downloadedSize, totalSize,
          downloadSpeed, errorMessage, priority, createTime, startTime, completeTime
        FROM download_task
      `;
      const results = await this.dbManager.querySql(sql);
      const tasks: DownloadTaskBackup[] = [];
      
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        tasks.push({
          id: Number(rec['id'] || 0),
          comicId: String(rec['comicId'] || ''),
          chapterId: rec['chapterId'] ? String(rec['chapterId']) : undefined,
          taskType: String(rec['taskType'] || ''),
          status: String(rec['status'] || 'pending'),
          progress: Number(rec['progress'] || 0),
          downloadedSize: Number(rec['downloadedSize'] || 0),
          totalSize: Number(rec['totalSize'] || 0),
          downloadSpeed: Number(rec['downloadSpeed'] || 0),
          errorMessage: rec['errorMessage'] ? String(rec['errorMessage']) : undefined,
          priority: Number(rec['priority'] || 0),
          createTime: Number(rec['createTime'] || 0),
          startTime: Number(rec['startTime'] || 0),
          completeTime: Number(rec['completeTime'] || 0)
        });
      }
      
      return tasks;
    } catch (error) {
      logger.error(TAG, `Failed to export download tasks: ${error}`);
      return [];
    }
  }

  /**
   * 导出缓存信息
   */
  private async exportCacheInfo(): Promise<CacheInfoBackup[]> {
    try {
      const sql = `
        SELECT
          id, cacheKey, cacheType, filePath, fileSize, expireTime,
          accessCount, lastAccessTime, createTime
        FROM cache_info
      `;
      const results = await this.dbManager.querySql(sql);
      const items: CacheInfoBackup[] = [];
      
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        const fileSize = Number(rec['fileSize'] || 0);
        const expireTime = Number(rec['expireTime'] || 0);
        items.push({
          id: Number(rec['id'] || 0),
          cacheKey: String(rec['cacheKey'] || ''),
          cacheType: String(rec['cacheType'] || ''),
          filePath: String(rec['filePath'] || ''),
          fileSize: fileSize,
          expireTime: expireTime,
          accessCount: Number(rec['accessCount'] || 0),
          lastAccessTime: Number(rec['lastAccessTime'] || 0),
          createTime: Number(rec['createTime'] || 0),
          // 兼容旧字段
          cacheSize: fileSize,
          expiryTime: expireTime
        });
      }
      
      return items;
    } catch (error) {
      logger.error(TAG, `Failed to export cache info: ${error}`);
      return [];
    }
  }

  /**
   * 导出插件信息
   */
  private async exportPlugins(): Promise<PluginBackup[]> {
    try {
      const sql = `
        SELECT
          id, pluginId, name, version, description, author,
          hspPath, configSchema, isEnabled, installTime, updateTime
        FROM plugin
      `;
      const results = await this.dbManager.querySql(sql);
      const plugins: PluginBackup[] = [];
      
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        const isEnabled = Boolean(rec['isEnabled']);
        plugins.push({
          id: Number(rec['id'] || 0),
          pluginId: String(rec['pluginId'] || ''),
          name: String(rec['name'] || ''),
          version: String(rec['version'] || ''),
          author: String(rec['author'] || ''),
          description: String(rec['description'] || ''),
          hspPath: String(rec['hspPath'] || ''),
          configSchema: String(rec['configSchema'] || ''),
          isEnabled: isEnabled,
          // 兼容旧字段
          enabled: isEnabled,
          installTime: Number(rec['installTime'] || 0),
          updateTime: Number(rec['updateTime'] || 0)
        });
      }
      
      return plugins;
    } catch (error) {
      logger.error(TAG, `Failed to export plugins: ${error}`);
      return [];
    }
  }

  /**
   * 导出收藏信息
   */
  private async exportFavorites(): Promise<FavoriteBackup[]> {
    try {
      const sql = `
        SELECT
          id, comicId, userId, folderName, addTime,
          lastReadChapterId, lastReadPageNumber, lastReadTime, readProgress
        FROM favorite
      `;
      const results = await this.dbManager.querySql(sql);
      const favorites: FavoriteBackup[] = [];
      
      for (const row of results) {
        const rec = row as Record<string, DatabaseRecord>;
        favorites.push({
          id: Number(rec['id'] || 0),
          comicId: String(rec['comicId'] || ''),
          userId: String(rec['userId'] || ''),
          folderName: String(rec['folderName'] || 'default'),
          addTime: Number(rec['addTime'] || 0),
          lastReadChapterId: String(rec['lastReadChapterId'] || ''),
          lastReadPageNumber: Number(rec['lastReadPageNumber'] || 0),
          lastReadTime: Number(rec['lastReadTime'] || 0),
          readProgress: Number(rec['readProgress'] || 0)
        });
      }
      
      return favorites;
    } catch (error) {
      logger.error(TAG, `Failed to export favorites: ${error}`);
      return [];
    }
  }

  /**
   * 导出在线漫画相关数据
   */
  private async exportOnlineData(): Promise<OnlineDataBackupSection> {
    const comics: OnlineComicBackup[] = [];
    const readHistory: OnlineReadHistoryBackup[] = [];
    
    try {
      const comicResults = await this.dbManager.querySql('SELECT * FROM online_comic_info ORDER BY updateTime DESC');
      for (const comicRow of comicResults) {
        const comicRecord = comicRow as Record<string, DatabaseRecord>;
        const comicId = String(comicRecord['id'] || '');
        
        const chapterResults = await this.dbManager.querySql(
          'SELECT * FROM online_chapter WHERE comicId = ? ORDER BY `index` ASC, addTime ASC',
          [comicId]
        );
        const chapters: OnlineChapterBackup[] = [];
        
        for (const chapterRow of chapterResults) {
          const chapterRecord = chapterRow as Record<string, DatabaseRecord>;
          const chapterId = String(chapterRecord['id'] || '');
          
          const pageResults = await this.dbManager.querySql(
            'SELECT * FROM online_page WHERE chapterId = ? ORDER BY pageNumber ASC',
            [chapterId]
          );
          const pages: OnlinePageBackup[] = [];
          
          for (const pageRow of pageResults) {
            const pageRecord = pageRow as Record<string, DatabaseRecord>;
            pages.push({
              id: String(pageRecord['id'] || ''),
              chapterId: String(pageRecord['chapterId'] || ''),
              pageNumber: Number(pageRecord['pageNumber'] || 0),
              imageUrl: String(pageRecord['imageUrl'] || ''),
              localPath: String(pageRecord['localPath'] || ''),
              width: Number(pageRecord['width'] || 0),
              height: Number(pageRecord['height'] || 0),
              fileSize: Number(pageRecord['fileSize'] || 0),
              isDownloaded: Boolean(pageRecord['isDownloaded']),
              createTime: Number(pageRecord['createTime'] || 0)
            });
          }
          
          chapters.push({
            id: String(chapterRecord['id'] || ''),
            comicId: String(chapterRecord['comicId'] || ''),
            externalId: String(chapterRecord['externalId'] || ''),
            title: String(chapterRecord['title'] || ''),
            chapterNumber: Number(chapterRecord['chapterNumber'] || 0),
            url: String(chapterRecord['url'] || ''),
            pageCount: Number(chapterRecord['pageCount'] || 0),
            publishTime: Number(chapterRecord['publishTime'] || 0),
            addTime: Number(chapterRecord['addTime'] || 0),
            createTime: Number(chapterRecord['createTime'] || 0),
            updateTime: Number(chapterRecord['updateTime'] || 0),
            isDownloaded: Boolean(chapterRecord['isDownloaded']),
            downloadPath: String(chapterRecord['downloadPath'] || ''),
            index: Number(chapterRecord['index'] || 0),
            pages: pages
          });
        }
        
        comics.push({
          id: String(comicRecord['id'] || ''),
          sourceId: String(comicRecord['sourceId'] || ''),
          externalId: String(comicRecord['externalId'] || ''),
          title: String(comicRecord['title'] || ''),
          author: String(comicRecord['author'] || ''),
          coverUrl: String(comicRecord['coverUrl'] || ''),
          description: String(comicRecord['description'] || ''),
          tags: String(comicRecord['tags'] || ''),
          rating: Number(comicRecord['rating'] || 0),
          lastUpdateTime: Number(comicRecord['lastUpdateTime'] || 0),
          addTime: Number(comicRecord['addTime'] || 0),
          createTime: Number(comicRecord['createTime'] || 0),
          updateTime: Number(comicRecord['updateTime'] || 0),
          sourceName: String(comicRecord['sourceName'] || ''),
          sourcePkg: String(comicRecord['sourcePkg'] || ''),
          isNSFW: Boolean(comicRecord['isNSFW']),
          isPrivate: Boolean(comicRecord['isPrivate']),
          chapters: chapters
        });
      }
    } catch (error) {
      logger.warn(TAG, `Failed to export online comic data: ${error}`);
    }
    
    try {
      const historyResults = await this.dbManager.querySql('SELECT * FROM online_read_history ORDER BY readTime DESC');
      for (const historyRow of historyResults) {
        const historyRecord = historyRow as Record<string, DatabaseRecord>;
        const pageNumber = Number(historyRecord['pageNumber'] || 0);
        readHistory.push({
          id: Number(historyRecord['id'] || 0),
          comicId: String(historyRecord['comicId'] || ''),
          chapterId: String(historyRecord['chapterId'] || ''),
          userId: String(historyRecord['userId'] || ''),
          pageNumber: pageNumber,
          readTime: Number(historyRecord['readTime'] || 0),
          duration: Number(historyRecord['duration'] || 0),
          createTime: Number(historyRecord['createTime'] || 0),
          // 兼容旧字段
          pageIndex: pageNumber
        });
      }
    } catch (error) {
      logger.warn(TAG, `Failed to export online read history: ${error}`);
    }
    
    return {
      comics: comics,
      readHistory: readHistory
    };
  }

  /**
   * 导出统一标注（书签/划线/想法）
   */
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
      logger.info(TAG, `导出统一标注成功: ${records.length} 条`);
      return records;
    } catch (error) {
      logger.warn(TAG, `导出统一标注失败，已跳过: ${error}`);
      return [];
    }
  }

  /**
   * 恢复统一标注（支持冲突策略）
   */
  private async restoreUnifiedAnnotationsWithStrategy(
    items: UnifiedAnnotationBackupItem[],
    strategy: 'skip' | 'replace' | 'merge'
  ): Promise<void> {
    if (!items || items.length <= 0) {
      logger.info(TAG, '无需恢复统一标注');
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

    let restoredCount = 0;
    let skippedCount = 0;
    let failedCount = 0;

    for (const rawItem of items) {
      const item = this.normalizeUnifiedAnnotationBackupItem(rawItem);
      if (item.id.length <= 0 || item.contentId.length <= 0) {
        skippedCount++;
        continue;
      }
      try {
        const existingRows = await this.dbManager.querySql(
          'SELECT updateTime FROM unified_annotation WHERE id = ? LIMIT 1',
          [item.id]
        );
        if (existingRows.length > 0) {
          if (strategy === 'skip') {
            skippedCount++;
            continue;
          }
          if (strategy === 'merge') {
            const existingRecord = existingRows[0] as Record<string, DatabaseRecord>;
            const existingUpdateTime = Number(existingRecord['updateTime'] || 0);
            if (existingUpdateTime > item.updateTime) {
              skippedCount++;
              continue;
            }
          }
        }

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
        restoredCount++;
      } catch (error) {
        failedCount++;
        logger.warn(TAG, `恢复统一标注失败: id=${item.id}, error=${error}`);
      }
    }

    logger.info(
      TAG,
      `统一标注恢复完成: success=${restoredCount}, skipped=${skippedCount}, failed=${failedCount}, strategy=${strategy}`
    );
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
      JSON.parse(trimmed);
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

  /**
   * 恢复漫画书源（完整字段）
   */
  private async restoreMangaSources(items: MangaSourceBackup[]): Promise<void> {
    logger.info(TAG, `Restoring manga sources: ${items.length} items`);
    
    for (const item of items) {
      try {
        const now = Date.now();
        const sql = `INSERT OR REPLACE INTO comic_source (
          id, pkg, name, baseUrl, version, description, language, type, 
          isEnabled, priority, configJson, cookies, tabs_config, createTime,
          preloadCurrentChapter, preloadCurrentPages, preloadNextChapter, preloadNextPages,
          downloadWhileReading, maxCacheSize, requireProxy, isNSFW, lastUpdateTime
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
        
        await this.dbManager.executeSql(sql, [
          item.id,
          item.pkg || '',
          item.name,
          item.baseUrl,
          item.version || '1.0',
          item.description || '',
          item.lang || 'zh-CN',
          item.type || 'manga',
          item.isEnabled ? 1 : 0,
          item.priority || 0,
          item.configJson || '',
          item.cookies || '',
          item.tabsConfig || '',
          item.createTime || now,
          item.preloadCurrentChapter ?? 1,
          item.preloadCurrentPages ?? 10,
          item.preloadNextChapter ?? 1,
          item.preloadNextPages ?? -1,
          item.downloadWhileReading ?? 1,
          item.maxCacheSize ?? 1073741824,
          item.requireProxy ?? 0,
          item.isNSFW ? 1 : 0,
          item.lastUsedTime || now
        ]);
        logger.debug(TAG, `Restored manga source: ${item.name}`);
      } catch (error) {
        logger.error(TAG, `Failed to restore manga source: ${item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, 'Manga sources restore completed (full fields)');
  }

  /**
   * 恢复小说书源（完整configJson）
   */
  private async restoreNovelSources(items: NovelSourceBackup[]): Promise<void> {
    logger.info(TAG, `Restoring novel sources: ${items.length} items`);
    
    let successCount = 0;
    let skipCount = 0;
    
    for (const item of items) {
      try {
        // 检查是否有完整的configJson
        if (!item.configJson || item.configJson.length === 0) {
          logger.warn(TAG, `Novel source ${item.bookSourceName || item.name} has no configJson, skipping`);
          skipCount++;
          continue;
        }
        
        const now = Date.now();
        const bookSourceUrl = item.bookSourceUrl || item.sourceUrl || item.id;
        const bookSourceName = item.bookSourceName || item.name || 'Unknown';
        
        // 生成唯一ID
        const id = `novel_source_${bookSourceUrl.replace(/[^a-zA-Z0-9]/g, '_')}`;
        
        const sql = `INSERT OR REPLACE INTO novel_source (
          id, bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType,
          enabled, weight, respondTime, configJson, createTime, updateTime, isNSFW
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
        
        await this.dbManager.executeSql(sql, [
          id,
          bookSourceUrl,
          bookSourceName,
          item.bookSourceGroup || '',
          item.bookSourceType || 0,
          item.enabled ? 1 : 0,
          item.weight || 0,
          item.respondTime || 180000,
          item.configJson,
          item.createTime || now,
          item.updateTime || now,
          item.isNSFW ? 1 : 0
        ]);
        
        // 同时加载到内存中
        try {
          const sourceConfig = JSON.parse(item.configJson) as LegadoBookSource;
          this.novelSourceManager.loadSourceToMemory(sourceConfig);
        } catch (parseError) {
          logger.warn(TAG, `Failed to parse configJson for ${bookSourceName}: ${parseError}`);
        }
        
        successCount++;
        logger.debug(TAG, `Restored novel source: ${bookSourceName}`);
      } catch (error) {
        logger.error(TAG, `Failed to restore novel source: ${item.bookSourceName || item.name}, ${error}`);
      }
    }
    
    logger.info(TAG, `Novel sources restore completed: ${successCount} success, ${skipCount} skipped`);
  }

  /**
   * 恢复漫画阅读进度
   * [修复] 使用正确的数据库字段名：pageNumber而非pageIndex，添加userId和createTime
   */
  private async restoreMangaReadProgress(items: MangaReadProgressBackup[]): Promise<void> {
    logger.info(TAG, `Restoring manga read progress: ${items.length} items`);
    
    const now = Date.now();
    for (const item of items) {
      try {
        // 先检查comicId和chapterId是否存在
        const comicExists = await this.dbManager.querySql('SELECT id FROM comic_info WHERE id = ?', [item.mangaId]);
        const chapterExists = await this.dbManager.querySql('SELECT id FROM chapter WHERE id = ?', [item.chapterId]);
        
        if (comicExists.length === 0 || chapterExists.length === 0) {
          logger.debug(TAG, `跳过阅读进度恢复: comicId=${item.mangaId}存在=${comicExists.length > 0}, chapterId=${item.chapterId}存在=${chapterExists.length > 0}`);
          continue;
        }
        
        const sql = 'INSERT OR REPLACE INTO read_history (comicId, chapterId, userId, pageNumber, readTime, duration, createTime) VALUES (?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          item.mangaId, 
          item.chapterId, 
          'default',  // userId
          item.pageIndex || 0,  // pageNumber
          item.lastReadTime || now,
          0,  // duration
          now  // createTime
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
      
      // 恢复字体设置
      if (settings.general && settings.general.fontSettings) {
        await this.restoreFontSettings(settings.general.fontSettings);
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

  /**
   * 恢复 WebView 配置
   */
  private async restoreWebViewConfigs(configs: WebViewConfigBackup[]): Promise<void> {
    logger.info(TAG, `Restoring WebView configs: ${configs.length} items`);
    
    for (const config of configs) {
      try {
        const now = Date.now();
        const updateTime = Number(config.updateTime || config.lastUpdateTime || now);
        const createTime = Number(config.createTime || updateTime || now);
        const enableImages = config.enableImages !== undefined
          ? config.enableImages
          : config.imageLoadingStrategy !== 'none';
        const sql = 'INSERT OR REPLACE INTO webview_source_config (id, sourceId, userAgent, referer, headers, cookies, timeout, retryCount, enableCache, cacheExpireTime, enableJavaScript, enableImages, enableCookies, enableLocalStorage, createTime, updateTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          config.id > 0 ? config.id : null,
          config.sourceId,
          config.userAgent || '',
          config.referer || '',
          config.headers || config.customHeaders || '{}',
          config.cookies || '{}',
          config.timeout || 30000,
          config.retryCount || 3,
          config.enableCache !== undefined ? (config.enableCache ? 1 : 0) : 1,
          config.cacheExpireTime || 3600,
          config.enableJavaScript !== undefined ? (config.enableJavaScript ? 1 : 0) : 1,
          enableImages ? 1 : 0,
          config.enableCookies !== undefined ? (config.enableCookies ? 1 : 0) : 1,
          config.enableLocalStorage !== undefined ? (config.enableLocalStorage ? 1 : 0) : 1,
          createTime,
          updateTime
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
        const startTime = Number(task.startTime ?? task.updateTime ?? 0);
        const completeTime = Number(
          task.completeTime ??
          ((task.status === 'completed' || task.status === 'success') ? (task.updateTime ?? 0) : 0)
        );
        const sql = 'INSERT OR REPLACE INTO download_task (id, comicId, chapterId, taskType, status, progress, downloadedSize, totalSize, downloadSpeed, errorMessage, priority, createTime, startTime, completeTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          task.id > 0 ? task.id : null,
          task.comicId,
          task.chapterId || null,
          task.taskType,
          task.status,
          task.progress,
          task.downloadedSize,
          task.totalSize,
          task.downloadSpeed || 0,
          task.errorMessage || null,
          task.priority || 0,
          task.createTime,
          startTime,
          completeTime
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
        const lastReadTime = Number(fav.lastReadTime ?? fav.updateTime ?? 0);
        const sql = 'INSERT OR REPLACE INTO favorite (id, comicId, userId, folderName, addTime, lastReadChapterId, lastReadPageNumber, lastReadTime, readProgress) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';
        
        await this.dbManager.executeSql(sql, [
          fav.id > 0 ? fav.id : null,
          fav.comicId,
          fav.userId,
          fav.folderName || 'default',
          fav.addTime,
          fav.lastReadChapterId || '',
          fav.lastReadPageNumber || 0,
          lastReadTime,
          fav.readProgress || 0
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
    const comics = data.comics as OnlineComicBackup[] | undefined;
    const readHistory = data.readHistory as OnlineReadHistoryBackup[] | undefined;
    
    logger.info(TAG, `Restoring online data: ${comics?.length ?? 0} comics, ${readHistory?.length ?? 0} history`);
    
    if (comics && comics.length > 0) {
      for (const comic of comics) {
        try {
          const now = Date.now();
          const sqlComic = 'INSERT OR REPLACE INTO online_comic_info (id, sourceId, externalId, title, author, description, coverUrl, tags, rating, lastUpdateTime, addTime, createTime, updateTime, sourceName, sourcePkg, isNSFW, isPrivate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
          
          await this.dbManager.executeSql(sqlComic, [
            comic.id,
            comic.sourceId,
            comic.externalId,
            comic.title,
            comic.author || '',
            comic.description || '',
            comic.coverUrl || '',
            comic.tags || '',
            comic.rating || 0,
            comic.lastUpdateTime || now,
            comic.addTime || now,
            comic.createTime || now,
            comic.updateTime || now,
            comic.sourceName || '',
            comic.sourcePkg || '',
            comic.isNSFW ? 1 : 0,
            comic.isPrivate ? 1 : 0
          ]);
          
          const chapters = comic.chapters as OnlineChapterBackup[] | undefined;
          if (chapters) {
            for (const chapter of chapters) {
              const chapterNow = Date.now();
              const chapterNumber = Number(chapter.chapterNumber || 0);
              const chapterIndex = Number(chapter.index || 0);
              const sqlChapter = 'INSERT OR REPLACE INTO online_chapter (id, comicId, externalId, title, chapterNumber, url, pageCount, publishTime, addTime, createTime, updateTime, isDownloaded, downloadPath, `index`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
              
              await this.dbManager.executeSql(sqlChapter, [
                chapter.id,
                chapter.comicId || comic.id,
                chapter.externalId,
                chapter.title,
                Number.isNaN(chapterNumber) ? 0 : chapterNumber,
                chapter.url || '',
                chapter.pageCount || 0,
                chapter.publishTime || 0,
                chapter.addTime || chapterNow,
                chapter.createTime || chapterNow,
                chapter.updateTime || chapterNow,
                chapter.isDownloaded ? 1 : 0,
                chapter.downloadPath || '',
                Number.isNaN(chapterIndex) ? 0 : chapterIndex
              ]);
              
              const pages = chapter.pages as OnlinePageBackup[] | undefined;
              if (pages) {
                for (const page of pages) {
                  const sqlPage = 'INSERT OR REPLACE INTO online_page (id, chapterId, pageNumber, imageUrl, localPath, width, height, fileSize, isDownloaded, createTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
                  
                  await this.dbManager.executeSql(sqlPage, [
                    page.id,
                    page.chapterId || chapter.id,
                    page.pageNumber,
                    page.imageUrl,
                    page.localPath || '',
                    page.width || 0,
                    page.height || 0,
                    page.fileSize || 0,
                    page.isDownloaded ? 1 : 0,
                    page.createTime || Date.now()
                  ]);
                }
              }
            }
          }
        } catch (error) {
          logger.error(TAG, `Failed to restore online comic: ${comic.title}, ${error}`);
        }
      }
    }
    
    if (readHistory && readHistory.length > 0) {
      for (const history of readHistory) {
        try {
          const pageNumber = Number(
            history.pageNumber !== undefined
              ? history.pageNumber
              : (history.pageIndex || 0)
          );
          const sql = 'INSERT OR REPLACE INTO online_read_history (id, comicId, chapterId, userId, pageNumber, readTime, duration, createTime) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
          
          await this.dbManager.executeSql(sql, [
            history.id > 0 ? history.id : null,
            history.comicId,
            history.chapterId,
            history.userId || 'default',
            pageNumber,
            history.readTime,
            history.duration || 0,
            history.createTime || history.readTime || Date.now()
          ]);
        } catch (error) {
          logger.error(TAG, `Failed to restore online read history: ${error}`);
        }
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
        // 递归删除目录及其所有内容
        this.deleteDirectoryRecursive(dir);
        logger.debug(TAG, `已清理临时目录: ${dir}`);
      }
    } catch (error) {
      logger.warn(TAG, `清理临时目录失败: ${error}`);
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
      
      const entries = fs.listFileSync(dirPath);
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        const stat = fs.statSync(fullPath);
        
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
        const existingBookResults = await this.dbManager.querySql('SELECT id FROM ebook_info WHERE id = ?', [item.id]);
        const exists = existingBookResults.length > 0;
        
        if (exists && strategy === 'skip') {
          logger.debug(TAG, `Skipping existing ebook: ${item.title}`);
          continue;
        }
        
        // 对于merge策略，保留更新的阅读进度
        if (exists && strategy === 'merge') {
          const progressResults = await this.dbManager.querySql(
            'SELECT currentPosition, progress, lastReadTime FROM ebook_reading_progress WHERE bookId = ? ORDER BY lastReadTime DESC LIMIT 1',
            [item.id]
          );
          if (progressResults.length > 0) {
            const existingProgress = progressResults[0] as Record<string, DatabaseRecord>;
            const existingReadTime = Number(existingProgress['lastReadTime'] || 0);
            const backupReadTime = item.lastReadTime || 0;
            
            if (existingReadTime > backupReadTime) {
              item.currentPage = Number(existingProgress['currentPosition'] || item.currentPage);
              item.readProgress = Number(existingProgress['progress'] || item.readProgress);
              item.lastReadTime = existingReadTime;
            }
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

  /**
   * [新增] 导出备份文件到Download/漫匹/backup文件夹
   * @param sourcePath 源备份文件路径
   * @param fileName 备份文件名
   * @returns 导出的文件路径，如果失败返回空字符串
   */
  private async exportToDownloadBackupFolder(sourcePath: string, fileName: string): Promise<string> {
    try {
      // 从AppStorage获取Download同步目录路径
      const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
      if (!downloadDirPath) {
        logger.info(TAG, 'Download同步目录未配置，跳过导出到外部存储');
        return '';
      }

      // 构建backup文件夹路径
      const backupFolderPath = `${downloadDirPath}/backup`;
      
      // 确保backup文件夹存在
      try {
        fs.accessSync(backupFolderPath);
      } catch (e) {
        fs.mkdirSync(backupFolderPath);
        logger.info(TAG, `创建backup文件夹: ${backupFolderPath}`);
      }

      // 复制备份文件到backup文件夹
      const destPath = `${backupFolderPath}/${fileName}`;
      await fs.copyFile(sourcePath, destPath);
      
      logger.info(TAG, `备份文件已导出到: ${destPath}`);
      return destPath;
    } catch (error) {
      logger.warn(TAG, `导出备份文件到Download目录失败: ${String(error)}`);
      return '';
    }
  }

  /**
   * 生成漫画元数据XML文件
   */
  private async generateMangaMetadataXml(manga: MangaBackupItem, targetDir: string): Promise<void> {
    try {
      const metadata: MangaMetadata = {
        title: manga.title,
        series: manga.title,
        author: manga.author,
        artist: manga.artist,
        description: manga.description,
        genre: manga.genre,
        status: manga.status,
        coverUrl: manga.coverUrl,
        sourceId: manga.sourceId,
        sourceName: manga.sourceName,
        url: manga.url,
        chapterCount: manga.chapters?.length || 0,
        lastUpdateTime: manga.lastUpdateTime,
        isFavorite: manga.isFavorite,
        isPrivate: manga.isPrivate,
        isNSFW: manga.isNSFW
      };

      const xmlContent = MetadataXmlGenerator.generateComicInfoXml(metadata);
      const xmlPath = `${targetDir}/ComicInfo.xml`;
      
      const file = fs.openSync(xmlPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, xmlContent);
      fs.closeSync(file);
      
      logger.debug(TAG, `已生成漫画元数据: ${xmlPath}`);
    } catch (error) {
      logger.warn(TAG, `生成漫画元数据XML失败: ${manga.title}, ${error}`);
    }
  }

  /**
   * 生成电子书元数据XML文件
   */
  private async generateEBookMetadataXml(ebook: EBookBackupItem, targetDir: string): Promise<void> {
    try {
      const metadata: EBookMetadata = {
        id: ebook.id,
        title: ebook.title,
        author: ebook.author,
        publisher: ebook.publisher,
        publishDate: ebook.publishDate,
        isbn: ebook.isbn,
        language: ebook.language,
        description: ebook.description,
        format: ebook.format,
        fileSize: ebook.fileSize,
        totalWordCount: ebook.totalWordCount,
        isFavorite: ebook.isFavorite,
        isPrivate: ebook.isPrivate
      };

      const xmlContent = MetadataXmlGenerator.generateEBookMetadataXml(metadata);
      const xmlPath = `${targetDir}/metadata.xml`;
      
      const file = fs.openSync(xmlPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, xmlContent);
      fs.closeSync(file);
      
      logger.debug(TAG, `已生成电子书元数据: ${xmlPath}`);
    } catch (error) {
      logger.warn(TAG, `生成电子书元数据XML失败: ${ebook.title}, ${error}`);
    }
  }

  /**
   * 生成小说元数据XML文件
   */
  private async generateNovelMetadataXml(novel: NovelBackupItem, targetDir: string): Promise<void> {
    try {
      const metadata: NovelMetadata = {
        id: novel.id,
        name: novel.name,
        author: novel.author,
        intro: novel.intro,
        kind: novel.kind,
        coverUrl: novel.coverUrl,
        sourceId: novel.sourceId,
        sourceName: novel.sourceName,
        bookUrl: novel.bookUrl,
        wordCount: novel.wordCount,
        chapterCount: novel.chapterCount,
        isFavorite: novel.isFavorite,
        isPrivate: novel.isPrivate,
        isNSFW: novel.isNSFW
      };

      const xmlContent = MetadataXmlGenerator.generateNovelMetadataXml(metadata);
      const xmlPath = `${targetDir}/metadata.xml`;
      
      const file = fs.openSync(xmlPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, xmlContent);
      fs.closeSync(file);
      
      logger.debug(TAG, `已生成小说元数据: ${xmlPath}`);
    } catch (error) {
      logger.warn(TAG, `生成小说元数据XML失败: ${novel.name}, ${error}`);
    }
  }
  
  /**
   * 导出字体设置
   * 字体设置存储在单独的preferences文件 'font_settings' 中
   */
  private async exportFontSettings(): Promise<FontSettingsBackup | undefined> {
    try {
      // 从FontManager的preferences读取字体设置
      const context = getGlobalContext();
      const fontPrefs: preferences.Preferences = await preferences.getPreferences(context, 'font_settings');
      
      const fontSettingsStr = await fontPrefs.get('settings', '') as string;
      const customFontsStr = await fontPrefs.get('custom_fonts', '') as string;
      
      if (!fontSettingsStr && !customFontsStr) {
        logger.debug(TAG, '没有字体设置需要导出');
        return undefined;
      }
      
      let fontSettings: Record<string, Object> = {};
      if (fontSettingsStr) {
        fontSettings = JSON.parse(fontSettingsStr) as Record<string, Object>;
      }
      
      // 获取自定义字体列表
      const customFonts: CustomFontBackup[] = [];
      if (customFontsStr) {
        const customFontsRaw = JSON.parse(customFontsStr) as Array<Record<string, Object>>;
        for (const font of customFontsRaw) {
          const filePath = String(font['filePath'] || '');
          // 从路径中提取文件名
          const fileName = filePath.split('/').pop() || '';
          customFonts.push({
            id: String(font['id'] || ''),
            familyName: String(font['familyName'] || ''),
            displayName: String(font['displayName'] || ''),
            fileName: fileName
          });
        }
      }
      
      const backup: FontSettingsBackup = {
        appFontType: String(fontSettings['appFontType'] || 'system'),
        appSystemFontId: String(fontSettings['appSystemFontId'] || 'default'),
        appCustomFontId: String(fontSettings['appCustomFontId'] || ''),
        appFontSize: Number(fontSettings['appFontSize'] || 1.0),
        novelFontType: String(fontSettings['novelFontType'] || 'system'),
        novelSystemFontId: String(fontSettings['novelSystemFontId'] || 'default'),
        novelCustomFontId: String(fontSettings['novelCustomFontId'] || ''),
        novelFontSize: Number(fontSettings['novelFontSize'] || 18),
        novelLineHeight: Number(fontSettings['novelLineHeight'] || 1.8),
        ebookFontType: String(fontSettings['ebookFontType'] || 'system'),
        ebookSystemFontId: String(fontSettings['ebookSystemFontId'] || 'default'),
        ebookCustomFontId: String(fontSettings['ebookCustomFontId'] || ''),
        ebookFontSize: Number(fontSettings['ebookFontSize'] || 18),
        ebookLineHeight: Number(fontSettings['ebookLineHeight'] || 1.6),
        customFonts: customFonts
      };
      
      logger.info(TAG, `导出字体设置: ${customFonts.length} 个自定义字体`);
      return backup;
    } catch (error) {
      logger.warn(TAG, `导出字体设置失败: ${error}`);
      return undefined;
    }
  }
  
  /**
   * 恢复字体设置
   * 字体设置存储在单独的preferences文件 'font_settings' 中
   * [修复] 增强日志输出，详细记录每个步骤
   */
  private async restoreFontSettings(fontSettings: FontSettingsBackup): Promise<void> {
    try {
      logger.info(TAG, `========== 开始恢复字体设置 ==========`);
      logger.info(TAG, `备份中的自定义字体数量: ${fontSettings.customFonts?.length || 0}`);
      
      // 获取FontManager的preferences
      const context = getGlobalContext();
      const fontPrefs: preferences.Preferences = await preferences.getPreferences(context, 'font_settings');
      
      // 恢复字体设置
      const settingsObj: Record<string, Object> = {};
      settingsObj['appFontType'] = fontSettings.appFontType;
      settingsObj['appSystemFontId'] = fontSettings.appSystemFontId;
      settingsObj['appCustomFontId'] = fontSettings.appCustomFontId;
      settingsObj['appFontSize'] = fontSettings.appFontSize;
      settingsObj['novelFontType'] = fontSettings.novelFontType;
      settingsObj['novelSystemFontId'] = fontSettings.novelSystemFontId;
      settingsObj['novelCustomFontId'] = fontSettings.novelCustomFontId;
      settingsObj['novelFontSize'] = fontSettings.novelFontSize;
      settingsObj['novelLineHeight'] = fontSettings.novelLineHeight;
      settingsObj['ebookFontType'] = fontSettings.ebookFontType;
      settingsObj['ebookSystemFontId'] = fontSettings.ebookSystemFontId;
      settingsObj['ebookCustomFontId'] = fontSettings.ebookCustomFontId;
      settingsObj['ebookFontSize'] = fontSettings.ebookFontSize;
      settingsObj['ebookLineHeight'] = fontSettings.ebookLineHeight;
      
      await fontPrefs.put('settings', JSON.stringify(settingsObj));
      logger.info(TAG, `字体基础设置已恢复: appFontType=${fontSettings.appFontType}, appCustomFontId=${fontSettings.appCustomFontId}`);
      
      // 恢复自定义字体列表
      if (fontSettings.customFonts && fontSettings.customFonts.length > 0) {
        const filesDir = this.sandboxManager.getDirectory('files');
        const fontsDir = `${filesDir}/custom_fonts`;
        
        logger.info(TAG, `检查字体目录: ${fontsDir}`);
        
        // [修复] 先检查字体目录是否存在并列出文件
        try {
          if (fs.accessSync(fontsDir)) {
            const existingFiles = fs.listFileSync(fontsDir);
            logger.info(TAG, `字体目录存在，包含文件: ${existingFiles.join(', ') || '空'}`);
          } else {
            logger.warn(TAG, `字体目录不存在: ${fontsDir}，字体文件可能未正确恢复`);
          }
        } catch (checkError) {
          logger.error(TAG, `检查字体目录失败: ${checkError}`);
        }
        
        const customFonts: Array<Record<string, Object>> = [];
        let foundCount = 0;
        let missingCount = 0;
        
        for (const font of fontSettings.customFonts) {
          const fontPath = `${fontsDir}/${font.fileName}`;
          logger.info(TAG, `检查字体文件: ${font.displayName} -> ${fontPath}`);
          
          // 检查字体文件是否存在
          let fileExists = false;
          try {
            fileExists = fs.accessSync(fontPath);
          } catch (e) {
            fileExists = false;
          }
          
          if (fileExists) {
            const fontObj: Record<string, Object> = {};
            fontObj['id'] = font.id;
            fontObj['familyName'] = font.familyName;
            fontObj['displayName'] = font.displayName;
            fontObj['filePath'] = fontPath;
            fontObj['isRegistered'] = false;
            fontObj['addedTime'] = Date.now();
            customFonts.push(fontObj);
            foundCount++;
            logger.info(TAG, `✓ 字体文件存在: ${font.displayName}`);
          } else {
            missingCount++;
            logger.warn(TAG, `✗ 字体文件不存在: ${fontPath}`);
          }
        }
        
        await fontPrefs.put('custom_fonts', JSON.stringify(customFonts));
        logger.info(TAG, `恢复自定义字体列表完成: 成功=${foundCount}, 缺失=${missingCount}`);
      } else {
        logger.info(TAG, `备份中没有自定义字体需要恢复`);
      }
      
      // 刷新preferences
      await fontPrefs.flush();
      
      // 通知FontManager重新加载设置
      try {
        const fontManagerModule = await import('./FontManager');
        const fontManager = fontManagerModule.getFontManager();
        await fontManager.reloadSettings();
      } catch (reloadError) {
        logger.warn(TAG, `通知FontManager重新加载失败: ${reloadError}`);
      }
      
      logger.info(TAG, `========== 字体设置恢复完成 ==========`);
    } catch (error) {
      logger.error(TAG, `恢复字体设置失败: ${error}`);
    }
  }
}

export function getEnhancedBackupManager(): EnhancedBackupManager {
  return EnhancedBackupManager.getInstance();
}
