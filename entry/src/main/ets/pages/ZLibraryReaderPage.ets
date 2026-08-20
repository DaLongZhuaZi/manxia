/**
 * ZLibrary在线阅读器页面
 * 通过WebView打开ZLibrary的在线阅读器
 * 不支持进度记录
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { WindowManager, DisplayMode } from 'manxia_theme/src/main/ets/Utils/WindowManager';

const TAG = 'ZLibraryReaderPage';

export interface ZLibraryReaderParams {
  readerUrl: string;
  bookTitle: string;
  sourceId?: string;
}

@Component
export struct ZLibraryReaderPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State isLoading: boolean = true;
  @State loadProgress: number = 0;
  @State errorMessage: string = '';
  @State readerUrl: string = '';
  @State bookTitle: string = '';
  @State sourceId: string = '';
  @State showControls: boolean = false;

  private webViewController: webview.WebviewController = new webview.WebviewController();
  private componentId: string = `zlibrary_reader_${Date.now()}`;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.debug(TAG, `主题切换: ${theme}`);
    });
    
    this.getUIContext().getPromptAction().showToast({
      message: 'ZLibrary在线阅读不支持进度记录',
      duration: 3000
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    this.exitFullScreen();
  }

  private enterFullScreen(): void {
    try {
      const uiContext = this.getUIContext();
      const currentMode = WindowManager.getCurrentMode();
      if (currentMode !== DisplayMode.IMMERSIVE_WITH_BARS) {
        this.previousDisplayMode = currentMode;
      }
      WindowManager.setDisplayModeWithTransition(DisplayMode.IMMERSIVE_WITH_BARS, uiContext);
    } catch (e) {
      logger.warn(TAG, `进入全屏失败: ${e}`);
    }
  }

  private exitFullScreen(): void {
    try {
      if (WindowManager.getCurrentMode() !== this.previousDisplayMode) {
        WindowManager.setDisplayMode(this.previousDisplayMode, this.getUIContext());
      }
    } catch (e) {
      logger.warn(TAG, `退出全屏失败: ${e}`);
    }
  }

  private goBack(): void {
    if (this.pathStack.size() > 0) {
      this.pathStack.pop();
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column() {
          if (this.isLoading) {
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              
              Text(`加载中... ${this.loadProgress}%`)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 12 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }

          Web({ src: this.readerUrl, controller: this.webViewController })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .imageAccess(true)
            .mixedMode(MixedMode.All)
            .cacheMode(CacheMode.Default)
            .onControllerAttached(() => {
              this.webViewController.setCustomUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            })
            
            .onProgressChange((event) => {
              if (event && event.newProgress !== undefined) {
                this.loadProgress = event.newProgress;
                if (event.newProgress >= 100) {
                  this.isLoading = false;
                }
              }
            })
            .onPageEnd(() => {
              this.isLoading = false;
              logger.info(TAG, `页面加载完成: ${this.readerUrl}`);
            })
            .onErrorReceive((event) => {
              if (event && event.error) {
                const errorInfo = event.error.getErrorInfo();
                const errorCode = event.error.getErrorCode();
                // 只对严重错误显示错误信息（404、403、502、连接重置、访问拒绝等）
                const criticalErrors = ['404', '403', '502', '503', 'ERR_CONNECTION_RESET', 'ERR_ACCESS_DENIED', 'ERR_NAME_NOT_RESOLVED'];
                const isCritical = criticalErrors.some((code: string) => errorInfo.includes(code) || String(errorCode).includes(code));
                if (isCritical) {
                  this.errorMessage = `加载失败: ${errorInfo}`;
                  logger.error(TAG, this.errorMessage);
                } else {
                  // 非严重错误只记录日志，不显示错误界面
                  logger.warn(TAG, `非严重错误（已忽略）: ${errorInfo}`);
                }
              }
            })
            .onClick(() => {
              this.showControls = !this.showControls;
            })
            .opacity(this.isLoading ? 0 : 1)
        }
        .width('100%')
        .height('100%')

        if (this.showControls) {
          Column() {
            Row() {
              Button() {
                Image($r('app.media.ic_back'))
                  .width(24)
                  .height(24)
                  .fillColor(Color.White)
              }
              .width(44)
              .height(44)
              .backgroundColor('rgba(0, 0, 0, 0.5)')
              .borderRadius(22)
              .onClick(() => this.goBack())

              Text(this.bookTitle)
                .fontSize(16)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .margin({ left: 12, right: 12 })
                .textAlign(TextAlign.Center)

              Button() {
                Image($r('app.media.ic_refresh'))
                  .width(24)
                  .height(24)
                  .fillColor(Color.White)
              }
              .width(44)
              .height(44)
              .backgroundColor('rgba(0, 0, 0, 0.5)')
              .borderRadius(22)
              .onClick(() => {
                this.isLoading = true;
                this.webViewController.refresh();
              })
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: ReaderSafeAreaUtils.getStatusBarInset(this.statusBarHeight) + 24
            })
            .justifyContent(FlexAlign.SpaceBetween)

            Blank()
          }
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.3)')
          .onClick(() => {
            this.showControls = false;
          })
        }

        if (this.errorMessage) {
          Column() {
            Text('加载失败')
              .fontSize(18)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .margin({ bottom: 8 })
            
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ bottom: 16 })
            
            Button('重试')
              .onClick(() => {
                this.errorMessage = '';
                this.isLoading = true;
                this.webViewController.refresh();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo?.param as ZLibraryReaderParams;
      if (params) {
        this.readerUrl = params.readerUrl || '';
        this.bookTitle = params.bookTitle || '在线阅读';
        this.sourceId = params.sourceId || '';
        logger.info(TAG, `打开在线阅读器: ${this.bookTitle}, URL: ${this.readerUrl}`);
      }
    })
    .onShown(() => {
      this.enterFullScreen();
    })
    .backgroundColor(Color.Black)
  }
}
