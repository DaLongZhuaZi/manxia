import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 备份与恢复页面
 * 支持导出和导入所有应用数据
 * 
 * 文件路径: entry/src/main/ets/pages/BackupPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getBackupManager } from '../Framework/Managers/BackupManager';
import { getEnhancedBackupManager, RestoreOptions } from '../Framework/Managers/EnhancedBackupManager';
import { BackupData, BackupMetadata, BackupOptions, DEFAULT_BACKUP_OPTIONS } from '../Models/BackupModels';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import { picker, fileIo, fileUri as coreFileUri } from '@kit.CoreFileKit';
import { BackupOptionsDialog } from '../components/backup/BackupOptionsDialog';
import { RestoreOptionsDialog } from '../components/backup/RestoreOptionsDialog';
import { WebDAVConfigDialog } from '../components/backup/WebDAVConfigDialog';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { getWebDAVBackupManager, RemoteBackupInfo, WebDAVSyncStatus } from '../Framework/WebDAV/WebDAVBackupManager';
import { WebDAVSettings, DEFAULT_WEBDAV_SETTINGS } from '../Models/WebDAVModels';
import { WebDAVClient, WebDAVConfig, WebDAVTestResult } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVClient';
import { quickTestWebDAVNative } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVNativeTest';
import { WebDAVNativeConfig, WebDAVNativeClient, isNativeModuleAvailable } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVNativeClient';
import { WebDAVErrorAnalyzer, analyzeWebDAVError } from 'manxia_network/src/main/ets/Framework/WebDAV/WebDAVErrorAnalyzer';
import { FTPConfig, FTPNativeClient, FTPFileInfo, isFTPNativeAvailable } from 'manxia_network/src/main/ets/Framework/FTP/FTPNativeClient';
import { SavedFTPConnection, DEFAULT_FTP_CONNECTION, createFTPConnection } from '../Models/FTPModels';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { SettingsSearchSupport } from './settings/SettingsSearchSupport';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { ExternalFileTaskParamStore } from 'manxia_network/src/main/ets/Framework/ExternalFile/ExternalFileTaskParamStore';

const TAG = 'BackupPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const APP_STORAGE_TRANSFER_RECORD_ID = 'pendingTransferRecordId';
const APP_STORAGE_TRANSFER_RESULT = 'pendingTransferImportResult';
const APP_STORAGE_TRANSFER_TRACKING_ACTIVE = 'pendingTransferTrackingActive';
const BACKUP_COPY_BUFFER_SIZE: number = 1024 * 1024;

interface ThemeState {
  currentTheme: ThemeType;
}

interface NativeTestResult {
  testName: string;
  success: boolean;
  message: string;
  duration: number;
}

interface NativeTestConfig {
  testConnection: boolean;
  testList: boolean;
  testCreateDir: boolean;
  testUpload: boolean;
  testDownload: boolean;
  testDelete: boolean;
  testQuota: boolean;
  customTestPath: string;
  customTestContent: string;
}

interface FileCopyProgress {
  bytesCopied: number;
  totalBytes: number;
}

interface NavDestinationPathInfo {
  param?: Object;
}

interface NavDestinationContext {
  pathStack: NavPathStack;
  pathInfo?: NavDestinationPathInfo;
}

export interface BackupExternalImportParams {
  externalBackupUri?: string;
  externalTaskInstanceId?: string;
}

