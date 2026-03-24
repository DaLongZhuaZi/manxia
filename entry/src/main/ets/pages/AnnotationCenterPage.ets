import { LengthMetrics, promptAction, UIContext } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { HdsNavDestination } from '@kit.UIDesignKit';
import fs from '@ohos.file.fs';
import { logger } from '../Utils/Logger';
import { GlobalBackgroundLayerMode } from '../Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { getUnifiedAnnotationManager, UnifiedAnnotationManager } from '../Framework/Annotations/UnifiedAnnotationManager';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';
import { DataManager } from '../Framework/Data/DataManager';
import { NovelDataManager } from '../Framework/Novel/NovelDataManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { buildNovelReaderParamsFromTxtEBook } from '../Framework/Adapters/LocalTextNovelAdapter';
import { UnifiedContentType } from '../Models/UnifiedContentModels';
import { UnifiedAnnotationRecord, UnifiedAnnotationType, HighlightLineType, AnnotationAnchor } from '../Models/AnnotationModels';
import { EBookFormat, EBookReadingProgress } from '../Models/EBookModels';
import { AppGuideOverlay, GuideHighlightRect } from '../Framework/Components/AppGuideOverlay';
import { ensureGuideAnchorVisibleInScroller, resolveGuideHighlightRectInRoot } from '../Framework/Components/AppGuideSupport';
import { AppGuideManager, AppGuidePageId, AppGuideStep } from '../Framework/Managers/AppGuideManager';

const TAG = 'AnnotationCenterPage';
const MAX_CONTENT_WIDTH: number = 960;

type AnnotationFilterType = 'all' | 'bookmark' | 'highlight' | 'thought';
type ShareFormatType = 'plain' | 'markdown';
type MangaReaderContentTypeValue = 'Local' | 'OnlineUndownloaded' | 'OnlineDownloaded';

export interface AnnotationCenterNovelReaderContext {
  sourceId?: string;
  bookUrl?: string;
  tocUrl?: string;
  sourceName?: string;
}

export interface AnnotationCenterMangaReaderContext {
  sourceId?: number;
  sourceName?: string;
  contentType?: MangaReaderContentTypeValue;
  chapterId?: string;
  pageIndex?: number;
}

export interface AnnotationCenterEBookReaderContext {
  chapterIndex?: number;
  pageIndex?: number;
  startOffset?: number;
}

export interface AnnotationCenterReaderContext {
  novel?: AnnotationCenterNovelReaderContext;
  manga?: AnnotationCenterMangaReaderContext;
  ebook?: AnnotationCenterEBookReaderContext;
}

export interface AnnotationCenterPageParams {
  contentType?: UnifiedContentType;
  contentId?: string;
  contentTitle?: string;
  readerContext?: AnnotationCenterReaderContext;
}

interface HighlightStylePreview {
  lineType?: string;
  color?: string;
}

interface NovelReaderRouteParams {
  sourceId: string;
  bookUrl: string;
  bookName: string;
  chapterUrl: string;
  chapterTitle: string;
  chapterIndex: number;
  totalChapters: number;
  chapterPageIndex?: number;
  chapterStartOffset?: number;
  tocUrl?: string;
  coverUrl?: string;
  sourceName?: string;
  localEbookId?: string;
}

interface MangaReaderRouteParams {
  mangaId: string;
  sourceId?: number;
  sourceName?: string;
  contentType: MangaReaderContentTypeValue;
  chapterId?: string;
  pageIndex?: number;
  fromPage?: string;
}

interface EBookReaderRouteParams {
  bookId: string;
}

interface InspirationContentSummary {
  key: string;
  contentType: UnifiedContentType;
  contentId: string;
  title: string;
  coverUri: string;
  totalCount: number;
  bookmarkCount: number;
  highlightCount: number;
  thoughtCount: number;
}

interface InspirationContentDisplayInfo {
  title: string;
  coverUri: string;
}

interface ContentKeyParts {
  contentType: UnifiedContentType;
  contentId: string;
}

