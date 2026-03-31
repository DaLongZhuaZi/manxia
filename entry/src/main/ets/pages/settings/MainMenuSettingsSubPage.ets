// 文件路径: entry/src/main/ets/pages/settings/MainMenuSettingsSubPage.ets
/**
 * 主页面设置子页面
 * 集中管理 MainMenuPage 相关设置
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { DataManager } from '../../Framework/Data/DataManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';
import {
  AnimationSettingsManager,
  DEFAULT_ANIMATION_SETTINGS
} from '../../Framework/Animation/AnimationSettingsManager';
import { getSuwayomiTracker, SuwayomiTracker, SuwayomiConfig } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { getKomgaTracker, KomgaTracker } from '../../Framework/Tracking/trackers/KomgaTracker';
import { KomgaConfig } from '../../Framework/Source/KomgaModels';
import { SettingsSearchSupport } from './SettingsSearchSupport';
import { SettingsGlassStyleHelper } from './SettingsGlassStyleHelper';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './SettingsPageTitleBarManager';

const TAG = 'MainMenuSettingsSubPage';
const TITLE_BAR_HEIGHT = 56;

/**
 * 详情页类型枚举
 * 注意：由于不同内容类型的数据结构不同，跨类型使用详情页可能导致显示异常
 * - DEFAULT: 使用原有的专用详情页
 * - UNIFIED: 使用统一详情页（支持所有内容类型）
 * - 其他类型: 仅在数据兼容时使用，否则回退到默认
 */
export enum DetailPageType {
  DEFAULT = 'default',       // 默认（使用原有逻辑）
  MANGA = 'manga',           // 漫画详情页
  EBOOK = 'ebook',           // 电子书详情页
  NOVEL = 'novel',           // 小说详情页
  UNIFIED = 'unified'        // 统一详情页
}

/**
 * 场景类型枚举
 */
export enum SceneType {
  MANGA = 'manga',           // 漫画场景
  EBOOK = 'ebook',           // 电子书场景
  NOVEL = 'novel'            // 小说场景
}

/**
 * 详情页选项
 */
interface DetailPageOption {
  type: DetailPageType;
  name: string;
  description: string;
}

/**
 * 底栏标签配置接口
 */
interface TabConfig {
  title: string;
  index: number;
  required: boolean;
}

/**
 * 底栏标签索引枚举
 */
enum TabIndex {
  HOME = 0,
  LIBRARY = 1,
  DISCOVER = 2,
  SOURCE = 3,
  BOOK_SOURCE = 4,
  SUWAYOMI = 5,
  SETTINGS = 6,
  KOMGA = 7
}

type TabletTopBarPosition = 'top' | 'bottom' | 'left' | 'right';

/**
 * 设置键常量
 */
export class PageSettingKeys {
  static readonly MANGA_DETAIL_PAGE_TYPE = 'page_settings_manga_detail_type';
  static readonly EBOOK_DETAIL_PAGE_TYPE = 'page_settings_ebook_detail_type';
  static readonly NOVEL_DETAIL_PAGE_TYPE = 'page_settings_novel_detail_type';
}

