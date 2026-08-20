// 文件路径：entry/src/main/ets/pages/SourceSettingsPage.ets
/**
 * 图源设置页面
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { AnimatedComponent } from '../Framework/Animation/AnimatedComponent';
import { AnimationType } from '../Framework/Animation/GlobalAnimationSystem';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager, UserSettingsDatabaseRecord } from '../Framework/Data/DataManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { ComicSourceDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { SourceContentCache } from '../Framework/Cache/SourceContentCache';
import { eventBus, GameEvent, SourceRuntimeConfigChangedPayload, buildSourceRuntimeConfigVersionKey } from '../Framework/EventBus';
import CookieManager from '../Framework/Managers/CookieManager';
import { SourceLoginPageParams } from './SourceLoginPage';
import { ReadingMode, ReadingDirection, PageTurnAnimationType, DEFAULT_READING_SETTINGS } from 'manxia_core/src/main/ets/Models/MangaModels';
import { EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, DEFAULT_EBOOK_READING_SETTINGS } from 'manxia_core/src/main/ets/Models/EBookModels';
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { AntiCrawlerConfig, CloudflareConfig, CaptchaConfig, IpBlockConfig } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG: string = 'SourceSettingsPage';
const COPYMANGA_SOURCE_PKG: string = 'com.manxia.extension.zh.copymangawebview';
const COPYMANGA_ACCOUNT_LOGIN_URL: string = 'https://www.mangacopy.com/web/login/loginByAccount?url=person%2Fhome';

/**
 * 页面导航参数
 */
export interface SourceSettingsPageParams {
  sourceName: string;
}

// ForEach 使用的接口类型
interface ReadingModeOption {
  mode: ReadingMode;
  label: string;
}

interface ReadingDirectionOption {
  direction: ReadingDirection;
  label: string;
}

interface PageTurnAnimationOption {
  type: PageTurnAnimationType;
  label: string;
}

// 图源自定义设置项接口
interface SourceCustomSetting {
  key: string;
  type: 'text' | 'select' | 'boolean' | 'number';
  name: string;
  description?: string;
  default?: string;
  options?: SourceSettingOption[];
  min?: number;
  max?: number;
}

interface SourceSettingOption {
  value: string;
  label: string;
}

// 镜像站点信息
interface MirrorSiteInfo {
  url: string;
  label: string;
}

interface SourceLoginConfig {
  url: string;
  method: string;
  usernameSelector: string;
  passwordSelector: string;
  submitSelector: string;
  supportsIndependentLogin: boolean;
  supportsCredentialLogin: boolean;
  hasLoginWorkflow: boolean;
}

