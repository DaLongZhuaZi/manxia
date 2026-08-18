/**
 * 小说搜索页面
 * 使用标签页形式展示各书源搜索结果
 * 支持搜索历史、搜索设置、响应式布局
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSearchPage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelInitializer } from '../Framework/Novel/NovelInitializer';
import { LegadoWorkflowKind } from '../Framework/Novel/LegadoCompatibilityTypes';
import { getLegadoSourceAutomationToken } from '../Framework/Novel/LegadoSourceAutomationIdentity';
import { LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { getLegadoMangaSourceBridge, LegadoMangaVirtualSource } from '../Framework/Novel/LegadoMangaSourceBridge';
import { getNovelSettingsManager, NovelSettingsManager } from '../Framework/Novel/NovelSettingsManager';
import { NovelSearchResult, NovelSourceInfo } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { NovelDetailPageParams, NovelSearchPageParams } from './NovelBookshelfPage';
import { NovelExplorePageParams } from './NovelExplorePage';
import { DeviceAdaptationManager, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { AppColors } from '../Framework/Theme/AppColors';
import { PageSettingsHelper, DetailPageType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';
import { MangaDetailPageParams } from './MangaDetailPage';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';

/**
 * 书源搜索结果分组
 */
interface SourceSearchResult {
  sourceId: string;
  sourceName: string;
  sourceGroup: string;  // 书源分组
  results: NovelSearchResult[];
  isLoading: boolean;
  hasError: boolean;
  errorMsg: string;
}

/**
 * 书源分组信息（用于书源选择对话框）
 */
interface SourceGroupInfo {
  groupName: string;      // 分组名称
  sources: NovelSourceInfo[];  // 该分组下的书源
  isExpanded: boolean;    // 是否展开
  selectedCount: number;  // 已选中数量
}

const TAG = 'NovelSearchPage';

// 书源选择弹窗分页常量
const SOURCE_SELECTOR_PAGE_SIZE = 100;
const SOURCE_SELECTOR_PRELOAD_THRESHOLD = 60;

// 搜索常量
const MAX_CONCURRENT_SOURCES = 50;  // 最大并发搜索数
const SEARCH_BATCH_SIZE = 10;       // 每批搜索数量
const SEARCH_BATCH_DELAY = 50;      // 批次间延迟(ms)
const PROGRESS_THROTTLE_MS = 300;   // 进度更新节流(ms)
const MAX_RESULTS_PER_SOURCE = 100; // 每个书源最大结果数
const SINGLE_SOURCE_SEARCH_SUGGESTIONS: string[] = [
  '斗破苍穹',
  '诡秘之主',
  '凡人修仙传',
  '一人之下',
  '咒术回战',
  '海贼王'
];

