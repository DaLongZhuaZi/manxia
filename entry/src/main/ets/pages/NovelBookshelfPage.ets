/**
 * 小说书架页面
 * 展示收藏的小说和最近阅读
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelBookshelfPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { getNovelDataManager, NovelDataManager } from '../Framework/Novel/NovelDataManager';
import { NovelBook, NovelReadStatus } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { getNovelSettingsManager, BookshelfSettings, BookshelfSortType, BrowseHistoryItem } from '../Framework/Novel/NovelSettingsManager';
import { AppColors } from '../Framework/Theme/AppColors';

const TAG = 'NovelBookshelfPage';
const TITLE_BAR_HEIGHT_MINI = 56;

/**
 * 按钮配置接口
 */
interface ActionButton {
  text: string;
  color: string | Resource;
}

/**
 * 小说书架页面参数
 */
export interface NovelBookshelfPageParams {
  // 可选参数
}

/**
 * 小说详情页面参数
 * 包含搜索结果中的所有信息，用于在详情页解析失败时作为fallback
 */
export interface NovelDetailPageParams {
  sourceId: string;
  bookUrl: string;
  bookName?: string;
  bookId?: string;
  // 从搜索结果传递的额外信息（用于fallback）
  author?: string;
  kind?: string;
  intro?: string;
  coverUrl?: string;
  latestChapterTitle?: string;
  wordCount?: string;
  sourceName?: string;
}

/**
 * 小说搜索页面参数
 */
export interface NovelSearchPageParams {
  keyword?: string;
  sourceId?: string;    // 指定书源ID，用于单书源搜索
  sourceName?: string;  // 书源名称，用于显示
}

/**
 * 小说阅读器页面参数
 */
export interface NovelReaderPageParams {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  chapterUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  tocUrl?: string; // 目录URL，用于加载章节列表
  // [修复] 添加用于记录浏览历史的字段
  author?: string;
  coverUrl?: string;
  sourceName?: string;
}

/**
 * 小说书源管理页面参数
 */
export interface NovelSourceManagementPageParams {
  // 可选参数
}

/**
 * 小说发现页参数
 */
export interface NovelExplorePageParams {
  sourceId?: string;
}

