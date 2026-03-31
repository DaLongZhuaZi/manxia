/**
 * AniList 登录页面
 * 使用 WebView 进行 OAuth2 授权
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { getAniListTracker, AniListTracker } from '../../Framework/Tracking/trackers/AniListTracker';
import { SettingsGlassStyleHelper } from './SettingsGlassStyleHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'AniListLoginPage';
const TITLE_BAR_HEIGHT: number = 56;

// AniList OAuth 配置
// 注意：需要在 https://anilist.co/settings/developer 注册应用获取 Client ID
// 创建应用时，Redirect URI 设置为: urn:ietf:wg:oauth:2.0:oob (用于移动端)
// 或者使用自定义 scheme: manxia://anilist/callback
const ANILIST_CLIENT_ID = '34461'; // ManXia 应用的 Client ID
const ANILIST_AUTH_URL = 'https://anilist.co/api/v2/oauth/authorize';

@Component
export struct AniListLoginPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State loginSuccess: boolean = false;
  @State showTokenInput: boolean = false;
  @State manualToken: string = '';

  private webController: webview.WebviewController = new webview.WebviewController();
  private aniListTracker: AniListTracker = getAniListTracker();
  private componentId: string = 'AniListLoginPage';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private getAuthUrl(): string {
    const params: string[] = [
      `client_id=${ANILIST_CLIENT_ID}`,
      `response_type=token`
    ];
    return `${ANILIST_AUTH_URL}?${params.join('&')}`;
  }

  private async handleAuthCallback(url: string): Promise<void> {
    logger.info(TAG, `处理授权回调: ${url}`);

    // AniList 使用 implicit grant，token 在 URL fragment 中
    // 格式: manxia://anilist/callback#access_token=xxx&token_type=Bearer&expires_in=xxx
    if (url.includes('#access_token=')) {
      const fragment = url.split('#')[1];
      const params = new Map<string, string>();
      
      const pairs = fragment.split('&');
      for (let i = 0; i < pairs.length; i++) {
        const pair = pairs[i].split('=');
        if (pair.length === 2) {
          params.set(pair[0], decodeURIComponent(pair[1]));
        }
      }

      const accessToken = params.get('access_token');
      const expiresIn = params.get('expires_in');

      if (accessToken) {
        // 直接使用 access token 完成登录
        const success = await this.aniListTracker.handleImplicitAuthCallback(accessToken, expiresIn ? parseInt(expiresIn) : 0);
        
        if (success) {
          this.loginSuccess = true;
          this.showSuccessToast();
          // 延迟返回
          setTimeout(() => {
            this.pathStack.pop();
          }, 1500);
        } else {
          this.errorMessage = '登录失败，请重试';
        }
      } else {
        this.errorMessage = '未获取到访问令牌';
      }
    } else if (url.includes('error=')) {
      // 处理错误
      const errorMatch = url.match(/error=([^&]+)/);
      const errorDesc = url.match(/error_description=([^&]+)/);
      this.errorMessage = errorDesc ? decodeURIComponent(errorDesc[1]) : (errorMatch ? errorMatch[1] : '授权失败');
    }
  }

  private showSuccessToast(): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
        message: `登录成功: ${this.aniListTracker.getAuthState().username}`,
        duration: 2000
      });
    });
  }

  private async handleManualToken(): Promise<void> {
    if (!this.manualToken) {
      this.errorMessage = '请输入 Token';
      return;
    }

    this.isLoading = true;
    try {
      const success = await this.aniListTracker.handleImplicitAuthCallback(this.manualToken.trim(), 31536000); // 1年有效期
      
      if (success) {
        this.loginSuccess = true;
        this.showTokenInput = false;
        this.showSuccessToast();
        setTimeout(() => {
          this.pathStack.pop();
        }, 1500);
      } else {
        this.errorMessage = 'Token 无效或已过期，请重新获取';
        this.showTokenInput = false;
      }
    } catch (error) {
      this.errorMessage = `登录失败: ${String(error)}`;
      this.showTokenInput = false;
    } finally {
      this.isLoading = false;
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
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          if (this.errorMessage) {
            // 错误提示
            Column({ space: 16 }) {
              Image($r('sys.symbol.exclamationmark_triangle'))
                .width(48)
                .height(48)
                .fillColor('#FF6B6B')

              Text(this.errorMessage)
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)

              Button('重试')
                .onClick(() => {
                  this.errorMessage = '';
                  this.webController.loadUrl(this.getAuthUrl());
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          } else if (this.loginSuccess) {
            // 登录成功
            Column({ space: 16 }) {
              Image($r('sys.symbol.checkmark_circle'))
                .width(64)
                .height(64)
                .fillColor('#10B981')

              Text('登录成功！')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Text(this.aniListTracker.getAuthState().username)
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          } else if (this.showTokenInput) {
            // 手动输入 Token（用于 oob 授权方式）
            Column({ space: 16 }) {
              Text('请从 AniList 页面复制 Token')
                .fontSize(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)

              Text('在 AniList 授权页面登录后，会显示一个 Token，请复制并粘贴到下方')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .textAlign(TextAlign.Center)
                .padding({ left: 20, right: 20 })

              TextInput({ placeholder: '粘贴 Access Token', text: this.manualToken })
                .width('90%')
                .height(48)
                .onChange((value: string) => {
                  this.manualToken = value;
                })

              Row({ space: 12 }) {
                Button('返回 WebView')
                  .onClick(() => {
                    this.showTokenInput = false;
                  })
                  .backgroundColor('#666666')

                Button('确认登录')
                  .onClick(() => {
                    this.handleManualToken();
                  })
                  .enabled(this.manualToken.length > 0)
              }
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          } else {
            // WebView 登录
            Web({ src: this.getAuthUrl(), controller: this.webController })
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
              })
              .onLoadIntercept((event) => {
                const request = event.data;
                const url = typeof request === 'string' ? request : request.getRequestUrl();
                logger.debug(TAG, `URL 拦截: ${url}`);
                
                // 检查是否是回调 URL 或包含 token
                if (url.startsWith('manxia://') || url.includes('#access_token=')) {
                  this.handleAuthCallback(url);
                  return true; // 拦截
                }
                // 检查是否是 oob 页面（用户需要手动复制 token）
                if (url.includes('anilist.co/api/v2/oauth/pin')) {
                  this.showTokenInput = true;
                }
                return false;
              })
              .onErrorReceive((event) => {
                const request = event.request;
                const error = event.error;
                const url = request.getRequestUrl();
                
                // 如果是回调 URL 的错误，忽略（因为 manxia:// 协议不被 WebView 支持）
                if (url.startsWith('manxia://')) {
                  this.handleAuthCallback(url);
                  return;
                }
                
                logger.error(TAG, `WebView 错误: ${error.getErrorInfo()}`);
              })
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 加载指示器
        if (this.isLoading && !this.errorMessage && !this.loginSuccess) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#80000000')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: 'AniList 登录',
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
