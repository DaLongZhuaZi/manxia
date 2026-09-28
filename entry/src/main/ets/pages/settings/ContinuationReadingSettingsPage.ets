import { HdsNavDestination, HdsNavDestinationAttribute } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ContinuationCacheManager } from '../../Framework/Distributed/ContinuationCacheManager';
import { ContinuationReadingSettingsManager } from '../../Framework/Distributed/ContinuationReadingSettingsManager';
import {
  ContinuationReadingSettings,
  ContinuationTransferMode
} from '../../Framework/Distributed/ContinuationReadingTypes';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'ContinuationReadingSettingsPage';
const COMPONENT_ID = 'ContinuationReadingSettingsPage';

@Component
export struct ContinuationReadingSettingsPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State private pathStack: NavPathStack = new NavPathStack();
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private fontState: FontAwareState = new FontAwareState();
  @State private settings: ContinuationReadingSettings = {
    readOnlyEnabled: true,
    importToLibraryEnabled: true,
    defaultMode: ContinuationTransferMode.READ_ONLY
  };
  @State private cacheSizeBytes: number = 0;
  @State private isClearingCache: boolean = false;
  @State private responsiveContentPadding: number = 16;
  @State private responsiveMaxContentWidth: number = 1200;
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  private settingsManager: ContinuationReadingSettingsManager = ContinuationReadingSettingsManager.getInstance();
  private cacheManager: ContinuationCacheManager = ContinuationCacheManager.getInstance();

  aboutToAppear(): void {
    this.updateResponsiveLayout();
    this.deviceChangeListener = (_deviceInfo: DeviceInfo): void => {
      this.updateResponsiveLayout();
    };
    this.deviceManager.addListener(this.deviceChangeListener);
  }

  private resolveAbilityContext(): common.UIAbilityContext | null {
    try {
      const hostContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      return hostContext ?? null;
    } catch (error) {
      logger.warn(TAG, `获取宿主上下文失败: ${String(error)}`);
      return null;
    }
  }

  private async loadSettings(): Promise<void> {
    const context = this.resolveAbilityContext();
    if (!context) {
      return;
    }
    try {
      await this.settingsManager.initialize(context);
      await this.cacheManager.initialize(context);
      this.settings = this.settingsManager.getSnapshot();
      this.cacheSizeBytes = await this.cacheManager.getCacheSize();
    } catch (error) {
      logger.error(TAG, `加载接续阅读设置失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '接续阅读设置加载失败' });
    }
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(COMPONENT_ID);
    FontAwareHelper.cleanupFontAware(COMPONENT_ID);
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private updateResponsiveLayout(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsiveContentPadding = layoutParams.contentPadding;
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsiveMaxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsiveMaxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsiveMaxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsiveMaxContentWidth = 1200;
        break;
      default:
        this.responsiveMaxContentWidth = 1200;
        break;
    }
  }

  private async setModeEnabled(mode: ContinuationTransferMode, enabled: boolean): Promise<void> {
    try {
      await this.settingsManager.setModeEnabled(mode, enabled);
      this.settings = this.settingsManager.getSnapshot();
    } catch (error) {
      logger.error(TAG, `更新接续方式开关失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '设置保存失败' });
    }
  }

  private async setDefaultMode(mode: ContinuationTransferMode): Promise<void> {
    try {
      await this.settingsManager.setDefaultMode(mode);
      this.settings = this.settingsManager.getSnapshot();
    } catch (error) {
      logger.error(TAG, `更新默认接续方式失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '设置保存失败' });
    }
  }

  private getCacheSizeText(): string {
    const bytes = Math.max(0, this.cacheSizeBytes);
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private async confirmAndClearCache(): Promise<void> {
    if (this.isClearingCache) {
      return;
    }
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '清理接续缓存',
      message: '将删除仅阅读接续保存的内容和对应的最近阅读记录。已导入书库的内容不会受影响。',
      buttons: [
        { text: '取消', color: $r('sys.color.font_secondary') },
        { text: '清理', color: $r('app.color.color_error') }
      ]
    });
    if (result.index !== 1) {
      return;
    }
    this.isClearingCache = true;
    try {
      await this.cacheManager.clearAll();
      this.cacheSizeBytes = await this.cacheManager.getCacheSize();
      AppStorage.setOrCreate('continuationCacheRevision', Date.now());
      this.getUIContext().getPromptAction().showToast({ message: '接续缓存已清理' });
    } catch (error) {
      logger.error(TAG, `清理接续缓存失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '接续缓存清理失败' });
    } finally {
      this.isClearingCache = false;
    }
  }

  @Builder
  private buildSettingRow(title: string, subtitle: string, enabled: boolean, mode: ContinuationTransferMode) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitle)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: enabled })
        .accessibilityText(title)
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .switchPointColor(Color.White)
        .onChange((value: boolean) => {
          void this.setModeEnabled(mode, value);
        })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  @Builder
  private buildSectionHeading(title: string, subtitle: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Text(subtitle)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, right: 4, bottom: 4 })
  }

  private isModeSelected(mode: ContinuationTransferMode): boolean {
    return this.settings.defaultMode === mode;
  }

  @Builder
  private buildModeOption(mode: ContinuationTransferMode, title: string, subtitle: string, enabled: boolean) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(20)
          .height(20)
          .fill(Color.Transparent)
          .stroke(this.isModeSelected(mode)
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .strokeWidth(this.isModeSelected(mode) ? 2 : 1.5)
        if (this.isModeSelected(mode)) {
          Circle()
            .width(10)
            .height(10)
            .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width(24)
      .height(24)

      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitle)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!enabled) {
        Text('已关闭')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(10)
    .backgroundColor(this.isModeSelected(mode) ? $r('app.color.accent_background') : Color.Transparent)
    .opacity(enabled ? 1 : 0.62)
    .onClick(() => {
      if (enabled) {
        void this.setDefaultMode(mode);
      }
    })
  }

  @Builder
  private buildContent() {
    Column({ space: 18 }) {
      this.buildSectionHeading('接续方式', '开启可用方式后，发起接续时会使用下面选定的默认方式。')
      Column() {
        this.buildSettingRow(
          '仅阅读接续',
          '内容仅保存在接收设备缓存，不加入书库。',
          this.settings.readOnlyEnabled,
          ContinuationTransferMode.READ_ONLY
        )
        Divider().color($r('sys.color.comp_divider'))
        this.buildSettingRow(
          '导入书库+接续',
          '完整传输内容并导入书库后继续阅读。',
          this.settings.importToLibraryEnabled,
          ContinuationTransferMode.IMPORT_TO_LIBRARY
        )
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })

      this.buildSectionHeading('默认方式', '关闭当前默认方式时，会自动切换到仍启用的方式。')
      Column({ space: 4 }) {
        this.buildModeOption(
          ContinuationTransferMode.READ_ONLY,
          '仅阅读',
          '文件放在接收设备缓存，不加入书库。',
          this.settings.readOnlyEnabled
        )
        this.buildModeOption(
          ContinuationTransferMode.IMPORT_TO_LIBRARY,
          '导入书库',
          '完整导入书籍，再按原位置继续阅读。',
          this.settings.importToLibraryEnabled
        )
      }
      .width('100%')
      .padding(8)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })

      this.buildSectionHeading('接续缓存', '仅阅读接续保存在本机，不进入书库；清理后会从最近阅读中移除。')
      Row() {
        Column({ space: 4 }) {
          Text('缓存占用')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.getCacheSizeText())
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('清理缓存')
          .enabled(!this.isClearingCache && this.cacheSizeBytes > 0)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor($r('app.color.background_secondary'))
          .borderRadius(10)
          .onClick(() => {
            void this.confirmAndClearCache();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll() {
          Column() {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            this.buildContent()
            Blank().height(32)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsiveMaxContentWidth })
          .padding({ left: this.responsiveContentPadding, right: this.responsiveContentPadding, bottom: 24 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '接续阅读',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack,
          contentPadding: 16
        })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      ThemeAwareHelper.initializeThemeAware(COMPONENT_ID, this.themeState, (_theme: ThemeType) => {});
      FontAwareHelper.initializeFontAware(COMPONENT_ID, this.fontState, (newState: FontAwareState) => {
        this.fontState = newState;
      });
      void this.loadSettings();
    })
    .backgroundColor(Color.Transparent)
  }
}
