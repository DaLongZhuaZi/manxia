/**
 * 代理配置对话框（图源网络代理）
 * 统一用于 MainMenuPage / SourceManagementPage
 */

import { promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeType } from '../../Framework/Managers/ThemeManager';
import { ProxyConfig, DEFAULT_PROXY_CONFIG, ProxyManager, ProxyProtocol } from '../../Framework/Network/ProxyManager';
import { SettingsPageSurfaceManager } from '../../pages/settings/SettingsPageSurfaceManager';

const TAG = 'ProxyConfigDialog';

type ProxyDialogTab = 'settings' | 'sources' | 'test';

interface ProxyTestSite {
  name: string;
  url: string;
  icon: string;
  status: 'idle' | 'testing' | 'success' | 'failed';
  responseTime?: number;
  error?: string;
}

const DEFAULT_PROXY_TEST_SITES: ProxyTestSite[] = [
  { name: 'Google', url: 'https://www.google.com', icon: '🔍', status: 'idle' },
  { name: 'GitHub', url: 'https://github.com', icon: '🐈', status: 'idle' },
  { name: 'Pixiv', url: 'https://www.pixiv.net', icon: '🎨', status: 'idle' },
  { name: 'Twitter', url: 'https://twitter.com', icon: '🐦', status: 'idle' },
  { name: 'YouTube', url: 'https://www.youtube.com', icon: '📺', status: 'idle' },
  { name: 'Telegram', url: 'https://telegram.org', icon: '✈️', status: 'idle' }
];

export interface ProxySourceItem {
  id: number;
  name: string;
  baseUrl: string;
  iconPath?: string;
  requireProxy?: boolean;
}

@ComponentV2
export struct ProxyConfigDialog {
  @Param @Require currentTheme: ThemeType;
  @Param @Require appFontFamily: string;
  @Param @Require initialConfig: ProxyConfig;
  @Param @Require sourceList: ProxySourceItem[];
  @Param @Require onSourceProxyChange: (sourceId: number, requireProxy: boolean) => Promise<void>;
  @Param @Require onSave: (config: ProxyConfig) => void;
  @Param @Require onCancel: () => void;

  @Local config: ProxyConfig = DEFAULT_PROXY_CONFIG;
  @Local currentTab: ProxyDialogTab = 'settings';
  @Local sourceItems: ProxySourceItem[] = [];
  @Local customTestUrl: string = '';
  @Local customTestResult: string = '';
  @Local isTestingProxy: boolean = false;
  @Local proxyTestSites: ProxyTestSite[] = [];

  private proxyManager: ProxyManager = ProxyManager.getInstance();
  private readonly tabOrder: ProxyDialogTab[] = ['settings', 'sources', 'test'];
  private swipeStartX: number = 0;
  private swipeOffsetX: number = 0;

  aboutToAppear(): void {
    this.config = this.copyProxyConfig(this.initialConfig);
    this.copySourceItems();
    this.proxyTestSites = this.buildDefaultProxyTestSites();
    this.currentTab = 'settings';
    this.customTestUrl = '';
    this.customTestResult = '';
    this.isTestingProxy = false;
    void this.proxyManager.initialize();
  }

  private copyProxyConfig(source: ProxyConfig): ProxyConfig {
    const copied: ProxyConfig = {
      enabled: source.enabled,
      protocol: source.protocol,
      sharedAuthEnabled: source.sharedAuthEnabled,
      sharedUsername: source.sharedUsername,
      sharedPassword: source.sharedPassword,
      httpEnabled: source.httpEnabled,
      httpHost: source.httpHost,
      httpPort: source.httpPort,
      httpAuthEnabled: source.httpAuthEnabled,
      httpUsername: source.httpUsername,
      httpPassword: source.httpPassword,
      httpsEnabled: source.httpsEnabled,
      httpsHost: source.httpsHost,
      httpsPort: source.httpsPort,
      httpsAuthEnabled: source.httpsAuthEnabled,
      httpsUsername: source.httpsUsername,
      httpsPassword: source.httpsPassword,
      socks5Host: source.socks5Host,
      socks5Port: source.socks5Port,
      socks5AuthEnabled: source.socks5AuthEnabled,
      socks5Username: source.socks5Username,
      socks5Password: source.socks5Password
    };
    return copied;
  }

  private updateConfig(next: ProxyConfig): void {
    this.config = this.copyProxyConfig(next);
  }

  private updateEnabled(enabled: boolean): void {
    const next = this.copyProxyConfig(this.config);
    next.enabled = enabled;
    this.updateConfig(next);
  }