@Component
export struct NovelSearchPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSearchPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State keyword: string = '';
  @State searchResults: NovelSearchResult[] = [];
  @State isSearching: boolean = false;
  @State hasSearched: boolean = false;
  @State searchErrorMessage: string = '';
  @State searchHistory: string[] = [];
  @State maxConcurrentSources: number = 5;
  // 单书源搜索模式
  @State singleSourceId: string = '';
  @State singleSourceName: string = '';
  @State singleSourceV2TraceSummary: string = '';
  @State showSingleSourceV2Trace: boolean = false;
  
  // 标签页相关状态
  @State sourceResults: SourceSearchResult[] = [];  // 按书源分组的搜索结果
  @State currentTabIndex: number = 0;  // 当前选中的标签页索引
  @State searchingSourceCount: number = 0;  // 正在搜索的书源数量
  @State completedSourceCount: number = 0;  // 已完成搜索的书源数量
  @State totalSourceCount: number = 0;  // 总书源数量
  
  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  private boundDeviceChangeHandler: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  
  // 书源选择相关
  @State showSourceSelector: boolean = false;
  @State selectedSourceIds: Set<string> = new Set();
  private allAvailableSources: NovelSourceInfo[] = [];  // 所有可用书源
  @State displayedAvailableSources: NovelSourceInfo[] = [];  // 当前显示的书源（分页）
  private sourceSelectorPage: number = 0;
  private sourceSelectorHasMore: boolean = true;
  private sourceSelectorIsLoading: boolean = false;
  
  // 书源选择对话框 - 分组展示相关
  @State sourceGroups: SourceGroupInfo[] = [];  // 书源分组列表
  @State sourceSelectorFilter: string = '';     // 搜索过滤关键词
  @State filteredSourceGroups: SourceGroupInfo[] = [];  // 过滤后的分组
  
  // 搜索控制相关
  private currentSearchTaskId: number = 0;  // 当前搜索任务ID
  private activeSearchKeyword: string = '';
  private lastProgressUpdate: number = 0;   // 上次进度更新时间戳
  @State searchProgress: string = '';       // 搜索进度文本
  
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private settingsManager: NovelSettingsManager = getNovelSettingsManager();

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
    this.loadSettings();
    this.initResponsiveLayout();
  }

  async loadSettings(): Promise<void> {
    await this.settingsManager.loadSettings();
    this.searchHistory = this.settingsManager.getSearchHistory();
    this.maxConcurrentSources = this.settingsManager.getMaxConcurrentSources();
  }
  
  private initResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      // DeviceChangeListener是函数类型: (deviceInfo: DeviceInfo) => void
      this.boundDeviceChangeHandler = () => {
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.boundDeviceChangeHandler);
    } catch (error) {
      logger.error(TAG, `初始化响应式布局失败: ${error}`);
    }
  }
  
  private updateResponsiveParams(): void {
    try {
      const deviceInfo = this.deviceManager.getDeviceInfo();
      this.responsive_isLandscape = deviceInfo.isLandscape;
      this.responsive_contentPadding = this.responsive_isLandscape ? 24 : 16;
      this.responsive_maxContentWidth = this.responsive_isLandscape ? 1200 : 600;
    } catch (error) {
      logger.error(TAG, `更新响应式参数失败: ${error}`);
    }
  }

  private lifecycle = new PageLifecycleManager('NovelSearchPage', { enableDebug: true });

  aboutToDisappear(): void {
    // 取消正在进行的搜索
    this.currentSearchTaskId++;
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.boundDeviceChangeHandler) {
      this.deviceManager.removeListener(this.boundDeviceChangeHandler);
      this.boundDeviceChangeHandler = null;
    }
  }

  private dismissSearchInputFocus(): void {
    this.getUIContext().getFocusController().clearFocus();
  }

  async doSearch(): Promise<void> {
    const normalizedKeyword = this.keyword.trim();
    if (!normalizedKeyword) {
      return;
    }

    // TextInput.onSubmit and the visible command can be delivered together by
    // an IME or UI automation. They describe the same user action, so a
    // second identical V2 request must not race the visible result and trace.
    if (this.isSearching && this.activeSearchKeyword === normalizedKeyword) {
      logger.info(TAG, `忽略重复搜索提交: ${normalizedKeyword}`);
      return;
    }

    this.dismissSearchInputFocus();

    // 取消之前的搜索任务
    this.currentSearchTaskId++;
    const taskId = this.currentSearchTaskId;
    this.activeSearchKeyword = normalizedKeyword;
    
    this.isSearching = true;
    this.hasSearched = true;
    this.searchErrorMessage = '';
    this.searchResults = [];
    this.sourceResults = [];
    this.currentTabIndex = 0;
    this.completedSourceCount = 0;
    this.searchProgress = '';
    this.singleSourceV2TraceSummary = '';
    this.showSingleSourceV2Trace = false;
    this.lastProgressUpdate = 0;

    try {
      // Source search is a V2 routing boundary. A cold-start page must not
      // issue a plausible legacy request before raw source records finish
      // restoring in the shared module initializer.
      await this.ensureNovelModuleReady();
      if (taskId !== this.currentSearchTaskId) {
        return;
      }
      // 保存搜索历史
      await this.settingsManager.addSearchHistory(normalizedKeyword);
      this.searchHistory = this.settingsManager.getSearchHistory();
      
      if (this.singleSourceId) {
        // 单书源搜索模式
        logger.info(TAG, `单书源搜索: ${this.keyword}, 书源: ${this.singleSourceName}`);
        const results = await this.sourceManager.search(this.singleSourceId, normalizedKeyword, 1, {
          maxResults: MAX_RESULTS_PER_SOURCE
        });
        
        // 检查任务是否已取消
        if (taskId !== this.currentSearchTaskId) {
          logger.info(TAG, '搜索任务已取消');
          return;
        }
        
        this.searchResults = results;
        this.sourceResults = [];
        logger.info(TAG, `搜索结果: ${results.length} 本`);
      } else {
        // 全局搜索模式 - 按书源分组搜索
        logger.info(TAG, `全局搜索: ${this.keyword}, 并发数: ${this.maxConcurrentSources}`);
        await this.doSearchBySource(taskId, normalizedKeyword);
      }
    } catch (error) {
      const executionError: string = String(error);
      logger.error(TAG, `搜索失败: ${executionError}`);
      if (executionError.includes('V2_EXECUTION_TRACE_MISSING')) {
        this.searchErrorMessage = 'V2 执行证据缺失，结果未被采用';
      } else if (executionError.includes('V2_FULL_CUTOVER_BLOCKED;workflow=search')) {
        this.searchErrorMessage = 'V2 全量切换已阻止该书源执行，已记录兼容性诊断';
      } else if (executionError.includes('V2_EXECUTION_UNAVAILABLE;workflow=search')) {
        this.searchErrorMessage = 'V2 搜索执行器未就绪，已阻止返回不可信空结果';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=result_mapping')) {
        this.searchErrorMessage = 'V2 搜索结果处理失败，已记录诊断信息';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=trace;error=http;status=')) {
        const statusMarker: string = ';status=';
        const statusStart: number = executionError.indexOf(statusMarker) + statusMarker.length;
        const statusCode: string = executionError.substring(statusStart).split(';')[0];
        this.searchErrorMessage = `V2 搜索请求返回 HTTP ${statusCode}，已记录诊断信息`;
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=trace;error=network')) {
        this.searchErrorMessage = 'V2 搜索网络请求未完成，已记录诊断信息';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=trace;error=unsupported_api')) {
        this.searchErrorMessage = '当前 V2 不支持该书源所需脚本 API，已记录兼容性诊断';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=trace;error=rule')) {
        this.searchErrorMessage = 'V2 搜索规则执行失败，已记录诊断信息';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=trace')) {
        this.searchErrorMessage = 'V2 搜索状态同步失败，已记录诊断信息';
      } else if (executionError.includes('V2_EXECUTION_FAILED;workflow=search;stage=request')) {
        this.searchErrorMessage = 'V2 搜索请求未完成，已记录诊断信息';
      } else {
        this.searchErrorMessage = '搜索未完成，请稍后重试';
      }
    }

    // 确保只有当前任务才更新状态
    if (taskId === this.currentSearchTaskId) {
      this.refreshSingleSourceV2TraceSummary();
      this.isSearching = false;
      this.activeSearchKeyword = '';
      this.searchProgress = '';
    }
  }
  
  /**
   * 按书源分组搜索 - 独立并行搜索机制
   * @param taskId 搜索任务ID，用于取消检查
   */
  async doSearchBySource(taskId: number, keyword: string): Promise<void> {
    let sourcesToSearch: NovelSourceInfo[];
    
    // 如果用户选择了指定书源，则只搜索选中的书源
    if (this.selectedSourceIds.size > 0) {
      const enabledSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      sourcesToSearch = enabledSources.filter(s => this.selectedSourceIds.has(s.id));
      logger.info(TAG, `使用指定书源搜索: ${sourcesToSearch.length}个`);
    } else {
      // 否则使用默认的并发数限制，最多50个
      const enabledSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      const maxSources = Math.min(this.maxConcurrentSources, MAX_CONCURRENT_SOURCES);
      sourcesToSearch = enabledSources.slice(0, maxSources);
    }
    
    this.totalSourceCount = sourcesToSearch.length;
    
    logger.info(TAG, `开始搜索 ${sourcesToSearch.length} 个书源`);
    
    // 分批执行搜索，避免主线程阻塞导致ANR
    for (let batchStart = 0; batchStart < sourcesToSearch.length; batchStart += SEARCH_BATCH_SIZE) {
      // 检查任务是否已取消
      if (taskId !== this.currentSearchTaskId) {
        logger.info(TAG, '搜索任务已取消');
        return;
      }
      
      const batchEnd = Math.min(batchStart + SEARCH_BATCH_SIZE, sourcesToSearch.length);
      const batchSources = sourcesToSearch.slice(batchStart, batchEnd);
      
      // 并行搜索当前批次的书源
      const batchPromises = batchSources.map(async (source: NovelSourceInfo) => {
        return this.searchSingleSource(source, taskId, keyword);
      });
      
      await Promise.all(batchPromises);
      
      // 节流更新进度
      this.throttledUpdateProgress();
      
      // 如果还有下一批，添加延迟让UI有时间响应
      if (batchEnd < sourcesToSearch.length) {
        await this.delay(SEARCH_BATCH_DELAY);
      }
    }
    
    logger.info(TAG, `全部搜索完成，共 ${this.sourceResults.length} 个书源有结果，总计 ${this.searchResults.length} 本`);
  }
  
  /**
   * 节流更新进度
   */
  private throttledUpdateProgress(): void {
    const now = Date.now();
    if (now - this.lastProgressUpdate >= PROGRESS_THROTTLE_MS) {
      this.lastProgressUpdate = now;
      this.searchProgress = `搜索中... (${this.completedSourceCount}/${this.totalSourceCount})`;
    }
  }
  
  /**
   * 搜索单个书源
   * @param source 书源信息
   * @param taskId 搜索任务ID
   */
  private async searchSingleSource(
    source: NovelSourceInfo,
    taskId: number,
    keyword: string
  ): Promise<SourceSearchResult> {
    const sourceResult: SourceSearchResult = {
      sourceId: source.id,
      sourceName: source.name,
      sourceGroup: source.group || '未分组',
      results: [],
      isLoading: true,
      hasError: false,
      errorMsg: ''
    };
    
    try {
      // 检查任务是否已取消
      if (taskId !== this.currentSearchTaskId) {
        return sourceResult;
      }
      
      const results = await this.sourceManager.search(source.id, keyword, 1, {
        maxResults: MAX_RESULTS_PER_SOURCE
      });
      
      // 再次检查任务是否已取消
      if (taskId !== this.currentSearchTaskId) {
        return sourceResult;
      }
      
      // 限制每个书源的结果数量，避免内存溢出
      const limitedResults = results.slice(0, MAX_RESULTS_PER_SOURCE);
      sourceResult.results = limitedResults;
      sourceResult.isLoading = false;
      
      // 只添加有结果的书源
      if (limitedResults.length > 0) {
        // 更新状态 - 添加到结果列表
        this.addSourceResult(sourceResult);
        // 同时更新总结果
        this.searchResults = [...this.searchResults, ...limitedResults];
      }
      
      logger.debug(TAG, `书源 ${source.name} 搜索完成: ${limitedResults.length} 本`);
    } catch (error) {
      sourceResult.isLoading = false;
      sourceResult.hasError = true;
      sourceResult.errorMsg = String(error);
      logger.warn(TAG, `书源 ${source.name} 搜索失败: ${String(error)}`);
    }
    
    this.completedSourceCount++;
    return sourceResult;
  }
  
  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
  
  /**
   * 添加书源搜索结果（保持响应式更新）
   */
  private addSourceResult(result: SourceSearchResult): void {
    // 创建新数组以触发状态更新
    this.sourceResults = [...this.sourceResults, result];
  }
  
  /**
   * 获取有结果的书源列表
   */
  getSourcesWithResults(): SourceSearchResult[] {
    return this.sourceResults.filter(s => s.results.length > 0);
  }

  async clearHistory(): Promise<void> {
    await this.settingsManager.clearSearchHistory();
    this.searchHistory = [];
    this.getUIContext().getPromptAction().showToast({ message: '搜索历史已清空' });
  }

  async removeHistoryItem(keyword: string): Promise<void> {
    await this.settingsManager.removeSearchHistory(keyword);
    this.searchHistory = this.settingsManager.getSearchHistory();
  }

  searchFromHistory(keyword: string): void {
    this.keyword = keyword;
    this.doSearch();
  }

  /** Exposes only the persisted redacted V2 proof for the active source search. */
  private refreshSingleSourceV2TraceSummary(): void {
    this.singleSourceV2TraceSummary = '';
    if (!this.singleSourceId) {
      return;
    }
    const summaries = this.sourceManager.getExecutionTraceWorkflowSummaries(this.singleSourceId);
    for (let index = 0; index < summaries.length; index++) {
      const summary = summaries[index];
      if (summary.workflow === LegadoWorkflowKind.SEARCH) {
        this.singleSourceV2TraceSummary =
          `V2 trace：${summary.workflow} · ${summary.transport} · HTTP ${summary.statusCode} · ` +
          `${summary.errorCode} · ${summary.outputSummary}`;
        return;
      }
    }
  }

  @Builder
  private buildSingleSourceV2TraceDisclosure(): void {
    if (this.singleSourceV2TraceSummary.length > 0) {
      Column() {
        Button(this.showSingleSourceV2Trace ? '收起诊断' : '执行诊断')
          .id('novel_search_v2_trace_toggle')
          .type(ButtonType.Normal)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
          })
          .borderRadius(6)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .onClick(() => {
            this.showSingleSourceV2Trace = !this.showSingleSourceV2Trace;
          })
        if (this.showSingleSourceV2Trace) {
          Text(this.singleSourceV2TraceSummary)
            .id('novel_search_v2_trace_detail')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 6 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private async ensureNovelModuleReady(): Promise<void> {
    const initializer = getNovelInitializer();
    if (initializer.isReady()) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const result = await initializer.initialize(context);
    if (!result.success) {
      throw new Error(`NOVEL_MODULE_INITIALIZATION_FAILED:${result.errors.length}`);
    }
  }

  /** A new navigation must not inherit cards from a previous source request. */
  private resetSearchPresentation(): void {
    this.currentSearchTaskId++;
    this.activeSearchKeyword = '';
    this.isSearching = false;
    this.hasSearched = false;
    this.searchErrorMessage = '';
    this.searchResults = [];
    this.sourceResults = [];
    this.currentTabIndex = 0;
    this.completedSourceCount = 0;
    this.totalSourceCount = 0;
    this.searchProgress = '';
  }

  private searchFromSuggestion(keyword: string): void {
    this.keyword = keyword;
    this.doSearch();
  }

  private getSingleSourceSearchSuggestions(): string[] {
    const suggestions = SINGLE_SOURCE_SEARCH_SUGGESTIONS.filter((suggestion: string): boolean => {
      return !this.searchHistory.includes(suggestion);
    });
    if (suggestions.length > 0) {
      return suggestions.slice(0, 3);
    }
    return SINGLE_SOURCE_SEARCH_SUGGESTIONS.slice(0, 3);
  }

  private currentSourceSupportsExplore(): boolean {
    if (!this.singleSourceId) {
      return false;
    }
    const source = this.sourceManager.getSource(this.singleSourceId);
    if (!source || !source.exploreUrl) {
      return false;
    }
    return source.exploreUrl.trim().length > 0;
  }

  private openCurrentSourceExplore(): void {
    if (!this.currentSourceSupportsExplore()) {
      return;
    }
    const params: NovelExplorePageParams = {
      sourceId: this.singleSourceId
    };
    this.pathStack.pushPathByName('NovelExplorePage', params);
  }

  showConcurrentSettings(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: `当前并发数: ${this.maxConcurrentSources}`,
      buttons: [
        { text: '3个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '5个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '10个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '20个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '30个书源', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '50个书源', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then(async (result) => {
      const values = [3, 5, 10, 20, 30, 50];
      this.maxConcurrentSources = values[result.index];
      await this.settingsManager.setMaxConcurrentSources(this.maxConcurrentSources);
      // 如果已选择的书源数量超过新的并发限制，清空选择
      if (this.selectedSourceIds.size > this.maxConcurrentSources) {
        this.selectedSourceIds.clear();
      }
      this.getUIContext().getPromptAction().showToast({ message: `已设置为同时搜索${this.maxConcurrentSources}个书源` });
    }).catch(() => {});
  }

  /**
   * 显示书源选择弹窗
   */
  showSourceSelectorDialog(): void {
    // 获取已启用的可搜索书源
    this.allAvailableSources = this.sourceManager.getEnabledSources()
      .filter(s => s.searchable)
      .sort((a, b) => {
        // 置顶的排在前面
        if (a.isTop && !b.isTop) return -1;
        if (!a.isTop && b.isTop) return 1;
        // 按名称排序
        return a.name.localeCompare(b.name);
      });
    
    // 构建分组列表
    this.buildSourceGroups();
    this.sourceSelectorFilter = '';
    this.applySourceFilter();
    
    // 重置分页状态并加载第一页
    this.sourceSelectorPage = 0;
    this.sourceSelectorHasMore = true;
    this.loadMoreAvailableSources(true);
    this.showSourceSelector = true;
  }
  
  /**
   * 构建书源分组列表
   */
  private buildSourceGroups(): void {
    const groupMap = new Map<string, NovelSourceInfo[]>();
    
    // 置顶书源单独一组
    const pinnedSources: NovelSourceInfo[] = [];
    
    for (const source of this.allAvailableSources) {
      if (source.isTop) {
        pinnedSources.push(source);
      } else {
        const groupName = source.group || '未分组';
        const existing = groupMap.get(groupName);
        if (existing) {
          existing.push(source);
        } else {
          groupMap.set(groupName, [source]);
        }
      }
    }
    
    const groups: SourceGroupInfo[] = [];
    
    // 置顶分组放在最前面
    if (pinnedSources.length > 0) {
      groups.push({
        groupName: '⭐ 置顶书源',
        sources: pinnedSources,
        isExpanded: true,
        selectedCount: this.countSelectedInSources(pinnedSources)
      });
    }
    
    // 添加其他分组（按分组名排序）
    const groupNames = Array.from(groupMap.keys()).sort((a, b) => a.localeCompare(b));
    for (const name of groupNames) {
      const sources = groupMap.get(name);
      if (sources) {
        const groupInfo: SourceGroupInfo = {
          groupName: name,
          sources: sources,
          isExpanded: false,
          selectedCount: this.countSelectedInSources(sources)
        };
        groups.push(groupInfo);
      }
    }
    
    this.sourceGroups = groups;
  }
  
  /**
   * 统计书源列表中已选中的数量
   */
  private countSelectedInSources(sources: NovelSourceInfo[]): number {
    return sources.filter(s => this.selectedSourceIds.has(s.id)).length;
  }
  
  /**
   * 应用书源过滤
   */
  private applySourceFilter(): void {
    if (!this.sourceSelectorFilter.trim()) {
      const result: SourceGroupInfo[] = [];
      for (const g of this.sourceGroups) {
        const info: SourceGroupInfo = {
          groupName: g.groupName,
          sources: g.sources,
          isExpanded: g.isExpanded,
          selectedCount: this.countSelectedInSources(g.sources)
        };
        result.push(info);
      }
      this.filteredSourceGroups = result;
    } else {
      const keyword = this.sourceSelectorFilter.toLowerCase();
      const result: SourceGroupInfo[] = [];
      for (const g of this.sourceGroups) {
        const filtered = g.sources.filter(s => 
          s.name.toLowerCase().includes(keyword) || 
          (s.group && s.group.toLowerCase().includes(keyword))
        );
        if (filtered.length > 0) {
          const info: SourceGroupInfo = {
            groupName: g.groupName,
            sources: filtered,
            isExpanded: true,
            selectedCount: this.countSelectedInSources(filtered)
          };
          result.push(info);
        }
      }
      this.filteredSourceGroups = result;
    }
  }
  
  /**
   * 切换分组展开状态
   */
  private toggleGroupExpanded(groupName: string): void {
    const result: SourceGroupInfo[] = [];
    for (const g of this.filteredSourceGroups) {
      if (g.groupName === groupName) {
        const info: SourceGroupInfo = {
          groupName: g.groupName,
          sources: g.sources,
          isExpanded: !g.isExpanded,
          selectedCount: g.selectedCount
        };
        result.push(info);
      } else {
        result.push(g);
      }
    }
    this.filteredSourceGroups = result;
  }
  
  /**
   * 选中整个分组
   */
  private selectEntireGroup(sources: NovelSourceInfo[]): void {
    const newSet = new Set(this.selectedSourceIds);
    const maxAllowed = this.maxConcurrentSources;
    
    for (const source of sources) {
      if (newSet.size >= maxAllowed) {
        this.getUIContext().getPromptAction().showToast({ message: `最多选择${maxAllowed}个书源` });
        break;
      }
      newSet.add(source.id);
    }
    
    this.selectedSourceIds = newSet;
    this.updateGroupSelectedCounts();
  }
  
  /**
   * 取消选中整个分组
   */
  private deselectEntireGroup(sources: NovelSourceInfo[]): void {
    const newSet = new Set(this.selectedSourceIds);
    for (const source of sources) {
      newSet.delete(source.id);
    }
    this.selectedSourceIds = newSet;
    this.updateGroupSelectedCounts();
  }
  
  /**
   * 更新分组已选计数
   */
  private updateGroupSelectedCounts(): void {
    const result: SourceGroupInfo[] = [];
    for (const g of this.filteredSourceGroups) {
      const info: SourceGroupInfo = {
        groupName: g.groupName,
        sources: g.sources,
        isExpanded: g.isExpanded,
        selectedCount: this.countSelectedInSources(g.sources)
      };
      result.push(info);
    }
    this.filteredSourceGroups = result;
  }
  
  /**
   * 移除字符串中的emoji表情
   */
  private removeEmoji(text: string): string {
    // 移除常见的emoji范围
    return text.replace(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}]/gu, '').trim();
  }
  
  /**
   * 加载更多可用书源（分页）
   */
  private loadMoreAvailableSources(reset: boolean = false): void {
    if (this.sourceSelectorIsLoading && !reset) return;
    if (!this.sourceSelectorHasMore && !reset) return;
    
    this.sourceSelectorIsLoading = true;
    
    const startIndex = reset ? 0 : this.sourceSelectorPage * SOURCE_SELECTOR_PAGE_SIZE;
    const endIndex = startIndex + SOURCE_SELECTOR_PAGE_SIZE;
    const newSources = this.allAvailableSources.slice(startIndex, endIndex);
    
    if (reset) {
      this.displayedAvailableSources = newSources;
      this.sourceSelectorPage = 1;
    } else {
      for (const source of newSources) {
        this.displayedAvailableSources.push(source);
      }
      this.sourceSelectorPage++;
    }
    
    this.sourceSelectorHasMore = endIndex < this.allAvailableSources.length;
    this.sourceSelectorIsLoading = false;
    
    logger.debug(TAG, `加载可用书源: 显示${this.displayedAvailableSources.length}/${this.allAvailableSources.length}`);
  }
  
  /**
   * 检查书源选择器是否需要预加载
   */
  private checkSourceSelectorPreload(index: number): void {
    const threshold = (this.sourceSelectorPage - 1) * SOURCE_SELECTOR_PAGE_SIZE + SOURCE_SELECTOR_PRELOAD_THRESHOLD;
    if (index >= threshold && this.sourceSelectorHasMore && !this.sourceSelectorIsLoading) {
      this.loadMoreAvailableSources();
    }
  }

  /**
   * 切换书源选择状态
   */
  toggleSourceSelection(sourceId: string): void {
    const newSet = new Set(this.selectedSourceIds);
    if (newSet.has(sourceId)) {
      newSet.delete(sourceId);
    } else {
      // 检查是否超过并发限制
      if (newSet.size >= this.maxConcurrentSources) {
        this.getUIContext().getPromptAction().showToast({ message: `最多选择${this.maxConcurrentSources}个书源` });
        return;
      }
      newSet.add(sourceId);
    }
    this.selectedSourceIds = newSet;
    this.updateGroupSelectedCounts();
  }

  /**
   * 清空书源选择
   */
  clearSourceSelection(): void {
    this.selectedSourceIds = new Set();
    this.updateGroupSelectedCounts();
  }

  /**
   * 规范化封面路径：本地文件添加file://前缀
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) {
      return '';
    }
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) {
      return path;
    }
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
  }

  async openBookDetail(book: NovelSearchResult): Promise<void> {
    const sourceManager = getNovelSourceManager();
    const source = sourceManager.getSource(book.sourceId);
    if (source && source.bookSourceType === LegadoBookSourceType.IMAGE) {
      const virtualSource: LegadoMangaVirtualSource | null =
        await getLegadoMangaSourceBridge().ensureVirtualComicSource(source);
      if (!virtualSource || virtualSource.sourceId <= 0) {
        promptAction.showToast({ message: '漫画书源桥接失败，请稍后重试' });
        return;
      }

      const pageType = PageSettingsHelper.getMangaDetailPageType();
      if (pageType === DetailPageType.UNIFIED) {
        const unifiedParams: UnifiedDetailPageParams = {
          contentType: UnifiedContentType.MANGA,
          contentId: book.bookUrl,
          sourceId: String(virtualSource.sourceId),
          sourceName: book.sourceName,
          sourcePkg: virtualSource.pkg,
          cachedTitle: book.name,
          cachedCover: book.coverUrl,
          cachedAuthor: book.author
        };
        this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      } else {
        const mangaParams: MangaDetailPageParams = {
          mangaId: book.bookUrl,
          sourceId: virtualSource.sourceId,
          sourcePkg: virtualSource.pkg,
          cachedTitle: book.name,
          cachedCover: book.coverUrl
        };
        this.pathStack.pushPathByName('MangaDetailPage', mangaParams);
      }
      return;
    }

    // 根据页面设置决定使用哪个详情页
    const pageType = PageSettingsHelper.getNovelDetailPageType();
    
    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.NOVEL,
        contentId: book.bookUrl,
        sourceId: book.sourceId,
        sourceName: book.sourceName,
        cachedTitle: book.name,
        cachedCover: book.coverUrl,
        cachedAuthor: book.author,
        forceNovelNetworkRefresh: sourceManager.shouldBlockLegacyFallback(book.sourceId),
        novelRequestCarrierKey: book.requestCarrierKey,
        novelBookVariable: book.variable
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    } else {
      // 使用原有小说详情页
      const params: NovelDetailPageParams = {
        sourceId: book.sourceId,
        bookUrl: book.bookUrl,
        bookName: book.name,
        author: book.author,
        kind: book.kind,
        intro: book.intro,
        coverUrl: book.coverUrl,
        latestChapterTitle: book.latestChapterTitle,
        wordCount: book.wordCount,
        sourceName: book.sourceName,
        requestCarrierKey: book.requestCarrierKey,
        bookVariable: book.variable
      };
      this.pathStack.pushPathByName('NovelDetailPage', params);
    }
  }

  @Builder
  buildSingleSourceSearchStarter() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

        Column({ space: 4 }) {
          Text('从当前书源开始找书')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.singleSourceName
            ? `仅检索「${this.singleSourceName}」，可输入作品名、作者名或别名。`
            : '仅检索当前书源，可输入作品名、作者名或别名。')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Column({ space: 8 }) {
        Text('试试这些关键词')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.getSingleSourceSearchSuggestions(), (suggestion: string) => {
            Button(suggestion)
              .height(32)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .type(ButtonType.Normal)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
              })
              .borderRadius(16)
              .padding({ left: 12, right: 12 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.searchFromSuggestion(suggestion);
              })
          }, (suggestion: string) => suggestion)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.currentSourceSupportsExplore()) {
        Row({ space: 8 }) {
          Text('不想输入关键词？')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Blank()
          Button('浏览书源发现')
            .height(32)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .type(ButtonType.Normal)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.openCurrentSourceExplore();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Text('当前书源未提供发现页，可直接输入关键词搜索。')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
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
    .margin({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
    .id('novel_single_source_search_starter')
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
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
          Row({ space: 12 }) {
            TextInput({ 
              placeholder: this.singleSourceId ? `在${this.singleSourceName}中搜索...` : '搜索小说、作者...', 
              text: this.keyword 
            })
              .id('novel_search_keyword_input')
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
                this.keyword = value;
              })
              .onSubmit(() => {
                this.doSearch();
              })

            Button('搜索')
              .id('novel_search_submit')
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.doSearch();
              })
          }
          .id(this.singleSourceId.length > 0
            ? `novel_search_single_source_${getLegadoSourceAutomationToken(this.singleSourceId)}`
            : 'novel_search_all_sources')
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding(this.responsive_contentPadding)
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

          // 搜索设置按钮（仅在非单书源模式下显示）
          if (!this.singleSourceId) {
            Row({ space: 8 }) {
              Button(`并发: ${this.maxConcurrentSources}`)
                .borderRadius(8)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .type(ButtonType.Normal)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .border({
                  width: 1,
                  color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                })
                .onClick(() => {
                  this.showConcurrentSettings();
                })
              
              // 书源选择按钮
              Button(this.selectedSourceIds.size > 0 ? `已选: ${this.selectedSourceIds.size}` : '选择书源')
                .borderRadius(8)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .type(ButtonType.Normal)
                .backgroundColor(this.selectedSourceIds.size > 0 
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .fontColor(this.selectedSourceIds.size > 0 
                  ? '#FFFFFF'
                  : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .border({
                  width: 1,
                  color: this.selectedSourceIds.size > 0 
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                })
                .onClick(() => {
                  this.showSourceSelectorDialog();
                })
              
              // 清空选择按钮（仅在有选择时显示）
              if (this.selectedSourceIds.size > 0) {
                Button('清空')
                  .borderRadius(8)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .type(ButtonType.Normal)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .border({
                    width: 1,
                    color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                  })
                  .onClick(() => {
                    this.clearSourceSelection();
                  })
              }
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 12 })
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

          // 搜索结果或历史记录
          if (this.hasSearched && !this.singleSourceId && this.sourceResults.length > 0) {
            // 标签页形式展示各书源结果
            this.buildTabsView()
          } else if (this.singleSourceId && this.searchResults.length > 0) {
            // 单书源搜索结果列表
            List({ space: 8 }) {
              if (this.singleSourceV2TraceSummary.length > 0) {
                ListItem() {
                  this.buildSingleSourceV2TraceDisclosure()
                }
              }
              ForEach(this.searchResults, (book: NovelSearchResult, index: number) => {
                ListItem() {
                  this.buildSearchResultItem(book, index)
                }
              }, (book: NovelSearchResult) => `${book.sourceId}_${book.bookUrl}`)
            }
            .width('100%')
            .height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8, bottom: 16 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .id('novel_search_single_source_results')
          } else if (this.searchErrorMessage.length > 0) {
            Column() {
              Text('搜索未完成')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(this.searchErrorMessage)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme))
                .margin({ top: 4 })
              if (this.singleSourceV2TraceSummary.length > 0) {
                this.buildSingleSourceV2TraceDisclosure()
              }
            }
            .width('100%')
            .id('novel_search_error_state')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.keyword && this.hasSearched && !this.isSearching && this.searchResults.length === 0) {
            // 搜索完成但无结果
            Column() {
              Text('😔')
                .fontSize(48)
                .fontFamily(this.appFontFamily)
                .margin({ bottom: 12 })
              Text('未找到相关小说')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('换个关键词试试吧')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 4 })
              if (this.singleSourceV2TraceSummary.length > 0) {
                this.buildSingleSourceV2TraceDisclosure()
              }
            }
            .width('100%')
            .id('novel_search_no_results_state')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.isSearching && this.sourceResults.length === 0) {
            // 正在搜索（还没有任何结果）
            Column() {
              LoadingProgress()
                .width(48)
                .height(48)
              Text(`搜索中... (${this.completedSourceCount}/${this.totalSourceCount})`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 12 })
            }
            .width('100%')
            .id('novel_search_loading_state')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 搜索历史
            Column() {
              if (this.searchHistory.length > 0) {
                Row() {
                  Text('搜索历史')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  
                  Blank()
                  
                  Text('清空')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .onClick(() => this.clearHistory())
                }
                .width('100%')
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 12 })

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.searchHistory, (historyKeyword: string) => {
                    Row({ space: 8 }) {
                      Text('🕐')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                      Text(historyKeyword)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      
                      SymbolGlyph($r('sys.symbol.xmark'))
                        .fontSize(14)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
                        .onClick(() => {
                          this.removeHistoryItem(historyKeyword);
                        })
                    }
                    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .borderRadius(16)
                    .border({
                      width: 1,
                      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
                    })
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => {
                      this.searchFromHistory(historyKeyword);
                    })
                  })
                }
                .width('100%')
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              }

              if (this.singleSourceId) {
                this.buildSingleSourceSearchStarter()
              } else if (this.searchHistory.length === 0) {
                // 无搜索历史时的提示
                Column() {
                  Text('📚')
                    .fontSize(48)
                    .fontFamily(this.appFontFamily)
                    .margin({ bottom: 12 })
                  Text('输入关键词搜索小说')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                .width('100%')
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
              }
            }
            .width('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignItems(HorizontalAlign.Start)
            .justifyContent(this.singleSourceId
              ? (this.searchHistory.length > 0 ? FlexAlign.SpaceBetween : FlexAlign.Center)
              : FlexAlign.Start)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .alignItems(this.responsive_isLandscape ? HorizontalAlign.Center : HorizontalAlign.Start)
        .padding({ bottom: this.navigationBarHeight })
        
        // 书源选择弹窗
        if (this.showSourceSelector) {
          this.buildSourceSelectorDialog()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.singleSourceId ? this.singleSourceName : '小说搜索',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.resetSearchPresentation();
      const param = context.pathInfo.param as NovelSearchPageParams | null;
      if (param) {
        if (param.sourceId) {
          this.singleSourceId = param.sourceId;
          this.singleSourceName = param.sourceName || '';
          logger.info(TAG, `单书源搜索模式: ${this.singleSourceName}`);
        }
        if (param.keyword) {
          this.keyword = param.keyword;
          this.doSearch();
        }
      }
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  buildTabsView() {
    Column() {
      // 搜索进度提示（如果还在搜索中）
      if (this.isSearching) {
        Row() {
          LoadingProgress()
            .width(16)
            .height(16)
          Text(`搜索中... (${this.completedSourceCount}/${this.totalSourceCount})`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      }
      
      // 标签页
      Tabs({ barPosition: BarPosition.Start, index: this.currentTabIndex }) {
        // "全部"标签页
        TabContent() {
          this.buildAllResultsList()
        }
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .tabBar(this.buildTabBarItem('全部', this.searchResults.length, -1))
        
        // 各书源标签页
        ForEach(this.sourceResults, (sourceResult: SourceSearchResult, index: number) => {
          TabContent() {
            this.buildSourceResultsList(sourceResult)
          }
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .tabBar(this.buildTabBarItem(sourceResult.sourceName, sourceResult.results.length, index))
        }, (sourceResult: SourceSearchResult) => sourceResult.sourceId)
      }
      .barMode(BarMode.Scrollable)
      .barWidth('100%')
      .barHeight(44)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
      .layoutWeight(1)
    }
    .width('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .layoutWeight(1)
  }
  
  @Builder
  buildTabBarItem(title: string, count: number, index: number) {
    Column() {
      Row({ space: 4 }) {
        Text(title)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(this.currentTabIndex === index + 1 || (index === -1 && this.currentTabIndex === 0) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTabIndex === index + 1 || (index === -1 && this.currentTabIndex === 0) 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 80 })
        
        Text(`${count}`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(this.currentTabIndex === index + 1 || (index === -1 && this.currentTabIndex === 0)
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .padding({ left: 12, right: 12 })
      
      // 底部指示条
      Divider()
        .width(this.currentTabIndex === index + 1 || (index === -1 && this.currentTabIndex === 0) ? 24 : 0)
        .height(3)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(2)
        .margin({ top: 6 })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  
  @Builder
  buildAllResultsList() {
    Scroll() {
      Column({ space: 8 }) {
        ForEach(this.searchResults, (book: NovelSearchResult, index: number) => {
          this.buildSearchResultItem(book, index)
        }, (book: NovelSearchResult) => `${book.sourceId}_${book.bookUrl}`)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
      .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }
  
  @Builder
  buildSourceResultsList(sourceResult: SourceSearchResult) {
    if (sourceResult.results.length === 0) {
      Column() {
        Text('该书源暂无结果')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: 8 }) {
          ForEach(sourceResult.results, (book: NovelSearchResult) => {
            this.buildSearchResultItemCompact(book)
          }, (book: NovelSearchResult) => `${book.sourceId}_${book.bookUrl}`)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
        .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
  }
  
  @Builder
  buildSearchResultItemCompact(book: NovelSearchResult) {
    Row() {
      // 封面
      if (book.coverUrl) {
        Image(this.normalizeCoverPath(book.coverUrl))
          .width(60)
          .height(80)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(20)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(60)
        .height(80)
        .borderRadius(6)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      
      // 信息
      Column() {
        Text(book.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(book.author || '未知作者')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 4 })
        
        if (book.latestChapterTitle) {
          Text(book.latestChapterTitle)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(10)
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
    .onClick(() => { void this.openBookDetail(book); })
  }

  @Builder
  buildSearchResultItem(book: NovelSearchResult, automationIndex: number = -1) {
    Row() {
      // 封面
      if (book.coverUrl) {
        Image(this.normalizeCoverPath(book.coverUrl))
          .width(70)
          .height(95)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(24)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(70)
        .height(95)
        .borderRadius(6)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      
      // 信息
      Column() {
        Text(book.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(book.author || '未知作者')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 4 })
        
        if (book.intro) {
          Text(book.intro)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 6 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        Row({ space: 8 }) {
          Text(book.sourceName)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
          
          if (book.latestChapterTitle) {
            Text(book.latestChapterTitle)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
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
    .id(`novel_search_result_${getLegadoSourceAutomationToken(book.sourceId)}_${automationIndex}`)
    .onClick(() => { void this.openBookDetail(book); })
  }

  @Builder
  buildSourceSelectorDialog() {
    // 半透明遮罩层
    Column() {
      // 弹窗内容
      Column() {
        // 标题栏
        Row() {
          Text('选择搜索书源')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`${this.selectedSourceIds.size}/${this.maxConcurrentSources}`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.selectedSourceIds.size >= this.maxConcurrentSources 
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })
        
        // 搜索框
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
          
          TextInput({ placeholder: '搜索书源...', text: this.sourceSelectorFilter })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Color.Transparent)
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .fontSize(14)
            .onChange((value: string) => {
              this.sourceSelectorFilter = value;
              this.applySourceFilter();
            })
          
          if (this.sourceSelectorFilter) {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
              .onClick(() => {
                this.sourceSelectorFilter = '';
                this.applySourceFilter();
              })
          }
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .margin({ left: 16, right: 16, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
        .borderRadius(20)
        
        // 分组列表
        List() {
          ForEach(this.filteredSourceGroups, (group: SourceGroupInfo, groupIndex: number) => {
            // 分组标题
            ListItem() {
              Row() {
                SymbolGlyph(group.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                
                Text(group.groupName)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .margin({ left: 8 })
                
                Text(`(${group.selectedCount}/${group.sources.length})`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .margin({ left: 4 })
                
                Blank()
                
                // 全选/取消按钮
                Text(group.selectedCount === group.sources.length ? '取消全选' : '全选')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .onClick(() => {
                    if (group.selectedCount === group.sources.length) {
                      this.deselectEntireGroup(group.sources);
                    } else {
                      this.selectEntireGroup(group.sources);
                    }
                  })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.toggleGroupExpanded(group.groupName);
              })
            }
            
            // 分组内的书源（展开时显示）- 使用Flex布局允许多个书源一行显示
            if (group.isExpanded) {
              ListItem() {
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(group.sources, (source: NovelSourceInfo, sourceIndex: number) => {
                    Row() {
                      Checkbox({ name: `${group.groupName}_${source.id}` })
                        .select(this.selectedSourceIds.has(source.id))
                        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                        .width(16)
                        .height(16)
                        .onChange(() => {
                          this.toggleSourceSelection(source.id);
                        })
                      
                      Text(this.removeEmoji(source.name))
                        .fontSize(13)
                        .fontFamily(this.appFontFamily)
                        .fontColor(this.selectedSourceIds.has(source.id)
                          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                          : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .margin({ left: 4 })
                      
                      if (source.isTop) {
                        SymbolGlyph($r('sys.symbol.star_fill'))
                          .fontSize(10)
                          .fontColor(['#FFB800'])
                          .margin({ left: 2 })
                      }
                    }
                    .height(32)
                    .padding({ left: 8, right: 10 })
                    .margin({ right: 4, bottom: 4 })
                    .backgroundColor(this.selectedSourceIds.has(source.id)
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20'
                      : ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .borderRadius(16)
                    .onClick(() => {
                      this.toggleSourceSelection(source.id);
                    })
                  }, (source: NovelSourceInfo, index: number) => `${group.groupName}_${source.id}_${this.selectedSourceIds.has(source.id)}_${index}`)
                }
                .width('100%')
                .padding({ left: 16, right: 12, top: 4, bottom: 8 })
              }
              .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ y: -10 }).animation({ duration: 150, curve: Curve.EaseOut })))
            }
          }, (group: SourceGroupInfo, index: number) => `${group.groupName}_${group.isExpanded}_${group.selectedCount}_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        
        // 底部按钮
        Row({ space: 12 }) {
          Button('清空')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .borderRadius(20)
            .type(ButtonType.Normal)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.clearSourceSelection();
            })
          
          Button('确定')
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .borderRadius(20)
            .type(ButtonType.Normal)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.showSourceSelector = false;
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        }
        .width('90%')
        .constraintSize({ maxWidth: 480, maxHeight: '85%' })
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
          offsetY: 6
        })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
      .onClick(() => {})  // 阻止点击事件冒泡
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
    .onClick(() => {
      this.showSourceSelector = false;
    })
  }
}
