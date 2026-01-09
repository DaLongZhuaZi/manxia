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
          // 分组筛选
          Row() {
            Text(this.selectedGroup || '全部')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Text('▼')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .margin({ left: 4 })
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .onClick(() => this.showGroupSelector())
          
          // 排序
          Row() {
            Text(this.getSortTypeName())
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Text('▼')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
              .margin({ left: 4 })
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .margin({ left: 8 })
          .onClick(() => this.showSortSelector())
          
          Blank()
          
          // 编辑按钮
          Text('编辑')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
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

  showGroupSelector(): void {
    const buttons: ActionButton[] = [
      { text: '全部', color: $r('sys.color.ohos_id_color_text_primary') }
    ];
    for (let i = 0; i < this.bookGroups.length && buttons.length < 6; i++) {
      const btn: ActionButton = { text: this.bookGroups[i], color: $r('sys.color.ohos_id_color_text_primary') };
      buttons.push(btn);
    }
    
    promptAction.showActionMenu({
      title: '选择分组',
      buttons: buttons as [ActionButton, ActionButton?, ActionButton?, ActionButton?, ActionButton?, ActionButton?]
    }).then((result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.selectGroup('');
      } else {
        this.selectGroup(this.bookGroups[result.index - 1]);
      }
    }).catch(() => {});
  }

  showSortSelector(): void {
    promptAction.showActionMenu({
      title: '排序方式',
      buttons: [
        { text: '最近阅读', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '书名', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '作者', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '添加时间', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '更新时间', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then((result) => {
      const sortTypes: BookshelfSortType[] = ['lastRead', 'name', 'author', 'addTime', 'updateTime'];
      this.changeSortType(sortTypes[result.index]);
    }).catch(() => {});
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
      this.buildBookList(this.favoriteBooks, '暂无收藏的小说')
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
    .borderRadius(10)
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
          Text(emptyText)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          
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
        List() {
          ForEach(books, (book: NovelBook) => {
            ListItem() {
              this.buildBookItem(book)
            }
          })
        }
        .width('100%')
        .padding({ top: 8 })
      }
    }
    .onRefreshing(() => this.onRefresh())
    .width('100%')
    .layoutWeight(1)
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
    .borderRadius(8)
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
