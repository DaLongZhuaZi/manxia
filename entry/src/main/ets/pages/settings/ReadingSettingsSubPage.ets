// 文件: entry/src/main/ets/pages/settings/ReadingSettingsSubPage.ets
/**
 * 阅读设置子页面
  * 聚合漫画、电子书与小说阅读全局配置。
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { ReadingMode, ReadingDirection, DEFAULT_READING_SETTINGS, PageTurnAnimationType, DoublePagePortraitLayout } from '../../Models/MangaModels';
import { EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, DEFAULT_EBOOK_READING_SETTINGS } from '../../Models/EBookModels';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import {
  TextPageTurnAnimation,
  TextAlignment,
  PRESET_BACKGROUNDS,
  PresetBackground,
  DEFAULT_TEXT_READER_SETTINGS,
  DEFAULT_READ_ALOUD_SETTINGS,
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  mergeRemoteReadAloudSettings,
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudSettings,
  TextReadingMode,
  BackgroundType,
  TextReaderSettings,
  normalizeReadAloudSettings
} from '../../Models/TextReaderModels';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { EBookDataManager, BackgroundImageInfo } from '../../Framework/Data/EBookDataManager';
import { fileIo } from '@kit.CoreFileKit';
import { ReadAloudAvailability, ReadAloudEngineAvailabilityMap } from '../../Framework/ReadAloud/ReadAloudAvailability';
import { ReadAloudController } from '../../Framework/ReadAloud/ReadAloudController';
import { ReadAloudVoiceOption } from '../../Framework/ReadAloud/ReadAloudTypes';
import { loadGlobalReadAloudSettings, persistGlobalReadAloudSettings } from '../../Framework/ReadAloud/ReadAloudSettingsStore';
import { ReadAloudSettingsInfoPanel } from '../../components/ReadAloudSettingsInfoPanel';
import { getFontManager, SystemFont, CustomFont } from '../../Framework/Managers/FontManager';
import { SettingsSearchSupport } from './SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'ReadingSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 页面参数
interface ReadingSettingsSubPageParams {
  fromPage?: string;
}

// 漫画翻页动画选项
interface PageTurnAnimationOption {
  type: PageTurnAnimationType;
  label: string;
}

// 文字翻页动画选项
interface TextAnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

interface TextReadingModeOption {
  mode: TextReadingMode;
  label: string;
}

@Component
export struct ReadingSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;

  // 主题与字体状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'ReadingSettingsSubPage';
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private readAloudController: ReadAloudController = ReadAloudController.getInstance();
  private fontManager = getFontManager();

  // 鍝嶅簲寮忓竷灞€鐘舵€?
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 漫画默认阅读设置
  @State defaultReadingMode: ReadingMode = DEFAULT_READING_SETTINGS.readingMode;
  @State defaultReadingDirection: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
  @State defaultBrightness: number = DEFAULT_READING_SETTINGS.brightness;
  @State keepScreenOn: boolean = DEFAULT_READING_SETTINGS.keepScreenOn;
  @State volumeKeyNavigation: boolean = DEFAULT_READING_SETTINGS.volumeKeyNavigation;
  @State defaultPageTurnAnimation: PageTurnAnimationType = DEFAULT_READING_SETTINGS.pageTurnAnimation;
  @State mangaDoublePagePortraitLayout: DoublePagePortraitLayout = DEFAULT_READING_SETTINGS.doublePagePortraitLayout;
  @State mangaPageSpacing: number = DEFAULT_READING_SETTINGS.pageSpacing;
  @State mangaShowPageInfo: boolean = DEFAULT_READING_SETTINGS.showPageInfo;
  @State mangaShowPageIndicator: boolean = DEFAULT_READING_SETTINGS.showPageIndicator;
  @State mangaFitMode: string = DEFAULT_READING_SETTINGS.fitMode;
  @State mangaAutoPageTurnInterval: number = DEFAULT_READING_SETTINGS.autoPageTurnInterval;
  @State mangaSkipIntroPages: number = DEFAULT_READING_SETTINGS.skipIntroPages;
  @State mangaCurlBackOpacity: number = DEFAULT_READING_SETTINGS.curlBackOpacity;
  @State mangaWebtoonLeftMargin: number = DEFAULT_READING_SETTINGS.webtoonLeftMargin;
  @State mangaWebtoonRightMargin: number = DEFAULT_READING_SETTINGS.webtoonRightMargin;
  @State mangaWebtoonMarginSync: boolean = DEFAULT_READING_SETTINGS.webtoonMarginSync;

  // 电子书默认设置
  @State ebookFontSize: number = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
  @State ebookLineHeight: number = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
  @State ebookPageMargin: number = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
  @State ebookThemeIndex: number = 0;
  @State ebookPageMode: EBookPageMode = DEFAULT_EBOOK_READING_SETTINGS.pageMode;

  // 文字阅读默认设置
  @State textFontSize: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize;
  @State textLineHeight: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.lineHeight;
  @State textParagraphSpacing: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing;
  @State textFirstLineIndent: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent;
  @State textLetterSpacing: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing;
  @State textFontFamily: string = DEFAULT_TEXT_READER_SETTINGS.textStyle.fontFamily;
  @State textFontWeight: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.fontWeight;
  @State textAlignment: TextAlignment = DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment;
  @State textPageMargin: number = DEFAULT_TEXT_READER_SETTINGS.pageMargins.left;
  @State textTopMargin: number = DEFAULT_TEXT_READER_SETTINGS.pageMargins.top;
  @State textBottomMargin: number = DEFAULT_TEXT_READER_SETTINGS.pageMargins.bottom;
  @State textReadingMode: TextReadingMode = DEFAULT_TEXT_READER_SETTINGS.readingMode;
  @State textBgColorIndex: number = 0;
  @State textTextColor: string = DEFAULT_TEXT_READER_SETTINGS.textStyle.textColor;
  @State textPageTurnAnimation: TextPageTurnAnimation = DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation;
  @State textKeepScreenOn: boolean = DEFAULT_TEXT_READER_SETTINGS.keepScreenOn;
  @State textVolumeKeyNav: boolean = DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation;
  @State textTapToTurn: boolean = DEFAULT_TEXT_READER_SETTINGS.tapToTurn;
  @State textAutoPageTurnEnabled: boolean = DEFAULT_TEXT_READER_SETTINGS.autoPageTurnEnabled ?? false;
  @State textAutoPageTurnInterval: number = DEFAULT_TEXT_READER_SETTINGS.autoPageTurnInterval ?? 8;
  @State textBgImagePath: string = '';
  @State textBgImageOpacity: number = 0.3;
  @State textUseBgImage: boolean = false;
  // 底部信息栏显示设置
  @State textShowTime: boolean = true;
  @State textShowBattery: boolean = true;
  @State textShowPageNumber: boolean = true;
  @State textShowProgress: boolean = false;
  // 听书默认设置
  @State textReadAloudEnabled: boolean = DEFAULT_READ_ALOUD_SETTINGS.enabled;
  @State textReadAloudEngine: ReadAloudEngineType = DEFAULT_READ_ALOUD_SETTINGS.engineType;
  @State textReadAloudSpeed: number = DEFAULT_READ_ALOUD_SETTINGS.speed;
  @State textReadAloudPitch: number = DEFAULT_READ_ALOUD_SETTINGS.pitch;
  @State textReadAloudVolume: number = DEFAULT_READ_ALOUD_SETTINGS.volume;
  @State textReadAloudVoiceLanguage: string = DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage ?? '';
  @State textReadAloudVoicePerson: number = DEFAULT_READ_ALOUD_SETTINGS.voicePerson ?? -1;
  @State textReadAloudVoiceOnline: number = DEFAULT_READ_ALOUD_SETTINGS.voiceOnline ?? -1;
  @State textReadAloudContinueBg: boolean = DEFAULT_READ_ALOUD_SETTINGS.continueInBackground;
  @State textReadAloudAutoNextChapter: boolean = DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter;
  @State textReadAloudPauseOnManualPageTurn: boolean = DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn;
  @State textReadAloudRemote: RemoteReadAloudSettings = DEFAULT_REMOTE_READ_ALOUD_SETTINGS;
  @State textReadAloudAvailability: ReadAloudEngineAvailabilityMap = ReadAloudAvailability.getCachedOrDefault();
  @State textReadAloudVoiceOptions: ReadAloudVoiceOption[] = [];
  @State showReadAloudPanel: boolean = false;
  @State textReadAloudStatusMessage: string = '';
  @State novelSystemFonts: SystemFont[] = [];
  @State novelCustomFonts: CustomFont[] = [];
  
  // 背景图管理状态
  @State allBackgroundImages: BackgroundImageInfo[] = [];
  @State showBackgroundManager: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '已成功获取 GlobalNavStack');
      }
      this.refreshNovelFontOptions();
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  onReady(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化响应式布局
    this.initializeResponsiveLayout();

    // 加载全局设置
    this.loadGlobalSettings();
    this.refreshNovelFontOptions();
    this.refreshReadAloudAvailability();
    this.applyPendingSearchTarget();
  }

  private lifecycle = new PageLifecycleManager('ReadingSettingsSubPage', { enableDebug: true });

  private markSettingsScrolling(): void {
    if (this.settingsTapEnabled) {
      this.settingsTapEnabled = false;
    }
    if (this.settingsTapUnlockTimer >= 0) {
      clearTimeout(this.settingsTapUnlockTimer);
    }
    this.settingsTapUnlockTimer = setTimeout(() => {
      this.settingsTapEnabled = true;
      this.settingsTapUnlockTimer = -1;
    }, this.scrollTapGuardDurationMs);
  }

  private cleanupSettingsTapGuard(): void {
    if (this.settingsTapUnlockTimer >= 0) {
      clearTimeout(this.settingsTapUnlockTimer);
      this.settingsTapUnlockTimer = -1;
    }
    this.settingsTapEnabled = true;
  }

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 注销设备监听
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('ReadingSettingsSubPage');
    if (!target) {
      return;
    }
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 420 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 160);
  }

  /**
   * 初始化响应式布局参数与监听
   */
  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
    * 鏇存柊鍝嶅簲寮忓弬鏁?
   */
  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}`);
  }

  private refreshNovelFontOptions(): void {
    try {
      this.novelSystemFonts = this.fontManager.getSystemFonts();
      this.novelCustomFonts = this.fontManager.getCustomFonts();
    } catch (error) {
      logger.warn(TAG, `刷新小说字体列表失败: ${String(error)}`);
      this.novelSystemFonts = [];
      this.novelCustomFonts = [];
    }
  }

  private getTextFontDisplayName(fontFamily: string): string {
    const systemFont = this.novelSystemFonts.find((font: SystemFont) => font.name === fontFamily);
    if (systemFont) {
      return systemFont.displayName;
    }
    const customFont = this.novelCustomFonts.find((font: CustomFont) => font.familyName === fontFamily);
    if (customFont) {
      return customFont.displayName;
    }
    return fontFamily;
  }

  /**
   * 加载全局阅读设置
   */
  private normalizeMangaReadingDirection(mode: ReadingMode, direction: ReadingDirection): ReadingDirection {
    const normalizedDirection = direction === ReadingDirection.VERTICAL
      ? ReadingDirection.TOP_TO_BOTTOM
      : direction;
    if (mode === ReadingMode.DOUBLE_PAGE && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    if (mode === ReadingMode.WEBTOON && normalizedDirection !== ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.TOP_TO_BOTTOM;
    }
    if (mode === ReadingMode.CONTINUOUS_SCROLL && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    return normalizedDirection;
  }

  private isTopToBottomMangaDirectionDisabled(): boolean {
    return this.defaultReadingMode === ReadingMode.CONTINUOUS_SCROLL ||
      this.defaultReadingMode === ReadingMode.DOUBLE_PAGE;
  }

  private isHorizontalMangaDirectionDisabled(): boolean {
    return this.defaultReadingMode === ReadingMode.WEBTOON;
  }

  private getSelectedMangaReadingDirection(): ReadingDirection {
    return this.normalizeMangaReadingDirection(
      this.defaultReadingMode,
      this.defaultReadingDirection
    );
  }

  private getMangaDirectionHint(): string {
    if (this.defaultReadingMode === ReadingMode.CONTINUOUS_SCROLL) {
      return '连续滚动仅支持从左到右或从右到左';
    }
    if (this.isHorizontalMangaDirectionDisabled()) {
      return '条漫模式仅支持从上到下';
    }
    if (this.defaultReadingMode === ReadingMode.DOUBLE_PAGE) {
      return '双页模式不支持从上到下';
    }
    return '';
  }

  private loadGlobalSettings(): void {
    try {
      // 漫画全局设置
      this.defaultReadingMode = this.settingsManager.getString(
        SettingKeys.GLOBAL_READING_MODE,
        DEFAULT_READING_SETTINGS.readingMode
      ) as ReadingMode;

      this.defaultReadingDirection = this.settingsManager.getString(
        SettingKeys.GLOBAL_READING_DIRECTION,
        DEFAULT_READING_SETTINGS.readingDirection
      ) as ReadingDirection;
      const normalizedMangaDirection = this.normalizeMangaReadingDirection(
        this.defaultReadingMode,
        this.defaultReadingDirection
      );
      if (normalizedMangaDirection !== this.defaultReadingDirection) {
        this.defaultReadingDirection = normalizedMangaDirection;
        this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
      }

      this.defaultBrightness = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_BRIGHTNESS,
        DEFAULT_READING_SETTINGS.brightness
      );

      this.keepScreenOn = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_KEEP_SCREEN_ON,
        DEFAULT_READING_SETTINGS.keepScreenOn
      );

      this.volumeKeyNavigation = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION,
        DEFAULT_READING_SETTINGS.volumeKeyNavigation
      );

      this.defaultPageTurnAnimation = this.settingsManager.getString(
        SettingKeys.GLOBAL_PAGE_TURN_ANIMATION,
        DEFAULT_READING_SETTINGS.pageTurnAnimation
      ) as PageTurnAnimationType;
      this.mangaDoublePagePortraitLayout = this.settingsManager.getString(
        SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT,
        DEFAULT_READING_SETTINGS.doublePagePortraitLayout
      ) as DoublePagePortraitLayout;
      this.mangaPageSpacing = Math.max(0, Math.min(50, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_PAGE_SPACING,
        DEFAULT_READING_SETTINGS.pageSpacing
      ))));
      this.mangaShowPageInfo = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INFO,
        DEFAULT_READING_SETTINGS.showPageInfo
      );
      this.mangaShowPageIndicator = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INDICATOR,
        DEFAULT_READING_SETTINGS.showPageIndicator
      );
      this.mangaFitMode = this.settingsManager.getString(
        SettingKeys.GLOBAL_MANGA_FIT_MODE,
        DEFAULT_READING_SETTINGS.fitMode
      );
      this.mangaAutoPageTurnInterval = Math.max(0, Math.min(60, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_AUTO_PAGE_TURN_INTERVAL,
        DEFAULT_READING_SETTINGS.autoPageTurnInterval
      ))));
      this.mangaSkipIntroPages = Math.max(0, Math.min(20, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_SKIP_INTRO_PAGES,
        DEFAULT_READING_SETTINGS.skipIntroPages
      ))));
      this.mangaCurlBackOpacity = Math.max(50, Math.min(100, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_CURL_BACK_OPACITY,
        DEFAULT_READING_SETTINGS.curlBackOpacity
      ))));
      this.mangaWebtoonLeftMargin = Math.max(0, Math.min(50, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN,
        DEFAULT_READING_SETTINGS.webtoonLeftMargin
      ))));
      this.mangaWebtoonRightMargin = Math.max(0, Math.min(50, Math.round(this.settingsManager.getNumber(
        SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN,
        DEFAULT_READING_SETTINGS.webtoonRightMargin
      ))));
      this.mangaWebtoonMarginSync = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_MANGA_WEBTOON_MARGIN_SYNC,
        DEFAULT_READING_SETTINGS.webtoonMarginSync
      );

      // 电子书全局设置
      this.ebookFontSize = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_EBOOK_FONT_SIZE,
        DEFAULT_EBOOK_READING_SETTINGS.fontSize
      );

      this.ebookLineHeight = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT,
        DEFAULT_EBOOK_READING_SETTINGS.lineHeight
      );

      this.ebookPageMargin = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN,
        DEFAULT_EBOOK_READING_SETTINGS.pageMargin
      );

      this.ebookThemeIndex = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_EBOOK_THEME,
        0
      );

      this.ebookPageMode = this.settingsManager.getString(
        SettingKeys.GLOBAL_EBOOK_PAGE_MODE,
        DEFAULT_EBOOK_READING_SETTINGS.pageMode
      ) as EBookPageMode;

      const globalNovelSettings = this.settingsManager.getJSON<TextReaderSettings>(
        SettingKeys.NOVEL_READER_SETTINGS,
        DEFAULT_TEXT_READER_SETTINGS
      );

      // 文字阅读全局设置
      this.textFontSize = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_FONT_SIZE,
        globalNovelSettings.textStyle.fontSize
      );
      this.textFontFamily = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_FONT_FAMILY,
        globalNovelSettings.textStyle.fontFamily
      );
      this.textFontWeight = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_FONT_WEIGHT,
        globalNovelSettings.textStyle.fontWeight
      );
      this.textLineHeight = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_LINE_HEIGHT,
        globalNovelSettings.textStyle.lineHeight
      );
      this.textParagraphSpacing = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING,
        globalNovelSettings.textStyle.paragraphSpacing
      );
      this.textFirstLineIndent = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT,
        globalNovelSettings.textStyle.firstLineIndent
      );
      this.textLetterSpacing = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_LETTER_SPACING,
        globalNovelSettings.textStyle.letterSpacing
      );
      this.textAlignment = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_ALIGNMENT,
        globalNovelSettings.textStyle.textAlignment
      ) as TextAlignment;
      this.textPageMargin = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_PAGE_MARGIN,
        globalNovelSettings.pageMargins.left
      );
      this.textTopMargin = globalNovelSettings.pageMargins.top;
      this.textBottomMargin = globalNovelSettings.pageMargins.bottom;
      this.textReadingMode = globalNovelSettings.readingMode;
      this.textBgColorIndex = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_BG_COLOR,
        0
      );
      this.textTextColor = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_TEXT_COLOR,
        globalNovelSettings.textStyle.textColor
      );
      this.textPageTurnAnimation = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION,
        globalNovelSettings.pageTurnAnimation
      ) as TextPageTurnAnimation;
      this.textKeepScreenOn = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON,
        globalNovelSettings.keepScreenOn
      );
      this.textVolumeKeyNav = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV,
        globalNovelSettings.volumeKeyNavigation
      );
      this.textTapToTurn = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_TAP_TO_TURN,
        globalNovelSettings.tapToTurn
      );
      this.textAutoPageTurnEnabled = globalNovelSettings.autoPageTurnEnabled ?? false;
      this.textAutoPageTurnInterval = Math.max(1, Math.min(60, Math.round(globalNovelSettings.autoPageTurnInterval ?? 8)));
      this.textBgImagePath = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH,
        globalNovelSettings.background.imagePath ?? ''
      );
      this.textBgImageOpacity = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY,
        globalNovelSettings.background.imageOpacity ?? 0.3
      );
      this.textUseBgImage = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE,
        globalNovelSettings.background.type === BackgroundType.IMAGE && this.textBgImagePath.length > 0
      );
      // 底部信息栏设置
      this.textShowTime = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_SHOW_TIME,
        true
      );
      this.textShowBattery = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_SHOW_BATTERY,
        true
      );
      this.textShowPageNumber = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_SHOW_PAGE_NUMBER,
        true
      );
      this.textShowProgress = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_SHOW_PROGRESS,
        false
      );
      const globalReadAloud = loadGlobalReadAloudSettings(this.settingsManager);
      this.textReadAloudEnabled = globalReadAloud.enabled;
      this.textReadAloudEngine = globalReadAloud.engineType;
      this.textReadAloudSpeed = globalReadAloud.speed;
      this.textReadAloudPitch = globalReadAloud.pitch;
      this.textReadAloudVolume = globalReadAloud.volume;
      this.textReadAloudVoiceLanguage = globalReadAloud.voiceLanguage ?? '';
      this.textReadAloudVoicePerson = globalReadAloud.voicePerson ?? -1;
      this.textReadAloudVoiceOnline = globalReadAloud.voiceOnline ?? -1;
      this.textReadAloudContinueBg = globalReadAloud.continueInBackground;
      this.textReadAloudAutoNextChapter = globalReadAloud.autoPlayNextChapter;
      this.textReadAloudPauseOnManualPageTurn = globalReadAloud.pauseOnManualPageTurn;
      this.textReadAloudRemote = globalReadAloud.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS;

      this.persistGlobalNovelReaderSettings().catch((error: Object | string) => {
        logger.warn(TAG, `同步全局小说设置失败: ${String(error)}`);
      });
      logger.info(TAG, '阅读设置加载完成');
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  private refreshReadAloudAvailability(): void {
    ReadAloudAvailability.refresh(false, this.buildGlobalReadAloudSettings()).then((map: ReadAloudEngineAvailabilityMap) => {
      this.textReadAloudAvailability = map;
      if (!map.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.textReadAloudStatusMessage = `系统 TTS 探测失败：${probeError}`;
        }
      }
      if (!map.REMOTE && this.textReadAloudEngine === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.textReadAloudStatusMessage = `远程 TTS 不可用：${probeError}`;
        }
      }
      if (!this.isReadAloudEngineAvailable(this.textReadAloudEngine)) {
        if (this.isReadAloudEngineAvailable(ReadAloudEngineType.SYSTEM)) {
          this.textReadAloudEngine = ReadAloudEngineType.SYSTEM;
        } else {
          this.textReadAloudEnabled = false;
        }
      }
      this.refreshReadAloudVoices();
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新听书引擎可用性失败: ${errorText}`);
      this.textReadAloudStatusMessage = `引擎可用性探测失败：${errorText}`;
    });
  }

  private isReadAloudEngineAvailable(engineType: ReadAloudEngineType): boolean {
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return this.textReadAloudAvailability.SYSTEM === true;
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return this.textReadAloudAvailability.LEGADO_COMPAT === true;
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      return this.textReadAloudAvailability.REMOTE === true;
    }
    return false;
  }

  private refreshReadAloudVoices(): void {
    if (!this.isReadAloudEngineAvailable(this.textReadAloudEngine)) {
      this.textReadAloudVoiceOptions = [];
      if (this.textReadAloudEngine === ReadAloudEngineType.SYSTEM) {
        const probeError = ReadAloudAvailability.getLastSystemProbeErrorMessage();
        if (probeError.length > 0) {
          this.textReadAloudStatusMessage = `系统 TTS 探测失败：${probeError}`;
        } else {
          this.textReadAloudStatusMessage = '系统 TTS 当前不可用，请点击刷新重试';
        }
      } else if (this.textReadAloudEngine === ReadAloudEngineType.REMOTE) {
        const probeError = ReadAloudAvailability.getLastRemoteProbeErrorMessage();
        if (probeError.length > 0) {
          this.textReadAloudStatusMessage = `远程 TTS 不可用：${probeError}`;
        } else {
          this.textReadAloudStatusMessage = '远程 TTS 当前不可用，请检查 endpoint/model/voice/apiKey';
        }
      } else {
        this.textReadAloudStatusMessage = '当前引擎不可用，请切换到“系统”或点击刷新重试';
      }
      return;
    }
    this.readAloudController.listVoices(this.textReadAloudEngine).then((voices: ReadAloudVoiceOption[]) => {
      this.textReadAloudVoiceOptions = voices;
      if (voices.length > 0) {
        this.textReadAloudStatusMessage = '';
      } else if (this.textReadAloudEngine === ReadAloudEngineType.SYSTEM) {
        this.textReadAloudStatusMessage = '系统 TTS 可直接朗读，但系统未返回可选音色';
      } else {
        this.textReadAloudStatusMessage = '当前引擎暂未返回音色列表';
      }
    }).catch((error: Object | string) => {
      const errorText = this.formatReadAloudError(error);
      logger.warn(TAG, `刷新全局听书音色列表失败: ${errorText}`);
      this.textReadAloudVoiceOptions = [];
      this.textReadAloudStatusMessage = `音色列表拉取失败：${errorText}`;
    });
  }

  private formatReadAloudError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorObj = error as Error;
    if (errorObj.message && errorObj.message.length > 0) {
      return errorObj.message;
    }
    try {
      const jsonText = JSON.stringify(error);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (_ignored) {
    }
    return String(error);
  }

  private buildGlobalReadAloudSettings(): ReadAloudSettings {
    return normalizeReadAloudSettings({
      enabled: this.textReadAloudEnabled,
      engineType: this.textReadAloudEngine,
      speed: this.textReadAloudSpeed,
      pitch: this.textReadAloudPitch,
      volume: this.textReadAloudVolume,
      continueInBackground: this.textReadAloudContinueBg,
      autoPlayNextChapter: this.textReadAloudAutoNextChapter,
      pauseOnManualPageTurn: this.textReadAloudPauseOnManualPageTurn,
      voiceLanguage: this.textReadAloudVoiceLanguage,
      voicePerson: this.textReadAloudVoicePerson,
      voiceOnline: this.textReadAloudVoiceOnline,
      remote: this.textReadAloudRemote
    });
  }

  private getReadAloudSummary(): string {
    const readAloud = this.buildGlobalReadAloudSettings();
    let engineLabel: string = '系统';
    if (readAloud.engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      engineLabel = '兼容';
    } else if (readAloud.engineType === ReadAloudEngineType.REMOTE) {
      engineLabel = '远程';
    }
    const enabledText = readAloud.enabled ? '已启用' : '未启用';
    return `${enabledText} · ${engineLabel} · 语速${readAloud.speed.toFixed(1)}x`;
  }

  private mergeReadAloudSettings(current: ReadAloudSettings, partial: Partial<ReadAloudSettings>): ReadAloudSettings {
    const currentRemote = current.remote;
    const partialRemote = partial.remote;
    let mergedRemote = currentRemote;
    if (partialRemote && currentRemote) {
      mergedRemote = mergeRemoteReadAloudSettings(currentRemote, partialRemote);
    }
    return normalizeReadAloudSettings({
      enabled: partial.enabled ?? current.enabled,
      engineType: partial.engineType ?? current.engineType,
      speed: partial.speed ?? current.speed,
      pitch: partial.pitch ?? current.pitch,
      volume: partial.volume ?? current.volume,
      continueInBackground: partial.continueInBackground ?? current.continueInBackground,
      autoPlayNextChapter: partial.autoPlayNextChapter ?? current.autoPlayNextChapter,
      pauseOnManualPageTurn: partial.pauseOnManualPageTurn ?? current.pauseOnManualPageTurn,
      voiceLanguage: partial.voiceLanguage ?? current.voiceLanguage,
      voicePerson: partial.voicePerson ?? current.voicePerson,
      voiceOnline: partial.voiceOnline ?? current.voiceOnline,
      remote: mergedRemote
    });
  }

  private applyGlobalReadAloudSettings(partial: Partial<ReadAloudSettings>): void {
    const current = this.buildGlobalReadAloudSettings();
    const next = this.mergeReadAloudSettings(current, partial);

    this.textReadAloudEnabled = next.enabled;
    this.textReadAloudEngine = next.engineType;
    this.textReadAloudSpeed = next.speed;
    this.textReadAloudPitch = next.pitch;
    this.textReadAloudVolume = next.volume;
    this.textReadAloudVoiceLanguage = next.voiceLanguage ?? '';
    this.textReadAloudVoicePerson = next.voicePerson ?? -1;
    this.textReadAloudVoiceOnline = next.voiceOnline ?? -1;
    this.textReadAloudContinueBg = next.continueInBackground;
    this.textReadAloudAutoNextChapter = next.autoPlayNextChapter;
    this.textReadAloudPauseOnManualPageTurn = next.pauseOnManualPageTurn;
    this.textReadAloudRemote = next.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS;

    this.persistGlobalReadAloudPartial(partial).catch((error: Object | string) => {
      logger.warn(TAG, `持久化全局听书设置失败: ${String(error)}`);
    });

    const shouldRefreshAvailability = partial.engineType !== undefined || partial.remote !== undefined;
    if (shouldRefreshAvailability) {
      this.refreshReadAloudAvailability();
      return;
    }
    if (
      partial.voiceLanguage !== undefined ||
      partial.voicePerson !== undefined ||
      partial.voiceOnline !== undefined
    ) {
      this.refreshReadAloudVoices();
    }
  }

  private async persistGlobalReadAloudPartial(partial: Partial<ReadAloudSettings>): Promise<void> {
    const current = this.buildGlobalReadAloudSettings();
    const next = this.mergeReadAloudSettings(current, partial);
    await persistGlobalReadAloudSettings(this.settingsManager, next);
    await this.persistGlobalNovelReaderSettings();
  }

  private clampTextAutoPageTurnInterval(value: number): number {
    return Math.max(1, Math.min(60, Math.round(value)));
  }

  private getFileNameFromPath(path: string): string {
    const slashIndex = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
    if (slashIndex >= 0 && slashIndex < path.length - 1) {
      return path.substring(slashIndex + 1);
    }
    return path;
  }

  private resolveTextBackgroundColor(): string {
    if (this.textBgColorIndex >= 0 && this.textBgColorIndex < PRESET_BACKGROUNDS.length) {
      return PRESET_BACKGROUNDS[this.textBgColorIndex].backgroundColor;
    }
    return DEFAULT_TEXT_READER_SETTINGS.background.color ?? '#F5F0E1';
  }

  private async copyBackgroundImageToSandbox(sourceUri: string): Promise<string> {
    const context = getContext(this) as common.UIAbilityContext;
    const cacheDir = context.cacheDir;
    const timestamp = Date.now();
    const randomSuffix = Math.floor(Math.random() * 100000).toString();
    let extension = '.jpg';
    const dotIndex = sourceUri.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < sourceUri.length - 1) {
      extension = sourceUri.substring(dotIndex);
    }
    const targetPath = `${cacheDir}/novel_global_bg_${timestamp}_${randomSuffix}${extension}`;
    const sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    fs.copyFileSync(sourceFile.fd, targetPath);
    fs.closeSync(sourceFile);
    return targetPath;
  }

  private async selectNovelBackgroundImage(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (!result.photoUris || result.photoUris.length === 0) {
        return;
      }
      const sourceUri = result.photoUris[0];
      const savedPath = await this.copyBackgroundImageToSandbox(sourceUri);
      this.textBgImagePath = savedPath;
      this.textUseBgImage = true;
      await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, this.textBgImagePath);
      await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, this.textUseBgImage);
      await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, this.textBgImageOpacity);
      await this.persistGlobalNovelReaderSettings();
      promptAction.showToast({ message: '已设置全局背景图', duration: 1500 });
    } catch (error) {
      logger.error(TAG, `选择全局背景图失败: ${String(error)}`);
      promptAction.showToast({ message: '选择背景图失败', duration: 1500 });
    }
  }

  private buildGlobalNovelReaderSettings(): TextReaderSettings {
    const currentGlobalSettings = this.settingsManager.getJSON<TextReaderSettings>(
      SettingKeys.NOVEL_READER_SETTINGS,
      DEFAULT_TEXT_READER_SETTINGS
    );
    const pageMargin = Math.max(8, Math.min(64, Math.round(this.textPageMargin)));
    const topMargin = Math.max(0, Math.min(96, Math.round(this.textTopMargin)));
    const bottomMargin = Math.max(0, Math.min(96, Math.round(this.textBottomMargin)));
    const textReadAloud = this.buildGlobalReadAloudSettings();
    const useBgImage = this.textUseBgImage && this.textBgImagePath.length > 0;
    const resolvedTextColor = this.textTextColor.length > 0
      ? this.textTextColor
      : DEFAULT_TEXT_READER_SETTINGS.textStyle.textColor;

    let backgroundType: BackgroundType = BackgroundType.COLOR;
    let backgroundColor: string | undefined = this.resolveTextBackgroundColor();
    let backgroundImagePath: string | undefined = undefined;
    let backgroundImageOpacity: number | undefined = this.textBgImageOpacity;
    if (useBgImage) {
      backgroundType = BackgroundType.IMAGE;
      backgroundImagePath = this.textBgImagePath;
      backgroundImageOpacity = Math.max(0.1, Math.min(1.0, this.textBgImageOpacity));
      backgroundColor = this.resolveTextBackgroundColor();
    }

    const nextSettings: TextReaderSettings = {
      readingMode: this.textReadingMode,
      readingDirection: currentGlobalSettings.readingDirection ?? DEFAULT_TEXT_READER_SETTINGS.readingDirection,
      pageTurnAnimation: this.textPageTurnAnimation,
      background: {
        type: backgroundType,
        color: backgroundColor,
        imagePath: backgroundImagePath,
        imageOpacity: backgroundImageOpacity
      },
      savedBackgroundImages: currentGlobalSettings.savedBackgroundImages ?? DEFAULT_TEXT_READER_SETTINGS.savedBackgroundImages,
      textStyle: {
        fontSize: Math.max(12, Math.min(40, Math.round(this.textFontSize))),
        lineHeight: Math.max(1.0, Math.min(3.0, this.textLineHeight)),
        paragraphSpacing: Math.max(0, Math.min(40, Math.round(this.textParagraphSpacing))),
        firstLineIndent: Math.max(0, Math.min(6, Math.round(this.textFirstLineIndent))),
        letterSpacing: Math.max(-2, Math.min(8, this.textLetterSpacing)),
        textColor: resolvedTextColor,
        fontWeight: Math.max(100, Math.min(900, Math.round(this.textFontWeight))),
        fontFamily: this.textFontFamily,
        textAlignment: this.textAlignment
      },
      pageMargins: {
        top: topMargin,
        bottom: bottomMargin,
        left: pageMargin,
        right: pageMargin
      },
      keepScreenOn: this.textKeepScreenOn,
      showPageNumber: this.textShowPageNumber,
      showProgress: this.textShowProgress,
      showTime: this.textShowTime,
      showBattery: this.textShowBattery,
      tapToTurn: this.textTapToTurn,
      volumeKeyNavigation: this.textVolumeKeyNav,
      autoScrollSpeed: currentGlobalSettings.autoScrollSpeed ?? DEFAULT_TEXT_READER_SETTINGS.autoScrollSpeed,
      autoPageTurnEnabled: this.textAutoPageTurnEnabled,
      autoPageTurnInterval: this.clampTextAutoPageTurnInterval(this.textAutoPageTurnInterval),
      curlBackOpacity: currentGlobalSettings.curlBackOpacity ?? DEFAULT_TEXT_READER_SETTINGS.curlBackOpacity,
      readAloud: textReadAloud
    };
    return nextSettings;
  }

  private async persistGlobalNovelReaderSettings(): Promise<void> {
    const nextSettings = this.buildGlobalNovelReaderSettings();
    await this.settingsManager.setJSON<TextReaderSettings>(SettingKeys.NOVEL_READER_SETTINGS, nextSettings);
    this.settingsManager.syncToAppStorage();
  }

  private async updateNovelBottomDisplayMode(mode: 'page' | 'progress' | 'none'): Promise<void> {
    if (mode === 'page') {
      this.textShowPageNumber = true;
      this.textShowProgress = false;
    } else if (mode === 'progress') {
      this.textShowPageNumber = false;
      this.textShowProgress = true;
    } else {
      this.textShowPageNumber = false;
      this.textShowProgress = false;
    }
    await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_SHOW_PAGE_NUMBER, this.textShowPageNumber);
    await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_SHOW_PROGRESS, this.textShowProgress);
    await this.persistGlobalNovelReaderSettings();
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
    * 漫画阅读设置
   */
  @Builder
  buildMangaReadingSettings() {
    Column({ space: 16 }) {
            Text('漫画默认设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 阅读模式
      Column({ space: 8 }) {
        Text('默认阅读模式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          Button({ stateEffect: true }) {
            Text('单页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.SINGLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.SINGLE_PAGE;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                this.defaultReadingDirection
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('双页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.DOUBLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.DOUBLE_PAGE;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                this.defaultReadingDirection
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('连续滚动')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(80)
            .height(36)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.CONTINUOUS_SCROLL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.CONTINUOUS_SCROLL;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              const normalizedDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                this.defaultReadingDirection
              );
              if (normalizedDirection !== this.defaultReadingDirection) {
                this.defaultReadingDirection = normalizedDirection;
                await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              }
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('条漫模式')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.WEBTOON
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.WEBTOON;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                this.defaultReadingDirection
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }

      // 阅读方向
      Column({ space: 8 }) {
        Text('默认阅读方向')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        if (this.getMangaDirectionHint().length > 0) {
          Text(this.getMangaDirectionHint())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
        Text('从左到右')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.getSelectedMangaReadingDirection() === ReadingDirection.LEFT_TO_RIGHT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .opacity(this.isHorizontalMangaDirectionDisabled() ? 0.4 : 1.0)
            .onClick(async () => {
              if (this.isHorizontalMangaDirectionDisabled()) {
                return;
              }
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                ReadingDirection.LEFT_TO_RIGHT
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
        Text('从右到左')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.getSelectedMangaReadingDirection() === ReadingDirection.RIGHT_TO_LEFT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .opacity(this.isHorizontalMangaDirectionDisabled() ? 0.4 : 1.0)
            .onClick(async () => {
              if (this.isHorizontalMangaDirectionDisabled()) {
                return;
              }
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                ReadingDirection.RIGHT_TO_LEFT
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
      Text('从上到下')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.getSelectedMangaReadingDirection() === ReadingDirection.TOP_TO_BOTTOM
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .opacity(this.isTopToBottomMangaDirectionDisabled() ? 0.4 : 1.0)
            .onClick(async () => {
              if (this.isTopToBottomMangaDirectionDisabled()) {
                return;
              }
              this.defaultReadingDirection = this.normalizeMangaReadingDirection(
                this.defaultReadingMode,
                ReadingDirection.TOP_TO_BOTTOM
              );
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Row() {
          Text('默认亮度')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${Math.round(this.defaultBrightness * 100)}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: Math.round(this.defaultBrightness * 100),
          min: 10,
          max: 200,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.defaultBrightness = Math.max(0.1, Math.min(2.0, value / 100));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_BRIGHTNESS, this.defaultBrightness);
            this.settingsManager.syncToAppStorage();
          })
      }

      // 翻页动画
      Column({ space: 8 }) {
          Text('默认翻页动画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach([
            { type: PageTurnAnimationType.NONE, label: '无' },
            { type: PageTurnAnimationType.SLIDE, label: '滑动' },
            { type: PageTurnAnimationType.FADE, label: '淡入' },
            { type: PageTurnAnimationType.CURL, label: '卷页' },
            { type: PageTurnAnimationType.CUBE, label: '立方' },
            { type: PageTurnAnimationType.COVER, label: '覆盖' },
            { type: PageTurnAnimationType.DEPTH, label: '景深' }
          ], (item: PageTurnAnimationOption) => {
            Button({ stateEffect: true }) {
              Text(item.label)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
            }
              .width(70)
              .height(32)
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(
                this.defaultPageTurnAnimation === item.type
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
              )
              .borderRadius(6)
              .onClick(async () => {
                this.defaultPageTurnAnimation = item.type;
                await this.settingsManager.setString(SettingKeys.GLOBAL_PAGE_TURN_ANIMATION, this.defaultPageTurnAnimation);
                this.settingsManager.syncToAppStorage();
              })
          })
        }
        .width('100%')
      }

      // 閫氱敤寮€鍏?
      Row() {
          Text('保持屏幕常亮')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.keepScreenOn })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.keepScreenOn = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
          Text('音量键翻页')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.volumeKeyNavigation })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.volumeKeyNavigation = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('显示页码信息')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.mangaShowPageInfo })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.mangaShowPageInfo = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INFO, this.mangaShowPageInfo);
            if (!isOn) {
              this.mangaShowPageIndicator = false;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INDICATOR, false);
            }
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('显示页面指示器')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.mangaShowPageIndicator })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.mangaShowPageIndicator = isOn;
            if (isOn && !this.mangaShowPageInfo) {
              this.mangaShowPageInfo = true;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INFO, true);
            }
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_MANGA_SHOW_PAGE_INDICATOR, this.mangaShowPageIndicator);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 8 }) {
        Row() {
          Text('双页竖屏组合')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('上下组合')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.mangaDoublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.mangaDoublePagePortraitLayout = DoublePagePortraitLayout.VERTICAL;
              await this.settingsManager.setString(SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT, this.mangaDoublePagePortraitLayout);
              this.settingsManager.syncToAppStorage();
            })
          Button({ stateEffect: true }) {
            Text('左右组合')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.mangaDoublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.mangaDoublePagePortraitLayout = DoublePagePortraitLayout.HORIZONTAL;
              await this.settingsManager.setString(SettingKeys.GLOBAL_MANGA_DOUBLE_PAGE_PORTRAIT_LAYOUT, this.mangaDoublePagePortraitLayout);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Row() {
          Text('页面间距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.mangaPageSpacing}px`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaPageSpacing,
          min: 0,
          max: 50,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaPageSpacing = Math.max(0, Math.min(50, Math.round(value)));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_PAGE_SPACING, this.mangaPageSpacing);
            this.settingsManager.syncToAppStorage();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('自动翻页间隔')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.mangaAutoPageTurnInterval === 0 ? '禁用' : `${this.mangaAutoPageTurnInterval}秒`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaAutoPageTurnInterval,
          min: 0,
          max: 60,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaAutoPageTurnInterval = Math.max(0, Math.min(60, Math.round(value)));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_AUTO_PAGE_TURN_INTERVAL, this.mangaAutoPageTurnInterval);
            this.settingsManager.syncToAppStorage();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('跳过开篇页数')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.mangaSkipIntroPages}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaSkipIntroPages,
          min: 0,
          max: 20,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaSkipIntroPages = Math.max(0, Math.min(20, Math.round(value)));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_SKIP_INTRO_PAGES, this.mangaSkipIntroPages);
            this.settingsManager.syncToAppStorage();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('卷页背面不透明度')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.mangaCurlBackOpacity}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaCurlBackOpacity,
          min: 50,
          max: 100,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaCurlBackOpacity = Math.max(50, Math.min(100, Math.round(value)));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_CURL_BACK_OPACITY, this.mangaCurlBackOpacity);
            this.settingsManager.syncToAppStorage();
          })
      }

      Column({ space: 8 }) {
        Text('图片适配模式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('适宽')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.mangaFitMode === 'fit_width'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.mangaFitMode = 'fit_width';
              await this.settingsManager.setString(SettingKeys.GLOBAL_MANGA_FIT_MODE, this.mangaFitMode);
              this.settingsManager.syncToAppStorage();
            })
          Button({ stateEffect: true }) {
            Text('适高')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.mangaFitMode === 'fit_height'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.mangaFitMode = 'fit_height';
              await this.settingsManager.setString(SettingKeys.GLOBAL_MANGA_FIT_MODE, this.mangaFitMode);
              this.settingsManager.syncToAppStorage();
            })
          Button({ stateEffect: true }) {
            Text('原始')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.mangaFitMode === 'original'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.mangaFitMode = 'original';
              await this.settingsManager.setString(SettingKeys.GLOBAL_MANGA_FIT_MODE, this.mangaFitMode);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }

      Row() {
        Text('条漫边距左右同步')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.mangaWebtoonMarginSync })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.mangaWebtoonMarginSync = isOn;
            if (isOn) {
              this.mangaWebtoonRightMargin = this.mangaWebtoonLeftMargin;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN, this.mangaWebtoonRightMargin);
            }
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_MANGA_WEBTOON_MARGIN_SYNC, this.mangaWebtoonMarginSync);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN, this.mangaWebtoonLeftMargin);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 8 }) {
        Row() {
          Text('条漫左边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.mangaWebtoonLeftMargin}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaWebtoonLeftMargin,
          min: 0,
          max: 50,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaWebtoonLeftMargin = Math.max(0, Math.min(50, Math.round(value)));
            if (this.mangaWebtoonMarginSync) {
              this.mangaWebtoonRightMargin = this.mangaWebtoonLeftMargin;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN, this.mangaWebtoonRightMargin);
            }
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN, this.mangaWebtoonLeftMargin);
            this.settingsManager.syncToAppStorage();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('条漫右边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.mangaWebtoonRightMargin}%`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.mangaWebtoonRightMargin,
          min: 0,
          max: 50,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.mangaWebtoonRightMargin = Math.max(0, Math.min(50, Math.round(value)));
            if (this.mangaWebtoonMarginSync) {
              this.mangaWebtoonLeftMargin = this.mangaWebtoonRightMargin;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_LEFT_MARGIN, this.mangaWebtoonLeftMargin);
            }
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_MANGA_WEBTOON_RIGHT_MARGIN, this.mangaWebtoonRightMargin);
            this.settingsManager.syncToAppStorage();
          })
      }
    }
    .width('100%')
    .padding(16)
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

  /**
    * 电子书阅读设置
   */
  @Builder
  buildEBookSettings() {
    Column({ space: 16 }) {
        Text('电子书默认设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 页面模式
      Column({ space: 8 }) {
        Row() {
        Text('默认字体大小')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookFontSize}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.ebookFontSize,
          min: 12,
          max: 32,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.ebookFontSize = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, this.ebookFontSize);
            this.settingsManager.syncToAppStorage();
          })
      }

      // 行高
      Column({ space: 8 }) {
        Row() {
          Text('默认行高')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookLineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.ebookLineHeight * 10,
          min: 12,
          max: 30,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.ebookLineHeight = value / 10;
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, this.ebookLineHeight);
            this.settingsManager.syncToAppStorage();
          })
      }

      // 椤佃竟璺?
      Column({ space: 8 }) {
        Row() {
            Text('默认页边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookPageMargin}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.ebookPageMargin,
          min: 8,
          max: 48,
          step: 4,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.ebookPageMargin = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, this.ebookPageMargin);
            this.settingsManager.syncToAppStorage();
          })
      }

      // 阅读主题
      Column({ space: 8 }) {
            Text('默认阅读主题')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

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
                    width: this.ebookThemeIndex === index ? 2 : 1,
                    color: this.ebookThemeIndex === index 
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                  })
                
                if (this.ebookThemeIndex === index) {
                  Image($r('app.media.ic_check'))
                    .width(16)
                    .height(16)
                    .fillColor(theme.nightMode ? '#FFFFFF' : '#000000')
                }
              }
              
              Text(theme.name)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 4 })
            }
            .onClick(async () => {
              this.ebookThemeIndex = index;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_THEME, this.ebookThemeIndex);
              this.settingsManager.syncToAppStorage();
            })
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
      }

      // 翻页方式
      Column({ space: 8 }) {
        Text('默认翻页模式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Row({ space: 16 }) {
          Row({ space: 8 }) {
            Radio({ value: 'simulation', group: 'ebookFlipMode' })
              .checked(this.ebookPageMode === EBookPageMode.SIMULATION)
              .onChange(async (isChecked: boolean) => {
                if (isChecked) {
                  this.ebookPageMode = EBookPageMode.SIMULATION;
                  await this.settingsManager.setString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, this.ebookPageMode);
                  this.settingsManager.syncToAppStorage();
                }
              })
          Text('仿真翻页')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }

          Row({ space: 8 }) {
            Radio({ value: 'horizontal', group: 'ebookFlipMode' })
              .checked(this.ebookPageMode === EBookPageMode.HORIZONTAL)
              .onChange(async (isChecked: boolean) => {
                if (isChecked) {
                  this.ebookPageMode = EBookPageMode.HORIZONTAL;
                  await this.settingsManager.setString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, this.ebookPageMode);
                  this.settingsManager.syncToAppStorage();
                }
              })
            Text('横向滑动')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
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

  /**
    * 文字阅读设置
   */
  @Builder
  buildTextReaderSettings() {
    Column({ space: 16 }) {
          Text('小说阅读默认设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text('默认字体大小')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textFontSize}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textFontSize,
          min: 12,
          max: 32,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.textFontSize = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, this.textFontSize);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      // 行高
      Column({ space: 8 }) {
        Row() {
          Text('默认行高')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textLineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textLineHeight * 10,
          min: 12,
          max: 30,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.textLineHeight = value / 10;
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, this.textLineHeight);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      // 娈甸棿璺?
      Column({ space: 8 }) {
        Row() {
          Text('段间距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textParagraphSpacing}px`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textParagraphSpacing,
          min: 0,
          max: 32,
          step: 2,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.textParagraphSpacing = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, this.textParagraphSpacing);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      // 首行缩进
      Column({ space: 8 }) {
        Row() {
        Text('首行缩进')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textFirstLineIndent}字符`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textFirstLineIndent,
          min: 0,
          max: 4,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.textFirstLineIndent = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, this.textFirstLineIndent);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      // 椤佃竟璺?
      Column({ space: 8 }) {
        Row() {
        Text('默认页边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textPageMargin}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textPageMargin,
          min: 8,
          max: 48,
          step: 4,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.textPageMargin = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, this.textPageMargin);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      // 背景主题
      Column({ space: 8 }) {
          Text('默认背景色')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(PRESET_BACKGROUNDS, (preset: PresetBackground, index: number) => {
            Column() {
              Stack() {
                Column()
                  .width(40)
                  .height(40)
                  .backgroundColor(preset.backgroundColor)
                  .borderRadius(20)
                  .border({
                    width: this.textBgColorIndex === index && !this.textUseBgImage ? 2 : 1,
                    color: this.textBgColorIndex === index && !this.textUseBgImage
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                  })

                if (this.textBgColorIndex === index && !this.textUseBgImage) {
                  Image($r('app.media.ic_check'))
                    .width(16)
                    .height(16)
                    .fillColor(preset.textColor)
                }
              }

              Text(preset.name)
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 4 })
                .maxLines(1)
            }
            .width(50)
            .margin({ right: 8, bottom: 8 })
            .onClick(async () => {
              this.textBgColorIndex = index;
              this.textUseBgImage = false;
              this.textTextColor = preset.textColor;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, this.textBgColorIndex);
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_TEXT_COLOR, this.textTextColor);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
              await this.persistGlobalNovelReaderSettings();
            })
          })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Row() {
          Text('背景图片')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Button(this.textBgImagePath.length > 0 ? '重新选择' : '选择图片')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .height(32)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
            .onClick(async () => {
              await this.selectNovelBackgroundImage();
            })
        }
        .width('100%')

        Row() {
          Text('启用背景图片')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textUseBgImage && this.textBgImagePath.length > 0 })
            .onChange(async (isOn: boolean) => {
              if (isOn && this.textBgImagePath.length === 0) {
                await this.selectNovelBackgroundImage();
                return;
              }
              this.textUseBgImage = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, this.textUseBgImage);
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')

        if (this.textBgImagePath.length > 0) {
          Text(`已选：${this.getFileNameFromPath(this.textBgImagePath)}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)

          Row() {
            Text('背景图透明度')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${Math.round(this.textBgImageOpacity * 100)}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Slider({
            value: this.textBgImageOpacity * 100,
            min: 10,
            max: 100,
            step: 1,
            style: SliderStyle.InSet
          })
            .onChange(async (value: number) => {
              this.textBgImageOpacity = Math.max(0.1, Math.min(1.0, value / 100));
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, this.textBgImageOpacity);
              await this.persistGlobalNovelReaderSettings();
            })
        }
      }

      Column({ space: 8 }) {
        Text('文字颜色')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(['#333333', '#FFFFFF', '#5D4037', '#2E7D32', '#1565C0', '#D4D4D4'], (color: string) => {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(28)
                .height(28)
                .backgroundColor(color)
                .borderRadius(14)
                .border({
                  width: this.textTextColor === color ? 2 : 1,
                  color: this.textTextColor === color ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                })
              if (this.textTextColor === color) {
                Image($r('app.media.ic_check'))
                  .width(14)
                  .height(14)
                  .fillColor(color === '#FFFFFF' ? '#333333' : '#FFFFFF')
              }
            }
            .margin({ right: 8, bottom: 8 })
            .onClick(async () => {
              this.textTextColor = color;
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_TEXT_COLOR, this.textTextColor);
              await this.persistGlobalNovelReaderSettings();
            })
          })
        }
        .width('100%')
      }

      // 翻页动画
      Column({ space: 8 }) {
          Text('默认翻页动画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach([
            { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
            { text: '卷页', anim: TextPageTurnAnimation.CURL },
            { text: '淡入', anim: TextPageTurnAnimation.FADE },
            { text: '无', anim: TextPageTurnAnimation.NONE }
          ] as TextAnimationOption[], (item: TextAnimationOption) => {
            Button({ stateEffect: true }) {
              Text(item.text)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(this.textPageTurnAnimation === item.anim
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
              .width(70)
              .height(36)
              .backgroundColor(
                this.textPageTurnAnimation === item.anim
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
              )
              .borderRadius(8)
              .margin({ right: 8, bottom: 8 })
              .onClick(async () => {
                this.textPageTurnAnimation = item.anim;
                await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, this.textPageTurnAnimation);
                await this.persistGlobalNovelReaderSettings();
              })
          })
        }
        .width('100%')
      }

      // 文字阅读交互开关
      Column({ space: 12 }) {
        Row() {
          Text('保持屏幕常亮')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textKeepScreenOn })
            .onChange(async (isOn: boolean) => {
              this.textKeepScreenOn = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, this.textKeepScreenOn);
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')

        Row() {
          Text('音量键翻页')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textVolumeKeyNav })
            .onChange(async (isOn: boolean) => {
              this.textVolumeKeyNav = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, this.textVolumeKeyNav);
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')

        Row() {
          Text('点击翻页')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textTapToTurn })
            .onChange(async (isOn: boolean) => {
              this.textTapToTurn = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, this.textTapToTurn);
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Text('默认阅读模式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Row({ space: 8 }) {
          ForEach([
            { mode: TextReadingMode.PAGE, label: '翻页' },
            { mode: TextReadingMode.SCROLL, label: '上下滚动' },
            { mode: TextReadingMode.DUAL_PAGE, label: '双页' }
          ] as TextReadingModeOption[], (item: TextReadingModeOption) => {
            Button({ stateEffect: true }) {
              Text(item.label)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(
                  this.textReadingMode === item.mode
                    ? Color.White
                    : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
                )
            }
              .layoutWeight(1)
              .height(36)
              .backgroundColor(
                this.textReadingMode === item.mode
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
              )
              .borderRadius(6)
              .onClick(async () => {
                this.textReadingMode = item.mode;
                await this.persistGlobalNovelReaderSettings();
              })
          })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Row() {
          Text('字间距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textLetterSpacing.toFixed(1)}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.textLetterSpacing * 10,
          min: -20,
          max: 80,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.textLetterSpacing = value / 10;
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_LETTER_SPACING, this.textLetterSpacing);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      Column({ space: 8 }) {
        Text('文字对齐')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('左对齐')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.textAlignment === TextAlignment.LEFT
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.textAlignment === TextAlignment.LEFT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.textAlignment = TextAlignment.LEFT;
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_ALIGNMENT, this.textAlignment);
              await this.persistGlobalNovelReaderSettings();
            })
          Button({ stateEffect: true }) {
            Text('居中')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.textAlignment === TextAlignment.CENTER
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.textAlignment === TextAlignment.CENTER
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.textAlignment = TextAlignment.CENTER;
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_ALIGNMENT, this.textAlignment);
              await this.persistGlobalNovelReaderSettings();
            })
          Button({ stateEffect: true }) {
            Text('两端')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.textAlignment === TextAlignment.JUSTIFY
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.textAlignment === TextAlignment.JUSTIFY
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.textAlignment = TextAlignment.JUSTIFY;
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_ALIGNMENT, this.textAlignment);
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        Text('字体样式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Row() {
          Text('当前')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(this.getTextFontDisplayName(this.textFontFamily))
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.novelSystemFonts, (font: SystemFont) => {
            Button({ stateEffect: true }) {
              Text(font.displayName)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(
                  this.textFontFamily === font.name
                    ? Color.White
                    : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
                )
            }
              .height(36)
              .margin({ right: 8, bottom: 8 })
              .backgroundColor(
                this.textFontFamily === font.name
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
              )
              .borderRadius(8)
              .onClick(async () => {
                this.textFontFamily = font.name;
                await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_FONT_FAMILY, this.textFontFamily);
                await this.persistGlobalNovelReaderSettings();
              })
          })
        }
        .width('100%')

        if (this.novelCustomFonts.length > 0) {
          Text('自定义字体')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.novelCustomFonts, (font: CustomFont) => {
              Button({ stateEffect: true }) {
                Text(font.displayName)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(
                    this.textFontFamily === font.familyName
                      ? Color.White
                      : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
                  )
              }
                .height(36)
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(
                  this.textFontFamily === font.familyName
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
                )
                .borderRadius(8)
                .onClick(async () => {
                  this.textFontFamily = font.familyName;
                  await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_FONT_FAMILY, this.textFontFamily);
                  await this.persistGlobalNovelReaderSettings();
                })
            })
          }
          .width('100%')
        } else {
          Text('暂无自定义字体，可在字体设置中导入')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }

      Column({ space: 8 }) {
        Row() {
          Text('字体粗细')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textFontWeight}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.textFontWeight,
          min: 100,
          max: 900,
          step: 100,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.textFontWeight = Math.max(100, Math.min(900, Math.round(value / 100) * 100));
            await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_FONT_WEIGHT, this.textFontWeight);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('上边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textTopMargin}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.textTopMargin,
          min: 0,
          max: 96,
          step: 2,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.textTopMargin = Math.max(0, Math.min(96, Math.round(value)));
            await this.persistGlobalNovelReaderSettings();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('下边距')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textBottomMargin}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        Slider({
          value: this.textBottomMargin,
          min: 0,
          max: 96,
          step: 2,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.textBottomMargin = Math.max(0, Math.min(96, Math.round(value)));
            await this.persistGlobalNovelReaderSettings();
          })
      }

      Column({ space: 8 }) {
        Row() {
          Text('自动翻页')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textAutoPageTurnEnabled })
            .onChange(async (isOn: boolean) => {
              this.textAutoPageTurnEnabled = isOn;
              await this.persistGlobalNovelReaderSettings();
            })
        }
        .width('100%')

        Row() {
          Text('自动翻页间隔')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textAutoPageTurnInterval}秒`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.textAutoPageTurnInterval,
          min: 1,
          max: 60,
          step: 1,
          style: SliderStyle.InSet
        })
          .onChange(async (value: number) => {
            this.textAutoPageTurnInterval = this.clampTextAutoPageTurnInterval(value);
            await this.persistGlobalNovelReaderSettings();
          })
      }

      Column({ space: 8 }) {
        Text('底部显示模式')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('页码')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.textShowPageNumber
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.textShowPageNumber
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              await this.updateNovelBottomDisplayMode('page');
            })
          Button({ stateEffect: true }) {
            Text('进度')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                !this.textShowPageNumber && this.textShowProgress
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              !this.textShowPageNumber && this.textShowProgress
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              await this.updateNovelBottomDisplayMode('progress');
            })
          Button({ stateEffect: true }) {
            Text('不显示')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(
                !this.textShowPageNumber && !this.textShowProgress
                  ? Color.White
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              !this.textShowPageNumber && !this.textShowProgress
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              await this.updateNovelBottomDisplayMode('none');
            })
        }
        .width('100%')
      }

      Row() {
        Text('显示时间（底部信息栏）')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.textShowTime })
          .onChange(async (isOn: boolean) => {
            this.textShowTime = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_SHOW_TIME, this.textShowTime);
            await this.persistGlobalNovelReaderSettings();
          })
      }
      .width('100%')

      Row() {
        Text('显示电量（状态栏）')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.textShowBattery })
          .onChange(async (isOn: boolean) => {
            this.textShowBattery = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_SHOW_BATTERY, this.textShowBattery);
            await this.persistGlobalNovelReaderSettings();
          })
      }
      .width('100%')

      Row() {
        Text('听书默认设置')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button(this.getReadAloudSummary())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .height(32)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .onClick(() => {
            this.showReadAloudPanel = true;
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
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
          
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            if (this.responsive_isLandscape) {
              // 横屏双列布局
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                Column({ space: 16 }) {
                  this.buildMangaReadingSettings()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_manga'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_manga') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'reading_manga'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_manga', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_manga', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_manga',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildEBookSettings()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_ebook'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_ebook') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'reading_ebook'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_ebook', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_ebook', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_ebook',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildTextReaderSettings()
                }
                .width('100%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_novel'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_novel') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'reading_novel'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_novel', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_novel', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_novel',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }
              .width('100%')
            } else {
              // 竖屏单列布局
              Column() {
                this.buildMangaReadingSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_manga'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_manga') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_manga'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_manga', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_manga', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_manga',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })

              Column() {
                this.buildEBookSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_ebook'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_ebook') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_ebook'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_ebook', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_ebook', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_ebook',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })

              Column() {
                this.buildTextReaderSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_novel'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'reading_novel') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'reading_novel'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_novel', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'reading_novel', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'reading_novel',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
            }

            Blank().height(40)
          }
          .enabled(this.settingsTapEnabled)
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.showReadAloudPanel) {
          ReadAloudSettingsInfoPanel({
            isLandscape: this.responsive_isLandscape,
            settings: this.buildGlobalReadAloudSettings(),
            availability: this.textReadAloudAvailability,
            voiceOptions: this.textReadAloudVoiceOptions,
            statusMessage: this.textReadAloudStatusMessage,
            appFontFamily: this.appFontFamily,
            callbacks: {
              onClose: () => {
                this.showReadAloudPanel = false;
              },
              onRefresh: () => {
                this.refreshReadAloudAvailability();
              },
              onChange: (partial: Partial<ReadAloudSettings>) => {
                this.applyGlobalReadAloudSettings(partial);
              }
            }
          })
        }
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '阅读设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}
