import { SafeUtils } from '../../Utils/SafeUtils';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import { ChapterInfo, ComicDetailInfo, ComicInfo, PageInfo } from './SourceExecutor';
import {
  KomgaAuthorOption,
  KomgaBrowseFilters,
  KomgaBrowseRequest,
  KomgaCollectionOption,
  KomgaConfig,
  KomgaContentType,
  KomgaFeedType,
  KomgaFilterOptions,
  KomgaInstanceConfig,
  KomgaLibraryOption,
  KomgaPaginatedResult,
  KomgaReadStatusMode,
  KomgaSortKey,
  KOMGA_DEFAULT_CHAPTER_TEMPLATE,
  createDefaultKomgaBrowseFilters,
  createEmptyKomgaFilterOptions
} from './KomgaModels';
import { loadKomgaConfig, saveKomgaConfig } from './KomgaConfigStore';

const TAG = 'KomgaSource';

interface KomgaPageWrapperDto<T> {
  content: T[];
  empty: boolean;
  first: boolean;
  last: boolean;
  number: number;
  numberOfElements: number;
  size: number;
  totalElements: number;
  totalPages: number;
}

interface KomgaCollectionDto {
  id: string;
  name: string;
}

interface KomgaSeriesMetadataDto {
  status: string;
  title: string;
  titleSort: string;
  summary: string;
  publisher: string;
  language: string;
  genres: string[];
  tags: string[];
  totalBookCount?: number;
}

interface KomgaBookMetadataAggregationDto {
  authors: KomgaAuthorOption[];
  tags: string[];
  releaseDate?: string;
  summary: string;
}

interface KomgaSeriesDto {
  id: string;
  libraryId: string;
  name: string;
  created?: string;
  lastModified?: string;
  fileLastModified: string;
  booksCount: number;
  metadata: KomgaSeriesMetadataDto;
  booksMetadata: KomgaBookMetadataAggregationDto;
}

interface KomgaBookMetadataDto {
  title: string;
  summary: string;
  number: string;
  numberSort: number;
  releaseDate?: string;
  authors: KomgaAuthorOption[];
  tags: string[];
}

interface KomgaMediaDto {
  status: string;
  mediaType: string;
  pagesCount: number;
  mediaProfile: string;
  epubDivinaCompatible: boolean;
}

interface KomgaBookDto {
  id: string;
  seriesId: string;
  seriesTitle: string;
  name: string;
  number: number;
  created?: string;
  lastModified?: string;
  fileLastModified: string;
  sizeBytes: number;
  size: string;
  media: KomgaMediaDto;
  metadata: KomgaBookMetadataDto;
}

interface KomgaReadListDto {
  id: string;
  name: string;
  summary: string;
  bookIds: string[];
  createdDate: string;
  lastModifiedDate: string;
}

interface KomgaPageDto {
  number: number;
  fileName: string;
  mediaType: string;
}

type KomgaItemDto = KomgaSeriesDto | KomgaReadListDto | KomgaBookDto;

interface KomgaChapterTemplateValues {
  title: string;
  seriesTitle: string;
  number: string;
  createdDate: string;
  releaseDate: string;
  size: string;
  sizeBytes: string;
}

const SUPPORTED_IMAGE_TYPES: string[] = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/jxl',
  'image/heif',
  'image/avif'
];

let komgaSourceInstance: KomgaSource | null = null;

export function getKomgaSource(): KomgaSource {
  if (!komgaSourceInstance) {
    komgaSourceInstance = new KomgaSource();
  }
  return komgaSourceInstance;
}

export class KomgaSource {
  private config: KomgaConfig | null = null;
  private filterCache: Map<string, KomgaFilterOptions> = new Map();

  public async initialize(forceReload: boolean = false): Promise<void> {
    if (this.config && !forceReload) {
      return;
    }

    this.config = await loadKomgaConfig();
    if (forceReload) {
      this.filterCache.clear();
    }
    logger.info(TAG, `KomgaSource 配置已加载: forceReload=${forceReload}, instances=${this.getConfig().instances.length}, currentInstance=${this.getConfig().currentInstanceId || '-'}`);
  }

