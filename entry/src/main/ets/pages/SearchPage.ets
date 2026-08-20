// 文件路径: entry/src/main/ets/pages/SearchPage.ets
// 职责: 搜索结果页面，提供跨多字段（标题、标签、章节名、作者、简介）的本地数据库搜索能力

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, UIContext, NavDestinationModifier } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { SearchHistoryManager } from '../Framework/Managers/SearchHistoryManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { DataManager, ComicInfo, ChapterInfo } from '../Framework/Data/DataManager';
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { MangaDetailPageParams } from './MangaDetailPage';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';

const TAG: string = 'SearchPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// NavDestinationContext接口定义
interface NavDestinationContext {
  pathStack: NavPathStack;
}

// 详情页导航路径类型（避免使用内联对象类型）
interface MangaDetailNavPath {
  name: string;
  param: MangaDetailPageParams;
}

// 搜索作用域枚举
enum SearchScope {
  All = 'All',
  MetaOnly = 'MetaOnly',
  IncludeChapters = 'IncludeChapters'
}

// 搜索配置接口
interface SearchConfig {
  query: string;
  scope: SearchScope;
  page: number;
  pageSize: number;
}

// 搜索结果统计接口
interface SearchStats {
  totalCount: number;
  metaMatches: number;
  chapterMatches: number;
}

// Toast配置接口
interface ToastConfig {
  message: string;
  duration: number;
  bottom: number;
}

// 排序类型枚举
enum SortType {
  TitleAsc = 'TitleAsc',
  TitleDesc = 'TitleDesc',
  AuthorAsc = 'AuthorAsc'
}

// 视图模式枚举（保留扩展能力）
enum SearchViewMode {
  List = 'List'
}

// 结果数据源（LazyForEach）
class ComicInfoDataSource implements IDataSource {
  private items: ComicInfo[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: ComicInfo[]) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ComicInfo {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  // 更新数据源内容
  updateItems(items: ComicInfo[]): void {
    this.items = items;
    for (let i = 0; i < this.listeners.length; i++) {
      const listener: DataChangeListener = this.listeners[i];
      listener.onDataReloaded();
    }
  }
}

@Component
struct SearchPage {
  // 导航栈
  @State pathStack: NavPathStack = new NavPathStack();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SearchPage';

  // 沉浸式显示状态（系统栏高度）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 全局UI上下文
  private uiContext: UIContext = this.getUIContext();

  // 数据管理器
  private dataManager: DataManager = DataManager.getInstance();
  private searchHistoryManager: SearchHistoryManager = new SearchHistoryManager(this.dataManager);

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State isLandscape: boolean = false;

  // 搜索状态
  @State private config: SearchConfig = { query: '', scope: SearchScope.All, page: 1, pageSize: 30 };
  @State private searchStats: SearchStats = { totalCount: 0, metaMatches: 0, chapterMatches: 0 };
  @State private isSearching: boolean = false;
  @State private results: ComicInfo[] = [];
  private dataSource: ComicInfoDataSource = new ComicInfoDataSource([]);

  // 建议与历史
  @State private hotKeywords: string[] = ['冒险', '恋爱', '科幻', '校园', '奇幻', '搞笑'];
  @State private searchHistory: string[] = [];
  @State private sortType: SortType = SortType.TitleAsc;
  @State private viewMode: SearchViewMode = SearchViewMode.List;

  aboutToAppear(): void {
    logger.lifecycle(TAG, '🔎 搜索页面显示');
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
    
    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 初始化响应式布局
    this.initResponsiveLayout();

    // 加载历史
    this.loadSearchHistory();
  }

