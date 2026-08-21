// 文件路径: src/main/ets/Framework/Managers/PreviewerEnvironmentManager.ets
/**
 * 漫画阅读器设置面板组件
 * 提供阅读模式、阅读方向、亮度调节、滤镜效果、页面间距等配置选项
 */

import { logger } from '../../Utils/Logger';
import { 
  GlobalAnimationManager, 
  AnimationType, 
  AnimationUtils,
  globalAnimationManager 
} from '../Animation/GlobalAnimationSystem';
import { 
  ReadingMode, 
  ReadingDirection,
  ReadingSettings,
  FilterSettings,
  DEFAULT_READING_SETTINGS,
  DEFAULT_FILTER_SETTINGS
} from '../../Models/MangaModels';
import { curves, UIContext } from '@kit.ArkUI';

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

@Component
export struct MangaReaderSettings {
  @Prop readingSettings: ReadingSettings;
  @Prop isVisible: boolean;
  // 回调函数不能使用@Prop装饰器
  onSettingsChange?: (settings: ReadingSettings) => void;
  onClose?: () => void;
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
    filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
    fullscreen: DEFAULT_READING_SETTINGS.fullscreen,
    volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation
  };
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private backdropOpacity: number = 0;
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
    this.currentSettings.fullscreen = this.readingSettings.fullscreen;
    this.currentSettings.volumeKeyNavigation = this.readingSettings.volumeKeyNavigation;

    if (this.isVisible) {
      this.showPanel();
    }
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
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

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

  /**
   * 应用设置
   */
  private applySettings(): void {
    logger.info(TAG, '应用阅读设置');
    if (this.onSettingsChange) {
      this.onSettingsChange(this.currentSettings);
    }
    this.hidePanel();

    // 动画完成后调用关闭回调
    setTimeout(() => {
      if (this.onClose) {
        this.onClose();
      }
    }, 500);
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
      fullscreen: DEFAULT_READING_SETTINGS.fullscreen,
      keepScreenOn: DEFAULT_READING_SETTINGS.keepScreenOn,
      showPageInfo: DEFAULT_READING_SETTINGS.showPageInfo,
      showPageIndicator: DEFAULT_READING_SETTINGS.showPageIndicator,
      fitMode: DEFAULT_READING_SETTINGS.fitMode,
      autoPageTurnInterval: DEFAULT_READING_SETTINGS.autoPageTurnInterval,
      filterSettings: DEFAULT_READING_SETTINGS.filterSettings,
      volumeKeyNavigation: DEFAULT_READING_SETTINGS.volumeKeyNavigation
    };
    this.applySettings();
  }

  /**
   * 更新阅读模式
   */
  private updateReadingMode(mode: ReadingMode): void {
    this.currentSettings.readingMode = mode;
    this.applySettings();
  }

  /**
   * 更新阅读方向
   */
  private updateReadingDirection(direction: ReadingDirection): void {
    this.currentSettings.readingDirection = direction;
    this.applySettings();
  }

  build() {
  }
}