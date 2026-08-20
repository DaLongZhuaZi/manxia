// 文件路径: entry/src/main/ets/pages/settings/NetworkSettingsSubPage.ets
/**
 * 下载与网络设置子页面
 * 包含下载设置、网络请求设置（User-Agent等）
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
// OLD: ../../Framework/Managers/SettingsManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_core/src/main/ets/Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'NetworkSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 导航参数接口
interface NetworkSettingsSubPageParams {
  fromPage?: string;
}

@Component
export struct NetworkSettingsSubPage {
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

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'NetworkSettingsSubPage';
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 下载设置
  @State downloadOnWifiOnly: boolean = true;
  @State maxConcurrentDownloads: number = 3;

  // 全局UserAgent设置
  @State globalUserAgent: string = '';
  @State globalUserAgentEnabled: boolean = false;
  private readonly DEFAULT_USER_AGENT: string = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

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

    // 加载保存的设置
    this.loadSettings();
    this.applyPendingSearchTarget();
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('NetworkSettingsSubPage');
    if (!target) {
      return;
    }
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 140);
  }

  private lifecycle = new PageLifecycleManager('NetworkSettingsSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

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
  }

  private loadSettings(): void {
    try {
      this.downloadOnWifiOnly = this.settingsManager.getBoolean(
        SettingKeys.DOWNLOAD_WIFI_ONLY,
        true
      );

      this.maxConcurrentDownloads = this.settingsManager.getNumber(
        SettingKeys.MAX_CONCURRENT_DOWNLOADS,
        3
      );

      this.globalUserAgentEnabled = this.settingsManager.getBoolean(
        SettingKeys.GLOBAL_USER_AGENT_ENABLED,
        false
      );
      this.globalUserAgent = this.settingsManager.getString(
        SettingKeys.GLOBAL_USER_AGENT,
        this.DEFAULT_USER_AGENT
      );

      logger.info(TAG, '下载与网络设置加载完成');
    } catch (error) {
      logger.error(TAG, '加载设置失败', String(error));
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
   * 构建下载设置区域
   */
  @Builder
  buildDownloadSettings() {
    Column({ space: 16 }) {
      Text('下载设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Column({ space: 4 }) {
          Text('仅WiFi下载')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('仅在WiFi网络下进行下载')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
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

      // 最大并发下载数
      Column({ space: 8 }) {
        Row() {
          Text('最大并发下载数')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Text(`${this.maxConcurrentDownloads}`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
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
   * 构建UserAgent设置区域
   */
  @Builder
  buildUserAgentSettings() {
    Column({ space: 16 }) {
      Text('网络请求设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Column({ space: 4 }) {
          Text('启用自定义User-Agent')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('为所有图源请求使用自定义UA')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.globalUserAgentEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.globalUserAgentEnabled = isOn;
            await this.settingsManager.setBoolean(SettingKeys.GLOBAL_USER_AGENT_ENABLED, isOn);
            this.settingsManager.syncToAppStorage();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.globalUserAgentEnabled) {
        Column({ space: 8 }) {
          Text('自定义User-Agent')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          TextArea({ text: this.globalUserAgent, placeholder: '输入自定义User-Agent...' })
            .fontSize(13)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .padding(12)
            .height(100)
            .width('100%')
            .onChange(async (value: string) => {
              this.globalUserAgent = value;
              await this.settingsManager.setString(SettingKeys.GLOBAL_USER_AGENT, value);
              this.settingsManager.syncToAppStorage();
            })

          Row({ space: 8 }) {
            Button('重置为默认')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .height(32)
              .onClick(async () => {
                this.globalUserAgent = this.DEFAULT_USER_AGENT;
                await this.settingsManager.setString(SettingKeys.GLOBAL_USER_AGENT, this.DEFAULT_USER_AGENT);
                this.settingsManager.syncToAppStorage();
              })

            Button('使用Chrome UA')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
              .height(32)
              .onClick(async () => {
                const chromeUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
                this.globalUserAgent = chromeUA;
                await this.settingsManager.setString(SettingKeys.GLOBAL_USER_AGENT, chromeUA);
                this.settingsManager.syncToAppStorage();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
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
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
                Column({ space: 16 }) {
                  this.buildDownloadSettings()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_download'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'network_download') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'network_download'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_download', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_download', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_download',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildUserAgentSettings()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_request'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'network_request') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'network_request'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_request', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_request', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_request',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }
              .width('100%')
            } else {
              Column() {
                this.buildDownloadSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'network_download'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'network_download') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_download'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_download', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_download', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'network_download',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })

              Column() {
                this.buildUserAgentSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'network_request'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'network_request') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'network_request'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_request', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'network_request', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'network_request',
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
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .onDidScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '下载与网络',
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
