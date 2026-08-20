/**
 * 小说发现页
 * 展示书源的发现分类和书籍列表
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelExplorePage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { NovelSearchResult, NovelSourceInfo } from 'manxia_core/src/main/ets/Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import {
  LegadoExploreDetailOpenResult,
  LegadoExploreDetailOpenStatus,
  openLegadoExploreDetail
} from '../Framework/Novel/LegadoExploreDetailNavigator';

const TAG = 'NovelExplorePage';

// 书源选择列表分页常量
const SOURCE_PAGE_SIZE = 100;
const SOURCE_PRELOAD_THRESHOLD = 60;

/**
 * 发现分类
 */
interface ExploreKind {
  title: string;
  url: string;
}

/**
 * 发现页参数
 */
export interface NovelExplorePageParams {
  sourceId?: string;
}

@Component
export struct NovelExplorePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelExplorePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State exploreSources: NovelSourceInfo[] = [];
  private allFilteredSources: NovelSourceInfo[] = [];  // 筛选后的所有书源
  @State displayedSources: NovelSourceInfo[] = [];  // 当前显示的书源（分页）
  private sourcePage: number = 0;
  private sourceHasMore: boolean = true;
  private sourceIsLoading: boolean = false;
  @State selectedSourceId: string = '';
  @State selectedSourceName: string = '';
  @State exploreKinds: ExploreKind[] = [];
  @State selectedKindIndex: number = 0;
  @State books: NovelSearchResult[] = [];
  @State isLoading: boolean = true;
  @State currentPage: number = 1;
  @State hasMore: boolean = true;
  @State showSourcePicker: boolean = false;
  @State showSearchBar: boolean = false;
  @State searchKeyword: string = '';
  
  // 横向滑动切换分类相关状态
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;
  
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private sourceListScroller: Scroller = new Scroller();
  // Every source/kind selection starts a new generation. Async requests must
  // prove they still belong to that generation before mutating this page.
  private exploreSelectionGeneration: number = 0;

  private beginExploreSelection(sourceId: string): number {
    this.exploreSelectionGeneration++;
    logger.debug(TAG,
      '发现页选择代次更新: generation=' + String(this.exploreSelectionGeneration) + ';source=' + sourceId);
    return this.exploreSelectionGeneration;
  }

  private isExploreSelectionCurrent(sourceId: string, generation: number): boolean {
    return generation === this.exploreSelectionGeneration && sourceId === this.selectedSourceId;
  }

  /**
   * 切换到下一个分类（支持循环）
   */
  private switchToNextKind(): void {
    if (this.exploreKinds.length === 0) return;
    const nextIndex = (this.selectedKindIndex + 1) % this.exploreKinds.length;
    this.selectKind(nextIndex);
  }
  
  /**
   * 切换到上一个分类（支持循环）
   */
  private switchToPrevKind(): void {
    if (this.exploreKinds.length === 0) return;
    const prevIndex = (this.selectedKindIndex - 1 + this.exploreKinds.length) % this.exploreKinds.length;
    this.selectKind(prevIndex);
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
  }

  private lifecycle = new PageLifecycleManager('NovelExplorePage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  loadExploreSources(): void {
    this.exploreSources = this.sourceManager.getExploreSources();
    this.filterSources();  // 应用筛选并初始化分页
    if (this.exploreSources.length > 0 && !this.selectedSourceId) {
      this.selectedSourceId = this.exploreSources[0].id;
      this.selectedSourceName = this.exploreSources[0].name;
      const generation = this.beginExploreSelection(this.selectedSourceId);
      this.resetExploreResults();
      void this.loadExploreKinds(this.selectedSourceId, generation);
    } else if (this.selectedSourceId) {
      // 如果已有选中的书源ID，找到对应的名称
      const source = this.exploreSources.find(s => s.id === this.selectedSourceId);
      if (source) {
        this.selectedSourceName = source.name;
        const generation = this.beginExploreSelection(source.id);
        this.resetExploreResults();
        void this.loadExploreKinds(source.id, generation);
      } else {
        this.beginExploreSelection(this.selectedSourceId);
        this.exploreKinds = [];
        this.books = [];
        this.isLoading = false;
      }
    } else {
      this.beginExploreSelection('');
      this.exploreKinds = [];
      this.books = [];
      this.isLoading = false;
    }
  }

  private resetExploreResults(): void {
    this.exploreKinds = [];
    this.selectedKindIndex = 0;
    this.books = [];
    this.currentPage = 1;
    this.hasMore = true;
    this.isLoading = true;
  }
  filterSources(): void {
    if (!this.searchKeyword.trim()) {
      this.allFilteredSources = this.exploreSources;
    } else {
      const keyword = this.searchKeyword.toLowerCase();
      this.allFilteredSources = this.exploreSources.filter(source => 
        source.name.toLowerCase().includes(keyword)
      );
    }
    // 重置分页状态并加载第一页
    this.sourcePage = 0;
    this.sourceHasMore = true;
    this.loadMoreSources(true);
  }
  
  /**
   * 加载更多书源（分页）
   */
  private loadMoreSources(reset: boolean = false): void {
    if (this.sourceIsLoading && !reset) return;
    if (!this.sourceHasMore && !reset) return;
    
    this.sourceIsLoading = true;
    
    const startIndex = reset ? 0 : this.sourcePage * SOURCE_PAGE_SIZE;
    const endIndex = startIndex + SOURCE_PAGE_SIZE;
    const newSources = this.allFilteredSources.slice(startIndex, endIndex);
    
    if (reset) {
      this.displayedSources = newSources;
      this.sourcePage = 1;
    } else {
      for (const source of newSources) {
        this.displayedSources.push(source);
      }
      this.sourcePage++;
    }
    
    this.sourceHasMore = endIndex < this.allFilteredSources.length;
    this.sourceIsLoading = false;
    
    logger.debug(TAG, `加载书源: 显示${this.displayedSources.length}/${this.allFilteredSources.length}`);
  }
  
  /**
   * 检查是否需要预加载
   */
  private checkSourcePreload(index: number): void {
    const threshold = (this.sourcePage - 1) * SOURCE_PAGE_SIZE + SOURCE_PRELOAD_THRESHOLD;
    if (index >= threshold && this.sourceHasMore && !this.sourceIsLoading) {
      this.loadMoreSources();
    }
  }

  async loadExploreKinds(
    requestSourceId: string = this.selectedSourceId,
    requestGeneration: number = this.exploreSelectionGeneration
  ): Promise<void> {
    if (!requestSourceId || !this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
      return;
    }

    try {
      const kinds = await this.sourceManager.getExploreKindsAsync(requestSourceId);
      if (!this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG,
          '丢弃过期发现分类结果: generation=' + String(requestGeneration) + ';source=' + requestSourceId);
        return;
      }
      this.exploreKinds = kinds;
      this.selectedKindIndex = 0;
      this.currentPage = 1;

      if (kinds.length > 0) {
        void this.loadBooks(requestSourceId, requestGeneration, 0, 1);
      } else {
        this.books = [];
        this.hasMore = false;
        this.isLoading = false;
      }
    } catch (error) {
      if (!this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG,
          '忽略过期发现分类异常: generation=' + String(requestGeneration) + ';source=' + requestSourceId);
        return;
      }
      logger.error(TAG, '加载发现分类失败: ' + String(error));
      this.exploreKinds = [];
      this.books = [];
      this.hasMore = false;
      this.isLoading = false;
    }
  }

  async loadBooks(
    requestSourceId: string = this.selectedSourceId,
    requestGeneration: number = this.exploreSelectionGeneration,
    requestKindIndex: number = this.selectedKindIndex,
    requestPage: number = this.currentPage
  ): Promise<void> {
    if (!requestSourceId || !this.isExploreSelectionCurrent(requestSourceId, requestGeneration) ||
      this.exploreKinds.length === 0) {
      return;
    }

    const kind = this.exploreKinds[requestKindIndex];
    if (!kind) {
      if (this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        this.isLoading = false;
      }
      return;
    }

    this.isLoading = true;
    try {
      const results = await this.sourceManager.explore(requestSourceId, kind.url, requestPage);
      if (!this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG,
          '丢弃过期发现书籍结果: generation=' + String(requestGeneration) + ';source=' + requestSourceId);
        return;
      }
      for (const result of results) {
        if (result.sourceId !== requestSourceId) {
          logger.error(TAG,
            '发现结果身份不一致，拒绝写入列表: expected=' + requestSourceId + ';actual=' + result.sourceId);
          return;
        }
      }

      if (requestPage === 1) {
        this.books = results;
      } else {
        this.books = [...this.books, ...results];
      }
      this.hasMore = results.length >= 20;
    } catch (error) {
      if (!this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        logger.debug(TAG,
          '忽略过期发现书籍异常: generation=' + String(requestGeneration) + ';source=' + requestSourceId);
        return;
      }
      logger.error(TAG, '加载发现页失败: ' + String(error));
    } finally {
      if (this.isExploreSelectionCurrent(requestSourceId, requestGeneration)) {
        this.isLoading = false;
      }
    }
  }
  loadMore(): void {
    if (!this.isLoading && this.hasMore) {
      this.currentPage++;
      void this.loadBooks(
        this.selectedSourceId,
        this.exploreSelectionGeneration,
        this.selectedKindIndex,
        this.currentPage
      );
    }
  }

  selectSource(source: NovelSourceInfo): void {
    if (this.selectedSourceId !== source.id) {
      this.selectedSourceId = source.id;
      this.selectedSourceName = source.name;
      const generation = this.beginExploreSelection(source.id);
      this.resetExploreResults();
      this.showSourcePicker = false;
      void this.loadExploreKinds(source.id, generation);
    } else {
      this.showSourcePicker = false;
    }
  }

  selectKind(index: number): void {
    if (this.selectedKindIndex !== index) {
      const requestSourceId = this.selectedSourceId;
      const requestGeneration = this.beginExploreSelection(requestSourceId);
      this.selectedKindIndex = index;
      this.currentPage = 1;
      this.books = [];
      this.hasMore = true;
      void this.loadBooks(requestSourceId, requestGeneration, index, 1);
    }
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

  private async openBookDetail(book: NovelSearchResult): Promise<void> {
    if (book.sourceId.length === 0 || book.sourceId !== this.selectedSourceId) {
      logger.error(
        TAG,
        '拒绝打开跨书源发现结果: selected=' + this.selectedSourceId + ';result=' + book.sourceId
      );
      promptAction.showToast({ message: '书源结果已过期，请刷新后重试' });
      return;
    }
    const selectedSourceIdAtOpen = this.selectedSourceId;
    const result: LegadoExploreDetailOpenResult =
      await openLegadoExploreDetail(this.pathStack, selectedSourceIdAtOpen, book);
    if (result.status === LegadoExploreDetailOpenStatus.REJECTED) {
      promptAction.showToast({ message: result.userMessage });
    }
  }
  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          
          if (this.exploreSources.length === 0) {
            this.buildEmpty()
          } else {
            // 搜索栏（可隐藏，带动画）
            Column() {
              this.buildSearchBar()
            }
            .width('100%')
            .height(this.showSearchBar ? 56 : 0)
            .opacity(this.showSearchBar ? 1 : 0)
            .clip(true)
            .animation({ duration: 200, curve: Curve.EaseOut })
            
            // 书源选择器（下拉式）
            this.buildSourceDropdown()
            
            // 分类选择
            if (this.exploreKinds.length > 0) {
              this.buildKindSelector()
            }
            
            // 书籍列表
            if (this.isLoading && this.books.length === 0) {
              this.buildLoading()
            } else {
              this.buildBookList()
            }
          }
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .padding({ bottom: this.navigationBarHeight })
        
        // 书源选择弹窗
        if (this.showSourcePicker) {
          this.buildSourcePickerOverlay()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '\u53d1\u73b0',
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
      logger.info(TAG, 'HdsNavDestination.onReady \u5df2\u89e6\u53d1');
      const param = context.pathInfo.param as NovelExplorePageParams | null;
      if (param?.sourceId) {
        this.selectedSourceId = param.sourceId;
      }
      this.loadExploreSources();
    })
  }

  @Builder
  buildEmpty() {
    Column() {
      Text('\u6682\u65e0\u652f\u6301\u53d1\u73b0\u529f\u80fd\u7684\u4e66\u6e90')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Text('\u8bf7\u5bfc\u5165\u5305\u542b\u53d1\u73b0\u89c4\u5219\u7684\u4e66\u6e90')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSearchBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ left: 12 })
      
      TextInput({ placeholder: '\u641c\u7d22\u4e66\u6e90...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(36)
        .backgroundColor(Color.Transparent)
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontSize(14)
        .onChange((value: string) => {
          this.searchKeyword = value;
          this.filterSources();
        })
      
      if (this.searchKeyword) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          .margin({ right: 12 })
          .onClick(() => {
            this.searchKeyword = '';
            this.filterSources();
          })
      }
    }
    .width('100%')
    .height(44)
    .margin({ left: 12, right: 12, top: 8, bottom: 8 })
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

  @Builder
  buildSourceDropdown() {
    Row() {
      Text(this.selectedSourceName || '\u9009\u62e9\u4e66\u6e90')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
      
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .rotate({ angle: this.showSourcePicker ? 180 : 0 })
        .animation({ duration: 200 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .margin({ left: 12, right: 12, bottom: 8 })
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
    .onClick(() => {
      this.showSourcePicker = !this.showSourcePicker;
    })
  }

  @Builder
  buildSourcePickerOverlay() {
    Column() {
      // 半透明遮罩
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.3)')
        .onClick(() => {
          this.showSourcePicker = false;
          this.searchKeyword = '';
          this.filterSources();
        })
      
      // 书源列表
      Column() {
        // 标题栏
        Row() {
          Text('\u9009\u62e9\u4e66\u6e90')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`${this.displayedSources.length}/${this.allFilteredSources.length} \u4e2a`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .borderWidth({ bottom: 0.5 })
        .borderColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
        
        // 搜索框
        Row() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
            .margin({ left: 12 })
          
          TextInput({ placeholder: '\u641c\u7d22\u4e66\u6e90...', text: this.searchKeyword })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(Color.Transparent)
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .fontSize(14)
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.filterSources();
            })
          
          if (this.searchKeyword) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
              .margin({ right: 12 })
              .onClick(() => {
                this.searchKeyword = '';
                this.filterSources();
              })
          }
        }
        .width('100%')
        .height(44)
        .margin({ left: 12, right: 12, top: 8, bottom: 8 })
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
        
        // 书源列表
        List({ scroller: this.sourceListScroller }) {
          ForEach(this.displayedSources, (source: NovelSourceInfo, index: number) => {
            ListItem() {
              Row() {
                Text(source.name)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.selectedSourceId === source.id ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .fontWeight(this.selectedSourceId === source.id ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                
                if (this.selectedSourceId === source.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(20)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                }
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .onClick(() => this.selectSource(source))
            }
          })
          
          // 加载更多指示器
          if (this.sourceHasMore) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                Text('\u52a0\u8f7d\u66f4\u591a...')
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .margin({ left: 8 })
              }
              .width('100%')
              .height(40)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
        .onScrollIndex((start: number, end: number) => {
          this.checkSourcePreload(end);
        })
        .onAppear(() => {
          // Scroll to the currently selected source.
          const selectedIndex = this.displayedSources.findIndex(s => s.id === this.selectedSourceId);
          if (selectedIndex > 0) {
            // Delay the scroll until the List has rendered.
            setTimeout(() => {
              this.sourceListScroller.scrollToIndex(selectedIndex, true, ScrollAlign.CENTER);
            }, 100);
          }
        })
      }
      .width('100%')
      .height('60%')
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius({
        topLeft: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme),
        topRight: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)
      })
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: -4
      })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
  }

  @Builder
  buildKindSelector() {
    Scroll() {
      Row({ space: 0 }) {
        ForEach(this.exploreKinds, (kind: ExploreKind, index: number) => {
          Row() {
            Text(kind.title)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.selectedKindIndex === index ? 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) : 
                ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .fontWeight(this.selectedKindIndex === index ? FontWeight.Medium : FontWeight.Normal)
          }
          .padding({ left: 12, right: 12, top: 0, bottom: 0 })
          .height(35)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.selectedKindIndex === index
            ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
            : Color.Transparent)
          .border({
            width: { top: this.selectedKindIndex === index ? 2 : 0, bottom: 0, left: 0, right: 0 },
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          })
          .onClick(() => this.selectKind(index))
          .animation({ duration: 150 })
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(38)
    .margin({ left: 12, right: 12, bottom: 8 })
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

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildBookList() {
    if (this.books.length === 0) {
      Column() {
        Text('暂无书籍')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(this.books, (book: NovelSearchResult) => {
          ListItem() {
            this.buildBookItem(book)
          }
        })
        
        // 加载更多
        if (this.hasMore) {
          ListItem() {
            Row() {
              if (this.isLoading) {
                LoadingProgress()
                  .width(24)
                  .height(24)
                  .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                Text('加载中...')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .margin({ left: 8 })
              } else {
                Text('上拉加载更多')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              }
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
          }
        }
      }
      .width('100%')
      .height('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 16 })
      .onReachEnd(() => this.loadMore())
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
          .onActionStart((event: GestureEvent) => {
            this.swipeStartX = event.offsetX;
            this.swipeOffsetX = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            this.swipeOffsetX = event.offsetX - this.swipeStartX;
          })
          .onActionEnd((event: GestureEvent) => {
            const swipeThreshold = 80;
            if (this.swipeOffsetX < -swipeThreshold) {
              this.switchToNextKind();
            } else if (this.swipeOffsetX > swipeThreshold) {
              this.switchToPrevKind();
            }
            this.swipeOffsetX = 0;
          })
      )
    }
  }

  @Builder
  buildBookItem(book: NovelSearchResult) {
    Row() {
      // 封面
      if (book.coverUrl) {
        Image(this.normalizeCoverPath(book.coverUrl))
          .width(70)
          .height(95)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(20)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
        }
        .width(70)
        .height(95)
        .borderRadius(4)
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
        
        if (book.intro) {
          Text(book.intro)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        if (book.latestChapterTitle) {
          Text(book.latestChapterTitle)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
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
    .margin({ bottom: 8 })
    .onClick(() => {
      void this.openBookDetail(book);
    })
  }
}