  public async reloadConfig(): Promise<void> {
    await this.initialize(true);
  }

  public getConfig(): KomgaConfig {
    return this.config || {
      instances: [],
      currentInstanceId: '',
      useBrowsePageAsEntry: true
    };
  }

  public isConfigured(): boolean {
    const instance = this.getCurrentInstance();
    return !!instance && instance.serverUrl.trim().length > 0;
  }

  public getInstances(): KomgaInstanceConfig[] {
    return this.getConfig().instances.filter(item => item.enabled !== false);
  }

  public getCurrentInstance(): KomgaInstanceConfig | null {
    const config = this.getConfig();
    const matched = config.instances.find(item => item.id === config.currentInstanceId && item.enabled !== false);
    return matched || config.instances.find(item => item.enabled !== false) || null;
  }

  public async setCurrentInstance(instanceId: string): Promise<boolean> {
    await this.initialize();
    const currentConfig = this.getConfig();
    const nextConfig: KomgaConfig = {
      instances: currentConfig.instances,
      currentInstanceId: instanceId,
      useBrowsePageAsEntry: currentConfig.useBrowsePageAsEntry
    };
    const success = await saveKomgaConfig(nextConfig);
    if (success) {
      this.config = await loadKomgaConfig();
    }
    return success;
  }

  public getServerUrl(instanceId?: string): string {
    const instance = this.resolveInstance(instanceId);
    return instance ? this.normalizeServerUrl(instance.serverUrl) : '';
  }

  public getImageHeaders(instanceId?: string): Record<string, string> {
    const instance = this.resolveInstance(instanceId);
    if (!instance) {
      return {};
    }
    return this.buildHeaders(instance, true);
  }

  public async getFilterOptions(instanceId?: string, forceRefresh: boolean = false): Promise<KomgaFilterOptions> {
    await this.initialize();
    const instance = this.resolveInstance(instanceId);
    if (!instance) {
      return createEmptyKomgaFilterOptions();
    }

    const cacheKey = instance.id;
    if (!forceRefresh && this.filterCache.has(cacheKey)) {
      logger.debug(TAG, `KomgaSource 筛选项缓存命中: instanceId=${cacheKey}`);
      return this.filterCache.get(cacheKey)!;
    }

    logger.info(TAG, `KomgaSource 加载筛选项: instanceId=${instance.id}, forceRefresh=${forceRefresh}`);
    const libraries = await this.requestJson<KomgaLibraryOption[]>('/api/v1/libraries', instance);
    const collectionsResponse = await this.requestJson<KomgaPageWrapperDto<KomgaCollectionDto>>('/api/v1/collections?unpaged=true', instance);
    const genres = await this.requestJson<string[]>('/api/v1/genres', instance);
    const tags = await this.requestJson<string[]>('/api/v1/tags', instance);
    const publishers = await this.requestJson<string[]>('/api/v1/publishers', instance);
    const authors = await this.requestJson<KomgaAuthorOption[]>('/api/v1/authors', instance);

    const authorsByRole: Record<string, KomgaAuthorOption[]> = {};
    (authors || []).forEach(author => {
      const role = author.role || 'other';
      const currentList = authorsByRole[role] || [];
      currentList.push(author);
      authorsByRole[role] = currentList;
    });

    const options: KomgaFilterOptions = {
      libraries: libraries || [],
      collections: this.toCollectionOptions(collectionsResponse?.content || []),
      genres: genres || [],
      tags: tags || [],
      publishers: publishers || [],
      authorsByRole: authorsByRole
    };

    this.filterCache.set(cacheKey, options);
    logger.info(TAG, `KomgaSource 筛选项加载完成: instanceId=${instance.id}, libraries=${options.libraries.length}, collections=${options.collections.length}, genres=${options.genres.length}, tags=${options.tags.length}, publishers=${options.publishers.length}`);
    return options;
  }

