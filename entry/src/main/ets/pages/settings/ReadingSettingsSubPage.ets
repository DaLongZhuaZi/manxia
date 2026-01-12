// 文件路径: entry/src/main/ets/pages/settings/ReadingSettingsSubPage.ets
/**
 * 阅读设置子页面
 * 包含漫画、电子书、纯文本阅读器的默认阅读设置
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
import { ReadingMode, ReadingDirection, DEFAULT_READING_SETTINGS, PageTurnAnimationType } from '../../Models/MangaModels';
import { EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, DEFAULT_EBOOK_READING_SETTINGS } from '../../Models/EBookModels';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { TextPageTurnAnimation, TextAlignment, PRESET_BACKGROUNDS, PresetBackground, DEFAULT_TEXT_READER_SETTINGS } from '../../Models/TextReaderModels';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { EBookDataManager, BackgroundImageInfo } from '../../Framework/Data/EBookDataManager';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'ReadingSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 导航参数接口
interface ReadingSettingsSubPageParams {
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

@Component
export struct ReadingSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'ReadingSettingsSubPage';
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
  @State textTextColor: string = DEFAULT_TEXT_READER_SETTINGS.textStyle.textColor;
  @State textPageTurnAnimation: TextPageTurnAnimation = DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation;
  @State textKeepScreenOn: boolean = DEFAULT_TEXT_READER_SETTINGS.keepScreenOn;
  @State textVolumeKeyNav: boolean = DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation;
  @State textTapToTurn: boolean = DEFAULT_TEXT_READER_SETTINGS.tapToTurn;
  @State textBgImagePath: string = '';
  @State textBgImageOpacity: number = 0.3;
  @State textUseBgImage: boolean = false;
  // 底部信息栏设置
  @State textShowTime: boolean = true;
  @State textShowBattery: boolean = true;
  @State textShowPageNumber: boolean = true;
  @State textShowProgress: boolean = false;
  
  // 背景图片管理
  @State allBackgroundImages: BackgroundImageInfo[] = [];
  @State showBackgroundManager: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

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
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化响应式布局
    this.initializeResponsiveLayout();

    // 加载保存的全局设置
    this.loadGlobalSettings();
  }

  private lifecycle = new PageLifecycleManager('ReadingSettingsSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
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
      // 漫画阅读设置
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

      this.defaultPageTurnAnimation = this.settingsManager.getString(
        SettingKeys.GLOBAL_PAGE_TURN_ANIMATION,
        DEFAULT_READING_SETTINGS.pageTurnAnimation
      ) as PageTurnAnimationType;

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

      // 纯文本阅读器全局设置
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
      this.textTextColor = this.settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_TEXT_COLOR,
        DEFAULT_TEXT_READER_SETTINGS.textStyle.textColor
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

      logger.info(TAG, '阅读设置加载完成');
    } catch (error) {
      logger.error(TAG, '加载阅读设置失败', String(error));
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
   * 构建漫画阅读设置区域
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
        
        Row({ space: 8 }) {
          Button({ stateEffect: true }) {
            Text('单页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
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
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
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
          .fontFamily(this.appFontFamily)
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

      // 开关设置
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

      // 页边距
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

      // 翻页模式
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 段间距
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
            this.settingsManager.syncToAppStorage();
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 页边距
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
            this.settingsManager.syncToAppStorage();
          })
      }

      // 背景色主题
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
              await this.settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_BG_COLOR, this.textBgColorIndex);
              await this.settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_USE_BG_IMAGE, false);
              this.settingsManager.syncToAppStorage();
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
            { text: '卷曲', anim: TextPageTurnAnimation.CURL },
            { text: '淡入淡出', anim: TextPageTurnAnimation.FADE },
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
            .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
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
            .fontFamily(this.appFontFamily)
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
                  this.buildMangaReadingSettings()
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
                .width('100%')
                .margin({ bottom: 16 })
              }
              .width('100%')
            } else {
              // 竖屏：原有布局
              this.buildMangaReadingSettings()
              this.buildEBookSettings()
              this.buildTextReaderSettings()
            }

            Blank().height(40)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '阅读设置' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}
