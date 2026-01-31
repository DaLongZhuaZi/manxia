/**
 * 小说搜索页面
 * 使用标签页形式展示各书源搜索结果
 * 支持搜索历史、搜索设置、响应式布局
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSearchPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelSettingsManager, NovelSettingsManager } from '../Framework/Novel/NovelSettingsManager';
import { NovelSearchResult, NovelSourceInfo } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { NovelDetailPageParams, NovelSearchPageParams } from './NovelBookshelfPage';
import { DeviceAdaptationManager, DeviceChangeListener } from '../Framework/Managers/DeviceAdaptationManager';
import { AppColors } from '../Framework/Theme/AppColors';
import { PageSettingsHelper, DetailPageType } from './settings/PageSettingsSubPage';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';

/**
 * 书源搜索结果分组
 */
interface SourceSearchResult {
  sourceId: string;
  sourceName: string;
  results: NovelSearchResult[];
  isLoading: boolean;
  hasError: boolean;
  errorMsg: string;
}

const TAG = 'NovelSearchPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

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
  @State searchHistory: string[] = [];
  @State maxConcurrentSources: number = 5;
  // 单书源搜索模式
  @State singleSourceId: string = '';
  @State singleSourceName: string = '';
  
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
  @State availableSources: NovelSourceInfo[] = [];
  
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
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.boundDeviceChangeHandler) {
      this.deviceManager.removeListener(this.boundDeviceChangeHandler);
      this.boundDeviceChangeHandler = null;
    }
  }

  async doSearch(): Promise<void> {
    if (!this.keyword.trim()) {
      return;
    }

    this.isSearching = true;
    this.hasSearched = true;
    this.searchResults = [];
    this.sourceResults = [];
    this.currentTabIndex = 0;
    this.completedSourceCount = 0;

    try {
      // 保存搜索历史
      await this.settingsManager.addSearchHistory(this.keyword.trim());
      this.searchHistory = this.settingsManager.getSearchHistory();
      
      if (this.singleSourceId) {
        // 单书源搜索模式
        logger.info(TAG, `单书源搜索: ${this.keyword}, 书源: ${this.singleSourceName}`);
        const results = await this.sourceManager.search(this.singleSourceId, this.keyword.trim(), 1);
        this.searchResults = results;
        // 单书源模式不使用标签页
        this.sourceResults = [];
        logger.info(TAG, `搜索结果: ${results.length} 本`);
      } else {
        // 全局搜索模式 - 按书源分组搜索
        logger.info(TAG, `全局搜索: ${this.keyword}, 并发数: ${this.maxConcurrentSources}`);
        await this.doSearchBySource();
      }
    } catch (error) {
      logger.error(TAG, `搜索失败: ${String(error)}`);
    }

    this.isSearching = false;
  }
  
  /**
   * 按书源分组搜索
   */
  async doSearchBySource(): Promise<void> {
    let sourcesToSearch: NovelSourceInfo[];
    
    // 如果用户选择了指定书源，则只搜索选中的书源
    if (this.selectedSourceIds.size > 0) {
      const enabledSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      sourcesToSearch = enabledSources.filter(s => this.selectedSourceIds.has(s.id));
      logger.info(TAG, `使用指定书源搜索: ${sourcesToSearch.map(s => s.name).join(', ')}`);
    } else {
      // 否则使用默认的并发数限制
      const enabledSources = this.sourceManager.getEnabledSources().filter(s => s.searchable);
      sourcesToSearch = enabledSources.slice(0, this.maxConcurrentSources);
    }
    
    this.totalSourceCount = sourcesToSearch.length;
    
    logger.info(TAG, `开始搜索 ${sourcesToSearch.length} 个书源`);
    
    // 分批执行搜索，避免主线程阻塞导致ANR
    // 每批最多10个书源，批次之间添加延迟让UI有时间响应
    const BATCH_SIZE = 10;
    const BATCH_DELAY_MS = 100; // 批次之间的延迟，让UI有时间刷新
    
    for (let batchStart = 0; batchStart < sourcesToSearch.length; batchStart += BATCH_SIZE) {
      const batchEnd = Math.min(batchStart + BATCH_SIZE, sourcesToSearch.length);
      const batchSources = sourcesToSearch.slice(batchStart, batchEnd);
      
      logger.info(TAG, `执行第 ${Math.floor(batchStart / BATCH_SIZE) + 1} 批搜索，书源数: ${batchSources.length}`);
      
      // 并行搜索当前批次的书源
      const batchPromises = batchSources.map(async (source: NovelSourceInfo) => {
        return this.searchSingleSource(source);
      });
      
      await Promise.all(batchPromises);
      
      // 如果还有下一批，添加延迟让UI有时间响应
      if (batchEnd < sourcesToSearch.length) {
        await this.delay(BATCH_DELAY_MS);
      }
    }
    
    logger.info(TAG, `全部搜索完成，共 ${this.sourceResults.length} 个书源有结果，总计 ${this.searchResults.length} 本`);
  }
  
  /**
   * 搜索单个书源
   */
  private async searchSingleSource(source: NovelSourceInfo): Promise<SourceSearchResult> {
    const sourceResult: SourceSearchResult = {
      sourceId: source.id,
      sourceName: source.name,
      results: [],
      isLoading: true,
      hasError: false,
      errorMsg: ''
    };
    
    try {
      const results = await this.sourceManager.search(source.id, this.keyword.trim(), 1);
      sourceResult.results = results;
      sourceResult.isLoading = false;
      
      // 只添加有结果的书源
      if (results.length > 0) {
        // 更新状态 - 添加到结果列表
        this.addSourceResult(sourceResult);
        // 同时更新总结果
        this.searchResults = [...this.searchResults, ...results];
      }
      
      logger.info(TAG, `书源 ${source.name} 搜索完成: ${results.length} 本`);
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
    promptAction.showToast({ message: '搜索历史已清空' });
  }

  async removeHistoryItem(keyword: string): Promise<void> {
    await this.settingsManager.removeSearchHistory(keyword);
    this.searchHistory = this.settingsManager.getSearchHistory();
  }

  searchFromHistory(keyword: string): void {
    this.keyword = keyword;
    this.doSearch();
  }

  showConcurrentSettings(): void {
    promptAction.showActionMenu({
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
      promptAction.showToast({ message: `已设置为同时搜索${this.maxConcurrentSources}个书源` });
    }).catch(() => {});
  }

  /**
   * 显示书源选择弹窗
   */
  showSourceSelectorDialog(): void {
    // 获取已启用的可搜索书源，按置顶和启用状态排序
    this.availableSources = this.sourceManager.getEnabledSources()
      .filter(s => s.searchable)
      .sort((a, b) => {
        // 置顶的排在前面
        if (a.isTop && !b.isTop) return -1;
        if (!a.isTop && b.isTop) return 1;
        // 按名称排序
        return a.name.localeCompare(b.name);
      });
    this.showSourceSelector = true;
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
        promptAction.showToast({ message: `最多选择${this.maxConcurrentSources}个书源` });
        return;
      }
      newSet.add(sourceId);
    }
    this.selectedSourceIds = newSet;
  }

  /**
   * 清空书源选择
   */
  clearSourceSelection(): void {
    this.selectedSourceIds = new Set();
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

  openBookDetail(book: NovelSearchResult): void {
    // 根据页面设置决定使用哪个详情页
    const pageType = PageSettingsHelper.getNovelDetailPageType();
    
    if (pageType === DetailPageType.UNIFIED) {
      // 使用统一详情页
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.NOVEL,
        contentId: book.bookUrl,
        sourceId: book.sourceId,
        cachedTitle: book.name,
        cachedCover: book.coverUrl,
        cachedAuthor: book.author
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
        sourceName: book.sourceName
      };
      this.pathStack.pushPathByName('NovelDetailPage', params);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
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
            TextInput({ 
              placeholder: this.singleSourceId ? `在${this.singleSourceName}中搜索...` : '搜索小说、作者...', 
              text: this.keyword 
            })
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
              .fontFamily(this.appFontFamily)
              .onClick(() => {
                this.doSearch();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding(this.responsive_contentPadding)

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
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 12 })
          }

          // 搜索结果或历史记录
          if (this.hasSearched && !this.singleSourceId && this.sourceResults.length > 0) {
            // 标签页形式展示各书源结果
            this.buildTabsView()
          } else if (this.singleSourceId && this.searchResults.length > 0) {
            // 单书源搜索结果列表
            Scroll() {
              Column({ space: 8 }) {
                ForEach(this.searchResults, (book: NovelSearchResult) => {
                  this.buildSearchResultItem(book)
                }, (book: NovelSearchResult) => `${book.sourceId}_${book.bookUrl}`)
              }
              .width('100%')
              .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
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
            }
            .width('100%')
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
                .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
              } else {
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
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(this.responsive_isLandscape ? HorizontalAlign.Center : HorizontalAlign.Start)
        
        // 书源选择弹窗
        if (this.showSourceSelector) {
          this.buildSourceSelectorDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
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
        title: { mainTitle: this.singleSourceId ? this.singleSourceName : '小说搜索' }
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
        .tabBar(this.buildTabBarItem('全部', this.searchResults.length, -1))
        
        // 各书源标签页
        ForEach(this.sourceResults, (sourceResult: SourceSearchResult, index: number) => {
          TabContent() {
            this.buildSourceResultsList(sourceResult)
          }
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
        ForEach(this.searchResults, (book: NovelSearchResult) => {
          this.buildSearchResultItem(book)
        }, (book: NovelSearchResult) => `${book.sourceId}_${book.bookUrl}`)
      }
      .width('100%')
      .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
      .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(10)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .onClick(() => this.openBookDetail(book))
  }

  @Builder
  buildSearchResultItem(book: NovelSearchResult) {
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .onClick(() => this.openBookDetail(book))
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
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 12 })
        
        // 提示文字
        Text(`最多可选择${this.maxConcurrentSources}个书源，置顶书源排在前面`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 12 })
        
        // 书源列表
        List() {
          ForEach(this.availableSources, (source: NovelSourceInfo) => {
            ListItem() {
              Row() {
                // 选择框
                Checkbox({ name: source.id })
                  .select(this.selectedSourceIds.has(source.id))
                  .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .onChange((isChecked: boolean) => {
                    this.toggleSourceSelection(source.id);
                  })
                
                // 书源信息
                Column() {
                  Row({ space: 6 }) {
                    Text(source.name)
                      .fontSize(15)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    
                    // 置顶标签
                    if (source.isTop) {
                      Text('置顶')
                        .fontSize(10)
                        .fontFamily(this.appFontFamily)
                        .fontColor('#FFFFFF')
                        .backgroundColor('#FF9800')
                        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                        .borderRadius(4)
                    }
                  }
                  .width('100%')
                  
                  if (source.group) {
                    Text(source.group)
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                      .margin({ top: 2 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .onClick(() => {
                this.toggleSourceSelection(source.id);
              })
            }
          }, (source: NovelSourceInfo) => source.id)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({
          strokeWidth: 0.5,
          color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme),
          startMargin: 52,
          endMargin: 20
        })
        
        // 底部按钮
        Row({ space: 12 }) {
          Button('清空选择')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .borderRadius(22)
            .type(ButtonType.Normal)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
            })
            .onClick(() => {
              this.clearSourceSelection();
            })
          
          Button('确定')
            .layoutWeight(1)
            .height(44)
            .fontFamily(this.appFontFamily)
            .borderRadius(22)
            .type(ButtonType.Normal)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.showSourceSelector = false;
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })
      }
      .width('90%')
      .constraintSize({ maxWidth: 500, maxHeight: '80%' })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({
        radius: 20,
        color: 'rgba(0, 0, 0, 0.3)',
        offsetX: 0,
        offsetY: 4
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }).animation({ duration: 200, curve: Curve.EaseOut })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
    .onClick(() => {
      // 点击遮罩层关闭弹窗
      this.showSourceSelector = false;
    })
  }
}