  public async browse(request: KomgaBrowseRequest): Promise<KomgaPaginatedResult<ComicInfo>> {
    await this.initialize();
    const instance = this.resolveInstance(request.instanceId);
    if (!instance) {
      return { items: [], totalCount: 0, hasMore: false };
    }

    const path = this.resolveBrowsePath(request.contentType, request.filters.collectionId);
    const queryParts: string[] = [];
    queryParts.push(`search=${encodeURIComponent(request.query || '')}`);
    queryParts.push(`page=${Math.max(0, request.page - 1)}`);
    queryParts.push('deleted=false');
    this.appendLibraryQueryParts(queryParts, instance, request.filters);
    this.appendFilterQueryParts(queryParts, request.filters);
    const sortParam = this.buildSortParam(request.feedType, request.contentType, request.filters.sortKey);
    if (sortParam.length > 0) {
      queryParts.push(`sort=${encodeURIComponent(sortParam)}`);
    }

    const queryText = queryParts.join('&');
    const separator = path.includes('?') ? '&' : '?';
    logger.info(TAG, `KomgaSource 浏览请求: instanceId=${instance.id}, path=${path}, contentType=${request.contentType}, feed=${request.feedType}, page=${request.page}, query="${request.query}", queryText=${queryText}`);
    const response = await this.requestJson<KomgaPageWrapperDto<KomgaItemDto>>(`${path}${separator}${queryText}`, instance);
    if (!response) {
      logger.warn(TAG, `KomgaSource 浏览结果为空: instanceId=${instance.id}, path=${path}`);
      return { items: [], totalCount: 0, hasMore: false };
    }

    const wrapper: KomgaPageWrapperDto<KomgaItemDto> = response;
    const items = (wrapper.content || []).map((item: KomgaItemDto) => this.toComicInfo(item, request.contentType, instance.id, instance));
    logger.info(TAG, `KomgaSource 浏览响应: instanceId=${instance.id}, received=${items.length}, total=${wrapper.totalElements || items.length}, hasMore=${wrapper.last === false}`);
    return {
      items: items,
      totalCount: wrapper.totalElements || items.length,
      hasMore: wrapper.last === false
    };
  }

  public async getMangaDetail(itemId: string, contentType: KomgaContentType, instanceId?: string): Promise<ComicDetailInfo | null> {
    await this.initialize();
    const instance = this.resolveInstance(instanceId);
    if (!instance) {
      return null;
    }

    logger.info(TAG, `KomgaSource 加载详情: instanceId=${instance.id}, itemId=${itemId}, contentType=${contentType}`);
    const detailResponse = await this.requestJson<KomgaItemDto>(this.buildItemPath(contentType, itemId), instance);
    if (!detailResponse) {
      logger.warn(TAG, `KomgaSource 详情为空: instanceId=${instance.id}, itemId=${itemId}, contentType=${contentType}`);
      return null;
    }

    const detail = this.toComicDetail(detailResponse, contentType, instance.id, instance);
    detail.chapters = await this.getChaptersForItem(itemId, contentType, instance);
    logger.info(TAG, `KomgaSource 详情加载完成: instanceId=${instance.id}, itemId=${itemId}, chapters=${detail.chapters ? detail.chapters.length : 0}`);
    return detail;
  }

  public async getPages(bookId: string, instanceId?: string): Promise<PageInfo[]> {
    await this.initialize();
    const instance = this.resolveInstance(instanceId);
    if (!instance) {
      return [];
    }

    logger.info(TAG, `KomgaSource 加载页面列表: instanceId=${instance.id}, bookId=${bookId}`);
    const response = await this.requestJson<KomgaPageDto[]>(`/api/v1/books/${bookId}/pages`, instance);
    if (!response || response.length <= 0) {
      logger.warn(TAG, `KomgaSource 页面列表为空: instanceId=${instance.id}, bookId=${bookId}`);
      return [];
    }

    const headers = this.buildHeaders(instance, true);
    const serverUrl = this.normalizeServerUrl(instance.serverUrl);
    const pages = response.map(page => {
      const needsConvert = !SUPPORTED_IMAGE_TYPES.includes(page.mediaType);
      const url = `${serverUrl}/api/v1/books/${bookId}/pages/${page.number}${needsConvert ? '?convert=png' : ''}`;
      const result: PageInfo = {
        url: url
      };
      (result as ESObject)['headers'] = headers;
      return result;
    });
    logger.info(TAG, `KomgaSource 页面列表加载完成: instanceId=${instance.id}, bookId=${bookId}, count=${pages.length}`);
    return pages;
  }