@Component
export struct SourceSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | undefined = undefined;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `SourceSettingsPage_${Date.now()}`;

  private dataManager: DataManager = DataManager.getInstance();
  private webViewManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  private contentCache: SourceContentCache = SourceContentCache.getInstance();
  private scroller: Scroller = new Scroller();
  private sourceLoginConfig: SourceLoginConfig = {
    url: '',
    method: 'manual',
    usernameSelector: '',
    passwordSelector: '',
    submitSelector: '',
    supportsIndependentLogin: false,
    supportsCredentialLogin: false,
    hasLoginWorkflow: false
  };
  private isCopyMangaSource: boolean = false;
  private readonly defaultCloudflareConfig: CloudflareConfig = {
    enabled: true,
    bypassMethod: 'interactive',
    timeout: 30000
  };
  private readonly defaultCaptchaConfig: CaptchaConfig = {
    enabled: true,
    autoSolve: false
  };
  private readonly defaultIpBlockConfig: IpBlockConfig = {
    enabled: true,
    delay: 3000
  };
  private readonly defaultAntiCrawlerConfig: AntiCrawlerConfig = {
    cloudflare: this.defaultCloudflareConfig,
    captcha: this.defaultCaptchaConfig,
    ipBlock: this.defaultIpBlockConfig
  };

  // 参数
  private pageParams: SourceSettingsPageParams | null = null;

  // 基本设置
  @State homeItemsPerPage: number = 20;
  @State readerPreloadCount: number = 10;
  @State preloadCurrentChapter: boolean = true;
  @State preloadNextChapter: boolean = false;
  @State downloadWhileReading: boolean = true;
  @State maxCacheSizeMB: number = 1024; // 以MB为单位

  // 登录设置
  @State username: string = '';
  @State password: string = '';
  @State cookieInput: string = '';
  @State cookieStatusText: string = '';
  @State isSaving: boolean = false;
  @State loginUrl: string = '';
  @State usernameSelector: string = '';
  @State passwordSelector: string = '';
  @State submitSelector: string = '';

  // 设备方向
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  // 漫画默认阅读设置（图源级别）
  @State sourceReadingMode: ReadingMode = DEFAULT_READING_SETTINGS.readingMode;
  @State sourceReadingDirection: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
  @State sourcePageTurnAnimation: PageTurnAnimationType = DEFAULT_READING_SETTINGS.pageTurnAnimation;
  @State sourceMangaSettingsEnabled: boolean = false;

  // 电子书默认阅读设置（图源级别）
  @State sourceEbookFontSize: number = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
  @State sourceEbookLineHeight: number = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
  @State sourceEbookPageMargin: number = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
  @State sourceEbookThemeIndex: number = 0;
  @State sourceEbookPageMode: EBookPageMode = DEFAULT_EBOOK_READING_SETTINGS.pageMode;
  @State sourceEbookSettingsEnabled: boolean = false;

  // 换源功能（镜像站点）
  @State mirrorSites: string[] = [];
  @State currentMirrorIndex: number = 0;
  @State currentBaseUrl: string = '';
  
  // 图源自定义设置（从source.json的settings字段读取）
  @State sourceCustomSettings: SourceCustomSetting[] = [];
  @State sourceCustomSettingValues: Map<string, string> = new Map();
  
  // 图源类型（用于控制显示哪些设置）
  @State sourceType: string = 'manga'; // 'manga' | 'ebook' | 'novel'
  
  // 图源级别UserAgent设置
  @State sourceUserAgent: string = '';
  @State sourceUserAgentEnabled: boolean = false;
  
  // 图源级别NSFW设置
  @State sourceIsNSFW: boolean = false;
  private readonly DEFAULT_USER_AGENT: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // Popup显示状态
  @State showPopupHomeItems: boolean = false;
  @State showPopupPreload: boolean = false;
  @State showPopupPreloadCurrent: boolean = false;
  @State showPopupPreloadNext: boolean = false;
  @State showPopupDownloadWhileReading: boolean = false;
  @State showPopupCacheSize: boolean = false;
  @State showPopupUserAgent: boolean = false;
  // 自定义设置项的Popup状态
  @State customSettingPopupStates: Map<string, boolean> = new Map();

  aboutToAppear(): void {
    logger.info(TAG, '=== aboutToAppear 开始 ===');
    const ui = this.getUIContext();
    this.uiContext = ui;
    ThemeAwareHelper.initializeThemeAware(
      TAG,
      this.themeState,
      (newTheme: ThemeType) => {},
      (newState: ThemeAwareState) => { this.themeState = newState; }
    );

    // 初始化设备方向
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;

    // 注册设备方向监听
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    logger.info(TAG, '=== aboutToAppear 结束 ===');
  }

  onPageShow() {
    logger.info(TAG, '=== onPageShow 开始 ===');
    logger.info(TAG, '=== onPageShow 结束 ===');
  }

  private showSourceSettingsHelp(): void {
    const helpContent = `# 图源设置帮助

## 功能介绍

图源设置页面允许您配置特定图源的个性化设置，包括阅读偏好、网络设置等。

## 阅读设置

### 阅读方向
- **从左到右**: 适合国漫、欧美漫画
- **从右到左**: 适合日漫
- **垂直滚动**: 条漫模式

### 阅读模式
- **单页**: 每次显示一页
- **双页**: 同时显示两页

### 翻页动画
选择您喜欢的翻页效果。

## 网络设置

### 镜像站点
如果原站点访问较慢，可以选择镜像站点加速访问。

### User-Agent
自定义请求的User-Agent，用于解决某些网站的访问限制。

### 缓存设置
- **缓存大小**: 设置图片缓存的最大容量
- **预加载**: 设置预加载的页数

## 登录管理

### 登录状态
显示当前图源的登录状态。

### 重新登录
如果登录失效，点击重新登录。

### 清除登录
清除当前图源的登录信息和Cookie。

## 自定义设置

部分图源支持额外的自定义设置项，这些设置由图源作者定义。

## 注意事项

- 设置仅对当前图源生效
- 部分设置需要重新加载内容才能生效
- 清除登录后需要重新登录才能访问需要登录的内容`;

    getHelpPanelManagerV2().showInlineHelp('图源设置帮助', helpContent);
  }

  /**
   * 加载图源配置中的镜像站点和自定义设置
   */
  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [{
      id: 'help',
      symbol: $r('sys.symbol.questionmark_circle'),
      label: '帮助',
      onClick: () => {
        this.showSourceSettingsHelp();
      },
      enabled: true
    }];
  }

  private resetSourceLoginConfig(): void {
    this.isCopyMangaSource = false;
    this.sourceLoginConfig = {
      url: '',
      method: 'manual',
      usernameSelector: '',
      passwordSelector: '',
      submitSelector: '',
      supportsIndependentLogin: false,
      supportsCredentialLogin: false,
      hasLoginWorkflow: false
    };
  }

  private normalizeSpecialLoginUrl(url: string): string {
    const normalizedUrl: string = url.trim();
    if (!this.isCopyMangaSource) {
      return normalizedUrl;
    }

    if (normalizedUrl.length === 0 ||
      normalizedUrl === 'https://www.mangacopy.com' ||
      normalizedUrl === 'https://www.mangacopy.com/') {
      return COPYMANGA_ACCOUNT_LOGIN_URL;
    }

    return normalizedUrl;
  }

  private normalizeSpecialSourceLoginUrl(configObj: Record<string, Object>): void {
    const metadata = configObj['metadata'] as Record<string, Object> | undefined;
    const metadataId = metadata ? metadata['id'] : null;
    this.isCopyMangaSource = typeof metadataId === 'string' && metadataId === COPYMANGA_SOURCE_PKG;
    if (!this.isCopyMangaSource) {
      return;
    }

    const currentUrl: string = this.sourceLoginConfig.url.trim();
    const normalizedUrl: string = this.normalizeSpecialLoginUrl(currentUrl);
    if (normalizedUrl !== currentUrl) {
      this.sourceLoginConfig.url = COPYMANGA_ACCOUNT_LOGIN_URL;
      this.sourceLoginConfig.supportsIndependentLogin = true;
      logger.info(TAG, `已应用拷贝漫画账号登录地址: ${COPYMANGA_ACCOUNT_LOGIN_URL}`);
    }
  }

  private parseSourceLoginConfig(config: Record<string, Object>): void {
    this.resetSourceLoginConfig();

    const configObj = config as Record<string, Object>;
    const capabilities = configObj['capabilities'] as Record<string, Object> | undefined;
    if (capabilities) {
      this.sourceLoginConfig.supportsIndependentLogin = capabilities['loginSupport'] === true;
      this.sourceLoginConfig.supportsCredentialLogin = capabilities['credentialLogin'] === true;
    }

    const workflows = configObj['workflows'] as Record<string, Object> | undefined;
    if (workflows) {
      this.sourceLoginConfig.hasLoginWorkflow = Object.keys(workflows).includes('login');
    }

    const login = configObj['login'] as Record<string, Object> | undefined;
    if (login) {
      const urlValue = login['url'];
      const methodValue = login['method'];
      const usernameSelectorValue = login['usernameSelector'];
      const passwordSelectorValue = login['passwordSelector'];
      const submitSelectorValue = login['submitSelector'];

      if (typeof urlValue === 'string' && urlValue.trim().length > 0) {
        this.sourceLoginConfig.url = urlValue.trim();
        this.sourceLoginConfig.supportsIndependentLogin = true;
      }
      if (typeof methodValue === 'string' && methodValue.trim().length > 0) {
        this.sourceLoginConfig.method = methodValue.trim().toLowerCase();
      }
      if (typeof usernameSelectorValue === 'string' && usernameSelectorValue.trim().length > 0) {
        this.sourceLoginConfig.usernameSelector = usernameSelectorValue.trim();
      }
      if (typeof passwordSelectorValue === 'string' && passwordSelectorValue.trim().length > 0) {
        this.sourceLoginConfig.passwordSelector = passwordSelectorValue.trim();
      }
      if (typeof submitSelectorValue === 'string' && submitSelectorValue.trim().length > 0) {
        this.sourceLoginConfig.submitSelector = submitSelectorValue.trim();
      }
    }

    this.normalizeSpecialSourceLoginUrl(configObj);

    if (this.loginUrl.length === 0 && this.sourceLoginConfig.url.length > 0) {
      this.loginUrl = this.sourceLoginConfig.url;
    }
    this.loginUrl = this.normalizeSpecialLoginUrl(this.loginUrl);
    if (this.usernameSelector.length === 0 && this.sourceLoginConfig.usernameSelector.length > 0) {
      this.usernameSelector = this.sourceLoginConfig.usernameSelector;
    }
    if (this.passwordSelector.length === 0 && this.sourceLoginConfig.passwordSelector.length > 0) {
      this.passwordSelector = this.sourceLoginConfig.passwordSelector;
    }
    if (this.submitSelector.length === 0 && this.sourceLoginConfig.submitSelector.length > 0) {
      this.submitSelector = this.sourceLoginConfig.submitSelector;
    }
  }

  private getEffectiveLoginUrl(): string {
    if (this.loginUrl.trim().length > 0) {
      return this.normalizeSpecialLoginUrl(this.loginUrl);
    }
    return this.normalizeSpecialLoginUrl(this.sourceLoginConfig.url);
  }

  private hasFormSelectorsConfigured(): boolean {
    return this.usernameSelector.trim().length > 0 &&
      this.passwordSelector.trim().length > 0 &&
      this.submitSelector.trim().length > 0;
  }

  private shouldUseWorkflowLogin(): boolean {
    return this.sourceLoginConfig.supportsCredentialLogin || this.sourceLoginConfig.hasLoginWorkflow;
  }

  private async refreshCookieStatus(sourceId: number): Promise<void> {
    try {
      const info = await CookieManager.getInstance().getCookieInfo(sourceId);
      if (info.hasCookie) {
        this.cookieStatusText = `已保存Cookie（${String(info.cookieCount)} 条）`;
      } else {
        this.cookieStatusText = '未保存Cookie';
      }
    } catch (error) {
      logger.warn(TAG, '刷新Cookie状态失败', String(error));
      this.cookieStatusText = 'Cookie状态不可用';
    }
  }

  private async executeWorkflowLogin(sourceRecord: ComicSourceDatabaseRecord): Promise<void> {
    if (!this.username.trim() || !this.password.trim()) {
      this.showToast('请输入账号和密码');
      return;
    }

    const sid: number = Number(sourceRecord.id);
    const pkg: string = sourceRecord.pkg || this.pageParams?.sourceName || '';
    let config: Record<string, Object> | null = null;
    if (pkg.length > 0) {
      config = await this.dataManager.getSourceConfigByPkg(pkg);
    }
    if (!config) {
      config = await this.dataManager.getSourceConfig(sid);
    }
    if (!config) {
      this.showToast('未找到图源登录配置');
      return;
    }

    const engineConfig: EngineConfig = {
      webViewController: new webview.WebviewController(),
      antiCrawlerConfig: this.defaultAntiCrawlerConfig,
      debug: true,
      timeout: 30000,
      caseSensitive: false,
      sourceId: sid
    };

    const engine = new MangaSourceEngine(engineConfig);
    await engine.loadConfig(JSON.stringify(config));
    await this.authManager.saveCredentials(sid, this.username.trim(), this.password);

    const result = await engine.executeLogin(this.username.trim(), this.password);
    if (!result.success) {
      const errorMessage = result.error ? String(result.error) : '未知错误';
      logger.warn(TAG, `图源登录工作流执行失败: ${errorMessage}`);
      this.showToast(`登录失败: ${errorMessage}`);
      return;
    }

    await this.refreshCookieStatus(sid);
    this.showToast('已按图源配置执行登录');
  }

  private async loadSourceConfigSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      return;
    }
    
    try {
      const sourceName: string = this.pageParams.sourceName;
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (!sourceRecord) {
        return;
      }
      
      // 获取图源配置JSON
      const pkg = sourceRecord.pkg || sourceName;
      const config: Record<string, Object> | null = await this.dataManager.getSourceConfigByPkg(pkg);
      if (!config) {
        logger.warn(TAG, `未找到图源配置: pkg=${pkg}`);
        return;
      }

      this.parseSourceLoginConfig(config);
      
      // 解析镜像站点列表
      const mirrors: string[] | undefined = config._MIRRORS as string[] || config.mirrors as string[];
      if (mirrors && Array.isArray(mirrors) && mirrors.length > 0) {
        this.mirrorSites = mirrors;
        logger.info(TAG, `加载到 ${mirrors.length} 个镜像站点`);
        
        // 加载当前选择的镜像索引
        const sid: number = Number(sourceRecord.id);
        const savedMirror = await this.dataManager.getSourceUserSetting(sid, 'source.mirrorIndex');
        if (savedMirror && savedMirror.settingValue) {
          this.currentMirrorIndex = Number(savedMirror.settingValue);
        }
      }
      
      // 获取当前baseUrl
      this.currentBaseUrl = sourceRecord.baseUrl || '';
      
      // 获取图源类型
      const metadata: Record<string, Object> | undefined = config.metadata as Record<string, Object>;
      if (metadata && metadata.type) {
        this.sourceType = String(metadata.type);
        logger.info(TAG, `图源类型: ${this.sourceType}`);
      }
      
      // 解析自定义设置
      const settings: Record<string, Object> | undefined = config.settings as Record<string, Object>;
      if (settings && typeof settings === 'object') {
        const customSettings: SourceCustomSetting[] = [];
        const settingKeys = Object.keys(settings);
        
        for (const key of settingKeys) {
          const setting: Record<string, Object> = settings[key] as Record<string, Object>;
          if (setting && typeof setting === 'object') {
            let settingType = (setting.type as string) || 'text';
            // 兼容string类型（映射为text）
            if (settingType === 'string') {
              settingType = 'text';
            }
            // 支持name或title字段作为显示名称
            const settingName = (setting.name as string) || (setting.title as string) || key;
            const settingDesc = setting.description as string;
            const settingDefault = setting.default !== undefined ? String(setting.default) : '';
            
            const customSetting: SourceCustomSetting = {
              key: key,
              type: settingType as 'text' | 'select' | 'boolean' | 'number',
              name: settingName,
              description: settingDesc,
              default: settingDefault
            };
            
            // 解析选项（select类型）
            if (setting.options && Array.isArray(setting.options)) {
              const optionsArray: SourceSettingOption[] = [];
              const rawOptions: Record<string, Object>[] = setting.options as Record<string, Object>[];
              for (let i = 0; i < rawOptions.length; i++) {
                const optObj: Record<string, Object> = rawOptions[i] as Record<string, Object>;
                const optItem: SourceSettingOption = {
                  value: String(optObj.value || ''),
                  label: String(optObj.label || optObj.value || '')
                };
                optionsArray.push(optItem);
              }
              customSetting.options = optionsArray;
            }
            
            // 解析数值范围
            if (setting.min !== undefined) {
              customSetting.min = Number(setting.min);
            }
            if (setting.max !== undefined) {
              customSetting.max = Number(setting.max);
            }
            
            customSettings.push(customSetting);
          }
        }
        
        this.sourceCustomSettings = customSettings;
        logger.info(TAG, `加载到 ${customSettings.length} 个自定义设置项`);
        
        // 加载已保存的自定义设置值
        const sid: number = Number(sourceRecord.id);
        for (const setting of customSettings) {
          const savedValue = await this.dataManager.getSourceUserSetting(sid, `custom.${setting.key}`);
          if (savedValue && savedValue.settingValue) {
            this.sourceCustomSettingValues.set(setting.key, savedValue.settingValue);
          } else if (setting.default) {
            this.sourceCustomSettingValues.set(setting.key, setting.default);
          }
        }
      }
    } catch (error) {
      logger.error(TAG, '加载图源配置设置失败', String(error));
    }
  }

  /**
   * 保存自定义设置值
   */
  private async saveCustomSetting(key: string, value: string): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      return;
    }
    
    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) {
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      await this.dataManager.saveSourceUserSetting(sid, `custom.${key}`, value, 'string');
      this.sourceCustomSettingValues.set(key, value);
      if (this.isRuntimeAffectingCustomSetting(key)) {
        this.invalidateSourceRuntimeAfterSettingsChange(sourceRecord, `custom.${key}`);
      }
      logger.info(TAG, `自定义设置已保存: ${key}=${value}`);
    } catch (error) {
      logger.error(TAG, `保存自定义设置失败: ${key}`, String(error));
    }
  }

  private isRuntimeAffectingCustomSetting(key: string): boolean {
    const normalizedKey: string = key.trim().toLowerCase();
    return normalizedKey === 'domain' ||
      normalizedKey === 'apidomain' ||
      normalizedKey === 'baseurl' ||
      normalizedKey.endsWith('domain') ||
      normalizedKey.endsWith('baseurl');
  }

  private invalidateSourceRuntimeAfterSettingsChange(sourceRecord: ComicSourceDatabaseRecord, reason: string): void {
    const sid: number = Number(sourceRecord.id);
    const sourceName: string = sourceRecord.name || this.pageParams?.sourceName || '';
    const baseUrl: string = this.currentBaseUrl || sourceRecord.baseUrl || '';

    this.contentCache.clearSource(sid);
    this.webViewManager.invalidateSourceRuntime(sid, sourceName);
    AppStorage.setOrCreate<number>(buildSourceRuntimeConfigVersionKey(sid), Date.now());

    const payload: SourceRuntimeConfigChangedPayload = new SourceRuntimeConfigChangedPayload(
      sid,
      sourceName,
      baseUrl,
      reason
    );
    eventBus.emit(GameEvent.SOURCE_RUNTIME_CONFIG_CHANGED, payload);
    logger.info(TAG, `已通知图源运行配置变更: sourceId=${sid}, reason=${reason}, baseUrl=${baseUrl}`);
  }

  /**
   * 切换镜像站点
   */
  private async switchMirror(index: number): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName || index < 0 || index >= this.mirrorSites.length) {
      return;
    }
    
    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) {
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      // 保存镜像索引
      await this.dataManager.saveSourceUserSetting(sid, 'source.mirrorIndex', String(index), 'number');
      this.currentMirrorIndex = index;
      
      // 解析镜像URL
      const mirrorStr = this.mirrorSites[index];
      let mirrorUrl = mirrorStr;
      
      // 处理带描述的镜像格式，如 "cn.baozimh.com (简体-主站)"
      const parenIndex = mirrorStr.indexOf('(');
      if (parenIndex > 0) {
        mirrorUrl = mirrorStr.substring(0, parenIndex).trim();
      }
      
      // 确保URL格式正确
      if (!mirrorUrl.startsWith('http://') && !mirrorUrl.startsWith('https://')) {
        mirrorUrl = 'https://' + mirrorUrl;
      }
      
      // 更新数据库中的baseUrl
      await this.dataManager.updateSourceBaseUrl(sid, mirrorUrl);
      this.currentBaseUrl = mirrorUrl;
      this.invalidateSourceRuntimeAfterSettingsChange(sourceRecord, 'mirror');
      
      this.showToast(`已切换到: ${mirrorUrl}`);
      logger.info(TAG, `镜像站点已切换: index=${index}, url=${mirrorUrl}`);
    } catch (error) {
      logger.error(TAG, '切换镜像站点失败', String(error));
      this.showToast('切换失败');
    }
  }

  private async loadSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      logger.error(TAG, '无效的sourceName，无法加载设置');
      this.showToast('页面参数错误');
      return;
    }
    
    try {
      const sourceName: string = this.pageParams.sourceName;
      logger.info(TAG, `开始加载图源设置: sourceName=${sourceName}`);
      
      // 加载图源配置中的镜像站点和自定义设置
      await this.loadSourceConfigSettings();
      
      // 获取图源记录以获取数字 ID（用于设置查询）
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (!sourceRecord) {
        logger.error(TAG, `未找到图源记录: sourceName=${sourceName}`);
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      const s1: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'homeItemsPerPage');
      const s2: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'readerPreloadCount');
      const s3: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadCurrentChapter');
      const s4: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'preloadNextChapter');
      const s5: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'downloadWhileReading');
      const s6: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'maxCacheSize');
      const creds = await this.dataManager.getSourceCredentials(sid);
      const l1: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.url');
      const l2: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.usernameSelector');
      const l3: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.passwordSelector');
      const l4: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'login.submitSelector');

      if (s1 && s1.settingValue) { this.homeItemsPerPage = Number(s1.settingValue); }
      if (s2 && s2.settingValue) { this.readerPreloadCount = Number(s2.settingValue); }
      if (s3 && s3.settingValue) { this.preloadCurrentChapter = s3.settingValue === '1'; }
      if (s4 && s4.settingValue) { this.preloadNextChapter = s4.settingValue === '1'; }
      if (s5 && s5.settingValue) { this.downloadWhileReading = s5.settingValue === '1'; }
      if (s6 && s6.settingValue) { this.maxCacheSizeMB = Math.round(Number(s6.settingValue) / (1024 * 1024)); }
      if (creds) { this.username = creds.username; this.password = creds.password; }
      if (l1 && l1.settingValue) { this.loginUrl = l1.settingValue; }
      if (l2 && l2.settingValue) { this.usernameSelector = l2.settingValue; }
      if (l3 && l3.settingValue) { this.passwordSelector = l3.settingValue; }
      if (l4 && l4.settingValue) { this.submitSelector = l4.settingValue; }
      this.loginUrl = this.normalizeSpecialLoginUrl(this.loginUrl);

      // 加载漫画默认阅读设置
      const mangaEnabled: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'manga.settingsEnabled');
      const mangaMode: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'manga.readingMode');
      const mangaDirection: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'manga.readingDirection');
      const mangaAnimation: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'manga.pageTurnAnimation');

      if (mangaEnabled && mangaEnabled.settingValue) { this.sourceMangaSettingsEnabled = mangaEnabled.settingValue === '1'; }
      if (mangaMode && mangaMode.settingValue) { this.sourceReadingMode = mangaMode.settingValue as ReadingMode; }
      if (mangaDirection && mangaDirection.settingValue) { this.sourceReadingDirection = mangaDirection.settingValue as ReadingDirection; }
      if (mangaAnimation && mangaAnimation.settingValue) { this.sourcePageTurnAnimation = mangaAnimation.settingValue as PageTurnAnimationType; }
      this.syncSourcePageTurnAnimationForCurrentMode();

      // 加载电子书默认阅读设置
      const ebookEnabled: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.settingsEnabled');
      const ebookFontSize: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.fontSize');
      const ebookLineHeight: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.lineHeight');
      const ebookPageMargin: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.pageMargin');
      const ebookTheme: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.themeIndex');
      const ebookPageMode: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'ebook.pageMode');

      if (ebookEnabled && ebookEnabled.settingValue) { this.sourceEbookSettingsEnabled = ebookEnabled.settingValue === '1'; }
      if (ebookFontSize && ebookFontSize.settingValue) { this.sourceEbookFontSize = Number(ebookFontSize.settingValue); }
      if (ebookLineHeight && ebookLineHeight.settingValue) { this.sourceEbookLineHeight = Number(ebookLineHeight.settingValue); }
      if (ebookPageMargin && ebookPageMargin.settingValue) { this.sourceEbookPageMargin = Number(ebookPageMargin.settingValue); }
      if (ebookTheme && ebookTheme.settingValue) { this.sourceEbookThemeIndex = Number(ebookTheme.settingValue); }
      if (ebookPageMode && ebookPageMode.settingValue) { this.sourceEbookPageMode = ebookPageMode.settingValue as EBookPageMode; }

      // 加载图源级别UserAgent设置
      const uaEnabled: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'network.userAgentEnabled');
      const uaValue: UserSettingsDatabaseRecord | null = await this.dataManager.getSourceUserSetting(sid, 'network.userAgent');
      if (uaEnabled && uaEnabled.settingValue) { this.sourceUserAgentEnabled = uaEnabled.settingValue === '1'; }
      if (uaValue && uaValue.settingValue) { this.sourceUserAgent = uaValue.settingValue; } else { this.sourceUserAgent = this.DEFAULT_USER_AGENT; }

      // 加载图源NSFW状态
      if (sourceRecord.isNSFW !== undefined) {
        this.sourceIsNSFW = sourceRecord.isNSFW === 1;
      }
    } catch (error) {
      logger.error(TAG, '加载图源设置失败', String(error));
    }
    // 刷新 Cookie 状态
    try {
      const sourceName: string = this.pageParams.sourceName;
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (sourceRecord) {
        const sid: number = Number(sourceRecord.id);
        await this.refreshCookieStatus(sid);
      }
    } catch (err) {
      logger.warn(TAG, '刷新Cookie状态失败', String(err));
      this.cookieStatusText = 'Cookie状态不可用';
    }
  }

  private isSourceVerticalDoublePageModeSelected(): boolean {
    return this.sourceReadingMode === ReadingMode.DOUBLE_PAGE &&
      this.sourceReadingDirection === ReadingDirection.TOP_TO_BOTTOM;
  }

  private normalizeSourcePageTurnAnimation(animationType: PageTurnAnimationType): PageTurnAnimationType {
    if (this.isSourceVerticalDoublePageModeSelected()) {
      return PageTurnAnimationType.SLIDE;
    }
    return animationType;
  }

  private syncSourcePageTurnAnimationForCurrentMode(): void {
    this.sourcePageTurnAnimation = this.normalizeSourcePageTurnAnimation(this.sourcePageTurnAnimation);
  }

  private async saveSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    this.isSaving = true;
    try {
      const sourceName: string = this.pageParams.sourceName;
      const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
      if (!sourceRecord) {
        this.showToast('未找到图源记录');
        this.isSaving = false;
        return;
      }
      const sid: number = Number(sourceRecord.id);
      
      await this.dataManager.saveSourceUserSetting(sid, 'homeItemsPerPage', String(this.homeItemsPerPage), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'readerPreloadCount', String(this.readerPreloadCount), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'preloadCurrentChapter', this.preloadCurrentChapter ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'preloadNextChapter', this.preloadNextChapter ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'downloadWhileReading', this.downloadWhileReading ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'maxCacheSize', String(this.maxCacheSizeMB * 1024 * 1024), 'number');
      await this.authManager.saveCredentials(sid, this.username, this.password);
      await this.dataManager.saveSourceUserSetting(sid, 'login.url', this.loginUrl, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.usernameSelector', this.usernameSelector, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.passwordSelector', this.passwordSelector, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'login.submitSelector', this.submitSelector, 'string');

      // 保存漫画默认阅读设置
      await this.dataManager.saveSourceUserSetting(sid, 'manga.settingsEnabled', this.sourceMangaSettingsEnabled ? '1' : '0', 'boolean');
      if (this.sourceMangaSettingsEnabled) {
        this.syncSourcePageTurnAnimationForCurrentMode();
        await this.dataManager.saveSourceUserSetting(sid, 'manga.readingMode', this.sourceReadingMode, 'string');
        await this.dataManager.saveSourceUserSetting(sid, 'manga.readingDirection', this.sourceReadingDirection, 'string');
        await this.dataManager.saveSourceUserSetting(sid, 'manga.pageTurnAnimation', this.sourcePageTurnAnimation, 'string');
      }

      // 保存电子书默认阅读设置
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.settingsEnabled', this.sourceEbookSettingsEnabled ? '1' : '0', 'boolean');
      if (this.sourceEbookSettingsEnabled) {
        await this.dataManager.saveSourceUserSetting(sid, 'ebook.fontSize', String(this.sourceEbookFontSize), 'number');
        await this.dataManager.saveSourceUserSetting(sid, 'ebook.lineHeight', String(this.sourceEbookLineHeight), 'number');
        await this.dataManager.saveSourceUserSetting(sid, 'ebook.pageMargin', String(this.sourceEbookPageMargin), 'number');
        await this.dataManager.saveSourceUserSetting(sid, 'ebook.themeIndex', String(this.sourceEbookThemeIndex), 'number');
        await this.dataManager.saveSourceUserSetting(sid, 'ebook.pageMode', this.sourceEbookPageMode, 'string');
      }

      // 保存图源级别UserAgent设置
      await this.dataManager.saveSourceUserSetting(sid, 'network.userAgentEnabled', this.sourceUserAgentEnabled ? '1' : '0', 'boolean');
      if (this.sourceUserAgentEnabled) {
        await this.dataManager.saveSourceUserSetting(sid, 'network.userAgent', this.sourceUserAgent, 'string');
      }

      // 保存图源NSFW状态
      await this.dataManager.updateSourceNSFW(sid, this.sourceIsNSFW);

      this.showToast('设置已保存');
    } catch (error) {
      logger.error(TAG, '保存图源设置失败', String(error));
      this.showToast('保存失败');
    }
    this.isSaving = false;
  }

  /**
   * 实时保存漫画默认阅读设置
   */
  private async saveMangaReadingSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      return;
    }
    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) { return; }
      const sid: number = Number(sourceRecord.id);
      this.syncSourcePageTurnAnimationForCurrentMode();
      
      await this.dataManager.saveSourceUserSetting(sid, 'manga.settingsEnabled', this.sourceMangaSettingsEnabled ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'manga.readingMode', this.sourceReadingMode, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'manga.readingDirection', this.sourceReadingDirection, 'string');
      await this.dataManager.saveSourceUserSetting(sid, 'manga.pageTurnAnimation', this.sourcePageTurnAnimation, 'string');
      logger.info(TAG, '漫画默认阅读设置已保存');
    } catch (error) {
      logger.error(TAG, '保存漫画默认阅读设置失败', String(error));
    }
  }

  /**
   * 实时保存UserAgent设置
   */
  private async saveUserAgentSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      return;
    }
    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) { return; }
      const sid: number = Number(sourceRecord.id);
      
      await this.dataManager.saveSourceUserSetting(sid, 'network.userAgentEnabled', this.sourceUserAgentEnabled ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'network.userAgent', this.sourceUserAgent, 'string');
      logger.info(TAG, 'UserAgent设置已保存');
      this.showToast('UserAgent设置已保存');
    } catch (error) {
      logger.error(TAG, '保存UserAgent设置失败', String(error));
    }
  }

  /**
   * 实时保存电子书默认阅读设置
   */
  private async saveEbookReadingSettings(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      return;
    }
    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) { return; }
      const sid: number = Number(sourceRecord.id);
      
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.settingsEnabled', this.sourceEbookSettingsEnabled ? '1' : '0', 'boolean');
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.fontSize', String(this.sourceEbookFontSize), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.lineHeight', String(this.sourceEbookLineHeight), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.pageMargin', String(this.sourceEbookPageMargin), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.themeIndex', String(this.sourceEbookThemeIndex), 'number');
      await this.dataManager.saveSourceUserSetting(sid, 'ebook.pageMode', this.sourceEbookPageMode, 'string');
      logger.info(TAG, '电子书默认阅读设置已保存');
    } catch (error) {
      logger.error(TAG, '保存电子书默认阅读设置失败', String(error));
    }
  }

  private async applyCookieInput(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }
    const sid: number = Number(sourceRecord.id);
    
    const controller = this.webViewManager.getWebViewInstance(sourceName);
    await this.authManager.loginWithCookieString(sid, controller, this.cookieInput);
    this.showToast('Cookie已保存并应用');
    await this.refreshCookieStatus(sid);
  }

  private async fetchCookieWithoutLogin(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    try {
      const sourceName: string = this.pageParams.sourceName;
      logger.info(TAG, `获取Cookie: sourceName=${sourceName}`);
      const srcRecord: ComicSourceDatabaseRecord | null = await this.dataManager.getComicSourceByName(sourceName);
      
      // 如果数据库中没有记录，尝试从配置文件获取baseUrl
      let baseUrl: string = '';
      if (!srcRecord) {
        logger.info(TAG, '未找到图源记录，尝试从DataManager获取配置');
        // 尝试从DataManager获取源配置
        try {
          const sourceConfig: Record<string, Object> | null = await this.dataManager.getSourceConfigByPkg(sourceName);
          if (sourceConfig) {
            const configObj = sourceConfig as Record<string, Object>;
            const keys = Object.keys(configObj);
            
            // 尝试从metadata.baseUrl获取
            if (keys.includes('metadata')) {
              const metadata = configObj['metadata'] as Record<string, Object>;
              const metaKeys = Object.keys(metadata);
              if (metaKeys.includes('baseUrl')) {
                baseUrl = String(metadata['baseUrl']);
              }
            }
            
            // 如果metadata中没有，尝试直接从配置根获取
            if (baseUrl.length === 0 && keys.includes('baseUrl')) {
              baseUrl = String(configObj['baseUrl']);
            }
          }
        } catch (e) {
          logger.warn(TAG, `获取源配置失败: ${String(e)}`);
        }
        
        if (baseUrl.length === 0) {
          this.showToast('未找到图源配置');
          return;
        }
      } else {
        baseUrl = srcRecord.baseUrl;
      }
      
      if (baseUrl.length === 0) { this.showToast('图源基础URL为空'); return; }
      if (!srcRecord) { this.showToast('未找到图源记录'); return; }
      
      const sid: number = Number(srcRecord.id);
      const cookieManager: CookieManager = CookieManager.getInstance();
      const ok: boolean = await cookieManager.fetchCookiesByDefaultRequest(sid, baseUrl);
      const info = await cookieManager.getCookieInfo(sid);
      if (ok) {
        this.showToast('已获取并保存服务器Cookie');
        this.cookieStatusText = info.hasCookie ? `已保存Cookie（${String(info.cookieCount)} 条）` : '未保存Cookie';
      } else if (info.hasCookie) {
        this.cookieStatusText = `已保存Cookie（${String(info.cookieCount)} 条）`;
        this.showToast('服务器未返回新Cookie，已使用本地Cookie');
        logger.info(TAG, `默认请求未返回Set-Cookie，但本地Cookie可用: sourceName=${sourceName}, count=${String(info.cookieCount)}`);
      } else {
        this.cookieStatusText = '未保存Cookie';
        this.showToast('未获取到服务器Cookie');
      }
    } catch (error) {
      logger.error(TAG, '获取服务器Cookie失败', String(error));
      this.showToast('获取Cookie失败');
    }
  }

  private async openLoginPage(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }
    const url: string = this.getEffectiveLoginUrl();
    if (url.length === 0) {
      if (this.shouldUseWorkflowLogin()) {
        this.showToast('当前图源使用凭据登录，请使用“表单登录”执行图源登录流程');
      } else {
        this.showToast('图源未配置独立登录页');
      }
      return;
    }
    
    // 跳转到独立的登录页面
    const loginParams: SourceLoginPageParams = {
      sourceName: sourceName,
      loginUrl: url,
      loginType: 'webview'
    };
    this.pathStack.pushPathByName('SourceLoginPage', loginParams);
    logger.info(TAG, `跳转到登录页面: sourceName=${sourceName}, url=${url}`);
  }

  private async performFormLogin(): Promise<void> {
    if (!this.pageParams || !this.pageParams.sourceName) {
      this.showToast('无效的图源');
      return;
    }
    
    const sourceName: string = this.pageParams.sourceName;
    const sourceRecord = await this.dataManager.getComicSourceByName(sourceName);
    if (!sourceRecord) {
      this.showToast('未找到图源记录');
      return;
    }

    if (this.shouldUseWorkflowLogin()) {
      logger.info(TAG, `执行图源登录工作流: sourceName=${sourceName}`);
      await this.executeWorkflowLogin(sourceRecord);
      return;
    }

    const loginMethod: string = this.sourceLoginConfig.method.trim().toLowerCase();
    if (loginMethod === 'manual' && !this.hasFormSelectorsConfigured()) {
      this.showToast('图源配置为手动登录，请使用“打开登录页”');
      return;
    }

    if (!this.username.trim() || !this.password.trim()) {
      this.showToast('请输入账号和密码');
      return;
    }

    const url: string = this.getEffectiveLoginUrl();
    if (url.length === 0) {
      this.showToast('图源未配置表单登录地址');
      return;
    }
    if (!this.hasFormSelectorsConfigured()) {
      this.showToast('图源未配置表单选择器');
      return;
    }
    
    // 跳转到独立的登录页面（表单模式）
    const loginParams: SourceLoginPageParams = {
      sourceName: sourceName,
      loginUrl: url,
      loginType: 'form',
      username: this.username,
      password: this.password,
      usernameSelector: this.usernameSelector,
      passwordSelector: this.passwordSelector,
      submitSelector: this.submitSelector
    };
    this.pathStack.pushPathByName('SourceLoginPage', loginParams);
    logger.info(TAG, `跳转到表单登录页面: sourceName=${sourceName}`);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2000,
        bottom: 100
      });
    } catch (e) {
      logger.warn(TAG, '显示Toast失败', String(e));
    }
    logger.info(TAG, message);
  }

  private handleSourceSettingsBack(reason: string): boolean {
    try {
      this.pathStack.pop();
      logger.info(TAG, `图源设置页返回: reason=${reason}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `图源设置页返回失败: reason=${reason}, error=${String(error)}`);
      return false;
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

        Scroll(this.scroller) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            // 换源设置分组（仅当有镜像站点时显示）
            if (this.mirrorSites.length > 0) {
              Column() {
                Text('换源')
                  .fontSize(18)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .margin({ bottom: 12 })

                Text(`当前站点: ${this.currentBaseUrl}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .margin({ bottom: 8 })

                Column({ space: 8 }) {
                  ForEach(this.mirrorSites, (mirror: string, index: number) => {
                    Row() {
                      Radio({ value: String(index), group: 'mirrorGroup' })
                        .checked(this.currentMirrorIndex === index)
                        .onChange((isChecked: boolean) => {
                          if (isChecked) {
                            this.switchMirror(index);
                          }
                        })
                      Text(mirror)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .margin({ left: 8 })
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4 })
                  })
                }
                .width('100%')
              }
              .width(this.isLandscape ? '48%' : '100%')
              .padding(16)
              .margin({ bottom: 16 })
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
            }

            // 图源自定义设置分组（仅当有自定义设置时显示）
            if (this.sourceCustomSettings.length > 0) {
              Column() {
                Text('图源设置')
                  .fontSize(18)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .margin({ bottom: 12 })

                ForEach(this.sourceCustomSettings, (setting: SourceCustomSetting) => {
                  Column() {
                    Row() {
                      Text(setting.name)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      if (setting.description) {
                        Text('?')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(Color.Gray)
                          .width(16)
                          .height(16)
                          .textAlign(TextAlign.Center)
                          .borderRadius(8)
                          .border({ width: 1, color: Color.Gray })
                          .margin({ left: 4 })
                          .onClick(() => {
                            const currentState = this.customSettingPopupStates.get(setting.key) || false;
                            this.customSettingPopupStates.set(setting.key, !currentState);
                            this.customSettingPopupStates = new Map(this.customSettingPopupStates);
                          })
                          .bindPopup(this.customSettingPopupStates.get(setting.key) || false, {
                            message: setting.description,
                            placement: Placement.Top,
                            enableArrow: true,
                            showInSubWindow: false,
                            mask: true,
                            autoCancel: true,
                            onStateChange: (e) => {
                              if (!e.isVisible) {
                                this.customSettingPopupStates.set(setting.key, false);
                                this.customSettingPopupStates = new Map(this.customSettingPopupStates);
                              }
                            }
                          })
                      }
                    }
                    .width('100%')
                    .margin({ bottom: 4 })

                    if (setting.type === 'text') {
                      TextInput({ text: this.sourceCustomSettingValues.get(setting.key) || setting.default || '' })
                        .width('100%')
                        .onChange((value: string) => {
                          this.saveCustomSetting(setting.key, value);
                        })
                    } else if (setting.type === 'boolean') {
                      Row() {
                        Blank()
                        Toggle({ type: ToggleType.Switch, isOn: (this.sourceCustomSettingValues.get(setting.key) || setting.default) === 'true' })
                          .onChange((isOn: boolean) => {
                            this.saveCustomSetting(setting.key, isOn ? 'true' : 'false');
                          })
                      }
                      .width('100%')
                    } else if (setting.type === 'select' && setting.options) {
                      Column({ space: 4 }) {
                        ForEach(setting.options, (option: SourceSettingOption, index: number) => {
                          Row() {
                            Radio({ value: option.value, group: `setting_${setting.key}` })
                              .checked((this.sourceCustomSettingValues.get(setting.key) || setting.default) === option.value)
                              .onChange((isChecked: boolean) => {
                                if (isChecked) {
                                  this.sourceCustomSettingValues.set(setting.key, option.value);
                                  this.sourceCustomSettingValues = new Map(this.sourceCustomSettingValues);
                                  this.saveCustomSetting(setting.key, option.value);
                                }
                              })
                            Text(option.label)
                              .fontSize(14)
                              .fontFamily(this.appFontFamily)
                              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                              .margin({ left: 8 })
                          }
                          .width('100%')
                        }, (option: SourceSettingOption) => `${setting.key}_${option.value}`)
                      }
                      .width('100%')
                    } else if (setting.type === 'number') {
                      Row() {
                        Blank()
                        Text(this.sourceCustomSettingValues.get(setting.key) || setting.default || '0')
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      }
                      .width('100%')
                      .margin({ bottom: 4 })

                      Slider({
                        value: Number(this.sourceCustomSettingValues.get(setting.key) || setting.default || 0),
                        min: setting.min || 0,
                        max: setting.max || 100,
                        step: 1,
                        style: SliderStyle.InSet
                      })
                        .width('100%')
                        .trackThickness(4)
                        .onChange((value: number) => {
                          this.saveCustomSetting(setting.key, String(Math.round(value)));
                        })
                    }

                    if (setting.description) {
                      Text(setting.description)
                        .fontSize(11)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                        .margin({ top: 4 })
                    }
                  }
                  .width('100%')
                  .margin({ bottom: 12 })
                })
              }
              .width(this.isLandscape ? '48%' : '100%')
              .padding(16)
              .margin({ bottom: 16 })
              .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
              .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
              .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
              .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
              .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
              .clip(true)
              .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
              .shadow({
                radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
                color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
                offsetX: 0,
                offsetY: 8
              })
            }

            // 基础设置分组
            Column() {
              Text('基础')
                .fontSize(18)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .margin({ bottom: 12 })

              // 首页每页条目数
              Column() {
                Row() {
                  Text('首页每页条目数')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupHomeItems = !this.showPopupHomeItems;
                    })
                    .bindPopup(this.showPopupHomeItems, {
                      message: '控制图源首页每次加载的漫画数量，范围10-100。数值越大加载越慢，但减少翻页次数',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupHomeItems = false;
                        }
                      }
                    })
                  Blank()
                  Text(`${this.homeItemsPerPage} 条`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                .width('100%')
                
                Slider({
                  value: this.homeItemsPerPage,
                  min: 10,
                  max: 100,
                  step: 5,
                  style: SliderStyle.InSet
                })
                .width('100%')
                .trackThickness(4)
                .onChange((value: number) => {
                  this.homeItemsPerPage = Math.round(value);
                })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 阅读器预加载数量
              Column() {
                Row() {
                  Text('阅读器预加载数量')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupPreload = !this.showPopupPreload;
                    })
                    .bindPopup(this.showPopupPreload, {
                      message: '阅读时提前加载的图片页数，范围1-10。数值越大翻页越流畅，但占用更多内存',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupPreload = false;
                        }
                      }
                    })
                  Blank()
                  Text(`${this.readerPreloadCount} 页`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                .width('100%')
                
                Slider({
                  value: this.readerPreloadCount,
                  min: 0,
                  max: 50,
                  step: 1,
                  style: SliderStyle.InSet
                })
                .width('100%')
                .trackThickness(4)
                .onChange((value: number) => {
                  this.readerPreloadCount = Math.round(value);
                })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 预加载当前章节
              Row() {
                Row() {
                  Text('预加载当前章节')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupPreloadCurrent = !this.showPopupPreloadCurrent;
                    })
                    .bindPopup(this.showPopupPreloadCurrent, {
                      message: '打开章节时自动预加载所有图片，提升阅读体验但消耗流量',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupPreloadCurrent = false;
                        }
                      }
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.preloadCurrentChapter })
                  .onChange((isOn: boolean) => { this.preloadCurrentChapter = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 预加载下一章节
              Row() {
                Row() {
                  Text('预加载下一章节')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupPreloadNext = !this.showPopupPreloadNext;
                    })
                    .bindPopup(this.showPopupPreloadNext, {
                      message: '阅读到最后几页时自动预加载下一章节，无缝连续阅读',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupPreloadNext = false;
                        }
                      }
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.preloadNextChapter })
                  .onChange((isOn: boolean) => { this.preloadNextChapter = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 边看边下载
              Row() {
                Row() {
                  Text('边看边下载')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupDownloadWhileReading = !this.showPopupDownloadWhileReading;
                    })
                    .bindPopup(this.showPopupDownloadWhileReading, {
                      message: '开启后，阅读时自动下载图片到永久存储，不会被清理。关闭后使用临时缓存，受最大缓存限制',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupDownloadWhileReading = false;
                        }
                      }
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.downloadWhileReading })
                  .onChange((isOn: boolean) => { this.downloadWhileReading = isOn; })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 最大缓存大小（仅在未开启边看边下载时有效）
              if (!this.downloadWhileReading) {
                Column() {
                  Row() {
                    Text('最大缓存大小')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Text('?')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(Color.Gray)
                      .width(16)
                      .height(16)
                      .textAlign(TextAlign.Center)
                      .borderRadius(8)
                      .border({ width: 1, color: Color.Gray })
                      .margin({ left: 4 })
                      .onClick(() => {
                        this.showPopupCacheSize = !this.showPopupCacheSize;
                      })
                      .bindPopup(this.showPopupCacheSize, {
                        message: '临时缓存的最大大小，超出后自动清理最旧的缓存',
                        placement: Placement.Top,
                        enableArrow: true,
                        showInSubWindow: false,
                        mask: true,
                        autoCancel: true,
                        onStateChange: (e) => {
                          if (!e.isVisible) {
                            this.showPopupCacheSize = false;
                          }
                        }
                      })
                    Blank()
                    Text(`${this.maxCacheSizeMB} MB`)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  }
                  .width('100%')
                  
                  Slider({
                    value: this.maxCacheSizeMB,
                    min: 100,
                    max: 10240,
                    step: 100,
                    style: SliderStyle.InSet
                  })
                  .width('100%')
                  .trackThickness(4)
                  .onChange((value: number) => {
                    this.maxCacheSizeMB = Math.round(value);
                  })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              }
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .margin({ bottom: 16 })
            .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
            .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
            .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
            .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
            .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
            .clip(true)
            .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
            .shadow({
              radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
              color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
              offsetX: 0,
              offsetY: 8
            })

            // UserAgent设置分组
            Column() {
              Text('网络请求')
                .fontSize(18)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .margin({ bottom: 12 })

              // 启用自定义UA开关
              Row() {
                Row() {
                  Text('自定义User-Agent')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('?')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(Color.Gray)
                    .width(16)
                    .height(16)
                    .textAlign(TextAlign.Center)
                    .borderRadius(8)
                    .border({ width: 1, color: Color.Gray })
                    .margin({ left: 4 })
                    .onClick(() => {
                      this.showPopupUserAgent = !this.showPopupUserAgent;
                    })
                    .bindPopup(this.showPopupUserAgent, {
                      message: '为此图源设置自定义User-Agent，覆盖全局设置。可用于解决某些网站的访问限制',
                      placement: Placement.Top,
                      enableArrow: true,
                      showInSubWindow: false,
                      mask: true,
                      autoCancel: true,
                      onStateChange: (e) => {
                        if (!e.isVisible) {
                          this.showPopupUserAgent = false;
                        }
                      }
                    })
                }
                .layoutWeight(1)
                
                Toggle({ type: ToggleType.Switch, isOn: this.sourceUserAgentEnabled })
                  .onChange((isOn: boolean) => { 
                    this.sourceUserAgentEnabled = isOn;
                    this.saveUserAgentSettings();
                  })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              if (this.sourceUserAgentEnabled) {
                Column({ space: 8 }) {
                  TextArea({ text: this.sourceUserAgent, placeholder: '输入自定义User-Agent...' })
                    .fontSize(13)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .borderRadius(8)
                    .padding(12)
                    .height(80)
                    .width('100%')
                    .onChange((value: string) => {
                      this.sourceUserAgent = value;
                    })

                  Row({ space: 8 }) {
                    Button('重置默认')
                      .fontSize(12)
                      .height(28)
                      .fontFamily(this.appFontFamily)
                      .onClick(() => {
                        this.sourceUserAgent = this.DEFAULT_USER_AGENT;
                        this.saveUserAgentSettings();
                      })

                    Button('Chrome UA')
                      .fontSize(12)
                      .height(28)
                      .fontFamily(this.appFontFamily)
                      .onClick(() => {
                        this.sourceUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
                        this.saveUserAgentSettings();
                      })

                    Button('保存')
                      .fontSize(12)
                      .height(28)
                      .fontFamily(this.appFontFamily)
                      .onClick(() => {
                        this.saveUserAgentSettings();
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Start)
                }
                .width('100%')
                .margin({ top: 8 })
              }
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .margin({ bottom: 16 })
            .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
            .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
            .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
            .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
            .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
            .clip(true)
            .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
            .shadow({
              radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
              color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
              offsetX: 0,
              offsetY: 8
            })

            // 登录设置分组
            Column() {
              Text('登录')
                .fontSize(18)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .margin({ bottom: 12 })

              // 账号
              Column() {
                Text('账号')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.username })
                  .width('100%')
                  .onChange((v: string) => { this.username = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 密码
              Column() {
                Text('密码')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.password })
                  .width('100%')
                  .type(InputType.Password)
                  .onChange((v: string) => { this.password = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 登录页地址
              Column() {
                Text('登录页地址')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.loginUrl })
                  .width('100%')
                  .onChange((v: string) => { this.loginUrl = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 账号选择器
              Column() {
                Text('账号选择器')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.usernameSelector })
                  .width('100%')
                  .onChange((v: string) => { this.usernameSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 密码选择器
              Column() {
                Text('密码选择器')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.passwordSelector })
                  .width('100%')
                  .onChange((v: string) => { this.passwordSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 提交按钮选择器
              Column() {
                Text('提交按钮选择器')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                TextInput({ text: this.submitSelector })
                  .width('100%')
                  .onChange((v: string) => { this.submitSelector = v; })
              }
              .width('100%')
              .margin({ bottom: 12 })

              // Cookie
              Column() {
                Text('Cookie（name=value; ...）')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .margin({ bottom: 4 })
                Row() {
                  Text(this.cookieStatusText)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  Button('获取Cookie（无Cookie请求）')
                    .layoutWeight(1)
                    .margin({ left: 8 })
                    .fontFamily(this.appFontFamily)
                    .onClick(() => { this.fetchCookieWithoutLogin(); })
                }
                .width('100%')
                .margin({ bottom: 6 })
                TextInput({ text: this.cookieInput })
                  .width('100%')
                  .onChange((v: string) => { this.cookieInput = v; })
              }
              .width('100%')
              .margin({ bottom: 16 })

              // 操作按钮
              Row() {
                Button('保存设置')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .fontFamily(this.appFontFamily)
                  .onClick(() => { this.saveSettings(); })
                Button('应用Cookie')
                  .layoutWeight(1)
                  .margin({ left: 4, right: 4 })
                  .fontFamily(this.appFontFamily)
                  .onClick(() => { this.applyCookieInput(); })
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Button('打开登录页')
                  .layoutWeight(1)
                  .margin({ right: 8 })
                  .fontFamily(this.appFontFamily)
                  .onClick(() => { this.openLoginPage(); })
                Button('表单登录')
                  .layoutWeight(1)
                  .margin({ left: 4 })
                  .fontFamily(this.appFontFamily)
                  .onClick(() => { this.performFormLogin(); })
              }
              .width('100%')
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
            .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
            .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
            .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
            .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
            .clip(true)
            .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
            .shadow({
              radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
              color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
              offsetX: 0,
              offsetY: 8
            })

            // 漫画默认阅读设置分组（仅漫画图源显示）
            if (this.sourceType === 'manga') {
            Column() {
              Row() {
                Text('漫画默认阅读设置')
                  .fontSize(18)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.sourceMangaSettingsEnabled })
                  .onChange((isOn: boolean) => { 
                    this.sourceMangaSettingsEnabled = isOn; 
                    this.saveMangaReadingSettings();
                  })
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.sourceMangaSettingsEnabled) {
                // 阅读模式
                Column({ space: 8 }) {
                  Text('默认阅读模式')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach([
                      { mode: ReadingMode.SINGLE_PAGE, label: '单页' },
                      { mode: ReadingMode.DOUBLE_PAGE, label: '双页' },
                      { mode: ReadingMode.CONTINUOUS_SCROLL, label: '连续滚动' },
                      { mode: ReadingMode.WEBTOON, label: '条漫' }
                    ], (item: ReadingModeOption) => {
                      Button({ stateEffect: true }) {
                        Text(item.label)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                      }
                        .height(32)
                        .margin({ right: 8, bottom: 8 })
                        .padding({ left: 12, right: 12 })
                        .backgroundColor(
                          this.sourceReadingMode === item.mode
                            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
                        )
                        .borderRadius(6)
                        .onClick(() => { 
                          this.sourceReadingMode = item.mode; 
                          this.syncSourcePageTurnAnimationForCurrentMode();
                          this.saveMangaReadingSettings();
                        })
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 阅读方向
                Column({ space: 8 }) {
                  Text('默认阅读方向')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach([
                      { direction: ReadingDirection.LEFT_TO_RIGHT, label: '从左到右' },
                      { direction: ReadingDirection.RIGHT_TO_LEFT, label: '从右到左' },
                      { direction: ReadingDirection.TOP_TO_BOTTOM, label: '从上到下' }
                    ], (item: ReadingDirectionOption) => {
                      Button({ stateEffect: true }) {
                        Text(item.label)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                      }
                        .height(32)
                        .margin({ right: 8, bottom: 8 })
                        .padding({ left: 12, right: 12 })
                        .backgroundColor(
                          this.sourceReadingDirection === item.direction
                            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
                        )
                        .borderRadius(6)
                        .onClick(() => { 
                          this.sourceReadingDirection = item.direction; 
                          this.syncSourcePageTurnAnimationForCurrentMode();
                          this.saveMangaReadingSettings();
                        })
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 翻页动画
                Column({ space: 8 }) {
                  Text('默认翻页动画')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  
                  if (this.isSourceVerticalDoublePageModeSelected()) {
                    Column({ space: 8 }) {
                      Button({ stateEffect: true }) {
                        Text('上下专属')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                      }
                      .width(104)
                      .height(32)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                      .borderRadius(6)
                      .onClick(() => {
                        this.sourcePageTurnAnimation = PageTurnAnimationType.SLIDE;
                        this.saveMangaReadingSettings();
                      })
                      Text('双页从上到下使用触顶/触底翻页，只支持专属上下滑动动画。')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                        .width('100%')
                    }
                    .width('100%')
                  } else {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach([
                      { type: PageTurnAnimationType.NONE, label: '无' },
                      { type: PageTurnAnimationType.SLIDE, label: '滑动' },
                      { type: PageTurnAnimationType.FADE, label: '淡入淡出' },
                      { type: PageTurnAnimationType.CURL, label: '卷页' },
                      { type: PageTurnAnimationType.CUBE, label: '立方体' },
                      { type: PageTurnAnimationType.COVER, label: '覆盖' },
                      { type: PageTurnAnimationType.DEPTH, label: '景深' }
                    ], (item: PageTurnAnimationOption) => {
                      Button({ stateEffect: true }) {
                        Text(item.label)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                      }
                        .width(60)
                        .height(32)
                        .margin({ right: 8, bottom: 8 })
                        .backgroundColor(
                          this.sourcePageTurnAnimation === item.type
                            ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                            : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
                        )
                        .borderRadius(6)
                        .onClick(() => { 
                          this.sourcePageTurnAnimation = this.normalizeSourcePageTurnAnimation(item.type);
                          this.saveMangaReadingSettings();
                        })
                    })
                  }
                  .width('100%')
                  }
                }
                .width('100%')
              } else {
                Text('启用后可为此图源的漫画设置默认阅读参数')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .margin({ top: 16 })
            .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
            .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
            .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
            .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
            .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
            .clip(true)
            .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
            .shadow({
              radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
              color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
              offsetX: 0,
              offsetY: 8
            })
            }

            // 电子书默认阅读设置分组（仅电子书图源显示）
            if (this.sourceType === 'ebook') {
            Column() {
              Row() {
                Text('电子书默认阅读设置')
                  .fontSize(18)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.sourceEbookSettingsEnabled })
                  .onChange((isOn: boolean) => { 
                    this.sourceEbookSettingsEnabled = isOn; 
                    this.saveEbookReadingSettings();
                  })
              }
              .width('100%')
              .margin({ bottom: 12 })

              if (this.sourceEbookSettingsEnabled) {
                // 字体大小
                Column({ space: 8 }) {
                  Row() {
                    Text('默认字体大小')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Text(`${this.sourceEbookFontSize}`)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  }
                  .width('100%')

                  Slider({
                    value: this.sourceEbookFontSize,
                    min: 12,
                    max: 32,
                    step: 1,
                    style: SliderStyle.InSet
                  })
                    .width('100%')
                    .trackThickness(4)
                    .onChange((value: number) => { 
                      this.sourceEbookFontSize = Math.round(value); 
                      this.saveEbookReadingSettings();
                    })
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 行高
                Column({ space: 8 }) {
                  Row() {
                    Text('默认行高')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Text(`${this.sourceEbookLineHeight.toFixed(1)}`)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  }
                  .width('100%')

                  Slider({
                    value: this.sourceEbookLineHeight * 10,
                    min: 12,
                    max: 30,
                    step: 1,
                    style: SliderStyle.InSet
                  })
                    .width('100%')
                    .trackThickness(4)
                    .onChange((value: number) => { 
                      this.sourceEbookLineHeight = value / 10; 
                      this.saveEbookReadingSettings();
                    })
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 页边距
                Column({ space: 8 }) {
                  Row() {
                    Text('默认页边距')
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    Blank()
                    Text(`${this.sourceEbookPageMargin}`)
                      .fontSize(14)
                      .fontFamily(this.appFontFamily)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  }
                  .width('100%')

                  Slider({
                    value: this.sourceEbookPageMargin,
                    min: 8,
                    max: 48,
                    step: 4,
                    style: SliderStyle.InSet
                  })
                    .width('100%')
                    .trackThickness(4)
                    .onChange((value: number) => { 
                      this.sourceEbookPageMargin = Math.round(value); 
                      this.saveEbookReadingSettings();
                    })
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 阅读主题
                Column({ space: 8 }) {
                  Text('默认阅读主题')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  Row({ space: 8 }) {
                    ForEach(EBOOK_THEME_PRESETS, (theme: EBookThemePreset, index: number) => {
                      Column() {
                        Stack() {
                          Column()
                            .width(36)
                            .height(36)
                            .backgroundColor(theme.backgroundColor)
                            .borderRadius(18)
                            .border({
                              width: this.sourceEbookThemeIndex === index ? 2 : 1,
                              color: this.sourceEbookThemeIndex === index 
                                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                                : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                            })
                          
                          if (this.sourceEbookThemeIndex === index) {
                            Image($r('app.media.ic_check'))
                              .width(14)
                              .height(14)
                              .fillColor(theme.nightMode ? '#FFFFFF' : '#000000')
                          }
                        }
                        
                        Text(theme.name)
                          .fontSize(10)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                          .margin({ top: 4 })
                      }
                      .onClick(() => { 
                        this.sourceEbookThemeIndex = index; 
                        this.saveEbookReadingSettings();
                      })
                    })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.SpaceAround)
                }
                .width('100%')
                .margin({ bottom: 12 })

                // 翻页模式
                Column({ space: 8 }) {
                  Text('默认翻页模式')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  Row({ space: 16 }) {
                    Row({ space: 8 }) {
                      Radio({ value: 'simulation', group: 'sourceEbookFlipMode' })
                        .checked(this.sourceEbookPageMode === EBookPageMode.SIMULATION)
                        .onChange((isChecked: boolean) => {
                          if (isChecked) { 
                            this.sourceEbookPageMode = EBookPageMode.SIMULATION; 
                            this.saveEbookReadingSettings();
                          }
                        })
                      Text('仿真翻页')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    }

                    Row({ space: 8 }) {
                      Radio({ value: 'horizontal', group: 'sourceEbookFlipMode' })
                        .checked(this.sourceEbookPageMode === EBookPageMode.HORIZONTAL)
                        .onChange((isChecked: boolean) => {
                          if (isChecked) { 
                            this.sourceEbookPageMode = EBookPageMode.HORIZONTAL; 
                            this.saveEbookReadingSettings();
                          }
                        })
                      Text('横向滑动')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    }
                  }
                  .width('100%')
                }
                .width('100%')
              } else {
                Text('启用后可为此图源的电子书设置默认阅读参数')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
            }
            .width(this.isLandscape ? '48%' : '100%')
            .padding(16)
            .margin({ top: 16 })
            .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
            .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
            .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
            .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
            .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
            .clip(true)
            .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
            .shadow({
              radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
              color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
              offsetX: 0,
              offsetY: 8
            })
            }
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight),
            bottom: this.navigationBarHeight + 8
          })
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '图源设置',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack,
          backAction: (): boolean => {
            return this.handleSourceSettingsBack('title_back');
          },
          actions: this.getTitleBarActions()
        })
      }
    }
    .width('100%')
    .height('100%')
    /* .titleBar({
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
        title: { mainTitle: '图源设置' },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showSourceSettingsHelp();
              }
            }
          }]
        }
      }
    }) */
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onBackPressed(() => {
      return this.handleSourceSettingsBack('system_back');
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 从context直接获取参数
      logger.info(TAG, `onReady被调用, pathInfo.param类型: ${typeof context.pathInfo.param}`);
      logger.info(TAG, `onReady pathInfo.param内容: ${JSON.stringify(context.pathInfo.param)}`);
      const params = context.pathInfo.param as SourceSettingsPageParams;
      logger.info(TAG, `转换后的params: ${JSON.stringify(params)}`);
      if (params && params.sourceName) {
        logger.info(TAG, `onReady获取到参数: sourceName=${params.sourceName}`);
        this.pageParams = params;
        this.loadSettings();
      } else {
        logger.error(TAG, `onReady未获取到有效参数, params=${JSON.stringify(params)}`);
      }
    })
    .backgroundColor(Color.Transparent)
  }
}
