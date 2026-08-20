import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { Manga } from 'manxia_core/src/main/ets/Models/MangaModels';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { DataManager, ReadHistory } from '../Framework/Data/DataManager';
import { RemoteLibraryMangaBridge } from '../Framework/Source/RemoteLibraryMangaBridge';
import { getRemoteLibraryShelfManager, RemoteLibraryShelfManager } from '../Framework/Source/RemoteLibraryShelfManager';
import SuwayomiCacheManager from '../Framework/Source/SuwayomiCacheManager';
import { ComicDetailInfo, ChapterInfo } from '../Framework/Source/SourceExecutor';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor } from '../Framework/Source/SuwayomiSourceExecutor';
import { SuwayomiImage } from '../components/SuwayomiImage';
import { MangaReaderContentType, MangaReaderPageParams } from './MangaReaderPage';
import { openMangaReaderInIsolatedAbility } from '../Framework/Reader/MangaReaderAbilityLauncher';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';

const TAG = 'SuwayomiMangaDetailPage';
const HERO_HEIGHT: number = 360;
const COMPONENT_ID: string = 'SuwayomiMangaDetailPage';

type SuwayomiDetailColorKey =
  'accent_blue' |
  'accent_green' |
  'background_dark' |
  'comp_background_tertiary' |
  'icon_primary' |
  'panel_background' |
  'panel_border' |
  'text_muted' |
  'text_primary';

interface SuwayomiMangaDetailParams {
  mangaId?: string;
  title?: string;
}

interface SuwayomiDetailChapterInfo extends ChapterInfo {
  isRead?: boolean;
  isDownloaded?: boolean;
  pageCount?: number;
  lastPageRead?: number;
}

interface SuwayomiDetailInfo extends ComicDetailInfo {
  inLibrary?: boolean;
  chapters?: SuwayomiDetailChapterInfo[];
}