  private async getChaptersForItem(itemId: string, contentType: KomgaContentType, instance: KomgaInstanceConfig): Promise<ChapterInfo[]> {
    if (contentType === 'BOOKS') {
      const response = await this.requestJson<KomgaBookDto>(`/api/v1/books/${itemId}?unpaged=true&media_status=READY&deleted=false`, instance);
      if (!response) {
        return [];
      }
      return [this.toChapterInfo(response, true, 0, instance)];
    }

    const response = await this.requestJson<KomgaPageWrapperDto<KomgaBookDto>>(
      `${this.buildItemPath(contentType, itemId)}/books?unpaged=true&media_status=READY&deleted=false`,
      instance
    );
    const books = response?.content || [];
    const isReadList = contentType === 'READLISTS';

    return books
      .filter((book: KomgaBookDto) => {
        const media = book.media ? book.media : this.createDefaultMedia();
        return media.mediaProfile !== 'EPUB' || media.epubDivinaCompatible;
      })
      .map((book: KomgaBookDto, index: number) => this.toChapterInfo(book, isReadList, index, instance))
      .sort((left, right) => {
        const leftNumber = Number((left as ESObject)['chapterNumber'] || 0);
        const rightNumber = Number((right as ESObject)['chapterNumber'] || 0);
        return rightNumber - leftNumber;
      });
  }

  private toComicInfo(raw: KomgaItemDto, contentType: KomgaContentType, instanceId: string, instance: KomgaInstanceConfig): ComicInfo {
    const serverUrl = this.normalizeServerUrl(instance.serverUrl);

    if (contentType === 'READLISTS') {
      const dto = raw as KomgaReadListDto;
      const result: ComicInfo = {
        id: dto.id,
        title: dto.name,
        description: dto.summary,
        coverUrl: `${serverUrl}/api/v1/readlists/${dto.id}/thumbnail`,
        status: 'UNKNOWN',
        url: `${serverUrl}/api/v1/readlists/${dto.id}`,
        instanceId: instanceId
      };

      (result as ESObject)['contentType'] = 'READLISTS';
      (result as ESObject)['instanceId'] = instanceId;
      (result as ESObject)['bookCount'] = dto.bookIds?.length || 0;
      return result;
    }

    if (contentType === 'BOOKS') {
      const dto = raw as KomgaBookDto;
      const metadata = this.getBookMetadata(dto);
      const result: ComicInfo = {
        id: dto.id,
        title: metadata.title,
        author: (metadata.authors || []).map(item => item.name).join(', '),
        description: metadata.summary,
        coverUrl: `${serverUrl}/api/v1/books/${dto.id}/thumbnail`,
        status: 'UNKNOWN',
        tags: this.uniqueStrings(metadata.tags || []),
        url: `${serverUrl}/api/v1/books/${dto.id}`,
        instanceId: instanceId
      };

      (result as ESObject)['contentType'] = 'BOOKS';
      (result as ESObject)['instanceId'] = instanceId;
      (result as ESObject)['seriesTitle'] = dto.seriesTitle || '';
      (result as ESObject)['pageCount'] = dto.media?.pagesCount || 0;
      (result as ESObject)['size'] = dto.size || '';
      return result;
    }

    const dto = raw as KomgaSeriesDto;
    const metadata = this.getSeriesMetadata(dto);
    const booksMetadata = this.getBooksMetadata(dto);
    const authorMap = this.groupAuthors(booksMetadata.authors || []);
    const tags = this.buildSeriesTags(metadata, booksMetadata);

    const result: ComicInfo = {
      id: dto.id,
      title: metadata.title,
      author: authorMap['writer'] || authorMap['penciller'] || '',
      description: metadata.summary || booksMetadata.summary,
      coverUrl: `${serverUrl}/api/v1/series/${dto.id}/thumbnail`,
      status: this.mapSeriesStatus(metadata.status, dto.booksCount, metadata.totalBookCount),
      tags: tags,
      url: `${serverUrl}/api/v1/series/${dto.id}`,
      instanceId: instanceId
    };

    (result as ESObject)['contentType'] = 'SERIES';
    (result as ESObject)['instanceId'] = instanceId;
    (result as ESObject)['publisher'] = metadata.publisher || '';
    (result as ESObject)['language'] = metadata.language || '';
    (result as ESObject)['booksCount'] = dto.booksCount;
    (result as ESObject)['authorsByRole'] = authorMap;
    return result;
  }