@Component
export struct AnnotationCenterPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  @State contentType: UnifiedContentType = UnifiedContentType.NOVEL;
  @State contentId: string = '';
  @State contentTitle: string = '灵感';

  @State filterType: AnnotationFilterType = 'all';
  @State isLoading: boolean = true;
  @State allRecords: UnifiedAnnotationRecord[] = [];
  @State records: UnifiedAnnotationRecord[] = [];
  @State visibleRecords: UnifiedAnnotationRecord[] = [];
  @State selectedRecordIds: string[] = [];
  @State contentSummaries: InspirationContentSummary[] = [];
  @State selectedContentKey: string = '';
  @State selectedContentName: string = '全部内容';
  @State selectedContentCoverUri: string = '';
  @State allContentChipSubtitle: string = '0 个内容';

  @State editingRecordId: string = '';
  @State editingTitleText: string = '';
  @State editingBodyText: string = '';
  @State savingEdit: boolean = false;

  @State pageEnterOpacity: number = 0;
  @State pageEnterOffsetY: number = 16;
  @State listOpacity: number = 1;
  @State listOffsetY: number = 0;
  @State private appGuideStep: AppGuideStep | null = null;
  @State private appGuideHighlightRect: GuideHighlightRect | null = null;

  @State showSharePreview: boolean = false;
  @State sharePreviewTitle: string = '';
  @State sharePreviewContent: string = '';
  @State sharePreviewFormat: ShareFormatType = 'plain';
  @State sharePreviewMaskOpacity: number = 0;
  @State sharePreviewPanelOpacity: number = 0;
  @State sharePreviewPanelScale: number = 0.96;

  private annotationManager: UnifiedAnnotationManager = getUnifiedAnnotationManager();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private dataManager: DataManager = DataManager.getInstance();
  private novelDataManager: NovelDataManager = NovelDataManager.getInstance();
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private uiContext: UIContext | null = null;
  private listAnimationToken: number = 0;
  private readerContext: AnnotationCenterReaderContext | null = null;
  private contentDisplayCache: Map<string, InspirationContentDisplayInfo> = new Map();
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;
  private hasCapturedDisplayMode: boolean = false;
  private hasRestoredDisplayMode: boolean = false;
  private hasEnsuredNormalMode: boolean = false;
  private appGuideManager: AppGuideManager = AppGuideManager.getInstance();
  private lastGuideAnchorId: string = '';

  onPageShow(): void {
    this.captureCurrentDisplayMode('onPageShow');
    this.ensureNormalDisplayMode('onPageShow');
    void this.refreshPageGuide('onPageShow');
  }

  private resolveGuideHighlightRect(anchorId?: string, borderRadius: number = 18): GuideHighlightRect | null {
    if (!anchorId || anchorId.length <= 0) {
      return null;
    }
    try {
      return resolveGuideHighlightRectInRoot(this.getUIContext(), anchorId, borderRadius, 'guide_inspiration_root');
    } catch (error) {
      logger.warn(TAG, `获取灵感引导锚点失败: ${String(error)}`);
      return null;
    }
  }

  private adjustGuideHighlightRect(anchorId: string | undefined, rect: GuideHighlightRect | null): GuideHighlightRect | null {
    if (!rect || !anchorId) {
      return rect;
    }
    let yOffset = this.statusBarHeight > 0 ? this.statusBarHeight : 24;
    if (anchorId === 'guide_inspiration_filters' ||
      anchorId === 'guide_inspiration_actions' ||
      anchorId === 'guide_inspiration_record_list') {
      yOffset += 12;
    }
    return {
      x: rect.x,
      y: rect.y + yOffset,
      width: rect.width,
      height: rect.height,
      borderRadius: rect.borderRadius
    };
  }

  private async refreshPageGuide(trigger: string): Promise<void> {
    await this.appGuideManager.initialize();
    if (!this.appGuideManager.getCurrentStep()) {
      await this.appGuideManager.tryAutoStartFlowByPage(AppGuidePageId.INSPIRATION);
    }
    const step = this.appGuideManager.getCurrentStep();
    if (!step || step.pageId !== AppGuidePageId.INSPIRATION) {
      this.appGuideStep = null;
      this.appGuideHighlightRect = null;
      this.lastGuideAnchorId = '';
      return;
    }
    if (this.alignGuideViewport(step) && !trigger.endsWith('_after_scroll')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_after_scroll`);
      }, 220);
      return;
    }
    this.appGuideStep = step;
    this.appGuideHighlightRect = this.adjustGuideHighlightRect(
      step.anchorId,
      this.resolveGuideHighlightRect(step.anchorId, step.borderRadius ?? 18)
    );
    if (!this.appGuideHighlightRect && !trigger.endsWith('_retry_layout')) {
      setTimeout(() => {
        void this.refreshPageGuide(`${trigger}_retry_layout`);
      }, 120);
    }
    logger.debug(TAG, `灵感引导已刷新: trigger=${trigger}, step=${step.id}`);
  }

  private alignGuideViewport(step: AppGuideStep): boolean {
    const anchorId = step.anchorId ?? '';
    if (anchorId.length <= 0) {
      return false;
    }
    const scrollResult = ensureGuideAnchorVisibleInScroller(
      this.getUIContext(),
      this.scroller,
      anchorId,
      'guide_inspiration_scroll'
    );
    if (!scrollResult.available) {
      return false;
    }
    this.lastGuideAnchorId = anchorId;
    return scrollResult.scrolled;
  }

  private handlePageGuideNext(): void {
    void this.appGuideManager.nextStep().then(() => {
      void this.refreshPageGuide('next');
    });
  }

  private handlePageGuideSkip(): void {
    void this.appGuideManager.skipCurrentFlow().then(() => {
      void this.refreshPageGuide('skip');
    });
  }

  private captureCurrentDisplayMode(trigger: string): void {
    if (this.hasCapturedDisplayMode) {
      return;
    }
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    this.hasCapturedDisplayMode = true;
    logger.info(TAG, `记录进入灵感页前的显示模式: trigger=${trigger}, mode=${this.previousDisplayMode}`);
  }

  private ensureNormalDisplayMode(trigger: string): void {
    if (this.hasEnsuredNormalMode) {
      return;
    }
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      if (!this.uiContext) {
        return;
      }
      PageWindowCoordinator.applyPagePolicy('AnnotationCenterPage', this.uiContext);
      this.hasEnsuredNormalMode = true;
      logger.info(TAG, `已切换为非沉浸式显示: trigger=${trigger}，确保灵感页标题栏与状态栏避让正常`);
    } catch (error) {
      logger.warn(TAG, `切换灵感页显示模式失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private restorePreviousDisplayMode(trigger: string): void {
    if (this.hasRestoredDisplayMode) {
      return;
    }
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      if (!this.uiContext) {
        return;
      }
      PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.uiContext);
      this.hasRestoredDisplayMode = true;
      logger.info(TAG, `离开灵感页，恢复显示模式: trigger=${trigger}, mode=${this.previousDisplayMode}`);
    } catch (error) {
      logger.warn(TAG, `恢复离开灵感页显示模式失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private isReturningToReader(): boolean {
    return !!(this.readerContext?.novel || this.readerContext?.manga || this.readerContext?.ebook);
  }

  private forceReaderImmersiveModeBeforeExit(trigger: string): void {
    try {
      if (!this.uiContext) {
        this.uiContext = this.getUIContext();
      }
      const context = this.uiContext ?? undefined;
      // 避免与灵感页进入时的默认模式异步调用竞争，返回阅读器后追加两次短延迟兜底。
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
      setTimeout(() => {
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
      }, 80);
      setTimeout(() => {
        WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, context);
      }, 180);
      this.hasRestoredDisplayMode = true;
      logger.info(TAG, `返回阅读器前强制恢复全沉浸: trigger=${trigger}`);
    } catch (error) {
      logger.warn(TAG, `返回阅读器前恢复全沉浸失败: trigger=${trigger}, error=${String(error)}`);
    }
  }

  private parsePageParams(context: NavDestinationContext): AnnotationCenterPageParams {
    const pathInfo = context.pathInfo;
    const fromPathInfo = pathInfo ? pathInfo.param as AnnotationCenterPageParams : null;
    if (fromPathInfo) {
      return fromPathInfo;
    }

    const fromStack = context.pathStack.getParamByName('AnnotationCenterPage') as AnnotationCenterPageParams[];
    if (fromStack && fromStack.length > 0) {
      const latest = fromStack[fromStack.length - 1];
      if (latest) {
        return latest;
      }
    }
    return {};
  }

  private buildContentKey(contentType: UnifiedContentType, contentId: string): string {
    return `${contentType}@@${encodeURIComponent(contentId)}`;
  }

  private parseContentKey(key: string): ContentKeyParts | null {
    if (!key || key.trim().length <= 0) {
      return null;
    }
    const delimiterIndex = key.indexOf('@@');
    if (delimiterIndex <= 0) {
      return null;
    }
    const contentTypeRaw = key.substring(0, delimiterIndex);
    const contentIdRaw = key.substring(delimiterIndex + 2);
    if (!contentIdRaw || contentIdRaw.trim().length <= 0) {
      return null;
    }
    let contentType: UnifiedContentType;
    if (contentTypeRaw === UnifiedContentType.NOVEL) {
      contentType = UnifiedContentType.NOVEL;
    } else if (contentTypeRaw === UnifiedContentType.MANGA) {
      contentType = UnifiedContentType.MANGA;
    } else if (contentTypeRaw === UnifiedContentType.EBOOK) {
      contentType = UnifiedContentType.EBOOK;
    } else {
      return null;
    }
    return {
      contentType,
      contentId: decodeURIComponent(contentIdRaw)
    };
  }

  private getCurrentSelectionTypeLabel(): string {
    if (this.selectedContentKey.length <= 0) {
      return '全部内容';
    }
    return this.getContentTypeLabel(this.contentType);
  }

  private getContentSummaryByKey(key: string): InspirationContentSummary | null {
    for (let i = 0; i < this.contentSummaries.length; i++) {
      if (this.contentSummaries[i].key === key) {
        return this.contentSummaries[i];
      }
    }
    return null;
  }

  private getOptionalStringField(target: object | null | undefined, fieldName: string): string {
    if (!target) {
      return '';
    }
    const rawValue = Reflect.get(target, fieldName) as string | number | boolean | null | undefined;
    if (typeof rawValue === 'string') {
      return rawValue.trim();
    }
    if (typeof rawValue === 'number' || typeof rawValue === 'boolean') {
      return String(rawValue);
    }
    return '';
  }

  private isNetworkUrl(url: string): boolean {
    if (!url || url.trim().length <= 0) {
      return false;
    }
    return url.startsWith('http://') || url.startsWith('https://');
  }

  private hasUriScheme(path: string): boolean {
    if (!path || path.trim().length <= 0) {
      return false;
    }
    return path.indexOf('://') > 0;
  }

  private normalizeContentCoverUri(rawCover: string, contentType: UnifiedContentType, contentId: string): string {
    const raw = rawCover ? rawCover.trim() : '';
    if (!raw) {
      logger.warn(TAG, `灵感内容封面为空: type=${contentType}, contentId=${contentId}`);
      return '';
    }
    if (raw.startsWith('app.media.') || raw.startsWith('$r(')) {
      logger.warn(TAG, `灵感内容封面为资源引用，跳过: type=${contentType}, contentId=${contentId}, raw=${raw}`);
      return '';
    }
    if (this.isNetworkUrl(raw) || raw.startsWith('data:') || raw.startsWith('resource://')) {
      return raw;
    }
    if (raw.startsWith('file://')) {
      const localPath = raw.substring('file://'.length);
      try {
        if (localPath.length > 0) {
          fs.accessSync(localPath);
        }
      } catch (error) {
        logger.warn(
          TAG,
          `灵感内容本地封面文件不存在或不可访问: type=${contentType}, contentId=${contentId}, path=${localPath}, error=${String(error)}`
        );
      }
      return raw;
    }
    if (this.hasUriScheme(raw)) {
      logger.warn(TAG, `灵感内容封面路径协议暂不支持，保持原值: type=${contentType}, contentId=${contentId}, raw=${raw}`);
      return raw;
    }
    try {
      fs.accessSync(raw);
    } catch (error) {
      logger.warn(
        TAG,
        `灵感内容本地封面文件不存在或不可访问: type=${contentType}, contentId=${contentId}, path=${raw}, error=${String(error)}`
      );
    }
    return `file://${raw}`;
  }

  private resolveMangaCoverRaw(mangaObject: object | null | undefined): string {
    if (!mangaObject) {
      return '';
    }
    const coverImagePath = this.getOptionalStringField(mangaObject, 'coverImagePath');
    if (coverImagePath.length > 0) {
      return coverImagePath;
    }
    const coverLocalPath = this.getOptionalStringField(mangaObject, 'coverLocalPath');
    if (coverLocalPath.length > 0) {
      return coverLocalPath;
    }
    return this.getOptionalStringField(mangaObject, 'coverUrl');
  }

  private resolveNovelCoverRaw(novelObject: object | null | undefined): string {
    if (!novelObject) {
      return '';
    }
    const coverLocalPath = this.getOptionalStringField(novelObject, 'coverLocalPath');
    if (coverLocalPath.length > 0) {
      return coverLocalPath;
    }
    return this.getOptionalStringField(novelObject, 'coverUrl');
  }

  private resolveEBookCoverRaw(ebookObject: object | null | undefined): string {
    if (!ebookObject) {
      return '';
    }
    const metadataObject = Reflect.get(ebookObject, 'metadata') as object | null | undefined;
    const coverImagePath = this.getOptionalStringField(metadataObject, 'coverImagePath');
    if (coverImagePath.length > 0) {
      return coverImagePath;
    }
    const fallbackPath = this.getOptionalStringField(ebookObject, 'coverImagePath');
    return fallbackPath;
  }

  private async resolveContentDisplayInfo(
    contentType: UnifiedContentType,
    contentId: string
  ): Promise<InspirationContentDisplayInfo> {
    const cacheKey = this.buildContentKey(contentType, contentId);
    const cached = this.contentDisplayCache.get(cacheKey);
    if (cached) {
      return cached;
    }
    const fallback: InspirationContentDisplayInfo = { title: '', coverUri: '' };
    try {
      if (contentType === UnifiedContentType.NOVEL) {
        const novel = await this.novelDataManager.getBook(contentId);
        const rawCover = this.resolveNovelCoverRaw(novel as object);
        const normalizedCover = this.normalizeContentCoverUri(rawCover, contentType, contentId);
        const result: InspirationContentDisplayInfo = {
          title: novel?.name || '',
          coverUri: normalizedCover
        };
        this.contentDisplayCache.set(cacheKey, result);
        return result;
      }
      if (contentType === UnifiedContentType.MANGA) {
        const manga = await this.dataManager.getComicById(contentId);
        const rawCover = this.resolveMangaCoverRaw(manga as object);
        const normalizedCover = this.normalizeContentCoverUri(rawCover, contentType, contentId);
        const result: InspirationContentDisplayInfo = {
          title: manga?.title || '',
          coverUri: normalizedCover
        };
        this.contentDisplayCache.set(cacheKey, result);
        return result;
      }
      const ebook = await this.ebookDataManager.getEBookById(contentId);
      const rawCover = this.resolveEBookCoverRaw(ebook as object);
      const normalizedCover = this.normalizeContentCoverUri(rawCover, contentType, contentId);
      const result: InspirationContentDisplayInfo = {
        title: ebook?.metadata.title || '',
        coverUri: normalizedCover
      };
      this.contentDisplayCache.set(cacheKey, result);
      return result;
    } catch (error) {
      logger.warn(TAG, `解析灵感内容显示信息失败: type=${contentType}, contentId=${contentId}, error=${String(error)}`);
      this.contentDisplayCache.set(cacheKey, fallback);
      return fallback;
    }
  }

  private async buildContentSummaries(records: UnifiedAnnotationRecord[]): Promise<InspirationContentSummary[]> {
    const summaryMap: Map<string, InspirationContentSummary> = new Map();
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      const key = this.buildContentKey(record.contentType, record.contentId);
      let summary = summaryMap.get(key);
      if (!summary) {
        summary = {
          key,
          contentType: record.contentType,
          contentId: record.contentId,
          title: '',
          coverUri: '',
          totalCount: 0,
          bookmarkCount: 0,
          highlightCount: 0,
          thoughtCount: 0
        };
        summaryMap.set(key, summary);
      }
      summary.totalCount += 1;
      const normalizedType = this.normalizeRecordType(record);
      if (normalizedType === UnifiedAnnotationType.BOOKMARK) {
        summary.bookmarkCount += 1;
      } else if (normalizedType === UnifiedAnnotationType.HIGHLIGHT) {
        summary.highlightCount += 1;
      } else {
        summary.thoughtCount += 1;
      }
    }

    const result: InspirationContentSummary[] = [];
    const summaryArray = Array.from(summaryMap.values());
    for (let i = 0; i < summaryArray.length; i++) {
      const summary = summaryArray[i];
      const display = await this.resolveContentDisplayInfo(summary.contentType, summary.contentId);
      const fallbackTitle = `${this.getContentTypeLabel(summary.contentType)}内容`;
      summary.title = display.title && display.title.trim().length > 0 ? display.title : fallbackTitle;
      summary.coverUri = display.coverUri || '';
      if (summary.coverUri.length <= 0) {
        logger.warn(
          TAG,
          `灵感内容筛选封面缺失: type=${summary.contentType}, contentId=${summary.contentId}, title=${summary.title}`
        );
      }
      result.push(summary);
    }
    result.sort((a: InspirationContentSummary, b: InspirationContentSummary) => {
      if (b.totalCount !== a.totalCount) {
        return b.totalCount - a.totalCount;
      }
      if (a.title === b.title) {
        return 0;
      }
      return a.title > b.title ? 1 : -1;
    });
    return result;
  }

  private applySelectionMetaFromSummary(summary: InspirationContentSummary): void {
    this.contentType = summary.contentType;
    this.contentId = summary.contentId;
    this.contentTitle = summary.title;
    this.selectedContentName = summary.title;
    this.selectedContentCoverUri = summary.coverUri;
  }

  private async applyContentSelectionByKey(contentKey: string, trigger: string): Promise<void> {
    this.selectedContentKey = contentKey;
    if (contentKey.length <= 0) {
      this.contentId = '';
      this.contentTitle = '全部内容';
      this.selectedContentName = '全部内容';
      this.selectedContentCoverUri = this.getAllContentCoverUri();
      this.refreshRecordsByContentSelection(trigger);
      return;
    }

    const summary = this.getContentSummaryByKey(contentKey);
    if (summary) {
      this.applySelectionMetaFromSummary(summary);
      this.refreshRecordsByContentSelection(trigger);
      return;
    }

    const keyParts = this.parseContentKey(contentKey);
    if (!keyParts) {
      this.selectedContentKey = '';
      this.contentId = '';
      this.contentTitle = '全部内容';
      this.selectedContentName = '全部内容';
      this.selectedContentCoverUri = this.getAllContentCoverUri();
      this.refreshRecordsByContentSelection(`${trigger}_fallback`);
      return;
    }

    this.contentType = keyParts.contentType;
    this.contentId = keyParts.contentId;
    const display = await this.resolveContentDisplayInfo(keyParts.contentType, keyParts.contentId);
    const fallbackTitle = this.contentTitle && this.contentTitle.trim().length > 0
      ? this.contentTitle
      : `${this.getContentTypeLabel(keyParts.contentType)}内容`;
    this.contentTitle = display.title && display.title.trim().length > 0 ? display.title : fallbackTitle;
    this.selectedContentName = this.contentTitle;
    this.selectedContentCoverUri = display.coverUri || '';
    this.refreshRecordsByContentSelection(trigger);
  }

  private refreshRecordsByContentSelection(trigger: string): void {
    if (this.selectedContentKey.length <= 0) {
      this.records = [...this.allRecords];
    } else {
      const keyParts = this.parseContentKey(this.selectedContentKey);
      if (!keyParts) {
        this.records = [...this.allRecords];
      } else {
        this.records = this.allRecords.filter((record: UnifiedAnnotationRecord) =>
          record.contentType === keyParts.contentType && record.contentId === keyParts.contentId
        );
      }
    }
    if (this.editingRecordId.length > 0) {
      this.cancelEdit();
    }
    this.selectedRecordIds = [];
    this.applyFilter();
    this.animateVisibleRecordsIn(trigger);
    logger.info(
      TAG,
      `灵感列表刷新完成: trigger=${trigger}, contentKey=${this.selectedContentKey || 'all'}, records=${this.records.length}`
    );
    this.refreshAllContentChipSubtitle(`refresh_records_${trigger}`);
  }

  private normalizeRecordType(record: UnifiedAnnotationRecord): UnifiedAnnotationType {
    const raw = String(record.annotationType)
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '')
      .replace(/_/g, '')
      .replace(/-/g, '');
    if (
      raw === UnifiedAnnotationType.HIGHLIGHT ||
      raw === 'highlight' ||
      raw === '1' ||
      raw === '划线' ||
      raw === 'underline'
    ) {
      return UnifiedAnnotationType.HIGHLIGHT;
    }
    if (
      raw === UnifiedAnnotationType.THOUGHT ||
      raw === 'thought' ||
      raw === 'note' ||
      raw === '2' ||
      raw === '想法'
    ) {
      return UnifiedAnnotationType.THOUGHT;
    }
    if (raw !== UnifiedAnnotationType.BOOKMARK && raw !== 'bookmark' && raw !== '0' && raw !== '书签') {
      logger.warn(TAG, `灵感页识别到未知标注类型，已按书签处理: raw=${String(record.annotationType)}, normalized=${raw}`);
    }
    return UnifiedAnnotationType.BOOKMARK;
  }

  private getContentTypeLabel(type: UnifiedContentType): string {
    if (type === UnifiedContentType.MANGA) {
      return '漫画';
    }
    if (type === UnifiedContentType.EBOOK) {
      return '电子书';
    }
    return '小说';
  }

  private getTypeLabel(type: UnifiedAnnotationType): string {
    if (type === UnifiedAnnotationType.BOOKMARK) {
      return '书签';
    }
    if (type === UnifiedAnnotationType.HIGHLIGHT) {
      return '划线';
    }
    return '想法';
  }

  private getFilterCount(filter: AnnotationFilterType): number {
    if (filter === 'all') {
      return this.records.length;
    }
    let count = 0;
    for (let i = 0; i < this.records.length; i++) {
      const type = this.normalizeRecordType(this.records[i]);
      if (filter === 'bookmark' && type === UnifiedAnnotationType.BOOKMARK) {
        count += 1;
      } else if (filter === 'highlight' && type === UnifiedAnnotationType.HIGHLIGHT) {
        count += 1;
      } else if (filter === 'thought' && type === UnifiedAnnotationType.THOUGHT) {
        count += 1;
      }
    }
    return count;
  }

  private getCurrentSelectionSummaryText(): string {
    if (this.selectedContentKey.length <= 0) {
      return `共 ${this.getAvailableContentCount()} 个内容 · ${this.records.length} 条灵感`;
    }
    const summary = this.getContentSummaryByKey(this.selectedContentKey);
    if (summary) {
      return `该内容共 ${summary.totalCount} 条灵感（书签${summary.bookmarkCount} · 划线${summary.highlightCount} · 想法${summary.thoughtCount}）`;
    }
    return `该内容共 ${this.records.length} 条灵感`;
  }

  private getAvailableContentCount(): number {
    if (this.contentSummaries.length > 0) {
      return this.contentSummaries.length;
    }
    if (this.selectedContentKey.length > 0 && this.records.length > 0) {
      return 1;
    }
    return 0;
  }

  private getAllContentCoverUri(): string {
    for (let i = 0; i < this.contentSummaries.length; i++) {
      const coverUri = this.contentSummaries[i].coverUri ? this.contentSummaries[i].coverUri.trim() : '';
      if (coverUri.length > 0) {
        return coverUri;
      }
    }
    return '';
  }

  private refreshAllContentChipSubtitle(trigger: string): void {
    const count = this.getAvailableContentCount();
    this.allContentChipSubtitle = `${count} 个内容`;
    if (count > 0 && this.getAllContentCoverUri().length <= 0) {
      logger.warn(TAG, `全部内容封面缺失: trigger=${trigger}, count=${count}`);
    }
    logger.debug(
      TAG,
      `刷新全部内容文案: trigger=${trigger}, count=${count}, summaries=${this.contentSummaries.length}, records=${this.records.length}`
    );
  }

  private getAnchorLabel(record: UnifiedAnnotationRecord): string {
    const parts: string[] = [];
    if (record.chapterTitle && record.chapterTitle.trim().length > 0) {
      parts.push(record.chapterTitle.trim());
    } else if (record.chapterIndex >= 0) {
      parts.push(`章节 ${record.chapterIndex + 1}`);
    }
    if (record.pageIndex >= 0) {
      parts.push(`P${record.pageIndex + 1}`);
    }
    if (record.contentType === UnifiedContentType.NOVEL) {
      const paragraphIndex = typeof record.anchor.paragraphIndex === 'number'
        ? Math.floor(record.anchor.paragraphIndex)
        : -1;
      if (paragraphIndex >= 0) {
        parts.push(`段落 ${paragraphIndex + 1}`);
      } else if (record.startOffset >= 0) {
        parts.push(`偏移 ${record.startOffset}`);
      }
    }
    if (record.pageProgress >= 0) {
      parts.push(`${Math.round(record.pageProgress * 100)}%`);
    }
    if (parts.length <= 0) {
      return '位置信息未记录';
    }
    return parts.join(' · ');
  }

  private getHighlightStyleLabel(record: UnifiedAnnotationRecord): string {
    if (!record.styleJson || record.styleJson.trim().length <= 0) {
      return '';
    }
    try {
      const styleObj = JSON.parse(record.styleJson) as HighlightStylePreview;
      const lineTypeText = styleObj.lineType === HighlightLineType.WAVY ? '波浪线' : '下划线';
      const colorText = styleObj.color && styleObj.color.trim().length > 0 ? styleObj.color : '';
      return colorText.length > 0 ? `${lineTypeText} / ${colorText}` : lineTypeText;
    } catch (_error) {
      return '';
    }
  }

  private formatTime(timestamp: number): string {
    if (!Number.isFinite(timestamp) || timestamp <= 0) {
      return '';
    }
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  private trimText(text: string, maxLength: number): string {
    if (text.length <= maxLength) {
      return text;
    }
    return `${text.substring(0, maxLength)}...`;
  }

  private startPageEnterAnimation(): void {
    this.pageEnterOpacity = 0;
    this.pageEnterOffsetY = 16;
    animateTo({
      duration: 260,
      curve: Curve.EaseOut
    }, () => {
      this.pageEnterOpacity = 1;
      this.pageEnterOffsetY = 0;
    });
  }

  private animateVisibleRecordsIn(trigger: string): void {
    this.listOpacity = 0.2;
    this.listOffsetY = 8;
    animateTo({
      duration: 240,
      curve: Curve.EaseOut
    }, () => {
      this.listOpacity = 1;
      this.listOffsetY = 0;
    });
    logger.info(TAG, `灵感列表动画完成: trigger=${trigger}, visible=${this.visibleRecords.length}`);
  }

  private applyFilterWithAnimation(trigger: string): void {
    const token = this.listAnimationToken + 1;
    this.listAnimationToken = token;
    animateTo({
      duration: 120,
      curve: Curve.EaseInOut
    }, () => {
      this.listOpacity = 0.08;
      this.listOffsetY = 8;
    });
    setTimeout(() => {
      if (token !== this.listAnimationToken) {
        return;
      }
      this.applyFilter();
      this.animateVisibleRecordsIn(trigger);
    }, 90);
  }

  private applyFilter(): void {
    if (this.filterType === 'all') {
      this.visibleRecords = [...this.records];
    } else {
      const filtered: UnifiedAnnotationRecord[] = [];
      for (let i = 0; i < this.records.length; i++) {
        const record = this.records[i];
        const type = this.normalizeRecordType(record);
        if (this.filterType === 'bookmark' && type === UnifiedAnnotationType.BOOKMARK) {
          filtered.push(record);
        } else if (this.filterType === 'highlight' && type === UnifiedAnnotationType.HIGHLIGHT) {
          filtered.push(record);
        } else if (this.filterType === 'thought' && type === UnifiedAnnotationType.THOUGHT) {
          filtered.push(record);
        }
      }
      this.visibleRecords = filtered;
    }

    this.selectedRecordIds = this.selectedRecordIds.filter((id: string) =>
      this.visibleRecords.some((record: UnifiedAnnotationRecord) => record.id === id)
    );
  }

  private async loadAnnotations(): Promise<void> {
    this.isLoading = true;
    try {
      let rawRecords = await this.annotationManager.getAllAnnotations();
      if (rawRecords.length <= 0 && this.contentId && this.contentId.trim().length > 0) {
        logger.warn(
          TAG,
          `全量灵感查询为空，回退到当前内容查询: contentType=${this.contentType}, contentId=${this.contentId}`
        );
        rawRecords = await this.annotationManager.getContentAnnotations(this.contentType, this.contentId);
      }
      this.allRecords = rawRecords;
      this.contentSummaries = await this.buildContentSummaries(rawRecords);
      const hasSelectedContent = this.selectedContentKey && this.selectedContentKey.trim().length > 0;
      await this.applyContentSelectionByKey(hasSelectedContent ? this.selectedContentKey : '', 'load_annotations');
      logger.info(
        TAG,
        `灵感数据加载完成: total=${this.allRecords.length}, contents=${this.contentSummaries.length}, bookmark=${this.getFilterCount('bookmark')}, highlight=${this.getFilterCount('highlight')}, thought=${this.getFilterCount('thought')}`
      );
    } catch (error) {
      logger.error(TAG, `加载灵感数据失败: ${String(error)}`);
      if (this.contentId && this.contentId.trim().length > 0) {
        try {
          logger.warn(TAG, `尝试回退加载当前内容灵感: contentType=${this.contentType}, contentId=${this.contentId}`);
          const currentRecords = await this.annotationManager.getContentAnnotations(this.contentType, this.contentId);
          this.allRecords = currentRecords;
          this.contentSummaries = await this.buildContentSummaries(currentRecords);
          const key = this.buildContentKey(this.contentType, this.contentId);
          await this.applyContentSelectionByKey(key, 'load_annotations_fallback_current_content');
          return;
        } catch (fallbackError) {
          logger.error(TAG, `回退加载当前内容灵感失败: ${String(fallbackError)}`);
        }
      }
      promptAction.showToast({ message: '加载灵感失败', duration: 1500 });
      this.allRecords = [];
      this.records = [];
      this.visibleRecords = [];
      this.selectedRecordIds = [];
      this.contentSummaries = [];
      this.selectedContentKey = '';
      this.selectedContentName = '全部内容';
      this.selectedContentCoverUri = '';
      this.contentTitle = '全部内容';
      this.refreshAllContentChipSubtitle('load_annotations_failed_reset');
    } finally {
      this.isLoading = false;
    }
  }

  private onFilterTypeChange(next: AnnotationFilterType): void {
    if (this.filterType === next) {
      return;
    }
    this.filterType = next;
    this.applyFilterWithAnimation(`filter_${next}`);
  }

  private isSelected(recordId: string): boolean {
    return this.selectedRecordIds.includes(recordId);
  }

  private toggleSelection(recordId: string): void {
    if (this.isSelected(recordId)) {
      this.selectedRecordIds = this.selectedRecordIds.filter((id: string) => id !== recordId);
    } else {
      this.selectedRecordIds = [...this.selectedRecordIds, recordId];
    }
  }

  private toggleSelectAllVisible(): void {
    if (this.visibleRecords.length <= 0) {
      promptAction.showToast({ message: '当前筛选下无可选灵感', duration: 1500 });
      return;
    }
    const allSelected = this.visibleRecords.every((record: UnifiedAnnotationRecord) => this.isSelected(record.id));
    if (allSelected) {
      this.selectedRecordIds = [];
    } else {
      this.selectedRecordIds = this.visibleRecords.map((record: UnifiedAnnotationRecord) => record.id);
    }
  }

  private formatRecordForShare(record: UnifiedAnnotationRecord, index: number): string {
    const type = this.normalizeRecordType(record);
    const lines: string[] = [];
    lines.push(`${index + 1}. [${this.getTypeLabel(type)}] ${this.getAnchorLabel(record)}`);

    if (record.title && record.title.trim().length > 0) {
      lines.push(`标记：${record.title.trim()}`);
    }
    if (record.quoteText && record.quoteText.trim().length > 0) {
      lines.push(`摘录：${record.quoteText.trim()}`);
    }
    if (record.textContent && record.textContent.trim().length > 0) {
      lines.push(`内容：${record.textContent.trim()}`);
    }
    if (type === UnifiedAnnotationType.HIGHLIGHT) {
      const styleLabel = this.getHighlightStyleLabel(record);
      if (styleLabel.length > 0) {
        lines.push(`样式：${styleLabel}`);
      }
    }
    return lines.join('\n');
  }

  private formatRecordForShareMarkdown(record: UnifiedAnnotationRecord, index: number): string {
    const type = this.normalizeRecordType(record);
    const lines: string[] = [];
    lines.push(`## ${index + 1}. ${this.getTypeLabel(type)} · ${this.getAnchorLabel(record)}`);

    if (record.title && record.title.trim().length > 0) {
      lines.push(`- 书签标记：${record.title.trim()}`);
    }
    if (record.quoteText && record.quoteText.trim().length > 0) {
      lines.push(`- 摘录：`);
      lines.push(`> ${record.quoteText.trim()}`);
    }
    if (record.textContent && record.textContent.trim().length > 0) {
      lines.push(`- 补充内容：${record.textContent.trim()}`);
    }
    if (type === UnifiedAnnotationType.HIGHLIGHT) {
      const styleLabel = this.getHighlightStyleLabel(record);
      if (styleLabel.length > 0) {
        lines.push(`- 划线样式：${styleLabel}`);
      }
    }
    return lines.join('\n');
  }

  private getSelectedRecordsForShare(): UnifiedAnnotationRecord[] {
    return this.visibleRecords.filter((record: UnifiedAnnotationRecord) =>
      this.selectedRecordIds.includes(record.id)
    );
  }

  private buildMergedShareText(records: UnifiedAnnotationRecord[], format: ShareFormatType): string {
    const typeLabel = this.getCurrentSelectionTypeLabel();
    const exportTime = this.formatTime(Date.now());
    if (format === 'markdown') {
      const body = records
        .map((record: UnifiedAnnotationRecord, index: number) => this.formatRecordForShareMarkdown(record, index))
        .join('\n\n');
      const header = [
        `# ${this.contentTitle} 灵感分享`,
        '',
        `- 内容类型：${typeLabel}`,
        `- 灵感数量：${records.length}`,
        `- 导出时间：${exportTime}`
      ];
      return `${header.join('\n')}\n\n${body}`;
    }

    const plainBody = records
      .map((record: UnifiedAnnotationRecord, index: number) => this.formatRecordForShare(record, index))
      .join('\n\n');
    const plainHeader = [
      `${this.contentTitle} 灵感分享`,
      `内容类型：${typeLabel}`,
      `灵感数量：${records.length}`,
      `导出时间：${exportTime}`,
      ''
    ];
    return `${plainHeader.join('\n')}\n${plainBody}`;
  }

  private async copyTextToClipboard(text: string, successMessage: string): Promise<boolean> {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: successMessage, duration: 1500 });
      return true;
    } catch (error) {
      logger.error(TAG, `复制灵感失败: ${String(error)}`);
      promptAction.showToast({ message: '复制失败', duration: 1500 });
      return false;
    }
  }

  private async copyRecords(records: UnifiedAnnotationRecord[], format: ShareFormatType): Promise<void> {
    if (records.length <= 0) {
      promptAction.showToast({ message: '没有可分享的灵感', duration: 1500 });
      return;
    }
    const mergedText = this.buildMergedShareText(records, format);
    const formatLabel = format === 'markdown' ? 'Markdown' : '文本';
    const successMessage = `已复制${records.length} 条灵感（${formatLabel}）`;
    await this.copyTextToClipboard(mergedText, successMessage);
    logger.info(TAG, `灵感复制完成: count=${records.length}, format=${format}`);
  }

  private async copySelectedRecords(format: ShareFormatType = 'plain'): Promise<void> {
    if (this.selectedRecordIds.length <= 0) {
      promptAction.showToast({ message: '请先选择灵感', duration: 1500 });
      return;
    }
    const selected = this.getSelectedRecordsForShare();
    await this.copyRecords(selected, format);
  }

  private async copySingleRecord(record: UnifiedAnnotationRecord, format: ShareFormatType = 'plain'): Promise<void> {
    await this.copyRecords([record], format);
  }

  private openSharePreview(records: UnifiedAnnotationRecord[], format: ShareFormatType): void {
    if (records.length <= 0) {
      promptAction.showToast({ message: '没有可分享的灵感', duration: 1500 });
      return;
    }
    this.sharePreviewTitle = records.length > 1
      ? `已选${records.length} 条灵感`
      : `${this.getTypeLabel(this.normalizeRecordType(records[0]))} 分享预览`;
    this.sharePreviewContent = this.buildMergedShareText(records, format);
    this.sharePreviewFormat = format;
    this.showSharePreview = true;
    this.sharePreviewMaskOpacity = 0;
    this.sharePreviewPanelOpacity = 0;
    this.sharePreviewPanelScale = 0.96;
    animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.sharePreviewMaskOpacity = 1;
      this.sharePreviewPanelOpacity = 1;
      this.sharePreviewPanelScale = 1;
    });
    logger.info(TAG, `打开灵感分享预览: count=${records.length}, format=${format}`);
  }

  private closeSharePreview(): void {
    animateTo({
      duration: 160,
      curve: Curve.EaseIn
    }, () => {
      this.sharePreviewMaskOpacity = 0;
      this.sharePreviewPanelOpacity = 0;
      this.sharePreviewPanelScale = 0.96;
    });
    setTimeout(() => {
      this.showSharePreview = false;
    }, 170);
  }

  private async copySharePreviewAndClose(): Promise<void> {
    const copied = await this.copyTextToClipboard(this.sharePreviewContent, '分享内容已复制');
    if (copied) {
      this.closeSharePreview();
    }
  }

  private async shareTextBySystem(text: string, title: string): Promise<boolean> {
    const safeText = text ? text.trim() : '';
    if (safeText.length <= 0) {
      promptAction.showToast({ message: '分享内容为空', duration: 1500 });
      return false;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: safeText,
        title: title && title.trim().length > 0 ? title : '灵感分享',
        description: '来自灵感页的分享内容'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      logger.info(TAG, `系统分享成功: title=${title}`);
      return true;
    } catch (error) {
      logger.error(TAG, `系统分享失败: ${String(error)}`);
      promptAction.showToast({ message: '系统分享失败，已复制到剪贴板', duration: 1800 });
      await this.copyTextToClipboard(safeText, '分享内容已复制');
      return false;
    }
  }

  private async sharePreviewBySystemAndClose(): Promise<void> {
    const shared = await this.shareTextBySystem(this.sharePreviewContent, this.sharePreviewTitle);
    if (shared) {
      this.closeSharePreview();
    }
  }

  private showShareActionMenuForSelected(): void {
    const selected = this.getSelectedRecordsForShare();
    if (selected.length <= 0) {
      promptAction.showToast({ message: '请先选择灵感', duration: 1500 });
      return;
    }
    promptAction.showActionMenu({
      title: `分享已选${selected.length} 条灵感`,
      buttons: [
        { text: '预览文本', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '预览Markdown', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '直接复制文本', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '直接复制Markdown', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.openSharePreview(selected, 'plain');
      } else if (result.index === 1) {
        this.openSharePreview(selected, 'markdown');
      } else if (result.index === 2) {
        await this.copyRecords(selected, 'plain');
      } else if (result.index === 3) {
        await this.copyRecords(selected, 'markdown');
      }
    }).catch(() => {});
  }

  private showShareActionMenuForRecord(record: UnifiedAnnotationRecord): void {
    promptAction.showActionMenu({
      title: '分享这条灵感',
      buttons: [
        { text: '预览文本', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '预览Markdown', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '直接复制文本', color: $r('sys.color.ohos_id_color_text_primary') },
        { text: '直接复制Markdown', color: $r('sys.color.ohos_id_color_text_primary') }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index === 0) {
        this.openSharePreview([record], 'plain');
      } else if (result.index === 1) {
        this.openSharePreview([record], 'markdown');
      } else if (result.index === 2) {
        await this.copySingleRecord(record, 'plain');
      } else if (result.index === 3) {
        await this.copySingleRecord(record, 'markdown');
      }
    }).catch(() => {});
  }

  private isEditing(recordId: string): boolean {
    return this.editingRecordId === recordId;
  }

  private startEdit(record: UnifiedAnnotationRecord): void {
    this.editingRecordId = record.id;
    const type = this.normalizeRecordType(record);
    logger.info(TAG, `进入灵感编辑: id=${record.id}, type=${type}`);
    if (type === UnifiedAnnotationType.HIGHLIGHT) {
      const linkedThought = this.findLinkedThoughtForHighlight(record);
      this.editingTitleText = '';
      this.editingBodyText = linkedThought ? (linkedThought.textContent || '') : '';
      return;
    }
    this.editingTitleText = record.title || '';
    this.editingBodyText = record.textContent || '';
  }

  private findLinkedThoughtForHighlight(highlightRecord: UnifiedAnnotationRecord): UnifiedAnnotationRecord | null {
    for (let i = 0; i < this.records.length; i++) {
      const record = this.records[i];
      if (this.normalizeRecordType(record) !== UnifiedAnnotationType.THOUGHT) {
        continue;
      }
      if (record.linkedAnnotationId && record.linkedAnnotationId === highlightRecord.id) {
        return record;
      }
    }

    for (let i = 0; i < this.records.length; i++) {
      const record = this.records[i];
      if (this.normalizeRecordType(record) !== UnifiedAnnotationType.THOUGHT) {
        continue;
      }
      if (record.chapterId && highlightRecord.chapterId && record.chapterId !== highlightRecord.chapterId) {
        continue;
      }
      if (record.chapterIndex >= 0 && highlightRecord.chapterIndex >= 0 && record.chapterIndex !== highlightRecord.chapterIndex) {
        continue;
      }
      if (
        record.startOffset === highlightRecord.startOffset &&
        record.endOffset === highlightRecord.endOffset &&
        record.quoteText === highlightRecord.quoteText
      ) {
        return record;
      }
    }
    return null;
  }

  private cancelEdit(): void {
    if (this.editingRecordId) {
      logger.info(TAG, `取消灵感编辑: id=${this.editingRecordId}`);
    }
    this.editingRecordId = '';
    this.editingTitleText = '';
    this.editingBodyText = '';
    this.savingEdit = false;
  }

  private getEditingRecord(): UnifiedAnnotationRecord | null {
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].id === this.editingRecordId) {
        return this.records[i];
      }
    }
    return null;
  }

  private async saveEdit(): Promise<void> {
    if (this.savingEdit || !this.editingRecordId) {
      return;
    }
    const target = this.getEditingRecord();
    if (!target) {
      this.cancelEdit();
      return;
    }

    this.savingEdit = true;
    const type = this.normalizeRecordType(target);
    let nextTitle = target.title || '';
    let nextText = target.textContent || '';
    try {
      if (type === UnifiedAnnotationType.BOOKMARK) {
        nextTitle = this.editingTitleText.trim();
        nextText = this.editingBodyText.trim();
        await this.annotationManager.updateAnnotationText(target.id, nextTitle, nextText);
      } else if (type === UnifiedAnnotationType.HIGHLIGHT) {
        nextText = this.editingBodyText.trim();
        const linkedThought = this.findLinkedThoughtForHighlight(target);
        if (linkedThought) {
          await this.annotationManager.updateAnnotationText(linkedThought.id, linkedThought.title || '', nextText);
        } else if (nextText.length > 0) {
          const anchor: AnnotationAnchor = {
            chapterId: target.chapterId,
            chapterTitle: target.chapterTitle,
            chapterIndex: target.chapterIndex,
            pageIndex: target.pageIndex,
            progress: target.pageProgress,
            startOffset: target.startOffset,
            endOffset: target.endOffset,
            quoteText: target.quoteText
          };
          await this.annotationManager.createThought({
            contentId: target.contentId,
            anchor,
            textContent: nextText,
            linkedAnnotationId: target.id
          });
        }
      } else {
        nextText = this.editingBodyText.trim();
        await this.annotationManager.updateAnnotationText(target.id, nextTitle, nextText);
      }

      logger.info(TAG, `灵感编辑保存成功: id=${target.id}, type=${type}`);
      promptAction.showToast({ message: '灵感已更新', duration: 1200 });
      this.cancelEdit();
      await this.loadAnnotations();
    } catch (error) {
      logger.error(TAG, `保存灵感编辑失败: id=${target.id}, error=${String(error)}`);
      promptAction.showToast({ message: '保存失败', duration: 1200 });
    } finally {
      this.savingEdit = false;
    }
  }

  private getEditButtonLabel(record: UnifiedAnnotationRecord): string {
    const type = this.normalizeRecordType(record);
    if (type === UnifiedAnnotationType.HIGHLIGHT || type === UnifiedAnnotationType.THOUGHT) {
      return '编辑想法';
    }
    return '编辑';
  }

  private deleteRecord(recordId: string): void {
    promptAction.showActionMenu({
      title: '删除这条灵感？',
      buttons: [
        { text: '删除', color: '#F04438' },
        { text: '取消', color: '#666666' }
      ]
    }).then(async (result: promptAction.ActionMenuSuccessResponse) => {
      if (result.index !== 0) {
        return;
      }
      try {
        await this.annotationManager.deleteAnnotation(recordId);
        this.selectedRecordIds = this.selectedRecordIds.filter((id: string) => id !== recordId);
        if (this.editingRecordId === recordId) {
          this.cancelEdit();
        }
        await this.loadAnnotations();
        promptAction.showToast({ message: '已删除', duration: 1200 });
      } catch (error) {
        logger.error(TAG, `删除灵感失败: id=${recordId}, error=${String(error)}`);
        promptAction.showToast({ message: '删除失败', duration: 1200 });
      }
    }).catch(() => {});
  }

  private normalizeMangaContentType(contentType?: string): MangaReaderContentTypeValue {
    if (contentType === 'OnlineDownloaded') {
      return 'OnlineDownloaded';
    }
    if (contentType === 'OnlineUndownloaded') {
      return 'OnlineUndownloaded';
    }
    return 'Local';
  }

  private clampChapterIndex(target: number, chapterCount: number): number {
    if (!Number.isFinite(target) || target < 0) {
      return 0;
    }
    const safeIndex = Math.floor(target);
    if (chapterCount <= 0) {
      return safeIndex;
    }
    return Math.max(0, Math.min(safeIndex, chapterCount - 1));
  }

  private async openNovelReaderByRecord(record: UnifiedAnnotationRecord): Promise<void> {
    const novelContext = this.readerContext?.novel;
    const book = await this.novelDataManager.getBook(record.contentId);
    if (!book) {
      promptAction.showToast({ message: '未找到小说书籍信息', duration: 1500 });
      logger.warn(TAG, `定位小说原文失败: 缺少书籍信息, contentId=${record.contentId}`);
      return;
    }

    const chapterCount = book.chapterCount > 0 ? book.chapterCount : 1;
    let targetChapterIndex = record.chapterIndex >= 0 ? record.chapterIndex : (book.lastReadChapterIndex ?? 0);
    targetChapterIndex = this.clampChapterIndex(targetChapterIndex, chapterCount);
    let chapter = await this.novelDataManager.getChapterByIndex(book.id, targetChapterIndex);
    if (!chapter && targetChapterIndex !== 0) {
      targetChapterIndex = 0;
      chapter = await this.novelDataManager.getChapterByIndex(book.id, 0);
    }
    if (!chapter) {
      promptAction.showToast({ message: '未找到小说章节信息', duration: 1500 });
      logger.warn(TAG, `定位小说原文失败: 缺少章节信息, contentId=${record.contentId}, chapterIndex=${targetChapterIndex}`);
      return;
    }

    const params: NovelReaderRouteParams = {
      sourceId: book.sourceId,
      bookUrl: book.bookUrl,
      bookName: book.name,
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterIndex: chapter.index >= 0 ? chapter.index : targetChapterIndex,
      totalChapters: chapterCount,
      chapterPageIndex: record.pageIndex >= 0 ? record.pageIndex : undefined,
      chapterStartOffset: record.startOffset >= 0
        ? record.startOffset
        : (typeof record.anchor.paragraphStartOffset === 'number' && record.anchor.paragraphStartOffset >= 0
          ? Math.floor(record.anchor.paragraphStartOffset)
          : undefined),
      tocUrl: novelContext?.tocUrl || book.tocUrl || book.bookUrl,
      coverUrl: book.coverLocalPath || book.coverUrl || '',
      sourceName: novelContext?.sourceName || book.sourceName
    };
    this.pathStack.pushPathByName('NovelReaderPage', params);
    logger.info(
      TAG,
      `定位小说原文成功: bookId=${book.id}, chapterIndex=${params.chapterIndex}, pageIndex=${params.chapterPageIndex ?? -1}, startOffset=${params.chapterStartOffset ?? -1}`
    );
  }

  private async inferMangaSourceId(mangaId: string): Promise<number | undefined> {
    const mangaContext = this.readerContext?.manga;
    if (mangaContext?.sourceId && mangaContext.sourceId > 0) {
      return mangaContext.sourceId;
    }
    try {
      const comicInfo = await this.dataManager.getComicById(mangaId);
      if (!comicInfo || !comicInfo.sourceId) {
        return undefined;
      }
      const sourceId = Number(comicInfo.sourceId);
      if (!Number.isFinite(sourceId) || sourceId <= 0) {
        return undefined;
      }
      return sourceId;
    } catch (error) {
      logger.warn(TAG, `推断漫画图源失败: ${String(error)}`);
      return undefined;
    }
  }

  private async openMangaReaderByRecord(record: UnifiedAnnotationRecord): Promise<void> {
    const mangaContext = this.readerContext?.manga;
    const mangaId = record.contentId;
    const sourceId = await this.inferMangaSourceId(mangaId);
    const contextContentType = this.normalizeMangaContentType(mangaContext?.contentType);
    const finalContentType: MangaReaderContentTypeValue = sourceId
      ? (contextContentType === 'Local' ? 'OnlineUndownloaded' : contextContentType)
      : 'Local';
    const chapterId = record.chapterId && record.chapterId.trim().length > 0
      ? record.chapterId
      : (mangaContext?.chapterId || '');
    const pageIndex = record.pageIndex >= 0
      ? record.pageIndex
      : (typeof mangaContext?.pageIndex === 'number' && mangaContext.pageIndex >= 0 ? Math.floor(mangaContext.pageIndex) : 0);

    const params: MangaReaderRouteParams = {
      mangaId,
      sourceId,
      sourceName: mangaContext?.sourceName,
      contentType: finalContentType,
      chapterId: chapterId.length > 0 ? chapterId : undefined,
      pageIndex,
      fromPage: 'AnnotationCenterPage'
    };
    this.pathStack.pushPathByName('MangaReaderPage', params);
    logger.info(
      TAG,
      `定位漫画原页成功: mangaId=${mangaId}, contentType=${finalContentType}, sourceId=${sourceId ?? -1}, chapterId=${params.chapterId || ''}, pageIndex=${pageIndex}`
    );
  }

  private async openEBookReaderByRecord(record: UnifiedAnnotationRecord): Promise<void> {
    const ebookContext = this.readerContext?.ebook;
    const ebook = await this.ebookDataManager.getEBookById(record.contentId);
    if (!ebook) {
      promptAction.showToast({ message: '未找到电子书信息', duration: 1500 });
      logger.warn(TAG, `定位电子书原页失败: 缺少书籍信息, contentId=${record.contentId}`);
      return;
    }

    const chapterCount = ebook.chapters.length;
    const fallbackChapterIndex = ebook.readingProgress?.currentChapterIndex ?? 0;
    const rawChapterIndex = record.chapterIndex >= 0
      ? record.chapterIndex
      : (ebookContext?.chapterIndex ?? fallbackChapterIndex);
    const targetChapterIndex = this.clampChapterIndex(rawChapterIndex, chapterCount);
    const targetChapter = chapterCount > 0 ? ebook.chapters[targetChapterIndex] : null;
    const rawStartOffset = record.startOffset >= 0
      ? record.startOffset
      : (ebookContext?.startOffset ?? -1);
    const rawPageIndex = record.pageIndex >= 0
      ? record.pageIndex
      : (ebookContext?.pageIndex ?? 0);
    const rawPosition = rawStartOffset >= 0 ? rawStartOffset : rawPageIndex;
    const currentPosition = ebook.format === EBookFormat.TXT
      ? (Number.isFinite(rawPageIndex) && rawPageIndex >= 0 ? Math.floor(rawPageIndex) : 0)
      : (Number.isFinite(rawPosition) && rawPosition >= 0 ? Math.floor(rawPosition) : 0);
    const safeStartOffset = Number.isFinite(rawStartOffset) && rawStartOffset >= 0
      ? Math.floor(rawStartOffset)
      : 0;
    const safeTxtDomPos = `page:${currentPosition};char:${safeStartOffset};chapter:${targetChapterIndex}`;
    const computedProgress = chapterCount > 0
      ? Math.max(0, Math.min(100, ((targetChapterIndex + 1) / chapterCount) * 100))
      : 0;
    const previousProgress = ebook.readingProgress;
    const nextProgress: EBookReadingProgress = {
      bookId: ebook.id,
      currentChapterId: targetChapter?.id || previousProgress?.currentChapterId || '',
      currentChapterIndex: targetChapterIndex,
      currentPosition,
      domPos: ebook.format === EBookFormat.TXT ? safeTxtDomPos : '',
      progress: computedProgress,
      lastReadTime: Date.now(),
      totalReadingTime: previousProgress?.totalReadingTime || 0
    };
    await this.ebookDataManager.saveReadingProgress(nextProgress);
    ebook.readingProgress = nextProgress;

    if (ebook.format === EBookFormat.TXT) {
      const baseParams = buildNovelReaderParamsFromTxtEBook(ebook);
      const params: NovelReaderRouteParams = {
        sourceId: baseParams.sourceId,
        bookUrl: baseParams.bookUrl,
        bookName: baseParams.bookName,
        tocUrl: baseParams.tocUrl,
        coverUrl: baseParams.coverUrl,
        sourceName: baseParams.sourceName,
        chapterIndex: targetChapterIndex,
        chapterUrl: targetChapter?.id || `ebook://${ebook.id}/chapter/${targetChapterIndex}`,
        chapterTitle: targetChapter?.title || `Chapter ${targetChapterIndex + 1}`,
        totalChapters: Math.max(chapterCount, 1),
        chapterPageIndex: currentPosition,
        chapterStartOffset: safeStartOffset,
        localEbookId: ebook.id
      };
      this.pathStack.pushPathByName('NovelReaderPage', params);
      logger.info(
        TAG,
        `定位TXT电子书原页成功: bookId=${ebook.id}, chapterIndex=${targetChapterIndex}, pageIndex=${currentPosition}, startOffset=${safeStartOffset}`
      );
      return;
    }

    const params: EBookReaderRouteParams = { bookId: ebook.id };
    this.pathStack.pushPathByName('EBookReaderPage', params);
    logger.info(
      TAG,
      `定位电子书原页成功: bookId=${ebook.id}, chapterIndex=${targetChapterIndex}, position=${currentPosition}`
    );
  }

  private async openRecordLocation(record: UnifiedAnnotationRecord): Promise<void> {
    try {
      if (record.contentType === UnifiedContentType.NOVEL) {
        await this.openNovelReaderByRecord(record);
      } else if (record.contentType === UnifiedContentType.MANGA) {
        await this.openMangaReaderByRecord(record);
      } else {
        await this.openEBookReaderByRecord(record);
      }
    } catch (error) {
      logger.error(TAG, `定位原文失败: ${String(error)}`);
      promptAction.showToast({ message: '定位原文失败，请重试', duration: 1500 });
    }
  }

  @Builder
  private buildContentCover(coverUri: string, size: number, traceKey: string = '') {
    if (coverUri && coverUri.trim().length > 0) {
      Image(coverUri)
        .width(size)
        .height(size)
        .borderRadius(10)
        .objectFit(ImageFit.Cover)
        .onError((event: ImageError) => {
          const errorMessage: string = event.message ? event.message : '';
          logger.warn(
            TAG,
            `灵感封面加载失败: trace=${traceKey || 'unknown'}, uri=${coverUri}, message=${errorMessage}`
          );
        })
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.bookmark'))
          .fontSize(size * 0.36)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(size)
      .height(size)
      .borderRadius(10)
      .backgroundColor('rgba(120,120,120,0.12)')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  private buildContentSelectionItem(title: string, subtitle: string, contentKey: string, coverUri: string) {
    Row({ space: 8 }) {
      this.buildContentCover(coverUri, 38, contentKey || 'all_content')

      Column({ space: 2 }) {
        Text(title)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(this.selectedContentKey === contentKey ? '#FFFFFF' : $r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(subtitle)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(this.selectedContentKey === contentKey ? 'rgba(255,255,255,0.86)' : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width(188)
    .padding(8)
    .borderRadius(12)
    .backgroundColor(this.selectedContentKey === contentKey ? '#2563EB' : this.themeManager.getGlassBackgroundResource())
    .border({
      width: 1,
      color: this.selectedContentKey === contentKey ? 'rgba(37,99,235,0.50)' : 'rgba(120,120,120,0.16)'
    })
    .onClick(() => {
      void this.applyContentSelectionByKey(contentKey, 'tap_content_selector');
    })
  }

  @Builder
  private buildContentSelectorSection() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        this.buildContentCover(
          this.selectedContentKey.length > 0 ? this.selectedContentCoverUri : this.getAllContentCoverUri(),
          52,
          this.selectedContentKey || 'selected_all'
        )

        Column({ space: 4 }) {
          Text(this.selectedContentName)
            .fontSize(15)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.getCurrentSelectionSummaryText())
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          this.buildContentSelectionItem('全部内容', this.allContentChipSubtitle, '', this.getAllContentCoverUri())
          ForEach(this.contentSummaries, (summary: InspirationContentSummary) => {
            this.buildContentSelectionItem(
              summary.title,
              `${this.getContentTypeLabel(summary.contentType)} · ${summary.totalCount} 条`,
              summary.key,
              summary.coverUri
            )
          }, (summary: InspirationContentSummary) => summary.key)
        }
      }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .border({ width: 1, color: 'rgba(120,120,120,0.16)' })
    .id('guide_inspiration_content_selector')
  }

  @Builder
  private buildFilterButton(label: string, value: AnnotationFilterType) {
    Button(`${label} ${this.getFilterCount(value)}`)
      .fontSize(13)
      .fontFamily(this.appFontFamily)
      .fontColor(this.filterType === value ? '#FFFFFF' : $r('app.color.text_secondary'))
      .backgroundColor(this.filterType === value ? '#2563EB' : 'rgba(120,120,120,0.14)')
      .borderRadius(14)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .onClick(() => this.onFilterTypeChange(value))
  }

  @Builder
  private buildFieldBlock(label: string, content: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
      Text(content)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildRecordCard(record: UnifiedAnnotationRecord) {
    Row({ space: 10 }) {
      Column({ space: 10 }) {
      Row() {
        Text(this.getTypeLabel(this.normalizeRecordType(record)))
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor('#2563EB')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('rgba(37,99,235,0.14)')
          .borderRadius(10)

        if (this.normalizeRecordType(record) === UnifiedAnnotationType.HIGHLIGHT && this.getHighlightStyleLabel(record).length > 0) {
          Text(this.getHighlightStyleLabel(record))
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }

        Blank()

        Text(this.formatTime(record.createdAt))
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Text(this.getAnchorLabel(record))
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if ((record.title ? record.title.trim() : '').length > 0) {
        this.buildFieldBlock('标题', record.title ? record.title.trim() : '')
      }
      if ((record.quoteText ? record.quoteText.trim() : '').length > 0) {
        this.buildFieldBlock('摘录', record.quoteText ? record.quoteText.trim() : '')
      }
      if ((record.textContent ? record.textContent.trim() : '').length > 0) {
        this.buildFieldBlock('内容', record.textContent ? record.textContent.trim() : '')
      }
      if (
        (record.title ? record.title.trim() : '').length <= 0 &&
        (record.quoteText ? record.quoteText.trim() : '').length <= 0 &&
        (record.textContent ? record.textContent.trim() : '').length <= 0
      ) {
        Text('该条灵感暂无可展示内容')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
      }

      Row({ space: 8 }) {
        if (!this.isEditing(record.id)) {
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(12)
                .fontColor([$r('app.color.text_primary')])
              Text(this.getEditButtonLabel(record))
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_primary'))
            }
          }
            .backgroundColor('rgba(120,120,120,0.14)')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => this.startEdit(record))
        } else {
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(12)
                .fontColor(['#FFFFFF'])
              Text(this.savingEdit ? '保存中...' : '保存')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor('#FFFFFF')
            }
          }
            .backgroundColor('#2563EB')
            .enabled(!this.savingEdit)
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              this.saveEdit();
            })

          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([$r('app.color.text_primary')])
              Text('取消')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_primary'))
            }
          }
            .backgroundColor('rgba(120,120,120,0.14)')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => this.cancelEdit())
        }

        if (this.normalizeRecordType(record) === UnifiedAnnotationType.BOOKMARK) {
          Button() {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(12)
                .fontColor(['#2563EB'])
              Text('跳转')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor('#2563EB')
            }
          }
            .backgroundColor('rgba(37,99,235,0.10)')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              void this.openRecordLocation(record);
            })
        }

        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right'))
              .fontSize(12)
              .fontColor(['#2563EB'])
            Text('分享')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor('#2563EB')
          }
        }
          .backgroundColor('rgba(37,99,235,0.10)')
          .borderRadius(10)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick(() => this.showShareActionMenuForRecord(record))

        Button() {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(12)
              .fontColor(['#F04438'])
            Text('删除')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor('#F04438')
          }
        }
          .backgroundColor('rgba(240,68,56,0.10)')
          .borderRadius(10)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick(() => this.deleteRecord(record.id))
      }
      .width('100%')

      if (this.isEditing(record.id)) {
        Column({ space: 8 }) {
          if (this.normalizeRecordType(record) === UnifiedAnnotationType.BOOKMARK) {
            TextInput({ text: this.editingTitleText, placeholder: '编辑书签标题' })
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .width('100%')
              .onChange((value: string) => {
                this.editingTitleText = value;
              })
          }

          TextInput({
            text: this.editingBodyText,
            placeholder: this.normalizeRecordType(record) === UnifiedAnnotationType.BOOKMARK
              ? '编辑补充备注'
              : '编辑想法内容'
          })
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .width('100%')
            .onChange((value: string) => {
              this.editingBodyText = value;
            })
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .backgroundColor('rgba(37,99,235,0.08)')
        .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut })
          .combine(TransitionEffect.translate({ y: 6 })))
      }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph(this.isSelected(record.id) ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(18)
          .fontColor([this.isSelected(record.id) ? '#2563EB' : $r('app.color.text_secondary')])
      }
      .width(34)
      .height(34)
      .backgroundColor('rgba(120,120,120,0.08)')
      .borderRadius(17)
      .onClick(() => {
        this.toggleSelection(record.id);
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .border({ width: 1, color: 'rgba(120,120,120,0.16)' })
    .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
      .combine(TransitionEffect.translate({ y: 8 })))
  }

  @Builder
  private buildSharePreviewOverlay() {
    if (this.showSharePreview) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .backgroundColor('rgba(0,0,0,0.44)')
          .opacity(this.sharePreviewMaskOpacity)
          .onClick(() => this.closeSharePreview())
          .expandSafeArea(
            [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
            [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
          )
          .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }))

        Column({ space: 12 }) {
          Row() {
            Column({ space: 2 }) {
              Text(this.sharePreviewTitle)
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.sharePreviewFormat === 'markdown' ? 'Markdown 格式' : '纯文本格式')
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(12)
                  .fontColor([$r('app.color.text_primary')])
                Text('关闭')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_primary'))
              }
            }
              .backgroundColor('rgba(120,120,120,0.14)')
              .borderRadius(10)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => this.closeSharePreview())
          }
          .width('100%')

          Scroll() {
            Text(this.sharePreviewContent)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Start)
              .width('100%')
              .padding(10)
          }
          .width('100%')
          .layoutWeight(1)
          .borderRadius(12)
          .backgroundColor('rgba(120,120,120,0.08)')
          .scrollBar(BarState.Auto)

          Row({ space: 8 }) {
            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right'))
                  .fontSize(12)
                  .fontColor(['#FFFFFF'])
                Text('系统分享')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor('#FFFFFF')
              }
            }
              .backgroundColor('#2563EB')
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                void this.sharePreviewBySystemAndClose();
              })

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(12)
                  .fontColor([$r('app.color.text_primary')])
                Text('复制并关闭')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_primary'))
              }
            }
              .backgroundColor('rgba(120,120,120,0.14)')
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.copySharePreviewAndClose();
              })

            Button() {
              Row({ space: 4 }) {
                SymbolGlyph($r('sys.symbol.doc_text'))
                  .fontSize(12)
                  .fontColor([$r('app.color.text_primary')])
                Text('仅复制')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_primary'))
              }
            }
              .backgroundColor('rgba(120,120,120,0.14)')
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.copyTextToClipboard(this.sharePreviewContent, '分享内容已复制');
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width('90%')
        .height('68%')
        .constraintSize({ maxWidth: MAX_CONTENT_WIDTH })
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.settings_panel_background'))
        .border({ width: 1, color: 'rgba(120,120,120,0.18)' })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.20)', offsetX: 0, offsetY: 8 })
        .opacity(this.sharePreviewPanelOpacity)
        .scale({ x: this.sharePreviewPanelScale, y: this.sharePreviewPanelScale })
        .zIndex(2)
        .position({ x: '50%', y: '50%' })
        .translate({ x: '-50%', y: '-50%' })
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
          .combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .align(Alignment.Center)
      .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
      .zIndex(999)
    }
  }

  private showAnnotationCenterHelp(): void {
    const helpContent = `# 灵感页帮助

## 页面说明

灵感页用于统一管理当前内容（小说、漫画、电子书）的书签、划线、想法，支持筛选、编辑、拼接和分享。

## 基础操作

- 使用顶部筛选按钮查看不同类型的灵感。
- 点击“选择”可加入批量操作。
- 点击“全选”可快速选中当前筛选下全部灵感。

## 编辑能力

- 书签可编辑标题与补充备注。
- 划线可编辑关联想法（若无想法可直接补充）。
- 想法支持直接修改内容并保存。

## 分享能力

- 支持单条分享和批量分享。
- 支持文本与 Markdown 两种导出格式。
- 可先进入“分享预览”检查内容，再复制发送。

## 删除与安全
- 删除灵感后会立即刷新列表。
- 删除划线会联动处理其关联想法，避免孤立数据。
- 建议在分享前检查敏感内容，避免误发。`;

    getHelpPanelManagerV2().showInlineHelp('灵感页帮助', helpContent);
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: $r('app.color.settings_panel_background'),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 12 }) {

            this.buildContentSelectorSection()

            Row({ space: 8 }) {
              this.buildFilterButton('全部', 'all')
              this.buildFilterButton('书签', 'bookmark')
              this.buildFilterButton('划线', 'highlight')
              this.buildFilterButton('想法', 'thought')
            }
            .width('100%')
            .id('guide_inspiration_filters')

            Row() {
              Text(`已选${this.selectedRecordIds.length} 条`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor($r('app.color.text_secondary'))

              Blank()

              Button() {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
                    .fontSize(12)
                    .fontColor([$r('app.color.text_primary')])
                  Text('全选')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.text_primary'))
                }
              }
                .backgroundColor('rgba(120,120,120,0.14)')
                .borderRadius(10)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .onClick(() => this.toggleSelectAllVisible())

              Button() {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right'))
                    .fontSize(12)
                    .fontColor(['#2563EB'])
                  Text('分享已选')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor('#2563EB')
                }
              }
                .backgroundColor('rgba(37,99,235,0.10)')
                .borderRadius(10)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ left: 8 })
                .onClick(() => this.showShareActionMenuForSelected())

              Button() {
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.doc_text'))
                    .fontSize(12)
                    .fontColor(['#FFFFFF'])
                  Text('拼接复制')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor('#FFFFFF')
                }
              }
                .backgroundColor('#2563EB')
                .borderRadius(10)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ left: 8 })
                .onClick(() => {
                  this.copySelectedRecords('plain');
                })
            }
            .width('100%')
            .id('guide_inspiration_actions')

            Column() {
              if (this.isLoading) {
                Column({ space: 10 }) {
                  LoadingProgress()
                    .width(30)
                    .height(30)
                    .color($r('app.color.accent_primary'))
                  Text('正在加载灵感...')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ top: 40, bottom: 40 })
                .justifyContent(FlexAlign.Center)
              } else if (this.visibleRecords.length <= 0) {
                Column({ space: 10 }) {
                  Text('当前筛选下暂无灵感')
                    .fontSize(15)
                    .fontFamily(this.appFontFamily)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ top: 40, bottom: 40 })
                .justifyContent(FlexAlign.Center)
              } else {
                Column({ space: 10 }) {
                  ForEach(this.visibleRecords, (record: UnifiedAnnotationRecord) => {
                    this.buildRecordCard(record)
                  }, (record: UnifiedAnnotationRecord) => record.id)
                }
                .width('100%')
              }
            }
            .width('100%')
            .opacity(this.listOpacity)
            .translate({ y: this.listOffsetY })
            .id('guide_inspiration_record_list')

            Blank().height(32)
          }
          .width('100%')
          .constraintSize({ maxWidth: MAX_CONTENT_WIDTH })
          .padding({ left: 16, right: 16, bottom: 24 })
          .opacity(this.pageEnterOpacity)
          .translate({ y: this.pageEnterOffsetY })
        }
        .width('100%')
        .height('100%')
        .id('guide_inspiration_scroll')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        this.buildSharePreviewOverlay()

        if (this.appGuideStep) {
          AppGuideOverlay({
            visible: this.appGuideStep !== null,
            title: this.appGuideStep.title,
            message: this.appGuideStep.message,
            progressText: this.appGuideManager.getCurrentProgressText(),
            nextButtonText: this.appGuideStep.nextButtonText ?? '下一步',
            cardPosition: this.appGuideStep.cardPosition,
            highlightRect: this.appGuideHighlightRect,
            showSkip: this.appGuideStep.showSkip !== false,
            onNext: () => {
              this.handlePageGuideNext();
            },
            onSkip: () => {
              this.handlePageGuideSkip();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .id('guide_inspiration_root')
      .expandSafeArea(
        [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
      )
    }
    .hideTitleBar(false)
    .mode(NavDestinationMode.STANDARD)
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: $r('app.color.settings_panel_background')
          }
        }
      },
      content: {
        title: {
          mainTitle: '灵感'
        },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showAnnotationCenterHelp();
              }
            }
          }]
        }
      }
    })
    .backgroundColor(Color.Transparent)
    .onWillAppear(() => {
      this.captureCurrentDisplayMode('onWillAppear');
      this.ensureNormalDisplayMode('onWillAppear');
    })
    .onWillShow(() => {
      this.ensureNormalDisplayMode('onWillShow');
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      this.captureCurrentDisplayMode('onReady');
      this.ensureNormalDisplayMode('onReady');
      const params = this.parsePageParams(context);
      this.readerContext = params.readerContext || null;
      const paramContentType = params.contentType;
      const paramContentId = params.contentId ? params.contentId.trim() : '';
      const hasInitialSelection = !!paramContentType && paramContentId.length > 0;
      if (hasInitialSelection) {
        this.contentType = paramContentType as UnifiedContentType;
        this.contentId = paramContentId;
        this.contentTitle = params.contentTitle && params.contentTitle.trim().length > 0
          ? params.contentTitle
          : this.getContentTypeLabel(this.contentType);
        this.selectedContentKey = this.buildContentKey(this.contentType, this.contentId);
        this.selectedContentName = this.contentTitle;
        this.selectedContentCoverUri = '';
      } else {
        this.contentId = '';
        this.contentTitle = '全部内容';
        this.selectedContentKey = '';
        this.selectedContentName = '全部内容';
        this.selectedContentCoverUri = '';
      }
      setTimeout(() => {
        void this.refreshPageGuide('onReady');
      }, 80);
      this.startPageEnterAnimation();
      void this.loadAnnotations();
    })
    .onAppear(() => {
      this.ensureNormalDisplayMode('onAppear');
    })
    .onBackPressed(() => {
      if (this.showSharePreview) {
        this.closeSharePreview();
        return true;
      }
      if (this.isReturningToReader()) {
        this.forceReaderImmersiveModeBeforeExit('onBackPressed');
      } else {
        this.restorePreviousDisplayMode('onBackPressed');
      }
      this.pathStack.pop();
      return true;
    })
  }
}



