import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
﻿import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { http } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { base64Encode } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { getKomgaTracker } from '../../Framework/Tracking/trackers/KomgaTracker';
import { getKomgaSourceExecutor } from '../../Framework/Source/KomgaSourceExecutor';
import { TabContentCacheManager } from '../../Framework/Cache/TabContentCacheManager';
import KomgaCacheManager from '../../Framework/Source/KomgaCacheManager';
import { RemoteLibraryMangaBridge } from '../../Framework/Source/RemoteLibraryMangaBridge';
import {
  KomgaAuthMode,
  KomgaConfig,
  KomgaInstanceConfig,
  KomgaLibraryOption,
  KOMGA_DEFAULT_CHAPTER_TEMPLATE
} from '../../Framework/Source/KomgaModels';
import {
  createDefaultKomgaInstance,
  createEmptyKomgaConfig,
  getKomgaInstanceDisplayName
} from '../../Framework/Source/KomgaConfigStore';

import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { eventBus, GameEvent, RemoteLibraryConfigChangedPayload } from '../../Framework/EventBus';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';

const TAG = 'KomgaSettingsPage';
const PAGE_BOTTOM_SPACER: number = 32;
const KOMGA_TAB_INDEX: number = 7;
const SETTINGS_TAB_INDEX: number = 6;
type KomgaSettingsColorKey =
  'accent_blue' |
  'background_dark' |
  'comp_background_tertiary' |
  'panel_background' |
  'text_muted' |
  'text_primary' |
  'button_text_primary' |
  'button_text_secondary' |
  'border_active' |
  'comp_divider' |
  'color_success' |
  'color_error';

