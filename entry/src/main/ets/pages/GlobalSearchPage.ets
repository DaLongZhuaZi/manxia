/**
 * 全局搜索页面
 * 支持搜索本地书库和在线图源
 */
import { DataService } from '../Framework/Services/DataService';
import { DataManager, ComicInfo } from '../Framework/Data/DataManager';
import { SourceManager, SourceInfo } from '../Framework/Source/SourceManager';
import { MangaSourceEngine, EngineConfig, SearchResult } from '../Framework/WebView/MangaSourceEngine';
import { Manga, ImageSourceType, MangaStatus, ReadingMode, ReadingDirection, DEFAULT_READING_SETTINGS, PageTurnAnimationType } from '../Models/MangaModels';
import { ReadingStatus } from '../Framework/Types/StatusEnums';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger } from '../Utils/Logger';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';

const TAG = 'GlobalSearchPage';

// 筛选类型枚举
enum FilterType {
  PURCHASED = 'purchased',  // 已浏览
  ALL = 'all',             // 全部
  HAS_RESULT = 'hasResult' // 有结果
}

// 搜索结果项
interface SearchResultItem {
  manga: Manga;
  source: string;         // 来源：'local' 或图源名称
  sourceId?: number | string;      // 图源ID（在线漫画）
  isLocal: boolean;       // 是否本地漫画
  externalId?: string;    // 外部ID（用于在线漫画）
}

// 图源分组
interface SourceGroup {
  sourceId: number | string; // 图源ID，本地为'local'
  sourceName: string;
  sourceLanguage: string;    // 语言标识
  items: SearchResultItem[];
  isSearching: boolean;      // 是否正在搜索
  hasError: boolean;         // 是否搜索出错
}

// 导航参数接口
interface SourceDetailNavParam {
  sourceId: number;
  searchKeyword: string;
}

interface MangaDetailNavParam {
  mangaId: string;
  sourceId?: number | string;
  useWebView?: boolean;
  mangaTitle?: string;
  coverUrl?: string;
}


@Component
export struct GlobalSearchPage {
  @StorageLink('currentTheme') themeState: ThemeAwareState = new ThemeAwareState();
  
  // 搜索相关
  @State searchKeyword: string = '';
  @State filterType: FilterType = FilterType.ALL;
  @State isSearching: boolean = false;
  
  // 结果相关 - 按图源分组
  @State sourceGroups: SourceGroup[] = [];
  
  // 图源列表
  @State availableSources: SourceInfo[] = [];
  
  // 历史记录
  @State searchHistory: string[] = [];
  
  // WebView相关
  private webViewController: webview.WebviewController = new webview.WebviewController();
  private searchEngines: Map<number, MangaSourceEngine> = new Map();
  
