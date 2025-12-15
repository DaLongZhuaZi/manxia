/**
 * 全局搜索页面
 * 仅搜索本地书库（漫画和电子书）
 */
import { DataService } from '../Framework/Services/DataService';
import { DataManager, ComicInfo } from '../Framework/Data/DataManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBook } from '../Models/EBookModels';
import { Manga, ImageSourceType, MangaStatus, DEFAULT_READING_SETTINGS } from '../Models/MangaModels';
import { ReadingStatus } from '../Framework/Types/StatusEnums';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { logger } from '../Utils/Logger';

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

const TAG = 'GlobalSearchPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

// 筛选类型枚举
enum FilterType {
  PURCHASED = 'purchased',  // 已浏览
  ALL = 'all',             // 全部
  HAS_RESULT = 'hasResult' // 有结果
}

// 搜索结果项类型
type SearchItemType = 'manga' | 'ebook';

// 搜索结果项
interface SearchResultItem {
  manga?: Manga;
  ebook?: EBook;
  source: string;         // 来源：'本地-漫画' 或 '本地-电子书'
  sourceId: string;       // 分组ID
  isLocal: boolean;       // 是否本地
  itemType: SearchItemType; // 项目类型
}

// 本地分组
interface SourceGroup {
  sourceId: string;          // 分组ID：'local-manga' 或 'local-ebook'
  sourceName: string;
  items: SearchResultItem[];
  isSearching: boolean;      // 是否正在搜索
  hasError: boolean;         // 是否搜索出错
  itemType: SearchItemType;  // 分组类型
}

// 导航参数接口
interface MangaDetailNavParam {
  mangaId: string;
}

interface EBookDetailNavParam {
  bookId: string;
}

// 全局搜索页面参数接口
export interface GlobalSearchPageParams {
  initialKeyword?: string;  // 初始搜索关键词
}


@Component
export struct GlobalSearchPage {
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'GlobalSearchPage';
  
  // 搜索相关
  @State searchKeyword: string = '';
  @State filterType: FilterType = FilterType.ALL;
  @State isSearching: boolean = false;
  
  // 结果相关 - 按类型分组（本地漫画、本地电子书）
  @State sourceGroups: SourceGroup[] = [];
  
  // 历史记录
  @State searchHistory: string[] = [];
  
  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;
  @State responsive_gridColumns: number = 5; // 横向滚动时每行显示的项目数
  
  private dataService: DataService = DataService.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private pathStack: NavPathStack = new NavPathStack();
  
  // 页面参数
  @State pageParams: GlobalSearchPageParams | null = null;

  aboutToAppear(): void {
    this.initThemeAware();
    this.loadSearchHistory();
    this.initResponsiveLayout();
  }
  
  /**
   * 处理页面参数，如果有初始关键词则自动搜索
   */
  private handlePageParams(): void {
    if (this.pageParams?.initialKeyword) {
      this.searchKeyword = this.pageParams.initialKeyword;
      logger.info(TAG, `收到初始搜索关键词: ${this.searchKeyword}`);
      this.performSearch();
    }
  }

  aboutToDisappear(): void {
    // 清理主题监听器
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
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
   * 获取筛选后的分组（只返回有结果或正在搜索的分组）
   */
  private getFilteredGroups(): SourceGroup[] {
    // 如果没有搜索关键词，返回空数组（显示搜索历史）
    if (!this.searchKeyword || this.searchKeyword.trim().length === 0) {
      return [];
    }
    
    switch (this.filterType) {
      case FilterType.PURCHASED:
      case FilterType.HAS_RESULT:
        return this.sourceGroups.filter(g => g.items.length > 0);
      case FilterType.ALL:
      default:
        // 返回有结果或正在搜索的分组
        return this.sourceGroups.filter(g => g.items.length > 0 || g.isSearching);
    }
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
   * 执行搜索 - 仅搜索本地漫画和电子书
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword || this.searchKeyword.trim() === '') {
      return;
    }

    try {
      logger.info(TAG, `开始本地搜索: "${this.searchKeyword}"`);
      this.saveSearchHistory(this.searchKeyword);

      // 初始化分组：本地漫画 + 本地电子书
      const groups: SourceGroup[] = [];
      
      // 添加本地漫画分组
      const mangaGroup: SourceGroup = {
        sourceId: 'local-manga',
        sourceName: '本地 - 漫画',
        items: [],
        isSearching: true,
        hasError: false,
        itemType: 'manga'
      };
      groups.push(mangaGroup);

      // 添加本地电子书分组
      const ebookGroup: SourceGroup = {
        sourceId: 'local-ebook',
        sourceName: '本地 - 电子书',
        items: [],
        isSearching: true,
        hasError: false,
        itemType: 'ebook'
      };
      groups.push(ebookGroup);

      this.sourceGroups = groups;

      // 并发搜索本地漫画和电子书
      await Promise.allSettled([
        this.searchLocalManga(),
        this.searchLocalEBooks()
      ]);

      logger.info(TAG, `本地搜索完成`);
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
    }
  }

