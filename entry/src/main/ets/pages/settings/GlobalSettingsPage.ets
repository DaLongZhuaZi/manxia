// 文件路径: entry/src/main/ets/pages/settings/GlobalSettingsPage.ets
/**
 * 全局设置页面（一级页面）
 * 显示设置分组入口，点击后跳转到对应的二级设置页面
 * 支持后续添加更多一级和二级内容
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType, GlassLevel, GlassStyleToken } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport, SettingsSearchResult } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { AppGuideOverlay, GuideHighlightRect } from 'manxia_theme/src/main/ets/Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from 'manxia_core/src/main/ets/Framework/Managers/AppGuideManager';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle, SettingsPageRowVisualStyle } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageSurfaceManager';

const TAG = 'GlobalSettingsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 设置分组项接口
interface SettingsGroupItem {
  id: string;
  title: string;
  subtitle: string;
  icon: ResourceStr;
  targetPage: string;
}

@Component
export struct GlobalSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();
  @State private searchKeyword: string = '';
  @State private searchResults: SettingsSearchResult[] = [];
  @State private settingsTapEnabled: boolean = true;
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;
  private settingsTapUnlockTimer: number = -1;
  private readonly scrollTapGuardDurationMs: number = 140;
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  private lastGuideAnchorId: string = '';

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageLink('source_settings_visible') sourceSettingsVisible: boolean = false;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'GlobalSettingsPage';

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 设置分组列表 - 可扩展添加更多分组
  private settingsGroups: SettingsGroupItem[] = [
    {
      id: 'reading',
      title: '阅读设置',
      subtitle: '漫画、电子书、纯文本阅读器的默认设置',
      icon: $r('sys.symbol.book_open_fill'),
      targetPage: 'ReadingSettingsSubPage'
    },
    {
      id: 'page',
      title: '页面设置',
      subtitle: '详情页类型选择、页面显示偏好',
      icon: $r('sys.symbol.thumbnails'),
      targetPage: 'PageSettingsSubPage'
    },
    {
      id: 'shortcut',
      title: '快捷方式',
      subtitle: '桌面长按菜单快捷方式显示与选择',
      icon: $r('sys.symbol.book'),
      targetPage: 'ShortcutSettingsSubPage'
    },
    {
      id: 'main_menu',
      title: '主页面设置',
      subtitle: '主页面入口交互、底栏标签与平板顶栏布局',
      icon: $r('sys.symbol.square_grid_2x2'),
      targetPage: 'MainMenuSettingsSubPage'
    },
    {
      id: 'source_features',
      title: '源功能设置',
      subtitle: '控制图源/书源相关入口、标签、按钮与信息展示',
      icon: $r('sys.symbol.root'),
      targetPage: 'SourceFeatureSettingsSubPage'
    },
    {
      id: 'font',
      title: '字体设置',
      subtitle: '界面字体、小说字体、电子书字体',
      icon: $r('sys.symbol.textformat'),
      targetPage: 'FontSettingsSubPage'
    },
    {
      id: 'interaction',
      title: '交互设置',
      subtitle: '震动反馈、触觉体验',
      icon: $r('sys.symbol.hand_tap'),
      targetPage: 'InteractionSettingsSubPage'
    },
    {
      id: 'animation',
      title: '动画设置',
      subtitle: '书籍打开/关闭动画效果',
      icon: $r('sys.symbol.rectangle_below_line_2'),
      targetPage: 'AnimationSettingsSubPage'
    },
    {
      id: 'visual_effects',
      title: '视觉效果',
      subtitle: '查看设备材质能力，管理系统自适应与手动档位',
      icon: $r('sys.symbol.lightbulb'),
      targetPage: 'VisualEffectsSettingsSubPage'
    },
    {
      id: 'ngf_framework_status',
      title: 'NGF框架状态',
      subtitle: '查看NGF模块可检测状态、核心桥接与运行健康度',
      icon: $r('sys.symbol.device_develop'),
      targetPage: 'NGFFrameworkStatusPage'
    },
    {
      id: 'tracking',
      title: '进度记录与服务器',
      subtitle: 'MAL、AniList、Bangumi 进度同步，Suwayomi、Komga 服务器配置',
      icon: $r('sys.symbol.mobiledata_and_cloud'),
      targetPage: 'TrackingSettingsSubPage'
    },
    {
      id: 'network',
      title: '下载与网络',
      subtitle: '下载设置、网络请求配置',
      icon: $r('sys.symbol.arrow_down_circle'),
      targetPage: 'NetworkSettingsSubPage'
    },
    {
      id: 'duplicate_detection',
      title: '内容重复检测',
      subtitle: '添加内容时检测书库中的重复与相似作品',
      icon: $r('sys.symbol.list_book'),
      targetPage: 'DuplicateDetectionSettingsSubPage'
    },
    {
      id: 'notification',
      title: '通知设置',
      subtitle: '下载完成通知、更新提醒',
      icon: $r('sys.symbol.bell'),
      targetPage: 'NotificationSettingsSubPage'
    },
    {
      id: 'advanced',
      title: '高级设置',
      subtitle: '调试选项、开发者模式、SFW模式',
      icon: $r('sys.symbol.engineer_fill'),
      targetPage: 'AdvancedSettingsSubPage'
    },
    {
      id: 'error_management',
      title: '错误管理',
      subtitle: '查看捕获的错误和闪退记录、导出错误报告',
      icon: $r('sys.symbol.exclamationmark_triangle'),
      targetPage: 'ErrorManagementSubPage'
    },
    {
      id: 'backup',
      title: '数据管理',
      subtitle: '备份与恢复、数据导入导出',
      icon: $r('sys.symbol.folder'),
      targetPage: 'BackupPage'
    }
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

  onPageShow(): void {
    PageWindowCoordinator.reapplyPagePolicy('GlobalSettingsPage', this.getUIContext());
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');
      }
    } catch (err) {
      logger.error(TAG, 'AppStorage.get 异常', String(err));
    }
    void this.refreshPageGuide('onPageShow');
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
    void this.refreshPageGuide('onReady');
  }

  private lifecycle = new PageLifecycleManager('GlobalSettingsPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.cleanupSettingsTapGuard();
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化响应式布局
   */
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

  /**
   * 更新响应式布局参数
   */
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
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}`);
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_global_settings_root');
    } catch (error) {
      logger.warn(TAG, `获取全局设置引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private adjustGuideHighlightRect(anchorId: string | undefined, rect: GuideHighlightRect | null): GuideHighlightRect | null {
    return rect;
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.GLOBAL_SETTINGS);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.GLOBAL_SETTINGS) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      this.lastGuideAnchorId = '';
      return;
    }
    if (this.normalizeGuidePresentation() && !trigger.endsWith('_after_prepare')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_prepare`);
      }, 180);
      return;
    }
    if (this.alignGuideViewport(step) && !trigger.endsWith('_after_scroll')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_scroll`);
      }, 280);
      return;
    }
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.adjustGuideHighlightRect(
      step.anchorId,
      this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18)
    );
    if (!this.appGuideHighlightRect && !trigger.endsWith('_retry_layout')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_retry_layout`);
      }, 120);
      return;
    }
    logger.debug(TAG, `全局设置引导已刷新: trigger=${trigger}, step=${step.id}`);
  }

  private normalizeGuidePresentation(): boolean {
    if (this.searchKeyword.length <= 0 && this.searchResults.length <= 0) {
      return false;
    }
    this.searchKeyword = '';
    this.searchResults = [];
    return true;
  }

  private alignGuideViewport(step: AppGuideStep): boolean {
    const anchorId = step.anchorId ?? '';
    if (anchorId.length <= 0) {
      return false;
    }
    const scrollResult = ensureGuideAnchorVisibleInScroller(
      this.getUIContext(),
      this.scroller,
      anchorId,
      'guide_global_settings_scroll',
      this.getStatusBarInset() + TITLE_BAR_HEIGHT_MINI + 16,
      32,
      280
    );
    if (!scrollResult.available) {
      return false;
    }
    this.lastGuideAnchorId = anchorId;
    return scrollResult.scrolled;
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败', String(error));
    }
  }

  /**
   * 导航到二级设置页面
   */
  private navigateToSubPage(targetPage: string): void {
    try {
      logger.info(TAG, `导航到: ${targetPage}`);
      this.pathStack.pushPathByName(targetPage, null);
    } catch (error) {
      logger.error(TAG, `导航失败: ${String(error)}`);
    }
  }

  private updateSearchResults(input: string): void {
    this.searchKeyword = input;
    const query = input.trim();
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      if (query.length === 0) {
        this.searchResults = [];
        return;
      }
      this.searchResults = SettingsSearchSupport.search(query);
    });
  }

  private clearSearch(): void {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
      this.searchKeyword = '';
      this.searchResults = [];
    });
  }

  private navigateToSearchResult(result: SettingsSearchResult): void {
    if (!this.settingsTapEnabled) {
      return;
    }
    try {
      const query = this.searchKeyword.trim();
      const target = SettingsSearchSupport.createTargetFromResult(result, query);
      SettingsSearchSupport.setPendingTarget(target);
      logger.info(TAG, `设置搜索命中跳转: ${result.id} -> ${result.targetPage}, anchor=${result.anchorId}, offset=${result.scrollOffset}`);
      this.pathStack.pushPathByName(result.targetPage, null);
    } catch (error) {
      logger.error(TAG, `设置搜索跳转失败: ${String(error)}`);
    }
  }

  private isSearchMode(): boolean {
    return this.searchKeyword.trim().length > 0;
  }

  private getSettingsGroups(): SettingsGroupItem[] {
    if (this.sourceSettingsVisible) {
      return this.settingsGroups;
    }
    return this.settingsGroups.filter((item: SettingsGroupItem) =>
      item.targetPage !== 'SourceFeatureSettingsSubPage'
    );
  }

  private resolvePageLabel(pageName: string): string {
    switch (pageName) {
      case 'ReadingSettingsSubPage':
        return '阅读设置';
      case 'PageSettingsSubPage':
        return '页面设置';
      case 'ShortcutSettingsSubPage':
        return '快捷方式';
      case 'MainMenuSettingsSubPage':
        return '主页面设置';
      case 'SourceFeatureSettingsSubPage':
        return '源功能设置';
      case 'FontSettingsSubPage':
        return '字体设置';
      case 'ThemeSettingsPage':
        return '主题设置';
      case 'InteractionSettingsSubPage':
        return '交互设置';
      case 'AnimationSettingsSubPage':
        return '动画设置';
      case 'VisualEffectsSettingsSubPage':
        return '视觉效果';
      case 'NGFFrameworkStatusPage':
        return 'NGF框架状态';
      case 'TrackingSettingsSubPage':
        return '进度记录与服务器';
      case 'NetworkSettingsSubPage':
        return '下载与网络';
      case 'DuplicateDetectionSettingsSubPage':
        return '内容重复检测';
      case 'NotificationSettingsSubPage':
        return '通知设置';
      case 'AdvancedSettingsSubPage':
        return '高级设置';
      case 'ErrorManagementSubPage':
        return '错误管理';
      case 'BackupPage':
        return '数据管理';
      default:
        return pageName;
    }
  }

  private getGlassToken(level: GlassLevel = GlassLevel.CARD): GlassStyleToken {
    return this.themeManager.getGlassToken(level);
  }

  private getGlassBackground(level: GlassLevel = GlassLevel.CARD): string {
    return this.getGlassToken(level).backgroundColor;
  }

  private getGlassBlurStyle(level: GlassLevel = GlassLevel.CARD): BlurStyle {
    return this.getGlassToken(level).blurStyle;
  }

  private getGlassBlurOptions(level: GlassLevel = GlassLevel.CARD): BackgroundBlurStyleOptions {
    return this.getGlassToken(level).blurOptions;
  }

  private getGlassRadius(level: GlassLevel = GlassLevel.CARD): number {
    return this.getGlassToken(level).radius;
  }

  private getGlassBorderColor(level: GlassLevel = GlassLevel.CARD): string {
    return this.getGlassToken(level).borderColor;
  }

  private getGlassBorderWidth(level: GlassLevel = GlassLevel.CARD): number {
    return this.getGlassToken(level).borderWidth;
  }

  private getGlassShadowColor(level: GlassLevel = GlassLevel.CARD): string {
    return this.getGlassToken(level).shadowColor;
  }

  private getSettingsCardSurfaceStyle(): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface;
  }

  private getSettingsCardRowStyle(): SettingsPageRowVisualStyle {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme);
  }

  private getSettingsCardBackground(): ResourceColor {
    return this.getSettingsCardSurfaceStyle().backgroundColor;
  }

  private getSettingsCardBlurStyle(): BlurStyle | undefined {
    return this.getSettingsCardSurfaceStyle().blurStyle;
  }

  private getSettingsCardBlurOptions(): BackgroundBlurStyleOptions {
    return this.getSettingsCardSurfaceStyle().blurOptions;
  }

  private getSettingsCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return this.getSettingsCardSurfaceStyle().backgroundEffect;
  }

  private getSettingsCardRadius(): number {
    return this.getSettingsCardSurfaceStyle().radius;
  }

  private getSettingsCardBorderColor(): ResourceColor {
    return this.getSettingsCardSurfaceStyle().borderColor;
  }

  private getSettingsCardBorderWidth(): number {
    return this.getSettingsCardSurfaceStyle().borderWidth;
  }

  private getSettingsCardShadowColor(): string {
    return this.getSettingsCardSurfaceStyle().shadowColor;
  }

  private getSettingsCardTopEdgeColor(): ResourceColor {
    return this.getSettingsCardSurfaceStyle().topEdgeColor;
  }

  private getSettingsCardBottomEdgeColor(): ResourceColor {
    return this.getSettingsCardSurfaceStyle().bottomEdgeColor;
  }

  private getSettingsCardSurfaceGradient(): LinearGradient {
    return this.getSettingsCardSurfaceStyle().surfaceGradient;
  }

  private getSettingsRowIconColor(): ResourceColor {
    return this.getSettingsCardRowStyle().iconColor;
  }

  private getSettingsRowTitleColor(): ResourceColor {
    return this.getSettingsCardRowStyle().titleColor;
  }

  private getSettingsRowSubtitleColor(): ResourceColor {
    return this.getSettingsCardRowStyle().subtitleColor;
  }

  private getSettingsRowChevronColor(): ResourceColor {
    return this.getSettingsCardRowStyle().chevronColor;
  }

  private getSettingsRowChevronOpacity(): number {
    return this.getSettingsCardRowStyle().chevronOpacity;
  }

  private getStatusBarInset(): number {
    return this.statusBarHeight > 0 ? this.statusBarHeight : 24;
  }

  private getCustomHeaderRowHeight(): number {
    return TITLE_BAR_HEIGHT_MINI;
  }

  private getCustomHeaderHeight(): number {
    return this.getStatusBarInset() + this.getCustomHeaderRowHeight() + 10;
  }

  private getCustomHeaderTopPadding(): number {
    return this.getStatusBarInset() + 4;
  }

  private getCustomHeaderContentTopPadding(): number {
    return this.getCustomHeaderHeight() - 8;
  }

  private getCustomHeaderBackButtonSize(): number {
    return 40;
  }

  private getCustomHeaderBackdropColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(8, 14, 24, 0.014)'
      : 'rgba(255, 255, 255, 0.010)';
  }

  private getCustomHeaderBackdropBlurRadius(): number {
    return this.themeState.currentTheme === ThemeType.DARK ? 15 : 10;
  }

  private getCustomHeaderBackButtonFillColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? '#2D384B'
      : '#F8FBFF';
  }

  private getCustomHeaderBackButtonBorderColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(255, 255, 255, 0.16)'
      : 'rgba(188, 206, 232, 0.92)';
  }

  private getCustomHeaderBackButtonShadowColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(0, 0, 0, 0.22)'
      : 'rgba(164, 186, 220, 0.18)';
  }

  private getCustomHeaderBackButtonIconColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(248, 251, 255, 0.98)'
      : '#6E7F98';
  }

  private getCustomHeaderTitleColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(244, 248, 255, 0.96)'
      : 'rgba(24, 30, 40, 0.96)';
  }

  private getCustomHeaderReflectionOpacity(): number {
    return this.themeState.currentTheme === ThemeType.DARK ? 0.70 : 0.82;
  }

  private getCustomHeaderBackButtonEdgeHighlightGradient(): LinearGradient {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0.34)', 0],
          ['rgba(255, 255, 255, 0.10)', 0.34],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.72)', 0],
        ['rgba(255, 255, 255, 0.18)', 0.34],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  private getCustomHeaderSurfaceGradient(): LinearGradient {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(204, 230, 255, 0.050)', 0],
          ['rgba(88, 118, 158, 0.020)', 0.28],
          ['rgba(16, 24, 36, 0.006)', 0.68],
          ['rgba(12, 20, 30, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.040)', 0],
        ['rgba(240, 246, 255, 0.016)', 0.26],
        ['rgba(255, 255, 255, 0.005)', 0.62],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  private getCustomHeaderReflectionGradient(): LinearGradient {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return {
        angle: 24,
        colors: [
          ['rgba(255, 255, 255, 0)', 0],
          ['rgba(236, 245, 255, 0.032)', 0.18],
          ['rgba(255, 255, 255, 0.056)', 0.38],
          ['rgba(255, 255, 255, 0.016)', 0.58],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 24,
      colors: [
        ['rgba(255, 255, 255, 0)', 0],
        ['rgba(255, 255, 255, 0.026)', 0.18],
        ['rgba(255, 255, 255, 0.060)', 0.38],
        ['rgba(255, 255, 255, 0.015)', 0.58],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  private getCustomHeaderBackButtonHighlightGradient(): LinearGradient {
    if (this.themeState.currentTheme === ThemeType.DARK) {
      return {
        angle: 180,
        colors: [
          ['rgba(255, 255, 255, 0.16)', 0],
          ['rgba(255, 255, 255, 0.05)', 0.38],
          ['rgba(255, 255, 255, 0)', 1]
        ]
      };
    }
    return {
      angle: 180,
      colors: [
        ['rgba(255, 255, 255, 0.14)', 0],
        ['rgba(255, 255, 255, 0.03)', 0.42],
        ['rgba(255, 255, 255, 0)', 1]
      ]
    };
  }

  /* Legacy HDS title bar experiment is disabled for this page-specific custom glass header iteration.
  private getImmersiveTitleBarBackground(): ResourceColor {
    return Color.Transparent;
  }

  private getImmersiveTitleBarMaskExtraHeight(): number {
    return 0;
  }

  private getImmersiveTitleBarBlurRadius(): number {
    return this.themeState.currentTheme === ThemeType.DARK ? 42 : 36;
  }

  private getImmersiveTitleBarScrolledBackground(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(10, 18, 30, 0.26)'
      : 'rgba(255, 255, 255, 0.20)';
  }

  private getImmersiveTitleBarTitleShadowColor(): ResourceColor {
    return this.themeState.currentTheme === ThemeType.DARK
      ? 'rgba(0, 0, 0, 0.34)'
      : 'rgba(255, 255, 255, 0.40)';
  }

  private getImmersiveTopGlassHeight(): number {
    return this.getCustomHeaderHeight() + 32;
  }

  private getImmersiveTopSpacerHeight(): number {
    return this.getCustomHeaderContentTopPadding() - 8;
  }

  private getImmersiveTopGlassBackground(): string {
    return this.getGlassBackground(GlassLevel.FEATURED);
  }

  private getImmersiveTopGlassBlurStyle(): BlurStyle {
    return this.getGlassBlurStyle(GlassLevel.FEATURED);
  }

  private getImmersiveTopGlassBlurOptions(): BackgroundBlurStyleOptions {
    return this.getGlassBlurOptions(GlassLevel.FEATURED);
  }

  private getImmersiveTopGlassBackgroundEffect(): BackgroundEffectOptions | undefined {
    return this.getGlassBackgroundEffect(GlassLevel.FEATURED);
  }

  private getImmersiveTopGlassSurfaceGradient(): LinearGradient {
    return this.getCustomHeaderSurfaceGradient();
  }

  private getImmersiveTopGlassReflectionGradient(): LinearGradient {
    return this.getCustomHeaderReflectionGradient();
  }

  private getImmersiveTitleBarPadding(): PaddingOptions {
    const padding: PaddingOptions = {
      start: LengthMetrics.vp(16),
      end: LengthMetrics.vp(16)
    };
    return padding;
  }

  private getImmersiveTitleBarTitleStyle(): HdsNavigationTitleStyle {
    const titleStyle: HdsNavigationTitleStyle = {
      mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
      mainTitleShadowColor: this.getImmersiveTitleBarTitleShadowColor()
    };
    return titleStyle;
  }

  private getImmersiveTitleBarBackIconStyle(): HdsNavigationIconItemStyle {
    const backIconStyle: HdsNavigationIconItemStyle = {
      backgroundColor: this.getTitleBarIconBackground(),
      iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
    };
    return backIconStyle;
  }

  private getImmersiveTitleBarContentStyle(): HdsTitleBarContentStyle {
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: this.getImmersiveTitleBarTitleStyle(),
      backIconStyle: this.getImmersiveTitleBarBackIconStyle()
    };
    return contentStyle;
  }

  private getImmersiveTitleBarDivider(): HdsNavigationDividerParams {
    const divider: HdsNavigationDividerParams = {
      showType: DividerShowType.OFF
    };
    return divider;
  }

  private getImmersiveTitleBarBackgroundStyle(backgroundColor: ResourceColor): HdsNavigationBackgroundStyle {
    const backgroundStyle: HdsNavigationBackgroundStyle = {
      backgroundColor,
      maskExtraHeight: this.getImmersiveTitleBarMaskExtraHeight(),
      blurRadius: this.getImmersiveTitleBarBlurRadius()
    };
    return backgroundStyle;
  }

  private getImmersiveTitleBarOriginalStyle(): HdsNavigationTitleBarStyle {
    const originalStyle: HdsNavigationTitleBarStyle = {
      backgroundStyle: this.getImmersiveTitleBarBackgroundStyle(this.getImmersiveTitleBarBackground()),
      contentStyle: this.getImmersiveTitleBarContentStyle()
    };
    return originalStyle;
  }

  private getImmersiveTitleBarScrollEffectStyle(): HdsNavigationTitleBarStyle {
    const scrollEffectStyle: HdsNavigationTitleBarStyle = {
      backgroundStyle: this.getImmersiveTitleBarBackgroundStyle(this.getImmersiveTitleBarScrolledBackground()),
      contentStyle: this.getImmersiveTitleBarContentStyle()
    };
    return scrollEffectStyle;
  }

  private getImmersiveTitleBarScrollEffectOptions(): ScrollEffectOptions {
    const scrollEffectOptions: ScrollEffectOptions = {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI + 20),
      enableRefreshOffsetChange: false
    };
    return scrollEffectOptions;
  }

  private getImmersiveTitleBarStyleOptions(): TitleBarStyleOptions {
    const styleOptions: TitleBarStyleOptions = {
      scrollEffectOpts: this.getImmersiveTitleBarScrollEffectOptions(),
      originalStyle: this.getImmersiveTitleBarOriginalStyle(),
      scrollEffectStyle: this.getImmersiveTitleBarScrollEffectStyle()
    };
    return styleOptions;
  }

  private getImmersiveTitleBarContentOptions(): TitleBarContentOptions {
    const title: HdsNavigationTitle = {
      mainTitle: '全局设置'
    };
    const contentOptions: TitleBarContentOptions = {
      title,
      divider: this.getImmersiveTitleBarDivider()
    };
    return contentOptions;
  }

  private getImmersiveTitleBarOptions(): HdsNavigationTitleBarOptions {
    const titleBarOptions: HdsNavigationTitleBarOptions = {
      padding: this.getImmersiveTitleBarPadding(),
      style: this.getImmersiveTitleBarStyleOptions(),
      content: this.getImmersiveTitleBarContentOptions(),
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    };
    return titleBarOptions;
  }

  @Builder
  buildImmersiveTopGlassBridge() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getImmersiveTopGlassSurfaceGradient())

      Column()
        .width('56%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .linearGradient(this.getImmersiveTopGlassReflectionGradient())

      Column({ space: 12 }) {
        Blank().height(this.getImmersiveTopSpacerHeight())
        this.buildSearchBar()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: this.responsive_maxContentWidth })
      .padding({
        left: this.responsive_contentPadding,
        right: this.responsive_contentPadding
      })
    }
    .width('100%')
    .height(this.getImmersiveTopGlassHeight())
    .margin({ top: -this.getStatusBarInset() })
    .backgroundColor(this.getImmersiveTopGlassBackground())
    .backgroundBlurStyle(this.getImmersiveTopGlassBlurStyle(), this.getImmersiveTopGlassBlurOptions())
    .backgroundEffect(this.getImmersiveTopGlassBackgroundEffect())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .zIndex(0)
  }

  */

  @Builder
  buildCustomGlassBackButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('70%')
          .height(8)
          .position({ x: 6, y: 4 })
          .linearGradient(this.getCustomHeaderBackButtonEdgeHighlightGradient())
          .borderRadius(999)
          .opacity(this.themeState.currentTheme === ThemeType.DARK ? 0.80 : 0.92)

        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.getCustomHeaderBackButtonIconColor()])
      }
      .width('100%')
      .height('100%')
    }
    .width(this.getCustomHeaderBackButtonSize())
    .height(this.getCustomHeaderBackButtonSize())
    .backgroundColor(this.getCustomHeaderBackButtonFillColor())
    .border({
      width: 1,
      color: this.getCustomHeaderBackButtonBorderColor()
    })
    .shadow({
      radius: 16,
      color: this.getCustomHeaderBackButtonShadowColor()
    })
    .linearGradient(this.getCustomHeaderBackButtonHighlightGradient())
    .onClick(() => {
      this.goBack();
    })
  }

  @Builder
  buildCustomGlassTitleBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getCustomHeaderBackdropColor())
        .backdropBlur(this.getCustomHeaderBackdropBlurRadius())

      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getCustomHeaderSurfaceGradient())

      Column()
        .width('24%')
        .height('62%')
        .position({ x: 0, y: 0 })
        .linearGradient(this.getCustomHeaderReflectionGradient())
        .opacity(this.getCustomHeaderReflectionOpacity())

      Column() {
        Row({ space: 12 }) {
          this.buildCustomGlassBackButton()

          Text('全局设置')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getCustomHeaderTitleColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

        }
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .height(this.getCustomHeaderRowHeight())
        .constraintSize({ maxWidth: this.responsive_maxContentWidth })
        .padding({
          left: this.responsive_contentPadding,
          right: this.responsive_contentPadding
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.getCustomHeaderTopPadding() })
      .alignItems(HorizontalAlign.Center)

    }
    .width('100%')
    .height(this.getCustomHeaderHeight())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .zIndex(10)
  }

  @Builder
  buildSearchResultItem(item: SettingsSearchResult, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSettingsCardTopEdgeColor())

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSettingsCardBottomEdgeColor())

      Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSettingsRowTitleColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.resolvePageLabel(item.targetPage))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text(item.description)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getSettingsRowSubtitleColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`匹配：${item.matchedKeyword}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getSettingsRowChevronColor())
        .opacity(this.getSettingsRowChevronOpacity())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(14)
    }
    .width('100%')
    .backgroundColor(this.getSettingsCardBackground())
    .linearGradient(this.getSettingsCardSurfaceGradient())
    .backgroundBlurStyle(this.getSettingsCardBlurStyle(), this.getSettingsCardBlurOptions())
    .backgroundEffect(this.getSettingsCardBackgroundEffect())
    .borderRadius(this.getSettingsCardRadius())
    .clip(true)
    .border({ width: this.getSettingsCardBorderWidth(), color: this.getSettingsCardBorderColor() })
    .shadow({
      radius: this.getSettingsCardRadius() + 4,
      color: this.getSettingsCardShadowColor(),
      offsetX: 0,
      offsetY: 8
    })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut, delay: Math.min(index, 6) * 28 })
        .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 220, curve: Curve.EaseOut, delay: Math.min(index, 6) * 28 })),
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
    ))
    .animation({ duration: 180, curve: Curve.EaseOut })
    .onClick(() => {
      this.navigateToSearchResult(item);
    })
  }

  @Builder
  buildSearchBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSettingsCardTopEdgeColor())

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSettingsCardBottomEdgeColor())

      Column({ space: 8 }) {
      Search({ value: this.searchKeyword, placeholder: '搜索设置项（如：进度记录与服务器、翻页动画、主导航栏）' })
        .searchButton('搜索')
        .onChange((value: string) => {
          this.updateSearchResults(value);
        })
        .onSubmit(() => {
          this.updateSearchResults(this.searchKeyword);
        })

      if (this.isSearchMode()) {
        Row() {
          Text(`找到 ${this.searchResults.length} 项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSettingsRowSubtitleColor())

          Blank()

          Button('清空')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .backgroundColor(this.getGlassBackground(GlassLevel.FLOATING))
            .backgroundBlurStyle(this.getGlassBlurStyle(GlassLevel.FLOATING), this.getGlassBlurOptions(GlassLevel.FLOATING))
            .height(28)
            .padding({ left: 10, right: 10 })
            .borderRadius(this.getGlassRadius(GlassLevel.FLOATING))
            .border({ width: this.getGlassBorderWidth(GlassLevel.FLOATING), color: this.getGlassBorderColor(GlassLevel.FLOATING) })
            .onClick(() => {
              this.clearSearch();
            })
        }
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ y: -6 })))
      }
      }
      .width('100%')
      .padding(14)
    }
    .width('100%')
    .backgroundColor(this.getSettingsCardBackground())
    .linearGradient(this.getSettingsCardSurfaceGradient())
    .backgroundBlurStyle(this.getSettingsCardBlurStyle(), this.getSettingsCardBlurOptions())
    .backgroundEffect(this.getSettingsCardBackgroundEffect())
    .borderRadius(this.getSettingsCardRadius())
    .clip(true)
    .border({ width: this.getSettingsCardBorderWidth(), color: this.getSettingsCardBorderColor() })
    .shadow({
      radius: this.getSettingsCardRadius() + 4,
      color: this.getSettingsCardShadowColor(),
      offsetX: 0,
      offsetY: 8
    })
    .id('' as string)
  }

  @Builder
  buildSearchResultList() {
    Column({ space: 10 }) {
      if (this.searchResults.length === 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(1)
            .backgroundColor(this.getSettingsCardTopEdgeColor())

          Column()
            .width('100%')
            .height(1)
            .align(Alignment.Bottom)
            .backgroundColor(this.getSettingsCardBottomEdgeColor())

          Column({ space: 8 }) {
          Text('未找到匹配的设置项')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSettingsRowTitleColor())
          Text('可尝试搜索：进度记录与服务器、Suwayomi服务器、Komga服务器、翻页动画')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSettingsRowSubtitleColor())
            .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .backgroundColor(this.getSettingsCardBackground())
        .linearGradient(this.getSettingsCardSurfaceGradient())
        .backgroundBlurStyle(this.getSettingsCardBlurStyle(), this.getSettingsCardBlurOptions())
        .backgroundEffect(this.getSettingsCardBackgroundEffect())
        .borderRadius(this.getSettingsCardRadius())
        .clip(true)
        .border({ width: this.getSettingsCardBorderWidth(), color: this.getSettingsCardBorderColor() })
        .shadow({
          radius: this.getSettingsCardRadius() + 4,
          color: this.getSettingsCardShadowColor(),
          offsetX: 0,
          offsetY: 8
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ y: 10 })))
      } else {
        ForEach(this.searchResults, (item: SettingsSearchResult, index: number) => {
          this.buildSearchResultItem(item, index)
        }, (item: SettingsSearchResult) => item.id)
      }
    }
    .width('100%')
  }

  private getGuideAnchorIdForGroup(item: SettingsGroupItem): string {
    if (item.targetPage === 'ReadingSettingsSubPage') {
      return 'guide_global_settings_reading_group';
    }
    if (item.targetPage === 'BackupPage') {
      return 'guide_global_settings_backup_group';
    }
    return `guide_global_settings_group_${item.id}`;
  }

  /**
   * 构建设置分组项
   */
  @Builder
  buildSettingsGroupItem(item: SettingsGroupItem) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSettingsCardTopEdgeColor())

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSettingsCardBottomEdgeColor())

      Row() {
      // 图标
      SymbolGlyph(item.icon as Resource)
        .fontSize(24)
        .fontColor([this.getSettingsRowIconColor()])
        .margin({ right: 16 })

      // 标题和副标题
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSettingsRowTitleColor())
        Text(item.subtitle)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSettingsRowSubtitleColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([this.getSettingsRowChevronColor()])
        .opacity(this.getSettingsRowChevronOpacity())
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor(this.getSettingsCardBackground())
    .linearGradient(this.getSettingsCardSurfaceGradient())
    .backgroundBlurStyle(this.getSettingsCardBlurStyle(), this.getSettingsCardBlurOptions())
    .backgroundEffect(this.getSettingsCardBackgroundEffect())
    .borderRadius(this.getSettingsCardRadius())
    .clip(true)
    .border({ width: this.getSettingsCardBorderWidth(), color: this.getSettingsCardBorderColor() })
    .shadow({
      radius: this.getSettingsCardRadius() + 4,
      color: this.getSettingsCardShadowColor(),
      offsetX: 0,
      offsetY: 8
    })
    .onClick(() => {
      this.navigateToSubPage(item.targetPage);
    })
    .id(this.getGuideAnchorIdForGroup(item))
  }

  /**
   * 构建设置分组列表
   */
  @Builder
  buildSettingsGroupList() {
    Column({ space: 12 }) {
      ForEach(this.getSettingsGroups(), (item: SettingsGroupItem) => {
        this.buildSettingsGroupItem(item)
      })
    }
    .width('100%')
    .id('' as string)
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

        Scroll(this.scroller) {
          Column() {
            Column({ space: 16 }) {
              this.buildSearchBar()

              if (this.isSearchMode()) {
                this.buildSearchResultList()
              } else {
                if (this.responsive_isLandscape) {
                  Grid() {
                    ForEach(this.getSettingsGroups(), (item: SettingsGroupItem) => {
                      GridItem() {
                        this.buildSettingsGroupItem(item)
                      }
                    })
                  }
                  .id('' as string)
                  .columnsTemplate('1fr 1fr')
                  .columnsGap(12)
                  .rowsGap(12)
                  .width('100%')
                } else {
                  this.buildSettingsGroupList()
                }
              }

              Blank().height(40)
            }
            .enabled(this.settingsTapEnabled)
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_maxContentWidth })
            .padding({
              top: SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight),
              left: this.responsive_contentPadding,
              right: this.responsive_contentPadding,
              bottom: 40
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .id('' as string)
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .onDidScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '全局设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack
        })

        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            showSkip: this.appGuideStep.showSkip !== false,
            themeState: this.themeState,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }
      }
      .id('' as string)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
