// 文件路径: entry/src/main/ets/pages/settings/GlobalSettingsPage.ets
/**
 * 全局设置页面（一级页面）
 * 显示设置分组入口，点击后跳转到对应的二级设置页面
 * 支持后续添加更多一级和二级内容
 */

import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType, GlassLevel, GlassStyleToken } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsSearchSupport, SettingsSearchResult } from './SettingsSearchSupport';
import { AppGuideOverlay, GuideHighlightRect } from '../../Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../../Framework/Managers/AppGuideManager';
import { GlobalBackgroundLayerMode } from '../../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../../Framework/Components/SharedPageBackgroundLayer';

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
      icon: $r('sys.symbol.books_vertical_fill'),
      targetPage: 'ReadingSettingsSubPage'
    },
    {
      id: 'page',
      title: '页面设置',
      subtitle: '详情页类型选择、页面显示偏好',
      icon: $r('sys.symbol.rectangle_stack'),
      targetPage: 'PageSettingsSubPage'
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
      icon: $r('sys.symbol.slider_horizontal_2_square'),
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
      id: 'tracking',
      title: '进度记录',
      subtitle: 'MAL、AniList、Bangumi等进度同步',
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
    if (!rect || !anchorId) {
      return rect;
    }
    switch (anchorId) {
      case 'guide_global_settings_search':
      case 'guide_global_settings_reading_group':
      case 'guide_global_settings_backup_group':
        return {
          x: rect.x,
          y: Math.max(0, rect.y - 32),
          width: rect.width,
          height: rect.height,
          borderRadius: rect.borderRadius
        };
      default:
        return rect;
    }
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
      TITLE_BAR_HEIGHT_MINI + 16,
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
    animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      if (query.length === 0) {
        this.searchResults = [];
        return;
      }
      this.searchResults = SettingsSearchSupport.search(query);
    });
  }

  private clearSearch(): void {
    animateTo({ duration: 160, curve: Curve.EaseIn }, () => {
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
      case 'TrackingSettingsSubPage':
        return '进度记录';
      case 'NetworkSettingsSubPage':
        return '下载与网络';
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

  private getTitleBarIconBackground(): string {
    return this.getGlassToken(GlassLevel.FLOATING).backgroundColor;
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

  @Builder
  buildSearchResultItem(item: SettingsSearchResult, index: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
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
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`匹配：${item.matchedKeyword}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getGlassBackground(GlassLevel.CARD))
    .backgroundBlurStyle(this.getGlassBlurStyle(GlassLevel.CARD), this.getGlassBlurOptions(GlassLevel.CARD))
    .borderRadius(this.getGlassRadius(GlassLevel.CARD))
    .border({ width: this.getGlassBorderWidth(GlassLevel.CARD), color: this.getGlassBorderColor(GlassLevel.CARD) })
    .shadow({ radius: this.getGlassRadius(GlassLevel.CARD), color: this.getGlassShadowColor(GlassLevel.CARD) })
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
    Column({ space: 8 }) {
      Search({ value: this.searchKeyword, placeholder: '搜索设置项（如：翻页动画、主导航栏）' })
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

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
    .backgroundColor(this.getGlassBackground(GlassLevel.NAVIGATION))
    .backgroundBlurStyle(this.getGlassBlurStyle(GlassLevel.NAVIGATION), this.getGlassBlurOptions(GlassLevel.NAVIGATION))
    .borderRadius(this.getGlassRadius(GlassLevel.NAVIGATION))
    .border({ width: this.getGlassBorderWidth(GlassLevel.NAVIGATION), color: this.getGlassBorderColor(GlassLevel.NAVIGATION) })
    .shadow({ radius: this.getGlassRadius(GlassLevel.NAVIGATION), color: this.getGlassShadowColor(GlassLevel.NAVIGATION) })
    .id('guide_global_settings_search')
  }

  @Builder
  buildSearchResultList() {
    Column({ space: 10 }) {
      if (this.searchResults.length === 0) {
        Column({ space: 8 }) {
          Text('未找到匹配的设置项')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('可尝试搜索：阅读模式、翻页动画、主导航栏、备份、日志')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getGlassBackground(GlassLevel.CARD))
        .backgroundBlurStyle(this.getGlassBlurStyle(GlassLevel.CARD), this.getGlassBlurOptions(GlassLevel.CARD))
        .borderRadius(this.getGlassRadius(GlassLevel.CARD))
        .border({ width: this.getGlassBorderWidth(GlassLevel.CARD), color: this.getGlassBorderColor(GlassLevel.CARD) })
        .shadow({ radius: this.getGlassRadius(GlassLevel.CARD), color: this.getGlassShadowColor(GlassLevel.CARD) })
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
    Row() {
      // 图标
      SymbolGlyph(item.icon as Resource)
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
        .margin({ right: 16 })

      // 标题和副标题
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Text(item.subtitle)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 箭头
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getGlassBackground(GlassLevel.CARD))
    .backgroundBlurStyle(this.getGlassBlurStyle(GlassLevel.CARD), this.getGlassBlurOptions(GlassLevel.CARD))
    .borderRadius(this.getGlassRadius(GlassLevel.CARD))
    .border({ width: this.getGlassBorderWidth(GlassLevel.CARD), color: this.getGlassBorderColor(GlassLevel.CARD) })
    .shadow({ radius: this.getGlassRadius(GlassLevel.CARD), color: this.getGlassShadowColor(GlassLevel.CARD) })
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
    .id('guide_global_settings_group_list')
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
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            this.buildSearchBar()

            if (this.isSearchMode()) {
              this.buildSearchResultList()
            } else {
              if (this.responsive_isLandscape) {
                // 横屏：使用Grid布局，每行2个
                Grid() {
                  ForEach(this.getSettingsGroups(), (item: SettingsGroupItem) => {
                    GridItem() {
                      this.buildSettingsGroupItem(item)
                    }
                  })
                }
                .id('guide_global_settings_group_list')
                .columnsTemplate('1fr 1fr')
                .columnsGap(12)
                .rowsGap(12)
                .width('100%')
              } else {
                // 竖屏：列表布局
                this.buildSettingsGroupList()
              }
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
        .id('guide_global_settings_scroll')
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .onScroll((_xOffset: number, _yOffset: number) => {
          this.markSettingsScrolling();
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

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
      .id('guide_global_settings_root')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: this.getGlassBackground(GlassLevel.NAVIGATION) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: this.getTitleBarIconBackground(), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: { backgroundColor: this.getGlassBackground(GlassLevel.SHEET) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: this.getTitleBarIconBackground(), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '全局设置' }
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
