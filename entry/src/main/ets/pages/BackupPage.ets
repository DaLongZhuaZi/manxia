/**
 * 备份与恢复页面
 * 支持导出和导入所有应用数据
 * 
 * 文件路径: entry/src/main/ets/pages/BackupPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { getBackupManager } from '../Framework/Managers/BackupManager';
import { getEnhancedBackupManager, RestoreOptions } from '../Framework/Managers/EnhancedBackupManager';
import { BackupData, BackupMetadata, BackupOptions, DEFAULT_BACKUP_OPTIONS } from '../Models/BackupModels';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { SandboxManager } from '../Framework/Storage/SandboxManager';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { BackupOptionsDialog } from '../components/backup/BackupOptionsDialog';
import { RestoreOptionsDialog } from '../components/backup/RestoreOptionsDialog';
import { WebDAVConfigDialog } from '../components/backup/WebDAVConfigDialog';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { getWebDAVBackupManager, RemoteBackupInfo, WebDAVSyncStatus } from '../Framework/WebDAV/WebDAVBackupManager';
import { WebDAVSettings, DEFAULT_WEBDAV_SETTINGS } from '../Models/WebDAVModels';
import { WebDAVClient, WebDAVConfig, WebDAVTestResult } from '../Framework/WebDAV/WebDAVClient';
import { preferences } from '@kit.ArkData';

const TAG = 'BackupPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface ThemeState {
  currentTheme: ThemeType;
}

@ComponentV2
struct BackupPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('BackupPage', { enableDebug: true });
  private backupManager = getBackupManager();
  private enhancedBackupManager = getEnhancedBackupManager();
  private webdavManager = getWebDAVBackupManager();
  pathStack: NavPathStack = new NavPathStack();
  
  // Tab状态
  @Local currentTab: 'local' | 'cloud' = 'local';
  
  // 本地备份状态
  @Local isCreatingBackup: boolean = false;
  @Local isRestoringBackup: boolean = false;
  @Local backupFiles: BackupFileInfo[] = [];
  @Local isLoading: boolean = true;
  
  // 云端备份状态
  @Local cloudBackups: RemoteBackupInfo[] = [];
  @Local isLoadingCloud: boolean = false;
  @Local syncStatus: WebDAVSyncStatus = {
    isUploading: false,
    isDownloading: false,
    uploadProgress: 0,
    downloadProgress: 0,
    lastSyncTime: 0
  };
  
  // WebDAV配置
  @Local webdavSettings: WebDAVSettings = {
    enabled: false,
    serverUrl: '',
    username: '',
    password: '',
    basePath: '/manxia',
    autoBackup: false,
    autoBackupInterval: 'manual',
    keepBackupCount: 5,
    lastSyncTime: 0,
    connectionStatus: 'untested',
    lastTestTime: 0,
    lastTestMessage: '',
    needCreateDir: false
  };
  @Local showWebDAVConfigDialog: boolean = false;
  @Local showInitCloudDialog: boolean = false;
  
  // 对话框状态
  @Local showBackupOptionsDialog: boolean = false;
  @Local showRestoreOptionsDialog: boolean = false;
  @Local showRestoreResultDialog: boolean = false;
  @Local currentRestoreBackup: BackupFileInfo | null = null;
  @Local restoreBackupData: BackupData | null = null;
  @Local restoreSuccess: boolean = false;
  @Local restoreErrorMessage: string = '';
  
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  
  aboutToAppear(): void {
    logger.info(TAG, '备份页面初始化');
    
    // 初始化主题并监听变化
    this.themeManager.getCurrentTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
    
    // 加载WebDAV配置
    this.loadWebDAVSettings();
    
    this.loadBackupFiles();
  }
  
  aboutToDisappear(): void {
    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
    this.lifecycle.destroy();
  }
  
  async loadWebDAVSettings(): Promise<void> {
    // 从本地存储加载WebDAV配置
    const savedSettings = await this.loadPersistedWebDAVSettings();
    
    if (savedSettings) {
      this.webdavSettings = savedSettings;
      logger.info(TAG, `已加载WebDAV配置: enabled=${savedSettings.enabled}, status=${savedSettings.connectionStatus}`);
      
      // 如果已启用且连接成功，配置WebDAV管理器
      if (savedSettings.enabled && savedSettings.connectionStatus === 'success') {
        const config: WebDAVConfig = {
          serverUrl: savedSettings.serverUrl,
          username: savedSettings.username,
          password: savedSettings.password,
          basePath: savedSettings.basePath
        };
        
        await this.webdavManager.configure(config);
        await this.loadCloudBackups();
      }
    } else {
      // 使用默认配置
      this.webdavSettings = {
        enabled: false,
        serverUrl: '',
        username: '',
        password: '',
        basePath: '/manxia',
        autoBackup: false,
        autoBackupInterval: 'manual',
        keepBackupCount: 5,
        lastSyncTime: 0,
        connectionStatus: 'untested',
        lastTestTime: 0,
        lastTestMessage: '',
        needCreateDir: false
      };
    }
  }
  
  async loadCloudBackups(): Promise<void> {
    if (!this.webdavManager.isConfigured()) {
      logger.warn(TAG, 'WebDAV未配置');
      return;
    }
    
    try {
      this.isLoadingCloud = true;
      
      // 检查索引文件是否存在
      const indexExists = await this.webdavManager.checkIndexExists();
      if (!indexExists) {
        logger.info(TAG, '云端索引文件不存在，需要初始化');
        this.showInitCloudDialog = true;
        this.cloudBackups = [];
        return;
      }
      
      this.cloudBackups = await this.webdavManager.listRemoteBackups();
      logger.info(TAG, `加载了 ${this.cloudBackups.length} 个云端备份`);
    } catch (error) {
      logger.error(TAG, `加载云端备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `加载云端备份失败: ${error}`,
        duration: 3000
      });
    } finally {
      this.isLoadingCloud = false;
    }
  }
  
  /**
   * 初始化云端备份
   */
  async initializeCloudBackup(): Promise<void> {
    try {
      this.showInitCloudDialog = false;
      
      this.getUIContext().getPromptAction().showToast({
        message: '正在初始化云端备份...',
        duration: 2000
      });
      
      // 创建索引文件
      await this.webdavManager.initializeCloudBackup();
      
      // 如果有本地备份，询问是否上传
      if (this.backupFiles.length > 0) {
        // 上传最新的本地备份
        const latestBackup = this.backupFiles[0];
        await this.uploadBackupToCloud(latestBackup.filePath);
      }
      
      this.getUIContext().getPromptAction().showToast({
        message: '云端备份初始化完成',
        duration: 2000
      });
      
      // 刷新云端备份列表
      await this.loadCloudBackups();
    } catch (error) {
      logger.error(TAG, `初始化云端备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `初始化失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  async uploadToCloud(localBackup: BackupFileInfo): Promise<void> {
    try {
      await this.webdavManager.uploadBackup(localBackup.filePath);
      this.getUIContext().getPromptAction().showToast({
        message: '上传成功',
        duration: 2000
      });
      await this.loadCloudBackups();
    } catch (error) {
      logger.error(TAG, `上传失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `上传失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  async downloadFromCloud(remoteBackup: RemoteBackupInfo): Promise<void> {
    try {
      const localPath = await this.webdavManager.downloadBackup(remoteBackup);
      this.getUIContext().getPromptAction().showToast({
        message: '下载成功',
        duration: 2000
      });
      await this.loadBackupFiles();
    } catch (error) {
      logger.error(TAG, `下载失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `下载失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  async deleteCloudBackup(remoteBackup: RemoteBackupInfo): Promise<void> {
    try {
      await this.webdavManager.deleteRemoteBackup(remoteBackup);
      this.getUIContext().getPromptAction().showToast({
        message: '删除成功',
        duration: 2000
      });
      await this.loadCloudBackups();
    } catch (error) {
      logger.error(TAG, `删除失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `删除失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  async saveWebDAVSettings(settings: WebDAVSettings): Promise<void> {
    try {
      logger.info(TAG, `保存WebDAV配置: enabled=${settings.enabled}, status=${settings.connectionStatus}`);
      
      // 如果需要创建目录且已启用
      // 注意：HarmonyOS不支持MKCOL方法，无法直接创建目录
      // 策略：跳过目录创建，在首次上传备份时目录会自动创建（如果服务器支持）
      // 或者提示用户在服务器端手动创建目录
      if (settings.enabled && settings.needCreateDir) {
        logger.info(TAG, `目录 ${settings.basePath} 不存在，将在首次上传时自动创建`);
        // 标记为成功，目录将在首次上传时创建
        settings.connectionStatus = 'success';
        settings.lastTestMessage = '连接成功，目录将在首次备份时自动创建';
        settings.needCreateDir = false;
      }
      
      // 如果已启用且连接成功，配置WebDAV管理器
      if (settings.enabled && settings.connectionStatus === 'success') {
        const config: WebDAVConfig = {
          serverUrl: settings.serverUrl,
          username: settings.username,
          password: settings.password,
          basePath: settings.basePath
        };
        
        await this.webdavManager.configure(config);
        await this.loadCloudBackups();
      }
      
      // 保存配置到本地存储（无论测试结果如何都保存）
      await this.persistWebDAVSettings(settings);
      
      this.webdavSettings = settings;
      this.showWebDAVConfigDialog = false;
      this.getUIContext().getPromptAction().showToast({
        message: 'WebDAV配置已保存',
        duration: 2000
      });
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存WebDAV配置失败: ${errorMsg}`);
      this.getUIContext().getPromptAction().showToast({
        message: `配置失败: ${errorMsg}`,
        duration: 3000
      });
    }
  }
  
  // 持久化保存WebDAV配置
  async persistWebDAVSettings(settings: WebDAVSettings): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: preferences.Options = { name: 'webdav_settings' };
      const dataPreferences: preferences.Preferences = await preferences.getPreferences(context, options);
      
      await dataPreferences.put('serverUrl', settings.serverUrl);
      await dataPreferences.put('username', settings.username);
      await dataPreferences.put('password', settings.password);
      await dataPreferences.put('basePath', settings.basePath);
      await dataPreferences.put('enabled', settings.enabled);
      await dataPreferences.put('autoBackup', settings.autoBackup);
      await dataPreferences.put('autoBackupInterval', settings.autoBackupInterval);
      await dataPreferences.put('keepBackupCount', settings.keepBackupCount);
      await dataPreferences.put('lastSyncTime', settings.lastSyncTime);
      await dataPreferences.put('connectionStatus', settings.connectionStatus);
      await dataPreferences.put('lastTestTime', settings.lastTestTime);
      await dataPreferences.put('lastTestMessage', settings.lastTestMessage);
      await dataPreferences.put('needCreateDir', settings.needCreateDir);
      await dataPreferences.flush();
      logger.info(TAG, 'WebDAV配置已持久化保存');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `持久化保存WebDAV配置失败: ${errorMsg}`);
    }
  }
  
  // 从本地存储加载WebDAV配置
  async loadPersistedWebDAVSettings(): Promise<WebDAVSettings | null> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const options: preferences.Options = { name: 'webdav_settings' };
      const dataPreferences: preferences.Preferences = await preferences.getPreferences(context, options);
      
      const serverUrl = dataPreferences.getSync('serverUrl', '') as string;
      
      if (!serverUrl) {
        return null;
      }
      
      const settings: WebDAVSettings = {
        serverUrl: serverUrl,
        username: dataPreferences.getSync('username', '') as string,
        password: dataPreferences.getSync('password', '') as string,
        basePath: dataPreferences.getSync('basePath', '/manxia') as string,
        enabled: dataPreferences.getSync('enabled', false) as boolean,
        autoBackup: dataPreferences.getSync('autoBackup', false) as boolean,
        autoBackupInterval: dataPreferences.getSync('autoBackupInterval', 'manual') as 'daily' | 'weekly' | 'manual',
        keepBackupCount: dataPreferences.getSync('keepBackupCount', 5) as number,
        lastSyncTime: dataPreferences.getSync('lastSyncTime', 0) as number,
        connectionStatus: dataPreferences.getSync('connectionStatus', 'untested') as 'untested' | 'testing' | 'success' | 'failed',
        lastTestTime: dataPreferences.getSync('lastTestTime', 0) as number,
        lastTestMessage: dataPreferences.getSync('lastTestMessage', '') as string,
        needCreateDir: dataPreferences.getSync('needCreateDir', false) as boolean
      };
      
      logger.info(TAG, `已加载WebDAV配置: ${settings.serverUrl}`);
      return settings;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `加载WebDAV配置失败: ${errorMsg}`);
      return null;
    }
  }
  
  async testWebDAVConnection(settings: WebDAVSettings): Promise<WebDAVTestResult> {
    try {
      const client = new WebDAVClient({
        serverUrl: settings.serverUrl,
        username: settings.username,
        password: settings.password,
        basePath: settings.basePath
      });
      
      return await client.testConnection();
    } catch (error) {
      logger.error(TAG, `测试WebDAV连接失败: ${error}`);
      const result: WebDAVTestResult = { 
        success: false, 
        needCreateDir: false, 
        message: `测试失败: ${error}` 
      };
      return result;
    }
  }
  
  async loadBackupFiles(): Promise<void> {
    try {
      this.isLoading = true;
      const sandboxManager = SandboxManager.getInstance();
      const filesDir = sandboxManager.getDirectory('files');
      const backupDir = `${filesDir}/backups`;
      
      if (!await sandboxManager.exists(backupDir)) {
        logger.info(TAG, '备份目录不存在');
        this.backupFiles = [];
        return;
      }
      
      const files = await fileIo.listFile(backupDir);
      const backupInfos: BackupFileInfo[] = [];
      
      for (const fileName of files) {
        if (fileName.endsWith('.json') || fileName.endsWith('.mxbackup')) {
          const filePath = `${backupDir}/${fileName}`;
          try {
            const stat = await fileIo.stat(filePath);
            let metadata: BackupMetadata;
            
            if (fileName.endsWith('.mxbackup')) {
              metadata = await this.enhancedBackupManager.getBackupMetadata(filePath);
            } else {
              metadata = await this.backupManager.getBackupMetadata(filePath);
            }
            
            backupInfos.push({
              fileName: fileName,
              filePath: filePath,
              fileSize: stat.size,
              metadata: metadata
            });
          } catch (error) {
            logger.error(TAG, `读取备份文件失败: ${fileName}, ${error}`);
          }
        }
      }
      
      this.backupFiles = backupInfos.sort((a, b) => b.metadata.timestamp - a.metadata.timestamp);
      logger.info(TAG, `加载了 ${this.backupFiles.length} 个备份文件`);
    } catch (error) {
      logger.error(TAG, `加载备份文件列表失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '加载失败' });
    } finally {
      this.isLoading = false;
    }
  }
  
  showBackupOptions(): void {
    this.showBackupOptionsDialog = true;
  }

  async createBackupWithOptions(options: BackupOptions): Promise<void> {
    try {
      this.isCreatingBackup = true;
      this.showBackupOptionsDialog = false;
      
      const filePath = await this.enhancedBackupManager.createBackup(options);
      
      this.getUIContext().getPromptAction().showToast({
        message: '备份创建成功',
        duration: 2000
      });
      
      await this.loadBackupFiles();
      
      // 如果WebDAV已启用且连接成功，自动上传到云端
      if (this.webdavSettings.enabled && this.webdavSettings.connectionStatus === 'success') {
        await this.uploadBackupToCloud(filePath);
      }
    } catch (error) {
      logger.error(TAG, `创建备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `创建备份失败: ${error}`,
        duration: 3000
      });
    } finally {
      this.isCreatingBackup = false;
    }
  }
  
  /**
   * 上传备份文件到WebDAV云端
   */
  async uploadBackupToCloud(localFilePath: string): Promise<void> {
    try {
      logger.info(TAG, `开始上传备份到云端: ${localFilePath}`);
      
      this.getUIContext().getPromptAction().showToast({
        message: '正在上传到云端...',
        duration: 2000
      });
      
      await this.webdavManager.uploadBackup(localFilePath);
      
      this.getUIContext().getPromptAction().showToast({
        message: '已同步到云端',
        duration: 2000
      });
      
      // 更新最后同步时间
      this.webdavSettings.lastSyncTime = Date.now();
      await this.persistWebDAVSettings(this.webdavSettings);
      
      // 刷新云端备份列表
      await this.loadCloudBackups();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `上传失败: ${errorMsg}`);
      this.getUIContext().getPromptAction().showToast({
        message: `云端同步失败: ${errorMsg}`,
        duration: 3000
      });
    }
  }

  async createBackup(): Promise<void> {
    this.showBackupOptions();
  }
  
  async showRestoreOptions(backupInfo: BackupFileInfo): Promise<void> {
    try {
      // 读取备份元数据（getBackupMetadata内部会解压并读取数据）
      const metadata = await this.enhancedBackupManager.getBackupMetadata(backupInfo.filePath);
      
      // 由于我们需要完整的备份数据来显示详情，这里需要再次解压读取
      // 使用公共API而不是私有方法
      const sandboxManager = SandboxManager.getInstance();
      const tempDir = `${sandboxManager.getDirectory('cache')}/restore_preview_${Date.now()}`;
      
      // 创建临时目录
      if (!await sandboxManager.exists(tempDir)) {
        await sandboxManager.createDirectory(tempDir);
      }
      
      // 使用getTarPackager获取公共实例
      const tarPackager = await import('../Framework/Utils/TarPackager').then(m => m.getTarPackager());
      await tarPackager.extractTarArchive(backupInfo.filePath, tempDir);
      
      // 读取JSON文件
      const jsonPath = `${tempDir}/backup.json`;
      const jsonBuffer = await sandboxManager.readFile(jsonPath);
      const jsonContent = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(jsonBuffer));
      const backupData = JSON.parse(jsonContent) as BackupData;
      
      // 清理临时目录
      await sandboxManager.deleteDirectory(tempDir);
      
      this.currentRestoreBackup = backupInfo;
      this.restoreBackupData = backupData;
      this.showRestoreOptionsDialog = true;
    } catch (error) {
      logger.error(TAG, `读取备份数据失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `读取备份失败: ${error}`,
        duration: 3000
      });
    }
  }

  async restoreBackupWithOptions(options: RestoreOptions): Promise<void> {
    try {
      this.isRestoringBackup = true;
      this.showRestoreOptionsDialog = false;
      
      if (this.currentRestoreBackup && this.currentRestoreBackup.fileName.endsWith('.mxbackup')) {
        await this.enhancedBackupManager.restoreBackupWithOptions(this.currentRestoreBackup.filePath, options);
      } else if (this.currentRestoreBackup) {
        await this.backupManager.restoreBackup(this.currentRestoreBackup.filePath);
      }
      
      this.restoreSuccess = true;
      this.restoreErrorMessage = '';
      this.showRestoreResultDialog = true;
    } catch (error) {
      logger.error(TAG, `恢复备份失败: ${error}`);
      this.restoreSuccess = false;
      this.restoreErrorMessage = String(error);
      this.showRestoreResultDialog = true;
    } finally {
      this.isRestoringBackup = false;
    }
  }

  async restartApp(): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      if (!uiCtx) {
        logger.error(TAG, '获取UIContext失败，无法重启应用');
        return;
      }
      const context = uiCtx.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext，无法重启应用');
        return;
      }

      const want: Want = {
        bundleName: 'com.dlzz.manxia',
        abilityName: 'EntryAbility'
      };

      await context.startAbility(want);
      context.terminateSelf();
    } catch (error) {
      logger.error(TAG, '重启应用失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '请手动重启应用',
        duration: 3000
      });
    }
  }
  
  async exportBackup(backupInfo: BackupFileInfo): Promise<void> {
    try {
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [backupInfo.fileName];
      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.save(documentSaveOptions);
      
      if (uris && uris.length > 0) {
        const sourceFile = await fileIo.open(backupInfo.filePath, fileIo.OpenMode.READ_ONLY);
        const destFile = await fileIo.open(uris[0], fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        
        const stat = await fileIo.stat(backupInfo.filePath);
        const buffer = new ArrayBuffer(stat.size);
        await fileIo.read(sourceFile.fd, buffer);
        await fileIo.write(destFile.fd, buffer);
        
        await fileIo.close(sourceFile);
        await fileIo.close(destFile);
        
        this.getUIContext().getPromptAction().showToast({
          message: '备份文件已导出',
          duration: 2000
        });
      }
    } catch (error) {
      logger.error(TAG, `导出备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `导出备份失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  async importBackup(): Promise<void> {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.select(documentSelectOptions);
      
      if (uris && uris.length > 0) {
        const sourceFile = await fileIo.open(uris[0], fileIo.OpenMode.READ_ONLY);
        const stat = await fileIo.stat(sourceFile.fd);
        const buffer = new ArrayBuffer(stat.size);
        await fileIo.read(sourceFile.fd, buffer);
        await fileIo.close(sourceFile);
        
        const sandboxManager = SandboxManager.getInstance();
        const filesDir = sandboxManager.getDirectory('files');
        const backupDir = `${filesDir}/backups`;
        
        if (!await sandboxManager.exists(backupDir)) {
          await sandboxManager.createDirectory(backupDir);
        }
        
        const fileName = `imported_backup_${Date.now()}.json`;
        const destPath = `${backupDir}/${fileName}`;
        const destFile = await fileIo.open(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        await fileIo.write(destFile.fd, buffer);
        await fileIo.close(destFile);
        
        await this.loadBackupFiles();
        
        this.getUIContext().getPromptAction().showToast({
          message: '备份文件已导入',
          duration: 2000
        });
      }
    } catch (error) {
      logger.error(TAG, `导入备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `导入备份失败: ${error}`,
        duration: 3000
      });
    }
  }
  
  deleteBackup(backupInfo: BackupFileInfo): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除备份文件 ${backupInfo.fileName} 吗？`,
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF0000' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        try {
          await fileIo.unlink(backupInfo.filePath);
          await this.loadBackupFiles();
          this.getUIContext().getPromptAction().showToast({
            message: '备份已删除',
            duration: 2000
          });
        } catch (error) {
          logger.error(TAG, `删除备份失败: ${error}`);
          this.getUIContext().getPromptAction().showToast({
            message: `删除失败: ${error}`,
            duration: 2000
          });
        }
      }
    });
  }
  
  formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }
  
  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  @Builder
  buildBackupOptionsDialog() {
    if (this.showBackupOptionsDialog) {
      BackupOptionsDialog({
        onConfirm: (options: BackupOptions) => {
          this.createBackupWithOptions(options);
        },
        onCancel: () => {
          this.showBackupOptionsDialog = false;
        },
        currentTheme: this.themeState.currentTheme
      })
    }
  }

  @Builder
  buildRestoreOptionsDialog() {
    if (this.showRestoreOptionsDialog && this.restoreBackupData && this.currentRestoreBackup) {
      RestoreOptionsDialog({
        backupData: this.restoreBackupData,
        metadata: this.currentRestoreBackup.metadata,
        onConfirm: (options: RestoreOptions) => {
          this.restoreBackupWithOptions(options);
        },
        onCancel: () => {
          this.showRestoreOptionsDialog = false;
          this.currentRestoreBackup = null;
          this.restoreBackupData = null;
        },
        currentTheme: this.themeState.currentTheme
      })
    }
  }

  @Builder
  buildRestoreResultDialog() {
    if (this.showRestoreResultDialog) {
      Column() {
        Column() {
          // 标题
          Text(this.restoreSuccess ? '恢复成功' : '恢复失败')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .padding({ top: 20, bottom: 16 })
          
          // 内容
          Scroll() {
            Column() {
              if (this.restoreSuccess) {
                Text('✅ 备份数据已成功恢复')
                  .fontSize(16)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .margin({ bottom: 12 })
                
                Text('请重启APP以应用所有更改')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              } else {
                Text('❌ 恢复过程中出现错误')
                  .fontSize(16)
                  .fontColor('#FF0000')
                  .margin({ bottom: 12 })
                
                Text(this.restoreErrorMessage)
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(5)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .height('40%')
          .scrollBar(BarState.Auto)
          
          // 底部按钮
          Row() {
            if (this.restoreSuccess) {
              Button('稍后重启')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => {
                  this.showRestoreResultDialog = false;
                  this.currentRestoreBackup = null;
                  this.restoreBackupData = null;
                })
              
              Blank().width(16)
              
              Button('重启APP')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => {
                  this.restartApp();
                })
            } else {
              Button('关闭')
                .fontSize(16)
                .fontColor('#FFFFFF')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(8)
                .width('100%')
                .onClick(() => {
                  this.showRestoreResultDialog = false;
                  this.currentRestoreBackup = null;
                  this.restoreBackupData = null;
                })
            }
          }
          .width('100%')
          .padding({ top: 16, bottom: 20 })
        }
        .width('90%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(16)
        .padding({ left: 20, right: 20 })
        .scale({ x: 1, y: 1 })
        .opacity(1)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }).animation({ duration: 300, curve: Curve.EaseOut })))
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .justifyContent(FlexAlign.Center)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
    }
  }

  
  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Column() {
          Blank().height(TITLE_BAR_HEIGHT_MINI)
          
          // Tab切换栏
          this.buildTabBar()
          
          // 内容区域
          Scroll() {
            Column() {
              // 存储概览（仅云端Tab显示）
              if (this.currentTab === 'cloud') {
                this.buildStorageOverview()
              }
              
              // 备份列表
              if (this.currentTab === 'local') {
                this.buildLocalBackupList()
              } else {
                this.buildCloudBackupList()
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        
        // 对话框层
        this.buildBackupOptionsDialog()
        this.buildRestoreOptionsDialog()
        this.buildRestoreResultDialog()
        this.buildWebDAVConfigDialog()
        this.buildInitCloudDialog()
      }
      .width('100%')
      .height('100%')
    }
  .hideTitleBar(false)
    .mode(NavDestinationMode.STANDARD)
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '备份与恢复' }
      }
    })
  }
  
  @Builder
  buildTabBar() {
    Row() {
      // 本地Tab
      Column() {
        Text('本地备份')
          .fontSize(16)
          .fontWeight(this.currentTab === 'local' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(
            this.currentTab === 'local'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
          )
        
        if (this.currentTab === 'local') {
          Divider()
            .width(40)
            .height(3)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .borderRadius(2)
        }
      }
      .layoutWeight(1)
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        this.currentTab = 'local';
      })
      
      // 云端Tab
      Column() {
        Row() {
          Text('云端备份')
            .fontSize(16)
            .fontWeight(this.currentTab === 'cloud' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(
              this.currentTab === 'cloud'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
            )
          
          if (this.webdavSettings.enabled) {
            Text('●')
              .fontSize(8)
              .fontColor('#00C853')
              .margin({ left: 4 })
          }
        }
        
        if (this.currentTab === 'cloud') {
          Divider()
            .width(40)
            .height(3)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .borderRadius(2)
        }
      }
      .layoutWeight(1)
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        this.currentTab = 'cloud';
        if (this.webdavSettings.enabled && this.cloudBackups.length === 0) {
          this.loadCloudBackups();
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
  }

  @Builder
  buildStorageOverview() {
    Column() {
      Row() {
        Text('☁️ 云端存储')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 设置按钮
        Text('⚙️')
          .fontSize(20)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .onClick(() => {
            this.showWebDAVConfigDialog = true;
          })
      }
      .width('100%')
      .padding(16)
      
      // 存储空间卡片
      Column() {
        if (this.webdavSettings.enabled && this.webdavSettings.connectionStatus === 'success') {
          // 已配置并连接成功
          Column() {
            Row() {
              Text('✅ 已连接')
                .fontSize(14)
                .fontColor('#FFFFFF')
              
              Blank()
              
              Text(`${this.cloudBackups.length} 个备份`)
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
            .width('100%')
            .margin({ bottom: 12 })
            
            // 服务器地址
            Text(this.webdavSettings.serverUrl)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .opacity(0.8)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ bottom: 8 })
            
            // 同步状态
            this.buildSyncStatus()
            
            // 操作按钮
            Row() {
              // 编辑按钮
              Button() {
                Row() {
                  Image($r('sys.media.ohos_ic_public_edit'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFFFFF')
                  Text('编辑')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                    .margin({ left: 4 })
                }
              }
              .backgroundColor('rgba(255, 255, 255, 0.2)')
              .borderRadius(6)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.showWebDAVConfigDialog = true;
              })
              
              Blank().width(12)
              
              // 断开连接按钮
              Button() {
                Row() {
                  Image($r('sys.media.ohos_ic_public_cancel'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFFFFF')
                  Text('断开')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                    .margin({ left: 4 })
                }
              }
              .backgroundColor('rgba(255, 255, 255, 0.2)')
              .borderRadius(6)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.webdavSettings.enabled = false;
                this.webdavSettings.connectionStatus = 'untested';
                this.persistWebDAVSettings(this.webdavSettings);
                this.cloudBackups = [];
              })
              
              Blank().width(12)
              
              // 删除配置按钮
              Button() {
                Row() {
                  Image($r('sys.symbol.clean_fill'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFFFFF')
                }
              }
              .backgroundColor('rgba(255, 82, 82, 0.6)')
              .borderRadius(6)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => {
                // 清空配置
                this.webdavSettings = {
                  enabled: false,
                  serverUrl: '',
                  username: '',
                  password: '',
                  basePath: '/manxia',
                  autoBackup: false,
                  autoBackupInterval: 'manual',
                  keepBackupCount: 5,
                  lastSyncTime: 0,
                  connectionStatus: 'untested',
                  lastTestTime: 0,
                  lastTestMessage: '',
                  needCreateDir: false
                };
                this.persistWebDAVSettings(this.webdavSettings);
                this.cloudBackups = [];
                this.getUIContext().getPromptAction().showToast({
                  message: '云存储配置已删除',
                  duration: 2000
                });
              })
            }
            .width('100%')
            .margin({ top: 12 })
            .justifyContent(FlexAlign.Start)
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .linearGradient({
            angle: 135,
            colors: [[0x667EEA, 0.0], [0x764BA2, 1.0]]
          })
          .shadow({
            radius: 20,
            color: 'rgba(102, 126, 234, 0.3)',
            offsetX: 0,
            offsetY: 4
          })
        } else if (this.webdavSettings.serverUrl) {
          // 已配置但未启用或连接失败
          Column() {
            Row() {
              Text(this.webdavSettings.connectionStatus === 'failed' ? '❌ 连接失败' : 
                   this.webdavSettings.connectionStatus === 'untested' ? '❓ 未测试' : '⏳ 待启用')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Blank()
              
              Toggle({ type: ToggleType.Switch, isOn: this.webdavSettings.enabled })
                .onChange((isOn: boolean) => {
                  this.webdavSettings.enabled = isOn;
                  this.persistWebDAVSettings(this.webdavSettings);
                  if (isOn && this.webdavSettings.connectionStatus === 'success') {
                    this.loadCloudBackups();
                  }
                })
            }
            .width('100%')
            .margin({ bottom: 8 })
            
            // 服务器地址
            Text(this.webdavSettings.serverUrl)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ bottom: 4 })
            
            // 上次测试消息
            if (this.webdavSettings.lastTestMessage) {
              Text(this.webdavSettings.lastTestMessage)
                .fontSize(11)
                .fontColor(this.webdavSettings.connectionStatus === 'failed' ? '#FF5252' : 
                           ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ bottom: 8 })
            }
            
            Row() {
              Button('测试连接')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor('transparent')
                .borderRadius(6)
                .border({
                  width: 1,
                  color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                })
                .onClick(async () => {
                  const result = await this.testWebDAVConnection(this.webdavSettings);
                  this.webdavSettings.connectionStatus = result.success ? 'success' : 'failed';
                  this.webdavSettings.lastTestTime = Date.now();
                  this.webdavSettings.lastTestMessage = result.message;
                  this.webdavSettings.needCreateDir = result.needCreateDir;
                  await this.persistWebDAVSettings(this.webdavSettings);
                })
              
              Blank().width(8)
              
              Button('编辑配置')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(6)
                .onClick(() => {
                  this.showWebDAVConfigDialog = true;
                })
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .border({
            width: 1,
            color: this.webdavSettings.connectionStatus === 'failed' ? '#FF5252' : 
                   ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
          })
        } else {
          // 未配置WebDAV
          Column() {
            Text('🔒 未配置云端备份')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ bottom: 8 })
            
            Text('点击右上角设置按钮配置WebDAV')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ bottom: 16 })
            
            Button('立即配置')
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.showWebDAVConfigDialog = true;
              })
          }
          .width('100%')
          .padding(20)
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme),
            style: BorderStyle.Dashed
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
  }

  @Builder
  buildSyncStatus() {
    if (this.syncStatus.isUploading || this.syncStatus.isDownloading) {
      Row() {
        LoadingProgress()
          .width(16)
          .height(16)
          .color('#FFFFFF')
        
        Text(this.syncStatus.isUploading ? '上传中...' : '下载中...')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .margin({ left: 8 })
        
        Text(`${Math.round((this.syncStatus.isUploading ? this.syncStatus.uploadProgress : this.syncStatus.downloadProgress) * 100)}%`)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .margin({ left: 8 })
      }
    } else if (this.syncStatus.lastSyncTime > 0) {
      Text(`最后同步: ${this.formatDate(this.syncStatus.lastSyncTime)}`)
        .fontSize(12)
        .fontColor('#FFFFFF')
        .opacity(0.8)
    }
  }

  @Builder
  buildLocalBackupList() {
    Column() {
      // 操作按钮
      Row() {
        Button('创建备份')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .enabled(!this.isCreatingBackup && !this.isRestoringBackup)
          .onClick(() => this.createBackup())
        
        Blank().width(12)
        
        Button('导入备份')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .enabled(!this.isCreatingBackup && !this.isRestoringBackup)
          .onClick(() => this.importBackup())
      }
      .width('100%')
      .padding(16)
      
      // 创建中提示
      if (this.isCreatingBackup) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          
          Text('正在创建备份...')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ left: 8 })
        }
        .padding({ left: 16, right: 16, bottom: 16 })
      }
      
      // 备份列表
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          
          Text('加载中...')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 16 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else if (this.backupFiles.length === 0) {
        Column() {
          Text('📦')
            .fontSize(48)
            .margin({ bottom: 16 })
          
          Text('暂无本地备份')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('点击"创建备份"开始备份数据')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          ForEach(this.backupFiles, (backup: BackupFileInfo) => {
            this.buildBackupCard(backup, 'local')
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  buildCloudBackupList() {
    Column() {
      if (!this.webdavSettings.enabled) {
        Column() {
          Text('☁️')
            .fontSize(48)
            .margin({ bottom: 16 })
          
          Text('云端备份未启用')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('请先配置WebDAV')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else if (this.isLoadingCloud) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          
          Text('加载云端备份...')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 16 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else if (this.cloudBackups.length === 0) {
        Column() {
          Text('☁️')
            .fontSize(48)
            .margin({ bottom: 16 })
          
          Text('暂无云端备份')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('上传本地备份到云端')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          ForEach(this.cloudBackups, (backup: RemoteBackupInfo) => {
            this.buildCloudBackupCard(backup)
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  buildBackupCard(backup: BackupFileInfo, type: 'local') {
    Column() {
      Row() {
        Column() {
          Text(this.formatDate(backup.metadata.timestamp))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(`${this.formatFileSize(backup.fileSize)} · ${backup.metadata.appVersion}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
          
          Row() {
            Text(`📚 ${backup.metadata.itemCounts.manga}`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            Text(`📖 ${backup.metadata.itemCounts.novel}`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 12 })
            
            Text(`📄 ${backup.metadata.itemCounts.ebook}`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 12 })
          }
          .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Column() {
          Button('恢复')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .enabled(!this.isRestoringBackup)
            .onClick(() => this.showRestoreOptions(backup))
          
          if (this.webdavSettings.enabled) {
            Button('上传')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .margin({ top: 8 })
              .onClick(() => this.uploadToCloud(backup))
          }
          
          Button('导出')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ top: 8 })
            .onClick(() => this.exportBackup(backup))
          
          Button('删除')
            .fontSize(14)
            .fontColor('#FF0000')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ top: 8 })
            .onClick(() => this.deleteBackup(backup))
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .shadow({
        radius: 8,
        color: 'rgba(0, 0, 0, 0.1)',
        offsetX: 0,
        offsetY: 2
      })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  buildCloudBackupCard(backup: RemoteBackupInfo) {
    Column() {
      Row() {
        Column() {
          Text(this.formatDate(backup.lastModified))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(`${this.formatFileSize(backup.size)} · ${backup.fileName}`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
          
          Row() {
            Text('☁️ 云端备份')
              .fontSize(12)
              .fontColor('#667EEA')
          }
          .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Column() {
          Button('下载')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => this.downloadFromCloud(backup))
          
          Button('删除')
            .fontSize(14)
            .fontColor('#FF0000')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ top: 8 })
            .onClick(() => this.deleteCloudBackup(backup))
        }
      }
      .width('100%')
      .padding(16)
      .borderRadius(12)
      .linearGradient({
        angle: 135,
        colors: [[0xE8EAF6, 0.0], [0xF3E5F5, 1.0]]
      })
      .shadow({
        radius: 12,
        color: 'rgba(102, 126, 234, 0.2)',
        offsetX: 0,
        offsetY: 4
      })
      .margin({ top: 12 })
    }
    .width('100%')
  }

  @Builder
  buildWebDAVConfigDialog() {
    if (this.showWebDAVConfigDialog) {
      WebDAVConfigDialog({
        settings: this.webdavSettings,
        onConfirm: (settings: WebDAVSettings) => {
          this.saveWebDAVSettings(settings);
        },
        onCancel: () => {
          this.showWebDAVConfigDialog = false;
        },
        onTest: (settings: WebDAVSettings) => {
          return this.testWebDAVConnection(settings);
        },
        currentTheme: this.themeState.currentTheme
      })
    }
  }
  
  @Builder
  buildInitCloudDialog() {
    if (this.showInitCloudDialog) {
      Column() {
        Column() {
          Text('初始化云端备份')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .margin({ bottom: 16 })
          
          Text('检测到云端尚未初始化备份索引。\n\n是否立即初始化？初始化后将自动上传最新的本地备份到云端。')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .lineHeight(22)
            .margin({ bottom: 24 })
          
          Row() {
            Button('取消')
              .fontSize(16)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                this.showInitCloudDialog = false;
              })
            
            Blank().width(16)
            
            Button('初始化')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                this.initializeCloudBackup();
              })
          }
          .width('100%')
        }
        .width('80%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(16)
        .padding(24)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .justifyContent(FlexAlign.Center)
    }
  }
}

export { BackupPage }

interface BackupFileInfo {
  fileName: string;
  filePath: string;
  fileSize: number;
  metadata: BackupMetadata;
}
