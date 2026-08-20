/**
 * 首页Tab内容组件
 * 从 MainMenuPage 提取的首页逻辑
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { Manga } from '../Models/MangaModels';
import { EBook } from '../Models/EBookModels';
import { NovelBook } from '../Models/NovelModels';
import { AppColors } from 'manxia_theme/src/main/ets/Framework/Theme/AppColors';
import { AvifImage } from './AvifImage';
import { getSuwayomiTracker } from '../Framework/Tracking/trackers/SuwayomiTracker';
import { getKomgaTracker } from '../Framework/Tracking/trackers/KomgaTracker';
import { UnifiedDetailPageParams, UnifiedContentType } from '../Models/UnifiedContentModels';
import { PageSettingsHelper, DetailPageType } from '../pages/settings/PageSettingsSubPage';
import { EBookDetailPageParams } from '../pages/EBookDetailPage';
import { NovelDetailPageParams } from '../pages/NovelBookshelfPage';
import { MangaDetailPageParams } from '../pages/MangaDetailPage';

const TAG = 'HomeTabContent';

interface BannerItem {
  title: string;
  subtitle: string;
  image: ResourceStr;
  backgroundColor: string;
}

@Component
export struct HomeTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 125;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @Prop homeGridColumns: number = 2;
  @Prop homeGridGap: number = 12;
  @Prop isLandscape: boolean = false;

  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private currentBannerIndex: number = 0;
  @Prop isLoadingRecentReading: boolean = false;
  @Prop recentReadingList: Manga[] = [];
  @Prop recentEBookList: EBook[] = [];
  @Prop recentNovelList: NovelBook[] = [];

  @StorageLink('userThemeBlurEnabled') private userThemeBlurEnabled: boolean = true;
  @StorageLink('userThemeCornerRadius') private userThemeCornerRadius: number = 12;
  @StorageLink('userThemeCoverCornerRadius') private userThemeCoverCornerRadius: number = 12;
  @StorageLink('userThemeShadowEnabled') private userThemeShadowEnabled: boolean = true;
  @StorageLink('source_features_enabled') private sourceFeaturesEnabled: boolean = false;

  private componentId: string = 'HomeTabContent';
  private swiperController: SwiperController = new SwiperController();

  private bannerItems: BannerItem[] = [
    {
      title: '欢迎使用漫匣',
      subtitle: '尽享精彩的漫画世界',
      image: $r('app.media.icon'),
      backgroundColor: '#1A1A2E'
    },
    {
      title: '管理您的漫画/电子书资源',
      subtitle: '热门连载，经典完结作品',
      image: $r('app.media.mangabook'),
      backgroundColor: '#16213E'
    },
    {
      title: '个性化分析',
      subtitle: '根据您的阅读习惯分析阅读偏好',
      image: $r('sys.symbol.histogram_fill'),
      backgroundColor: '#0F3460'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState,
      (theme: ThemeType) => {
        const newState = new ThemeAwareState();
        newState.updateTheme(theme);
        this.themeState = newState;
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  onRefreshSignalChanged(): void {
    // Home tab 刷新逻辑由 MainMenuPage 通过数据绑定驱动
  }

  // ── 工具方法 ──

  private isNetworkUrl(url: string | undefined): boolean {
    const normalized = typeof url === 'string' ? url.trim() : '';
    if (!normalized) return false;
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private getGlassBackground(): ResourceColor {
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(255, 255, 255, 0.68)';
    } else {
      return 'rgba(16, 22, 32, 0.78)';
    }
  }

  private getGlassBlur(): BlurStyle | undefined {
    if (!this.userThemeBlurEnabled) {
      return undefined;
    }
    return BlurStyle.Thin;
  }

  private getGlassRadius(): number {
    return this.userThemeCornerRadius;
  }

  private getCoverImageRadius(): number {
    return this.userThemeCoverCornerRadius;
  }

  private getGlassShadowColor(): string {
    if (!this.userThemeShadowEnabled) {
      return 'rgba(0, 0, 0, 0)';
    }
    if (this.themeState.currentTheme === ThemeType.LIGHT) {
      return 'rgba(0, 0, 0, 0.1)';
    } else {
      return 'rgba(0, 0, 0, 0.3)';
    }
  }

  private getHomeGridColumnsTemplate(): string {
    let template = '';
    for (let i = 0; i < this.homeGridColumns; i++) {
      template += '1fr ';
    }
    return template.trim();
  }

  // ── 导航方法 ──

  private openMangaDetail(manga: Manga): void {
    try {
      const pageType = PageSettingsHelper.getMangaDetailPageType();
      if (pageType === DetailPageType.UNIFIED) {
        const unifiedParams: UnifiedDetailPageParams = {
          contentType: UnifiedContentType.MANGA,
          contentId: manga.id,
          sourceId: manga.sourceInfo?.sourceId,
          sourceName: manga.sourceInfo?.sourceName,
          sourcePkg: manga.sourceInfo?.sourcePkg,
          cachedTitle: manga.title,
          cachedCover: manga.coverImagePath
        };
        this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      } else if (pageType === DetailPageType.EBOOK) {
        const ebookParams: EBookDetailPageParams = {
          bookId: manga.id
        };
        this.pathStack.pushPathByName('EBookDetailPage', ebookParams);
      } else {
        const params: MangaDetailPageParams = {
          mangaId: manga.id
        };
        this.pathStack.pushPathByName('MangaDetailPage', params);
      }
    } catch (error) {
      logger.error(TAG, `打开漫画详情页失败: ${String(error)}`);
    }
  }

  private openEBookDetail(ebook: EBook): void {
    try {
      const pageType = PageSettingsHelper.getEBookDetailPageType();
      if (pageType === DetailPageType.UNIFIED) {
        const unifiedParams: UnifiedDetailPageParams = {
          contentType: UnifiedContentType.EBOOK,
          contentId: ebook.id,
          cachedTitle: ebook.metadata?.title,
          cachedCover: ebook.metadata?.coverImagePath
        };
        this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
      } else {
        const params: EBookDetailPageParams = {
          bookId: ebook.id
        };
        this.pathStack.pushPathByName('EBookDetailPage', params);
      }
    } catch (error) {
      logger.error(TAG, `打开电子书详情页失败: ${String(error)}`);
    }
  }

  private openNovelDetail(novel: NovelBook): void {
    try {
      const unifiedParams: UnifiedDetailPageParams = {
        contentType: UnifiedContentType.NOVEL,
        contentId: novel.id,
        cachedTitle: novel.name,
        cachedCover: novel.coverLocalPath || novel.coverUrl
      };
      this.pathStack.pushPathByName('UnifiedDetailPage', unifiedParams);
    } catch (error) {
      logger.error(TAG, `打开小说详情页失败: ${String(error)}`);
    }
  }

  private openMangaReader(manga: Manga, componentId: string): void {
    // 简化版：直接导航到详情页，由详情页负责阅读器跳转
    this.openMangaDetail(manga);
  }

  private async navigateToSuwayomi(): Promise<void> {
    const tracker = getSuwayomiTracker();
    await tracker.initialize();
    const config = tracker.getConfig();
    if (config.useBrowsePageAsEntry && config.serverUrl) {
      this.pathStack.pushPathByName('SuwayomiBrowsePage', null);
    } else {
      this.pathStack.pushPathByName('SuwayomiSettingsPage', null);
    }
  }

  private async navigateToKomga(): Promise<void> {
    const tracker = getKomgaTracker();
    await tracker.initialize();
    const config = tracker.getConfig();
    const currentInstance = tracker.getCurrentInstance();
    if (config.useBrowsePageAsEntry && currentInstance && currentInstance.serverUrl) {
      this.pathStack.pushPathByName('KomgaBrowsePage', null);
    } else {
      this.pathStack.pushPathByName('KomgaSettingsPage', null);
    }
  }

  private switchToLibrary(): void {
    try {
      const navStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (navStack) {
        // 通过 AppStorage 触发 Tab 切换
        AppStorage.setOrCreate<boolean>('home_switch_to_library', true);
      }
    } catch (error) {
      logger.warn(TAG, `切换到书库失败: ${String(error)}`);
    }
  }

  // ── @Builder 方法 ──

  @Builder
  buildBannerSwiper() {
    Swiper(this.swiperController) {
      ForEach(this.bannerItems, (item: BannerItem, index: number) => {
        Row() {
          Column({ space: this.isLandscape ? 4 : 8 }) {
            Text(item.title)
              .fontSize(this.isLandscape ? 18 : 24)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)

            Text(item.subtitle)
              .fontSize(this.isLandscape ? 13 : 16)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
              .opacity(0.9)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image(item.image)
            .width(this.isLandscape ? 60 : 80)
            .height(this.isLandscape ? 60 : 80)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
        .width('100%')
        .height(this.isLandscape ? 80 : 120)
        .padding(this.isLandscape ? 12 : 16)
        .backgroundColor(item.backgroundColor)
        .borderRadius(12)
      })
    }
    .width('100%')
    .height(this.isLandscape ? 80 : 120)
    .autoPlay(true)
    .interval(4000)
    .indicator(
      new DotIndicator()
        .itemWidth(8)
        .itemHeight(8)
        .selectedItemWidth(16)
        .selectedItemHeight(8)
        .color(Color.White)
        .selectedColor(Color.White)
    )
    .onChange((index: number) => {
      this.currentBannerIndex = index;
    })
  }

  @Builder
  buildNovelEntryCardCompact() {
    Column({ space: 8 }) {
      if (this.sourceFeaturesEnabled) {
        Image($r('app.media.legado'))
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
      } else {
        SymbolGlyph($r('sys.symbol.text_book_closed'))
          .fontSize(28)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
      }

      Text('小说阅读')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text(this.sourceFeaturesEnabled ? 'Legado书源' : '本地小说')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.pathStack.pushPathByName('NovelBookshelfPage', null);
    })
  }

  @Builder
  buildSuwayomiEntryCardCompact() {
    Column({ space: 8 }) {
      Image($r('app.media.suwayomi_icon'))
        .width(40)
        .height(40)

      Text('Suwayomi')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text('漫画服务器')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      void this.navigateToSuwayomi();
    })
  }

  @Builder
  buildKomgaEntryCardCompact() {
    Column({ space: 8 }) {
      Image($r('app.media.komga_icon'))
        .width(44)
        .height(44)

      Text('Komga')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text('自建漫画库')
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getGlassBackground())
    .backgroundBlurStyle(this.getGlassBlur())
    .borderRadius(this.getGlassRadius())
    .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      void this.navigateToKomga();
    })
  }

  @Builder
  buildRecentReadingWaterfall() {
    Grid() {
      ForEach(this.recentReadingList, (manga: Manga) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              if (this.isNetworkUrl(manga.coverImagePath)) {
                AvifImage({
                  src: manga.coverImagePath,
                  imageWidth: '100%',
                  imageHeight: '100%',
                  objectFit: ImageFit.Cover,
                  imageBorderRadius: this.getCoverImageRadius(),
                })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .id(`cover_manga_home_${manga.id}`)
              } else {
                Image(manga.coverImagePath || $r('app.media.mangabook'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .borderRadius(this.getCoverImageRadius())
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                  .onError(() => {
                    logger.warn(TAG, `封面加载失败: ${manga.id}`);
                  })
                  .id(`cover_manga_home_${manga.id}`)
              }
            }
            .width('100%')
            .aspectRatio(0.7)
            .shadow({ radius: 8, color: AppColors.getShadowColor(4), offsetY: 4 })
            .borderRadius(this.getCoverImageRadius())
            .clip(true)
            .onClick(() => {
              this.openMangaReader(manga, `cover_manga_home_${manga.id}`);
            })

            Text(manga.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openMangaDetail(manga); })
          }
          .width('100%')
        }
      }, (manga: Manga) => `manga_${manga.id}`)

      ForEach(this.recentEBookList, (ebook: EBook) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              if (this.isNetworkUrl(ebook.metadata?.coverImagePath)) {
                AvifImage({
                  src: ebook.metadata?.coverImagePath || '',
                  imageWidth: '100%',
                  imageHeight: '100%',
                  objectFit: ImageFit.Cover,
                  imageBorderRadius: this.getCoverImageRadius(),
                })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .id(`cover_ebook_home_${ebook.id}`)
              } else {
                Image(ebook.metadata?.coverImagePath || $r('app.media.ic_ebook'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .borderRadius(this.getCoverImageRadius())
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                  .onError(() => {
                    logger.warn(TAG, `电子书封面加载失败: ${ebook.id}`);
                  })
                  .id(`cover_ebook_home_${ebook.id}`)
              }
            }
            .width('100%')
            .aspectRatio(0.7)
            .shadow({ radius: 8, color: AppColors.getShadowColor(4), offsetY: 4 })
            .borderRadius(this.getCoverImageRadius())
            .clip(true)
            .onClick(() => {
              this.openEBookDetail(ebook);
            })

            Text(ebook.metadata.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openEBookDetail(ebook); })
          }
          .width('100%')
        }
      }, (ebook: EBook) => `ebook_${ebook.id}`)

      ForEach(this.recentNovelList, (novel: NovelBook) => {
        GridItem() {
          Column({ space: 8 }) {
            Stack() {
              if (this.isNetworkUrl(novel.coverUrl)) {
                AvifImage({
                  src: novel.coverUrl || '',
                  imageWidth: '100%',
                  imageHeight: '100%',
                  objectFit: ImageFit.Cover,
                  imageBorderRadius: this.getCoverImageRadius(),
                })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                .id(`cover_novel_home_${novel.id}`)
              } else {
                Image(novel.coverLocalPath || novel.coverUrl || $r('app.media.ic_source_novel'))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .borderRadius(this.getCoverImageRadius())
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                  .onError(() => {
                    logger.warn(TAG, `小说封面加载失败: ${novel.id}`);
                  })
                  .id(`cover_novel_home_${novel.id}`)
              }

              Text('小说')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(AppColors.onSuccess)
                .backgroundColor(AppColors.success)
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(4)
                .position({ x: 4, y: 4 })
            }
            .width('100%')
            .aspectRatio(0.7)
            .shadow({ radius: 8, color: AppColors.getShadowColor(4), offsetY: 4 })
            .borderRadius(this.getCoverImageRadius())
            .clip(true)
            .onClick(() => {
              this.openNovelDetail(novel);
            })

            Text(novel.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .onClick(() => { this.openNovelDetail(novel); })
          }
          .width('100%')
        }
      }, (novel: NovelBook) => `novel_${novel.id}`)
    }
    .columnsTemplate(this.getHomeGridColumnsTemplate())
    .columnsGap(this.homeGridGap)
    .rowsGap(this.homeGridGap)
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
  }

  @Builder
  buildHomeContent() {
    Column({ space: 16 }) {
      this.buildBannerSwiper()

      Row({ space: 12 }) {
        Column() {
          this.buildNovelEntryCardCompact()
        }
        .layoutWeight(1)

        Column() {
          this.buildSuwayomiEntryCardCompact()
        }
        .layoutWeight(1)
      }
      .width('100%')

      Column() {
        this.buildKomgaEntryCardCompact()
      }
      .width('100%')

      Column({ space: 12 }) {
        Row() {
          Text('最近阅读')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Blank()

          Text('查看全部 >')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .onClick(() => {
              this.switchToLibrary();
            })
        }
        .width('100%')

        if (this.isLoadingRecentReading) {
          Row() {
            LoadingProgress()
              .width(24)
              .height(24)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text('加载中...')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ left: 8 })
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getGlassBackground())
          .backgroundBlurStyle(this.getGlassBlur())
          .borderRadius(this.getGlassRadius())
          .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else if (this.recentReadingList.length === 0 && this.recentEBookList.length === 0 && this.recentNovelList.length === 0) {
          Column({ space: 8 }) {
            Image($r('sys.symbol.clock'))
              .width(48)
              .height(48)

            Text('暂无阅读记录')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

            Button('去书库看看')
              .fontSize(14)
              .height(32)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .backgroundColor(this.getGlassBackground())
              .backgroundBlurStyle(this.getGlassBlur())
              .borderRadius(16)
              .clip(true)
              .onClick(() => {
                this.switchToLibrary();
              })
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.getGlassBackground())
          .backgroundBlurStyle(this.getGlassBlur())
          .borderRadius(this.getGlassRadius())
          .shadow({ radius: this.getGlassRadius(), color: this.getGlassShadowColor(), offsetX: 0, offsetY: 4 })
        } else {
          this.buildRecentReadingWaterfall()
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }

  build() {
    Column() {
      Blank().height(this.topSpacerHeight)
      this.buildHomeContent()
      Blank().height(this.bottomSpacerHeight)
    }
    .width('100%')
    .height('100%')
  }
}