  private lifecycle = new PageLifecycleManager('SearchPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, '搜索页面销毁');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 清理设备变化监听
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  /**
   * 初始化响应式布局
   */
  private initResponsiveLayout(): void {
    const deviceInfo: DeviceInfo = this.deviceManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    
    this.deviceChangeListener = (info: DeviceInfo) => {
      this.isLandscape = info.isLandscape;
      logger.info(TAG, `设备方向变化: ${info.orientation}, isLandscape=${this.isLandscape}`);
    };
    this.deviceManager.addListener(this.deviceChangeListener);
  }

  private showToast(message: string): void {
    const toastConfig: ToastConfig = { message: message, duration: 2000, bottom: 100 };
    try {
      this.getUIContext().getPromptAction().showToast(toastConfig);
    } catch (error) {
      logger.warn(TAG, `Toast显示失败: ${message}`);
    }
  }

  private async loadSearchHistory(): Promise<void> {
    const list: string[] = await this.searchHistoryManager.load('default_user');
    this.searchHistory = list;
  }

  private async saveSearchHistory(): Promise<void> {
    await this.searchHistoryManager.save('default_user', this.searchHistory);
  }

  private addToHistory(query: string): void {
    const task: Promise<string[]> = this.searchHistoryManager.add('default_user', String(query), this.searchHistory);
    task.then((updated: string[]) => {
      this.searchHistory = updated;
    }).catch((error: Error) => {
      logger.warn(TAG, `添加搜索历史失败: ${String(error)}`);
    });
  }

  private clearHistory(): void {
    this.searchHistory = [];
    this.searchHistoryManager.clear('default_user').then(() => {
      logger.info(TAG, '已清空搜索历史');
    }).catch((error: Error) => {
      logger.warn(TAG, `清空搜索历史失败: ${String(error)}`);
    });
  }

  private applySorting(items: ComicInfo[]): ComicInfo[] {
    const copied: ComicInfo[] = items.slice();
    if (this.sortType === SortType.TitleAsc) {
      copied.sort((a: ComicInfo, b: ComicInfo) => a.title.localeCompare(b.title));
    } else if (this.sortType === SortType.TitleDesc) {
      copied.sort((a: ComicInfo, b: ComicInfo) => b.title.localeCompare(a.title));
    } else if (this.sortType === SortType.AuthorAsc) {
      copied.sort((a2: ComicInfo, b2: ComicInfo) => {
        const aa: string = a2.author ? a2.author : '';
        const bb: string = b2.author ? b2.author : '';
        return aa.localeCompare(bb);
      });
    }
    return copied;
  }

  private async performSearch(): Promise<void> {
    const query: string = this.config.query.trim();
    if (query.length === 0) {
      this.results = [];
      this.searchStats = { totalCount: 0, metaMatches: 0, chapterMatches: 0 };
      this.dataSource.updateItems([]);
      return;
    }

    this.isSearching = true;
    try {
      // 加入历史
      this.addToHistory(query);

      // 元数据匹配（标题/作者/简介/标签）
      const metaMatches: ComicInfo[] = await this.dataManager.searchComics(query);

      // 章节名匹配（可选）
      let chapterRelatedComics: ComicInfo[] = [];
      if (this.config.scope === SearchScope.All || this.config.scope === SearchScope.IncludeChapters) {
        chapterRelatedComics = await this.dataManager.searchComicsByChapterTitle(query);
      }

      // 合并去重
      const mergedMap: Map<string, ComicInfo> = new Map<string, ComicInfo>();
      for (let i = 0; i < metaMatches.length; i++) {
        const item: ComicInfo = metaMatches[i];
        mergedMap.set(item.id, item);
      }
      for (let j = 0; j < chapterRelatedComics.length; j++) {
        const item2: ComicInfo = chapterRelatedComics[j];
        if (!mergedMap.has(item2.id)) {
          mergedMap.set(item2.id, item2);
        }
      }

      const mergedListUnsorted: ComicInfo[] = Array.from(mergedMap.values());

      // 排序
      const mergedList: ComicInfo[] = this.applySorting(mergedListUnsorted);

      // 简单分页（本地）
      const startIndex: number = (this.config.page - 1) * this.config.pageSize;
      const endIndex: number = startIndex + this.config.pageSize;
      const paged: ComicInfo[] = mergedList.slice(startIndex, endIndex);

      this.results = paged;
      this.searchStats = {
        totalCount: mergedList.length,
        metaMatches: metaMatches.length,
        chapterMatches: chapterRelatedComics.length
      };
      this.dataSource.updateItems(this.results);
      logger.info(TAG, `搜索完成，共 ${mergedList.length} 条，当前页 ${this.results.length} 条`);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '搜索失败', message);
      this.showToast('搜索失败，请稍后重试');
    } finally {
      this.isSearching = false;
    }
  }