  /**
   * 搜索本地漫画
   */
  private async searchLocalManga(): Promise<void> {
    const groupIndex = this.sourceGroups.findIndex(g => g.sourceId === 'local-manga');
    if (groupIndex < 0) return;

    try {
      const searchResult = await this.dataService.searchComics('');
      const allManga: Manga[] = this.convertComicsToManga(searchResult.comics);
      const keyword: string = this.searchKeyword.toLowerCase();
      
      const filtered: Manga[] = allManga.filter((manga: Manga): boolean => 
        manga.title.toLowerCase().includes(keyword) ||
        manga.metadata.authors.some((author: string): boolean => author.toLowerCase().includes(keyword)) ||
        manga.metadata.genres.some((genre: string): boolean => genre.toLowerCase().includes(keyword))
      );

      const items: SearchResultItem[] = filtered.map((manga: Manga): SearchResultItem => {
        const item: SearchResultItem = {
          manga: manga,
          source: '本地 - 漫画',
          sourceId: 'local-manga',
          isLocal: true,
          itemType: 'manga'
        };
        return item;
      });

      this.sourceGroups[groupIndex].items = items;
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = false;

      // 触发响应式更新
      this.sourceGroups = this.cloneSourceGroups();
      logger.info(TAG, `本地漫画搜索完成: ${items.length}条结果`);
    } catch (error) {
      logger.error(TAG, `本地漫画搜索失败: ${error}`);
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = true;
      this.sourceGroups = this.cloneSourceGroups();
    }
  }

  /**
   * 搜索本地电子书
   */
  private async searchLocalEBooks(): Promise<void> {
    const groupIndex = this.sourceGroups.findIndex(g => g.sourceId === 'local-ebook');
    if (groupIndex < 0) return;

    try {
      // 获取所有电子书并筛选
      const allEBooks: EBook[] = await this.ebookDataManager.searchEBooks(this.searchKeyword);
      
      const items: SearchResultItem[] = allEBooks.map((ebook: EBook): SearchResultItem => {
        const item: SearchResultItem = {
          ebook: ebook,
          source: '本地 - 电子书',
          sourceId: 'local-ebook',
          isLocal: true,
          itemType: 'ebook'
        };
        return item;
      });

      this.sourceGroups[groupIndex].items = items;
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = false;

      // 触发响应式更新
      this.sourceGroups = this.cloneSourceGroups();
      logger.info(TAG, `本地电子书搜索完成: ${items.length}条结果`);
    } catch (error) {
      logger.error(TAG, `本地电子书搜索失败: ${error}`);
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = true;
      this.sourceGroups = this.cloneSourceGroups();
    }
  }

  /**
   * 克隆分组数组以触发响应式更新
   */
  private cloneSourceGroups(): SourceGroup[] {
    const result: SourceGroup[] = [];
    for (const group of this.sourceGroups) {
      // 深拷贝每个分组对象
      const clonedGroup: SourceGroup = {
        sourceId: group.sourceId,
        sourceName: group.sourceName,
        items: [...group.items], // 浅拷贝 items 数组
        isSearching: group.isSearching,
        hasError: group.hasError,
        itemType: group.itemType
      };
      result.push(clonedGroup);
    }
    return result;
  }

  /**
   * 将ComicInfo转换为Manga
   */
  private convertComicsToManga(comics: ComicInfo[]): Manga[] {
    return comics.map((comic: ComicInfo): Manga => {
      // 优先使用本地封面路径，其次使用网络URL
      const coverPath: string = comic.coverLocalPath || comic.coverUrl || '';
      const coverSourceType: ImageSourceType = comic.coverLocalPath ? ImageSourceType.LOCAL : ImageSourceType.NETWORK;
      
      const manga: Manga = {
        id: comic.id,
        title: comic.title,
        alternativeTitles: [],
        description: comic.description,
        coverImagePath: coverPath,
        coverSourceType: coverSourceType,
        status: comic.status,
        metadata: {
          authors: [comic.author],
          artists: [],
          genres: comic.tags,
          themes: [],
          demographics: [],
          contentRating: undefined,
          publicationYear: undefined,
          publisher: undefined,
          serialization: undefined
        },
        chapters: [],
        readingProgress: {
          currentChapterId: '',
          currentPageIndex: 0,
          readingStatus: ReadingStatus.UNREAD,
          totalReadingTime: 0,
          lastReadAt: 0,
          readingPercentage: 0
        },
        bookmarks: [],
        readingSettings: DEFAULT_READING_SETTINGS,
        isFavorite: false,
        lastUpdatedAt: comic.lastUpdateTime,
        sourceInfo: {
          sourceName: comic.sourceId,
          sourceUrl: '',
          sourceId: comic.sourceId,
          sourceLanguage: 'zh',
          requiresLogin: false,
          apiVersion: '1.0'
        }
      };
      return manga;
    });
  }

