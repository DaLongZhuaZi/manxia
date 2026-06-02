import { SafeFileUtils } from '../Utils/SafeFileUtils';
import { SafeUtils } from '../Utils/SafeUtils';
/**
 * 小说书源管理页面
 * 导入、删除、测试书源
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelSourceManagementPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelSourceValidator, ValidationConfig, NovelSourceValidator, SourceValidationResult, SPECIAL_GROUP_NAMES } from '../Framework/Novel/NovelSourceValidator';
import { NovelSourceInfo } from '../Models/NovelModels';
import { LegadoSourceImportResult, LegadoBookSource, LegadoBookSourceType } from '../Framework/Novel/LegadoSourceTypes';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { SettingKeys, SettingsManager } from '../Framework/Managers/SettingsManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';
import { NovelSearchPageParams } from './NovelBookshelfPage';
import { ValidationProgressDialog, ValidationProgressController, ValidationProgressInfo } from '../Framework/Components/ValidationProgressDialog';
import { GroupManagementDialog, GroupInfo, SplitCondition } from '../Framework/Components/GroupManagementDialog';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';
import { FileEditorParams } from './FileEditorPage';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsPanelSurfaceHelper } from './settings/SettingsPanelSurfaceHelper';
import { SettingsPageSurfaceManager } from './settings/SettingsPageSurfaceManager';

const TAG = 'NovelSourceManagementPage';

// 分页加载常量
const PAGE_SIZE = 100;  // 每次加载数量
const PRELOAD_THRESHOLD = 60;  // 预加载触发阈值（当显示到第60-70个时开始加载下一批）
const VALIDATION_CONCURRENCY_DEFAULT = 10;
const VALIDATION_CONCURRENCY_MAX = 50;
const VALIDATION_CONCURRENCY_OPTIONS: [number, number, number, number, number, number] = [10, 15, 20, 30, 40, 50];
const NETWORK_IMPORT_MAX_DEPTH = 4;
const MULTI_SELECT_BAR_ANIMATED_HEIGHT = 178;
const QUICK_ACTION_PANEL_ANIMATED_HEIGHT = 184;
const GROUP_FILTER_SINGLE_HEIGHT = 52;
type ImportErrorValue = Object | string | number | boolean | null | undefined;

interface NetworkImportSummary {
  successCount: number;
  failCount: number;
  fetchedCount: number;
}

type SourceUrlCollectionValue = string | string[] | null | undefined;
type GlassActionButtonTone = 'primary' | 'neutral' | 'success' | 'warning' | 'danger' | 'accent';
type SourceContextMenuAction = 'search' | 'edit' | 'debug' | 'pin' | 'delete' | '';

interface NetworkSourceUrlIndexPayload {
  sourceUrls?: SourceUrlCollectionValue;
  bookSourceUrls?: SourceUrlCollectionValue;
}

type GroupPickerMode = 'add' | 'remove';
type DeleteConfirmMode = 'single' | 'batch';
enum ValidationPresetMode {
  QUICK = 0,
  STANDARD = 1,
  FULL = 2
}

enum GroupFilterDisplayMode {
  COLLAPSED = 0,
  SINGLE_LINE = 1,
  FULL = 2
}

interface ValidationDialogScope {
  sourceIds: string[];
  validateAll: boolean;
}

interface DeleteDialogPayload {
  mode: DeleteConfirmMode;
  sourceIds: string[];
  title: string;
  message: string;
}

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
  @State showImportEntryDialog: boolean = false;
  @State showImportDialog: boolean = false;
  @State showImportUrlDialog: boolean = false;
  @State importText: string = '';
  @State importUrl: string = '';
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
  @State showQuickActionPanel: boolean = true;
  @State groupFilterDisplayMode: GroupFilterDisplayMode = GroupFilterDisplayMode.SINGLE_LINE;
  // 多选模式
  @State isMultiSelectMode: boolean = false;
  @State selectedSourceIds: Set<string> = new Set();
  @State showGroupInputDialog: boolean = false;
  @State groupInputValue: string = '';
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
  private settingsManager: SettingsManager = SettingsManager.getInstance();
  private listScroller: Scroller = new Scroller();
  // 校验进度对话框
  private validationProgressController: ValidationProgressController | null = null;
  private validationDialogController: CustomDialogController | null = null;
  // 存储最近一次校验的失效书源ID列表
  private lastValidationInvalidSourceIds: string[] = [];
  // 书源长按菜单状态
  @State showSourceContextMenu: boolean = false;
  @State contextMenuSource: NovelSourceInfo | null = null;
  @State contextMenuHoverAction: SourceContextMenuAction = '';
  // 排序模式状态
  @State isSortMode: boolean = false;
  @State isSavingOrder: boolean = false;
  // 校验配置对话框状态
  @State showValidationSetupDialog: boolean = false;
  @State validationPresetMode: ValidationPresetMode = ValidationPresetMode.STANDARD;
  @State validationKeywordInput: string = '我的';
  @State validationConcurrencyInput: number = VALIDATION_CONCURRENCY_DEFAULT;
  @State validationTargetCount: number = 0;
  @State isValidationTargetAll: boolean = true;
  private validationDialogScope: ValidationDialogScope = {
    sourceIds: [],
    validateAll: true
  };
  // 分组选择对话框状态（替代截断的 ActionMenu）
  @State showGroupPickerDialog: boolean = false;
  @State groupPickerMode: GroupPickerMode = 'add';
  @State groupPickerKeyword: string = '';
  @State groupPickerGroups: string[] = [];
  @State groupPickerFilteredGroups: string[] = [];
  // 删除确认对话框状态（统一玻璃样式）
  @State showDeleteConfirmDialog: boolean = false;
  @State deleteConfirmTitle: string = '';
  @State deleteConfirmMessage: string = '';
  @State deleteConfirmMode: DeleteConfirmMode = 'single';
  private pendingDeleteSourceIds: string[] = [];

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
    // 获取所有书源（已按 customOrder 排序，未启用的在末尾）
    const sources = this.sourceManager.getAllSources();
    // getAllSources 已经按 customOrder 排序，直接使用
    this.allSources = sources;
    
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
      const isAudioKeyword: boolean = keyword.includes('听书') || keyword.includes('有声') || keyword.includes('audio');
      result = result.filter(s => 
        s.name.toLowerCase().includes(keyword) || 
        (s.group && s.group.toLowerCase().includes(keyword)) ||
        s.url.toLowerCase().includes(keyword) ||
        (isAudioKeyword && this.isAudioSource(s))
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

  private isAudioSource(source: NovelSourceInfo): boolean {
    return source.bookSourceType === LegadoBookSourceType.AUDIO;
  }

  private toggleSearchBar(): void {
    this.showSearchBar = !this.showSearchBar;
    if (!this.showSearchBar) {
      this.searchKeyword = '';
      this.applyFilter();
    }
  }

  private toggleQuickActionPanel(): void {
    this.showQuickActionPanel = !this.showQuickActionPanel;
  }

  private cycleGroupFilterDisplayMode(): void {
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.COLLAPSED) {
      this.groupFilterDisplayMode = GroupFilterDisplayMode.SINGLE_LINE;
      return;
    }
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.SINGLE_LINE) {
      this.groupFilterDisplayMode = GroupFilterDisplayMode.FULL;
      return;
    }
    this.groupFilterDisplayMode = GroupFilterDisplayMode.COLLAPSED;
  }

  private getGroupFilterSwitchLabel(): string {
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.COLLAPSED) {
      return '单行';
    }
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.SINGLE_LINE) {
      return '全部';
    }
    return '收起';
  }

  private getGroupFilterContainerHeight(): number {
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.COLLAPSED) {
      return 0;
    }
    if (this.groupFilterDisplayMode === GroupFilterDisplayMode.SINGLE_LINE) {
      return GROUP_FILTER_SINGLE_HEIGHT;
    }

    const totalChipCount = this.sourceGroups.length + 1;
    const chipsPerRow = 3;
    const rowCount = Math.max(1, Math.ceil(totalChipCount / chipsPerRow));
    const rowHeight = 34;
    const rowGap = 8;
    const verticalPadding = 12;
    const computedHeight = rowCount * rowHeight + (rowCount - 1) * rowGap + verticalPadding;
    return Math.min(220, computedHeight);
  }

  private buildStandardValidationConfig(): Partial<ValidationConfig> {
    return {
      checkSearch: true,
      checkDiscovery: false,
      checkInfo: true,
      checkCategory: true,
      checkContent: false,
      timeout: 120000,
      keyword: '我的',
      concurrency: this.getValidationConcurrency()
    };
  }

  private quickValidateSources(sourceIds?: string[]): void {
    const config = this.buildStandardValidationConfig();
    void this.doValidateSources(sourceIds, config);
  }

  private getGlassActionButtonBackground(tone: GlassActionButtonTone): Resource {
    switch (tone) {
      case 'primary':
        return ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme);
      case 'success':
        return ThemeAwareHelper.getTestManagementThemedColor('button_success', this.themeState.currentTheme);
      case 'warning':
        return ThemeAwareHelper.getTestManagementThemedColor('button_warning', this.themeState.currentTheme);
      case 'danger':
        return ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme);
      case 'accent':
        return ThemeAwareHelper.getTestManagementThemedColor('button_purple', this.themeState.currentTheme);
      case 'neutral':
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme);
    }
  }

  private getGlassActionButtonTextColor(tone: GlassActionButtonTone): Resource {
    switch (tone) {
      case 'neutral':
        return ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme);
      case 'primary':
      case 'success':
      case 'warning':
      case 'danger':
      case 'accent':
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme);
    }
  }

  private getGlassActionButtonBorderColor(tone: GlassActionButtonTone): Resource {
    switch (tone) {
      case 'primary':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
      case 'success':
        return ThemeAwareHelper.getTestManagementThemedColor('success_border', this.themeState.currentTheme);
      case 'warning':
        return ThemeAwareHelper.getTestManagementThemedColor('color_warning', this.themeState.currentTheme);
      case 'danger':
        return ThemeAwareHelper.getTestManagementThemedColor('error_border', this.themeState.currentTheme);
      case 'accent':
        return ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme);
      case 'neutral':
      default:
        return ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme);
    }
  }

  private getGlassActionButtonBlurStyle(): BlurStyle | undefined {
    return SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme);
  }

  private getGlassActionButtonBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme);
  }

  private getGlassActionButtonBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme);
  }

  private getGlassActionButtonGradient(): LinearGradient {
    return SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme);
  }

  private getGlassActionButtonShadowColor(): string {
    return SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme);
  }

  private isContextMenuActionHighlighted(action: SourceContextMenuAction): boolean {
    return this.contextMenuHoverAction === action;
  }

  private updateContextMenuHoverState(action: SourceContextMenuAction, isHovering: boolean): void {
    if (isHovering) {
      this.contextMenuHoverAction = action;
      return;
    }
    if (this.contextMenuHoverAction === action) {
      this.contextMenuHoverAction = '';
    }
  }

  private updateContextMenuTouchState(action: SourceContextMenuAction, event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.contextMenuHoverAction = action;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.contextMenuHoverAction === action) {
        this.contextMenuHoverAction = '';
      }
    }
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'search',
        label: '搜索',
        symbol: $r('sys.symbol.magnifyingglass'),
        onClick: () => {
          this.toggleSearchBar();
        }
      },
      {
        id: 'multiSelect',
        label: this.isMultiSelectMode ? '取消多选' : '多选',
        symbol: $r('sys.symbol.checkmark'),
        onClick: () => {
          this.toggleMultiSelectMode();
        }
      },
      {
        id: 'import',
        label: '导入书源',
        symbol: $r('sys.symbol.folder'),
        onClick: () => {
          this.showImportOptions();
        }
      },
      {
        id: 'validate',
        label: '一键校验',
        symbol: $r('sys.symbol.wrench_arrow_counterclockwise'),
        onClick: () => {
          this.quickValidateSources();
        }
      },
      {
        id: 'quickPanel',
        label: this.showQuickActionPanel ? '收起快捷' : '展开快捷',
        symbol: $r('sys.symbol.line_3_horizontal_circle'),
        onClick: () => {
          this.toggleQuickActionPanel();
        }
      }
    ];
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 隐藏的WebView组件，用于执行JS网络请求
        LegadoWebViewComponent()
        
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层：预留标题栏高度
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
          
          // 搜索栏（可隐藏，带动画）
          Column() {
            this.buildSearchBar()
          }
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .height(this.showSearchBar ? 56 : 0)
          .opacity(this.showSearchBar ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })
          
          // 多选操作栏（展开/收起动画参考搜索栏）
          Column() {
            this.buildMultiSelectBar()
          }
          .width('100%')
          .height(this.isMultiSelectMode ? MULTI_SELECT_BAR_ANIMATED_HEIGHT : 0)
          .opacity(this.isMultiSelectMode ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })
          
          // 排序模式操作栏
          if (this.isSortMode) {
            this.buildSortModeBar()
          }
          
          // 统计信息和分组筛选（排序模式下隐藏）
          if (!this.isSortMode) {
            this.buildStats()
          }

          // 一级快捷操作（展开/收起动画参考搜索栏）
          Column() {
            this.buildQuickActionPanel()
          }
          .width('100%')
          .height(!this.isSortMode && !this.isMultiSelectMode && this.showQuickActionPanel
            ? QUICK_ACTION_PANEL_ANIMATED_HEIGHT
            : 0)
          .opacity(!this.isSortMode && !this.isMultiSelectMode && this.showQuickActionPanel ? 1 : 0)
          .clip(true)
          .animation({ duration: 200, curve: Curve.EaseOut })

          this.buildListGuideHeader(!this.isSortMode && !this.isMultiSelectMode && this.showQuickActionPanel)
          
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 导入对话框
        if (this.showImportEntryDialog) {
          this.buildImportEntryDialog()
        }

        if (this.showImportDialog) {
          this.buildImportDialog()
        }

        if (this.showImportUrlDialog) {
          this.buildImportUrlDialog()
        }

        if (this.showGroupInputDialog) {
          this.buildGroupInputDialog()
        }

        if (this.showValidationSetupDialog) {
          this.buildValidationSetupDialog()
        }

        if (this.showGroupPickerDialog) {
          this.buildGroupPickerDialog()
        }

        if (this.showDeleteConfirmDialog) {
          this.buildDeleteConfirmDialog()
        }
        
        // 操作加载遮罩层
        if (this.isOperating) {
          this.buildOperatingOverlay()
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '书源管理',
          appFontFamily: this.appFontFamily,
          actions: this.getTitleBarActions()
        })

      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .id('guide_novel_source_root')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.loadSources();
    })
  }

  @Builder
  buildSearchBar() {
    Row() {
      TextInput({ placeholder: '搜索书源名称、分组或网址...', text: this.searchKeyword })
        .layoutWeight(1)
        .height(40)
        .backgroundColor(this.getGlassActionButtonBackground('neutral'))
        .linearGradient(this.getGlassActionButtonGradient())
        .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
        .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
        .border({
          width: 1,
          color: this.getGlassActionButtonBorderColor('neutral')
        })
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
    .id('guide_novel_source_search')
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
        Button('全选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('primary'))
          .backgroundColor(this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('primary')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(30)
          .margin({ right: 8 })
          .onClick(() => this.selectAll())
        
        // 反选按钮
        Button('反选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('primary'))
          .backgroundColor(this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('primary')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(30)
          .margin({ right: 8 })
          .onClick(() => this.invertSelection())

        // 退出多选
        Button('退出')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(30)
          .onClick(() => {
            this.selectedSourceIds = new Set();
            this.isMultiSelectMode = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      
      // 批量操作按钮 - 第一排
      Row() {
        // 批量置顶
        Button('置顶')
          .fontSize(12)
          .fontColor(this.getGlassActionButtonTextColor('primary'))
          .fontFamily(this.appFontFamily)
          .backgroundColor(this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('primary')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('success'))
          .backgroundColor(this.getGlassActionButtonBackground('success'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('success')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('warning'))
          .backgroundColor(this.getGlassActionButtonBackground('warning'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('warning')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('danger'))
          .backgroundColor(this.getGlassActionButtonBackground('danger'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('danger')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('accent'))
          .backgroundColor(this.getGlassActionButtonBackground('accent'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('accent')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
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
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ right: 8 })
          .enabled(this.selectedSourceIds.size > 0)
          .onClick(() => this.showRemoveFromGroupDialog())
        
        // 退出多选
        Button('退出多选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => {
            this.selectedSourceIds = new Set();
            this.isMultiSelectMode = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
    }
    .width('100%')
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
   * 构建排序模式操作栏
   */
  @Builder
  buildSortModeBar() {
    Column() {
      // 提示文字
      Row() {
        SymbolGlyph($r('sys.symbol.line_3_horizontal_circle'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
        Text('排序模式')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 8 })
        Text(`（共 ${this.filteredSources.length} 个启用的书源）`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
      
      // 操作按钮
      Row() {
        // 取消按钮
        Button('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(20)
          .height(36)
          .layoutWeight(1)
          .margin({ right: 12 })
          .onClick(() => this.exitSortMode())
        
        // 保存排序按钮
        Button('保存排序')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('primary'))
          .backgroundColor(this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('primary')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(20)
          .height(36)
          .layoutWeight(1)
          .onClick(() => this.saveSourceOrder())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .width('100%')
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
   * 显示导入选项弹窗
   */
  showImportOptions(): void {
    this.showImportEntryDialog = true;
  }

  /**
   * 进入排序模式
   */
  enterSortMode(): void {
    // 清除筛选和搜索，显示所有启用的书源
    this.selectedGroup = '';
    this.searchKeyword = '';
    this.showSearchBar = false;
    this.isMultiSelectMode = false;
    this.selectedSourceIds.clear();
    // 重新加载并应用筛选（只显示启用的书源）
    this.applyFilterForSortMode();
    this.isSortMode = true;
    this.getUIContext().getPromptAction().showToast({ message: '已进入排序模式，点击上下箭头调整顺序' });
  }

  /**
   * 退出排序模式
   */
  exitSortMode(): void {
    this.isSortMode = false;
    this.loadSources();
  }

  /**
   * 应用排序模式下的筛选（只显示启用的书源）
   */
  applyFilterForSortMode(): void {
    // 只显示启用的书源用于排序
    this.filteredSources = this.allSources.filter(s => s.enabled);
    this.currentPage = 0;
    this.hasMoreData = true;
    this.loadMoreSources(true);
  }

  /**
   * 保存书源排序
   */
  async saveSourceOrder(): Promise<void> {
    if (this.isSavingOrder) return;
    
    this.isSavingOrder = true;
    this.isOperating = true;
    this.operatingMessage = '正在保存排序...';
    
    try {
      // 获取当前显示的启用书源ID列表（按当前顺序）
      const enabledSourceIds = this.filteredSources.map(s => s.id);
      const count = await this.sourceManager.batchUpdateSourceOrder(enabledSourceIds);
      
      this.getUIContext().getPromptAction().showToast({ message: `已保存 ${count} 个书源的排序` });
      this.exitSortMode();
    } catch (error) {
      logger.error(TAG, `保存排序失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存排序失败' });
    } finally {
      this.isSavingOrder = false;
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  /**
   * 移动书源到指定位置
   * @param fromIndex 当前位置索引
   * @param toIndex 目标位置索引
   */
  moveSourceInList(fromIndex: number, toIndex: number): void {
    if (fromIndex < 0 || fromIndex >= this.filteredSources.length) return;
    if (toIndex < 0 || toIndex >= this.filteredSources.length) return;
    if (fromIndex === toIndex) return;
    
    // 交换位置
    const temp = this.filteredSources[fromIndex];
    this.filteredSources[fromIndex] = this.filteredSources[toIndex];
    this.filteredSources[toIndex] = temp;
    
    // 刷新显示列表
    this.loadMoreSources(true);
  }

  /**
   * 置顶书源
   * @param currentIndex 当前位置索引
   */
  moveSourceToTop(currentIndex: number): void {
    if (currentIndex <= 0 || currentIndex >= this.filteredSources.length) return;
    
    // 移除并插入到开头
    const source = this.filteredSources.splice(currentIndex, 1)[0];
    this.filteredSources.unshift(source);
    
    // 刷新显示列表
    this.loadMoreSources(true);
  }

  /**
   * 置底书源
   * @param currentIndex 当前位置索引
   */
  moveSourceToBottom(currentIndex: number): void {
    if (currentIndex < 0 || currentIndex >= this.filteredSources.length - 1) return;
    
    // 移除并插入到末尾
    const source = this.filteredSources.splice(currentIndex, 1)[0];
    this.filteredSources.push(source);
    
    // 刷新显示列表
    this.loadMoreSources(true);
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
    this.getUIContext().getPromptAction().showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 个书源` });
    this.loadSources();
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
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })
      
      // 分组筛选
      if (this.sourceGroups.length > 0) {
        Row() {
          Text('分组筛选')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Blank()
          Button(this.getGroupFilterSwitchLabel())
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .borderRadius(14)
            .height(28)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.cycleGroupFilterDisplayMode();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        Column() {
          if (this.groupFilterDisplayMode === GroupFilterDisplayMode.FULL) {
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap }) {
                Text('全部')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.selectedGroup === ''
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .backgroundColor(this.selectedGroup === '' ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .borderRadius(16)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => this.selectGroup(''))
                
                ForEach(this.sourceGroups, (group: string) => {
                  Text(`${group}(${this.groupCounts.get(group) || 0})`)
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.selectedGroup === group
                      ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .backgroundColor(this.selectedGroup === group ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(16)
                    .margin({ right: 8, bottom: 8 })
                    .onClick(() => this.selectGroup(group))
                })
              }
              .width('100%')
            }
            .scrollBar(BarState.Auto)
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
            .transition(
              TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ y: 6 }).animation({ duration: 200, curve: Curve.EaseOut }))
            )
          } else {
            Scroll() {
              Row() {
                // 全部按钮
                Text('全部')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.selectedGroup === ''
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
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
                    .fontColor(this.selectedGroup === group
                      ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
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
            .transition(
              TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ y: -6 }).animation({ duration: 200, curve: Curve.EaseOut }))
            )
          }
        }
        .width('100%')
        .height(this.getGroupFilterContainerHeight())
        .opacity(this.groupFilterDisplayMode === GroupFilterDisplayMode.COLLAPSED ? 0 : 1)
        .clip(true)
        .animation({ duration: 200, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .id('guide_novel_source_stats')
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
    .margin({ top: 8 })
  }

  @Builder
  buildQuickActionPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('快捷操作')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Button('收起')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .borderRadius(14)
          .height(28)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.toggleQuickActionPanel();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      // 校验相关
      Row({ space: 8 }) {
        Button('一键校验')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('warning'))
          .backgroundColor(this.getGlassActionButtonBackground('warning'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('warning')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.quickValidateSources())

        Button('高级校验')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('accent'))
          .backgroundColor(this.getGlassActionButtonBackground('accent'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('accent')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.showValidationConfigDialog())

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14 })

      // 管理相关
      Row({ space: 8 }) {
        Button('多选管理')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.toggleMultiSelectMode())

        Button('分组管理')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('accent'))
          .backgroundColor(this.getGlassActionButtonBackground('accent'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('accent')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.showGroupManageDialog())

        Button('排序模式')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.enterSortMode())
      }
      .width('100%')
      .padding({ left: 14, right: 14 })

      // 书源维护相关
      Row({ space: 8 }) {
        Button('导入书源')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('primary'))
          .backgroundColor(this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('primary')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => this.showImportOptions())

        Button('全部启用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('success'))
          .backgroundColor(this.getGlassActionButtonBackground('success'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('success')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => {
            void this.batchEnableSources(true);
          })

        Button('全部禁用')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .onClick(() => {
            void this.batchEnableSources(false);
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 12 })
    }
    .width('100%')
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
    .margin({ top: 8 })
  }

  @Builder
  buildListGuideHeader(showGuideDetail: boolean) {
    Column({ space: 4 }) {
      Row() {
        Text('书源列表')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Blank()
        Text(`${this.filteredSources.length} 项`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        if (!this.isSortMode && !this.isMultiSelectMode && !this.showQuickActionPanel) {
          Button('展开')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .borderRadius(14)
            .height(28)
            .padding({ left: 12, right: 12 })
            .margin({ left: 10 })
            .onClick(() => {
              this.toggleQuickActionPanel();
            })
        }
      }
      .width('100%')

      Column() {
        Text('点击卡片进入搜索，点击右侧更多按钮进行编辑/调试/置顶/删除')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(showGuideDetail ? 16 : 0)
      .opacity(showGuideDetail ? 1 : 0)
      .clip(true)
      .animation({ duration: 200, curve: Curve.EaseOut })
    }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 8 })
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
      .id('guide_novel_source_list')
  }

  @Builder
  buildLoading() {
    Column() {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('正在加载书源...')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      }
      .padding({ left: 26, right: 26, top: 24, bottom: 24 })
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
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
      .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 }).animation({ duration: 200, curve: Curve.EaseOut })))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  buildEmpty() {
    Column() {
      Column() {
        Text('暂无书源')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        Text('前往右上角更多菜单中"导入书源"')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 8 })
      }
      .padding({ left: 24, right: 24, top: 24, bottom: 24 })
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
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildSourceList() {
    List({ scroller: this.listScroller }) {
      // 排序模式下使用完整的 filteredSources，否则使用分页的 displayedSources
      ForEach(this.isSortMode ? this.filteredSources : this.displayedSources, (source: NovelSourceInfo, index: number) => {
        ListItem() {
          this.buildSourceItem(source, index)
        }
        .swipeAction(this.isSortMode ? undefined : {
          end: this.buildSwipeActions(source)
        })
      })

      // 加载更多指示器（排序模式下不显示）
      if (this.hasMoreData && !this.isSortMode) {
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

      ListItem() {
        Row()
          .width('100%')
          .height(24 + this.navigationBarHeight)
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Auto)
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

          if (this.isAudioSource(source)) {
            Text('听书')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor('#1677FF')
              .backgroundColor('#E6F4FF')
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
      
      // 排序模式下显示移动按钮，否则显示开关
      if (this.isSortMode) {
        Row({ space: 8 }) {
          // 置顶按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_up_circle'))
              .fontSize(16)
              .fontColor([index === 0 ?
                ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .enabled(index > 0)
          .onClick(() => this.moveSourceToTop(index))

          // 上移按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_up'))
              .fontSize(18)
              .fontColor([index === 0 ?
                ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .enabled(index > 0)
          .onClick(() => this.moveSourceInList(index, index - 1))

          // 下移按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(18)
              .fontColor([index === this.filteredSources.length - 1 ?
                ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .enabled(index < this.filteredSources.length - 1)
          .onClick(() => this.moveSourceInList(index, index + 1))

          // 置底按钮
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.chevron_down_circle'))
              .fontSize(16)
              .fontColor([index === this.filteredSources.length - 1 ?
                ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme) :
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
          .width(32)
          .height(32)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .enabled(index < this.filteredSources.length - 1)
          .onClick(() => this.moveSourceToBottom(index))
        }
      } else {
        Row({ space: 8 }) {
          Toggle({ type: ToggleType.Switch, isOn: source.enabled })
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onChange((isOn: boolean) => {
              this.toggleSource(source, isOn);
            })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(16)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          .width(30)
          .height(30)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .shadow({
            radius: 8,
            color: this.getGlassActionButtonShadowColor(),
            offsetX: 0,
            offsetY: 3
          })
          .onClick(() => {
            this.showSourceActionMenu(source);
          })
        }
      }
    }
    .width('100%')
    .padding({ left: 12, right: 16, top: 12, bottom: 12 })
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
      // 排序模式下不响应点击
      if (this.isSortMode) {
        return;
      }
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
          // 排序模式下不响应长按
          if (!this.isMultiSelectMode && !this.isSortMode) {
            this.showSourceActionMenu(source);
          }
        })
    )
    .bindPopup(this.showSourceContextMenu && this.contextMenuSource?.id === source.id, {
      builder: this.buildSourceContextMenu(source),
      placement: Placement.Bottom,
      popupColor: Color.Transparent,
      enableArrow: false,
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
      .backgroundColor(this.isContextMenuActionHighlighted('search')
        ? SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)
        : Color.Transparent)
      .backgroundBlurStyle(
        this.isContextMenuActionHighlighted('search') ? this.getGlassActionButtonBlurStyle() : undefined,
        this.getGlassActionButtonBlurOptions()
      )
      .backgroundEffect(this.isContextMenuActionHighlighted('search')
        ? this.getGlassActionButtonBackgroundEffect()
        : undefined)
      .borderRadius(6)
      .onHover((isHover: boolean) => {
        this.updateContextMenuHoverState('search', isHover);
      })
      .onTouch((event: TouchEvent) => {
        this.updateContextMenuTouchState('search', event);
      })
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
      .backgroundColor(this.isContextMenuActionHighlighted('edit')
        ? SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)
        : Color.Transparent)
      .backgroundBlurStyle(
        this.isContextMenuActionHighlighted('edit') ? this.getGlassActionButtonBlurStyle() : undefined,
        this.getGlassActionButtonBlurOptions()
      )
      .backgroundEffect(this.isContextMenuActionHighlighted('edit')
        ? this.getGlassActionButtonBackgroundEffect()
        : undefined)
      .borderRadius(6)
      .onHover((isHover: boolean) => {
        this.updateContextMenuHoverState('edit', isHover);
      })
      .onTouch((event: TouchEvent) => {
        this.updateContextMenuTouchState('edit', event);
      })
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
      .backgroundColor(this.isContextMenuActionHighlighted('debug')
        ? SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)
        : Color.Transparent)
      .backgroundBlurStyle(
        this.isContextMenuActionHighlighted('debug') ? this.getGlassActionButtonBlurStyle() : undefined,
        this.getGlassActionButtonBlurOptions()
      )
      .backgroundEffect(this.isContextMenuActionHighlighted('debug')
        ? this.getGlassActionButtonBackgroundEffect()
        : undefined)
      .borderRadius(6)
      .onHover((isHover: boolean) => {
        this.updateContextMenuHoverState('debug', isHover);
      })
      .onTouch((event: TouchEvent) => {
        this.updateContextMenuTouchState('debug', event);
      })
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
      .backgroundColor(this.isContextMenuActionHighlighted('pin')
        ? SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)
        : Color.Transparent)
      .backgroundBlurStyle(
        this.isContextMenuActionHighlighted('pin') ? this.getGlassActionButtonBlurStyle() : undefined,
        this.getGlassActionButtonBlurOptions()
      )
      .backgroundEffect(this.isContextMenuActionHighlighted('pin')
        ? this.getGlassActionButtonBackgroundEffect()
        : undefined)
      .borderRadius(6)
      .onHover((isHover: boolean) => {
        this.updateContextMenuHoverState('pin', isHover);
      })
      .onTouch((event: TouchEvent) => {
        this.updateContextMenuTouchState('pin', event);
      })
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
      .backgroundColor(this.isContextMenuActionHighlighted('delete')
        ? SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme)
        : Color.Transparent)
      .backgroundBlurStyle(
        this.isContextMenuActionHighlighted('delete') ? this.getGlassActionButtonBlurStyle() : undefined,
        this.getGlassActionButtonBlurOptions()
      )
      .backgroundEffect(this.isContextMenuActionHighlighted('delete')
        ? this.getGlassActionButtonBackgroundEffect()
        : undefined)
      .borderRadius(6)
      .onHover((isHover: boolean) => {
        this.updateContextMenuHoverState('delete', isHover);
      })
      .onTouch((event: TouchEvent) => {
        this.updateContextMenuTouchState('delete', event);
      })
      .onClick(() => {
        const sourceToDelete = this.contextMenuSource;
        this.hideSourceContextMenu();
        if (sourceToDelete) {
          this.deleteSource(sourceToDelete);
        }
      })
    }
    .width(144)
    .padding(6)
    .backgroundColor(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundColor)
    .backgroundBlurStyle(
      SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurStyle,
      SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurOptions
    )
    .backgroundEffect(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundEffect)
    .linearGradient(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.surfaceGradient)
    .borderRadius(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius)
    .clip(true)
    .shadow({
      radius: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius + 2,
      color: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.shadowColor,
      offsetX: 0,
      offsetY: 4
    })
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
        .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 180, curve: Curve.EaseOut }))
    )
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
        .fontColor(this.getGlassActionButtonTextColor('danger'))
        .backgroundColor(this.getGlassActionButtonBackground('danger'))
        .linearGradient(this.getGlassActionButtonGradient())
        .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
        .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
        .border({
          width: 1,
          color: this.getGlassActionButtonBorderColor('danger')
        })
        .shadow({
          radius: 8,
          color: this.getGlassActionButtonShadowColor(),
          offsetX: 0,
          offsetY: 3
        })
        .borderRadius(8)
        .width(80)
        .height('100%')
        .onClick(() => this.deleteSource(source))
    }
  }

  @Builder
  buildImportEntryDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 透明点击层：用于点空白关闭，不使用遮罩效果
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          if (!this.isImporting) {
            this.showImportEntryDialog = false;
          }
        })

      Column({ space: 12 }) {
        Text('导入书源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('兼容 Legado：文件、网络链接导入')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        Column({ space: 10 }) {
          Button('从文件导入')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .borderRadius(10)
            .height(42)
            .width('100%')
            .onClick(() => {
              this.showImportEntryDialog = false;
              void this.importFromFile();
            })

          Button('网络导入（含 Legado 链接）')
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('primary'))
            .backgroundColor(this.getGlassActionButtonBackground('primary'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('primary')
            })
            .borderRadius(10)
            .height(42)
            .width('100%')
            .onClick(() => {
              this.showImportEntryDialog = false;
              this.showImportUrlDialog = true;
            })
        }
        .width('100%')
        .margin({ top: 8 })

        Button('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .borderRadius(8)
          .height(34)
          .width('100%')
          .margin({ top: 4 })
          .onClick(() => {
            this.showImportEntryDialog = false;
          })
      }
      .width('90%')
      .constraintSize({ maxWidth: 680, maxHeight: '80%' })
      .padding(24)
      .backgroundColor(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundColor)
      .backgroundBlurStyle(
        SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurStyle,
        SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurOptions
      )
      .backgroundEffect(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundEffect)
      .linearGradient(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.surfaceGradient)
      .borderRadius(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius)
      .clip(true)
      .border({
        width: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderWidth,
        color: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderColor
      })
      .shadow({
        radius: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius + 4,
        color: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.shadowColor,
        offsetX: 0,
        offsetY: 8
      })
      .transition(
        TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 220, curve: Curve.EaseOut }))
      )
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .zIndex(3000)
  }

  @Builder
  buildImportDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        if (!this.isImporting) {
          this.showImportDialog = false;
        }
      }
    }) {
      Column() {
        Text('导入书源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('粘贴Legado书源JSON')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 8 })

        TextArea({ placeholder: '粘贴书源JSON...', text: this.importText })
          .width('100%')
          .height(200)
          .margin({ top: 16 })
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)
          .onChange((value: string) => {
            this.importText = value;
          })

        Button(this.isImporting ? '导入中...' : '导入')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isImporting ?
            this.getGlassActionButtonTextColor('neutral') :
            this.getGlassActionButtonTextColor('primary'))
          .backgroundColor(this.isImporting ?
            this.getGlassActionButtonBackground('neutral') :
            this.getGlassActionButtonBackground('primary'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.isImporting ?
              this.getGlassActionButtonBorderColor('neutral') :
              this.getGlassActionButtonBorderColor('primary')
          })
          .borderRadius(8)
          .height(34)
          .width('100%')
          .margin({ top: 16 })
          .enabled(!this.isImporting)
          .onClick(() => this.doImport())

        Button('取消')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .borderRadius(8)
          .height(34)
          .width('100%')
          .margin({ top: 12 })
          .onClick(() => {
            this.showImportDialog = false;
            this.importText = '';
          })
      }
      .width('100%')
    }
  }

  @Builder
  buildImportUrlDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 透明点击层：用于点空白关闭，不使用遮罩效果
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          if (!this.isImporting) {
            this.showImportUrlDialog = false;
          }
        })

      Column() {
        Text('网络导入书源')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('支持 http/https 链接，或 legado://import/... 的 src 参数')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 8 })

        TextInput({ placeholder: '请输入链接', text: this.importUrl })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.importUrl = value;
          })

        Row() {
          Button('取消')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .margin({ right: 8 })
            .enabled(!this.isImporting)
            .onClick(() => {
              this.showImportUrlDialog = false;
            })

          Button(this.isImporting ? '导入中...' : '下载并导入')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.isImporting ?
              this.getGlassActionButtonTextColor('neutral') :
              this.getGlassActionButtonTextColor('primary'))
            .backgroundColor(this.isImporting ?
              this.getGlassActionButtonBackground('neutral') :
              this.getGlassActionButtonBackground('primary'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.isImporting ?
                this.getGlassActionButtonBorderColor('neutral') :
                this.getGlassActionButtonBorderColor('primary')
            })
            .borderRadius(8)
            .height(34)
            .layoutWeight(1)
            .margin({ left: 8 })
            .enabled(!this.isImporting)
            .onClick(() => this.importFromNetwork())
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('90%')
      .constraintSize({ maxWidth: 680, maxHeight: '80%' })
      .padding(24)
      .backgroundColor(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundColor)
      .backgroundBlurStyle(
        SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurStyle,
        SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurOptions
      )
      .backgroundEffect(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundEffect)
      .linearGradient(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.surfaceGradient)
      .borderRadius(SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius)
      .clip(true)
      .border({
        width: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderWidth,
        color: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderColor
      })
      .shadow({
        radius: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius + 4,
        color: SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.shadowColor,
        offsetX: 0,
        offsetY: 8
      })
      .transition(
        TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 220, curve: Curve.EaseOut }))
      )
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .zIndex(3000)
  }

  @Builder
  buildGroupInputDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showGroupInputDialog = false;
      }
    }) {
      Column({ space: 14 }) {
        Text('新建并添加分组')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text('输入分组名称后，将当前选中的书源直接加入该分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        TextInput({ placeholder: '请输入分组名称', text: this.groupInputValue })
          .width('100%')
          .height(44)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.groupInputValue = value;
          })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .onClick(() => {
              this.showGroupInputDialog = false;
            })

          Button('确认添加')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('primary'))
            .backgroundColor(this.getGlassActionButtonBackground('primary'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('primary')
            })
            .onClick(() => {
              this.confirmGroupInputAndAdd();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  buildValidationSetupDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        if (!this.isValidating) {
          this.showValidationSetupDialog = false;
        }
      }
    }) {
      Column({ space: 14 }) {
        Text('高级校验配置')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(
          this.isValidationTargetAll
            ? `将校验全部书源（${this.validationTargetCount} 个）`
            : `将校验已选书源（${this.validationTargetCount} 个）`
        )
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        Text('校验模式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Row({ space: 8 }) {
          Button('快速')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.validationPresetMode === ValidationPresetMode.QUICK
              ? this.getGlassActionButtonTextColor('primary')
              : this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.validationPresetMode === ValidationPresetMode.QUICK
              ? this.getGlassActionButtonBackground('primary')
              : this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.validationPresetMode === ValidationPresetMode.QUICK
                ? this.getGlassActionButtonBorderColor('primary')
                : this.getGlassActionButtonBorderColor('neutral')
            })
            .onClick(() => {
              this.validationPresetMode = ValidationPresetMode.QUICK;
            })

          Button('标准')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.validationPresetMode === ValidationPresetMode.STANDARD
              ? this.getGlassActionButtonTextColor('primary')
              : this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.validationPresetMode === ValidationPresetMode.STANDARD
              ? this.getGlassActionButtonBackground('primary')
              : this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.validationPresetMode === ValidationPresetMode.STANDARD
                ? this.getGlassActionButtonBorderColor('primary')
                : this.getGlassActionButtonBorderColor('neutral')
            })
            .onClick(() => {
              this.validationPresetMode = ValidationPresetMode.STANDARD;
            })

          Button('完整')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.validationPresetMode === ValidationPresetMode.FULL
              ? this.getGlassActionButtonTextColor('primary')
              : this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.validationPresetMode === ValidationPresetMode.FULL
              ? this.getGlassActionButtonBackground('primary')
              : this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.validationPresetMode === ValidationPresetMode.FULL
                ? this.getGlassActionButtonBorderColor('primary')
                : this.getGlassActionButtonBorderColor('neutral')
            })
            .onClick(() => {
              this.validationPresetMode = ValidationPresetMode.FULL;
            })
        }
        .width('100%')

        Text(this.getValidationPresetDescription(this.validationPresetMode))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .width('100%')

        Text('并发线程')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')

        Scroll() {
          Row({ space: 8 }) {
            ForEach(VALIDATION_CONCURRENCY_OPTIONS, (concurrency: number) => {
              Button(`${concurrency} 线程`)
                .height(32)
                .borderRadius(8)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(this.validationConcurrencyInput === concurrency
                  ? this.getGlassActionButtonTextColor('primary')
                  : this.getGlassActionButtonTextColor('neutral'))
                .backgroundColor(this.validationConcurrencyInput === concurrency
                  ? this.getGlassActionButtonBackground('primary')
                  : this.getGlassActionButtonBackground('neutral'))
                .linearGradient(this.getGlassActionButtonGradient())
                .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
                .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
                .border({
                  width: 1,
                  color: this.validationConcurrencyInput === concurrency
                    ? this.getGlassActionButtonBorderColor('primary')
                    : this.getGlassActionButtonBorderColor('neutral')
                })
                .onClick(() => {
                  this.validationConcurrencyInput = concurrency;
                })
            })
          }
        }
        .width('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)

        TextInput({ placeholder: '请输入校验关键词', text: this.validationKeywordInput })
          .width('100%')
          .height(44)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.validationKeywordInput = value;
          })

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .enabled(!this.isValidating)
            .onClick(() => {
              this.showValidationSetupDialog = false;
            })

          Button(this.isValidating ? '校验中...' : '开始校验')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('warning'))
            .backgroundColor(this.getGlassActionButtonBackground('warning'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('warning')
            })
            .enabled(!this.isValidating)
            .onClick(() => {
              this.confirmValidationSetupDialog();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  buildGroupPickerDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        this.showGroupPickerDialog = false;
      }
    }) {
      Column({ space: 12 }) {
        Text(this.groupPickerMode === 'add' ? '添加到分组' : '从分组移除')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.groupPickerMode === 'add'
          ? '请选择目标分组，或新建分组后添加'
          : '请选择要移除的分组')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))

        TextInput({ placeholder: '搜索分组名称', text: this.groupPickerKeyword })
          .width('100%')
          .height(42)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.updateGroupPickerKeyword(value);
          })

        if (this.groupPickerFilteredGroups.length > 0) {
          List() {
            ForEach(this.groupPickerFilteredGroups, (groupName: string) => {
              ListItem() {
                Button(groupName)
                  .width('100%')
                  .height(38)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.getGlassActionButtonTextColor('neutral'))
                  .backgroundColor(this.getGlassActionButtonBackground('neutral'))
                  .linearGradient(this.getGlassActionButtonGradient())
                  .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
                  .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
                  .border({
                    width: 1,
                    color: this.getGlassActionButtonBorderColor('neutral')
                  })
                  .borderRadius(8)
                  .onClick(() => {
                    this.selectGroupFromPicker(groupName);
                  })
              }
              .padding({ top: 4, bottom: 4 })
            })
          }
          .width('100%')
          .height(220)
          .divider({
            strokeWidth: 0.5,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme),
            startMargin: 0,
            endMargin: 0
          })
        } else {
          Column() {
            Text(this.groupPickerKeyword.trim().length > 0 ? '未找到匹配的分组' : '暂无可用分组')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .borderRadius(8)
        }

        if (this.groupPickerMode === 'add') {
          Button('新建分组并添加')
            .width('100%')
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('accent'))
            .backgroundColor(this.getGlassActionButtonBackground('accent'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('accent')
            })
            .onClick(() => {
              this.showGroupPickerDialog = false;
              this.groupInputValue = '';
              this.showGroupInputDialog = true;
            })
        }

        Button('取消')
          .width('100%')
          .height(34)
          .borderRadius(8)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getGlassActionButtonTextColor('neutral'))
          .backgroundColor(this.getGlassActionButtonBackground('neutral'))
          .linearGradient(this.getGlassActionButtonGradient())
          .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
          .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
          .border({
            width: 1,
            color: this.getGlassActionButtonBorderColor('neutral')
          })
          .onClick(() => {
            this.showGroupPickerDialog = false;
          })
      }
      .width('100%')
    }
  }

  @Builder
  buildDeleteConfirmDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      onMaskTap: () => {
        if (!this.isOperating) {
          this.dismissDeleteConfirmDialog();
        }
      }
    }) {
      Column({ space: 14 }) {
        Text(this.deleteConfirmTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Text(this.deleteConfirmMessage)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('neutral'))
            .backgroundColor(this.getGlassActionButtonBackground('neutral'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('neutral')
            })
            .enabled(!this.isOperating)
            .onClick(() => {
              this.dismissDeleteConfirmDialog();
            })

          Button(this.isOperating ? '删除中...' : '确认删除')
            .layoutWeight(1)
            .height(34)
            .borderRadius(8)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getGlassActionButtonTextColor('danger'))
            .backgroundColor(this.getGlassActionButtonBackground('danger'))
            .linearGradient(this.getGlassActionButtonGradient())
            .backgroundBlurStyle(this.getGlassActionButtonBlurStyle(), this.getGlassActionButtonBlurOptions())
            .backgroundEffect(this.getGlassActionButtonBackgroundEffect())
            .border({
              width: 1,
              color: this.getGlassActionButtonBorderColor('danger')
            })
            .enabled(!this.isOperating)
            .onClick(() => {
              void this.confirmDeleteDialogAction();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  private resolveImportErrorText(error: ImportErrorValue): string {
    if (error === undefined || error === null) {
      return '未知错误';
    }
    if (typeof error === 'string' || typeof error === 'number' || typeof error === 'boolean') {
      return String(error);
    }
    if (error instanceof Error) {
      const message = error.message ? error.message.trim() : '';
      if (message.length > 0) {
        return message;
      }
      return error.name ? error.name : 'Error';
    }

    const objectError = error as Object;
    const entries = Object.entries(objectError) as [string, Object][];
    let message = '';
    let code = '';
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = String(entries[i][1]);
      if (message.length === 0 && (key === 'message' || key === 'msg' || key === 'error' || key === 'detail')) {
        message = value;
      }
      if (code.length === 0 && (key === 'code' || key === 'statusCode' || key === 'status' || key === 'errno')) {
        code = value;
      }
    }
    if (message.length > 0 && code.length > 0) {
      return `${message} (code=${code})`;
    }
    if (message.length > 0) {
      return message;
    }
    if (code.length > 0) {
      return `错误码 ${code}`;
    }
    try {
      const fallback = JSON.stringify(objectError);
      if (fallback && fallback.length > 0 && fallback !== '{}') {
        return fallback;
      }
    } catch (_error) {
    }
    return String(objectError);
  }

  private isHttpUrl(url: string): boolean {
    return /^https?:\/\/.+/i.test(url);
  }

  private decodeQueryValue(rawValue: string): string {
    const plusNormalized = rawValue.replace(/\+/g, ' ');
    try {
      return decodeURIComponent(plusNormalized);
    } catch (_error) {
      return plusNormalized;
    }
  }

  private readQueryParamValue(query: string, targetKey: string): string {
    const queryParts = query.split('&');
    const normalizedTargetKey = targetKey.toLowerCase();
    for (const queryPart of queryParts) {
      const eqIndex = queryPart.indexOf('=');
      const rawKey = eqIndex >= 0 ? queryPart.substring(0, eqIndex) : queryPart;
      const rawValue = eqIndex >= 0 ? queryPart.substring(eqIndex + 1) : '';
      const decodedKey = this.decodeQueryValue(rawKey).trim().toLowerCase();
      if (decodedKey === normalizedTargetKey) {
        return this.decodeQueryValue(rawValue).trim();
      }
    }
    return '';
  }

  private resolveNetworkImportUrl(input: string): string {
    const trimmed = input.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (this.isHttpUrl(trimmed)) {
      return trimmed;
    }

    const lowerInput = trimmed.toLowerCase();
    if (!lowerInput.startsWith('legado://')) {
      return '';
    }

    const queryIndex = trimmed.indexOf('?');
    if (queryIndex < 0 || queryIndex >= trimmed.length - 1) {
      return '';
    }
    const query = trimmed.substring(queryIndex + 1);
    const srcValue = this.readQueryParamValue(query, 'src');
    return this.isHttpUrl(srcValue) ? srcValue : '';
  }

  private appendNetworkUrl(target: string[], rawUrl: string): void {
    const normalizedUrl = this.resolveNetworkImportUrl(rawUrl);
    if (normalizedUrl.length === 0) {
      return;
    }
    if (!target.includes(normalizedUrl)) {
      target.push(normalizedUrl);
    }
  }

  private collectSourceUrlsFromValue(target: string[], value: SourceUrlCollectionValue): void {
    if (value === undefined || value === null) {
      return;
    }
    if (typeof value === 'string') {
      this.appendNetworkUrl(target, value);
      return;
    }
    if (Array.isArray(value)) {
      for (const item of value) {
        if (typeof item === 'string') {
          this.appendNetworkUrl(target, item);
        }
      }
    }
  }

  private extractSourceUrlsFromContent(content: string): string[] {
    const trimmedContent = content.trim();
    if (trimmedContent.length === 0) {
      return [];
    }

    if (this.isHttpUrl(trimmedContent) || trimmedContent.toLowerCase().startsWith('legado://')) {
      const directUrl = this.resolveNetworkImportUrl(trimmedContent);
      return directUrl.length > 0 ? [directUrl] : [];
    }

    if (!trimmedContent.startsWith('{')) {
      return [];
    }

    try {
      const parsed: Object = SafeUtils.parseObj(trimmedContent) as Object;
      if (Array.isArray(parsed)) {
        return [];
      }
      const container = parsed as NetworkSourceUrlIndexPayload;
      const sourceUrls: string[] = [];
      this.collectSourceUrlsFromValue(sourceUrls, container.sourceUrls);
      this.collectSourceUrlsFromValue(sourceUrls, container.bookSourceUrls);
      return sourceUrls;
    } catch (_error) {
      return [];
    }
  }

  private async fetchNetworkText(url: string): Promise<string> {
    let request: http.HttpRequest | null = null;
    try {
      request = http.createHttp();
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000,
        header: {
          'Accept': 'application/json,text/plain,*/*'
        }
      });

      const statusCode: number = response.responseCode;
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`HTTP请求失败: ${statusCode}`);
      }

      const responseText = (response.result as string).trim();
      if (responseText.length === 0) {
        throw new Error('网络导入内容为空');
      }
      return responseText;
    } finally {
      if (request) {
        try {
          request.destroy();
        } catch (destroyError) {
          logger.warn(TAG, `网络请求资源释放失败: ${this.resolveImportErrorText(destroyError as ImportErrorValue)}`);
        }
      }
    }
  }

  private async importNetworkJsonContent(content: string, sourceUrl: string): Promise<[number, number]> {
    this.operatingMessage = '正在导入网络书源...';
    const results = await this.sourceManager.importFromJSON(content);
    if (results.length === 0) {
      throw new Error(`未识别到有效书源: ${sourceUrl}`);
    }
    const successCount = results.filter((r: LegadoSourceImportResult) => r.success).length;
    const failCount = results.filter((r: LegadoSourceImportResult) => !r.success).length;
    return [successCount, failCount];
  }

  private async importNetworkSourceRecursive(
    url: string,
    visitedUrls: Set<string>,
    depth: number
  ): Promise<NetworkImportSummary> {
    if (depth > NETWORK_IMPORT_MAX_DEPTH) {
      throw new Error(`网络导入层级过深，已超过 ${NETWORK_IMPORT_MAX_DEPTH} 层`);
    }

    const normalizedUrl = this.resolveNetworkImportUrl(url);
    if (!this.isHttpUrl(normalizedUrl)) {
      throw new Error(`链接格式不正确: ${url}`);
    }

    if (visitedUrls.has(normalizedUrl)) {
      logger.info(TAG, `跳过重复网络导入链接: ${normalizedUrl}`);
      return {
        successCount: 0,
        failCount: 0,
        fetchedCount: 0
      };
    }
    visitedUrls.add(normalizedUrl);

    this.operatingMessage = `正在下载网络书源... (${visitedUrls.size})`;
    logger.info(TAG, `开始拉取网络书源: depth=${depth}, url=${normalizedUrl}`);
    const content = await this.fetchNetworkText(normalizedUrl);
    logger.info(TAG, `网络下载完成: url=${normalizedUrl}, length=${content.length}`);

    const nestedUrls = this.extractSourceUrlsFromContent(content);
    if (nestedUrls.length > 0) {
      logger.info(TAG, `检测到远程 sourceUrls 索引: url=${normalizedUrl}, count=${nestedUrls.length}`);
      let totalSuccess = 0;
      let totalFail = 0;
      let totalFetched = 1;
      for (const nestedUrl of nestedUrls) {
        try {
          const childResult = await this.importNetworkSourceRecursive(nestedUrl, visitedUrls, depth + 1);
          totalSuccess += childResult.successCount;
          totalFail += childResult.failCount;
          totalFetched += childResult.fetchedCount;
        } catch (error) {
          totalFail += 1;
          logger.warn(TAG, `远程 sourceUrls 子任务失败: url=${nestedUrl}, ${this.resolveImportErrorText(error as ImportErrorValue)}`);
        }
      }
      return {
        successCount: totalSuccess,
        failCount: totalFail,
        fetchedCount: totalFetched
      };
    }

    const importResult = await this.importNetworkJsonContent(content, normalizedUrl);
    return {
      successCount: importResult[0],
      failCount: importResult[1],
      fetchedCount: 1
    };
  }

  private async importSingleFilePath(fileUri: string, fileProcessed: number, fileCount: number): Promise<[number, number]> {
    this.operatingMessage = `正在处理文件 ${fileProcessed}/${fileCount}...`;
    logger.info(TAG, `处理文件 ${fileProcessed}/${fileCount}: ${fileUri}`);

    const file: fs.File = SafeFileUtils.openSync(fileUri, fs.OpenMode.READ_ONLY);
    try {
      const stat: fs.Stat = SafeFileUtils.statSync(file.fd);
      const fileSize: number = stat.size;
      logger.info(TAG, `文件大小: ${fileSize} 字节`);

      const maxBufferSize = 50 * 1024 * 1024;
      const bufferSize = Math.min(fileSize, maxBufferSize);
      const buffer = new ArrayBuffer(bufferSize);
      const readLen: number = SafeFileUtils.readSync(file.fd, buffer);
      if (readLen < fileSize) {
        logger.warn(TAG, `文件过大，只读取了 ${readLen}/${fileSize} 字节`);
      }
      if (readLen <= 0) {
        throw new Error('文件读取失败或内容为空');
      }

      const uint8Array = new Uint8Array(buffer, 0, readLen);
      const decoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
      const jsonContent = decoder.decodeToString(uint8Array);

      logger.debug(TAG, `读取到JSON内容，长度: ${jsonContent.length}`);
      this.operatingMessage = `正在导入文件 ${fileProcessed}/${fileCount} 的书源...`;

      const results = await this.sourceManager.importFromJSON(jsonContent);
      const successCount = results.filter((r: LegadoSourceImportResult) => r.success).length;
      const failCount = results.filter((r: LegadoSourceImportResult) => !r.success).length;
      logger.info(TAG, `文件 ${fileProcessed} 导入完成: 成功${successCount}个, 失败${failCount}个`);
      return [successCount, failCount];
    } finally {
      SafeFileUtils.closeSync(file);
    }
  }

  async importFromNetwork(): Promise<void> {
    const rawInput = this.importUrl.trim();
    if (rawInput.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入网络导入链接' });
      return;
    }
    const normalizedUrl = this.resolveNetworkImportUrl(rawInput);
    if (!this.isHttpUrl(normalizedUrl)) {
      this.getUIContext().getPromptAction().showToast({ message: '链接格式不正确，请输入 http/https 或 legado://import/... 链接' });
      return;
    }

    this.isOperating = true;
    this.isImporting = true;
    this.operatingMessage = '正在下载网络书源...';

    try {
      logger.info(TAG, `开始网络导入书源: raw=${rawInput}, normalized=${normalizedUrl}`);
      const importResult = await this.importNetworkSourceRecursive(normalizedUrl, new Set<string>(), 0);
      const successCount = importResult.successCount;
      const failCount = importResult.failCount;
      const fetchedCount = importResult.fetchedCount;

      this.showImportUrlDialog = false;
      this.importUrl = '';
      if (successCount > 0) {
        this.loadSources();
        this.getUIContext().getPromptAction().showToast({
          message: `成功导入 ${successCount} 个书源${failCount > 0 ? `，${failCount} 个失败` : ''}${fetchedCount > 1 ? `（共拉取 ${fetchedCount} 个远程文件）` : ''}`
        });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请检查链接或内容格式' });
      }
      logger.info(TAG, `网络导入书源完成: 成功${successCount}个, 失败${failCount}个, 拉取${fetchedCount}个远程文件`);
    } catch (error) {
      const errorText = this.resolveImportErrorText(error as ImportErrorValue);
      logger.error(TAG, `网络导入书源失败: ${errorText}`);
      this.getUIContext().getPromptAction().showToast({ message: `网络导入失败: ${errorText}` });
    } finally {
      this.isImporting = false;
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

  async doImport(): Promise<void> {
    if (!this.importText.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入书源JSON' });
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
        this.getUIContext().getPromptAction().showToast({ 
          message: `成功导入 ${successCount} 个书源${failCount > 0 ? `，${failCount} 个失败` : ''}` 
        });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请检查JSON格式' });
      }
    } catch (error) {
      logger.error(TAG, `导入失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '导入失败: ' + String(error) });
    }
    
    this.isImporting = false;
    this.isOperating = false;
    this.operatingMessage = '';
  }

  async toggleSource(source: NovelSourceInfo, enabled: boolean): Promise<void> {
    await this.sourceManager.setSourceEnabled(source.id, enabled);
    this.loadSources();
  }

  private openDeleteConfirmDialog(payload: DeleteDialogPayload): void {
    if (payload.sourceIds.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可删除的书源' });
      return;
    }
    this.pendingDeleteSourceIds = payload.sourceIds.slice();
    this.deleteConfirmMode = payload.mode;
    this.deleteConfirmTitle = payload.title;
    this.deleteConfirmMessage = payload.message;
    this.showDeleteConfirmDialog = true;
  }

  private dismissDeleteConfirmDialog(): void {
    this.showDeleteConfirmDialog = false;
    this.pendingDeleteSourceIds = [];
  }

  private async confirmDeleteDialogAction(): Promise<void> {
    if (this.pendingDeleteSourceIds.length === 0) {
      this.dismissDeleteConfirmDialog();
      this.getUIContext().getPromptAction().showToast({ message: '没有可删除的书源' });
      return;
    }
    this.isOperating = true;
    this.operatingMessage = this.deleteConfirmMode === 'single' ? '正在删除书源...' : '正在批量删除书源...';

    let successCount = 0;
    for (const sourceId of this.pendingDeleteSourceIds) {
      try {
        await this.sourceManager.deleteSource(sourceId);
        successCount++;
      } catch (error) {
        logger.error(TAG, `删除失败: ${String(error)}`);
      }
    }

    this.isOperating = false;
    this.operatingMessage = '';
    this.dismissDeleteConfirmDialog();

    if (this.deleteConfirmMode === 'batch') {
      this.selectedSourceIds = new Set();
      this.isMultiSelectMode = false;
    }

    this.loadSources();

    if (successCount > 0) {
      this.getUIContext().getPromptAction().showToast({ message: `已删除 ${successCount} 个书源` });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请稍后重试' });
    }
  }

  deleteSource(source: NovelSourceInfo): void {
    const payload: DeleteDialogPayload = {
      mode: 'single',
      sourceIds: [source.id],
      title: '确认删除',
      message: `确定要删除书源“${source.name}”吗？`
    };
    this.openDeleteConfirmDialog(payload);
  }

  /**
   * 从文件导入书源（支持多文件选择，最多99个）
   */
  async importFromFile(): Promise<void> {
    try {
      // 获取UIAbilityContext
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
      if (!context) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取应用上下文' });
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
      this.isImporting = true;
      this.operatingMessage = `正在读取 ${fileCount} 个文件...`;
      
      let totalSuccessCount = 0;
      let totalFailCount = 0;
      let fileProcessed = 0;
      
      // 逐个处理选中的文件
      for (const fileUri of selectResult) {
        fileProcessed++;
        try {
          const result = await this.importSingleFilePath(fileUri, fileProcessed, fileCount);
          totalSuccessCount += result[0];
          totalFailCount += result[1];
        } catch (fileError) {
          totalFailCount++;
          logger.error(TAG, `处理文件 ${fileUri} 失败: ${this.resolveImportErrorText(fileError as ImportErrorValue)}`);
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
        this.getUIContext().getPromptAction().showToast({ message });
        logger.info(TAG, `书源导入完成: 共处理${fileCount}个文件, 成功${totalSuccessCount}个书源, 失败${totalFailCount}个`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败，请检查JSON格式' });
        logger.error(TAG, '书源导入失败: 没有成功导入任何书源');
      }
    } catch (error) {
      const errorText = this.resolveImportErrorText(error as ImportErrorValue);
      logger.error(TAG, `从文件导入书源失败: ${errorText}`);
      this.getUIContext().getPromptAction().showToast({ message: '导入失败: ' + errorText });
    }
    
    this.isImporting = false;
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
    this.contextMenuHoverAction = '';
    this.showSourceContextMenu = true;
  }

  /**
   * 隐藏书源操作菜单
   */
  hideSourceContextMenu(): void {
    this.showSourceContextMenu = false;
    this.contextMenuHoverAction = '';
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
        this.getUIContext().getPromptAction().showToast({ message: '书源不存在' });
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
      this.getUIContext().getPromptAction().showToast({ message: '打开编辑器失败' });
    }
  }

  /**
   * 切换书源置顶状态
   */
  async toggleSourcePin(source: NovelSourceInfo): Promise<void> {
    const rawSource = this.sourceManager.getSource(source.id);
    if (!rawSource) {
      this.getUIContext().getPromptAction().showToast({ message: '书源不存在' });
      return;
    }
    
    // 切换置顶状态：置顶的书源weight设为1000，取消置顶设为0
    const newWeight = source.weight > 0 ? 0 : 1000;
    rawSource.weight = newWeight;
    
    // 保存到数据库
    try {
      const dataManager = getNovelDataManager();
      await dataManager.saveSource(rawSource);
      this.getUIContext().getPromptAction().showToast({ message: newWeight > 0 ? '已置顶' : '已取消置顶' });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `置顶失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  private normalizeValidationConcurrency(value: number): number {
    if (!Number.isFinite(value)) {
      return VALIDATION_CONCURRENCY_DEFAULT;
    }
    const integerValue = Math.floor(value);
    return Math.max(1, Math.min(VALIDATION_CONCURRENCY_MAX, integerValue));
  }

  private getValidationConcurrency(): number {
    const value = this.settingsManager.getNumber(
      SettingKeys.NOVEL_SOURCE_VALIDATION_CONCURRENCY,
      VALIDATION_CONCURRENCY_DEFAULT
    );
    return this.normalizeValidationConcurrency(value);
  }

  private async saveValidationConcurrency(concurrency: number): Promise<void> {
    const normalized = this.normalizeValidationConcurrency(concurrency);
    try {
      await this.settingsManager.setNumber(SettingKeys.NOVEL_SOURCE_VALIDATION_CONCURRENCY, normalized);
    } catch (error) {
      logger.warn(TAG, `保存校验并发数失败: ${String(error)}`);
    }
  }

  private getValidationPresetDescription(mode: ValidationPresetMode): string {
    switch (mode) {
      case ValidationPresetMode.QUICK:
        return '快速：仅检测搜索流程，适合批量排查。';
      case ValidationPresetMode.FULL:
        return '完整：搜索 + 发现 + 详情 + 分类 + 内容，耗时更长。';
      case ValidationPresetMode.STANDARD:
      default:
        return '标准：搜索 + 详情 + 分类，兼顾速度与准确性。';
    }
  }

  private buildValidationPresetConfig(mode: ValidationPresetMode): Partial<ValidationConfig> {
    switch (mode) {
      case ValidationPresetMode.QUICK:
        return {
          checkSearch: true,
          checkDiscovery: false,
          checkInfo: false,
          checkCategory: false,
          checkContent: false,
          timeout: 60000
        };
      case ValidationPresetMode.FULL:
        return {
          checkSearch: true,
          checkDiscovery: true,
          checkInfo: true,
          checkCategory: true,
          checkContent: true,
          timeout: 180000
        };
      case ValidationPresetMode.STANDARD:
      default:
        return {
          checkSearch: true,
          checkDiscovery: false,
          checkInfo: true,
          checkCategory: true,
          checkContent: false,
          timeout: 120000
        };
    }
  }

  private resolveValidationDialogScope(sourceIds?: string[]): ValidationDialogScope {
    if (sourceIds && sourceIds.length > 0) {
      return {
        sourceIds: sourceIds.slice(),
        validateAll: false
      };
    }
    return {
      sourceIds: [],
      validateAll: true
    };
  }

  private confirmValidationSetupDialog(): void {
    const keyword = this.validationKeywordInput.trim();
    if (keyword.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入校验关键词' });
      return;
    }
    const normalizedConcurrency = this.normalizeValidationConcurrency(this.validationConcurrencyInput);
    const presetConfig = this.buildValidationPresetConfig(this.validationPresetMode);
    const finalConfig: Partial<ValidationConfig> = {
      timeout: presetConfig.timeout,
      checkSearch: presetConfig.checkSearch,
      checkDiscovery: presetConfig.checkDiscovery,
      checkInfo: presetConfig.checkInfo,
      checkCategory: presetConfig.checkCategory,
      checkContent: presetConfig.checkContent,
      keyword: keyword,
      concurrency: normalizedConcurrency
    };
    this.showValidationSetupDialog = false;
    this.validationConcurrencyInput = normalizedConcurrency;
    void this.saveValidationConcurrency(normalizedConcurrency);
    if (this.validationDialogScope.validateAll) {
      void this.doValidateSources(undefined, finalConfig);
      return;
    }
    const selectedSourceIds = this.validationDialogScope.sourceIds.slice();
    void this.doValidateSources(selectedSourceIds, finalConfig);
  }

  /**
   * 显示校验配置对话框
   */
  showValidationConfigDialog(sourceIds?: string[]): void {
    const scope = this.resolveValidationDialogScope(sourceIds);
    const targetCount = scope.validateAll ? this.allSources.length : scope.sourceIds.length;
    if (targetCount === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无可校验的书源' });
      return;
    }
    this.validationDialogScope = scope;
    this.isValidationTargetAll = scope.validateAll;
    this.validationTargetCount = targetCount;
    this.validationPresetMode = ValidationPresetMode.STANDARD;
    this.validationKeywordInput = '我的';
    this.validationConcurrencyInput = this.getValidationConcurrency();
    this.showValidationSetupDialog = true;
  }

  /**
   * 执行校验
   */
  async doValidateSources(sourceIds?: string[], config?: Partial<ValidationConfig>): Promise<void> {
    if (this.isValidating) {
      this.getUIContext().getPromptAction().showToast({ message: '正在校验中...' });
      return;
    }

    const idsToValidate = sourceIds ? sourceIds.slice() : this.allSources.map(s => s.id);
    if (idsToValidate.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无可校验的书源' });
      return;
    }
    
    this.isValidating = true;
    this.isOperating = true;
    this.validationProgress = '准备校验...';
    this.operatingMessage = '准备校验...';
    
    const validator = getNovelSourceValidator();
    
    // 设置 UIAbility 上下文（后台长时任务所需）
    const context = (this.getUIContext().getHostContext() as common.UIAbilityContext) as common.UIAbilityContext;
    validator.setContext(context);
    
    // 后台长时任务由 NovelSourceValidator 内部统一申请和释放，避免重复持有
    
    // 显示进度对话框
    this.showValidationProgressDialog(idsToValidate.length, validator);
    
    // 用于跟踪统计
    let validCount = 0;
    let invalidCount = 0;
    
    try {
      const validationConfig: Partial<ValidationConfig> = {
        timeout: config?.timeout,
        checkSearch: config?.checkSearch,
        checkDiscovery: config?.checkDiscovery,
        checkInfo: config?.checkInfo,
        checkCategory: config?.checkCategory,
        checkContent: config?.checkContent,
        keyword: config?.keyword,
        concurrency: config?.concurrency !== undefined
          ? this.normalizeValidationConcurrency(config.concurrency)
          : this.getValidationConcurrency()
      };

      const result = await validator.validateSources(
        idsToValidate, 
        validationConfig,
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
          this.getUIContext().getPromptAction().showToast({ message: '正在取消校验...' });
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

  /**
   * 关闭失效书源（根据最近一次校验结果）
   * 保留置顶状态，仅禁用书源
   */
  async closeInvalidSources(): Promise<void> {
    if (this.lastValidationInvalidSourceIds.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有失效的书源需要关闭' });
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
    
    this.getUIContext().getPromptAction().showToast({ message });
    
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
      this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
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

    this.getUIContext().getPromptAction().showToast({ message: `已${pin ? '置顶' : '取消置顶'} ${count} 个书源` });
    this.selectedSourceIds = new Set();
    this.loadSources();
  }

  /**
   * 批量启用/禁用书源
   */
  async batchSetEnabled(enabled: boolean): Promise<void> {
    if (this.selectedSourceIds.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
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

    this.getUIContext().getPromptAction().showToast({ message: `已${enabled ? '启用' : '禁用'} ${count} 个书源` });
    this.selectedSourceIds = new Set();
    this.loadSources();
  }

  /**
   * 批量校验书源
   */
  async batchValidateSources(): Promise<void> {
    if (this.selectedSourceIds.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
      return;
    }

    const sourceIds = Array.from(this.selectedSourceIds);
    this.quickValidateSources(sourceIds);
    
    // 退出多选模式
    this.selectedSourceIds = new Set();
    this.isMultiSelectMode = false;
  }

  /**
   * 批量删除书源
   */
  batchDeleteSources(): void {
    if (this.selectedSourceIds.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
      return;
    }

    const sourceIds = Array.from(this.selectedSourceIds);
    const payload: DeleteDialogPayload = {
      mode: 'batch',
      sourceIds: sourceIds,
      title: '确认批量删除',
      message: `确定要删除选中的 ${sourceIds.length} 个书源吗？`
    };
    this.openDeleteConfirmDialog(payload);
  }

  // ==================== 分组管理功能 ====================

  /**
   * 显示添加到分组对话框
   */
  showAddToGroupDialog(): void {
    this.openGroupPickerDialog('add');
  }

  private confirmGroupInputAndAdd(): void {
    const groupName = this.groupInputValue.trim();
    if (groupName.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入分组名称' });
      return;
    }
    this.showGroupInputDialog = false;
    this.groupInputValue = '';
    void this.addSelectedSourcesToGroup(groupName);
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
      this.getUIContext().getPromptAction().showToast({ message: `已将 ${count} 个书源添加到分组 "${groupName}"` });
      this.selectedSourceIds = new Set();
      this.isMultiSelectMode = false;
      this.loadSources();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `添加失败: ${String(error)}` });
    }
    
    this.isOperating = false;
    this.operatingMessage = '';
  }

  /**
   * 显示从分组移除对话框
   */
  showRemoveFromGroupDialog(): void {
    this.openGroupPickerDialog('remove');
  }

  private openGroupPickerDialog(mode: GroupPickerMode): void {
    if (this.selectedSourceIds.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择书源' });
      return;
    }

    const existingGroups = this.sourceManager.getAllGroups();
    if (mode === 'remove' && existingGroups.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无分组' });
      return;
    }

    this.groupPickerMode = mode;
    this.groupPickerGroups = existingGroups.slice();
    this.groupPickerKeyword = '';
    this.groupPickerFilteredGroups = existingGroups.slice();
    this.showGroupPickerDialog = true;
  }

  private updateGroupPickerKeyword(keyword: string): void {
    this.groupPickerKeyword = keyword;
    const normalizedKeyword = keyword.trim().toLowerCase();
    if (normalizedKeyword.length === 0) {
      this.groupPickerFilteredGroups = this.groupPickerGroups.slice();
      return;
    }
    const filtered: string[] = [];
    for (const groupName of this.groupPickerGroups) {
      if (groupName.toLowerCase().includes(normalizedKeyword)) {
        filtered.push(groupName);
      }
    }
    this.groupPickerFilteredGroups = filtered;
  }

  private selectGroupFromPicker(groupName: string): void {
    this.showGroupPickerDialog = false;
    if (this.groupPickerMode === 'add') {
      void this.addSelectedSourcesToGroup(groupName);
      return;
    }
    void this.removeSelectedSourcesFromGroup(groupName);
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
      this.getUIContext().getPromptAction().showToast({ message: `已从分组 "${groupName}" 移除 ${count} 个书源` });
      this.selectedSourceIds = new Set();
      this.isMultiSelectMode = false;
      this.loadSources();
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: `移除失败: ${String(error)}` });
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
      this.getUIContext().getPromptAction().showToast({ message: '暂无分组' });
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
      this.getUIContext().getPromptAction().showToast({ message: `已将 ${count} 个书源的分组从 "${oldName}" 改为 "${newName}"` });
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
      
      this.getUIContext().getPromptAction().showToast({ message: `已合并 ${sourceGroups.length} 个分组，影响 ${totalCount} 个书源` });
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
      
      this.getUIContext().getPromptAction().showToast({ message: `拆分完成：组一 ${group1Count} 个，组二 ${group2Count} 个` });
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
      this.getUIContext().getPromptAction().showToast({ message: `已删除分组 "${groupName}"，影响 ${count} 个书源` });
      this.loadSources();
    } catch (error) {
      logger.error(TAG, `删除分组失败: ${String(error)}`);
      throw new Error(String(error));
    } finally {
      this.isOperating = false;
      this.operatingMessage = '';
    }
  }

}
