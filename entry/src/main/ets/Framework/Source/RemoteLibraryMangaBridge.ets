import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import {
  DEFAULT_READING_SETTINGS,
  ImageSourceType,
  Manga,
  MangaBookmark,
  MangaChapter,
  MangaMetadata,
  MangaPage,
  MangaSourceInfo,
  ReadingProgress,
  ReadingSettings
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { DataManager, FavoriteInfo } from '../Data/DataManager';
import { DownloadStatus, ReadingStatus, StatusConverter } from 'manxia_core/src/main/ets/Framework/Types/StatusEnums';
import { ComicInfo, ComicDetailInfo, ChapterInfo, PageInfo } from './SourceExecutor';
import { getSuwayomiSourceExecutor, SuwayomiSourceExecutor } from './SuwayomiSourceExecutor';
import { getKomgaSourceExecutor, KomgaSourceExecutor } from './KomgaSourceExecutor';
import { createDefaultKomgaBrowseFilters, KomgaContentType, KomgaInstanceConfig } from './KomgaModels';
import { RequestHeaderEntry, RequestHeaders } from '../Cache/ImageCacheManager';

const TAG = 'RemoteLibraryMangaBridge';
const REMOTE_LIBRARY_PREF_NAME: string = 'remote_library_bridge_cache';
const REMOTE_LIBRARY_CACHE_KEY: string = 'remote_library_cache_v1';
const REMOTE_PROVIDER_SUWAYOMI: 'suwayomi' = 'suwayomi';
const REMOTE_PROVIDER_KOMGA: 'komga' = 'komga';
const SUWAYOMI_PAGE_SIZE: number = 100;
const KOMGA_GUARD_MAX_PAGES: number = 1000;
const KOMGA_CONTENT_TYPES: KomgaContentType[] = ['SERIES', 'READLISTS', 'BOOKS'];
const REMOTE_LIBRARY_REFRESH_TTL_MS: number = 24 * 60 * 60 * 1000;
const REMOTE_LIBRARY_CACHE_VERSION: number = 2;

export type RemoteProviderType = 'suwayomi' | 'komga';

export interface ParsedRemoteMangaId {
  providerType: RemoteProviderType;
  rawMangaId: string;
  instanceId?: string;
  contentType?: KomgaContentType;
}

export interface ParsedRemoteChapterId {
  providerType: RemoteProviderType;
  rawChapterId: string;
  instanceId?: string;
}

interface RemoteProviderCacheBucket {
  providerType: RemoteProviderType;
  signature: string;
  updatedAt: number;
  mangas: Manga[];
}

interface RemoteLibraryCacheData {
  version: number;
  updatedAt: number;
  mangas: Manga[];
  buckets: RemoteProviderCacheBucket[];
}

interface RemoteLibraryCachePayload {
  version?: number;
  updatedAt?: number;
  mangas?: Manga[];
  buckets?: RemoteProviderCacheBucket[];
}

interface RemoteProviderSignature {
  providerType: RemoteProviderType;
  signature: string;
  instanceId: string;
}

interface SuwayomiLibraryComicInfo extends ComicInfo {
  lastReadAt?: number;
  inLibraryAt?: number;
  unreadCount?: number;
  lastFetchedAt?: number;
}

interface KomgaLibraryComicInfo extends ComicInfo {
  contentType?: KomgaContentType;
  instanceId?: string;
  language?: string;
}

interface RemoteProviderContext {
  providerType: RemoteProviderType;
  rawMangaId: string;
  instanceId: string;
  contentType: KomgaContentType;
}

export class RemoteLibraryMangaBridge {
  private static instance: RemoteLibraryMangaBridge | null = null;
  private initialized: boolean = false;
  private cacheData: RemoteLibraryCacheData = {
    version: REMOTE_LIBRARY_CACHE_VERSION,
    updatedAt: 0,
    mangas: [],
    buckets: []
  };
  private readonly suwayomiExecutor: SuwayomiSourceExecutor = getSuwayomiSourceExecutor();
  private readonly komgaExecutor: KomgaSourceExecutor = getKomgaSourceExecutor();
  private readonly dataManager: DataManager = DataManager.getInstance();
  private refreshInFlight: Promise<Manga[]> | null = null;

  private constructor() {
  }

  public static getInstance(): RemoteLibraryMangaBridge {
    if (RemoteLibraryMangaBridge.instance === null) {
      RemoteLibraryMangaBridge.instance = new RemoteLibraryMangaBridge();
    }
    return RemoteLibraryMangaBridge.instance;
  }

  public static buildSuwayomiMangaId(rawMangaId: string): string {
    return `provider:suwayomi:manga:${rawMangaId}`;
  }

  public static buildSuwayomiChapterId(rawChapterId: string): string {
    return `provider:suwayomi:chapter:${rawChapterId}`;
  }

  public static buildKomgaMangaId(instanceId: string, contentType: KomgaContentType, itemId: string): string {
    return `provider:komga:${instanceId}:${contentType}:${itemId}`;
  }

  public static buildKomgaChapterId(instanceId: string, bookId: string): string {
    return `provider:komga:${instanceId}:book:${bookId}`;
  }

  public static parseProviderMangaId(mangaId: string): ParsedRemoteMangaId | null {
    const rawId = String(mangaId || '').trim();
    if (!rawId.startsWith('provider:')) {
      return null;
    }

    const segments = rawId.split(':');
    if (segments.length === 4 && segments[1] === REMOTE_PROVIDER_SUWAYOMI && segments[2] === 'manga' && segments[3].length > 0) {
      return {
        providerType: REMOTE_PROVIDER_SUWAYOMI,
        rawMangaId: segments[3]
      };
    }

    if (segments.length === 5 && segments[1] === REMOTE_PROVIDER_KOMGA && segments[2].length > 0 && segments[4].length > 0) {
      return {
        providerType: REMOTE_PROVIDER_KOMGA,
        rawMangaId: segments[4],
        instanceId: segments[2],
        contentType: RemoteLibraryMangaBridge.normalizeKomgaContentType(segments[3])
      };
    }

    return null;
  }

  public static parseProviderChapterId(chapterId: string): ParsedRemoteChapterId | null {
    const rawId = String(chapterId || '').trim();
    if (!rawId.startsWith('provider:')) {
      return null;
    }

    const segments = rawId.split(':');
    if (segments.length === 4 && segments[1] === REMOTE_PROVIDER_SUWAYOMI && segments[2] === 'chapter' && segments[3].length > 0) {
      return {
        providerType: REMOTE_PROVIDER_SUWAYOMI,
        rawChapterId: segments[3]
      };
    }

    if (segments.length === 5 && segments[1] === REMOTE_PROVIDER_KOMGA && segments[2].length > 0 && segments[3] === 'book' && segments[4].length > 0) {
      return {
        providerType: REMOTE_PROVIDER_KOMGA,
        rawChapterId: segments[4],
        instanceId: segments[2]
      };
    }

    return null;
  }

  public isRemoteProviderManga(manga: Manga): boolean {
    if (manga.sourceInfo?.providerType === REMOTE_PROVIDER_SUWAYOMI || manga.sourceInfo?.providerType === REMOTE_PROVIDER_KOMGA) {
      return true;
    }
    return RemoteLibraryMangaBridge.parseProviderMangaId(manga.id) !== null;
  }

  public async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      const store = await preferences.getPreferences(getContext(), REMOTE_LIBRARY_PREF_NAME);
      const cacheText = await store.get(REMOTE_LIBRARY_CACHE_KEY, '') as string;
      if (cacheText.length > 0) {
        const parsed = SafeUtils.parseObj<RemoteLibraryCachePayload>(cacheText);
        this.cacheData = {
          version: REMOTE_LIBRARY_CACHE_VERSION,
          updatedAt: parsed.updatedAt || 0,
          mangas: this.cloneMangaList(parsed.mangas || []),
          buckets: this.cloneCacheBuckets(parsed.buckets || [])
        };
        logger.info(TAG, `loaded remote library cache, count=${this.cacheData.mangas.length}, buckets=${this.cacheData.buckets.length}`);
      }
    } catch (error) {
      logger.warn(TAG, `initialize remote library cache failed: ${String(error)}`);
      this.cacheData = {
        version: REMOTE_LIBRARY_CACHE_VERSION,
        updatedAt: 0,
        mangas: [],
        buckets: []
      };
    }

    this.initialized = true;
  }

  public async getCachedLibraryManga(): Promise<Manga[]> {
    await this.initialize();
    const favoriteComicIds = await this.loadFavoriteComicIdSet();
    const activeSignatures = await this.resolveActiveProviderSignatures();
    this.migrateLegacyMangaToActiveBuckets(activeSignatures);
    const filteredManga = this.getFavoriteMangaFromActiveBuckets(activeSignatures, favoriteComicIds);

    this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
    this.cacheData.mangas = this.cloneMangaList(filteredManga);
    await this.persistCache();

    return this.cloneMangaList(filteredManga);
  }

  public async getCachedMangaById(mangaId: string): Promise<Manga | null> {
    await this.initialize();
    const activeSignatures = await this.resolveActiveProviderSignatures();
    this.migrateLegacyMangaToActiveBuckets(activeSignatures);
    const target = this.findMangaInActiveBuckets(mangaId, activeSignatures) || this.findMangaById(this.cacheData.mangas, mangaId);
    return target ? this.cloneManga(target) : null;
  }

  public async clearProviderCache(providerType: RemoteProviderType): Promise<void> {
    await this.initialize();
    const nextBuckets: RemoteProviderCacheBucket[] = [];
    for (let index = 0; index < this.cacheData.buckets.length; index++) {
      const bucket = this.cacheData.buckets[index];
      if (bucket.providerType !== providerType) {
        nextBuckets.push({
          providerType: bucket.providerType,
          signature: bucket.signature,
          updatedAt: bucket.updatedAt,
          mangas: this.cloneMangaList(bucket.mangas)
        });
      }
    }

    const nextMangas: Manga[] = [];
    for (let index = 0; index < this.cacheData.mangas.length; index++) {
      const manga = this.cacheData.mangas[index];
      if (!this.isMangaFromProvider(manga, providerType)) {
        nextMangas.push(this.cloneManga(manga));
      }
    }

    this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
    this.cacheData.updatedAt = Date.now();
    this.cacheData.buckets = nextBuckets;
    this.cacheData.mangas = nextMangas;
    await this.persistCache();
    logger.info(TAG, `cleared remote library provider cache: provider=${providerType}`);
  }

  public async clearKomgaInstanceCache(instanceId: string): Promise<void> {
    const normalizedInstanceId = String(instanceId || '').trim();
    if (normalizedInstanceId.length <= 0) {
      await this.clearProviderCache(REMOTE_PROVIDER_KOMGA);
      return;
    }

    await this.initialize();
    const nextBuckets: RemoteProviderCacheBucket[] = [];
    const instanceSignaturePart = `instance=${normalizedInstanceId}|`;
    for (let index = 0; index < this.cacheData.buckets.length; index++) {
      const bucket = this.cacheData.buckets[index];
      if (bucket.providerType === REMOTE_PROVIDER_KOMGA && bucket.signature.indexOf(instanceSignaturePart) >= 0) {
        continue;
      }
      nextBuckets.push({
        providerType: bucket.providerType,
        signature: bucket.signature,
        updatedAt: bucket.updatedAt,
        mangas: this.cloneMangaList(bucket.mangas)
      });
    }

    const nextMangas: Manga[] = [];
    for (let index = 0; index < this.cacheData.mangas.length; index++) {
      const manga = this.cacheData.mangas[index];
      if (!this.isMangaFromKomgaInstance(manga, normalizedInstanceId)) {
        nextMangas.push(this.cloneManga(manga));
      }
    }

    this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
    this.cacheData.updatedAt = Date.now();
    this.cacheData.buckets = nextBuckets;
    this.cacheData.mangas = nextMangas;
    await this.persistCache();
    logger.info(TAG, `cleared remote library Komga instance cache: instance=${normalizedInstanceId}`);
  }

  public async refreshAllLibraryManga(forceRefresh: boolean = false): Promise<Manga[]> {
    if (this.refreshInFlight !== null) {
      logger.debug(TAG, 'remote library refresh already running, reuse in-flight work');
      return await this.refreshInFlight;
    }

    const refreshWork = this.executeLibraryRefresh(forceRefresh);
    this.refreshInFlight = refreshWork;
    try {
      return await refreshWork;
    } finally {
      this.refreshInFlight = null;
    }
  }

  private async executeLibraryRefresh(forceRefresh: boolean): Promise<Manga[]> {
    await this.initialize();

    const favoriteComicIds = await this.loadFavoriteComicIdSet();
    const activeSignatures = await this.resolveActiveProviderSignatures();
    this.migrateLegacyMangaToActiveBuckets(activeSignatures);
    let workingList = this.getFavoriteMangaFromActiveBuckets(activeSignatures, favoriteComicIds);
    const hasRemoteFavorites = this.hasRemoteProviderFavorites(favoriteComicIds);
    const refreshedAt = Date.now();

    if (!hasRemoteFavorites) {
      this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
      this.cacheData.updatedAt = refreshedAt;
      this.cacheData.mangas = this.cloneMangaList(workingList);
      await this.persistCache();
      logger.info(TAG, 'skip remote library refresh: no remote favorites');
      return this.cloneMangaList(this.cacheData.mangas);
    }

    const suwayomiSignatures = this.collectNeededProviderSignatures(REMOTE_PROVIDER_SUWAYOMI, activeSignatures, favoriteComicIds);
    const komgaSignatures = this.collectNeededProviderSignatures(REMOTE_PROVIDER_KOMGA, activeSignatures, favoriteComicIds);
    const suwayomiFresh = this.areProviderBucketsFresh(suwayomiSignatures, refreshedAt);
    const komgaFresh = this.areProviderBucketsFresh(komgaSignatures, refreshedAt);

    if (!forceRefresh && suwayomiFresh && komgaFresh) {
      this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
      this.cacheData.mangas = this.cloneMangaList(workingList);
      await this.persistCache();
      logger.info(TAG, `use fresh remote library cache, count=${workingList.length}, suwayomiBuckets=${suwayomiSignatures.length}, komgaBuckets=${komgaSignatures.length}`);
      return this.cloneMangaList(workingList);
    }

    if (suwayomiSignatures.length > 0 && (forceRefresh || !suwayomiFresh)) {
      const suwayomiItems = await this.refreshSuwayomiLibrary(workingList, refreshedAt, favoriteComicIds);
      if (suwayomiItems !== null) {
        this.replaceProviderBuckets(suwayomiSignatures, suwayomiItems, refreshedAt, favoriteComicIds);
      }
    }

    if (komgaSignatures.length > 0 && (forceRefresh || !komgaFresh)) {
      const komgaItems = await this.refreshKomgaLibrary(workingList, refreshedAt, favoriteComicIds, komgaSignatures);
      if (komgaItems !== null) {
        this.replaceProviderBuckets(komgaSignatures, komgaItems, refreshedAt, favoriteComicIds);
      }
    }

    workingList = this.getFavoriteMangaFromActiveBuckets(activeSignatures, favoriteComicIds);
    this.cacheData.version = REMOTE_LIBRARY_CACHE_VERSION;
    this.cacheData.updatedAt = refreshedAt;
    this.cacheData.mangas = this.cloneMangaList(workingList);
    await this.persistCache();
    return this.cloneMangaList(this.cacheData.mangas);
  }

  public async loadRemoteMangaDetail(baseManga: Manga | null, mangaId: string): Promise<Manga | null> {
    await this.initialize();

    let seedManga: Manga | null = baseManga ? this.cloneManga(baseManga) : null;
    if (seedManga === null) {
      seedManga = await this.getCachedMangaById(mangaId);
    }

    const providerContext = this.resolveProviderContext(seedManga, mangaId);
    if (providerContext === null) {
      return null;
    }

    if (providerContext.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      await this.suwayomiExecutor.initialize();
      const detail = await this.suwayomiExecutor.getDetail(providerContext.rawMangaId);
      if (detail === null) {
        return null;
      }
      const result = this.convertSuwayomiDetailToManga(detail, seedManga, providerContext.rawMangaId);
      if (result.isFavorite) {
        await this.upsertCachedManga(result);
      }
      return this.cloneManga(result);
    }

    await this.komgaExecutor.initialize();
    const detail = await this.komgaExecutor.getDetail(
      providerContext.rawMangaId,
      providerContext.contentType,
      providerContext.instanceId
    );
    if (detail === null) {
      return null;
    }
    const result = this.convertKomgaDetailToManga(detail, seedManga, providerContext.instanceId, providerContext.contentType);
    if (result.isFavorite) {
      await this.upsertCachedManga(result);
    }
    return this.cloneManga(result);
  }

  public buildSuwayomiMangaFromDetail(detail: ComicDetailInfo, rawMangaId: string, baseManga: Manga | null = null): Manga {
    return this.cloneManga(this.convertSuwayomiDetailToManga(detail, baseManga, rawMangaId));
  }

  public buildKomgaMangaFromDetail(
    detail: ComicDetailInfo,
    instanceId: string,
    contentType: KomgaContentType,
    baseManga: Manga | null = null
  ): Manga {
    return this.cloneManga(this.convertKomgaDetailToManga(detail, baseManga, instanceId, contentType));
  }

  public async loadChapterPages(manga: Manga, chapter: MangaChapter): Promise<MangaPage[]> {
    const providerContext = this.resolveProviderContext(manga, manga.id);
    if (providerContext === null) {
      return [];
    }

    if (providerContext.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      await this.suwayomiExecutor.initialize();
      const rawChapterId = this.resolveRawChapterId(chapter);
      if (rawChapterId.length <= 0) {
        return [];
      }
      const pages = await this.suwayomiExecutor.getPages(rawChapterId);
      return this.convertSourcePagesToMangaPages(chapter.id, pages);
    }

    await this.komgaExecutor.initialize();
    const rawBookId = this.resolveRawChapterId(chapter);
    if (rawBookId.length <= 0) {
      return [];
    }
    const pages = await this.komgaExecutor.getPages(rawBookId, providerContext.instanceId);
    return this.convertSourcePagesToMangaPages(chapter.id, pages);
  }

  public async getRequestHeaders(manga: Manga): Promise<RequestHeaders> {
    const providerContext = this.resolveProviderContext(manga, manga.id);
    if (providerContext === null) {
      return {} as RequestHeaders;
    }

    if (providerContext.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      await this.suwayomiExecutor.initialize();
      return this.mapStandardHeadersToRequestHeaders(this.suwayomiExecutor.getImageHeaders());
    }

    await this.komgaExecutor.initialize();
    return this.mapStandardHeadersToRequestHeaders(this.komgaExecutor.getImageHeaders(providerContext.instanceId));
  }

  public async updateCachedReadingProgress(mangaId: string, chapterId: string, pageIndex: number, readDuration: number): Promise<void> {
    await this.initialize();

    const target = this.cacheData.mangas.find((item: Manga) => item.id === mangaId);
    if (!target) {
      return;
    }

    target.readingProgress.currentChapterId = chapterId;
    target.readingProgress.currentPageIndex = pageIndex;
    target.readingProgress.lastReadAt = Date.now();
    target.readingProgress.readingStatus = ReadingStatus.READING;
    target.readingProgress.totalReadingTime += (readDuration / 1000 / 60);
    await this.persistCache();
  }

  public async removeFromLibrary(manga: Manga): Promise<boolean> {
    const providerContext = this.resolveProviderContext(manga, manga.id);
    if (providerContext === null) {
      return false;
    }

    if (providerContext.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      await this.suwayomiExecutor.initialize();
      const success = await this.suwayomiExecutor.removeFromLibrary(providerContext.rawMangaId);
      if (success) {
        await this.removeCachedManga(manga.id);
      }
      return success;
    }

    return false;
  }

  public async upsertLocalLibraryManga(manga: Manga): Promise<void> {
    const nextManga = this.cloneManga(manga);
    nextManga.isFavorite = true;
    nextManga.addedToLibraryAt = nextManga.addedToLibraryAt && nextManga.addedToLibraryAt > 0
      ? nextManga.addedToLibraryAt
      : Date.now();
    nextManga.lastUpdatedAt = Date.now();
    await this.upsertCachedManga(nextManga);
  }

  public async removeLocalLibraryManga(mangaId: string): Promise<void> {
    await this.removeCachedManga(mangaId);
  }

  private async refreshSuwayomiLibrary(
    existingList: Manga[],
    refreshedAt: number,
    favoriteComicIds: Set<string>
  ): Promise<Manga[] | null> {
    try {
      await this.suwayomiExecutor.initialize();
      if (!this.suwayomiExecutor.isConfigured()) {
        return [];
      }

      const result: Manga[] = [];
      let offset = 0;
      let hasMore = true;

      while (hasMore) {
        const response = await this.suwayomiExecutor.getLibraryPaginated(-1, offset, SUWAYOMI_PAGE_SIZE, 'IN_LIBRARY_AT', 'DESC');
        const items = response.items || [];
        for (let index = 0; index < items.length; index++) {
          const info = items[index] as SuwayomiLibraryComicInfo;
          const syntheticId = RemoteLibraryMangaBridge.buildSuwayomiMangaId(info.id);
          const existing = this.findMangaById(existingList, syntheticId);
          const isFavorite = favoriteComicIds.has(syntheticId);
          result.push(this.convertSuwayomiLibraryComicToManga(info, existing, refreshedAt, isFavorite));
        }

        if (!response.hasMore || items.length <= 0) {
          hasMore = false;
        } else {
          offset += items.length;
        }
      }

      logger.info(TAG, `refreshed Suwayomi library, count=${result.length}`);
      return result;
    } catch (error) {
      logger.warn(TAG, `refresh Suwayomi library failed: ${String(error)}`);
      return null;
    }
  }

  private async refreshKomgaLibrary(
    existingList: Manga[],
    refreshedAt: number,
    favoriteComicIds: Set<string>,
    targetSignatures: RemoteProviderSignature[]
  ): Promise<Manga[] | null> {
    try {
      await this.komgaExecutor.initialize();
      if (!this.komgaExecutor.isConfigured()) {
        return [];
      }

      const result: Manga[] = [];
      const instances = this.komgaExecutor.getInstances();
      for (let instanceIndex = 0; instanceIndex < instances.length; instanceIndex++) {
        const instance = instances[instanceIndex];
        if (instance.enabled === false || !this.hasSignatureForInstance(targetSignatures, instance.id)) {
          continue;
        }

        for (let typeIndex = 0; typeIndex < KOMGA_CONTENT_TYPES.length; typeIndex++) {
          const contentType = KOMGA_CONTENT_TYPES[typeIndex];
          let page = 1;
          let hasMore = true;
          let guard = 0;

          while (hasMore && guard < KOMGA_GUARD_MAX_PAGES) {
            const response = await this.komgaExecutor.browse({
              instanceId: instance.id,
              contentType: contentType,
              browseMode: 'library',
              feedType: 'LATEST',
              page: page,
              query: '',
              filters: createDefaultKomgaBrowseFilters()
            });
            const items = response.items || [];
            for (let index = 0; index < items.length; index++) {
              const info = items[index] as KomgaLibraryComicInfo;
              const syntheticId = RemoteLibraryMangaBridge.buildKomgaMangaId(instance.id, contentType, info.id);
              const existing = this.findMangaById(existingList, syntheticId);
              const isFavorite = favoriteComicIds.has(syntheticId);
              result.push(this.convertKomgaLibraryComicToManga(info, existing, instance, contentType, refreshedAt, isFavorite));
            }

            hasMore = response.hasMore;
            page += 1;
            guard += 1;
          }
        }
      }

      logger.info(TAG, `refreshed Komga library, count=${result.length}`);
      return result;
    } catch (error) {
      logger.warn(TAG, `refresh Komga library failed: ${String(error)}`);
      return null;
    }
  }

  private resolveProviderContext(manga: Manga | null, mangaId: string): RemoteProviderContext | null {
    if (manga !== null && manga.sourceInfo?.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      const rawMangaId = manga.sourceInfo.providerItemId || this.extractRawMangaId(manga.id);
      if (rawMangaId.length > 0) {
        return {
          providerType: REMOTE_PROVIDER_SUWAYOMI,
          rawMangaId: rawMangaId,
          instanceId: '',
          contentType: 'SERIES'
        };
      }
    }

    if (manga !== null && manga.sourceInfo?.providerType === REMOTE_PROVIDER_KOMGA) {
      const rawMangaId = manga.sourceInfo.providerItemId || this.extractRawMangaId(manga.id);
      const instanceId = manga.sourceInfo.providerInstanceId || this.extractInstanceId(manga.id);
      const contentType = RemoteLibraryMangaBridge.normalizeKomgaContentType(
        manga.sourceInfo.providerContentType || this.extractKomgaContentType(manga.id)
      );
      if (rawMangaId.length > 0 && instanceId.length > 0) {
        return {
          providerType: REMOTE_PROVIDER_KOMGA,
          rawMangaId: rawMangaId,
          instanceId: instanceId,
          contentType: contentType
        };
      }
    }

    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    if (parsed === null) {
      return null;
    }

    return {
      providerType: parsed.providerType,
      rawMangaId: parsed.rawMangaId,
      instanceId: parsed.instanceId || '',
      contentType: parsed.contentType || 'SERIES'
    };
  }

  private extractRawMangaId(mangaId: string): string {
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    return parsed?.rawMangaId || '';
  }

  private extractInstanceId(mangaId: string): string {
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    return parsed?.instanceId || '';
  }

  private extractKomgaContentType(mangaId: string): string {
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    return parsed?.contentType || 'SERIES';
  }

  private resolveRawChapterId(chapter: MangaChapter): string {
    if (chapter.externalId && chapter.externalId.length > 0) {
      return chapter.externalId;
    }
    const parsed = RemoteLibraryMangaBridge.parseProviderChapterId(chapter.id);
    return parsed?.rawChapterId || '';
  }

  private convertSuwayomiLibraryComicToManga(
    info: SuwayomiLibraryComicInfo,
    existing: Manga | null,
    refreshedAt: number,
    isFavorite: boolean
  ): Manga {
    const syntheticId = RemoteLibraryMangaBridge.buildSuwayomiMangaId(info.id);
    const coverPath = this.resolvePreferredCoverPath(existing, info.coverUrl || '');
    return {
      id: syntheticId,
      title: info.title,
      alternativeTitles: existing ? existing.alternativeTitles.concat() : [],
      description: info.description || '',
      coverImagePath: coverPath,
      coverSourceType: this.isNetworkUrl(coverPath) ? ImageSourceType.NETWORK : ImageSourceType.LOCAL,
      status: StatusConverter.toMangaStatus(info.status),
      metadata: this.buildMetadata(info.author, info.tags || []),
      chapters: existing ? this.cloneChapters(existing.chapters) : [],
      readingProgress: existing ? this.cloneReadingProgress(existing.readingProgress) : this.createDefaultReadingProgress(),
      bookmarks: existing ? this.cloneBookmarks(existing.bookmarks) : [],
      readingSettings: existing ? this.cloneReadingSettings(existing.readingSettings) : this.cloneReadingSettings(DEFAULT_READING_SETTINGS),
      isFavorite: isFavorite,
      addedToLibraryAt: typeof info.inLibraryAt === 'number' && info.inLibraryAt > 0
        ? info.inLibraryAt
        : (existing?.addedToLibraryAt || refreshedAt),
      lastUpdatedAt: typeof info.lastFetchedAt === 'number' && info.lastFetchedAt > 0
        ? info.lastFetchedAt
        : (existing?.lastUpdatedAt || refreshedAt),
      sourceInfo: {
        sourceName: 'Suwayomi',
        sourceUrl: info.url || this.suwayomiExecutor.getServerUrl(),
        sourceId: 'provider_suwayomi',
        externalId: info.id,
        sourceLanguage: 'multi',
        requiresLogin: false,
        providerType: REMOTE_PROVIDER_SUWAYOMI,
        providerItemId: info.id
      },
      contentType: 'manga',
      isNSFW: existing?.isNSFW,
      isPrivate: false
    };
  }

  private convertKomgaLibraryComicToManga(
    info: KomgaLibraryComicInfo,
    existing: Manga | null,
    instance: KomgaInstanceConfig,
    contentType: KomgaContentType,
    refreshedAt: number,
    isFavorite: boolean
  ): Manga {
    const syntheticId = RemoteLibraryMangaBridge.buildKomgaMangaId(instance.id, contentType, info.id);
    const coverPath = this.resolvePreferredCoverPath(existing, info.coverUrl || '');
    return {
      id: syntheticId,
      title: info.title,
      alternativeTitles: existing ? existing.alternativeTitles.concat() : [],
      description: info.description || '',
      coverImagePath: coverPath,
      coverSourceType: this.isNetworkUrl(coverPath) ? ImageSourceType.NETWORK : ImageSourceType.LOCAL,
      status: StatusConverter.toMangaStatus(info.status),
      metadata: this.buildMetadata(info.author, info.tags || []),
      chapters: existing ? this.cloneChapters(existing.chapters) : [],
      readingProgress: existing ? this.cloneReadingProgress(existing.readingProgress) : this.createDefaultReadingProgress(),
      bookmarks: existing ? this.cloneBookmarks(existing.bookmarks) : [],
      readingSettings: existing ? this.cloneReadingSettings(existing.readingSettings) : this.cloneReadingSettings(DEFAULT_READING_SETTINGS),
      isFavorite: isFavorite,
      addedToLibraryAt: existing?.addedToLibraryAt || refreshedAt,
      lastUpdatedAt: existing?.lastUpdatedAt || refreshedAt,
      sourceInfo: {
        sourceName: `Komga ${instance.displayName}`,
        sourceUrl: info.url || this.komgaExecutor.getServerUrl(instance.id),
        sourceId: 'provider_komga',
        externalId: info.id,
        sourceLanguage: info.language || 'multi',
        requiresLogin: true,
        providerType: REMOTE_PROVIDER_KOMGA,
        providerItemId: info.id,
        providerInstanceId: instance.id,
        providerContentType: contentType
      },
      contentType: 'manga',
      isNSFW: existing?.isNSFW,
      isPrivate: false
    };
  }

  private convertSuwayomiDetailToManga(detail: ComicDetailInfo, baseManga: Manga | null, rawMangaId: string): Manga {
    const seed = baseManga || this.findMangaById(this.cacheData.mangas, RemoteLibraryMangaBridge.buildSuwayomiMangaId(rawMangaId));
    const manga = this.convertSuwayomiLibraryComicToManga({
      id: detail.id,
      title: detail.title,
      author: detail.author,
      coverUrl: detail.coverUrl,
      description: detail.description,
      status: detail.status,
      tags: detail.tags,
      url: detail.url,
      lastFetchedAt: detail.updateTime
    }, seed, Date.now(), seed?.isFavorite === true);
    manga.chapters = this.convertSuwayomiChapters(detail.chapters || []);
    return manga;
  }

  private convertKomgaDetailToManga(
    detail: ComicDetailInfo,
    baseManga: Manga | null,
    instanceId: string,
    contentType: KomgaContentType
  ): Manga {
    const seed = baseManga || this.findMangaById(
      this.cacheData.mangas,
      RemoteLibraryMangaBridge.buildKomgaMangaId(instanceId, contentType, detail.id)
    );
    const manga = this.convertKomgaLibraryComicToManga({
      id: detail.id,
      title: detail.title,
      author: detail.author,
      coverUrl: detail.coverUrl,
      description: detail.description,
      status: detail.status,
      tags: detail.tags,
      url: detail.url,
      instanceId: instanceId
    }, seed, this.resolveKomgaInstance(instanceId), contentType, Date.now(), seed?.isFavorite === true);
    manga.chapters = this.convertKomgaChapters(detail.chapters || [], instanceId);
    return manga;
  }

  private convertSuwayomiChapters(chapters: ChapterInfo[]): MangaChapter[] {
    const result: MangaChapter[] = [];
    for (let index = 0; index < chapters.length; index++) {
      const chapter = chapters[index];
      result.push({
        id: RemoteLibraryMangaBridge.buildSuwayomiChapterId(chapter.id),
        externalId: chapter.id,
        title: chapter.title,
        chapterNumber: typeof chapter.chapterNumber === 'number' && chapter.chapterNumber > 0 ? chapter.chapterNumber : index + 1,
        pages: [],
        totalPages: chapter.pageCount || 0,
        publishDate: chapter.updateTime || Date.now(),
        language: 'multi',
        scanlationGroup: '',
        isDownloaded: false,
        downloadStatus: DownloadStatus.PENDING,
        downloadProgress: 0,
        localPath: undefined
      });
    }
    return result;
  }

  private convertKomgaChapters(chapters: ChapterInfo[], instanceId: string): MangaChapter[] {
    const result: MangaChapter[] = [];
    for (let index = 0; index < chapters.length; index++) {
      const chapter = chapters[index];
      result.push({
        id: RemoteLibraryMangaBridge.buildKomgaChapterId(instanceId, chapter.id),
        externalId: chapter.id,
        title: chapter.title,
        chapterNumber: typeof chapter.chapterNumber === 'number' && chapter.chapterNumber > 0 ? chapter.chapterNumber : index + 1,
        pages: [],
        totalPages: chapter.pageCount || 0,
        publishDate: chapter.updateTime || Date.now(),
        language: 'multi',
        scanlationGroup: '',
        isDownloaded: false,
        downloadStatus: DownloadStatus.PENDING,
        downloadProgress: 0,
        localPath: undefined
      });
    }
    return result;
  }

  private convertSourcePagesToMangaPages(chapterId: string, pages: PageInfo[]): MangaPage[] {
    const result: MangaPage[] = [];
    for (let index = 0; index < pages.length; index++) {
      const page = pages[index];
      result.push({
        id: `${chapterId}_page_${index}`,
        index: index,
        sourceType: ImageSourceType.NETWORK,
        imagePath: page.url,
        imageUrl: page.url,
        width: page.width,
        height: page.height,
        fileSize: 0,
        isLoaded: false
      });
    }
    return result;
  }

  private mapStandardHeadersToRequestHeaders(headers: Record<string, string>): RequestHeaders {
    const result: RequestHeaders = {};

    if (headers['Authorization']) {
      result.authorization = headers['Authorization'];
    }
    if (headers['User-Agent']) {
      result.userAgent = headers['User-Agent'];
    }
    if (headers['Referer']) {
      result.referer = headers['Referer'];
    }
    if (headers['Origin']) {
      result.origin = headers['Origin'];
    }
    if (headers['Cookie']) {
      result.cookie = headers['Cookie'];
    }
    if (headers['Accept']) {
      result.accept = headers['Accept'];
    }
    if (headers['Accept-Language']) {
      result.acceptLanguage = headers['Accept-Language'];
    }
    if (headers['Cache-Control']) {
      result.cacheControl = headers['Cache-Control'];
    }
    if (headers['Pragma']) {
      result.pragma = headers['Pragma'];
    }
    if (headers['Sec-Fetch-Dest']) {
      result.secFetchDest = headers['Sec-Fetch-Dest'];
    }
    if (headers['Sec-Fetch-Mode']) {
      result.secFetchMode = headers['Sec-Fetch-Mode'];
    }
    if (headers['Sec-Fetch-Site']) {
      result.secFetchSite = headers['Sec-Fetch-Site'];
    }
    this.appendExtraRequestHeader(result, 'X-API-Key', headers['X-API-Key']);
    this.appendExtraRequestHeader(result, 'X-Auth-Token', headers['X-Auth-Token']);

    return result;
  }

  private appendExtraRequestHeader(target: RequestHeaders, name: string, value: string | undefined): void {
    if (!value || value.length <= 0) {
      return;
    }
    const nextEntry: RequestHeaderEntry = {
      name: name,
      value: value
    };
    target.extraHeaders = target.extraHeaders
      ? target.extraHeaders.concat([nextEntry])
      : [nextEntry];
  }

  private buildMetadata(authorText: string | undefined, tags: string[]): MangaMetadata {
    const authors: string[] = [];
    if (authorText && authorText.trim().length > 0) {
      authors.push(authorText.trim());
    }
    return {
      authors: authors,
      artists: [],
      genres: tags ? tags.concat() : [],
      themes: [],
      demographics: []
    };
  }

  private createDefaultReadingProgress(): ReadingProgress {
    return {
      currentChapterId: '',
      currentPageIndex: 0,
      readingStatus: ReadingStatus.UNREAD,
      totalReadingTime: 0,
      lastReadAt: 0,
      readingPercentage: 0
    };
  }

  private async loadFavoriteComicIdSet(): Promise<Set<string>> {
    const result = new Set<string>();
    try {
      const favorites: FavoriteInfo[] = await this.dataManager.getUserFavorites('default_user');
      for (let index = 0; index < favorites.length; index++) {
        const comicId = String(favorites[index].comicId || '').trim();
        if (comicId.length > 0) {
          result.add(comicId);
        }
      }
    } catch (error) {
      logger.warn(TAG, `load favorite comic ids failed: ${String(error)}`);
    }
    return result;
  }

  private hasRemoteProviderFavorites(favoriteComicIds: Set<string>): boolean {
    let result = false;
    favoriteComicIds.forEach((comicId: string): void => {
      if (result) {
        return;
      }
      result = RemoteLibraryMangaBridge.parseProviderMangaId(comicId) !== null;
    });
    return result;
  }

  private async resolveActiveProviderSignatures(): Promise<RemoteProviderSignature[]> {
    const result: RemoteProviderSignature[] = [];

    try {
      await this.suwayomiExecutor.initialize();
      if (this.suwayomiExecutor.isConfigured()) {
        const config = this.suwayomiExecutor.getConfig();
        const signature = this.buildSuwayomiSignature(
          this.suwayomiExecutor.getServerUrl() || config.serverUrl,
          config.useAuth,
          config.username
        );
        if (signature.length > 0) {
          result.push({
            providerType: REMOTE_PROVIDER_SUWAYOMI,
            signature: signature,
            instanceId: ''
          });
        }
      }
    } catch (error) {
      logger.warn(TAG, `resolve Suwayomi cache signature failed: ${String(error)}`);
    }

    try {
      await this.komgaExecutor.initialize();
      const instances = this.komgaExecutor.getInstances();
      for (let index = 0; index < instances.length; index++) {
        const instance = instances[index];
        if (instance.enabled === false || instance.serverUrl.trim().length <= 0) {
          continue;
        }
        const signature = this.buildKomgaSignature(instance);
        if (signature.length > 0) {
          result.push({
            providerType: REMOTE_PROVIDER_KOMGA,
            signature: signature,
            instanceId: instance.id
          });
        }
      }
    } catch (error) {
      logger.warn(TAG, `resolve Komga cache signatures failed: ${String(error)}`);
    }

    return result;
  }

  private buildSuwayomiSignature(serverUrl: string, useAuth: boolean, username: string): string {
    const normalizedServerUrl = this.normalizeCacheServerUrl(serverUrl);
    if (normalizedServerUrl.length <= 0) {
      return '';
    }
    const authMode = useAuth ? 'BASIC' : 'NONE';
    const normalizedUsername = useAuth ? username.trim().toLowerCase() : '';
    return `suwayomi|server=${normalizedServerUrl}|auth=${authMode}|user=${normalizedUsername}`;
  }

  private buildKomgaSignature(instance: KomgaInstanceConfig): string {
    const normalizedServerUrl = this.normalizeCacheServerUrl(this.komgaExecutor.getServerUrl(instance.id) || instance.serverUrl);
    if (normalizedServerUrl.length <= 0) {
      return '';
    }
    const authMode = instance.authMode || 'NONE';
    const normalizedUsername = authMode === 'BASIC' ? instance.username.trim().toLowerCase() : '';
    const apiKeyHash = authMode === 'API_KEY' ? this.shortStableHash(instance.apiKey.trim()) : '';
    return `komga|instance=${instance.id}|server=${normalizedServerUrl}|auth=${authMode}|user=${normalizedUsername}|key=${apiKeyHash}`;
  }

  private normalizeCacheServerUrl(serverUrl: string): string {
    let normalized = String(serverUrl || '').trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  private shortStableHash(value: string): string {
    if (value.length <= 0) {
      return '';
    }

    let hash: number = 0;
    for (let index = 0; index < value.length; index++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(index);
      hash = hash & hash;
    }
    return Math.abs(hash).toString(36);
  }

  private collectNeededProviderSignatures(
    providerType: RemoteProviderType,
    activeSignatures: RemoteProviderSignature[],
    favoriteComicIds: Set<string>
  ): RemoteProviderSignature[] {
    const result: RemoteProviderSignature[] = [];
    favoriteComicIds.forEach((comicId: string): void => {
      const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(comicId);
      if (parsed === null || parsed.providerType !== providerType) {
        return;
      }

      const signature = this.findActiveSignatureForParsedMangaId(parsed, activeSignatures);
      if (signature !== null && !this.includesSignature(result, signature)) {
        result.push(signature);
      }
    });
    return result;
  }

  private areProviderBucketsFresh(signatures: RemoteProviderSignature[], now: number): boolean {
    for (let index = 0; index < signatures.length; index++) {
      const signature = signatures[index];
      const bucket = this.findCacheBucket(signature.providerType, signature.signature);
      if (bucket === null || bucket.updatedAt <= 0 || now - bucket.updatedAt >= REMOTE_LIBRARY_REFRESH_TTL_MS) {
        return false;
      }
    }
    return true;
  }

  private migrateLegacyMangaToActiveBuckets(activeSignatures: RemoteProviderSignature[]): void {
    for (let index = 0; index < this.cacheData.mangas.length; index++) {
      const manga = this.cacheData.mangas[index];
      const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
      if (parsed === null) {
        continue;
      }

      const signature = this.findActiveSignatureForParsedMangaId(parsed, activeSignatures);
      if (signature === null) {
        continue;
      }

      const bucket = this.ensureCacheBucket(signature.providerType, signature.signature, this.cacheData.updatedAt);
      this.upsertMangaIntoBucket(bucket, manga);
    }
  }

  private getFavoriteMangaFromActiveBuckets(activeSignatures: RemoteProviderSignature[], favoriteComicIds: Set<string>): Manga[] {
    const result: Manga[] = [];
    const seenIds: Set<string> = new Set<string>();
    for (let index = 0; index < this.cacheData.buckets.length; index++) {
      const bucket = this.cacheData.buckets[index];
      if (!this.includesBucketSignature(activeSignatures, bucket.providerType, bucket.signature)) {
        continue;
      }
      for (let mangaIndex = 0; mangaIndex < bucket.mangas.length; mangaIndex++) {
        const manga = bucket.mangas[mangaIndex];
        if (manga.isFavorite && favoriteComicIds.has(manga.id) && !seenIds.has(manga.id)) {
          result.push(this.cloneManga(manga));
          seenIds.add(manga.id);
        }
      }
    }
    return result;
  }

  private findMangaInActiveBuckets(mangaId: string, activeSignatures: RemoteProviderSignature[]): Manga | null {
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(mangaId);
    if (parsed === null) {
      return null;
    }

    const signature = this.findActiveSignatureForParsedMangaId(parsed, activeSignatures);
    if (signature === null) {
      return null;
    }

    const bucket = this.findCacheBucket(signature.providerType, signature.signature);
    if (bucket === null) {
      return null;
    }
    return this.findMangaById(bucket.mangas, mangaId);
  }

  private replaceProviderBuckets(
    targetSignatures: RemoteProviderSignature[],
    nextItems: Manga[],
    refreshedAt: number,
    favoriteComicIds: Set<string>
  ): void {
    for (let signatureIndex = 0; signatureIndex < targetSignatures.length; signatureIndex++) {
      const targetSignature = targetSignatures[signatureIndex];
      const bucket = this.ensureCacheBucket(targetSignature.providerType, targetSignature.signature, refreshedAt);
      const nextIds: Set<string> = new Set<string>();
      const nextBucketItems: Manga[] = [];

      for (let itemIndex = 0; itemIndex < nextItems.length; itemIndex++) {
        const item = nextItems[itemIndex];
        if (!favoriteComicIds.has(item.id) || !this.mangaMatchesSignature(item, targetSignature)) {
          continue;
        }
        nextIds.add(item.id);
        nextBucketItems.push(this.cloneManga(item));
      }

      for (let existingIndex = 0; existingIndex < bucket.mangas.length; existingIndex++) {
        const existing = bucket.mangas[existingIndex];
        if (existing.isFavorite && favoriteComicIds.has(existing.id) && !nextIds.has(existing.id)) {
          nextBucketItems.push(this.cloneManga(existing));
        }
      }

      bucket.updatedAt = refreshedAt;
      bucket.mangas = nextBucketItems;
    }
  }

  private mangaMatchesSignature(manga: Manga, signature: RemoteProviderSignature): boolean {
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
    if (parsed === null || parsed.providerType !== signature.providerType) {
      return false;
    }
    if (signature.providerType === REMOTE_PROVIDER_SUWAYOMI) {
      return true;
    }
    return (parsed.instanceId || '') === signature.instanceId;
  }

  private findActiveSignatureForParsedMangaId(
    parsed: ParsedRemoteMangaId,
    activeSignatures: RemoteProviderSignature[]
  ): RemoteProviderSignature | null {
    for (let index = 0; index < activeSignatures.length; index++) {
      const signature = activeSignatures[index];
      if (signature.providerType !== parsed.providerType) {
        continue;
      }
      if (parsed.providerType === REMOTE_PROVIDER_SUWAYOMI) {
        return signature;
      }
      if (signature.instanceId === (parsed.instanceId || '')) {
        return signature;
      }
    }
    return null;
  }

  private includesSignature(signatures: RemoteProviderSignature[], target: RemoteProviderSignature): boolean {
    for (let index = 0; index < signatures.length; index++) {
      if (signatures[index].providerType === target.providerType && signatures[index].signature === target.signature) {
        return true;
      }
    }
    return false;
  }

  private includesBucketSignature(signatures: RemoteProviderSignature[], providerType: RemoteProviderType, signature: string): boolean {
    for (let index = 0; index < signatures.length; index++) {
      if (signatures[index].providerType === providerType && signatures[index].signature === signature) {
        return true;
      }
    }
    return false;
  }

  private hasSignatureForInstance(signatures: RemoteProviderSignature[], instanceId: string): boolean {
    for (let index = 0; index < signatures.length; index++) {
      if (signatures[index].providerType === REMOTE_PROVIDER_KOMGA && signatures[index].instanceId === instanceId) {
        return true;
      }
    }
    return false;
  }

  private findCacheBucket(providerType: RemoteProviderType, signature: string): RemoteProviderCacheBucket | null {
    for (let index = 0; index < this.cacheData.buckets.length; index++) {
      const bucket = this.cacheData.buckets[index];
      if (bucket.providerType === providerType && bucket.signature === signature) {
        return bucket;
      }
    }
    return null;
  }

  private ensureCacheBucket(providerType: RemoteProviderType, signature: string, updatedAt: number): RemoteProviderCacheBucket {
    const existing = this.findCacheBucket(providerType, signature);
    if (existing !== null) {
      return existing;
    }

    const nextBucket: RemoteProviderCacheBucket = {
      providerType: providerType,
      signature: signature,
      updatedAt: updatedAt,
      mangas: []
    };
    this.cacheData.buckets.push(nextBucket);
    return nextBucket;
  }

  private upsertMangaIntoBucket(bucket: RemoteProviderCacheBucket, manga: Manga): void {
    for (let index = 0; index < bucket.mangas.length; index++) {
      if (bucket.mangas[index].id === manga.id) {
        bucket.mangas[index] = this.cloneManga(manga);
        return;
      }
    }
    bucket.mangas.push(this.cloneManga(manga));
  }

  private resolvePreferredCoverPath(existing: Manga | null, fallbackCoverPath: string): string {
    const existingCoverPath = String(existing?.coverImagePath || '').trim();
    if (existingCoverPath.length > 0 && !this.isNetworkUrl(existingCoverPath)) {
      const normalizedExistingCoverPath = existingCoverPath.startsWith('file://')
        ? existingCoverPath.substring('file://'.length)
        : existingCoverPath;
      let accessError: string = '';
      try {
        if (normalizedExistingCoverPath.length > 0 && SafeFileUtils.accessSync(normalizedExistingCoverPath)) {
          return existingCoverPath;
        }
      } catch (error) {
        accessError = String(error);
      }

      if (normalizedExistingCoverPath.length > 0) {
        if (accessError.length > 0) {
          logger.warn(TAG, `drop stale remote library local cover path: path=${normalizedExistingCoverPath}, error=${accessError}`);
        } else {
          logger.warn(TAG, `drop stale remote library local cover path: path=${normalizedExistingCoverPath}`);
        }
      }
    }
    return fallbackCoverPath;
  }

  private isNetworkUrl(path: string): boolean {
    const normalizedPath = String(path || '').trim();
    if (normalizedPath.length <= 0) {
      return false;
    }
    return normalizedPath.startsWith('http://') || normalizedPath.startsWith('https://');
  }

  private resolveKomgaInstance(instanceId: string): KomgaInstanceConfig {
    const instances = this.komgaExecutor.getInstances();
    for (let index = 0; index < instances.length; index++) {
      if (instances[index].id === instanceId) {
        return instances[index];
      }
    }

    const current = this.komgaExecutor.getCurrentInstance();
    if (current !== null) {
      return current;
    }

    return {
      id: instanceId,
      displayName: 'Komga',
      serverUrl: this.komgaExecutor.getServerUrl(instanceId),
      authMode: 'NONE',
      username: '',
      password: '',
      apiKey: '',
      defaultLibraryIds: [],
      chapterTitleTemplate: '',
      enabled: true
    };
  }

  private async upsertCachedManga(manga: Manga): Promise<void> {
    await this.initialize();

    const activeSignatures = await this.resolveActiveProviderSignatures();
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
    if (parsed !== null) {
      const signature = this.findActiveSignatureForParsedMangaId(parsed, activeSignatures);
      if (signature !== null) {
        const now = Date.now();
        const bucket = this.ensureCacheBucket(signature.providerType, signature.signature, now);
        if (bucket.updatedAt <= 0) {
          bucket.updatedAt = now;
        }
        this.upsertMangaIntoBucket(bucket, manga);
      }
    }

    let replaced = false;
    for (let index = 0; index < this.cacheData.mangas.length; index++) {
      if (this.cacheData.mangas[index].id === manga.id) {
        this.cacheData.mangas[index] = this.cloneManga(manga);
        replaced = true;
        break;
      }
    }

    if (!replaced) {
      this.cacheData.mangas.push(this.cloneManga(manga));
    }

    await this.persistCache();
  }

  private async removeCachedManga(mangaId: string): Promise<void> {
    await this.initialize();
    for (let bucketIndex = 0; bucketIndex < this.cacheData.buckets.length; bucketIndex++) {
      const bucket = this.cacheData.buckets[bucketIndex];
      for (let index = bucket.mangas.length - 1; index >= 0; index--) {
        if (bucket.mangas[index].id === mangaId) {
          bucket.mangas.splice(index, 1);
        }
      }
    }
    for (let index = this.cacheData.mangas.length - 1; index >= 0; index--) {
      if (this.cacheData.mangas[index].id === mangaId) {
        this.cacheData.mangas.splice(index, 1);
      }
    }
    await this.persistCache();
  }

  private async persistCache(): Promise<void> {
    try {
      const store = await preferences.getPreferences(getContext(), REMOTE_LIBRARY_PREF_NAME);
      const payload: RemoteLibraryCacheData = {
        version: REMOTE_LIBRARY_CACHE_VERSION,
        updatedAt: this.cacheData.updatedAt,
        mangas: this.cloneMangaList(this.cacheData.mangas),
        buckets: this.cloneCacheBuckets(this.cacheData.buckets)
      };
      await store.put(REMOTE_LIBRARY_CACHE_KEY, JSON.stringify(payload));
      await store.flush();
    } catch (error) {
      logger.warn(TAG, `persist remote library cache failed: ${String(error)}`);
    }
  }

  private findMangaById(items: Manga[], mangaId: string): Manga | null {
    for (let index = 0; index < items.length; index++) {
      if (items[index].id === mangaId) {
        return items[index];
      }
    }
    return null;
  }

  private isMangaFromProvider(manga: Manga, providerType: RemoteProviderType): boolean {
    if (manga.sourceInfo?.providerType === providerType) {
      return true;
    }
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
    return parsed !== null && parsed.providerType === providerType;
  }

  private isMangaFromKomgaInstance(manga: Manga, instanceId: string): boolean {
    if (manga.sourceInfo?.providerType === REMOTE_PROVIDER_KOMGA && manga.sourceInfo.providerInstanceId === instanceId) {
      return true;
    }
    const parsed = RemoteLibraryMangaBridge.parseProviderMangaId(manga.id);
    return parsed !== null && parsed.providerType === REMOTE_PROVIDER_KOMGA && (parsed.instanceId || '') === instanceId;
  }

  private cloneCacheBuckets(buckets: RemoteProviderCacheBucket[]): RemoteProviderCacheBucket[] {
    const result: RemoteProviderCacheBucket[] = [];
    for (let index = 0; index < buckets.length; index++) {
      const bucket = buckets[index];
      result.push({
        providerType: bucket.providerType,
        signature: bucket.signature,
        updatedAt: bucket.updatedAt || 0,
        mangas: this.cloneMangaList(bucket.mangas || [])
      });
    }
    return result;
  }

  private cloneMangaList(items: Manga[]): Manga[] {
    const result: Manga[] = [];
    for (let index = 0; index < items.length; index++) {
      result.push(this.cloneManga(items[index]));
    }
    return result;
  }

  private cloneManga(manga: Manga): Manga {
    return {
      id: manga.id,
      title: manga.title,
      alternativeTitles: manga.alternativeTitles ? manga.alternativeTitles.concat() : [],
      description: manga.description,
      coverImagePath: manga.coverImagePath,
      coverSourceType: manga.coverSourceType,
      status: manga.status,
      metadata: this.cloneMetadata(manga.metadata),
      chapters: this.cloneChapters(manga.chapters),
      readingProgress: this.cloneReadingProgress(manga.readingProgress),
      bookmarks: this.cloneBookmarks(manga.bookmarks),
      readingSettings: this.cloneReadingSettings(manga.readingSettings),
      isFavorite: manga.isFavorite,
      addedToLibraryAt: manga.addedToLibraryAt,
      lastUpdatedAt: manga.lastUpdatedAt,
      sourceInfo: manga.sourceInfo ? this.cloneSourceInfo(manga.sourceInfo) : undefined,
      contentType: manga.contentType,
      isNSFW: manga.isNSFW,
      isPrivate: manga.isPrivate
    };
  }

  private cloneMetadata(metadata: MangaMetadata): MangaMetadata {
    return {
      authors: metadata.authors ? metadata.authors.concat() : [],
      artists: metadata.artists ? metadata.artists.concat() : [],
      genres: metadata.genres ? metadata.genres.concat() : [],
      themes: metadata.themes ? metadata.themes.concat() : [],
      demographics: metadata.demographics ? metadata.demographics.concat() : [],
      contentRating: metadata.contentRating,
      publicationYear: metadata.publicationYear,
      publisher: metadata.publisher,
      serialization: metadata.serialization
    };
  }

  private cloneReadingProgress(progress: ReadingProgress): ReadingProgress {
    return {
      currentChapterId: progress.currentChapterId,
      currentPageIndex: progress.currentPageIndex,
      readingStatus: progress.readingStatus,
      totalReadingTime: progress.totalReadingTime,
      lastReadAt: progress.lastReadAt,
      readingPercentage: progress.readingPercentage
    };
  }

  private cloneReadingSettings(settings: ReadingSettings): ReadingSettings {
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      doublePageVerticalDirection: settings.doublePageVerticalDirection,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin,
      webtoonRightMargin: settings.webtoonRightMargin,
      webtoonMarginSync: settings.webtoonMarginSync
    };
  }

  private cloneBookmarks(bookmarks: MangaBookmark[]): MangaBookmark[] {
    const result: MangaBookmark[] = [];
    for (let index = 0; index < bookmarks.length; index++) {
      const bookmark = bookmarks[index];
      result.push({
        id: bookmark.id,
        chapterId: bookmark.chapterId,
        pageIndex: bookmark.pageIndex,
        title: bookmark.title,
        createdAt: bookmark.createdAt,
        note: bookmark.note
      });
    }
    return result;
  }

  private cloneChapters(chapters: MangaChapter[]): MangaChapter[] {
    const result: MangaChapter[] = [];
    for (let index = 0; index < chapters.length; index++) {
      const chapter = chapters[index];
      result.push({
        id: chapter.id,
        externalId: chapter.externalId,
        title: chapter.title,
        chapterNumber: chapter.chapterNumber,
        pages: this.clonePages(chapter.pages),
        totalPages: chapter.totalPages,
        publishDate: chapter.publishDate,
        language: chapter.language,
        scanlationGroup: chapter.scanlationGroup,
        isDownloaded: chapter.isDownloaded,
        downloadStatus: chapter.downloadStatus,
        downloadProgress: chapter.downloadProgress,
        localPath: chapter.localPath
      });
    }
    return result;
  }

  private clonePages(pages: MangaPage[]): MangaPage[] {
    const result: MangaPage[] = [];
    for (let index = 0; index < pages.length; index++) {
      const page = pages[index];
      result.push({
        id: page.id,
        index: page.index,
        sourceType: page.sourceType,
        imagePath: page.imagePath,
        imageUrl: page.imageUrl,
        localPath: page.localPath,
        width: page.width,
        height: page.height,
        fileSize: page.fileSize,
        isLoaded: page.isLoaded,
        errorMessage: page.errorMessage,
        priority: page.priority
      });
    }
    return result;
  }

  private cloneSourceInfo(sourceInfo: MangaSourceInfo): MangaSourceInfo {
    return {
      sourceName: sourceInfo.sourceName,
      sourceUrl: sourceInfo.sourceUrl,
      sourceId: sourceInfo.sourceId,
      externalId: sourceInfo.externalId,
      sourceLanguage: sourceInfo.sourceLanguage,
      requiresLogin: sourceInfo.requiresLogin,
      apiVersion: sourceInfo.apiVersion,
      isNSFW: sourceInfo.isNSFW,
      providerType: sourceInfo.providerType,
      providerItemId: sourceInfo.providerItemId,
      providerInstanceId: sourceInfo.providerInstanceId,
      providerContentType: sourceInfo.providerContentType
    };
  }

  private static normalizeKomgaContentType(rawType: string | undefined): KomgaContentType {
    if (rawType === 'BOOKS') {
      return 'BOOKS';
    }
    if (rawType === 'READLISTS') {
      return 'READLISTS';
    }
    return 'SERIES';
  }
}
