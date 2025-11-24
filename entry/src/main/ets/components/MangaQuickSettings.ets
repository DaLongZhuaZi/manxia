/**
 * 漫画快速设置面板
 * 提供阅读模式和阅读方向的快速切换
 */

import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { 
  ReadingMode, 
  ReadingDirection,
  ReadingSettings
} from '../Models/MangaModels';
import { curves, UIContext } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'MangaQuickSettings';

interface AnimateParam {
  duration: number;
  curve: Curve;
}

// 定义事件回调接口
interface MangaQuickSettingsCallbacks {
  onSettingsChange: (settings: ReadingSettings) => void;
  onClose: () => void;
  onOpenFullSettings: () => void;
}

@Component
export struct MangaQuickSettings {
  @Prop readingSettings: ReadingSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: MangaQuickSettingsCallbacks;

  // 内部状态
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 200;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();

  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaQuickSettings', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 播放入场动画
    setTimeout(() => {
      this.showPanel();
    }, 50);
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware('MangaQuickSettings');
  }

  /**
   * 显示面板
   */
  private showPanel(): void {
    if (!this.uiContext) {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.backdropOpacity = 0.5;
      return;
    }
    
    this.uiContext.animateTo({
      duration: 300,
      curve: curves.initCurve(Curve.EaseOut)
    }, () => {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.backdropOpacity = 0.5;
    });
  }

  /**
   * 隐藏面板
   */
  private hidePanel(): void {
    // 立即通知父组件关闭
    if (this.callbacks.onClose) {
      this.callbacks.onClose();
    }
    
    // 播放淡出动画
    if (this.uiContext) {
      this.uiContext.animateTo({
        duration: 250,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.panelOpacity = 0;
        this.panelTranslateY = 200;
        this.backdropOpacity = 0;
      });
    }
  }

  /**
   * 更新阅读模式
   */
  private updateReadingMode(mode: ReadingMode): void {
    const newSettings: ReadingSettings = {
      readingMode: mode,
      readingDirection: this.readingSettings.readingDirection,
      brightness: this.readingSettings.brightness,
      keepScreenOn: this.readingSettings.keepScreenOn,
      pageSpacing: this.readingSettings.pageSpacing,
      showPageInfo: this.readingSettings.showPageInfo,
      showPageIndicator: this.readingSettings.showPageIndicator,
      fitMode: this.readingSettings.fitMode,
      autoPageTurnInterval: this.readingSettings.autoPageTurnInterval,
      skipIntroPages: this.readingSettings.skipIntroPages,
      pageTurnAnimation: this.readingSettings.pageTurnAnimation,
      filterSettings: this.readingSettings.filterSettings,
      volumeKeyNavigation: this.readingSettings.volumeKeyNavigation
    };
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新阅读方向
   */
  private updateReadingDirection(direction: ReadingDirection): void {
    const newSettings: ReadingSettings = {
      readingMode: this.readingSettings.readingMode,
      readingDirection: direction,
      brightness: this.readingSettings.brightness,
      keepScreenOn: this.readingSettings.keepScreenOn,
      pageSpacing: this.readingSettings.pageSpacing,
      showPageInfo: this.readingSettings.showPageInfo,
      showPageIndicator: this.readingSettings.showPageIndicator,
      fitMode: this.readingSettings.fitMode,
      autoPageTurnInterval: this.readingSettings.autoPageTurnInterval,
      skipIntroPages: this.readingSettings.skipIntroPages,
      pageTurnAnimation: this.readingSettings.pageTurnAnimation,
      filterSettings: this.readingSettings.filterSettings,
      volumeKeyNavigation: this.readingSettings.volumeKeyNavigation
    };
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 打开完整设置
   */
  private openFullSettings(): void {
    if (this.callbacks.onOpenFullSettings) {
      this.callbacks.onOpenFullSettings();
    }
  }

  /**
   * 构建阅读模式选择器
   */
  @Builder
  buildReadingModeSelector() {
    Column() {
      Text('阅读模式')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        // 左→右
        this.buildModeButton('左→右', ReadingMode.SINGLE_PAGE, $r('app.media.ic_ltr'))
        
        // 右→左
        this.buildModeButton('右→左', ReadingMode.SINGLE_PAGE_RTL, $r('app.media.ic_rtl'))
        
        // 上→下
        this.buildModeButton('上→下', ReadingMode.SINGLE_PAGE_TTB, $r('app.media.ic_vertical'))
        
        // 条漫
        this.buildModeButton('条漫', ReadingMode.WEBTOON, $r('app.media.ic_continuous'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建模式按钮
   */
  @Builder
  buildModeButton(label: string, mode: ReadingMode, icon: Resource) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.readingSettings.readingMode === mode ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      Text(label)
        .fontSize(10)
        .fontColor(this.readingSettings.readingMode === mode ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(this.readingSettings.readingMode === mode ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : 
      Color.Transparent)
    .borderRadius(8)
    .onClick(() => this.updateReadingMode(mode))
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 背景遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.hidePanel();
          })

        // 快速设置面板
        Column() {
          // 面板标题
          Row() {
            Text('阅读模式快捷设置')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)

            Button() {
              Image($r('app.media.ic_close'))
                .width(20)
                .height(20)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.hidePanel())
          }
          .width('100%')
          .margin({ bottom: 16 })

          // 阅读模式选择
          this.buildReadingModeSelector()

          // 底部按钮（仅保留完成）
          Row() {
            Button('完成')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .height(40)
              .onClick(() => this.hidePanel())
          }
          .width('100%')
        }
        .width('100%')
        .padding(20)
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius({ topLeft: 16, topRight: 16 })
        .opacity(this.panelOpacity)
        .translate({ x: 0, y: this.panelTranslateY })
        .position({ x: 0, y: '100%' })
        .translate({ x: 0, y: '-100%' })
        .hitTestBehavior(HitTestMode.Default)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}