  private dataService: DataService = DataService.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private sourceManager: SourceManager = SourceManager.getInstance();
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.loadAvailableSources();
    this.loadSearchHistory();
  }

  /**
   * 主题变化回调
   */
  onThemeChange(): void {
    // 主题变化时的处理逻辑（如果需要）
  }

  /**
   * 获取筛选后的图源分组
   */
  private getFilteredGroups(): SourceGroup[] {
    const filtered = (() => {
      switch (this.filterType) {
        case FilterType.PURCHASED:
        case FilterType.HAS_RESULT:
          // 只显示有结果的图源
          return this.sourceGroups.filter(g => g.items.length > 0);
        case FilterType.ALL:
        default:
          // 显示全部图源
          return this.sourceGroups;
      }
    })();
    
    logger.debug(TAG, `getFilteredGroups调用: filterType=${this.filterType}, 总数=${this.sourceGroups.length}, 筛选后=${filtered.length}`);
    filtered.forEach((g, idx) => {
      logger.debug(TAG, `  [${idx}] ${g.sourceName}: isSearching=${g.isSearching}, items=${g.items.length}, hasError=${g.hasError}`);
    });
    
    return filtered;
  }

  /**
   * 加载可用图源列表
   */
  private async loadAvailableSources(): Promise<void> {
    try {
      this.availableSources = await this.sourceManager.getAllSources();
      logger.info(TAG, `加载了 ${this.availableSources.length} 个图源`);
    } catch (error) {
      logger.error(TAG, `加载图源失败: ${error}`);
    }
  }

  /**
   * 加载搜索历史
   */
  private loadSearchHistory(): void {
    try {
      const history = AppStorage.get<string[]>('searchHistory') || [];
      this.searchHistory = history.slice(0, 10); // 最多10条
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
   * 执行搜索 - 按图源分组并发搜索
   */
  private async performSearch(): Promise<void> {
    if (!this.searchKeyword || this.searchKeyword.trim() === '') {
      return;
    }

    try {
      logger.info(TAG, `========== 开始全局搜索: "${this.searchKeyword}" ==========`);
      
      // 保存搜索历史
      this.saveSearchHistory(this.searchKeyword);

      // 初始化图源分组：本地书库 + 所有在线图源
      const groups: SourceGroup[] = [];
      logger.debug(TAG, `准备创建图源分组，在线图源数量: ${this.availableSources.length}`);
      
      // 添加本地书库分组
      groups.push({
        sourceId: 'local',
        sourceName: '本地书库',
        sourceLanguage: '中文',
        items: [],
        isSearching: true,
        hasError: false
      });

      // 添加所有在线图源分组
      for (const source of this.availableSources) {
        groups.push({
          sourceId: source.id,
          sourceName: source.name,
          sourceLanguage: '中文', // 可以从source配置中获取
          items: [],
          isSearching: true,
          hasError: false
        });
      }

      logger.debug(TAG, `创建了 ${groups.length} 个图源分组`);
      this.sourceGroups = groups;
      logger.debug(TAG, `sourceGroups已设置，长度: ${this.sourceGroups.length}`);
      this.sourceGroups.forEach((g, idx) => {
        logger.debug(TAG, `  初始分组[${idx}]: ${g.sourceName}, isSearching=${g.isSearching}`);
      });

      // 并发搜索所有图源
      const searchPromises: Promise<void>[] = [];
      logger.debug(TAG, `开始并发搜索...`);

      // 搜索本地书库
      searchPromises.push(this.searchLocalInGroup());

      // 搜索所有在线图源
      for (const source of this.availableSources) {
        searchPromises.push(this.searchSourceInGroup(source));
      }

      // 等待所有搜索完成
      await Promise.allSettled(searchPromises);

      // 搜索完成，打印最终状态
      logger.info(TAG, `========== 全局搜索完成 ==========`);
      logger.debug(TAG, `最终sourceGroups状态:`);
      this.sourceGroups.forEach((g, idx) => {
        logger.debug(TAG, `  [${idx}] ${g.sourceName}: isSearching=${g.isSearching}, items=${g.items.length}, hasError=${g.hasError}`);
      });
      
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
    }
  }

  /**
   * 在本地书库分组中搜索
   */
  private async searchLocalInGroup(): Promise<void> {
    const groupIndex = this.sourceGroups.findIndex(g => g.sourceId === 'local');
    if (groupIndex < 0) return;

    try {
      logger.debug(TAG, `开始搜索本地书库`);
      
      // 使用searchComics方法搜索所有漫画
      const searchResult = await this.dataService.searchComics('');
      const allManga: Manga[] = this.convertComicsToManga(searchResult.comics);
      const keyword: string = this.searchKeyword.toLowerCase();
      
      const filtered: Manga[] = allManga.filter((manga: Manga): boolean => 
        manga.title.toLowerCase().includes(keyword) ||
        manga.metadata.authors.some((author: string): boolean => author.toLowerCase().includes(keyword)) ||
        manga.metadata.genres.some((genre: string): boolean => genre.toLowerCase().includes(keyword))
      );

      const items: SearchResultItem[] = filtered.map((manga: Manga): SearchResultItem => ({
        manga: manga,
        source: '本地书库',
        sourceId: 'local',
        isLocal: true
      }));

      // 更新分组结果
      logger.debug(TAG, `[本地搜索] 更新前: isSearching=${this.sourceGroups[groupIndex].isSearching}`);
      this.sourceGroups[groupIndex].items = items;
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = false;
      logger.debug(TAG, `[本地搜索] 更新后: isSearching=${this.sourceGroups[groupIndex].isSearching}, items=${items.length}`);

      // 触发响应式更新
      this.sourceGroups = [...this.sourceGroups];
      logger.debug(TAG, `[本地搜索] 触发响应式更新，新数组长度: ${this.sourceGroups.length}`);

      logger.info(TAG, `本地搜索完成: ${items.length}条结果`);
    } catch (error) {
      logger.error(TAG, `本地搜索失败: ${error}`);
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = true;
      
      // 触发响应式更新
      this.sourceGroups = [...this.sourceGroups];
    }
  }

  /**
   * 在指定图源分组中搜索
   * 使用WebView引擎进行搜索
   */
  private async searchSourceInGroup(source: SourceInfo): Promise<void> {
    const groupIndex = this.sourceGroups.findIndex(g => g.sourceId === source.id);
    if (groupIndex < 0) return;

    try {
      logger.debug(TAG, `开始在图源"${source.name}"中搜索`);
      
      // 获取或创建搜索引擎
      let engine = this.searchEngines.get(source.id);
      if (!engine) {
        // 创建新的搜索引擎
        const config: ESObject | null = await this.dataManager.getSourceConfig(source.id);
        if (!config) {
          logger.warn(TAG, `未找到图源配置: ${source.id}`);
          this.sourceGroups[groupIndex].isSearching = false;
          this.sourceGroups[groupIndex].hasError = true;
          return;
        }

        // 配置引擎
        const engineConfig: EngineConfig = {
          webViewController: this.webViewController,
          antiCrawlerConfig: config.antiCrawler || {},
          debug: false,
          timeout: 30000,
          caseSensitive: false,
          sourceId: source.id
        };

        engine = new MangaSourceEngine(engineConfig);
        
        // 加载配置
        const configJson = JSON.stringify(config);
        await engine.loadConfig(configJson);
        
        // 缓存引擎
        this.searchEngines.set(source.id, engine);
      }

      // 执行搜索
      const result: ESObject = await engine.searchManga(this.searchKeyword, 1);

      if (!result.success || !result.data) {
        this.sourceGroups[groupIndex].items = [];
        this.sourceGroups[groupIndex].isSearching = false;
        this.sourceGroups[groupIndex].hasError = false;
        logger.info(TAG, `图源"${source.name}"搜索完成: 0条结果`);
        return;
      }

      // 从SearchResult中获取mangas数组
      const searchResult: SearchResult = result.data as SearchResult;
      const dataArray: ESObject[] = Array.isArray(searchResult.mangas) ? searchResult.mangas as ESObject[] : [];
      logger.debug(TAG, `图源"${source.name}"返回数据: ${dataArray.length}条`);

      // 转换为SearchResultItem
      const items: SearchResultItem[] = dataArray.map((mangaInfo: ESObject): SearchResultItem => {
        const mangaObj: Manga = this.createMangaFromSearchResult(mangaInfo, source);
        return {
          manga: mangaObj,
          source: source.name,
          sourceId: source.id,
          isLocal: false,
          externalId: mangaInfo.id as string
        };
      });

      // 更新分组结果
      logger.debug(TAG, `[${source.name}] 更新前: isSearching=${this.sourceGroups[groupIndex].isSearching}`);
      this.sourceGroups[groupIndex].items = items;
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = false;
      logger.debug(TAG, `[${source.name}] 更新后: isSearching=${this.sourceGroups[groupIndex].isSearching}, items=${items.length}`);

      // 触发响应式更新
      this.sourceGroups = [...this.sourceGroups];
      logger.debug(TAG, `[${source.name}] 触发响应式更新，新数组长度: ${this.sourceGroups.length}`);

      logger.info(TAG, `图源"${source.name}"搜索完成: ${items.length}条结果`);
    } catch (error) {
      logger.error(TAG, `在图源"${source.name}"中搜索失败: ${error}`);
      this.sourceGroups[groupIndex].isSearching = false;
      this.sourceGroups[groupIndex].hasError = true;
      
      // 触发响应式更新
      this.sourceGroups = [...this.sourceGroups];
    }
  }

  /**
   * 从搜索结果创建Manga对象
   */
  private createMangaFromSearchResult(mangaInfo: ESObject, source: SourceInfo): Manga {
    return {
      id: mangaInfo.id as string,
      title: mangaInfo.title as string,
      alternativeTitles: [],
      description: (mangaInfo.description as string) || '',
      coverImagePath: mangaInfo.cover as string,
      coverSourceType: ImageSourceType.NETWORK,
      status: MangaStatus.ONGOING,
      metadata: {
        authors: mangaInfo.author ? [mangaInfo.author] : [],
        artists: [],
        genres: mangaInfo.genres || [],
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
      lastUpdatedAt: Date.now(),
      sourceInfo: {
        sourceName: source.name,
        sourceUrl: mangaInfo.url || '',
        sourceId: source.id.toString(),
        sourceLanguage: 'zh',
        requiresLogin: false,
        apiVersion: '1.0'
      }
    };
  }

  /**
   * 将ComicInfo转换为Manga
   */
  private convertComicsToManga(comics: ComicInfo[]): Manga[] {
    return comics.map((comic: ComicInfo): Manga => {
      const manga: Manga = {
        id: comic.id,
        title: comic.title,
        alternativeTitles: [],
        description: comic.description,
        coverImagePath: comic.coverUrl,
        coverSourceType: ImageSourceType.NETWORK,
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
   * 导航到图源详情页
   */
  private navigateToSource(sourceId: number): void {
    try {
      const navParam: SourceDetailNavParam = {
        sourceId: sourceId,
        searchKeyword: this.searchKeyword
      };
      
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        logger.debug(TAG, `导航到 SourceDetailPage（全局栈），sourceId=${sourceId}`);
        globalStack.pushPath({ name: 'SourceDetailPage', param: navParam as Object });
      } else {
        logger.debug(TAG, `导航到 SourceDetailPage（本地栈），sourceId=${sourceId}`);
        this.pathStack.pushPath({ name: 'SourceDetailPage', param: navParam as Object });
      }
    } catch (error) {
      logger.error(TAG, `导航到图源详情页失败: ${error}`);
    }
  }

  /**
   * 打开漫画详情页
   */
  private openMangaDetail(item: SearchResultItem): void {
    try {
      let navParam: MangaDetailNavParam;
      
      if (item.isLocal) {
        // 本地漫画
        navParam = { mangaId: item.manga.id };
      } else {
        // 在线漫画 - 使用externalId作为mangaId
        navParam = {
          mangaId: item.externalId || item.manga.id,
          sourceId: item.sourceId,
          useWebView: true,
          mangaTitle: item.manga.title,
          coverUrl: item.manga.coverImagePath
        };
      }
      
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        logger.debug(TAG, `导航到 MangaDetailPage（全局栈），mangaId=${item.manga.id}`);
        globalStack.pushPath({ name: 'MangaDetailPage', param: navParam });
      } else {
        logger.debug(TAG, `导航到 MangaDetailPage（本地栈），mangaId=${item.manga.id}`);
        this.pathStack.pushPath({ name: 'MangaDetailPage', param: navParam });
      }
    } catch (error) {
      logger.error(TAG, `打开漫画详情失败: ${error}`);
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 隐藏的WebView（用于搜索）
        Web({ src: 'about:blank', controller: this.webViewController })
          .width(1)
          .height(1)
          .visibility(Visibility.Hidden)
          .zIndex(-1)

        Column() {
        // 搜索栏
        Row({ space: 12 }) {
          TextInput({ placeholder: '搜索漫画、作者、标签...', text: this.searchKeyword })
            .layoutWeight(1)
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
        .padding(16)

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
        .padding({ left: 16, right: 16, bottom: 12 })

        // 搜索结果或历史记录
        if (this.getFilteredGroups().length > 0) {
          // 按图源分组显示搜索结果
          List({ space: 16 }) {
            ForEach(this.getFilteredGroups(), (group: SourceGroup) => {
              ListItem() {
                this.buildSourceGroupCard(group)
              }
            }, (group: SourceGroup) => group.sourceId.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8 })
        } else if (this.searchKeyword && this.sourceGroups.length > 0) {
          // 搜索完成但无结果
          Column() {
            Text('未找到相关漫画')
              .fontSize(16)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
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
                .padding(16)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              ForEach(this.searchHistory, (keyword: string) => {
                Text(keyword)
                  .fontSize(14)
                  .padding(12)
                  .width('100%')
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .onClick(() => {
                    this.searchKeyword = keyword;
                    this.performSearch();
                  })
              })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      }
      .width('100%')
      .height('100%')
    }
    .title('全局搜索')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
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
          Row({ space: 8 }) {
            Text(group.sourceName)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            Text(group.sourceLanguage)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          
          if (group.isSearching) {
            Text('搜索中...')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          } else if (group.hasError) {
            Text('搜索失败')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          } else {
            Text(`${group.items.length}漫画`)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 查看更多按钮
        if (group.items.length > 0) {
          Row({ space: 4 }) {
            Text('查看更多')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('→')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .onClick(() => {
            logger.info(TAG, `查看更多: ${group.sourceName}`);
          })
        }
      }
      .width('100%')

      // 横向滚动的漫画列表
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
              this.buildMangaCard(item)
            }, (item: SearchResultItem) => item.manga.id)
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
  }

  /**
   * 构建漫画卡片（横向滚动）
   */
  @Builder
  buildMangaCard(item: SearchResultItem) {
    Column({ space: 8 }) {
      // 封面
      Image(item.manga.coverImagePath)
        .width(100)
        .height(140)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.mangabook'))

      // 标题
      Text(item.manga.title)
        .fontSize(13)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(100)
        .textAlign(TextAlign.Start)
    }
    .width(100)
    .onClick(() => {
      this.openMangaDetail(item);
    })
  }
}