@ComponentV2
struct BackupPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  @Local fontState: FontAwareState = new FontAwareState();
  @Local appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('BackupPage', { enableDebug: true });
  private backupManager = getBackupManager();
  private enhancedBackupManager = getEnhancedBackupManager();
  private webdavManager = getWebDAVBackupManager();
  pathStack: NavPathStack = new NavPathStack();
  private routeExternalBackupUri: string = '';
  private routeExternalTaskInstanceId: string = '';
  private hasHandledRouteExternalBackup: boolean = false;
  
  // Tab状态
  @Local currentTab: 'local' | 'cloud' | 'native_test' | 'ftp' = 'local';
  @Local searchHighlightTab: 'local' | 'cloud' | 'native_test' | 'ftp' | '' = '';
  @Local appGuideStep: AppGuideStep | null = null;
  @Local appGuideHighlightRect: GuideHighlightRect | null = null;
  
  // 横向滑动切换标签页相关状态
  private readonly tabOrder: ('local' | 'cloud' | 'native_test' | 'ftp')[] = ['local', 'cloud', 'native_test', 'ftp'];
  @Local private swipeStartX: number = 0;
  @Local private swipeOffsetX: number = 0;
  private scroller: Scroller = new Scroller();
  
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
    autoBackupInterval: 'daily',
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
  
  // Native测试状态
  @Local nativeTestRunning: boolean = false;
  @Local nativeTestResults: NativeTestResult[] = [];
  @Local nativeTestSummary: string = '';
  @Local nativeTestConfig: NativeTestConfig = {
    testConnection: true,
    testList: true,
    testCreateDir: true,
    testUpload: true,
    testDownload: true,
    testDelete: true,
    testQuota: true,
    customTestPath: '',
    customTestContent: ''
  };
  
  // FTP管理器状态
  @Local savedFTPConnections: SavedFTPConnection[] = [];
  @Local currentFTPConnection: SavedFTPConnection | null = null;
  @Local ftpEditingConnection: SavedFTPConnection | null = null;
  @Local ftpConnected: boolean = false;
  @Local ftpCurrentPath: string = '/';
  @Local ftpFiles: FTPFileInfo[] = [];
  @Local ftpLoading: boolean = false;
  @Local ftpClient: FTPNativeClient | null = null;
  @Local showFTPEditDialog: boolean = false;
  @Local ftpTestResult: string = '';
  @Local ftpConnectionName: string = '';
  
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  private webdavInitPromise: Promise<boolean> | null = null;
  private webdavConfigKey: string = '';
  private cloudSyncTimer: number | undefined = undefined;
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  
  /**
   * 切换到下一个标签页（支持循环）
   */
  private switchToNextTab(): void {
    const currentIndex = this.tabOrder.indexOf(this.currentTab);
    const nextIndex = (currentIndex + 1) % this.tabOrder.length;
    this.currentTab = this.tabOrder[nextIndex];
    this.onTabChanged();
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('BackupPage');
    if (!target) {
      return;
    }
    let nextTab: 'local' | 'cloud' | 'native_test' | 'ftp' = 'local';
    if (target.anchorId === 'backup_cloud') {
      nextTab = 'cloud';
    } else if (target.anchorId === 'backup_ftp') {
      nextTab = 'ftp';
    } else if (target.anchorId === 'backup_native') {
      nextTab = 'native_test';
    }

    this.currentTab = nextTab;
    this.onTabChanged();
    this.searchHighlightTab = nextTab;
    setTimeout(() => {
      this.searchHighlightTab = '';
    }, 2200);
  }

  private getTabBackground(tabId: 'local' | 'cloud' | 'native_test' | 'ftp'): ResourceColor {
    if (this.searchHighlightTab === tabId) {
      return this.themeState.currentTheme === ThemeType.DARK ? 'rgba(102, 180, 255, 0.16)' : 'rgba(24, 144, 255, 0.12)';
    }
    if (this.currentTab === tabId) {
      return ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme);
    }
    return Color.Transparent;
  }

  private getTabTopBorderWidth(tabId: 'local' | 'cloud' | 'native_test' | 'ftp'): number {
    return (this.currentTab === tabId || this.searchHighlightTab === tabId) ? 2 : 0;
  }
  
  /**
   * 切换到上一个标签页（支持循环）
   */
  private switchToPrevTab(): void {
    const currentIndex = this.tabOrder.indexOf(this.currentTab);
    const prevIndex = (currentIndex - 1 + this.tabOrder.length) % this.tabOrder.length;
    this.currentTab = this.tabOrder[prevIndex];
    this.onTabChanged();
  }
  
  /**
   * 标签页切换后的回调
   */
  private onTabChanged(): void {
    if (this.currentTab === 'cloud' && this.webdavSettings.enabled && this.cloudBackups.length === 0) {
      this.scheduleLoadCloudBackups(80);
    }
  }

  private getWebDAVConfigKey(settings: WebDAVSettings): string {
    return `${settings.serverUrl}|${settings.username}|${settings.basePath}|${settings.enabled}|${settings.connectionStatus}`;
  }

  private scheduleLoadCloudBackups(delayMs: number = 0): void {
    if (this.cloudSyncTimer !== undefined) {
      clearTimeout(this.cloudSyncTimer);
      this.cloudSyncTimer = undefined;
    }
    this.cloudSyncTimer = setTimeout(() => {
      this.cloudSyncTimer = undefined;
      this.loadCloudBackups();
    }, delayMs) as number;
  }

  private async ensureWebDAVReady(forceReconfigure: boolean = false): Promise<boolean> {
    if (!this.webdavSettings.enabled || this.webdavSettings.connectionStatus !== 'success') {
      return false;
    }

    const configKey = this.getWebDAVConfigKey(this.webdavSettings);
    if (!forceReconfigure && this.webdavManager.isConfigured() && this.webdavConfigKey === configKey) {
      return true;
    }

    if (this.webdavInitPromise) {
      return await this.webdavInitPromise;
    }

    this.webdavInitPromise = (async (): Promise<boolean> => {
      try {
        const config: WebDAVConfig = {
          serverUrl: this.webdavSettings.serverUrl,
          username: this.webdavSettings.username,
          password: this.webdavSettings.password,
          basePath: this.webdavSettings.basePath
        };
        await this.webdavManager.configure(config);
        this.webdavConfigKey = configKey;
        return true;
      } catch (error) {
        logger.error(TAG, `初始化WebDAV连接失败: ${error}`);
        return false;
      }
    })();

    try {
      return await this.webdavInitPromise;
    } finally {
      this.webdavInitPromise = null;
    }
  }
  
  aboutToAppear(): void {
    logger.info(TAG, '备份页面初始化');
    
    // 初始化字体管理
    try {
      const storedFont = AppStorage.get<string>('appFontFamily');
      if (storedFont) {
        this.appFontFamily = storedFont;
      }
    } catch (e) {
      logger.warn(TAG, '获取存储字体失败');
    }
    
    // 初始化主题并监听变化（使用getActualTheme获取实际显示的主题）
    this.themeManager.getActualTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);
    
    // 加载WebDAV配置
    this.loadWebDAVSettings();
    
    // 加载FTP连接配置
    this.loadFTPConnections();
    
    this.loadBackupFiles();
    
    // 检查是否有外部导入的备份文件
    if (!this.handleRouteExternalBackupImport('aboutToAppear')) {
      this.checkPendingBackupImport();
    }
    this.applyPendingSearchTarget();
    setTimeout(() => {
      void this.refreshPageGuide('aboutToAppear');
    }, 120);
  }

  private setRouteExternalBackupParams(params: BackupExternalImportParams | undefined): void {
    if (!params || !params.externalBackupUri || params.externalBackupUri.length <= 0) {
      return;
    }
    this.routeExternalBackupUri = params.externalBackupUri;
    this.routeExternalTaskInstanceId = params.externalTaskInstanceId ?? '';
    logger.info(TAG, `已接收独立备份恢复任务参数: uri=${this.routeExternalBackupUri}, instance=${this.routeExternalTaskInstanceId}`);
    this.handleRouteExternalBackupImport('onReady');
  }

  private handleRouteExternalBackupImport(source: string): boolean {
    if (this.hasHandledRouteExternalBackup || this.routeExternalBackupUri.length <= 0) {
      return false;
    }
    this.hasHandledRouteExternalBackup = true;
    setTimeout((): void => {
      void this.importBackupFromUri(this.routeExternalBackupUri);
    }, 500);
    logger.info(TAG, `已调度独立备份恢复任务: source=${source}, uri=${this.routeExternalBackupUri}`);
    return true;
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_backup_root');
    } catch (error) {
      logger.warn(TAG, `获取备份恢复引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private adjustGuideHighlightRect(anchorId: string | undefined, rect: GuideHighlightRect | null): GuideHighlightRect | null {
    return rect;
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.BACKUP_RESTORE);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.BACKUP_RESTORE) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      return;
    }
    if (this.prepareGuidePresentation(step.anchorId) && !trigger.endsWith('_after_prepare')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_prepare`);
      }, 220);
      return;
    }
    if (this.alignGuideViewport(step.anchorId) && !trigger.endsWith('_after_scroll')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_scroll`);
      }, 280);
      return;
    }
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.adjustGuideHighlightRect(
      step.anchorId,
      this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18)
    );
    if (!this.appGuideHighlightRect && trigger !== 'retry_layout') {
      setTimeout(() => {
        void this.refreshPageGuide('retry_layout');
      }, 120);
    }
    logger.debug(TAG, `备份恢复引导已刷新: trigger=${trigger}, step=${step.id}`);
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  private prepareGuidePresentation(anchorId?: string): boolean {
    let targetTab: 'local' | 'cloud' | 'native_test' | 'ftp' | null = null;
    switch (anchorId) {
      case 'guide_backup_root':
      case 'guide_backup_tabs':
      case 'guide_backup_local_panel':
        targetTab = 'local';
        break;
      case 'guide_backup_cloud_panel':
        targetTab = 'cloud';
        break;
      case 'guide_backup_native_panel':
        targetTab = 'native_test';
        break;
      case 'guide_backup_ftp_panel':
        targetTab = 'ftp';
        break;
      default:
        break;
    }
    if (!targetTab || this.currentTab === targetTab) {
      return false;
    }
    this.currentTab = targetTab;
    this.onTabChanged();
    return true;
  }

  private alignGuideViewport(anchorId?: string): boolean {
    if (!anchorId || anchorId.length <= 0) {
      return false;
    }
    if (anchorId === 'guide_backup_root' || anchorId === 'guide_backup_tabs') {
      return false;
    }
    const scrollResult = ensureGuideAnchorVisibleInScroller(
      this.getUIContext(),
      this.scroller,
      anchorId,
      'guide_backup_scroll',
      this.getTitleBarSpacerHeight() + 18,
      32,
      280
    );
    return scrollResult.available && scrollResult.scrolled;
  }

  private getTitleBarSpacerHeight(): number {
    const statusBarHeight = AppStorage.get<number>('statusBarHeight');
    return SettingsPageTitleBarManager.getContentTopPadding(statusBarHeight ?? 0);
  }

  private getBottomSafeSpacing(): number {
    const navigationBarHeight = AppStorage.get<number>('navigationBarHeight');
    return 24 + (navigationBarHeight ?? 0);
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [{
      id: 'help',
      label: '帮助',
      symbol: $r('sys.symbol.questionmark_circle'),
      onClick: () => {
        this.showBackupHelp();
      }
    }];
  }

  private finalizeTrackedTransferImport(
    status: 'imported' | 'import_failed' | 'import_cancelled'
  ): void {
    try {
      const recordId = AppStorage.get<string>(APP_STORAGE_TRANSFER_RECORD_ID);
      const trackingActive = AppStorage.get<boolean>(APP_STORAGE_TRANSFER_TRACKING_ACTIVE);
      if (!trackingActive || !recordId || recordId.trim().length <= 0) {
        return;
      }

      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_RESULT, status);
      AppStorage.setOrCreate(APP_STORAGE_TRANSFER_TRACKING_ACTIVE, false);
      logger.info(TAG, `已回写局域网传书备份导入结果: recordId=${recordId}, status=${status}`);
    } catch (error) {
      logger.warn(TAG, `回写局域网传书备份导入结果失败: ${String(error)}`);
    }
  }

  private releaseExternalBackupTaskLock(reason: string): void {
    if (this.routeExternalTaskInstanceId.length <= 0) {
      return;
    }
    ExternalFileTaskParamStore.getInstance().releaseBackupRestoreLock(this.routeExternalTaskInstanceId);
    logger.info(TAG, `已释放独立备份恢复锁: instance=${this.routeExternalTaskInstanceId}, reason=${reason}`);
  }

  private resolveReadableImportPath(sourceUri: string): string {
    const trimmedUri = sourceUri.trim();
    try {
      return new coreFileUri.FileUri(trimmedUri).path;
    } catch (_error) {
    }
    if (trimmedUri.startsWith('file://docs')) {
      return trimmedUri.replace('file://docs', '');
    }
    if (trimmedUri.startsWith('file://')) {
      return trimmedUri.replace('file://', '');
    }
    return trimmedUri;
  }
  
  /**
   * 检查并处理外部导入的备份文件
   */
  private async checkPendingBackupImport(): Promise<void> {
    try {
      const pendingBackupUri = AppStorage.get<string>('pendingBackupUri');
      const backupImportPending = AppStorage.get<boolean>('backupImportPending');
      
      if (pendingBackupUri && backupImportPending) {
        logger.info(TAG, `💾 检测到外部导入的备份文件: ${pendingBackupUri}`);
        
        // 清除标记
        AppStorage.delete('pendingBackupUri');
        AppStorage.delete('backupImportPending');
        AppStorage.delete('pendingFileCategory');
        
        // 延迟执行导入，确保页面已完全加载
        setTimeout(() => {
          this.importBackupFromUri(pendingBackupUri);
        }, 500);
      }
    } catch (error) {
      logger.error(TAG, `检查外部备份文件失败: ${error}`);
    }
  }
  
  /**
   * 从URI导入备份文件
   * 备份文件是tar格式，需要先复制到沙箱目录再恢复
   */
  private async importBackupFromUri(uri: string): Promise<void> {
    try {
      logger.info(TAG, `开始从URI导入备份: ${uri}`);
      
      // 从URI中提取文件名
      const decodedUri = decodeURIComponent(uri);
      const fileName = decodedUri.substring(decodedUri.lastIndexOf('/') + 1);
      
      // 显示确认对话框
      this.getUIContext().showAlertDialog({
        title: '确认导入备份',
        message: `确定要导入备份文件吗？\n\n文件名: ${fileName}\n\n⚠️ 恢复备份将覆盖当前数据！`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: '取消',
          action: () => {
            logger.info(TAG, '用户取消导入备份');
            this.finalizeTrackedTransferImport('import_cancelled');
            this.releaseExternalBackupTaskLock('cancel');
          }
        },
        secondaryButton: {
          value: '确认导入',
          fontColor: Color.Red,
          action: () => {
            this.executeRestoreFromExternalUri(uri);
          }
        }
      });
      
    } catch (error) {
      logger.error(TAG, `从URI导入备份失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: `导入失败: ${error}` });
      this.finalizeTrackedTransferImport('import_failed');
      this.releaseExternalBackupTaskLock('import_error');
    }
  }
  
  /**
   * 执行从外部URI导入的备份恢复操作
   */
  private async executeRestoreFromExternalUri(uri: string): Promise<void> {
    let tempPath = '';
    try {
      this.isRestoringBackup = true;
      logger.info(TAG, `开始执行备份恢复: ${uri}`);
      const readablePath = this.resolveReadableImportPath(uri);
      
      // 将外部文件复制到沙箱临时目录
      const sandboxManager = SandboxManager.getInstance();
      tempPath = sandboxManager.getDirectory('temp') + '/temp_restore_' + Date.now() + '.mxbak';
      
      const copyProgress = await this.copyFileByChunksAtomic(readablePath, tempPath);
      
      logger.info(TAG, `备份文件已复制到: ${tempPath}, 大小: ${copyProgress.bytesCopied} 字节`);
      
      // 使用EnhancedBackupManager恢复备份（它会解压tar文件）
      await this.enhancedBackupManager.restoreBackup(tempPath);

      this.getUIContext().getPromptAction().showToast({ message: '备份恢复成功！' });
      logger.info(TAG, '备份恢复成功');
      this.finalizeTrackedTransferImport('imported');
      this.releaseExternalBackupTaskLock('restore_success');
      
      // 刷新备份列表
      this.loadBackupFiles();
      
    } catch (error) {
      logger.error(TAG, `执行恢复失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: `恢复失败: ${error}` });
      this.finalizeTrackedTransferImport('import_failed');
      this.releaseExternalBackupTaskLock('restore_failed');
    } finally {
      if (tempPath.length > 0) {
        this.cleanupLocalTempFile(tempPath);
      }
      this.isRestoringBackup = false;
    }
  }
  
  aboutToDisappear(): void {
    this.releaseExternalBackupTaskLock('disappear');
    if (this.cloudSyncTimer !== undefined) {
      clearTimeout(this.cloudSyncTimer);
      this.cloudSyncTimer = undefined;
    }

    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
    this.lifecycle.destroy();
  }

  private showBackupHelp(): void {
    const helpContent = `# 备份与恢复帮助

## 功能概述

本页面提供三种数据管理方式：**本地备份**、**WebDAV云端同步**和**FTP文件管理**。

---

## 📦 本地备份

### 创建备份
1. 切换到"本地备份"标签页
2. 点击顶部"创建备份"按钮
3. 选择要备份的数据类型
4. 等待备份完成，备份文件将显示在列表中

### 管理备份
- **恢复**: 将备份数据还原到应用中
- **上传**: 将本地备份上传到WebDAV云端（需先配置WebDAV）
- **导出**: 将备份文件导出到设备存储，方便传输
- **删除**: 删除不需要的备份文件

### 导入备份
点击"导入备份"按钮，从设备存储选择备份文件导入

---

## ☁️ WebDAV云端同步

### 配置WebDAV服务器
1. 切换到"云端备份"标签页
2. 点击"配置WebDAV"按钮
3. 填写服务器信息：
   - **服务器地址**: WebDAV服务URL（如 https://dav.jianguoyun.com/dav/）
   - **用户名/密码**: 登录凭据
   - **备份路径**: 云端存储目录（如 /manxia_backup/）
4. 点击"测试连接"验证配置
5. 保存配置

### 支持的WebDAV服务
- **坚果云**: 国内推荐，稳定可靠
- **Nextcloud**: 自建云盘首选
- **群晖NAS**: 家庭NAS用户
- **其他**: 任何标准WebDAV协议服务

### 云端操作
- **上传**: 将本地备份同步到云端
- **下载**: 从云端下载备份到本地
- **删除**: 删除云端备份文件

---

## 📁 FTP文件管理

### 添加FTP连接
1. 切换到"FTP管理"标签页
2. 点击右上角"添加"按钮
3. 填写连接信息：
   - **连接名称**: 自定义名称，便于识别
   - **服务器地址**: FTP服务器IP或域名
   - **端口**: FTP端口（默认21，FTPS默认990）
   - **用户名/密码**: 登录凭据
   - **FTPS**: 启用加密传输
   - **被动模式**: 推荐开启，解决NAT穿透问题
4. 点击"保存"

### 连接管理
- 点击连接卡片直接连接到FTP服务器
- 点击编辑图标修改连接配置
- 点击删除图标移除连接（需确认）

### 文件浏览器
连接成功后进入文件浏览器：
- **导航**: 点击文件夹进入，点击"上级"返回
- **刷新**: 重新加载当前目录
- **新建文件夹**: 在当前目录创建文件夹
- **下载**: 下载文件到本地
- **删除**: 删除文件或文件夹

---

## 📋 备份内容说明

| 数据类型 | 包含内容 |
|----------|----------|
| 漫画数据 | 收藏列表、阅读进度、章节缓存信息 |
| 电子书数据 | 书架、阅读进度、书签、笔记 |
| 小说数据 | 收藏、阅读进度、书源配置 |
| 应用设置 | 主题、阅读设置、显示偏好 |

---

## ⚠️ 注意事项

1. **备份不含原始文件**: 备份仅包含元数据和进度，不含图片/文档原文件
2. **恢复会覆盖数据**: 恢复操作会覆盖现有数据，请谨慎操作
3. **定期备份**: 建议定期创建备份，防止数据丢失
4. **网络安全**: WebDAV和FTP传输建议使用HTTPS/FTPS加密
5. **密码安全**: 连接密码仅存储在本地，不会上传到云端`;

    getHelpPanelManagerV2().showInlineHelp('备份与恢复帮助', helpContent);
  }
  
  async loadWebDAVSettings(): Promise<void> {
    // 从本地存储加载WebDAV配置
    const savedSettings = await this.loadPersistedWebDAVSettings();
    
    if (savedSettings) {
      this.webdavSettings = savedSettings;
      logger.info(TAG, `已加载WebDAV配置: enabled=${savedSettings.enabled}, status=${savedSettings.connectionStatus}`);
      
      // 记录配置签名，只有在需要云操作时才真正连接WebDAV，避免页面进入卡顿
      this.webdavConfigKey = this.getWebDAVConfigKey(savedSettings);

      if (savedSettings.enabled && savedSettings.connectionStatus === 'success' && this.currentTab === 'cloud') {
        this.scheduleLoadCloudBackups(120);
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
        autoBackupInterval: 'daily',
        keepBackupCount: 5,
        lastSyncTime: 0,
        connectionStatus: 'untested',
        lastTestTime: 0,
        lastTestMessage: '',
        needCreateDir: false
      };
      this.webdavConfigKey = '';
    }
  }
  
  async loadCloudBackups(): Promise<void> {
    if (this.isLoadingCloud) {
      return;
    }

    const isReady = await this.ensureWebDAVReady();
    if (!isReady) {
      logger.warn(TAG, 'WebDAV未就绪，跳过云端备份加载');
      return;
    }
    
    try {
      this.isLoadingCloud = true;

      // 先读取索引列表，避免重复发起两次相同请求
      this.cloudBackups = await this.webdavManager.listRemoteBackups();
      if (this.cloudBackups.length === 0) {
        const indexExists = await this.webdavManager.checkIndexExists();
        this.showInitCloudDialog = !indexExists;
      } else {
        this.showInitCloudDialog = false;
      }
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
      const isReady = await this.ensureWebDAVReady();
      if (!isReady) {
        throw new Error('WebDAV未配置或连接不可用');
      }

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
      const isReady = await this.ensureWebDAVReady();
      if (!isReady) {
        throw new Error('WebDAV未配置或连接不可用');
      }

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
      const isReady = await this.ensureWebDAVReady();
      if (!isReady) {
        throw new Error('WebDAV未配置或连接不可用');
      }

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
      const isReady = await this.ensureWebDAVReady();
      if (!isReady) {
        throw new Error('WebDAV未配置或连接不可用');
      }

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
      logger.info(TAG, `检查是否需要配置WebDAV管理器: enabled=${settings.enabled}, status=${settings.connectionStatus}`);
      if (settings.enabled && settings.connectionStatus === 'success') {
        const config: WebDAVConfig = {
          serverUrl: settings.serverUrl,
          username: settings.username,
          password: settings.password,
          basePath: settings.basePath
        };
        
        logger.info(TAG, '开始配置WebDAV管理器');
        await this.webdavManager.configure(config);
        this.webdavConfigKey = this.getWebDAVConfigKey(settings);
        logger.info(TAG, 'WebDAV管理器配置完成');
        if (this.currentTab === 'cloud') {
          this.scheduleLoadCloudBackups(80);
        }
      } else {
        logger.warn(TAG, `跳过WebDAV管理器配置: enabled=${settings.enabled}, status=${settings.connectionStatus}`);
        this.webdavConfigKey = '';
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
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
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
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
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
        autoBackupInterval: dataPreferences.getSync('autoBackupInterval', 'daily') as 'daily' | 'weekly',
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
      // 优先使用Native客户端（支持HTTPS自签名证书）
      if (isNativeModuleAvailable()) {
        logger.info(TAG, '使用Native客户端测试WebDAV连接');
        const nativeConfig: WebDAVNativeConfig = {
          serverUrl: settings.serverUrl,
          username: settings.username,
          password: settings.password,
          basePath: settings.basePath,
          timeoutMs: 30000,
          verifySSL: true
        };
        const nativeClient = new WebDAVNativeClient(nativeConfig);
        await nativeClient.initialize();
        const result = await nativeClient.testConnection();
        
        // 增强错误提示
        if (!result.success) {
          result.message = this.enhanceWebDAVErrorMessage(result.message, settings.basePath);
        }
        return result;
      }
      
      // 回退到ArkTS客户端
      logger.info(TAG, '使用ArkTS客户端测试WebDAV连接');
      const client = new WebDAVClient({
        serverUrl: settings.serverUrl,
        username: settings.username,
        password: settings.password,
        basePath: settings.basePath
      });
      
      const result = await client.testConnection();
      // 增强错误提示
      if (!result.success) {
        result.message = this.enhanceWebDAVErrorMessage(result.message, settings.basePath);
      }
      return result;
    } catch (error) {
      logger.error(TAG, `测试WebDAV连接失败: ${error}`);
      const errorMsg = this.enhanceWebDAVErrorMessage(String(error), settings.basePath);
      const result: WebDAVTestResult = { 
        success: false, 
        needCreateDir: false, 
        message: errorMsg
      };
      return result;
    }
  }
  
  /**
   * 增强WebDAV错误提示信息（使用智能错误分析器）
   */
  private enhanceWebDAVErrorMessage(originalMessage: string, basePath: string): string {
    // 使用智能错误分析器
    const analysis = WebDAVErrorAnalyzer.analyze(originalMessage, undefined, basePath);
    return WebDAVErrorAnalyzer.formatErrorForUser(analysis);
  }
  
  /**
   * 显示WebDAV错误详情对话框
   */
  private showWebDAVErrorDialog(error: string, basePath: string): void {
    const analysis = WebDAVErrorAnalyzer.analyze(error, undefined, basePath);
    
    this.getUIContext().showAlertDialog({
      title: `❌ ${analysis.title}`,
      message: `${analysis.description}\n\n💡 建议：\n${analysis.suggestions.map((s, i) => `${i + 1}. ${s}`).join('\n')}`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '知道了',
        action: () => {}
      },
      secondaryButton: analysis.canAutoFix ? {
        value: '重试',
        action: () => {
          // 可以触发重试操作
          this.testWebDAVConnection(this.webdavSettings);
        }
      } : undefined
    });
  }

  async runNativeWebDAVTest(): Promise<void> {
    try {
      logger.info(TAG, '开始WebDAV Native模块测试');
      
      this.getUIContext().getPromptAction().showToast({
        message: '正在运行Native测试...',
        duration: 2000
      });

      const nativeConfig: WebDAVNativeConfig = {
        serverUrl: this.webdavSettings.serverUrl,
        username: this.webdavSettings.username,
        password: this.webdavSettings.password,
        basePath: this.webdavSettings.basePath,
        timeoutMs: 30000,
        verifySSL: true
      };

      const summary = await quickTestWebDAVNative(nativeConfig);
      logger.info(TAG, `Native测试结果:\n${summary}`);

      // 显示测试结果对话框
      this.getUIContext().showAlertDialog({
        title: 'WebDAV Native 测试结果',
        message: summary,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        confirm: {
          value: '确定',
          action: () => {}
        }
      });
    } catch (error) {
      logger.error(TAG, `Native测试失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({
        message: `Native测试失败: ${error}`,
        duration: 3000
      });
    }
  }

  async runFullNativeTest(): Promise<void> {
    if (this.nativeTestRunning) return;
    
    this.nativeTestRunning = true;
    this.nativeTestResults = [];
    this.nativeTestSummary = '';
    
    try {
      logger.info(TAG, '开始完整Native测试');
      
      const nativeConfig: WebDAVNativeConfig = {
        serverUrl: this.webdavSettings.serverUrl,
        username: this.webdavSettings.username,
        password: this.webdavSettings.password,
        basePath: this.webdavSettings.basePath,
        timeoutMs: 30000,
        verifySSL: true
      };

      const client = new WebDAVNativeClient(nativeConfig);
      const testDir = this.nativeTestConfig.customTestPath || `_native_test_${Date.now()}`;
      const testFile = `${testDir}/test_file.txt`;
      const testContent = `Native Test Content - ${new Date().toISOString()}`;
      let totalDuration = 0;
      let passedCount = 0;

      // 初始化客户端
      const initStart = Date.now();
      const initResult = await client.initialize();
      const initDuration = Date.now() - initStart;
      totalDuration += initDuration;
      
      if (!initResult) {
        this.nativeTestResults.push({
          testName: '初始化客户端',
          success: false,
          message: 'Native模块初始化失败',
          duration: initDuration
        });
        this.nativeTestSummary = `测试失败: Native模块初始化失败`;
        this.nativeTestRunning = false;
        return;
      }
      
      this.nativeTestResults.push({
        testName: '初始化客户端',
        success: true,
        message: '客户端初始化成功',
        duration: initDuration
      });
      passedCount++;

      // 连接测试
      if (this.nativeTestConfig.testConnection) {
        const start = Date.now();
        try {
          const result = await client.testConnection();
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '连接测试',
            success: result.success,
            message: result.message,
            duration
          });
          if (result.success) passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '连接测试',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 目录列表测试
      if (this.nativeTestConfig.testList) {
        const start = Date.now();
        try {
          const files = await client.list('');
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '目录列表 (PROPFIND)',
            success: true,
            message: `获取到 ${files.length} 个文件/目录`,
            duration
          });
          passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '目录列表 (PROPFIND)',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 创建目录测试
      if (this.nativeTestConfig.testCreateDir) {
        const start = Date.now();
        try {
          const result = await client.createDirectory(testDir);
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '创建目录 (MKCOL)',
            success: result.success,
            message: result.success ? `目录创建成功: ${testDir}` : result.message,
            duration
          });
          if (result.success) passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '创建目录 (MKCOL)',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 上传文件测试
      if (this.nativeTestConfig.testUpload) {
        const start = Date.now();
        try {
          const result = await client.putFileContents(testFile, testContent);
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '上传文件 (PUT)',
            success: result.success,
            message: result.success ? `上传成功: ${testFile}` : result.message,
            duration
          });
          if (result.success) passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '上传文件 (PUT)',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 下载文件测试
      if (this.nativeTestConfig.testDownload) {
        const start = Date.now();
        try {
          const content = await client.getFileContents(testFile);
          const duration = Date.now() - start;
          totalDuration += duration;
          const contentMatch = content === testContent;
          this.nativeTestResults.push({
            testName: '下载文件 (GET)',
            success: contentMatch,
            message: contentMatch ? `下载成功，内容匹配` : `内容不匹配`,
            duration
          });
          if (contentMatch) passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '下载文件 (GET)',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 删除文件测试
      if (this.nativeTestConfig.testDelete) {
        const start = Date.now();
        try {
          // 先删除文件
          await client.deleteFile(testFile);
          // 再删除目录
          const result = await client.deleteFile(testDir);
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '删除文件 (DELETE)',
            success: result.success,
            message: result.success ? '删除成功' : result.message,
            duration
          });
          if (result.success) passedCount++;
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '删除文件 (DELETE)',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 配额测试
      if (this.nativeTestConfig.testQuota) {
        const start = Date.now();
        try {
          const quota = await client.getQuota();
          const duration = Date.now() - start;
          totalDuration += duration;
          if (quota.success) {
            const usedGB = (quota.usedBytes / 1024 / 1024 / 1024).toFixed(2);
            const availableGB = (quota.availableBytes / 1024 / 1024 / 1024).toFixed(2);
            this.nativeTestResults.push({
              testName: '磁盘配额',
              success: true,
              message: `已用: ${usedGB}GB, 可用: ${availableGB}GB`,
              duration
            });
            passedCount++;
          } else {
            this.nativeTestResults.push({
              testName: '磁盘配额',
              success: false,
              message: quota.message || '不支持配额查询',
              duration
            });
          }
        } catch (e) {
          const duration = Date.now() - start;
          totalDuration += duration;
          this.nativeTestResults.push({
            testName: '磁盘配额',
            success: false,
            message: `${e}`,
            duration
          });
        }
      }

      // 销毁客户端
      client.destroy();

      // 生成摘要
      const totalTests = this.nativeTestResults.length;
      this.nativeTestSummary = `总计: ${totalTests} | 通过: ${passedCount} | 失败: ${totalTests - passedCount} | 耗时: ${totalDuration}ms`;
      
      logger.info(TAG, `Native测试完成: ${this.nativeTestSummary}`);
      
    } catch (error) {
      logger.error(TAG, `Native测试异常: ${error}`);
      this.nativeTestResults.push({
        testName: '测试异常',
        success: false,
        message: `${error}`,
        duration: 0
      });
      this.nativeTestSummary = `测试异常: ${error}`;
    } finally {
      this.nativeTestRunning = false;
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
        if (fileName.endsWith('.json') || fileName.endsWith('.mxbackup') || fileName.endsWith('.mxbak')) {
          const filePath = `${backupDir}/${fileName}`;
          try {
            const stat = await fileIo.stat(filePath);
            let metadata: BackupMetadata;
            
            if (fileName.endsWith('.mxbackup') || fileName.endsWith('.mxbak')) {
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
      
      // 检查是否已导出到Download/漫匹/backup文件夹
      const downloadDirPath = AppStorage.get<string>('downloadSyncDirPath');
      if (downloadDirPath) {
        this.getUIContext().getPromptAction().showToast({
          message: '备份创建成功，已导出到 Download/漫匹/backup',
          duration: 3000
        });
      } else {
        this.getUIContext().getPromptAction().showToast({
          message: '备份创建成功',
          duration: 2000
        });
      }
      
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
      const isReady = await this.ensureWebDAVReady();
      if (!isReady) {
        throw new Error('WebDAV未配置或连接不可用');
      }
      
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

  private confirmSensitiveCloudBackup(options: BackupOptions): void {
    if (!options.includeCloudConfig) {
      this.createBackupWithOptions(options);
      return;
    }

    this.getUIContext().showAlertDialog({
      title: '确认备份云存储配置',
      message: '云存储配置包含 WebDAV、Suwayomi、Komga、FTP 的账号、密码和 API Key。请只在你能妥善保存备份文件时启用。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消备份云存储配置');
        }
      },
      secondaryButton: {
        value: '继续备份',
        fontColor: Color.Red,
        action: () => {
          this.createBackupWithOptions(options);
        }
      }
    });
  }

  private confirmSensitiveCloudRestore(options: RestoreOptions): void {
    if (!options.restoreCloudConfig) {
      this.restoreBackupWithOptions(options);
      return;
    }

    this.getUIContext().showAlertDialog({
      title: '确认恢复云存储配置',
      message: '恢复云存储配置会写入 WebDAV、Suwayomi、Komga、FTP 的账号、密码和 API Key，并覆盖当前相关配置。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消恢复云存储配置');
        }
      },
      secondaryButton: {
        value: '继续恢复',
        fontColor: Color.Red,
        action: () => {
          this.restoreBackupWithOptions(options);
        }
      }
    });
  }
  
  async showRestoreOptions(backupInfo: BackupFileInfo): Promise<void> {
    try {
      const backupData = await this.loadBackupDataForPreview(backupInfo);
      
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

  private async loadBackupDataForPreview(backupInfo: BackupFileInfo): Promise<BackupData> {
    if (!backupInfo.fileName.endsWith('.mxbackup') && !backupInfo.fileName.endsWith('.mxbak')) {
      const sandboxManager = SandboxManager.getInstance();
      const jsonContent = await sandboxManager.readTextFile(backupInfo.filePath);
      return SafeUtils.parseObj(jsonContent) as BackupData;
    }

    const sandboxManager = SandboxManager.getInstance();
    const tempDir = `${sandboxManager.getDirectory('cache')}/restore_preview_${Date.now()}`;
    try {
      if (!await sandboxManager.exists(tempDir)) {
        await sandboxManager.createDirectory(tempDir);
      }

      const tarPackager = await import('../Framework/Utils/TarPackager').then(m => m.getTarPackager());
      await tarPackager.extractTarArchive(backupInfo.filePath, tempDir);

      const jsonPath = `${tempDir}/backup.json`;
      const jsonContent = await sandboxManager.readTextFile(jsonPath);
      return SafeUtils.parseObj(jsonContent) as BackupData;
    } finally {
      await this.deleteDirectoryRecursive(tempDir);
    }
  }

  private async deleteDirectoryRecursive(path: string): Promise<void> {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        await fileIo.unlink(path);
        return;
      }

      const entries = await fileIo.listFile(path);
      for (const entry of entries) {
        await this.deleteDirectoryRecursive(`${path}/${entry}`);
      }
      await fileIo.rmdir(path);
    } catch (error) {
      logger.warn(TAG, `清理目录失败: ${path}, ${error}`);
    }
  }

  async restoreBackupWithOptions(options: RestoreOptions): Promise<void> {
    try {
      this.isRestoringBackup = true;
      this.showRestoreOptionsDialog = false;
      
      if (this.currentRestoreBackup && (this.currentRestoreBackup.fileName.endsWith('.mxbackup') || this.currentRestoreBackup.fileName.endsWith('.mxbak'))) {
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

  private async copyFileByChunks(sourcePath: string, targetPath: string): Promise<FileCopyProgress> {
    const sourceFile = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    let targetFile: fileIo.File | null = null;
    try {
      targetFile = await fileIo.open(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      const stat = await fileIo.stat(sourceFile.fd);
      const totalBytes = stat.size;
      let offset = 0;
      let copied = 0;

      while (offset < totalBytes) {
        const remaining = totalBytes - offset;
        const chunkSize = remaining > BACKUP_COPY_BUFFER_SIZE ? BACKUP_COPY_BUFFER_SIZE : remaining;
        const buffer = new ArrayBuffer(chunkSize);
        const readBytes = await fileIo.read(sourceFile.fd, buffer, { length: chunkSize });
        if (readBytes <= 0) {
          throw new Error(`读取备份文件失败: offset=${offset}, readBytes=${readBytes}`);
        }
        if (readBytes !== chunkSize) {
          throw new Error(`备份文件读取不完整: expected=${chunkSize}, actual=${readBytes}`);
        }

        const writtenBytes = await fileIo.write(targetFile.fd, buffer, { length: readBytes });
        if (writtenBytes !== readBytes) {
          throw new Error(`备份文件写入不完整: expected=${readBytes}, actual=${writtenBytes}`);
        }

        offset += readBytes;
        copied += writtenBytes;
      }

      return { bytesCopied: copied, totalBytes: totalBytes };
    } finally {
      if (targetFile) {
        await fileIo.close(targetFile);
      }
      await fileIo.close(sourceFile);
    }
  }

  private async copyFileByChunksAtomic(sourcePath: string, targetPath: string): Promise<FileCopyProgress> {
    const tempPath = `${targetPath}.copy_${Date.now()}.tmp`;
    try {
      const progress = await this.copyFileByChunks(sourcePath, tempPath);
      this.replaceLocalFileAfterCopy(tempPath, targetPath);
      return progress;
    } catch (error) {
      this.cleanupLocalTempFile(tempPath);
      throw new Error(`原子复制备份文件失败: ${error}`);
    }
  }

  private replaceLocalFileAfterCopy(tempPath: string, targetPath: string): void {
    try {
      SafeFileUtils.renameSyncStrict(tempPath, targetPath);
      return;
    } catch (renameError) {
      logger.warn(TAG, `直接替换导入文件失败，尝试暂存旧文件后重试: ${renameError}`);
    }

    if (SafeFileUtils.accessSync(targetPath)) {
      const previousPath = `${targetPath}.previous_${Date.now()}.tmp`;
      SafeFileUtils.renameSyncStrict(targetPath, previousPath);
      try {
        SafeFileUtils.renameSyncStrict(tempPath, targetPath);
        this.cleanupLocalTempFile(previousPath);
        return;
      } catch (replaceError) {
        if (SafeFileUtils.accessSync(previousPath) && !SafeFileUtils.accessSync(targetPath)) {
          SafeFileUtils.renameSyncStrict(previousPath, targetPath);
        }
        throw new Error(`替换导入文件失败且已尝试恢复旧文件: ${replaceError}`);
      }
    }
    SafeFileUtils.renameSyncStrict(tempPath, targetPath);
  }

  private cleanupLocalTempFile(tempPath: string): void {
    try {
      if (SafeFileUtils.accessSync(tempPath)) {
        SafeFileUtils.unlinkSyncStrict(tempPath);
      }
    } catch (cleanupError) {
      logger.warn(TAG, `清理临时文件失败: ${cleanupError}`);
    }
  }

  private resolveBackupImportExtension(uri: string): string {
    const fileName = this.resolveFileNameFromUri(uri).toLowerCase();
    if (fileName.endsWith('.mxbak')) {
      return '.mxbak';
    }
    if (fileName.endsWith('.mxbackup')) {
      return '.mxbackup';
    }
    return '.json';
  }

  private resolveFileNameFromUri(uri: string): string {
    try {
      const uriObj = new coreFileUri.FileUri(uri);
      return uriObj.name;
    } catch (error) {
      logger.debug(TAG, `解析导入文件名失败，使用URI片段: ${error}`);
    }

    try {
      const cleanUri = uri.split('?')[0].split('#')[0];
      const rawName = cleanUri.substring(cleanUri.lastIndexOf('/') + 1);
      return decodeURIComponent(rawName);
    } catch (decodeError) {
      logger.warn(TAG, `解析导入文件URI失败: ${decodeError}`);
      return '';
    }
  }
  
  async exportBackup(backupInfo: BackupFileInfo): Promise<void> {
    try {
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [backupInfo.fileName];
      const documentViewPicker = new picker.DocumentViewPicker();
      const uris = await documentViewPicker.save(documentSaveOptions);
      
      if (uris && uris.length > 0) {
        await this.copyFileByChunks(backupInfo.filePath, uris[0]);
        
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
        const sandboxManager = SandboxManager.getInstance();
        const filesDir = sandboxManager.getDirectory('files');
        const backupDir = `${filesDir}/backups`;
        
        if (!await sandboxManager.exists(backupDir)) {
          await sandboxManager.createDirectory(backupDir);
        }
        
        const extension = this.resolveBackupImportExtension(uris[0]);
        const fileName = `imported_backup_${Date.now()}${extension}`;
        const destPath = `${backupDir}/${fileName}`;
        await this.copyFileByChunksAtomic(uris[0], destPath);
        
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

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  @Builder
  buildBackupOptionsDialog() {
    if (this.showBackupOptionsDialog) {
      BackupOptionsDialog({
        onConfirm: (options: BackupOptions) => {
          this.confirmSensitiveCloudBackup(options);
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
          this.confirmSensitiveCloudRestore(options);
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
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .padding({ top: 20, bottom: 16 })
          
          // 内容
          Scroll(this.scroller) {
            Column() {
              if (this.restoreSuccess) {
                Text('✅ 备份数据已成功恢复')
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .margin({ bottom: 12 })
                
                Text('请重启APP以应用所有更改')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              } else {
                Text('❌ 恢复过程中出现错误')
                  .fontSize(16)
                  .fontColor('#FF0000')
                  .fontFamily(this.appFontFamily)
                  .margin({ bottom: 12 })
                
                Text(this.restoreErrorMessage)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
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
                .fontFamily(this.appFontFamily)
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
                .fontFamily(this.appFontFamily)
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
                .fontFamily(this.appFontFamily)
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
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(16)
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: 18,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 10
        })
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
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        Column() {
          Blank().height(this.getTitleBarSpacerHeight())
          
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
              } else if (this.currentTab === 'cloud') {
                this.buildCloudBackupList()
              } else if (this.currentTab === 'native_test') {
                this.buildNativeTestPanel()
              } else if (this.currentTab === 'ftp') {
                this.buildFTPManagerPanel()
              }
              Blank().height(this.getBottomSafeSpacing())
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .id('guide_backup_scroll')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
              .onActionStart((event: GestureEvent) => {
                this.swipeStartX = event.offsetX;
                this.swipeOffsetX = 0;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.swipeOffsetX = event.offsetX - this.swipeStartX;
              })
              .onActionEnd((event: GestureEvent) => {
                const swipeThreshold = 80;
                if (this.swipeOffsetX < -swipeThreshold) {
                  this.switchToNextTab();
                } else if (this.swipeOffsetX > swipeThreshold) {
                  this.switchToPrevTab();
                }
                this.swipeOffsetX = 0;
              })
          )
        }
        .width('100%')
        .height('100%')
        .id('guide_backup_root')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '备份与恢复',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })
        
        // 对话框层
        this.buildBackupOptionsDialog()
        this.buildRestoreOptionsDialog()
        this.buildRestoreResultDialog()
        this.buildWebDAVConfigDialog()
        this.buildInitCloudDialog()

        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            showSkip: this.appGuideStep.showSkip !== false,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
  .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .mode(NavDestinationMode.STANDARD)
    /*
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '备份与恢复' },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showBackupHelp();
              }
            }
          }]
        }
      }
    })
    */
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as BackupExternalImportParams | undefined;
      this.setRouteExternalBackupParams(params);
    })
    .onShown(() => {
      void this.refreshPageGuide('onShown');
    })
    .backgroundColor(Color.Transparent)
  }
  
  /**
   * 构建标签栏 - VSCode风格
   */
  @Builder
  buildTabBar() {
    Scroll() {
      Row({ space: 0 }) {
        // 本地备份Tab
        Row() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(14)
            .fontColor([this.currentTab === 'local'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          
          Text('本地备份')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTab === 'local'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.getTabBackground('local'))
        .border({
          width: { top: this.getTabTopBorderWidth('local'), bottom: 0, left: 0, right: 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.currentTab = 'local';
        })
        .animation({ duration: 150 })
        
        // 云端备份Tab
        Row() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(14)
            .fontColor([this.currentTab === 'cloud'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          
          Text('云端备份')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTab === 'cloud'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          if (this.webdavSettings.enabled) {
            Circle()
              .width(6)
              .height(6)
              .fill('#00C853')
              .margin({ left: 6 })
          }
        }
        .padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.getTabBackground('cloud'))
        .border({
          width: { top: this.getTabTopBorderWidth('cloud'), bottom: 0, left: 0, right: 0 },
          color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        })
        .onClick(() => {
          this.currentTab = 'cloud';
          if (this.webdavSettings.enabled && this.cloudBackups.length === 0) {
            this.scheduleLoadCloudBackups(80);
          }
        })
        .animation({ duration: 150 })
        
        // Native测试Tab
        Row() {
          SymbolGlyph($r('sys.symbol.spanner_case_fill'))
            .fontSize(14)
            .fontColor([this.currentTab === 'native_test'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          
          Text('Native测试')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTab === 'native_test'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.getTabBackground('native_test'))
        .border({
          width: { top: this.getTabTopBorderWidth('native_test'), bottom: 0, left: 0, right: 0 },
          color: '#4CAF50'
        })
        .onClick(() => {
          this.currentTab = 'native_test';
        })
        .animation({ duration: 150 })
        
        // FTP管理器Tab
        Row() {
          SymbolGlyph($r('sys.symbol.folder_circle'))
            .fontSize(14)
            .fontColor([this.currentTab === 'ftp'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .margin({ right: 6 })
          
          Text('FTP管理')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.currentTab === 'ftp'
              ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 12, right: 12, top: 0, bottom: 0 })
        .height(35)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.getTabBackground('ftp'))
        .border({
          width: { top: this.getTabTopBorderWidth('ftp'), bottom: 0, left: 0, right: 0 },
          color: '#FF9800'
        })
        .onClick(() => {
          this.currentTab = 'ftp';
        })
        .animation({ duration: 150 })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .height(35)
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(18)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 18,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ left: 16, right: 16, top: 8, bottom: 4 })
    .id('guide_backup_tabs')
  }

  @Builder
  buildNativeTestPanel() {
    Column({ space: 16 }) {
      // 标题区域
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.spanner_case_fill'))
            .fontSize(20)
            .fontColor(['#4CAF50'])
          Text('WebDAV Native 测试')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Blank()
        if (this.nativeTestRunning) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#4CAF50')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      // WebDAV配置状态
      Column() {
        Row() {
          Text('服务器状态')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          if (this.webdavSettings.enabled) {
            Row({ space: 4 }) {
              Circle().width(8).height(8).fill('#4CAF50')
              Text('已配置')
                .fontSize(12)
                .fontColor('#4CAF50')
                .fontFamily(this.appFontFamily)
            }
          } else {
            Row({ space: 4 }) {
              Circle().width(8).height(8).fill('#FF5252')
              Text('未配置')
                .fontSize(12)
                .fontColor('#FF5252')
                .fontFamily(this.appFontFamily)
            }
          }
        }
        .width('100%')
        
        if (this.webdavSettings.enabled) {
          Text(this.webdavSettings.serverUrl)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .width('100%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .margin({ left: 16, right: 16 })

      // 测试选项配置
      Column({ space: 12 }) {
        Text('测试项目')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        this.buildTestOptionRow('连接测试', this.nativeTestConfig.testConnection, (v: boolean) => {
          this.nativeTestConfig.testConnection = v;
        })
        this.buildTestOptionRow('目录列表 (PROPFIND)', this.nativeTestConfig.testList, (v: boolean) => {
          this.nativeTestConfig.testList = v;
        })
        this.buildTestOptionRow('创建目录 (MKCOL)', this.nativeTestConfig.testCreateDir, (v: boolean) => {
          this.nativeTestConfig.testCreateDir = v;
        })
        this.buildTestOptionRow('上传文件 (PUT)', this.nativeTestConfig.testUpload, (v: boolean) => {
          this.nativeTestConfig.testUpload = v;
        })
        this.buildTestOptionRow('下载文件 (GET)', this.nativeTestConfig.testDownload, (v: boolean) => {
          this.nativeTestConfig.testDownload = v;
        })
        this.buildTestOptionRow('删除文件 (DELETE)', this.nativeTestConfig.testDelete, (v: boolean) => {
          this.nativeTestConfig.testDelete = v;
        })
        this.buildTestOptionRow('磁盘配额', this.nativeTestConfig.testQuota, (v: boolean) => {
          this.nativeTestConfig.testQuota = v;
        })
      }
      .width('100%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .margin({ left: 16, right: 16 })

      // 自定义测试路径
      Column({ space: 8 }) {
        Text('自定义测试路径（可选）')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
        
        TextInput({ placeholder: '例如: /test/custom_folder', text: this.nativeTestConfig.customTestPath })
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .height(40)
          .onChange((value: string) => {
            this.nativeTestConfig.customTestPath = value;
          })
      }
      .width('100%')
      .padding(16)
      .borderRadius(12)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .margin({ left: 16, right: 16 })

      // 运行测试按钮
      Button(this.nativeTestRunning ? '测试中...' : '运行完整测试')
        .width('90%')
        .height(48)
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(this.nativeTestRunning ? '#9E9E9E' : '#4CAF50')
        .borderRadius(24)
        .enabled(!this.nativeTestRunning && this.webdavSettings.enabled)
        .onClick(async () => {
          await this.runFullNativeTest();
        })

      // 测试结果区域
      if (this.nativeTestResults.length > 0) {
        Column({ space: 8 }) {
          Row() {
            Text('测试结果')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Button('清除')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .backgroundColor('transparent')
              .onClick(() => {
                this.nativeTestResults = [];
                this.nativeTestSummary = '';
              })
          }
          .width('100%')

          ForEach(this.nativeTestResults, (result: NativeTestResult) => {
            this.buildTestResultRow(result)
          })

          if (this.nativeTestSummary) {
            Text(this.nativeTestSummary)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .width('100%')
              .margin({ top: 8 })
          }
        }
        .width('100%')
        .padding(16)
        .borderRadius(12)
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: 16,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 8
        })
        .margin({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .id('guide_backup_native_panel')
  }

  @Builder
  buildTestOptionRow(label: string, checked: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor('#4CAF50')
        .onChange((isOn: boolean) => {
          onChange(isOn);
        })
    }
    .width('100%')
    .height(40)
  }

  @Builder
  buildTestResultRow(result: NativeTestResult) {
    Row({ space: 8 }) {
      Text(result.success ? '✓' : '✗')
        .fontSize(16)
        .fontColor(result.success ? '#4CAF50' : '#FF5252')
        .fontWeight(FontWeight.Bold)
      
      Column({ space: 2 }) {
        Text(result.testName)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(result.message)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      
      Text(`${result.duration}ms`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .borderRadius(8)
    .backgroundColor(result.success 
      ? 'rgba(76, 175, 80, 0.1)' 
      : 'rgba(255, 82, 82, 0.1)')
  }

  @Builder
  buildStorageOverview() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.cloud')).fontSize(18).fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('云端存储')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        
        Blank()
        
        // 设置按钮
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(20)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
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
                .fontFamily(this.appFontFamily)
              
              Blank()
              
              Text(`${this.cloudBackups.length} 个备份`)
                .fontSize(14)
                .fontColor('#FFFFFF')
                .fontFamily(this.appFontFamily)
            }
            .width('100%')
            .margin({ bottom: 12 })
            
            // 服务器地址
            Text(this.webdavSettings.serverUrl)
              .fontSize(12)
              .fontColor('#FFFFFF')
              .opacity(0.8)
              .maxLines(1)
              .fontFamily(this.appFontFamily)
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
                    .fontFamily(this.appFontFamily)
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
                    .fontFamily(this.appFontFamily)
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
                  Image($r('sys.symbol.trash'))
                    .width(16)
                    .height(16)
                    .fillColor('#FFFFFF')
                  Text('删除')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                    .fontFamily(this.appFontFamily)
                    .margin({ left: 4 })
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
                  autoBackupInterval: 'daily',
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
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Blank()
              
              Toggle({ type: ToggleType.Switch, isOn: this.webdavSettings.enabled })
                .onChange((isOn: boolean) => {
                  this.webdavSettings.enabled = isOn;
                  this.persistWebDAVSettings(this.webdavSettings);
                  if (isOn && this.webdavSettings.connectionStatus === 'success') {
                    this.scheduleLoadCloudBackups(80);
                  }
                })
            }
            .width('100%')
            .margin({ bottom: 8 })
            
            // 服务器地址
            Text(this.webdavSettings.serverUrl)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ bottom: 4 })
            
            // 上次测试消息
            if (this.webdavSettings.lastTestMessage) {
              Text(this.webdavSettings.lastTestMessage)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
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
                .fontFamily(this.appFontFamily)
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
              
              Button('Native测试')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor('#4CAF50')
                .backgroundColor('transparent')
                .borderRadius(6)
                .border({
                  width: 1,
                  color: '#4CAF50'
                })
                .onClick(async () => {
                  await this.runNativeWebDAVTest();
                })
              
              Blank().width(8)
              
              Button('编辑配置')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .fontFamily(this.appFontFamily)
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
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: this.webdavSettings.connectionStatus === 'failed' ? '#FF5252' : 
                   SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          })
          .shadow({
            radius: 16,
            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 8
          })
        } else {
          // 未配置WebDAV
          Column() {
            Text('🔒 未配置云端备份')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ bottom: 8 })
            
            Text('点击右上角设置按钮配置WebDAV')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ bottom: 16 })
            
            Button('立即配置')
              .fontSize(14)
              .fontColor('#FFFFFF')
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(8)
              .onClick(() => {
                this.showWebDAVConfigDialog = true;
              })
          }
          .width('100%')
          .padding(20)
          .borderRadius(12)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme),
            style: BorderStyle.Dashed
          })
          .shadow({
            radius: 16,
            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 8
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
          .fontFamily(this.appFontFamily)
        
        Text(`${Math.round(Math.max(0, Math.min(100, this.syncStatus.isUploading ? this.syncStatus.uploadProgress : this.syncStatus.downloadProgress)))}%`)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .margin({ left: 8 })
          .fontFamily(this.appFontFamily)
      }
    } else if (this.syncStatus.lastSyncTime > 0) {
      Text(`最后同步: ${this.formatDate(this.syncStatus.lastSyncTime)}`)
        .fontSize(12)
        .fontColor('#FFFFFF')
        .opacity(0.8)
        .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .enabled(!this.isCreatingBackup && !this.isRestoringBackup)
          .onClick(() => this.createBackup())
        
        Blank().width(12)
        
        Button('导入备份')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else if (this.backupFiles.length === 0) {
        Column() {
          Text('📦')
            .fontSize(48)
            .margin({ bottom: 16 })
            .fontFamily(this.appFontFamily)
          
          Text('暂无本地备份')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('点击"创建备份"开始备份数据')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
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
    .id('guide_backup_local_panel')
  }

  @Builder
  buildCloudBackupList() {
    Column() {
      if (!this.webdavSettings.enabled) {
        Column() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
            .margin({ bottom: 16 })
          
          Text('云端备份未启用')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('请先配置WebDAV')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 16 })
        }
        .width('100%')
        .height(300)
        .justifyContent(FlexAlign.Center)
      } else if (this.cloudBackups.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.cloud'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
            .margin({ bottom: 16 })
          
          Text('暂无云端备份')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('上传本地备份到云端')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
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
    .id('guide_backup_cloud_panel')
  }

  @Builder
  buildBackupCard(backup: BackupFileInfo, type: 'local') {
    Column() {
      Row() {
        Column() {
          Text(this.formatDate(backup.metadata.timestamp))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(`${this.formatFileSize(backup.fileSize)} · ${backup.metadata.appVersion}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
          
          Row() {
            Text(`📚 ${backup.metadata.itemCounts.manga}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            
            Text(`📖 ${backup.metadata.itemCounts.novel}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 12 })
            
            Text(`📄 ${backup.metadata.itemCounts.ebook}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .enabled(!this.isRestoringBackup)
            .onClick(() => this.showRestoreOptions(backup))
          
          if (this.webdavSettings.enabled) {
            Button('上传')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(6)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .margin({ top: 8 })
              .onClick(() => this.uploadToCloud(backup))
          }
          
          Button('导出')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ top: 8 })
            .onClick(() => this.exportBackup(backup))
          
          Button('删除')
            .fontSize(14)
            .fontColor('#FF0000')
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .margin({ top: 8 })
            .onClick(() => this.deleteBackup(backup))
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(12)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
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
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text(`${this.formatFileSize(backup.size)} · ${backup.fileName}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
          
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.cloud'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text('云端备份')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .margin({ top: 8 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Column() {
          Button('下载')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => this.downloadFromCloud(backup))
          
          Button('删除')
            .fontSize(14)
            .fontColor('#FF0000')
            .fontFamily(this.appFontFamily)
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
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
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
        currentTheme: this.themeState.currentTheme,
        appFontFamily: this.appFontFamily
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
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .margin({ bottom: 16 })
          
          Text('检测到云端尚未初始化备份索引。\n\n是否立即初始化？初始化后将自动上传最新的本地备份到云端。')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .lineHeight(22)
            .margin({ bottom: 24 })
          
          Row() {
            Button('取消')
              .fontSize(16)
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
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
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(
          SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
          SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
        )
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(16)
        .clip(true)
        .border({
          width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
          color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
        })
        .shadow({
          radius: 18,
          color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
          offsetX: 0,
          offsetY: 10
        })
        .padding(24)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .justifyContent(FlexAlign.Center)
    }
  }
  
  @Builder
  buildFTPManagerPanel() {
    Column({ space: 12 }) {
      // 连接状态和配置区域
      if (!this.ftpConnected) {
        // 未连接时显示连接列表
        this.buildFTPConnectionList()
      } else {
        // 已连接时显示文件浏览器
        this.buildFTPFileBrowser()
      }
      
      // 编辑对话框
      if (this.showFTPEditDialog) {
        this.buildFTPEditDialog()
      }
    }
    .width('100%')
    .id('guide_backup_ftp_panel')
  }
  
  @Builder
  buildFTPConnectionList() {
    Column({ space: 12 }) {
      // 标题和添加按钮
      Row() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder_circle'))
            .fontSize(20)
            .fontColor(['#FF9800'])
          Text('FTP 连接管理')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        Blank()
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
            Text('添加').fontSize(13).fontColor('#FFFFFF').fontFamily(this.appFontFamily)
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FF9800')
        .borderRadius(6)
        .onClick(() => {
          this.ftpEditingConnection = null;
          this.ftpConnectionName = '';
          this.showFTPEditDialog = true;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      // 连接列表
      if (this.savedFTPConnections.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.folder_circle'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          Text('暂无保存的FTP连接')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 8 })
          Text('点击右上角"添加"按钮创建新连接')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.savedFTPConnections, (conn: SavedFTPConnection) => {
            ListItem() {
              this.buildFTPConnectionItem(conn)
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      
      // 错误提示
      if (this.ftpTestResult) {
        Text(this.ftpTestResult)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.ftpTestResult.startsWith('') ? '#4CAF50' : '#F44336')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16 })
      }
      
      // 加载状态
      if (this.ftpLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color('#FF9800')
          Text('连接中...').fontSize(13).fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(16)
      }
    }
  }
  
  @Builder
  buildFTPConnectionItem(conn: SavedFTPConnection) {
    Row({ space: 12 }) {
      // 图标
      Column() {
        SymbolGlyph($r('sys.symbol.folder_circle'))
          .fontSize(28)
          .fontColor([conn.useFTPS ? '#4CAF50' : '#FF9800'])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(8)
      
      // 连接信息
      Column({ space: 2 }) {
        Text(conn.name || conn.host)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(`${conn.host}:${conn.port}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Row({ space: 8 }) {
          if (conn.useFTPS) {
            Text('FTPS')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor('#4CAF50')
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor('#E8F5E9')
              .borderRadius(4)
          }
          Text(`@${conn.username}`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      // 操作按钮
      Row({ space: 4 }) {
        // 编辑
        Button() {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(18)
            .fontColor(['#2196F3'])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.ftpEditingConnection = conn;
          this.ftpConnectionName = conn.name;
          this.showFTPEditDialog = true;
        })
        
        // 删除
        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor(['#F44336'])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.getUIContext().showAlertDialog({
            title: '删除连接',
            message: `确定要删除 "${conn.name || conn.host}" 吗？`,
            primaryButton: { value: '取消', action: () => {} },
            secondaryButton: {
              value: '删除',
              fontColor: '#F44336',
              action: () => this.deleteFTPConnection(conn.id)
            }
          });
        })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 16,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .onClick(() => this.connectToSavedFTP(conn))
  }
  
  @Builder
  buildFTPEditDialog() {
    Column() {
      Column({ space: 12 }) {
        // 标题
        Text(this.ftpEditingConnection ? '编辑FTP连接' : '添加FTP连接')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        // 连接名称
        TextInput({ placeholder: '连接名称（可选）', text: this.ftpConnectionName })
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .height(44)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => { this.ftpConnectionName = value; })
        
        // 主机地址
        TextInput({ placeholder: 'FTP服务器地址', text: this.ftpEditingConnection?.host || '' })
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .height(44)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => {
            if (this.ftpEditingConnection) {
              this.ftpEditingConnection.host = value;
            } else {
              this.ftpEditingConnection = createFTPConnection(this.ftpConnectionName, value, 21, '', '', false, true);
            }
          })
        
        // 端口
        Row({ space: 8 }) {
          TextInput({ placeholder: '端口', text: (this.ftpEditingConnection?.port || 21).toString() })
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .type(InputType.Number)
            .width(100)
            .height(44)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .onChange((value: string) => {
              if (this.ftpEditingConnection) {
                this.ftpEditingConnection.port = parseInt(value) || 21;
              }
            })
          
          Row({ space: 6 }) {
            Checkbox().select(this.ftpEditingConnection?.useFTPS || false).selectedColor('#FF9800')
              .onChange((value: boolean) => {
                if (this.ftpEditingConnection) {
                  this.ftpEditingConnection.useFTPS = value;
                  this.ftpEditingConnection.port = value ? 990 : 21;
                }
              })
            Text('FTPS').fontSize(13).fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          
          Row({ space: 6 }) {
            Checkbox().select(this.ftpEditingConnection?.passive !== false).selectedColor('#FF9800')
              .onChange((value: boolean) => {
                if (this.ftpEditingConnection) {
                  this.ftpEditingConnection.passive = value;
                }
              })
            Text('被动模式').fontSize(13).fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .width('100%')
        
        // 用户名
        TextInput({ placeholder: '用户名', text: this.ftpEditingConnection?.username || '' })
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .height(44)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => {
            if (this.ftpEditingConnection) {
              this.ftpEditingConnection.username = value;
            }
          })
        
        // 密码
        TextInput({ placeholder: '密码', text: this.ftpEditingConnection?.password || '' })
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .type(InputType.Password)
          .height(44)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .onChange((value: string) => {
            if (this.ftpEditingConnection) {
              this.ftpEditingConnection.password = value;
            }
          })
        
        // 按钮
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(8)
            .layoutWeight(1)
            .height(44)
            .onClick(() => {
              this.showFTPEditDialog = false;
              this.ftpEditingConnection = null;
            })
          
          Button('保存')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .fontFamily(this.appFontFamily)
            .backgroundColor('#FF9800')
            .borderRadius(8)
            .layoutWeight(1)
            .height(44)
            .onClick(async () => {
              if (!this.ftpEditingConnection?.host) {
                this.getUIContext().getPromptAction().showToast({ message: '请输入服务器地址', duration: 2000 });
                return;
              }
              
              this.ftpEditingConnection.name = this.ftpConnectionName || this.ftpEditingConnection.host;
              
              // 检查是新建还是编辑
              const existingIndex = this.savedFTPConnections.findIndex((c: SavedFTPConnection) => c.id === this.ftpEditingConnection!.id);
              if (existingIndex >= 0) {
                await this.updateFTPConnection(this.ftpEditingConnection);
              } else {
                await this.addFTPConnection(this.ftpEditingConnection);
              }
              
              this.showFTPEditDialog = false;
              this.ftpEditingConnection = null;
              this.getUIContext().getPromptAction().showToast({ message: '保存成功', duration: 2000 });
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 18,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
  }
  
  @Builder
  buildFTPFileBrowser() {
    Column({ space: 0 }) {
      // 顶部工具栏
      Row({ space: 8 }) {
        // 断开连接按钮
        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(16)
              .fontColor(['#FFFFFF'])
            Text('断开').fontSize(13).fontColor('#FFFFFF').fontFamily(this.appFontFamily)
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#F44336')
        .borderRadius(6)
        .onClick(() => this.disconnectFTP())
        
        // 服务器信息
        Text(this.currentFTPConnection ? `${this.currentFTPConnection.name || this.currentFTPConnection.host}` : '')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        // 刷新按钮
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor(['#FF9800'])
        }
        .width(36)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => this.refreshFTPList())
        
        // 新建文件夹按钮
        Button() {
          SymbolGlyph($r('sys.symbol.folder_badge_plus'))
            .fontSize(18)
            .fontColor(['#FF9800'])
        }
        .width(36)
        .height(36)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => this.createFTPDirectory())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      
      // 当前路径
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(16)
          .fontColor(['#FF9800'])
        Text(this.ftpCurrentPath || '/')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        // 返回上级目录
        if (this.ftpCurrentPath !== '/') {
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_up'))
                .fontSize(14)
                .fontColor(['#FF9800'])
              Text('上级').fontSize(12).fontColor('#FF9800').fontFamily(this.appFontFamily)
            }
          }
          .height(28)
          .padding({ left: 8, right: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .borderRadius(6)
          .onClick(() => this.navigateToParent())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(16)
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: 16,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      
      // 文件列表
      if (this.ftpLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color('#FF9800')
          Text('加载中...').fontSize(13).fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.ftpFiles.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          Text('目录为空').fontSize(14).fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.ftpFiles, (file: FTPFileInfo) => {
            ListItem() {
              this.buildFTPFileItem(file)
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  @Builder
  buildFTPFileItem(file: FTPFileInfo) {
    Row({ space: 12 }) {
      // 文件图标
      SymbolGlyph(file.isDirectory ? $r('sys.symbol.folder_fill') : $r('sys.symbol.doc_plaintext_fill'))
        .fontSize(24)
        .fontColor([file.isDirectory ? '#FF9800' : '#2196F3'])
      
      // 文件信息
      Column({ space: 2 }) {
        Text(file.name)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Row({ space: 8 }) {
          if (!file.isDirectory && file.size > 0) {
            Text(this.formatFileSize(file.size))
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          if (file.permissions) {
            Text(file.permissions)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      // 操作按钮
      if (!file.isDirectory) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_down_circle'))
            .fontSize(20)
            .fontColor(['#4CAF50'])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.downloadFTPFile(file))
      }
      
      Button() {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor(['#F44336'])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.deleteFTPItem(file))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(16)
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: 14,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 6
    })
    .onClick(() => {
      if (file.isDirectory) {
        this.navigateToDirectory(file.path);
      }
    })
  }
  
  // FTP操作方法
  disconnectFTP(): void {
    this.currentFTPConnection = null;
    if (this.ftpClient) {
      this.ftpClient.destroy();
      this.ftpClient = null;
    }
    this.ftpConnected = false;
    this.ftpFiles = [];
    this.ftpCurrentPath = '/';
    this.ftpTestResult = '';
  }
  
  async refreshFTPList(): Promise<void> {
    if (!this.ftpClient) return;
    
    this.ftpLoading = true;
    try {
      this.ftpFiles = await this.ftpClient.list(this.ftpCurrentPath);
    } catch (e) {
      logger.error(TAG, `刷新FTP列表失败: ${e}`);
      this.getUIContext().getPromptAction().showToast({ message: `刷新失败: ${e}`, duration: 2000 });
    } finally {
      this.ftpLoading = false;
    }
  }
  
  async navigateToDirectory(path: string): Promise<void> {
    this.ftpCurrentPath = path;
    await this.refreshFTPList();
  }
  
  navigateToParent(): void {
    if (this.ftpCurrentPath === '/') return;
    const parts = this.ftpCurrentPath.split('/').filter((p: string) => p);
    parts.pop();
    this.ftpCurrentPath = '/' + parts.join('/');
    if (this.ftpCurrentPath !== '/') this.ftpCurrentPath += '/';
    this.refreshFTPList();
  }
  
  async createFTPDirectory(): Promise<void> {
    if (!this.ftpClient) return;
    
    // 使用简单的输入对话框
    this.getUIContext().showAlertDialog({
      title: '新建文件夹',
      message: '请输入文件夹名称',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '创建',
        action: async () => {
          // 由于AlertDialog不支持输入，使用默认名称
          const dirName = 'new_folder_' + Date.now();
          const result = await this.ftpClient!.mkdir(this.ftpCurrentPath + dirName);
          if (result.success) {
            this.getUIContext().getPromptAction().showToast({ message: '文件夹创建成功', duration: 2000 });
            await this.refreshFTPList();
          } else {
            this.getUIContext().getPromptAction().showToast({ message: `创建失败: ${result.message}`, duration: 2000 });
          }
        }
      }
    });
  }
  
  async downloadFTPFile(file: FTPFileInfo): Promise<void> {
    if (!this.ftpClient) return;
    
    this.getUIContext().getPromptAction().showToast({ message: '开始下载...', duration: 1000 });
    
    const localPath = `/data/storage/el2/base/haps/entry/files/downloads/${file.name}`;
    const result = await this.ftpClient.download(file.path, localPath);
    
    if (result.success) {
      this.getUIContext().getPromptAction().showToast({ message: `下载成功: ${file.name}`, duration: 2000 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: `下载失败: ${result.message}`, duration: 2000 });
    }
  }
  
  async deleteFTPItem(file: FTPFileInfo): Promise<void> {
    if (!this.ftpClient) return;
    
    this.getUIContext().showAlertDialog({
      title: '确认删除',
      message: `确定要删除 "${file.name}" 吗？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#F44336',
        action: async () => {
          const result = file.isDirectory 
            ? await this.ftpClient!.rmdir(file.path)
            : await this.ftpClient!.deleteFile(file.path);
          
          if (result.success) {
            this.getUIContext().getPromptAction().showToast({ message: '删除成功', duration: 2000 });
            await this.refreshFTPList();
          } else {
            this.getUIContext().getPromptAction().showToast({ message: `删除失败: ${result.message}`, duration: 2000 });
          }
        }
      }
    });
  }
  
  formatFileSize(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB';
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + ' GB';
  }
  
  // FTP连接配置持久化方法
  async loadFTPConnections(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const options: preferences.Options = { name: 'ftp_connections' };
      const dataPreferences: preferences.Preferences = await preferences.getPreferences(context, options);
      
      const connectionsJson = await dataPreferences.get('connections', '[]') as string;
      this.savedFTPConnections = SafeUtils.parseArr(connectionsJson) as SavedFTPConnection[];
      logger.info(TAG, `加载了 ${this.savedFTPConnections.length} 个FTP连接配置`);
    } catch (e) {
      logger.error(TAG, `加载FTP连接配置失败: ${e}`);
      this.savedFTPConnections = [];
    }
  }
  
  async saveFTPConnections(): Promise<void> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      const options: preferences.Options = { name: 'ftp_connections' };
      const dataPreferences: preferences.Preferences = await preferences.getPreferences(context, options);
      
      await dataPreferences.put('connections', JSON.stringify(this.savedFTPConnections));
      await dataPreferences.flush();
      logger.info(TAG, `保存了 ${this.savedFTPConnections.length} 个FTP连接配置`);
    } catch (e) {
      logger.error(TAG, `保存FTP连接配置失败: ${e}`);
    }
  }
  
  async addFTPConnection(connection: SavedFTPConnection): Promise<void> {
    this.savedFTPConnections.push(connection);
    await this.saveFTPConnections();
  }
  
  async updateFTPConnection(connection: SavedFTPConnection): Promise<void> {
    const index = this.savedFTPConnections.findIndex((c: SavedFTPConnection) => c.id === connection.id);
    if (index >= 0) {
      this.savedFTPConnections[index] = connection;
      await this.saveFTPConnections();
    }
  }
  
  async deleteFTPConnection(connectionId: string): Promise<void> {
    this.savedFTPConnections = this.savedFTPConnections.filter((c: SavedFTPConnection) => c.id !== connectionId);
    await this.saveFTPConnections();
  }
  
  async connectToSavedFTP(connection: SavedFTPConnection): Promise<void> {
    this.currentFTPConnection = connection;
    this.ftpLoading = true;
    this.ftpTestResult = '';
    
    try {
      const config: FTPConfig = {
        host: connection.host,
        port: connection.port,
        username: connection.username,
        password: connection.password,
        useFTPS: connection.useFTPS,
        passive: connection.passive,
        timeoutMs: connection.timeoutMs
      };
      
      this.ftpClient = new FTPNativeClient(config);
      const result = await this.ftpClient.testConnection();
      
      if (result.success) {
        this.ftpConnected = true;
        this.ftpCurrentPath = '/';
        // 更新最后使用时间
        connection.lastUsedAt = Date.now();
        await this.updateFTPConnection(connection);
        await this.refreshFTPList();
      } else {
        this.ftpTestResult = `❌ ${result.message}`;
        this.ftpClient.destroy();
        this.ftpClient = null;
        this.currentFTPConnection = null;
      }
    } catch (e) {
      this.ftpTestResult = `❌ 连接失败: ${e}`;
      if (this.ftpClient) {
        this.ftpClient.destroy();
        this.ftpClient = null;
      }
      this.currentFTPConnection = null;
    } finally {
      this.ftpLoading = false;
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
