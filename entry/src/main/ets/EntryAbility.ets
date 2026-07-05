import { SafeUtils } from './Utils/SafeUtils';
//文件路径：entry/src/main/ets/EntryAbility.ets
/**
 * 应用入口Ability
 * 负责初始化应用上下文、数据管理系统和窗口管理
 */
 
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { setContext } from './GlobalContext';
import { DeepLinkRouter } from './Framework/Utils/DeepLinkRouter';
import { logger } from './Utils/Logger';
import { WindowManager, DisplayMode } from './Utils/WindowManager';
import { OrientationLockApplyResult, OrientationLockManager, OrientationLockStrategy } from './Utils/OrientationLockManager';
import { DataInitializer } from './Framework/Initialization/DataInitializer';
import { ThemeManager } from './Framework/Managers/ThemeManager';
import { DeviceAdaptationManager } from './Framework/Managers/DeviceAdaptationManager';
import { SettingsManager, SettingKeys } from './Framework/Managers/SettingsManager';
import { AnimationSettingsManager } from './Framework/Animation/AnimationSettingsManager';
import { VisualEffectsManager } from './Framework/Managers/VisualEffectsManager';
import { AppNotificationManager } from './Framework/Managers/NotificationManager';
import { MangaDownloadManager } from './Framework/Download/DownloadManager';
import { getNovelSourceValidator } from './Framework/Novel/NovelSourceValidator';
import { uiContextManager } from './Framework/Managers/UIContextManager';
import { ProxyManager } from './Framework/Network/ProxyManager';
import { getFontManager } from './Framework/Managers/FontManager';
import { getDownloadSyncManager } from './Framework/Managers/DownloadSyncManager';
import { getChangelogManager } from './Framework/Managers/ChangelogManager';
import { getAutoBackupScheduler } from './Framework/WebDAV/WebDAVAutoBackupScheduler';
import { widgetDataSync } from './Utils/WidgetDataSync';
import { getUnifiedDetailPageEnforcer } from './Framework/Enforcement/UnifiedDetailPageEnforcer';
import { InitPhase } from './Framework/Managers/AppInitializationManager';
import { getCrashRecorderService } from './Framework/Debug/CrashRecorderService';
import { getErrorMonitorService } from './Framework/Debug/ErrorMonitorService';
import { getErrorRecordManager } from './Framework/Debug/ErrorRecordManager';
import { getHoldingAwarenessManager } from './Framework/Managers/HoldingAwarenessManager';
import { initializeReaderKitRuntimeGate } from './Framework/Initialization/ReaderKitFeatureGate';
import { ReaderHostWindowRestoreCoordinator } from './Framework/Reader/ReaderHostWindowRestoreCoordinator';
import {
  NETWORK_FOLDER_AVIF_EXTENSIONS,
  NETWORK_FOLDER_BACKUP_EXTENSIONS,
  NETWORK_FOLDER_CODE_EXTENSIONS,
  NETWORK_FOLDER_COMIC_EXTENSIONS,
  NETWORK_FOLDER_EBOOK_EXTENSIONS,
  NETWORK_FOLDER_FONT_EXTENSIONS,
  NETWORK_FOLDER_IMAGE_EXTENSIONS,
  NETWORK_FOLDER_JSON_EXTENSIONS
} from './Models/NetworkFolderModels';
import {
  ngfContentSourceIntegrationFacade,
  ngfContentWorkflowIntegrationFacade,
  ngfCoreEventBridge,
  ngfCoreIntegrationFacade,
  ngfDataIntegrationFacade,
  ngfLifecycleOrchestratorFacade,
  ngfPlatformOhosIntegrationFacade,
  ngfSettingsStoreFacade,
  ngfUiShellIntegrationFacade
} from './Framework/NGF';
import { BasePayload, eventBus, GameEvent, ContinuationTriggeredPayload } from './Framework/EventBus';
import { distributedFileManager } from './Framework/Distributed/DistributedFileManager';
import { distributedDataSyncManager } from './Framework/Distributed/DistributedDataSyncManager';
import { openExternalFileTaskInIsolatedAbilityByContext } from './Framework/ExternalFile/ExternalFileTaskLauncher';
import {
  ExternalFileTaskFactory,
  ExternalFileTaskKind,
  ExternalFileTaskParams,
  ExternalFileTaskSource
} from './Framework/ExternalFile/ExternalFileTaskTypes';