@Component
export struct NovelBookshelfPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelBookshelfPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State favoriteBooks: NovelBook[] = [];
  @State recentBooks: NovelBook[] = [];
  @State browseHistory: BrowseHistoryItem[] = [];
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State currentTab: number = 0;
  @State bookGroups: string[] = [];
  @State selectedGroup: string = '';
  @State showSortMenu: boolean = false;
  @State showGroupMenu: boolean = false;
  @State isEditMode: boolean = false;
  @State selectedBookIds: string[] = [];
  @State bookshelfSettings: BookshelfSettings = {
    sortType: 'lastRead',
    sortAscending: false,
    showReadProgress: true,
    gridColumns: 3,
    displayMode: 'list'
  };
  @State showFilterPopup: boolean = false; // 筛选popup显示状态
  @State showSortPopup: boolean = false; // 排序popup显示状态
  @State viewMode: 'list' | 'grid' = 'list'; // 视图模式
  @State filterType: 'all' | 'unread' | 'reading' | 'finished' = 'all'; // 筛选类型
  private dataManager: NovelDataManager = getNovelDataManager();
  private settingsManager = getNovelSettingsManager();
  private browseHistoryListener: (() => void) | null = null;

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
    
    // 注册历史浏览变化监听器，实现实时刷新
    this.browseHistoryListener = () => {
      this.browseHistory = this.settingsManager.getBrowseHistory();
    };
    this.settingsManager.addBrowseHistoryListener(this.browseHistoryListener);
  }

  private lifecycle = new PageLifecycleManager('NovelBookshelfPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除历史浏览监听器
    if (this.browseHistoryListener) {
      this.settingsManager.removeBrowseHistoryListener(this.browseHistoryListener);
      this.browseHistoryListener = null;
    }
  }

  async loadBooks(): Promise<void> {
    logger.info(TAG, `开始加载书籍列表`);
    if (!this.isRefreshing) {
      this.isLoading = true;
    }
    try {
      // 加载设置
      await this.settingsManager.loadSettings();
      this.bookshelfSettings = this.settingsManager.getBookshelfSettings();
      
      // 加载分组
      this.bookGroups = await this.dataManager.getBookGroups();
      logger.info(TAG, `加载分组: ${this.bookGroups.length}个`);
      
      // 根据分组和排序加载书籍
      if (this.selectedGroup) {
        this.favoriteBooks = await this.dataManager.getBooksByGroup(this.selectedGroup);
        logger.info(TAG, `加载分组书籍: ${this.selectedGroup}, 数量: ${this.favoriteBooks.length}`);
      } else {
        this.favoriteBooks = await this.dataManager.getFavoriteBooksSorted(
          this.bookshelfSettings.sortType,
          this.bookshelfSettings.sortAscending
        );
        logger.info(TAG, `加载收藏书籍: 数量: ${this.favoriteBooks.length}, 排序: ${this.bookshelfSettings.sortType}`);
      }
      this.recentBooks = await this.dataManager.getRecentBooks(20);
      logger.info(TAG, `加载最近阅读: ${this.recentBooks.length}本`);
      
      // 加载历史浏览记录
      this.browseHistory = this.settingsManager.getBrowseHistory();
      logger.info(TAG, `加载浏览历史: ${this.browseHistory.length}条`);
    } catch (error) {
      logger.error(TAG, `加载书籍失败: ${String(error)}`);
    }
    this.isLoading = false;
    this.isRefreshing = false;
  }
  
  /**
   * 下拉刷新
   */
  async onRefresh(): Promise<void> {
    logger.info(TAG, `下拉刷新书籍列表`);
    this.isRefreshing = true;
    await this.loadBooks();
  }

  /**
   * 删除历史浏览记录
   */
  async removeBrowseHistoryItem(item: BrowseHistoryItem): Promise<void> {
    await this.settingsManager.removeBrowseHistory(item.sourceId, item.bookUrl);
  }

  /**
   * 清空历史浏览记录
   */
  async clearBrowseHistory(): Promise<void> {
    await this.settingsManager.clearBrowseHistory();
    promptAction.showToast({ message: '历史浏览已清空' });
  }

  /**
   * 打开历史浏览的书籍详情
   */
  openBrowseHistoryDetail(item: BrowseHistoryItem): void {
    const params: NovelDetailPageParams = {
      sourceId: item.sourceId,
      bookUrl: item.bookUrl,
      bookName: item.bookName,
      author: item.author,
      coverUrl: item.coverUrl,
      sourceName: item.sourceName
    };
    this.pathStack.pushPathByName('NovelDetailPage', params);
  }

  async changeSortType(sortType: BookshelfSortType): Promise<void> {
    this.bookshelfSettings.sortType = sortType;
    const newSettings: BookshelfSettings = {
      sortType: sortType,
      sortAscending: this.bookshelfSettings.sortAscending,
      showReadProgress: this.bookshelfSettings.showReadProgress,
      gridColumns: this.bookshelfSettings.gridColumns,
      displayMode: this.bookshelfSettings.displayMode
    };
    await this.settingsManager.updateBookshelfSettings(newSettings);
    this.showSortMenu = false;
    await this.loadBooks();
  }

  async selectGroup(group: string): Promise<void> {
    this.selectedGroup = group;
    this.showGroupMenu = false;
    await this.loadBooks();
  }

  toggleEditMode(): void {
    this.isEditMode = !this.isEditMode;
    if (!this.isEditMode) {
      this.selectedBookIds = [];
    }
  }

  toggleBookSelection(bookId: string): void {
    const index = this.selectedBookIds.indexOf(bookId);
    if (index >= 0) {
      this.selectedBookIds = this.selectedBookIds.filter(id => id !== bookId);
    } else {
      this.selectedBookIds = [...this.selectedBookIds, bookId];
    }
  }

  isBookSelected(bookId: string): boolean {
    return this.selectedBookIds.indexOf(bookId) >= 0;
  }

  async deleteSelectedBooks(): Promise<void> {
    if (this.selectedBookIds.length === 0) return;
    
    promptAction.showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedBookIds.length} 本书籍吗？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4D4F' }
      ]
    }).then(async (result) => {
      if (result.index === 1) {
        const idsToDelete = [...this.selectedBookIds];
        await this.dataManager.deleteBooksBatch(idsToDelete);
        // 重置选择状态
        this.selectedBookIds = [];
        this.isEditMode = false;
        // 重新加载书籍列表以确保数据同步
        await this.loadBooks();
        promptAction.showToast({ message: '删除成功' });
      }
    });
  }

  async moveSelectedToGroup(): Promise<void> {
    if (this.selectedBookIds.length === 0) return;
    
    const buttons: ActionButton[] = [
      { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') },
      { text: '新建分组', color: $r('sys.color.ohos_id_color_text_primary_activated') }
    ];
    for (let i = 0; i < this.bookGroups.length && buttons.length < 6; i++) {
      const btn: ActionButton = { text: this.bookGroups[i], color: $r('sys.color.ohos_id_color_text_primary') };
      buttons.push(btn);
    }
    
    promptAction.showActionMenu({
      title: '移动到分组',
      buttons: buttons as [ActionButton, ActionButton?, ActionButton?, ActionButton?, ActionButton?, ActionButton?]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) return;
      if (result.index === 1) {
        // 新建分组
        this.showNewGroupDialog();
      } else {
        const groupName = this.bookGroups[result.index - 2];
        const idsToMove = [...this.selectedBookIds];
        await this.dataManager.setBookGroupBatch(idsToMove, groupName);
        // 直接更新本地数据，避免UI闪烁
        // 如果当前有选中分组且移动到其他分组，则从列表中移除
        if (this.selectedGroup && this.selectedGroup !== groupName) {
          this.favoriteBooks = this.favoriteBooks.filter(book => !idsToMove.includes(book.id));
        } else {
          // 更新书籍的分组信息（直接修改属性，然后重新赋值数组触发UI更新）
          for (const book of this.favoriteBooks) {
            if (idsToMove.includes(book.id)) {
              book.groupName = groupName;
            }
          }
          this.favoriteBooks = [...this.favoriteBooks];
        }
        this.selectedBookIds = [];
        this.isEditMode = false;
        promptAction.showToast({ message: `已移动到"${groupName}"` });
      }
    }).catch(() => {});
  }

  showNewGroupDialog(): void {
    // 简化处理，使用默认分组名
    const newGroupName = `分组${this.bookGroups.length + 1}`;
    const idsToMove = [...this.selectedBookIds];
    this.dataManager.setBookGroupBatch(idsToMove, newGroupName).then(() => {
      // 直接更新本地数据，避免UI闪烁
      // 添加新分组到列表
      if (!this.bookGroups.includes(newGroupName)) {
        this.bookGroups = [...this.bookGroups, newGroupName];
      }
      // 如果当前有选中分组，则从列表中移除
      if (this.selectedGroup) {
        this.favoriteBooks = this.favoriteBooks.filter(book => !idsToMove.includes(book.id));
      } else {
        // 更新书籍的分组信息（直接修改属性，然后重新赋值数组触发UI更新）
        for (const book of this.favoriteBooks) {
          if (idsToMove.includes(book.id)) {
            book.groupName = newGroupName;
          }
        }
        this.favoriteBooks = [...this.favoriteBooks];
      }
      this.selectedBookIds = [];
      this.isEditMode = false;
      promptAction.showToast({ message: `已移动到"${newGroupName}"` });
    });
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层
        Column() {
          // 标题栏占位
          Blank().height(TITLE_BAR_HEIGHT_MINI)
          
          // Tab切换
          this.buildTabs()
          
          // 内容区域
          if (this.isLoading) {
            this.buildLoading()
          } else {
            this.buildContent()
          }
        }
        .width('100%')
        .height('100%')
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
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
            },
            menuStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
            },
            menuStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: '小说书架'
        },
        menu: {
          value: this.isEditMode ? [] : [{
            content: {
              label: '搜索',
              icon: $r('sys.symbol.magnifyingglass'),
              isEnabled: true,
              action: () => this.goToSearch()
            }
          }, {
            content: {
              label: '发现',
              icon: $r('sys.symbol.crown'),
              isEnabled: true,
              action: () => {
                const params: NovelExplorePageParams = {};
                this.pathStack.pushPathByName('NovelExplorePage', params);
              }
            }
          }, {
            content: {
              label: '小说设置',
              icon: $r('sys.symbol.gearshape'),
              isEnabled: true,
              action: () => this.goToNovelSettings()
            }
          }]
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.loadBooks();
    })
    .onShown(() => {
      logger.lifecycle(TAG, '📱 页面显示，刷新书籍列表');
      this.loadBooks();
    })
  }

  /**
   * 构建标签栏 - VSCode风格
   */
  @Builder
  buildTabs() {
    Column() {
      Scroll() {
        Row({ space: 0 }) {
          // 收藏Tab
          Row() {
            SymbolGlyph($r('sys.symbol.heart'))
              .fontSize(14)
              .fontColor([this.currentTab === 0
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .margin({ right: 6 })
            Text('收藏')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.currentTab === 0
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .padding({ left: 12, right: 12 })
          .height(35)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.currentTab === 0
            ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
            : Color.Transparent)
          .border({
            width: { top: this.currentTab === 0 ? 2 : 0 },
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          })
          .onClick(() => { this.currentTab = 0; })
          .animation({ duration: 150 })

          // 历史浏览Tab
          Row() {
            SymbolGlyph($r('sys.symbol.clock'))
              .fontSize(14)
              .fontColor([this.currentTab === 1
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
              .margin({ right: 6 })
            Text('历史浏览')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(this.currentTab === 1
                ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .padding({ left: 12, right: 12 })
          .height(35)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.currentTab === 1
            ? ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme)
            : Color.Transparent)
          .border({
            width: { top: this.currentTab === 1 ? 2 : 0 },
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          })
          .onClick(() => { this.currentTab = 1; })
          .animation({ duration: 150 })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .height(35)
      .width('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
      
      // 分组和排序工具栏（仅在收藏页显示）
      if (this.currentTab === 0 && !this.isEditMode) {
        Row() {
          // 视图切换按钮
          Button() {
            SymbolGlyph(this.viewMode === 'list' ? $r('sys.symbol.square_grid_2x2') : $r('sys.symbol.list_bullet'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.viewMode = this.viewMode === 'list' ? 'grid' : 'list';
          })
          
          // 筛选按钮（使用popup）
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.slider_vertical_3'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text(this.getFilterTypeName())
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
          }
          .height(32)
          .backgroundColor(Color.Transparent)
          .margin({ left: 8 })
          .onClick(() => {
            this.showFilterPopup = true;
          })
          .bindPopup(this.showFilterPopup, {
            builder: this.buildFilterPopup(),
            placement: Placement.Bottom,
            width: '180vp',
            onStateChange: (e) => {
              if (!e.isVisible) {
                this.showFilterPopup = false;
              }
            }
          })
          
          // 排序按钮（使用popup）
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.slider_vertical_3'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text(this.getSortTypeName())
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            }
          }
          .height(32)
          .backgroundColor(Color.Transparent)
          .margin({ left: 8 })
          .onClick(() => {
            this.showSortPopup = true;
          })
          .bindPopup(this.showSortPopup, {
            builder: this.buildSortPopup(),
            placement: Placement.Bottom,
            width: '160vp',
            onStateChange: (e) => {
              if (!e.isVisible) {
                this.showSortPopup = false;
              }
            }
          })
          
          Blank()
          
          // 编辑按钮
          Button() {
            SymbolGlyph($r('sys.symbol.square_and_pencil'))
              .fontSize(18)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.toggleEditMode())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      }
      
      // 编辑模式工具栏
      if (this.isEditMode) {
        Row() {
          Text(`已选择 ${this.selectedBookIds.length} 项`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          Blank()
          
          Text('取消')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ right: 16 })
            .onClick(() => this.toggleEditMode())
          
          Text('移动')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.selectedBookIds.length > 0 ? '#1890FF' : '#CCCCCC')
            .margin({ right: 16 })
            .onClick(() => this.moveSelectedToGroup())
          
          Text('删除')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(this.selectedBookIds.length > 0 ? '#FF4D4F' : '#CCCCCC')
            .onClick(() => this.deleteSelectedBooks())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
  }

  getSortTypeName(): string {
    const names: Record<string, string> = {
      'lastRead': '最近阅读',
      'name': '书名',
      'author': '作者',
      'addTime': '添加时间',
      'updateTime': '更新时间'
    };
    return names[this.bookshelfSettings.sortType] || '最近阅读';
  }
  
  getFilterTypeName(): string {
    const names: Record<string, string> = {
      'all': '全部',
      'unread': '未读',
      'reading': '阅读中',
      'finished': '已读完'
    };
    return names[this.filterType] || '全部';
  }
  
  /**
   * 获取筛选后的书籍列表
   */
  getFilteredBooks(): NovelBook[] {
    if (this.filterType === 'all') {
      return this.favoriteBooks;
    }
    return this.favoriteBooks.filter((book: NovelBook) => {
      if (this.filterType === 'unread') {
        return book.readStatus === NovelReadStatus.UNREAD || !book.readStatus;
      } else if (this.filterType === 'reading') {
        return book.readStatus === NovelReadStatus.READING;
      } else if (this.filterType === 'finished') {
        return book.readStatus === NovelReadStatus.FINISHED;
      }
      return true;
    });
  }
  
  /**
   * 构建筛选Popup
   */
  @Builder
  buildFilterPopup() {
    Column() {
      Text('筛选')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })
      
      this.buildFilterOption('全部', 'all')
      this.buildFilterOption('未读', 'unread')
      this.buildFilterOption('阅读中', 'reading')
      this.buildFilterOption('已读完', 'finished')
    }
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }
  
  @Builder
  buildFilterOption(label: string, type: 'all' | 'unread' | 'reading' | 'finished') {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.filterType === type ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Blank()
      if (this.filterType === type) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 8, right: 8 })
    .borderRadius(8)
    .backgroundColor(this.filterType === type ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
      Color.Transparent)
    .onClick(() => {
      this.filterType = type;
      this.showFilterPopup = false;
    })
  }
  
  /**
   * 构建排序Popup
   */
  @Builder
  buildSortPopup() {
    Column() {
      Text('排序')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .margin({ bottom: 12 })
      
      this.buildSortOption('最近阅读', 'lastRead')
      this.buildSortOption('书名', 'name')
      this.buildSortOption('作者', 'author')
      this.buildSortOption('添加时间', 'addTime')
      this.buildSortOption('更新时间', 'updateTime')
    }
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }
  
  @Builder
  buildSortOption(label: string, type: BookshelfSortType) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(this.bookshelfSettings.sortType === type ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      Blank()
      if (this.bookshelfSettings.sortType === type) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }
    }
    .width('100%')
    .height(40)
    .padding({ left: 8, right: 8 })
    .borderRadius(8)
    .backgroundColor(this.bookshelfSettings.sortType === type ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
      Color.Transparent)
    .onClick(() => {
      this.changeSortType(type);
      this.showSortPopup = false;
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
  buildContent() {
    if (this.currentTab === 0) {
      this.buildBookList(this.getFilteredBooks(), '暂无收藏的小说')
    } else {
      this.buildBrowseHistoryList()
    }
  }

  @Builder
  buildBrowseHistoryList() {
    Refresh({ refreshing: $$this.isRefreshing }) {
      if (this.browseHistory.length === 0) {
        Column() {
          Text('暂无浏览记录')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          Text('进入小说详情页即可记录')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 8 })
          
          Button('去搜索小说')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(20)
            .padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .margin({ top: 24 })
            .onClick(() => this.goToSearch())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // 清空按钮
          Row() {
            Blank()
            Text('清空历史')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .onClick(() => this.clearBrowseHistory())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          
          List() {
            ForEach(this.browseHistory, (item: BrowseHistoryItem) => {
              ListItem() {
                this.buildBrowseHistoryItem(item)
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.buildDeleteButton(item)
                  }
                }
              })
            }, (item: BrowseHistoryItem) => `${item.sourceId}_${item.bookUrl}`)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .onRefreshing(() => this.onRefresh())
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  buildBrowseHistoryItem(item: BrowseHistoryItem) {
    Row() {
      // 封面
      if (item.coverUrl) {
        Image(item.coverUrl)
          .width(50)
          .height(70)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(item.bookName.substring(0, 1))
            .fontSize(18)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(50)
        .height(70)
        .borderRadius(6)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }
      
      // 信息
      Column() {
        Text(item.bookName)
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(item.author || '未知作者')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 4 })
        
        Row({ space: 8 }) {
          Text(item.sourceName)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
          
          Text(this.formatBrowseTime(item.browseTime))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        }
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(AppColors.cornerRadius)
    .opacity(AppColors.getTransparency('card'))
    .margin({ left: 16, right: 16, bottom: 8 })
    .onClick(() => this.openBrowseHistoryDetail(item))
  }

  @Builder
  buildDeleteButton(item: BrowseHistoryItem) {
    Row() {
      Text('删除')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
    }
    .width(80)
    .height('100%')
    .backgroundColor('#FF4444')
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.removeBrowseHistoryItem(item))
  }

  /**
   * 格式化浏览时间
   */
  private formatBrowseTime(timestamp: number): string {
    const now = Date.now();
    const diff = now - timestamp;
    const minute = 60 * 1000;
    const hour = 60 * minute;
    const day = 24 * hour;
    
    if (diff < minute) {
      return '刚刚';
    } else if (diff < hour) {
      return `${Math.floor(diff / minute)}分钟前`;
    } else if (diff < day) {
      return `${Math.floor(diff / hour)}小时前`;
    } else if (diff < 7 * day) {
      return `${Math.floor(diff / day)}天前`;
    } else {
      const date = new Date(timestamp);
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
  }

  @Builder
  buildBookList(books: NovelBook[], emptyText: string) {
    Refresh({ refreshing: $$this.isRefreshing }) {
      if (books.length === 0) {
        Column() {
          Text(this.filterType === 'all' ? emptyText : '没有符合条件的小说')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
          if (this.filterType !== 'all') {
            Text('尝试更换筛选条件')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .margin({ top: 8 })
          }
          
          Button('去搜索小说')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(20)
            .padding({ left: 24, right: 24, top: 10, bottom: 10 })
            .margin({ top: 24 })
            .onClick(() => this.goToSearch())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        if (this.viewMode === 'list') {
          // 列表视图
          List() {
            ForEach(books, (book: NovelBook) => {
              ListItem() {
                this.buildBookItem(book)
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.buildBookDeleteButton(book)
                  }
                }
              })
            })
          }
          .width('100%')
          .padding({ top: 8 })
        } else {
          // 网格视图
          Scroll() {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(books, (book: NovelBook) => {
                this.buildBookGridItem(book)
              })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })
          }
          .width('100%')
        }
      }
    }
    .onRefreshing(() => this.onRefresh())
    .width('100%')
    .layoutWeight(1)
  }
  
  /**
   * 构建书籍删除按钮（滑动删除）
   */
  @Builder
  buildBookDeleteButton(book: NovelBook) {
    Row() {
      Text('删除')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
    }
    .width(80)
    .height('100%')
    .backgroundColor('#FF4444')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      promptAction.showDialog({
        title: '确认删除',
        message: `确定要删除"${book.name}"吗？`,
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '删除', color: '#FF4D4F' }
        ]
      }).then(async (result) => {
        if (result.index === 1) {
          await this.dataManager.deleteBook(book.id);
          await this.loadBooks();
          promptAction.showToast({ message: '删除成功' });
        }
      });
    })
  }
  
  /**
   * 构建网格视图的书籍项
   */
  @Builder
  buildBookGridItem(book: NovelBook) {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 封面
        if (book.coverUrl) {
          Image(book.coverUrl)
            .width('100%')
            .height(140)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text(book.name.substring(0, 1))
              .fontSize(28)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
          }
          .width('100%')
          .height(140)
          .borderRadius(8)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .justifyContent(FlexAlign.Center)
        }
        
        // 编辑模式选择框
        if (this.isEditMode) {
          Stack() {
            Circle()
              .width(20)
              .height(20)
              .fill(this.isBookSelected(book.id) ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                'rgba(0,0,0,0.3)')
              .stroke(this.isBookSelected(book.id) ?
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                '#FFFFFF')
              .strokeWidth(2)
            
            if (this.isBookSelected(book.id)) {
              Text('✓')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
            }
          }
          .margin(6)
        }
      }
      
      // 书名
      Text(book.name)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
        .width('100%')
      
      // 作者
      Text(book.author || '未知作者')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
        .width('100%')
    }
    .width('31%')
    .margin({ left: '1%', right: '1%', bottom: 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(AppColors.cornerRadius)
    .opacity(AppColors.getTransparency('card'))
    .padding(6)
    .onClick(() => {
      if (this.isEditMode) {
        this.toggleBookSelection(book.id);
      } else {
        this.openBook(book);
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (!this.isEditMode) {
            this.isEditMode = true;
            this.toggleBookSelection(book.id);
          }
        })
    )
  }

  @Builder
  buildBookItem(book: NovelBook) {
    Row() {
      // 编辑模式下显示选择框
      if (this.isEditMode) {
        Stack() {
          Circle()
            .width(22)
            .height(22)
            .fill(this.isBookSelected(book.id) ? 
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              Color.Transparent)
            .stroke(this.isBookSelected(book.id) ? 
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .strokeWidth(2)
          
          if (this.isBookSelected(book.id)) {
            Text('✓')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
          }
        }
        .width(24)
        .height(24)
        .margin({ right: 8 })
      }
      
      // 封面
      if (book.coverUrl) {
        Image(book.coverUrl)
          .width(80)
          .height(110)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(24)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
        }
        .width(80)
        .height(110)
        .borderRadius(4)
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
        
        Text(book.latestChapterTitle || '暂无章节')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Row() {
          Text(book.sourceName)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(2)
          
          if (book.readStatus === NovelReadStatus.READING) {
            Text(`读到第${(book.lastReadChapterIndex ?? 0) + 1}章`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor('#52C41A')
              .margin({ left: 8 })
          }
        }
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.isBookSelected(book.id) ? 
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) :
      ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(AppColors.cornerRadius)
    .opacity(AppColors.getTransparency('card'))
    .margin({ left: 12, right: 12, bottom: 8 })
    .onClick(() => {
      if (this.isEditMode) {
        this.toggleBookSelection(book.id);
      } else {
        this.openBook(book);
      }
    })
  }

  goToSearch(): void {
    const params: NovelSearchPageParams = {};
    this.pathStack.pushPathByName('NovelSearchPage', params);
  }

  goToSourceManagement(): void {
    const params: NovelSourceManagementPageParams = {};
    this.pathStack.pushPathByName('NovelSourceManagementPage', params);
  }

  goToNovelSettings(): void {
    this.pathStack.pushPathByName('NovelSettingsPage', null);
  }

  goToExplore(): void {
    const params: NovelExplorePageParams = {};
    this.pathStack.pushPathByName('NovelExplorePage', params);
  }

  openBook(book: NovelBook): void {
    const params: NovelDetailPageParams = {
      sourceId: book.sourceId,
      bookUrl: book.bookUrl,
      bookId: book.id,
      bookName: book.name
    };
    this.pathStack.pushPathByName('NovelDetailPage', params);
  }
}
