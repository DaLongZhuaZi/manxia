/**
 * Suwayomi 图源浏览页面
 * 专门用于浏览单个图源的漫画内容
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, display } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { SuwayomiSourceExecutor, getSuwayomiSourceExecutor, SuwayomiExtensionSource } from '../Framework/Source/SuwayomiSourceExecutor';
import { ComicInfo } from '../Framework/Source/SourceExecutor';
import { SuwayomiImage } from '../components/SuwayomiImage';

const TAG = 'SuwayomiSourceBrowsePage';
const TITLE_BAR_HEIGHT: number = 56;

// 页面参数接口
export interface SuwayomiSourceBrowseParams {
  source: SuwayomiExtensionSource;
  keyword?: string; // 可选的搜索关键词，传入后自动搜索
}

// 漫画详情页参数
interface SuwayomiMangaDetailParams {
  mangaId: string;
  title: string;
}

type BrowseType = 'POPULAR' | 'LATEST';

@Component
export struct SuwayomiSourceBrowsePage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 数据状态
  @State source: SuwayomiExtensionSource | null = null;
  @State mangas: ComicInfo[] = [];
  @State browseType: BrowseType = 'POPULAR';
  @State currentPage: number = 1;
  @State hasMore: boolean = true;

  // 搜索状态
  @State searchQuery: string = '';
  @State isSearchMode: boolean = false;

  // UI 状态
  @State isLoading: boolean = false;
  @State isLoadingMore: boolean = false;
  @State errorMessage: string = '';
  @State gridColumns: number = 3; // 默认3列，根据屏幕宽度动态调整

  private executor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private componentId: string = 'SuwayomiSourceBrowsePage';
  private displayCallback: Callback<number> | null = null;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
    });
    this.updateGridColumns();
    this.registerDisplayChangeListener();
  }

  /**
   * 注册屏幕变化监听（横竖屏切换）
   */
  private registerDisplayChangeListener(): void {
    try {
      this.displayCallback = (_displayId: number) => {
        this.updateGridColumns();
      };
      display.on('change', this.displayCallback);
      logger.info(TAG, '已注册屏幕变化监听');
    } catch (error) {
      logger.error(TAG, `注册屏幕变化监听失败: ${error}`);
    }
  }

  /**
   * 取消屏幕变化监听
   */
  private unregisterDisplayChangeListener(): void {
    try {
      if (this.displayCallback) {
        display.off('change', this.displayCallback);
        this.displayCallback = null;
        logger.info(TAG, '已取消屏幕变化监听');
      }
    } catch (error) {
      logger.error(TAG, `取消屏幕变化监听失败: ${error}`);
    }
  }

  /**
   * 根据屏幕宽度动态计算Grid列数
   * 确保每个卡片宽度在合理范围内（100-150vp）
   */
  private updateGridColumns(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const screenWidth = px2vp(displayInfo.width);
      // 每个卡片理想宽度约120vp，加上间距
      const idealCardWidth = 120;
      const padding = 32; // 左右padding各16
      const gap = 12; // 列间距
      const availableWidth = screenWidth - padding;
      // 计算列数，最少3列，最多8列
      let columns = Math.floor((availableWidth + gap) / (idealCardWidth + gap));
      columns = Math.max(3, Math.min(8, columns));
      this.gridColumns = columns;
      logger.info(TAG, `屏幕宽度: ${screenWidth}vp, Grid列数: ${columns}`);
    } catch (error) {
      logger.error(TAG, `获取屏幕信息失败: ${error}`);
      this.gridColumns = 3;
    }
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    this.unregisterDisplayChangeListener();
  }

  private async initialize(): Promise<void> {
    if (!this.source) {
      this.errorMessage = '未指定图源';
      return;
    }

    this.isLoading = true;
    try {
      await this.executor.initialize();
      this.executor.setCurrentSource(this.source.id);
      await this.loadMangas(true);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      this.errorMessage = `初始化失败: ${error}`;
    }
    this.isLoading = false;
  }

  private async loadMangas(reset: boolean = false): Promise<void> {
    if (reset) {
      this.currentPage = 1;
      this.mangas = [];
      this.hasMore = true;
      this.isLoading = true;
    } else {
      if (this.isLoadingMore || !this.hasMore) return;
      this.isLoadingMore = true;
    }

    this.errorMessage = '';

    try {
      const newMangas = await this.executor.browse(this.browseType, this.currentPage);
      if (reset) {
        this.mangas = newMangas;
      } else {
        this.mangas = this.mangas.concat(newMangas);
      }
      this.hasMore = newMangas.length >= 20;
      logger.info(TAG, `加载漫画: ${this.mangas.length} 本, 页码: ${this.currentPage}`);
    } catch (error) {
      logger.error(TAG, `加载失败: ${error}`);
      this.errorMessage = `加载失败: ${error}`;
    }

    this.isLoading = false;
    this.isLoadingMore = false;
  }

  private async loadMore(): Promise<void> {
    if (this.isSearchMode) return;
    this.currentPage++;
    await this.loadMangas(false);
  }

  private async performSearch(): Promise<void> {
    if (!this.searchQuery.trim()) {
      this.isSearchMode = false;
      await this.loadMangas(true);
      return;
    }

    this.isSearchMode = true;
    this.isLoading = true;
    this.errorMessage = '';

    try {
      this.mangas = await this.executor.search(this.searchQuery);
      this.hasMore = false;
      logger.info(TAG, `搜索结果: ${this.mangas.length} 本`);
    } catch (error) {
      logger.error(TAG, `搜索失败: ${error}`);
      this.errorMessage = `搜索失败: ${error}`;
    }

    this.isLoading = false;
  }

  private openMangaDetail(manga: ComicInfo): void {
    const params: SuwayomiMangaDetailParams = { mangaId: manga.id, title: manga.title };
    this.pathStack.pushPathByName('SuwayomiMangaDetailPage', params);
  }

  private showToast(message: string): void {
    import('@kit.ArkUI').then(arkUI => {
      arkUI.promptAction.showToast({
        message: message,
        duration: 2000
      });
    });
  }

  @Builder
  buildSearchBar() {
    Row({ space: 8 }) {
      TextInput({ placeholder: `在 ${this.source?.name || '图源'} 中搜索...`, text: this.searchQuery })
        .layoutWeight(1)
        .height(40)
        .borderRadius(20)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .onChange((value: string) => {
          this.searchQuery = value;
        })
        .onSubmit(() => {
          this.performSearch();
        })

      if (this.searchQuery) {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.searchQuery = '';
          this.isSearchMode = false;
          this.loadMangas(true);
        })
        .fontFamily(this.appFontFamily)
      }

      Button() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
      .borderRadius(20)
      .onClick(() => {
        this.performSearch();
      })
      .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  buildBrowseTypeSelector() {
    if (!this.isSearchMode) {
      Row({ space: 12 }) {
        // 热门
        Text('热门')
          .fontSize(14)
          .fontWeight(this.browseType === 'POPULAR' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.browseType === 'POPULAR' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.browseType === 'POPULAR' ?
            ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) :
            Color.Transparent)
          .borderRadius(20)
          .onClick(() => {
            if (this.browseType !== 'POPULAR') {
              this.browseType = 'POPULAR';
              this.loadMangas(true);
            }
          })
          .fontFamily(this.appFontFamily)

        // 最新
        Text('最新')
          .fontSize(14)
          .fontWeight(this.browseType === 'LATEST' ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.browseType === 'LATEST' ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.browseType === 'LATEST' ?
            ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) :
            Color.Transparent)
          .borderRadius(20)
          .onClick(() => {
            if (this.browseType !== 'LATEST') {
              this.browseType = 'LATEST';
              this.loadMangas(true);
            }
          })
          .fontFamily(this.appFontFamily)

        Blank()

        // 漫画数量
        Text(`${this.mangas.length} 本`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }
  }

  @Builder
  buildMangaGrid() {
    if (this.isLoading && this.mangas.length === 0) {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        Text('加载中...')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 12 })
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .height(300)
      .justifyContent(FlexAlign.Center)
    } else if (this.errorMessage) {
      Column() {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(48)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 12 })
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)
        Button('重试')
          .margin({ top: 16 })
          .onClick(() => this.loadMangas(true))
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .height(300)
      .justifyContent(FlexAlign.Center)
    } else if (this.mangas.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(48)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        Text(this.isSearchMode ? '没有找到相关漫画' : '暂无漫画')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .margin({ top: 12 })
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .height(300)
      .justifyContent(FlexAlign.Center)
    } else {
      // 漫画网格 - 动态列数适配平板横屏
      Grid() {
        ForEach(this.mangas, (manga: ComicInfo) => {
          GridItem() {
            this.buildMangaCard(manga)
          }
        })
      }
      .columnsTemplate(Array(this.gridColumns).fill('1fr').join(' '))
      .columnsGap(12)
      .rowsGap(12)
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
  }

  @Builder
  buildMangaCard(manga: ComicInfo) {
    Column() {
      // 封面 - 限制最大高度防止平板横屏时过大
      Stack({ alignContent: Alignment.BottomStart }) {
        SuwayomiImage({
          src: manga.coverUrl || '',
          imageWidth: '100%',
          imgAspectRatio: 0.7,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 8,
          placeholderColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme)
        })
          .constraintSize({ maxHeight: 200 })

        // 渐变遮罩
        Column()
          .width('100%')
          .height('50%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0.7)', 1]]
          })
          .borderRadius({ bottomLeft: 8, bottomRight: 8 })
      }
      .width('100%')
      .constraintSize({ maxHeight: 200 }) // Stack也限制高度

      // 标题
      Text(manga.title)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
        .width('100%')
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .onClick(() => this.openMangaDetail(manga))
  }

  @Builder
  buildLoadMoreButton() {
    if (this.hasMore && this.mangas.length > 0 && !this.isSearchMode) {
      Column() {
        if (this.isLoadingMore) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            Text('加载中...')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .fontFamily(this.appFontFamily)
          }
          .height(44)
          .justifyContent(FlexAlign.Center)
        } else {
          Button('加载更多')
            .width('100%')
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .borderRadius(22)
            .onClick(() => this.loadMore())
            .fontFamily(this.appFontFamily)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容
        Column() {
          Blank().height(TITLE_BAR_HEIGHT)

          // 搜索栏
          this.buildSearchBar()

          // 浏览类型选择器
          this.buildBrowseTypeSelector()

          // 漫画列表
          Scroll() {
            Column() {
              this.buildMangaGrid()
              this.buildLoadMoreButton()
              Blank().height(40)
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
      }
    }
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
        title: { mainTitle: this.source?.name || '图源浏览' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as SuwayomiSourceBrowseParams;
      if (params?.source) {
        this.source = params.source;
        // 如果传入了搜索关键词，设置并自动搜索
        if (params.keyword) {
          this.searchQuery = params.keyword;
          this.isSearchMode = true;
        }
        this.initialize().then(() => {
          // 初始化完成后，如果有搜索关键词则执行搜索
          if (params.keyword) {
            this.performSearch();
          }
        });
      }
    })
  }
}
