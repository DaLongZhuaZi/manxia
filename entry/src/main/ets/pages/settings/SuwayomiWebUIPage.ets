import { UIContext } from '@ohos.arkui.UIContext';
/**
 * Suwayomi WebUI 页面
 * 使用 WebView 访问 Suwayomi 服务器的 Web 界面
 * 使用全屏 WebView 访问服务端界面
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareState } from '../../Framework/Components/FontAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { getSuwayomiTracker, SuwayomiTracker } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';

const TAG = 'SuwayomiWebUIPage';

// 页面参数接口
interface SuwayomiWebUIParams {
  url?: string;
}

@Component
export struct SuwayomiWebUIPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // WebView 状态
  @State isLoading: boolean = true;
  @State currentUrl: string = '';
  @State pageTitle: string = 'Suwayomi';
  @State canGoBack: boolean = false;
  @State canGoForward: boolean = false;
  @State errorMessage: string = '';

  private webController: webview.WebviewController = new webview.WebviewController();
  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();
  private componentId: string = 'SuwayomiWebUIPage';
  private serverUrl: string = '';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private initializeUrl(params: SuwayomiWebUIParams | null): void {
    if (params?.url) {
      this.serverUrl = params.url;
    } else {
      this.serverUrl = this.suwayomiTracker.getWebUIUrl();
    }
    this.currentUrl = this.serverUrl;
    logger.info(TAG, `初始化 WebUI URL: ${this.serverUrl}`);
  }

  private goBack(): void {
    if (this.canGoBack) {
      this.webController.backward();
    }
  }

  private goForward(): void {
    if (this.canGoForward) {
      this.webController.forward();
    }
  }

  private refresh(): void {
    this.webController.refresh();
  }

  private goHome(): void {
    this.webController.loadUrl(this.serverUrl);
  }

  private showToast(message: string): void {
    import('@kit.ArkUI').then(arkUI => {
      AppStorage.get<UIContext>('GlobalUIContext')?.getPromptAction()?.showToast({
        message: message,
        duration: 2000
      });
    });
  }

  private buildImmersiveTitleActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'forward',
        symbol: $r('sys.symbol.chevron_right'),
        enabled: this.canGoForward,
        onClick: () => this.goForward()
      },
      {
        id: 'refresh',
        symbol: $r('sys.symbol.arrow_clockwise'),
        onClick: () => this.refresh()
      },
      {
        id: 'home',
        symbol: $r('sys.symbol.house'),
        onClick: () => this.goHome()
      }
    ];
  }

  @Builder
  buildTitleBarMenu() {
    Row({ space: 16 }) {
      // 返回按钮
      Image($r('sys.symbol.chevron_left'))
        .width(24)
        .height(24)
        .fillColor(this.canGoBack ?
          ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .onClick(() => this.goBack())

      // 前进按钮
      Image($r('sys.symbol.chevron_right'))
        .width(24)
        .height(24)
        .fillColor(this.canGoForward ?
          ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .onClick(() => this.goForward())

      // 刷新按钮
      Image($r('sys.symbol.arrow_clockwise'))
        .width(24)
        .height(24)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .onClick(() => this.refresh())

      // 主页按钮
      Image($r('sys.symbol.house'))
        .width(24)
        .height(24)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .onClick(() => this.goHome())
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Start)
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
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          // 工具栏
          // this.buildTitleBarMenu()

          // 加载进度条
          if (this.isLoading) {
            Progress({ value: 0, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }

          // 错误提示
          if (this.errorMessage) {
            Column({ space: 16 }) {
              Image($r('sys.symbol.exclamationmark_triangle'))
                .width(48)
                .height(48)
                .fillColor('#FF6B6B')

              Text(this.errorMessage)
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)
                .fontFamily(this.appFontFamily)

              Button('重试')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .fontColor(Color.White)
                .onClick(() => {
                  this.errorMessage = '';
                  this.webController.loadUrl(this.serverUrl);
                })
                .fontFamily(this.appFontFamily)
            }
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .width('88%')
            .layoutWeight(1)
            .alignSelf(ItemAlign.Center)
            .justifyContent(FlexAlign.Center)
            .padding(24)
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
          } else {
            // WebView
            Web({ src: this.currentUrl, controller: this.webController })
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .width('100%')
              .layoutWeight(1)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .mixedMode(MixedMode.All)
              .cacheMode(CacheMode.Default)
              .databaseAccess(true)
              .fileAccess(true)
              .onlineImageAccess(true)
              .zoomAccess(true)
              .overviewModeAccess(true)
              .onPageBegin(() => {
                this.isLoading = true;
              })
              .onPageEnd(() => {
                this.isLoading = false;
                this.canGoBack = this.webController.accessBackward();
                this.canGoForward = this.webController.accessForward();
              })
              .onTitleReceive((event) => {
                if (event && event.title) {
                  this.pageTitle = event.title;
                }
              })
              .onErrorReceive((event) => {
                if (event && event.error) {
                  const errorInfo = event.error.getErrorInfo();
                  const errorCode = event.error.getErrorCode();
                  logger.debug(TAG, `WebView 资源错误: ${errorInfo}, code: ${errorCode}`);
                  if (this.currentUrl === this.serverUrl && !this.isLoading && errorCode < -100) {
                    this.errorMessage = `无法连接到服务器\n${errorInfo}`;
                  }
                }
              })
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.pageTitle || 'Suwayomi WebUI',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack,
          actions: this.buildImmersiveTitleActions()
        })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: SuwayomiWebUIParams = param as SuwayomiWebUIParams;
        this.initializeUrl(params);
      } else {
        this.initializeUrl(null);
      }
    })
  }
}
