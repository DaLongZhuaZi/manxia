import { preferences } from '@kit.ArkData';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { ChapterInfo, ComicDetailInfo } from '../Framework/Source/SourceExecutor';
import { getKomgaSourceExecutor, KomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';
import { KomgaContentType, KomgaReaderProgress } from '../Framework/Source/KomgaModels';
import { KomgaImage } from '../components/KomgaImage';

const TAG = 'KomgaMangaDetailPage';
const READING_PROGRESS_STORE: string = 'komga_reading_progress';
const TITLE_BAR_HEIGHT: number = 56;
const HERO_HEIGHT: number = 360;

type KomgaDetailColorKey =
  'accent_blue' |
  'background_dark' |
  'comp_background_tertiary' |
  'icon_primary' |
  'panel_background' |
  'panel_border' |
  'text_muted' |
  'text_primary';

interface KomgaMangaDetailParams {
  itemId: string;
  contentType: KomgaContentType;
  title?: string;
}

interface KomgaReaderParams {
  itemId: string;
  contentType: KomgaContentType;
  bookId: string;
  chapterIndex: number;
  mangaTitle: string;
}

@Component
export struct KomgaMangaDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State pageContentOpacity: number = 0;
  @State itemId: string = '';
  @State contentType: KomgaContentType = 'SERIES';
  @State pageTitle: string = '';
  @State detail: ComicDetailInfo | null = null;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State sortDescending: boolean = true;
  @State lastReadBookId: string = '';
  @State lastReadChapterIndex: number = -1;
  @State lastReadPageIndex: number = 0;
  @State descriptionExpanded: boolean = false;

  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private componentId: string = 'KomgaMangaDetailPage';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (_newTheme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  private color(name: KomgaDetailColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 1800 });
  }

  private revealPageContent(): void {
    animateTo({
      duration: 280,
      curve: Curve.EaseOut
    }, () => {
      this.pageContentOpacity = 1;
    });
  }

  private getHostContext(): common.UIAbilityContext {
    const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('Komga 详情页无法获取 UIAbilityContext');
    }
    return context;
  }

  private getProgressKey(): string {
    return `${this.contentType}_${this.itemId}`;
  }

  private async loadReadingProgress(): Promise<void> {
    try {
      const store = preferences.getPreferencesSync(this.getHostContext(), { name: READING_PROGRESS_STORE });
      const rawText = store.getSync(this.getProgressKey(), '') as string;
      if (!rawText) {
        this.lastReadBookId = '';
        this.lastReadChapterIndex = -1;
        this.lastReadPageIndex = 0;
        return;
      }

      const progress: KomgaReaderProgress = JSON.parse(rawText) as KomgaReaderProgress;
      this.lastReadBookId = progress.bookId || '';
      this.lastReadChapterIndex = progress.chapterIndex >= 0 ? progress.chapterIndex : -1;
      this.lastReadPageIndex = progress.pageIndex >= 0 ? progress.pageIndex : 0;
    } catch (error) {
      logger.warn(TAG, `读取 Komga 阅读进度失败: ${String(error)}`);
      this.lastReadBookId = '';
      this.lastReadChapterIndex = -1;
      this.lastReadPageIndex = 0;
    }
  }

  private async loadDetail(): Promise<void> {
    if (this.itemId.length <= 0) {
      this.errorMessage = '无效的 Komga 条目';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    try {
      await this.executor.initialize(true);
      this.detail = await this.executor.getDetail(this.itemId, this.contentType);
      if (this.detail !== null) {
        this.pageTitle = this.detail.title;
      } else {
        this.errorMessage = '未能获取详情数据';
      }
      await this.loadReadingProgress();
    } catch (error) {
      logger.error(TAG, `加载 Komga 详情失败: ${String(error)}`);
      this.errorMessage = `加载失败：${String(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private copyChapters(source?: ChapterInfo[]): ChapterInfo[] {
    if (source === null || source === undefined || source.length <= 0) {
      return [];
    }
    return source.concat();
  }

  private getSortedChapters(): ChapterInfo[] {
    const chapters: ChapterInfo[] = this.copyChapters(this.detail?.chapters);
    chapters.sort((left: ChapterInfo, right: ChapterInfo) => {
      const leftNumber: number = this.getChapterNumber(left);
      const rightNumber: number = this.getChapterNumber(right);
      return this.sortDescending ? rightNumber - leftNumber : leftNumber - rightNumber;
    });
    return chapters;
  }

  private getChapterNumber(chapter: ChapterInfo): number {
    return typeof chapter.chapterNumber === 'number' ? Number(chapter.chapterNumber) : 0;
  }

  private getReaderIndex(chapterId: string): number {
    const descending: ChapterInfo[] = this.copyChapters(this.detail?.chapters);
    descending.sort((left: ChapterInfo, right: ChapterInfo) => {
      const leftNumber: number = this.getChapterNumber(left);
      const rightNumber: number = this.getChapterNumber(right);
      return rightNumber - leftNumber;
    });
    return descending.findIndex((item: ChapterInfo) => item.id === chapterId);
  }

  private getDetailStringField(key: string): string {
    if (this.detail === null) {
      return '';
    }
    const data: ESObject = this.detail as ESObject;
    const raw: Object = data[key];
    return typeof raw === 'string' ? String(raw) : '';
  }

  private getDetailNumberField(key: string): number {
    if (this.detail === null) {
      return 0;
    }
    const data: ESObject = this.detail as ESObject;
    const raw: Object = data[key];
    if (typeof raw === 'number') {
      return Number(raw);
    }
    if (typeof raw === 'string') {
      const parsed: number = Number(raw);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private getContentTypeLabel(): string {
    if (this.contentType === 'READLISTS') {
      return '阅读列表';
    }
    if (this.contentType === 'BOOKS') {
      return '书籍';
    }
    return '系列';
  }

  private getDescriptionText(): string {
    const summary: string = this.getDetailStringField('summary');
    if (summary.length > 0) {
      return summary;
    }
    if (this.detail !== null && this.detail.description !== undefined && this.detail.description.length > 0) {
      return this.detail.description;
    }
    return '暂无简介';
  }

  private getTags(): string[] {
    if (this.detail === null || this.detail.tags === undefined || this.detail.tags.length <= 0) {
      return [];
    }
    return this.detail.tags.concat();
  }

  private getChapterCount(): number {
    const chapters: ChapterInfo[] = this.getSortedChapters();
    if (chapters.length > 0) {
      return chapters.length;
    }
    const bookCount: number = this.getDetailNumberField('bookCount');
    return bookCount > 0 ? bookCount : 0;
  }

  private getPageCountLabel(): string {
    const pageCount: number = this.getDetailNumberField('pageCount');
    return pageCount > 0 ? `${pageCount} 页` : '未记录页数';
  }

  private getPublisherLabel(): string {
    const publisher: string = this.getDetailStringField('publisher');
    return publisher.length > 0 ? publisher : '未记录出版社';
  }

  private getLanguageLabel(): string {
    const language: string = this.getDetailStringField('language');
    return language.length > 0 ? language : '语言未标注';
  }

  private getReleaseDateLabel(): string {
    const releaseDate: string = this.getDetailStringField('releaseDate');
    return releaseDate.length > 0 ? releaseDate : '未记录时间';
  }

  private getHeaderMetaLine(): string {
    const segments: string[] = [];
    if (this.detail !== null && this.detail.author !== undefined && this.detail.author.length > 0) {
      segments.push(this.detail.author);
    }
    const publisher: string = this.getDetailStringField('publisher');
    if (publisher.length > 0) {
      segments.push(publisher);
    }
    const language: string = this.getDetailStringField('language');
    if (language.length > 0) {
      segments.push(language);
    }
    return segments.length > 0 ? segments.join(' · ') : 'Komga 自建内容';
  }

  private getStatusLabel(): string {
    if (this.detail !== null && this.detail.status !== undefined && this.detail.status.length > 0 && this.detail.status !== 'UNKNOWN') {
      return this.detail.status;
    }
    return '状态未标注';
  }

  private getLastReadChapter(): ChapterInfo | null {
    if (this.lastReadBookId.length <= 0) {
      return null;
    }
    const chapters: ChapterInfo[] = this.getSortedChapters();
    for (let index: number = 0; index < chapters.length; index++) {
      if (chapters[index].id === this.lastReadBookId) {
        return chapters[index];
      }
    }
    return null;
  }

  private getContinueDescription(): string {
    const chapter: ChapterInfo | null = this.getLastReadChapter();
    if (chapter !== null) {
      return `${chapter.title} · 第 ${this.lastReadPageIndex + 1} 页`;
    }
    const chapterCount: number = this.getChapterCount();
    if (chapterCount > 0) {
      return `共 ${chapterCount} 条可阅读内容`;
    }
    return '当前没有可阅读内容';
  }

  private buildChapterMeta(chapter: ChapterInfo): string {
    const segments: string[] = [];
    const chapterNumber: number = this.getChapterNumber(chapter);
    if (chapterNumber > 0) {
      segments.push(`编号 ${chapterNumber}`);
    }
    if (chapter.pageCount !== undefined && chapter.pageCount > 0) {
      segments.push(`${chapter.pageCount} 页`);
    }
    if (this.contentType !== 'SERIES' && chapter.seriesTitle !== undefined && chapter.seriesTitle.length > 0) {
      segments.push(chapter.seriesTitle);
    }
    if (chapter.updateTime !== undefined && chapter.updateTime > 0) {
      segments.push(this.formatTimestamp(chapter.updateTime));
    }
    return segments.length > 0 ? segments.join(' · ') : '点击进入阅读器';
  }

  private formatTimestamp(timestamp: number): string {
    try {
      const date: Date = new Date(timestamp);
      const year: number = date.getFullYear();
      const month: string = String(date.getMonth() + 1).padStart(2, '0');
      const day: string = String(date.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    } catch (_error) {
      return '';
    }
  }

  private openChapter(chapter: ChapterInfo): void {
    const chapterIndex: number = this.getReaderIndex(chapter.id);
    const params: KomgaReaderParams = {
      itemId: this.itemId,
      contentType: this.contentType,
      bookId: chapter.id,
      chapterIndex: chapterIndex >= 0 ? chapterIndex : 0,
      mangaTitle: this.detail !== null ? this.detail.title : this.pageTitle
    };
    this.pathStack.pushPathByName('KomgaReaderPage', params);
  }

  private continueReading(): void {
    const chapters: ChapterInfo[] = this.getSortedChapters();
    if (chapters.length <= 0) {
      this.toast('当前没有可阅读内容');
      return;
    }

    if (this.lastReadBookId.length > 0) {
      for (let index: number = 0; index < chapters.length; index++) {
        if (chapters[index].id === this.lastReadBookId) {
          this.openChapter(chapters[index]);
          return;
        }
      }
    }

    this.openChapter(chapters[0]);
  }

  private toggleDescriptionExpanded(): void {
    this.descriptionExpanded = !this.descriptionExpanded;
  }

  @Builder
  private buildBadge(text: string, highlighted: boolean = false) {
    Text(text)
      .fontSize(11)
      .fontColor(highlighted ? Color.White : this.color('text_primary'))
      .fontFamily(this.appFontFamily)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(highlighted ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(999)
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private buildInfoCard(title: string, value: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(11)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .padding(14)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(16)
    .border({ width: 1, color: this.color('panel_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHeroSection() {
    Row({ space: 16 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        KomgaImage({
          src: this.detail !== null ? (this.detail.coverUrl || '') : '',
          imageWidth: 136,
          imageHeight: 196,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 18
        })
        Text(this.getContentTypeLabel())
          .fontSize(11)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(0, 0, 0, 0.56)')
          .borderRadius(999)
          .margin({ top: 10, right: 10 })
      }

      Column({ space: 10 }) {
        Row({ space: 8 }) {
          this.buildBadge('Komga', true)
          this.buildBadge(this.getStatusLabel())
        }

        Text(this.detail !== null ? this.detail.title : this.pageTitle)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.getHeaderMetaLine())
          .fontSize(13)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 12 }) {
          Text(`${this.getChapterCount()} 项内容`)
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
          Text(this.getPageCountLabel())
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
        }

        Row({ space: 12 }) {
          Button(this.lastReadBookId.length > 0 ? '继续阅读' : '开始阅读')
            .height(38)
            .layoutWeight(1)
            .backgroundColor(this.color('accent_blue'))
            .fontColor(Color.White)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .onClick(() => this.continueReading())

          Button(this.sortDescending ? '最新在前' : '最旧在前')
            .height(38)
            .layoutWeight(1)
            .backgroundColor(this.color('comp_background_tertiary'))
            .fontColor(this.color('text_primary'))
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .onClick(() => {
              this.sortDescending = !this.sortDescending;
            })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(24)
    .border({ width: 1, color: this.color('panel_border') })
  }

  @Builder
  private buildContinueSection() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 4 }) {
          Text('继续阅读')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text(this.getContinueDescription())
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('打开')
          .height(32)
          .backgroundColor(this.color('accent_blue'))
          .fontColor(Color.White)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .onClick(() => this.continueReading())
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildInfoCard('内容类型', this.getContentTypeLabel())
        this.buildInfoCard('发布时间', this.getReleaseDateLabel())
        this.buildInfoCard('出版社', this.getPublisherLabel())
        this.buildInfoCard('语言', this.getLanguageLabel())
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(20)
    .border({ width: 1, color: this.color('panel_border') })
  }

  @Builder
  private buildDescriptionSection() {
    Column({ space: 10 }) {
      Text('简介')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)

      Text(this.getDescriptionText())
        .fontSize(13)
        .lineHeight(22)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
        .maxLines(this.descriptionExpanded ? 99 : 6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.getDescriptionText().length > 36) {
        Button(this.descriptionExpanded ? '收起简介' : '展开简介')
          .height(32)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .onClick(() => this.toggleDescriptionExpanded())
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(20)
    .border({ width: 1, color: this.color('panel_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTagsSection() {
    Column({ space: 10 }) {
      Text('标签')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .alignSelf(ItemAlign.Start)

      if (this.getTags().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.getTags(), (tag: string) => {
            this.buildBadge(tag)
          }, (tag: string) => tag)
        }
      } else {
        Text('当前内容暂未提供标签。')
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(20)
    .border({ width: 1, color: this.color('panel_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildChapterItem(chapter: ChapterInfo) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(48)
          .height(48)
          .backgroundColor(this.isLastReadChapter(chapter) ? this.color('accent_blue') : this.color('comp_background_tertiary'))
          .borderRadius(14)

        Text(this.getChapterBadgeText(chapter))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isLastReadChapter(chapter) ? Color.White : this.color('text_primary'))
          .fontFamily(this.appFontFamily)
      }

      Column({ space: 6 }) {
        Text(chapter.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.buildChapterMeta(chapter))
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.isLastReadChapter(chapter)) {
          Text(`上次阅读到第 ${this.lastReadPageIndex + 1} 页`)
            .fontSize(11)
            .fontColor(this.color('accent_blue'))
            .fontFamily(this.appFontFamily)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        if (this.isLastReadChapter(chapter)) {
          this.buildBadge('最近阅读', true)
        } else {
          this.buildBadge('阅读')
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.color('panel_background'))
    .borderRadius(18)
    .border({ width: 1, color: this.color('panel_border') })
    .onClick(() => this.openChapter(chapter))
  }

  @Builder
  private buildChapterSection() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text('章节列表')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text(`共 ${this.getSortedChapters().length} 条内容`)
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(this.sortDescending ? '最新在前' : '最旧在前')
          .height(32)
          .backgroundColor(this.color('comp_background_tertiary'))
          .fontColor(this.color('text_primary'))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            this.sortDescending = !this.sortDescending;
          })
      }
      .width('100%')

      if (this.getSortedChapters().length > 0) {
        Column({ space: 12 }) {
          ForEach(this.getSortedChapters(), (chapter: ChapterInfo) => {
            this.buildChapterItem(chapter)
          }, (chapter: ChapterInfo) => chapter.id)
        }
        .width('100%')
      } else {
        Column({ space: 10 }) {
          Text('暂无可阅读内容')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.color('text_primary'))
            .fontFamily(this.appFontFamily)
          Text('请检查 Komga 服务器中的书籍元数据或章节同步状态。')
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(24)
        .backgroundColor(this.color('panel_background'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
      }
    }
    .width('100%')
  }

  private getChapterBadgeText(chapter: ChapterInfo): string {
    const chapterNumber: number = this.getChapterNumber(chapter);
    if (chapterNumber > 0) {
      return `${chapterNumber}`;
    }
    return '读';
  }

  private isLastReadChapter(chapter: ChapterInfo): boolean {
    return this.lastReadBookId.length > 0 && this.lastReadBookId === chapter.id;
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 14 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text('正在同步 Komga 详情…')
        .fontSize(14)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.pageContentOpacity)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildErrorState() {
    Column({ space: 16 }) {
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor('#FF6B6B')
        .fontFamily(this.appFontFamily)
        .textAlign(TextAlign.Center)

      Button('重新加载')
        .backgroundColor(this.color('accent_blue'))
        .fontColor(Color.White)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          void this.loadDetail();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
    .opacity(this.pageContentOpacity)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.color('background_dark'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.detail !== null && this.detail.coverUrl !== undefined && this.detail.coverUrl.length > 0) {
          KomgaImage({
            src: this.detail.coverUrl,
            imageWidth: '100%',
            imageHeight: HERO_HEIGHT,
            objectFit: ImageFit.Cover,
            imgBorderRadius: 0
          })
            .width('100%')
            .height(HERO_HEIGHT)
            .opacity(0.26)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        }

        Column()
          .width('100%')
          .height(HERO_HEIGHT + 120)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [
              ['rgba(0,0,0,0.08)', 0],
              ['rgba(0,0,0,0.26)', 0.28],
              [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.78]
            ]
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

        if (this.isLoading) {
          this.buildLoadingState()
        } else if (this.errorMessage.length > 0) {
          this.buildErrorState()
        } else if (this.detail !== null) {
          Scroll() {
            Column({ space: 16 }) {
              Blank().height(TITLE_BAR_HEIGHT + 12)
              this.buildHeroSection()
              this.buildContinueSection()
              this.buildDescriptionSection()
              this.buildTagsSection()
              this.buildChapterSection()
              Blank().height(28)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 28 })
            .opacity(this.pageContentOpacity)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.pageTitle.length > 0 ? this.pageTitle : 'Komga 详情')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: KomgaMangaDetailParams = param as KomgaMangaDetailParams;
        this.itemId = params.itemId;
        this.contentType = params.contentType;
        this.pageTitle = params.title || '';
      }
      void this.loadDetail();
    })
    .onShown(() => {
      this.revealPageContent();
    })
  }
}