  private toComicDetail(raw: KomgaItemDto, contentType: KomgaContentType, instanceId: string, instance: KomgaInstanceConfig): ComicDetailInfo {
    const baseInfo = this.toComicInfo(raw, contentType, instanceId, instance);
    const detail: ComicDetailInfo = {
      id: baseInfo.id,
      title: baseInfo.title,
      author: baseInfo.author,
      coverUrl: baseInfo.coverUrl,
      description: baseInfo.description,
      status: baseInfo.status,
      tags: baseInfo.tags,
      url: baseInfo.url,
      updateTime: baseInfo.updateTime,
      chapters: []
    };

    if (contentType === 'SERIES') {
      const dto = raw as KomgaSeriesDto;
      const metadata = this.getSeriesMetadata(dto);
      const booksMetadata = this.getBooksMetadata(dto);
      (detail as ESObject)['publisher'] = metadata.publisher || '';
      (detail as ESObject)['language'] = metadata.language || '';
      (detail as ESObject)['summary'] = metadata.summary || booksMetadata.summary || '';
      (detail as ESObject)['releaseDate'] = booksMetadata.releaseDate || '';
    } else if (contentType === 'BOOKS') {
      const dto = raw as KomgaBookDto;
      const metadata = this.getBookMetadata(dto);
      (detail as ESObject)['seriesTitle'] = dto.seriesTitle || '';
      (detail as ESObject)['summary'] = metadata.summary || '';
      (detail as ESObject)['releaseDate'] = metadata.releaseDate || '';
      (detail as ESObject)['pageCount'] = dto.media?.pagesCount || 0;
      (detail as ESObject)['size'] = dto.size || '';
    } else {
      const dto = raw as KomgaReadListDto;
      (detail as ESObject)['summary'] = dto.summary || '';
      (detail as ESObject)['bookCount'] = dto.bookIds?.length || 0;
    }

    return detail;
  }

  private toChapterInfo(book: KomgaBookDto, isReadList: boolean, index: number, instance: KomgaInstanceConfig): ChapterInfo {
    const metadata = this.getBookMetadata(book);

    const serverUrl = this.normalizeServerUrl(instance.serverUrl);
    const chapterInfo: ChapterInfo = {
      id: book.id,
      title: this.formatChapterName(book, metadata, isReadList, instance.chapterTitleTemplate || KOMGA_DEFAULT_CHAPTER_TEMPLATE),
      updateTime: this.parseDateValue(metadata.releaseDate) || this.parseDateValue(book.created) || this.parseDateValue(book.fileLastModified),
      coverUrl: `${serverUrl}/api/v1/books/${book.id}/thumbnail`,
      instanceId: instance.id
    };

    (chapterInfo as ESObject)['chapterNumber'] = isReadList ? index + 1 : (metadata.numberSort || 0);
    (chapterInfo as ESObject)['seriesTitle'] = book.seriesTitle;
    (chapterInfo as ESObject)['pageCount'] = book.media?.pagesCount || 0;
    return chapterInfo;
  }

