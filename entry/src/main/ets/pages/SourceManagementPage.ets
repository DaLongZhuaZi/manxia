/**
 * 图源管理页面
 * 提供图源的搜索、启用/禁用、置顶、测试、删除等功能
 * 使用 HdsNavDestination 实现统一的导航体验
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { DataManager } from '../Framework/Data/DataManager';
import { SourceRepositoryManager } from '../Framework/Source/SourceRepositoryManager';
import { ProxyManager, ProxyConfig, DEFAULT_PROXY_CONFIG } from '../Framework/Network/ProxyManager';
import { ProxyConfigDialog } from '../components/source/ProxyConfigDialog';
import { SourceManager, getSourceManager } from '../Framework/Source/SourceManager';
import { SourceTester, TestResult, TestItemResult } from '../Framework/Source/SourceTester';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { sourceDebugLogManager } from '../Framework/Debug/SourceDebugLogManager';

const TAG = 'SourceManagementPage';

// 分页加载常量
const PAGE_SIZE = 100;  // 每次加载数量
const PRELOAD_THRESHOLD = 60;  // 预加载触发阈值

/**
 * 图源信息接口
 */
interface SourceInfo {
  id: number;
  name: string;
  pkg: string;
  baseUrl: string;
  version: string;
  description: string;
  language: string;
  isEnabled: boolean;
  priority: number;
  lastUpdateTime: number;
  createTime: number;
  iconPath?: string;
  isDebugMode?: boolean;
  isPinned?: boolean;  // 是否置顶
  isNSFW?: boolean;    // 是否为NSFW图源
  requireProxy?: boolean; // 是否需要代理
}

/**
 * 图源列表筛选类型
 */
enum SourceFilterType {
  ALL = 'all',
  PINNED = 'pinned',
  DISABLED = 'disabled',
  NSFW = 'nsfw'
}

