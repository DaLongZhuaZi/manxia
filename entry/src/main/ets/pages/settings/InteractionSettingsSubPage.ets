// 文件路径: entry/src/main/ets/pages/settings/InteractionSettingsSubPage.ets
/**
 * 交互设置子页面
 * 管理震动等交互体验设置
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareHelper, ThemeAwareState } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { InteractionManager, VibrationScene, VibrationIntensity, InteractionSettings } from '../../Framework/Managers/InteractionManager';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from './SettingsSearchSupport';

const TAG = 'InteractionSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface InteractionSettingsSubPageParams {
  fromPage?: string;
}

interface SceneGroup {
  title: string;
  scenes: VibrationScene[];
}

@Component
export struct InteractionSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'InteractionSettingsSubPage';
  private interactionManager: InteractionManager = InteractionManager.getInstance();

  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  @State vibrationEnabled: boolean = true;
  @State vibrationIntensity: VibrationIntensity = VibrationIntensity.LEVEL_3;
  @State sceneButtonClick: boolean = true;
  @State sceneToggleSwitch: boolean = true;
  @State sceneListItemSelect: boolean = true;
  @State sceneLongPress: boolean = true;
  @State sceneSwipeAction: boolean = true;
  @State scenePageTurn: boolean = false;
  @State sceneChapterChange: boolean = true;
  @State sceneBookmarkAdd: boolean = true;
  @State sceneDownloadComplete: boolean = true;
  @State sceneDownloadError: boolean = true;
  @State sceneSuccess: boolean = true;
  @State sceneError: boolean = true;
  @State sceneWarning: boolean = true;
  @State sceneNotification: boolean = true;

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
    this.initializeResponsiveLayout();
    this.loadSettings();
    this.applyPendingSearchTarget();
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('InteractionSettingsSubPage');
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

  private lifecycle = new PageLifecycleManager('InteractionSettingsSubPage', { enableDebug: true });

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
    const settings = this.interactionManager.getSettings();
    this.vibrationEnabled = settings.vibrationEnabled;
    this.vibrationIntensity = settings.vibrationIntensity;
    this.sceneButtonClick = settings.sceneSettings[VibrationScene.BUTTON_CLICK] !== false;
    this.sceneToggleSwitch = settings.sceneSettings[VibrationScene.TOGGLE_SWITCH] !== false;
    this.sceneListItemSelect = settings.sceneSettings[VibrationScene.LIST_ITEM_SELECT] !== false;
    this.sceneLongPress = settings.sceneSettings[VibrationScene.LONG_PRESS] !== false;
    this.sceneSwipeAction = settings.sceneSettings[VibrationScene.SWIPE_ACTION] !== false;
    this.scenePageTurn = settings.sceneSettings[VibrationScene.PAGE_TURN] !== false;
    this.sceneChapterChange = settings.sceneSettings[VibrationScene.CHAPTER_CHANGE] !== false;
    this.sceneBookmarkAdd = settings.sceneSettings[VibrationScene.BOOKMARK_ADD] !== false;
    this.sceneDownloadComplete = settings.sceneSettings[VibrationScene.DOWNLOAD_COMPLETE] !== false;
    this.sceneDownloadError = settings.sceneSettings[VibrationScene.DOWNLOAD_ERROR] !== false;
    this.sceneSuccess = settings.sceneSettings[VibrationScene.SUCCESS] !== false;
    this.sceneError = settings.sceneSettings[VibrationScene.ERROR] !== false;
    this.sceneWarning = settings.sceneSettings[VibrationScene.WARNING] !== false;
    this.sceneNotification = settings.sceneSettings[VibrationScene.NOTIFICATION] !== false;
    logger.info(TAG, '交互设置加载完成');
  }

  private getSceneValue(scene: VibrationScene): boolean {
    switch (scene) {
      case VibrationScene.BUTTON_CLICK: return this.sceneButtonClick;
      case VibrationScene.TOGGLE_SWITCH: return this.sceneToggleSwitch;
      case VibrationScene.LIST_ITEM_SELECT: return this.sceneListItemSelect;
      case VibrationScene.LONG_PRESS: return this.sceneLongPress;
      case VibrationScene.SWIPE_ACTION: return this.sceneSwipeAction;
      case VibrationScene.PAGE_TURN: return this.scenePageTurn;
      case VibrationScene.CHAPTER_CHANGE: return this.sceneChapterChange;
      case VibrationScene.BOOKMARK_ADD: return this.sceneBookmarkAdd;
      case VibrationScene.DOWNLOAD_COMPLETE: return this.sceneDownloadComplete;
      case VibrationScene.DOWNLOAD_ERROR: return this.sceneDownloadError;
      case VibrationScene.SUCCESS: return this.sceneSuccess;
      case VibrationScene.ERROR: return this.sceneError;
      case VibrationScene.WARNING: return this.sceneWarning;
      case VibrationScene.NOTIFICATION: return this.sceneNotification;
      default: return true;
    }
  }

  private setSceneValue(scene: VibrationScene, value: boolean): void {
    switch (scene) {
      case VibrationScene.BUTTON_CLICK: this.sceneButtonClick = value; break;
      case VibrationScene.TOGGLE_SWITCH: this.sceneToggleSwitch = value; break;
      case VibrationScene.LIST_ITEM_SELECT: this.sceneListItemSelect = value; break;
      case VibrationScene.LONG_PRESS: this.sceneLongPress = value; break;
      case VibrationScene.SWIPE_ACTION: this.sceneSwipeAction = value; break;
      case VibrationScene.PAGE_TURN: this.scenePageTurn = value; break;
      case VibrationScene.CHAPTER_CHANGE: this.sceneChapterChange = value; break;
      case VibrationScene.BOOKMARK_ADD: this.sceneBookmarkAdd = value; break;
      case VibrationScene.DOWNLOAD_COMPLETE: this.sceneDownloadComplete = value; break;
      case VibrationScene.DOWNLOAD_ERROR: this.sceneDownloadError = value; break;
      case VibrationScene.SUCCESS: this.sceneSuccess = value; break;
      case VibrationScene.ERROR: this.sceneError = value; break;
      case VibrationScene.WARNING: this.sceneWarning = value; break;
      case VibrationScene.NOTIFICATION: this.sceneNotification = value; break;
    }
  }

  private getSceneGroups(): SceneGroup[] {
    return [
      {
        title: '通用交互',
        scenes: [
          VibrationScene.BUTTON_CLICK,
          VibrationScene.TOGGLE_SWITCH,
          VibrationScene.LIST_ITEM_SELECT,
          VibrationScene.LONG_PRESS,
          VibrationScene.SWIPE_ACTION,
        ]
      },
      {
        title: '阅读器',
        scenes: [
          VibrationScene.PAGE_TURN,
          VibrationScene.CHAPTER_CHANGE,
          VibrationScene.BOOKMARK_ADD,
        ]
      },
      {
        title: '下载',
        scenes: [
          VibrationScene.DOWNLOAD_COMPLETE,
          VibrationScene.DOWNLOAD_ERROR,
        ]
      },
      {
        title: '系统提示',
        scenes: [
          VibrationScene.SUCCESS,
          VibrationScene.ERROR,
          VibrationScene.WARNING,
          VibrationScene.NOTIFICATION,
        ]
      }
    ];
  }

  @Builder
  buildSettingItem(title: string, description: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        if (description) {
          Text(description)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((value: boolean) => {
          onChange(value);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }

  @Builder
  buildIntensitySelector() {
    Column({ space: 8 }) {
      Text('震动强度')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 4 }) {
        ForEach(InteractionManager.getAllIntensities(), (intensity: VibrationIntensity) => {
          Button(InteractionManager.getIntensityDisplayName(intensity))
            .fontSize(13)
            .height(36)
            .layoutWeight(1)
            .fontFamily(this.appFontFamily)
            .backgroundColor(this.vibrationIntensity === intensity
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(this.vibrationIntensity === intensity
              ? '#FFFFFF'
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(8)
            .onClick(async () => {
              this.vibrationIntensity = intensity;
              await this.interactionManager.setVibrationIntensity(intensity);
              this.interactionManager.vibrate(VibrationScene.BUTTON_CLICK);
            })
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildSceneGroup(group: SceneGroup) {
    Column({ space: 0 }) {
      Text(group.title)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
        .padding({ left: 16, bottom: 8 })

      Column() {
        ForEach(group.scenes, (scene: VibrationScene, index: number) => {
          Column() {
            this.buildSettingItem(
              InteractionManager.getSceneDisplayName(scene),
              '',
              this.getSceneValue(scene),
              async (value: boolean) => {
                this.setSceneValue(scene, value);
                await this.interactionManager.setSceneEnabled(scene, value);
                if (value) {
                  this.interactionManager.vibrate(scene);
                }
              }
            )
            if (index < group.scenes.length - 1) {
              Divider()
                .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
                .margin({ left: 16 })
            }
          }
        })
      }
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    }
    .width('100%')
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
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              // 全局开关
              Column() {
                Column() {
                  this.buildSettingItem(
                    '启用震动反馈',
                    '关闭后所有震动效果将被禁用',
                    this.vibrationEnabled,
                    async (value: boolean) => {
                      this.vibrationEnabled = value;
                      await this.interactionManager.setVibrationEnabled(value);
                      if (value) {
                        this.interactionManager.vibrate(VibrationScene.TOGGLE_SWITCH);
                      }
                    }
                  )
                }
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
                .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'interaction_basic'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'interaction_basic') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_basic'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_basic', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_basic', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'interaction_basic',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              if (this.vibrationEnabled) {
                // 震动强度
                Column() {
                  this.buildIntensitySelector()
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_intensity'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'interaction_intensity') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'interaction_intensity'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_intensity', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_intensity', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_intensity',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })

                // 场景设置
                Flex({
                  wrap: FlexWrap.Wrap,
                  justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
                }) {
                  ForEach(this.getSceneGroups(), (group: SceneGroup) => {
                    Column() {
                      this.buildSceneGroup(group)
                    }
                    .width(this.responsive_isLandscape ? '48%' : '100%')
                    .margin({ bottom: 16 })
                  })
                }
                .width('100%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_scene'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'interaction_scene') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'interaction_scene'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_scene', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_scene', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_scene',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })

                // 重置按钮
                Column() {
                  Button('恢复默认设置')
                    .width('100%')
                    .height(44)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .borderRadius(12)
                    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
                    .onClick(async () => {
                      await this.interactionManager.resetToDefault();
                      this.loadSettings();
                      this.interactionManager.vibrate(VibrationScene.SUCCESS);
                    })
                }
                .width(this.responsive_isLandscape ? '48%' : '100%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_reset'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'interaction_reset') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'interaction_reset'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_reset', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_reset', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_reset',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }
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
        .scrollBar(BarState.Auto)
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
        title: { mainTitle: '交互设置' }
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
