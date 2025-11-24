// 文件路径: src/main/ets/components/MangaReaderSettings.ets
/**
 * 漫画阅读器设置面板组件
 * 提供阅读模式、阅读方向、亮度调节、滤镜效果、页面间距等配置选项
 */

import { logger } from '../Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { 
  GlobalAnimationManager, 
  AnimationType, 
  AnimationUtils,
  globalAnimationManager 
} from '../Framework/Animation/GlobalAnimationSystem';
import { 
  ReadingMode, 
  ReadingDirection,
  ReadingSettings,
  FilterSettings,
  PageTurnAnimationType,
  DEFAULT_READING_SETTINGS,
  DEFAULT_FILTER_SETTINGS
} from '../Models/MangaModels';
import { curves, UIContext } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'MangaReaderSettings';

/**
 * 设置面板参数接口
 */
export interface MangaReaderSettingsParams {
  /** 当前阅读设置 */
  readingSettings: ReadingSettings;
  /** 是否显示设置面板 */
  isVisible: boolean;
  /** 设置变更回调 */
  onSettingsChange?: (settings: ReadingSettings) => void;
  /** 关闭面板回调 */
  onClose?: () => void;
}

// 定义事件回调接口
interface MangaReaderSettingsCallbacks {
  onSettingsChange: (settings: ReadingSettings) => void;
  onClose: () => void;
}

@Component
export struct MangaReaderSettings {
  @Prop readingSettings: ReadingSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: MangaReaderSettingsCallbacks;

  // 内部状态
  @State private currentSettings: ReadingSettings = {
    readingMode: DEFAULT_READING_SETTINGS.readingMode,
    readingDirection: DEFAULT_READING_SETTINGS.readingDirection,
    brightness: DEFAULT_READING_SETTINGS.brightness,
    keepScreenOn: DEFAULT_READING_SETTINGS.keepScreenOn,
    pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
    showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
    showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
    fitMode: DEFAULT_READING_SETTINGS.fitMode,
    autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
    skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
    pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
    filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
    volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation
  };
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();