export default class EntryAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.startup('EntryAbility', 'onCreate START', 'EntryAbility开始创建');
    initializeReaderKitRuntimeGate('EntryAbility.onCreate');
    
    // 初始化分布式管理器
    distributedFileManager.initialize(this.context);
    distributedDataSyncManager.initialize(this.context);

    // 处理跨端接续 (App Continuation)
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.restoreContinuationState(want);
    }
    
    // 详细记录Want信息用于调试
    logger.info('EntryAbility', `📋 Want详情: uri=${want.uri || 'null'}, type=${want.type || 'null'}, action=${want.action || 'null'}`);
    if (want.parameters) {
      logger.info('EntryAbility', `📋 Want参数: ${JSON.stringify(Object.keys(want.parameters))}`);
    }

    // 优先处理文件分享导入（排在最前，避免 params 键的存在导致误入卡片逻辑）
    if (want.parameters && want.parameters['share_import_files']) {
      this.handleShareImport(want);
    }
    else if (this.handleNotificationNavigation(want, false)) {
      logger.info('EntryAbility', '📣 已记录通知点击导航目标');
    }
    // 检查是否通过 Deep Link 打开应用（manxia:// 或 https://manxia.top/）
    else if (this.isDeepLinkUri(want.uri || '')) {
      const uri: string = want.uri || '';
      logger.info('EntryAbility', `🔗 通过 Deep Link 打开应用: ${uri}`);
      this.handleDeepLink(uri);
    }
    // 检查是否通过文件打开应用
    else if (want.uri) {
      logger.info('EntryAbility', `📁 通过文件打开应用: ${want.uri}, type=${want.type || 'unknown'}`);
      this.handleFileOpen(want.uri, want.type || '', ExternalFileTaskSource.FILE_OPEN);
    } else if (want.parameters) {
      // 兼容性处理：某些系统可能将文件信息放在parameters中
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      // 检查是否来自fileContextMenu（文件管理器右键菜单）
      const fileUris = want.parameters['fileUris'] as string[];
      const menuHandler = want.parameters['menuHandler'] as string;
      
      if (fileUris && fileUris.length > 0) {
        logger.info('EntryAbility', `📁 通过右键菜单打开文件: ${fileUris[0]}, handler=${menuHandler}`);
        this.handleFileOpen(fileUris[0], '', ExternalFileTaskSource.FILE_CONTEXT_MENU);
      } else if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件: ${uri}`);
        this.handleFileOpen(uri, type || '', ExternalFileTaskSource.FILE_OPEN);
      }
    }

    // 卡片router事件放最后（文件打开的Want也可能携带params，必须排在文件处理之后）
    if (want.parameters && want.parameters['params']) {
      this.handleWidgetRouter(want);
    }

    this.handleShortcutIntent(want);

    // 启动可监控的初始化流程
    this.runManagedInitialization();
  }
  
  /**
   * 执行可监控的初始化流程
   * 所有初始化按顺序执行，并通过AppInitializationManager报告进度
   */
  private async runManagedInitialization(): Promise<void> {
    const initManager = ngfLifecycleOrchestratorFacade;
    initManager.startInitialization();
    ngfCoreEventBridge.publishInitializationState(InitPhase.NOT_STARTED, 'started', '应用初始化流程已启动');
    
    // 阶段1：设置全局上下文
    initManager.beginPhase(InitPhase.CONTEXT_SETUP);
    try {
      setContext(this.context);
      uiContextManager.setAbilityContext(this.context);
      const ngfIntegrated = ngfCoreIntegrationFacade.bootstrap();
      if (ngfIntegrated) {
        logger.info('EntryAbility', '✅ NGF Core 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'integrated', 'NGF Core 运行时集成完成');
      } else {
        logger.warn('EntryAbility', '⚠️ NGF Core 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'fallback', 'NGF Core 集成失败，使用旧路径');
      }

      const ngfPlatformIntegrated = ngfPlatformOhosIntegrationFacade.bootstrap();
      if (ngfPlatformIntegrated) {
        logger.info('EntryAbility', '✅ NGF Platform OHOS 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'platform_integrated', 'NGF Platform OHOS 运行时集成完成');
      } else {
        logger.warn('EntryAbility', '⚠️ NGF Platform OHOS 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'platform_fallback', 'NGF Platform OHOS 集成失败，使用旧路径');
      }

      const ngfUiShellIntegrated = ngfUiShellIntegrationFacade.bootstrap();
      if (ngfUiShellIntegrated) {
        logger.info('EntryAbility', '✅ NGF UI Shell 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'ui_shell_integrated', 'NGF UI Shell 运行时集成完成');
      } else {
        logger.warn('EntryAbility', '⚠️ NGF UI Shell 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'ui_shell_fallback', 'NGF UI Shell 集成失败，使用旧路径');
      }

      const ngfDataIntegrated = ngfDataIntegrationFacade.bootstrap();
      if (ngfDataIntegrated) {
        logger.info('EntryAbility', '✅ NGF Data 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'data_integrated', 'NGF Data 运行时集成完成');
      } else {
        logger.warn('EntryAbility', '⚠️ NGF Data 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(InitPhase.CONTEXT_SETUP, 'data_fallback', 'NGF Data 集成失败，使用旧路径');
      }

      const ngfContentWorkflowIntegrated = ngfContentWorkflowIntegrationFacade.bootstrap();
      if (ngfContentWorkflowIntegrated) {
        logger.info('EntryAbility', '✅ NGF Content Workflow 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(
          InitPhase.CONTEXT_SETUP,
          'content_workflow_integrated',
          'NGF Content Workflow 运行时集成完成'
        );
      } else {
        logger.warn('EntryAbility', '⚠️ NGF Content Workflow 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(
          InitPhase.CONTEXT_SETUP,
          'content_workflow_fallback',
          'NGF Content Workflow 集成失败，使用旧路径'
        );
      }

      const ngfContentSourceIntegrated = ngfContentSourceIntegrationFacade.bootstrap();
      if (ngfContentSourceIntegrated) {
        logger.info('EntryAbility', '✅ NGF Content Source 运行时集成完成');
        ngfCoreEventBridge.publishInitializationState(
          InitPhase.CONTEXT_SETUP,
          'content_source_integrated',
          'NGF Content Source 运行时集成完成'
        );
      } else {
        logger.warn('EntryAbility', '⚠️ NGF Content Source 运行时集成失败，继续使用旧路径');
        ngfCoreEventBridge.publishInitializationState(
          InitPhase.CONTEXT_SETUP,
          'content_source_fallback',
          'NGF Content Source 集成失败，使用旧路径'
        );
      }

      logger.info('EntryAbility', '✅ GlobalContext 和 UIContextManager 设置成功');
      initManager.completePhase(InitPhase.CONTEXT_SETUP);
      this.publishInitPhaseCompleted(InitPhase.CONTEXT_SETUP, '上下文设置完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 上下文设置失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.CONTEXT_SETUP, errorMessage);
      ngfCoreEventBridge.publishInitializationFailed(InitPhase.CONTEXT_SETUP, errorMessage);
      return; // 关键阶段失败，停止初始化
    }

    // 阶段2：设备适配
    initManager.beginPhase(InitPhase.DEVICE_ADAPTATION);
    try {
      const deviceManager = DeviceAdaptationManager.getInstance();
      const deviceInfo = deviceManager.getDeviceInfo();
      logger.info('EntryAbility', `📱 设备适配: ${deviceInfo.deviceType}, ${deviceInfo.breakpoint}`);
      initManager.completePhase(InitPhase.DEVICE_ADAPTATION);
      this.publishInitPhaseCompleted(InitPhase.DEVICE_ADAPTATION, '设备适配完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 设备适配失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.DEVICE_ADAPTATION, errorMessage);
      this.publishInitPhaseFailed(InitPhase.DEVICE_ADAPTATION, errorMessage);
      // 非关键阶段，继续执行
    }

    // 阶段3：数据系统初始化
    initManager.beginPhase(InitPhase.DATA_SYSTEM);
    try {
      const dataInitializer = DataInitializer.getInstance();
      const result = await dataInitializer.initialize(this.context, {
        enableAutoBackup: true,
        enableDataSync: false,
        cacheConfig: {
          maxImageCacheSize: 500 * 1024 * 1024,
          maxDiskCacheAge: 7 * 24 * 60 * 60 * 1000
        },
        databaseConfig: {
          enableWAL: true,
          pageSize: 4096,
          cacheSize: 2000
        }
      });
      
      if (result.success) {
        logger.info('EntryAbility', `✅ 数据系统初始化成功，耗时: ${result.duration}ms`);
        initManager.completePhase(InitPhase.DATA_SYSTEM);
        this.publishInitPhaseCompleted(InitPhase.DATA_SYSTEM, `数据系统初始化完成，耗时: ${result.duration}ms`);
      } else {
        throw new Error(result.errors.join(', '));
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 数据系统初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.DATA_SYSTEM, errorMessage);
      ngfCoreEventBridge.publishInitializationFailed(InitPhase.DATA_SYSTEM, errorMessage);
      return; // 关键阶段失败，停止初始化
    }

    // 阶段4：设置管理器
    initManager.beginPhase(InitPhase.SETTINGS);
    try {
      await this.initializeAppStorage();
      initManager.completePhase(InitPhase.SETTINGS);
      this.publishInitPhaseCompleted(InitPhase.SETTINGS, '设置管理器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 设置管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.SETTINGS, errorMessage);
      ngfCoreEventBridge.publishInitializationFailed(InitPhase.SETTINGS, errorMessage);
      return; // 关键阶段失败，停止初始化
    }

    // 阶段5：字体管理器（关键 - 修复字体失效问题）
    initManager.beginPhase(InitPhase.FONT_MANAGER);
    try {
      const fontManager = getFontManager();
      await fontManager.initialize(this.context);
      logger.info('EntryAbility', '✅ 字体管理器初始化成功');
      initManager.completePhase(InitPhase.FONT_MANAGER);
      this.publishInitPhaseCompleted(InitPhase.FONT_MANAGER, '字体管理器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 字体管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.FONT_MANAGER, errorMessage);
      ngfCoreEventBridge.publishInitializationFailed(InitPhase.FONT_MANAGER, errorMessage);
      return; // 关键阶段失败，停止初始化
    }

    // 阶段6：代理管理器
    initManager.beginPhase(InitPhase.PROXY_MANAGER);
    try {
      const proxyManager = ProxyManager.getInstance();
      await proxyManager.initialize();
      logger.info('EntryAbility', `✅ 代理管理器初始化成功`);
      initManager.completePhase(InitPhase.PROXY_MANAGER);
      this.publishInitPhaseCompleted(InitPhase.PROXY_MANAGER, '代理管理器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 代理管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.PROXY_MANAGER, errorMessage);
      this.publishInitPhaseFailed(InitPhase.PROXY_MANAGER, errorMessage);
    }

    // 阶段7：下载同步管理器
    initManager.beginPhase(InitPhase.DOWNLOAD_SYNC);
    try {
      const downloadSyncManager = getDownloadSyncManager();
      await downloadSyncManager.initialize();
      logger.info('EntryAbility', '✅ 下载同步管理器初始化成功');
      initManager.completePhase(InitPhase.DOWNLOAD_SYNC);
      this.publishInitPhaseCompleted(InitPhase.DOWNLOAD_SYNC, '下载同步管理器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 下载同步管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.DOWNLOAD_SYNC, errorMessage);
      this.publishInitPhaseFailed(InitPhase.DOWNLOAD_SYNC, errorMessage);
    }

    // 阶段8：下载管理器
    initManager.beginPhase(InitPhase.DOWNLOAD_MANAGER);
    try {
      const downloadManager = MangaDownloadManager.getInstance();
      downloadManager.setContext(this.context);
      // 同步设置书源校验器的 context，确保后台长时任务可用
      getNovelSourceValidator().setContext(this.context);
      logger.info('EntryAbility', '✅ 下载管理器 & 书源校验器初始化成功');
      initManager.completePhase(InitPhase.DOWNLOAD_MANAGER);
      this.publishInitPhaseCompleted(InitPhase.DOWNLOAD_MANAGER, '下载管理器与书源校验器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 下载管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.DOWNLOAD_MANAGER, errorMessage);
      this.publishInitPhaseFailed(InitPhase.DOWNLOAD_MANAGER, errorMessage);
    }

    // 阶段9：自动备份调度器
    initManager.beginPhase(InitPhase.AUTO_BACKUP);
    try {
      const scheduler = getAutoBackupScheduler();
      await scheduler.initialize(this.context);
      logger.info('EntryAbility', '✅ 自动备份调度器初始化成功');
      initManager.completePhase(InitPhase.AUTO_BACKUP);
      this.publishInitPhaseCompleted(InitPhase.AUTO_BACKUP, '自动备份调度器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 自动备份调度器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.AUTO_BACKUP, errorMessage);
      this.publishInitPhaseFailed(InitPhase.AUTO_BACKUP, errorMessage);
    }

    // 阶段10：桌面卡片同步
    initManager.beginPhase(InitPhase.WIDGET_SYNC);
    try {
      widgetDataSync.init(this.context);
      await widgetDataSync.syncAllData();
      logger.info('EntryAbility', '✅ 桌面卡片同步初始化成功');
      initManager.completePhase(InitPhase.WIDGET_SYNC);
      this.publishInitPhaseCompleted(InitPhase.WIDGET_SYNC, '桌面卡片同步初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 桌面卡片同步初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.WIDGET_SYNC, errorMessage);
      this.publishInitPhaseFailed(InitPhase.WIDGET_SYNC, errorMessage);
    }

    // 阶段11：更新日志管理器
    initManager.beginPhase(InitPhase.CHANGELOG);
    try {
      const changelogManager = getChangelogManager();
      await changelogManager.initialize(this.context);
      if (changelogManager.shouldShowChangelog()) {
        AppStorage.setOrCreate('shouldShowChangelog', true);
      }
      logger.info('EntryAbility', '✅ 更新日志管理器初始化成功');
      initManager.completePhase(InitPhase.CHANGELOG);
      this.publishInitPhaseCompleted(InitPhase.CHANGELOG, '更新日志管理器初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 更新日志管理器初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.CHANGELOG, errorMessage);
      this.publishInitPhaseFailed(InitPhase.CHANGELOG, errorMessage);
    }

    // 初始化统一错误记录管理器（必须在 CrashRecorder/ErrorMonitor 之前）
    try {
      getErrorRecordManager().initialize(this.context);
      logger.info('EntryAbility', '✅ 统一错误记录管理器初始化成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 统一错误记录管理器初始化失败: ${errorMessage}`);
    }

    // 阶段12：闪退记录服务（尽早注册，捕获后续初始化阶段的崩溃）
    initManager.beginPhase(InitPhase.CRASH_RECORDER);
    try {
      const crashRecorder = getCrashRecorderService();
      crashRecorder.initialize(this.context);
      crashRecorder.cleanOldCrashLogs();
      logger.info('EntryAbility', '✅ 闪退记录服务初始化成功');
      initManager.completePhase(InitPhase.CRASH_RECORDER);
      this.publishInitPhaseCompleted(InitPhase.CRASH_RECORDER, '闪退记录服务初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 闪退记录服务初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.CRASH_RECORDER, errorMessage);
      this.publishInitPhaseFailed(InitPhase.CRASH_RECORDER, errorMessage);
    }

    // 阶段13：错误监控服务（延迟500ms启动，确保日志系统完全就绪）
    initManager.beginPhase(InitPhase.ERROR_MONITOR);
    try {
      const errorMonitor = getErrorMonitorService();
      // 延迟启动，与日志系统略有延迟同步
      setTimeout((): void => {
        try {
          errorMonitor.start(this.context);
          logger.info('EntryAbility', '✅ 错误监控服务已延迟启动');
        } catch (delayError) {
          const msg = delayError instanceof Error ? delayError.message : String(delayError);
          logger.warn('EntryAbility', `⚠️ 错误监控服务延迟启动失败: ${msg}`);
        }
      }, 500);
      logger.info('EntryAbility', '✅ 错误监控服务初始化成功（将在500ms后启动）');
      initManager.completePhase(InitPhase.ERROR_MONITOR);
      this.publishInitPhaseCompleted(InitPhase.ERROR_MONITOR, '错误监控服务初始化完成');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.warn('EntryAbility', `⚠️ 错误监控服务初始化失败: ${errorMessage}`);
      initManager.failPhase(InitPhase.ERROR_MONITOR, errorMessage);
      this.publishInitPhaseFailed(InitPhase.ERROR_MONITOR, errorMessage);
    }

    // 所有阶段完成
    initManager.markCompleted();
    ngfCoreEventBridge.publishInitializationCompleted('应用初始化流程全部完成');
  }

  private publishInitPhaseCompleted(phase: InitPhase, message: string): void {
    ngfCoreEventBridge.publishInitializationState(phase, 'completed', message);
  }

  private publishInitPhaseFailed(phase: InitPhase, errorMessage: string): void {
    ngfCoreEventBridge.publishInitializationFailed(phase, errorMessage);
  }
  
  /**
   * 初始化AppStorage（从数据库加载设置）
   * 注意：此方法必须在数据库初始化完成后调用
   */
  private async initializeAppStorage(): Promise<void> {
    try {
      logger.info('EntryAbility', '🔧 开始初始化设置管理器');
      
      // 初始化设置管理器
      const settingsManager = SettingsManager.getInstance();
      await settingsManager.initialize();

      // 同步设置到AppStorage
      settingsManager.syncToAppStorage();

      // 初始化动画设置管理器
      const animationSettingsManager = AnimationSettingsManager.getInstance();
      await animationSettingsManager.initialize();
      const visualEffectsManager = VisualEffectsManager.getInstance();
      await visualEffectsManager.initialize();
      logger.info('EntryAbility', '视觉效果管理器初始化完成');
      logger.info('EntryAbility', '✅ 动画设置管理器初始化完成');

      // 记录关键设置
      const advancedMode = ngfSettingsStoreFacade.getBoolean(SettingKeys.ADVANCED_MODE_ENABLED, true);
      logger.info('EntryAbility', `✅ 高级模式设置: ${advancedMode}`);
      
      // 初始化后台模糊遮罩设置到AppStorage
      const backgroundBlurEnabled = ngfSettingsStoreFacade.getBoolean(SettingKeys.BACKGROUND_BLUR_ENABLED, false);
      const backgroundBlurBgType = ngfSettingsStoreFacade.getString(SettingKeys.BACKGROUND_BLUR_BG_TYPE, 'solid');
      const backgroundBlurBgImage = ngfSettingsStoreFacade.getString(SettingKeys.BACKGROUND_BLUR_BG_IMAGE, '');
      const backgroundBlurIconType = ngfSettingsStoreFacade.getString(SettingKeys.BACKGROUND_BLUR_ICON_TYPE, 'shield');
      AppStorage.setOrCreate('backgroundBlurEnabled', backgroundBlurEnabled);
      AppStorage.setOrCreate('backgroundBlurBgType', backgroundBlurBgType);
      AppStorage.setOrCreate('backgroundBlurBgImage', backgroundBlurBgImage);
      AppStorage.setOrCreate('backgroundBlurIconType', backgroundBlurIconType);
      void getHoldingAwarenessManager().initialize();
      WindowManager.syncBackgroundState(false, '应用启动初始化');
      logger.info('EntryAbility', `✅ 后台模糊遮罩设置: enabled=${backgroundBlurEnabled}, bgType=${backgroundBlurBgType}, iconType=${backgroundBlurIconType}`);
      
      // 初始化日志等级设置
      const logOutputLevel = ngfSettingsStoreFacade.getNumber(SettingKeys.LOG_OUTPUT_LEVEL, 0); // 默认关闭
      logger.initializeHilogLevelFromIndex(logOutputLevel);
      
      // 初始化并执行统一详情页强制覆盖
      await this.enforceUnifiedDetailPage();
      
      logger.info('EntryAbility', '✅ 设置管理器初始化完成，所有设置已同步到AppStorage');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 设置初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 强制执行统一详情页设置覆盖
   * 在APP启动时检测并强制所有详情页设置为统一详情页
   */
  private async enforceUnifiedDetailPage(): Promise<void> {
    try {
      logger.info('EntryAbility', '🛡️ 开始执行统一详情页强制覆盖...');
      
      const enforcer = getUnifiedDetailPageEnforcer();
      await enforcer.initialize();
      
      // 执行强制覆盖
      const result = await enforcer.enforce();
      
      if (result.success) {
        if (result.enforced) {
          logger.info('EntryAbility', `✅ ${result.message}`);
          // 记录变更详情
          result.changes.forEach(change => {
            logger.debug('EntryAbility', `  - ${change.scene}: ${change.oldValue} → ${change.newValue}`);
          });
        } else {
          logger.info('EntryAbility', `✅ ${result.message}`);
        }
      } else {
        logger.warn('EntryAbility', `⚠️ 统一详情页强制覆盖失败: ${result.message}`);
      }
      
      // 输出当前状态
      const status = enforcer.getCurrentStatus();
      logger.debug('EntryAbility', `📊 当前详情页设置状态: manga=${status.manga}, ebook=${status.ebook}, novel=${status.novel}`);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 统一详情页强制执行器初始化失败: ${errorMessage}`);
      // 不影响应用启动，继续执行
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.lifecycle('EntryAbility', '窗口阶段创建', '开始加载UI...');

    // 使用新的WindowManager设置默认显示模式（显示所有系统栏）
    try {
      // 初始化WindowManager（已包含设置默认系统栏和存储系统栏高度）
      WindowManager.initialize(windowStage);
      
      // [修复] 启用自动旋转需要在页面加载后才能获取UIContext
      // 因此将此操作移到页面加载完成后执行
      const mainWindow = windowStage.getMainWindowSync();
      
      // 通过全局方向锁定管理器设置自动旋转，不需要UIContext
      // 等待方向设置完成后再加载SplashPage，确保系统方向锁定已正确应用
      OrientationLockManager.applyStrategyToWindow(
        mainWindow,
        OrientationLockStrategy.AUTO_ROTATION_RESTRICTED,
        'EntryAbility.onWindowStageCreate'
      )
        .then((result: OrientationLockApplyResult) => {
          if (result.success) {
            logger.info('EntryAbility', '✅ 使用WindowManager设置默认显示模式成功（显示所有系统栏 + 自动旋转）');
          } else {
            logger.error('EntryAbility', `❌ 设置自动旋转失败: ${result.message}`);
          }
          // 方向设置完成后加载SplashPage
          this.loadSplashPage(windowStage);
        })
        .catch((error: Error) => {
          logger.error('EntryAbility', `❌ 设置自动旋转异常: ${error.message}`);
          // 即使失败也要加载SplashPage
          this.loadSplashPage(windowStage);
        });
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ WindowManager初始化失败: ${errorMessage}`);
      // 即使失败也要加载SplashPage
      this.loadSplashPage(windowStage);
    }
  }

  onWindowStageDestroy(): void {
    logger.lifecycle('EntryAbility', '窗口阶段销毁');
    WindowManager.dispose();
  }

  /**
   * 加载启动页面
   */
  private loadSplashPage(windowStage: window.WindowStage): void {
    try {
      logger.info('EntryAbility', '🚀 开始加载SplashPage，主题初始化将由SplashPage负责');

      windowStage.loadContent('pages/SplashPage', (err) => {
        if (err && err.code !== 0) {
          logger.error('EntryAbility', `❌ 加载SplashPage失败: ${JSON.stringify(err)}`);
          return;
        } else {
          logger.info('EntryAbility', '✅ SplashPage 加载成功');
        }
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 加载SplashPage异常: ${errorMessage}`);
    }
  }

  // 文件类型常量
  private static readonly FILE_TYPE_AVIF: string = 'avif';
  private static readonly FILE_TYPE_IMAGE: string = 'image';
  private static readonly FILE_TYPE_BACKUP: string = 'backup';
  private static readonly FILE_TYPE_COMIC: string = 'comic';
  private static readonly FILE_TYPE_EBOOK: string = 'ebook';
  private static readonly FILE_TYPE_PDF: string = 'pdf';
  private static readonly FILE_TYPE_JSON: string = 'json';
  private static readonly FILE_TYPE_FONT: string = 'font';
  private static readonly FILE_TYPE_CODE: string = 'code';
  private static readonly FILE_TYPE_UNKNOWN: string = 'unknown';
  
  // 代码文件扩展名到语言的映射
  private static readonly CODE_EXTENSIONS: Map<string, string> = new Map([
    ['.ts', 'typescript'],
    ['.ets', 'typescript'],
    ['.js', 'javascript'],
    ['.jsx', 'javascript'],
    ['.tsx', 'typescript'],
    ['.jsonc', 'json'],
    ['.py', 'python'],
    ['.java', 'java'],
    ['.cpp', 'cpp'],
    ['.c', 'c'],
    ['.h', 'cpp'],
    ['.hpp', 'cpp'],
    ['.cs', 'csharp'],
    ['.go', 'go'],
    ['.rs', 'rust'],
    ['.swift', 'swift'],
    ['.kt', 'kotlin'],
    ['.rb', 'ruby'],
    ['.php', 'php'],
    ['.html', 'html'],
    ['.htm', 'html'],
    ['.css', 'css'],
    ['.scss', 'scss'],
    ['.less', 'less'],
    ['.xml', 'xml'],
    ['.yaml', 'yaml'],
    ['.yml', 'yaml'],
    ['.md', 'markdown'],
    ['.markdown', 'markdown'],
    ['.sql', 'sql'],
    ['.sh', 'shell'],
    ['.bash', 'shell'],
    ['.zsh', 'shell'],
    ['.ps1', 'powershell'],
    ['.bat', 'bat'],
    ['.cmd', 'bat'],
    ['.txt', 'plaintext'],
    ['.log', 'plaintext'],
    ['.ini', 'ini'],
    ['.conf', 'ini'],
    ['.cfg', 'ini'],
    ['.toml', 'toml'],
    ['.lua', 'lua'],
    ['.r', 'r'],
    ['.dart', 'dart'],
    ['.vue', 'vue'],
    ['.svelte', 'svelte']
  ]);

  /**
   * 获取文件扩展名（包含点号）
   */
  private getFileExtension(uri: string): string {
    const normalizedUri = this.normalizeUriForFileTypeDetect(uri);
    const lastDotIndex = normalizedUri.lastIndexOf('.');
    if (lastDotIndex === -1 || lastDotIndex >= normalizedUri.length - 1) {
      return '';
    }
    return normalizedUri.substring(lastDotIndex).toLowerCase();
  }

  private getFileExtensionWithoutDot(uri: string): string {
    const extension = this.getFileExtension(uri);
    if (extension.startsWith('.')) {
      return extension.substring(1);
    }
    return extension;
  }

  private normalizeUriForFileTypeDetect(uri: string): string {
    const trimmed = uri.trim();
    if (trimmed.length <= 0) {
      return '';
    }

    const queryIndex = trimmed.indexOf('?');
    const hashIndex = trimmed.indexOf('#');
    let endIndex = trimmed.length;
    if (queryIndex >= 0 && hashIndex >= 0) {
      endIndex = Math.min(queryIndex, hashIndex);
    } else if (queryIndex >= 0) {
      endIndex = queryIndex;
    } else if (hashIndex >= 0) {
      endIndex = hashIndex;
    }

    const pathPart = trimmed.substring(0, endIndex);
    try {
      return decodeURIComponent(pathPart).trim().toLowerCase();
    } catch (_error) {
      return pathPart.trim().toLowerCase();
    }
  }

  private isExtensionIn(extension: string, supportedExtensions: string[]): boolean {
    if (extension.length <= 0) {
      return false;
    }
    return supportedExtensions.includes(extension);
  }

  /**
   * 根据文件URI获取文件类型
   */
  private getFileTypeFromUri(uri: string): string {
    const extension = this.getFileExtensionWithoutDot(uri);
    
    // AVIF图片
    if (this.isExtensionIn(extension, NETWORK_FOLDER_AVIF_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_AVIF;
    }

    // 普通图片
    if (this.isExtensionIn(extension, NETWORK_FOLDER_IMAGE_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_IMAGE;
    }
    
    // 备份文件
    if (this.isExtensionIn(extension, NETWORK_FOLDER_BACKUP_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_BACKUP;
    }
    
    // 漫画压缩包
    if (this.isExtensionIn(extension, NETWORK_FOLDER_COMIC_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_COMIC;
    }
    
    // 电子书
    if (this.isExtensionIn(extension, NETWORK_FOLDER_EBOOK_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_EBOOK;
    }
    
    // PDF
    if (extension === 'pdf') {
      return EntryAbility.FILE_TYPE_PDF;
    }
    
    // JSON文件
    if (this.isExtensionIn(extension, NETWORK_FOLDER_JSON_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_JSON;
    }
    
    // 字体文件
    if (this.isExtensionIn(extension, NETWORK_FOLDER_FONT_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_FONT;
    }
    
    // 代码文件（检查扩展名是否在映射表中）
    const ext = this.getFileExtension(uri);
    if (ext.length > 0 && EntryAbility.CODE_EXTENSIONS.has(ext)) {
      return EntryAbility.FILE_TYPE_CODE;
    }
    if (this.isExtensionIn(extension, NETWORK_FOLDER_CODE_EXTENSIONS)) {
      return EntryAbility.FILE_TYPE_CODE;
    }
    
    return EntryAbility.FILE_TYPE_UNKNOWN;
  }

  private mapFileTypeToExternalTaskKind(fileType: string): ExternalFileTaskKind {
    switch (fileType) {
      case EntryAbility.FILE_TYPE_AVIF:
        return ExternalFileTaskKind.AVIF;
      case EntryAbility.FILE_TYPE_IMAGE:
        return ExternalFileTaskKind.IMAGE;
      case EntryAbility.FILE_TYPE_BACKUP:
        return ExternalFileTaskKind.BACKUP;
      case EntryAbility.FILE_TYPE_COMIC:
        return ExternalFileTaskKind.COMIC;
      case EntryAbility.FILE_TYPE_EBOOK:
        return ExternalFileTaskKind.EBOOK;
      case EntryAbility.FILE_TYPE_PDF:
        return ExternalFileTaskKind.PDF;
      case EntryAbility.FILE_TYPE_JSON:
        return ExternalFileTaskKind.JSON;
      case EntryAbility.FILE_TYPE_FONT:
        return ExternalFileTaskKind.FONT;
      case EntryAbility.FILE_TYPE_CODE:
        return ExternalFileTaskKind.CODE;
      default:
        return ExternalFileTaskKind.UNKNOWN;
    }
  }

  private buildExternalFileTaskParams(
    uri: string,
    mimeType: string,
    source: ExternalFileTaskSource
  ): ExternalFileTaskParams {
    const fileType = this.getFileTypeFromUri(uri);
    const kind = this.mapFileTypeToExternalTaskKind(fileType);
    const codeExt = this.getFileExtension(uri);
    const language = kind === ExternalFileTaskKind.CODE
      ? EntryAbility.CODE_EXTENSIONS.get(codeExt) || 'plaintext'
      : '';
    return ExternalFileTaskFactory.createSingleFileTask(
      kind,
      uri,
      mimeType,
      source,
      ExternalFileTaskFactory.extractFileName(uri),
      language
    );
  }

  private inferCodeLanguageFromFileName(fileName: string): string {
    const codeExt = this.getFileExtension(fileName);
    return EntryAbility.CODE_EXTENSIONS.get(codeExt) || 'plaintext';
  }

  private handleFileOpen(uri: string, mimeType: string, source: ExternalFileTaskSource = ExternalFileTaskSource.FILE_OPEN): void {
    const taskParams = this.buildExternalFileTaskParams(uri, mimeType, source);
    logger.info('EntryAbility', `📁 文件类型识别: ${taskParams.kind}, URI: ${uri}`);

    void openExternalFileTaskInIsolatedAbilityByContext(
      this.context,
      taskParams,
      'EntryAbility.fileOpen'
    ).then((started: boolean): void => {
      if (started) {
        logger.info('EntryAbility', `✅ 已交由外部文件独立实例处理: ${uri}`);
        return;
      }
      this.handleFileOpenFallback(uri, mimeType);
      this.notifyFileOpenToUI();
    });
  }

  /**
   * 处理文件打开请求
   * 根据文件类型设置不同的AppStorage标记，供后续页面处理
   */
  private handleFileOpenFallback(uri: string, mimeType: string): void {
    const fileType = this.getFileTypeFromUri(uri);
    logger.info('EntryAbility', `📁 文件独立实例不可用，回退旧流程: ${fileType}, URI: ${uri}`);
    
    switch (fileType) {
      case EntryAbility.FILE_TYPE_AVIF:
        // AVIF文件：跳转到AVIF查看器
        logger.info('EntryAbility', `🖼️ 检测到AVIF文件，将打开AVIF查看器`);
        AppStorage.setOrCreate('pendingAvifUri', uri);
        break;

      case EntryAbility.FILE_TYPE_IMAGE:
        // 普通图片：跳转到图片查看器
        logger.info('EntryAbility', `🖼️ 检测到图片文件，将打开图片查看器`);
        AppStorage.setOrCreate('pendingAvifUri', uri);
        AppStorage.setOrCreate('pendingFileCategory', 'image');
        break;
        
      case EntryAbility.FILE_TYPE_BACKUP:
        // 备份文件：跳转到备份恢复页面
        logger.info('EntryAbility', `💾 检测到备份文件，将跳转到备份恢复页面`);
        AppStorage.setOrCreate('pendingBackupUri', uri);
        AppStorage.setOrCreate('pendingFileCategory', 'backup');
        break;
        
      case EntryAbility.FILE_TYPE_COMIC:
        // 漫画文件：跳转到文件导入页面（漫画导入流程）
        logger.info('EntryAbility', `📚 检测到漫画文件，将跳转到漫画导入流程`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', mimeType);
        AppStorage.setOrCreate('pendingFileCategory', 'comic');
        break;
        
      case EntryAbility.FILE_TYPE_EBOOK:
        // 电子书文件：跳转到文件导入页面（电子书导入流程）
        logger.info('EntryAbility', `📖 检测到电子书文件，将跳转到电子书导入流程`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', mimeType);
        AppStorage.setOrCreate('pendingFileCategory', 'ebook');
        break;
        
      case EntryAbility.FILE_TYPE_PDF:
        // PDF文件：跳转到文件导入页面（PDF导入流程）
        logger.info('EntryAbility', `📄 检测到PDF文件，将跳转到PDF导入流程`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', mimeType);
        AppStorage.setOrCreate('pendingFileCategory', 'pdf');
        break;
        
      case EntryAbility.FILE_TYPE_JSON:
        // JSON文件：显示导入选项对话框（书源/图源/文件编辑器）
        logger.info('EntryAbility', `📋 检测到JSON文件，将显示导入选项`);
        AppStorage.setOrCreate('pendingJsonUri', uri);
        AppStorage.setOrCreate('pendingFileCategory', 'json');
        break;
        
      case EntryAbility.FILE_TYPE_FONT:
        // 字体文件：导入为自定义字体
        logger.info('EntryAbility', `🔤 检测到字体文件，将导入为自定义字体`);
        AppStorage.setOrCreate('pendingFontUri', uri);
        AppStorage.setOrCreate('pendingFileCategory', 'font');
        break;
        
      case EntryAbility.FILE_TYPE_CODE:
        // 代码文件：使用文件编辑器打开
        const codeExt = this.getFileExtension(uri);
        const codeLang = EntryAbility.CODE_EXTENSIONS.get(codeExt) || 'plaintext';
        logger.info('EntryAbility', `💻 检测到代码文件，将使用文件编辑器打开，语言: ${codeLang}`);
        AppStorage.setOrCreate('pendingCodeUri', uri);
        AppStorage.setOrCreate('pendingCodeLanguage', codeLang);
        AppStorage.setOrCreate('pendingFileCategory', 'code');
        break;
        
      default:
        // 未知类型：保存到通用文件URI
        logger.info('EntryAbility', `❓ 未知文件类型，保存到通用文件URI`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', mimeType);
        AppStorage.setOrCreate('pendingFileCategory', 'unknown');
        break;
    }
  }

  /**
   * 处理卡片router事件
   * 根据卡片传递的targetPage参数设置AppStorage标记
   */
  private handleWidgetRouter(want: Want): void {
    try {
      if (!want.parameters || !want.parameters['params']) {
        return;
      }
      
      // 解析params参数
      const paramsRaw = want.parameters['params'];
      let params: Record<string, string> = {};
      if (typeof paramsRaw === 'string') {
        params = SafeUtils.parseObj(paramsRaw) as Record<string, string>;
      } else if (typeof paramsRaw === 'object' && paramsRaw !== null) {
        params = paramsRaw as Record<string, string>;
      }
      const targetPage = params['targetPage'];
      
      logger.info('EntryAbility', `📱 收到卡片router事件: targetPage=${targetPage}`);
      
      if (targetPage === 'readingAnalytics') {
        // 设置标记，跳转到阅读报告页面的日视图
        AppStorage.setOrCreate('widgetTargetPage', 'readingAnalytics');
        AppStorage.setOrCreate('widgetTargetView', params['targetView'] || 'daily');
        logger.info('EntryAbility', '✅ 已设置卡片跳转目标: 阅读报告-日视图');
      } else if (targetPage === 'continueRead') {
        const contentType = params['contentType'] || '';
        const contentId = params['contentId'] || '';
        if (!contentType || !contentId) {
          logger.warn('EntryAbility', `continueRead参数不完整: type=${contentType}, id=${contentId}`);
          return;
        }
        AppStorage.setOrCreate('widgetTargetPage', 'continueRead');
        AppStorage.setOrCreate('widgetContentType', contentType);
        AppStorage.setOrCreate('widgetContentId', contentId);
        logger.info('EntryAbility', `✅ 已设置继续阅读跳转: type=${contentType}, id=${contentId}`);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 处理卡片router事件失败: ${errorMessage}`);
    }
  }

  /**
   * 处理长按快捷入口（兼容实现，便于后续接入系统shortcuts）
   */
  private handleShortcutIntent(want: Want): void {
    try {
      if (!want.parameters) {
        return;
      }
      const shortcutId = want.parameters['shortcutId'] as string;
      if (!shortcutId) {
        return;
      }

      logger.info('EntryAbility', `📌 收到快捷入口请求: shortcutId=${shortcutId}`);
      switch (shortcutId) {
        case 'reading_analytics':
        case 'readingAnalytics':
          AppStorage.setOrCreate('widgetTargetPage', 'readingAnalytics');
          AppStorage.setOrCreate('widgetTargetView', 'daily');
          break;
        case 'search':
        case 'open_search':
          AppStorage.setOrCreate('widgetTargetPage', 'search');
          break;
        case 'continue_read':
        case 'continueRead':
        case 'open_recent_read':
        case 'downloads':
        case 'open_downloads':
          // 兼容旧快捷方式ID：历史版本可能仍使用downloads
          AppStorage.setOrCreate('widgetTargetPage', 'continueReadLatest');
          break;
        case 'continue_read_aloud':
        case 'continueReadAloud':
        case 'open_recent_read_aloud':
          AppStorage.setOrCreate('widgetTargetPage', 'continueReadAloud');
          break;
        case 'inspiration':
        case 'open_inspiration':
          AppStorage.setOrCreate('widgetTargetPage', 'inspiration');
          break;
        case 'library':
        case 'open_library':
          AppStorage.setOrCreate('widgetTargetPage', 'library');
          break;
        default:
          logger.warn('EntryAbility', `未识别的shortcutId: ${shortcutId}`);
          break;
      }
    } catch (error) {
      logger.warn('EntryAbility', `handleShortcutIntent error: ${String(error)}`);
    }
  }

  /**
   * 处理系统分享导入
   */
  private handleShareImport(want: Want): void {
    if (!want.parameters) {
      return;
    }

    const shareFiles = want.parameters['share_import_files'] as string[];
    const shareType = want.parameters['share_import_type'] as string;
    const shareSource = want.parameters['share_import_source'] as string;
    const shareLanguage = want.parameters['share_import_language'] as string;

    if (!shareFiles || !Array.isArray(shareFiles) || shareFiles.length === 0) {
      logger.warn('EntryAbility', '未找到有效的分享文件');
      return;
    }

    logger.info('EntryAbility', `📤 通过系统分享接收文件: ${shareFiles.length} 个, 类型: ${shareType}, 来源: ${shareSource}`);

    const taskKind = ExternalFileTaskFactory.normalizeKind(shareType || 'comic');
    const taskParams = ExternalFileTaskFactory.createShareTask(
      taskKind,
      shareFiles,
      ExternalFileTaskSource.SYSTEM_SHARE,
      shareFiles.length > 0 ? ExternalFileTaskFactory.extractFileName(shareFiles[0]) : ''
    );
    if (taskKind === ExternalFileTaskKind.CODE) {
      const language = shareLanguage && shareLanguage.length > 0
        ? shareLanguage
        : this.inferCodeLanguageFromFileName(ExternalFileTaskFactory.extractFileName(shareFiles[0]));
      taskParams.language = language;
    }
    void openExternalFileTaskInIsolatedAbilityByContext(
      this.context,
      taskParams,
      'EntryAbility.shareImport'
    ).then((started: boolean): void => {
      if (started) {
        logger.info('EntryAbility', `✅ 系统分享已交由外部文件独立实例处理: count=${shareFiles.length}`);
        return;
      }
      this.handleShareImportFallback(shareFiles, shareType, shareSource, taskParams.language);
      this.notifyFileOpenToUI();
    });
  }

  private handleShareImportFallback(shareFiles: string[], shareType: string, shareSource: string, language: string = ''): void {
    const firstFile = shareFiles.length > 0 ? shareFiles[0] : '';
    if (firstFile.length <= 0) {
      return;
    }

    switch (shareType) {
      case EntryAbility.FILE_TYPE_AVIF:
      case EntryAbility.FILE_TYPE_IMAGE:
        AppStorage.setOrCreate('pendingAvifUri', firstFile);
        AppStorage.setOrCreate('pendingFileCategory', shareType);
        return;
      case EntryAbility.FILE_TYPE_BACKUP:
        AppStorage.setOrCreate('pendingBackupUri', firstFile);
        AppStorage.setOrCreate('pendingFileCategory', 'backup');
        AppStorage.setOrCreate('backupImportPending', true);
        return;
      case EntryAbility.FILE_TYPE_JSON:
        AppStorage.setOrCreate('pendingJsonUri', firstFile);
        AppStorage.setOrCreate('pendingFileCategory', 'json');
        return;
      case EntryAbility.FILE_TYPE_FONT:
        AppStorage.setOrCreate('pendingFontUri', firstFile);
        AppStorage.setOrCreate('pendingFileCategory', 'font');
        return;
      case EntryAbility.FILE_TYPE_CODE:
        AppStorage.setOrCreate('pendingCodeUri', firstFile);
        AppStorage.setOrCreate('pendingCodeLanguage', language.length > 0 ? language : this.inferCodeLanguageFromFileName(firstFile));
        AppStorage.setOrCreate('pendingFileCategory', 'code');
        return;
      default:
        break;
    }

    // 保存到AppStorage，供后续页面处理（数组需要转为JSON字符串）
    AppStorage.setOrCreate('pendingShareFiles', JSON.stringify(shareFiles));
    AppStorage.setOrCreate('pendingShareType', shareType || 'comic');
    AppStorage.setOrCreate('pendingShareSource', shareSource || 'system_share');
  }

  /**
   * 应用已在后台运行时接收新的Want请求（如从文件管理器打开文件）
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.info('EntryAbility', 'onNewWant: 接收到新的Want请求');
    // 打印Want详情辅助调试
    logger.info('EntryAbility', `📋 onNewWant Want: uri=${want.uri || 'null'}, type=${want.type || 'null'}`);
    if (want.parameters) {
      logger.info('EntryAbility', `📋 onNewWant 参数键: ${JSON.stringify(Object.keys(want.parameters))}`);
    }
    
    // 优先处理文件分享导入（share_import_files是系统分享的特征键）
    if (want.parameters && want.parameters['share_import_files']) {
      this.handleShareImport(want);
      return;
    }

    // 处理跨端接续 (App Continuation) 热启动
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.restoreContinuationState(want);
    }

    if (this.handleNotificationNavigation(want, true)) {
      return;
    }

    // 检查是否通过 Deep Link 打开应用（manxia:// 或 https://manxia.top/）
    const deepLinkUri: string = want.uri || '';
    if (this.isDeepLinkUri(deepLinkUri)) {
      logger.info('EntryAbility', `🔗 通过 Deep Link 打开应用（onNewWant）: ${deepLinkUri}`);
      this.handleDeepLink(deepLinkUri);
      this.notifyDeepLinkToUI();
      return;
    }

    // 检查是否通过文件URI打开应用
    if (want.uri) {
      logger.info('EntryAbility', `📁 通过文件打开应用（onNewWant）: ${want.uri}`);
      this.handleFileOpen(want.uri, want.type || '', ExternalFileTaskSource.FILE_OPEN);
      return;
    }
    
    // 检查是否通过参数传递文件URI（兼容性处理）
    if (want.parameters) {
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      const fileUris = want.parameters['fileUris'] as string[];
      
      if (fileUris && fileUris.length > 0) {
        logger.info('EntryAbility', `📁 通过参数打开文件（onNewWant）: ${fileUris[0]}`);
        this.handleFileOpen(fileUris[0], '', ExternalFileTaskSource.FILE_CONTEXT_MENU);
        return;
      } else if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件（onNewWant）: ${uri}`);
        this.handleFileOpen(uri, type || '', ExternalFileTaskSource.FILE_OPEN);
        return;
      }
    }
    
    // 卡片router事件放最后（文件打开的Want也可能携带params，必须排在文件处理之后）
    if (want.parameters && want.parameters['params']) {
      this.handleWidgetRouter(want);
    }

    this.handleShortcutIntent(want);
  }

  /**
   * 通知UI层有新文件需要处理（仅用于onNewWant场景）
   * 通过递增AppStorage计数器触发MainMenuPage的@Watch监听器，
   * 解决app在前台时onPageShow不会重新触发的问题
   */
  private notifyFileOpenToUI(): void {
    const current = AppStorage.get<number>('fileOpenNewWantTrigger') || 0;
    AppStorage.setOrCreate('fileOpenNewWantTrigger', current + 1);
    logger.info('EntryAbility', `📣 通知UI处理新文件 (trigger: ${current + 1})`);
  }

  /**
   * 通知UI层有新的Deep Link需要处理（仅用于onNewWant场景）
   */
  private notifyDeepLinkToUI(): void {
    const current = AppStorage.get<number>('deepLinkTrigger') || 0;
    AppStorage.setOrCreate('deepLinkTrigger', current + 1);
    logger.info('EntryAbility', `📣 通知UI处理Deep Link (trigger: ${current + 1})`);
  }

  private handleNotificationNavigation(want: Want, notifyUi: boolean): boolean {
    if (!want.parameters) {
      return false;
    }
    const routeName: string = want.parameters['notificationRouteName'] as string;
    if (!routeName || routeName.length <= 0) {
      return false;
    }
    AppStorage.setOrCreate('widgetTargetPage', 'sourceAutoCheck');
    AppStorage.setOrCreate('sourceAutoCheckRouteName', routeName);
    AppStorage.setOrCreate('sourceAutoCheckSourceId', want.parameters['notificationSourceId'] as number);
    AppStorage.setOrCreate('sourceAutoCheckSourceName', want.parameters['notificationSourceName'] as string);
    AppStorage.setOrCreate('sourceAutoCheckSourcePkg', want.parameters['notificationSourcePkg'] as string);
    AppStorage.setOrCreate('sourceAutoCheckInitialUrl', want.parameters['notificationInitialUrl'] as string);
    AppStorage.setOrCreate('sourceAutoCheckTaskId', want.parameters['notificationAutoCheckTaskId'] as string);
    AppStorage.setOrCreate('sourceAutoCheckOpenReport', want.parameters['notificationOpenAutoCheckReport'] as boolean);
    if (notifyUi) {
      const current = AppStorage.get<number>('sourceAutoCheckNavigationTrigger') || 0;
      AppStorage.setOrCreate('sourceAutoCheckNavigationTrigger', current + 1);
      logger.info('EntryAbility', `📣 通知UI打开图源巡检页面 (trigger: ${current + 1})`);
    }
    return true;
  }

  private isDeepLinkUri(uri: string): boolean {
    return uri.startsWith('manxia://') ||
      uri.startsWith('https://manxia.top/') ||
      uri.startsWith('https://www.manxia.top/');
  }

  /**
   * 应用进入前台时的回调
   * 回到前台不需要主动停止长时任务，等业务完成后再停止
   */
  onForeground(): void {
    logger.lifecycle('EntryAbility', '应用进入前台');
    
    // 清除后台状态（统一由WindowManager管理）
    WindowManager.syncBackgroundState(false, '应用进入前台');

    try {
      widgetDataSync.init(this.context);
      void widgetDataSync.syncAllDataThrottled();
    } catch (error) {
      logger.warn('EntryAbility', `onForeground widget sync error: ${String(error)}`);
    }

    // 触发业务注册的前台事件
    try {
      eventBus.publish(GameEvent.APP_ENTER_FOREGROUND, new BasePayload());
    } catch (error) {
      logger.warn('EntryAbility', `onForeground 事件发布异常: ${String(error)}`);
    }
    
    // 重新检测系统主题
    try {
      const themeManager = ThemeManager.getInstance();
      const colorMode = this.context.config.colorMode as number | undefined;
      
      // 检查 colorMode 是否有效
      if (colorMode !== undefined) {
        themeManager.updateSystemTheme(colorMode);
        logger.info('EntryAbility', `前台检测系统主题: colorMode=${colorMode}`);
      } else {
        logger.warn('EntryAbility', '前台检测系统主题失败: colorMode 为 undefined');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `前台检测系统主题失败: ${errorMessage}`);
    }

    if (!ReaderHostWindowRestoreCoordinator.applyPendingRestore('EntryAbility.onForeground')) {
      WindowManager.reapplyCurrentDisplayMode();
      WindowManager.reapplyCurrentDisplayMode(220);
    }
  }

  /**
   * 应用进入后台时的回调
   *
   * 注意事项：
   *  - 长时任务应在业务开始时已申请（用户触发下载/校验时）
   *  - onBackground 中可申请短时任务（秒级，用于应急收尾)
   *  - 业务监听后台事件：eventBus.subscribe(GameEvent.APP_ENTER_BACKGROUND, callback)
   */
  onBackground(): void {
    logger.lifecycle('EntryAbility', '应用进入后台');
    
    // 设置后台状态（统一由WindowManager管理）
    WindowManager.syncBackgroundState(true, '应用进入后台');

    // 触发业务注册的后台事件（下载管理器、校验器等可监听此事件）
    try {
      eventBus.publish(GameEvent.APP_ENTER_BACKGROUND, new BasePayload());
    } catch (error) {
      logger.warn('EntryAbility', `onBackground 事件发布异常: ${String(error)}`);
    }
  }

  /**
   * 处理 Deep Link URI
   * 存储解析结果 + 原始URI，由 MainMenuPage 处理导航；无法解析的复杂链接再弹出兜底对话框。
   */
  private handleDeepLink(uri: string): void {
    try {
      logger.info('EntryAbility', `🔗 开始解析 Deep Link: ${uri}`);
      if (uri === 'manxia://open' || uri === 'https://manxia.top/' || uri === 'https://www.manxia.top/') {
        AppStorage.setOrCreate('hasDeepLink', false);
        AppStorage.setOrCreate('deepLinkShowDialog', false);
        logger.info('EntryAbility', `🔗 基础打开链接，无需额外跳转: ${uri}`);
        return;
      }
      const router: DeepLinkRouter = DeepLinkRouter.getInstance();
      const stored: boolean = router.storeForLater(uri);
      // 有效深度链接先交给主页面自动导航；无具体路由时再弹出兜底对话框。
      if (stored) {
        AppStorage.setOrCreate('deepLinkDialogUri', uri);
        logger.info('EntryAbility', `🔗 Deep Link 已存储: ${uri}`);
      } else {
        logger.info('EntryAbility', `🔗 Deep Link 无具体路由，仅弹出对话框`);
        AppStorage.setOrCreate('deepLinkDialogUri', uri);
        AppStorage.setOrCreate('deepLinkShowDialog', true);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `🔗 Deep Link 解析失败: ${errorMessage}`);
    }
  }

  // 在Ability销毁时的清理工作（游戏引擎已移除）
  onDestroy(): void {
    logger.info('EntryAbility', 'onDestroy: app is being destroyed');
    WindowManager.dispose();

    try {
      getErrorMonitorService().stop();
    } catch (error) {
      logger.warn('EntryAbility', `stop ErrorMonitorService failed: ${String(error)}`);
    }

    try {
      getCrashRecorderService().dispose();
    } catch (error) {
      logger.warn('EntryAbility', `dispose CrashRecorderService failed: ${String(error)}`);
    }
    
    distributedDataSyncManager.leaveSession();
  }

  /**
   * 鸿蒙跨端流转 (App Continuation) 状态保存
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    logger.info('EntryAbility', 'onContinue: 开始保存接续状态');
    
    // 生成分布式状态机 sessionId
    const sessionId = `continuation_${Date.now()}`;
    
    // 将会话ID写入 wantParam 传给目标端
    wantParam['distributedSessionId'] = sessionId;
    
    // 从AppStorage提取当前阅读状态
    const bookId = AppStorage.get<string>('currentReadBookId') || '';
    const chapterIndex = AppStorage.get<number>('currentReadChapterIndex') || 0;
    const pageIndex = AppStorage.get<number>('currentReadPageIndex') || 0;
    const offset = AppStorage.get<number>('currentReadOffset') || 0;
    const sourceType = AppStorage.get<string>('currentReadSourceType') || '';
    const isLocal = AppStorage.get<boolean>('currentReadIsLocal') || false;

    // 启动分布式状态机
    distributedDataSyncManager.joinSession(sessionId);
    distributedDataSyncManager.updateProgress(bookId, chapterIndex, pageIndex, offset, sourceType);

    wantParam['bookId'] = bookId;
    wantParam['isLocal'] = isLocal;
    wantParam['chapterIndex'] = chapterIndex;
    wantParam['pageIndex'] = pageIndex;
    wantParam['offset'] = offset;
    wantParam['sourceType'] = sourceType;
    
    // 触发全局接续事件，供前端（如MainMenuPage）弹出遥控器进入提示
    eventBus.publish(
      GameEvent.CONTINUATION_TRIGGERED,
      new ContinuationTriggeredPayload(sessionId, bookId, chapterIndex, pageIndex, offset, sourceType, isLocal)
    );
    
    logger.info('EntryAbility', `onContinue 状态已保存: bookId=${bookId}, sessionId=${sessionId}`);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 恢复跨端流转状态
   */
  private restoreContinuationState(want: Want): void {
    logger.info('EntryAbility', 'restoreContinuationState: 开始恢复跨端流转状态');
    
    if (want.parameters && want.parameters['distributedSessionId']) {
      const sessionId = want.parameters['distributedSessionId'] as string;
      const bookId = want.parameters['bookId'] as string;
      const isLocal = want.parameters['isLocal'] as boolean;
      const chapterIndex = want.parameters['chapterIndex'] as number;
      const pageIndex = want.parameters['pageIndex'] as number;
      const offset = want.parameters['offset'] as number;
      const rawSourceType = want.parameters['sourceType'] as string;
      const sourceType = this.normalizeContinuationSourceType(rawSourceType);
      
      logger.info('EntryAbility', `目标端接续解析: sessionId=${sessionId}, bookId=${bookId}`);
      
      // 延迟目标端加入分布式状态机会话，避免与应用数据系统初始化竞争导致卡死
      ngfLifecycleOrchestratorFacade.getCompletionPromise().then(() => {
        logger.info('EntryAbility', '应用初始化完成，目标端开始加入分布式状态机会话');
        distributedDataSyncManager.joinSession(sessionId);
      });
      
      // 设置标志位，让 MainMenuPage 或阅读器直接拉起内容
      AppStorage.setOrCreate('widgetTargetPage', 'continueRead');
      AppStorage.setOrCreate('widgetContentType', sourceType);
      AppStorage.setOrCreate('widgetContentId', bookId);
      AppStorage.setOrCreate('continuationSessionId', sessionId);
      AppStorage.setOrCreate('continuationPageIndex', pageIndex);
      AppStorage.setOrCreate('continuationOffset', offset);
      AppStorage.setOrCreate('continuationChapterIndex', chapterIndex);
      AppStorage.setOrCreate('continuationIsLocal', isLocal);
    }
  }

  private normalizeContinuationSourceType(sourceType: string): string {
    const safeSourceType = sourceType ? sourceType : '';
    const normalized = safeSourceType.trim().toLowerCase();
    if (normalized === 'novel') {
      return 'novel';
    }
    if (normalized === 'ebook' || normalized === 'epub' || normalized === 'pdf' || normalized === 'txt') {
      return 'ebook';
    }
    return 'manga';
  }
}
