/**
 * 小说书源管理页面
 * 导入、删除、测试书源
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 改进：
 * 1. 使用标准titleBar + 图标入口
 * 2. 添加书源搜索功能
 * 3. 书源置顶功能
 * 4. 分页加载（首次100个，滚动到60-70时静默加载更多）
 * 5. 点击书源进入专属搜索页面
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSourceManagementPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelSourceValidator, ValidationConfig, DEFAULT_VALIDATION_CONFIG, NovelSourceValidator, SourceValidationResult, SPECIAL_GROUP_NAMES } from '../Framework/Novel/NovelSourceValidator';
import { getNovelLoginManager } from '../Framework/Novel/NovelLoginManager';
import { NovelSourceInfo } from '../Models/NovelModels';
import { LegadoSourceImportResult, LegadoBookSource } from '../Framework/Novel/LegadoSourceTypes';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { NovelSourceManagementPageParams, NovelSearchPageParams } from './NovelBookshelfPage';
import { NovelSourceLoginPageParams } from './NovelSourceLoginPage';
import { ValidationProgressDialog, ValidationProgressController, ValidationProgressInfo } from '../Framework/Components/ValidationProgressDialog';
import { GroupManagementDialog, GroupInfo, GroupOperationCallback, SplitCondition } from '../Framework/Components/GroupManagementDialog';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';
import { FileEditorParams } from './FileEditorPage';

const TAG = 'NovelSourceManagementPage';

// 分页加载常量
const PAGE_SIZE = 100;  // 每次加载数量
const PRELOAD_THRESHOLD = 60;  // 预加载触发阈值（当显示到第60-70个时开始加载下一批）

/**
 * 书源操作菜单项
 */
interface SourceMenuItem {
  title: string;
  icon: Resource;
  action: string;
}

