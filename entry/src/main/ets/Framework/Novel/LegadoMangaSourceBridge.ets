/**
 * Bridges Legado IMAGE book sources into the existing online manga pipeline.
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { md5Hash } from 'manxia_core/src/main/ets/Utils/CryptoUtils';
import { DataManager, OnlineComicSourceSaveInput, OnlineChapterInfoInput, OnlinePageInfoInput } from '../Data/DataManager';
import { ComicSourceDatabaseRecord } from 'manxia_core/src/main/ets/Framework/Database/DatabaseTypes';
import { ComicInfo } from '../Source/SourceExecutor';
import { DownloadStatus, MangaStatus, ReadingStatus } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';
import {
  ImageSourceType,
  Manga,
  MangaChapter,
  MangaImageRequestHeader,
  MangaMetadata,
  MangaPage,
  ReadingProgress
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { DEFAULT_READING_SETTINGS } from 'manxia_core/src/main/ets/Models/MangaModels';
import { NovelSearchResult } from 'manxia_core/src/main/ets/Models/NovelModels';
import { PageInfo as SourcePageInfo, PageRequestHeader } from 'manxia_source_engine/src/main/ets/Framework/WebView/MangaSourceTypes';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import {
  LegadoBook,
  LegadoBookSource,
  LegadoBookSourceType,
  LegadoChapter
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { LegadoUrlAnalyzer, ParsedUrlRequest } from './LegadoUrlAnalyzer';
import { LegadoJsSourceEffects } from './LegadoJsEngine';
import { getNovelDataManager } from './NovelDataManager';
import { getNovelSourceManager, NovelSourceManager } from './NovelSourceManager';
import {
  LegadoWorkflowContentResult,
  LegadoWorkflowOutputKind
} from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCompatibilityTypes';
import { getNovelLoginManager } from './NovelLoginManager';
import { getCookieStore } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoCookieStore';
import { LegadoMangaExtractedImage, LegadoMangaImageExtractor } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoMangaImageExtractor';
import { HtmlFormatter } from 'manxia_novel/src/main/ets/Framework/Novel/HtmlFormatter';

const TAG = 'LegadoMangaSourceBridge';
const LEGADO_MANGA_PKG_PREFIX = 'legado.image.';
const LEGADO_MANGA_ADAPTER = 'legado-image';

/**
 * comic_source.name is globally unique while Legado permits several IMAGE
 * sources to share a visible bookSourceName. Keep the original name in the
 * bridge metadata and give its internal manga-source record a stable identity.
 */
export function buildLegadoImageVirtualSourceRecordName(bookSourceName: string, pkg: string): string {
  const normalizedName = bookSourceName.trim();
  const packageIdentity = pkg.startsWith(LEGADO_MANGA_PKG_PREFIX)
    ? pkg.substring(LEGADO_MANGA_PKG_PREFIX.length)
    : pkg;
  const displayName = normalizedName.length > 0 ? normalizedName : 'Unnamed Legado IMAGE source';
  return `Legado IMAGE [${packageIdentity}] ${displayName}`;
}

export interface LegadoMangaVirtualSource {
  pkg: string;
  sourceId: number;
  sourceName: string;
  sourceUrl: string;
}

export interface LegadoMangaDetailResult {
  sourceId: number;
  sourcePkg: string;
  sourceName: string;
  source: LegadoBookSource;
  manga: Manga;
  chapters: MangaChapter[];
}

export interface LegadoMangaChapterResult {
  chapter: MangaChapter;
  originalChapter: LegadoChapter;
}

export interface LegadoMangaPageResult {
  pages: SourcePageInfo[];
  mangaPages: MangaPage[];
}

export interface LegadoImageRequestContext {
  source: LegadoBookSource;
  pageUrl: string;
  chapterUrl: string;
}

interface LegadoVirtualMetadata {
  id: string;
  name: string;
  baseUrl: string;
  version: string;
  description: string;
  language: string;
  type: string;
  adapter: string;
  bookSourceUrl: string;
  bookSourceName: string;
  bookSourceType: number;
  nsfw: boolean;
}

interface LegadoVirtualConfig {
  metadata: LegadoVirtualMetadata;
  capabilities: LegadoVirtualCapabilities;
  network: LegadoVirtualNetwork;
  workflows: LegadoVirtualWorkflows;
}

interface LegadoVirtualCapabilities {
  search: boolean;
  detail: boolean;
  chapters: boolean;
  pages: boolean;
}

interface LegadoVirtualNetwork {
  sourceHeader: string;
}

interface LegadoVirtualWorkflows {
  adapter: string;
}

interface LegadoHeaderMap {
  User_Agent?: string;
  UserAgent?: string;
  userAgent?: string;
  USER_AGENT?: string;
  Referer?: string;
  referer?: string;
  Referrer?: string;
  referrer?: string;
  Origin?: string;
  origin?: string;
  Accept?: string;
  accept?: string;
  Cookie?: string;
  cookie?: string;
  Authorization?: string;
  authorization?: string;
  AcceptLanguage?: string;
  acceptLanguage?: string;
  ACCEPT_LANGUAGE?: string;
  CacheControl?: string;
  cacheControl?: string;
  CACHE_CONTROL?: string;
  Pragma?: string;
  pragma?: string;
}

interface LegadoImageResolvedRequest {
  imageUrl: string;
  headers: PageRequestHeader[];
}

export class LegadoMangaSourceBridge {
  private static instance: LegadoMangaSourceBridge | null = null;
  private dataManager: DataManager = DataManager.getInstance();
  private sourceManager: NovelSourceManager = getNovelSourceManager();
  private virtualSourceSyncTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  private constructor() {}

  static getInstance(): LegadoMangaSourceBridge {
    if (!LegadoMangaSourceBridge.instance) {
      LegadoMangaSourceBridge.instance = new LegadoMangaSourceBridge();
    }
    return LegadoMangaSourceBridge.instance;
  }

  /**
   * 重置单例状态，清理长生命周期 Map
   * 应用退出、用户注销或图源全量重置时调用
   */
  reset(): void {
    this.virtualSourceSyncTasks.clear();
  }

  static isLegadoMangaPkg(pkg: string | undefined | null): boolean {
    return !!pkg && pkg.startsWith(LEGADO_MANGA_PKG_PREFIX);
  }