  private goBack(): void {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, '返回失败，导航到首页', String(error));
      this.pathStack.pushPath({ name: 'MainMenuPage' });
    }
  }

  private navigateToDetail(comic: ComicInfo): void {
    const params: MangaDetailPageParams = {
      mangaId: comic.id,
      fromPage: 'SearchPage'
    };
    const path: MangaDetailNavPath = { name: 'MangaDetailPage', param: params };
    try {
      this.pathStack.pushPath(path);
    } catch (error) {
      const message: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, '导航到详情失败', message);
      this.showToast('打开详情失败');
    }
  }

  //（移除自定义顶部栏，改用 HdsNavDestination 标准 titleBar）

  /**
   * 获取搜索范围显示文本
   */
  private getScopeLabel(): string {
    if (this.config.scope === SearchScope.MetaOnly) {
      return '仅元数据';
    } else if (this.config.scope === SearchScope.IncludeChapters) {
      return '含章节名';
    }
    return '全部';
  }

  /**
   * 切换搜索范围
   */
  private toggleSearchScope(): void {
    if (this.config.scope === SearchScope.All) {
      this.config = { query: this.config.query, scope: SearchScope.MetaOnly, page: 1, pageSize: this.config.pageSize };
    } else if (this.config.scope === SearchScope.MetaOnly) {
      this.config = { query: this.config.query, scope: SearchScope.IncludeChapters, page: 1, pageSize: this.config.pageSize };
    } else {
      this.config = { query: this.config.query, scope: SearchScope.All, page: 1, pageSize: this.config.pageSize };
    }
  }

  // 搜索栏
  @Builder
  buildSearchBar() {
    Column({ space: this.isLandscape ? 8 : 12 }) {
      // 输入框 + 搜索按钮（横屏时添加筛选按钮）
      Row({ space: 8 }) {
        TextInput({ placeholder: this.isLandscape ? '搜索...' : '输入关键字（标题、作者、标签、章节名…）', text: this.config.query })
          .layoutWeight(1)
          .height(this.isLandscape ? 36 : 40)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme) })
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.config = { query: value, scope: this.config.scope, page: 1, pageSize: this.config.pageSize };
          })

        // 横屏模式：筛选按钮放在搜索栏内
        if (this.isLandscape) {
          Button(this.getScopeLabel())
            .height(36)
            .fontFamily(this.appFontFamily)
            .padding({ left: 12, right: 12 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .fontSize(12)
            .borderRadius(18)
            .onClick(() => {
              this.toggleSearchScope();
            })
        }

        Button('搜索')
          .fontFamily(this.appFontFamily)
          .width(this.isLandscape ? 60 : 80)
          .height(this.isLandscape ? 36 : 40)
          .fontSize(this.isLandscape ? 13 : 14)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .onClick(() => {
            this.performSearch();
          })
      }

      // 搜索范围选项（仅竖屏显示）
      if (!this.isLandscape) {
        Row({ space: 12 }) {
          // 仅元数据
          Radio({ value: 'MetaOnly', group: 'searchScope' })
            .checked(this.config.scope === SearchScope.MetaOnly)
            .onChange((checked: boolean) => {
              if (checked) {
                this.config = { query: this.config.query, scope: SearchScope.MetaOnly, page: 1, pageSize: this.config.pageSize };
              }
            })
          Text('仅元数据')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          // 包含章节名
          Radio({ value: 'IncludeChapters', group: 'searchScope' })
            .checked(this.config.scope === SearchScope.IncludeChapters)
            .onChange((checked: boolean) => {
              if (checked) {
                this.config = { query: this.config.query, scope: SearchScope.IncludeChapters, page: 1, pageSize: this.config.pageSize };
              }
            })
          Text('包含章节名')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          // 全部
          Radio({ value: 'All', group: 'searchScope' })
            .checked(this.config.scope === SearchScope.All)
            .onChange((checked: boolean) => {
              if (checked) {
                this.config = { query: this.config.query, scope: SearchScope.All, page: 1, pageSize: this.config.pageSize };
              }
            })
          Text('全部')
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.isLandscape ? 8 : 12, bottom: this.isLandscape ? 8 : 12 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
    .borderRadius(12)
  }

  // 建议与历史 chips
  @Builder
  buildSuggestions() {
    Column({ space: 10 }) {
      // 标题与清除历史
      Row({ space: 8 }) {
        Text('搜索历史')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank().layoutWeight(1)
        Button() {
          Row({ space: 4 }) {
            Image($r('sys.symbol.trash')).width(16).height(16)
            Text('清除历史')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 8, right: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          this.clearHistory();
        })
      }

      // 三排横向滑动的历史 chips
      if (this.searchHistory.length > 0) {
        // 第1排
        this.buildHistoryRow(0)
        // 第2排
        this.buildHistoryRow(1)
        // 第3排
        this.buildHistoryRow(2)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // 获取单行历史记录
  private getHistoryRow(rowIndex: number): string[] {
    const result: string[] = [];
    for (let i: number = 0; i < this.searchHistory.length; i++) {
      const mod: number = i % 3;
      if (mod === rowIndex) {
        result.push(this.searchHistory[i]);
      }
    }
    return result;
  }

  // 单行历史chips，使用 Scroll + Row（避免在UI块中声明变量）
  @Builder
  buildHistoryRow(rowIndex: number) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.getHistoryRow(rowIndex), (h: string) => {
          Button(h)
            .height(28)
            .fontFamily(this.appFontFamily)
            .padding({ left: 10, right: 10 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .onClick(() => {
              this.config = { query: h, scope: this.config.scope, page: 1, pageSize: this.config.pageSize };
              this.performSearch();
            })
        })
      }
    }
    .width('100%')
    .height(40)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  private getSortLabel(): string {
    if (this.sortType === SortType.TitleAsc) {
      return '标题升序';
    } else if (this.sortType === SortType.TitleDesc) {
      return '标题降序';
    }
    return '作者升序';
  }

  // 工具栏（排序/分页）
  @Builder
  buildToolbar() {
    Row({ space: 12 }) {
      // 排序切换
      Button(this.getSortLabel())
        .height(28)
        .fontFamily(this.appFontFamily)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          if (this.sortType === SortType.TitleAsc) {
            this.sortType = SortType.TitleDesc;
          } else if (this.sortType === SortType.TitleDesc) {
            this.sortType = SortType.AuthorAsc;
          } else {
            this.sortType = SortType.TitleAsc;
          }
          // 重发搜索保持当前查询与页码
          this.performSearch();
        })

      Blank().layoutWeight(1)

      // 分页控件
      Button('上一页')
        .height(28)
        .fontFamily(this.appFontFamily)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          if (this.config.page > 1) {
            this.config = { query: this.config.query, scope: this.config.scope, page: this.config.page - 1, pageSize: this.config.pageSize };
            this.performSearch();
          }
        })

      Button('下一页')
        .height(28)
        .fontFamily(this.appFontFamily)
        .padding({ left: 10, right: 10 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .onClick(() => {
          const totalPages: number = Math.ceil(this.searchStats.totalCount / this.config.pageSize);
          if (this.config.page < totalPages) {
            this.config = { query: this.config.query, scope: this.config.scope, page: this.config.page + 1, pageSize: this.config.pageSize };
            this.performSearch();
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // 空状态卡片
  @Builder
  buildEmptyState() {
    Column({ space: 8 }) {
      Image($r('app.media.ic_image_placeholder')).width(64).height(64)
      Text('没有找到匹配的结果')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      Text('试试热门关键字或更换搜索范围')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(24)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  // 构建结果项
  @Builder
  buildResultItem(comic: ComicInfo, index: number) {
    Row({ space: 12 }) {
      // 封面
      Image($r('app.media.ic_image_placeholder'))
        .width(60)
        .height(90)
        .borderRadius(6)
        .objectFit(ImageFit.Cover)

      // 文本信息
      Column({ space: 6 }) {
        Text(comic.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (comic.author && comic.author.length > 0) {
          Text(`作者：${comic.author}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (comic.tags && comic.tags.length > 0) {
          Text(`标签：${comic.tags}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }

      Blank().layoutWeight(1)

      // 进入详情
      Button('详情')
        .height(36)
        .fontFamily(this.appFontFamily)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .onClick(() => {
          this.navigateToDetail(comic);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .borderRadius(8)
  }

  // 构建统计与状态
  @Builder
  buildStatusBar() {
    Row({ space: 12 }) {
      Text(`结果：${this.searchStats.totalCount}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      Text(`元数据匹配：${this.searchStats.metaMatches}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      Text(`章节匹配：${this.searchStats.chapterMatches}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  build() {
    // 使用 HdsNavDestination 作为根组件
    HdsNavDestination() {
      // Stack 双层沉浸式结构
      Stack() {
        // 背景层（扩展到系统栏）
        Column()
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))

        // 内容层（按系统栏高度留白）
        Column({ space: 12 }) {
          // 标题栏占位
          Blank().height(TITLE_BAR_HEIGHT_MINI)

          // 搜索栏
          this.buildSearchBar()

          // 状态栏
          this.buildStatusBar()

          // 建议与历史
          this.buildSuggestions()

          // 结果列表（List + LazyForEach，设置显式width/height）
          List() {
            LazyForEach(this.dataSource, (item: ComicInfo, index: number) => {
              ListItem() {
                this.buildResultItem(item, index)
              }
              .width('100%')
            }, (item: ComicInfo) => item.id)
          }
          .width('100%')
          .height('60%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          // 空状态
          if (!this.isSearching && this.results.length === 0 && this.config.query.length > 0) {
            this.buildEmptyState()
          }
        }
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
        .width('100%')
        .height('100%')

        // 顶部标题栏由 HdsNavDestination.titleBar 管理
      }
    }
    .backgroundColor(Color.Transparent)
    .mode(NavDestinationMode.STANDARD)
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
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
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
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)
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
          mainTitle: '搜索',
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    })
  }
}

export { SearchPage };