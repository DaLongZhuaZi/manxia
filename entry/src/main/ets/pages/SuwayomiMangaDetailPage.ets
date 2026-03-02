/**
 * Suwayomi 漫画详情页面
 * 显示漫画详情和章节列表
 * 样式参考 UnifiedDetailPage
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor } from '../Framework/Source/SuwayomiSourceExecutor';
import { ComicDetailInfo, ChapterInfo } from '../Framework/Source/SourceExecutor';
import { SuwayomiImage } from '../components/SuwayomiImage';

const TAG = 'SuwayomiMangaDetailPage';
const TITLE_BAR_HEIGHT: number = 56;
const COVER_HEIGHT: number = 200;
const COVER_WIDTH: number = 140;
const READING_PROGRESS_STORE = 'suwayomi_reading_progress';

// 页面参数接口
interface SuwayomiMangaDetailParams {
  mangaId?: string;
  title?: string;
}

// 阅读器参数接口
interface SuwayomiReaderParams {
  mangaId: string;
  chapterId: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
}

// 阅读进度数据接口
interface ReadingProgressData {
  mangaId: string;
  chapterId: string;
  chapterIndex: number;
  timestamp: number;
}

@Component
export struct SuwayomiMangaDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  // 漫画数据
  @State mangaId: string = '';
  @State mangaTitle: string = '';
  @State mangaDetail: ComicDetailInfo | null = null;

  // 章节排序
  @State sortDescending: boolean = true;

  // 阅读进度
  @State lastReadChapterId: string = '';
  @State lastReadChapterIndex: number = -1;
  @State isInLibrary: boolean = false;

  // 图片请求头
  @State imageHeaders: Record<string, string> = {};

  private executor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();

  /**
   * 加载阅读进度
   */
  private async loadReadingProgress(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: READING_PROGRESS_STORE });
      const progressKey = `manga_${this.mangaId}`;
      const progressJson = store.getSync(progressKey, '') as string;
      if (progressJson) {
        const progress = JSON.parse(progressJson) as ReadingProgressData;
        this.lastReadChapterId = progress.chapterId || '';
        this.lastReadChapterIndex = progress.chapterIndex ?? -1;
        logger.info(TAG, `加载阅读进度: 章节索引=${this.lastReadChapterIndex}`);
      }
    } catch (error) {
      logger.error(TAG, `加载阅读进度失败: ${error}`);
    }
  }

  /**
   * 保存阅读进度
   */
  private async saveReadingProgress(chapterId: string, chapterIndex: number): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(getContext(), { name: READING_PROGRESS_STORE });
      const progressKey = `manga_${this.mangaId}`;
      const progress: ReadingProgressData = {
        mangaId: this.mangaId,
        chapterId: chapterId,
        chapterIndex: chapterIndex,
        timestamp: Date.now()
      };
      store.putSync(progressKey, JSON.stringify(progress));
      await store.flush();
      this.lastReadChapterId = chapterId;
      this.lastReadChapterIndex = chapterIndex;
      logger.info(TAG, `保存阅读进度: 章节索引=${chapterIndex}`);
    } catch (error) {
      logger.error(TAG, `保存阅读进度失败: ${error}`);
    }
  }

  private async loadMangaDetail(): Promise<void> {
    if (!this.mangaId) {
      this.errorMessage = '漫画 ID 无效';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      await this.executor.initialize();
      // 获取图片请求头
      this.imageHeaders = this.executor.getImageHeaders();
      logger.info(TAG, `封面鉴权状态: authorization=${this.imageHeaders['Authorization'] ? 'present' : 'absent'}`);
      
      // 加载漫画详情
      this.mangaDetail = await this.executor.getDetail(this.mangaId);
      if (this.mangaDetail) {
        this.mangaTitle = this.mangaDetail.title;
        // 获取 inLibrary 状态
        this.isInLibrary = (this.mangaDetail as ESObject)['inLibrary'] === true;
        logger.info(TAG, `加载漫画详情: ${this.mangaDetail.title}, ${this.mangaDetail.chapters?.length || 0} 章, inLibrary=${this.isInLibrary}`);
        logger.info(TAG, `详情封面URL: ${this.mangaDetail.coverUrl ? this.mangaDetail.coverUrl.substring(0, 120) : 'empty'}`);
        
        // 查找最后阅读的章节（从服务器端 isRead 状态）
        this.findLastReadChapter();
      } else {
        this.errorMessage = '无法加载漫画详情';
      }
    } catch (error) {
      logger.error(TAG, `加载详情失败: ${error}`);
      this.errorMessage = `加载失败: ${error}`;
    }

    this.isLoading = false;
  }

  /**
   * 从服务器端数据查找最后阅读的章节
   */
  private findLastReadChapter(): void {
    if (!this.mangaDetail?.chapters) return;
    
    // 找到最后一个已读章节
    let lastReadIndex = -1;
    for (let i = 0; i < this.mangaDetail.chapters.length; i++) {
      const chapter = this.mangaDetail.chapters[i];
      if ((chapter as ESObject)['isRead'] === true) {
        lastReadIndex = i;
      }
    }
    
    if (lastReadIndex >= 0) {
      this.lastReadChapterIndex = lastReadIndex;
      this.lastReadChapterId = this.mangaDetail.chapters[lastReadIndex].id;
      logger.info(TAG, `找到最后阅读章节: index=${lastReadIndex}, id=${this.lastReadChapterId}`);
    }
  }

  private getSortedChapters(): ChapterInfo[] {
    if (!this.mangaDetail?.chapters) {
      return [];
    }
    const chapters = [...this.mangaDetail.chapters];
    if (this.sortDescending) {
      chapters.reverse();
    }
    return chapters;
  }

  /**
   * 获取章节页数
   */
  private getChapterPageCount(chapter: ChapterInfo): number {
    return (chapter as ESObject)['pageCount'] || 0;
  }

  /**
   * 获取章节最后阅读页码
   */
  private getChapterLastPageRead(chapter: ChapterInfo): number {
    return (chapter as ESObject)['lastPageRead'] || 0;
  }

  private openChapter(chapter: ChapterInfo, index: number): void {
    // 保存阅读进度
    this.saveReadingProgress(chapter.id, index);
    
    // 导航到阅读器页面
    const params: SuwayomiReaderParams = {
      mangaId: this.mangaId,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      chapterIndex: index,
      totalChapters: this.mangaDetail?.chapters?.length || 0
    };
    this.pathStack.pushPathByName('SuwayomiReaderPage', params);
  }

  /**
   * 继续阅读（从上次阅读位置）
   */
  private continueReading(): void {
    const chapters = this.getSortedChapters();
    if (chapters.length === 0) return;

    // 使用章节 ID 查找，而不是索引，因为排序可能改变了
    if (this.lastReadChapterId) {
      const chapterIndex = chapters.findIndex(
        (ch: ChapterInfo) => ch.id === this.lastReadChapterId
      );
      if (chapterIndex >= 0) {
        this.openChapter(chapters[chapterIndex], chapterIndex);
        return;
      }
    }

    // 如果没有找到阅读记录，从第一章开始
    this.openChapter(chapters[0], 0);
  }

  private async addToLibrary(): Promise<void> {
    try {
      logger.info(TAG, `尝试添加到库: mangaId=${this.mangaId}, isInLibrary=${this.isInLibrary}`);
      
      if (this.isInLibrary) {
        // 已在库中，移除
        const success = await this.executor.removeFromLibrary(this.mangaId);
        if (success) {
          this.isInLibrary = false;
          this.showToast('已从库中移除');
        } else {
          this.showToast('移除失败');
        }
      } else {
        // 不在库中，添加
        const success = await this.executor.addToLibrary(this.mangaId);
        if (success) {
          this.isInLibrary = true;
          this.showToast('已添加到库');
        } else {
          this.showToast('添加失败');
        }
      }
    } catch (error) {
      logger.error(TAG, `添加/移除库失败: ${error}`);
      this.showToast(`操作失败: ${error}`);
    }
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
  buildHeader() {
    Row({ space: 16 }) {
      // 封面
      Stack() {
        if (this.mangaDetail?.coverUrl) {
          SuwayomiImage({
            src: this.mangaDetail.coverUrl,
            imageWidth: COVER_WIDTH,
            imageHeight: COVER_HEIGHT,
            imgBorderRadius: 8,
            objectFit: ImageFit.Cover
          })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.text_book_closed'))
              .fontSize(48)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          }
          .width(COVER_WIDTH)
          .height(COVER_HEIGHT)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
        }

        // 内容类型标签
        Text('Suwayomi')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor('rgba(0,0,0,0.6)')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 4, y: 4 })
          .fontFamily(this.appFontFamily)
      }

      // 信息区域
      Column({ space: 8 }) {
        Text(this.mangaDetail?.title || '加载中...')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)

        if (this.mangaDetail?.author) {
          Text(this.mangaDetail.author)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }

        Row({ space: 8 }) {
          if (this.mangaDetail?.status) {
            Text(this.mangaDetail.status)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .fontFamily(this.appFontFamily)
          }

          Text(`${this.mangaDetail?.chapters?.length || 0}章`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .fontFamily(this.appFontFamily)
        }

        Text('来源: Suwayomi')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)

        Blank()

        // 操作按钮
        Row({ space: 12 }) {
          Button(this.lastReadChapterIndex >= 0 ? '继续阅读' : '开始阅读')
            .fontSize(14)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .fontColor(Color.White)
            .height(36)
            .layoutWeight(1)
            .onClick(() => this.continueReading())
            .fontFamily(this.appFontFamily)

          Button() {
            SymbolGlyph(this.isInLibrary ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(20)
              .fontColor([this.isInLibrary 
                ? '#FF6B6B'
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
          }
          .width(36)
          .height(36)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(18)
          .onClick(() => this.addToLibrary())
          .fontFamily(this.appFontFamily)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .height(COVER_HEIGHT)
    }
    .width('100%')
    .padding(16)
  }

  @Builder
  buildDescription() {
    if (this.mangaDetail?.description) {
      Column({ space: 8 }) {
        Text('简介')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)

        Text(this.mangaDetail.description)
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .lineHeight(20)
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  buildTags() {
    if (this.mangaDetail?.tags && this.mangaDetail.tags.length > 0) {
      Column({ space: 8 }) {
        Text('标签')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.mangaDetail.tags, (tag: string) => {
            Text(tag)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(12)
              .margin({ right: 8, bottom: 8 })
              .fontFamily(this.appFontFamily)
          })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  buildChapterList() {
    Column({ space: 12 }) {
      // 章节列表头部
      Row() {
        Text(`章节列表 (${this.mangaDetail?.chapters?.length || 0})`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .fontFamily(this.appFontFamily)

        Blank()

        // 排序按钮
        Button() {
          SymbolGlyph(this.sortDescending ? $r('sys.symbol.arrow_down') : $r('sys.symbol.arrow_up'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(32)
        .height(32)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.sortDescending = !this.sortDescending;
        })
        .fontFamily(this.appFontFamily)
      }
      .width('100%')

      // 章节列表（使用List组件）
      List() {
        ForEach(this.getSortedChapters(), (chapter: ChapterInfo, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              // 左侧：章节序号
              Column() {
                Text(`${index + 1}`)
                  .fontSize(12)
                  .fontColor(this.isChapterRead(chapter.id) 
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .fontWeight(this.isChapterRead(chapter.id) ? FontWeight.Bold : FontWeight.Normal)
                  .fontFamily(this.appFontFamily)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(this.isChapterRead(chapter.id) 
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '20'
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .justifyContent(FlexAlign.Center)

              // 中间：章节标题、页数和下载状态
              Column({ space: 2 }) {
                Text(chapter.title)
                  .fontSize(14)
                  .fontWeight(this.isChapterRead(chapter.id) ? FontWeight.Normal : FontWeight.Medium)
                  .fontColor(this.isChapterRead(chapter.id) 
                    ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.appFontFamily)

                // 页数和阅读进度信息
                Row({ space: 8 }) {
                  // 页数信息
                  if (this.getChapterPageCount(chapter) > 0) {
                    Text(`${this.getChapterPageCount(chapter)} 页`)
                      .fontSize(10)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                      .fontFamily(this.appFontFamily)
                  }

                  // 阅读进度（如果有）
                  if (this.getChapterLastPageRead(chapter) > 0 && !this.isChapterRead(chapter.id)) {
                    Text(`已读 ${this.getChapterLastPageRead(chapter)}/${this.getChapterPageCount(chapter)}`)
                      .fontSize(10)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                      .fontFamily(this.appFontFamily)
                  }

                  // 下载状态
                  if (this.isChapterDownloaded(chapter.id)) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(10)
                        .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme)])
                      Text('已缓存')
                        .fontSize(10)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                        .fontFamily(this.appFontFamily)
                    }
                  }
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 右侧：阅读状态标签
              if (this.isChapterRead(chapter.id)) {
                Text('已读')
                  .fontSize(10)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                  .borderRadius(10)
                  .fontFamily(this.appFontFamily)
              } else if (chapter.id === this.lastReadChapterId) {
                Text('阅读中')
                  .fontSize(10)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) + '15')
                  .borderRadius(10)
                  .fontFamily(this.appFontFamily)
              }
            }
            .width('100%')
            .padding({ top: 10, bottom: 10 })
            .onClick(() => this.openChapter(chapter, index))
          }
        }, (chapter: ChapterInfo) => chapter.id)
      }
      .width('100%')
      .height(350)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 检查章节是否已读（使用服务器端状态）
   */
  private isChapterRead(chapterId: string): boolean {
    if (!this.mangaDetail?.chapters) return false;
    const chapter = this.mangaDetail.chapters.find(ch => ch.id === chapterId);
    return chapter ? (chapter as ESObject)['isRead'] === true : false;
  }

  /**
   * 检查章节是否已下载
   */
  private isChapterDownloaded(chapterId: string): boolean {
    if (!this.mangaDetail?.chapters) return false;
    const chapter = this.mangaDetail.chapters.find(ch => ch.id === chapterId);
    return chapter ? (chapter as ESObject)['isDownloaded'] === true : false;
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Stack() {
          // 纯色背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 封面图片作为背景（模糊效果）
          if (this.mangaDetail?.coverUrl) {
            Image(this.mangaDetail.coverUrl)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .blur(30)
              .opacity(0.5)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          }

          // 渐变遮罩
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.2)' : 'rgba(245,245,245,0.2)', 0],
                [this.themeState.currentTheme === ThemeType.DARK ? 'rgba(26,26,26,0.7)' : 'rgba(245,245,245,0.7)', 0.3],
                [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.6]
              ]
            })
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
            Text('加载中...')
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .margin({ top: 16 })
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMessage) {
          Column({ space: 16 }) {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor('#FF6B6B')
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)

            Button('重试')
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .fontColor(Color.White)
              .onClick(() => this.loadMangaDetail())
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .padding(16)
        } else {
          Scroll() {
            Column({ space: 16 }) {
              // 顶部避让空间（避免被titlebar遮挡）
              Blank().height(TITLE_BAR_HEIGHT)

              // 头部信息（包含操作按钮）
              this.buildHeader()

              // 简介
              this.buildDescription()

              // 标签
              this.buildTags()

              // 章节列表
              this.buildChapterList()

              Blank().height(40)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 40 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
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
        title: { mainTitle: this.mangaTitle || '漫画详情' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: SuwayomiMangaDetailParams = param as SuwayomiMangaDetailParams;
        if (params.mangaId) {
          this.mangaId = params.mangaId;
        }
        if (params.title) {
          this.mangaTitle = params.title;
        }
        this.loadMangaDetail();
      }
    })
  }
}
