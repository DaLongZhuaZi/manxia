import { hdsMaterial, HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import {
  DeviceAdaptationManager,
  DeviceInfo,
  DeviceChangeListener,
  Breakpoint
} from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import {
  VisualEffectsManager,
  VisualEffectsMaterialMode,
  VisualEffectsState,
  VisualEffectsStateListener
} from 'manxia_core/src/main/ets/Framework/Managers/VisualEffectsManager';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';

const TAG = 'VisualEffectsSettingsSubPage';

interface SelectOption {
  value: string;
}

@Component
export struct VisualEffectsSettingsSubPage {
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

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'VisualEffectsSettingsSubPage';

  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  private visualEffectsManager: VisualEffectsManager = VisualEffectsManager.getInstance();
  private stateListener: VisualEffectsStateListener | null = null;

  @State materialMode: VisualEffectsMaterialMode = VisualEffectsMaterialMode.ADAPTIVE;
  @State manualMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State effectiveMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @State supportedMaterialTypes: Array<hdsMaterial.MaterialType> = [hdsMaterial.MaterialType.ADAPTIVE];
  @State availableManualLevels: Array<hdsMaterial.MaterialLevel> = [hdsMaterial.MaterialLevel.SMOOTH];
  @State supportsImmersiveMaterial: boolean = false;
  @State supportsAdaptiveMaterial: boolean = true;
  @State recommendedManualLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State capabilityLastCheckedAt: number = 0;
  @State capabilityDetectError: string = '';
  @State isRefreshingCapability: boolean = false;
  @State isSavingSettings: boolean = false;

  private lifecycle = new PageLifecycleManager('VisualEffectsSettingsSubPage', { enableDebug: true });

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
      }
    } catch (error) {
      logger.error(TAG, 'Failed to read GlobalNavStack', String(error));
    }
  }

  onReady(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {});
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });

    this.initializeResponsiveLayout();
    void this.initializeVisualEffectsState();
  }

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

    if (this.stateListener) {
      this.visualEffectsManager.removeListener(this.stateListener);
      this.stateListener = null;
    }
  }

  private async initializeVisualEffectsState(): Promise<void> {
    try {
      if (!this.visualEffectsManager.isInitialized()) {
        await this.visualEffectsManager.initialize();
      }

      this.applyState(this.visualEffectsManager.getState());
      this.stateListener = (state: VisualEffectsState) => {
        this.applyState(state);
      };
      this.visualEffectsManager.addListener(this.stateListener);
      this.applyPendingSearchTarget();
    } catch (error) {
      logger.error(TAG, 'Failed to initialize visual effects state', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '视觉效果设置初始化失败',
        duration: 1800
      });
    }
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('VisualEffectsSettingsSubPage');
    if (!target) {
      return;
    }

    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `Failed to scroll to settings search target: ${String(error)}`);
      }
    }, 140);
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (_deviceInfo: DeviceInfo) => {
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, 'Failed to initialize responsive layout', String(error));
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

  private applyState(state: VisualEffectsState): void {
    this.materialMode = state.settings.materialMode;
    this.manualMaterialLevel = state.settings.manualMaterialLevel;
    this.effectiveMaterialLevel = state.effectiveMaterialLevel;
    this.supportedMaterialTypes = state.capability.supportedMaterialTypes.slice();
    this.availableManualLevels = state.capability.availableManualLevels.slice();
    this.supportsImmersiveMaterial = state.capability.supportsImmersiveMaterial;
    this.supportsAdaptiveMaterial = state.capability.supportsAdaptiveMaterial;
    this.recommendedManualLevel = state.capability.recommendedManualLevel;
    this.capabilityLastCheckedAt = state.capability.lastCheckedAt;
    this.capabilityDetectError = state.capability.detectError;
  }

  private syncStateFromManager(): void {
    this.applyState(this.visualEffectsManager.getState());
  }

  private getModeOptions(): Array<SelectOption> {
    return [
      { value: this.visualEffectsManager.getMaterialModeLabel(VisualEffectsMaterialMode.ADAPTIVE) },
      { value: this.visualEffectsManager.getMaterialModeLabel(VisualEffectsMaterialMode.MANUAL) }
    ];
  }

  private getManualLevelOptions(): Array<SelectOption> {
    return this.availableManualLevels.map((level: hdsMaterial.MaterialLevel) => {
      const option: SelectOption = {
        value: this.visualEffectsManager.getMaterialLevelLabel(level)
      };
      return option;
    });
  }

  private getMaterialModeSelectedIndex(): number {
    return this.materialMode === VisualEffectsMaterialMode.MANUAL ? 1 : 0;
  }

  private getManualLevelSelectedIndex(): number {
    const index = this.availableManualLevels.findIndex((level: hdsMaterial.MaterialLevel) => level === this.manualMaterialLevel);
    return index >= 0 ? index : 0;
  }

  private getCurrentMaterialModeLabel(): string {
    return this.visualEffectsManager.getMaterialModeLabel(this.materialMode);
  }

  private getCurrentManualLevelLabel(): string {
    return this.visualEffectsManager.getMaterialLevelLabel(this.manualMaterialLevel);
  }

  private getCurrentEffectiveLevelLabel(): string {
    return this.visualEffectsManager.getMaterialLevelLabel(this.effectiveMaterialLevel);
  }

  private getRecommendedManualLevelLabel(): string {
    return this.visualEffectsManager.getMaterialLevelLabel(this.recommendedManualLevel);
  }

  private getSupportedTypeText(): string {
    if (this.supportedMaterialTypes.length === 0) {
      return '未获取到类型信息';
    }
    return this.supportedMaterialTypes
      .map((type: hdsMaterial.MaterialType) => this.visualEffectsManager.getMaterialTypeLabel(type))
      .join('、');
  }

  private getAvailableManualLevelText(): string {
    if (this.availableManualLevels.length === 0) {
      return '无';
    }
    return this.availableManualLevels
      .map((level: hdsMaterial.MaterialLevel) => this.visualEffectsManager.getMaterialLevelLabel(level))
      .join('、');
  }

  private getCapabilitySummaryText(): string {
    if (this.supportsImmersiveMaterial) {
      return '当前设备声明支持沉浸式材质，可以手动选择精美、轻柔、流畅档位。';
    }
    return '当前设备未声明沉浸式材质，建议优先使用流畅档位以降低卡顿和发热风险。';
  }

  private getEffectiveDescription(): string {
    if (this.materialMode === VisualEffectsMaterialMode.ADAPTIVE) {
      return '当前由系统策略自动决定材质等级，适合优先兼顾性能与显示效果。';
    }

    if (!this.supportsImmersiveMaterial) {
      return '当前设备不支持沉浸式材质，手动模式下会限制为流畅档位。';
    }

    return '当前已固定为手动档位，组件应优先读取该等级作为统一的视觉效果策略。';
  }

  private getManualLevelHintText(): string {
    if (this.materialMode === VisualEffectsMaterialMode.ADAPTIVE) {
      return '手动档位会被保存下来，并在切换到“手动固定档位”后生效。';
    }
    return '手动档位已经生效，推荐优先使用系统建议值。';
  }

  private getLastCheckedText(): string {
    if (this.capabilityLastCheckedAt <= 0) {
      return '尚未检测';
    }
    return this.formatTimestamp(this.capabilityLastCheckedAt);
  }

  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    const second = `${date.getSeconds()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  private async handleMaterialModeSelected(index: number): Promise<void> {
    const nextMode = index === 1 ? VisualEffectsMaterialMode.MANUAL : VisualEffectsMaterialMode.ADAPTIVE;
    this.isSavingSettings = true;
    try {
      await this.visualEffectsManager.setMaterialMode(nextMode);
      this.syncStateFromManager();
    } catch (error) {
      logger.error(TAG, 'Failed to update material mode', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '更新材质策略失败',
        duration: 1800
      });
    } finally {
      this.isSavingSettings = false;
    }
  }

  private async handleManualLevelSelected(index: number): Promise<void> {
    const targetLevel = this.availableManualLevels[index];
    if (targetLevel === undefined) {
      return;
    }

    this.isSavingSettings = true;
    try {
      await this.visualEffectsManager.setManualMaterialLevel(targetLevel);
      this.syncStateFromManager();
    } catch (error) {
      logger.error(TAG, 'Failed to update manual material level', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '更新手动档位失败',
        duration: 1800
      });
    } finally {
      this.isSavingSettings = false;
    }
  }

  private async handleRefreshCapability(): Promise<void> {
    this.isRefreshingCapability = true;
    try {
      await this.visualEffectsManager.refreshCapability();
      this.syncStateFromManager();
      this.getUIContext().getPromptAction().showToast({
        message: this.capabilityDetectError.length > 0 ? '已完成检测，当前使用保守配置' : '设备材质能力已更新',
        duration: 1800
      });
    } catch (error) {
      logger.error(TAG, 'Failed to refresh material capability', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '重新检测设备能力失败',
        duration: 1800
      });
    } finally {
      this.isRefreshingCapability = false;
    }
  }

  private async handleResetToRecommended(): Promise<void> {
    this.isSavingSettings = true;
    try {
      await this.visualEffectsManager.resetToRecommended();
      this.syncStateFromManager();
      this.getUIContext().getPromptAction().showToast({
        message: '已恢复推荐设置',
        duration: 1600
      });
    } catch (error) {
      logger.error(TAG, 'Failed to reset visual effects settings', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '恢复推荐设置失败',
        duration: 1800
      });
    } finally {
      this.isSavingSettings = false;
    }
  }

  @Builder
  buildBadge(text: string, emphasize: boolean = false) {
    Text(text)
      .fontSize(12)
      .fontWeight(emphasize ? FontWeight.Medium : FontWeight.Regular)
      .fontFamily(this.appFontFamily)
      .fontColor(
        emphasize
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
      )
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(
        emphasize
          ? (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(76, 175, 80, 0.14)' : 'rgba(76, 175, 80, 0.10)')
          : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)
      )
      .borderRadius(999)
      .border({
        width: 1,
        color: emphasize
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  buildInfoRow(label: string, value: string, emphasize: boolean = false) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Blank()

      Text(value)
        .fontSize(13)
        .fontWeight(emphasize ? FontWeight.Medium : FontWeight.Regular)
        .fontFamily(this.appFontFamily)
        .fontColor(
          emphasize
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
        )
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildOverviewCard() {
    Column({ space: 14 }) {
      Row({ space: 14 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.lightbulb'))
            .fontSize(28)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        }
        .width(52)
        .height(52)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(
          this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.04)'
        )
        .borderRadius(16)

        Column({ space: 4 }) {
          Text('视觉效果管理器')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('通过系统 API 检测设备材质能力，并统一管理全局推荐策略与手动档位。')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        this.buildBadge(this.supportsImmersiveMaterial ? '支持沉浸式材质' : '未声明沉浸式材质', this.supportsImmersiveMaterial)
        this.buildBadge(`推荐手动档位：${this.getRecommendedManualLevelLabel()}`, true)
        this.buildBadge(`当前生效：${this.getCurrentEffectiveLevelLabel()}`)
      }
      .width('100%')

      Text(this.getCapabilitySummaryText())
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      Column({ space: 10 }) {
        this.buildInfoRow('支持材质类型', this.getSupportedTypeText())
        this.buildInfoRow('可手动档位', this.getAvailableManualLevelText())
        this.buildInfoRow('最近检测', this.getLastCheckedText())
        this.buildInfoRow('当前策略', this.getCurrentMaterialModeLabel(), true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.capabilityDetectError.length > 0) {
        Text(`最近一次检测返回错误，当前已回退到保守配置：${this.capabilityDetectError}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#D35454')
          .width('100%')
      }
    }
    .width('100%')
    .padding(18)
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
  buildStrategyCard() {
    Column({ space: 14 }) {
      Text('材质策略')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('优先推荐系统自适应；如果你希望固定视觉表现，也可以切换到手动固定档位。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Column({ space: 4 }) {
          Text('策略模式')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('系统自适应会把最终材质等级交给系统策略决定。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Select(this.getModeOptions())
          .selected(this.getMaterialModeSelectedIndex())
          .value(this.getCurrentMaterialModeLabel())
          .font({ size: 14 })
          .selectedOptionFont({ size: 14 })
          .optionFont({ size: 14 })
          .enabled(!this.isSavingSettings && !this.isRefreshingCapability)
          .onSelect((index: number) => {
            void this.handleMaterialModeSelected(index);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      Row() {
        Column({ space: 4 }) {
          Text('手动档位')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('管理器会根据设备能力过滤不可用档位。')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Select(this.getManualLevelOptions())
          .selected(this.getManualLevelSelectedIndex())
          .value(this.getCurrentManualLevelLabel())
          .font({ size: 14 })
          .selectedOptionFont({ size: 14 })
          .optionFont({ size: 14 })
          .enabled(!this.isSavingSettings && !this.isRefreshingCapability && this.availableManualLevels.length > 0)
          .onSelect((index: number) => {
            void this.handleManualLevelSelected(index);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Text(this.getManualLevelHintText())
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
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
  buildEffectiveCard() {
    Column({ space: 14 }) {
      Text('当前生效等级')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text(this.getCurrentEffectiveLevelLabel())
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text(this.getEffectiveDescription())
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))

      Column({ space: 10 }) {
        this.buildInfoRow('当前策略', this.getCurrentMaterialModeLabel())
        this.buildInfoRow('手动预设', this.getCurrentManualLevelLabel())
        this.buildInfoRow('推荐手动档位', this.getRecommendedManualLevelLabel(), true)
        this.buildInfoRow('支持自适应类型', this.supportsAdaptiveMaterial ? '支持' : '未声明')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
  buildActionsCard() {
    Column({ space: 12 }) {
      Text('操作')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('重新检测会再次调用系统 API；恢复推荐设置会把策略切回系统自适应，并把手动档位重置为当前设备的推荐值。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Button(this.isRefreshingCapability ? '正在检测设备能力...' : '重新检测设备能力')
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(Color.White)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(10)
        .enabled(!this.isRefreshingCapability)
        .onClick(() => {
          void this.handleRefreshCapability();
        })

      Button('恢复推荐设置')
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
        .enabled(!this.isSavingSettings)
        .onClick(() => {
          void this.handleResetToRecommended();
        })
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

            Column() {
              this.buildOverviewCard()
            }
            .width('100%')
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'visual_effects_capability'
            ))
            .borderRadius(18)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'visual_effects_capability') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_capability'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(
                this.activeSearchAnchorId,
                'visual_effects_capability',
                this.searchHighlightPulse
              ),
              y: SettingsSearchSupport.getHighlightScale(
                this.activeSearchAnchorId,
                'visual_effects_capability',
                this.searchHighlightPulse
              )
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'visual_effects_capability',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })

            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              Column() {
                this.buildStrategyCard()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_strategy'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'visual_effects_strategy') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'visual_effects_strategy'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_strategy',
                  this.searchHighlightPulse
                ),
                y: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_strategy',
                  this.searchHighlightPulse
                )
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_strategy',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              Column() {
                this.buildEffectiveCard()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_effective'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'visual_effects_effective') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'visual_effects_effective'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_effective',
                  this.searchHighlightPulse
                ),
                y: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_effective',
                  this.searchHighlightPulse
                )
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_effective',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              Column() {
                this.buildActionsCard()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_actions'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'visual_effects_actions') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'visual_effects_actions'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_actions',
                  this.searchHighlightPulse
                ),
                y: SettingsSearchSupport.getHighlightScale(
                  this.activeSearchAnchorId,
                  'visual_effects_actions',
                  this.searchHighlightPulse
                )
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'visual_effects_actions',
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
          title: '视觉效果',
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
