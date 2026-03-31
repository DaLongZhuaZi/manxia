// 文件路径: entry/src/main/ets/pages/settings/AdvancedSettingsSubPage.ets
/**
 * 高级设置子页面
 * 包含调试设置、开发者选项、SFW模式等
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';
import { ContentFilterManager } from '../../Framework/Managers/ContentFilterManager';
import { WelcomeGuideManager } from '../../Framework/Managers/WelcomeGuideManager';
import { AppGuideManager } from '../../Framework/Managers/AppGuideManager';
import { common, Want } from '@kit.AbilityKit';
import { logger, LOG_LEVEL_NAMES, LOG_LEVEL_VALUES, LogLevel } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport } from './SettingsSearchSupport';
import { setReaderKitEnabled } from '../../Framework/Initialization/ReaderKitFeatureGate';
import { SettingsGlassStyleHelper } from './SettingsGlassStyleHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'AdvancedSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 导航参数接口
interface AdvancedSettingsSubPageParams {
  fromPage?: string;
}

@Component
export struct AdvancedSettingsSubPage {
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
  @StorageLink('source_settings_visible') sourceSettingsVisible: boolean = false;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'AdvancedSettingsSubPage';
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private welcomeGuideManager: WelcomeGuideManager = WelcomeGuideManager.getInstance();
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 调试设置
  @State autoCheckUpdates: boolean = true;
  @State enableLogFloatingWindow: boolean = true;
  @State advancedModeEnabled: boolean = true;
  @State forceTabletMode: boolean = false;
  @State forceLandscapeMode: boolean = false;
  @State readerKitEnabled: boolean = true;
  @State preloadDebugMode: string = 'off';
  @State showRestartDialog: boolean = false;
  
  // 内容过滤设置
  @State sfwModeEnabled: boolean = false;
  @State nsfwScopeImageSourceEnabled: boolean = true;
  @State nsfwScopeBookSourceEnabled: boolean = true;
  private contentFilterManager: ContentFilterManager = ContentFilterManager.getInstance();
  
  // 隐私保护设置
  @State backgroundBlurEnabled: boolean = false;
  @State backgroundBlurBgType: string = 'solid'; // 'solid' | 'custom'
  @State backgroundBlurBgImage: string = '';
  @State backgroundBlurIconType: string = 'shield'; // 'shield' | 'logo'
  
  // 日志等级设置
  @State logOutputLevelIndex: number = 0; // 默认关闭 (0=关闭, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR, 5=FATAL)
  private otherActionsSecretTapCount: number = 0;
  private otherActionsSecretTapTimer: number = -1;
  private ignoreNextOtherActionsSecretTap: boolean = false;

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

  private clearOtherActionsSecretTapTimer(): void {
    if (this.otherActionsSecretTapTimer >= 0) {
      clearTimeout(this.otherActionsSecretTapTimer);
      this.otherActionsSecretTapTimer = -1;
    }
  }

  private resetOtherActionsSecretTap(): void {
    this.otherActionsSecretTapCount = 0;
    this.clearOtherActionsSecretTapTimer();
  }

  private async handleOtherActionsSecretTap(): Promise<void> {
    if (this.ignoreNextOtherActionsSecretTap) {
      this.ignoreNextOtherActionsSecretTap = false;
      return;
    }

    this.otherActionsSecretTapCount += 1;
    this.clearOtherActionsSecretTapTimer();
    this.otherActionsSecretTapTimer = setTimeout(() => {
      this.otherActionsSecretTapCount = 0;
      this.otherActionsSecretTapTimer = -1;
    }, 1500);

    if (this.otherActionsSecretTapCount < 5) {
      return;
    }

    this.resetOtherActionsSecretTap();

    if (this.sourceSettingsVisible) {
      promptAction.showToast({
        message: '源功能设置已显示',
        duration: 1500
      });
      return;
    }

    this.sourceSettingsVisible = true;
    await this.settingsManager.setBoolean(SettingKeys.SOURCE_SETTINGS_VISIBLE, true);
    this.settingsManager.syncToAppStorage();
    AppStorage.setOrCreate('source_settings_visible', true);
    promptAction.showToast({
      message: '已显示源功能设置',
      duration: 1500
    });
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
    const target = SettingsSearchSupport.consumePendingTarget('AdvancedSettingsSubPage');
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

  private lifecycle = new PageLifecycleManager('AdvancedSettingsSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    this.resetOtherActionsSecretTap();
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
      this.autoCheckUpdates = this.settingsManager.getBoolean(
        SettingKeys.AUTO_CHECK_UPDATES,
        true
      );

      this.enableLogFloatingWindow = this.settingsManager.getBoolean(
        SettingKeys.ENABLE_LOG_FLOATING_WINDOW,
        false
      );

      this.advancedModeEnabled = this.settingsManager.getBoolean(
        SettingKeys.ADVANCED_MODE_ENABLED,
        true
      );

      this.forceTabletMode = this.settingsManager.getBoolean(
        SettingKeys.FORCE_TABLET_MODE,
        false
      );

      this.forceLandscapeMode = this.settingsManager.getBoolean(
        SettingKeys.FORCE_LANDSCAPE_MODE,
        false
      );
      this.readerKitEnabled = this.settingsManager.getBoolean(
        SettingKeys.READER_KIT_ENABLED,
        true
      );

      this.preloadDebugMode = this.settingsManager.getString(
        SettingKeys.PRELOAD_DEBUG_MODE,
        'off'
      );
      
      // 加载SFW模式设置
      this.sfwModeEnabled = this.contentFilterManager.isSFWModeEnabled();
      
      // 加载NSFW作用域设置
      this.nsfwScopeImageSourceEnabled = this.contentFilterManager.isNsfwScopeImageSourceEnabled();
      this.nsfwScopeBookSourceEnabled = this.contentFilterManager.isNsfwScopeBookSourceEnabled();
      
      // 加载后台模糊设置
      this.backgroundBlurEnabled = this.settingsManager.getBoolean(
        SettingKeys.BACKGROUND_BLUR_ENABLED,
        false
      );
      this.backgroundBlurBgType = this.settingsManager.getString(
        SettingKeys.BACKGROUND_BLUR_BG_TYPE,
        'solid'
      );
      this.backgroundBlurBgImage = this.settingsManager.getString(
        SettingKeys.BACKGROUND_BLUR_BG_IMAGE,
        ''
      );
      this.backgroundBlurIconType = this.settingsManager.getString(
        SettingKeys.BACKGROUND_BLUR_ICON_TYPE,
        'shield'
      );
      
      // 加载日志等级设置
      this.logOutputLevelIndex = this.settingsManager.getNumber(
        SettingKeys.LOG_OUTPUT_LEVEL,
        0  // 默认关闭
      );
      // 同步到logger
      logger.initializeHilogLevelFromIndex(this.logOutputLevelIndex);

      logger.info(TAG, '高级设置加载完成');
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
   * 构建调试设置区域
   */
  @Builder
  buildDebugSettings() {
    Column({ space: 16 }) {
      Text('调试设置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Column({ space: 4 }) {
          Text('高级模式')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('启用后显示更多开发者选项')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('显示实时日志输出')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('在手机上使用平板布局')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('锁定应用为横屏显示')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
            Text('预加载调试信息')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('显示漫画阅读器的预加载队列详情')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Select([
            { value: '关闭' },
            { value: '开启' },
            { value: '常驻' }
          ])
            .selected(this.preloadDebugMode === 'off' ? 0 : (this.preloadDebugMode === 'on' ? 1 : 2))
            .value(this.preloadDebugMode === 'off' ? '关闭' : (this.preloadDebugMode === 'on' ? '开启' : '常驻'))
            .font({ size: 14 })
            .selectedOptionFont({ size: 14 })
            .optionFont({ size: 14 })
            .onSelect(async (index: number) => {
              const modes = ['off', 'on', 'always'];
              this.preloadDebugMode = modes[index];
              await this.settingsManager.setString(SettingKeys.PRELOAD_DEBUG_MODE, modes[index]);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('ReaderKit 系统能力')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('启用后 EPUB/MOBI/AZW 将优先使用系统 ReaderKit')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.readerKitEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.readerKitEnabled = isOn;
              await setReaderKitEnabled(isOn);
              this.settingsManager.syncToAppStorage();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Column({ space: 4 }) {
            Text('SFW模式')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('隐藏所有NSFW(成人)内容')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.sfwModeEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.sfwModeEnabled = isOn;
              await this.contentFilterManager.setSFWMode(isOn);
              promptAction.showToast({
                message: isOn ? 'SFW模式已启用，已隐藏NSFW内容' : 'SFW模式已关闭',
                duration: 2000
              });
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        // NSFW作用域子开关（仅在SFW模式关闭时显示）
        if (!this.sfwModeEnabled) {
          Row() {
            Column({ space: 4 }) {
              Text('图源NSFW作用域')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('入库时从图源继承NSFW标记')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)

            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.nsfwScopeImageSourceEnabled })
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .onChange(async (isOn: boolean) => {
                this.nsfwScopeImageSourceEnabled = isOn;
                await this.contentFilterManager.setNsfwScopeImageSource(isOn);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 16 })

          Row() {
            Column({ space: 4 }) {
              Text('书源NSFW作用域')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('入库时从书源继承NSFW标记')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)

            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.nsfwScopeBookSourceEnabled })
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .onChange(async (isOn: boolean) => {
                this.nsfwScopeBookSourceEnabled = isOn;
                await this.contentFilterManager.setNsfwScopeBookSource(isOn);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 16 })
        }

        Row() {
          Column({ space: 4 }) {
            Text('自动检查更新')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('启动时检查应用更新')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
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
            Text('后台模糊遮罩')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('在多任务界面显示模糊效果保护隐私')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.backgroundBlurEnabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (isOn: boolean) => {
              this.backgroundBlurEnabled = isOn;
              await this.settingsManager.setBoolean(SettingKeys.BACKGROUND_BLUR_ENABLED, isOn);
              this.settingsManager.syncToAppStorage();
              // 同步到AppStorage供全局使用
              AppStorage.setOrCreate('backgroundBlurEnabled', isOn);
              promptAction.showToast({
                message: isOn ? '后台模糊遮罩已启用' : '后台模糊遮罩已关闭',
                duration: 2000
              });
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        // 后台遮罩自定义选项（仅在启用时显示）
        if (this.backgroundBlurEnabled) {
          // 图标类型选择
          Row() {
            Column({ space: 4 }) {
              Text('遮罩图标')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('选择遮罩中央显示的图标')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Select([
              { value: '锁定图标' },
              { value: '应用Logo' }
            ])
              .selected(this.backgroundBlurIconType === 'shield' ? 0 : 1)
              .value(this.backgroundBlurIconType === 'shield' ? '锁定图标' : '应用Logo')
              .font({ size: 14 })
              .selectedOptionFont({ size: 14 })
              .optionFont({ size: 14 })
              .onSelect(async (index: number) => {
                const iconType = index === 0 ? 'shield' : 'logo';
                this.backgroundBlurIconType = iconType;
                await this.settingsManager.setString(SettingKeys.BACKGROUND_BLUR_ICON_TYPE, iconType);
                this.settingsManager.syncToAppStorage();
                AppStorage.setOrCreate('backgroundBlurIconType', iconType);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        
        // 日志等级设置
        Row() {
          Column({ space: 4 }) {
            Text('日志等级')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text('控制hilog日志输出等级，关闭后不输出任何日志')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Select([
            { value: '关闭' },
            { value: 'DEBUG' },
            { value: 'INFO' },
            { value: 'WARN' },
            { value: 'ERROR' },
            { value: 'FATAL' }
          ])
            .selected(this.logOutputLevelIndex)
            .value(LOG_LEVEL_NAMES[this.logOutputLevelIndex])
            .font({ size: 14 })
            .selectedOptionFont({ size: 14 })
            .optionFont({ size: 14 })
            .onSelect(async (index: number) => {
              this.logOutputLevelIndex = index;
              // 保存到设置
              await this.settingsManager.setNumber(SettingKeys.LOG_OUTPUT_LEVEL, index);
              this.settingsManager.syncToAppStorage();
              // 立即应用到logger
              logger.initializeHilogLevelFromIndex(index);
              promptAction.showToast({
                message: `日志等级已设置为: ${LOG_LEVEL_NAMES[index]}`,
                duration: 2000
              });
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
   * 构建开发者工具区域
   */
  @Builder
  buildDeveloperTools() {
    Column({ space: 16 }) {
      Text('开发者工具')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Column({ space: 0 }) {
        // 生命周期监控
        this.buildToolItem('生命周期监控', '查看页面生命周期状态', $r('sys.symbol.timer'), 'LifecycleMonitorPage')
        
        Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)).margin({ left: 52 })
        
        // 日志管理
        this.buildToolItem('日志管理', '查看和导出应用日志', $r('sys.symbol.doc_plaintext'), 'LogManagerPage')
        
        Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)).margin({ left: 52 })
        
        // 系统资源预览
        this.buildToolItem('系统资源预览', '预览系统图标和资源', $r('sys.symbol.paintpalette'), 'SystemResourcePreviewPage')
      }
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(12)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  /**
   * 构建工具项
   */
  @Builder
  buildToolItem(title: string, subtitle: string, icon: Resource, targetPage: string) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(subtitle)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.pathStack.pushPathByName(targetPage, null);
    })
  }

  /**
   * 构建其他操作区域
   */
  @Builder
  buildOtherActions() {
    Column({ space: 16 }) {
      Text('其他操作')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 重播引导页面按钮
      Button({ stateEffect: true }) {
        Text('重播引导页面')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
        .width('100%')
        .height(44)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .borderRadius(12)
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.ignoreNextOtherActionsSecretTap = true;
            setTimeout(() => {
              this.ignoreNextOtherActionsSecretTap = false;
            }, 200);
          }
        })
        .onClick(() => {
          this.ignoreNextOtherActionsSecretTap = true;
          setTimeout(() => {
            this.ignoreNextOtherActionsSecretTap = false;
          }, 0);
          this.resetGuideAndRestart();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
    .onClick(() => {
      void this.handleOtherActionsSecretTap();
    })
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
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('设置已更改，需要重启应用才能生效。')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .textAlign(TextAlign.Center)

        Row({ space: 12 }) {
          Button('稍后重启')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
            .layoutWeight(1)
            .onClick(() => {
              this.showRestartDialog = false;
            })

          Button('立即重启')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
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
   */
  private async resetGuideAndRestart(): Promise<void> {
    try {
      await this.welcomeGuideManager.resetGuide();
      await this.appGuideManager.resetAllGuideStates();
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

      await context.startAbility(want);
      await context.terminateSelf();
      logger.info(TAG, '已重置引导并请求重启应用');
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '重播引导并重启应用失败', msg);
    }
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
                  this.buildDebugSettings()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_debug'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_debug') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'advanced_debug'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_debug', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_debug', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_debug',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildDeveloperTools()
                }
                .width('48%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_tools'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_tools') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'advanced_tools'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_tools', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_tools', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_tools',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
                
                Column({ space: 16 }) {
                  this.buildOtherActions()
                }
                .width('100%')
                .padding(4)
                .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_actions'
                ))
                .borderRadius(16)
                .border({
                  width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_actions') ? 1 : 0,
                  color: SettingsSearchSupport.getHighlightOverlayBorder(
                    this.themeState.currentTheme,
                    this.activeSearchAnchorId,
                    'advanced_actions'
                  )
                })
                .scale({
                  x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_actions', this.searchHighlightPulse),
                  y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_actions', this.searchHighlightPulse)
                })
                .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_actions',
                  this.searchHighlightPulse
                ))
                .animation({ duration: 260, curve: Curve.EaseOut })
                .margin({ bottom: 16 })
              }
              .width('100%')
            } else {
              Column() {
                this.buildDebugSettings()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_debug'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_debug') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_debug'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_debug', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_debug', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_debug',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })

              Column() {
                this.buildDeveloperTools()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_tools'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_tools') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_tools'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_tools', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_tools', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_tools',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })

              Column() {
                this.buildOtherActions()
              }
              .width('100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_actions'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'advanced_actions') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'advanced_actions'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_actions', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'advanced_actions', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'advanced_actions',
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
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 重启提示对话框
        if (this.showRestartDialog) {
          this.buildRestartDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '高级设置',
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
