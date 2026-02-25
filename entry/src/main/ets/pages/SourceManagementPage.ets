/**
 * 图源管理页面
 * 提供图源的搜索、启用/禁用、置顶、测试、删除等功能
 * 使用 HdsNavDestination 实现统一的导航体验
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
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
  isPinned?: boolean;  // 是否置顶
  isNSFW?: boolean;    // 是否为NSFW图源
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

const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct SourceManagementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  // 所有图源（内存中完整列表）
  private allSources: SourceInfo[] = [];
  // 当前显示的图源（分页加载）
  @State displayedSources: SourceInfo[] = [];
  // 筛选后的图源（用于搜索和分组筛选）
  @State filteredSourceList: SourceInfo[] = [];
  @State searchText: string = '';
  @State isLoading: boolean = false;
  @State showProxyDialog: boolean = false;
  @State proxyConfig: ProxyConfig = DEFAULT_PROXY_CONFIG;
  @State currentFilter: SourceFilterType = SourceFilterType.ALL;  // 当前筛选类型
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
      
      this.allSources = sources.map((source) => {
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
          isPinned: source.isPinned || false,
          isNSFW: source.isNSFW || false
        };
        return info;
      });
      
      this.applyFilter();
      this.updateCounts();
      
      logger.info(TAG, `✅ 加载了${this.allSources.length}个图源，置顶${this.pinnedCount}个`);
    } catch (error) {
      logger.error(TAG, '加载图源列表失败', String(error));
    } finally {
      this.isLoading = false;
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
    promptAction.showToast({
      message: message,
      duration: 2000
    });
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        Column() {
          // 标题栏占位
          Blank().height(TITLE_BAR_HEIGHT_MINI)
          
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
        
        // 代理配置对话框
        if (this.showProxyDialog) {
          ProxyConfigDialog({
            currentTheme: this.themeState.currentTheme,
            initialConfig: this.proxyConfig,
            onSave: (config: ProxyConfig) => {
              this.proxyManager.saveConfig(config);
              this.proxyConfig = config;
              this.showProxyDialog = false;
            },
            onCancel: () => {
              this.showProxyDialog = false;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
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
        title: {
          mainTitle: '图源管理'
        }
      }
    })
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
          this.showProxyDialog = true;
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
          Color.White :
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
        .borderRadius(8)
        .backgroundColor(this.currentFilter === filterType ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.currentFilter === filterType ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' :
      Color.Transparent)
    .onClick(() => {
      this.currentFilter = filterType;
      this.applyFilter();
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
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, bottom: 16 })
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
        Button(source.isPinned ? '取消置顶' : '置顶')
          .fontSize(12)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor(source.isPinned ?
            ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(async () => {
            await this.togglePinSource(source);
          })
        
        Button(source.isNSFW ? '取消NSFW' : 'NSFW')
          .fontSize(12)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor(source.isNSFW ?
            '#FF4444' :
            ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .fontColor(source.isNSFW ? Color.White :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onClick(async () => {
            await this.toggleSourceNSFW(source);
          })
        
        // Button(this.testingSourceId === source.id ? '测试中...' : '测试')
        //   .fontSize(12)
        //   .layoutWeight(1)
        //   .fontFamily(this.appFontFamily)
        //   .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        //   .enabled(this.testingSourceId === -1)
        //   .onClick(async () => {
        //     await this.testSource(source);
        //   })
        
        Button('删除')
          .fontSize(12)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .onClick(async () => {
            await this.deleteSource(source);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
  }
}