  private updateProtocol(protocol: ProxyProtocol): void {
    const next = this.copyProxyConfig(this.config);
    next.protocol = protocol;
    this.updateConfig(next);
  }

  private updateHttpEnabled(enabled: boolean): void {
    const next = this.copyProxyConfig(this.config);
    next.httpEnabled = enabled;
    this.updateConfig(next);
  }

  private updateHttpHost(host: string): void {
    const next = this.copyProxyConfig(this.config);
    next.httpHost = host;
    this.updateConfig(next);
  }

  private updateHttpPort(value: string): void {
    const port = parseInt(value);
    if (!isNaN(port) && port > 0 && port <= 65535) {
      const next = this.copyProxyConfig(this.config);
      next.httpPort = port;
      this.updateConfig(next);
    }
  }

  private updateHttpsEnabled(enabled: boolean): void {
    const next = this.copyProxyConfig(this.config);
    next.httpsEnabled = enabled;
    this.updateConfig(next);
  }

  private updateHttpsHost(host: string): void {
    const next = this.copyProxyConfig(this.config);
    next.httpsHost = host;
    this.updateConfig(next);
  }

  private updateHttpsPort(value: string): void {
    const port = parseInt(value);
    if (!isNaN(port) && port > 0 && port <= 65535) {
      const next = this.copyProxyConfig(this.config);
      next.httpsPort = port;
      this.updateConfig(next);
    }
  }

  private updateSocks5Host(host: string): void {
    const next = this.copyProxyConfig(this.config);
    next.socks5Host = host;
    this.updateConfig(next);
  }

  private updateSocks5Port(value: string): void {
    const port = parseInt(value);
    if (!isNaN(port) && port > 0 && port <= 65535) {
      const next = this.copyProxyConfig(this.config);
      next.socks5Port = port;
      this.updateConfig(next);
    }
  }

  private updateSharedAuthEnabled(enabled: boolean): void {
    const next = this.copyProxyConfig(this.config);
    next.sharedAuthEnabled = enabled;
    next.httpAuthEnabled = enabled;
    next.httpsAuthEnabled = enabled;
    next.socks5AuthEnabled = enabled;
    this.updateConfig(next);
  }

  private updateSharedUsername(username: string): void {
    const next = this.copyProxyConfig(this.config);
    next.sharedUsername = username;
    next.httpUsername = username;
    next.httpsUsername = username;
    next.socks5Username = username;
    this.updateConfig(next);
  }

  private updateSharedPassword(password: string): void {
    const next = this.copyProxyConfig(this.config);
    next.sharedPassword = password;
    next.httpPassword = password;
    next.httpsPassword = password;
    next.socks5Password = password;
    this.updateConfig(next);
  }

  private copySourceItems(): void {
    const items: ProxySourceItem[] = [];
    for (let i = 0; i < this.sourceList.length; i++) {
      const source = this.sourceList[i];
      const copied: ProxySourceItem = {
        id: source.id,
        name: source.name,
        baseUrl: source.baseUrl,
        iconPath: source.iconPath,
        requireProxy: source.requireProxy === true
      };
      items.push(copied);
    }
    this.sourceItems = items;
  }

  private buildDefaultProxyTestSites(): ProxyTestSite[] {
    const sites: ProxyTestSite[] = [];
    for (let i = 0; i < DEFAULT_PROXY_TEST_SITES.length; i++) {
      const site = DEFAULT_PROXY_TEST_SITES[i];
      const copied: ProxyTestSite = {
        name: site.name,
        url: site.url,
        icon: site.icon,
        status: 'idle'
      };
      sites.push(copied);
    }
    return sites;
  }

  private getTabTitle(tab: ProxyDialogTab): string {
    if (tab === 'settings') {
      return '代理设置';
    }
    if (tab === 'sources') {
      return '图源列表';
    }
    return '连接测试';
  }

  private getTabIcon(tab: ProxyDialogTab): Resource {
    if (tab === 'settings') {
      return $r('sys.symbol.slider_vertical_3');
    }
    if (tab === 'sources') {
      return $r('sys.symbol.picture');
    }
    return $r('sys.symbol.wifi');
  }

  private isTabActive(tab: ProxyDialogTab): boolean {
    return this.currentTab === tab;
  }

  private getDialogCardBackground(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.backgroundColor;
  }