@Component
export struct SuwayomiMangaDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State pageContentOpacity: number = 0;
  @State descriptionExpanded: boolean = false;
  @State isLibraryActionPending: boolean = false;

  @State mangaId: string = '';
  @State mangaTitle: string = '';
  @State mangaDetail: SuwayomiDetailInfo | null = null;
  @State originalCoverUrl: string = '';
  @State displayCoverUrl: string = '';

  @State sortDescending: boolean = true;
  @State lastReadChapterId: string = '';
  @State lastReadChapterIndex: number = -1;
  @State lastReadPageIndex: number = 0;
  @State isInLocalLibrary: boolean = false;
  @State isInRemoteLibrary: boolean = false;
  @State imageHeaders: Record<string, string> = {};

  private readonly executor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private readonly remoteLibraryBridge: RemoteLibraryMangaBridge = RemoteLibraryMangaBridge.getInstance();
  private readonly remoteLibraryShelfManager: RemoteLibraryShelfManager = getRemoteLibraryShelfManager();
  private readonly themeManager: ThemeManager = ThemeManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(COMPONENT_ID, this.themeState, (_newTheme: ThemeType) => {
    });
    FontAwareHelper.initializeFontAware(COMPONENT_ID, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(COMPONENT_ID);
    FontAwareHelper.cleanupFontAware(COMPONENT_ID);
  }

  private color(name: SuwayomiDetailColorKey): ResourceColor {
    return ThemeAwareHelper.getTestManagementThemedColor(name, this.themeState.currentTheme);
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private getTitleBarActions(): SettingsImmersiveTitleActionItem[] {
    return [
      {
        id: 'refresh',
        symbol: $r('sys.symbol.arrow_clockwise'),
        label: '刷新',
        enabled: !this.isLoading,
        onClick: () => {
          void this.loadMangaDetail();
        }
      }
    ];
  }

  private revealPageContent(): void {
    const uiContext = this.getUIContext();
    if (!uiContext) {
      this.pageContentOpacity = 1;
      return;
    }

    uiContext.animateTo({
      duration: 280,
      curve: Curve.EaseOut
    }, () => {
      this.pageContentOpacity = 1;
    });
  }

  private getSyntheticMangaId(): string {
    return RemoteLibraryMangaBridge.buildSuwayomiMangaId(this.mangaId);
  }

  private getDisplayCoverUrl(): string {
    const remoteCoverUrl = String(this.originalCoverUrl || '').trim();
    if (remoteCoverUrl.startsWith('http://') || remoteCoverUrl.startsWith('https://')) {
      return remoteCoverUrl;
    }
    const rawCoverUrl = String(this.displayCoverUrl || '').trim();
    if (rawCoverUrl.length <= 0) {
      return '';
    }
    if (rawCoverUrl.startsWith('file://') || rawCoverUrl.startsWith('http://') || rawCoverUrl.startsWith('https://')) {
      return rawCoverUrl;
    }
    return `file://${rawCoverUrl}`;
  }

  private getPreferredLibraryCoverSource(): string {
    const currentCoverPath = String(this.displayCoverUrl || '').trim();
    const referenceCoverPath = this.originalCoverUrl.length > 0 ? this.originalCoverUrl : currentCoverPath;
    if (referenceCoverPath.startsWith('http://') || referenceCoverPath.startsWith('https://')) {
      const cachedCoverPath = SuwayomiCacheManager.getCachedCoverPath(this.mangaId, referenceCoverPath);
      if (cachedCoverPath !== null && cachedCoverPath.length > 0) {
        return cachedCoverPath;
      }
    }
    return currentCoverPath;
  }

  private ensureDetailCoverCached(): void {
    if (this.originalCoverUrl.length <= 0) {
      return;
    }
    if (!this.originalCoverUrl.startsWith('http://') && !this.originalCoverUrl.startsWith('https://')) {
      return;
    }

    const cachedCoverPath = SuwayomiCacheManager.getCachedCoverPath(this.mangaId, this.originalCoverUrl);
    if (cachedCoverPath !== null && cachedCoverPath.length > 0) {
      return;
    }

    const headers = this.executor.getImageHeaders();
    void SuwayomiCacheManager.cacheCover(this.mangaId, this.originalCoverUrl, headers).catch((error: Error) => {
      logger.debug(TAG, `Suwayomi 详情封面预缓存失败: ${error.message}`);
    });
  }

  private getChapterPageCount(chapter: SuwayomiDetailChapterInfo): number {
    return typeof chapter.pageCount === 'number' ? chapter.pageCount : 0;
  }

  private getChapterLastPageRead(chapter: SuwayomiDetailChapterInfo): number {
    return typeof chapter.lastPageRead === 'number' ? chapter.lastPageRead : 0;
  }

  private async loadLocalLibraryState(): Promise<void> {
    const syntheticMangaId = this.getSyntheticMangaId();
    this.isInLocalLibrary = await this.remoteLibraryShelfManager.isInLocalLibrary(syntheticMangaId);

    if (!this.isInLocalLibrary) {
      return;
    }

    const cachedManga = await this.remoteLibraryBridge.getCachedMangaById(syntheticMangaId);
    if (cachedManga === null || this.mangaDetail === null) {
      return;
    }

    const cachedCoverPath = String(cachedManga.coverImagePath || '').trim();
    if (cachedCoverPath.length > 0 && !cachedCoverPath.startsWith('http://') && !cachedCoverPath.startsWith('https://')) {
      this.displayCoverUrl = cachedCoverPath;
    }
  }

  private buildCurrentMangaForLibrary(): Manga | undefined {
    if (this.mangaDetail === null || this.mangaId.length <= 0) {
      return undefined;
    }
    const currentManga = this.remoteLibraryBridge.buildSuwayomiMangaFromDetail(this.mangaDetail, this.mangaId);
    const preferredCoverSource = this.getPreferredLibraryCoverSource();
    if (preferredCoverSource.length > 0) {
      currentManga.coverImagePath = preferredCoverSource;
    }
    return currentManga;
  }

  private async toggleLocalLibrary(): Promise<void> {
    if (this.isLibraryActionPending || this.mangaDetail === null || this.mangaId.length <= 0) {
      return;
    }

    const currentManga = this.buildCurrentMangaForLibrary();
    if (currentManga === undefined) {
      this.showToast('当前漫画信息不完整');
      return;
    }

    const uiContext = this.getUIContext();
    if (uiContext === undefined || uiContext === null) {
      this.showToast('无法获取页面上下文');
      return;
    }

    const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
    const filesDir = hostContext && typeof hostContext.filesDir === 'string' ? String(hostContext.filesDir) : '';
    if (filesDir.length <= 0) {
      this.showToast('无法获取本地书库目录');
      return;
    }

    this.isLibraryActionPending = true;
    try {
      if (this.isInLocalLibrary) {
        await this.remoteLibraryShelfManager.removeFromLocalLibrary(currentManga, filesDir);
        this.isInLocalLibrary = false;
        if (this.originalCoverUrl.length > 0) {
          this.displayCoverUrl = this.originalCoverUrl;
        }
        this.showToast('已从本地书架移除');
      } else {
        const updatedManga = await this.remoteLibraryShelfManager.addToLocalLibrary(currentManga, filesDir);
        this.isInLocalLibrary = true;
        if (updatedManga.coverImagePath.length > 0) {
          this.displayCoverUrl = updatedManga.coverImagePath;
        }
        this.showToast('已加入本地书架');
      }
    } catch (error) {
      logger.error(TAG, `切换本地书架状态失败: ${String(error)}`);
      this.showToast('书架操作失败');
    } finally {
      this.isLibraryActionPending = false;
    }
  }

  private async loadReadingProgress(): Promise<void> {
    try {
      const history: ReadHistory | null = await DataManager.getInstance().getLatestReadHistory(this.getSyntheticMangaId(), 'default_user');
      if (history === null) {
        this.lastReadChapterId = '';
        this.lastReadChapterIndex = -1;
        this.lastReadPageIndex = 0;
        return;
      }

      const parsedChapter = RemoteLibraryMangaBridge.parseProviderChapterId(history.chapterId);
      this.lastReadChapterId = parsedChapter ? parsedChapter.rawChapterId : history.chapterId;
      this.lastReadPageIndex = history.pageIndex >= 0 ? history.pageIndex : 0;
      this.lastReadChapterIndex = -1;

      if (this.mangaDetail?.chapters) {
        for (let index = 0; index < this.mangaDetail.chapters.length; index++) {
          if (this.mangaDetail.chapters[index].id === this.lastReadChapterId) {
            this.lastReadChapterIndex = index;
            break;
          }
        }
      }
    } catch (error) {
      this.lastReadChapterId = '';
      this.lastReadChapterIndex = -1;
      this.lastReadPageIndex = 0;
      logger.error(TAG, `加载阅读进度失败: ${String(error)}`);
    }
  }

  private async loadMangaDetail(): Promise<void> {
    if (this.mangaId.length <= 0) {
      this.errorMessage = '漫画 ID 无效';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    this.pageContentOpacity = 0;

    try {
      await this.executor.initialize();
      this.imageHeaders = this.executor.getImageHeaders();
      this.mangaDetail = await this.executor.getDetail(this.mangaId) as SuwayomiDetailInfo | null;

      if (this.mangaDetail === null) {
        this.errorMessage = '无法加载漫画详情';
        return;
      }

      this.mangaTitle = this.mangaDetail.title;
      this.originalCoverUrl = String(this.mangaDetail.coverUrl || '').trim();
      this.displayCoverUrl = this.originalCoverUrl;
      this.isInRemoteLibrary = this.mangaDetail.inLibrary === true;
      this.ensureDetailCoverCached();

      await this.loadLocalLibraryState();
      await this.loadReadingProgress();
      if (this.lastReadChapterId.length <= 0) {
        this.findLastReadChapter();
      }
    } catch (error) {
      logger.error(TAG, `加载漫画详情失败: ${String(error)}`);
      this.errorMessage = `加载失败: ${String(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  private findLastReadChapter(): void {
    if (!this.mangaDetail?.chapters) {
      return;
    }

    let lastReadIndex = -1;
    for (let index = 0; index < this.mangaDetail.chapters.length; index++) {
      const chapter = this.mangaDetail.chapters[index];
      if (chapter.isRead === true) {
        lastReadIndex = index;
      }
    }

    if (lastReadIndex < 0) {
      return;
    }

    this.lastReadChapterIndex = lastReadIndex;
    this.lastReadChapterId = this.mangaDetail.chapters[lastReadIndex].id;
    const lastPageRead = this.getChapterLastPageRead(this.mangaDetail.chapters[lastReadIndex]);
    this.lastReadPageIndex = lastPageRead > 0 ? Math.max(0, lastPageRead - 1) : 0;
  }

  private getSortedChapters(): SuwayomiDetailChapterInfo[] {
    if (!this.mangaDetail?.chapters) {
      return [];
    }

    const chapters = this.mangaDetail.chapters.concat();
    if (this.sortDescending) {
      chapters.reverse();
    }
    return chapters;
  }

  private getDescriptionText(): string {
    if (this.mangaDetail?.description && this.mangaDetail.description.length > 0) {
      return this.mangaDetail.description;
    }
    return '暂无简介';
  }

  private getStatusLabel(): string {
    if (this.mangaDetail?.status && this.mangaDetail.status.length > 0) {
      return this.mangaDetail.status;
    }
    return '状态未标注';
  }

  private getHeaderMetaLine(): string {
    const segments: string[] = [];
    if (this.mangaDetail?.author && this.mangaDetail.author.length > 0) {
      segments.push(this.mangaDetail.author);
    }
    if (this.mangaDetail?.tags && this.mangaDetail.tags.length > 0) {
      segments.push(`${this.mangaDetail.tags.length} 个标签`);
    }
    return segments.length > 0 ? segments.join(' · ') : 'Suwayomi 远程漫画';
  }

  private isChapterRead(chapterId: string): boolean {
    if (!this.mangaDetail?.chapters) {
      return false;
    }
    const chapter = this.mangaDetail.chapters.find((item: SuwayomiDetailChapterInfo) => item.id === chapterId);
    if (chapter === undefined) {
      return false;
    }
    return chapter.isRead === true;
  }

  private isChapterDownloaded(chapterId: string): boolean {
    if (!this.mangaDetail?.chapters) {
      return false;
    }
    const chapter = this.mangaDetail.chapters.find((item: SuwayomiDetailChapterInfo) => item.id === chapterId);
    if (chapter === undefined) {
      return false;
    }
    return chapter.isDownloaded === true;
  }

  private openChapter(chapter: SuwayomiDetailChapterInfo, index: number, pageIndex: number = 0): void {
    this.executor.warmPages(chapter.id);
    const readerParams: MangaReaderPageParams = {
      manga: this.mangaDetail !== null
        ? this.remoteLibraryBridge.buildSuwayomiMangaFromDetail(this.mangaDetail, this.mangaId)
        : undefined,
      mangaId: this.getSyntheticMangaId(),
      chapterId: RemoteLibraryMangaBridge.buildSuwayomiChapterId(chapter.id),
      pageIndex: pageIndex >= 0 ? pageIndex : 0,
      fromPage: 'SuwayomiMangaDetailPage',
      contentType: MangaReaderContentType.Suwayomi,
      readerTitle: this.mangaDetail?.title || ''
    };
    openMangaReaderInIsolatedAbility(this.getUIContext(), this.pathStack, readerParams, TAG);
  }

  private continueReading(): void {
    const chapters = this.getSortedChapters();
    if (chapters.length <= 0) {
      return;
    }

    if (this.lastReadChapterId.length > 0) {
      const chapterIndex = chapters.findIndex((chapter: SuwayomiDetailChapterInfo) => chapter.id === this.lastReadChapterId);
      if (chapterIndex >= 0) {
        this.openChapter(chapters[chapterIndex], chapterIndex, this.lastReadPageIndex);
        return;
      }
    }

    this.openChapter(chapters[0], 0);
  }

  private toggleDescriptionExpanded(): void {
    this.descriptionExpanded = !this.descriptionExpanded;
  }

  private getSortSymbol(): Resource {
    return this.sortDescending ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_up');
  }

  private getDescriptionToggleSymbol(): Resource {
    return this.descriptionExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down');
  }

  private getLibraryActionSymbol(): Resource {
    return this.isInLocalLibrary ? $r('sys.symbol.minus_circle_fill') : $r('sys.symbol.plus_square');
  }

  private getContinueActionTitle(): string {
    return this.lastReadChapterId.length > 0 ? '继续阅读' : '开始阅读';
  }

  private getContinueActionDescription(): string {
    const chapters = this.getSortedChapters();
    if (this.lastReadChapterId.length > 0) {
      const targetChapter = chapters.find((chapter: SuwayomiDetailChapterInfo) => chapter.id === this.lastReadChapterId);
      if (targetChapter !== undefined) {
        return `${targetChapter.title} · 第 ${this.lastReadPageIndex + 1} 页`;
      }
    }
    if (chapters.length > 0) {
      return `共 ${chapters.length} 章内容`;
    }
    return '当前暂无可阅读章节';
  }

  private getLibraryActionTitle(): string {
    return this.isInLocalLibrary ? '移出书架' : '加入书架';
  }

  private getLibraryActionDescription(): string {
    if (this.isInLocalLibrary) {
      return '保留远程条目，仅从本地书架移除';
    }
    return '保存到本地书架，便于稍后继续阅读';
  }

  private getDisplayTags(): string[] {
    const merged: string[] = [];
    const append = (tag: string): void => {
      const normalized: string = String(tag || '').trim();
      if (normalized.length > 0 && !merged.includes(normalized)) {
        merged.push(normalized);
      }
    };

    append('Suwayomi');
    append(this.getStatusLabel());
    if (this.isInLocalLibrary) {
      append('已加入书架');
    }
    if (this.isInRemoteLibrary) {
      append('服务器书库');
    }
    if (this.mangaDetail !== null && this.mangaDetail.tags !== undefined) {
      for (let index: number = 0; index < this.mangaDetail.tags.length; index++) {
        append(this.mangaDetail.tags[index]);
      }
    }
    return merged;
  }

  private getReadingProgressLabel(): string {
    if (this.lastReadChapterIndex >= 0) {
      return `第 ${this.lastReadChapterIndex + 1} 章 · 第 ${this.lastReadPageIndex + 1} 页`;
    }
    return '尚未开始阅读';
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
  private buildStatusChip(text: string, highlighted: boolean = false) {
    Text(text)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(highlighted ? Color.White : this.color('text_primary'))
      .fontFamily(this.appFontFamily)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(highlighted ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(999)
  }

  @Builder
  private buildSectionHeader(symbol: Resource, title: string, subtitle: string = '') {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor([this.color('icon_primary')])
      }
      .width(36)
      .height(36)
      .backgroundColor(this.color('comp_background_tertiary'))
      .borderRadius(14)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.color('text_primary'))
          .fontFamily(this.appFontFamily)

        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor(this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildIconActionButton(
    symbol: Resource,
    action: () => void,
    highlighted: boolean = false,
    enabled: boolean = true
  ) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Stack() {
        SymbolGlyph(symbol)
          .fontSize(18)
          .fontColor([highlighted ? Color.White : this.color('text_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor(highlighted ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(999)
      .clip(true)
      .border({
        width: 1,
        color: highlighted ? 'rgba(255,255,255,0.08)' : this.color('panel_border')
      })
    }
    .width(40)
    .height(40)
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.42)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(999)
    .clip(true)
    .onClick(() => action())
  }

  @Builder
  private buildMetaChip(symbol: Resource, label: string) {
    Row({ space: 6 }) {
      SymbolGlyph(symbol)
        .fontSize(14)
        .fontColor([this.color('text_muted')])
      Text(label)
        .fontSize(12)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(999)
    .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private buildActionButton(
    symbol: Resource,
    title: string,
    description: string,
    emphasized: boolean,
    enabled: boolean,
    action: () => void
  ) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 12 }) {
        Stack() {
          SymbolGlyph(symbol)
            .fontSize(20)
            .fontColor([emphasized ? Color.White : this.color('icon_primary')])
        }
        .width(42)
        .height(42)
        .backgroundColor(emphasized ? 'rgba(255,255,255,0.16)' : this.color('panel_background'))
        .borderRadius(16)

        Column({ space: 3 }) {
          Text(title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(emphasized ? Color.White : this.color('text_primary'))
            .fontFamily(this.appFontFamily)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(description)
            .fontSize(11)
            .fontColor(emphasized ? 'rgba(255,255,255,0.82)' : this.color('text_muted'))
            .fontFamily(this.appFontFamily)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(emphasized ? this.color('accent_blue') : this.color('comp_background_tertiary'))
      .borderRadius(20)
      .clip(true)
      .border({
        width: 1,
        color: emphasized ? 'rgba(255,255,255,0.08)' : this.color('panel_border')
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .enabled(enabled)
    .opacity(enabled ? 1 : 0.42)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .borderRadius(20)
    .clip(true)
    .onClick(() => action())
  }

  @Builder
  private buildInfoCard(symbol: Resource, title: string, value: string) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        SymbolGlyph(symbol)
          .fontSize(15)
          .fontColor([this.color('icon_primary')])
        Text(title)
          .fontSize(11)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.color('text_primary'))
        .fontFamily(this.appFontFamily)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48%')
    .padding(16)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(18)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 2
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHeroSection() {
    Row({ space: 18 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.displayCoverUrl.length > 0) {
          SuwayomiImage({
            src: this.getDisplayCoverUrl(),
            imageWidth: 136,
            imageHeight: 196,
            objectFit: ImageFit.Cover,
            imgBorderRadius: 18
          })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.text_book_closed'))
              .fontSize(48)
              .fontColor([this.color('icon_primary')])
          }
          .width(136)
          .height(196)
          .backgroundColor(this.color('comp_background_tertiary'))
          .borderRadius(18)
          .justifyContent(FlexAlign.Center)
        }

        Text('Suwayomi')
          .fontSize(11)
          .fontColor(Color.White)
          .fontFamily(this.appFontFamily)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(0, 0, 0, 0.56)')
          .borderRadius(999)
          .margin({ top: 10, right: 10 })
      }

      Column({ space: 10 }) {
        Text(this.mangaDetail !== null ? this.mangaDetail.title : this.mangaTitle)
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

        Flex({ wrap: FlexWrap.Wrap }) {
          this.buildMetaChip($r('sys.symbol.book'), `${this.mangaDetail?.chapters?.length || 0} 章内容`)
          if (this.isInRemoteLibrary) {
            this.buildMetaChip($r('sys.symbol.bookshelf'), '服务端已收藏')
          }
        }
        .width('100%')

        Column({ space: 10 }) {
          this.buildActionButton(
            $r('sys.symbol.book'),
            this.getContinueActionTitle(),
            this.getContinueActionDescription(),
            true,
            this.getSortedChapters().length > 0,
            () => this.continueReading()
          )

          this.buildActionButton(
            this.getLibraryActionSymbol(),
            this.getLibraryActionTitle(),
            this.getLibraryActionDescription(),
            false,
            !this.isLibraryActionPending,
            () => {
              void this.toggleLocalLibrary();
            }
          )
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(28)
    .clip(true)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private buildOverviewSection() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        this.buildSectionHeader($r('sys.symbol.book'), '概览', '统一展示章节、进度和书架状态')
        Blank().layoutWeight(1)
        this.buildIconActionButton(
          $r('sys.symbol.arrow_right'),
          () => this.continueReading(),
          true,
          this.getSortedChapters().length > 0
        )
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildInfoCard($r('sys.symbol.book_pages'), '章节数', `${this.getSortedChapters().length} 章`)
        this.buildInfoCard($r('sys.symbol.clock'), '阅读进度', this.getReadingProgressLabel())
        this.buildInfoCard($r('sys.symbol.book'), '本地书架', this.isInLocalLibrary ? '已加入' : '未加入')
        this.buildInfoCard($r('sys.symbol.bookshelf'), '服务端书库', this.isInRemoteLibrary ? '已收藏' : '未收藏')
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(24)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private buildDescriptionSection() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        this.buildSectionHeader($r('sys.symbol.doc_text'), '简介')

        if (this.getDescriptionText().length > 36) {
          Blank().layoutWeight(1)
          this.buildIconActionButton(this.getDescriptionToggleSymbol(), () => this.toggleDescriptionExpanded())
        }
      }
      .width('100%')

      Text(this.getDescriptionText())
        .fontSize(13)
        .lineHeight(22)
        .fontColor(this.color('text_muted'))
        .fontFamily(this.appFontFamily)
        .maxLines(this.descriptionExpanded ? 99 : 6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(24)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTagsSection() {
    Column({ space: 14 }) {
      this.buildSectionHeader($r('sys.symbol.bookmark'), '标签', '用于快速理解漫画主题与来源信息')

      if (this.getDisplayTags().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.getDisplayTags(), (tag: string) => {
            this.buildBadge(tag)
          }, (tag: string) => tag)
        }
      } else {
        Text('当前漫画暂无标签')
          .fontSize(12)
          .fontColor(this.color('text_muted'))
          .fontFamily(this.appFontFamily)
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(24)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildChapterSection() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        this.buildSectionHeader($r('sys.symbol.list_bullet'), '章节列表', `共 ${this.getSortedChapters().length} 章`)
        Blank().layoutWeight(1)
        this.buildIconActionButton(this.getSortSymbol(), () => {
          this.sortDescending = !this.sortDescending;
        })
      }
      .width('100%')

      List() {
        ForEach(this.getSortedChapters(), (chapter: SuwayomiDetailChapterInfo, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              Column() {
                Text(`${index + 1}`)
                  .fontSize(12)
                  .fontWeight(this.isChapterRead(chapter.id) ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.isChapterRead(chapter.id) ? this.color('accent_blue') : this.color('text_muted'))
                  .fontFamily(this.appFontFamily)
              }
              .width(36)
              .height(36)
              .borderRadius(18)
              .backgroundColor(this.isChapterRead(chapter.id)
                ? 'rgba(78, 148, 255, 0.18)'
                : this.color('comp_background_tertiary'))
              .justifyContent(FlexAlign.Center)

              Column({ space: 4 }) {
                Text(chapter.title)
                  .fontSize(14)
                  .fontWeight(this.isChapterRead(chapter.id) ? FontWeight.Normal : FontWeight.Medium)
                  .fontColor(this.isChapterRead(chapter.id) ? this.color('text_muted') : this.color('text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.appFontFamily)

                Row({ space: 8 }) {
                  if (this.getChapterPageCount(chapter) > 0) {
                    Text(`${this.getChapterPageCount(chapter)} 页`)
                      .fontSize(10)
                      .fontColor(this.color('text_muted'))
                      .fontFamily(this.appFontFamily)
                  }

                  if (this.getChapterLastPageRead(chapter) > 0 && !this.isChapterRead(chapter.id)) {
                    Text(`已读 ${this.getChapterLastPageRead(chapter)}/${this.getChapterPageCount(chapter)}`)
                      .fontSize(10)
                      .fontColor(this.color('accent_blue'))
                      .fontFamily(this.appFontFamily)
                  }

                  if (this.isChapterDownloaded(chapter.id)) {
                    Row({ space: 4 }) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                        .fontSize(10)
                        .fontColor([this.color('accent_green')])
                      Text('已缓存')
                        .fontSize(10)
                        .fontColor(this.color('accent_green'))
                        .fontFamily(this.appFontFamily)
                    }
                  }
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (this.isChapterRead(chapter.id)) {
                this.buildStatusChip('已读', true)
              } else if (chapter.id === this.lastReadChapterId) {
                this.buildStatusChip('阅读中', true)
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.color('comp_background_tertiary'))
            .borderRadius(18)
            .border({ width: 1, color: this.color('panel_border') })
            .onClick(() => this.openChapter(chapter, index))
          }
        }, (chapter: SuwayomiDetailChapterInfo) => chapter.id)
      }
      .width('100%')
      .height(380)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0, color: Color.Transparent })
    }
    .width('100%')
    .padding(20)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .borderRadius(24)
    .border({ width: 1, color: this.color('panel_border') })
    .shadow({
      radius: this.themeManager.getGlassRadius(),
      color: this.themeManager.getGlassShadowColor(),
      offsetX: 0,
      offsetY: 4
    })
  }

  @Builder
  private buildLoadingState() {
    Column({ space: 14 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text('正在同步 Suwayomi 详情…')
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
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(18)
        .onClick(() => {
          void this.loadMangaDetail();
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

        if (this.getDisplayCoverUrl().length > 0) {
          SuwayomiImage({
            src: this.getDisplayCoverUrl(),
            imageWidth: '100%',
            imageHeight: HERO_HEIGHT,
            objectFit: ImageFit.Cover,
            imgBorderRadius: 0
          })
            .width('100%')
            .height(HERO_HEIGHT)
            .opacity(0.24)
            .blur(22)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        }

        Column()
          .width('100%')
          .height(HERO_HEIGHT + 120)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [
              ['rgba(0,0,0,0.06)', 0],
              ['rgba(0,0,0,0.22)', 0.28],
              [this.themeState.currentTheme === ThemeType.DARK ? '#1A1A1A' : '#F5F5F5', 0.78]
            ]
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

        if (this.isLoading) {
          this.buildLoadingState()
        } else if (this.errorMessage.length > 0) {
          this.buildErrorState()
        } else if (this.mangaDetail !== null) {
          Scroll() {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
              this.buildHeroSection()
              this.buildOverviewSection()
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

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.mangaTitle.length > 0 ? this.mangaTitle : 'Suwayomi 详情',
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 1200,
          pathStack: this.pathStack,
          actions: this.getTitleBarActions(),
          maxDirectActions: 1
        })
      }
      .width('100%')
      .height('100%')
    }
    .title(this.mangaTitle.length > 0 ? this.mangaTitle : 'Suwayomi 详情')
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as SuwayomiMangaDetailParams | undefined;
      if (param !== null && param !== undefined) {
        this.mangaId = param.mangaId || '';
        this.mangaTitle = param.title || '';
      }
      void this.loadMangaDetail();
    })
    .onShown(() => {
      this.revealPageContent();
    })
    .backgroundColor(Color.Transparent)
  }
}