  private formatChapterName(
    book: KomgaBookDto,
    metadata: KomgaBookMetadataDto,
    isReadList: boolean,
    template: string
  ): string {
    const values: KomgaChapterTemplateValues = {
      title: metadata.title || book.name || '',
      seriesTitle: book.seriesTitle || '',
      number: metadata.number || '',
      createdDate: book.created || '',
      releaseDate: metadata.releaseDate || '',
      size: book.size || '',
      sizeBytes: String(book.sizeBytes || 0)
    };

    const safeTemplate = template.trim().length > 0 ? template : KOMGA_DEFAULT_CHAPTER_TEMPLATE;
    let title = safeTemplate;
    title = title.replace(/\{title\}/g, values.title);
    title = title.replace(/\{seriesTitle\}/g, values.seriesTitle);
    title = title.replace(/\{number\}/g, values.number);
    title = title.replace(/\{createdDate\}/g, values.createdDate);
    title = title.replace(/\{releaseDate\}/g, values.releaseDate);
    title = title.replace(/\{size\}/g, values.size);
    title = title.replace(/\{sizeBytes\}/g, values.sizeBytes);

    if (isReadList) {
      return `${book.seriesTitle} ${title}`.trim();
    }
    return title.trim();
  }

  private mapSeriesStatus(status: string, booksCount: number, totalBookCount?: number): string {
    if (status === 'ENDED' && totalBookCount !== undefined && booksCount < totalBookCount) {
      return 'PUBLISHING_FINISHED';
    }

    switch (status) {
      case 'ENDED':
        return 'COMPLETED';
      case 'ONGOING':
        return 'ONGOING';
      case 'ABANDONED':
        return 'CANCELLED';
      case 'HIATUS':
        return 'ON_HIATUS';
      default:
        return 'UNKNOWN';
    }
  }

  private resolveBrowsePath(contentType: KomgaContentType, collectionId: string): string {
    if (contentType === 'SERIES' && collectionId.trim().length > 0) {
      return `/api/v1/collections/${collectionId}/series`;
    }

    switch (contentType) {
      case 'READLISTS':
        return '/api/v1/readlists';
      case 'BOOKS':
        return '/api/v1/books';
      default:
        return '/api/v1/series';
    }
  }

  private buildItemPath(contentType: KomgaContentType, itemId: string): string {
    switch (contentType) {
      case 'READLISTS':
        return `/api/v1/readlists/${itemId}`;
      case 'BOOKS':
        return `/api/v1/books/${itemId}`;
      default:
        return `/api/v1/series/${itemId}`;
    }
  }

  private appendLibraryQueryParts(queryParts: string[], instance: KomgaInstanceConfig, filters: KomgaBrowseFilters): void {
    const selectedLibraryIds = filters.selectedLibraryIds.length > 0 ? filters.selectedLibraryIds : instance.defaultLibraryIds;
    if (selectedLibraryIds.length > 0) {
      queryParts.push(`library_id=${encodeURIComponent(selectedLibraryIds.join(','))}`);
    }
  }

  private appendFilterQueryParts(queryParts: string[], filters: KomgaBrowseFilters): void {
    this.appendReadStatusQueryParts(queryParts, filters.readStatusMode);
    this.appendCsvQueryParts(queryParts, 'status', filters.selectedStatuses);
    this.appendCsvQueryParts(queryParts, 'genre', filters.selectedGenres);
    this.appendCsvQueryParts(queryParts, 'tag', filters.selectedTags);
    this.appendCsvQueryParts(queryParts, 'publisher', filters.selectedPublishers);
    if (filters.selectedAuthorRole.trim().length > 0 && filters.selectedAuthorName.trim().length > 0) {
      queryParts.push(`author=${encodeURIComponent(`${filters.selectedAuthorName},${filters.selectedAuthorRole}`)}`);
    }
  }

  private appendReadStatusQueryParts(queryParts: string[], mode: KomgaReadStatusMode): void {
    if (mode === 'UNREAD') {
      queryParts.push('read_status=UNREAD');
      queryParts.push('read_status=IN_PROGRESS');
      return;
    }
    if (mode === 'IN_PROGRESS') {
      queryParts.push('read_status=IN_PROGRESS');
      return;
    }
    if (mode === 'READ') {
      queryParts.push('read_status=READ');
    }
  }

