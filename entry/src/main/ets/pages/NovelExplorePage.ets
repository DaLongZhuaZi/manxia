/**
 * 小说发现页
 * 展示书源的发现分类和书籍列表
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelExplorePage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { getNovelSourceManager, NovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { NovelSearchResult, NovelSourceInfo } from '../Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { NovelDetailPageParams } from './NovelBookshelfPage';
import { LegadoWebViewComponent } from '../Framework/Novel/LegadoWebViewComponent';

const TAG = 'NovelExplorePage';

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

const TITLE_BAR_HEIGHT_MINI = 56;

@Component
export struct NovelExplorePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelExplorePage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State exploreSources: NovelSourceInfo[] = [];
  @State filteredSources: NovelSourceInfo[] = [];
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
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private sourceListScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  loadExploreSources(): void {
    this.exploreSources = this.sourceManager.getExploreSources();
    this.filteredSources = this.exploreSources;
    if (this.exploreSources.length > 0 && !this.selectedSourceId) {
      this.selectedSourceId = this.exploreSources[0].id;
      this.selectedSourceName = this.exploreSources[0].name;
      this.loadExploreKinds();
    } else if (this.selectedSourceId) {
      // 如果已有选中的书源ID，找到对应的名称
      const source = this.exploreSources.find(s => s.id === this.selectedSourceId);
      if (source) {
        this.selectedSourceName = source.name;
        this.loadExploreKinds();
      } else {
        this.isLoading = false;
      }
    } else {
      this.isLoading = false;
    }
  }

  filterSources(): void {
    if (!this.searchKeyword.trim()) {
      this.filteredSources = this.exploreSources;
    } else {
      const keyword = this.searchKeyword.toLowerCase();
      this.filteredSources = this.exploreSources.filter(source => 
        source.name.toLowerCase().includes(keyword)
      );
    }
  }

  loadExploreKinds(): void {
    if (!this.selectedSourceId) {
      this.isLoading = false;
      return;
    }
    
    const kinds = this.sourceManager.getExploreKinds(this.selectedSourceId);
    this.exploreKinds = kinds;
    this.selectedKindIndex = 0;
    
    if (kinds.length > 0) {
      this.loadBooks();
    } else {
      this.isLoading = false;
    }
  }

  async loadBooks(): Promise<void> {
    if (!this.selectedSourceId || this.exploreKinds.length === 0) {
      this.isLoading = false;
      return;
    }

    this.isLoading = true;
    const kind = this.exploreKinds[this.selectedKindIndex];
    
    try {
      const results = await this.sourceManager.explore(
        this.selectedSourceId, 
        kind.url, 
        this.currentPage
      );
      
      if (this.currentPage === 1) {
        this.books = results;
      } else {
        this.books = [...this.books, ...results];
      }
      
      this.hasMore = results.length >= 20;
    } catch (error) {
      logger.error(TAG, `加载发现页失败: ${String(error)}`);
    }
    
    this.isLoading = false;
  }

  loadMore(): void {
    if (!this.isLoading && this.hasMore) {
      this.currentPage++;
      this.loadBooks();
    }
  }

  selectSource(source: NovelSourceInfo): void {
    if (this.selectedSourceId !== source.id) {
      this.selectedSourceId = source.id;
      this.selectedSourceName = source.name;
      this.currentPage = 1;
      this.books = [];
      this.showSourcePicker = false;
      this.loadExploreKinds();
    } else {
      this.showSourcePicker = false;
    }
  }

  selectKind(index: number): void {
    if (this.selectedKindIndex !== index) {
      this.selectedKindIndex = index;
      this.currentPage = 1;
      this.books = [];
      this.loadBooks();
    }
  }

  openBookDetail(book: NovelSearchResult): void {
    const params: NovelDetailPageParams = {
      sourceId: book.sourceId,
      bookUrl: book.bookUrl,
      bookName: book.name,
      // 传递完整fallback信息
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

  build() {
    HdsNavDestination() {
      Stack() {
        // 隐藏的WebView组件，用于Legado书源JS执行
        LegadoWebViewComponent()
        
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层
        Column() {
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
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
        
        // 书源选择弹窗
        if (this.showSourcePicker) {
          this.buildSourcePickerOverlay()
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
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: '发现'
        },
      }
    })
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
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
      Text('暂无支持发现功能的书源')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      
      Text('请导入包含发现规则的书源')
        .fontSize(12)
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
      Image($r('app.media.ic_search'))
        .width(20)
        .height(20)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .margin({ left: 12 })
      
      TextInput({ placeholder: '搜索书源...', text: this.searchKeyword })
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
        Image($r('app.media.ic_close'))
          .width(18)
          .height(18)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
          .margin({ right: 12 })
          .onClick(() => {
            this.searchKeyword = '';
            this.filterSources();
          })
      }
    }
    .width('100%')
    .height(44)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  @Builder
  buildSourceDropdown() {
    Row() {
      Text(this.selectedSourceName || '选择书源')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)
      
      Image($r('app.media.ic_arrow_down'))
        .width(16)
        .height(16)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
        .rotate({ angle: this.showSourcePicker ? 180 : 0 })
        .animation({ duration: 200 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
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
          Text('选择书源')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`共 ${this.filteredSources.length} 个`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .borderWidth({ bottom: 0.5 })
        .borderColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
        
        // 搜索框
        Row() {
          Image($r('app.media.ic_search'))
            .width(18)
            .height(18)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
            .margin({ left: 12 })
          
          TextInput({ placeholder: '搜索书源...', text: this.searchKeyword })
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
            Image($r('app.media.ic_close'))
              .width(16)
              .height(16)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme))
              .margin({ right: 12 })
              .onClick(() => {
                this.searchKeyword = '';
                this.filterSources();
              })
          }
        }
        .width('100%')
        .height(44)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .margin({ left: 12, right: 12, top: 8, bottom: 8 })
        
        // 书源列表
        List({ scroller: this.sourceListScroller }) {
          ForEach(this.filteredSources, (source: NovelSourceInfo, index: number) => {
            ListItem() {
              Row() {
                Text(source.name)
                  .fontSize(14)
                  .fontColor(this.selectedSourceId === source.id ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .fontWeight(this.selectedSourceId === source.id ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                
                if (this.selectedSourceId === source.id) {
                  Image($r('app.media.ic_check'))
                    .width(20)
                    .height(20)
                    .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                }
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .onClick(() => this.selectSource(source))
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
        .onAppear(() => {
          // 滚动到当前选中的书源
          const selectedIndex = this.filteredSources.findIndex(s => s.id === this.selectedSourceId);
          if (selectedIndex > 0) {
            // 延迟滚动，确保List已渲染
            setTimeout(() => {
              this.sourceListScroller.scrollToIndex(selectedIndex, true, ScrollAlign.CENTER);
            }, 100);
          }
        })
      }
      .width('100%')
      .height('60%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
  }

  @Builder
  buildKindSelector() {
    Scroll() {
      Row() {
        ForEach(this.exploreKinds, (kind: ExploreKind, index: number) => {
          Column() {
            Text(kind.title)
              .fontSize(14)
              .fontColor(this.selectedKindIndex === index ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
                ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .fontWeight(this.selectedKindIndex === index ? FontWeight.Medium : FontWeight.Normal)
            
            if (this.selectedKindIndex === index) {
              Divider()
                .width(24)
                .height(2)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .margin({ top: 4 })
            }
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => this.selectKind(index))
        })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
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
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .margin({ left: 8 })
              } else {
                Text('上拉加载更多')
                  .fontSize(12)
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
      .layoutWeight(1)
      .padding({ top: 8 })
      .onReachEnd(() => this.loadMore())
    }
  }

  @Builder
  buildBookItem(book: NovelSearchResult) {
    Row() {
      // 封面
      if (book.coverUrl) {
        Image(book.coverUrl)
          .width(70)
          .height(95)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Text(book.name.substring(0, 1))
            .fontSize(20)
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
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(book.author || '未知作者')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 4 })
        
        if (book.intro) {
          Text(book.intro)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        
        if (book.latestChapterTitle) {
          Text(book.latestChapterTitle)
            .fontSize(10)
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
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ left: 12, right: 12, bottom: 8 })
    .onClick(() => this.openBookDetail(book))
  }
}
