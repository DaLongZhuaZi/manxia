// 文件路径: entry/src/main/ets/pages/settings/TrackingSettingsSubPage.ets
/**
 * 进度记录设置子页面
 * 管理第三方进度记录（MAL、AniList、Kitsu等）的登录和配置
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import {
  TrackerId,
  TrackerInfo,
  TRACKER_INFO_LIST,
  getTrackerName
} from '../../Framework/Tracking/TrackingModels';
import { getAniListTracker, AniListTracker } from '../../Framework/Tracking/trackers/AniListTracker';
import { getSuwayomiTracker, SuwayomiTracker } from '../../Framework/Tracking/trackers/SuwayomiTracker';
import { SettingsSearchSupport } from './SettingsSearchSupport';

const TAG = 'TrackingSettingsSubPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

/**
 * 进度记录登录状态
 */
interface TrackerLoginStatus {
  trackerId: TrackerId;
  isLoggedIn: boolean;
  username: string;
}

@Component
export struct TrackingSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
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

  // 跟踪器实例
  private aniListTracker: AniListTracker = getAniListTracker();
  private suwayomiTracker: SuwayomiTracker = getSuwayomiTracker();

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
    // 每次页面显示时刷新进度记录状态
    this.initializeTrackerStatus();
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

    // 初始化进度记录状态
    this.initializeTrackerStatus();
    this.applyPendingSearchTarget();
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

  private async initializeTrackerStatus(): Promise<void> {
    // 初始化跟踪器
    await this.aniListTracker.initialize();
    await this.suwayomiTracker.initialize();

    // 初始化所有进度记录的状态
    const statusList: TrackerLoginStatus[] = [];
    for (let i = 0; i < TRACKER_INFO_LIST.length; i++) {
      const info = TRACKER_INFO_LIST[i];
      let isLoggedIn = false;
      let username = '';

      // 检查各进度记录的登录状态
      if (info.id === TrackerId.ANILIST) {
        isLoggedIn = this.aniListTracker.isLoggedIn();
        username = this.aniListTracker.getAuthState().username;
      } else if (info.id === TrackerId.SUWAYOMI) {
        isLoggedIn = this.suwayomiTracker.isLoggedIn();
        username = this.suwayomiTracker.getConfig().serverUrl || '';
      }

      const status: TrackerLoginStatus = {
        trackerId: info.id,
        isLoggedIn: isLoggedIn,
        username: username
      };
      statusList.push(status);
    }
    this.trackerStatusList = statusList;
    logger.info(TAG, `初始化进度记录状态: ${this.trackerStatusList.length}个服务`);
  }

  private getTrackerStatus(trackerId: TrackerId): TrackerLoginStatus | undefined {
    return this.trackerStatusList.find(s => s.trackerId === trackerId);
  }

  /**
   * 获取可用的进度记录列表（只显示已实现的服务）
   */
  private getAvailableTrackers(): TrackerInfo[] {
    // 目前只有 AniList 和 Suwayomi 可用
    const availableIds: TrackerId[] = [TrackerId.ANILIST, TrackerId.SUWAYOMI];
    return TRACKER_INFO_LIST.filter(tracker => availableIds.includes(tracker.id));
  }

  /**
   * 检查进度记录是否可用
   */
  private isTrackerAvailable(trackerId: TrackerId): boolean {
    return trackerId === TrackerId.ANILIST || trackerId === TrackerId.SUWAYOMI;
  }

  private handleTrackerClick(tracker: TrackerInfo): void {
    const status = this.getTrackerStatus(tracker.id);
    
    // Suwayomi 总是进入设置页面（可以编辑配置或登出）
    if (tracker.id === TrackerId.SUWAYOMI) {
      this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
      return;
    }
    
    if (status && status.isLoggedIn) {
      // 已登录，显示账户管理对话框
      logger.info(TAG, `点击已登录的进度记录: ${tracker.name}`);
      this.showAccountDialog(tracker, status.username);
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
      default:
        this.showComingSoonToast(tracker.name);
        break;
    }
  }

  private showAccountDialog(tracker: TrackerInfo, username: string): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showDialog({
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
      }).then((result) => {
        if (result.index === 0) {
          this.handleLogout(tracker);
        }
      });
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
      default:
        break;
    }
    // 刷新状态
    await this.initializeTrackerStatus();
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
        message: `已从 ${tracker.name} 登出`,
        duration: 2000
      });
    });
  }

  private showComingSoonToast(serviceName: string): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
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
      default:
        return $r('app.media.icon');
    }
  }

  @Builder
  buildTrackerItem(tracker: TrackerInfo) {
    Row() {
      // 图标区域
      Image(this.getTrackerIcon(tracker.icon))
        .width(44)
        .height(44)
        .borderRadius(22)
        .objectFit(ImageFit.Cover)

      // 信息区域
      Column({ space: 4 }) {
        Text(tracker.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.getTrackerDescription(tracker.id))
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 状态指示
      if (this.getTrackerStatus(tracker.id)?.isLoggedIn) {
        Column({ space: 2 }) {
          Text(this.getTrackerStatus(tracker.id)?.username || '已登录')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.End)
        .constraintSize({ maxWidth: 100 })
      } else {
        Text('未登录')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }

      Image($r('sys.symbol.chevron_right'))
        .width(16)
        .height(16)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(10)
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
        return '自托管漫画服务器同步';
      default:
        return '进度记录';
    }
  }

  @Builder
  buildTrackerSection() {
    Column({ space: 16 }) {
      Text('进度记录')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('连接第三方服务以同步您的阅读进度。登录后，您的阅读进度将自动同步到这些平台。')
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildInfoSection() {
    Column({ space: 12 }) {
      Text('关于进度记录')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Text('进度记录允许您将阅读进度同步到第三方平台。当您阅读完一个章节时，进度会自动更新到已连接的服务。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text('注意：跟踪是单向的（本应用 → 进度记录）。在其他设备上的阅读进度不会自动同步回本应用。')
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
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
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '进度记录' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.onPageShow();
      this.onReady();
    })
    .backgroundColor(Color.Transparent)
  }
}
