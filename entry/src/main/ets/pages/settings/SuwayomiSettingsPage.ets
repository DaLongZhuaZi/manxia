import { UIContext } from '@ohos.arkui.UIContext';
/**
 * Suwayomi 设置页面
 * 配置服务器地址、认证信息，支持图源模式和服务器模式
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import { SafeUtils } from '../../Utils/SafeUtils';
import { base64Encode } from '../../Utils/CryptoUtils';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { FontAwareState } from '../../Framework/Components/FontAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { getSuwayomiTracker, SuwayomiTracker, SuwayomiConfig } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { SettingsManager } from '../../Framework/Managers/SettingsManager';
import { SettingsPanelSurfaceHelper } from './SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';
import { getSuwayomiSourceExecutor } from '../../Framework/Source/SuwayomiSourceExecutor';
import { TabContentCacheManager } from '../../Framework/Cache/TabContentCacheManager';
import SuwayomiCacheManager from '../../Framework/Source/SuwayomiCacheManager';
import { RemoteLibraryMangaBridge } from '../../Framework/Source/RemoteLibraryMangaBridge';
import { eventBus, GameEvent, RemoteLibraryConfigChangedPayload } from '../../Framework/EventBus';

const TAG = 'SuwayomiSettingsPage';
const TITLE_BAR_HEIGHT: number = 56;
const SUWAYOMI_TAB_INDEX: number = 5;
const SETTINGS_TAB_INDEX: number = 6;

// 页面参数接口
interface SuwayomiWebUIParams {
  url?: string;
}

interface SuwayomiTestGraphQLData {
  __typename?: string;
}

interface SuwayomiTestGraphQLError {
  message: string;
}

interface SuwayomiTestGraphQLResponse {
  data?: SuwayomiTestGraphQLData;
  errors?: SuwayomiTestGraphQLError[];
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
  @State showSuwayomiInBottomBar: boolean = false;

  // UI 状态
  @State isLoading: boolean = false;
  @State isTesting: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;
  @State showPassword: boolean = false;

  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();
  private settingsManager: SettingsManager = SettingsManager.getInstance();
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
    await this.loadBottomBarVisibility();
  }

  private async loadBottomBarVisibility(): Promise<void> {
    try {
      const visibleTabs = await this.settingsManager.getVisibleTabs();
      this.showSuwayomiInBottomBar = visibleTabs.includes(SUWAYOMI_TAB_INDEX);
    } catch (error) {
      logger.error(TAG, '加载 Suwayomi 底栏入口设置失败', String(error));
      this.showSuwayomiInBottomBar = false;
    }
  }

  private buildVisibleTabsWithTarget(currentTabs: number[], targetIndex: number, visible: boolean): number[] {
    const nextTabs: number[] = [];
    for (let index = 0; index < currentTabs.length; index++) {
      const tabIndex = currentTabs[index];
      if (tabIndex !== targetIndex && !nextTabs.includes(tabIndex)) {
        nextTabs.push(tabIndex);
      }
    }

    if (!visible) {
      return nextTabs;
    }

    const settingsIndex = nextTabs.indexOf(SETTINGS_TAB_INDEX);
    if (settingsIndex >= 0) {
      nextTabs.splice(settingsIndex, 0, targetIndex);
    } else {
      nextTabs.push(targetIndex);
    }
    return nextTabs;
  }

  private async saveBottomBarVisibility(isOn: boolean): Promise<void> {
    const previousValue = this.showSuwayomiInBottomBar;
    this.showSuwayomiInBottomBar = isOn;
    try {
      const currentTabs = await this.settingsManager.getVisibleTabs();
      const nextTabs = this.buildVisibleTabsWithTarget(currentTabs, SUWAYOMI_TAB_INDEX, isOn);
      await this.settingsManager.setVisibleTabs(nextTabs);
      AppStorage.setOrCreate('visible_tabs', nextTabs);
      logger.info(TAG, `Suwayomi 底栏入口已${isOn ? '显示' : '隐藏'}: ${JSON.stringify(nextTabs)}`);
      this.showRestartRequiredDialog();
    } catch (error) {
      this.showSuwayomiInBottomBar = previousValue;
      logger.error(TAG, '保存 Suwayomi 底栏入口设置失败', String(error));
      this.showToast('保存底栏入口设置失败');
    }
  }

  private showRestartRequiredDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '配置已保存',
      message: '底栏入口设置已保存，需要重启APP才能生效。',
      buttons: [
        { text: '知道了', color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) }
      ]
    });
  }

  private normalizeServerUrl(serverUrl: string): string {
    const raw = serverUrl.trim();
    if (raw.length <= 0) {
      return '';
    }
    const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(raw);
    const withScheme = hasScheme ? raw : `http://${raw}`;
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
  }

  private buildAuthHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (this.useAuth && this.username.trim().length > 0) {
      const credentials = `${this.username}:${this.password}`;
      headers['Authorization'] = `Basic ${base64Encode(credentials)}`;
    }
    return headers;
  }

  private async testConnectionDirectly(): Promise<boolean> {
    const serverUrl = this.normalizeServerUrl(this.serverUrl);
    if (serverUrl.length <= 0) {
      return false;
    }

    const request = http.createHttp();
    try {
      const response = await request.request(`${serverUrl}/api/graphql`, {
        method: http.RequestMethod.POST,
        header: this.buildAuthHeaders(),
        extraData: JSON.stringify({ query: 'query { __typename }' }),
        connectTimeout: 10000,
        readTimeout: 30000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        logger.warn(TAG, `Suwayomi 测试连接失败: responseCode=${response.responseCode}`);
        return false;
      }
      const result = SafeUtils.parseObj(response.result as string) as SuwayomiTestGraphQLResponse;
      if (result.errors && result.errors.length > 0) {
        logger.warn(TAG, `Suwayomi GraphQL 测试失败: ${result.errors[0].message}`);
        return false;
      }
      return result.data !== undefined;
    } catch (error) {
      logger.error(TAG, 'Suwayomi 连接测试异常', String(error));
      return false;
    } finally {
      request.destroy();
    }
  }

  private async testConnection(): Promise<void> {
    if (!this.serverUrl) {
      this.testResult = '请输入服务器地址';
      this.testSuccess = false;
      return;
    }

    this.isTesting = true;
    this.testResult = '';

    const config: SuwayomiConfig = {
      serverUrl: this.serverUrl.trim(),
      username: this.username,
      password: this.password,
      useAuth: this.useAuth,
      useBrowsePageAsEntry: this.useBrowsePageAsEntry
    };

    const success = await this.testConnectionDirectly();

    this.testSuccess = success;
    if (!success) {
      this.testResult = '连接失败，请检查地址和认证信息';
      this.isTesting = false;
      return;
    }

    this.testResult = '连接成功，正在保存配置...';
    const saved = await this.suwayomiTracker.saveConfig(config);
    this.isTesting = false;
    if (saved) {
      await getSuwayomiSourceExecutor().initialize(true);
      this.notifySuwayomiConfigChanged('test_connection_saved');
      this.testResult = '连接成功，配置已保存';
      this.showToast('Suwayomi 连接已保存');
    } else {
      this.testSuccess = false;
      this.testResult = '连接成功，但保存配置失败';
    }
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
      await getSuwayomiSourceExecutor().initialize(true);
      this.notifySuwayomiConfigChanged('settings_saved');
      this.showToast('配置已保存');
      this.pathStack.pop();
    } else {
      this.showToast('保存失败');
    }
  }

  private async clearConfig(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      await this.suwayomiTracker.logout();
      this.serverUrl = '';
      this.username = '';
      this.password = '';
      this.useAuth = false;
      this.useBrowsePageAsEntry = false;
      this.testResult = '';
      this.testSuccess = false;
      await this.clearSuwayomiRuntimeAndCaches();
      await getSuwayomiSourceExecutor().initialize(true);
      this.notifySuwayomiConfigChanged('settings_cleared');
      this.showToast('配置已清除');
    } finally {
      this.isLoading = false;
    }
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

  private notifySuwayomiConfigChanged(reason: string): void {
    eventBus.publish(
      GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED,
      new RemoteLibraryConfigChangedPayload('suwayomi', reason)
    );
  }

  private async clearSuwayomiRuntimeAndCaches(): Promise<void> {
    try {
      getSuwayomiSourceExecutor().clearDataCache();
      SuwayomiCacheManager.clearAllCache();
      await TabContentCacheManager.getInstance().clearSuwayomiCache();
      await RemoteLibraryMangaBridge.getInstance().clearProviderCache('suwayomi');
      logger.info(TAG, '已清理 Suwayomi 连接状态与相关缓存');
    } catch (error) {
      logger.warn(TAG, `清理 Suwayomi 缓存失败: ${String(error)}`);
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

                Text('填写 Suwayomi 根地址即可，例如 http://192.168.1.100:4567；不要追加 /api/graphql。')
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)
                  .width('100%')
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

              Text('这里对应 Suwayomi 的 Basic Auth。simple_login 或 ui_login 需要服务端允许 API 会话，否则请改用 Basic Auth。')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .fontFamily(this.appFontFamily)
                .width('100%')

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

            // 测试并保存按钮
            Button(this.isTesting ? '测试中...' : '测试并保存')
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .fontColor(Color.White)
              .enabled(!this.isTesting && !this.isLoading && !!this.serverUrl)
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
              Text('入口设置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .alignSelf(ItemAlign.Start)
                .fontFamily(this.appFontFamily)

              Row() {
                Column({ space: 4 }) {
                  Text('在底栏当中显示 Suwayomi')
                    .fontSize(14)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .fontFamily(this.appFontFamily)

                  Text('调整后需要重启APP才能生效')
                    .fontSize(12)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .fontFamily(this.appFontFamily)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.showSuwayomiInBottomBar })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    void this.saveBottomBarVisibility(isOn);
                  })
              }
              .width('100%')

              Row() {
                Text('主页面点击 Suwayomi 入口时直达浏览页')
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .fontFamily(this.appFontFamily)

                Blank()

                Toggle({ type: ToggleType.Switch, isOn: this.useBrowsePageAsEntry })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    this.useBrowsePageAsEntry = isOn;
                    void this.saveConfigSilently();
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
            .alignItems(HorizontalAlign.Start)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

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
