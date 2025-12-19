//文件路径：entry/src/main/ets/EntryAbility.ets
/**
 * 应用入口Ability
 * 负责初始化应用上下文、数据管理系统和窗口管理
 */
 
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { setContext } from './GlobalContext';
import { logger } from './Utils/Logger';
import { WindowManager, DisplayMode } from './Utils/WindowManager';
import { DataInitializer } from './Framework/Initialization/DataInitializer';
import { ThemeManager } from './Framework/Managers/ThemeManager';
import { DeviceAdaptationManager } from './Framework/Managers/DeviceAdaptationManager';
import { SettingsManager, SettingKeys } from './Framework/Managers/SettingsManager';
import { AppNotificationManager } from './Framework/Managers/NotificationManager';
import { MangaDownloadManager } from './Framework/Download/DownloadManager';
import { uiContextManager } from './Framework/Managers/UIContextManager';

export default class EntryAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.startup('EntryAbility', 'onCreate START', 'EntryAbility开始创建');

    // 检查是否通过系统分享接收文件
    if (want.parameters && want.parameters['share_import_files']) {
      this.handleShareImport(want);
    }
    // 检查是否通过文件打开应用
    else if (want.uri) {
      logger.info('EntryAbility', `📁 通过文件打开应用: ${want.uri}`);
      // 保存文件URI到AppStorage，在窗口创建后处理
      AppStorage.setOrCreate('pendingFileUri', want.uri);
      AppStorage.setOrCreate('pendingFileType', want.type || '');
    } else if (want.parameters) {
      // 兼容性处理：某些系统可能将文件信息放在parameters中
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件: ${uri}`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', type || '');
      }
    }

    // 唯一的职责：设置全局上下文
    try {
      setContext(this.context);
      logger.info('EntryAbility', '✅ GlobalContext 设置成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ GlobalContext 设置失败: ${errorMessage}`);
      // 这是一个关键错误，可以考虑是否要终止应用
    }

    // 设置UIContextManager的AbilityContext
    try {
      uiContextManager.setAbilityContext(this.context);
      logger.info('EntryAbility', '✅ UIContextManager AbilityContext 设置成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ UIContextManager AbilityContext 设置失败: ${errorMessage}`);
    }

    // 初始化设备适配管理器
    try {
      const deviceManager = DeviceAdaptationManager.getInstance();
      const deviceInfo = deviceManager.getDeviceInfo();
      logger.info('EntryAbility', `📱 设备适配管理器初始化成功: 设备类型=${deviceInfo.deviceType}, 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 设备适配管理器初始化失败: ${errorMessage}`);
    }

    // 初始化数据管理系统
    this.initializeDataSystem();
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

      // 记录关键设置
      const advancedMode = settingsManager.getBoolean(SettingKeys.ADVANCED_MODE_ENABLED, true);
      logger.info('EntryAbility', `✅ 高级模式设置: ${advancedMode}`);
      
      logger.info('EntryAbility', '✅ 设置管理器初始化完成，所有设置已同步到AppStorage');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 设置初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 初始化下载管理器
   */
  private async initializeDownloadManager(): Promise<void> {
    try {
      logger.info('EntryAbility', '📥 开始初始化下载管理器');
      
      // 只初始化下载管理器，不请求通知权限
      const downloadManager = MangaDownloadManager.getInstance();
      downloadManager.setContext(this.context);
      logger.info('EntryAbility', '✅ 下载管理器初始化成功');
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 下载管理器初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 初始化数据管理系统
   */
  private async initializeDataSystem(): Promise<void> {
    try {
      logger.info('EntryAbility', '🚀 开始初始化数据管理系统');
      
      const dataInitializer = DataInitializer.getInstance();
      const result = await dataInitializer.initialize(this.context, {
        enableAutoBackup: true,
        enableDataSync: false,
        cacheConfig: {
          maxImageCacheSize: 500 * 1024 * 1024, // 500MB
          maxDiskCacheAge: 7 * 24 * 60 * 60 * 1000 // 7天
        },
        databaseConfig: {
          enableWAL: true,
          pageSize: 4096,
          cacheSize: 2000
        }
      });

      if (result.success) {
        logger.info('EntryAbility', `✅ 数据管理系统初始化成功，耗时: ${result.duration}ms`);
        if (result.warnings.length > 0) {
          logger.warn('EntryAbility', `⚠️ 初始化警告: ${result.warnings.join(', ')}`);
        }
        
        // 数据库初始化成功后，初始化设置管理器
        await this.initializeAppStorage();
        
        // 初始化下载管理器（不请求通知权限，在MainMenuPage首次显示时请求）
        await this.initializeDownloadManager();
      } else {
        logger.error('EntryAbility', `❌ 数据管理系统初始化失败: ${result.errors.join(', ')}`);
        // 可以考虑是否要继续启动应用或进入安全模式
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 数据管理系统初始化异常: ${errorMessage}`);
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
      
      // 直接使用window API设置自动旋转，不需要UIContext
      mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
        .then(() => {
          logger.info('EntryAbility', '✅ 使用WindowManager设置默认显示模式成功（显示所有系统栏 + 自动旋转）');
        })
        .catch((error: BusinessError) => {
          logger.error('EntryAbility', `❌ 设置自动旋转失败: ${JSON.stringify(error)}`);
        });
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ WindowManager初始化失败: ${errorMessage}`);
    }

    // 直接加载SplashPage，让SplashPage负责主题初始化
    this.loadSplashPage(windowStage);
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

    if (!shareFiles || !Array.isArray(shareFiles) || shareFiles.length === 0) {
      logger.warn('EntryAbility', '未找到有效的分享文件');
      return;
    }

    logger.info('EntryAbility', `📤 通过系统分享接收文件: ${shareFiles.length} 个, 类型: ${shareType}, 来源: ${shareSource}`);
    
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
    
    // 检查是否通过系统分享接收文件
    if (want.parameters && want.parameters['share_import_files']) {
      this.handleShareImport(want);
      return;
    }
    
    // 检查是否通过文件打开应用
    if (want.uri) {
      logger.info('EntryAbility', `📁 通过文件打开应用（onNewWant）: ${want.uri}`);
      AppStorage.setOrCreate('pendingFileUri', want.uri);
      AppStorage.setOrCreate('pendingFileType', want.type || '');
    } else if (want.parameters) {
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件（onNewWant）: ${uri}`);
        AppStorage.setOrCreate('pendingFileUri', uri);
        AppStorage.setOrCreate('pendingFileType', type || '');
      }
    }
  }

  /**
   * 应用进入前台时的回调
   */
  onForeground(): void {
    logger.lifecycle('EntryAbility', '应用进入前台');
    
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
  }

  /**
   * 应用进入后台时的回调
   */
  onBackground(): void {
    logger.lifecycle('EntryAbility', '应用进入后台');
  }

  // 在Ability销毁时的清理工作（游戏引擎已移除）
  onDestroy(): void {
    logger.info('EntryAbility', 'onDestroy: 应用正在销毁...');
  }
}
