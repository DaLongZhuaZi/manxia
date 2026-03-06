// 文件路径：entry/src/main/ets/pages/SourceLoginPage.ets
/**
 * 图源登录页面
 * 提供独立的 WebView 环境用于登录操作
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import webview from '@ohos.web.webview';
import { logger } from '../Utils/Logger';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DataManager } from '../Framework/Data/DataManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import CookieManager from '../Framework/Managers/CookieManager';

const TAG: string = 'SourceLoginPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 页面导航参数
 */
export interface SourceLoginPageParams {
  sourceName: string;
  loginUrl: string;
  loginType: 'webview' | 'form';
  // 表单登录参数（可选）
  username?: string;
  password?: string;
  usernameSelector?: string;
  passwordSelector?: string;
  submitSelector?: string;
}

@Component
export struct SourceLoginPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | undefined = undefined;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  
  // 主题管理
  private themeManager: ThemeManager = ThemeManager.getInstance();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = `SourceLoginPage_${Date.now()}`;
  
  // 页面参数
  private pageParams: SourceLoginPageParams | null = null;
  
  // WebView 控制器
  private webViewController: webview.WebviewController = new webview.WebviewController();
  
  // 管理器
  private dataManager: DataManager = DataManager.getInstance();
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();
  
  // 状态
  @State isLoading: boolean = true;
  @State loadProgress: number = 0;
  @State pageTitle: string = '登录';
  @State canGoBack: boolean = false;
  @State canGoForward: boolean = false;

  aboutToAppear(): void {
    logger.info(TAG, '页面初始化');
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
    
    // 设置自定义 UserAgent
    try {
      this.webViewController.setCustomUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36');
      logger.info(TAG, 'UserAgent 设置成功');
    } catch (error) {
      logger.warn(TAG, `UserAgent 设置失败: ${error}`);
    }
    logger.info(TAG, '=== aboutToAppear 开始 ===');
    const ui = this.getUIContext();
    this.uiContext = ui;
    
    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
    
    logger.info(TAG, '=== aboutToAppear 结束 ===');
  }

  aboutToDisappear(): void {
    logger.info(TAG, '页面即将销毁');
    try {
      // 清理 WebView
      this.webViewController.clearHistory();
    } catch (e) {
      logger.warn(TAG, 'WebView清理失败', String(e));
    }
  }

  /**
   * 处理登录成功
   */
  private async handleLoginSuccess(): Promise<void> {
    if (!this.pageParams) return;
    
    try {
      // 提取并保存 Cookie
      const cookieStr = await this.webViewController.runJavaScript('document.cookie');
      logger.info(TAG, `登录成功，Cookie长度: ${cookieStr.length}`);
      
      if (cookieStr && cookieStr.length > 0) {
        // 获取图源记录以获取数字 ID
        const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
        if (sourceRecord) {
          const sourceId: number = Number(sourceRecord.id);
          await this.authManager.loginWithCookieString(
            sourceId,
            this.webViewController,
            cookieStr
          );
        }
        
        // 返回上一页
        this.pathStack.pop();
      }
    } catch (e) {
      logger.error(TAG, '处理登录成功失败', String(e));
    }
  }

  /**
   * 执行表单登录
   */
  private async performFormLogin(): Promise<void> {
    if (!this.pageParams) return;
    
    try {
      // 获取图源记录以获取数字 ID
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (!sourceRecord) {
        logger.error(TAG, '未找到图源记录');
        return;
      }
      
      const sourceId: number = Number(sourceRecord.id);
      await this.authManager.performFormLogin(
        sourceId,
        this.webViewController,
        this.pageParams.loginUrl,
        this.pageParams.username || '',
        this.pageParams.password || '',
        this.pageParams.usernameSelector || '',
        this.pageParams.passwordSelector || '',
        this.pageParams.submitSelector || ''
      );
      
      logger.info(TAG, '表单登录执行完成');
    } catch (e) {
      logger.error(TAG, '表单登录失败', String(e));
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // WebView 容器
        Column() {
          // 加载进度条
          if (this.isLoading) {
            Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }

          // WebView
          Web({ src: this.pageParams?.loginUrl || 'about:blank', controller: this.webViewController })
            .margin({ top: '10%', bottom: '10%' })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .mixedMode(MixedMode.All)
            .cacheMode(CacheMode.Default)
            .onPageBegin((event) => {
              this.isLoading = true;
              this.loadProgress = 0;
              logger.debug(TAG, `页面开始加载: ${event?.url}`);
            })
            .onPageEnd((event) => {
              this.isLoading = false;
              this.loadProgress = 100;
              this.canGoBack = this.webViewController.accessBackward();
              this.canGoForward = this.webViewController.accessForward();
              logger.debug(TAG, `页面加载完成: ${event?.url}`);
              
              // 如果是表单登录，自动执行
              if (this.pageParams?.loginType === 'form') {
                this.performFormLogin();
              }
            })
            .onProgressChange((event) => {
              this.loadProgress = event?.newProgress || 0;
            })
            .onTitleReceive((event) => {
              this.pageTitle = event?.title || '登录';
            })
            .onErrorReceive((event) => {
              logger.error(TAG, `页面加载错误: ${event?.error?.getErrorInfo()}`);
            })
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .margin({ top: this.statusBarHeight })

        // 底部工具栏
        Row() {
          // 返回按钮
          Button({ type: ButtonType.Normal }) {
            Text('←')
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontColor(this.canGoBack ? 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .opacity(this.canGoBack ? 1.0 : 0.5)
          }
          .width(50)
          .height(40)
          .backgroundColor(Color.Transparent)
          .enabled(this.canGoBack)
          .onClick(() => {
            if (this.canGoBack) {
              this.webViewController.backward();
            }
          })

          // 前进按钮
          Button({ type: ButtonType.Normal }) {
            Text('→')
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontColor(this.canGoForward ? 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .opacity(this.canGoForward ? 1.0 : 0.5)
          }
          .width(50)
          .height(40)
          .backgroundColor(Color.Transparent)
          .enabled(this.canGoForward)
          .onClick(() => {
            if (this.canGoForward) {
              this.webViewController.forward();
            }
          })

          Blank()

          // 刷新按钮
          Button({ type: ButtonType.Normal }) {
            Text('⟳')
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width(50)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.webViewController.refresh();
          })

          // 完成按钮
          Button('完成')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(4)
            .padding({ left: 16, right: 16 })
            .height(36)
            .onClick(() => {
              this.handleLoginSuccess();
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
        .position({ x: 0, y: '100%' })
        .translate({ y: -56 })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(false)
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
        title: {
          mainTitle: this.pageTitle,
          subTitle: this.pageParams?.loginType === 'webview' ? 'WebView登录' : '表单登录'
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 从context直接获取参数
      const params = context.pathInfo.param as SourceLoginPageParams;
      if (params && params.sourceName && params.loginUrl) {
        logger.info(TAG, `onReady获取到参数: sourceName=${params.sourceName}, loginType=${params.loginType}`);
        this.pageParams = params;
        this.pageTitle = params.loginType === 'webview' ? 'WebView登录' : '表单登录';
      } else {
        logger.error(TAG, 'onReady未获取到有效参数');
      }
    })
    .backgroundColor(Color.Transparent)
  }
}
