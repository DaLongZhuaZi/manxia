// 文件路径: entry/src/main/ets/pages/GlobalSettingsPage.ets
/**
 * 全局设置页面
 * 提供应用级别的配置选项，包括阅读设置、下载设置、通知设置等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { common, Want } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
// 已弃用自定义 AnimatedButton，改用原生 ArkUI Button
import { logger } from '../Utils/Logger';
import { ReadingMode, ReadingDirection, DEFAULT_READING_SETTINGS, PageTurnAnimationType } from '../Models/MangaModels';
import { EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, DEFAULT_EBOOK_READING_SETTINGS } from '../Models/EBookModels';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { TextPageTurnAnimation, TextAlignment, PRESET_BACKGROUNDS, PresetBackground, DEFAULT_TEXT_READER_SETTINGS } from '../Models/TextReaderModels';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { WindowManager } from '../Utils/WindowManager';

const TAG = 'GlobalSettingsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 导航参数接口
interface GlobalSettingsPageParams {
  fromPage?: string;
}

// ForEach 使用的接口类型
interface PageTurnAnimationOption {
  type: PageTurnAnimationType;
  label: string;
}

// 纯文本阅读器翻页动画选项接口
interface TextAnimationOption {
  text: string;
  anim: TextPageTurnAnimation;
}

// 使用NavDestinationContext官方类型
// @kit.ArkUI提供的NavDestinationContext已包含必要的类型定义

@Component
struct GlobalSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'GlobalSettingsPage';
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 漫画全局阅读设置
  @State defaultReadingMode: ReadingMode = DEFAULT_READING_SETTINGS.readingMode;
  @State defaultReadingDirection: ReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
  @State defaultBrightness: number = DEFAULT_READING_SETTINGS.brightness;
  @State keepScreenOn: boolean = DEFAULT_READING_SETTINGS.keepScreenOn;
  @State volumeKeyNavigation: boolean = DEFAULT_READING_SETTINGS.volumeKeyNavigation;
  @State defaultPageTurnAnimation: PageTurnAnimationType = DEFAULT_READING_SETTINGS.pageTurnAnimation;

  // 电子书全局阅读设置
  @State ebookFontSize: number = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
  @State ebookLineHeight: number = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
  @State ebookPageMargin: number = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
  @State ebookThemeIndex: number = 0;
  @State ebookPageMode: EBookPageMode = DEFAULT_EBOOK_READING_SETTINGS.pageMode;

  // 纯文本阅读器全局设置
  @State textFontSize: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize;
  @State textLineHeight: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.lineHeight;
  @State textParagraphSpacing: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing;
  @State textFirstLineIndent: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent;
  @State textLetterSpacing: number = DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing;
  @State textAlignment: TextAlignment = DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment;
  @State textPageMargin: number = DEFAULT_TEXT_READER_SETTINGS.pageMargins.left;
  @State textBgColorIndex: number = 0;
  @State textPageTurnAnimation: TextPageTurnAnimation = DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation;
  @State textKeepScreenOn: boolean = DEFAULT_TEXT_READER_SETTINGS.keepScreenOn;
  @State textVolumeKeyNav: boolean = DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation;
  @State textTapToTurn: boolean = DEFAULT_TEXT_READER_SETTINGS.tapToTurn;
  @State textBgImagePath: string = '';
  @State textBgImageOpacity: number = 0.3;
  @State textUseBgImage: boolean = false;

  // 下载设置
  @State downloadOnWifiOnly: boolean = true;
  @State maxConcurrentDownloads: number = 3;
  @State downloadPath: string = '/storage/emulated/0/Download/Manxia';

  // 通知设置
  @State enableDownloadNotifications: boolean = true;
  @State enableUpdateNotifications: boolean = true;

  // 其他设置
  @State autoCheckUpdates: boolean = true;
  @State clearCacheOnExit: boolean = false;
  @State enableLogFloatingWindow: boolean = true;
  @State advancedModeEnabled: boolean = false;
  @State forceTabletMode: boolean = false;
  @State forceLandscapeMode: boolean = false;
  @State showRestartDialog: boolean = false;

  onPageShow(): void {
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
  }

  onReady(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });

    // 初始化响应式布局
    this.initializeResponsiveLayout();

    // 加载保存的全局设置
    this.loadGlobalSettings();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化响应式布局
   */
  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
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

  /**
   * 加载全局设置
   */
  private loadGlobalSettings(): void {
    try {
      // 从SettingsManager加载全局设置
      this.defaultReadingMode = this.settingsManager.getString(
        SettingKeys.GLOBAL_READING_MODE,
        DEFAULT_READING_SETTINGS.readingMode
      ) as ReadingMode;

      this.defaultReadingDirection = this.settingsManager.getString(
        SettingKeys.GLOBAL_READING_DIRECTION,
        DEFAULT_READING_SETTINGS.readingDirection
      ) as ReadingDirection;

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

      this.downloadOnWifiOnly = this.settingsManager.getBoolean(
        SettingKeys.DOWNLOAD_WIFI_ONLY,
        true
      );

      this.maxConcurrentDownloads = this.settingsManager.getNumber(
        SettingKeys.MAX_CONCURRENT_DOWNLOADS,
        3
      );

      this.enableDownloadNotifications = this.settingsManager.getBoolean(
        SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS,
        true
      );

      this.enableUpdateNotifications = this.settingsManager.getBoolean(
        SettingKeys.ENABLE_UPDATE_NOTIFICATIONS,
        true
      );

      this.autoCheckUpdates = this.settingsManager.getBoolean(
        SettingKeys.AUTO_CHECK_UPDATES,
        true
      );

      this.clearCacheOnExit = this.settingsManager.getBoolean(
        SettingKeys.CLEAR_CACHE_ON_EXIT,
        false
      );

      this.enableLogFloatingWindow = this.settingsManager.getBoolean(
        SettingKeys.ENABLE_LOG_FLOATING_WINDOW,
        false
      );

      this.advancedModeEnabled = this.settingsManager.getBoolean(
        SettingKeys.ADVANCED_MODE_ENABLED,
        false
      );

      this.forceTabletMode = this.settingsManager.getBoolean(
        SettingKeys.FORCE_TABLET_MODE,
        false
      );

      this.forceLandscapeMode = this.settingsManager.getBoolean(
        SettingKeys.FORCE_LANDSCAPE_MODE,
        false
      );

      // 加载漫画翻页动画设置
      this.defaultPageTurnAnimation = this.settingsManager.getString(
        SettingKeys.GLOBAL_PAGE_TURN_ANIMATION,
        DEFAULT_READING_SETTINGS.pageTurnAnimation
      ) as PageTurnAnimationType;

      // 加载电子书全局设置
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

      // 加载纯文本阅读器全局设置
      this.textFontSize = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_FONT_SIZE,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize
      );
      this.textLineHeight = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_LINE_HEIGHT,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.lineHeight
      );
      this.textParagraphSpacing = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing
      );
      this.textFirstLineIndent = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent
      );
      this.textLetterSpacing = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_LETTER_SPACING,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing
      );
      this.textAlignment = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_ALIGNMENT,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment
      ) as TextAlignment;
      this.textPageMargin = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_PAGE_MARGIN,
        DEFAULT_TEXT_READER_SETTINGS.pageMargins.left
      );
      this.textBgColorIndex = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_BG_COLOR,
        0
      );
      this.textPageTurnAnimation = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION,
        DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation
      ) as TextPageTurnAnimation;
      this.textKeepScreenOn = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON,
        DEFAULT_TEXT_READER_SETTINGS.keepScreenOn
      );
      this.textVolumeKeyNav = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV,
        DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation
      );
      this.textTapToTurn = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_TAP_TO_TURN,
        DEFAULT_TEXT_READER_SETTINGS.tapToTurn
      );
      this.textBgImagePath = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH,
        ''
      );
      this.textBgImageOpacity = this.settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY,
        0.3
      );
      this.textUseBgImage = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE,
        false
      );

      logger.info(TAG, '全局设置加载完成');
    } catch (error) {
      logger.error(TAG, '加载全局设置失败', String(error));
    }
  }

  /**
   * 保存全局设置
   */
  private async saveGlobalSettings(): Promise<void> {
    try {
      await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
      await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
      await this.settingsManager.setNumber(SettingKeys.GLOBAL_BRIGHTNESS, this.defaultBrightness);
      await this.settingsManager.setBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, this.keepScreenOn);
      await this.settingsManager.setBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, this.volumeKeyNavigation);
      await this.settingsManager.setBoolean(SettingKeys.DOWNLOAD_WIFI_ONLY, this.downloadOnWifiOnly);
      await this.settingsManager.setNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, this.maxConcurrentDownloads);
      await this.settingsManager.setBoolean(SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS, this.enableDownloadNotifications);
      await this.settingsManager.setBoolean(SettingKeys.ENABLE_UPDATE_NOTIFICATIONS, this.enableUpdateNotifications);
      await this.settingsManager.setBoolean(SettingKeys.AUTO_CHECK_UPDATES, this.autoCheckUpdates);
      await this.settingsManager.setBoolean(SettingKeys.CLEAR_CACHE_ON_EXIT, this.clearCacheOnExit);
      await this.settingsManager.setBoolean(SettingKeys.ENABLE_LOG_FLOATING_WINDOW, this.enableLogFloatingWindow);
      await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, this.advancedModeEnabled);
      await this.settingsManager.setBoolean(SettingKeys.FORCE_TABLET_MODE, this.forceTabletMode);
      await this.settingsManager.setBoolean(SettingKeys.FORCE_LANDSCAPE_MODE, this.forceLandscapeMode);

      // 同步到AppStorage
      this.settingsManager.syncToAppStorage();

      logger.info(TAG, '全局设置保存成功');
    } catch (error) {
      logger.error(TAG, '保存全局设置失败', String(error));
    }
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 构建阅读设置区域
   */
  @Builder
  buildReadingSettings() {
    Column({ space: 16 }) {
      Text('漫画阅读设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 阅读模式
      Column({ space: 8 }) {
        Text('默认阅读模式')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('单页')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.SINGLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.SINGLE_PAGE;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('双页')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.DOUBLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.DOUBLE_PAGE;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('连续滚动')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(80)
            .height(36)
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.CONTINUOUS_SCROLL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.CONTINUOUS_SCROLL;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('条漫')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width(70)
            .height(36)
            .backgroundColor(
              this.defaultReadingMode === ReadingMode.WEBTOON
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingMode = ReadingMode.WEBTOON;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              this.defaultReadingDirection = ReadingDirection.TOP_TO_BOTTOM;
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('从左到右')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.defaultReadingDirection === ReadingDirection.LEFT_TO_RIGHT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingDirection = ReadingDirection.LEFT_TO_RIGHT;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('从右到左')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.defaultReadingDirection === ReadingDirection.RIGHT_TO_LEFT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingDirection = ReadingDirection.RIGHT_TO_LEFT;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })

          Button({ stateEffect: true }) {
            Text('从上到下')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .layoutWeight(1)
            .height(36)
            .backgroundColor(
              this.defaultReadingDirection === ReadingDirection.TOP_TO_BOTTOM
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(6)
            .onClick(async () => {
              this.defaultReadingDirection = ReadingDirection.TOP_TO_BOTTOM;
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }

      // 翻页动画
      Column({ space: 8 }) {
        Text('默认翻页动画')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach([
            { type: PageTurnAnimationType.NONE, label: '无' },
            { type: PageTurnAnimationType.SLIDE, label: '滑动' },
            { type: PageTurnAnimationType.FADE, label: '淡入淡出' },
            { type: PageTurnAnimationType.CURL, label: '卷页' },
            { type: PageTurnAnimationType.CUBE, label: '立方体' },
            { type: PageTurnAnimationType.COVER, label: '覆盖' },
            { type: PageTurnAnimationType.DEPTH, label: '景深' }
          ], (item: PageTurnAnimationOption) => {
            Button({ stateEffect: true }) {
              Text(item.label)
                .fontSize(12)
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

      // 开关设置
      Row() {
        Text('保持屏幕常亮')
          .fontSize(14)
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
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建通知设置区域
   */
  @Builder
  buildNotificationSettings() {
    Column({ space: 16 }) {
      Text('通知设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Text('下载完成通知')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.enableDownloadNotifications })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.enableDownloadNotifications = isOn;
            await this.settingsManager.setBoolean(SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('更新通知')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.enableUpdateNotifications })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.enableUpdateNotifications = isOn;
            await this.settingsManager.setBoolean(SettingKeys.ENABLE_UPDATE_NOTIFICATIONS, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建下载设置区域
   */
  @Builder
  buildDownloadSettings() {
    Column({ space: 16 }) {
      Text('下载设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Text('仅在Wi-Fi下下载')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.downloadOnWifiOnly })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.downloadOnWifiOnly = isOn;
            await this.settingsManager.setBoolean(SettingKeys.DOWNLOAD_WIFI_ONLY, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 8 }) {
        Row() {
          Text('最大并发下载数')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.maxConcurrentDownloads}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')

        Slider({
          value: this.maxConcurrentDownloads,
          min: 1,
          max: 5,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (value: number) => {
            this.maxConcurrentDownloads = Math.round(value);
            await this.settingsManager.setNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, this.maxConcurrentDownloads);
            this.settingsManager.syncToAppStorage();
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建调试设置区域（仅在高级模式下显示）
   */
  @Builder
  buildDebugSettings() {
    Column({ space: 16 }) {
      Text('调试设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Column({ space: 4 }) {
          Text('高级模式')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('启用后显示更多开发者选项')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.advancedModeEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.advancedModeEnabled = isOn;
            await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, isOn);
            this.settingsManager.syncToAppStorage();
            this.showRestartDialog = true;
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.advancedModeEnabled) {
        Row() {
          Column({ space: 4 }) {
            Text('日志悬浮窗')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('显示实时日志输出')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.enableLogFloatingWindow })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.enableLogFloatingWindow = isOn;
              await this.settingsManager.setBoolean(SettingKeys.ENABLE_LOG_FLOATING_WINDOW, isOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('强制平板模式')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('在手机上使用平板布局')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.forceTabletMode })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.forceTabletMode = isOn;
              await this.settingsManager.setBoolean(SettingKeys.FORCE_TABLET_MODE, isOn);
              this.settingsManager.syncToAppStorage();
              this.showRestartDialog = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('强制横屏模式')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('锁定应用为横屏显示')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.forceLandscapeMode })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.forceLandscapeMode = isOn;
              await this.settingsManager.setBoolean(SettingKeys.FORCE_LANDSCAPE_MODE, isOn);
              this.settingsManager.syncToAppStorage();
              this.showRestartDialog = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('自动检查更新')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('启动时检查应用更新')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.autoCheckUpdates })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.autoCheckUpdates = isOn;
              await this.settingsManager.setBoolean(SettingKeys.AUTO_CHECK_UPDATES, isOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('退出时清理缓存')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('关闭应用时自动清理临时文件')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.clearCacheOnExit })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.clearCacheOnExit = isOn;
              await this.settingsManager.setBoolean(SettingKeys.CLEAR_CACHE_ON_EXIT, isOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建电子书默认设置区域
   */
  @Builder
  buildEBookSettings() {
    Column({ space: 16 }) {
      Text('电子书默认设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text('默认字体大小')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookFontSize}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookLineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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

      // 页边距
      Column({ space: 8 }) {
        Row() {
          Text('默认页边距')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.ebookPageMargin}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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

      // 翻页模式
      Column({ space: 8 }) {
        Text('默认翻页模式')
          .fontSize(14)
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
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建纯文本阅读器默认设置区域
   */
  @Builder
  buildTextReaderSettings() {
    Column({ space: 16 }) {
      Text('纯文本阅读器默认设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 字体大小
      Column({ space: 8 }) {
        Row() {
          Text('默认字体大小')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textFontSize}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 行高
      Column({ space: 8 }) {
        Row() {
          Text('默认行高')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textLineHeight.toFixed(1)}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 段间距
      Column({ space: 8 }) {
        Row() {
          Text('段间距')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textParagraphSpacing}px`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 首行缩进
      Column({ space: 8 }) {
        Row() {
          Text('首行缩进')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textFirstLineIndent}字符`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 页边距
      Column({ space: 8 }) {
        Row() {
          Text('默认页边距')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.textPageMargin}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 背景色主题
      Column({ space: 8 }) {
        Text('默认背景色')
          .fontSize(14)
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
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 4 })
                .maxLines(1)
            }
            .width(50)
            .margin({ right: 8, bottom: 8 })
            .onClick(async () => {
              this.textBgColorIndex = index;
              this.textUseBgImage = false;
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, this.textBgColorIndex);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
              this.settingsManager.syncToAppStorage();
            })
          })
        }
        .width('100%')
      }

      // 自定义背景图片
      Column({ space: 12 }) {
        Row() {
          Text('使用背景图片')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textUseBgImage })
            .onChange(async (isOn: boolean) => {
              this.textUseBgImage = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, isOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')

        if (this.textUseBgImage) {
          // 图片不透明度
          Column({ space: 8 }) {
            Row() {
              Text('图片不透明度')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Blank()
              Text(`${Math.round(this.textBgImageOpacity * 100)}%`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
            .width('100%')

            Slider({
              value: this.textBgImageOpacity * 100,
              min: 10,
              max: 100,
              step: 5,
              style: SliderStyle.InSet
            })
              .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .onChange(async (value: number) => {
                this.textBgImageOpacity = value / 100;
                await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, this.textBgImageOpacity);
                this.settingsManager.syncToAppStorage();
              })
          }

          // 选择图片按钮
          Button('选择背景图片')
            .width('100%')
            .height(40)
            .fontSize(14)
            .type(ButtonType.Normal)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.selectTextBackgroundImage();
            })

          // 当前背景图片预览
          if (this.textBgImagePath && this.textBgImagePath.length > 0) {
            Column({ space: 8 }) {
              Text('当前背景图片')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')

              Image(this.textBgImagePath.startsWith('/') ? 'file://' + this.textBgImagePath : this.textBgImagePath)
                .width('100%')
                .height(100)
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .opacity(this.textBgImageOpacity)
            }
            .width('100%')
          }
        }
      }

      // 翻页动画
      Column({ space: 8 }) {
        Text('默认翻页动画')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach([
            { text: '滑动', anim: TextPageTurnAnimation.SLIDE },
            { text: '卷曲', anim: TextPageTurnAnimation.CURL },
            { text: '淡入淡出', anim: TextPageTurnAnimation.FADE },
            { text: '无', anim: TextPageTurnAnimation.NONE }
          ] as TextAnimationOption[], (item: TextAnimationOption) => {
            Button({ stateEffect: true }) {
              Text(item.text)
                .fontSize(13)
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
                this.settingsManager.syncToAppStorage();
              })
          })
        }
        .width('100%')
      }

      // 开关设置
      Column({ space: 12 }) {
        Row() {
          Text('保持屏幕常亮')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textKeepScreenOn })
            .onChange(async (isOn: boolean) => {
              this.textKeepScreenOn = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, this.textKeepScreenOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')

        Row() {
          Text('音量键翻页')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textVolumeKeyNav })
            .onChange(async (isOn: boolean) => {
              this.textVolumeKeyNav = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, this.textVolumeKeyNav);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')

        Row() {
          Text('点击翻页')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.textTapToTurn })
            .onChange(async (isOn: boolean) => {
              this.textTapToTurn = isOn;
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, this.textTapToTurn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 选择纯文本阅读器背景图片
   */
  private async selectTextBackgroundImage(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取应用上下文');
        return;
      }

      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      const photoPicker = new picker.PhotoViewPicker(context);
      const selectResult = await photoPicker.select(photoSelectOptions);

      if (selectResult && selectResult.photoUris.length > 0) {
        const sourceUri = selectResult.photoUris[0];
        // 将图片复制到沙箱目录
        const savedPath = await this.copyBgImageToSandbox(sourceUri, context);
        if (savedPath) {
          this.textBgImagePath = savedPath;
          await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, savedPath);
          this.settingsManager.syncToAppStorage();
          logger.info(TAG, `背景图片已保存: ${savedPath}`);
        }
      }
    } catch (error) {
      logger.error(TAG, `选择背景图片失败: ${String(error)}`);
    }
  }

  /**
   * 将背景图片复制到沙箱目录
   */
  private async copyBgImageToSandbox(sourceUri: string, context: common.UIAbilityContext): Promise<string | null> {
    try {
      const cacheDir = context.cacheDir;
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(2, 8);
      const destPath = `${cacheDir}/global_bg_${timestamp}_${randomStr}.jpg`;

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
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Column() {
        Button({ stateEffect: true }) {
          Text('恢复默认')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(async () => {
            // 恢复漫画阅读默认设置
            this.defaultReadingMode = DEFAULT_READING_SETTINGS.readingMode;
            this.defaultReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
            this.defaultBrightness = DEFAULT_READING_SETTINGS.brightness;
            this.keepScreenOn = DEFAULT_READING_SETTINGS.keepScreenOn;
            this.volumeKeyNavigation = DEFAULT_READING_SETTINGS.volumeKeyNavigation;
            this.defaultPageTurnAnimation = DEFAULT_READING_SETTINGS.pageTurnAnimation;

            // 恢复电子书默认设置
            this.ebookFontSize = DEFAULT_EBOOK_READING_SETTINGS.fontSize;
            this.ebookLineHeight = DEFAULT_EBOOK_READING_SETTINGS.lineHeight;
            this.ebookPageMargin = DEFAULT_EBOOK_READING_SETTINGS.pageMargin;
            this.ebookThemeIndex = 0;
            this.ebookPageMode = DEFAULT_EBOOK_READING_SETTINGS.pageMode;

            // 恢复纯文本阅读器默认设置
            this.textFontSize = DEFAULT_TEXT_READER_SETTINGS.textStyle.fontSize;
            this.textLineHeight = DEFAULT_TEXT_READER_SETTINGS.textStyle.lineHeight;
            this.textParagraphSpacing = DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing;
            this.textFirstLineIndent = DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent;
            this.textLetterSpacing = DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing;
            this.textAlignment = DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment;
            this.textPageMargin = DEFAULT_TEXT_READER_SETTINGS.pageMargins.left;
            this.textBgColorIndex = 0;
            this.textPageTurnAnimation = DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation;
            this.textKeepScreenOn = DEFAULT_TEXT_READER_SETTINGS.keepScreenOn;
            this.textVolumeKeyNav = DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation;
            this.textTapToTurn = DEFAULT_TEXT_READER_SETTINGS.tapToTurn;
            this.textUseBgImage = false;
            this.textBgImagePath = '';
            this.textBgImageOpacity = 0.3;

            // 恢复下载设置
            this.downloadOnWifiOnly = true;
            this.maxConcurrentDownloads = 3;

            // 恢复通知设置
            this.enableDownloadNotifications = true;
            this.enableUpdateNotifications = true;

            // 保存所有恢复的设置到 SettingsManager
            try {
              // 漫画阅读设置
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_MODE, this.defaultReadingMode);
              await this.settingsManager.setString(SettingKeys.GLOBAL_READING_DIRECTION, this.defaultReadingDirection);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_BRIGHTNESS, this.defaultBrightness);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_KEEP_SCREEN_ON, this.keepScreenOn);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_VOLUME_KEY_NAVIGATION, this.volumeKeyNavigation);
              await this.settingsManager.setString(SettingKeys.GLOBAL_PAGE_TURN_ANIMATION, this.defaultPageTurnAnimation);

              // 电子书设置
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_FONT_SIZE, this.ebookFontSize);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_LINE_HEIGHT, this.ebookLineHeight);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_PAGE_MARGIN, this.ebookPageMargin);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_EBOOK_THEME, this.ebookThemeIndex);
              await this.settingsManager.setString(SettingKeys.GLOBAL_EBOOK_PAGE_MODE, this.ebookPageMode);

              // 纯文本阅读器设置
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_FONT_SIZE, this.textFontSize);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_LINE_HEIGHT, this.textLineHeight);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_PARAGRAPH_SPACING, this.textParagraphSpacing);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_FIRST_LINE_INDENT, this.textFirstLineIndent);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_LETTER_SPACING, this.textLetterSpacing);
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_ALIGNMENT, this.textAlignment);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_PAGE_MARGIN, this.textPageMargin);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, this.textBgColorIndex);
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_PAGE_TURN_ANIMATION, this.textPageTurnAnimation);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_KEEP_SCREEN_ON, this.textKeepScreenOn);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_VOLUME_KEY_NAV, this.textVolumeKeyNav);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_TAP_TO_TURN, this.textTapToTurn);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, this.textUseBgImage);
              await this.settingsManager.setString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, this.textBgImagePath);
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_IMAGE_OPACITY, this.textBgImageOpacity);

              // 下载设置
              await this.settingsManager.setBoolean(SettingKeys.DOWNLOAD_WIFI_ONLY, this.downloadOnWifiOnly);
              await this.settingsManager.setNumber(SettingKeys.MAX_CONCURRENT_DOWNLOADS, this.maxConcurrentDownloads);

              // 通知设置
              await this.settingsManager.setBoolean(SettingKeys.ENABLE_DOWNLOAD_NOTIFICATIONS, this.enableDownloadNotifications);
              await this.settingsManager.setBoolean(SettingKeys.ENABLE_UPDATE_NOTIFICATIONS, this.enableUpdateNotifications);

              // 同步到 AppStorage
              this.settingsManager.syncToAppStorage();

              logger.info(TAG, '已恢复所有默认设置并保存');
            } catch (error) {
              logger.error(TAG, '保存默认设置失败', String(error));
            }
          })
      }.width('30%')

      Column() {
        Button({ stateEffect: true }) {
          Text('返回')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            this.goBack();
          })
      }.layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            if (this.responsive_isLandscape) {
              // 横屏：使用Flex布局，设置项自动换行，每行最多2个
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                Column({ space: 16 }) {
                  this.buildReadingSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildEBookSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildTextReaderSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildDownloadSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildNotificationSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildDebugSettings()
                }
                .width('48%')
                .margin({ bottom: 16 })
                
              }
              .width('100%')
              
              this.buildActionButtons()
            } else {
              // 竖屏：原有布局
              this.buildReadingSettings()
              this.buildEBookSettings()
              this.buildTextReaderSettings()
              this.buildDownloadSettings()
              this.buildNotificationSettings()
              this.buildDebugSettings()
              this.buildActionButtons()
            }

            // 重播引导页面按钮（页面底部）
            Column() {
              Button({ stateEffect: true }) {
                Text('重播引导页面')
                  .fontSize(16)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              }
                .width('100%')
                .height(44)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .borderRadius(12)
                .onClick(() => {
                  this.resetGuideAndRestart();
                })
            }
            .width('100%')
            .padding({ top: 8, bottom: 24 })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth }) // 响应式最大宽度
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart) // 响应式：大屏居中对齐
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)

        // 重启提示对话框
        if (this.showRestartDialog) {
          this.buildRestartDialog()
        }
      }
    }
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
        title: { mainTitle: '全局设置' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }

  /**
   * 构建重启提示对话框
   */
  @Builder
  buildRestartDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .onClick(() => {
          this.showRestartDialog = false;
        })

      // 对话框内容
      Column({ space: 20 }) {
        Text('需要重启应用')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('高级模式设置已更改，需要重启应用才能生效。')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)

        Row({ space: 12 }) {
          Button('稍后重启')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
            .layoutWeight(1)
            .onClick(() => {
              this.showRestartDialog = false;
            })

          Button('立即重启')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .layoutWeight(1)
            .onClick(async () => {
              await this.restartApp();
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.2)' })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 重启应用
   */
  private async restartApp(): Promise<void> {
    try {
      const uiCtx = this.getUIContext();
      if (!uiCtx) {
        logger.error(TAG, '获取UIContext失败，无法重启应用');
        return;
      }
      const context = uiCtx.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext，无法重启应用');
        return;
      }

      const want: Want = {
        bundleName: 'com.dlzz.manxia',
        abilityName: 'EntryAbility'
      };

      await context.startAbility(want);
      context.terminateSelf();
    } catch (error) {
      logger.error(TAG, '重启应用失败', String(error));
    }
  }

  /**
   * 重置引导标记并重启应用
   * 使用UIContext获取HostContext，调用startAbility后终止当前Ability
   */
  private async resetGuideAndRestart(): Promise<void> {
    try {
      await this.welcomeGuideManager.resetGuide();
      const uiCtx = this.getUIContext();
      if (!uiCtx) {
        logger.error(TAG, '获取UIContext失败，无法重启应用');
        return;
      }
      const context = uiCtx.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext，无法重启应用');
        return;
      }

      const want: Want = {
        bundleName: 'com.dlzz.manxia',
        abilityName: 'EntryAbility',
        parameters: {
          'fromSettings': true,
          'forceGuide': true
        }
      };

      // 先启动主Ability，再终止当前，达到“重启”效果
      await context.startAbility(want);
      await context.terminateSelf();
      logger.info(TAG, '已重置引导并请求重启应用');
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '重播引导并重启应用失败', msg);
    }
  }
}

export { GlobalSettingsPage }
