/**
 * 全局搜索页面
 * 搜索所有内容（本地+在线漫画、电子书、小说）
 */
import { ComicInfo } from '../Framework/Data/DataManager';
import { EBook } from '../Models/EBookModels';
import { NovelBook, NovelSearchResult, NovelSourceInfo } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { NovelDetailPageParams } from './NovelBookshelfPage';
import {
  GlobalSearchService,
  getGlobalSearchService,
  SearchContentType,
  SearchSourceType,
  OnlineSourceType,
  UnifiedSearchItem,
  SearchSourceGroup,
  SearchFilterConfig
} from '../Framework/Services/GlobalSearchService';
import { SourceInfo } from '../Framework/Source/SourceManager';
import { PageSettingsHelper, DetailPageType, SceneType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { webview } from '@kit.ArkWeb';
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';

const TAG = 'GlobalSearchPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;
const SEARCH_PREFS_NAME = 'global_search_preferences';

// 源选择列表分页常量
const SOURCE_DISPLAY_LIMIT = 20;  // 默认显示数量
const SOURCE_DISPLAY_STEP = 50;   // 每次加载更多的数量

// 搜索偏好持久化接口
interface SearchPreferences {
  contentType: string;
  sourceType: string;
  selectedMangaSources: string[];
  selectedNovelSources: string[];
  enableSuwayomi: boolean;
  showSourceExpanded: boolean;  // 是否展开源选择器
}

// 导航参数接口
interface MangaDetailNavParam {
  mangaId: string;
}

interface EBookDetailNavParam {
  bookId: string;
}

interface OnlineMangaDetailNavParam {
  sourceId: number;
  comicId: string;
  comicTitle?: string;
}

interface SuwayomiDetailNavParam {
  mangaId: string;
}

// 全局搜索页面参数接口
export interface GlobalSearchPageParams {
  initialKeyword?: string;  // 初始搜索关键词
  initialContentType?: string;    // 初始内容类型筛选 ('manga' | 'novel' | 'ebook' | 'all')
  initialSourceType?: string;     // 初始来源类型筛选 ('local' | 'online' | 'all')
  autoSelectAllSources?: boolean; // 是否自动选中该类型的所有已开启源
}


@Component
export struct GlobalSearchPage {
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'GlobalSearchPage';
  
  // 搜索相关
  @State searchKeyword: string = '';
  @State isSearching: boolean = false;
  @State searchProgress: string = '';
  
  // 筛选配置
  @State contentTypeFilter: SearchContentType = SearchContentType.ALL;
  @State sourceTypeFilter: SearchSourceType = SearchSourceType.LOCAL;
  @State selectedMangaSources: string[] = [];
  @State selectedNovelSources: string[] = [];
  @State enableSuwayomi: boolean = false;
  @State maxConcurrent: number = 5;
  
  // 可用源列表
  @State availableMangaSources: SourceInfo[] = [];
  @State availableNovelSources: NovelSourceInfo[] = [];
  @State isSuwayomiAvailable: boolean = false;
  
  // 结果相关
  @State sourceGroups: SearchSourceGroup[] = [];
  @State filteredGroups: SearchSourceGroup[] = [];  // 缓存筛选结果
  
  // 历史记录
  @State searchHistory: string[] = [];
  
  // UI 状态
  @State showSourceExpanded: boolean = false;  // 源选择区域是否展开
  @State expandedGroups: Set<string> = new Set<string>();  // 已展开显示所有结果的分组ID
  @State mangaSourceDisplayCount: number = SOURCE_DISPLAY_LIMIT;  // 当前显示的漫画图源数量
  @State novelSourceDisplayCount: number = SOURCE_DISPLAY_LIMIT;  // 当前显示的小说书源数量
  
  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  @State responsive_gridColumns: number = 5;
  
  // 服务
  private searchService: GlobalSearchService = getGlobalSearchService();
  private pathStack: NavPathStack = new NavPathStack();
  private lastProgressUpdate: number = 0;  // 上次进度更新时间戳
  
  // WebView 相关（用于后台搜索 WebView 格式图源）
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
  @State webViewReady: boolean = false;
  
  // 页面参数
  @State pageParams: GlobalSearchPageParams | null = null;

  aboutToAppear(): void {
    this.initThemeAware();
    this.initFontAware();
    this.loadSearchHistory();
    this.initResponsiveLayout();
    this.loadSearchPreferences();
    this.loadAvailableSources();
    this.initWebView();
  }
  
  /**
   * 初始化 WebView（用于后台搜索 WebView 格式图源）
   */
  private initWebView(): void {
    // WebView 控制器将在组件附加时设置为全局控制器
    logger.info(TAG, '初始化 WebView 用于全局搜索');
  }
  
  /**
   * 等待 WebView 就绪
   * 【关键】图源搜索需要 WebView 控制器，必须等待其附加完成
   */
  private async waitForWebViewReady(): Promise<void> {
    // 如果已经就绪，直接返回
    if (this.webViewReady) {
      logger.debug(TAG, 'WebView 已就绪');
      return;
    }
    
    // 等待 WebView 附加，最多等待 5 秒
    const maxWaitTime = 5000;
    const checkInterval = 100;
    let waitedTime = 0;
    
    logger.info(TAG, '等待 WebView 就绪...');
    
    while (!this.webViewReady && waitedTime < maxWaitTime) {
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      waitedTime += checkInterval;
    }
    
    if (this.webViewReady) {
      logger.info(TAG, `WebView 已就绪，等待了 ${waitedTime}ms`);
    } else {
      logger.warn(TAG, `WebView 等待超时 (${maxWaitTime}ms)，图源搜索可能失败`);
    }
  }
  
  /**
   * 加载搜索偏好设置
   */
  private async loadSearchPreferences(): Promise<void> {
    try {
      const context = getContext(this);
      const store = await preferences.getPreferences(context, SEARCH_PREFS_NAME);
      
      const contentType = await store.get('contentType', SearchContentType.ALL) as string;
      const sourceType = await store.get('sourceType', SearchSourceType.LOCAL) as string;
      const mangaSources = await store.get('selectedMangaSources', '[]') as string;
      const novelSources = await store.get('selectedNovelSources', '[]') as string;
      const suwayomi = await store.get('enableSuwayomi', false) as boolean;
      const expanded = await store.get('showSourceExpanded', false) as boolean;
      
      this.contentTypeFilter = contentType as SearchContentType;
      this.sourceTypeFilter = sourceType as SearchSourceType;
      this.selectedMangaSources = JSON.parse(mangaSources) as string[];
      this.selectedNovelSources = JSON.parse(novelSources) as string[];
      this.enableSuwayomi = suwayomi;
      this.showSourceExpanded = expanded;
      
      logger.info(TAG, `加载搜索偏好: 内容=${contentType}, 来源=${sourceType}`);
    } catch (error) {
      logger.warn(TAG, `加载搜索偏好失败: ${error}`);
    }
  }

  /**
   * 保存搜索偏好设置
   */
  private async saveSearchPreferences(): Promise<void> {
    try {
      const context = getContext(this);
      const store = await preferences.getPreferences(context, SEARCH_PREFS_NAME);
      
      await store.put('contentType', this.contentTypeFilter);
      await store.put('sourceType', this.sourceTypeFilter);
      await store.put('selectedMangaSources', JSON.stringify(this.selectedMangaSources));
      await store.put('selectedNovelSources', JSON.stringify(this.selectedNovelSources));
      await store.put('enableSuwayomi', this.enableSuwayomi);
      await store.put('showSourceExpanded', this.showSourceExpanded);
      
      await store.flush();
      logger.debug(TAG, '搜索偏好已保存');
    } catch (error) {
      logger.warn(TAG, `保存搜索偏好失败: ${error}`);
    }
  }

  /**
   * 加载可用的在线源
   */
  private async loadAvailableSources(): Promise<void> {
    try {
      // 加载漫画图源
      this.availableMangaSources = await this.searchService.getAvailableMangaSources();
      logger.info(TAG, `加载了 ${this.availableMangaSources.length} 个漫画图源`);
      
      // 加载小说书源
      this.availableNovelSources = this.searchService.getAvailableNovelSources();
      logger.info(TAG, `加载了 ${this.availableNovelSources.length} 个小说书源`);
      
      // 检查 Suwayomi 是否可用
      this.isSuwayomiAvailable = this.searchService.isSuwayomiConfigured();
      logger.info(TAG, `Suwayomi 可用: ${this.isSuwayomiAvailable}`);
    } catch (error) {
      logger.error(TAG, `加载可用源失败: ${error}`);
    }
  }
  
  /**
   * 处理页面参数，如果有初始关键词则自动搜索
   * 支持预设筛选配置（从详情页快捷搜索跳转时使用）
   */
  private async handlePageParams(): Promise<void> {
    if (this.pageParams?.initialKeyword) {
      this.searchKeyword = this.pageParams.initialKeyword;
      
      // 应用初始筛选配置（如果提供）
      if (this.pageParams.initialContentType) {
        this.contentTypeFilter = this.pageParams.initialContentType as SearchContentType;
      }
      if (this.pageParams.initialSourceType) {
        this.sourceTypeFilter = this.pageParams.initialSourceType as SearchSourceType;
      }
      
      // 自动选中所有已开启的源
      if (this.pageParams.autoSelectAllSources) {
        // 确保源列表已加载
        await this.loadAvailableSources();
        this.autoSelectSourcesForContentType();
      }
      
      logger.info(TAG, `收到初始搜索关键词: ${this.searchKeyword}, contentType=${this.contentTypeFilter}, sourceType=${this.sourceTypeFilter}`);
      this.performSearch();
    }
  }
  
  /**
   * 根据当前内容类型自动选中所有已开启的源
   * 用于从详情页快捷搜索跳转时，自动选中对应类型的所有源
   */
  private autoSelectSourcesForContentType(): void {
    if (this.contentTypeFilter === SearchContentType.MANGA || this.contentTypeFilter === SearchContentType.ALL) {
      // 选中所有已开启的漫画图源（已按置顶排序）
      this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
      logger.info(TAG, `自动选中 ${this.selectedMangaSources.length} 个漫画图源`);
    }
    if (this.contentTypeFilter === SearchContentType.NOVEL || this.contentTypeFilter === SearchContentType.ALL) {
      // 选中所有已开启的小说书源
      this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
      logger.info(TAG, `自动选中 ${this.selectedNovelSources.length} 个小说书源`);
    }
  }

  private lifecycle = new PageLifecycleManager('GlobalSearchPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    // 清理主题监听器
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化主题感知
   */
  private initThemeAware(): void {
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }
  
  /**
   * 初始化字体感知
   */
  private initFontAware(): void {
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  /**
   * 初始化响应式布局
   */
  private initResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 横屏=${deviceInfo.isLandscape}`);
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
        this.responsive_gridColumns = 4;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        this.responsive_gridColumns = 5;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        this.responsive_gridColumns = 6;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        this.responsive_gridColumns = 8;
        break;
    }
  }

  /**
   * 更新筛选后的分组缓存
   */
  private updateFilteredGroups(): void {
    if (!this.searchKeyword || this.searchKeyword.trim().length === 0) {
      this.filteredGroups = [];
      return;
    }
    
    // 返回有结果、正在搜索或有错误的分组（全部显示，让用户看到搜索进度）
    this.filteredGroups = this.sourceGroups.filter(g => g.items.length > 0 || g.isSearching || g.hasError);
  }

  /**
   * 加载搜索历史
   */
  private loadSearchHistory(): void {
    try {
      const history = AppStorage.get<string[]>('searchHistory') || [];
      this.searchHistory = history.slice(0, 10);
    } catch (error) {
      logger.error(TAG, `加载搜索历史失败: ${error}`);
    }
  }

  /**
   * 保存搜索历史
   */
  private saveSearchHistory(keyword: string): void {
    if (!keyword || keyword.trim() === '') return;
    
    const history = [keyword, ...this.searchHistory.filter(h => h !== keyword)];
    this.searchHistory = history.slice(0, 10);
    AppStorage.setOrCreate('searchHistory', this.searchHistory);
  }

  /**
   * 执行搜索 - 使用 GlobalSearchService
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword || this.searchKeyword.trim() === '') {
      return;
    }

    try {
      this.isSearching = true;
      this.searchProgress = '正在搜索...';
      this.sourceGroups = [];
      
      // 自动收起在线源列表
      this.showSourceExpanded = false;
      
      // 【关键】如果需要在线搜索图源，等待 WebView 就绪
      const needOnlineMangaSearch = this.sourceTypeFilter !== SearchSourceType.LOCAL && 
                                     this.selectedMangaSources.length > 0 &&
                                     (this.contentTypeFilter === SearchContentType.ALL || 
                                      this.contentTypeFilter === SearchContentType.MANGA);
      if (needOnlineMangaSearch) {
        await this.waitForWebViewReady();
      }
      
      logger.info(TAG, `开始搜索: "${this.searchKeyword}", 内容类型=${this.contentTypeFilter}, 来源=${this.sourceTypeFilter}`);
      this.saveSearchHistory(this.searchKeyword);

      // 构建筛选配置
      const filterConfig: SearchFilterConfig = {
        contentType: this.contentTypeFilter,
        sourceType: this.sourceTypeFilter,
        selectedMangaSources: this.selectedMangaSources,
        selectedNovelSources: this.selectedNovelSources,
        enableSuwayomi: this.enableSuwayomi,
        maxConcurrent: this.maxConcurrent
      };

      // 执行搜索
      const results = await this.searchService.searchAll(
        this.searchKeyword,
        filterConfig,
        (completed: number, total: number, groupName: string, groups: SearchSourceGroup[]) => {
          // 节流进度更新，最多每500ms更新一次UI
          const now = Date.now();
          if (now - this.lastProgressUpdate >= 500 || completed === total) {
            this.lastProgressUpdate = now;
            this.searchProgress = `搜索中... (${completed}/${total})`;
            this.sourceGroups = [...groups];
            this.updateFilteredGroups();
          }
        }
      );

      this.sourceGroups = results;
      this.updateFilteredGroups();
      this.isSearching = false;
      this.searchProgress = '';
      
      const totalResults = results.reduce((sum, g) => sum + g.items.length, 0);
      logger.info(TAG, `搜索完成: ${results.length}个分组, ${totalResults}条结果`);
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
      this.isSearching = false;
      this.searchProgress = '';
    }
  }

  /**
   * 获取内容类型的显示名称
   */
  private getContentTypeName(type: SearchContentType): string {
    switch (type) {
      case SearchContentType.MANGA: return '漫画';
      case SearchContentType.NOVEL: return '小说';
      case SearchContentType.EBOOK: return '电子书';
      default: return '全部';
    }
  }

  /**
   * 获取来源类型的显示名称
   */
  private getSourceTypeName(type: SearchSourceType): string {
    switch (type) {
      case SearchSourceType.LOCAL: return '本地';
      case SearchSourceType.ONLINE: return '在线';
      default: return '全部';
    }
  }

  /**
   * 获取项目数量文本
   */
  private getItemCountText(group: SearchSourceGroup): string {
    const count = group.items.length;
    switch (group.contentType) {
      case SearchContentType.MANGA: return `${count}本漫画`;
      case SearchContentType.NOVEL: return `${count}本小说`;
      case SearchContentType.EBOOK: return `${count}本电子书`;
      default: return `${count}项`;
    }
  }

  /**
   * 获取已选源的摘要信息
   */
  private getSelectedSourcesSummary(): string {
    const parts: string[] = [];
    if (this.selectedMangaSources.length > 0) {
      parts.push(`${this.selectedMangaSources.length}个图源`);
    }
    if (this.selectedNovelSources.length > 0) {
      parts.push(`${this.selectedNovelSources.length}个书源`);
    }
    if (this.enableSuwayomi) {
      parts.push('Suwayomi');
    }
    return parts.length > 0 ? parts.join(', ') : '未选择';
  }

  /**
   * 切换漫画图源选中状态
   */
  private toggleMangaSource(sourceId: string): void {
    const index = this.selectedMangaSources.indexOf(sourceId);
    if (index >= 0) {
      this.selectedMangaSources = this.selectedMangaSources.filter(id => id !== sourceId);
    } else {
      this.selectedMangaSources = [...this.selectedMangaSources, sourceId];
    }
    this.saveSearchPreferences();
  }

  /**
   * 切换小说书源选中状态
   */
  private toggleNovelSource(sourceId: string): void {
    const index = this.selectedNovelSources.indexOf(sourceId);
    if (index >= 0) {
      this.selectedNovelSources = this.selectedNovelSources.filter(id => id !== sourceId);
    } else {
      this.selectedNovelSources = [...this.selectedNovelSources, sourceId];
    }
    this.saveSearchPreferences();
  }
  
  /**
   * 切换分组展开状态
   */
  private toggleGroupExpanded(groupId: string): void {
    const newSet = new Set<string>(this.expandedGroups);
    if (newSet.has(groupId)) {
      newSet.delete(groupId);
    } else {
      newSet.add(groupId);
    }
    this.expandedGroups = newSet;
  }

  /**
   * 打开详情页 - 支持统一搜索结果项
   * 根据设置判断跳转到默认详情页还是统一详情页
   */
  private openDetail(item: UnifiedSearchItem): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      const stack = globalStack || this.pathStack;
      
      // 本地漫画
      if (item.contentType === SearchContentType.MANGA && item.sourceType === SearchSourceType.LOCAL && item.rawManga) {
        const pageType = PageSettingsHelper.getMangaDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          // 统一详情页
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.MANGA,
            contentId: item.rawManga.id
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          // 默认详情页
          const navParam: MangaDetailNavParam = { mangaId: item.rawManga.id };
          stack.pushPath({ name: 'MangaDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到本地漫画详情页: ${item.rawManga.id}, pageType=${pageType}`);
      }
      // 本地电子书
      else if (item.contentType === SearchContentType.EBOOK && item.rawEbook) {
        const pageType = PageSettingsHelper.getEBookDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.EBOOK,
            contentId: item.rawEbook.id
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: EBookDetailNavParam = { bookId: item.rawEbook.id };
          stack.pushPath({ name: 'EBookDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到电子书详情页: ${item.rawEbook.id}, pageType=${pageType}`);
      }
      // 本地小说
      else if (item.contentType === SearchContentType.NOVEL && item.sourceType === SearchSourceType.LOCAL && item.rawNovelBook) {
        const pageType = PageSettingsHelper.getNovelDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.NOVEL,
            contentId: item.rawNovelBook.bookUrl,
            sourceId: item.rawNovelBook.sourceId
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: NovelDetailPageParams = { 
            sourceId: item.rawNovelBook.sourceId,
            bookUrl: item.rawNovelBook.bookUrl,
            bookName: item.rawNovelBook.name,
            author: item.rawNovelBook.author,
            coverUrl: item.rawNovelBook.coverUrl,
            intro: item.rawNovelBook.intro,
            sourceName: item.rawNovelBook.sourceName
          };
          stack.pushPath({ name: 'NovelDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到本地小说详情页: ${item.rawNovelBook.name}, pageType=${pageType}`);
      }
      // 在线漫画（图源）
      else if (item.contentType === SearchContentType.MANGA && item.onlineSourceType === OnlineSourceType.MANGA_SOURCE && item.rawOnlineComic) {
        const pageType = PageSettingsHelper.getMangaDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.MANGA,
            contentId: item.rawOnlineComic.id,
            sourceId: item.sourceId
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: OnlineMangaDetailNavParam = {
            sourceId: parseInt(item.sourceId),
            comicId: item.rawOnlineComic.id,
            comicTitle: item.rawOnlineComic.title
          };
          stack.pushPath({ name: 'SourceDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到在线漫画详情页: ${item.rawOnlineComic.title}, pageType=${pageType}`);
      }
      // 在线漫画（Suwayomi）
      else if (item.contentType === SearchContentType.MANGA && item.onlineSourceType === OnlineSourceType.SUWAYOMI && item.rawOnlineComic) {
        const suwayomiParam: SuwayomiDetailNavParam = { mangaId: item.rawOnlineComic.id };
        stack.pushPath({ name: 'SuwayomiDetailPage', param: suwayomiParam });
        logger.debug(TAG, `导航到Suwayomi详情页: ${item.rawOnlineComic.id}`);
      }
      // 在线小说（书源）
      else if (item.contentType === SearchContentType.NOVEL && item.onlineSourceType === OnlineSourceType.NOVEL_SOURCE && item.rawNovelSearch) {
        const pageType = PageSettingsHelper.getNovelDetailPageType();
        if (pageType === DetailPageType.UNIFIED) {
          const unifiedParam: UnifiedDetailPageParams = {
            contentType: UnifiedContentType.NOVEL,
            contentId: item.rawNovelSearch.bookUrl,
            sourceId: item.rawNovelSearch.sourceId
          };
          stack.pushPath({ name: 'UnifiedDetailPage', param: unifiedParam });
        } else {
          const navParam: NovelDetailPageParams = { 
            sourceId: item.rawNovelSearch.sourceId,
            bookUrl: item.rawNovelSearch.bookUrl,
            bookName: item.rawNovelSearch.name,
            author: item.rawNovelSearch.author,
            coverUrl: item.rawNovelSearch.coverUrl,
            intro: item.rawNovelSearch.intro,
            sourceName: item.rawNovelSearch.sourceName
          };
          stack.pushPath({ name: 'NovelDetailPage', param: navParam });
        }
        logger.debug(TAG, `导航到在线小说详情页: ${item.rawNovelSearch.name}, pageType=${pageType}`);
      }
    } catch (error) {
      logger.error(TAG, `打开详情页失败: ${error}`);
    }
  }
  
  /**
   * 打开图源搜索页面
   * 跳转到 SourceDetailPage 的搜索标签，传递搜索结果避免重复搜索
   */
  private openSourceSearchPage(group: SearchSourceGroup): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      const stack = globalStack || this.pathStack;
      
      // 从 groupId 提取 sourceId，格式为 "online-manga-{sourceId}"
      const groupIdParts = group.groupId.split('-');
      const sourceIdStr = groupIdParts.length >= 3 ? groupIdParts[2] : '';
      const sourceId = parseInt(sourceIdStr);
      if (isNaN(sourceId)) {
        logger.warn(TAG, `无效的图源ID: ${group.groupId}`);
        return;
      }
      
      // 【关键】将搜索结果缓存到 AppStorage，避免 SourceDetailPage 重复搜索
      // 定义缓存数据结构
      interface CachedComicInfo {
        id: string;
        title: string;
        author: string;
        coverUrl: string;
        description: string;
        url: string;
        status: string;
      }
      interface SearchCacheData {
        keyword: string;
        results: CachedComicInfo[];
        timestamp: number;
      }
      
      // 转换 UnifiedSearchItem 为 SourceDetailPage 可用的 ComicInfo 格式
      const cachedResults: CachedComicInfo[] = group.items.map((item: UnifiedSearchItem): CachedComicInfo => {
        const result: CachedComicInfo = {
          id: item.rawOnlineComic?.id || '',
          title: item.title,
          author: item.author || '',
          coverUrl: item.coverUrl || '',
          description: item.description || '',
          url: item.rawOnlineComic?.url || '',
          status: item.rawOnlineComic?.status || ''
        };
        return result;
      });
      
      // 存储缓存，使用 sourceId 和 keyword 组合作为 key
      const cacheKey = `global_search_cache_${sourceId}`;
      const cacheData: SearchCacheData = {
        keyword: this.searchKeyword,
        results: cachedResults,
        timestamp: Date.now()
      };
      AppStorage.setOrCreate(cacheKey, JSON.stringify(cacheData));
      logger.info(TAG, `缓存搜索结果: ${cachedResults.length} 条, key=${cacheKey}`);
      
      // 跳转到 SourceDetailPage，传递 initialTab='search' 和 searchKeyword
      // 并标记来自全局搜索，让 SourceDetailPage 优先使用缓存
      interface SourceSearchNavParam {
        sourceId: number;
        initialTab: string;
        searchKeyword: string;
        fromGlobalSearch: boolean;  // 标记来自全局搜索
      }
      const navParam: SourceSearchNavParam = {
        sourceId: sourceId,
        initialTab: 'search',
        searchKeyword: this.searchKeyword,
        fromGlobalSearch: true
      };
      
      stack.pushPath({ name: 'SourceDetailPage', param: navParam });
      logger.info(TAG, `跳转到图源搜索页: sourceId=${sourceId}, keyword="${this.searchKeyword}"`);
    } catch (error) {
      logger.error(TAG, `打开图源搜索页失败: ${error}`);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层（纯色，响应全局主题）
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
          Row({ space: 12 }) {
            TextInput({ placeholder: '搜索漫画、电子书、作者...', text: this.searchKeyword })
              .layoutWeight(1)
              .height(44)
              .borderRadius(12)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
              })
              .onChange((value: string) => {
                this.searchKeyword = value;
              })
              .onSubmit(() => {
                this.performSearch();
              })

            Button('搜索')
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.performSearch();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding(this.responsive_contentPadding)

          // 紧凑筛选栏 - 内容类型 + 来源类型 在一行（可滑动）
          Scroll() {
            Row({ space: 12 }) {
              // 内容类型筛选
              Row({ space: 4 }) {
                this.buildContentTypeChip('全部', SearchContentType.ALL)
                this.buildContentTypeChip('漫画', SearchContentType.MANGA)
                this.buildContentTypeChip('小说', SearchContentType.NOVEL)
                this.buildContentTypeChip('电子书', SearchContentType.EBOOK)
              }
              
              // 分隔符
              Divider()
                .vertical(true)
                .height(20)
                .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
              
              // 来源类型筛选
              Row({ space: 6 }) {
                this.buildSourceTypeIconChip($r('sys.symbol.folder'), SearchSourceType.LOCAL)
                this.buildSourceTypeIconChip($r('sys.symbol.worldclock_fill_1'), SearchSourceType.ONLINE)
                this.buildSourceTypeIconChip($r('sys.symbol.square_grid_2x2'), SearchSourceType.ALL)
              }
              
              // Suwayomi 独立开关（仅当可用时显示）
              if (this.isSuwayomiAvailable && this.sourceTypeFilter !== SearchSourceType.LOCAL) {
                Divider()
                  .vertical(true)
                  .height(20)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
                
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.computer_host_fill'))
                    .fontSize(14)
                    .fontColor([this.enableSuwayomi ? 
                      Color.White : 
                      ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                  Text('Suwayomi')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.enableSuwayomi ? 
                      Color.White : 
                      ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(16)
                .backgroundColor(this.enableSuwayomi ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : 
                  ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .border({
                  width: 1,
                  color: this.enableSuwayomi ? 
                    Color.Transparent : 
                    ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                })
                .animation({ duration: 200, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.enableSuwayomi = !this.enableSuwayomi;
                  this.saveSearchPreferences();
                })
              }
            }
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding({ bottom: 8 })

          // 在线源选择器（仅当选择在线或全部时显示）
          if (this.sourceTypeFilter !== SearchSourceType.LOCAL) {
            this.buildInlineSourceSelector()
          }

          // 搜索结果或历史记录
          if (this.searchKeyword && this.filteredGroups.length > 0) {
            // 按图源分组显示搜索结果
            if (this.responsive_isLandscape) {
              // 横屏模式：使用网格布局
              this.buildLandscapeResults()
            } else {
              // 竖屏模式：使用列表布局
              Scroll() {
                Column({ space: 16 }) {
                  ForEach(this.filteredGroups, (group: SearchSourceGroup) => {
                    this.buildSourceGroupCard(group)
                  }, (group: SearchSourceGroup) => `${group.groupId}-${group.items.length}`)
                }
                .width('100%')
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8 })
              }
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)
            }
          } else if (this.searchKeyword && this.sourceGroups.length > 0 && !this.sourceGroups.some(g => g.isSearching)) {
            // 搜索完成但无结果
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(48)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
              Text('未找到相关内容')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('换个关键词试试吧')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.searchKeyword && this.sourceGroups.some(g => g.isSearching)) {
            // 正在搜索
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
              Text('搜索中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 12 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 搜索历史
            Column() {
              if (this.searchHistory.length > 0) {
                Text('搜索历史')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .padding(this.responsive_contentPadding)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.searchHistory, (keyword: string) => {
                    Row({ space: 6 }) {
                      SymbolGlyph($r('sys.symbol.clock'))
                        .fontSize(14)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                      Text(keyword)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .padding({ left: 12, right: 14, top: 8, bottom: 8 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .borderRadius(18)
                    .border({
                      width: 1,
                      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                    })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.searchKeyword = keyword;
                      this.performSearch();
                    })
                  })
                }
                .width('100%')
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(this.responsive_isLandscape ? HorizontalAlign.Center : HorizontalAlign.Start)
        
        // 隐藏的 WebView 组件（用于后台搜索 WebView 格式图源）
        Web({
          src: 'about:blank',
          controller: this.webViewController
        })
          .width(1)
          .height(1)
          .opacity(0)
          .visibility(Visibility.None)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .onControllerAttached(() => {
            logger.info(TAG, 'WebView控制器已附加，设置为全局控制器');
            this.webViewReady = true;
            this.webViewSourceManager.setGlobalWebViewController(this.webViewController);
          })
          .onPageEnd(() => {
            logger.debug(TAG, 'WebView页面加载完成');
          })
          .onErrorReceive((event) => {
            const errorInfo = event.error.getErrorInfo();
            logger.warn(TAG, `WebView错误: ${errorInfo}`);
          })
      }
      .width('100%')
      .height('100%')
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      // 获取页面参数
      const params: GlobalSearchPageParams | undefined = context.pathInfo?.param as GlobalSearchPageParams | undefined;
      if (params) {
        this.pageParams = params;
        this.handlePageParams();
      }
    })
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
        title: { mainTitle: '全局搜索' }
      }
    })
    .backgroundColor(Color.Transparent)
  }

  /**
   * 构建横屏模式下的搜索结果
   */
  @Builder
  buildLandscapeResults() {
    Scroll() {
      Column({ space: 24 }) {
        ForEach(this.filteredGroups, (group: SearchSourceGroup) => {
          Column({ space: 12 }) {
            // 分组标题
            Row() {
              Text(group.groupName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Text(`(${this.getItemCountText(group)})`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })

            // 网格布局显示结果
            if (group.items.length > 0) {
              Grid() {
                ForEach(group.items, (item: UnifiedSearchItem) => {
                  GridItem() {
                    this.buildItemCard(item)
                  }
                }, (item: UnifiedSearchItem) => item.id)
              }
              .columnsTemplate(`repeat(${this.responsive_gridColumns}, 1fr)`)
              .columnsGap(12)
              .rowsGap(16)
              .width('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
            }
          }
          .width('100%')
        }, (group: SearchSourceGroup) => group.groupId)
        
        Blank().height(40)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.responsive_maxContentWidth })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }


  /**
   * 构建源分组卡片
   */
  @Builder
  buildSourceGroupCard(group: SearchSourceGroup) {
    Column({ space: 12 }) {
      // 源标题行
      Row() {
        Column({ space: 4 }) {
          Text(group.groupName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          if (group.isSearching) {
            Text('搜索中...')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          } else if (group.hasError) {
            Text('搜索失败')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          } else {
            Text(this.getItemCountText(group))
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        // 操作按钮区域：统一使用"展开全部"/"收起"逻辑
        if (!group.isSearching && group.items.length > 10) {
          Row({ space: 4 }) {
            Text(this.expandedGroups.has(group.groupId) ? '收起' : `展开全部 (${group.items.length})`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            SymbolGlyph(this.expandedGroups.has(group.groupId) ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
          .onClick(() => {
            this.toggleGroupExpanded(group.groupId);
          })
        }
      }
      .width('100%')

      // 搜索结果内容区域
      if (group.isSearching) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(24)
            .height(24)
          Text('搜索中...')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
      } else if (group.items.length > 0) {
        // 判断是否展开显示所有结果
        if (this.expandedGroups.has(group.groupId)) {
          // 展开模式：显示所有结果（网格布局）
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(group.items, (item: UnifiedSearchItem) => {
              Column() {
                this.buildItemCard(item)
              }
              .margin({ right: 12, bottom: 12 })
            }, (item: UnifiedSearchItem) => item.id)
          }
          .width('100%')
        } else {
          // 收起模式：横向滚动显示前10个
          Scroll() {
            Row({ space: 12 }) {
              ForEach(group.items.slice(0, 10), (item: UnifiedSearchItem) => {
                this.buildItemCard(item)
              }, (item: UnifiedSearchItem) => item.id)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
      } else if (group.hasError) {
        Text('搜索失败，请重试')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
      } else {
        Text('暂无结果')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
      }
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

  /**
   * 获取搜索结果封面
   */
  private getUnifiedCoverSource(item: UnifiedSearchItem): ResourceStr {
    const coverUrl = item.coverUrl || '';
    
    // 根据内容类型返回默认封面
    if (coverUrl.length === 0) {
      switch (item.contentType) {
        case SearchContentType.MANGA:
          return $r('app.media.mangabook');
        case SearchContentType.EBOOK:
          return $r('app.media.ic_ebook');
        case SearchContentType.NOVEL:
          return $r('app.media.ic_ebook');
        default:
          return $r('app.media.mangabook');
      }
    }
    
    // 应用资源路径
    if (coverUrl.startsWith('app.media.')) {
      const resourceName = coverUrl.substring('app.media.'.length);
      if (resourceName === 'mangabook') return $r('app.media.mangabook');
      if (resourceName === 'ic_ebook') return $r('app.media.ic_ebook');
      if (resourceName === 'ic_novel') return $r('app.media.ic_ebook');
      return $r('app.media.mangabook');
    }
    
    // 本地文件路径
    if (coverUrl.startsWith('/')) {
      return `file://${coverUrl}`;
    }
    
    return coverUrl;
  }

  /**
   * 获取搜索结果默认封面
   */
  private getDefaultCover(contentType: SearchContentType): Resource {
    switch (contentType) {
      case SearchContentType.MANGA:
        return $r('app.media.mangabook');
      case SearchContentType.EBOOK:
        return $r('app.media.ic_ebook');
      case SearchContentType.NOVEL:
        return $r('app.media.ic_ebook');
      default:
        return $r('app.media.mangabook');
    }
  }

  /**
   * 构建项目卡片（统一搜索结果）
   */
  @Builder
  buildItemCard(item: UnifiedSearchItem) {
    Column({ space: 8 }) {
      // 封面
      if (item.coverUrl && item.coverUrl.length > 0) {
        Image(this.getUnifiedCoverSource(item))
          .width(100)
          .height(140)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .alt(this.getDefaultCover(item.contentType))
      } else {
        // 无封面时显示标题首字
        Column() {
          Text(item.title.substring(0, 1))
            .fontSize(32)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(100)
        .height(140)
        .borderRadius(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }

      // 标题
      Text(item.title)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(100)
        .textAlign(TextAlign.Start)
    }
    .width(100)
    .onClick(() => {
      this.openDetail(item);
    })
  }

  /**
   * 构建内容类型筛选Chip
   */
  @Builder
  buildContentTypeChip(label: string, type: SearchContentType) {
    Text(label)
      .fontSize(12)
      .fontFamily(this.appFontFamily)
      .fontColor(this.contentTypeFilter === type ? 
        Color.White : 
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.contentTypeFilter === type ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({
        width: 1,
        color: this.contentTypeFilter === type ? 
          Color.Transparent : 
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .animation({ duration: 200, curve: Curve.EaseInOut })
      .onClick(() => {
        this.contentTypeFilter = type;
        this.saveSearchPreferences();
        this.updateFilteredGroups();
      })
  }

  /**
   * 构建来源类型筛选图标Chip
   */
  @Builder
  buildSourceTypeIconChip(icon: Resource, type: SearchSourceType) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.sourceTypeFilter === type ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.sourceTypeFilter === type ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.sourceTypeFilter === type ? 
        Color.Transparent : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.sourceTypeFilter = type;
      this.saveSearchPreferences();
      this.updateFilteredGroups();
    })
  }

  /**
   * 构建内联在线源选择器（可折叠）
   */
  @Builder
  buildInlineSourceSelector() {
    Column() {
      // 展开/收起按钮
      Row({ space: 8 }) {
        SymbolGlyph(this.showSourceExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(14)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        
        SymbolGlyph($r('sys.symbol.worldclock_fill_1'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        
        Text('在线源')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        // 已选源数量标记
        Text(this.getSelectedSourcesCountForCurrentType())
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 全选/清空快捷按钮
        if (this.showSourceExpanded) {
          Row({ space: 12 }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('全选')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .onClick(() => {
              this.selectAllSourcesForCurrentType();
            })
            
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(14)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              Text('清空')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
            .onClick(() => {
              this.clearAllSourcesForCurrentType();
            })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .onClick(() => {
        animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
          this.showSourceExpanded = !this.showSourceExpanded;
        });
        this.saveSearchPreferences();
      })

      // 展开的源选择内容
      if (this.showSourceExpanded) {
        Scroll() {
          Column({ space: 16 }) {
            // 根据内容类型显示对应的源
            if (this.shouldShowMangaSources()) {
              this.buildMangaSourcesSection()
            }
            
            if (this.shouldShowNovelSources()) {
              this.buildNovelSourcesSection()
            }
            
            // 电子书无在线源提示
            if (this.contentTypeFilter === SearchContentType.EBOOK) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.info_circle'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                Text('电子书仅支持本地搜索')
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 16, bottom: 16 })
            }

            // 无可用源提示
            if (this.getAvailableSourcesForCurrentType() === 0 && this.contentTypeFilter !== SearchContentType.EBOOK) {
              Column({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.questionmark_circle'))
                  .fontSize(32)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                Text('暂无可用的在线源')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                Text('请先添加图源或书源')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')
              .padding({ top: 20, bottom: 20 })
            }
          }
          .width('100%')
          .padding(12)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .margin({ top: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(12)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
    .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 8 })
  }

  /**
   * 构建源选择Chip
   */
  @Builder
  buildSourceChip(name: string, id: string, isSelected: boolean, onClick: () => void) {
    Text(name)
      .fontSize(11)
      .fontFamily(this.appFontFamily)
      .fontColor(isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .border({
        width: 1,
        color: isSelected ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
      })
      .margin({ right: 6, bottom: 6 })
      .onClick(onClick)
  }

  /**
   * 构建带置顶标记的源选择Chip
   */
  @Builder
  buildSourceChipWithPin(name: string, id: string, isSelected: boolean, isPinned: boolean, onClick: () => void) {
    Row({ space: 2 }) {
      if (isPinned) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(10)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      Text(name)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(isSelected ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
    }
    .padding({ left: isPinned ? 4 : 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(12)
    .backgroundColor(isSelected ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' : 
      (isPinned ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '10' :
        ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme)))
    .border({
      width: 1,
      color: isSelected ? 
        ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
        (isPinned ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '50' :
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
    })
    .margin({ right: 6, bottom: 6 })
    .onClick(onClick)
  }

  /**
   * 获取已选源数量文本
   * 注：Suwayomi 已独立，不计入此处
   */
  private getSelectedSourcesCount(): string {
    const count = this.selectedMangaSources.length + this.selectedNovelSources.length;
    const total = this.availableMangaSources.length + this.availableNovelSources.length;
    return `${count}/${total}`;
  }

  /**
   * 全选所有源
   * 注：Suwayomi 已独立，不在此处控制
   */
  private selectAllSources(): void {
    this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
    this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
    this.saveSearchPreferences();
  }

  /**
   * 清空所有源选择
   * 注：Suwayomi 已独立，不在此处控制
   */
  private clearAllSources(): void {
    this.selectedMangaSources = [];
    this.selectedNovelSources = [];
    this.saveSearchPreferences();
  }

  /**
   * 判断是否应显示漫画图源
   */
  private shouldShowMangaSources(): boolean {
    return (this.contentTypeFilter === SearchContentType.ALL || 
            this.contentTypeFilter === SearchContentType.MANGA) &&
           this.availableMangaSources.length > 0;
  }

  /**
   * 判断是否应显示小说书源
   */
  private shouldShowNovelSources(): boolean {
    return (this.contentTypeFilter === SearchContentType.ALL || 
            this.contentTypeFilter === SearchContentType.NOVEL) &&
           this.availableNovelSources.length > 0;
  }

  /**
   * 获取当前类型已选源数量
   * 注：Suwayomi 已独立，不计入此处
   */
  private getSelectedSourcesCountForCurrentType(): string {
    let selected = 0;
    let total = 0;
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      selected += this.selectedMangaSources.length;
      total += this.availableMangaSources.length;
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      selected += this.selectedNovelSources.length;
      total += this.availableNovelSources.length;
    }
    
    return `${selected}/${total}`;
  }

  /**
   * 获取当前类型可用源数量
   * 注：Suwayomi 已独立，不计入此处
   */
  private getAvailableSourcesForCurrentType(): number {
    let total = 0;
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      total += this.availableMangaSources.length;
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      total += this.availableNovelSources.length;
    }
    
    return total;
  }

  /**
   * 根据当前类型全选
   * 注：Suwayomi 已独立，不在此处控制
   */
  private selectAllSourcesForCurrentType(): void {
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      this.selectedMangaSources = this.availableMangaSources.map(s => s.id.toString());
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      this.selectedNovelSources = this.availableNovelSources.map(s => s.id);
    }
    
    this.saveSearchPreferences();
  }

  /**
   * 根据当前类型清空
   * 注：Suwayomi 已独立，不在此处控制
   */
  private clearAllSourcesForCurrentType(): void {
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.MANGA) {
      this.selectedMangaSources = [];
    }
    
    if (this.contentTypeFilter === SearchContentType.ALL || this.contentTypeFilter === SearchContentType.NOVEL) {
      this.selectedNovelSources = [];
    }
    
    this.saveSearchPreferences();
  }

  /**
   * 构建漫画图源区域
   * 注：Suwayomi 已移至筛选栏作为独立开关
   */
  @Builder
  buildMangaSourcesSection() {
    Column({ space: 10 }) {
      // 标题行
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.shutter_photo'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
        
        Text('漫画图源')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(`${this.selectedMangaSources.length}/${this.availableMangaSources.length}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        // 置顶源提示
        if (this.availableMangaSources.some(s => s.isPinned)) {
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.pin_fill'))
              .fontSize(12)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
            Text(`${this.availableMangaSources.filter(s => s.isPinned).length}`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
        }
      }
      .width('100%')
      
      // 图源列表
      if (this.availableMangaSources.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.availableMangaSources.slice(0, this.mangaSourceDisplayCount), (source: SourceInfo) => {
            this.buildMangaSourceChip(source)
          }, (source: SourceInfo) => `manga-${source.id}-${this.selectedMangaSources.includes(source.id.toString())}`)
        }
        .width('100%')
        
        // 显示更多/收起按钮
        if (this.availableMangaSources.length > SOURCE_DISPLAY_LIMIT) {
          Row({ space: 4 }) {
            if (this.mangaSourceDisplayCount < this.availableMangaSources.length) {
              Text(`显示更多 (${this.mangaSourceDisplayCount}/${this.availableMangaSources.length})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onClick(() => {
                  this.mangaSourceDisplayCount = Math.min(
                    this.mangaSourceDisplayCount + SOURCE_DISPLAY_STEP,
                    this.availableMangaSources.length
                  );
                })
            } else {
              Text('收起')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.mangaSourceDisplayCount = SOURCE_DISPLAY_LIMIT;
                })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8 })
        }
      } else {
        Text('暂无可用图源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .padding({ top: 8 })
      }
    }
    .width('100%')
  }

  /**
   * 构建小说书源区域
   */
  @Builder
  buildNovelSourcesSection() {
    Column({ space: 10 }) {
      // 标题行
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
        
        Text('小说书源')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Text(`${this.selectedNovelSources.length}/${this.availableNovelSources.length}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 书源列表
      if (this.availableNovelSources.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.availableNovelSources.slice(0, this.novelSourceDisplayCount), (source: NovelSourceInfo) => {
            this.buildNovelSourceChip(source)
          }, (source: NovelSourceInfo) => `novel-${source.id}-${this.selectedNovelSources.includes(source.id)}`)
        }
        .width('100%')
        
        // 显示更多/收起按钮
        if (this.availableNovelSources.length > SOURCE_DISPLAY_LIMIT) {
          Row({ space: 4 }) {
            if (this.novelSourceDisplayCount < this.availableNovelSources.length) {
              Text(`显示更多 (${this.novelSourceDisplayCount}/${this.availableNovelSources.length})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .onClick(() => {
                  this.novelSourceDisplayCount = Math.min(
                    this.novelSourceDisplayCount + SOURCE_DISPLAY_STEP,
                    this.availableNovelSources.length
                  );
                })
            } else {
              Text('收起')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .onClick(() => {
                  this.novelSourceDisplayCount = SOURCE_DISPLAY_LIMIT;
                })
            }
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8 })
        }
      } else {
        Text('暂无可用书源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .padding({ top: 8 })
      }
    }
    .width('100%')
  }

  /**
   * 构建漫画图源Chip
   */
  @Builder
  buildMangaSourceChip(source: SourceInfo) {
    Row({ space: 4 }) {
      // 网络访问标识（requireProxy 表示需要 Internet）
      if (source.requireProxy) {
        SymbolGlyph($r('sys.symbol.airplane_departure'))
          .fontSize(11)
          .fontColor([this.selectedMangaSources.includes(source.id.toString()) ? 
            Color.White :
            ThemeAwareHelper.getTestManagementThemedColor('accent_orange', this.themeState.currentTheme)])
      }
      // 置顶标识
      if (source.isPinned) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(10)
          .fontColor([this.selectedMangaSources.includes(source.id.toString()) ? 
            Color.White :
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
      Text(source.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.selectedMangaSources.includes(source.id.toString()) ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: (source.requireProxy || source.isPinned) ? 6 : 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.selectedMangaSources.includes(source.id.toString()) ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.selectedMangaSources.includes(source.id.toString()) ? 
        Color.Transparent : 
        (source.isPinned ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '50' :
          ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
    })
    .margin({ right: 8, bottom: 8 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.toggleMangaSource(source.id.toString());
    })
  }

  /**
   * 构建小说书源Chip
   */
  @Builder
  buildNovelSourceChip(source: NovelSourceInfo) {
    Row({ space: 4 }) {
      Text(source.name)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.selectedNovelSources.includes(source.id) ? 
          Color.White : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.selectedNovelSources.includes(source.id) ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .border({
      width: 1,
      color: this.selectedNovelSources.includes(source.id) ? 
        Color.Transparent : 
        ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .margin({ right: 8, bottom: 8 })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onClick(() => {
      this.toggleNovelSource(source.id);
    })
  }
}