  async ensureVirtualComicSource(source: LegadoBookSource): Promise<LegadoMangaVirtualSource | null> {
    if (source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return null;
    }

    const pkg = await this.buildVirtualPkg(source.bookSourceUrl);
    await this.synchronizeVirtualComicSource(pkg, source);

    const sourceRecord = await this.dataManager.getComicSourceByPkg(pkg);
    if (!sourceRecord) {
      logger.warn(TAG, `虚拟漫画图源创建后未找到记录: pkg=${pkg}`);
      return null;
    }
    if (!this.validateVirtualComicSourceIdentity(sourceRecord, pkg, source)) {
      logger.error(TAG, `IMAGE 虚拟图源身份校验失败，拒绝使用导入记录: pkg=${pkg}`);
      return null;
    }

    await this.dataManager.setComicSourceEnabledByPkg(pkg, source.enabled !== false);
    await this.dataManager.restoreOnlineComicSourceByPkg(pkg);

    const sourceId = Number(sourceRecord.id);
    const result: LegadoMangaVirtualSource = {
      pkg: pkg,
      sourceId: Number.isFinite(sourceId) ? sourceId : 0,
      sourceName: source.bookSourceName,
      sourceUrl: source.bookSourceUrl
    };
    return result;
  }

  /**
   * Import and page-opening paths can ask for the same virtual source at the
   * same time. Serialize per package so the check-then-insert import API never
   * races itself on the database's unique constraints.
   */
  private async synchronizeVirtualComicSource(pkg: string, source: LegadoBookSource): Promise<void> {
    const previousTask = this.virtualSourceSyncTasks.get(pkg);
    const task: Promise<void> = previousTask === undefined
      ? this.persistVirtualComicSource(pkg, source)
      : previousTask.then(() => this.persistVirtualComicSource(pkg, source));
    this.virtualSourceSyncTasks.set(pkg, task);
    try {
      await task;
    } finally {
      if (this.virtualSourceSyncTasks.get(pkg) === task) {
        this.virtualSourceSyncTasks.delete(pkg);
      }
    }
  }

  private async persistVirtualComicSource(pkg: string, source: LegadoBookSource): Promise<void> {
    const config = this.buildVirtualConfig(pkg, source);
    const jsonContent = JSON.stringify(config);
    await this.dataManager.importSourceFromJSON(jsonContent);
  }

  async disableVirtualComicSource(source: LegadoBookSource): Promise<void> {
    if (source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return;
    }
    const pkg = await this.buildVirtualPkg(source.bookSourceUrl);
    await this.dataManager.setComicSourceEnabledByPkg(pkg, false);
  }

  async isLegadoMangaSourceId(sourceId: number): Promise<boolean> {
    if (!sourceId || sourceId <= 0) {
      return false;
    }
    const record = await this.dataManager.getComicSourceById(sourceId);
    return this.isLegadoMangaRecord(record);
  }

  /**
   * Resolves the lossless V2 document identity for IMAGE transport evidence.
   * The raw document and source URL remain inside the compatibility store.
   */
  async getRawSourceDocumentSha256(sourceId: number): Promise<string> {
    if (sourceId <= 0) {
      return '';
    }
    try {
      const source: LegadoBookSource | null = await this.resolveLegadoSourceByComicSourceId(sourceId);
      if (source === null) {
        return '';
      }
      const record = await getNovelDataManager().getCompatibilityRecord(source.bookSourceUrl);
      if (record === null || record.rawSha256.length <= 0) {
        return '';
      }
      return record.rawSha256.toUpperCase();
    } catch (error) {
      logger.warn(TAG, `读取 IMAGE V2 原始文档身份失败: sourceId=${sourceId}, error=${String(error)}`);
      return '';
    }
  }

  /**
   * A legacy-created comic cache is not V2 workflow evidence. During a full
   * V2 cutover, detail navigation must execute the live IMAGE bridge rather
   * than silently rendering that stale record.
   */
  async shouldForceNetworkDetail(sourceId: number): Promise<boolean> {
    const source = await this.resolveLegadoSourceByComicSourceId(sourceId);
    if (source === null) {
      return false;
    }
    return this.isV2LegacyFallbackBlocked(source.bookSourceUrl);
  }

  isLegadoMangaRecord(record: ComicSourceDatabaseRecord | null): boolean {
    if (!record) {
      return false;
    }
    if (LegadoMangaSourceBridge.isLegadoMangaPkg(record.pkg)) {
      return true;
    }
    const configText = typeof record.configJson === 'string' ? record.configJson : '';
    return configText.indexOf(`"adapter":"${LEGADO_MANGA_ADAPTER}"`) >= 0 ||
      configText.indexOf(`"adapter": "${LEGADO_MANGA_ADAPTER}"`) >= 0;
  }

  async loadDetailWithChapters(
    sourceId: number,
    bookUrl: string,
    cachedTitle?: string,
    cachedCover?: string
  ): Promise<LegadoMangaDetailResult | null> {
    logger.warn(
      TAG,
      `IMAGE_V2_DETAIL_ENTER sourceId=${sourceId};bookUrlLength=${bookUrl.length};` +
      `cachedTitle=${(cachedTitle || '').length > 0};cachedCover=${(cachedCover || '').length > 0}`
    );
    const source = await this.resolveLegadoSourceByComicSourceId(sourceId);
    if (!source) {
      logger.warn(TAG, `IMAGE_V2_DETAIL_SOURCE_MISSING sourceId=${sourceId}`);
      return null;
    }

    let book = await this.getBookInfo(source, bookUrl);
    logger.warn(
      TAG,
      `IMAGE_V2_DETAIL_BOOK_INFO sourceId=${sourceId};present=${book !== null};` +
      `nameLength=${book ? book.name.length : 0};authorLength=${book ? book.author.length : 0};` +
      `tocUrlLength=${book && book.tocUrl ? book.tocUrl.length : 0}`
    );
    if (!book) {
      if (this.isV2LegacyFallbackBlocked(source.bookSourceUrl)) {
        logger.warn(TAG, `V2 详情工作流失败，拒绝 IMAGE 桥接 fallback: source=${source.bookSourceUrl}`);
        return null;
      }
      book = this.buildFallbackBook(source, bookUrl, cachedTitle, cachedCover);
    }

    const chapters = await this.getChapterList(source, book);
    logger.warn(TAG, `IMAGE_V2_DETAIL_TOC sourceId=${sourceId};chapterCount=${chapters.length}`);
    const sourceRecord = await this.dataManager.getComicSourceById(sourceId);
    const sourcePkg = sourceRecord && sourceRecord.pkg ? String(sourceRecord.pkg) : await this.buildVirtualPkg(source.bookSourceUrl);
    const mangaChapters = this.convertChapters(book.bookUrl, chapters);
    const manga = this.buildManga(sourceId, sourcePkg, source, book, mangaChapters);

    await this.saveMangaToDatabase(sourceId, sourcePkg, source, book, manga, mangaChapters);

    const result: LegadoMangaDetailResult = {
      sourceId: sourceId,
      sourcePkg: sourcePkg,
      sourceName: source.bookSourceName,
      source: source,
      manga: manga,
      chapters: mangaChapters
    };
    return result;
  }

