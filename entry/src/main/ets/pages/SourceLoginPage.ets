import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 图源登录页面
 * 提供独立 WebView 环境用于登录操作
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import webview from '@ohos.web.webview';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { DataManager } from '../Framework/Data/DataManager';
import CookieManager from 'manxia_core/src/main/ets/Framework/Managers/CookieManager';
import { WebViewAuthManager } from '../Framework/WebView/WebViewAuthManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG: string = 'SourceLoginPage';
const LOGIN_PAGE_DESKTOP_USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
const LOGIN_PAGE_MOBILE_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36';
const COPYMANGA_SOURCE_NAME: string = '\u62F7\u8D1D\u6F2B\u753B';
const COPYMANGA_PRIMARY_DOMAIN: string = 'mangacopy.com';
const COPYMANGA_FALLBACK_DOMAIN: string = 'copymanga.com';
const AUTO_LOGIN_CHECK_INTERVAL_MS: number = 1200;

/**
 * 页面导航参数
 */
export interface SourceLoginPageParams {
  sourceName: string;
  loginUrl: string;
  loginType: 'webview' | 'form';
  username?: string;
  password?: string;
  usernameSelector?: string;
  passwordSelector?: string;
  submitSelector?: string;
}

interface CopyMangaLoginSnapshot {
  hasToken: boolean;
  hasUserId: boolean;
  cookieLength: number;
  currentUrl: string;
}