@Component
export struct KomgaSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pageContentOpacity: number = 0;
  @State instances: KomgaInstanceConfig[] = [];
  @State selectedInstanceId: string = '';
  @State useBrowsePageAsEntry: boolean = true;
  @State showKomgaInBottomBar: boolean = false;
  @State displayName: string = '';
  @State serverUrl: string = '';
  @State authMode: KomgaAuthMode = 'NONE';
  @State username: string = '';
  @State password: string = '';
  @State apiKey: string = '';
  @State defaultLibraryIds: string[] = [];
  @State chapterTitleTemplate: string = KOMGA_DEFAULT_CHAPTER_TEMPLATE;
  @State instanceEnabled: boolean = true;
  @State availableLibraries: KomgaLibraryOption[] = [];
  @State isLoading: boolean = false;
  @State isTesting: boolean = false;
  @State isLoadingLibraries: boolean = false;
  @State testResult: string = '';
  @State testSuccess: boolean = false;

  private tracker = getKomgaTracker();
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
  private componentId: string = 'KomgaSettingsPage';
  private testConnectionRequestId: number = 0;
  private libraryLoadRequestId: number = 0;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    void this.loadConfig();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private color(name: KomgaSettingsColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private getChipTextColor(selected: boolean): ResourceColor {
    return selected ? this.color('button_text_primary') : this.color('button_text_secondary');
  }

  private getChipBackgroundColor(selected: boolean): ResourceColor {
    return selected ? this.color('accent_blue') : this.color('comp_background_tertiary');
  }

  private getChipBorderColor(selected: boolean): ResourceColor {
    return selected ? this.color('border_active') : this.color('comp_divider');
  }

  private getActionButtonBackgroundColor(enabled: boolean, primary: boolean): ResourceColor {
    if (!enabled) {
      return this.color('comp_background_tertiary');
    }
    return primary ? this.color('accent_blue') : this.color('comp_background_tertiary');
  }

  private getActionButtonTextColor(enabled: boolean, primary: boolean): ResourceColor {
    if (!enabled) {
      return this.color('text_muted');
    }
    return primary ? this.color('button_text_primary') : this.color('button_text_secondary');
  }

  private canTestCurrentInstance(): boolean {
    return !this.isTesting && this.serverUrl.trim().length > 0;
  }

  private canLoadLibrariesForCurrentInstance(): boolean {
    return !this.isLoadingLibraries && this.serverUrl.trim().length > 0;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
  }

  private notifyKomgaConfigChanged(reason: string): void {
    eventBus.publish(
      GameEvent.REMOTE_LIBRARY_CONFIG_CHANGED,
      new RemoteLibraryConfigChangedPayload('komga', reason)
    );
  }

  private revealPageContent(): void {
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.pageContentOpacity = 1;
    });
  }

  private resolveValidInstanceId(preferredId: string, instances: KomgaInstanceConfig[]): string {
    if (instances.length <= 0) {
      return '';
    }
    return instances.some((item: KomgaInstanceConfig) => item.id === preferredId)
      ? preferredId
      : instances[0].id;
  }

  private getCurrentInstance(): KomgaInstanceConfig | null {
    return this.instances.find(item => item.id === this.selectedInstanceId) || this.instances[0] || null;
  }

  private hydrateDraft(instance: KomgaInstanceConfig | null): void {
    const current = instance || createDefaultKomgaInstance();
    this.displayName = current.displayName;
    this.serverUrl = current.serverUrl;
    this.authMode = current.authMode;
    this.username = current.username;
    this.password = current.password;
    this.apiKey = current.apiKey;
    this.defaultLibraryIds = this.copyStringArray(current.defaultLibraryIds);
    this.chapterTitleTemplate = current.chapterTitleTemplate || KOMGA_DEFAULT_CHAPTER_TEMPLATE;
    this.instanceEnabled = current.enabled !== false;
  }

  private commitDraft(): void {
    const index = this.instances.findIndex(item => item.id === this.selectedInstanceId);
    if (index < 0) {
      return;
    }
    const next = this.copyInstances(this.instances);
    const updatedInstance: KomgaInstanceConfig = {
      id: next[index].id,
      displayName: this.displayName,
      serverUrl: this.serverUrl,
      authMode: this.authMode,
      username: this.username,
      password: this.password,
      apiKey: this.apiKey,
      defaultLibraryIds: this.copyStringArray(this.defaultLibraryIds),
      chapterTitleTemplate: this.chapterTitleTemplate.trim().length > 0 ? this.chapterTitleTemplate : KOMGA_DEFAULT_CHAPTER_TEMPLATE,
      enabled: this.instanceEnabled
    };
    next[index] = updatedInstance;
    this.instances = next;
  }

  private syncDraftToInstances(clearConnectionState: boolean = false, resetLibraries: boolean = false): void {
    this.commitDraft();
    if (clearConnectionState) {
      this.testConnectionRequestId += 1;
      this.isTesting = false;
      this.testResult = '';
      this.testSuccess = false;
    }
    if (resetLibraries) {
      this.libraryLoadRequestId += 1;
      this.isLoadingLibraries = false;
      this.availableLibraries = [];
    }
  }

  private async loadConfig(): Promise<void> {
    await this.tracker.initialize(true);
    const config: KomgaConfig = this.tracker.getConfig();
    const nextInstances: KomgaInstanceConfig[] = config.instances.length > 0
      ? this.copyInstances(config.instances)
      : [createDefaultKomgaInstance()];
    this.instances = nextInstances;
    this.selectedInstanceId = this.resolveValidInstanceId(config.currentInstanceId, nextInstances);
    this.useBrowsePageAsEntry = config.useBrowsePageAsEntry;
    this.hydrateDraft(this.getCurrentInstance());
    this.testResult = '';
    this.availableLibraries = [];
    await this.loadBottomBarVisibility();
    if (this.serverUrl.trim().length > 0) {
      void this.loadLibraries(false);
    }
  }

  private selectInstance(instanceId: string): void {
    this.commitDraft();
    this.selectedInstanceId = this.resolveValidInstanceId(instanceId, this.instances);
    this.hydrateDraft(this.getCurrentInstance());
    this.testConnectionRequestId += 1;
    this.libraryLoadRequestId += 1;
    this.isTesting = false;
    this.isLoadingLibraries = false;
    this.availableLibraries = [];
    this.testResult = '';
    this.testSuccess = false;
    if (this.serverUrl.trim().length > 0) {
      void this.loadLibraries(false);
    }
  }

  private addInstance(): void {
    this.commitDraft();
    const instance = createDefaultKomgaInstance();
    this.instances = this.instances.concat([instance]);
    this.selectedInstanceId = instance.id;
    this.hydrateDraft(instance);
    this.testConnectionRequestId += 1;
    this.libraryLoadRequestId += 1;
    this.isTesting = false;
    this.isLoadingLibraries = false;
    this.availableLibraries = [];
    this.testResult = '';
    this.testSuccess = false;
  }

  private async removeCurrentInstance(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    const removedInstanceId = this.selectedInstanceId;
    this.isLoading = true;
    if (this.instances.length <= 1) {
      try {
        const success = await this.tracker.saveConfig(createEmptyKomgaConfig());
        if (!success) {
          this.toast('删除实例失败');
          return;
        }
        await this.clearKomgaRuntimeAndCaches(true, removedInstanceId);
        await getKomgaSourceExecutor().initialize(true);
        await this.loadConfig();
        this.notifyKomgaConfigChanged('instance_removed');
        this.toast('Komga 实例已删除');
      } finally {
        this.isLoading = false;
      }
      return;
    }
    const nextInstances = this.instances.filter((item: KomgaInstanceConfig) => item.id !== removedInstanceId);
    this.instances = this.copyInstances(nextInstances);
    this.selectedInstanceId = this.instances[0].id;
    this.hydrateDraft(this.instances[0]);
    this.testConnectionRequestId += 1;
    this.libraryLoadRequestId += 1;
    this.isTesting = false;
    this.isLoadingLibraries = false;
    this.availableLibraries = [];
    this.testResult = '';
    this.testSuccess = false;

    try {
      const success = await this.tracker.saveConfig(this.buildConfigForSave());
      if (!success) {
        this.toast('删除实例失败');
        await this.loadConfig();
        return;
      }
      await this.clearKomgaRuntimeAndCaches(false, removedInstanceId);
      await getKomgaSourceExecutor().initialize(true);
      this.notifyKomgaConfigChanged('instance_removed');
      this.toast('Komga 实例已删除');
    } finally {
      this.isLoading = false;
    }
  }

  private buildDraftInstance(): KomgaInstanceConfig {
    const current = this.getCurrentInstance();
    const fallback = createDefaultKomgaInstance();
    return {
      id: current?.id || fallback.id,
      displayName: this.displayName,
      serverUrl: this.serverUrl,
      authMode: this.authMode,
      username: this.username,
      password: this.password,
      apiKey: this.apiKey,
      defaultLibraryIds: this.copyStringArray(this.defaultLibraryIds),
      chapterTitleTemplate: this.chapterTitleTemplate.trim().length > 0 ? this.chapterTitleTemplate : KOMGA_DEFAULT_CHAPTER_TEMPLATE,
      enabled: this.instanceEnabled
    };
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

  private buildHeaders(instance: KomgaInstanceConfig): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'User-Agent': 'ManXiaKomga/1.0'
    };
    if (instance.authMode === 'API_KEY' && instance.apiKey.trim().length > 0) {
      headers['X-API-Key'] = instance.apiKey.trim();
    } else if (instance.authMode === 'BASIC' && instance.username.trim().length > 0) {
      headers['Authorization'] = `Basic ${base64Encode(`${instance.username}:${instance.password}`)}`;
    }
    return headers;
  }

  private async testConnection(): Promise<void> {
    if (this.isTesting || this.isLoading) {
      return;
    }
    const instance = this.buildDraftInstance();
    if (instance.serverUrl.trim().length <= 0) {
      this.testResult = '请先填写服务器地址';
      this.testSuccess = false;
      return;
    }

    const requestId = this.testConnectionRequestId + 1;
    this.testConnectionRequestId = requestId;
    const requestInstanceId = instance.id;
    this.isTesting = true;
    this.testResult = '';
    const request = http.createHttp();
    try {
      const response = await request.request(`${this.normalizeServerUrl(instance.serverUrl)}/api/v1/libraries`, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(instance),
        connectTimeout: 20000,
        readTimeout: 20000
      });
      if (requestId === this.testConnectionRequestId && requestInstanceId === this.selectedInstanceId) {
        this.testSuccess = response.responseCode >= 200 && response.responseCode < 300;
        if (this.testSuccess) {
          const resultText = response.result as string;
          this.availableLibraries = SafeUtils.parseArr(resultText) as KomgaLibraryOption[];
          this.testResult = '连接成功，正在保存配置...';
          this.commitDraft();
          const config = this.buildConfigForSave();
          const saved = await this.tracker.saveConfig(config);
          if (saved) {
            await getKomgaSourceExecutor().initialize(true);
            this.notifyKomgaConfigChanged('test_connection_saved');
            this.testResult = '连接成功，配置已保存';
            this.toast('Komga 连接已保存');
          } else {
            this.testSuccess = false;
            this.testResult = '连接成功，但保存配置失败';
          }
        } else {
          this.testResult = `连接失败，响应码：${response.responseCode}`;
        }
      }
    } catch (error) {
      logger.error(TAG, `测试 Komga 连接失败: ${String(error)}`);
      if (requestId === this.testConnectionRequestId && requestInstanceId === this.selectedInstanceId) {
        this.testSuccess = false;
        this.testResult = `连接失败：${String(error)}`;
      }
    } finally {
      if (requestId === this.testConnectionRequestId) {
        this.isTesting = false;
      }
      request.destroy();
    }
  }

  private async loadLibraries(showToast: boolean): Promise<void> {
    const instance = this.buildDraftInstance();
    if (instance.serverUrl.trim().length <= 0) {
      if (showToast) {
        this.toast('请先填写服务器地址');
      }
      return;
    }

    const requestId = this.libraryLoadRequestId + 1;
    this.libraryLoadRequestId = requestId;
    const requestInstanceId = instance.id;
    this.isLoadingLibraries = true;
    const request = http.createHttp();
    try {
      const response = await request.request(`${this.normalizeServerUrl(instance.serverUrl)}/api/v1/libraries`, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(instance),
        connectTimeout: 20000,
        readTimeout: 20000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`响应码 ${response.responseCode}`);
      }
      const resultText = response.result as string;
      const libraries = SafeUtils.parseArr(resultText) as KomgaLibraryOption[];
      if (requestId === this.libraryLoadRequestId && requestInstanceId === this.selectedInstanceId) {
        this.availableLibraries = libraries;
        if (showToast) {
          this.toast(`已加载 ${this.availableLibraries.length} 个库`);
        }
      }
    } catch (error) {
      logger.error(TAG, `加载 Komga 库列表失败: ${String(error)}`);
      if (requestId === this.libraryLoadRequestId && requestInstanceId === this.selectedInstanceId) {
        this.availableLibraries = [];
        if (showToast) {
          this.toast(`加载库列表失败：${String(error)}`);
        }
      }
    } finally {
      if (requestId === this.libraryLoadRequestId) {
        this.isLoadingLibraries = false;
      }
      request.destroy();
    }
  }

  private toggleLibrary(libraryId: string): void {
    this.defaultLibraryIds = this.defaultLibraryIds.includes(libraryId)
      ? this.defaultLibraryIds.filter((item: string) => item !== libraryId)
      : this.defaultLibraryIds.concat([libraryId]);
    this.syncDraftToInstances();
  }

  private async saveConfig(openBrowseAfterSave: boolean = false): Promise<void> {
    this.isLoading = true;
    this.commitDraft();
    const config = this.buildConfigForSave();

    const success = await this.tracker.saveConfig(config);
    this.isLoading = false;
    if (!success) {
      this.toast('保存失败');
      return;
    }

    await getKomgaSourceExecutor().initialize(true);
    this.notifyKomgaConfigChanged('settings_saved');
    this.toast('Komga 配置已保存');
    if (openBrowseAfterSave) {
      this.pathStack.pushPathByName('KomgaBrowsePage', null);
    }
  }

  private async clearConfig(): Promise<void> {
    this.isLoading = true;
    const success = await this.tracker.saveConfig(createEmptyKomgaConfig());
    this.isLoading = false;
    if (!success) {
      this.toast('清除配置失败');
      return;
    }
    await this.clearKomgaRuntimeAndCaches(true);
    await getKomgaSourceExecutor().initialize(true);
    await this.loadConfig();
    this.notifyKomgaConfigChanged('settings_cleared');
    this.toast('Komga 配置已清除');
  }

  private async clearKomgaRuntimeAndCaches(clearAll: boolean, instanceId?: string): Promise<void> {
    try {
      const executor = getKomgaSourceExecutor();
      const normalizedInstanceId = instanceId !== undefined ? String(instanceId || '').trim() : '';
      if (clearAll || normalizedInstanceId.length <= 0) {
        executor.clearDataCache();
        await executor.clearPersistentDetailCache();
        await RemoteLibraryMangaBridge.getInstance().clearProviderCache('komga');
      } else {
        executor.clearDataCache(normalizedInstanceId);
        await executor.clearPersistentDetailCache(normalizedInstanceId);
        await RemoteLibraryMangaBridge.getInstance().clearKomgaInstanceCache(normalizedInstanceId);
      }
      KomgaCacheManager.clearAllCache();
      await TabContentCacheManager.getInstance().clearKomgaCache();
      logger.info(TAG, `已清理 Komga 连接状态与相关缓存: clearAll=${clearAll}, instanceId=${normalizedInstanceId || '-'}`);
    } catch (error) {
      logger.warn(TAG, `清理 Komga 缓存失败: ${String(error)}`);
    }
  }

  private copyStringArray(values: string[]): string[] {
    return values.concat();
  }

  private copyInstance(instance: KomgaInstanceConfig): KomgaInstanceConfig {
    const nextInstance: KomgaInstanceConfig = {
      id: instance.id,
      displayName: instance.displayName,
      serverUrl: instance.serverUrl,
      authMode: instance.authMode,
      username: instance.username,
      password: instance.password,
      apiKey: instance.apiKey,
      defaultLibraryIds: this.copyStringArray(instance.defaultLibraryIds),
      chapterTitleTemplate: instance.chapterTitleTemplate,
      enabled: instance.enabled
    };
    return nextInstance;
  }

  private copyInstances(instances: KomgaInstanceConfig[]): KomgaInstanceConfig[] {
    return instances.map((instance: KomgaInstanceConfig) => this.copyInstance(instance));
  }

  private buildConfigForSave(): KomgaConfig {
    const config: KomgaConfig = {
      instances: this.copyInstances(this.instances),
      currentInstanceId: this.resolveValidInstanceId(this.selectedInstanceId, this.instances),
      useBrowsePageAsEntry: this.useBrowsePageAsEntry
    };
    return config;
  }

  private async loadBottomBarVisibility(): Promise<void> {
    try {
      const visibleTabs = await this.settingsManager.getVisibleTabs();
      this.showKomgaInBottomBar = visibleTabs.includes(KOMGA_TAB_INDEX);
    } catch (error) {
      logger.error(TAG, '加载 Komga 底栏入口设置失败', String(error));
      this.showKomgaInBottomBar = false;
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
    const previousValue = this.showKomgaInBottomBar;
    this.showKomgaInBottomBar = isOn;
    try {
      const currentTabs = await this.settingsManager.getVisibleTabs();
      const nextTabs = this.buildVisibleTabsWithTarget(currentTabs, KOMGA_TAB_INDEX, isOn);
      await this.settingsManager.setVisibleTabs(nextTabs);
      AppStorage.setOrCreate('visible_tabs', nextTabs);
      logger.info(TAG, `Komga 底栏入口已${isOn ? '显示' : '隐藏'}: ${JSON.stringify(nextTabs)}`);
      this.showRestartRequiredDialog();
    } catch (error) {
      this.showKomgaInBottomBar = previousValue;
      logger.error(TAG, '保存 Komga 底栏入口设置失败', String(error));
      this.toast('保存底栏入口设置失败');
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

  @Builder
  private buildChip(label: string, selected: boolean, action: () => void) {
    Button(label)
      .fontSize(12)
      .fontColor(this.getChipTextColor(selected))
      .fontFamily(this.appFontFamily)
      .constraintSize({ minHeight: 0 })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.getChipBackgroundColor(selected))
      .border({ width: 1, color: this.getChipBorderColor(selected) })
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
      .stateEffect(false)
      .onClick(() => action())
  }

  @Builder
  private buildAuthModeChip(label: string, mode: KomgaAuthMode) {
    Button(label)
      .fontSize(12)
      .fontColor(this.getChipTextColor(this.authMode === mode))
      .fontFamily(this.appFontFamily)
      .constraintSize({ minHeight: 0 })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.getChipBackgroundColor(this.authMode === mode))
      .border({ width: 1, color: this.getChipBorderColor(this.authMode === mode) })
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
      .stateEffect(false)
      .onClick(() => {
        if (this.authMode !== mode) {
          this.authMode = mode;
          this.syncDraftToInstances(true, true);
        }
      })
  }

  build() {
    NavDestination() {
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

          Column({ space: 12 }) {
            Text('实例管理')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .alignSelf(ItemAlign.Start)
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.instances, (instance: KomgaInstanceConfig) => {
                this.buildChip(getKomgaInstanceDisplayName(instance), instance.id === this.selectedInstanceId, () => {
                  this.selectInstance(instance.id);
                })
              }, (instance: KomgaInstanceConfig) => instance.id)
            }
            .width('100%')
            Row({ space: 12 }) {
              Button('新增实例')
                .layoutWeight(1)
                .backgroundColor(this.color('comp_background_tertiary'))
                .fontColor(this.color('button_text_secondary'))
                .fontFamily(this.appFontFamily)
                .onClick(() => this.addInstance())
              Button('删除当前')
                .layoutWeight(1)
                .backgroundColor(this.color('comp_background_tertiary'))
                .fontColor(this.color('button_text_secondary'))
                .fontFamily(this.appFontFamily)
                .onClick(() => { void this.removeCurrentInstance(); })
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

          Column({ space: 12 }) {
            Text('当前实例')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .alignSelf(ItemAlign.Start)

            TextInput({ placeholder: '实例名称（可选）', text: this.displayName })
              .height(44)
              .backgroundColor(this.color('comp_background_tertiary'))
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .onChange((value: string) => {
                this.displayName = value;
                this.syncDraftToInstances();
              })

            TextInput({ placeholder: 'http://192.168.1.100:25600', text: this.serverUrl })
              .height(44)
              .backgroundColor(this.color('comp_background_tertiary'))
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .onChange((value: string) => {
                this.serverUrl = value;
                this.syncDraftToInstances(true, true);
              })

            Text('填写 Komga 根地址即可，例如 http://192.168.1.100:25600；反向代理路径请保留在根地址中。')
              .fontSize(12)
              .fontColor(this.color('text_muted'))
              .fontFamily(this.appFontFamily)
              .width('100%')

            Flex({ wrap: FlexWrap.Wrap }) {
              this.buildAuthModeChip('无需认证', 'NONE')
              this.buildAuthModeChip('Basic Auth', 'BASIC')
              this.buildAuthModeChip('API Key', 'API_KEY')
            }

            Text('Komga 官方支持 Basic Auth 与 X-API-Key。启用认证时建议优先使用 API Key，并确认反向代理不会移除认证请求头。')
              .fontSize(12)
              .fontColor(this.color('text_muted'))
              .fontFamily(this.appFontFamily)
              .width('100%')

            if (this.authMode === 'BASIC') {
              TextInput({ placeholder: '用户名', text: this.username })
                .height(44)
                .backgroundColor(this.color('comp_background_tertiary'))
                .fontColor(this.color('text_primary'))
                .fontFamily(this.appFontFamily)
                .onChange((value: string) => {
                  this.username = value;
                  this.syncDraftToInstances(true, true);
                })

              TextInput({ placeholder: '密码', text: this.password })
                .height(44)
                .backgroundColor(this.color('comp_background_tertiary'))
                .fontColor(this.color('text_primary'))
                .fontFamily(this.appFontFamily)
                .type(InputType.Password)
                .onChange((value: string) => {
                  this.password = value;
                  this.syncDraftToInstances(true, true);
                })
            } else if (this.authMode === 'API_KEY') {
              TextInput({ placeholder: 'X-API-Key', text: this.apiKey })
                .height(44)
                .backgroundColor(this.color('comp_background_tertiary'))
                .fontColor(this.color('text_primary'))
                .fontFamily(this.appFontFamily)
                .onChange((value: string) => {
                  this.apiKey = value;
                  this.syncDraftToInstances(true, true);
                })
            }

            Row() {
              Text('启用该实例')
                .fontSize(14)
                .fontColor(this.color('text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.instanceEnabled })
                .onChange((value: boolean) => {
                  this.instanceEnabled = value;
                  this.syncDraftToInstances();
                })
            }
            .width('100%')

            Row({ space: 12 }) {
              Button(this.isTesting ? '测试中...' : '测试并保存')
                .layoutWeight(1)
                .backgroundColor(this.getActionButtonBackgroundColor(this.canTestCurrentInstance() && !this.isLoading, true))
                .fontColor(this.getActionButtonTextColor(this.canTestCurrentInstance() && !this.isLoading, true))
                .fontFamily(this.appFontFamily)
                .enabled(this.canTestCurrentInstance() && !this.isLoading)
                .onClick(() => {
                  void this.testConnection();
                })
              Button(this.isLoadingLibraries ? '加载中...' : '加载库列表')
                .layoutWeight(1)
                .backgroundColor(this.getActionButtonBackgroundColor(this.canLoadLibrariesForCurrentInstance(), false))
                .fontColor(this.getActionButtonTextColor(this.canLoadLibrariesForCurrentInstance(), false))
                .fontFamily(this.appFontFamily)
                .enabled(this.canLoadLibrariesForCurrentInstance())
                .onClick(() => {
                  void this.loadLibraries(true);
                })
            }
            .width('100%')

            if (this.testResult.length > 0) {
              Text(this.testResult)
                .fontSize(13)
                .fontColor(this.testSuccess ? this.color('color_success') : this.color('color_error'))
                .fontFamily(this.appFontFamily)
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

          Column({ space: 12 }) {
            Text('默认库与阅读行为')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .alignSelf(ItemAlign.Start)

            Row() {
              Column({ space: 4 }) {
                Text('在底栏当中显示 Komga')
                  .fontSize(14)
                  .fontColor(this.color('text_primary'))
                  .fontFamily(this.appFontFamily)

                Text('调整后需要重启APP才能生效')
                  .fontSize(12)
                  .fontColor(this.color('text_muted'))
                  .fontFamily(this.appFontFamily)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.showKomgaInBottomBar })
                .selectedColor(this.color('accent_blue'))
                .switchPointColor(Color.White)
                .onChange((value: boolean) => {
                  void this.saveBottomBarVisibility(value);
                })
            }
            .width('100%')

            if (this.availableLibraries.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.availableLibraries, (library: KomgaLibraryOption) => {
                  this.buildChip(library.name, this.defaultLibraryIds.includes(library.id), () => {
                    this.toggleLibrary(library.id);
                  })
                }, (library: KomgaLibraryOption) => library.id)
              }
              .width('100%')
            } else {
              Text('尚未加载库列表。保存前建议至少加载一次，以便选择默认库。')
                .fontSize(12)
                .fontColor(this.color('text_muted'))
                .fontFamily(this.appFontFamily)
                .width('100%')
            }

            TextInput({ placeholder: '{number} - {title} ({size})', text: this.chapterTitleTemplate })
              .height(44)
              .backgroundColor(this.color('comp_background_tertiary'))
              .fontColor(this.color('text_primary'))
              .fontFamily(this.appFontFamily)
              .onChange((value: string) => {
                this.chapterTitleTemplate = value;
                this.syncDraftToInstances();
              })

            Text('模板占位符：{title} {seriesTitle} {number} {createdDate} {releaseDate} {size} {sizeBytes}')
              .fontSize(12)
              .fontColor(this.color('text_muted'))
              .fontFamily(this.appFontFamily)
              .width('100%')

            Row() {
              Text('主页面点击 Komga 入口时直达浏览页')
                .fontSize(14)
                .fontColor(this.color('text_primary'))
                .fontFamily(this.appFontFamily)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.useBrowsePageAsEntry })
                .selectedColor(this.color('accent_blue'))
                .switchPointColor(Color.White)
                .onChange((value: boolean) => this.useBrowsePageAsEntry = value)
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

          Row({ space: 12 }) {
            Button('清除配置')
              .layoutWeight(1)
              .backgroundColor(this.color('comp_background_tertiary'))
              .fontColor(this.color('button_text_secondary'))
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                void this.clearConfig();
              })
            Button(this.isLoading ? '保存中...' : '保存配置')
              .layoutWeight(1)
              .backgroundColor(this.color('accent_blue'))
              .fontColor(this.color('button_text_primary'))
              .fontFamily(this.appFontFamily)
              .enabled(!this.isLoading)
              .onClick(() => {
                void this.saveConfig(false);
              })
          }
          .width('100%')

          Button('保存并打开浏览页')
            .width('100%')
            .backgroundColor(this.color('accent_blue'))
            .fontColor(this.color('button_text_primary'))
            .fontFamily(this.appFontFamily)
            .enabled(!this.isLoading)
            .onClick(() => {
              void this.saveConfig(true);
            })

          Blank().height(PAGE_BOTTOM_SPACER)
        }
          .width('100%')
          .padding({ left: 16, right: 16, top: 0, bottom: 0 })
          .opacity(this.pageContentOpacity)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: 'Komga 设置',
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 1200,
          pathStack: this.pathStack
        })
      }
      .width('100%')
      .height('100%')
    }
    .title('Komga 设置')
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onShown(() => {
      this.revealPageContent();
    })
    .backgroundColor(Color.Transparent)
  }
}
