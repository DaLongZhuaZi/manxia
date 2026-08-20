// 文件路径: entry/src/main/ets/pages/settings/ShortcutSettingsSubPage.ets
/**
 * 快捷方式设置子页面
 * - 读取并管理桌面长按应用图标时展示的快捷方式
 * - 支持从预设快捷方式中选择最多 4 个显示
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import shortcutManager from '@ohos.bundle.shortcutManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_core/src/main/ets/Framework/Utils/ResponsiveLayout';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'ShortcutSettingsSubPage';
const SHORTCUT_MAX_VISIBLE_COUNT: number = 4;

interface ShortcutPresetItem {
  id: string;
  title: string;
  description: string;
}

interface ShortcutDisplayItem {
  id: string;
  title: string;
  description: string;
  enabled: boolean;
}

@Component
export struct ShortcutSettingsSubPage {
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
  private componentId: string = 'ShortcutSettingsSubPage';
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 快捷方式设置状态
  @State private shortcutItems: ShortcutDisplayItem[] = [];
  @State private visibleShortcutCount: number = 0;
  @State private isLoading: boolean = true;

  private readonly shortcutPresets: ShortcutPresetItem[] = [
    { id: 'reading_analytics', title: '阅读报告', description: '快速进入阅读报告页面' },
    { id: 'search', title: '全局搜索', description: '快速进入全局搜索页面' },
    { id: 'continue_read', title: '继续阅读', description: '快速继续最近阅读内容' },
    { id: 'continue_read_aloud', title: '继续听书', description: '快速继续最近听书内容' },
    { id: 'inspiration', title: '灵感', description: '快速进入灵感记录页面' }
  ];

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
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {
      logger.info(TAG, '主题切换完成');
    });
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
    void this.loadShortcutSettings();
  }

  private lifecycle = new PageLifecycleManager('ShortcutSettingsSubPage', { enableDebug: true });

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

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('ShortcutSettingsSubPage');
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

  private hasPresetShortcut(shortcutId: string): boolean {
    for (let index = 0; index < this.shortcutPresets.length; index++) {
      if (this.shortcutPresets[index].id === shortcutId) {
        return true;
      }
    }
    return false;
  }

  private buildDefaultVisibleShortcutIds(): string[] {
    const ids: string[] = [];
    const maxCount = Math.min(SHORTCUT_MAX_VISIBLE_COUNT, this.shortcutPresets.length);
    for (let index = 0; index < maxCount; index++) {
      ids.push(this.shortcutPresets[index].id);
    }
    return ids;
  }

  private sanitizeVisibleShortcutIds(rawIds: string[]): string[] {
    const sanitized: string[] = [];
    for (let index = 0; index < rawIds.length; index++) {
      const shortcutId = rawIds[index];
      if (!this.hasPresetShortcut(shortcutId)) {
        continue;
      }
      if (sanitized.includes(shortcutId)) {
        continue;
      }
      sanitized.push(shortcutId);
    }
    return sanitized;
  }

  private getCachedVisibleShortcutIds(): string[] {
    const defaultIds = this.buildDefaultVisibleShortcutIds();
    const cachedIds = this.settingsManager.getJSON<string[]>(SettingKeys.SHORTCUT_VISIBLE_IDS, defaultIds);
    const sanitized = this.sanitizeVisibleShortcutIds(cachedIds);
    if (sanitized.length <= 0) {
      return defaultIds;
    }
    return sanitized;
  }

  private createItemsFromVisibleIds(visibleIds: string[]): ShortcutDisplayItem[] {
    const items: ShortcutDisplayItem[] = [];
    for (let index = 0; index < this.shortcutPresets.length; index++) {
      const preset = this.shortcutPresets[index];
      const enabled = visibleIds.includes(preset.id);
      const item: ShortcutDisplayItem = {
        id: preset.id,
        title: preset.title,
        description: preset.description,
        enabled
      };
      items.push(item);
    }
    return items;
  }

  private findShortcutInfoById(
    infos: shortcutManager.ShortcutInfo[],
    shortcutId: string
  ): shortcutManager.ShortcutInfo | null {
    for (let index = 0; index < infos.length; index++) {
      if (infos[index].id === shortcutId) {
        return infos[index];
      }
    }
    return null;
  }

  private collectVisibleShortcutIdsFromItems(items: ShortcutDisplayItem[]): string[] {
    const visibleIds: string[] = [];
    for (let index = 0; index < items.length; index++) {
      if (items[index].enabled) {
        visibleIds.push(items[index].id);
      }
    }
    return visibleIds;
  }

  private updateVisibleShortcutCount(): void {
    let count = 0;
    for (let index = 0; index < this.shortcutItems.length; index++) {
      if (this.shortcutItems[index].enabled) {
        count++;
      }
    }
    this.visibleShortcutCount = count;
  }

  private async persistVisibleShortcutIds(visibleIds: string[]): Promise<void> {
    // 保存用户实际选择的所有可见快捷方式，不做数量截断
    // 系统层面会自行限制显示数量（前4个），但本地配置应保留完整选择
    await this.settingsManager.setJSON<string[]>(SettingKeys.SHORTCUT_VISIBLE_IDS, visibleIds);
    this.settingsManager.syncToAppStorage();
  }

  private async alignSystemShortcutVisibility(
    systemInfos: shortcutManager.ShortcutInfo[],
    desiredItems: ShortcutDisplayItem[]
  ): Promise<void> {
    for (let index = 0; index < desiredItems.length; index++) {
      const item = desiredItems[index];
      const systemInfo = this.findShortcutInfoById(systemInfos, item.id);
      if (!systemInfo) {
        continue;
      }
      const systemVisible = systemInfo.visible !== false;
      if (systemVisible === item.enabled) {
        continue;
      }
      try {
        await shortcutManager.setShortcutVisibleForSelf(item.id, item.enabled);
      } catch (error) {
        logger.warn(TAG, `同步系统快捷方式可见状态失败: id=${item.id}, enabled=${item.enabled}, error=${String(error)}`);
      }
    }
  }

  private async loadShortcutSettings(): Promise<void> {
    this.isLoading = true;
    const cachedVisibleIds = this.getCachedVisibleShortcutIds();
    let items = this.createItemsFromVisibleIds(cachedVisibleIds);
    let systemInfos: shortcutManager.ShortcutInfo[] = [];
    let hasSystemInfos: boolean = false;

    try {
      systemInfos = await shortcutManager.getAllShortcutInfoForSelf();
      hasSystemInfos = true;
      if (systemInfos.length > 0) {
        const mergedItems: ShortcutDisplayItem[] = [];
        for (let index = 0; index < items.length; index++) {
          const currentItem = items[index];
          const info = this.findShortcutInfoById(systemInfos, currentItem.id);
          const nextItem: ShortcutDisplayItem = {
            id: currentItem.id,
            title: currentItem.title,
            description: currentItem.description,
            enabled: currentItem.enabled
          };
          if (info && info.visible !== nextItem.enabled) {
            logger.info(TAG, `检测到系统快捷方式状态差异: id=${nextItem.id}, systemEnabled=${info.visible !== false}, desiredEnabled=${nextItem.enabled}`);
          }
          mergedItems.push(nextItem);
        }
        items = mergedItems;
      }
    } catch (error) {
      logger.warn(TAG, `读取系统快捷方式状态失败，回退到本地设置: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '读取系统快捷方式状态失败，已使用本地配置',
        duration: 1600
      });
    }

    const normalizedVisibleIds = this.sanitizeVisibleShortcutIds(this.collectVisibleShortcutIdsFromItems(items));
    const normalizedItems: ShortcutDisplayItem[] = [];
    for (let index = 0; index < items.length; index++) {
      const source = items[index];
      const normalizedItem: ShortcutDisplayItem = {
        id: source.id,
        title: source.title,
        description: source.description,
        enabled: normalizedVisibleIds.includes(source.id)
      };
      normalizedItems.push(normalizedItem);
    }

    if (hasSystemInfos) {
      await this.alignSystemShortcutVisibility(systemInfos, normalizedItems);
    }

    this.shortcutItems = normalizedItems;
    this.updateVisibleShortcutCount();
    this.isLoading = false;

    try {
      await this.persistVisibleShortcutIds(this.collectVisibleShortcutIdsFromItems(this.shortcutItems));
    } catch (error) {
      logger.warn(TAG, `持久化快捷方式配置失败: ${String(error)}`);
    }
  }

  private findShortcutItem(shortcutId: string): ShortcutDisplayItem | null {
    for (let index = 0; index < this.shortcutItems.length; index++) {
      if (this.shortcutItems[index].id === shortcutId) {
        return this.shortcutItems[index];
      }
    }
    return null;
  }

  private replaceShortcutEnabled(shortcutId: string, enabled: boolean): void {
    const nextItems: ShortcutDisplayItem[] = [];
    for (let index = 0; index < this.shortcutItems.length; index++) {
      const source = this.shortcutItems[index];
      const nextItem: ShortcutDisplayItem = {
        id: source.id,
        title: source.title,
        description: source.description,
        enabled: source.enabled
      };
      if (source.id === shortcutId) {
        nextItem.enabled = enabled;
      }
      nextItems.push(nextItem);
    }
    this.shortcutItems = nextItems;
    this.updateVisibleShortcutCount();
  }

  private buildRestartDialogMessage(): string {
    return '快捷方式配置已更新，建议重启APP后生效。\n\n是否立即重启？';
  }

  private showRestartDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '配置已保存',
      message: this.buildRestartDialogMessage(),
      buttons: [
        { text: '稍后重启', color: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) },
        { text: '立即重启', color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) }
      ]
    }).then((result) => {
      if (result.index === 1) {
        void this.restartApp();
      }
    });
  }

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
      await context.terminateSelf();
      logger.info(TAG, 'APP已重启');
    } catch (error) {
      logger.error(TAG, '重启APP失败', String(error));
      this.getUIContext().getPromptAction().showToast({
        message: '重启失败，请手动重启APP',
        duration: 2000
      });
    }
  }

  private async toggleShortcutEnabled(shortcutId: string, enabled: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    const item = this.findShortcutItem(shortcutId);
    if (!item) {
      return;
    }
    if (item.enabled === enabled) {
      return;
    }

    if (enabled && this.visibleShortcutCount >= SHORTCUT_MAX_VISIBLE_COUNT) {
      this.getUIContext().getPromptAction().showToast({
        message: `最多仅可显示 ${SHORTCUT_MAX_VISIBLE_COUNT} 个快捷方式`,
        duration: 1500
      });
      return;
    }

    this.replaceShortcutEnabled(shortcutId, enabled);

    try {
      await shortcutManager.setShortcutVisibleForSelf(shortcutId, enabled);
      await this.persistVisibleShortcutIds(this.collectVisibleShortcutIdsFromItems(this.shortcutItems));
      logger.info(TAG, `快捷方式状态已更新: id=${shortcutId}, enabled=${enabled}`);
      this.getUIContext().getPromptAction().showToast({
        message: '快捷方式设置已保存',
        duration: 1200
      });
      this.showRestartDialog();
    } catch (error) {
      this.replaceShortcutEnabled(shortcutId, !enabled);
      logger.error(TAG, `更新快捷方式状态失败: id=${shortcutId}, enabled=${enabled}, error=${String(error)}`);
      this.getUIContext().getPromptAction().showToast({
        message: '保存失败，请稍后重试',
        duration: 1500
      });
    }
  }

  @Builder
  private buildTipsCard() {
    Column({ space: 8 }) {
      Text('快捷方式说明')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text(`系统长按应用图标的快捷菜单最多展示 ${SHORTCUT_MAX_VISIBLE_COUNT} 个快捷方式，请在下方进行选择。`)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text('提示：可在桌面长按应用图标后，长按并拖动某个快捷方式到桌面。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
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

  @Builder
  private buildShortcutRow(item: ShortcutDisplayItem) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: item.enabled })
        .enabled(!this.isLoading)
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .switchPointColor(Color.White)
        .onChange((isOn: boolean) => {
          void this.toggleShortcutEnabled(item.id, isOn);
        })
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 8, bottom: 8 })
  }

  @Builder
  private buildShortcutSettingsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('快捷方式选择')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        Text(`${this.visibleShortcutCount}/${SHORTCUT_MAX_VISIBLE_COUNT}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.visibleShortcutCount > SHORTCUT_MAX_VISIBLE_COUNT
            ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      if (this.visibleShortcutCount > SHORTCUT_MAX_VISIBLE_COUNT) {
        Text(`当前已启用 ${this.visibleShortcutCount} 个，系统仅展示前 ${SHORTCUT_MAX_VISIBLE_COUNT} 个，请关闭至少 ${this.visibleShortcutCount - SHORTCUT_MAX_VISIBLE_COUNT} 个。`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .width('100%')
      } else {
        Text('可从 5 个预设中选择最多 4 个显示')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
      }

      if (this.isLoading) {
        Text('正在读取快捷方式设置...')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .padding({ top: 4, bottom: 4 })
      } else {
        Column({ space: 2 }) {
          ForEach(this.shortcutItems, (item: ShortcutDisplayItem) => {
            this.buildShortcutRow(item)
          }, (item: ShortcutDisplayItem) => item.id)
        }
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
              this.buildTipsCard()
            }
            .width('100%')
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'shortcut_info'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'shortcut_info') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'shortcut_info'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'shortcut_info', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'shortcut_info', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'shortcut_info',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })

            Column() {
              this.buildShortcutSettingsCard()
            }
            .width('100%')
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'shortcut_core'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'shortcut_core') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'shortcut_core'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'shortcut_core', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'shortcut_core', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'shortcut_core',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })

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
          title: '快捷方式',
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
      this.applyPendingSearchTarget();
    })
    .backgroundColor(Color.Transparent)
  }
}