const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct NovelSourceManagementPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelSourceManagementPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 所有书源（内存中完整列表）
  private allSources: NovelSourceInfo[] = [];
  // 当前显示的书源（分页加载）
  @State displayedSources: NovelSourceInfo[] = [];
  // 筛选后的书源（用于搜索和分组筛选）
  @State filteredSources: NovelSourceInfo[] = [];
  @State isLoading: boolean = true;
  @State showImportDialog: boolean = false;
  @State importText: string = '';
  @State isImporting: boolean = false;
  @State isValidating: boolean = false;
  @State validationProgress: string = '';
  @State sourceGroups: string[] = [];
  @State selectedGroup: string = '';
  // 分组统计（分组名 -> 书源数量）
  @State groupCounts: Map<string, number> = new Map();
  // 书源搜索
  @State searchKeyword: string = '';
  @State showSearchBar: boolean = false;
  // 多选模式
  @State isMultiSelectMode: boolean = false;
  @State selectedSourceIds: Set<string> = new Set();
  // 操作加载状态（导入/删除等）
  @State isOperating: boolean = false;
  @State operatingMessage: string = '';
  // 统计数据（用于强制刷新）
  @State totalSourceCount: number = 0;
  @State enabledSourceCount: number = 0;
  @State searchableSourceCount: number = 0;
  @State validatedSourceCount: number = 0;  // 已验证的书源数量
  @State workingSourceCount: number = 0;    // 正常工作的书源数量
  // 分页加载状态
  private currentPage: number = 0;
  private hasMoreData: boolean = true;
  private isLoadingMore: boolean = false;
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private listScroller: Scroller = new Scroller();
  // 校验进度对话框
  private validationProgressController: ValidationProgressController | null = null;
  private validationDialogController: CustomDialogController | null = null;
  // 存储最近一次校验的失效书源ID列表
  private lastValidationInvalidSourceIds: string[] = [];
  // 书源长按菜单状态
  @State showSourceContextMenu: boolean = false;
  @State contextMenuSource: NovelSourceInfo | null = null;

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

  private lifecycle = new PageLifecycleManager('NovelSourceManagementPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  loadSources(): void {
    this.isLoading = true;
    // 获取所有书源，按置顶和权重排序
    const sources = this.sourceManager.getAllSources();
    // 置顶的书源排在前面（weight越高越靠前）
    this.allSources = sources.sort((a, b) => b.weight - a.weight);
    
    // 更新统计数据
    this.totalSourceCount = this.allSources.length;
    this.enabledSourceCount = this.allSources.filter(s => s.enabled).length;
    this.searchableSourceCount = this.allSources.filter(s => s.searchable).length;
    
    // 统计工作正常的书源（分组包含"✅工作正常"）
    const workingSources = this.allSources.filter(s => 
      s.group && s.group.includes(SPECIAL_GROUP_NAMES.WORKING)
    );
    this.workingSourceCount = workingSources.length;
    
    // 错误分组标记前缀
    const errorGroupPrefixes = ['🔍', '🔗', '⏱', '🔒', '📡', '❌', '校验', '💥', '🚫', '⚠️', '🌐', '📜'];
    // 已验证：分组中包含错误标记的书源（验证失败）+ 工作正常的书源
    const failedSources = this.allSources.filter(s => {
      if (!s.group) return false;
      return errorGroupPrefixes.some(prefix => s.group!.includes(prefix));
    });
    this.validatedSourceCount = failedSources.length + workingSources.length;
    
    // 统计未分组的书源数量
    const ungroupedCount = this.allSources.filter(s => !s.group || s.group.trim() === '').length;
    
    // 提取所有分组
    const groupSet = new Set<string>();
    this.allSources.forEach(s => {
      if (s.group) {
        // 分组可能是逗号分隔的多个分组
        const groups = s.group.split(',').map(g => g.trim()).filter(g => g);
        groups.forEach(g => groupSet.add(g));
      }
    });
    
    // 构建分组列表，添加虚拟分组
    const realGroups = Array.from(groupSet).sort();
    this.sourceGroups = [];
    
    // 统计每个分组的书源数量
    const newGroupCounts = new Map<string, number>();
    
    // 添加"未分组"虚拟分组（如果有未分组的书源）
    if (ungroupedCount > 0) {
      this.sourceGroups.push(SPECIAL_GROUP_NAMES.UNGROUPED);
      newGroupCounts.set(SPECIAL_GROUP_NAMES.UNGROUPED, ungroupedCount);
    }
    
    // 添加真实分组并统计数量
    for (const g of realGroups) {
      this.sourceGroups.push(g);
      // 统计该分组的书源数量
      const count = this.allSources.filter(s => {
        if (!s.group) return false;
        const groups = s.group.split(',').map(grp => grp.trim());
        return groups.includes(g);
      }).length;
      newGroupCounts.set(g, count);
    }
    
    this.groupCounts = newGroupCounts;
    
    // 应用筛选并重置分页
    this.applyFilter();
    this.isLoading = false;
  }

  applyFilter(): void {
    let result = this.allSources;
    
    // 分组筛选
    if (this.selectedGroup) {
      if (this.selectedGroup === SPECIAL_GROUP_NAMES.UNGROUPED) {
        // "未分组"虚拟分组：筛选没有分组的书源
        result = result.filter(s => !s.group || s.group.trim() === '');
      } else {
        // 真实分组：筛选分组包含选中分组的书源（支持多分组）
        result = result.filter(s => {
          if (!s.group) return false;
          const groups = s.group.split(',').map(g => g.trim());
          return groups.includes(this.selectedGroup);
        });
      }
    }
    
    // 搜索筛选
    if (this.searchKeyword.trim()) {
      const keyword = this.searchKeyword.toLowerCase();
      result = result.filter(s => 
        s.name.toLowerCase().includes(keyword) || 
        (s.group && s.group.toLowerCase().includes(keyword)) ||
        s.url.toLowerCase().includes(keyword)
      );
    }
    
    this.filteredSources = result;
    // 重置分页状态
    this.currentPage = 0;
    this.hasMoreData = true;
    // 加载第一页
    this.loadMoreSources(true);
  }

  /**
   * 加载更多书源（分页）
   * @param reset 是否重置列表
   */
  loadMoreSources(reset: boolean = false): void {
    if (this.isLoadingMore && !reset) return;
    if (!this.hasMoreData && !reset) return;
    
    this.isLoadingMore = true;
    
    const startIndex = reset ? 0 : this.currentPage * PAGE_SIZE;
    const endIndex = startIndex + PAGE_SIZE;
    const newSources = this.filteredSources.slice(startIndex, endIndex);
    
    if (reset) {
      this.displayedSources = newSources;
      this.currentPage = 1;
    } else {
      // 追加新数据，不触发UI闪烁
      for (const source of newSources) {
        this.displayedSources.push(source);
      }
      this.currentPage++;
    }
    
    this.hasMoreData = endIndex < this.filteredSources.length;
    this.isLoadingMore = false;
    
    logger.debug(TAG, `加载书源: 显示${this.displayedSources.length}/${this.filteredSources.length}`);
  }

  /**
   * 检查是否需要预加载
   */
  checkPreload(index: number): void {
    // 当滚动到当前页的第60-70个时，静默加载下一批
    const threshold = (this.currentPage - 1) * PAGE_SIZE + PRELOAD_THRESHOLD;
    if (index >= threshold && this.hasMoreData && !this.isLoadingMore) {
      logger.debug(TAG, `触发预加载: index=${index}, threshold=${threshold}`);
      this.loadMoreSources();
    }
  }

  selectGroup(group: string): void {
    this.selectedGroup = group;
    this.applyFilter();
  }

  /**
   * 搜索书源
   */
  onSearchChange(keyword: string): void {
    this.searchKeyword = keyword;
    this.applyFilter();
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 隐藏的WebView组件，用于执行JS网络请求
        LegadoWebViewComponent()
        
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层：预留标题栏高度
        Column() {
          // 标题栏占位
          Blank().height(TITLE_BAR_HEIGHT_MINI)
          
          // 搜索栏（可隐藏，带动画）
          Column() {
            this.buildSearchBar()
          }
          .width('100%')
          .height(this.showSearchBar ? 56 : 0)
          .opacity(this.showSearchBar ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })
          
          // 多选操作栏
          if (this.isMultiSelectMode) {
            this.buildMultiSelectBar()
          }
          
          // 统计信息和分组筛选
          this.buildStats()
          
          // 书源列表
          if (this.isLoading) {
            this.buildLoading()
          } else if (this.allSources.length === 0) {
            this.buildEmpty()
          } else {
            this.buildSourceList()
          }
        }
        .width('100%')
        .height('100%')

        // 导入对话框
        if (this.showImportDialog) {
          this.buildImportDialog()
        }
        
        // 操作加载遮罩层
        if (this.isOperating) {
          this.buildOperatingOverlay()
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
          mainTitle: '书源管理'
        },
        menu: {
          value: [{
            content: {
              label: '搜索',
              icon: $r('sys.symbol.magnifyingglass'),
              isEnabled: true,
              action: () => { 
                this.showSearchBar = !this.showSearchBar;
                if (!this.showSearchBar) {
                  this.searchKeyword = '';
                  this.applyFilter();
                }
              }
            }
          }, {
            content: {
              label: this.isMultiSelectMode ? '取消多选' : '多选',
              icon: $r('sys.symbol.checkmark'),
              isEnabled: true,
              action: () => { this.toggleMultiSelectMode(); }
            }
          }, {
            content: {
              label: '导入书源',
              icon: $r('sys.symbol.folder'),
              isEnabled: true,
              action: () => { this.showImportOptions(); }
            }
          }, {
            content: {
              label: '校验书源',
              icon: $r('sys.symbol.wrench_arrow_counterclockwise'),
              isEnabled: true,
              action: () => { this.validateAllSources(); }
            }
          }, {
            content: {
              label: '更多',
              icon: $r('sys.symbol.more'),
              isEnabled: true,
              action: () => { this.showMoreOptions(); }
            }
          }]
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.loadSources();
    })
  }

  @Builder
  buildTitleBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ left: 16 })
        .onClick(() => this.pathStack.pop())
      
      Text('书源管理')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ left: 16 })
      
      Blank()
      
      // 搜索图标
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ right: 12 })
        .onClick(() => {
          this.showSearchBar = !this.showSearchBar;
          if (!this.showSearchBar) {
            this.searchKeyword = '';
            this.applyFilter();
          }
        })
      
      // 导入图标
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ right: 12 })
        .onClick(() => this.showImportOptions())
      
      // 校验图标
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ right: 12 })
        .onClick(() => this.validateAllSources())
      
      // 更多操作图标
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(24)
        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
        .margin({ right: 16 })
        .onClick(() => this.showMoreOptions())
    }
    .width('100%')
    .height(56)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  buildSearchBar() {
    Row() {
      TextInput({ placeholder: '搜索书源名称、分组或网址...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(20)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.onSearchChange(value);
        })
      
      if (this.searchKeyword) {
        Text('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 12 })
          .onClick(() => {
            this.searchKeyword = '';
            this.applyFilter();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  @Builder
  buildMultiSelectBar() {
    Column() {
      // 选中统计和操作按钮
      Row() {
        Text(`已选择 ${this.selectedSourceIds.size} 个`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        // 全选按钮
        Text('全选')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .borderRadius(16)
          .margin({ right: 8 })
          .onClick(() => this.selectAll())
        
        // 反选按钮
        Text('反选')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => this.invertSelection())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      
      // 批量操作按钮 - 第一排
      Row() {
        // 批量置顶
        Button('置顶')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchPinSources(true))
        
        // 批量取消置顶
        Button('取消置顶')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchPinSources(false))
        
        // 批量启用
        Button('启用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#52C41A')
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchSetEnabled(true))
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      
      // 批量操作按钮 - 第二排
      Row() {
        // 批量禁用
        Button('禁用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchSetEnabled(false))
        
        // 批量校验
        Button('校验')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF9800')
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchValidateSources())
        
        // 批量删除
        Button('删除')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.batchDeleteSources())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      
      // 批量操作按钮 - 第三排（分组管理）
      Row() {
        // 添加到分组
        Button('添加分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#9C27B0')
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.showAddToGroupDialog())
        
        // 从分组移除
        Button('移除分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.showRemoveFromGroupDialog())
        
        // 分组管理
        Button('管理分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.showGroupManageDialog())
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  /**
   * 显示导入选项菜单
   */
  showImportOptions(): void {
    promptAction.showActionMenu({
      title: '导入书源',
      buttons: [
        { text: '从文件导入', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '从剪贴板导入', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.importFromFile();
      } else if (result.index === 1) {
        this.showImportDialog = true;
      }
    }).catch(() => {});
  }

  /**
   * 显示更多操作菜单
   */
  showMoreOptions(): void {
    promptAction.showActionMenu({
      title: '更多操作',
      buttons: [
        { text: '替换规则', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '批量启用', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '批量禁用', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.goToReplaceRules();
      } else if (result.index === 1) {
        this.batchEnableSources(true);
      } else if (result.index === 2) {
        this.batchEnableSources(false);
      }
    }).catch(() => {});
  }

  /**
   * 批量启用/禁用书源
   */
  async batchEnableSources(enabled: boolean): Promise<void> {
    const sources = this.filteredSources;
    let count = 0;
    for (const source of sources) {
      if (source.enabled !== enabled) {
        await this.sourceManager.setSourceEnabled(source.id, enabled);
        count++;
      }
    }
    promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 个书源` });
    this.loadSources();
  }

  goToReplaceRules(): void {
    this.pathStack.pushPathByName('NovelReplaceRulePage', null);
  }

  @Builder
  buildStats() {
    Column() {
      Row() {
        Column() {
          Text(String(this.totalSourceCount))
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Row() {
            Text('总书源')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Text(` (${this.enabledSourceCount}已启用)`)
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          }
          .margin({ top: 4 })
        }
        .layoutWeight(1)
        
        Column() {
          Text(`${this.workingSourceCount}/${this.validatedSourceCount}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_success', this.themeState.currentTheme))
          Text('正常工作/已验证')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      
      // 分组筛选
      if (this.sourceGroups.length > 0) {
        Scroll() {
          Row() {
            // 全部按钮
            Text('全部')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(this.selectedGroup === '' ? '#FFFFFF' : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .backgroundColor(this.selectedGroup === '' ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(16)
              .margin({ right: 8 })
              .onClick(() => this.selectGroup(''))
            
            // 分组按钮
            ForEach(this.sourceGroups, (group: string) => {
              Text(`${group}(${this.groupCounts.get(group) || 0})`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.selectedGroup === group ? '#FFFFFF' : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .backgroundColor(this.selectedGroup === group ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(16)
                .margin({ right: 8 })
                .onClick(() => this.selectGroup(group))
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ top: 8 })
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildOperatingOverlay() {
    Column() {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        
        Text(this.operatingMessage || '处理中...')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 16 })
      }
      .padding(32)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .borderRadius(16)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.5)')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildEmpty() {
    Column() {
      Text('暂无书源')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Text('点击右上角"导入"添加书源')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .margin({ top: 8 })
      
      Button('从剪贴板导入')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(20)
        .margin({ top: 24 })
        .onClick(() => this.importFromClipboard())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildSourceList() {
    List({ scroller: this.listScroller }) {
      ForEach(this.displayedSources, (source: NovelSourceInfo, index: number) => {
        ListItem() {
          this.buildSourceItem(source, index)
        }
        .swipeAction({
          end: this.buildSwipeActions(source)
        })
      })
      
      // 加载更多指示器
      if (this.hasMoreData) {
        ListItem() {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text(`加载中... (${this.displayedSources.length}/${this.filteredSources.length})`)
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
    .padding({ top: 8 })
    .onScrollIndex((start: number, end: number) => {
      // 检查是否需要预加载
      this.checkPreload(end);
    })
  }

  @Builder
  buildSourceItem(source: NovelSourceInfo, index: number) {
    Row() {
      // 多选模式下显示复选框
      if (this.isMultiSelectMode) {
        Checkbox({ name: source.id, group: 'sourceGroup' })
          .select(this.selectedSourceIds.has(source.id))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ right: 8 })
          .onChange((isChecked: boolean) => {
            this.toggleSourceSelection(source.id, isChecked);
          })
      }
      
      // 置顶指示（权重 > 0 表示置顶）
      if (source.weight > 0) {
        Text('⭐')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .margin({ right: 4 })
      }
      
      // 状态指示
      Column()
        .width(4)
        .height(40)
        .borderRadius(2)
        .backgroundColor(source.enabled ? '#52C41A' : '#D9D9D9')
      
      // 信息
      Column() {
        Row() {
          Text(source.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          
          if (source.searchable) {
            Text('搜索')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(2)
              .margin({ left: 8 })
          }
          
          if (source.hasExplore) {
            Text('发现')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor('#52C41A')
              .backgroundColor('#F6FFED')
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .borderRadius(2)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        
        Text(source.group || '未分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
        
        Text(source.url)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      
      // 开关
      Toggle({ type: ToggleType.Switch, isOn: source.enabled })
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .onChange((isOn: boolean) => {
          this.toggleSource(source, isOn);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .margin({ left: 12, right: 12, bottom: 8 })
    .borderRadius(8)
    .onClick(() => {
      if (this.isMultiSelectMode) {
        // 多选模式下点击切换选中状态
        this.toggleSourceSelection(source.id, !this.selectedSourceIds.has(source.id));
      } else {
        // 点击书源进入专属搜索页面
        this.goToSourceSearch(source);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (!this.isMultiSelectMode) {
            this.showSourceActionMenu(source);
          }
        })
    )
    .bindPopup(this.showSourceContextMenu && this.contextMenuSource?.id === source.id, {
      builder: this.buildSourceContextMenu(source),
      placement: Placement.Bottom,
      popupColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme),
      enableArrow: true,
      autoCancel: true,
      onStateChange: (e) => {
        if (!e.isVisible) {
          this.hideSourceContextMenu();
        }
      }
    })
  }

  /**
   * 构建书源上下文菜单
   */
  @Builder
  buildSourceContextMenu(source: NovelSourceInfo) {
    Column({ space: 0 }) {
      // 搜索按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          Text('搜索')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const sourceToSearch = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToSearch) {
          this.goToSourceSearch(sourceToSearch);
        }
      })

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 编辑按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('编辑')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const sourceToEdit = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToEdit) {
          this.editSourceConfig(sourceToEdit);
        }
      })

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 调试按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          Text('调试')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const sourceToDebug = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToDebug) {
          this.goToDebugSource(sourceToDebug);
        }
      })

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 置顶按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.pin'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          Text(source.weight > 0 ? '取消置顶' : '置顶')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const sourceToPin = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToPin) {
          this.toggleSourcePin(sourceToPin);
        }
      })

      Divider().color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      // 删除按钮
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme)])
          Text('删除')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        const sourceToDelete = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToDelete) {
          this.deleteSource(sourceToDelete);
        }
      })
    }
    .width(120)
    .borderRadius(8)
  }

  /**
   * 进入书源专属搜索页面
   */
  goToSourceSearch(source: NovelSourceInfo): void {
    // 传递sourceId到搜索页面，让搜索页面只使用这个书源
    const params: NovelSearchPageParams = {
      keyword: '',
      sourceId: source.id,
      sourceName: source.name
    };
    this.pathStack.pushPathByName('NovelSearchPage', params);
  }

  /**
   * 进入书源调试页面
   */
  goToDebugSource(source: NovelSourceInfo): void {
    // 通过AppStorage传递参数
    AppStorage.setOrCreate('NovelSourceDebugPageParams', { sourceId: source.id });
    this.pathStack.pushPathByName('NovelSourceDebugPage', null);
  }

  @Builder
  buildSwipeActions(source: NovelSourceInfo) {
    Row() {
      Button('删除')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
        .width(80)
        .height('100%')
        .onClick(() => this.deleteSource(source))
    }
  }

  @Builder
  buildImportDialog() {
    Column() {
      // 遮罩
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          if (!this.isImporting) {
            this.showImportDialog = false;
          }
        })
      
      // 对话框
      Column() {
        Text('导入书源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .margin({ top: 20 })
        
        Text('粘贴Legado书源JSON')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 8 })
        
        TextArea({ placeholder: '粘贴书源JSON...', text: this.importText })
          .width('100%')
          .height(200)
          .margin({ top: 16 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.importText = value;
          })
        
        Row() {
          Button('从剪贴板粘贴')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .borderRadius(20)
            .layoutWeight(1)
            .margin({ right: 8 })
            .onClick(() => this.pasteFromClipboard())
          
          Button(this.isImporting ? '导入中...' : '导入')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(this.isImporting ? 
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) : 
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(20)
            .layoutWeight(1)
            .margin({ left: 8 })
            .enabled(!this.isImporting)
            .onClick(() => this.doImport())
        }
        .width('100%')
        .margin({ top: 16 })
        
        Button('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(20)
          .width('100%')
          .margin({ top: 12, bottom: 20 })
          .onClick(() => {
            this.showImportDialog = false;
            this.importText = '';
          })
      }
      .width('90%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .borderRadius(16)
      .padding({ left: 20, right: 20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  async pasteFromClipboard(): Promise<void> {
    try {
      const pasteData: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = await pasteData.getData();
      if (data.hasType(pasteboard.MIMETYPE_TEXT_PLAIN)) {
        const text: string = data.getPrimaryText();
        if (text) {
          this.importText = text;
        }
      }
    } catch (error) {
      logger.error(TAG, `读取剪贴板失败: ${String(error)}`);
      promptAction.showToast({ message: '读取剪贴板失败' });
    }
  }

  async importFromClipboard(): Promise<void> {
    await this.pasteFromClipboard();
    if (this.importText) {
      this.showImportDialog = true;
    }
  }

  async doImport(): Promise<void> {
    if (!this.importText.trim()) {
      promptAction.showToast({ message: '请输入书源JSON' });
      return;
    }

    this.isImporting = true;
    this.showImportDialog = false;
    this.isOperating = true;
    this.operatingMessage = '正在导入书源...';
    
    try {
      const results = await this.sourceManager.importFromJSON(this.importText);
      
      const successCount = results.filter(r => r.success).length;
      const failCount = results.filter(r => !r.success).length;
      
      if (successCount > 0) {
        this.loadSources();
        this.importText = '';
        promptAction.showToast({ 
          message: `成功导入 ${successCount} 个书源${failCount > 0 ? `，${failCount} 个失败` : ''}` 
        });
      } else {
        promptAction.showToast({ message: '导入失败，请检查JSON格式' });
      }
    } catch (error) {
      logger.error(TAG, `导入失败: ${String(error)}`);
      promptAction.showToast({ message: '导入失败: ' + String(error) });
    }
    
    this.isImporting = false;
    this.isOperating = false;
    this.operatingMessage = '';
  }

  async toggleSource(source: NovelSourceInfo, enabled: boolean): Promise<void> {
    await this.sourceManager.setSourceEnabled(source.id, enabled);
    this.loadSources();
  }

  deleteSource(source: NovelSourceInfo): void {
    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除书源“${source.name}”吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        this.isOperating = true;
        this.operatingMessage = '正在删除...';
        try {
          await this.sourceManager.deleteSource(source.id);
          this.loadSources();
          promptAction.showToast({ message: '已删除' });
        } catch (error) {
          logger.error(TAG, `删除失败: ${String(error)}`);
          promptAction.showToast({ message: '删除失败' });
        }
        this.isOperating = false;
        this.operatingMessage = '';
      }
    });
  }

  /**
   * 从文件导入书源（支持多文件选择，最多99个）
   */
  async importFromFile(): Promise<void> {
    try {
      // 获取UIAbilityContext
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!context) {
        promptAction.showToast({ message: '无法获取应用上下文' });
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }

      // 创建文档选择器
      const documentPicker = new picker.DocumentViewPicker(context);
      
      // 设置选择选项 - 允许选择多个书源文件（最多99个）
      // 支持.json和.txt格式（txt文件内容也应为JSON格式）
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 99,
        fileSuffixFilters: ['.json', '.txt'],
      };

      logger.info(TAG, '打开文件选择器，选择书源文件（支持.json和.txt，支持多选）');
      
      // 打开文件选择器
      const selectResult = await documentPicker.select(selectOptions);
      
      if (!selectResult || !selectResult.length || selectResult.length === 0) {
        logger.info(TAG, '用户取消了文件选择');
        return;
      }

      const fileCount = selectResult.length;
      logger.info(TAG, `用户选择了 ${fileCount} 个文件`);
      
      // 显示加载状态
      this.isOperating = true;
      this.operatingMessage = `正在读取 ${fileCount} 个文件...`;
      
      let totalSuccessCount = 0;
      let totalFailCount = 0;
      let fileProcessed = 0;
      
      // 逐个处理选中的文件
      for (const fileUri of selectResult) {
        fileProcessed++;
        this.operatingMessage = `正在处理文件 ${fileProcessed}/${fileCount}...`;
        logger.info(TAG, `处理文件 ${fileProcessed}/${fileCount}: ${fileUri}`);
        
        try {
          // 读取文件内容
          const file: fs.File = fs.openSync(fileUri, fs.OpenMode.READ_ONLY);
          const stat: fs.Stat = fs.statSync(file.fd);
          const fileSize: number = stat.size;
          logger.info(TAG, `文件大小: ${fileSize} 字节`);
          
          // 根据文件大小动态分配缓冲区（最大50MB）
          const maxBufferSize = 50 * 1024 * 1024;
          const bufferSize = Math.min(fileSize, maxBufferSize);
          const buffer = new ArrayBuffer(bufferSize);
          const readLen: number = fs.readSync(file.fd, buffer);
          fs.closeSync(file);
          
          if (readLen < fileSize) {
            logger.warn(TAG, `文件过大，只读取了 ${readLen}/${fileSize} 字节`);
          }
          
          // 使用TextDecoder正确解码UTF-8
          const uint8Array = new Uint8Array(buffer, 0, readLen);
          const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
          const jsonContent = decoder.decode(uint8Array);
          
          logger.debug(TAG, `读取到JSON内容，长度: ${jsonContent.length}`);
          
          // 更新加载状态
          this.operatingMessage = `正在导入文件 ${fileProcessed}/${fileCount} 的书源...`;
          
          // 导入书源
          const results = await this.sourceManager.importFromJSON(jsonContent);
          
          const successCount = results.filter((r: LegadoSourceImportResult) => r.success).length;
          const failCount = results.filter((r: LegadoSourceImportResult) => !r.success).length;
          
          totalSuccessCount += successCount;
          totalFailCount += failCount;
          
          logger.info(TAG, `文件 ${fileProcessed} 导入完成: 成功${successCount}个, 失败${failCount}个`);
        } catch (fileError) {
          logger.error(TAG, `处理文件 ${fileUri} 失败: ${String(fileError)}`);
          // 继续处理下一个文件
        }
      }
      
      // 刷新书源列表
      if (totalSuccessCount > 0) {
        this.loadSources();
      }
      
      // 显示最终结果
      if (totalSuccessCount > 0) {
        const message = fileCount > 1 
          ? `从 ${fileCount} 个文件成功导入 ${totalSuccessCount} 个书源${totalFailCount > 0 ? `，${totalFailCount} 个失败` : ''}`
          : `成功导入 ${totalSuccessCount} 个书源${totalFailCount > 0 ? `，${totalFailCount} 个失败` : ''}`;
        promptAction.showToast({ message });
        logger.info(TAG, `书源导入完成: 共处理${fileCount}个文件, 成功${totalSuccessCount}个书源, 失败${totalFailCount}个`);
      } else {
        promptAction.showToast({ message: '导入失败，请检查JSON格式' });
        logger.error(TAG, '书源导入失败: 没有成功导入任何书源');
      }
    } catch (error) {
      logger.error(TAG, `从文件导入书源失败: ${String(error)}`);
      promptAction.showToast({ message: '导入失败: ' + String(error) });
    }
    
    this.isOperating = false;
    this.operatingMessage = '';
  }

  // ==================== 书源操作菜单 ====================

  /**
   * 显示书源操作菜单（使用popup形式）
   */
  showSourceActionMenu(source: NovelSourceInfo): void {
    logger.info(TAG, `显示书源操作菜单: ${source.name}`);
    this.contextMenuSource = source;
    this.showSourceContextMenu = true;
  }

  /**
   * 隐藏书源操作菜单
   */
  hideSourceContextMenu(): void {
    this.showSourceContextMenu = false;
    this.contextMenuSource = null;
  }

  /**
   * 编辑书源配置文件
   */
  editSourceConfig(source: NovelSourceInfo): void {
    try {
      logger.info(TAG, `编辑书源配置: ${source.name} (id: ${source.id})`);
      
      // 获取书源的原始JSON
      const rawSource = this.sourceManager.getSource(source.id);
      if (!rawSource) {
        promptAction.showToast({ message: '书源不存在' });
        return;
      }
      
      // 将书源对象转换为JSON字符串
      const sourceJson = JSON.stringify(rawSource, null, 2);
      
      // 导航到文件编辑器页面，传入内容而非文件路径
      const params: FileEditorParams = {
        content: sourceJson,
        language: 'json',
        readOnly: false,
        title: `编辑: ${source.name}`
      };
      
      this.pathStack.pushPathByName('FileEditorPage', params);
    } catch (err) {
      logger.error(TAG, `编辑书源配置失败: ${String(err)}`);
      promptAction.showToast({ message: '打开编辑器失败' });
    }
  }

  /**
   * 切换书源置顶状态
   */
  async toggleSourcePin(source: NovelSourceInfo): Promise<void> {
    const rawSource = this.sourceManager.getSource(source.id);
    if (!rawSource) {
      promptAction.showToast({ message: '书源不存在' });
      return;
    }
    
    // 切换置顶状态：置顶的书源weight设为1000，取消置顶设为0
    const newWeight = source.weight > 0 ? 0 : 1000;
    rawSource.weight = newWeight;
    
    // 保存到数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(rawSource);
      promptAction.showToast({ message: newWeight > 0 ? '已置顶' : '已取消置顶' });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `置顶失败: ${String(error)}`);
      promptAction.showToast({ message: '操作失败' });
    }
  }

  async validateSingleSource(source: NovelSourceInfo): Promise<void> {
    promptAction.showToast({ message: `正在校验 ${source.name}...` });
    
    try {
      const validator = getNovelSourceValidator();
      const rawSource = this.sourceManager.getSource(source.id);
      
      if (!rawSource) {
        promptAction.showToast({ message: '书源不存在' });
        return;
      }
      
      const result = await validator.validateSource(rawSource);
      
      if (result.isValid) {
        promptAction.showToast({ 
          message: `✓ ${source.name} 可用 (${result.searchTime}ms, ${result.bookCount}本)` 
        });
      } else {
        promptAction.showToast({ 
          message: `✗ ${source.name} 不可用: ${result.error || '未知错误'}` 
        });
      }
    } catch (error) {
      promptAction.showToast({ message: `校验失败: ${String(error)}` });
    }
  }

  goToLogin(source: NovelSourceInfo): void {
    const rawSource = this.sourceManager.getSource(source.id);
    
    if (!rawSource || !rawSource.loginUrl) {
      promptAction.showToast({ message: '该书源不支持登录' });
      return;
    }
    
    const params: NovelSourceLoginPageParams = {
      sourceId: source.id
    };
    this.pathStack.pushPathByName('NovelSourceLoginPage', params);
  }

  /**
   * 显示校验配置对话框
   */
  showValidationConfigDialog(sourceIds?: string[]): void {
    // 使用ActionMenu显示校验选项
    promptAction.showActionMenu({
      title: '选择校验方式',
      buttons: [
        { text: '快速校验（仅搜索）', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '标准校验（搜索+详情+目录）', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '完整校验（全部项目）', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      let config: Partial<ValidationConfig>;
      switch (result.index) {
        case 0: // 快速校验
          config = {
            checkSearch: true,
            checkDiscovery: false,
            checkInfo: false,
            checkCategory: false,
            checkContent: false,
            timeout: 60000
          };
          break;
        case 1: // 标准校验
          config = {
            checkSearch: true,
            checkDiscovery: false,
            checkInfo: true,
            checkCategory: true,
            checkContent: false,
            timeout: 120000
          };
          break;
        case 2: // 完整校验
          config = {
            checkSearch: true,
            checkDiscovery: true,
            checkInfo: true,
            checkCategory: true,
            checkContent: true,
            timeout: 180000
          };
          break;
        default:
          return; // 取消
      }
      
      // 显示关键词输入对话框
      this.showKeywordInputDialog(config, sourceIds);
    }).catch(() => {});
  }

  /**
   * 显示关键词输入对话框
   */
  showKeywordInputDialog(config: Partial<ValidationConfig>, sourceIds?: string[]): void {
    // 直接使用默认关键词开始校验
    const mergedConfig: Partial<ValidationConfig> = {
      timeout: config.timeout,
      checkSearch: config.checkSearch,
      checkDiscovery: config.checkDiscovery,
      checkInfo: config.checkInfo,
      checkCategory: config.checkCategory,
      checkContent: config.checkContent,
      keyword: '我的'
    };
    this.doValidateSources(sourceIds, mergedConfig);
  }

  /**
   * 执行校验
   */
  async doValidateSources(sourceIds?: string[], config?: Partial<ValidationConfig>): Promise<void> {
    if (this.isValidating) {
      promptAction.showToast({ message: '正在校验中...' });
      return;
    }
    
    this.isValidating = true;
    this.isOperating = true;
    this.validationProgress = '准备校验...';
    this.operatingMessage = '准备校验...';
    
    const validator = getNovelSourceValidator();
    const idsToValidate = sourceIds || this.allSources.map(s => s.id);
    
    // 显示进度对话框
    this.showValidationProgressDialog(idsToValidate.length, validator);
    
    // 用于跟踪统计
    let validCount = 0;
    let invalidCount = 0;
    
    try {
      const result = await validator.validateSources(
        idsToValidate, 
        config,
        (current: number, total: number, res: SourceValidationResult) => {
          // 更新统计
          if (res.isValid) {
            validCount++;
          } else {
            invalidCount++;
          }
          
          // 更新进度对话框
          if (this.validationProgressController) {
            const progressInfo: ValidationProgressInfo = {
              current,
              total,
              validCount,
              invalidCount,
              currentSourceName: res.sourceName,
              isComplete: false,
              isCancelled: false
            };
            this.validationProgressController.updateProgress(progressInfo);
          }
          
          // 更新页面状态
          const statusIcon = res.isValid ? '✓' : '✗';
          this.validationProgress = `${statusIcon} ${current}/${total}: ${res.sourceName}`;
          this.operatingMessage = this.validationProgress;
        },
        true, // 自动更新分组
        true  // 显示系统通知
      );
      
      // 收集失效书源的ID列表
      const invalidSourceIds: string[] = [];
      for (const r of result.results) {
        if (!r.isValid) {
          invalidSourceIds.push(r.sourceId);
        }
      }
      this.lastValidationInvalidSourceIds = invalidSourceIds;
      
      // 更新对话框为完成状态
      if (this.validationProgressController) {
        const progressInfo: ValidationProgressInfo = {
          current: result.total,
          total: result.total,
          validCount: result.valid,
          invalidCount: result.invalid,
          currentSourceName: '',
          isComplete: true,
          isCancelled: validator.isRunning() === false && result.results.length < idsToValidate.length,
          invalidSourceIds: invalidSourceIds
        };
        this.validationProgressController.updateProgress(progressInfo);
      }
      
      // 统计各类错误
      const errorStats = new Map<string, number>();
      for (const r of result.results) {
        if (!r.isValid && r.errorGroups) {
          for (const group of r.errorGroups) {
            errorStats.set(group, (errorStats.get(group) || 0) + 1);
          }
        }
      }
      
      // 结果已在对话框中显示，不再使用toast
      // 构建结果消息（用于日志）
      let message = `校验完成: ${result.valid}/${result.total} 可用`;
      if (errorStats.size > 0) {
        const errorDetails: string[] = [];
        errorStats.forEach((count, group) => {
          errorDetails.push(`${group}(${count})`);
        });
        message += `, 失败分组: ${errorDetails.join(', ')}`;
      }
      logger.info(TAG, message);
      
      // 刷新书源列表和分组
      this.loadSources();
    } catch (error) {
      // 更新对话框为取消状态
      if (this.validationProgressController) {
        const progressInfo: ValidationProgressInfo = {
          current: validCount + invalidCount,
          total: idsToValidate.length,
          validCount,
          invalidCount,
          currentSourceName: '',
          isComplete: false,
          isCancelled: true
        };
        this.validationProgressController.updateProgress(progressInfo);
      }
      // 错误已在对话框中显示
      logger.error(TAG, `校验失败: ${String(error)}`);
    }
    
    this.isValidating = false;
    this.isOperating = false;
    this.validationProgress = '';
    this.operatingMessage = '';
  }
  
  /**
   * 显示校验进度对话框（带取消按钮）
   */
  private showValidationProgressDialog(total: number, validator: NovelSourceValidator): void {
    // 创建对话框控制器
    this.validationDialogController = new CustomDialogController({
      builder: ValidationProgressDialog({
        themeState: this.themeState,
        onCancel: () => {
          validator.cancelValidation();
          promptAction.showToast({ message: '正在取消校验...' });
        },
        onControllerReady: (ctrl: ValidationProgressController) => {
          this.validationProgressController = ctrl;
          // 初始化进度
          ctrl.updateProgress({
            current: 0,
            total: total,
            validCount: 0,
            invalidCount: 0,
            currentSourceName: '准备中...',
            isComplete: false,
            isCancelled: false
          });
        },
        onCloseInvalidSources: () => {
          this.closeInvalidSources();
        }
      }),
      autoCancel: false,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    
    this.validationDialogController.open();
  }

  async validateAllSources(): Promise<void> {
    this.showValidationConfigDialog();
  }

  /**
   * 关闭失效书源（根据最近一次校验结果）
   * 保留置顶状态，仅禁用书源
   */
  async closeInvalidSources(): Promise<void> {
    if (this.lastValidationInvalidSourceIds.length === 0) {
      promptAction.showToast({ message: '没有失效的书源需要关闭' });
      return;
    }

    this.isOperating = true;
    this.operatingMessage = '正在关闭失效书源...';

    let successCount = 0;
    let failCount = 0;

    for (const sourceId of this.lastValidationInvalidSourceIds) {
      try {
        // 获取书源信息
        const rawSource = this.sourceManager.getSource(sourceId);
        if (rawSource) {
          // 保存当前的weight（置顶状态）
          const currentWeight = rawSource.weight;
          
          // 仅禁用书源，不改变weight
          await this.sourceManager.setSourceEnabled(sourceId, false);
          
          // 确保weight没有被改变
          const updatedSource = this.sourceManager.getSource(sourceId);
          if (updatedSource && updatedSource.weight !== currentWeight) {
            const dataManager = getNovelDataManager();
            updatedSource.weight = currentWeight;
            await dataManager.saveSource(updatedSource);
          }
          
          successCount++;
        }
      } catch (error) {
        logger.error(TAG, `关闭书源失败 ${sourceId}: ${String(error)}`);
        failCount++;
      }
    }

    this.isOperating = false;
    this.operatingMessage = '';

    // 显示结果
    const message = failCount > 0 
      ? `已关闭 ${successCount} 个失效书源，${failCount} 个失败`
      : `已关闭 ${successCount} 个失效书源`;
    
    promptAction.showToast({ message });
    
    // 关闭对话框
    if (this.validationDialogController) {
      this.validationDialogController.close();
    }
    
    // 刷新书源列表
    this.loadSources();
    
    // 清空失效书源列表
    this.lastValidationInvalidSourceIds = [];
  }

  // ==================== 多选模式操作 ====================

  /**
   * 切换多选模式
   */
  toggleMultiSelectMode(): void {
    this.isMultiSelectMode = !this.isMultiSelectMode;
    if (!this.isMultiSelectMode) {
      // 退出多选模式时清空选中列表
      this.selectedSourceIds = new Set();
    }
  }

  /**
   * 切换单个书源的选中状态
   */
  toggleSourceSelection(sourceId: string, isSelected: boolean): void {
    const newSet = new Set(this.selectedSourceIds);
    if (isSelected) {
      newSet.add(sourceId);
    } else {
      newSet.delete(sourceId);
    }
    this.selectedSourceIds = newSet;
  }

  /**
   * 全选当前筛选后的书源
   */
  selectAll(): void {
    const newSet = new Set<string>();
    for (const source of this.filteredSources) {
      newSet.add(source.id);
    }
    this.selectedSourceIds = newSet;
  }

  /**
   * 反选当前筛选后的书源
   */
  invertSelection(): void {
    const newSet = new Set<string>();
    for (const source of this.filteredSources) {
      if (!this.selectedSourceIds.has(source.id)) {
        newSet.add(source.id);
      }
    }
    this.selectedSourceIds = newSet;
  }

  /**
   * 批量置顶/取消置顶书源
   */
  async batchPinSources(pin: boolean): Promise<void> {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    const dataManager = getNovelDataManager();
    let count = 0;
    const newWeight = pin ? 1000 : 0;

    for (const sourceId of this.selectedSourceIds) {
      const rawSource = this.sourceManager.getSource(sourceId);
      if (rawSource) {
        rawSource.weight = newWeight;
        try {
          await dataManager.saveSource(rawSource);
          count++;
        } catch (error) {
          logger.error(TAG, `置顶失败: ${String(error)}`);
        }
      }
    }

    promptAction.showToast({ message: `已${pin ? '置顶' : '取消置顶'} ${count} 个书源` });
    this.selectedSourceIds = new Set();
    this.loadSources();
  }

  /**
   * 批量启用/禁用书源
   */
  async batchSetEnabled(enabled: boolean): Promise<void> {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    let count = 0;
    for (const sourceId of this.selectedSourceIds) {
      try {
        await this.sourceManager.setSourceEnabled(sourceId, enabled);
        count++;
      } catch (error) {
        logger.error(TAG, `设置启用状态失败: ${String(error)}`);
      }
    }

    promptAction.showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 个书源` });
    this.selectedSourceIds = new Set();
    this.loadSources();
  }

  /**
   * 批量校验书源
   */
  async batchValidateSources(): Promise<void> {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    // 显示校验配置对话框
    const sourceIds = Array.from(this.selectedSourceIds);
    this.showValidationConfigDialog(sourceIds);
    
    // 退出多选模式
    this.selectedSourceIds = new Set();
    this.isMultiSelectMode = false;
  }

  /**
   * 批量删除书源
   */
  batchDeleteSources(): void {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedSourceIds.size} 个书源吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        let count = 0;
        for (const sourceId of this.selectedSourceIds) {
          try {
            await this.sourceManager.deleteSource(sourceId);
            count++;
          } catch (error) {
            logger.error(TAG, `删除失败: ${String(error)}`);
          }
        }
        promptAction.showToast({ message: `已删除 ${count} 个书源` });
        this.selectedSourceIds = new Set();
        this.isMultiSelectMode = false;
        this.loadSources();
      }
    });
  }

  // ==================== 分组管理功能 ====================

  /**
   * 显示添加到分组对话框
   */
  showAddToGroupDialog(): void {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    const existingGroups = this.sourceManager.getAllGroups();
    
    // 构建按钮列表 - 使用元组类型
    const buttonList: promptAction.Button[] = [];
    for (let i = 0; i < existingGroups.length; i++) {
      const btn: promptAction.Button = { text: existingGroups[i], color: '#333333' };
      buttonList.push(btn);
    }
    
    // 添加"新建分组"选项
    buttonList.push({ text: '+ 新建分组', color: '#9C27B0' });
    buttonList.push({ text: '取消', color: '#666666' });

    // 转换为元组类型
    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: '选择分组',
      buttons: buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === buttons.length - 1) {
        // 取消
        return;
      } else if (result.index === buttons.length - 2) {
        // 新建分组
        this.showCreateGroupDialog();
      } else {
        // 选择现有分组
        const groupName = existingGroups[result.index];
        this.addSelectedSourcesToGroup(groupName);
      }
    }).catch(() => {});
  }

  /**
   * 显示创建分组对话框
   */
  showCreateGroupDialog(): void {
    // 使用简单的提示让用户输入分组名
    promptAction.showDialog({
      title: '新建分组',
      message: '请在下方输入分组名称后点击确定',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确定', color: '#9C27B0' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        // 由于系统对话框不支持输入，使用预设的分组名
        const defaultGroups = ['精品', '常用', '备用', '测试'];
        this.showSelectDefaultGroupDialog(defaultGroups);
      }
    });
  }

  /**
   * 显示选择预设分组对话框
   */
  showSelectDefaultGroupDialog(defaultGroups: string[]): void {
    const buttonList: promptAction.Button[] = [];
    for (let i = 0; i < defaultGroups.length; i++) {
      const btn: promptAction.Button = { text: defaultGroups[i], color: '#333333' };
      buttonList.push(btn);
    }
    buttonList.push({ text: '取消', color: '#666666' });

    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: '选择分组名称',
      buttons: buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < defaultGroups.length) {
        const groupName = defaultGroups[result.index];
        this.addSelectedSourcesToGroup(groupName);
      }
    }).catch(() => {});
  }

  /**
   * 将选中的书源添加到分组
   */
  async addSelectedSourcesToGroup(groupName: string): Promise<void> {
    const sourceIds = Array.from(this.selectedSourceIds);
    
    this.isOperating = true;
    this.operatingMessage = `正在添加到分组 "${groupName}"...`;
    
    try {
      const count = await this.sourceManager.addSourcesToGroup(sourceIds, groupName);
      promptAction.showToast({ message: `已将 ${count} 个书源添加到分组 "${groupName}"` });
      this.selectedSourceIds = new Set();
      this.isMultiSelectMode = false;
      this.loadSources();
    } catch (error) {
      promptAction.showToast({ message: `添加失败: ${String(error)}` });
    }
    
    this.isOperating = false;
    this.operatingMessage = '';
  }

  /**
   * 显示从分组移除对话框
   */
  showRemoveFromGroupDialog(): void {
    if (this.selectedSourceIds.size === 0) {
      promptAction.showToast({ message: '请先选择书源' });
      return;
    }

    const existingGroups = this.sourceManager.getAllGroups();
    if (existingGroups.length === 0) {
      promptAction.showToast({ message: '暂无分组' });
      return;
    }

    const buttonList: promptAction.Button[] = [];
    const groupsToShow = existingGroups.slice(0, 5);
    for (let i = 0; i < groupsToShow.length; i++) {
      const btn: promptAction.Button = { text: groupsToShow[i], color: '#333333' };
      buttonList.push(btn);
    }
    buttonList.push({ text: '取消', color: '#666666' });

    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: '从哪个分组移除？',
      buttons: buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < existingGroups.length && result.index < 5) {
        const groupName = existingGroups[result.index];
        this.removeSelectedSourcesFromGroup(groupName);
      }
    }).catch(() => {});
  }

  /**
   * 将选中的书源从分组移除
   */
  async removeSelectedSourcesFromGroup(groupName: string): Promise<void> {
    const sourceIds = Array.from(this.selectedSourceIds);
    
    this.isOperating = true;
    this.operatingMessage = `正在从分组 "${groupName}" 移除...`;
    
    try {
      const count = await this.sourceManager.removeSourcesFromGroup(sourceIds, groupName);
      promptAction.showToast({ message: `已从分组 "${groupName}" 移除 ${count} 个书源` });
      this.selectedSourceIds = new Set();
      this.isMultiSelectMode = false;
      this.loadSources();
    } catch (error) {
      promptAction.showToast({ message: `移除失败: ${String(error)}` });
    }
    
    this.isOperating = false;
    this.operatingMessage = '';
  }

  /**
   * 显示分组管理对话框
   */
  showGroupManageDialog(): void {
    const existingGroups = this.sourceManager.getAllGroups();
    
    if (existingGroups.length === 0) {
      promptAction.showToast({ message: '暂无分组' });
      return;
    }

    // 构建分组信息列表
    const groupInfos = this.buildGroupInfos();

    // 创建对话框
    const dialogController = new CustomDialogController({
      builder: GroupManagementDialog({
        themeState: this.themeState,
        groups: groupInfos,
        callbacks: {
          onRename: async (oldName: string, newName: string) => {
            await this.renameGroupOperation(oldName, newName);
          },
          onMerge: async (sourceGroups: string[], targetGroup: string) => {
            await this.mergeGroupsOperation(sourceGroups, targetGroup);
          },
          onSplit: async (groupName: string, condition: SplitCondition) => {
            await this.splitGroupOperation(groupName, condition);
          },
          onDelete: async (groupName: string) => {
            await this.deleteGroupOperation(groupName);
          },
          onRefresh: (): GroupInfo[] => {
            return this.buildGroupInfos();
          }
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    
    dialogController.open();
  }

  /**
   * 构建分组信息列表
   */
  buildGroupInfos(): GroupInfo[] {
    const existingGroups = this.sourceManager.getAllGroups();
    const groupInfos: GroupInfo[] = [];
    
    for (const groupName of existingGroups) {
      const sourcesInGroup = this.allSources.filter(s => {
        if (!s.group) return false;
        const groups = s.group.split(',').map(g => g.trim());
        return groups.includes(groupName);
      });
      
      const enabledCount = sourcesInGroup.filter(s => s.enabled).length;
      const disabledCount = sourcesInGroup.filter(s => !s.enabled).length;
      const pinnedCount = sourcesInGroup.filter(s => s.weight > 0).length;
      
      groupInfos.push({
        name: groupName,
        count: sourcesInGroup.length,
        enabledCount,
        disabledCount,
        pinnedCount
      });
    }
    
    return groupInfos;
  }

  /**
   * 重命名分组操作
   */
  async renameGroupOperation(oldName: string, newName: string): Promise<void> {
    this.isOperating = true;
    this.operatingMessage = '正在重命名分组...';
    
    try {
      const count = await this.sourceManager.renameGroup(oldName, newName);
      promptAction.showToast({ message: `已将 ${count} 个书源的分组从 "${oldName}" 改为 "${newName}"` });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `重命名分组失败: ${String(error)}`);
      throw new Error(String(error));
    } finally {
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  /**
   * 合并分组操作
   */
  async mergeGroupsOperation(sourceGroups: string[], targetGroup: string): Promise<void> {
    this.isOperating = true;
    this.operatingMessage = '正在合并分组...';
    
    try {
      const dataManager = getNovelDataManager();
      let totalCount = 0;
      
      // 遍历所有书源，将属于源分组的书源移动到目标分组
      for (const source of this.allSources) {
        if (!source.group) continue;
        
        const groups = source.group.split(',').map(g => g.trim());
        const hasSourceGroup = sourceGroups.some(sg => groups.includes(sg));
        
        if (hasSourceGroup) {
          // 移除源分组，添加目标分组
          const newGroups = groups.filter(g => !sourceGroups.includes(g));
          if (!newGroups.includes(targetGroup)) {
            newGroups.push(targetGroup);
          }
          
          const rawSource = this.sourceManager.getSource(source.id);
          if (rawSource) {
            rawSource.bookSourceGroup = newGroups.join(',');
            await dataManager.saveSource(rawSource);
            totalCount++;
          }
        }
      }
      
      promptAction.showToast({ message: `已合并 ${sourceGroups.length} 个分组，影响 ${totalCount} 个书源` });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `合并分组失败: ${String(error)}`);
      throw new Error(String(error));
    } finally {
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  /**
   * 拆分分组操作
   */
  async splitGroupOperation(groupName: string, condition: SplitCondition): Promise<void> {
    this.isOperating = true;
    this.operatingMessage = '正在拆分分组...';
    
    try {
      const dataManager = getNovelDataManager();
      let group1Count = 0;
      let group2Count = 0;
      
      // 根据条件拆分分组
      const sourcesInGroup = this.allSources.filter(s => {
        if (!s.group) return false;
        const groups = s.group.split(',').map(g => g.trim());
        return groups.includes(groupName);
      });
      
      for (const source of sourcesInGroup) {
        let shouldMoveToGroup1 = false;
        let group1Name = '';
        let group2Name = '';
        
        if (condition.type === 'enabled') {
          shouldMoveToGroup1 = source.enabled;
          group1Name = `${groupName}-启用`;
          group2Name = `${groupName}-禁用`;
        } else if (condition.type === 'pinned') {
          shouldMoveToGroup1 = source.weight > 0;
          group1Name = `${groupName}-置顶`;
          group2Name = `${groupName}-普通`;
        } else if (condition.type === 'keyword' && condition.keyword) {
          shouldMoveToGroup1 = source.name.includes(condition.keyword);
          group1Name = `${groupName}-${condition.keyword}`;
          group2Name = `${groupName}-其他`;
        }
        
        const rawSource = this.sourceManager.getSource(source.id);
        if (rawSource) {
          const groups = (rawSource.bookSourceGroup || '').split(',').map(g => g.trim()).filter(g => g);
          const newGroups = groups.filter(g => g !== groupName);
          
          if (shouldMoveToGroup1) {
            newGroups.push(group1Name);
            group1Count++;
          } else {
            newGroups.push(group2Name);
            group2Count++;
          }
          
          rawSource.bookSourceGroup = newGroups.join(',');
          await dataManager.saveSource(rawSource);
        }
      }
      
      promptAction.showToast({ message: `拆分完成：组一 ${group1Count} 个，组二 ${group2Count} 个` });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `拆分分组失败: ${String(error)}`);
      throw new Error(String(error));
    } finally {
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  /**
   * 删除分组操作
   */
  async deleteGroupOperation(groupName: string): Promise<void> {
    this.isOperating = true;
    this.operatingMessage = '正在删除分组...';
    
    try {
      const count = await this.sourceManager.deleteGroup(groupName);
      promptAction.showToast({ message: `已删除分组 "${groupName}"，影响 ${count} 个书源` });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `删除分组失败: ${String(error)}`);
      throw new Error(String(error));
    } finally {
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  /**
   * 显示重命名分组对话框（旧版，保留以防兼容性问题）
   */
  showRenameGroupDialog(): void {
    const existingGroups = this.sourceManager.getAllGroups();
    const buttonList: promptAction.Button[] = [];
    const groupsToShow = existingGroups.slice(0, 5);
    for (let i = 0; i < groupsToShow.length; i++) {
      const btn: promptAction.Button = { text: groupsToShow[i], color: '#333333' };
      buttonList.push(btn);
    }
    buttonList.push({ text: '取消', color: '#666666' });

    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: '选择要重命名的分组',
      buttons: buttons
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < existingGroups.length && result.index < 5) {
        const oldName = existingGroups[result.index];
        this.showSelectNewGroupNameDialog(oldName);
      }
    }).catch(() => {});
  }

  /**
   * 显示选择新分组名对话框
   */
  showSelectNewGroupNameDialog(oldName: string): void {
    const allNames = ['精品', '常用', '备用', '测试', '失效'];
    const newNames: string[] = [];
    for (let i = 0; i < allNames.length; i++) {
      if (allNames[i] !== oldName) {
        newNames.push(allNames[i]);
      }
    }
    const buttonList: promptAction.Button[] = [];
    for (let i = 0; i < newNames.length; i++) {
      const btn: promptAction.Button = { text: newNames[i], color: '#333333' };
      buttonList.push(btn);
    }
    buttonList.push({ text: '取消', color: '#666666' });

    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: `将 "${oldName}" 重命名为`,
      buttons: buttons
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < newNames.length) {
        const newName = newNames[result.index];
        this.isOperating = true;
        this.operatingMessage = '正在重命名分组...';
        
        try {
          const count = await this.sourceManager.renameGroup(oldName, newName);
          promptAction.showToast({ message: `已将 ${count} 个书源的分组从 "${oldName}" 改为 "${newName}"` });
          this.loadSources();
        } catch (error) {
          promptAction.showToast({ message: `重命名失败: ${String(error)}` });
        }
        
        this.isOperating = false;
        this.operatingMessage = '';
      }
    }).catch(() => {});
  }

  /**
   * 显示删除分组对话框
   */
  showDeleteGroupDialog(): void {
    const existingGroups = this.sourceManager.getAllGroups();
    const buttonList: promptAction.Button[] = [];
    const groupsToShow = existingGroups.slice(0, 5);
    for (let i = 0; i < groupsToShow.length; i++) {
      const btn: promptAction.Button = { text: groupsToShow[i], color: '#FF4D4F' };
      buttonList.push(btn);
    }
    buttonList.push({ text: '取消', color: '#666666' });

    const buttons: [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?] = 
      [buttonList[0], buttonList[1], buttonList[2], buttonList[3], buttonList[4], buttonList[5]];

    promptAction.showActionMenu({
      title: '选择要删除的分组（仅移除标签，不删除书源）',
      buttons: buttons
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index < existingGroups.length && result.index < 5) {
        const groupName = existingGroups[result.index];
        
        this.isOperating = true;
        this.operatingMessage = '正在删除分组...';
        
        try {
          const count = await this.sourceManager.deleteGroup(groupName);
          promptAction.showToast({ message: `已删除分组 "${groupName}"，影响 ${count} 个书源` });
          this.loadSources();
        } catch (error) {
          promptAction.showToast({ message: `删除失败: ${String(error)}` });
        }
        
        this.isOperating = false;
        this.operatingMessage = '';
      }
    }).catch(() => {});
  }

  /**
   * 显示分组统计
   */
  showGroupStats(): void {
    const existingGroups = this.sourceManager.getAllGroups();
    const stats: string[] = [];
    
    for (const group of existingGroups) {
      const count = this.sourceManager.getSourcesByGroup(group).length;
      stats.push(`${group}: ${count}个`);
    }
    
    const noGroupCount = this.sourceManager.getSourcesWithoutGroup().length;
    stats.push(`未分组: ${noGroupCount}个`);
    
    promptAction.showDialog({
      title: '分组统计',
      message: stats.join('\n'),
      buttons: [{ text: '确定', color: $r('sys.color.ohos_id_color_text_primary') }]
    });
  }
}
