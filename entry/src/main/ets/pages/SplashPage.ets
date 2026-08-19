// 文件路径: src/main/ets/pages/SplashPage.ets
// 职责: 应用启动页面，显示品牌标识和加载状态，监听真实初始化进度

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeManager, ThemeType, CUSTOM_THEME_KEYS } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { common } from '@kit.AbilityKit';
import { colorMap } from 'manxia_core/src/main/ets/Data/ResourceMap';
import { BuiltInThemeResources } from '../Framework/Theme/BuiltInThemeResources';
import { getAppInitializationManager, InitializationState, InitPhase, InitProgressCallback } from '../Framework/Managers/AppInitializationManager';
import { ngfEventBusFacade, NGFEventPayload, NGFInitializationEventName } from '../Framework/NGF';
import { ngfPlatformWindowControllerFacade, NGFDisplayMode } from '../Framework/NGF/platformOhos/index';

const TAG = 'SplashPage';

/**
 * 启动页面组件
 * 实现沉浸式显示，背景图片缩放展示，透明图标覆盖
 */
@Entry
@Component
struct SplashPage {
  // 沉浸式显示状态属性
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 页面状态
  @State private isPageLoaded: boolean = false;
  @State private isThemeLoaded: boolean = false;
  @State private isAppInitialized: boolean = false; // APP初始化是否完成
  @State private backgroundScale: number = 1.0;
  @State private loadingProgress: string = '正在启动...';
  @State private initProgress: number = 0; // 初始化进度 0-100
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isWindowPortrait: boolean = true; // 窗口是否为竖屏（根据窗口尺寸判断）
  
  // 初始化管理器回调
  private initProgressCallback: InitProgressCallback | null = null;
  private ngfInitListenerAttached: boolean = false;
  private readonly ngfInitListenerId: string = 'SplashPage_NGF_InitListener';

