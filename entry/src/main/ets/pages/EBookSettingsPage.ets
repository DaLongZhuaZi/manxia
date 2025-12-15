// 文件路径: entry/src/main/ets/pages/EBookSettingsPage.ets
/**
 * 电子书设置页面
 * 提供电子书阅读相关的设置选项
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { EBook, EBookReadingSettings, EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, EBookFormat, DEFAULT_EBOOK_READING_SETTINGS } from '../Models/EBookModels';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo } from '../Framework/Managers/DeviceAdaptationManager';
import { SandboxManager } from '../Framework/Storage/SandboxManager';
import {
  TextReaderSettings,
  TextReadingMode,
  TextPageTurnAnimation,
  TextAlignment,
  BackgroundType,
  PRESET_BACKGROUNDS,
  PresetBackground,
  DEFAULT_TEXT_READER_SETTINGS
} from '../Models/TextReaderModels';
import { eventBus, GameEvent, BasePayload } from '../Framework/EventBus';

const TAG = 'EBookSettingsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/** 文字对齐选项接口 */
interface AlignmentSettingOption {
  text: string;
  align: TextAlignment;
}

/** 翻页动画选项接口 */
interface AnimationSettingOption {
  text: string;
  anim: TextPageTurnAnimation;
}

/** 判断背景色是否为深色 */
function isDarkBackground(bgColor: string): boolean {
  const hex = bgColor.replace('#', '');
  const r = parseInt(hex.substring(0, 2), 16);
  const g = parseInt(hex.substring(2, 4), 16);
  const b = parseInt(hex.substring(4, 6), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance < 0.5;
}

@Component
export struct EBookSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'EBookSettingsPage';
  private scroller: Scroller = new Scroller();

  // 电子书数据
  @State ebook: EBook | null = null;
  @State settings: EBookReadingSettings | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';

  // 字体设置
  @State settingFontSize: number = 18;
  @State settingFontFamily: string = 'HarmonyOS Sans';
  @State settingFontPath: string = '';
  @State settingFontWeight: number = 400;
  
  // 排版设置
  @State settingLineHeight: number = 1.9;
  
  // 颜色主题设置
  @State settingBgColor: string = '#FFFFFF';
  @State settingTextColor: string = '#000000';
  @State settingThemeBgImage: string = '';
  @State settingNightMode: boolean = false;
  @State selectedThemeIndex: number = 0;
  
  // 翻页设置
  @State settingPageMargin: number = 20;
  @State settingPageMode: EBookPageMode = EBookPageMode.SIMULATION;
  
  // 系统设置
  @State settingBrightness: number = 100;
  @State settingAutoSave: boolean = true;
  @State settingSaveInterval: number = 30;

  // ========== 纯文本阅读器专用设置 ==========
  @State textReaderSettings: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS;
  // 字体设置
  @State settingLetterSpacing: number = 0;
  @State settingParagraphSpacing: number = 8;
  @State settingFirstLineIndent: number = 2;
  @State settingTextAlignment: TextAlignment = TextAlignment.JUSTIFY;
  // 翻页设置
  @State settingPageTurnAnimation: TextPageTurnAnimation = TextPageTurnAnimation.SLIDE;
  @State settingTapToTurn: boolean = true;
  @State settingVolumeKeyNavigation: boolean = true;
  @State settingKeepScreenOn: boolean = false;
  // 显示设置
  @State settingShowPageNumber: boolean = true;
  @State settingShowProgress: boolean = false;
  @State settingShowTime: boolean = true;
  @State settingShowBattery: boolean = false;
  // 背景设置
  @State settingBackgroundType: BackgroundType = BackgroundType.COLOR;
  @State settingBackgroundImagePath: string = '';
  @State settingBackgroundImageOpacity: number = 0.3;

  // 主题相关
  private themeManager: ThemeManager = ThemeManager.getInstance();

  // 设备方向检测
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  
  // UI上下文（用于获取应用上下文）
  private uiContext: UIContext | undefined = undefined;
  
  // 封面路径（用于显示更新后的封面）
  @State coverImagePath: string = '';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 注册设备方向变化监听器
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      logger.info(TAG, `设备方向变化: ${deviceInfo.isLandscape ? '横屏' : '竖屏'}`);
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // 移除设备方向监听器
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
    }
  }

  /**
   * 更新设备方向
   */
  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    logger.info(TAG, `设备方向初始化: ${this.isLandscape ? '横屏' : '竖屏'}`);
  }

  /**
   * 加载电子书设置
   */
  private async loadSettings(bookId: string): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `加载电子书设置: ${bookId}`);
      const ebook = await this.ebookDataManager.getEBookById(bookId);

      if (!ebook) {
        throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      
      // [修复] 初始化封面路径状态变量
      this.coverImagePath = ebook.metadata.coverImagePath || '';
      
      // [修复] 先获取全局设置
      const settingsManager = SettingsManager.getInstance();
      const isTextFormat = ebook.format === EBookFormat.TXT;
      
      // 电子书全局设置
      const globalThemeIndex = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_THEME, 0);
      const globalFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, DEFAULT_EBOOK_READING_SETTINGS.fontSize);
      const globalLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, DEFAULT_EBOOK_READING_SETTINGS.lineHeight);
      const globalPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, DEFAULT_EBOOK_READING_SETTINGS.pageMargin);
      const globalPageMode = settingsManager.getString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, DEFAULT_EBOOK_READING_SETTINGS.pageMode) as EBookPageMode;
      const themePreset: EBookThemePreset = EBOOK_THEME_PRESETS[globalThemeIndex] || EBOOK_THEME_PRESETS[0];
      
      // 纯文本阅读器全局设置
      const globalTextFontSize = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, 18);
      const globalTextLineHeight = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, 1.8);
      const globalTextParagraphSpacing = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, 16);
      const globalTextFirstLineIndent = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, 2);
      const globalTextPageMargin = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, 24);
      const globalTextBgColorIndex = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, 0);
      const globalTextUseBgImage = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
      const globalTextBgImagePath = settingsManager.getString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, '');
      const globalTextBgImageOpacity = settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, 1.0);
      const globalTextPageTurnAnimation = settingsManager.getString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, TextPageTurnAnimation.SLIDE) as TextPageTurnAnimation;
      const globalTextKeepScreenOn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, true);
      const globalTextVolumeKeyNav = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, true);
      const globalTextTapToTurn = settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, true);
      const globalTextBgPreset = PRESET_BACKGROUNDS[globalTextBgColorIndex] || PRESET_BACKGROUNDS[0];
      
      // 加载阅读设置
      if (ebook.readingSettings) {
        // [修复] 检查是否是默认设置（followSystemTheme=true 且背景色是默认白色或夜间黑色）
        const isDefaultSettings = ebook.readingSettings.followSystemTheme === true &&
          (ebook.readingSettings.backgroundColor === '#FFFFFF' || 
           ebook.readingSettings.backgroundColor === '#1E1E1E' ||
           ebook.readingSettings.backgroundColor === '#F5F0E1' ||
           ebook.readingSettings.backgroundColor === DEFAULT_EBOOK_READING_SETTINGS.backgroundColor);
        
        if (isDefaultSettings) {
          if (isTextFormat) {
            // 纯文本格式：使用纯文本阅读器全局设置
            logger.info(TAG, `纯文本格式检测到默认设置，应用全局设置: 字体大小=${globalTextFontSize}, 背景色=${globalTextBgPreset.backgroundColor}`);
            
            this.settingFontSize = globalTextFontSize;
            this.settingFontFamily = DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
            this.settingFontPath = '';
            this.settingFontWeight = 400;
            this.settingLineHeight = globalTextLineHeight;
            this.settingBgColor = globalTextBgPreset.backgroundColor;
            this.settingTextColor = globalTextBgPreset.textColor;
            this.settingThemeBgImage = '';
            this.settingNightMode = false;
            this.selectedThemeIndex = globalTextBgColorIndex;
            this.settingPageMargin = globalTextPageMargin;
            this.settingPageMode = EBookPageMode.SIMULATION;
            this.settingAutoSave = DEFAULT_EBOOK_READING_SETTINGS.autoSave;
            this.settingSaveInterval = DEFAULT_EBOOK_READING_SETTINGS.saveInterval;
            
            // 纯文本阅读器专用设置从全局设置读取
            this.settingLetterSpacing = 0;
            this.settingParagraphSpacing = globalTextParagraphSpacing;
            this.settingFirstLineIndent = globalTextFirstLineIndent;
            this.settingTextAlignment = TextAlignment.JUSTIFY;
            this.settingPageTurnAnimation = globalTextPageTurnAnimation;
            this.settingTapToTurn = globalTextTapToTurn;
            this.settingVolumeKeyNavigation = globalTextVolumeKeyNav;
            this.settingKeepScreenOn = globalTextKeepScreenOn;
            this.settingShowPageNumber = true;
            this.settingShowProgress = false;
            this.settingShowTime = true;
            this.settingShowBattery = false;
            this.settingBackgroundType = globalTextUseBgImage ? BackgroundType.IMAGE : BackgroundType.COLOR;
            this.settingBackgroundImagePath = globalTextBgImagePath;
            this.settingBackgroundImageOpacity = globalTextBgImageOpacity;
          } else {
            // 其他格式：使用电子书全局设置
            logger.info(TAG, `检测到默认设置，应用全局设置: 主题索引=${globalThemeIndex}, 背景色=${themePreset.backgroundColor}, 字体大小=${globalFontSize}`);
            
            this.settingFontSize = globalFontSize;
            this.settingFontFamily = DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
            this.settingFontPath = '';
            this.settingFontWeight = DEFAULT_EBOOK_READING_SETTINGS.fontWeight || 400;
            this.settingLineHeight = globalLineHeight;
            this.settingBgColor = themePreset.backgroundColor;
            this.settingTextColor = themePreset.textColor;
            this.settingThemeBgImage = themePreset.themeBgImage || '';
            this.settingNightMode = themePreset.nightMode;
            this.selectedThemeIndex = globalThemeIndex;
            this.settingPageMargin = globalPageMargin;
            this.settingPageMode = globalPageMode;
            this.settingAutoSave = DEFAULT_EBOOK_READING_SETTINGS.autoSave;
            this.settingSaveInterval = DEFAULT_EBOOK_READING_SETTINGS.saveInterval;
            
            // 纯文本阅读器专用设置使用默认值
            this.settingLetterSpacing = 0;
            this.settingParagraphSpacing = 8;
            this.settingFirstLineIndent = 2;
            this.settingTextAlignment = TextAlignment.JUSTIFY;
            this.settingPageTurnAnimation = TextPageTurnAnimation.SLIDE;
            this.settingTapToTurn = true;
            this.settingVolumeKeyNavigation = true;
            this.settingKeepScreenOn = false;
            this.settingShowPageNumber = true;
            this.settingShowProgress = false;
            this.settingShowTime = true;
            this.settingShowBattery = false;
            this.settingBackgroundType = BackgroundType.COLOR;
            this.settingBackgroundImagePath = '';
            this.settingBackgroundImageOpacity = 0.3;
          }
        } else {
          // 用户已修改过设置，使用保存的设置
          logger.info(TAG, `使用用户自定义设置: 背景色=${ebook.readingSettings.backgroundColor}, 字体大小=${ebook.readingSettings.fontSize}`);
          
          this.settings = ebook.readingSettings;
          // 字体设置
          this.settingFontSize = ebook.readingSettings.fontSize;
          this.settingFontFamily = ebook.readingSettings.fontFamily;
          this.settingFontPath = ebook.readingSettings.fontPath || '';
          this.settingFontWeight = ebook.readingSettings.fontWeight || 400;
          // 排版设置
          this.settingLineHeight = ebook.readingSettings.lineHeight;
          // 颜色主题设置
          this.settingBgColor = ebook.readingSettings.backgroundColor;
          this.settingTextColor = ebook.readingSettings.textColor;
          this.settingThemeBgImage = ebook.readingSettings.themeBgImage || '';
          this.settingNightMode = ebook.readingSettings.nightMode || false;
          // 查找匹配的主题索引
          this.selectedThemeIndex = EBOOK_THEME_PRESETS.findIndex(
            (theme: EBookThemePreset) => theme.backgroundColor === this.settingBgColor
          );
          if (this.selectedThemeIndex < 0) this.selectedThemeIndex = 0;
          // 翻页设置
          this.settingPageMargin = ebook.readingSettings.pageMargin;
          this.settingPageMode = ebook.readingSettings.pageMode || EBookPageMode.SIMULATION;
          // 系统设置
          this.settingAutoSave = ebook.readingSettings.autoSave;
          this.settingSaveInterval = ebook.readingSettings.saveInterval;
          
          // ========== 加载纯文本阅读器专用设置 ==========
          // 高级字体设置
          this.settingLetterSpacing = ebook.readingSettings.letterSpacing ?? 0;
          this.settingParagraphSpacing = ebook.readingSettings.paragraphSpacing ?? 8;
          this.settingFirstLineIndent = ebook.readingSettings.firstLineIndent ?? 2;
          this.settingTextAlignment = (ebook.readingSettings.textAlignment as TextAlignment) ?? TextAlignment.JUSTIFY;
          // 翻页动画设置
          this.settingPageTurnAnimation = (ebook.readingSettings.pageTurnAnimation as TextPageTurnAnimation) ?? TextPageTurnAnimation.SLIDE;
          this.settingTapToTurn = ebook.readingSettings.tapToTurn ?? true;
          this.settingVolumeKeyNavigation = ebook.readingSettings.volumeKeyNavigation ?? true;
          this.settingKeepScreenOn = ebook.readingSettings.keepScreenOn ?? false;
          // 显示设置
          this.settingShowPageNumber = ebook.readingSettings.showPageNumber ?? true;
          this.settingShowProgress = ebook.readingSettings.showProgress ?? false;
          this.settingShowTime = ebook.readingSettings.showTime ?? true;
          this.settingShowBattery = ebook.readingSettings.showBattery ?? false;
          // 背景设置
          this.settingBackgroundType = (ebook.readingSettings.backgroundType as BackgroundType) ?? BackgroundType.COLOR;
          this.settingBackgroundImagePath = ebook.readingSettings.backgroundImagePath ?? '';
          this.settingBackgroundImageOpacity = ebook.readingSettings.backgroundImageOpacity ?? 0.3;
        }
      } else {
        // 没有保存的设置，使用全局设置
        if (isTextFormat) {
          // 纯文本格式：使用纯文本阅读器全局设置
          logger.info(TAG, `纯文本格式无保存设置，应用全局设置: 字体大小=${globalTextFontSize}, 背景色=${globalTextBgPreset.backgroundColor}`);
          
          this.settingFontSize = globalTextFontSize;
          this.settingFontFamily = DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
          this.settingFontPath = '';
          this.settingFontWeight = 400;
          this.settingLineHeight = globalTextLineHeight;
          this.settingBgColor = globalTextBgPreset.backgroundColor;
          this.settingTextColor = globalTextBgPreset.textColor;
          this.settingThemeBgImage = '';
          this.settingNightMode = false;
          this.selectedThemeIndex = globalTextBgColorIndex;
          this.settingPageMargin = globalTextPageMargin;
          this.settingPageMode = EBookPageMode.SIMULATION;
          this.settingAutoSave = DEFAULT_EBOOK_READING_SETTINGS.autoSave;
          this.settingSaveInterval = DEFAULT_EBOOK_READING_SETTINGS.saveInterval;
          
          // 纯文本阅读器专用设置从全局设置读取
          this.settingLetterSpacing = 0;
          this.settingParagraphSpacing = globalTextParagraphSpacing;
          this.settingFirstLineIndent = globalTextFirstLineIndent;
          this.settingTextAlignment = TextAlignment.JUSTIFY;
          this.settingPageTurnAnimation = globalTextPageTurnAnimation;
          this.settingTapToTurn = globalTextTapToTurn;
          this.settingVolumeKeyNavigation = globalTextVolumeKeyNav;
          this.settingKeepScreenOn = globalTextKeepScreenOn;
          this.settingShowPageNumber = true;
          this.settingShowProgress = false;
          this.settingShowTime = true;
          this.settingShowBattery = false;
          this.settingBackgroundType = globalTextUseBgImage ? BackgroundType.IMAGE : BackgroundType.COLOR;
          this.settingBackgroundImagePath = globalTextBgImagePath;
          this.settingBackgroundImageOpacity = globalTextBgImageOpacity;
        } else {
          // 其他格式：使用电子书全局设置
          logger.info(TAG, `无保存设置，应用全局设置: 主题索引=${globalThemeIndex}, 字体大小=${globalFontSize}`);
          
          this.settingFontSize = globalFontSize;
          this.settingFontFamily = DEFAULT_EBOOK_READING_SETTINGS.fontFamily;
          this.settingFontPath = '';
          this.settingFontWeight = DEFAULT_EBOOK_READING_SETTINGS.fontWeight || 400;
          this.settingLineHeight = globalLineHeight;
          this.settingBgColor = themePreset.backgroundColor;
          this.settingTextColor = themePreset.textColor;
          this.settingThemeBgImage = themePreset.themeBgImage || '';
          this.settingNightMode = themePreset.nightMode;
          this.selectedThemeIndex = globalThemeIndex;
          this.settingPageMargin = globalPageMargin;
          this.settingPageMode = globalPageMode;
          this.settingAutoSave = DEFAULT_EBOOK_READING_SETTINGS.autoSave;
          this.settingSaveInterval = DEFAULT_EBOOK_READING_SETTINGS.saveInterval;
          
          // 纯文本阅读器专用设置使用默认值
          this.settingLetterSpacing = 0;
          this.settingParagraphSpacing = 8;
          this.settingFirstLineIndent = 2;
          this.settingTextAlignment = TextAlignment.JUSTIFY;
          this.settingPageTurnAnimation = TextPageTurnAnimation.SLIDE;
          this.settingTapToTurn = true;
          this.settingVolumeKeyNavigation = true;
          this.settingKeepScreenOn = false;
          this.settingShowPageNumber = true;
          this.settingShowProgress = false;
          this.settingShowTime = true;
          this.settingShowBattery = false;
          this.settingBackgroundType = BackgroundType.COLOR;
          this.settingBackgroundImagePath = '';
          this.settingBackgroundImageOpacity = 0.3;
        }
      }

      logger.info(TAG, `电子书设置加载完成: ${ebook.metadata.title}`);
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      logger.error(TAG, this.errorMessage);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 即时保存设置到数据库
   * 每次设置变更时自动调用，无需手动点击保存按钮
   */
  private async saveSettingsImmediately(): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      // 更新设置
      const newSettings: EBookReadingSettings = {
        // 字体设置
        fontSize: this.settingFontSize,
        fontFamily: this.settingFontFamily,
        fontPath: this.settingFontPath,
        fontWeight: this.settingFontWeight,
        // 排版设置
        lineHeight: this.settingLineHeight,
        // 颜色主题设置
        backgroundColor: this.settingBgColor,
        textColor: this.settingTextColor,
        themeBgImage: this.settingThemeBgImage,
        nightMode: this.settingNightMode,
        // 翻页设置
        pageMargin: this.settingPageMargin,
        pageMode: this.settingPageMode,
        // 系统设置
        brightness: this.settingBrightness,
        autoSave: this.settingAutoSave,
        saveInterval: this.settingSaveInterval,
        followSystemTheme: false,
        
        // ========== 纯文本阅读器专用设置 ==========
        // 高级字体设置
        letterSpacing: this.settingLetterSpacing,
        paragraphSpacing: this.settingParagraphSpacing,
        firstLineIndent: this.settingFirstLineIndent,
        textAlignment: this.settingTextAlignment,
        // 翻页动画设置
        pageTurnAnimation: this.settingPageTurnAnimation,
        tapToTurn: this.settingTapToTurn,
        volumeKeyNavigation: this.settingVolumeKeyNavigation,
        keepScreenOn: this.settingKeepScreenOn,
        // 显示设置
        showPageNumber: this.settingShowPageNumber,
        showProgress: this.settingShowProgress,
        showTime: this.settingShowTime,
        showBattery: this.settingShowBattery,
        // 背景设置
        backgroundType: this.settingBackgroundType,
        backgroundImagePath: this.settingBackgroundImagePath,
        backgroundImageOpacity: this.settingBackgroundImageOpacity
      };

      this.ebook.readingSettings = newSettings;
      await this.ebookDataManager.saveEBook(this.ebook);
      
      // [修复] 发布电子书更新事件，通知其他页面刷新
      eventBus.publish(GameEvent.EBOOK_UPDATED, new BasePayload());
      
      logger.debug(TAG, '设置已即时保存');
    } catch (error) {
      logger.error(TAG, `即时保存设置失败: ${String(error)}`);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        if (this.isLoading) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            this.buildLoadingView()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        } else if (this.errorMessage.length > 0) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            this.buildErrorView()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        } else if (this.isLandscape) {
          // 横屏布局：左边40%电子书信息，右边60%设置选项
          Row() {
            // 左侧：电子书封面和基本信息
            Scroll() {
              Column() {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildEBookInfoSection()
              }
              .width('100%')
            }
            .width('40%')
            .height('100%')
            .padding({ left: 16, right: 8 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            
            // 右侧：各种设置选项
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildSettingsContent()
              }
              .width('100%')
              .padding({ bottom: 40 })
            }
            .width('60%')
            .height('100%')
            .padding({ left: 8, right: 16 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .height('100%')
        } else {
          // 竖屏布局：原有布局
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(TITLE_BAR_HEIGHT_MINI)
              this.buildEBookInfoSection()
              this.buildSettingsContent()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 40 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as EBookSettingsPageParams | null;
      if (param && param.bookId) {
        this.loadSettings(param.bookId);
      } else {
        this.errorMessage = '无效的电子书ID';
        this.isLoading = false;
      }
    })
    .backgroundColor(Color.Transparent)
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '电子书设置' }
      }
    })
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(60)
        .height(60)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建错误视图
   */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Text(this.errorMessage)
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
        .height(40)
        .onClick(() => {
          this.pathStack.pop();
        })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }

  /**
   * 检查是否为 PDF 格式
   */
  private isPdfFormat(): boolean {
    return this.ebook?.format === EBookFormat.PDF;
  }

  /**
   * 检查是否为纯文本格式（TXT等使用自定义文本阅读器）
   */
  private isTextFormat(): boolean {
    const format = this.ebook?.format;
    return format === EBookFormat.TXT;
  }

  /**
   * 构建设置内容
   * 根据电子书格式显示不同的设置选项
   */
  @Builder
  buildSettingsContent() {
    Column({ space: 16 }) {
      // PDF 格式显示专用设置
      if (this.isPdfFormat()) {
        this.buildPdfSettingsContent()
      } else if (this.isTextFormat()) {
        // 纯文本格式显示文本阅读器设置
        this.buildTextReaderSettingsContent()
      } else {
        // 其他格式显示标准设置
        this.buildStandardSettingsContent()
      }
    }
    .width('100%')
  }

  /**
   * 构建 PDF 专用设置内容
   */
  @Builder
  buildPdfSettingsContent() {
    // PDF 格式提示
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_pdf'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('PDF 文档设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text('PDF 文档使用系统 PDF 阅读器进行渲染，部分设置可能不适用。')
        .fontSize(13)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // PDF 显示设置
    Column({ space: 12 }) {
      Text('显示设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildPdfDisplaySettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 阅读设置（自动保存等）
    Column({ space: 12 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildReadingSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

  }

  /**
   * 构建 PDF 显示设置
   */
  @Builder
  buildPdfDisplaySettings() {
    Column({ space: 16 }) {
      // 页面适配模式（PDF Kit 支持）
      Row() {
        Text('页面适配')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text('适应宽度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      // 连续滚动
      Row() {
        Text('连续滚动')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(false) // PDF Kit 默认启用连续滚动
      }
      .width('100%')

      // 显示滚动条
      Row() {
        Text('显示滚动条')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(false) // PDF Kit 默认显示滚动条
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建标准设置内容（非 PDF 格式）
   */
  @Builder
  buildStandardSettingsContent() {
    // 字体设置
    Column({ space: 12 }) {
      Text('字体设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildFontSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 主题设置
    Column({ space: 12 }) {
      Text('主题设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildThemeSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 翻页设置
    Column({ space: 12 }) {
      Text('翻页设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildFlipModeSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 阅读设置
    Column({ space: 12 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

        this.buildReadingSettings()
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

    }
  

  /**
   * 构建主题设置
   */
  @Builder
  buildThemeSettings() {
    Column({ space: 16 }) {
      // 预设主题选择
      Text('选择主题')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(EBOOK_THEME_PRESETS, (theme: EBookThemePreset, index: number) => {
          Column() {
            Stack() {
              Column()
                .width(40)
                .height(40)
                .backgroundColor(theme.backgroundColor)
                .borderRadius(20)
                .border({
                  width: this.selectedThemeIndex === index ? 2 : 1,
                  color: this.selectedThemeIndex === index 
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme)
                })
              
              if (this.selectedThemeIndex === index) {
                Image($r('app.media.ic_check'))
                  .width(16)
                  .height(16)
                  .fillColor(theme.nightMode ? '#FFFFFF' : '#000000')
              }
            }
            
            Text(theme.name)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ top: 4 })
          }
          .onClick(() => {
            this.selectedThemeIndex = index;
            this.settingBgColor = theme.backgroundColor;
            this.settingTextColor = theme.textColor;
            this.settingThemeBgImage = theme.themeBgImage;
            this.settingNightMode = theme.nightMode;
            this.saveSettingsImmediately();
          })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
  }

  /**
   * 构建翻页模式设置
   */
  @Builder
  buildFlipModeSettings() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        // 仿真翻页
        Row({ space: 8 }) {
          Radio({ value: 'simulation', group: 'flipMode' })
            .checked(this.settingPageMode === EBookPageMode.SIMULATION)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.settingPageMode = EBookPageMode.SIMULATION;
                this.saveSettingsImmediately();
              }
            })
          Text('仿真翻页')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }

        // 横向滑动
        Row({ space: 8 }) {
          Radio({ value: 'horizontal', group: 'flipMode' })
            .checked(this.settingPageMode === EBookPageMode.HORIZONTAL)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.settingPageMode = EBookPageMode.HORIZONTAL;
                this.saveSettingsImmediately();
              }
            })
          Text('横向滑动')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建字体设置
   */
  @Builder
  buildFontSettings() {
    Column({ space: 16 }) {
      // 字体大小
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingFontSize,
          min: 12,
          max: 32,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingFontSize = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingFontSize}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 行高
      Row() {
        Text('行高')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingLineHeight * 10,
          min: 12,
          max: 30,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingLineHeight = value / 10;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingLineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 页边距（从显示设置移到这里）
      Row() {
        Text('页边距')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingPageMargin,
          min: 8,
          max: 48,
          step: 4
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingPageMargin = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingPageMargin}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建阅读设置
   */
  @Builder
  buildReadingSettings() {
    Column({ space: 16 }) {
      // 自动保存
      Row() {
        Text('自动保存进度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingAutoSave })
          .onChange((isOn: boolean) => {
            this.settingAutoSave = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')

      // 保存间隔
      if (this.settingAutoSave) {
        Row() {
          Text('保存间隔')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width(80)

          Slider({
            value: this.settingSaveInterval,
            min: 10,
            max: 120,
            step: 10
          })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.settingSaveInterval = value;
              this.saveSettingsImmediately();
            })

          Text(`${this.settingSaveInterval}秒`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width(50)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 从相册选择封面图片
   */
  private async selectCoverImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择封面图片');
      
      // 获取UIAbilityContext
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      // 创建图片选择器
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new picker.PhotoViewPicker(context);
      const selectResult = await photoPicker.select(photoSelectOptions);
      
      if (!selectResult || selectResult.photoUris.length === 0) {
        logger.info(TAG, '未选择图片');
        return;
      }

      const selectedUri: string = selectResult.photoUris[0] as string;
      logger.info(TAG, `选择了图片: ${selectedUri}`);

      // 复制到电子书目录并重命名为 cover.<ext>
      if (!this.ebook) {
        this.showToast('电子书数据不存在');
        return;
      }
      
      const ebookId: string = this.ebook.id;
      const sandbox: SandboxManager = SandboxManager.getInstance();
      const ebooksDir: string = sandbox.getDirectory('ebooks');
      const safeTitle: string = this.sanitizeFileName(this.ebook.metadata.title || ebookId);
      const ebookRoot: string = `${ebooksDir}/${safeTitle}`;
      await sandbox.createDirectory(ebookRoot);

      const ext: string = this.getFileExtension(selectedUri);
      const coverTarget: string = `${ebookRoot}/cover${ext.length > 0 ? '.' + ext : ''}`;
      if (await sandbox.exists(coverTarget)) {
        await sandbox.deleteFile(coverTarget);
      }
      await sandbox.copyFile(selectedUri, coverTarget);

      // 更新数据库与页面状态
      await this.ebookDataManager.updateEBookCover(ebookId, coverTarget);
      this.coverImagePath = coverTarget;
      if (this.ebook) {
        this.ebook.metadata.coverImagePath = coverTarget;
      }
      
      // [修复] 发布封面变更事件，通知其他页面刷新
      eventBus.publish(GameEvent.EBOOK_COVER_CHANGED, new BasePayload());
      
      this.showToast('封面已更新');
      logger.info(TAG, '封面图片更新成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `选择封面图片失败: ${errorMessage}`);
      this.showToast('选择封面失败');
    }
  }

  /**
   * 获取文件扩展名
   */
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    if (lastDot === -1 || lastDot === filePath.length - 1) {
      return '';
    }
    return filePath.substring(lastDot + 1).toLowerCase();
  }

  /**
   * 清理文件名中的非法字符
   */
  private sanitizeFileName(name: string): string {
    return name.replace(/[\\/:*?"<>|]/g, '_').trim();
  }

  /**
   * 显示Toast提示
   */
  private showToast(message: string): void {
    try {
      import('@kit.ArkUI').then((arkUI) => {
        arkUI.promptAction.showToast({ message: message, duration: 2000 });
      });
    } catch (error) {
      logger.error(TAG, `显示Toast失败: ${String(error)}`);
    }
  }

  /**
   * 获取封面图片源
   * 支持沙箱路径、媒体资源路径和网络URL
   */
  private getCoverImageSource(): string | Resource {
    const coverPath = this.ebook?.metadata.coverImagePath;
    if (!coverPath || coverPath.length === 0) {
      return $r('app.media.ic_ebook');
    }
    
    // 检查是否为媒体资源路径 (app.media.xxx 格式)
    if (coverPath.startsWith('app.media.')) {
      // 提取资源名称并返回 Resource 类型
      const resourceName = coverPath.replace('app.media.', '');
      // 使用动态资源引用
      return $r(`app.media.${resourceName}`);
    }
    
    // 沙箱路径需要添加 file:// 前缀
    if (coverPath.startsWith('/')) {
      return `file://${coverPath}`;
    }
    
    // 其他情况（如网络URL）直接返回
    return coverPath;
  }

  /**
   * 获取显示用的封面路径
   * 优先使用 @State coverImagePath，确保封面更新后 UI 能响应式刷新
   */
  private getDisplayCoverPath(): string {
    return this.coverImagePath || this.ebook?.metadata.coverImagePath || '';
  }

  /**
   * 计算电子书整体阅读进度百分比
   * 考虑章节数量，基于当前章节索引和章节内进度计算整体进度
   * 与 EBookDetailPage 保持一致的计算方法
   */
  private calculateOverallProgress(): number {
    if (!this.ebook || !this.ebook.readingProgress) {
      return 0;
    }

    const totalChapters = this.ebook.chapters.length;
    if (totalChapters === 0) {
      // 没有章节信息时，直接返回存储的进度值
      return Math.floor(this.ebook.readingProgress.progress);
    }

    const progress = this.ebook.readingProgress;
    const currentChapterIndex = progress.currentChapterIndex;
    const chapterProgress = progress.progress;

    // 计算整体进度：已完成的章节数 + 当前章节的进度比例
    const completedChapters = currentChapterIndex;
    const currentChapterContribution = chapterProgress / 100;
    const overallProgress = ((completedChapters + currentChapterContribution) / totalChapters) * 100;

    return Math.floor(Math.min(overallProgress, 100));
  }

  /**
   * 检查是否有阅读进度
   */
  private hasReadingProgress(): boolean {
    if (!this.ebook || !this.ebook.readingProgress) {
      return false;
    }
    const progress = this.ebook.readingProgress;
    if (progress.domPos && progress.domPos.length > 0) {
      return true;
    }
    if (progress.currentChapterIndex > 0) {
      return true;
    }
    if (progress.progress > 0) {
      return true;
    }
    return false;
  }

  /**
   * 构建电子书信息展示区域
   */
  @Builder
  buildEBookInfoSection() {
    if (this.ebook) {
      Column({ space: 16 }) {
        // 封面图片 - 使用 @State coverImagePath 来确保封面更新后 UI 能响应式刷新
        Stack() {
          if (this.getDisplayCoverPath().length > 0) {
            // 根据路径类型选择不同的图片加载方式
            if (this.getDisplayCoverPath().startsWith('app.media.')) {
              // 媒体资源路径 - 使用 $r() 加载
              Image($r(`app.media.${this.getDisplayCoverPath().replace('app.media.', '')}`))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
            } else {
              // 沙箱路径或网络URL - 使用 key 强制刷新图片
              Image(this.getDisplayCoverPath().startsWith('/') 
                ? `file://${this.getDisplayCoverPath()}` 
                : this.getDisplayCoverPath())
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .key(`ebook_cover_${this.coverImagePath}`)
            }
          } else {
            Column() {
              Image($r('app.media.ic_ebook'))
                .width(50)
                .height(50)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .height('100%')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width(100)
        .height(150)
        .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

        // 从相册选择封面按钮
        Button('从相册选择封面')
          .width('80%')
          .height(36)
          .fontSize(14)
          .type(ButtonType.Normal)
          .borderRadius(18)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .onClick(() => { this.selectCoverImage(); })

        // 标题
        Text(this.ebook.metadata.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)

        // 作者
        Text(this.ebook.metadata.author)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)

        // 格式标签
        Row({ space: 8 }) {
          Text(this.ebook.format)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(4)

          Text(`${this.ebook.chapters.length}章`)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .borderRadius(4)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // 阅读进度 - 使用与 EBookDetailPage 一致的计算方法
        if (this.hasReadingProgress()) {
          Column({ space: 4 }) {
            Text(`已读 ${this.calculateOverallProgress()}%`)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Progress({
              value: this.calculateOverallProgress(),
              total: 100,
              type: ProgressType.Linear
            })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }

  /**
   * 构建纯文本阅读器设置内容
   * 提供与 TextReaderSettingsPanel 相同的设置选项
   */
  @Builder
  buildTextReaderSettingsContent() {
    // 格式提示
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_ebook'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('纯文本阅读器设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text('纯文本格式使用自定义阅读器，支持丰富的个性化设置。')
        .fontSize(13)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 字体设置
    Column({ space: 12 }) {
      Text('字体设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildTextFontSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 背景设置
    Column({ space: 12 }) {
      Text('背景设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildTextBackgroundSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 翻页设置
    Column({ space: 12 }) {
      Text('翻页设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildTextPageTurnSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 显示设置
    Column({ space: 12 }) {
      Text('显示设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildTextDisplaySettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 阅读设置
    Column({ space: 12 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildReadingSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

  }

  /**
   * 构建纯文本字体设置
   */
  @Builder
  buildTextFontSettings() {
    Column({ space: 16 }) {
      // 字体大小
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingFontSize,
          min: 12,
          max: 36,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingFontSize = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingFontSize}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 行高
      Row() {
        Text('行高')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingLineHeight * 10,
          min: 12,
          max: 30,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingLineHeight = value / 10;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingLineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 字间距
      Row() {
        Text('字间距')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingLetterSpacing,
          min: 0,
          max: 5,
          step: 0.5
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingLetterSpacing = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingLetterSpacing.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 段落间距
      Row() {
        Text('段落间距')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingParagraphSpacing,
          min: 0,
          max: 24,
          step: 2
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingParagraphSpacing = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingParagraphSpacing}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 首行缩进
      Row() {
        Text('首行缩进')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingFirstLineIndent,
          min: 0,
          max: 4,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingFirstLineIndent = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingFirstLineIndent}字`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 字体粗细
      Row() {
        Text('字体粗细')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingFontWeight,
          min: 300,
          max: 700,
          step: 100
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingFontWeight = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingFontWeight}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 文字对齐
      Column({ space: 8 }) {
        Text('文字对齐')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          ForEach([
            { text: '左对齐', align: TextAlignment.LEFT },
            { text: '居中', align: TextAlignment.CENTER },
            { text: '右对齐', align: TextAlignment.RIGHT },
            { text: '两端', align: TextAlignment.JUSTIFY }
          ] as AlignmentSettingOption[], (item: AlignmentSettingOption) => {
            Button(item.text)
              .fontSize(12)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(this.settingTextAlignment === item.align ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.settingTextAlignment === item.align ?
                Color.White :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.settingTextAlignment = item.align;
                this.saveSettingsImmediately();
              })
          })
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建纯文本背景设置
   */
  @Builder
  buildTextBackgroundSettings() {
    Column({ space: 16 }) {
      // 预设背景颜色
      Text('预设背景')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(PRESET_BACKGROUNDS, (preset: PresetBackground) => {
          Column() {
            Stack() {
              Column()
                .width(40)
                .height(40)
                .backgroundColor(preset.backgroundColor)
                .borderRadius(20)
                .border({
                  width: this.settingBgColor === preset.backgroundColor ? 2 : 1,
                  color: this.settingBgColor === preset.backgroundColor
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme)
                })

              if (this.settingBgColor === preset.backgroundColor && this.settingBackgroundType === BackgroundType.COLOR) {
                Image($r('app.media.ic_check'))
                  .width(16)
                  .height(16)
                  .fillColor(isDarkBackground(preset.backgroundColor) ? '#FFFFFF' : '#000000')
              }
            }

            Text(preset.name)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ top: 4 })
          }
          .onClick(() => {
            this.settingBackgroundType = BackgroundType.COLOR;
            this.settingBgColor = preset.backgroundColor;
            this.settingTextColor = preset.textColor;
            this.settingNightMode = isDarkBackground(preset.backgroundColor);
            this.saveSettingsImmediately();
          })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 自定义背景图片
      Row() {
        Text('使用背景图片')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingBackgroundType === BackgroundType.IMAGE })
          .onChange((isOn: boolean) => {
            this.settingBackgroundType = isOn ? BackgroundType.IMAGE : BackgroundType.COLOR;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')

      if (this.settingBackgroundType === BackgroundType.IMAGE) {
        // 背景图片不透明度
        Row() {
          Text('图片不透明度')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width(100)

          Slider({
            value: this.settingBackgroundImageOpacity * 100,
            min: 10,
            max: 100,
            step: 5
          })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.settingBackgroundImageOpacity = value / 100;
              this.saveSettingsImmediately();
            })

          Text(`${Math.round(this.settingBackgroundImageOpacity * 100)}%`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width(50)
            .textAlign(TextAlign.End)
        }
        .width('100%')

        // 选择背景图片按钮
        Button('选择背景图片')
          .width('100%')
          .height(40)
          .fontSize(14)
          .type(ButtonType.Normal)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.selectBackgroundImage();
          })

        // 当前背景图片预览
        if (this.settingBackgroundImagePath && this.settingBackgroundImagePath.length > 0) {
          Column({ space: 8 }) {
            Text('当前背景图片')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')

            // 沙箱路径需要添加 file:// 前缀
            Image(this.settingBackgroundImagePath.startsWith('/') 
              ? 'file://' + this.settingBackgroundImagePath 
              : this.settingBackgroundImagePath)
              .width('100%')
              .height(120)
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
  }

  /**
   * 选择背景图片
   */
  private async selectBackgroundImage(): Promise<void> {
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new picker.PhotoViewPicker(context);
      const selectResult = await photoPicker.select(photoSelectOptions);

      if (selectResult && selectResult.photoUris.length > 0) {
        const sourceUri = selectResult.photoUris[0];
        // 将图片复制到沙箱目录
        const savedPath = await this.copyImageToSandbox(sourceUri, context);
        if (savedPath) {
          this.settingBackgroundImagePath = savedPath;
          this.saveSettingsImmediately();
          this.showToast('背景图片已保存');
        }
      }
    } catch (error) {
      logger.error(TAG, `选择背景图片失败: ${String(error)}`);
      this.showToast('选择背景图片失败');
    }
  }

  /**
   * 将图片复制到沙箱目录
   */
  private async copyImageToSandbox(sourceUri: string, context: common.UIAbilityContext): Promise<string | null> {
    try {
      const cacheDir = context.cacheDir;
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(2, 8);
      const destPath = `${cacheDir}/bg_${timestamp}_${randomStr}.jpg`;

      logger.info(TAG, `准备复制图片: ${sourceUri} -> ${destPath}`);

      // 打开源文件（PhotoViewPicker 返回的 URI 需要只读权限打开）
      const srcFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      logger.info(TAG, `源文件打开成功, fd: ${srcFile.fd}`);

      // 使用 copyFileSync(fd, path) 方式复制
      fs.copyFileSync(srcFile.fd, destPath);
      logger.info(TAG, `copyFileSync 完成`);

      // 关闭源文件
      fs.closeSync(srcFile);

      // 验证复制结果
      const stat = fs.statSync(destPath);
      logger.info(TAG, `图片复制成功: ${destPath}, 大小: ${stat.size} 字节`);

      return destPath;
    } catch (error) {
      logger.error(TAG, `复制图片到沙箱失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 构建纯文本翻页设置
   */
  @Builder
  buildTextPageTurnSettings() {
    Column({ space: 16 }) {
      // 翻页动画
      Column({ space: 8 }) {
        Text('翻页动画')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          ForEach([
            { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
            { text: '卷曲', anim: TextPageTurnAnimation.CURL },
            { text: '淡入淡出', anim: TextPageTurnAnimation.FADE },
            { text: '无', anim: TextPageTurnAnimation.NONE }
          ] as AnimationSettingOption[], (item: AnimationSettingOption) => {
            Button(item.text)
              .fontSize(12)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(this.settingPageTurnAnimation === item.anim ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.settingPageTurnAnimation === item.anim ?
                Color.White :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.settingPageTurnAnimation = item.anim;
                this.saveSettingsImmediately();
              })
          })
        }
        .width('100%')
      }
      .width('100%')

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 点击翻页
      Row() {
        Text('点击翻页')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingTapToTurn })
          .onChange((isOn: boolean) => {
            this.settingTapToTurn = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')

      // 音量键翻页
      Row() {
        Text('音量键翻页')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingVolumeKeyNavigation })
          .onChange((isOn: boolean) => {
            this.settingVolumeKeyNavigation = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')

      // 屏幕常亮
      Row() {
        Text('保持屏幕常亮')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingKeepScreenOn })
          .onChange((isOn: boolean) => {
            this.settingKeepScreenOn = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建纯文本显示设置
   */
  @Builder
  buildTextDisplaySettings() {
    Column({ space: 16 }) {
      // 页边距
      Row() {
        Text('页边距')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingPageMargin,
          min: 8,
          max: 48,
          step: 4
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingPageMargin = value;
            this.saveSettingsImmediately();
          })

        Text(`${this.settingPageMargin}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 底部信息显示
      Column({ space: 8 }) {
        Text('底部信息显示')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        // 右下角显示选项（页码/进度/不显示，三选一）
        Text('右下角显示')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          Button('页码')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(this.settingShowPageNumber ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(this.settingShowPageNumber ?
              Color.White :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.settingShowPageNumber = true;
              this.settingShowProgress = false;
              this.saveSettingsImmediately();
            })

          Button('进度')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(!this.settingShowPageNumber && this.settingShowProgress ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(!this.settingShowPageNumber && this.settingShowProgress ?
              Color.White :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.settingShowPageNumber = false;
              this.settingShowProgress = true;
              this.saveSettingsImmediately();
            })

          Button('不显示')
            .fontSize(12)
            .height(32)
            .layoutWeight(1)
            .backgroundColor(!this.settingShowPageNumber && !this.settingShowProgress ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(!this.settingShowPageNumber && !this.settingShowProgress ?
              Color.White :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.settingShowPageNumber = false;
              this.settingShowProgress = false;
              this.saveSettingsImmediately();
            })
        }
        .width('100%')
      }
      .width('100%')

      // 显示时间
      Row() {
        Text('显示时间 (底部中央)')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingShowTime })
          .onChange((isOn: boolean) => {
            this.settingShowTime = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')

      // 显示电量
      Row() {
        Text('显示电量 (左下角)')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingShowBattery })
          .onChange((isOn: boolean) => {
            this.settingShowBattery = isOn;
            this.saveSettingsImmediately();
          })
      }
      .width('100%')
    }
    .width('100%')
  }
}

// 已经在 struct 定义时导出，不需要重复导出