  private appendCsvQueryParts(queryParts: string[], key: string, values: string[]): void {
    if (values.length <= 0) {
      return;
    }
    queryParts.push(`${encodeURIComponent(key)}=${encodeURIComponent(values.join(','))}`);
  }

  private buildSortParam(feedType: KomgaFeedType, contentType: KomgaContentType, sortKey: KomgaSortKey): string {
    let effectiveSort: KomgaSortKey = sortKey;
    if (feedType === 'LATEST' && sortKey === createDefaultKomgaBrowseFilters().sortKey) {
      effectiveSort = 'DATE_UPDATED';
    }
    if (feedType === 'POPULAR' && sortKey === createDefaultKomgaBrowseFilters().sortKey) {
      effectiveSort = 'ALPHABETICAL';
    }

    switch (effectiveSort) {
      case 'RELEVANCE':
        return 'relevance,desc';
      case 'ALPHABETICAL':
        return contentType === 'SERIES' ? 'metadata.titleSort,asc' : 'name,asc';
      case 'DATE_ADDED':
        return 'createdDate,desc';
      case 'DATE_UPDATED':
        return 'lastModifiedDate,desc';
      case 'RANDOM':
        return 'random,desc';
      default:
        return '';
    }
  }

  private resolveInstance(instanceId?: string): KomgaInstanceConfig | null {
    const config = this.getConfig();
    if (instanceId && instanceId.length > 0) {
      const instance = config.instances.find(item => item.id === instanceId && item.enabled !== false);
      if (instance) {
        return instance;
      }
    }
    return this.getCurrentInstance();
  }

