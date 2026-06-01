import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { Manga } from '../Models/MangaModels';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { DataManager, FavoriteInfo, ReadHistory } from '../Framework/Data/DataManager';
import { ChapterInfo, ComicDetailInfo } from '../Framework/Source/SourceExecutor';
import { RemoteLibraryMangaBridge } from '../Framework/Source/RemoteLibraryMangaBridge';
import { getRemoteLibraryShelfManager, RemoteLibraryShelfManager } from '../Framework/Source/RemoteLibraryShelfManager';
import { getKomgaSourceExecutor, KomgaSourceExecutor } from '../Framework/Source/KomgaSourceExecutor';
import { KomgaContentType } from '../Framework/Source/KomgaModels';
import KomgaCacheManager from '../Framework/Source/KomgaCacheManager';
import { KomgaImage } from '../components/KomgaImage';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { MangaReaderContentType, MangaReaderPageParams } from './MangaReaderPage';
import { openMangaReaderInIsolatedAbility } from '../Framework/Reader/MangaReaderAbilityLauncher';


const TAG = 'KomgaMangaDetailPage';
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
  instanceId?: string;
  title?: string;
}

interface KomgaDetailInfo extends ComicDetailInfo {
  summary?: string;
  bookCount?: number;
  publisher?: string;
  language?: string;
  releaseDate?: string;
  pageCount?: number;
  instanceId?: string;
}

