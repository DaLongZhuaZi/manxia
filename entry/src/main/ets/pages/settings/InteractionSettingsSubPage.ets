// 文件路径: entry/src/main/ets/pages/settings/InteractionSettingsSubPage.ets
/**
 * 交互设置子页面
 * 管理震动等交互体验设置
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { InteractionManager, VibrationScene, VibrationIntensity, InteractionSettings } from 'manxia_core/src/main/ets/Framework/Managers/InteractionManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import {
  getHoldingAwarenessManager,
  HoldingAwarenessConfidence,
  HoldingAwarenessFeature,
  HoldingAwarenessListener,
  HoldingAwarenessManager,
  HoldingAwarenessSide,
  HoldingAwarenessSnapshot,
  HoldingAwarenessSource
} from 'manxia_core/src/main/ets/Framework/Managers/HoldingAwarenessManager';

const TAG = 'InteractionSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface InteractionSettingsSubPageParams {
  fromPage?: string;
}

interface SceneGroup {
  title: string;
  scenes: VibrationScene[];
}

enum InteractionSettingsTab {
  VIBRATION = 0,
  HOLDING_AWARENESS = 1
}

@Component
export struct InteractionSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State @Watch('onSearchAnchorChanged') private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'InteractionSettingsSubPage';
  private interactionManager: InteractionManager = InteractionManager.getInstance();
  private holdingAwarenessManager: HoldingAwarenessManager = getHoldingAwarenessManager();
  private readonly holdingAwarenessListener: HoldingAwarenessListener = (snapshot: HoldingAwarenessSnapshot): void => {
    this.refreshHoldingAwarenessSettings(snapshot);
  };

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
  @State holdingAwarenessEnabled: boolean = true;
  @State holdingAwarenessMainMenuSearchButtonEnabled: boolean = true;
  @State holdingAwarenessMainMenuPrivacyExitButtonEnabled: boolean = true;
  @State holdingAwarenessMainMenuShelfPreviewEnabled: boolean = true;
  @State holdingAwarenessDetailLandscapeReadActionsEnabled: boolean = true;
  @State holdingAwarenessReadAloudFloatingBallEnabled: boolean = true;
  @State holdingAwarenessTaskFloatingBallEnabled: boolean = true;
  @State holdingAwarenessMangaWebtoonQuickNavigationEnabled: boolean = true;
  @State holdingAwarenessTextHighlightThoughtPopupEnabled: boolean = true;
  @State holdingAwarenessStatusText: string = '未检测';
  @State holdingAwarenessPermissionText: string = '未检测';
  @State private selectedInteractionTab: InteractionSettingsTab = InteractionSettingsTab.VIBRATION;

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
    this.holdingAwarenessManager.addListener(this.holdingAwarenessListener);
    this.loadSettings();
    void this.refreshHoldingAwarenessRuntimeState();
    this.applyPendingSearchTarget();
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('InteractionSettingsSubPage');
    if (!target) {
      return;
    }
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = this.resolveSearchScrollOffset(target.anchorId, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 140);
  }

  private getTabForAnchor(anchorId: string): InteractionSettingsTab {
    if (anchorId === 'interaction_holding_awareness') {
      return InteractionSettingsTab.HOLDING_AWARENESS;
    }
    return InteractionSettingsTab.VIBRATION;
  }

  onSearchAnchorChanged(): void {
    if (this.activeSearchAnchorId.length <= 0) {
      return;
    }
    const targetTab: InteractionSettingsTab = this.getTabForAnchor(this.activeSearchAnchorId);
    if (this.selectedInteractionTab !== targetTab) {
      this.selectedInteractionTab = targetTab;
    }
  }

  private resolveSearchScrollOffset(anchorId: string, fallbackOffset: number): number {
    if (this.getTabForAnchor(anchorId) === InteractionSettingsTab.HOLDING_AWARENESS) {
      return 0;
    }
    return Math.max(0, fallbackOffset);
  }

  private lifecycle = new PageLifecycleManager('InteractionSettingsSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    SettingsSearchSupport.clearHighlight(this);
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    this.holdingAwarenessManager.removeListener(this.holdingAwarenessListener);
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
    this.refreshHoldingAwarenessSettings();
    logger.info(TAG, '交互设置加载完成');
  }

  private async refreshHoldingAwarenessRuntimeState(): Promise<void> {
    try {
      await this.holdingAwarenessManager.resume();
      this.refreshHoldingAwarenessSettings();
    } catch (error) {
      logger.warn(TAG, `刷新智感握姿状态失败：${String(error)}`);
    }
  }

  private refreshHoldingAwarenessSettings(snapshot?: HoldingAwarenessSnapshot): void {
    this.holdingAwarenessEnabled = this.holdingAwarenessManager.isGlobalEnabled();
    this.holdingAwarenessMainMenuSearchButtonEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.MAIN_MENU_FLOATING_SEARCH_BUTTON);
    this.holdingAwarenessMainMenuPrivacyExitButtonEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.MAIN_MENU_PRIVACY_EXIT_BUTTON);
    this.holdingAwarenessMainMenuShelfPreviewEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.MAIN_MENU_SHELF_PREVIEW_CONTROLS);
    this.holdingAwarenessDetailLandscapeReadActionsEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.DETAIL_LANDSCAPE_READ_ACTIONS);
    this.holdingAwarenessReadAloudFloatingBallEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.READ_ALOUD_FLOATING_BALL);
    this.holdingAwarenessTaskFloatingBallEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.TASK_FLOATING_BALL);
    this.holdingAwarenessMangaWebtoonQuickNavigationEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.MANGA_WEBTOON_QUICK_NAVIGATION);
    this.holdingAwarenessTextHighlightThoughtPopupEnabled =
      this.holdingAwarenessManager.isFeatureEnabled(HoldingAwarenessFeature.TEXT_HIGHLIGHT_THOUGHT_POPUP);
    const currentSnapshot: HoldingAwarenessSnapshot = snapshot ? snapshot : this.holdingAwarenessManager.getSnapshot();
    this.holdingAwarenessStatusText =
      `${this.describeHoldingAwarenessSide(currentSnapshot.side)} / ${this.describeHoldingAwarenessSource(currentSnapshot.source)} / ${this.describeHoldingAwarenessConfidence(currentSnapshot.confidence)}`;
    this.holdingAwarenessPermissionText =
      `握姿权限${currentSnapshot.detectGestureGranted ? '已授权' : '未授权'}，动作权限${currentSnapshot.activityMotionGranted ? '已授权' : '未授权'}，${currentSnapshot.available ? '当前可用' : '当前不可用'}`;
  }

  private describeHoldingAwarenessSide(side: HoldingAwarenessSide): string {
    switch (side) {
      case HoldingAwarenessSide.NONE:
        return '未握持';
      case HoldingAwarenessSide.LEFT:
        return '左手握持';
      case HoldingAwarenessSide.RIGHT:
        return '右手握持';
      case HoldingAwarenessSide.BOTH:
        return '双手握持';
      default:
        return '未知握姿';
    }
  }

  private describeHoldingAwarenessSource(source: HoldingAwarenessSource): string {
    switch (source) {
      case HoldingAwarenessSource.HOLDING_HAND:
        return '智感握姿';
      case HoldingAwarenessSource.OPERATING_HAND:
        return '操作手';
      case HoldingAwarenessSource.COMBINED:
        return '联合判断';
      default:
        return '默认回退';
    }
  }

  private describeHoldingAwarenessConfidence(confidence: HoldingAwarenessConfidence): string {
    switch (confidence) {
      case HoldingAwarenessConfidence.EXACT:
        return '精确';
      case HoldingAwarenessConfidence.INFERRED:
        return '推断';
      default:
        return '回退';
    }
  }

  private async setHoldingAwarenessFeatureEnabled(feature: HoldingAwarenessFeature, enabled: boolean): Promise<void> {
    await this.holdingAwarenessManager.setFeatureEnabled(feature, enabled);
    this.refreshHoldingAwarenessSettings();
    this.interactionManager.vibrate(VibrationScene.TOGGLE_SWITCH);
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
          VibrationScene.BUTTON_CLICK
        ]
      },
      {
        title: '系统提示',
        scenes: [
          VibrationScene.WARNING
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
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
  }

  @Builder
  buildSettingRow(title: string, description: string, isOn: boolean, onChange: (value: boolean) => void) {
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
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
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

  @Builder
  buildHoldingAwarenessStatus() {
    Column({ space: 8 }) {
      Text('当前状态')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')

      Text(this.holdingAwarenessStatusText)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Text(this.holdingAwarenessPermissionText)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  @Builder
  buildHoldingAwarenessSettings() {
    Column() {
      this.buildSettingRow(
        '启用智感握姿',
        '根据握持手与操作手自动调整支持的交互位置',
        this.holdingAwarenessEnabled,
        async (value: boolean) => {
          this.holdingAwarenessEnabled = value;
          await this.holdingAwarenessManager.setGlobalEnabled(value);
          this.refreshHoldingAwarenessSettings();
          this.interactionManager.vibrate(VibrationScene.TOGGLE_SWITCH);
        }
      )

      if (this.holdingAwarenessEnabled) {
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '主界面搜索按钮',
          '全局搜索悬浮按钮按握姿自动停靠到易触达侧',
          this.holdingAwarenessMainMenuSearchButtonEnabled,
          async (value: boolean) => {
            this.holdingAwarenessMainMenuSearchButtonEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.MAIN_MENU_FLOATING_SEARCH_BUTTON,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '隐私书库退出按钮',
          '隐私模式下的退出悬浮按钮按握姿选择停靠侧',
          this.holdingAwarenessMainMenuPrivacyExitButtonEnabled,
          async (value: boolean) => {
            this.holdingAwarenessMainMenuPrivacyExitButtonEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.MAIN_MENU_PRIVACY_EXIT_BUTTON,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '书架预览控件',
          '编辑书架时的列数滑条与详情浮层按握姿靠近拇指侧',
          this.holdingAwarenessMainMenuShelfPreviewEnabled,
          async (value: boolean) => {
            this.holdingAwarenessMainMenuShelfPreviewEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.MAIN_MENU_SHELF_PREVIEW_CONTROLS,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '详情页横屏阅读按钮',
          '横屏详情页的阅读与听书浮动按钮组按握姿停靠',
          this.holdingAwarenessDetailLandscapeReadActionsEnabled,
          async (value: boolean) => {
            this.holdingAwarenessDetailLandscapeReadActionsEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.DETAIL_LANDSCAPE_READ_ACTIONS,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '听书悬浮球',
          '听书悬浮球未被手动拖动时按握姿选择默认停靠侧',
          this.holdingAwarenessReadAloudFloatingBallEnabled,
          async (value: boolean) => {
            this.holdingAwarenessReadAloudFloatingBallEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.READ_ALOUD_FLOATING_BALL,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '后台任务悬浮球',
          '后台任务进度悬浮球未被手动拖动时按握姿选择默认停靠侧',
          this.holdingAwarenessTaskFloatingBallEnabled,
          async (value: boolean) => {
            this.holdingAwarenessTaskFloatingBallEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.TASK_FLOATING_BALL,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '漫画条漫快速导航',
          '条漫与连续滚动模式的快速导航滑条按握姿切换左右侧',
          this.holdingAwarenessMangaWebtoonQuickNavigationEnabled,
          async (value: boolean) => {
            this.holdingAwarenessMangaWebtoonQuickNavigationEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.MANGA_WEBTOON_QUICK_NAVIGATION,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildSettingRow(
          '文本划线想法悬浮窗',
          '小说划线想法浮窗按握姿靠近易操作侧显示',
          this.holdingAwarenessTextHighlightThoughtPopupEnabled,
          async (value: boolean) => {
            this.holdingAwarenessTextHighlightThoughtPopupEnabled = value;
            await this.setHoldingAwarenessFeatureEnabled(
              HoldingAwarenessFeature.TEXT_HIGHLIGHT_THOUGHT_POPUP,
              value
            );
          }
        )

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .margin({ left: 16 })

        this.buildHoldingAwarenessStatus()
      }
    }
    .width('100%')
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
    .width('100%')
  }

  @Builder
  buildInteractionTabButton(tab: InteractionSettingsTab, label: string) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.selectedInteractionTab === tab
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .fontWeight(this.selectedInteractionTab === tab ? FontWeight.Bold : FontWeight.Normal)
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })

      Divider()
        .strokeWidth(2)
        .color(this.selectedInteractionTab === tab
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : Color.Transparent)
        .width('60%')
    }
    .layoutWeight(1)
    .onClick(() => {
      this.selectedInteractionTab = tab;
    })
  }

  @Builder
  buildInteractionTabBar() {
    Row({ space: 0 }) {
      this.buildInteractionTabButton(InteractionSettingsTab.VIBRATION, '震动反馈')
      this.buildInteractionTabButton(InteractionSettingsTab.HOLDING_AWARENESS, '智感握姿')
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .margin({ left: 16, right: 16 })
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
            this.buildInteractionTabBar()

            if (this.selectedInteractionTab === InteractionSettingsTab.VIBRATION) {
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
                        await this.holdingAwarenessManager.setGlobalEnabled(true);
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.MAIN_MENU_FLOATING_SEARCH_BUTTON,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.MAIN_MENU_PRIVACY_EXIT_BUTTON,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.MAIN_MENU_SHELF_PREVIEW_CONTROLS,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.DETAIL_LANDSCAPE_READ_ACTIONS,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.READ_ALOUD_FLOATING_BALL,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.TASK_FLOATING_BALL,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.MANGA_WEBTOON_QUICK_NAVIGATION,
                          true
                        );
                        await this.holdingAwarenessManager.setFeatureEnabled(
                          HoldingAwarenessFeature.TEXT_HIGHLIGHT_THOUGHT_POPUP,
                          true
                        );
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
              .animation({ duration: 260, curve: Curve.EaseOut })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ y: 12 }).animation({ duration: 220, curve: Curve.EaseOut })),
                TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
              ))
            }

            if (this.selectedInteractionTab === InteractionSettingsTab.HOLDING_AWARENESS) {
              Column() {
                this.buildHoldingAwarenessSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'interaction_holding_awareness'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'interaction_holding_awareness') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'interaction_holding_awareness'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_holding_awareness', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'interaction_holding_awareness', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'interaction_holding_awareness',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .transition(TransitionEffect.asymmetric(
                TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
                  .combine(TransitionEffect.translate({ y: 12 }).animation({ duration: 220, curve: Curve.EaseOut })),
                TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
              ))
              .margin({ bottom: 16 })
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
        .scrollBar(BarState.Auto)
        .onDidScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '交互设置',
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