@Component
export struct MainMenuSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('source_features_enabled') @Watch('onSourceFeaturesEnabledChanged') sourceFeaturesEnabled: boolean = false;
  private componentId: string = 'MainMenuSettingsSubPage';
  private scroller: Scroller = new Scroller();
  @State private settingsTapEnabled: boolean = true;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  @State private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 设置状态
  @State mangaDetailPageType: DetailPageType = DetailPageType.DEFAULT;
  @State ebookDetailPageType: DetailPageType = DetailPageType.DEFAULT;
  @State novelDetailPageType: DetailPageType = DetailPageType.DEFAULT;
  @State recommendationEnabled: boolean = true;
  @State shelfContentEnabled: boolean = true;
  @State libraryCoverOpenReaderEnabled: boolean = true;
  @State mainPageBottomBarAnimationEnabled: boolean = DEFAULT_ANIMATION_SETTINGS.mainPageBottomBarAnimationEnabled;
  @State suwayomiBrowsePageAsEntryEnabled: boolean = false;
  @State komgaBrowsePageAsEntryEnabled: boolean = true;
  @State libraryDisplayMode: string = 'flat';

  // 设置管理器
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private animationSettingsManager: AnimationSettingsManager = AnimationSettingsManager.getInstance();
  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();
  private komgaTracker: KomgaTracker = getKomgaTracker();
  private dataManager: DataManager = DataManager.getInstance();

  // 详情页选项列表（只保留默认和统一详情页两项）
  private detailPageOptions: DetailPageOption[] = [
    { type: DetailPageType.DEFAULT, name: '默认', description: '使用原有的专用详情页' },
    { type: DetailPageType.UNIFIED, name: '统一详情页', description: '使用新的统一详情页（推荐，支持所有内容类型）' }
  ];

  // 底栏标签配置列表
  private tabConfigs: TabConfig[] = [
    { title: '书库', index: TabIndex.LIBRARY, required: true },
    { title: '历史', index: TabIndex.DISCOVER, required: false },
    { title: '图源', index: TabIndex.SOURCE, required: false },
    { title: '书源', index: TabIndex.BOOK_SOURCE, required: false },
    { title: 'Suwayomi', index: TabIndex.SUWAYOMI, required: false },
    { title: 'Komga', index: TabIndex.KOMGA, required: false },
    { title: '管理', index: TabIndex.SETTINGS, required: true }
  ];

  // 底栏自定义状态
  @State visibleTabIndices: number[] = [];
  @State tempVisibleTabIndices: number[] = [];
  @State tabletTopBarPosition: TabletTopBarPosition = 'top';
  private tabletTopBarPositions: TabletTopBarPosition[] = ['top', 'bottom', 'left', 'right'];

  private isSourceFeatureTab(index: number): boolean {
    return index === TabIndex.SOURCE || index === TabIndex.BOOK_SOURCE;
  }

  private getAvailableTabConfigs(): TabConfig[] {
    return this.tabConfigs.filter((cfg: TabConfig) =>
      this.sourceFeaturesEnabled || !this.isSourceFeatureTab(cfg.index)
    );
  }

  private getDefaultTabIndices(): number[] {
    const preferredOrder: number[] = [
      TabIndex.LIBRARY,
      TabIndex.SOURCE,
      TabIndex.BOOK_SOURCE,
      TabIndex.SETTINGS
    ];
    const availableIndices = this.getAvailableTabConfigs().map((cfg: TabConfig) => cfg.index);
    const defaults: number[] = [];
    for (const idx of preferredOrder) {
      if (availableIndices.includes(idx)) {
        defaults.push(idx);
      }
    }
    return defaults.length > 0 ? defaults : this.getAvailableTabConfigs().map((cfg: TabConfig) => cfg.index);
  }

  private sanitizeVisibleTabIndices(indices: number[]): number[] {
    const allowedIndices = this.getAvailableTabConfigs().map((cfg: TabConfig) => cfg.index);
    const requiredIndices = this.getAvailableTabConfigs()
      .filter((cfg: TabConfig) => cfg.required)
      .map((cfg: TabConfig) => cfg.index);
    const sanitized: number[] = [];

    for (const idx of indices) {
      if (!allowedIndices.includes(idx) || sanitized.includes(idx)) {
        continue;
      }
      sanitized.push(idx);
    }
    for (const idx of requiredIndices) {
      if (!sanitized.includes(idx)) {
        sanitized.push(idx);
      }
    }

    return sanitized;
  }

  private getEnabledTabIndicesForCustomization(): number[] {
    return this.sanitizeVisibleTabIndices(this.tempVisibleTabIndices);
  }

  private getDisabledTabConfigsForCustomization(): TabConfig[] {
    const enabledTabIndices = this.getEnabledTabIndicesForCustomization();
    return this.getAvailableTabConfigs().filter((cfg: TabConfig) =>
      !enabledTabIndices.includes(cfg.index) && !cfg.required
    );
  }

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
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
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
    this.loadVisibleTabs();
    this.loadSuwayomiEntrySettings();
    this.loadKomgaEntrySettings();
    this.loadLibraryDisplayMode();
  }

  private lifecycle = new PageLifecycleManager('MainMenuSettingsSubPage', { enableDebug: true });

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
    const target = SettingsSearchSupport.consumePendingTarget('MainMenuSettingsSubPage');
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

  /**
   * 加载设置
   */
  private loadSettings(): void {
    const mangaType = this.settingsManager.getString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    const ebookType = this.settingsManager.getString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    const novelType = this.settingsManager.getString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    const tabletTopBarPosition = this.settingsManager.getString(SettingKeys.MAIN_MENU_TABLET_TOP_BAR_POSITION, 'left');

    this.mangaDetailPageType = mangaType as DetailPageType;
    this.ebookDetailPageType = ebookType as DetailPageType;
    this.novelDetailPageType = novelType as DetailPageType;
    this.recommendationEnabled = this.settingsManager.getBoolean(SettingKeys.RECOMMENDATION_ENABLED, true);
    this.shelfContentEnabled = this.settingsManager.getBoolean(SettingKeys.SHELF_CONTENT_ENABLED, true);
    this.libraryCoverOpenReaderEnabled = this.settingsManager.getBoolean(SettingKeys.MAIN_MENU_LIBRARY_COVER_OPEN_READER_ENABLED, true);
    this.tabletTopBarPosition = this.normalizeTabletTopBarPosition(tabletTopBarPosition);
    AppStorage.setOrCreate('main_menu_tablet_top_bar_position', this.tabletTopBarPosition);
    this.mainPageBottomBarAnimationEnabled = this.animationSettingsManager.getSettings().mainPageBottomBarAnimationEnabled;

    logger.info(TAG, `加载设置: manga=${mangaType}, ebook=${ebookType}, novel=${novelType}, recommendation=${this.recommendationEnabled}, shelfContent=${this.shelfContentEnabled}, libraryCoverRead=${this.libraryCoverOpenReaderEnabled}`);
  }

  private async loadSuwayomiEntrySettings(): Promise<void> {
    try {
      await this.suwayomiTracker.initialize();
      const config = this.suwayomiTracker.getConfig();
      this.suwayomiBrowsePageAsEntryEnabled = config.useBrowsePageAsEntry ?? false;
    } catch (error) {
      logger.error(TAG, '加载 Suwayomi 入口设置失败', String(error));
    }
  }

  private async loadKomgaEntrySettings(): Promise<void> {
    try {
      await this.komgaTracker.initialize();
      const config = this.komgaTracker.getConfig();
      this.komgaBrowsePageAsEntryEnabled = config.useBrowsePageAsEntry;
    } catch (error) {
      logger.error(TAG, '加载 Komga 入口设置失败', String(error));
    }
  }

  /**
   * 保存设置
   */
  private async loadLibraryDisplayMode(): Promise<void> {
    try {
      const viewMode: string | null = await this.dataManager.getUserSetting('default_user', 'library_view_mode');
      this.libraryDisplayMode = viewMode === 'category' ? 'shelf' : 'flat';
    } catch (error) {
      logger.error(TAG, '加载主页面书库显示模式失败', String(error));
      this.libraryDisplayMode = 'flat';
    }
  }

  private async saveLibraryDisplayMode(mode: string): Promise<void> {
    if (mode === this.libraryDisplayMode) {
      return;
    }

    const targetMode: string = mode === 'shelf' ? 'category' : 'grid';
    try {
      await this.dataManager.saveUserSetting('default_user', 'library_view_mode', targetMode);
      this.libraryDisplayMode = mode;
      promptAction.showDialog({
        title: '配置已保存',
        message: '主页面书库显示模式已更新，需要重启APP后生效。\n\n是否立即重启？',
        buttons: [
          { text: '稍后重启', color: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) },
          { text: '立即重启', color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.restartApp();
        }
      });
    } catch (error) {
      logger.error(TAG, '保存主页面书库显示模式失败', String(error));
      promptAction.showToast({
        message: '保存失败，请重试',
        duration: 1500
      });
    }
  }

  private normalizeTabletTopBarPosition(value: string): TabletTopBarPosition {
    switch (value) {
      case 'top':
      case 'bottom':
      case 'left':
      case 'right':
        return value;
      default:
        return 'top';
    }
  }

  private isTabletDevice(): boolean {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    return deviceInfo.isTablet || deviceInfo.isFoldable;
  }

  private isFoldableDevice(): boolean {
    const deviceInfo = this.deviceManager.getDeviceInfo();
    return deviceInfo.isFoldable;
  }

  private getAdaptiveTopBarSettingsTitle(): string {
    if (this.isFoldableDevice()) {
      return '折叠屏导航模式';
    }
    return '平板横屏顶栏位置';
  }

  private getAdaptiveTopBarSettingsDescription(): string {
    if (this.isFoldableDevice()) {
      return '折叠屏独立逻辑：选择“上/下”使用常规手机顶栏+底栏；选择“左/右”使用平板模式侧顶栏。';
    }
    return '可将平板横屏模式的“顶栏”放在上/下/左/右，修改后建议重启 APP';
  }

  private getAdaptiveTopBarPositionLabel(position: TabletTopBarPosition): string {
    if (!this.isFoldableDevice()) {
      return this.getTabletTopBarPositionLabel(position);
    }
    switch (position) {
      case 'top':
        return '上（手机模式）';
      case 'bottom':
        return '下（手机模式）';
      case 'left':
        return '左（平板模式）';
      case 'right':
        return '右（平板模式）';
      default:
        return '上（手机模式）';
    }
  }

  private getTabletTopBarPositionLabel(position: TabletTopBarPosition): string {
    switch (position) {
      case 'top':
        return '上';
      case 'bottom':
        return '下';
      case 'left':
        return '左';
      case 'right':
        return '右';
      default:
        return '上';
    }
  }

  private async saveTabletTopBarPosition(position: TabletTopBarPosition): Promise<void> {
    const normalized = this.normalizeTabletTopBarPosition(position);
    if (normalized === this.tabletTopBarPosition) {
      return;
    }

    this.tabletTopBarPosition = normalized;

    try {
      await this.settingsManager.setString(SettingKeys.MAIN_MENU_TABLET_TOP_BAR_POSITION, normalized);
      AppStorage.setOrCreate('main_menu_tablet_top_bar_position', normalized);
      const dialogMessage = this.isFoldableDevice()
        ? '折叠屏导航模式已更新，需要重启APP后生效。\n\n是否立即重启？'
        : '平板横屏顶栏位置已更新，需要重启APP后生效。\n\n是否立即重启？';

      promptAction.showDialog({
        title: '配置已保存',
        message: dialogMessage,
        buttons: [
          { text: '稍后重启', color: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) },
          { text: '立即重启', color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.restartApp();
        }
      });
    } catch (error) {
      logger.error(TAG, '保存平板顶栏位置失败', String(error));
      promptAction.showToast({
        message: '保存失败，请重试',
        duration: 1500
      });
    }
  }

  private saveSettings(): void {
    this.settingsManager.setString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, this.mangaDetailPageType);
    this.settingsManager.setString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, this.ebookDetailPageType);
    this.settingsManager.setString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, this.novelDetailPageType);
    this.settingsManager.setBoolean(SettingKeys.RECOMMENDATION_ENABLED, this.recommendationEnabled);
    this.settingsManager.setBoolean(SettingKeys.SHELF_CONTENT_ENABLED, this.shelfContentEnabled);
    this.settingsManager.setBoolean(SettingKeys.MAIN_MENU_LIBRARY_COVER_OPEN_READER_ENABLED, this.libraryCoverOpenReaderEnabled);

    logger.info(TAG, `保存设置: manga=${this.mangaDetailPageType}, ebook=${this.ebookDetailPageType}, novel=${this.novelDetailPageType}, recommendation=${this.recommendationEnabled}, shelfContent=${this.shelfContentEnabled}, libraryCoverRead=${this.libraryCoverOpenReaderEnabled}`);

    promptAction.showToast({
      message: '设置已保存',
      duration: 1500
    });
  }

  private async saveMainPageBottomBarAnimationSetting(enabled: boolean): Promise<void> {
    try {
      await this.animationSettingsManager.setMainPageBottomBarAnimationEnabled(enabled);
      this.mainPageBottomBarAnimationEnabled = enabled;
    } catch (error) {
      logger.error(TAG, '保存主页面底栏动画设置失败', String(error));
      promptAction.showToast({
        message: '保存失败，请重试',
        duration: 1500
      });
    }
  }

  private async saveSuwayomiBrowseEntrySetting(enabled: boolean): Promise<void> {
    try {
      await this.suwayomiTracker.initialize();
      const config = this.suwayomiTracker.getConfig();
      const nextConfig: SuwayomiConfig = {
        serverUrl: config.serverUrl,
        username: config.username,
        password: config.password,
        useAuth: config.useAuth,
        useBrowsePageAsEntry: enabled
      };
      const success = await this.suwayomiTracker.saveConfig(nextConfig);
      if (!success) {
        throw new Error('saveConfig failed');
      }
      this.suwayomiBrowsePageAsEntryEnabled = enabled;
      promptAction.showToast({
        message: '设置已保存',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, '保存 Suwayomi 入口设置失败', String(error));
      this.suwayomiBrowsePageAsEntryEnabled = !enabled;
      promptAction.showToast({
        message: '保存失败，请重试',
        duration: 1500
      });
    }
  }

  /**
   * 获取详情页类型名称
   */
  private getDetailPageTypeName(type: DetailPageType): string {
    const option = this.detailPageOptions.find(o => o.type === type);
    return option ? option.name : '默认';
  }

  /**
   * 加载可见标签配置
   */
  private async loadVisibleTabs(): Promise<void> {
    try {
      const defaultTabs = this.getDefaultTabIndices();
      // 从持久化存储读取
      const savedTabs = await this.settingsManager.getVisibleTabs();
      if (savedTabs && savedTabs.length > 0) {
        this.visibleTabIndices = this.sanitizeVisibleTabIndices(savedTabs);
        logger.info(TAG, `已加载自定义标签配置: ${JSON.stringify(savedTabs)}`);
      } else {
        this.visibleTabIndices = defaultTabs;
        logger.info(TAG, '使用默认标签配置');
      }
      // 同步到临时状态
      this.tempVisibleTabIndices = [...this.visibleTabIndices];
      // 同步到 AppStorage 以便 UI 响应
      AppStorage.setOrCreate('visible_tabs', this.visibleTabIndices);
    } catch (error) {
      logger.error(TAG, '加载可见标签配置失败', String(error));
      this.visibleTabIndices = this.getDefaultTabIndices();
      this.tempVisibleTabIndices = [...this.visibleTabIndices];
    }
  }

  private async saveKomgaBrowseEntrySetting(enabled: boolean): Promise<void> {
    try {
      await this.komgaTracker.initialize();
      const config = this.komgaTracker.getConfig();
      const nextConfig: KomgaConfig = {
        instances: config.instances,
        currentInstanceId: config.currentInstanceId,
        useBrowsePageAsEntry: enabled
      };
      const success = await this.komgaTracker.saveConfig(nextConfig);
      if (!success) {
        throw new Error('saveConfig failed');
      }
      this.komgaBrowsePageAsEntryEnabled = enabled;
      promptAction.showToast({
        message: '设置已保存',
        duration: 1500
      });
    } catch (error) {
      logger.error(TAG, '保存 Komga 入口设置失败', String(error));
      this.komgaBrowsePageAsEntryEnabled = !enabled;
      promptAction.showToast({
        message: '保存失败，请重试',
        duration: 1500
      });
    }
  }

  private onSourceFeaturesEnabledChanged(): void {
    void this.loadVisibleTabs();
  }

  /**
   * 保存可见标签配置
   */
  private async saveVisibleTabs(preserveHiddenSourceTabs: boolean = true): Promise<void> {
    try {
      // 确保必须显示的标签（书库、管理）始终存在
      const requiredIndices = this.getAvailableTabConfigs()
        .filter(cfg => cfg.required)
        .map(cfg => cfg.index);
      const allowedIndices = this.getAvailableTabConfigs().map((cfg: TabConfig) => cfg.index);
      const hiddenSourceIndices = !this.sourceFeaturesEnabled && preserveHiddenSourceTabs
        ? (await this.settingsManager.getVisibleTabs()).filter((idx: number) => this.isSourceFeatureTab(idx))
        : [];

      // 合并索引并去重
      const combined: number[] = [];
      for (const idx of this.tempVisibleTabIndices) {
        if (allowedIndices.includes(idx) && !combined.includes(idx)) {
          combined.push(idx);
        }
      }
      for (const idx of requiredIndices) {
        if (!combined.includes(idx)) {
          combined.push(idx);
        }
      }
      for (const idx of hiddenSourceIndices) {
        if (!combined.includes(idx)) {
          combined.push(idx);
        }
      }

      const finalIndices = combined;
      // 不再排序，保持用户自定义顺序

      // 保存到持久化存储
      await this.settingsManager.setVisibleTabs(finalIndices);
      // 同步到 AppStorage 以便 UI 响应
      AppStorage.setOrCreate('visible_tabs', finalIndices);
      
      this.visibleTabIndices = finalIndices;
      this.tempVisibleTabIndices = [...finalIndices];

      logger.info(TAG, `已保存标签配置: ${JSON.stringify(finalIndices)}`);
      
      // 显示重启提示对话框
      promptAction.showDialog({
        title: '配置已保存',
        message: '底栏配置已保存，需要重启APP才能生效。\n\n是否立即重启？',
        buttons: [
          { text: '稍后重启', color: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) },
          { text: '立即重启', color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) }
        ]
      }).then((result) => {
        if (result.index === 1) {
          // 用户选择立即重启
          this.restartApp();
        }
      });
    } catch (error) {
      logger.error(TAG, '保存可见标签配置失败', String(error));
    }
  }

  /**
   * 切换标签可见性
   */
  private toggleTabVisibility(index: number): void {
    if (!this.getAvailableTabConfigs().some((cfg: TabConfig) => cfg.index === index)) {
      return;
    }

    const newIndices: number[] = [];
    const idx = this.tempVisibleTabIndices.indexOf(index);

    if (idx > -1) {
      // 移除该索引
      for (let i = 0; i < this.tempVisibleTabIndices.length; i++) {
        if (this.tempVisibleTabIndices[i] !== index) {
          newIndices.push(this.tempVisibleTabIndices[i]);
        }
      }
      this.tempVisibleTabIndices = newIndices;
    } else {
      // 添加到末尾
      for (let i = 0; i < this.tempVisibleTabIndices.length; i++) {
        newIndices.push(this.tempVisibleTabIndices[i]);
      }
      newIndices.push(index);
      this.tempVisibleTabIndices = newIndices;
    }
  }

  /**
   * 移动标签位置（拖拽排序）
   */
  private moveTab(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0) {
      return;
    }
    const newIndices = [...this.tempVisibleTabIndices];
    const removedArr = newIndices.splice(fromIndex, 1);
    const removed = removedArr[0];
    newIndices.splice(toIndex, 0, removed);
    this.tempVisibleTabIndices = newIndices;
    logger.info(TAG, `移动标签: ${fromIndex} -> ${toIndex}`);
  }

  /**
   * 重置底栏配置为默认
   */
  private async resetTabsToDefault(): Promise<void> {
    this.tempVisibleTabIndices = this.getDefaultTabIndices();
    await this.saveVisibleTabs(false);
  }

  /**
   * 重启APP
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
      await context.terminateSelf();
      logger.info(TAG, 'APP已重启');
    } catch (error) {
      logger.error(TAG, '重启APP失败', String(error));
      promptAction.showToast({
        message: '重启失败，请手动重启APP',
        duration: 2000
      });
    }
  }

  @Builder
  buildSceneSettings(title: string, description: string, currentType: DetailPageType, onSelect: (type: DetailPageType) => void) {
    Column({ space: 0 }) {
      // 标题行
      Row() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        Text(this.getDetailPageTypeName(currentType))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')
      .padding({ top: 14, bottom: 8 })

      // 描述
      Text(description)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
        .padding({ bottom: 12 })

      // 选项列表
      Column({ space: 4 }) {
        ForEach(this.detailPageOptions, (option: DetailPageOption) => {
          Row({ space: 12 }) {
            // 自定义单选框
            Stack() {
              Circle()
                .width(20)
                .height(20)
                .fill(Color.Transparent)
                .stroke(currentType === option.type ?
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .strokeWidth(currentType === option.type ? 2 : 1.5)

              if (currentType === option.type) {
                Circle()
                  .width(10)
                  .height(10)
                  .fill(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
            }

            Column({ space: 2 }) {
              Text(option.name)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Text(option.description)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .height(52)
          .padding({ left: 8, right: 8 })
          .borderRadius(10)
          .backgroundColor(currentType === option.type ?
            (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.03)') :
            Color.Transparent)
          .onClick(() => {
            onSelect(option.type);
          })
        }, (option: DetailPageOption) => `${option.type}_${currentType}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildLibraryDisplayModeSetting() {
    Column({ space: 10 }) {
      Text('主页面书库显示模式')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text('平铺为默认模式；书架为书架视图。修改后需重启APP生效。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Row({ space: 8 }) {
          Text('平铺（默认模式）')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.libraryDisplayMode === 'flat'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (this.libraryDisplayMode === 'flat') {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
        }
        .height(42)
        .padding({ left: 14, right: 14 })
        .margin({ right: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.libraryDisplayMode === 'flat'
          ? (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')
          : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderWidth(this.libraryDisplayMode === 'flat' ? 1.5 : 1)
        .borderColor(this.libraryDisplayMode === 'flat'
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
        .onClick(() => {
          this.saveLibraryDisplayMode('flat');
        })

        Row({ space: 8 }) {
          Text('书架（书架视图）')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.libraryDisplayMode === 'shelf'
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (this.libraryDisplayMode === 'shelf') {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
        }
        .height(42)
        .padding({ left: 14, right: 14 })
        .margin({ right: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.libraryDisplayMode === 'shelf'
          ? (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')
          : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderWidth(this.libraryDisplayMode === 'shelf' ? 1.5 : 1)
        .borderColor(this.libraryDisplayMode === 'shelf'
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
        .onClick(() => {
          this.saveLibraryDisplayMode('shelf');
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildResetButton() {
    Button('恢复主页面设置默认值')
      .fontSize(14)
      .fontFamily(this.appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
      .backgroundColor(Color.Transparent)
      .borderWidth(1)
      .borderColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
      .borderRadius(12)
      .height(44)
      .width('100%')
      .onClick(() => {
        promptAction.showDialog({
          title: '确认重置',
          message: '这将重置主页面相关设置和底栏配置为默认值，是否继续？',
          buttons: [
            { text: '取消', color: '#888888' },
            { text: '确认重置', color: '#FF4444' }
          ]
        }).then(async (result) => {
          if (result.index === 1) {
            this.libraryCoverOpenReaderEnabled = true;
            this.mainPageBottomBarAnimationEnabled = DEFAULT_ANIMATION_SETTINGS.mainPageBottomBarAnimationEnabled;
            this.suwayomiBrowsePageAsEntryEnabled = false;
            this.settingsManager.setBoolean(SettingKeys.MAIN_MENU_LIBRARY_COVER_OPEN_READER_ENABLED, true);
            await this.saveMainPageBottomBarAnimationSetting(DEFAULT_ANIMATION_SETTINGS.mainPageBottomBarAnimationEnabled);
            await this.saveSuwayomiBrowseEntrySetting(false);
            this.resetTabsToDefault();
          }
        });
      })
  }

  /**
   * 获取标签配置
   */
  private getTabConfig(tabIndex: number): TabConfig | undefined {
    return this.getAvailableTabConfigs().find((cfg: TabConfig) => cfg.index === tabIndex);
  }

  @Builder
  buildTabItem(tabIndex: number, arrayIndex: number, isEnabled: boolean) {
    Row({ space: 8 }) {
      // 上下移动按钮（仅启用的标签显示）
      if (isEnabled && arrayIndex >= 0) {
        Column({ space: 2 }) {
          // 上移按钮
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(16)
            .fontColor([arrayIndex > 0 ?
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            .onClick(() => {
              if (arrayIndex > 0) {
                this.moveTab(arrayIndex, arrayIndex - 1);
              }
            })
          // 下移按钮
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([arrayIndex < this.tempVisibleTabIndices.length - 1 ?
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
            .onClick(() => {
              if (arrayIndex < this.tempVisibleTabIndices.length - 1) {
                this.moveTab(arrayIndex, arrayIndex + 1);
              }
            })
        }
        .width(24)
        .justifyContent(FlexAlign.Center)
      } else {
        Blank().width(24)
      }

      // 标题和描述
      Column({ space: 2 }) {
        Text(this.getTabConfig(tabIndex)?.title ?? '')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(isEnabled ?
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

        if (this.getTabConfig(tabIndex)?.required) {
          Text('必须显示')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 开关
      Toggle({ type: ToggleType.Switch, isOn: isEnabled })
        .selectedColor('#6200EE')
        .switchPointColor(Color.White)
        .enabled(!(this.getTabConfig(tabIndex)?.required ?? false))
        .onChange((isOn: boolean) => {
          if (!(this.getTabConfig(tabIndex)?.required ?? false)) {
            this.toggleTabVisibility(tabIndex);
          }
        })
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 16 })
    .borderRadius(10)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      if (!(this.getTabConfig(tabIndex)?.required ?? false)) {
        this.toggleTabVisibility(tabIndex);
      }
    })
  }

  @Builder
  buildTabCustomization() {
    Column({ space: 12 }) {
      // 操作提示
      Text('点击上下箭头调整标签顺序，开关控制是否显示')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .padding({ left: 4, bottom: 4 })

      // 已启用的标签（按顺序显示，可拖抽排序）
      if (this.getEnabledTabIndicesForCustomization().length > 0) {
        Column({ space: 4 }) {
          Text('已启用')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .padding({ left: 4, bottom: 4 })

          Column({ space: 2 }) {
            ForEach(this.getEnabledTabIndicesForCustomization(), (tabIndex: number, index: number) => {
              this.buildTabItem(tabIndex, index, true)
            }, (tabIndex: number) => `enabled_${tabIndex}_${this.getEnabledTabIndicesForCustomization().indexOf(tabIndex)}`)
          }
          .width('100%')
          .padding(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(12)
        }
        .width('100%')
      }

      // 未启用的标签
      Column({ space: 4 }) {
        // 筛选未启用的标签
        if (this.getDisabledTabConfigsForCustomization().length > 0) {
          Text('未启用')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .padding({ left: 4, bottom: 4 })

          Column({ space: 2 }) {
            ForEach(this.getDisabledTabConfigsForCustomization(),
              (cfg: TabConfig) => {
                this.buildTabItem(cfg.index, -1, false)
              }, (cfg: TabConfig) => `disabled_${cfg.index}`)
          }
          .width('100%')
          .padding(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(12)
        }
      }
      .width('100%')

      // 操作按钮
      Row({ space: 12 }) {
        // 重置按钮
        Button('重置')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .backgroundColor(this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)')
          .borderRadius(10)
          .height(44)
          .layoutWeight(1)
          .onClick(() => {
            this.tempVisibleTabIndices = this.getDefaultTabIndices();
          })

        // 保存按钮
        Button('保存配置')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(10)
          .height(44)
          .layoutWeight(2)
          .onClick(() => {
            this.saveVisibleTabs();
          })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildTabletTopBarPositionSettings() {
    Column({ space: 8 }) {
      Text('平板横屏顶栏位置')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .padding({ left: 4 })

      Text('可将平板横屏模式的“顶栏”放在上/下/左/右，修改后建议重启 APP')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .padding({ left: 4, bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.tabletTopBarPositions, (position: TabletTopBarPosition) => {
          Row({ space: 8 }) {
            Text(this.getTabletTopBarPositionLabel(position))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.tabletTopBarPosition === position
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            if (this.tabletTopBarPosition === position) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            }
          }
          .height(42)
          .padding({ left: 14, right: 14 })
          .margin({ right: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(this.tabletTopBarPosition === position
            ? (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')
            : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderWidth(this.tabletTopBarPosition === position ? 1.5 : 1)
          .borderColor(this.tabletTopBarPosition === position
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
          .onClick(() => {
            this.saveTabletTopBarPosition(position);
          })
        }, (position: TabletTopBarPosition) => position)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildAdaptiveTopBarPositionSettings() {
    Column({ space: 8 }) {
      Text(this.getAdaptiveTopBarSettingsTitle())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .padding({ left: 4 })

      Text(this.getAdaptiveTopBarSettingsDescription())
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .padding({ left: 4, bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.tabletTopBarPositions, (position: TabletTopBarPosition) => {
          Row({ space: 8 }) {
            Text(this.getAdaptiveTopBarPositionLabel(position))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(this.tabletTopBarPosition === position
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            if (this.tabletTopBarPosition === position) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            }
          }
          .height(42)
          .padding({ left: 14, right: 14 })
          .margin({ right: 8, bottom: 8 })
          .borderRadius(10)
          .backgroundColor(this.tabletTopBarPosition === position
            ? (this.themeState.currentTheme === ThemeType.DARK ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)')
            : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderWidth(this.tabletTopBarPosition === position ? 1.5 : 1)
          .borderColor(this.tabletTopBarPosition === position
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('comp_divider', this.themeState.currentTheme))
          .onClick(() => {
            this.saveTabletTopBarPosition(position);
          })
        }, (position: TabletTopBarPosition) => position)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
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
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {

            // 主页面交互设置
            Column({ space: 8 }) {
              Text('主页面交互')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .padding({ left: 4 })

              Text('控制主页面书库点击行为、底栏动画，以及 Suwayomi / Komga 入口跳转行为')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .padding({ left: 4, bottom: 8 })

              this.buildLibraryDisplayModeSetting()

              Row() {
                Column({ space: 4 }) {
                  Text('书库封面点击直达阅读')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text('开启后：书库内点击封面直接阅读；点击标题打开详情页')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.libraryCoverOpenReaderEnabled })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    this.libraryCoverOpenReaderEnabled = isOn;
                    this.settingsManager.setBoolean(SettingKeys.MAIN_MENU_LIBRARY_COVER_OPEN_READER_ENABLED, isOn);
                    promptAction.showToast({
                      message: '设置已保存',
                      duration: 1500
                    });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(12)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })

              Row() {
                Column({ space: 4 }) {
                  Text('底栏动画效果')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text('关闭后底部导航栏将常驻显示，不会自动隐藏')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.mainPageBottomBarAnimationEnabled })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    this.mainPageBottomBarAnimationEnabled = isOn;
                    this.saveMainPageBottomBarAnimationSetting(isOn);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(12)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })

              Row() {
                Column({ space: 4 }) {
                  Text('Suwayomi 入口直达浏览页')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text('开启后，主页面 Suwayomi 入口将直接跳转到浏览页面')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.suwayomiBrowsePageAsEntryEnabled })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    this.suwayomiBrowsePageAsEntryEnabled = isOn;
                    this.saveSuwayomiBrowseEntrySetting(isOn);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(12)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })

              Row() {
                Column({ space: 4 }) {
                  Text('Komga 入口直达浏览页')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  Text('开启后，主页面 Komga 入口将直接跳转到浏览页面')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.komgaBrowsePageAsEntryEnabled })
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .switchPointColor(Color.White)
                  .onChange((isOn: boolean) => {
                    this.komgaBrowsePageAsEntryEnabled = isOn;
                    this.saveKomgaBrowseEntrySetting(isOn);
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .borderRadius(12)
              .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
            }
            .width(this.responsive_isLandscape ? '48%' : '100%')
            .alignItems(HorizontalAlign.Start)
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_behavior'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'main_menu_behavior') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'main_menu_behavior'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_behavior', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_behavior', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_behavior',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })
            .margin({ bottom: 16 })

            // 底栏自定义部分
            Column({ space: 8 }) {
              // 分段标题
              Text('底栏自定义')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .padding({ left: 4 })

              Text('自定义底部导航栏显示的标签及顺序')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .padding({ left: 4, bottom: 8 })

              // 底栏标签自定义
              this.buildTabCustomization()
            }
            .width(this.responsive_isLandscape ? '48%' : '100%')
            .alignItems(HorizontalAlign.Start)
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_navigation'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'main_menu_navigation') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'main_menu_navigation'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_navigation', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_navigation', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_navigation',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })
            .margin({ bottom: 16 })

            if (this.isTabletDevice()) {
              Column() {
                this.buildAdaptiveTopBarPositionSettings()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'main_menu_adaptive_nav'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'main_menu_adaptive_nav') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'main_menu_adaptive_nav'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_adaptive_nav', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_adaptive_nav', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'main_menu_adaptive_nav',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })
            }

            // 恢复默认按钮
            Column() {
              this.buildResetButton()
            }
            .width(this.responsive_isLandscape ? '48%' : '100%')
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_reset'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'main_menu_reset') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'main_menu_reset'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_reset', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'main_menu_reset', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'main_menu_reset',
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
        .scrollBar(BarState.Auto)
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '主页面设置',
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

/**
 * 页面设置工具类
 * 用于获取当前场景应该使用的详情页类型
 * 
 * 重要：如果全局强制模式启用，所有场景都将使用统一详情页
 */
export class PageSettingsHelper {
  private static settingsManager: SettingsManager = SettingsManager.getInstance();
  
  // 强制模式设置键
  private static readonly FORCE_UNIFIED_KEY = 'force_unified_detail_page_enabled';

  /**
   * 检查强制统一详情页模式是否启用
   * 默认为 true（强制启用统一详情页）
   */
  static isForceUnifiedEnabled(): boolean {
    return PageSettingsHelper.settingsManager.getBoolean(PageSettingsHelper.FORCE_UNIFIED_KEY, true);
  }

  /**
   * 获取漫画场景的详情页类型
   */
  static getMangaDetailPageType(): DetailPageType {
    // 强制模式下直接返回 UNIFIED
    if (PageSettingsHelper.isForceUnifiedEnabled()) {
      return DetailPageType.UNIFIED;
    }
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 获取电子书场景的详情页类型
   */
  static getEBookDetailPageType(): DetailPageType {
    // 强制模式下直接返回 UNIFIED
    if (PageSettingsHelper.isForceUnifiedEnabled()) {
      return DetailPageType.UNIFIED;
    }
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 获取小说场景的详情页类型
   */
  static getNovelDetailPageType(): DetailPageType {
    // 强制模式下直接返回 UNIFIED
    if (PageSettingsHelper.isForceUnifiedEnabled()) {
      return DetailPageType.UNIFIED;
    }
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 根据场景和设置获取应该跳转的详情页名称
   * 
   * 注意：如果强制模式启用，始终返回 'UnifiedDetailPage'
   */
  static getDetailPageName(scene: SceneType): string {
    // 双重保障：强制模式下直接返回统一详情页
    if (PageSettingsHelper.isForceUnifiedEnabled()) {
      logger.debug('PageSettingsHelper', `强制模式启用，${scene}场景使用统一详情页`);
      return 'UnifiedDetailPage';
    }
    
    let pageType: DetailPageType;

    switch (scene) {
      case SceneType.MANGA:
        pageType = PageSettingsHelper.getMangaDetailPageType();
        break;
      case SceneType.EBOOK:
        pageType = PageSettingsHelper.getEBookDetailPageType();
        break;
      case SceneType.NOVEL:
        pageType = PageSettingsHelper.getNovelDetailPageType();
        break;
      default:
        pageType = DetailPageType.DEFAULT;
    }

    // 如果是默认，返回原有页面名称
    if (pageType === DetailPageType.DEFAULT) {
      switch (scene) {
        case SceneType.MANGA:
          return 'MangaDetailPage';
        case SceneType.EBOOK:
          return 'EBookDetailPage';
        case SceneType.NOVEL:
          return 'NovelDetailPage';
      }
    }

    // 如果选择了统一详情页
    if (pageType === DetailPageType.UNIFIED) {
      return 'UnifiedDetailPage';
    }

    // 如果选择了特定类型的详情页
    switch (pageType) {
      case DetailPageType.MANGA:
        return 'MangaDetailPage';
      case DetailPageType.EBOOK:
        return 'EBookDetailPage';
      case DetailPageType.NOVEL:
        return 'NovelDetailPage';
      default:
        return 'UnifiedDetailPage';
    }
  }
}