  async search(sourceId: number, keyword: string, page: number = 1): Promise<ComicInfo[]> {
    const source = await this.resolveLegadoSourceByComicSourceId(sourceId);
    if (!source) {
      return [];
    }
    const books = await this.sourceManager.search(source.bookSourceUrl, keyword, page);
    return this.convertNovelSearchResultsToComicInfo(books);
  }

  async exploreDefault(sourceId: number, page: number = 1): Promise<ComicInfo[]> {
    const source = await this.resolveLegadoSourceByComicSourceId(sourceId);
    if (!source) {
      return [];
    }
    if (!source.exploreUrl || source.exploreUrl.trim().length <= 0) {
      return [];
    }
    const kinds = await this.sourceManager.getExploreKindsAsync(source.bookSourceUrl);
    if (kinds.length <= 0 || kinds[0].url.trim().length <= 0) {
      return [];
    }
    const books = await this.sourceManager.explore(source.bookSourceUrl, kinds[0].url, page);
    return this.convertNovelSearchResultsToComicInfo(books);
  }

  async loadPageList(
    sourceId: number,
    mangaExternalId: string,
    chapterExternalId: string
  ): Promise<LegadoMangaPageResult | null> {
    logger.info(TAG, `开始加载Legado漫画页面列表: sourceId=${sourceId}, manga=${mangaExternalId}, chapter=${chapterExternalId}`);
    const source = await this.resolveLegadoSourceByComicSourceId(sourceId);
    if (!source) {
      logger.warn(TAG, `无法解析Legado漫画虚拟图源: sourceId=${sourceId}`);
      return null;
    }
    const chapter = await this.resolveChapter(source, mangaExternalId, chapterExternalId);
    if (!chapter) {
      logger.warn(TAG, `无法定位Legado漫画章节: sourceId=${sourceId}, manga=${mangaExternalId}, chapter=${chapterExternalId}`);
      return null;
    }
    logger.info(TAG, `Legado漫画章节定位成功: source=${source.bookSourceName}, chapterTitle=${chapter.title}, chapterUrl=${chapter.url}`);

    const content = await this.getContent(source, chapter);
    const images: LegadoMangaExtractedImage[] =
      LegadoMangaImageExtractor.extractImages(content, chapter.url || mangaExternalId);
    logger.info(TAG, `Legado漫画正文解析完成: contentLength=${content.length}, images=${images.length}, chapterUrl=${chapter.url || mangaExternalId}`);
    const pages: SourcePageInfo[] = [];
    const mangaPages: MangaPage[] = [];

    for (let i = 0; i < images.length; i++) {
      const image = images[i];
      const resolvedRequest = await this.resolveImageRequestAsync(source, image.requestUrl, chapter.url || mangaExternalId);
      const imageUrl = resolvedRequest.imageUrl;
      const headers = resolvedRequest.headers;
      const pageInfo: SourcePageInfo = {
        page: i + 1,
        imageUrl: imageUrl,
        width: 0,
        height: 0,
        requestHeaders: headers
      };
      pages.push(pageInfo);
      mangaPages.push({
        id: `${chapterExternalId}_page_${i}`,
        index: i,
        sourceType: ImageSourceType.NETWORK,
        imagePath: imageUrl,
        imageUrl: imageUrl,
        width: 0,
        height: 0,
        fileSize: 0,
        requestHeaders: this.convertToMangaHeaders(headers),
        isLoaded: false
      });
    }
    if (pages.length <= 0) {
      logger.warn(TAG, `Legado漫画页面列表为空: sourceId=${sourceId}, manga=${mangaExternalId}, chapter=${chapterExternalId}, contentLength=${content.length}`);
    } else {
      logger.info(TAG, `Legado漫画页面列表加载完成: sourceId=${sourceId}, pages=${pages.length}`);
    }

    const result: LegadoMangaPageResult = {
      pages: pages,
      mangaPages: mangaPages
    };
    return result;
  }

  buildImageRequestHeaders(context: LegadoImageRequestContext): MangaImageRequestHeader[] {
    return this.convertToMangaHeaders(this.resolveImageRequest(context.source, context.pageUrl, context.chapterUrl).headers);
  }

  private async buildVirtualPkg(bookSourceUrl: string): Promise<string> {
    const hash = await md5Hash(bookSourceUrl);
    return `${LEGADO_MANGA_PKG_PREFIX}${hash.substring(0, 16)}`;
  }

  private buildVirtualConfig(pkg: string, source: LegadoBookSource): LegadoVirtualConfig {
    const metadata: LegadoVirtualMetadata = {
      id: pkg,
      name: buildLegadoImageVirtualSourceRecordName(source.bookSourceName, pkg),
      baseUrl: this.resolveBaseUrl(source.bookSourceUrl),
      version: String(source.lastUpdateTime || Date.now()),
      description: source.bookSourceComment || 'Legado IMAGE bridge source',
      language: 'zh-CN',
      type: 'manga',
      adapter: LEGADO_MANGA_ADAPTER,
      bookSourceUrl: source.bookSourceUrl,
      bookSourceName: source.bookSourceName,
      bookSourceType: LegadoBookSourceType.IMAGE,
      nsfw: source.isNSFW === true
    };
    const capabilities: LegadoVirtualCapabilities = {
      search: !!source.searchUrl,
      detail: true,
      chapters: true,
      pages: true
    };
    const network: LegadoVirtualNetwork = {
      sourceHeader: source.header || ''
    };
    const workflows: LegadoVirtualWorkflows = {
      adapter: LEGADO_MANGA_ADAPTER
    };
    return {
      metadata: metadata,
      capabilities: capabilities,
      network: network,
      workflows: workflows
    };
  }