  private buildHeaders(instance: KomgaInstanceConfig, isImageRequest: boolean = false): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': isImageRequest ? 'image/*,*/*;q=0.8' : 'application/json',
      'User-Agent': 'ManXiaKomga/1.0'
    };

    if (instance.authMode === 'API_KEY' && instance.apiKey.trim().length > 0) {
      headers['X-API-Key'] = instance.apiKey.trim();
    } else if (instance.authMode === 'BASIC' && instance.username.trim().length > 0) {
      headers['Authorization'] = `Basic ${this.base64Encode(`${instance.username}:${instance.password}`)}`;
    }

    return headers;
  }

  private async requestJson<T>(pathOrUrl: string, instance: KomgaInstanceConfig): Promise<T | null> {
    const serverUrl = this.normalizeServerUrl(instance.serverUrl);
    if (serverUrl.length <= 0) {
      logger.warn(TAG, `Komga 请求被跳过，服务器地址为空: instanceId=${instance.id}`);
      return null;
    }

    const requestUrl = pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')
      ? pathOrUrl
      : `${serverUrl}${pathOrUrl.startsWith('/') ? pathOrUrl : `/${pathOrUrl}`}`;

    const request = http.createHttp();
    try {
      logger.debug(TAG, `Komga 请求开始: instanceId=${instance.id}, url=${requestUrl}`);
      const response = await request.request(requestUrl, {
        method: http.RequestMethod.GET,
        header: this.buildHeaders(instance),
        connectTimeout: 30000,
        readTimeout: 30000
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        logger.error(TAG, `Komga 请求失败: ${response.responseCode} ${requestUrl}`);
        return null;
      }

      logger.debug(TAG, `Komga 请求成功: code=${response.responseCode}, url=${requestUrl}`);
      if (typeof response.result === 'string') {
        return SafeUtils.parseObj(response.result) as T;
      }
      return response.result as T;
    } catch (error) {
      logger.error(TAG, `Komga 请求异常: ${requestUrl} ${String(error)}`);
      return null;
    } finally {
      request.destroy();
    }
  }

  private normalizeServerUrl(rawServerUrl: string): string {
    const raw = rawServerUrl.trim();
    if (raw.length <= 0) {
      return '';
    }
    const hasScheme = /^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//.test(raw);
    const withScheme = hasScheme ? raw : `http://${raw}`;
    return withScheme.endsWith('/') ? withScheme.substring(0, withScheme.length - 1) : withScheme;
  }

  private uniqueStrings(values: string[]): string[] {
    const result: string[] = [];
    values.forEach(value => {
      if (value && !result.includes(value)) {
        result.push(value);
      }
    });
    return result;
  }

  private toCollectionOptions(items: KomgaCollectionDto[]): KomgaCollectionOption[] {
    return items.map((item: KomgaCollectionDto) => {
      const option: KomgaCollectionOption = {
        id: item.id,
        name: item.name
      };
      return option;
    });
  }

  private getSeriesMetadata(dto: KomgaSeriesDto): KomgaSeriesMetadataDto {
    if (dto.metadata) {
      return dto.metadata;
    }

    const metadata: KomgaSeriesMetadataDto = {
      status: 'UNKNOWN',
      title: dto.name || '',
      titleSort: dto.name || '',
      summary: '',
      publisher: '',
      language: '',
      genres: [],
      tags: []
    };
    return metadata;
  }

  private getBooksMetadata(dto: KomgaSeriesDto): KomgaBookMetadataAggregationDto {
    if (dto.booksMetadata) {
      return dto.booksMetadata;
    }

    const booksMetadata: KomgaBookMetadataAggregationDto = {
      authors: [],
      tags: [],
      releaseDate: '',
      summary: ''
    };
    return booksMetadata;
  }

  private getBookMetadata(book: KomgaBookDto): KomgaBookMetadataDto {
    if (book.metadata) {
      return book.metadata;
    }

    const metadata: KomgaBookMetadataDto = {
      title: book.name || '',
      summary: '',
      number: '',
      numberSort: 0,
      releaseDate: '',
      authors: [],
      tags: []
    };
    return metadata;
  }

  private createDefaultMedia(): KomgaMediaDto {
    const media: KomgaMediaDto = {
      status: 'READY',
      mediaType: 'image/jpeg',
      pagesCount: 0,
      mediaProfile: 'DIVINA',
      epubDivinaCompatible: false
    };
    return media;
  }

  private buildSeriesTags(
    metadata: KomgaSeriesMetadataDto,
    booksMetadata: KomgaBookMetadataAggregationDto
  ): string[] {
    const values: string[] = [];
    this.appendUniqueStrings(values, metadata.genres);
    this.appendUniqueStrings(values, metadata.tags);
    this.appendUniqueStrings(values, booksMetadata.tags);
    return values;
  }

  private appendUniqueStrings(target: string[], values?: string[]): void {
    if (!values || values.length <= 0) {
      return;
    }
    values.forEach((value: string) => {
      if (value && !target.includes(value)) {
        target.push(value);
      }
    });
  }

  private groupAuthors(authors: KomgaAuthorOption[]): Record<string, string> {
    const map: Record<string, string[]> = {};
    authors.forEach(author => {
      const key = author.role || 'other';
      const currentList = map[key] || [];
      if (!currentList.includes(author.name)) {
        currentList.push(author.name);
      }
      map[key] = currentList;
    });

    const result: Record<string, string> = {};
    Object.keys(map).forEach(key => {
      result[key] = map[key].join(', ');
    });
    return result;
  }

  private parseDateValue(value?: string): number {
    if (!value || value.trim().length <= 0) {
      return 0;
    }
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private base64Encode(input: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let index = 0;

    while (index < input.length) {
      const a = input.charCodeAt(index++);
      const b = index < input.length ? input.charCodeAt(index++) : 0;
      const c = index < input.length ? input.charCodeAt(index++) : 0;
      const triplet = (a << 16) | (b << 8) | c;

      result += chars.charAt((triplet >> 18) & 0x3F);
      result += chars.charAt((triplet >> 12) & 0x3F);
      result += index > input.length + 1 ? '=' : chars.charAt((triplet >> 6) & 0x3F);
      result += index > input.length ? '=' : chars.charAt(triplet & 0x3F);
    }

    return result;
  }
}
