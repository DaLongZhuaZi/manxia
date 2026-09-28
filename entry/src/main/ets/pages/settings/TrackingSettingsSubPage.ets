import { UIContext } from '@ohos.arkui.UIContext';
// 文件路径: entry/src/main/ets/pages/settings/TrackingSettingsSubPage.ets
/**
 * 进度记录与服务器设置子页面
 * 管理第三方进度记录（MAL、AniList、Bangumi）与服务器（Suwayomi、Komga）的登录和配置
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import {
  TrackerId,
  TrackerInfo,
  TRACKER_INFO_LIST,
  getTrackerName
} from '../../Framework/Tracking/TrackingModels';
import { getAniListTracker, AniListTracker } from '../../Framework/Tracking/trackers/AniListTracker';
import { getSuwayomiTracker, SuwayomiTracker } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { getKomgaTracker, KomgaTracker } from '../../Framework/Tracking/trackers/KomgaTracker';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'TrackingSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 进度记录登录状态
 */
interface TrackerLoginStatus {
  trackerId: TrackerId;
  isLoggedIn: boolean;
  statusText: string;
  primaryInfoLabel: string;
  primaryInfoValue: string;
  connectionLabel: string;
  connectionValue: string;
  secondaryInfo: string;
  statusTone: TrackerStatusTone;
}

enum TrackerStatusTone {
  NEUTRAL = 0,
  INFO = 1,
  SUCCESS = 2
}

@Component
export struct TrackingSettingsSubPage {
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
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'TrackingSettingsSubPage';

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 进度记录状态
  @State trackerStatusList: TrackerLoginStatus[] = [];
  private trackerRefreshVersion: number = 0;

  // 跟踪器实例
  private aniListTracker: AniListTracker = getAniListTracker();
  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();
  private komgaTracker: KomgaTracker = getKomgaTracker();

  private lifecycle = new PageLifecycleManager('TrackingSettingsSubPage', { enableDebug: true });

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
    this.refreshTrackerStatus();
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

