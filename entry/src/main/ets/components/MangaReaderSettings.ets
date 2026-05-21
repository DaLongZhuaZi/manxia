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
  DoublePagePortraitLayout,
  DEFAULT_READING_SETTINGS,
  DEFAULT_FILTER_SETTINGS
} from '../Models/MangaModels';
import { curves, UIContext, display } from '@kit.ArkUI';
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
    lockDeviceOrientation: DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
    lockMode: DEFAULT_READING_SETTINGS.lockMode ?? false,
    lockOrientation: DEFAULT_READING_SETTINGS.lockMode ?? false,
    pageSpacing: DEFAULT_READING_SETTINGS.pageSpacing,
    showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
    showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
    fitMode: DEFAULT_READING_SETTINGS.fitMode,
    autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
    skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
    pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
    doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
    doublePageVerticalDirection: DEFAULT_READING_SETTINGS.doublePageVerticalDirection,
    filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
    volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation,
    curlBackOpacity: DEFAULT_READING_SETTINGS.curlBackOpacity,
    webtoonLeftMargin: DEFAULT_READING_SETTINGS.webtoonLeftMargin,
    webtoonRightMargin: DEFAULT_READING_SETTINGS.webtoonRightMargin,
    webtoonMarginSync: DEFAULT_READING_SETTINGS.webtoonMarginSync
  };
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;
  @State private screenWidth: number = 360;
  @State private screenHeight: number = 640;

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
    
    // 初始化屏幕方向检测
    this.detectScreenOrientation();
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaReaderSettings', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `MangaReaderSettings 主题切换: ${theme}`);
    });
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
    
    // 复制阅读设置（确保所有字段都被复制）
    this.currentSettings.readingMode = this.readingSettings.readingMode;
    this.currentSettings.doublePagePortraitLayout = this.readingSettings.doublePagePortraitLayout || DoublePagePortraitLayout.VERTICAL;
    this.currentSettings.readingDirection = this.normalizeReadingDirectionForMode(
      this.readingSettings.readingMode,
      this.readingSettings.readingDirection,
      this.currentSettings.doublePagePortraitLayout
    );
    this.currentSettings.brightness = this.readingSettings.brightness;
    this.currentSettings.keepScreenOn = this.readingSettings.keepScreenOn;
    this.currentSettings.lockDeviceOrientation = this.readingSettings.lockDeviceOrientation ??
      DEFAULT_READING_SETTINGS.lockDeviceOrientation ??
      false;
    this.currentSettings.lockMode = this.readingSettings.lockMode ??
      this.readingSettings.lockOrientation ??
      DEFAULT_READING_SETTINGS.lockMode ??
      false;
    this.currentSettings.lockOrientation = this.currentSettings.lockMode;
    this.currentSettings.pageSpacing = this.readingSettings.pageSpacing;
    this.currentSettings.showPageInfo = this.readingSettings.showPageInfo;
    this.currentSettings.showPageIndicator = this.readingSettings.showPageIndicator;
    this.currentSettings.fitMode = this.readingSettings.fitMode;
    this.currentSettings.autoPageTurnInterval = this.readingSettings.autoPageTurnInterval;
    this.currentSettings.skipIntroPages = this.readingSettings.skipIntroPages;
    this.currentSettings.pageTurnAnimation = this.normalizePageTurnAnimationForMode(
      this.readingSettings.pageTurnAnimation,
      this.currentSettings.readingMode,
      this.currentSettings.doublePagePortraitLayout
    );
    this.currentSettings.doublePageVerticalDirection = this.readingSettings.doublePageVerticalDirection ??
      DEFAULT_READING_SETTINGS.doublePageVerticalDirection;
    this.currentSettings.filterSettings = this.readingSettings.filterSettings;
    this.currentSettings.volumeKeyNavigation = this.readingSettings.volumeKeyNavigation;
    this.currentSettings.curlBackOpacity = this.readingSettings.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity;
    this.currentSettings.webtoonLeftMargin = this.readingSettings.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin;
    this.currentSettings.webtoonRightMargin = this.readingSettings.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin;
    this.currentSettings.webtoonMarginSync = this.readingSettings.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync;
    
    logger.debug(TAG, `复制阅读设置: pageTurnAnimation=${this.currentSettings.pageTurnAnimation}, curlBackOpacity=${this.currentSettings.curlBackOpacity}`);
    
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

    if (this.isLandscape) {
      // 横屏：从右侧滑入
      const slideInOptions: AnimateParam = { 
        duration: 250, 
        curve: curves.initCurve(Curve.EaseOut),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideInOptions, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      // 竖屏：从底部滑入
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
    if (this.isLandscape) {
      // 横屏：向右滑出
      const slideOutOptions: AnimateParam = { 
        duration: 200, 
        curve: curves.initCurve(Curve.EaseIn),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideOutOptions, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = 320;
      });
    } else {
      // 竖屏：向下滑出
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
    }

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
      lockDeviceOrientation: DEFAULT_READING_SETTINGS.lockDeviceOrientation ?? false,
      lockMode: DEFAULT_READING_SETTINGS.lockMode ?? false,
      lockOrientation: DEFAULT_READING_SETTINGS.lockMode ?? false,
      showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      skipIntroPages: DEFAULT_READING_SETTINGS.skipIntroPages,
      pageTurnAnimation: DEFAULT_READING_SETTINGS.pageTurnAnimation,
      doublePagePortraitLayout: DEFAULT_READING_SETTINGS.doublePagePortraitLayout,
      doublePageVerticalDirection: DEFAULT_READING_SETTINGS.doublePageVerticalDirection,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation,
      curlBackOpacity: DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
    this.applySettings();
  }

  /**
   * 更新阅读模式（立即应用）
   */
  private updateReadingMode(mode: ReadingMode): void {
    this.currentSettings.readingMode = mode;
    this.currentSettings.readingDirection = this.normalizeReadingDirectionForMode(
      mode,
      this.currentSettings.readingDirection,
      this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
    this.normalizeCurrentPageTurnAnimation();
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
    if (this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.currentSettings.doublePagePortraitLayout = direction === ReadingDirection.TOP_TO_BOTTOM
        ? DoublePagePortraitLayout.VERTICAL
        : DoublePagePortraitLayout.HORIZONTAL;
    }
    this.currentSettings.readingDirection = this.normalizeReadingDirectionForMode(
      this.currentSettings.readingMode,
      direction,
      this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
    this.normalizeCurrentPageTurnAnimation();
    // 立即通知父组件应用设置，但不关闭面板
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
    logger.info(TAG, `阅读方向已更新: ${direction}`);
  }

  private isCurrentWebtoonReadingMode(): boolean {
    return this.currentSettings.readingMode === ReadingMode.WEBTOON ||
      this.currentSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      this.currentSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isContinuousScrollMode(): boolean {
    return this.currentSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private isSinglePageReadingMode(): boolean {
    return this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE ||
      this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      this.currentSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
  }

  private isVerticalDoublePageAnimationLocked(): boolean {
    return this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      (this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL) ===
        DoublePagePortraitLayout.VERTICAL;
  }

  private normalizePageTurnAnimationForMode(
    animationType: PageTurnAnimationType,
    mode: ReadingMode,
    doublePagePortraitLayout: DoublePagePortraitLayout
  ): PageTurnAnimationType {
    if (mode === ReadingMode.DOUBLE_PAGE && doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      return PageTurnAnimationType.SLIDE;
    }
    return animationType;
  }

  private normalizeCurrentPageTurnAnimation(): void {
    this.currentSettings.pageTurnAnimation = this.normalizePageTurnAnimationForMode(
      this.currentSettings.pageTurnAnimation,
      this.currentSettings.readingMode,
      this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
  }

  private normalizeReadingDirection(direction: ReadingDirection): ReadingDirection {
    return direction === ReadingDirection.VERTICAL
      ? ReadingDirection.TOP_TO_BOTTOM
      : direction;
  }

  private normalizeReadingDirectionForMode(
    mode: ReadingMode,
    direction: ReadingDirection,
    doublePagePortraitLayout: DoublePagePortraitLayout
  ): ReadingDirection {
    const normalizedDirection = this.normalizeReadingDirection(direction);
    if (mode === ReadingMode.DOUBLE_PAGE && doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      return ReadingDirection.TOP_TO_BOTTOM;
    }
    if (mode === ReadingMode.DOUBLE_PAGE && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    if ((mode === ReadingMode.WEBTOON ||
      mode === ReadingMode.WEBTOON_WITH_GAP ||
      mode === ReadingMode.CONTINUOUS_VERTICAL) &&
      normalizedDirection !== ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.TOP_TO_BOTTOM;
    }
    if (mode === ReadingMode.CONTINUOUS_SCROLL && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    return normalizedDirection;
  }

  private getSelectedReadingDirection(): ReadingDirection {
    return this.normalizeReadingDirectionForMode(
      this.currentSettings.readingMode,
      this.currentSettings.readingDirection,
      this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
  }

  private isTTBDirectionDisabled(): boolean {
    return this.isContinuousScrollMode();
  }

  private isHorizontalDirectionDisabled(): boolean {
    return this.isCurrentWebtoonReadingMode();
  }

  private getReadingDirectionHint(): string {
    if (this.isContinuousScrollMode()) {
      return '连续滚动仅支持从左到右或从右到左';
    }
    if (this.isHorizontalDirectionDisabled()) {
      return '条漫模式仅支持从上到下';
    }
    if (this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      (this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL) ===
        DoublePagePortraitLayout.VERTICAL) {
      return '当前双页为上下组合；选择左右方向会切换为左右组合。';
    }
    if (this.currentSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      return '当前双页为左右组合；选择从上到下将切换为上下组合。';
    }
    return '';
  }

  private isModeLocked(): boolean {
    return this.currentSettings.lockMode ?? this.currentSettings.lockOrientation ?? false;
  }

  private setModeLocked(isOn: boolean): void {
    this.currentSettings.lockMode = isOn;
    this.currentSettings.lockOrientation = isOn;
  }

  private getDeviceOrientationLockHint(): string {
    if (this.currentSettings.lockDeviceOrientation ?? false) {
      return '旋转设备时保持当前横竖屏方向';
    }
    return '开启后会锁住当前设备方向，避免阅读时误旋转';
  }

  private getModeLockHint(): string {
    if (this.isModeLocked()) {
      return '旋转设备时保持当前阅读模式';
    }
    if (this.isSinglePageReadingMode()) {
      return '单页模式横屏会临时切换为左右双页';
    }
    return '关闭时允许阅读器按屏幕方向临时优化布局';
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
    const normalizedAnimation: PageTurnAnimationType = this.normalizePageTurnAnimationForMode(
      animationType,
      this.currentSettings.readingMode,
      this.currentSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
    logger.info(TAG, `更新翻页动画: ${this.currentSettings.pageTurnAnimation} -> ${normalizedAnimation}`);
    this.currentSettings.pageTurnAnimation = normalizedAnimation;
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
    } else if (key === 'lockMode' || key === 'lockOrientation') {
      this.setModeLocked(!this.isModeLocked());
    } else if (key === 'lockDeviceOrientation') {
      this.currentSettings.lockDeviceOrientation = !(this.currentSettings.lockDeviceOrientation ?? false);
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

      if (this.getReadingDirectionHint().length > 0) {
        Text(this.getReadingDirectionHint())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 12 })
      }

      Row() {
        // 从左到右
        Column() {
          Image($r('app.media.ic_ltr'))
            .width(24)
            .height(24)
            .fillColor(this.getSelectedReadingDirection() === ReadingDirection.LEFT_TO_RIGHT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('左→右')
            .fontSize(12)
            .fontColor(this.getSelectedReadingDirection() === ReadingDirection.LEFT_TO_RIGHT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.getSelectedReadingDirection() === ReadingDirection.LEFT_TO_RIGHT ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .opacity(this.isHorizontalDirectionDisabled() ? 0.4 : 1.0)
        .onClick(() => {
          if (!this.isHorizontalDirectionDisabled()) {
            this.updateReadingDirection(ReadingDirection.LEFT_TO_RIGHT);
          }
        })

        // 从右到左
        Column() {
          Image($r('app.media.ic_rtl'))
            .width(24)
            .height(24)
            .fillColor(this.getSelectedReadingDirection() === ReadingDirection.RIGHT_TO_LEFT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('右→左')
            .fontSize(12)
            .fontColor(this.getSelectedReadingDirection() === ReadingDirection.RIGHT_TO_LEFT ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.getSelectedReadingDirection() === ReadingDirection.RIGHT_TO_LEFT ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .opacity(this.isHorizontalDirectionDisabled() ? 0.4 : 1.0)
        .onClick(() => {
          if (!this.isHorizontalDirectionDisabled()) {
            this.updateReadingDirection(ReadingDirection.RIGHT_TO_LEFT);
          }
        })

        // 垂直
        Column() {
          Image($r('app.media.ic_vertical'))
            .width(24)
            .height(24)
            .fillColor(this.getSelectedReadingDirection() === ReadingDirection.TOP_TO_BOTTOM ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))

          Text('从上到下')
            .fontSize(12)
            .fontColor(this.getSelectedReadingDirection() === ReadingDirection.TOP_TO_BOTTOM ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.getSelectedReadingDirection() === ReadingDirection.TOP_TO_BOTTOM ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .opacity(this.isTTBDirectionDisabled() ? 0.4 : 1.0)
        .onClick(() => {
          if (!this.isTTBDirectionDisabled()) {
            this.updateReadingDirection(ReadingDirection.TOP_TO_BOTTOM);
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建滤镜开关
   */
  @Builder
  buildFilterToggle() {
    Row() {
      Text('启用滤镜')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      
      Blank()
      
      Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.filterSettings.enabled })
        .selectedColor($r('app.color.accent'))
        .onChange((isOn: boolean) => {
          this.updateFilterSettings('enabled', isOn);
          if (this.callbacks.onSettingsChange) {
            this.callbacks.onSettingsChange(this.currentSettings);
          }
        })
    }
    .width('100%')
    .margin({ bottom: 16 })
  }

  /**
   * 构建亮度调节器（滤镜亮度）
   */
  @Builder
  buildFilterBrightnessControl() {
    Column() {
      Row() {
        Text('滤镜亮度')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${this.currentSettings.filterSettings.brightness}%`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({
        value: this.currentSettings.filterSettings.brightness,
        min: 0,
        max: 200,
        step: 5
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateFilterSettings('brightness', value);
          if (this.callbacks.onSettingsChange) {
            this.callbacks.onSettingsChange(this.currentSettings);
          }
        })
    }
    .width('100%')
    .margin({ bottom: 12 })
    .opacity(this.currentSettings.filterSettings.enabled ? 1.0 : 0.5)
  }

  /**
   * 构建对比度调节器
   */
  @Builder
  buildContrastControl() {
    Column() {
      Row() {
        Text('对比度')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${this.currentSettings.filterSettings.contrast}%`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({
        value: this.currentSettings.filterSettings.contrast,
        min: 0,
        max: 200,
        step: 5
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateFilterSettings('contrast', value);
          if (this.callbacks.onSettingsChange) {
            this.callbacks.onSettingsChange(this.currentSettings);
          }
        })
    }
    .width('100%')
    .margin({ bottom: 12 })
    .opacity(this.currentSettings.filterSettings.enabled ? 1.0 : 0.5)
  }

  /**
   * 构建饱和度调节器
   */
  @Builder
  buildSaturationControl() {
    Column() {
      Row() {
        Text('饱和度')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${this.currentSettings.filterSettings.saturation}%`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({
        value: this.currentSettings.filterSettings.saturation,
        min: 0,
        max: 200,
        step: 5
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateFilterSettings('saturation', value);
          if (this.callbacks.onSettingsChange) {
            this.callbacks.onSettingsChange(this.currentSettings);
          }
        })
    }
    .width('100%')
    .margin({ bottom: 12 })
    .opacity(this.currentSettings.filterSettings.enabled ? 1.0 : 0.5)
  }

  /**
   * 构建棕褐色滤镜调节器
   */
  @Builder
  buildSepiaControl() {
    Column() {
      Row() {
        Text('复古色调')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))

        Blank()

        Text(`${this.currentSettings.filterSettings.sepia}%`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      Slider({
        value: this.currentSettings.filterSettings.sepia,
        min: 0,
        max: 100,
        step: 5
      })
        .width('100%')
        .trackColor($r('app.color.divider'))
        .selectedColor($r('app.color.accent'))
        .onChange((value: number) => {
          this.updateFilterSettings('sepia', value);
          if (this.callbacks.onSettingsChange) {
            this.callbacks.onSettingsChange(this.currentSettings);
          }
        })
    }
    .width('100%')
    .margin({ bottom: 12 })
    .opacity(this.currentSettings.filterSettings.enabled ? 1.0 : 0.5)
  }

  /**
   * 构建特殊滤镜开关（灰度、反色）
   */
  @Builder
  buildSpecialFilters() {
    Column() {
      // 灰度模式
      Row() {
        Text('灰度模式')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        
        Blank()
        
        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.filterSettings.grayscale })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.updateFilterSettings('grayscale', isOn);
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 反色模式
      Row() {
        Text('反色模式')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        
        Blank()
        
        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.filterSettings.invert })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.updateFilterSettings('invert', isOn);
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
    .opacity(this.currentSettings.filterSettings.enabled ? 1.0 : 0.5)
  }

  /**
   * 构建滤镜重置按钮
   */
  @Builder
  buildFilterResetButton() {
    Button('重置滤镜')
      .fontSize(14)
      .fontColor($r('app.color.accent'))
      .backgroundColor(Color.Transparent)
      .borderWidth(1)
      .borderColor($r('app.color.accent'))
      .borderRadius(8)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onClick(() => {
        // 重置滤镜设置为默认值
        this.currentSettings.filterSettings = {
          enabled: false,
          brightness: 100,
          contrast: 100,
          saturation: 100,
          hue: 0,
          gamma: 1.0,
          sepia: 0,
          invert: false,
          grayscale: false,
          blur: 0
        };
        if (this.callbacks.onSettingsChange) {
          this.callbacks.onSettingsChange(this.currentSettings);
        }
      })
  }

  /**
   * 构建完整的滤镜设置面板
   */
  @Builder
  buildFilterSettingsPanel() {
    Column() {
      this.buildFilterToggle()
      this.buildFilterBrightnessControl()
      this.buildContrastControl()
      this.buildSaturationControl()
      this.buildSepiaControl()
      this.buildSpecialFilters()
      this.buildFilterResetButton()
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建亮度调节器（屏幕亮度）
   */
  @Builder
  buildBrightnessControl() {
    Column() {
      Row() {
        Text('屏幕亮度')
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
  private buildVerticalDoublePageAnimationLockContent(textSize: number) {
    Column({ space: 8 }) {
      Row() {
        Text('上下专属')
          .fontSize(textSize)
          .fontColor($r('app.color.accent'))
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.accent_background'))
      .borderRadius(8)
      .justifyContent(FlexAlign.Center)

      Text('上下双页使用触顶/触底翻页，只支持专属上下滑动动画。')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildPageTurnAnimationSettings() {
    Column() {
      Text('翻页动画')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })

      if (this.isVerticalDoublePageAnimationLocked()) {
        this.buildVerticalDoublePageAnimationLockContent(12)
      } else {
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
      .margin({ bottom: 8 })
      
      // 第三行：新增3种动画
      Row() {
        // 立方体
        Column() {
          Text('立方体')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.CUBE ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.CUBE ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.CUBE))

        // 覆盖
        Column() {
          Text('覆盖')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.COVER ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.COVER ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.COVER))

        // 景深
        Column() {
          Text('景深')
            .fontSize(12)
            .fontColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.DEPTH ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.pageTurnAnimation === PageTurnAnimationType.DEPTH ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updatePageTurnAnimation(PageTurnAnimationType.DEPTH))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      
      // 卷页透明度滑动条（仅在选择卷页动画时显示）
      if (this.currentSettings.pageTurnAnimation === PageTurnAnimationType.CURL) {
        Column() {
          Row() {
            Text('卷页不透明度')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(`${this.currentSettings.curlBackOpacity ?? 90}%`)
              .fontSize(14)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ top: 16, bottom: 8 })
          
          Slider({
            value: this.currentSettings.curlBackOpacity ?? 90,
            min: 0,
            max: 100,
            step: 5,
            style: SliderStyle.OutSet
          })
            .blockColor($r('app.color.accent'))
            .trackColor($r('app.color.background_secondary'))
            .selectedColor($r('app.color.accent'))
            .onChange((value: number) => {
              this.updateCurlBackOpacity(value);
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      }
    }
    .width('100%')
    .margin({ bottom: 24 })
  }
  
  /**
   * 更新卷页背面透明度
   */
  private updateCurlBackOpacity(opacity: number): void {
    logger.info(TAG, `更新卷页透明度: ${this.currentSettings.curlBackOpacity} -> ${opacity}`);
    this.currentSettings.curlBackOpacity = opacity;
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }
  
  /**
   * 更新双页竖屏组合方式
   */
  private updateDoublePagePortraitLayout(layout: DoublePagePortraitLayout): void {
    logger.info(TAG, `更新双页竖屏组合方式: ${this.currentSettings.doublePagePortraitLayout} -> ${layout}`);
    this.currentSettings.doublePagePortraitLayout = layout;
    this.currentSettings.readingDirection = this.normalizeReadingDirectionForMode(
      this.currentSettings.readingMode,
      this.currentSettings.readingDirection,
      layout
    );
    this.normalizeCurrentPageTurnAnimation();
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.currentSettings);
    }
  }
  
  /**
   * 构建双页竖屏组合方式设置
   */
  @Builder
  buildDoublePagePortraitLayoutSettings() {
    Column() {
      Text('双页竖屏组合')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })
      
      Row({ space: 8 }) {
        // 上下组合
        Column() {
          Text('上下组合')
            .fontSize(12)
            .fontColor((this.currentSettings.doublePagePortraitLayout || DoublePagePortraitLayout.VERTICAL) === DoublePagePortraitLayout.VERTICAL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor((this.currentSettings.doublePagePortraitLayout || DoublePagePortraitLayout.VERTICAL) === DoublePagePortraitLayout.VERTICAL ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.VERTICAL))
        
        // 左右组合
        Column() {
          Text('左右组合')
            .fontSize(12)
            .fontColor(this.currentSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ? 
              $r('app.color.accent') : $r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .padding(12)
        .backgroundColor(this.currentSettings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL ? 
          $r('app.color.accent_background') : Color.Transparent)
        .borderRadius(8)
        .onClick(() => this.updateDoublePagePortraitLayout(DoublePagePortraitLayout.HORIZONTAL))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  /**
   * 构建开关设置项
   * 注意：showPageInfo 控制页面信息显示，showPageIndicator 控制页面指示器
   */
  @Builder
  buildToggleSettings() {
    Column() {
      // 显示页面信息（页码等）
      Row() {
        Column() {
          Text('显示页面信息')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text('在页面上显示当前页码')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.showPageInfo })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.showPageInfo = isOn;
            // 同步更新 showPageIndicator
            this.currentSettings.showPageIndicator = isOn;
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider()
        .color($r('app.color.divider'))

      Row() {
        Column() {
          Text('锁定模式')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(this.getModeLockHint())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isModeLocked() })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.setModeLocked(isOn);
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      Divider()
        .color($r('app.color.divider'))

      Row() {
        Column() {
          Text('锁定方向')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text(this.getDeviceOrientationLockHint())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.lockDeviceOrientation ?? false })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.lockDeviceOrientation = isOn;
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
        Column() {
          Text('保持屏幕常亮')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
          Text('阅读时防止屏幕自动关闭')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.keepScreenOn })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.currentSettings.keepScreenOn = isOn;
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

  /**
   * 构建横屏设置面板（从右侧滑入，双列布局）
   */
  @Builder
  buildLandscapeSettingsPanel() {
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
          Text('高级设置')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.hidePanel())
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 滚动内容 - 横屏使用更紧凑的布局
        Scroll() {
          Column() {
            // 横屏布局：滤镜设置
            this.buildLandscapeFilterSettings()
            
            Divider()
              .margin({ top: 12, bottom: 12 })
              .color($r('app.color.divider'))
            
            // 开关设置（横向布局）
            this.buildLandscapeToggleSettings()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)

        // 操作按钮
        Row() {
          Button('重置')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.background_secondary'))
            .layoutWeight(1)
            .height(36)
            .onClick(() => this.resetToDefaults())

          Blank().width(8)

          Button('关闭')
            .fontSize(12)
            .fontColor($r('app.color.text_on_accent'))
            .backgroundColor($r('app.color.accent'))
            .layoutWeight(1)
            .height(36)
            .onClick(() => this.hidePanel())
        }
        .width('100%')
      }
      .width(320)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 横屏滤镜设置（紧凑布局）
   */
  @Builder
  buildLandscapeFilterSettings() {
    Column() {
      Text('显示设置')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })

      // 滤镜开关
      Row() {
        Text('启用滤镜')
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.filterSettings.enabled })
          .selectedColor($r('app.color.accent'))
          .onChange((isOn: boolean) => {
            this.updateFilterSettings('enabled', isOn);
            if (this.callbacks.onSettingsChange) {
              this.callbacks.onSettingsChange(this.currentSettings);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 横屏翻页动画设置（紧凑网格布局）
   */
  @Builder
  buildLandscapePageTurnAnimation() {
    Column() {
      Text('翻页动画')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })

      if (this.isVerticalDoublePageAnimationLocked()) {
        this.buildVerticalDoublePageAnimationLockContent(11)
      } else {
      // 3x3 网格布局
      Column() {
        Row() {
          this.buildCompactAnimButton('无', PageTurnAnimationType.NONE)
          this.buildCompactAnimButton('滑动', PageTurnAnimationType.SLIDE)
          this.buildCompactAnimButton('淡入', PageTurnAnimationType.FADE)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 4 })

        Row() {
          this.buildCompactAnimButton('立方体', PageTurnAnimationType.CUBE)
          this.buildCompactAnimButton('覆盖', PageTurnAnimationType.COVER)
          this.buildCompactAnimButton('景深', PageTurnAnimationType.DEPTH)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ bottom: 4 })

        Row() {
          this.buildCompactAnimButton('卷页', PageTurnAnimationType.CURL)
          // 占位
          Column().width('31%')
          Column().width('31%')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 紧凑动画按钮
   */
  @Builder
  buildCompactAnimButton(label: string, type: PageTurnAnimationType) {
    Text(label)
      .fontSize(10)
      .fontColor(this.currentSettings.pageTurnAnimation === type ? 
        $r('app.color.accent') : $r('app.color.text_secondary'))
      .width('31%')
      .height(28)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.currentSettings.pageTurnAnimation === type ? 
        $r('app.color.accent_background') : Color.Transparent)
      .borderRadius(4)
      .onClick(() => this.updatePageTurnAnimation(type))
  }

  /**
   * 横屏开关设置（横向布局）
   */
  @Builder
  buildLandscapeToggleSettings() {
    Column() {
      Text('其他设置')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })

      // 两列布局
      Row() {
        // 左列
        Column() {
          Row() {
            Text('页面信息')
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.showPageInfo })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.currentSettings.showPageInfo = isOn;
                this.currentSettings.showPageIndicator = isOn;
                if (this.callbacks.onSettingsChange) {
                  this.callbacks.onSettingsChange(this.currentSettings);
                }
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('锁定方向')
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.lockDeviceOrientation ?? false })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.currentSettings.lockDeviceOrientation = isOn;
                if (this.callbacks.onSettingsChange) {
                  this.callbacks.onSettingsChange(this.currentSettings);
                }
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('锁定模式')
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.isModeLocked() })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.setModeLocked(isOn);
                if (this.callbacks.onSettingsChange) {
                  this.callbacks.onSettingsChange(this.currentSettings);
                }
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .margin({ right: 8 })

        // 右列
        Column() {
          Row() {
            Text('屏幕常亮')
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.keepScreenOn })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.currentSettings.keepScreenOn = isOn;
                if (this.callbacks.onSettingsChange) {
                  this.callbacks.onSettingsChange(this.currentSettings);
                }
              })
          }
          .width('100%')
          .margin({ bottom: 6 })

          Row() {
            Text('音量翻页')
              .fontSize(11)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.currentSettings.volumeKeyNavigation })
              .selectedColor($r('app.color.accent'))
              .onChange((isOn: boolean) => {
                this.currentSettings.volumeKeyNavigation = isOn;
                if (this.callbacks.onSettingsChange) {
                  this.callbacks.onSettingsChange(this.currentSettings);
                }
              })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
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

        // 根据屏幕方向选择不同布局
        if (this.isLandscape) {
          this.buildLandscapeSettingsPanel()
        } else {
          // 竖屏设置面板
          Column() {
            // 面板标题
            Row() {
              Column() {
                Text('显示效果设置')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                Text('滤镜等显示效果配置')
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
                this.buildSectionTitle('图像滤镜')
                this.buildFilterSettingsPanel()
                
                Divider()
                  .margin({ top: 16, bottom: 16 })
                  .color($r('app.color.divider'))
                
                // ===== 显示设置 =====
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
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
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
    }
  }
}
