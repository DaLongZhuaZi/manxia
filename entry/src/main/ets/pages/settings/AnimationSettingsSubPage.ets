// 文件路径: entry/src/main/ets/pages/settings/AnimationSettingsSubPage.ets
/**
 * 动画设置子页面
 * 控制APP内的书籍打开/关闭动画等动画效果
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_core/src/main/ets/Framework/Utils/ResponsiveLayout';
import { 
  AnimationSettingsManager, 
  AnimationSettings, 
  DEFAULT_ANIMATION_SETTINGS,
  AnimationSettingsListener
} from '../../Framework/Animation/AnimationSettingsManager';
import { SettingsSearchSupport } from './SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'AnimationSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct AnimationSettingsSubPage {
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
  private componentId: string = 'AnimationSettingsSubPage';

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 动画设置管理器
  private animationSettingsManager: AnimationSettingsManager = AnimationSettingsManager.getInstance();
  private settingsListener: AnimationSettingsListener | null = null;

  // 动画设置状态
  @State bookOpenEnabled: boolean = DEFAULT_ANIMATION_SETTINGS.bookOpenEnabled;
  @State bookCloseEnabled: boolean = DEFAULT_ANIMATION_SETTINGS.bookCloseEnabled;
  @State bookOpenDuration: number = DEFAULT_ANIMATION_SETTINGS.bookOpenDuration;
  @State bookCloseDuration: number = DEFAULT_ANIMATION_SETTINGS.bookCloseDuration;
  @State mainPageBottomBarAnimationEnabled: boolean = DEFAULT_ANIMATION_SETTINGS.mainPageBottomBarAnimationEnabled;

  private lifecycle = new PageLifecycleManager('AnimationSettingsSubPage', { enableDebug: true });

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

    // 加载动画设置
    this.loadAnimationSettings();

    // 监听设置变化
    this.settingsListener = (settings: AnimationSettings) => {
      this.updateLocalState(settings);
    };
    this.animationSettingsManager.addListener(this.settingsListener);
    this.applyPendingSearchTarget();
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('AnimationSettingsSubPage');
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

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

    // 移除设置变化监听器
    if (this.settingsListener) {
      this.animationSettingsManager.removeListener(this.settingsListener);
      this.settingsListener = null;
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
   * 加载动画设置
   */
  private loadAnimationSettings(): void {
    const settings = this.animationSettingsManager.getSettings();
    this.updateLocalState(settings);
    logger.info(TAG, '动画设置加载完成');
  }

  /**
   * 更新本地状态
   */
  private updateLocalState(settings: AnimationSettings): void {
    this.bookOpenEnabled = settings.bookOpenEnabled;
    this.bookCloseEnabled = settings.bookCloseEnabled;
    this.bookOpenDuration = settings.bookOpenDuration;
    this.bookCloseDuration = settings.bookCloseDuration;
    this.mainPageBottomBarAnimationEnabled = settings.mainPageBottomBarAnimationEnabled;
  }

  /**
   * 获取时长显示文本
   */
  private getDurationText(duration: number): string {
    if (duration <= 200) {
      return '快速';
    } else if (duration <= 400) {
      return '正常';
    } else if (duration <= 600) {
      return '较慢';
    } else {
      return '慢速';
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
   * 构建书籍动画设置区域
   */
  @Builder
  buildBookAnimationSettings() {
    Column({ space: 16 }) {
      Text('书籍打开/关闭动画')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('控制从书架点击书籍封面进入阅读器时的翻开动画，以及从阅读器返回时的关闭动画效果。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 打开动画开关
      Row() {
        Column({ space: 4 }) {
          Text('书籍打开动画')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('点击书籍封面时播放翻开动画')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.bookOpenEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            await this.animationSettingsManager.setBookOpenAnimationEnabled(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 打开动画时长（仅在启用时显示）
      if (this.bookOpenEnabled) {
        Column({ space: 8 }) {
          Row() {
            Text('打开动画速度')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${this.getDurationText(this.bookOpenDuration)} (${this.bookOpenDuration}ms)`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Slider({
            value: this.bookOpenDuration,
            min: 100,
            max: 800,
            step: 50,
            style: SliderStyle.InSet
          })
            .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (value: number) => {
              this.bookOpenDuration = Math.round(value);
              await this.animationSettingsManager.setBookOpenDuration(this.bookOpenDuration);
            })
        }
        .width('100%')
        .padding({ left: 8 })
      }

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
        .margin({ top: 4, bottom: 4 })

      // 关闭动画开关
      Row() {
        Column({ space: 4 }) {
          Text('书籍关闭动画')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('从阅读器返回时播放关闭动画')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.bookCloseEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            await this.animationSettingsManager.setBookCloseAnimationEnabled(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 关闭动画时长（仅在启用时显示）
      if (this.bookCloseEnabled) {
        Column({ space: 8 }) {
          Row() {
            Text('关闭动画速度')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${this.getDurationText(this.bookCloseDuration)} (${this.bookCloseDuration}ms)`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Slider({
            value: this.bookCloseDuration,
            min: 100,
            max: 800,
            step: 50,
            style: SliderStyle.InSet
          })
            .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (value: number) => {
              this.bookCloseDuration = Math.round(value);
              await this.animationSettingsManager.setBookCloseDuration(this.bookCloseDuration);
            })
        }
        .width('100%')
        .padding({ left: 8 })
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
   * 构建主页面动画设置区域
   */
  @Builder
  buildMainPageAnimationSettings() {
    Column({ space: 16 }) {
      Text('主页面动画')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('控制主页面的动画效果，包括底部导航栏的滚动隐藏/显示动画。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 底栏动画开关
      Row() {
        Column({ space: 4 }) {
          Text('底栏动画效果')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('关闭后底部导航栏将常驻显示，不会自动隐藏')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.mainPageBottomBarAnimationEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            await this.animationSettingsManager.setMainPageBottomBarAnimationEnabled(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
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
   * 构建重置按钮区域
   */
  @Builder
  buildResetSection() {
    Column({ space: 12 }) {
      Button('恢复默认设置')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
        .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
        .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
        .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
        .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
        .clip(true)
        .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
        .onClick(async () => {
          await this.animationSettingsManager.setBookOpenAnimationEnabled(DEFAULT_ANIMATION_SETTINGS.bookOpenEnabled);
          await this.animationSettingsManager.setBookCloseAnimationEnabled(DEFAULT_ANIMATION_SETTINGS.bookCloseEnabled);
          await this.animationSettingsManager.setBookOpenDuration(DEFAULT_ANIMATION_SETTINGS.bookOpenDuration);
          await this.animationSettingsManager.setBookCloseDuration(DEFAULT_ANIMATION_SETTINGS.bookCloseDuration);
        })

      Text('恢复书籍开关动画设置为默认值')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .margin({ top: 8 })
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
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              // 书籍动画设置
              Column() {
                this.buildBookAnimationSettings()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'animation_book'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'animation_book') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'animation_book'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'animation_book', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'animation_book', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'animation_book',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })
              
              // 重置按钮
              Column() {
                this.buildResetSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'animation_reset'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'animation_reset') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'animation_reset'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'animation_reset', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'animation_reset', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'animation_reset',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })
            }
            .width('100%')

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
          title: '动画设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
