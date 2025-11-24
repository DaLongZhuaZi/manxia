// 文件路径: src/main/ets/pages/SplashPage.ets
// 职责: 应用启动页面，显示品牌标识和加载状态

import { logger } from '../Utils/Logger';
import { ThemeManager, ThemeType, CUSTOM_THEME_KEYS } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';
import { common } from '@kit.AbilityKit';
import { colorMap } from '../Data/ResourceMap';
import { deviceInfo } from '@kit.BasicServicesKit';

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
  @State private backgroundScale: number = 1.0;
  @State private logoOpacity: number = 0;
  @State private loadingProgress: string = '正在启动...';
  @State private themeState: ThemeAwareState = new ThemeAwareState();

  // 自定义主题全局状态（用于背景选择）
  @StorageProp(CUSTOM_THEME_KEYS.SPLASH_BACKGROUND_IMAGE) customSplashBackgroundImage: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.BACKGROUND_IMAGE) customBackgroundImage: string = '';
  @StorageProp(CUSTOM_THEME_KEYS.IS_CUSTOM_THEME_ACTIVE) customThemeActive: boolean = false;
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';

  // 主题管理器
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private uiContext: UIContext | undefined = undefined;
  private componentId: string = 'SplashPage';

  aboutToAppear(): void {
    logger.lifecycle('SplashPage', '🚀 启动页面开始加载');
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error('SplashPage', '获取UIContext失败');
      return;
    }

    // 开始完整的初始化流程
    this.startCompleteInitialization();
  }

  /**
   * 开始完整的初始化流程
   */
  private async startCompleteInitialization(): Promise<void> {
    try {
      logger.info('SplashPage', '🎯 开始完整初始化流程');
      
      // 1. 启动入场动画（不依赖主题）
      this.startEntranceAnimation();
      this.loadingProgress = '正在启动...';

      // 2. 初始化欢迎引导管理器
      logger.info('SplashPage', '📖 开始初始化欢迎引导管理器...');
      await this.welcomeGuideManager.initialize();
      logger.info('SplashPage', '✅ 欢迎引导管理器初始化完成');

      // 3. 等待ThemeManager完全初始化
      logger.info('SplashPage', '🎨 开始初始化主题管理器...');
      await this.themeManager.initialize();
      
      // 4. 使用ThemeAwareHelper初始化主题感知功能（现在会获取正确的实际主题）
      await ThemeAwareHelper.initializeThemeAware(
        this.componentId,
        this.themeState,
        (newTheme: ThemeType) => {
          logger.info('SplashPage', `🔄 主题变化: ${this.themeState.currentTheme} -> ${newTheme}`);
        },
        (newState: ThemeAwareState) => {
          // 重新赋值整个themeState对象以触发UI更新
          this.themeState = newState;
        }
      );
      
      logger.info('SplashPage', `✅ 主题初始化完成，当前显示主题: ${this.themeState.currentTheme}`);

      this.isThemeLoaded = true;
      this.loadingProgress = '主题加载完成';

      // 5. 等待页面渲染完成
      setTimeout(() => {
        this.isPageLoaded = true;
        this.loadingProgress = '初始化完成';
        this.checkInitializationComplete();
      }, 800); // 给用户足够时间看到主题应用效果

    } catch (error) {
      logger.error('SplashPage', '完整初始化失败', String(error));
      this.loadingProgress = '初始化失败';


      this.isThemeLoaded = true;
      this.isPageLoaded = true;
      
      // 即使失败也要跳转，避免卡在启动页
      setTimeout(() => {
        this.navigateToMainPage();
      }, 1000);
    }
  }

  /**
   * 启动入场动画
   */
  private startEntranceAnimation(): void {
    if (!this.uiContext) return;

    // 背景缩放动画
    const scaleAnimateOptions: AnimateParam = {
      duration: 1500,
      curve: Curve.EaseOut,
      iterations: 1,
      playMode: PlayMode.Normal
    };

    this.uiContext.animateTo(scaleAnimateOptions, () => {
      this.backgroundScale = 1.1;
    });

    // Logo淡入动画
    setTimeout(() => {
      if (!this.uiContext) return;
      
      const fadeAnimateOptions: AnimateParam = {
        duration: 800,
        curve: Curve.EaseInOut,
        iterations: 1,
        playMode: PlayMode.Normal
      };

      this.uiContext.animateTo(fadeAnimateOptions, () => {
        this.logoOpacity = 1.0;
      });
    }, 300);
  }

  /**
   * 检查初始化是否完成
   */
  private checkInitializationComplete(): void {
    if (this.isPageLoaded && this.isThemeLoaded) {
      logger.info('SplashPage', '✅ 所有初始化完成，准备跳转到主页面');
      
      // 延迟一段时间让用户看到完成状态
      setTimeout(() => {
        this.navigateToMainPage();
      }, 800);
    }
  }

  /**
   * 跳转到主页面或引导页面
   */
  private navigateToMainPage(): void {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error('SplashPage', '无法获取UIAbilityContext');
        return;
      }

      // 检查是否需要显示引导页面
      const shouldShowGuide = this.welcomeGuideManager.shouldShowGuide();
      logger.info('SplashPage', `是否显示引导: ${shouldShowGuide}`);

      // 使用router跳转到对应页面
      const router = this.uiContext?.getRouter();
      if (router) {
        const targetUrl = shouldShowGuide ? 'pages/WelcomeGuidePage' : 'pages/MainMenuPage';
        
        router.replaceUrl({
          url: targetUrl
        }).then(() => {
          logger.info('SplashPage', `✅ 成功跳转到${shouldShowGuide ? '引导' : '主'}页面`);
        }).catch((error: Error) => {
          logger.error('SplashPage', '跳转失败', error.message);
        });
      } else {
        logger.error('SplashPage', '无法获取Router实例');
      }
    } catch (error) {
      logger.error('SplashPage', '跳转过程中发生异常', String(error));
    }
  }

  /**
   * 页面即将销毁时的清理工作
   */
  aboutToDisappear(): void {
    logger.lifecycle('SplashPage', '页面即将销毁');
    // 清理主题感知功能
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 根据当前主题获取文本颜色
   */
  private getTextColor(): ResourceStr {
    return ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme);
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
          .backgroundColor(Color.Transparent)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      // 内容层 - 预留安全区域
      Column() {
        // 主要内容区域
        Column() {
          // Logo区域 - 使用应用图标
          Image($r('app.media.icon'))
            .width(120)
            .height(120)
            .objectFit(ImageFit.Contain)
            .opacity(this.logoOpacity)

          // 加载状态文本
          Text(this.loadingProgress)
            .fontSize(16)
            .fontColor(this.getTextColor())
            .opacity(0.8)
            .margin({ top: 24 })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
  }

  // 媒体资源回退：根据当前自定义主题ID与设备类型选择 a_* / b_*
  private getFallbackMediaResource(): ResourceStr {
    const setId: string = (this.currentCustomThemeId === 'secondary_custom_theme') ? 'b' : 'a';
    const devType: string = String(deviceInfo.deviceType);
    if (setId === 'a') {
      if (devType === 'foldable') { return $r('app.media.a_1'); }
      if (devType === 'phone') { return $r('app.media.a_2'); }
      return $r('app.media.a_3');
    } else {
      if (devType === 'foldable') { return $r('app.media.b_1'); }
      if (devType === 'phone') { return $r('app.media.b_2'); }
      return $r('app.media.b_3');
    }
  }
}

export { SplashPage };