import { UIContext } from '@ohos.arkui.UIContext';
/**
 * Suwayomi 设置页面
 * 配置服务器地址、认证信息，支持图源模式和服务器模式
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { FontAwareState } from '../../Framework/Components/FontAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { getSuwayomiTracker, SuwayomiTracker, SuwayomiConfig } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'SuwayomiSettingsPage';
const TITLE_BAR_HEIGHT: number = 56;

// 页面参数接口
interface SuwayomiWebUIParams {
  url?: string;
}

@Component
export struct SuwayomiSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 配置状态
  @State serverUrl: string = '';
  @State username: string = '';
  @State password: string = '';
  @State useAuth: boolean = false;
  @State useBrowsePageAsEntry: boolean = false;

  // UI 状态
  @State isLoading: boolean = false;
  @State isTesting: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;
  @State showPassword: boolean = false;

  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();
  private componentId: string = 'SuwayomiSettingsPage';

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
  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });

    // 加载现有配置
    this.loadConfig();
  }

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  private async loadConfig(): Promise<void> {
    await this.suwayomiTracker.initialize();
    const config = this.suwayomiTracker.getConfig();
    this.serverUrl = config.serverUrl;
    this.username = config.username;
    this.password = config.password;
    this.useAuth = config.useAuth;
    this.useBrowsePageAsEntry = config.useBrowsePageAsEntry ?? false;
  }

  private async testConnection(): Promise<void> {
    if (!this.serverUrl) {
      this.testResult = '请输入服务器地址';
      this.testSuccess = false;
      return;
    }

    this.isTesting = true;
    this.testResult = '';

    // 先保存配置
    const config: SuwayomiConfig = {
      serverUrl: this.serverUrl.trim(),
      username: this.username,
      password: this.password,
      useAuth: this.useAuth,
      useBrowsePageAsEntry: this.useBrowsePageAsEntry
    };
    await this.suwayomiTracker.saveConfig(config);

    // 测试连接
    const success = await this.suwayomiTracker.testConnection();

    this.isTesting = false;
    this.testSuccess = success;
    this.testResult = success ? '连接成功！' : '连接失败，请检查地址和认证信息';
  }

  private async saveConfig(): Promise<void> {
    this.isLoading = true;

    const config: SuwayomiConfig = {
      serverUrl: this.serverUrl.trim(),
      username: this.username,
      password: this.password,
      useAuth: this.useAuth,
      useBrowsePageAsEntry: this.useBrowsePageAsEntry
    };

    const success = await this.suwayomiTracker.saveConfig(config);

    this.isLoading = false;

    if (success) {
      this.showToast('配置已保存');
      this.pathStack.pop();
    } else {
      this.showToast('保存失败');
    }
  }

  private async clearConfig(): Promise<void> {
    await this.suwayomiTracker.logout();
    this.serverUrl = '';
    this.username = '';
    this.password = '';
    this.useAuth = false;
    this.useBrowsePageAsEntry = false;
    this.testResult = '';
    this.showToast('配置已清除');
  }

  private async saveConfigSilently(): Promise<void> {
    const config: SuwayomiConfig = {
      serverUrl: this.serverUrl.trim(),
      username: this.username,
      password: this.password,
      useAuth: this.useAuth,
      useBrowsePageAsEntry: this.useBrowsePageAsEntry
    };
    await this.suwayomiTracker.saveConfig(config);
    logger.info(TAG, `配置已静默保存: useBrowsePageAsEntry=${this.useBrowsePageAsEntry}`);
  }

  private openWebUI(): void {
    if (!this.serverUrl) {
      this.showToast('请先配置服务器地址');
      return;
    }
    // 导航到 WebUI 页面
    const params: SuwayomiWebUIParams = { url: this.serverUrl };
    this.pathStack.pushPathByName('SuwayomiWebUIPage', params);
  }

  private openBrowsePage(): void {
    if (!this.serverUrl) {
      this.showToast('请先配置服务器地址');
      return;
    }
    // 导航到浏览页面
    this.pathStack.pushPathByName('SuwayomiBrowsePage', null);
  }

  private showToast(message: string): void {
    import('@kit.ArkUI').then(arkUI => {
      AppStorage.get<UIContext>('GlobalUIContext')?.getPromptAction()?.showToast({
        message: message,
        duration: 2000
      });
    });
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

        Scroll() {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            // 功能按钮（如果已配置）
            if (this.serverUrl) {
              Row({ space: 12 }) {
                Button('浏览图源')
                  .layoutWeight(1)
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .fontColor(Color.White)
                  .onClick(() => this.openBrowsePage())
                  .fontFamily(this.appFontFamily)

                Button('打开 WebUI')
                  .layoutWeight(1)
                  .height(44)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .onClick(() => this.openWebUI())
                  .fontFamily(this.appFontFamily)
              }
              .width('100%')
            }

            // 服务器配置区域
            Column({ space: 12 }) {
              Text('服务器配置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .alignSelf(ItemAlign.Start)
                .fontFamily(this.appFontFamily)

              // 服务器地址
              Column({ space: 4 }) {
                Text('服务器地址')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .alignSelf(ItemAlign.Start)
                  .fontFamily(this.appFontFamily)

                TextInput({ placeholder: 'http://192.168.1.100:4567', text: this.serverUrl })
                  .width('100%')
                  .height(44)
                  .onChange((value: string) => {
                    this.serverUrl = value;
                    this.testResult = '';
                  })
                  .fontFamily(this.appFontFamily)
              }
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

              // 使用认证开关
              Row() {
                Text('使用认证')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)

                Blank()

                Toggle({ type: ToggleType.Switch, isOn: this.useAuth })
                  .onChange((isOn: boolean) => {
                    this.useAuth = isOn;
                  })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })

              // 认证信息（条件显示）
              if (this.useAuth) {
                Column({ space: 8 }) {
                  // 用户名
                  Column({ space: 4 }) {
                    Text('用户名')
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      .alignSelf(ItemAlign.Start)
                      .fontFamily(this.appFontFamily)

                    TextInput({ placeholder: '用户名', text: this.username })
                      .width('100%')
                      .height(44)
                      .onChange((value: string) => {
                        this.username = value;
                      })
                      .fontFamily(this.appFontFamily)
                  }

                  // 密码
                  Column({ space: 4 }) {
                    Text('密码')
                      .fontSize(14)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      .alignSelf(ItemAlign.Start)
                      .fontFamily(this.appFontFamily)

                    Row() {
                      TextInput({ placeholder: '密码', text: this.password })
                        .width('100%')
                        .height(44)
                        .type(this.showPassword ? InputType.Normal : InputType.Password)
                        .onChange((value: string) => {
                          this.password = value;
                        })
                        .fontFamily(this.appFontFamily)
                    }
                  }
                }
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

            // 测试连接按钮
            Button(this.isTesting ? '测试中...' : '测试连接')
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .fontColor(Color.White)
              .enabled(!this.isTesting && !!this.serverUrl)
              .onClick(() => this.testConnection())
              .fontFamily(this.appFontFamily)

            // 测试结果
            if (this.testResult) {
              Text(this.testResult)
                .fontSize(14)
                .fontColor(this.testSuccess ? '#10B981' : '#FF6B6B')
                .textAlign(TextAlign.Center)
                .fontFamily(this.appFontFamily)
            }

            // 功能说明
            Column({ space: 12 }) {
              Text('功能说明')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .alignSelf(ItemAlign.Start)
                .fontFamily(this.appFontFamily)

              Text('图源模式：将 Suwayomi 作为漫画源使用，可以浏览、搜索和阅读漫画，阅读进度会自动同步。')
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)

              Text('服务器模式：直接访问 Suwayomi WebUI，可以进行完整的服务器管理操作。')
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)
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
            .alignItems(HorizontalAlign.Start)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

            // 操作按钮
            Row({ space: 12 }) {
              Button('清除配置')
                .layoutWeight(1)
                .height(44)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .enabled(!!this.serverUrl)
                .onClick(() => this.clearConfig())
                .fontFamily(this.appFontFamily)

              Button(this.isLoading ? '保存中...' : '保存配置')
                .layoutWeight(1)
                .height(44)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .fontColor(Color.White)
                .enabled(!this.isLoading && !!this.serverUrl)
                .onClick(() => this.saveConfig())
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Blank().height(40)
          }
          .enabled(this.settingsTapEnabled)
          .width('100%')
          .padding(16)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
          title: 'Suwayomi 设置',
          appFontFamily: this.appFontFamily,
          pathStack: this.pathStack
        })
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
