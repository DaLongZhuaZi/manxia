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
import { AnimationSettingsManager } from './Framework/Animation/AnimationSettingsManager';
import { AppNotificationManager } from './Framework/Managers/NotificationManager';
import { MangaDownloadManager } from './Framework/Download/DownloadManager';
import { uiContextManager } from './Framework/Managers/UIContextManager';
import { ProxyManager } from './Framework/Network/ProxyManager';
import { getFontManager } from './Framework/Managers/FontManager';
import { getDownloadSyncManager } from './Framework/Managers/DownloadSyncManager';
import { getChangelogManager } from './Framework/Managers/ChangelogManager';
import { getAutoBackupScheduler } from './Framework/WebDAV/WebDAVAutoBackupScheduler';

export default class EntryAbility extends UIAbility {

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.startup('EntryAbility', 'onCreate START', 'EntryAbility开始创建');
    
    // 详细记录Want信息用于调试
    logger.info('EntryAbility', `📋 Want详情: uri=${want.uri || 'null'}, type=${want.type || 'null'}, action=${want.action || 'null'}`);
    if (want.parameters) {
      logger.info('EntryAbility', `📋 Want参数: ${JSON.stringify(Object.keys(want.parameters))}`);
    }

    // 检查是否通过系统分享接收文件
    if (want.parameters && want.parameters['share_import_files']) {
      this.handleShareImport(want);
    }
    // 检查是否通过 Deep Link 打开应用
    else if (want.uri && want.uri.startsWith('manxia://')) {
      logger.info('EntryAbility', `🔗 通过 Deep Link 打开应用: ${want.uri}`);
      this.handleDeepLink(want.uri);
    }
    // 检查是否通过文件打开应用
    else if (want.uri) {
      logger.info('EntryAbility', `📁 通过文件打开应用: ${want.uri}, type=${want.type || 'unknown'}`);
      this.handleFileOpen(want.uri, want.type || '');
    } else if (want.parameters) {
      // 兼容性处理：某些系统可能将文件信息放在parameters中
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      // 检查是否来自fileContextMenu（文件管理器右键菜单）
      const fileUris = want.parameters['fileUris'] as string[];
      const menuHandler = want.parameters['menuHandler'] as string;
      
      if (fileUris && fileUris.length > 0) {
        logger.info('EntryAbility', `📁 通过右键菜单打开文件: ${fileUris[0]}, handler=${menuHandler}`);
        this.handleFileOpen(fileUris[0], '');
      } else if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件: ${uri}`);
        this.handleFileOpen(uri, type || '');
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
    
    // 初始化代理管理器
    this.initializeProxyManager();
    
    // 初始化字体管理器
    this.initializeFontManager();
    
    // 初始化更新日志管理器
    this.initializeChangelogManager();
  }
  
  /**
   * 初始化字体管理器
   */
  private async initializeFontManager(): Promise<void> {
    try {
      const fontManager = getFontManager();
      await fontManager.initialize(this.context);
      logger.info('EntryAbility', '✅ 字体管理器初始化成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 字体管理器初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 初始化更新日志管理器
   */
  private async initializeChangelogManager(): Promise<void> {
    try {
      const changelogManager = getChangelogManager();
      await changelogManager.initialize(this.context);
      logger.info('EntryAbility', `✅ 更新日志管理器初始化成功，当前版本: ${changelogManager.getCurrentVersion()}`);
      
      // 检查是否需要显示更新日志（新版本首次启动）
      // 注意：实际显示会在主页面加载后触发，这里只是初始化
      if (changelogManager.shouldShowChangelog()) {
        logger.info('EntryAbility', '📋 检测到新版本，将在主页面显示更新日志');
        AppStorage.setOrCreate('shouldShowChangelog', true);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 更新日志管理器初始化失败: ${errorMessage}`);
    }
  }
  
  /**
   * 初始化代理管理器
   */
  private async initializeProxyManager(): Promise<void> {
    try {
      const proxyManager = ProxyManager.getInstance();
      await proxyManager.initialize();
      logger.info('EntryAbility', `✅ 代理管理器初始化成功: enabled=${proxyManager.isEnabled()}`);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 代理管理器初始化失败: ${errorMessage}`);
    }
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
      logger.info('EntryAbility', '✅ 动画设置管理器初始化完成');

      // 记录关键设置
      const advancedMode = settingsManager.getBoolean(SettingKeys.ADVANCED_MODE_ENABLED, true);
      logger.info('EntryAbility', `✅ 高级模式设置: ${advancedMode}`);
      
      // 初始化后台模糊遮罩设置到AppStorage
      const backgroundBlurEnabled = settingsManager.getBoolean(SettingKeys.BACKGROUND_BLUR_ENABLED, false);
      const backgroundBlurBgType = settingsManager.getString(SettingKeys.BACKGROUND_BLUR_BG_TYPE, 'solid');
      const backgroundBlurBgImage = settingsManager.getString(SettingKeys.BACKGROUND_BLUR_BG_IMAGE, '');
      const backgroundBlurIconType = settingsManager.getString(SettingKeys.BACKGROUND_BLUR_ICON_TYPE, 'shield');
      AppStorage.setOrCreate('backgroundBlurEnabled', backgroundBlurEnabled);
      AppStorage.setOrCreate('backgroundBlurBgType', backgroundBlurBgType);
      AppStorage.setOrCreate('backgroundBlurBgImage', backgroundBlurBgImage);
      AppStorage.setOrCreate('backgroundBlurIconType', backgroundBlurIconType);
      AppStorage.setOrCreate('isInBackground', false);
      logger.info('EntryAbility', `✅ 后台模糊遮罩设置: enabled=${backgroundBlurEnabled}, bgType=${backgroundBlurBgType}, iconType=${backgroundBlurIconType}`);
      
      logger.info('EntryAbility', '✅ 设置管理器初始化完成，所有设置已同步到AppStorage');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 设置初始化失败: ${errorMessage}`);
    }
  }

  /**
   * 初始化Download同步管理器
   * 检查并创建保留文件夹（ebooks, manga, storage, covers, temp, backup）
   */
  private async initializeDownloadSyncManager(): Promise<void> {
    try {
      const downloadSyncManager = getDownloadSyncManager();
      await downloadSyncManager.initialize();
      logger.info('EntryAbility', '✅ Download同步管理器初始化成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ Download同步管理器初始化失败: ${errorMessage}`);
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
   * 初始化WebDAV自动备份调度器
   */
  private async initializeAutoBackupScheduler(): Promise<void> {
    try {
      logger.info('EntryAbility', '📦 开始初始化WebDAV自动备份调度器');
      const scheduler = getAutoBackupScheduler();
      await scheduler.initialize(this.context);
      logger.info('EntryAbility', '✅ WebDAV自动备份调度器初始化成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ WebDAV自动备份调度器初始化失败: ${errorMessage}`);
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
        
        // 初始化Download同步管理器（检查并创建保留文件夹）
        await this.initializeDownloadSyncManager();
        
        // 初始化下载管理器（不请求通知权限，在MainMenuPage首次显示时请求）
        await this.initializeDownloadManager();
        
        // 初始化WebDAV自动备份调度器
        await this.initializeAutoBackupScheduler();
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

    // 监听窗口状态变化，用于后台模糊遮罩功能
    this.registerWindowStageEventListener(windowStage);

    // 使用新的WindowManager设置默认显示模式（显示所有系统栏）
    try {
      // 初始化WindowManager（已包含设置默认系统栏和存储系统栏高度）
      WindowManager.initialize(windowStage);
      
      // [修复] 启用自动旋转需要在页面加载后才能获取UIContext
      // 因此将此操作移到页面加载完成后执行
      const mainWindow = windowStage.getMainWindowSync();
      
      // 直接使用window API设置自动旋转，不需要UIContext
      // 等待方向设置完成后再加载SplashPage，确保系统方向锁定已正确应用
      mainWindow.setPreferredOrientation(window.Orientation.AUTO_ROTATION_RESTRICTED)
        .then(() => {
          logger.info('EntryAbility', '✅ 使用WindowManager设置默认显示模式成功（显示所有系统栏 + 自动旋转）');
          // 方向设置完成后加载SplashPage
          this.loadSplashPage(windowStage);
        })
        .catch((error: BusinessError) => {
          logger.error('EntryAbility', `❌ 设置自动旋转失败: ${JSON.stringify(error)}`);
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

  /**
   * 注册窗口状态事件监听器
   * 用于检测窗口进入后台/前台，实现后台模糊遮罩功能
   */
  private registerWindowStageEventListener(windowStage: window.WindowStage): void {
    try {
      windowStage.on('windowStageEvent', (event: window.WindowStageEventType) => {
        // WindowStageEventType枚举值:
        // SHOWN=1, ACTIVE=2, INACTIVE=3, HIDDEN=4, RESUMED=5, PAUSED=6
        logger.info('EntryAbility', `🪟 窗口状态变化: ${event}`);
        
        switch (event) {
          case window.WindowStageEventType.SHOWN:
          case window.WindowStageEventType.ACTIVE:
          case window.WindowStageEventType.RESUMED: // 5 - 窗口恢复
            // 窗口显示或激活，清除后台状态
            AppStorage.setOrCreate('isInBackground', false);
            logger.info('EntryAbility', '窗口进入前台，清除后台模糊状态');
            break;
          case window.WindowStageEventType.INACTIVE:
          case window.WindowStageEventType.HIDDEN:
          case window.WindowStageEventType.PAUSED: // 6 - 窗口暂停（进入多任务）
            // 窗口失去焦点或隐藏，设置后台状态
            AppStorage.setOrCreate('isInBackground', true);
            logger.info('EntryAbility', '窗口进入后台，设置后台模糊状态');
            break;
        }
      });
      logger.info('EntryAbility', '✅ 窗口状态事件监听器注册成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `❌ 注册窗口状态事件监听器失败: ${errorMessage}`);
    }
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
    const lastDotIndex = uri.lastIndexOf('.');
    if (lastDotIndex === -1) return '';
    return uri.substring(lastDotIndex).toLowerCase();
  }

  /**
   * 根据文件URI获取文件类型
   */
  private getFileTypeFromUri(uri: string): string {
    const lowerUri = uri.toLowerCase();
    
    // AVIF图片
    if (lowerUri.endsWith('.avif')) {
      return EntryAbility.FILE_TYPE_AVIF;
    }
    
    // 备份文件
    if (lowerUri.endsWith('.mxbak') || lowerUri.endsWith('.mxbackup')) {
      return EntryAbility.FILE_TYPE_BACKUP;
    }
    
    // 漫画压缩包
    if (lowerUri.endsWith('.cbz') || lowerUri.endsWith('.cbr')) {
      return EntryAbility.FILE_TYPE_COMIC;
    }
    
    // 电子书
    if (lowerUri.endsWith('.epub') || lowerUri.endsWith('.mobi') || lowerUri.endsWith('.azw3')) {
      return EntryAbility.FILE_TYPE_EBOOK;
    }
    
    // PDF
    if (lowerUri.endsWith('.pdf')) {
      return EntryAbility.FILE_TYPE_PDF;
    }
    
    // JSON文件
    if (lowerUri.endsWith('.json')) {
      return EntryAbility.FILE_TYPE_JSON;
    }
    
    // 字体文件
    if (lowerUri.endsWith('.ttf') || lowerUri.endsWith('.otf') || lowerUri.endsWith('.ttc')) {
      return EntryAbility.FILE_TYPE_FONT;
    }
    
    // 代码文件（检查扩展名是否在映射表中）
    const ext = this.getFileExtension(lowerUri);
    if (ext && EntryAbility.CODE_EXTENSIONS.has(ext)) {
      return EntryAbility.FILE_TYPE_CODE;
    }
    
    return EntryAbility.FILE_TYPE_UNKNOWN;
  }

  /**
   * 处理文件打开请求
   * 根据文件类型设置不同的AppStorage标记，供后续页面处理
   */
  private handleFileOpen(uri: string, mimeType: string): void {
    const fileType = this.getFileTypeFromUri(uri);
    logger.info('EntryAbility', `📁 文件类型识别: ${fileType}, URI: ${uri}`);
    
    switch (fileType) {
      case EntryAbility.FILE_TYPE_AVIF:
        // AVIF文件：跳转到AVIF查看器
        logger.info('EntryAbility', `🖼️ 检测到AVIF文件，将打开AVIF查看器`);
        AppStorage.setOrCreate('pendingAvifUri', uri);
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
      this.handleFileOpen(want.uri, want.type || '');
    } else if (want.parameters) {
      const uri = want.parameters['uri'] as string;
      const type = want.parameters['type'] as string;
      const fileUris = want.parameters['fileUris'] as string[];
      
      if (fileUris && fileUris.length > 0) {
        logger.info('EntryAbility', `📁 通过参数打开文件（onNewWant）: ${fileUris[0]}`);
        this.handleFileOpen(fileUris[0], '');
      } else if (uri) {
        logger.info('EntryAbility', `📁 通过参数打开文件（onNewWant）: ${uri}`);
        this.handleFileOpen(uri, type || '');
      }
    }
  }

  /**
   * 应用进入前台时的回调
   */
  onForeground(): void {
    logger.lifecycle('EntryAbility', '应用进入前台');
    
    // 清除后台模糊状态
    AppStorage.setOrCreate('isInBackground', false);
    
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
    
    // 设置后台状态，触发模糊遮罩（如果已启用）
    AppStorage.setOrCreate('isInBackground', true);
  }

  /**
   * 处理 Deep Link URI
   * 格式: manxia://search/{source}?type={searchType}&query={query}
   */
  private handleDeepLink(uri: string): void {
    try {
      logger.info('EntryAbility', `🔗 开始解析 Deep Link: ${uri}`);
      
      // 手动解析 URI: manxia://search/pixiv?type=id&query=139692726
      // 1. 提取 host 和 path
      const schemeEnd = uri.indexOf('://');
      if (schemeEnd === -1) {
        logger.warn('EntryAbility', `🔗 无效的 URI 格式: ${uri}`);
        return;
      }
      
      const afterScheme = uri.substring(schemeEnd + 3); // 去掉 "manxia://"
      const queryStart = afterScheme.indexOf('?');
      const pathPart = queryStart === -1 ? afterScheme : afterScheme.substring(0, queryStart);
      const queryPart = queryStart === -1 ? '' : afterScheme.substring(queryStart + 1);
      
      // 2. 解析 path: search/pixiv
      const pathSegments = pathPart.split('/');
      if (pathSegments.length < 2 || pathSegments[0] !== 'search') {
        logger.warn('EntryAbility', `🔗 不支持的 Deep Link 格式: ${uri}`);
        return;
      }
      
      const source: string = pathSegments[1];
      
      // 3. 解析 query 参数
      let type: string = 'id';
      let query: string = '';
      
      if (queryPart) {
        const params = queryPart.split('&');
        for (const param of params) {
          const parts = param.split('=');
          const key = parts[0];
          const value = parts.length > 1 ? parts[1] : '';
          if (key === 'type' && value) {
            type = decodeURIComponent(value);
          } else if (key === 'query' && value) {
            query = decodeURIComponent(value);
          }
        }
      }
      
      if (source && query) {
        logger.info('EntryAbility', `🔗 Deep Link 解析成功: source=${source}, type=${type}, query=${query}`);
        
        // 保存到 AppStorage，在 MainMenuPage 中处理
        AppStorage.setOrCreate('deepLinkSource', source);
        AppStorage.setOrCreate('deepLinkType', type);
        AppStorage.setOrCreate('deepLinkQuery', query);
        AppStorage.setOrCreate('hasDeepLink', true);
      } else {
        logger.warn('EntryAbility', `🔗 Deep Link 参数不完整: source=${source}, query=${query}`);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error('EntryAbility', `🔗 Deep Link 解析失败: ${errorMessage}`);
    }
  }

  // 在Ability销毁时的清理工作（游戏引擎已移除）
  onDestroy(): void {
    logger.info('EntryAbility', 'onDestroy: 应用正在销毁...');
  }
}