  private resolveBaseUrl(sourceUrl: string): string {
    const trimmed = sourceUrl.trim();
    const match = trimmed.match(/^(https?:\/\/[^\/?#]+)/i);
    if (match && match.length > 1) {
      return match[1];
    }
    return trimmed;
  }

  private async resolveLegadoSourceByComicSourceId(sourceId: number): Promise<LegadoBookSource | null> {
    const record = await this.dataManager.getComicSourceById(sourceId);
    if (!this.isLegadoMangaRecord(record)) {
      return null;
    }
    if (!record || !record.pkg || record.pkg.trim().length <= 0) {
      logger.warn(TAG, `IMAGE 虚拟图源记录缺少稳定包名: sourceId=${sourceId}`);
      return null;
    }
    const bookSourceUrl = this.extractBookSourceUrl(record);
    if (!bookSourceUrl) {
      return null;
    }
    const source = await this.getLegadoSourceByUrl(bookSourceUrl);
    if (!source || source.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return null;
    }
    if (!this.validateVirtualComicSourceIdentity(record, record.pkg, source)) {
      logger.error(TAG, `IMAGE 虚拟图源身份不一致，拒绝数字 ID 解析: sourceId=${sourceId}`);
      return null;
    }
    return source;
  }

  /**
   * A numeric comic_source.id is only an address. The package and the
   * serialized Legado metadata are the identity contract that prevents a
   * neighboring IMAGE source from being selected after stale cache reuse.
   */
  private validateVirtualComicSourceIdentity(
    record: ComicSourceDatabaseRecord | null,
    expectedPkg: string,
    expectedSource: LegadoBookSource
  ): boolean {
    if (!record || !record.pkg || record.pkg !== expectedPkg) {
      return false;
    }
    if (!this.isLegadoMangaRecord(record)) {
      return false;
    }
    const config: LegadoVirtualConfig = SafeUtils.parseObj<LegadoVirtualConfig>(record.configJson);
    const metadata: LegadoVirtualMetadata | null = config ? config.metadata : null;
    const workflows: LegadoVirtualWorkflows | null = config ? config.workflows : null;
    if (!metadata || !workflows) {
      return false;
    }
    if (record.pkg !== expectedPkg || metadata.id !== expectedPkg) {
      return false;
    }
    if (metadata.bookSourceUrl !== expectedSource.bookSourceUrl) {
      return false;
    }
    if (metadata.bookSourceType !== LegadoBookSourceType.IMAGE) {
      return false;
    }
    if (metadata.adapter !== LEGADO_MANGA_ADAPTER || workflows.adapter !== LEGADO_MANGA_ADAPTER) {
      return false;
    }
    if (record.type !== undefined && record.type !== 'manga' && record.type !== 'image') {
      return false;
    }
    return true;
  }

  private extractBookSourceUrl(record: ComicSourceDatabaseRecord | null): string {
    if (!record || !record.configJson || typeof record.configJson !== 'string') {
      return '';
    }
    try {
      const config = SafeUtils.parseObj(record.configJson) as LegadoVirtualConfig;
      if (config && config.metadata && config.metadata.bookSourceUrl) {
        return String(config.metadata.bookSourceUrl);
      }
    } catch (error) {
      logger.warn(TAG, `解析Legado虚拟图源配置失败: ${String(error)}`);
    }
    return '';
  }

  private buildFallbackBook(
    source: LegadoBookSource,
    bookUrl: string,
    cachedTitle?: string,
    cachedCover?: string
  ): LegadoBook {
    return {
      id: `${source.bookSourceUrl}_${encodeURIComponent(bookUrl)}`,
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
      bookUrl: bookUrl,
      name: cachedTitle || bookUrl,
      author: '',
      intro: '',
      coverUrl: cachedCover || '',
      tocUrl: bookUrl,
      latestChapterTitle: '',
      wordCount: '',
      updateTime: Date.now(),
      type: LegadoBookSourceType.IMAGE,
      isNSFW: source.isNSFW === true
    };
  }

  private convertChapters(bookUrl: string, chapters: LegadoChapter[]): MangaChapter[] {
    const result: MangaChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const externalId = this.buildChapterExternalId(bookUrl, chapter, i);
      result.push({
        id: externalId,
        externalId: externalId,
        title: chapter.title || `第${i + 1}章`,
        chapterNumber: chapter.index >= 0 ? chapter.index : i,
        pages: [],
        totalPages: 0,
        publishDate: chapter.updateTime || Date.now(),
        language: 'zh-CN',
        scanlationGroup: '',
        isDownloaded: false,
        downloadStatus: DownloadStatus.PENDING,
        downloadProgress: 0
      });
    }
    return result;
  }

  private buildManga(
    sourceId: number,
    sourcePkg: string,
    source: LegadoBookSource,
    book: LegadoBook,
    chapters: MangaChapter[]
  ): Manga {
    const now = Date.now();
    const metadata: MangaMetadata = {
      authors: book.author ? [book.author] : [],
      artists: [],
      genres: this.parseGenres(book.kind),
      themes: [],
      demographics: [],
      publisher: '',
      serialization: ''
    };
    const readingProgress: ReadingProgress = {
      currentChapterId: '',
      currentPageIndex: 0,
      totalReadingTime: 0,
      lastReadAt: 0,
      readingStatus: ReadingStatus.UNREAD,
      readingPercentage: 0
    };
    return {
      id: book.bookUrl,
      title: book.name || book.bookUrl,
      alternativeTitles: [],
      description: book.intro || '',
      coverImagePath: book.coverUrl || '',
      coverSourceType: book.coverUrl ? ImageSourceType.NETWORK : ImageSourceType.RESOURCE,
      status: MangaStatus.UNKNOWN,
      metadata: metadata,
      chapters: chapters,
      readingProgress: readingProgress,
      bookmarks: [],
      readingSettings: DEFAULT_READING_SETTINGS,
      isFavorite: false,
      lastUpdatedAt: book.updateTime || now,
      sourceInfo: {
        sourceName: source.bookSourceName,
        sourceUrl: source.bookSourceUrl,
        sourceId: String(sourceId),
        sourcePkg: sourcePkg,
        externalId: book.bookUrl,
        sourceLanguage: 'zh-CN',
        requiresLogin: !!source.loginUrl,
        isNSFW: source.isNSFW === true
      },
      contentType: 'manga',
      isNSFW: source.isNSFW === true || book.isNSFW === true
    };
  }

  private async saveMangaToDatabase(
    sourceId: number,
    sourcePkg: string,
    source: LegadoBookSource,
    book: LegadoBook,
    manga: Manga,
    chapters: MangaChapter[]
  ): Promise<void> {
    const comicData: OnlineComicSourceSaveInput = {
      id: book.bookUrl,
      title: manga.title,
      author: book.author || '',
      description: manga.description || '',
      coverUrl: manga.coverImagePath || '',
      tags: manga.metadata.genres || [],
      rating: 0,
      updateTime: Date.now(),
      sourceName: source.bookSourceName,
      sourcePkg: sourcePkg,
      isNSFW: source.isNSFW === true || book.isNSFW === true,
      status: 'unknown',
      chapterCount: chapters.length
    };
    const internalComicId = await this.dataManager.saveOnlineComicFromSource(sourceId, comicData, book.bookUrl);
    manga.id = internalComicId;

    if (source.bookSourceType === LegadoBookSourceType.IMAGE && this.shouldReplaceExistingImageChapters(book, chapters)) {
      await this.dataManager.deleteOnlineChaptersAndPages(internalComicId);
    }

    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const chapterInput: OnlineChapterInfoInput = {
        comicId: internalComicId,
        externalId: chapter.externalId || chapter.id,
        title: chapter.title,
        chapterNumber: chapter.chapterNumber,
        url: chapter.externalId || chapter.id,
        pageCount: chapter.totalPages || 0,
        publishTime: typeof chapter.publishDate === 'number' ? chapter.publishDate : Date.now(),
        isDownloaded: false,
        downloadPath: undefined,
        index: i
      };
      const internalChapterId = await this.dataManager.addOnlineChapterInfo(chapterInput);
      chapter.id = internalChapterId;
    }
  }

  async savePagesToDatabase(chapterId: string, pages: SourcePageInfo[]): Promise<void> {
    await this.dataManager.deleteOnlineChapterPages(chapterId);
    const inputs: OnlinePageInfoInput[] = [];
    for (let i = 0; i < pages.length; i++) {
      const page = pages[i];
      inputs.push({
        chapterId: chapterId,
        pageNumber: i,
        imageUrl: page.imageUrl,
        requestHeaders: this.serializePageRequestHeaders(page.requestHeaders),
        width: page.width || 0,
        height: page.height || 0,
        fileSize: 0
      });
    }
    await this.dataManager.batchAddOnlinePages(chapterId, inputs);
  }

  private serializePageRequestHeaders(headers: PageRequestHeader[] | undefined): string {
    if (!headers || headers.length <= 0) {
      return '';
    }
    const normalized: PageRequestHeader[] = [];
    for (let i = 0; i < headers.length; i++) {
      const header = headers[i];
      if (!header) {
        continue;
      }
      const name = String(header.name || '').trim();
      const value = String(header.value || '').trim();
      if (name.length <= 0 || value.length <= 0) {
        continue;
      }
      normalized.push({
        name: name,
        value: value
      } as PageRequestHeader);
    }
    if (normalized.length <= 0) {
      return '';
    }
    return SafeUtils.stringifyJson(normalized, '');
  }

  private async resolveChapter(
    source: LegadoBookSource,
    mangaExternalId: string,
    chapterExternalId: string
  ): Promise<LegadoChapter | null> {
    const book = await this.getBookInfo(source, mangaExternalId);
    if (!book && this.isV2LegacyFallbackBlocked(source.bookSourceUrl)) {
      logger.warn(TAG, `V2 详情工作流失败，拒绝 IMAGE 章节解析 fallback: source=${source.bookSourceUrl}`);
      return null;
    }
    const actualBook = book || this.buildFallbackBook(source, mangaExternalId);
    const chapters = await this.getChapterList(source, actualBook);
    if (chapters.length <= 0 && this.isV2LegacyFallbackBlocked(source.bookSourceUrl)) {
      logger.warn(TAG, `V2 目录工作流失败，拒绝 IMAGE 缓存章节 fallback: source=${source.bookSourceUrl}`);
      return null;
    }
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      const externalId = this.buildChapterExternalId(mangaExternalId, chapter, i);
      if (externalId === chapterExternalId || chapter.url === chapterExternalId || chapter.id === chapterExternalId) {
        return chapter;
      }
    }
    if (source.bookSourceType === LegadoBookSourceType.IMAGE && chapters.length === 1 &&
      this.isSameUrlIdentity(actualBook.bookUrl, chapters[0].url)) {
      logger.warn(TAG, `Legado图片书源章节ID未命中，回退到详情页单章: manga=${mangaExternalId}, requested=${chapterExternalId}`);
      return chapters[0];
    }
    if (chapterExternalId.length > 0) {
      return {
        id: chapterExternalId,
        bookUrl: mangaExternalId,
        url: chapterExternalId,
        title: chapterExternalId,
        index: 0
      };
    }
    return null;
  }