  /**
   * 打开详情页
   */
  private openDetail(item: SearchResultItem): void {
    try {
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      const stack = globalStack || this.pathStack;
      
      if (item.itemType === 'manga' && item.manga) {
        const navParam: MangaDetailNavParam = { mangaId: item.manga.id };
        stack.pushPath({ name: 'MangaDetailPage', param: navParam });
        logger.debug(TAG, `导航到漫画详情页: ${item.manga.id}`);
      } else if (item.itemType === 'ebook' && item.ebook) {
        const navParam: EBookDetailNavParam = { bookId: item.ebook.id };
        stack.pushPath({ name: 'EBookDetailPage', param: navParam });
        logger.debug(TAG, `导航到电子书详情页: ${item.ebook.id}`);
      }
    } catch (error) {
      logger.error(TAG, `打开详情页失败: ${error}`);
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
              .onClick(() => {
                this.performSearch();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding(this.responsive_contentPadding)

          // 筛选按钮
          Row({ space: 8 }) {
            Button(this.filterType === FilterType.PURCHASED ? '✓ 已浏览' : '已浏览')
              .borderRadius(8)
              .fontSize(14)
              .type(ButtonType.Normal)
              .backgroundColor(this.filterType === FilterType.PURCHASED ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
                ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(this.filterType === FilterType.PURCHASED ? Color.White : 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.filterType = FilterType.PURCHASED;
              })

            Button(this.filterType === FilterType.ALL ? '✓ 全部' : '全部')
              .borderRadius(8)
              .fontSize(14)
              .type(ButtonType.Normal)
              .backgroundColor(this.filterType === FilterType.ALL ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
                ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(this.filterType === FilterType.ALL ? Color.White : 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.filterType = FilterType.ALL;
              })

            Button(this.filterType === FilterType.HAS_RESULT ? '✓ 有结果' : '有结果')
              .borderRadius(8)
              .fontSize(14)
              .type(ButtonType.Normal)
              .backgroundColor(this.filterType === FilterType.HAS_RESULT ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
                ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
              .fontColor(this.filterType === FilterType.HAS_RESULT ? Color.White : 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(() => {
                this.filterType = FilterType.HAS_RESULT;
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_isLandscape ? this.responsive_maxContentWidth : '100%' })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 12 })

          // 搜索结果或历史记录
          if (this.searchKeyword && this.getFilteredGroups().length > 0) {
            // 按图源分组显示搜索结果
            if (this.responsive_isLandscape) {
              // 横屏模式：使用网格布局
              this.buildLandscapeResults()
            } else {
              // 竖屏模式：使用列表布局
              Scroll() {
                Column({ space: 16 }) {
                  ForEach(this.getFilteredGroups(), (group: SourceGroup) => {
                    this.buildSourceGroupCard(group)
                  }, (group: SourceGroup) => `${group.sourceId}-${group.items.length}`)
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
            Column() {
              Text('😔')
                .fontSize(48)
                .margin({ bottom: 12 })
              Text('未找到相关内容')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text('换个关键词试试吧')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ top: 4 })
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
                  .padding(this.responsive_contentPadding)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.searchHistory, (keyword: string) => {
                    Row({ space: 8 }) {
                      Text('🕐')
                        .fontSize(14)
                      Text(keyword)
                        .fontSize(14)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .borderRadius(16)
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
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
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
        ForEach(this.getFilteredGroups(), (group: SourceGroup) => {
          Column({ space: 12 }) {
            // 分组标题
            Row() {
              Text(group.sourceName)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              
              Text(`(${group.items.length}${group.itemType === 'manga' ? '本漫画' : '本电子书'})`)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })

            // 网格布局显示结果
            if (group.items.length > 0) {
              Grid() {
                ForEach(group.items, (item: SearchResultItem) => {
                  GridItem() {
                    this.buildItemCard(item)
                  }
                }, (item: SearchResultItem) => this.getItemId(item))
              }
              .columnsTemplate(`repeat(${this.responsive_gridColumns}, 1fr)`)
              .columnsGap(12)
              .rowsGap(16)
              .width('100%')
              .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
            }
          }
          .width('100%')
        }, (group: SourceGroup) => group.sourceId.toString())
        
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
   * 构建图源分组卡片
   */
  @Builder
  buildSourceGroupCard(group: SourceGroup) {
    Column({ space: 12 }) {
      // 图源标题行
      Row() {
        Column({ space: 4 }) {
          Text(group.sourceName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          if (group.isSearching) {
            Text('搜索中...')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          } else if (group.hasError) {
            Text('搜索失败')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          } else {
            Text(`${group.items.length}${group.itemType === 'manga' ? '本漫画' : '本电子书'}`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      // 横向滚动的列表
      if (group.isSearching) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(24)
            .height(24)
          Text('搜索中...')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(180)
        .justifyContent(FlexAlign.Center)
      } else if (group.items.length > 0) {
        Scroll() {
          Row({ space: 12 }) {
            ForEach(group.items.slice(0, 10), (item: SearchResultItem) => {
              this.buildItemCard(item)
            }, (item: SearchResultItem) => this.getItemId(item))
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      } else if (group.hasError) {
        Text('搜索失败，请重试')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .height(180)
          .textAlign(TextAlign.Center)
      } else {
        Text('暂无结果')
          .fontSize(14)
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
   * 获取项目ID
   */
  private getItemId(item: SearchResultItem): string {
    if (item.itemType === 'manga' && item.manga) {
      return item.manga.id;
    } else if (item.itemType === 'ebook' && item.ebook) {
      return item.ebook.id;
    }
    return '';
  }

  /**
   * 规范化封面路径：本地文件添加 file:// 前缀
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) {
      return '';
    }
    // 如果是应用资源路径 (app.media.xxx)，返回空字符串让调用方使用默认资源
    if (path.startsWith('app.media.') || path.startsWith('$r(')) {
      return '';
    }
    // 如果是本地路径（以 / 开头），添加 file:// 前缀
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
  }

  /**
   * 获取漫画封面资源
   */
  private getMangaCoverSource(manga: Manga): ResourceStr {
    const raw = manga?.coverImagePath || '';
    if (raw.length === 0) {
      return $r('app.media.mangabook');
    }
    
    // 检查是否为应用资源路径 (app.media.xxx)
    if (raw.startsWith('app.media.')) {
      const resourceName = raw.substring('app.media.'.length);
      if (resourceName === 'mangabook') {
        return $r('app.media.mangabook');
      } else if (resourceName === 'icon') {
        return $r('app.media.icon');
      }
      return $r('app.media.mangabook');
    }
    
    // 本地文件路径
    if (raw.startsWith('/')) {
      return `file://${raw}`;
    }
    
    return raw;
  }

  /**
   * 获取电子书封面资源
   */
  private getEBookCoverSource(ebook: EBook): ResourceStr {
    const raw = ebook?.metadata?.coverImagePath || '';
    if (raw.length === 0) {
      return $r('app.media.ic_ebook');
    }
    
    // 检查是否为应用资源路径 (app.media.xxx)
    if (raw.startsWith('app.media.')) {
      const resourceName = raw.substring('app.media.'.length);
      if (resourceName === 'mangabook') {
        return $r('app.media.mangabook');
      } else if (resourceName === 'ic_ebook') {
        return $r('app.media.ic_ebook');
      } else if (resourceName === 'icon') {
        return $r('app.media.icon');
      }
      return $r('app.media.ic_ebook');
    }
    
    // 本地文件路径
    if (raw.startsWith('/')) {
      return `file://${raw}`;
    }
    
    return raw;
  }

  /**
   * 构建项目卡片（漫画或电子书）
   */
  @Builder
  buildItemCard(item: SearchResultItem) {
    Column({ space: 8 }) {
      // 封面
      if (item.itemType === 'manga' && item.manga) {
        Image(this.getMangaCoverSource(item.manga))
          .width(100)
          .height(140)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .alt($r('app.media.mangabook'))
      } else if (item.itemType === 'ebook' && item.ebook) {
        Image(this.getEBookCoverSource(item.ebook))
          .width(100)
          .height(140)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
          .alt($r('app.media.ic_ebook'))
      }

      // 标题
      Text(item.itemType === 'manga' && item.manga ? item.manga.title : 
           (item.itemType === 'ebook' && item.ebook ? item.ebook.metadata.title : ''))
        .fontSize(13)
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
}