@Component
export struct SourceLoginPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();

  private componentId: string = `SourceLoginPage_${Date.now()}`;
  private pageParams: SourceLoginPageParams | null = null;
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private dataManager: DataManager = DataManager.getInstance();
  private authManager: WebViewAuthManager = WebViewAuthManager.getInstance();

  @State isLoading: boolean = true;
  @State loadProgress: number = 0;
  @State pageTitle: string = '图源登录';
  @State canGoBack: boolean = false;
  @State canGoForward: boolean = false;
  @State loginTargetUrl: string = 'about:blank';
  @State currentLoginType: 'webview' | 'form' = 'webview';

  private appliedUserAgent: string = '';
  private formLoginTriggered: boolean = false;
  private targetNavigationPending: boolean = false;
  private targetNavigationAttempted: boolean = false;
  private webControllerAttached: boolean = false;
  private navigationRetryCount: number = 0;
  private maxNavigationRetries: number = 8;
  private autoCompleteTriggered: boolean = false;
  private isCompletingLogin: boolean = false;
  private lastAutoLoginCheckTime: number = 0;

  aboutToAppear(): void {
    logger.info(TAG, '页面初始化');
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
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

    setTimeout(() => {
      this.applyCustomUserAgentIfNeeded();
    }, 0);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    this.webControllerAttached = false;
    try {
      this.webViewController.clearHistory();
    } catch (error) {
      logger.warn(TAG, `WebView 清理失败: ${String(error)}`);
    }
  }

  private scheduleNavigateToTarget(reason: string, delayMs: number): void {
    if (!this.targetNavigationPending || this.loginTargetUrl === 'about:blank') {
      return;
    }
    setTimeout(() => {
      this.tryNavigateToTarget(reason);
    }, delayMs);
  }

  private isCopyMangaLoginFlow(): boolean {
    const lowerUrl: string = this.loginTargetUrl.toLowerCase();
    if (lowerUrl.includes(COPYMANGA_PRIMARY_DOMAIN) || lowerUrl.includes(COPYMANGA_FALLBACK_DOMAIN)) {
      return true;
    }

    const sourceName: string = this.pageParams ? this.pageParams.sourceName : '';
    return sourceName === COPYMANGA_SOURCE_NAME;
  }

  private getTargetUserAgent(): string {
    if (this.isCopyMangaLoginFlow()) {
      return LOGIN_PAGE_MOBILE_USER_AGENT;
    }
    return LOGIN_PAGE_DESKTOP_USER_AGENT;
  }

  private normalizeCookieString(rawCookie: string): string {
    const normalized: string = rawCookie ? rawCookie.trim() : '';
    if (normalized.length === 0 || normalized === 'undefined' || normalized === 'null') {
      return '';
    }
    return normalized;
  }

  private getContentPanelMargin(): number {
    return this.isCopyMangaLoginFlow() ? 4 : 12;
  }

  private getActionBarBottomInset(): number {
    return this.isCopyMangaLoginFlow() ? 4 : 8;
  }

  private shouldAttemptAutoComplete(_loadedUrl: string): boolean {
    return false;
  }

  private parseCopyMangaLoginSnapshot(rawJson: string, fallbackUrl: string): CopyMangaLoginSnapshot {
    const fallbackSnapshot: CopyMangaLoginSnapshot = {
      hasToken: false,
      hasUserId: false,
      cookieLength: 0,
      currentUrl: fallbackUrl
    };
    if (rawJson.length === 0) {
      return fallbackSnapshot;
    }

    try {
      const parsedResult = SafeUtils.parseObj(rawJson) as Object;
      const parsedObj: Record<string, Object> = typeof parsedResult === 'string'
        ? SafeUtils.parseObj(String(parsedResult)) as Record<string, Object>
        : parsedResult as Record<string, Object>;
      const keys: string[] = Object.keys(parsedObj);
      if (!keys.includes('hasToken') || !keys.includes('hasUserId') || !keys.includes('cookieLength')) {
        return fallbackSnapshot;
      }
      const resolvedUrl: string = keys.includes('currentUrl') ? String(parsedObj['currentUrl']) : fallbackUrl;
      return {
        hasToken: parsedObj['hasToken'] === true,
        hasUserId: parsedObj['hasUserId'] === true,
        cookieLength: Number(parsedObj['cookieLength']),
        currentUrl: resolvedUrl
      };
    } catch (error) {
      logger.debug(TAG, `解析自动登录检测结果失败: ${String(error)}`);
      return fallbackSnapshot;
    }
  }

  private async tryAutoCompleteLogin(loadedUrl: string): Promise<void> {
    if (!this.shouldAttemptAutoComplete(loadedUrl)) {
      return;
    }

    const now: number = Date.now();
    if (now - this.lastAutoLoginCheckTime < AUTO_LOGIN_CHECK_INTERVAL_MS) {
      return;
    }
    this.lastAutoLoginCheckTime = now;

    try {
      const snapshotScript: string = `
        (() => {
          const rawCookie = document.cookie || '';
          const names = rawCookie.split(';').map((item) => item.trim().split('=')[0]).filter((item) => item.length > 0);
          return JSON.stringify({
            hasToken: names.indexOf('token') >= 0,
            hasUserId: names.indexOf('user_id') >= 0,
            cookieLength: rawCookie.length,
            currentUrl: window.location.href || ''
          });
        })();
      `;
      const rawSnapshot: string = await this.webViewController.runJavaScript(snapshotScript) as string;
      const snapshot: CopyMangaLoginSnapshot = this.parseCopyMangaLoginSnapshot(rawSnapshot, loadedUrl);
      if (snapshot.hasToken && snapshot.hasUserId && snapshot.cookieLength > 0) {
        this.autoCompleteTriggered = true;
        logger.info(TAG, `检测到拷贝漫画登录成功，自动完成登录: url=${snapshot.currentUrl}, cookieLength=${String(snapshot.cookieLength)}`);
        void this.handleLoginSuccess();
      }
    } catch (error) {
      logger.debug(TAG, `自动完成登录检测失败: ${String(error)}`);
    }
  }

  private applyCustomUserAgentIfNeeded(): void {
    const targetUserAgent: string = this.getTargetUserAgent();
    if (this.appliedUserAgent === targetUserAgent) {
      return;
    }

    try {
      this.webViewController.setCustomUserAgent(targetUserAgent);
      this.appliedUserAgent = targetUserAgent;
      logger.info(TAG, `UserAgent 设置成功: ${this.isCopyMangaLoginFlow() ? 'mobile' : 'desktop'}`);
    } catch (error) {
      const errorText: string = String(error);
      if (errorText.includes('Init error')) {
        return;
      }
      logger.warn(TAG, `UserAgent 设置失败: ${errorText}`);
    }
  }

  private tryNavigateToTarget(reason: string): void {
    if (!this.targetNavigationPending ||
      this.targetNavigationAttempted ||
      this.loginTargetUrl === 'about:blank') {
      return;
    }
    if (!this.webControllerAttached) {
      this.scheduleNavigateToTarget(`${reason}_waitAttach`, 120);
      return;
    }
    if (this.navigationRetryCount >= this.maxNavigationRetries) {
      logger.warn(TAG, `Login navigation exceeded retry limit: url=${this.loginTargetUrl}`);
      this.targetNavigationPending = false;
      return;
    }

    try {
      this.navigationRetryCount = this.navigationRetryCount + 1;
      this.webViewController.loadUrl(this.loginTargetUrl);
      this.targetNavigationAttempted = true;
      logger.info(
        TAG,
        `Trigger login navigation (${reason}) [${String(this.navigationRetryCount)}/${String(this.maxNavigationRetries)}]: ${this.loginTargetUrl}`
      );
      logger.info(TAG, `已触发登录地址跳转(${reason}): ${this.loginTargetUrl}`);
    } catch (error) {
      const errorText: string = String(error);
      if (!errorText.includes('Init error')) {
        this.targetNavigationAttempted = false;
        this.scheduleNavigateToTarget(`${reason}_retry`, 160);
        logger.warn(TAG, `触发登录地址跳转失败(${reason}): ${errorText}`);
      }
    }
  }

  private applyLoginParams(params: SourceLoginPageParams): void {
    this.pageParams = params;
    this.currentLoginType = params.loginType;
    this.pageTitle = params.loginType === 'webview' ? 'WebView 登录' : '表单登录';
    this.formLoginTriggered = false;
    this.autoCompleteTriggered = false;
    this.isCompletingLogin = false;
    this.lastAutoLoginCheckTime = 0;

    const targetUrl: string = params.loginUrl.trim().length > 0 ? params.loginUrl.trim() : 'about:blank';
    this.loginTargetUrl = targetUrl;
    this.targetNavigationPending = targetUrl !== 'about:blank';
    this.targetNavigationAttempted = false;
    this.navigationRetryCount = 0;
    logger.info(TAG, '图源登录页已禁用自动完成，请手动点击“完成登录”保存最新Cookie');
    logger.info(TAG, `登录参数已应用: loginType=${params.loginType}, targetUrl=${targetUrl}`);

    setTimeout(() => {
      this.applyCustomUserAgentIfNeeded();
      this.scheduleNavigateToTarget('applyLoginParams', 80);
    }, 0);
  }

  private buildTitleActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'forward',
        symbol: $r('sys.symbol.chevron_right'),
        enabled: this.canGoForward,
        onClick: () => {
          if (this.canGoForward) {
            this.webViewController.forward();
          }
        }
      },
      {
        id: 'refresh',
        symbol: $r('sys.symbol.arrow_clockwise'),
        onClick: () => {
          this.webViewController.refresh();
        }
      },
      {
        id: 'complete',
        label: '完成登录',
        symbol: $r('sys.symbol.checkmark'),
        onClick: () => {
          void this.handleLoginSuccess();
        }
      }
    ];
  }

  private async handleLoginSuccess(): Promise<void> {
    if (!this.pageParams || this.isCompletingLogin) {
      return;
    }
    this.isCompletingLogin = true;

    try {
      const sourceRecord = await this.dataManager.getComicSourceByName(this.pageParams.sourceName);
      if (sourceRecord) {
        const sourceId: number = Number(sourceRecord.id);
        await this.authManager.captureCookiesFromController(sourceId, this.webViewController);
        let cookieStr: string = await CookieManager.getInstance().getCookieString(sourceId);
      logger.info(TAG, `登录完成，Cookie 长度: ${cookieStr.length}`);

      if (cookieStr.length === 0) {
        const rawCookieStr: string = await this.webViewController.runJavaScript('document.cookie') as string;
        cookieStr = this.normalizeCookieString(rawCookieStr);
        if (cookieStr.length > 0) {
          await this.authManager.loginWithCookieString(sourceId, this.webViewController, cookieStr);
          logger.warn(TAG, 'WebCookieManager抓取为空，已回退为document.cookie保存');
        }
      }
      } else {
        logger.warn(TAG, `完成登录时未找到图源记录: ${this.pageParams.sourceName}`);
      }
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `处理登录成功失败: ${String(error)}`);
    } finally {
      this.isCompletingLogin = false;
    }
  }

  private async performFormLogin(): Promise<void> {
    if (!this.pageParams) {
      return;
    }

    try {
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
      logger.info(TAG, '表单登录已执行');
    } catch (error) {
      logger.error(TAG, `表单登录失败: ${String(error)}`);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

        Column() {
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight));

          Column() {
            if (this.isLoading) {
              Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(2)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme));
            }

            Web({ src: 'about:blank', controller: this.webViewController })
              .width('100%')
              .layoutWeight(1)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .zoomAccess(true)
              .overviewModeAccess(true)
              .fileAccess(true)
              .mixedMode(MixedMode.All)
              .cacheMode(CacheMode.Default)
              .onControllerAttached(() => {
                this.webControllerAttached = true;
                this.applyCustomUserAgentIfNeeded();
                this.targetNavigationAttempted = false;
                this.scheduleNavigateToTarget('controllerAttached', 100);
              })
              .onPageBegin((event) => {
                this.applyCustomUserAgentIfNeeded();
                const beginUrl: string = event?.url ? event.url : '';
                if (beginUrl === this.loginTargetUrl && beginUrl.length > 0) {
                  this.targetNavigationPending = false;
                } else if ((beginUrl.length === 0 || beginUrl === 'about:blank') && this.targetNavigationPending) {
                  this.targetNavigationAttempted = false;
                  this.scheduleNavigateToTarget('pageBeginBlank', 140);
                }
                this.isLoading = true;
                this.loadProgress = 0;
                logger.debug(TAG, `页面开始加载: ${beginUrl}`);
              })
              .onPageEnd((event) => {
                const loadedUrl: string = event?.url ? event.url : '';
                this.isLoading = false;
                this.loadProgress = 100;
                this.canGoBack = this.webViewController.accessBackward();
                this.canGoForward = this.webViewController.accessForward();

                if (loadedUrl === this.loginTargetUrl && loadedUrl.length > 0) {
                  this.targetNavigationPending = false;
                } else if ((loadedUrl.length === 0 || loadedUrl === 'about:blank') && this.targetNavigationPending) {
                  this.targetNavigationAttempted = false;
                  this.scheduleNavigateToTarget('pageEndBlank', 180);
                } else if (loadedUrl.length > 0 && loadedUrl !== 'about:blank') {
                  this.targetNavigationPending = false;
                }

                if (this.currentLoginType === 'form' &&
                  !this.formLoginTriggered &&
                  loadedUrl.length > 0 &&
                  loadedUrl !== 'about:blank') {
                  this.formLoginTriggered = true;
                  void this.performFormLogin();
                }
                // 自动完成已禁用，避免旧Cookie导致误判登录成功
                logger.debug(TAG, `页面加载完成: ${loadedUrl}`);
              })
              .onProgressChange((event) => {
                this.loadProgress = event?.newProgress || 0;
              })
              .onTitleReceive((event) => {
                if (event?.title && event.title.length > 0) {
                  this.pageTitle = event.title;
                }
              })
              .onErrorReceive((event) => {
                logger.error(TAG, `页面加载错误: ${event?.error?.getErrorInfo()}`);
              });
          }
          .width('100%')
          .layoutWeight(1)
          .margin({
            left: this.getContentPanelMargin(),
            right: this.getContentPanelMargin(),
            bottom: this.isCopyMangaLoginFlow() ? 6 : 10
          })
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          })
          .shadow({
            radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 8
          });

          Row({ space: 10 }) {
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)]);
            }
              .width(44)
              .height(40)
              .enabled(this.canGoBack)
              .opacity(this.canGoBack ? 1 : 0.45)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (this.canGoBack) {
                  this.webViewController.backward();
                }
              });

            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)]);
            }
              .width(44)
              .height(40)
              .enabled(this.canGoForward)
              .opacity(this.canGoForward ? 1 : 0.45)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                if (this.canGoForward) {
                  this.webViewController.forward();
                }
              });

            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(20)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)]);
            }
              .width(44)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.webViewController.refresh();
              });

            Blank();

            Button('完成登录')
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .borderRadius(10)
              .padding({ left: 18, right: 18 })
              .onClick(() => {
                void this.handleLoginSuccess();
              });
          }
          .width('100%')
          .height(56)
          .margin({
            left: this.getContentPanelMargin(),
            right: this.getContentPanelMargin(),
            bottom: this.navigationBarHeight + this.getActionBarBottomInset()
          })
          .padding({ left: 10, right: 10 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
          .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
          .backgroundBlurStyle(
            SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
            SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
          )
          .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
          .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
          .clip(true)
          .border({
            width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
            color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
          })
          .shadow({
            radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
            color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
            offsetX: 0,
            offsetY: 8
          });
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.pageTitle,
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack,
          actions: this.buildTitleActions()
        });
      }
      .width('100%')
      .height('100%');
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as SourceLoginPageParams;
      if (params && params.sourceName && params.loginUrl) {
        logger.info(TAG, `onReady获取到参数: sourceName=${params.sourceName}, loginType=${params.loginType}, loginUrl=${params.loginUrl}`);
        this.applyLoginParams(params);
      } else {
        logger.error(TAG, 'onReady 未获取到有效参数');
      }
    })
    .backgroundColor(Color.Transparent);
  }
}