  private async getLegadoSourceByUrl(bookSourceUrl: string): Promise<LegadoBookSource | null> {
    try {
      const sources = await getNovelDataManager().getAllSources();
      for (let i = 0; i < sources.length; i++) {
        const source = sources[i];
        if (source.bookSourceUrl === bookSourceUrl) {
          return source;
        }
      }
    } catch (error) {
      logger.warn(TAG, `读取Legado书源失败: ${String(error)}`);
    }
    return null;
  }

  private async getBookInfo(source: LegadoBookSource, bookUrl: string): Promise<LegadoBook | null> {
    return await this.sourceManager.getBookInfo(source.bookSourceUrl, bookUrl);
  }

  /** Keep IMAGE bridge fallback semantics inside the central V2 policy boundary. */
  private isV2LegacyFallbackBlocked(sourceId: string): boolean {
    return this.sourceManager.shouldBlockLegacyFallback(sourceId);
  }

  private async getChapterList(source: LegadoBookSource, book: LegadoBook): Promise<LegadoChapter[]> {
    const chapters = await this.sourceManager.getChapterList(source.bookSourceUrl, book);
    return await this.normalizeImageBookChapters(source, book, chapters);
  }

  private async getContentResult(
    source: LegadoBookSource,
    chapter: LegadoChapter
  ): Promise<LegadoWorkflowContentResult> {
    return await this.sourceManager.getContentWithResult(source.bookSourceUrl, chapter);
  }

  private async getContent(source: LegadoBookSource, chapter: LegadoChapter): Promise<string> {
    const result = await this.getContentResult(source, chapter);
    if (!result.handoff.isReady() || result.handoff.kind !== LegadoWorkflowOutputKind.IMAGE) {
      throw new Error(
        `V2_OUTPUT_HANDOFF_BLOCKED;workflow=image;kind=${result.handoff.kind};` +
        `status=${result.handoff.status};reason=${result.handoff.reasonCode}`
      );
    }
    return result.handoff.imageContent;
  }

  private async normalizeImageBookChapters(
    source: LegadoBookSource,
    book: LegadoBook,
    chapters: LegadoChapter[]
  ): Promise<LegadoChapter[]> {
    if (book.type !== LegadoBookSourceType.IMAGE) {
      return chapters;
    }
    const singleChapter = this.buildSingleImageBookChapter(book);
    const content = await this.getContent(source, singleChapter);
    const images = LegadoMangaImageExtractor.extractImages(content, singleChapter.url || book.bookUrl);
    if (images.length <= 0) {
      return chapters;
    }
    this.applyImageBookCoverFallback(book, images);
    if (!this.shouldPreferSingleImageBookChapter(book, chapters, images.length)) {
      return chapters;
    }
    logger.info(TAG, `Legado图片书源使用详情页作为单章: book=${book.name || book.bookUrl}, images=${images.length}, originalChapters=${chapters.length}`);
    return [singleChapter];
  }

  private applyImageBookCoverFallback(book: LegadoBook, images: LegadoMangaExtractedImage[]): void {
    const currentCover = book.coverUrl ? book.coverUrl.trim() : '';
    if (currentCover.length > 0) {
      return;
    }
    for (let i = 0; i < images.length; i++) {
      const image = images[i];
      const coverUrl = image.imageUrl ? image.imageUrl.trim() : '';
      if (this.isUsableImageCoverUrl(coverUrl)) {
        book.coverUrl = coverUrl;
        logger.info(TAG, `Legado图片书源使用首图作为封面: book=${book.name || book.bookUrl}, cover=${coverUrl}`);
        return;
      }
    }
  }