  // 自定义主题全局状态（用于背景选择）
  @StorageProp(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE) customSplashBackgroundImage: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE) customBackgroundImage: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE) customThemeActive: boolean = false;
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.HIDE_SPLASH_LOGO) hideSplashLogo: boolean = false;
  @StorageProp(CUSTOM_THEME_KEYS.HIDE_SPLASH_PROGRESS) hideSplashProgress: boolean = false;

  // 主题管理器
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private uiContext: UIContext | undefined = undefined;
  private componentId: string = 'SplashPage';
  private initStartTime: number = 0; // 初始化开始时间
  private readonly MIN_SPLASH_DURATION: number = 1600; // 最小停留时间 1.6 秒
  private readonly MIN_SPLASH_DURATION_SHORTCUT: number = 2200; // 快捷入口启动最小停留时间 2.2 秒

  private isNgfPlatformIntegrated(): boolean {
    try {
      return AppStorage.get<boolean>('ngf_platform_integrated') === true;
    } catch (_error) {
      return false;
    }
  }

  private toNgfDisplayMode(mode: DisplayMode): NGFDisplayMode | null {
    switch (mode) {
      case DisplayMode.DEFAULT:
        return NGFDisplayMode.DEFAULT;
      case DisplayMode.FULL_IMMERSIVE:
        return NGFDisplayMode.FULL_IMMERSIVE;
      case DisplayMode.IMMERSIVE_WITH_BARS:
        return NGFDisplayMode.IMMERSIVE_WITH_BARS;
      case DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE:
        return NGFDisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE;
      case DisplayMode.HIDE_STATUS_BAR:
      case DisplayMode.HIDE_NAVIGATION_BAR:
      default:
        return null;
    }
  }

  private applyDisplayModeWithNgfFallback(mode: DisplayMode): void {
    if (this.isNgfPlatformIntegrated()) {
      const ngfMode = this.toNgfDisplayMode(mode);
      if (ngfMode !== null) {
        try {
          ngfPlatformWindowControllerFacade.setDisplayMode(ngfMode);
          return;
        } catch (error) {
          logger.warn(TAG, `NGF窗口模式切换失败，回退旧链路: ${String(error)}`);
        }
      }
    }
    WindowManager.setDisplayMode(mode, this.uiContext);
  }

  aboutToAppear(): void {
    logger.lifecycle('SplashPage', '🚀 启动页面开始加载');
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error('SplashPage', '获取UIContext失败');
      return;
    }

    this.applyDisplayModeWithNgfFallback(DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE);

    // 检测窗口实际方向（根据窗口尺寸判断，而非物理方向）
    this.detectWindowOrientation();

    // 开始完整的初始化流程
    this.startCompleteInitialization();
  }

  /**
   * 检测窗口实际方向
   * 在SplashPage期间强制使用竖屏布局，避免系统锁定竖屏但设备横握时的显示问题
   * 跳转到MainMenuPage后会恢复自动旋转
   */
  private detectWindowOrientation(): void {
    try {
      const mainWindow = WindowManager.getMainWindowFromUIContext(this.uiContext);
      if (mainWindow) {
        const props = mainWindow.getWindowProperties();
        const rect = props.windowRect;
        logger.info(TAG, `窗口尺寸: width=${rect.width}, height=${rect.height}`);
        
        // SplashPage期间强制使用竖屏布局
        // 这样可以避免系统锁定竖屏但设备横握时的显示问题
        // 跳转到MainMenuPage后会根据用户设置恢复自动旋转
        this.isWindowPortrait = true;
        logger.info(TAG, `SplashPage强制使用竖屏布局`);
      }
    } catch (error) {
      logger.warn(TAG, `窗口方向检测失败: ${String(error)}`);
      this.isWindowPortrait = true; // 默认竖屏
    }
  }

  /**
   * 开始完整的初始化流程
   * 监听 EntryAbility 的真实初始化进度
   */
  private async startCompleteInitialization(): Promise<void> {
    try {
      logger.info('SplashPage', '🎯 开始完整初始化流程');
      this.initStartTime = Date.now();
      
      // 1. 初始化欢迎引导管理器（SplashPage自己的初始化）
      logger.info('SplashPage', '📖 初始化欢迎引导管理器...');
      await this.welcomeGuideManager.initialize();
      logger.info('SplashPage', '✅ 欢迎引导管理器初始化完成');

      // 2. 初始化主题管理器（先加载主题级开屏显示策略）
      logger.info('SplashPage', '🎨 初始化主题管理器...');
      const wasThemeManagerReady: boolean = this.themeManager.isReady();
      await this.themeManager.initialize();
      if (wasThemeManagerReady) {
        await this.themeManager.refreshSplashBackgroundForLaunch();
      }
      
      // 4. 初始化主题感知功能
      await ThemeAwareHelper.initializeThemeAware(
        this.componentId,
        this.themeState,
        (newTheme: ThemeType) => {
          logger.info('SplashPage', `🔄 主题变化: ${this.themeState.currentTheme} -> ${newTheme}`);
        },
        (newState: ThemeAwareState) => {
          this.themeState = newState;
        }
      );
      
      logger.info('SplashPage', `✅ 主题初始化完成: ${this.themeState.currentTheme}`);
      this.isThemeLoaded = true;
      logger.info(
        TAG,
        `开屏显示策略: customActive=${this.customThemeActive}, hideLogo=${this.themeManager.isSplashLogoHiddenByTheme()}, hideProgress=${this.themeManager.isSplashProgressHiddenByTheme()}`
      );

      // 3. 注册初始化进度监听器（在主题状态加载后再绑定，避免先显示再隐藏）
      this.setupInitializationListener();

      // 4. 等待 EntryAbility 的初始化完成
      await this.waitForAppInitialization();
      
      // 5. 所有初始化完成
      this.isPageLoaded = true;
      this.checkInitializationComplete();

    } catch (error) {
      logger.error('SplashPage', '初始化失败', String(error));
      this.loadingProgress = '初始化失败';
      this.isThemeLoaded = true;
      this.isPageLoaded = true;
      this.isAppInitialized = true;
      
      // 即使失败也要跳转
      setTimeout(() => {
        this.navigateToMainPage();
      }, 1000);
    }
  }
  
  /**
   * 设置初始化进度监听器
   */
  private setupInitializationListener(): void {
    const initManager = getAppInitializationManager();
    
    this.initProgressCallback = (state: InitializationState) => {
      // 更新进度和显示文本
      this.initProgress = state.progress;
      this.loadingProgress = state.displayText;
      
      logger.info('SplashPage', `📊 初始化进度: ${state.progress}% - ${state.displayText}`);
      
      // 检查是否完成或失败
      if (state.isCompleted) {
        this.isAppInitialized = true;
        logger.info('SplashPage', '✅ APP初始化完成');
      } else if (state.isFailed) {
        this.isAppInitialized = true;
        logger.warn('SplashPage', `⚠️ APP初始化失败: ${state.errorMessage}`);
      }
    };
    
    initManager.addProgressListener(this.initProgressCallback);
    this.setupNGFInitializationBridgeListener();
  }

  private setupNGFInitializationBridgeListener(): void {
    if (this.ngfInitListenerAttached) {
      return;
    }

    const stateSubscribed = ngfEventBusFacade.subscribe(
      NGFInitializationEventName.INIT_STATE_CHANGED,
      this.ngfInitListenerId,
      (payload: NGFEventPayload): void => {
        logger.debug(TAG, `收到NGF初始化状态事件: ${payload.payloadJson}`);
      }
    );

    const failedSubscribed = ngfEventBusFacade.subscribe(
      NGFInitializationEventName.INIT_FAILED,
      this.ngfInitListenerId,
      (payload: NGFEventPayload): void => {
        logger.warn(TAG, `收到NGF初始化失败事件: ${payload.payloadJson}`);
        if (!this.isAppInitialized) {
          this.loadingProgress = '初始化失败';
        }
      }
    );

    const completedSubscribed = ngfEventBusFacade.subscribe(
      NGFInitializationEventName.INIT_COMPLETED,
      this.ngfInitListenerId,
      (payload: NGFEventPayload): void => {
        logger.info(TAG, `收到NGF初始化完成事件: ${payload.payloadJson}`);
        if (!this.isAppInitialized) {
          this.loadingProgress = '准备就绪';
        }
      }
    );

    this.ngfInitListenerAttached = stateSubscribed || failedSubscribed || completedSubscribed;
  }

  private cleanupNGFInitializationBridgeListener(): void {
    if (!this.ngfInitListenerAttached) {
      return;
    }

    ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_STATE_CHANGED, this.ngfInitListenerId);
    ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_FAILED, this.ngfInitListenerId);
    ngfEventBusFacade.unsubscribe(NGFInitializationEventName.INIT_COMPLETED, this.ngfInitListenerId);
    this.ngfInitListenerAttached = false;
  }
  
  /**
   * 等待APP初始化完成
   */
  private async waitForAppInitialization(): Promise<void> {
    const initManager = getAppInitializationManager();
    
    // 如果已经完成，直接返回
    if (initManager.isCompleted() || initManager.isFailed()) {
      this.isAppInitialized = true;
      return;
    }
    
    // 等待初始化Promise完成
    logger.info('SplashPage', '⏳ 等待APP初始化完成...');
    const success = await initManager.getCompletionPromise();
    this.isAppInitialized = true;
    
    if (success) {
      logger.info('SplashPage', `✅ APP初始化成功，耗时: ${initManager.getDuration()}ms`);
    } else {
      logger.warn('SplashPage', '⚠️ APP初始化失败，将继续启动');
    }
  }

  /**
   * 检查初始化是否完成
   */
  private checkInitializationComplete(): void {
    // 必须同时满足：页面加载完成 + 主题加载完成 + APP初始化完成
    if (this.isPageLoaded && this.isThemeLoaded && this.isAppInitialized) {
      const elapsed = Date.now() - this.initStartTime;
      const minDuration = this.getEffectiveMinSplashDuration();
      const remainingTime = Math.max(0, minDuration - elapsed);
      
      logger.info('SplashPage', `✅ 所有初始化完成，耗时 ${elapsed}ms，还需等待 ${remainingTime}ms`);
      
      // 确保最少停留时间
      if (remainingTime > 0) {
        this.loadingProgress = '准备就绪';
        setTimeout(() => {
          this.fadeOutAndNavigate();
        }, remainingTime);
      } else {
        this.fadeOutAndNavigate();
      }
    }
  }

  /**
   * 执行跳转（淡出动画由 pageTransition 处理）
   */
  private fadeOutAndNavigate(): void {
    this.loadingProgress = '';
    // 直接跳转，淡出动画由 pageTransition 处理
    this.navigateToMainPage();
  }

  /**
   * 跳转到主页面或引导页面
   */
  private navigateToMainPage(): void {
    let targetUrl: string = '';
    let startupRoutePending: boolean = false;
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error('SplashPage', '无法获取UIAbilityContext');
        return;
      }

      const shouldShowGuide = this.welcomeGuideManager.shouldShowGuide();
      logger.info('SplashPage', `是否显示引导: ${shouldShowGuide}`);

      startupRoutePending = !shouldShowGuide && this.hasWidgetTargetPage();
      AppStorage.setOrCreate('startupRoutePending', startupRoutePending);
      AppStorage.setOrCreate('appGuideStartupPending', false);
      if (startupRoutePending) {
        this.loadingProgress = '正在准备快捷入口...';
      }

      const router = this.uiContext?.getRouter();
      if (router) {
        targetUrl = shouldShowGuide ? 'pages/WelcomeGuidePage' : 'pages/MainMenuPage';
        logger.info('SplashPage', `prepare_navigation: targetUrl=${targetUrl}, startupRoutePending=${startupRoutePending}`);

        router.pushUrl({
          url: targetUrl
        }).then(() => {
          logger.info('SplashPage', `navigation_success: target=${shouldShowGuide ? 'WelcomeGuidePage' : 'MainMenuPage'}, shouldShowGuide=${shouldShowGuide}`);
          router.clear();
        }).catch((error: Object | string | number | boolean) => {
          logger.error('SplashPage', `navigation_failed: ${this.buildNavigationErrorDetails(error)}`);
        });
      } else {
        logger.error('SplashPage', '无法获取Router实例');
      }
    } catch (error) {
      const errorDetails: string = this.buildNavigationErrorDetails(error as Object | string | number | boolean | null | undefined);
      logger.error('SplashPage',
        `navigation_exception: targetUrl=${targetUrl}, startupRoutePending=${startupRoutePending}, details=${errorDetails}`);
    }
  }

  private buildNavigationErrorDetails(error: Object | string | number | boolean | null | undefined): string {
    let errorDetails: string = String(error);
    if (typeof error === 'object' && error !== null) {
      const routeError: Error = error as Error;
      if (typeof routeError.message === 'string' && routeError.message.length > 0 && routeError.message !== errorDetails) {
        errorDetails = `${errorDetails}; message=${routeError.message}`;
      }
      if (typeof routeError.stack === 'string' && routeError.stack.length > 0) {
        errorDetails = `${errorDetails}; stack=${routeError.stack}`;
      }
      try {
        const errorJson: string = JSON.stringify(error);
        if (errorJson.length > 0 && errorJson !== '{}') {
          errorDetails = `${errorDetails}; json=${errorJson}`;
        }
      } catch {
      }
    }
    return errorDetails;
  }

  private hasWidgetTargetPage(): boolean {
    const targetPage = AppStorage.get<string>('widgetTargetPage') || '';
    return targetPage.trim().length > 0;
  }

  private getEffectiveMinSplashDuration(): number {
    return this.hasWidgetTargetPage() ? this.MIN_SPLASH_DURATION_SHORTCUT : this.MIN_SPLASH_DURATION;
  }

  /**
   * 页面即将销毁时的清理工作
   */
  private lifecycle = new PageLifecycleManager('SplashPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle('SplashPage', '页面即将销毁');
    this.lifecycle.destroy();
    // 清理主题感知功能
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // 清理初始化进度监听器
    if (this.initProgressCallback) {
      const initManager = getAppInitializationManager();
      initManager.removeProgressListener(this.initProgressCallback);
      this.initProgressCallback = null;
    }
    this.cleanupNGFInitializationBridgeListener();
  }

  /**
   * 根据当前主题获取文本颜色
   */
  private getTextColor(): ResourceStr {
    return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
  }

  /**
   * 获取开屏页兜底背景色
   * 说明：避免透明背景在部分设备/系统主题下透出窗口默认白底
   */
  private getSplashBaseBackgroundColor(): ResourceStr {
    return ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme);
  }

  private shouldShowSplashLogo(): boolean {
    const hiddenByManager: boolean = this.themeManager.isSplashLogoHiddenByTheme();
    if (hiddenByManager) {
      return false;
    }
    if (!this.customThemeActive) {
      return true;
    }
    return !this.hideSplashLogo;
  }

  private shouldShowSplashProgress(): boolean {
    // 主题状态未加载完成前不显示进度，避免配置加载前出现错误闪现
    if (!this.isThemeLoaded) {
      return false;
    }
    const hiddenByManager: boolean = this.themeManager.isSplashProgressHiddenByTheme();
    if (hiddenByManager) {
      return false;
    }
    if (!this.customThemeActive) {
      return true;
    }
    return !this.hideSplashProgress;
  }

  build() {
    // 沉浸式显示设计：Stack双层布局
    Stack() {
      // 背景层 - 扩展到系统栏区域
      // 支持自定义主题的开屏背景（优先使用开屏背景，其次使用普通背景，最后使用默认资源）
      if (this.customThemeActive && this.customSplashBackgroundImage && this.customSplashBackgroundImage.length > 0) {
        Image('file://' + this.customSplashBackgroundImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: this.backgroundScale, y: this.backgroundScale })
          .syncLoad(true)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else if (this.customThemeActive && this.customBackgroundImage && this.customBackgroundImage.length > 0) {
        Image('file://' + this.customBackgroundImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Auto)
          .scale({ x: this.backgroundScale, y: this.backgroundScale })
          .syncLoad(true)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else if (this.customThemeActive) {
        Image(this.getFallbackMediaResource())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .scale({ x: this.backgroundScale, y: this.backgroundScale })
          .syncLoad(true)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.getSplashBaseBackgroundColor())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      // 内容层 - 预留安全区域
      Column() {
        // 主要内容区域
        Column() {
          // Logo区域 - 使用应用图标
          if (this.shouldShowSplashLogo()) {
            Image($r('app.media.icon'))
              .width(126)
              .height(126)
              .objectFit(ImageFit.Contain)
              .animation({ duration: 300, curve: Curve.EaseOut })
          }

          if (this.shouldShowSplashProgress()) {
            // 加载状态文本
            Text(this.loadingProgress)
              .fontSize(16)
              .fontColor(this.getTextColor())
              .opacity(0.8)
              .margin({ top: 24 })
              .animation({ duration: 200, curve: Curve.EaseOut })
            
            // 进度条容器
            Column() {
              // 进度条背景
              Stack({ alignContent: Alignment.Start }) {
                // 背景轨道
                Row()
                  .width('100%')
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor(this.themeState.currentTheme === 'dark' 
                    ? 'rgba(255, 255, 255, 0.1)' 
                    : 'rgba(0, 0, 0, 0.1)')
                
                // 进度填充
                Row()
                  .width(`${this.initProgress}%`)
                  .height(4)
                  .borderRadius(2)
                  .backgroundColor(this.themeState.currentTheme === 'dark'
                    ? '#4FC3F7'
                    : '#2196F3')
                  .animation({ duration: 300, curve: Curve.EaseOut })
              }
              .width(200)
              .height(4)
              
              // 进度百分比文本
              Text(`${this.initProgress}%`)
                .fontSize(12)
                .fontColor(this.getTextColor())
                .opacity(0.6)
                .margin({ top: 8 })
            }
            .margin({ top: 32 })
            .opacity(this.initProgress > 0 ? 1 : 0)
            .animation({ duration: 300, curve: Curve.EaseOut })
          }
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getSplashBaseBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // 页面过渡动画
  pageTransition() {
    // SplashPage 退出时保持不变（让 MainMenuPage 淡入覆盖）
    PageTransitionExit({ duration: 350, curve: Curve.EaseOut })
  }

  // 媒体资源回退：根据当前自定义主题ID与设备类型选择 a_* / b_*
  private getFallbackMediaResource(): ResourceStr {
    return BuiltInThemeResources.resolveResource(this.currentCustomThemeId);
  }
}

export { SplashPage };
