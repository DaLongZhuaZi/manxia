/**
 * 漫画快速设置面板
 * 提供阅读模式和阅读方向的快速切换
 * 支持横屏/竖屏自适应布局
 */

import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { 
  ReadingMode, 
  ReadingDirection,
  ReadingSettings,
  DoublePagePortraitLayout
} from '../Models/MangaModels';
import { curves, UIContext, display } from '@kit.ArkUI';
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
  @State private panelTranslateX: number = 0;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;
  @State private screenWidth: number = 360;
  @State private screenHeight: number = 640;

  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    
    // 初始化屏幕方向检测
    this.detectScreenOrientation();
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaQuickSettings', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 播放入场动画
    setTimeout(() => {
      this.showPanel();
    }, 50);
  }
  
  /**
   * 检测屏幕方向
   */
  private detectScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (displayInfo) {
        this.screenWidth = displayInfo.width / (displayInfo.densityPixels || 1);
        this.screenHeight = displayInfo.height / (displayInfo.densityPixels || 1);
        this.isLandscape = this.screenWidth > this.screenHeight;
        logger.info(TAG, `屏幕方向检测: ${this.isLandscape ? '横屏' : '竖屏'}, ${this.screenWidth}x${this.screenHeight}`);
      }
    } catch (error) {
      logger.error(TAG, `屏幕方向检测失败: ${String(error)}`);
    }
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
   * 创建新设置对象（复制当前设置）
   */
  private createNewSettings(): ReadingSettings {
    return {
      readingMode: this.readingSettings.readingMode,
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
      doublePagePortraitLayout: this.readingSettings.doublePagePortraitLayout,
      filterSettings: this.readingSettings.filterSettings,
      volumeKeyNavigation: this.readingSettings.volumeKeyNavigation,
      curlBackOpacity: this.readingSettings.curlBackOpacity,
      webtoonLeftMargin: this.readingSettings.webtoonLeftMargin ?? 0,
      webtoonRightMargin: this.readingSettings.webtoonRightMargin ?? 0,
      webtoonMarginSync: this.readingSettings.webtoonMarginSync ?? true
    };
  }

  /**
   * 更新阅读模式
   */
  private updateReadingMode(mode: ReadingMode): void {
    const newSettings = this.createNewSettings();
    newSettings.readingMode = mode;
    
    // 如果切换到双页模式且当前方向是TTB，则自动切换到LTR
    if (mode === ReadingMode.DOUBLE_PAGE && newSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      logger.info(TAG, `切换到双页模式，自动将阅读方向从TTB改为LTR`);
      newSettings.readingDirection = ReadingDirection.LEFT_TO_RIGHT;
    }
    
    // 如果切换到条漫模式，自动切换到TTB
    if (mode === ReadingMode.WEBTOON && newSettings.readingDirection !== ReadingDirection.TOP_TO_BOTTOM) {
      logger.info(TAG, `切换到条漫模式，自动将阅读方向调整为TTB`);
      newSettings.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新阅读方向
   */
  private updateReadingDirection(direction: ReadingDirection): void {
    const newSettings = this.createNewSettings();
    newSettings.readingDirection = direction;
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新双页竖屏组合方式
   */
  private updateDoublePagePortraitLayout(layout: DoublePagePortraitLayout): void {
    const newSettings = this.createNewSettings();
    newSettings.doublePagePortraitLayout = layout;
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新音量键翻页设置
   */
  private updateVolumeKeyNavigation(enabled: boolean): void {
    const newSettings = this.createNewSettings();
    newSettings.volumeKeyNavigation = enabled;
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新条漫左边距
   */
  private updateWebtoonLeftMargin(value: number): void {
    const newSettings = this.createNewSettings();
    newSettings.webtoonLeftMargin = value;
    
    // 如果同步调整开启，同时更新右边距
    if (newSettings.webtoonMarginSync) {
      newSettings.webtoonRightMargin = value;
    }
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新条漫右边距
   */
  private updateWebtoonRightMargin(value: number): void {
    const newSettings = this.createNewSettings();
    newSettings.webtoonRightMargin = value;
    
    // 如果同步调整开启，同时更新左边距
    if (newSettings.webtoonMarginSync) {
      newSettings.webtoonLeftMargin = value;
    }
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 更新条漫边距同步设置
   */
  private updateWebtoonMarginSync(enabled: boolean): void {
    const newSettings = this.createNewSettings();
    newSettings.webtoonMarginSync = enabled;
    
    // 如果开启同步，将右边距设置为与左边距相同
    if (enabled) {
      newSettings.webtoonRightMargin = newSettings.webtoonLeftMargin;
    }
    
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(newSettings);
    }
  }

  /**
   * 判断是否为条漫模式
   */
  private isWebtoonMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.WEBTOON ||
      this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  /**
   * 判断是否禁用从上到下阅读方向（双页模式下不支持）
   */
  private isTTBDisabled(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE;
  }

  /**
   * 判断是否禁用水平阅读方向（条漫模式下不支持）
   */
  private isHorizontalDirectionDisabled(): boolean {
    return this.readingSettings.readingMode === ReadingMode.WEBTOON;
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
   * 构建阅读模式选择器（参考MangaSettingsPage设计）
   */
  @Builder
  buildReadingModeSelector() {
    Column({ space: 8 }) {
      Text('阅读模式')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      // 第一行：单页、双页、连续滚动
      Row({ space: 8 }) {
        this.buildModeButton('单页', ReadingMode.SINGLE_PAGE)
        this.buildModeButton('双页', ReadingMode.DOUBLE_PAGE)
        this.buildModeButton('连续滚动', ReadingMode.CONTINUOUS_SCROLL)
      }
      .width('100%')

      // 第二行：条漫
      Row({ space: 8 }) {
        this.buildModeButton('条漫', ReadingMode.WEBTOON)
        Column().layoutWeight(1)
        Column().layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建阅读方向选择器
   */
  @Builder
  buildReadingDirectionSelector() {
    Column({ space: 8 }) {
      Row() {
        Text('阅读方向')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        if (this.isTTBDisabled()) {
          Text('双页模式不支持从上到下')
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        if (this.isHorizontalDirectionDisabled()) {
          Text('条漫模式仅支持从上到下')
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        this.buildDirectionButton('从上到下', ReadingDirection.TOP_TO_BOTTOM, this.isTTBDisabled())
        this.buildDirectionButton('从左到右', ReadingDirection.LEFT_TO_RIGHT, this.isHorizontalDirectionDisabled())
        this.buildDirectionButton('从右到左', ReadingDirection.RIGHT_TO_LEFT, this.isHorizontalDirectionDisabled())
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建双页竖屏组合选择器
   */
  @Builder
  buildDoublePageLayoutSelector() {
    Column({ space: 8 }) {
      Text('双页竖屏组合')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        Column() {
          Text('上下组合')
            .fontSize(12)
            .fontColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
          Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.VERTICAL))

        Column() {
          Text('左右组合')
            .fontSize(12)
            .fontColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .padding(10)
        .backgroundColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
          Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.HORIZONTAL))
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建音量键翻页开关
   */
  @Builder
  buildVolumeKeyToggle() {
    Row() {
      Text('音量键翻页')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
      
      Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.volumeKeyNavigation })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.updateVolumeKeyNavigation(isOn);
        })
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建条漫边距调整（竖屏版本）
   */
  @Builder
  buildWebtoonMarginSelector() {
    Column({ space: 8 }) {
      Text('边距调整')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      // 同步调整开关
      Row() {
        Text('左右同步')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.webtoonMarginSync ?? true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.updateWebtoonMarginSync(isOn);
          })
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 左边距滑块
      Column({ space: 4 }) {
        Row() {
          Text('左边距')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${Math.round(this.readingSettings.webtoonLeftMargin ?? 0)}%`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.readingSettings.webtoonLeftMargin ?? 0,
          min: 0,
          max: 40,
          step: 1
        })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .onChange((value: number) => {
            this.updateWebtoonLeftMargin(value);
          })
      }
      .width('100%')

      // 右边距滑块（仅在非同步模式下显示）
      if (!(this.readingSettings.webtoonMarginSync ?? true)) {
        Column({ space: 4 }) {
          Row() {
            Text('右边距')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${Math.round(this.readingSettings.webtoonRightMargin ?? 0)}%`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Slider({
            value: this.readingSettings.webtoonRightMargin ?? 0,
            min: 0,
            max: 40,
            step: 1
          })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .onChange((value: number) => {
              this.updateWebtoonRightMargin(value);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ bottom: 16 })
  }

  /**
   * 构建模式按钮
   */
  @Builder
  buildModeButton(label: string, mode: ReadingMode) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.readingSettings.readingMode === mode ? 
          ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(this.readingSettings.readingMode === mode ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(8)
    .onClick(() => this.updateReadingMode(mode))
  }

  /**
   * 构建方向按钮
   */
  @Builder
  buildDirectionButton(label: string, direction: ReadingDirection, disabled: boolean) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(disabled ?
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
          (this.readingSettings.readingDirection === direction ? 
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : 
            ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)))
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(this.readingSettings.readingDirection === direction && !disabled ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(8)
    .opacity(disabled ? 0.5 : 1.0)
    .onClick(() => {
      if (!disabled) {
        this.updateReadingDirection(direction);
      }
    })
  }

  /**
   * 构建竖屏面板（从底部滑入）
   */
  @Builder
  buildPortraitPanel() {
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

      // 可滚动内容区域
      Scroll() {
        Column() {
          // 阅读模式选择
          this.buildReadingModeSelector()
          
          // 阅读方向选择
          this.buildReadingDirectionSelector()
          
          // 双页竖屏组合
          this.buildDoublePageLayoutSelector()
          
          // 条漫边距调整（仅在条漫模式下显示）
          if (this.isWebtoonMode()) {
            this.buildWebtoonMarginSelector()
          }
          
          // 音量键翻页
          this.buildVolumeKeyToggle()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部按钮
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
    .constraintSize({ maxHeight: '70%' })
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

  /**
   * 构建横屏面板（从右侧滑入，紧凑布局）
   */
  @Builder
  buildLandscapePanel() {
    Row() {
      // 左侧空白区域（点击关闭）
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.hidePanel())

      // 右侧设置面板
      Column() {
        // 面板标题
        Row() {
          Text('快捷设置')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.hidePanel())
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 可滚动内容
        Scroll() {
          Column() {
            // 横屏模式：使用更紧凑的网格布局
            this.buildLandscapeModeSelector()
            
            // 阅读方向（紧凑版）
            this.buildLandscapeDirectionSelector()
            
            // 双页竖屏组合（紧凑版）
            this.buildLandscapeDoublePageLayout()
            
            // 条漫边距调整（仅在条漫模式下显示）
            if (this.isWebtoonMode()) {
              this.buildLandscapeWebtoonMarginSelector()
            }
            
            // 音量键翻页
            this.buildLandscapeVolumeKeyToggle()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 底部按钮
        Button('完成')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .width('100%')
          .height(36)
          .onClick(() => this.hidePanel())
      }
      .width(240)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .opacity(this.panelOpacity)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 构建横屏模式选择器（2x2网格布局）
   */
  @Builder
  buildLandscapeModeSelector() {
    Column() {
      Text('阅读模式')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ bottom: 6 })

      // 第一行
      Row({ space: 4 }) {
        this.buildCompactModeButton('单页', ReadingMode.SINGLE_PAGE)
        this.buildCompactModeButton('双页', ReadingMode.DOUBLE_PAGE)
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 第二行
      Row({ space: 4 }) {
        this.buildCompactModeButton('滚动', ReadingMode.CONTINUOUS_SCROLL)
        this.buildCompactModeButton('条漫', ReadingMode.WEBTOON)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /**
   * 构建横屏阅读方向选择器
   */
  @Builder
  buildLandscapeDirectionSelector() {
    Column() {
      Text('阅读方向')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        this.buildCompactDirectionButton('上→下', ReadingDirection.TOP_TO_BOTTOM, this.isTTBDisabled())
        this.buildCompactDirectionButton('左→右', ReadingDirection.LEFT_TO_RIGHT, this.isHorizontalDirectionDisabled())
        this.buildCompactDirectionButton('右→左', ReadingDirection.RIGHT_TO_LEFT, this.isHorizontalDirectionDisabled())
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /**
   * 构建横屏双页竖屏组合选择器
   */
  @Builder
  buildLandscapeDoublePageLayout() {
    Column() {
      Text('双页竖屏组合')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')
        .margin({ bottom: 6 })

      Row({ space: 4 }) {
        Column() {
          Text('上下')
            .fontSize(10)
            .fontColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL ?
              ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.VERTICAL))

        Column() {
          Text('左右')
            .fontSize(10)
            .fontColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ?
              ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.readingSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
        .borderRadius(6)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.HORIZONTAL))
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /**
   * 构建横屏音量键翻页开关
   */
  @Builder
  buildLandscapeVolumeKeyToggle() {
    Row() {
      Text('音量键翻页')
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
      
      Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.volumeKeyNavigation })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.updateVolumeKeyNavigation(isOn);
        })
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /**
   * 构建横屏条漫边距调整
   */
  @Builder
  buildLandscapeWebtoonMarginSelector() {
    Column({ space: 6 }) {
      Row() {
        Text('边距调整')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Text('同步')
          .fontSize(10)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ right: 4 })
        
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.webtoonMarginSync ?? true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.updateWebtoonMarginSync(isOn);
          })
      }
      .width('100%')

      // 左边距
      Row() {
        Text('左')
          .fontSize(10)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(20)
        
        Slider({
          value: this.readingSettings.webtoonLeftMargin ?? 0,
          min: 0,
          max: 40,
          step: 1
        })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .layoutWeight(1)
          .onChange((value: number) => {
            this.updateWebtoonLeftMargin(value);
          })
        
        Text(`${Math.round(this.readingSettings.webtoonLeftMargin ?? 0)}%`)
          .fontSize(10)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .width(30)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 右边距（仅在非同步模式下显示）
      if (!(this.readingSettings.webtoonMarginSync ?? true)) {
        Row() {
          Text('右')
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width(20)
          
          Slider({
            value: this.readingSettings.webtoonRightMargin ?? 0,
            min: 0,
            max: 40,
            step: 1
          })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .layoutWeight(1)
            .onChange((value: number) => {
              this.updateWebtoonRightMargin(value);
            })
          
          Text(`${Math.round(this.readingSettings.webtoonRightMargin ?? 0)}%`)
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .width(30)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(6)
    .margin({ bottom: 12 })
  }

  /**
   * 构建紧凑模式按钮（横屏用）
   */
  @Builder
  buildCompactModeButton(label: string, mode: ReadingMode) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontColor(this.readingSettings.readingMode === mode ? 
          ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(this.readingSettings.readingMode === mode ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(6)
    .onClick(() => this.updateReadingMode(mode))
  }

  /**
   * 构建紧凑方向按钮（横屏用）
   */
  @Builder
  buildCompactDirectionButton(label: string, direction: ReadingDirection, disabled: boolean) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontColor(disabled ?
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
          (this.readingSettings.readingDirection === direction ? 
            ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme) : 
            ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)))
    }
    .layoutWeight(1)
    .padding(8)
    .backgroundColor(this.readingSettings.readingDirection === direction && !disabled ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
    .borderRadius(6)
    .opacity(disabled ? 0.5 : 1.0)
    .onClick(() => {
      if (!disabled) {
        this.updateReadingDirection(direction);
      }
    })
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

        // 快速设置面板 - 横屏/竖屏自适应
        if (this.isLandscape) {
          // 横屏布局：从右侧滑入，宽度较窄
          this.buildLandscapePanel()
        } else {
          // 竖屏布局：从底部滑入
          this.buildPortraitPanel()
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth > 0 && newHeight > 0) {
          const wasLandscape = this.isLandscape;
          this.isLandscape = newWidth > newHeight;
          this.screenWidth = newWidth;
          this.screenHeight = newHeight;
          if (wasLandscape !== this.isLandscape) {
            logger.info(TAG, `屏幕方向变化: ${this.isLandscape ? '横屏' : '竖屏'}`);
          }
        }
      })
      .position({ x: 0, y: 0 })
    }
  }
}