  private isUsableImageCoverUrl(url: string): boolean {
    if (!url || url.trim().length <= 0) {
      return false;
    }
    const normalized = url.trim().toLowerCase();
    if (normalized === '#' || normalized === 'about:blank' || normalized.startsWith('javascript:')) {
      return false;
    }
    if (normalized.startsWith('data:') && normalized.indexOf('data:image/') !== 0) {
      return false;
    }
    if (normalized.indexOf('img@src') >= 0 || normalized.indexOf('img@data-src') >= 0) {
      return false;
    }
    if (normalized.indexOf('placeholder') >= 0 || normalized.indexOf('blank.gif') >= 0 ||
      normalized.indexOf('spacer.gif') >= 0 || normalized.indexOf('transparent.gif') >= 0) {
      return false;
    }
    return true;
  }

  private buildSingleImageBookChapter(book: LegadoBook): LegadoChapter {
    const chapterUrl = book.tocUrl && book.tocUrl.trim().length > 0 ? book.tocUrl : book.bookUrl;
    const title = book.latestChapterTitle && book.latestChapterTitle.trim().length > 0
      ? book.latestChapterTitle
      : '全文';
    return {
      id: `${book.bookUrl}#full`,
      bookUrl: book.bookUrl,
      url: chapterUrl,
      requestUrlTemplate: book.tocRequestUrlTemplate || book.requestUrlTemplate || chapterUrl,
      requestCarrier: book.tocRequestCarrier || book.requestCarrier,
      title: title,
      index: 0,
      updateTime: book.updateTime || Date.now()
    };
  }

  private shouldPreferSingleImageBookChapter(book: LegadoBook, chapters: LegadoChapter[], imageCount: number): boolean {
    if (imageCount <= 1) {
      return false;
    }
    if (chapters.length <= 0) {
      return true;
    }
    if (chapters.length === 1 && this.isSameUrlIdentity(book.bookUrl, chapters[0].url)) {
      return true;
    }
    return !this.hasChapterWithBookIdentity(book, chapters);
  }

  private shouldReplaceExistingImageChapters(book: LegadoBook, chapters: MangaChapter[]): boolean {
    if (chapters.length !== 1) {
      return false;
    }
    const firstChapter = chapters[0];
    const chapterUrl = firstChapter.externalId || firstChapter.id;
    const expectedUrl = book.tocUrl && book.tocUrl.trim().length > 0 ? book.tocUrl : book.bookUrl;
    return this.isSameUrlIdentity(book.bookUrl, expectedUrl) && chapterUrl === expectedUrl;
  }

  private hasChapterWithBookIdentity(book: LegadoBook, chapters: LegadoChapter[]): boolean {
    const bookIdentity = this.normalizeUrlIdentity(book.bookUrl);
    if (bookIdentity.length <= 0) {
      return false;
    }
    for (let i = 0; i < chapters.length; i++) {
      const chapter = chapters[i];
      if (this.normalizeUrlIdentity(chapter.url) === bookIdentity) {
        return true;
      }
    }
    return false;
  }

  private isSameUrlIdentity(left: string, right: string): boolean {
    const leftIdentity = this.normalizeUrlIdentity(left);
    const rightIdentity = this.normalizeUrlIdentity(right);
    return leftIdentity.length > 0 && leftIdentity === rightIdentity;
  }

  private normalizeUrlIdentity(url: string): string {
    const trimmed = url ? url.trim() : '';
    if (trimmed.length <= 0) {
      return '';
    }
    let result = trimmed;
    const hashIndex = result.indexOf('#');
    if (hashIndex >= 0) {
      result = result.substring(0, hashIndex);
    }
    const queryIndex = result.indexOf('?');
    if (queryIndex >= 0) {
      result = result.substring(0, queryIndex);
    }
    while (result.endsWith('/') && result.length > 1) {
      result = result.substring(0, result.length - 1);
    }
    return result.toLowerCase();
  }

  private convertNovelSearchResultsToComicInfo(books: NovelSearchResult[]): ComicInfo[] {
    const result: ComicInfo[] = [];
    for (let i = 0; i < books.length; i++) {
      const book = books[i];
      result.push({
        id: book.bookUrl,
        title: book.name || '',
        author: book.author || '',
        coverUrl: book.coverUrl || '',
        description: book.intro || '',
        status: book.latestChapterTitle || '',
        tags: this.parseGenres(book.kind),
        url: book.bookUrl,
        updateTime: Date.now()
      });
    }
    return result;
  }

  private buildChapterExternalId(bookUrl: string, chapter: LegadoChapter, index: number): string {
    if (chapter.url && chapter.url.trim().length > 0) {
      return chapter.url;
    }
    const title = chapter.title || `chapter_${index}`;
    return `${bookUrl}#${index}#${encodeURIComponent(title)}`;
  }