@Component
export struct SourceManagementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  // 所有图源（内存中完整列表）
  private allSources: SourceInfo[] = [];
  // 当前显示的图源（分页加载）
  @State displayedSources: SourceInfo[] = [];
  // 筛选后的图源（用于搜索和分组筛选）
  @State filteredSourceList: SourceInfo[] = [];
  @State searchText: string = '';
  @State isLoading: boolean = false;
  @State showProxyDialog: boolean = false;
  @State proxyDialogVisible: boolean = false;
  @State proxyConfig: ProxyConfig = DEFAULT_PROXY_CONFIG;
  @State currentFilter: SourceFilterType = SourceFilterType.ALL;  // 当前筛选类型
  @State filterListOpacity: number = 1;
  @State filterListOffsetY: number = 0;
  @State totalCount: number = 0;  // 图源总数
  @State pinnedCount: number = 0;  // 置顶图源数
  @State disabledCount: number = 0;  // 已关闭图源数
  @State nsfwCount: number = 0;  // NSFW图源数
  @State testingSourceId: number = -1;  // 正在测试的图源ID

  // 分页加载状态
  private currentPage: number = 0;
  private hasMoreData: boolean = true;
  private isLoadingMore: boolean = false;

  private componentId: string = `SourceManagementPage_${Date.now()}`;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  private sourceManager: SourceManager = getSourceManager();
  private dataManager: DataManager = DataManager.getInstance();
  private proxyManager: ProxyManager = ProxyManager.getInstance();
  private listScroller: Scroller = new Scroller();
  private filterSwitchToken: number = 0;
  private proxyDialogAnimationToken: number = 0;

  aboutToAppear() {
    // 初始化主题
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化代理管理器并加载配置
    this.proxyManager.initialize().then(() => {
      this.proxyConfig = this.proxyManager.getConfig();
    });
    // 注意：图源列表加载移至 onReady 回调中
  }

  private lifecycle = new PageLifecycleManager('SourceManagementPage', { enableDebug: true });

  aboutToDisappear() {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  /**
   * 加载图源列表
   */
  private async loadSourceList(): Promise<void> {
    try {
      this.isLoading = true;

      // 使用 SourceManager 加载图源（包含置顶状态）
      const sources = await this.sourceManager.getAllSourcesSortedByPinned();
      const repoManager = SourceRepositoryManager.getInstance();

      const mappedSources: SourceInfo[] = sources.map((source) => {
        const pkg = source.pkg || '';
        // 尝试获取图源图标路径
        let iconPath: string | undefined = source.iconPath;
        if (!iconPath && pkg) {
          const iconFile = repoManager.getSourceIconPath(pkg);
          if (iconFile) {
            iconPath = iconFile;
          }
        }

        const info: SourceInfo = {
          id: source.id,
          name: source.name,
          pkg: pkg,
          baseUrl: source.baseUrl,
          version: source.version,
          description: source.description || '',
          language: source.language || 'zh-CN',
          isEnabled: source.isEnabled,
          priority: source.priority || 0,
          lastUpdateTime: source.lastUpdateTime || 0,
          createTime: source.createTime,
          iconPath: iconPath,
          isDebugMode: false,
          isPinned: source.isPinned || false,
          isNSFW: source.isNSFW || false,
          requireProxy: source.requireProxy || false
        };
        return info;
      });
      await this.loadSourceDebugModes(mappedSources);
      this.allSources = mappedSources;

      this.applyFilter();
      this.updateCounts();

      logger.info(TAG, `✅ 加载了${this.allSources.length}个图源，置顶${this.pinnedCount}个`);
    } catch (error) {
      logger.error(TAG, '加载图源列表失败', String(error));
    } finally {
      this.isLoading = false;
    }
  }

  private async loadSourceDebugModes(sources: SourceInfo[]): Promise<void> {
    const tasks: Promise<void>[] = [];
    for (let i = 0; i < sources.length; i++) {
      tasks.push(this.loadSourceDebugModeForItem(sources[i]));
    }
    await Promise.all(tasks);
  }

  private async loadSourceDebugModeForItem(source: SourceInfo): Promise<void> {
    try {
      source.isDebugMode = await sourceDebugLogManager.isDebugModeEnabled(source.id);
    } catch (error) {
      source.isDebugMode = false;
      logger.warn(TAG, `加载图源调试模式失败: ${source.name}`, String(error));
    }
  }

  /**
   * 应用筛选
   */
  private applyFilter(): void {
    let filtered = [...this.allSources];

    // 应用类型筛选
    if (this.currentFilter === SourceFilterType.PINNED) {
      filtered = filtered.filter((s: SourceInfo) => s.isPinned);
    } else if (this.currentFilter === SourceFilterType.DISABLED) {
      filtered = filtered.filter((s: SourceInfo) => !s.isEnabled);
    } else if (this.currentFilter === SourceFilterType.NSFW) {
      filtered = filtered.filter((s: SourceInfo) => s.isNSFW);
    }

    // 应用搜索筛选
    if (this.searchText.trim()) {
      const lowerKeyword = this.searchText.toLowerCase();
      filtered = filtered.filter((source: SourceInfo) => {
        return source.name.toLowerCase().includes(lowerKeyword) ||
               source.baseUrl.toLowerCase().includes(lowerKeyword) ||
               source.description.toLowerCase().includes(lowerKeyword);
      });
    }

    this.filteredSourceList = filtered;
    // 重置分页状态
    this.currentPage = 0;
    this.hasMoreData = true;
    // 加载第一页
    this.loadMoreSources(true);
  }

  private switchFilterWithAnimation(filterType: SourceFilterType): void {
    if (this.currentFilter === filterType) {
      return;
    }
    this.filterSwitchToken += 1;
    const switchToken: number = this.filterSwitchToken;
    this.filterListOpacity = 0;
    this.filterListOffsetY = 10;
    setTimeout(() => {
      if (this.filterSwitchToken !== switchToken) {
        return;
      }
      this.currentFilter = filterType;
      this.applyFilter();
      this.filterListOpacity = 1;
      this.filterListOffsetY = 0;
    }, 110);
  }

  private openProxyDialog(): void {
    this.proxyDialogAnimationToken += 1;
    const animationToken: number = this.proxyDialogAnimationToken;
    this.showProxyDialog = true;
    this.proxyDialogVisible = false;
    setTimeout(() => {
      if (this.proxyDialogAnimationToken !== animationToken || !this.showProxyDialog) {
        return;
      }
      this.proxyDialogVisible = true;
    }, 0);
  }

  private closeProxyDialog(): void {
    if (!this.showProxyDialog) {
      return;
    }
    this.proxyDialogAnimationToken += 1;
    const animationToken: number = this.proxyDialogAnimationToken;
    this.proxyDialogVisible = false;
    setTimeout(() => {
      if (this.proxyDialogAnimationToken !== animationToken) {
        return;
      }
      if (!this.proxyDialogVisible) {
        this.showProxyDialog = false;
      }
    }, 220);
  }

  /**
   * 加载更多图源（分页）
   * @param reset 是否重置列表
   */
  private loadMoreSources(reset: boolean = false): void {
    if (this.isLoadingMore && !reset) return;
    if (!this.hasMoreData && !reset) return;

    this.isLoadingMore = true;

    const startIndex = reset ? 0 : this.currentPage * PAGE_SIZE;
    const endIndex = startIndex + PAGE_SIZE;
    const newSources = this.filteredSourceList.slice(startIndex, endIndex);

    if (reset) {
      this.displayedSources = newSources;
      this.currentPage = 1;
    } else {
      // 追加新数据
      for (const source of newSources) {
        this.displayedSources.push(source);
      }
      this.currentPage++;
    }

    this.hasMoreData = endIndex < this.filteredSourceList.length;
    this.isLoadingMore = false;

    logger.debug(TAG, `加载图源: 显示${this.displayedSources.length}/${this.filteredSourceList.length}`);
  }

  /**
   * 检查是否需要预加载
   */
  private checkPreload(index: number): void {
    const threshold = (this.currentPage - 1) * PAGE_SIZE + PRELOAD_THRESHOLD;
    if (index >= threshold && this.hasMoreData && !this.isLoadingMore) {
      logger.debug(TAG, `触发预加载: index=${index}, threshold=${threshold}`);
      this.loadMoreSources();
    }
  }

  /**
   * 更新统计数据
   */
  private updateCounts(): void {
    this.totalCount = this.allSources.length;
    this.pinnedCount = this.allSources.filter((s: SourceInfo) => s.isPinned).length;
    this.disabledCount = this.allSources.filter((s: SourceInfo) => !s.isEnabled).length;
    this.nsfwCount = this.allSources.filter((s: SourceInfo) => s.isNSFW).length;
  }

  /**
   * 搜索图源
   */
  private searchSources(keyword: string): void {
    this.searchText = keyword;
    this.applyFilter();
    logger.debug(TAG, `搜索"${keyword}"，找到${this.filteredSourceList.length}个结果`);
  }

  /**
   * 切换NSFW状态
   */
  private async toggleSourceNSFW(source: SourceInfo): Promise<void> {
    try {
      const newNSFWState = !source.isNSFW;
      await this.dataManager.updateSourceNSFW(source.id, newNSFWState);

      // 更新本地状态
      source.isNSFW = newNSFWState;

      // 重新应用筛选
      this.applyFilter();
      this.updateCounts();

      logger.info(TAG, `图源"${source.name}"已${newNSFWState ? '标记' : '取消'}NSFW`);
      this.showToast(`图源"${source.name}"已${newNSFWState ? '标记为NSFW' : '取消NSFW标记'}`);
    } catch (error) {
      logger.error(TAG, `切换NSFW状态失败: ${source.name}`, String(error));
      this.showToast('操作失败');
    }
  }

  /**
   * 切换置顶状态
   */
  private async togglePinSource(source: SourceInfo): Promise<void> {
    try {
      const newPinnedState = await this.sourceManager.togglePinSource(source.id);

      // 更新本地状态
      source.isPinned = newPinnedState;

      // 重新排序并应用筛选
      this.allSources = this.sortSourcesByPinned(this.allSources);
      this.applyFilter();
      this.updateCounts();

      logger.info(TAG, `图源"${source.name}"已${newPinnedState ? '置顶' : '取消置顶'}`);
    } catch (error) {
      logger.error(TAG, `切换置顶状态失败: ${source.name}`, String(error));
    }
  }

  /**
   * 按置顶状态排序
   */
  private async toggleSourceDebugMode(source: SourceInfo): Promise<void> {
    try {
      const newDebugMode = !(source.isDebugMode === true);
      await sourceDebugLogManager.setDebugModeEnabled(source.id, newDebugMode);
      source.isDebugMode = newDebugMode;
      if (!newDebugMode) {
        sourceDebugLogManager.clearDetailEntry(source.id);
      }

      logger.info(TAG, `图源"${source.name}"调试模式已${newDebugMode ? '开启' : '关闭'}`);
      this.showToast(`图源"${source.name}"调试模式已${newDebugMode ? '开启' : '关闭'}`);
    } catch (error) {
      logger.error(TAG, `切换图源调试模式失败: ${source.name}`, String(error));
      this.showToast('调试模式切换失败');
    }
  }

  private sortSourcesByPinned(sources: SourceInfo[]): SourceInfo[] {
    const pinned = sources.filter(s => s.isPinned);
    const unpinned = sources.filter(s => !s.isPinned);
    return [...pinned, ...unpinned];
  }

  /**
   * 切换图源启用状态
   */
  private async toggleSourceEnabled(source: SourceInfo): Promise<void> {
    try {
      const newState = !source.isEnabled;
      await this.dataManager.updateComicSource(source.id, { isEnabled: newState });

      // 更新本地状态
      source.isEnabled = newState;

      logger.info(TAG, `图源"${source.name}"已${newState ? '启用' : '禁用'}`);
    } catch (error) {
      logger.error(TAG, `切换图源状态失败: ${source.name}`, String(error));
    }
  }

  /**
   * 删除图源
   */
  private async deleteSource(source: SourceInfo): Promise<void> {
    try {
      // 删除图源文件
      if (source.pkg) {
        try {
          const repoManager = SourceRepositoryManager.getInstance();
          repoManager.deleteSourceFiles(source.pkg);
        } catch (e) {
          logger.warn(TAG, `删除图源文件失败: ${e}`);
        }
      }

      // 【关键】清理WebView引擎缓存（必须在删除数据库记录之前）
      try {
        this.webViewSourceManager.removeSource(String(source.id), source.name);
        this.webViewSourceManager.removeEngineByName(source.name);
        logger.info(TAG, `WebView引擎缓存已清理: ${source.id} (${source.name})`);
      } catch (e) {
        logger.warn(TAG, `清理WebView引擎缓存失败: ${e}`);
      }

      // 如果是置顶图源，从置顶列表中移除
      if (source.isPinned) {
        await this.sourceManager.unpinSource(source.id);
      }

      await this.dataManager.deleteComicSource(source.id);

      // 从列表中移除
      const index = this.allSources.findIndex((s: SourceInfo) => s.id === source.id);
      if (index !== -1) {
        this.allSources.splice(index, 1);
      }

      this.applyFilter();
      this.updateCounts();

      logger.info(TAG, `图源"${source.name}"已删除`);
      this.showToast(`图源"${source.name}"已删除`);
    } catch (error) {
      logger.error(TAG, `删除图源失败: ${source.name}`, String(error));
      this.showToast('删除图源失败');
    }
  }

  /**
   * 测试图源
   */
  private async testSource(source: SourceInfo): Promise<void> {
    try {
      this.testingSourceId = source.id;
      this.showToast(`正在测试图源: ${source.name}...`);
      logger.info(TAG, `开始测试图源: ${source.name}`);

      const tester = new SourceTester();
      const result: TestResult = await tester.testSource(source.id, source.name);

      if (result.success) {
        this.showToast(`✅ ${source.name} 测试成功\n通过: ${result.passedTests}/${result.totalTests}, 耗时: ${result.duration}ms`);
        logger.info(TAG, `图源测试成功: ${source.name}, 通过: ${result.passedTests}/${result.totalTests}, 耗时: ${result.duration}ms`);
      } else {
        const failedTest = result.tests.find((t: TestItemResult) => !t.success);
        const errorMsg = failedTest?.error || '未知错误';
        this.showToast(`❌ ${source.name} 测试失败\n${errorMsg}`);
        logger.error(TAG, `图源测试失败: ${source.name}, 错误: ${errorMsg}`);
      }
    } catch (error) {
      this.showToast(`测试异常: ${String(error)}`);
      logger.error(TAG, `图源测试异常: ${source.name}`, String(error));
    } finally {
      this.testingSourceId = -1;
    }
  }

  /**
   * 显示提示
   */
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 2000
    });
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

          // 搜索栏
          this.buildSearchBar()

          // 图源列表
          if (this.isLoading) {
            this.buildLoadingView()
          } else if (this.filteredSourceList.length === 0) {
            this.buildEmptyView()
          } else {
            this.buildSourceList()
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 代理配置对话框
        if (this.showProxyDialog) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(14, 20, 31, 0.24)')
              .opacity(this.proxyDialogVisible ? 1 : 0)
              .animation({ duration: 180, curve: Curve.EaseOut })
              .onClick(() => {
                this.closeProxyDialog();
              })

            ProxyConfigDialog({
              currentTheme: this.themeState.currentTheme,
              appFontFamily: this.appFontFamily,
              initialConfig: this.proxyConfig,
              sourceList: this.allSources,
              onSourceProxyChange: async (sourceId: number, requireProxy: boolean): Promise<void> => {
                await this.sourceManager.updateSourceProxySetting(sourceId, requireProxy);
                for (let i = 0; i < this.allSources.length; i++) {
                  if (this.allSources[i].id === sourceId) {
                    this.allSources[i].requireProxy = requireProxy;
                    break;
                  }
                }
                this.applyFilter();
              },
              onSave: (config: ProxyConfig) => {
                void this.proxyManager.saveConfig(config);
                this.proxyConfig = config;
                this.closeProxyDialog();
              },
              onCancel: () => {
                this.closeProxyDialog();
              }
            })
              .opacity(this.proxyDialogVisible ? 1 : 0)
              .scale({
                x: this.proxyDialogVisible ? 1 : 0.95,
                y: this.proxyDialogVisible ? 1 : 0.95
              })
              .animation({ duration: 220, curve: Curve.EaseOut })
              .onClick(() => {
              })
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .zIndex(3000)
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '图源管理',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.loadSourceList();
    })
  }

  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    Column({ space: 12 }) {
      // 搜索框
      Row({ space: 8 }) {
        Search({ placeholder: '搜索图源名称、URL或描述' })
          .searchButton('搜索')
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchSources(value);
          })

        // 代理按钮
        Button() {
          SymbolGlyph($r('sys.symbol.satellite'))
            .fontSize(20)
            .fontColor([this.proxyConfig.enabled ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(40)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(8)
        .onClick(() => {
          this.openProxyDialog();
        })
      }
      .width('100%')

      // 筛选Tab
      Row({ space: 4 }) {
        this.buildFilterTab('全部', SourceFilterType.ALL)
        this.buildFilterTab('已置顶', SourceFilterType.PINNED)
        this.buildFilterTab('已关闭', SourceFilterType.DISABLED)
        this.buildFilterTab('NSFW', SourceFilterType.NSFW)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
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

  /**
   * 构建筛选Tab
   */
  @Builder
  buildFilterTab(label: string, filterType: SourceFilterType) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentFilter === filterType ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

      Text(`${this.getFilterCount(filterType)}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentFilter === filterType ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .linearGradient(this.currentFilter === filterType ? {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '26', 0],
            [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '30', 1]
          ]
        } : {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 0],
            [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 1]
          ]
        })
        .border({
          width: this.currentFilter === filterType ? 1.2 : 1,
          color: this.currentFilter === filterType ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '99' :
            ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
        })
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .linearGradient(this.currentFilter === filterType ? {
      angle: 130,
      colors: [
        [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '2B', 0],
        [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 0.45],
        [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '33', 1]
      ]
    } : {
      angle: 130,
      colors: [
        [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 0],
        [ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme), 1]
      ]
    })
    .border({
      width: this.currentFilter === filterType ? 1.4 : 1,
      color: this.currentFilter === filterType ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + 'B3' :
        ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
    })
    .shadow({
      radius: this.currentFilter === filterType ? 9 : 0,
      color: this.currentFilter === filterType ?
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '33' :
        Color.Transparent,
      offsetX: 0,
      offsetY: 0
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
    .onClick(() => {
      this.switchFilterWithAnimation(filterType);
    })
  }

  /**
   * 获取筛选类型对应的数量
   */
  private getFilterCount(filterType: SourceFilterType): number {
    switch (filterType) {
      case SourceFilterType.ALL:
        return this.totalCount;
      case SourceFilterType.PINNED:
        return this.pinnedCount;
      case SourceFilterType.DISABLED:
        return this.disabledCount;
      case SourceFilterType.NSFW:
        return this.nsfwCount;
      default:
        return 0;
    }
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 构建空状态视图
   */
  @Builder
  buildEmptyView() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_source_normal'))
        .width(80)
        .height(80)
        .opacity(0.3)

      Text(this.getEmptyViewText())
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 获取空状态提示文本
   */
  private getEmptyViewText(): string {
    if (this.searchText) {
      return '未找到匹配的图源';
    }
    switch (this.currentFilter) {
      case SourceFilterType.PINNED:
        return '暂无置顶图源';
      case SourceFilterType.DISABLED:
        return '暂无已关闭的图源';
      case SourceFilterType.NSFW:
        return '暂无NSFW图源';
      default:
        return '暂无图源\n请通过主页面的"图源导入"导入图源';
    }
  }

  /**
   * 构建图源列表
   */
  @Builder
  buildSourceList() {
    List({ scroller: this.listScroller }) {
      ForEach(this.displayedSources, (source: SourceInfo, index: number) => {
        ListItem() {
          this.buildSourceCard(source)
        }
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 180, curve: Curve.EaseOut }))
        )
      }, (source: SourceInfo) => String(source.id))

      // 加载更多指示器
      if (this.hasMoreData) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text(`加载中... (${this.displayedSources.length}/${this.filteredSourceList.length})`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
        }
      }

      ListItem() {
        Row()
          .width('100%')
          .height(24 + this.navigationBarHeight)
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, bottom: 8 })
    .opacity(this.filterListOpacity)
    .translate({ y: this.filterListOffsetY })
    .animation({ duration: 220, curve: Curve.EaseOut })
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .onScrollIndex((start: number, end: number) => {
      // 检查是否需要预加载
      this.checkPreload(end);
    })
  }

  /**
   * 构建图源卡片
   */
  @Builder
  buildSourceCard(source: SourceInfo) {
    Column({ space: 12 }) {
      // 标题行
      Row({ space: 12 }) {
        // 图源图标
        Stack() {
          if (source.iconPath) {
            Image('file://' + source.iconPath)
              .width(48)
              .height(48)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          } else {
            // 默认图标
            Column() {
              Text(source.name.charAt(0).toUpperCase())
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            }
            .width(48)
            .height(48)
            .borderRadius(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }

          // 置顶标记
          if (source.isPinned) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              .position({ x: -4, y: -4 })
          }
        }
        .width(48)
        .height(48)

        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(source.name)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            if (source.isPinned) {
              Text('已置顶')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20')
            }

            if (source.isNSFW) {
              Text('NSFW')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor('#FF4444')
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor('#FF444420')
            }

            if (source.isDebugMode) {
              Text('调试')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20')
            }
          }

          Text(source.baseUrl)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: source.isEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            await this.toggleSourceEnabled(source);
          })
      }
      .width('100%')

      // 描述
      if (source.description) {
        Text(source.description)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 信息行
      Row({ space: 16 }) {
        Text(`版本: ${source.version}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

        Text(`语言: ${source.language}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

        Text(`优先级: ${source.priority}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      // 操作按钮
      Row({ space: 8 }) {
        Button() {
          SymbolGlyph(source.isPinned ? $r('sys.symbol.pin_fill') : $r('sys.symbol.pin'))
            .fontSize(16)
            .fontColor([source.isPinned ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + 'B8'])
        }
        .layoutWeight(1)
        .height(34)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .linearGradient(source.isPinned ? {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '30', 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '3B', 1]
          ]
        } : {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 1]
          ]
        })
        .border({
          width: source.isPinned ? 1.4 : 1,
          color: source.isPinned ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + 'C2' :
            ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
        })
        .shadow({
          radius: source.isPinned ? 8 : 0,
          color: source.isPinned ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '30' :
            Color.Transparent,
          offsetX: 0,
          offsetY: 0
        })
        .onClick(() => {
          void this.togglePinSource(source);
        })

        Button() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(16)
            .fontColor([source.isNSFW ?
              ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + 'B8'])
        }
        .layoutWeight(1)
        .height(34)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .linearGradient(source.isNSFW ? {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '30', 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '3B', 1]
          ]
        } : {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 1]
          ]
        })
        .border({
          width: source.isNSFW ? 1.4 : 1,
          color: source.isNSFW ?
            ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + 'C2' :
            ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
        })
        .shadow({
          radius: source.isNSFW ? 8 : 0,
          color: source.isNSFW ?
            ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '2E' :
            Color.Transparent,
          offsetX: 0,
          offsetY: 0
        })
        .onClick(() => {
          void this.toggleSourceNSFW(source);
        })

        Button() {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(16)
            .fontColor([source.isDebugMode ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + 'B8'])
        }
        .layoutWeight(1)
        .height(34)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .linearGradient(source.isDebugMode ? {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '30', 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '3B', 1]
          ]
        } : {
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 1]
          ]
        })
        .border({
          width: source.isDebugMode ? 1.4 : 1,
          color: source.isDebugMode ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + 'C2' :
            ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
        })
        .shadow({
          radius: source.isDebugMode ? 8 : 0,
          color: source.isDebugMode ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '2E' :
            Color.Transparent,
          offsetX: 0,
          offsetY: 0
        })
        .onClick(() => {
          void this.toggleSourceDebugMode(source);
        })

        Button() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)])
        }
        .layoutWeight(1)
        .height(34)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .linearGradient({
          angle: 130,
          colors: [
            [ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '26', 0],
            [ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme), 0.5],
            [ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '33', 1]
          ]
        })
        .border({
          width: 1.4,
          color: ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + 'B8'
        })
        .shadow({
          radius: 8,
          color: ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme) + '2E',
          offsetX: 0,
          offsetY: 0
        })
        .onClick(() => {
          void this.deleteSource(source);
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
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
}