  // 动画系统
  private animationManager: GlobalAnimationManager = globalAnimationManager;
  private animationId: string = '';
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    // 获取UI上下文
    this.animationId = AnimationUtils.generateAnimationId();
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
    }
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaReaderSettings', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `MangaReaderSettings 主题切换: ${theme}`);
    });
    
    // 复制阅读设置
    this.currentSettings.readingMode = this.readingSettings.readingMode;
    this.currentSettings.readingDirection = this.readingSettings.readingDirection;
    this.currentSettings.brightness = this.readingSettings.brightness;
    this.currentSettings.keepScreenOn = this.readingSettings.keepScreenOn;
    this.currentSettings.pageSpacing = this.readingSettings.pageSpacing;
    this.currentSettings.showPageInfo = this.readingSettings.showPageInfo;
    this.currentSettings.showPageIndicator = this.readingSettings.showPageIndicator;
    this.currentSettings.fitMode = this.readingSettings.fitMode;
    this.currentSettings.autoPageTurnInterval = this.readingSettings.autoPageTurnInterval;
    this.currentSettings.filterSettings = this.readingSettings.filterSettings;
    this.currentSettings.volumeKeyNavigation = this.readingSettings.volumeKeyNavigation;
    
    // 延迟执行动画，确保组件完全渲染后再播放
    if (this.isVisible) {
      setTimeout(() => {
        this.showPanel();
      }, 50);
    }
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware('MangaReaderSettings');
  }

  onPageShow() {
    if (this.isVisible) {
      this.showPanel();
    }
  }

  /**
   * 显示设置面板
   */
  private showPanel(): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

    const fadeInOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeInOptions, () => {
      this.backdropOpacity = 0.5;
    });

    const slideInOptions: AnimateParam = { 
      duration: 300, 
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(slideInOptions, () => {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
    });
  }

  /**
   * 隐藏设置面板
   */
  private hidePanel(): void {
    // 立即通知父组件关闭，停止接收事件
    if (this.callbacks.onClose) {
      this.callbacks.onClose();
    }
    
    // 播放淡出动画（仅用于视觉效果）
    if (this.uiContext) {
    const slideOutOptions: AnimateParam = { 
      duration: 300, 
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(slideOutOptions, () => {
      this.panelOpacity = 0;
      this.panelTranslateY = 300;
    });

    const fadeOutOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeOutOptions, () => {
      this.backdropOpacity = 0;
    });
    }
  }

  /**
   * 应用设置
   */
  private applySettings(): void {
    logger.info(TAG, '应用阅读设置');
    if (this.callbacks.onSettingsChange) {
          this.callbacks.onSettingsChange(this.currentSettings);
        }
    
    // 立即通知父组件关闭
      if (this.callbacks.onClose) {
          this.callbacks.onClose();
        }
  }

  /**
   * 重置为默认设置
   */
  private resetToDefaults(): void {
    this.currentSettings = {
      readingMode: DEFAULT_READING_SETTINGS.readingMode,
      readingDirection: DEFAULT_READING_SETTINGS.readingDirection,
      brightness: DEFAULT_READING_SETTINGS.brightness,
      pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
      keepScreenOn: DEFAULT_READING_SETTINGS.keepScreenOn,
      showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation
    };
    this.applySettings();
  }

  /**
   * 更新阅读模式（立即应用）
   */
  private updateReadingMode(mode: ReadingMode): void {
    this.currentSettings.readingMode = mode;
    // 立即通知父组件应用设置，但不关闭面板
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
    logger.info(TAG, `阅读模式已更新: ${mode}`);
  }

  /**
   * 更新阅读方向（立即应用）
   */
  private updateReadingDirection(direction: ReadingDirection): void {
    this.currentSettings.readingDirection = direction;
    // 立即通知父组件应用设置，但不关闭面板
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
    logger.info(TAG, `阅读方向已更新: ${direction}`);
  }

  /**
   * 更新亮度（实时预览）
   */
  private updateBrightness(brightness: number): void {
    this.currentSettings.brightness = Math.max(0.1, Math.min(2.0, brightness));
    // 实时通知父组件应用亮度变化
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }

  /**
   * 更新页面间距（实时预览）
   */
  private updatePageSpacing(spacing: number): void {
    this.currentSettings.pageSpacing = Math.max(0, Math.min(50, spacing));
    // 实时通知父组件应用间距变化
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }
  
  /**
   * 更新自动翻页间隔（实时预览）
   */
  private updateAutoPageTurnInterval(interval: number): void {
    this.currentSettings.autoPageTurnInterval = Math.max(0, Math.min(10, interval));
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }
  
  /**
   * 更新跳过前情提要页数（实时预览）
   */
  private updateSkipIntroPages(pages: number): void {
    this.currentSettings.skipIntroPages = Math.max(0, Math.min(20, pages));
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }
  
  /**
   * 更新翻页动画类型（立即应用）
   */
  private updatePageTurnAnimation(animationType: PageTurnAnimationType): void {
    this.currentSettings.pageTurnAnimation = animationType;
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }

  /**
   * 切换设置项（立即应用）
   */
  private toggleSetting(key: keyof ReadingSettings): void {
    // 使用显式属性访问替代索引访问
    if (key === 'keepScreenOn') {
      this.currentSettings.keepScreenOn = !this.currentSettings.keepScreenOn;
    } else if (key === 'showPageInfo') {
      this.currentSettings.showPageInfo = !this.currentSettings.showPageInfo;
    } else if (key === 'showPageIndicator') {
      this.currentSettings.showPageIndicator = !this.currentSettings.showPageIndicator;
    } else if (key === 'volumeKeyNavigation') {
      this.currentSettings.volumeKeyNavigation = !this.currentSettings.volumeKeyNavigation;
    }
    // 立即通知父组件应用设置
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
    logger.info(TAG, `设置项已切换: ${key}`);
  }

  /**
   * 更新滤镜设置
   */
  private updateFilterSettings(key: keyof FilterSettings, value: number | boolean): void {
    const newFilterSettings: FilterSettings = {
      enabled: this.currentSettings.filterSettings.enabled,
      brightness: this.currentSettings.filterSettings.brightness,
      contrast: this.currentSettings.filterSettings.contrast,
      saturation: this.currentSettings.filterSettings.saturation,
      hue: this.currentSettings.filterSettings.hue,
      gamma: this.currentSettings.filterSettings.gamma,
      sepia: this.currentSettings.filterSettings.sepia,
      grayscale: this.currentSettings.filterSettings.grayscale,
      invert: this.currentSettings.filterSettings.invert,
      blur: this.currentSettings.filterSettings.blur
    };
    
    if (key === 'enabled') {
      newFilterSettings.enabled = value as boolean;
    } else if (key === 'brightness') {
      newFilterSettings.brightness = value as number;
    } else if (key === 'contrast') {
      newFilterSettings.contrast = value as number;
    } else if (key === 'saturation') {
      newFilterSettings.saturation = value as number;
    } else if (key === 'hue') {
      newFilterSettings.hue = value as number;
    } else if (key === 'gamma') {
      newFilterSettings.gamma = value as number;
    } else if (key === 'sepia') {
      newFilterSettings.sepia = value as number;
    } else if (key === 'grayscale') {
      newFilterSettings.grayscale = value as boolean;
    } else if (key === 'invert') {
      newFilterSettings.invert = value as boolean;
    } else if (key === 'blur') {
      newFilterSettings.blur = value as number;
    }
    
    this.currentSettings.filterSettings = newFilterSettings;
  }

  /**
   * 构建章节标题
   */
  @Builder
  buildSectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .margin({ bottom: 16 })
  }

  /**
   * 构建阅读模式选择器（已移至快速设置，这里保留代码但不使用）
   */
  @Builder
  buildReadingModeSelector() {
    Column() {
      Text('阅读模式')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      // 第一行：单页模式
      Row() {
        // 单页模式（从左到右）
        Column() {
          Image($r('app.media.ic_single_page'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('左→右')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.SINGLE_PAGE_LTR))

        // 单页模式（从右到左）
        Column() {
          Image($r('app.media.ic_single_page'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('右→左')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.SINGLE_PAGE_RTL))

        // 单页模式（从上到下）
        Column() {
          Image($r('app.media.ic_single_page'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('上→下')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.SINGLE_PAGE_TTB))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 8 })

      // 第二行：其他模式
      Row() {
        // 双页模式
        Column() {
          Image($r('app.media.ic_double_page'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('双页')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.DOUBLE_PAGE))

        // 条漫模式
        Column() {
          Image($r('app.media.ic_continuous'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.WEBTOON ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('条漫')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.WEBTOON ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.WEBTOON ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.WEBTOON))

        // 条漫（有间隙）模式
        Column() {
          Image($r('app.media.ic_continuous'))
            .width(28)
            .height(28)
            .fillColor(this.currentSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('间隙')
            .fontSize(10)
            .fontColor(this.currentSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding(8)
        .backgroundColor(this.currentSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(6)
        .onClick(() => this.updateReadingMode(ReadingMode.WEBTOON_WITH_GAP))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建阅读方向选择器
   */
  @Builder
  buildReadingDirectionSelector() {
    Column() {
      Text('阅读方向')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        // 从左到右
        Column() {
          Image($r('app.media.ic_ltr'))
            .width(24)
            .height(24)
            .fillColor(this.currentSettings.readingDirection === ReadingDirection.LEFT_TO_RIGHT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('左→右')
            .fontSize(12)
            .fontColor(this.currentSettings.readingDirection === ReadingDirection.LEFT_TO_RIGHT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.readingDirection === ReadingDirection.LEFT_TO_RIGHT ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateReadingDirection(ReadingDirection.LEFT_TO_RIGHT))

        // 从右到左
        Column() {
          Image($r('app.media.ic_rtl'))
            .width(24)
            .height(24)
            .fillColor(this.currentSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('右→左')
            .fontSize(12)
            .fontColor(this.currentSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateReadingDirection(ReadingDirection.RIGHT_TO_LEFT))

        // 垂直
        Column() {
          Image($r('app.media.ic_vertical'))
            .width(24)
            .height(24)
            .fillColor(this.currentSettings.readingDirection === ReadingDirection.VERTICAL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('垂直')
            .fontSize(12)
            .fontColor(this.currentSettings.readingDirection === ReadingDirection.VERTICAL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.readingDirection === ReadingDirection.VERTICAL ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateReadingDirection(ReadingDirection.VERTICAL))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建亮度调节器
   */
  @Builder
  buildBrightnessControl() {
    Column() {
      Row() {
        Text('亮度')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${Math.round(this.currentSettings.brightness * 100)}%`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Row() {
        Image($r('app.media.ic_brightness_low'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_secondary'))

        Slider({
          value: this.currentSettings.brightness,
          min: 0.1,
          max: 2.0,
          step: 0.1
        })
          .layoutWeight(1)
          .margin({ left: 12, right: 12 })
          .trackColor($r('app.color.divider'))
          .selectedColor($r('app.color.accent'))
          .onChange((value: number) => this.updateBrightness(value))

        Image($r('app.media.ic_brightness_high'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建页面间距调节器
   */
  @Builder
  buildPageSpacingControl() {
    Column() {
      Row() {
        Text('页面间距')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${this.currentSettings.pageSpacing}px`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Slider({
        value: this.currentSettings.pageSpacing,
        min: 0,
        max: 50,
        step: 5
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => this.updatePageSpacing(value))
    }
    .width('100%')
    .margin({ bottom: 24 })
  }
  
  /**
   * 构建跳过前情提要设置
   */
  @Builder
  buildSkipIntroSettings() {
    Column() {
      Row() {
        Text('跳过前情提要')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(this.currentSettings.skipIntroPages > 0 
          ? `${this.currentSettings.skipIntroPages}页` 
          : '不跳过')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Slider({
        value: this.currentSettings.skipIntroPages,
        min: 0,
        max: 20,
        step: 1
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => this.updateSkipIntroPages(value))
    }
    .width('100%')
    .margin({ bottom: 24 })
  }
  
  /**
   * 构建翻页动画设置
   */
  @Builder
  buildPageTurnAnimationSettings() {
    Column() {
      Text('翻页动画')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      Row() {
        // 无动画
        Column() {
          Text('无')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.NONE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.NONE ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.NONE))

        // 滑动
        Column() {
          Text('滑动')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.SLIDE))

        // 淡入淡出
        Column() {
          Text('淡入淡出')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.FADE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.FADE ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.FADE))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ bottom: 8 })
      
      Row() {
        // 卷页
        Column() {
          Text('卷页')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.CURL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.CURL ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.CURL))

        // 缩放
        Column() {
          Text('缩放')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.ZOOM ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.ZOOM ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.ZOOM))

        // 翻转
        Column() {
          Text('翻转')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.FLIP ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.FLIP ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.FLIP))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建开关设置项
   */
  @Builder
  buildToggleSettings() {
    Column() {
      // 显示页面指示器
      Row() {
        Text('显示页面指示器')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.showPageIndicator })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.showPageIndicator = isOn;
            // 立即应用，但不关闭面板
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider()
        .color($r('app.color.divider'))

      // 保持屏幕常亮
      Row() {
        Text('保持屏幕常亮')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.keepScreenOn })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.keepScreenOn = isOn;
            // 立即应用，但不关闭面板
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider()
        .color($r('app.color.divider'))

      // 音量键翻页
      Row() {
        Text('音量键翻页')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.volumeKeyNavigation })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.volumeKeyNavigation = isOn;
            // 立即应用，但不关闭面板
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row() {
      // 重置按钮
      Button('重置')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.background_secondary'))
        .layoutWeight(1)
        .height(44)
        .onClick(() => this.resetToDefaults())

      Blank().width(12)

      // 关闭按钮
      Button('关闭')
        .fontSize(16)
        .fontColor($r('app.color.text_on_accent'))
        .backgroundColor($r('app.color.accent'))
        .layoutWeight(1)
        .height(44)
        .onClick(() => this.hidePanel())
    }
    .width('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 背景遮罩 - 拦截背景区域的点击
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.hidePanel();
          })

        // 设置面板 - 允许内部交互
        Column() {
          // 面板标题
          Row() {
            Column() {
              Text('自动功能设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              Text('滤镜、高级功能等详细配置')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

            Button() {
              Image($r('app.media.ic_close'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_secondary'))
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.hidePanel())
          }
          .width('100%')
          .padding({ bottom: 20 })

          // 滚动内容
          Scroll() {
            Column() {
              // ===== 滤镜设置 =====
              this.buildSectionTitle('滤镜设置')
              this.buildBrightnessControl()
              
              Divider()
                .margin({ top: 16, bottom: 16 })
                .color($r('app.color.divider'))
              
              // ===== 高级功能 =====
              this.buildSectionTitle('高级功能')
              // ===== 阅读快捷 =====
              this.buildSkipIntroSettings()
              // ===== 翻页动画 =====
              this.buildPageTurnAnimationSettings()
              // ===== 页面间距 =====
              this.buildPageSpacingControl()
              // ===== 其他设置 =====
              this.buildToggleSettings()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)

          // 操作按钮
          this.buildActionButtons()
        }
        .width('100%')
        .height('80%')
        .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
        .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
        .borderRadius({ topLeft: 16, topRight: 16 })
        .padding(20)
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