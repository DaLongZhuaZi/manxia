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
// 已弃用自定义 AnimatedButton，改用原生 ArkUI Button
import { logger } from '../Utils/Logger';
import { ReadingMode, ReadingDirection, DEFAULT_READING_SETTINGS, PageTurnAnimationType } from '../Models/MangaModels';
import { EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, DEFAULT_EBOOK_READING_SETTINGS } from '../Models/EBookModels';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
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
      Text('默认阅读设置')
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
          .onChange((isOn: boolean) => {
            this.keepScreenOn = isOn;
            AppStorage.setOrCreate('global_keep_screen_on', this.keepScreenOn);
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
          .onChange((isOn: boolean) => {
            this.volumeKeyNavigation = isOn;
            AppStorage.setOrCreate('global_volume_key_navigation', this.volumeKeyNavigation);
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
        Text('仅Wi-Fi下载')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.downloadOnWifiOnly })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.downloadOnWifiOnly = isOn;
            AppStorage.setOrCreate('download_wifi_only', this.downloadOnWifiOnly);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Column({ space: 8 }) {
        Row() {
          Text('最大并发下载数')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(`${this.maxConcurrentDownloads}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Slider({
          value: this.maxConcurrentDownloads,
          min: 1,
          max: 10,
          step: 1,
          style: SliderStyle.InSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange((value: number) => {
            this.maxConcurrentDownloads = Math.round(value);
            AppStorage.setOrCreate('max_concurrent_downloads', this.maxConcurrentDownloads);
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
          .onChange((isOn: boolean) => {
            this.enableDownloadNotifications = isOn;
            AppStorage.setOrCreate('enable_download_notifications', this.enableDownloadNotifications);
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
          .onChange((isOn: boolean) => {
            this.enableUpdateNotifications = isOn;
            AppStorage.setOrCreate('enable_update_notifications', this.enableUpdateNotifications);
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
          .onClick(() => {
            // 恢复默认设置
            this.defaultReadingMode = DEFAULT_READING_SETTINGS.readingMode;
            this.defaultReadingDirection = DEFAULT_READING_SETTINGS.readingDirection;
            this.defaultBrightness = DEFAULT_READING_SETTINGS.brightness;
            this.keepScreenOn = DEFAULT_READING_SETTINGS.keepScreenOn;
            this.volumeKeyNavigation = DEFAULT_READING_SETTINGS.volumeKeyNavigation;
            logger.info(TAG, '已恢复默认设置');
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

  @Builder
  buildDebugSettings() {
    Column({ space: 16 }) {
      Text('调试与工具')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 高级模式开关
      Column({ space: 8 }) {
        Row() {
          Column({ space: 4 }) {
            Text('高级模式')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            Text('启用图源管理等高级功能')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.advancedModeEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.advancedModeEnabled = isOn;
              await this.settingsManager.setBoolean(SettingKeys.ADVANCED_MODE_ENABLED, isOn);
              this.settingsManager.syncToAppStorage();
              // 显示重启提示
              this.showRestartDialog = true;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        if (this.advancedModeEnabled) {
          Text('⚠️ 需要重启应用才能生效')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme))
            .width('100%')
        }
      }
      .width('100%')

      Row() {
        Text('启用日志悬浮窗口')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
        Text('强制平板模式')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.forceTabletMode })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.forceTabletMode = isOn;
            await this.settingsManager.setBoolean(SettingKeys.FORCE_TABLET_MODE, isOn);
            this.settingsManager.syncToAppStorage();
            logger.info(TAG, isOn ? '已开启强制平板模式' : '已关闭强制平板模式');
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('强制横屏显示')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.forceLandscapeMode })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.forceLandscapeMode = isOn;
            await this.settingsManager.setBoolean(SettingKeys.FORCE_LANDSCAPE_MODE, isOn);
            this.settingsManager.syncToAppStorage();
            const ui = this.getUIContext();
            if (isOn) {
              WindowManager.setPreferredOrientationLandscape(ui);
              logger.info(TAG, '已开启强制横屏显示');
            } else {
              WindowManager.setPreferredOrientationAuto(ui);
              logger.info(TAG, '已关闭强制横屏显示');
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 存储管理入口
      Row({ space: 12 }) {
        Image($r('app.media.ic_storage'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))

        Column({ space: 4 }) {
          Text('存储管理')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Text('查看和管理应用存储空间')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Image($r('app.media.ic_arrow_right'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      .borderRadius(8)
      .onClick(() => {
        logger.info(TAG, '导航到存储管理页面');
        this.pathStack.pushPathByName('StorageManagementPage', null);
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