  private getDialogCardBlurStyle(): BlurStyle | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.blurStyle;
  }

  private getDialogCardBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.blurOptions;
  }

  private getDialogCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.backgroundEffect;
  }

  private getDialogCardBorderColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.borderColor;
  }

  private getDialogCardBorderWidth(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.borderWidth;
  }

  private getDialogCardShadowColor(): string {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.shadowColor;
  }

  private getDialogCardRadius(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.currentTheme).surface.radius;
  }

  private activateTab(tab: ProxyDialogTab): void {
    this.currentTab = tab;
  }

  private switchToNextTab(): void {
    const currentIndex: number = this.tabOrder.indexOf(this.currentTab);
    const nextIndex: number = (currentIndex + 1) % this.tabOrder.length;
    this.currentTab = this.tabOrder[nextIndex];
  }

  private switchToPrevTab(): void {
    const currentIndex: number = this.tabOrder.indexOf(this.currentTab);
    const prevIndex: number = (currentIndex - 1 + this.tabOrder.length) % this.tabOrder.length;
    this.currentTab = this.tabOrder[prevIndex];
  }

  private handleTabSwipeStart(event: GestureEvent): void {
    this.swipeStartX = event.offsetX;
    this.swipeOffsetX = 0;
  }

  private handleTabSwipeUpdate(event: GestureEvent): void {
    this.swipeOffsetX = event.offsetX - this.swipeStartX;
  }

  private handleTabSwipeEnd(): void {
    const swipeThreshold: number = 80;
    if (this.swipeOffsetX < -swipeThreshold) {
      this.switchToNextTab();
    } else if (this.swipeOffsetX > swipeThreshold) {
      this.switchToPrevTab();
    }
    this.swipeOffsetX = 0;
  }

  private getEnabledProxySourceCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.sourceItems.length; i++) {
      if (this.sourceItems[i].requireProxy === true) {
        count += 1;
      }
    }
    return count;
  }

  private updateLocalSourceProxy(sourceId: number, requireProxy: boolean): void {
    const updated: ProxySourceItem[] = [];
    for (let i = 0; i < this.sourceItems.length; i++) {
      const item = this.sourceItems[i];
      if (item.id === sourceId) {
        const changed: ProxySourceItem = {
          id: item.id,
          name: item.name,
          baseUrl: item.baseUrl,
          iconPath: item.iconPath,
          requireProxy: requireProxy
        };
        updated.push(changed);
      } else {
        updated.push(item);
      }
    }
    this.sourceItems = updated;
  }

  private async handleSourceProxyToggle(sourceId: number, requireProxy: boolean): Promise<void> {
    try {
      await this.onSourceProxyChange(sourceId, requireProxy);
      this.updateLocalSourceProxy(sourceId, requireProxy);
    } catch (error) {
      logger.error(TAG, `更新图源代理开关失败: sourceId=${sourceId}, error=${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '更新图源代理失败，请重试',
        duration: 1500
      });
    }
  }

  private updateProxyTestSiteStatus(
    index: number,
    status: 'idle' | 'testing' | 'success' | 'failed',
    responseTime?: number,
    error?: string
  ): void {
    const sites: ProxyTestSite[] = [];
    for (let i = 0; i < this.proxyTestSites.length; i++) {
      const oldSite = this.proxyTestSites[i];
      if (i === index) {
        const nextSite: ProxyTestSite = {
          name: oldSite.name,
          url: oldSite.url,
          icon: oldSite.icon,
          status: status,
          responseTime: responseTime,
          error: error
        };
        sites.push(nextSite);
      } else {
        sites.push(oldSite);
      }
    }
    this.proxyTestSites = sites;
  }

  private async testSingleUrl(url: string, index: number): Promise<void> {
    if (index >= 0) {
      this.updateProxyTestSiteStatus(index, 'testing');
    } else {
      this.customTestResult = '正在测试...';
    }

    this.isTestingProxy = true;
    try {
      await this.proxyManager.saveConfig(this.config);
      const startTime: number = Date.now();
      const result = await this.proxyManager.testSingleUrl(url);
      const responseTime: number = Date.now() - startTime;

      if (index >= 0) {
        if (result.success) {
          this.updateProxyTestSiteStatus(index, 'success', responseTime, undefined);
        } else {
          this.updateProxyTestSiteStatus(index, 'failed', undefined, result.error);
        }
      } else {
        if (result.success) {
          this.customTestResult = `✓ 连接成功 (${responseTime}ms)`;
        } else {
          this.customTestResult = `✗ 连接失败: ${result.error || '未知错误'}`;
        }
      }
    } catch (error) {
      if (index >= 0) {
        this.updateProxyTestSiteStatus(index, 'failed', undefined, String(error));
      } else {
        this.customTestResult = `✗ 测试失败: ${String(error)}`;
      }
    }
    this.isTestingProxy = false;
  }

  @Builder
  private buildCapsuleTabButton(tab: ProxyDialogTab) {
    Row({ space: 4 }) {
      SymbolGlyph(this.getTabIcon(tab))
        .fontSize(12)
        .fontColor([this.isTabActive(tab)
          ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme)])
      Text(this.getTabTitle(tab))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.isTabActive(tab) ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.isTabActive(tab)
          ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.isTabActive(tab)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme)
      : Color.Transparent)
    .borderRadius(999)
    .onClick(() => {
      this.activateTab(tab);
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private buildCapsuleTabBar() {
    Row({ space: 6 }) {
      ForEach(this.tabOrder, (tab: ProxyDialogTab) => {
        this.buildCapsuleTabButton(tab)
      })
    }
    .width('100%')
    .padding(4)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
    })
    .borderRadius(999)
    .clip(true)
  }

  @Builder
  private buildSharedAuthSection() {
    Column({ space: 8 }) {
      Row() {
        Toggle({ type: ToggleType.Checkbox, isOn: this.config.sharedAuthEnabled })
          .onChange((isOn: boolean) => {
            this.updateSharedAuthEnabled(isOn);
          })

        Text('需要账号密码')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ left: 8 })
      }
      .width('100%')

      if (this.config.sharedAuthEnabled) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '用户名', text: this.config.sharedUsername })
            .layoutWeight(1)
            .height(40)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .onChange((value: string) => {
              this.updateSharedUsername(value);
            })

          TextInput({ placeholder: '密码', text: this.config.sharedPassword })
            .layoutWeight(1)
            .height(40)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .type(InputType.Password)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .onChange((value: string) => {
              this.updateSharedPassword(value);
            })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private buildSettingsTab() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text('代理类型')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          Button('HTTP/HTTPS')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.config.protocol === ProxyProtocol.HTTP
              ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .backgroundColor(this.config.protocol === ProxyProtocol.HTTP
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.updateProtocol(ProxyProtocol.HTTP);
            })

          Button('SOCKS5')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.config.protocol === ProxyProtocol.SOCKS5
              ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .backgroundColor(this.config.protocol === ProxyProtocol.SOCKS5
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.updateProtocol(ProxyProtocol.SOCKS5);
            })
        }
        .width('100%')
      }
      .width('100%')

      if (this.config.protocol === ProxyProtocol.HTTP) {
        Column({ space: 8 }) {
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.config.httpEnabled })
              .onChange((isOn: boolean) => {
                this.updateHttpEnabled(isOn);
              })

            Text('HTTP代理')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '代理地址', text: this.config.httpHost })
              .layoutWeight(2)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateHttpHost(value);
              })
              .enabled(this.config.httpEnabled)

            TextInput({ placeholder: '端口', text: this.config.httpPort.toString() })
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .type(InputType.Number)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateHttpPort(value);
              })
              .enabled(this.config.httpEnabled)
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          Row() {
            Toggle({ type: ToggleType.Checkbox, isOn: this.config.httpsEnabled })
              .onChange((isOn: boolean) => {
                this.updateHttpsEnabled(isOn);
              })

            Text('HTTPS代理')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '代理地址', text: this.config.httpsHost })
              .layoutWeight(2)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateHttpsHost(value);
              })
              .enabled(this.config.httpsEnabled)

            TextInput({ placeholder: '端口', text: this.config.httpsPort.toString() })
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .type(InputType.Number)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateHttpsPort(value);
              })
              .enabled(this.config.httpsEnabled)
          }
          .width('100%')
        }
        .width('100%')
      } else {
        Column({ space: 8 }) {
          Text('SOCKS5代理')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .width('100%')

          Row({ space: 8 }) {
            TextInput({ placeholder: '代理地址', text: this.config.socks5Host })
              .layoutWeight(2)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateSocks5Host(value);
              })

            TextInput({ placeholder: '端口', text: this.config.socks5Port.toString() })
              .layoutWeight(1)
              .height(40)
              .borderRadius(8)
              .fontFamily(this.appFontFamily)
              .type(InputType.Number)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
              .onChange((value: string) => {
                this.updateSocks5Port(value);
              })
          }
          .width('100%')
        }
        .width('100%')
      }

      this.buildSharedAuthSection()

      Text('提示：代理将应用于图源和图源仓库的网络请求')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  private buildSourcesTab() {
    Column({ space: 12 }) {
      Row() {
        Text('图源代理设置')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.getEnabledProxySourceCount()}/${this.sourceItems.length} 个已启用`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
      }
      .width('100%')

      if (this.sourceItems.length > 0) {
        Column({ space: 4 }) {
          ForEach(this.sourceItems, (source: ProxySourceItem) => {
            Row({ space: 8 }) {
              if (source.iconPath) {
                Image(`file://${source.iconPath}`)
                  .width(28)
                  .height(28)
                  .borderRadius(6)
              } else {
                Image($r('app.media.ic_source_normal'))
                  .width(28)
                  .height(28)
                  .borderRadius(6)
              }

              Column({ space: 2 }) {
                Text(source.name)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

                Text(source.baseUrl)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: source.requireProxy === true })
                .onChange((isOn: boolean) => {
                  void this.handleSourceProxyToggle(source.id, isOn);
                })
            }
            .width('100%')
            .padding(10)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
          })
        }
        .width('100%')
      } else {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(40)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme)])

          Text('暂无图源')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
        }
        .width('100%')
        .padding({ top: 36, bottom: 36 })
      }
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  private buildTestTab() {
    Column({ space: 12 }) {
      Text('点击测试网站连接')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.proxyTestSites, (site: ProxyTestSite, index: number) => {
          this.buildProxyTestTile(site, index)
        })
      }
      .width('100%')

      Column({ space: 8 }) {
        Text('自定义测试')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          TextInput({ placeholder: '输入网址，如 https://example.com', text: this.customTestUrl })
            .layoutWeight(1)
            .height(40)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .onChange((value: string) => {
              this.customTestUrl = value;
            })

          Button('测试')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme))
            .fontFamily(this.appFontFamily)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme))
            .borderRadius(8)
            .width(60)
            .height(40)
            .enabled(this.customTestUrl.length > 0 && !this.isTestingProxy)
            .onClick(() => {
              let targetUrl = this.customTestUrl.trim();
              if (targetUrl.length <= 0) {
                return;
              }
              if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://')) {
                targetUrl = `https://${targetUrl}`;
              }
              this.customTestUrl = targetUrl;
              void this.testSingleUrl(targetUrl, -1);
            })
        }
        .width('100%')

        if (this.customTestResult.length > 0) {
          Text(this.customTestResult)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
            .width('100%')
            .padding(10)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
            .borderRadius(8)
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 12 })
  }

  @Builder
  private buildProxyTestTile(site: ProxyTestSite, index: number) {
    Column({ space: 4 }) {
      Text(site.icon)
        .fontSize(24)

      Text(site.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

      if (site.status === 'testing') {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme))
      } else if (site.status === 'success') {
        Text(`${site.responseTime}ms`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.currentTheme))
      } else if (site.status === 'failed') {
        Text('失败')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.currentTheme))
      } else {
        Text('点击测试')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
      }
    }
    .width('30%')
    .aspectRatio(1)
    .padding(8)
    .margin(4)
    .backgroundColor(site.status === 'success'
      ? 'rgba(76, 175, 80, 0.1)'
      : (site.status === 'failed'
        ? 'rgba(244, 67, 54, 0.1)'
        : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme)))
    .borderRadius(12)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (site.status !== 'testing') {
        void this.testSingleUrl(site.url, index);
      }
    })
  }

  build() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.globe_and_keyboard'))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme)])

        Text('网络代理设置')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .margin({ left: 8 })

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.config.enabled })
          .onChange((isOn: boolean) => {
            this.updateEnabled(isOn);
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      this.buildCapsuleTabBar()

      Scroll() {
        Column() {
          if (this.currentTab === 'settings') {
            this.buildSettingsTab()
          } else if (this.currentTab === 'sources') {
            this.buildSourcesTab()
          } else {
            this.buildTestTab()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
          .onActionStart((event: GestureEvent) => {
            this.handleTabSwipeStart(event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.handleTabSwipeUpdate(event);
          })
          .onActionEnd(() => {
            this.handleTabSwipeEnd();
          })
      )

      Row({ space: 16 }) {
        Button('取消')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
          })

        Button('保存')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme))
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.currentTheme))
          .borderRadius(8)
          .layoutWeight(1)
          .onClick(() => {
            this.onSave(this.config);
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('90%')
    .height('70%')
    .constraintSize({ maxWidth: 560, maxHeight: 640 })
    .backgroundColor(this.getDialogCardBackground())
    .backgroundBlurStyle(this.getDialogCardBlurStyle(), this.getDialogCardBlurOptions())
    .backgroundEffect(this.getDialogCardBackgroundEffect())
    .borderRadius(this.getDialogCardRadius())
    .clip(true)
    .border({
      width: this.getDialogCardBorderWidth(),
      color: this.getDialogCardBorderColor()
    })
    .shadow({
      radius: this.getDialogCardRadius() + 4,
      color: this.getDialogCardShadowColor(),
      offsetX: 0,
      offsetY: 8
    })
    .padding(24)
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut }))
    )
  }
}