    this.refreshTrackerStatus();
    this.applyPendingSearchTarget();
  }

  private refreshTrackerStatus(): void {
    const refreshVersion = ++this.trackerRefreshVersion;
    void this.initializeTrackerStatus(refreshVersion);
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('TrackingSettingsSubPage');
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

  private async initializeTrackerStatus(refreshVersion: number): Promise<void> {
    try {
      await this.aniListTracker.initialize();
      await this.suwayomiTracker.initialize(true);
      await this.komgaTracker.initialize(true);

      const statusList: TrackerLoginStatus[] = [
        this.buildAniListTrackerStatus(),
        this.buildSuwayomiTrackerStatus(),
        this.buildKomgaTrackerStatus()
      ];
      if (refreshVersion !== this.trackerRefreshVersion) {
        logger.info(TAG, `忽略过期的进度记录状态刷新: version=${refreshVersion}`);
        return;
      }
      this.trackerStatusList = statusList.concat();
      logger.info(TAG, `初始化进度记录状态: ${this.trackerStatusList.length}个服务`);
    } catch (error) {
      logger.error(TAG, '初始化进度记录状态失败', String(error));
    }
  }

  private getTrackerStatus(trackerId: TrackerId): TrackerLoginStatus | undefined {
    return this.trackerStatusList.find(s => s.trackerId === trackerId);
  }

  private getTrackerStatusOrDefault(trackerId: TrackerId): TrackerLoginStatus {
    const status = this.getTrackerStatus(trackerId);
    if (status) {
      return status;
    }
    return {
      trackerId: trackerId,
      isLoggedIn: false,
      statusText: '未配置',
      primaryInfoLabel: '状态',
      primaryInfoValue: '暂未获取服务状态',
      connectionLabel: '连接',
      connectionValue: '状态获取失败',
      secondaryInfo: '请稍后重试',
      statusTone: TrackerStatusTone.NEUTRAL
    };
  }

  private buildAniListTrackerStatus(): TrackerLoginStatus {
    const authState = this.aniListTracker.getAuthState();
    const isLoggedIn = authState.isLoggedIn && authState.username.trim().length > 0;
    return {
      trackerId: TrackerId.ANILIST,
      isLoggedIn: isLoggedIn,
      statusText: isLoggedIn ? '已登录' : '未登录',
      primaryInfoLabel: '账号',
      primaryInfoValue: isLoggedIn ? authState.username : '点击登录 AniList 账号',
      connectionLabel: '授权',
      connectionValue: isLoggedIn ? 'OAuth 授权已建立' : '尚未建立 AniList 授权',
      secondaryInfo: isLoggedIn ? 'OAuth 已授权，可同步漫画阅读进度' : '登录后可将阅读进度同步到 AniList',
      statusTone: isLoggedIn ? TrackerStatusTone.SUCCESS : TrackerStatusTone.NEUTRAL
    };
  }

  private buildSuwayomiTrackerStatus(): TrackerLoginStatus {
    const config = this.suwayomiTracker.getConfig();
    const hasServer = config.serverUrl.trim().length > 0;
    let authText = '认证：未启用';
    if (config.useAuth) {
      authText = config.username.trim().length > 0 ? `认证：${config.username}` : '认证：已启用';
    }
    const secondaryInfo = hasServer
      ? `${config.useBrowsePageAsEntry ? '浏览页入口' : '设置页入口'} · 可用于进度同步`
      : '配置 Suwayomi 服务器后即可启用同步';
    return {
      trackerId: TrackerId.SUWAYOMI,
      isLoggedIn: hasServer,
      statusText: hasServer ? '已配置' : '未配置',
      primaryInfoLabel: '服务器',
      primaryInfoValue: hasServer ? config.serverUrl : '点击填写 Suwayomi 服务器地址',
      connectionLabel: '认证',
      connectionValue: hasServer ? authText : '未建立服务器连接',
      secondaryInfo: secondaryInfo,
      statusTone: hasServer ? TrackerStatusTone.INFO : TrackerStatusTone.NEUTRAL
    };
  }

  private buildKomgaTrackerStatus(): TrackerLoginStatus {
    const config = this.komgaTracker.getConfig();
    const currentInstance = this.komgaTracker.getCurrentInstance();
    const hasCurrentInstance = currentInstance !== null && currentInstance.serverUrl.trim().length > 0;
    const enabledInstanceCount = config.instances.filter((instance) => {
      return instance.enabled !== false && instance.serverUrl.trim().length > 0;
    }).length;
    const authModeText = hasCurrentInstance && currentInstance
      ? (currentInstance.authMode === 'API_KEY'
        ? 'API Key 认证'
        : (currentInstance.authMode === 'BASIC' ? 'Basic 认证' : '匿名访问'))
      : '未建立实例连接';
    const secondaryInfo = hasCurrentInstance
      ? `${authModeText} · ${config.useBrowsePageAsEntry ? '浏览页入口' : '设置页入口'} · 已启用实例 ${enabledInstanceCount} 个`
      : `已保存实例 ${config.instances.length} 个，点击继续配置 Komga`;
    return {
      trackerId: TrackerId.KOMGA,
      isLoggedIn: hasCurrentInstance,
      statusText: hasCurrentInstance ? '已配置' : '未配置',
      primaryInfoLabel: '当前实例',
      primaryInfoValue: hasCurrentInstance ? this.komgaTracker.getAuthState().username : '点击配置 Komga 实例',
      connectionLabel: '服务器',
      connectionValue: hasCurrentInstance && currentInstance ? currentInstance.serverUrl : '未配置服务器地址',
      secondaryInfo: secondaryInfo,
      statusTone: hasCurrentInstance ? TrackerStatusTone.INFO : TrackerStatusTone.NEUTRAL
    };
  }

  /**
   * 获取可用的进度记录列表（只显示已实现的服务）
   */
  private getAvailableTrackers(): TrackerInfo[] {
    const availableIds: TrackerId[] = [TrackerId.ANILIST, TrackerId.SUWAYOMI, TrackerId.KOMGA];
    return TRACKER_INFO_LIST.filter(tracker => availableIds.includes(tracker.id));
  }

  /**
   * 检查进度记录是否可用
   */
  private isTrackerAvailable(trackerId: TrackerId): boolean {
    return trackerId === TrackerId.ANILIST || trackerId === TrackerId.SUWAYOMI || trackerId === TrackerId.KOMGA;
  }

  private handleTrackerClick(tracker: TrackerInfo): void {
    const status = this.getTrackerStatus(tracker.id);
    
    // Suwayomi 总是进入设置页面（可以编辑配置或登出）
    if (tracker.id === TrackerId.SUWAYOMI) {
      this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
      return;
    }
    if (tracker.id === TrackerId.KOMGA) {
      this.pathStack.pushPathByName('KomgaSettingsPage', null);
      return;
    }
    
    if (status && status.isLoggedIn) {
      // 已登录，显示账户管理对话框
      logger.info(TAG, `点击已登录的进度记录: ${tracker.name}`);
      this.showAccountDialog(tracker, status.primaryInfoValue);
    } else {
      // 未登录，开始登录流程
      logger.info(TAG, `点击未登录的进度记录: ${tracker.name}`);
      this.startLogin(tracker);
    }
  }

  private startLogin(tracker: TrackerInfo): void {
    switch (tracker.id) {
      case TrackerId.ANILIST:
        // 导航到 AniList 登录页面
        this.pathStack.pushPathByName('AniListLoginPage', null);
        break;
      case TrackerId.SUWAYOMI:
        // 导航到 Suwayomi 设置页面
        this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
        break;
      case TrackerId.KOMGA:
        this.pathStack.pushPathByName('KomgaSettingsPage', null);
        break;
      default:
        this.showComingSoonToast(tracker.name);
        break;
    }
  }

  private showAccountDialog(tracker: TrackerInfo, username: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: tracker.name,
      message: `已登录账户: ${username}`,
      buttons: [
        {
          text: '登出',
          color: '#FF6B6B'
        },
        {
          text: '取消',
          color: '#999999'
        }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 0) {
        this.handleLogout(tracker);
      }
    });
  }

  private async handleLogout(tracker: TrackerInfo): Promise<void> {
    switch (tracker.id) {
      case TrackerId.ANILIST:
        await this.aniListTracker.logout();
        break;
      case TrackerId.SUWAYOMI:
        await this.suwayomiTracker.logout();
        break;
      case TrackerId.KOMGA:
        await this.komgaTracker.logout();
        break;
      default:
        break;
    }
    this.refreshTrackerStatus();
    import('@kit.ArkUI').then(arkUI => {
      AppStorage.get<UIContext>('GlobalUIContext')?.getPromptAction()?.showToast({
        message: `已从 ${tracker.name} 登出`,
        duration: 2000
      });
    });
  }

  private showComingSoonToast(serviceName: string): void {
    import('@kit.ArkUI').then(arkUI => {
      AppStorage.get<UIContext>('GlobalUIContext')?.getPromptAction()?.showToast({
        message: `${serviceName} 登录功能即将推出`,
        duration: 2000
      });
    });
  }

  private getTrackerIcon(iconName: string): Resource {
    switch (iconName) {
      case 'anilist_icon':
        return $r('app.media.anilist_icon');
      case 'mal_icon':
        return $r('app.media.icon');
      case 'kitsu_icon':
        return $r('app.media.icon');
      case 'mangaupdates_icon':
        return $r('app.media.icon');
      case 'bangumi_icon':
        return $r('app.media.icon');
      case 'suwayomi_icon':
        return $r('app.media.suwayomi_icon');
      case 'komga_icon':
        return $r('app.media.komga_icon');
      default:
        return $r('app.media.icon');
    }
  }

  @Builder
  buildTrackerItem(tracker: TrackerInfo) {
    Row() {
      Image(this.getTrackerIcon(tracker.icon))
        .width(44)
        .height(44)
        .borderRadius(22)
        .objectFit(ImageFit.Cover)

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(tracker.name)
            .layoutWeight(1)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(this.getTrackerStatusOrDefault(tracker.id).statusText)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getTrackerStatusTextColor(tracker.id))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.getTrackerStatusBackgroundColor(tracker.id))
            .borderRadius(999)
        }
        .width('100%')

        Text(this.getTrackerDescription(tracker.id))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 6 }) {
          Text(this.getTrackerStatusOrDefault(tracker.id).primaryInfoLabel)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

          Text(this.getTrackerStatusOrDefault(tracker.id).primaryInfoValue)
            .layoutWeight(1)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(this.getTrackerStatusOrDefault(tracker.id).connectionLabel)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

          Text(this.getTrackerStatusOrDefault(tracker.id).connectionValue)
            .layoutWeight(1)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Text(this.getTrackerStatusOrDefault(tracker.id).secondaryInfo)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })

      Image($r('sys.symbol.chevron_right'))
        .width(16)
        .height(16)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .onClick(() => this.handleTrackerClick(tracker))
  }

  private getTrackerColor(trackerId: TrackerId): ResourceColor {
    switch (trackerId) {
      case TrackerId.MY_ANIME_LIST:
        return '#2E51A2';
      case TrackerId.ANILIST:
        return '#02A9FF';
      case TrackerId.KITSU:
        return '#F75239';
      case TrackerId.MANGA_UPDATES:
        return '#F7931E';
      case TrackerId.BANGUMI:
        return '#F09199';
      case TrackerId.SUWAYOMI:
        return '#6366F1';
      case TrackerId.KOMGA:
        return '#10B981';
      default:
        return '#6B7280';
    }
  }

  private getTrackerDescription(trackerId: TrackerId): string {
    switch (trackerId) {
      case TrackerId.MY_ANIME_LIST:
        return '全球最大的动漫数据库';
      case TrackerId.ANILIST:
        return '现代化的动漫追踪平台';
      case TrackerId.KITSU:
        return '社区驱动的动漫追踪';
      case TrackerId.MANGA_UPDATES:
        return '漫画发布信息追踪';
      case TrackerId.BANGUMI:
        return '中文ACG追踪平台';
      case TrackerId.SUWAYOMI:
        return '自托管漫画服务器同步';
      case TrackerId.KOMGA:
        return 'Komga 自托管漫画服务器连接';
      default:
        return '进度记录与服务器';
    }
  }

  private getTrackerStatusTextColor(trackerId: TrackerId): ResourceColor {
    const status = this.getTrackerStatusOrDefault(trackerId);
    switch (status.statusTone) {
      case TrackerStatusTone.SUCCESS:
        return ThemeAwareHelper.getTestManagementThemedColor('color_success', this.themeState.currentTheme);
      case TrackerStatusTone.INFO:
        return ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme);
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme);
    }
  }

  private getTrackerStatusBackgroundColor(trackerId: TrackerId): ResourceColor {
    const status = this.getTrackerStatusOrDefault(trackerId);
    if (status.statusTone === TrackerStatusTone.SUCCESS) {
      return this.themeState.currentTheme === ThemeType.DARK ? 'rgba(16, 185, 129, 0.18)' : 'rgba(16, 185, 129, 0.10)';
    }
    if (status.statusTone === TrackerStatusTone.INFO) {
      return this.themeState.currentTheme === ThemeType.DARK ? 'rgba(2, 169, 255, 0.18)' : 'rgba(2, 169, 255, 0.10)';
    }
    return this.themeState.currentTheme === ThemeType.DARK ? 'rgba(148, 163, 184, 0.14)' : 'rgba(100, 116, 139, 0.10)';
  }

  @Builder
  buildTrackerSection() {
    Column({ space: 16 }) {
      Text('进度记录与服务器')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('连接进度记录平台与自托管服务器以同步阅读进度。Suwayomi 和 Komga 属于服务器，AniList 等属于进度记录平台。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Column({ space: 8 }) {
        ForEach(this.getAvailableTrackers(), (tracker: TrackerInfo) => {
          this.buildTrackerItem(tracker)
        }, (tracker: TrackerInfo) => tracker.id.toString())
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
  buildInfoSection() {
    Column({ space: 12 }) {
      Text('关于进度记录与服务器')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('本页同时管理两类能力：进度记录平台（如 MAL、AniList、Bangumi）和自托管服务器（Suwayomi、Komga）。阅读章节后，进度会同步到已连接目标。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text('注意：这里的检查是单向的，只会从本应用去查看平台内容。你在其他设备上的阅读进度不会自动同步回来。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
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
  buildSubscriptionSection() {
    Column({ space: 12 }) {
      Text('更新提醒')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('这里管理的是应用里的更新提醒，不是 RSS。它可以帮你盯住书架、远程库和支持的在线内容；你也可以从管理标签里的“更新提醒”直接进入。当前版本只会在 APP 回到前台时补查，后台不会定时执行。')
        .fontSize(13)
        .lineHeight(20)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Button('打开更新提醒')
        .height(38)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(999)
        .onClick(() => {
          this.pathStack.pushPathByName('SubscriptionManagementPage', null);
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
            Flex({
              wrap: FlexWrap.Wrap,
              justifyContent: this.responsive_isLandscape ? FlexAlign.SpaceBetween : FlexAlign.Start
            }) {
              // 进度记录列表
              Column() {
                this.buildTrackerSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'tracking_services'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'tracking_services') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'tracking_services'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'tracking_services', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'tracking_services', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'tracking_services',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })

              // 说明信息
              Column() {
                this.buildInfoSection()
              }
              .width(this.responsive_isLandscape ? '48%' : '100%')
              .padding(4)
              .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'tracking_info'
              ))
              .borderRadius(16)
              .border({
                width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'tracking_info') ? 1 : 0,
                color: SettingsSearchSupport.getHighlightOverlayBorder(
                  this.themeState.currentTheme,
                  this.activeSearchAnchorId,
                  'tracking_info'
                )
              })
              .scale({
                x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'tracking_info', this.searchHighlightPulse),
                y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'tracking_info', this.searchHighlightPulse)
              })
              .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'tracking_info',
                this.searchHighlightPulse
              ))
              .animation({ duration: 260, curve: Curve.EaseOut })
              .margin({ bottom: 16 })
            }
            .width('100%')

            Column() {
              this.buildSubscriptionSection()
            }
            .width('100%')
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'subscription_tracking'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'subscription_tracking') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(
                this.themeState.currentTheme,
                this.activeSearchAnchorId,
                'subscription_tracking'
              )
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'subscription_tracking', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'subscription_tracking', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'subscription_tracking',
              this.searchHighlightPulse
            ))
            .animation({ duration: 260, curve: Curve.EaseOut })
            .margin({ bottom: 16 })

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
          title: '进度记录与服务器',
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
      this.onReady();
    })
    .onWillShow(() => {
      this.onPageShow();
    })
    .backgroundColor(Color.Transparent)
  }
}