  private parseGenres(kind?: string): string[] {
    if (!kind || kind.trim().length <= 0) {
      return [];
    }
    const parts = kind.split(/[,，;；\s]+/);
    const result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      if (part.length > 0 && !result.includes(part)) {
        result.push(part);
      }
    }
    return result;
  }

  private buildSourcePageRequestHeaders(
    source: LegadoBookSource,
    pageUrl: string,
    chapterUrl: string,
    resolvedPageRequest?: ParsedUrlRequest | null
  ): PageRequestHeader[] {
    const headerMap: Map<string, string> = new Map<string, string>();
    const pageRequest = resolvedPageRequest !== undefined ? resolvedPageRequest : this.analyzeImageRequestUrl(source, pageUrl, chapterUrl);
    this.mergeHeaderText(headerMap, source.header || '');
    const loginManager = getNovelLoginManager();
    this.mergeHeaderText(headerMap, loginManager.getLoginHeader(source.bookSourceUrl));
    if (pageRequest) {
      this.mergeHeaderRecord(headerMap, pageRequest.headers);
    }

    const requestUrl = pageRequest ? (pageRequest.requestUrl || pageRequest.url) : HtmlFormatter.getUrlWithoutLegadoOption(pageUrl);
    const storeCookie = getCookieStore().getCookie(requestUrl) || getCookieStore().getCookie(pageUrl) ||
      getCookieStore().getCookie(chapterUrl) || getCookieStore().getCookie(source.bookSourceUrl);
    const loginCookie = loginManager.getCookieString(source.bookSourceUrl);
    const mergedCookie = this.mergeCookieStrings(storeCookie, loginCookie);
    if (mergedCookie.length > 0 && !this.hasHeader(headerMap, 'Cookie')) {
      headerMap.set('Cookie', mergedCookie);
    }
    if (!this.hasHeader(headerMap, 'Referer') && chapterUrl.length > 0) {
      headerMap.set('Referer', chapterUrl);
    }
    if (!this.hasHeader(headerMap, 'User-Agent')) {
      headerMap.set('User-Agent', 'Mozilla/5.0 (HarmonyOS; Manxia Legado Manga Bridge)');
    }

    const result: PageRequestHeader[] = [];
    headerMap.forEach((value: string, key: string) => {
      if (key.length > 0 && value.length > 0) {
        result.push({ name: key, value: value });
      }
    });
    return result;
  }

  private resolveImageRequest(
    source: LegadoBookSource,
    pageUrl: string,
    chapterUrl: string
  ): LegadoImageResolvedRequest {
    const pageRequest = this.analyzeImageRequestUrl(source, pageUrl, chapterUrl);
    const imageUrl = pageRequest ? (pageRequest.requestUrl || pageRequest.url) : HtmlFormatter.getUrlWithoutLegadoOption(pageUrl);
    const headers = this.buildSourcePageRequestHeaders(source, pageUrl, chapterUrl, pageRequest);
    const result: LegadoImageResolvedRequest = {
      imageUrl: imageUrl,
      headers: headers
    };
    return result;
  }

  private async resolveImageRequestAsync(
    source: LegadoBookSource,
    pageUrl: string,
    chapterUrl: string
  ): Promise<LegadoImageResolvedRequest> {
    const pageRequest = await this.analyzeImageRequestUrlAsync(source, pageUrl, chapterUrl);
    const imageUrl = pageRequest ? (pageRequest.requestUrl || pageRequest.url) : HtmlFormatter.getUrlWithoutLegadoOption(pageUrl);
    const headers = this.buildSourcePageRequestHeaders(source, pageUrl, chapterUrl, pageRequest);
    const result: LegadoImageResolvedRequest = {
      imageUrl: imageUrl,
      headers: headers
    };
    return result;
  }

  private analyzeImageRequestUrl(
    source: LegadoBookSource,
    pageUrl: string,
    chapterUrl: string
  ): ParsedUrlRequest | null {
    if (!pageUrl || pageUrl.indexOf(',') < 0) {
      return null;
    }
    try {
      const analyzer = this.createImageUrlAnalyzer(source, chapterUrl);
      const request = analyzer.analyzeUrl(pageUrl);
      this.persistUrlAnalyzerSourceEffects(source, analyzer);
      return request;
    } catch (error) {
      logger.warn(TAG, `解析图片URL请求选项失败: ${String(error)}`);
      return null;
    }
  }

  private async analyzeImageRequestUrlAsync(
    source: LegadoBookSource,
    pageUrl: string,
    chapterUrl: string
  ): Promise<ParsedUrlRequest | null> {
    if (!pageUrl || pageUrl.indexOf(',') < 0) {
      return null;
    }
    try {
      const analyzer = this.createImageUrlAnalyzer(source, chapterUrl);
      const request = await analyzer.analyzeUrlAsync(pageUrl);
      this.persistUrlAnalyzerSourceEffects(source, analyzer);
      return request;
    } catch (error) {
      logger.warn(TAG, `异步解析图片URL请求选项失败: ${String(error)}`);
      return this.analyzeImageRequestUrl(source, pageUrl, chapterUrl);
    }
  }

  private createImageUrlAnalyzer(source: LegadoBookSource, chapterUrl: string): LegadoUrlAnalyzer {
    const analyzer = new LegadoUrlAnalyzer(chapterUrl, source.bookSourceUrl, source.jsLib || '');
    analyzer.setVariables(this.buildSourceContextVariables(source));
    return analyzer;
  }

  private persistUrlAnalyzerSourceEffects(source: LegadoBookSource, analyzer: LegadoUrlAnalyzer): void {
    this.persistSourceEffects(source, analyzer.getSourceEffectsSnapshot());
    analyzer.clearSourceEffects();
  }

  private persistSourceEffects(source: LegadoBookSource, effects?: LegadoJsSourceEffects): void {
    if (!effects) {
      return;
    }
    const sourceId = source.bookSourceUrl || '';
    if (sourceId.length <= 0) {
      return;
    }

    const loginManager = getNovelLoginManager();
    if (effects.loginInfo !== undefined) {
      loginManager.putLoginInfo(sourceId, effects.loginInfo);
    }
    if (effects.removeLoginHeader === true) {
      loginManager.removeLoginHeader(sourceId);
    }
    if (effects.loginHeader !== undefined) {
      loginManager.putLoginHeader(sourceId, effects.loginHeader);
    }
    if (effects.sourceVariable !== undefined) {
      loginManager.setSourceVariable(sourceId, effects.sourceVariable);
    }
    if (effects.data && effects.data.length > 0) {
      for (let i = 0; i < effects.data.length; i++) {
        const item = effects.data[i];
        if (!item || item.key.length <= 0) {
          continue;
        }
        loginManager.putSourceData(sourceId, item.key, item.value);
      }
    }
  }

  private buildSourceContextVariables(source: LegadoBookSource): Record<string, string> {
    const loginManager = getNovelLoginManager();
    const sourceId = source.bookSourceUrl || '';
    const sourceData = loginManager.getSourceDataSnapshot(sourceId);
    const variables: Record<string, string> = {};
    variables['sourceUrl'] = sourceId;
    variables['__source_bookSourceName'] = source.bookSourceName || '';
    variables['__source_bookSourceGroup'] = source.bookSourceGroup || '';
    variables['__source_bookSourceComment'] = source.bookSourceComment || '';
    variables['__source_header'] = source.header || '';
    variables['__source_loginUrl'] = source.loginUrl || '';
    variables['__source_loginUi'] = source.loginUi || '';
    variables['__source_loginCheckJs'] = source.loginCheckJs || '';
    variables['__source_variableComment'] = source.variableComment || '';
    variables['__loginInfo'] = loginManager.getLoginInfo(sourceId);
    variables['__loginHeader'] = loginManager.getLoginHeader(sourceId);
    variables['__sourceVariable'] = loginManager.getSourceVariable(sourceId);
    variables['__sourceData'] = SafeUtils.stringifyJson(sourceData, '{}');
    variables['cookie'] = loginManager.getCookieString(sourceId);
    return variables;
  }

  private mergeHeaderRecord(target: Map<string, string>, headers: Record<string, string>): void {
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = headers[key] ? String(headers[key]).trim() : '';
      if (key.length > 0 && value.length > 0) {
        this.setHeader(target, key, value);
      }
    }
  }

  private mergeHeaderText(target: Map<string, string>, headerText: string): void {
    const trimmed = headerText.trim();
    if (trimmed.length <= 0) {
      return;
    }
    const parsed = this.parseHeaderRecord(trimmed);
    if (parsed !== null) {
      this.mergeKnownHeader(target, 'User-Agent', parsed.User_Agent || parsed.UserAgent || parsed.userAgent || parsed.USER_AGENT);
      this.mergeKnownHeader(target, 'Referer', parsed.Referer || parsed.referer || parsed.Referrer || parsed.referrer);
      this.mergeKnownHeader(target, 'Origin', parsed.Origin || parsed.origin);
      this.mergeKnownHeader(target, 'Accept', parsed.Accept || parsed.accept);
      this.mergeKnownHeader(target, 'Cookie', parsed.Cookie || parsed.cookie);
      this.mergeKnownHeader(target, 'Authorization', parsed.Authorization || parsed.authorization);
      this.mergeKnownHeader(target, 'Accept-Language', parsed.AcceptLanguage || parsed.acceptLanguage || parsed.ACCEPT_LANGUAGE);
      this.mergeKnownHeader(target, 'Cache-Control', parsed.CacheControl || parsed.cacheControl || parsed.CACHE_CONTROL);
      this.mergeKnownHeader(target, 'Pragma', parsed.Pragma || parsed.pragma);
      this.mergeDashHeaderText(target, trimmed, 'User-Agent');
      this.mergeDashHeaderText(target, trimmed, 'Accept-Language');
      this.mergeDashHeaderText(target, trimmed, 'Cache-Control');
      this.mergeHeaderRecord(target, parsed as Record<string, string>);
      return;
    }

    const lines = trimmed.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      const splitIndex = line.indexOf(':');
      if (splitIndex > 0) {
        const key = line.substring(0, splitIndex).trim();
        const value = line.substring(splitIndex + 1).trim();
        if (key.length > 0 && value.length > 0) {
          this.setHeader(target, key, value);
        }
      }
    }
  }

  private parseHeaderRecord(headerText: string): LegadoHeaderMap | null {
    const trimmed = headerText.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return null;
    }

    const strictParsed = this.tryParseHeaderRecord(trimmed);
    if (strictParsed !== null) {
      return strictParsed;
    }

    const fixedHeader = trimmed
      .replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":')
      .replace(/([{,]\s*)'([^']+)'\s*:/g, '$1"$2":')
      .replace(/:\s*'([^'\\]*(?:\\.[^'\\]*)*)'/g, (match: string, value: string): string => {
        const escapedValue = value.replace(/"/g, '\\"');
        return `:"${escapedValue}"`;
      });
    const fixedParsed = this.tryParseHeaderRecord(fixedHeader);
    if (fixedParsed !== null) {
      return fixedParsed;
    }

    return this.parseHeaderPairs(trimmed);
  }

  private tryParseHeaderRecord(headerJson: string): LegadoHeaderMap | null {
    const parsed = SafeUtils.parseOptional<Record<string, Object>>(headerJson);
    if (parsed === undefined || parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return null;
    }
    const keys = Object.keys(parsed);
    if (keys.length <= 0) {
      return null;
    }
    const headers: Record<string, string> = {};
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = parsed[key];
      if (key.length > 0 && value !== undefined && value !== null) {
        headers[key] = String(value);
      }
    }
    if (Object.keys(headers).length <= 0) {
      return null;
    }
    return headers as LegadoHeaderMap;
  }

  private parseHeaderPairs(headerText: string): LegadoHeaderMap | null {
    let body = headerText.trim();
    if (body.startsWith('{') && body.endsWith('}')) {
      body = body.substring(1, body.length - 1);
    }
    const headers: Record<string, string> = {};
    const pairs = body.split(',');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const splitIndex = pair.indexOf(':');
      if (splitIndex <= 0) {
        continue;
      }
      const key = this.trimHeaderToken(pair.substring(0, splitIndex));
      const value = this.trimHeaderToken(pair.substring(splitIndex + 1));
      if (key.length > 0 && value.length > 0) {
        headers[key] = value;
      }
    }
    if (Object.keys(headers).length <= 0) {
      return null;
    }
    return headers as LegadoHeaderMap;
  }

  private trimHeaderToken(value: string): string {
    let result = value.trim();
    if (result.length >= 2) {
      const first = result.charAt(0);
      const last = result.charAt(result.length - 1);
      if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
        result = result.substring(1, result.length - 1).trim();
      }
    }
    return result;
  }

  private mergeCookieStrings(primaryCookie: string, secondaryCookie: string): string {
    const cookieMap: Map<string, string> = new Map<string, string>();
    this.collectCookiePairs(cookieMap, primaryCookie);
    this.collectCookiePairs(cookieMap, secondaryCookie);
    const parts: string[] = [];
    cookieMap.forEach((value: string, key: string) => {
      if (key.length > 0 && value.length > 0) {
        parts.push(`${key}=${value}`);
      }
    });
    return parts.join('; ');
  }

  private collectCookiePairs(target: Map<string, string>, cookieText: string): void {
    const trimmed = cookieText.trim();
    if (trimmed.length <= 0) {
      return;
    }
    const parts = trimmed.split(';');
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i].trim();
      const splitIndex = part.indexOf('=');
      if (splitIndex <= 0) {
        continue;
      }
      const key = part.substring(0, splitIndex).trim();
      const value = part.substring(splitIndex + 1).trim();
      if (key.length > 0 && value.length > 0) {
        target.set(key, value);
      }
    }
  }

  private mergeKnownHeader(target: Map<string, string>, key: string, value?: string): void {
    if (value && value.length > 0) {
      this.setHeader(target, key, value);
    }
  }

  private mergeDashHeaderText(target: Map<string, string>, headerText: string, key: string): void {
    const escapedKey = key.replace('-', '\\-');
    const pattern = new RegExp(`["']${escapedKey}["']\\s*:\\s*["']([^"']+)["']`, 'i');
    const match = headerText.match(pattern);
    if (match && match.length > 1 && match[1].length > 0) {
      this.setHeader(target, key, match[1]);
    }
  }

  private setHeader(target: Map<string, string>, key: string, value: string): void {
    const trimmedKey = key.trim();
    const trimmedValue = value.trim();
    if (trimmedKey.length <= 0 || trimmedValue.length <= 0) {
      return;
    }
    const existingKey = this.findHeaderKey(target, trimmedKey);
    if (existingKey.length > 0) {
      target.delete(existingKey);
    }
    target.set(trimmedKey, trimmedValue);
  }

  private findHeaderKey(headers: Map<string, string>, name: string): string {
    const target = name.toLowerCase();
    const keys = Array.from(headers.keys());
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === target) {
        return keys[i];
      }
    }
    return '';
  }

  private hasHeader(headers: Map<string, string>, name: string): boolean {
    return this.findHeaderKey(headers, name).length > 0;
  }

  private convertToMangaHeaders(headers: PageRequestHeader[]): MangaImageRequestHeader[] {
    const result: MangaImageRequestHeader[] = [];
    for (let i = 0; i < headers.length; i++) {
      result.push({
        name: headers[i].name,
        value: headers[i].value
      });
    }
    return result;
  }
}

export function getLegadoMangaSourceBridge(): LegadoMangaSourceBridge {
  return LegadoMangaSourceBridge.getInstance();
}