@Component
export struct KomgaMangaDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State pageContentOpacity: number = 0;
  @State itemId: string = '';
  @State instanceId: string = '';
  @State contentType: KomgaContentType = 'SERIES';

  @State pageTitle: string = '';
  @State detail: KomgaDetailInfo | null = null;
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State sortDescending: boolean = true;
  @State lastReadBookId: string = '';
  @State lastReadChapterIndex: number = -1;
  @State lastReadPageIndex: number = 0;
  @State descriptionExpanded: boolean = false;
  @State isInLocalLibrary: boolean = false;
  @State isLibraryActionPending: boolean = false;
  @State originalCoverUrl: string = '';
  @State displayCoverUrl: string = '';
  @State chapterLibraryIds: string[] = [];
  @State chapterLibraryPendingIds: string[] = [];

  private executor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private remoteLibraryBridge: RemoteLibraryMangaBridge = RemoteLibraryMangaBridge.getInstance();
  private remoteLibraryShelfManager: RemoteLibraryShelfManager = getRemoteLibraryShelfManager();
  private themeManager: ThemeManager = ThemeManager.getInstance();
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

  private getEffectiveInstanceId(): string {
    if (this.instanceId.length > 0) {
      return this.instanceId;
    }
    if (this.detail !== null && this.detail.instanceId !== undefined && this.detail.instanceId.length > 0) {
      return this.detail.instanceId;
    }
    return this.executor.getCurrentInstanceId();
  }

  private getImageHeaders(): Record<string, string> {
    return this.executor.getImageHeaders(this.getEffectiveInstanceId());
  }

  private getDetailCoverCacheKey(): string {
    return `${this.getEffectiveInstanceId()}_${this.contentType}_${this.itemId}_detail_cover`;
  }

  private getChapterCoverCacheKey(chapter: ChapterInfo): string {
    const instanceId = chapter.instanceId !== undefined && chapter.instanceId.length > 0
      ? chapter.instanceId
      : this.getEffectiveInstanceId();
    return `${instanceId}_${this.contentType}_${chapter.id}_chapter_cover`;
  }

  private getChapterInstanceId(chapter: ChapterInfo): string {
    if (chapter.instanceId !== undefined && chapter.instanceId.length > 0) {
      return chapter.instanceId;
    }
    return this.getEffectiveInstanceId();
  }

  private getChapterSyntheticMangaId(chapter: ChapterInfo): string {
    return RemoteLibraryMangaBridge.buildKomgaMangaId(this.getChapterInstanceId(chapter), 'BOOKS', chapter.id);
  }

  private isChapterInLocalLibrary(chapter: ChapterInfo): boolean {
    return this.chapterLibraryIds.includes(this.getChapterSyntheticMangaId(chapter));
  }

  private isChapterLibraryActionPending(chapter: ChapterInfo): boolean {
    return this.chapterLibraryPendingIds.includes(this.getChapterSyntheticMangaId(chapter));
  }

  private setChapterLibraryPending(chapterMangaId: string, pending: boolean): void {
    if (pending) {
      if (!this.chapterLibraryPendingIds.includes(chapterMangaId)) {
        this.chapterLibraryPendingIds = this.chapterLibraryPendingIds.concat([chapterMangaId]);
      }
      return;
    }
    this.chapterLibraryPendingIds = this.chapterLibraryPendingIds.filter((item: string) => item !== chapterMangaId);
  }

  private setChapterLocalLibraryState(chapterMangaId: string, inLibrary: boolean): void {
    if (inLibrary) {
      if (!this.chapterLibraryIds.includes(chapterMangaId)) {
        this.chapterLibraryIds = this.chapterLibraryIds.concat([chapterMangaId]);
      }
      return;
    }
    this.chapterLibraryIds = this.chapterLibraryIds.filter((item: string) => item !== chapterMangaId);
  }

  private getChapterLibraryButtonLabel(chapter: ChapterInfo): string {
    if (this.isChapterLibraryActionPending(chapter)) {
      return '处理中';
    }
    return this.isChapterInLocalLibrary(chapter) ? '移出书架' : '加入书架';
  }

  private getSyntheticMangaId(): string {
    return RemoteLibraryMangaBridge.buildKomgaMangaId(this.getEffectiveInstanceId(), this.contentType, this.itemId);
  }

  private getDisplayCoverUrl(): string {
    const remoteCoverUrl = String(this.originalCoverUrl || '').trim();
    if (remoteCoverUrl.startsWith('http://') || remoteCoverUrl.startsWith('https://')) {
      return remoteCoverUrl;
    }
    const rawCoverPath = String(this.displayCoverUrl || '').trim();
    if (rawCoverPath.length <= 0) {
      return '';
    }
    if (rawCoverPath.startsWith('file://') || rawCoverPath.startsWith('http://') || rawCoverPath.startsWith('https://')) {
      return rawCoverPath;
    }
    return `file://${rawCoverPath}`;
  }

  private getPreferredLibraryCoverSource(): string {
    const currentCoverPath = String(this.displayCoverUrl || '').trim();
    const referenceCoverPath = this.originalCoverUrl.length > 0 ? this.originalCoverUrl : currentCoverPath;
    if (referenceCoverPath.startsWith('http://') || referenceCoverPath.startsWith('https://')) {
      const cachedCoverPath = KomgaCacheManager.getCachedCoverPath(this.getDetailCoverCacheKey(), referenceCoverPath);
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

    const cachedCoverPath = KomgaCacheManager.getCachedCoverPath(this.getDetailCoverCacheKey(), this.originalCoverUrl);
    if (cachedCoverPath !== null && cachedCoverPath.length > 0) {
      return;
    }

    const headers = this.getImageHeaders();
    void KomgaCacheManager.cacheCover(this.getDetailCoverCacheKey(), this.originalCoverUrl, headers).catch((error: Object | string | number | boolean) => {
      logger.debug(TAG, `Komga 详情封面预缓存失败: ${String(error)}`);
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
          void this.loadDetail(true);
        }
      }
    ];
  }

  private revealPageContent(): void {
    const uiContext = this.getUIContext();
    if (uiContext === undefined || uiContext === null) {
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

  private async loadLocalLibraryState(): Promise<void> {
    const syntheticMangaId = this.getSyntheticMangaId();
    this.isInLocalLibrary = await this.remoteLibraryShelfManager.isInLocalLibrary(syntheticMangaId);
    logger.info(TAG, `同步 Komga 当前条目书架状态: mangaId=${syntheticMangaId}, inLibrary=${this.isInLocalLibrary}`);

    if (!this.isInLocalLibrary) {
      return;
    }

    const cachedManga = await this.remoteLibraryBridge.getCachedMangaById(syntheticMangaId);
    if (cachedManga === null || this.detail === null) {
      return;
    }

    const cachedCoverPath = String(cachedManga.coverImagePath || '').trim();
    if (cachedCoverPath.length > 0 && !cachedCoverPath.startsWith('http://') && !cachedCoverPath.startsWith('https://')) {
      this.displayCoverUrl = cachedCoverPath;
    }
  }

  private async loadChapterLibraryState(): Promise<void> {
    if (this.detail === null || this.detail.chapters === undefined || this.detail.chapters.length <= 0) {
      this.chapterLibraryIds = [];
      return;
    }

    const favorites: FavoriteInfo[] = await DataManager.getInstance().getUserFavorites('default_user');
    const favoriteComicIds = new Set<string>();
    for (let index: number = 0; index < favorites.length; index++) {
      const comicId = String(favorites[index].comicId || '').trim();
      if (comicId.length > 0) {
        favoriteComicIds.add(comicId);
      }
    }

    const nextChapterLibraryIds: string[] = [];
    for (let index: number = 0; index < this.detail.chapters.length; index++) {
      const chapter = this.detail.chapters[index];
      const chapterMangaId = this.getChapterSyntheticMangaId(chapter);
      if (favoriteComicIds.has(chapterMangaId)) {
        nextChapterLibraryIds.push(chapterMangaId);
      }
    }

    this.chapterLibraryIds = nextChapterLibraryIds;
    logger.info(TAG, `同步 Komga 章节书架状态: itemId=${this.itemId}, total=${this.detail.chapters.length}, inLibrary=${nextChapterLibraryIds.length}`);
  }

  private getChapterPreferredLibraryCoverSource(chapter: ChapterInfo): string {
    const coverUrl = chapter.coverUrl !== undefined ? String(chapter.coverUrl).trim() : '';
    if (!coverUrl.startsWith('http://') && !coverUrl.startsWith('https://')) {
      return coverUrl;
    }

    const cachedCoverPath = KomgaCacheManager.getCachedCoverPath(this.getChapterCoverCacheKey(chapter), coverUrl);
    if (cachedCoverPath !== null && cachedCoverPath.length > 0) {
      return cachedCoverPath;
    }
    return coverUrl;
  }

  private async buildChapterMangaForLibrary(chapter: ChapterInfo): Promise<Manga | null> {
    const instanceId = this.getChapterInstanceId(chapter);
    let bookDetail: KomgaDetailInfo | null = null;

    if (this.contentType === 'BOOKS' && this.detail !== null && this.itemId === chapter.id && this.getEffectiveInstanceId() === instanceId) {
      bookDetail = this.detail;
    } else {
      bookDetail = await this.executor.getDetail(chapter.id, 'BOOKS', instanceId) as KomgaDetailInfo | null;
    }

    if (bookDetail === null) {
      logger.warn(TAG, `无法加载章节对应的 Komga BOOK 详情: chapterId=${chapter.id}, instanceId=${instanceId}`);
      return null;
    }

    const chapterManga = this.remoteLibraryBridge.buildKomgaMangaFromDetail(bookDetail, instanceId, 'BOOKS');
    const preferredCoverSource = this.getChapterPreferredLibraryCoverSource(chapter);
    if (preferredCoverSource.length > 0) {
      chapterManga.coverImagePath = preferredCoverSource;
    }
    return chapterManga;
  }

  private async toggleChapterLocalLibrary(chapter: ChapterInfo): Promise<void> {
    const chapterMangaId = this.getChapterSyntheticMangaId(chapter);
    if (this.isChapterLibraryActionPending(chapter)) {
      return;
    }

    const uiContext = this.getUIContext();
    if (uiContext === undefined || uiContext === null) {
      this.toast('无法获取页面上下文');
      return;
    }

    const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
    const filesDir = hostContext && typeof hostContext.filesDir === 'string' ? String(hostContext.filesDir) : '';
    if (filesDir.length <= 0) {
      this.toast('无法获取本地书库目录');
      return;
    }

    this.setChapterLibraryPending(chapterMangaId, true);
    try {
      if (this.isChapterInLocalLibrary(chapter)) {
        let targetManga = await this.remoteLibraryBridge.getCachedMangaById(chapterMangaId);
        if (targetManga === null) {
          targetManga = await this.buildChapterMangaForLibrary(chapter);
        }
        if (targetManga === null) {
          this.toast('当前章节信息不完整');
          return;
        }

        await this.remoteLibraryShelfManager.removeFromLocalLibrary(targetManga, filesDir);
        this.setChapterLocalLibraryState(chapterMangaId, false);
        logger.info(TAG, `Komga 章节已从本地书架移除: chapterId=${chapter.id}, mangaId=${chapterMangaId}`);
        this.toast('章节已从本地书架移除');
      } else {
        const chapterManga = await this.buildChapterMangaForLibrary(chapter);
        if (chapterManga === null) {
          this.toast('无法加入书架，请稍后重试');
          return;
        }

        await this.remoteLibraryShelfManager.addToLocalLibrary(chapterManga, filesDir);
        this.setChapterLocalLibraryState(chapterMangaId, true);
        logger.info(TAG, `Komga 章节已加入本地书架: chapterId=${chapter.id}, mangaId=${chapterMangaId}`);
        this.toast('章节已加入本地书架');
      }

      if (chapterMangaId === this.getSyntheticMangaId()) {
        if (!this.isChapterInLocalLibrary(chapter) && this.originalCoverUrl.length > 0) {
          this.displayCoverUrl = this.originalCoverUrl;
        }
        await this.loadLocalLibraryState();
      }
    } catch (error) {
      logger.error(TAG, `切换 Komga 章节本地书架状态失败: chapterId=${chapter.id}, error=${String(error)}`);
      this.toast('章节书架操作失败');
    } finally {
      this.setChapterLibraryPending(chapterMangaId, false);
    }
  }

  private buildCurrentMangaForLibrary(): Manga | undefined {
    if (this.detail === null || this.itemId.length <= 0) {
      return undefined;
    }
    const currentManga = this.remoteLibraryBridge.buildKomgaMangaFromDetail(
      this.detail,
      this.getEffectiveInstanceId(),
      this.contentType
    );
    const preferredCoverSource = this.getPreferredLibraryCoverSource();
    if (preferredCoverSource.length > 0) {
      currentManga.coverImagePath = preferredCoverSource;
    }
    return currentManga;
  }

  private async toggleLocalLibrary(): Promise<void> {
    if (this.isLibraryActionPending || this.detail === null || this.itemId.length <= 0) {
      return;
    }

    const currentManga = this.buildCurrentMangaForLibrary();
    if (currentManga === undefined) {
      this.toast('当前内容信息不完整');
      return;
    }

    const uiContext = this.getUIContext();
    if (uiContext === undefined || uiContext === null) {
      this.toast('无法获取页面上下文');
      return;
    }

    const hostContext = uiContext.getHostContext() as common.UIAbilityContext;
    const filesDir = hostContext && typeof hostContext.filesDir === 'string' ? String(hostContext.filesDir) : '';
    if (filesDir.length <= 0) {
      this.toast('无法获取本地书库目录');
      return;
    }

    this.isLibraryActionPending = true;
    logger.info(TAG, `切换 Komga 当前条目书架状态: mangaId=${this.getSyntheticMangaId()}, inLibrary=${this.isInLocalLibrary}`);
    try {
      if (this.isInLocalLibrary) {
        await this.remoteLibraryShelfManager.removeFromLocalLibrary(currentManga, filesDir);
        this.isInLocalLibrary = false;
        if (this.originalCoverUrl.length > 0) {
          this.displayCoverUrl = this.originalCoverUrl;
        }
        logger.info(TAG, `Komga 当前条目已从本地书架移除: mangaId=${currentManga.id}`);
        this.toast('已从本地书架移除');
      } else {
        const updatedManga = await this.remoteLibraryShelfManager.addToLocalLibrary(currentManga, filesDir);
        this.isInLocalLibrary = true;
        if (updatedManga.coverImagePath.length > 0) {
          this.displayCoverUrl = updatedManga.coverImagePath;
        }
        logger.info(TAG, `Komga 当前条目已加入本地书架: mangaId=${updatedManga.id}`);
        this.toast('已加入本地书架');
      }
    } catch (error) {
      logger.error(TAG, `切换本地书架状态失败: ${String(error)}`);
      this.toast('书架操作失败');
    } finally {
      this.isLibraryActionPending = false;
    }
  }

  private async loadReadingProgress(): Promise<void> {
    try {
      const syntheticMangaId = RemoteLibraryMangaBridge.buildKomgaMangaId(this.getEffectiveInstanceId(), this.contentType, this.itemId);
      const history: ReadHistory | null = await DataManager.getInstance().getLatestReadHistory(syntheticMangaId, 'default_user');
      if (history === null) {
        this.lastReadBookId = '';
        this.lastReadChapterIndex = -1;
        this.lastReadPageIndex = 0;
        return;
      }

      const parsedChapter = RemoteLibraryMangaBridge.parseProviderChapterId(history.chapterId);
      this.lastReadBookId = parsedChapter ? parsedChapter.rawChapterId : history.chapterId;
      this.lastReadPageIndex = history.pageIndex >= 0 ? history.pageIndex : 0;
      this.lastReadChapterIndex = -1;

      if (this.detail?.chapters) {
        for (let index: number = 0; index < this.detail.chapters.length; index++) {
          if (this.detail.chapters[index].id === this.lastReadBookId) {
            this.lastReadChapterIndex = index;
            break;
          }
        }
      }

      logger.info(TAG, `读取统一 Komga 阅读进度: bookId=${this.lastReadBookId}, pageIndex=${this.lastReadPageIndex}`);
    } catch (error) {
      logger.warn(TAG, `读取 Komga 阅读进度失败: ${String(error)}`);
      this.lastReadBookId = '';
      this.lastReadChapterIndex = -1;
      this.lastReadPageIndex = 0;
    }
  }
  private async loadDetail(forceRefresh: boolean = false): Promise<void> {
    if (this.itemId.length <= 0) {
      this.errorMessage = '无效的 Komga 条目';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    logger.info(TAG, `开始加载 Komga 详情: itemId=${this.itemId}, contentType=${this.contentType}, instanceId=${this.instanceId || this.getEffectiveInstanceId()}, forceRefresh=${forceRefresh}`);
    try {
      await this.executor.initialize(forceRefresh);
      this.detail = await this.executor.getDetail(this.itemId, this.contentType, this.instanceId, forceRefresh) as KomgaDetailInfo | null;
      if (this.detail !== null) {
        if (this.detail.instanceId !== undefined && this.detail.instanceId.length > 0) {
          this.instanceId = this.detail.instanceId;
        }
        this.pageTitle = this.detail.title;
        this.originalCoverUrl = String(this.detail.coverUrl || '').trim();
        this.displayCoverUrl = this.originalCoverUrl;
        this.ensureDetailCoverCached();
        await this.loadLocalLibraryState();
        await this.loadChapterLibraryState();
        logger.info(TAG, `Komga 详情加载完成: itemId=${this.itemId}, chapters=${this.detail.chapters ? this.detail.chapters.length : 0}, inLibrary=${this.isInLocalLibrary}`);
      } else {
        this.errorMessage = '未能获取详情数据';
        this.chapterLibraryIds = [];
        logger.warn(TAG, `Komga 详情为空: itemId=${this.itemId}, contentType=${this.contentType}`);
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
    const summary: string = this.detail?.summary ? this.detail.summary : '';
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
    const bookCount: number = this.detail?.bookCount !== undefined ? this.detail.bookCount : 0;
    return bookCount > 0 ? bookCount : 0;
  }

  private getPageCountLabel(): string {
    const pageCount: number = this.detail?.pageCount !== undefined ? this.detail.pageCount : 0;
    return pageCount > 0 ? `${pageCount} 页` : '未记录页数';
  }

  private getPublisherLabel(): string {
    const publisher: string = this.detail?.publisher ? this.detail.publisher : '';
    return publisher.length > 0 ? publisher : '未记录出版社';
  }

  private getLanguageLabel(): string {
    const language: string = this.detail?.language ? this.detail.language : '';
    return language.length > 0 ? language : '语言未标注';
  }

  private getReleaseDateLabel(): string {
    const releaseDate: string = this.detail?.releaseDate ? this.detail.releaseDate : '';
    return releaseDate.length > 0 ? releaseDate : '未记录时间';
  }

  private getHeaderMetaLine(): string {
    const segments: string[] = [];
    if (this.detail !== null && this.detail.author !== undefined && this.detail.author.length > 0) {
      segments.push(this.detail.author);
    }
    const publisher: string = this.detail?.publisher ? this.detail.publisher : '';
    if (publisher.length > 0) {
      segments.push(publisher);
    }
    const language: string = this.detail?.language ? this.detail.language : '';
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



  private openChapter(chapter: ChapterInfo, pageIndex: number = 0): void {
    const instanceId = chapter.instanceId !== undefined && chapter.instanceId.length > 0
      ? chapter.instanceId
      : this.getEffectiveInstanceId();
    const readerParams: MangaReaderPageParams = {
      manga: this.detail !== null
        ? this.remoteLibraryBridge.buildKomgaMangaFromDetail(this.detail, instanceId, this.contentType)
        : undefined,
      mangaId: RemoteLibraryMangaBridge.buildKomgaMangaId(instanceId, this.contentType, this.itemId),
      chapterId: RemoteLibraryMangaBridge.buildKomgaChapterId(instanceId, chapter.id),
      pageIndex: pageIndex >= 0 ? pageIndex : 0,
      fromPage: 'KomgaMangaDetailPage',
      contentType: MangaReaderContentType.Komga,
      readerTitle: this.detail?.title || ''
    };
    openMangaReaderInIsolatedAbility(this.getUIContext(), this.pathStack, readerParams, TAG);
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
          this.openChapter(chapters[index], this.lastReadPageIndex);
          return;
        }
      }
    }

    this.openChapter(chapters[0]);
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

  private getChapterLibraryActionSymbol(chapter: ChapterInfo): Resource {
    return this.isChapterInLocalLibrary(chapter) ? $r('sys.symbol.minus_circle_fill') : $r('sys.symbol.plus_square');
  }

  private getContinueActionTitle(): string {
    return this.lastReadBookId.length > 0 ? '继续阅读' : '开始阅读';
  }

  private getLibraryActionTitle(): string {
    return this.isInLocalLibrary ? '移出书架' : '加入书架';
  }

  private getLibraryActionDescription(): string {
    if (this.isInLocalLibrary) {
      return '保留远程条目，仅从本地书架移除';
    }
    return '保存到本地书架，便于后续继续阅读';
  }

  private getDisplayTags(): string[] {
    const merged: string[] = [];
    const append = (tag: string): void => {
      const normalized = String(tag || '').trim();
      if (normalized.length > 0 && !merged.includes(normalized)) {
        merged.push(normalized);
      }
    };

    append('Komga');
    append(this.getContentTypeLabel());
    append(this.getStatusLabel());
    if (this.isInLocalLibrary) {
      append('已加入书架');
    }

    const sourceTags = this.getTags();
    for (let index = 0; index < sourceTags.length; index++) {
      append(sourceTags[index]);
    }
    return merged;
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
        KomgaImage({
          src: this.getDisplayCoverUrl(),
          imageWidth: 136,
          imageHeight: 196,
          objectFit: ImageFit.Cover,
          imgBorderRadius: 18,
          requestHeaders: this.getImageHeaders(),
          cacheKey: this.getDetailCoverCacheKey()
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

        Flex({ wrap: FlexWrap.Wrap }) {
          this.buildMetaChip($r('sys.symbol.rectangle_stack'), `${this.getChapterCount()} 条内容`)
          this.buildMetaChip($r('sys.symbol.book'), this.getPageCountLabel())
        }
        .width('100%')

        Column({ space: 10 }) {
          this.buildActionButton(
            $r('sys.symbol.book'),
            this.getContinueActionTitle(),
            this.getContinueDescription(),
            true,
            this.getChapterCount() > 0,
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
  private buildContinueSection() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        this.buildSectionHeader($r('sys.symbol.book'), '概览', '快速查看当前条目的核心信息')
        Blank().layoutWeight(1)
        this.buildIconActionButton(
          $r('sys.symbol.arrow_right'),
          () => this.continueReading(),
          true,
          this.getChapterCount() > 0
        )
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        this.buildInfoCard($r('sys.symbol.books_vertical_fill'), '内容类型', this.getContentTypeLabel())
        this.buildInfoCard($r('sys.symbol.clock'), '发布时间', this.getReleaseDateLabel())
        this.buildInfoCard($r('sys.symbol.folder'), '出版社', this.getPublisherLabel())
        this.buildInfoCard($r('sys.symbol.book'), '语言', this.getLanguageLabel())
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
      this.buildSectionHeader($r('sys.symbol.bookmark'), '标签', '用于快速理解内容主题')

      if (this.getDisplayTags().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.getDisplayTags(), (tag: string) => {
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
  private buildChapterItem(chapter: ChapterInfo) {
    Row({ space: 14 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.BottomStart }) {
          KomgaImage({
            src: chapter.coverUrl || '',
            imageWidth: 72,
            imageHeight: 100,
            objectFit: ImageFit.Cover,
            imgBorderRadius: 16,
            requestHeaders: this.executor.getImageHeaders(chapter.instanceId),
            cacheKey: this.getChapterCoverCacheKey(chapter)
          })

          Text(this.getChapterBadgeText(chapter))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .fontFamily(this.appFontFamily)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.isLastReadChapter(chapter) ? this.color('accent_blue') : 'rgba(0, 0, 0, 0.45)')
            .borderRadius(999)
            .margin({ left: 8, bottom: 8 })
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
        .justifyContent(FlexAlign.Center)
      }
      .layoutWeight(1)
      .onClick(() => this.openChapter(chapter))

      Column({ space: 8 }) {
        if (this.isLastReadChapter(chapter)) {
          this.buildStatusChip('最近阅读', true)
        } else if (this.isChapterInLocalLibrary(chapter)) {
          this.buildStatusChip('已在书架', true)
        } else {
          this.buildStatusChip('阅读')
        }

        this.buildIconActionButton(
          this.getChapterLibraryActionSymbol(chapter),
          () => {
            void this.toggleChapterLocalLibrary(chapter);
          },
          this.isChapterInLocalLibrary(chapter),
          !this.isChapterLibraryActionPending(chapter)
        )
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.color('comp_background_tertiary'))
    .borderRadius(20)
    .border({ width: 1, color: this.color('panel_border') })
  }


  @Builder
  private buildChapterSection() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        this.buildSectionHeader($r('sys.symbol.list_bullet'), '章节列表', `共 ${this.getSortedChapters().length} 条内容`)
        Blank().layoutWeight(1)
        this.buildIconActionButton(this.getSortSymbol(), () => {
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
        .backgroundColor(this.color('comp_background_tertiary'))
        .borderRadius(18)
        .border({ width: 1, color: this.color('panel_border') })
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
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(18)
        .onClick(() => {
          void this.loadDetail(true);
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
          KomgaImage({
            src: this.getDisplayCoverUrl(),
            imageWidth: '100%',
            imageHeight: HERO_HEIGHT,
            objectFit: ImageFit.Cover,
            imgBorderRadius: 0,
            requestHeaders: this.getImageHeaders(),
            cacheKey: this.getDetailCoverCacheKey()
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
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
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

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.pageTitle.length > 0 ? this.pageTitle : 'Komga 详情',
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
    .title(this.pageTitle.length > 0 ? this.pageTitle : 'Komga 详情')
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: Object | undefined = context.pathInfo.param as Object | undefined;
      if (param !== null && param !== undefined) {
        const params: KomgaMangaDetailParams = param as KomgaMangaDetailParams;
        this.itemId = params.itemId;
        this.contentType = params.contentType;
        this.instanceId = params.instanceId || '';
        this.pageTitle = params.title || '';
      }
      void this.loadDetail();
    })
    .onShown(() => {
      this.revealPageContent();
    })
    .backgroundColor(Color.Transparent)
  }
}
